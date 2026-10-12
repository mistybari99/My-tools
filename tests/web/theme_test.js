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
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8193);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let fails = 0; const ok = (c, m) => { if (!c) { fails++; console.log('FAIL', m); } else console.log('ok  ', m); };
  const open = async (init, hash, theme) => {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn');${theme ? `if(!localStorage.getItem('bos_theme'))localStorage.setItem('bos_theme','${theme}');` : ''}}catch(e){}${init || ''}`);
    await p.goto('http://localhost:8193/' + hash); await p.waitForTimeout(1400); return p;
  };
  const ovf = (p) => p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  // first run: default Premium Dark (headless prefers light => Premium Light); with dark preference => Premium Dark
  let p = await open('', '#/home'); let th = await p.evaluate(() => document.documentElement.dataset.theme);
  ok(th === 'light' || th === 'dark', 'first run picks dark/light from prefers-color-scheme: ' + th); await p.context().close();
  const ctxD = await br.newContext({ viewport: { width: 360, height: 780 }, colorScheme: 'dark' }); const pd = await ctxD.newPage();
  await pd.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') })); await pd.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await pd.addInitScript(`window.__DATA=${JSON.stringify(data)}`); await pd.goto('http://localhost:8193/#/home'); await pd.waitForTimeout(800);
  ok(await pd.evaluate(() => document.documentElement.dataset.theme) === 'dark' && await pd.evaluate(() => document.documentElement.hasAttribute('data-skin')), 'dark preference => Premium Dark default'); await ctxD.close();
  // switch + persist
  p = await open('', '#/home', 'dark');
  await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(400);
  ok(await p.locator('#navDrawer [data-theme-pick]').count() === 1, 'Theme dropdown in drawer');
  await p.evaluate(() => { const s = document.querySelector('#nav_theme'); s.value = 'light'; s.dispatchEvent(new Event('change', { bubbles: true })); }); await p.waitForTimeout(500);
  ok(await p.evaluate(() => document.documentElement.dataset.theme + '|' + localStorage.getItem('bos_theme')) === 'light|light', 'switch to light applies attribute + persists');
  await p.reload(); await p.waitForTimeout(1200); ok(await p.evaluate(() => document.documentElement.dataset.theme) === 'light', 'light persists after reload');
  await p.evaluate(() => { window.BOS_THEME.set('classic'); }); const cl = await p.evaluate(() => ({ skin: document.documentElement.hasAttribute('data-skin'), fs: getComputedStyle(document.documentElement).fontSize, bg: getComputedStyle(document.body).backgroundColor }));
  ok(!cl.skin && cl.fs === '17px', 'Classic: no skin attribute, old 17px root size, old stylesheet behaviour (' + cl.fs + ')'); await p.context().close();
  // classic leaves old icons / premium has 3D icons
  p = await open('', '#/home', 'classic'); ok(await p.locator('svg.i3').count() === 0, 'Classic: old icons only, no 3D svg: ' + await p.locator('svg.i3').count()); await p.context().close();
  p = await open('', '#/home', 'dark'); ok(await p.locator('#hv_tiles svg.i3, .qm svg.i3').count() > 3, 'Premium: tiles use BOS.icon 3D svgs');
  // icons for every IA record
  const miss = await p.evaluate(() => window.BOS.IA.filter((r) => !/^<svg/.test(window.BOS.icon(r.i3 || r.icon, 22))).map((r) => r.id)); ok(!miss.length, 'BOS.icon svg for every BOS.IA record' + (miss.length ? ': ' + miss : ''));
  const gm = await p.evaluate(() => window.BOS.ia.GID.filter((g) => !/^<svg/.test(window.BOS.icon('g:' + g, 18)))); ok(!gm.length, 'group icons for all 13 categories');
  const acts = ['add', 'edit', 'search', 'filter', 'more', 'check', 'close', 'warning', 'info', 'lock', 'print', 'download', 'camera', 'barcode', 'calendar', 'user', 'location', 'cart', 'pos', 'box', 'factory', 'money', 'chart', 'gear', 'stamp', 'bell', 'star', 'history', 'truck', 'recipe', 'asset', 'supplier'];
  const am = await p.evaluate((a) => a.filter((k) => !/^<svg/.test(window.BOS.icon(k, 18))), acts); ok(!am.length, 'action icons present' + (am.length ? ': ' + am : ''));
  ok(await p.evaluate(() => window.BOS.icon('nope') === '' && !window.BOS.icon.has('nope')), 'unknown key returns empty (nav falls back to old icon)');
  // POS first: owner
  ok(await p.locator('.sellbig').count() === 1 && await p.evaluate(() => document.querySelector('#hv_main').firstElementChild.classList.contains('sellbig')), 'owner: Sell is the first/largest element of Home');
  const centre = (pp) => pp.evaluate(() => { const b = [...document.querySelectorAll('#bnav > button')]; return b.length + '|' + b.findIndex((x) => x.classList.contains('sell')); });
  ok(await centre(p) === '5|2', 'owner: Sell orb is the centre slot: ' + await centre(p));
  ok(await p.evaluate(() => document.querySelector('#hv_qgrid .qt button').dataset.quick) === 'pos', 'owner: POS is first quick action');
  const bh = await p.evaluate(() => document.querySelector('.sellbig').getBoundingClientRect().height); ok(bh >= 48, 'Sell button is a big target: ' + bh);
  await p.context().close();
  p = await open(`window.__OWNER=false;window.__PERMS={POS:{view:true,enter:true,approve:false}};`, '#/home', 'dark');
  ok(await p.locator('.sellbig').count() === 1 && await centre(p) === '5|2' && await p.evaluate(() => document.querySelector('#hv_qgrid .qt button').dataset.quick) === 'pos', 'cashier: Sell first on Home, centre of bar, first quick action'); await p.context().close();
  p = await open(`window.__OWNER=false;window.__PERMS={'04-1':{view:true,enter:true,approve:false}};`, '#/home', 'dark');
  ok(await p.locator('.sellbig').count() === 0 && await p.locator('#bnav .sell').count() === 0, 'role without POS: no Sell button, keeps own top job'); await p.context().close();
  // no horizontal overflow at 360 on 6 screens x 3 themes
  const screens = ['#/home', '#/pos', '#/items', '#/entry/new/10-2/1', '#/form/14-1', '#/reports'];
  for (const t of ['dark', 'light', 'classic']) for (const h of screens) { p = await open('', h, t); const o = await ovf(p); ok(o <= 0, `no horizontal overflow ${t} ${h} (${o})`); await p.context().close(); }
  // drawer open overflow + tap targets
  p = await open('', '#/home', 'dark'); await p.click('header.top [data-act=nav_open]'); await p.waitForTimeout(400); ok(await ovf(p) <= 0, 'no overflow with drawer open');
  const small = await p.evaluate(() => [...document.querySelectorAll('#navDrawer button.rb')].filter((b) => b.offsetHeight && b.offsetHeight < 44).length); ok(small === 0, 'drawer rows >= 44px: ' + small); await p.context().close();
  console.log('errors:', errors.length ? [...new Set(errors)] : 'none'); console.log('assert failures:', fails); await br.close(); srv.close();
})();
