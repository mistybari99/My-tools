// Shared mock for rollout_test.js / outbox_test.js (phase17 RPCs). Layered on s10_common (has_grant via M.grants, my_context via M.ctx).
//   window.__M.w5 : { net:false (every phase17 rpc fails like a lost network), err:{fn:'message'}, rev: [...] ...}
const C = require('./s10_common.js');
const LOCS = [
  { id: 1, code: 'main', name_bn: 'ইসলামিয়া মেইন', name_mix: 'ইসলামিয়া Main', name_en: 'Islamia Main', sort: 1, is_active: true, status: 'live' },
  { id: 2, code: 'branch2', name_bn: '২য় শাখা', name_mix: '২য় Branch', name_en: '2nd Branch', sort: 2, is_active: true, status: 'live' },
  { id: 3, code: 'godown', name_bn: 'গোডাউন', name_mix: 'Godown', name_en: 'Godown', sort: 3, is_active: true, status: 'live' },
  { id: 9, code: 'old_closed', name_bn: 'বন্ধ', name_mix: 'Closed', name_en: 'Old Closed', sort: 9, is_active: false, status: 'closed' }];
function mk(base, o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.locations = JSON.parse(JSON.stringify(LOCS));
  T.rules = (T.rules || []).concat([
    { key: 'rollout_enforce', module: 'entries', kind: 'switch', value: null, default_value: true, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 },
    { key: 'entered_later_on', module: 'entries', kind: 'switch', value: o.laterOff ? false : null, default_value: true, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 2 },
    { key: 'change_requests_on', module: 'entries', kind: 'switch', value: null, default_value: true, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 3 },
    { key: 'owner_self_approve', module: 'lists', kind: 'switch', value: o.selfOff ? false : null, default_value: true, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 4 }]);
  T.form_rollout = []; T.forms.filter((f) => /^\d+-\d+$/.test(f.code)).forEach((f) => LOCS.forEach((l) => T.form_rollout.push({ form_code: f.code, location_id: l.id, mode: 'app', note: null, changed_at: '2026-10-01T00:00:00Z' })));
  (o.cells || []).forEach(([f, l, m]) => { const r = T.form_rollout.find((x) => x.form_code === f && x.location_id === l); if (r) r.mode = m; });
  T.entry_change_requests = o.reqs || []; T.entries = o.entries || [];
  return data;
}
const EXTRA5 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.w5 = Object.assign({ net: false, err: {}, seen: {}, revs: [], counts: { pending: 0 } }, window.__W0 || {});
 const NETERR = { message: 'TypeError: Failed to fetch', details: '', hint: '', code: '' };
 c.rpc = async (fn, args) => {
  if (!/^(save_entry|submit_entry|rollout_|set_rule|owner_self_approve_set|entry_change|entry_revisions_list|number_audit_both)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.net) return { data: null, error: NETERR };
  if (W.err[fn]) { const m = W.err[fn]; if (!W.keep) delete W.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  const E = T.entries;
  if (fn === 'save_entry') {
    const meta = args.p_meta || null;
    if (!args.p_id && meta && meta.client_id && W.seen[meta.client_id]) { const e0 = E.find((x) => x.id === W.seen[meta.client_id]); return { data: { id: e0.id, serial: e0.serial, duplicate: true }, error: null }; }
    let e = args.p_id && E.find((x) => x.id === args.p_id);
    const later = meta && 'entered_later' in meta ? !!meta.entered_later : (e ? e.entered_later : false);
    if (later && meta && !String(meta.paper_serial || '').trim()) return { data: null, error: { message: 'paper_serial_required', code: 'P0001' } };
    if (!e) { const n = E.length + 1; e = { id: 'e' + n, serial: n, form_code: args.p_form, location_id: args.p_loc, status: 'draft', created_by: 'u1', created_staff: 'owner1', check_data: {}, rev_no: 1, client_id: meta && meta.client_id || null }; E.push(e); if (e.client_id) W.seen[e.client_id] = e.id; }
    Object.assign(e, { data: args.p_data, flags: args.p_flags, entry_date: args.p_date, entered_later: later, paper_serial: later ? ((meta && meta.paper_serial) || e.paper_serial) : null, paper_at: later ? ((meta && meta.paper_at) || e.paper_at) : null });
    if (W.lose) { W.lose = false; return { data: null, error: NETERR }; }      // saved on the server but the answer was lost
    return { data: { id: e.id, serial: e.serial }, error: null };
  }
  if (fn === 'submit_entry') { const e = E.find((x) => x.id === args.p_id); if (!e) return { data: null, error: { message: 'entry not found', code: 'P0001' } }; if (e.status !== 'draft') return { data: null, error: { message: 'entry is locked', code: 'P0001' } }; e.status = 'submitted'; return { data: { status: 'submitted' }, error: null }; }
  if (fn === 'rollout_set') { const r = T.form_rollout.find((x) => x.form_code === args.p_form && x.location_id === args.p_loc); r.mode = args.p_mode; r.note = args.p_note; return { data: { to: args.p_mode }, error: null }; }
  if (fn === 'rollout_set_many') { let n = 0; T.form_rollout.forEach((r) => { if ((!args.p_forms || args.p_forms.includes(r.form_code)) && (!args.p_locs || args.p_locs.includes(r.location_id))) { r.mode = args.p_mode; r.note = args.p_note; n++; } }); return { data: n, error: null }; }
  if (fn === 'owner_self_approve_set') { const r = T.rules.find((x) => x.key === 'owner_self_approve'); r.value = args.p_on; return { data: { owner_self_approve: args.p_on }, error: null }; }
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'entry_change_request') { const e = E.find((x) => x.id === args.p_entry); if (e.status !== 'approved') return { data: null, error: { message: 'not_locked', code: 'P0001' } }; const id = T.entry_change_requests.length + 1;
    T.entry_change_requests.push({ id, entry_id: e.id, base_rev: e.rev_no || 1, requested_by: 'u1', requested_staff: 'owner1', reason: args.p_reason, patch: args.p_patch, status: 'pending', created_at: '2026-10-11T10:00:00Z' }); return { data: { id, status: 'pending' }, error: null }; }
  if (fn === 'entry_change_decide') { const r = T.entry_change_requests.find((x) => x.id === args.p_id); r.status = args.p_approve ? 'approved' : 'rejected'; r.decision_note = args.p_note; if (args.p_approve) { const e = E.find((x) => x.id === r.entry_id); e.data = r.patch.data || e.data; e.rev_no = (e.rev_no || 1) + 1; } return { data: { status: r.status, rev_no: 2 }, error: null }; }
  if (fn === 'entry_change_cancel') { T.entry_change_requests.find((x) => x.id === args.p_id).status = 'cancelled'; return { data: null, error: null }; }
  if (fn === 'entry_revisions_list') return { data: clone(W.revs), error: null };
  if (fn === 'entry_change_counts') return { data: clone(W.counts), error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
module.exports = Object.assign({}, C, { mk, EXTRA5, LOCS });
