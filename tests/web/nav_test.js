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
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8091);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn')}catch(e){}`);
  const sleep = (n) => p.waitForTimeout(n);
  await p.setViewportSize({ width: 360, height: 760 });
  await p.goto('http://localhost:8091/#/home'); await sleep(1200);
  await p.screenshot({ path: SP + '/n_home.png' });
  console.log('bnav visible home:', await p.locator('#bnav').isVisible(), '| header lang buttons:', await p.locator('header.top .lang').count());
  // mode toggle + period
  await p.click('[data-act=hv_mode][data-v=acc]'); await sleep(300); await p.click('[data-act=hv_period][data-v=month]'); await sleep(600);
  await p.screenshot({ path: SP + '/n_home_acc.png' });
  // pin a tile
  await p.click('#hv_tiles .qt:nth-child(1) .st'); await sleep(300);   // the ⋮ menu of the tile (no star buttons any more)
  await p.click('.ctl-sheet.ctl-menu .ctl-opt:first-child'); await sleep(250);   // first item = Pin to favourites
  console.log('pinned:', await p.evaluate(() => JSON.stringify(Object.keys(localStorage).filter((k) => k.startsWith('bos_p')).map((k) => [k, localStorage[k]]))));
  console.log('fav tiles:', await p.locator('#hv_fav .qt').count());
  // drawer
  await p.click('header.top [data-act=nav_open]'); await sleep(500);
  console.log('drawer open:', await p.locator('#navDrawer.on').count(), '| lang in drawer:', await p.locator('#navDrawer .lang button').count());
  await p.click('.dr-g[data-v=item]'); await sleep(200);
  await p.screenshot({ path: SP + '/n_drawer.png' });
  await p.fill('#nav_q', '10-'); await sleep(200); console.log('search hits:', await p.locator('#nav_body .dr-i').count());
  await p.fill('#nav_q', ''); await sleep(100);
  // hardware back closes drawer first
  const h0 = await p.evaluate(() => location.hash); await p.goBack(); await sleep(400);
  console.log('after back: drawer open', await p.locator('#navDrawer.on').count(), 'hash same', h0 === await p.evaluate(() => location.hash));
  // navigate via drawer
  await p.click('header.top [data-act=nav_open]'); await sleep(400);
  await p.click('.dr-it[data-v=items]'); await sleep(900);
  console.log('hash after drawer nav:', await p.evaluate(() => location.hash), '| drawer', await p.locator('#navDrawer.on').count());
  // language switch from drawer
  await p.click('header.top [data-act=nav_open]'); await sleep(400); await p.click('#navDrawer [data-act=lang][data-v=en]'); await sleep(600);
  console.log('lang en brand:', await p.locator('.dr-head b').textContent(), '| group label:', await p.locator('.dr-g .gl').first().textContent());
  await p.click('#navDrawer [data-act=lang][data-v=mix]'); await sleep(500);
  console.log('mix group labels:', (await p.locator('.dr-g .gl').allTextContents()).join(' / '));
  await p.click('#navScrim', { position: { x: 345, y: 300 } }); await sleep(400);
  console.log('closed by scrim:', await p.locator('#navDrawer.on').count());
  // form page and POS: bnav hidden
  await p.goto('http://localhost:8091/#/entry/new/10-2/1'); await sleep(1000);
  console.log('bnav in entry:', await p.locator('#bnav').isVisible()); await p.screenshot({ path: SP + '/n_form.png' });
  await p.goto('http://localhost:8091/#/pos'); await sleep(1200);
  console.log('bnav in pos:', await p.locator('#bnav').isVisible()); await p.screenshot({ path: SP + '/n_pos.png' });
  await p.goto('http://localhost:8091/#/form/10-1'); await sleep(900);
  console.log('bnav in formlist:', await p.locator('#bnav').isVisible(), '| header dots', await p.locator('#hd_dots').count(), '| stars', await p.locator('.st[aria-pressed]').count());
  // non-owner, hide mode vs lock mode
  await p.addInitScript(`window.__OWNER=false;window.__PERMS={POS:{view:true,enter:true,approve:false}};`);
  await p.evaluate(() => localStorage.setItem('bos_lang', 'bn')); await p.goto('http://localhost:8091/#/home'); await p.reload(); await sleep(1500);
  await p.screenshot({ path: SP + '/n_home_staff.png' });
  await p.click('header.top [data-act=nav_open]'); await sleep(500); await p.screenshot({ path: SP + '/n_drawer_staff.png' });
  console.log('staff locked rows:', await p.locator('.dr-i.lock').count());
  await p.addInitScript(`window.__DATA.tables.rules=[{key:'ui_noperm_mode',value:'hide',sort:1}];`);
  await p.reload(); await sleep(1500);
  await p.click('header.top [data-act=nav_open]'); await sleep(500);
  console.log('HIDE mode: locked rows', await p.locator('.dr-i.lock').count(), '| lockcards', await p.locator('.lockcard').count(), '| groups', await p.locator('.dr-g').count());
  console.log('errors:', errors.length ? [...new Set(errors)] : 'none'); await br.close(); srv.close();
})();
