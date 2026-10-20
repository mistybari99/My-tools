// Module A (accounting) web page #/accounts: overview, unbalanced warning, Post now (dry run first), tabs (statements, trial balance, ledger, journal book,
// parties), manual journal validation, opening balances, chart of accounts, settings & mappings, print + CSV, "Data needed", no-permission text.
// Run: node accounts_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const ROW = (id, code, bn, en, type, side, parent, grp) => ({ id, code, name_bn: bn, name_en: en, type, normal_side: side, parent_id: parent || null, is_group: !!grp, is_system: true, active: true, sort: id });
const COA = [ROW(1, '1000', 'সম্পদ', 'Assets', 'asset', 'debit', null, true), ROW(2, '1110', 'হাতে নগদ', 'Cash in hand', 'asset', 'debit', 1), ROW(3, '1210', 'গ্রাহকের বাকি', 'Customer receivables', 'asset', 'debit', 1),
  ROW(4, '2000', 'দায়', 'Liabilities', 'liability', 'credit', null, true), ROW(5, '2100', 'সরবরাহকারীর পাওনা', 'Supplier payables', 'liability', 'credit', 4), ROW(6, '3100', 'মালিকের মূলধন', 'Owner capital', 'equity', 'credit', null),
  ROW(7, '4100', 'বিক্রয়', 'Sales', 'income', 'credit', null), ROW(8, '5300', 'ভাড়া', 'Rent', 'expense', 'debit', null), ROW(9, '3900', 'জমা মুনাফা', 'Retained earnings', 'equity', 'credit', null)];
