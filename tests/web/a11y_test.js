// bos113 accessibility: web/a11yfix.js (sheets, pickers, drawer, data-act rows, labels, aria-pressed, skip link, <main>), axe-core before/after, pointer behaviour unchanged.
// Run: node a11y_test.js <abs tests/web dir>      axe-core 4.10.2: env AXE_JS=<axe.min.js>, else node_modules/axe-core, else the axe checks are skipped (reported)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
let AXE = null;
for (const f of [process.env.AXE_JS, path.join(_P.REPO_DIR, 'node_modules/axe-core/axe.min.js'), '/tmp/claude-0/-home-user/01f35780-3d2a-5333-96e7-c9a8dcfddfe7/scratchpad/a11y/axe/package/axe.min.js']) if (f && fs.existsSync(f)) { AXE = fs.readFileSync(f, 'utf8'); break; }
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, n = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } else log('PASS:', m); };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: o.w || 360, height: 740 }, deviceScaleFactor: 1, hasTouch: !!o.touch, isMobile: !!o.touch }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message + ' | ' + hash));
    if (o.block) await p.route('**/a11yfix.js', (r) => r.fulfill({ contentType: 'text/javascript', body: '' }));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0={};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');localStorage.setItem('bos_theme','${o.theme || 'light'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/#/` + hash); await p.waitForTimeout(1200); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const act = (p) => p.evaluate(() => { const a = document.activeElement; return a ? (a.tagName + (a.id ? '#' + a.id : '') + (a.className && typeof a.className === 'string' ? '.' + a.className.split(' ')[0] : '')) : 'null'; });
  const inSheet = (p) => p.evaluate(() => !!(document.activeElement && document.activeElement.closest('#sheet')));
  const inDrawer = (p) => p.evaluate(() => !!(document.activeElement && document.activeElement.closest('#navDrawer')));

  // ---------- load order (new test; order_test.js is unchanged) ----------
  const idx = fs.readFileSync(path.join(_P.WEB_DIR, 'index.html'), 'utf8'); const scripts = [...idx.matchAll(/<script[^>]*\ssrc="([^"]+)"/g)].map((m) => m[1]);
  ok(scripts.filter((s) => s === 'a11yfix.js').length === 1, 'a11yfix.js is loaded exactly once');
  ok(scripts.indexOf('kbdfix.js') >= 0 && scripts.indexOf('kbdfix.js') < scripts.indexOf('a11yfix.js') && scripts.indexOf('a11yfix.js') < scripts.indexOf('pos.js'), 'a11yfix.js loads after kbdfix.js and before pos.js');
  ok(fs.existsSync(path.join(_P.WEB_DIR, 'a11yfix.js')), 'a11yfix.js exists');

  // ---------- plain openSheet sheet (customers > New customer) : keyboard user ----------
  let p = await open('customers');
  await p.focus('[data-act=cu_add]'); await p.keyboard.press('Enter'); await wait(p, 400);
  const sh = await p.evaluate(() => { const s = document.querySelector('#sheet .sheet'); return s && { role: s.getAttribute('role'), modal: s.getAttribute('aria-modal'), lb: s.getAttribute('aria-labelledby'), lbText: (document.getElementById(s.getAttribute('aria-labelledby') || 'x') || {}).textContent }; });
  ok(sh && sh.role === 'dialog' && sh.modal === 'true', 'sheet has role=dialog aria-modal=true');
  ok(sh && sh.lb && sh.lbText && sh.lbText.trim().length > 0, 'sheet aria-labelledby points to its heading: ' + (sh && sh.lbText));
  ok(await inSheet(p), 'keyboard open: focus moved into the sheet: ' + await act(p));
  let leaked = 0; for (let i = 0; i < 40; i++) { await p.keyboard.press('Tab'); if (!await inSheet(p)) leaked++; }
  ok(leaked === 0, 'Tab x40 never leaves the sheet (leaked ' + leaked + ')');
  leaked = 0; for (let i = 0; i < 40; i++) { await p.keyboard.press('Shift+Tab'); if (!await inSheet(p)) leaked++; }
  ok(leaked === 0, 'Shift+Tab x40 never leaves the sheet (leaked ' + leaked + ')');
  await p.keyboard.press('Escape'); await wait(p, 250);
  ok(await p.evaluate(() => !document.getElementById('sheet')), 'Esc closes the sheet');
  ok(await p.evaluate(() => document.activeElement && document.activeElement.getAttribute('data-act') === 'cu_add'), 'focus returns to the opener: ' + await act(p));
  await p.close();

  // ---------- pointer user: no focus jump into a field (no on-screen keyboard), same behaviour ----------
  p = await open('customers', { touch: true });
  await p.tap('[data-act=cu_add]'); await wait(p, 400);
  ok(await p.evaluate(() => !!document.getElementById('sheet')), 'pointer: sheet opens');
  { const q = await open('customers', { touch: true, block: true }); await q.tap('[data-act=cu_add]'); await wait(q, 400); const f0 = await act(q); await q.close();
    ok(await act(p) === f0 || await p.evaluate(() => document.activeElement.matches('.sheet')), 'pointer: a11yfix adds no focus jump of its own (with: ' + await act(p) + ', without: ' + f0 + ')'); }
  ok(await p.evaluate(() => { const s = document.querySelector('#sheet .sheet'); return getComputedStyle(s).outlineStyle === 'none' || parseFloat(getComputedStyle(s).outlineWidth) === 0; }), 'pointer: no focus ring on the sheet');
  await p.tap('#sheet [data-act=closesheet]'); await wait(p, 250);
  ok(await p.evaluate(() => !document.getElementById('sheet')), 'pointer: close button still closes');
  await p.tap('[data-act=cu_add]'); await wait(p, 300);
  await p.mouse.click(5, 5); await wait(p, 250);
  ok(await p.evaluate(() => !document.getElementById('sheet')), 'pointer: tap on backdrop still closes');
  await p.close();

  // ---------- picker dialog (controls.js) trap + roving tabindex ----------
  p = await open('customers');
  await p.focus('[data-act=cu_add]'); await p.keyboard.press('Enter'); await wait(p, 400);
  const trg = (await p.$$('#sheet .ctl-trg'))[1]; ok(!!trg, 'sheet has a picker trigger');
  if (trg) {
    await trg.focus(); await p.keyboard.press('Enter'); await wait(p, 300);
    ok(await p.evaluate(() => !!document.querySelector('.ctl-bg .ctl-sheet')), 'picker opens from the keyboard');
    const inCtl = () => p.evaluate(() => !!(document.activeElement && document.activeElement.closest('.ctl-sheet')));
    let lk = 0; for (let i = 0; i < 25; i++) { await p.keyboard.press('Tab'); if (!await inCtl()) lk++; }
    ok(lk === 0, 'picker: Tab x25 stays inside (leaked ' + lk + ')');
    lk = 0; for (let i = 0; i < 25; i++) { await p.keyboard.press('Shift+Tab'); if (!await inCtl()) lk++; }
    ok(lk === 0, 'picker: Shift+Tab x25 stays inside (leaked ' + lk + ')');
    await p.keyboard.press('ArrowDown'); await wait(p, 100);
    ok(await p.evaluate(() => { const o = [...document.querySelectorAll('.ctl-list .ctl-opt')]; return o.filter((x) => x.tabIndex === 0).length === 1 && document.activeElement.tabIndex === 0; }), 'picker: roving tabindex (exactly the focused option is tabbable)');
    await p.keyboard.press('Escape'); await wait(p, 250);
    ok(await p.evaluate(() => !document.querySelector('.ctl-bg')), 'picker: Esc closes (existing behaviour)');
    ok(await p.evaluate(() => !!document.getElementById('sheet')), 'picker Esc does not also close the sheet under it');
    ok(await p.evaluate(() => !!document.activeElement.closest('#sheet')), 'picker: focus returns to the sheet trigger');
  }
  await p.close();

  // ---------- drawer ----------
  p = await open('customers');
  await p.focus('header.top [data-act=nav_open]'); await p.keyboard.press('Enter'); await wait(p, 700);
  ok(await inDrawer(p), 'drawer: focus is inside after open: ' + await act(p));
  ok(await p.evaluate(() => document.querySelector('[data-act=nav_open]').getAttribute('aria-expanded') === 'true'), 'drawer: Menu button aria-expanded=true');
  let dl = 0; for (let i = 0; i < 60; i++) { await p.keyboard.press('Tab'); if (!await inDrawer(p)) dl++; }
  ok(dl === 0, 'drawer: Tab x60 never leaves the drawer (leaked ' + dl + ')');
  dl = 0; for (let i = 0; i < 60; i++) { await p.keyboard.press('Shift+Tab'); if (!await inDrawer(p)) dl++; }
  ok(dl === 0, 'drawer: Shift+Tab x60 never leaves the drawer (leaked ' + dl + ')');
  await p.keyboard.press('Escape'); await wait(p, 700);
  ok(await p.evaluate(() => !document.querySelector('.drawer.on')), 'drawer: Esc closes');
  ok(await p.evaluate(() => document.activeElement && document.activeElement.getAttribute('data-act') === 'nav_open'), 'drawer: focus returns to the Menu button: ' + await act(p));
  ok(await p.evaluate(() => document.querySelector('[data-act=nav_open]').getAttribute('aria-expanded') === 'false'), 'drawer: aria-expanded=false after close');
  await p.close();

  // ---------- data-act rows: keyboard-activatable, no layout change ----------
  for (const [route, sel, label] of [['home', 'div[data-act=openform]', 'home forms list'], ['settings2', 'div.card.item[data-act=go]', 'settings2 menu'], ['staff', 'div.card.item[data-act=staffopen]', 'staff list']]) {
    p = await open(route);
    const info = await p.evaluate((s) => { const l = [...document.querySelectorAll(s)]; return { n: l.length, ok: l.filter((e) => e.getAttribute('role') === 'button' && e.tabIndex === 0).length }; }, sel);
    ok(info.n > 0 && info.ok === info.n, label + ': ' + info.ok + '/' + info.n + ' rows have role=button tabindex=0');
    if (route === 'staff' || route === 'settings2') {
      const hash0 = await p.evaluate(() => location.hash);
      await p.focus(sel); await p.keyboard.press(route === 'staff' ? 'Enter' : 'Space'); await wait(p, 500);
      if (route === 'staff') ok(await p.evaluate(() => !!document.getElementById('sheet')), 'staff row: Enter opens the staff sheet like a click');
      else ok(await p.evaluate((h) => location.hash !== h, hash0), 'settings2 row: Space navigates like a click');
    }
    await p.close();
  }
  // layout identical with and without the helper (visuals unchanged for pointer users)
  for (const route of ['home', 'settings2', 'staff', 'locset', 'rulehub']) {
    const snap = (o) => open(route, o).then(async (q) => { const r = await q.evaluate(() => ({ h: document.documentElement.scrollHeight, w: document.documentElement.scrollWidth, r: [...document.querySelectorAll('#app *')].filter((e) => !e.closest('header')).slice(0, 400).map((e) => { const b = e.getBoundingClientRect(); return [Math.round(b.x), Math.round(b.y), Math.round(b.width), Math.round(b.height)].join(','); }).join(';') })); await q.close(); return r; });
    const a = await snap({}), b = await snap({ block: true });
    ok(a.h === b.h && a.w === b.w && a.r === b.r, route + ': page geometry identical with and without a11yfix.js (' + a.h + 'px)');
  }

  // ---------- labels associated ----------
  p = await open('locset');
  const lb = await p.evaluate(() => { const l = [...document.querySelectorAll('label')].filter((x) => !x.querySelector('input,select,textarea')); const bad = l.filter((x) => { const f = x.getAttribute('for'); return !f || !document.getElementById(f); }); return { n: l.length, bad: bad.length, ex: bad.slice(0, 2).map((x) => x.textContent) }; });
  ok(lb.n > 0 && lb.bad === 0, 'locset: every <label> now points at a control (' + lb.n + ' labels, unlinked ' + lb.bad + ' ' + lb.ex + ')');
  ok(await p.evaluate(() => { const l = document.querySelector('label[for]'); const i = l && document.getElementById(l.getAttribute('for')); return !!i && i.labels.length >= 1 && i.labels[0] === l; }), 'locset: a tied label is the control label (clicking it focuses the field)');
  await p.close();

  // ---------- aria-pressed synced with .on ----------
  p = await open('rulehub');
  const tg = await p.evaluate(() => [...document.querySelectorAll('button.tog[data-act]')].map((b) => [b.classList.contains('on'), b.getAttribute('aria-pressed')]));
  ok(tg.length > 0 && tg.every(([on, ap]) => ap === String(on)), 'rulehub: aria-pressed matches .on on ' + tg.length + ' toggles');
  await p.evaluate(() => { const b = document.querySelector('button.tog[data-act]'); b.classList.toggle('on'); });
  await wait(p, 120);
  ok(await p.evaluate(() => { const b = document.querySelector('button.tog[data-act]'); return b.getAttribute('aria-pressed') === String(b.classList.contains('on')); }), 'aria-pressed follows a class change');
  await p.close();
  p = await open('matrix');
  const tm = await p.evaluate(() => [...document.querySelectorAll('button.tog[data-act]')].map((b) => [b.classList.contains('on'), b.getAttribute('aria-pressed')]));
  ok(tm.length > 0 && tm.every(([on, ap]) => ap === String(on)), 'matrix: aria-pressed matches .on on ' + tm.length + ' toggles');
  await p.close();

  // ---------- skip link + main ----------
  p = await open('settings2/units');
  ok(await p.evaluate(() => !!document.querySelector('[role=main]')), 'role=main present');
  await p.evaluate(() => { document.activeElement && document.activeElement.blur(); }); await p.keyboard.press('Tab');
  const sk = await p.evaluate(() => { const a = document.activeElement; const r = a.getBoundingClientRect(); return { txt: a.textContent, cls: a.className, vis: r.top >= 0 && r.height > 0 }; });
  ok(/Skip to content/.test(sk.txt) && sk.vis, 'first Tab stop is a visible "Skip to content" link');
  const h0 = await p.evaluate(() => location.hash);
  await p.keyboard.press('Enter'); await wait(p, 200);
  ok(await p.evaluate((h) => location.hash === h, h0), 'skip link does not change the route hash');
  ok(await p.evaluate(() => { const a = document.activeElement; return !!a && a.closest('#app') && !a.closest('header.top') && !a.classList.contains('a11y-skip'); }), 'skip link moves focus into the content, past the header: ' + await act(p));
  await p.close();
  p = await open('home', { lang: 'bn' });
  ok(await p.evaluate(() => /[ঀ-৿]/.test(document.querySelector('.a11y-skip').textContent)), 'Bangla mode: skip link label is Bangla');
  await p.close();
  p = await open('home', { lang: 'en' });
  ok(await p.evaluate(() => !/[ঀ-৿]/.test(document.querySelector('.a11y-skip').textContent)), 'English mode: skip link label is all English');
  await p.close();

  // ---------- 320px reflow on new screens ----------
  for (const route of ['settings2/units', 'locset', 'rulehub', 'purchase/new', 'invoice']) {
    p = await open(route, { w: 320 }); const ov = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth); await p.close();
    ok(ov <= 0, route + ' @320px: no horizontal overflow (' + ov + 'px)');
  }
  // 44px targets on a NEW screen, old screen untouched
  p = await open('settings2/units');
  const sm = await p.evaluate(() => [...document.querySelectorAll('#app button.mini,#app a.mini')].filter((e) => e.offsetParent).map((e) => Math.round(e.getBoundingClientRect().height)));
  ok(sm.length === 0 || sm.every((h) => h >= 44), 'new screen settings2/units: .mini controls are >=44px high (' + sm + ')');
  ok(await p.evaluate(() => document.getElementById('app').hasAttribute('data-a11y-new')), 'settings2/units is flagged as a new screen');
  await p.close();
  p = await open('home');
  ok(await p.evaluate(() => !document.getElementById('app').hasAttribute('data-a11y-new')), 'home (old screen) is not flagged, so its look is untouched');
  await p.close();

  // ---------- axe-core: before (helper blocked) / after ----------
  const R8 = ['locset', 'purchase/new', 'purchase/return', 'settings2/units', 'settings', 'settings2/shelf', 'invoice', 'rulehub'];
  if (!AXE) log('SKIP: axe-core not found (set AXE_JS)');
  else {
    const run = async (route, block) => { const q = await open(route, { block }); const v = await q.evaluate(async (s) => { (0, eval)(s); const r = await axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'] } }); return r.violations.map((x) => ({ id: x.id, imp: x.impact, n: x.nodes.length })); }, AXE); await q.close(); return v; };
    const crit = (v) => v.filter((x) => x.imp === 'critical').reduce((a, x) => a + x.n, 0), tot = (v) => v.reduce((a, x) => a + x.n, 0);
    log('\naxe-core 4.10.2 (critical nodes / all nodes)\nroute                  before      after');
    let cb = 0, ca = 0, newCrit = [];
    for (const r of R8) { const b = await run(r, true), a = await run(r, false); cb += crit(b); ca += crit(a); log(r.padEnd(22) + (crit(b) + '/' + tot(b)).padStart(8) + (crit(a) + '/' + tot(a)).padStart(10)); a.filter((x) => x.imp === 'critical' && !b.some((y) => y.id === x.id)).forEach((x) => newCrit.push(r + ':' + x.id)); }
    log('TOTAL critical'.padEnd(22) + String(cb).padStart(8) + String(ca).padStart(10));
    ok(newCrit.length === 0, 'no NEW critical axe rule on the 8 routes ' + newCrit);
    ok(ca < cb && ca === 0, 'critical axe nodes on the 8 routes: ' + cb + ' -> ' + ca);
  }

  ok(errors.length === 0, 'no page errors' + (errors.length ? ': ' + errors[0] : ''));
  log(`${n - bad} passed, ${bad} failed`); await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e); srv.close(); process.exit(2); } })();
