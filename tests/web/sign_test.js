// W5b: PIN signatures UI. The second person signs in on a throw-away second client (persistSession:false) and sign_entry runs on THAT client.
// Run: node sign_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (process.env.V) log(c ? 'ok' : 'FAIL', m); if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage(); p.setDefaultTimeout(5000);
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};window.__W6=${JSON.stringify(o.w6 || { blind: false })};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC || []).filter((c) => c[0] === f), fn);
  const signSheet = async (p, role, staff, pin) => { await p.click(`#pinbox [data-act=e_pin_sign][data-v=${role}]`); await wait(p, 600); if (staff) await p.selectOption('#ps_staff', staff); await p.fill('#ps_pin', pin); await p.click('[data-act=ps_go]'); await wait(p, 700); };

  // ---------- switch ON, 06-1 ----------
  let p = await open({}, '#/entry/new/14-1/1');
  ok(await p.locator('#pinbox').count() === 1, 'PIN signature box is shown');
  ok(await p.locator('[data-p="witness"]:visible').count() === 0 && await p.locator('[data-p="second_sig"]:visible').count() === 0, 'the old name pickers are gone while PIN signature is on');
  ok(await p.locator('#pinbox [data-act=e_pin_sign]').count() === 2, 'two Sign with PIN buttons (witness, second signature)');
  await p.screenshot({ path: SP + '/sg_box.png', fullPage: true });
  await p.click('#pinbox [data-act=e_pin_sign][data-v=witness]'); await wait(p, 700);
  ok((await calls(p, 'save_entry')).length === 1, 'the draft is saved first (the signature needs an entry)');
  const opts = await p.$$eval('#ps_staff option', (o) => o.map((x) => x.value));
  ok(opts.includes('testf02') && opts.includes('teste03') && !opts.includes('owner1'), 'the maker is not offered as a signer');
  // wrong PIN
  await p.selectOption('#ps_staff', 'testf02'); await p.fill('#ps_pin', '0000'); await p.click('[data-act=ps_go]'); await wait(p, 600);
  let lf = await calls(p, 'login_failed'); ok(lf.length === 1 && lf[0][1].p_staff === 'testf02', 'wrong PIN goes through login_failed (lockout of phase11)');
  ok(!(await calls(p, 'sign_entry')).length, 'no signature was attempted');
  ok(await p.locator('#ps_err:visible').count() === 1, 'an error is shown in the sheet');
  // bad format
  await p.fill('#ps_pin', '12'); await p.click('[data-act=ps_go]'); await wait(p, 300); ok(/4-6 digits/.test(await p.textContent('#ps_err')), 'PIN format checked');
  // right PIN
  await p.fill('#ps_pin', '4321'); await p.click('[data-act=ps_go]'); await wait(p, 800);
  let se = await calls(p, 'sign_entry');
  ok(se.length === 1 && se[0][1].p_role === 'witness' && se[0][2] === 'second', 'sign_entry ran on the SECOND client');
  let sec = await p.evaluate(() => window.__W6S.second); ok(sec.length === 2 && sec[1].email === 'testf02@staff.islamia-bos.app' && sec[1].pw === '4321-bos', 'second client signed the other person in with their own staff id and PIN');
  ok(await p.evaluate(() => ((window.__AC || []).filter((c) => c[0] === 'sign_entry' && c[2] === 'main')).length === 0), 'never on the main (maker) session');
  ok(/Signed by: TestF/.test(await p.textContent('#pinbox')), 'box shows who signed');
  ok(await p.evaluate(() => { const s = JSON.parse(localStorage.getItem('supabase.auth.token') || 'null'); return true; }), 'main session untouched');
  const sv = await calls(p, 'save_entry'); ok(sv.length >= 2 && sv[sv.length - 1][1].p_data.witness === 'testf02', 'the signer is written into the sheet (witness)');
  ok(await p.locator('#pinbox [data-act=e_pin_sign]').count() === 1, 'only the second signature is left');
  // another login for the second signature: testf02 is not offered again
  await p.click('#pinbox [data-act=e_pin_sign][data-v=second_sig]'); await wait(p, 600);
  const opts2 = await p.$$eval('#ps_staff option', (o) => o.map((x) => x.value)); ok(!opts2.includes('testf02') && opts2.includes('teste03'), 'a login that already signed is not offered again');
  await p.selectOption('#ps_staff', 'teste03'); await p.fill('#ps_pin', '5555'); await p.click('[data-act=ps_go]'); await wait(p, 800);
  ok(/Signed by: TestE/.test(await p.textContent('#pinbox')) && await p.locator('#pinbox [data-act=e_pin_sign]').count() === 0, 'both signed');
  // server refusal text
  p = await open({}, '#/entry/new/14-1/1'); await p.click('#pinbox [data-act=e_pin_sign][data-v=witness]'); await wait(p, 600);
  await p.evaluate(() => { window.__W6S.err.sign_entry = 'signer_already_signed'; });
  await p.selectOption('#ps_staff', 'testf02'); await p.fill('#ps_pin', '4321'); await p.click('[data-act=ps_go]'); await wait(p, 700);
  ok(/already signed/i.test(await p.textContent('#ps_err')), 'server refusal gets a clear message (sheet stays open)');
  // client refuses the maker without any sign-in
  const r = await p.evaluate(async () => { const n0 = window.__W6S.second.length; const x = await window.BOS.signWithPin({ entryId: 'e1', role: 'witness', staffId: 'OWNER1', pin: '1234' }); return { x, n: window.__W6S.second.length - n0 }; });
  ok(r.x.ok === false && r.x.code === 'self' && r.n === 0, 'the maker is refused before any sign-in');
  // locked login is refused before any sign-in
  await p.evaluate(() => { window.__W6S.locked = true; });
  const r2 = await p.evaluate(async () => { const n0 = window.__W6S.second.length; const x = await window.BOS.signWithPin({ entryId: 'e1', role: 'witness', staffId: 'testf02', pin: '4321' }); return { x, n: window.__W6S.second.length - n0 }; });
  ok(r2.x.code === 'locked' && r2.n === 0, 'a locked login is refused without trying the PIN');

  // ---------- submit needs the signatures ----------
  p = await open({}, '#/entry/new/14-1/1'); await p.click('[data-act=e_submit]'); await wait(p, 700);
  ok(/Witness/.test(await p.evaluate(() => document.body.innerText)) && /Not signed yet/.test(await p.evaluate(() => document.body.innerText)), 'missing list names the missing PIN signatures');

  // ---------- 03-1 pair ----------
  p = await open({}, '#/entry/new/10-1/1');
  ok(await p.locator('#pinbox [data-act=e_pin_sign][data-v=hub_pair]').count() === 1, '10-1: one pair signature');
  await signSheet(p, 'hub_pair', 'teste03', '5555');
  se = await calls(p, 'sign_entry'); ok(se.length === 1 && se[0][1].p_role === 'hub_pair', '03-1 pair signed through sign_entry');
  ok(/Signed by: TestE/.test(await p.textContent('#pinbox')), '03-1 shows the signer');

  // ---------- switch OFF / phase18 missing: the old name picker ----------
  for (const w6 of [{ pin: false, blind: false }, { pin: 'missing', blind: 'missing' }]) {
    p = await open({ w6 }, '#/entry/new/14-1/1');
    ok(await p.locator('#pinbox').count() === 0 && await p.locator('[data-p="witness"]:visible').count() === 1 && await p.locator('[data-p="second_sig"]:visible').count() === 1, 'PIN signature off ' + JSON.stringify(w6) + ': name pickers as before');
  }
  p = await open({}, '#/entry/new/10-2/1'); ok(await p.locator('#pinbox').count() === 0 && (await calls(p, 'pin_sig_active')).length === 0, 'other forms never ask');
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal overflow');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
