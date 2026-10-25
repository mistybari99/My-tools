// Reconciliation screens (web/recon118.js, phase118 step B4) in Chromium with a mocked supabase client (tests/web/stub.js + canned rpc answers).
// Run: node tests/web/recon118_test.js [abs tests/web dir]      (serves ../../web of this checkout)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR, PORT = _P.freePort();
const src = fs.readFileSync(SP + '/smoke.js', 'utf8');
const mkData = () => new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': ext === '.js' ? 'text/javascript' : ext === '.css' ? 'text/css' : ext === '.html' ? 'text/html' : 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const BN = /[ঀ-৿]/;
// ---- canned answers (shape = the real phase118 output; numbers = the audit scenario) ----
const row = (o) => Object.assign({ location_id: 2, location_bn: 'S1', location_en: 'Showroom S1', unit: 'kg', opening_qty: 0, production_qty: 0, purchases_qty: 0, transfer_in_qty: 0, give_back_qty: 0, used_qty: 0, sales_qty: 0, wastage_qty: 0, transit_loss_qty: 0, transfer_out_qty: 0, adjustments_qty: 0, closing_qty: 0, balance_qty: 0, variance_qty: 0, flags: [] }, o);
const SR = (cost) => ({ from: '2026-10-01', to: '2026-10-14', location_ids: [2], cost_visible: cost, row_count: 2, truncated: false, summary: { items: 2, with_variance: 1, unbalanced: 0, adjusted: 1 }, sales_unmatched: {},
  rows: [row(Object.assign({ item_code: 'FG-A', item_bn: 'মিষ্টি এ', item_en: 'Sweet A', transfer_in_qty: 13, give_back_qty: 1, sales_qty: 5, transfer_out_qty: 2, closing_qty: 7, balance_qty: 7 }, cost ? { avg_cost: 40, closing_value: 280 } : {})),
         row(Object.assign({ item_code: 'RC-X', item_bn: '=SUM(1)', item_en: '=SUM(1)', unit: 'pc', opening_qty: 9, purchases_qty: 5, sales_qty: 3, adjustments_qty: -1, closing_qty: 10, balance_qty: 11, variance_qty: -1, flags: ['variance', 'adjusted'] }, cost ? { avg_cost: 7, closing_value: 70 } : {}))] });
const UM = { total: 3, counts: { untracked: 1, not_posted: 1, over_posted: 1 }, truncated: false, rows: [
  { receipt: 31, sale_date: '2026-10-14', location_bn: 'S1', location_en: 'Showroom S1', item_code: 'RC-U', item_en: 'Untracked', item_bn: 'x', unit: 'pc', base_unit: 'pc', sold_qty: 2, sold_base_qty: 2, ledger_qty: 0, diff_qty: 2, kind: 'untracked' },
  { receipt: 33, sale_date: '2026-10-14', location_bn: 'S1', location_en: 'Showroom S1', item_code: 'RC-R', item_en: 'Raw', item_bn: 'x', unit: 'kg', base_unit: 'kg', sold_qty: 3, sold_base_qty: 3, ledger_qty: 0, diff_qty: 3, kind: 'not_posted' },
  { receipt: 12, sale_date: '2026-10-14', location_bn: 'S1', location_en: 'Showroom S1', item_code: 'RS-B', item_en: 'Item B', item_bn: 'x', unit: 'pc', base_unit: 'pc', sold_qty: 4, sold_base_qty: 4, ledger_qty: 5, diff_qty: -1, kind: 'over_posted' }] };
