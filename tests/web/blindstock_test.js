// B2: blind stock count (36-1) and GRN (13-1) UI. The mock answers stock_blind_active / count_lines_state / count_lines_seal.
// Run: node blindstock_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const EXTRA7 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const S = window.__SB = window.__SB || { on: true, sealed: false, err: null };
 c.rpc = async (fn, args) => {
  if (!/^(stock_blind_active|count_lines_state|count_lines_seal)$/.test(fn)) return rpc(fn, args);
  (window.__AC7 = window.__AC7 || []).push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (fn === 'stock_blind_active') return { data: !!S.on, error: null };
  if (fn === 'count_lines_state') return { data: { blind: true, rows: 1, sealed: S.sealed ? 1 : 0, all_sealed: !!S.sealed }, error: null };
  if (S.err) { const m = S.err; S.err = null; return { data: null, error: { message: m, code: 'P0001' } }; }
  S.sealed = true; return { data: { blind: true, sealed: 1 }, error: null };
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(sb, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA7 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__SB=${JSON.stringify(sb)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC7 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const openAll = (p) => p.evaluate(() => { document.querySelectorAll('details').forEach((d) => { d.open = true; }); });

  // 36-1 blind ON
  let p = await open({ on: true, sealed: false }, '#/entry/new/04-3/1'); await openAll(p);
  ok((await calls(p, 'stock_blind_active')).length === 1, '36-1 asks the server');
  ok(await p.locator('[data-p="rows.0.count"]').count() === 1, 'count field present');
  await p.fill('[data-p="rows.0.count"]', '7'); await wait(p, 200);
  ok(!(await p.locator('[data-p="rows.0.book"]').first().isVisible()), 'book field is not on the screen while blind');
  ok(await p.locator('[data-act=e_seal]').count() === 1, 'Lock the counts button');
  ok(/Blind count/.test(await p.evaluate(() => document.body.innerText)), 'hint shown');
  await p.click('[data-act=e_seal]'); await wait(p, 600);
  const sc = await calls(p, 'count_lines_seal'); ok(sc.length === 1, 'count_lines_seal called after the draft is saved');
  ok((await p.evaluate(() => (window.__AC || []).filter((c) => c[0] === 'save_entry').length)) >= 1, 'draft saved first');
  ok(await p.locator('[data-act=e_seal]').count() === 0, 'lock button gone after sealing');
  ok(await p.locator('[data-p="rows.0.count"][disabled]').count() === 1, 'counted figure read-only after sealing');
  ok(!(await p.locator('[data-p="rows.0.book"]').first().isVisible()), 'book still hidden after sealing (the system adds it at submit)');
  await p.screenshot({ path: SP + '/bs_043.png', fullPage: true });

  // 36-1 blind OFF
  p = await open({ on: false }, '#/entry/new/04-3/1'); await openAll(p);
  await p.fill('[data-p="rows.0.count"]', '7'); await wait(p, 200);
  ok(await p.locator('[data-p="rows.0.book"]').first().isVisible() && await p.locator('[data-act=e_seal]').count() === 0, 'switch OFF: old behaviour (book field, no lock button)');

  // 13-1 blind ON: memo hidden until counted are locked
  p = await open({ on: true, sealed: false }, '#/entry/new/04-1/1'); await openAll(p);
  ok(await p.locator('[data-p="lines.0.counted"]').count() === 1 && !(await p.locator('[data-p="lines.0.memo"]').first().isVisible()), '04-1: memo hidden before the lock');
  await p.fill('[data-p="lines.0.counted"]', '10'); await p.click('[data-act=e_seal]'); await wait(p, 600);
  ok(await p.locator('[data-p="lines.0.memo"]').first().isVisible(), '04-1: memo appears after the lock');
  ok(await p.locator('[data-p="lines.0.counted"][disabled]').count() === 1, '04-1: counted read-only after the lock');
  // error text
  p = await open({ on: true, sealed: false, err: 'count_missing' }, '#/entry/new/04-1/1'); await openAll(p);
  await p.fill('[data-p="lines.0.counted"]', '10'); await p.click('[data-act=e_seal]'); await wait(p, 600);
  const bt = await p.evaluate(() => document.body.innerText); ok(/Type the count/.test(bt), 'friendly text for count_missing ' + bt.slice(-200).replace(/\n/g,' '));
  // other forms never ask
  p = await open({ on: true }, '#/entry/new/10-2/1'); ok((await calls(p, 'stock_blind_active')).length === 0, 'other forms do not ask');
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal overflow');
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
