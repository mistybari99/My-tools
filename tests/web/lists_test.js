const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
data.tables.option_lists = [
 { list_code: 'marketing_heads', value_code: '1', label_bn: 'অনলাইন বিজ্ঞাপন', label_en: 'Online ads', sort: 1, active: true, extra: { limit_month: 5000 } },
 { list_code: 'marketing_heads', value_code: '2', label_bn: 'ছাপা', label_en: 'Printing', sort: 2, active: true, extra: {} },
 { list_code: 'expense_heads', value_code: 'transport', label_bn: 'যাতায়াত', label_en: 'Transport', sort: 1, active: true, extra: {} },
 { list_code: 'expense_heads', value_code: 'fuel', label_bn: 'জ্বালানি', label_en: 'Fuel', sort: 2, active: true, extra: {} }];
data.tables.location_settings = [];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8085);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn')}catch(e){}`);
  await p.goto('http://localhost:8085/#/lists'); await p.waitForTimeout(800);
  await p.click('[data-act=ls2_pick][data-v=marketing_heads]'); await p.waitForTimeout(400);
  console.log('lists cards:', await p.locator('.card.stack').count()); await p.screenshot({ path: SP + '/l_lists.png' });
  // 10-2 uses the edited expense heads; 18-1 uses marketing heads
  await p.goto('http://localhost:8085/#/entry/new/10-2/1'); await p.waitForTimeout(800);
  console.log('10-2 head options:', (await p.locator('select[data-p="lines.0.head"] option').allTextContents()).join(' | '));
  await p.goto('http://localhost:8085/#/entry/new/18-1/1'); await p.waitForTimeout(800);
  console.log('18-1 head options:', (await p.locator('select[data-p="lines.0.head"] option').allTextContents()).join(' | '));
  await p.goto('http://localhost:8085/#/locset'); await p.waitForTimeout(800);
  console.log('locset h2:', await p.locator('#ls_body h2').allTextContents());
  console.log('mkt_limit visible inputs:', await p.locator('[id^=lv_mkt_limit]').count(), '| fridge rows:', await p.locator('[id^=lv_fridge]').count(), '| daytag:', await p.locator('[id^=lv_daytag]').count());
  await p.screenshot({ path: SP + '/l_locset.png', fullPage: false });
  // Bng-Eng rendering of settings labels
  await p.evaluate(() => localStorage.setItem('bos_lang', 'mix')); await p.reload(); await p.waitForTimeout(800);
  console.log('mix labels sample:', (await p.locator('#ls_body .card b').allTextContents()).slice(3, 8));
  console.log('errors:', errors.length ? [...new Set(errors)] : 'none'); await br.close(); srv.close();
})();
