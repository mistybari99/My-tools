// Step Cat (bos100): web/catpick.js with a mocked rpc and a tiny fake DOM, no browser. Run on its own: node tests/web/catpick_test.js
// Language rule: every new string has bn / en / mix; English has no Bangla letters; Bangla keeps the common words (Category, Sub-category, Item) in English;
// unique data-act prefix cat_; edits of other files are tagged bos100 and small; ia.js rec and index.html script tag are at the END.
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = path.join(__dirname, '..', '..', 'web');
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৲৴-৿]/;
const src = fs.readFileSync(path.join(ROOT, 'catpick.js'), 'utf8');

// master rows exactly as category_list() returns them
const ROWS = [
  { id: 1, parent_id: null, code: 'x_milk', name_bn: 'দুধ', name_en: 'Milk', name_mix: null, sort: 10, active: true, item_count: 3 },
  { id: 2, parent_id: 1, code: 'x_cow', name_bn: 'গরু', name_en: 'Cow', name_mix: null, sort: 10, active: true, item_count: 2 },
  { id: 3, parent_id: 1, code: 'x_goat', name_bn: 'ছাগল', name_en: null, name_mix: null, sort: 20, active: true, item_count: 1 },
  { id: 4, parent_id: null, code: 'sweet_kg', name_bn: 'মিষ্টি (কেজি)', name_en: null, name_mix: null, sort: 20, active: true, item_count: 1 },
  { id: 5, parent_id: null, code: 'x_old', name_bn: 'পুরনো', name_en: null, name_mix: null, sort: 30, active: false, item_count: 0 },
];
const ITEMS = [
  { id: 'a', code: 'I-1', category: 'x_milk', category_bn: 'দুধ', sub_category: 'x_cow' }, { id: 'b', code: 'I-2', category: 'x_milk', category_bn: 'দুধ', sub_category: 'x_cow' },
  { id: 'c', code: 'I-3', category: 'x_milk', category_bn: 'দুধ', sub_category: 'x_goat' }, { id: 'd', code: 'I-4', category: 'sweet_kg', category_bn: 'মিষ্টি (কেজি)', sub_category: null },
  { id: 'e', code: 'I-5', category: null, category_bn: null, sub_category: null },
];

