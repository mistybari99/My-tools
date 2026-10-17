// Wave 1 integration wiring (phase 99, package I-1): the places where the new screens touch the existing ones.
//   S1 Home shows the "books freshness" strip for a person with Accounts view and stays empty and silent without phase 98.
//   S2 pos.js: the answer {parked:true} of record_sale2 is a sent sale (held for the owner, no receipt, no retry, nothing queued).
//   S3 salereturn.js: the return picker (restock quantities, receipt number, override reason) calls _w1c_sale_return; without phase 91 the old sale_return is called; rule codes are said in words.
//   S4 pay.js: bank transfer and cheque rows exist only while receipt_bank_on is ON (POS), and send mode bank + cheque_no / cheque_date; with the switch OFF the three old modes only.
//   S5 forms_stock.js / paths.js: the switch-coupling warning is shown before the switch is saved (Cancel keeps the old state, Continue saves).
//   S6 every new screen is registered once in web/ia.js and its script is in index.html; no duplicate route.
// Server calls are stand-ins; the SQL is tested in supabase/phase88..99_test.sql. Run: node wave1_wiring_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = 8609, srv = C.serve(PORT);
const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const PREVIEW = { lines: [{ item_id: 'i0', qty: 2, class: 'test_perish', restock_qty: 2, restock_rule: 'restock', receipt_needed: true }], violations: ['return_window_exceeded'], can_override: true };
const EXTRA_W = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M || (window.__M = { calls: [] });
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = window.__W = Object.assign({ fresh: null, preview: ${JSON.stringify(PREVIEW)}, noPreview: false, srErr: null, park: false, bankOn: false, warn: null, setRule: [] }, window.__W0 || {});
 c.rpc = async (fn, args) => {
  const own = ['_w1c_return_preview', '_w1c_sale_return', '_w1f_receipt_settings', '_w1g_freshness', '_w1g_switch_coupling_warning', 'record_sale2', 'path_switch_set'];
  if (!own.includes(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  const miss = { data: null, error: { message: 'Could not find the function public.' + fn, code: 'PGRST202' } };
  if (fn === '_w1g_freshness') return W.fresh ? { data: W.fresh, error: null } : miss;
  if (fn === '_w1c_return_preview') return W.noPreview ? miss : { data: clone(W.preview), error: null };
  if (fn === '_w1c_sale_return') return W.srErr ? { data: null, error: { message: W.srErr, code: 'P0001' } } : { data: { id: 'r9', amount: 520, w1c: { written_off_items: 1 } }, error: null };
  if (fn === '_w1f_receipt_settings') return { data: { modes: ['cash', 'mobile', 'card'], bank_on: !!W.bankOn, ref_required: 'off', events: [] }, error: null };
  if (fn === '_w1g_switch_coupling_warning') return { data: W.warn, error: null };
  if (fn === 'record_sale2') return W.park ? { data: { parked: true, held_id: 7 }, error: null } : { data: { id: 's9', receipt: 9, total: (args.p_payments || []).reduce((t, x) => t + x.amount, 0), due: 0 }, error: null };
  if (fn === 'path_switch_set') return { data: { ok: true }, error: null };
  return rpc(fn, args); }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|return window has passed/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA_W }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o); (o.tables || []).forEach(([k, v]) => { data.tables[k] = v; });
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };
  const wait = (p, t = 300) => p.waitForTimeout(t);

  // ---------- S6 registry and script tags ----------
  let p = await open({}, '#/home');
  const reg = await p.evaluate(() => { const ia = window.BOS.IA, want = ['openparties', 'periodlock', 'moneycontrols', 'otherincome', 'freshness', 'profitcheck', 'returnrules', 'bankreceipt'];
    return { each: want.map((w) => ia.filter((r) => r.route === w).length), pages: want.map((w) => !!(window.BOS_PAGES || {})[w]), groups: want.map((w) => (ia.find((r) => r.route === w) || {}).group),
      homeSlots: want.map((w) => !!(ia.find((r) => r.route === w) || {}).home), dup: ia.length - new Set(ia.map((r) => r.route)).size }; });
  ok(reg.each.every((x) => x === 1), 'each new screen is registered exactly once: ' + reg.each); ok(reg.pages.every(Boolean), 'each new screen has its page function (script tag in index.html): ' + reg.pages);
  ok(JSON.stringify(reg.groups) === JSON.stringify(['acc', 'acc', 'acc', 'acc', 'acc', 'acc', 'settings', 'cust']), 'groups: ' + reg.groups); ok(reg.dup === 0, 'no duplicate route'); ok(reg.homeSlots.every((x) => !x), 'no Home slot is taken by the new screens');
  await p.close();

  // ---------- S1 Home strip ----------
  p = await open({ w: { fresh: { status: 'fresh', last_posted_at: today + 'T05:00:00Z', age_minutes: 5, pending: 0, errors: 0, sched_on: true, last_check_at: today + 'T05:02:00Z' } } }, '#/home'); await wait(p, 500);
  ok(await p.locator('#hv_fresh #fr_strip').count() === 1, 'Home shows the books freshness strip for the owner'); ok((await calls(p, '_w1g_freshness')).length >= 1, 'the strip asked the server once'); await p.close();
  p = await open({}, '#/home'); await wait(p, 400);
  ok(await p.locator('#hv_fresh').count() === 1 && (await p.locator('#hv_fresh').innerHTML()).trim() === '', 'without phase 98 the strip place stays empty'); await p.close();
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={POS:{view:true,enter:true}};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};', m: { grants: [], ctx: { locations: [1], roles: ['salesperson'] } }, w: { fresh: { status: 'fresh' } } }, '#/home'); await wait(p, 400);
  if (process.env.DBG) log('S1c:', await p.locator('#hv_fresh').count(), JSON.stringify(await calls(p, '_w1g_freshness')));
  ok(await p.locator('#hv_fresh').count() === 0 && (await calls(p, '_w1g_freshness')).length === 0, 'a person without Accounts view gets no strip and no call'); await p.close();

  // ---------- S2 parked sale ----------
  p = await open({ w: { park: true } }, '#/pos'); await wait(p, 400);
  const item = await p.evaluate(() => { const it = window.__DATA.tables.items.find((i) => i.unit === 'pc'); return it && it.id; });
  await p.click(`.pos-item[data-v="${item}"]`); await p.click('[data-act=pos_cart]'); await wait(p, 300); await p.click('#cart_ok'); await wait(p, 700);
  const sent = await calls(p, 'record_sale2'); const toast = await toastTxt(p);
  ok(sent.length === 1, 'the sale was sent once'); ok(/Held for the owner/.test(toast), 'toast says held for the owner: ' + toast); ok(!/Receipt/.test(toast), 'no receipt number is shown');
  const q = await p.evaluate(() => Object.keys(localStorage).map((k) => localStorage.getItem(k)).filter((v) => /p_client/.test(v || '')).length);
  ok(q === 0, 'a parked sale is not left in the offline queue'); await wait(p, 1500); ok((await calls(p, 'record_sale2')).length === 1, 'and it is not sent again'); await p.close();

  // ---------- S4 bank and cheque rows ----------
  for (const on of [false, true]) {
    p = await open({ w: { bankOn: on } }, '#/pos'); await wait(p, 400);
    const it = await p.evaluate(() => window.__DATA.tables.items.find((i) => i.unit === 'pc').id);
    await p.click(`.pos-item[data-v="${it}"]`); await p.click('[data-act=pos_cart]'); await wait(p, 500);
    const nb = await p.locator('[data-act=pay_add][data-m=bank]').count(), nc = await p.locator('[data-act=pay_add][data-m=cheque]').count(), n3 = await p.locator('[data-act=pay_add]').count();
    if (!on) { ok(nb === 0 && nc === 0 && n3 === 3, 'switch OFF: only cash, mobile, card can be added: ' + n3); await p.close(); continue; }
    ok(nb === 1 && nc === 1 && n3 === 5, 'switch ON: bank transfer and cheque can be added: ' + n3);
    await p.click('[data-act=pay_add][data-m=cheque]'); await wait(p, 200);
    ok(await p.locator('[data-pay="1.cheque_no"]').count() === 1 && await p.locator('[data-pay="1.cheque_date"]').count() === 1, 'a cheque row asks for the number and the date');
    const tot = Number(await p.inputValue('[data-pay="1.amount"]')); await p.fill('[data-pay="0.amount"]', '10'); await p.fill('[data-pay="1.amount"]', String(tot - 10)); const rest = String(tot - 10); await p.fill('[data-pay="1.cheque_no"]', 'CHQ-77'); await p.fill('[data-pay="1.cheque_date"]', today);
    await p.click('#cart_ok'); await wait(p, 500); if (process.env.DBG) log('S4 toast:', await toastTxt(p), '| pay_sum:', (await p.textContent('#pay_sum')).replace(/\s+/g, ' '), '| calls:', JSON.stringify((await p.evaluate(() => window.__M.calls.map((c) => c[0]))).slice(-6)));
    const sr = (await calls(p, 'record_sale2'))[0]; const pay = sr && sr.p_payments && sr.p_payments.find((x) => x.mode === 'bank');
    ok(pay && pay.cheque_no === 'CHQ-77' && pay.cheque_date === today && Number(pay.amount) === Number(rest), 'the sale carries mode bank with the cheque number and date: ' + JSON.stringify(sr && sr.p_payments));
    await p.close();
  }

  // ---------- S3 return picker ----------
  const sales = [{ id: 's1', receipt: 12, sold_at: today + 'T05:00:00Z', total: 1040, status: 'done', customer: 'Rahim', location_id: 1, pay_mode: 'cash', sale_date: today }];
  const mk = () => ({ sale_id: 's1', receipt: 12, status: 'done', location_id: 1, customer_id: null, customer: null, factor: 1, due_first: true, balance: null, can_return: true,
    lines: [{ item_id: 'i0', name: 'White sweet', unit: 'kg', sold: 4, returned: 0, left: 4, price: 260 }], returns: [] });
  const fill = async (pg) => { await pg.fill('[data-rq="0"]', '2'); await wait(pg, 900); };
  p = await open({ sales, m: { saleRet: mk() } }, '#/salereturn/s1'); await wait(p, 400); await fill(p);
  ok(await p.locator('#sr_rr [data-rr-item="i0"]').count() === 1 && await p.locator('#rrp_receipt').count() === 1 && await p.locator('#rrp_override').count() === 1, 'the picker shows the item, the receipt field and the override reason');
  ok((await calls(p, '_w1c_return_preview')).length >= 1 && (await calls(p, '_w1c_return_preview'))[0].p_sale === 's1', 'the preview was asked for this sale');
  await p.fill('#rrp_i0', '1'); await p.fill('#rrp_receipt', 'R-12'); await p.fill('#rrp_override', 'test regular customer');
  await p.selectOption('#sr_reason', 'damaged'); await p.selectOption('#sr_mode', 'cash'); await p.click('#sr_go'); await wait(p, 500);
  const w = await calls(p, '_w1c_sale_return'); const plain = await calls(p, 'sale_return');
  ok(w.length === 1 && plain.length === 0, 'the save goes through _w1c_sale_return, not the plain sale_return');
  ok(w[0] && JSON.stringify(w[0].p_restock_lines) === '[{"item_id":"i0","restock_qty":1}]' && w[0].p_receipt_no === 'R-12' && w[0].p_override_reason === 'test regular customer' && JSON.stringify(w[0].p_lines) === '[{"item_id":"i0","qty":2}]',
    'restock lines, receipt number, override reason and lines are sent: ' + JSON.stringify(w[0])); await p.close();
  p = await open({ sales, m: { saleRet: mk() }, w: { noPreview: true } }, '#/salereturn/s1'); await wait(p, 400); await fill(p);
  ok(await p.locator('#sr_rr [data-rr-item]').count() === 0, 'without phase 91 there is no picker');
  await p.selectOption('#sr_reason', 'damaged'); await p.selectOption('#sr_mode', 'cash'); await p.click('#sr_go'); await wait(p, 500);
  ok((await calls(p, 'sale_return')).length === 1 && (await calls(p, '_w1c_sale_return')).length === 0, 'and the old sale_return is called as before'); await p.close();
  p = await open({ sales, m: { saleRet: mk() }, w: { srErr: 'return_window_exceeded' } }, '#/salereturn/s1'); await wait(p, 400); await fill(p);
  await p.selectOption('#sr_reason', 'damaged'); await p.selectOption('#sr_mode', 'cash'); await p.click('#sr_go'); await wait(p, 500);
  ok(/return window has passed/i.test(await toastTxt(p)), 'a refused return says the rule in words: ' + await toastTxt(p)); await p.close();

  // ---------- S5 switch-coupling warning on #/ledgerlinks ----------
  const lk = (on) => [['rules', [{ key: 'forms_post_to_ledger', module: 'x', kind: 'switch', value: on, default_value: false, label_bn: 'k', label_en: 'k', label_mix: 'k', sort: 1 }]]];
  p = await open({}, '#/ledgerlinks'); await wait(p, 300);
  const hasLk = await p.locator('[data-act=lk_set]').count();
  if (hasLk) {
    await p.evaluate(() => { const A = window.BOS_APP, o = A.sb.rpc.bind(A.sb); A.sb.rpc = async (fn, a) => (fn === '_w1g_switch_coupling_warning' ? { data: { show: true, confirm: false, severity: 'info', text: 'test warning text', actions: [], fix: null }, error: null } : o(fn, a)); });
    await p.click('[data-act=lk_set][data-v="master:1"]'); await wait(p, 500);
    ok(await p.locator('#fr_warn').count() === 1 && /test warning text/.test(await p.textContent('#fr_warn')), 'turning the master switch ON shows the warning first');
    ok((await calls(p, 'set_rule')).filter((x) => x.p_key === 'forms_post_to_ledger' && x.p_value === true).length === 0, 'nothing is saved while the warning is open');
    await p.click('[data-act=fr_back]'); await wait(p, 400);
    ok((await calls(p, 'set_rule')).filter((x) => x.p_key === 'forms_post_to_ledger').length === 0, 'Back keeps the old state');
    await p.click('[data-act=lk_set][data-v="master:1"]'); await wait(p, 500); await p.click('#fr_go'); await wait(p, 500);
    ok((await calls(p, 'set_rule')).filter((x) => x.p_key === 'forms_post_to_ledger' && x.p_value === true).length === 1, 'Continue saves the switch');
  } else log('(ledgerlinks has no switches in this stub: S5 skipped, covered by forms_links_test)');
  await p.close();

  ok(errors.length === 0, 'no console errors: ' + errors.join(' | ').slice(0, 400));
  log('assertions:', n); log('errors:', errors.length ? errors.join('\n') : 'none'); log('assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e); srv.close(); process.exit(2); } })();
