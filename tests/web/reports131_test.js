// Verified reports #/reports131 (web/reports131.js), RPCs mocked with the REAL shapes of the phase131 functions.
// Checks: catalogue + off banner, sales table + totals + generated-at + filters text, sort / paging calls, drill (day -> documents), status chips, "data needed" for empty, cost-hidden note,
// friendly errors, CSV export (BOM, footer, export log call), html escaping, 360px no horizontal page overflow, no JS errors.
// Run: node reports131_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const I = window.__R;
 const clone = (x) => JSON.parse(JSON.stringify(x));
 c.rpc = async (fn, args) => {
  (window.__ACI = window.__ACI || []).push([fn, clone(args || {})]);
  if (fn === 'rpt131_catalog') return { data: { enabled: !I.off, reports: [] }, error: null };
  if (fn === 'rpt131_log_export') return { data: null, error: I.nolog ? { message: 'not allowed' } : null };
  if (fn.startsWith('rpt131_')) { if (I.err) return { data: null, error: { message: I.err } }; const r = clone(I.res[fn] || I.res.empty); if (fn === 'rpt131_sales' && args.p_sort) r.sort = args.p_sort; if (I.nocost) r.cost_visible = false; return { data: r, error: null }; }
  return rpc(fn, args);
 }; return c; }; })();`;
const cols = [{ k: 'label', bn: 'ভাগ', en: 'Group', t: 'text' }, { k: 'bills', bn: 'বিল', en: 'Bills', t: 'int', sum: true }, { k: 'net_sales', bn: 'নিট বিক্রি', en: 'Net sales', t: 'money', sum: true }, { k: 'margin', bn: 'মার্জিন', en: 'Margin', t: 'money', sum: true, cost: true }];
const mkR = (o) => ({ off: !!o.off, nocost: !!o.nocost, err: null, nolog: !!o.nolog, res: {
  rpt131_sales: { report: 'rpt131_sales', off: false, generated_at: '2026-10-15T04:07:00Z', generated_by: 'Own<b>er</b>', filters: { from: '2026-10-12', to: '2026-10-15', group: 'day' }, columns: cols,
    rows: [{ dim: '2026-10-12', label_bn: '2026-10-12', label_en: '2026-10-12', bills: 4, net_sales: 2080, margin: null }, { dim: '2026-10-15', label_bn: 'X<i>y</i>', label_en: 'X<i>y</i>', bills: 2, net_sales: -340, margin: null }],
    totals: { bills: 6, net_sales: 1740, margin: null }, row_count: 2, page: 1, size: 50, has_more: false, sort: 'dim:asc', data_needed: false, cost_visible: true, notes: [{ code: 'basis', text_en: 'Voided bills are never counted.', text_bn: 'বাতিল গোনা হয়নি' }] },
  rpt131_sales_recon: { report: 'rpt131_sales_recon', off: false, generated_at: '2026-10-15T04:07:00Z', filters: { from: '2026-10-12', to: '2026-10-12', status: 'all' },
    columns: [{ k: 'd', bn: 'তারিখ', en: 'Date', t: 'date' }, { k: 'ref', bn: 'রসিদ', en: 'Receipt', t: 'text' }, { k: 'register_net', bn: 'রেজিস্টার', en: 'Register', t: 'money', sum: true }, { k: 'status', bn: 'স্ট্যাটাস', en: 'Status', t: 'status' }],
    rows: [{ doc_type: 'sale', doc_id: 'abc', d: '2026-10-12', ref: '1', register_net: 900, status: 'posted' }, { doc_type: 'return', doc_id: 'def', d: '2026-10-12', ref: 'R-1', register_net: -300, status: 'unposted', outlet_en: 'Main' }],
    totals: { register_net: 600 }, row_count: 2, page: 1, size: 50, has_more: false, data_needed: false, cost_visible: true, notes: [],
    tie_out: { register_net_total: 600, docs_books_net_total: 900, journal_by_entry_date: 900, unposted_value: -300, not_reversed_docs: 0, explained_gap: -300 }, summary: { by_status: { 'posted/sale': { docs: 1, register_net: 900, books_net: 900 } } } },
  empty: { report: 'x', off: false, generated_at: '2026-10-15T04:07:00Z', filters: {}, columns: cols, rows: [], totals: null, row_count: 0, page: 1, size: 50, has_more: false, data_needed: true, cost_visible: true, notes: [] } } });
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } };
  async function open(hash, o = {}, lang = 'en') {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__R=${JSON.stringify(mkR(o))};try{localStorage.setItem('bos_lang','${lang}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__ACI || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'page overflow ' + m);

  let p = await open('#/reports131');
  let t = await text(p);
  ok(await p.locator('#r131_off').count() === 0, 'no off banner when enabled');
  ok(await p.locator('table.r131-t tbody tr').count() === 2, 'two result rows');
  ok(/Net sales/.test(t) && /2,080.00/.test(t) && /-340.00/.test(t), 'money formatted, negative day kept');
  ok(/Total/.test(t) && /1,740.00/.test(t), 'server totals shown');
  ok(/Generated:/.test(t) && /Filters:/.test(t) && /2026-10-12 → 2026-10-15/.test(t), 'generated-at and the filters are displayed');
  ok(/Voided bills are never counted/.test(t), 'notes shown');
  ok(await p.locator('table.r131-t td >> text=—').count() >= 2, 'null cost / margin shown as a dash (data needed), not 0');
  ok(!(await p.locator('table.r131-t').innerHTML()).includes('<i>y</i>') && /X<i>y<\/i>/.test(t), 'row text escaped');
  ok(/Own<b>er<\/b>/.test(t), 'generated-by escaped');
  const first = await calls(p, 'rpt131_sales'); ok(first.length >= 1 && first[0].p_group === 'day' && /^\d{4}-\d\d-\d\d$/.test(first[0].p_from) && first[0].p_locs === null && first[0].p_page === 1, 'first call payload');
  await noOverflow(p, 'result'); 
  ok(await p.evaluate(() => { const w = document.querySelector('.r131-wrap'); return !!w && getComputedStyle(w).overflowX === 'auto'; }), 'table scrolls inside its own box');
  const small = await p.evaluate(() => [...document.querySelectorAll('#r131_body button, #r131_body select, #r131_body input')].filter((b) => b.offsetParent && !b.classList.contains('ctl-hid') && b.getBoundingClientRect().height < 39.5).length); if (small) console.log('small:', await p.evaluate(() => [...document.querySelectorAll('#r131_body button, #r131_body select, #r131_body input')].filter((b) => b.offsetParent && !b.classList.contains('ctl-hid') && b.getBoundingClientRect().height < 39.5).map((b) => b.tagName + '#' + b.id + '.' + b.className + ' ' + b.getBoundingClientRect().height))); ok(small === 0, 'taps at least 40px');
  await p.screenshot({ path: SP + '/r131_list.png', fullPage: true });

  // group change, outlet, sort
  await p.selectOption('#r131_group', 'outlet'); await wait(p, 400);
  let c = await calls(p, 'rpt131_sales'); ok(c[c.length - 1].p_group === 'outlet', 'group change reloads');
  await p.click('th[data-k=net_sales]'); await wait(p, 400);
  c = await calls(p, 'rpt131_sales'); ok(c[c.length - 1].p_sort === 'net_sales:desc', 'sort click sends the sort');
  await p.click('th[data-k=net_sales]'); await wait(p, 400);
  c = await calls(p, 'rpt131_sales'); ok(c[c.length - 1].p_sort === 'net_sales:asc', 'second click flips the direction');
  await p.fill('#r131_q', 'test_user_a'); await p.click('[data-act=r131_go]'); await wait(p, 400);
  c = await calls(p, 'rpt131_sales'); ok(c[c.length - 1].p_search === 'test_user_a' && c[c.length - 1].p_page === 1, 'search sent');

  // drill: group by day then tap a row
  await p.selectOption('#r131_group', 'day'); await wait(p, 400);
  await p.click('tr.r131-row[data-i="0"]'); await wait(p, 600);
  c = await calls(p, 'rpt131_sales_recon'); ok(c.length >= 1 && c[c.length - 1].p_from === '2026-10-12' && c[c.length - 1].p_to === '2026-10-12', 'a day row opens the documents of that day');
  t = await text(p);
  ok(await p.locator('.r131-chip', { hasText: /^Posted$/ }).count() === 1 && await p.locator('.r131-chip', { hasText: 'Unposted' }).count() === 1, 'status chips');
  ok(/Tie-out to the books/.test(t) && /Register − books/.test(t) && /-300.00/.test(t), 'tie-out block shown');
  await noOverflow(p, 'recon');
  await p.click('tr.r131-row[data-i="1"]'); await wait(p, 300);
  ok(await p.locator('#sheet').count() === 1 && /R-1/.test(await p.textContent('#sheet')), 'a return opens a detail sheet');
  await p.click('[data-act=closesheet]'); await wait(p, 100);

  // status filter and report picker
  await p.selectOption('#r131_status', 'unposted'); await wait(p, 400);
  c = await calls(p, 'rpt131_sales_recon'); ok(c[c.length - 1].p_status === 'unposted', 'status filter sent');
  await p.selectOption('#r131_key', 'rpt131_wastage'); await wait(p, 500);
  c = await calls(p, 'rpt131_wastage'); ok(c.length >= 1 && c[0].p_group === 'reason' && c[0].p_status === 'all', 'wastage defaults');
  ok(/Data needed: nothing matches/.test(await text(p)), 'empty result says data needed, no zero totals');
  await p.selectOption('#r131_key', 'rpt131_ageing'); await wait(p, 500);
  c = await calls(p, 'rpt131_ageing'); ok(c[0].p_kind === 'receivable', 'ageing call');
  await p.selectOption('#r131_kind', 'payable'); await wait(p, 400);
  c = await calls(p, 'rpt131_ageing'); ok(c[c.length - 1].p_kind === 'payable' && c[c.length - 1].p_as_of === null && await p.locator('#r131_asof').isDisabled(), 'payable ignores the date');

  // CSV
  await p.selectOption('#r131_key', 'rpt131_sales'); await wait(p, 500);
  const [dl] = await Promise.all([p.waitForEvent('download'), p.click('[data-act=r131_csv]')]); await wait(p, 600);
  const csv = fs.readFileSync(await dl.path(), 'utf8');
  ok(csv.charCodeAt(0) === 0xFEFF && /Group,Bills,Net sales/.test(csv) && /Total,6,1740/.test(csv) && /Generated:/.test(csv) && /Filters:/.test(csv), 'csv has BOM, header, total, generated-at and filters');
  c = await calls(p, 'rpt131_log_export'); ok(c.length === 1 && c[0].p_key === 'rpt131_sales' && c[0].p_kind === 'csv' && c[0].p_rows === 2, 'export logged on the server');

  // friendly errors
  await p.evaluate(() => { window.__R.err = 'bad_range'; }); await p.click('[data-act=r131_go]'); await wait(p, 400);
  ok(/date range is not valid/.test(await text(p)), 'bad_range is friendly');
  await p.evaluate(() => { window.__R.err = 'not allowed for this location'; }); await p.click('[data-act=r131_go]'); await wait(p, 400);
  ok(/place is not open to you/.test(await text(p)), 'location refusal is friendly');
  await noOverflow(p, 'error');

  // off
  p = await open('#/reports131', { off: true });
  ok(await p.locator('#r131_off').count() === 1 && /switched off/.test(await text(p)), 'off banner'); await noOverflow(p, 'off');
  // cost hidden
  p = await open('#/reports131', { nocost: true });
  t = await text(p); ok(/Cost columns are hidden for you/.test(t) && !/Margin/.test(await p.locator('thead').innerText()), 'cost columns hidden with a note');
  // bangla
  p = await open('#/reports131', {}, 'bn');
  ok(/যাচাই করা রিপোর্ট/.test(await text(p)) && /তৈরি:/.test(await text(p)), 'bangla mode'); await noOverflow(p, 'bn');
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
