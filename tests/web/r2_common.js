// Shared harness for announce_test.js, todo_test.js, shifts_test.js (package R2). Headless Chromium at 360x780 against THIS checkout's web/ folder.
//   const R = require(SP + '/r2_common.js')(SP, PORT);  await R.start();  const p = await R.open('#/announce', { owner:false, lang:'en', rules:{announce_on:true}, init:{...} });
//   window.__R2 in the page = the state of the server stand-in (R2 RPCs only; everything else goes to the normal stub): calls [[fn,args]...], err {fn:'message'}, missing {fn:true|all:true},
//   ann {state, active, mine, receipts, posted}, todo {on, repeat_on, can_assign, mine, given}, shift {state, my, roster, report}, staff [...].
// Test names only (test_*). Screenshots go to $R2_SHOTS or the temp folder, never into the repository.
const fs = require('fs'), path = require('path'), http = require('http'), os = require('os');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');

const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const build = () => ({ calls: [], err: {}, missing: {}, keep: false, next: 500,
   staff: [{ id: 'p1', staff_id: 'test_a', full_name: 'test_person_a' }, { id: 'p2', staff_id: 'test_b', full_name: 'test_person_b' }],
   ann: { state: { on: true, can_post: false, can_post_all: false, post_locations: [] }, active: [], mine: [], receipts: {}, posted: [] },
   todo: { on: true, repeat_on: false, can_assign: false, mine: [], given: [] },
   shift: { state: { on: true, mates_on: true, can_manage: false, locations: [], linked: true }, my: { on: true, linked: true, mates_on: true, days: [] },
            roster: { templates: [], employees: [] }, report: { attendance: true, rows: [], totals: {} } } });
 const merge = (t, s) => { for (const k of Object.keys(s || {})) { if (s[k] && typeof s[k] === 'object' && !Array.isArray(s[k]) && t[k] && typeof t[k] === 'object') merge(t[k], s[k]); else t[k] = s[k]; } return t; };
 const R = window.__R2 = window.__R2 || merge(build(), window.__R2_INIT || {});
 const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
 const addDays = (iso, n) => { const d = new Date(iso + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
 c.rpc = async (fn, args) => {
  if (fn === 'staff_directory') return { data: clone(R.staff), error: null };
  if (!/^r2_/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, clone(args || {})]);
  if (R.missing[fn] === true || R.missing.all === true) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + fn } };
  if (R.err[fn]) { const m = R.err[fn]; if (!R.keep) delete R.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  const A = R.ann, T = R.todo, S = R.shift, ok = (d) => ({ data: clone(d), error: null }), bad = (m) => ({ data: null, error: { message: m, code: 'P0001' } });
  // ---- announcements
  if (fn === 'r2_announce_state') return ok(A.state);
  if (fn === 'r2_announce_active') return ok(A.active);
  if (fn === 'r2_announce_seen') { const x = A.active.find((y) => y.id === args.p_id); if (!x) return bad('not allowed'); x.seen = true; return ok({ id: x.id, seen: true }); }
  if (fn === 'r2_announce_post') { A.posted.push(clone(args)); const id = R.next++; A.mine.unshift({ id, title: args.p_title, body: args.p_body, urgent: args.p_urgent, target_kind: args.p_kind, target_role: args.p_kind === 'role' ? args.p_target : null,
      target_location: args.p_kind === 'location' ? Number(args.p_target) : null, target_user: null, target_name: null, starts_at: args.p_starts || new Date().toISOString(), ends_at: args.p_ends, status: 'active', created_at: new Date().toISOString(),
      created_by: 'u1', poster: 'test_owner', withdrawn_reason: null, live: true, audience: 5, seen: 0 }); return ok({ id, audience: 5 }); }
  if (fn === 'r2_announce_mine') return ok(A.mine);
  if (fn === 'r2_announce_receipts') return ok(A.receipts[args.p_id] || { id: args.p_id, title: 'test', status: 'active', seen: [], unseen: [] });
  if (fn === 'r2_announce_withdraw') { const x = A.mine.find((y) => y.id === args.p_id); if (!x) return bad('not allowed'); x.status = 'withdrawn'; x.live = false; x.withdrawn_reason = args.p_reason; return ok({ id: x.id, status: 'withdrawn' }); }
  // ---- to-do
  const open = () => T.mine.filter((x) => x.status === 'open');
  if (fn === 'r2_todo_state') { if (T.on === false) return ok({ on: false, repeat_on: false, can_assign: false, open: 0, overdue: 0, next: [] }); return ok({ on: true, repeat_on: !!T.repeat_on, can_assign: !!T.can_assign, open: open().length, overdue: open().filter((x) => x.overdue).length, next: open().slice(0, 3) }); }
  if (fn === 'r2_todo_mine') return ok(T.on === false ? [] : T.mine.filter((x) => x.status === 'open' || (args.p_all && (x.status === 'done' || x.status === 'cannot'))));
  if (fn === 'r2_todo_given') return ok(T.given.filter((x) => !args.p_status || x.status === args.p_status));
  if (fn === 'r2_todo_assign') { T.assigned = (T.assigned || []).concat([clone(args)]); const n = args.p_kind === 'role' ? 3 : 1; for (let i = 0; i < n; i++) T.given.unshift({ id: R.next++, title: args.p_title, detail: args.p_detail, due_date: args.p_due, priority: args.p_priority, status: 'open', assignee: 'test_person_' + i, repeat_kind: args.p_repeat, overdue: false }); return ok({ count: n, ids: [1] }); }
  if (fn === 'r2_todo_set') { const x = T.mine.find((y) => y.id === args.p_id); if (!x) return bad('not allowed'); if (args.p_status === 'cannot' && !(args.p_note || '').trim()) return bad('reason_required'); x.status = args.p_status; x.status_note = args.p_note; x.overdue = false; return ok({ id: x.id, status: x.status }); }
  if (fn === 'r2_todo_manage') { const x = T.given.find((y) => y.id === args.p_id); if (!x) return bad('not allowed'); if (args.p_action === 'cancel') { if (!(args.p_note || '').trim()) return bad('reason_required'); x.status = 'cancelled'; x.status_note = args.p_note; } else { x.status = 'open'; } return ok({ id: x.id, status: x.status }); }
  // ---- shifts
  if (fn === 'r2_shift_state') return ok(S.state);
  if (fn === 'r2_shift_my') return ok(S.my);
  if (fn === 'r2_shift_roster') { const r = clone(S.roster); r.loc = args.p_loc; r.from = args.p_from || today(); r.days = args.p_days || 7;
    r.employees.forEach((e) => { e.days = (e.d || []).map((o) => Object.assign({ day: addDays(r.from, o.o), shift_id: o.shift_id === undefined ? null : o.shift_id, off: !!o.off, note: o.note || null, source: o.source || 'day', holiday_bn: null, holiday_en: null, leave: !!o.leave })); }); return ok(r); }
  if (['r2_roster_set', 'r2_roster_clear', 'r2_roster_week', 'r2_roster_copy_week'].includes(fn)) return ok(fn === 'r2_roster_copy_week' ? { copied: 4, skipped: 1 } : { id: R.next++ });
  if (fn === 'r2_shift_template_save') { const t = S.roster.templates; if (args.p_id) { const x = t.find((y) => y.id === args.p_id); if (x) { Object.assign(x, args.p_data.active === false ? { retired: true } : {}); if (args.p_data.active === false) S.roster.templates = t.filter((y) => y.id !== args.p_id); } return ok({ id: args.p_id }); }
    const id = R.next++; t.push({ id, name_bn: args.p_data.name_bn, name_en: args.p_data.name_en, location_id: args.p_data.location_id === undefined ? null : args.p_data.location_id, start: args.p_data.start_time, end: args.p_data.end_time }); return ok({ id }); }
  if (fn === 'r2_shift_report') return ok(S.report);
  return ok(null);
 }; return c; }; })();`;

module.exports = (SP, PORT) => {
  const C = require(SP + '/w5b_common.js'); const base = C.baseData(SP);
  const srv = http.createServer((q, r) => { const f = path.join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]);
    fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
  const R = { C, srv, errors: [], bad: 0, n: 0, br: null };
  R.log = (...a) => console.log(...a);
  R.ok = (c, m) => { R.n++; if (!c) { R.bad++; console.log('FAIL:', m); } };
  R.start = async () => { R.br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' }); };
  R.stop = async () => { if (R.br) await R.br.close(); srv.close(); };
  R.wait = (p, n = 300) => p.waitForTimeout(n);
  R.text = (p) => p.evaluate(() => document.body.innerText);
  R.calls = (p, fn) => p.evaluate((f) => window.__R2.calls.filter((c) => !f || c[0] === f).map((c) => c[1]), fn || null);
  R.callNames = (p) => p.evaluate(() => window.__R2.calls.map((c) => c[0]));
  R.noOverflow = async (p, m) => R.ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow: ' + m);
  R.shot = async (p, name) => { const d = process.env.R2_SHOTS || path.join(os.tmpdir(), 'r2shots'); try { fs.mkdirSync(d, { recursive: true }); await p.screenshot({ path: path.join(d, name + '.png') }); } catch (e) { /* screenshots are optional */ } };
  R.today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
  R.addDays = (iso, n) => { const d = new Date(iso + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
  // o: owner (default true), lang, rules {key:true|false}, init (merged into window.__R2), reducedMotion, dark
  R.open = async (hash, o = {}) => {
    const ctx = await R.br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, reducedMotion: o.reducedMotion ? 'reduce' : 'no-preference', colorScheme: o.dark ? 'dark' : 'light' });
    const p = await ctx.newPage();
    p.on('pageerror', (e) => R.errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) R.errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    Object.keys(o.rules || {}).forEach((k) => data.tables.rules.push({ key: k, module: 'people', kind: 'switch', value: o.rules[k], default_value: k === 'shift_mates_on', label_bn: k, label_en: k, label_mix: k, sort: 9 }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__R2_INIT=${JSON.stringify(o.init || {})};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(o.settle || 1600); return p;
  };
  return R;
};
