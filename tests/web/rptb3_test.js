// RPT-B3 screens: #/trace, #/recall, #/stockout, #/purchrep, the new stockx tabs, damaged quantity on transfer receive, supplier lot on a purchase line.
// Server calls are stand-ins (the real SQL is tested in supabase/phase430..436_test.sql). 360px width, English and Bangla, CSV download content, "data not captured" instead of 0.
// Run: node rptb3_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const path = require('path'), http = require('http');
const WEB = path.join(SP, '..', '..', 'web');      // serve THIS checkout (s10_common.serve points at the main checkout)
const base = C.baseData(SP), PORT = 8391;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[path.extname(f)] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const day = new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const BATCH = { batch_id: 11, item_id: 'i0', code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', location_id: 1, location: 'Test place', location_en: 'Test place', made_at: day + 'T01:00:00Z', expires_at: null, qty_made: 100, qty_remaining: 80, lot_no: 'LOT-T1', base_unit: 'kg',
  origin: { type: 'receipt', supplier: 'test_supplier_a', bill_no: 'B-1', bill_date: day, lot_no: 'LOT-T1', expiry: null } };
const FG = Object.assign({}, BATCH, { batch_id: 12, code: 'T-FG', name_bn: 'test_fg', name_en: 'test_fg', lot_no: null, qty_made: 10, qty_remaining: 5, origin: { type: 'production', made_at: day } });
const TRACE = { batch: BATCH, warnings: [], back: { root_batch_id: 11, inputs: [], unbatched_inputs: [] },
  forward: { batches: [Object.assign({ relation: 'start' }, BATCH), Object.assign({ relation: 'made_from' }, FG)], sales: [{ sale_id: 's1', receipt: 7, sale_date: day, location_id: 2, location: 'Test shop', location_en: 'Test shop', customer: 'test_customer_a', customer_id: null, qty: 2, batch_id: 12, code: 'T-FG' }, { sale_id: 's2', receipt: 8, sale_date: day, location_id: 1, location: 'Test place', location_en: 'Test place', customer: null, qty: 1.5, batch_id: 12, code: 'T-FG' }],
    sales_total: 2, sales_truncated: false, made_into: [], transfers: [{ transfer_id: 't1', from_batch_id: 12, qty_sent: 4, from_location_id: 1, to_location_id: 2, status: 'sent', received_qty: null, sent_at: day }], taken_out: [{ batch_id: 11, reason: 'wastage', qty: 1 }], issued_without_run: [{ batch_id: 11, qty: 3 }], hidden_places: 1, batches_truncated: false,
    summary: { by_place: [{ location_id: 1, location: 'Test place', location_en: 'Test place', on_hand: 85, sold: 1.5, sales_n: 1, in_transit: 0 }], unbatched: [{ code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', location_id: 1, base_unit: 'kg', unbatched: 50, negative: false }], named_customers: 1, sales_without_customer: 1 } } };
const CASE = { case: { id: '11111111-1111-1111-1111-111111111111', case_no: 3, title: 'test recall', reason: 'test reason', hazard: null, status: 'open', opened_at: day, opened_staff: 'owner1' }, entered: [Object.assign({}, BATCH, { action_status: 'to_do', action_note: null })], forward: TRACE.forward,
  summary: TRACE.forward.summary, unlotted_receipts: [{ bill_id: 'b9', bill_no: 'B-9', bill_date: day, supplier: 'test_supplier_a', code: 'T-RAW', qty: 10 }], data_notes: ['unbatched_stock_present'] };
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M || (window.__M = { calls: [] });
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)); const W = window.__W = Object.assign({ err: {}, hideCost: false }, window.__W0 || {});
 const R = ${JSON.stringify({ TRACE, CASE, BATCH, FG })};
 c.rpc = async (fn, args) => {
  const own = /^(trace_batch|recall_|rb3_log_export|stockout_|shelf_life_missing|supplier_returns_report|purch_price_variance|supplier_rejection_rate|supplier_dependency|supplier_delivery_perf|supplier_price_|item_supplier_|transfer_damage_report|yield_report|qc_list|qc_gate|qc_record|stock_receive_transfer|receipt_lots_|has_grant)/;
  if (!own.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn] } };
  const ok = (d) => ({ data: clone(d), error: null });
  switch (fn) {
   case 'has_grant': return ok(true);
   case 'trace_batch_find': return ok([R.BATCH, R.FG]);
   case 'trace_batch': return ok(R.TRACE);
   case 'recall_list': return ok([{ id: R.CASE.case.id, case_no: 3, title: 'test recall', reason: 'test reason', status: 'open', opened_at: '${day}', batches_n: 1, to_do_n: 1 }]);
   case 'recall_affected': return ok(R.CASE);
   case 'recall_open': return ok({ id: R.CASE.case.id, case_no: 3 });
   case 'stockout_summary': return ok({ rows: [{ location_id: 1, location: 'Test place', location_en: 'Test place', item_id: 'i0', code: 'T-FG', name_bn: 'test_fg', name_en: 'test_fg', base_unit: 'kg', events: 2, days: 1, last_date: '${day}', est_missed_total: null, est_captured_n: 0, est_not_captured_n: 2, on_hand_now: null, tracked: true }] });
   case 'stockout_list': return ok({ rows: [{ id: 'so1', log_date: '${day}', location_id: 1, location: 'Test place', location_en: 'Test place', code: 'T-FG', name_bn: 'test_fg', name_en: 'test_fg', base_unit: 'kg', note: 'test note', est_missed_qty: null, status: 'open', created_staff: 'owner1' }] });
   case 'stockout_add': return ok({ id: 'so2' });
   case 'supplier_returns_report': return ok({ cost_hidden: W.hideCost, returns: [{ bill_id: 'r1', bill_no: 'R-1', bill_date: '${day}', supplier: 'test_supplier_a', location: 'Test place', ref_bill_id: 'b1', ref_bill_no: 'B-1', reason_code: 'damaged', reason_label: 'Damaged', total: W.hideCost ? null : 200, variance: null, items: [{ code: 'T-RAW', qty: 2, unit: 'kg' }] }], discounts: [], voided: [], refunds: [], summary: [{ supplier: 'test_supplier_a', purchases_n: 3, purchases_total: W.hideCost ? null : 2350, returns_n: 1, returns_total: W.hideCost ? null : 200, return_pct: W.hideCost ? null : 8.51, discounts_total: null, voided_n: 0, voided_total: null, refunds_n: 0, refunds_total: null }] });
   case 'supplier_price_list': return ok([{ id: 1, item_id: 'i0', code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', supplier: 'test_supplier_a', price: 110, unit: 'kg', base_unit: 'kg', price_base: 110, effective_from: '${day}', effective_to: null, active: true, current: true, can_edit: true }]);
   case 'purch_price_variance': return ok({ lines: 2, lines_with_agreed: 1, lines_without_agreed: 1, extra_cost_total: 100, summary: [], rows: [{ bill_id: 'b1', bill_no: 'B-1', bill_date: '${day}', supplier: 'test_supplier_a', code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', base_unit: 'kg', qty: 10, actual_price: 120, agreed_price: 110, diff: 10, diff_pct: 9.09, extra_cost: 100, location: 'x' }, { bill_id: 'b2', bill_no: 'B-2', bill_date: '${day}', supplier: 'test_supplier_b', code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', base_unit: 'kg', qty: 4, actual_price: 130, agreed_price: null, diff: null, diff_pct: null, extra_cost: null, location: 'x' }] });
   case 'supplier_rejection_rate': return ok({ rows: [{ supplier_id: 'sp1', supplier: 'test_supplier_a', checks: 2, pass: 1, hold: 0, reject: 1, reject_rate_pct: 50, qty_captured_n: 0, qty_not_captured_n: 2, qty_checked: null, qty_rejected: 0, reject_rate_qty_pct: null, receipts_n: 3, share_checked_pct: 66.7, supplier_not_captured: false }], checks: [{ check_id: 'q1', source_id: 'b1', day: '${day}', status: 'reject', supplier: 'test_supplier_a', code: null, qty: null, note: 'smell', is_bill: true }] });
   case 'supplier_dependency': return ok({ cost_hidden: false, summary: { single_supplier: 1, declared_not_captured: 1, no_alternative: 0, preferred_not_main: 0, used_not_declared: 0 }, rows: [{ item_id: 'i0', code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', base_unit: 'kg', suppliers_used: 1, qty_total: 24, top_supplier: 'test_supplier_a', top_share_pct: 100, value_total: 2400, preferred: [], alternatives: [], used: [{ supplier: 'test_supplier_a', share_pct: 100, qty: 24, value: 2400, declared: false }], flags: ['single_supplier_used', 'declared_suppliers_not_captured'] }] });
   case 'supplier_delivery_perf': return ok({ summary: [{ supplier: 'test_supplier_a', pos: 2, received_complete: 1, on_time: 1, late: 0, on_time_pct: 100, avg_days_late: null, avg_lead_days: 6, overdue_open: 0, partial: 0, promised_date_not_captured: 1 }], rows: [{ entry_id: 'e1', po_no: 'PO-T1', po_date: '${day}', location: 'Test place', supplier: 'test_supplier_a', promised_date: null, first_grn: '${day}', last_grn: '${day}', days_late: null, status: 'received_no_promised_date' }] });
   case 'transfer_damage_report': return ok({ received_n: 2, damaged_not_captured_n: 1, damaged_total_captured: 1.5, rows: [{ transfer_id: 't1', day: '${day}', from_name: 'A', to_name: 'B', code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', qty_sent: 5, received_qty: 4, short: 1, damaged: 1.5, reason_label: 'Broken', batch_id: 12 }, { transfer_id: 't2', day: '${day}', from_name: 'A', to_name: 'B', code: 'T-RAW', name_bn: 'test_raw', name_en: 'test_raw', qty_sent: 2, received_qty: 2, short: 0, damaged: null, reason_label: null, batch_id: null }] });
   case 'yield_report': return ok({ summary: [{ code: 'T-FG', name_bn: 'test_fg', name_en: 'test_fg', runs: 2, actual_captured: 1, actual_not_captured: 1, var_pct: -10 }], rows: [{ run_id: 'r1', day: '${day}', location: 'Test place', code: 'T-FG', name_bn: 'test_fg', name_en: 'test_fg', yield_std: 10, yield_actual: null, var_pct: null, batch_id: 12 }] });
   case 'shelf_life_missing': return ok({ count: 1, items: [{ item_id: 'i0', code: 'T-FG', name_bn: 'test_fg', name_en: 'test_fg', why: 'recipe' }] });
   case 'qc_gate': return ok({ status: null, switch_on: false, blocked: false });
   case 'qc_list': return ok([{ id: 'q1', source_type: 'grn', source_id: 'b1', location_id: 1, status: 'reject', checks: [], note: 'smell', created_at: '${day}T01:00:00Z', created_staff: 'x', history_n: 1, item_id: null, item_code: null, qty: null, supplier_id: null, supplier_name: null }]);
   case 'receipt_lots_get': return ok([]);
   default: return ok({ ok: true }); } };
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
    data.tables.suppliers = [{ id: 'sp1', name: 'test_supplier_a', active: true }]; data.tables.option_lists.push({ list_code: 'transfer_damage_reasons', value_code: 'broken', label_bn: 'ভেঙে গেছে', label_en: 'Broken', label_mix: 'Broken', sort: 1, active: true });
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1200); return p;
  }
  const wait = (p, t = 300) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const txt = (p, s = 'body') => p.textContent(s);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth); ok(r <= 1, 'no horizontal scroll at 360px: ' + m + ' (' + r + ')'); };
  const csvOf = async (p, sel) => { const [d] = await Promise.all([p.waitForEvent('download'), p.click(sel)]); return fs.readFileSync(await d.path(), 'utf8'); };

  // ---- registry
  let p = await open({}, '#/home');
  const reg = await p.evaluate(() => { const ia = window.BOS.IA, want = ['trace', 'recall', 'stockout', 'purchrep', 'report/p2_rate_trend']; return { each: want.map((w) => ia.filter((r) => r.route === w).length), g: want.map((w) => (ia.find((r) => r.route === w) || {}).group), pages: want.slice(0, 4).map((w) => !!window.BOS_PAGES[w]) }; });
  ok(reg.each.every((x) => x === 1) && JSON.stringify(reg.g) === JSON.stringify(['stock', 'stock', 'stock', 'purch', 'purch']) && reg.pages.every(Boolean), 'five records once, in stock / purch, pages exist: ' + JSON.stringify(reg)); await p.close();

  // ---- trace search + detail
  p = await open({}, '#/trace'); await p.fill('#tr_q', 'LOT'); await p.click('[data-act=tr_find]'); await wait(p, 400);
  ok(await p.locator('[data-act=tr_open]').count() === 2 && /test_supplier_a/.test(await txt(p, '#tr_res')) && /LOT-T1/.test(await txt(p, '#tr_res')), 'search lists batches with supplier and lot');
  ok(/data not captured: expiry date/.test(await txt(p, '#tr_res')), 'a missing expiry is said, not blank');
  await p.click('[data-act=tr_open][data-v="11"]'); await wait(p, 500);
  let t = await txt(p, '#tr_detail');
  ok((await calls(p, 'trace_batch')).length === 1 && /Where it went/.test(t) && /test_customer_a/.test(t) && /no customer name recorded/.test(t), 'detail shows sales with a named customer and "no customer name recorded"');
  ok(/Same items NOT in any batch/.test(t) && /50/.test(t) && /outside what you may see/.test(t) && /Issued by hand/.test(t), 'unbatched quantity, hidden places and manual issue are printed');
  ok(/in transit/.test(t) || /Transit/.test(t), 'in transit shown');
  await p.click('[data-act=tr_sale][data-i="0"]'); await wait(p, 200); ok(/Receipt #7/.test(await txt(p, '#sheet')), 'a sale row opens its detail (drill-down)'); await p.click('[data-act=closesheet]');
  const csv = await csvOf(p, '[data-act=tr_csv]'); ok(/LOT-T1/.test(csv) && /test_customer_a/.test(csv) && /no customer name recorded/.test(csv) && (await calls(p, 'rb3_log_export')).length === 1, 'CSV has the lot, the customer and "no customer name recorded"; the export was logged first');
  await noOverflow(p, 'trace detail'); await p.click('[data-act=tr_recall]'); await wait(p, 600); ok(/#\/recall\/new\/11/.test(await p.evaluate(() => location.hash)), 'start-recall goes to the recall screen with the batch'); await p.close();

  // ---- recall
  p = await open({}, '#/recall/new/11'); await wait(p, 400);
  ok(await p.locator('#rc_t').count() === 1 && /paper form code: to be given by owner/.test(await txt(p, '#sheet')), 'new case sheet, with the paper-form-code line');
  await p.click('[data-act=rc_create]'); await wait(p, 200); ok((await calls(p, 'recall_open')).length === 0, 'title and reason are required before anything is sent');
  await p.fill('#rc_t', 'test recall'); await p.fill('#rc_r', 'test reason'); await p.click('[data-act=rc_create]'); await wait(p, 600);
  let c = await calls(p, 'recall_open'); ok(c.length === 1 && c[0].p_batches[0] === 11 && c[0].p_title === 'test recall', 'recall_open sent with the batch');
  ok(/recall\/11111111/.test(await p.evaluate(() => location.hash)), 'goes to the case'); t = await txt(p, 'body');
  ok(/Affected stock/.test(t) && /Receipts of the same item and supplier with NO lot recorded/.test(t) && /B-9/.test(t) && /Same items NOT in any batch/.test(t), 'case shows the affected-stock report, unlotted receipts and unbatched stock');
  await p.click('[data-act=rc_mark]'); await wait(p, 200); await p.selectOption('#rc_st', 'written_off'); await p.click('[data-act=rc_markgo]'); await wait(p, 400);
  c = await calls(p, 'recall_batch_mark'); ok(c.length === 1 && c[0].p_status === 'written_off' && c[0].p_batch === 11, 'mark sends the status');
  await p.click('[data-act=rc_close]'); await wait(p, 200); await p.click('[data-act=rc_closego]'); await wait(p, 200); ok((await calls(p, 'recall_close')).length === 0, 'closing needs a note');
  await p.click('.sheet-x'); await wait(p, 200);
  const rcsv = await csvOf(p, '[data-act=rc_csv]'); ok(/Recall,3,test recall/.test(rcsv) && /B-9/.test(rcsv), 'case CSV'); await noOverflow(p, 'recall case'); await p.close();

  // ---- stockout
  p = await open({}, '#/stockout'); await wait(p, 300);
  t = await txt(p, '#so_out'); ok(/data not captured: estimate/.test(t) && /2 times/.test(t) && /stock not tracked|no stock record/.test(t), 'summary says "data not captured" for a missing estimate and has no made-up stock figure');
  await p.fill('#so_item', 'I-001'); await p.evaluate(() => {});
  const first = await p.evaluate(() => { const o = document.querySelector('#so_dl option'); return o ? o.value : ''; });
  await p.fill('#so_item', first); await p.fill('#so_note', 'test note'); await p.click('[data-act=so_save]'); await wait(p, 500);
  c = await calls(p, 'stockout_add'); ok(c.length === 1 && c[0].p_est_qty === null && c[0].p_unit === null && c[0].p_note === 'test note' && !!c[0].p_client, 'save without an estimate sends null, not 0');
  const scsv = await csvOf(p, '[data-act=so_csv]'); ok(/data not captured: estimate/.test(scsv), 'CSV says data not captured'); await noOverflow(p, 'stockout'); await p.close();

  // ---- purchasing reports
  p = await open({}, '#/purchrep'); await wait(p, 500); t = await txt(p, '#pr_out');
  ok(/Purchase returns/.test(t) && /Damaged/.test(t) && /8.51%/.test(t), 'returns tab'); ok(await p.locator('[data-act=pr_go][data-v="#/purchase/r1"]').count() === 1, 'a return opens its bill (drill-down)');
  ok(/Open the report/.test(await txt(p)), 'price trend link');
  for (const [tab, pat] of [['price', /without an agreed price/], ['rej', /50%/], ['sup', /declared suppliers: data not captured/], ['del', /promised date/]]) {
    await p.click(`[data-act=pur_tab][data-v=${tab}]`); await wait(p, 500); t = await txt(p, '#pr_out'); ok(pat.test(t), 'tab ' + tab + ' shows ' + pat); await noOverflow(p, tab);
  }
  ok(/data not captured: quantity/.test(await (async () => { await p.click('[data-act=pur_tab][data-v=rej]'); await wait(p, 400); return txt(p, '#pr_out'); })()), 'rejection tab: quantity rate not 0 when no quantity was typed');
  const pcsv = await csvOf(p, '#pr_out [data-act=pur_csv]'); ok(/test_supplier_a/.test(pcsv), 'CSV of the rejection tab'); await p.close();
  p = await open({ w: { hideCost: true } }, '#/purchrep'); await wait(p, 500); ok(/may not see money figures/.test(await txt(p, '#pr_out')) && !/ ৳ 200/.test(await txt(p, '#pr_out')), 'without the cost right the money is hidden and said so'); await p.close();
  p = await open({ lang: 'bn' }, '#/purchrep'); await wait(p, 500); ok(/ক্রয় ফেরত/.test(await txt(p, '#pr_out')), 'Bangla'); await noOverflow(p, 'purchrep bn'); await p.close();

  // ---- stockx tabs
  p = await open({}, '#/stockx'); await wait(p, 400);
  await p.click('[data-act=sx_tab][data-v=ex]'); await wait(p, 500); ok(await p.locator('[data-shelf-missing]').count() === 1 && /Shelf life is NOT set/.test(await txt(p, '#sx_out')), 'expiry tab: shelf life not set notice');
  await p.click('[data-act=sx_tab][data-v=qc]'); await wait(p, 500); t = await txt(p, '#sx_out'); ok(/data not captured: item/.test(t) && /data not captured: supplier/.test(t) && /data not captured: quantity/.test(t), 'quality tab says what was not captured');
  await p.selectOption('#sx_qst_f', 'reject'); await p.click('[data-act=sx_go]'); await wait(p, 400); c = await calls(p, 'qc_list'); ok(c[c.length - 1].p_status === 'reject', 'status filter sent');
  await p.click('[data-act=sx_tab][data-v=dm]'); await wait(p, 500); t = await txt(p, '#sx_out'); ok(/data not captured: damaged quantity/.test(t) && /1 receipts without a damaged quantity/.test(t) && /Broken/.test(t), 'damaged tab: not captured is said and counted');
  ok(await p.locator('[data-act=go][data-v="trace/12"]').count() === 1, 'damaged row links to the trace');
  const dcsv = await csvOf(p, '#sx_out [data-act=sx_csv]'); ok(/data not captured: damaged quantity/.test(dcsv), 'damaged CSV');
  await p.click('[data-act=sx_tab][data-v=yi]'); await wait(p, 500); t = await txt(p, '#sx_out'); ok(/data not captured: actual yield/.test(t) && /-10%/.test(t), 'yield tab: actual yield missing is said'); await noOverflow(p, 'stockx yield'); await p.close();

  // ---- purchase line lot fields
  p = await open({}, '#/purchase/new'); await wait(p, 600);
  const first2 = await p.evaluate(() => { const o = document.querySelector('#pu_dl option'); return o ? o.value : ''; });
  await p.fill('[data-ln="0.item"]', first2); await p.evaluate(() => { const el = document.querySelector('[data-ln="0.item"]'); el.dispatchEvent(new Event('change', { bubbles: true })); }); await wait(p, 300);
  ok(await p.locator('[data-ln="0.lot"]').count() === 1 && await p.locator('[data-ln="0.lotexp"]').count() === 1, 'a stock line has optional supplier lot and expiry fields');
  ok(/to be given by owner/.test(await txt(p, '#pe_lines')), 'paper-form-code line');
  await noOverflow(p, 'purchase editor'); await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
