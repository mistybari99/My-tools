// P2c web: attend2 (self punch + evidence + soft GPS, mark others with source tag + client-id outbox, locks, counted-once report), eqcheck page, and the B.rpcq outbox.
// Run: timeout 250 node attend2_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const ROOT = _P.WEB_DIR;
const base = C.baseData(SP), PORT = _P.freePort();
const srv = http.createServer((q, r) => {
  const u = q.url.split('?')[0]; const f = path.join(ROOT, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
    if (ext === '.html' && !/attend2\.js/.test(String(b))) b = Buffer.from(String(b).replace('</body>', '<script src="attend2.js"></script></body>'));
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = window.__A2 = Object.assign({ calls: [], err: {}, net: false, seen: {}, me: null, board: null, staff: null, count: null, regs: [], eq: {} }, window.__A20 || {});
 c.rpc = async (fn, args) => {
  if (!/^(att_|attendance_self_punch|attendance_mark_others|attendance_count_once|attendance_form_link_run|entry_equation_check)/.test(fn)) return rpc(fn, args);
  W.calls.push([fn, clone(args || {})]);
  if (W.net) return { data: null, error: { message: 'TypeError: Failed to fetch', code: '' } };
  if (W.err[fn]) { const m = W.err[fn]; delete W.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  if (fn === 'att_my_status') return { data: clone(W.me), error: null };
  if (fn === 'attendance_self_punch') return { data: { id: 1, direction: args.p_dir, evidence_state: args.p_ev_kind ? (W.regs.find((r) => r.kind === args.p_ev_kind && r.ref === args.p_ev_ref) ? 'registered' : 'unregistered') : 'none', geo_flag: args.p_lat == null ? 'unchecked' : 'ok' }, error: null };
  if (fn === 'att_evidence_register') { const id = W.regs.length + 1; W.regs.push({ id, kind: args.p_kind, ref: args.p_ref, label: args.p_label, active: true, employee_id: args.p_emp }); T.att_evidence_reg = W.regs; return { data: { id }, error: null }; }
  if (fn === 'att_evidence_void') { const r = W.regs.find((x) => x.id === args.p_id); r.active = false; return { data: { id: args.p_id, active: false }, error: null }; }
  if (fn === 'att_others_board') return { data: clone(W.board), error: null };
  if (fn === 'attendance_mark_others') { if (W.seen[args.p_client]) return { data: Object.assign({}, W.seen[args.p_client], { duplicate: true }), error: null };
    const r = W.board.rows.find((x) => x.employee_id === args.p_emp); Object.assign(r, { status: args.p_status, rest_minutes: args.p_rest_min, mark_source: args.p_source, pending: true }); W.seen[args.p_client] = { status: args.p_status }; W.written = (W.written || 0) + 1; return { data: { status: args.p_status }, error: null }; }
  if (fn === 'att_staff_overview') return { data: clone(W.staff), error: null };
  if (fn === 'att_self_lock_set') { if (args.p_scope === 'person') W.staff.rows.find((x) => x.employee_id === args.p_ref).person_locked = args.p_locked; else { const r = W.staff.role_locks.find((x) => x.role === args.p_ref); if (r) r.locked = args.p_locked; else W.staff.role_locks.push({ role: args.p_ref, locked: args.p_locked }); } return { data: { locked: args.p_locked }, error: null }; }
  if (fn === 'att_site_geo_set') return { data: { location_id: args.p_loc }, error: null };
  if (fn === 'attendance_count_once') return { data: clone(W.count), error: null };
  if (fn === 'attendance_form_link_run') return { data: { result: { linked: 1 } }, error: null };
  if (fn === 'entry_equation_check') return { data: clone(W.eq[args.p_entry]), error: null };
  return { data: null, error: null };
 }; return c; }; })();
 // browser pieces the headless run does not have: a passkey and a fake photo upload
 (function(){ const cred = { rawId: new Uint8Array([1,2,3,4,5,6,7,8]).buffer }; navigator.credentials.create = async () => { (window.__A2 = window.__A2 || {}).passCreate = true; return cred; };
   navigator.credentials.get = async () => { (window.__A2 = window.__A2 || {}).passGet = true; return cred; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, permissions: ['geolocation'], geolocation: { latitude: 23.8103, longitude: 90.4125 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept('lost phone')); await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const T = data.tables;
    T.att_evidence_reg = [];
    T.entries = [{ id: 'q1', form_code: '10-2', serial: 1, entry_date: '2026-10-12', status: 'submitted', location_id: 1, data: {}, flags: [] }, { id: 'w1', form_code: '02-2', serial: 4, entry_date: '2026-10-11', status: 'draft', location_id: 1, data: {}, flags: [] }];
    const emp = (id, n, bn, en, st) => ({ employee_id: id, employee_no: n, name_bn: bn, name_en: en, status: st || 'absent', rest_minutes: null, mark_source: null, pending: false, is_me: false, person_locked: false, role: 'salesperson', evidence: [] });
    const A2 = {
      me: o.me || { employee: true, employee_id: 'e5', name_bn: 'সালমা', name_en: 'Salma', can_punch: true, state: 'ok', evidence: [], last_punch: null, geo_check_on: true },
      board: { day: '2026-10-13', location_id: 1, rows: [emp('e1', 'E01', 'করিম', 'Karim'), Object.assign(emp('e11', 'E11', 'ম্যানেজার', 'Manager Emp', 'present'), { is_me: true })] },
      staff: { location_id: 1, self_punch_master: true, rows: [Object.assign(emp('e1', 'E01', 'করিম', 'Karim'), { evidence: [{ id: 1, kind: 'finger_device' }] }), emp('e5', 'E05', 'সালমা', 'Salma')], role_locks: [] },
      count: { location_id: 1, month: '2026-09-01', primary: 'a', counted: 'attendance_record', path_a_has_month: true, a_open: true, b_open: true, mismatches: 1,
        forms: [{ entry_id: 'f1', serial: 1, status: 'submitted', is_shadow: true }, { entry_id: 'f2', serial: 2, status: 'submitted', is_shadow: false }],
        rows: [{ employee_id: 'e1', name_bn: 'করিম', name_en: 'Karim', employee_no: 'E01', mismatch: true, device: { present: 2, late: 0, absent: 1, ot_hours: 2 }, form: { present: 5, late: 0, absent: 0, ot_hours: 0 } },
               { employee_id: 'e5', name_bn: 'সালমা', name_en: 'Salma', employee_no: 'E05', mismatch: false, device: { present: 3, late: 1, absent: 0, ot_hours: 0 }, form: { present: 3, late: 1, absent: 0, ot_hours: 0 } }] },
      eq: { q1: { form: '10-2', supported: true, ok: false, recomputed: { total: 500, imprest_diff: -200 }, mismatches: [{ code: 'imprest_mismatch', kind: 'flag_missing', recomputed: -200, stored: null }], observations: [] },
            w1: { form: '02-2', supported: true, ok: true, recomputed: { t_net: 1600 }, mismatches: [], observations: [{ code: 'receipts_vs_net', receipts_total: 2100, sheet_net: 1600 }] } } };
    const m0 = o.staff ? { grants: [], ctx: { is_owner: false, roles: ['salesperson'], locations: [1] } } : {};
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(m0)};window.__OWNER=${o.staff ? 'false' : 'true'};window.__A20=${JSON.stringify(A2)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__A2.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // ---------- me: punch with and without evidence ----------
  let p = await open('#/attend2');
  if (process.env.A2DBG) { console.log((await text(p)).slice(0, 600)); console.log(errors.join('\n')); }
  let t = await text(p); ok(/You can punch now/.test(t) && /Honest limits/.test(t), 'status chip + honest limits box');
  ok(await p.locator('[data-act=a2_punch]').count() === 2, 'check in / out buttons');
  await p.click('[data-act=a2_punch][data-v=in]'); await wait(p, 500);
  let c = await calls(p, 'attendance_self_punch'); ok(c.length === 1 && c[0].p_dir === 'in' && c[0].p_ev_kind === null && c[0].p_lat !== null, 'punch without evidence, with the soft GPS (box ticked)');
  await p.click('[data-act=a2_regpass]'); await wait(p, 500);
  c = await calls(p, 'att_evidence_register'); ok(c.length === 1 && c[0].p_kind === 'webauthn' && c[0].p_ref === 'AQIDBAUGBwg' && c[0].p_emp === 'e5', 'passkey registered as a reference only');
  ok(/passkey/.test(await text(p)), 'registration listed after the call');
  await p.selectOption('#a2_ev', 'webauthn'); await p.evaluate(() => { window.__A2.calls.length = 0; });
  await p.click('[data-act=a2_punch][data-v=out]'); await wait(p, 500);
  c = await calls(p, 'attendance_self_punch'); ok(c.length === 1 && c[0].p_ev_kind === 'webauthn' && c[0].p_ev_ref === 'AQIDBAUGBwg' && await p.evaluate(() => !!window.__A2.passGet), 'punch with passkey evidence');
  await p.evaluate(() => { window.__A2.err.attendance_self_punch = 'self_punch_locked: x'; });
  await p.click('[data-act=a2_punch][data-v=in]'); await wait(p, 400);
  ok(/locked self punch/.test(await text(p)), 'friendly text when the owner locked self punch');
  await noOverflow(p, 'me');
  p = await open('#/attend2', { me: { employee: true, employee_id: 'e5', name_bn: 'সালমা', name_en: 'Salma', can_punch: false, state: 'self_punch_locked', evidence: [], geo_check_on: false } });
  t = await text(p); ok(/locked self punch/.test(t) && await p.locator('[data-act=a2_punch]').count() === 0, 'locked person sees why and has no punch buttons');

  // ---------- mark others + client-id outbox ----------
  p = await open('#/attend2');
  await p.click('[data-act=a2_tab][data-v=mark]'); await wait(p, 600);
  ok(await p.locator('#a2_rows .card').count() === 2, 'two people on the board');
  ok(await p.locator('[data-act=a2_mark]').count() === 1, 'no Mark button on his own row');
  await p.click('[data-act=a2_mark][data-v=e1]'); await wait(p, 300);
  ok(/YOUR declaration/.test(await p.textContent('.sheet')) && await p.locator('#a2_src option').count() === 4, 'source tag choices with the honest hint');
  await p.selectOption('#a2_s', 'present'); await p.fill('#a2_in', '09:00'); await p.fill('#a2_out', '21:00'); await p.fill('#a2_rest', '60'); await p.selectOption('#a2_src', 'finger');
  await p.click('[data-act=a2_marksave]'); await wait(p, 300);
  ok((await calls(p, 'attendance_mark_others')).length === 0, 'reason is required before anything is sent');
  await p.fill('#a2_r', 'device offline'); await p.evaluate(() => { window.__A2.net = true; });
  await p.click('[data-act=a2_marksave]'); await wait(p, 700);
  c = await calls(p, 'attendance_mark_others'); ok(c.length === 1 && c[0].p_emp === 'e1' && c[0].p_in === '09:00' && c[0].p_out === '21:00' && c[0].p_rest_min === 60 && c[0].p_source === 'finger' && !!c[0].p_client, 'mark sent with times, rest, tag and a client key');
  t = await text(p); ok(/Not sent yet/.test(t) && /Kept on the phone|Not sent yet/.test(t), 'network down: kept on the phone, shown as not sent yet');
  const q = await p.evaluate(() => window.BOS.rpcq.list()); ok(q.length === 1 && q[0].args.p_client === c[0].p_client && q[0].state === 'wait', 'queue holds the same client key');
  ok(await p.evaluate(() => (localStorage.getItem('bos_rpcq_' + (window.BOS_APP.S.ctx.profile ? window.BOS_APP.S.ctx.profile.id : 'anon')) || '').includes('device offline')), 'a localStorage copy exists');
  const idbN = await p.evaluate(() => new Promise((res) => { const r = indexedDB.open('bos_rpcq', 1); r.onsuccess = () => { const g = r.result.transaction('q').objectStore('q').getAll(); g.onsuccess = () => res(g.result.length); }; r.onerror = () => res(-1); }));
  ok(idbN === 1, 'an IndexedDB copy exists (' + idbN + ')');
  await p.evaluate(() => { window.__A2.net = false; });
  await p.evaluate(() => window.dispatchEvent(new Event('online'))); await wait(p, 800);
  c = await calls(p, 'attendance_mark_others'); ok(c.length === 2 && c[1].p_client === c[0].p_client, 'back online: resent with the SAME key');
  ok((await p.evaluate(() => window.BOS.rpcq.list())).length === 0 && await p.evaluate(() => window.__A2.written === 1), 'queue empty and the server wrote once');
  // a lost answer: server saved it, phone did not hear -> resend gives duplicate, still one write
  await p.evaluate(() => { const A = window.__A2; A.seen['K-LOST'] = { status: 'late' }; window.BOS.rpcq.enqueue({ id: 'K-LOST', fn: 'attendance_mark_others', args: { p_emp: 'e1', p_day: '2026-10-13', p_status: 'late', p_source: 'manual', p_reason: 'abc', p_client: 'K-LOST' }, label: 'lost answer' }); });
  await wait(p, 300); await p.evaluate(() => window.BOS.rpcq.flush()); await wait(p, 400);
  ok((await p.evaluate(() => window.BOS.rpcq.list())).length === 0 && await p.evaluate(() => window.__A2.written === 1), 'repeated key = duplicate answer, queue cleared, no second write');
  // a server refusal is kept visible, not retried forever
  await p.evaluate(() => { window.BOS.rpcq.enqueue({ id: 'K-BAD', fn: 'attendance_mark_others', args: { p_emp: 'e1', p_day: '2026-10-13', p_status: 'present', p_source: 'manual', p_reason: 'abc', p_client: 'K-BAD' }, label: 'bad one' }); window.__A2.err.attendance_mark_others = 'month_locked'; });
  await wait(p, 300); await p.evaluate(() => window.BOS.rpcq.flush()); await wait(p, 500);
  const q2 = await p.evaluate(() => window.BOS.rpcq.list()); ok(q2.length === 1 && q2[0].state === 'refused' && /month_locked/.test(q2[0].msg), 'refused item kept with the server message');
  await p.evaluate(() => { window.__A2.calls.length = 0; window.BOS.rpcq.flush(); }); await wait(p, 300); ok((await calls(p, 'attendance_mark_others')).length === 0, 'refused items are not resent by themselves');
  await p.evaluate(() => { window.BOS.rpcq.discard('K-BAD'); });
  // saveEntry helper keeps the form client id in the meta
  const se = await p.evaluate(() => { const id = window.BOS.rpcq.saveEntry({ p_id: null, p_form: '10-2', p_loc: 1, p_date: '2026-10-13', p_data: {}, p_flags: [] }, { client_id: 'C-1' }); const it = window.BOS.rpcq.list().find((x) => x.id === 'C-1'); const r = { id, fn: it && it.fn, cid: it && it.args.p_meta.client_id }; window.BOS.rpcq.discard('C-1'); return r; });
  ok(se.id === 'C-1' && se.fn === 'save_entry' && se.cid === 'C-1', 'saveEntry queues save_entry with its client_id meta');
  await p.evaluate(() => { window.__A2.err.attendance_mark_others = 'cannot_mark_self'; });
  await p.click('[data-act=a2_mark][data-v=e1]'); await wait(p, 300); await p.fill('#a2_r', 'again'); await p.click('[data-act=a2_marksave]'); await wait(p, 500);
  ok(/cannot mark yourself/.test(await text(p)), 'friendly text for cannot_mark_self');
  await noOverflow(p, 'mark');
  p = await open('#/attend2', { staff: true });
  await p.click('[data-act=a2_tab][data-v=mark]'); await wait(p, 600);
  ok(/owner gives this right/.test(await text(p)) && (await calls(p, 'att_others_board')).length === 0, 'no grant: explained, board not even requested');

  // ---------- staff and locks ----------
  p = await open('#/attend2');
  await p.click('[data-act=a2_tab][data-v=staff]'); await wait(p, 600);
  t = await text(p); ok(/Karim/.test(t) && /finger \(device\)/.test(t) && /Master switch app_punch_on: ON/.test(t), 'people with evidence chips and the master switch state');
  await p.click('[data-act=a2_lockp][data-v=e5]'); await wait(p, 500);
  c = await calls(p, 'att_self_lock_set'); ok(c.length === 1 && c[0].p_scope === 'person' && c[0].p_ref === 'e5' && c[0].p_locked === true, 'person lock sent');
  ok(/Self-punch lock: Locked/.test(await text(p)), 'lock shown after reload');
  await p.click('[data-act=a2_lockr][data-v=salesperson]'); await wait(p, 500);
  c = await calls(p, 'att_self_lock_set'); ok(c.length === 2 && c[1].p_scope === 'role' && c[1].p_ref === 'salesperson' && c[1].p_locked === true, 'role lock sent');
  await p.click('[data-act=a2_geoset]'); await wait(p, 600); c = await calls(p, 'att_site_geo_set'); ok(c.length === 1 && Math.abs(c[0].p_lat - 23.8103) < 0.001, 'place coordinates from the phone');
  await p.selectOption('#a2_fe', 'e5'); await p.fill('#a2_fd', 'dev-17'); await p.click('[data-act=a2_finger]'); await wait(p, 400);
  c = await calls(p, 'att_evidence_register'); ok(c.length === 1 && c[0].p_kind === 'finger_device' && c[0].p_ref === 'dev-17', 'fingerprint-enrolled flag');
  await noOverflow(p, 'staff');

  // ---------- counted once ----------
  await p.click('[data-act=a2_tab][data-v=count]'); await wait(p, 600);
  t = await text(p); ok(/Attendance record/.test(t) && /Shadow copy \(locked\)/.test(t) && /Differs/.test(t) && /Matches/.test(t) && /14-1/.test(t), 'counted source, shadow chip, per-person difference, 14-1 note');
  await p.click('[data-act=a2_link]'); await wait(p, 500); c = await calls(p, 'attendance_form_link_run'); ok(c.length === 1 && c[0].p_month.endsWith('-01'), 'link now');
  await noOverflow(p, 'count');

  // ---------- eqcheck ----------
  p = await open('#/eqcheck'); await wait(p, 500);
  ok(await p.locator('[data-act=eq_check]').count() === 2, 'two sheets listed');
  await p.click('[data-act=eq_check][data-v=q1]'); await wait(p, 400);
  t = await text(p); ok(/imprest_mismatch/.test(t) && /the phone raised no flag/.test(t), 'difference shown with plain words');
  await p.click('[data-act=eq_check][data-v=w1]'); await wait(p, 400);
  t = await text(p); ok(/All match/.test(t) && /receipts_vs_net/.test(t), 'honest sheet: all match + information line');
  await noOverflow(p, 'eqcheck');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
