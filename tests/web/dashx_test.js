// Owner dashboard (#/dashx): default layout, chart-type switching with a FAKE B.charts (or the REAL web/charts.js with DX_REAL=1), metric picker + cost secrecy, drag and drop (mouse and touch),
// up/down buttons, reset, fail-soft tiles, no overflow, English-only text, blocked localStorage, period/location sharing, abort on leaving.
// Run: node tests/web/dashx_test.js     (DX_REAL=1 to use web/charts.js instead of the local fake; DX_SHOTS=0 to skip the screenshots)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = _P.TESTS_DIR;
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const REAL = process.env.DX_REAL === '1';
const dh = (n = 0) => new Date(Date.now() + n * 86400000).toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
const TD = dh(0), YD = dh(-1);
const DEF = 11;
const NOCOSTP = 'window.__PERMS={ITEMS:{view:true,enter:true,approve:false}};';
const BN = /[ঀ-৿]/;

// ---- the "server" side of the layout (in node) ----
const SRV = { layout: null, updated: null, saves: [], gets: 0, missing: false };
const srvOp = (op, a) => {
  if (op === 'get') { SRV.gets++; return SRV.missing ? { error: 'missing' } : { layout: SRV.layout, updated_at: SRV.updated }; }
  if (op === 'save') { if (SRV.missing) return { error: 'missing' }; const same = JSON.stringify(SRV.layout) === JSON.stringify(a.layout); SRV.layout = JSON.parse(JSON.stringify(a.layout)); SRV.updated = new Date().toISOString(); SRV.saves.push(JSON.parse(JSON.stringify(a.layout))); return { ok: true, changed: !same }; }
  return null;
};

// ---- a tiny local fake of B.charts (contract: TYPES, render, compatible, convert) ----
const FAKE = `(function(){ var B = window.BOS; var L = B.L; var ids = ['line','area','bar','column','stacked_bar','pie','donut','treemap','gauge','bullet'];
 var names = ['Line','Area','Bar','Column','Stacked bar','Pie','Donut','Treemap','Gauge','Bullet']; var bn = ['লাইন চার্ট','এরিয়া','বার','কলাম','স্ট্যাকড বার','পাই','ডোনাট','ট্রি-ম্যাপ','গেজ','বুলেট'];
 var calls = window.__CR = [];
 B.charts = { TYPES: ids.map(function (id, i) { return { id: id, label: L(bn[i], names[i], names[i]), icon: names[i].slice(0, 2) }; }),
  compatible: function (s) { var out = []; if (s.slices) out = ['bar','column','pie','donut','treemap']; else if (s.series && !(s.value !== undefined)) { out = ['line','area','bar','column']; if (s.series.length > 1) out.push('stacked_bar'); } else if (s.value !== undefined) { out = ['gauge','bullet']; if (s.series) out = ['line','area','bar','column'].concat(out); }
   return out; },
  convert: function (s, to) { var c = Object.assign({}, s); c.type = to; c.converted = true; return c; },
  render: function (host, spec) { calls.push({ op: 'render', type: spec.type, spec: Object.assign(JSON.parse(JSON.stringify(spec)), { hasFormat: typeof spec.format === 'function' && typeof spec.format(1234) === 'string' }), title: spec.title }); host.innerHTML = '<svg class="fk" data-type="' + spec.type + '" width="100" height="20"></svg>';
   return { update: function (s) { calls.push({ op: 'update', type: s.type, spec: JSON.parse(JSON.stringify(s)) }); }, destroy: function () { calls.push({ op: 'destroy' }); host.innerHTML = ''; } }; } };
})();`;

// REAL charts.js: wrap render() so every call is recorded the same way as the fake does
const WRAP = `;(function(){ var c = window.BOS.charts, calls = window.__CR = [], r = c.render; var rec = function (op, s) { return { op: op, type: s.type, spec: Object.assign(JSON.parse(JSON.stringify(s)), { converted: !!s._shape || s.converted, hasFormat: typeof s.format === 'function' && typeof s.format(1234) === 'string' }), title: s.title }; };
 c.render = function (host, spec) { calls.push(rec('render', spec)); var h = r(host, spec); return { update: function (s) { calls.push(rec('update', s)); return h.update(s); }, destroy: function () { calls.push({ op: 'destroy' }); return h.destroy(); } }; }; })();`;
