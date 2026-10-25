// Business-template gate (web/bizctx.js + web/ia.js): the sweets business (food_manufacturing, or no template) does not see screens of other trades in the drawer / Home / search; a business with another template does;
// routes stay registered. Also: announce / todo / shifts stay visible to the owner while their switch is OFF. Test names only.
// Run: node bizgate_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const clone = (x) => JSON.parse(JSON.stringify(x));
 c.rpc = async (fn, args) => { (window.__ACO = window.__ACO || []).push([fn, clone(args || {})]);
  if (fn === 'org_tree') { if (window.__ORGERR) return { data: null, error: { message: 'function org_tree does not exist' } }; return { data: clone(window.__ORGROWS || []), error: null }; }
  return rpc(fn, args); }; return c; }; })();`;
const row = (id, parent_id, kind, code, name_bn, name_en, extra) => Object.assign({ id, parent_id, kind, code, name_bn, name_en, template_code: null, template_status: null, status: 'active', attrs: {}, depth: 0, path: code, location_ids: [] }, extra || {});
const ORG = (o) => [row(1, null, 'group', 'GROUP', 'গ্রুপ', 'Group'), row(2, 1, 'legal_entity', 'LE1', 'আইনি এক', 'Entity One'), row(10, 2, 'business', 'BIZ1', o.n1bn || 'মিষ্টি ব্যবসা', o.n1en || 'Sweets business', { template_code: 'food_manufacturing', template_status: 'available' }),
  ...(o.two ? [row(3, 1, 'legal_entity', 'LE2', 'আইনি দুই', 'Entity Two'), row(20, 3, 'business', 'BIZ2', o.n2bn || 'দ্বিতীয় ব্যবসা', o.n2en || 'Second <b>Biz</b>')] : [])];
const LOCS = (two) => [
  { id: 1, code: 'main', name_bn: 'ইসলামিয়া মেইন', name_mix: 'ইসলামিয়া Main', name_en: 'Islamia Main', sort: 1, kind: 'showroom', status: 'live', is_active: true, org_unit_id: 10 },
  { id: 2, code: 'branch2', name_bn: '২য় শাখা', name_mix: '২য় Branch', name_en: '2nd Branch', sort: 2, kind: 'showroom', status: 'live', is_active: true, org_unit_id: 10 },
  ...(two ? [{ id: 3, code: 'hw1', name_bn: 'দোকান এক', name_en: 'Shop One', sort: 3, kind: 'showroom', status: 'live', is_active: true, org_unit_id: 20 }, { id: 4, code: 'hw2', name_bn: 'দোকান দুই', name_en: 'Shop Two', sort: 4, kind: 'showroom', status: 'live', is_active: true, org_unit_id: 20 }] : [])];
const BRANDS_DB = [{ location_id: 1, brand_code: 'islamiya', brand_bn: 'ইসলামিয়া মিষ্টি ঘর', brand_en: 'ISLAMIYA MISTY GHAR' }, { location_id: 2, brand_code: 'islamiya', brand_bn: 'ইসলামিয়া মিষ্টি ঘর', brand_en: 'ISLAMIYA MISTY GHAR' },
  { location_id: 3, brand_code: 'hw_brand', brand_bn: 'হার্ডওয়্যার ব্র্যান্ড', brand_en: 'Hardware Brand' }];
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 1 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: fs.readFileSync(WEB + '/index.html', 'utf8') }));
    const data = C.mk(base, {}); const T = data.tables; T.locations = LOCS((o.rows || []).some((r) => r.id === 20)); T.report_brand_map = o.brands === false ? [] : BRANDS_DB;
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__ORGROWS=${JSON.stringify(o.rows || [])};window.__ORGERR=${!!o.err};${o.owner === false ? "window.__OWNER=false;window.__PROFILE={id:'u2',staff_id:'mgr2',full_name:'Manager',status:'active',lang:'en'};" : ''}try{localStorage.setItem('bos_lang','en')${o.stored ? `;localStorage.setItem('bos_biz_u1','${o.stored}')` : ''}}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const locIds = (p, k) => p.evaluate((key) => (window.BOS.ENV[key] || []).map((l) => l.id), k);
  const openDrawer = async (p) => { await p.evaluate(() => window.BOS_NAV.open()); await wait(p, 400); };
  const OTHER = ['variants', 'cheques', 'schemes', 'tinting', 'impexp'];
  const ORG2 = (tpl) => [...ORG({ two: true }).slice(0, 4), row(20, 3, 'business', 'BIZ2', 'দ্বিতীয় ব্যবসা', 'Second business', tpl === undefined ? {} : { template_code: tpl, template_status: 'not_implemented' })];
  const inDrawer = (p, r) => p.locator('#nav_body .dr-it[data-v="' + r + '"]').count();
  const vis = (p, r) => p.evaluate((x) => window.BOS.IA.find((y) => y.route === x).ok({ own: true, GF: {}, locOk: () => true }), r);

  // 1. one sweets business: other-trade screens are not offered; routes stay registered; announce / todo / shifts are offered (switch OFF)
  let p = await open('#/home', { rows: ORG({}) });
  ok(await p.evaluate(() => window.BOS.biz.otherTrade() === false && window.BOS.biz.hasTemplate('food_manufacturing')), 'sweets business: otherTrade() false');
  for (const r of OTHER) ok(await vis(p, r) === false, 'sweets: registry hides ' + r);
  await openDrawer(p);
  for (const r of OTHER) ok(await inDrawer(p, r) === 0, 'sweets: no drawer entry for ' + r);
  for (const r of ['announce', 'todo', 'shifts']) ok(await inDrawer(p, r) === 1, 'owner: drawer entry for ' + r + ' while its switch is OFF');
  ok(await p.evaluate((l) => l.every((r) => { const x = window.BOS.IA.find((y) => y.route === r); return !!x && x.status === 'live'; }), OTHER), 'other-trade routes still registered and live (hidden only by the gate)');
  await p.evaluate(() => { location.hash = '#/variants'; }); await wait(p, 900);
  ok(await p.locator('#app').count() === 1 && !/not found|404/i.test(await p.locator('#app').innerText()), 'the route still opens by link');
  await noOverflow(p, 'sweets drawer + variants route');

  // 2. no organization data at all (phase122 missing): same as sweets
  p = await open('#/home', { err: true });
  for (const r of OTHER) ok(await vis(p, r) === false, 'no org data: registry hides ' + r);

  // 3. two businesses: sweets chosen -> hidden; the other business has a non-sweets template -> shown; all -> shown
  p = await open('#/home', { rows: ORG2('dealership') });
  for (const r of OTHER) ok(await vis(p, r) === false, 'two businesses, sweets chosen: hidden ' + r);
  await p.evaluate(() => window.BOS.biz.setCur(20));
  for (const r of OTHER) ok(await vis(p, r) === true, 'other-template business chosen: shown ' + r);
  await p.evaluate(() => window.BOS.biz.setCur(10));
  for (const r of OTHER) ok(await vis(p, r) === false, 'back to sweets: hidden ' + r);
  await p.evaluate(() => window.BOS.biz.setCur('all'));
  for (const r of OTHER) ok(await vis(p, r) === true, 'owner all-businesses view: shown ' + r);
  await p.evaluate(() => window.BOS.biz.setCur(20)); await openDrawer(p);
  for (const r of OTHER) ok(await inDrawer(p, r) === 1, 'drawer shows ' + r + ' for the other-template business');
  await noOverflow(p, 'drawer, other-template business');
  // a second business without a template is the sweets kind: nothing appears
  p = await open('#/home', { rows: ORG2(undefined) }); await p.evaluate(() => window.BOS.biz.setCur(20));
  for (const r of OTHER) ok(await vis(p, r) === false, 'second business without template: hidden ' + r);

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
