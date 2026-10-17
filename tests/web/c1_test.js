// RPT-C1 screens: the notices in the hub reports (web/reportnotes.js + 3 hook sites in reports.js), #/expenseregister, #/statements, the cost-gaps block of #/costing, and the repaired Balance sheet widget of the owner board.
// Run: node tests/web/c1_test.js <abs dir tests/web>      (phone width 360, headless; the server calls are stand-ins, the SQL is tested in supabase/phase440..444_test.sql)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), http = require('http'), path = require('path');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web');
const base = C.baseData(SP);
const srv = http.createServer((q, r) => { const f = path.join(WEB, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
  r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8395);
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const P = M.p = Object.assign({ fail: {}, noStart: false, noPhase: false, dl: [] }, window.__P0 || {});
 const NOTES = [{ code: 'management_view', level: 'info', text_en: 'Management view, not the books.', text_bn: 'ম্যানেজমেন্ট ভিউ, হিসাবের খাতা নয়।', link: { route: 'profitcheck', label_en: 'Open Profit check', label_bn: 'Profit check খুলুন' }, basis: [{ code: 'salary', text_en: 'Salary: from the salary sheets.', text_bn: 'বেতন: শিট থেকে।' }] },
   { code: 'profit_incomplete', level: 'warn', text_en: '1 of 2 row(s) are incomplete: 1 without expenses.', text_bn: '২টির মধ্যে ১টি অসম্পূর্ণ।' }, { code: 'returns_line', level: 'info', text_en: 'Sale returns in this period: 1 return(s), 100.00.', text_bn: 'ফেরত ১টি।' }];
 const CAT = [{ key: 'l1_pnl', group: 'profit', allowed: true, kind: 'agg', name_bn: 'লাভ-ক্ষতি', name_en: 'Profit and loss (management view)', name_mix: 'Profit and loss', filters: ['date', 'locations'], dims: [{ key: 'location', time: false, label_bn: 'লোকেশন', label_en: 'Location' }], default_group: '', compare: false, needs_date: true, columns: [] }];
 const RES = { report: 'l1_pnl', columns: [{ key: 'location_id', type: 'id', role: 'dim', label_bn: '', label_en: '' }, { key: 'location_bn', type: 'text', role: 'dim', label_bn: 'লোকেশন', label_en: 'Location' }, { key: 'sales', type: 'money', role: 'measure', label_bn: 'বিক্রি', label_en: 'Sales' },
   { key: 'fixed', type: 'money', role: 'measure', label_bn: 'স্থির খরচ', label_en: 'Fixed cost' }, { key: 'profit', type: 'money', role: 'measure', label_bn: 'লাভ', label_en: 'Profit' }],
   rows: [{ location_id: 1, location_bn: 'test_shop', sales: 400, fixed: null, profit: null }], totals: { sales: 400, fixed: null, profit: null }, compare: null, page: { n: 1, size: 50, groups: 1, cap: 500 }, has_more: false, notes: [], data_needed: false,
   meta: { from: '2026-10-01', to: '2026-10-17', group: [], sort: null, dir: 'asc', cost_shown: true, today: '2026-10-17' } };
 const EXP = { from: '2026-10-01', to: '2026-10-17', location_id: null, basis: 'all', count: 3, limit: 100, offset: 0, has_more: false, shown_amount: 1090,
   totals: { report: 790, pl: 1102, daybook: 1090, journal: 837, journal_posted: 837, not_in_books: 1500, lines: 3 },
   recon: { agree: false, summary_en: 'Expense report 790.00; P&L 1,102.00; journal 837.00.', summary_bn: 'খরচ রিপোর্ট 790.00; P&L 1,102.00; জার্নাল 837.00।', unposted: { n: 0, amount: 0 },
     lines: [{ class: 'voucher_approved', label_en: 'Expense vouchers, approved', label_bn: 'ভাউচার', n: 1, amount: 500, report: 500, pl: 500, journal: 500, why_en: null, why_bn: null }, { class: 'quick', label_en: 'Quick expenses', label_bn: 'দ্রুত খরচ', n: 1, amount: 300, report: 0, pl: 300, journal: 300, why_en: 'Counted in the P&L; the expense report leaves it out.', why_bn: 'রিপোর্ট বাদ দেয়' }] },
   settings: { expense_count_on: 'as_today', report_expense_parity_on: false, d_wallet_fee_treatment: 'separate_expense' }, labels: { expense_heads: { transport: { bn: 'যাতায়াত', en: 'Transport' } }, marketing_heads: {} },
   rows: [{ key: 'voucher:1', source_id: 'e-1', kind: 'voucher', class: 'voucher_approved', status: 'approved', entry_date: '2026-10-17', location_id: 1, amount: 500, paid_to: null, ref: null, mode: 'cash', heads: [{ head: 'transport', amount: 500 }], in_report: true, in_pl: true, in_journal: true, posted: true, flags: [], no_receipt_amount: 0, unreadable: 0, staff: 'test_owner' },
     { key: 'quick:1', source_id: 'q-1', kind: 'quick', class: 'quick', status: 'done', entry_date: '2026-10-17', location_id: 1, amount: 300, paid_to: 'test_rider', ref: null, mode: 'cash', heads: null, in_report: false, in_pl: true, in_journal: true, posted: true, flags: ['no_receipt'], no_receipt_amount: 300, unreadable: 0, staff: 'test_owner' },
     { key: 'marketing:1', source_id: 'e-9', kind: 'marketing', class: 'marketing', status: 'submitted', entry_date: '2026-10-16', location_id: 1, amount: 1500, paid_to: 'test_campaign', ref: null, mode: 'imprest', heads: null, in_report: false, in_pl: false, in_journal: false, posted: false, flags: ['not_in_books', 'maybe_in_voucher'], no_receipt_amount: 0, unreadable: 0, staff: 'test_owner' }] };
 const NEED = { data_needed: true, reason: 'accounting_not_started', text_en: 'The accounting module is not switched on (no start date) - no data captured.', text_bn: 'হিসাব মডিউল চালু নেই - কোনো তথ্য সংগ্রহ হয়নি।' };
 const PL = { from: '2026-09-01', to: '2026-10-17', location_id: null, months: ['2026-09', '2026-10'], provisional: false, cogs_missing_entries: 0,
   outlets: [{ location_id: 1, name_bn: 'test_shop_1', name_en: 'test_shop_1', assigned: true }, { location_id: 2, name_bn: 'test_shop_2', name_en: 'test_shop_2', assigned: true }, { location_id: null, name_bn: 'x', name_en: 'Not assigned to an outlet', assigned: false }],
   cells: [{ month: '2026-09', location_id: 1, income: 5000, cogs: 0, gross: 5000, expenses: 0, net: 5000 }, { month: '2026-09', location_id: 2, income: 3000, cogs: 0, gross: 3000, expenses: 1000, net: 2000 }, { month: '2026-10', location_id: 1, income: 600, cogs: 84, gross: 516, expenses: 1177, net: -661 }, { month: '2026-10', location_id: null, income: 70, cogs: 0, gross: 70, expenses: 0, net: 70 }],
   by_month: [{ month: '2026-09', income: 8000, cogs: 0, gross: 8000, expenses: 1000, net: 7000 }, { month: '2026-10', income: 670, cogs: 84, gross: 586, expenses: 1177, net: -591 }],
   by_outlet: [{ location_id: 1, income: 5600, cogs: 84, gross: 5516, expenses: 1177, net: 4339 }, { location_id: 2, income: 3000, cogs: 0, gross: 3000, expenses: 1000, net: 2000 }, { location_id: null, income: 70, cogs: 0, gross: 70, expenses: 0, net: 70 }],
   grand: { income: 8670, cogs: 84, gross: 8586, expenses: 2177, net: 6409 }, notes: [{ code: 'unassigned_outlet', level: 'info', text_en: 'Some journal lines have no outlet; they are on their own row.', text_bn: 'কিছু লাইনে আউটলেট নেই।' }],
   basis: { text_en: 'From the journal (the books). It is not the management view of the hub reports.', text_bn: 'জার্নাল থেকে।' } };
 const CF = { from: '2026-09-01', to: '2026-10-17', location_id: null, opening: 0, flows: 4763, opening_in_period: 950000, transfers_netted: 2000, transfer_entries: 1, unallocated: 0, closing: 954763, opening_through: '2026-09-01',
   classes: [{ class: 'operating', in: 8812, out: 2049, net: 6763, accounts: [{ account_id: 30, code: '4100', name_bn: 'বিক্রয়', name_en: 'Sales', in: 8700, out: 0, net: 8700 }] }, { class: 'investing', in: 0, out: 4000, net: -4000, accounts: [] }, { class: 'financing', in: 2000, out: 0, net: 2000, accounts: [] }, { class: 'unclassified', in: 0, out: 0, net: 0, accounts: [] }],
   by_source: [{ category: 'sale', in: 700, out: 0, net: 700 }], notes: [{ code: 'opening_in_period', level: 'info', text_en: 'Opening balances posted inside this period (950,000.00) are not a flow.', text_bn: 'শুরুর ব্যালেন্স' }],
   basis: { text_en: 'Direct method from the journal.', text_bn: 'সরাসরি পদ্ধতি।' } };
 const WC = { as_of: '2026-10-17', location_id: null, formula: { cash: 954763, receivables: 0, inventory: -24, payables: 400, working_capital: 954339 },
   by_class: { totals: { current_assets: 954739, current_liabilities: 400, non_current_assets: 4000, non_current_liabilities: 0, unclassified_assets: 0, unclassified_liabilities: 0 }, working_capital: 954339, classed_accounts: 7, unclassified_accounts: 0,
     current_assets: [{ account_id: 3, code: '1110', name_bn: 'নগদ', name_en: 'Cash in hand', amount: 906800 }], current_liabilities: [{ account_id: 20, code: '2100', name_bn: 'পাওনা', name_en: 'Supplier payables', amount: 400 }], non_current_assets: [{ account_id: 17, code: '1510', name_bn: 'স্থায়ী', name_en: 'Fixed assets', amount: 4000 }], non_current_liabilities: [], unclassified_assets: [], unclassified_liabilities: [] },
   notes: [], basis: { text_en: 'From the journal up to the date.', text_bn: 'জার্নাল' } };
 const WC0 = Object.assign(clone(WC), { by_class: Object.assign(clone(WC.by_class), { working_capital: null, classed_accounts: 0, current_assets: [], current_liabilities: [], non_current_assets: [], unclassified_assets: [{ account_id: 3, code: '1110', name_bn: 'নগদ', name_en: 'Cash in hand', amount: 906800 }] }), notes: [{ code: 'no_current_class', level: 'warn', text_en: 'No account is classed current yet, so working capital by class is not calculated (not captured).', text_bn: 'সংগ্রহ হয়নি' }] });
 const CLS = [{ id: 3, code: '1110', name_bn: 'নগদ', name_en: 'Cash in hand', type: 'asset', active: true, is_cash: true, cf_class: null, bs_class: 'current', suggest_cf: null, suggest_bs: 'current' }, { id: 30, code: '4100', name_bn: 'বিক্রয়', name_en: 'Sales', type: 'income', active: true, is_cash: false, cf_class: null, bs_class: null, suggest_cf: 'operating', suggest_bs: null },
   { id: 17, code: '1510', name_bn: 'স্থায়ী', name_en: 'Fixed assets', type: 'asset', active: true, is_cash: false, cf_class: 'investing', bs_class: 'non_current', suggest_cf: 'investing', suggest_bs: 'non_current' }];
 const known = ['report_catalog', 'report_presets', 'report_run', 'report_notes', 'expense_register', 'stmt_pl_matrix', 'stmt_pl_drill', 'stmt_cash_flow', 'stmt_cf_drill', 'stmt_working_capital', 'coa_class_list', 'coa_class_set', 'coa_class_apply_suggested', 'acct_cash_flow', 'c1_export_log', 'set_rule', 'd_recipe_cost_gaps', 'acct_balance_sheet', 'balance_sheet'];
 c.rpc = async (fn, args) => {
  if (!known.includes(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (P.fail[fn]) return { data: null, error: { message: P.fail[fn] } };
  if (P.noPhase && /^(report_notes|expense_register|stmt_|coa_class|c1_export_log)/.test(fn)) return { data: null, error: { message: 'Could not find the function public.' + fn, code: 'PGRST202' } };
  if (fn === 'report_catalog') return { data: CAT, error: null };
  if (fn === 'report_presets') return { data: { this_month: { from: '2026-10-01', to: '2026-10-17' }, today: { from: '2026-10-17', to: '2026-10-17' } }, error: null };
  if (fn === 'report_run') return { data: clone(RES), error: null };
  if (fn === 'report_notes') return { data: clone(NOTES), error: null };
  if (fn === 'expense_register') { const e = clone(EXP); e.basis = args.p_basis; if (args.p_basis === 'report') { e.rows = e.rows.filter((r) => r.in_report); e.count = e.rows.length; } return { data: e, error: null }; }
  if (fn === 'stmt_pl_matrix') return { data: P.noStart ? clone(NEED) : clone(PL), error: null };
  if (fn === 'stmt_pl_drill') return { data: { month: '2026-09', accounts: [{ account_id: 30, code: '4100', name_bn: 'বিক্রয়', name_en: 'Sales', kind: 'income', amount: 5000, lines: 1 }], entries: [{ entry_id: 'j1', entry_date: '2026-09-05', source_type: 'manual', memo: 'test cash sale p1', kind: 'income', amount: 5000 }] }, error: null };
  if (fn === 'stmt_cash_flow') return { data: P.noStart ? clone(NEED) : clone(CF), error: null };
  if (fn === 'stmt_cf_drill') return { data: { rows: [{ entry_id: 'j2', entry_date: '2026-09-10', source_type: 'manual', memo: 'test fixed asset', class: 'investing', account_id: 17, account_code: '1510', amount: -4000 }] }, error: null };
  if (fn === 'stmt_working_capital') return { data: P.noStart ? clone(NEED) : (P.noClass ? clone(WC0) : clone(WC)), error: null };
  if (fn === 'coa_class_list') return { data: clone(CLS), error: null };
  if (fn === 'coa_class_set') return { data: { account_id: args.p_account }, error: null };
  if (fn === 'coa_class_apply_suggested') return { data: { dry: args.p_dry, accounts: 12 }, error: null };
  if (fn === 'acct_cash_flow') return { data: { closing: P.tabClosing === undefined ? 954763 : P.tabClosing, rows: [] }, error: null };
  if (fn === 'c1_export_log') return { data: null, error: null };
  if (fn === 'set_rule') return { data: null, error: null };
  if (fn === 'd_recipe_cost_gaps') return { data: [{ item_id: 'i9', code: 'RM-9', name_bn: 'test_material', name_en: 'test_material', kind: 'ingredient', roles: ['sugar'], recipes: 2, method: 'average_purchase' }], error: null };
  if (fn === 'acct_balance_sheet') return { data: P.noStart ? { data_needed: true } : { as_of: args.p_as_of, total_assets: 958699, total_liabilities_and_equity: 958699, difference: 0, unbalanced: false }, error: null };
  if (fn === 'balance_sheet') return { data: null, error: { message: 'Could not find the function public.balance_sheet' } };
  return { data: null, error: null };
 };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } };
  async function open(o, hash, lang) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/404/.test(m.text()) && !/not allowed/.test(m.text()) && !/Could not find/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o); data.tables.locations = data.tables.locations || [];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__P0=${JSON.stringify(o.p || {})};${o.owner === false ? 'window.__OWNER=false;' : ''}try{localStorage.setItem('bos_lang','${lang || 'en'}')}catch(e){}`);
    await p.goto('http://localhost:8395/' + (o.hash0 || '')); await p.waitForTimeout(1200);
    await p.evaluate(() => { location.hash = '#/x'; }); await p.waitForTimeout(100);
    await p.evaluate((h) => { location.hash = h; }, hash); await p.waitForTimeout(1000);
    return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const text = (p, sel) => p.evaluate((s) => (document.querySelector(s) || document.body).innerText, sel || 'body');
  const dl = async (p, sel) => { const [d] = await Promise.all([p.waitForEvent('download'), p.click(sel)]); const f = await d.path(); return { name: d.suggestedFilename(), text: fs.readFileSync(f, 'utf8') }; };

  // ---------------- 1. hub report: notices, link, not captured, CSV
  let p = await open({}, '#/report/l1_pnl');
  ok((await calls(p, 'report_notes')).length === 1, 'the hub asks for the notices once per run');
  let nc = (await calls(p, 'report_notes'))[0]; ok(nc.p_key === 'l1_pnl' && Array.isArray(nc.p_cols) && nc.p_cols.includes('profit'), 'notices asked with the report key and the columns');
  let t = await text(p, '#rp_res');
  ok(/Management view, not the books/.test(t) && /incomplete/.test(t) && /Sale returns in this period/.test(t), 'the three notices are shown (en)');
  ok(await p.locator('#rp_res a[href="#/profitcheck"]').count() === 1, 'the management notice links to Profit check');
  ok(await p.locator('#rp_res details.rp-basis').count() === 1, 'the basis lines are in a fold-out');
  ok(/Not captured/.test(await text(p, '#rp_tbl tfoot')), 'a total with no value shows Not captured, not 0 and not blank');
  ok(!/\b0\b/.test(await text(p, '#rp_tbl tfoot').then((x) => x.replace(/400/g, ''))), 'no 0 in the total row');
  await noOverflow(p, 'hub report with notices');
  const f = await dl(p, '[data-act=rp_csv]');
  ok(/not captured/.test(f.text) && /Management view, not the books/.test(f.text) && /Salary: from the salary sheets/.test(f.text), 'the CSV carries "not captured" and the notices with their basis lines');
  await p.close();
  p = await open({ p: { noPhase: true } }, '#/report/l1_pnl');
  ok(await p.locator('#rp_tbl').count() === 1 && await p.locator('.rp-c1').count() === 0, 'an old database (no report_notes): the report still draws, no notice, no error');
  await p.close();
  p = await open({}, '#/report/l1_pnl', 'bn');
  ok(/ম্যানেজমেন্ট ভিউ, হিসাবের খাতা নয়/.test(await text(p, '#rp_res')), 'the notice follows the language (bn)');
  await noOverflow(p, 'bn'); await p.close();

  // ---------------- 2. expense register
  p = await open({}, '#/expenseregister');
  let c = await calls(p, 'expense_register'); ok(c.length === 1 && c[0].p_basis === 'all' && /^\d{4}-\d{2}-01$/.test(c[0].p_from) && c[0].p_loc === null && c[0].p_limit === 100, 'the register opens for the month so far, every line, all places');
  t = await text(p, '#er_res');
  ok(/Expense report\s*৳ 790/.test(t.replace(/\n/g, ' ')) && /1,102/.test(t) && /837/.test(t) && /1,500/.test(t), 'the three totals and the 18-1 amount are shown');
  ok(/The totals differ/.test(t) && /Why the totals differ/.test(t), 'the reconciliation is there and says the totals differ');
  ok(await p.locator('[data-act=er_open]').count() === 3, 'three lines');
  ok(/Expense report ✓/.test(await text(p, '#er_res')) && /Expense report –/.test(await text(p, '#er_res')), 'each line shows which totals count it (tick and dash)');
  await noOverflow(p, 'expense register');
  await p.click('[data-act=er_basis][data-b=report]'); await p.waitForTimeout(500);
  c = await calls(p, 'expense_register'); ok(c[c.length - 1].p_basis === 'report', 'tapping a total lists the lines behind it (basis report)');
  ok(await p.locator('[data-act=er_open]').count() === 1, 'only the line the expense report counts');
  await p.click('[data-act=er_basis][data-b=report]'); await p.waitForTimeout(500);
  c = await calls(p, 'expense_register'); ok(c[c.length - 1].p_basis === 'all', 'tapping it again goes back to every line');
  await p.click('[data-act=er_kind][data-k=quick]'); await p.click('[data-act=er_run]'); await p.waitForTimeout(500);
  c = await calls(p, 'expense_register'); ok(JSON.stringify(c[c.length - 1].p_kinds) === '["quick"]', 'the kind chip filters');
  await p.click('[data-act=er_kind][data-k=quick]'); await p.click('[data-act=er_run]'); await p.waitForTimeout(400);
  await p.click('[data-act=er_open] >> nth=2'); await p.waitForTimeout(300);
  t = await text(p, '#sheet');
  ok(/1,500/.test(t) && /test_campaign/.test(t) && /Not in the books/.test(t) && /may also be typed as a voucher/.test(t), 'the line detail shows the amount, paid to and the notes');
  ok(await p.locator('#sheet a[href="#/entry/e-9"]').count() === 1, 'a link opens the source record');
  await p.click('#sheet .sheet-x'); await p.waitForTimeout(150);
  const f2 = await dl(p, '[data-act=er_csv]');
  ok(/Expense register/.test(f2.text) && /test_rider/.test(f2.text) && /Why the totals differ/.test(f2.text) && /Totals agree,no/.test(f2.text), 'the CSV has the lines, the totals and the reconciliation');
  ok((await calls(p, 'c1_export_log')).length === 1 && (await calls(p, 'c1_export_log'))[0].p_key === 'expense_register', 'the export is checked and logged on the server first');
  const nBefore = (await calls(p, 'expense_register')).length;
  await p.fill('#er_from', '2026-10-17'); await p.fill('#er_to', '2026-10-01'); await p.click('[data-act=er_run]'); await p.waitForTimeout(200);
  ok((await calls(p, 'expense_register')).length === nBefore, 'a reversed range is not sent');
  await p.close();
  p = await open({ p: { fail: { expense_register: 'not allowed' } } }, '#/expenseregister');
  ok(/Not allowed/.test(await text(p, '#er_res')), 'a refusal is shown in words'); await p.close();
  p = await open({ p: { noPhase: true } }, '#/expenseregister');
  ok(/not installed/.test(await text(p, '#er_res')), 'an old database says the database part is missing'); await p.close();
  for (const lang of ['bn', 'mix']) { p = await open({}, '#/expenseregister', lang); await noOverflow(p, 'expense register ' + lang); ok(await p.locator('[data-act=er_open]').count() === 3, 'lines in ' + lang); await p.close(); }

  // ---------------- 3. statements
  p = await open({}, '#/statements');
  c = await calls(p, 'stmt_pl_matrix'); ok(c.length === 1 && c[0].p_from === null && c[0].p_loc === null, 'the P&L opens from the start of the books');
  t = await text(p, '#st_res');
  ok(/Sep 2026/.test(t) && /Oct 2026/.test(t) && /Not assigned to an outlet/.test(t) && /6,409/.test(t), 'months in columns, outlets in rows, the grand total');
  await noOverflow(p, 'P&L matrix'); ok(await p.locator('#st_pl_tbl').count() === 1, 'matrix table');
  await p.selectOption('#st_metric', 'income'); await p.click('[data-act=st_run]'); await p.waitForTimeout(400);
  ok(/8,670/.test(await text(p, '#st_pl_tbl')), 'the measure selector changes the figures (income grand total)');
  await p.click('[data-act=st_cell][data-m="2026-09"][data-l="1"]'); await p.waitForTimeout(400);
  c = await calls(p, 'stmt_pl_drill'); ok(c.length === 1 && c[0].p_month === '2026-09-01' && c[0].p_loc === 1 && c[0].p_unassigned === false, 'a cell opens the drill-down for that month and outlet');
  t = await text(p, '#sheet'); ok(/4100/.test(t) && /test cash sale p1/.test(t), 'accounts and entries behind the cell'); await p.click('#sheet .sheet-x');
  ok(await p.locator('a[href="#/profitcheck"]').count() >= 1 && await p.locator('a[href="#/report/l1_pnl"]').count() === 1, 'the link to Profit check and the management view');
  const f3 = await dl(p, '[data-act=st_csv]');
  ok(/Not assigned to an outlet/.test(f3.text) && /^﻿outlet,2026-09,2026-10,total/.test(f3.text) && /From the journal/.test(f3.text), 'P&L CSV'); ok((await calls(p, 'c1_export_log'))[0].p_key === 'stmt_pl_matrix', 'P&L export logged');
  // cash flow
  await p.click('[data-act=st_tab][data-v=cf]'); await p.waitForTimeout(300); await p.click('[data-act=st_run]'); await p.waitForTimeout(600);
  t = await text(p, '#st_res');
  ok(/Operating/.test(t) && /Investing/.test(t) && /Financing/.test(t) && /Unclassified/.test(t) && /954763/.test(t.replace(/,/g, '')) && /950000/.test(t.replace(/,/g, '')), 'classes, opening journals and closing shown');
  ok(/Closing agrees with the Cash flow tab/.test(t), 'closing is compared with the existing Cash flow tab');
  await noOverflow(p, 'cash flow');
  await p.click('[data-act=st_cfclass][data-c=investing]'); await p.waitForTimeout(400);
  c = await calls(p, 'stmt_cf_drill'); ok(c.length === 1 && c[0].p_class === 'investing' && c[0].p_account === null, 'a class opens its drill-down'); ok(/test fixed asset/.test(await text(p, '#sheet')), 'the entries behind the class'); await p.click('#sheet .sheet-x');
  await p.fill('#st_thr', '2026-09-01'); await p.click('[data-act=st_thr_save]'); await p.waitForTimeout(500);
  c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'report_cf_opening_through' && c[0].p_value === '2026-09-01', 'the owner sets the opening-balance date');
  const f4 = await dl(p, '[data-act=st_csv]'); ok(/operating/.test(f4.text) && /Cash-flow statement/.test(f4.text) && /954763/.test(f4.text), 'cash flow CSV');
  // working capital
  await p.click('[data-act=st_tab][data-v=wc]'); await p.waitForTimeout(300); await p.click('[data-act=st_run]'); await p.waitForTimeout(500);
  t = await text(p, '#st_res'); ok(/Working capital/.test(t) && /954339/.test(t.replace(/,/g, '')) && /Plain formula/.test(t), 'working capital by class and the formula'); await noOverflow(p, 'working capital');
  const f5 = await dl(p, '[data-act=st_csv]'); ok(/working_capital_by_class,,,954339/.test(f5.text), 'working capital CSV');
  await p.close();
  p = await open({ p: { noClass: true } }, '#/statements');
  await p.click('[data-act=st_tab][data-v=wc]'); await p.waitForTimeout(200); await p.click('[data-act=st_run]'); await p.waitForTimeout(500);
  t = await text(p, '#st_res'); ok(/Not captured/.test(t) && /not calculated/.test(t) && /Assets with no class/.test(t), 'no class at all: working capital says Not captured, never 0');
  const f6 = await dl(p, '[data-act=st_csv]'); ok(/not captured/.test(f6.text), 'and so does its CSV'); await p.close();
  // classes
  p = await open({}, '#/statements');
  await p.click('[data-act=st_tab][data-v=cls]'); await p.waitForTimeout(500);
  ok(await p.locator('#st_res .card[data-id]').count() === 3, 'three accounts listed'); await noOverflow(p, 'classes');
  ok(await p.locator('[data-id="3"] select').first().isDisabled(), 'a cash account has no cash-flow class (disabled)');
  ok(await p.locator('[data-id="30"] select').nth(1).isDisabled(), 'a balance class is only for assets and liabilities');
  await p.selectOption('[data-id="30"] select >> nth=0', 'operating'); await p.click('[data-act=st_clsave][data-id="30"]'); await p.waitForTimeout(500);
  c = await calls(p, 'coa_class_set'); ok(c.length === 1 && c[0].p_account === 30 && c[0].p_cf === 'operating' && c[0].p_bs === null, 'a class is saved for one account');
  await p.click('[data-act=st_clblank]'); ok(await p.locator('#st_res .card[data-id]').count() === 1, 'only accounts with a blank class');
  await p.click('[data-act=st_clprev]'); await p.waitForTimeout(400);
  c = await calls(p, 'coa_class_apply_suggested'); ok(c.length === 1 && c[0].p_dry === true, 'the preview is a dry run'); ok(/12 accounts would get a class/.test(await text(p, '#st_res')), 'the preview says how many');
  await p.click('[data-act=st_clapply]'); await p.waitForTimeout(200); ok((await calls(p, 'coa_class_apply_suggested')).length === 1, 'apply without a reason is not sent');
  await p.fill('#st_clwhy', 'usual practice, owner agreed'); await p.click('[data-act=st_clapply]'); await p.waitForTimeout(500);
  c = await calls(p, 'coa_class_apply_suggested'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_reason === 'usual practice, owner agreed', 'apply sent with its reason');
  const f7 = await dl(p, '[data-act=st_csv]'); ok(/cash_flow_class/.test(f7.text) && /4100/.test(f7.text), 'classes CSV'); await p.close();
  // no accounting start date
  p = await open({ p: { noStart: true } }, '#/statements');
  ok(/no data captured/.test(await text(p, '#st_res')) && !/৳ \d/.test(await text(p, '#st_res')), 'without the start date: the notice and no number');
  await p.click('[data-act=st_tab][data-v=cf]'); await p.click('[data-act=st_run]'); await p.waitForTimeout(400); ok(/no data captured/.test(await text(p, '#st_res')), 'cash flow: same');
  await p.click('[data-act=st_tab][data-v=wc]'); await p.click('[data-act=st_run]'); await p.waitForTimeout(400); ok(/no data captured/.test(await text(p, '#st_res')), 'working capital: same');
  await p.close();
  p = await open({ p: { fail: { stmt_pl_matrix: 'not allowed' } } }, '#/statements'); ok(/Not allowed/.test(await text(p, '#st_res')), 'a refusal is shown'); await p.close();
  for (const lang of ['bn', 'mix']) { p = await open({}, '#/statements', lang); await noOverflow(p, 'statements ' + lang); await p.close(); }

  // ---------------- 4. costing: the cost-gaps block
  p = await open({}, '#/costing');
  await p.waitForTimeout(500);
  c = await calls(p, 'd_recipe_cost_gaps'); ok(c.length >= 1, 'costing asks for the materials with no cost'); t = await text(p, '#cs_gaps');
  ok(/RM-9/.test(t) && /Ingredients and packaging with no cost/.test(t), 'the materials with no cost are listed'); await noOverflow(p, 'costing gaps');
  const f8 = await dl(p, '[data-act=cs_gapcsv]'); ok(/RM-9/.test(f8.text) && /average_purchase/.test(f8.text), 'gaps CSV'); await p.close();

  // ---------------- 5. owner board: the balance sheet widget calls the books function
  p = await open({}, '#/home');
  const bs = await p.evaluate(async () => { const B = window.BOS; const w = B.ownerboard && B.ownerboard.KINDS && B.ownerboard.KINDS.balance_check; if (!w) return 'nokind'; try { const r = await w.load({ td: '2026-10-17' }); return r; } catch (e) { return 'err:' + e.message; } });
  ok(bs && typeof bs === 'object' && bs.tone === 'ok', 'the balance widget loads from acct_balance_sheet and is green when balanced (got ' + JSON.stringify(bs) + ')');
  c = await calls(p, 'acct_balance_sheet'); ok(c.length === 1 && c[0].p_as_of === '2026-10-17', 'the widget calls acct_balance_sheet with the date');
  ok((await calls(p, 'balance_sheet')).length === 0, 'the dead balance_sheet call is gone');
  await p.close();

  ok(errors.length === 0, 'page errors: ' + errors.slice(0, 5).join(' | '));
  await br.close(); srv.close();
  console.log(bad ? 'FAILED: ' + bad : 'ALL PASS');
  process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e); srv.close(); process.exit(2); } })();
