// Module B2 web: payroll month flow Preview (trial) -> Create -> Adjust -> Approve -> Pay, calculation trail, payslip print, CSV export,
// month summary by place, advances, festival bonus, final settlement, salary privacy (no salary right = nothing is even fetched), friendly errors.
// Run: timeout 250 node payroll_test.js <abs tests/web dir>
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
    if (ext === '.html' && !/payroll\.js/.test(String(b))) b = Buffer.from(String(b).replace('</body>', '<script src="attendance.js"></script><script src="payroll.js"></script></body>'));
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

// the worked example of supabase/phase42_test.sql (basic 20000, 2 absent, 3 lates, 10 OT hours, Eid bonus, advance 1500 -> net 27750)
const LINE1 = { employee_id: 'e1', employee_no: 'E-0001', name: 'করিম', name_en: 'TestF', location_id: 1, pay_basis: 'monthly', basic: 20000, basic_amount: 20000, allowances: [], allowance_total: 0, structure_deductions: [], structure_deduction_total: 0,
  days_in_month: 30, employed_days: 30, paid_days: 28, absent_days: 2, half_days: 0, unpaid_leave_days: 0, paid_leave_days: 1, off_days: 4, holiday_days: 0, late_count: 3, late_minutes: 90, late_deduction: 666.67, absent_deduction: 1333.33,
  unpaid_deduction: 0, not_employed_deduction: 0, ot_minutes: 600, ot_amount: 1250, bonus: [{ name: 'Eid', amount: 10000, auto: true }], advance_recovery: 1500, advances: [{ advance_id: 1, amount: 1500 }], other_deductions: [], adjustments: [],
  gross: 31250, deductions: 3500, round_adj: 0, net: 27750, warnings: ['unapproved_days:1'],
  calc_detail: { trail: [{ k: 'basic', f: 'monthly 20000', v: 20000 }, { k: 'day_rate', f: '20000 / 30', v: 666.6667 }, { k: 'absent', f: '2 × 666.6667', v: -1333.33 }, { k: 'late', f: '3 / 3 = 1 × 666.6667', v: -666.67 }, { k: 'ot', f: '10 h × 83.3333 × 1.5', v: 1250 }, { k: 'advance', f: '1', v: -1500 }] } };
const LINE2 = { employee_id: 'e8', employee_no: 'E-0008', name: 'নতুন', name_en: 'Newcomer', location_id: 1, basic: 30000, basic_amount: 30000, allowances: [{ name: 'House rent', amount: 7500 }], allowance_total: 7500, days_in_month: 30, employed_days: 15, paid_days: 15,
  absent_days: 0, late_count: 0, not_employed_deduction: 15000, ot_minutes: 0, ot_amount: 0, bonus: [], advance_recovery: 0, other_deductions: [], adjustments: [], structure_deductions: [], gross: 37500, deductions: 15000, round_adj: 0, net: 22500, warnings: ['days_not_computed:15'], calc_detail: { trail: [] } };
const LINE3 = { employee_id: 'e3', employee_no: 'E-0003', name: 'গার্ড', name_en: 'Guard', location_id: 1, days_in_month: 30, employed_days: 30, basic: 0, basic_amount: 0, gross: 0, deductions: 0, net: 0, warnings: ['no_pay_structure'], skip: true };

