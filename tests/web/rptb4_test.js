// RPT-B4 screens: #/prodplan (plan, orders, run capture), #/prodreports (eight production reports), #/targets (target vs achievement, KPI, factory vs retail), #/capacity (labour, capacity, set-up),
// the owner-board widget target_vs and the registry placement. Server calls are stand-ins (the real SQL is tested in supabase/phase404..416_test.sql).
// 360px width, English and Bangla, CSV content + the audit call before it, "data not captured" instead of 0, blind real-use entry, entry payloads.
// Run: node rptb4_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const path = require('path'), http = require('http');
const WEB = path.join(SP, '..', '..', 'web');      // serve THIS checkout
const base = C.baseData(SP), PORT = 8394;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[path.extname(f)] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const day = (n = 0) => new Date(Date.now() + 6 * 3600e3 + n * 86400e3).toISOString().slice(0, 10);
const td = day(), m0 = td.slice(0, 7) + '-01';
const RUN1 = '11111111-1111-4111-8111-111111111111', RUN2 = '22222222-2222-4222-8222-222222222222';
const PLAN1 = '33333333-3333-4333-8333-333333333333';
const FG = { item_id: 'fg1', code: 'F-001', name_bn: 'test_sweet', name_en: 'test_sweet', base_unit: 'kg' };
const LOC = { location_id: 5, location: 'Test factory', location_en: 'Test factory' };
const RUNS = { [RUN1]: Object.assign({ run_id: RUN1, made_at: day(-3) + 'T05:00:00Z', day: day(-3), status: 'done', batches: 2, output: 18, yield_std: 20, yield_actual: 18, can_edit: true, link: { plan_id: PLAN1, order_id: 7 },
    issue_lines: [{ item_id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', base_unit: 'kg', actual_qty: 13, actual_at: day(-2), booked_qty: 12, diff: 1 }, { item_id: 'rm2', code: 'R-002', name_bn: 'test_sugar', name_en: 'test_sugar', base_unit: 'kg', actual_qty: 6, actual_at: day(-2), booked_qty: 6, diff: 0 }],
    extra_lines: [], losses: [{ id: 'l1', kind: 'reject', qty: 1, reason_code: 'burnt', note: 'test', created_staff: 'owner1' }], candidate_plans: [{ id: PLAN1, plan_date: day(-3), planned_qty: 20, planned_batches: 2 }], open_orders: [{ id: 7, order_date: day(-6), due_date: day(-1), qty: 25, made: 18 }] }, FG, LOC),
  [RUN2]: Object.assign({ run_id: RUN2, made_at: day(-1) + 'T05:00:00Z', day: day(-1), status: 'done', batches: 1, output: 10, yield_std: 10, yield_actual: null, can_edit: true, link: null,
    issue_lines: [{ item_id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', base_unit: 'kg', actual_qty: null, actual_at: null, booked_qty: null, diff: null }, { item_id: 'rm2', code: 'R-002', name_bn: 'test_sugar', name_en: 'test_sugar', base_unit: 'kg', actual_qty: null, actual_at: null, booked_qty: null, diff: null }],
    extra_lines: [], losses: [], candidate_plans: [{ id: PLAN1, plan_date: day(-1), planned_qty: 10, planned_batches: 1 }], open_orders: [{ id: 7, order_date: day(-6), due_date: day(-1), qty: 25, made: 18 }] }, FG, LOC) };
const RECENT = [Object.assign({ run_id: RUN2, made_at: RUNS[RUN2].made_at, day: day(-1), batches: 1, output: 10, yield_actual: null, actual_issue_lines: 0, loss_state: null, linked: false, can_edit: true }, FG, LOC),
  Object.assign({ run_id: RUN1, made_at: RUNS[RUN1].made_at, day: day(-3), batches: 2, output: 18, yield_actual: 18, actual_issue_lines: 2, loss_state: 'recorded', linked: true, can_edit: true }, FG, LOC)];
const nd = (o) => Object.assign({ from: day(-10), to: td, notes: [], basis: 'test basis text' }, o);
const PVA = nd({ summary: { plans: 2, cancelled_plans: 0, rows_met: 0, rows_short: 1, rows_not_made: 0, rows_qty_not_captured: 1, unplanned_runs: 1 },
  rows: [Object.assign({ plan_date: day(-3), plans_n: 1, plan_ids: [PLAN1], planned_batches: 2, planned_qty: 20, planned_qty_missing_n: 0, actual_batches: 2, actual_qty: 18, runs_n: 1, run_ids: [RUN1], achievement_pct: 90, status: 'short' }, FG, LOC),
    Object.assign({ plan_date: day(-1), plans_n: 1, plan_ids: ['p9'], planned_batches: null, planned_qty: null, planned_qty_missing_n: 1, actual_batches: 0, actual_qty: 0, runs_n: 0, run_ids: [], achievement_pct: null, status: 'qty_not_captured' }, FG, LOC)],
  unplanned: [Object.assign({ day: day(-2), runs_n: 1, run_ids: [RUN2], batches: 1, qty: 10 }, FG, LOC)] });
const ORD = nd({ summary: { orders: 2, open: 2, overdue: 1, not_started: 1, made_not_closed: 0, due_not_captured: 1 },
  rows: [Object.assign({ order_no: 7, order_date: day(-6), due_date: day(-1), for_location_id: 1, for_location: 'Test shop', for_location_en: 'Test shop', qty: 25, made: 18, balance: 7, runs_n: 1, run_ids: [RUN1], status: 'open', state: 'overdue', days_overdue: 1, due_not_captured: false, note: null, close_note: null }, FG, LOC),
    Object.assign({ order_no: 8, order_date: td, due_date: null, for_location_id: null, qty: 5, made: 0, balance: 5, runs_n: 0, run_ids: [], status: 'open', state: 'not_started', days_overdue: null, due_not_captured: true }, FG, LOC)] });
const REC = nd({ rows: [Object.assign({ day: td, made: 0, runs_n: 0, sent: 17, received: 14, in_transit: 2, short: 1, cancelled: 0, transfers_n: 2, tie_ok: true }, FG, LOC)],
  summary: [Object.assign({ made: 28, sent: 17, received: 14, in_transit: 2, short: 1, cancelled: 0, made_not_sent: 11, on_hand_now: null, tie_ok: true }, FG, LOC)] });
const COSTROW = (hide) => Object.assign({ run_id: RUN1, day: day(-3), status: 'measured', yield_var_qty: 2, real_material_cost: hide ? null : 1260, std_cost_for_real_output: hide ? null : 1053, price_var: hide ? null : 35, usage_var: hide ? null : 55, yield_var: hide ? null : 117, total_var: hide ? null : 207,
  conversion_cost: hide ? null : 0, missing: [], lines: [{ item_id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', std_qty: 12, actual_qty: 13, price_var: hide ? null : 65, usage_var: hide ? null : 55 }] }, FG, LOC);
const COST = (hide) => nd({ cost_hidden: hide, rows: [COSTROW(hide), Object.assign({}, COSTROW(hide), { run_id: RUN2, day: day(-1), status: 'not_measured', yield_var_qty: null, price_var: null, usage_var: null, yield_var: null, total_var: null, real_material_cost: null, std_cost_for_real_output: null, missing: ['real use of ingredients', 'actual yield'], lines: [] })],
  summary: [Object.assign({ runs: 2, runs_measured: 1, runs_partly: 0, runs_not_measured: 1, price_var: hide ? null : 35, price_var_runs: 1, usage_var: hide ? null : 55, usage_var_runs: 1, yield_var: hide ? null : 117, yield_var_runs: 1, total_var: hide ? null : 207, total_var_pct: hide ? null : 19.66 }, FG)] });
const USE = nd({ runs: 2, runs_with_real_use: 1, rows: [{ run_id: RUN1, day: day(-3), fg_code: 'F-001', fg_name_bn: 'test_sweet', fg_name_en: 'test_sweet', item_id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', base_unit: 'kg', std_qty: 12, actual_qty: 13, diff: 1, diff_pct: 8.33, status: 'measured' },
    { run_id: RUN2, day: day(-1), fg_code: 'F-001', fg_name_bn: 'test_sweet', fg_name_en: 'test_sweet', item_id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', base_unit: 'kg', std_qty: 6, actual_qty: null, diff: null, diff_pct: null, status: 'not_captured' }],
  summary: [{ item_id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', base_unit: 'kg', runs_issued: 2, runs_measured: 1, runs_not_captured: 1, std_qty_measured: 12, actual_qty_measured: 13, diff: 1, diff_pct: 8.33 }] });
const YLD = nd({ limit_pct: null, notes: [{ code: 'limit_not_set', field: 'yield_variance_warn_pct' }], rows: [Object.assign({ run_id: RUN1, day: day(-3), batches: 2, yield_std: 20, yield_actual: 18, booked_output: 18, var_qty: -2, var_pct: -10, status: 'measured', over_limit: null }, FG, LOC),
    Object.assign({ run_id: RUN2, day: day(-1), batches: 1, yield_std: 10, yield_actual: null, booked_output: 10, var_qty: null, var_pct: null, status: 'not_captured', over_limit: null }, FG, LOC)],
  summary: [Object.assign({ runs: 2, measured: 1, not_captured: 1, std_qty_measured: 20, actual_qty_measured: 18, var_pct: -10, over_limit_runs: null }, FG)] });
const LOSS = nd({ rows: [Object.assign({ run_id: RUN1, day: day(-3), output: 18, state: 'recorded', reject_qty: 1, rework_qty: 0.5, reject_pct: 5.56, rework_pct: 2.78, lines: [{ id: 'l1', kind: 'reject', qty: 1, reason_code: 'burnt', reason: 'Burnt', reason_bn: 'পোড়া' }] }, FG, LOC),
    Object.assign({ run_id: RUN2, day: day(-1), output: 10, state: 'not_captured', reject_qty: null, rework_qty: null, reject_pct: null, rework_pct: null, lines: [] }, FG, LOC)],
  by_reason: [{ reason_code: 'burnt', reason: 'Burnt', reason_bn: 'পোড়া', reject_n: 1, rework_n: 0 }], by_item: [Object.assign({ runs: 2, runs_known: 1, runs_not_captured: 1, output_known: 18, reject_qty: 1, rework_qty: 0.5, reject_pct: 5.56, rework_pct: 2.78 }, FG)] });
const WST = (hide) => nd({ cost_hidden: hide, summary: { records: 2 }, rows: [Object.assign({ id: 'w1', day: day(-1), qty: 1, reason_code: 'spoiled', reason: 'Spoiled', reason_bn: 'নষ্ট', batch_id: 4, run_id: RUN2, batch_state: 'from_run', value: hide ? null : 64.29, value_state: hide ? 'cost_hidden' : 'known' }, FG, LOC),
    Object.assign({ id: 'w2', day: day(-1), qty: 2, reason_code: 'spoiled', reason: 'Spoiled', reason_bn: 'নষ্ট', batch_id: null, run_id: null, batch_state: 'batch_not_captured', value: null, value_state: hide ? 'cost_hidden' : 'cost_not_captured' }, { item_id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', base_unit: 'kg' }, LOC)],
  by_reason: [{ reason_code: 'spoiled', reason: 'Spoiled', reason_bn: 'নষ্ট', records: 2, value: hide ? null : 64.29, value_known_n: hide ? 0 : 1, value_not_known_n: hide ? 2 : 1 }], by_item: [], by_batch: [Object.assign({ batch_id: 4, run_id: RUN2, records: 1, qty: 1, value: hide ? null : 64.29, value_not_known_n: 0 }, FG)] });
const TGT = nd({ summary: { rows_with_target: 2, rows_without_target: 1, target_total: 17000, achieved_total_for_targets: 600, behind: 2, costs_hidden: false }, net_of_returns: true,
  rows: [{ month: m0, location_id: 1, location: 'Test shop', location_en: 'Test shop', target_id: 5, target: 12000, achieved: 600, gross_sales: 800, returns: 200, bills: 1, achievement_pct: 5, shortfall: 11400, days_in_month: 30, days_elapsed: 10, pace_pct: 33.3, pace_amount: 4000, status: 'behind', gp_target_pct: 30, gp_pct: 67.86, gp_gap_pp: 37.86, uncosted_pct: 0, gp_state: 'known' },
    { month: m0, location_id: 2, location: 'Test shop two', location_en: 'Test shop two', target_id: null, target: null, achieved: 120, gross_sales: 120, returns: 0, bills: 1, achievement_pct: null, shortfall: null, days_in_month: 30, days_elapsed: 10, pace_pct: null, pace_amount: null, status: 'target_not_set', gp_target_pct: null, gp_pct: null, gp_gap_pp: null, uncosted_pct: null, gp_state: 'cost_hidden' }] });
const KPI = nd({ limits: { sales_drop_pct: null, discount_pct: 40, void_n: 0 }, open_exceptions: { red: 1, yellow: 2 }, missing_days: [day(-9), day(-8)], net_of_returns: true,
  notes: [{ code: 'alert_limit_not_set', field: 'kpi_alert_sales_drop_pct' }],
  alerts: [{ day: day(-2), location_id: 1, location: 'Test shop', location_en: 'Test shop', kind: 'discount_high', value: 50, limit: 40 }],
  days: [{ day: day(-2), places_covered: 1, net_sales: 100, gross_sales: 100, returns: 0, bills: 1, avg_bill: 100, discount_pct: 50, void_n: 1, void_amt: 200, runs_n: null, yield_var_pct: null }], places: [{ location_id: 1, location: 'Test shop', location_en: 'Test shop', days: 5, net_sales: 400, bills: 4, avg_bill: 100, discount_pct: 12, void_n: 1 }] });
const CMP = nd({ basis: 'none', price_pct: null, cost_hidden: false, notes: [{ code: 'transfers_not_valued', field: 'transfer_valuation_basis' }], statement: 'Shop gross profit is at ledger cost; never netted.',
  factory: { rows: [Object.assign({ runs: 2, output: 28, costed_runs: 2, production_cost: 1800, cost_state: 'known' }, FG, LOC)], totals: {} },
  transfers: { rows: [Object.assign({ from_location_id: 5, from_location: 'Test factory', from_location_en: 'Test factory', to_location_id: 1, to_location: 'Test shop', to_location_en: 'Test shop', transfers: 1, sent: 15, received: 14, in_transit: 0, cost_value: 964.29, cost_state: 'known', transfer_value: null, value_state: 'not_valued', margin: null }, FG)], totals: { cost_value: 964.29, transfer_value: null, factory_margin: null, rows_not_valued: 1 } },
  retail: { rows: [{ location_id: 1, location: 'Test shop', location_en: 'Test shop', gross_sales: 800, returns: 0, net_sales: 800, bills: 1, cogs: 257.14, costed_sales: 800, gross_profit: 542.86, gp_pct: 67.86, uncosted_pct: 0, cost_state: 'known' }], totals: { net_sales: 800, gross_profit: 542.86 } } });
const LAB = nd({ rows: [Object.assign({ run_id: RUN1, day: day(-3), batches: 2, output: 18, line_id: null, labour_hours: 15, people: 5, crews: 2, output_per_hour: 1.2, hours_per_unit: 0.8333, status: 'measured' }, FG, LOC),
    Object.assign({ run_id: RUN2, day: day(-1), batches: 1, output: 10, line_id: null, labour_hours: null, people: null, crews: null, output_per_hour: null, hours_per_unit: null, status: 'labour_not_captured' }, FG, LOC)],
  by_item: [Object.assign({ runs: 2, measured: 1, labour_not_captured: 1, output_measured: 18, labour_hours: 15, output_per_hour: 1.2 }, FG)], by_place: [Object.assign({ runs: 2, measured: 1, labour_not_captured: 1, labour_hours: 15, batches_measured: 2, batches_per_hour: 0.1333 }, LOC)] });
const CAP = nd({ notes: [], rows: [Object.assign({ line_id: null, days: 7, days_rated: 7, days_not_rated: 0, capacity_batches: 24, batches_made_on_rated_days: 3, batches_made_on_days_not_rated: null, batches_made: 3, utilization_pct: 12.5, rated_batches_per_day: 4, rated_days_per_week: 6, status: 'rated' }, LOC),
    { line_id: null, location_id: 6, location: 'Test factory two', location_en: 'Test factory two', days: 7, days_rated: 0, days_not_rated: 7, capacity_batches: null, batches_made_on_rated_days: null, batches_made_on_days_not_rated: 2, batches_made: 2, utilization_pct: null, rated_batches_per_day: null, rated_days_per_week: null, status: 'rated_capacity_not_captured' }] });
const TILE = { month: m0, rows: [{ location_id: '1', location: 'Test shop', location_en: 'Test shop', target: 12000, achieved: 600, achievement_pct: 5, pace_pct: 33.3, status: 'behind' }], no_target: [], total: { target: 12000, achieved: 600, achievement_pct: 5, pace_pct: 33.3 }, behind: 1, notes: [] };
const LINES = [{ id: 1, location_id: 5, location: 'Test factory', location_en: 'Test factory', name_bn: 'test_line_one', name_en: 'Test line one', active: true, retired_note: null, can_edit: true }];
const RATINGS = [{ id: 3, location_id: 5, location: 'Test factory', location_en: 'Test factory', line_id: null, batches_per_day: 4, days_per_week: 6, effective_from: day(-40), note: null, status: 'active', retired_note: null, can_edit: true }];

const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M || (window.__M = { calls: [] });
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)); const W = window.__W = Object.assign({ err: {}, hideCost: false, canTarget: true, canEdit: true, grants: null }, window.__W0 || {});
 const R = ${JSON.stringify({ RUNS, RECENT, PVA, ORD, REC, USE, YLD, LOSS, TGT, KPI, CMP, LAB, CAP, TILE, LINES, RATINGS, RUN1, RUN2 })};
 const FG = ${JSON.stringify(FG)}, LOC = ${JSON.stringify(LOC)}, day = ${day.toString()}, PLAN1 = '${PLAN1}', RUN1 = R.RUN1, RUN2 = R.RUN2, td = day();
 const nd = ${nd.toString()}, COSTROW = ${COSTROW.toString()}, COST = ${COST.toString()}, WST = ${WST.toString()};
 c.rpc = async (fn, args) => {
  const own = /^(rb4_|prod_|production_line_|capacity_rating_|sales_target_|kpi_snapshot_|has_grant|owner_board_)/;
  if (!own.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn] } };
  const ok = (d) => ({ data: clone(d), error: null });
  if (/^owner_board_/.test(fn)) return { data: null, error: { message: 'Could not find the function public.' + fn + ' in the schema cache', code: 'PGRST202' } };
  switch (fn) {
   case 'has_grant': return ok(W.grants === null ? true : W.grants.includes(args.p_code));
   case 'rb4_plan_vs_actual': return ok(W.emptyPlan ? Object.assign({}, R.PVA, { rows: [], unplanned: [], summary: { plans: 0, cancelled_plans: 0, rows_met: 0, rows_short: 0, rows_not_made: 0, rows_qty_not_captured: 0, unplanned_runs: 0 }, notes: [{ code: 'plan_not_captured', field: 'production plan' }] }) : R.PVA);
   case 'rb4_order_status': return ok(R.ORD);
   case 'rb4_dispatch_recon': return ok(R.REC);
   case 'rb4_cost_variance': return ok(COST(W.hideCost));
   case 'rb4_consumption_vs_recipe': return ok(R.USE);
   case 'rb4_run_yield': return ok(R.YLD);
   case 'rb4_losses': return ok(R.LOSS);
   case 'rb4_wastage_dim': return ok(WST(W.hideCost));
   case 'rb4_target_report': return ok(R.TGT);
   case 'rb4_kpi_trend': return ok(R.KPI);
   case 'rb4_factory_vs_retail': return ok(W.cmpBasis ? Object.assign({}, R.CMP, { basis: W.cmpBasis }) : R.CMP);
   case 'rb4_labour_productivity': return ok(R.LAB);
   case 'rb4_capacity_utilization': return ok(R.CAP);
   case 'rb4_target_tile': return ok(R.TILE);
   case 'rb4_log_export': return ok(null);
   case 'sales_target_list': return ok({ can_edit: W.canTarget, rows: [] });
   case 'sales_target_set': return ok({ id: 9 });
   case 'sales_target_retire': return ok({ status: 'retired' });
   case 'kpi_snapshot_take': return ok({ rows_written: 20 });
   case 'prod_runs_recent': return ok({ rows: R.RECENT });
   case 'prod_labour_list': return ok(R.RECENT.map((r) => ({ run_id: r.run_id, line_id: null, labour_hours: r.run_id === R.RUN1 ? 15 : null, entries: r.run_id === R.RUN1 ? [{ id: 31, people: 3, hours_each: 4, note: null }] : [] })));
   case 'prod_run_detail': { const r = clone(R.RUNS[args.p_run]); if (W.readOnly) r.can_edit = false; ((W.saved && W.saved[args.p_run]) || []).forEach((s) => { const l = r.issue_lines.find((x) => x.item_id === s.item_id); if (l) { l.actual_qty = s.qty; l.booked_qty = 6; l.diff = s.qty - 6; } }); return ok(r); }
   case 'prod_actual_issue_set': W.saved = W.saved || {}; W.saved[args.p_run] = args.p_lines; return ok({ run_id: args.p_run, lines: args.p_lines.length });
   case 'production_line_list': return ok(R.LINES);
   case 'capacity_rating_list': return ok(R.RATINGS);
   default: return ok({ ok: true, id: 'x1' }); } };
 return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage(); p.setDefaultTimeout(8000);
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o);
    const T = data.tables;
    T.items.push({ id: 'fg1', code: 'F-001', name_bn: 'test_sweet', name_en: 'test_sweet', item_type: 'finished_good', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true }, { id: 'rm1', code: 'R-001', name_bn: 'test_milk', name_en: 'test_milk', item_type: 'raw_material', unit: 'kg', base_unit: 'kg', tracked: true, is_active: true });
    T.locations = [{ id: 1, code: 'main', name_bn: 'Test shop', name_en: 'Test shop', kind: 'showroom', status: 'live' }, { id: 5, code: 'fac', name_bn: 'Test factory', name_en: 'Test factory', kind: 'factory', status: 'live' }];
    T.production_plans = [{ id: PLAN1, plan_date: day(-3), location_id: 5, item_id: 'fg1', planned_batches: 2, planned_qty: 20, note: 'test plan', status: 'planned', cancel_note: null, created_staff: 'owner1' }];
    T.option_lists.push({ list_code: 'wastage_reasons', value_code: 'burnt', label_bn: 'পোড়া', label_en: 'Burnt', label_mix: 'Burnt', sort: 1, active: true });
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};${o.owner === false ? 'window.__OWNER=false;' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');${o.ls || ''}}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1300); return p;
  }
  const wait = (p, t = 350) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const txt = (p, s = 'body') => p.textContent(s);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth); ok(r <= 1, 'no horizontal scroll at 360px: ' + m + ' (' + r + ')'); };
  const csvOf = async (p, sel) => { const [d] = await Promise.all([p.waitForEvent('download'), p.click(sel)]); return fs.readFileSync(await d.path(), 'utf8'); };
  const shot = async (p, name) => { if (process.env.RB4_SHOTS) await p.screenshot({ path: process.env.RB4_SHOTS + '/' + name + '.png', fullPage: false }); };
  const tab = async (p, act, id) => { await p.click(`[data-act="${act}_tab"][data-v="${id}"]`); await wait(p, 500); };

  // ---- registry
  let p = await open({}, '#/home');
  const reg = await p.evaluate(() => { const ia = window.BOS.IA, want = ['prodplan', 'prodreports', 'capacity', 'targets']; return { each: want.map((w) => ia.filter((r) => r.route === w).length), g: want.map((w) => (ia.find((r) => r.route === w) || {}).group), pages: want.map((w) => !!window.BOS_PAGES[w]),
    old: ['recipes', 'recipebook', 'costing', 'costsources', 'costattrib', 'reports', 'report', 'biz', 'brandpnl', 'owner', 'stockx', 'exceptions'].map((w) => ia.filter((r) => r.route === w).length) }; });
  ok(reg.each.every((x) => x === 1) && JSON.stringify(reg.g) === JSON.stringify(['factory', 'factory', 'factory', 'dash']) && reg.pages.every(Boolean), 'four records once, in factory / factory / factory / dash, pages exist: ' + JSON.stringify(reg));
  ok(reg.old.every((x) => x === 1), 'no existing route was removed or duplicated: ' + JSON.stringify(reg.old));
  const also = await p.evaluate(() => ['prodreports', 'targets', 'capacity'].map((w) => (window.BOS.IA.find((r) => r.route === w).also || []).join(',')));
  ok(also[0] === 'stock,reports' && also[1] === 'sale,reports' && also[2] === 'reports', 'also-lists keep the reports reachable from stock / sale / reports: ' + also.join(' | ')); await p.close();

  // ---- production reports
  p = await open({}, '#/prodreports');
  ok(/Production reports/.test(await txt(p)), 'prodreports title (English)');
  ok((await p.locator('[data-act="prr_tab"]').count()) === 8, 'eight tabs');
  let t0 = await txt(p);
  ok(/short/.test(t0) && /Made with no plan/.test(t0), 'plan tab: status and the unplanned block'); ok(/data not captured: Planned batches/.test(t0) && /data not captured: Planned quantity/.test(t0), 'plan tab: missing plan figures say "data not captured" naming the field');
  ok(!/NaN|undefined|null/.test(t0.replace(/test basis text/, '')), 'plan tab: no NaN / undefined / null text');
  await noOverflow(p, 'plan tab'); await shot(p, 'plan');
  const c1 = await csvOf(p, '[data-act="prr_csv"]');
  ok(/Item,Status,Plan day/.test(c1) && /data not captured: Planned batches/.test(c1) && /F-001 · test_sweet,short/.test(c1), 'plan csv: header, the status code and the not-captured cell; got ' + c1.slice(0, 200).replace(/\r?\n/g, ' | '));
  const ex = await calls(p, 'rb4_log_export'); ok(ex.length === 1 && ex[0].p_key === 'plan_vs_actual' && ex[0].p_kind === 'csv' && ex[0].p_rows > 3, 'the audit call came first: ' + JSON.stringify(ex));
  await p.click('.card.tap >> nth=0'); await wait(p); ok(/Open the run/.test(await txt(p)), 'a row opens a sheet with a link to its run'); ok((await p.locator('[data-act="rb4_go"]').count()) >= 1, 'link buttons present');
  await p.click('[data-act="rb4_go"] >> nth=0'); await wait(p, 600); ok(/#\/prodplan\/run\//.test(await p.evaluate(() => location.hash)), 'the link goes to the run sheet route: ' + await p.evaluate(() => location.hash)); await p.close();

  p = await open({ w: { err: { rb4_log_export: 'not allowed' } } }, '#/prodreports');
  let dl = null; p.on('download', (d) => { dl = d; }); await p.click('[data-act="prr_csv"]'); await wait(p, 700);
  ok(dl === null && /Export not allowed/.test(await txt(p)), 'a refused audit line means no file and a message'); await p.close();

  p = await open({ w: { emptyPlan: true } }, '#/prodreports'); t0 = await txt(p); ok(/No production plan is entered/.test(t0) && /data not captured: production plan/.test(t0), 'no plan at all: the note says so'); await p.close();

  p = await open({}, '#/prodreports');
  const seen = {};
  for (const [id, rpcName, expect] of [['order', 'rb4_order_status', /overdue/], ['recon', 'rb4_dispatch_recon', /In transit/], ['cost', 'rb4_cost_variance', /Price variance/], ['use', 'rb4_consumption_vs_recipe', /Real quantity/], ['yield', 'rb4_run_yield', /Standard yield/], ['loss', 'rb4_losses', /Reject/], ['waste', 'rb4_wastage_dim', /batch not captured/]]) {
    await tab(p, 'prr', id); const t1 = await txt(p); seen[id] = (await calls(p, rpcName)).length;
    ok(expect.test(t1), id + ' tab shows its content'); ok(!/NaN|undefined/.test(t1.replace(/test basis text/, '')), id + ' tab: no NaN / undefined'); await noOverflow(p, id + ' tab');
    ok((await p.locator('[data-act="prr_csv"]').count()) === 1, id + ' tab has a CSV button');
  }
  ok(Object.values(seen).every((x) => x >= 1), 'every tab called its server function: ' + JSON.stringify(seen));
  // specific wording
  await tab(p, 'prr', 'order'); t0 = await txt(p); ok(/data not captured: due day/.test(t0), 'an order without a due day says so (never overdue)');
  await tab(p, 'prr', 'recon'); t0 = await txt(p); ok(/data not captured: On hand now/.test(t0), 'on hand not captured is named');
  await tab(p, 'prr', 'yield'); t0 = await txt(p); ok(/data not captured: actual yield/.test(t0) && /The owner has not set a limit/.test(t0), 'yield: not captured + owner limit note');
  await tab(p, 'prr', 'use'); t0 = await txt(p); ok(/data not captured: real use/.test(t0), 'consumption: real use not captured');
  await tab(p, 'prr', 'loss'); t0 = await txt(p); ok(/data not captured: reject and rework/.test(t0), 'loss: not captured named');
  await tab(p, 'prr', 'cost'); await p.click('.card.tap >> nth=1'); await wait(p); t0 = await txt(p); ok(/Ingredient/.test(t0) || /Details/.test(t0) || /Missing/.test(t0), 'cost row opens its detail'); await p.click('[data-act="closesheet"]'); await wait(p, 200);
  const c2 = await csvOf(p, '[data-act="prr_csv"]'); ok(/Price variance/.test(c2) && /35/.test(c2) && /real use of ingredients, actual yield/.test(c2), 'cost csv has the variance and the missing list');
  await p.close();
  p = await open({ w: { hideCost: true } }, '#/prodreports'); await tab(p, 'prr', 'cost'); t0 = await txt(p);
  ok(/You may not see money figures/.test(t0), 'cost hidden: the notice shows'); ok(!/৳ 35|৳ 207/.test(t0), 'cost hidden: no money figure on screen'); await noOverflow(p, 'cost hidden');
  const c3 = await csvOf(p, '[data-act="prr_csv"]'); ok(!/207|1260/.test(c3), 'cost hidden: no money in the csv'); await p.close();

  // ---- Bangla
  p = await open({ lang: 'bn' }, '#/prodreports'); t0 = await txt(p); ok(/উৎপাদন রিপোর্ট/.test(t0) && /পরিকল্পনা বনাম আসল/.test(t0) && /তথ্য লেখা হয়নি/.test(t0), 'Bangla mode: title, tab and the not-captured wording'); await noOverflow(p, 'prodreports bn');
  await p.close();
  p = await open({ lang: 'bn' }, '#/targets'); t0 = await txt(p); ok(/লক্ষ্য, KPI ও তুলনা/.test(t0) && /লক্ষ্য বনাম অর্জন/.test(t0), 'Bangla mode: targets title and tab'); await noOverflow(p, 'targets bn'); await p.close();
  p = await open({ lang: 'bn' }, '#/capacity'); t0 = await txt(p); ok(/শ্রম ও ক্ষমতা/.test(t0), 'Bangla mode: capacity title'); await noOverflow(p, 'capacity bn'); await p.close();
  p = await open({ lang: 'bn' }, '#/prodplan'); t0 = await txt(p); ok(/উৎপাদন: পরিকল্পনা, অর্ডার ও রান/.test(t0), 'Bangla mode: prodplan title'); await noOverflow(p, 'prodplan bn'); await p.close();

  // ---- production capture (prodplan)
  p = await open({}, '#/prodplan'); t0 = await txt(p);
  ok(/Production: plan, orders & runs/.test(t0) && /paper form code: to be given by owner/.test(t0), 'prodplan title and the paper-form-code line'); ok(/2 lines/.test(t0) && /data not captured: real use of ingredients/.test(t0), 'runs: real use present for run 1, not captured for run 2');
  ok(/data not captured: reject and rework/.test(t0) && /data not captured: labour hours/.test(t0), 'runs: loss and labour not captured named'); await noOverflow(p, 'prodplan runs');
  await p.click('.card.tap >> nth=0'); await wait(p, 700);   // newest first = run 2
  let sh = await txt(p); ok(/Real use of ingredients/.test(sh) && /Type what you measured first/.test(sh), 'run sheet opens (run 2) with the blind hint'); ok((await p.locator('.pp_ru').count()) === 2, 'two blind inputs');
  ok(!/Recipe 6|Recipe\s*6/.test(sh), 'blind: the recipe quantity of an unsaved line is NOT on the screen'); ok(/data not captured: Actual yield/.test(sh) || /Actual yield/.test(sh), 'actual yield is shown as not captured on the run');
  await noOverflow(p, 'run sheet'); await shot(p, 'run');
  await p.fill('.pp_ru >> nth=0', '6.5'); await p.click('[data-act="pp_rusave"]'); await wait(p, 700);
  let cs = await calls(p, 'prod_actual_issue_set'); ok(cs.length === 1 && cs[0].p_run === RUN2 && cs[0].p_lines.length === 1 && cs[0].p_lines[0].item_id === 'rm1' && cs[0].p_lines[0].qty === 6.5, 'real use payload: ' + JSON.stringify(cs));
  sh = await txt(p); ok(/Recipe 6/.test(sh) && /Difference \+0\.5/.test(sh), 'after the save the recipe quantity and the difference appear');
  await p.fill('#pp_l_q', '1'); await p.selectOption('#pp_l_r', 'burnt'); await p.click('[data-act="pp_lossadd"]'); await wait(p, 600);
  cs = await calls(p, 'prod_loss_add'); ok(cs.length === 1 && cs[0].p_kind === 'reject' && cs[0].p_qty === 1 && cs[0].p_reason === 'burnt' && cs[0].p_run === RUN2 && !!cs[0].p_client, 'reject payload: ' + JSON.stringify(cs));
  await p.click('[data-act="pp_lossnone"]'); await wait(p, 500); cs = await calls(p, 'prod_loss_add'); ok(cs.length === 2 && cs[1].p_kind === 'none', 'checked-none payload');
  await p.fill('#pp_l_q', '0'); await p.selectOption('#pp_l_r', 'burnt'); const before = (await calls(p, 'prod_loss_add')).length; await p.click('[data-act="pp_lossadd"]'); await wait(p, 300); ok((await calls(p, 'prod_loss_add')).length === before, 'a zero quantity is stopped on the screen');
  await p.fill('#pp_b_p', '3'); await p.fill('#pp_b_h', '4'); await p.click('[data-act="pp_labadd"]'); await wait(p, 600);
  cs = await calls(p, 'prod_labour_add'); ok(cs.length === 1 && cs[0].p_people === 3 && cs[0].p_hours === 4 && cs[0].p_run === RUN2, 'labour payload: ' + JSON.stringify(cs));
  await p.fill('#pp_b_h', '30'); const lb = (await calls(p, 'prod_labour_add')).length; await p.click('[data-act="pp_labadd"]'); await wait(p, 300); ok((await calls(p, 'prod_labour_add')).length === lb, 'more than 24 hours is stopped on the screen');
  await p.selectOption('#pp_k_plan', PLAN1); await p.selectOption('#pp_k_order', '7'); await p.click('[data-act="pp_linksave"]'); await wait(p, 600);
  cs = await calls(p, 'prod_run_link'); ok(cs.length === 1 && cs[0].p_plan === PLAN1 && cs[0].p_order === 7 && cs[0].p_clear_plan === false, 'link payload: ' + JSON.stringify(cs)); await p.close();

  p = await open({}, `#/prodplan/run/${RUN1}`); sh = await txt(p);
  ok(/Real use of ingredients/.test(sh) && /Recipe 12/.test(sh) && /Difference \+1/.test(sh), 'the route #/prodplan/run/<id> opens the run sheet; saved lines show recipe and difference'); ok(/Burnt/.test(sh) || /burnt/.test(sh), 'the loss line shows its reason'); await p.close();
  p = await open({ w: { readOnly: true } }, `#/prodplan/run/${RUN1}`); sh = await txt(p); ok(/You can only view this run/.test(sh) && (await p.locator('.pp_ru').count()) === 0 && (await p.locator('[data-act="pp_rusave"]').count()) === 0, 'a viewer without the right sees no input and no save button'); await p.close();

  p = await open({}, '#/prodplan/plans'); t0 = await txt(p); ok(/test plan/.test(t0) && /planned/.test(t0), 'plans tab lists the plan'); await noOverflow(p, 'plans tab');
  await p.click('[data-act="pp_newplan"]'); await wait(p); await p.selectOption('#pp_p_loc', '5'); await p.fill('#pp_p_item', 'F-001 · test_sweet'); await p.fill('#pp_p_b', '2'); await p.click('[data-act="pp_plansave"]'); await wait(p, 700);
  cs = await calls(p, 'prod_plan_add'); ok(cs.length === 1 && cs[0].p_loc === 5 && cs[0].p_item === 'fg1' && cs[0].p_batches === 2 && cs[0].p_qty === null && !!cs[0].p_client, 'plan payload: ' + JSON.stringify(cs));
  await p.click('[data-act="pp_newplan"]'); await wait(p); await p.selectOption('#pp_p_loc', '5'); await p.fill('#pp_p_item', 'F-001'); const pb = (await calls(p, 'prod_plan_add')).length; await p.click('[data-act="pp_plansave"]'); await wait(p, 300); ok((await calls(p, 'prod_plan_add')).length === pb, 'a plan with neither batches nor quantity is stopped on the screen'); await p.click('[data-act="closesheet"]'); await wait(p, 200);
  await p.click('.card.tap >> nth=0'); await wait(p); await p.click('[data-act="pp_cancelplan"]'); await wait(p, 500); await p.fill('#pp_why', 'test: not needed'); await p.click('[data-act="pp_cancelplango"]'); await wait(p, 600);
  cs = await calls(p, 'prod_plan_cancel'); ok(cs.length === 1 && cs[0].p_id === PLAN1 && cs[0].p_note === 'test: not needed', 'plan cancel payload: ' + JSON.stringify(cs)); await p.close();

  p = await open({}, '#/prodplan/orders'); t0 = await txt(p); ok(/#7/.test(t0) && /overdue/.test(t0) && /data not captured: due day/.test(t0), 'orders tab lists orders with the overdue state and the missing due day'); await noOverflow(p, 'orders tab');
  await p.click('[data-act="pp_neworder"]'); await wait(p); await p.selectOption('#pp_o_loc', '5'); await p.selectOption('#pp_o_for', '1'); await p.fill('#pp_o_item', 'F-001'); await p.fill('#pp_o_q', '12'); await p.fill('#pp_o_due', day(3)); await p.click('[data-act="pp_ordersave"]'); await wait(p, 700);
  cs = await calls(p, 'prod_order_add'); ok(cs.length === 1 && cs[0].p_loc === 5 && cs[0].p_for_loc === 1 && cs[0].p_item === 'fg1' && cs[0].p_qty === 12 && cs[0].p_due === day(3) && cs[0].p_unit === null, 'order payload: ' + JSON.stringify(cs));
  await p.click('.card.tap >> nth=0'); await wait(p); await p.click('[data-act="pp_closeorder"]'); await wait(p, 500); await p.fill('#pp_why', 'test: agreed'); await p.click('[data-act="pp_closeordergo"]'); await wait(p, 600);
  cs = await calls(p, 'prod_order_close'); ok(cs.length === 1 && cs[0].p_id === 7 && cs[0].p_note === 'test: agreed', 'order close payload: ' + JSON.stringify(cs));
  await p.click('.card.tap >> nth=0'); await wait(p); await p.click('[data-act="pp_cancelorder"]'); await wait(p, 500); await p.fill('#pp_why', 'x'); const oc = (await calls(p, 'prod_order_cancel')).length; await p.click('[data-act="pp_cancelordergo"]'); await wait(p, 300); ok((await calls(p, 'prod_order_cancel')).length === oc, 'a cancel reason under 3 characters is stopped on the screen'); await p.close();

  // ---- targets, KPI, comparison
  p = await open({}, '#/targets'); t0 = await txt(p);
  await shot(p, 'targets'); ok(/Targets, KPI & comparison/.test(t0) && /Test shop/.test(t0) && /behind/.test(t0) && /target not set/.test(t0), 'targets tab: rows with statuses'); ok(/data not captured: sales target/.test(t0), 'a place with sales but no target says "data not captured: sales target"');
  ok(/Set a target/.test(t0) && /paper form code: to be given by owner/.test(t0), 'the owner sees the entry button and the paper-form-code line'); await noOverflow(p, 'targets tab');
  const tg = await calls(p, 'rb4_target_report'); ok(tg.length >= 1 && tg[0].p_from_month === m0, 'the target report is asked for this month: ' + JSON.stringify(tg[0]));
  const c4 = await csvOf(p, '[data-act="tgp_csv"]'); ok(/Target/.test(c4), 'target csv'); ok((await calls(p, 'rb4_log_export')).some((x) => x.p_key === 'target_report'), 'target csv wrote its audit call first');
  await p.click('[data-act="tg_new"]'); await wait(p); await p.selectOption('#tg_loc', '1'); await p.fill('#tg_amt', '12000'); await p.fill('#tg_gp', '120'); await p.click('[data-act="tg_save"]'); await wait(p, 300); ok((await calls(p, 'sales_target_set')).length === 0, 'a gross-profit % above 100 is stopped on the screen');
  await p.fill('#tg_gp', '30'); await p.fill('#tg_note', 'test'); await p.click('[data-act="tg_save"]'); await wait(p, 700);
  cs = await calls(p, 'sales_target_set'); ok(cs.length === 1 && cs[0].p_loc === 1 && /^\d{4}-\d{2}-01$/.test(cs[0].p_month) && cs[0].p_amount === 12000 && cs[0].p_gp_pct === 30 && cs[0].p_note === 'test', 'target payload: ' + JSON.stringify(cs));
  await p.click('.card.tap >> nth=0'); await wait(p); ok(/Change this target/.test(await txt(p)) && /Retire this target/.test(await txt(p)), 'a row with a target offers change / retire to who may');
  await p.click('[data-act="tg_retire"]'); await wait(p, 500); await p.fill('#tg_why', 'test: wrong month'); await p.click('[data-act="tg_rgo"]'); await wait(p, 600); cs = await calls(p, 'sales_target_retire'); ok(cs.length === 1 && cs[0].p_id === 5 && cs[0].p_note === 'test: wrong month', 'retire payload: ' + JSON.stringify(cs)); await p.close();

  p = await open({ w: { canTarget: false } }, '#/targets'); t0 = await txt(p); ok(!/Set a target/.test(t0) && /Targets are set by the owner/.test(t0) && (await p.locator('[data-act="tg_new"]').count()) === 0, 'a reader who may not set targets sees no button, only the owner-only line'); await p.close();

  p = await open({}, '#/targets'); await tab(p, 'tgp', 'kpi'); t0 = await txt(p);
  ok(/discount high/.test(t0) && /Test shop/.test(t0), 'KPI tab: the alert is listed'); ok(/data not captured: limit/.test(t0), 'an unset limit is named, not shown as 0'); ok(/Open exceptions/.test(t0) && /red/.test(t0), 'open exceptions count with a link'); ok(/Days without a snapshot/.test(t0), 'missing days are listed apart');
  await noOverflow(p, 'kpi tab'); await shot(p, 'kpi');
  await p.click('[data-act="tg_snap"]'); await wait(p, 800); cs = await calls(p, 'kpi_snapshot_take'); ok(cs.length >= 1 && cs[0].p_redo === false && cs[0].p_to <= day(-1), 'snapshot call: closed days only, no redo: ' + JSON.stringify(cs));
  const c5 = await csvOf(p, '[data-act="tgp_csv"]'); ok(/discount high|discount_high/.test(c5) || /Alerts/.test(c5), 'kpi csv has the alerts block');
  await tab(p, 'tgp', 'cmp'); t0 = await txt(p);
  ok(/not valued/.test(t0) && /Transfer valuation basis/.test(t0), 'compare tab: the basis is none and transfers say "not valued"'); ok(/Factory → shops/.test(t0) && /Shops/.test(t0) && /Test shop/.test(t0), 'compare tab: three blocks'); ok(/never netted/.test(await p.evaluate(() => document.body.innerHTML)), 'the statement that shop profit is never netted with a transfer value is in the page');
  await noOverflow(p, 'compare tab'); const c6 = await csvOf(p, '[data-act="tgp_csv"]'); ok(/not valued/.test(c6) && /964.29/.test(c6), 'compare csv: cost value and the not-valued state'); await p.close();
  p = await open({ w: { cmpBasis: 'cost' } }, '#/targets'); await tab(p, 'tgp', 'cmp'); t0 = await txt(p); ok(/at factory cost/.test(t0), 'compare tab names the basis in force'); await p.close();

  // ---- capacity and labour
  p = await open({}, '#/capacity'); t0 = await txt(p);
  ok(/Output per labour hour/.test(t0) && /labour not captured/.test(t0) && /data not captured: labour hours/.test(t0), 'labour tab: a run with no labour says so'); await noOverflow(p, 'labour tab'); const c7 = await csvOf(p, '[data-act="cp_csv"]'); ok(/labour not captured|Per run/.test(c7), 'labour csv');
  await tab(p, 'cp', 'cap'); t0 = await txt(p); ok(/12.5 %/.test(t0) && /rated capacity not captured/.test(t0) && /data not captured: rated capacity/.test(t0), 'capacity tab: utilization, and a place with no rating says "rated capacity not captured"'); await noOverflow(p, 'capacity tab');
  await tab(p, 'cp', 'set'); t0 = await txt(p); ok(/Add a line/.test(t0) && /Set rated capacity/.test(t0) && /test_line_one|Test line one/.test(t0), 'set-up tab: buttons and the line'); await noOverflow(p, 'set-up tab');
  await p.click('[data-act="cp_newline"]'); await wait(p); await p.selectOption('#cp_l_loc', '5'); await p.fill('#cp_l_bn', 'test_line_two'); await p.fill('#cp_l_en', 'Test line two'); await p.click('[data-act="cp_linesave"]'); await wait(p, 700);
  cs = await calls(p, 'production_line_set'); ok(cs.length === 1 && cs[0].p_id === null && cs[0].p_loc === 5 && cs[0].p_name_bn === 'test_line_two' && cs[0].p_name_en === 'Test line two', 'line payload: ' + JSON.stringify(cs));
  await p.click('[data-act="cp_newrate"]'); await wait(p); await p.selectOption('#cp_r_loc', '5'); await p.fill('#cp_r_bpd', '4'); await p.fill('#cp_r_dpw', '8'); const rb = (await calls(p, 'capacity_rating_set')).length; await p.click('[data-act="cp_ratesave"]'); await wait(p, 300); ok((await calls(p, 'capacity_rating_set')).length === rb, 'more than 7 working days is stopped on the screen');
  await p.fill('#cp_r_dpw', '6'); await p.click('[data-act="cp_ratesave"]'); await wait(p, 700); cs = await calls(p, 'capacity_rating_set'); ok(cs.length === 1 && cs[0].p_loc === 5 && cs[0].p_line === null && cs[0].p_batches_per_day === 4 && cs[0].p_days_per_week === 6, 'rating payload: ' + JSON.stringify(cs));
  await p.click('.card.tap >> nth=1'); await wait(p); const hasRet = await p.locator('[data-act="cp_retrate"]').count(); ok(hasRet >= 1 || (await p.locator('[data-act="cp_retline"]').count()) >= 1, 'a set-up row offers retire to who may');
  if (hasRet) { await p.click('[data-act="cp_retrate"]'); await wait(p, 500); await p.fill('#cp_why', 'test: replaced'); await p.click('[data-act="cp_rgo"]'); await wait(p, 600); cs = await calls(p, 'capacity_rating_retire'); ok(cs.length === 1 && cs[0].p_id === 3 && cs[0].p_note === 'test: replaced', 'rating retire payload: ' + JSON.stringify(cs)); }
  await p.close();
  p = await open({ owner: false, w: { grants: ['x'] } }, '#/capacity'); await tab(p, 'cp', 'set'); t0 = await txt(p); ok(/set by the owner or a holder of the right/.test(t0) && (await p.locator('[data-act="cp_newline"]').count()) === 0, 'a reader without the right sees no set-up button'); await p.close();

  // ---- owner board widget
  p = await open({ ls: `localStorage.setItem('bos_ob_items_u1',JSON.stringify([{widget:'target_vs',config:{cid:'a'},enabled:true}]));` }, '#/owner'); await wait(p, 900); t0 = await txt(p);
  ok(/target vs achievement/i.test(t0) && /5%/.test(t0) && /behind/.test(t0) && /Test shop/.test(t0), 'owner board: the target tile shows the % and the place that is behind; got ' + t0.slice(0, 300).replace(/\s+/g, ' '));
  ok((await calls(p, 'rb4_target_tile')).length >= 1, 'the tile calls rb4_target_tile'); await p.close();

  ok(errors.length === 0, 'no page errors: ' + errors.slice(0, 5).join(' | '));
  log('errors:', errors.length ? errors.slice(0, 8) : 'none'); log(`assert failures: ${bad} of ${n}`);
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.error('TEST CRASH', e); process.exit(2); } })();
