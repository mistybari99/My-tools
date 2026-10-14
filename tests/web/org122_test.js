// Organization tree page #/organization (web/org122.js): tree + badges, create / rename / deactivate sheets, validation, server error text, empty state, non-owner blocked.
// Run: node org122_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const O = window.__ORG;
 const clone = (x) => JSON.parse(JSON.stringify(x));
 const build = (pid) => O.units.filter((u) => (u.parent_id || null) === pid).map((u) => Object.assign(clone(u), { children: build(u.id) }));
 c.rpc = async (fn, args) => {
  (window.__ACO = window.__ACO || []).push([fn, clone(args || {})]);
  if (fn === 'has_grant') return { data: !!O.grant, error: null };
  if (fn === 'org_tree') return { data: build(null), error: null };
  if (fn === 'org_unit_save') { if (O.err) { const m = O.err; O.err = null; return { data: null, error: { message: m, code: 'P0001' } }; }
    if (args.p_id) { const u = O.units.find((x) => x.id === args.p_id); Object.assign(u, { code: args.p_code, name_bn: args.p_name_bn, name_en: args.p_name_en, template_code: args.p_template }); return { data: { id: u.id }, error: null }; }
    const id = 100 + O.units.length; O.units.push({ id, parent_id: args.p_parent, kind: args.p_kind, code: args.p_code, name_bn: args.p_name_bn, name_en: args.p_name_en, template_code: args.p_template, status: 'active', attrs: args.p_attrs }); return { data: { id }, error: null }; }
  if (fn === 'org_unit_deactivate') { if (O.err) { const m = O.err; O.err = null; return { data: null, error: { message: m, code: 'P0001' } }; } const u = O.units.find((x) => x.id === args.p_id); u.status = 'inactive'; return { data: { id: u.id }, error: null }; }
  return rpc(fn, args);
 }; return c; }; })();`;
const units = (o) => o.empty ? [] : [
  { id: 1, parent_id: null, kind: 'group', code: 'GRP', name_bn: 'গ্রুপ <b>x</b>', name_en: 'Main <b>group</b>', status: 'active', attrs: {} },
  { id: 2, parent_id: 1, kind: 'business', code: 'BIZ1', name_bn: 'ব্যবসা এক', name_en: 'Business One', template_code: 'tpl_ok', status: 'active', attrs: {} },
  { id: 3, parent_id: 1, kind: 'business', code: 'BIZ2', name_bn: 'ব্যবসা দুই', name_en: 'Business Two', template_code: 'tpl_no', status: 'active', attrs: {} },
  { id: 4, parent_id: 2, kind: 'branch', code: 'BR1', name_bn: 'শাখা', name_en: 'A very long branch name that must wrap inside a narrow phone screen without any sideways scrolling at all', status: 'active', attrs: { k: 1 } },
  { id: 5, parent_id: 4, kind: 'site', code: 'ST1', name_bn: 'সাইট', name_en: 'Site', status: 'inactive', attrs: {} },
  { id: 6, parent_id: null, kind: 'legal_entity', code: 'LE1', name_bn: 'প্রতিষ্ঠান', name_en: 'Entity', status: 'active', attrs: {}, legal_entity: { trade_licence_ref: 'TL-77', owner_pct: 60, fiscal_start: '07-01', base_currency: 'BDT' } }];
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: ((h) => (/org122\.js/.test(h) ? h : h.replace('<script src="cashmoves.js"></script>', '<script src="cashmoves.js"></script><script src="org122.js"></script>')))(fs.readFileSync(WEB + '/index.html', 'utf8')) }));
    const data = C.mk(base, {}); const T = data.tables;
    T.business_templates = [{ code: 'tpl_ok', name: 'Ready Template', status: 'available' }, { code: 'tpl_set', name: 'Setup Template', status: 'needs_setup' }, { code: 'tpl_no', name: 'Unbuilt Template', status: 'not_implemented' }, { code: 'tpl_plan', name: 'Planned Template', status: 'planned' }];
    const ORG = { units: units(o), grant: !!o.grant };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__ORG=${JSON.stringify(ORG)};${o.owner === false ? "window.__OWNER=false;window.__PROFILE={id:'u2',staff_id:'mgr2',full_name:'Manager',status:'active',lang:'en'};" : ''}try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__ACO || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  let p = await open('#/organization');
  let t = await text(p);
  ok(await p.locator('.og-node').count() === 6, 'six nodes drawn');
  ok(/Group/.test(t) && /Business/.test(t) && /Branch/.test(t) && /Legal entity/.test(t), 'kind badges');
  ok(!(await p.locator('#og_body b >> text=x').count()) && /Main <b>group<\/b>/.test(t), 'names escaped, not injected as HTML');
  ok(/Ready Template · Available/.test(t), 'available template badge');
  ok(/Unbuilt Template · Not built yet/.test(t) && !/Unbuilt Template · (Available|Configured)/.test(t) && /not built yet, so it is not live/.test(t), 'not_implemented template never called ready');
  ok(/TL-77/.test(t) && /Owner %: 60/.test(t), 'legal entity facts shown');
  ok(await p.locator('.og-node[data-id="5"] .chip', { hasText: 'Inactive' }).count() === 1 && await p.locator('.og-node[data-id="5"] [data-act=og_off]').count() === 0, 'inactive unit marked, no actions');
  await noOverflow(p, 'tree'); 
  const small = await p.evaluate(() => [...document.querySelectorAll('#og_body button')].filter((b) => b.getBoundingClientRect().height < 39.5).length); ok(small === 0, 'all taps at least 40px');
  await p.screenshot({ path: SP + '/org_tree.png', fullPage: true });

  // create under business 2
  await p.click('.og-node[data-id="2"] [data-act=og_add]'); await wait(p, 200);
  ok(await p.locator('#og_kind option').allTextContents().then((a) => a.includes('Branch') && a.includes('Cost centre') && !a.includes('Group')), 'child kinds limited by parent');
  await p.click('[data-act=og_save]'); await wait(p, 100); ok(/Enter a code/.test(await p.textContent('#og_err')) && !(await calls(p, 'org_unit_save')).length, 'code validation, no call');
  await p.fill('#og_code', 'NEW1'); await p.click('[data-act=og_save]'); await wait(p, 100); ok(/Enter a name/.test(await p.textContent('#og_err')), 'name validation');
  await p.fill('#og_nen', 'New Branch'); await p.evaluate(() => { document.getElementById('og_from').value = ''; });
  await p.evaluate(() => { window.__ORG.err = 'code_duplicate'; }); await p.click('[data-act=og_save]'); await wait(p, 300);
  ok(/already used/.test(await p.textContent('#og_err')) && await p.locator('#og_form').count() === 1, 'known server code shown friendly, sheet stays');
  await p.evaluate(() => { window.__ORG.err = 'weird_server_text 42'; }); await p.click('[data-act=og_save]'); await wait(p, 300);
  ok(/weird_server_text 42/.test(await p.textContent('#og_err')), 'unknown server message shown raw');
  await p.click('[data-act=og_save]'); await wait(p, 600);
  let c = await calls(p, 'org_unit_save'); const last = c[c.length - 1];
  ok(c.length === 3 && last.p_parent === 2 && last.p_kind === 'branch' && last.p_code === 'NEW1' && last.p_name_en === 'New Branch' && last.p_id === null && last.p_client && last.p_template === null, 'create sends correct args with client id');
  ok(/New Branch/.test(await text(p)) && await p.locator('#sheet').count() === 0, 'new unit listed, sheet closed');
  // business create with template: not_implemented option disabled
  await p.click('.og-node[data-id="1"] [data-act=og_add]'); await wait(p, 200);
  await p.selectOption('#og_kind', 'business'); await wait(p, 100);
  ok(await p.locator('#og_tplw').isVisible() && await p.locator('#og_tpl option[value=tpl_no]').isDisabled(), 'template picker shown for business, unbuilt one disabled');
  await p.keyboard.press('Escape'); await p.click('[data-act=closesheet]').catch(() => {});
  // rename
  await p.click('.og-node[data-id="2"] [data-act=og_edit]'); await wait(p, 200);
  ok(await p.inputValue('#og_code') === 'BIZ1' && await p.locator('#og_kind').isDisabled(), 'rename prefilled, kind locked');
  await p.fill('#og_nen', 'Renamed One'); await p.click('[data-act=og_save]'); await wait(p, 600);
  c = await calls(p, 'org_unit_save'); const rn = c[c.length - 1]; ok(rn.p_id === 2 && rn.p_parent === 1 && rn.p_name_en === 'Renamed One' && rn.p_template === 'tpl_ok', 'rename keeps id, parent, template');
  ok(/Renamed One/.test(await text(p)), 'renamed shown');
  // deactivate
  await p.click('.og-node[data-id="4"] [data-act=og_off]'); await wait(p, 200);
  await p.click('[data-act=og_offgo]'); await wait(p, 100); ok(/at least 3/.test(await p.textContent('#og_err')) && !(await calls(p, 'org_unit_deactivate')).length, 'reason required');
  await p.fill('#og_why', 'closed down'); await p.evaluate(() => { window.__ORG.err = 'has_active_children'; }); await p.click('[data-act=og_offgo]'); await wait(p, 300);
  ok(/still has active units/.test(await p.textContent('#og_err')), 'deactivate error friendly');
  await p.click('[data-act=og_offgo]'); await wait(p, 600);
  c = await calls(p, 'org_unit_deactivate'); ok(c.length === 2 && c[1].p_id === 4 && c[1].p_reason === 'closed down', 'deactivate sent with reason');
  ok(await p.locator('.og-node[data-id="4"] > .card .chip', { hasText: 'Inactive' }).count() === 1, 'unit now inactive');
  await noOverflow(p, 'after edits');

  // empty state
  p = await open('#/organization', { empty: true });
  ok(await p.locator('#og_empty').count() === 1 && /No organization added yet/.test(await text(p)) && await p.locator('[data-act=og_add]').count() === 1, 'empty state with add button');
  await p.click('[data-act=og_add]'); await wait(p, 200); ok(await p.locator('#og_kind option').count() === 3, 'root kinds: group / legal entity / business'); await noOverflow(p, 'empty + sheet');

  // non-owner
  p = await open('#/organization', { owner: false });
  ok(await p.locator('#og_noperm').count() === 1 && !(await calls(p, 'org_tree')).length && await p.locator('[data-act=og_add]').count() === 0, 'non-owner blocked, tree never fetched');
  p = await open('#/organization', { owner: false, grant: true });
  ok(await p.locator('.og-node').count() === 6, 'grant org_manage opens the page');

  // Bangla mode renders
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
