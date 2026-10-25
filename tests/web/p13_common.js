// Shared mock for daybook_test.js / salary_test.js (phase13 RPCs). Layered on top of s10_common's EXTRA (has_grant, my_context ...).
const C = require('./s10_common.js');
const EXTRA2 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const ln = (loc, dir, mode, type, amount, ref, text, extra) => Object.assign({ loc, dir, mode, type, amount, ref, text, who: 'st', at: '2026-10-05T04:00:00Z', src: 'sale', src_id: 's1', internal: false, sensitive: false }, extra || {});
 const Z = (c, b, m) => ({ cash: c, bank: b, mobile: m, total: c + b + m });
 M.db = Object.assign({ start: null, hidden: false, off: false, denied: false, exportDenied: false, rows: null, saved: [] }, window.__DB0 || {});
 const days = () => { const s = M.db.start;
  const d1 = { date: '2026-10-05', in: Z(300, 0, 200), out: Z(135, 0, 0), lines: [ ln(1, 'in', 'cash', 'sale', 300, '#901', 'TestK'), ln(1, 'in', 'mobile', 'sale', 200, '#901', 'bkash'), ln(1, 'out', 'cash', 'bill', 100, 'D-101', 'Dudh Ghor', { src: 'bill', src_id: 'b1' }), ln(1, 'out', 'cash', 'expense', 35, '#9001', '2 line(s)', { src: 'entry', src_id: 'e9001' }) ] };
  const d2 = { date: '2026-10-06', in: Z(40, 150, 0), out: Z(2020, 60, 0), lines: [ ln(1, 'in', 'cash', 'sale', 40, '#902', null), ln(1, 'in', 'bank', 'collection', 150, null, 'TestF', { src: 'customer', src_id: 'c1' }), ln(1, 'out', 'bank', 'supplier', 60, null, 'Dudh Ghor', { src: 'supplier', src_id: 'su1' }), ln(1, 'out', 'cash', 'handover', 2020, '#9003', 'TestF', { src: 'entry', src_id: 'e9003', internal: window.__DB_INTERNAL === true }) ] };
  d1.transfers = 0; d2.transfers = 2020;
  if (s) { d1.net_open = Z(0, 0, 0); d1.net_close = Z(165, 0, 200); d2.net_open = Z(165, 0, 200); d2.net_close = Z(-1815, 90, 200); if (M.db.balances) { d1.open = Z(1000, 0, 0); d1.close = Z(1165, 0, 200); d2.open = Z(1165, 0, 200); d2.close = Z(-815, 90, 200); } }
  return [d1, d2]; };
 const sal = () => ({ month: '2026-10-01', loc: 1, sheets: 1, data_needed: false, drafts_excluded: true, duplicate_sheets: M.db.dup ? [{ loc: 1, n: 2 }] : [],
  rows: [ { entry_id: 'e5', serial: 9005, loc: 1, status: 'approved', name: 'TestK cook', salary: 10000, work_days: 26, absent: 3, leave: 0, due: 10000, overtime: 500, other: 0, gross: 10500, adv_ded: 1000, other_ded: 0, deductions: 1000, net: 9500, remark: null, paid: 9500, signed: true },
          { entry_id: 'e5', serial: 9005, loc: 1, status: 'approved', name: 'TestF', salary: 8000, work_days: null, absent: null, leave: null, due: 8000, overtime: 0, other: 100, gross: 8100, adv_ded: 0, other_ded: 50, deductions: 50, net: 8050, remark: 'x', paid: null, signed: null, ambiguous: !!M.db.dup } ],
  totals: { people: 2, due: 18000, overtime: 500, other: 100, gross: 18600, adv_ded: 1000, other_ded: 50, deductions: 1050, net: 17550 },
  advances: [ { entry_id: 'e4', serial: 9004, loc: 1, status: 'approved', staff: 'owner1', name: 'TestK cook', post: 'cook', given: 1300, deducted: 200, outstanding: 1100 } ],
  attendance: [ { entry_id: 'e8', serial: 9008, loc: 1, name: 'TestK cook', present: 26, late: 2, absent: 3, leave_unpaid: null, leave_paid: null, ot_hours: 10 } ] });
 c.rpc = async (fn, args) => {
  if (fn === 'day_book') { M.calls.push([fn, clone(args || {})]); if (M.db.denied) return { data: null, error: { message: 'not allowed' } }; if (M.db.off) return { data: null, error: { message: 'daybook_off' } };
    if (M.db.missing) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.day_book' } };
    const d = days(); return { data: { from: args.p_from, to: args.p_to, loc: args.p_loc, start: M.db.start, opening_known: !!M.db.start && !M.db.startAfter, balances: !!M.db.balances, skipped_rows: M.db.skipped || 0, names_masked: !!M.db.masked, capped: !!M.db.capped, enabled: !M.db.off, salary_hidden: M.db.hidden, days: d,
      totals: { in: Z(340, 150, 200), out: Z(2155, 60, 0), transfers: 2020, net_open: M.db.start ? Z(0, 0, 0) : null, net_close: M.db.start ? Z(-1815, 90, 200) : null, open: M.db.balances ? Z(1000, 0, 0) : null, close: M.db.balances ? Z(-815, 90, 200) : null }, notes: ['card_as_bank', 'imprest_in_cash', 'bank_deposit_not_dated', 'hub_receipt_not_recorded', 'drafts_excluded', 'refunds_included', 'future_dates_capped'] }, error: null }; }
  if (fn === 'salary_report') { M.calls.push([fn, clone(args || {})]); if (M.db.denied) return { data: null, error: { message: 'not allowed' } }; const r = sal(); if (M.db.empty) { r.rows = []; r.sheets = 0; r.data_needed = true; r.totals = {}; } return { data: r, error: null }; }
  if (fn === 'report_catalog') return { data: [], error: null };
  if (fn === 'set_daybook_opening') { M.calls.push([fn, clone(args || {})]); return { data: null, error: null }; }
  if (fn === 'set_daybook_start') { M.calls.push([fn, clone(args || {})]); return { data: null, error: null }; }
  if (fn === 'set_rule') { M.calls.push([fn, clone(args || {})]); return { data: null, error: null }; }
  if (fn === 'log_page_export') { M.calls.push([fn, clone(args || {})]); if (M.db.exportDenied) return { data: null, error: { message: 'not allowed' } }; return { data: null, error: null }; }
  return rpc(fn, args); };
 return c; }; })();`;
module.exports = Object.assign({}, C, { EXTRA2 });
