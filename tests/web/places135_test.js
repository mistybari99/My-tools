// Places of a business (web/places135.js inside #/organization, phase135): add a place (client key, friendly errors, the place appears in the pick-lists of its own business only),
// list + move (owner only: check first, blockers, force tick), the guided "New business" flow (template status shown honestly, 1..n places, branch units, summary + checklist, retry makes nothing twice),
// a manager of one business has no New business / Move, no overflow at 360 px, no JS errors.   Run: node places135_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const clone = (x) => JSON.parse(JSON.stringify(x)); const W = () => window.__PF;
 c.rpc = async (fn, args) => { (window.__ACO = window.__ACO || []).push([fn, clone(args || {})]); const w = W(); args = args || {};
  if (fn === 'org_tree') return { data: clone(w.tree), error: null };
  if (fn === 'has_grant') return { data: true, error: null };
  if (fn === 'business_profile_list134') return { data: [], error: null };
  if (fn === 'org_unit_save') {
    if (w.errUnit) return { data: null, error: { message: w.errUnit } };
    const seen = w.keys['u' + args.p_client]; if (seen) return { data: { dup: true, id: seen.id, code: seen.code }, error: null };
    const id = w.next++; const par = w.tree.find((r) => r.id === args.p_parent) || {}; const code = String(args.p_code).toUpperCase();
    w.tree.push({ id, parent_id: args.p_parent, kind: args.p_kind, code, name_bn: args.p_name_bn, name_en: args.p_name_en, template_code: args.p_template, template_status: null, status: 'active', attrs: {}, depth: (par.depth || 0) + 1, path: code, location_ids: [] });
    w.keys['u' + args.p_client] = { id, code }; return { data: { dup: false, id, code }, error: null }; }
  if (fn === 'business_place_create135') {
    if (w.err) return { data: null, error: { message: w.err } };
    const seen = w.keys['p' + args.p_client]; if (seen) return { data: { dup: true, id: seen.id, code: seen.code }, error: null };
    const id = w.nextLoc++; const unit = args.p_org_branch || args.p_business; const bz = w.tree.find((r) => r.id === args.p_business);
    const code = String(bz.code).toLowerCase() + '_' + (args.p_code || 'p' + id); const row = { id, code, name_bn: args.p_name_bn, name_en: args.p_name_en, sort: id, kind: args.p_kind, status: 'setting_up', is_active: true, org_unit_id: unit };
    w.places.push(row); window.__DATA.tables.locations.push(clone(row)); w.keys['p' + args.p_client] = { id, code }; return { data: { dup: false, id, code, business_id: args.p_business, org_unit_id: unit }, error: null }; }
  if (fn === 'business_places_list135') { const rows = w.places.filter((x) => { let u = w.tree.find((r) => r.id === x.org_unit_id); while (u && u.kind !== 'business') u = w.tree.find((r) => r.id === u.parent_id); return u && u.id === args.p_business; });
    return { data: rows.map((x) => { const u = w.tree.find((r) => r.id === x.org_unit_id) || {}; return Object.assign({}, x, { unit_kind: u.kind, unit_code: u.code, unit_name_bn: u.name_bn, unit_name_en: u.name_en }); }), error: null }; }
  if (fn === 'business_place_move135') {
    if (args.p_dry) return { data: Object.assign({ dry: true, stock_items: 2, tx_total: 4, users: 0, open_documents: 0, needs_force: true, can_move: false, blockers: ['place_has_transactions'] }, w.impact || {}), error: null };
    if (w.errMove) return { data: null, error: { message: w.errMove } };
    return { data: { dup: false, id: args.p_location }, error: null }; }
  return rpc(fn, args); }; return c; }; })();`;
const row = (id, parent_id, kind, code, name_bn, name_en, extra) => Object.assign({ id, parent_id, kind, code, name_bn, name_en, template_code: null, template_status: null, status: 'active', attrs: {}, depth: 0, path: code, location_ids: [] }, extra || {});
const TREE_OWNER = () => [row(1, null, 'group', 'GROUP', 'গ্রুপ-ক', 'Group Alpha'), row(2, 1, 'legal_entity', 'LE-S', 'আইনি এক', 'Entity One', { depth: 1 }), row(10, 2, 'business', 'SWEETS', 'ব্যবসা এক', 'Business One', { depth: 2, template_code: 'food_manufacturing', template_status: 'available' }),
  row(3, 1, 'legal_entity', 'LE-D', 'আইনি দুই', 'Entity Two', { depth: 1 }), row(20, 3, 'business', 'DLR', 'ব্যবসা দুই', 'Business Two', { depth: 2, template_code: 'dealership', template_status: 'not_implemented' }),
  row(21, 20, 'branch', 'DLR-N', 'উত্তর শাখা', 'North branch', { depth: 3 })];
const TREE_ONE = () => [row(10, null, 'business', 'SWEETS', 'ব্যবসা এক', 'Business One', { template_code: 'food_manufacturing', template_status: 'available' })];
const LOCS = () => [{ id: 1, code: 'main', name_bn: 'মেইন', name_en: 'Main', sort: 1, kind: 'showroom', status: 'live', is_active: true, org_unit_id: 10 },
  { id: 5, code: 'dlr_n', name_bn: 'উত্তর', name_en: 'North shop', sort: 5, kind: 'showroom', status: 'setting_up', is_active: true, org_unit_id: 21 }];
const TPLS = [{ code: 'food_manufacturing', name_bn: 'খাদ্য', name_en: 'Food manufacturing', status: 'available', modules: [], sort: 10 }, { code: 'dealership', name_bn: 'ডিলারশিপ', name_en: 'Dealership', status: 'not_implemented', modules: [], sort: 20 }];
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 1 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: fs.readFileSync(WEB + '/index.html', 'utf8') }));
    const data = C.mk(base, {}); const T = data.tables; T.locations = LOCS(); T.report_brand_map = []; T.business_templates = TPLS;
    const PF = { tree: o.tree, places: o.one ? [] : LOCS().filter((l) => l.id === 5).concat(LOCS().filter((l) => l.id === 1)), keys: {}, next: 100, nextLoc: 50, err: null, impact: o.impact || null };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__PF=${JSON.stringify(PF)};${o.owner === false ? "window.__OWNER=false;window.__PROFILE={id:'u2',staff_id:'mgr2',full_name:'Manager',status:'active',lang:'en'};" : ''}try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1600); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => { const s = document.getElementById('sheet'); const sh = s && s.querySelector('.sheet'); return document.documentElement.scrollWidth <= window.innerWidth + 1 && (!sh || sh.scrollWidth <= sh.clientWidth + 1); }), 'overflow ' + m);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const calls = (p, fn) => p.evaluate((f) => (window.__ACO || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const pick = (p, sel, v) => p.evaluate(([s, x]) => { const e = document.querySelector(s); e.value = x; e.dispatchEvent(new Event('change', { bubbles: true })); }, [sel, v]);

  // 1. owner: buttons on the business cards, the New business button
  let p = await open('#/organization', { tree: TREE_OWNER() });
  ok(await p.locator('#nb_open').count() === 1, 'owner sees New business');
  ok(await p.locator('[data-act=pl_add]').count() === 2 && await p.locator('[data-act=pl_list]').count() === 2, 'Add place + Places on each business card (not on the group / entity / branch)');
  await noOverflow(p, 'organization owner');

  // 2. add a place to business one: args, client key, appears for ITS business only
  ok(await p.evaluate(() => window.BOS.biz.multi() && window.BOS.biz.cur() === 10), 'two businesses, working business = first');
  await p.click('[data-act=pl_add][data-v="10"]'); await wait(p, 300);
  ok(await p.locator('#pl_br').count() === 0, 'a business without branch units has no branch picker');
  await p.selectOption('#pl_kind', 'godown'); await p.fill('#pl_nbn', 'নতুন গুদাম'); await p.fill('#pl_nen', 'New store'); await p.fill('#pl_code', 'store9');
  await noOverflow(p, 'add place sheet');
  await p.fill('#pl_code', 'Bad Code'); await p.click('[data-act=pl_save]'); await wait(p, 200);
  ok(/code is not valid/.test(await p.textContent('#pl_err')) && (await calls(p, 'business_place_create135')).length === 0, 'bad code stopped in the browser with a friendly text');
  await p.fill('#pl_code', 'store9'); await p.evaluate(() => { window.__PF.err = 'name_in_use'; }); await p.click('[data-act=pl_save]'); await wait(p, 400);
  ok(/already has a place with this name/.test(await p.textContent('#pl_err')), 'server code name_in_use shown as friendly text');
  await p.evaluate(() => { window.__PF.err = 'code_too_long'; }); await p.click('[data-act=pl_save]'); await wait(p, 400);
  ok(/code is too long/.test(await p.textContent('#pl_err')), 'code_too_long friendly');
  await p.evaluate(() => { window.__PF.err = 'weird 77'; }); await p.click('[data-act=pl_save]'); await wait(p, 400);
  ok(/weird 77/.test(await p.textContent('#pl_err')), 'unknown error raw');
  await p.evaluate(() => { window.__PF.err = null; }); await p.click('[data-act=pl_save]'); await wait(p, 900);
  let c = await calls(p, 'business_place_create135'); const last = c[c.length - 1];
  ok(c.length === 4 && last.p_business === 10 && last.p_kind === 'godown' && last.p_code === 'store9' && last.p_name_en === 'New store' && last.p_name_bn === 'নতুন গুদাম' && last.p_org_branch === null && last.p_client, 'create args (business, kind, code, names, no branch, client key)');
  ok(new Set(c.map((x) => x.p_client)).size === 1, 'the retries after errors reuse ONE client key (no second place)');
  ok(await p.evaluate(() => window.BOS.ENV.locs.some((l) => l.code === 'sweets_store9') && !window.BOS.ENV.locs.some((l) => l.id === 5)), 'the new place is in the pick-list of ITS business (B.ENV.locs); the other business place is not');
  ok(/Places · Business One/.test(await text(p)) && /sweets_store9/.test(await text(p)), 'the list sheet opens with the new place');
  await p.evaluate(() => window.BOS.biz.setCur(20)); await wait(p, 500);
  ok(await p.evaluate(() => !window.BOS.ENV.locs.some((l) => l.code === 'sweets_store9') && window.BOS.ENV.locs.some((l) => l.id === 5)), 'switching to the other business: its places only');
  await p.evaluate(() => window.BOS.biz.setCur(10)); await wait(p, 300);

  // 3. Places of business two (has a branch unit): branch picker, then Move
  await p.evaluate(() => document.querySelector('[data-act=closesheet]').click()); await wait(p, 200);
  await p.click('[data-act=pl_add][data-v="20"]'); await wait(p, 300);
  ok(await p.locator('#pl_br option').count() === 2, 'branch picker: the business + its branch');
  await p.selectOption('#pl_br', '21'); await p.fill('#pl_nbn', 'ডিলার'); await p.fill('#pl_nen', 'Dealer X'); await p.click('[data-act=pl_save]'); await wait(p, 900);
  c = await calls(p, 'business_place_create135'); ok(c[c.length - 1].p_org_branch === 21 && c[c.length - 1].p_business === 20 && c[c.length - 1].p_code === null, 'branch passed, empty code = null (server makes it)');
  ok(await p.locator('[data-act=pl_move]').count() === 2 && /North branch/.test(await text(p)), 'owner sees Move on each place; the branch is named');
  await p.locator('[data-act=pl_move]').first().click(); await wait(p, 300);
  ok(await p.locator('#mv_biz option').count() === 1, 'move target: the other business only');
  await p.fill('#mv_why', 'ab'); await p.click('[data-act=pl_check]'); await wait(p, 400);
  let t = await text(p); ok(/Items in stock: 2/.test(t) && /Transaction rows: 4/.test(t) && /transactions; tick the box/.test(t), 'dry-run impact shown with the transactions blocker');
  ok(await p.locator('#mv_force').count() === 1 && await p.locator('[data-act=pl_domove]').count() === 1, 'force tick + Move now');
  await noOverflow(p, 'move sheet');
  await p.click('[data-act=pl_domove]'); await wait(p, 300);
  ok(/at least 3 characters/.test(await p.textContent('#pl_err')) && (await calls(p, 'business_place_move135')).filter((x) => !x.p_dry).length === 0, 'reason too short is stopped in the browser');
  await p.fill('#mv_why', 'created in the wrong business'); await p.check('#mv_force'); await p.click('[data-act=pl_domove]'); await wait(p, 800);
  c = (await calls(p, 'business_place_move135')).filter((x) => !x.p_dry); ok(c.length === 1 && c[0].p_force === true && c[0].p_dry === false && c[0].p_business === 10 && c[0].p_reason === 'created in the wrong business' && c[0].p_client, 'move args (force, reason, client key)');
  // blockers
  await p.evaluate(() => { window.__PF.impact = { users: 2, blockers: ['place_has_users', 'place_has_transactions'], can_move: false }; });
  await p.locator('[data-act=pl_move]').first().click(); await wait(p, 300); await p.fill('#mv_why', 'try again please'); await p.click('[data-act=pl_check]'); await wait(p, 400);
  t = await text(p); ok(/People are assigned to this place/.test(t) && await p.locator('[data-act=pl_domove]').count() === 0 && await p.locator('#mv_force').count() === 0, 'people assigned: no Move button, no force tick');
  await p.close();

  // 4. the guided New business flow
  p = await open('#/organization', { tree: TREE_OWNER() });
  await p.click('#nb_open'); await wait(p, 300);
  t = await text(p); ok(/Step 1\/3/.test(t), 'step 1 shown');
  let opts = await p.locator('#nb_tpl option').allTextContents();
  ok(opts.some((x) => /Dealership · Not built yet/.test(x)) && opts.some((x) => /Food manufacturing · Available/.test(x)), 'templates show their honest status');
  ok(await p.locator('#nb_le option').count() >= 3, 'legal entity: new + existing ones');
  await noOverflow(p, 'wizard step 1');
  await p.click('[data-act=nb_next]'); await wait(p, 200); ok(/Enter a name/.test(await p.textContent('#pl_err')), 'name needed');
  await p.fill('#nb_bn', 'ডিলার নতুন'); await p.fill('#nb_en', 'New Dealer Co'); await p.fill('#nb_code', 'ndc'); await pick(p, '#nb_tpl', 'dealership'); await wait(p, 300);
  ok(await p.locator('#nb_ack').count() === 1 && /no screens of its own yet/.test(await text(p)), 'a not-built template asks for a tick, with the honest text');
  ok(await p.inputValue('#nb_code') === 'NDC' && await p.inputValue('#nb_en') === 'New Dealer Co', 'typed values survive the template change');
  await p.click('[data-act=nb_next]'); await wait(p, 200); ok(/no screens of its own yet|Step 1\/3/.test(await text(p)) && /Step 1\/3/.test(await text(p)), 'not ticked: stays on step 1');
  await p.check('#nb_ack'); await p.click('[data-act=nb_next]'); await wait(p, 300);
  t = await text(p); ok(/Step 2\/3/.test(t) && await p.locator('[data-row]').count() === 2, 'step 2: two places by default for a dealership');
  await noOverflow(p, 'wizard step 2');
  await p.click('[data-act=nb_run]'); await wait(p, 200); ok(/Enter a name/.test(await p.textContent('#pl_err')), 'places need names');
  await p.fill('#nb_pb0', 'শো-রুম এক'); await p.fill('#nb_pe0', 'Showroom One'); await p.selectOption('#nb_k1', 'godown'); await p.fill('#nb_pb1', 'গুদাম'); await p.fill('#nb_pe1', 'Warehouse');
  await p.click('[data-act=nb_addrow]'); await wait(p, 200); ok(await p.locator('[data-row]').count() === 3 && await p.inputValue('#nb_pe0') === 'Showroom One', 'add a third row keeps the typed values');
  await p.click('[data-act=nb_rm][data-v="2"]'); await wait(p, 200); ok(await p.locator('[data-row]').count() === 2, 'remove a row');
  await p.evaluate(() => { window.__PF.err = 'name_in_use'; });
  await p.click('[data-act=nb_run]'); await wait(p, 1200);
  t = await text(p); ok(/Step 3\/3/.test(t) && /Failed: 2/.test(t) && /already has a place with this name/.test(t), 'step 3 after a failure: the failed places are listed with friendly text');
  ok(await p.locator('[data-act=nb_run]').count() === 1 && await p.locator('#nb_todo').count() === 0, 'a retry button, no checklist yet');
  await p.evaluate(() => { window.__PF.err = null; });
  await p.click('[data-act=nb_run]'); await wait(p, 1500);
  t = await text(p); ok(await p.locator('#nb_todo').count() === 1 && !/Failed/.test(t), 'step 3: summary + the what-to-do-next checklist');
  const sv = await calls(p, 'org_unit_save'); const keys = sv.map((x) => x.p_client);
  const kinds = sv.map((x) => x.p_kind + ':' + x.p_code);
  ok(sv.length >= 8 && new Set(keys).size === 4 && kinds.filter((k) => k === 'legal_entity:LE-NDC').length === 2 && kinds.includes('business:NDC') && kinds.includes('branch:NDC-B1') && kinds.includes('branch:NDC-B2'), 'unit calls: legal entity, business, 2 branches; the retry re-sent the SAME 4 keys (nothing twice) ' + JSON.stringify(kinds));
  const biz = sv.find((x) => x.p_kind === 'business'); ok(biz.p_template === 'dealership' && biz.p_name_en === 'New Dealer Co', 'business saved with the chosen template and names');
  ok(await p.evaluate(() => window.__PF.tree.filter((r) => r.kind === 'business').length === 3 && window.__PF.tree.filter((r) => r.code === 'LE-NDC').length === 1), 'exactly one new legal entity and one new business exist');
  const pc = await calls(p, 'business_place_create135').then((a) => a.slice(-2)); ok(pc[0].p_kind === 'showroom' && pc[1].p_kind === 'godown' && pc[0].p_org_branch && pc[1].p_org_branch && pc[0].p_org_branch !== pc[1].p_org_branch, 'places created with their own branch units and kinds');
  ok(await p.evaluate(() => window.__PF.places.filter((x) => /^ndc_/.test(x.code)).length === 2), 'two places exist (no duplicates after the retry)');
  ok(/Set each place live/.test(t) && /org_scope_on/.test(t) && /Staff/.test(t), 'the checklist names the next steps (live, people, scope switch)');
  await noOverflow(p, 'wizard step 3'); await p.close();

  // 5. a manager of ONE business: Add place yes; New business / Move no
  p = await open('#/organization', { owner: false, tree: TREE_ONE(), one: true });
  ok(await p.locator('#nb_open').count() === 0, 'no New business for a non-owner');
  ok(await p.locator('[data-act=pl_add]').count() === 1, 'a manager can add a place to his business');
  await p.evaluate(() => { window.__PF.places.push({ id: 60, code: 'sweets_x', name_bn: 'ক', name_en: 'X place', kind: 'showroom', status: 'setting_up', is_active: true, org_unit_id: 10 }); });
  await p.click('[data-act=pl_list]'); await wait(p, 300);
  ok(/X place/.test(await text(p)) && await p.locator('[data-act=pl_move]').count() === 0, 'a manager sees the list but has no Move');
  await noOverflow(p, 'manager list'); await p.close();

  ok(!errors.length, 'no JS errors: ' + errors.slice(0, 3).join(' | '));
  console.log(bad ? 'PLACES135: ' + bad + ' FAILED' : 'PLACES135: ALL OK'); await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e); process.exit(2); } })();
