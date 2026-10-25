// Manufacturing-cost screens (web/cost116.js, phases 116/117, step C1) in Chromium with a mocked supabase client (tests/web/stub.js + canned rpc answers).
// Run: node tests/web/cost116_test.js [abs tests/web dir]      (serves ../../web of this checkout)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR, PORT = _P.freePort();
const src = fs.readFileSync(SP + '/smoke.js', 'utf8');
const mkData = () => new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': ext === '.js' ? 'text/javascript' : ext === '.css' ? 'text/css' : ext === '.html' ? 'text/html' : 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const BN = /[ঀ-৿]/;
const ANS = {
  production_variance116: { location_id: 1, runs: 2, runs_with_standard: 1, rows: [
    { run_id: 'r1', made_at: '2026-10-05T08:00:00Z', code: 'FG-A', batches: 2, theoretical_output: 20, output: 18.5, actual_material: 3000, actual_conversion: 237, actual_total: 3237, standard_available: true, standard_total: 2990, price_var: 30.41, usage_var: 225, conv_var: 15, total_var: 247, yield_loss_money: 242.78, complete: true, conversion_provisional: false },
    { run_id: 'r2', made_at: '2026-10-06T08:00:00Z', code: 'FG-B', batches: 1, theoretical_output: 10, output: 10, actual_total: 500, complete: false, why: 'no_standard', yield_loss_money: 0 }],
    totals: { price_var: 30.41, usage_var: 225, conv_var: 15, total_var: 270.41, actual_total: 3237, standard_total: 2990, yield_loss_money: 242.78 } },
  production_cost_queue116: [
    { run_id: 'run-u', made_at: '2026-10-03T08:00:00Z', code: 'FG-A', output: 20, unit_cost: 40, conversion_mode: 'pool', reason: 'ingredient_cost_unknown', month: '2026-10-01' },
    { run_id: 'run-p', made_at: '2026-10-04T08:00:00Z', code: 'FG-B', output: 2, unit_cost: 30, conversion_mode: 'pool', reason: 'conversion_provisional', month: '2026-10-01' }],
  reprice_dry: { dry: true, location_id: 1, month: '2026-10-01', runs: 1, total_delta: 20, rows: [{ run_id: 'run-p', made_at: '2026-10-04T08:00:00Z', old_conversion: 60, new_conversion: 80, delta: 20, to_inventory: 12, to_cogs: 8, journal: true }], skipped: [{ run_id: 'x', why: 'ingredient_cost_unknown' }] },
  reprice_done: { dry: false, location_id: 1, month: '2026-10-01', runs: 1, total_delta: 20, rows: [{ run_id: 'run-p', made_at: '2026-10-04T08:00:00Z', old_conversion: 60, new_conversion: 80, delta: 20, to_inventory: 12, to_cogs: 8, journal: true }], skipped: [] },
  recost_dry: { dry: true, run_id: 'run-u', lines: [{ ledger_id: 1, item_id: 'i1', code: 'RAW-1', qty: 5, unit_cost: 60, amount: 300 }], material_known: 100, material_added: 300, material_new: 400, conversion: 0, unit_cost_new: 20 },
  recost_done: { dry: false, run_id: 'run-u', lines: [{ code: 'RAW-1', qty: 5, unit_cost: 60, amount: 300 }], material_new: 400, conversion: 0, unit_cost: 20, journal_reposted: true },
  pool_vs_gl117: { location_id: 1, month: '2026-10-01', rows: [{ type: 'GAS', label_en: 'Gas', pool: 3500, posted: 0 }, { type: 'LABOUR', label_en: 'Labour', pool: 2000, posted: 0 }], pool_total: 5500, posted_total: 0, absorbed_gl: 270, expense_gl: 0, expense_gl_from_pool: 0, expense_gl_other: 0, absorbed_exceeds_expense: true, unabsorbed_in_pnl: -270 },
  overhead_trueup117: { location_id: 1, month: '2026-10-01', rows: [{ type: 'GAS', label_en: 'Gas', label_bn: 'Gas', actual: 3500, absorbed: 200, unabsorbed: 3300 }], actual_total: 3500, absorbed_total: 270, over_absorbed_types: [{ type: 'LABOUR', over_absorbed: 12 }] },
  recipe_stage_cost116: { recipe_id: 'rc1', location_id: 1, unknown_cost: false, semi_finished_amount: 1066.67, other_amount: 60, lines: [
    { item_id: 'i9', code: 'CHHANA', kind: 'ingredient', semi_finished: true, qty: 2, avg_cost: 533.3333, amount: 1066.67, stage: { run_id: 'sr', material_cost: 1600, conversion_cost: 0, unit_cost: 533.3333 } },
    { item_id: 'i8', code: 'SUGAR', kind: 'ingredient', semi_finished: false, qty: 1, avg_cost: 60, amount: 60, stage: null }] },
};
const TABLES = {
  recipes: [{ id: 'rc1', item_id: 'fg1', version: 1, active: true }],
  items: [{ id: 'fg1', code: 'FG-S', name_bn: 'মিষ্টি', name_en: 'Sweet', item_type: 'finished_good' }],
  location_cost_cfg: [{ location_id: 1, driver116: 'batches', normal_units116: null, normal_batches116: 40, normal_labour_hours116: null }],
  cost_component_types: [{ code: 'GAS', label_en: 'Gas', label_bn: 'গ্যাস', active: true, driver116: 'output_kg' }],
};
const EXTRA = `(function(){ const T = ${JSON.stringify(TABLES)}; const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const from = c.from; window.__RC = [];
 const chain = (rows) => { const o = new Proxy({}, { get: (t, k) => (k === 'then' ? (f, g) => Promise.resolve({ data: rows, error: null }).then(f, g) : () => o) }); return o; };
 c.from = (t) => (T[t] ? chain(T[t]) : from.call(c, t));
 c.rpc = async (fn, args) => {
  if (fn === 'has_grant') { window.__RC.push([fn, args]); return { data: (window.__GRANTS || []).includes(args.p_code), error: null }; }
  if (/^(production_variance116|production_cost_queue116|production_reprice116|production_recost116|pool_vs_gl117|overhead_trueup117|recipe_stage_cost116|loc_cost_driver_set116|cost_type_driver_set116)$/.test(fn)) {
   window.__RC.push([fn, JSON.parse(JSON.stringify(args || {}))]); const A = window.__ANS || {}; let a = A[fn];
   if (fn === 'production_reprice116') a = args.p_dry ? A.reprice_dry : A.reprice_done; if (fn === 'production_recost116') a = args.p_dry ? A.recost_dry : A.recost_done;
   if (a && a.error) return { data: null, error: a.error }; return { data: a === undefined ? null : JSON.parse(JSON.stringify(a)), error: null }; }
  return rpc(fn, args); }; return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, pass = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else pass++; };
  // o.rules = rules that are ON; o.owner=false + o.perms/o.grants for a plain user
  async function open(hash, ans, o = {}) {
    const data = mkData();
    const ctx = await br.newContext({ viewport: { width: 400, height: 800 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_|Content Security Policy|Refused to execute/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};${o.owner === false ? 'window.__OWNER=false;' : ''}window.__PERMS=${o.owner === false ? '{}' : 'undefined'};window.__GRANTS=${JSON.stringify(o.grants || [])};window.__ANS=${JSON.stringify(ans)};try{localStorage.setItem('bos_lang',${JSON.stringify(o.lang || 'en')});}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/#/home'); await p.waitForTimeout(1200);
    // rules are read from BOS.ENV.rules: set which switches are ON, then go to the screen
    await p.evaluate((on) => { const r = {}; on.forEach((k) => { r[k] = { key: k, value: true, default_value: false }; }); window.BOS.ENV.rules = r; }, o.rules || []);
    await p.evaluate((h) => { location.hash = h; }, hash.replace(/^\//, '')); await p.waitForTimeout(o.wait || 1200);
    return { p, ctx };
  }
  const text = (p, sel) => p.evaluate((s) => (document.querySelector(s) || {}).innerText || '', sel);
  const calls = (p, fn) => p.evaluate((f) => window.__RC.filter((c) => !f || c[0] === f), fn);
  const ALLON = ['std_snapshot_auto116', 'conv_provisional116', 'cost_supply_to_avg116', 'pool_gl_post117', 'pool_drivers116', 'semi_finished_ingredient116'];

  // 1. variance: owner, English, switch on
  let { p, ctx } = await open('#/cost116var', ANS, { rules: ALLON });
  let body = await text(p, '#app');
  ok(/Standard vs actual/.test(body), 'variance title: ' + body.slice(0, 80));
  ok(!BN.test(body.replace(/মিষ্টি/g, '')), 'English mode: no Bangla letters on the variance screen');
  ok((await p.$$('#c6_tbl tbody tr')).length === 2, 'two run rows');
  ok(/Yield loss \(money\)/.test(body) && /242.78/.test(body) && /270.41/.test(body), 'yield loss in money and the total variance are shown');
  ok(/Price variance/.test(body) && /Usage variance/.test(body) && /Conversion variance/.test(body) && /No standard stored/.test(body), 'variance parts and the no-standard flag');
  ok((await p.$$('[data-c6-off]')).length === 0, 'switch on: no switch-off message');
  let cs = await calls(p, 'production_variance116');
  ok(cs.length >= 1 && cs[0][1].p_loc === 1 && /^\d{4}-\d\d-01$/.test(cs[0][1].p_from) && cs[0][1].p_use_latest === false, 'RPC args: place, month start, use_latest false');
  ok((await p.$$('a.tog[href="#/cost116queue"]')).length === 1, 'tab bar links to the other cost screens');
  await ctx.close();

  // 2. no cost right: a plain user without ITEM_COST or view_cost
  ({ p, ctx } = await open('#/cost116var', ANS, { owner: false }));
  body = await text(p, '#app');
  ok((await p.$$('#c6_nocost')).length === 1 && /cost right/.test(body), 'no cost right: clear message');
  ok((await calls(p, 'production_variance116')).length === 0 && (await p.$$('#c6_tbl')).length === 0, 'no cost right: no cost RPC called, no numbers');
  await ctx.close();
  // with the view_cost grant the same user sees the screen
  ({ p, ctx } = await open('#/cost116var', ANS, { owner: false, grants: ['view_cost'], rules: ALLON }));
  ok((await p.$$('#c6_tbl')).length === 1 && (await p.$$('#c6_nocost')).length === 0, 'view_cost grant: the table is there');
  await ctx.close();

  // 3. switch off: every screen says so
  for (const [route, key, re] of [['cost116var', 'std_snapshot_auto116', /Automatic standard snapshot/], ['cost116queue', 'conv_provisional116', /Provisional overhead/], ['cost116gl', 'pool_gl_post117', /Pool posted to the books/],
    ['cost116drv', 'pool_drivers116', /Pool drivers/], ['cost116stage', 'semi_finished_ingredient116', /Semi-finished as ingredient/]]) {
    ({ p, ctx } = await open('#/' + route, ANS, { rules: [] }));
    body = await text(p, '#app');
    ok((await p.$$(`[data-c6-off="${key}"]`)).length === 1 && re.test(body) && /This switch is off/.test(body), route + ': switch-off message names ' + key);
    await ctx.close();
    ({ p, ctx } = await open('#/' + route, ANS, { rules: [key] }));
    ok((await p.$$('[data-c6-off]')).length === 0, route + ': no message once ' + key + ' is on');
    await ctx.close();
  }

  // 4. queue: dry run first, then confirm to apply
  ({ p, ctx } = await open('#/cost116queue', ANS, { rules: ALLON }));
  body = await text(p, '#app');
  ok((await p.$$('#c6_qtbl tbody tr')).length === 2 && /Ingredient cost unknown/.test(body) && /Overhead provisional/.test(body), 'queue lists both runs with plain reasons');
  ok((await calls(p, 'production_reprice116')).length === 0, 'nothing is re-priced on load');
  await p.click('[data-act="c6_rp_check"]'); await p.waitForTimeout(300);
  cs = await calls(p, 'production_reprice116');
  ok(cs.length === 1 && cs[0][1].p_dry === true && /^\d{4}-\d\d-01$/.test(cs[0][1].p_month) && cs[0][1].p_loc === 1, 'check = ONE dry call');
  body = await text(p, '#c6_rpres');
  ok(/Dry run only: nothing was changed/.test(body) && /20/.test(body) && /Skipped/.test(body), 'dry result shown with the delta and skipped runs');
  await p.click('[data-act="c6_rp_apply"]'); await p.waitForTimeout(200);
  ok((await calls(p, 'production_reprice116')).length === 1 && (await p.$$('#c6_rpask')).length === 1, 'Apply only asks; no write yet');
  await p.click('[data-act="c6_rp_no"]'); await p.waitForTimeout(150);
  ok((await p.$$('#c6_rpask')).length === 0 && (await calls(p, 'production_reprice116')).length === 1, 'No: nothing written');
  await p.click('[data-act="c6_rp_apply"]'); await p.waitForTimeout(150); await p.click('[data-act="c6_rp_yes"]'); await p.waitForTimeout(400);
  cs = await calls(p, 'production_reprice116');
  ok(cs.length === 2 && cs[1][1].p_dry === false && cs[1][1].p_month === cs[0][1].p_month, 'Yes: the second call is the real one (p_dry false) for the same month');
  ok(/Applied/.test(await text(p, '#c6_rpres')), 'applied result shown');
  // re-cost one run: dry, then confirm
  await p.click('[data-act="c6_recost"][data-v="run-u"]'); await p.waitForTimeout(300);
  cs = await calls(p, 'production_recost116');
  ok(cs.length === 1 && cs[0][1].p_dry === true && cs[0][1].p_run === 'run-u', 're-cost starts as a dry call');
  body = await text(p, '#c6_rc'); ok(/RAW-1/.test(body) && /400/.test(body) && /Dry run only/.test(body), 're-cost dry result shows the ingredient and the new cost');
  await p.click('[data-act="c6_rc_apply"]'); await p.waitForTimeout(150);
  ok((await calls(p, 'production_recost116')).length === 1 && (await p.$$('#c6_rcask')).length === 1, 're-cost Apply only asks');
  await p.click('[data-act="c6_rc_yes"]'); await p.waitForTimeout(400);
  cs = await calls(p, 'production_recost116');
  ok(cs.length === 2 && cs[1][1].p_dry === false, 're-cost Yes: real call');
  await ctx.close();
  // a reprice refused by the server shows a message, not numbers
  ({ p, ctx } = await open('#/cost116queue', Object.assign({}, ANS, { reprice_dry: { error: { message: 'not allowed' } } }), { rules: ALLON }));
  await p.click('[data-act="c6_rp_check"]'); await p.waitForTimeout(300);
  ok((await p.$$('#c6_rp')).length === 0 && (await p.$$('[data-act="c6_rp_apply"]')).length === 0, 'refused dry run: no Apply button');
  await ctx.close();

  // 5. pool vs books
  ({ p, ctx } = await open('#/cost116gl', ANS, { rules: ALLON }));
  body = await text(p, '#app');
  ok(/Pool total/.test(body) && /5,500/.test(body) && /Expense in books/.test(body) && /Unabsorbed in the P&L/.test(body), 'pool vs books figures');
  ok((await p.$$('#c6_glwarn')).length === 1 && /charged more overhead than is an expense/.test(body), 'absorbed > expense gives the warning');
  ok((await p.$$('#c6_tu')).length === 1 && /Over-absorbed/.test(body), 'month true-up table and the over-absorbed line');
  cs = await calls(p); ok(cs.some((c) => c[0] === 'pool_vs_gl117') && cs.some((c) => c[0] === 'overhead_trueup117'), 'both RPCs called');
  await ctx.close();

  // 6. drivers: owner saves, a cost-right user only reads
  ({ p, ctx } = await open('#/cost116drv', ANS, { rules: ALLON }));
  ok((await p.$$('[data-c6-loc]')).length >= 1 && (await p.$$('[data-c6-type="GAS"]')).length === 1, 'drivers: place cards and cost-type card');
  await p.selectOption('[data-c6-loc="1"] [data-f="driver"]', 'labour_hours'); await p.fill('[data-c6-loc="1"] [data-f="h"]', '160');
  await p.click('[data-act="c6_dloc"][data-v="1"]'); await p.waitForTimeout(300);
  cs = await calls(p, 'loc_cost_driver_set116');
  ok(cs.length === 1 && cs[0][1].p_loc === 1 && cs[0][1].p_driver === 'labour_hours' && cs[0][1].p_normal_hours === 160 && cs[0][1].p_normal_units === null, 'loc driver RPC args');
  await p.selectOption('[data-c6-type="GAS"] [data-f="driver"]', 'batches'); await p.click('[data-act="c6_dtype"][data-v="GAS"]'); await p.waitForTimeout(300);
  cs = await calls(p, 'cost_type_driver_set116'); ok(cs.length === 1 && cs[0][1].p_code === 'GAS' && cs[0][1].p_driver === 'batches', 'cost-type driver RPC args');
  await p.fill('[data-c6-loc="1"] [data-f="b"]', 'abc'); await p.click('[data-act="c6_dloc"][data-v="1"]'); await p.waitForTimeout(200);
  ok((await calls(p, 'loc_cost_driver_set116')).length === 1, 'a bad number is not sent');
  await ctx.close();
  ({ p, ctx } = await open('#/cost116drv', ANS, { owner: false, grants: ['view_cost'], rules: ALLON }));
  ok((await p.$$('[data-act="c6_dloc"]')).length === 0 && /Only the owner can change this/.test(await text(p, '#app')), 'not owner: read only, no save button');
  await ctx.close();

  // 7. stage cost
  ({ p, ctx } = await open('#/cost116stage', ANS, { rules: ALLON }));
  body = await text(p, '#app');
  ok(/From semi-finished/.test(body) && /1,066.67/.test(body) && /CHHANA/.test(body) && /Semi-finished/.test(body) && /533.3333/.test(body), 'stage split shows the semi-finished share and its last run');
  cs = await calls(p, 'recipe_stage_cost116'); ok(cs.length === 1 && cs[0][1].p_recipe === 'rc1' && cs[0][1].p_loc === 1, 'stage RPC args');
  await ctx.close();

  // 8. Bangla mode
  ({ p, ctx } = await open('#/cost116var', ANS, { rules: [], lang: 'bn' }));
  body = await text(p, '#app'); ok(BN.test(body) && /স্ট্যান্ডার্ড বনাম আসল/.test(body) && /এই সুইচ বন্ধ আছে/.test(body), 'Bangla mode: Bangla title and switch-off message');
  await ctx.close();
  ({ p, ctx } = await open('#/cost116queue', ANS, { rules: ALLON, lang: 'mix' }));
  body = await text(p, '#app'); ok(/Cost-এর অপেক্ষা/.test(body) && /Re-cost/.test(body), 'mix mode: Bangla + English words');
  await ctx.close();

  // 9. registry
  ({ p, ctx } = await open('#/home', {}));
  const reg = await p.evaluate(() => ['cost116var', 'cost116queue', 'cost116gl', 'cost116drv', 'cost116stage'].map((r) => [r, !!(window.BOS_PAGES && window.BOS_PAGES[r]), !!(window.BOS.ia && window.BOS.ia.byRoute(r))]));
  ok(reg.every((x) => x[1] && x[2]), 'routes registered in BOS_PAGES and ia.js: ' + JSON.stringify(reg));
  await ctx.close();
  ok(errors.length === 0, 'no page or console errors: ' + errors.slice(0, 3).join(' | '));
  await br.close(); srv.close();
  console.log(`cost116_test: ${pass} passed, ${bad} failed`); process.exit(bad ? 1 : 0);
})();