const MAPS = [{ key: 'pay_cash', account_id: 2, label_bn: 'নগদ টাকা', label_en: 'Cash payments' }, { key: 'receivable', account_id: 3, label_bn: 'গ্রাহকের বাকি', label_en: 'Customer receivable' }];
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const A = window.__ACC;
 c.rpc = async (fn, args) => {
  (window.__ACALLS = window.__ACALLS || []).push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (!/^acct_|^set_rule$|^inventory_vs_gl$|^opening_balance_post$/.test(fn)) return rpc(fn, args);
  const err = (m) => ({ data: null, error: { message: m, code: 'P0001' } });
  if (A.fail && A.fail[fn]) { const m = A.fail[fn]; if (!A.keep) delete A.fail[fn]; return err(m); }
  if (fn === 'acct_status') return { data: A.status, error: null };
  if (fn === 'acct_overview') return { data: A.status.start ? A.overview : { data_needed: true, on: true }, error: null };
  if (fn === 'acct_balance_sheet') return { data: A.status.start ? A.bs : { data_needed: true }, error: null };
  if (fn === 'acct_income_statement') return { data: A.status.start ? A.pl : { data_needed: true }, error: null };
  if (fn === 'acct_cash_flow') return { data: A.cf, error: null };
  if (fn === 'acct_trial_balance') return { data: A.tb, error: null };
  if (fn === 'acct_ledger') return { data: A.ledger, error: null };
  if (fn === 'acct_journal_book') return { data: A.book, error: null };
  if (fn === 'acct_party_ledger') return { data: A.party, error: null };
  if (fn === 'acct_reconcile') return { data: A.reco, error: null };
  if (fn === 'inventory_vs_gl') return { data: A.inv, error: null };
  if (fn === 'acct_post_pending') return { data: args.p_dry ? A.dry : A.real, error: null };
  if (fn === 'acct_set_start') { A.status.start = args.p_date; return { data: { start: args.p_date }, error: null }; }
  if (fn === 'set_rule') { if (args.p_key === 'accounting_on') A.status.on = args.p_value; if (args.p_key === 'accounting_autopost') A.status.autopost = args.p_value; return { data: null, error: null }; }
  if (fn === 'acct_journal_post') {
    let d = 0, k = 0; (args.p_lines || []).forEach((l) => { d += l.debit || 0; k += l.credit || 0; });
    if (d !== k) return err('unbalanced: debit ' + d + ' credit ' + k + ' (entry 1)');
    if (args.p_dry) return { data: { dry: true, total_debit: d, total_credit: k, lines: args.p_lines.length }, error: null };
    return { data: { id: 77, total: d }, error: null }; }
  if (fn === 'acct_opening') { let d = 0, k = 0; (args.p_lines || []).forEach((l) => { d += l.debit || 0; k += l.credit || 0; });
    const diff = Math.round((d - k) * 100) / 100; if (diff !== 0 && !args.p_plug) return err('unbalanced: debit ' + d + ' credit ' + k);
    if (args.p_dry) return { data: { dry: true, total_debit: Math.max(d, k), total_credit: Math.max(d, k), plug: diff }, error: null };
    A.status.opening = true; return { data: { id: 5, plug: diff }, error: null }; }
  if (fn === 'opening_balance_post') { const t = JSON.stringify(args.p_json || {}); const bal = /"amount":100\\b/.test(t) && /"amount":100\\b.*"amount":100\\b/.test(t);
    if (args.p_dry) return { data: { dry: true, total_debit: 100, total_credit: bal ? 100 : 60, difference: bal ? 0 : 40, balanced: bal }, error: null };
    if (!bal) return err('unbalanced: debit 100 credit 60'); A.status.opening = true; return { data: { id: 6 }, error: null }; }
  if (fn === 'acct_account_save') { if (args.p_id === null && args.p_code === '1110') return err('code_taken'); return { data: { id: 99, code: args.p_code }, error: null }; }
  if (fn === 'acct_mapping_set') return { data: { key: args.p_key }, error: null };
  if (fn === 'acct_journal_reverse') return { data: { id: 88 }, error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
const IS = (o) => ({ from: '2026-10-01', to: '2026-10-13', income: [{ id: 7, code: '4100', name_bn: 'বিক্রয়', name_en: 'Sales', parent_id: null, is_group: false, amount: 2050 }], expense: [{ id: 8, code: '5300', name_bn: 'ভাড়া', name_en: 'Rent', parent_id: null, is_group: false, amount: 1400 }],
  total_income: 2050, total_expense: 1400, cogs: 900, gross_profit: 1150, net_profit: 650, cogs_missing: o.cm || 0, unknown_cost_rev: o.unk || 0, cogs_estimate_missing: o.unk ? 200 : 0, provisional: !!o.unk });
const BS = (o = {}) => ({ as_of: '2026-10-13', assets: [{ id: 1, code: '1000', name_bn: 'সম্পদ', name_en: 'Assets', parent_id: null, is_group: true, amount: 10180 }, { id: 2, code: '1110', name_bn: 'হাতে নগদ', name_en: 'Cash in hand', parent_id: 1, is_group: false, amount: 10180 }],
  liabilities: [{ id: 5, code: '2100', name_bn: 'সরবরাহকারীর পাওনা', name_en: 'Supplier payables', parent_id: null, is_group: false, amount: 3800 }], equity: [{ id: 6, code: '3100', name_bn: 'মালিকের মূলধন', name_en: 'Owner capital', parent_id: null, is_group: false, amount: 5730 }],
  total_assets: 10180, total_liabilities: 3800, total_equity: 5730, retained_earnings: 650, total_equity_and_earnings: 6380, total_liabilities_and_equity: 10180, unbalanced: !!o.unbal, difference: o.unbal ? 25 : 0, cogs_missing: o.cm || 0 });
function acc(o = {}) {
  const status = Object.assign({ on: true, autopost: true, start: '2026-10-01', can_manage: true, owner: true, opening: false, entries: 17, accounts: 9, last_post: null }, o.status || {});
  return { status, overview: { start: status.start, on: status.on, balance_sheet: {}, income_month: { total_income: 2050, total_expense: 1400, net_profit: 650, cogs: 900, gross_profit: 1150, from: '2026-10-01' }, status },
    bs: BS(o), pl: IS(o), cf: { from: '2026-10-01', to: '2026-10-13', opening: 0, rows: [{ category: 'sale', in: 1800, out: 0, net: 1800 }, { category: 'bank_deposit', in: 300, out: 300, net: 0 }], total_in: 2100, total_out: 300, closing: 1800 },
    tb: { from: '2026-10-01', to: '2026-10-13', rows: [{ id: 2, code: '1110', name_bn: 'হাতে নগদ', name_en: 'Cash in hand', type: 'asset', parent_id: null, is_group: false, open_dr: 0, open_cr: 0, dr: 6230, cr: 0, close_dr: 6230, close_cr: 0 },
      { id: 6, code: '3100', name_bn: 'মালিকের মূলধন', name_en: 'Owner capital', type: 'equity', parent_id: null, is_group: false, open_dr: 0, open_cr: 0, dr: 0, cr: 6230, close_dr: 0, close_cr: 6230 }], total_debit: 6230, total_credit: 6230, balanced: true, diff: 0 },
    ledger: { account: { id: 2, code: '1110', name_bn: 'হাতে নগদ', name_en: 'Cash in hand', type: 'asset', normal_side: 'debit', is_group: false }, from: '2026-10-01', to: '2026-10-13', opening: 0, closing: 1500,
      rows: [{ date: '2026-10-02', entry_id: 3, line_no: 1, memo: 'Receipt 1', source_type: 'sale', source_id: 'abcdef12-0000', account_code: '1110', debit: 1000, credit: 0, balance: 1000, reversal: false }, { date: '2026-10-03', entry_id: 4, line_no: 1, memo: 'Cash move: owner_topup', source_type: 'cash_move', source_id: 'fedcba98-0000', account_code: '1110', debit: 500, credit: 0, balance: 1500, reversal: false }], truncated: false },
    book: { from: '2026-10-01', to: '2026-10-13', total: 2, rows: [{ id: 9, date: '2026-10-05', location_id: 1, source_type: 'manual', source_id: 'x1', memo: 'Rent for October', status: 'posted', reverses_id: null, flags: null, lines: [{ line_no: 1, code: '5300', name_bn: 'ভাড়া', name_en: 'Rent', debit: 3000, credit: 0 }, { line_no: 2, code: '1110', name_bn: 'হাতে নগদ', name_en: 'Cash in hand', debit: 0, credit: 3000 }] },
      { id: 8, date: '2026-10-04', location_id: 1, source_type: 'sale', source_id: 'abcdef12-0000', memo: 'Receipt 1', status: 'posted', reverses_id: null, flags: 'cogs_missing', lines: [{ line_no: 1, code: '1110', name_bn: 'হাতে নগদ', name_en: 'Cash in hand', debit: 500, credit: 0 }, { line_no: 2, code: '4100', name_bn: 'বিক্রয়', name_en: 'Sales', debit: 0, credit: 500 }] }] },
    party: { party_type: 'customer', party_id: 'c1', from: '2026-10-01', to: '2026-10-13', opening: 0, closing: 150, rows: [{ date: '2026-10-04', entry_id: 8, memo: 'Receipt 2', source_type: 'sale', source_id: 'aaaa1111', account_code: '1210', debit: 250, credit: 0, balance: 250 }, { date: '2026-10-05', entry_id: 10, memo: 'Due collection', source_type: 'collection', source_id: '7', account_code: '1210', debit: 0, credit: 100, balance: 150 }] },
    inv: { as_of: '2026-10-13', location_id: null, start: '2026-10-01', valuation_basis: 'average_cost', agree: false, total: { gl: 3040, valuation: 2940, diff: 100, unexplained: 0 },
      rows: [{ key: 'inv_raw', code: '1320', name_bn: 'মজুত: কাঁচামাল', name_en: 'Raw materials', gl: 3040, valuation: 2940, ledger_value: 2940, diff: 100, unexplained: 0,
        reasons: [{ code: 'count_adjust', amount: 150 }, { code: 'opening', amount: -250 }, { code: 'transfer', amount: 300 }, { code: 'manual_journal', amount: 40 }, { code: 'mystery_new_code', amount: -140 }] }] },
    reco: { start: '2026-10-01', customers: [], customers_off: 0, suppliers: [{ party_id: 's1', name: 'Sugar Co', journal: 3800, existing: 3100, difference: 700, unexplained: 700 }], suppliers_off: 1, unattributed_receivable: 0 },
    dry: { dry: true, start: '2026-10-01', posted: 3, reversed: 1, by_type: { sale: 2, purchase: 1, sale_reversed: 1 }, locked: 0, waiting: { cost_missing: 1 }, cogs_missing: 1, errors: [], more: false, total_debit: 1500, total_credit: 1500,
      trial: [{ code: '1110', name_bn: 'হাতে নগদ', name_en: 'Cash in hand', debit: 1500, credit: 0 }, { code: '4100', name_bn: 'বিক্রয়', name_en: 'Sales', debit: 0, credit: 1500 }],
      preview: [{ date: '2026-10-13', source_type: 'sale', source_id: 's1', memo: 'Receipt 7', lines: [{ code: '1110', debit: 1500, credit: 0 }, { code: '4100', debit: 0, credit: 1500 }] }] },
    real: { dry: false, posted: 3, reversed: 1, by_type: {}, locked: 0, waiting: {}, cogs_missing: 1, errors: o.realErr || [], more: false, skipped_sources: [] }, fail: o.fail || {} };
}
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', async (d) => { if (d.type() === 'prompt') await d.accept(o.reason || 'booked to the wrong month'); else await d.accept(); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: ((h) => (/accounts\.js/.test(h) ? h : h.replace('<script src="cashmoves.js"></script>', '<script src="cashmoves.js"></script><script src="accounts.js"></script>')))(fs.readFileSync(WEB + '/index.html', 'utf8')) }));
    const data = C.mk(base, {}); const T = data.tables;
    T.coa_accounts = JSON.parse(JSON.stringify(COA)); T.acct_mappings = JSON.parse(JSON.stringify(MAPS)); T.suppliers = [{ id: 'sp1', name: 'Dudh Ghor' }, { id: 'sp2', name: 'Sugar Co' }]; T.customers = [{ id: 'c1', mobile: '01711111111', name: 'Rahim' }];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__ACC=${JSON.stringify(acc(o))};try{localStorage.setItem('bos_lang','en')}catch(e){}window.print=()=>{window.__PRINTED=(document.getElementById('ac_print')||{}).innerText||'none'};`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__ACALLS || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const tab = async (p, v) => { await p.selectOption('#ac_tab', v); await wait(p, 400); };

  // ---- overview ----
  let p = await open('#/accounts');
  let t = await text(p);
  ok(/Accounts & ledger/.test(t), 'page title'); ok(/Total assets/.test(t) && /10,180\.00/.test(t), 'total assets shown'); ok(/Balanced/.test(t), 'balanced text');
  ok(/Customer|Supplier payables/.test(t) && /Cash in hand/.test(t), 'balance sheet rows shown');
  let c = await calls(p, 'acct_post_pending'); ok(c.length >= 1 && c[0].p_dry === false, 'auto-post on open (switch on)');
  ok(/Posted: 3 \+ 1/.test(t) || (await p.locator('#toast').textContent()).includes('Posted'), 'auto-post tells how many were posted');
  await noOverflow(p, 'overview');
  // Post now: dry run first, then confirm
  const before = (await calls(p, 'acct_post_pending')).length;
  await p.click('[data-act=ac_post]'); await wait(p, 500);
  c = await calls(p, 'acct_post_pending'); ok(c.length === before + 1 && c[c.length - 1].p_dry === true, 'Post now asks for a dry run first');
  t = await text(p); ok(/Check before posting/.test(t) && /New entries: 3/.test(t.replace(/\s+/g, ' ')) && /Cost unknown|cost_missing/.test(t), 'dry-run sheet shows counts and the waiting reason');
  ok(/Net effect/.test(t) && /1,500\.00/.test(t), 'trial calculation shown');
  await noOverflow(p, 'post sheet');
  await p.click('[data-act=ac_postgo]'); await wait(p, 500);
  c = await calls(p, 'acct_post_pending'); ok(c.length === before + 2 && c[c.length - 1].p_dry === false, 'confirm sends the real post');
  // print + csv
  await p.click('[data-act=ac_print]'); await wait(p, 300);
  ok(/Total assets|Cash in hand/.test(await p.evaluate(() => window.__PRINTED || '')), 'print builds the printable copy');
  const [dl] = await Promise.all([p.waitForEvent('download', { timeout: 4000 }), p.click('[data-act=ac_csv]')]);
  ok(/accounts-overview/.test(dl.suggestedFilename()), 'CSV file name'); const body = fs.readFileSync(await dl.path(), 'utf8'); ok(/"1110","Cash in hand","10180"/.test(body), 'CSV has the account rows');
  await p.screenshot({ path: SP + '/ac_overview.png', fullPage: true });

  // ---- unbalanced + cogs warnings ----
  p = await open('#/accounts', { status: { autopost: false }, unbal: true, cm: 2 });
  t = await text(p);
  ok(/does not balance/.test(t) && /25\.00/.test(t), 'unbalanced warning with the difference'); ok(/2 sale\(s\)\/movement\(s\) have no known cost/.test(t), 'cogs missing note');
  ok((await calls(p, 'acct_post_pending')).length === 0, 'no auto post when the switch is off');

  // ---- phase 72: status strip, failed-posting banner (autopost no longer swallows errors), provisional profit ----
  p = await open('#/accounts', { status: { pending: 2, errors: 1, locked: 1, last_post_at: '2026-10-13T08:00:00Z', error_list: [{ source_type: 'sale', source_id: 'abcdef1234', error: 'unbalanced', tries: 2 }] }, realErr: [{ source_type: 'sale', source_id: 'abcdef1234', error: 'unbalanced' }], unk: 427 });
  t = (await text(p)).replace(/\s+/g, ' ');
  ok(/Last post: 13\/10\/2026/.test(t) && /Pending 2/.test(t) && /Errors 1/.test(t) && /Held by a closed period 1/.test(t), 'status strip: last post, pending, errors, held');
  ok(/1 entries were not posted/.test(t) && /unbalanced/.test(t), 'failed-posting banner with the reason');
  ok(/Provisional: sales with no known cost: ৳ 427\.00/.test(t) && /estimate from the typed cost: ৳ 200\.00/.test(t), 'overview shows the provisional unknown-cost figure');
  await noOverflow(p, 'strip');
  c = await calls(p, 'acct_post_pending'); const b4 = c.length; await p.click('#ac_failbanner [data-act=ac_post]'); await wait(p, 400);
  c = await calls(p, 'acct_post_pending'); ok(c.length === b4 + 1 && c[c.length - 1].p_dry === true, 'the banner link opens the Post now panel (dry run first)');
  p = await open('#/accounts', { status: { autopost: false, pending: 0, errors: 0, last_post_at: null }, unk: 100 });
  t = (await text(p)).replace(/\s+/g, ' '); ok(/Last post: not yet/.test(t) && /Pending 0/.test(t) && /Errors 0/.test(t) && !(await p.locator('#ac_failbanner').count()), 'quiet strip when nothing failed');
  await tab(p, 'pl'); t = (await text(p)).replace(/\s+/g, ' '); ok(/Gross profit \(income − cost of goods\) \(provisional\)/.test(t) && /Provisional: sales with no known cost: ৳ 100\.00/.test(t), 'P&L marks the gross profit provisional');

  // ---- tabs ----
  await tab(p, 'bs'); t = await text(p); ok(/Total liabilities/.test(t) && /Earnings to date/.test(t), 'balance sheet tab'); await noOverflow(p, 'bs');
  await p.fill('#ac_asof', '2026-10-10'); await p.dispatchEvent('#ac_asof', 'change'); await wait(p, 300);
  c = await calls(p, 'acct_balance_sheet'); ok(c[c.length - 1].p_as_of === '2026-10-10', 'as-of date sent');
  await tab(p, 'pl'); t = await text(p); ok(/Net profit/.test(t) && /Gross profit/.test(t) && /650\.00/.test(t), 'P&L tab'); await noOverflow(p, 'pl');
  await tab(p, 'cf'); t = await text(p); ok(/Closing/.test(t) && /bank_deposit|Cash move/.test(t), 'cash flow tab'); await noOverflow(p, 'cf');
  await tab(p, 'tb'); t = await text(p); ok(/Balanced/.test(t) && /6,230\.00/.test(t), 'trial balance tab'); await noOverflow(p, 'tb');
  await p.selectOption('#ac_loc', '1'); await wait(p, 300); c = await calls(p, 'acct_trial_balance'); ok(c[c.length - 1].p_loc === 1, 'place filter sent');
  await tab(p, 'ledger'); ok(/Choose an account/.test(await text(p)), 'ledger asks for an account');
  await p.selectOption('#ac_acc', '2'); await wait(p, 400); t = await text(p);
  ok(/Receipt 1/.test(t) && /1,500\.00/.test(t) && /Opening/.test(t) && /Closing/.test(t), 'ledger shows running balance'); ok(await p.locator('a.ac-src[href="#/cashmoves"]').count() === 1, 'source link to the cash moves page');
  await noOverflow(p, 'ledger');
  await tab(p, 'journal'); t = await text(p); ok(/Rent for October/.test(t) && /cogs_missing/.test(t), 'journal book entries'); ok(await p.locator('[data-act=ac_rev]').count() === 1, 'only the manual entry offers a reversal');
  await p.click('[data-act=ac_rev]'); await wait(p, 400); c = await calls(p, 'acct_journal_reverse'); ok(c.length === 1 && c[0].p_id === 9 && /wrong month/.test(c[0].p_note) && c[0].p_client, 'reversal sends the reason and a client id');
  await noOverflow(p, 'journal');
  await tab(p, 'parties'); await p.fill('#ac_pmob', '01711111111'); await p.click('[data-act=ac_pshow]'); await wait(p, 400);
  c = await calls(p, 'acct_party_ledger'); ok(c.length >= 1 && c[c.length - 1].p_type === 'customer' && c[c.length - 1].p_id === 'c1', 'customer found by mobile'); ok(/Due collection/.test(await text(p)), 'party rows shown');
  await p.click('[data-act=ac_reco]'); await wait(p, 400); t = await text(p); ok(/Sugar Co/.test(t) && /700\.00/.test(t), 'reconciliation shows the supplier difference'); ok(/Everything agrees/.test(t), 'customers agree text'); await noOverflow(p, 'parties');
  // phase 72: stock vs books section in the reconcile tab (read only)
  c = await calls(p, 'inventory_vs_gl'); ok(c.length === 1 && c[0].p_loc === 1 && /^\d{4}-\d{2}-\d{2}$/.test(c[0].p_date), 'stock-vs-books asked with the as-of date and the chosen place (1)');
  t = await text(p).then((x) => x.replace(/\s+/g, ' ')); ok(/Reconcile: stock vs books/.test(t) && /Raw materials/.test(t) && /3,040\.00/.test(t) && /2,940\.00/.test(t) && /Stock-count adjustment/.test(t) && /-250\.00/.test(t) && /mystery_new_code/.test(t), 'stock-vs-books table with reasons (unknown code falls back to the code)');
  ok(/Nothing is posted here/.test(t), 'stock-vs-books says it posts nothing');

  // ---- manual journal ----
  await tab(p, 'new');
  await p.selectOption('#ac_l0_a', '8'); await p.fill('#ac_l0_d', '3000'); await p.dispatchEvent('#ac_l0_d', 'input');
  await p.selectOption('#ac_l1_a', '2'); await p.fill('#ac_l1_c', '2900'); await p.dispatchEvent('#ac_l1_c', 'input');
  await p.fill('#ac_jmemo', 'Rent');
  ok(/Difference 100\.00/.test(await p.textContent('#ac_tot')), 'live difference shown');
  await p.click('[data-act=ac_jsave]'); await wait(p, 400);
  ok((await calls(p, 'acct_journal_post')).length === 0, 'unbalanced entry is stopped on the phone before the server');
  ok(/Debit and credit are not equal/.test(await p.locator('#toast').textContent()), 'friendly unbalanced text');
  await p.fill('#ac_l1_c', '3000'); await p.dispatchEvent('#ac_l1_c', 'input');
  await p.click('[data-act=ac_jdry]'); await wait(p, 400);
  c = await calls(p, 'acct_journal_post'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_lines.length === 2 && c[0].p_lines[0].account_id === 8 && c[0].p_lines[0].debit === 3000, 'dry check sent with the lines');
  ok(/nothing was written/.test(await p.textContent('#ac_jout')), 'dry text');
  await p.click('[data-act=ac_addline]'); ok(await p.locator('.ac-line').count() === 3, 'add a line');
  await noOverflow(p, 'new journal');
  await p.click('[data-act=ac_jsave]'); await wait(p, 600);
  c = await calls(p, 'acct_journal_post'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_client && c[1].p_memo === 'Rent', 'real save sent with a client id');
  // server error shown friendly
  await p.evaluate(() => { window.__ACC.fail.acct_journal_post = 'period_closed'; });
  await tab(p, 'new'); await p.selectOption('#ac_l0_a', '8'); await p.fill('#ac_l0_d', '10'); await p.dispatchEvent('#ac_l0_d', 'input'); await p.selectOption('#ac_l1_a', '2'); await p.fill('#ac_l1_c', '10'); await p.dispatchEvent('#ac_l1_c', 'input'); await p.fill('#ac_jmemo', 'closed try');
  await p.click('[data-act=ac_jsave]'); await wait(p, 400); ok(/This period is closed/.test(await p.locator('#toast').textContent()), 'period closed text');

  // ---- opening ----
  await tab(p, 'opening'); ok(/Opening balances: enter what each account held/.test(await text(p)), 'opening wizard text');
  await p.fill('#ac_o2', '1000'); await p.dispatchEvent('#ac_o2', 'input'); await p.fill('#ac_o6', '600'); await p.dispatchEvent('#ac_o6', 'input');
  ok(/Difference 400\.00/.test(await p.textContent('#ac_optot')), 'opening totals shown');
  await p.click('[data-act=ac_opdry]'); await wait(p, 400); c = await calls(p, 'acct_opening');
  ok(c.length === 1 && c[0].p_dry === true && c[0].p_plug === true && c[0].p_lines.length === 2, 'opening dry sent with the balancing switch'); ok(/Difference 400\.00/.test(await p.textContent('#ac_opout')), 'plug shown');
  await p.click('details summary'); await p.fill('#ac_obj', '{"cash":[{"mode":"cash","amount":100}],"capital":[{"kind":"owner","amount":60}]}'); await p.click('[data-act=ac_obdry]'); await wait(p, 300);
  c = await calls(p, 'opening_balance_post'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_plug === false && /Difference 40\.00/.test(await p.textContent('#ac_obout')), 'full opening preview shows the difference');
  await p.click('[data-act=ac_obsave]'); await wait(p, 400); c = await calls(p, 'opening_balance_post'); ok(c.length === 2 && c[1].p_dry === false && !!c[1].p_client, 'full opening unbalanced is sent to the server (which refuses)'); ok(/unbalanced|debit/i.test(await p.locator('#toast').textContent()), 'refusal is shown');
  await p.evaluate(() => { document.querySelector('#ac_obj').closest('details').open = true; }); await p.fill('#ac_obj', 'not json'); await p.click('[data-act=ac_obsave]'); await wait(p, 200); c = await calls(p, 'opening_balance_post'); ok(c.length === 2, 'invalid JSON is not sent');
  await p.click('[data-act=ac_opsave]'); await wait(p, 500); c = await calls(p, 'acct_opening'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_client, 'opening saved');
  ok(/already entered/.test(await text(p)), 'opening done text');
  await noOverflow(p, 'opening');

  // ---- chart ----
  await tab(p, 'chart'); t = await text(p); ok(/1110 · Cash in hand/.test(t) && /Chart of accounts/.test(t), 'chart listed'); await noOverflow(p, 'chart');
  await p.click('[data-act=ac_add]'); await wait(p, 200);
  await p.fill('#ac_nc', '1110'); await p.fill('#ac_nbn', 'নগদ'); await p.fill('#ac_nen', 'Cash'); await p.click('[data-act=ac_addgo]'); await wait(p, 400);
  ok(/already used/.test(await p.locator('#toast').textContent()), 'code taken text'); c = await calls(p, 'acct_account_save'); ok(c.length === 1 && c[0].p_code === '1110' && c[0].p_id === null, 'add sent');
  await p.fill('#ac_nc', '1115'); await p.click('[data-act=ac_addgo]'); await wait(p, 400); c = await calls(p, 'acct_account_save'); ok(c.length === 2 && c[1].p_code === '1115', 'a new code is saved');
  await p.click('[data-act=ac_edit] >> nth=0'); await wait(p, 200); await p.click('[data-act=ac_retire]'); await wait(p, 400);
  c = await calls(p, 'acct_account_save'); ok(c.length === 3 && c[2].p_active === false && c[2].p_id === 2, 'retire sends active=false (never delete)');

  // ---- settings ----
  await tab(p, 'settings'); t = await text(p); ok(/Which account each kind of transaction goes to/.test(t), 'mapping section');
  await p.selectOption('#ac_m_pay_cash', '3'); await wait(p, 300); c = await calls(p, 'acct_mapping_set'); ok(c.length === 1 && c[0].p_key === 'pay_cash' && c[0].p_account === 3, 'mapping change sent');
  await p.click('[data-act=ac_sw][data-v=accounting_autopost]'); await wait(p, 400); c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'accounting_autopost' && c[0].p_value === true, 'autopost switch sends set_rule');
  await noOverflow(p, 'settings');

  // ---- data needed ----
  p = await open('#/accounts', { status: { start: null, on: false } });
  t = await text(p); ok(/Data needed/.test(t), 'Data needed while the start date is empty'); ok(await p.locator('#ac_start').count() === 1, 'owner can set the start date here');
  await p.fill('#ac_start', '2026-11-01'); await p.click('[data-act=ac_setstart]'); await wait(p, 600);
  c = await calls(p, 'acct_set_start'); ok(c.length === 1 && c[0].p_date === '2026-11-01', 'start date sent'); ok(!/Data needed/.test(await text(p)), 'page opens after the start date');
  await tab(p, 'tb'); ok(true, 'tabs still work');
  // a non-manager sees read-only
  p = await open('#/accounts', { status: { can_manage: false, owner: false } });
  ok(await p.locator('[data-act=ac_post]').count() === 0, 'no Post now without the manage grant'); await tab(p, 'new'); ok(/No permission/.test(await text(p)), 'manual journal needs manage');
  await tab(p, 'settings'); ok(await p.locator('[data-act=ac_sw]').count() === 0, 'switches are owner only');
  // no permission at all
  p = await open('#/accounts', { fail: { acct_status: 'not allowed' } });
  ok(/No permission for this page/.test(await text(p)), 'friendly no-permission text');
  // Bangla default
  { const ctx = await br.newContext({ viewport: { width: 360, height: 780 } }); const q = await ctx.newPage(); q.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    await q.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await q.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await q.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: ((h) => (/accounts\.js/.test(h) ? h : h.replace('<script src="cashmoves.js"></script>', '<script src="cashmoves.js"></script><script src="accounts.js"></script>')))(fs.readFileSync(WEB + '/index.html', 'utf8')) }));
    const data = C.mk(base, {}); data.tables.coa_accounts = COA; data.tables.acct_mappings = MAPS;
    await q.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__ACC=${JSON.stringify(acc())};try{localStorage.setItem('bos_lang','bn')}catch(e){}`);
    await q.goto(`http://localhost:${PORT}/#/accounts`); await q.waitForTimeout(1500);
    ok(/হিসাব ও খতিয়ান/.test(await q.evaluate(() => document.body.innerText)) && /মোট সম্পদ/.test(await q.evaluate(() => document.body.innerText)), 'Bangla labels'); }

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
