// X6 market page (web/market.js, #/market): 360px width, no horizontal scroll, every tab renders, no page errors, Bangla + English labels present.
// Run: X6_PORT=8571 node x6_market_test.js <abs tests/web dir>   (uses the same local stub server as ia_test.js; no external network)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = Number(process.env.X6_PORT || 8571), srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else console.log('PASS:', m); };
  const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 });
  const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  const data = C.mk(base, {}); await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify({})};`);
  await p.goto(`http://localhost:${PORT}/#/market`); await p.waitForTimeout(1500);
  const body = await p.evaluate(() => (document.querySelector('#mi_body') || {}).innerText || '');
  ok(body.length > 0, 'the market page renders a body');
  ok(/Overview/.test(body) && /Opportunities/.test(body), 'the tabs are visible (English)');
  ok(/সারসংক্ষেপ|বাজার/.test(body), 'Bangla labels are shown');
  await p.evaluate(() => { document.documentElement.scrollWidth; });
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal scroll at 360px on the overview');
  for (const key of ['research', 'prices', 'opps', 'growth']) {
    const btn = await p.$(`#mi_body [data-act=mi_tab][data-v=${key}]`);
    if (!btn) { ok(false, 'tab button ' + key + ' exists'); continue; }
    await btn.click(); await p.waitForTimeout(700);
    ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal scroll at 360px on ' + key);
  }
  ok(errors.length === 0, 'no page errors (' + errors.slice(0, 3).join(' | ') + ')');
  await br.close();
  console.log(bad ? `RESULT: ${bad} FAIL` : 'RESULT: all pass');
  process.exitCode = bad ? 1 : 0;
} catch (e) { console.log('ERROR', e.message); process.exitCode = 1; } finally { try { srv.close(); } catch (e) { /* ignore */ } process.exit(process.exitCode || 0); } })();
