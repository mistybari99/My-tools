// Return & exit rules page (#/returnrules): sale return control (class rules, general rules, report) and staff exit (mode, statuses, keep access, log).
// Server calls are stand-ins; the real SQL is tested in supabase/phase90_test.sql and supabase/phase91_test.sql.
// Covers: owner sees and saves the rules (arguments checked), invalid input stopped before the server, a person without the right sees a notice and no data,
// server refusals shown in words, the keep-access flow with a reason, the report, the picker helper for salereturn.js, 360px width, no console errors.
// Run: node returnrules_test.js <abs tests/web dir> [shots dir]     (serves ../../web of THIS checkout and injects the script tag; the route is not in ia.js yet)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web'); const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = 8497;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from((b.toString('utf8').includes('src="returnrules.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="returnrules.js"></script></body>')));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const day = new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const CLASSES = [
  { class_code: 'test_perish', items: 12, sample_en: 'test_item_a', sample_bn: 'test_item_a', configured: false, restock: 'restock', window_hours: null, receipt_required: null, effective_from: null, active: false, note: null, perishable: true },
  { class_code: 'test_dry', items: 5, sample_en: 'test_item_b', sample_bn: 'test_item_b', configured: false, restock: 'restock', window_hours: null, receipt_required: null, effective_from: null, active: false, note: null, perishable: false },
  { class_code: 'test_boxed', items: 3, sample_en: 'test_item_c', sample_bn: 'test_item_c', configured: true, restock: 'no_restock', window_hours: 48, receipt_required: true, effective_from: '2026-01-01', active: true, note: 'owner confirmed', perishable: true }];
const SETTINGS = { needs_receipt: false, window_hours: null, expired_mode: 'allow', classes: CLASSES };
const EXIT = { mode: 'off', statuses: ['resigned', 'terminated', 'retired'], alert_hours: null, devices: false, can_keep: true, is_owner: true, allowed_statuses: ['resigned', 'terminated', 'retired', 'on_leave'] };
const OPEN = [{ employee_id: 'em1', employee_no: 'E-1', name_en: 'test_staff_one', name_bn: 'test_staff_one', status: 'resigned', status_date: day, staff_id: 'test01', login_status: 'active', kept: false, kept_reason: null },
  { employee_id: 'em2', employee_no: 'E-2', name_en: 'test_staff_two', name_bn: 'test_staff_two', status: 'terminated', status_date: day, staff_id: 'test02', login_status: 'active', kept: true, kept_reason: 'handover of the till' }];
const LOG = [{ id: 2, at: day + 'T10:00:00Z', employee_id: 'em1', employee_no: 'E-1', name_en: 'test_staff_one', from: 'active', to: 'resigned', action: 'revoked', grants_ended: 2, lists_ended: 0, devices_off: 0, reason: 'left' },
  { id: 1, at: day + 'T09:00:00Z', employee_id: 'em2', employee_no: 'E-2', name_en: 'test_staff_two', from: 'active', to: 'terminated', action: 'kept', grants_ended: 0, lists_ended: 0, devices_off: 0, reason: 'handover' }];
