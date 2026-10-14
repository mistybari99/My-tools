// Step C: costing page (#/costing): recipe cost rows (raw / packaging / conversion + today's price), conversion-rate editor (blank amount allowed, typed hours, suggestion shown only),
// monthly pools, per-location method (owner only), true-up with the "অনাবশোষিত ওভারহেড" row, run costs, no access without the cost right, 360px phone width, Bangla.
// Run: node costing_test.js <abs tests/web dir> [shots dir]      (serves ../../web of THIS checkout and injects the script tags)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web'); const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = 8374;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from((b.toString('utf8').includes('src="costing.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="costing.js"></script></body>')));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.items.push({ id: 'fg1', code: 'F-001', name_bn: 'রসগোল্লা', name_en: 'Rasgulla', item_type: 'finished_good', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true });
  T.locations = [{ id: 1, code: 'main', name_bn: 'মেইন শোরুম', name_en: 'Main showroom', kind: 'showroom' }, { id: 5, code: 'fac', name_bn: 'মিষ্টি কারখানা', name_en: 'Sweet factory', kind: 'factory' }];
  T.recipes = [{ id: 'rc1', item_id: 'fg1', version: 1, active: true, yield_qty: 10 }];
  T.cost_component_types = [['labour', 'শ্রম / মজুরি', 'Labour'], ['gas', 'গ্যাস / জ্বালানি', 'Gas / fuel'], ['electricity', 'বিদ্যুৎ', 'Electricity'], ['licence_fee', 'লাইসেন্স ও ফি', 'Licence and fees'], ['other', '☐ অন্য: ______', 'Other: ______']].map((t) => ({ code: t[0], label_bn: t[1], label_en: t[2], active: true }));
  T.location_cost_cfg = [{ location_id: 5, mode: 'recipe', normal_monthly_output: null }];
  T.factory_cost_pools = [{ id: 1, location_id: 5, month: new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 7) + '-01', component_type: 'labour', period_kind: 'month', actual_amount: 5000, one_off: false, source: 'manual', active: true }];
  return data;
}
const COST = { recipe_id: 'rc1', complete: true, rows: [{ row: 'raw', amount: 444 }, { row: 'packaging', amount: 0 }, { row: 'conversion', amount: 100, mode: 'recipe', complete: false }], batch_cost: 544, unit_cost: 54.4,
  today: { batch_cost: 600, unit_cost: 60, gap_pct: 12.5, gap_warn: true } };
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.wc = Object.assign({ err: {}, comps: [{ id: 7, type: 'labour', label_bn: 'শ্রম', label_en: 'Labour', basis: 'per_labour_hour', amount: 50, hours_per_batch: null, incomplete: true }, { id: 8, type: 'gas', label_bn: 'গ্যাস', label_en: 'Gas', basis: 'per_unit', amount: null, incomplete: true }], sugg: 2 }, window.__WC || {});
 c.rpc = async (fn, args) => {
  if (!/^(recipe_cost|cost_type_add|pool_set|loc_cost_cfg_set|overhead_trueup|production_run_costs)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === 'recipe_cost') return { data: clone(W.cost), error: null };
  if (fn === 'recipe_cost_components_get') return { data: { recipe_id: args.p_recipe, components: clone(W.comps), incomplete: true, flag: 'রূপান্তর খরচ অসম্পূর্ণ', suggested_labour_hours: W.sugg }, error: null };
  if (fn === 'recipe_cost_component_set') return { data: { id: 99 }, error: null };
  if (fn === 'recipe_cost_component_retire') return { data: null, error: null };
  if (fn === 'cost_type_add') return { data: { code: 'x1' }, error: null };
  if (fn === 'pool_set') { T.factory_cost_pools.push({ id: 2, location_id: args.p_loc, month: args.p_month, component_type: args.p_type, period_kind: args.p_period_kind, actual_amount: args.p_amount, one_off: args.p_one_off, source: 'manual', active: true }); return { data: { id: 2 }, error: null }; }
  if (fn === 'loc_cost_cfg_set') { const r = T.location_cost_cfg.find((x) => x.location_id === args.p_loc); if (r) Object.assign(r, { mode: args.p_mode, normal_monthly_output: args.p_normal }); else T.location_cost_cfg.push({ location_id: args.p_loc, mode: args.p_mode, normal_monthly_output: args.p_normal }); return { data: null, error: null }; }
  if (fn === 'overhead_trueup') return { data: clone(W.trueup), error: null };
  if (fn === 'production_run_costs') return { data: clone(W.runs), error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('Spice hire'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const W = Object.assign({ cost: COST, trueup: { rows: [{ type: 'labour', label_bn: 'শ্রম / মজুরি', label_en: 'Labour', actual: 5000, absorbed: 60, unabsorbed: 4940 }, { type: 'gas', label_bn: 'গ্যাস', label_en: 'Gas', actual: null, absorbed: 30, unabsorbed: null }], actual_total: 5000, absorbed_total: 90, unabsorbed_overhead: 4910 },
      runs: [{ run_id: 'r1', made_at: '2026-10-10T05:00:00Z', status: 'done', code: 'F-001', output: 10, material_cost: 444, conversion_cost: 100, conversion_complete: false, unit_cost: 54.4, std_cost: 54.4, actual_cost: 54.4 }, { run_id: 'r2', made_at: '2026-10-11T05:00:00Z', status: 'void', code: 'F-001', output: 9, material_cost: 444, conversion_cost: 0, conversion_complete: true, unit_cost: 49.33, std_cost: 44.4, actual_cost: 49.33 }] }, o.w || {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__WC=${JSON.stringify(W)};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => { const w = window.innerWidth; const out = []; document.querySelectorAll('body *').forEach((e) => { const b = e.getBoundingClientRect(); if (b.width && b.right > w + 1) out.push(e.tagName + '.' + String(e.className).slice(0, 20) + ' r=' + Math.round(b.right)); }); return { ok: document.documentElement.scrollWidth <= w + 1, out: out.slice(0, 5) }; }); ok(r.ok, 'horizontal overflow ' + m + ' ' + JSON.stringify(r)); };

  // ---- no access without the cost right
  let p = await open({ owner: false, m: { grants: [] } }, '#/costing');
  ok(/cost right is needed/.test(await p.textContent('#cs_body')) && await p.locator('[data-act=cs_open]').count() === 0, 'no cost right: nothing is shown');
  await p.close();

  // ---- owner: recipe cost sheet
  p = await open({}, '#/costing');
  ok(await p.locator('[data-act=cs_tab]').count() === 5, 'five tabs');
  await p.click('[data-act=cs_open]'); await wait(p, 400);
  let c = await calls(p, 'recipe_cost'); ok(c.length === 1 && c[0].p_recipe === 'rc1' && c[0].p_loc === 5, 'recipe_cost asked for the factory place');
  const sh = await p.textContent('.sheet');
  ok(/Raw material/.test(sh) && /Packaging/.test(sh) && /Conversion cost/.test(sh) && /৳ 444/.test(sh) && /৳ 100/.test(sh), 'raw / packaging / conversion are separate rows');
  ok(/৳ 544/.test(sh) && /৳ 54\.4/.test(sh), 'batch and unit cost shown');
  ok(/Today's purchase price/.test(sh) && /৳ 600/.test(sh) && /12\.5%/.test(sh) && /Gap above the limit/.test(sh), "today's price row with gap % and the warning chip");
  ok(/Conversion cost incomplete/.test(sh), 'incomplete conversion is flagged');
  ok(/2 h/.test(sh) && /never added to cost by itself/.test(sh), 'labour suggestion shown only as a suggestion');
  ok(/Previous values are kept/.test(sh), 'history note');
  await p.screenshot({ path: OUT + '/cs_recipe.png' }); await noOverflow(p, 'recipe sheet');
  // add a rate: blank amount is allowed and sent as null
  await p.click('[data-act=cs_rcnew]'); await wait(p, 200);
  await p.selectOption('#cr_type', 'electricity'); await p.selectOption('#cr_basis', 'per_batch'); await p.fill('#cr_amt', '');
  await p.click('[data-act=cs_rcsave]'); await wait(p, 400);
  c = await calls(p, 'recipe_cost_component_set'); ok(c.length === 1 && c[0].p_type === 'electricity' && c[0].p_amount === null && c[0].p_basis === 'per_batch' && typeof c[0].p_client === 'string', 'blank amount sent as null (stays blank), with a client id');
  await p.click('[data-act=cs_rcnew]'); await wait(p, 200);
  await p.selectOption('#cr_type', 'labour'); await p.selectOption('#cr_basis', 'per_labour_hour'); await p.fill('#cr_amt', '৫০'); await p.fill('#cr_hrs', '2');
  ok(/2 h/.test(await p.textContent('.sheet')), 'suggestion beside the hours box');
  await p.click('[data-act=cs_rcsave]'); await wait(p, 400);
  c = await calls(p, 'recipe_cost_component_set'); ok(c.length === 2 && c[1].p_amount === 50 && c[1].p_hours === 2 && c[1].p_basis === 'per_labour_hour', 'typed hours and Bangla-digit amount sent');
  await p.click('[data-act=cs_rcnew]'); await wait(p, 200);
  await p.selectOption('#cr_type', '__new'); await p.fill('#cr_amt', '7'); await p.click('[data-act=cs_rcsave]'); await wait(p, 500);
  c = await calls(p, 'cost_type_add'); ok(c.length === 1 && c[0].p_label_bn === 'Spice hire', 'a new cost type is added by name');
  c = await calls(p, 'recipe_cost_component_set'); ok(c.length === 3 && c[2].p_type === 'x1', 'and then used');
  await p.click('[data-act=cs_rcret]'); await wait(p, 300); ok((await calls(p, 'recipe_cost_component_retire')).length === 1, 'retire sends the id');
  await p.close();

  // ---- pools
  p = await open({}, '#/costing'); await p.click('[data-act=cs_tab][data-v=pool]'); await wait(p, 400);
  ok(await p.locator('[data-t]').count() === 5, 'one row per cost type');
  ok(await p.locator('[data-t=labour] [data-cs-amt]').inputValue() === '5000', 'existing pool amount loaded');
  ok(/not here/.test(await p.textContent('#cs_pane')), 'showroom/admin note');
  await p.fill('[data-t=gas] [data-cs-amt]', '3000'); await p.check('[data-t=gas] [data-cs-oneoff]'); await p.click('[data-t=gas] [data-act=cs_poolsave]'); await wait(p, 400);
  c = await calls(p, 'pool_set'); ok(c.length === 1 && c[0].p_type === 'gas' && c[0].p_amount === 3000 && c[0].p_one_off === true && c[0].p_period_kind === 'month' && /-01$/.test(c[0].p_month) && c[0].p_loc === 5, 'pool_set with place, month, amount, one-off flag');
  await p.fill('[data-t=licence_fee] [data-cs-amt]', '12000'); await p.check('[data-t=licence_fee] [data-cs-year]'); await p.click('[data-t=licence_fee] [data-act=cs_poolsave]'); await wait(p, 400);
  c = await calls(p, 'pool_set'); ok(c.length === 2 && c[1].p_period_kind === 'year', 'a yearly amount is sent as period year');
  await p.fill('[data-t=electricity] [data-cs-amt]', 'abc'); await p.click('[data-t=electricity] [data-act=cs_poolsave]'); await wait(p, 200);
  ok((await calls(p, 'pool_set')).length === 2, 'a blank / bad pool amount is not sent');
  await p.screenshot({ path: OUT + '/cs_pool.png' }); await noOverflow(p, 'pools');
  await p.close();

  // ---- per-location method
  p = await open({}, '#/costing'); await p.click('[data-act=cs_tab][data-v=loc]'); await wait(p, 300);
  ok(await p.locator('[data-l]').count() === 2, 'one card per place');
  ok(await p.locator('[data-l="5"] [data-cs-mode]').inputValue() === 'recipe', 'current mode shown');
  await p.selectOption('[data-l="5"] [data-cs-mode]', 'pool'); await p.fill('[data-l="5"] [data-cs-normal]', '1,000'.replace(',', '')); await p.click('[data-l="5"] [data-act=cs_locsave]'); await wait(p, 400);
  c = await calls(p, 'loc_cost_cfg_set'); ok(c.length === 1 && c[0].p_loc === 5 && c[0].p_mode === 'pool' && c[0].p_normal === 1000, 'mode + normal output sent');
  await p.fill('[data-l="1"] [data-cs-normal]', ''); await p.click('[data-l="1"] [data-act=cs_locsave]'); await wait(p, 300);
  c = await calls(p, 'loc_cost_cfg_set'); ok(c.length === 2 && c[1].p_normal === null && c[1].p_mode === 'off', 'a blank normal output stays blank (null)');
  await p.screenshot({ path: OUT + '/cs_loc.png' }); await noOverflow(p, 'location tab');
  await p.close();
  p = await open({ owner: false, m: { grants: ['view_cost'] } }, '#/costing'); await p.click('[data-act=cs_tab][data-v=loc]'); await wait(p, 300);
  ok(await p.locator('[data-act=cs_locsave]').count() === 0 && await p.locator('[data-l="5"] [data-cs-mode][disabled]').count() === 1 && /Only the owner/.test(await p.textContent('#cs_pane')), 'cost-right holder who is not the owner: read only');
  await p.close();

  // ---- true-up and runs
  p = await open({}, '#/costing'); await p.click('[data-act=cs_tab][data-v=true]'); await wait(p, 200); await p.click('[data-act=cs_true]'); await wait(p, 400);
  c = await calls(p, 'overhead_trueup'); ok(c.length === 1 && c[0].p_loc === 5 && /-01$/.test(c[0].p_month), 'true-up asked for place + month');
  ok(/Unabsorbed overhead/.test(await p.textContent('#cs_unabs')) && /4,910/.test(await p.textContent('#cs_unabs')), 'the unabsorbed overhead row');
  ok(/no actual entered/.test(await p.textContent('#cs_pane')), 'a type with no actual says so, no zero guessed');
  await p.screenshot({ path: OUT + '/cs_true.png' }); await noOverflow(p, 'true-up');
  await p.click('[data-act=cs_tab][data-v=runs]'); await wait(p, 200); await p.click('[data-act=cs_runs]'); await wait(p, 400);
  ok(await p.locator('#cs_pane .card').count() === 3 && /Conversion cost incomplete/.test(await p.textContent('#cs_pane')) && /Void/.test(await p.textContent('#cs_pane')), 'run costs: two runs, incomplete + void marked');
  ok(/৳ 54\.4/.test(await p.textContent('#cs_pane')) && /Standard/.test(await p.textContent('#cs_pane')), 'unit, standard and actual cost shown');
  await noOverflow(p, 'runs'); await p.close();

  // ---- Bangla
  p = await open({ lang: 'bn' }, '#/costing');
  ok(/খরচ/.test(await p.textContent('header.top h1')), 'Bangla title');
  await p.click('[data-act=cs_open]'); await wait(p, 400);
  ok(/রূপান্তর খরচ অসম্পূর্ণ/.test(await p.textContent('.sheet')) && /আজকের কেনা দাম/.test(await p.textContent('.sheet')), 'Bangla labels on the cost sheet');
  await p.screenshot({ path: OUT + '/cs_bn.png' }); await noOverflow(p, 'Bangla sheet');
  await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
