// Opening dues and payables web piece (#/openparties): customer and supplier lists with the difference column, type / change-with-reason sheets, paste import (check first, all or nothing),
// the opening-screen sections, changes with approve / reject, the gate with causes and the fill from the journal, the three settings (owner edits, others read), English labels, 360px width.
// Run: node openparties_test.js <abs tests/web dir>       (web/openparties.js is injected into index.html here; the integrator adds the real <script> tag and the registry line)
// The server functions are mocked: this test checks the screen, supabase/phase88_test.sql checks the database. Screenshots go to OP_SHOTS if that variable is set (never into the repository).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8561, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);   // serves THIS checkout's web/
const EXTRA_SRC = (K) => `(function(){ const K = ${JSON.stringify(K)}; const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__OP = window.__OP || {};
 R.calls = R.calls || []; R.o = R.o || {};
 c.rpc = async (fn, args) => {
  if (!/^(w1a_|set_rule$)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  const O = R.o;
  if (O.missing) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + fn } };
  if (O.err && O.err[fn]) return { data: null, error: { message: O.err[fn], code: 'P0001' } };
  if (fn === 'w1a_open_state') return { data: Object.assign({}, K.ST, O.state || {}), error: null };
  if (fn === 'w1a_open_list') return { data: args.p_kind === 'supplier' ? K.SUP : K.CUST, error: null };
  if (fn === 'w1a_open_set') return { data: { kind: args.p_kind, old: null, new: args.p_amount }, error: null };
  if (fn === 'w1a_open_adjust') return { data: { id: 1, status: O.adjStatus || 'approved' }, error: null };
  if (fn === 'w1a_open_import') {
    if (!args.p_dry) return { data: { dry: false, changed: args.p_rows.length, created: 0, unchanged: 0, total_new: 0 }, error: null };
    const rows = args.p_rows.map((r, i) => ({ i: i + 1, status: O.badRow === i + 1 ? 'unknown_party' : 'ok', name: r.name || r.mobile, new: Number(r.amount) })); const er = rows.filter((r) => r.status !== 'ok').length;
    return { data: { dry: true, kind: args.p_kind, ok: rows.length - er, same: 0, create: 0, errors: er, total_new: rows.reduce((s, r) => s + (r.new || 0), 0), rows }, error: null };
  }
  if (fn === 'w1a_open_json') return { data: K.JSON, error: null };
  if (fn === 'w1a_open_precheck') return { data: K.PRE, error: null };
  if (fn === 'w1a_open_adjust_list') return { data: K.ADJ, error: null };
  if (fn === 'w1a_open_adjust_decide') return { data: { id: args.p_id, status: args.p_approve ? 'approved' : 'rejected' }, error: null };
  if (fn === 'w1a_party_gate') return { data: O.red ? K.RED : K.GREEN, error: null };
  if (fn === 'w1a_open_from_journal') return { data: { dry: !!args.p_dry, entry_id: 3, rows: [], filled: 1, same: 2, conflicts: 0 }, error: null };
  if (fn === 'set_rule') return { data: null, error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;
const ST = (o) => Object.assign({ link: true, freeze: 'off', adjust_mode: 'direct', batch_exists: false, batch_at: null, frozen: false, accounting_start: '2026-10-01', can_manage: true, is_owner: true, all_places: true,
  customers_typed: 2, customers_typed_total: 700, suppliers_typed: 1, suppliers_typed_total: 300, pending_adjustments: 0 }, o || {});
const CUST = { kind: 'customer', link: true, frozen: false, has_more: false, rows: [
  { id: '11111111-0000-0000-0000-000000000001', name: 'test_cust_one', mobile: '01800000001', active: true, opening: 500, opening_date: '2026-10-01', journal_opening: 500, journal_balance: 500, subledger_balance: 500, difference: 0 },
  { id: '11111111-0000-0000-0000-000000000002', name: 'test_cust_two', mobile: '01800000002', active: true, opening: null, opening_date: null, journal_opening: 0, journal_balance: 150, subledger_balance: 0, difference: 150 } ] };
const SUP = { kind: 'supplier', link: true, frozen: false, has_more: false, rows: [{ id: '22222222-0000-0000-0000-000000000001', name: 'test_sup_one', mobile: null, active: true, opening: 300, opening_date: null, journal_opening: 300, journal_balance: 300, subledger_balance: 300, difference: 0 }] };
const RULES = [
  { key: 'open_parties_link', kind: 'switch', value: null, default_value: false, choices: null, label_en: 'Count opening dues in customer balances', hint_en: 'OFF = as today.' },
  { key: 'open_parties_freeze', kind: 'choice', value: null, default_value: 'off', choices: ['off', 'after_opening'], label_en: 'Lock opening dues after the opening batch', hint_en: 'off = changes are allowed as today.' },
  { key: 'open_parties_adjust_mode', kind: 'choice', value: null, default_value: 'direct', choices: ['direct', 'approval'], label_en: 'Who decides a change of an opening due', hint_en: 'direct = made with a reason.' }];
const ADJ = { rows: [
  { id: 7, kind: 'customer', party_id: 'p', party_name: 'test_cust_one', old_amount: 500, new_amount: 560, delta: 60, reason: 'paper corrected', mode: 'approval', status: 'pending', requested_by: 'u', decided_by: null, decision_note: null, journal_entry_id: null, can_decide: true },
  { id: 6, kind: 'supplier', party_id: 'q', party_name: 'test_sup_one', old_amount: 300, new_amount: 280, delta: -20, reason: 'statement', mode: 'direct', status: 'approved', requested_by: 'u', decided_by: 'u', decision_note: 'direct', journal_entry_id: 41, can_decide: false }] };
const GREEN = { status: 'green', link: true, start: '2026-10-01', customers: [], suppliers: [], customers_off: 0, suppliers_off: 0, unattributed_receivable: 0 };
const RED = { status: 'red', link: true, start: '2026-10-01', customers_off: 1, suppliers_off: 0, unattributed_receivable: 0, suppliers: [],
  customers: [{ party_id: '11111111-0000-0000-0000-000000000002', name: 'test_cust_two', journal: 400, existing: 90, advance_applied: 0, difference: 310, unexplained: 310, typed_opening: 0, journal_opening: 310, cause: 'opening_in_books_not_in_subledger' }] };
const JSON_ = { batch_exists: false, customer_dues: [{ customer_id: 'a', amount: '500' }], supplier_dues: [{ supplier_id: 'b', amount: '300' }], not_postable: [{ kind: 'supplier', party_id: 'c', name: 'test_sup_neg', amount: -40, why: 'a supplier who owes us cannot go in supplier_dues' }] };
const PRE = { rows: [{ kind: 'customer', party_id: 'x', name: 'test_cust_one', json_amount: 510, typed: 500, status: 'differs' }], link: true, differing: 1 };
const K = { ST: ST(), CUST, SUP, ADJ, GREEN, RED, JSON: JSON_, PRE };
const EXTRA = EXTRA_SRC(K);

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    // the integrator adds this one registry line to web/ia.js (docs/integration/W1-A.md); the test injects the same line
    await p.route('**/ia.js', async (r) => { const res = await r.fetch(); const body = (await res.text()).replace("  rec('restoredrill',", "  rec('openparties', 'acc', ['Opening dues and payables', 'Opening dues and payables', 'Opening dues and payables'], { icon: 'book', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['opening dues', 'opening balance', 'old dues', 'customer due', 'supplier payable', 'import dues'] }),\n  rec('restoredrill',"); await r.fulfill({ response: res, body }); });
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/openparties\.js/.test(h) ? h : h.replace('</body>', '<script src="openparties.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {}); data.tables.rules = (data.tables.rules || []).filter((x) => !/^open_parties_/.test(x.key)).concat(RULES);
    const opx = { calls: [], o: o.o || {} };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__OP=${JSON.stringify(opx)};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__OP.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const shot = async (p, n) => { if (process.env.OP_SHOTS) await p.screenshot({ path: process.env.OP_SHOTS + '/' + n + '.png', fullPage: true }); };
  const click = async (p, sel) => { await p.click(sel); await wait(p, 350); };
  let p;

  // ---- 1. customers: header, list with the difference column, type sheet
  p = await open('#/openparties', { o: {} });
  let t = await text(p);
  ok(/Opening dues and payables/.test(await p.locator('h1').textContent()), 'title (English)');
  ok(await p.locator('#op_head').count() === 1 && /Opening batch not posted yet/.test(t) && /Customers with an opening: 2/.test(t), 'header shows the batch state and the typed counts');
  ok(await p.locator('.op-row').count() === 2 && /test_cust_one/.test(t) && /01800000001/.test(t), 'two customer rows with the mobile (manager)');
  ok(await p.locator('.op-row[data-id$="0002"] .op-diff.bad').count() === 1 && await p.locator('.op-row[data-id$="0001"] .op-diff.bad').count() === 0, 'the difference column is red only for the party that differs');
  ok(/150\.00/.test(await p.locator('.op-row[data-id$="0002"] .op-diff').innerText()), 'the difference figure is shown (150.00)');
  ok(await p.locator('[data-act=op_type]').count() === 2 && await p.locator('[data-act=op_change]').count() === 0, 'before the opening batch the button is "Type opening"');
  ok(await p.locator('#op_linkoff').count() === 0, 'no switch-off warning while the link is ON');
  ok((await calls(p, 'w1a_open_state')).length === 1 && (await calls(p, 'w1a_open_list')).length === 1 && (await calls(p, 'w1a_open_list'))[0].p_kind === 'customer', 'one state call and one list call');
  await noOverflow(p, 'customers'); await shot(p, 'op_customers');
  await click(p, '.op-row[data-id$="0002"] [data-act=op_type]');
  ok(await p.locator('#ty_amt').count() === 1, 'type sheet opens');
  await p.fill('#ty_amt', 'abc'); await click(p, '[data-act=op_typego]');
  ok((await calls(p, 'w1a_open_set')).length === 0, 'a bad amount is not sent');
  await p.fill('#ty_amt', '১২৫০.৫০'); await p.fill('#ty_note', 'paper page 4'); await click(p, '[data-act=op_typego]');
  let sc = await calls(p, 'w1a_open_set');
  ok(sc.length === 1 && sc[0].p_kind === 'customer' && sc[0].p_party === '11111111-0000-0000-0000-000000000002' && sc[0].p_amount === 1250.5 && sc[0].p_note === 'paper page 4', 'the opening is sent with Latin digits, the party id and the note');

  // ---- 2. switch OFF warning, and suppliers tab
  p = await open('#/openparties', { o: { state: { link: false } } });
  ok(await p.locator('#op_linkoff').count() === 1 && /NOT counted yet/.test(await text(p)), 'link OFF: the warning says the typed dues are not counted yet');
  await click(p, '[data-act=op_tab][data-v=suppliers]');
  ok(await p.locator('.op-row').count() === 1 && /test_sup_one/.test(await text(p)) && (await calls(p, 'w1a_open_list')).pop().p_kind === 'supplier', 'suppliers tab lists suppliers');
  await noOverflow(p, 'suppliers');

  // ---- 3. after the batch: change with a reason
  p = await open('#/openparties', { o: { state: { batch_exists: true, customers_typed: 2 } } });
  ok(await p.locator('[data-act=op_change]').count() === 2 && await p.locator('[data-act=op_type]').count() === 0, 'after the batch the button is "Change with reason"');
  await click(p, '.op-row[data-id$="0001"] [data-act=op_change]');
  await p.fill('#ch_amt', '520'); await click(p, '[data-act=op_changego]');
  ok((await calls(p, 'w1a_open_adjust')).length === 0, 'no reason = nothing is sent');
  await p.fill('#ch_why', 'ab'); await click(p, '[data-act=op_changego]');
  ok((await calls(p, 'w1a_open_adjust')).length === 0, 'a 2-character reason is not a reason');
  await p.fill('#ch_why', 'paper ledger corrected'); await click(p, '[data-act=op_changego]');
  const ac = await calls(p, 'w1a_open_adjust');
  ok(ac.length === 1 && ac[0].p_new === 520 && ac[0].p_reason === 'paper ledger corrected' && ac[0].p_kind === 'customer' && /^[0-9a-f-]{36}$/.test(ac[0].p_client), 'the change is sent with the reason and a client id');
  ok(await p.locator('#ty_amt').count() === 0 && await p.locator('#ch_why').count() === 0, 'the sheet closes after the change');
  p = await open('#/openparties', { o: { state: { batch_exists: true, adjust_mode: 'approval' }, adjStatus: 'pending' } });
  await click(p, '.op-row[data-id$="0001"] [data-act=op_change]');
  ok(/second person must approve/.test(await text(p)) && /Ask for approval/.test(await text(p)), 'approval mode: the sheet says a second person must approve');

  // ---- 4. paste import
  p = await open('#/openparties', { o: {} });
  await click(p, '[data-act=op_tab][data-v=import]');
  ok(await p.locator('#im_text').count() === 1 && await p.locator('#op_imgo').count() === 0, 'import tab: textarea, no Import button before a check');
  await p.fill('#im_text', 'mobile,amount\n01800000001, 500\n০১৮০০০০০০০২;৭৫০;2026-10-01\ntest_cust_three, 1200.50');
  await click(p, '[data-act=op_imcheck]');
  let ic = await calls(p, 'w1a_open_import');
  ok(ic.length === 1 && ic[0].p_dry === true && ic[0].p_rows.length === 3, 'Check sends a dry run of 3 rows (the header line is skipped)');
  ok(ic[0].p_rows[0].mobile === '01800000001' && ic[0].p_rows[0].amount === '500' && ic[0].p_rows[1].mobile === '০১৮০০০০০০০২' && ic[0].p_rows[1].amount === '750' && ic[0].p_rows[1].date === '2026-10-01'
    && ic[0].p_rows[2].name === 'test_cust_three' && ic[0].p_rows[2].amount === '1200.50', 'rows are read: mobile or name, amount with Latin digits and no thousands comma, optional date');
  ok(await p.locator('#op_imres').count() === 1 && await p.locator('#op_imgo').count() === 1 && /Import 3 row/.test(await text(p)), 'a clean check shows the Import button with the count');
  await noOverflow(p, 'import');
  await p.fill('#im_text', '01800000001, 999'); await click(p, '#op_imgo');
  ic = await calls(p, 'w1a_open_import');
  ok(ic.length === 1, 'editing the list after the check: Import refuses to send (check again first)');
  await click(p, '[data-act=op_imcheck]'); await click(p, '#op_imgo');
  ic = await calls(p, 'w1a_open_import');
  ok(ic.length === 3 && ic[2].p_dry === false && ic[2].p_rows.length === 1 && ic[2].p_rows[0].amount === '999', 'after a new check the real import is sent once, not a dry run');
  p = await open('#/openparties', { o: { badRow: 2 } });
  await click(p, '[data-act=op_tab][data-v=import]');
  await p.fill('#im_text', '01800000001, 5\n01800000002, 6'); await click(p, '[data-act=op_imcheck]');
  ok(await p.locator('#op_imgo').count() === 0 && /1 not valid/.test(await text(p)) && /not found/.test(await text(p)), 'a check with a bad row: no Import button, the reason is shown');
  // the opening screen sections
  await click(p, '[data-act=op_json]');
  ok(/1 customer line/.test(await text(p)) && /1 supplier line/.test(await text(p)) && /1 cannot be posted here/.test(await text(p)) && /"customer_dues"/.test(await p.locator('#op_jsonout').inputValue()), 'the opening sections are shown with the not-postable count');
  await p.fill('#pc_text', 'not json'); await click(p, '[data-act=op_precheck]');
  ok((await calls(p, 'w1a_open_precheck')).length === 0, 'a broken JSON is not sent');
  await p.fill('#pc_text', '{"customer_dues":[]}'); await click(p, '[data-act=op_precheck]');
  ok((await calls(p, 'w1a_open_precheck')).length === 1 && /1 differ/.test(await text(p)) && /differs/.test(await text(p)), 'the comparison shows what differs');
  await noOverflow(p, 'import results'); await shot(p, 'op_import');

  // ---- 5. changes
  p = await open('#/openparties', { o: {} });
  await click(p, '[data-act=op_tab][data-v=changes]');
  ok(await p.locator('.op-adj').count() === 2 && /paper corrected/.test(await text(p)) && /journal #41/.test(await text(p)), 'changes list with reasons and the journal number');
  ok(await p.locator('.op-adj[data-id="7"] [data-act=op_decide]').count() === 2, 'a pending change that this person may decide has Approve and Reject');
  await click(p, '.op-adj[data-id="7"] [data-act=op_decide][data-ok="0"]');
  await click(p, '[data-act=op_decidego]');
  ok((await calls(p, 'w1a_open_adjust_decide')).length === 0, 'reject without a reason is not sent');
  await p.fill('#dc_note', 'not supported'); await click(p, '[data-act=op_decidego]');
  const dc = await calls(p, 'w1a_open_adjust_decide');
  ok(dc.length === 1 && dc[0].p_id === 7 && dc[0].p_approve === false && dc[0].p_note === 'not supported', 'reject is sent with the note');
  await noOverflow(p, 'changes'); await shot(p, 'op_changes');

  // ---- 6. gate
  p = await open('#/openparties', { o: { red: true } });
  await click(p, '[data-act=op_tab][data-v=gate]');
  ok(await p.locator('#op_gatebanner').count() === 0, 'the gate does not run by itself');
  await click(p, '[data-act=op_gate]');
  ok(await p.locator('#op_gatebanner[data-status=red]').count() === 1 && /RED: 1 party/.test(await text(p)) && /in the books but not in the sub-ledger/.test(await text(p)) && /310\.00/.test(await text(p)), 'red gate: the party, the difference and the cause in words');
  p = await open('#/openparties', { o: { red: true, state: { batch_exists: true } } });
  await click(p, '[data-act=op_tab][data-v=gate]'); await click(p, '[data-act=op_gate]');
  await click(p, '[data-act=op_fillcheck]');
  ok((await calls(p, 'w1a_open_from_journal')).length === 1 && (await calls(p, 'w1a_open_from_journal'))[0].p_dry === true && /1 would be filled/.test(await text(p)), 'the fill is checked first (dry run)');
  await click(p, '[data-act=op_fillgo]');
  const fj = await calls(p, 'w1a_open_from_journal');
  ok(fj.length === 2 && fj[1].p_dry === false, 'the fill is applied after the check');
  await noOverflow(p, 'gate'); await shot(p, 'op_gate_red');
  p = await open('#/openparties', { o: {} });
  await click(p, '[data-act=op_tab][data-v=gate]'); await click(p, '[data-act=op_gate]');
  ok(await p.locator('#op_gatebanner[data-status=green]').count() === 1 && /All parties agree/.test(await text(p)), 'green gate');

  // ---- 7. settings: owner edits, others read
  p = await open('#/openparties', { o: {} });
  await click(p, '[data-act=op_tab][data-v=settings]');
  ok(await p.locator('.op-rule').count() === 3 && /Count opening dues in customer balances/.test(await text(p)) && /Every change is written to the change log/.test(await text(p)), 'three settings with their English labels');
  await p.check('#rl_open_parties_link'); await click(p, '.op-rule[data-key=open_parties_link] [data-act=op_rulesave]');
  await p.selectOption('#rl_open_parties_freeze', 'after_opening'); await click(p, '.op-rule[data-key=open_parties_freeze] [data-act=op_rulesave]');
  const sr = await calls(p, 'set_rule');
  ok(sr.length === 2 && sr[0].p_key === 'open_parties_link' && sr[0].p_value === true && sr[1].p_key === 'open_parties_freeze' && sr[1].p_value === 'after_opening', 'the owner saves the switch (true) and the choice (text) through set_rule');
  await noOverflow(p, 'settings'); await shot(p, 'op_settings');
  p = await open('#/openparties', { owner: false, o: { state: { is_owner: false } } });
  await click(p, '[data-act=op_tab][data-v=settings]');
  ok(await p.locator('[data-act=op_rulesave]').count() === 0 && /Only the owner changes this/.test(await text(p)), 'a non-owner sees the settings but has no Save button');

  // ---- 8. not installed / denied / no manage right
  p = await open('#/openparties', { o: { missing: true } });
  ok(/phase88\.sql has not been run/.test(await text(p)), 'friendly message when phase88 is not installed');
  p = await open('#/openparties', { o: { err: { w1a_open_state: 'not allowed' } } });
  ok(/do not have permission/.test(await text(p)), 'denied message');
  p = await open('#/openparties', { o: { state: { can_manage: false } } });
  ok(await p.locator('[data-act=op_type]').count() === 0 && await p.locator('[data-act=op_change]').count() === 0 && await p.locator('.op-row').count() === 2, 'a viewer without Accounts manage sees the lists but no change buttons');

  // ---- 9. Bangla and mix modes still render (English labels only for now) and nothing overflows at 360px
  p = await open('#/openparties', { lang: 'bn', o: {} });
  ok(/Opening dues and payables/.test(await p.locator('h1').textContent()), 'bn mode: the English title is shown (labels are English only for now)');
  await noOverflow(p, 'bn');
  p = await open('#/openparties', { lang: 'mix', o: {} });
  await noOverflow(p, 'mix');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
