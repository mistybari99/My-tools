// What's new page (web/whatsnew.js, #/whatsnew) in Chromium at 360px: renders, no horizontal overflow, 44px Open buttons,
// every Open target exists in web/ia.js, English mode has no Bangla letters, seen marks + New dot, and works with localStorage blocked.
// Run: node tests/web/whatsnew_test.js [abs tests/web dir]
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const PORT = _P.freePort();
const BN = /[ঀ-৿]/;
let ok = 0, bad = 0; const chk = (n, c) => { if (c) ok++; else { bad++; console.log('FAIL ' + n); } };
const src = fs.readFileSync(path.join(ROOT, 'whatsnew.js'), 'utf8');
const ia = fs.readFileSync(path.join(ROOT, 'ia.js'), 'utf8');
const idx = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const routes = [...src.matchAll(/route: '([^']+)'/g)].map((m) => m[1]);
const iaRoutes = new Set([...ia.matchAll(/^\s*rec\('([^']+)'/gm)].map((m) => m[1]));
chk('whatsnew.js lists ' + routes.length + ' features', routes.length >= 10);
const missing = routes.filter((r) => !iaRoutes.has(r));
chk('every Open target exists in ia.js' + (missing.length ? ': ' + missing : ''), missing.length === 0);
chk('ia.js has one whatsnew rec', [...ia.matchAll(/rec\('whatsnew'/g)].length === 1);
chk('index.html loads whatsnew.js once, after ia.js', idx.split('src="whatsnew.js"').length === 2 && idx.indexOf('ia.js') < idx.indexOf('whatsnew.js'));
const actNames = [...src.matchAll(/data-act="([^"]+)"/g)].map((m) => m[1]);
chk('all data-act names carry the wn_ prefix', actNames.length > 0 && actNames.every((a) => a.indexOf('wn_') === 0));
const hn = [...src.matchAll(/Object\.assign\(H, \{\s*([a-z_]+):/g)].map((m) => m[1]);
chk('handlers use the wn_ prefix', hn.length > 0 && hn.every((h) => h.indexOf('wn_') === 0));
const smoke = fs.readFileSync(path.join(SP, 'smoke.js'), 'utf8');
const mkData = () => new Function('fs', smoke.slice(smoke.indexOf('const csv'), smoke.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const stub = fs.readFileSync(path.join(SP, 'stub.js'), 'utf8');
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = [];
  async function open(lang, opts = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 760 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: stub }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const blockStorage = opts.blockStorage ? `try{Object.defineProperty(window,'localStorage',{get(){throw new Error('blocked')}});}catch(e){}` : '';
    await p.addInitScript(`window.__DATA=${JSON.stringify(mkData())};${blockStorage}try{localStorage.setItem('bos_lang','${lang}');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/#/whatsnew'); await p.waitForTimeout(1300);
    return { p, ctx };
  }
  const info = (p) => p.evaluate(() => ({
    html: document.querySelector('#app') ? document.querySelector('#app').innerText : '',
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    opens: [...document.querySelectorAll('[data-act="wn_open"]')].map((b) => ({ k: b.dataset.k, h: b.getBoundingClientRect().height })),
    dots: document.querySelectorAll('.wn_dot').length,
    seen: document.querySelectorAll('[data-wn] .chip').length,
  }));

  // 1. English, phone width
  let s = await open('en');
  let i = await info(s.p);
  chk('page renders the title and intro', /What's new/.test(i.html) && /Tap Open/.test(i.html));
  chk('360px: no horizontal overflow (' + i.overflow + 'px)', i.overflow <= 0);
  chk('one Open button per feature (' + i.opens.length + ')', i.opens.length === routes.length);
  chk('every Open button is at least 44px high', i.opens.every((o) => o.h >= 44));
  chk('English mode has no Bangla letters', !BN.test(i.html));
  chk('every feature starts as New (' + i.dots + ' dots)', i.dots === routes.length && i.seen === 0);
  const pick = await s.p.$('[data-act="wn_open"][data-k="invoice"]');
  await pick.click(); await s.p.waitForTimeout(800);
  const hash = await s.p.evaluate(() => location.hash);
  chk('Open goes to the feature route (' + hash + ')', hash === '#/invoiceview');
  const seenNow = await s.p.evaluate(() => { try { return localStorage.getItem('bos_whatsnew_seen'); } catch (e) { return 'x'; } });
  chk('tapping Open marks the feature seen in localStorage', /invoice/.test(seenNow || ''));
  await s.p.goto('http://localhost:' + PORT + '/#/whatsnew'); await s.p.waitForTimeout(1200);
  i = await info(s.p);
  chk('after return: one seen mark and one fewer New dot', i.seen === 1 && i.dots === routes.length - 1);
  await s.ctx.close();

  // 2. Bangla and mix modes
  s = await open('bn'); i = await info(s.p);
  chk('Bangla mode renders Bangla and keeps the Bangla-letter invoice word', BN.test(i.html) && /ইনভয়েস/.test(i.html));
  await s.ctx.close();
  s = await open('mix'); i = await info(s.p);
  chk('mix mode uses Latin letters for English words', /Sale-এর পরে Invoice/.test(i.html) && /What's new/.test(i.html));
  await s.ctx.close();

  // 3. localStorage blocked: page still renders, Open still navigates
  s = await open('en', { blockStorage: true }); i = await info(s.p);
  chk('blocked storage: page renders all features', i.opens.length === routes.length && /নতুন কী আছে/.test(i.html));
  chk('blocked storage: no 360px overflow (' + i.overflow + 'px)', i.overflow <= 0);
  await (await s.p.$('[data-act="wn_open"][data-k="scan"]')).click(); await s.p.waitForTimeout(800);
  chk('blocked storage: Open still navigates to #/scan', (await s.p.evaluate(() => location.hash)) === '#/scan');
  await s.ctx.close();

  chk('no page errors' + (errors.length ? ': ' + errors[0] : ''), errors.length === 0);
  console.log(ok + ' passed, ' + bad + ' failed');
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
})().catch((e) => { console.log('FAIL ' + e.message); process.exit(1); });
