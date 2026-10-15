// Stage B2 business context (web/bizctx.js): unchanged sweets rendering, switcher hidden for one business / visible for two, pickers filtered, 'all' only for the owner and labelled,
// DB-driven brand lists with the old list as fallback, brand/title from the business name, escaped names, no JS errors, no overflow at 360px.
// Run: node b2_test.js <abs tests/web dir>
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
  const legacy = 'ISLAMIYA MISTY GHAR';

  // 1. one business (today's sweets): nothing changes
  let p = await open('#/home', { rows: ORG({}) });
  ok(await p.evaluate(() => window.BOS.biz.multi() === false && window.BOS.biz.list().length === 1), 'one business detected');
  ok(JSON.stringify(await locIds(p, 'locs')) === '[1,2]' && JSON.stringify(await locIds(p, 'locsAll')) === '[1,2]', 'one business: location list untouched');
  ok(await p.evaluate(() => window.BOS.ENV.locs === window.BOS.ENV.locsAll), 'one business: same array (no copy)');
  await openDrawer(p);
  ok(await p.locator('#nav_biz').count() === 0 && await p.locator('#nav_bizbox').count() === 0, 'switcher hidden for a single business');
  ok((await p.textContent('.dr-head')).includes(legacy), 'drawer shows the legacy brand while the business still has the seeded placeholder name');
  ok(!(await p.title()).includes('Sweets business'), 'document title not changed by the placeholder name');
  ok(await p.evaluate(() => window.BOS.biz.brand().custom !== true), 'brand = legacy');
  await noOverflow(p, 'home + drawer, one business');

  // 2. phase122 missing / org_tree error: old behaviour
  p = await open('#/home', { err: true });
  ok(await p.evaluate(() => window.BOS.biz.list().length === 0 && !window.BOS.biz.multi()) && JSON.stringify(await locIds(p, 'locs')) === '[1,2]', 'org_tree error: no businesses, no filter');
  await openDrawer(p); ok(await p.locator('#nav_biz').count() === 0, 'org_tree error: no switcher');

  // 3. two businesses, owner
  p = await open('#/home', { rows: ORG({ two: true }) });
  ok(await p.evaluate(() => window.BOS.biz.multi() && window.BOS.biz.cur() === 10), 'two businesses: default = the first (original) business');
  ok(JSON.stringify(await locIds(p, 'locs')) === '[1,2]' && JSON.stringify(await locIds(p, 'locsAll')) === '[1,2,3,4]', 'pickers show only the chosen business');
  await openDrawer(p);
  ok(await p.locator('#nav_biz').count() === 1, 'switcher visible for two businesses');
  const opts = await p.locator('#nav_biz option').allTextContents(); ok(opts.length === 3 && /All businesses \(owner master view\)/.test(opts[2]), 'owner gets the labelled all-businesses option: ' + opts.join('|'));
  ok(opts.some((t) => t === 'Second <b>Biz</b>') && !(await p.locator('#nav_bizbox b').count()), 'business name escaped');
  const lo = await p.locator('#nav_loc option').allTextContents().catch(() => []); ok(lo.length === 0 || (!lo.includes('Shop One') && lo.includes('Islamia Main')), 'location drawer picker only has business 1 places: ' + lo.join('|'));
  ok((await p.textContent('.dr-head')).includes(legacy), 'first business keeps the legacy brand');
  await noOverflow(p, 'drawer, two businesses');
  await p.screenshot({ path: SP + '/b2_switcher.png' });
  await p.selectOption('#nav_biz', '20'); await wait(p, 700);
  ok(JSON.stringify(await locIds(p, 'locs')) === '[3,4]', 'after switching, pickers show business 2 places only');
  ok(await p.evaluate(() => localStorage.getItem('bos_biz_u1')) === '20', 'choice remembered per user');
  await openDrawer(p);
  ok((await p.textContent('.dr-head')).includes('Second') && !(await p.textContent('.dr-head')).includes(legacy), 'second business name used as brand in drawer');
  ok((await p.title()).includes('Second'), 'document title follows the business name');
  const lo2 = await p.locator('#nav_loc option').allTextContents().catch(() => []); ok(lo2.includes('Shop One') && !lo2.includes('Islamia Main'), 'drawer location picker follows the business: ' + lo2.join('|'));
  ok(await p.evaluate(() => window.BOS.biz.brandFor(1).bn) === 'ইসলামিয়া মিষ্টি ঘর' && await p.evaluate(() => window.BOS.biz.brandFor(3).en) === 'Second <b>Biz</b>', 'document brand follows the business of its place');
  await p.selectOption('#nav_biz', 'all'); await wait(p, 700);
  ok(JSON.stringify(await locIds(p, 'locs')) === '[1,2,3,4]', 'owner master view: all places');
  await openDrawer(p); ok(await p.locator('#nav_bizbox .chip.warn').count() === 1 && /all businesses together/.test(await p.textContent('#nav_bizbox')), 'all-businesses view is clearly labelled');
  await noOverflow(p, 'all view');
  // stored 'all' for a non-owner is refused
  p = await open('#/home', { rows: ORG({ two: true }), owner: false, stored: 'all' });
  ok(await p.evaluate(() => window.BOS.biz.cur() === 10), 'non-owner can never be in the all view');
  await openDrawer(p); const no = await p.locator('#nav_biz option').allTextContents().catch(() => []); ok(!no.some((t) => /All businesses/.test(t)), 'non-owner has no all-businesses option');
  // a person who sees only one business (org_tree returns only their chain): no switcher
  p = await open('#/home', { rows: ORG({}), owner: false });
  await openDrawer(p); ok(await p.locator('#nav_biz').count() === 0, 'single-business user: no switcher');

  // 4. brand lists driven by report_brand_map, fallback otherwise
  p = await open('#/home', { rows: ORG({}) });
  const fb = [['islamia', { bn: 'ইসলামিয়া মিষ্টি ঘর', en: 'ISLAMIYA MISTY GHAR' }], ['bari', { bn: 'মিষ্টি বাড়ি', en: 'MISTY BARI' }], ['other', { bn: 'অন্য', en: 'Other' }]];
  const r1 = await p.evaluate((f) => window.BOS.biz.brandOpts(f, ['other']).map((x) => x[0]), fb);
  ok(JSON.stringify(r1) === JSON.stringify(['islamia', 'hw_brand', 'other']) || JSON.stringify(r1) === JSON.stringify(['islamia', 'other']), 'DB brand keeps the old stored code when it is the same brand: ' + r1);
  p = await open('#/home', { rows: ORG({}), brands: false });
  const r2 = await p.evaluate((f) => window.BOS.biz.brandOpts(f, ['other']), fb); ok(JSON.stringify(r2) === JSON.stringify(fb), 'empty DB list = the old list exactly');
  const f185 = await p.evaluate(() => { const f = window.BOS.forms['05-5'].head.find((x) => x.id === 'brand' || x.key === 'brand'); const o = f && (typeof f.options === 'function' ? f.options() : f.options); return o ? o.map((x) => x[0]) : null; });
  ok(JSON.stringify(f185) === JSON.stringify(['islamia', 'bari', 'alcakes', 'other']), 'form 05-5 brand select unchanged when the DB list is empty: ' + f185);
  p = await open('#/home', { rows: ORG({ two: true }) });
  const r3 = await p.evaluate((f) => window.BOS.biz.brandOpts(f, ['other']).map((x) => x[0]), fb); ok(JSON.stringify(r3) === JSON.stringify(['islamia', 'other']), 'brand list cut to the chosen business: ' + r3);
  await p.evaluate(() => window.BOS.biz.setCur(20));
  const r4 = await p.evaluate((f) => window.BOS.biz.brandOpts(f, ['other']).map((x) => x[0]), fb); ok(JSON.stringify(r4) === JSON.stringify(['hw_brand', 'other']), 'second business gets its own brands: ' + r4);

  // 5. an owner-renamed single business becomes the brand (receipts, header, title)
  p = await open('#/home', { rows: ORG({ n1bn: 'নতুন নাম', n1en: 'New Name Ltd' }) });
  ok(await p.evaluate(() => window.BOS.biz.brand().en) === 'New Name Ltd' && (await p.title()).includes('New Name Ltd'), 'renamed business: brand and title follow it');
  const h1 = await p.evaluate(() => [...document.querySelectorAll('header.top h1, h1.brandh, .brandh')].map((e) => e.textContent).join('|')); ok(h1.includes('New Name Ltd'), 'page header shows the business name: ' + h1);

  // 6. other screens still draw with two businesses, no overflow
  for (const h of ['#/organization', '#/locations', '#/reports']) { p = await open(h, { rows: ORG({ two: true }) }); await noOverflow(p, h); }

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
