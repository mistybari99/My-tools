// Step Sec2 (bos111): L1 catpick CSV formula guard, L2 purchaseprint okMail, L8 landed_q4 selector escaping. Mocked, no browser.
// Run on its own: node tests/web/sec2_test.js        FAILING-BEFORE: on the files without the bos111 edits every block below fails.
const fs = require('fs'), vm = require('vm'), path = require('path');
const { WEB_DIR: ROOT } = require('./_paths');
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const rd = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const L = (bn, en, mix) => ({ bn, en, mix }), lab = (x) => !x ? '' : typeof x === 'string' ? x : (x.en || x.bn);

(async () => {
  // ---------- L1 catpick: csv cells ----------
  {
    const handlers = {}, els = {}; let rpcRows = [];
    const sb = { rpc: async (fn) => (fn === 'biz_items_by_category' ? { data: JSON.parse(JSON.stringify(rpcRows)), error: null } : { data: [], error: null }), from: () => ({ select: () => ({ order: () => ({}) }) }) };
    const A = { sb, S: { lang: 'en', ctx: { is_owner: true, profile: { id: 'u1' } } }, esc, toast() {}, fail() {}, shell: (t, h) => { els.shell = h; }, openSheet() {}, closeSheet() {}, H: handlers };
    const win = { BOS_APP: A, BOS: { L, lab, ENV: {} }, BOS_PAGES: {}, addEventListener() {}, location: { hash: '' } };
    const mkEl = (id, v) => ({ id, value: v, innerHTML: '', dataset: {}, addEventListener() {} });
    const document = { getElementById: (id) => els[id] || null, querySelector: (s) => els[s.replace(/^#/, '')] || null, querySelectorAll: () => [], createElement: () => ({ style: {}, setAttribute() {}, click() {} }), head: { appendChild() {} }, body: { appendChild() {} }, addEventListener() {} };
    const ctx = vm.createContext({ window: win, document, location: win.location, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Blob: function () {}, setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {}, Promise, console, localStorage: { getItem: () => null, setItem() {}, removeItem() {} } });
    vm.runInContext(rd('catpick.js'), ctx, { filename: 'catpick.js' });
    const cp = win.BOS.catpick;
    rpcRows = [
      { category: 'a', sub_category: null, cat_name_bn: '=HYPERLINK("http://x","go")', cat_name_en: '=HYPERLINK("http://x","go")', items: 3, revenue: 340, cogs: 130, share_pct: 50 },
      { category: 'b', sub_category: null, cat_name_bn: '+SUM(A1)', cat_name_en: '+SUM(A1)', items: 1, revenue: -5, cogs: null, share_pct: 1.5 },
      { category: 'c', sub_category: null, cat_name_bn: '-2+3', cat_name_en: '-2+3', items: 1, revenue: 0, cogs: 0, share_pct: 0 },
      { category: 'd', sub_category: null, cat_name_bn: '@cmd', cat_name_en: '@cmd', items: 1, revenue: 1, cogs: 1, share_pct: 1 },
      { category: 'e', sub_category: null, cat_name_bn: 'Milk, "fresh"', cat_name_en: 'Milk, "fresh"', items: 2, revenue: 10, cogs: 4, share_pct: 2 }];
    await win.BOS_PAGES.catreport();
    els.cat_rf = mkEl('cat_rf', '2026-10-01'); els.cat_rt = mkEl('cat_rt', '2026-10-14'); els.cat_rl = mkEl('cat_rl', 'category'); els.cat_rep = { innerHTML: '' };
    await handlers.cat_rpt_go();
    const lines = cp.csvText().split('\n');
    chk('L1 header unchanged', lines[0] === 'category,items,revenue,cost,share_pct');
    chk('L1 "=HYPERLINK(...)" starts with an apostrophe (text, not a formula); the quoted comma form stays valid', lines[1] === `"'=HYPERLINK(""http://x"",""go"")",3,340,130,50`);
    chk('L1 "+SUM(A1)" is guarded, a negative NUMBER (-5) is not', lines[2] === "'+SUM(A1),1,-5,,1.5");
    chk('L1 "-2+3" guarded, "@cmd" guarded', lines[3] === "'-2+3,1,0,0,0" && lines[4] === "'@cmd,1,1,1,1");
    chk('L1 an ordinary name with comma and quotes is only quoted', lines[5] === '"Milk, ""fresh""",2,10,4,2');
  }
  // ---------- L2 purchaseprint okMail ----------
  {
    const win = { BOS_APP: { sb: { rpc: async () => ({ data: null, error: { message: 'x' } }) }, S: { lang: 'en', ctx: {} }, esc, toast() {}, shell() {}, openSheet() {}, closeSheet() {}, fmt: (n) => String(n), H: {} }, BOS: { L, lab, ENV: { locs: [] } }, BOS_PAGES: {}, location: { hash: '' }, navigator: {}, addEventListener() {} };
    const document = { getElementById: () => null, querySelector: () => null, createElement: () => ({ style: {}, setAttribute() {} }), body: { appendChild() {} }, addEventListener() {} };
    const ctx = vm.createContext({ window: win, document, location: win.location, navigator: win.navigator, URL: {}, Blob: function () {}, setTimeout, clearTimeout, Promise, console });
    vm.runInContext(rd('purchaseprint.js'), ctx, { filename: 'purchaseprint.js' });
    const ok = win.BOS.purchaseprint.okMail;
    chk('L2 plain addresses still pass (a@b.co, first.last@mail.example.com, x+y@b-c.org)', ok('a@b.co') && ok(' first.last@mail.example.com ') && ok('x+y@b-c.org'));
    chk('L2 a@b.co?bcc=x@evil.com and a@b.co?bcc=evil%40x.com (no second @) are refused', !ok('a@b.co?bcc=x@evil.com') && !ok('a@b.co?bcc=evil%40x.com'));
    chk('L2 &cc=, #, comma / semicolon lists, angle brackets and quotes are refused', !ok('a@b.co&cc=x@evil.com') && !ok('a@b.co#x') && !ok('a@b.co,c@d.co') && !ok('a@b.co;c@d.co') && !ok('<a@b.co>') && !ok('"a"@b.co'));
    chk('L2 empty / no domain / one-letter TLD / spaces are refused', !ok('') && !ok(null) && !ok('a@b') && !ok('a@b.c') && !ok('a b@c.co'));
  }
  // ---------- L8 landed_q4 selectors ----------
  {
    const queried = [];
    const boxes = [{ checked: true, getAttribute: () => 'g"]\\x' }, { checked: true, getAttribute: () => 'g2' }];
    const A = { sb: { rpc: async (fn, a) => ({ data: [{ bill_id: 'b"][x="1' }], error: null }) }, S: { lang: 'en', ctx: {} }, esc, toast() {}, H: {} };
    const pick = [];
    const win = { CSS: { escape: (v) => String(v).replace(/[^A-Za-z0-9_-]/g, (c) => '\\' + c) }, BOS_APP: A, BOS: { L, lab, landed: { _state: () => ({ pick, info: { mode: 'per_bill' } }) } }, BOS_PAGES: {}, addEventListener() {} };
    const document = { querySelector: (s) => { queried.push(s); return s === '#q4_grnmsg' ? { textContent: '' } : null; }, querySelectorAll: () => boxes, createElement: () => ({}), body: {}, addEventListener() {} };
    const ctx = vm.createContext({ window: win, document, setTimeout, clearTimeout, Promise, console, CSS: { escape: (v) => String(v).replace(/[^A-Za-z0-9_-]/g, (c) => '\\' + c) } });
    vm.runInContext(rd('landed_q4.js'), ctx, { filename: 'landed_q4.js' });
    await win.BOS.landedQ4.addTicked(null);
    const sel = queried.filter((s) => /lcpk|q4g/.test(s));
    chk('L8 selectors were built (bill + GRN checkbox, once per id)', sel.length === 4);
    chk('L8 the id is escaped in the bill selector: [data-lcpk="b\\"\\]\\[x\\=\\"1"] has no raw quote or bracket from the id', sel.some((s) => s === '[data-lcpk="b\\"\\]\\[x\\=\\"1"]'));
    chk('L8 the id is escaped in the GRN selector too', sel.some((s) => s === '#q4_grnlist input[data-q4g="g\\"\\]\\\\x"]'));
    chk('L8 a normal id gives the same selector as before (g2)', sel.some((s) => s === '#q4_grnlist input[data-q4g="g2"]'));
    // without CSS.escape the fallback still protects quotes and brackets
    const ctx2 = vm.createContext({ window: Object.assign({}, win, { CSS: undefined }), document, setTimeout, clearTimeout, Promise, console });
    queried.length = 0; vm.runInContext(rd('landed_q4.js'), ctx2, { filename: 'landed_q4.js' }); await ctx2.window.BOS.landedQ4.addTicked(null);
    chk('L8 fallback (no CSS.escape): quotes / brackets / backslashes of the id are backslash-escaped', queried.filter((s) => /lcpk/.test(s)).every((s) => !/data-lcpk="b"\]/.test(s)) && queried.some((s) => s.includes('b\\"\\]')));
  }
  // ---------- the edits are tagged and small ----------
  for (const f of ['catpick.js', 'purchaseprint.js', 'landed_q4.js', 'itemimg.js']) chk(f + ' carries the bos111 tag', /bos111/.test(rd(f)));
  console.log(failn ? 'FAIL ' + failn : 'OK', 'pass=' + pass);
  process.exit(failn ? 1 : 0);
})().catch((e) => { console.log('ERROR', e); process.exit(1); });
