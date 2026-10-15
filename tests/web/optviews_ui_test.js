// Step Vis: real nav.js + ia.js + optviews.js in a browser (stub backend). Hide removes a permitted option everywhere in the drawer / search, Locked keeps it and opens the ask-the-owner sheet,
// no data = nothing changes, the owner screen opens. Run: node tests/web/optviews_ui_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const OV = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const r = c.rpc;
 c.rpc = async (fn, args) => { if (fn === 'my_option_views') { window.__OVC = (window.__OVC || 0) + 1; return window.__OV === 'err' ? { data: null, error: { message: 'Could not find the function' } } : { data: window.__OV || [], error: null }; } return r(fn, args); }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } };
  async function open(ov, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + OV }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OV=${JSON.stringify(ov)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const drawer = async (p) => { await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(500); };
  const rows = (p, v) => p.locator(`#nav_body [data-act=nav_go][data-v="${v}"]`).count();
  // 1. no data: as before
  let p = await open([], '#/home'); await drawer(p);
  ok(await rows(p, 'items') > 0 && await rows(p, 'stock') > 0, 'no views: items and stock are in the drawer');
  ok(await p.evaluate(() => window.__OVC) === 1, 'my_option_views is read once');
  await p.close();
  // 2. server error: as before
  p = await open('err', '#/home'); await drawer(p);
  ok(await rows(p, 'items') > 0, 'views unavailable: drawer unchanged');
  await p.close();
  // 3. hide + locked
  p = await open([{ key: 'r:items', mode: 'hide', src: 'user' }, { key: 'r:stock', mode: 'locked', src: 'user' }], '#/home'); await drawer(p);
  ok(await rows(p, 'items') === 0, 'hidden option (permitted) is not in the drawer');
  ok(await rows(p, 'stock') > 0, 'locked option is still listed');
  ok(/locked/i.test(await p.locator('#nav_body [data-act=nav_go][data-v="stock"]').first().innerText()), 'locked row is tagged');
  await p.click('#nav_body [data-act=nav_grp][data-v=stock]'); await p.waitForTimeout(300);
  await p.locator('#nav_body [data-act=nav_go][data-v="stock"]').first().click(); await p.waitForTimeout(500);
  ok(await p.locator('.sheet').count() > 0 && /ask the owner/i.test(await p.locator('.sheet').first().innerText()), 'tapping a locked row opens the ask-the-owner sheet');
  ok(!/#\/stock/.test(await p.evaluate(() => location.hash)), 'the page did not open');
  await p.locator('.sheet [data-act=closesheet]').last().click({ force: true, timeout: 5000 }); await p.waitForTimeout(300);
  await p.fill('#nav_q', 'item'); await p.waitForTimeout(700);
  ok(await rows(p, 'items') === 0, 'search does not find a hidden option');
  await p.close();
  // 4. owner screen
  p = await open([], '#/optviews');
  ok(await p.locator('#ov_who').count() === 1, 'owner screen has the person picker');
  ok(!/[ঀ-৿]/.test(await p.locator('main, #app, body').first().innerText()), 'English mode: no Bangla letters on the screen');
  await p.close();
  console.log('errors:', errors.length ? errors.join(' | ') : 'none'); console.log('assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.log('CRASH', e && e.stack || e); process.exit(2); } })();
