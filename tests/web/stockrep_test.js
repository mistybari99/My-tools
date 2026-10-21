// RPT-B2 web pieces: #/stockrep (movement ledger, period reconciliation), #/batchrep (batch stock, ageing, unsold, distribution, expired/damaged/unsold, trace), the report viewer additions
// (sub-totals, "not captured" cells, row drill, item-type filter), the registry placement in web/ia.js, CSV on every page, 360px width, three language modes.
// The server functions are mocked here (supabase/phase420..425_test.sql check the database). Run: node stockrep_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const ROOT = path.join(__dirname, '..', '..', 'web');
const base = C.baseData(SP), PORT = 8742, srv = require('http').createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = path.extname(f); r.writeHead(200, { 'content-type': x === '.js' ? 'text/javascript' : x === '.css' ? 'text/css' : x === '.html' ? 'text/html' : 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const ITEM = '11111111-0000-0000-0000-0000000000a1';
const LEDGER = { item: { id: ITEM, code: 'test_fg_sweet', name_bn: 'test_মিষ্টি', name_en: 'test_sweet', unit: 'kg' }, location: { id: 1, name_bn: 'শোরুম', name_en: 'Test outlet' }, from: '2026-10-01', to: '2026-10-17',
  opening: 0, closing: 7.7, row_count: 3, truncated: false, summary: [{ reason: 'transfer_in', rows: 1, in_qty: 20, out_qty: 0, net: 20 }, { reason: 'sale_out', rows: 1, in_qty: 0, out_qty: 12, net: -12 }, { reason: 'wastage', rows: 1, in_qty: 0, out_qty: 0.3, net: -0.3 }],
  check: { ledger_total_all: 7.7, cached: 7.7, ok: true, later_rows: 0, closing_is_latest: true }, cost_shown: true, notes: [],
  rows: [{ id: 1, day: '2026-10-15', time: '10:00', reason: 'transfer_in', qty_delta: 20, running: 20, unit_cost: 42.5, value: 850, who: 'test_owner', note: null, batch_id: 5, batch_no: null, doc: { kind: 'transfer', label: 'Transfer Factory > Test outlet', detail: { status: 'received', sent_qty: 20 } } },
    { id: 2, day: '2026-10-16', time: '12:30', reason: 'sale_out', qty_delta: -12, running: 8, unit_cost: 42.5, value: -510, who: 'test_sales', note: null, batch_id: 5, batch_no: null, doc: { kind: 'sale', label: 'Sale #990001', detail: { receipt: 990001, status: 'done' } } },
    { id: 3, day: '2026-10-16', time: '15:00', reason: 'wastage', qty_delta: -0.3, running: 7.7, unit_cost: null, value: null, _nc: ['unit_cost', 'value'], who: 'test_sales', note: 'test', batch_id: null, batch_no: null, doc: { kind: 'wastage', label: 'Wastage · Expired', detail: { reason_code: 'expired' } } }] };
const RECON = { from: '2026-10-01', to: '2026-10-17', location_id: null, cost_shown: true, truncated: false,
  summary: { pairs: 2, ok: 1, cache_differs: 1, unclassified: 0, identity_holds: true, in_transit_lines: 1, short_lines: 1, cache_checked: true, later_rows: 0 },
  notes: [{ code: 'info', text_en: 'Opening = the ledger replayed to the day before the start.', text_bn: 'শুরু = আগের দিন পর্যন্ত খাতা।' }],
  rows: [{ item_id: ITEM, location_id: 1, location_bn: 'শোরুম', location_en: 'Test outlet', item_code: 'test_fg_sweet', item_name: 'test_মিষ্টি', item_name_en: 'test_sweet', unit: 'kg', item_type: 'finished_good', opening: 0, opening_entry: 0, purchase_in: 0, production_in: 0, transfer_in: 20, sales_back: 5, sale_out: -15, issue_out: 0, wastage: -2, transfer_out: 0, purchase_return: 0, count_adjust: -0.3, reversal: 0, unclassified: 0, closing: 7.7, identity_diff: 0, later_qty: 0, ledger_total: 7.7, cached: 7.7, cache_diff: 0, in_transit_out: 0, state: 'ok' },
    { item_id: ITEM, location_id: 7, location_bn: 'গোডাউন', location_en: 'Test store', item_code: 'test_raw_flour', item_name: 'test_ময়দা', item_name_en: 'test_flour', unit: 'kg', item_type: 'raw_material', opening: 0, opening_entry: 100, purchase_in: 60, production_in: 0, transfer_in: 0, sales_back: 0, sale_out: 0, issue_out: 0, wastage: 0, transfer_out: -80, purchase_return: -2, count_adjust: -1, reversal: 0, unclassified: 0, closing: 77, identity_diff: 0, later_qty: 0, ledger_total: 77, cached: 79, cache_diff: 2, in_transit_out: 0, state: 'cache_differs' }],
  transit: [{ transfer_id: 't1', sent_day: '2026-10-16', from_name: 'Test factory', to_name: 'Test outlet 4', item_code: 'test_fg_sweet', item_name: 'test_sweet', unit: 'kg', qty: 5, days: 1 }],
  short: [{ transfer_id: 't2', sent_day: '2026-10-15', received_day: '2026-10-16', from_name: 'Test factory', to_name: 'Test outlet 3', item_code: 'test_fg_sweet', item_name: 'test_sweet', unit: 'kg', sent_qty: 10, received_qty: 8, short_qty: 2, claim: 'open', short_value: null, value_missing: true }] };
const cols = (a) => a.map(([key, bn, en, type]) => ({ key, label_bn: bn, label_en: en, type, role: ['money', 'int', 'num', 'pct'].includes(type) ? 'measure' : 'dim' }));
const BATCHES = { cost_shown: true, truncated: false, batches: 2, notes: [{ code: 'data_needed', what: 'shelf_life_rules / expires_at', text_en: '1 batch(es) have no expiry date captured (shown as "no expiry", not safe).', text_bn: '১টি ব্যাচে মেয়াদ লেখা নেই।' }],
  columns: cols([['item_code', 'কোড', 'Code', 'text'], ['item_name', 'আইটেম', 'Item', 'text'], ['row_kind', 'ধরন', 'Row', 'text'], ['batch_no', 'ব্যাচ', 'Batch', 'text'], ['expires_on', 'মেয়াদ শেষ', 'Expires', 'date'], ['days_left', 'বাকি দিন', 'Days left', 'int'], ['state', 'অবস্থা', 'State', 'text'], ['qty', 'পরিমাণ', 'Qty', 'num'], ['value', 'মূল্য', 'Value', 'money']]),
  rows: [{ item_code: 'test_fg_sweet', item_name: 'test_মিষ্টি', row_kind: 'batch', batch_no: '#5', expires_on: '2026-10-18', days_left: 1, state: 'soon', qty: 7.7, value: 327.5, drill: '#/batchrep/trace?batch=5' },
    { item_code: 'test_fg_cake', item_name: 'test_কেক', row_kind: 'batch', batch_no: '#2', expires_on: null, days_left: null, state: 'no_expiry', qty: 3, value: null, _nc: ['expires_on', 'days_left', 'value'], drill: '#/batchrep/trace?batch=2' },
    { item_code: 'test_raw_flour', item_name: 'test_ময়দা', row_kind: 'unbatched', batch_no: null, expires_on: null, days_left: null, state: 'unbatched', qty: 77, value: 3137.75, _nc: ['expires_on', 'days_left', 'batch_no'], drill: '#/stockrep/ledger?item=' + ITEM + '&loc=7' }] };
const AGE = Object.assign({}, BATCHES, { notes: [{ code: 'data_needed', what: 'report_aging_buckets', text_en: 'No age bands are set (rule report_aging_buckets).', text_bn: 'বয়সের ভাগ বসানো নেই।' }],
  columns: cols([['item_name', 'আইটেম', 'Item', 'text'], ['age_days', 'বয়স', 'Age (days)', 'int'], ['age_band', 'ভাগ', 'Age band', 'text'], ['qty', 'পরিমাণ', 'Qty', 'num']]), rows: [{ item_name: 'test_মিষ্টি', age_days: 2, age_band: null, qty: 15, _nc: ['age_band'], drill: '#/batchrep/trace?batch=5' }],
  sections: [{ id: 'by_item', title_bn: 'আইটেম অনুযায়ী বয়স', title_en: 'Age by item', columns: cols([['item_name', 'আইটেম', 'Item', 'text'], ['oldest_days', 'সবচেয়ে পুরনো', 'Oldest (days)', 'int'], ['avg_days', 'গড়', 'Average age', 'num']]), rows: [{ item_name: 'test_মিষ্টি', oldest_days: 2, avg_days: 1.5 }] }] });
const UNSOLD = Object.assign({}, BATCHES, { notes: [], columns: cols([['item_name', 'আইটেম', 'Item', 'text'], ['batch_id', 'ব্যাচ', 'Batch', 'int'], ['made_qty', 'তৈরি', 'Made', 'num'], ['sold_qty', 'বিক্রি', 'Sold', 'num'], ['unsold_qty', 'অবিক্রীত', 'Unsold', 'num'], ['unaccounted_qty', 'হিসাবহীন', 'Not accounted', 'num']]),
  rows: [{ item_name: 'test_মিষ্টি', batch_id: 5, made_qty: 50, sold_qty: 10, unsold_qty: 34.7, unaccounted_qty: 0, drill: '#/batchrep/trace?batch=5' }] });
const DIST = Object.assign({}, UNSOLD, { columns: cols([['item_name', 'আইটেম', 'Item', 'text'], ['location_en', 'Place', 'Place', 'text'], ['role', 'ভূমিকা', 'Role', 'text'], ['received_qty', 'পেয়েছে', 'Received', 'num'], ['sold_qty', 'বিক্রি', 'Sold', 'num']]),
  rows: [{ item_name: 'test_মিষ্টি', location_en: 'Test outlet', role: 'outlet', received_qty: 20, sold_qty: 10, drill: '#/batchrep/trace?batch=5' }, { item_name: 'test_কেক', location_en: 'Test outlet', role: 'no_batch', received_qty: null, sold_qty: 1, _nc: ['received_qty'], drill: '#/stockrep/ledger?item=' + ITEM + '&loc=1' }] });
const EXPD = Object.assign({}, UNSOLD, { columns: cols([['day', 'তারিখ', 'Date', 'date'], ['class', 'ধরন', 'Class', 'text'], ['item_name', 'আইটেম', 'Item', 'text'], ['qty', 'পরিমাণ', 'Qty', 'num'], ['back_in_stock', 'ফিরেছে', 'Back in stock', 'text']]),
  rows: [{ day: '2026-10-16', class: 'expired', item_name: 'test_মিষ্টি', qty: 1.5, back_in_stock: null, drill: '#/batchrep/trace?batch=5' }, { day: '2026-10-16', class: 'damaged', item_name: 'test_মিষ্টি', qty: 2, back_in_stock: true, drill: '#/stockrep/ledger?item=' + ITEM + '&loc=1' }],
  sections: [{ id: 'by_class', title_bn: 'ধরন অনুযায়ী', title_en: 'By class', columns: cols([['class', 'ধরন', 'Class', 'text'], ['entries', 'এন্ট্রি', 'Entries', 'int']]), rows: [{ class: 'expired', entries: 1 }, { class: 'damaged', entries: 1 }] }] });
const TRACE = { batch_id: 5, item: { code: 'test_fg_sweet', name_bn: 'test_মিষ্টি', name_en: 'test_sweet', unit: 'kg' }, made_on: '2026-10-15', expires_on: null, cost_shown: false, truncated: false,
  summary: { made_qty: 50, sold_qty: 10, wasted_qty: 3, other_qty: 0.3, short_qty: 2, in_transit_qty: 5, remaining_qty: 29.7, unaccounted_qty: 0 },
  family: [{ batch_id: 5, location: 'Test factory', made_on: '2026-10-15', expires_on: null, qty_made: 50, qty_remaining: 15 }, { batch_id: 6, location: 'Test outlet', made_on: '2026-10-15', expires_on: null, qty_made: 20, qty_remaining: 7.7 }],
  rows: [{ id: 1, day: '2026-10-15', time: '09:00', location: 'Test factory', batch_id: 5, reason: 'production_in', qty_delta: 50, doc: { label: 'Production run 2026-10-15' } }, { id: 2, day: '2026-10-16', time: '10:00', location: 'Test outlet', batch_id: 6, reason: 'sale_out', qty_delta: -12, doc: { label: 'Sale #990001' } }] };
const VIEW = { report: 'stock_balance', columns: cols([['item_code', 'কোড', 'Code', 'text'], ['item_name', 'আইটেম', 'Item', 'text'], ['qty', 'আছে', 'On hand', 'num'], ['state', 'অবস্থা', 'State', 'text'], ['avg_cost', 'গড় খরচ', 'Avg cost', 'money'], ['value', 'মূল্য', 'Value', 'money']]),
  rows: [{ item_code: 'test_raw_salt', item_name: 'test_লবণ', qty: 9, state: 'no_min', avg_cost: null, value: null, _nc: ['avg_cost', 'value'], drill: '#/stockrep/ledger?item=' + ITEM + '&loc=7' }, { item_code: 'test_fg_cake', item_name: 'test_কেক', qty: -1, state: 'negative', avg_cost: null, value: null, _nc: ['avg_cost', 'value'], drill: '#/stockrep/ledger?item=' + ITEM + '&loc=1' }],
  totals: { value: 1234.5, lines: 2 }, page: { n: 1, size: 50, groups: 2, cap: 500 }, has_more: false, data_needed: false, meta: { from: '2026-10-17', to: '2026-10-17', sort: 'item_name', dir: 'asc', cost_shown: true },
  notes: [{ code: 'data_needed', what: 'unit cost', text_en: '2 stock line(s) with a quantity have no cost recorded.', text_bn: '২টি লাইনে খরচ লেখা নেই।' }],
  subtotals: [{ id: 'by_place', title_bn: 'লোকেশন অনুযায়ী মোট', title_en: 'Totals by place', columns: cols([['name', 'নাম', 'Name', 'text'], ['lines', 'লাইন', 'Lines', 'int'], ['value', 'মূল্য', 'Value', 'money']]), rows: [{ name: 'গোডাউন', name_en: 'Test store', lines: 1, value: 1000 }] }] };
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__RB = window.__RB || { calls: [], o: {} }; const K = ${JSON.stringify({ LEDGER, RECON, BATCHES, AGE, UNSOLD, DIST, EXPD, TRACE, VIEW })};
 c.rpc = async (fn, args) => {
  const mine = /^(stock_movement_ledger|stock_recon_period|batch_stock_rows|fg_ageing_rows|unsold_by_batch|fg_distribution|expired_damaged_unsold|fg_batch_rows|log_report_export4|has_grant|report_catalog|report_catalog2|report_run2|log_report_export2|wastage_by_reason2|wastage_by_reason|near_expiry_report|reorder_report|stock_reconcile|stock_reconcile_fix)$/.test(fn);
  if (!mine) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]); const O = R.o;
  if (O.err && O.err[fn]) return { data: null, error: { message: O.err[fn], code: 'P0001' } };
  if (fn === 'has_grant') return { data: args.p_code === 'export_data' ? !!O.export : true, error: null };
  if (fn === 'stock_movement_ledger') return { data: K.LEDGER, error: null };
  if (fn === 'stock_recon_period') return { data: K.RECON, error: null };
  if (fn === 'batch_stock_rows') return { data: K.BATCHES, error: null };
  if (fn === 'fg_ageing_rows') return { data: K.AGE, error: null };
  if (fn === 'unsold_by_batch') return { data: K.UNSOLD, error: null };
  if (fn === 'fg_distribution') return { data: K.DIST, error: null };
  if (fn === 'expired_damaged_unsold') return { data: K.EXPD, error: null };
  if (fn === 'fg_batch_rows') return { data: K.TRACE, error: null };
  if (fn === 'log_report_export4' || fn === 'log_report_export2') return { data: null, error: null };
  if (fn === 'report_catalog') return { data: [], error: null };
  if (fn === 'report_catalog2') return { data: [{ key: 'stock_balance', group: 'stock', grant: 'report_stock', allowed: true, kind: 'raw', engine: 2, name_bn: 'স্টক ব্যালান্স', name_en: 'Stock balance', name_mix: 'Stock balance', filters: ['locations', 'brands', 'categories', 'item_types'], dims: [], columns: [], compare: false, needs_date: false, cost_only: false }], error: null };
  if (fn === 'report_run2') return { data: K.VIEW, error: null };
  if (fn === 'wastage_by_reason2') return { data: [{ reason_code: 'expired', label_bn: 'মেয়াদ শেষ', label_en: 'Expired', entries: 2, items: 2, qty: null, unit: null, mixed_units: true, units: [{ unit: 'kg', qty: 1.5, entries: 1 }, { unit: 'pc', qty: 1, entries: 1 }] }, { reason_code: 'broken', label_bn: 'ভেঙে', label_en: 'Broken', entries: 1, items: 1, qty: 0.5, unit: 'kg', mixed_units: false, units: [{ unit: 'kg', qty: 0.5, entries: 1 }] }], error: null };
  if (fn === 'near_expiry_report' || fn === 'reorder_report' || fn === 'wastage_by_reason') return { data: [], error: null };
  if (fn === 'stock_reconcile') return { data: [], error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    data.tables.items = (data.tables.items || []).concat([{ id: ITEM, code: 'test_fg_sweet', name_bn: 'test_মিষ্টি', name_en: 'test_sweet', unit: 'kg', is_active: true, tracked: true, item_type: 'finished_good' }]);
    data.tables.item_types = [{ code: 'raw_material', label_bn: 'কাঁচামাল', label_en: 'Raw material', sort: 3, active: true }, { code: 'finished_good', label_bn: 'তৈরি পণ্য', label_en: 'Finished good', sort: 1, active: true }, { code: 'packaging', label_bn: 'প্যাকেজিং', label_en: 'Packaging', sort: 4, active: true }];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=true;window.__RB={calls:[],o:${JSON.stringify(o.o || {})}};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1600); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__RB.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow at 360px: ' + m);
  const click = async (p, sel) => { await p.click(sel); await wait(p, 350); };
  let p, t;

  // ---- 1. registry: every report is placed under its group, nothing duplicated, every route resolves
  p = await open('#/home');
  const reg = await p.evaluate(() => { const ia = window.BOS.IA, pages = window.BOS_PAGES || {}; const ids = ia.map((r) => r.id);
    const g = (id) => { const r = ia.find((x) => x.id === id); return r ? [r.group, r.drawer, (r.also || []).join(',')].join('|') : null; };
    return { dup: ids.length - new Set(ids).size, unresolved: ia.filter((r) => r.status !== 'soon' && !['home', 'items', 'staff', 'matrix', 'rules', 'settings', 'logs', 'backup', 'itemreq'].includes(r.route.split('/')[0]) && !pages[r.route.split('/')[0]]).map((r) => r.route),
      ledger: g('stockrep/ledger'), recon: g('stockrep/recon'), batches: g('batchrep/batches'), sb: g('report/stock_balance'), integ: g('report/stock_integrity'), p4: g('report/p4_supplier_score'), ageing: g('report/supplier_ageing'), slow: g('report/item_slow'),
      keys: ['stock_balance', 'expiry_soon', 'transfers_register', 'transfers_gap', 'k2_count_variance', 'stock_adjustments', 'wastage', 'wastage_rate', 'stock_integrity', 'daily_closing', 'item_turnover', 'item_slow'].filter((k) => !ia.some((r) => r.id === 'report/' + k)),
      pages: ['ledger', 'recon', 'batches', 'ageing', 'unsold', 'distribution', 'expired', 'trace'].filter((k) => !ia.some((r) => r.id === (['ledger', 'recon'].includes(k) ? 'stockrep/' : 'batchrep/') + k)), hasPages: !!pages.stockrep && !!pages.batchrep, oldRoutes: ['stockx', 'stock', 'reports', 'report', 'payables'].filter((k) => !ia.some((r) => r.id === k)) }; });
  ok(reg.dup === 0 && reg.unresolved.length === 0, 'registry: no duplicate id, every route resolves: ' + reg.unresolved);
  ok(reg.hasPages && reg.keys.length === 0 && reg.pages.length === 0, 'registry: all report keys and pages have a record: ' + reg.keys + ' ' + reg.pages);
  ok(/^stock\|true\|reports$/.test(reg.ledger) && /^stock\|false\|reports,appr$/.test(reg.recon) && /^stock\|true\|reports$/.test(reg.batches), 'ledger / batches in the drawer, recon also under approvals: ' + reg.ledger + ' ' + reg.recon + ' ' + reg.batches);
  ok(/^stock\|false\|reports$/.test(reg.sb) && /^stock\|false\|reports,appr$/.test(reg.integ) && /^purch\|false\|reports$/.test(reg.p4) && /^purch\|false\|reports$/.test(reg.ageing) && /^stock\|false\|reports,sale$/.test(reg.slow), 'report records: stock / purch groups with also: ' + [reg.sb, reg.integ, reg.p4, reg.ageing, reg.slow]);
  ok(reg.oldRoutes.length === 0, 'old routes kept: ' + reg.oldRoutes);
  await p.context().close();

  // ---- 2. movement ledger
  p = await open(`#/stockrep/ledger?item=${ITEM}&loc=1&from=2026-10-01&to=2026-10-17`, { o: { export: true } });
  t = await text(p);
  ok(/Movement ledger/.test(t) && /test_fg_sweet/.test(t), 'ledger: tabs and item header');
  ok((await p.locator('#stk_open').textContent()) === '0' && (await p.locator('#stk_close').textContent()) === '7.7', 'ledger: opening 0, closing 7.7');
  ok(await p.locator('#stk_check.ok').count() === 1 && /Cached balance equals the ledger/.test(t), 'ledger: the check against the cached balance is green');
  ok(await p.locator('.rp-t').first().locator('tbody tr').count() === 3, 'ledger: 3 rows with running balance');
  ok(/20/.test(await p.locator('.rp-t').first().locator('tbody tr').nth(0).innerText()) && /7\.7/.test(await p.locator('.rp-t').first().locator('tbody tr').nth(2).innerText()), 'ledger: running balance 20 then 7.7');
  ok(/not captured/.test(await p.locator('.rp-t').first().locator('tbody tr').nth(2).innerText()), 'ledger: a row without a cost says not captured, not 0');
  const lc = await calls(p, 'stock_movement_ledger'); ok(lc.length === 1 && lc[0].p_item === ITEM && lc[0].p_loc === 1 && lc[0].p_from === '2026-10-01', 'ledger: one call with the item, place and dates');
  await noOverflow(p, 'ledger');
  await click(p, '.rp-t tbody tr:nth-child(2)');
  ok(/Sale #990001/.test(await text(p)) && await p.locator('.sheet').count() === 1, 'ledger: a row opens its source document');
  await click(p, '[data-act=closesheet]');
  const dl = p.waitForEvent('download'); await p.click('[data-act=rk_csv][data-key=stock_ledger]'); const d = await dl; const csv = fs.readFileSync(await d.path(), 'utf8');
  ok(csv.charCodeAt(0) === 0xfeff && /Running balance/.test(csv) && csv.split('\n').length === 4 && /not captured/.test(csv), 'ledger: CSV with header, 3 rows, not captured cell');
  await wait(p, 300); ok((await calls(p, 'log_report_export4')).length === 1 && (await calls(p, 'log_report_export4'))[0].p_key === 'stock_ledger', 'ledger: the export is logged');
  await p.context().close();
  p = await open(`#/stockrep/ledger?item=${ITEM}&loc=1`);
  ok(await p.evaluate(() => /disabled/.test(window.BOS.repkit.csvBtn(false, 'stock_ledger')) && !/rk_csv/.test(window.BOS.repkit.csvBtn(false, 'stock_ledger')) && /rk_csv/.test(window.BOS.repkit.csvBtn(true, 'stock_ledger'))), 'ledger: without the export right the CSV button is locked');
  await p.context().close();

  // ---- 3. reconciliation
  p = await open('#/stockrep/recon');
  t = await text(p);
  ok(await p.locator('#stk_ident.ok').count() === 1 && /Opening \+ movements = closing on every row/.test(t), 'recon: identity notice green');
  ok(await p.locator('.rp-t').first().locator('tbody tr').count() === 2 && /cache_differs/.test(t), 'recon: two rows, one with a cache difference');
  ok(/Transfers on the road/.test(t) && /Transfers received short/.test(t) && /Test outlet 4/.test(t) && /open/.test(t), 'recon: transit and short lists');
  ok(/not captured/.test(await p.locator('.hsec:has-text("short") + .scrollx').innerText()), 'recon: a short transfer without a cost shows not captured');
  const rc = await calls(p, 'stock_recon_period'); ok(rc.length === 1 && /^\d{4}-\d\d-\d\d$/.test(rc[0].p_from) && rc[0].p_loc === null, 'recon: one call, dates, all places');
  await noOverflow(p, 'recon');
  await click(p, '.rp-t tbody tr:nth-child(1)');
  ok(/#\/stockrep\/ledger\?item=/.test(await p.evaluate(() => location.hash)), 'recon: a row opens the ledger of that item and place');
  await p.context().close();

  // ---- 4. batch pages: each tab renders, notices name the field, not captured cells, rows drill to the trace, CSV
  for (const [tab, key, needle] of [['batches', 'batch_stock', 'no expiry'], ['ageing', 'fg_ageing', 'report_aging_buckets'], ['unsold', 'unsold_by_batch', '34.7'], ['distribution', 'fg_distribution', 'no_batch'], ['expired', 'expired_damaged_unsold', 'damaged']]) {
    p = await open('#/batchrep/' + tab, { o: { export: true } }); t = await text(p);
    ok(new RegExp(needle).test(t), 'batchrep ' + tab + ': content (' + needle + ')');
    ok(await p.locator('.rp-t tbody tr').count() >= 1 && await p.locator(`[data-act=rk_csv][data-key=${key}]`).count() === 1, 'batchrep ' + tab + ': rows and a CSV button');
    await noOverflow(p, 'batchrep ' + tab);
    if (tab === 'batches') {
      ok(/not captured/.test(await p.locator('.rp-t tbody tr').nth(1).innerText()) && /unbatched/.test(await p.locator('.rp-t tbody tr').nth(2).innerText()), 'batches: the no-expiry batch and the unbatched line say not captured / unbatched');
      ok(/shelf_life_rules/.test(t), 'batches: the notice names the field');
    }
    if (tab === 'ageing') ok(/Age by item/.test(t) && /1\.5/.test(t), 'ageing: the per-item section');
    if (tab === 'expired') ok(/By class/.test(t), 'expired: the section by class');
    if (tab !== 'batches') { await click(p, '.rp-t tbody tr:nth-child(1)'); ok(/#\/(batchrep\/trace|stockrep\/ledger)/.test(await p.evaluate(() => location.hash)), 'batchrep ' + tab + ': a row drills to the trace or ledger'); }
    const dl2 = p.waitForEvent('download').catch(() => null); if (tab === 'batches') { await p.click(`[data-act=rk_csv][data-key=${key}]`); const dd = await dl2; ok(dd && fs.readFileSync(await dd.path(), 'utf8').charCodeAt(0) === 0xfeff, 'batches: CSV downloads'); }
    await p.context().close();
  }
  p = await open('#/batchrep/trace?batch=5'); t = await text(p);
  ok(await p.locator('#bch_acc .stat').count() === 8 && /Not accounted/.test(t) && /29\.7/.test(t), 'trace: the account of the batch (8 figures, 29.7 in stock)');
  ok(/Batch family/.test(t) && /Source rows/.test(t) && /Production run 2026-10-15/.test(t), 'trace: family and source rows');
  ok(/not captured/.test(t), 'trace: a batch with no expiry says not captured');
  await noOverflow(p, 'trace'); await p.context().close();

  // ---- 5. the report viewer: sub-totals, not captured cells, row drill, item-type filter
  p = await open('#/report/stock_balance'); t = await text(p);
  ok(/Totals by place/.test(t) && /Test store/.test(t), 'viewer: sub-totals section');
  ok((t.match(/not captured/g) || []).length >= 4, 'viewer: uncosted cells say not captured');
  ok(/2 stock line\(s\) with a quantity have no cost recorded/.test(t), 'viewer: the notice with the count');
  await noOverflow(p, 'viewer');
  await click(p, '.rp-t tbody tr:nth-child(1)');
  ok(/#\/stockrep\/ledger\?item=/.test(await p.evaluate(() => location.hash)), 'viewer: a row drills to the item ledger');
  await p.goBack(); await wait(p, 800);
  await click(p, '[data-act=rp_filter]');
  ok(/Item type/.test(await text(p)) && await p.locator('[data-k=item_types]').count() === 3, 'viewer: the item-type filter offers the three types');
  await click(p, '[data-k=item_types][data-v=raw_material]'); await click(p, '[data-act=fl_apply]');
  const rr = await calls(p, 'report_run2'); ok(rr.length >= 2 && (rr[rr.length - 1].p_filters.item_types || []).join() === 'raw_material', 'viewer: the chosen item type is sent to the server');
  await p.context().close();

  // ---- 6. stock screen (stockx): wastage without a sum across units, CSV
  p = await open('#/stockx', { o: { export: true } });
  await click(p, '[data-act=sx_tab][data-v=wa]'); t = await text(p);
  ok(/1\.5 kg \+ 1 pc/.test(t) && /Different units: not added up/.test(t) && /0\.5 kg/.test(t), 'stockx: mixed units are listed per unit, not summed');
  ok((await calls(p, 'wastage_by_reason2')).length >= 1 && await p.locator('[data-act=rk_csv][data-key=stockx_wastage]').count() === 1, 'stockx: new function and CSV button');
  await noOverflow(p, 'stockx'); await p.context().close();

  // ---- 7. Bangla and mix modes at 360px
  for (const lang of ['bn', 'mix']) {
    p = await open('#/batchrep/batches', { lang }); ok(await p.locator('.rp-t').count() >= 1, lang + ': batch page renders'); await noOverflow(p, 'batchrep ' + lang); await p.context().close();
    p = await open(`#/stockrep/ledger?item=${ITEM}&loc=1`, { lang }); ok(await p.locator('.rp-t').count() >= 1, lang + ': ledger renders'); await noOverflow(p, 'ledger ' + lang); await p.context().close();
  }
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