const BS = (cost) => ({ from: '2026-10-01', to: '2026-10-14', location_ids: [2, 3], cost_visible: cost, ageing_hours: [24, 72], row_count: 1, truncated: false,
  by_location: [Object.assign({ location_id: 3, location_bn: 'S2', location_en: 'Showroom S2', transfers_sent: 3, transfers_short: 0, transfers_in_transit: 2 }, cost ? { sent_value: 560, received_value: 400, short_value: 0, in_transit_value: 160 } : {})],
  rows: [row(Object.assign({ location_id: 3, location_en: 'Showroom S2', item_code: 'FG-A', item_en: 'Sweet A', item_bn: 'এ', sent_in_qty: 14, received_qty: 10, short_qty: 0, in_transit_qty: 4, in_transit_age_0_qty: 3, in_transit_age_1_qty: 1, in_transit_age_2_qty: 0, sold_qty: 8, wasted_qty: 1, remaining_qty: 1, flags: ['transit_old'] }, cost ? { sent_value: 560, received_value: 400, in_transit_value: 160, remaining_value: 40 } : {}))] });
const NPB = (o) => Object.assign({ location_id: 2, location_bn: 'S1', location_en: 'Showroom S1', net_sales: 920, costed_sales: 720, uncosted_sales: 200, cogs: 360, gross_profit: 360, gross_margin_pct: 50, wastage_cost: 0, card_fees: 7.2, variable_expenses: 0,
  contribution_margin: 352.8, contribution_pct: 49, other_expenses: 150, salary: 300, fixed_monthly: 0, shared_costs: 610, overhead_total: 1060, net_profit: -707.2, net_profit_pct: -98.22, complete: false, gaps: ['uncosted_sales'] }, o || {});
const NP = { from: '2026-10-01', to: '2026-10-31', location_ids: [1, 2, 3, 6], variable_heads: ['transport'], cost_source: 'ledger_then_item_costs',
  branches: [NPB(), NPB({ location_id: 3, location_en: 'Showroom S2', net_sales: 640, uncosted_sales: 0, gross_profit: 320, wastage_cost: 40, card_fees: 0, variable_expenses: 40, contribution_margin: 240, other_expenses: 0, salary: 0, shared_costs: 290, net_profit: -50, gaps: ['salary_not_recorded'] })],
  products: [{ item_code: 'FG-A', item_en: 'Sweet A', item_bn: 'এ', qty: 12, net_sales: 1000, costed_sales: 1000, uncosted_sales: 0, cogs: 480, gross_profit: 520, wastage_cost: 40, allocated_variable: 42.8, contribution_margin: 437.2, allocated_overhead: 704.8, net_profit: -267.6, cost_complete: true },
             { item_code: 'RS-C', item_en: 'Item C', item_bn: 'সি', qty: 2, net_sales: 200, costed_sales: 0, uncosted_sales: 200, cogs: 0, gross_profit: 0, wastage_cost: 0, allocated_variable: 1.57, contribution_margin: -1.57, allocated_overhead: 230.43, net_profit: -232, cost_complete: false }],
  product_branch: [{ location_id: 2, location_en: 'Showroom S1', location_bn: 'S1', item_code: 'FG-A', item_en: 'Sweet A', item_bn: 'এ', qty: 4, net_sales: 360, costed_sales: 360, uncosted_sales: 0, cogs: 160, gross_profit: 200, wastage_cost: 0, allocated_variable: 2.82, contribution_margin: 197.18, allocated_overhead: 414.78, net_profit: -217.6, cost_complete: true }],
  company: { net_sales: 1560, costed_sales: 1360, uncosted_sales: 200, cogs: 680, gross_profit: 680, contribution_margin: 592.8, overhead_total: 1350, net_profit: -757.2, unallocated_shared_costs: 120 },
  included: ['net_sales_after_discount_and_returns', 'cogs_from_stock_ledger_cost', 'wastage_and_transit_loss_at_ledger_cost', 'card_fees_by_settlement_date', 'variable_expense_heads', 'other_expenses_quick_and_form_10_2', 'salary_sheet_02_2', 'monthly_fixed_cost', 'shared_bills_attributed_pro_rated_by_days'],
  not_included: ['profit_on_sales_with_unknown_cost', 'payroll_app_payments', 'shared_bills_not_attributed_to_a_place', 'online_delivery_charge', 'depreciation_and_other_books_only_entries', 'product_conversion_cost_when_factory_costing_is_off'] };
