const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); window.__UP = [];
 c.storage = { from: () => ({ upload: async (p, b) => { window.__UP.push([p, b.size, b.type]); return { error: null }; },
   createSignedUrls: async (ps) => ({ data: ps.map((p) => ({ path: p, signedUrl: 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==' })), error: null }),
   createSignedUrl: async () => ({ data: { signedUrl: 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==' }, error: null }) }) }; return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const ctx = await br.newContext({ viewport: { width: 390, height: 800 } }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn')}catch(e){}`);
  await p.goto('http://localhost:' + PORT + '/#/entry/new/10-2/1'); await p.waitForTimeout(700);
  // 1x1 PNG
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
  await p.setInputFiles('input[data-photo]', { name: 'a.png', mimeType: 'image/png', buffer: png }); await p.waitForTimeout(700);
  console.log('uploads:', await p.evaluate(() => window.__UP), '| thumbs:', await p.locator('.photos img').count());
  await p.setInputFiles('input[data-photo]', { name: 'b.png', mimeType: 'image/png', buffer: png }); await p.waitForTimeout(500);
  console.log('thumbs after 2nd:', await p.locator('.photos img').count());
  await p.click('.photos .mini >> nth=0'); await p.waitForTimeout(200); console.log('thumbs after delete:', await p.locator('.photos img').count());
  await p.click('.photos img >> nth=0'); await p.waitForTimeout(300); console.log('viewer sheet img:', await p.locator('.sheet img').count());
  console.log('errors:', errors.length ? errors : 'none'); await br.close(); srv.close();
})();
