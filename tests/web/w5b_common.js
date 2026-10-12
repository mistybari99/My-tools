// Shared mock for blind_test.js / sign_test.js (phase18 RPCs). Layered on w5_common (save_entry / submit_entry mock) -> s10_common.
//   window.__W6S (kept across clients: s10 resets window.__M on every createClient) and window.__AC = every rpc [fn, args, 'main'|'second'] : { blind:true, pin:true, locked:false, counts:{entryId:row}, peeks:[], err:{fn:'message'}, second:[] }
const C = require('./w5_common.js');
function mk(base, o = {}) {
  const data = C.mk(base, o); const T = data.tables;
  T.entry_signatures = o.sigs || [];
  (o.entries || []).forEach((e) => T.entries.push(e));
  return data;
}
const EXTRA6 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = window.__W6S = window.__W6S || Object.assign({ blind: true, pin: true, locked: false, counts: {}, peeks: [], err: {}, second: [] }, window.__W6 || {});
 const second = !!(a[2] && a[2].auth && a[2].auth.persistSession === false); c.__second = second;
 const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
 const den = (o) => { if (!o) return 0; return [1000,500,200,100,50,20,10,5,2,1].reduce((s,d) => s + d * num(o['n'+d]), 0) + num(o.coin); };
 if (second) { const si = c.auth.signInWithPassword; c.auth.signInWithPassword = async (cred) => { W.second.push({ email: cred.email, pw: cred.password }); const r = await si(cred); if (!r.error) c.__email = cred.email; return r; }; }
 c.rpc = async (fn, args) => {
  (window.__AC = window.__AC || []).push([fn, clone(args || {}), second ? 'second' : 'main']);
  if (!/^(blind_active|pin_sig_active|count_save|count_get|count_peek|sign_entry|login_precheck)$/.test(fn)) return rpc(fn, args);
  if (fn === 'login_precheck') return { data: { locked: !!W.locked }, error: null };
  if (W.err[fn]) { const m = W.err[fn]; delete W.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  const E = T.entries;
  if (fn === 'blind_active') return { data: W.blind === 'missing' ? null : !!W.blind, error: W.blind === 'missing' ? { message: 'function does not exist' } : null };
  if (fn === 'pin_sig_active') return { data: W.pin === 'missing' ? null : !!W.pin, error: W.pin === 'missing' ? { message: 'function does not exist' } : null };
  const exp = (e, sec) => { const d = e.data || {}; if (sec === 'drawer') return num(d.open_counted) + num(d.total_entered) - (num(d.d_bkash) + num(d.d_nagad) + num(d.d_card) + num(d.d_bank) + num(d.d_other)) + num(d.dues) + num(d.new_adv) - num(d.prior_adv) - num(d.refund) - num(d.credit_sales) - num(d.midday_hub) + num(d.rounding); return den(d.count) - num(d.leave_float); };
  if (fn === 'count_get') { const r = W.counts[args.p_entry + ':' + args.p_section]; if (r && W.hide) return { data: { saved: true, counted: r.counted, hidden: true }, error: null }; return { data: r ? Object.assign({ saved: true }, r) : { saved: false, blind: true }, error: null }; }
  if (fn === 'count_peek') { const e = E.find((x) => x.id === args.p_entry); if (!e) return { data: null, error: { message: 'entry not found', code: 'P0001' } }; if (W.noPeek) return { data: null, error: { message: 'not allowed', code: 'P0001' } }; W.peeks.push(args.p_entry); return { data: { saved: false, expected: exp(e, args.p_section) }, error: null }; }
  if (fn === 'count_save') { const e = E.find((x) => x.id === args.p_entry); if (!e) return { data: null, error: { message: 'entry not found', code: 'P0001' } }; const k = args.p_entry + ':' + args.p_section;
    if (W.counts[k]) return { data: null, error: { message: 'count_already_saved', code: 'P0001' } };
    const counted = den(args.p_counted), ex = exp(e, args.p_section); W.counts[k] = { counted, expected: ex, diff: counted - ex, match: counted === ex, seen_before_count: W.peeks.includes(args.p_entry) };
    if (W.hide) return { data: { section: args.p_section, saved: true, counted, hidden: true }, error: null };
    return { data: { section: args.p_section, counted, expected: ex, diff: counted - ex, match: counted === ex }, error: null }; }
  if (fn === 'sign_entry') { if (!second) return { data: null, error: { message: 'signer must be the second login', code: 'P0001' } };
    const e = E.find((x) => x.id === args.p_entry); const staff = (c.__email || '').split('@')[0];
    if (!e) return { data: null, error: { message: 'entry not found', code: 'P0001' } };
    if (staff === e.created_staff) return { data: null, error: { message: 'signer_is_maker', code: 'P0001' } };
    if (T.entry_signatures.some((s) => s.entry_id === e.id && s.signer_staff === staff)) return { data: null, error: { message: 'signer_already_signed', code: 'P0001' } };
    if (T.entry_signatures.some((s) => s.entry_id === e.id && s.role === args.p_role)) return { data: null, error: { message: 'role_already_signed', code: 'P0001' } };
    T.entry_signatures.push({ entry_id: e.id, role: args.p_role, signer_staff: staff }); return { data: { entry: e.id, role: args.p_role, signer_staff: staff }, error: null }; }
  return { data: null, error: null }; };
 return c; }; })();`;
module.exports = Object.assign({}, C, { mk, EXTRA6 });
