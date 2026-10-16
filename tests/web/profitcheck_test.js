// Profit check screen (web/profitcheck.js). Run: node tests/web/profitcheck_test.js <abs dir tests/web>
// Serves THIS checkout's web/ folder, injects profitcheck.js (the integrator adds the script tag and the web/ia.js line), mocks the phase 92 / 93 RPCs and the settings rows.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), http = require('http'), path = require('path');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web');
const base = C.baseData(SP);
const srv = http.createServer((q, r) => { const f = path.join(WEB, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
  r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8392);
const RULES = [
  ['profit_one_number_on', 'switch', false, null, 'One profit number: count losses in the profit', 'Off keeps every profit figure exactly as it is today.'],
  ['profit_losses_from', 'text', null, null, 'Count these extra profit rows from this date', 'Blank counts every date.'],
  ['profit_loss_wastage', 'switch', true, null, 'Profit counts wasted stock', 'Acts only while the master switch is on.'],
  ['profit_loss_count', 'switch', true, null, 'Profit counts stock count shortages', 'Acts only while the master switch is on.'],
  ['profit_loss_transit', 'switch', true, null, 'Profit counts goods lost in transit', 'Acts only while the master switch is on.'],
  ['profit_loss_cashshort', 'switch', true, null, 'Profit counts cash short and over', 'Acts only while the master switch is on.'],
  ['profit_loss_billopex', 'switch', true, null, 'Profit counts running costs paid by supplier bill', 'Acts only while the master switch is on.'],
  ['profit_overhead_once', 'switch', true, null, 'Profit counts factory overhead once', 'Acts only while the master switch is on.'],
  ['profit_source', 'choice', 'management', ['management', 'ledger'], 'Partner shares take the profit from', 'management or ledger.'],
  ['report_salary_source', 'choice', 'legacy', ['legacy', 'app_first'], 'Salary in the profit comes from', 'legacy or app_first.'],
  ['report_expense_parity_on', 'switch', false, null, 'Expense report counts quick expenses and skips shadow vouchers', 'Off keeps the expense report as it is.'],
  ['expense_count_on', 'choice', 'as_today', ['as_today', 'approved', 'submitted'], 'Expense vouchers count when they are', 'as_today, approved or submitted.'],
  ['brand_map_dated_on', 'switch', false, null, 'Brand reports use the brand each place had on each day', 'Off = today\'s brand map for every day.'],
].map((x, i) => ({ key: x[0], module: 'reports', kind: x[1], value: null, default_value: x[2], choices: x[3], label_bn: x[4], label_mix: x[4], label_en: x[4], hint_en: x[5], sort: 790 + i }));
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 M.p = Object.assign({ excl: [], hist: [{ id: 1, location_id: 1, brand_code: 'test_a', brand_bn: 'test_a', brand_en: 'Test A', valid_from: null, valid_to: null, active: true, reason: 'existing', changed_at: '2026-10-01' }], fail: null }, window.__P0 || {});
 const RECON = { from: '2026-10-01', to: '2026-10-17', one_number_on: true, management_profit: -931, ledger_profit: -796, difference: -135, explained: -135, unexplained: 0, unposted_documents: 0, ledger_note: null,
   would_add_if_counted: { wastage: { amount: 30, rows: 1 }, count_shrink: { amount: 120, rows: 1 } },
   rows: [{ key: 'sales', label_en: 'Net sales', management: 400, ledger: 400, difference: 0, reason: null }, { key: 'count_shrink', label_en: 'Stock count shortage', management: -120, ledger: 0, difference: -120, reason: 'count_adjustment_not_in_journal_yet' },
          { key: 'cash_short', label_en: 'Cash short and over', management: -15, ledger: 0, difference: -15, reason: 'cash_short_not_posted_to_journal' }, { key: 'other', label_en: 'Other journal entries', management: 0, ledger: 0, difference: 0, reason: null }] };
 const PAR = { expenses: { daybook: 800, pl: 800, expense_report: 500, journal: 800, agree: false }, salary: { daybook_paid: 8000, pl: 7000, journal: 8000, pl_agrees_journal: false, note: 'The P&L and the journal show the salary expense.' } };
 c.rpc = async (fn, args) => {
  const known = ['profit_recon', 'report_parity', 'profit_exclusions_list', 'profit_exclude', 'profit_exclusion_revoke', 'brand_map_hist_list', 'brand_map_set', 'set_rule'];
  if (!known.includes(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (M.p.fail && M.p.fail[fn]) return { data: null, error: { message: M.p.fail[fn] } };
  if (fn === 'profit_recon') return { data: RECON, error: null };
  if (fn === 'report_parity') return { data: PAR, error: null };
  if (fn === 'profit_exclusions_list') return { data: clone(M.p.excl), error: null };
  if (fn === 'profit_exclude') { M.p.excl.push({ id: 5, cause: args.p_cause, source_id: args.p_source_id, amount: 30, row_date: '2026-10-17', reason: args.p_reason, status: 'active' }); return { data: 5, error: null }; }
  if (fn === 'profit_exclusion_revoke') { M.p.excl.forEach((x) => { if (x.id === args.p_id) { x.status = 'revoked'; x.revoke_reason = args.p_reason; } }); return { data: true, error: null }; }
  if (fn === 'brand_map_hist_list') return { data: clone(M.p.hist), error: null };
  if (fn === 'brand_map_set') return { data: { id: 9, valid_from: args.p_from, backdated: false }, error: null };
  if (fn === 'set_rule') { const r = window.__DATA.tables.rules.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; return { data: null, error: null }; }
  return { data: null, error: null };
 };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } };
  async function open(o, hash, lang) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/404/.test(m.text()) && !/not allowed/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o); data.tables.locations = data.tables.locations || [];
    data.tables.rules = (data.tables.rules || []).filter((x) => !RULES.some((r) => r.key === x.key)).concat(JSON.parse(JSON.stringify(RULES)));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__P0=${JSON.stringify(o.p || {})};${o.owner === false ? 'window.__OWNER=false;' : ''}try{localStorage.setItem('bos_lang','${lang || 'en'}')}catch(e){}`);
    await p.goto('http://localhost:8392/' + hash); await p.waitForTimeout(1200);
    await p.addScriptTag({ content: fs.readFileSync(path.join(WEB, 'profitcheck.js'), 'utf8') });      // the integrator adds the real script tag
    await p.evaluate(() => { location.hash = '#/x'; }); await p.waitForTimeout(100);
    await p.evaluate(() => { location.hash = '#/profitcheck'; }); await p.waitForTimeout(900);
    return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);

  let p = await open({}, '');
  ok(await p.locator('#pc_body [data-key]').count() === 13, 'all 13 settings are drawn (got ' + await p.locator('#pc_body [data-key]').count() + ')');
  const txt = await p.textContent('#pc_body');
  ok(/One profit number: count losses in the profit/.test(txt) && /Expense vouchers count when they are/.test(txt), 'labels come from the server rows, in English');
  ok(!/[^\x00-\x7F]/.test(txt.replace(/৳|…/g, '')), 'no non-English letters on the page');
  await noOverflow(p, 'profit check page');
  // switch: master on
  await p.click('[data-key=profit_one_number_on] button'); await p.waitForTimeout(400);
  let c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'profit_one_number_on' && c[0].p_value === true, 'master switch sent as set_rule true');
  ok(/On/.test(await p.textContent('[data-key=profit_one_number_on]')), 'master shows On after saving');
  // switch that is ON by default goes off
  await p.click('[data-key=profit_loss_wastage] button'); await p.waitForTimeout(400);
  c = await calls(p, 'set_rule'); ok(c.length === 2 && c[1].p_key === 'profit_loss_wastage' && c[1].p_value === false, 'a default-on switch is sent as false');
  // choice: only a change sends, a click does not
  await p.click('[data-key=profit_source] select'); await p.waitForTimeout(150); ok((await calls(p, 'set_rule')).length === 2, 'clicking a choice sends nothing');
  await p.selectOption('[data-key=profit_source] select', 'ledger'); await p.waitForTimeout(400);
  c = await calls(p, 'set_rule'); ok(c.length === 3 && c[2].p_key === 'profit_source' && c[2].p_value === 'ledger', 'choice change sent');
  // start date text rule
  await p.fill('[data-key=profit_losses_from] input', '2026-10-01'); await p.click('[data-key=profit_losses_from] button'); await p.waitForTimeout(400);
  c = await calls(p, 'set_rule'); ok(c.length === 4 && c[3].p_key === 'profit_losses_from' && c[3].p_value === '2026-10-01', 'start date sent');
  await p.fill('[data-key=profit_losses_from] input', ''); await p.click('[data-key=profit_losses_from] button'); await p.waitForTimeout(400);
  c = await calls(p, 'set_rule'); ok(c.length === 5 && c[4].p_value === null, 'blank start date sent as null (every date)');
  // compare
  await p.click('[data-act=pc_cmp]'); await p.waitForTimeout(500);
  c = await calls(p, 'profit_recon'); ok(c.length === 1 && c[0].p_loc === null && /^\d{4}-\d{2}-01$/.test(c[0].p_from), 'recon asked for the month so far, all places');
  const out = await p.textContent('#pc_out');
  ok(/931/.test(out) && /796/.test(out) && /135/.test(out), 'management, journal and difference are shown');
  ok(/stock count shortage is not written to the books yet/i.test(out) && /Cash short is not posted/i.test(out), 'the named causes are shown in words');
  ok(/Net sales/.test(out) && !/Other journal entries/.test(out), 'zero lines are hidden, lines with a figure are shown');
  if (process.env.W1D_SHOT) await p.screenshot({ path: process.env.W1D_SHOT, fullPage: true });      // optional, for a look by hand; the test itself writes no image into the repo
  ok(/If you count it, profit changes by/.test(out), 'the effect before switching on is shown');
  ok(/Differ/.test(await p.textContent('#pc_par')) && /500/.test(await p.textContent('#pc_par')), 'parity: the expense report differs (500)');
  await noOverflow(p, 'with the reconciliation open');
  // exception path
  await p.fill('#pc_xs', 'w-1'); await p.fill('#pc_xr', 'abc'); await p.click('[data-act=pc_excl]'); await p.waitForTimeout(250);
  ok((await calls(p, 'profit_exclude')).length === 0, 'a short reason is not sent');
  await p.fill('#pc_xr', 'flood damage, owner decision'); await p.click('[data-act=pc_excl]'); await p.waitForTimeout(500);
  c = await calls(p, 'profit_exclude'); ok(c.length === 1 && c[0].p_cause === 'wastage' && c[0].p_source_id === 'w-1' && c[0].p_reason === 'flood damage, owner decision', 'exclusion sent with its reason');
  ok(/Left out/.test(await p.textContent('#pc_body')) && /flood damage/.test(await p.textContent('#pc_body')), 'the exception is listed');
  await p.click('[data-act=pc_unexcl]'); await p.waitForTimeout(250); ok((await calls(p, 'profit_exclusion_revoke')).length === 0, 'revoke without a reason is not sent');
  await p.fill('#pc_rv_5', 'counted again after the review'); await p.click('[data-act=pc_unexcl]'); await p.waitForTimeout(500);
  c = await calls(p, 'profit_exclusion_revoke'); ok(c.length === 1 && c[0].p_id === 5 && c[0].p_reason === 'counted again after the review', 'revoke sent with its reason');
  ok(/Counted again/.test(await p.textContent('#pc_body')), 'the revoked exception shows as counted again');
  // brand map: a past date needs a reason
  await p.fill('#pc_bc', 'test_b'); await p.fill('#pc_bb', 'test_b'); await p.fill('#pc_be', 'Test B'); await p.fill('#pc_bf', '2020-01-05'); await p.fill('#pc_br', ''); await p.click('[data-act=pc_brand]'); await p.waitForTimeout(250);
  ok((await calls(p, 'brand_map_set')).length === 0, 'a past date without a reason is not sent');
  await p.fill('#pc_br', 'the brand was wrong from that day'); await p.click('[data-act=pc_brand]'); await p.waitForTimeout(500);
  c = await calls(p, 'brand_map_set'); ok(c.length === 1 && c[0].p_code === 'test_b' && c[0].p_from === '2020-01-05' && c[0].p_reason === 'the brand was wrong from that day', 'brand change sent with date and reason');
  await p.fill('#pc_bc', ''); await p.click('[data-act=pc_brand]'); await p.waitForTimeout(200); ok((await calls(p, 'brand_map_set')).length === 1, 'a blank brand is not sent');
  await p.close();

  // server refusal is shown, nothing crashes
  p = await open({ p: { fail: { profit_exclude: 'already_excluded', set_rule: 'bad_value' } } }, '');
  await p.fill('#pc_xs', 'w-1'); await p.fill('#pc_xr', 'a reason that is long enough'); await p.click('[data-act=pc_excl]'); await p.waitForTimeout(400);
  ok(/already left out/.test(await p.evaluate(() => document.body.innerText)), 'server refusal shown in words');
  await p.click('[data-key=profit_one_number_on] button'); await p.waitForTimeout(300); ok(/not allowed/.test(await p.evaluate(() => document.body.innerText)), 'a refused setting shows the message');
  await p.close();

  // not the owner: the settings are read-only
  p = await open({ owner: false }, '');
  ok(await p.locator('[data-key=profit_one_number_on] button[disabled]').count() === 1 && await p.locator('[data-key=profit_source] select[disabled]').count() === 1, 'a non-owner sees the settings disabled');
  ok(/Only the owner can change these/.test(await p.textContent('#pc_body')), 'and is told why');
  await p.close();

  // all three language modes: no horizontal overflow, nothing breaks
  for (const lang of ['bn', 'mix', 'en']) {
    p = await open({}, '', lang);
    await p.click('[data-act=pc_cmp]'); await p.waitForTimeout(500);
    ok(await p.locator('#pc_body [data-key]').count() === 13, 'settings drawn in ' + lang);
    await noOverflow(p, lang); await p.close();
  }
  await br.close();
  console.log('errors:', errors.length ? errors.join(' | ') : 'none'); console.log('assert failures:', bad);
  process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.log('TEST CRASH', e); process.exit(2); } finally { srv.close(); } })();
