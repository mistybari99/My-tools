const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = process.env.WEBROOT || path.join(__dirname, '..', '..', 'web'), TAG = process.env.SHOT || 'after';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
data.tables.option_lists = [
 { list_code: 'marketing_heads', value_code: '1', label_bn: 'অনলাইন বিজ্ঞাপন', label_en: 'Online ads', sort: 1, active: true, extra: { limit_month: 5000 } },
 { list_code: 'marketing_heads', value_code: '2', label_bn: 'ছাপা', label_en: 'Printing', sort: 2, active: true, extra: {} },
 { list_code: 'expense_heads', value_code: 'transport', label_bn: 'যাতায়াত', label_en: 'Transport', sort: 1, active: true, extra: {} },
 { list_code: 'expense_heads', value_code: 'fuel', label_bn: 'জ্বালানি', label_en: 'Fuel', sort: 2, active: true, extra: {} }];
data.tables.location_settings = [];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8093);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const ctx = await br.newContext({ viewport: { width: 360, height: 740 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{if(!sessionStorage.getItem('nf_seed')){localStorage.setItem('bos_lang','en');sessionStorage.setItem('nf_seed','1')}}catch(e){}`);
  const sleep = (n) => p.waitForTimeout(n);
  let ok = 0, bad = 0; const chk = (n, c) => { if (c) ok++; else bad++; console.log((c ? 'PASS ' : 'FAIL ') + n); };
  const shot = (n) => p.screenshot({ path: path.join(__dirname, 'navfold_' + n + '_' + TAG + '.png') });
  const bodyH = () => p.evaluate(() => document.querySelector('#nav_body').getBoundingClientRect().height);
  const openDr = async () => { await p.click('header.top [data-act=nav_open]'); await sleep(500); };
  await p.goto('http://localhost:8093/#/home'); await sleep(1200);
  await openDr();
  const hasTog = await p.locator('.dr-ftog').count();
  await shot('collapsed');
  const h0 = await bodyH();
  if (TAG === 'before') { console.log('before body height', h0); await shot('open'); await br.close(); srv.close(); return; }
  chk('toggle exists', hasTog === 1);
  chk('default collapsed', (await p.getAttribute('.dr-ftog', 'aria-expanded')) === 'false' && !(await p.locator('#nav_foot.open').count()));
  chk('collapsed hides logout', (await p.evaluate(() => document.querySelector('.dr-fx').getBoundingClientRect().height)) < 1 && (await p.getAttribute('.dr-fxi', 'inert')) !== null);
  chk('online dot visible collapsed', await p.locator('#nav_net2').isVisible());
  const tb = await p.locator('.dr-ftog').boundingBox(); chk('tap target >=40', tb.height >= 40 && tb.width >= 40);
  const lbl = await p.getAttribute('.dr-ftog', 'aria-label'); chk('aria-label English', /Show or hide/.test(lbl));
  console.log('collapsed body height', h0);
  await p.click('.dr-ftog'); await sleep(500); await shot('expanded');
  const h1 = await bodyH();
  chk('expanded: aria true + logout visible', (await p.getAttribute('.dr-ftog', 'aria-expanded')) === 'true' && await p.locator('.dr-foot .lo').isVisible());
  chk('collapsed list taller than expanded', h0 > h1 + 100); console.log('expanded body height', h1);
  chk('overflow-x none', await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.querySelector('#navDrawer').scrollWidth <= document.querySelector('#navDrawer').clientWidth));
  chk('state stored', await p.evaluate(() => localStorage.getItem('bos_navfoot')) === '1');
  // lang + theme still work
  await p.click('#navDrawer .lang button[data-v=bn]'); await sleep(500);
  chk('lang switch to bn', await p.evaluate(() => localStorage.getItem('bos_lang')) === 'bn');
  chk('still expanded after lang re-render', await p.locator('#nav_foot.open').count() === 1);
  chk('bn aria-label', /দেখান/.test(await p.getAttribute('.dr-ftog', 'aria-label')));
  await p.click('#navDrawer .lang button[data-v=en]'); await sleep(400);
  for (const th of ['light', 'classic', 'dark']) { await p.evaluate((v) => { const e = document.querySelector('#nav_theme'); e.value = v; e.dispatchEvent(new Event('change', { bubbles: true })); }, th); await sleep(400); chk('theme ' + th, (await p.evaluate(() => document.documentElement.dataset.theme || document.documentElement.getAttribute('data-theme') || localStorage.getItem('bos_theme'))) !== null && (await p.inputValue('#nav_theme')) === th); if (th === 'light') await shot('light'); }
  // persistence after reload
  await p.reload(); await sleep(1200); await openDr();
  chk('expanded persists after reload', await p.locator('#nav_foot.open').count() === 1);
  await p.click('.dr-ftog'); await sleep(400);
  chk('collapse again', await p.locator('#nav_foot.open').count() === 0 && await p.evaluate(() => localStorage.getItem('bos_navfoot')) === '0');
  await p.reload(); await sleep(1200); await openDr();
  chk('collapsed persists after reload', await p.locator('#nav_foot.open').count() === 0);
  await p.click('.dr-ftog'); await sleep(400);
  await p.click('.dr-foot .lo'); await sleep(1000);
  chk('logout works (drawer gone or login shown)', await p.evaluate(() => !document.querySelector('#navDrawer.on') || !!document.querySelector('[data-act=login],#email,input[type=password]')));
  chk('no page errors', errors.length === 0); if (errors.length) console.log(errors.join('\n'));
  console.log('done', ok, 'pass', bad, 'fail'); await br.close(); srv.close(); process.exit(bad ? 1 : 0);
})();
