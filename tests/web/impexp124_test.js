// Import-Export page #/impexp (web/impexp124.js), RPCs mocked with the REAL shapes of phase124 functions.
// Checks: shipments list, add sheet (client id, validation, friendly server errors), status change, currency + rate setup, module-off banner (no write buttons), view-only user, no-business message, 360px overflow, no JS errors.
// Run: node impexp124_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const I = window.__IE;
 const clone = (x) => JSON.parse(JSON.stringify(x));
 const fail = () => { const m = I.err; I.err = null; return { data: null, error: { message: m, code: 'P0001' } }; };
 c.rpc = async (fn, args) => {
  (window.__ACI = window.__ACI || []).push([fn, clone(args || {})]);
  if (fn === 'ie_businesses124') return { data: clone(I.biz), error: null };
  if (fn === 'ie_currencies_list') return { data: clone(I.curs), error: null };
  if (fn === 'ie_fx_rates_list') return { data: clone(I.rates), error: null };
  if (fn === 'shipments_by_currency') return { data: clone(I.sum), error: null };
  if (fn === 'shipments_list') return { data: clone(I.ships.filter((s) => !args.p_status || s.status === args.p_status)), error: null };
  if (fn === 'shipment_save') { if (I.err) return fail(); const id = 50 + I.ships.length; const rate = args.p_rate || 110; I.ships.unshift({ id, direction: args.p_direction, reference: args.p_reference, counterparty: args.p_counterparty, status: 'draft', currency: args.p_currency, amount: args.p_amount, rate, amount_base: Math.round(args.p_amount * rate * 100) / 100, ship_date: args.p_ship_date, freight: args.p_freight, landed_base: 0 }); return { data: { dup: false, id }, error: null }; }
  if (fn === 'shipment_set_status') { if (I.err) return fail(); const s = I.ships.find((x) => x.id === args.p_id); s.status = args.p_status; return { data: { dup: false, status: args.p_status }, error: null }; }
  if (fn === 'currency_save') { if (I.err) return fail(); I.curs.push({ id: 9, code: args.p_code, name_bn: args.p_name_bn, name_en: args.p_name_en, decimals: args.p_decimals, active: args.p_active }); return { data: { dup: false, id: 9 }, error: null }; }
  if (fn === 'fx_rate_set') { if (I.err) return fail(); I.rates.unshift({ id: 8, currency: args.p_currency, rate: args.p_rate, valid_from: args.p_valid_from, note: args.p_note }); return { data: { dup: false, id: 8 }, error: null }; }
  return rpc(fn, args);
 }; return c; }; })();`;
const mkI = (o) => ({
  biz: o.nobiz ? [] : [{ id: 7, code: 'IEA', name_bn: 'এ আমদানি <i>x</i>', name_en: 'IE A <i>x</i>', status: 'active', base_currency: 'BDT', can_manage: o.view ? false : true, impexp_on: o.off ? false : true }],
  curs: [{ id: 1, code: 'USD', name_bn: 'ডলার', name_en: 'US dollar', decimals: 2, active: true, is_base: false }, { id: 2, code: 'EUR', name_bn: 'ইউরো', name_en: 'Euro', decimals: 2, active: true, is_base: false }],
  rates: [{ id: 3, currency: 'USD', rate: 110.5, valid_from: '2026-10-01', note: 'oct' }],
  sum: [{ currency: 'USD', direction: 'import', shipments: 2, amount: 3000, amount_base: 331500, landed_base: 340000, base_currency: 'BDT' }],
  ships: [
    { id: 1, direction: 'import', reference: 'IMP-<b>001</b>', counterparty: 'A very long counterparty name that must wrap inside a narrow phone screen without any sideways scrolling at all', status: 'booked', currency: 'USD', amount: 1000.56, rate: 110.5, amount_base: 110561.88, ship_date: '2026-10-02', freight: 50, landed_base: 110611.88, base_currency: 'BDT' },
    { id: 2, direction: 'export', reference: 'EXP-001', counterparty: 'Buyer', status: 'closed', currency: 'BDT', amount: 2500, rate: 1, amount_base: 2500, ship_date: '2026-10-03', freight: 0, landed_base: 2500, base_currency: 'BDT' }],
});
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: ((h) => (/impexp124\.js/.test(h) ? h : h.replace('<script src="cashmoves.js"></script>', '<script src="cashmoves.js"></script><script src="impexp124.js"></script>')))(fs.readFileSync(WEB + '/index.html', 'utf8')) }));
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__IE=${JSON.stringify(mkI(o))};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__ACI || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  let p = await open('#/impexp');
  let t = await text(p);
  ok(await p.locator('.ie-ship').count() === 2, 'two shipments listed');
  ok(/IMP-<b>001<\/b>/.test(t) && !(await p.locator('.ie-ship b >> text=001').count() && false), 'reference escaped, not injected as HTML');
  ok(/110,561.88 BDT/.test(t) && /Landed cost/.test(t), 'base amount and landed cost shown');
  ok(/By currency/.test(t) && /331,500.00 BDT/.test(t), 'by-currency summary shown');
  ok(/Nothing is posted to the accounts/.test(t), 'no-GL note shown');
  ok(await p.locator('#ie_off').count() === 0, 'no off banner when the module is on');
  ok(await p.locator('.ie-ship[data-id="2"] [data-act]').count() === 0, 'a closed shipment has no actions');
  const a1 = await calls(p, 'shipments_list'); ok(a1.length >= 1 && a1[0].p_org === 7, 'every read is scoped by the business id');
  await noOverflow(p, 'list');
  const small = await p.evaluate(() => [...document.querySelectorAll('#ie_body button')].filter((b) => b.getBoundingClientRect().height < 39.5).length); ok(small === 0, 'all taps at least 40px');
  await p.screenshot({ path: SP + '/ie_list.png', fullPage: true });

  // filter
  await p.selectOption('#ie_filt', 'closed'); await wait(p, 300);
  ok(await p.locator('.ie-ship').count() === 1, 'status filter narrows');
  await p.selectOption('#ie_filt', ''); await wait(p, 300);

  // add shipment
  await p.click('[data-act=ie_new]'); await wait(p, 200);
  ok(await p.locator('#ie_cur option').allTextContents().then((a) => a.join() === 'BDT,USD,EUR'), 'currency pick-list = base + the configured list (nothing hardcoded)');
  await p.click('[data-act=ie_ship_save]'); await wait(p, 100);
  ok(/Enter a reference/.test(await p.textContent('#ie_err')) && !(await calls(p, 'shipment_save')).length, 'reference validation, no call');
  await p.fill('#ie_ref', 'IMP-NEW'); await p.fill('#ie_amt', 'abc'); await p.click('[data-act=ie_ship_save]'); await wait(p, 100);
  ok(/Amount is not valid/.test(await p.textContent('#ie_err')) && !(await calls(p, 'shipment_save')).length, 'bad amount, no call');
  await p.fill('#ie_amt', '1,000.5'); await p.selectOption('#ie_cur', 'USD'); await p.fill('#ie_fr', '25');
  await p.evaluate(() => { window.__IE.err = 'no_rate'; }); await p.click('[data-act=ie_ship_save]'); await wait(p, 300);
  ok(/No rate for this currency/.test(await p.textContent('#ie_err')) && await p.locator('#ie_form').count() === 1, 'known server code shown friendly, sheet stays');
  await p.evaluate(() => { window.__IE.err = 'weird_text 42'; }); await p.click('[data-act=ie_ship_save]'); await wait(p, 300);
  ok(/weird_text 42/.test(await p.textContent('#ie_err')), 'unknown server message shown raw');
  await noOverflow(p, 'add sheet');
  await p.click('[data-act=ie_ship_save]'); await wait(p, 600);
  let c = await calls(p, 'shipment_save'); const last = c[c.length - 1];
  ok(c.length === 3 && last.p_org === 7 && last.p_id === null && last.p_direction === 'import' && last.p_reference === 'IMP-NEW' && last.p_currency === 'USD' && last.p_amount === 1000.5 && last.p_rate === null && last.p_freight === 25 && last.p_insurance === 0 && last.p_client, 'save payload: business, key, empty rate = null (server looks it up), typed cost line');
  ok(c[0].p_client === c[1].p_client && c[1].p_client === last.p_client, 'the same client key is kept across retries');
  ok(/IMP-NEW/.test(await text(p)) && await p.locator('#sheet').count() === 0, 'new shipment listed, sheet closed');

  // status change
  await p.click('.ie-ship[data-id="1"] [data-act=ie_status]'); await wait(p, 200);
  ok(await p.locator('[data-act=ie_status_go]').allTextContents().then((a) => a.join() === 'In transit,Received,Cancelled'), 'only the allowed next statuses are offered');
  await p.click('[data-act=ie_status_go][data-to=in_transit]'); await wait(p, 500);
  c = await calls(p, 'shipment_set_status'); ok(c.length === 1 && c[0].p_id === 1 && c[0].p_status === 'in_transit' && c[0].p_client && c[0].p_org === 7, 'status call with key');
  ok(await p.locator('.ie-ship[data-id="1"] .chip', { hasText: 'In transit' }).count() === 1, 'status chip updated');

  // edit
  await p.click('.ie-ship[data-id="1"] [data-act=ie_edit]'); await wait(p, 200);
  ok(await p.locator('#ie_ref').isDisabled() && await p.locator('#ie_amt').isDisabled(), 'reference fixed; amount locked once in transit');
  await p.fill('#ie_du', '12'); await p.click('[data-act=ie_ship_save]'); await wait(p, 500);
  c = await calls(p, 'shipment_save'); ok(c[c.length - 1].p_id === 1 && c[c.length - 1].p_duty_tax === 12 && c[c.length - 1].p_client === null, 'edit sends the id and the new cost line, no create key');

  // money tab
  await p.click('[data-act=ie_tab][data-v=money]'); await wait(p, 200);
  t = await text(p);
  ok(/USD · US dollar/.test(t) && /1 USD = 110.5/.test(t) && /No rate/.test(t), 'currencies with the latest rate; missing rate flagged');
  await p.click('[data-act=ie_curnew]'); await wait(p, 200);
  await p.fill('#ie_cc', 'gbp'); await p.fill('#ie_cen', 'Pound'); await p.click('[data-act=ie_cur_save]'); await wait(p, 500);
  c = await calls(p, 'currency_save'); ok(c.length === 1 && c[0].p_code === 'GBP' && c[0].p_name_bn === 'Pound' && c[0].p_decimals === 2 && c[0].p_active === true && c[0].p_client, 'currency_save payload');
  ok(/GBP/.test(await text(p)), 'new currency listed');
  await p.click('[data-act=ie_ratenew][data-c=EUR]'); await wait(p, 200);
  await p.click('[data-act=ie_rate_save]'); await wait(p, 100); ok(/Rate is not valid/.test(await p.textContent('#ie_err')) && !(await calls(p, 'fx_rate_set')).length, 'rate validation');
  await p.fill('#ie_rv', '120.25'); await p.click('[data-act=ie_rate_save]'); await wait(p, 500);
  c = await calls(p, 'fx_rate_set'); ok(c.length === 1 && c[0].p_currency === 'EUR' && c[0].p_rate === 120.25 && c[0].p_client && c[0].p_org === 7, 'fx_rate_set payload');
  ok(/1 EUR = 120.25/.test(await text(p)), 'rate shown after save');
  await noOverflow(p, 'money tab'); await p.screenshot({ path: SP + '/ie_money.png', fullPage: true });

  // module off
  p = await open('#/impexp', { off: true });
  ok(await p.locator('#ie_off').count() === 1 && /module is off/.test(await text(p)), 'off banner');
  ok(await p.locator('[data-act=ie_new], [data-act=ie_edit], [data-act=ie_status]').count() === 0 && await p.locator('.ie-ship').count() === 2, 'reading works, no write buttons');
  // view only
  p = await open('#/impexp', { view: true });
  ok(await p.locator('[data-act=ie_new], [data-act=ie_edit], [data-act=ie_status]').count() === 0 && await p.locator('.ie-ship').count() === 2, 'view-only user: list yes, no write buttons');
  // none
  p = await open('#/impexp', { nobiz: true });
  ok(await p.locator('#ie_noperm').count() === 1, 'no business: friendly message'); await noOverflow(p, 'empty');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
