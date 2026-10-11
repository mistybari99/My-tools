const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.css') ? 'text/css' : f.endsWith('.json') ? 'application/json' : f.endsWith('.svg') ? 'image/svg+xml' : f.endsWith('.webp') ? 'image/webp' : 'text/html' }); r.end(b); }); }).listen(8078);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a);
  async function open(hash, lang = 'bn') {
    const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, deviceScaleFactor: 2, locale: 'bn-BD' }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push(hash + ': ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(hash + ' console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','${lang}')}catch(e){}`);
    await p.goto('http://localhost:8078/' + hash); await p.waitForTimeout(700); return p;
  }
  const flagTxt = async (p) => (await p.locator('#flagsbox .flag').allTextContents()).map((s) => s.replace(/\s+/g, ' ').trim());
  // ---- 10-2
  let p = await open('#/entry/new/10-2/1');
  await p.fill('[data-p="lines.0.amount"]', '1500'); await p.selectOption('[data-p="lines.0.head"]', 'staff_meal'); await p.click('[data-act=pick][data-p="lines.0.receipt"][data-v=no]');
  await p.fill('[data-p="cash_now"]', '3000'); await p.fill('[data-p="receipts_total"]', '1500');
  log('10-2 total:', await p.textContent('[data-calc=total]'), '| imprest text:', await p.textContent('[data-calc=imprest_text]'));
  log('10-2 flags:', await flagTxt(p));
  await p.screenshot({ path: SP + '/e_10-2.png', fullPage: true });
  await p.click('[data-act=e_submit]'); await p.waitForTimeout(500); log('10-2 submit sheet:', (await p.locator('.sheet').textContent()).replace(/\s+/g, ' ').slice(0, 160));
  await p.screenshot({ path: SP + '/e_10-2_sheet.png' });
  await p.context().close();
  // ---- 10-1
  p = await open('#/entry/new/10-1/1');
  await p.fill('[data-p="count.n500"]', '4'); await p.fill('[data-p="count.n100"]', '12'); await p.fill('[data-p="count.coin"]', '150'); await p.fill('[data-p="leave_float"]', '1500');
  log('10-1 counted:', await p.textContent('[data-calc=counted_total]'), 'handover:', await p.textContent('[data-calc=handover]'), '| flags:', await flagTxt(p));
  await p.context().close();
  // ---- 03-1
  p = await open('#/entry/new/03-1/1');
  await p.fill('[data-p="items.0.sent"]', '20'); await p.fill('[data-p="items.0.demand"]', '15'); await p.fill('[data-p="items.0.prod_date"]', '2026-10-12');
  await p.fill('[data-p="items.0.item"]', 'I-001 · সাদা মিষ্টি – কেজি'); await p.dispatchEvent('[data-p="items.0.item"]', 'change');
  log('03-1 unit:', await p.textContent('[data-calc="rows.items.0.unit"]'), '| tag:', await p.textContent('[data-calc="rows.items.0.tag"]'), '| flags:', await flagTxt(p));
  await p.screenshot({ path: SP + '/e_03-1.png', fullPage: true }); await p.context().close();
  // ---- 04-3 count-first
  p = await open('#/entry/new/04-3/1');
  log('04-3 book visible before count:', await p.locator('[data-p="rows.0.book"]').isVisible());
  await p.fill('[data-p="rows.0.count"]', '9'); log('04-3 book visible after count:', await p.locator('[data-p="rows.0.book"]').isVisible());
  await p.fill('[data-p="rows.0.item"]', 'I-001'); await p.dispatchEvent('[data-p="rows.0.item"]', 'change'); await p.fill('[data-p="rows.0.book"]', '10');
  log('04-3 var:', await p.textContent('[data-calc="rows.rows.0.var"]'), '| flags:', await flagTxt(p)); await p.context().close();
  // ---- 14-1
  p = await open('#/entry/new/14-1/1');
  await p.fill('[data-p="open_counted"]', '1900'); await p.fill('[data-p="cat_sweet"]', '30000'); await p.fill('[data-p="cat_cake"]', '5000'); await p.fill('[data-p="total_entered"]', '35000');
  await p.fill('[data-p="d_bkash"]', '4000'); await p.fill('[data-p="d_nagad"]', '1000'); await p.fill('[data-p="party_cash"]', '2000'); await p.fill('[data-p="goods_based"]', '31000');
  log('14-1 expected visible before count:', await p.locator('[data-calc=expected]').isVisible());
  await p.fill('[data-p="cash_count.n1000"]', '28'); await p.fill('[data-p="cash_count.n500"]', '2');
  log('14-1 cat_sum:', await p.textContent('[data-calc=cat_sum]'), '| cat_match:', await p.textContent('[data-calc=cat_match]'), '| d_total:', await p.textContent('[data-calc=d_total]'), '| retail:', await p.textContent('[data-calc=retail]'));
  log('14-1 counted:', await p.textContent('[data-calc=counted_total]'), '| expected:', await p.textContent('[data-calc=expected]'), '| short/over:', await p.textContent('[data-calc=short_over]'));
  log('14-1 flags:', await flagTxt(p));
  log('14-1 fridge name/temps:', await p.textContent('[data-calc="rows.fridges.0.name"]')); await p.fill('[data-p="fridges.0.temp"]', '12'); log('   temp ok text:', await p.textContent('[data-calc="rows.fridges.0.temp_ok"]'));
  await p.screenshot({ path: SP + '/e_14-1.png', fullPage: true });
  // save draft then reopen
  await p.click('[data-act=e_save]'); await p.waitForTimeout(400); log('14-1 saved, hash:', await p.evaluate(() => location.hash)); 
  await p.context().close();
  // ---- lists/pages
  for (const [h, n] of [['#/form/14-1', 'list'], ['#/locset', 'locset'], ['#/exceptions', 'exceptions'], ['#/releases', 'releases'], ['#/home', 'home']]) { p = await open(h, 'mix'); await p.screenshot({ path: `${SP}/e_${n}.png` }); await p.context().close(); }
  log('JS errors:', errors.length ? errors : 'none'); await br.close(); srv.close();
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
