const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8082);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await br.newContext({ viewport: { width: 390, height: 800 } }); const p = await ctx.newPage(); const errors = [];
  p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn')}catch(e){}`);
  await p.goto('http://localhost:8082/#/home'); await p.waitForTimeout(800);
  const codes = await p.evaluate(() => Object.keys(window.BOS.forms)); console.log('forms live:', codes.length, codes.join(' '));
  const all = data.tables.forms.map((f) => f.code).filter((c) => !['ITEMS', 'ITEM_COST', 'POS', '0-1'].includes(c));
  console.log('not live:', all.filter((c) => !codes.includes(c)));
  for (const lang of ['bn', 'mix', 'en']) {
    await p.evaluate((l) => localStorage.setItem('bos_lang', l), lang);
    for (const c of codes) { await p.goto('http://localhost:8082/#/entry/new/' + c + '/1'); await p.reload(); await p.waitForTimeout(250);
      const n = await p.locator('.fld, .tbl').count(); if (n < 3) console.log('FEW FIELDS', lang, c, n); }
  }
  console.log('errors:', errors.length ? [...new Set(errors)].slice(0, 10) : 'none'); await br.close(); srv.close();
})();
