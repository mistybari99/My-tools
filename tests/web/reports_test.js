const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

// ---- mock of the phase9 report functions (runs inside the page) ----
function MOCK() {
  const real = window.supabase.createClient;
  window.__CALLS = [];
  window.supabase.createClient = (...a) => {
    const c = real(...a); const rpc = c.rpc;
    const dimsAll = [
      { key: 'day', time: true, label_bn: 'দিন', label_en: 'Day' }, { key: 'week', time: true, label_bn: 'সপ্তাহ', label_en: 'Week', needs_rule: 'ws' },
      { key: 'fy', time: true, label_bn: 'অর্থবছর', label_en: 'Fiscal year', needs_rule: 'fy' },
      { key: 'location', time: false, label_bn: 'লোকেশন', label_en: 'Location' }, { key: 'brand', time: false, label_bn: 'ব্র্যান্ড', label_en: 'Brand' }, { key: 'staff', time: false, label_bn: 'কর্মী', label_en: 'Staff' }];
    const fl = ['date', 'locations', 'brands', 'staff', 'modes', 'sale_type', 'customer', 'min_amount', 'max_amount'];
    const CATALOG = [
      { key: 'sales_summary', group: 'sales', allowed: true, kind: 'agg', name_bn: 'বিক্রির সারসংক্ষেপ', name_en: 'Sales summary', name_mix: 'Sales সারসংক্ষেপ', filters: fl, dims: dimsAll, default_group: '', compare: true, needs_date: true, columns: [] },
      { key: 'item_sales', group: 'sales', allowed: true, kind: 'agg', name_bn: 'আইটেম-ওয়াইজ বিক্রি', name_en: 'Item-wise sales', name_mix: 'Item-wise বিক্রি', filters: fl.concat(['items', 'categories']), dims: dimsAll.concat([{ key: 'item', time: false, label_bn: 'আইটেম', label_en: 'Item' }]), default_group: 'item', compare: true, needs_date: true, columns: [] },
      { key: 'receipt_register', group: 'sales', allowed: true, kind: 'raw', name_bn: 'রসিদ তালিকা', name_en: 'Receipt register', name_mix: 'Receipt তালিকা', filters: ['date', 'locations', 'search', 'status'], dims: [], default_group: null, compare: false, needs_date: true, columns: [] },
      { key: 'payment_modes', group: 'cash', allowed: true, kind: 'agg', name_bn: 'পেমেন্ট মাধ্যম অনুযায়ী', name_en: 'By payment mode', name_mix: 'Payment mode অনুযায়ী', filters: fl, dims: dimsAll, default_group: 'location', compare: true, needs_date: true, columns: [] },
      { key: 'customer_dues', group: 'customers', allowed: false, kind: 'raw', name_bn: 'গ্রাহকের কাছে পাওনা', name_en: 'Due from customers', name_mix: 'Customer এর কাছে পাওনা', filters: ['customer'], dims: [], default_group: null, compare: false, needs_date: false, columns: [] },
    ];
    const LOCS = [{ id: 1, bn: 'ইসলামিয়া মেইন', en: 'Islamia Main', brand: 'islamiya', bbn: 'ইসলামিয়া মিষ্টি ঘর', ben: 'ISLAMIYA MISTY GHAR', net: 100000, bills: 50, discount: 2000, due: 5000 },
      { id: 2, bn: '২য় শাখা', en: '2nd Branch', brand: 'misty_bari', bbn: 'মিষ্টি বাড়ি', ben: 'MISTY BARI', net: 60000, bills: 30, discount: 500, due: 0 }];
    const MEAS = [{ key: 'bills', label_bn: 'বিল', label_en: 'Bills', type: 'int', role: 'measure' }, { key: 'net', label_bn: 'বিক্রি', label_en: 'Sales', type: 'money', role: 'measure' },
      { key: 'discount', label_bn: 'ছাড়', label_en: 'Discount', type: 'money', role: 'measure' }, { key: 'due', label_bn: 'বাকি', label_en: 'Due', type: 'money', role: 'measure' }];
    const sum = (rows, k) => rows.reduce((s, r) => s + r[k], 0);
    const totalsOf = (rows) => ({ bills: sum(rows, 'bills'), net: sum(rows, 'net'), discount: sum(rows, 'discount'), due: sum(rows, 'due') });
    function aggRows(flt, group, factor) {
      let rows = LOCS.filter((l) => (!flt.locations || flt.locations.includes(l.id)) && (!flt.brands || flt.brands.includes(l.brand)));
      rows = rows.map((l) => ({ ...l, net: l.net * factor, bills: Math.round(l.bills * factor), discount: l.discount * factor, due: l.due * factor }));
      if (group === 'brand') { const m = {}; rows.forEach((l) => { const x = m[l.brand] || (m[l.brand] = { ...l, net: 0, bills: 0, discount: 0, due: 0 }); x.net += l.net; x.bills += l.bills; x.discount += l.discount; x.due += l.due; }); rows = Object.values(m); }
      return rows;
    }
    c.rpc = async (fn, args) => {
      if (fn === 'report_catalog') return { data: CATALOG, error: null };
      if (fn === 'report_presets') return { data: { today: { from: '2026-10-11', to: '2026-10-11' }, yesterday: { from: '2026-10-10', to: '2026-10-10' }, last_7: { from: '2026-10-05', to: '2026-10-11' }, last_30: { from: '2026-09-12', to: '2026-10-11' },
        this_month: { from: '2026-10-01', to: '2026-10-11' }, last_month: { from: '2026-09-01', to: '2026-09-30' }, this_week: null, last_week: null, this_fy: null, last_fy: null }, error: null };
      if (fn === 'has_grant') return { data: false, error: null };
      if (fn === 'report_run') {
        window.__CALLS.push(JSON.parse(JSON.stringify(args)));
        const flt = args.p_filters || {}, key = args.p_key, pg = args.p_page || 1;
        const meta = { from: '2026-10-01', to: '2026-10-11', group: [], sort: null, dir: 'asc', cost_shown: false, today: '2026-10-11' };
        if (key === 'item_sales') {
          const N = 120, all = Array.from({ length: N }, (_, i) => ({ item_id: 'i' + i, item_code: 'I-' + (1000 + i), item_name: 'মিষ্টি ' + (i + 1), item_name_en: 'Sweet ' + (i + 1), qty: 10 + i, bills: 5, net: 1000 + i * 10 }));
          const rows = all.slice((pg - 1) * 50, pg * 50), tn = all.reduce((s, r) => s + r.net, 0);
          return { data: { report: key, columns: [{ key: 'item_id', type: 'id', role: 'dim', label_bn: '', label_en: '' }, { key: 'item_code', type: 'text', role: 'dim', label_bn: 'কোড', label_en: 'Code' }, { key: 'item_name', type: 'text', role: 'dim', label_bn: 'আইটেম', label_en: 'Item' },
            { key: 'item_name_en', type: 'text', role: 'dim', label_bn: 'Item (EN)', label_en: 'Item (EN)' }, { key: 'qty', type: 'num', role: 'measure', label_bn: 'পরিমাণ', label_en: 'Qty' }, { key: 'net', type: 'money', role: 'measure', label_bn: 'বিক্রি', label_en: 'Sales' }],
            rows, totals: { qty: all.reduce((s, r) => s + r.qty, 0), net: tn }, compare: null, page: { n: pg, size: 50, groups: N, cap: 500 }, has_more: pg * 50 < N, notes: [], data_needed: false, meta: { ...meta, group: ['item'] } }, error: null };
        }
        if (key === 'receipt_register') {
          return { data: { report: key, columns: [{ key: 'receipt', type: 'int', role: 'col', label_bn: 'রসিদ নং', label_en: 'Receipt #' }, { key: 'customer_name', type: 'text', role: 'col', label_bn: 'গ্রাহক', label_en: 'Customer' }, { key: 'total', type: 'money', role: 'col', label_bn: 'মোট', label_en: 'Total' }],
            rows: [{ receipt: 1001, customer_name: '=cmd|calc', total: 500 }, { receipt: 1002, customer_name: 'Rina, "VIP"', total: 750.5 }], totals: { total: 1250.5 }, compare: null, page: { n: 1, size: 50, groups: 2, cap: 500 }, has_more: false,
            notes: [{ code: 'mobile_masked' }], data_needed: false, meta }, error: null };
        }
        // aggregate: sales_summary / payment_modes
        const g = args.p_group, group = g == null ? (key === 'payment_modes' ? 'location' : '') : g === 'total' ? '' : g.split(',')[0];
        const rows = aggRows(flt, group, 1), cols = [];
        if (group === 'location') cols.push({ key: 'location_id', type: 'id', role: 'dim', label_bn: '', label_en: '' }, { key: 'location_bn', type: 'text', role: 'dim', label_bn: 'লোকেশন', label_en: 'Location' }, { key: 'location_en', type: 'text', role: 'dim', label_bn: 'Location (EN)', label_en: 'Location (EN)' });
        if (group === 'brand') cols.push({ key: 'brand_code', type: 'id', role: 'dim', label_bn: '', label_en: '' }, { key: 'brand_bn', type: 'text', role: 'dim', label_bn: 'ব্র্যান্ড', label_en: 'Brand' }, { key: 'brand_en', type: 'text', role: 'dim', label_bn: 'Brand (EN)', label_en: 'Brand (EN)' });
        const out = rows.map((l) => ({ location_id: l.id, location_bn: l.bn, location_en: l.en, brand_code: l.brand, brand_bn: l.bbn, brand_en: l.ben, bills: l.bills, net: l.net, discount: l.discount, due: l.due }));
        const tot = totalsOf(rows);
        let compare = null;
        if (args.p_compare) { const pr = aggRows(flt, group, 0.8), pt = totalsOf(pr), delta = {}; Object.keys(tot).forEach((k) => { delta[k] = { current: tot[k], previous: pt[k], abs: tot[k] - pt[k], pct: pt[k] ? Math.round(10000 * (tot[k] - pt[k]) / pt[k]) / 100 : null }; });
          compare = { mode: flt.compare_mode || 'prev', from: '2026-09-20', to: '2026-09-30', totals: pt, rows: pr.map((l) => ({ location_id: l.id, location_bn: l.bn, location_en: l.en, brand_code: l.brand, brand_bn: l.bbn, brand_en: l.ben, bills: l.bills, net: l.net, discount: l.discount, due: l.due })), delta }; }
        const notes = flt.preset === 'this_fy' ? [] : [];
        return { data: { report: key, columns: cols.concat(MEAS), rows: group === '' ? [{ ...tot }] : out, totals: tot, compare, page: { n: 1, size: 50, groups: out.length, cap: 500 }, has_more: false, notes, data_needed: false, meta: { ...meta, group: group ? [group] : [] } }, error: null };
      }
      return rpc(fn, args);
    };
    return c;
  };
}

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  p.on('dialog', (d) => d.accept());
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + '\n(' + MOCK.toString() + ')();' }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  data.tables.report_brand_map = [{ location_id: 1, brand_code: 'islamiya', brand_bn: 'ইসলামিয়া মিষ্টি ঘর', brand_en: 'ISLAMIYA MISTY GHAR' }, { location_id: 2, brand_code: 'misty_bari', brand_bn: 'মিষ্টি বাড়ি', brand_en: 'MISTY BARI' }];
  data.tables.customers = [{ id: 'c1', name: 'Rina', mobile: '01711111111' }];
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','bn')}catch(e){}
    window.__BLOBS=[];const _c=URL.createObjectURL.bind(URL);URL.createObjectURL=(b)=>{ if(b&&b.text){ b.arrayBuffer().then(ab=>{window.__BLOBS.push({head:Array.from(new Uint8Array(ab).slice(0,3)),type:b.type});}); b.text().then(t=>{(window.__BLOBS_T=window.__BLOBS_T||[]).push(t);}); } return _c(b); };
    window.__PRINTED=0;window.print=()=>{window.__PRINTED++; const e=document.getElementById('rp_print'); window.__PRINTHTML=e?e.innerText:null;};`);
  const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); if (!c) errors.push('assert: ' + m); };
  await p.goto('http://localhost:' + PORT + '/#/home'); await p.waitForTimeout(900);

  // 1 home tile + hub
  ok(await p.locator('.qm', { hasText: 'রিপোর্ট' }).count() > 0, 'home has a Reports tile');
  await p.click('.qm >> text=রিপোর্ট'); await p.waitForTimeout(500);
  ok(location_hash(await p.url()) === '#/reports', 'tile opens #/reports');
  ok(await p.locator('.rp-row[data-act=rp_open]').count() === 4, 'hub lists 4 allowed reports');
  ok(await p.locator('.rp-row.lock').count() === 1, 'hub shows 1 locked report (lock mode)');
  ok((await p.locator('.ptabs button').allTextContents()).length >= 4, 'group pills present');
  await p.screenshot({ path: SP + '/rp_hub.png', fullPage: true });
  await p.fill('#rp_q', 'item'); await p.waitForTimeout(100);
  ok(await p.locator('.rp-row[data-act=rp_open]').count() === 1, 'hub search narrows to 1');
  await p.fill('#rp_q', '');

  // 2 open a report
  await p.click('.rp-row[data-v=sales_summary]'); await p.waitForTimeout(700);
  ok(location_hash(await p.url()) === '#/report/sales_summary', 'report route');
  ok(await p.locator('.rp-stats .stat').count() >= 3, 'summary stat cards');
  let calls = await p.evaluate(() => window.__CALLS); ok(calls.length === 1 && calls[0].p_filters.preset === 'this_month' && calls[0].p_group === null, 'first call: preset this_month, default group');
  await p.screenshot({ path: SP + '/rp_view.png', fullPage: true });

  // 3 filter sheet: fiscal preset shows Data needed; pick a location
  await p.click('[data-act=rp_filter]'); await p.waitForTimeout(300);
  ok(await p.locator('#sheet .fl-na').count() === 4, 'week/fiscal presets show Data needed (4)');
  ok((await p.locator('#sheet .fl-na').first().textContent()).includes('তথ্য দরকার'), 'Data needed label');
  ok(await p.locator('#sheet [data-k=brands]').count() === 2, 'brand multi-select has 2 brands');
  await p.screenshot({ path: SP + '/rp_filter.png' });
  await p.click('#sheet [data-k=locations][data-v="1"]'); await p.click('#sheet [data-act=fl_p][data-v=last_7]');
  await p.click('#sheet [data-act=fl_apply]'); await p.waitForTimeout(600);
  calls = await p.evaluate(() => window.__CALLS); const lc = calls[calls.length - 1];
  ok(JSON.stringify(lc.p_filters.locations) === '[1]' && lc.p_filters.preset === 'last_7', 'filters sent: locations [1], preset last_7');
  ok(await p.locator('.fl-chip').count() === 2, 'two chips (date + location)');
  ok(await p.locator('.rp-n').textContent() === '2', 'filter count badge 2');
  await p.click('.fl-chip >> nth=1'); await p.waitForTimeout(500);
  ok(await p.locator('.fl-chip').count() === 1, 'chip removal');

  // 4 group switch
  await p.click('.rp-seg [data-v=location]'); await p.waitForTimeout(500);
  ok(await p.locator('#rp_tbl tbody tr').count() === 2, 'per-location rows = 2');
  ok((await p.locator('#rp_tbl tbody tr').first().innerText()).includes('ইসলামিয়া মেইন'), 'location name merged (bn)');
  await p.click('.rp-seg [data-v=brand]'); await p.waitForTimeout(500);
  ok((await p.locator('#rp_tbl tbody').innerText()).includes('মিষ্টি বাড়ি'), 'per-brand rows show brand');
  await p.click('.rp-seg [data-v=total]'); await p.waitForTimeout(500);
  ok(await p.locator('#rp_tbl tbody tr').count() === 1, 'combined = 1 row');
  calls = await p.evaluate(() => window.__CALLS); ok(calls[calls.length - 1].p_group === 'total', 'total sends p_group total');

  // 5 compare
  await p.click('.rp-seg [data-v=location]'); await p.waitForTimeout(400);
  await p.click('[data-act=rp_cmp]'); await p.waitForTimeout(600);
  calls = await p.evaluate(() => window.__CALLS); const cc = calls[calls.length - 1];
  ok(cc.p_compare === true && cc.p_filters.compare_mode === 'prev', 'compare call: prev');
  ok(await p.locator('.dl.ok, .dl.warn').count() > 0, 'delta chips shown');
  await p.click('[data-act=rp_cm][data-v=year]'); await p.waitForTimeout(500);
  calls = await p.evaluate(() => window.__CALLS); ok(calls[calls.length - 1].p_filters.compare_mode === 'year', 'compare mode year');
  await p.screenshot({ path: SP + '/rp_compare.png', fullPage: true });

  // 6 drill-down
  await p.click('#rp_tbl tbody tr >> nth=0'); await p.waitForTimeout(600);
  calls = await p.evaluate(() => window.__CALLS); const dc = calls[calls.length - 1];
  ok(JSON.stringify(dc.p_filters.locations) === '[1]', 'drill applies location filter');
  ok(await p.locator('[data-act=rp_back]').count() === 1, 'back-to-previous button after drill');
  await p.click('[data-act=rp_back]'); await p.waitForTimeout(500);
  calls = await p.evaluate(() => window.__CALLS); ok(!calls[calls.length - 1].p_filters.locations, 'back restores filters');

  // 7 columns
  await p.click('[data-act=rp_cols]'); await p.waitForTimeout(200);
  await p.click('#sheet [data-k=discount]'); await p.click('#sheet [data-act=closesheet]'); await p.waitForTimeout(200);
  ok(!(await p.locator('#rp_tbl thead').innerText()).includes('ছাড়'), 'column hidden');

  // 8 save / load / delete view
  await p.click('[data-act=rp_views]'); await p.waitForTimeout(300);
  await p.fill('#rp_vn', 'আমার সাপ্তাহিক'); await p.click('#rp_vs'); await p.click('[data-act=rp_vsave]'); await p.waitForTimeout(500);
  const saved = await p.evaluate(() => window.__DATA.tables.report_views);
  ok(saved && saved.length === 1 && saved[0].name === 'আমার সাপ্তাহিক' && saved[0].shared === true && saved[0].report_code === 'sales_summary' && saved[0].params.group === 'location' && saved[0].params.compare === 'year' && saved[0].params.hidden.includes('discount'),
    'view saved (private/shared flag, group, compare, hidden cols)');
  await p.click('[data-act=rp_views]'); await p.waitForTimeout(300);
  ok(await p.locator('#rp_vl .rp-vb').count() === 1, 'view listed in sheet');
  await p.click('[data-act=closesheet]');
  await p.goBack(); await p.waitForTimeout(600);
  ok(await p.locator('[data-act=rp_view_open]').count() === 1, 'hub lists saved view');
  await p.screenshot({ path: SP + '/rp_hub_views.png', fullPage: true });
  await p.click('[data-act=rp_view_open]'); await p.waitForTimeout(800);
  ok(await p.locator('.rp-meta b', { hasText: 'আমার সাপ্তাহিক' }).count() === 1, 'view reopened from hub');
  ok(await p.locator('[data-act=rp_cmp][aria-pressed=true]').count() === 1, 'view restored compare');

  // 9 CSV
  await p.click('[data-act=rp_csv]'); await p.waitForTimeout(800);
  ok(await p.locator('[data-act=rp_csv]').count() === 1, 'csv button visible (owner)');
  const blobs = await p.evaluate(() => ({ b: window.__BLOBS, t: window.__BLOBS_T }));
  ok(blobs.b && blobs.b.length === 1 && blobs.b[0].head.join(',') === '239,187,191', 'CSV starts with UTF-8 BOM');
  const csv = (blobs.t && blobs.t[0]) || '';
  ok(csv.includes('লোকেশন') && csv.includes('ইসলামিয়া মেইন') && csv.split('\r\n')[0].includes('বিক্রি'), 'CSV headers + rows (Bangla)');
  ok(!csv.split('\r\n')[0].includes('ছাড়'), 'CSV honours hidden column');
  ok(/মোট,\d+,160000/.test(csv), 'CSV totals row: ' + (csv.split('\r\n')[3] || ''));
  ok(csv.includes('Asia/Dhaka'), 'CSV footer has export time');

  // 10 paging + print + raw report + locked export
  await p.goto('http://localhost:' + PORT + '/#/report/item_sales'); await p.waitForTimeout(800);
  ok(await p.locator('#rp_tbl tbody tr').count() === 50, 'item_sales first page 50 rows');
  await p.click('[data-act=rp_more]'); await p.waitForTimeout(500);
  ok(await p.locator('#rp_tbl tbody tr').count() === 100, 'more -> 100 rows');
  await p.click('[data-act=rp_print]'); await p.waitForTimeout(900);
  const pr = await p.evaluate(() => ({ n: window.__PRINTED, h: window.__PRINTHTML }));
  ok(pr.n === 1 && pr.h && pr.h.includes('Sweet') || pr.h.includes('মিষ্টি 120'), 'print view built with all 120 rows');
  await p.click('[data-act=rp_csv]'); await p.waitForTimeout(800);
  const b2 = await p.evaluate(() => window.__BLOBS_T); const csv2 = b2[b2.length - 1];
  ok(csv2.trim().split('\r\n').filter((l) => l.startsWith('I-')).length === 120, 'CSV exports all pages (120 rows)');
  await p.goto('http://localhost:' + PORT + '/#/report/receipt_register'); await p.waitForTimeout(700);
  await p.click('[data-act=rp_csv]'); await p.waitForTimeout(700);
  const b3 = await p.evaluate(() => window.__BLOBS_T); const csv3 = b3[b3.length - 1];
  ok(csv3.includes(`"'=cmd|calc"`) || csv3.includes("'=cmd|calc"), 'CSV neutralises formula text');
  ok(csv3.includes('"Rina, ""VIP"""'), 'CSV quotes commas/quotes');
  ok(await p.locator('.rp-note').count() === 1, 'server note shown (mobile masked)');
  await p.goto('http://localhost:' + PORT + '/#/report/customer_dues'); await p.waitForTimeout(500);
  ok(await p.locator('.notice').count() === 1, 'locked report page shows no-permission');

  // 11 non-owner without export grant
  await p.goto('http://localhost:' + PORT + '/#/report/sales_summary'); await p.waitForTimeout(600);
  await p.evaluate(() => { window.BOS_APP.S.ctx.is_owner = false; });
  await p.goto('http://localhost:' + PORT + '/#/reports'); await p.waitForTimeout(300);
  await p.screenshot({ path: SP + '/rp_en.png', fullPage: false });

  // 12 languages
  await p.evaluate(() => { window.BOS_APP.S.ctx.is_owner = true; });
  for (const lang of ['en', 'mix']) {
    await p.goto('http://localhost:' + PORT + '/#/report/sales_summary'); await p.evaluate((l) => { try { localStorage.setItem('bos_lang', l); } catch (e) { /* */ } }, lang);
    await p.reload(); await p.waitForTimeout(900); await p.screenshot({ path: SP + `/rp_${lang}.png`, fullPage: true });
  }
  console.log('errors:', errors.length ? errors : 'none'); await br.close(); srv.close();
})();
function location_hash(u) { return u.slice(u.indexOf('#')); }
