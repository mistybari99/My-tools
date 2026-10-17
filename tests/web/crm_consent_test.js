// CRM-B web pieces: web/crm_consent.js (#/crmconsent: consent register, sheet, paper list, export, access log, settings; the API the customer list, profile and POS call)
// and web/crm_dupes.js (#/crmdupes: possible duplicates, "same person" link, unlink, settings).
// Also the HOOKS: the exact lines for the integrator-owned web/customers.js and web/pos.js are applied to a SCRATCH COPY (tests/web/crm_hooks.js; the real files are not touched),
// the doc docs/integration/CRM-B.md is checked to contain them word for word, and the hooked customer list, menu, profile and POS strip are run.
// Run: node crm_consent_test.js <abs tests/web dir>       (the server functions are mocked here; supabase/phase303_test.sql, phase304_test.sql, phase305_test.sql check the database)
// Screenshots go to CRM_SHOTS if that variable is set (never into the repository).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const HK = require('./crm_hooks.js');
const WEB = path.join(__dirname, '..', '..', 'web');
const base = C.baseData(SP), PORT = 8571;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' };
let HOOKED = false;
const srv = require('http').createServer((q, r) => {
  const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, 'utf8', (e, t) => {
    if (e) { r.writeHead(404); return r.end(); }
    if (HOOKED && (u === '/customers.js' || u === '/pos.js')) t = HK.apply(u.slice(1), t);        // the scratch copy: hooks applied in memory only
    r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); r.end(t);
  });
}).listen(PORT);

const POL = (o) => Object.assign({ guard_on: false, contact_ok: true, mask_style: 'first3_last2', can_reveal: true, reason_required: false, export_on: false, export_cap: null, can_export: false, print_needs_export: false, can_print: true,
  can_consent: true, can_manage_consent: true, consent_pos_on: false, dup_on: true, can_merge: true, can_link: true, is_owner: true }, o || {});
const SUM = { active_customers: 10, dnc: 1, channels: { sms: { in: 4, out: 2, not_asked: 4, coverage_pct: 60 }, whatsapp: { in: 1, out: 0, not_asked: 9, coverage_pct: 10 } } };
const REG = (o) => Object.assign({ total: 2, masked: false, summary: SUM, rows: [
  { id: 'k1', name: 'test_cust_one', mobile: '01700000001', status: 'in', at: '2026-10-01T00:00:00Z', dnc: false, how: 'paper_form' },
  { id: 'k2', name: 'test_cust_two', mobile: '01700000002', status: 'out', at: '2026-10-02T00:00:00Z', dnc: true, how: 'phone' }] }, o || {});
const CAND = { off: false, total: 2, masked: false, rows: [
  { a_id: 'k1', b_id: 'k3', strength: 'strong', reasons: ['same_name', 'same_address'], a: { id: 'k1', name: 'test_cust_one', active: true, mobile: '01700000001' }, b: { id: 'k3', name: 'TEST cust-one', active: true, mobile: '01700000003' } },
  { a_id: 'k2', b_id: 'k4', strength: 'weak', reasons: ['similar_name'], a: { id: 'k2', name: 'test_cust_two', active: true, mobile: '01700000002' }, b: { id: 'k4', name: 'test_cust_twa', active: false, mobile: '01700000004' } }] };
const LINKS = [{ id: 1, primary_id: 'k1', primary_name: 'test_cust_one', primary_mobile: '01700000001', linked_id: 'k3', linked_name: 'TEST cust-one', linked_mobile: '01700000003', reason: 'second number', created_staff: 'owner1', created_at: '2026-10-03T00:00:00Z', undone_at: null, undo_reason: null },
  { id: 2, primary_id: 'k2', primary_name: 'test_cust_two', primary_mobile: '01700000002', linked_id: 'k4', linked_name: 'test_cust_twa', linked_mobile: '01700000004', reason: 'old', created_staff: 'owner1', created_at: '2026-09-03T00:00:00Z', undone_at: '2026-09-04T00:00:00Z', undo_reason: 'mistake' }];
const DIR = [
  { id: 'k1', mobile: '01700000001', name: 'test_cust_one', type: 'retail', active: true, tier_id: null, tier_locked: false, birthday: null, anniversary: null, address: 'test road', whatsapp: null, note: null, credit_limit: null, customer_since: '2026-01-01', balance: 0, spend: 100, orders: 1, last_sale: '2026-10-01', points: 0, masked: false, linked_to: null, linked_count: 0 },
  { id: 'k2', mobile: '01700000002', name: 'test_cust_two', type: 'retail', active: true, tier_id: null, tier_locked: false, birthday: null, anniversary: null, address: null, whatsapp: null, note: null, credit_limit: null, customer_since: '2026-01-01', balance: 0, spend: 0, orders: 0, last_sale: null, points: 0, masked: false, linked_to: null, linked_count: 0 }];
