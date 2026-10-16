// Web test for #/monthclose (web/monthclose.js): preview, blockers, post pending, close, reopen, settings (owner only), non-owner view, Bangla, 360px overflow.
// Run: node monthclose_test.js <abs tests/web dir>      (web/monthclose.js is injected into index.html here; the integrator adds the <script> tag for real)
// Test data only (test_* names, invented round numbers). Server side is proven by supabase/phase82_test.sql.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const ROOT = path.join(__dirname, '..', '..', 'web');   // the web folder of THIS checkout (the shared harness serves a fixed path)
const base = C.baseData(SP), PORT = 8382;
const srv = http.createServer((q, r) => {
  const u = q.url.split('?')[0]; const f = path.join(ROOT, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' }[ext] || 'application/octet-stream' }); r.end(b); });
}).listen(PORT);
const EXTRA82 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const S = window.__S82 = { state: 'open', can_close: true, blockers: [], warnings: ['accrual_hook_missing'], err: {} };
 c.rpc = async (fn, args) => {
  if (!/^(c_|set_rule$)/.test(fn)) return rpc(fn, args);
  (window.__AC82 = window.__AC82 || []).push([fn, clone(args || {})]);
  if (S.err[fn]) { const m = S.err[fn]; delete S.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  if (fn === 'c_month_close_preview') return { data: { month: args.p_month, to: args.p_month.slice(0, 8) + '28', state: S.state, blockers: S.blockers, warnings: S.warnings, can_close: S.can_close && S.state === 'open',
      payroll: { runs: [{ run_id: 7, location_id: 1, status: 'paid', shadow: false, basis: 'accrual', staff: 2, net: 23000, advance_recovery: 2000, salary_expense: 25000, paid: 23000, unpaid: 0, accrual_posted: true },
                        { run_id: 8, location_id: 2, status: 'approved', shadow: true, basis: 'form', staff: 1, net: 777, advance_recovery: 0, salary_expense: 777, paid: 0, unpaid: 777, accrual_posted: false }],
        salary_expense: 25000, net_pay: 23000, paid: 23000, unpaid: 0, salary_in_journal: 25000, pending_postings: 0, accrual_on: true, accrual_from: args.p_month, hooks_installed: false, pay_source: 'by_payment' },
      advances: { outstanding_all_staff: 3000 }, profit: { income: 500000, expense: 25000, net_profit: 475000, salary_in_journal: 25000, profit_before_salary: 500000, source: 'journal' } }, error: null };
  if (fn === 'c_month_closes') return { data: S.state === 'closed' ? [{ month: '2026-09-01', state: 'closed', net_profit: 475000 }] : [], error: null };
  if (fn === 'c_partner_month_split') return { data: { month: args.p_month, agreements: [{ agreement_id: 1, title: 'test deed', status: 'ok', base_profit: 475000, parties: [{ party_id: 1, name: 'test_partner_one', role: 'owner', share_percent: 60, amount: 285000 }, { party_id: 2, name: 'test_partner_two', role: 'partner', share_percent: 40, amount: 190000 }] }] }, error: null };
  if (fn === 'c_post_pending') return { data: { posted: 1, reversed: 0, errors: [], waiting: {} }, error: null };
  if (fn === 'c_month_close') { S.state = 'closed'; return { data: { state: 'closed' }, error: null }; }
  if (fn === 'c_month_reopen') { S.state = 'open'; return { data: { state: 'open' }, error: null }; }
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; return { data: null, error: null }; }
  return { data: {}, error: null };
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept('test note'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA82 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(/localhost:\d+\/(index\.html)?(\?.*)?$/, async (r) => { const resp = await r.fetch(); const body = ((h) => (/monthclose\.js/.test(h) ? h : h.replace('<script src="parallel.js"></script>', '<script src="parallel.js"></script><script src="monthclose.js"></script>')))(await resp.text()); r.fulfill({ response: resp, body }); });
    const data = C.mk(base, {}); const T = data.tables;
    T.rules = ['payroll_accrual_on', 'payroll_accrual_from', 'salary_pay_source', 'salary_in_daily_off', 'partner_settlement_post_on', 'partner_accrue_at'].map((k) => ({ key: k, value: null,
      default_value: k === 'salary_pay_source' ? 'by_payment' : k === 'partner_accrue_at' ? 'approval' : k === 'salary_in_daily_off' ? true : k === 'payroll_accrual_from' ? null : false }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC82 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // ---- owner: preview, runs, profit, split, settings
  let p = await open('#/monthclose'); let c = await calls(p, 'c_month_close_preview'); let t = await text(p);
  ok(c.length === 1 && /^\d{4}-\d{2}-01$/.test(c[0].p_month), 'preview asked for a month first-day');
  const prevM = (() => { const d = new Date(Date.now() + 6 * 3600e3); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() - 1); return d.toISOString().slice(0, 10); })();
  ok(c[0] && c[0].p_month === prevM, 'default month is last month');
  ok(/Monthly Close/.test(t) && /25,000/.test(t) && /23,000/.test(t) && /Monthly accrual/.test(t) && /The paper form is the record/.test(t), 'salary cost, net pay and run basis shown');
  ok(/Profit before salary/.test(t) && /4,75,000|475,000/.test(t), 'month profit shown');
  ok(/test_partner_one/.test(t) && /2,85,000|285,000/.test(t), 'partner split shown to the owner');
  ok(/Warnings/.test(t) && /link to the books is not installed|Accrual is on but the link/.test(t), 'warning text shown');
  ok(await p.evaluate(() => !document.querySelector('[data-act=mc_close]').disabled), 'close enabled when the server says can_close');
  ok((await calls(p, 'c_partner_month_split')).length === 1, 'owner loads the split');
  await noOverflow(p, 'owner view');
  await p.click('[data-act=mc_post]'); await wait(p); ok((await calls(p, 'c_post_pending')).length === 1, 'post pending calls the server');
  await p.click('[data-act=mc_close]'); await wait(p, 500);
  c = await calls(p, 'c_month_close'); ok(c.length === 1 && c[0].p_month === prevM && c[0].p_note === 'test note', 'close sends month and note');
  t = await text(p); ok(/Closed/.test(t) && !(await p.$('[data-act=mc_close]')), 'closed state shown, close button gone');
  await p.click('[data-act=mc_reopen]'); await wait(p, 500);
  c = await calls(p, 'c_month_reopen'); ok(c.length === 1 && c[0].p_reason === 'test note', 'reopen sends the reason'); t = await text(p); ok(/Open/.test(t) && await p.$('[data-act=mc_close]'), 'open again');

  // ---- settings are owner only and go through set_rule
  await p.click('[data-act=mc_tog][data-k=payroll_accrual_on]'); await wait(p, 400);
  c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'payroll_accrual_on' && c[0].p_value === true, 'accrual switch sends true');
  await p.selectOption('[data-mc-rule=salary_pay_source]', 'mobile'); await wait(p, 400);
  c = await calls(p, 'set_rule'); ok(c.length === 2 && c[1].p_key === 'salary_pay_source' && c[1].p_value === 'mobile', 'salary source sends mobile');
  ok(/bKash/.test(await text(p)), 'bKash option is named');
  await p.fill('#mc_from', '2026-09-01'); await p.press('#mc_from', 'Tab'); await wait(p, 400);
  c = await calls(p, 'set_rule'); ok(c.length === 3 && c[2].p_key === 'payroll_accrual_from' && c[2].p_value === '2026-09-01', 'first month sends the date');
  await p.selectOption('[data-mc-rule=partner_accrue_at]', 'payment'); await wait(p, 400);
  c = await calls(p, 'set_rule'); ok(c[c.length - 1].p_key === 'partner_accrue_at' && c[c.length - 1].p_value === 'payment', 'partner basis sends payment');

  // ---- blockers and server errors in plain words
  const pb = await open('#/monthclose'); await pb.evaluate(() => { window.__S82.can_close = false; window.__S82.blockers = ['payroll_not_posted', 'advance_recovery_exceeds_balance']; });
  await pb.selectOption('#mc_month', await pb.evaluate(() => document.querySelectorAll('#mc_month option')[1].value)); await wait(pb, 500); t = await text(pb);
  ok(/Payroll entries are not posted yet/.test(t) && /above the advance still owed/.test(t), 'blockers are explained'); ok(await pb.evaluate(() => document.querySelector('[data-act=mc_close]').disabled), 'close disabled while blocked');
  await pb.evaluate(() => { window.__S82.err.c_post_pending = 'not allowed'; }); await pb.click('[data-act=mc_post]'); await wait(pb, 400); t = await text(pb); ok(/not allowed to do this/.test(t), 'server refusal shown in plain words');

  // ---- not the owner: no settings, no split call
  const pn = await open('#/monthclose', { owner: false }); t = await text(pn);
  ok(!/Settings \(owner only\)/.test(t) && !/test_partner_one/.test(t) && (await calls(pn, 'c_partner_month_split')).length === 0, 'non-owner sees no settings and no partner split');
  ok(!(await pn.$('[data-act=mc_reopen]')), 'non-owner has no reopen button'); await noOverflow(pn, 'non-owner');

  // ---- Bangla: clean text, no overflow
  const bn = await open('#/monthclose', { lang: 'bn' }); t = await text(bn);
  ok(/মাস শেষের হিসাব/.test(t) && !/undefined|\[object|NaN/.test(t), 'Bangla renders cleanly'); await noOverflow(bn, 'bn');
  await bn.screenshot({ path: '/tmp/mc_bn.png', fullPage: true }); await p.screenshot({ path: '/tmp/mc_en.png', fullPage: true });

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
