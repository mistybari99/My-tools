const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const R = (key, module, kind, def, bn, extra = {}) => ({ key, module, kind, value: null, default_value: def, label_bn: bn, label_en: bn, label_mix: bn, sort: 1, ...extra });
data.tables.rules = [R('fiscal_year_start_month', 'settings', 'number', null, 'fy'), R('fiscal_year_start_day', 'settings', 'number', null, 'fd'), R('week_start', 'settings', 'choice', null, 'ws'), R('vat_on', 'settings', 'switch', false, 'vat'), R('vat_rate', 'settings', 'number', null, 'vr'),
  R('barcode_camera_on', 'settings', 'switch', false, 'bc'), R('barcode_device_on', 'settings', 'switch', false, 'bd'), R('ui_noperm_mode', 'settings', 'choice', 'lock', 'np'), R('stock_negative_mode', 'settings', 'choice', 'warn', 'sn'), R('costing_method', 'settings', 'choice', 'avg', 'cm'),
  R('discount_mode_amount_on', 'pos', 'switch', true, 'da'), R('discount_mode_percent_on', 'pos', 'switch', true, 'dp')];
const items = data.tables.items; const I1 = items[0], I2 = items[1];
data.tables.unit_conversions = [{ id: 1, item_id: null, from_unit: 'kg', to_unit: 'gram', factor: 1000, active: true, note: null }];
data.tables.shelf_life_rules = [{ id: 11, item_id: null, category: null, season_label: null, start_month: null, start_day: null, end_month: null, end_day: null, value: 3, unit: 'days', active: true },
  { id: 12, item_id: I1.id, category: null, season_label: 'Winter', start_month: 11, start_day: 15, end_month: 2, end_day: 15, value: 5, unit: 'days', active: true }];
