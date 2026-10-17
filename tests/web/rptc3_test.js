// RPT-C3 web screens: campaigns.js, couponuse.js, auditreports.js, forecast.js (rptkit.js), the till hooks in pos.js, the 18-1 campaign field, ia.js placement, the CSV rule, 360px layout.
// Server answers are canned stand-ins in the shape the SQL returns (the SQL itself is tested in supabase/phase458..468_test.sql). Run: node rptc3_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = 8731, srv = C.serve(PORT);
const WEB = process.env.BOS_WEB_ROOT || '/home/user/My-tools/web';
const TD = new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const R = {
  mkt_spend_by_campaign: { rows: [{ campaign_code: 'ca', name_en: 'Alpha promo', name_bn: 'অ্যালফা', spend: 300, lines: 1, budget: 1000, budget_used_pct: 30, nonpay_value: null, first_day: TD, last_day: TD }, { campaign_code: null, name_en: null, spend: 100, lines: 1, budget: null, budget_used_pct: null, nonpay_value: 80 }],
    by_month: [{ month: TD.slice(0, 8) + '01', campaign_code: 'ca', spend: 300 }], totals: { spend: 400, nonpay_value: null, lines: 2 }, coverage: { pct: 50, spend_with_campaign_pct: 75 }, notes: ['spend_paid_only', 'no_such_code_zz'], basis: 'paid 18-1 lines' },
  mkt_spend_lines: { rows: [{ day: TD, head: '1', head_name: 'Online ads', amt: 300, source: 'bank', campaign_txt: null, receipt: 'R1', status: 'approved', in_books: false }] },
  mkt_campaign_performance: { rows: [{ campaign_code: 'ca', name_en: 'Alpha promo', tagged_bills: 2, revenue_net: 300, discount_given: 0, cogs: null, contribution_costed: null, cost_coverage_pct: null, spend: 300, after_spend_costed: null, identified_customers: 1 }], totals: { revenue_net: 300 }, coverage: { tagged_pct: 60, tagged_revenue_pct: 49 }, notes: ['cost_hidden', 'tagged_sales_only'], basis: 'b' },
  mkt_roi: { rows: [{ campaign_code: 'ca', name_en: 'Alpha promo', roi_pct_costed_part: null, why_no_roi: 'cost_hidden', revenue_per_taka: 1, revenue_net: 300, spend: 300 }], unassigned_spend_not_in_roi: 100, coverage: { tagged_pct: 60 }, notes: ['unassigned_spend_not_in_roi'] },
  mkt_repeat_after_promo: { data_needed: ['mkt_repeat_days'], rows: [], notes: ['window_days_not_set'], basis: 'x' },
  mkt_post_preview: { rows: [{ entry_id: 'e1', serial: 5, rev_no: 1, location_id: 1, line_no: 1, day: TD, head: '1', amt: 300, source: 'bank', cls: 'possible_duplicate', why: 'look-alike', campaign_code: null, decision: null }, { entry_id: 'e1', serial: 5, rev_no: 1, location_id: 1, line_no: 2, day: TD, head: '3', amt: 150, source: 'mobile', cls: 'to_post', campaign_code: 'ca' }], counts: {}, setting: { on: true, from: '2026-09-01', accounting_start: '2026-09-01', mappings_ok: true }, notes: ['imprest_never_posted_here'], basis: 'b' },
  mkt_post_run: { dry: true, posted: 1, reversed: 0, period_locked: 0, errors: [] },
  mkt_coupon_usage: { crmf_installed: false, validated: [], typed: [{ offer_code: 'TESTOFFER10', bills: 1, discount_given: 0, net: 200, campaign_code: 'ca' }], totals: { validated_uses: 0, typed_bills: 1 }, notes: ['crmf_not_installed', 'typed_codes_not_validated'], basis: 'b' },
  aud_log_page: { rows: Array.from({ length: 3 }, (_, i) => ({ id: 100 - i, at: TD + 'T04:00:00Z', staff_id: 'owner1', action: 'insert', table_name: 'sales', record_id: 'r' + i, detail: { new: { a: 1 } } })), total: 120, limit: 50, offset: 0, notes: ['owner_only', 'append_only'], basis: 'b' },
  aud_void_register: { rows: [{ module: 'sale', kind: 'void', ref: 'Receipt 9', rec_date: TD, event_at: null, amount: 100, who: 'test_staff', reason: 'test', location_id: 1 }, { module: 'journal', kind: 'reversal', ref: 'x', rec_date: TD, event_at: TD + 'T05:00:00Z', amount: 50, who: 'o', reason: 'Reversal: x', location_id: 1 }], total: 2, notes: ['time_not_captured_where_the_module_stores_none', 'salary_modules_hidden'] },
  aud_cost_gaps: { sections: { item_no_cost: { total: 1, rows: [{ code: 'C3-NOCOST', name_en: 'test_nocost', item_type: 'resale' }] }, fg_no_recipe: { total: 0, rows: [] }, recipe_waste_missing: { total: 0, rows: [] }, ingredient_no_cost: { total: 0, rows: [], cost_hidden: true }, batch_no_expiry: { total: 2, rows: [{ batch_no: 'B1', code: 'W1D-FG', qty_remaining: 2, made_at: TD + 'T01:00:00Z', location_id: 1 }] } }, notes: ['ingredient_costs_need_the_cost_right'] },
  fc_sales_forecast: { rows: [{ date: TD, weekday: 1, is_today: true, n_obs: 2, expected: 350, low: 300, high: 400, festival: null, festival_uplift_pct: null, expected_with_uplift: null }, { date: TD.slice(0, 8) + '28', weekday: 2, n_obs: 0, expected: null, low: null, high: null }],
    totals: { expected: 350, low: 300, high: 400, expected_with_uplift: null, days_without_estimate: 1 }, assumptions: { window_days: 28, window_from: '2026-09-19', window_to: '2026-10-16', first_sale_date: '2026-09-26', effective_window_days: 21, trading_days: 6, ordinary_trading_days: 5, festival_days_left_out: 1, data_coverage_pct: 28.6, same_weekday_days_used: { 1: 2, 2: 3 }, revenue_basis: 'net of returns', uplift_entered_by_owner: false, festival_rows: 2 },
    notes: ['range_is_lowest_and_highest_past_same_weekday_not_a_confidence_interval', 'no_probability_claimed', 'history_shorter_than_the_window'], basis: 'Average of the same weekday over the last 28 days' },
  fc_cash_calendar: { rows: [{ date: TD, in: 300, out: 0, transfers: 1000, net_known: 300, items: [{ kind: 'order_balance', dir: 'in', amount: 300, ref: 'Order #1', assumed: false }, { kind: 'salary_assumed', dir: 'out', amount: 5000, ref: 'Same as last', assumed: true }] }], buckets: { overdue_in: 200, overdue_out: 350, date_unknown_in: 0, date_unknown_out: 100 }, totals: { in: 300, out: 400 }, assumptions: ['salary repeats the last payroll run on day 5'], coverage: { salary_pay_day_set: true, customer_credit_days_column: false }, notes: ['customers_have_no_credit_days_so_dues_are_undated'] },
  fc_scenario: { lines: [{ key: 'net_sales', baseline: 1000, scenario: 1155, delta: 155, delta_pct: 15.5 }, { key: 'result_after_costs', baseline: null, scenario: null, delta: null, delta_pct: null }], result_missing: ['cost_coverage_not_full', 'fixed_cost_not_set'], notes: ['arithmetic_on_typed_percents_not_a_forecast'] },
  fc_seasonal: { festivals: [{ festival_id: 1, name_en: 'Test fest', name_bn: 'টেস্ট', start: '2026-10-03', trading_days: 1, avg_per_trading_day: 500, baseline_trading_days: 1, baseline_avg_per_trading_day: 400, observed_difference_pct: 25, owner_uplift_pct: 30 }, { festival_id: 2, name_en: 'Empty fest', start: '2025-12-25', trading_days: 0, avg_per_trading_day: null, baseline_trading_days: 0, baseline_avg_per_trading_day: null, observed_difference_pct: null, owner_uplift_pct: null }], grouped: [], upcoming: [], by_month: [], notes: ['observed_differences_are_history_not_promises'] },
  festival_list: { rows: [{ id: 1, name_bn: 'টেস্ট উৎসব', name_en: 'Test fest', start_date: '2026-12-25', end_date: '2026-12-26', uplift_pct: 20, active: true }] },
  festival_save: { ok: true, id: 2 }, mkt_campaign_save: { status: 'added', value_code: 'newc' }, mkt_tag_sale: { ok: true }, mkt_tag_sale_client: { ok: true }, mkt_post_decide: { ok: true }, rptc3_export_log: null,
  mkt_active_campaigns: [{ code: 'ca', name_bn: 'অ্যালফা', name_en: 'Alpha promo', start: null, end: null }],
};
const EXTRA3 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M = window.__M || { calls: [] };
 const R3 = window.__R3 = Object.assign({ data: ${JSON.stringify(R)}, err: {}, delay: 0 }, window.__R30 || {});
 c.rpc = async (fn, args) => { if (!(fn in R3.data) && !(fn in R3.err)) return rpc(fn, args);
   M.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]); if (R3.err[fn]) return { data: null, error: R3.err[fn] }; const d = R3.data[fn]; return { data: typeof d === 'function' ? d(args) : JSON.parse(JSON.stringify(d === undefined ? null : d)), error: null }; };
 const from = c.from; c.from = (t) => { if (t === 'option_lists') { const b = from(t); const sel = b.select.bind(b); b.select = (...x) => { sel(...x); return b; }; } return from(t); };
 return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; let n = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => (o.prompt ? d.accept(o.prompt) : d.accept()));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA3 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o); data.tables.locations = data.tables.locations || [];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__R30=${JSON.stringify(o.r3 || {})};${o.owner === false ? 'window.__OWNER=false;' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1200); return p;
  }
  const wait = (p, ms = 300) => p.waitForTimeout(ms);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow at 360px: ' + m);
  const txt = (p, s) => p.textContent(s);

  // ---------- 1. spend by campaign: stats, null = "Data not captured", notes translated, drill, CSV after the server logged it ----------
  let p = await open({}, '#/campaigns'); if (process.env.DEBUG) console.log((await p.textContent('#app')).slice(0, 500), errors);
  await p.click('[data-act=cp_tab][data-v=spend]'); await wait(p, 500);
  ok(/400/.test(await txt(p, '#cp_stats')), 'total spend 400 shown');
  ok(await p.locator('#cp_stats .chip.warn').count() === 1, 'the nonpay value (null) shows ONE "Data not captured" chip, not 0');
  ok(!/৳ 0(?!\d)/.test(await txt(p, '#cp_body')), 'no invented zero money');
  ok(/Only the paid amount is counted/.test(await txt(p, '#cp_notes')) && /no such code zz/.test(await txt(p, '#cp_notes')), 'known note code translated, unknown code readable');
  ok(await p.locator('#cp_t0 .rp-row').count() === 2, 'two campaign rows'); ok(/\(no campaign\)/.test(await txt(p, '#cp_t0')), 'the unassigned row is labelled');
  ok(/—/.test(await txt(p, '#cp_t0')), 'a missing budget shows a dash');
  await p.screenshot({ path: SP + '/rptc3_spend.png' }); await noOverflow(p, 'spend tab');
  await p.click('#cp_t0 .rp-row:first-child'); await wait(p, 250); ok(/Alpha promo/.test(await txt(p, '#cp_sheet')) || /Alpha promo/.test(await txt(p, '.sheet')), 'row sheet opens');
  await p.click('[data-act=cp_drill]'); await wait(p, 400); const dl0 = await calls(p, 'mkt_spend_lines');
  ok(dl0.length === 1 && dl0[0].p_campaign === 'ca', 'drill-down asks for the lines of that campaign'); ok(/Online ads/.test(await txt(p, '#cp_dr')), 'drill rows drawn');
  await p.click('.sheet [data-act=closesheet]'); await wait(p, 150);
  await p.click('#cp_t0 .rp-row:nth-child(2)'); await p.click('[data-act=cp_drill]'); await wait(p, 300); ok((await calls(p, 'mkt_spend_lines')).pop().p_campaign === '__none', 'the unassigned row drills with __none');
  await p.click('.sheet [data-act=closesheet]'); await wait(p, 150);
  const dl = p.waitForEvent('download'); await p.click('#cp_csvb'); const d = await dl; const t = fs.readFileSync(await d.path(), 'utf8');
  ok(/^﻿?campaign_code|^﻿?name/.test(t) || /Alpha promo/.test(t) || /spend/.test(t), 'csv has the table'); ok(/Marketing campaigns and reports/.test(t) && /paid 18-1 lines/.test(t) && /Asia\/Dhaka/.test(t), 'csv footer: title, basis, who/when');
  const lg = await calls(p, 'rptc3_export_log'); ok(lg.length === 1 && lg[0].p_key === 'mkt_spend' && lg[0].p_kind === 'csv', 'export logged before the file (rptc3_export_log)');
  await p.close();
  // CSV refused by the server -> no file
  p = await open({ r3: { err: { rptc3_export_log: { message: 'not allowed' } } } }, '#/campaigns'); await p.click('[data-act=cp_tab][data-v=spend]'); await wait(p, 500);
  let got = false; p.once('download', () => { got = true; }); await p.click('#cp_csvb'); await wait(p, 500); ok(!got, 'no file when the export check refuses'); ok(/not allowed/i.test(await txt(p, '#toast')), 'refusal toast'); await p.close();

  // ---------- 2. performance with cost hidden, ROI reason, repeat needs days ----------
  p = await open({}, '#/campaigns'); await p.click('[data-act=cp_tab][data-v=perf]'); await wait(p, 500);
  ok(/cost and profit are hidden/i.test(await txt(p, '#cp_notes')), 'cost-hidden note is shown'); ok(await p.locator('#cp_t0 .rp-row').count() === 1, 'one campaign row');
  ok(/60 %/.test(await txt(p, '#cp_stats')), 'tagged share (attribution coverage) is shown as a stat');
  await p.click('[data-act=cp_tab][data-v=roi]'); await wait(p, 400); ok(/cost hidden/.test(await txt(p, '#cp_t0')), 'ROI says why there is no figure'); ok(/100/.test(await txt(p, '#cp_stats')), 'unassigned spend shown apart');
  await p.click('[data-act=cp_tab][data-v=repeat]'); await wait(p, 400); ok(await p.locator('#cp_need').count() === 1, 'server "data needed" shows the notice'); ok(await p.locator('#cp_x_days').count() === 1, 'a days box is offered');
  await p.fill('#cp_x_days', '৩০'); await p.click('[data-act=cp_run]'); await wait(p, 400); const rc = await calls(p, 'mkt_repeat_after_promo'); ok(rc.pop().p_days === 30, 'Bangla digits accepted, days sent as 30');
  await p.screenshot({ path: SP + '/rptc3_repeat.png' }); await noOverflow(p, 'repeat tab'); await p.close();

  // ---------- 3. campaign master, owner vs non-owner ----------
  p = await open({}, '#/campaigns'); await wait(p, 300); ok(await p.locator('#cp_m_add').count() === 1, 'owner sees Add campaign');
  await p.click('#cp_m_add'); await wait(p, 200); await p.fill('#cp_f_bn', 'নতুন প্রচার'); await p.fill('#cp_f_start', '2026-12-01'); await p.fill('#cp_f_budget', '500'); await p.click('#cp_m_save'); await wait(p, 500);
  const cs = await calls(p, 'mkt_campaign_save'); ok(cs.length === 1 && cs[0].p_value === null && cs[0].p_patch.name_bn === 'নতুন প্রচার' && cs[0].p_patch.start === '2026-12-01' && cs[0].p_patch.budget === '500', 'campaign saved through the server function');
  await p.close();
  p = await open({ owner: false }, '#/campaigns'); await wait(p, 300); ok(await p.locator('#cp_m_add').count() === 0, 'a non-owner does not get the Add button (the server also refuses)'); await p.close();

  // ---------- 4. posting tab: dry run, decision ----------
  p = await open({ prompt: 'same as the voucher' }, '#/campaigns'); await p.click('[data-act=cp_tab][data-v=post]'); await wait(p, 500);
  ok(/Looks like a 10-2 line/.test(await txt(p, '#cp_t0')) && /To post/.test(await txt(p, '#cp_t0')), 'line states shown in words');
  await p.click('#cp_post_dry'); await wait(p, 400); const pr = await calls(p, 'mkt_post_run'); ok(pr.length === 1 && pr[0].p_dry === true, 'dry run asks for a dry run'); ok(/Dry run: 1/.test(await txt(p, '#cp_post_res')), 'dry result shown');
  await p.click('#cp_t0 .rp-row:first-child'); await wait(p, 200); await p.click('.sheet [data-act=cp_dec][data-v=skip]'); await wait(p, 400);
  const dc = await calls(p, 'mkt_post_decide'); ok(dc.length === 1 && dc[0].p_decision === 'skip' && dc[0].p_line === 1 && dc[0].p_reason === 'same as the voucher', 'decision sent with a reason');
  await p.close();
  p = await open({ r3: { data: { mkt_post_preview: Object.assign({}, R.mkt_post_preview, { setting: { on: false, from: null, mappings_ok: true } }) } } }, '#/campaigns'); await p.click('[data-act=cp_tab][data-v=post]'); await wait(p, 400);
  ok(await p.locator('#cp_post_real').isDisabled(), 'Post now is disabled while the setting is OFF'); await p.close();

  // ---------- 5. coupon usage page ----------
  p = await open({}, '#/couponuse'); await wait(p, 500); ok(/CRM-F|coupon module/.test(await txt(p, '#cu_notes')), 'says the coupon module is not installed'); ok(/TESTOFFER10/.test(await txt(p, '#cu_t1')), 'typed code listed'); ok(await p.locator('#cu_empty_0').count() === 1, 'validated block says none');
  await noOverflow(p, 'coupon page'); await p.close();

  // ---------- 6. audit reports ----------
  p = await open({}, '#/auditreports'); await wait(p, 500); ok(/Page 1 of 3/.test(await txt(p, '#ar_pg')), 'pager: 120 rows / 50 = 3 pages'); ok(/Owner/i.test(await txt(p, '#ar_notes')), 'owner-only note');
  await p.click('[data-act=ar_pg][data-v="1"]'); await wait(p, 400); const lp = await calls(p, 'aud_log_page'); ok(lp.pop().p_offset === 50, 'next page asks for offset 50');
  await p.fill('#ar_x_search', 'abc'); await p.click('[data-act=ar_run]'); await wait(p, 400); ok((await calls(p, 'aud_log_page')).pop().p_search === 'abc', 'search sent');
  const dl2 = p.waitForEvent('download'); await p.click('#ar_csvb'); const d2 = await dl2; const t2 = fs.readFileSync(await d2.path(), 'utf8'); ok(/staff_id/.test(t2) && /owner1/.test(t2), 'log csv built from pages'); ok((await calls(p, 'rptc3_export_log')).pop().p_key === 'aud_log', 'log export logged');
  await p.click('[data-act=ar_tab][data-v=voids]'); await wait(p, 500); ok(/Sale/.test(await txt(p, '#ar_t0')) && /Journal reversal/.test(await txt(p, '#ar_t0')), 'void register rows labelled'); ok(/Salary-related lines are left out/.test(await txt(p, '#ar_notes')), 'salary-hidden note');
  ok(/—/.test(await txt(p, '#ar_t0 .rp-row:first-child')), 'a void with no stored time shows a dash'); await p.screenshot({ path: SP + '/rptc3_voids.png' }); await noOverflow(p, 'void register');
  await p.click('[data-act=ar_tab][data-v=gaps]'); await wait(p, 500); ok(/C3-NOCOST/.test(await txt(p, '#ar_body')), 'gap list shows the item'); ok(/Right to see costs|need the right to see costs/i.test(await txt(p, '#ar_notes')), 'ingredient cost note'); await noOverflow(p, 'gaps'); await p.close();

  // ---------- 7. forecast ----------
  p = await open({}, '#/forecast'); await wait(p, 500);
  ok((await calls(p, 'fc_sales_forecast')).pop().p_ahead === 7 && (await calls(p, 'fc_sales_forecast')).pop().p_window === null, 'horizon 7 prefilled and visible, window NOT assumed (null)');
  ok(/350/.test(await txt(p, '#fc_stats')), 'expected total shown'); ok(await p.locator('#fc_stats .chip.warn').count() === 1, 'the missing "with uplift" is a Data-not-captured chip');
  ok(/28\.6/.test(await txt(p, '#fc_assum')) && /Data coverage/.test(await txt(p, '#fc_assum')), 'assumptions panel shows the coverage %'); ok(/NOT a statistical confidence interval/i.test(await txt(p, '#fc_notes')), 'the confidence-interval warning is shown');
  ok(await p.locator('#fc_t0 .rp-row').count() === 2, 'two forecast days'); const lastRow = await txt(p, '#fc_t0 .rp-row:nth-child(2)'); ok(/—/.test(lastRow) && !/৳ 0(?!\d)/.test(lastRow), 'a day with no same-weekday history has dashes, not zeros');
  await p.screenshot({ path: SP + '/rptc3_forecast.png' }); await noOverflow(p, 'sales forecast');
  await p.fill('#fc_x_win', '28'); await p.fill('#fc_x_ahead', '3'); await p.click('[data-act=fc_run]'); await wait(p, 400); const f2 = (await calls(p, 'fc_sales_forecast')).pop(); ok(f2.p_window === 28 && f2.p_ahead === 3, 'typed window and horizon sent');
  await p.click('[data-act=fc_tab][data-v=cash]'); await wait(p, 500); ok(/Same as last/.test(await txt(p, '#fc_body')) === false, 'items are inside the row sheet'); await p.click('#fc_t0 .rp-row'); await wait(p, 200); ok(/assumed/.test(await txt(p, '.sheet')), 'an assumed salary line is marked'); await p.click('.sheet [data-act=closesheet]');
  ok(/customers have no credit days/i.test(await txt(p, '#fc_notes')), 'cash notes'); await noOverflow(p, 'cash');
  await p.click('[data-act=fc_tab][data-v=scenario]'); await wait(p, 400); await p.fill('#fc_x_volume', '10'); await p.fill('#fc_x_price', '5'); await p.click('[data-act=fc_run]'); await wait(p, 400);
  const sc = (await calls(p, 'fc_scenario')).pop(); ok(sc.p_inputs.volume_pct === '10' && sc.p_inputs.price_pct === '5' && !('cost_pct' in sc.p_inputs), 'only the typed percents are sent, none suggested');
  ok(await p.locator('#fc_sc_missing').count() === 1 && /not every sale has a cost price/.test(await txt(p, '#fc_sc_missing')), 'blank result explains why');
  await p.click('[data-act=fc_tab][data-v=seasonal]'); await wait(p, 500); ok(/25/.test(await txt(p, '#fc_t0')), 'observed difference shown'); ok(/—/.test(await txt(p, '#fc_t0 .rp-row:nth-child(2)')), 'a festival with no data shows dashes');
  await p.click('[data-act=fc_tab][data-v=festivals]'); await wait(p, 500); ok(await p.locator('#fc_f_add').count() === 1, 'owner can add a festival');
  await p.click('#fc_f_add'); await wait(p, 200); await p.fill('#fc_ff_bn', 'টেস্ট ঈদ'); await p.fill('#fc_ff_start', '2027-03-10'); await p.fill('#fc_ff_uplift', '20'); await p.click('#fc_f_save'); await wait(p, 500);
  const fs_ = await calls(p, 'festival_save'); ok(fs_.length === 1 && fs_[0].p_id === null && fs_[0].p.start_date === '2027-03-10' && fs_[0].p.end_date === '2027-03-10' && fs_[0].p.uplift_pct === '20', 'festival saved (end defaults to the start day)'); await p.close();
  p = await open({ owner: false }, '#/forecast'); await p.click('[data-act=fc_tab][data-v=festivals]'); await wait(p, 400); ok(await p.locator('#fc_f_add').count() === 0, 'a non-owner cannot add a festival'); await p.close();
  // a refused report shows a lock card
  p = await open({ r3: { err: { fc_sales_forecast: { message: 'not allowed' } } } }, '#/forecast'); await wait(p, 500); ok(await p.locator('#fc_lock').count() === 1, 'a refused call shows the lock card, not an error dump'); await p.close();
  p = await open({ r3: { err: { fc_sales_forecast: { code: 'PGRST202', message: 'Could not find the function public.fc_sales_forecast' } } } }, '#/forecast'); await wait(p, 500); ok(/not installed yet/.test(await txt(p, '#fc_err')), 'missing SQL says so'); await p.close();

  // ---------- 8. Bangla mode ----------
  p = await open({ lang: 'bn' }, '#/forecast'); await wait(p, 500); ok(/পরিকল্পনা ও পূর্বাভাস/.test(await txt(p, 'h1')) || /পূর্বাভাস/.test(await txt(p, '#app')), 'Bangla title'); ok(/একই বারের/.test(await txt(p, '#fc_notes')) || /পরিসংখ্যানের আস্থা-সীমা/.test(await txt(p, '#fc_notes')), 'notes in Bangla');
  await p.screenshot({ path: SP + '/rptc3_forecast_bn.png' }); await noOverflow(p, 'Bangla forecast'); await p.close();

  // ---------- 9. the till hooks ----------
  p = await open({}, '#/pos'); await wait(p, 600);
  const hook = await p.evaluate(async () => { const b = window.BOS.mkt; await b.prefetch(); const html = b.posBox(); document.body.insertAdjacentHTML('beforeend', '<div id="t_box">' + html + '</div>');
    const sel = document.querySelector('#t_box #mkt_camp'), code = document.querySelector('#t_box #mkt_code'); sel.value = 'ca'; sel.dispatchEvent(new Event('change', { bubbles: true })); code.value = 'summer1'; code.dispatchEvent(new Event('input', { bubbles: true }));
    const cur = b.current(); await b.afterSale('sale-1'); const after = b.current(); b.posBox(); const sel2 = document.querySelector('#t_box #mkt_camp'); sel2.value = 'ca'; sel2.dispatchEvent(new Event('change', { bubbles: true })); b.queued('client-9');
    return { hasSel: !!sel, cur, after, q: localStorage.getItem('bos_mkt_pending') }; });
  ok(hook.hasSel && hook.cur.camp === 'ca' && hook.cur.code === 'summer1', 'the till box keeps the campaign and the code'); ok(hook.after.camp === '' && hook.after.code === '', 'cleared after the sale');
  const tg = await calls(p, 'mkt_tag_sale'); ok(tg.length === 1 && tg[0].p_sale === 'sale-1' && tg[0].p_campaign === 'ca' && tg[0].p_offer === 'SUMMER1', 'afterSale tags the sale with the upper-cased code'); ok(/client-9/.test(hook.q || ''), 'a queued (offline) sale remembers its tag for later');
  await p.close();
  // ---------- 10. static wiring ----------
  const pos = fs.readFileSync(WEB + '/pos.js', 'utf8'), idx = fs.readFileSync(WEB + '/index.html', 'utf8'), ia = fs.readFileSync(WEB + '/ia.js', 'utf8'), fc = fs.readFileSync(WEB + '/forms_cash.js', 'utf8');
  ok(/B\.mkt && B\.mkt\.posBox/.test(pos) && /B\.mkt\.afterSale\(data\.id\)/.test(pos) && /B\.mkt\.queued\(p\.p_client\)/.test(pos), 'pos.js has the three optional hooks');
  ok(['rptkit', 'campaigns', 'couponuse', 'auditreports', 'forecast'].every((s) => idx.includes(`<script src="${s}.js">`)) && idx.indexOf('rptkit.js') < idx.indexOf('campaigns.js'), 'scripts in index.html, kit first');
  ['campaigns', 'couponuse', 'auditreports', 'forecast'].forEach((r) => ok((ia.match(new RegExp(`rec\\('${r}'`, 'g')) || []).length === 1, 'ia.js registers ' + r + ' once'));
  ok(/SEL\('campaign_id'/.test(fc) && /T\('campaign'/.test(fc), '18-1 keeps the free-text campaign field and gains the list field');
  const ff = fs.readFileSync(WEB + '/forms_cash.js', 'utf8'); ok(!/marketing_post_on/.test(ff), 'no setting logic hidden in a form');
  log('assertions:', n); log('errors:', errors.length ? errors.slice(0, 8).join(' | ') : 'none'); log('assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.log('CRASH', e); srv.close(); process.exit(2); } })();
