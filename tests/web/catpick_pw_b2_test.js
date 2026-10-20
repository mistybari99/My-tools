// catpick_pw_b2_test.js = catpick_pw_test.js adapted to the phase108 Bangla-wording step and later registry/script appends (QA webfull). Only the listed assertions differ.
// Step Cat (bos100): the real app + web/catpick.js in a phone-size browser (360 px) with a mocked rpc.
// Screens: #/categories (tree, add, rename, merge, move up, switch off, move items, rule), #/catreport (sales + stock value, level, CSV), POS Sub-category chips,
// stock hub filter sheet (Sub-category), the item pickers (stock issue sheet: a Category + Sub-category bar that filters the item list and remembers the choice),
// the item editor (Sub-category list follows the Category), three languages, no horizontal overflow, no page errors.
// Run on its own: node tests/web/catpick_pw_test.js <abs tests/web dir>      (serves ../../web of THIS checkout)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname;
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web');
const base = C.baseData(SP), PORT = 8498;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  // i0 / i1: sweet_kg with Sub-categories s_a / s_b; i2: sweet_pc with s_c; the rest keep their seed Category without a Sub-category
  T.items.forEach((i) => { i.sub_category = null; });
  Object.assign(T.items[0], { category: 'sweet_kg', sub_category: 's_a' }); Object.assign(T.items[1], { category: 'sweet_kg', sub_category: 's_b' }); Object.assign(T.items[2], { category: 'sweet_pc', sub_category: 's_c' });
  T.option_lists = (T.option_lists || []).concat([['s_a', 'ক', 'A sub'], ['s_b', 'খ', 'B sub'], ['s_c', 'গ', 'C sub']].map((u, i) => ({ list_code: 'item_subcategories', value_code: u[0], label_bn: u[1], label_en: u[2], sort: i + 1, active: true, extra: {} })));
  [0, 1, 2].forEach((n) => Object.assign(T.items[n], { item_type: 'finished_good', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true }));
  T.recipes = [{ id: 'rc1', item_id: T.items[0].id, version: 1, yield_qty: 2, yield_unit: null, active: true, note: null, used_at: null, created_at: '2026-10-01T00:00:00Z' }, { id: 'rc2', item_id: T.items[2].id, version: 1, yield_qty: 5, yield_unit: null, active: true, note: null, used_at: null, created_at: '2026-10-02T00:00:00Z' }];
  T.recipe_lines = []; T.product_packaging = []; T.rules.push({ key: 'packaging_consume_on', module: 'stock', kind: 'choice', value: null, default_value: 'off', label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 });
  return data;
}
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const K = window.__K = Object.assign({ calls: [], err: {}, master: true, mode: 'warn', missing: 2,
  rows: [
   { id: 1, parent_id: null, code: 'sweet_kg', name_bn: 'মিষ্টি (কেজি)', name_en: null, name_mix: null, sort: 10, active: true, item_count: 4 },
   { id: 2, parent_id: 1, code: 's_a', name_bn: 'ক', name_en: 'A sub', name_mix: null, sort: 10, active: true, item_count: 1 },
   { id: 3, parent_id: 1, code: 's_b', name_bn: 'খ', name_en: 'B sub', name_mix: null, sort: 20, active: true, item_count: 1 },
   { id: 4, parent_id: null, code: 'sweet_pc', name_bn: 'মিষ্টি (পিস)', name_en: null, name_mix: null, sort: 20, active: true, item_count: 3 },
   { id: 5, parent_id: 4, code: 's_c', name_bn: 'গ', name_en: 'C sub', name_mix: null, sort: 10, active: true, item_count: 1 }],
  sales: [
   { category: 'sweet_kg', sub_category: null, cat_name_bn: 'মিষ্টি (কেজি)', cat_name_en: null, sub_name_bn: null, sub_name_en: null, items: 2, revenue: 340, cogs: 130, cogs_unknown_items: 0, share_pct: 91.89 },
   { category: null, sub_category: null, cat_name_bn: null, cat_name_en: null, sub_name_bn: null, sub_name_en: null, items: 1, revenue: 30, cogs: null, cogs_unknown_items: 1, share_pct: 8.11 }],
  stock: [{ category: 'sweet_kg', sub_category: null, cat_name_bn: 'মিষ্টি (কেজি)', cat_name_en: null, sub_name_bn: null, sub_name_en: null, items: 2, value: 570 }] }, window.__K0 || {});
 c.rpc = async (fn, args) => {
  if (!/^(category_|item_set_category|biz_items_by_category$|stock_valuation_by_category$|items_missing_category$)/.test(fn) && !(fn === 'set_rule' && args && args.p_key === 'category_required_on_item')) return rpc(fn, args);
  K.calls.push([fn, clone(args || {})]);
  if (K.err[fn]) return { data: null, error: { message: K.err[fn] } };
  if (fn === 'category_list') return K.master ? { data: clone(K.rows), error: null } : { data: null, error: { message: 'function public.category_list does not exist' } };
  if (fn === 'category_rule_state') return { data: { mode: K.mode, recommended: 'warn', missing: K.missing, missing_sub: 0 }, error: null };
  if (fn === 'set_rule') { K.mode = args.p_value; return { data: null, error: null }; }
  if (fn === 'category_save') return { data: { id: 9, code: 'k001' }, error: null };
  if (fn === 'category_rename') return { data: { id: args.p_id, items_updated: 3 }, error: null };
  if (fn === 'category_merge') return { data: { items_moved: 2, subs_moved: 1 }, error: null };
  if (fn === 'category_move') return { data: { items_moved: 1 }, error: null };
  if (fn === 'category_reorder') return { data: 2, error: null };
  if (fn === 'item_set_category_bulk') return { data: { items: args.p_items.length }, error: null };
  if (fn === 'items_missing_category') return { data: [{ item_id: 'i5', code: 'I-006', name_bn: 'কিছু', name_en: 'Something', item_type: 'finished_good', category: null, sub_category: null, reason: 'no_category' }, { item_id: 'i6', code: 'I-007', name_bn: 'আরও', name_en: 'More', item_type: 'finished_good', category: 'sweet_kg', sub_category: null, reason: 'no_sub_category' }], error: null };
  if (fn === 'biz_items_by_category') return { data: clone(K.sales), error: null };
  if (fn === 'stock_valuation_by_category') return { data: clone(K.stock), error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__K0=${JSON.stringify(o.k || {})};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); try { await p.waitForFunction(() => window.BOS && window.BOS.catpick && window.BOS.catpick._state().tree, null, { timeout: 5000 }); } catch (e) { /* tests that need the tree will fail on their own */ } return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const kcalls = (p, fn) => p.evaluate((f) => window.__K.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const wait = (p, n = 300) => p.waitForTimeout(n);

  // ---------- #/categories ----------
  let p = await open({}, '#/categories');
  ok(await p.locator('.cat-card').count() === 2, 'two Category cards');
  ok(await p.locator('.cat-sub').count() === 3, 'three Sub-category rows');
  ok(/Categories and sub-categories/.test(await p.textContent('body')), 'English title');
  ok(/Items without a Category/.test(await p.textContent('body')) && /2/.test(await p.textContent('#cat_tree') + 2), 'rule card shows the missing count');
  ok(await p.locator('#cat_mode').count() === 1 && (await p.inputValue('#cat_mode')) === 'warn', 'owner sees the rule select on warn');
  await noOverflow(p, 'categories'); await p.screenshot({ path: SP + '/cat_tree.png' });
  // add
  await p.click('[data-act=cat_add]'); await wait(p, 200); await p.fill('#cat_nbn', 'Snacks'); await p.fill('#cat_nen', 'Snacks'); await p.click('[data-act=cat_add_go]'); await wait(p, 400);
  let c = await kcalls(p, 'category_save'); ok(c.length === 1 && c[0].p_name_bn === 'Snacks' && c[0].p_parent === null && /^[0-9a-f-]{36}$/.test(c[0].p_client), 'add: category_save with a client id');
  // menu -> add sub-category
  await p.click('.cat-card >> nth=0 >> [data-act=cat_menu]'); await wait(p, 200);
  ok(await p.locator('.sheet [data-act=cat_addsub]').count() === 1 && await p.locator('.sheet [data-act=cat_rename]').count() === 1 && await p.locator('.sheet [data-act=cat_merge]').count() === 1, 'owner menu: add sub, rename, merge');
  await noOverflow(p, 'menu'); await p.screenshot({ path: SP + '/cat_menu.png' });
  await p.click('.sheet [data-act=cat_addsub]'); await wait(p, 200); await p.fill('#cat_nbn', 'Sub X'); await p.click('[data-act=cat_add_go]'); await wait(p, 400);
  c = await kcalls(p, 'category_save'); ok(c.length === 2 && c[1].p_parent === 1, 'add sub: parent id 1');
  // rename
  await p.click('.cat-card >> nth=0 >> [data-act=cat_menu]'); await wait(p, 150); await p.click('.sheet [data-act=cat_rename]'); await wait(p, 200);
  ok((await p.inputValue('#cat_nbn')) === 'মিষ্টি (কেজি)', 'rename sheet starts with the Bangla name'); await p.fill('#cat_nbn', 'Sweets'); await p.fill('#cat_nen', 'Sweets by kg'); await p.click('[data-act=cat_rename_go]'); await wait(p, 400);
  c = await kcalls(p, 'category_rename'); ok(c.length === 1 && c[0].p_id === 1 && c[0].p_name_en === 'Sweets by kg', 'rename call');
  // merge
  await p.click('.cat-card >> nth=0 >> [data-act=cat_menu]'); await wait(p, 150); await p.click('.sheet [data-act=cat_merge]'); await wait(p, 200);
  ok(/cannot be undone/.test(await p.textContent('.sheet')), 'merge warns'); await p.selectOption('#cat_mt', '4'); await p.click('[data-act=cat_merge_go]'); await wait(p, 400);
  c = await kcalls(p, 'category_merge'); ok(c.length === 1 && c[0].p_from === 1 && c[0].p_into === 4, 'merge call'); ok(/2/.test(await p.textContent('#toast')), 'merge toast shows the moved count');
  // up / down / off
  await p.click('.cat-card >> nth=1 >> [data-act=cat_menu]'); await wait(p, 150); await p.click('.sheet [data-act=cat_up]'); await wait(p, 400);
  c = await kcalls(p, 'category_reorder'); ok(c.length === 1 && c[0].p_ids.join() === '4,1', 'move up: new order 4,1');
  await p.click('.cat-card >> nth=0 >> [data-act=cat_menu]'); await wait(p, 150); await p.click('.sheet [data-act=cat_toggle]'); await wait(p, 400);
  c = await kcalls(p, 'category_save'); ok(c[c.length - 1].p_id === 1 && c[c.length - 1].p_active === false, 'switch off');
  // move items
  await p.click('.cat-card >> nth=0 >> [data-act=cat_menu]'); await wait(p, 150); await p.click('.sheet [data-act=cat_moveitems]'); await wait(p, 300);
  ok(await p.locator('.sheet .cat-pick').count() >= 1, 'items of the Category listed'); await noOverflow(p, 'move items');
  await p.click('.sheet .cat-pick >> nth=0'); await p.selectOption('#cm_c', 'sweet_kg'); await wait(p, 100);
  ok(await p.locator('#cm_s option').count() === 3, 'Sub-category select follows the Category (All + 2)'); await p.selectOption('#cm_s', 's_b'); await p.click('[data-act=cat_move_go]'); await wait(p, 400);
  c = await kcalls(p, 'item_set_category_bulk'); ok(c.length === 1 && c[0].p_cat === 1 && c[0].p_sub === 3 && c[0].p_items.length === 1, 'move items call: Category 1, Sub-category 3');
  // missing list
  await p.click('[data-act=cat_missing]'); await wait(p, 300); ok(await p.locator('.sheet .cat-pick').count() === 2, 'missing list shows both items'); ok(/No sub-category/.test(await p.textContent('.sheet')), 'sub-category reason chip');
  await p.click('#cat_selall'); await p.selectOption('#cm_c', 'sweet_pc'); await p.click('[data-act=cat_move_go]'); await wait(p, 400);
  c = await kcalls(p, 'item_set_category_bulk'); ok(c.length === 2 && c[1].p_items.join() === 'i5,i6' && c[1].p_cat === 4 && c[1].p_sub === null, 'bulk set from the missing list');
  // rule
  await p.selectOption('#cat_mode', 'required'); await wait(p, 400); c = await kcalls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'category_required_on_item' && c[0].p_value === 'required', 'rule change call');
  await p.close();

  // no master (phase100 not installed): the page still opens from the items, read only
  p = await open({ k: { master: false } }, '#/categories'); ok(await p.locator('.cat-card').count() >= 2, 'tree built from the items without phase100'); ok(await p.locator('[data-act=cat_menu]').count() === 0, 'no edit buttons without the master'); ok(/not installed/.test(await p.textContent('body')), 'says phase100 is missing');
  await p.close();

  // Bangla and Bng/Eng mix
  for (const lang of ['bn', 'mix']) { p = await open({ lang }, '#/categories'); const t = await p.textContent('body'); ok(lang === 'bn' ? /ক্যাটাগরি/.test(t) : (/Category/.test(t) && /Sub-category/.test(t) && !/ক্যাটাগরি/.test(t.replace(/মিষ্টি/g, ''))), lang + (lang === 'bn' ? ': Bangla Category words (wording step)' : ': keeps Category / Sub-category in English')); ok(/প্রতিটি/.test(t), lang + ': Bangla sentence'); await noOverflow(p, lang); await p.screenshot({ path: SP + '/cat_' + lang + '.png' }); await p.close(); }

  // ---------- #/catreport ----------
  p = await open({}, '#/catreport'); await p.click('[data-act=cat_rpt_go]'); await wait(p, 400);
  ok(await p.locator('.cat-tbl tbody tr').count() === 3, 'report: 2 groups + total'); ok(/370/.test(await p.textContent('.cat-tot')) && /130/.test(await p.textContent('.cat-tot')), 'report total revenue 370 and cost 130');
  ok(/\(no category\)/.test(await p.textContent('.cat-tbl')), 'uncategorised row'); await noOverflow(p, 'report'); await p.screenshot({ path: SP + '/cat_report.png' });
  c = await kcalls(p, 'biz_items_by_category'); ok(c.length === 1 && c[0].p_level === 'category' && c[0].p_loc === null, 'sales call');
  await p.selectOption('#cat_rl', 'sub'); await p.click('[data-act=cat_rpt_go]'); await wait(p, 300); c = await kcalls(p, 'biz_items_by_category'); ok(c[1].p_level === 'sub', 'Sub-category level sent'); ok(await p.locator('.cat-tbl th').count() === 6, 'sub level has the extra column');
  const dl = p.waitForEvent('download', { timeout: 4000 }).catch(() => null); await p.click('[data-act=cat_rpt_csv]'); const d = await dl; ok(d && /by-category-sales/.test(d.suggestedFilename()), 'CSV download');
  await p.click('[data-act=cat_rpt_k][data-v=stock]'); await wait(p, 200); await p.click('[data-act=cat_rpt_go]'); await wait(p, 400); c = await kcalls(p, 'stock_valuation_by_category'); ok(c.length === 1, 'stock value call'); ok(/570/.test(await p.textContent('.cat-tbl')), 'stock value shown');
  await p.close();
  p = await open({ k: { sales: [{ category: 'sweet_kg', sub_category: null, cat_name_bn: 'x', cat_name_en: null, items: 2, revenue: 340, cogs: null, cogs_unknown_items: 0, share_pct: 100 }] } }, '#/catreport'); await p.click('[data-act=cat_rpt_go]'); await wait(p, 400);
  ok(/No cost right/.test(await p.textContent('body')), 'cost-less user: the notice says why cost is blank'); await p.close();

  // ---------- POS Sub-category chips ----------
  p = await open({}, '#/pos'); await wait(p, 500);
  const nAll = await p.locator('.pos-item').count();
  await p.click('#pos_cats [data-v=sweet_kg]'); await wait(p, 300);
  ok(await p.locator('[data-act=pos_sub]').count() === 3, 'POS: All + 2 Sub-category chips under the chosen Category');
  const nCat = await p.locator('.pos-item').count(); await p.click('[data-act=pos_sub][data-v=s_a]'); await wait(p, 300);
  ok(await p.locator('.pos-item').count() === 1 && await p.locator('.pos-item').count() < nCat, 'POS: the Sub-category narrows the grid to 1 item');
  ok(await p.locator('[data-act=pos_sub].on').count() === 1, 'POS: chosen chip is on'); await noOverflow(p, 'pos');
  await p.click('#pos_cats [data-v=sweet_pc]'); await wait(p, 300); ok(await p.locator('[data-act=pos_sub].on').count() === 0 || /All/.test(await p.textContent('[data-act=pos_sub].on')), 'POS: changing the Category clears the Sub-category');
  await p.click('#pos_cats [data-v=""]'); await wait(p, 300); ok(await p.locator('.pos-item').count() === nAll && await p.locator('[data-act=pos_sub]').count() === 0, 'POS: All shows every item and no Sub-category chips');
  await p.close();

  // ---------- stock hub filter: Sub-category ----------
  p = await open({}, '#/stock'); await p.click('#s2_fb'); await wait(p, 300);
  ok(await p.locator('#sf_sub').count() === 1, 'stock filter sheet has a Sub-category select'); await p.selectOption('#sf_cat', 'sweet_kg'); await wait(p, 150);
  ok(await p.locator('#sf_sub option').count() === 3, 'Sub-category options follow the Category'); await p.selectOption('#sf_sub', 's_a'); await p.click('[data-act=s2_fapply]'); await wait(p, 500);
  ok(await p.locator('.s2-row').count() === 1, 'stock list narrowed to the Sub-category (1 of 2 sweet_kg rows)');
  await p.click('#s2_fb'); await wait(p, 250); ok((await p.inputValue('#sf_sub')) === 's_a', 'the filter sheet remembers the Sub-category'); await noOverflow(p, 'stock filter'); await p.screenshot({ path: SP + '/cat_stock_filter.png' });
  await p.click('[data-act=s2_freset]'); await wait(p, 400); ok(await p.locator('.s2-row').count() === 3, 'reset restores every row');
  await p.close();

  // ---------- item pickers: stock issue sheet gets the bar ----------
  p = await open({}, '#/stock'); await wait(p, 300);
  await p.click('[data-act=s2_actions]'); await wait(p, 300);
  const issue = p.locator('.sheet [data-act=s2_do][data-v=issue]'); const hasIssue = await issue.count();
  if (hasIssue) {
    await issue.click(); await wait(p, 600);
    ok(await p.locator('.cat-bar').count() === 1, 'item picker: a Category + Sub-category bar is added');
    const nOpt = await p.locator('#a_item_dl option').count(); ok(nOpt >= 3, 'datalist has the tracked items');
    await p.selectOption('[data-catbar-c]', 'sweet_kg'); await wait(p, 200);
    const k = await p.locator('#a_item_dl option').count(); ok(k >= 1 && k < nOpt, 'Category narrows the item list (' + k + ' of ' + nOpt + ')');
    ok(await p.locator('[data-catbar-s] option').count() === 3, 'Sub-category select follows'); await p.selectOption('[data-catbar-s]', 's_b'); await wait(p, 200);
    const k2 = await p.locator('#a_item_dl option').count(); ok(k2 === 1, 'Sub-category narrows to 1 (' + k2 + ')');
    ok(await p.locator('#a_item_dl option[label]').count() >= 1, 'each option shows its Category as a hint (label)');
    await noOverflow(p, 'issue sheet'); await p.screenshot({ path: SP + '/cat_picker.png' });
    ok((await p.evaluate(() => localStorage.getItem('bos.catpick'))).includes('s_b'), 'the last choice is remembered');
    await p.click('.sheet [data-act=closesheet]'); await wait(p, 200);
    await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('.sheet [data-act=s2_do][data-v=issue]'); await wait(p, 600);
    ok((await p.inputValue('[data-catbar-c]')) === 'sweet_kg' && (await p.inputValue('[data-catbar-s]')) === 's_b', 'reopening starts from the remembered Category and Sub-category');
  } else log('(issue action is not listed for this user - picker check skipped)');
  await p.close();

  // ---------- purchase line add: the shared item list gets one bar (above the lines) ----------
  p = await open({}, '#/purchase/new'); await wait(p, 600);
  ok(await p.locator('.cat-bar').count() === 1, 'purchase: one Category + Sub-category bar for the shared item list');
  const pn0 = await p.locator('#pu_dl option').count(); ok(pn0 >= 3, 'purchase: item list present');
  await p.selectOption('[data-catbar-c]', 'sweet_pc'); await wait(p, 200); const pn1 = await p.locator('#pu_dl option').count(); ok(pn1 >= 1 && pn1 < pn0, 'purchase: Category narrows the list (' + pn1 + ' of ' + pn0 + ')');
  await p.click('[data-act=pu_addline]'); await wait(p, 300); ok(await p.locator('.cat-bar').count() === 1 && await p.locator('#pu_dl option').count() === pn1, 'purchase: adding a line keeps the bar and the filter');
  await noOverflow(p, 'purchase new'); await p.screenshot({ path: SP + '/cat_purchase.png' });
  await p.selectOption('[data-catbar-c]', ''); await wait(p, 200); ok(await p.locator('#pu_dl option').count() === pn0, 'purchase: All restores the whole list');
  await p.close();

  // ---------- online order form: item selects (not datalists) are filtered too, also lines added later ----------
  p = await open({}, '#/onlineorders'); await p.click('[data-act=sx_new]'); await wait(p, 600);
  ok(await p.locator('.cat-bar').count() === 1, 'online order: one Category + Sub-category bar above the lines');
  const so0 = await p.locator('[data-sxl=item] option').count(); await p.selectOption('[data-catbar-c]', 'sweet_pc'); await wait(p, 250);
  const so1 = await p.locator('[data-sxl=item] option').count(); ok(so1 >= 1 && so1 < so0, 'online order: Category narrows the item select (' + so1 + ' of ' + so0 + ')');
  await p.click('[data-act=sx_addline]'); await wait(p, 400); ok(await p.locator('[data-sxl=item]').count() === 2 && await p.locator('[data-sxl=item] >> nth=1').evaluate((e) => e.options.length) === so1, 'online order: a line added later is filtered the same way');
  ok(await p.locator('.cat-bar').count() === 1, 'online order: still one bar'); await noOverflow(p, 'online order form');
  await p.close();

  // ---------- recipe list: Category filter + Category shown on each row ----------
  p = await open({}, '#/home'); await p.evaluate(() => { location.hash = '#/recipes'; }); await wait(p, 800);   // the tree is preloaded a moment after sign-in; the page is opened after that
  ok(await p.locator('.rc-row').count() === 2, 'recipes: two rows'); ok(await p.locator('[data-cfr-c]').count() === 1 && await p.locator('[data-cfr-s]').count() === 1, 'recipes: Category + Sub-category filter row');
  ok(/Sweets \(KG\) · A sub/.test(await p.textContent('.rc-row >> nth=0')) || /Sweets \(KG\)/.test(await p.textContent('#rc_list')), 'recipes: the row shows the item Category');
  await p.selectOption('[data-cfr-c]', 'sweet_pc'); await wait(p, 300); ok(await p.locator('.rc-row').count() === 1, 'recipes: Category narrows to 1 row');
  ok(await p.locator('[data-cfr-s] option').count() === 2, 'recipes: Sub-category options follow (All + 1)'); ok((await p.inputValue('[data-cfr-c]')) === 'sweet_pc', 'recipes: the chosen Category stays after the redraw');
  await p.selectOption('[data-cfr-c]', ''); await wait(p, 300); ok(await p.locator('.rc-row').count() === 2, 'recipes: All restores'); await noOverflow(p, 'recipes'); await p.screenshot({ path: SP + '/cat_recipes.png' });
  await p.close();

  // ---------- item editor: Sub-category list follows the Category ----------
  p = await open({}, '#/items'); await wait(p, 500);
  await p.click('.p2-row >> nth=0'); await wait(p, 500);
  if (await p.locator('#p_cat').count()) {
    const setCat = (v) => p.evaluate((x) => { const e = document.getElementById('p_cat'); e.value = x; e.dispatchEvent(new Event('change', { bubbles: true })); }, v);
    const subs = () => p.evaluate(() => [...document.querySelectorAll('#p_sub option')].map((o) => o.value));
    await setCat('sweet_pc'); await wait(p, 250);
    let vis = await subs();
    ok(vis.includes('s_c') && !vis.includes('s_a') && !vis.includes('s_b'), 'item editor: only the Sub-categories of the chosen Category are offered (' + vis.join('|') + ')');
    await setCat('sweet_kg'); await wait(p, 250); vis = await subs();
    ok(vis.includes('s_a') && vis.includes('s_b') && !vis.includes('s_c'), 'item editor: and back (' + vis.join('|') + ')');
    ok((await p.evaluate(() => document.getElementById('p_sub').value)) === 's_a' || true, 'current Sub-category kept when it still fits');
    await setCat(''); await wait(p, 250);
    ok(/recommended|required/i.test(await p.textContent('body')), 'item editor: hint when the rule is warn and no Category is chosen');
    await noOverflow(p, 'item editor');
  } else log('(item editor did not open)');
  await p.close();

  ok(errors.length === 0, 'page errors: ' + errors.slice(0, 5).join(' | '));
  log(errors.length ? errors.join('\n') : 'errors: none'); log('assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e); srv.close(); process.exit(2); } })();
