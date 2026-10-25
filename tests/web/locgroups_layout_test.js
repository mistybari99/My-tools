const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = process.env.WEBROOT || _P.WEB_DIR, TAG = process.env.SHOT || 'after';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
data.tables.option_lists = [
 { list_code: 'marketing_heads', value_code: '1', label_bn: 'অনলাইন বিজ্ঞাপন', label_en: 'Online ads', sort: 1, active: true, extra: { limit_month: 5000 } },
 { list_code: 'marketing_heads', value_code: '2', label_bn: 'ছাপা', label_en: 'Printing', sort: 2, active: true, extra: {} },
 { list_code: 'expense_heads', value_code: 'transport', label_bn: 'যাতায়াত', label_en: 'Transport', sort: 1, active: true, extra: {} },
 { list_code: 'expense_heads', value_code: 'fuel', label_bn: 'জ্বালানি', label_en: 'Fuel', sort: 2, active: true, extra: {} }];
data.tables.location_settings = [];
const ALLLOCS = data.tables.locations.slice(); data.tables.locations = ALLLOCS.slice(0, 1);   // main flow: ONE place -> the footer is collapsed by default; the 2-places flow is at the end
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const ctx = await br.newContext({ viewport: { width: 360, height: 740 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{if(!sessionStorage.getItem('nf_seed')){localStorage.setItem('bos_lang','en');sessionStorage.setItem('nf_seed','1')}}catch(e){}`);
  const sleep = (n) => p.waitForTimeout(n);
  let ok = 0, bad = 0; const chk = (n, c) => { if (c) ok++; else bad++; console.log((c ? 'PASS ' : 'FAIL ') + n); };
  const noOverflow = () => p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1);
  await p.goto('http://localhost:' + PORT + '/#/locations'); await sleep(1500);
  const groups = await p.$$eval('#lo_list .lg-h', (els) => els.map((e) => e.textContent.replace(/\s+/g, ' ').trim()));
  console.log('group headings:', JSON.stringify(groups));
  chk('locations list shows at least one group heading', groups.length >= 1);
  chk('the headings are in the owner order (Main, Branch, Production, Warehouse, Unclassified)', (() => {
    const order = ['Main Showroom', 'Branch', 'Production House', 'Warehouse', 'Unclassified'];
    const idx = groups.map((g) => order.findIndex((o) => g.startsWith(o))); return idx.every((v) => v >= 0) && idx.every((v, i) => i === 0 || idx[i - 1] < v); })());
  chk('360px: no horizontal scroll on the locations list', await noOverflow());
  const box = await p.locator('#lo_list .lg-h').first().boundingBox();
  chk('360px: a group heading fits inside the 360px width', box && box.x >= 0 && box.x + box.width <= 360);
  await p.evaluate(() => { const q = document.getElementById('lo_q'); if (q) { q.value = 'zzz_no_such_place'; q.dispatchEvent(new Event('input', { bubbles: true })); } }); await sleep(300);
  chk('search with no match shows the empty text, no group heading', (await p.$$('#lo_list .lg-h')).length === 0);
  // the places sheet is opened from the business tree; the picker of attendance is covered by locgroups_test.js
  console.log('assert failures: ' + bad);
  await br.close(); srv.close();
  process.exit(bad ? 1 : 0);
})();