// window.__ANS = { fn: data | {error:{message}} } ; window.__RC = calls [fn, args]
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__RC = [];
 c.rpc = async (fn, args) => { if (/^(stock_recon_statement|stock_sales_unmatched|factory_branch_statement|net_profit_report|recon_export_log118)$/.test(fn)) { window.__RC.push([fn, JSON.parse(JSON.stringify(args || {}))]);
   const a = (window.__ANS || {})[fn]; if (a && a.error) return { data: null, error: a.error }; return { data: a === undefined ? null : JSON.parse(JSON.stringify(a)), error: null }; }
  return rpc(fn, args); }; return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, pass = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else pass++; };
  async function open(hash, ans, o = {}) {
    const data = mkData();
    const ctx = await br.newContext({ viewport: { width: 400, height: 800 }, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_|Content Security Policy/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};${o.owner === false ? 'window.__OWNER=false;' : ''}window.__ANS=${JSON.stringify(ans)};try{localStorage.setItem('bos_lang',${JSON.stringify(o.lang || 'en')});}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(o.wait || 1500);
    return { p, ctx };
  }
  const text = (p, sel) => p.evaluate((s) => (document.querySelector(s) || {}).innerText || '', sel);
  const calls = (p) => p.evaluate(() => window.__RC);

  // 1. stock reconciliation, owner, cost visible
  let { p, ctx } = await open('#/stockrecon', { stock_recon_statement: SR(true), stock_sales_unmatched: UM });
  let body = await text(p, '#app');
  ok(/Stock reconciliation/.test(body), 'stock screen title (English): ' + body.slice(0, 60));
  ok(!BN.test(body.replace(/মিষ্টি এ/g, '')), 'English mode: no Bangla letters on the stock screen (item names from data excepted)');
  ok((await p.$$('#rc_tbl tbody tr')).length === 2, 'two statement rows');
  ok(/Opening/.test(body) && /Closing/.test(body) && /Stored balance/.test(body) && /Variance/.test(body), 'column heads of the formula are there');
  ok(/Avg cost/.test(body) && /Closing value/.test(body) && /280/.test(body), 'cost holder: avg cost and closing value columns');
  ok(/Ledger ≠ stored balance/.test(body) && /Has an adjustment/.test(body), 'flags are spelled out');
  ok(/Sales lines not matched in the stock ledger/.test(body) && (await p.$$('table.bz')).length === 2, 'unmatched-sales table below');
  ok(/Item is not stock-tracked/.test(body) && /Nothing left stock/.test(body) && /More left stock than sold/.test(body), 'unmatched kinds are spelled out');
  let cs = await calls(p);
  ok(cs.some((c) => c[0] === 'stock_recon_statement' && c[1].p_loc === null && /^\d{4}-\d\d-01$/.test(c[1].p_from)) && cs.some((c) => c[0] === 'stock_sales_unmatched'), 'both RPCs called, default window starts on the 1st of the month');
  await p.click('[data-act="rc_only"]'); await p.waitForTimeout(150);
  ok((await p.$$('#rc_tbl tbody tr')).length === 1 && /RC-X/.test(await text(p, '#rc_tbl')), 'only-flagged toggle leaves the variance row');
  await p.click('[data-act="rc_only"]'); await p.fill('#rc_q', 'fg-a'); await p.waitForTimeout(150);
  ok((await p.$$('#rc_tbl tbody tr')).length === 1 && /FG-A/.test(await text(p, '#rc_tbl')), 'item filter works without a server call');
  await p.fill('#rc_q', '');
  await p.click('[data-act="rc_kind"][data-v="over_posted"]'); await p.waitForTimeout(100);
  ok((await p.$$('table.bz'))[1] && (await (await p.$$('table.bz'))[1].$$('tbody tr')).length === 1, 'kind chip filters the unmatched list');
  // CSV: audit first, then the file
  const [dl] = await Promise.all([p.waitForEvent('download', { timeout: 5000 }).catch(() => null), p.click('[data-act="rc_csv"]')]);
  await p.waitForTimeout(300);
  cs = await calls(p);
  ok(!!dl && /^stock_recon-.*\.csv$/.test(dl.suggestedFilename()), 'CSV file offered: ' + (dl && dl.suggestedFilename()));
  ok(cs.some((c) => c[0] === 'recon_export_log118' && c[1].p_key === 'stock_recon' && c[1].p_rows === 2), 'the export is logged before the download');
  if (dl) { const txt = fs.readFileSync(await dl.path(), 'utf8'); ok(txt.charCodeAt(0) === 0xFEFF && /Opening/.test(txt.split('\r\n')[0]), 'CSV has a BOM and a header');
    ok(!/(^|,)=/.test(txt), 'no CSV cell starts with ='); ok(/FG-A/.test(txt) && /,7,7,0/.test(txt), 'CSV carries the numbers'); }
  ok(await p.evaluate(() => window.BOS.recon118.csvCell('=SUM(1)') === "'=SUM(1)" && window.BOS.recon118.csvCell('@x') === "'@x" && window.BOS.recon118.csvCell('a,b') === '"a,b"' && window.BOS.recon118.csvCell(-5) === '-5'), 'csvCell neutralises = and @, quotes commas, keeps negative numbers');
  await ctx.close();

  // 2. no cost right: no cost columns anywhere
  ({ p, ctx } = await open('#/stockrecon', { stock_recon_statement: SR(false), stock_sales_unmatched: { total: 0, counts: {}, rows: [] } }));
  body = await text(p, '#app');
  ok(!/Avg cost|Closing value/.test(body) && !/280/.test(body), 'no cost right: no cost or value column, no value');
  ok(/matches the stock ledger/.test(body), 'no unmatched lines: the green line');
  await ctx.close();

  // 3. refused by the server
  ({ p, ctx } = await open('#/stockrecon', { stock_recon_statement: { error: { message: 'not allowed' } }, stock_sales_unmatched: { error: { message: 'not allowed' } } }));
  body = await text(p, '#app'); ok(/not allowed to see this page/.test(body), 'server refusal shows the no-access line: ' + body.slice(0, 80));
  await ctx.close();
  ({ p, ctx } = await open('#/stockrecon', { stock_recon_statement: { error: { message: 'function public.stock_recon_statement does not exist' } }, stock_sales_unmatched: null }));
  body = await text(p, '#app'); ok(/database part is not installed yet/.test(body), 'missing phase118 shows the not-installed line');
  await ctx.close();

  // 4. branch statement
  ({ p, ctx } = await open('#/branchstmt', { factory_branch_statement: BS(true) }));
  body = await text(p, '#app');
  ok(/Factory-to-branch statement/.test(body) && !BN.test(body.replace(/এ/g, '')), 'branch statement title, English only');
  ok(/Transit age limits \(hours\): 24 \/ 72/.test(body), 'ageing limits shown');
  ok(/Sent to here/.test(body) && /Received/.test(body) && /In transit/.test(body) && /Remaining/.test(body) && /Old in transit/.test(body), 'sent / received / in transit / remaining columns and the old-transit flag');
  ok(/Sent value/.test(body) && /560/.test(body) && /In-transit value/.test(body), 'values for a cost holder');
  ok(/By place/.test(body) && /Showroom S2/.test(body), 'by-place cards');
  await ctx.close();
  ({ p, ctx } = await open('#/branchstmt', { factory_branch_statement: BS(false) }));
  body = await text(p, '#app'); ok(!/Sent value|In-transit value|Remaining value|560/.test(body) && /Sent to here/.test(body), 'no cost right: quantities only');
  await ctx.close();

  // 5. net profit
  ({ p, ctx } = await open('#/netprofit', { net_profit_report: NP }));
  body = await text(p, '#app');
  ok(/Net profit \(product and branch\)/.test(body) && !BN.test(body.replace(/এ|সি/g, '')), 'net profit title, English only');
  ok(/Included in these figures/.test(body) && /Net sales \(after discount and returns\)/.test(body) && /Card fees \(by settlement date\)/.test(body), 'the included list is on screen');
  ok(/Not included/.test(body) && /Profit on sales with unknown cost/.test(body) && /Payroll app payments/.test(body) && /Depreciation/.test(body), 'the not-included list is on screen');
  ok(/Heads counted as variable: transport/.test(body), 'variable heads shown');
  ok(/Contribution margin/.test(body) && /Net profit after overhead/.test(body) && /352.8/.test(body) && /-707.2/.test(body), 'branch table: contribution margin and net profit after overhead');
  ok(/Sales with unknown cost \(not in profit\)/.test(body) && /No salary sheet/.test(body), 'gap chips');
  ok(/All places together/.test(body) && /-757.2/.test(body) && /Shared bills not charged to any place: 120/.test(body), 'company row and the unallocated line');
  await p.click('[data-act="rc_tab"][data-v="product"]'); await p.waitForTimeout(150);
  body = await text(p, '#app');
  ok((await p.$$('#rc_tbl tbody tr')).length === 2 && /Allocated: overhead/.test(body) && /Sales, cost unknown/.test(body), 'product tab: two products, allocated columns, cost-unknown chip on RS-C');
  ok(/Product fees, variable expenses and overhead = the branch amount/.test(body), 'allocation method is explained');
  await p.click('[data-act="rc_tab"][data-v="pb"]'); await p.waitForTimeout(150);
  ok((await p.$$('#rc_tbl tbody tr')).length === 1 && /Showroom S1/.test(await text(p, '#rc_tbl')), 'product x branch tab');
  const [dl2] = await Promise.all([p.waitForEvent('download', { timeout: 5000 }).catch(() => null), p.click('[data-act="rc_csv"]')]);
  cs = await calls(p);
  ok(!!dl2 && cs.some((c) => c[0] === 'recon_export_log118' && c[1].p_key === 'net_profit_product'), 'profit CSV is logged under net_profit_product');
  await ctx.close();
  ({ p, ctx } = await open('#/netprofit', { net_profit_report: { error: { message: 'not allowed' } } }));
  body = await text(p, '#app'); ok(/not allowed to see this page/.test(body), 'profit report refused by the server: no-access line, no numbers');
  await ctx.close();

  // 6. Bangla mode
  ({ p, ctx } = await open('#/netprofit', { net_profit_report: NP }, { lang: 'bn' }));
  body = await text(p, '#app'); ok(BN.test(body) && /নিট লাভ/.test(body), 'Bangla mode shows Bangla titles');
  await ctx.close();

  // 7. a plain user without export_data does not get the CSV button
  ({ p, ctx } = await open('#/stockrecon', { stock_recon_statement: SR(false), stock_sales_unmatched: UM }, { owner: false }));
  ok((await p.$$('[data-act="rc_csv"]')).length === 0 && (await p.$$('#rc_tbl')).length === 1, 'not owner and no export_data: table yes, CSV button no');
  await ctx.close();

  // 8. registry: the three routes exist in ia.js and are handled
  ({ p, ctx } = await open('#/home', {}));
  const reg = await p.evaluate(() => ['stockrecon', 'branchstmt', 'netprofit'].map((r) => [r, !!(window.BOS_PAGES && window.BOS_PAGES[r]), !!(window.BOS.ia && window.BOS.ia.byRoute(r))]));
  ok(reg.every((x) => x[1] && x[2]), 'routes registered in BOS_PAGES and ia.js: ' + JSON.stringify(reg));
  await ctx.close();
  ok(errors.length === 0, 'no page or console errors: ' + errors.slice(0, 3).join(' | '));
  await br.close(); srv.close();
  console.log(`recon118_test: ${pass} passed, ${bad} failed`); process.exit(bad ? 1 : 0);
})();