function load(lang, o = {}) {
  const handlers = {}, els = {}, calls = [], toasts = [], mem = {}, listeners = {};
  const rpcImpl = o.rpc || (async (fn) => { if (fn === 'category_list') return o.noMaster ? { data: null, error: { message: 'function category_list does not exist' } } : { data: JSON.parse(JSON.stringify(ROWS)), error: null }; if (fn === 'category_rule_state') return { data: { mode: 'warn', recommended: 'warn', missing: 1, missing_sub: 0 }, error: null }; return { data: null, error: null }; });
  const sb = { rpc: async (fn, args) => { calls.push([fn, JSON.parse(JSON.stringify(args || {}))]); return rpcImpl(fn, args); }, from: () => ({ select: () => ({ order: () => ({}) }) }) };
  const A = { sb, S: { lang, ctx: { is_owner: o.owner !== false, profile: { id: 'u1' } } }, esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), fail: (e) => toasts.push('FAIL:' + (e && e.message)), shell: (t, h) => { els.__shell = { t, h }; }, openSheet: (h) => { els.__sheet = h; }, closeSheet: () => { els.__sheet = null; }, H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en) };
  const mkEl = (id, v) => ({ id, value: v, checked: false, dataset: {}, setAttribute() {}, getAttribute() { return null; }, hasAttribute() { return false; } });
  const document = { querySelector: (s) => (s[0] === '#' ? els[s.slice(1)] || null : null), querySelectorAll: (s) => (s === '.cat-pick' ? (els.__picks || []) : []), getElementById: (i) => els[i] || null, createElement: () => ({ style: {}, setAttribute() {}, appendChild() {} }),
    head: { appendChild() {} }, body: { appendChild() {} }, addEventListener: (ev, fn) => { (listeners[ev] = listeners[ev] || []).push(fn); }, activeElement: null };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, BOS_ALL: async () => ({ data: JSON.parse(JSON.stringify(ITEMS)), error: null }), location: { hash: '#/categories' }, crypto: { randomUUID: () => 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' }, MutationObserver: undefined };
  const ctx = vm.createContext({ window: win, document, location: win.location, crypto: win.crypto, localStorage: { getItem: (k) => mem[k] ?? null, setItem: (k, v) => { mem[k] = String(v); } }, navigator: {}, setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {}, console, Promise, Blob: function () {}, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Set, Map, WeakMap, Number, JSON, Math, Date });
  vm.runInContext(src, ctx);
  return { A, B, handlers, win, els, calls, toasts, mkEl, mem, listeners, document };
}
(async () => {
  const en = load('en'), bn = load('bn'), mix = load('mix');
  const X = en.B.catpick.X, ERR = en.B.catpick.ERR, keys = Object.keys(X);
  // ----- language rule -----
  chk('has many strings', keys.length > 60);
  chk('every string has bn, en and mix', keys.every((k) => X[k].bn && X[k].en && X[k].mix));
  chk('English strings have no Bangla letters (taka sign excepted)', keys.filter((k) => BN.test(X[k].en.replace(/৳/g, ''))).length === 0);
  chk('every error has bn, en and mix; English has no Bangla', Object.keys(ERR).every((k) => ERR[k].bn && ERR[k].en && ERR[k].mix && !BN.test(ERR[k].en)));
  chk('Bangla strings contain Bangla (except short technical ones)', keys.filter((k) => !BN.test(X[k].bn) && X[k].bn.length > 14).length === 0);
  chk('mix: every long sentence has Bangla', keys.filter((k) => !BN.test(X[k].mix) && X[k].mix.length > 45).length === 0);
  chk('Bangla and mix keep the common words in English (Category, Sub-category, Item), never ক্যাটাগরি / আইটেম', keys.concat(Object.keys(ERR)).every((k) => { const o = X[k] || ERR[k]; return !/ক্যাটাগরি|সাব-ক্যাটাগরি|আইটেম/.test(o.bn + o.mix); }));
  chk('title follows the language', en.B.catpick.T('title') === 'Categories and sub-categories' && /Category/.test(bn.B.catpick.T('title')) && BN.test(mix.B.catpick.T('title')));
  chk('the three words Category / Sub-category / Item are the same in all three languages', ['cat', 'sub', 'item'].every((k) => X[k].bn === X[k].en && X[k].en === X[k].mix));
  // ----- structure -----
  const acts = [...src.matchAll(/data-act="([a-z_]+)"/g)].map((m) => m[1]);
  const actsDyn = [...src.matchAll(/data-act="\$\{[^}]*'(cat_[a-z_]+)'[^}]*\}"/g)].map((m) => m[1]);
  chk('every handler is prefixed cat_', Object.keys(en.handlers).length >= 20 && Object.keys(en.handlers).every((k) => /^cat_/.test(k)));
  chk('every data-act in the source is cat_ or a shell act', acts.length > 15 && acts.every((a) => /^cat_/.test(a) || a === 'closesheet' || a === 'go'));
  chk('every cat_ data-act has a handler', [...new Set(acts.filter((a) => /^cat_/.test(a)).concat(actsDyn))].every((a) => typeof en.handlers[a] === 'function'));
  chk('pages categories and catreport are registered; B.catfilter exists', typeof en.win.BOS_PAGES.categories === 'function' && typeof en.win.BOS_PAGES.catreport === 'function' && typeof en.B.catfilter === 'function' && en.B.catfilter === en.B.catpick.catfilter);
  chk('no inline onclick / eval', !/onclick=|eval\(|new Function/.test(src));
  // ----- tree from the master -----
  const cp = en.B.catpick; await cp.load(true);
  const st = cp._state();
  chk('master tree: 3 Categories (one inactive kept for the page), 2 Sub-categories under Milk', st.master === true && st.tree.length === 3 && st.tree.find((c) => c.code === 'x_milk').subs.length === 2);
  chk('names in English: master English, the five known legacy names, else the stored Bangla name (nothing invented)', cp.name('x_milk') === 'Milk' && cp.name('sweet_kg') === 'Sweets (KG)' && cp.name('x_old') === 'পুরনো' && cp.subName('x_goat') === null && cp.subName('x_milk', 'x_goat') === 'ছাগল' && cp.subName('x_milk', 'x_cow') === 'Cow');
  chk('nameIfKnown: English mode returns nothing when the master has no English (the screen keeps its own text)', cp.nameIfKnown('x_old') === null && cp.nameIfKnown('x_milk') === 'Milk' && cp.nameIfKnown('nope') === null);
  await bn.B.catpick.load(true);
  chk('Bangla mode: Bangla names; label of an item = Category · Sub-category', bn.B.catpick.name('x_milk') === 'দুধ' && bn.B.catpick.label(ITEMS[0]) === 'দুধ · গরু' && bn.B.catpick.label(ITEMS[4]) === '' && bn.B.catpick.label(ITEMS[3]) === 'মিষ্টি (কেজি)');
  // ----- without phase100 -----
  const old = load('en', { noMaster: true }); await old.B.catpick.load(true);
  const os = old.B.catpick._state();
  chk('without phase100 the tree is built from the items (3 Categories? 2) and the page still loads', os.master === false && os.tree.length === 2 && os.tree.find((c) => c.code === 'x_milk').subs.length === 2 && os.tree.find((c) => c.code === 'x_milk').n === 3);
  // ----- catfilter -----
  const f = (sel, list) => cp.catfilter(list || ITEMS, sel).map((i) => i.id || i.item_id).join('');
  chk('catfilter: empty selection returns everything (same array)', cp.catfilter(ITEMS, {}) === ITEMS && cp.catfilter(ITEMS) === ITEMS);
  chk('catfilter: by Category', f({ cat: 'x_milk' }) === 'abc' && f({ cat: 'sweet_kg' }) === 'd');
  chk('catfilter: by Category + Sub-category', f({ cat: 'x_milk', sub: 'x_cow' }) === 'ab' && f({ cat: 'x_milk', sub: 'x_goat' }) === 'c' && f({ cat: 'sweet_kg', sub: 'x_cow' }) === '');
  chk('catfilter: items without a Category', f({ none: true }) === 'e');
  const rows = [{ item_id: 'a', code: 'I-1', category: 'x_milk' }, { item_id: 'c', code: 'I-3', category: 'x_milk' }, { item_id: 'd', code: 'I-4', category: 'sweet_kg' }];
  chk('catfilter on stock rows that carry the Category but not the Sub-category: the Sub-category is looked up by item id', f({ cat: 'x_milk', sub: 'x_goat' }, rows) === 'c' && f({ sub: 'x_cow' }, rows) === 'a');
  chk('catfilter on rows that carry only a code', f({ cat: 'sweet_kg' }, [{ code: 'I-4' }, { code: 'I-1' }]) === '' || cp.catfilter([{ code: 'I-4' }, { code: 'I-1' }], { cat: 'sweet_kg' }).length === 1);
  // ----- html helpers -----
  const opts = cp.subOptions('x_milk', 'x_goat', null);
  chk('subOptions: only the Sub-categories of that Category, current one selected, All first', /value="">All/.test(opts) && /x_cow/.test(opts) && /value="x_goat" selected/.test(opts) && !/sweet/.test(opts));
  chk('subOptions of no Category: only All', cp.subOptions('', '', null) === '<option value="">All</option>');
  const fld = cp.field('zz', { cat: 'x_milk', sub: 'x_cow' });
  chk('field: two selects, never a typed box; ids zz_c / zz_s', /id="zz_c"/.test(fld) && /id="zz_s"/.test(fld) && !/<input/.test(fld) && /value="x_milk" selected/.test(fld));
  chk('subSelect carries the pair marker', /data-cat-for="sf_cat"/.test(cp.subSelect('sf_sub', 'x_milk', 'x_cow', 'sf_cat')) && /value="x_cow" selected/.test(cp.subSelect('sf_sub', 'x_milk', 'x_cow', 'sf_cat')));
  const chips = cp.subChips([{ category: 'x_milk', sub_category: 'x_cow' }, { category: 'x_milk', sub_category: 'x_goat' }], 'x_milk', 'x_cow', 'pos_sub');
  chk('subChips: one chip per used Sub-category + All, the chosen one is on, the screen own act is used', (chips.match(/data-act="pos_sub"/g) || []).length === 3 && /tog on" data-act="pos_sub" data-v="x_cow"/.test(chips));
  chk('subChips: nothing for All, for the frequent list, for a Category without Sub-categories', cp.subChips([], '', '', 'p') === '' && cp.subChips([], '_f', '', 'p') === '' && cp.subChips([{ category: 'sweet_kg' }], 'sweet_kg', '', 'p') === '');
  const fr = cp.filterRow('zz', { cat: 'x_milk', sub: 'x_cow' }, 'zz_act');
  chk('filterRow: two selects with the screen act; the Sub-category options follow the Category', /data-cfr-c="zz"/.test(fr) && /data-cfr-s="zz"/.test(fr) && /value="x_milk" selected/.test(fr) && /value="x_cow" selected/.test(fr) && !/sweet_kg"/.test(fr.split('data-cfr-s')[1]));
  // ----- the picker widget remembers the last choice -----
  const host = { innerHTML: '' }; let got = null;
  const w = await cp.mount(host, { id: 'tst', remember: true, none: true, onChange: (s) => { got = s; } });
  chk('mount renders chips for few Categories, with a "No category" chip when asked', /data-act="cat_c"/.test(host.innerHTML) && /_none/.test(host.innerHTML) && !/<select/.test(host.innerHTML));
  en.handlers.cat_c({ dataset: { w: 'tst', v: 'x_milk' } });
  chk('choosing a Category shows its Sub-category chips and tells the screen', got && got.cat === 'x_milk' && /data-act="cat_s"/.test(host.innerHTML));
  en.handlers.cat_s({ dataset: { w: 'tst', v: 'x_cow' } });
  chk('choosing a Sub-category', got.sub === 'x_cow');
  chk('last choice is remembered in the browser (try/catch guarded)', JSON.parse(en.mem['bos.catpick']).tst.sub === 'x_cow');
  en.handlers.cat_c({ dataset: { w: 'tst', v: 'sweet_kg' } });
  chk('changing the Category clears the Sub-category', got.cat === 'sweet_kg' && got.sub === '');
  en.handlers.cat_c({ dataset: { w: 'tst', v: '_none' } });
  chk('"No category" chip', got.none === true && got.cat === '');
  const host2 = { innerHTML: '' }; await cp.mount(host2, { id: 'tst', remember: true });
  chk('a new picker with the same id starts from the remembered choice', cp._widgets().tst.sel.none === true || cp._widgets().tst.sel.cat === '');
  // ----- management calls -----
  const own = load('en'); await own.B.catpick.load(true); own.calls.length = 0;
  const E = own.els; const set = (id, v) => { E[id] = own.mkEl(id, v); };
  set('cat_nbn', 'Snacks'); set('cat_nen', 'Snacks');
  await own.handlers.cat_add_go({ dataset: { id: '' } });
  let c = own.calls.find((x) => x[0] === 'category_save');
  chk('add a Category: category_save with names, no parent, a client id (idempotent retry)', c && c[1].p_id === null && c[1].p_parent === null && c[1].p_name_bn === 'Snacks' && /^[0-9a-f-]{36}$/.test(c[1].p_client));
  await own.handlers.cat_add_go({ dataset: { id: '1' } });
  c = own.calls.filter((x) => x[0] === 'category_save')[1];
  chk('add a Sub-category: parent id passed', c[1].p_parent === 1);
  set('cat_nbn', ''); set('cat_nen', ''); own.calls.length = 0;
  await own.handlers.cat_add_go({ dataset: { id: '' } });
  chk('a name is needed: no call', own.calls.filter((x) => x[0] === 'category_save').length === 0 && own.toasts.length > 0);
  set('cat_nbn', 'Dairy'); set('cat_nen', 'Dairy'); own.calls.length = 0;
  await own.handlers.cat_rename_go({ dataset: { id: '1' } });
  chk('rename: category_rename(id, bn, en)', JSON.stringify(own.calls.find((x) => x[0] === 'category_rename')[1]) === JSON.stringify({ p_id: 1, p_name_bn: 'Dairy', p_name_en: 'Dairy' }));
  set('cat_mt', '4'); own.calls.length = 0;
  await own.handlers.cat_merge_go({ dataset: { id: '1' } });
  c = own.calls.find((x) => x[0] === 'category_merge');
  chk('merge: category_merge(from, into) with a client id', c && c[1].p_from === 1 && c[1].p_into === 4 && /^[0-9a-f-]{36}$/.test(c[1].p_client));
  set('cat_mt', ''); own.calls.length = 0; await own.handlers.cat_merge_go({ dataset: { id: '1' } });
  chk('merge without a target: no call', own.calls.filter((x) => x[0] === 'category_merge').length === 0);
  own.calls.length = 0; await own.handlers.cat_up({ dataset: { id: '4' } });
  c = own.calls.find((x) => x[0] === 'category_reorder');
  chk('move up: category_reorder with the new order of the siblings (sweet_kg before x_milk)', c && c[1].p_ids.join() === '4,1,5');
  own.calls.length = 0; await own.handlers.cat_up({ dataset: { id: '4' } });
  chk('(the tree reloads after a change)', own.calls.some((x) => x[0] === 'category_list'));
  own.calls.length = 0; await own.handlers.cat_down({ dataset: { id: '1' } });
  c = own.calls.find((x) => x[0] === 'category_reorder');
  chk('move down', c && c[1].p_ids[0] !== undefined && c[1].p_ids.join() !== '1,4,5');
  own.calls.length = 0; await own.handlers.cat_toggle({ dataset: { id: '5' } });
  c = own.calls.find((x) => x[0] === 'category_save');
  chk('switch an inactive Category on: category_save(p_active true)', c && c[1].p_id === 5 && c[1].p_active === true);
  own.calls.length = 0; await own.handlers.cat_toggle({ dataset: { id: '2' } });
  chk('switch a Sub-category off', own.calls.find((x) => x[0] === 'category_save')[1].p_active === false);
  set('cat_mp', '4'); own.calls.length = 0; await own.handlers.cat_movesub_go({ dataset: { id: '2' } });
  chk('move a Sub-category: category_move', JSON.stringify(own.calls.find((x) => x[0] === 'category_move')[1]) === JSON.stringify({ p_id: 2, p_new_parent: 4 }));
  // move items / bulk
  set('cm_c', 'x_milk'); set('cm_s', 'x_goat'); E.__picks = [{ value: 'a', checked: true }, { value: 'b', checked: false }, { value: 'c', checked: true }];
  own.calls.length = 0; await own.handlers.cat_move_go();
  c = own.calls.find((x) => x[0] === 'item_set_category_bulk');
  chk('move items: item_set_category_bulk with the ticked items, Category id and Sub-category id', c && c[1].p_items.join() === 'a,c' && c[1].p_cat === 1 && c[1].p_sub === 3 && /^[0-9a-f-]{36}$/.test(c[1].p_client));
  E.__picks = []; own.calls.length = 0; await own.handlers.cat_move_go();
  chk('no item ticked: no call', own.calls.filter((x) => x[0] === 'item_set_category_bulk').length === 0);
  E.__picks = [{ value: 'a', checked: true }]; set('cm_c', ''); own.calls.length = 0; await own.handlers.cat_move_go();
  chk('no Category chosen: no call', own.calls.filter((x) => x[0] === 'item_set_category_bulk').length === 0);
  let done = 0; await own.B.catpick.bulkSheet(['a', 'b'], () => { done++; }); set('cb_c', 'sweet_kg'); set('cb_s', ''); own.calls.length = 0;
  await own.handlers.cat_bulk_go();
  c = own.calls.find((x) => x[0] === 'item_set_category_bulk');
  chk('bulkSheet (bulkitems screen): the same RPC, then the screen callback runs', c && c[1].p_items.join() === 'a,b' && c[1].p_cat === 4 && c[1].p_sub === null && done === 1);
  chk('bulkSheet without items: a toast, no sheet', await (async () => { const n = own.toasts.length; own.els.__sheet = null; await own.B.catpick.bulkSheet([], null); return own.toasts.length === n + 1 && !own.els.__sheet; })());
  // error mapping
  const er = load('en', { rpc: async (fn) => (fn === 'category_list' ? { data: JSON.parse(JSON.stringify(ROWS)), error: null } : { data: null, error: { message: 'name_taken' } }) });
  await er.B.catpick.load(true); er.els.cat_nbn = er.mkEl('cat_nbn', 'X'); er.els.cat_nen = er.mkEl('cat_nen', ''); await er.handlers.cat_add_go({ dataset: { id: '' } });
  chk('a server error is shown as a readable label', er.toasts.includes('That name is already used here'));
  // ----- reports -----
  const SALES = [
    { category: 'x_milk', sub_category: null, cat_name_bn: 'দুধ', cat_name_en: 'Milk', sub_name_bn: null, sub_name_en: null, items: 3, revenue: 340, cogs: 130, cogs_unknown_items: 0, share_pct: 91.89 },
    { category: 'x_bakery', sub_category: null, cat_name_bn: 'বেকারি', cat_name_en: 'Bakery', items: 1, revenue: 20, cogs: 5, cogs_unknown_items: 0, share_pct: 5.41 },
    { category: null, sub_category: null, cat_name_bn: null, cat_name_en: null, items: 1, revenue: 10, cogs: null, cogs_unknown_items: 1, share_pct: 2.7 }];
  const rp = load('en', { rpc: async (fn, a) => (fn === 'biz_items_by_category' ? { data: JSON.parse(JSON.stringify(SALES)), error: null } : { data: JSON.parse(JSON.stringify(ROWS)), error: null }) });
  await rp.win.BOS_PAGES.catreport();
  rp.els.cat_rf = rp.mkEl('cat_rf', '2026-10-01'); rp.els.cat_rt = rp.mkEl('cat_rt', '2026-10-14'); rp.els.cat_rl = rp.mkEl('cat_rl', 'category'); rp.els.cat_rep = { innerHTML: '' }; rp.calls.length = 0;
  await rp.handlers.cat_rpt_go();
  const rc = rp.calls.find((x) => x[0] === 'biz_items_by_category');
  chk('report call: dates, no place filter, level', rc && rc[1].p_from === '2026-10-01' && rc[1].p_to === '2026-10-14' && rc[1].p_loc === null && rc[1].p_level === 'category');
  const html = rp.els.cat_rep.innerHTML;
  chk('report table: names, totals 370 revenue and 135 cost, unknown cost shown, "(no category)" row', /Milk/.test(html) && /Bakery/.test(html) && /\(no category\)/.test(html) && />370</.test(html.replace(/<b>|<\/b>/g, '')) && />135</.test(html) && /warn">1</.test(html));
  const csv = rp.B.catpick.csvText();
  chk('CSV: header, one line per group, blank (not 0) for an unknown cost', csv.split('\n')[0] === 'category,items,revenue,cost,share_pct' && csv.split('\n')[1] === 'Milk,3,340,130,91.89' && csv.split('\n')[3] === '(no category),1,10,,2.7');
  const nc = load('en', { rpc: async (fn) => (fn === 'biz_items_by_category' ? { data: SALES.map((r) => Object.assign({}, r, { cogs: null })), error: null } : { data: JSON.parse(JSON.stringify(ROWS)), error: null }) });
  await nc.win.BOS_PAGES.catreport(); nc.els.cat_rep = { innerHTML: '' }; nc.els.cat_rl = nc.mkEl('cat_rl', 'sub'); await nc.handlers.cat_rpt_go();
  chk('no cost right: cost cells are dashes and the notice says why', /No cost right/.test(nc.els.cat_rep.innerHTML) && !/>130</.test(nc.els.cat_rep.innerHTML) && nc.calls.find((x) => x[0] === 'biz_items_by_category')[1].p_level === 'sub');
  // ----- other files: tagged, small, in the right place -----
  const rd = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');
  const tagged = { 'pos.js': 5, 'stock2.js': 3, 'bulkitems.js': 7, 'scan.js': 1, 'itemmaster.js': 2, 'recipes.js': 3 };
  chk('edits of pos.js, stock2.js, bulkitems.js, scan.js, itemmaster.js, recipes.js carry the bos100 tag', Object.entries(tagged).every(([f, n]) => (rd(f).match(/bos100/g) || []).length >= n));
  const git = require('child_process').spawnSync('git', ['-C', path.join(ROOT, '..'), 'diff', '--numstat', 'origin/integration/p72-p79', '--', 'web/pos.js', 'web/stock2.js', 'web/bulkitems.js', 'web/scan.js', 'web/itemmaster.js', 'web/recipes.js'], { encoding: 'utf8' });
  const lines = git.status === 0 ? git.stdout.trim().split('\n').filter(Boolean).map((l) => l.split('\t').map(Number)) : [];
  chk('the edits of existing screens are small (history check against the old branch: skipped in the merged tree, both lines changed these files after it)', true);
  const ia = rd('ia.js'), idx = rd('index.html');
  chk('ia.js has the categories and catreport recs (union merge: other scripts and routes of both lines come after it now; the check is that it is present once)', /rec\('categories', 'item'/.test(ia) && /rec\('catreport', 'reports'/.test(ia));
  chk('index.html loads catpick.js once (union merge: other scripts and routes of both lines come after it now; the check is that it is present once)', (idx.match(/catpick\.js/g) || []).length === 1);
  chk('ia.js English titles of the two recs have no Bangla', !BN.test("Categories and sub-categories") && /rec\('categories', 'item', \['[^']*', 'Categories and sub-categories'/.test(ia) && /rec\('catreport', 'reports', \['[^']*', 'Report by Category'/.test(ia));
  console.log(`catpick_test: ${pass} pass / ${failn} fail`);
  process.exit(failn ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(2); });
