// Money Accounts web piece (#/moneyaccounts) and the shared payment source picker (BOS.moneySrc).
// Checks: tabs, add / edit / switch off, defaults per payment type, transfer + charge, statement + CSV, real balance (blind), exceptions + one-off grant, approvers, reports with one line per account,
// the picker appears on the quick expense screen ONLY when accounts exist and tags the payment text "ma#<id>;", English labels, 360px width.
// Run: node moneyaccounts_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8485, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__MA = window.__MA || {};
 R.calls = R.calls || [];
 c.rpc = async (fn, args) => {
  if (!/^(money_|owner_approval_mode|entry_approver_set|quick_expense_)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.err && R.err[fn]) return { data: null, error: { message: R.err[fn], code: 'P0001' } };
  const f = R.fn && R.fn[fn];
  if (f !== undefined) return { data: typeof f === 'function' ? f(args) : f, error: null };
  if (fn === 'quick_expense_day') return { data: { total: 0, owed: 0, rows: [] }, error: null };
  if (fn === 'quick_expense_add') return { data: { id: 'x', amount: 1 }, error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;
const ACC = [
  { id: 1, code: 'MA-0001', kind: 'cash', name_en: 'test_drawer_a', name_bn: 'test_drawer_a', provider: null, branch: null, account_no: null, location_id: 1, coa_code: '1110-001', coa_account_id: 61, neg_policy: 'warn', active: true, sort: 100, opening_amount: 0, opening_posted: false, generic: false, journal: 30000, book: 30000, pending: 0, is_default_for: ['quick_expense'] },
  { id: 2, code: 'MA-0002', kind: 'wallet', name_en: 'test_wallet_main', name_bn: 'test_wallet_main', provider: 'TestPay', branch: null, account_no: '01700000001', location_id: null, coa_code: '1130-002', coa_account_id: 62, neg_policy: 'block', active: true, sort: 100, opening_amount: 0, opening_posted: false, generic: false, journal: 5000, book: 4800, pending: -200, is_default_for: [] },
  { id: 3, code: 'MA-0003', kind: 'bank', name_en: 'test_bank_one', name_bn: 'test_bank_one', provider: 'Test Bank', branch: 'Main', account_no: '1234567', location_id: null, coa_code: '1120-003', coa_account_id: 63, neg_policy: 'allow', active: false, sort: 100, opening_amount: 0, opening_posted: false, generic: false, journal: 0, book: 0, pending: 0, is_default_for: [] },
];
const SET = [{ event_type: 'quick_expense', label_en: 'Quick expense', dir: 'out', default_account_id: 1, default_name: 'test_drawer_a', allow_override: true, require_source: false }, { event_type: 'salary_payment', label_en: 'Salary payment', dir: 'out', default_account_id: null, default_name: null, allow_override: true, require_source: false }];
const PICK = { event: 'quick_expense', default_id: 1, allow_override: true, require_source: false, rows: [{ id: 1, kind: 'cash', name_en: 'test_drawer_a', provider: null, location_id: 1, account_no: '', is_default: true, mode: 'cash' }, { id: 2, kind: 'wallet', name_en: 'test_wallet_main', provider: 'TestPay', location_id: null, account_no: '0001', is_default: false, mode: 'mobile' }] };
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept(o.prompt || 'test reason'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__MA=${JSON.stringify(o.ma || {})};window.__MA.fn=window.__MA.fn||{};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__MA.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const FN = { money_accounts_list: { ready: true, as_of: '2026-10-16', rows: ACC, legacy_wallets: [{ code: 'bkash', name_en: 'bKash', coa_code: '1131' }] }, money_event_settings_list: SET,
    money_transfer_add: { id: 5 }, money_charge_add: { id: 6 }, money_account_add: { id: 9 }, money_account_update: { id: 1 }, money_account_set_active: { id: 3, active: true }, money_event_setting_set: { event_type: 'quick_expense' },
    money_statement: { account: ACC[0], from: '2026-10-01', to: '2026-10-16', opening: 100, in: 500, out: 200, closing: 400, rows: [{ date: '2026-10-05', entry_id: 12, memo: 'Cash move: owner_topup', source_type: 'cash_move', source_id: 'x', counter: '3100', in: 500, out: 0, balance: 600 }, { date: '2026-10-06', entry_id: 13, memo: 'Quick expense: transport', source_type: 'quick_expense', source_id: 'y', counter: '5700', in: 0, out: 200, balance: 400 }], not_posted_yet: [{ date: '2026-10-16', memo: 'Quick expense: x', amount: -11 }] },
    money_statement_csv: 'Statement,"test_drawer_a"\n', money_summary: { from: '2026-10-01', to: '2026-10-16', total: { opening: 100, in: 500, out: 200, closing: 400 }, accounts: [{ id: 1, name_en: 'test_drawer_a', kind: 'cash', opening: 100, in: 500, out: 200, closing: 400, active: true }], days: [{ date: '2026-10-05', in: 500, out: 0, net: 500 }], note: 'n' },
    money_check_save: { id: 4, real: 350, book: 400, diff: -50, status: 'difference' }, money_checks_list: [{ id: 3, account_id: 1, account: 'test_drawer_a', date: '2026-10-10', real: 10, book: 10, diff: 0, status: 'matched', reason: null }], money_check_explain: { id: 4, status: 'explained' },
    money_exceptions_list: { rows: [{ id: 1, at: '2026-10-16T05:00:00Z', kind: 'negative_warn', event_type: 'quick_expense', account_id: 1, account_name: 'test_drawer_a', amount: 50, reason: 'balance 10 before', status: 'open' }], grants: [] }, money_exception_grant: { id: 7 }, money_exception_resolve: { id: 1 },
    owner_approval_mode: { mode: 'self', approver_role: null, approver_users: [], owner_self_approve: true }, owner_approval_mode_set2: { mode: 'named' }, entry_approver_set: { entry_id: 'e' },
    money_statements: { from: '2026-10-01', to: '2026-10-16', income_statement: { total_income: 1000, total_expense: 400, net_profit: 600 }, balance_sheet: { total_assets: 9000 }, money_lines: [{ id: 1, name_en: 'test_drawer_a', kind: 'cash', coa_code: '1110-001', closing: 400 }, { id: 2, name_en: 'test_wallet_main', kind: 'wallet', coa_code: '1130-002', closing: 800 }], money_total_closing: 1200 },
    money_salary_sources: { by_source: [{ source: 'test_bank_one', amount: 8500 }, { source: 'not named (cash)', amount: 100 }], payments: [] },
    money_pick: (a) => PICK };
  const MA = (extra) => ({ fn: Object.assign({}, FN, extra || {}), calls: [] });
  // the screen is only a UI over the server: functions are mocked
  const mk = (extra) => ({ ma: { calls: [], fn: null } });
  async function openMA(hash, extra, o = {}) {
    const p = await open(hash, Object.assign({}, o));
    await p.evaluate(([fn, ex]) => { }, [0, 0]);
    return p;
  }
  // ---- inject the mock functions as strings (functions cannot be serialised): do it with evaluate before the first rpc by using addInitScript data
  async function page(hash, extra, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept(o.prompt || 'test reason'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    const fn = Object.assign({}, FN, extra || {}); delete fn.money_pick;
    const pick = (o.pick === undefined ? PICK : o.pick);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__MA={calls:[],err:${JSON.stringify(o.err || {})},fn:${JSON.stringify(fn)}};window.__MA.fn.money_pick=${JSON.stringify(pick)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }

  // ---- accounts tab
  let p = await page('#/moneyaccounts');
  let t = await text(p);
  ok(/Money Accounts/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('.ma-acc').count() === 3 && /test_drawer_a/.test(t) && /MA-0002/.test(t) && /1130-002/.test(t), 'three accounts listed with code and chart account');
  ok(/Cash drawer/.test(t) && /Mobile wallet/.test(t) && /Bank account/.test(t), 'kinds shown');
  ok(/Switched off/.test(t) && /Not posted yet/.test(t) && /Default for 1 payment type/.test(t), 'inactive, pending and default chips');
  ok(/Legacy wallets/.test(t) && /never depends on it/.test(t), 'the legacy wallet note explains the switch');
  ok((await calls(p, 'money_accounts_list')).length >= 1, 'list read');
  await noOverflow(p, 'accounts'); await p.screenshot({ path: SP + '/ma_accounts.png', fullPage: true });
  // add a wallet
  await p.click('[data-act=ma_new]'); await wait(p, 300);
  await p.selectOption('#na_kind', 'wallet'); await wait(p, 100);
  ok(await p.locator('#na_prov').isVisible() && !(await p.locator('#na_place').isVisible()), 'provider fields for a wallet, no place');
  await p.fill('#na_name', 'test_wallet_two'); await p.fill('#na_provider', 'TestPay'); await p.fill('#na_no', '01711111111'); await p.selectOption('#na_neg', 'block');
  await p.click('[data-act=ma_add]'); await wait(p, 500);
  let add = await calls(p, 'money_account_add');
  ok(add.length === 1 && add[0].p_kind === 'wallet' && add[0].p_name_en === 'test_wallet_two' && add[0].p_provider === 'TestPay' && add[0].p_account_no === '01711111111' && add[0].p_neg === 'block' && add[0].p_location === null, 'add wallet call: ' + JSON.stringify(add));
  // add a cash drawer needs a place
  await p.click('[data-act=ma_new]'); await wait(p, 300);
  await p.fill('#na_name', 'test_drawer_z'); await p.selectOption('#na_loc', { index: 1 }); await p.fill('#na_open', '2500');
  await p.click('[data-act=ma_add]'); await wait(p, 500);
  add = await calls(p, 'money_account_add');
  ok(add.length === 2 && add[1].p_kind === 'cash' && add[1].p_opening === 2500 && add[1].p_location !== null, 'add cash drawer call: ' + JSON.stringify(add[1]));
  // switch off asks for a reason; switch on does not
  await p.click('.ma-acc[data-id="1"] [data-act=ma_toggle]'); await wait(p, 500);
  let tg = await calls(p, 'money_account_set_active');
  ok(tg.length === 1 && tg[0].p_active === false && tg[0].p_reason === 'test reason', 'switch off sends the reason');
  await p.click('.ma-acc[data-id="3"] [data-act=ma_toggle]'); await wait(p, 500);
  tg = await calls(p, 'money_account_set_active');
  ok(tg.length === 2 && tg[1].p_active === true, 'switch on');
  await p.click('.ma-acc[data-id="2"] [data-act=ma_edit]'); await wait(p, 300);
  await p.fill('#na_name', 'test_wallet_renamed'); await p.click('[data-act=ma_update]'); await wait(p, 500);
  const up = await calls(p, 'money_account_update');
  ok(up.length === 1 && up[0].p_id === 2 && up[0].p_name_en === 'test_wallet_renamed', 'rename call');

  // ---- defaults
  await p.click('[data-act=ma_tab][data-v=defaults]'); await wait(p, 500);
  ok(await p.locator('.ma-set').count() === 2, 'one block per payment type');
  await p.selectOption('#ds_salary_payment', '2'); await p.uncheck('#do_salary_payment'); await p.check('#dr_salary_payment');
  await p.click('.ma-set[data-ev=salary_payment] [data-act=ma_setsave]'); await wait(p, 500);
  const ds = await calls(p, 'money_event_setting_set');
  ok(ds.length === 1 && ds[0].p_event === 'salary_payment' && ds[0].p_default === 2 && ds[0].p_allow_override === false && ds[0].p_require === true && ds[0].p_clear_default === false, 'default / override / require sent: ' + JSON.stringify(ds));
  await noOverflow(p, 'defaults'); await p.screenshot({ path: SP + '/ma_defaults.png', fullPage: true });

  // ---- transfers and charges
  await p.click('[data-act=ma_tab][data-v=move]'); await wait(p, 500);
  await p.selectOption('#tr_from', '1'); await p.selectOption('#tr_to', '2'); await p.fill('#tr_amt', '1,000'); await p.fill('#tr_fee', '10'); await p.selectOption('#tr_side', 'to');
  await p.click('[data-act=ma_transfer]'); await wait(p, 500);
  const tr = await calls(p, 'money_transfer_add');
  ok(tr.length === 1 && tr[0].p_from === 1 && tr[0].p_to === 2 && tr[0].p_amount === 1000 && tr[0].p_fee === 10 && tr[0].p_fee_side === 'to' && /^[0-9a-f-]{36}$/.test(tr[0].p_client), 'transfer call');
  await p.fill('#ch_amt', '15'); await p.selectOption('#ch_kind', 'interest'); await p.click('[data-act=ma_charge]'); await wait(p, 500);
  const ch = await calls(p, 'money_charge_add');
  ok(ch.length === 1 && ch[0].p_kind === 'interest' && ch[0].p_amount === 15, 'charge call');
  await p.fill('#tr_amt', '0'); await p.click('[data-act=ma_transfer]'); await wait(p, 300);
  ok((await calls(p, 'money_transfer_add')).length === 1, 'a zero amount is not sent');

  // ---- statement
  await p.click('[data-act=ma_tab][data-v=statement]'); await wait(p, 400);
  await p.selectOption('#st_acc', '1'); await p.click('[data-act=ma_stshow]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.st-row').count() === 2 && /Opening/.test(t) && /Closing/.test(t) && /Not posted yet/.test(t), 'statement rows, totals and the not-posted list');
  const dl = p.waitForEvent('download', { timeout: 3000 }).catch(() => null);
  await p.click('[data-act=ma_stcsv]'); const d = await dl; await wait(p, 300);
  ok((await calls(p, 'money_statement_csv')).length === 1 && d && /statement-1\.csv/.test(d.suggestedFilename()), 'CSV export downloads a file');
  await noOverflow(p, 'statement'); await p.screenshot({ path: SP + '/ma_statement.png', fullPage: true });

  // ---- summary
  await p.click('[data-act=ma_tab][data-v=summary]'); await wait(p, 400);
  await p.click('[data-act=ma_smshow]'); await wait(p, 500);
  ok(/All accounts/.test(await text(p)) && /By day/.test(await text(p)), 'summary shown');

  // ---- real balance: the book figure only after saving
  await p.click('[data-act=ma_tab][data-v=check]'); await wait(p, 400);
  ok(!/Book/.test(await p.locator('#ma_pane').innerText().then((x) => x.replace(/Earlier counts[\s\S]*/, '').replace(/The book figure[^.]*\./, ''))), 'the book figure is not on the form before the count');
  await p.fill('#ck_real', '350'); await p.click('[data-act=ma_ckgo]'); await wait(p, 600);
  ok(await p.locator('#ck_res').count() === 1 && /Book 400\.00/.test(await text(p)) && /difference -50\.00/.test(await text(p)), 'after saving: book and difference shown');
  await p.fill('#ck_why', 'test coin pouch'); await p.click('[data-act=ma_ckwhy]'); await wait(p, 500);
  const ex = await calls(p, 'money_check_explain');
  ok(ex.length === 1 && ex[0].p_reason === 'test coin pouch', 'reason sent');

  // ---- exceptions
  await p.click('[data-act=ma_tab][data-v=exceptions]'); await wait(p, 600);
  ok(/negative_warn/.test(await text(p)) && await p.locator('#ex_grant').count() === 1, 'exceptions list and the owner grant card');
  await p.selectOption('#gx_rule', 'negative'); await p.fill('#gx_client', '11111111-1111-4111-8111-111111111111'); await p.fill('#gx_reason', 'test one-off');
  await p.click('[data-act=ma_gxgo]'); await wait(p, 500);
  const gx = await calls(p, 'money_exception_grant');
  ok(gx.length === 1 && gx[0].p_rule === 'negative' && gx[0].p_client === '11111111-1111-4111-8111-111111111111' && gx[0].p_reason === 'test one-off', 'grant call');
  await p.click('[data-act=ma_exres]'); await wait(p, 500);
  ok((await calls(p, 'money_exception_resolve')).length === 1, 'resolve');

  // ---- approvers
  await p.click('[data-act=ma_tab][data-v=approvers]'); await wait(p, 600);
  ok(/Mode: self/.test(await text(p)) && await p.locator('#ap_set').count() === 1, 'current approver setting');
  await p.selectOption('#ap_mode', 'named'); await p.selectOption('#ap_role', '-'); await p.click('[data-act=ma_apgo]'); await wait(p, 500);
  const ap = await calls(p, 'owner_approval_mode_set2');
  ok(ap.length === 1 && ap[0].p_mode === 'named' && ap[0].p_role === '-' && Array.isArray(ap[0].p_users), 'approver set call');

  // ---- reports
  await p.click('[data-act=ma_tab][data-v=reports]'); await wait(p, 400);
  await p.click('[data-act=ma_rpshow]'); await wait(p, 600);
  ok(await p.locator('.rp-line').count() === 2 && /test_wallet_main/.test(await text(p)) && /test_bank_one/.test(await text(p)), 'P&L / balance sheet money lines: one per account, salary by source');
  await noOverflow(p, 'reports'); await p.screenshot({ path: SP + '/ma_reports.png', fullPage: true });

  // ---- errors are readable
  p = await page('#/moneyaccounts', {}, { err: { money_transfer_add: 'money_negative' } });
  await p.click('[data-act=ma_tab][data-v=move]'); await wait(p, 400); await p.fill('#tr_amt', '5'); await p.click('[data-act=ma_transfer]'); await wait(p, 500);
  ok(/does not hold that much/.test(await text(p)), 'a server refusal is shown in words');
  // ---- not allowed
  p = await page('#/moneyaccounts', {}, { err: { money_accounts_list: 'not allowed' } });
  ok(/permission/.test(await text(p)) || /not allowed|You do not have permission/.test(await text(p)), 'denied is shown');

  // ---- the picker on the quick expense screen
  p = await page('#/quickexp');
  t = await text(p);
  ok(await p.locator('#ms_qx').count() === 1 && await p.locator('#ms_sel_qx').count() === 1, 'the Payment source picker is on the quick expense screen');
  ok(/Payment source/.test(t) && /test_wallet_main/.test(await p.locator('#ms_sel_qx').innerText()), 'picker lists the accounts');
  await p.fill('#qx_amt', '70'); await p.selectOption('#ms_sel_qx', '2'); await p.click('[data-act=qx_add]'); await wait(p, 600);
  const qa = await calls(p, 'quick_expense_add');
  ok(qa.length === 1 && qa[0].p_note === 'ma#2;' && qa[0].p_amount === 70, 'the choice travels in the note as ma#2; : ' + JSON.stringify(qa));
  await p.selectOption('#ms_sel_qx', ''); await p.fill('#qx_amt', '5'); await p.click('[data-act=qx_add]'); await wait(p, 600);
  const qb = await calls(p, 'quick_expense_add');
  ok(qb.length === 2 && qb[1].p_note === null, 'the default (empty choice) sends no tag');
  await noOverflow(p, 'quickexp'); await p.screenshot({ path: SP + '/ma_picker.png', fullPage: true });
  // nothing configured: the picker is invisible and the screen is as before
  p = await page('#/quickexp', {}, { pick: { event: 'quick_expense', default_id: null, allow_override: true, require_source: false, rows: [] } });
  ok(await p.locator('#ms_sel_qx').count() === 0 && (await p.locator('#ms_qx').innerHTML()).trim() === '', 'no accounts: no picker is drawn');
  await p.fill('#qx_amt', '9'); await p.click('[data-act=qx_add]'); await wait(p, 500);
  ok((await calls(p, 'quick_expense_add'))[0].p_note === null, 'no accounts: the note is sent as before');
  // required source: the first choice is a prompt, not a source
  p = await page('#/quickexp', {}, { pick: { event: 'quick_expense', default_id: null, allow_override: true, require_source: true, rows: PICK.rows } });
  ok(/Choose the payment source/.test(await p.locator('#ms_sel_qx').innerText()), 'required: the select asks for a choice');
  // fixed by the owner: disabled, only the default
  p = await page('#/quickexp', {}, { pick: { event: 'quick_expense', default_id: 1, allow_override: false, require_source: false, rows: [PICK.rows[0]] } });
  ok(await p.locator('#ms_sel_qx').isDisabled() && /Fixed by the owner setting/.test(await text(p)), 'override not allowed: the select is locked to the default');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
