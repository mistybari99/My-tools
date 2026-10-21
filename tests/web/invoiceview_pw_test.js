// Step Inv (bos92): the real app (pos.js + invoice.js + invoiceview.js) in a phone-size browser with a mocked rpc.
// Run on its own: node tests/web/invoiceview_pw_test.js <abs tests/web dir>      (serves ../../web of THIS checkout)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname, ROOT = _P.WEB_DIR, PORT = _P.freePort();
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
data.tables.invoice_templates = data.tables.invoice_templates || []; data.tables.print_profiles = data.tables.print_profiles || [];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = [];
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]);
  if (fn === 'has_grant') return { data: true, error: null };
  if (fn === 'find_customer') return { data: { found: false, mobile: args.p_mobile }, error: null };
  if (fn === 'record_sale2' || fn === 'record_sale_offline') { if (window.__OFFLINE) return { data: null, error: { message: 'TypeError: Failed to fetch' } };
    const T = window.__DATA.tables, S = T.sales = T.sales || [];
    const tot = args.p_lines.reduce((s, l) => s + (l.amount !== undefined ? l.amount : l.qty * (l.item_id ? T.items.find((i) => i.id === l.item_id).sell_price : l.price)), 0) - args.p_discount;
    const paid = (args.p_payments || []).reduce((s, p) => s + p.amount, 0);
    const row = { id: 's' + (S.length + 1), receipt: S.length + 1, location_id: args.p_loc, sale_date: new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }), sold_at: new Date().toISOString(), lines: args.p_lines.map((l) => ({ ...l, amount: l.amount !== undefined ? l.amount : l.qty * (l.item_id ? T.items.find((i) => i.id === l.item_id).sell_price : l.price) })), subtotal: tot + args.p_discount, discount: args.p_discount, total: tot, pay_mode: 'cash', quick: args.p_quick, status: 'done', created_staff: 'owner1', paid, due_amount: tot - paid, customer: args.p_customer_name, client_id: args.p_client };
    S.push(row); return { data: { id: row.id, receipt: row.receipt, total: tot, paid, due: tot - paid }, error: null }; }
  if (fn === 'invoice_data92') { if (window.__OFFLINE || window.__NOINV) return { data: null, error: { message: window.__NOINV ? 'Could not find the function' : 'TypeError: Failed to fetch' } };
    const T = window.__DATA.tables, s = (T.sales || []).find((x) => x.id === args.p_sale || (args.p_client && x.client_id === args.p_client)); if (!s) return { data: null, error: { message: 'not_found' } };
    return { data: { id: s.id, client_id: s.client_id, receipt: s.receipt, location_id: s.location_id, location_code: 'M', location: { bn: 'প্রধান', en: 'Main branch', mix: 'Main' }, sale_date: s.sale_date, sold_at: s.sold_at, status: s.status, cashier: 'owner1',
      lines: s.lines.map((l) => ({ item_id: l.item_id, code: 'C1', name: l.name || 'Item', name_en: l.name || 'Item', unit: 'pc', qty: l.qty || 1, price: l.price || l.amount, amount: l.amount })), subtotal: s.subtotal, discount: s.discount, total: s.total, paid: s.paid, due: s.due_amount,
      payments: [{ mode: 'cash', wallet: null, amount: s.paid }], vat: null, customer: s.customer ? { name: s.customer, mobile: '01711000001', masked: false } : null, shares: [] }, error: null }; }
  if (fn === 'invoice_share_log92') { (window.__SHARES = window.__SHARES || []).push(args); return { data: 1, error: null }; }
  return rpc(fn, args); }; return c; }; window.__PRINTS = 0; window.print = () => { window.__PRINTS++; };
 window.__CLICKS = []; const oc = HTMLAnchorElement.prototype.click; HTMLAnchorElement.prototype.click = function () { if (/^(mailto:|sms:|https:\\/\\/wa\\.me)/.test(this.href) || this.download) { window.__CLICKS.push({ href: this.href, target: this.target, download: this.download }); return; } return oc.call(this); };
 })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, pass = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (c) pass++; else { bad++; log('FAIL:', m); } };
  const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{if(!localStorage.getItem('bos_lang'))localStorage.setItem('bos_lang','en');}catch(e){}`);
  const noOverflow = async (m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1 && (!document.querySelector('#sheet .sheet') || document.querySelector('#sheet .sheet').scrollWidth <= document.querySelector('#sheet .sheet').clientWidth + 1)), 'horizontal overflow ' + m);
  const setRule = (v) => p.evaluate((x) => { window.BOS.ENV.rules = window.BOS.ENV.rules || {}; window.BOS.ENV.rules.pos_show_invoice_after_sale = { key: 'pos_show_invoice_after_sale', value: x, default_value: 'never' }; }, v);
  const pc = data.tables.items.find((i) => i.unit === 'pc');
  const sell = async () => { await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(250); await p.click('#cart_ok'); await p.waitForTimeout(700); };
  await p.goto(`http://localhost:${PORT}/#/pos`); await p.waitForTimeout(1000);

  // 1. default (rule absent = never): exactly as before, the small print bar, no invoice sheet
  await sell(); ok(await p.locator('#sheet').count() === 0 && await p.locator('#iv_offer').count() === 1 && await p.locator('#iv92_bar').count() === 0, 'never: old behaviour (print bar only)');
  await p.evaluate(() => { const o = document.getElementById('iv_offer'); if (o) o.remove(); });

  // 2. always
  await setRule('always'); await sell();
  ok(await p.locator('#sheet [data-iv92=card]').count() === 1, 'always: invoice card on screen'); ok(await p.locator('#iv_offer').count() === 0, 'always: old print bar removed');
  const card = (await p.textContent('#iv92_card')).replace(/\s+/g, ' '); ok(/Invoice/.test(card) && new RegExp('৳ ' + pc.sell_price).test(card), 'card has the total: ' + card.slice(0, 120));
  for (const a of ['print', 'sms', 'wa', 'email', 'share', 'copy', 'dl']) ok(await p.locator(`[data-act=iv92_${a}]`).count() === 1, 'button ' + a);
  await noOverflow('invoice sheet'); await p.screenshot({ path: SP + '/inv92_always.png' });
  // sheet scrolls on a small phone: the Close button is reachable
  await p.locator('#sheet [data-act=closesheet] >> nth=-1').scrollIntoViewIfNeeded(); ok(await p.locator('#sheet [data-act=closesheet] >> nth=-1').isVisible(), 'close reachable');
  await p.screenshot({ path: SP + '/inv92_always_bottom.png' });
  // print
  await p.click('[data-act=iv92_print]'); await p.waitForTimeout(600); ok(await p.evaluate(() => window.__PRINTS) === 1, 'Print reached window.print through the existing path');
  ok(await p.evaluate(() => (window.__SHARES || []).some((x) => x.p_channel === 'print' && x.p_sale)), 'print logged');
  // print not available -> friendly text
  await p.evaluate(() => { window.__realPrint = window.print; window.print = () => { throw new Error('no printer'); }; });
  await p.click('[data-act=iv92_print]'); await p.waitForTimeout(600); ok(/Printing did not work/.test(await p.textContent('#iv92_np')) && /Share or Download/.test(await p.textContent('#iv92_np')), 'no-printer fallback text'); await p.screenshot({ path: SP + '/inv92_noprinter.png' });
  await p.evaluate(() => { window.print = window.__realPrint; });
  // deep links
  await p.fill('#iv92_phone', '01711 000001'); await p.fill('#iv92_email', 'buyer@example.com');
  await p.click('[data-act=iv92_wa]'); await p.click('[data-act=iv92_sms]'); await p.click('[data-act=iv92_email]'); await p.waitForTimeout(300);
  const cl = await p.evaluate(() => window.__CLICKS);
  ok(cl.length === 3 && /^https:\/\/wa\.me\/8801711000001\?text=/.test(cl[0].href) && /^sms:\+8801711000001\?body=/.test(cl[1].href) && /^mailto:buyer@example\.com\?subject=/.test(cl[2].href), 'three deep links: ' + JSON.stringify(cl.map((c) => c.href.slice(0, 40))));
  ok(/Total/.test(decodeURIComponent(cl[0].href)), 'wa text has the total');
  const sh = await p.evaluate(() => window.__SHARES.map((x) => x.p_channel).join()); ok(/whatsapp/.test(sh) && /sms/.test(sh) && /email/.test(sh), 'channels logged: ' + sh);
  ok(!(await p.evaluate(() => JSON.stringify(window.__SHARES))).match(/01711|buyer@/), 'the typed number / address is not sent to the log');
  await p.click('[data-act=iv92_dl]'); await p.waitForTimeout(300); ok((await p.evaluate(() => window.__CLICKS)).some((c) => /^invoice-M-\d+\.html$/.test(c.download)), 'download file name');
  await p.click('[data-act=iv92_copy]'); await p.waitForTimeout(200);
  await p.click('#sheet [data-act=closesheet] >> nth=-1'); await p.waitForTimeout(200);

  // 3. ask
  await setRule('ask'); await sell(); ok(await p.locator('#iv92_bar').count() === 1 && await p.locator('#sheet').count() === 0 && await p.locator('#iv_offer').count() === 0, 'ask: bar only');
  await p.screenshot({ path: SP + '/inv92_ask.png' }); await p.click('[data-act=iv92_show]'); await p.waitForTimeout(500); ok(await p.locator('#sheet [data-iv92=card]').count() === 1 && await p.locator('#iv92_bar').count() === 0, 'ask: tap shows the invoice');
  await p.click('#sheet [data-act=closesheet] >> nth=-1');

  // 4. offline queued sale: provisional number, pending
  await setRule('always'); await p.evaluate(() => { window.__OFFLINE = true; });
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(250); await p.click('#cart_ok'); await p.waitForTimeout(700);
  const pend = (await p.textContent('#sheet')).replace(/\s+/g, ' ');
  ok(/Q-[0-9A-F]{6}/.test(pend) && /Pending sync/.test(pend), 'offline: provisional number + pending note: ' + pend.slice(0, 160));
  ok(await p.evaluate(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length) >= 1, 'sale is in the local queue'); await noOverflow('pending'); await p.screenshot({ path: SP + '/inv92_pending.png' });
  await p.evaluate(() => { window.__OFFLINE = false; }); await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(600);
  await p.click('[data-act=iv92_check]'); await p.waitForTimeout(600); ok(!/Pending sync/.test(await p.textContent('#iv92_pend')) && /M-\d+/.test(await p.textContent('#iv92_card')), 'after sync: check shows the final number');
  await p.click('#sheet [data-act=closesheet] >> nth=-1');

  // 5. old database (function missing): the cart copy is shown, no error
  await p.evaluate(() => { window.__NOINV = true; }); const nErr = errors.length; await sell(); ok(await p.locator('#sheet [data-iv92=card]').count() === 1, 'function missing: still shows the invoice'); ok(errors.length === nErr, 'no page error'); await p.evaluate(() => { window.__NOINV = false; });
  await p.click('#sheet [data-act=closesheet] >> nth=-1');

  // 6. from today's list and the invoices page
  await p.click('[data-act=pos_tab][data-v=today]'); await p.waitForTimeout(600); await p.click('#pos_body .card.item >> nth=0'); await p.waitForTimeout(500);
  ok(await p.locator('[data-act=iv92_open]').count() === 1, 'today sheet has the invoice button'); await p.click('[data-act=iv92_open]'); await p.waitForTimeout(600); ok(await p.locator('#sheet [data-iv92=card]').count() === 1, 'history open shows the invoice'); await noOverflow('history');
  await p.click('#sheet [data-act=closesheet] >> nth=-1');
  await p.goto(`http://localhost:${PORT}/#/invoiceview`); await p.waitForTimeout(900); ok(await p.locator('#iv92_list .card.item').count() >= 1, 'invoices page lists sales'); await noOverflow('invoices page'); await p.screenshot({ path: SP + '/inv92_page.png' });
  await p.click('#iv92_list .card.item >> nth=0'); await p.waitForTimeout(500); ok(await p.locator('#sheet [data-iv92=card]').count() === 1, 'page row opens the invoice');

  // 7. Bangla mode renders, no overflow
  await p.evaluate(() => { localStorage.setItem('bos_lang', 'bn'); }); await p.reload(); await p.waitForTimeout(1000); await setRule('always'); await p.goto(`http://localhost:${PORT}/#/pos`); await p.waitForTimeout(800); await setRule('always');
  await sell(); ok(await p.locator('#sheet [data-iv92=card]').count() === 1 && /প্রিন্ট/.test(await p.textContent('[data-act=iv92_print]')), 'Bangla mode'); await noOverflow('bangla'); await p.screenshot({ path: SP + '/inv92_bn.png' });

  const real = [...new Set(errors)].filter((e) => !/Failed to load resource|favicon/.test(e));
  log(`invoiceview_pw_test: ${pass} pass / ${bad} fail | page errors:`, real.length ? real : 'none'); await br.close(); srv.close(); process.exit(bad || real.length ? 1 : 0);
})();
