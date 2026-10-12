// Shared mock for locations_test.js / control_test.js (phase16 RPCs). Layered on s10_common (has_grant via M.grants, my_context via M.ctx).
const C = require('./s10_common.js');
const LOCS = [
  { id: 1, code: 'main', name_bn: 'ইসলামিয়া মেইন', name_mix: 'ইসলামিয়া Main', name_en: 'Islamia Main', sort: 1, is_active: true, kind: 'showroom', model: 'A', status: 'live', hub_functions: true, supplied_by: null },
  { id: 2, code: 'branch2', name_bn: '২য় শাখা', name_mix: '২য় Branch', name_en: '2nd Branch', sort: 2, is_active: true, kind: 'showroom', model: 'A', status: 'live', hub_functions: false, supplied_by: 6 },
  { id: 5, code: 'mishti_factory', name_bn: 'মুজগুন্নি কারখানা', name_mix: 'Mujgunni Factory', name_en: 'Mujgunni Sweet Factory', sort: 6, is_active: true, kind: 'factory', model: 'A', status: 'paused', paused_reason: 'stopped', hub_functions: false },
  { id: 6, code: 'cake_factory', name_bn: 'কেক কারখানা', name_mix: 'Cake Factory', name_en: 'Cake Factory', sort: 5, is_active: true, kind: 'factory', model: 'A', status: 'live', hub_functions: false },
  { id: 7, code: 'godown', name_bn: 'গোডাউন', name_mix: 'Godown', name_en: 'Godown', sort: 7, is_active: true, kind: 'godown', model: 'A', status: 'live', hub_functions: false },
  { id: 8, code: 'new_one', name_bn: 'নতুন এক', name_mix: null, name_en: 'New One', sort: 8, is_active: true, kind: 'showroom', model: 'A', status: 'planned', hub_functions: false },
  { id: 9, code: 'old_closed', name_bn: 'বন্ধ পুরোনো', name_mix: null, name_en: 'Old Closed', sort: 9, is_active: false, kind: 'showroom', model: 'A', status: 'closed', closed_reason: 'finished', hub_functions: false }];
