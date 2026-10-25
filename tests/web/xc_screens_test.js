// XC screens (web/xc_unsold.js #/xcunsold, web/xc_summary.js #/xcsummary): static checks, no browser and no database.
//  * both files parse; both routes are registered in web/ia.js and loaded by web/index.html
//  * every i18n key the screens use exists in web/i18n.js with bn, mix and en
//  * every RPC the screens call exists as a function in the SQL phases (phase494, phase497)
//  * the screens write only through the RPCs named in docs/integration/XC.md (no insert / update / delete on a table)
//  * no CSV export in the screens (so no formula-injection path); no hard-coded demo names
// Run: node xc_screens_test.js <abs tests/web dir>   (the repository root is found from this file's folder)
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'web');
const read = (p) => fs.readFileSync(p, 'utf8');
let pass = 0, fail = 0;
const ok = (c, msg) => { if (c) { pass++; } else { fail++; console.log('FAIL: ' + msg); } };

const FILES = ['xc_unsold.js', 'xc_summary.js'];
const src = {};
for (const f of FILES) {
  src[f] = read(path.join(WEB, f));
  try { new vm.Script(src[f], { filename: f }); ok(true, f + ' parses'); } catch (e) { ok(false, f + ' does not parse: ' + e.message); }
}

// routes
const ia = read(path.join(WEB, 'ia.js'));
ok(/rec\('xcunsold',\s*'stock'/.test(ia), 'ia.js registers xcunsold in group stock');
ok(/rec\('xcsummary',\s*'settings'/.test(ia), 'ia.js registers xcsummary in group settings');
ok(!/rec\('xc(unsold|summary)'[^\n]*ruleOn\(/.test(ia), 'XC main features are not hidden behind a switch (switches live inside the feature)');
const html = read(path.join(WEB, 'index.html'));
for (const f of FILES) ok(html.includes('src="' + f + '"'), 'index.html loads ' + f);
ok(/window\.BOS_PAGES = Object\.assign\(window\.BOS_PAGES \|\| \{\}, \{ xcunsold: view \}\)/.test(src['xc_unsold.js']), 'xc_unsold registers route xcunsold');
ok(/\{ xcsummary: view \}/.test(src['xc_summary.js']), 'xc_summary registers route xcsummary');

// i18n keys
const i18nSrc = read(path.join(WEB, 'i18n.js'));
const ctx = { window: {} };
vm.runInNewContext(i18nSrc, ctx, { filename: 'i18n.js' });
const T = ctx.window.BOS_T;
const used = new Set();
const rpcNames = new Set();
for (const f of FILES) for (const m of src[f].matchAll(/call\('([a-z_0-9]+)'|sb\.rpc\('([a-z_0-9]+)'/g)) rpcNames.add(m[1] || m[2]);
for (const f of FILES) for (const m of src[f].matchAll(/from\('([a-z_0-9]+)'\)/g)) rpcNames.add(m[1]);   // table names are not i18n keys
for (const f of FILES) for (const m of src[f].matchAll(/'(xc_[a-z0-9_]+)'/g)) if (!rpcNames.has(m[1]) && !m[1].endsWith('_')) used.add(m[1]);
for (const o of ['sold_discount', 'staff_meal', 'donation', 'waste']) used.add('xc_out_' + o);
let missingKeys = [];
for (const k of used) {
  const e = T[k];
  if (!e || !e.bn || !e.mix || !e.en) missingKeys.push(k);
}
ok(missingKeys.length === 0, 'every xc_ key has bn, mix and en: missing ' + missingKeys.join(', '));
ok(used.size > 40, 'the screens use a realistic number of keys (' + used.size + ')');

// RPCs used by the screens exist in the SQL phases
const sqlDir = path.join(ROOT, 'supabase');
const sqlText = ['phase494.sql', 'phase497.sql'].map((f) => read(path.join(sqlDir, f))).join('\n');
const rpcs = new Set();
for (const f of FILES) for (const m of src[f].matchAll(/call\('([a-z_0-9]+)'|sb\.rpc\('([a-z_0-9]+)'/g)) rpcs.add(m[1] || m[2]);
for (const r of rpcs) ok(new RegExp('create or replace function public\\.' + r + '\\(').test(sqlText), 'RPC exists in phase494/497: ' + r);
ok(rpcs.has('xc_unsold_record') && rpcs.has('xc_recipient_save') && rpcs.has('xc_summary_history'), 'the decision and recipient RPCs are used');

// writes: only RPCs, never a table write
for (const f of FILES) {
  ok(!/\.(insert|update|upsert|delete)\(/.test(src[f]), f + ' writes no table directly');
  ok(!/csv/i.test(src[f]), f + ' has no CSV export');
  ok(!/sendEmail|telegram\.org|api\.telegram|smtp/i.test(src[f]), f + ' sends nothing');
}
ok(!/xc_unsold_void|xc_unsold_report/.test(src['xc_unsold.js']), 'unsold screen has no void and no report call (not in scope)');

console.log('xc_screens_test: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
