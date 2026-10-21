// W5b: server-side blind count UI (06-1 drawer, 03-1 hub). The mock server returns the expected figure only from count_save / count_peek.
// Run: node blind_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};window.__W6=${JSON.stringify(o.w6 || {})};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const hiddenCalc = (p, k) => p.evaluate((key) => { const el = document.querySelector(`[data-calc="${key}"]`); return !el || !!el.closest('[hidden]') || !el.offsetParent; }, k);
  const fill14 = async (p, notes) => { await p.fill('[data-p="open_counted"]', '2000'); await p.fill('[data-p="total_entered"]', '10000'); await p.fill('[data-p="d_bkash"]', '3000'); await p.fill('[data-p="dues"]', '500'); await p.fill('[data-p="credit_sales"]', '200');
    await p.fill('[data-p="cash_count.n1000"]', String(notes[0])); await p.fill('[data-p="cash_count.n100"]', String(notes[1])); await wait(p, 100); };
  const open14 = async (p) => { await p.evaluate(() => { document.querySelectorAll('details').forEach((d) => { d.open = true; }); }); };

  // ---------- A: blind ON, 06-1 ----------
  let p = await open({}, '#/entry/new/14-1/1');
  await fill14(p, [9, 3]);
  ok(await p.locator('#blindbox').count() === 1 && await p.locator('#blind_save').count() === 1, 'blind box with Save count');
  ok(await p.locator('#blind_peek').count() === 1, 'owner may peek (logged)');
  ok(await hiddenCalc(p, 'expected') && await hiddenCalc(p, 'short_over'), 'expected + short/over hidden before the count is saved');
  let body = await p.evaluate(() => document.body.innerText);
  ok(!/Expected drawer balance|Short \/ over \(/.test(body), 'no expected / short-over line on the page before the save');
  ok(!(await p.evaluate(() => JSON.stringify(window.__DATA.tables.entries || []))).includes('expected'), 'nothing named expected in the stored entries');
  await p.screenshot({ path: SP + '/bl_before.png', fullPage: true });
  await p.click('#blind_save'); await wait(p, 500);
  let c = await calls(p, 'count_save');
  ok((await calls(p, 'save_entry')).length >= 1 && c.length === 1 && c[0].p_section === 'drawer' && c[0].p_counted.n1000 === '9' && c[0].p_counted.n100 === '3', 'draft saved first, then count_save with the typed notes');
  ok(!(await p.evaluate(() => JSON.stringify(window.__DATA.tables.entries))).includes('expected'), 'the saved entry never contained the expected figure');
  ok(/Count saved/.test(await p.textContent('#blindbox')) && /Expected: ৳ 9,300/.test(await p.textContent('#blindbox')), 'after the save: expected shown from the server');
  ok(/Short \/ over: 0 \(matches\)/.test(await p.textContent('#blind_diff')), 'zero diff is shown, not blank: "Short / over: 0 (matches)"');
  ok(!(await hiddenCalc(p, 'expected')) && !(await hiddenCalc(p, 'short_over')), 'the CALC fields appear after the save');
  ok(await p.locator('[data-p="cash_count.n1000"][disabled]').count() === 1, 'the saved count is read-only');
  ok(await p.locator('#blind_save').count() === 0 && await p.locator('#blind_peek').count() === 0, 'no save/peek buttons any more');
  await p.screenshot({ path: SP + '/bl_after.png', fullPage: true });
  // already saved -> server refusal shows a friendly text
  await p.evaluate(() => { window.__W6S.err.count_save = 'count_already_saved'; });
  // short drawer on a second sheet
  p = await open({}, '#/entry/new/14-1/1'); await fill14(p, [8, 3]); await p.click('#blind_save'); await wait(p, 500);
  ok(/Short \/ over: ৳ -1,000/.test(await p.textContent('#blind_diff')) || /-1,000/.test(await p.textContent('#blind_diff')), 'short by 1,000 shown after the save');
  ok((await p.locator('#flagsbox').textContent()).length > 0, 'the usual flags work after the reveal');
  // nothing typed -> asks for the count
  p = await open({}, '#/entry/new/14-1/1'); await p.click('#blind_save'); await wait(p, 200);
  ok((await calls(p, 'count_save')).length === 0, 'an empty count is not saved');
  // server refuses a second different count
  p = await open({ w6: {} }, '#/entry/new/14-1/1'); await fill14(p, [9, 3]); await p.evaluate(() => { window.__W6S.err.count_save = 'count_already_saved'; }); await p.click('#blind_save'); await wait(p, 400);
  ok(/already saved/i.test(await p.evaluate(() => document.body.innerText)), 'count_already_saved gets a clear message'); ok(await p.locator('#blind_save').count() === 1, 'and the page stays blind');

  // ---------- A2: server hides expected / diff from the maker of a draft ----------
  p = await open({ w6: { hide: true } }, '#/entry/new/14-1/1'); await fill14(p, [9, 3]); await p.click('#blind_save'); await wait(p, 500);
  ok(/Count saved/.test(await p.textContent('#blindbox')) && await p.locator('#blind_later').count() === 1, 'maker: count saved, expected / diff come after submit');
  ok(!/Expected: |Short \/ over/.test(await p.textContent('#blindbox')) && await hiddenCalc(p, 'expected') && await hiddenCalc(p, 'short_over'), 'maker never sees expected or short/over after the save');
  ok(await p.locator('[data-p="cash_count.n1000"][disabled]').count() === 1, 'count read-only after the save');

  // ---------- B: peek (logged) ----------
  p = await open({}, '#/entry/new/14-1/1'); await fill14(p, [9, 3]); await p.click('#blind_peek'); await wait(p, 500);
  ok((await calls(p, 'count_peek')).length === 1 && /Expected: ৳ 9,300/.test(await p.textContent('#blindbox')), 'peek returns the expected figure');
  ok(/seen before the count/i.test(await p.textContent('#blindbox')), 'the screen says it was seen early');
  await p.click('#blind_save'); await wait(p, 500);
  ok(/seen before the count/i.test(await p.textContent('#blindbox')), 'seen-early note stays on the saved result');
  // peek refused by the server
  p = await open({ w6: { noPeek: true } }, '#/entry/new/14-1/1'); await fill14(p, [9, 3]); await p.click('#blind_peek'); await wait(p, 400);
  ok(await hiddenCalc(p, 'expected'), 'peek refused: still blind');

  // ---------- C: switch OFF / phase18 missing: the old screen ----------
  for (const w6 of [{ blind: false }, { blind: 'missing', pin: 'missing' }]) {
    p = await open({ w6 }, '#/entry/new/14-1/1'); await fill14(p, [9, 3]);
    ok(await p.locator('#blindbox').count() === 0 && !(await hiddenCalc(p, 'expected')), 'blind off (' + JSON.stringify(w6) + '): expected shown at once as before');
    ok(/Expected drawer balance/.test(await p.evaluate(() => document.body.innerText)), 'old screen shows the expected line');
  }

  // ---------- D: hub 03-1 ----------
  const hub = { id: 'h1', form_code: '03-1', location_id: 1, serial: 7, entry_date: '2026-10-12', status: 'submitted', data: { count: { n1000: '5' }, leave_float: '1000', carrier: 'Rafiq' }, check_data: {}, flags: [], created_by: 'u9', created_staff: 'maker9', rev_no: 1 };
  p = await open({ entries: [hub] }, '#/entry/h1');
  ok(await p.locator('#blind_hidden').count() === 1, 'the hub person does not see the sender\'s count while blind');
  ok(!/4,000|5,000/.test(await p.evaluate(() => document.body.innerText)), 'neither handover (4,000) nor the sender total (5,000) on the page');
  ok(await p.locator('#blind_save').count() === 1, 'save count button');
  await p.fill('[data-p="rcount.n1000"]', '4'); await p.click('#blind_save'); await wait(p, 500);
  c = await calls(p, 'count_save'); ok(c.length === 1 && c[0].p_section === 'hub' && c[0].p_counted.n1000 === '4', 'hub count_save sent');
  ok(/Short \/ over: 0 \(matches\)/.test(await p.textContent('#blind_diff')), 'hub: zero diff shown');
  ok(await p.locator('#blind_hidden').count() === 0 && /4,000/.test(await p.evaluate(() => document.body.innerText)), 'after the save the sender\'s section and the handover appear');
  // reload of an entry whose count is saved: shown at once
  p = await open({ entries: [hub], w6: { counts: { 'h1:hub': { counted: 3500, expected: 4000, diff: -500, match: false, seen_before_count: false } } } }, '#/entry/h1');
  ok(await p.locator('#blind_hidden').count() === 0 && /-500|500/.test(await p.textContent('#blindbox')), 'reopen: saved count and the diff are shown, nothing hidden');
  await p.screenshot({ path: SP + '/bl_hub.png', fullPage: true });

  // ---------- E: other forms untouched ----------
  p = await open({}, '#/entry/new/10-2/1'); ok(await p.locator('#blindbox').count() === 0 && (await calls(p, 'blind_active')).length === 0, 'a form that is not 06-1 / 03-1 never asks');
  const ov = await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1); ok(ov, 'no horizontal overflow');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
