const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = process.env.WEB_ROOT || '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8084);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = [];
 const CU = window.__CUST = [{ id: 'c1', mobile: '01711111111', name: 'Rafiq', type: 'retail', credit_limit: null, balance: 350, oldest: '2026-10-01' }];
 c.rpc = async (fn, args) => {
  window.__CALLS.push([fn, args]);
  if (fn === 'find_customer') { const m = String(args.p_mobile).replace(/\\D/g, '').replace(/^880/, '0'); const x = CU.find((u) => u.mobile === m); return { data: x ? { found: true, id: x.id, name: x.name, mobile: x.mobile, type: x.type, balance: x.balance, credit_limit: x.credit_limit } : { found: false, mobile: m }, error: null }; }
  if (fn === 'record_sale2') { if (window.__OFFLINE) return { data: null, error: { message: 'TypeError: Failed to fetch' } };
    if (window.__FAIL) return { data: null, error: { message: window.__FAIL } };
    const S = window.__DATA.tables.sales = window.__DATA.tables.sales || [];
    const tot = args.p_lines.reduce((s, l) => s + (l.amount !== undefined ? l.amount : l.qty * (l.item_id ? (window.__DATA.tables.items.find((i) => i.id === l.item_id).sell_price) : l.price)), 0) - args.p_discount;
    const paid = (args.p_payments || []).reduce((s, p) => s + p.amount, 0);
    if ((tot - paid > 0 || args.p_sale_type === 'wholesale') && !args.p_customer_mobile) return { data: null, error: { message: 'customer_required' } };
    const row = { id: 's' + (S.length + 1), receipt: S.length + 1, location_id: args.p_loc, sale_date: new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }), sold_at: new Date().toISOString(), lines: args.p_lines, subtotal: tot, discount: args.p_discount, total: tot, pay_mode: paid === 0 ? 'due' : (tot - paid === 0 && args.p_payments.length === 1 ? args.p_payments[0].mode : 'split'), quick: args.p_quick, sale_type: args.p_sale_type, paid, due_amount: tot - paid, customer: args.p_customer_name, status: 'done', created_staff: 'owner1' };
    S.push(row); window.__LAST = args; return { data: { id: row.id, receipt: row.receipt, total: tot, paid, due: tot - paid }, error: null }; }
  if (fn === 'customer_dues') return { data: CU.map((u) => ({ ...u })), error: null };
  if (fn === 'customer_ledger') return { data: [{ at: '2026-10-01T10:00:00Z', kind: 'sale', ref: '#4', location_id: 1, debit: 500, credit: 0, balance: 500 }, { at: '2026-10-02T10:00:00Z', kind: 'collection', ref: 'cash', location_id: 1, debit: 0, credit: 150, balance: 350 }], error: null };
  if (fn === 'collect_payment') { const u = CU[0]; const tot = args.p_payments.reduce((s, p) => s + p.amount, 0); if (tot > u.balance) return { data: null, error: { message: 'overpaid' } }; u.balance -= tot; window.__COLL = args; return { data: { collected: tot, balance: u.balance }, error: null }; }
  if (fn === 'payments_summary') return { data: [], error: null };
  if (fn === 'sales_summary') return { data: [], error: null };
  return rpc(fn, args); }; return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a);
  const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  p.on('dialog', (d) => d.accept(d.defaultValue()));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn');}catch(e){}`);
  const toast = async () => (await p.textContent('#toast')).trim();
  await p.goto('http://localhost:8084/#/pos'); await p.waitForTimeout(900);
  const pc = data.tables.items.find((i) => i.unit === 'pc'), kg = data.tables.items.find((i) => i.unit === 'kg');
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click(`.pos-item[data-v="${pc.id}"]`);
  await p.click(`.pos-item[data-v="${kg.id}"]`); await p.click('[data-act=pos_q_set][data-n="0.5"]'); await p.click('[data-act=pos_q_ok]');
  const total = 2 * pc.sell_price + 0.5 * kg.sell_price; log('bar total expect', total, '|', (await p.textContent('#pos_bar')).replace(/\s+/g, ' ').slice(0, 40));
  await p.click('[data-act=pos_cart]'); await p.waitForTimeout(300);
  log('default: one cash row =', await p.inputValue('[data-pay="0.amount"]'), '| customer block:', await p.locator('#cu_mobile').count());
  await p.screenshot({ path: SP + '/q_cart.png' });
  // wholesale needs a customer
  await p.click('[data-act=pos_type][data-v=wholesale]'); await p.waitForTimeout(150);
  log('wholesale -> customer block shown:', await p.locator('#cu_mobile').count());
  await p.click('#cart_ok'); log('no mobile ->', await toast());
  await p.fill('#cu_mobile', '+880 1712-345678'); await p.waitForTimeout(500);
  log('new customer name field:', await p.locator('#cu_name').count());
  await p.fill('#cu_name', 'Karim'); await p.screenshot({ path: SP + '/q_wholesale.png' });
  await p.click('#cart_ok'); await p.waitForTimeout(500);
  const L1 = await p.evaluate(() => window.__LAST); log('wholesale sent:', JSON.stringify({ type: L1.p_sale_type, mobile: L1.p_customer_mobile, name: L1.p_customer_name, pay: L1.p_payments }));
  log('toast:', await toast());
  // partial: retail, pay only 100 -> due -> customer required
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(200);
  await p.fill('[data-pay="0.amount"]', '40'); await p.waitForTimeout(200);
  log('partial: customer block auto shown:', await p.locator('#cu_mobile').count(), '| summary:', (await p.textContent('#pay_sum')).replace(/\s+/g, ' ').trim());
  await p.click('#cart_ok'); log('partial no customer ->', await toast());
  await p.fill('#cu_mobile', '01711111111'); await p.waitForTimeout(500);
  log('existing customer note:', (await p.textContent('#cart_cust')).replace(/\s+/g, ' ').slice(0, 90));
  await p.screenshot({ path: SP + '/q_partial.png' });
  await p.click('#cart_ok'); await p.waitForTimeout(400);
  const L2 = await p.evaluate(() => window.__LAST); log('partial sent: paid', L2.p_payments[0].amount, 'mobile', L2.p_customer_mobile, '| toast:', await toast());
  // split: cash + mobile
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(200);
  await p.click('[data-act=pay_add][data-m=mobile]'); await p.waitForTimeout(150);
  await p.fill('[data-pay="0.amount"]', '60'); await p.fill('[data-pay="1.amount"]', String(pc.sell_price - 60));
  await p.click('#cart_ok'); log('mobile without wallet ->', await toast());
  await p.selectOption('[data-pay="1.wallet"]', 'bkash'); await p.fill('[data-pay="1.ref"]', 'TX99'); await p.screenshot({ path: SP + '/q_split.png' });
  await p.click('#cart_ok'); await p.waitForTimeout(400);
  const L3 = await p.evaluate(() => window.__LAST); log('split sent:', JSON.stringify(L3.p_payments));
  // quick cash one tap
  await p.click('[data-act=pos_quick]'); await p.fill('#qs_amt', '250'); await p.click('[data-act=pos_qs_cash]'); await p.waitForTimeout(400);
  const L4 = await p.evaluate(() => window.__LAST); log('quick sent:', JSON.stringify({ lines: L4.p_lines, pay: L4.p_payments, quick: L4.p_quick }));
  // other item
  await p.click('[data-act=pos_other]'); await p.fill('#ot_name', 'Special box'); await p.fill('#ot_qty', '2'); await p.fill('#ot_unit', 'pc'); await p.fill('#ot_price', '120'); await p.click('[data-act=pos_ot_ok]');
  await p.click('[data-act=pos_cart]'); await p.waitForTimeout(200); await p.click('#cart_ok'); await p.waitForTimeout(400);
  const L5 = await p.evaluate(() => window.__LAST); log('custom line sent:', JSON.stringify(L5.p_lines));
  // discount modes: amount or percent
  let bad = 0; const okk = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(250);
  okk(await p.locator('#cart_dk .tog').count() === 2, 'both toggles shown'); okk(/৳/.test(await p.textContent('#cart_disc_l')), 'label shows ৳ by default');
  await p.click('[data-act=pos_dk][data-v=percent]'); await p.fill('#cart_disc', '10'); await p.waitForTimeout(150);
  const sub = pc.sell_price, dAmt = Math.round(sub * 10) / 100;
  log('percent live:', (await p.textContent('#cart_disc_calc')).trim(), '| total', (await p.textContent('#cart_total')).trim(), 'expect', sub - dAmt);
  okk((await p.textContent('#cart_disc_calc')).includes(String(dAmt)), 'computed amount shown'); okk((await p.textContent('#cart_total')).includes(String(sub - dAmt)), 'total follows percent');
  await p.screenshot({ path: SP + '/q_disc_pct.png' });
  await p.fill('#cart_disc', '150'); await p.click('#cart_ok'); okk(/১০০|100|মোটের বেশি|exceed/.test(await toast()), 'percent over 100 refused'); await p.fill('#cart_disc', '10');
  await p.click('#cart_ok'); await p.waitForTimeout(400);
  const D1 = await p.evaluate(() => window.__LAST); log('percent sent:', JSON.stringify({ d: D1.p_discount, k: D1.p_discount_kind, i: D1.p_discount_input }));
  okk(D1.p_discount_kind === 'percent' && D1.p_discount_input === 10 && D1.p_discount === dAmt, 'percent payload');
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(250); await p.fill('#cart_disc', '15'); await p.click('#cart_ok'); await p.waitForTimeout(400);
  const D2 = await p.evaluate(() => window.__LAST); log('amount sent:', JSON.stringify({ d: D2.p_discount, k: D2.p_discount_kind, i: D2.p_discount_input })); okk(D2.p_discount === 15 && D2.p_discount_kind === 'amount' && D2.p_discount_input === 15, 'amount payload');
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(250); await p.click('#cart_ok'); await p.waitForTimeout(400);
  const D3 = await p.evaluate(() => window.__LAST); okk(!('p_discount_kind' in D3) && D3.p_discount === 0, 'no discount -> payload unchanged (no new keys)');
  // rules: percent off -> no toggle, amount only
  await p.evaluate(() => { window.BOS.ENV.rules = Object.assign(window.BOS.ENV.rules || {}, { discount_mode_percent_on: { key: 'discount_mode_percent_on', value: false, default_value: true } }); });
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(250); okk(await p.locator('#cart_dk').count() === 0 && await p.locator('#cart_disc').count() === 1, 'percent off: no toggle, amount field'); await p.screenshot({ path: SP + '/q_disc_amt_only.png' });
  await p.evaluate(() => { window.BOS.ENV.rules.discount_mode_amount_on = { key: 'discount_mode_amount_on', value: false, default_value: true }; await_ = 1; }); await p.click('[data-act=closesheet]'); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(250);
  okk(await p.locator('#cart_disc').count() === 0, 'both off: no discount field'); await p.click('#cart_ok'); await p.waitForTimeout(300);
  await p.evaluate(() => { delete window.BOS.ENV.rules.discount_mode_percent_on; delete window.BOS.ENV.rules.discount_mode_amount_on; });
  // old-shape queued sale (no kind keys) still replays
  await p.evaluate(() => { const k = 'bos_pos_queue_u1'; const q = JSON.parse(localStorage.getItem(k) || '[]'); q.push({ p_client: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', p_loc: 1, p_lines: [{ item_id: null, name: 'Old', amount: 90 }], p_discount: 0, p_payments: [{ mode: 'cash', amount: 90 }], p_customer_mobile: null, p_customer_name: null, p_sale_type: 'retail', p_note: null, p_quick: true, p_sold_at: new Date().toISOString(), _t: 1, _total: 90, _paid: 90 }); localStorage.setItem(k, JSON.stringify(q)); });
  await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(500); okk((await p.evaluate(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length)) === 0, 'old queued sale replayed'); // bos105 (pos2b): since phase83 a queue replay goes through record_sale_offline (same args), so the stub's record_sale2 hook never sees it and window.__LAST is not updated; check __CALLS instead.
  { const oc = await p.evaluate(() => window.__CALLS.filter((c) => c[1] && c[1].p_client === 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa').map((c) => [c[0], c[1].p_lines[0].name, c[1].p_sale_type]));
    okk(oc.length === 1 && oc[0][0] === 'record_sale_offline' && oc[0][1] === 'Old' && oc[0][2] === 'retail', 'old queued payload sent once via record_sale_offline');
    await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(300);
    okk((await p.evaluate(() => window.__CALLS.filter((c) => c[1] && c[1].p_client === 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa').length)) === 1, 'second flush does not send it again'); }
  log('discount asserts failed:', bad);
  // server refusal message mapping
  await p.evaluate(() => { window.__FAIL = 'discount_needs_approval'; });
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(200); await p.fill('#cart_disc', '10'); await p.click('#cart_ok'); await p.waitForTimeout(300);
  log('refusal toast:', await toast()); await p.evaluate(() => { window.__FAIL = null; }); await p.click('[data-act=closesheet]');
  // offline queue with new payload
  await p.evaluate(() => { window.__OFFLINE = true; });
  await p.click('[data-act=pos_quick]'); await p.fill('#qs_amt', '70'); await p.click('[data-act=pos_qs_cash]'); await p.waitForTimeout(400);
  log('offline queue:', await p.evaluate(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length));
  await p.evaluate(() => { window.__OFFLINE = false; }); await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(400);
  log('after flush:', await p.evaluate(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length));
  // today
  await p.click('[data-act=pos_tab][data-v=today]'); await p.waitForTimeout(500); await p.screenshot({ path: SP + '/q_today.png' });
  log('today rows:', await p.locator('#pos_body .card.item').count());
  // dues page
  await p.goto('http://localhost:8084/#/dues'); await p.waitForTimeout(700);
  log('dues rows:', await p.locator('#du_list .card').count()); await p.screenshot({ path: SP + '/q_dues.png' });
  await p.click('#du_list .card >> nth=0'); await p.waitForTimeout(500); await p.screenshot({ path: SP + '/q_collect.png' });
  await p.fill('[data-pay="0.amount"]', '999'); await p.click('[data-act=du_collect]'); await p.waitForTimeout(300); log('overpay ->', await toast());
  await p.fill('[data-pay="0.amount"]', '100'); await p.click('[data-act=du_collect]'); await p.waitForTimeout(500);
  log('collected:', JSON.stringify(await p.evaluate(() => window.__COLL.p_payments)), '| toast:', await toast());
  log('errors:', errors.length ? [...new Set(errors)] : 'none'); await br.close(); srv.close();
})();
