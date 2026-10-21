// Test-only stand-in for supabase-js: in-memory tables, owner session.
(function () {
  const D = window.__DATA;
  const OWNER = { id: 'u1', staff_id: 'owner1', full_name: 'TestK Uddin', status: 'active', lang: 'bn' };
  let session = window.__SESSION === false ? null : { user: { id: 'u1' } };
  const tables = D.tables;
  function builder(name) {
    let maybe = false, single = false, rows = tables[name] || (tables[name] = []), op = 'select', payload = null, filters = [], ord = null, lim = null, head = false, count = false, rng = null, conflict = null;
    const b = {
      select(_c, o) { if (o && o.head) head = true; if (o && o.count) count = true; return b; },
      order(c, o) { ord = [c, !(o && o.ascending === false)]; return b; },
      eq(c, v) { filters.push((r) => r[c] === v); return b; },
      gte(c, v) { filters.push((r) => r[c] >= v); return b; }, lt(c, v) { filters.push((r) => r[c] < v); return b; }, lte(c, v) { filters.push((r) => r[c] <= v); return b; }, neq(c, v) { filters.push((r) => r[c] !== v); return b; }, in(c, arr) { filters.push((r) => arr.includes(r[c])); return b; }, single() { single = true; return b; },
      limit(n) { lim = n; return b; }, maybeSingle() { single = true; maybe = true; return b; }, range(a, z) { rng = [a, z]; return b; },
      insert(p) { op = 'insert'; payload = p; return b; }, update(p) { op = 'update'; payload = p; return b; },
      upsert(p, o) { op = 'upsert'; payload = p; conflict = o && o.onConflict ? o.onConflict.split(',') : null; return b; }, delete() { op = 'delete'; return b; },
      then(res, rej) { return Promise.resolve(run()).then(res, rej); },
    };
    function run() {
      let out = rows.filter((r) => filters.every((f) => f(r)));
      if (op === 'update') { out.forEach((r) => Object.assign(r, payload)); return { data: out, error: null }; }
      if (op === 'insert') { const n = Object.assign({ id: 'new' + Math.random(), code: 'I-999' }, payload); rows.push(n); return { data: [n], error: null }; }
      if (op === 'upsert') { const k = conflict || ['role_code', 'form_code']; (Array.isArray(payload) ? payload : [payload]).forEach((pl) => { const i = rows.findIndex((r) => k.every((x) => r[x] === pl[x])); if (i >= 0) rows[i] = pl; else rows.push(pl); }); return { data: Array.isArray(payload) ? payload : [payload], error: null }; }
      if (op === 'delete') { tables[name] = rows = rows.filter((r) => !filters.every((f) => f(r))); return { data: [], error: null }; }
      if (ord) out = [...out].sort((a, z) => (a[ord[0]] > z[ord[0]] ? 1 : -1) * (ord[1] ? 1 : -1));
      if (lim) out = out.slice(0, lim); if (rng) out = out.slice(rng[0], rng[1] + 1);
      if (single) return { data: out[0] || null, error: out[0] || maybe ? null : { message: 'none' } };
      return head ? { data: null, count: out.length, error: null } : { data: out, count: out.length, error: null };
    }
    return b;
  }
  window.supabase = { createClient: () => ({
    auth: {
      getSession: async () => ({ data: { session } }),
      signInWithPassword: async ({ password }) => { if (password.startsWith('0000')) return { error: { message: 'bad' } }; session = { user: { id: 'u1' } }; return { data: { session }, error: null }; },
      signUp: async () => ({ data: { session: null }, error: null }),
      signOut: async () => { session = null; },
    },
    rpc: async (fn, args) => {
      if (fn === 'staff_directory') return { data: [{ staff_id: 'owner1', full_name: 'TestK Uddin' }, { staff_id: 'testf02', full_name: 'TestF' }, { staff_id: 'teste03', full_name: 'TestE' }], error: null };
      if (fn === 'save_entry') { const E = tables.entries; let e = args.p_id && E.find((x) => x.id === args.p_id);
        if (!e) { e = { id: 'e' + (E.length + 1), serial: E.length + 1, form_code: args.p_form, location_id: args.p_loc, status: 'draft', created_by: 'u1', created_staff: 'owner1', check_data: {} }; E.push(e); }
        Object.assign(e, { data: args.p_data, flags: args.p_flags, entry_date: args.p_date }); window.__SAVED = JSON.parse(JSON.stringify(e)); return { data: { id: e.id, serial: e.serial }, error: null }; }
      if (fn === 'submit_entry') { const e = tables.entries.find((x) => x.id === args.p_id); const red = (e.flags || []).filter((f) => f.level === 'red' && !(tables.release_requests || []).some((r) => r.entry_id === e.id && r.flag_code === f.code && r.status === 'approved'));
        if (red.length) return { data: null, error: { message: 'red_blocked:' + red.map((f) => f.code).join(',') } }; e.status = 'submitted'; return { data: { status: 'submitted' }, error: null }; }
      if (fn === 'request_release') { (tables.release_requests = tables.release_requests || []).push({ id: 1, entry_id: args.p_entry, flag_code: args.p_flag, status: 'pending', reason: args.p_reason }); return { data: { id: 1 }, error: null }; }
      if (fn === 'decide_entry') { const e = tables.entries.find((x) => x.id === args.p_id); e.status = args.p_approve ? 'approved' : 'rejected'; e.check_data = args.p_check; window.__DECIDED = args; return { data: { status: e.status }, error: null }; }

      if (fn === 'my_context') { const perms = {}; tables.forms.forEach((f) => { perms[f.code] = { view: true, enter: true, approve: true }; });
        return { data: { profile: window.__PROFILE || OWNER, is_owner: window.__OWNER !== false, roles: ['owner'], locations: [], perms: window.__PERMS || perms }, error: null }; }
      if (fn === 'submit_item_change') return { data: { status: window.__OWNER === false ? 'pending' : 'applied' }, error: null };
      if (fn === 'decide_item_change') return { data: { status: 'approved' }, error: null };
      if (fn === 'login_precheck') return { data: { locked: false }, error: null };
      return { data: null, error: null };
    },
    from: builder,
  }) };
})();
