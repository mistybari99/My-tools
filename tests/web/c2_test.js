// RPT-C2 web: order and delivery reports (#/orderreports), customer insight (#/custinsight), staff reports (#/staffreports), the capture fields in the Online orders screen, the 06-1 cashier box, the production sheet fields.
// Run: node tests/web/c2_test.js <abs tests/web dir>   (360 px phone, mocked RPCs; the real script tags are in web/index.html)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = 8394, srv = C.serve(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const X = window.__X = Object.assign({ feat: { v: 452, spec: true, promise: true, cost: true, cancel: true, advance: true, detail: true, online_orders_on: true, promise_required: false, refund_record_on: true, advance_post_on: false }, orders: [], fail: {}, notes: ['sources_not_merged'] }, window.__X0 || {});
 const regRows = [
  { source: 'app', ref: '#1', order_id: 'o1', entry_id: null, order_date: '2026-10-16', customer_name: 'test_customer_a', customer_mobile: null, channel: 'phone', order_type: 'cake', status: 'delivered', promised_date: '2026-10-16', promised_from: '10:00:00', promised_to: '12:00:00', total: 230, advance: 50, balance: 0, advance_state: 'paid_into_sale', delivery_cost: null },
  { source: 'app', ref: '#2', order_id: 'o2', entry_id: null, order_date: '2026-10-16', customer_name: 'test_customer_b', customer_mobile: null, channel: 'phone', order_type: 'normal', status: 'cancelled', promised_date: null, promised_from: null, promised_to: null, total: 100, advance: 60, balance: 0, advance_state: 'refund_not_recorded', delivery_cost: null },
  { source: 'paper_20_1', ref: '20-1/9001', order_id: null, entry_id: 'e1', order_date: '2026-10-16', customer_name: 'test_paper_a', customer_mobile: null, channel: 'phone', order_type: 'cake', status: 'handed', promised_date: '2026-10-15', promised_from: '11:00:00', promised_to: null, total: 300, advance: 100, balance: null, advance_state: 'on_sheet', delivery_cost: null },
  { source: 'paper_20_6', ref: '20-6/9004/1', order_id: null, entry_id: 'e2', order_date: '2026-10-16', customer_name: null, customer_mobile: null, channel: 'test_platform', order_type: 'normal', status: 'handed', promised_date: null, promised_from: null, promised_to: null, total: 120, advance: null, balance: null, advance_state: 'none', delivery_cost: null }];
 const e = (m) => ({ data: null, error: { message: m, code: 'P0001' } });
 c.rpc = async (fn, args) => {
  (window.__AC = window.__AC || []).push([fn, clone(args || {})]);
  if (X.fail[fn]) { const m = X.fail[fn]; return e(m); }
  if (fn === 'c2_orders_features') return { data: X.feat, error: null };
  if (fn === 'c2_order_register') return { data: { from: args.p_from, to: args.p_to, module_on: X.feat.online_orders_on, notes: X.notes, truncated: false, row_count: 4, totals_by_source: { app: { rows: 2, total: 330, advance: 110, balance: 0, rows_without_balance: 0 }, paper_20_1: { rows: 1, total: 300, advance: 100, balance: null, rows_without_balance: 1 }, paper_20_6: { rows: 1, total: 120, advance: null, balance: null, rows_without_balance: 1 } }, rows: regRows.filter((r) => !args.p_source || r.source === args.p_source) }, error: null };
  if (fn === 'c2_order_detail') return { data: { order: { id: args.p_order, order_no: 1, customer_name: 'test_customer_a', status: 'delivered', delivery_mode: 'home', delivery_date: '2026-10-16', advance: 50 }, register_row: regRows[0], events: [{ from: null, to: 'new', note: 'created', at: '2026-10-16T09:00:00Z', by: 'x' }], specs: [{ weight_kg: 1.5, flavour: 'test_flavour', message: 'test_msg' }], promise: { slot_from: '10:00:00', slot_to: '12:00:00' }, costs: null, cost_hidden: true, advance_post: null, refund: null, sale: { id: 's1', receipt: 5, status: 'done', paid: 230, due: 0 }, module_on: true, can_move_money: false }, error: null };
  if (fn === 'c2_orders_delayed') return { data: { module_on: true, notes: ['open_without_date_not_judged'], summary: { delayed: 1, delayed_app: 1, delayed_paper_20_1: 0, oldest_days: 2, judged_by_slot: 1, judged_by_date_only: 0, open_without_promised_date: 3, open_not_yet_due: 0 }, rows: [{ source: 'app', ref: '#3', order_id: 'o3', customer_name: 'test_customer_c', status: 'confirmed', promised_date: '2026-10-14', promised_from: '09:00:00', promised_to: '10:00:00', basis: 'slot', overdue_hours: 61.5, overdue_days: 3, advance: 40, balance: 160 }] }, error: null };
  if (fn === 'c2_orders_ontime') return { data: { module_on: true, notes: ['paper_delivery_time_not_captured'], summary: { judged: 0, on_time: 0, late: 0, on_time_pct: null, delivered_without_promised_date_not_judged: 2 }, still_open_overdue: 1, rows: [] }, error: null };
  if (fn === 'c2_order_cancellations') return { data: { module_on: true, notes: ['refund_switch_off'], summary: { cancelled: 1, cancel_rate_pct: 12.5, cancelled_value: 100, advance_total: 60, refunded: 0, refund_due: 0, refund_not_recorded: 60 }, by_reason: [{ reason: 'test_reason', orders: 1, advance: 60 }], paper_20_1: { sheets_not_collected: 0, advance: 0 }, rows: [{ ref: '#2', order_id: 'o2', cancelled_at: '2026-10-16T10:00:00', customer_name: 'test_customer_b', reason: 'test_reason', total: 100, advance: 60, advance_state: 'refund_not_recorded' }] }, error: null };
  if (fn === 'c2_order_refunds_list') return { data: { rows: [] }, error: null };
  if (fn === 'c2_delivery_cost_report') return { data: { notes: ['cost_hidden'], summary: { orders: 2, delivered: 1, charge_total: 60, with_cost_captured: null, cost_not_captured: null }, by_kind: null, by_delivery_by: null, paper_20_6: { lines: 0 }, rows: [{ ref: '#1', order_id: 'o1', order_date: '2026-10-16', customer_name: 'test_customer_a', delivery_mode: 'home', delivery_by: null, status: 'delivered', charge: 30, cost: null, margin: null }] }, error: null };
  if (fn === 'c2_credit_risk') return { data: { as_of: '2026-10-17', notes: ['risk_rule_not_set', 'no_default_terms'], summary: { customers_owing: 2, balance_total: 650, overdue_total: 50, customers_overdue: 1, owing_without_terms: 1, over_limit: 0 }, rows: [
    { customer_id: 'c1', name: 'test_cust_1', mobile: '01700000301', balance: 150, oldest_open: '2026-09-07', terms_days: 30, terms_source: 'customer', overdue: 50, days_past_due: 10, credit_limit: null, limit_used_pct: null, advance_held: 40, advance_applied: 0, risk: 'rule_not_set' },
    { customer_id: 'c2', name: 'test_cust_2', mobile: '01700000302', balance: 500, oldest_open: '2026-07-09', terms_days: null, terms_source: 'none', overdue: null, days_past_due: null, credit_limit: null, limit_used_pct: null, advance_held: 0, advance_applied: 0, risk: 'no_terms' }] }, error: null };
  if (fn === 'c2_dues_not_linked_notice') return { data: { items: [{ code: 'sales_due_no_customer', amount: 100, count: 1, fix_route: 'dues' }], journal_checked: false }, error: null };
  if (fn === 'c2_customer_card') return { data: { customer: { id: 'c1', name: 'test_cust_1', mobile: '01700000301', credit_days: 30, credit_limit: null, default_credit_days: null }, credit: { balance: 150, overdue: 50, days_past_due: 10, risk: 'rule_not_set', advance_held: 40 }, ltv: { orders: 2, revenue: 400, net_revenue: 300, first_sale: '2026-09-07', last_sale: '2026-10-07' }, returns_last_365_days: null, special_orders_last_365_days: [], can_edit_terms: true }, error: null };
  if (fn === 'c2_customer_credit_days_set') { return { data: { id: args.p_customer, credit_days: args.p_days }, error: null }; }
  if (fn === 'c2_customer_ltv') return { data: { all_time: true, notes: ['cost_hidden'], summary: { customers: 1, orders: 2, revenue: 400, returns: 100, net_revenue: 300, sales_without_customer: 1, revenue_without_customer: 100 }, rows: [{ customer_id: 'c1', name: 'test_cust_1', orders: 2, revenue: 400, returns: 100, net_revenue: 300, avg_order: 200, first_sale: '2026-09-07', last_sale: '2026-10-07', days_as_customer: 30, days_since_last: 10, gross_margin: null, sales_with_known_cost: null }] }, error: null };
  if (fn === 'c2_att_period_summary') return { data: { from: args.p_from, to: args.p_to, notes: ['app_days_only', 'paper_02_1_not_included'], paper_02_1_sheets_in_range: 1, summary: { people: 2, people_with_no_record_at_all: 1, days_with_record: 6, days_without_record: 6, late_days: 1, late_minutes: 20, absent: 1, worked_minutes: 1450, ot_minutes: 45, ot_waiting_minutes: 15, scheduled_minutes: 1350, variance_minutes: -200, days_without_shift: 1 }, rows: [
    { employee_id: 'em1', employee_no: 'E1', name_en: 'test_emp_1', present: 2, late_status: 1, absent: 1, half_day: 1, leave: 0, unpaid: 0, off: 1, holiday: 0, days_without_record: 0, late_days: 1, late_minutes: 20, worked_minutes: 1450, single_punch_days: 1, manual_days: 1, days_with_shift: 3, days_without_shift: 1, scheduled_minutes: 1350, variance_minutes: -200, ot_minutes: 45, ot_approved_minutes: 30, ot_waiting_minutes: 15, early_leave_minutes: 0 },
    { employee_id: 'em2', employee_no: 'E2', name_en: 'test_emp_2', present: 0, late_status: 0, absent: 0, half_day: 0, leave: 0, unpaid: 0, off: 0, holiday: 0, days_without_record: 6, late_days: 0, late_minutes: 0, worked_minutes: 0, single_punch_days: 0, manual_days: 0, days_with_shift: 0, days_without_shift: 0, scheduled_minutes: null, variance_minutes: null, ot_minutes: 0, ot_approved_minutes: 0, ot_waiting_minutes: 0, early_leave_minutes: 0 }] }, error: null };
  if (fn === 'c2_att_person_days') return { data: { rows: [{ day: '2026-10-11', status: 'present', worked_minutes: 480, scheduled_minutes: 450, variance_minutes: 30 }] }, error: null };
  if (fn === 'c2_cashier_variance') return { data: { notes: ['cashier_not_written_on_some_sheets'], summary: { sheets: 5, sheets_without_cashier: 1, short_amount: 60, over_amount: 5, net: -55 }, rows: [{ cashier: 'test_staff_a', cashier_written: true, shift: 's1', sheets: 2, short_sheets: 1, over_sheets: 1, short_amount: 20, over_amount: 5, net: -15, worst: 20, cases_open: 0, cases_approved: 1, cases_rejected: 0, cases_void: 0 }, { cashier: '', cashier_written: false, shift: 'full', sheets: 1, short_sheets: 1, over_sheets: 0, short_amount: 30, over_amount: 0, net: -30, worst: 30 }], uncredited_sheets_with_a_variance: [] }, error: null };
  if (fn === 'c2_sales_per_labour_hour') return { data: { notes: [], summary: { sales: 200, returns: 0, labour_hours: null, punch_coverage_pct: null, sales_per_hour: null, places_without_hours: 1 }, rows: [{ loc: 1, name_en: 'test_place', sales: 200, returns: 0, bills: 1, staff_days: 0, labour_hours: null, punch_coverage_pct: null, sales_per_hour: null, status: 'no_attendance_records' }] }, error: null };
  if (fn === 'c2_order_spec_save' || fn === 'c2_order_promise_set' || fn === 'c2_order_cost_add' || fn === 'c2_order_cancel' || fn === 'c2_order_deliver') return { data: { ok: true, refund: 'due', status: 'x', receipt: 9 }, error: null };
  if (fn === 'c2_crew_pick') return { data: [{ employee_id: 'em1', name_en: 'test_emp_1' }], error: null };
  if (fn === 'c2_orders_for_production') return { data: { module_on: true, rows: [{ order_id: 'o9', order_no: 9, customer_name: 'test_customer_z', delivery_date: '2026-10-18' }] }, error: null };
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001|status of 4/.test(m.text()) && !/^Error: /.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept('test reason'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
    T.items = [{ id: 'it1', code: 'C1', name_bn: 'test_item', name_en: 'test_item', sell_price: 100, is_active: true }];
    T.option_lists = (T.option_lists || []).concat([{ list_code: 'order_delivery_cost_kinds', value_code: 'fuel', label_bn: 'Fuel', label_en: 'Fuel', sort: 1, active: true }]);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__X0=${JSON.stringify(o.x || {})};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const txt = (p) => p.evaluate(() => document.body.innerText);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const show = async (p) => { await p.click('[data-act$="_run"]'); await wait(p, 600); };

  // ---- order reports ----
  let p = await open('#/orderreports');
  ok(await p.locator('.c2-tabs button').count() === 10, 'ten order report tabs (got ' + await p.locator('.c2-tabs button').count() + ')');
  await noOverflow(p, 'orderreports start');
  await show(p);
  let t = await txt(p);
  ok(/App order/.test(t) && /Paper 20-1/.test(t) && /Paper 23-1 line/.test(t), 'register shows the three sources apart');
  ok(/never added together/.test(t), 'note: sources are not merged');
  ok(await p.locator('.c2-tbl tbody tr').count() === 4, 'register has 4 rows');
  ok(/Refund NOT recorded/.test(t) && /Paid into the sale/.test(t), 'advance states are shown in words');
  const nullCells = await p.locator('.c2-tbl td span.muted').count(); ok(nullCells > 0, 'a missing figure is shown as a dash, not 0');
  await noOverflow(p, 'register at 360px');
  await p.click('.c2-tbl tbody tr:first-child'); await wait(p, 500);
  ok((await calls(p, 'c2_order_detail')).length === 1, 'clicking an app row opens the order detail (drill-down)');
  ok(/Cake specification/.test(await txt(p)) && /Cost figures need the cost right/.test(await txt(p)), 'detail shows the cake spec and hides the cost with a reason');
  await p.evaluate(() => document.querySelector('#sheet') && document.querySelector('#sheet').remove());
  await p.click('[data-act=c2_csv]'); await wait(p, 200);
  const csv = await p.evaluate(() => window.__c2csv);
  ok(csv && /^Source,Ref,Taken/.test(csv.text) && csv.text.split('\r\n').length === 5, 'CSV has the header and 4 rows');
  ok(/20-1\/9001[^\r\n]*,,/.test(csv.text), 'CSV leaves a missing balance empty, not 0');
  await p.selectOption('#c2_src', 'app'); await show(p);
  const rc = await calls(p, 'c2_order_register'); ok(rc[rc.length - 1].p_source === 'app', 'the source filter is sent');
  await p.click('[data-act=or_tab][data-v=delayed]'); await show(p); t = await txt(p);
  ok(/Open, no promised date/.test(t) && /61.5/.test(t) && /Time slot/.test(t), 'delayed tab: count of open orders with no date, hours late, judged by slot');
  await p.click('[data-act=or_tab][data-v=ontime]'); await show(p); t = await txt(p);
  ok(/On time %/.test(t) && !/On time %\s*0/.test(t) && /Delivered, no promised date/.test(t), 'on-time tab: an empty percentage is a dash, not 0');
  await p.click('[data-act=or_tab][data-v=cancel]'); await show(p); t = await txt(p);
  ok(/Refund NOT recorded/.test(t) && /refund switch is off/.test(t), 'cancellation tab: refund not recorded + switch note');
  await p.click('[data-act=or_tab][data-v=dcost]'); await show(p); t = await txt(p);
  ok(/Cost figures need the cost right/.test(t), 'delivery cost tab: cost hidden note');
  await noOverflow(p, 'delivery cost tab');
  await p.close();

  // ---- customer insight ----
  p = await open('#/custinsight'); await show(p); t = await txt(p);
  ok(/Dues not linked to a customer/.test(t) && /Sales with an amount due but no customer/.test(t), 'credit tab: the not-linked notice is shown');
  ok(/Rule not set/.test(t) && /No credit terms/.test(t) && /risk rule is not set/.test(t), 'risk says rule not set / no terms, never an invented label');
  await noOverflow(p, 'credit risk at 360px');
  await p.click('.c2-tbl tbody tr:first-child'); await wait(p, 500);
  ok(/Credit days \(own\)/.test(await txt(p)) && await p.locator('[data-act=ci_setdays]').count() === 1, 'customer card with the credit days field');
  await p.fill('#c2_cd', '45'); await p.click('[data-act=ci_setdays]'); await wait(p, 500);
  const sd = await calls(p, 'c2_customer_credit_days_set'); ok(sd.length === 1 && sd[0].p_days === 45 && sd[0].p_customer === 'c1', 'saving credit days calls the server function');
  await p.evaluate(() => document.querySelector('#sheet') && document.querySelector('#sheet').remove());
  await p.click('[data-act=ci_tab][data-v=ltv]'); await show(p); t = await txt(p);
  ok(/Gross margin/.test(t) && /Sales with no customer/.test(t), 'lifetime value tab');
  const lc = await calls(p, 'c2_customer_ltv'); ok(lc[0].p_from === null && lc[0].p_to === null, 'lifetime value asks for ALL time (no date cap)');
  await p.close();

  // ---- staff reports ----
  p = await open('#/staffreports'); await show(p); t = await txt(p);
  ok(/Paper 19-1 sheets \(not added\)/.test(t) && /test_emp_2/.test(t), 'attendance tab: paper sheets counted not added; a person with no record is listed');
  await noOverflow(p, 'attendance at 360px');
  await p.click('[data-act=sr_tab][data-v=variance]'); await show(p); t = await txt(p);
  ok(/Days without a shift/.test(t) && /-3h 20m/.test(t), 'variance tab shows -200 minutes as -3h 20m');
  await p.click('[data-act=sr_tab][data-v=saleshour]'); await show(p); t = await txt(p);
  ok(/No attendance records/.test(t) && !/Sales per hour\s*৳ 0/.test(t), 'sales per hour with no hours is a dash with the reason');
  await p.click('[data-act=sr_tab][data-v=cashier]'); await show(p); t = await txt(p);
  ok(/No cashier written/.test(t) && /Shift 1/.test(t), 'cashier tab: shift words and the sheet without a cashier');
  await p.click('[data-act=sr_tab][data-v=attendance]'); await show(p);
  await p.click('.c2-tbl tbody tr:first-child'); await wait(p, 500);
  ok((await calls(p, 'c2_att_person_days')).length === 1, 'attendance row opens the person days');
  await p.close();

  // ---- Online orders screen: capture fields and the old behaviour without the server part ----
  p = await open('#/onlineorders', { x: {} }); await wait(p, 500);
  await p.click('[data-act=sx_new]'); await wait(p, 700);
  ok(await p.locator('#c2_cw').count() === 1 && await p.locator('#c2_pf').count() === 1, 'order form has the cake specification and promised time fields');
  await p.fill('#c2_cw', '1.5'); await p.fill('#c2_cf', 'test_flavour'); await p.fill('#c2_pf', '10:00'); await p.fill('#c2_pt', '12:00');
  await p.fill('#sx_n', 'test_customer_q'); await p.fill('#sx_m', '01700000999');
  await p.click('[data-act=sx_save]'); await wait(p, 800);
  const sp = await calls(p, 'c2_order_spec_save'); const pr = await calls(p, 'c2_order_promise_set');
  ok(sp.length === 1 && sp[0].p_specs[0].weight_kg === 1.5 && sp[0].p_specs[0].flavour === 'test_flavour', 'saving sends the cake specification');
  ok(pr.length === 1 && pr[0].p_from === '10:00' && pr[0].p_to === '12:00', 'saving sends the promised time slot');
  await p.close();
  p = await open('#/onlineorders', { x: { feat: false } }); await wait(p, 500);
  await p.click('[data-act=sx_new]'); await wait(p, 600);
  ok(await p.locator('#c2_cw').count() === 0, 'without the server part the old order form is unchanged');
  await p.close();

  // ---- 06-1 cashier box and the ia entries ----
  p = await open('#/home'); await wait(p, 400);
  ok(await p.evaluate(() => (window.BOS.forms['06-1'].head || []).some((f) => f.id === 'cashier' && f.type === 'staff')) && await p.evaluate(() => (window.BOS.forms['06-1'].head || []).some((f) => f.id === 'shift')), 'form 06-1 has a Cashier box beside the existing shift box');
  ok(await p.evaluate(() => ['orderreports', 'custinsight', 'staffreports'].every((r) => window.BOS.IA.some((x) => x.route === r))), 'the three screens are registered once in ia.js');
  ok(await p.evaluate(() => ['c2_orders', 'c2_cust', 'c2_staff'].every((k) => (window.BOS.reportLinks || []).some((l) => l.key === k))), 'the three screens are linked from the Reports hub list');
  await p.close();

  log('errors:', errors.length ? errors.slice(0, 8) : 'none'); log('assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.error(e); process.exit(2); } })();
