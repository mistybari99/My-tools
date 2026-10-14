// Finance 2 web page #/finance2 (phase53): statement parser, bank reconcile (dry import, suggestions, match, unmatch), year-end close (preview, problems,
// confirm, reverse), VAT report (off / rate missing / numbers), fixed assets (dry, save, register, schedule, depreciation preview + confirm), budgets (dry, save,
// vs-actual), switches-off banners, no-permission text, Bangla, no horizontal overflow, no JS errors.
// Run: node finance2_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const ROW = (id, code, bn, en, type, parent, grp) => ({ id, code, name_bn: bn, name_en: en, type, parent_id: parent || null, is_group: !!grp, active: true });
const COA = [ROW(1, '1100', 'নগদ ও ব্যাংক', 'Cash and bank', 'asset', null, true), ROW(2, '1110', 'হাতে নগদ', 'Cash in hand', 'asset', 1), ROW(3, '1120', 'ব্যাংক', 'Bank', 'asset', 1), ROW(4, '4100', 'বিক্রয়', 'Sales', 'income'), ROW(5, '5300', 'ভাড়া', 'Rent', 'expense')];
const RULES = (o) => [['bank_recon_on', true], ['year_close_on', true], ['fixed_assets_on', true], ['budgets_on', true], ['vat_on', true], ['vat_rate', 15], ['period_closed_until', '2025-12-31']]
  .map(([key, v]) => ({ key, value: (o.rules && key in o.rules) ? o.rules[key] : v, default_value: null }));
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const F = window.__F2;
 c.rpc = async (fn, args) => {
  (window.__FCALLS = window.__FCALLS || []).push([fn, JSON.parse(JSON.stringify(args || {}))]);
  const KNOWN = /^(bank_|year_close|vat_report|fa_|budget_)/;
  if (!KNOWN.test(fn)) return rpc(fn, args);
  const err = (m) => ({ data: null, error: { message: m, code: 'P0001' } });
  if (F.fail && F.fail[fn]) { const m = F.fail[fn]; if (!F.keep) delete F.fail[fn]; return err(m); }
  const ok = (d) => ({ data: d, error: null });
  if (fn === 'bank_stmt_import') return ok(args.p_dry ? { dry: true, rows: args.p_rows.length, new: args.p_rows.length - F.dups, duplicate: F.dups, invalid: 0, sum_in: 7000, sum_out: -1500 } : { batch_id: args.p_client, rows: args.p_rows.length, imported: args.p_rows.length, duplicate: 0 });
  if (fn === 'bank_recon_report') return ok(F.rep);
  if (fn === 'bank_recon_lines') return ok(F.matched);
  if (fn === 'bank_recon_suggest') return ok(F.sugg);
  if (fn === 'bank_recon_candidates') return ok(F.cands);
  if (fn === 'bank_recon_match_many') return ok({ dry: args.p_dry, ok: args.p_pairs.length, failed: 0, failures: [] });
  if (fn === 'bank_recon_match') { F.rep.statement_unmatched = F.rep.statement_unmatched.filter((x) => x.id !== args.p_line); return ok({ match_id: 1 }); }
  if (fn === 'bank_recon_unmatch') return ok({ unmatched: args.p_line });
  if (fn === 'year_close_list') return ok(F.yl);
  if (fn === 'year_close_run') { if (args.p_dry) return ok(F.prev); F.yl.rows.unshift({ id: 9, fiscal_from: args.p_from, fiscal_to: args.p_to, net_profit: F.prev.net_profit, status: 'closed' }); return ok({ id: 9, entry_id: 70 }); }
  if (fn === 'year_close_reverse') { F.yl.rows[0].status = 'reopened'; return ok({ id: args.p_id, reversal_id: 71 }); }
  if (fn === 'vat_report') return ok(F.vat);
  if (fn === 'fa_register') return ok(F.reg);
  if (fn === 'fa_asset_save') { if (args.p_dry) return ok({ dry: true, monthly: 1000, last_month: 1000, depr_from: args.p_depr_from, depr_to: '2027-06-01', depreciable: 10000 }); F.reg.rows.push({ id: 'a2', code: args.p_code, name: args.p_name, cost: args.p_cost, accumulated: 0, book_value: args.p_cost, life_months: args.p_life_months, depr_from: args.p_depr_from, status: 'active' }); return ok({ id: 'a2', monthly: 1000 }); }
  if (fn === 'fa_schedule') return ok({ code: 'FA-1', name: 'Oven', rows: [{ k: 1, month: '2026-07-01', amount: 1000, accumulated: 1000, book_value: 11000, posted: true }, { k: 2, month: '2026-08-01', amount: 1000, accumulated: 2000, book_value: 10000, posted: false }] });
  if (fn === 'fa_depr_post') return ok(args.p_dry ? F.dpost : Object.assign({}, F.dpost, { dry: false }));
  if (fn === 'fa_asset_dispose') return ok({ id: args.p_id });
  if (fn === 'budget_set') return ok({ dry: args.p_dry, new: args.p_rows.length, changed: 0, unchanged: 0 });
  if (fn === 'budget_vs_actual') return ok(F.bva);
  return ok(null); };
 return c; }; })();`;
const f2 = (o = {}) => ({ fail: o.fail || {}, dups: o.dups || 0,
  rep: { matched_count: 2, statement_unmatched_count: 1, book_unmatched_count: 1, statement_total: 7000, book_total: 8000, difference: -1000, statement_unmatched: [{ id: 11, date: '2026-10-11', amount: 999, reference: 'unknown', description: 'x' }], book_unmatched: [{ entry_id: 5, line_no: 1, date: '2026-10-10', memo: 'Cheque received', source_type: 'manual', amount: 2000 }] },
  matched: [{ id: 12, date: '2026-10-09', amount: 5000, reference: 'INV-77', description: 'deposit', matched: true, entry_id: 3, line_no: 1, how: 'manual' }],
  sugg: { count: 2, suggestions: [{ line_id: 21, line_date: '2026-10-08', amount: 3000, reference: 'A1', entry_id: 6, line_no: 1, entry_date: '2026-10-08', memo: 'Deposit', days_off: 0, ref_hit: true, candidates: 1, confident: true }, { line_id: 22, line_date: '2026-10-08', amount: 2000, reference: 'CHQ', entry_id: 7, line_no: 1, entry_date: '2026-10-07', memo: 'Cheque', days_off: -1, ref_hit: false, candidates: 2, confident: false }] },
  cands: [{ entry_id: 5, line_no: 1, date: '2026-10-10', memo: 'Cheque received', source_type: 'manual', source_id: 'x', amount: 999, days_off: 1, ref_hit: false }],
  yl: { on: true, period_closed_until: o.lock === undefined ? '2025-12-31' : o.lock, owner: o.owner !== false, rows: [] },
  prev: { from: '2025-01-01', to: '2025-12-31', income_total: 13000, expense_total: 4000, net_profit: 9000, accounts: 3, ok: !o.problem, problems: o.problem ? ['period_not_locked'] : [], period_closed_until: null, dry: true,
    lines: [{ account_id: 4, debit: 13000, credit: 0, location_id: 1, code: '4100', name: 'Sales' }, { account_id: 5, debit: 0, credit: 4000, location_id: 1, code: '5300', name: 'Rent' }, { account_id: 9, debit: 0, credit: 9000, location_id: 1, code: 'RE', name: 'Retained earnings' }] },
  vat: o.vat || { rate: 15, prices_include_vat: true, from: '2026-10-01', to: '2026-10-13', output: { taxable_sales: 500, vat: 65.22, undecided_amount: 500, documents: 1 }, input: { taxable_purchases: 1000, vat: 130.43, undecided_amount: 0, documents: 1 }, net_vat_payable: -65.21, months: [{ month: '2026-10-01', output_vat: 65.22, input_vat: 130.43 }] },
  reg: { on: true, as_of: '2026-10-13', rows: [{ id: 'a1', code: 'FA-1', name: 'Oven', category: null, cost: 12000, salvage: 2000, life_months: 10, depr_from: '2026-07-01', status: 'active', accumulated: 3000, book_value: 9000, months_posted: 3 }] },
  dpost: { dry: true, through: '2026-09-01', count: 2, total: 2000, rows: [{ code: 'FA-1', month: '2026-08-01', k: 2, amount: 1000 }, { code: 'FA-1', month: '2026-09-01', k: 3, amount: 1000 }], skipped: [{ code: 'FA-9', month: '2026-08-01', why: 'period_closed' }] },
  bva: { on: true, from: '2026-10-01', to: '2026-10-31', by_month: false, rows: [{ account_id: 5, code: '5300', name_en: 'Rent', name_bn: 'ভাড়া', type: 'expense', month: null, budget: 8000, actual: 6000, variance: 2000, pct_used: 75.0 }, { account_id: 4, code: '4100', name_en: 'Sales', name_bn: 'বিক্রয়', type: 'income', month: null, budget: 20000, actual: 14000, variance: -6000, pct_used: 70.0 }],
    income_budget: 20000, income_actual: 14000, expense_budget: 8000, expense_actual: 6000, profit_budget: 12000, profit_actual: 8000 } });
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', async (d) => { if (d.type() === 'prompt') await d.accept(o.reason || 'checked with the accountant'); else await d.accept(); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: ((h) => (/finance2\.js/.test(h) ? h : h.replace('<script src="accounts.js"></script>', '<script src="accounts.js"></script><script src="finance2.js"></script>')))(fs.readFileSync(WEB + '/index.html', 'utf8')) }));
    const data = C.mk(base, {}); const T = data.tables; T.coa_accounts = JSON.parse(JSON.stringify(COA)); T.rules = RULES(o);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__F2=${JSON.stringify(f2(o))};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__FCALLS || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const tab = async (p, v) => { await p.selectOption('#f2_tab', v); await wait(p, 500); };

  // ---- parser (pure) ----
  let p = await open('#/finance2');
  const P = await p.evaluate(() => {
    const f = window.BOS.f2; const a = f.parseStatement('Date,Description,Debit,Credit,Balance\n2026-10-01,"Salary, Oct",1500,,8500\n01/10/2026,Deposit INV-1,,"5,000.00",\n2026-13-45,bad,1,,\n');
    const b = f.parseStatement('[{"date":"2026-10-02","amount":"-250.5","reference":"R1"},{"date":"2026-10-03","amount":0}]');
    const c = f.parseStatement('2026-10-05;Cash dep;1200\n2026-10-06;Fee;(30)');
    const d = f.parseStatement('Date\tNarration\tAmount\n05-10-2026\tPOS\t৳১,২০০');
    return { a, b, c, d, amt: [f.parseAmt('1,250.50'), f.parseAmt('(40)'), f.parseAmt('12.5 Dr'), f.parseAmt('abc'), f.parseAmt('')], dt: [f.parseDate('31/12/2025'), f.parseDate('2026-02-30'), f.parseDate('x')] };
  });
  ok(P.a.rows.length === 2 && P.a.rows[1].amount === 5000 && P.a.rows[1].date === '2026-10-01' && P.a.rows[0].amount === -1500 && P.a.rows[0].description === 'Salary, Oct' && P.a.rows[0].balance === 8500, 'csv with header: debit = money out, quoted comma kept');
  ok(P.a.errors.length >= 1, 'bad date / unreadable amount rows are reported, not dropped silently');
  ok(P.b.rows.length === 1 && P.b.rows[0].amount === -250.5 && P.b.rows[0].reference === 'R1' && P.b.errors.length === 1, 'JSON rows, zero amount refused');
  ok(P.c.rows.length === 2 && P.c.rows[1].amount === -30 && P.c.rows[0].date === '2026-10-05', 'semicolon CSV without header: date, description, amount; (30) is negative');
  ok(P.d.rows.length === 1 && P.d.rows[0].amount === 1200 && P.d.rows[0].date === '2026-10-05', 'tab-separated, DD-MM-YYYY, Bangla digits and currency sign');
  ok(P.amt[0] === 1250.5 && P.amt[1] === -40 && P.amt[2] === -12.5 && Number.isNaN(P.amt[3]) && P.amt[4] === null, 'amount parser');
  ok(P.dt[0] === '2025-12-31' && P.dt[1] === null && P.dt[2] === null, 'date parser rejects impossible dates');

  // ---- bank tab ----
  let t = await text(p);
  ok(/Finance 2/.test(t) && /Bank reconcile/.test(t), 'page title and default tab');
  ok(/Nothing is posted by itself/.test(t), 'bank tab says nothing is auto posted'); ok(/Matched: 2/.test(t) && /Difference/.test(t), 'summary shown');
  ok(/999\.00/.test(t) && /Cheque received/.test(t) && /INV-77/.test(t), 'unmatched statement, unmatched book and matched lists');
  await noOverflow(p, 'bank');
  await p.fill('#f2_btext', 'Date,Description,Amount,Reference\n2026-10-08,Deposit,3000,A1\n2026-10-08,Cheque,2000,CHQ\n2026-10-09,Fee,-30,\nbroken line');
  await p.click('[data-act=f2_bcheck]'); await wait(p, 500);
  let c = await calls(p, 'bank_stmt_import'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_rows.length === 3 && c[0].p_rows[0].reference === 'A1' && c[0].p_client === null, 'check sends a dry run with the parsed rows');
  t = await text(p); ok(/New: 3/.test(t) && /Bad rows/.test(t), 'dry result shown, bad row reported'); ok(await p.locator('[data-act=f2_bimport]').count() === 1, 'import button appears after the check');
  await p.click('[data-act=f2_bimport]'); await wait(p, 500);
  c = await calls(p, 'bank_stmt_import'); ok(c.length === 2 && c[1].p_dry === false && /^[0-9a-f-]{36}$/.test(c[1].p_client), 'confirm sends the real import with a client id');
  await p.click('[data-act=f2_bsugg]'); await wait(p, 500); t = await text(p);
  ok(/Confident/.test(t) && /Several candidates/.test(t), 'suggestions show confident and ambiguous ones');
  ok(await p.locator('[data-f2-sg="0"]:checked').count() === 1 && await p.locator('[data-f2-sg="1"]:checked').count() === 0, 'only confident suggestions are ticked by default');
  await p.click('[data-act=f2_baccept]'); await wait(p, 500); c = await calls(p, 'bank_recon_match_many');
  ok(c.length === 2 && c[0].p_dry === true && c[1].p_dry === false && c[1].p_pairs.length === 1 && c[1].p_pairs[0].line_id === 21 && c[1].p_pairs[0].entry_id === 6, 'accept checks (dry) then matches only the ticked pair');
  await p.click('[data-act=f2_bfind]'); await wait(p, 500); t = await text(p); ok(/Possible book lines/.test(t) && /Cheque received/.test(t), 'candidate sheet'); await noOverflow(p, 'candidate sheet');
  await p.click('[data-act=f2_bmatch]'); await wait(p, 500); c = await calls(p, 'bank_recon_match'); ok(c.length === 1 && c[0].p_line === 11 && c[0].p_entry === 5 && c[0].p_line_no === 1, 'manual match sends line + journal line');
  await p.click('[data-act=f2_bunm]'); await wait(p, 500); c = await calls(p, 'bank_recon_unmatch'); ok(c.length === 1 && c[0].p_line === 12 && /accountant/.test(c[0].p_note), 'unmatch asks for a reason');
  await p.screenshot({ path: SP + '/f2_bank.png', fullPage: true });

  // ---- close ----
  await tab(p, 'close'); t = await text(p);
  ok(/Year-end close/.test(t) && /Books closed until/.test(t) && /2025-12-31/.test(t), 'close tab with the lock date'); ok(await p.locator('[data-act=f2_crun]').count() === 0, 'no close button before the preview');
  await p.click('[data-act=f2_cprev]'); await wait(p, 500); c = await calls(p, 'year_close_run'); ok(c.length === 1 && c[0].p_dry === true, 'preview is a dry run');
  t = await text(p); ok(/13,000\.00/.test(t) && /4,000\.00/.test(t) && /9,000\.00/.test(t) && /retained earnings/.test(t), 'preview numbers');
  await noOverflow(p, 'close');
  await p.click('[data-act=f2_crun]'); await wait(p, 500); c = await calls(p, 'year_close_run'); ok(c.length === 2 && c[1].p_dry === false && /accountant/.test(c[1].p_note) && c[1].p_client, 'close confirms with a note and client id');
  t = await text(p); ok(/Closed/.test(t) && await p.locator('[data-act=f2_crev]').count() === 1, 'closed row with a reverse button');
  await p.click('[data-act=f2_crev]'); await wait(p, 500); c = await calls(p, 'year_close_reverse'); ok(c.length === 1 && c[0].p_id === 9 && /accountant/.test(c[0].p_note), 'reverse asks for a reason'); ok(/Reopened/.test(await text(p)), 'status becomes reopened');
  await p.close();
  p = await open('#/finance2', { problem: true }); await tab(p, 'close'); await p.click('[data-act=f2_cprev]'); await wait(p, 500); t = await text(p);
  ok(/Set the books-closed date/.test(t) && await p.locator('[data-act=f2_crun]').count() === 0, 'not locked: friendly problem and no close button');
  await p.close();
  p = await open('#/finance2', { owner: false }); await tab(p, 'close'); await p.click('[data-act=f2_cprev]'); await wait(p, 500); ok(/Only the owner/.test(await text(p)) && await p.locator('[data-act=f2_crun]').count() === 0, 'non-owner manager cannot close');
  await p.close();

  // ---- vat ----
  p = await open('#/finance2'); await tab(p, 'vat'); t = await text(p);
  ok(/Output VAT/.test(t) && /65\.22/.test(t) && /130\.43/.test(t) && /-65\.21/.test(t) && /15%/.test(t), 'VAT numbers'); ok(/Report only/.test(t) && /undecided/i.test(t), 'report-only note and undecided amount');
  await noOverflow(p, 'vat'); c = await calls(p, 'vat_report'); ok(c.length >= 1 && c[0].p_from && c[0].p_to, 'range sent');
  await p.close();
  p = await open('#/finance2', { vat: { off: true } }); await tab(p, 'vat'); ok(/VAT is OFF/.test(await text(p)), 'VAT off message'); await p.close();
  p = await open('#/finance2', { vat: { data_needed: true, need: 'vat_rate' } }); await tab(p, 'vat'); ok(/No VAT rate is set/.test(await text(p)) && /never assumes/.test(await text(p)), 'no rate: the app says it never assumes one'); await p.close();

  // ---- fixed assets ----
  p = await open('#/finance2'); await tab(p, 'fa'); t = await text(p);
  ok(/Asset register/.test(t) && /FA-1/.test(t) && /9,000\.00/.test(t) && /straight line/.test(t), 'register and method shown');
  await p.fill('#f2_fcode', 'FA-2'); await p.fill('#f2_fname', 'Mixer'); await p.fill('#f2_fcost', '12,000'); await p.fill('#f2_fsalv', '2000'); await p.fill('#f2_flife', '10');
  await p.click('[data-act=f2_fdry]'); await wait(p, 500); c = await calls(p, 'fa_asset_save'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_cost === 12000 && c[0].p_salvage === 2000 && c[0].p_life_months === 10 && /-01$/.test(c[0].p_depr_from), 'asset dry run sends cleaned numbers and a first-of-month start');
  ok(/Monthly: 1,000\.00/.test(await text(p)), 'monthly amount previewed');
  await p.click('[data-act=f2_fsave]'); await wait(p, 500); c = await calls(p, 'fa_asset_save'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_client, 'save after the preview'); ok(/FA-2/.test(await text(p)), 'new asset in the register');
  await p.click('[data-act=f2_fsched]'); await wait(p, 500); ok(/Oven/.test(await text(p)) && /11,000\.00/.test(await text(p)), 'schedule sheet'); await noOverflow(p, 'schedule'); await p.click('.sheet .close, .sheet button[data-act=close], #sheet [data-act=closesheet]').catch(() => {}); await p.evaluate(() => window.BOS_APP.closeSheet());
  await p.click('[data-act=f2_fpdry]'); await wait(p, 500); c = await calls(p, 'fa_depr_post'); ok(c.length === 1 && c[0].p_dry === true, 'depreciation preview first');
  t = await text(p); ok(/Will post: 2/.test(t) && /2,000\.00/.test(t) && /Period closed/.test(t.replace(/-/g, ' ')) , 'preview rows and skipped reason');
  await p.click('[data-act=f2_fpgo]'); await wait(p, 500); c = await calls(p, 'fa_depr_post'); ok(c.length === 2 && c[1].p_dry === false, 'confirm posts');
  await p.click('[data-act=f2_fdisp]'); await wait(p, 500); c = await calls(p, 'fa_asset_dispose'); ok(c.length === 1 && c[0].p_id === 'a1' && /accountant/.test(c[0].p_note), 'dispose asks for a reason');
  await noOverflow(p, 'fa'); await p.close();

  // ---- budgets ----
  p = await open('#/finance2'); await tab(p, 'budget'); t = await text(p);
  ok(/Budget vs actual/.test(t) && /8,000\.00/.test(t) && /6,000\.00/.test(t) && /75/.test(t), 'vs-actual table'); ok(await p.locator('.f2-bad').count() >= 1 && await p.locator('.f2-good').count() >= 1, 'good / bad variance colours');
  await p.fill('#f2_uamt', '5000'); await p.fill('#f2_un', '3'); await p.click('[data-act=f2_udry]'); await wait(p, 500);
  c = await calls(p, 'budget_set'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_rows.length === 3 && c[0].p_rows[1].month.endsWith('-01') && c[0].p_rows[0].amount === 5000, 'three months of the same amount, dry first');
  ok(/New: 3/.test(await text(p)), 'dry result'); await p.click('[data-act=f2_usave]'); await wait(p, 500); c = await calls(p, 'budget_set'); ok(c.length === 2 && c[1].p_dry === false, 'save after the preview');
  await noOverflow(p, 'budget'); await p.screenshot({ path: SP + '/f2_budget.png', fullPage: true }); await p.close();

  // ---- switches off / errors / no permission / Bangla ----
  p = await open('#/finance2', { rules: { bank_recon_on: false } }); ok(/switched off/.test(await text(p)), 'bank switch OFF shows the banner'); await p.close();
  p = await open('#/finance2', { fail: { bank_recon_report: 'switch_off: bank_recon_on' } }); ok(/switched off/.test(await text(p)), 'a server switch_off error is friendly'); await p.close();
  p = await open('#/finance2', { lang: 'bn' }); t = await text(p); ok(/ব্যাংক মেলানো/.test(t) && /নিজে পোস্ট হয় না|auto post/.test(t), 'Bangla labels'); await noOverflow(p, 'bn'); await p.close();
  p = await open('#/home'); await p.evaluate(() => { window.BOS_APP.S.ctx.is_owner = false; window.BOS_APP.S.gcache = { uid: window.BOS_APP.S.ctx.profile.id, v: { accounts_manage: { ok: false, at: Date.now() } } }; location.hash = '#/finance2'; }); await wait(p, 900);
  ok(/for the owner or someone/.test(await text(p)), 'no permission text'); await p.close();

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
