const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8079);
const EXTRA = `
(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 c.rpc = async (fn, args) => {
  if (fn === 'record_sale') { if (window.__OFFLINE) return { data: null, error: { message: 'TypeError: Failed to fetch' } };
    const S = window.__DATA.tables.sales = window.__DATA.tables.sales || [];
    const dup = S.find((s) => s.client_id === args.p_client); if (dup) return { data: { id: dup.id, receipt: dup.receipt, total: dup.total, dup: true }, error: null };
    const lines = args.p_lines.map((l) => { const it = l.item_id ? window.__DATA.tables.items.find((i) => i.id === l.item_id) : null; const price = it ? (l.override ? l.price : it.sell_price) : l.amount; const qty = it ? l.qty : 1; return { item_id: l.item_id, name: l.name, qty, price, amount: qty * price, override: !!l.override }; });
    const sub = lines.reduce((s, l) => s + l.amount, 0); const row = { id: 's' + (S.length + 1), client_id: args.p_client, receipt: S.length + 1, location_id: args.p_loc, sale_date: new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }), sold_at: new Date().toISOString(), lines, subtotal: sub, discount: args.p_discount, total: sub - args.p_discount, pay_mode: args.p_mode, customer: args.p_customer, note: args.p_note, quick: args.p_quick, status: 'done', created_staff: 'owner1' };
    S.push(row); window.__LAST = args; return { data: { id: row.id, receipt: row.receipt, total: row.total }, error: null }; }
  if (fn === 'sales_summary') { const out = {}; (window.__DATA.tables.sales || []).forEach((s) => { const k = [s.sale_date, s.location_id, s.pay_mode, s.status].join('|'); const o = out[k] = out[k] || { sale_date: s.sale_date, location_id: s.location_id, pay_mode: s.pay_mode, status: s.status, n: 0, total: 0, discount: 0 }; o.n++; o.total += s.total; o.discount += s.discount || 0; }); return { data: Object.values(out), error: null }; }
  if (fn === 'void_sale') { const s = window.__DATA.tables.sales.find((x) => x.id === args.p_id); s.status = 'void'; s.void_note = args.p_note; s.void_staff = 'owner1'; return { data: null, error: null }; }
  return rpc(fn, args); }; return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a);
  const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, deviceScaleFactor: 2, locale: 'bn-BD' }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  p.on('dialog', (d) => d.accept(d.defaultValue()));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn');localStorage.removeItem('bos_pos_queue_u1')}catch(e){}`);
  await p.goto('http://localhost:8079/#/home'); await p.waitForTimeout(700);
  log('home has POS tile:', await p.locator('.tile', { hasText: 'সেল (POS)' }).count());
  await p.click('.tile >> text=সেল (POS)'); await p.waitForTimeout(600);
  log('items on grid:', await p.locator('.pos-item').count());
  await p.screenshot({ path: SP + '/p_sell.png' });
  // pc item adds directly, kg item opens quantity sheet
  const pcItem = data.tables.items.find((i) => i.unit === 'pc'), kgItem = data.tables.items.find((i) => i.unit === 'kg');
  await p.click(`.pos-item[data-v="${pcItem.id}"]`); await p.click(`.pos-item[data-v="${pcItem.id}"]`);
  await p.click(`.pos-item[data-v="${kgItem.id}"]`); await p.waitForTimeout(200); await p.screenshot({ path: SP + '/p_qty.png' });
  await p.click('[data-act=pos_q_set][data-n="0.5"]'); await p.click('[data-act=pos_q_ok]');
  log('bar:', (await p.locator('#pos_bar').textContent()).replace(/\s+/g, ' '), '| expect', 2 * pcItem.sell_price + 0.5 * kgItem.sell_price);
  await p.click('[data-act=pos_cart]'); await p.waitForTimeout(200);
  await p.fill('#cart_disc', '10'); await p.fill('#cart_given', '5000'); await p.waitForTimeout(100);
  log('total/change:', await p.textContent('#cart_total'), '|', (await p.textContent('#cart_change')).trim());
  await p.screenshot({ path: SP + '/p_cart.png' });
  await p.click('#cart_ok'); await p.waitForTimeout(500);
  log('toast:', await p.textContent('#toast'));
  log('sent:', JSON.stringify({ mode: (await p.evaluate(() => window.__LAST)).p_mode, disc: (await p.evaluate(() => window.__LAST)).p_discount, lines: (await p.evaluate(() => window.__LAST)).p_lines.length }));
  // quick sale
  await p.click('[data-act=pos_quick]'); await p.fill('#qs_amt', '250'); await p.click('[data-act=pos_qmode][data-v=mobile]'); await p.screenshot({ path: SP + '/p_quick.png' }); await p.click('[data-act=pos_qs_ok]'); await p.waitForTimeout(400);
  log('quick toast:', await p.textContent('#toast'));
  // due requires customer
  await p.click('[data-act=pos_quick]'); await p.fill('#qs_amt', '90'); await p.click('[data-act=pos_qmode][data-v=due]'); await p.click('[data-act=pos_qs_ok]'); await p.waitForTimeout(200);
  log('due without name:', await p.textContent('#toast')); await p.fill('#qs_c', 'Karim'); await p.click('[data-act=pos_qs_ok]'); await p.waitForTimeout(400);
  // offline: queued, then flushed
  await p.evaluate(() => { window.__OFFLINE = true; });
  await p.click('[data-act=pos_quick]'); await p.fill('#qs_amt', '70'); await p.click('[data-act=pos_qmode][data-v=cash]'); await p.click('[data-act=pos_qs_ok]'); await p.waitForTimeout(400);
  log('offline toast:', await p.textContent('#toast'), '| queue len:', await p.evaluate(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length), '| chip:', await p.locator('#pos_q').count());
  await p.evaluate(() => { window.__OFFLINE = false; }); await p.evaluate(() => window.BOS.pos.flush()); await p.waitForTimeout(400);
  log('after flush queue:', await p.evaluate(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length), '| sales stored:', await p.evaluate(() => window.__DATA.tables.sales.length));
  // today + void
  await p.click('[data-act=pos_tab][data-v=today]'); await p.waitForTimeout(500); await p.screenshot({ path: SP + '/p_today.png' });
  log('today rows:', await p.locator('#pos_body .card.item').count(), '| header:', (await p.locator('#pos_body .card').first().textContent()).replace(/\s+/g, ' ').slice(0, 120));
  await p.click('#pos_body .card.item >> nth=0'); await p.waitForTimeout(200);
  await p.click('[data-act=pos_void]'); log('void w/o note:', await p.textContent('#toast'));
  await p.fill('#void_note', 'wrong item'); await p.click('[data-act=pos_void]'); await p.waitForTimeout(500);
  log('voided rows:', await p.locator('.chip.bad', { hasText: 'বাতিল' }).count());
  await p.screenshot({ path: SP + '/p_today2.png' });
  await p.evaluate(() => { const T = window.__DATA.tables; T.exceptions = [{ id: 1, level: 'red', status: 'open' }, { id: 2, level: 'yellow', status: 'open' }]; T.entries = (T.entries || []).concat([{ id: 'x1', form_code: '10-2', location_id: 1, serial: 7, entry_date: '2026-10-11', status: 'submitted', created_staff: 'karim02', flags: [{ level: 'red' }], created_by: 'u2' }]); });
  await p.goto('http://localhost:8079/#/pending'); await p.waitForTimeout(500); log('pending rows:', await p.locator('.card.item').count());
  await p.goto('http://localhost:8079/#/home'); await p.waitForTimeout(900); await p.screenshot({ path: SP + '/p_home.png', fullPage: false });
  log('dash rows:', (await p.locator('.dash-row').allTextContents()).map((s) => s.replace(/\s+/g, ' ').trim()));
  log('JS errors:', errors.length ? errors : 'none');
  await br.close(); srv.close();
})();