const EXTRA42P = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const from = c.from; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 c.from = (t) => { (window.__TB = window.__TB || []).push(t); return from(t); };
 c.rpc = async (fn, args) => {
  (window.__AC42 = window.__AC42 || []).push([fn, clone(args || {})]);
  const E = window.__ERR42 && window.__ERR42[fn]; if (E) { delete window.__ERR42[fn]; return { data: null, error: { message: E, code: 'P0001' } }; }
  const L1 = ${JSON.stringify(LINE1)}, L2 = ${JSON.stringify(LINE2)}, L3 = ${JSON.stringify(LINE3)};
  if (fn === 'payroll_preview') return { data: { dry: true, month: args.p_month, location_id: args.p_loc, lines: [L1, L2, L3], totals: { people: 2, net: 50250 } }, error: null };
  if (fn === 'payroll_create') { T.payroll_runs.push({ id: 5, month: args.p_month, location_id: args.p_loc, status: 'draft' }); [L1, L2].forEach((l, i) => T.payroll_lines.push(Object.assign({ id: 100 + i, run_id: 5, active: true, payment_status: 'unpaid', paid_amount: 0 }, clone(l))));
    return { data: { id: 5, status: 'draft', lines: 2, net: 50250 }, error: null }; }
  if (fn === 'payroll_refresh') return { data: { id: 5, refreshed_lines: 2 }, error: null };
  if (fn === 'payroll_line_adjust') { const l = T.payroll_lines.find((x) => x.id === args.p_line); if (args.p_kind === 'bonus' && args.p_remove == null) { l.bonus.push({ name: args.p_name, amount: args.p_amount, reason: args.p_reason }); l.net += args.p_amount; l.gross += args.p_amount; } return { data: l, error: null }; }
  if (fn === 'payroll_approve') { T.payroll_runs[0].status = 'approved'; return { data: { id: 5, status: 'approved' }, error: null }; }
  if (fn === 'payroll_pay') { T.payroll_lines.forEach((l) => { if (!args.p_lines || args.p_lines.includes(l.id)) { const amt = args.p_amount || (l.net - l.paid_amount); l.paid_amount += amt; l.payment_status = l.paid_amount >= l.net ? 'paid' : 'partly'; } });
    if (T.payroll_lines.every((l) => l.payment_status === 'paid')) T.payroll_runs[0].status = 'paid'; return { data: { id: 5, status: T.payroll_runs[0].status, payments: 2 }, error: null }; }
  if (fn === 'payroll_void') { T.payroll_runs[0].status = 'void'; return { data: { status: 'void' }, error: null }; }
  if (fn === 'staff_advance_add') { T.employee_advances.unshift({ id: 9, employee_id: args.p_emp, adv_date: args.p_date, amount: args.p_amount, instalment: args.p_instalment, mode: args.p_mode, recover_from: args.p_recover_from, note: args.p_note, status: 'active' }); return { data: { id: 9 }, error: null }; }
  if (fn === 'staff_advance_void') { T.employee_advances.find((x) => x.id === args.p_id).status = 'void'; return { data: { status: 'void' }, error: null }; }
  if (fn === 'payroll_bonus_event_save') { if (args.p_active) T.payroll_bonus_events.push({ id: 3, month: args.p_month, name: args.p_name, location_id: args.p_loc, active: true }); return { data: { id: 3 }, error: null }; }
  if (fn === 'payroll_settlement_preview') return { data: { dry: true, line: Object.assign({}, L2, { employed_days: 10, net: 3000, warnings: [] }), advances_left: 500 }, error: null };
  return rpc(fn, args);
 }; return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept('typed by mistake')); await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA42P }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const T = data.tables;
    T.employees = [['e1', 'E-0001', 'করিম', 'TestF', 1], ['e8', 'E-0008', 'নতুন', 'Newcomer', 1], ['e2', 'E-0002', 'রহিম', 'TestK', 2]].map((r) => ({ id: r[0], employee_no: r[1], full_name_bn: r[2], full_name_en: r[3], primary_location_id: r[4], status: 'active', joining_date: '2025-01-01' }));
    T.payroll_runs = o.runs || []; T.payroll_lines = o.lines || []; T.payroll_bonus_events = [];
    T.employee_advances = [{ id: 1, employee_id: 'e1', adv_date: '2026-09-01', amount: 3000, instalment: 1500, mode: 'cash', recover_from: '2026-09-01', note: 'phone', status: 'active' }];
    T.employee_advance_recoveries = [{ advance_id: 1, amount: 1500, status: 'active' }];
    const m0 = o.staff ? { grants: [], ctx: { is_owner: false, roles: ['showroom_manager'], locations: [1] } } : o.acct ? { grants: ['salary_view', 'payroll_manage'], ctx: { is_owner: false, roles: ['salesperson'], locations: [1] } } : {};
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(m0)};window.__OWNER=${o.staff || o.acct ? 'false' : 'true'};window.__ERR42={};try{localStorage.setItem('bos_lang','en')}catch(e){};
      window.print=()=>{window.__PRINTED=(document.querySelector('#pr_print')||{}).innerText||''};const cou=URL.createObjectURL;URL.createObjectURL=(b)=>{if(b&&b.text)b.text().then((t)=>{window.__CSV=t});return cou.call(URL,b)};`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC42 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => { if (process.env.DBG) console.log(m, await p.evaluate(() => [...document.querySelectorAll('body *')].filter((e) => e.getBoundingClientRect().right > window.innerWidth + 1).slice(0, 5).map((e) => e.tagName + '.' + e.className + '#' + e.id + ' ' + Math.round(e.getBoundingClientRect().right)).join(' | '))); return ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m); };

  // ---------- preview -> create -> adjust -> approve -> pay ----------
  let p = await open('#/payroll');
  const month = await p.inputValue('#pr_month');
  const exp = (() => { const d = new Date(new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }) + 'T00:00:00Z'); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - 1); return d.toISOString().slice(0, 7); })();
  ok(month === exp, 'default month = last month (' + month + ')');
  ok(await p.inputValue('#pr_loc') === '1', 'first place chosen');
  let t = await text(p); ok(/No payroll for this month yet/.test(t) && /1 Preview/.test(t), 'no run yet, steps shown');
  await p.click('[data-act=pr_preview]'); await wait(p, 600);
  let c = await calls(p, 'payroll_preview'); ok(c.length === 1 && c[0].p_month === month + '-01' && c[0].p_loc === 1, 'preview for the month and place');
  t = await text(p); ok(/Trial: nothing was saved/.test(t) && /27,750/.test(t) && /22,500/.test(t) && /2 people/.test(t) && /50,250/.test(t), 'trial lines and totals (skipped person not counted)');
  ok(/No pay structure - left out/.test(t) && /15 days without attendance/.test(t) && /1 manual days waiting approval/.test(t), 'warnings in plain words');
  ok((await calls(p, 'payroll_create')).length === 0, 'preview created nothing');
  await p.click('[data-act=pr_line][data-i="0"]'); await wait(p, 300);
  let sh = await p.textContent('.sheet'); ok(/One day's pay/.test(sh) && /20000 \/ 30/.test(sh) && /Absent/.test(sh) && /− ৳ 1,333.33/.test(sh) && /10 h × 83.3333 × 1.5/.test(sh) && /Bonus: Eid/.test(sh) && /Net pay/.test(sh), 'calculation trail');
  await p.click('.sheet [data-act=closesheet]'); await noOverflow(p, 'preview'); await p.screenshot({ path: SP + '/pay_preview.png', fullPage: true });
  await p.click('[data-act=pr_create]'); await wait(p, 700);
  c = await calls(p, 'payroll_create'); ok(c.length === 1 && c[0].p_month === month + '-01' && c[0].p_loc === 1 && c[0].p_client, 'create with a client id');
  t = await text(p); ok(/Draft/.test(t) && /3 Adjust/.test(t) && await p.locator('#pr_lines .card').count() === 2, 'draft run with 2 lines');
  await p.click('[data-act=pr_line][data-i="0"]'); await wait(p, 300); await p.click('.sheet [data-act=ln_adj][data-k=bonus]'); await wait(p, 300);
  await p.fill('#aj_n', 'Extra'); await p.fill('#aj_a', '500'); await p.click('[data-act=aj_save]'); await wait(p, 300);
  ok(/Write a reason/.test(await text(p)) && (await calls(p, 'payroll_line_adjust')).length === 0, 'adjustment needs a reason');
  await p.fill('#aj_r', 'good month'); await p.click('[data-act=aj_save]'); await wait(p, 600);
  c = await calls(p, 'payroll_line_adjust'); ok(c.length === 1 && c[0].p_line === 100 && c[0].p_kind === 'bonus' && c[0].p_amount === 500 && c[0].p_reason === 'good month', 'bonus added with a reason');
  ok(/28,250/.test(await text(p)), 'new net shown');
  await p.click('[data-act=pr_line][data-i="0"]'); await wait(p, 300); ok(await p.locator('.sheet [data-act=ln_rm]').count() === 1, 'manual item can be removed, auto Eid bonus cannot');
  await p.click('.sheet [data-act=closesheet]');
  await p.click('[data-act=pr_refresh]'); await wait(p, 500); ok((await calls(p, 'payroll_refresh')).length === 1, 'recalculate from attendance');
  await p.evaluate(() => { window.__ERR42 = { payroll_approve: 'negative_net' }; }); await p.click('[data-act=pr_approve]'); await wait(p, 500); ok(/Net pay is negative!/.test(await text(p)), 'friendly approve error');
  await p.click('[data-act=pr_approve]'); await wait(p, 600); ok((await calls(p, 'payroll_approve')).length === 2 && /Approved/.test(await text(p)) && /5 Pay/.test(await text(p)), 'approved');
  ok(await p.locator('[data-act=pr_refresh]').count() === 0, 'no recalculation after approval');
  await p.click('[data-act=pr_line][data-i="1"]'); await wait(p, 300); await p.click('.sheet [data-act=ln_pay]'); await wait(p, 300);
  ok(await p.inputValue('#py_a') === '22500', 'one-line pay prefilled with the amount due');
  await p.fill('#py_a', '10000'); await p.selectOption('#py_m', 'bank'); await p.fill('#py_r', 'TT-9'); await p.click('[data-act=py_go]'); await wait(p, 600);
  c = await calls(p, 'payroll_pay'); ok(c.length === 1 && c[0].p_run === 5 && JSON.stringify(c[0].p_lines) === '[101]' && c[0].p_amount === 10000 && c[0].p_mode === 'bank' && c[0].p_ref === 'TT-9' && c[0].p_client, 'part payment of one line');
  ok(/Part paid/.test(await text(p)), 'line shows part paid');
  await p.click('[data-act=pr_payall]'); await wait(p, 300); await p.click('[data-act=py_go]'); await wait(p, 600);
  c = await calls(p, 'payroll_pay'); ok(c.length === 2 && c[1].p_lines === null && c[1].p_mode === 'cash' && c[1].p_amount === null && c[1].p_client !== c[0].p_client, 'pay everyone unpaid in cash');
  ok(/Paid/.test(await text(p)) && await p.locator('[data-act=pr_payall]').count() === 0, 'run paid');
  await p.click('[data-act=pr_line][data-i="0"]'); await wait(p, 300); await p.click('.sheet [data-act=ln_slip]'); await wait(p, 300);
  let pr = await p.evaluate(() => window.__PRINTED || ''); ok(/Payslip/.test(pr) && /TestF/.test(pr) && /28,250/.test(pr) && /Advance recovery/.test(pr) && /Received by/.test(pr), 'payslip printed');
  await p.click('.sheet [data-act=closesheet]'); await p.click('[data-act=pr_csv]'); await wait(p, 500);
  const csv = await p.evaluate(() => window.__CSV || ''); if (process.env.DBG) console.log(JSON.stringify(csv)); ok(/^\uFEFF?employee_no,name,/.test(csv) && /E-0001,করিম/.test(csv) && csv.trim().split('\n').length === 3, 'CSV export with a header and 2 lines');
  await noOverflow(p, 'run'); await p.screenshot({ path: SP + '/pay_run.png', fullPage: true });

  // ---------- summary by place (owner) ----------
  const runs = [{ id: 5, month: exp + '-01', location_id: 1, status: 'paid' }, { id: 6, month: exp + '-01', location_id: 2, status: 'draft' }];
  const lines = [Object.assign({ id: 100, run_id: 5, active: true, payment_status: 'paid', paid_amount: 27750 }, LINE1), Object.assign({ id: 200, run_id: 6, active: true, payment_status: 'unpaid', paid_amount: 0 }, LINE2, { location_id: 2 })];
  p = await open('#/payroll', { runs, lines });
  await p.selectOption('#pr_loc', ''); await wait(p, 600);
  t = await text(p); if (process.env.DBG) console.log(t); ok(/Islamia Main/.test(t) && /2nd Branch/.test(t) && /Paid ৳ 27,750/.test(t) && /Net pay ৳ 50,250/.test(t) && /Draft/.test(t), 'month summary by place');
  await noOverflow(p, 'summary');

  // ---------- advances, bonus, settlement ----------
  p = await open('#/payroll', { acct: true });
  await p.click('[data-act=pr_tab][data-v=adv]'); await wait(p, 600);
  t = await text(p); ok(/TestF/.test(t) && /Owed ৳ 1,500/.test(t), 'advance with what is still owed');
  await p.click('[data-act=adv_new]'); await wait(p, 300); await p.selectOption('#av_e', 'e8'); await p.fill('#av_a', '2000'); await p.fill('#av_i', '500'); await p.click('[data-act=av_save]'); await wait(p, 600);
  c = await calls(p, 'staff_advance_add'); ok(c.length === 1 && c[0].p_emp === 'e8' && c[0].p_amount === 2000 && c[0].p_instalment === 500 && c[0].p_mode === 'cash' && /-01$/.test(c[0].p_recover_from) && c[0].p_client, 'advance given with instalments');
  await p.click('[data-act=pr_tab][data-v=more]'); await wait(p, 600);
  await p.click('[data-act=fb_save]'); await wait(p, 500); c = await calls(p, 'payroll_bonus_event_save'); ok(c.length === 1 && c[0].p_name === 'Eid' && c[0].p_loc === 1 && c[0].p_active === true, 'festival bonus of the month (place of a non-owner)');
  ok(/Eid/.test(await text(p)), 'bonus event listed');
  await p.selectOption('#st_e', 'e8'); await p.click('[data-act=st_show]'); await wait(p, 500);
  c = await calls(p, 'payroll_settlement_preview'); ok(c.length === 1 && c[0].p_emp === 'e8', 'settlement preview asked');
  t = await p.textContent('#st_out'); ok(/Trial/.test(t) && /3,000/.test(t) && /৳ 500/.test(t), 'settlement net and advance left');
  await noOverflow(p, 'more');

  // ---------- no salary right: nothing fetched ----------
  p = await open('#/payroll', { staff: true });
  ok(/You are not allowed to see pay/.test(await text(p)), 'privacy message');
  ok((await calls(p, 'payroll_preview')).length === 0 && !(await p.evaluate(() => (window.__TB || []).includes('payroll_runs') || (window.__TB || []).includes('payroll_lines'))), 'no payroll query at all without the right');
  await p.click('[data-act=pr_tab][data-v=adv]'); await wait(p, 400); ok(!(await p.evaluate(() => (window.__TB || []).includes('employee_advances'))), 'no advance query without the right');
  ok(await p.locator('#pr_loc option[value=""]').count() === 0, 'no company summary for a non-owner');
  // friendly create error
  p = await open('#/payroll'); await p.click('[data-act=pr_preview]'); await wait(p, 500); await p.evaluate(() => { window.__ERR42 = { payroll_create: 'run_exists' }; }); await p.click('[data-act=pr_create]'); await wait(p, 500);
  ok(/already exists/.test(await text(p)), 'friendly run-exists text');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
