// Step PBill (bos104): the real app (purchase.js + purchaseprint.js) in a phone-size browser with a mocked rpc.
// Run on its own: node tests/web/purchaseprint_pw_test.js <abs tests/web dir>      (serves ../../web of THIS checkout)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname, ROOT = path.join(__dirname, '..', '..', 'web'), PORT = 8494;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
data.tables.invoice_templates = data.tables.invoice_templates || []; data.tables.print_profiles = data.tables.print_profiles || [];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

const BILL = { id: 'pb1', kind: 'bill', status: 'posted', supplier_id: null, supplier_name: 'Test Supplier', bill_no: 'PB-7', bill_date: '2026-10-14', location_id: 1, subtotal: 300, discount: 20, total: 280, paid: 100, due: 180, note: 'Note <b>x</b>',
  lines: [{ qty: 2, unit: 'kg', unit_cost: 100, amount: 200, description: 'Sugar' }, { qty: 1, unit: 'pc', unit_cost: 100, amount: 100, description: '<img src=x onerror=alert(1)>' }], payments: [] };
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = [];
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]);
  if (fn === 'has_grant') return { data: true, error: null };
  if (fn === 'purchase_get') { if (window.__REFUSE) return { data: null, error: { message: 'not allowed' } }; return { data: Object.assign({}, ${JSON.stringify(BILL)}, window.__BILL || {}), error: null }; }
  if (fn === 'purchase_list') return window.__REFUSE ? { data: null, error: { message: 'not allowed' } } : { data: [{ id: 'pb1', kind: 'bill', status: 'posted', supplier_name: 'Test Supplier', bill_no: 'PB-7', bill_date: '2026-10-14', location_id: 1, n_lines: 2, total: 280, due: 180 }], error: null };
  if (fn === 'get_doc_templates') return { data: window.__CHOICES || [], error: null };
  return rpc(fn, args); }; return c; }; window.__IFR = [];
 const d = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'srcdoc'); Object.defineProperty(HTMLIFrameElement.prototype, 'srcdoc', { set(v) { window.__IFR.push(v); d.set.call(this, v); }, get() { return d.get.call(this); } });
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
  const noOverflow = async (m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1 && (!document.querySelector('#sheet .sheet') || document.querySelector('#sheet .sheet').scrollWidth <= document.querySelector('#sheet .sheet').clientWidth + 1)), 'no horizontal overflow: ' + m);
  await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1000);
  await p.evaluate(() => { location.hash = '#/purchase/pb1'; }); await p.waitForTimeout(1200);
  // 1. the button group on the bill page
  ok(await p.locator('#pbp_grp').count() === 1, 'group injected on the bill page: ' + (await p.textContent('#app')).replace(/\s+/g, ' ').slice(0, 160));
  ok(/Test Supplier/.test(await p.textContent('#app')) && await p.locator('#app .s2-led').count() >= 1, 'purchase.js bill page itself intact');
  await noOverflow('bill page'); await p.screenshot({ path: SP + '/pbill_page.png' });
  // 2. open the sheet
  await p.click('#pbp_grp [data-act=pbp_open] >> nth=-1'); await p.waitForTimeout(600);
  ok(await p.locator('#sheet [data-pbp=card]').count() === 1, 'sheet opened');
  for (const a of ['print', 'grn', 'share', 'dl', 'email_go', 'sms', 'wa']) ok(await p.locator(`[data-act=pbp_${a}]`).count() === 1, 'button ' + a);
  ok(!/[ঀ-৲৴-৿]/.test(await p.textContent('#sheet')), 'English mode: no Bangla letters in the sheet');
  await noOverflow('sheet'); await p.screenshot({ path: SP + '/pbill_sheet.png' });
  // 3. print: built-in layout (nothing chosen)
  await p.click('[data-act=pbp_print]'); await p.waitForTimeout(700);
  const ifr = await p.evaluate(() => window.__IFR); ok(ifr.length === 1 && ifr[0].includes('data-pbp="builtin"') && ifr[0].includes('Test Supplier') && !ifr[0].includes('<img src=x') && ifr[0].includes('&lt;img'), 'built-in print page, escaped');
  ok(await p.locator('#pbp_np .notice').count() === 0, 'no printer warning when print works');
  // printed layout screenshot
  const pp = await ctx.newPage(); await pp.setViewportSize({ width: 794, height: 900 }); await pp.setContent(ifr[0]); await pp.screenshot({ path: SP + '/pbill_printed_builtin.png' });
  await pp.setViewportSize({ width: 360, height: 780 }); ok(await pp.evaluate(() => document.documentElement.scrollWidth <= 361), 'built-in printed page also fits 360px'); await pp.screenshot({ path: SP + '/pbill_printed_360.png' });
  // 4. GRN
  await p.click('[data-act=pbp_grn]'); await p.waitForTimeout(500); const ifr2 = await p.evaluate(() => window.__IFR); ok(ifr2.length === 2 && ifr2[1].includes('Goods Received Note') && !/Rate/.test(ifr2[1]), 'GRN page has no rates');
  // 5. links
  await p.fill('#pbp_email', 'sup@example.com'); await p.fill('#pbp_phone', '01711 000002');
  await p.click('[data-act=pbp_wa]'); await p.click('[data-act=pbp_sms]'); await p.click('[data-act=pbp_email_go]'); await p.click('[data-act=pbp_dl]'); await p.waitForTimeout(300);
  const cl = await p.evaluate(() => window.__CLICKS);
  ok(cl.length === 4 && /^https:\/\/wa\.me\/8801711000002\?text=/.test(cl[0].href) && /^sms:\+8801711000002\?body=/.test(cl[1].href) && /^mailto:sup@example\.com\?subject=/.test(cl[2].href) && /^purchase-bill-PB-7\.html$/.test(cl[3].download), 'links: ' + JSON.stringify(cl.map((c) => (c.href || c.download).slice(0, 40))));
  await p.click('#sheet [data-act=closesheet] >> nth=-1'); await p.waitForTimeout(200);
  // 6. chosen template, void marking
  await p.evaluate(() => { window.__CHOICES = [{ doc_type: 'purchase_bill', template_id: 'a4_formal', location_id: null }]; window.__BILL = { status: 'void', void_note: 'wrong supplier' }; window.BOS.tpl.ensureReset(); });
  await p.evaluate(() => window.BOS.purchaseprint.open('pb1')); await p.waitForTimeout(500); await p.click('[data-act=pbp_print]'); await p.waitForTimeout(700);
  const ifr3 = await p.evaluate(() => window.__IFR); const last = ifr3[ifr3.length - 1];
  ok(last.includes('data-tpl="a4_formal"') && last.includes('data-pbp="status"') && last.includes('VOID'), 'chosen template used and VOID marked');
  const pp2 = await ctx.newPage(); await pp2.setViewportSize({ width: 794, height: 900 }); await pp2.setContent(last); await pp2.screenshot({ path: SP + '/pbill_printed_template_void.png' });
  await p.click('#sheet [data-act=closesheet] >> nth=-1'); await p.waitForTimeout(200);
  // 7. the page route
  await p.goto(`http://localhost:${PORT}/#/purchaseprint`); await p.waitForTimeout(1000);
  ok(await p.locator('#pbp_list .card.item').count() === 1, 'route page lists the bill'); await noOverflow('route page'); await p.screenshot({ path: SP + '/pbill_route.png' });
  await p.click('#pbp_list [data-act=pbp_quick]'); await p.waitForTimeout(800); ok((await p.evaluate(() => window.__IFR)).length >= 4, 'row Print button prints');
  await p.click('#sheet [data-act=closesheet] >> nth=-1'); await p.waitForTimeout(200);
  // 8. refusal: nothing shown
  await p.evaluate(() => { window.__REFUSE = true; }); const n0 = (await p.evaluate(() => window.__IFR)).length;
  await p.evaluate(() => window.BOS.purchaseprint.open('pb1')); await p.waitForTimeout(400); ok(await p.locator('#sheet').count() === 0, 'refused: no sheet');
  await p.evaluate(() => { location.hash = '#/home'; }); await p.waitForTimeout(300); await p.evaluate(() => { location.hash = '#/purchaseprint'; }); await p.waitForTimeout(900); ok(!/Test Supplier|280/.test(await p.textContent('#app')), 'refused: route page shows no bill');
  await p.goto(`http://localhost:${PORT}/#/home`); await p.evaluate(() => { window.__REFUSE = true; location.hash = '#/purchase/pb1'; }); await p.waitForTimeout(900); ok(await p.locator('#pbp_grp').count() === 0, 'refused: no button group');
  // 9. Bangla mode
  await p.evaluate(() => { window.__REFUSE = false; window.__BILL = null; localStorage.setItem('bos_lang', 'bn'); }); await p.reload(); await p.waitForTimeout(1200);
  await p.evaluate(() => { location.hash = '#/home'; }); await p.waitForTimeout(300); await p.evaluate(() => { location.hash = '#/purchase/pb1'; }); await p.waitForTimeout(1200);
  ok(await p.locator('#pbp_grp').count() === 1, 'Bangla mode: group present'); await p.click('#pbp_grp [data-act=pbp_open] >> nth=-1'); await p.waitForTimeout(500); await noOverflow('bangla sheet'); await p.screenshot({ path: SP + '/pbill_sheet_bn.png' });
  const real = [...new Set(errors)].filter((e) => !/Failed to load resource|favicon/.test(e));
  log(`purchaseprint_pw_test: ${pass} pass / ${bad} fail | page errors:`, real.length ? real : 'none'); await br.close(); srv.close(); process.exit(bad || real.length ? 1 : 0);
})();
