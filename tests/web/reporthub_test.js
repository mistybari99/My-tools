// Business Memory hub (web/reporthub*.js). Run: node tests/web/reporthub_test.js <abs dir tests/web>
// Serves THIS checkout's web/ folder, mocks the phase470-476 RPCs, drives the pages at 360 px in three language modes.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), http = require('http'), path = require('path');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web');
const base = C.baseData(SP);
const srv = http.createServer((q, r) => { const f = path.join(WEB, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
  r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8397);
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const P = Object.assign({ fail: {}, masked: false, empty: false, mismatch: false, nopay: false, canExport: true, noCatalog: false }, window.__P0 || {});
 const ev = (k, t, extra) => Object.assign({ ts: '2026-10-17T05:' + t + ':00+00:00', time: '11:' + t, day: '2026-10-17', kind: k, area: 'sales', loc: 1, who: 'test_seller', amount: 100, qty: null, dir: 'in', title: k, status: 'done', detail: {}, ref_table: 'sales', ref_id: 'id-' + k, link: 'pos' }, extra || {});
 const EVENTS = [ev('sale', '10', { amount: 520, detail: { receipt: 7, pay_mode: 'cash', customer: 'test_customer_a', discount: 20 } }), ev('void', '20', { amount: 260, dir: 'out', status: 'void', detail: { receipt: 8 } }), ev('expense', '30', { area: 'expense', amount: 120, dir: 'out', ref_table: 'quick_expenses', detail: { head: 'staff_meal', paid_to: 'test_x' } }),
   ev('transfer_received', '40', { area: 'stock', amount: null, qty: 4, dir: 'in', ref_table: 'stock_transfers', detail: { short: 1, item: 'test_item' } }), ev('exception', '50', { area: 'control', who: null, amount: 50, dir: null, status: 'open', ref_table: 'exceptions' })];
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const SPEND = (f) => ({ generated_at: '2026-10-17T05:00:00+00:00', filters: f, total: 1500, count: 3, limit: 50, offset: 0, matched: { head: 1, memo: 1, both: 1, filter: 0 }, linked: { direct: 0, text: 1 }, unlinked: { count: P.unl || 0, amount: 220, missing_fields: ['quick_expenses.person_id'] }, overlap: { count: 0, amount: 0 }, no_source: 0,
   by_month: [{ month: '2026-09', amount: 700, n: 1 }, { month: '2026-10', amount: 800, n: 2 }], by_head: [{ head: 'staff_meal', label_en: 'Staff meals', label_bn: 'খাবার', amount: 1000, n: 2 }, { head: 'repair', label_en: 'Repairs', label_bn: 'মেরামত', amount: 500, n: 1 }], by_kind: [{ kind: 'quick_expense', amount: 1500, n: 3 }],
   rows: [{ date: '2026-10-17', ts: '2026-10-17T05:00:00+00:00', kind: 'quick_expense', status: 'posted', amount: 800, head: 'repair', head_en: 'Repairs', head_bn: 'মেরামত', memo: 'test electricity bill', loc: 1, mode: 'cash', who: 'test_owner', matched_by: 'memo', person_link: null, ref_table: 'quick_expenses', ref_id: 'q1', link: 'quickexp', detail: {}, possible_duplicate: false },
          { date: '2026-09-17', ts: '2026-09-17T05:00:00+00:00', kind: 'quick_expense', status: 'posted', amount: 700, head: 'staff_meal', head_en: 'Staff meals', head_bn: 'খাবার', memo: 'lunch', loc: 1, mode: 'cash', who: null, matched_by: 'both', person_link: null, ref_table: 'quick_expenses', ref_id: 'q2', link: 'quickexp', detail: {}, possible_duplicate: false }],
   masked: P.nopay ? ['advance', 'salary', 'head:staff_meal', 'head:labour', 'person:staff'] : [], notes: [], person: f.person ? { kind: f.person.kind, id: f.person.id, label: 'test_staff_a', allowed: true } : null });
 c.rpc = async (fn, args) => {
  if (!fn.startsWith('rpt_hub_') && fn !== 'report_catalog') return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (P.fail[fn]) return { data: null, error: { message: P.fail[fn] } };
  if (fn === 'report_catalog') return { data: P.noCatalog ? null : [], error: null };
  if (fn === 'rpt_hub_perms') return { data: { owner: P.canExport, areas: { export: P.canExport }, locations: [1, 2] }, error: null };
  if (fn === 'rpt_hub_my') return { data: window.__MY || { fav: [], view: [], pin: [], recent: [] }, error: null };
  if (fn === 'rpt_hub_item_save') { window.__MY = window.__MY || { fav: [], view: [], pin: [], recent: [] }; const k = args.p_kind; window.__MY[k].push({ id: 11, key: args.p_key, name: args.p_name, params: args.p_params }); return { data: 11, error: null }; }
  if (fn === 'rpt_hub_item_remove') { if (window.__MY) Object.keys(window.__MY).forEach((k) => { window.__MY[k] = window.__MY[k].filter((x) => x.id !== args.p_id); }); return { data: true, error: null }; }
  if (fn === 'rpt_hub_touch' || fn === 'rpt_hub_log_export') return { data: null, error: null };
  if (fn === 'rpt_hub_day') { const evs = P.empty ? [] : EVENTS; return { data: { generated_at: '2026-10-17T05:30:00+00:00', filters: { date: args.p_date, loc: args.p_loc }, total_events: evs.length, limit: args.p_limit, offset: args.p_offset, events: evs.slice(args.p_offset, args.p_offset + args.p_limit), kind_counts: P.empty ? {} : { sale: { n: 1, amount: 520 }, void: { n: 1 }, expense: { n: 1, amount: 120 } },
     totals: P.nopay || P.masked ? { net_sales: 2060, sales_total: 2320, returns_total: 260 } : { net_sales: 2060, sales_total: 2320, returns_total: 260, expense_total: 120, void_amount: 260 },
     reconcile: P.mismatch ? { status: 'mismatch', checks: [{ field: 'net_sales', hub: 2060, summary: 2000, ok: false }] } : P.masked ? { status: 'not_available', why: 'no_summary_right' } : { status: 'match', checks: [] },
     masked: P.masked ? [{ area: 'payroll', kinds: ['payroll', 'advance'] }, { area: 'stock', kinds: ['wastage'] }] : [], notes: [] }, error: null }; }
  if (fn === 'rpt_hub_find_entity') { if (args.p_q.indexOf('none') >= 0) return { data: [], error: null }; if (args.p_kind === 'staff') return { data: args.p_q.indexOf('two') >= 0 ? [{ kind: 'staff', id: 's1', label: 'test_staff_a', sub: 'sa' }, { kind: 'staff', id: 's2', label: 'test_staff_b', sub: 'sb' }] : [{ kind: 'staff', id: 's1', label: 'test_staff_a', sub: 'sa' }], error: null }; return { data: [{ kind: args.p_kind, id: 'x1', label: 'test_item_one', sub: 'code1' }], error: null }; }
  if (fn === 'rpt_hub_entity') return { data: { generated_at: '2026-10-17T05:31:00+00:00', entity: { kind: args.p_kind, id: args.p_id, label: 'test_item_one', sub: 'code1', unit: 'kg' }, filters: {}, has_balance: true, opening: 100, closing: 99, total_events: 2, events: [ev('ledger', '10', { area: 'stock', qty: 10, amount: null, balance: 110, title: 'purchase_in', ref_table: 'stock_ledger', link: null, detail: { reason: 'purchase_in', item: 'test_item_one' } }), ev('ledger', '20', { area: 'stock', qty: -11, amount: null, dir: 'out', balance: 99, title: 'issue_out', ref_table: 'stock_ledger', link: null, detail: { reason: 'issue_out' } })], kind_counts: {}, masked: [], notes: [] }, error: null };
  if (fn === 'rpt_hub_compare') return { data: { generated_at: '2026-10-17T05:32:00+00:00', a: { from: args.p_a_from, to: args.p_a_to, days: 17 }, b: { from: args.p_b_from, to: args.p_b_to, days: 30 }, notes: ['periods_differ_in_length'], masked: [], hidden_metrics: [], metrics: [{ key: 'net_sales', label_en: 'Net sales', label_bn: 'নিট বিক্রি', money: true, a: 1000, b: 1500, delta: 500, pct: 50, movers: [{ loc: 1, a: 1000, b: 1400, delta: 400 }] }, { key: 'void_count', label_en: 'Voided sales', label_bn: 'বাতিল', money: false, a: 2, b: 1, delta: -1, pct: -50, movers: [] }] }, error: null };
  if (fn === 'rpt_hub_drill') return { data: { generated_at: '2026-10-17T05:33:00+00:00', metric: args.p_metric, label_en: 'Net sales', label_bn: 'নিট বিক্রি', filters: {}, total: 2060, count: 2, limit: 50, offset: 0, groups: [{ key: '2026-10-17', n: 2, value: 2060 }], masked: [], rows: [Object.assign(ev('sale', '10'), { value: 2320 }), Object.assign(ev('return', '11', { ref_table: 'sale_returns' }), { value: -260 })] }, error: null };
  if (fn === 'rpt_hub_trail') return { data: { generated_at: '2026-10-17T05:34:00+00:00', table: args.p_table, id: args.p_id, record: { id: args.p_id, total: 260, status: 'void', note: null }, trail: [{ event: 'created', at: '2026-10-17T05:00:00+00:00', who: 'test_seller', note: null }, { event: 'voided', at: '2026-10-17T05:10:00+00:00', who: null, note: 'wrong item' }], reversals: [{ at: '2026-10-17T05:10:00+00:00', reason: 'sale_void_in', qty: 1, item: 'test_item', who: 'test_seller' }], journal: [], exceptions: [{ id: 1, flag: 'sale_void', level: 'yellow', status: 'open' }], corrections: [], change_requests: [], audit_log: [], not_recorded: ['who_voided'], notes: ['audit_log_owner_only'] }, error: null };
  if (fn === 'rpt_hub_spend_options') return { data: { heads: [{ code: 'staff_meal', list: 'expense_heads', label_en: 'Staff meals', label_bn: 'খাবার' }, { code: 'repair', list: 'expense_heads', label_en: 'Repairs', label_bn: 'মেরামত' }], utility_types: [], accounts: [], money_accounts: [], pay_modes: ['cash', 'bank', 'mobile', 'card'], locations: [] }, error: null };
  if (fn === 'rpt_hub_spend') return { data: SPEND(args.p_filters), error: null };
  return { data: null, error: null };
 };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; console.log('FAIL:', m); } };
  async function open(o, hash, lang) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/404/.test(m.text()) && !/not allowed/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o); data.tables.locations = data.tables.locations || [];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__P0=${JSON.stringify(o.p || {})};${o.owner === false ? 'window.__OWNER=false;' : ''}try{localStorage.setItem('bos_lang','${lang || 'en'}')}catch(e){}`);
    await p.goto('http://localhost:8397/#/home'); await p.waitForTimeout(1200);
    await p.evaluate((h) => { location.hash = h; }, hash); await p.waitForTimeout(1100);
    return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const askPage = async (o, q, lang) => { const p = await open(o, '#/reports/hub', lang); await p.evaluate((h) => { location.hash = h; }, '#/reports/hub/ask?q=' + encodeURIComponent(q)); await p.waitForTimeout(1400); return p; };

  // ---------- hub home + catalogue ----------
  let p = await open({}, '#/reports/hub');
  ok(/Business Memory/.test(await text(p)) && await p.locator('#rh_q').count() === 1, 'hub opens with the question box');
  ok(await p.locator('.rh-tool').count() === 5, 'five tools');
  ok(await p.locator('.rh-sec-h').count() === 14, 'INTEGRATION: all 14 sections of the registry are listed (got ' + await p.locator('.rh-sec-h').count() + ')');
  ok(/5\. Stock/.test(await p.textContent('#rh_cat')), 'section 5 name is shown');
  await noOverflow(p, 'hub home');
  await p.click('.rh-sec-h[data-v=s02]'); await p.waitForTimeout(200);
  ok(await p.locator('.rh-rep[data-id=r011]').count() === 1 && /Sales summary/.test(await p.textContent('.rh-rep[data-id=r011]')), 'a section opens and lists report 11');
  await p.click('.rh-rep[data-id=r011] .rh-rep-t'); await p.waitForTimeout(150);
  ok(/Data source/.test(await p.textContent('.rh-rep[data-id=r011]')) && /report_sales/.test(await p.textContent('.rh-rep[data-id=r011]')), 'a report row expands to source and required right');
  await p.fill('#rh_cq', 'electricity'); await p.waitForTimeout(250);
  ok(await p.locator('.rh-asklink').count() === 1, 'a word that is no report name offers to ask it as a question');
  await p.fill('#rh_cq', 'বিক্রি'); await p.waitForTimeout(250);
  ok(await p.locator('.rh-rep').count() >= 5, 'Bengali search finds sales reports');
  await p.fill('#rh_cq', '#76'); await p.waitForTimeout(250);
  ok(await p.locator('.rh-rep[data-id=r076]').count() === 1, 'search by report number');
  await p.fill('#rh_cq', 'zzzzqqq'); await p.waitForTimeout(250);
  ok(/Nothing matches/.test(await p.textContent('#rh_cat')), 'empty search says so');
  await p.fill('#rh_cq', ''); await p.waitForTimeout(150);
  await p.selectOption('#rh_ft', 'unavailable'); await p.waitForTimeout(200);
  ok(await p.locator('.rh-rep').count() === 1, 'INTEGRATION: status filter: 1 unavailable report in the registry (got ' + await p.locator('.rh-rep').count() + ')');
  await p.selectOption('#rh_ft', ''); await p.selectOption('#rh_fs', 'x'); await p.waitForTimeout(200);
  ok(await p.locator('.rh-rep').count() === 0, 'INTEGRATION: section filter: the not-audited group is empty, every report is in a section');
  await p.selectOption('#rh_fs', ''); await p.selectOption('#rh_fa', 'purchase'); await p.waitForTimeout(200);
  ok(await p.locator('.rh-rep').count() === 15, 'area filter purchasing = 15 reports');
  await p.selectOption('#rh_fa', '');
  await p.fill('#rh_cq', '#11'); await p.waitForTimeout(250);
  await p.click('.rh-rep[data-id=r011] .rh-star'); await p.waitForTimeout(300);
  ok((await calls(p, 'rpt_hub_item_save')).some((c) => c.p_kind === 'fav' && c.p_key === 'r011'), 'favourite saved on the server');
  ok(/★/.test(await p.textContent('.rh-rep[data-id=r011] .rh-star')), 'star turns on');
  await p.click('.rh-rep[data-id=r011] [data-act=rh_rep_open]'); await p.waitForTimeout(500);
  ok((await calls(p, 'rpt_hub_touch')).some((c) => c.p_key === 'r011'), 'opening a report is noted as recent');
  ok(/#\/report\/sales_summary/.test(await p.evaluate(() => location.hash)), 'it opens the existing viewer (report/sales_summary)');
  await p.close();

  // ---------- the old reports list gets the card (also when the report engine is missing) ----------
  p = await open({ p: { noCatalog: true } }, '#/reports');
  await p.waitForTimeout(2500);
  ok(await p.locator('#rh_banner').count() === 1, 'the old Reports page shows the Business Memory card (even when the report engine is missing)');
  await p.click('#rh_banner button'); await p.waitForTimeout(700);
  ok(/reports\/hub/.test(await p.evaluate(() => location.hash)) && await p.locator('#rh_q').count() === 1, 'the card leads to the hub');
  await p.close();

  // ---------- Ask / Find: English, chips, run ----------
  p = await open({}, '#/reports/hub');
  await p.fill('#rh_q', 'electricity bill of main branch last 8 months'); await p.click('[data-act=rh_ask]'); await p.waitForTimeout(1200);
  let c = await calls(p, 'rpt_hub_spend');
  ok(c.length === 1 && c[0].p_filters.heads.includes('electricity') && c[0].p_filters.loc === 1 && /^\d{4}-\d{2}-\d{2}$/.test(c[0].p_filters.from) && !c[0].p_filters.person, 'English question runs with head, place and period');
  ok(/I understood/.test(await text(p)) && await p.locator('.rh-chip').count() === 4, 'the four "I understood" chips are always shown');
  const chipsTxt = await p.textContent('#rh_chips');
  ok(/electricity/i.test(chipsTxt) && /last 8 months/i.test(chipsTxt), 'chips show what was read: electricity, last 8 months');
  ok(/Generated at/.test(await text(p)) && /Filters/.test(await text(p)), 'generated-at and the applied filters are visible');
  ok(/1,500|1500/.test(await text(p)) && /Month by month/.test(await text(p)), 'total and month by month shown');
  ok(await p.locator('.rh-ev .chip:has-text("memo")').count() >= 1 && await p.locator('.rh-ev .chip:has-text("both")').count() >= 1, 'rows say matched by memo / both');
  await noOverflow(p, 'ask result');
  await p.click('[data-act=rh_chip][data-s=place]'); await p.waitForTimeout(250);
  await p.selectOption('#rh_el', '2'); await p.click('[data-act=rh_ed_place]'); await p.waitForTimeout(800);
  c = await calls(p, 'rpt_hub_spend'); ok(c.length === 2 && c[1].p_filters.loc === 2, 'editing a chip re-runs with the new place');
  const dl = p.waitForEvent('download', { timeout: 4000 }).catch(() => null);
  await p.click('[data-act=rh_spend_csv]'); const d = await dl; ok(!!d, 'CSV file is produced'); if (d) { const txt = fs.readFileSync(await d.path(), 'utf8'); ok(/date,source,status,amount/.test(txt) && /test electricity bill/.test(txt) && txt.charCodeAt(0) === 0xfeff, 'CSV has header, rows and a BOM'); }
  ok((await calls(p, 'rpt_hub_log_export')).length === 1, 'the export is logged once');
  await p.fill('#rh_vn', 'my power bill'); await p.click('[data-act=rh_save_view]'); await p.waitForTimeout(300);
  ok((await calls(p, 'rpt_hub_item_save')).some((x) => x.p_kind === 'view' && x.p_name === 'my power bill' && /tool:spend/.test(x.p_key)), 'a view is saved with a name');
  await p.close();

  // ---------- Bengali question ----------
  p = await open({}, '#/reports/hub', 'bn');
  await p.fill('#rh_q', 'গত ৮ মাসে মেইন শাখার বিদ্যুৎ বিল কত'); await p.click('[data-act=rh_ask]'); await p.waitForTimeout(1200);
  c = await calls(p, 'rpt_hub_spend'); ok(c.length === 1 && c[0].p_filters.heads.includes('electricity') && c[0].p_filters.loc === 1, 'Bengali question runs the same way');
  ok(await p.locator('.rh-chip').count() === 4, 'Bengali: four chips');
  await noOverflow(p, 'bengali ask');
  await p.close();

  // ---------- unsure: no number, builder + reports ----------
  p = await open({}, '#/reports/hub');
  await p.fill('#rh_q', 'the water bill'); await p.click('[data-act=rh_ask]'); await p.waitForTimeout(900);
  ok((await calls(p, 'rpt_hub_spend')).length === 0, 'no period: NOTHING is run');
  ok(/did not guess a number/.test(await text(p)) && await p.locator('#rh_bld').count() === 1, 'it says it did not guess and shows the builder');
  ok(await p.locator('.rh-chip.missing').count() === 1, 'the period chip is marked missing');
  await p.click('[data-act=rh_chip][data-s=period]'); await p.waitForTimeout(200); await p.click('[data-act=rh_ed_pre][data-v=last_month]'); await p.waitForTimeout(900);
  ok((await calls(p, 'rpt_hub_spend')).length === 1, 'choosing a period then runs it');
  await p.close();
  p = await askPage({}, 'গত মাসে ভাড়া কত');
  ok((await calls(p, 'rpt_hub_spend')).length === 0 && await p.locator('.rh-chip.ambiguous').count() >= 1, 'ভাড়া alone is ambiguous: no run, the chip says choose');
  await p.close();
  p = await askPage({}, 'hello');
  ok((await calls(p, 'rpt_hub_spend')).length === 0 && /Examples/.test(await text(p)), 'unrelated text: no run, examples shown');
  await p.close();

  // ---------- person lookup ----------
  p = await askPage({}, 'how much was paid for test_staff_a meals in the last year');
  c = await calls(p, 'rpt_hub_spend'); ok(c.length === 1 && c[0].p_filters.person && c[0].p_filters.person.kind === 'staff' && c[0].p_filters.person.id === 's1' && c[0].p_filters.heads.includes('staff_meal'), 'the name is looked up first, then the person id is sent');
  ok((await calls(p, 'rpt_hub_find_entity')).length >= 1, 'find_entity was called');
  await p.close();
  p = await askPage({ p: { unl: 2 } }, 'paid for test_staff_a meals last year');
  ok(/Not linked to a person/.test(await text(p)) && /person id on quick expenses/.test(await text(p)), 'the not-linked count and the missing field are shown');
  await p.close();
  p = await askPage({}, 'paid for test_two meals last year');
  ok((await calls(p, 'rpt_hub_spend')).length === 0 && /Which one/.test(await text(p)), 'two people with that name: asks which one, runs nothing');
  await p.click('[data-act=rh_pick_person][data-i="1"]'); await p.waitForTimeout(900);
  c = await calls(p, 'rpt_hub_spend'); ok(c.length === 1 && c[0].p_filters.person.id === 's2', 'after the pick it runs for that person');
  await p.close();
  p = await askPage({}, 'paid for staff none meals last year');
  ok((await calls(p, 'rpt_hub_spend')).length === 0 && /not found/i.test(await text(p)), 'name not found: nothing run, said in words');
  await p.close();
  p = await askPage({ p: { nopay: true } }, 'staff meals last year');
  ok(/payroll right/.test(await text(p)), 'a viewer without the payroll right is told staff pay rows are not shown');
  await p.close();

  // ---------- Day replay ----------
  p = await open({}, '#/reports/hub/day?date=2026-10-17');
  ok(await p.locator('.rh-ev').count() === 5, 'day replay lists the events');
  ok(/Matches the daily summary/.test(await text(p)), 'reconciliation banner is green when it matches');
  ok(/11:10/.test(await text(p)) && /test_seller/.test(await text(p)) && /not recorded/.test(await text(p)), 'time and who are shown; a missing who says "not recorded"');
  ok(await p.locator('.rh-ev.void').count() === 1, 'a voided row is struck through');
  ok(await p.locator('.rh-ev [data-act=rh_trail]').count() === 5, 'every row links to its record');
  ok(/Generated at/.test(await text(p)) && /2026-10-17/.test(await p.textContent('.rh-stamp')), 'generated-at and the date filter are visible');
  ok(!/undefined/.test(await text(p)), 'no "undefined" text');
  await noOverflow(p, 'day replay');
  await p.click('[data-act=rh_day_kind][data-v=sale]'); await p.waitForTimeout(500);
  c = await calls(p, 'rpt_hub_day'); ok(c[c.length - 1].p_kinds && c[c.length - 1].p_kinds[0] === 'sale', 'kind chip filters on the server');
  await p.click('[data-act=rh_day_step][data-v="-1"]'); await p.waitForTimeout(500);
  c = await calls(p, 'rpt_hub_day'); ok(c[c.length - 1].p_date === '2026-10-16', 'previous day');
  await p.click('.rh-tot [data-act=rh_drill_day]'); await p.waitForTimeout(900);
  ok(/Behind this number/.test(await text(p)) && (await calls(p, 'rpt_hub_drill')).length === 1, 'tapping a total drills to the transactions');
  ok(/add up to the figure/.test(await text(p)), 'the drill says the rows add up to the figure');
  await p.close();
  p = await open({ p: { mismatch: true } }, '#/reports/hub/day?date=2026-10-17');
  ok(/oes NOT match/.test(await text(p)) && /2060 ≠ 2000/.test(await text(p)), 'a mismatch warning shows the two numbers');
  await p.close();
  p = await open({ p: { empty: true } }, '#/reports/hub/day?date=2026-10-17');
  ok(/Nothing is recorded for this day/.test(await text(p)), 'empty day: clear empty state');
  await p.close();
  p = await open({ p: { masked: true } }, '#/reports/hub/day?date=2026-10-17');
  ok(/Not shown to you/.test(await text(p)) && /Pay & advances/.test(await text(p)), 'masked kinds are named, no counts');
  ok(/Not compared/.test(await text(p)), 'reconcile unavailable is said, not guessed');
  await p.close();
  p = await open({ p: { fail: { rpt_hub_day: 'could not find the function public.rpt_hub_day' } } }, '#/reports/hub/day?date=2026-10-17');
  ok(/not installed on the database yet/.test(await text(p)), 'phases not pasted: clear message');
  await p.close();
  p = await open({ p: { canExport: false } }, '#/reports/hub/day?date=2026-10-17');
  const dl2 = p.waitForEvent('download', { timeout: 1500 }).catch(() => null); await p.click('[data-act=rh_day_csv]'); ok(!(await dl2), 'no export right: no file'); await p.close();
  p = await open({}, '#/reports/hub/day?date=2026-10-17');
  const dl3 = p.waitForEvent('download', { timeout: 4000 }).catch(() => null); await p.click('[data-act=rh_day_csv]'); const f3 = await dl3; ok(!!f3, 'day CSV downloads'); await p.close();

  // ---------- Entity / Compare / Trail ----------
  p = await open({}, '#/reports/hub/entity');
  await p.fill('#rh_eq', 'flour'); await p.click('[data-act=rh_ent_find]'); await p.waitForTimeout(500);
  await p.click('[data-act=rh_ent_pick]'); await p.waitForTimeout(800);
  ok(/Opening balance/.test(await text(p)) && /Closing balance/.test(await text(p)) && await p.locator('.rh-ev').count() === 2, 'item timeline with opening, closing and running balance');
  ok(/110/.test(await text(p)) && /99/.test(await text(p)), 'running quantity shown');
  await noOverflow(p, 'entity'); await p.close();
  p = await open({}, '#/reports/hub/compare');
  ok(/Net sales/.test(await text(p)) && /\+50/.test(await text(p)) && /Biggest movers/.test(await text(p)), 'compare: change, percent, movers');
  ok(/different lengths/.test(await text(p)), 'different period lengths are flagged');
  await noOverflow(p, 'compare');
  await p.click('[data-act=rh_cmp_why][data-m=net_sales]'); await p.waitForTimeout(800);
  ok(/Behind this number/.test(await text(p)), 'a figure name leads to the drill'); await p.close();
  p = await open({}, '#/reports/hub/trail?table=sales&id=abc');
  ok(/Voided/.test(await text(p)) && /wrong item/.test(await text(p)) && /Not recorded/.test(await text(p)) && /who voided it/.test(await text(p)), 'trail shows the void with its reason and what is not recorded');
  ok(/Stock reversals/.test(await text(p)) && /owner only/.test(await text(p)), 'reversals and the audit-log note');
  await noOverflow(p, 'trail'); await p.close();

  // ---------- three language modes ----------
  for (const lang of ['bn', 'mix', 'en']) {
    for (const h of ['#/reports/hub', '#/reports/hub/day?date=2026-10-17', '#/reports/hub/compare', '#/reports/hub/spend']) {
      p = await open({}, h, lang); await noOverflow(p, h + ' ' + lang); ok(!(await text(p)).includes('undefined'), 'no "undefined" on ' + h + ' ' + lang); await p.close();
    }
  }
  await br.close();
  console.log('RESULT: ' + (n - bad) + ' of ' + n + ' checks passed; page errors: ' + (errors.length ? errors.join(' | ') : 'none'));
  process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.log('TEST CRASH', e); process.exit(2); } finally { srv.close(); } })();
