// Restore drill web piece (#/restoredrill, owner): status + warning, 3-step how-to in bn/mix/en, record form, history, owner-only, 360px width.
// Run: node restoredrill_test.js <abs tests/web dir>      (web/restoredrill.js is injected into index.html here; the lead adds the real <script> tag)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8481, srv = C.serve(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__RD = window.__RD || { calls: [], rows: [], status: { warn_days: 90, drills: 0, last: null, age_days: null, last_pass_age_days: null, never: true, warn: true, last_failed: false }, err: null, missing: false };
 c.rpc = async (fn, args) => {
  if (!/^restore_drill_/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.missing) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + fn } };
  if (fn === 'restore_drill_status') return { data: R.status, error: null };
  if (fn === 'restore_drill_list') return { data: R.rows, error: null };
  if (fn === 'restore_drill_record') {
    if (R.err) return { data: null, error: { message: R.err, code: 'P0001' } };
    R.rows.unshift({ id: R.rows.length + 1, drilled_at: '2026-10-14T06:00:00Z', backup_name: args.p_backup_name, result: args.p_result, tables_ok: args.p_tables_ok, rows_ok: args.p_rows_ok, notes: args.p_notes });
    R.status = { warn_days: 90, drills: R.rows.length, last: { id: 1, at: '2026-10-14T06:00:00Z', result: args.p_result, backup_name: args.p_backup_name }, age_days: 0.1, last_pass_age_days: args.p_result === 'pass' ? 0.1 : null, never: false, warn: args.p_result !== 'pass', last_failed: args.p_result === 'fail' };
    return { data: R.rows.length, error: null };
  }
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/restoredrill\.js/.test(h) ? h : h.replace('</body>', '<script src="restoredrill.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__RD=${JSON.stringify(o.rd || undefined) || 'undefined'};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__RD.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // never drilled: warning + 3 steps + form
  let p = await open('#/restoredrill');
  let t = await text(p);
  ok(/Restore drill/.test(await p.locator('h1').textContent()), 'title (English)');
  ok(/No drill recorded yet - warning/.test(t), 'warns when no drill was ever recorded');
  ok(/1\) Download the newest backup/.test(t) && /2\) On your own computer/.test(t) && /3\) Write the PASS/.test(t), 'three steps shown');
  ok(/UNVERIFIED/.test(t), 'honest about the real Supabase');
  ok(await p.locator('.chip.warn').count() === 1, 'warn chip');
  ok(await p.locator('[data-act=rdr_save]').count() === 1, 'record form present');
  await noOverflow(p, 'never'); await p.screenshot({ path: SP + '/rdr_never.png', fullPage: true });

  // validation: no name, pass without both ticks
  await p.click('[data-act=rdr_save]'); await wait(p, 200);
  ok((await calls(p, 'restore_drill_record')).length === 0, 'empty name is not sent');
  await p.fill('#rdr_name', 'run-2026-10-14'); await p.check('#rdr_tok'); await p.click('[data-act=rdr_save]'); await wait(p, 200);
  ok((await calls(p, 'restore_drill_record')).length === 0, 'pass with one tick is not sent');

  // record a pass
  await p.check('#rdr_rok'); await p.fill('#rdr_notes', 'first drill <b>x</b>'); await p.click('[data-act=rdr_save]'); await wait(p, 600);
  let c = await calls(p, 'restore_drill_record');
  ok(c.length === 1 && c[0].p_backup_name === 'run-2026-10-14' && c[0].p_result === 'pass' && c[0].p_tables_ok === true && c[0].p_rows_ok === true && c[0].p_notes === 'first drill <b>x</b>' && c[0].p_drilled_at === null, 'record RPC args');
  t = await text(p);
  ok(/Up to date/.test(t) && await p.locator('.chip.warn').count() === 0, 'status turns green after a passing drill');
  ok(await p.locator('.rdr-row').count() === 1 && /run-2026-10-14/.test(t), 'history row added');
  ok(await p.locator('.rdr-row b').count() === 0, 'notes are escaped');
  await noOverflow(p, 'after record'); await p.screenshot({ path: SP + '/rdr_pass.png', fullPage: true });

  // record a fail with a date
  await p.fill('#rdr_name', 'run-bad'); await p.selectOption('#rdr_result', 'fail'); await p.fill('#rdr_when', '2026-10-01'); await p.click('[data-act=rdr_save]'); await wait(p, 600);
  c = await calls(p, 'restore_drill_record');
  ok(c.length === 2 && c[1].p_result === 'fail' && c[1].p_tables_ok === false && /^2026-10-01T/.test(c[1].p_drilled_at), 'fail recorded with a date');
  ok(/latest drill failed/.test(await text(p)), 'failed latest drill is flagged');

  // server error is shown, not thrown
  await p.evaluate(() => { window.__RD.err = 'not allowed'; }); await p.fill('#rdr_name', 'x'); await p.selectOption('#rdr_result', 'fail'); await p.click('[data-act=rdr_save]'); await wait(p, 500);
  ok((await calls(p, 'restore_drill_record')).length === 3, 'error call made');

  // old pass -> stale warning, Bangla
  p = await open('#/restoredrill', { lang: 'bn', rd: { calls: [], rows: [{ id: 1, drilled_at: '2026-06-01T06:00:00Z', backup_name: 'old', result: 'pass', tables_ok: true, rows_ok: true, notes: null }],
    status: { warn_days: 90, drills: 1, last: { id: 1, at: '2026-06-01T06:00:00Z', result: 'pass', backup_name: 'old' }, age_days: 135, last_pass_age_days: 135, never: false, warn: true, last_failed: false }, err: null, missing: false } });
  t = await text(p);
  ok(/রিস্টোর ড্রিল/.test(await p.locator('h1').textContent()) && /সতর্কতা/.test(t) && /১\) সর্বশেষ ব্যাকআপ নামান/.test(t), 'Bangla title, stale warning, step 1');
  ok(/135/.test(t), 'age in days shown');
  await noOverflow(p, 'bn');
  p = await open('#/restoredrill', { lang: 'mix' });
  ok(/Restore drill/.test(await p.locator('h1').textContent()) && /Download|নামান/.test(await text(p)), 'mix mode renders');

  // function missing on the server
  p = await open('#/restoredrill', { rd: { calls: [], rows: [], status: null, err: null, missing: true } });
  ok(/phase70\.sql has not been run/.test(await text(p)), 'friendly message when phase70 is not installed');

  // non-owner: nothing is fetched
  p = await open('#/restoredrill', { owner: false });
  ok(await p.evaluate(() => (window.__RD ? window.__RD.calls.length : 0)) === 0, 'non-owner makes no drill RPC');
  ok(await p.locator('[data-act=rdr_save]').count() === 0, 'non-owner sees no form');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
