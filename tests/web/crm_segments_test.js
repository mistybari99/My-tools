// CRM-C web pieces: Customer lists (#/crmlists, web/crm_segments.js) and Customer value (#/crmvalue, web/crm_rfm.js).
// Checks: the hook text (ia.js two records, index.html two script tags, nav.js two grant codes) applied to a SCRATCH COPY of web/ works and registers each screen once in the "cust" group;
// lists: score summary and refresh (capped call), saved lists with Live/Frozen chips, presets, the rule sent to the server (field, comparison, number; all/any), empty value refused before any call,
// count and label chips, "no score yet" notice, customer pages (50 per page, masked phone note), save / freeze / retire / export (reason, CSV, client id), item search, server refusals in plain English,
// saving switched off, no permission; value: overview tiles, outlet filter, labels and their explanation, lapsed (days needed, at risk), top customers sort, profit tab only with the cost right and
// the "cost unknown" flag; English labels only, 360px without horizontal overflow, no console errors.
// Server calls are stand-ins; the SQL is tested in supabase/phase306..308_test.sql. Run: node crm_segments_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), os = require('os'), path = require('path');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const H = require(SP + '/crmc_hooks.js');
const WEB = path.join(SP, '..', '..', 'web');
const SCRATCH = H.apply(WEB, path.join(os.tmpdir(), 'crmc_web_' + process.pid));
const base = C.baseData(SP), PORT = 8617;
const srv = require('http').createServer((q, r) => {
  const u = q.url.split('?')[0]; const f = path.join(SCRATCH, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => {
    if (e) { r.writeHead(404); return r.end(); }
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[path.extname(f)] || 'application/octet-stream' }); r.end(b);
  });
}).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__CR = window.__CR || {}; R.calls = R.calls || [];
 c.rpc = async (fn, args) => {
  if (!/^crmc_/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.err && R.err[fn]) return { data: null, error: { message: R.err[fn], code: 'P0001' } };
  const f = R.fn && R.fn[fn];
  if (f === undefined) return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
  return { data: f, error: null };
 }; return c; }; })();`;
const ME = { view: true, edit: true, run: true, export: true, contact: true, cost: true, owner: true, segments_on: true, export_on: true, export_max: 100, guard_on: false };
const STATUS = { customers: 7, scored: 5, never_scored: 2, stale: 1, oldest: '2026-10-15T05:00:00Z', newest: '2026-10-16T05:00:00Z', mode: 'standard', recent_days: null, frequency_min: null, spend_min: null, missing: ['crm_rfm_recent_days', 'crm_rfm_frequency_min', 'crm_rfm_spend_min'], batch: 2000, schedule_on: false, schedule_hours: null, last_run: null, winback_days: 60 };
const F = (field, kind, ops, label, unit) => ({ field, kind, ops, label, unit: unit || null, lo: null, hi: null });
const CAT = { fields: [F('days_since_last', 'num', ['eq', 'ne', 'gt', 'ge', 'lt', 'le', 'between'], 'Days since last visit', 'days'), F('orders_total', 'num', ['eq', 'ne', 'gt', 'ge', 'lt', 'le', 'between'], 'Orders, all time', 'orders'),
  F('spend_12m', 'num', ['eq', 'ne', 'gt', 'ge', 'lt', 'le', 'between'], 'Spent in the last 12 months', '৳'), F('birthday_in_days', 'within', ['le'], 'Birthday within the next days', 'days'),
  F('birthday_this_month', 'bool', ['is'], 'Birthday is this month'), F('opted_in', 'optin', ['is'], 'Agreed to messages'), F('tier', 'set_text', ['in', 'not_in'], 'Customer tier'),
  F('source', 'set_text', ['in', 'not_in'], 'How they came to us'), F('rfm_label', 'set_text', ['in', 'not_in'], 'Customer label (score)'), F('outlet', 'set_int', ['in', 'not_in'], 'Bought at outlet (last 12 months)'),
  F('bought_item', 'items', ['in'], 'Bought any of these items')],
  tiers: [{ code: 'walkin', name: 'Walk-in' }, { code: 'gold', name: 'Gold' }], types: [{ code: 'retail', name: 'Retail' }], groups: [], outlets: [{ id: 1, name: 'Main' }, { id: 2, name: 'Branch 2' }],
  labels: ['Champion', 'At risk', 'At-risk', 'One-time'], channels: ['any', 'sms', 'whatsapp'] };
const SEGS = [{ id: 1, name: 'test_list_lapsed', kind: 'dynamic', rule: { match: 'all', conditions: [{ field: 'days_since_last', op: 'gt', value: 60 }] }, note: 'not seen', active: true, last_count: 12, last_count_at: '2026-10-16T05:00:00Z' },
  { id: 2, name: 'test_list_frozen', kind: 'list', rule: null, note: null, active: true, member_count: 80, frozen_at: '2026-10-15T05:00:00Z', last_count: 80, last_count_at: '2026-10-15T05:00:00Z' }];
const row = (i, o) => Object.assign({ customer_id: 'c' + i, name: 'test_cust_' + i, mobile: '017******' + String(10 + i).slice(-2), tier: 'gold', last_visit: '2026-08-01', days_since_last: 76, orders_total: 3, orders_12m: 2, spend_12m: 450, lifetime_spend: 900, avg_bill: 300, due_amount: 0, label: 'At-risk', top_items: [] }, o || {});
const PAGE1 = { total: 120, limit: 50, offset: 0, masked: true, rows: Array.from({ length: 50 }, (_, i) => row(i)) };
const PAGE2 = { total: 120, limit: 50, offset: 50, masked: true, rows: Array.from({ length: 50 }, (_, i) => row(50 + i)) };
const PREV = { count: 3, total_customers: 7, scored_customers: 5, unscored_customers: 2, members_scored: 2, members_unscored: 1, over_cap: false, cap: 5000, by_label: { 'At-risk': 1, Inactive: 1 }, lifetime_spend: 930, spend_12m: 430, oldest_score: '2026-10-15T05:00:00Z', kind: 'dynamic' };
const OV = { customers_scored: 5, buyers: 4, repeat_buyers: 1, repeat_rate_pct: 33.3, active_12m: 3, repeat_12m: 1, repeat_rate_12m_pct: 40.0, new_12m: 2, avg_lifetime_value: 431.67, median_lifetime_value: 425, avg_orders: 1.5, spend_12m: 2090, top_tenth_share_pct: 38.6,
  owing_customers: 1, owed_total: 600, lapsed: 2, at_risk: 1, by_label: { Champion: 1 }, total_customers: 7, unscored_customers: 2, mode: 'standard', winback_days: 60, outlet: null, note: 'Spend is net of returns. Rates count customers who have bought at least once.' };
const SUM = { mode: 'standard', recent_days: null, frequency_min: null, spend_min: null, customers_scored: 5, labels: [{ label: 'Champion', customers: 2, share_pct: 40.0, avg_lifetime_spend: 900, spend_12m: 1800, avg_days_since_last: 5 }, { label: 'One-time', customers: 3, share_pct: 60.0, avg_lifetime_spend: 100, spend_12m: 300, avg_days_since_last: 40 }],
  explain: 'Standard labels, the same cut-offs as the Customer value report: Champion = 3 or more orders in 12 months and seen within 30 days.' };
const PROFIT = { from: '2026-09-17', to: '2026-10-16', customers: 2, limit: 50, offset: 0, all_revenue: 1730, customer_revenue: 1660, masked: false, note: 'Only sales linked to a customer are listed.',
  rows: [{ customer_id: 'c1', name: 'test_cust_due', mobile: '01700000008', revenue: 1000, costed_revenue: 1000, cogs: 400, margin: 600, margin_pct: 60.0, unknown_cost_revenue: 0, cost_partial: false },
         { customer_id: 'c2', name: 'test_cust_champ', mobile: '01700000001', revenue: 600, costed_revenue: 220, cogs: 200, margin: 20, margin_pct: 9.1, unknown_cost_revenue: 380, cost_partial: true }] };
const FN = { crmc_me: ME, crmc_metrics_status: STATUS, crmc_field_catalog: CAT, crmc_segments_list: SEGS, crmc_metrics_refresh: { dry: false, processed: 2000, remaining: 3000, batch: 2000 }, crmc_preview: PREV, crmc_members: PAGE1,
  crmc_segment_save: { id: 3, name: 'test_new' }, crmc_segment_freeze: { id: 4, name: 'test_frozen_new' }, crmc_segment_retire: { id: 1, active: false }, crmc_item_search: [{ id: 'aaaaaaaa-0000-0000-0000-0000000000a1', code: 'test_it_a', name: 'test item a' }],
  crmc_export: { log_id: 5, columns: ['name', 'mobile'], rows: [['test_cust_1', '017******11']], total: 1, mobile_masked: true }, crmc_overview: OV, crmc_rfm_summary: SUM, crmc_rfm_list: PAGE1, crmc_value_list: PAGE1, crmc_lapsed: PAGE1, crmc_profit: PROFIT };

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, total = 0; const ok = (c, m) => { total++; if (!c) { bad++; log('FAIL:', m); } };
  async function page(hash, extra, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept(o.prompt === undefined ? 'test reason' : o.prompt));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const fn = Object.assign({}, FN, extra || {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__CR={calls:[],err:${JSON.stringify(o.err || {})},fn:${JSON.stringify(fn)}};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__CR.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const toastText = (p) => p.evaluate(() => (document.querySelector('#toast') || {}).textContent || '');
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // ---- hook text: registered once, in the customers group, with a script tag each, grants listed in nav.js
  let p = await page('#/crmlists');
  const reg = await p.evaluate(() => ({ lists: BOS.IA.filter((r) => r.id === 'crmlists').length, value: BOS.IA.filter((r) => r.id === 'crmvalue').length, g: (BOS.IA.find((r) => r.id === 'crmlists') || {}).group, g2: (BOS.IA.find((r) => r.id === 'crmvalue') || {}).group }));
  ok(reg.lists === 1 && reg.value === 1 && reg.g === 'cust' && reg.g2 === 'cust', 'each screen registered once in group cust: ' + JSON.stringify(reg));
  const htmlText = fs.readFileSync(SCRATCH + '/index.html', 'utf8');
  ok((htmlText.match(/crm_segments\.js/g) || []).length === 1 && (htmlText.match(/crm_rfm\.js/g) || []).length === 1, 'script tags once each');
  ok((fs.readFileSync(SCRATCH + '/nav.js', 'utf8').match(/'crm_view', 'crm_settings_edit'/g) || []).length === 2, 'nav.js asks for the two CRM grants in both lists');

  // ---- Customer lists: head, saved lists
  let t = await text(p);
  ok(/Customer lists/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('#cs_sum').textContent() === '5 of 7 customers scored' && /1 need a refresh/.test(t), 'score summary: ' + await p.locator('#cs_sum').textContent());
  ok(await p.locator('#cs_unscored').count() === 1 && /2 customers have no score yet/.test(t), 'the "no score yet" notice');
  ok(await p.locator('.cs-seg').count() === 2 && /Frozen/.test(t) && /Live/.test(t) && /80 customers, frozen/.test(t) && /Last count 12/.test(t), 'two saved lists with Live and Frozen chips');
  ok(await p.locator('.cs-seg').nth(0).locator('details button').count() === 4 && await p.locator('.cs-seg').nth(1).locator('details button').count() === 2, 'More folds: live list has Freeze, Change rules, Export, Retire; frozen has Export, Retire');
  await noOverflow(p, 'lists'); await p.screenshot({ path: SP + '/crmc_lists.png', fullPage: true });
  await p.click('#cs_head [data-act=cs_refresh]'); await wait(p, 500);
  const rf = await calls(p, 'crmc_metrics_refresh');
  ok(rf.length === 1 && rf[0].p_dry === false, 'refresh call: ' + JSON.stringify(rf));
  ok(/Scored 2000, 3000 left: press again/.test(await toastText(p)), 'toast says what is left: ' + await toastText(p));
  await p.click('[data-act=cs_count][data-v="1"]'); await wait(p, 400);
  ok(/test_list_lapsed: 3 customers/.test(await toastText(p)), 'count now: ' + await toastText(p));
  ok((await calls(p, 'crmc_preview')).some((c) => c.p_segment === 1 && c.p_rule === null), 'count of a saved list asks by id');
  await p.click('[data-act=crs_open][data-v="2"]'); await wait(p, 500);
  let c1 = await calls(p, 'crmc_members');
  ok(c1.length === 1 && c1[0].p_segment === 2 && c1[0].p_rule === null && c1[0].p_offset === 0 && c1[0].p_limit === 50, 'open a saved list: ' + JSON.stringify(c1));
  t = await text(p);
  ok(await p.locator('.cs-mem').count() === 50 && /120 customers · showing 1 to 50/.test(t) && /phone numbers are hidden for you/.test(t) && /017\*{6}10/.test(t), 'a page of 50 with the masked-phone note');
  await noOverflow(p, 'members sheet');
  await p.click('[data-act=cs_pg][data-v="50"]', { timeout: 3000 }).catch(() => {}); await wait(p, 300);

  // ---- New list builder
  p = await page('#/crmlists', { crmc_members: PAGE2 });
  await p.click('[data-act=crs_tab][data-v=build]'); await wait(p, 200);
  ok(await p.locator('#cs_presets button').count() === 10, 'ten presets');
  await p.click('[data-act=cs_preset][data-v=notseen]'); await wait(p, 300);
  ok(await p.locator('.cs-cond').count() === 2 && await p.locator('#cs_0_field').inputValue() === 'days_since_last' && await p.locator('#cs_0_op').inputValue() === 'gt' && await p.locator('#cs_0_v').inputValue() === '60', 'preset: not seen, taking the owner days (60) as the starting number');
  await p.fill('#cs_0_v', ''); await p.click('#cs_preview'); await wait(p, 300);
  ok((await calls(p, 'crmc_preview')).length === 0 && /Type a number/.test(await toastText(p)), 'empty number refused on the screen, no server call: ' + await toastText(p));
  await p.fill('#cs_0_v', '30'); await p.click('#cs_preview'); await wait(p, 500);
  let pv = await calls(p, 'crmc_preview');
  ok(pv.length === 1 && JSON.stringify(pv[0].p_rule) === JSON.stringify({ match: 'all', conditions: [{ field: 'days_since_last', op: 'gt', value: 30 }, { field: 'orders_total', op: 'ge', value: 1 }] }) && pv[0].p_segment === null, 'rule sent to the server: ' + JSON.stringify(pv));
  t = await text(p);
  ok(await p.locator('#cs_count').textContent() === '3 customers' && /At-risk 1/.test(t) && /Inactive 1/.test(t) && /Total spent ৳930/.test(t), 'count and label chips');
  ok(await p.locator('#cs_unsc_note').count() === 1 && /1 of them have no score yet/.test(t), 'members without a score are flagged');
  await noOverflow(p, 'builder'); await p.screenshot({ path: SP + '/crmc_build.png', fullPage: true });
  await p.click('#cs_result [data-act=cs_members]'); await wait(p, 500);
  c1 = await calls(p, 'crmc_members');
  ok(c1.length === 1 && c1[0].p_rule.conditions.length === 2 && c1[0].p_segment === null, 'show customers of the rule');
  await p.click('[data-act=closesheet]'); await wait(p, 200);
  // the match switch and a bool / channel condition
  await p.click('[data-act=cs_add]'); await wait(p, 200);
  await p.selectOption('#cs_2_field', 'opted_in'); await wait(p, 300);
  await p.selectOption('#cs_2_v', 'no'); await p.selectOption('#cs_2_ch', 'sms'); await p.selectOption('#cs_match', 'any');
  await p.click('#cs_preview'); await wait(p, 400);
  pv = await calls(p, 'crmc_preview'); const last = pv[pv.length - 1].p_rule;
  ok(last.match === 'any' && last.conditions[2].field === 'opted_in' && last.conditions[2].value === false && last.conditions[2].channel === 'sms', 'agreed-to-messages condition: ' + JSON.stringify(last.conditions[2]));
  await p.click('[data-act=cs_del][data-i="2"]'); await wait(p, 200);
  ok(await p.locator('.cs-cond').count() === 2, 'rule removed');
  // between
  await p.selectOption('#cs_0_op', 'between'); await wait(p, 100);
  // tier chips
  await p.click('[data-act=cs_preset][data-v=tier]'); await wait(p, 300);
  await p.click('.cs-cond [data-act=cs_sel][data-v=gold]'); await wait(p, 200);
  await p.click('#cs_preview'); await wait(p, 400);
  pv = await calls(p, 'crmc_preview'); ok(JSON.stringify(pv[pv.length - 1].p_rule.conditions[0]) === JSON.stringify({ field: 'tier', op: 'in', value: ['gold'] }), 'tier chips: ' + JSON.stringify(pv[pv.length - 1].p_rule));
  // outlet chips send numbers
  await p.click('[data-act=cs_preset][data-v=outlet]'); await wait(p, 300);
  await p.click('.cs-cond [data-act=cs_sel][data-v="2"]'); await wait(p, 200); await p.click('#cs_preview'); await wait(p, 400);
  pv = await calls(p, 'crmc_preview'); ok(JSON.stringify(pv[pv.length - 1].p_rule.conditions[0].value) === '[2]', 'outlet chips send numbers');
  // item search
  await p.click('[data-act=cs_preset][data-v=item]'); await wait(p, 300);
  await p.fill('#cs_0_q', 'test item'); await p.click('[data-act=cs_itemfind]'); await wait(p, 400);
  ok((await calls(p, 'crmc_item_search'))[0].p_q === 'test item' && await p.locator('[data-act=cs_itemadd]').count() === 1, 'item search');
  await p.click('[data-act=cs_itemadd]'); await wait(p, 200); await p.fill('#cs_0_days', '90'); await p.click('#cs_preview'); await wait(p, 400);
  pv = await calls(p, 'crmc_preview'); const ic = pv[pv.length - 1].p_rule.conditions[0];
  ok(ic.field === 'bought_item' && ic.value[0] === 'aaaaaaaa-0000-0000-0000-0000000000a1' && ic.within_days === 90, 'item rule: ' + JSON.stringify(ic));
  // source words
  await p.selectOption('#cs_0_field', 'source'); await wait(p, 300); await p.fill('#cs_0_txt', 'Facebook, walk-in'); await p.click('#cs_preview'); await wait(p, 400);
  pv = await calls(p, 'crmc_preview'); ok(JSON.stringify(pv[pv.length - 1].p_rule.conditions[0].value) === '["Facebook","walk-in"]', 'source words split by commas');
  // save / freeze
  await p.click('#cs_result [data-act=cs_savesheet]'); await wait(p, 300);
  await p.fill('#cs_name', ''); await p.click('[data-act=cs_save]'); await wait(p, 300);
  ok((await calls(p, 'crmc_segment_save')).length === 0 && /Write a name/.test(await toastText(p)), 'save without a name refused on the screen');
  await p.fill('#cs_name', 'test_new'); await p.fill('#cs_note', 'for a call'); await p.click('[data-act=cs_save]'); await wait(p, 600);
  const sv = await calls(p, 'crmc_segment_save');
  ok(sv.length === 1 && sv[0].p_name === 'test_new' && sv[0].p_id === null && /^[0-9a-f-]{36}$/.test(sv[0].p_client) && sv[0].p_note === 'for a call' && sv[0].p_rule.conditions[0].field === 'source', 'save call with a client id: ' + JSON.stringify(sv));
  p = await page('#/crmlists'); await p.click('[data-act=crs_tab][data-v=build]'); await p.click('[data-act=cs_preset][data-v=onetime]'); await p.click('#cs_preview'); await wait(p, 400);
  await p.click('#cs_result [data-act=cs_freezesheet]'); await wait(p, 300); await p.fill('#cs_fname', 'test_frozen_new'); await p.click('[data-act=cs_freeze]'); await wait(p, 500);
  const fz = await calls(p, 'crmc_segment_freeze'); ok(fz.length === 1 && fz[0].p_name === 'test_frozen_new' && fz[0].p_segment === null && fz[0].p_rule.conditions[0].value === 1, 'freeze call: ' + JSON.stringify(fz));
  // retire and export of saved lists
  await p.click('[data-act=crs_tab][data-v=lists]'); await wait(p, 200);
  await p.locator('.cs-seg').nth(0).locator('details summary').click(); await p.click('[data-act=cs_retire][data-v="1"]'); await wait(p, 500);
  const rt = await calls(p, 'crmc_segment_retire'); ok(rt.length === 1 && rt[0].p_id === 1 && rt[0].p_active === false && rt[0].p_reason === 'test reason', 'retire sends the reason');
  await p.locator('.cs-seg').nth(0).locator('details summary').click(); await p.click('[data-act=cs_exportsaved][data-v="1"]'); await wait(p, 600);
  const ex = await calls(p, 'crmc_export'); ok(ex.length === 1 && ex[0].p_segment === 1 && ex[0].p_rule === null && ex[0].p_reason === 'test reason' && /^[0-9a-f-]{36}$/.test(ex[0].p_client), 'export sends segment, reason, client id');
  ok(/Exported 1 customers \(phone numbers hidden for you\)/.test(await toastText(p)), 'export toast: ' + await toastText(p));

  // ---- refusals in plain English, switched-off saving, no permission
  p = await page('#/crmlists', {}, { err: { crmc_preview: 'bad_rule:bad_value', crmc_segment_save: 'segments_off', crmc_segment_freeze: 'over_cap:6000' } });
  await p.click('[data-act=crs_tab][data-v=build]'); await p.click('[data-act=cs_preset][data-v=onetime]'); await p.click('#cs_preview'); await wait(p, 400);
  ok(/A value is missing or not allowed/.test(await toastText(p)), 'bad rule in English: ' + await toastText(p));
  p = await page('#/crmlists', {}, { err: { crmc_segment_freeze: 'over_cap:6000' } });
  await p.click('[data-act=crs_tab][data-v=build]'); await p.click('[data-act=cs_preset][data-v=onetime]'); await p.click('#cs_preview'); await wait(p, 400);
  await p.click('#cs_result [data-act=cs_freezesheet]'); await p.fill('#cs_fname', 'test_x'); await p.click('[data-act=cs_freeze]'); await wait(p, 400);
  ok(/6000 customers, more than the largest list that can be frozen/.test(await toastText(p)), 'over cap in English: ' + await toastText(p));
  p = await page('#/crmlists', { crmc_me: Object.assign({}, ME, { segments_on: false, export_on: false, export: false, run: false, owner: false }) });
  t = await text(p);
  ok(await p.locator('#cs_off').count() === 1 && /Saving lists is switched off/.test(t) && await p.locator('#cs_head [data-act=cs_refresh]').count() === 0, 'saving off notice, no refresh button without the right');
  await p.click('[data-act=crs_tab][data-v=build]'); await p.click('[data-act=cs_preset][data-v=onetime]'); await p.click('#cs_preview'); await wait(p, 400);
  ok(await p.locator('#cs_result [data-act=cs_savesheet]').isDisabled() && await p.locator('#cs_result [data-act=cs_freezesheet]').isDisabled() && await p.locator('#cs_result [data-act=cs_exportnew]').count() === 0, 'save and freeze disabled, no export button while off');
  p = await page('#/crmlists', { crmc_me: { view: false, edit: false, run: false, export: false, contact: false, cost: false, owner: false } });
  ok(await p.locator('#cs_noperm').count() === 1 && await p.locator('#cs_head').count() === 0, 'no permission: nothing but a sentence');

  // ---- Customer value
  p = await page('#/crmvalue');
  t = await text(p);
  ok(/Customer value/.test(await p.locator('h1').textContent()) && await p.locator('#cv_tabs button').count() === 5, 'title and five tabs (Profit shown with the cost right)');
  ok(await p.locator('#cv_repeat b').textContent() === '33.3%' && await p.locator('#cv_buyers b').textContent() === '4' && /৳432/.test(await p.locator('#cv_ltv').innerText()) && await p.locator('#cv_atrisk b').textContent() === '1', 'overview tiles');
  ok(/Spend is net of returns/.test(await p.locator('#cv_note').innerText()) && /Scores last updated/.test(t), 'note and freshness strip');
  await noOverflow(p, 'value overview'); await p.screenshot({ path: SP + '/crmc_value.png', fullPage: true });
  await p.selectOption('#cv_outlet', '2'); await wait(p, 400);
  const ov = await calls(p, 'crmc_overview'); ok(ov[ov.length - 1].p_outlet === 2, 'outlet filter asks the server');
  await p.click('[data-act=cv_tab][data-v=labels]'); await wait(p, 400);
  t = await text(p);
  ok(await p.locator('#cv_std').count() === 1 && /standard labels/i.test(t) && /Champion/.test(t) && await p.locator('.cv-label').count() === 2 && /same cut-offs as the Customer value report/.test(await p.locator('#cv_explain').innerText()), 'labels with the standard-mode notice and explanation');
  await p.click('[data-act=cv_label][data-v=Champion]'); await wait(p, 400);
  const rl = await calls(p, 'crmc_rfm_list'); ok(rl.length === 1 && rl[0].p_label === 'Champion' && rl[0].p_offset === 0, 'label list call');
  ok(await p.locator('.cv-mem').count() === 50 && /120 customers/.test(await p.locator('#cv_pg_sum').innerText()), 'page of 50');
  await p.click('[data-act=cv_page][data-v="50"]'); await wait(p, 400);
  const rl2 = await calls(p, 'crmc_rfm_list'); ok(rl2.length === 2 && rl2[1].p_offset === 50, 'next 50');
  await p.click('[data-act=cv_tab][data-v=lapsed]'); await wait(p, 400);
  ok(await p.locator('#cv_days').inputValue() === '60', 'lapsed days prefilled from the owner setting');
  await p.fill('#cv_days', ''); await p.click('#cv_go'); await wait(p, 300);
  ok(/Type how many days first/.test(await toastText(p)) && (await calls(p, 'crmc_lapsed')).length === 0, 'days needed first');
  await p.fill('#cv_days', '90'); await p.click('#cv_go'); await wait(p, 400);
  let lp = await calls(p, 'crmc_lapsed'); ok(lp.length === 1 && lp[0].p_days === 90 && lp[0].p_kind === 'lapsed', 'lapsed call: ' + JSON.stringify(lp));
  await p.click('[data-act=cv_kind][data-v=at_risk]'); await wait(p, 400);
  lp = await calls(p, 'crmc_lapsed'); ok(lp[lp.length - 1].p_kind === 'at_risk' && lp[lp.length - 1].p_days === null, 'at-risk call');
  await p.click('[data-act=cv_tab][data-v=top]'); await wait(p, 400);
  await p.selectOption('#cv_sort', 'orders'); await wait(p, 400);
  const vl = await calls(p, 'crmc_value_list'); ok(vl[vl.length - 1].p_sort === 'orders', 'sort asks the server');
  await p.click('[data-act=cv_tab][data-v=profit]'); await wait(p, 300);
  ok(await p.locator('#cv_from').inputValue() !== '' && await p.locator('#cv_to').inputValue() !== '', 'profit dates default to the last 30 days');
  await p.click('#cv_pgo'); await wait(p, 500);
  t = await text(p); const pf = await calls(p, 'crmc_profit');
  ok(pf.length === 1 && pf[0].p_sort === 'margin', 'profit call');
  ok(await p.locator('.cv-profit').count() === 2 && /some cost unknown/.test(t) && /profit ৳600 \(60\.0%\)/.test(t) && /৳380 sold with no known cost/.test(t) && /৳1,660 of ৳1,730 sold to named customers/.test(t), 'profit rows with the unknown-cost flag');
  await noOverflow(p, 'profit'); await p.screenshot({ path: SP + '/crmc_profit.png', fullPage: true });
  p = await page('#/crmvalue', { crmc_me: Object.assign({}, ME, { cost: false, run: false, owner: false }) });
  ok(await p.locator('#cv_tabs button').count() === 4 && await p.locator('[data-act=cv_tab][data-v=profit]').count() === 0 && await p.locator('#cv_refresh').count() === 0, 'no Profit tab and no refresh button without the rights');
  p = await page('#/crmvalue', { crmc_me: { view: false, edit: false, run: false, export: false, contact: false, cost: false, owner: false } });
  ok(await p.locator('#cv_noperm').count() === 1, 'no permission sentence');
  p = await page('#/crmvalue', { crmc_overview: Object.assign({}, OV, { lapsed: null, winback_days: null }) });
  await p.locator('#cv_pane details summary').click(); ok(/set days/.test(await p.locator('#cv_lapsed').innerText()), 'lapsed tile says the days must be set while the setting is blank');

  ok(!/[ঀ-৲৴-৿]/.test(await text(p)), "English labels only (the taka sign is a currency mark)");
  ok(errors.length === 0, 'console errors: ' + errors.join(' | '));
  await br.close(); srv.close(); fs.rmSync(SCRATCH, { recursive: true, force: true });
  log(bad ? 'crm_segments_test: ' + bad + ' FAILED of ' + total : 'crm_segments_test: all ' + total + ' assertions passed (0 failures, no console errors)');
  process.exit(bad ? 1 : 0);
} catch (e) { console.log('crm_segments_test crashed:', e); try { srv.close(); fs.rmSync(SCRATCH, { recursive: true, force: true }); } catch (x) {} process.exit(2); } })();
