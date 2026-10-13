// Module B2 web: attendance board (mark / approve / OT / recompute), month grid, device file import (preview first, batch, undo), unmapped ids,
// devices (token shown once), shifts and holidays, leave requests / approvals / balances, app check-in, friendly errors, no overflow at 360px.
// Run: timeout 250 node attendance_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const ROOT = '/home/user/My-tools/web';
const base = C.baseData(SP), PORT = 8442;
// the lead adds the script tags to index.html (docs/regs/attendance.md); the test injects them so it does not depend on that edit
const srv = http.createServer((q, r) => {
  const u = q.url.split('?')[0]; const f = path.join(ROOT, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
    if (ext === '.html' && !/attendance\.js/.test(String(b))) b = Buffer.from(String(b).replace('</body>', '<script src="attendance.js"></script><script src="payroll.js"></script></body>'));
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

const EXTRA42 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 c.rpc = async (fn, args) => {
  (window.__AC42 = window.__AC42 || []).push([fn, clone(args || {})]);
  const E = window.__ERR42 && window.__ERR42[fn]; if (E) { delete window.__ERR42[fn]; return { data: null, error: { message: E, code: 'P0001' } }; }
  if (fn === 'attendance_board') return { data: clone(window.__BOARD), error: null };
  if (fn === 'attendance_recompute') return { data: { employees: 4, days_saved: 4, manual_kept: 1, locked: 0 }, error: null };
  if (fn === 'attendance_mark') { const r = window.__BOARD.rows.find((x) => x.employee_id === args.p_emp); Object.assign(r, { status: args.p_status, source: 'manual', pending: true, reason: args.p_reason }); return { data: { approved: false }, error: null }; }
  if (fn === 'attendance_approve') { const r = window.__BOARD.rows.find((x) => x.employee_id === args.p_emp); r.pending = false; if (!args.p_approve) r.source = 'auto'; return { data: { approved: args.p_approve }, error: null }; }
  if (fn === 'attendance_ot_approve') { const r = window.__BOARD.rows.find((x) => x.employee_id === args.p_emp); r.ot_approved = true; return { data: { ot_approved: true }, error: null }; }
  if (fn === 'attendance_month') { const days = []; for (let d = 1; d <= 30; d++) days.push({ day: '2026-09-' + String(d).padStart(2, '0'), status: d === 4 ? 'absent' : d % 7 === 4 ? 'off' : d === 10 ? 'late' : d === 11 ? 'leave' : 'present', ot_minutes: d === 12 ? 120 : 0 }); return { data: { days, locked: true }, error: null }; }
  if (fn === 'attendance_import') { if (args.p_dry) return { data: { dry: true, total: args.p_rows.length, rejected: 0, valid: args.p_rows.length, duplicates_in_file: 1, already_in: 0, new: args.p_rows.length - 1, unmapped: 1, unmapped_ids: ['777'], employees: 1, from: '2026-10-01T02:58:00Z', to: '2026-10-01T12:01:00Z' }, error: null };
    T.attendance_import_batches.unshift({ id: 'b2', location_id: args.p_loc, file_name: args.p_file, rows_new: args.p_rows.length - 1, rows_dup: 1, rows_unmapped: 1, status: 'active', created_at: '2026-10-13T05:00:00Z' }); return { data: { new: args.p_rows.length - 1, batch: 'b2' }, error: null }; }
  if (fn === 'attendance_import_void') { const b = T.attendance_import_batches.find((x) => x.id === args.p_batch); b.status = 'void'; return { data: { status: 'void', punches_voided: 3 }, error: null }; }
  if (fn === 'attendance_unmapped') return { data: window.__UNM || [], error: null };
  if (fn === 'attendance_map_user') { window.__UNM = []; const e = T.employees.find((x) => x.id === args.p_emp); e.device_user_id = args.p_device_user_id; return { data: { punches_mapped: 1 }, error: null }; }
  if (fn === 'attendance_device_register') { T.attendance_devices.push({ id: 7, name: args.p_name, location_id: args.p_loc, vendor: args.p_vendor, serial: args.p_serial, active: true, last_seen: null, pushed_rows: 0 }); return { data: { id: 7, token: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789', shown_once: true }, error: null }; }
  if (fn === 'attendance_device_token_reset') return { data: { id: args.p_id, token: 'ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000ffff0000' }, error: null };
  if (fn === 'attendance_device_set_active') { const d = T.attendance_devices.find((x) => x.id === args.p_id); d.active = args.p_active; return { data: { active: args.p_active }, error: null }; }
  if (fn === 'attendance_app_punch') return { data: { id: 1, direction: args.p_dir }, error: null };
  if (fn === 'shift_save') { T.shifts.push(Object.assign({ id: 9, active: true, crosses_midnight: false }, args.p_data)); return { data: { id: 9 }, error: null }; }
  if (fn === 'shift_assign') return { data: { id: 1 }, error: null };
  if (fn === 'holiday_save') { T.holidays.push({ id: 5, day: args.p_day, location_id: args.p_loc, name_bn: args.p_name_bn, name_en: args.p_name_en, paid: args.p_paid, active: true }); return { data: { id: 5 }, error: null }; }
  if (fn === 'holiday_retire') { T.holidays.find((x) => x.id === args.p_id).active = false; return { data: { id: args.p_id }, error: null }; }
  if (fn === 'leave_request_save') { T.leave_requests.unshift({ id: 50, employee_id: args.p_emp, leave_type: args.p_type, from_date: args.p_from, to_date: args.p_to, days: 2, reason: args.p_reason, status: 'pending' }); return { data: { id: 50 }, error: null }; }
  if (fn === 'leave_decide') { const r = T.leave_requests.find((x) => x.id === args.p_id); r.status = args.p_approve ? 'approved' : 'rejected'; r.decision_note = args.p_note; return { data: r, error: null }; }
  if (fn === 'leave_cancel') { T.leave_requests.find((x) => x.id === args.p_id).status = 'cancelled'; return { data: { status: 'cancelled' }, error: null }; }
  if (fn === 'leave_balances') return { data: [{ leave_type: 'casual', name_bn: 'নৈমিত্তিক', name_en: 'Casual leave', paid: true, entitled: 10, taken: 3, pending: 2, remaining: 7 }, { leave_type: 'unpaid', name_bn: 'বিনা বেতন', name_en: 'Unpaid leave', paid: false, entitled: 0, taken: 1, pending: 0, remaining: null }], error: null };
  return rpc(fn, args);
 }; return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept('wrong file loaded')); await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA42 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const T = data.tables;
    T.employees = [['e1', 'E-0001', 'করিম', 'Karim', 1, '101'], ['e2', 'E-0002', 'রহিম', 'Rahim', 1, '102'], ['e3', 'E-0003', 'জামাল', 'Jamal', 1, null], ['e5', 'E-0005', 'সালমা', 'Salma', 1, null], ['e8', 'E-0008', 'অন্য', 'Other place', 2, null]]
      .map((r) => ({ id: r[0], employee_no: r[1], full_name_bn: r[2], full_name_en: r[3], primary_location_id: r[4], device_user_id: r[5], status: 'active', profile_id: r[0] === 'e5' ? 'u1' : null }));
    T.attendance_devices = [{ id: 3, name: 'Gate ZK', location_id: 1, vendor: 'zkteco', serial: 'SN9', active: true, last_seen: '2026-10-13T04:00:00Z', pushed_rows: 120 }];
    T.attendance_import_batches = [{ id: 'b1', location_id: 1, file_name: 'old.dat', rows_new: 40, rows_dup: 2, rows_unmapped: 0, status: 'active', created_at: '2026-10-10T05:00:00Z' }];
    T.shifts = [{ id: 1, name_bn: 'সাধারণ শিফট', name_en: 'General shift', location_id: null, start_time: '09:00:00', end_time: '18:00:00', grace_late_min: 10, grace_early_min: 10, break_min: 60, crosses_midnight: false, min_hours_full_day: 7, min_hours_half_day: 4, is_default: true, active: true }];
    T.holidays = [{ id: 1, day: '2026-12-16', location_id: null, name_bn: 'বিজয় দিবস', name_en: 'Victory Day', paid: true, active: true }];
    T.leave_types = [{ code: 'casual', name_bn: 'নৈমিত্তিক ছুটি', name_en: 'Casual leave', paid: true, active: true, sort: 3 }, { code: 'unpaid', name_bn: 'বিনা বেতনের ছুটি', name_en: 'Unpaid leave', paid: false, active: true, sort: 4 }];
    T.leave_requests = [{ id: 11, employee_id: 'e2', leave_type: 'casual', from_date: '2026-10-20', to_date: '2026-10-21', days: 2, reason: 'wedding', status: 'pending' },
      { id: 12, employee_id: 'e3', leave_type: 'casual', from_date: '2026-10-02', to_date: '2026-10-02', days: 1, reason: null, status: 'approved' }, { id: 13, employee_id: 'e8', leave_type: 'casual', from_date: '2026-10-02', to_date: '2026-10-02', days: 1, status: 'pending' }];
    if (o.appPunch) T.rules.push({ key: 'app_punch_on', module: 'people', kind: 'switch', value: true, default_value: false, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 9 });
    const board = { day: '2026-10-13', rows: [
      { employee_id: 'e1', employee_no: 'E-0001', name_bn: 'করিম', name_en: 'Karim', status: 'late', first_in: '2026-10-13T03:40:00Z', last_out: null, late_minutes: 40, ot_minutes: 0, source: 'manual', pending: true, reason: 'device down', single_punch: true },
      { employee_id: 'e2', employee_no: 'E-0002', name_bn: 'রহিম', name_en: 'Rahim', status: 'present', first_in: '2026-10-13T02:55:00Z', last_out: '2026-10-13T14:00:00Z', late_minutes: 0, ot_minutes: 120, ot_approved: false, source: 'auto', pending: false },
      { employee_id: 'e3', employee_no: 'E-0003', name_bn: 'জামাল', name_en: 'Jamal', status: 'absent', source: 'auto', pending: false },
      { employee_id: 'e5', employee_no: 'E-0005', name_bn: 'সালমা', name_en: 'Salma', status: 'leave', leave_type: 'sick', source: 'auto', pending: false }],
      counts: { total: 4, present: 2, late: 1, absent: 1, leave: 1, off: 0, pending: 1 } };
    const m0 = o.staff ? { grants: [], ctx: { is_owner: false, roles: ['salesperson'], locations: [1] } } : {};
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(m0)};window.__OWNER=${o.staff ? 'false' : 'true'};window.__BOARD=${JSON.stringify(board)};window.__UNM=${JSON.stringify([{ device_user_id: '999', device_id: 3, device_name: 'Gate ZK', punches: 4, first_at: '2026-10-11T03:00:00Z', last_at: '2026-10-12T12:00:00Z' }])};window.__ERR42={};try{localStorage.setItem('bos_lang','en')}catch(e){};`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC42 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // ---------- today board ----------
  let p = await open('#/attendance');
  ok(await p.locator('#at_rows .card').count() === 4, 'four people on the board');
  let t = await text(p); ok(/Present 2/.test(t) && /Late 1/.test(t) && /Absent 1/.test(t) && /On leave 1/.test(t) && /Waiting approval 1/.test(t), 'summary chips');
  ok(/In 09:40/.test(t) && /40m late/.test(t) && /One punch only/.test(t), 'times shown in Dhaka time with late minutes and the one-punch hint');
  ok(/In 08:55 · Out 20:00/.test(t) && /Overtime 2h/.test(t), 'in / out / overtime');
  await p.click('[data-act=at_recompute]'); await wait(p, 400);
  let c = await calls(p, 'attendance_recompute'); ok(c.length === 1 && c[0].p_from === c[0].p_to && c[0].p_employee === null, 'recompute for the shown day');
  await p.click('[data-act=at_menu][data-v=e1]'); await wait(p, 300);
  let sh = await p.textContent('.sheet'); ok(/Mark \/ correct/.test(sh) && /Approve/.test(sh) && /Reject/.test(sh) && /device down/.test(sh), 'menu of a pending manual day: mark, approve, reject, reason');
  await p.evaluate(() => { window.__ERR42 = { attendance_approve: 'maker_cannot_approve' }; });
  await p.click('.sheet [data-act=at_appr][data-ok="1"]'); await wait(p, 400); ok(/You cannot approve your own entry/.test(await text(p)), 'friendly maker-checker text');
  await p.click('.sheet [data-act=at_appr][data-ok="1"]'); await wait(p, 500);
  c = await calls(p, 'attendance_approve'); ok(c.length === 2 && c[1].p_emp === 'e1' && c[1].p_approve === true, 'approve sent');
  await p.click('[data-act=at_menu][data-v=e2]'); await wait(p, 300); ok(/Approve overtime \(2h \)/.test(await p.textContent('.sheet')), 'overtime approval offered');
  await p.click('.sheet [data-act=at_ot]'); await wait(p, 400); c = await calls(p, 'attendance_ot_approve'); ok(c.length === 1 && c[0].p_emp === 'e2', 'overtime approved');
  await p.click('[data-act=at_menu][data-v=e3]'); await wait(p, 300); await p.click('.sheet [data-act=at_mark]'); await wait(p, 300);
  await p.selectOption('#mk_s', 'present'); await p.fill('#mk_in', '09:05'); await p.fill('#mk_out', '18:00'); await p.click('[data-act=mk_save]'); await wait(p, 300);
  ok(/Write a reason/.test(await text(p)) && (await calls(p, 'attendance_mark')).length === 0, 'reason required before saving');
  await p.fill('#mk_r', 'machine was off'); await p.fill('#mk_ot', '30'); await p.click('[data-act=mk_save]'); await wait(p, 500);
  c = await calls(p, 'attendance_mark'); ok(c.length === 1 && c[0].p_emp === 'e3' && c[0].p_status === 'present' && c[0].p_in === '09:05' && c[0].p_out === '18:00' && c[0].p_ot_minutes === 30 && c[0].p_reason === 'machine was off', 'manual mark sent with times and reason');
  await p.evaluate(() => { window.__ERR42 = { attendance_mark: 'month_locked' }; });
  await p.click('[data-act=at_menu][data-v=e3]'); await wait(p, 300); await p.click('.sheet [data-act=at_mark]'); await wait(p, 300); await p.fill('#mk_r', 'again please'); await p.click('[data-act=mk_save]'); await wait(p, 400);
  ok(/this month is locked/.test(await text(p)), 'friendly month-locked text');
  await p.click('.sheet [data-act=closesheet]').catch(() => {});
  await noOverflow(p, 'board'); await p.screenshot({ path: SP + '/att_board.png', fullPage: true });

  // ---------- month grid ----------
  await p.click('[data-act=at_tab][data-v=month]'); await wait(p, 600);
  ok(await p.locator('#at_grid .c').count() === 30 && await p.locator('#at_grid .h').count() === 7, 'month grid: 7 day heads and 30 days');
  t = await text(p); ok(/Payroll approved - this month is locked/.test(t) && /Absent 1/.test(t), 'month summary and lock shown');
  c = await calls(p, 'attendance_month'); ok(c.length >= 1 && c[0].p_emp === 'e1' && /-01$/.test(c[0].p_month), 'month asked for the first person');
  await noOverflow(p, 'month grid');

  // ---------- import ----------
  await p.click('[data-act=at_tab][data-v=import]'); await wait(p, 700);
  ok(await p.locator('[data-act=im_prev][disabled]').count() === 1, 'preview disabled until a file is read');
  ok(/old\.dat/.test(await text(p)), 'earlier imports listed');
  const dat = '    101\t2026-10-01 08:58:00\t1\t0\t0\t0\n    101\t2026-10-01 18:01:00\t1\t1\t0\t0\n    101\t2026-10-01 18:01:00\t1\t1\t0\t0\n    777\t2026-10-01 09:00:00\t1\t0\t0\t0\nbroken\n';
  await p.setInputFiles('#im_file', { name: 'attlog.dat', mimeType: 'text/plain', buffer: Buffer.from(dat) }); await wait(p, 800);
  ok(/Rows read: 4 · Unreadable 1/.test(await text(p)), 'attlog read: 4 rows, 1 unreadable');
  await p.selectOption('#im_dev', '3'); await p.click('[data-act=im_prev]'); await wait(p, 700);
  c = await calls(p, 'attendance_import'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_device === 3 && c[0].p_rows.length === 4 && c[0].p_rows[0].user_id === '101' && c[0].p_rows[0].ts === '2026-10-01 08:58:00' && c[0].p_rows[0].dir === '0' && c[0].p_file === 'attlog.dat', 'preview is a dry run with the parsed rows');
  t = await p.textContent('#im_prev'); ok(/New 3/.test(t) && /Duplicates 1/.test(t) && /Unknown ids 1/.test(t) && /777/.test(t), 'preview counts shown');
  await p.click('[data-act=im_go]'); await wait(p, 700);
  c = await calls(p, 'attendance_import'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_client && c[1].p_device === 3, 'import sent for real with a client id after the preview');
  ok(await p.locator('#im_batches .card').count() === 2, 'new batch listed');
  await p.click('#im_batches [data-act=im_undo] >> nth=0'); await wait(p, 600);
  c = await calls(p, 'attendance_import_void'); ok(c.length === 1 && c[0].p_batch === 'b2' && c[0].p_reason === 'wrong file loaded', 'undo sends the reason');
  await p.fill('#im_paste', 'AC-No.,Name,Time,State\n101,Karim,01/10/2026 08:55,C/In\n102,Rahim,2026-10-01 09:20:00,C/In\n'); await wait(p, 1200);
  ok(await p.locator('#im_cu').count() === 1 && await p.inputValue('#im_cu') === '0' && await p.inputValue('#im_ct') === '2', 'CSV columns found and offered for mapping');
  await p.click('[data-act=im_prev]'); await wait(p, 600);
  c = await calls(p, 'attendance_import'); ok(c[2].p_rows.length === 2 && c[2].p_rows[0].ts === '2026-10-01 08:55:00' && c[2].p_rows[1].user_id === '102', 'CSV rows normalised (day/month/year)');
  // unmapped
  ok(/ID 999/.test(await text(p)), 'unknown device id listed');
  await p.selectOption('#um_e0', 'e3'); await p.click('[data-act=um_link][data-i="0"]'); await wait(p, 600);
  c = await calls(p, 'attendance_map_user'); ok(c.length === 1 && c[0].p_device_user_id === '999' && c[0].p_emp === 'e3', 'device id linked to the person');
  await noOverflow(p, 'import'); await p.screenshot({ path: SP + '/att_import.png', fullPage: true });

  // ---------- devices ----------
  await p.click('[data-act=at_tab][data-v=devices]'); await wait(p, 500);
  ok(/Gate ZK/.test(await text(p)) && /120 rows/.test(await text(p)), 'device listed with its counter');
  await p.click('[data-act=dv_new]'); await wait(p, 300); await p.fill('#dv_n', 'Factory door'); await p.fill('#dv_s', 'SN22'); await p.click('[data-act=dv_save]'); await wait(p, 600);
  c = await calls(p, 'attendance_device_register'); ok(c.length === 1 && c[0].p_name === 'Factory door' && c[0].p_vendor === 'zkteco' && c[0].p_loc === 1, 'register sent');
  sh = await p.textContent('.sheet'); ok(/shown once/.test(sh) && /abcdef0123456789/.test(sh) && /fingerprint_bridge\.py/.test(sh), 'token shown once with the bridge command');
  await noOverflow(p, 'token sheet');
  await p.click('.sheet [data-act=closesheet]'); await wait(p, 200);
  await p.click('[data-act=dv_menu][data-v="3"]'); await wait(p, 300); await p.click('.sheet [data-act=dv_reset]'); await wait(p, 400);
  ok((await calls(p, 'attendance_device_token_reset')).length === 1 && /ffff0000/.test(await p.textContent('.sheet')), 'token reset shows the new token');

  // ---------- shifts and holidays ----------
  await p.click('.sheet [data-act=closesheet]'); await p.click('[data-act=at_tab][data-v=setup]'); await wait(p, 500);
  t = await text(p); ok(/General shift/.test(t) && /09:00–18:00/.test(t) && /Victory Day/.test(t), 'shift and holiday listed');
  await p.click('[data-act=sh_edit][data-v=""]'); await wait(p, 300); await p.fill('#sh_bn', 'রাত'); await p.fill('#sh_st', '22:00'); await p.fill('#sh_et', '06:00'); await p.click('[data-act=sh_save]'); await wait(p, 500);
  c = await calls(p, 'shift_save'); ok(c.length === 1 && c[0].p_id === null && c[0].p_data.start_time === '22:00' && c[0].p_data.end_time === '06:00' && c[0].p_data.location_id === 1 && c[0].p_data.break_min === 60, 'new shift sent');
  await p.click('[data-act=sh_assign]'); await wait(p, 300); await p.selectOption('#as_e', 'e2'); await p.uncheck('.as_wd[value="5"]'); await p.check('.as_off[value="5"]'); await p.click('[data-act=shf_save]'); await wait(p, 400);
  c = await calls(p, 'shift_assign'); ok(c.length === 1 && c[0].p_emp === 'e2' && c[0].p_weekdays === 127 - 32 && c[0].p_off_mask === 32 && c[0].p_client, 'shift assignment with weekdays and weekly off');
  await p.click('[data-act=hol_add]'); await wait(p, 300); await p.fill('#ho_d', '2026-12-25'); await p.fill('#ho_bn', 'বড়দিন'); await p.click('[data-act=ho_save]'); await wait(p, 500);
  c = await calls(p, 'holiday_save'); ok(c.length === 1 && c[0].p_day === '2026-12-25' && c[0].p_loc === 1 && c[0].p_paid === true, 'holiday saved for the place');
  await noOverflow(p, 'setup');

  // ---------- leave ----------
  p = await open('#/leave');
  ok(await p.locator('#lv_list .card').count() === 2, 'requests of this place only');
  t = await text(p); ok(/Rahim/.test(t) && /Pending/.test(t) && /2026-10-20 – 2026-10-21/.test(t) && /wedding/.test(t), 'request details');
  await p.click('[data-act=lv_dec][data-ok="1"]'); await wait(p, 500); c = await calls(p, 'leave_decide'); ok(c.length === 1 && c[0].p_id === 11 && c[0].p_approve === true, 'approve leave');
  await p.click('[data-act=lv_new]'); await wait(p, 300); await p.selectOption('#lr_e', 'e3'); await p.fill('#lr_f', '2026-10-25'); await p.fill('#lr_to', '2026-10-26'); await p.fill('#lr_r', 'fever');
  await p.evaluate(() => { window.__ERR42 = { leave_request_save: 'leave_balance_short' }; }); await p.click('[data-act=lr_save]'); await wait(p, 400);
  ok(/Not enough leave left/.test(await text(p)), 'friendly balance text');
  await p.click('[data-act=lr_save]'); await wait(p, 500); c = await calls(p, 'leave_request_save');
  ok(c.length === 2 && c[1].p_emp === 'e3' && c[1].p_type === 'casual' && c[1].p_from === '2026-10-25' && c[1].p_to === '2026-10-26' && c[1].p_client && c[1].p_client === c[0].p_client, 'leave request sent (same client key on retry)');
  await p.click('[data-act=lv_cancel] >> nth=0'); await wait(p, 400); ok((await calls(p, 'leave_cancel')).length === 1, 'cancel sends a reason');
  await p.click('[data-act=lv_tab][data-v=bal]'); await wait(p, 500);
  t = await p.textContent('#lv_bal'); ok(/Casual leave/.test(t) && /Per year 10/.test(t) && /Taken 3/.test(t) && /Left 7/.test(t) && /no limit/.test(t), 'balances');
  await noOverflow(p, 'leave');

  // ---------- staff without rights + app check-in ----------
  p = await open('#/attendance', { staff: true, appPunch: true });
  ok(await p.locator('[data-act=at_recompute]').count() === 0, 'no recompute for staff');
  await p.click('[data-act=at_menu][data-v=e1]'); await wait(p, 300); ok(await p.locator('.sheet [data-act=at_mark]').count() === 0 && await p.locator('.sheet [data-act=at_appr]').count() === 0, 'no mark / approve for staff');
  await p.click('.sheet [data-act=closesheet]');
  await p.click('[data-act=at_punch][data-v=in]'); await wait(p, 400); c = await calls(p, 'attendance_app_punch'); ok(c.length === 1 && c[0].p_dir === 'in', 'app check-in when the rule is on');
  await p.click('[data-act=at_tab][data-v=import]'); await wait(p, 400); ok(/Not allowed/.test(await text(p)) && (await calls(p, 'attendance_unmapped')).length === 0, 'import closed to staff (no call made)');
  p = await open('#/attendance'); ok(await p.locator('[data-act=at_punch]').count() === 0, 'no check-in button while the rule is off');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
