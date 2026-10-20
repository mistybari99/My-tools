// Information architecture (web/ia.js): registry integrity, drawer reachability, role filtering, search sections, breadcrumb, recent, old URLs, phone width, Increment A acceptance A1-A7.
// Run: node ia_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message + ' @ ' + String(e.stack).split('\n')[1] + ' | ' + p.url().slice(-30))); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o); (o.tables || []).forEach(([k, v]) => { data.tables[k] = v; });
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS=' + JSON.stringify(o.perms || {}) + ';' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');${o.ls || ''}}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1300); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const openDrawer = async (p) => { await p.click('header.top [data-act=nav_open]'); await wait(p, 500); };
  const staffCtx = (roles, locs = [1]) => ({ roles, locations: locs, is_owner: false });

  // ---------- registry integrity (owner) ----------
  let p = await open({}, '#/home');
  const reg = await p.evaluate(() => {
    const ia = window.BOS.IA, local = ['home', 'items', 'staff', 'matrix', 'rules', 'settings', 'logs', 'backup', 'itemreq'], pages = window.BOS_PAGES || {};
    const ids = ia.map((r) => r.id), routes = ia.map((r) => r.route);
    return { n: ia.length, dupId: ids.length - new Set(ids).size, dupRoute: routes.length - new Set(routes).size,
      unresolved: ia.filter((r) => r.status !== 'soon' && !local.includes(r.route.split('/')[0]) && !pages[r.route.split('/')[0]]).map((r) => r.route),
      noLabel: ia.filter((r) => !window.BOS.ia.label(r)).map((r) => r.id), badGroup: ia.filter((r) => !window.BOS.ia.GID.includes(r.group)).map((r) => r.id),
      noKw: ia.filter((r) => r.drawer && !r.kw.length && r.id !== 'products').map((r) => r.id), groups: window.BOS.ia.GID.length, hasGroupPage: !!pages.group };
  });
  ok(reg.n > 50, 'registry has records: ' + reg.n); ok(reg.dupId === 0 && reg.dupRoute === 0, 'no duplicate id / route'); ok(reg.unresolved.length === 0, 'every route resolves to a registered page: ' + reg.unresolved);
  ok(reg.noLabel.length === 0 && reg.badGroup.length === 0, 'labels + groups valid ' + reg.noLabel + reg.badGroup); ok(reg.noKw.length === 0, 'every drawer screen has search keywords: ' + reg.noKw); ok(reg.groups === 13 && reg.hasGroupPage, '13 categories + group page');
  await p.close();

  // ---------- owner: every live drawer screen reachable from the drawer ----------
  p = await open({}, '#/home'); await openDrawer(p);
  const miss = await p.evaluate(() => window.BOS.IA.filter((r) => r.status === 'live' && r.drawer && !['announce', 'todo', 'shifts'].includes(r.route)).filter((r) => !document.querySelector('#nav_body .dr-it[data-v="' + r.route + '"]')).map((r) => r.route));
  ok(miss.length === 0, 'owner: every live drawer screen is in the drawer: ' + miss);
  ok(await p.locator('.dr-g').count() >= 10, 'owner sees the categories: ' + await p.locator('.dr-g').count());
  for (const r of ['bulkitems', 'itemmap', 'itemimport', 'assets', 'recipes', 'rollout', 'changes', 'outbox', 'locations', 'control', 'daybook', 'salary', 'brandpnl', 'discounts', 'ledgerlinks', 'salereturn']) ok(await p.locator(`#nav_body .dr-it[data-v="${r}"]`).count() === 1, 'reachable from the drawer: ' + r);
  // every group has the "everything in this category" page and it lists screens
  await p.evaluate(() => { location.hash = '#/group/item'; }); await wait(p, 700);
  ok(await p.locator('[data-ia=bulkitems]').count() === 1 && await p.locator('[data-ia=itemimport]').count() === 1, 'group page lists the item tools');
  await noOverflow(p, 'group page'); await p.context().close();

  // ---------- staff: only what they may use ----------
  p = await open({ owner: false, perms: { POS: { view: true, enter: true } }, m: { grants: [], ctx: staffCtx(['salesperson']) } }, '#/home'); await openDrawer(p);
  const staffSees = await p.locator('#nav_body .dr-it').evaluateAll((e) => e.map((x) => x.dataset.v));
  ok(staffSees.includes('pos') && staffSees.includes('dues'), 'cashier sees POS + dues: ' + staffSees);
  ok(await p.locator('#nav_body .dr-i.lock').count() <= 8, 'lock mode: at most 8 summary lines: ' + await p.locator('#nav_body .dr-i.lock').count());
  ok(await p.evaluate(() => 'রহিম আলী'.replace(/[^\p{L}\p{M}\p{N} ]/gu, ' ') === 'রহিম আলী') && fs.readFileSync(_P.WEB_DIR + '/nav.js', 'utf8').includes('\\p{L}\\p{M}\\p{N}'), 'Bangla marks survive the customer-search sanitiser (রহিম আলী)');
  ok(!['staff', 'matrix', 'rules', 'settings', 'backup', 'control', 'locations', 'bulkitems', 'rulehub', 'logs', 'releases', 'emergency'].some((r) => staffSees.includes(r)), 'cashier sees no owner-only screens: ' + staffSees);
  await p.context().close();

  // ---------- search: Bangla + English keywords, sections, group line ----------
  p = await open({}, '#/home'); await openDrawer(p);
  const sr = (q) => p.evaluate((x) => { const c = { own: true, roles: [], P: () => true, GF: {}, locOk: () => true, canPos: () => true, anyApprove: () => true, ctlOk: () => true, formLive: () => true }; const s = window.BOS.ia.searchSections(x, c); return { do: s.do.map((d) => d.route), go: s.go.map((r) => r.route), set: s.settings.map((r) => r.route) }; }, q);
  ok((await sr('দাম')).go.includes('items'), 'Bangla keyword দাম finds items'); ok((await sr('price')).go.includes('items'), 'English keyword price finds items');
  ok((await sr('বেতন')).go.includes('salary') && (await sr('payroll')).go.includes('salary'), 'salary by Bangla and English');
  ok((await sr('sell')).do.includes('pos') && (await sr('বিক্রি')).do.includes('pos'), 'verb sell / বিক্রি -> POS (Do)'); ok((await sr('stock count')).do.includes('form/04-3'), 'stock count -> form 04-3');
  ok((await sr('fiscal')).set.includes('settings2/fiscal'), 'Settings section finds fiscal'); ok((await sr('pay supplier')).do.includes('payables'), 'pay supplier -> payables');
  await p.fill('#nav_q', 'bulk'); await wait(p, 400);
  ok(await p.locator('#nav_body .dr-it[data-v=bulkitems]').count() === 1 && /Items & Master Data/.test(await p.textContent('#nav_body')), 'search result shows its category line');
  await p.fill('#nav_q', 'sell'); await wait(p, 400); ok(await p.locator('#nav_body [data-do][data-v=pos]').count() + await p.locator('#nav_body .dr-it[data-v=pos]').count() >= 1, 'sell shows POS in the list');
  await p.fill('#nav_q', 'zzzqqq'); await wait(p, 500); ok(await p.locator('#nav_body [data-state=empty]').count() === 1, 'no result -> empty state');
  await p.context().close();
  p = await open({ owner: false, perms: { ITEMS: { view: true } }, m: { grants: [], ctx: staffCtx(['salesperson']) } }, '#/home'); await openDrawer(p);
  ok((await p.evaluate(() => window.BOS.ia.searchSections('sell', { own: false, roles: [], P: () => false, GF: {}, locOk: () => false, canPos: () => false, anyApprove: () => false, ctlOk: () => false, formLive: () => false }).do.length)) === 0, 'A3: no Sell result without POS permission');
  await p.context().close();

  // ---------- breadcrumb ----------
  p = await open({}, '#/purchase'); await wait(p, 700);
  ok(await p.locator('nav.crumb').count() === 1 && /Purchasing & Suppliers/.test(await p.textContent('nav.crumb')) && /Purchase bills/.test(await p.textContent('nav.crumb')), 'breadcrumb Group > Screen on #/purchase: ' + await p.locator('nav.crumb').allTextContents());
  await p.click('nav.crumb button'); await wait(p, 600); ok(/#\/group\/purch/.test(await p.evaluate(() => location.hash)), 'crumb group link opens the category page'); await noOverflow(p, 'purch group');
  await p.goto(`http://localhost:${PORT}/#/home`); await wait(p, 900); ok(await p.locator('nav.crumb').count() === 0, 'no breadcrumb on Home'); await p.context().close();

  // ---------- recent (last 5, per user) ----------
  p = await open({}, '#/items'); for (const h of ['dues', 'reports', 'biz', 'stock', 'daybook', 'assets']) { await p.evaluate((x) => { location.hash = '#/' + x; }, h); await wait(p, 450); }
  const rc = await p.evaluate(() => window.BOS.ia.recent(JSON.parse(JSON.stringify(window.BOS_APP.S.ctx.profile.id))));
  ok(rc.length === 5 && rc[0] === 'assets' && !rc.includes('items'), 'recent keeps the last 5, newest first: ' + rc);
  await p.goto(`http://localhost:${PORT}/#/home`); await wait(p, 1200); ok(await p.locator('#hv_recent').count() === 0 && !/Recent/i.test(await p.locator('#app').innerText()), 'Home has no Recent block (Module E)'); await p.context().close();

  // ---------- old URLs still open (owner) ----------
  p = await open({}, '#/home');
  for (const r of ['items', 'products', 'itemreq', 'staff', 'matrix', 'rules', 'rulehub', 'settings', 'settings2', 'logs', 'backup', 'dues', 'biz', 'reports', 'lists', 'locations', 'locset', 'control', 'invoice', 'stock', 'purchase', 'recipes', 'assets', 'salereturn', 'daybook', 'salary', 'exceptions', 'releases', 'emergency', 'pending', 'numaudit', 'rollout', 'changes', 'outbox', 'bulkitems', 'itemmap', 'itemimport', 'itemtypes', 'brandpnl', 'discounts', 'ledgerlinks', 'settings2/units', 'payables', 'purchase/new']) {
    await p.evaluate((x) => { location.hash = '#/' + x; }, r); await wait(p, 450);
    ok((await p.evaluate(() => location.hash)) === '#/' + r && await p.locator('#app h1').count() >= 1 && await p.locator('.hgreet').count() === 0, 'old URL opens: ' + r);
  }
  await p.context().close();

  // ---------- A1 cashier home / A5 bottom nav ----------
  p = await open({ owner: false, perms: { POS: { view: true, enter: true } }, m: { grants: [], ctx: staffCtx(['salesperson']) } }, '#/home'); await wait(p, 500);
  ok(await p.locator('#hv_qa [data-quick=pos]').count() === 1, 'A1: cashier quick action Sell is on Home');
  ok(await p.locator('#hv_main [data-v=staff], #hv_main [data-v=releases], #hv_main [data-v=emergency]').count() === 0, 'A1: no owner-only row on cashier Home');
  ok(await p.locator('#bnav button').count() === 5, 'A5: bottom bar has 4 slots + centre Sell orb: ' + await p.locator('#bnav button').count()); ok(await p.locator('#bnav [data-slot=pos]').count() === 1, 'cashier slot 1 is Sell');
  await noOverflow(p, 'cashier home'); await p.context().close();
  p = await open({}, '#/home'); ok(await p.locator('#bnav button').count() === 5 && await p.locator('#bnav [data-slot=control]').count() === 1 && await p.locator('#bnav [data-slot=reports]').count() === 1, 'A5: owner bar = Home, Control, Reports, Me'); await noOverflow(p, 'owner home');
  const before = await p.evaluate(() => window.BOS_NAV.entries().filter((e) => e.kind === 'r').map((e) => e.route).sort().join());
  await p.evaluate(() => localStorage.setItem('bos_ia_home_v2', 'off')); await p.reload(); await wait(p, 1300);
  ok(await p.locator('#bnav [data-act=nav_open]').count() === 1 && await p.locator('#hv_qa .qt').count() === 0, 'switch OFF: old bottom bar + no quick actions');
  const after = await p.evaluate(() => window.BOS_NAV.entries().filter((e) => e.kind === 'r').map((e) => e.route).sort().join());
  ok(before === after, 'A5: drawer route set identical with the switch on/off'); await p.context().close();

  // ---------- A2 owner Now strip, A4 back closes drawer, A7 offline ----------
  p = await open({ tables: [['exceptions', [{ id: 1, status: 'open', created_at: '2026-01-01' }]], ['emergency_requests', [{ id: 1, status: 'pending' }, { id: 2, status: 'pending' }]]] }, '#/home'); await wait(p, 600);
  const now = await p.locator('#hv_main .hrow.mk').evaluateAll((e) => e.map((x) => x.dataset.v));
  ok(now.includes('emergency') && now.includes('exceptions') && now.length <= 5, 'A2: owner Now strip lists the open items (max 5): ' + now);
  await openDrawer(p); await p.goBack(); await wait(p, 400); ok(await p.locator('#navDrawer.on').count() === 0, 'A4: Back closes the drawer first');
  await p.context().setOffline(true); await openDrawer(p); await p.fill('#nav_q', 'sell'); await wait(p, 600);
  ok(await p.locator('#nav_body [data-state=offline]').count() === 1, 'A7: offline notice for Find; Do/Go still listed'); ok(await p.locator('#nav_body [data-v=pos]').count() >= 1, 'A7: Do/Go results still work offline');
  await p.context().close();

  log('A3 close-day / open-shop flows: not built (increment B).');
  const real = errors.filter((e) => !/viewNumAudit|ERR_INTERNET_DISCONNECTED/.test(e));   // numaudit: stub has no data for its rpc (pre-existing); the offline error is the test's own setOffline
  log('errors:', real.length ? real.slice(0, 8) : 'none'); log('assert failures:', bad);
  await br.close(); srv.close();
} catch (e) { console.log('CRASH', e); process.exit(1); } })();
