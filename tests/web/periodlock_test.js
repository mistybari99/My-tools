// Period lock web piece (#/periodlock). Checks: lock state and tabs, hooks-not-installed notice, set lock date (reason travels), lock rules saved through period_lock_policy_set in the right order,
// override window needs a reason and sends its dates / minutes / scope / person, end a window, back-date limits (number or empty), lateness report, late sale policy and the held-sale decisions
// (accept / re-date / reject send a reason), accounting backlog preview and the switch with a reason, guards, log, server errors shown in plain English, a non-owner sees only the state,
// English labels, 360px width without horizontal overflow, no console errors.
// The route is registered by the integrator (web/ia.js + a script tag in index.html); this test serves index.html with the script tag added, exactly as the integrator will.
// Run: node periodlock_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8589, srv = require('http').createServer((q, r) => {
  const u = q.url.split('?')[0]; const f = require('path').join(__dirname, '..', '..', 'web', u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => {
    if (e) { r.writeHead(404); return r.end(); }
    const x = require('path').extname(f); let body = b;
    if (u === '/' || u === '/index.html') body = Buffer.from(String(b).includes('src="periodlock.js"') ? String(b) : String(b).replace('<script src="moneyaccounts.js"></script>', '<script src="moneyaccounts.js"></script><script src="periodlock.js"></script>'));
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(body);
  });
}).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__PL = window.__PL || {};
 R.calls = R.calls || [];
 c.rpc = async (fn, args) => {
  if (!/^(period_|late_sale|accounting_on)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.err && R.err[fn]) return { data: null, error: { message: R.err[fn], code: 'P0001' } };
  const f = R.fn && R.fn[fn];
  if (f !== undefined) return { data: f, error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;
const STATE = { owner: true, today: '2026-10-16', mode: 'manual', manual_date: '2026-09-30', auto_day: null, effective_lock_date: '2026-09-30', owner_mode: 'off', override_minutes: 60, backward_policy: 'allow',
  backdate: { purchase: null, cash_move: 7, expense: null, production: null }, late_sale_policy: 'redate', offline_hours: 72, start_date_lock_after_opening: false, accounting_on: true, accounting_on_needs_reason: false, held_sales: 1,
  hooks: { lock_check: false, acct_locked: false, record_sale2: true, cash_move_add: true, quick_expense_add: true, save_purchase: true, production_post: true },
  my_windows: [], open_windows: [{ id: 5, user_id: 'u9', staff: 'test_staff_a', scope: 'lock', from: '2026-09-01', to: '2026-09-10', doc: null, expires_at: '2026-10-16T12:00:00Z', reason: 'test: late paper bill', uses: 2 }] };
const HELD = [{ id: 3, client_id: 'c', location_id: 1, sold_at: '2026-10-12T05:00:00Z', received_at: '2026-10-16T05:00:00Z', hours_late: 96, status: 'held', user_id: 'u8', staff: 'test_cashier', n_lines: 2, paid: 900, lines: [], decide_reason: null },
  { id: 2, client_id: 'd', location_id: 1, sold_at: '2026-10-10T05:00:00Z', received_at: '2026-10-16T05:00:00Z', hours_late: 140, status: 'accepted', user_id: 'u8', staff: 'test_cashier', n_lines: 1, paid: 100, lines: [], decide_reason: 'test: seen on the sheet' }];
const LATE = { days: 30, as_of: '2026-10-16', by_document: { cash_move: { records: 12, max_days_late: 9, same_day: 6, days_1_2: 3, days_3_7: 2, days_8_30: 1, over_30: 0 } }, note: 'Sales are not listed.' };
const LOG = { windows: [{ id: 5, scope: 'lock', user_id: 'u9', staff: 'test_staff_a', from_date: '2026-09-01', to_date: '2026-09-10', doc_type: null, reason: 'test: late paper bill', started_at: '2026-10-16T05:00:00Z', expires_at: '2026-10-16T06:00:00Z', ended_at: null, uses: 2 }],
  exceptions: [{ id: 9, at: '2026-10-16T05:30:00Z', kind: 'period_lock_exception', reason: 'test: late paper bill (override window #5)', src_table: 'period_overrides', src_id: '5', status: 'open' }],
  audit: [{ id: 40, at: '2026-10-16T05:30:00Z', staff_id: 'owner1', action: 'period_override_used', record_id: '5', detail: {} }] };
const FN = { period_lock_state: STATE, period_lock_set: { old: '2026-09-30', new: '2026-09-15', back: true }, period_lock_policy_set: { key: 'x' }, period_override_start: { id: 6, expires_at: '2026-10-16T09:00:00Z', minutes: 30 }, period_override_end: { id: 5, ended: true },
  period_override_log: LOG, period_lateness_report: LATE, late_sales_held_list: HELD, late_sale_release: { id: 3, action: 'accept' },
  accounting_on_preview: { ran: true, accounting_on: true, start_date: '2026-08-01', would_post: 14, would_reverse: 1, skipped_locked: 3, by_type: { cash_move: 14 }, oldest_in_sample: '2026-09-02', data_needed: false, more: false }, accounting_on_set: { old: true, new: false } };
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, total = 0; const ok = (c, m) => { total++; if (!c) { bad++; log('FAIL:', m); } };
  async function page(hash, extra, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept(o.prompt === undefined ? 'test reason' : o.prompt));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    const fn = Object.assign({}, FN, extra || {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__PL={calls:[],err:${JSON.stringify(o.err || {})},fn:${JSON.stringify(fn)}};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__PL.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const toastText = (p) => p.evaluate(() => (document.querySelector('#toast') || {}).textContent || '');
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // ---- Lock tab
  let p = await page('#/periodlock');
  let t = await text(p);
  ok(/Period lock/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('#pl_eff').textContent() === '2026-09-30' && /Books are closed up to/.test(t), 'the effective lock date is shown');
  ok(/Typed date 2026-09-30/.test(t) && /Owner: Silent/.test(t), 'mode chips');
  ok(/can still change closed dates without a trace/.test(t), 'the silent owner warning is shown');
  ok(await p.locator('#pl_hooks').count() === 1 && /the closed-period test/.test(await p.locator('#pl_hooks').innerText()) && !/cash moves/.test(await p.locator('#pl_hooks').innerText()), 'the hooks notice lists exactly the missing links');
  ok(await p.locator('#pl_tabs button').count() === 6, 'six tabs for the owner');
  await noOverflow(p, 'lock'); await p.screenshot({ path: SP + '/pl_lock.png', fullPage: true });
  // set the date: reason travels
  await p.fill('#pl_ld', '2026-09-15'); await p.fill('#pl_lr', 'test: wrong month was closed'); await p.click('[data-act=pl_setdate]'); await wait(p, 500);
  let sd = await calls(p, 'period_lock_set');
  ok(sd.length === 1 && sd[0].p_date === '2026-09-15' && sd[0].p_reason === 'test: wrong month was closed', 'lock date call: ' + JSON.stringify(sd));
  await p.fill('#pl_ld', ''); await p.fill('#pl_lr', ''); await p.click('[data-act=pl_setdate]'); await wait(p, 500);
  sd = await calls(p, 'period_lock_set');
  ok(sd.length === 2 && sd[1].p_date === null && sd[1].p_reason === null, 'clearing sends a null date');
  // lock rules: switching to auto needs the day, the day goes first
  await p.selectOption('#pl_mode', 'auto'); await p.fill('#pl_day', ''); await p.click('[data-act=pl_savepolicy]'); await wait(p, 300);
  ok((await calls(p, 'period_lock_policy_set')).length === 0 && /Set the automatic lock day first/.test(await toastText(p)), 'auto without a day is not sent');
  await p.fill('#pl_day', '10'); await p.selectOption('#pl_om', 'reason'); await p.selectOption('#pl_bw', 'reason_always'); await p.fill('#pl_min', '30'); await p.click('[data-act=pl_savepolicy]'); await wait(p, 600);
  let pp = await calls(p, 'period_lock_policy_set');
  ok(pp.length === 5 && pp[0].p_key === 'auto_lock_day' && pp[0].p_value === 10 && pp[1].p_key === 'period_lock_mode' && pp[1].p_value === 'auto' && pp[2].p_key === 'owner_closed_period_mode' && pp[2].p_value === 'reason'
    && pp[3].p_key === 'lock_backward_policy' && pp[3].p_value === 'reason_always' && pp[4].p_key === 'period_override_default_minutes' && pp[4].p_value === 30, 'rules sent in order: ' + JSON.stringify(pp.map((x) => x.p_key + '=' + x.p_value)));

  // ---- Override tab
  await p.click('[data-act=pl_tab][data-v=override]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.pl-win').count() === 1 && /test_staff_a/.test(t) && /used 2 time/.test(t) && /test: late paper bill/.test(t), 'open window listed with person, uses and reason');
  await p.fill('#ov_from', '2026-09-01'); await p.fill('#ov_to', '2026-09-05'); await p.click('[data-act=pl_ovstart]'); await wait(p, 300);
  ok((await calls(p, 'period_override_start')).length === 0 && /Write a reason/.test(await toastText(p)), 'no window without a reason');
  await p.fill('#ov_reason', 'test: month-end paper bill'); await p.fill('#ov_from', ''); await p.click('[data-act=pl_ovstart]'); await wait(p, 300);
  ok((await calls(p, 'period_override_start')).length === 0, 'no window without dates');
  await p.fill('#ov_from', '2026-09-01'); await p.fill('#ov_min', '30'); await p.selectOption('#ov_scope', 'both'); await p.selectOption('#ov_doc', 'cash_move'); await p.selectOption('#ov_user', { index: 0 });
  await p.click('[data-act=pl_ovstart]'); await wait(p, 500);
  const os = await calls(p, 'period_override_start');
  ok(os.length === 1 && os[0].p_reason === 'test: month-end paper bill' && os[0].p_from === '2026-09-01' && os[0].p_to === '2026-09-05' && os[0].p_minutes === 30 && os[0].p_scope === 'both' && os[0].p_doc === 'cash_move' && os[0].p_for_user === null, 'window call: ' + JSON.stringify(os));
  await p.click('.pl-win[data-id="5"] [data-act=pl_ovend]'); await wait(p, 500);
  const oe = await calls(p, 'period_override_end');
  ok(oe.length === 1 && oe[0].p_id === 5 && oe[0].p_note === 'test reason', 'end call');
  await noOverflow(p, 'override'); await p.screenshot({ path: SP + '/pl_override.png', fullPage: true });

  // ---- Back-dating tab
  await p.click('[data-act=pl_tab][data-v=backdate]'); await wait(p, 600);
  t = await text(p);
  ok(await p.locator('.pl-bd').count() === 4 && await p.locator('#bd_cash_move').inputValue() === '7' && await p.locator('#bd_purchase').inputValue() === '', 'four limits, blank = no limit');
  ok(await p.locator('.pl-late-row').count() === 1 && /12 records, latest 9 days late/.test(t), 'lateness report shown');
  await p.fill('#bd_purchase', '30'); await p.click('.pl-bd[data-k=purchase] [data-act=pl_bdsave]'); await wait(p, 500);
  await p.fill('#bd_cash_move', ''); await p.click('.pl-bd[data-k=cash_move] [data-act=pl_bdsave]'); await wait(p, 500);
  await p.fill('#bd_expense', '-3'); await p.click('.pl-bd[data-k=expense] [data-act=pl_bdsave]'); await wait(p, 300);
  pp = (await calls(p, 'period_lock_policy_set')).slice(5);
  ok(pp.length === 2 && pp[0].p_key === 'backdate_max_days_purchase' && pp[0].p_value === 30 && pp[1].p_key === 'backdate_max_days_cash_move' && pp[1].p_value === null, 'limit saved as a number, blank as null; a negative is not sent: ' + JSON.stringify(pp));
  await p.fill('#lr_days', '14'); await p.click('[data-act=pl_lateshow]'); await wait(p, 400);
  const lr = await calls(p, 'period_lateness_report');
  ok(lr.length >= 2 && lr[lr.length - 1].p_days === 14, 'report asked for 14 days');
  await noOverflow(p, 'backdate'); await p.screenshot({ path: SP + '/pl_backdate.png', fullPage: true });

  // ---- Late sales tab
  await p.click('[data-act=pl_tab][data-v=late]'); await wait(p, 600);
  t = await text(p);
  ok(await p.locator('.pl-held').count() === 2 && /96 hours late/.test(t) && /72 hours/.test(t) && /test: seen on the sheet/.test(t), 'held sales and the limit shown');
  ok(await p.locator('.pl-held[data-id="3"] [data-act=pl_rel]').count() === 3 && await p.locator('.pl-held[data-id="2"] [data-act=pl_rel]').count() === 0, 'only a held sale has the three decisions');
  await p.selectOption('#pl_lp', 'park'); await p.click('[data-act=pl_savelate]'); await wait(p, 500);
  pp = (await calls(p, 'period_lock_policy_set')).slice(7);
  ok(pp.length === 1 && pp[0].p_key === 'late_sale_policy' && pp[0].p_value === 'park', 'policy saved');
  await p.click('.pl-held[data-id="3"] [data-act=pl_rel][data-a=accept]'); await wait(p, 500);
  await p.click('.pl-held[data-id="3"] [data-act=pl_rel][data-a=redate]'); await wait(p, 500);
  await p.click('.pl-held[data-id="3"] [data-act=pl_rel][data-a=reject]'); await wait(p, 500);
  const rl = await calls(p, 'late_sale_release');
  ok(rl.length === 3 && rl.map((x) => x.p_action).join() === 'accept,redate,reject' && rl.every((x) => x.p_id === 3 && x.p_reason === 'test reason'), 'three decisions each with the reason: ' + JSON.stringify(rl));
  await noOverflow(p, 'late'); await p.screenshot({ path: SP + '/pl_late.png', fullPage: true });
  // a decision without a reason is not sent
  const p2 = await page('#/periodlock', {}, { prompt: '' });
  await p2.click('[data-act=pl_tab][data-v=late]'); await wait(p2, 500);
  await p2.click('.pl-held[data-id="3"] [data-act=pl_rel][data-a=accept]'); await wait(p2, 400);
  ok((await calls(p2, 'late_sale_release')).length === 0 && /Write a reason/.test(await toastText(p2)), 'no decision without a reason');

  // ---- Accounting tab
  await p.click('[data-act=pl_tab][data-v=books]'); await wait(p, 500);
  ok(/Accounting is ON/.test(await text(p)), 'accounting state');
  await p.click('[data-act=pl_prevgo]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('#pl_prev').count() === 1 && /Documents that would be posted/.test(t) && /14/.test(t) && /Skipped because their date is closed/.test(t), 'backlog preview shown');
  await p.click('[data-act=pl_accset]'); await wait(p, 500);
  const ac = await calls(p, 'accounting_on_set');
  ok(ac.length === 1 && ac[0].p_on === false && ac[0].p_reason === 'test reason', 'switch off sends the reason');
  await p.check('#pl_g1'); await p.check('#pl_g2'); await p.click('[data-act=pl_saveguards]'); await wait(p, 600);
  pp = (await calls(p, 'period_lock_policy_set')).slice(8);
  ok(pp.length === 2 && pp[0].p_key === 'start_date_lock_after_opening' && pp[0].p_value === true && pp[1].p_key === 'accounting_on_needs_reason' && pp[1].p_value === true, 'guards saved');
  await noOverflow(p, 'books'); await p.screenshot({ path: SP + '/pl_books.png', fullPage: true });

  // ---- Log tab
  await p.click('[data-act=pl_tab][data-v=log]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.pl-logwin').count() === 1 && await p.locator('.pl-logex').count() === 1 && await p.locator('.pl-logau').count() === 1 && /period_lock_exception/.test(t) && /period_override_used/.test(t), 'log shows windows, exceptions and audit lines');
  await noOverflow(p, 'log');

  // ---- server errors in plain English
  const p3 = await page('#/periodlock', {}, { err: { period_lock_set: 'lock_backward_needs_reason', period_override_start: 'period_closed_reason_required' } });
  await p3.fill('#pl_ld', '2026-09-01'); await p3.click('[data-act=pl_setdate]'); await wait(p3, 500);
  ok(/needs a written reason/.test(await toastText(p3)), 'server refusal shown in English: ' + await toastText(p3));

  // ---- a non-owner
  const p4 = await page('#/periodlock', { period_lock_state: Object.assign({}, STATE, { owner: false, open_windows: [], my_windows: [{ id: 7, scope: 'lock', from: '2026-09-01', to: '2026-09-02', doc: null, expires_at: '2026-10-16T12:00:00Z', reason: 'test: for me' }] }) }, { owner: false });
  t = await text(p4);
  ok(await p4.locator('#pl_tabs button').count() === 1 && await p4.locator('#pl_setdate').count() === 0 && await p4.locator('#pl_policy').count() === 0 && /Your open override windows/.test(t) && /test: for me/.test(t), 'a non-owner sees the state and own windows only');
  await noOverflow(p4, 'non-owner');

  // ---- no demo names, only English labels
  ok(!/[ঀ-৿]/.test(await text(p)), 'English labels only');
  ok(errors.length === 0, 'console errors: ' + errors.join(' | '));
  await br.close(); srv.close();
  log(bad ? 'periodlock_test: ' + bad + ' FAILED of ' + total : 'periodlock_test: all ' + total + ' assertions passed (0 failures, no console errors)');
  process.exit(bad ? 1 : 0);
} catch (e) { console.log('periodlock_test crashed:', e); try { srv.close(); } catch (x) {} process.exit(2); } })();
