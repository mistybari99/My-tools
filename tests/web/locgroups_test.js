// Location groups (UI only, no browser): Main Showroom, Branch, Production House, Warehouse, Unclassified.
// Every fixture is a neutral test_* place. Run: node locgroups_test.js <abs tests/web dir>
const _P = require('./_paths');
const fs = require('fs'), path = require('path');
const src = fs.readFileSync(path.join(_P.WEB_DIR, 'locgroups.js'), 'utf8');
global.window = {};
new Function('window', 'document', src)(global.window, undefined);
const G = global.window.BOS.locGroups;

let fails = 0;
const ok = (c, m) => { if (!c) { fails++; console.log('FAIL: ' + m); } else console.log('PASS: ' + m); };

const P = [
  { id: 1, code: 'test_main', kind: 'showroom', hub_functions: true, name_en: 'test main' },
  { id: 2, code: 'test_branch_a', kind: 'showroom', hub_functions: false, name_en: 'test branch a' },
  { id: 3, code: 'test_branch_b', kind: 'showroom', name_en: 'test branch b', unit_kind: 'branch' },
  { id: 4, code: 'test_fac_a', kind: 'factory', hub_functions: false, name_en: 'test factory a' },
  { id: 5, code: 'test_fac_b', kind: 'factory', name_en: 'test factory b' },
  { id: 6, code: 'test_gd', kind: 'godown', name_en: 'test godown' },
  { id: 7, code: 'test_hub', kind: 'hub', name_en: 'test hub' },
  { id: 8, code: 'test_none', kind: null, name_en: 'test no kind' },
  { id: 9, code: 'test_showroom_unknown', kind: 'showroom', name_en: 'test showroom without the flag' },
];

// 1. classification from existing fields only
ok(G.classify(P[0]) === 'main', 'a showroom with hub_functions is the Main Showroom');
ok(G.classify(P[1]) === 'branch', 'a showroom without hub_functions is a Branch');
ok(G.classify(P[2]) === 'branch', 'a showroom in a branch unit (no hub flag) is a Branch');
ok(G.classify(P[3]) === 'production' && G.classify(P[4]) === 'production', 'factories are Production House');
ok(G.classify(P[5]) === 'warehouse', 'godowns are Warehouse');
ok(G.classify(P[6]) === 'unclassified' && G.classify(P[7]) === 'unclassified', 'hub, no kind: Unclassified (never guessed)');
ok(G.classify(P[8]) === 'unclassified', 'a showroom with no hub flag and no branch unit: Unclassified');
ok(G.classify(null) === 'unclassified' && G.classify(undefined) === 'unclassified', 'no place: Unclassified');

// 2. the groups come in the order of the owner: Main Showroom, Branch, Production House, Warehouse, Unclassified
const g = G.grouped(P);
ok(JSON.stringify(g.map((x) => x.key)) === JSON.stringify(['main', 'branch', 'production', 'warehouse', 'unclassified']), 'group order is Main, Branch, Production, Warehouse, Unclassified');
ok(g.find((x) => x.key === 'branch').items.length === 2 && g.find((x) => x.key === 'production').items.length === 2, 'counts: 2 branches, 2 production');
ok(g.find((x) => x.key === 'unclassified').items.map((x) => x.code).join(',') === 'test_hub,test_none,test_showroom_unknown', 'Unclassified lists every place that fits no group');

// 3. an empty group is not shown; no place at all shows no group
ok(G.grouped([P[0]]).length === 1, 'only the groups that have a place are returned');
ok(G.grouped([]).length === 0, 'no places: no groups');

// 4. the picker: one optgroup per group, option values are the place ids, labels escaped
const html = G.optionsHTML([P[0], P[3]], 4, (l) => '<' + l.name_en + '>', 'All');
ok(/<option value="">All<\/option>/.test(html), 'the picker keeps its "all" option when asked');
ok((html.match(/<optgroup /g) || []).length === 2, 'the picker has one optgroup per group that has a place');
ok(/<option value="4" selected>&lt;test factory a&gt;<\/option>/.test(html), 'the selected place is marked and its name is escaped');
ok(/<option value="1" >/.test(html) || /<option value="1"\s/.test(html), 'option values are the place ids');
ok(G.optionsHTML([], null, null, undefined) === '', 'an empty picker has no options');

// 5. the list: a heading per group with its count, the same card for every place
const list = G.listHTML(P, (l) => '[' + l.code + ']');
ok((list.match(/<section class="lg-group"/g) || []).length === 5, 'the list has one section per group that has a place');
ok(/data-group="branch"><h3 class="lg-h">[^<]*<span class="muted">2<\/span><\/h3>\[test_branch_a\]\[test_branch_b\]/.test(list), 'the Branch section has its heading, count and cards in order');

// 6. the group names: the owner's English names; Bangla proposals are present (to review)
ok(G.GROUPS.map((x) => x.en).join('|') === 'Main Showroom|Branch|Production House|Warehouse|Unclassified', 'the English group names are the owner names');
ok(G.GROUPS.every((x) => x.bn && x.bn.length > 0), 'every group has a Bangla name (proposal, to review)');

console.log('assert failures: ' + fails);
process.exit(fails ? 1 : 0);
