// RPT-B1 web checks at 360px: the report viewer shows the new returns / refund columns and the "not captured" notes, the notes travel in the CSV, a row with _drill opens its source transactions
// (with a CSV), the festival report has its "Compare with" dates, the Reports map (#/reports/map: 14 sections, badges, links, filter, search, CSV, extension point, valid routes),
// the business page shows the cost-basis note and has a CSV. Serves ../../web of THIS checkout. Run: node rptb1_web_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = path.join(SP, '..', '..', 'web');
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8641);
// the report keys that exist in a fresh database (report_catalog + report_catalog2 of phase 99 + phase 403)
const KEYS = 'collections payment_modes wallet_recon best_customers credit_limit_use customer_dues receivable_aging pos_day_close quick_unlisted voids category_sales discounts hour_weekday item_sales receipt_register retail_wholesale sales_combined sales_summary sales_trend cash_short_over w1_cash_flow w2_handover_vs_hub exceptions_summary g2_paper_numbers x2_bypass x3_audit_log x4_compliance e2_expense_trend e3_weak_control expense_by_head e4_marketing_limit m2_marketing_vs_sales s10_orders l1_pnl l2_margin l3_shop_pnl l4_owner_sheet l5_breakeven t3_payroll t4_staff_cost_ratio p2_rate_trend p4_supplier_score p5_po_match p6_purchase_budget purchases_by_supplier supplier_ageing q1_fridge_temp q2_hygiene q3_complaints d5_lapsed item_slow m1_rfm attendance_summary x5_staff_trend expiry_soon f1_production f2_yield f3_raw_vs_recipe f4_breakdowns k2_count_variance k3_store_ledger stock_balance stock_low transfers_gap wastage y1_daily_sellout y2_festival_compare y3_customer_items'.split(' ');