data.tables.suppliers = [{ id: 'sp1', name: 'Dudh Ghor', mobile: '01711111111', type_code: 'milk', credit_days: 7, opening_balance: null, active: true }];
data.tables.profiles = [{ id: 'u1', staff_id: 'owner1', full_name: 'Rahim Uddin', status: 'active' }, { id: 'u2', staff_id: 'karim02', full_name: 'Karim', status: 'active' }];
data.tables.user_grants = [{ id: 1, user_id: 'u2', grant_code: 'view_cost', location_id: null, valid_until: null, note: null }];
data.tables.roles = [{ code: 'owner', name_bn: 'মালিক', name_en: 'Owner', active: true, sort: 1 }, { code: 'showroom_manager', name_bn: 'শোরুম ম্যানেজার', name_en: 'Showroom manager', active: true, sort: 2 }];
data.tables.rule_grants = []; data.tables.grant_defs = [{ grant_code: 'view_cost', module: 'cost', sort: 20, label_bn: 'কস্ট', label_en: 'cost' }];
data.tables.role_favourites = []; data.tables.user_favourites = [];
data.tables.option_lists = [{ list_code: 'units', value_code: 'kg', label_bn: 'কেজি', sort: 1, active: true }, { list_code: 'units', value_code: 'gram', label_bn: 'গ্রাম', sort: 2, active: true }, { list_code: 'supplier_types', value_code: 'milk', label_bn: 'দুধ', label_en: 'Milk', sort: 1, active: true }];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8091);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = []; const T = window.__DATA.tables;
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]);
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'set_unit_conversion') { const u = T.unit_conversions; const i = u.findIndex((x) => (x.item_id || null) === (args.p_item || null) && x.from_unit === args.p_from && x.to_unit === args.p_to);
    if (args.p_factor === null) { if (i >= 0) u.splice(i, 1); } else if (i >= 0) u[i].factor = args.p_factor; else u.push({ id: 100 + u.length, item_id: args.p_item, from_unit: args.p_from, to_unit: args.p_to, factor: args.p_factor, active: true, note: args.p_note }); return { data: null, error: null }; }
  if (fn === 'save_supplier') { const s = T.suppliers; if (args.p_id) Object.assign(s.find((x) => x.id === args.p_id), args.p_patch); else s.push({ id: 'sp' + (s.length + 1), ...args.p_patch }); return { data: 'x', error: null }; }
  if (fn === 'set_user_grant') { const g = T.user_grants; if (args.p_allowed) g.push({ id: 50 + g.length, user_id: args.p_user, grant_code: args.p_code, location_id: args.p_loc, valid_until: args.p_until, note: args.p_note }); else { const i = g.findIndex((x) => x.user_id === args.p_user && x.grant_code === args.p_code && (x.location_id || null) === (args.p_loc || null)); if (i >= 0) g.splice(i, 1); } return { data: null, error: null }; }
  if (fn === 'set_grant') { const g = T.rule_grants; const i = g.findIndex((x) => x.grant_code === args.p_code && x.role_code === args.p_role); if (i >= 0) g[i].allowed = args.p_allowed; else g.push({ grant_code: args.p_code, role_code: args.p_role, allowed: args.p_allowed }); return { data: null, error: null }; }
  if (fn === 'shelf_life_for') { const md = +args.p_date.slice(5, 7) * 100 + +args.p_date.slice(8, 10); const win = md >= 1115 || md <= 215; if (args.p_item === T.shelf_life_rules[1].item_id && win) return { data: { rule_id: 12, scope: 'item', season: 'Winter', value: 5, unit: 'days', hours: 120 }, error: null }; return { data: { rule_id: 11, scope: 'all', season: null, value: 3, unit: 'days', hours: 72 }, error: null }; }
  if (fn === 'has_grant') return { data: true, error: null };
  return rpc(fn, args); }; return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  p.on('dialog', (d) => d.accept());
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{if(!localStorage.getItem('bos_lang'))localStorage.setItem('bos_lang','en');}catch(e){}`);
  const calls = (fn) => p.evaluate((f) => window.__CALLS.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const go = async (h) => { await p.evaluate((x) => { location.hash = x; }, h); await p.waitForTimeout(450); };
  const noOverflow = async (m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  await p.goto('http://localhost:8091/#/settings2'); await p.waitForTimeout(900);
  log('hub cards:', await p.locator('.s2card').count()); ok(await p.locator('.s2card').count() === 14, 'hub has 14 cards'); await p.screenshot({ path: SP + '/z_hub.png', fullPage: true }); await noOverflow('hub');
  // drawer entry
  await p.click('.hbtn[data-act=nav_open]'); await p.waitForTimeout(400);
  log('drawer has settings2 + invoice:', await p.locator('#navDrawer [data-act=nav_go][data-v=settings2]').count(), await p.locator('#navDrawer [data-act=nav_go][data-v=invoice]').count()); await p.keyboard.press('Escape'); await p.waitForTimeout(300);
  // fiscal
  await go('#/settings2/fiscal'); await p.selectOption('#fy_m', '7'); await p.fill('#fy_d', '1'); log('fiscal preview:', (await p.textContent('#fy_prev')).trim());
  await p.click('[data-act=s2_fy_save]'); await p.waitForTimeout(500);
  const sr = await calls('set_rule'); log('fiscal rules:', JSON.stringify(sr.map((c) => [c.p_key, c.p_value])));
  ok(sr.some((c) => c.p_key === 'fiscal_year_start_month' && c.p_value === 7) && sr.some((c) => c.p_key === 'fiscal_year_start_day' && c.p_value === 1), 'fiscal saved');
  await p.fill('#fy_d', '40'); await p.click('[data-act=s2_fy_save]'); ok(/not valid/.test(await p.textContent('#toast')), 'bad day refused');
  await p.click('[data-act=s2_wk][data-v=sun]'); await p.waitForTimeout(400); ok((await calls('set_rule')).some((c) => c.p_key === 'week_start' && c.p_value === 'sun'), 'week start saved'); await p.screenshot({ path: SP + '/z_fiscal.png', fullPage: true }); await noOverflow('fiscal');
  // vat
  await go('#/settings2/vat'); await p.click('[data-act=s2_sw][data-k=vat_on]'); await p.waitForTimeout(400); ok((await calls('set_rule')).some((c) => c.p_key === 'vat_on' && c.p_value === true), 'vat on');
  await p.fill('#vat_rate', '7.5'); await p.click('[data-act=s2_num_step][data-k=vat_rate]:nth-of-type(2)').catch(() => {}); await p.fill('#vat_rate', '7.5'); await p.click('[data-act=s2_num_save]'); await p.waitForTimeout(400);
  ok((await calls('set_rule')).some((c) => c.p_key === 'vat_rate' && c.p_value === 7.5), 'vat rate'); await p.fill('#vat_rate', '150'); await p.click('[data-act=s2_num_save]'); ok(/not valid/.test(await p.textContent('#toast')), 'vat >100 refused'); await p.screenshot({ path: SP + '/z_vat.png' });
  // barcode: separate
  await go('#/settings2/barcode'); await p.click('[data-act=s2_sw][data-k=barcode_camera_on]'); await p.waitForTimeout(400);
  const bc = (await calls('set_rule')).filter((c) => /barcode/.test(c.p_key)); ok(bc.length === 1 && bc[0].p_key === 'barcode_camera_on' && bc[0].p_value === true, 'camera only'); ok(await p.evaluate(() => window.BOS.rule('barcode_device_on', false)) === false, 'device untouched');
  await p.click('[data-act=s2_sw][data-k=barcode_device_on]'); await p.waitForTimeout(400); ok(await p.evaluate(() => window.BOS.rule('barcode_device_on', false)) === true && await p.evaluate(() => window.BOS.rule('barcode_camera_on', false)) === true, 'both on separately');
  // noperm + stock + disc
  await go('#/settings2/noperm'); await p.click('[data-act=s2_choice][data-v=hide]'); await p.waitForTimeout(400); ok(await p.evaluate(() => window.BOS.rule('ui_noperm_mode', 'lock')) === 'hide', 'noperm hide');
  await go('#/settings2/stock'); await p.click('[data-act=s2_choice][data-v=block]'); await p.waitForTimeout(400); ok(await p.evaluate(() => window.BOS.rule('stock_negative_mode', 'warn')) === 'block', 'stock block');
  await go('#/settings2/disc'); await p.click('[data-act=s2_sw][data-k=discount_mode_percent_on]'); await p.waitForTimeout(400); ok(await p.evaluate(() => window.BOS.rule('discount_mode_percent_on', true)) === false, 'percent off'); await p.click('[data-act=s2_sw][data-k=discount_mode_percent_on]'); await p.waitForTimeout(400);
  ok(await p.evaluate(() => window.BOS.rule('discount_mode_percent_on', true)) === true, 'percent back on');
  // units
  await go('#/settings2/units'); log('unit rows:', await p.locator('.s2conv').count());
  await p.click('[data-act=s2_cv_step][data-d="1"]'); await p.waitForTimeout(400); let uc = await calls('set_unit_conversion'); ok(uc.length === 1 && uc[0].p_factor === 1010, 'increase factor ' + JSON.stringify(uc.map((c) => c.p_factor)));
  await p.click('[data-act=s2_cv_step][data-d="-1"]'); await p.waitForTimeout(400);
  await p.fill('#cv_from', 'box'); await p.fill('#cv_to', 'piece'); await p.fill('#cv_fac', '12'); await p.click('[data-act=s2_cv_add]'); await p.waitForTimeout(400); ok(await p.locator('.s2conv').count() === 2, 'added global rule');
  await p.selectOption('#u_scope', I1.id); await p.waitForTimeout(300); ok(await p.locator('.s2conv').count() === 0, 'per item scope empty -> data needed'); log('empty note:', (await p.textContent('.notice.warn')).trim().slice(0, 40));
  await p.fill('#cv_from', 'pack'); await p.fill('#cv_to', 'piece'); await p.fill('#cv_fac', '6'); await p.click('[data-act=s2_cv_add]'); await p.waitForTimeout(400);
  uc = await calls('set_unit_conversion'); ok(uc[uc.length - 1].p_item === I1.id, 'per item p_item'); await p.screenshot({ path: SP + '/z_units.png', fullPage: true }); await noOverflow('units');
  await p.click('[data-act=s2_cv_del]'); await p.waitForTimeout(400); uc = await calls('set_unit_conversion'); ok(uc[uc.length - 1].p_factor === null, 'remove sends null');
  // shelf
  await go('#/settings2/shelf'); log('shelf cards:', await p.locator('[id^=sh_]:not([id^=sh_t])').count()); 
  await p.selectOption('#sh_t_item', I1.id); await p.fill('#sh_t_date', '2027-01-10'); await p.click('[data-act=s2_sh_test]'); await p.waitForTimeout(300); const o1 = (await p.textContent('#sh_t_out')).trim(); log('winter:', o1); ok(/#12/.test(o1) && /Winter/.test(o1), 'winter rule');
  await p.fill('#sh_t_date', '2026-07-10'); await p.click('[data-act=s2_sh_test]'); await p.waitForTimeout(300); const o2 = (await p.textContent('#sh_t_out')).trim(); log('summer:', o2); ok(/#11/.test(o2), 'general rule');
  await p.click('[data-act=s2_sh_step][data-id="11"][data-d="1"]'); await p.waitForTimeout(300); ok((await p.textContent('#sh_11')).includes('4 days'), 'increase shelf value');
  await p.click('[data-act=s2_sh_new]'); await p.selectOption('#sh_scope', 'cat'); await p.waitForTimeout(100); await p.fill('#sh_val', '36'); await p.selectOption('#sh_unit', 'hours'); await p.click('#sh_year'); await p.fill('#sh_s_d', '1'); await p.selectOption('#sh_cat', { index: 1 }).catch(() => {}); await p.screenshot({ path: SP + '/z_shelf_sheet.png' });
  await p.click('[data-act=s2_sh_save]'); await p.waitForTimeout(500); log('shelf rules in data:', await p.evaluate(() => window.__DATA.tables.shelf_life_rules.length));
  await p.screenshot({ path: SP + '/z_shelf.png', fullPage: true }); await noOverflow('shelf');
  // suppliers
  await go('#/settings2/suppliers'); ok(await p.locator('#su_list .card').count() === 1, 'supplier listed'); log('supplier data-needed chip:', await p.locator('#su_list .chip.warn').count());
  await p.click('[data-act=s2_su_new]'); await p.click('[data-act=s2_su_save]'); ok(/name/i.test(await p.textContent('#toast')), 'name required');
  await p.fill('#su_name', 'Chini Bhandar'); await p.fill('#su_mobile', '01922222222'); await p.fill('#su_credit', '15'); await p.fill('#su_open', '2500'); await p.click('[data-act=s2_su_save]'); await p.waitForTimeout(500);
  const ss = await calls('save_supplier'); ok(ss.length === 1 && ss[0].p_id === null && ss[0].p_patch.credit_days === 15, 'save_supplier new'); ok(await p.locator('#su_list .card').count() === 2, 'two suppliers');
  await p.click('#su_list .card >> nth=0'); await p.fill('#su_note', 'good'); await p.click('[data-act=s2_su_save]'); await p.waitForTimeout(400); ok((await calls('save_supplier'))[1].p_id !== null, 'save_supplier edit'); await p.screenshot({ path: SP + '/z_sup.png', fullPage: true }); await noOverflow('suppliers');
  // access
  await go('#/settings2/access'); await p.selectOption('#ac_user', 'u2'); await p.waitForTimeout(200); log('u2 existing chips:', await p.locator('[data-act=s2_ac_del]').count());
  await p.click('[data-act=s2_ac_give][data-g=view_profit]'); await p.selectOption('#ac_loc', { index: 1 }); await p.fill('#ac_until', '2026-12-31'); await p.click('[data-act=s2_ac_save]'); await p.waitForTimeout(500);
  const ug = await calls('set_user_grant'); log('give:', JSON.stringify(ug[0])); ok(ug[0].p_code === 'view_profit' && ug[0].p_user === 'u2' && ug[0].p_loc !== null && /2026-12-31/.test(ug[0].p_until), 'user grant with loc + expiry');
  await p.click('[data-act=s2_ac_give][data-g=salary_view]'); await p.fill('#ac_until', '2026-02-30'); await p.click('[data-act=s2_ac_save]'); ok(/YYYY/.test(await p.textContent('#toast')), 'bad date'); await p.click('[data-act=closesheet]');
  await p.click('[data-act=s2_ac_del] >> nth=0'); await p.waitForTimeout(400); ok((await calls('set_user_grant')).some((c) => c.p_allowed === false), 'remove grant');
  await p.screenshot({ path: SP + '/z_access.png', fullPage: true });
  await p.click('[data-act=s2_ac_tab][data-v=role]'); await p.click('[data-act=s2_ac_role][data-g=view_reports]'); await p.waitForTimeout(400); ok((await calls('set_grant')).some((c) => c.p_code === 'view_reports' && c.p_role === 'showroom_manager' && c.p_allowed === true), 'role grant');
  await p.click('[data-act=s2_ac_tab][data-v=over]'); await p.waitForTimeout(200); log('overview cards:', await p.locator('#s2_body .card').count()); await noOverflow('access');
  // role favourites
  await go('#/settings2/fav'); await p.selectOption('#rf_new', 'r:pos'); await p.click('[data-act=s2_rf_add]'); await p.waitForTimeout(400);
  await p.selectOption('#rf_new', 'r:dues'); await p.click('[data-act=s2_rf_add]'); await p.waitForTimeout(400); log('role fav rows:', await p.evaluate(() => JSON.stringify(window.__DATA.tables.role_favourites.map((x) => x.key + ':' + x.sort))));
  await p.click('[data-act=s2_rf_move][data-d="-1"] >> nth=1'); await p.waitForTimeout(400); log('after move:', await p.evaluate(() => JSON.stringify(window.__DATA.tables.role_favourites.map((x) => x.key + ':' + x.sort))));
  await p.click('[data-act=s2_rf_del] >> nth=0'); await p.waitForTimeout(400); ok(await p.evaluate(() => window.__DATA.tables.role_favourites.length) === 1, 'fav removed'); await p.screenshot({ path: SP + '/z_fav.png', fullPage: true });
  // 3 modes
  for (const m of ['bn', 'mix']) { await p.evaluate((x) => localStorage.setItem('bos_lang', x), m); await go('#/settings2'); await p.reload(); await p.waitForTimeout(900); const tx = (await p.locator('.s2card .nm').allTextContents()).slice(0, 4).join(' | '); log(m + ':', tx); await p.screenshot({ path: SP + '/z_hub_' + m + '.png' }); }
  // non-owner gate
  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
})();
