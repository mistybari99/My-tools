// Control Center (#/control): 12 tiles, tiers, merged Needs you, Home tile, drawer entry, grant-aware route guard. Run: node control_test.js <dir holding smoke.js stub>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w4_common.js');
const base = C.baseData(SP), PORT = 8322, srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA3 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1300); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const asDeleg = (g) => ({ owner: false, m: { grants: g, ctx: { roles: ['salesperson'], locations: [1] } } });

  // ---------- owner ----------
  let p = await open({}, '#/control');
  ok(await p.locator('[data-tile]').count() === 12, 'owner sees 12 tiles');
  ok(await p.locator('.grid[data-group]').count() === 4, 'four groups');
  ok(await p.locator('[data-tile].soon').count() === 1, 'Print & books is the only Soon tile (Rollout board now opens #/rollout)');
  ok(await p.locator('[data-tile=locations] .badge').textContent() === '1', 'Locations tile shows places being set up');
  ok(await p.locator('[data-tile=locset] .badge').textContent() === '1' && await p.locator('[data-tile=lists] .badge').textContent() === '4' && await p.locator('[data-tile=items] .badge').textContent() === '2' && await p.locator('[data-tile=staff] .badge').textContent() === '1', 'tile counts from the server');
  ok(await p.locator('#cc_needs [data-need]').count() === 7, 'merged Needs you: 7 rows with a count (releases/emergency are 0)');
  const keys = await p.locator('#cc_needs [data-need]').evaluateAll((els) => els.map((e) => e.dataset.need));
  ok(['exceptions', 'item_requests', 'staff_pending', 'wastage', 'location_setup', 'settings_drafts', 'lists'].every((k) => keys.includes(k)), 'Needs you combines requests, exceptions, staff, wastage, location setup, drafts, lists');
  ok(/13/.test(await p.textContent('.hsec')), 'total of the needs rows = 13');
  ok(/Owner/.test(await p.textContent('#cc_tier')), 'tier chip');
  await p.screenshot({ path: SP + '/cc_owner.png' }); await noOverflow(p, 'control owner');
  await p.click('[data-tile=locations]'); await wait(p, 600); ok(/#\/locations/.test(await p.evaluate(() => location.hash)) && await p.locator('#lo_list').count() === 1, 'Locations tile opens the screen');
  await p.goto(`http://localhost:${PORT}/#/control`); await wait(p, 700);
  await p.click('#cc_needs [data-need=wastage]'); await wait(p, 600); ok(/#\/stock/.test(await p.evaluate(() => location.hash)), 'wastage row goes to stock');
  // Home tile + drawer
  await p.goto(`http://localhost:${PORT}/#/home`); await wait(p, 1200);
  ok(await p.locator('#hv_ctl [data-act=go][data-v=control]').count() === 1, 'Home has the Control Center tile for the owner');
  ok(/Control Center/.test(await p.textContent('#hv_ctl')) && await p.locator('#hv_ctl .badge').count() === 1, 'tile with total count');
  ok(await p.locator('.hrow[data-v=locations]').count() === 1 && await p.locator('.hrow[data-v=locset]').count() === 1, 'Needs you on Home lists location setup and settings drafts');
  await p.screenshot({ path: SP + '/cc_home.png' }); await noOverflow(p, 'home');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400); await p.click('.dr-g[data-v=settings]'); await p.click('.dr-g[data-v=loc]'); await wait(p, 200);
  ok(await p.locator('.dr-it[data-v=control]').count() === 1 && await p.locator('.dr-it[data-v=locations]').count() === 1, 'drawer has Control Center and Locations'); await p.context().close();

  // ---------- head management ----------
  p = await open(asDeleg(['head_management']), '#/control');
  ok(await p.locator('[data-tile]').count() === 4, 'head management sees 4 tiles (Lists needs the list_manage grant: the server decides the queue by it)');
  const hk = await p.locator('[data-tile]').evaluateAll((els) => els.map((e) => e.dataset.tile).sort().join(','));
  ok(hk === 'locations,locset,printbooks,rollout', 'the right four: ' + hk);
  ok(await p.locator('[data-tile=items], [data-tile=staff], [data-tile=backup], [data-tile=logs]').count() === 0, 'no costs / staff / backup tiles');
  ok(/Head management/.test(await p.textContent('#cc_tier')), 'tier chip head');
  await p.screenshot({ path: SP + '/cc_head.png' }); await noOverflow(p, 'control head');
  ok(await p.locator('[data-tile=lists]').count() === 0, 'no Lists tile for head management alone');
  await p.goto(`http://localhost:${PORT}/#/lists`); await wait(p, 800); ok(await p.locator('.hgreet').count() === 1, 'head management alone cannot open #/lists (Home instead)');
  await p.goto(`http://localhost:${PORT}/#/staff`); await wait(p, 800); ok(await p.locator('[data-act=staffopen]').count() === 0, 'head management cannot open #/staff (owner only)');
  await p.goto(`http://localhost:${PORT}/#/home`); await wait(p, 1200); ok(await p.locator('#hv_ctl [data-act=go][data-v=control]').count() === 1, 'head management also gets the Home tile');
  await p.context().close();

  // ---------- single-grant delegates ----------
  p = await open(asDeleg(['list_manage']), '#/control');
  ok(await p.locator('[data-tile]').count() === 1 && await p.locator('[data-tile=lists]').count() === 1, 'list_manage sees only the Lists tile'); await p.context().close();
  p = await open(asDeleg(['location_manage']), '#/control');
  ok(await p.locator('[data-tile]').count() === 1 && await p.locator('[data-tile=locations]').count() === 1, 'location_manage sees only Locations'); await p.context().close();
  p = await open(asDeleg(['settings_approve']), '#/control');
  ok(await p.locator('[data-tile]').count() === 1 && await p.locator('[data-tile=locset]').count() === 1, 'settings_approve sees only Location settings'); await p.context().close();

  // ---------- route guard (known issue: list_manage holders could not open #/lists) ----------
  p = await open(asDeleg(['list_manage']), '#/lists');
  ok(/#\/lists/.test(await p.evaluate(() => location.hash)) && await p.locator('#app h1').first().textContent() !== '', 'list_manage holder can open #/lists');
  ok(!(await p.locator('.hgreet').count()), 'not bounced to Home');
  await p.goto(`http://localhost:${PORT}/#/locations`); await wait(p, 800); ok(await p.locator('#lo_list').count() === 0, 'list_manage alone cannot open #/locations');
  await p.context().close();
  p = await open(asDeleg(['location_manage']), '#/locations'); ok(await p.locator('#lo_list .card').count() === 7, 'location_manage opens #/locations'); await p.goto(`http://localhost:${PORT}/#/lists`); await wait(p, 800); ok(await p.locator('.hgreet').count() === 1, 'location_manage alone cannot open #/lists (Home instead)'); await p.context().close();
  p = await open(asDeleg(['settings_approve']), '#/locset'); ok(await p.locator('#ls_loc').count() === 1, 'settings_approve opens #/locset'); await p.context().close();

  // ---------- staff ----------
  p = await open(asDeleg([]), '#/control');
  ok(await p.locator('#cc_needs').count() === 0 && await p.locator('.hgreet').count() === 1, 'staff typing #/control lands on Home');
  ok(await p.locator('#hv_ctl [data-act=go]').count() === 0, 'staff Home has no Control Center tile');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400); ok(await p.locator('.dr-it[data-v=control]').count() === 0 && await p.locator('.dr-it[data-v=locations]').count() === 0, 'staff drawer has no Control Center / Locations'); await p.context().close();

  // ---------- languages ----------
  p = await open({ lang: 'bn' }, '#/control'); ok(/কন্ট্রোল সেন্টার/.test(await p.textContent('h1')) && /লোকেশন/.test(await p.textContent('[data-tile=locations]')), 'Bangla'); await p.screenshot({ path: SP + '/cc_bn.png' }); await p.context().close();
  p = await open({ lang: 'mix' }, '#/control'); ok(/Control Center/.test(await p.textContent('h1')), 'Bng-Eng'); await p.context().close();

  console.log('errors:', errors.length ? [...new Set(errors)] : 'none'); console.log('assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.error('TEST CRASH', e); srv.close(); process.exit(2); } })();
