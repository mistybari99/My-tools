// P3 slice b web: online orders (#/onlineorders), forms 20-x <-> sales (#/saleforms), benefits report (#/benefitsx), BI export (#/biexport).
// Run: timeout 250 node salesx_test.js <abs tests/web dir>      (the test injects <script src="salesx.js"> into index.html; the lead adds the real tag)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const SX = window.__SX = Object.assign({ orders: [], fail: {}, forms: [], linked: [], grants: [], missing: [], exportRes: null }, window.__SX0 || {});
 const e = (m) => ({ data: null, error: { message: m, code: 'P0001' } });
 c.rpc = async (fn, args) => {
  (window.__AC = window.__AC || []).push([fn, clone(args || {})]);
  if (SX.fail[fn]) { const m = SX.fail[fn]; delete SX.fail[fn]; return e(m); }
  if (fn === 'online_orders_list') return { data: SX.orders.filter((o) => !args.p_status || o.status === args.p_status).map((o) => Object.assign({}, o, { balance: o.subtotal - o.discount + o.delivery_charge - o.advance })), error: null };
  if (fn === 'online_order_save') { if (args.p_id) { const o = SX.orders.find((x) => x.id === args.p_id); Object.assign(o, { customer_name: args.p_name }); return { data: { id: o.id }, error: null }; }
    const sub = args.p_lines.reduce((s, l) => s + l.qty * 100, 0); const o = { id: 'o' + (SX.orders.length + 1), order_no: SX.orders.length + 1, location_id: args.p_loc, channel: args.p_channel, customer_name: args.p_name, customer_mobile: args.p_mobile,
      delivery_mode: args.p_delivery_mode, delivery_date: args.p_delivery_date, subtotal: sub, discount: args.p_discount, delivery_charge: args.p_charge, advance: args.p_advance, status: 'new', sale_id: null, lines: args.p_lines, created_at: 'x' };
    SX.orders.push(o); return { data: { id: o.id, order_no: o.order_no }, error: null }; }
  if (fn === 'online_order_status') { SX.orders.find((x) => x.id === args.p_id).status = args.p_to; return { data: { status: args.p_to }, error: null }; }
  if (fn === 'online_order_cancel') { const o = SX.orders.find((x) => x.id === args.p_id); o.status = 'cancelled'; return { data: { status: 'cancelled' }, error: null }; }
  if (fn === 'online_order_deliver') { const o = SX.orders.find((x) => x.id === args.p_id); o.status = 'delivered'; return { data: { status: 'delivered', sale_id: 's9', receipt: 77 }, error: null }; }
  if (fn === 'online_order_link_sale') { SX.orders.find((x) => x.id === args.p_id).status = 'delivered'; return { data: { status: 'delivered' }, error: null }; }
  if (fn === 'unlinked_sale_forms') return { data: SX.forms, error: null };
  if (fn === 'sale_form_link') { T.sale_form_links.push({ id: 5, sale_id: args.p_sale, entry_id: args.p_entry, form_code: '20-1', amount_diff: 0, location_id: 1, state: 'active', linked_at: 'x' }); SX.forms = SX.forms.filter((f) => f.entry_id !== args.p_entry); return { data: { id: 5, amount_diff: 0 }, error: null }; }
  if (fn === 'sale_form_unlink') { T.sale_form_links.length = 0; return { data: { state: 'void' }, error: null }; }
  if (fn === 'benefits_report') return { data: { as_of: args.p_as_of, grants: SX.grants, missing: SX.missing, paid_in_payroll_monthly_visible: 0 }, error: null };
  if (fn === 'employee_benefit_grant') { SX.grants.push({ id: 9, employee_id: args.p_emp, employee_name: 'এমপ ১', type_code: args.p_type, from_date: args.p_from, eligible_from: args.p_from, to_date: null, state: 'eligible', paid_in_payroll: false, value_per_month: null }); return { data: { id: 9 }, error: null }; }
  if (fn === 'employee_benefit_grant_end') { SX.grants.forEach((g) => { g.state = 'ended'; }); return { data: { id: args.p_id }, error: null }; }
  if (fn === 'bi_export') return { data: SX.exportRes || { dataset: args.p_dataset, format: args.p_format, columns: ['id'], row_count: 3, truncated: !!args.p_limit, cap: 5000, cost_visible: false, log_id: 1, csv: 'id\\n1\\n2\\n3', rows: [{ id: 1 }, { id: 2 }, { id: 3 }] }, error: null };
  if (fn === 'bi_export_log_list') return { data: [{ at: '2026-10-13T10:00:00Z', dataset: 'sales', row_count: 3, truncated: false, format: 'csv' }], error: null };
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  const html = fs.readFileSync(_P.WEB_DIR + '/index.html', 'utf8').replace('</body>', '<script src="salesx.js"></script></body>');
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001|status of 4/.test(m.text()) && !/^Error: /.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept('wrong sale'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: html }));
    const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
    T.items = [{ id: 'it1', code: 'C1', name_bn: 'কেক', name_en: 'Cake', sell_price: 100, is_active: true }, { id: 'it2', code: 'C2', name_bn: 'মিষ্টি', name_en: 'Sweet', sell_price: 50, is_active: true }];
    T.sales = [{ id: 's1', receipt: 12, total: 330, sale_date: '2026-10-13', location_id: 1, status: 'done', sold_at: '2026-10-13T10:00:00Z' }, { id: 's2', receipt: 13, total: 100, sale_date: '2026-10-13', location_id: 1, status: 'done', sold_at: '2026-10-13T11:00:00Z' }];
    T.employees = [{ id: 'em1', full_name_bn: 'এমপ ১', employee_no: 'E1', status: 'active' }];
    T.benefit_types = [{ code: 'meal', name_bn: 'খাবার', name_en: 'Meal', paid_in_payroll: false, eligible_after_days: 0, default_for_all: false, active: true, sort: 1 }, { code: 'festival', name_bn: 'উৎসব', name_en: 'Festival', paid_in_payroll: true, eligible_after_days: 90, default_for_all: true, active: true, sort: 2 }];
    T.sale_form_links = [];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__SX0=${JSON.stringify(o.sx || {})};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const txt = (p) => p.evaluate(() => document.body.innerText);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // ---- online orders ----
  let p = await open('#/onlineorders');
  ok(/Online orders/.test(await txt(p)) && /Nothing/.test(await txt(p)), 'orders page opens, empty list says nothing');
  await p.click('[data-act=sx_new]'); await wait(p, 500);
  ok(await p.locator('#sx_form').count() === 1 && await p.locator('[data-line]').count() === 1, 'new-order sheet with one item line');
  await p.fill('#sx_n', 'Rina'); await p.fill('#sx_m', '01711000001'); await p.selectOption('#sx_dm', 'pickup'); await p.fill('[data-sxl=qty]', '2'); await p.fill('#sx_ad', '50'); await p.selectOption('#sx_am', 'mobile');
  await noOverflow(p, 'order sheet'); await p.screenshot({ path: SP + '/sx_order_form.png' });
  await p.click('[data-act=sx_save]'); await wait(p, 600);
  let c = await calls(p, 'online_order_save');
  ok(c.length === 1 && c[0].p_name === 'Rina' && c[0].p_lines.length === 1 && c[0].p_lines[0].qty === 2 && c[0].p_lines[0].item_id === 'it1' && c[0].p_advance === 50 && c[0].p_adv_mode === 'mobile' && /^[0-9a-f-]{36}$/.test(c[0].p_client) && c[0].p_id === null, 'save sends lines, advance + mode, a client id');
  ok(await p.locator('[data-order=o1]').count() === 1 && /Rina/.test(await txt(p)) && /New/.test(await p.locator('[data-order=o1]').innerText()), 'order card appears as New');
  ok(/Balance\s+৳ 150/.test(await p.locator('[data-order=o1]').innerText()), 'balance = 200 - 50 shown');
  await p.click('[data-order=o1] [data-act=sx_st_confirmed]'); await wait(p, 500);
  ok((await calls(p, 'online_order_status'))[0].p_to === 'confirmed' && /Confirmed/.test(await p.locator('[data-order=o1]').innerText()), 'confirm');
  ok(await p.locator('[data-order=o1] [data-act=sx_deliver]').count() === 0, 'cannot deliver before packed (button hidden)');
  await p.click('[data-order=o1] [data-act=sx_st_packed]'); await wait(p, 500);
  await p.click('[data-order=o1] [data-act=sx_deliver]'); await wait(p, 400);
  ok(await p.inputValue('#sx_pa') === '150', 'deliver sheet prefilled with the balance');
  await p.click('[data-act=sx_deliver_go]'); await wait(p, 600);
  c = await calls(p, 'online_order_deliver');
  ok(c.length === 1 && c[0].p_payments.length === 1 && c[0].p_payments[0].amount === 150 && c[0].p_payments[0].mode === 'cash', 'deliver sends the collected payment');
  ok(/Delivered/.test(await p.locator('[data-order=o1]').innerText()) && await p.locator('[data-order=o1] .row.wrap button').count() === 0, 'delivered order has no more buttons');
  // error text friendly
  await p.evaluate(() => { window.__SX.fail.online_order_save = 'module_off'; }); await p.click('[data-act=sx_new]'); await wait(p, 400); await p.fill('#sx_n', 'X'); await p.fill('#sx_m', '01711000002'); await p.click('[data-act=sx_save]'); await wait(p, 500);
  ok(/switched off/.test(await p.evaluate(() => document.querySelector('#toast').textContent)), 'module_off shown as friendly text');
  // cancel with advance fate
  p = await open('#/onlineorders', { sx: { orders: [{ id: 'o7', order_no: 7, location_id: 1, channel: 'phone', customer_name: 'Sumi', customer_mobile: '017', delivery_mode: 'pickup', subtotal: 100, discount: 0, delivery_charge: 0, advance: 20, status: 'confirmed', lines: [] }] } });
  await p.click('[data-order=o7] [data-act=sx_cancel]'); await wait(p, 400);
  ok(await p.locator('#sx_cf').count() === 1, 'advance fate asked when there is an advance');
  await p.fill('#sx_cr', 'no answer'); await p.selectOption('#sx_cf', 'refund'); await p.click('[data-act=sx_cancel_go]'); await wait(p, 500);
  c = await calls(p, 'online_order_cancel'); ok(c.length === 1 && c[0].p_reason === 'no answer' && c[0].p_advance_fate === 'refund', 'cancel sends reason + fate');
  await p.click('[data-act=sx_linksale]').catch(() => {}); // cancelled order has no link button
  p = await open('#/onlineorders', { sx: { orders: [{ id: 'o8', order_no: 8, location_id: 1, channel: 'phone', customer_name: 'Tia', customer_mobile: '017', delivery_mode: 'pickup', subtotal: 100, discount: 0, delivery_charge: 0, advance: 0, status: 'confirmed', lines: [] }] } });
  await p.click('[data-order=o8] [data-act=sx_linksale]'); await wait(p, 500); ok(await p.locator('#sx_ls option').count() === 2, 'link sheet lists the sales of the place');
  await p.selectOption('#sx_ls', 's2'); await p.click('[data-act=sx_link_go]'); await wait(p, 500);
  c = await calls(p, 'online_order_link_sale'); ok(c.length === 1 && c[0].p_sale === 's2', 'link sends the picked sale'); await noOverflow(p, 'orders');
  p = await open('#/onlineorders', { lang: 'bn' }); ok(/অনলাইন অর্ডার/.test(await txt(p)), 'Bangla mode');

  // ---- forms <-> sales ----
  p = await open('#/saleforms', { sx: { forms: [{ entry_id: 'en1', form_code: '20-1', serial: 4, entry_date: '2026-10-13', location_id: 1, customer: 'Rina', form_total: 330, candidate_sales: ['s1'] }, { entry_id: 'en2', form_code: '20-4', serial: 5, entry_date: '2026-10-13', location_id: 1, customer: 'Party A', form_total: null, candidate_sales: [] }] } });
  ok(/Not linked to a sale \(2\)/.test(await txt(p)) && /#12/.test(await txt(p)) && /Rina/.test(await txt(p)), 'unlinked forms with the candidate sale receipt');
  await noOverflow(p, 'saleforms'); await p.screenshot({ path: SP + '/sx_forms.png', fullPage: true });
  await p.evaluate(() => { window.__SX.fail.sale_form_link = 'path_locked: x'; }); await p.click('[data-act=sf_link]'); await wait(p, 500);
  ok(/locked/.test(await p.evaluate(() => document.querySelector('#toast').textContent)), 'path_locked friendly');
  await p.click('[data-act=sf_link]'); await wait(p, 600);
  c = await calls(p, 'sale_form_link'); ok(c.length === 2 && c[1].p_entry === 'en1' && c[1].p_sale === 's1', 'link sends entry + sale');
  ok(/Linked \(1\)/.test(await txt(p)) && /Not linked to a sale \(1\)/.test(await txt(p)), 'report refreshed: one linked, one left');
  await p.click('[data-act=sf_unlink]'); await wait(p, 600); c = await calls(p, 'sale_form_unlink'); ok(c.length === 1 && c[0].p_note === 'wrong sale', 'unlink asks a reason');

  // ---- benefits ----
  p = await open('#/benefitsx', { sx: { grants: [{ id: 1, employee_id: 'em1', employee_name: 'এমপ ১', type_code: 'festival', from_date: '2026-09-01', eligible_from: '2026-12-01', to_date: null, state: 'not_yet', paid_in_payroll: true, value_per_month: null },
      { id: 2, employee_id: 'em1', employee_name: 'এমপ ১', type_code: 'meal', from_date: '2026-09-01', eligible_from: '2026-09-01', to_date: null, state: 'eligible', paid_in_payroll: false, value_per_month: 800 }], missing: [{ employee_id: 'em2', employee_name: 'এমপ ২', type_code: 'festival', eligible_from: '2026-06-01' }] } });
  const bt = await txt(p);
  ok(/Report only/.test(bt) && /Not yet eligible/.test(bt) && /Eligible/.test(bt) && /Paid in payroll/.test(bt) && /৳ 800/.test(bt), 'grants with state, paid flag and visible value');
  ok(/Eligible but not granted \(1\)/.test(bt) && /এমপ ২/.test(bt), 'missing list');
  ok(!/Value \/ month ৳ null|undefined|NaN/.test(bt), 'hidden value is not printed as null');
  await p.click('[data-act=bx_add]'); await wait(p, 500); await p.selectOption('#bx_t', 'meal'); await p.fill('#bx_v', '500'); await p.click('[data-act=bx_go]'); await wait(p, 600);
  c = await calls(p, 'employee_benefit_grant'); ok(c.length === 1 && c[0].p_emp === 'em1' && c[0].p_type === 'meal' && c[0].p_value === 500 && c[0].p_id === null && /^[0-9a-f-]{36}$/.test(c[0].p_client), 'grant sends employee, type, value, client id');
  await noOverflow(p, 'benefits'); await p.screenshot({ path: SP + '/sx_benefits.png', fullPage: true });

  // ---- BI export ----
  p = await open('#/biexport');
  ok(await p.locator('#ex_ds option').count() === 5 && /Cost prices appear only/.test(await txt(p)), 'five datasets + cost note');
  await p.selectOption('#ex_ds', 'stock_ledger'); await p.selectOption('#ex_fmt', 'json'); await p.fill('#ex_lim', '2'); await p.click('[data-act=ex_run]'); await wait(p, 600);
  c = await calls(p, 'bi_export'); ok(c.length === 1 && c[0].p_dataset === 'stock_ledger' && c[0].p_format === 'json' && c[0].p_limit === 2 && /^\d{4}-\d\d-\d\d$/.test(c[0].p_from), 'export sends dataset, format, limit and dates');
  ok(/3 rows/.test(await txt(p)) && /Cut at the row cap/.test(await txt(p)) && await p.locator('[data-act=ex_dl]').count() === 1, 'result with row count, truncated notice, download button');
  ok(/Export log/.test(await txt(p)), 'owner sees the log');
  await p.evaluate(() => { window.__SX.fail.bi_export = 'cost_not_allowed: x'; }); await p.selectOption('#ex_ds', 'purchases'); await p.click('[data-act=ex_run]'); await wait(p, 500);
  ok(/cost right/.test(await p.evaluate(() => document.querySelector('#toast').textContent)), 'cost_not_allowed friendly');
  const dl = p.waitForEvent('download', { timeout: 4000 }).catch(() => null); await p.selectOption('#ex_ds', 'sales'); await p.selectOption('#ex_fmt', 'csv'); await p.fill('#ex_lim', ''); await p.click('[data-act=ex_run]'); await wait(p, 500); await p.click('[data-act=ex_dl]');
  const d = await dl; ok(d && /^sales_\d{4}-\d\d-\d\d_\d{4}-\d\d-\d\d\.csv$/.test(d.suggestedFilename()), 'csv file name');
  await noOverflow(p, 'export'); await p.screenshot({ path: SP + '/sx_export.png', fullPage: true });
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
