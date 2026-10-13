// POS: sell in another unit (Kg / Pc) + bigger item names. Run: node pos_units_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const data = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.css') ? 'text/css' : 'text/html' }); r.end(b); }); }).listen(8086);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = [];
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]); if (fn === 'record_sale2') { window.__LAST = args; return { data: { id: 's1', receipt: 1, total: 0, paid: 0, due: 0 }, error: null }; } if (['find_customer','customer_dues','payments_summary','sales_summary'].includes(fn)) return { data: fn === 'find_customer' ? null : [], error: null }; return rpc(fn, args); }; return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } };
  const kg = data.tables.items.find((i) => i.unit === 'kg' && i.sell_price), pc = data.tables.items.find((i) => i.unit === 'pc' && i.sell_price);
  data.tables.unit_conversions = [{ id: 1, item_id: kg.id, from_unit: 'pc', to_unit: 'kg', factor: 0.5, active: true }];
  const ctx = await br.newContext({ viewport: { width: 390, height: 800 } }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('4'));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en');}catch(e){}`);
  await p.goto('http://localhost:8086/#/pos'); await p.waitForTimeout(1000);
  const fs1 = await p.evaluate((id) => parseFloat(getComputedStyle(document.querySelector(`.pos-item[data-v="${id}"] .pn`)).fontSize), kg.id); ok(fs1 >= 18, 'item name font is at least 18px (was ' + fs1 + ')');
  // a kg item that also has a pc conversion: the sheet offers both units
  await p.click(`.pos-item[data-v="${kg.id}"]`); await p.waitForTimeout(200);
  ok(await p.locator('[data-act=pos_q_unit]').count() === 2, 'two unit chips (Kg and Piece)');
  await p.click('[data-act=pos_q_unit][data-u="pc"]'); await p.waitForTimeout(200);
  await p.fill('#pos_qty', '3'); await p.waitForTimeout(100);
  ok(/1\.5/.test(await p.textContent('#pos_qconv')), 'conversion hint shows 3 pc = 1.5 kg: ' + (await p.textContent('#pos_qconv')));
  await p.click('[data-act=pos_q_ok]'); await p.waitForTimeout(200);
  await p.click('[data-act=pos_cart]'); await p.waitForTimeout(300);
  const cl = await p.textContent('#cart_lines'); ok(/3\s*Piece/.test(cl), 'cart line shows the 3 pieces typed: ' + cl.replace(/\s+/g, ' ').slice(0, 120));
  await p.click('[data-act=pos_step][data-d="1"]'); await p.waitForTimeout(150);
  ok(/4\s*Piece/.test(await p.textContent('#cart_lines')), 'stepper steps whole pieces');
  await p.click('#cart_ok'); await p.waitForTimeout(600);
  const last = await p.evaluate(() => window.__LAST); ok(last && last.p_lines[0].item_id === kg.id && Math.abs(last.p_lines[0].qty - 2) < 1e-9, 'the server gets the quantity in the item unit (4 pc x 0.5 = 2 kg): ' + JSON.stringify(last && last.p_lines[0]));
  // a piece item without any conversion still adds with one tap
  await p.goto('http://localhost:8086/#/pos'); await p.reload(); await p.waitForTimeout(900);
  await p.click(`.pos-item[data-v="${pc.id}"]`); await p.waitForTimeout(150);
  ok(await p.locator('[data-act=pos_q_unit]').count() === 0 && /1/.test(await p.textContent('#pos_bar')), 'a piece item with no conversion adds at once');
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close(); srv.close();
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
