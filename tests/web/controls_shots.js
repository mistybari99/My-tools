// Fresh screenshots of the collapsed controls, dark + light. Run: node controls_shots.js tests/web
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const data = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.webp': 'image/webp' };
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'text/plain' }); r.end(b); }); }).listen(PORT);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const th of ['dark', 'light']) {
    const open = async (hash) => { const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
      await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
      await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
      await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en');localStorage.setItem('bos_theme','${th}')}catch(e){}`);
      await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1200); return p; };
    const shot = (p, n) => p.screenshot({ path: `${SP}/final_${n}_${th}.png` });
    let p = await open('#/pos'); await shot(p, 'pos');
    await p.locator('#pos_cats .ctl-trg').click().catch(() => {}); await p.waitForTimeout(300); await shot(p, 'sheet_open'); await p.keyboard.press('Escape'); await p.context().close();
    p = await open('#/entry/new/10-2/1'); await shot(p, 'form_10-2'); await p.context().close();
    p = await open('#/entry/new/14-1/1'); await shot(p, 'form_14-1'); await p.context().close();
    p = await open('#/items'); await p.locator('#p2_fb').click().catch((e) => console.log('items fb', e.message.slice(0, 60))); await p.waitForTimeout(400); await shot(p, 'items_filter'); await p.context().close();
    p = await open('#/report/sales_summary'); await p.locator('[data-act=rp_filter]').click({ timeout: 3000 }).catch((e) => console.log('rp_filter n/a')); await p.waitForTimeout(400); await shot(p, 'reports_filter'); await p.context().close();
    p = await open('#/home'); await p.locator('header.top [data-act=nav_open]').click().catch(() => {}); await p.waitForTimeout(500); await shot(p, 'drawer'); await p.context().close();
  }
  await br.close(); srv.close();
})();
