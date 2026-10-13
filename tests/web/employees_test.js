// Module B1: employees list, registration wizard, profile (pay hidden without the salary right), deeds, print, friendly errors.
// Run: timeout 250 node employees_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const ROOT = '/home/user/My-tools/web';
const base = C.baseData(SP), PORT = 8441;
// the lead adds <script src="employees.js"> to index.html (docs/regs/employees.md); the test injects it so it does not depend on that edit
const srv = http.createServer((q, r) => {
  const u = q.url.split('?')[0]; const f = path.join(ROOT, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
    if (ext === '.html' && !/employees\.js/.test(String(b))) b = Buffer.from(String(b).replace('</body>', '<script src="employees.js"></script></body>'));
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

const EXTRA41 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)); const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
 const mgr = () => window.__NOMANAGE ? false : true;
 const calc = (basic, comps) => { let al = 0, de = 0; const lines = comps.map((x) => { const v = x.amount != null ? x.amount : Math.round(basic * x.percent_of_basic) / 100; if (x.kind === 'allowance') al += v; else de += v; return Object.assign({}, x, { calc: v }); }); return { components: lines, allowances: al, deductions: de, gross: basic + al, net: basic + al - de }; };
 c.rpc = async (fn, args) => {
  (window.__AC41 = window.__AC41 || []).push([fn, clone(args || {})]);
  const E = window.__ERR41 && window.__ERR41[fn]; if (E) { delete window.__ERR41[fn]; return { data: null, error: { message: E, code: 'P0001' } }; }
  if (fn === 'employee_save') { const d = args.p_data || {}; let e = args.p_id && T.employees.find((x) => x.id === args.p_id);
    if (!e) { e = { id: 'n' + (T.employees.length + 1), employee_no: null, status: 'draft', employment_type: 'permanent', primary_location_id: null }; T.employees.push(e); }
    Object.assign(e, d); return { data: { id: e.id, employee_no: e.employee_no, status: e.status, warnings: window.__WARN41 || {} }, error: null }; }
  if (fn === 'employee_dup_check') return { data: { nid: args.p_nid === '1990123456789' ? [{ id: 'e1', employee_no: 'E-0001', name: 'আব্দুল করিম', status: 'active' }] : [], mobile: [], mobile_blocks: true }, error: null };
  if (fn === 'employee_submit') { const e = T.employees.find((x) => x.id === args.p_id); e.status = 'active'; e.employee_no = e.employee_no || 'E-0009'; return { data: { id: e.id, employee_no: e.employee_no, status: 'active' }, error: null }; }
  if (fn === 'employee_locations_set') return { data: { id: args.p_id }, error: null };
  if (fn === 'employee_set_photo') { const e = T.employees.find((x) => x.id === args.p_id); e.photo_path = args.p_path; return { data: { photo_path: args.p_path }, error: null }; }
  if (fn === 'employee_doc_add') { T.employee_documents.push({ id: T.employee_documents.length + 1, employee_id: args.p_id, kind: args.p_kind, file_path: args.p_path, note: args.p_note, void: false, uploaded_at: '2026-10-13T00:00:00Z' }); return { data: { id: 1 }, error: null }; }
  if (fn === 'employee_doc_void') { const d = T.employee_documents.find((x) => x.id === args.p_doc); if (d) d.void = true; return { data: { id: args.p_doc }, error: null }; }
  if (fn === 'employee_status_set') { const e = T.employees.find((x) => x.id === args.p_id); e.status = args.p_status; return { data: { status: args.p_status }, error: null }; }
  if (fn === 'employee_link_profile') { const e = T.employees.find((x) => x.id === args.p_id); e.profile_id = args.p_profile; return { data: { id: e.id }, error: null }; }
  if (fn === 'leave_entitlement_set') return { data: { leave_type: args.p_type }, error: null };
  if (fn === 'employee_benefit_save') return { data: { id: 77 }, error: null };
  if (fn === 'employee_benefit_end') return { data: { id: args.p_id }, error: null };
  if (fn === 'employee_benefits_list') return { data: window.__SALARY === false ? [{ id: 1, kind: 'meal', description: 'Lunch', from_date: '2026-08-01', to_date: null, active: true, value_per_month: null }] : [{ id: 1, kind: 'meal', description: 'Lunch', from_date: '2026-08-01', to_date: null, active: true, value_per_month: 1200 }], error: null };
  if (fn === 'employee_pay_set') { const r = calc(args.p_basic, args.p_components); if (args.p_dry) return { data: Object.assign({ dry: true, basic: args.p_basic }, r), error: null }; T.pay_saved = (T.pay_saved || 0) + 1; return { data: Object.assign({ pay_id: 1, basic: args.p_basic }, r), error: null }; }
  if (fn === 'employee_pay_current') { if (window.__SALARY === false) return { data: null, error: { message: 'not allowed', code: 'P0001' } }; return { data: Object.assign({ pay_id: 1, effective_from: '2026-08-01', pay_basis: 'monthly', basic: 25000, ot_rule: 'multiple_of_hourly', ot_value: 1.5, bonus_rules: [{ name: 'Eid', months_of_basic: 1, min_service_months: 6 }] }, calc(25000, [{ kind: 'allowance', name: 'House rent', percent_of_basic: 40 }, { kind: 'deduction', name: 'Provident fund', amount: 1000 }])), error: null }; }
  if (fn === 'employee_pay_history') return { data: [{ effective_from: '2026-08-01', basic: 25000, net: 34000 }, { effective_from: '2026-01-01', basic: 20000, net: 27000 }], error: null };
  if (fn === 'employee_pay_account_get') return { data: { bank_account: 'DBBL 123', mobile_wallet: '01711000001' }, error: null };
  if (fn === 'deeds_expiring') return { data: [{ deed_id: 5, employee_id: 'e1', employee_no: 'E-0001', full_name_bn: 'আব্দুল করিম', role_code: 'cashier', title: 'Cashier deed', end_date: '2026-10-20', days_left: 7 }], error: null };
  if (fn === 'deed_template_save') { const id = T.deed_templates.length + 10; T.deed_templates.push({ id, family_id: args.p_family || id, version: 1, role_code: args.p_role, title_bn: args.p_title_bn, title_en: args.p_title_en, clauses: args.p_clauses, active: true }); return { data: { id }, error: null }; }
  if (fn === 'deed_template_retire') return { data: {}, error: null };
  if (fn === 'deed_save') { const id = args.p_id || T.employee_deeds.length + 20; T.employee_deeds.push({ id, employee_id: args.p_emp, role_code: args.p_role, title: args.p_title, clauses: args.p_clauses || [], status: 'draft', revision_no: 1 }); return { data: { id, status: 'draft', revision_no: 1 }, error: null }; }
  if (fn === 'deed_activate') { const d = T.employee_deeds.find((x) => x.id === args.p_id); if (d) d.status = 'active'; return { data: { status: 'active' }, error: null }; }
  if (fn === 'deed_revise') { T.employee_deeds.push({ id: 31, employee_id: 'e1', role_code: 'cashier', title: 'Cashier deed', clauses: [{ no: 1, kind: 'text', text_en: 'Rule one' }], status: 'draft', revision_no: 2, supersedes_id: args.p_id }); return { data: { id: 31, revision_no: 2 }, error: null }; }
  if (fn === 'deed_end') { const d = T.employee_deeds.find((x) => x.id === args.p_id); if (d) d.status = 'terminated'; return { data: {}, error: null }; }
  return rpc(fn, args);
 }; return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept('typed by mistake')); await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA41 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const T = data.tables;
    T.staff_roles = [['manager', 'ম্যানেজার', 'Manager', true], ['cashier', 'ক্যাশিয়ার', 'Cashier', true], ['storekeeper', 'স্টোরকিপার', 'Storekeeper', true], ['helper', 'হেল্পার', 'Helper', false]].map((r, i) => ({ code: r[0], name_bn: r[1], name_en: r[2], major: r[3], active: true, sort: i + 1 }));
    T.leave_types = [['annual', 'বার্ষিক ছুটি', 'Annual leave', 0], ['sick', 'অসুস্থতার ছুটি', 'Sick leave', 14], ['casual', 'নৈমিত্তিক ছুটি', 'Casual leave', 10]].map((r, i) => ({ code: r[0], name_bn: r[1], name_en: r[2], paid: true, default_days: r[3], active: true, sort: i + 1 }));
    T.option_lists = (T.option_lists || []).concat([['emp_designation', 'cashier', 'ক্যাশিয়ার', 'Cashier'], ['emp_designation', 'salesperson', 'সেলসম্যান', 'Salesperson'], ['emp_department', 'showroom', 'শোরুম', 'Showroom']].map((r, i) => ({ list_code: r[0], value_code: r[1], label_bn: r[2], label_en: r[3], sort: i + 1, active: true })));
    T.employees = [
      { id: 'e1', employee_no: 'E-0001', full_name_bn: 'আব্দুল করিম', full_name_en: 'Abdul Karim', mobile: '01711000001', nid_no: '1990123456789', designation: 'cashier', department: 'showroom', primary_location_id: 1, primary_role_code: 'cashier', employment_type: 'permanent', status: 'active', joining_date: '2026-01-05', photo_path: 'EMP/1/a.jpg', profile_id: null },
      { id: 'e2', employee_no: 'E-0002', full_name_bn: 'সালমা বেগম', full_name_en: 'Salma Begum', mobile: '01811000002', nid_no: '19901234567890123', designation: 'salesperson', primary_location_id: 2, primary_role_code: 'helper', employment_type: 'contract', status: 'on_leave', joining_date: '2026-02-01' },
      { id: 'e3', employee_no: 'E-0003', full_name_bn: 'রফিক', mobile: '01911000003', primary_location_id: 1, employment_type: 'daily', status: 'resigned', joining_date: '2025-05-01' },
      { id: 'e4', employee_no: null, full_name_bn: 'খসড়া ব্যক্তি', primary_location_id: 1, employment_type: 'permanent', status: 'draft' }];
    T.employee_documents = [{ id: 1, employee_id: 'e1', kind: 'nid', file_path: 'EMPDOC/1/n.jpg', note: 'front', void: false, uploaded_at: '2026-10-01T00:00:00Z' }];
    T.employee_status_log = [{ id: 1, employee_id: 'e1', from_status: 'draft', to_status: 'active', status_date: '2026-01-05', reason: 'registered' }];
    T.employee_leave_entitlements = [{ id: 1, employee_id: 'e1', leave_type: 'casual', days_per_year: 10 }]; T.employee_locations = [{ employee_id: 'e1', location_id: 2, active: true }];
    T.deed_templates = [{ id: 1, family_id: 1, version: 1, role_code: 'cashier', title_bn: 'ক্যাশিয়ার চুক্তি', title_en: 'Cashier deed', clauses: [{ no: 1, kind: 'amount', text_en: 'Cash limit', value: '50000', unit: 'BDT' }, { no: 2, kind: 'rule', text_en: 'Count with a second person' }], active: true }];
    T.employee_deeds = [{ id: 5, employee_id: 'e1', role_code: 'cashier', title: 'Cashier deed', clauses: [{ no: 1, kind: 'rule', text_en: 'Rule one' }], status: 'active', revision_no: 1, start_date: '2026-01-05', end_date: '2026-10-20' }];
    T.profiles = [{ id: 'u9', staff_id: 'sales06', full_name: 'Sales Person', status: 'active' }];
    const m0 = o.nomanage ? { grants: ['employee_view'], ctx: { is_owner: false, roles: ['showroom_manager'], locations: [1] } } : {};
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(m0)};window.__OWNER=${o.nomanage ? 'false' : 'true'};window.__SALARY=${o.nosalary ? 'false' : 'true'};window.__NOMANAGE=${o.nomanage ? 'true' : 'false'};window.__ERR41={};try{localStorage.setItem('bos_lang','en')}catch(e){};window.print=()=>{window.__PRINTED=(document.querySelector('#em_print')||{}).innerText||''};`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC41 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const PNG = require(SP + '/s10_common.js').PNGBUF;

  // ---------- list ----------
  let p = await open('#/employees');
  ok(await p.locator('#em_list .card.em-row').count() === 4, 'four rows (discarded excluded)');
  let t = await text(p); ok(/Active 1/.test(t) && /On leave 1/.test(t) && /Draft 1/.test(t), 'summary counts'); ok(/Abdul Karim/.test(t) && /E-0001/.test(t) && /Cashier/.test(t), 'name, number, designation');
  ok(await p.locator('#em_list img.em-av').count() === 1 && await p.locator('#em_list span.em-av').count() === 3, 'avatar photo for one, initials for the others');
  await p.fill('#em_q', '01811'); await wait(p, 200); ok(await p.locator('#em_list .card.em-row').count() === 1, 'search by mobile');
  await p.fill('#em_q', '19901234567890123'); await wait(p, 200); ok(await p.locator('#em_list .card.em-row').count() === 1, 'search by NID');
  await p.fill('#em_q', 'E-0003'); await wait(p, 200); ok(/রফিক|Rafiq/.test(await text(p)) && await p.locator('#em_list .card.em-row').count() === 1, 'search by number');
  await p.fill('#em_q', ''); await wait(p, 200);
  await p.evaluate(() => { document.querySelector('#em_filters details').open = true; });
  await p.selectOption('#em_fs', 'active'); await wait(p, 150); ok(await p.locator('#em_list .card.em-row').count() === 1, 'filter by status');
  await p.selectOption('#em_fs', ''); await p.selectOption('#em_ft', 'daily'); await wait(p, 150); ok(await p.locator('#em_list .card.em-row').count() === 1, 'filter by type');
  await p.selectOption('#em_ft', ''); await p.selectOption('#em_fl', '2'); await wait(p, 150); ok(await p.locator('#em_list .card.em-row').count() === 1, 'filter by place'); await p.selectOption('#em_fl', '');
  await p.selectOption('#em_fr', 'cashier'); await wait(p, 150); ok(await p.locator('#em_list .card.em-row').count() === 1, 'filter by role'); await p.selectOption('#em_fr', '');
  await p.click('[data-act=em_menu][data-v=e1]'); await wait(p, 300);
  const sheet = await p.textContent('.sheet'); ok(/Open/.test(sheet) && /Edit details/.test(sheet) && /Add deed/.test(sheet) && /Add document/.test(sheet) && /Change status/.test(sheet) && /Link to login account/.test(sheet) && /Copy mobile/.test(sheet), 'row menu has every action');
  await p.click('.sheet [data-act=em_status]'); await wait(p, 200); await p.selectOption('#ss_s', 'resigned'); await p.fill('#ss_r', 'moved away'); await p.click('[data-act=ss_save]'); await wait(p, 500);
  let c = await calls(p, 'employee_status_set'); ok(c.length === 1 && c[0].p_status === 'resigned' && c[0].p_reason === 'moved away' && c[0].p_id === 'e1', 'status change sent with reason');
  await noOverflow(p, 'list'); await p.screenshot({ path: SP + '/emp_list.png', fullPage: true });
  await p.click('[data-act=em_menu][data-v=e2]'); await wait(p, 300); await p.click('.sheet [data-act=em_link]'); await wait(p, 400); await p.selectOption('#lk_p', 'u9'); await p.click('[data-act=lk_save]:not([data-un])'); await wait(p, 400);
  c = await calls(p, 'employee_link_profile'); ok(c.length === 1 && c[0].p_profile === 'u9', 'login link sent');

  // ---------- wizard ----------
  p = await open('#/employees');
  await p.click('[data-act=em_new]'); await wait(p, 600);
  ok(/1\/6/.test(await text(p)), 'wizard step 1 of 6');
  await p.click('[data-act=em_next]'); await wait(p, 300); ok(/Name and work place are required/.test(await text(p)), 'cannot go on without name and place');
  await p.selectOption('#w_primary_location_id', '1'); await p.fill('#w_full_name_bn', 'নতুন কর্মী'); await p.fill('#w_full_name_en', 'New Worker'); await p.fill('#w_nid_no', '1990123456789'); await p.fill('#w_mobile', '01712345678'); await wait(p, 700);
  ok(/already exists/.test(await p.textContent('#w_dup')) && await p.locator('#w_dup a').count() === 1, 'duplicate NID warning with a link to the person');
  await p.fill('#w_nid_no', '1234567890'); await p.click('[data-act=em_draft]'); await wait(p, 500);
  c = await calls(p, 'employee_save'); ok(c.length === 1 && c[0].p_id === null && c[0].p_client && c[0].p_data.full_name_bn === 'নতুন কর্মী' && c[0].p_data.primary_location_id === 1 && c[0].p_dry === false, 'draft saved at step 1 with a client id');
  await p.click('[data-act=em_next]'); await wait(p, 500);
  c = await calls(p, 'employee_save'); ok(c.length === 2 && c[1].p_id === 'n5' && c[1].p_client === null, 'second save updates the same draft');
  ok(/2\/6/.test(await text(p)), 'step 2');
  await p.fill('#w_joining_date', '2026-10-01'); await p.selectOption('#w_designation', 'cashier'); await p.selectOption('#w_primary_role_code', 'cashier'); await p.selectOption('#w_employment_type', 'contract');
  await p.check('.w_loc[value="2"]'); await p.click('[data-act=em_next]'); await wait(p, 600);
  c = await calls(p, 'employee_locations_set'); ok(c.length === 1 && JSON.stringify(c[0].p_locs) === '[2]', 'other places sent');
  c = await calls(p, 'employee_save'); ok(c[2].p_data.designation === 'cashier' && c[2].p_data.employment_type === 'contract' && c[2].p_data.joining_date === '2026-10-01', 'job fields sent');
  ok(/3\/6/.test(await text(p)) && await p.locator('#w_p_basic').count() === 1, 'pay step shown to a person with the salary right');
  await p.fill('#w_p_basic', '20000'); await p.click('[data-act=em_comp_add][data-k=allowance][data-n="House rent"]'); await wait(p, 100); await p.fill('#w_cv0', '40');
  await p.click('[data-act=em_comp_add][data-k=deduction][data-n="Provident fund"]'); await wait(p, 100); await p.selectOption('#w_cm1', 'percent'); await p.fill('#w_cv1', '5');
  await p.click('[data-act=em_pay_prev]'); await wait(p, 500);
  ok(/28,000/.test(await p.textContent('#w_pay_out')) && /27,000/.test(await p.textContent('#w_pay_out')), 'preview shows gross 28,000 and net 27,000');
  ok((await calls(p, 'employee_pay_set')).length === 1 && (await calls(p, 'employee_pay_set'))[0].p_dry === true, 'preview is a dry run');
  ok(await p.evaluate(() => (window.__DATA.tables.pay_saved || 0) === 0), 'preview wrote nothing');
  await p.selectOption('#w_p_otr', 'multiple_of_hourly'); await p.fill('#w_p_otv', '1.5'); await p.click('[data-act=em_bonus_add]'); await wait(p, 100);
  await p.click('[data-act=em_ben_add]'); await wait(p, 100); await p.fill('#w_bd0', 'Lunch daily'); await p.fill('#w_bv0', '1500');
  await p.click('[data-act=em_next]'); await wait(p, 900);
  c = await calls(p, 'employee_pay_set'); const real = c.filter((x) => !x.p_dry);
  ok(real.length === 1 && real[0].p_basic === 20000 && real[0].p_basis === 'monthly' && real[0].p_ot_rule === 'multiple_of_hourly' && real[0].p_ot_value === 1.5 && real[0].p_components.length === 2 && real[0].p_components[0].percent_of_basic === 40 && real[0].p_components[1].kind === 'deduction' && real[0].p_bonus[0].months_of_basic === 1 && real[0].p_client, 'pay saved for real with lines, OT, bonus and a client id');
  c = await calls(p, 'leave_entitlement_set'); ok(c.length === 3 && c.some((x) => x.p_type === 'casual' && x.p_days === 10) && c.some((x) => x.p_type === 'sick' && x.p_days === 14), 'leave entitlements sent with the suggested defaults');
  c = await calls(p, 'employee_benefit_save'); ok(c.length === 1 && c[0].p_kind === 'meal' && c[0].p_value === 1500 && c[0].p_desc === 'Lunch daily', 'facility saved with its monthly value');
  ok(/4\/6/.test(await text(p)), 'documents step');
  await p.setInputFiles('#w_cam', { name: 'p.png', mimeType: 'image/png', buffer: PNG }); await wait(p, 900);
  let up = await p.evaluate(() => window.__UP); ok(up.length === 1 && /^EMP\/1\/.+\.jpg$/.test(up[0][0]), 'portrait uploaded to EMP/<place>/');
  c = await calls(p, 'employee_set_photo'); ok(c.length === 1 && /^EMP\/1\//.test(c[0].p_path), 'portrait path recorded');
  ok(await p.locator('#w_body img.em-av').count() === 1, 'portrait shown');
  await p.selectOption('#w_dk', 'nid'); await p.fill('#w_dn', 'front'); await p.setInputFiles('#w_doc', { name: 'n.png', mimeType: 'image/png', buffer: PNG }); await wait(p, 900);
  up = await p.evaluate(() => window.__UP); c = await calls(p, 'employee_doc_add'); ok(up.length === 2 && /^EMPDOC\/1\//.test(up[1][0]) && c.length === 1 && c[0].p_kind === 'nid' && c[0].p_note === 'front' && c[0].p_client, 'document uploaded to EMPDOC and recorded');
  await noOverflow(p, 'wizard documents'); await p.click('[data-act=em_next]'); await wait(p, 500);
  ok(/5\/6/.test(await text(p)), 'deed step');
  await p.selectOption('#wd_role', 'cashier'); await p.selectOption('#wd_tpl', '1'); await wait(p, 300);
  ok(await p.locator('#wd_cl [data-cl]').count() === 2 && await p.inputValue('#wd_title') === 'Cashier deed', 'template copies clauses and title');
  await p.click('#wd_cl [data-act=cl_add]'); await wait(p, 150); await p.fill('#cl_e2', 'Extra rule'); await p.click('[data-act=cl_up][data-v="2"]'); await wait(p, 150);
  ok(await p.inputValue('#cl_e1') === 'Extra rule', 'clause moved up');
  await p.click('[data-act=cl_del][data-v="0"]'); await wait(p, 150); ok(await p.locator('#wd_cl [data-cl]').count() === 2, 'clause removed');
  await p.fill('#wd_start', '2026-10-01'); await p.fill('#wd_dep', '5000'); await p.fill('#wd_gn', 'Rahim'); await p.click('[data-act=em_next]'); await wait(p, 600);
  c = await calls(p, 'deed_save'); ok(c.length === 1 && c[0].p_emp === 'n5' && c[0].p_role === 'cashier' && c[0].p_template === 1 && c[0].p_deposit === 5000 && c[0].p_clauses.length === 2 && c[0].p_clauses[0].text_en === 'Extra rule' && c[0].p_start === '2026-10-01', 'draft deed saved with the edited clauses');
  ok(/6\/6/.test(await text(p)) && /নতুন কর্মী|New Worker/.test(await text(p)), 'review step');
  await p.click('[data-act=em_finish]'); await wait(p, 900);
  c = await calls(p, 'employee_submit'); ok(c.length === 1 && c[0].p_id === 'n5', 'submit sent'); ok(/#\/employee\/n5/.test(await p.evaluate(() => location.hash)), 'goes to the new profile');
  ok(/E-0009/.test(await text(p)), 'number shown on the profile'); await noOverflow(p, 'profile after wizard');
  // friendly errors
  p = await open('#/employees/new'); await p.selectOption('#w_primary_location_id', '1'); await p.fill('#w_full_name_bn', 'ডুপ্লিকেট');
  await p.evaluate(() => { window.__ERR41 = { employee_save: 'duplicate_nid' }; }); await p.click('[data-act=em_next]'); await wait(p, 400);
  ok(/An employee with this NID already exists/.test(await text(p)), 'friendly duplicate NID text');
  await p.evaluate(() => { window.__ERR41 = { employee_save: 'bad_mobile' }; }); await p.click('[data-act=em_next]'); await wait(p, 400); ok(/Mobile number is not valid/.test(await text(p)), 'friendly bad mobile text');
  await p.evaluate(() => { window.__ERR41 = { employee_save: 'some_new_code' }; }); await p.click('[data-act=em_next]'); await wait(p, 400); ok(/some_new_code/.test(await text(p)), 'unknown server text shown raw');
  await noOverflow(p, 'wizard step 1'); await p.screenshot({ path: SP + '/emp_wizard.png', fullPage: true });

  // ---------- profile ----------
  p = await open('#/employee/e1');
  t = await text(p); ok(/Abdul Karim/.test(t) && /E-0001/.test(t), 'profile header');
  const tabs = await p.locator('.ptabs button').allTextContents(); ok(tabs.join('|') === 'Overview|Pay|Facilities|Documents|Deeds|History', 'tabs for owner: ' + tabs.join('|'));
  await p.click('[data-act=pf_tab][data-v=pay]'); await wait(p, 200); t = await text(p); ok(/25,000/.test(t) && /35,000/.test(t) && /34,000/.test(t) && /DBBL 123/.test(t) && /Eid/.test(t), 'pay tab: basic, gross, net, account, bonus');
  await p.click('[data-act=pf_tab][data-v=fac]'); await wait(p, 200); t = await text(p); ok(/Lunch/.test(t) && /1,200/.test(t) && /Casual/.test(t), 'facilities tab with value for salary people');
  await p.click('[data-act=pf_tab][data-v=docs]'); await wait(p, 200); ok(await p.locator('#pf_tab img.em-av').count() === 1, 'documents tab thumbnail');
  await p.click('[data-act=pf_doc_void]'); await wait(p, 400); c = await calls(p, 'employee_doc_void'); ok(c.length === 1 && c[0].p_reason === 'typed by mistake', 'void needs and sends a reason');
  await p.click('[data-act=pf_tab][data-v=hist]'); await wait(p, 200); ok(/registered/.test(await text(p)), 'history tab');
  await p.click('[data-act=pf_tab][data-v=deeds]'); await wait(p, 200); ok(/Cashier deed/.test(await text(p)) && /Active/.test(await text(p)), 'deeds tab');
  await p.click('[data-act=dd_open][data-v="5"]'); await wait(p, 500);
  const dsheet = await p.textContent('.sheet'); ok(/Rule one/.test(dsheet) && /Print/.test(dsheet) && /Revise/.test(dsheet) && /End deed/.test(dsheet), 'active deed: print / revise / end');
  await p.click('.sheet [data-act=dd_print]'); await wait(p, 300); ok(/Cashier deed/.test(await p.evaluate(() => window.__PRINTED || '')) && /Rule one/.test(await p.evaluate(() => window.__PRINTED || '')), 'deed print view built');
  await p.click('.sheet [data-act=dd_revise]'); await wait(p, 700); c = await calls(p, 'deed_revise'); ok(c.length === 1 && c[0].p_id === 5, 'revise sent');
  ok(await p.locator('.sheet #dd_cl [data-cl]').count() === 1, 'revision opens a draft form with the clauses');
  await p.fill('#cl_e0', 'Rule one changed'); await p.click('[data-act=dd_save][data-v="1"]'); await wait(p, 700);
  c = await calls(p, 'deed_save'); ok(c.length === 1 && c[0].p_id === 31 && c[0].p_clauses[0].text_en === 'Rule one changed', 'revision draft saved'); c = await calls(p, 'deed_activate'); ok(c.length === 1 && c[0].p_id === 31, 'revision put in force');
  await p.click('[data-act=pf_print][data-v=card]'); await wait(p, 300); let pr = await p.evaluate(() => window.__PRINTED || ''); ok(/Abdul Karim/.test(pr) && /E-0001/.test(pr), 'ID card print');
  await p.click('[data-act=pf_print][data-v=sheet]'); await wait(p, 300); pr = await p.evaluate(() => window.__PRINTED || ''); ok(/01711000001/.test(pr) && /1990123456789/.test(pr), 'profile sheet print');
  await noOverflow(p, 'profile'); await p.screenshot({ path: SP + '/emp_profile.png', fullPage: true });
  // no salary right: no Pay tab, no pay call
  p = await open('#/employee/e1', { nosalary: true, nomanage: true });
  const tabs2 = await p.locator('.ptabs button').allTextContents(); ok(tabs2.join('|') === 'Overview|Facilities|History', 'tabs without salary / manage rights: ' + tabs2.join('|'));
  ok((await calls(p, 'employee_pay_current')).length === 0 && (await calls(p, 'employee_pay_history')).length === 0 && (await calls(p, 'employee_pay_account_get')).length === 0, 'no pay function is even called without the salary right');
  await p.click('[data-act=pf_tab][data-v=fac]'); await wait(p, 200); t = await text(p); ok(/Lunch/.test(t) && !/1,200/.test(t), 'facility shown without its value');
  ok(!/DBBL/.test(await text(p)), 'pay account not shown');
  // wizard without salary rights
  p = await open('#/employees/new', { nosalary: true, nomanage: true });
  await p.selectOption('#w_primary_location_id', '1'); await p.fill('#w_full_name_bn', 'বেতনহীন'); await p.click('[data-act=em_next]'); await wait(p, 400); await p.click('[data-act=em_next]'); await wait(p, 500);
  ok(/3\/6/.test(await text(p)) && await p.locator('#w_p_basic').count() === 0 && /not allowed to see or set pay/.test(await text(p)), 'pay inputs are not offered without the salary right');

  // ---------- deeds screen ----------
  p = await open('#/deeds');
  t = await text(p); ok(/Ending soon/.test(t) && /7 days left/.test(t) && /Cashier deed/.test(t) && /Deed templates/.test(t) && /v1/.test(t), 'expiring deeds and templates listed');
  await p.click('[data-act=tp_new]'); await wait(p, 300); await p.selectOption('#tp_role', 'storekeeper'); await p.fill('#tp_bn', 'স্টোর চুক্তি'); await p.fill('#tp_en', 'Store deed');
  await p.click('#tp_cl [data-act=cl_add]'); await wait(p, 100); await p.selectOption('#cl_k0', 'amount'); await p.fill('#cl_e0', 'Stock limit'); await p.fill('#cl_v0', '100000'); await p.fill('#cl_u0', 'BDT');
  await p.click('#tp_cl [data-act=cl_add]'); await wait(p, 100); await p.fill('#cl_e1', 'Count weekly'); await p.click('[data-act=cl_up][data-v="1"]'); await wait(p, 100);
  await p.click('[data-act=tp_save]'); await wait(p, 600);
  c = await calls(p, 'deed_template_save'); ok(c.length === 1 && c[0].p_role === 'storekeeper' && c[0].p_family === null && c[0].p_clauses.length === 2 && c[0].p_clauses[0].text_en === 'Count weekly' && c[0].p_clauses[1].kind === 'amount' && c[0].p_clauses[1].value === '100000' && c[0].p_client, 'template saved with reordered clauses');
  await p.click('[data-act=tp_edit][data-v="1"]'); await wait(p, 300); ok(/v1 → v2/.test(await p.textContent('.sheet')), 'editing a template makes the next version');
  await p.click('.sheet [data-act=closesheet] >> nth=0').catch(() => {}); await noOverflow(p, 'deeds'); await p.screenshot({ path: SP + '/emp_deeds.png', fullPage: true });

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
