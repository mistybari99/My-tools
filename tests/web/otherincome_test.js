// Other income + chart & heads + customer bank / cheque receipts (web/otherincome.js: #/otherincome and #/bankreceipt).
// Checks: tabs, switch-off notice, entry form (head, mode, payment source picker, dry run, save, void with a reason sheet), chart & heads (rename, another code, choose account, switch off with reason,
// expense head turn on with effective date and reason, other income head), coverage (ok / problems), settings (owner only, date validation, set_rule calls), bank receipts (channels follow the switch,
// payment source filtered by channel, cheque number and date, reference rule with a reason, over-due refused, collect call arguments, recent list), server error text, English labels in all three modes, 360px width.
// Run: node otherincome_test.js <abs tests/web dir>      (web/otherincome.js and the two registry lines are injected here; the integrator adds the real <script> tag and the ia.js lines)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const SHOTS = process.env.W1F_SHOTS || '/tmp/w1f_shots';
try { fs.mkdirSync(SHOTS, { recursive: true }); } catch (e) { /* ignore */ }
const base = C.baseData(SP), PORT = 8497, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__W1 = window.__W1 || {};
 R.calls = R.calls || [];
 c.rpc = async (fn, args) => {
  if (!/^(_w1f_|money_pick$|set_rule$|customer_balance$)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.err && R.err[fn]) { const m = R.err[fn]; delete R.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  if (fn === 'money_pick') { const d = (R.pick || {})[args.p_event] || (R.pick || {}).default; return d ? { data: JSON.parse(JSON.stringify(d)), error: null } : { data: null, error: { message: 'unknown_event', code: 'P0001' } }; }
  const f = R.fn && R.fn[fn];
  if (f !== undefined) return { data: JSON.parse(JSON.stringify(f)), error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;
const REG = "  rec('otherincome', 'acc', ['Other income', 'Other income', 'Other income'], { icon: 'money', ok: (c) => c.own || c.GF.cash_move === true || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['other income', 'scrap', 'old oil', 'rent received'] }),\n  rec('bankreceipt', 'cust', ['Bank & cheque receipts', 'Bank & cheque receipts', 'Bank & cheque receipts'], { icon: 'money', ok: pos, kw: ['bank receipt', 'cheque', 'bank transfer'] }),\n  rec('restoredrill',";
const ACC = (id, code, name, type) => ({ id, code, name_en: name, name_bn: name, type, normal_side: type === 'asset' || type === 'expense' ? 'debit' : 'credit', is_group: false, is_system: true, active: true, sort: id });
const COA = [ACC(1, '1110', 'Cash in hand', 'asset'), ACC(2, '5300', 'Rent', 'expense'), ACC(3, '5400', 'Utilities', 'expense'), ACC(4, '5700', 'Transport', 'expense'), ACC(5, '4900', 'Other income', 'income'), ACC(6, '4910', 'Purchase discounts received', 'income')];
const HEADS = [{ code: 'scrap_sale', label_en: 'Scrap and packaging sale', active: true, key: 'oi_scrap_sale', own_account: false, account_code: '4900', account_name: 'Other income' },
  { code: 'old_oil', label_en: 'Used cooking oil sale', active: true, key: 'oi_old_oil', own_account: false, account_code: '4900', account_name: 'Other income' },
  { code: 'supplier_discount', label_en: 'Supplier discount received in cash', active: true, key: 'oi_supplier_discount', own_account: true, account_code: '4910', account_name: 'Purchase discounts received' },
  { code: 'old_head', label_en: 'Old head', active: false, key: 'oi_old_head', own_account: false, account_code: '4900', account_name: 'Other income' }];
const OIROWS = [{ id: 'oi-1', location_id: 1, income_date: '2026-10-16', head: 'scrap_sale', head_label: 'Scrap and packaging sale', amount: 300, mode: 'cash', money_account_id: null, account_name: null, received_from: 'test_buyer', ref: 'ref1', note: 'test scrap', status: 'done', created_staff: 'test_cashier' },
  { id: 'oi-2', location_id: 1, income_date: '2026-10-15', head: 'old_oil', head_label: 'Used cooking oil sale', amount: 120, mode: 'bank', money_account_id: 3, account_name: 'test_bank_oi', received_from: null, ref: null, note: null, status: 'void', void_note: 'test wrong entry', created_staff: 'test_cashier' }];
const SEEDS = [{ key: 'courier_receivable', proposed_code: '1250', purpose: 'Cash on delivery held by couriers', status: 'created', placeholder: false, note: null, type: 'asset', mapped: true, has_account: true, account_id: 61, code: '1250', name_en: 'Courier cash receivable', name_bn: 'Courier cash receivable', active: true, has_lines: false },
  { key: 'bad_debt', proposed_code: '5890', purpose: 'Customer dues written off', status: 'code_taken', placeholder: false, note: 'code 5890 is used by another account', type: 'expense', mapped: false, has_account: false, account_id: null, code: null, name_en: null, name_bn: null, active: null, has_lines: false },
  { key: 'vat_payable', proposed_code: '2800', purpose: 'Placeholder for VAT', status: 'created', placeholder: true, note: null, type: 'liability', mapped: false, has_account: true, account_id: 68, code: '2800', name_en: 'VAT payable (not in use yet)', name_bn: 'VAT payable (not in use yet)', active: false, has_lines: false }];
const EHEADS = [{ code: 'rent', label_en: 'Rent', label_bn: 'Rent', active: false, seeded: true, effective_from: null, key: 'exp_rent', mapped: true, account_code: '5300', account_name: 'Rent', unposted: 0 },
  { code: 'utilities', label_en: 'Utilities (electricity, gas, water)', label_bn: 'x', active: false, seeded: true, effective_from: null, key: 'exp_utilities', mapped: false, account_code: null, account_name: null, unposted: 2 },
  { code: 'labour', label_en: 'Temporary labour wages', label_bn: 'x', active: true, seeded: false, effective_from: null, key: 'exp_labour', mapped: true, account_code: '5200', account_name: 'Salaries and wages', unposted: 0 }];
const PICK_OI = { event: 'other_income', default_id: null, allow_override: true, require_source: false, rows: [{ id: 1, kind: 'cash', name_en: 'test_drawer_a', provider: null, location_id: 1, account_no: '', is_default: false, mode: 'cash' }, { id: 3, kind: 'bank', name_en: 'test_bank_oi', provider: 'Test Bank', location_id: null, account_no: '70010001', is_default: false, mode: 'bank' }] };
const PICK_CC = { event: 'customer_collection', default_id: null, allow_override: true, require_source: false, rows: [{ id: 1, kind: 'cash', name_en: 'test_drawer_a', provider: null, location_id: 1, account_no: '', is_default: false, mode: 'cash' },
  { id: 2, kind: 'wallet', name_en: 'test_wallet_main', provider: 'TestPay', location_id: null, account_no: '01700000001', is_default: false, mode: 'mobile' }, { id: 3, kind: 'bank', name_en: 'test_bank_oi', provider: 'Test Bank', location_id: null, account_no: '70010001', is_default: false, mode: 'bank' }] };
const RCPTS = { rows: [{ id: 11, kind: 'collection', location_id: 1, mode: 'bank', amount: 600, paid_at: '2026-10-16T05:00:00Z', ref: null, cheque_no: 'CHQ-100', cheque_date: '2026-10-16', money_account_id: 3, account_name: 'test_bank_oi', ref_waiver: null, voided: false, customer_name: 'test_customer_97', customer_mobile: '01900000097', receipt: null, created_staff: 'test_staff' },
  { id: 12, kind: 'collection', location_id: 1, mode: 'bank', amount: 10, paid_at: '2026-10-16T06:00:00Z', ref: null, cheque_no: null, cheque_date: null, money_account_id: null, account_name: null, ref_waiver: 'test_reason_noref', voided: false, customer_name: 'test_customer_97', customer_mobile: '01900000097', receipt: null, created_staff: 'test_staff' }] };
const FN = {
  _w1f_other_income_heads: HEADS, _w1f_other_income_list: { on: false, from: null, rows: OIROWS }, _w1f_other_income_add: { id: 'oi-9', amount: 300, mode: 'cash', money_account_id: null }, _w1f_other_income_void: { id: 'oi-1', status: 'void' },
  _w1f_seed_report: SEEDS, _w1f_expense_heads: EHEADS, _w1f_seed_edit: { key: 'x', changed: true }, _w1f_seed_new_code: { key: 'x', code: '1255', old_retired: true }, _w1f_seed_map: { key: 'x', changed: true },
  _w1f_expense_head_set: { code: 'rent', active: true }, _w1f_other_income_head_set: { code: 'commission', active: true }, _w1f_mapping_coverage: { ran: true, ok: true, unmapped: 0, rows: [] },
  _w1f_receipt_settings: { bank_on: false, ref_required: 'off', ref_from: null, modes: ['cash', 'mobile', 'card'], events: [] }, _w1f_receipts_list: RCPTS, _w1f_collect_payment: { collected: 1400, balance: 3600, ids: [21, 22] },
  customer_balance: 5000, set_rule: null,
};
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('**/ia.js', async (r) => { const res = await r.fetch(); const body = (await res.text()).replace("  rec('restoredrill',", REG); await r.fulfill({ response: res, body }); });
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/otherincome\.js/.test(h) ? h : h.replace('</body>', '<script src="moneysrc.js"></script><script src="otherincome.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {});
    data.tables.coa_accounts = COA;
    data.tables.rules = o.rules || [{ key: 'other_income_on', value: null, default_value: false }, { key: 'other_income_from', value: null, default_value: null }, { key: 'receipt_bank_on', value: null, default_value: false },
      { key: 'receipt_ref_required', value: null, default_value: 'off' }, { key: 'receipt_ref_from', value: null, default_value: null }];
    data.tables.customers = [{ id: 'c-1', name: 'test_customer_97', mobile: '01900000097' }];
    const w1 = { calls: [], err: o.err || {}, fn: Object.assign({}, FN, o.fn || {}), pick: { other_income: PICK_OI, customer_collection: PICK_CC, default: PICK_CC } };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__W1=${JSON.stringify(w1)};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, m = 300) => p.waitForTimeout(m);
  const calls = (p, fn) => p.evaluate((f) => (window.__W1.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const toastText = (p) => p.evaluate(() => { const t = document.querySelector('.toast, #toast'); return t ? t.innerText : ''; });
  const setErr = (p, fn, msg) => p.evaluate(([f, m]) => { window.__W1.err[f] = m; }, [fn, msg]);

  // ---------------- Other income: off notice, form, picker, dry run, save, void
  let p = await open('#/otherincome');
  let t = await text(p);
  ok(/Other income/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('#oi_tabs .tog').count() === 4, 'four tabs');
  ok(await p.locator('#oi_off').count() === 1 && /switched OFF/.test(t), 'the OFF notice is shown while the server says the switch is off');
  ok(await p.locator('#oi_head option').count() === 3, 'only the active heads are offered (3 of 4)');
  ok(/test_buyer/.test(t) && /Scrap and packaging sale/.test(t) && /test wrong entry/.test(t), 'recent entries with the voided one marked and its reason');
  ok(await p.locator('.oi-row[data-id=oi-1] [data-act=oi_void]').count() === 1 && await p.locator('.oi-row[data-id=oi-2] [data-act=oi_void]').count() === 0, 'void only on a done entry');
  await wait(p, 600);
  ok(await p.locator('#ms_sel_oi').count() === 1 && await p.locator('#ms_sel_oi option').count() === 3, 'the payment source picker shows the accounts (none + 2)');
  ok((await calls(p, 'money_pick')).some((c) => c.p_event === 'other_income'), 'the picker asked for the event other_income');
  await p.fill('#oi_amt', '0'); await p.click('[data-act=oi_save]'); await wait(p, 200);
  ok((await calls(p, '_w1f_other_income_add')).length === 0, 'a zero amount never reaches the server');
  await p.fill('#oi_amt', '300'); await p.selectOption('#oi_head', 'old_oil'); await p.selectOption('#oi_mode', 'bank'); await p.selectOption('#ms_sel_oi', '3'); await p.fill('#oi_from', 'test_buyer'); await p.fill('#oi_ref', 'TRX-5');
  await p.click('[data-act=oi_dry]'); await wait(p, 300);
  let c = await calls(p, '_w1f_other_income_add');
  ok(c.length === 1 && c[0].p_dry === true && c[0].p_client === null && c[0].p_amount === 300 && c[0].p_head === 'old_oil' && c[0].p_mode === 'bank' && c[0].p_money_account === 3, 'dry run sends the form without a client id: ' + JSON.stringify(c[0]));
  await p.click('[data-act=oi_save]'); await wait(p, 400);
  c = await calls(p, '_w1f_other_income_add');
  ok(c.length === 2 && c[1].p_dry === false && /^[0-9a-f-]{36}$/.test(c[1].p_client) && c[1].p_received_from === 'test_buyer' && c[1].p_ref === 'TRX-5' && c[1].p_loc >= 1, 'save sends a client id (offline retry safe), place and the fields');
  await p.click('.oi-row[data-id=oi-1] [data-act=oi_void]'); await wait(p, 200);
  ok(await p.locator('#vd_why').count() === 1, 'void opens a reason sheet (no browser prompt)');
  await p.fill('#vd_why', 'x'); await p.click('[data-act=oi_voidgo]'); await wait(p, 200);
  ok((await calls(p, '_w1f_other_income_void')).length === 0, 'a reason shorter than 3 characters is refused in the browser');
  await p.fill('#vd_why', 'test_reason_void'); await p.click('[data-act=oi_voidgo]'); await wait(p, 300);
  c = await calls(p, '_w1f_other_income_void');
  ok(c.length === 1 && c[0].p_id === 'oi-1' && c[0].p_note === 'test_reason_void', 'void call carries the id and the reason');
  await noOverflow(p, 'other income en'); await p.screenshot({ path: SHOTS + '/oi_enter.png', fullPage: true });

  // server error text
  p = await open('#/otherincome', { err: { _w1f_other_income_add: 'other_income_off' } });
  await p.fill('#oi_amt', '50'); await p.click('[data-act=oi_save]'); await wait(p, 400);
  ok(/switched OFF/.test(await toastText(p)) || /switched OFF/.test(await text(p)), 'a server refusal is shown in English text');
  p = await open('#/otherincome', { err: { _w1f_other_income_list: 'function public._w1f_other_income_list does not exist' } });
  ok(/phase 96/.test(await text(p)) || /does not have this feature/.test(await text(p)), 'a missing server function is explained, not a crash');

  // ---------------- Chart & heads
  p = await open('#/otherincome');
  await p.click('[data-act=oi_tab][data-v=chart]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.w1-seed').count() === 3 && /Courier cash receivable/.test(t) && /Added for you/.test(t), 'seeded accounts listed with their status');
  ok(/Code already used: choose an account/.test(t) && /No account yet/.test(t), 'a seed whose code was taken says so and offers Choose account');
  ok(await p.locator('.w1-seed[data-k=bad_debt] [data-act=w1_rename]').count() === 0, 'no Rename on a seed without an account');
  ok(await p.locator('.w1-ehead').count() === 3 && await p.locator('.w1-ohead').count() === 4, 'expense heads (3) and other income heads (4) listed');
  ok(/2 older documents not posted yet/.test(t), 'the head with older unposted documents shows the count');
  await p.click('.w1-seed[data-k=courier_receivable] [data-act=w1_rename]'); await wait(p, 200);
  await p.fill('#rn_en', 'Courier COD receivable'); await p.click('[data-act=w1_renamego]'); await wait(p, 300);
  c = await calls(p, '_w1f_seed_edit');
  ok(c.length === 1 && c[0].p_key === 'courier_receivable' && c[0].p_name_en === 'Courier COD receivable' && c[0].p_active === null, 'rename call');
  await p.click('.w1-seed[data-k=courier_receivable] [data-act=w1_newcode]'); await wait(p, 200);
  ok(/never moved/.test(await text(p)), 'the sheet explains that history is never moved');
  await p.fill('#nc_code', '1255'); await p.fill('#nc_why', 'test_reason_code'); await p.click('[data-act=w1_newcodego]'); await wait(p, 300);
  c = await calls(p, '_w1f_seed_new_code');
  ok(c.length === 1 && c[0].p_code === '1255' && c[0].p_reason === 'test_reason_code', 'another code call with the reason');
  await p.click('.w1-seed[data-k=bad_debt] [data-act=w1_map]'); await wait(p, 300);
  ok(await p.locator('#mp_acc option').count() === 3, 'Choose account lists only the active EXPENSE accounts (3), not income or assets');
  await p.selectOption('#mp_acc', '5400'); await p.click('[data-act=w1_mapgo]'); await wait(p, 300);
  c = await calls(p, '_w1f_seed_map');
  ok(c.length === 1 && c[0].p_key === 'bad_debt' && c[0].p_account_code === '5400', 'map call');
  await p.click('.w1-seed[data-k=courier_receivable] [data-act=w1_active]'); await wait(p, 200);
  await p.fill('#ac_why', 'ab'); await p.click('[data-act=w1_activego]'); await wait(p, 200);
  ok((await calls(p, '_w1f_seed_edit')).length === 1, 'switching an account off needs a reason of 3+ characters (refused in the browser)');
  await p.fill('#ac_why', 'test_reason_off'); await p.click('[data-act=w1_activego]'); await wait(p, 300);
  c = await calls(p, '_w1f_seed_edit');
  ok(c.length === 2 && c[1].p_active === false && c[1].p_reason === 'test_reason_off', 'switch off call');
  await p.click('.w1-seed[data-k=vat_payable] [data-act=w1_active]'); await wait(p, 300);
  c = await calls(p, '_w1f_seed_edit');
  ok(c.length === 3 && c[2].p_active === true && c[2].p_reason === null, 'switching a placeholder ON needs no reason');
  // expense heads
  await p.click('.w1-ehead[data-c=utilities] [data-act=w1_ehead]'); await wait(p, 300);
  ok(/needed: 2 older documents not posted yet/.test(await text(p)), 'the reason field says it is needed when older documents exist');
  await p.selectOption('#eh_acc', '5400'); await p.fill('#eh_eff', '2026-10-16'); await p.fill('#eh_why', 'test_reason_history'); await p.click('[data-act=w1_eheadgo]'); await wait(p, 300);
  c = await calls(p, '_w1f_expense_head_set');
  ok(c.length === 1 && c[0].p_code === 'utilities' && c[0].p_account_code === '5400' && c[0].p_active === true && c[0].p_effective_from === '2026-10-16' && c[0].p_reason === 'test_reason_history', 'turn on call: account, effective date, reason');
  await p.click('[data-act=w1_ehead][data-v=""]'); await wait(p, 300);
  await p.fill('#eh_code', 'Bad Code'); await p.fill('#eh_label', 'Insurance'); await p.click('[data-act=w1_eheadgo]'); await wait(p, 200);
  ok((await calls(p, '_w1f_expense_head_set')).length === 1, 'a bad head code never reaches the server');
  await p.fill('#eh_code', 'insurance'); await p.selectOption('#eh_acc', '5400'); await p.click('[data-act=w1_eheadgo]'); await wait(p, 300);
  c = await calls(p, '_w1f_expense_head_set');
  ok(c.length === 2 && c[1].p_code === 'insurance' && c[1].p_label_en === 'Insurance', 'a new head: code and name sent');
  await p.click('.w1-ehead[data-c=labour] [data-act=w1_eretire]'); await wait(p, 200);
  await p.fill('#er_why', 'test_reason_retire'); await p.click('[data-act=w1_eretirego]'); await wait(p, 300);
  c = await calls(p, '_w1f_expense_head_set');
  ok(c.length === 3 && c[2].p_active === false && c[2].p_reason === 'test_reason_retire', 'retire needs a reason');
  await p.click('[data-act=w1_ohead][data-v=""]'); await wait(p, 300);
  await p.fill('#oh_code', 'commission'); await p.fill('#oh_label', 'Commission received'); await p.selectOption('#oh_acc', '4910'); await p.click('[data-act=w1_oheadgo]'); await wait(p, 300);
  c = await calls(p, '_w1f_other_income_head_set');
  ok(c.length === 1 && c[0].p_code === 'commission' && c[0].p_account_code === '4910', 'a new other income head with its own account');
  await noOverflow(p, 'chart en'); await p.screenshot({ path: SHOTS + '/oi_chart.png', fullPage: true });
  // a server refusal inside a sheet
  await setErr(p, '_w1f_expense_head_set', 'older_documents_unposted');
  await p.click('.w1-ehead[data-c=rent] [data-act=w1_ehead]'); await wait(p, 300);
  await p.selectOption('#eh_acc', '5300'); await p.click('[data-act=w1_eheadgo]'); await wait(p, 400);
  ok(/Older documents with this head are not posted yet/.test(await toastText(p)) || /Older documents with this head are not posted yet/.test(await text(p)), 'the history guard text is shown');

  // coverage
  p = await open('#/otherincome');
  await p.click('[data-act=oi_tab][data-v=cov]'); await wait(p, 400);
  ok(await p.locator('#cov_ok').count() === 1, 'coverage OK');
  p = await open('#/otherincome', { fn: { _w1f_mapping_coverage: { ran: true, ok: false, unmapped: 2, rows: [{ kind: 'expense_head', key: 'exp_insurance', problem: 'active head with no account' }, { kind: 'seed', key: 'bad_debt', problem: 'not mapped to an active account' }] } } });
  await p.click('[data-act=oi_tab][data-v=cov]'); await wait(p, 400);
  ok(await p.locator('#cov_bad').count() === 1 && await p.locator('.cov-row').count() === 2 && /exp_insurance/.test(await text(p)), 'coverage problems listed');

  // settings
  p = await open('#/otherincome');
  await p.click('[data-act=oi_tab][data-v=set]'); await wait(p, 400);
  ok(await p.locator('#rs_other_income_on').count() === 1 && !(await p.locator('#rs_other_income_on').isChecked()), 'the switch shows OFF (default)');
  await p.check('#rs_other_income_on'); await p.fill('#rs_other_income_from', '2026-10'); await p.click('[data-act=w1_setsave]'); await wait(p, 300);
  ok((await calls(p, 'set_rule')).length === 0, 'a bad date is refused in the browser');
  await p.fill('#rs_other_income_from', '2026-10-16'); await p.click('[data-act=w1_setsave]'); await wait(p, 400);
  c = await calls(p, 'set_rule');
  ok(c.length === 2 && c.some((x) => x.p_key === 'other_income_on' && x.p_value === true) && c.some((x) => x.p_key === 'other_income_from' && x.p_value === '2026-10-16'), 'set_rule called for the switch and the date: ' + JSON.stringify(c));
  p = await open('#/otherincome', { owner: false });
  await p.click('[data-act=oi_tab][data-v=set]'); await wait(p, 400);
  ok(await p.locator('[data-act=w1_setsave]').count() === 0 && await p.locator('#rs_other_income_on:disabled').count() === 1, 'a non-owner sees the settings but cannot save them');

  // ---------------- Bank & cheque receipts
  p = await open('#/bankreceipt');
  t = await text(p);
  ok(/Bank & cheque receipts/.test(await p.locator('h1').textContent()), 'receipts title');
  ok(await p.locator('#rc_bankoff').count() === 1, 'bank / cheque OFF notice while the switch is off');
  ok(await p.locator('#rc_recent, .rc-row').count() === 2 && /CHQ-100|cheque CHQ-100/.test(t) && /test_bank_oi/.test(t) && /no reference, reason on record: test_reason_noref/.test(t), 'recent bank and cheque receipts: cheque no, account name, waived reason');
  await p.fill('#rc_mobile', '01900000097'); await p.click('[data-act=rc_find]'); await wait(p, 500);
  ok(await p.locator('#rc_cust').count() === 1 && /test_customer_97/.test(await text(p)) && /5,000\.00/.test(await p.locator('#rc_due').textContent()), 'customer found, due 5,000.00 shown');
  ok(await p.locator('#rc_ch0 option').count() === 3, 'with the switch OFF only cash, mobile and card are channels');
  ok(await p.locator('#rc_ch0 option[value=bank]').count() === 0 && await p.locator('#rc_ch0 option[value=cheque]').count() === 0, 'no bank transfer or cheque channel yet');
  await p.fill('#rc_amt0', '100'); await p.click('[data-act=rc_collect]'); await wait(p, 400);
  c = await calls(p, '_w1f_collect_payment');
  ok(c.length === 1 && c[0].p_loc >= 1 && c[0].p_customer === 'c-1' && /^[0-9a-f-]{36}$/.test(c[0].p_client) && c[0].p_payments.length === 1 && c[0].p_payments[0].mode === 'cash' && c[0].p_payments[0].amount === 100, 'cash collect call: ' + JSON.stringify(c[0]));
  // bank ON, reference required
  const SET_ON = { bank_on: true, ref_required: 'bank', ref_from: null, modes: ['cash', 'mobile', 'card', 'bank'], events: [] };
  p = await open('#/bankreceipt', { fn: { _w1f_receipt_settings: SET_ON } });
  await p.fill('#rc_mobile', '01900000097'); await p.click('[data-act=rc_find]'); await wait(p, 500);
  ok(await p.locator('#rc_bankoff').count() === 0 && await p.locator('#rc_ch0 option').count() === 5, 'with the switch ON bank transfer and cheque join the channels (5)');
  await p.selectOption('#rc_ch0', 'bank'); await wait(p, 300);
  ok(await p.locator('#rc_src0, select[data-w1r="0.macc"]').count() === 1, 'a payment source select appears for the bank channel');
  ok(await p.locator('select[data-w1r="0.macc"] option').count() === 2, 'for bank only bank accounts (+ the empty choice) are offered');
  ok(await p.locator('#rc_why0').count() === 1, 'the reason field appears because a reference is required');
  await p.fill('#rc_amt0', '800'); await p.selectOption('select[data-w1r="0.macc"]', '3'); await p.click('[data-act=rc_collect]'); await wait(p, 300);
  ok((await calls(p, '_w1f_collect_payment')).length === 0, 'bank with no reference and no reason is refused in the browser');
  await p.fill('#rc_ref0', 'TRX900'); await p.click('[data-act=rc_add]'); await wait(p, 300);
  await p.selectOption('#rc_ch1', 'cheque'); await wait(p, 300);
  ok(await p.locator('#rc_chq1').count() === 1 && await p.locator('#rc_chqd1').count() === 1 && /bank receipt with its cheque number/.test(await text(p)), 'cheque row asks for the cheque number and date');
  await p.fill('#rc_amt1', '600'); await p.click('[data-act=rc_collect]'); await wait(p, 300);
  ok((await calls(p, '_w1f_collect_payment')).length === 0, 'a cheque row without a cheque number is refused in the browser');
  await p.fill('#rc_chq1', 'CHQ-100'); await p.fill('#rc_chqd1', '2026-10-20'); await p.selectOption('select[data-w1r="1.macc"]', '3');
  await p.fill('#rc_amt1', '6000'); await p.click('[data-act=rc_collect]'); await wait(p, 300);
  ok((await calls(p, '_w1f_collect_payment')).length === 0 && /More than the customer owes/.test(await toastText(p) + await text(p)), 'more than the due is refused in the browser');
  await p.fill('#rc_amt1', '600'); await p.fill('#rc_note', 'test note'); await p.click('[data-act=rc_collect]'); await wait(p, 500);
  c = await calls(p, '_w1f_collect_payment');
  ok(c.length === 1 && c[0].p_payments.length === 2, 'one call with both rows');
  const b0 = c[0].p_payments[0], b1 = c[0].p_payments[1];
  ok(b0.mode === 'bank' && b0.amount === 800 && b0.money_account_id === 3 && b0.ref === 'TRX900' && b0.cheque_no === undefined, 'bank row: mode bank, amount, account, reference');
  ok(b1.mode === 'bank' && b1.amount === 600 && b1.money_account_id === 3 && b1.cheque_no === 'CHQ-100' && b1.cheque_date === '2026-10-20' && b1.ref === undefined, 'cheque row: mode bank, cheque number and date, no reference needed');
  ok(c[0].p_note === 'test note', 'note sent');
  ok(/Collected/.test(await toastText(p) + await text(p)), 'a success message');
  // a reason waives a missing reference
  p = await open('#/bankreceipt', { fn: { _w1f_receipt_settings: SET_ON } });
  await p.fill('#rc_mobile', '01900000097'); await p.click('[data-act=rc_find]'); await wait(p, 500);
  await p.selectOption('#rc_ch0', 'bank'); await wait(p, 200); await p.fill('#rc_amt0', '10'); await p.fill('#rc_why0', 'test_reason_noref'); await p.click('[data-act=rc_collect]'); await wait(p, 400);
  c = await calls(p, '_w1f_collect_payment');
  ok(c.length === 1 && c[0].p_payments[0].exception_reason === 'test_reason_noref' && c[0].p_payments[0].ref === undefined, 'the reason travels as exception_reason');
  // source filtered by channel
  await p.selectOption('#rc_ch0', 'mobile'); await wait(p, 300);
  ok(await p.locator('select[data-w1r="0.macc"] option').count() === 2, 'for mobile only wallet accounts (+ empty)');
  await p.selectOption('#rc_ch0', 'cash'); await wait(p, 300);
  ok(await p.locator('select[data-w1r="0.macc"] option').count() === 2 && await p.locator('#rc_why0').count() === 0, 'for cash only cash drawers, and no reference reason is asked');
  // unknown customer, server error
  p = await open('#/bankreceipt', { fn: { _w1f_receipt_settings: SET_ON }, err: { _w1f_collect_payment: 'receipt_reference_required' } });
  await p.fill('#rc_mobile', '01900000099'); await p.click('[data-act=rc_find]'); await wait(p, 400);
  ok(await p.locator('#rc_cust').count() === 0 && /Customer not found/.test(await toastText(p) + await text(p)), 'unknown customer');
  await p.fill('#rc_mobile', '01900000097'); await p.click('[data-act=rc_find]'); await wait(p, 400);
  await p.fill('#rc_amt0', '10'); await p.click('[data-act=rc_collect]'); await wait(p, 400);
  ok(/A reference number is required/.test(await toastText(p) + await text(p)), 'a server refusal is shown in English text');
  // owner settings on the receipts page
  p = await open('#/bankreceipt', { fn: { _w1f_receipt_settings: SET_ON } });
  ok(await p.locator('#rs_receipt_bank_on').count() === 1 && await p.locator('#rs_receipt_ref_required').count() === 1 && await p.locator('#rs_receipt_ref_from').count() === 1, 'the owner sees the three receipt settings');
  await p.selectOption('#rs_receipt_ref_required', 'bank_mobile'); await p.click('[data-act=w1_setsave]'); await wait(p, 400);
  c = await calls(p, 'set_rule');
  ok(c.some((x) => x.p_key === 'receipt_ref_required' && x.p_value === 'bank_mobile'), 'set_rule for the reference rule');
  p = await open('#/bankreceipt', { owner: false });
  ok(await p.locator('#rs_receipt_bank_on').count() === 0, 'a non-owner does not see the receipt settings');
  ok(/Money Accounts/.test(await text(p)), 'the page points to Money Accounts for the default payment source');

  // ---------------- languages and width: English labels in all three modes, no overflow
  for (const lang of ['en', 'bn', 'mix']) {
    p = await open('#/otherincome', { lang });
    ok(/Other income/.test(await p.locator('h1').textContent()) && /Enter/.test(await text(p)), 'English labels in mode ' + lang);
    await noOverflow(p, 'other income ' + lang);
    p = await open('#/bankreceipt', { lang, fn: { _w1f_receipt_settings: SET_ON } });
    await p.fill('#rc_mobile', '01900000097'); await p.click('[data-act=rc_find]'); await wait(p, 400);
    await p.click('[data-act=rc_add]'); await p.selectOption('#rc_ch1', 'cheque'); await wait(p, 300);
    ok(/Bank & cheque receipts/.test(await p.locator('h1').textContent()), 'receipts title in mode ' + lang);
    await noOverflow(p, 'receipts ' + lang);
    if (lang === 'en') await p.screenshot({ path: SHOTS + '/oi_receipts.png', fullPage: true });
  }

  // ---------------- the real registry carries the two routes (injected lines)
  p = await open('#/otherincome');
  ok(await p.evaluate(() => !!(window.BOS_PAGES && window.BOS_PAGES.otherincome && window.BOS_PAGES.bankreceipt)), 'both routes are registered as pages');
  await br.close(); srv.close();
  log(errors.length ? 'ERRORS: ' + errors.slice(0, 6).join(' | ') : 'no console errors');
  log(`RESULT ${n - bad} pass, ${bad + errors.length} fail (${n} asserts)`);
  process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.log('CRASH', e && e.stack || e); process.exit(2); } })();
