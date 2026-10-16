// Money controls web piece (#/moneycontrols): settings for every policy choice (owner edits, others read), requests (approve, reject with a reason, cancel, own approver),
// exceptions (red / yellow, one-off exception form), checks (shared supplier identity / pay account), mapping types, English labels, 360px width, no console errors.
// The server is mocked: the screen is only a UI over phases 94 and 95 (the decisions are made and tested in SQL).
// Run: node moneycontrols_test.js <abs tests/web dir>      (web/moneycontrols.js and one ia.js line are injected here; the integrator adds the real <script> tag and registry line)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8486, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__MC = window.__MC || { calls: [], fn: {}, err: {} };
 c.rpc = async (fn, args) => {
  if (!/^(w1e_|money_exception_|set_rule$)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.err && R.err[fn]) return { data: null, error: { message: R.err[fn], code: 'P0001' } };
  if (fn === 'set_rule') return { data: null, error: null };
  const f = R.fn && R.fn[fn];
  if (f !== undefined) return { data: f, error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;
const RULE = (key, kind, label, hint, def, o = {}) => Object.assign({ key, module: 'books', kind, value: null, default_value: def, choices: null, unit: null, min_value: null, max_value: null, label_en: label, hint_en: hint }, o);
const RULES = [
  RULE('owner_money_entry_mode', 'choice', 'Who may record an owner draw or an owner top-up', 'open = anyone with the cash move right (today).', 'open', { choices: ['open', 'approval', 'owner'] }),
  RULE('bank_slip_required', 'switch', 'Bank slip number required on a bank deposit and a bank withdraw', 'Off = today.', false),
  RULE('bank_move_large_over', 'number', 'Flag a bank deposit or withdraw above this amount', 'Blank = off.', null, { unit: 'Tk' }),
  RULE('bank_move_backdate_days', 'number', 'Flag a bank deposit or withdraw dated more than this many days back', 'Blank = off.', null, { unit: 'days' }),
  RULE('supplier_pay_dup_mode', 'choice', 'Same supplier payment entered twice', 'off = today.', 'off', { choices: ['off', 'flag', 'block'] }),
  RULE('supplier_pay_dup_hours', 'number', 'Window for the repeat-payment check', 'Blank = the same calendar day.', null, { unit: 'hours' }),
  RULE('supplier_pay_over', 'number', 'A supplier payment above this amount waits for the approver', 'Blank = off.', null, { unit: 'Tk' }),
  RULE('supplier_dup_mode', 'choice', 'Second supplier with the same name, mobile or TIN', 'off = today.', 'off', { choices: ['off', 'warn', 'block'] }),
  RULE('employee_pay_dup_mode', 'choice', 'Two employees on one pay account', 'off = today.', 'off', { choices: ['off', 'warn', 'block'] }),
  RULE('employee_pay_change_flag', 'switch', 'Red line when an employee pay account is changed', 'Off = today.', false),
  RULE('journal_loc_check', 'switch', 'Check the place of every line of a manual journal', 'Off = today.', false),
  RULE('journal_attach_over', 'number', 'A manual journal above this total needs an attachment', 'Blank = off.', null, { unit: 'Tk' }),
  RULE('journal_control_acct_mode', 'choice', 'Manual journal by a person who is not the owner on a control account', 'allow = today.', 'allow', { choices: ['allow', 'request', 'block'] }),
  RULE('journal_control_prefixes', 'text', 'Chart codes that count as control accounts', 'Comma separated.', '11,1210,13,2100'),
  RULE('mapping_type_guard', 'switch', 'Check the account type when a mapping is changed', 'Off = today.', false),
  RULE('purchase_separate_poster', 'switch', 'The person who wrote a purchase bill cannot post it', 'Off by default', false),
];
const PEOPLE = [{ id: '00000000-0000-0000-0000-0000000000a1', full_name: 'test_cashier', staff_id: 'tc1', status: 'active' }, { id: '00000000-0000-0000-0000-0000000000a2', full_name: 'test_approver', staff_id: 'ta1', status: 'active' }];
const STATE = { settings: {}, pending: 2, approver: { mode: 'self', role: null, users: [] }, hooks: { pay_supplier: false, cash_move_add: true, acct_journal_post: false }, is_owner: true };
const RQ = { rows: [
  { id: 11, kind: 'owner_money', status: 'pending', location_id: 1, amount: 700, ref_date: '2026-10-16', summary: 'owner_draw 700.00 on 2026-10-16 (cash)', requested_by: PEOPLE[0].id, requested_staff: 'tc1', requested_at: '2026-10-16T05:00:00Z', can_decide: true, can_cancel: true, mine: false },
  { id: 12, kind: 'supplier_pay', status: 'pending', location_id: 1, amount: 6000, ref_date: '2026-10-16', summary: 'Supplier payment 6000 to test_supplier (limit 5000)', requested_by: PEOPLE[1].id, requested_staff: 'ta1', requested_at: '2026-10-16T05:10:00Z', can_decide: false, can_cancel: false, mine: true },
  { id: 13, kind: 'journal_control', status: 'approved', location_id: 1, amount: 200, ref_date: '2026-10-15', summary: 'Manual journal 200 on 2026-10-15: test memo', requested_by: PEOPLE[0].id, requested_staff: 'tc1', requested_at: '2026-10-15T05:00:00Z', decided_staff: 'ta1', decision_note: 'checked', can_decide: false, can_cancel: false, mine: false } ] };
const EX = { rows: [
  { id: 1, at: '2026-10-16T05:00:00Z', kind: 'w1e_pay_account_changed', event_type: 'w1e_pay_account', amount: null, reason: 'pay account changed: bank ****-777 -> ****-888', status: 'open', level: 'red' },
  { id: 2, at: '2026-10-16T05:01:00Z', kind: 'w1e_bank_move_flag', event_type: 'w1e_bank_large', amount: 1500, reason: 'bank_deposit 1500.00 is above the limit 1000', status: 'open', level: 'yellow' },
  { id: 3, at: '2026-10-16T05:02:00Z', kind: 'override_exception', event_type: 'w1e_bank_slip', amount: 500, reason: 'test: slip lost', status: 'resolved', resolve_note: 'checked with the bank', level: 'yellow' } ],
  grants: [{ id: 4, rule: 'override', event_type: 'w1e_owner_money', for_user: PEOPLE[0].id, reason: 'test: owner asked', used_at: null, revoked: false, expires_at: '2026-10-17T05:00:00Z' }] };
const CK = { vendors: [{ a_id: 'x1', a_name: 'test_vendor_a', b_id: 'x2', b_name: 'Test_Vendor_A', by: 'name' }], pay_accounts: [{ a_id: 'e1', a_no: 'TESTW1E_H', b_id: 'e2', b_no: 'TESTW1E_I', by: 'bank_account', account: '****-999' }] };
const TY = [{ key_like: 'sales', allowed: ['income'], active: true, note: 'sales' }, { key_like: 'exp\\_%', allowed: ['expense'], active: true, note: 'expense heads' }, { key_like: 'wastage', allowed: ['expense'], active: false, note: null }];
const FN = { w1e_state: STATE, w1e_requests_list: RQ, w1e_exceptions_list: EX, w1e_checks: CK, w1e_mapping_types_list: TY, w1e_request_decide: { id: 11, status: 'approved' }, w1e_request_cancel: { id: 11, status: 'cancelled' },
  w1e_request_approver_set: { id: 11 }, money_exception_grant: { id: 9 }, money_exception_resolve: { id: 1 }, w1e_mapping_type_set: { key_like: 'sales' } };
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function page(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.setDefaultTimeout(8000); p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept(o.prompt === undefined ? 'test reason' : o.prompt));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/moneycontrols\.js/.test(h) ? h : h.replace('</body>', '<script src="moneycontrols.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {}); data.tables.rules = JSON.parse(JSON.stringify(RULES)); data.tables.profiles = (data.tables.profiles || []).concat(PEOPLE); data.tables.roles = (data.tables.roles || []);
    const fn = Object.assign({}, FN, o.fn || {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__MC={calls:[],err:${JSON.stringify(o.err || {})},fn:${JSON.stringify(fn)}};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, f) => p.evaluate((x) => (window.__MC.calls || []).filter((c) => c[0] === x).map((c) => c[1]), f);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  log('section: settings (owner)');
  // ---- settings (owner)
  let p = await page('#/moneycontrols');
  let t = await text(p);
  ok(/Money controls/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('.mc-rule').count() === 16, 'all 16 settings listed (15 new + the existing purchase setting): ' + await p.locator('.mc-rule').count());
  ok(/Owner money/.test(t) && /Bank deposits and withdrawals/.test(t) && /Supplier payments/.test(t) && /Journals/.test(t) && /Chart mapping/.test(t), 'groups');
  ok(/Who may record an owner draw or an owner top-up/.test(t) && /Default \(today\): open/.test(t) && /Default \(today\): blank \(off\)/.test(t), 'English label and the default that keeps today');
  ok(/Supplier payment guard: waiting for the hook/.test(t) && /Cash move answer: ready/.test(t), 'hook status is shown (the integrator step)');
  ok(/mode self/.test(t) && await p.locator('a[href="#/moneyaccounts"]').count() === 1, 'the approver chosen under Money Accounts is shown, not chosen here');
  ok((await calls(p, 'w1e_state')).length >= 1, 'state read');
  await noOverflow(p, 'settings'); await p.screenshot({ path: SP + '/mc_settings.png', fullPage: true });
  await p.selectOption('#mc_r_owner_money_entry_mode', 'approval'); await p.click('.mc-rule[data-key=owner_money_entry_mode] [data-act=mc_save]'); await wait(p, 500);
  let sr = await calls(p, 'set_rule');
  ok(sr.length === 1 && sr[0].p_key === 'owner_money_entry_mode' && sr[0].p_value === 'approval', 'choice saved through set_rule (logged by the server): ' + JSON.stringify(sr));
  await p.fill('#mc_r_supplier_pay_over', '5,000'); await p.click('.mc-rule[data-key=supplier_pay_over] [data-act=mc_save]'); await wait(p, 500);
  sr = await calls(p, 'set_rule');
  ok(sr.length === 2 && sr[1].p_key === 'supplier_pay_over' && sr[1].p_value === 5000, 'number saved as a number: ' + JSON.stringify(sr[1]));
  await p.fill('#mc_r_supplier_pay_over', ''); await p.click('.mc-rule[data-key=supplier_pay_over] [data-act=mc_save]'); await wait(p, 500);
  sr = await calls(p, 'set_rule');
  ok(sr.length === 3 && sr[2].p_value === null, 'blank number = off is sent as null');
  await p.fill('#mc_r_supplier_pay_over', 'abc'); await p.click('.mc-rule[data-key=supplier_pay_over] [data-act=mc_save]'); await wait(p, 300);
  ok((await calls(p, 'set_rule')).length === 3, 'a non-number is not sent');
  await p.selectOption('#mc_r_bank_slip_required', 'true'); await p.click('.mc-rule[data-key=bank_slip_required] [data-act=mc_save]'); await wait(p, 500);
  sr = await calls(p, 'set_rule');
  ok(sr.length === 4 && sr[3].p_key === 'bank_slip_required' && sr[3].p_value === true, 'switch saved as boolean');
  await p.fill('#mc_r_journal_control_prefixes', '11,13'); await p.click('.mc-rule[data-key=journal_control_prefixes] [data-act=mc_save]'); await wait(p, 500);
  sr = await calls(p, 'set_rule');
  ok(sr.length === 5 && sr[4].p_value === '11,13', 'text saved');

  log('section: settings (not the owner)');
  // ---- settings (not the owner): read only
  p = await page('#/moneycontrols', { owner: false, fn: { w1e_state: Object.assign({}, STATE, { is_owner: false }) } });
  t = await text(p);
  ok(/Only the owner can change a setting/.test(t) && await p.locator('[data-act=mc_save]').count() === 0, 'a non-owner sees the settings but no Save button');

  log('section: requests');
  // ---- requests
  p = await page('#/moneycontrols');
  await p.click('[data-act=mc_tab][data-v=requests]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.mc-req').count() === 3 && /Owner money/.test(t) && /Supplier payment/.test(t) && /Journal on a control account/.test(t), 'three requests, kinds in English');
  ok(await p.locator('.mc-req[data-id="11"] [data-act=mc_approve]').count() === 1 && await p.locator('.mc-req[data-id="12"] [data-act=mc_approve]').count() === 0, 'Approve only where the server says can_decide');
  ok(/you cannot decide your own request/.test(t), 'the maker is told he cannot decide his own request');
  ok((await calls(p, 'w1e_requests_list')).some((a) => a.p_status === 'pending'), 'pending list asked by default');
  await noOverflow(p, 'requests'); await p.screenshot({ path: SP + '/mc_requests.png', fullPage: true });
  await p.click('.mc-req[data-id="11"] [data-act=mc_approve]'); await wait(p, 500);
  let dc = await calls(p, 'w1e_request_decide');
  ok(dc.length === 1 && dc[0].p_id === 11 && dc[0].p_approve === true, 'approve call');
  await p.click('.mc-req[data-id="11"] [data-act=mc_reject]'); await wait(p, 500);
  dc = await calls(p, 'w1e_request_decide');
  ok(dc.length === 2 && dc[1].p_approve === false && dc[1].p_note === 'test reason', 'reject sends the reason');
  await p.click('.mc-req[data-id="11"] [data-act=mc_cancel]'); await wait(p, 500);
  const cc = await calls(p, 'w1e_request_cancel');
  ok(cc.length === 1 && cc[0].p_id === 11 && cc[0].p_note === 'test reason', 'cancel sends the reason');
  await p.click('.mc-req[data-id="11"] [data-act=mc_setap]'); await wait(p, 300);
  await p.selectOption('#sa_user', PEOPLE[1].id); await p.click('[data-act=mc_setapgo]'); await wait(p, 300);
  ok((await calls(p, 'w1e_request_approver_set')).length === 0, 'a reason is required for a per-request approver');
  await p.fill('#sa_why', 'test: this one goes to the other person'); await p.click('[data-act=mc_setapgo]'); await wait(p, 500);
  const ap = await calls(p, 'w1e_request_approver_set');
  ok(ap.length === 1 && ap[0].p_id === 11 && ap[0].p_user === PEOPLE[1].id && ap[0].p_role === null && /other person/.test(ap[0].p_reason), 'approver for one request: ' + JSON.stringify(ap));
  await p.click('[data-act=mc_rqf][data-v=all]'); await wait(p, 500);
  ok((await calls(p, 'w1e_requests_list')).some((a) => a.p_status === null), 'the All filter asks for every status');
  // an error from the server is shown in plain English
  p = await page('#/moneycontrols', { err: { w1e_request_decide: 'self_approval' } });
  await p.click('[data-act=mc_tab][data-v=requests]'); await wait(p, 500);
  await p.click('.mc-req[data-id="11"] [data-act=mc_approve]'); await wait(p, 500);
  ok(/you cannot decide it/.test(await text(p)), 'self_approval is explained');
  // a short reject reason is not sent
  p = await page('#/moneycontrols', { prompt: 'x' });
  await p.click('[data-act=mc_tab][data-v=requests]'); await wait(p, 500);
  await p.click('.mc-req[data-id="11"] [data-act=mc_reject]'); await wait(p, 400);
  ok((await calls(p, 'w1e_request_decide')).length === 0, 'a reject without a real reason is not sent');

  log('section: exceptions');
  // ---- exceptions
  p = await page('#/moneycontrols');
  await p.click('[data-act=mc_tab][data-v=exceptions]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.mc-ex').count() === 3 && await p.locator('.mc-ex[data-level=red]').count() === 1 && /Red/.test(t) && /Yellow/.test(t), 'red and yellow lines');
  ok(/Pay account changed/.test(t) && /Bank move flagged/.test(t) && /One-off exception used/.test(t) && /\*\*\*\*-888/.test(t) && !/555-666/.test(t), 'kinds in English, account numbers masked');
  ok(/Exceptions allowed/.test(t) && /test: owner asked/.test(t), 'exceptions the owner allowed are listed');
  await noOverflow(p, 'exceptions'); await p.screenshot({ path: SP + '/mc_exceptions.png', fullPage: true });
  await p.click('.mc-ex [data-act=mc_exres]'); await wait(p, 500);
  const rs = await calls(p, 'money_exception_resolve');
  ok(rs.length === 1 && rs[0].p_id === 1 && rs[0].p_note === 'test reason', 'looked-at note sent');
  await p.selectOption('#gx_ev', 'w1e_dup_payment'); await p.fill('#gx_reason', 'ab'); await p.selectOption('#gx_user', PEOPLE[0].id); await p.click('[data-act=mc_grant]'); await wait(p, 300);
  ok((await calls(p, 'money_exception_grant')).length === 0, 'a reason of 2 letters is not sent');
  await p.fill('#gx_reason', 'test: two real invoices of the same amount'); await p.selectOption('#gx_user', ''); await p.click('[data-act=mc_grant]'); await wait(p, 300);
  ok((await calls(p, 'money_exception_grant')).length === 0, 'no person chosen: not sent');
  await p.selectOption('#gx_user', PEOPLE[0].id); await p.click('[data-act=mc_grant]'); await wait(p, 500);
  const gx = await calls(p, 'money_exception_grant');
  ok(gx.length === 1 && gx[0].p_rule === 'override' && gx[0].p_event === 'w1e_dup_payment' && gx[0].p_for_user === PEOPLE[0].id && gx[0].p_hours === 24 && /two real invoices/.test(gx[0].p_reason), 'one-off exception call: ' + JSON.stringify(gx));
  p = await page('#/moneycontrols', { owner: false, fn: { w1e_state: Object.assign({}, STATE, { is_owner: false }) } });
  await p.click('[data-act=mc_tab][data-v=exceptions]'); await wait(p, 500);
  ok(await p.locator('#mc_grant').count() === 0, 'a non-owner has no exception form');

  log('section: checks');
  // ---- checks
  p = await page('#/moneycontrols');
  await p.click('[data-act=mc_tab][data-v=checks]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.mc-vd').count() === 1 && await p.locator('.mc-pa').count() === 1 && /same name/.test(t) && /TESTW1E_H/.test(t) && /\*\*\*\*-999/.test(t), 'shared supplier identity and shared pay account listed, number masked');
  await noOverflow(p, 'checks');

  log('section: mapping types');
  // ---- mapping types
  await p.click('[data-act=mc_tab][data-v=types]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.mc-ty').count() === 3 && /sales/.test(t) && /exp_%/.test(t) && /Switched off/.test(t) && /never deleted/.test(t), 'three rows, a switched-off row, the never-deleted note');
  await p.fill('#mt_0', 'income, expense'); await p.click('.mc-ty[data-k=sales] [data-act=mc_tysave]'); await wait(p, 500);
  let ts = await calls(p, 'w1e_mapping_type_set');
  ok(ts.length === 1 && ts[0].p_key_like === 'sales' && JSON.stringify(ts[0].p_allowed) === '["income","expense"]' && ts[0].p_active === true && ts[0].p_reason === 'test reason', 'type list saved with a reason: ' + JSON.stringify(ts));
  await p.click('.mc-ty[data-k=sales] [data-act=mc_tytog]'); await wait(p, 500);
  ts = await calls(p, 'w1e_mapping_type_set');
  ok(ts.length === 2 && ts[1].p_active === false, 'switch off (never delete)');
  await noOverflow(p, 'types'); await p.screenshot({ path: SP + '/mc_types.png', fullPage: true });

  log('section: server function missing');
  // ---- server function missing: a friendly message, no crash
  p = await page('#/moneycontrols', { err: { w1e_state: 'Could not find the function public.w1e_state' } });
  ok(/Could not find the function/.test(await text(p)) || /Money controls/.test(await p.locator('h1').textContent()), 'a missing server function does not break the page');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
