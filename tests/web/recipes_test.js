// W6: recipes / BOM page (#/recipes), editor, production sheet (+ stock hub button), can-make view, packaging rules, cost gating.
// Run: node recipes_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = 8362, srv = C.serve(PORT);
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables; const it = T.items;
  Object.assign(it[0], { item_type: 'finished_good', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true });
  Object.assign(it[1], { item_type: 'finished_good', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true });
  Object.assign(it[2], { item_type: 'resale', unit: 'pc', base_unit: 'piece', tracked: true, is_active: true });
  it.push({ id: 'rf1', code: 'R-001', name_bn: 'ময়দা', name_en: 'Flour', item_type: 'raw_material', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true },
          { id: 'rs1', code: 'R-002', name_bn: 'চিনি', name_en: 'Sugar', item_type: 'raw_material', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true },
          { id: 'pb1', code: 'P-001', name_bn: 'বাক্স', name_en: 'Box', item_type: 'packaging', unit: 'piece', base_unit: 'piece', tracked: true, is_active: true },
          { id: 'as1', code: 'A-001', name_bn: 'চেয়ার', name_en: 'Chair', item_type: 'asset', unit: 'piece', base_unit: 'piece', tracked: false, is_active: true });
  T.unit_conversions.push({ id: 90, item_id: 'rf1', from_unit: 'gram', to_unit: 'kg', factor: 0.001, active: true });
  const i0 = it[0].id, i1 = it[1].id;
  T.recipes = [
    { id: 'rc1', item_id: i0, version: 1, yield_qty: 2, yield_unit: null, active: true, note: null, used_at: '2026-10-01T00:00:00Z', created_at: '2026-10-01T00:00:00Z' },
    { id: 'rc2', item_id: i1, version: 1, yield_qty: 5, yield_unit: null, active: true, note: null, used_at: null, created_at: '2026-10-02T00:00:00Z' },
    { id: 'rc3', item_id: i1, version: 0, yield_qty: 5, yield_unit: null, active: false, note: null, used_at: null, created_at: '2026-09-02T00:00:00Z' }];
  T.recipe_lines = [
    { id: 1, recipe_id: 'rc1', ingredient_item_id: 'rf1', qty: 500, unit: 'gram', waste_pct: 10, note: null, sort: 1 },
    { id: 2, recipe_id: 'rc1', ingredient_item_id: 'rs1', qty: 0.2, unit: null, waste_pct: 0, note: null, sort: 2 },
    { id: 3, recipe_id: 'rc2', ingredient_item_id: 'rf1', qty: 1, unit: null, waste_pct: null, note: null, sort: 1 },
    { id: 4, recipe_id: 'rc3', ingredient_item_id: 'rf1', qty: 1, unit: null, waste_pct: 5, note: null, sort: 1 }];
  T.product_packaging = [{ id: 1, product_item_id: i0, packaging_item_id: 'pb1', qty_per_unit: 2, applies_to: 'sale', active: true, note: null }];
  T.rules.push({ key: 'packaging_consume_on', module: 'stock', kind: 'choice', value: o.pk || null, default_value: 'off', label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 });
  return data;
}
const EXTRA6 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.w6 = Object.assign({ err: {}, cost: true, onhand: { rf1: 10, rs1: 0.3 }, max: [] }, window.__W6 || {});
 c.rpc = async (fn, args) => {
  if (!/^(recipe_|packaging_set|production_|set_rule)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) { const m = W.err[fn]; if (!W.keep) delete W.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'recipe_save') { const id = 'n' + (T.recipes.length + 1); const v = Math.max(0, ...T.recipes.filter((r) => r.item_id === args.p_item).map((r) => r.version)) + 1;
    T.recipes.push({ id, item_id: args.p_item, version: v, yield_qty: args.p_yield_qty, yield_unit: args.p_yield_unit, active: true, note: args.p_note, used_at: null, created_at: '2026-10-12T00:00:00Z' });
    args.p_lines.forEach((l, i) => T.recipe_lines.push({ id: 100 + T.recipe_lines.length, recipe_id: id, ingredient_item_id: l.ingredient_item_id, qty: l.qty, unit: l.unit, waste_pct: l.waste_pct, note: l.note, sort: i + 1 })); return { data: { id, version: v }, error: null }; }
  if (fn === 'recipe_set_active') { T.recipes.find((r) => r.id === args.p_id).active = args.p_active; return { data: null, error: null }; }
  if (fn === 'recipe_copy') { const s = T.recipes.find((r) => r.id === args.p_from); const id = 'c' + T.recipes.length; T.recipes.push(Object.assign({}, s, { id, item_id: args.p_item || s.item_id, version: 1, used_at: null })); return { data: { id, version: 1 }, error: null }; }
  if (fn === 'packaging_set') { T.product_packaging.push({ id: 50, product_item_id: args.p_product, packaging_item_id: args.p_packaging, qty_per_unit: args.p_qty, applies_to: args.p_applies, active: args.p_active, note: null }); return { data: 50, error: null }; }
  if (fn === 'recipe_cost') { if (!W.cost) return { data: null, error: { message: 'not allowed', code: 'P0001' } };
    return { data: { recipe_id: args.p_recipe, complete: !W.partial, batch_cost: W.partial ? null : 154, unit_cost: W.partial ? null : 77, lines: [{ ingredient_item_id: 'rf1', unit_cost: 40, line_cost: 22 }, { ingredient_item_id: 'rs1', unit_cost: W.partial ? null : 60, line_cost: W.partial ? null : 12, waste_missing: true }] }, error: null }; }
  if (fn === 'production_preview') { const b = args.p_batches; const lines = T.recipe_lines.filter((l) => l.recipe_id === args.p_recipe).map((l) => { const it = T.items.find((i) => i.id === l.ingredient_item_id); const need = (l.unit === 'gram' ? l.qty / 1000 : l.qty) * b * (1 + (l.waste_pct || 0) / 100); const oh = W.onhand[l.ingredient_item_id] || 0;
      return { item_id: it.id, kind: 'ingredient', code: it.code, name_bn: it.name_bn, name_en: it.name_en, need: Math.round(need * 10000) / 10000, on_hand: oh, short: Math.max(need - oh, 0), unit: it.base_unit, tracked: true, unit_ok: true, waste_missing: l.waste_pct === null }; });
    return { data: { recipe_id: args.p_recipe, batches: b, yield_base: 2 * b, yield_unit: 'kg', lines, can_make: lines.every((l) => l.short <= 0), waste_missing: lines.filter((l) => l.waste_missing).length }, error: null }; }
  if (fn === 'production_can_make') return { data: clone(W.max), error: null };
  if (fn === 'production_post') return { data: { run_id: 'run1', qty: 6, consumed: [], waste_missing: 0, cost_complete: true }, error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA6 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__W6=${JSON.stringify(o.w || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };
  const i0 = base.tables.items[0].id, i1 = base.tables.items[1].id;
  const itemTxt = (idx) => base.tables.items[idx].code + ' · ' + (base.tables.items[idx].name_en || base.tables.items[idx].name_bn);

  // ---------- list ----------
  let p = await open({}, '#/recipes');
  ok(await p.locator('#rc_list .rc-row').count() === 2, 'two active recipes listed');
  ok(/Used/.test(await p.textContent('#rc_list .rc-row')) || /Used/.test(await p.textContent('#rc_list')), 'used version shows the frozen chip');
  ok(await p.locator('#rc_list .chip.warn').count() === 1 && /Data needed/.test(await p.textContent('#rc_list .chip.warn')), 'empty waste % shows Data needed');
  await p.screenshot({ path: SP + '/rc_list.png' }); await noOverflow(p, 'list');
  await p.click('[data-act=rc_f][data-v=all]'); await wait(p, 150); ok(await p.locator('#rc_list .rc-row').count() === 3, 'All shows the inactive one too');
  await p.click('[data-act=rc_f][data-v=off]'); await wait(p, 150); ok(await p.locator('#rc_list .rc-row').count() === 1 && /Inactive/.test(await p.textContent('#rc_list')), 'Inactive filter');
  await p.click('[data-act=rc_f][data-v=active]'); await wait(p, 150);
  await p.fill('#rc_q', 'zzzz'); await wait(p, 150); ok(await p.locator('#rc_list .rc-row').count() === 0, 'search narrows'); await p.fill('#rc_q', ''); await wait(p, 150);
  // menu on the used recipe
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 200);
  const mt = await p.textContent('.sheet');
  ok(/New version/.test(mt) && /Inactivate/.test(mt) && /Duplicate/.test(mt) && /Packaging/.test(mt) && /Show cost/.test(mt) && /Produce/.test(mt), 'menu: new version, inactivate, duplicate, packaging, cost, produce');
  await p.screenshot({ path: SP + '/rc_menu.png' }); await noOverflow(p, 'menu');
  await p.click('.sheet [data-act=rc_toggle]'); await wait(p, 400);
  let c = await calls(p, 'recipe_set_active'); ok(c.length === 1 && c[0].p_active === false, 'inactivate sends recipe_set_active(false)');
  ok(await p.locator('#rc_list .rc-row').count() === 1, 'inactivated recipe leaves the Active list');
  await p.close();

  // ---------- cost ----------
  p = await open({}, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 150); await p.click('.sheet [data-act=rc_cost]'); await wait(p, 400);
  ok(/৳ 154/.test(await p.textContent('.sheet')) && /৳ 77/.test(await p.textContent('.sheet')), 'cost sheet shows batch and unit cost');
  await p.screenshot({ path: SP + '/rc_cost.png' }); await noOverflow(p, 'cost');
  await p.close();
  p = await open({ w: { partial: true } }, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 150); await p.click('.sheet [data-act=rc_cost]'); await wait(p, 400);
  ok(/no known cost|Some ingredients/.test(await p.textContent('.sheet')) && !/৳ 154/.test(await p.textContent('.sheet')), 'unknown cost: no total, Data needed');
  await p.close();

  // ---------- editor: new recipe ----------
  p = await open({}, '#/recipes');
  await p.click('[data-act=rc_new]'); await wait(p, 500);
  ok(await p.locator('#rc_item').count() === 1, 'editor opens');
  await p.fill('#rc_item', itemTxt(0)); await p.dispatchEvent('#rc_item', 'change'); await wait(p, 200);
  await p.fill('#rc_yq', '3');
  await p.fill('#rl_item_0', 'R-001 · Flour'); await p.dispatchEvent('#rl_item_0', 'change'); await wait(p, 200);
  ok((await p.locator('#rl_unit_0 option').allTextContents()).some((t) => /gram/i.test(t)), 'unit list includes the converted unit (gram)');
  await p.fill('#rl_qty_0', '500'); await p.selectOption('#rl_unit_0', 'gram');
  ok(await p.locator('#rl_wc_0').count() === 1, 'blank waste % shows Data needed');
  await p.click('[data-act=rc_addline]'); await wait(p, 200);
  await p.fill('#rl_item_1', 'R-002 · Sugar'); await p.dispatchEvent('#rl_item_1', 'change'); await wait(p, 200);
  await p.fill('#rl_qty_1', '0.2'); await p.fill('#rl_w_1', '5');
  ok(await p.locator('#rl_wc_0').count() === 1 && await p.locator('#rl_wc_1').count() === 0, 'only the blank line is marked');
  await p.screenshot({ path: SP + '/rc_editor.png' }); await noOverflow(p, 'editor');
  // validation: bad waste
  await p.fill('#rl_w_1', '150'); await p.click('#rc_go'); await wait(p, 200); ok(/0–100/.test(await toastTxt(p)) && (await calls(p, 'recipe_save')).length === 0, 'waste above 100 refused in the browser');
  await p.fill('#rl_w_1', '5'); await p.click('#rc_go'); await wait(p, 500);
  c = await calls(p, 'recipe_save'); ok(c.length === 1 && c[0].p_id === null && c[0].p_item === i0 && c[0].p_yield_qty === 3, 'recipe_save as a new version');
  ok(c[0].p_lines.length === 2 && c[0].p_lines[0].unit === 'gram' && c[0].p_lines[0].waste_pct === null && c[0].p_lines[1].waste_pct === 5 && c[0].p_lines[0].qty === 500, 'lines carry unit, qty and waste (empty = null)');
  ok(typeof c[0].p_client === 'string' && c[0].p_client.length > 20, 'client id sent');
  await p.close();
  // ingredient picker: only raw / packaging / resale
  p = await open({}, '#/recipes/new'); await wait(p, 300);
  const opts = await p.locator('#rl_dl option').evaluateAll((os) => os.map((o) => o.value));
  ok(opts.length === 4 && !opts.some((v) => /A-001/.test(v)) && opts.some((v) => /R-001/.test(v)), 'ingredient picker offers raw material / packaging / resale only (no asset)');
  const fopts = await p.locator('#rc_idl option').evaluateAll((os) => os.map((o) => o.value)); ok(fopts.length === 2, 'product picker offers finished goods only');
  await p.close();

  // ---------- editor: used version => new version ----------
  p = await open({}, '#/recipes/rc1'); await wait(p, 400);
  ok(/NEW version|new version/i.test(await p.textContent('.notice.warn')) && await p.locator('#rc_item[disabled]').count() === 1, 'used version: banner, product locked');
  ok(await p.locator('#rc_lines .rc-line').count() === 2 && (await p.inputValue('#rl_qty_0')) === '500', 'lines loaded');
  await p.fill('#rl_w_0', '12'); await p.click('#rc_go'); await wait(p, 500);
  c = await calls(p, 'recipe_save'); ok(c.length === 1 && c[0].p_id === null && c[0].p_item === i0 && c[0].p_lines[0].waste_pct === 12 && c[0].p_retire_old === true, 'saving a used version sends p_id null (new version) and retires the old by default');
  await p.close();
  p = await open({}, '#/recipes/rc2'); await wait(p, 400);
  ok(await p.locator('.notice.warn').count() === 0, 'unused version: editable in place, no banner');
  await p.click('#rc_go'); await wait(p, 400); c = await calls(p, 'recipe_save'); ok(c.length === 1 && c[0].p_id === 'rc2', 'unused version saved in place (p_id given)');
  await p.close();

  // ---------- duplicate / new version from the menu ----------
  p = await open({}, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 150); await p.click('.sheet [data-act=rc_dup]'); await wait(p, 200);
  await p.fill('#dp_item', itemTxt(1)); await p.click('[data-act=rc_dupgo]'); await wait(p, 400);
  c = await calls(p, 'recipe_copy'); ok(c.length === 1 && c[0].p_item === i1 && typeof c[0].p_client === 'string', 'duplicate to another product');
  await p.close();
  p = await open({}, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 150); await p.click('.sheet [data-act=rc_newver]'); await wait(p, 500);
  ok(await p.locator('.notice.warn').count() === 1, 'New version opens the editor in new-version mode');
  await p.close();

  // ---------- production sheet ----------
  p = await open({}, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 150); await p.click('.sheet [data-act=rc_make]'); await wait(p, 300);
  ok(await p.locator('#pr_rec').count() === 1 && (await p.inputValue('#pr_rec')) === 'rc1', 'production sheet preselects the recipe');
  await p.fill('#pr_b', '3'); await wait(p, 700);
  let pv = await calls(p, 'production_preview'); ok(pv.length >= 1 && pv[pv.length - 1].p_batches === 3 && pv[pv.length - 1].p_recipe === 'rc1', 'preview asked for 3 batches');
  ok(/1\.65/.test(await p.textContent('#pr_pv')), 'preview: flour 500 g x 3 x 1.10 = 1.65 kg');
  ok(await p.locator('#pr_pv .chip.bad').count() === 1 && await p.locator('#pr_short').count() === 1, 'sugar shown short (0.6 needed, 0.3 on hand) with a warning');
  await p.screenshot({ path: SP + '/rc_prod.png' }); await noOverflow(p, 'production sheet');
  await p.click('#pr_go'); await wait(p, 500);
  c = await calls(p, 'production_post'); ok(c.length === 1 && c[0].p_recipe === 'rc1' && c[0].p_batches === 3 && c[0].p_loc === 1 && typeof c[0].p_client === 'string' && c[0].p_client.length > 20, 'production_post with loc, recipe, batches, client id');
  ok(/Production saved/.test(await toastTxt(p)), 'success toast');
  await p.close();
  // server refusals shown nicely
  p = await open({ w: { err: { production_post: 'insufficient_stock' } } }, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 150); await p.click('.sheet [data-act=rc_make]'); await wait(p, 300); await p.fill('#pr_b', '1'); await wait(p, 600);
  await p.click('#pr_go'); await wait(p, 400); ok(/Not enough stock/.test(await toastTxt(p)) && await p.locator('.sheet').count() === 1, 'shortage refusal: toast, sheet stays open');
  await p.close();
  p = await open({ w: { err: { production_post: 'recipe_inactive' } } }, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 150); await p.click('.sheet [data-act=rc_make]'); await wait(p, 300); await p.fill('#pr_b', '1'); await wait(p, 600);
  await p.click('#pr_go'); await wait(p, 400); ok(/inactive/i.test(await toastTxt(p)), 'recipe_inactive shown'); await p.close();

  // ---------- can make now ----------
  p = await open({ w: { max: [
    { recipe_id: 'rc1', item_id: i0, version: 1, code: 'I-001', name_bn: 'সাদা মিষ্টি', name_en: 'White sweet', max_batches: 8.3333, limiting_item_id: 'rf1', unknown: false, yield_per_batch: 2, yield_unit: 'kg' },
    { recipe_id: 'rc2', item_id: i1, version: 1, code: 'I-002', name_bn: 'কালো মিষ্টি', name_en: 'Black sweet', max_batches: 0, limiting_item_id: 'rs1', unknown: false, yield_per_batch: 5, yield_unit: 'kg' },
    { recipe_id: 'x', item_id: i1, version: 1, code: 'I-003', name_bn: 'আরেক', name_en: 'Another', max_batches: null, limiting_item_id: null, unknown: true, yield_per_batch: 1, yield_unit: 'kg' }] } }, '#/recipes/make');
  await wait(p, 400);
  ok(await p.locator('#mk_list .rc-row').count() === 3, 'three recipes in the can-make view');
  ok(/8\.3333/.test(await p.textContent('#mk_list .rc-row:first-child')) && /Flour/.test(await p.textContent('#mk_list .rc-row:first-child')), 'max batches and limiting ingredient');
  ok(await p.locator('#mk_list .rc-row.mk.bad').count() === 1 && /Data needed/.test(await p.textContent('#mk_list')), 'zero stock = bad edge; unknown = Data needed');
  await p.screenshot({ path: SP + '/rc_make.png' }); await noOverflow(p, 'can make');
  await p.click('#mk_list .rc-row:first-child'); await wait(p, 300); ok((await p.inputValue('#pr_rec')) === 'rc1' && (await p.inputValue('#pr_b')) === '1', 'tapping a row opens the production sheet for it');
  await p.close();

  // ---------- packaging ----------
  p = await open({}, '#/recipes/packaging');
  ok(await p.locator('#rc_main .rc-row').count() === 1 && /Box/.test(await p.textContent('#rc_main')) && /Sale/.test(await p.textContent('#rc_main')), 'packaging rule listed');
  ok(/Off/.test(await p.textContent('#rc_main .tog.on')) && /not taken out automatically/.test(await p.textContent('#rc_main')), 'setting off by default, explained');
  await p.click('[data-act=rc_pkmode][data-v=sale]'); await wait(p, 400);
  c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'packaging_consume_on' && c[0].p_value === 'sale', 'owner switches the setting (set_rule)');
  await p.screenshot({ path: SP + '/rc_pack.png' }); await noOverflow(p, 'packaging');
  await p.click('[data-act=rc_pkedit]'); await wait(p, 200);
  const popts = await p.locator('#pk_il option').evaluateAll((os) => os.map((o) => o.value)); ok(popts.length === 1 && /P-001/.test(popts[0]), 'packaging picker offers packaging items only');
  await p.fill('#pk_prod', itemTxt(1)); await p.fill('#pk_item', 'P-001 · Box'); await p.fill('#pk_q', '0.5'); await p.selectOption('#pk_ap', 'production'); await p.click('[data-act=rc_pksave]'); await wait(p, 400);
  c = await calls(p, 'packaging_set'); ok(c.length === 1 && c[0].p_product === i1 && c[0].p_packaging === 'pb1' && c[0].p_qty === 0.5 && c[0].p_applies === 'production' && c[0].p_active === true, 'packaging_set sent');
  await p.close();

  // ---------- stock hub: recipe button on "Production in" ----------
  p = await open({}, '#/stock');
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('.s2-act[data-v=prod]'); await wait(p, 300);
  ok(await p.locator('[data-act=rc_prodopen]').count() === 1 && await p.locator('#a_go').count() === 1, 'stock Production in keeps the old form and adds the recipe button');
  await p.click('[data-act=rc_prodopen]'); await wait(p, 400); ok(await p.locator('#pr_rec').count() === 1, 'recipe button opens the recipe production sheet');
  await p.close();
  p = await open({ m: { errs: {} } }, '#/stock'); await p.close();

  // ---------- no grants: read only ----------
  p = await open({ owner: false, m: { grants: ['stock_production'] } }, '#/recipes');
  ok(await p.locator('[data-act=rc_new]').count() === 0, 'no recipe_manage: no New recipe button');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 200);
  const lt = await p.textContent('.sheet'); ok(/Produce/.test(lt) && !/Show cost/.test(lt), 'no view_cost: no cost entry');
  ok(await p.locator('.sheet [data-act=rc_toggle]').count() === 0 && await p.locator('.sheet [data-act=rc_dup]').count() === 0 && await p.locator('.sheet [data-act=rc_newver]').count() === 0, 'manage actions are not clickable');
  ok(await p.locator('.sheet .rc-lock').count() >= 3, 'locked rows shown in lock mode');
  await p.close();
  p = await open({ owner: false, hide: true, m: { grants: ['stock_production'] } }, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 200); ok(await p.locator('.sheet .rc-lock').count() === 0, 'hide mode: no locked rows');
  await p.close();
  p = await open({ owner: false, m: { grants: ['stock_production', 'view_cost'] } }, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 200); ok(/Show cost/.test(await p.textContent('.sheet')), 'view_cost holder sees the cost entry'); await p.close();
  p = await open({ owner: false, w: { cost: false }, m: { grants: ['stock_production', 'view_cost'] } }, '#/recipes');
  await p.click('#rc_list .rc-row:first-child [data-act=rc_menu]'); await wait(p, 200); await p.click('.sheet [data-act=rc_cost]'); await wait(p, 400);
  ok(/Not allowed/i.test(await toastTxt(p)) && !/৳/.test(await p.textContent('body')), 'server refusal of cost shows no figures'); await p.close();

  // ---------- Bangla ----------
  p = await open({ lang: 'bn' }, '#/recipes'); ok(/রেসিপি/.test(await p.textContent('header.top h1')), 'Bangla title'); await p.screenshot({ path: SP + '/rc_bn.png' }); await noOverflow(p, 'bangla list'); await p.close();

  await br.close();
  log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