const rule = (key, kind, def, value, label) => ({ key, module: 'crm', kind, value: value === undefined ? null : value, default_value: def, choices: kind === 'choice' ? ['first3_last2', 'last4'] : null, label_bn: key, label_en: label || key, label_mix: key, hint_en: 'hint for ' + key, sort: 1 });
const RULES = [rule('crm_consent_pos_on', 'switch', false, undefined, 'Let counter staff record'), rule('crm_quiet_from', 'text', null, undefined, 'Quiet time starts'), rule('crm_quiet_to', 'text', null), rule('crm_pii_guard_on', 'switch', false, undefined, 'Show customer phone and address only to people who are allowed'),
  rule('crm_mask_style', 'choice', 'first3_last2'), rule('crm_unmask_reason_required', 'switch', true), rule('crm_reveal_for_call', 'switch', false), rule('crm_export_on', 'switch', false), rule('crm_export_max_rows', 'number', null), rule('crm_print_needs_export', 'switch', false),
  rule('crm_dup_check_on', 'switch', false, undefined, 'Look for duplicate customers'), rule('crm_dup_similar_names_on', 'switch', false, undefined, 'Also list names that differ by one letter')];

const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const K = ${JSON.stringify({ SUM, REG: REG(), CAND, LINKS, DIR })}; const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const R = window.__CRM = window.__CRM || { calls: [], o: {} };
 c.rpc = async (fn, args) => {
  if (!/^(_crmb_|find_customer$|set_rule$|customer_directory$|customer_profile$)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, clone(args || {})]); const O = R.o;
  if (O.missing && /^_crmb_/.test(fn)) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + fn } };
  if (O.err && O.err[fn]) { const m = O.err[fn]; if (!O.keep) delete O.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  if (fn === '_crmb_policy') return { data: O.pol, error: null };
  if (fn === '_crmb_customer_list') return { data: clone(O.list || K.DIR), error: null };
  if (fn === 'customer_directory') return { data: clone(K.DIR), error: null };
  if (fn === '_crmb_customer_profile' || fn === 'customer_profile') { const x = (O.list || K.DIR).find((u) => u.id === args.p_customer) || K.DIR[0];
    return { data: { customer: { id: x.id, mobile: x.mobile, name: x.name, type: 'retail', active: true, tier_id: null, tier_locked: false, birthday: null, anniversary: null, address: x.address, whatsapp: null, note: null, source: null, credit_limit: null, customer_since: '2026-01-01' }, spend: 100, orders: 1, orders_12m: 1, first_sale: '2026-02-01', last_sale: '2026-10-01', avg_bill: 100, balance: 0, points: 0, history: [], gifts: [], points_log: [], recent_sales: [], masked: !!x.masked }, error: null }; }
  if (fn === '_crmb_consent_get') return { data: clone(O.cget || { customer_id: args.p_customer, dnc: false, block: null, can_manage: true, channels: { sms: { status: 'in', how: 'paper_form', by: 'mgr2' }, whatsapp: { status: 'not_asked' } } }), error: null };
  if (fn === '_crmb_consent_history') return { data: [{ id: 3, at: '2026-10-01T00:00:00Z', kind: 'optin', channel: 'sms', status: 'in', how: 'paper_form', note: 'form 7', staff_id: 'mgr2' }], error: null };
  if (fn === '_crmb_consent_set' || fn === '_crmb_prefs_set' || fn === '_crmb_consent_set_mobile') return { data: { status: 'in', duplicate: false }, error: null };
  if (fn === '_crmb_consent_get_mobile') return { data: { found: true, customer_id: 'k1', dnc: false, channels: { sms: { status: O.posKnown || 'not_asked' }, whatsapp: { status: 'not_asked' } } }, error: null };
  if (fn === '_crmb_consent_register') return { data: clone(O.reg || K.REG), error: null };
  if (fn === '_crmb_consent_import') { const rows = args.p_rows.map((r, i) => ({ i: i + 1, mobile: r.mobile, status: i === 1 ? 'withdrawn_kept' : i === 2 ? 'bad_mobile' : 'will_change' }));
    return { data: { dry: args.p_dry, duplicate: false, will_change: rows.filter((r) => r.status === 'will_change').length, same: 0, withdrawn_kept: 1, errors: 1, rows }, error: null }; }
  if (fn === '_crmb_phone_reveal') return { data: { id: args.p_customer, name: 'test_cust_one', mobile: '01700000001', whatsapp: null, address: null, logged: true }, error: null };
  if (fn === '_crmb_view_log_list') return { data: [{ id: 2, at: '2026-10-05T10:00:00Z', staff_id: 'cash1', what: 'call', reason: 'order is ready', row_count: 1, customer_id: 'k1', customer_name: 'test_cust_one' }, { id: 1, at: '2026-10-04T10:00:00Z', staff_id: 'grant1', what: 'list', reason: null, row_count: 5000, customer_id: null, customer_name: null }], error: null };
  if (fn === '_crmb_export_log_list') return { data: [{ id: 1, at: '2026-10-06T10:00:00Z', staff_id: 'owner1', kind: 'export', what: 'customers', row_count: 7, masked: false, format: 'csv', reason: 'monthly list' }], error: null };
  if (fn === '_crmb_export') return { data: { log_id: 5, count: 2, truncated: false, masked: false, format: 'csv', columns: ['id', 'name'], rows: null, csv: 'id,name\\n1,test_cust_one\\n' }, error: null };
  if (fn === '_crmb_print_log') return { data: 9, error: null };
  if (fn === '_crmb_dup_candidates') return { data: clone(O.cand || K.CAND), error: null };
  if (fn === '_crmb_links_list') return { data: clone(K.LINKS), error: null };
  if (fn === '_crmb_customer_group') return { data: O.grp || { customer_id: args.p_customer, root_id: 'k1', is_primary: true, in_group: true, members: [{ id: 'k1', name: 'test_cust_one', mobile: '01700000001', active: true, is_primary: true, balance: 0 }, { id: 'k3', name: 'TEST cust-one', mobile: '01700000003', active: true, is_primary: false, balance: 700 }], combined: { spend: 2400, orders: 2, last_sale: '2026-10-01', points: 0 }, ledgers_separate: true, note: 'Dues, payments and the books stay on each customer.' }, error: null };
  if (fn === '_crmb_link_customers' || fn === '_crmb_unlink_customers' || fn === '_crmb_dup_review') return { data: { ok: true, duplicate: false }, error: null };
  if (fn === 'find_customer') return { data: String(args.p_mobile).endsWith('3') ? { found: true, id: 'k3', name: 'TEST cust-one', mobile: args.p_mobile, balance: 0 } : { found: false }, error: null };
  if (fn === 'set_rule') return { data: null, error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, total = 0; const ok = (c, m) => { total++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); let h = await res.text(); for (const f of ['crm_consent.js', 'crm_dupes.js']) if (!h.includes(f)) h = h.replace('</body>', `<script src="${f}"></script></body>`); if (!/customers\.js/.test(h)) h = h.replace('</body>', '<script src="customers.js"></script></body>'); await r.fulfill({ response: res, body: h }); });
    const data = C.mk(base, {}); data.tables.rules = (data.tables.rules || []).filter((x) => !/^crm_/.test(x.key)).concat(RULES);
    const crm = { calls: [], o: Object.assign({ pol: POL() }, o.o || {}) };
    const M0 = o.staff ? { grants: [], ctx: { is_owner: false, roles: ['salesperson'], locations: [1], perms: { POS: { view: true, enter: true, approve: false } } } }
      : o.mgr ? { grants: ['customer_manage'], ctx: { is_owner: false, roles: ['showroom_manager'], locations: [1], perms: { POS: { view: true, enter: true, approve: true } } } } : null;
    if (o.block) await p.addInitScript(`try{Object.defineProperty(window,'localStorage',{get(){throw new Error('blocked')}});Object.defineProperty(window,'sessionStorage',{get(){throw new Error('blocked')}});}catch(e){}`);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.staff || o.mgr ? 'false' : 'true'};window.__M0=${JSON.stringify(M0)};window.__CRM=${JSON.stringify(crm)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__CRM.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const shot = async (p, n) => { if (process.env.CRM_SHOTS) await p.screenshot({ path: process.env.CRM_SHOTS + '/' + n + '.png', fullPage: true }); };
  const click = async (p, sel) => { await p.waitForSelector(sel, { timeout: 10000 }); await p.click(sel); await wait(p, 350); };
  let p, t;

  // ---- 0. the hooks: every site exists exactly once in the real files, the doc has the new text word for word
  const DOC = fs.readFileSync(path.join(__dirname, '..', '..', 'docs', 'integration', 'CRM-B.md'), 'utf8');
  for (const f of Object.keys(HK.HOOKS)) {
    let threw = null; try { HK.apply(f, fs.readFileSync(path.join(WEB, f), 'utf8')); } catch (e) { threw = e.message; }
    ok(!threw, 'hook sites found exactly once in web/' + f + (threw ? ': ' + threw : ''));
    for (const [, nw] of HK.HOOKS[f]) ok(DOC.includes(nw), 'the doc contains the hook text word for word (' + f + '): ' + nw.slice(0, 60));
    for (const [old] of HK.HOOKS[f]) ok(DOC.includes(old), 'the doc contains the old text (' + f + '): ' + old.slice(0, 60));
  }
  ok(/crmConsent/.test(fs.readFileSync(path.join(WEB, 'customers.js'), 'utf8')) && /crmConsent/.test(fs.readFileSync(path.join(WEB, 'pos.js'), 'utf8')), 'the real customers.js and pos.js carry the integrated hooks (integration: they were untouched before)');
  { const tmp = require('os').tmpdir(); for (const f of Object.keys(HK.HOOKS)) { const fp = path.join(tmp, 'crm_hooked_' + f); fs.writeFileSync(fp, HK.apply(f, fs.readFileSync(path.join(WEB, f), 'utf8'))); try { require('child_process').execFileSync(process.execPath, ['--check', fp]); } catch (e) { ok(false, 'hooked copy of ' + f + ' is valid JavaScript'); } } }

  // ---- 1. the consent register (owner)
  p = await open('#/crmconsent');
  t = await text(p);
  ok(/Customer consent and privacy/.test(await p.locator('h1').textContent()), 'title (English)');
  ok(await p.locator('#cc_head').count() === 1 && /Phone numbers hidden: OFF/.test(t) && /Export: OFF/.test(t), 'header chips show the three switches at their defaults');
  ok(await p.locator('#cc_tabs [data-v=import]').count() === 1 && await p.locator('#cc_tabs [data-v=access]').count() === 1, 'owner sees Paper list and Access log tabs');
  ok(await p.locator('#cc_sum').count() === 1 && /4 agree/.test(t) && /2 do not agree/.test(t) && /4 not asked/.test(t) && /60%/.test(t), 'summary tiles');
  ok(await p.locator('.crmc-row').count() === 2 && /test_cust_one/.test(t) && /Agrees/.test(t) && /Do not contact/.test(t), 'two register rows with status chips');
  ok((await calls(p, '_crmb_consent_register')).length === 1 && (await calls(p, '_crmb_consent_register'))[0].p_channel === 'sms', 'one register call, channel sms');
  await noOverflow(p, 'register'); await shot(p, 'crm_register');
  await p.selectOption('#cc_st', 'out'); await p.fill('#cc_q', 'two'); await click(p, '[data-act=cc_show]');
  const rg = (await calls(p, '_crmb_consent_register')).pop();
  ok(rg.p_status === 'out' && rg.p_search === 'two', 'the filter and the search are sent');

  // ---- 2. the consent sheet
  await click(p, '.crmc-row[data-v=k2]');
  ok(await p.locator('#crmc_sheet').count() === 1 && await p.locator('.crmc-ch').count() === 2 && /SMS/.test(await text(p)) && /WhatsApp/.test(await text(p)), 'sheet shows both channels');
  ok(await p.locator('.crmc-ch[data-ch=sms] [data-in="1"]').isDisabled() && !(await p.locator('.crmc-ch[data-ch=sms] [data-in="0"]').isDisabled()), 'a channel that already agrees cannot be set to agree again');
  ok(await p.locator('.crmc-hist').count() === 1 && /form 7/.test(await text(p)), 'the last changes are shown to a manager');
  await noOverflow(p, 'consent sheet'); await shot(p, 'crm_sheet');
  await click(p, '.crmc-ch[data-ch=whatsapp] [data-in="1"]');
  let cs = await calls(p, '_crmb_consent_set');
  ok(cs.length === 1 && cs[0].p_channel === 'whatsapp' && cs[0].p_in === true && cs[0].p_how === 'phone' && cs[0].p_customer === 'k2' && /^[0-9a-f-]{36}$/.test(cs[0].p_client), 'a yes is sent with channel, way, customer and a client id');
  await p.selectOption('#crmc_how', 'paper_form'); await p.fill('#crmc_note', 'form 9');
  await click(p, '.crmc-ch[data-ch=sms] [data-in="0"]');
  cs = await calls(p, '_crmb_consent_set');
  ok(cs.length === 2 && cs[1].p_in === false && cs[1].p_how === 'paper_form' && cs[1].p_note === 'form 9', 'a no is sent with the chosen way and note');
  // yes after no needs a reason
  p = await open('#/crmconsent', { o: { cget: { customer_id: 'k2', dnc: false, block: null, can_manage: true, channels: { sms: { status: 'out', how: 'phone' }, whatsapp: { status: 'not_asked' } } } } });
  await click(p, '.crmc-row[data-v=k2]'); await click(p, '.crmc-ch[data-ch=sms] [data-in="1"]');
  ok((await calls(p, '_crmb_consent_set')).length === 0 && /Write a reason/.test(await text(p)), 'a yes after a no without a note is not sent');
  await p.fill('#crmc_note', 'customer asked to be messaged again'); await click(p, '.crmc-ch[data-ch=sms] [data-in="1"]');
  ok((await calls(p, '_crmb_consent_set')).length === 1, 'with a note it is sent');
  // do-not-contact
  await click(p, '[data-act=crmc_dnc][data-on="1"]');
  const dn = await calls(p, '_crmb_prefs_set');
  ok(dn.length === 1 && dn[0].p_dnc === true && dn[0].p_customer === 'k2', 'do-not-contact ON is sent');
  p = await open('#/crmconsent', { o: { cget: { customer_id: 'k2', dnc: true, block: 'dnc', can_manage: true, channels: { sms: { status: 'in' }, whatsapp: { status: 'not_asked' } } } } });
  await click(p, '.crmc-row[data-v=k2]'); await click(p, '[data-act=crmc_dnc][data-on="0"]');
  ok((await calls(p, '_crmb_prefs_set')).length === 0, 'switching do-not-contact OFF without a note is not sent');
  p = await open('#/crmconsent', { o: { cget: { customer_id: 'k2', dnc: false, block: 'group_opted_out', can_manage: true, channels: { sms: { status: 'in' }, whatsapp: { status: 'not_asked' } } } } });
  await click(p, '.crmc-row[data-v=k2]');
  ok(/Another number of the same person said no/.test(await text(p)), 'a group block is explained');

  // ---- 3. counter staff (no manager right): no register, short sheet, only the four counter ways
  p = await open('#/crmconsent', { staff: true, o: { pol: POL({ can_manage_consent: false, is_owner: false, can_merge: false, can_link: false, consent_pos_on: true }), cget: { customer_id: 'k1', dnc: false, block: null, can_manage: false, channels: { sms: { status: 'not_asked' }, whatsapp: { status: 'not_asked' } } } } });
  t = await text(p);
  ok(/for the owner and customer managers/.test(t) && await p.locator('#cc_tabs [data-v=import]').count() === 0 && await p.locator('#cc_tabs [data-v=access]').count() === 0, 'counter staff: no register, no import or access tabs');
  ok((await calls(p, '_crmb_consent_register')).length === 0, 'the register is not even requested');
  await p.evaluate(() => window.BOS.crmConsent.sheet('k1', 'test_cust_one')); await wait(p, 400);
  ok(await p.locator('#crmc_sheet').count() === 1 && await p.locator('#crmc_how option').count() === 4 && await p.locator('#crmc_how option[value=owner_entry]').count() === 0 && await p.locator('.crmc-hist').count() === 0, 'counter staff: four ways only, no history');
  ok((await calls(p, '_crmb_consent_history')).length === 0, 'history is not requested for counter staff');
  p = await open('#/crmconsent', { staff: true, o: { pol: POL({ can_consent: false, can_manage_consent: false, is_owner: false }) } });
  await p.evaluate(() => window.BOS.crmConsent.sheet('k1', 'x')); await wait(p, 300);
  ok(await p.locator('#crmc_sheet').count() === 0, 'no consent right: the sheet does not open');

  // ---- 4. paper list import
  p = await open('#/crmconsent');
  await click(p, '[data-act=cc_tab][data-v=import]');
  ok(await p.locator('#im_text').count() === 1 && await p.locator('#cc_imgo').count() === 0, 'import tab: no Apply before a check');
  await p.fill('#im_text', 'mobile\n01700000011\n01700000012,x\nabc'); await p.fill('#im_note', 'ab'); await click(p, '[data-act=cc_imcheck]');
  ok((await calls(p, '_crmb_consent_import')).length === 0, 'a list name under 3 characters is not sent');
  await p.fill('#im_note', 'Eid form 2026'); await click(p, '[data-act=cc_imcheck]');
  let ic = await calls(p, '_crmb_consent_import');
  ok(ic.length === 1 && ic[0].p_dry === true && ic[0].p_rows.length === 3 && ic[0].p_rows[0].mobile === '01700000011' && ic[0].p_in === true && ic[0].p_list_note === 'Eid form 2026', 'Check sends a dry run of 3 numbers (header skipped)');
  ok(await p.locator('#cc_imres').count() === 1 && /said no before: kept/.test(await text(p)) && /not a mobile number/.test(await text(p)) && await p.locator('#cc_imgo').count() === 1, 'the check result explains each kind of row and offers Apply');
  await p.fill('#im_text', '01700000011'); await click(p, '#cc_imgo');
  ic = await calls(p, '_crmb_consent_import'); ok(ic.length === 1, 'editing the list after the check: Apply refuses (check again)');
  await click(p, '[data-act=cc_imcheck]'); await click(p, '#cc_imgo');
  ic = await calls(p, '_crmb_consent_import'); ok(ic.length === 3 && ic[2].p_dry === false && ic[2].p_client === ic[1].p_client, 'after a new check Apply sends the real import with the same batch id');
  await noOverflow(p, 'import');

  // ---- 5. export tab
  p = await open('#/crmconsent');
  await click(p, '[data-act=cc_tab][data-v=export]');
  ok(/switched off/.test(await text(p)) && await p.locator('[data-act=cc_export]').count() === 0, 'export OFF (default): no button');
  p = await open('#/crmconsent', { o: { pol: POL({ export_on: true, export_cap: 50, can_export: true }) } });
  await click(p, '[data-act=cc_tab][data-v=export]');
  ok(await p.locator('[data-act=cc_export]').count() === 1 && /Up to 50 customers/.test(await text(p)) && /Reason \(optional\)/.test(await text(p)) && /monthly list/.test(await text(p)), 'export ON: button, cap, owner reason optional, the log below');
  await click(p, '[data-act=cc_export]');
  let ex = await calls(p, '_crmb_export'); ok(ex.length === 1 && ex[0].p_format === 'csv' && ex[0].p_dataset === 'customers', 'the export is requested as csv');
  p = await open('#/crmconsent', { staff: true, o: { pol: POL({ export_on: true, export_cap: 50, can_export: true, is_owner: false, can_manage_consent: false }) } });
  await click(p, '[data-act=cc_tab][data-v=export]');
  await click(p, '[data-act=cc_export]'); ok((await calls(p, '_crmb_export')).length === 0 && /Write a reason/.test(await text(p)), 'a non-owner must write a reason first');
  await p.fill('#ex_reason', 'month end mailing list'); await click(p, '[data-act=cc_export]'); ok((await calls(p, '_crmb_export')).length === 1 && (await calls(p, '_crmb_export'))[0].p_reason === 'month end mailing list', 'with a reason it is sent');
  p = await open('#/crmconsent', { o: { pol: POL({ export_on: true, export_cap: null, can_export: false }) } });
  await click(p, '[data-act=cc_tab][data-v=export]');
  ok(/Set the most rows/.test(await text(p)) && await p.locator('[data-act=cc_export]').count() === 0, 'export ON but no cap: blocked with the reason');

  // ---- 6. access log (owner only)
  p = await open('#/crmconsent');
  await click(p, '[data-act=cc_tab][data-v=access]');
  t = await text(p); ok(/opened to call/.test(t) && /order is ready/.test(t) && /opened the list/.test(t), 'access log lines');
  await noOverflow(p, 'access');

  // ---- 7. settings (owner edits; typed values)
  p = await open('#/crmconsent');
  await click(p, '[data-act=cc_tab][data-v=settings]');
  ok(await p.locator('.cc-rule').count() === 10, 'ten settings listed');
  await p.check('#rl_crm_pii_guard_on'); await click(p, '.cc-rule[data-key=crm_pii_guard_on] [data-act=cc_rulesave]');
  await p.fill('#rl_crm_export_max_rows', '500'); await click(p, '.cc-rule[data-key=crm_export_max_rows] [data-act=cc_rulesave]');
  await p.selectOption('#rl_crm_mask_style', 'last4'); await click(p, '.cc-rule[data-key=crm_mask_style] [data-act=cc_rulesave]');
  await p.fill('#rl_crm_export_max_rows', 'abc'); await click(p, '.cc-rule[data-key=crm_export_max_rows] [data-act=cc_rulesave]');
  const sr = await calls(p, 'set_rule');
  ok(sr.length === 3 && sr[0].p_key === 'crm_pii_guard_on' && sr[0].p_value === true && sr[1].p_value === 500 && sr[2].p_value === 'last4', 'switch (boolean), number (number) and choice (text) go through set_rule; "abc" is not sent');
  await noOverflow(p, 'settings'); await shot(p, 'crm_settings');
  p = await open('#/crmconsent', { staff: true, o: { pol: POL({ is_owner: false, can_manage_consent: true }) } });
  await click(p, '[data-act=cc_tab][data-v=settings]');
  ok(await p.locator('[data-act=cc_rulesave]').count() === 0, 'a non-owner sees the settings but has no Save button');

  // ---- 8. server without the phases
  p = await open('#/crmconsent', { o: { missing: true } });
  ok(/phase303\.sql and phase304\.sql have not been run/.test(await text(p)), 'missing server functions: a clear message');
  p = await open('#/crmdupes', { o: { missing: true } });
  ok(/phase305\.sql has not been run/.test(await text(p)), 'duplicates: missing server functions, a clear message');

  // ---- 9. duplicates screen
  p = await open('#/crmdupes');
  t = await text(p);
  ok(/Duplicate customers/.test(await p.locator('h1').textContent()) && await p.locator('.dp-pair').count() === 2 && /Very likely/.test(t) && /Weak hint/.test(t) && /same name/.test(t) && /name one letter different/.test(t), 'two pairs with strength and reasons in words');
  ok(await p.locator('.dp-pair[data-a=k1] [data-act=dp_same]').count() === 1 && await p.locator('.dp-pair[data-a=k1] [data-act=dp_not]').count() === 1, 'each pair has "Same person" and "Not the same"');
  await noOverflow(p, 'dupes'); await shot(p, 'crm_dupes');
  await click(p, '.dp-pair[data-a=k1] [data-act=dp_same]');
  await click(p, '[data-act=dp_samego]'); ok((await calls(p, '_crmb_link_customers')).length === 0, 'no reason: not sent');
  await p.check('input[name=dp_main][value=b]'); await p.fill('#dp_why', 'second number on the paper form'); await click(p, '[data-act=dp_samego]');
  let lk = await calls(p, '_crmb_link_customers');
  ok(lk.length === 1 && lk[0].p_primary === 'k3' && lk[0].p_linked === 'k1' && lk[0].p_reason === 'second number on the paper form' && /^[0-9a-f-]{36}$/.test(lk[0].p_client), 'the chosen main customer is the primary; reason and client id sent');
  await click(p, '.dp-pair[data-a=k2] [data-act=dp_not]'); await p.fill('#dp_why', 'ab'); await click(p, '[data-act=dp_notgo]');
  ok((await calls(p, '_crmb_dup_review')).length === 0, 'a short reason is not sent');
  await p.fill('#dp_why', 'different people'); await click(p, '[data-act=dp_notgo]');
  const rv = await calls(p, '_crmb_dup_review'); ok(rv.length === 1 && rv[0].p_not_duplicate === true && rv[0].p_a === 'k2' && rv[0].p_b === 'k4', '"Not the same" is sent with the pair and the reason');
  await click(p, '[data-act=dp_tab][data-v=linked]');
  ok(await p.locator('.dp-link').count() === 2 && /unlinked: mistake/.test(await text(p)) && await p.locator('[data-act=dp_unlink]').count() === 1, 'linked tab: active and undone links, Unlink only on the active one');
  await click(p, '[data-act=dp_unlink]'); await click(p, '[data-act=dp_unlinkgo]'); ok((await calls(p, '_crmb_unlink_customers')).length === 0, 'unlink without a reason is not sent');
  await p.fill('#dp_why', 'they are two people'); await click(p, '[data-act=dp_unlinkgo]');
  const ul = await calls(p, '_crmb_unlink_customers'); ok(ul.length === 1 && ul[0].p_linked === 'k3' && ul[0].p_reason === 'they are two people', 'unlink sent');
  await noOverflow(p, 'linked');
  await click(p, '[data-act=dp_tab][data-v=settings]');
  ok(await p.locator('.dp-rule').count() === 2, 'two duplicate settings'); await p.check('#rl_crm_dup_check_on'); await click(p, '.dp-rule[data-key=crm_dup_check_on] [data-act=dp_rulesave]');
  const dr = await calls(p, 'set_rule'); ok(dr.length === 1 && dr[0].p_key === 'crm_dup_check_on' && dr[0].p_value === true, 'the owner switches the check on');
  p = await open('#/crmdupes', { o: { cand: { off: true, rows: [], total: 0 } } });
  ok(await p.locator('#dp_off').count() === 1 && /switched off/.test(await text(p)), 'switch OFF: the list explains it');
  p = await open('#/crmdupes', { staff: true, o: { pol: POL({ is_owner: false, can_link: false, can_merge: false }) } });
  ok(await p.locator('[data-act=dp_same]').count() === 0 && /you cannot link or dismiss/.test(await text(p)), 'a viewer without the right sees no link buttons');

  // ---- 10. the HOOKED customers screen (scratch copy of customers.js)
  HOOKED = true;
  p = await open('#/customers', { o: { pol: POL({ guard_on: true, contact_ok: false, can_reveal: true, reason_required: true, can_consent: true }), list: DIR.map((r) => Object.assign({}, r, { mobile: '017******' + r.mobile.slice(-2), address: null, masked: true })) } });
  ok((await calls(p, '_crmb_customer_list')).length >= 1 && (await calls(p, 'customer_directory')).length === 0, 'hooked list: read through _crmb_customer_list, not customer_directory');
  t = await text(p); ok(/017\*\*\*\*\*\*01/.test(t) && !/01700000001/.test(t), 'hooked list: the number is shown masked, the full number is nowhere on the screen');
  await click(p, '.cu-row[data-v=k1] [data-act=cu_menu]');
  ok(await p.locator('[data-act=crmc_call]').count() === 1 && await p.locator('a[href^="tel:"]').count() === 0 && await p.locator('a[href*="wa.me"]').count() === 0, 'hooked menu: masked row has an "ask first" Call button, no tel link, no WhatsApp link');
  ok(await p.locator('[data-act=crmc_open]').count() === 1, 'hooked menu: the "Messages (consent)" button is there');
  await noOverflow(p, 'hooked menu'); await shot(p, 'crm_menu');
  await click(p, '[data-act=crmc_call]');
  await click(p, '[data-act=crmc_callgo]'); ok((await calls(p, '_crmb_phone_reveal')).length === 0, 'the call needs a reason (policy says so)');
  p.on('framenavigated', () => {});
  await p.fill('#cl_why', 'order is ready, calling'); await p.evaluate(() => { window.__navTo = null; });
  await click(p, '[data-act=crmc_callgo]');
  const rv2 = await calls(p, '_crmb_phone_reveal'); ok(rv2.length === 1 && rv2[0].p_customer === 'k1' && rv2[0].p_reason === 'order is ready, calling', 'the reveal is asked with the customer and the reason');
  p = await open('#/customers', { o: { pol: POL(), list: DIR } });
  await click(p, '.cu-row[data-v=k1] [data-act=cu_menu]');
  ok(await p.locator('a[href="tel:01700000001"]').count() === 1 && await p.locator('a[href*="wa.me"]').count() === 1 && await p.locator('[data-act=crmc_call]').count() === 0, 'hooked menu at the default (nothing masked): the plain tel link and WhatsApp link, as today');
  await click(p, '[data-act=crmc_open]');
  ok(await p.locator('#crmc_sheet').count() === 1, 'the consent sheet opens from the customer menu');
  p = await open('#/customers', { o: { pol: POL({ can_consent: false, dup_on: false }), list: DIR } });
  await click(p, '.cu-row[data-v=k1] [data-act=cu_menu]');
  ok(await p.locator('[data-act=crmc_open]').count() === 0 && await p.locator('[data-act=dp_open]').count() === 0, 'no consent right and duplicates off: neither extra button');
  p = await open('#/customers', { o: { pol: POL(), list: DIR } });
  await click(p, '.cu-row[data-v=k1] [data-act=cu_open]').catch(() => {});
  await p.evaluate(() => document.querySelector('.cu-row[data-v=k1]').click()); await wait(p, 500);
  ok((await calls(p, '_crmb_customer_profile')).length >= 1 && (await calls(p, 'customer_profile')).length === 0, 'hooked profile: read through _crmb_customer_profile');
  p = await open('#/customers', { o: { missing: true, list: DIR } });
  ok((await calls(p, 'customer_directory')).length >= 1 && await p.locator('.cu-row').count() === 2, 'server without phase304: the hooked list falls back to customer_directory and still works');
  HOOKED = false;
  p = await open('#/customers', { o: { missing: true, list: DIR } });
  ok(await p.locator('.cu-row').count() === 2 && (await calls(p, '_crmb_customer_list')).length === 0, 'the real (unhooked) customers.js is unchanged: it never calls the new functions');

  // ---- 11. POS strip (API) and the hooked pos.js
  HOOKED = true;
  p = await open('#/pos', { o: { pol: POL({ consent_pos_on: true }) } });
  await p.evaluate(() => window.BOS.crmConsent.policy(true)); await wait(p, 200);
  const stripNone = await p.evaluate(() => window.BOS.crmConsent.posStrip('0170')); ok(stripNone === '', 'POS strip: nothing for a half-typed number');
  const strip = await p.evaluate(() => window.BOS.crmConsent.posStrip('01700000001')); ok(/crmc_pos/.test(strip) && /Yes/.test(strip) && /Not asked/.test(strip), 'POS strip: Yes / No / Not asked');
  await p.evaluate(() => { document.body.insertAdjacentHTML('beforeend', '<div id="strip_host" style="position:fixed;bottom:0">' + window.BOS.crmConsent.posStrip('01700000001') + '</div>'); }); await wait(p, 300);
  await p.evaluate(() => document.querySelector('#strip_host [data-v=yes]').click()); await wait(p, 200);
  ok(await p.evaluate(async () => { return (await window.BOS.crmConsent.afterSale('01700000001')) === true; }), 'afterSale returns true after a Yes');
  const sm = await calls(p, '_crmb_consent_set_mobile'); ok(sm.length === 1 && sm[0].p_mobile === '01700000001' && sm[0].p_in === true && sm[0].p_how === 'pos_tick' && sm[0].p_channel === 'sms', 'the tick is written by mobile, way pos_tick');
  ok(await p.evaluate(async () => (await window.BOS.crmConsent.afterSale('01700000001')) === false) && (await calls(p, '_crmb_consent_set_mobile')).length === 1, 'nothing is sent twice (the choice is cleared)');
  p = await open('#/pos', { o: { pol: POL({ consent_pos_on: false }) } });
  await p.evaluate(() => window.BOS.crmConsent.policy(true)); await wait(p, 200);
  ok(await p.evaluate(() => window.BOS.crmConsent.posStrip('01700000001')) === '', 'switch OFF (default): no POS strip');
  // the hooked POS screen draws the strip under the mobile field
  p = await open('#/pos', { o: { pol: POL({ consent_pos_on: true }) } });
  const pcItem = base.tables.items.find((i) => i.unit === 'pc' && i.sell_price);
  await p.click(`.pos-item[data-v="${pcItem.id}"]`); await wait(p, 200); await p.click('[data-act=pos_cart]'); await wait(p, 300);
  await p.click('[data-act=pos_cust_show]'); await wait(p, 200); await p.fill('#cu_mobile', '01700000001'); await wait(p, 900);
  ok(await p.locator('#crmc_pos').count() === 1 && /Agrees to messages\?/.test(await p.locator('#cart_cust').innerText()), 'hooked POS: "Agrees to messages?" appears under the mobile number');
  await noOverflow(p, 'pos strip'); await shot(p, 'crm_pos');
  HOOKED = false;
  p = await open('#/pos', { o: { pol: POL({ consent_pos_on: true }) } });
  await p.click(`.pos-item[data-v="${pcItem.id}"]`); await wait(p, 200); await p.click('[data-act=pos_cart]'); await wait(p, 300);
  await p.click('[data-act=pos_cust_show]'); await wait(p, 200); await p.fill('#cu_mobile', '01700000001'); await wait(p, 900);
  ok(await p.locator('#crmc_pos').count() === 0, 'unhooked pos.js: no strip (today)');

  // ---- 12. print gate
  p = await open('#/crmconsent', { o: { pol: POL({ can_print: false }) } });
  ok(await p.evaluate(async () => (await window.BOS.crmConsent.printGate('customer_list', 3)) === false) && (await calls(p, '_crmb_print_log')).length === 0, 'print refused when the policy says no (nothing logged)');
  p = await open('#/crmconsent', { o: { pol: POL({ can_print: true }) } });
  ok(await p.evaluate(async () => (await window.BOS.crmConsent.printGate('customer_list', 3)) === true) && (await calls(p, '_crmb_print_log')).length === 1 && (await calls(p, '_crmb_print_log'))[0].p_count === 3, 'print allowed: logged with the row count');
  p = await open('#/crmconsent', { o: { missing: true } });
  ok(await p.evaluate(async () => (await window.BOS.crmConsent.printGate('customer_list', 3)) === true), 'server without phase304: printing is not blocked');

  // ---- 13. browser storage blocked: both screens still draw
  p = await open('#/crmconsent', { block: true });
  ok(await p.locator('#cc_head').count() === 1, 'consent screen renders with storage blocked');
  p = await open('#/crmdupes', { block: true });
  ok(await p.locator('.dp-pair').count() === 2, 'duplicates screen renders with storage blocked');
  ok(errors.length === 0, 'no console or page errors: ' + errors.slice(0, 4).join(' | '));
  await br.close(); srv.close();
  log(bad === 0 ? 'ALL OK (' + total + ' checks)' : 'FAILED: ' + bad + ' of ' + total); process.exit(bad === 0 ? 0 : 1);
} catch (e) { console.error('TEST CRASH', e); srv.close(); process.exit(2); } })();