const TITLES = ['Decide', 'Code', 'Name under Other', 'Item list', 'Duty slots', 'Skill check', 'Hiring', 'One-person gap', 'Cash boxes', 'Settings sheet', 'Equipment', 'Print paper', 'Supply map', 'Training', 'Opening count', 'Start on the 1st', 'Weekly comparison'];
function steps(loc, doneUpTo) { return TITLES.map((t, i) => ({ location_id: loc, step_no: i + 1, title_bn: 'ধাপ ' + (i + 1), title: t, owner_role: i === 0 ? 'Owner' : 'Head management', owner_yes: [1, 5, 8, 10].includes(i + 1), optional: i + 1 === 13, done: i + 1 <= doneUpTo, note: null })); }
function mk(base, o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.locations = JSON.parse(JSON.stringify(LOCS));
  T.location_setup_steps = steps(8, 2);
  T.option_lists = (T.option_lists || []).concat([
    { list_code: 'location_models', value_code: 'A', label_bn: 'ক — নিজস্ব', label_en: 'A — Own place', label_mix: 'A — Own place', sort: 1, active: true },
    { list_code: 'location_models', value_code: 'B', label_bn: 'খ — ফ্র্যাঞ্চাইজ', label_en: 'B — Franchise', label_mix: 'B — Franchise', sort: 2, active: false }]);
  T.settings_values = [{ sheet_id: 11, key: 'drawer_float', value: 2000 }, { sheet_id: 11, key: 'imprest', value: null }, { sheet_id: 12, key: 'drawer_float', value: 2500 }];
  return data;
}
const EXTRA3 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.w4 = Object.assign({ cc: { tier: 'owner', item_requests: 2, exceptions: 1, releases: 0, emergency: 0, staff_pending: 1, wastage: 3, location_setup: 1, settings_drafts: 1, lists: 4 },
   warn: {}, sheets: [{ id: 11, location_id: 1, version: 1, status: 'approved', effective_from: '2000-01-01', source: 'seed', note: null, filled: 1, blank: 1, in_force: false }, { id: 12, location_id: 1, version: 2, status: 'approved', effective_from: '2026-10-01', source: 'legacy', note: 'x', filled: 1, blank: 0, in_force: true }],
   limits: { drawer_float: 2500 }, err: {} }, window.__W0 || {});
 c.rpc = async (fn, args) => {
  if (!/^(control_counts|location_|sheet_|get_limit|limit_missing)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn] } };
  const L = T.locations;
  if (fn === 'control_counts') return { data: clone(W.cc), error: null };
  if (fn === 'location_save') { const p = args.p_patch;
    if (args.p_id === null) { const id = Math.max(...L.map((x) => x.id)) + 1; const code = (p.name_en || 'loc').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
      L.push(Object.assign({ id, code, sort: id, is_active: true, status: 'planned', hub_functions: false }, p)); T.location_setup_steps.push(...window.__STEPS(id, 1)); return { data: { id, code, created: true }, error: null }; }
    Object.assign(L.find((x) => x.id === args.p_id), p); return { data: { id: args.p_id, created: false }, error: null }; }
  if (fn === 'location_set_status') { const l = L.find((x) => x.id === args.p_id); const w = W.warn[args.p_status];
    if (w && !args.p_override) return { data: { ok: false, warnings: w, status: l.status }, error: null };
    l.status = args.p_status; if (args.p_status === 'paused') l.paused_reason = args.p_reason; if (args.p_status === 'closed') { l.closed_reason = args.p_reason; l.is_active = false; } return { data: { ok: true, status: l.status }, error: null }; }
  if (fn === 'location_set_active') { L.find((x) => x.id === args.p_id).is_active = args.p_active; return { data: null, error: null }; }
  if (fn === 'location_steps_init') { return { data: 17, error: null }; }
  if (fn === 'location_step_set') { const s = T.location_setup_steps.find((x) => x.location_id === args.p_loc && x.step_no === args.p_step); s.done = args.p_done; return { data: { ok: true }, error: null }; }
  if (fn === 'sheet_list') return { data: clone(W.sheets.filter((s) => s.location_id === args.p_loc).sort((a, b) => b.version - a.version)), error: null };
  if (fn === 'sheet_draft') { let d = W.sheets.find((s) => s.location_id === args.p_loc && s.status === 'draft'); if (!d) { d = { id: 20, location_id: args.p_loc, version: 3, status: 'draft', effective_from: null, source: 'sheet', note: null, filled: 1, blank: 1, in_force: false }; W.sheets.unshift(d); T.settings_values.push({ sheet_id: 20, key: 'drawer_float', value: 2500 }, { sheet_id: 20, key: 'imprest', value: null }); } return { data: d.id, error: null }; }
  if (fn === 'sheet_set') { Object.keys(args.p_values).forEach((k) => { const r = T.settings_values.find((x) => x.sheet_id === args.p_sheet && x.key === k); if (r) r.value = args.p_values[k]; else T.settings_values.push({ sheet_id: args.p_sheet, key: k, value: args.p_values[k] }); }); return { data: Object.keys(args.p_values).length, error: null }; }
  if (fn === 'sheet_approve') { const s = W.sheets.find((x) => x.id === args.p_sheet); s.status = 'approved'; s.effective_from = args.p_effective; return { data: { ok: true, version: s.version }, error: null }; }
  if (fn === 'sheet_discard') { W.sheets.find((x) => x.id === args.p_sheet).status = 'discarded'; return { data: null, error: null }; }
  if (fn === 'get_limit') return { data: W.limits[args.p_key] === undefined ? null : W.limits[args.p_key], error: null };
  if (fn === 'limit_missing') return { data: args.p_keys.filter((k) => W.limits[k] === undefined), error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
const STEPS_FN = `window.__STEPS = (loc, n) => ${JSON.stringify(TITLES)}.map((t, i) => ({ location_id: loc, step_no: i + 1, title_bn: 'ধাপ ' + (i + 1), title: t, owner_role: i === 0 ? 'Owner' : 'Head management', owner_yes: [1, 5, 8, 10].includes(i + 1), optional: i + 1 === 13, done: i + 1 <= n, note: null }));`;
module.exports = Object.assign({}, C, { mk, EXTRA3: STEPS_FN + EXTRA3, TITLES });
