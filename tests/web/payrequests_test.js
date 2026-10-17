// Pay requests web piece (R1): #/payrequest (staff), #/partyrequest (supplier payment requests), #/payapprovals (the chosen approver: waiting, due, later, all; approve on a date, reject, pay),
// #/payreqsettings (owner: switches, approver, limits), registry records in ia.js, 360px width, no console errors. The server is mocked: the screens are only a UI over phase 120
// (the decisions are made and tested in SQL, supabase/phase120_test.sql).
// Run: node payrequests_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8487, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__PR = window.__PR || { calls: [], fn: {}, err: {} };
 c.rpc = async (fn, args) => {
  if (!/^(pay_request_|set_rule$|supplier_pick$)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.err && R.err[fn]) return { data: null, error: { message: R.err[fn], code: 'P0001' } };
  if (fn === 'set_rule') return { data: null, error: null };
  let f = R.fn && R.fn[fn];
  if (fn === 'pay_request_list') f = (R.fn.pay_request_list || {})[(args || {}).p_scope] || { rows: [] };
  if (f !== undefined) return { data: f, error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;
const RULE = (key, kind, def, o = {}) => Object.assign({ key, module: 'people', kind, value: null, default_value: def, choices: null, unit: null, min_value: null, max_value: null, label_en: key, hint_en: '' }, o);
const RULES = [RULE('pay_requests_on', 'switch', false), RULE('pay_requests_required', 'switch', false), RULE('pay_requests_required_kinds', 'choice', 'both', { choices: ['both', 'advance', 'salary'] }),
  RULE('pay_request_exception_mode', 'choice', 'reason', { choices: ['reason', 'owner', 'never'] }), RULE('pay_request_max_per_month', 'number', null), RULE('pay_request_advance_ceiling', 'number', null),
  RULE('party_requests_on', 'switch', false), RULE('party_requests_required', 'switch', false)];
const PEOPLE = [{ id: '00000000-0000-0000-0000-0000000000a1', full_name: 'test_cashier', staff_id: 'tc1', status: 'active' }, { id: '00000000-0000-0000-0000-0000000000a2', full_name: 'test_approver', staff_id: 'ta1', status: 'active' }];
const ST = (o) => Object.assign({ staff_on: true, party_on: true, staff_required: false, required_kinds: 'both', party_required: false, exception_mode: 'reason', max_per_month: null, advance_ceiling: null, my_employee: 'e1', is_owner: false,
  approver_staff: false, approver_party: false, can_on_behalf: false, approver: { staff: { mode: 'owner', role: null, user: null }, party: { mode: 'owner', role: null, user: null }, party_same: true }, gate: { advance: true, salary: true, supplier: true }, counts: { inbox: 1, due: 1, mine_open: 2 }, today: '2026-10-16' }, o || {});
const ev = (a, n) => ({ at: '2026-10-1' + n + 'T05:00:00Z', action: a, by: 'ts1', note: null, data: null });
const MINE = { rows: [
  { id: 1, kind: 'advance', status: 'received', amount: 3000, approved_amount: null, paid_amount: 0, reason: 'test: rent', needed_by: '2026-10-19', pay_date: null, date_changed: false, requested_at: '2026-10-16T05:00:00Z', mine: true, can_cancel: true, can_decide: false, can_pay: false, events: [ev('received', 6)] },
  { id: 2, kind: 'advance', status: 'approved', amount: 2000, approved_amount: 1500, paid_amount: 0, reason: 'test: school', needed_by: '2026-10-18', pay_date: '2026-10-22', date_changed: true, decision_note: 'test: next week', requested_at: '2026-10-15T05:00:00Z', mine: true, can_cancel: true, events: [ev('received', 5), ev('approved', 6)] },
  { id: 3, kind: 'salary', status: 'rejected', amount: 500, reason: 'test: small', needed_by: '2026-10-17', decision_note: 'test: not this month', requested_at: '2026-10-14T05:00:00Z', mine: true, events: [] },
  { id: 4, kind: 'advance', status: 'paid', amount: 700, approved_amount: 700, paid_amount: 700, paid_at: '2026-10-13T08:00:00Z', reason: 'test: paid', needed_by: '2026-10-13', pay_date: '2026-10-13', date_changed: false, requested_at: '2026-10-10T05:00:00Z', mine: true, events: [] },
  { id: 5, kind: 'advance', status: 'cancelled', amount: 100, reason: 'test: cancelled', needed_by: '2026-10-13', requested_at: '2026-10-09T05:00:00Z', mine: true, events: [] } ] };
const PARTY = { rows: [{ id: 21, kind: 'supplier', status: 'received', amount: 4000, reason: 'test: march bill', needed_by: '2026-10-19', subject: 'test_supplier', bill_ref: 'BILL-1', requested_at: '2026-10-16T05:00:00Z', mine: true, can_cancel: true, events: [] }] };
const INBOX = { rows: [
  { id: 31, kind: 'advance', status: 'received', amount: 3000, reason: 'test: rent', needed_by: '2026-10-19', subject: 'test_emp_1', requested_at: '2026-10-16T05:00:00Z', location_id: 1, paid_amount: 0, can_decide: true, can_pay: false, events: [] },
  { id: 32, kind: 'supplier', status: 'received', amount: 900, reason: 'test: supplier', needed_by: '2026-10-19', subject: 'test_supplier', asked_by_name: 'test contact', on_behalf: true, requested_at: '2026-10-16T05:00:00Z', location_id: 1, paid_amount: 0, can_decide: false, can_pay: false, mine: true, events: [] } ] };
const DUE = { rows: [{ id: 41, kind: 'salary', status: 'approved', amount: 2500, approved_amount: 2500, paid_amount: 0, reason: 'test: salary part', needed_by: '2026-10-14', pay_date: '2026-10-15', overdue: true, date_changed: true, subject: 'test_emp_2', requested_at: '2026-10-12T05:00:00Z', location_id: 1, can_decide: true, can_pay: true, events: [] }] };
const FN = { pay_request_state: ST(), pay_request_list: { mine: MINE, inbox: INBOX, due: DUE, upcoming: { rows: [] }, all: { rows: [].concat(INBOX.rows, DUE.rows) } }, supplier_pick: [{ id: 's1', name: 'test_supplier', type_code: 'x' }],
  pay_request_submit: { id: 99, status: 'received' }, pay_request_cancel: { id: 1, status: 'cancelled' }, pay_request_decide: { id: 31, status: 'approved' }, pay_request_pay: { request_id: 41, status: 'paid' }, pay_request_approver_set: { mode: 'role' } };
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } else log('ok:', m); };
  async function page(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.setDefaultTimeout(8000); p.on('pageerror', (e) => errors.push('pageerror: ' + e.message + ' @ ' + (e.stack||'').split('\n').slice(0,3).join(' | '))); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept(o.prompt === undefined ? 'test reason' : o.prompt));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); data.tables.rules = JSON.parse(JSON.stringify(RULES)); data.tables.profiles = (data.tables.profiles || []).concat(PEOPLE); data.tables.roles = [{ code: 'purchasing', name_en: 'Purchasing', active: true, sort: 1 }, { code: 'owner', name_en: 'Owner', active: true, sort: 0 }];
    data.tables.employees = [{ id: 'e1', full_name_en: 'test_emp_1', full_name_bn: 'test_emp_1', employee_no: 'T1', status: 'active' }];
    const fn = Object.assign({}, FN, o.fn || {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === true ? 'true' : 'false'};window.__PR={calls:[],err:${JSON.stringify(o.err || {})},fn:${JSON.stringify(fn)}};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, f) => p.evaluate((x) => (window.__PR.calls || []).filter((c) => c[0] === x).map((c) => c[1]), f);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal overflow: ' + m);

  log('section: staff page, switched off');
  let p = await page('#/payrequest', { fn: { pay_request_state: ST({ staff_on: false }) } });
  let t = await text(p);
  ok(/not switched on/.test(t) && await p.locator('#prq_form').count() === 0, 'off: a notice, no form');
  ok(await p.locator('a[href="#/payreqsettings"]').count() === 0, 'a non-owner gets no link to the settings');
  p = await page('#/payrequest', { owner: true, fn: { pay_request_state: ST({ staff_on: false, is_owner: true }) } });
  ok(await p.locator('a[href="#/payreqsettings"]').count() === 1, 'the owner is pointed to the settings page');

  log('section: staff page, on');
  p = await page('#/payrequest');
  t = await text(p);
  ok(/Ask for salary or advance/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('#prq_form').count() === 1 && await p.locator('#prq_emp').count() === 0, 'form shown; the "for someone else" field only appears for a payroll manager');
  ok(await p.locator('.prq-card').count() === 5, 'five requests listed: ' + await p.locator('.prq-card').count());
  ok(/Received, waiting for a decision/.test(t), 'status: received');
  ok(await p.locator('.prq-card[data-id="2"] .prq-changed').count() === 1 && /Pay date 2026-10-22/.test(await p.locator('.prq-card[data-id="2"]').innerText()) && /You asked for 2026-10-18/.test(await p.locator('.prq-card[data-id="2"]').innerText()), 'approved on another date: the pay date and the date he asked for are both shown');
  ok(/Approved amount 1,500/.test(await p.locator('.prq-card[data-id="2"]').innerText()), 'approved for a smaller amount: shown');
  ok(/Rejected/.test(await p.locator('.prq-card[data-id="3"]').innerText()) && /not this month/.test(await p.locator('.prq-card[data-id="3"]').innerText()), 'rejected: the reason is shown');
  ok(/Paid/.test(await p.locator('.prq-card[data-id="4"]').innerText()) && /2026-10-13/.test(await p.locator('.prq-card[data-id="4"]').innerText()), 'paid: the date is shown');
  ok(await p.locator('.prq-card[data-id="1"] [data-act=prq_cancel]').count() === 1 && await p.locator('.prq-card[data-id="4"] [data-act=prq_cancel]').count() === 0, 'Cancel only where the server says can_cancel');
  ok(await p.locator('.prq-card[data-id="2"] .prq-hist').count() === 1, 'a history (timeline) is available on a request with events');
  await noOverflow(p, 'staff page'); await p.screenshot({ path: SP + '/prq_staff.png', fullPage: true });
  await p.click('[data-act=prq_send]'); await wait(p, 300);
  ok((await calls(p, 'pay_request_submit')).length === 0, 'an empty form sends nothing');
  await p.fill('#prq_amt', '3,000'); await p.fill('#prq_reason', 'ab'); await p.click('[data-act=prq_send]'); await wait(p, 300);
  ok((await calls(p, 'pay_request_submit')).length === 0, 'a reason shorter than 3 characters sends nothing');
  await p.fill('#prq_reason', 'test: house rent'); await p.fill('#prq_date', '2026-10-20'); await p.click('[data-act=prq_send]'); await wait(p, 600);
  let sb = await calls(p, 'pay_request_submit');
  ok(sb.length === 1 && sb[0].p_kind === 'advance' && sb[0].p_amount === 3000 && sb[0].p_reason === 'test: house rent' && sb[0].p_needed_by === '2026-10-20' && /^[0-9a-f-]{36}$/.test(sb[0].p_client), 'submit: kind, amount (digits and comma cleaned), reason, date, a client id for retries: ' + JSON.stringify(sb[0]));
  await p.selectOption('#prq_kind', 'salary'); await p.fill('#prq_amt', '500'); await p.fill('#prq_reason', 'test: salary part'); await p.click('[data-act=prq_send]'); await wait(p, 600);
  sb = await calls(p, 'pay_request_submit');
  ok(sb.length === 2 && sb[1].p_kind === 'salary' && sb[1].p_client !== sb[0].p_client, 'a second request uses a new client id');
  await p.click('.prq-card[data-id="1"] [data-act=prq_cancel]'); await wait(p, 500);
  const cn = await calls(p, 'pay_request_cancel');
  ok(cn.length === 1 && cn[0].p_id === 1 && cn[0].p_note === 'test reason', 'cancel asks for a reason and sends it');
  p = await page('#/payrequest', { err: { pay_request_submit: 'monthly_request_limit' } });
  await p.fill('#prq_amt', '100'); await p.fill('#prq_reason', 'test: one more'); await p.click('[data-act=prq_send]'); await wait(p, 500);
  ok(/limit of requests for this month is reached/.test(await p.locator('#toast').innerText()), 'a server refusal is shown in plain words');
  p = await page('#/payrequest', { fn: { pay_request_state: ST({ can_on_behalf: true }) } });
  ok(await p.locator('#prq_emp').count() === 1, 'a payroll manager sees "For" (enter a request for a colleague)');
  await p.selectOption('#prq_emp', 'e1'); await p.fill('#prq_amt', '50'); await p.fill('#prq_reason', 'test: for colleague'); await p.click('[data-act=prq_send]'); await wait(p, 500);
  ok((await calls(p, 'pay_request_submit')).some((a) => a.p_employee === 'e1'), 'the colleague is sent as p_employee');

  log('section: supplier payment request');
  p = await page('#/partyrequest', { fn: { pay_request_list: { mine: PARTY } } });
  t = await text(p);
  ok(/Ask to pay a supplier/.test(await p.locator('h1').textContent()) && await p.locator('#prq_sup option').count() === 2, 'title and supplier list');
  ok(await p.locator('.prq-card').count() === 1 && /BILL-1/.test(t), 'own supplier requests listed with the bill reference');
  await p.click('[data-act=prq_sendp]'); await wait(p, 300);
  ok((await calls(p, 'pay_request_submit')).length === 0, 'no supplier chosen: nothing sent');
  await p.selectOption('#prq_sup', 's1'); await p.fill('#prq_amt', '4000'); await p.fill('#prq_bill', 'BILL-2'); await p.fill('#prq_reason', 'test: march bill'); await p.fill('#prq_by', 'test contact'); await p.click('[data-act=prq_sendp]'); await wait(p, 600);
  sb = await calls(p, 'pay_request_submit');
  ok(sb.length === 1 && sb[0].p_kind === 'supplier' && sb[0].p_supplier === 's1' && sb[0].p_amount === 4000 && sb[0].p_bill_ref === 'BILL-2' && sb[0].p_asked_by === 'test contact', 'supplier request: supplier, amount, bill reference and the supplier-side contact: ' + JSON.stringify(sb[0]));
  await noOverflow(p, 'party page'); await p.screenshot({ path: SP + '/prq_party.png', fullPage: true });
  p = await page('#/partyrequest', { fn: { pay_request_state: ST({ party_on: false }) } });
  ok(await p.locator('#prq_form').count() === 0 && /not switched on/.test(await text(p)), 'party requests off: a notice');

  log('section: approver page');
  p = await page('#/payapprovals', { fn: { pay_request_state: ST({ approver_staff: true }) } });
  t = await text(p);
  ok(/Pay requests to decide/.test(await p.locator('h1').textContent()), 'title');
  ok(/Due today \(1\)/.test(t) && /Waiting \(1\)/.test(t), 'tabs carry the counts');
  ok(await p.locator('.prq-card[data-id="41"]').count() === 1 && await p.locator('.prq-card[data-id="41"] [data-act=prq_pay]').count() === 1 && /Overdue/.test(await p.locator('.prq-card[data-id="41"]').innerText()), 'the due tab shows the overdue item with Pay now');
  await p.click('[data-act=prq_tab][data-v=wait]'); await wait(p, 500);
  ok(await p.locator('.prq-card[data-id="31"] [data-act=prq_decide]').count() === 1 && await p.locator('.prq-card[data-id="32"] [data-act=prq_decide]').count() === 0, 'Approve only where can_decide (the maker gets no button)');
  ok(/test_emp_1 asks/.test(await p.locator('.prq-card[data-id="31"]').innerText()) && /test contact/.test(await p.locator('.prq-card[data-id="32"]').innerText()), 'the approver sees who asks (and the supplier-side contact)');
  await noOverflow(p, 'approver page'); await p.screenshot({ path: SP + '/prq_appr.png', fullPage: true });
  await p.click('.prq-card[data-id="31"] [data-act=prq_decide]'); await wait(p, 300);
  ok(await p.locator('#prqd_date').count() === 1 && await p.locator('#prqd_amt').count() === 1, 'the approve sheet asks for the date and the amount');
  await p.fill('#prqd_date', '2026-10-25'); await p.fill('#prqd_amt', '2,500'); await p.fill('#prqd_note', 'test: next week'); await p.click('[data-act=prq_decide_go]'); await wait(p, 600);
  let dc = await calls(p, 'pay_request_decide');
  ok(dc.length === 1 && dc[0].p_id === 31 && dc[0].p_approve === true && dc[0].p_pay_date === '2026-10-25' && dc[0].p_amount === 2500 && dc[0].p_note === 'test: next week', 'approve on another date and amount: ' + JSON.stringify(dc[0]));
  await p.click('.prq-card[data-id="31"] [data-act=prq_reject]'); await wait(p, 600);
  dc = await calls(p, 'pay_request_decide');
  ok(dc.length === 2 && dc[1].p_approve === false && dc[1].p_note === 'test reason', 'reject sends the reason');
  p = await page('#/payapprovals', { fn: { pay_request_state: ST({ approver_staff: true }) }, prompt: '' });
  await p.click('[data-act=prq_tab][data-v=wait]'); await wait(p, 400); await p.click('.prq-card[data-id="31"] [data-act=prq_reject]'); await wait(p, 400);
  ok((await calls(p, 'pay_request_decide')).length === 0, 'a rejection without a reason is not sent');
  p = await page('#/payapprovals', { fn: { pay_request_state: ST({ approver_staff: true }) } });
  await p.click('.prq-card[data-id="41"] [data-act=prq_pay]'); await wait(p, 400);
  ok(await p.locator('#prqp_mode').count() === 1 && await p.locator('#prqp_note').count() === 1, 'the pay sheet asks how it is paid (cash, mobile banking, bank: not fixed)');
  ok(await p.locator('#prqp_mode option').count() === 3, 'three modes to choose from');
  await p.selectOption('#prqp_mode', 'mobile'); await p.click('[data-act=prq_pay_go]'); await wait(p, 600);
  const py = await calls(p, 'pay_request_pay');
  ok(py.length === 1 && py[0].p_id === 41 && py[0].p_mode === 'mobile' && py[0].p_money_account === null, 'pay sends the request id and the mode chosen now: ' + JSON.stringify(py[0]));
  p = await page('#/payapprovals', { fn: { pay_request_state: ST({ approver_staff: true }) }, err: { pay_request_pay: 'more_than_due' } });
  await p.click('.prq-card[data-id="41"] [data-act=prq_pay]'); await wait(p, 300); await p.click('[data-act=prq_pay_go]'); await wait(p, 500);
  ok(/More than the salary due/.test(await p.locator('#toast').innerText()), 'a refusal by the payment function is shown in plain words');
  p = await page('#/payapprovals', { fn: { pay_request_state: ST(), pay_request_list: { due: { rows: [] }, inbox: { rows: [] } } } });
  ok(/Nothing here/.test(await text(p)), 'nothing to decide: an empty list, no error');

  log('section: settings (owner)');
  p = await page('#/payreqsettings', { owner: true, fn: { pay_request_state: ST({ is_owner: true }) } });
  t = await text(p);
  ok(/Pay request settings/.test(await p.locator('h1').textContent()) && await p.locator('.prq-sw').count() === 4, 'four switches');
  ok(/Payment check: 3\/3/.test(t), 'the payment check (trigger) status is shown');
  await p.click('.prq-sw[data-key=pay_requests_on] [data-act=prq_sw]'); await wait(p, 500);
  let sr = await calls(p, 'set_rule');
  ok(sr.length === 1 && sr[0].p_key === 'pay_requests_on' && sr[0].p_value === true, 'switch on: set_rule(true): ' + JSON.stringify(sr));
  await p.selectOption('#prqs_pay_requests_required_kinds', 'advance'); await p.click('.prq-sel[data-key=pay_requests_required_kinds] [data-act=prq_selsave]'); await wait(p, 500);
  sr = await calls(p, 'set_rule');
  ok(sr.length === 2 && sr[1].p_key === 'pay_requests_required_kinds' && sr[1].p_value === 'advance', 'kinds saved');
  await p.fill('#prql_pay_request_max_per_month', '3'); await p.click('.prq-lim[data-key=pay_request_max_per_month] [data-act=prq_limsave]'); await wait(p, 500);
  sr = await calls(p, 'set_rule');
  ok(sr.length === 3 && sr[2].p_value === 3, 'limit saved as a number');
  await p.fill('#prql_pay_request_max_per_month', ''); await p.click('.prq-lim[data-key=pay_request_max_per_month] [data-act=prq_limsave]'); await wait(p, 500);
  sr = await calls(p, 'set_rule');
  ok(sr.length === 4 && sr[3].p_value === null, 'blank limit = no limit is sent as null');
  await p.selectOption('#prqa_mode_staff', 'role'); await p.selectOption('#prqa_role_staff', 'purchasing'); await p.click('.prq-appr[data-scope=staff] [data-act=prq_appr]'); await wait(p, 500);
  const ap = await calls(p, 'pay_request_approver_set');
  ok(ap.length === 1 && ap[0].p_scope === 'staff' && ap[0].p_mode === 'role' && ap[0].p_role === 'purchasing' && ap[0].p_user === null, 'approver set in one call: ' + JSON.stringify(ap[0]));
  ok(await p.locator('#prqa_mode_party option').count() === 4, 'the supplier approver can also be "same as staff requests"');
  await noOverflow(p, 'settings'); await p.screenshot({ path: SP + '/prq_settings.png', fullPage: true });

  log('section: registry (ia.js)');
  p = await page('#/payrequest');
  const reg = await p.evaluate(() => { const g = (r) => window.BOS.IA.filter((x) => x.route === r); return ['payrequest', 'partyrequest', 'payapprovals', 'payreqsettings'].map((r) => [r, g(r).length, g(r)[0] && g(r)[0].group, g(r)[0] && g(r)[0].status]); });
  ok(JSON.stringify(reg) === JSON.stringify([['payrequest', 1, 'people', 'live'], ['partyrequest', 1, 'purch', 'live'], ['payapprovals', 1, 'appr', 'live'], ['payreqsettings', 1, 'settings', 'live']]), 'each screen is registered once, in the right group: ' + JSON.stringify(reg));
  const vis = await p.evaluate(() => { const c = { own: false, anyApprove: () => false, locOk: () => true, P: () => false, GF: {}, canPos: () => false, ctlOk: () => false }; const o = Object.assign({}, c, { own: true });
    const f = (r, x) => window.BOS.IA.find((y) => y.route === r).ok(x); return [f('payrequest', c), f('partyrequest', c), f('payapprovals', c), f('payreqsettings', c), f('payapprovals', o), f('payreqsettings', o)]; });
  ok(JSON.stringify(vis) === JSON.stringify([true, true, false, false, true, true]), 'visibility: staff see the two request screens; the inbox only for an approver or the owner; settings only for the owner: ' + JSON.stringify(vis));
  ok(await p.evaluate(() => window.BOS.IA.every((r, i, a) => a.filter((x) => x.route === r.route).length === 1)), 'no route is registered twice anywhere in the registry');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  if (errors.length) process.exitCode = 1; if (bad) process.exitCode = 1;
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
