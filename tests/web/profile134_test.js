// Business profile (web/profile134.js, #/profile) + brand from the profile (web/bizctx.js): a person of ONE business sees only his own business (name, logo, receipt text), never a switcher,
// a group name, 'all businesses' or a tree above his business; the owner sees the group name only on owner-only screens (#/organization root, the master view note); a two-business owner gets the
// switcher with the profile names; the manager of a business edits the profile (patch + client key, friendly errors); a plain user sees it read-only without the licence number.
// Run: node profile134_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const clone = (x) => JSON.parse(JSON.stringify(x)); const W = () => window.__PF;
 c.rpc = async (fn, args) => { (window.__ACO = window.__ACO || []).push([fn, clone(args || {})]);
  if (fn === 'org_tree') return { data: clone(W().tree), error: null };
  if (fn === 'has_grant') return { data: !!W().grant, error: null };
  if (fn === 'business_profile_list134') return { data: clone(W().list), error: null };
  if (fn === 'business_profile_get') { const id = (args && args.p_biz) || W().list[0].org_unit_id; const x = W().list.find((r) => r.org_unit_id === id); if (!x) return { data: null, error: { message: 'not allowed' } };
    return { data: Object.assign({}, x, { business_id: x.org_unit_id, can_edit: !!W().edit, trade_licence_ref: W().edit ? 'TL-9' : null }), error: null }; }
  if (fn === 'business_profile_save') { if (W().err) return { data: null, error: { message: W().err } }; const x = W().list.find((r) => r.org_unit_id === args.p_biz); Object.assign(x, args.p_patch); return { data: { dup: false, id: 1, business_id: args.p_biz }, error: null }; }
  return rpc(fn, args); }; return c; }; })();`;
const row = (id, parent_id, kind, code, name_bn, name_en, extra) => Object.assign({ id, parent_id, kind, code, name_bn, name_en, template_code: null, template_status: null, status: 'active', attrs: {}, depth: 0, path: code, location_ids: [] }, extra || {});
const prof = (id, code, bn, en, extra) => Object.assign({ org_unit_id: id, code, status: 'active', display_name_bn: bn, display_name_en: en, short_name: null, logo_path: null, address: null, phone: null, email: null, receipt_header: null, receipt_footer: null, theme_color: null, can_edit: false }, extra || {});
const TREE_ONE = [row(10, null, 'business', 'SWEETS', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR', { template_code: 'food_manufacturing' })];   // what the server sends a person of one business
const TREE_OWNER = [row(1, null, 'group', 'GROUP', 'MD-AL AMIN', 'MD-AL AMIN'), row(2, 1, 'legal_entity', 'LE-S', 'আইনি এক', 'Entity One', { depth: 1 }), row(10, 2, 'business', 'SWEETS', 'মিষ্টি ব্যবসা', 'Sweets business', { depth: 2 }),
  row(3, 1, 'legal_entity', 'LE-Z', 'আইনি দুই', 'Entity Two', { depth: 1 }), row(20, 3, 'business', 'ZETA', 'জেটা', 'Zeta Hardware B134', { depth: 2 })];
const LOCS = (two) => [
  { id: 1, code: 'main', name_bn: 'মেইন', name_en: 'Main', sort: 1, kind: 'showroom', status: 'live', is_active: true, org_unit_id: 10 },
  ...(two ? [{ id: 3, code: 'hw1', name_bn: 'দোকান এক', name_en: 'Shop One', sort: 3, kind: 'showroom', status: 'live', is_active: true, org_unit_id: 20 }] : [])];
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 1 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: fs.readFileSync(WEB + '/index.html', 'utf8') }));
    const data = C.mk(base, {}); const T = data.tables; T.locations = LOCS(o.two); T.report_brand_map = [];
    const PF = { tree: o.tree, list: o.list, edit: !!o.edit, grant: !!o.grant, err: o.err || null };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__PF=${JSON.stringify(PF)};${o.owner === false ? "window.__OWNER=false;window.__PROFILE={id:'u2',staff_id:'mgr2',full_name:'Manager',status:'active',lang:'en'};" : ''}try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const pick = (p, sel, v) => p.evaluate(([s, x]) => { const e = document.querySelector(s); e.value = x; e.dispatchEvent(new Event('change', { bubbles: true })); }, [sel, v]);
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const calls = (p, fn) => p.evaluate((f) => (window.__ACO || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const openDrawer = async (p) => { await p.evaluate(() => window.BOS_NAV.open()); await wait(p, 400); };
  const sweets = prof(10, 'SWEETS', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR', { address: 'Main road 1', phone: '01711-000000', receipt_header: 'Welcome <b>x</b>', receipt_footer: 'Come again' });

  // 1. a person of ONE business (not the owner)
  let p = await open('#/home', { owner: false, tree: TREE_ONE, list: [sweets] });
  ok(await p.evaluate(() => window.BOS.biz.multi() === false && window.BOS.biz.list().length === 1), 'one business detected');
  await openDrawer(p);
  ok(await p.locator('#nav_biz').count() === 0 && await p.locator('#nav_bizbox').count() === 0, 'no switcher');
  let dh = await p.textContent('.dr-head'); ok(/ISLAMIYA MISTY GHAR/.test(dh), 'drawer shows the business profile name');
  ok(!/MD-AL AMIN|All businesses|Group/i.test(await text(p)), 'no group name / all businesses on screen');
  ok(/ISLAMIYA MISTY GHAR/.test(await p.title()), 'document title from the profile');
  ok(await p.evaluate(() => { const r = window.BOS.biz.receipt(1); return r.header === 'Welcome <b>x</b>' && r.footer === 'Come again' && r.address === 'Main road 1'; }), 'receipt texts of the profile');
  ok(await p.evaluate(() => window.BOS.biz.groupName() === ''), 'no group name for a non-owner');
  await p.close();

  // 2. #/organization for a manager of one business: the business is the root, nothing above it
  p = await open('#/organization', { owner: false, grant: true, tree: TREE_ONE, list: [sweets] });
  let t = await text(p);
  ok(await p.locator('.og-node').count() === 1 && /ISLAMIYA MISTY GHAR|Sweets/i.test(t) && !/MD-AL AMIN|Legal entity|Group/.test(t), 'organization shows only the own business as root (no group, no legal entity)');
  await noOverflow(p, 'organization'); await p.close();

  // 3. #/profile: a plain user sees it read only, no licence, no picker
  p = await open('#/profile', { owner: false, tree: TREE_ONE, list: [sweets], edit: false });
  t = await text(p);
  ok(await p.locator('#pf_nbn').inputValue() === 'ইসলামিয়া মিষ্টি ঘর' && await p.locator('#pf_nbn').isDisabled(), 'name shown, read only');
  ok(await p.locator('#pf_lic').count() === 0 && await p.locator('[data-act=pf_save]').count() === 0 && await p.locator('#pf_biz').count() === 0, 'no licence field, no save button, no business picker');
  ok(/View only/.test(t), 'read-only note'); await noOverflow(p, 'profile read only'); await p.close();

  // 4. the manager of the business edits it
  p = await open('#/profile', { owner: false, grant: true, tree: TREE_ONE, list: [sweets], edit: true });
  ok(await p.locator('#pf_lic').inputValue() === 'TL-9' && await p.locator('[data-act=pf_save]').count() === 1, 'manager sees the licence and the save button');
  await p.fill('#pf_addr', 'New road 5'); await p.fill('#pf_rf', 'See you');
  await p.click('[data-act=pf_save]'); await wait(p, 600);
  let c = await calls(p, 'business_profile_save'); const last = c[c.length - 1] || {};
  ok(c.length === 1 && last.p_biz === 10 && last.p_patch.address === 'New road 5' && last.p_patch.receipt_footer === 'See you' && last.p_client && last.p_patch.display_name_bn === 'ইসলামিয়া মিষ্টি ঘর', 'save sends the patch for the own business with a client key');
  ok(!('theme_color' in last.p_patch), 'an untouched default colour is not sent');
  ok(/Saved/.test(await p.textContent('#toast')), 'saved toast');
  await p.evaluate(() => { window.__PF.err = 'bad_color'; }); await p.fill('#pf_addr', 'x'); await p.click('[data-act=pf_save]'); await wait(p, 400);
  ok(/Colour must look like/.test(await p.textContent('#pf_err')), 'server code shown as friendly text');
  await p.evaluate(() => { window.__PF.err = 'weird text 7'; }); await p.click('[data-act=pf_save]'); await wait(p, 400);
  ok(/weird text 7/.test(await p.textContent('#pf_err')), 'unknown error shown raw');
  await p.fill('#pf_nbn', ''); await p.click('[data-act=pf_save]'); await wait(p, 200);
  ok(/Name is not valid/.test(await p.textContent('#pf_err')) && (await calls(p, 'business_profile_save')).length === 3, 'empty name stopped in the browser');
  await noOverflow(p, 'profile edit'); await p.close();

  // 5. the owner with two businesses
  const zeta = prof(20, 'ZETA', 'জেটা হার্ডওয়্যার ১৩৪', 'Zeta Hardware B134');
  p = await open('#/home', { two: true, tree: TREE_OWNER, list: [sweets, zeta], edit: true });
  ok(await p.evaluate(() => window.BOS.biz.multi() && window.BOS.biz.list().length === 2), 'owner: two businesses');
  await openDrawer(p);
  ok(await p.locator('#nav_biz').count() === 1, 'owner: switcher present');
  let opts = await p.locator('#nav_biz option').allTextContents();
  ok(opts.some((x) => /ISLAMIYA MISTY GHAR/.test(x)) && opts.some((x) => /Zeta Hardware B134/.test(x)) && opts.some((x) => /All businesses/.test(x)), 'switcher lists the profile names and the master view');
  await pick(p, '#nav_biz', '20'); await wait(p, 500);
  await openDrawer(p); ok(/Zeta Hardware B134/.test(await p.textContent('.dr-head')) && /Zeta Hardware B134/.test(await p.title()), 'entering the second business shows its own profile name');
  await pick(p, '#nav_biz', 'all'); await wait(p, 500); await openDrawer(p);
  ok(/MD-AL AMIN/.test(await p.textContent('#nav_bizbox')), 'the owner master view names the group');
  await p.close();
  p = await open('#/organization', { two: true, tree: TREE_OWNER, list: [sweets, zeta], edit: true });
  t = await text(p); ok(/MD-AL AMIN/.test(t) && await p.locator('.og-node').count() === 5, 'owner: organization root shows the group name, all units');
  await p.close();
  p = await open('#/profile', { two: true, tree: TREE_OWNER, list: [sweets, zeta], edit: true });
  ok(await p.locator('#pf_biz').count() === 1, 'owner: business picker on the profile screen');
  await pick(p, '#pf_biz', '20'); await wait(p, 500);
  ok(await p.locator('#pf_nen').inputValue() === 'Zeta Hardware B134', 'picker loads the other profile');
  ok((await calls(p, 'business_profile_get')).some((x) => x.p_biz === 20), 'get called for the picked business');
  await noOverflow(p, 'profile owner'); await p.close();

  // 6. old server (phase134 not pasted): the legacy brand stays
  p = await open('#/home', { owner: false, tree: [row(10, 2, 'business', 'SWEETS', 'মিষ্টি ব্যবসা', 'Sweets business')], list: [] });
  await openDrawer(p); ok(/ISLAMIYA MISTY GHAR/.test(await p.textContent('.dr-head')), 'without profiles the legacy brand is shown'); await p.close();

  ok(!errors.length, 'no JS errors: ' + errors.slice(0, 3).join(' | '));
  console.log(bad ? 'PROFILE134: ' + bad + ' FAILED' : 'PROFILE134: ALL OK'); await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e); process.exit(2); } })();
