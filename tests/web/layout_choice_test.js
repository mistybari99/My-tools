// Screen layout choice (docs/DESKTOP_LAYOUT.md 4.2): Settings row with three buttons, stored per device in localStorage bos_layout.
//   auto (default, key removed) | phone (bos_layout='phone') | PC look (bos_layout='desktop').
// Mocked Supabase stub only (tests/web/stub.js), no live backend, no demo data. Prints PASS / FAIL lines and a RESULT line; exit 1 on any failure.
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = process.env.WEBROOT || _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  let ok = 0, bad = 0; const errors = [];
  const chk = (n, c) => { if (c) ok++; else bad++; console.log((c ? 'PASS ' : 'FAIL ') + n); };
  async function open(w, lang, opts) {
    const ctx = await br.newContext({ viewport: { width: w, height: 900 }, deviceScaleFactor: 1 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const block = opts && opts.blockStorage ? "Object.defineProperty(Storage.prototype,'setItem',{value:function(){throw new Error('blocked')}});Object.defineProperty(Storage.prototype,'removeItem',{value:function(){throw new Error('blocked')}});" : '';
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','${lang || 'en'}')}catch(e){}` + block);
    await p.goto('http://localhost:' + PORT + '/#/settings'); await p.waitForSelector('#lay_row', { timeout: 15000 }).catch(() => {}); await p.waitForTimeout(300);
    return { p, ctx };
  }
  const state = (p) => p.evaluate(() => {
    const row = document.querySelector('#lay_row'), app = document.querySelector('#app');
    const pressed = row ? [...row.querySelectorAll('[data-act="layout_set"]')].filter((b) => b.getAttribute('aria-pressed') === 'true').map((b) => b.dataset.v) : null;
    const dr = document.querySelector('.drawer');
    return { attr: document.documentElement.getAttribute('data-layout'), pressed, sb: document.body.classList.contains('desk-sb'), appW: Math.round(app.getBoundingClientRect().width), appL: Math.round(app.getBoundingClientRect().left), scrollOver: document.documentElement.scrollWidth - innerWidth, drawerVis: dr ? getComputedStyle(dr).visibility : null };
  });
  const store = (p) => p.evaluate(() => { try { return localStorage.getItem('bos_layout'); } catch (e) { return 'ERR'; } });
  const click = async (p, v) => { await p.click(`#lay_row [data-act="layout_set"][data-v="${v}"]`); await p.waitForTimeout(250); };

  // 1. default on a PC: the row exists, automatic is pressed, no stored key, the sidebar shows
  let { p, ctx } = await open(1440, 'en');
  chk('settings screen shows the layout row', await p.evaluate(() => !!document.querySelector('#lay_row')));
  chk('three choices with the owner order (auto, phone, desktop)', await p.evaluate(() => [...document.querySelectorAll('#lay_row [data-act="layout_set"]')].map((b) => b.dataset.v).join(',') === 'auto,phone,desktop'));
  let s = await state(p);
  chk('default: automatic is pressed', JSON.stringify(s.pressed) === '["auto"]');
  chk('default: no bos_layout key stored', (await store(p)) === null);
  chk('default at 1440: sidebar on, #app beside it', s.sb && s.appL >= 288 - 1);
  chk('default: no horizontal overflow', s.scrollOver <= 0);
  chk('row label carries an info (i) hook', await p.evaluate(() => !!document.querySelector('#lay_row [data-info="feature:layout_choice"]')));

  // 2. phone look: stored per device, page follows at once, sidebar off, column back to 640
  await click(p, 'phone');
  s = await state(p);
  chk('phone: localStorage bos_layout = phone', (await store(p)) === 'phone');
  chk('phone: html[data-layout] = phone and phone is pressed', s.attr === 'phone' && JSON.stringify(s.pressed) === '["phone"]');
  chk('phone: sidebar off and #app is the 640 phone column', !s.sb && s.appW <= 640);
  chk('phone: no horizontal overflow', s.scrollOver <= 0);
  await p.reload(); await p.waitForSelector('#lay_row', { timeout: 15000 }).catch(() => {}); await p.waitForTimeout(300);
  s = await state(p);
  chk('phone choice survives a reload (theme_glass.js applies it)', s.attr === 'phone' && JSON.stringify(s.pressed) === '["phone"]');

  // 3. PC look at 1440: stored as desktop; sidebar on
  await click(p, 'desktop');
  s = await state(p);
  chk('PC look: localStorage bos_layout = desktop', (await store(p)) === 'desktop');
  chk('PC look: sidebar on at 1440', s.attr === 'desktop' && s.sb && s.appL >= 288 - 1);
  chk('PC look: desktop is pressed', JSON.stringify(s.pressed) === '["desktop"]');

  // 4. automatic again: key removed, attribute removed
  await click(p, 'auto');
  s = await state(p);
  chk('automatic: key removed', (await store(p)) === null);
  chk('automatic: no data-layout attribute, sidebar back on at 1440', s.attr === null && s.sb);
  await ctx.close();

  // 5. PC look on a phone width: the phone 360 layout stays exactly as before (desktop rules need 1024px)
  ({ p, ctx } = await open(360, 'en'));
  await click(p, 'desktop');
  s = await state(p);
  chk('360 with PC look: still the phone column, no sidebar', s.attr === 'desktop' && !s.sb && s.appW <= 640 && s.scrollOver <= 0);
  await ctx.close();

  // 6. Bangla labels (owner words) and English labels
  ({ p, ctx } = await open(1024, 'bn'));
  const labels = await p.evaluate(() => [...document.querySelectorAll('#lay_row [data-act="layout_set"]')].map((b) => b.textContent.trim()));
  chk('Bangla labels: স্বয়ংক্রিয় / ফোনের চেহারা / পিসির চেহারা', labels.length === 3 && labels[0].includes('স্বয়ংক্রিয়') && labels[1] === 'ফোনের চেহারা' && labels[2] === 'পিসির চেহারা');
  await ctx.close();
  ({ p, ctx } = await open(1024, 'en'));
  const en = await p.evaluate(() => [...document.querySelectorAll('#lay_row [data-act="layout_set"]')].map((b) => b.textContent.trim()));
  chk('English labels: Automatic / Phone look / PC look', en.join('|') === 'Automatic|Phone look|PC look');
  await ctx.close();

  // 7. storage blocked: the buttons do not throw and the choice still applies for this visit
  ({ p, ctx } = await open(1440, 'en', { blockStorage: true }));
  await click(p, 'phone');
  s = await state(p);
  chk('storage blocked: no page error, phone applied for this visit', s.attr === 'phone' && !s.sb && errors.length === 0);
  await ctx.close();

  // 8. info (i) entry exists and is a real key in web/data/info.json
  const info = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'info.json'), 'utf8'));
  chk('info.json has feature:layout_choice with title and default', !!(info.entries['feature:layout_choice'] && info.entries['feature:layout_choice'].title && info.entries['feature:layout_choice'].default));
  chk('no page errors', errors.length === 0); if (errors.length) console.log(errors.slice(0, 5));
  console.log('RESULT ' + ok + ' passed, ' + bad + ' failed');
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
})();
