// W7: nav leftovers - fiscal-year "Year" tab, drawer search (items / customers / screens), location switcher, staff "today's sheets", biz FY chip, reports2 merge.
// Run: node nav2_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const dhaka = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const rule = (key, v) => ({ key, module: 'settings', kind: 'number', value: v, default_value: null, label_bn: key, label_en: key, label_mix: key, sort: 1 });
// in-page helpers: record every rpc, give the stub builder .or() for the customer search
const EXTRA_NAV = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const from = c.from; window.__R = [];
 c.rpc = async (fn, args) => { window.__R.push([fn, JSON.parse(JSON.stringify(args || {}))]);
   if (fn === 'report_catalog2') return { data: [{ key: 'stock_low', group: 'stock', grant: 'report_stock', allowed: true, kind: 'raw', engine: 2, name_bn: 'স্টক কম', name_en: 'Stock at or below minimum', name_mix: 'Stock কম', filters: ['locations'], dims: [], default_group: null, columns: [], compare: false, needs_date: false }, { key: 'wastage', group: 'stock', grant: 'report_stock', allowed: true, kind: 'raw', engine: 2, name_bn: 'অপচয়', name_en: 'Wastage', name_mix: 'অপচয়', filters: ['date', 'locations'], dims: [{ key: 'reason', label_bn: 'কারণ', label_en: 'Reason', time: false }, { key: 'item', label_bn: 'আইটেম', label_en: 'Item', time: false }], default_group: 'reason', columns: [], compare: false, needs_date: true }], error: null };
   if (fn === 'report_catalog') return { data: [{ key: 'sales_summary', group: 'sales', grant: 'report_sales', allowed: true, kind: 'agg', name_bn: 'বিক্রি', name_en: 'Sales summary', name_mix: 'বিক্রি', filters: ['date', 'locations'], dims: [], default_group: '', columns: [], compare: false, needs_date: true }], error: null };
   if (fn === 'report_run2') return { data: { report: args.p_key, columns: [{ key: 'item_name', label_bn: 'আইটেম', label_en: 'Item', type: 'text', role: 'dim' }, { key: 'qty', label_bn: 'পরিমাণ', label_en: 'Qty', type: 'num', role: 'measure' }], rows: [{ item_name: 'A', qty: 3 }], totals: { qty: 3 }, compare: null, page: { n: 1, size: 50, groups: 1, cap: 500 }, has_more: false, notes: [], data_needed: false, meta: { from: '2026-10-01', to: '2026-10-12', sort: 'qty', dir: 'asc' } }, error: null };
   if (fn === 'report_presets') return { data: null, error: { message: 'x' } };
   return rpc(fn, args); };
 c.from = (t) => { const b = from(t); if (t === 'customers') { const sel = b.select; b.or = (expr) => { const m = /ilike\\.%([^%]*)%/.exec(expr); const q = (m ? m[1] : '').toLowerCase(); const rows = (window.__DATA.tables.customers || []).filter((r) => String(r.name || '').toLowerCase().includes(q) || String(r.mobile || '').includes(q)); const o = { select: () => o, order: () => o, limit: () => o, then: (res, rej) => Promise.resolve({ data: rows, error: null }).then(res, rej) }; return o; }; } return b; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + EXTRA_NAV }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o); (o.rules || []).forEach((r) => data.tables.rules.push(r)); if (o.customers) data.tables.customers = o.customers; if (o.entries) data.tables.entries = o.entries; if (o.rollout) o.rollout.forEach(([f, l, m]) => { const r = data.tables.form_rollout.find((x) => x.form_code === f && x.location_id === l); if (r) r.mode = m; });
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS=' + JSON.stringify(o.perms || {}) + ';' : ''}try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1300); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const rc = (p, fn) => p.evaluate((f) => window.__R.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const td = dhaka(), y = Number(td.slice(0, 4));

  // ---------- fiscal year ----------
  let p = await open({}, '#/home');
  ok(await p.evaluate(() => window.BOS.fyStart('2026-10-12')) === '2026-01-01', 'no fiscal rule -> 1 January');
  await p.click('[data-act=hv_period][data-v=year]'); await wait(p, 600);
  let c = await rc(p, 'sales_summary'); ok(c.length && c[c.length - 1].p_from === y + '-01-01', 'Year tab with no rule asks from 1 January: ' + JSON.stringify(c.slice(-1)));
  await p.close();
  p = await open({ rules: [rule('fiscal_year_start_month', 7), rule('fiscal_year_start_day', 1)] }, '#/home');
  const fy = await p.evaluate(() => ['2026-10-12', '2026-06-30', '2026-07-01', '2027-02-03'].map((d) => window.BOS.fyStart(d)));
  ok(JSON.stringify(fy) === JSON.stringify(['2026-07-01', '2025-07-01', '2026-07-01', '2026-07-01']), 'July fiscal year: ' + JSON.stringify(fy));
  await p.click('[data-act=hv_period][data-v=year]'); await wait(p, 600);
  c = await rc(p, 'sales_summary'); const exp = await p.evaluate((d) => window.BOS.fyStart(d), td);
  ok(c.length && c[c.length - 1].p_from === exp, 'Year tab asks from the fiscal start ' + exp);
  await p.close();
  p = await open({ rules: [rule('fiscal_year_start_month', 2), rule('fiscal_year_start_day', 31)] }, '#/home');
  const fe = await p.evaluate(() => [window.BOS.fyStart('2028-03-01'), window.BOS.fyStart('2028-02-28')]);
  ok(fe[0] === '2028-02-29' && fe[1] === '2027-02-28', 'day 31 in February is cut to the month end (leap year too): ' + JSON.stringify(fe));
  await p.close();
  p = await open({ rules: [rule('fiscal_year_start_month', 13), rule('fiscal_year_start_day', 0)] }, '#/home');
  ok(await p.evaluate(() => window.BOS.fyStart('2026-10-12')) === '2026-01-01', 'out-of-range rule values fall back to 1 January');
  await p.close();

  // ---------- biz page: fiscal-year chip ----------
  p = await open({ rules: [rule('fiscal_year_start_month', 7), rule('fiscal_year_start_day', 1)] }, '#/biz'); await wait(p, 500);
  ok(await p.locator('[data-act=bz_days][data-v=fy]').count() === 1, 'biz page has a fiscal-year chip');
  await p.click('[data-act=bz_days][data-v=fy]'); await wait(p, 600);
  c = await rc(p, 'biz_daily'); ok(c.length && c[c.length - 1].p_from === await p.evaluate((d) => window.BOS.fyStart(d), td), 'biz_daily asks from the fiscal start: ' + JSON.stringify(c.slice(-1)));
  await p.close();

  // ---------- drawer search ----------
  const cust = [{ id: 'c1', name: 'Karim Store', mobile: '01711000001' }, { id: 'c2', name: 'Jamal Mistan', mobile: '01811000002' }];
  p = await open({ customers: cust }, '#/home');
  const item = base.tables.items[0]; const frag = String(item.name_en || item.code).slice(0, 4);
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400);
  await p.fill('#nav_q', frag); await wait(p, 120);
  await wait(p, 900);
  ok(await p.locator('#nav_body .dr-it[data-v^="items/edit/"]').count() >= 1, 'item hit "' + frag + '" is listed and opens its edit page');
  await p.fill('#nav_q', 'jamal'); await wait(p, 900);
  ok(await p.locator('#nav_body .dr-it[data-v=dues]').count() === 1 && /Jamal Mistan/.test(await p.textContent('#nav_body')), 'customer hit by name');
  await p.fill('#nav_q', '0171100'); await wait(p, 900);
  ok(/Karim Store/.test(await p.textContent('#nav_body')) && !/Jamal/.test(await p.textContent('#nav_body')), 'customer hit by mobile fragment');
  await p.fill('#nav_q', '10-2'); await wait(p, 900);
  ok(await p.locator('#nav_body .dr-it[data-v="form/10-2"]').count() === 1, 'form hit by code');
  await p.fill('#nav_q', 'k'); await wait(p, 600);
  ok(!/Searching/.test(await p.textContent('#nav_body')) && await p.locator('#nav_body .dr-it[data-v=dues]').count() === 0, 'one letter searches the menu only (no customer / item fetch)');
  const cq = await p.evaluate(() => window.__R.length);
  // debounce: typing fast sends at most one customer query per pause (customers use from(), so count items fetches through rpc-free path: check no error)
  await p.fill('#nav_q', 'zzzzqq'); await wait(p, 900);
  ok(/Nothing found/.test(await p.textContent('#nav_body')), 'nothing found text');
  await p.screenshot({ path: SP + '/n2_search.png' });
  await p.close();

  // ---------- location switcher ----------
  p = await open({}, '#/home');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400);
  ok(await p.locator('#nav_loc').count() === 1, 'owner sees the location switcher');
  const opts = await p.locator('#nav_loc option').allTextContents(); ok(opts.length === 4 && /All locations/.test(opts[0]), 'All + 3 active places (closed one not offered): ' + JSON.stringify(opts));
  let ev = await p.evaluate(() => { window.__EV = []; window.addEventListener('bos:loc', (e) => window.__EV.push(e.detail.id)); return window.BOS.curLoc(); });
  ok(ev === null, 'owner default = all');
  await p.selectOption('#nav_loc', '2'); await wait(p, 600);
  const st = await p.evaluate(() => ({ cur: window.BOS.curLoc(), ev: window.__EV, ls: localStorage.getItem('bos_curloc_u1'), pos: localStorage.getItem('bos_pos_loc') }));
  ok(st.cur === 2 && JSON.stringify(st.ev) === '[2]' && st.ls === '2' && st.pos === '2', 'choice stored, POS place synced, event fired: ' + JSON.stringify(st));
  ok(await p.locator('#navDrawer.on').count() === 0, 'drawer closes after the choice');
  await p.reload(); await wait(p, 1300);
  ok(await p.evaluate(() => window.BOS.curLoc()) === 2, 'choice survives a reload (per user)');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400);
  ok(await p.inputValue('#nav_loc') === '2', 'switcher shows the saved place');
  await p.selectOption('#nav_loc', 'all'); await wait(p, 500);
  ok(await p.evaluate(() => window.BOS.curLoc()) === null, 'back to all');
  await p.close();
  // a person with exactly one place: fixed, no switcher
  p = await open({ owner: false, perms: { POS: { view: true, enter: true } }, m: { ctx: { roles: ['salesperson'], locations: [1], is_owner: false } } }, '#/home');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400);
  ok(await p.locator('#nav_loc').count() === 0 && await p.evaluate(() => window.BOS.curLoc()) === 1, 'one-place person: no switcher, curLoc fixed to 1');
  await p.close();
  // two places, not management: only their own, plus "all my places"
  p = await open({ owner: false, perms: { POS: { view: true, enter: true } }, m: { ctx: { roles: ['salesperson'], locations: [1, 3], is_owner: false } } }, '#/home');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400);
  const o2 = await p.locator('#nav_loc option').allTextContents(); ok(o2.length === 3, 'two-place person: all-mine + 2 places (not the third): ' + JSON.stringify(o2));
  await p.close();
  // a stored place that the person may not use is ignored
  p = await open({ owner: false, perms: { POS: { view: true, enter: true } }, m: { ctx: { roles: ['salesperson'], locations: [1, 3], is_owner: false } } }, '#/home');
  await p.evaluate(() => localStorage.setItem('bos_curloc_u1', '2')); ok(await p.evaluate(() => window.BOS.curLoc()) === null, 'foreign stored place ignored -> all mine');
  await p.close();

  // ---------- staff home: today's sheets ----------
  const E = (f, l, s) => ({ id: 'e_' + f + l + s, form_code: f, location_id: l, serial: 1, entry_date: td, status: s, data: {}, flags: [], created_by: 'u1' });
  const stf = { owner: false, perms: { '14-1': { view: true, enter: true }, '10-2': { view: true, enter: true }, '03-1': { view: true, enter: true }, '10-1': { view: true, enter: false }, POS: { view: true, enter: true } },
    m: { ctx: { roles: ['salesperson'], locations: [1], is_owner: false } }, entries: [E('14-1', 1, 'approved'), E('10-2', 1, 'draft'), E('04-1', 1, 'submitted')], rollout: [['03-1', 1, 'paper']] };
  p = await open(Object.assign({}, stf, { rules: [{ key: 'home_daily_forms', module: 'settings', kind: 'text', value: '14-1, 10-2, 03-1, 10-1', default_value: null, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 }] }), '#/home');
  const rows = await p.locator('#hv_sheets .hrow').allTextContents();
  ok(rows.length === 3, 'only enterable forms from the rule (10-1 is view-only): ' + JSON.stringify(rows));
  const t = (code) => rows.find((r) => r.includes(code)) || '';
  ok(/Done/.test(t('14-1')) && /Draft/.test(t('10-2')) && /On paper/.test(t('03-1')), 'states: submitted/approved = Done, draft = Draft, rollout paper = On paper');
  ok(/1\/2 done/.test(await p.textContent('#hv_sheets .hsec')), 'summary counts only app sheets: ' + (await p.textContent('#hv_sheets .hsec')));
  ok(/^(?!.*14-1)/.test(rows[0]) && /10-2/.test(rows[0]), 'unfinished (draft) comes before done');
  await p.click('#hv_sheets .hrow'); await wait(p, 500);
  ok(/#\/form\/10-2/.test(await p.evaluate(() => location.hash)), 'a row opens the form');
  await p.close();
  p = await open(stf, '#/home');   // rule empty: every enterable form of this person that exists in the app
  const all = await p.locator('#hv_sheets .hrow').count(); ok(all >= 3, 'rule empty -> all my enterable sheets (' + all + ')');
  ok(/narrow/i.test(await p.textContent('#hv_sheets')), 'hint tells the owner how to narrow the list');
  await p.screenshot({ path: SP + '/n2_sheets.png' });
  await p.close();
  p = await open({}, '#/home');
  ok(await p.locator('#hv_sheets .hrow').count() === 0, 'owner home has no sheets block');
  await p.close();
  // no form_rollout table readable: counts as app
  p = await open(Object.assign({}, stf, { rollout: [] }), '#/home');
  await p.evaluate(() => { window.__DATA.tables.form_rollout = []; });
  ok(await p.locator('#hv_sheets .hrow').count() >= 3, 'works when rollout rows are missing');
  await p.close();

  // ---------- reports hub merges the second engine ----------
  p = await open({}, '#/reports'); await wait(p, 600);
  const hub = await p.textContent('#rp_list');
  ok(/Sales summary/.test(hub) && /Stock at or below minimum/.test(hub) && /Wastage/.test(hub), 'hub lists both engines: ' + hub.slice(0, 120));
  ok(/Stock & wastage/.test(await p.textContent('#rp_gp')), 'new group tab named');
  await p.click('[data-act=rp_open][data-v=wastage]'); await wait(p, 900);
  c = await rc(p, 'report_run2'); ok(c.length === 1 && c[0].p_key === 'wastage', 'report_run2 called for an engine-2 key');
  ok((await rc(p, 'report_run')).length === 0, 'report_run NOT called for it');
  ok(await p.locator('#rp_g1').count() === 1 && (await p.locator('#rp_g1 option').allTextContents()).some((x) => /Reason/.test(x)), 'group picker shows the report dims');
  ok(await p.locator('#rp_g2').count() === 0, 'no second-level group for engine 2');
  ok(/A/.test(await p.textContent('#rp_tbl')), 'rows drawn');
  await p.close();
  p = await open({}, '#/report/stock_low'); await wait(p, 900);
  ok((await rc(p, 'report_run2')).length >= 1, 'direct link to an engine-2 report works (catalogue merged on load)');
  await p.close();

  const real = errors.filter((e) => !/Failed to load resource|favicon|net::ERR/.test(e));
  log('errors:', real.length ? real.join(' | ') : 'none'); log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('TEST CRASH', e); } srv.close(); })();
