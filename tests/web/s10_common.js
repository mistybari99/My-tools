// Shared mock for stock2_test.js / purchase_test.js: in-page RPC stand-ins for the phase10 API (the Supabase stub returns null for unknown RPCs).
const fs = require('fs'), path = require('path'), http = require('http');
const ROOT = require('path').join(__dirname, '..', '..', 'web');      // this checkout's web/ folder (was a fixed path to the main checkout)
function baseData(SP) {
  const src = fs.readFileSync(SP + '/smoke.js', 'utf8');
  return new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
}
const R = (key, kind, def, extra = {}) => ({ key, module: 'x', kind, value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1, ...extra });
function mkData(base, o = {}) {
  const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
  T.rules = [R('ui_noperm_mode', 'choice', o.hide ? 'hide' : 'lock'), R('wastage_photo_above', 'number', null, o.photoAbove ? { value: o.photoAbove } : {}), R('em_enabled', 'switch', true), R('em_issue_x', 'switch', false), R('barcode_camera_on', 'switch', false), R('barcode_device_on', 'switch', false, o.dev ? { value: true } : {}), ...(o.rules || [])];
  T.option_lists = [
    ...[['kg', 'কেজি', 'kg'], ['piece', 'পিস', 'piece'], ['box', 'বক্স', 'box'], ['gram', 'গ্রাম', 'gram']].map((u, i) => ({ list_code: 'units', value_code: u[0], label_bn: u[1], label_en: u[2], sort: i + 1, active: true })),
    ...[['expired', 'মেয়াদ শেষ', 'Expired'], ['spoiled', 'নষ্ট', 'Spoiled'], ['unknown', 'কারণ অজানা', 'Unknown reason']].map((u, i) => ({ list_code: 'wastage_reasons', value_code: u[0], label_bn: u[1], label_en: u[2], sort: i + 1, active: true })),
    ...[['damaged', 'ক্ষতিগ্রস্ত', 'Damaged'], ['wrong_item', 'ভুল মাল', 'Wrong item']].map((u, i) => ({ list_code: 'return_reasons', value_code: u[0], label_bn: u[1], label_en: u[2], sort: i + 1, active: true })),
    ...[['sweet_kg', 'মিষ্টি (কেজি)', 'Sweets (kg)'], ['sweet_pc', 'মিষ্টি (পিস)', 'Sweets (piece)']].map((u, i) => ({ list_code: 'item_categories', value_code: u[0], label_bn: u[1], label_en: u[2], sort: i + 1, active: true }))];
  T.unit_conversions = [{ id: 1, item_id: null, from_unit: 'kg', to_unit: 'gram', factor: 1000, active: true }, { id: 2, item_id: T.items[0].id, from_unit: 'box', to_unit: 'kg', factor: 2, active: true }, { id: 3, item_id: T.items[2].id, from_unit: 'box', to_unit: 'piece', factor: 12, active: true }];
  const it = T.items; Object.assign(it[0], { tracked: true, base_unit: 'kg', min_stock: 5 }); Object.assign(it[1], { tracked: true, base_unit: 'kg' }); Object.assign(it[2], { tracked: true, base_unit: 'piece', unit: 'pc' });
  if (o.sales) T.sales = o.sales;
  (o.itemPatch || []).forEach((pt, i) => Object.assign(it[i], pt));
  T.suppliers = [{ id: 'sp1', name: 'Dudh Ghor', type_code: 'milk', active: true }, { id: 'sp2', name: 'Chini Mill', type_code: 'sugar', active: true }];
  T.grant_defs = [{ grant_code: 'stock_issue', emergency_rule: 'em_issue_x', sort: 1, label_bn: 'issue', label_en: 'Issue' }];
  return data;
}
const PNG = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
// everything runs in the page; tests read/modify window.__M
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; window.__UP = [];
 const M = window.__M = Object.assign({ calls: [], fail: {}, noCost: false, grants: null, ctx: null,
  levels: [
   { item_id: 'i0', code: 'I-001', name_bn: 'সাদা মিষ্টি', name_en: 'White sweet', category: 'sweet_kg', base_unit: 'kg', location_id: 1, qty: 3.5, min_stock: 5, below_min: true, avg_cost: 210, value: 735 },
   { item_id: 'i1', code: 'I-002', name_bn: 'কালো মিষ্টি', name_en: 'Black sweet', category: 'sweet_kg', base_unit: 'kg', location_id: 1, qty: 0, min_stock: null, below_min: false, avg_cost: 200, value: 0 },
   { item_id: 'i2', code: 'I-003', name_bn: 'রসমালাই', name_en: 'Rasmalai', category: 'sweet_pc', base_unit: 'piece', location_id: 1, qty: 40, min_stock: 10, below_min: false, avg_cost: 18, value: 720 }],
  ledger: [{ id: 3, item_id: 'i0', location_id: 1, qty_delta: -1.5, unit_cost: 210, reason: 'sale_out', made_at: '2026-10-10T09:00:00Z', note: null }, { id: 2, item_id: 'i0', location_id: 1, qty_delta: 5, unit_cost: 210, reason: 'opening', made_at: '2026-10-09T09:00:00Z', note: 'start' }],
  exp: [{ batch_id: 11, item_id: 'i0', code: 'I-001', name_bn: 'সাদা মিষ্টি', name_en: 'White sweet', location_id: 1, made_at: '2026-10-10T02:00:00Z', expires_at: '2026-10-11T20:00:00Z', qty_remaining: 2, hours_left: 5.5, expired: false },
        { batch_id: 12, item_id: 'i2', code: 'I-003', name_bn: 'রসমালাই', name_en: 'Rasmalai', location_id: 1, made_at: '2026-10-09T02:00:00Z', expires_at: '2026-10-10T20:00:00Z', qty_remaining: 12, hours_left: -3, expired: true }],
  tr: [{ id: 't1', item_id: 'i0', code: 'I-001', name_bn: 'সাদা মিষ্টি', name_en: 'White sweet', from_location_id: 2, to_location_id: 1, qty: 10, sent_at: '2026-10-10T08:00:00Z', sent_staff: 'karim02', note: 'van' },
        { id: 't2', item_id: 'i2', code: 'I-003', name_bn: 'রসমালাই', name_en: 'Rasmalai', from_location_id: 1, to_location_id: 2, qty: 20, sent_at: '2026-10-10T08:30:00Z', sent_staff: 'owner1', note: null }],
  recon: [],
  list: [
   { id: 'b1', kind: 'bill', supplier_id: 'sp1', supplier_name: 'Dudh Ghor', bill_no: 'D-101', bill_date: '2026-10-08', location_id: 1, status: 'posted', total: 1000, discount: 0, paid: 400, due: 600, photo: null, created_staff: 'owner1', n_lines: 2 },
   { id: 'b2', kind: 'bill', supplier_id: 'sp2', supplier_name: 'Chini Mill', bill_no: 'C-9', bill_date: '2026-10-09', location_id: 1, status: 'draft', total: 500, discount: 0, paid: 0, due: 500, photo: null, created_staff: 'owner1', n_lines: 1 },
   { id: 'b3', kind: 'bill', supplier_id: 'sp1', supplier_name: 'Dudh Ghor', bill_no: 'D-100', bill_date: '2026-10-01', location_id: 1, status: 'void', total: 300, discount: 0, paid: 0, due: 300, photo: null, created_staff: 'owner1', n_lines: 1 },
   { id: 'b4', kind: 'return', supplier_id: 'sp1', supplier_name: 'Dudh Ghor', bill_no: 'R-1', bill_date: '2026-10-09', location_id: 1, status: 'posted', total: 100, discount: 0, paid: 0, due: 100, photo: null, created_staff: 'owner1', n_lines: 1 }],
  dues: [{ supplier_id: 'sp1', name: 'Dudh Ghor', mobile: '01711111111', type_code: 'milk', credit_days: 7, balance: 600, oldest: '2026-09-20', overdue: 600 }, { supplier_id: 'sp2', name: 'Chini Mill', mobile: '01822222222', type_code: 'sugar', credit_days: null, balance: 500, oldest: '2026-10-09', overdue: 0 }],
  summary: { total_payable: 1100, suppliers_owed: 2, overdue: 600, overdue_suppliers: 1, oldest: '2026-09-20', credit_total: 0 },
  sled: [{ at: '2026-10-08T00:00:00Z', kind: 'bill', ref: 'D-101', location_id: 1, debit: 1000, credit: 0, balance: 1000, note: null, pid: null, bill_id: 'b1' }, { at: '2026-10-09T05:00:00Z', kind: 'payment', ref: 'cash', location_id: 1, debit: 0, credit: 400, balance: 600, note: null, pid: 7, bill_id: null }],
  openBills: [{ bill_id: 'b1', bill_no: 'D-101', bill_date: '2026-10-08', location_id: 1, bill_due: 600, open_amt: 600 }]
 }, window.__M0 || {});
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const noCost = (r) => M.noCost ? r.map((x) => Object.assign({}, x, { avg_cost: null, value: null, unit_cost: null })) : r;
 c.rpc = async (fn, args) => { M.calls.push([fn, clone(args || {})]);
  const f = M.fail[fn]; if (f) { if (f.once) delete M.fail[fn]; return { data: null, error: { message: f.msg, hint: f.hint } }; }
  if (fn === 'supplier_pick') return { data: T.suppliers.map((s) => ({ id: s.id, name: s.name, type_code: s.type_code })), error: null };
  if (fn === 'has_grant') return { data: M.grants === null ? true : M.grants.includes(args.p_code), error: null };
  if (fn === 'my_context') { const r = await rpc(fn, args); if (M.ctx && r.data) Object.assign(r.data, M.ctx); return r; }
  if (fn === 'stock_levels') { const f2 = args.p_filters || {}; let r = M.levels.filter((x) => (!f2.item_ids || f2.item_ids.includes(x.item_id)) && (args.p_loc === null || args.p_loc === undefined || x.location_id === args.p_loc) && (!f2.category || x.category === f2.category) && (!f2.below_min || x.below_min) && (f2.include_zero || args.p_loc || Number(x.qty) !== 0)); return { data: noCost(clone(r)), error: null }; }
  if (fn === 'stock_ledger_rows') return { data: noCost(clone(M.ledger)), error: null };
  if (fn === 'expiry_list') return { data: clone(M.exp), error: null };
  if (fn === 'stock_in_transit') return { data: clone(M.tr), error: null };
  if (fn === 'stock_wastage' && M.pendingWaste) return { data: { pending: true, request_id: 'w9', qty: args.p_qty }, error: null };
  if (fn === 'items_with_cost') return { data: clone(M.costRows || []), error: null };
  if (fn === 'wastage_pending') return { data: clone(M.wa || []), error: null };
  if (fn === 'wastage_decide') return { data: { status: args.p_approve ? 'approved' : 'rejected' }, error: null };
  if (fn === 'wastage_cancel') return { data: { status: 'cancelled' }, error: null };
  if (fn === 'supplier_credits') return { data: clone(M.credits || []), error: null };
  if (fn === 'supplier_refund') return { data: { refunded: args.p_amount, balance: -100 }, error: null };
  if (fn === 'void_supplier_refund') return { data: null, error: null };
  if (fn === 'sale_returns_for') return { data: clone(M.saleRet), error: null };
  if (fn === 'sale_return') return { data: { id: 'r1', amount: 520, credit: 500, refund: 20 }, error: null };
  if (fn === 'void_sale_return') return { data: { status: 'void' }, error: null };
  if (fn === 'stock_opening' || fn === 'stock_wastage' || fn === 'stock_issue' || fn === 'stock_production_in' || fn === 'stock_transfer' || fn === 'stock_expire_batch' || fn === 'stock_receive_transfer' || fn === 'stock_cancel_transfer') return { data: { ledger_id: 99, id: 'x', qty: 1 }, error: null };
  if (fn === 'stock_count_adjust') return { data: { ledger_id: 98, delta: -1.5, qty: 2 }, error: null };
  if (fn === 'stock_reconcile') return { data: clone(M.recon), error: null };
  if (fn === 'purchase_list') { let r = M.list.filter((x) => (!args.p_supplier || x.supplier_id === args.p_supplier) && (!args.p_status || x.status === args.p_status) && (!args.p_from || x.bill_date >= args.p_from) && (!args.p_to || x.bill_date <= args.p_to)); return { data: clone(r), error: null }; }
  if (fn === 'purchase_get') { const l = M.list.find((x) => x.id === args.p_id) || M.list[0]; const d = M.detail && M.detail[args.p_id]; return { data: Object.assign({}, l, { subtotal: l.total + l.discount, note: null, void_note: null, reason_code: null, ref_bill_id: null, lines: [{ line_no: 1, item_id: 'i0', description: null, qty: 4, unit: 'kg', unit_cost: 250, amount: 1000 }, { line_no: 2, item_id: null, description: 'Gas cylinder', qty: 1, unit: null, unit_cost: 0, amount: 0 }], payments: [{ id: 5, mode: 'cash', wallet: null, ref: null, amount: 400, paid_at: '2026-10-08T05:00:00Z', voided: false }] }, d || {}), error: null }; }
  if (fn === 'save_purchase') return { data: { id: 'b9', status: 'draft', total: 525, lines: 2 }, error: null };
  if (fn === 'post_purchase') return { data: { id: args.p_id, status: 'posted', total: 525 }, error: null };
  if (fn === 'void_purchase') return { data: { id: args.p_id, status: 'void' }, error: null };
  if (fn === 'supplier_dues') return { data: clone(M.dues), error: null };
  if (fn === 'payables_summary') return { data: [clone(M.summary)], error: null };
  if (fn === 'supplier_ledger') return { data: clone(M.sled), error: null };
  if (fn === 'supplier_open_bills') return { data: clone(M.openBills), error: null };
  if (fn === 'pay_supplier') return { data: { paid: 100, balance: 500 }, error: null };
  if (fn === 'void_supplier_payment') return { data: null, error: null };
  return rpc(fn, args); };
 c.storage = { from: () => ({ upload: async (p, b) => { if (M.upFail && p.indexOf(M.upFail) === 0) return { error: { message: 'new row violates row-level security policy' } }; window.__UP.push([p, b.size, b.type]); return { error: null }; },
   createSignedUrls: async (ps) => ({ data: ps.map((p) => ({ path: p, signedUrl: '${PNG}' })), error: null }), createSignedUrl: async () => ({ data: { signedUrl: '${PNG}' }, error: null }) }) };
 return c; }; })();`;
function serve(port) {
  return http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(port);
}
// a tiny 100x100 jpeg-able png for photo uploads
const PNGBUF = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
module.exports = { baseData, mkData, EXTRA, serve, PNGBUF };