const FK = REAL ? 'svg.bch-svg' : '.fk';
const R = (key, def) => ({ key, module: 'ui', kind: 'switch', value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1 });
const OBD = () => ({
  sales: [TD, YD, dh(-2), dh(-3), dh(-5), dh(-8), dh(-9)].map((d, i) => ({ sale_date: d, location_id: 1, pay_mode: i % 2 ? 'bkash' : 'cash', status: 'done', n: 10 + i, total: 5000 - i * 300, discount: 100 }))
    .concat([{ sale_date: TD, location_id: 1, pay_mode: 'cash', status: 'void', n: 2, total: 300, discount: 0 }]),
  cat: [{ category: 'sweet', cat_name_bn: 'মিষ্টি', cat_name_en: 'Sweets', revenue: 9000 }, { category: 'snack', cat_name_bn: 'নাস্তা', cat_name_en: 'Snacks', revenue: 4000 }],
  items: [{ item_id: 'i1', code: 'I-1', name_bn: 'রসগোল্লা', name_en: 'Rosogolla', qty: 10, revenue: 3000, cogs: 1800, abc: 'A' }, { item_id: 'i2', code: 'I-2', name_bn: 'সন্দেশ', name_en: 'Sandesh', qty: 5, revenue: 1500, cogs: 900, abc: 'A' }],
  daily: [TD, YD, dh(-2), dh(-9)].map((d, i) => ({ sale_date: d, location_id: 1, n: 10, revenue: 5000, discount: 0, void_n: 0, void_amt: 0, costed_rev: 5000, cogs: 3000 + i * 100 })),
  stockval: [{ category: 'sweet', cat_name_bn: 'মিষ্টি', cat_name_en: 'Sweets', items: 3, value: 12000 }, { category: 'raw', cat_name_bn: 'কাঁচামাল', cat_name_en: 'Raw material', items: 5, value: 8000 }],
  inc: { from: TD, to: TD, income: [], expense: [{ code: '5100', name_bn: 'ভাড়া', name_en: 'Rent', amount: 2000, is_group: false }, { code: '5200', name_bn: 'বিদ্যুৎ', name_en: 'Electricity', amount: 800, is_group: false }, { code: '5000', name_bn: 'বিক্রীত মালের খরচ', name_en: 'Cost of goods sold', amount: 9000, is_group: false }], total_income: 20000, total_expense: 11800, net_profit: 8200 },
  dues: [{ id: 'c1', name: 'test_user_a', balance: 1500, oldest: dh(-45) }, { id: 'c2', name: 'test_user_b', balance: 500, oldest: dh(-3) }],
  pay: [{ total_payable: 9000, suppliers_owed: 2, overdue: 2500, overdue_suppliers: 1, oldest: dh(-20), credit_total: 0 }],
  orders: [{ id: 1, channel: 'facebook' }, { id: 2, channel: 'facebook' }, { id: 3, channel: 'whatsapp' }],
  inbox: { on: true, new_count: 4 }, levels: [{ item_id: 'i0', below_min: true }, { item_id: 'i1', below_min: false }], expiry: [{ batch_id: 1, expired: false, hours_left: 5 }],
  grants: null, fail: [], slow: [],
});

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, pass = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } else pass++; };
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const EXTRA = `(function(){ var real = window.supabase.createClient; window.supabase.createClient = function () { var c = real.apply(null, arguments); var rpc = c.rpc, from = c.from; var OB = window.__OB || {};
   var clone = function (x) { return JSON.parse(JSON.stringify(x === undefined ? null : x)); };
   var miss = function (fn) { return { data: null, error: { message: 'Could not find the function public.' + fn + ' in the schema cache', code: 'PGRST202' } }; };
   c.rpc = async function (fn, args) {
    (window.__AC = window.__AC || []).push([fn, clone(args || {}), Date.now()]);
    if ((OB.fail || []).indexOf(fn) >= 0) return { data: null, error: { message: 'boom ' + fn } };
    if ((OB.slow || []).indexOf(fn) >= 0) return new Promise(function () {});
    if (fn === 'has_grant') { return { data: OB.grants === null || OB.grants === undefined ? true : OB.grants.indexOf(args.p_code) >= 0, error: null }; }
    if (fn === 'dash_layout_get') { if (OB.noServer) return miss(fn); var g = await window.__srv('get'); return g.error ? miss(fn) : { data: g, error: null }; }
    if (fn === 'dash_layout_save') { if (OB.noServer) return miss(fn); var s = await window.__srv('save', { layout: clone(args.p_layout) }); return s.error ? miss(fn) : { data: s, error: null }; }
    if (fn === 'sales_summary') return { data: clone(OB.sales), error: null };
    if (fn === 'biz_items_by_category') return { data: clone(OB.cat), error: null };
    if (fn === 'biz_items') return { data: clone(OB.items), error: null };
    if (fn === 'biz_daily') return { data: clone(OB.daily), error: null };
    if (fn === 'stock_valuation_by_category') return { data: clone(OB.stockval), error: null };
    if (fn === 'acct_income_statement') return { data: clone(OB.inc), error: null };
    if (fn === 'customer_dues') return { data: clone(OB.dues), error: null };
    if (fn === 'payables_summary') return { data: clone(OB.pay), error: null };
    if (fn === 'online_orders_list') return { data: clone(OB.orders), error: null };
    if (fn === 'inbox_board') return { data: clone(OB.inbox), error: null };
    if (fn === 'stock_levels') return { data: clone(OB.levels), error: null };
    if (fn === 'expiry_list') return { data: clone(OB.expiry), error: null };
    if (fn === 'ledger_problem_count') return { data: 2, error: null };
    if (fn === 'payments_summary') return { data: [], error: null };
    if (fn === 'cost_wait_list96') return { data: { total: 3 }, error: null };
    if (fn === 'drawer_report') return { data: { totals: { no_sale_open: 1 } }, error: null };
    return rpc(fn, args); };
   return c; }; })();`;
  const sweep = async (p) => { const H = await p.evaluate(() => document.documentElement.scrollHeight); for (let y = 0; y <= H; y += 500) { await p.evaluate((yy) => window.scrollTo(0, yy), y); await wait(p, 120); } await wait(p, 600); await p.evaluate(() => window.scrollTo(0, 0)); await wait(p, 300); };
  async function open(hash, o = {}) {
    const ctx = o.ctx || await br.newContext({ viewport: { width: o.w || 360, height: o.h || 780 }, hasTouch: !!o.touch });
    const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|PGRST|Could not find|status of 4|boom/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept());
    await p.exposeFunction('__srv', (op, a) => srvOp(op, a));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route('**/charts.js', (r) => r.fulfill({ contentType: 'text/javascript', body: REAL ? fs.readFileSync(_P.WEB_DIR + '/charts.js', 'utf8') + WRAP : FAKE }));
    const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
    T.rules = [R('ui_noperm_mode', 'lock')];
    T.exceptions = [{ id: 1, flag_code: 'x', level: 'red', status: 'open', amount: 1, entry_date: TD, created_at: TD + 'T10:00:00Z' }];
    T.production_runs = [{ id: 'p1', made_at: TD + 'T09:00:00+06:00', batches: 3, status: 'done', location_id: 1 }];
    await p.addInitScript(`${o.init ? o.init + ';' : ''}window.__DATA=${JSON.stringify(data)};window.__OB=${JSON.stringify(Object.assign(OBD(), o.ob || {}))};${o.owner === false ? 'window.__OWNER=false;' : ''}${o.cap ? 'window.__DX_CAP_MS=' + o.cap + ';' : ''}window.__DX_TTL_MS=${o.ttl === undefined ? 60000 : o.ttl};window.__DX_SAVE_MS=${o.saveMs || 500};try{if(!localStorage.getItem('bos_lang'))localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await wait(p, o.settle || 1800); if (/dashx/.test(hash) && !o.noSweep) await sweep(p); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => (window.__AC || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const renders = (p) => p.evaluate(() => (window.__CR || []).filter((c) => c.op === 'render').map((c) => ({ type: c.type, title: c.title, converted: !!c.spec.converted, spec: c.spec })));
  const order = (p) => p.evaluate(() => Array.from(document.querySelectorAll('#dx_grid .dx-t')).map((e) => e.dataset.m));
  const overflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1 && document.body.scrollWidth <= window.innerWidth + 1), 'horizontal overflow: ' + m);
  const focus = async (p, m) => { await p.evaluate((mm) => { const e = document.querySelector(`.dx-t[data-m=${mm}]`); window.scrollTo(0, e.getBoundingClientRect().top + window.scrollY - 60); }, m); await wait(p, 200); };
  const reset = () => { SRV.layout = null; SRV.updated = null; SRV.saves = []; SRV.gets = 0; SRV.missing = false; };

  // ================= 1. default layout renders (owner, 360px) =================
  reset(); let p = await open('#/dashx'); await sweep(p);
  ok(await p.locator('#dx_root').count() === 1, 'T1 dashboard route renders');
  let ord = await order(p);
  ok(ord.length === DEF && ord[0] === 'sales_total' && ord.includes('stock_value_cat') && ord.includes('expense_by_head') && ord.includes('dues_mix') && ord.includes('orders_by_channel') && ord.includes('alerts_overview'), 'T1 default layout has the 11 default tiles: ' + ord.join(','));
  ok(await p.locator('.dx-t[data-m=sales_total] .dx-kv').first().textContent().then((t) => /Tk [\d,]+/.test(t)).catch(() => false), 'T1 sales KPI shows a Tk value');
  const r0 = await renders(p);
  ok(r0.length >= 7, 'T1 chart tiles called B.charts.render (' + r0.length + ')');
  const types0 = r0.map((x) => x.type);
  ok(['line', 'donut', 'bar', 'treemap', 'pie', 'stacked_bar', 'column'].every((t) => types0.includes(t)), 'T1 default chart types used: ' + types0.join(','));
  ok(r0.every((x) => x.converted), 'T1 every render received the converted spec');
  ok(r0.some((x) => x.spec.slices && x.spec.slices.every((s) => s.label && s.value >= 0)) && r0.some((x) => x.spec.series && x.spec.hasFormat), 'T1 spec carries slices / series and a format function');
  ok((await calls(p, 'sales_summary')).length === 1, 'T1 one sales_summary call shared by every sales tile (got ' + (await calls(p, 'sales_summary')).length + ')');
  ok((await calls(p, 'biz_daily')).length === 1, 'T1 one biz_daily call');
  await overflow(p, 'default 360');
  ok(await p.evaluate(() => Array.from(document.querySelectorAll('#dx_root button')).filter((b) => b.offsetParent && !b.closest('.dx-ed,.dx-ch')).every((b) => { const r = b.getBoundingClientRect(); return r.height >= 40 && r.width >= 36; })), 'T1 touch targets >= 40px (buttons in view)');
  ok(await p.evaluate(() => Array.from(document.querySelectorAll('#dx_root input,#dx_root select')).every((e) => parseFloat(getComputedStyle(e).fontSize) >= 16)), 'T1 inputs are 16px');
  ok(await p.evaluate(() => document.querySelector('.dx-t[data-m=sales_total]').getBoundingClientRect().width < 200 && document.querySelector('.dx-t[data-m=sales_trend]').getBoundingClientRect().width > 300), 'T1 phone grid: S tile 1 column, M tile 2 columns');
  if (process.env.DX_SHOTS !== '0') { await p.evaluate(() => window.BOS_THEME.set('dark')); await wait(p, 500); await p.screenshot({ path: SP + '/dashx_dark_360.png', fullPage: true }); await p.evaluate(() => window.BOS_THEME.set('light')); await wait(p, 500); await p.screenshot({ path: SP + '/dashx_light_360.png', fullPage: true }); await p.evaluate(() => window.BOS_THEME.set('dark')); await wait(p, 300); }
  if (process.env.DX_ONLY === 'shots') { await br.close(); srv.close(); process.exit(0); }
  // the 4 period chips, shared by all tiles
  const s0 = (await calls(p, 'sales_summary')).length;
  await p.click('.dx-chip[data-v="30d"]'); await wait(p, 1500);
  const sc = await calls(p, 'sales_summary');
  ok(sc.length === s0 + 1 && sc[sc.length - 1].p_from < sc[0].p_from, 'T1b 30 days chip: ONE new batched sales call with an earlier from (' + sc.length + ')');
  ok(await p.locator('.dx-chip[aria-pressed=true]').getAttribute('data-v') === '30d', 'T1b chip active');
  await p.click('.dx-chip[data-v="custom"]'); await wait(p, 200);
  ok(await p.locator('#dx_cust:not([hidden])').count() === 1, 'T1b custom shows two date inputs');
  await p.fill('#dx_from', dh(-3)); await p.fill('#dx_to', dh(-1)); await p.dispatchEvent('#dx_to', 'change'); await wait(p, 1500);
  ok((await calls(p, 'biz_items_by_category')).some((c) => c.p_from === dh(-3) && c.p_to === dh(-1)), 'T1b custom range reaches the server calls');
  await p.selectOption('#dx_loc', { index: 1 }).catch(() => {}); await wait(p, 1200);
  ok((await calls(p, 'biz_daily')).some((c) => c.p_loc !== null), 'T1c location filter reaches calls (p_loc)');
  await p.close();

  // ================= 2. chart type switching, disabled types =================
  reset(); p = await open('#/dashx'); await sweep(p);
  const tileSel = '.dx-t[data-m=sales_by_cat]';
  const btns = await p.$$eval(tileSel + ' .dx-tb', (bs) => bs.map((b) => ({ v: b.dataset.v, off: b.getAttribute('aria-disabled') === 'true', on: b.getAttribute('aria-pressed') === 'true', title: b.title })));
  ok(btns.length === 10 && btns.map((b) => b.v).join() === 'line,area,bar,column,stacked_bar,pie,donut,treemap,gauge,bullet', 'T2 ten chart buttons in the contract order: ' + btns.map((b) => b.v).join());
  ok(btns.find((b) => b.v === 'donut').on && !btns.find((b) => b.v === 'pie').off && btns.find((b) => b.v === 'gauge').off && btns.find((b) => b.v === 'line').off, 'T2 slices data: pie enabled, gauge / line disabled, donut active');
  ok(/Not available/.test(btns.find((b) => b.v === 'gauge').title), 'T2 disabled button has a tooltip saying why: ' + btns.find((b) => b.v === 'gauge').title);
  const n0 = (await renders(p)).length;
  await p.click(tileSel + ' .dx-tb[data-v=gauge]', { force: true }); await wait(p, 300);
  ok((await renders(p)).length === n0, 'T2 clicking a disabled type does not render');
  ok(await p.locator(tileSel + ' .dx-tb[aria-pressed=true]').getAttribute('data-v') === 'donut', 'T2 disabled click leaves the active type');
  await p.click(tileSel + ' .dx-tb[data-v=pie]'); await wait(p, 400);
  const rr = await renders(p); const last = rr[rr.length - 1];
  ok(rr.length === n0 + 1 && last.type === 'pie' && last.converted && last.spec.slices.length === 2, 'T2 switching to pie renders the CONVERTED spec: ' + JSON.stringify(last && last.type));
  ok(await p.locator(tileSel + ' ' + FK).getAttribute('data-type') === 'pie', 'T2 chart host shows pie');
  const destroys = await p.evaluate(() => window.__CR.filter((c) => c.op === 'destroy').length); ok(destroys >= 1, 'T2 old instance destroyed');
  await wait(p, 900);
  ok(SRV.saves.length >= 1 && SRV.saves[SRV.saves.length - 1].tiles.find((t) => t.metric === 'sales_by_cat').type === 'pie', 'T2 type saved to the layout');
  // value metric: KPI + gauge + bullet
  await p.click('.dx-t[data-m=sales_total] .dx-tb[data-v=gauge]'); await wait(p, 300);
  const rg = (await renders(p)).pop(); ok(rg.type === 'gauge' && rg.spec.value > 0 && rg.spec.max > rg.spec.value, 'T2 KPI -> gauge renders with value / max');
  await p.click('.dx-t[data-m=sales_total] .dx-tb[data-v=kpi]'); await wait(p, 300);
  ok(await p.locator('.dx-t[data-m=sales_total] .dx-kv').count() === 1, 'T2 KPI button returns to the number');
  // target: used by gauge / bullet
  await p.click('.dx-t[data-m=sales_total] [data-act=dx_menu]'); await wait(p, 300);
  await p.fill('#dx_tg', '30000'); await p.click('[data-act=dx_mensave]'); await wait(p, 300);
  await p.click('.dx-t[data-m=sales_total] .dx-tb[data-v=bullet]'); await wait(p, 300);
  const rb = (await renders(p)).pop(); ok(rb.type === 'bullet' && rb.spec.target === 30000 && Array.isArray(rb.spec.ranges), 'T2 target + ranges reach the bullet spec');
  await p.close();

  // ================= 3. metric picker + cost secrecy =================
  reset(); p = await open('#/dashx');
  await p.click('[data-act=dx_add]'); await wait(p, 400);
  let pick = await p.locator('#sheet').innerText();
  ok(/Gross profit/.test(pick) && /Stock value by category/.test(pick) && /Total sales/.test(pick) && /Expenses by head/.test(pick), 'T3 owner picker lists sales, cost and accounts metrics');
  ok(await p.locator('#sheet .hsec').count() >= 5, 'T3 picker is grouped');
  await p.fill('#dx_q', 'channel'); await wait(p, 200); ok(await p.locator('#sheet .hrow').count() === 1, 'T3 picker search');
  await p.click('#sheet .hrow'); await wait(p, 1200);
  ok((await order(p)).length === DEF + 1 && (await order(p)).pop() === 'orders_by_channel', 'T3 add tile via picker (now ' + (await order(p)).length + ')');
  await p.click('[data-act=dx_add]'); await wait(p, 400);
  ok(await p.locator('#sheet').count() === 0 && (await order(p)).length === DEF + 1, 'T3 at 12 tiles the picker does not open (max 12)');
  await p.close();
  reset(); p = await open('#/dashx', { owner: false, init: NOCOSTP, ob: { grants: ['view_reports'] } });
  ord = await order(p);
  ok(ord.length > 0 && !ord.includes('gross_profit') && !ord.includes('stock_value_cat') && !ord.includes('expense_by_head'), 'T3 non-cost user: default layout has no cost / accounts tiles: ' + ord.join(','));
  await p.click('[data-act=dx_add]'); await wait(p, 400);
  pick = await p.locator('#sheet').innerText();
  ok(/Total sales/.test(pick) && !/Gross profit/.test(pick) && !/Stock value/.test(pick) && !/Cost of goods/.test(pick) && !/Net profit/.test(pick) && !/Expenses by head/.test(pick), 'T3 non-cost user: picker hides cost / profit / accounts metrics');
  for (const fn of ['biz_daily', 'stock_valuation_by_category', 'acct_income_statement', 'cost_wait_list96']) ok((await calls(p, fn)).length === 0, 'T3 cost source never called for a non-cost user: ' + fn);
  await p.close();
  // cost grant opens the cost metrics
  reset(); p = await open('#/dashx', { owner: false, init: NOCOSTP, ob: { grants: ['view_reports', 'view_cost'] } });
  await p.click('[data-act=dx_add]'); await wait(p, 400); pick = await p.locator('#sheet').innerText();
  ok(/Gross profit/.test(pick) && /Stock value by category/.test(pick) && !/Expenses by head/.test(pick), 'T3 cost-grant user: cost metrics shown, accounts metrics still hidden');
  await p.close();
  // a person with no report right is sent Home
  reset(); p = await open('#/dashx', { owner: false, init: NOCOSTP, ob: { grants: [] } });
  ok(await p.locator('#dx_root').count() === 0 && /#\/home|#\/?$/.test(await p.evaluate(() => location.hash)), 'T3 no report right: back to Home');
  await p.close();

  // ================= 4. drag and drop: MOUSE =================
  reset(); p = await open('#/dashx');
  ord = await order(p);
  const grip = async (m) => p.evaluate((mm) => { const r = document.querySelector(`.dx-t[data-m=${mm}] .dx-grip`).getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; }, m);
  const rect = async (m) => p.evaluate((mm) => { const r = document.querySelector(`.dx-t[data-m=${mm}]`).getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; }, m);
  await focus(p, 'sales_trend');
  const g1 = await grip('sales_trend'); const tgt = await rect('sales_by_cat');
  SRV.saves = [];
  await p.mouse.move(g1.x, g1.y); await p.mouse.down(); await p.mouse.move(g1.x + 3, g1.y + 8, { steps: 2 }); await p.mouse.move(g1.x + 20, g1.y + 40, { steps: 3 });
  ok(await p.locator('.dx-ph').count() === 1 && await p.locator('.dx-lift').count() === 1, 'T4 mouse drag: tile lifted with a placeholder');
  await p.mouse.move(tgt.x + tgt.w / 2, tgt.y + tgt.h - 8, { steps: 8 }); await wait(p, 100);
  await p.mouse.up(); await wait(p, 1500);
  const ord2 = await order(p);
  ok(ord2.indexOf('sales_trend') > ord2.indexOf('sales_by_cat') && ord2.join() !== ord.join() && ord2.length === DEF, 'T4 mouse drag reordered: ' + ord2.join(','));
  ok(await p.locator('.dx-ph, .dx-lift').count() === 0, 'T4 placeholder / lift removed after the drop');
  ok(SRV.saves.length === 1 && SRV.saves[0].tiles.map((t) => t.metric).join() === ord2.join(), 'T4 dash_layout_save called ONCE (debounced) with the new order (' + SRV.saves.length + ')');
  ok((await calls(p, 'dash_layout_save')).length === 1, 'T4 rpc dash_layout_save count = 1');
  // reload: the order comes back from the server
  await p.reload(); await wait(p, 1800); ok((await order(p)).join() === ord2.join(), 'T4 order restored after reload');
  await p.close();

  // ================= 5. drag and drop: TOUCH long-press (pointer events), haptics =================
  reset(); p = await open('#/dashx', { touch: true, init: 'window.__VIB=[];navigator.vibrate=function(n){window.__VIB.push(n);return true};' });
  ord = await order(p); await focus(p, 'sales_trend');
  const fire = (type, x, y, id) => p.evaluate(([t, xx, yy, pid]) => { const el = document.elementFromPoint(xx, yy) || document.body; const ev = new PointerEvent(t, { pointerId: pid, pointerType: 'touch', isPrimary: true, bubbles: true, cancelable: true, clientX: xx, clientY: yy }); el.dispatchEvent(ev); }, [type, x, y, id]);
  const t1 = await p.evaluate(() => { const r = document.querySelector('.dx-t[data-m=sales_by_cat] .dx-tt').getBoundingClientRect(); return { x: r.left + 10, y: r.top + r.height / 2 }; });
  // short move before 250 ms = a scroll, no drag
  await fire('pointerdown', t1.x, t1.y, 7); await fire('pointermove', t1.x, t1.y + 30, 7); await wait(p, 350); ok(await p.locator('.dx-lift').count() === 0, 'T5 moving before the long-press = no drag (page scroll)'); await fire('pointerup', t1.x, t1.y + 30, 7);
  // tap (no hold) still opens the picker
  SRV.saves = [];
  await fire('pointerdown', t1.x, t1.y, 8); await wait(p, 330);
  ok(await p.locator('.dx-lift').count() === 1 && await p.locator('.dx-ph').count() === 1, 'T5 held 250ms: the tile lifts');
  ok(await p.evaluate(() => window.__VIB.length >= 1), 'T5 haptic: navigator.vibrate called on lift');
  const tg2 = await rect('sales_trend'); await fire('pointermove', t1.x, t1.y - 6, 8);
  await fire('pointermove', tg2.x + 30, tg2.y + 12, 8); await wait(p, 100); await fire('pointerup', tg2.x + 30, tg2.y + 12, 8); await wait(p, 1500);
  const ord3 = await order(p);
  ok(ord3.indexOf('sales_by_cat') < ord3.indexOf('sales_trend') && ord3.join() !== ord.join(), 'T5 touch drag reordered: ' + ord3.join(','));
  ok(SRV.saves.length === 1, 'T5 one debounced save after the touch drop (' + SRV.saves.length + ')');
  ok(await p.locator('#sheet').count() === 0, 'T5 the release after a drag did not open a menu / picker');
  // auto-scroll near the bottom edge
  await focus(p, 'sales_trend');
  const t2 = await p.evaluate(() => { const r = document.querySelector('.dx-t[data-m=sales_by_cat] .dx-tt').getBoundingClientRect(); return { x: r.left + 10, y: r.top + r.height / 2 }; });
  await fire('pointerdown', t2.x, t2.y, 9); await wait(p, 330); await fire('pointermove', t2.x, 760, 9); await wait(p, 700);
  ok(await p.evaluate(() => window.scrollY) > 40, 'T5 auto-scroll near the bottom edge while dragging (scrollY ' + await p.evaluate(() => window.scrollY) + ')');
  await fire('pointerup', t2.x, 760, 9); await wait(p, 900);
  await p.close();

  // ================= 6. up / down buttons in Edit layout mode =================
  reset(); p = await open('#/dashx', { saveMs: 1500 });
  ok(!(await p.locator('.dx-t[data-m=sales_total] .dx-ed').isVisible()), 'T6 arrows hidden outside edit mode');
  await p.click('[data-act=dx_edit]'); await wait(p, 200);
  ok(await p.locator('.dx-t[data-m=sales_total] [data-act=dx_dn]').isVisible() && await p.locator('.dx-t[data-m=sales_total] [data-act=dx_up]').isDisabled(), 'T6 edit mode shows arrows; first tile has no "up"');
  ord = await order(p); SRV.saves = [];
  await p.locator('.dx-t[data-m=sales_total] [data-act=dx_dn]').click(); await wait(p, 200);
  ord2.length = 0; ord2.push(...await order(p));
  ok(ord2[1] === 'sales_total' && ord2[0] === ord[1], 'T6 down button moved the tile: ' + ord2.slice(0, 3).join());
  await p.locator('.dx-t[data-m=sales_total] [data-act=dx_up]').click(); await wait(p, 100);
  ok((await order(p)).join() === ord.join(), 'T6 up button moved it back');
  await p.locator('.dx-t[data-m=sales_total] [data-act=dx_dn]').click(); await p.locator('.dx-t[data-m=sales_total] [data-act=dx_dn]').click(); await wait(p, 2200);
  ok(SRV.saves.length === 1 && SRV.saves[0].tiles[2].metric === 'sales_total', 'T6 arrows: ONE debounced save with the final order (' + SRV.saves.length + ')');
  ok(await p.evaluate(() => document.getElementById('dx_sr').textContent.length > 0), 'T6 position announced for screen readers');
  // size, duplicate, remove, rename from the menu
  await p.click('.dx-t[data-m=sales_trend] [data-act=dx_menu]'); await wait(p, 300);
  await p.click('#sheet [data-act=dx_size][data-v=L]'); await wait(p, 300);
  ok(await p.locator('.dx-t[data-m=sales_trend]').getAttribute('data-size') === 'L', 'T6 menu: size L');
  await p.click('.dx-t[data-m=sales_trend] [data-act=dx_menu]'); await wait(p, 300);
  await p.fill('#dx_rn', 'My 7 day sales'); await p.click('[data-act=dx_mensave]'); await wait(p, 300);
  ok(/My 7 day sales/.test(await p.locator('.dx-t[data-m=sales_trend] .dx-tt').textContent()), 'T6 menu: rename');
  await p.click('.dx-t[data-m=sales_trend] [data-act=dx_menu]'); await wait(p, 300); await p.click('#sheet [data-act=dx_dup]'); await wait(p, 500);
  ok((await order(p)).filter((m) => m === 'sales_trend').length === 2, 'T6 menu: duplicate');
  await p.locator('.dx-t[data-m=sales_trend] >> nth=1').locator('[data-act=dx_rm]').click(); await wait(p, 300);
  ok((await order(p)).filter((m) => m === 'sales_trend').length === 1, 'T6 remove (edit bar)');
  await p.click('.dx-t[data-m=sales_trend] [data-act=dx_menu]'); await wait(p, 300); await p.click('#sheet [data-act=dx_full]'); await wait(p, 500);
  ok(await p.locator('#dx_full').count() === 1 && (await renders(p)).pop().spec.height >= 240, 'T6 full screen overlay renders a big chart');
  await p.click('[data-act=dx_fclose]'); ok(await p.locator('#dx_full').count() === 0, 'T6 full screen closes');
  // metric change from the tile title
  await p.click('.dx-t[data-m=sales_trend] .dx-ti'); await wait(p, 300);
  await p.click('#sheet [data-act=dx_setm][data-m=sales_by_pay]'); await wait(p, 1200);
  ok((await order(p)).includes('sales_by_pay') && !(await order(p)).includes('sales_trend'), 'T6 title -> picker changes the tile metric');
  ok((await renders(p)).pop().type === 'pie', 'T6 new metric starts with its default chart type');

  // ================= 7. reset to default =================
  await p.click('[data-act=dx_reset]'); await wait(p, 1600);
  ord = await order(p); ok(ord.length === DEF && ord[0] === 'sales_total' && ord[3] === 'sales_trend', 'T7 reset restores the default layout');
  ok(SRV.layout && SRV.layout.tiles[3].metric === 'sales_trend', 'T7 reset saved');
  await p.close();

  // ================= 8. fail-soft tiles =================
  reset(); p = await open('#/dashx', { ob: { fail: ['sales_summary', 'biz_items'] } });
  const nd = await p.locator('.dx-t[data-state=error] [data-state=nodata], .dx-t[data-state=error] .dx-nd').count();
  ok(nd >= 3 && /No data/.test(await p.locator('.dx-t[data-m=sales_total]').innerText()), 'T8 rpc error: sales tiles show "No data" (' + nd + ')');
  ok(await p.locator('.dx-t[data-m=sales_by_cat] ' + FK).count() === 1 && await p.locator('.dx-t[data-m=cust_dues] .dx-kv').count() === 1, 'T8 other tiles still render');
  ok(await p.locator('#dx_root').count() === 1 && (await order(p)).length === DEF, 'T8 page and layout intact');
  await p.click('.dx-t[data-m=sales_total] [data-act=dx_refresh]'); await wait(p, 600); ok((await calls(p, 'sales_summary')).length >= 2, 'T8 refresh button retries the source');
  await p.close();
  reset(); p = await open('#/dashx', { ob: { slow: ['biz_items_by_category'] }, cap: 400, settle: 1800 });
  ok(/No data/.test(await p.locator('.dx-t[data-m=sales_by_cat]').innerText()), 'T8 a call slower than the cap ends as "No data"');
  await p.close();
  reset(); p = await open('#/dashx', { ob: { noServer: true } });
  ok((await order(p)).length === DEF, 'T8 phase104 missing: dashboard works from this phone');
  await p.click('.dx-t[data-m=sales_total] .dx-tb[data-v=gauge]'); await wait(p, 1400);
  ok(await p.evaluate(() => /Saved on this phone only/.test(document.getElementById('dx_status').textContent)), 'T8 status says "Saved on this phone only"');
  ok(await p.evaluate(() => JSON.parse(localStorage.getItem('bos_dashx_u1')).tiles[0].type) === 'gauge', 'T8 local copy has the change');
  await p.close();

  // ================= 9. merge on load (server vs this phone) =================
  reset(); SRV.layout = { v: 1, period: '30d', loc: null, u: 5000, tiles: [{ id: 'a', metric: 'cust_dues', size: 'S', type: 'kpi' }, { id: 'b', metric: 'top_items', size: 'L', type: 'column', title: 'Mine' }] }; SRV.updated = new Date().toISOString();
  p = await open('#/dashx');
  ok((await order(p)).join() === 'cust_dues,top_items' && /Mine/.test(await p.locator('.dx-t[data-m=top_items] .dx-tt').textContent()) && await p.locator('.dx-chip[aria-pressed=true]').getAttribute('data-v') === '30d', 'T9 saved server layout is used (order, title, period)');
  ok((await renders(p))[0].type === 'column', 'T9 saved chart type used');
  await p.close();
  reset(); SRV.layout = { v: 1, period: '7d', loc: null, u: 1000, tiles: [{ id: 'a', metric: 'cust_dues', size: 'S', type: 'kpi' }] };
  p = await open('#/dashx', { init: `localStorage.setItem('bos_dashx_u1', JSON.stringify({v:1,period:'today',loc:null,u:Date.now()+1000,tiles:[{id:'z',metric:'voids',size:'S',type:'kpi'},{id:'y',metric:'bad_metric_x',size:'S',type:'kpi'}]}))` });
  await wait(p, 1200);
  ok((await order(p)).join() === 'voids' && SRV.saves.length === 1 && SRV.saves[0].tiles[0].metric === 'voids', 'T9 newer phone copy wins, unknown metric dropped, pushed to the server');
  await p.close();

  // ================= 10. English: no Bangla; Bangla mode shows Bangla; mix =================
  reset(); p = await open('#/dashx', { lang: 'en' });
  await p.click('.dx-t[data-m=sales_by_cat] [data-act=dx_menu]'); await wait(p, 300);
  const txt = await p.evaluate(() => document.body.innerText + ' ' + Array.from(document.querySelectorAll('[title],[aria-label]')).map((e) => (e.title || '') + ' ' + (e.getAttribute('aria-label') || '')).join(' '));
  ok(!BN.test(txt), 'T10 English mode: no Bangla on the dashboard / menu / tooltips' + (BN.test(txt) ? ' -> ' + (txt.match(/.{0,20}[ঀ-৿]+.{0,20}/) || [''])[0] : ''));
  await p.click('#sheet [data-act=closesheet]'); await wait(p, 200);
  await p.click('[data-act=dx_add]'); await wait(p, 300); ok(!BN.test(await p.locator('#sheet').innerText()), 'T10 English picker has no Bangla');
  await p.close();
  p = await open('#/dashx', { lang: 'bn' });
  ok(BN.test(await p.locator('.dx-hint').innerText()) && /Edit|সাজান/.test(await p.locator('[data-act=dx_edit]').innerText()), 'T10 Bangla mode shows Bangla text');
  await p.close();
  p = await open('#/dashx', { lang: 'mix' }); ok((await order(p)).length === DEF && /Layout|Tile/.test(await p.locator('.dx-act').innerText()), 'T10 mix mode renders (common words English)'); await p.close();
  for (const f of ['dashx', 'dashx_metrics']) {
    const s = fs.readFileSync(_P.WEB_DIR + '/' + f + '.js', 'utf8'); let n = 0, badn = 0;
    for (const m of s.matchAll(/\bL\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'/g)) { n++; if (BN.test(m[2])) { badn++; log('FAIL T10 L() english has Bangla: ' + m[2]); } }
    ok(n > 20 && badn === 0, `T10 ${f}.js: ${n} English strings, none with Bangla`); if (badn) bad++;
  }

  // ================= 11. blocked localStorage =================
  reset(); p = await open('#/dashx', { init: `Object.defineProperty(window,'localStorage',{get:function(){throw new Error('blocked')},configurable:true});` });
  ok((await order(p)).length === DEF, 'T11 localStorage blocked: dashboard still renders');
  await p.click('.dx-t[data-m=sales_by_cat] .dx-tb[data-v=pie]'); await wait(p, 1300);
  ok(SRV.saves.length === 1 && SRV.saves[0].tiles.find((t) => t.metric === 'sales_by_cat').type === 'pie', 'T11 blocked storage: the server copy still saves');
  await p.close();

  // ================= DEF. no overflow on phones and tablet; screenshots =================
  for (const [w, h] of [[360, 640], [412, 800], [820, 1100], [1100, 900]]) {
    reset(); p = await open('#/dashx', { w, h }); await overflow(p, 'width ' + w);
    if (w === 820 || w === 1100) { const cols = await p.evaluate(() => getComputedStyle(document.getElementById('dx_grid')).gridTemplateColumns.split(' ').length); ok(cols === (w === 820 ? 4 : 6), `T12 tablet ${w}: ${cols} columns`); }
    if (w === 820 && process.env.DX_SHOTS !== '0') await p.screenshot({ path: SP + '/dashx_dark_820.png' });
    await p.click('[data-act=dx_edit]'); await wait(p, 150); await overflow(p, 'edit mode ' + w);
    await p.click('.dx-t >> nth=0 >> [data-act=dx_menu]'); await wait(p, 300); await overflow(p, 'menu sheet ' + w);
    await p.close();
  }
  reset(); p = await open('#/dashx', { w: 360, h: 780, init: "try{localStorage.setItem('bos_theme','classic')}catch(e){}" }); await overflow(p, 'classic theme');
  if (process.env.DX_SHOTS !== '0') await p.screenshot({ path: SP + '/dashx_classic_360.png' }); await p.close();

  // ================= 13. leaving the screen aborts and destroys =================
  reset(); p = await open('#/dashx', { ttl: 0, ob: { slow: ['customer_dues'] } });
  const nr = await p.evaluate(() => window.__CR.filter((c) => c.op === 'render').length);
  await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 600);
  const nd2 = await p.evaluate(() => window.__CR.filter((c) => c.op === 'destroy').length);
  ok(nr > 0 && nd2 >= nr, `T13 leaving: every chart instance destroyed (${nd2}/${nr})`);
  ok(await p.locator('#dx_root').count() === 0, 'T13 dashboard gone');
  // ================= 14. Home link + route in the IA =================
  await wait(p, 600); ok(await p.locator('#dx_home, [data-act=dx_open]').count() >= 1, 'T14 Home shows the "Open dashboard" link for the owner');
  await p.click('[data-act=dx_open]'); await wait(p, 1500); ok(await p.locator('#dx_root').count() === 1, 'T14 the Home link opens #/dashx');
  ok(await p.evaluate(() => !!window.BOS.ia.byRoute('dashx')), 'T14 route registered in ia.js');
  await p.close();
  reset(); p = await open('#/home', { owner: false, init: NOCOSTP, ob: { grants: [] } }); await wait(p, 800); ok(await p.locator('#dx_home').count() === 0, 'T14 no link for a person without the report right'); await p.close();

  log('JS errors:', errors.length ? errors : 'none'); if (errors.length) bad++;
  log(`dashx_test: ${pass} passed, ${bad} failed` + (REAL ? ' (REAL charts.js)' : ' (fake charts)'));
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.error('DASHX TEST CRASH', e); srv.close(); process.exit(2); } })();