const REPORT = { from: day, to: day, by_reason: [{ reason: 'damaged', class: 'test_perish', returns: 2, lines: 2, restocked_qty: 1, written_off_qty: 3, written_off_value: 300 }], overrides: [{ return_id: 'r1', at: day + 'T11:00:00Z', kinds: ['return_window_exceeded'], reason: 'regular customer', by: 'u1' }], not_covered: 2 };
function mk(o = {}) { return C.mkData(base, o); }
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.rr = Object.assign({ err: {}, settings: ${JSON.stringify(SETTINGS)}, exit: ${JSON.stringify(EXIT)}, open: ${JSON.stringify(OPEN)}, log: ${JSON.stringify(LOG)}, report: ${JSON.stringify(REPORT)} }, window.__W || {});
 c.rpc = async (fn, args) => {
  if (!/^_w1c_/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === '_w1c_return_settings' || fn === '_w1c_return_global_set') return { data: clone(W.settings), error: null };
  if (fn === '_w1c_exit_settings' || fn === '_w1c_exit_settings_set') return { data: clone(W.exit), error: null };
  if (fn === '_w1c_exit_open_list') return { data: clone(W.open), error: null };
  if (fn === '_w1c_exit_log_list') return { data: clone(W.log), error: null };
  if (fn === '_w1c_return_report') return { data: clone(W.report), error: null };
  if (fn === '_w1c_exit_scan') return { data: W.scan || { raised: 1, hours: 24 }, error: null };
  return { data: { ok: true }, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } else if (process.env.DBG) log('ok:', m); };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__W=${JSON.stringify(o.w || {})};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const txt = (p, s) => p.textContent(s);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth); ok(r <= 1, 'no horizontal scroll at 360px: ' + m + ' (' + r + ')'); };

  // ---- return rules tab
  let p = await open({}, '#/returnrules');
  let t = await txt(p, '#rr_body');
  ok(/Return rules/.test(t) && /Staff exit/.test(t) && /Returns report/.test(t), 'three tabs');
  ok(await p.locator('[data-class]').count() === 3, 'three item classes listed');
  ok(!(await p.isChecked('#rr_receipt')) && (await p.inputValue('#rr_window')) === '' && (await p.inputValue('#rr_exp')) === 'allow', 'general rules show today: receipt off, no window, expired = allow');
  ok(/No rule: goods go back on the shelf, any age, no receipt \(today\)/.test(await txt(p, '[data-class="test_dry"] [data-sum]')), 'a class without a rule says what happens today');
  ok(/Never put back on the shelf: written off at once · window 48 hours · receipt needed/.test(await txt(p, '[data-class="test_boxed"] [data-sum]')), 'a configured class shows its rule in words');
  ok(await p.locator('[data-class="test_perish"] [data-act=rr_suggest]').count() === 1 && await p.locator('[data-class="test_dry"] [data-act=rr_suggest]').count() === 0 && await p.locator('[data-class="test_boxed"] [data-act=rr_suggest]').count() === 0, 'suggestion only for an unconfigured perishable class');
  await p.fill('#rr_window', '0'); await p.click('[data-act=rr_gsave]'); await wait(p, 150);
  ok(/window must be a number of hours above zero/.test(await txt(p, '#toast')) && (await calls(p, '_w1c_return_global_set')).length === 0, 'a zero window is stopped before the server');
  await p.check('#rr_receipt'); await p.fill('#rr_window', '24'); await p.selectOption('#rr_exp', 'block'); await p.click('[data-act=rr_gsave]'); await wait(p, 300);
  let c = await calls(p, '_w1c_return_global_set');
  ok(c.length === 1 && c[0].p_needs_receipt === true && c[0].p_window === 24 && c[0].p_expired === 'block', 'general rules sent: receipt on, 24 hours, block');
  await p.fill('#rr_window', ''); await p.click('[data-act=rr_gsave]'); await wait(p, 300);
  c = await calls(p, '_w1c_return_global_set'); ok(c.length === 2 && c[1].p_window === null, 'an empty window is sent as null (no limit)');
  // class edit
  await p.click('[data-class="test_dry"] [data-act=rr_edit]'); await wait(p, 150);
  ok(await p.locator('[data-panel="test_dry"]').count() === 1 && (await p.inputValue('#rr_restock')) === 'restock', 'edit panel opens with the default: put back');
  await p.selectOption('#rr_restock', 'no_restock'); await p.fill('#rr_cwin', '12'); await p.selectOption('#rr_crec', 'yes'); await p.fill('#rr_cnote', 'cakes'); await p.click('[data-act=rr_csave]'); await wait(p, 300);
  c = await calls(p, '_w1c_return_class_set');
  ok(c.length === 1 && c[0].p_class === 'test_dry' && c[0].p_restock === 'no_restock' && c[0].p_window === 12 && c[0].p_receipt === true && c[0].p_note === 'cakes' && /^\d{4}-\d\d-\d\d$/.test(c[0].p_effective), 'class rule sent with restock, window, receipt, date and note');
  await p.click('[data-class="test_dry"] [data-act=rr_edit]'); await wait(p, 150); await p.fill('#rr_cwin', 'abc'); await p.click('[data-act=rr_csave]'); await wait(p, 150);
  ok(/window must be a number of hours above zero/.test(await txt(p, '#toast')) && (await calls(p, '_w1c_return_class_set')).length === 1, 'a bad class window is stopped before the server');
  await p.click('[data-act=rr_cancel]'); await wait(p, 100);
  await p.click('[data-class="test_perish"] [data-act=rr_suggest]'); await wait(p, 150);
  ok((await p.inputValue('#rr_restock')) === 'no_restock', 'the suggestion pre-selects never put back (nothing is saved yet)');
  ok((await calls(p, '_w1c_return_class_set')).length === 1, 'suggest alone saves nothing'); await p.click('[data-act=rr_csave]'); await wait(p, 300);
  c = await calls(p, '_w1c_return_class_set'); ok(c.length === 2 && c[1].p_class === 'test_perish' && c[1].p_restock === 'no_restock' && c[1].p_window === null && c[1].p_receipt === null, 'saving the suggestion sends no_restock, no window, receipt follows the general switch');
  await p.click('[data-class="test_boxed"] [data-act=rr_off]'); await wait(p, 150); await p.fill('#rr_offreason', 'ok'); await p.click('[data-act=rr_coffgo]'); await wait(p, 150);
  ok(/Write a reason/.test(await txt(p, '#toast')) && (await calls(p, '_w1c_return_class_off')).length === 0, 'switching a rule off needs a reason of 3 letters');
  await p.fill('#rr_offreason', 'boxes are fine'); await p.click('[data-act=rr_coffgo]'); await wait(p, 300);
  c = await calls(p, '_w1c_return_class_off'); ok(c.length === 1 && c[0].p_class === 'test_boxed' && c[0].p_reason === 'boxes are fine', 'switch off sent with the reason');
  await p.screenshot({ path: OUT + '/rr_returns.png' }); await noOverflow(p, 'return rules tab'); await p.close();

  // ---- not the owner
  p = await open({ w: { err: { _w1c_return_settings: 'not allowed' } } }, '#/returnrules');
  ok(/Only the owner can change the return rules/.test(await txt(p, '#rr_body')) && await p.locator('[data-class]').count() === 0, 'a person without the right sees a notice and no rules'); await p.close();
  // ---- server refusal in words
  p = await open({ w: { err: { _w1c_return_class_set: 'unknown_class' } } }, '#/returnrules');
  await p.click('[data-class="test_dry"] [data-act=rr_edit]'); await wait(p, 150); await p.click('[data-act=rr_csave]'); await wait(p, 300);
  ok(/No item has this class/.test(await txt(p, '#toast')), 'server refusal unknown_class in words'); await p.close();

  // ---- staff exit tab
  p = await open({}, '#/returnrules'); await p.click('[data-act=rr_tab][data-v=exit]'); await wait(p, 300);
  t = await txt(p, '#rr_body');
  ok((await p.inputValue('#ex_mode')) === 'off' && await p.locator('.ex_st:checked').count() === 3 && !(await p.isChecked('#ex_dev')), 'exit settings show today: mode off, three statuses, devices off');
  ok(/Resigned/.test(t) && /On leave \(not recommended\)/.test(t), 'statuses are labelled, on leave is flagged as not recommended');
  ok(await p.locator('[data-emp]').count() === 2 && /Left but can still log in/.test(t), 'two people who left and can still log in');
  ok(await p.locator('[data-emp="em1"] [data-act=ex_keepopen][data-k=keep]').count() === 1 && await p.locator('[data-emp="em2"] [data-act=ex_keepopen][data-k=end]').count() === 1, 'keep on the first, end the keep on the kept one');
  ok(/revoked|Login disabled/.test(t) && /Access kept/.test(t), 'log shows the actions in words');
  await p.selectOption('#ex_mode', 'auto'); await p.uncheck('.ex_st[value=retired]'); await p.check('.ex_st[value=on_leave]'); await p.fill('#ex_hours', '24'); await p.check('#ex_dev'); await p.click('[data-act=ex_save]'); await wait(p, 300);
  c = await calls(p, '_w1c_exit_settings_set');
  ok(c.length === 1 && c[0].p_mode === 'auto' && c[0].p_statuses === 'resigned,terminated,on_leave' && c[0].p_alert_hours === 24 && c[0].p_devices === true, 'exit settings sent');
  await p.fill('#ex_hours', '-1'); await p.click('[data-act=ex_save]'); await wait(p, 150);
  ok(/Hours must be a number/.test(await txt(p, '#toast')) && (await calls(p, '_w1c_exit_settings_set')).length === 1, 'bad hours stopped before the server');
  await p.fill('#ex_hours', ''); for (const v of ['resigned', 'terminated', 'retired']) await p.uncheck('.ex_st[value=' + v + ']');
  await p.click('[data-act=ex_save]'); await wait(p, 150);
  ok(/Choose at least one status/.test(await txt(p, '#toast')) && (await calls(p, '_w1c_exit_settings_set')).length === 1, 'no status chosen stopped before the server');
  await p.click('[data-emp="em1"] [data-act=ex_keepopen]'); await wait(p, 150); await p.fill('#ex_reason', 'no'); await p.click('[data-act=ex_keepgo]'); await wait(p, 150);
  ok(/Write a reason/.test(await txt(p, '#toast')) && (await calls(p, '_w1c_exit_keep')).length === 0, 'keep access needs a reason');
  await p.fill('#ex_reason', 'needs the till report'); await p.click('[data-act=ex_keepgo]'); await wait(p, 300);
  c = await calls(p, '_w1c_exit_keep'); ok(c.length === 1 && c[0].p_employee === 'em1' && c[0].p_reason === 'needs the till report', 'keep access sent with the person and the reason');
  await p.click('[data-emp="em2"] [data-act=ex_keepopen]'); await wait(p, 150); await p.fill('#ex_reason', 'handover finished'); await p.click('[data-act=ex_keepgo]'); await wait(p, 300);
  c = await calls(p, '_w1c_exit_keep_end'); ok(c.length === 1 && c[0].p_employee === 'em2' && c[0].p_reason === 'handover finished', 'ending the keep sent');
  await p.click('[data-act=ex_scan]'); await wait(p, 300);
  ok((await calls(p, '_w1c_exit_scan')).length === 1 && /1 new red lines/.test(await txt(p, '#toast')), 'check now runs the scan and says how many red lines');
  await p.screenshot({ path: OUT + '/rr_exit.png' }); await noOverflow(p, 'staff exit tab'); await p.close();

  // ---- HR (not the owner): sees the rules, cannot change them, cannot keep without the right
  p = await open({ w: { exit: Object.assign({}, EXIT, { is_owner: false, can_keep: false }) } }, '#/returnrules'); await p.click('[data-act=rr_tab][data-v=exit]'); await wait(p, 300);
  ok(await p.locator('[data-act=ex_save]').count() === 0 && await p.locator('#ex_mode:disabled').count() === 1 && await p.locator('[data-act=ex_keepopen]').count() === 0, 'a non-owner without the keep right: settings read only, no keep buttons'); await p.close();
  p = await open({ w: { err: { _w1c_exit_settings: 'not allowed' } } }, '#/returnrules'); await p.click('[data-act=rr_tab][data-v=exit]'); await wait(p, 300);
  ok(/do not have permission to see the staff exit rules/.test(await txt(p, '#rr_body')) && await p.locator('[data-emp]').count() === 0, 'a cashier sees a notice, no people'); await p.close();
  p = await open({ w: { err: { _w1c_exit_keep: 'reason_required' } } }, '#/returnrules'); await p.click('[data-act=rr_tab][data-v=exit]'); await wait(p, 300);
  await p.click('[data-emp="em1"] [data-act=ex_keepopen]'); await wait(p, 150); await p.fill('#ex_reason', 'some reason'); await p.click('[data-act=ex_keepgo]'); await wait(p, 300);
  ok(/Write a reason/.test(await txt(p, '#toast')), 'server refusal reason_required in words'); await p.close();

  // ---- report tab
  p = await open({}, '#/returnrules'); await p.click('[data-act=rr_tab][data-v=report]'); await wait(p, 300);
  t = await txt(p, '#rr_body');
  ok(/Returns by reason: restocked or written off/.test(t) && /damaged/.test(t) && /test_perish/.test(t) && /300/.test(t), 'report table shows reason, class and value');
  ok(/2 returns in this period were saved without the return rules/.test(t), 'returns saved without the rules are counted and said');
  ok(/return_window_exceeded/.test(t) && /regular customer/.test(t), 'overrides listed with their reason');
  await p.fill('#rp_from', day); await p.click('[data-act=rp_go]'); await wait(p, 300);
  c = await calls(p, '_w1c_return_report'); ok(c.length >= 2 && c[c.length - 1].p_from === day && c[c.length - 1].p_loc === null, 'report asked for the chosen dates');
  await p.screenshot({ path: OUT + '/rr_report.png' }); await noOverflow(p, 'report tab'); await p.close();

  // ---- the picker for salereturn.js
  p = await open({}, '#/returnrules');
  const pk = await p.evaluate(() => {
    const pv = { lines: [{ item_id: 'it1', class: 'test_perish', qty: 3, restock_qty: 0, restock_rule: 'no_restock', receipt_needed: true }, { item_id: 'it2', class: 'test_dry', qty: 2, restock_qty: 2, restock_rule: 'restock', receipt_needed: true }],
      violations: ['return_window_exceeded'], can_override: true };
    const d = document.createElement('div'); d.id = 'pk'; d.innerHTML = window.BOS.returnRules.pickerHTML(pv, { it1: 'test_item_a', it2: 'test_item_b' }); document.body.appendChild(d);
    d.querySelector('#rrp_it2').value = '1'; d.querySelector('#rrp_receipt').value = '#123'; d.querySelector('#rrp_override').value = 'manager checked';
    return { html: d.textContent, args: window.BOS.returnRules.collect(d) };
  });
  ok(/test_item_a/.test(pk.html) && /not put back on the shelf/.test(pk.html) && /return window has passed/.test(pk.html) && /Override reason/.test(pk.html), 'picker shows the items, the class note, the rule that is broken and the override field');
  ok(pk.args.p_receipt_no === '#123' && pk.args.p_override_reason === 'manager checked' && pk.args.p_restock_lines.length === 2 && pk.args.p_restock_lines[0].restock_qty === 0 && pk.args.p_restock_lines[1].restock_qty === 1, 'collect returns restock lines, receipt and override reason for _w1c_sale_return');
  const pk2 = await p.evaluate(() => { const d = document.createElement('div'); d.innerHTML = window.BOS.returnRules.pickerHTML({ lines: [], violations: ['return_window_exceeded'], can_override: false }, {}); return d.textContent; });
  ok(/Ask a manager who holds the override right/.test(pk2) && !/Override reason/.test(pk2), 'a person without the override right is told to ask a manager, no reason field');
  await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
