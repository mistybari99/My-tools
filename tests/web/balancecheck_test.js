// Balance check web piece (#/balancecheck): red/green banner, equation, journal and stock breaks, cross-checks, 3 languages, guarded test-reset card, 360px width.
// Run: node balancecheck_test.js <abs tests/web dir>      (web/balancecheck.js is injected into index.html here; the lead adds the real <script> tag)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8484, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);   // serves THIS checkout's web/
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__BC = window.__BC || { calls: [], check: null, state: { allowed: false, owner: true, flag: false, last: null }, missing: false, deny: false, resetErr: null };
 c.rpc = async (fn, args) => {
  if (!/^_e_/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.missing) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + fn } };
  if (R.deny && fn === '_e_balance_check') return { data: null, error: { message: 'not allowed', code: 'P0001' } };
  if (fn === '_e_balance_check') return { data: R.check, error: null };
  if (fn === '_e_test_reset_state') return { data: R.state, error: null };
  if (fn === '_e_test_reset') { if (R.resetErr) return { data: null, error: { message: R.resetErr, code: 'P0001' } }; R.state = { allowed: false, owner: true, flag: false, last: 'x' }; return { data: { ok: true }, error: null }; }
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    // the integrator adds this one registry line to web/ia.js (docs/integration/E.md); the test injects the same line
    await p.route('**/ia.js', async (r) => { const res = await r.fetch(); const body = (await res.text()).replace("  rec('restoredrill',", "  rec('balancecheck', 'acc', ['হিসাব মেলানো', 'Balance check', 'Balance check'], { icon: 'check', ok: (c) => c.own || c.GF.accounts_view === true || c.GF.accounts_manage === true, kw: ['balance check', 'books agree', 'trial balance', 'equation', 'হিসাব মেলানো'] }),\n  rec('restoredrill',"); await r.fulfill({ response: res, body }); });
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/balancecheck\.js/.test(h) ? h : h.replace('</body>', '<script src="balancecheck.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__BC=${JSON.stringify(o.bc || undefined) || 'undefined'};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__BC.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  const GREEN = { status: 'green', as_of: '2026-10-16', start: '2026-10-11', reds: [], warnings: [],
    equation: { assets: 8000, liabilities: 0, equity: 10000, earnings: -2000, liabilities_equity_earnings: 8000, difference: 0, ok: true },
    trial_balance: { total_debit: 12000, total_credit: 12000, difference: 0, ok: true },
    journal: { broken: 0, rows: [], truncated: false, ok: true }, stock_identity: { broken: 0, rows: [], truncated: false, ok: true, as_of: 'now' },
    cross_checks: { daybook_vs_journal: { ran: true, kinds_differing: 0, diff: 0, ok: true }, money_accounts: { ran: true, ok: true, red: false, amber: false, money_accounts_total: 100, ledger_total: 100, difference: 0 }, inventory_vs_gl: { ran: true, diff: 0, ok: true }, unposted_sources: { ran: true, pending: 0, errors: 0, ok: true } } };
  const RED = JSON.parse(JSON.stringify(GREEN)); RED.status = 'red'; RED.reds = ['equation', 'trial_balance', 'journal', 'stock_identity'];
  RED.equation.difference = 100; RED.equation.ok = false; RED.trial_balance.difference = 100; RED.trial_balance.ok = false;
  RED.journal = { broken: 1, ok: false, truncated: false, rows: [{ entry_id: 3, date: '2026-10-16', source_type: 'manual', source_id: 'test_unbalanced_1', debit: 7000, credit: 6900, diff: 100, lines: 2 }] };
  RED.stock_identity = { broken: 1, ok: false, truncated: false, rows: [{ item_id: 'aaaaaaaa-0000', location_id: 1, opening: 100, in: 0, out: 30, expected_closing: 70, stock_balance: 75, diff: 5 }] };
  RED.warnings = ['daybook_vs_journal']; RED.cross_checks.daybook_vs_journal = { ran: true, kinds_differing: 1, diff: -500, ok: false };

  // green
  let p = await open('#/balancecheck', { bc: { calls: [], check: GREEN, state: { allowed: false, owner: true, flag: false, last: null }, missing: false } });
  let t = await text(p);
  ok(/Balance check/.test(await p.locator('h1').textContent()), 'title (English)');
  ok(await p.locator('#bc_banner[data-status=green]').count() === 1 && /All good/.test(t), 'green banner');
  ok(/Assets/.test(t) && /8,000/.test(t) && /10,000/.test(t), 'equation figures shown');
  ok(await p.locator('.bc-xc[data-k=money_accounts]').count() === 1 && /Money accounts total = mapped ledger accounts/.test(t), 'phase87: the money accounts item is on the page');
  ok(await p.locator('#bc_reset').count() === 0, 'no reset card while the server flag is OFF');
  ok((await calls(p, '_e_balance_check')).length === 1 && (await calls(p, '_e_balance_check'))[0].p_loc === null, 'one read-only call, all places');
  ok((await calls(p, '_e_test_reset')).length === 0, 'the reset is never called on load');
  await noOverflow(p, 'green'); await p.screenshot({ path: SP + '/bc_green.png', fullPage: true });

  // red
  p = await open('#/balancecheck', { bc: { calls: [], check: RED, state: { allowed: false, owner: true, flag: false }, missing: false } });
  t = await text(p);
  ok(await p.locator('#bc_banner[data-status=red]').count() === 1 && /RED - the books do not agree/.test(t), 'red banner');
  ok(await p.locator('.bc-je').count() === 1 && /test_unbalanced_1/.test(t), 'the unbalanced entry is listed');
  ok(await p.locator('.bc-st').count() === 1 && /70/.test(t) && /75/.test(t), 'the stock identity break is listed');
  ok(await p.locator('#bc_warn').count() === 1 && await p.locator('.bc-xc[data-k=daybook_vs_journal] .chip.bad').count() === 1, 'amber cross-check shown');
  await noOverflow(p, 'red'); await p.screenshot({ path: SP + '/bc_red.png', fullPage: true });

  // Bangla and mix
  p = await open('#/balancecheck', { lang: 'bn', bc: { calls: [], check: RED, state: { owner: true, flag: false }, missing: false } });
  ok(/হিসাব মেলানো/.test(await p.locator('h1').textContent()) && /লাল - হিসাব মেলেনি/.test(await text(p)), 'Bangla title and banner');
  await noOverflow(p, 'bn');
  p = await open('#/balancecheck', { lang: 'mix', bc: { calls: [], check: GREEN, state: { owner: true, flag: false }, missing: false } });
  ok(/Balance check/.test(await p.locator('h1').textContent()), 'mix mode renders');

  // accounting start date missing
  p = await open('#/balancecheck', { bc: { calls: [], check: { status: 'data_needed', why: 'accounting_start_date' }, state: null, missing: false } });
  ok(/start date is not set/.test(await text(p)), 'data needed message');

  // function missing / denied
  p = await open('#/balancecheck', { bc: { calls: [], check: null, state: null, missing: true } });
  ok(/phase84\.sql has not been run/.test(await text(p)), 'friendly message when phase84 is not installed');
  p = await open('#/balancecheck', { bc: { calls: [], check: null, state: null, missing: false, deny: true } });
  ok(/do not have permission/.test(await text(p)), 'denied message');

  // reset card: only when owner AND server flag is on; wrong phrase is not sent; right phrase is sent
  p = await open('#/balancecheck', { bc: { calls: [], check: GREEN, state: { allowed: true, owner: true, flag: true }, missing: false } });
  ok(await p.locator('#bc_reset').count() === 1 && /TEST PROJECTS ONLY/.test(await text(p)), 'reset card shown when the flag is ON');
  await p.fill('#bc_phrase', 'delete all test data'); await p.click('[data-act=bc_reset]'); await wait(p, 200);
  ok((await calls(p, '_e_test_reset')).length === 0, 'wrong phrase is not sent');
  await p.fill('#bc_phrase', 'DELETE ALL TEST DATA'); await p.click('[data-act=bc_reset]'); await wait(p, 600);
  const rc = await calls(p, '_e_test_reset');
  ok(rc.length === 1 && rc[0].p_phrase === 'DELETE ALL TEST DATA', 'right phrase sent once');
  ok(await p.locator('#bc_reset').count() === 0, 'card disappears when the flag is OFF again');
  p = await open('#/balancecheck', { bc: { calls: [], check: GREEN, state: { allowed: false, owner: false, flag: true }, missing: false } });
  ok(await p.locator('#bc_reset').count() === 0, 'a non-owner never sees the reset card');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