function MOCK(KEYS) {
  const real = window.supabase.createClient;
  window.__CALLS = [];
  window.supabase.createClient = (...a) => {
    const c = real(...a);
    const fl = ['date', 'locations'];
    const mkc = (key, grp, kind, name, extra) => Object.assign({ key, group: grp, allowed: true, kind, name_bn: name, name_en: name, name_mix: name, filters: fl, dims: [], default_group: null, compare: false, needs_date: true, columns: [] }, extra || {});
    const CAT1 = [mkc('sales_summary', 'sales', 'agg', 'Sales summary', { dims: [{ key: 'day', time: true, label_bn: 'দিন', label_en: 'Day' }], default_group: '' }), mkc('item_sales', 'sales', 'agg', 'Item-wise sales'), mkc('pos_day_close', 'pos', 'raw', 'POS day close'), mkc('payment_modes', 'cash', 'agg', 'By payment mode')];
    const CAT2 = ['f3_raw_vs_recipe', 'y1_daily_sellout', 'y2_festival_compare', 'y3_customer_items'].map((k) => mkc(k, k.startsWith('y2') ? 'sales' : k.startsWith('y3') ? 'customers' : 'stock', 'raw', k, { engine: 2 }));
    const col = (key, en, type, role) => ({ key, label_bn: en, label_en: en, type, role: role || (['money', 'num', 'int', 'pct'].includes(type) ? 'measure' : 'dim') });
    const RESP = {
      sales_summary: { columns: [col('bills', 'Bills', 'int'), col('net', 'Sales', 'money'), col('returns_amt', 'Returns', 'money'), col('net_after_returns', 'Sales after returns', 'money')], rows: [{ bills: 4, net: 1800, returns_amt: 400, net_after_returns: 1400 }], totals: { bills: 4, net: 1800, returns_amt: 400, net_after_returns: 1400 },
        notes: [{ code: 'returns_basis', text_en: 'Returns columns: goods taken back, counted on the day of the return.', text_bn: 'ফেরতের কলাম' }, { code: 'cost_unknown', text_en: 'Cost is unknown for sales of 130.00 (5.3 %). Needed: type its cost price in the item master.', text_bn: 'খরচ জানা নেই' }] },
      pos_day_close: { columns: [col('day', 'Day', 'date', 'col'), col('expected_cash', 'Expected cash in drawer', 'money', 'col'), col('refund_cash', 'Cash refunds paid out', 'money', 'col'), col('expected_cash_after_refunds', 'Expected cash in drawer after refunds', 'money', 'col')],
        rows: [{ day: '2026-10-17', expected_cash: 900, refund_cash: 200, expected_cash_after_refunds: 700 }], totals: { expected_cash: 900, refund_cash: 200, expected_cash_after_refunds: 700 }, notes: [] },
      f3_raw_vs_recipe: { columns: [col('ingredient_bn', 'Ingredient', 'text'), col('expected', 'Per recipe', 'num'), col('actual', 'Actually issued', 'num'), col('actual_status', 'Actual measured?', 'text')], rows: [{ ingredient_bn: 'test_raw', expected: 10, actual: null, actual_status: 'not captured' }], totals: null,
        notes: [{ code: 'not_captured', what: 'actual_issue', text_en: 'Actual raw material use is not captured for 1 of 1 lines. Needed: the real issue of each batch (the issue slip 18-1).', text_bn: 'ধরা হয়নি' }] },
      y1_daily_sellout: { columns: [col('day', 'Date', 'date'), col('item_bn', 'Item', 'text'), col('sold', 'Sold', 'num'), col('closing', 'Left at closing', 'num')], rows: [{ day: '2026-10-17', item_bn: 'test_cake', sold: 10, closing: 9, _drill: { day: '2026-10-17', loc: 1, item: 'i1' } }], totals: { sold: 10 }, notes: [] },
      y2_festival_compare: { columns: [col('item_bn', 'Item', 'text'), col('qty_now', 'Quantity now', 'num'), col('qty_prev', 'Quantity before', 'num'), col('state', 'State', 'text')], rows: [{ item_bn: 'test_cake', qty_now: 62, qty_prev: null, state: 'no previous data', _drill: { item: 'i1' } }], totals: null,
        notes: [{ code: 'compare_range', text_en: 'Compared with 2025-10-15 to 2025-10-17', text_bn: 'তুলনা' }, { code: 'not_captured', text_en: 'No sales were recorded in the previous period. Needed: other dates in "Compare with".', text_bn: 'আগের বিক্রি নেই' }] },
    };
    const meta = { from: '2026-10-15', to: '2026-10-17', group: [], sort: null, dir: 'asc', cost_shown: true, today: '2026-10-17' };
    const rpc = c.rpc;
    c.rpc = async (fn, args) => {
      if (fn === 'report_catalog') return { data: CAT1, error: null };
      if (fn === 'report_catalog2') return { data: CAT2, error: null };
      if (fn === 'report_presets') return { data: { today: { from: '2026-10-17', to: '2026-10-17' }, last_7: { from: '2026-10-11', to: '2026-10-17' }, this_month: { from: '2026-10-01', to: '2026-10-17' } }, error: null };
      if (fn === 'has_grant') return { data: true, error: null };
      if (fn === 'report_run' || fn === 'report_run2') {
        window.__CALLS.push(JSON.parse(JSON.stringify(args)));
        const r = RESP[args.p_key]; if (!r) return { data: null, error: { message: 'unknown_report' } };
        return { data: Object.assign({ report: args.p_key, compare: null, page: { n: 1, size: 50, groups: r.rows.length, cap: 500 }, has_more: false, data_needed: false, meta }, r), error: null };
      }
      if (fn === 'report_drill') { window.__CALLS.push({ drill: JSON.parse(JSON.stringify(args)) }); return { data: { title_bn: 'স্টকের নড়াচড়া', title_en: 'test_cake · stock movements', columns: [col('time', 'Time', 'text', 'col'), col('reason', 'Kind', 'text', 'col'), col('qty', 'Quantity (+/-)', 'num', 'col'), col('ref', 'Source', 'text', 'col')], rows: [{ time: '08:33', reason: 'sale_out', qty: -5, ref: 'Receipt 10' }, { time: '08:34', reason: 'wastage', qty: -2, ref: 'wastage rb1-w-b' }], notes: [], count: 2 }, error: null }; }
      if (fn === 'log_report_export' || fn === 'log_report_export2') return { data: null, error: null };
      if (fn === 'biz_daily') return { data: [{ sale_date: '2026-10-16', location_id: 1, n: 9, revenue: 21000, discount: 500, void_n: 1, void_amt: 300, costed_rev: 18000, cogs: 16200 }], error: null };
      if (fn === 'biz_items') return { data: [{ item_id: 'a', code: 'I-001', name_bn: 'সাদা মিষ্টি', name_en: 'White', unit: 'kg', qty: 30, revenue: 12000, cogs: null, share_pct: 60, cum_pct: 60, abc: 'A' }, { item_id: 'b', code: 'I-002', name_bn: 'কালো মিষ্টি', name_en: 'Black', unit: 'kg', qty: 10, revenue: 8000, cogs: 5000, share_pct: 40, cum_pct: 100, abc: 'B' }], error: null };
      if (fn === 'biz_staff') return { data: [], error: null };
      if (fn === 'biz_outlook') return { data: null, error: null };
      if (fn === 'biz_cost_status') return { data: { basis: 'price_list', revenue: 2450, ledger_rev: 0, price_list_rev: 120, unknown_rev: 130, unknown_pct: 5.31, ledger_could_cost_rev: 200 }, error: null };
      return rpc(fn, args);
    };
    return c;
  };
}

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let n = 0, bad = 0;
  const ok = (c, m) => { n++; if (!c) { bad++; console.log('FAIL: ' + m); } };
  async function open(hash, lang, withRegistry) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + '\n(' + MOCK.toString() + ')(' + JSON.stringify(KEYS) + ');' }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    if (!withRegistry) await p.route('**/data/report_registry.json', (r) => r.fulfill({ contentType: 'application/json', body: '{}' }));      // INTEGRATION: the old checks below are about the static map; the registry sync has its own check at the end
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','${lang || 'en'}')}catch(e){}
      window.__BL=[];const _c=URL.createObjectURL.bind(URL);URL.createObjectURL=(b)=>{ if(b&&b.text){ b.text().then(t=>window.__BL.push(t)); } return _c(b); };`);
    await p.goto('http://localhost:8641/' + hash); await p.waitForTimeout(1200); return p;
  }
  const wait = (p, t = 300) => p.waitForTimeout(t);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal page scroll: ' + m);
  const lastCsv = (p) => p.evaluate(() => window.__BL[window.__BL.length - 1] || '');

  // ---------- 1 sales summary: new columns, notes, CSV carries both ----------
  let p = await open('#/report/sales_summary');
  const th = await p.locator('#rp_tbl thead').innerText();
  ok(/Returns/.test(th) && /Sales after returns/.test(th), 'sales summary shows the Returns and Sales after returns columns');
  const notes = await p.locator('.rp-note').allInnerTexts();
  ok(notes.some((x) => /Returns columns/.test(x)) && notes.some((x) => /Cost is unknown/.test(x)), 'the returns basis and the unknown-cost notes are shown');
  ok(await p.locator('.rp-note.warn').count() === 1, 'the unknown-cost note is a warning, the basis note is info');
  await noOverflow(p, 'sales summary');
  await p.click('[data-act=rp_csv]'); await wait(p, 600);
  let csv = await lastCsv(p);
  ok(/Sales after returns/.test(csv) && /1400/.test(csv) && /Cost is unknown for sales of 130\.00/.test(csv), 'CSV has the new columns and the notes (a blank is explained)');
  await p.close();

  // ---------- 2 POS day close ----------
  p = await open('#/report/pos_day_close');
  ok(/Cash refunds paid out/.test(await p.locator('#rp_tbl thead').innerText()) && /Expected cash in drawer after refunds/.test(await p.locator('#rp_tbl thead').innerText()), 'POS day close shows the refund and the cash-after-refunds columns');
  await p.click('[data-act=rp_csv]'); await wait(p, 600); csv = await lastCsv(p); ok(/700/.test(csv) && /Cash refunds paid out/.test(csv), 'POS day close CSV');
  await noOverflow(p, 'pos day close'); await p.close();

  // ---------- 3 f3: not captured ----------
  p = await open('#/report/f3_raw_vs_recipe');
  const rn = await p.locator('.rp-note').allInnerTexts();
  ok(rn.some((x) => /^Not captured: Actual raw material use is not captured/.test(x)) && await p.locator('.rp-note.warn').count() === 1, 'f3: a "Not captured" warning names the form needed');
  const row = await p.locator('#rp_tbl tbody tr').first().innerText(); ok(/—/.test(row) && /not captured/.test(row), 'f3: the actual cell is a dash and the status says not captured (no 0.00)');
  await p.click('[data-act=rp_csv]'); await wait(p, 600); csv = await lastCsv(p); ok(/Not captured: Actual raw material use/.test(csv), 'f3 CSV carries the notice');
  await p.close();

  // ---------- 4 sell-out drill-down ----------
  p = await open('#/report/y1_daily_sellout');
  ok(await p.locator('#rp_tbl tbody tr.tap[data-act=rp_src]').count() === 1 && /transactions behind/.test(await p.locator('.rp-hint').innerText()), 'a row with _drill is tappable and says so');
  await p.click('#rp_tbl tbody tr.tap'); await wait(p, 500);
  ok(await p.locator('#rp_srct tbody tr').count() === 2 && /Receipt 10/.test(await p.locator('#rp_srct').innerText()) && /stock movements/.test(await p.textContent('.sheet')), 'the sheet lists the source transactions');
  const dc = await p.evaluate(() => window.__CALLS.filter((c) => c.drill).map((c) => c.drill)); ok(dc.length === 1 && dc[0].p_key === 'y1_daily_sellout' && dc[0].p_ref.loc === 1 && dc[0].p_ref.day === '2026-10-17', 'report_drill got the key and the row reference');
  await noOverflow(p, 'drill sheet');
  await p.click('[data-act=rp_srccsv]'); await wait(p, 500); csv = await lastCsv(p); ok(/Kind,Quantity/.test(csv) && /wastage/.test(csv), 'the drill-down has its own CSV');
  await p.close();

  // ---------- 5 festival: compare-with dates, no previous data ----------
  p = await open('#/report/y2_festival_compare');
  ok(await p.locator('#rp_pf').count() === 1 && await p.locator('#rp_pt').count() === 1, 'the festival report has the Compare with dates');
  await p.fill('#rp_pf', '2025-10-01'); await p.fill('#rp_pt', '2025-10-03'); await p.dispatchEvent('#rp_pt', 'change'); await wait(p, 600);
  const cl = await p.evaluate(() => window.__CALLS.filter((c) => c.p_key === 'y2_festival_compare').pop().p_filters);
  ok(cl.prev_from === '2025-10-01' && cl.prev_to === '2025-10-03', 'prev_from / prev_to are sent');
  ok((await p.locator('.rp-note').allInnerTexts()).some((x) => /^Not captured: No sales were recorded/.test(x)), 'the "no previous data" notice is shown');
  ok(/no previous data/.test(await p.locator('#rp_tbl tbody').innerText()), 'the row says no previous data (the previous quantity is a dash, not 0)');
  await p.close();
  p = await open('#/report/y1_daily_sellout'); ok(await p.locator('#rp_pf').count() === 0, 'other reports have no Compare with dates'); await p.close();

  // ---------- 6 reports map ----------
  p = await open('#/reports/map');
  ok(/#\/reports\/map/.test(p.url()) && /Reports map/.test(await p.textContent('header.top h1')), 'the map opens at #/reports/map');
  ok(await p.locator('details.rm-sec').count() === 5 && await p.locator('section.rm-sec.pend').count() === 10, 'sections 1-4 + the extra one are listed, sections 5-14 are "not audited yet" placeholders');
  const rows = await p.evaluate(() => window.BOS.reportsMap.sections().flatMap((s) => s.reports.map((r) => ({ n: r.n, st: r.status, route: r.route, g: r.group, sec: s.id }))));
  ok(rows.filter((r) => typeof r.n === 'number').length === 55, 'the 55 reports of the audit are in the registry');
  const cnt = await p.evaluate(() => window.BOS.reportsMap.counts()); ok(cnt.implemented + cnt.incomplete + cnt.unavailable + cnt.unverified === 55 && cnt.unverified === 1 && cnt.pending === 10 && cnt.unavailable >= 9, 'badge counts add up: ' + JSON.stringify(cnt));
  const bad1 = await p.evaluate((KEYS) => { const IA = window.BOS.ia, out = [];
    window.BOS.reportsMap.sections().forEach((s) => s.reports.forEach((r) => { [r.route].concat(r.more || []).filter(Boolean).forEach((rt) => { if (rt.startsWith('report/')) { if (!KEYS.includes(rt.slice(7))) out.push(rt); } else if (!IA.byRoute(rt)) out.push(rt); }); if (!IA.GID.includes(r.group)) out.push('group:' + r.group); if (!r.route && r.status !== 'unavailable') out.push('noroute:' + r.n); if (r.status === 'unavailable' && !r.needs) out.push('noneeds:' + r.n); }));
    return out; }, KEYS);
  ok(bad1.length === 0, 'every route exists (report key or ia.js page), every group is one of the 13, every unavailable report says what is needed: ' + JSON.stringify(bad1));
  ok(await p.locator('details.rm-sec[data-sec="1"]').getAttribute('open') !== null, 'section 1 is open');
  await p.click('details.rm-sec[data-sec="2"] summary'); await wait(p, 150);
  ok(await p.locator('.rm-row[data-n="11"] .rm-st').innerText() === 'Implemented' && await p.locator('.rm-row[data-n="11"] .rm-open').count() === 1, 'report 11: Implemented badge and one Open link');
  await p.click('.rm-row[data-n="11"] .rm-open'); await wait(p, 600);
  ok(/#\/report\/sales_summary/.test(p.url()), 'the link opens the existing route #/report/sales_summary');
  await p.goBack(); await wait(p, 600);
  ok(await p.locator('.rm-row[data-n="7"] .rm-nb').count() === 1 && await p.locator('.rm-row[data-n="7"] .rm-open').count() === 0 && /Needed/.test(await p.locator('.rm-row[data-n="7"] .rm-need').innerText()), 'an unavailable report has no link; it says "Not built yet" and what is needed');
  await p.click('.rm-stat[data-v=unverified]'); await wait(p, 250);
  ok(await p.locator('.rm-row').count() === 1 && await p.locator('.rm-row[data-n="8"]').count() === 1, 'the status filter shows only the unverified report (8)');
  await p.click('.rm-stat[data-v=unverified]'); await p.fill('#rm_q', 'budget'); await wait(p, 250);
  ok(await p.locator('.rm-row').count() === 1, 'search finds a report by name');
  await p.fill('#rm_q', ''); await wait(p, 200);
  await noOverflow(p, 'reports map');
  await p.screenshot({ path: SP + '/rm_map.png', fullPage: true });
  await p.click('[data-act=rm_csv]'); await wait(p, 500); csv = await lastCsv(p);
  ok(/implemented/.test(csv) && /report\/sales_summary/.test(csv) && /Section 5/.test(csv) && csv.split('\n').length > 60, 'the map CSV lists every report with status and route');
  // extension point: a later audit fills a section without touching the page code
  await p.evaluate(() => window.BOS.reportsMap.extend([{ id: 5, title: ['বিভাগ ৫', 'Purchasing', 'Purchasing'], reports: [{ n: 56, name: ['ক্রয় রিপোর্ট', 'Purchases by supplier', 'Purchases by supplier'], status: 'implemented', route: 'report/purchases_by_supplier', group: 'purch' }] }]));
  await p.goto('http://localhost:8641/#/reports'); await wait(p, 500); await p.goto('http://localhost:8641/#/reports/map'); await wait(p, 700);
  ok(await p.locator('details.rm-sec[data-sec="5"]').count() === 1 && await p.locator('section.rm-sec.pend').count() === 9, 'extend() turns section 5 from a placeholder into a listed section');
  await p.close();

  // INTEGRATION: with web/data/report_registry.json (RPT-HUB) the map shows all 193 reports in 14 sections and follows the registry statuses
  p = await open('#/reports/map', 'en', true);
  ok(await p.locator('details.rm-sec').count() === 15 && await p.locator('section.rm-sec.pend').count() === 0, 'with the registry: 14 sections + the extra one are listed, none is a placeholder');
  const nreg = await p.evaluate(() => window.BOS.reportsMap.sections().filter((s) => !s.extra).reduce((n, s) => n + s.reports.length, 0));
  ok(nreg === 193, 'with the registry: all 193 reports are on the map (' + nreg + ')');
  const r7 = await p.evaluate(() => { const r = window.BOS.reportsMap.sections()[0].reports.find((x) => x.n === 7); return r && [r.status, r.route]; });
  ok(r7 && r7[0] === 'implemented' && r7[1] === 'prodreports', 'report 7 follows the registry: built by RPT-B4, opens Production reports');
  ok(await p.locator('.rm-hublink [data-v="reports/hub"]').count() === 1, 'the map links to Business Memory');
  await p.close();

  // the hub (#/reports) still works and links to the map
  p = await open('#/reports');
  ok(await p.locator('.rp-row[data-act=go][data-v="reports/map"]').count() === 1, 'the report hub lists the map under "Other pages"');
  await noOverflow(p, 'hub'); await p.close();

  // map in Bangla
  p = await open('#/reports/map', 'bn'); ok(/রিপোর্ট মানচিত্র/.test(await p.textContent('header.top h1')) && /অডিট বাকি/.test(await p.textContent('#rm_body')), 'the map is in Bangla'); await noOverflow(p, 'map bn'); await p.close();

  // ---------- 7 business page ----------
  p = await open('#/biz');
  await wait(p, 600);
  const bz = await p.textContent('#bz_body');
  ok(await p.locator('#bz_cstat').count() === 1 && /only the cost typed in the item master/.test(bz) && /Cost unknown for/.test(bz) && /130/.test(bz), 'the business page shows the cost basis and the unknown-cost amount');
  ok(/Sales whose cost the stock ledger knows/.test(bz), 'and the hint that the ledger knows a cost');
  await noOverflow(p, 'biz');
  await p.click('#bz_csvb'); await wait(p, 500); csv = await lastCsv(p);
  ok(/code,item,class,qty,revenue/.test(csv) && /not captured/.test(csv) && /cost unknown \(revenue\),130/.test(csv), 'the business page CSV has the items, "not captured" for an item with no cost, and the cost status');
  await p.close();

  console.log('assertions: ' + n);
  console.log('errors: ' + (errors.length ? JSON.stringify(errors.slice(0, 6)) : 'none'));
  console.log('assert failures: ' + bad);
  await br.close(); srv.close();
  process.exit(bad || errors.length ? 1 : 0);
})();
