// Bulk item editor (#/bulkitems) + old-item decision page (#/itemmap) + unpriced chip. Run: node bulkitems_test.js tests/web
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const base = dataFn(fs);
const R = (key, kind, def, extra = {}) => ({ key, module: 'settings', kind, value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1, ...extra });
function mkData() {
  const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
  T.rules = [R('vat_on', 'switch', false), R('barcode_camera_on', 'switch', false), R('barcode_device_on', 'switch', false), R('ui_noperm_mode', 'choice', 'lock')];
  T.option_lists = [{ list_code: 'units', value_code: 'kg', label_bn: 'কেজি', label_en: 'kg', sort: 1, active: true }, { list_code: 'units', value_code: 'piece', label_bn: 'পিস', label_en: 'piece', sort: 2, active: true },
    { list_code: 'units', value_code: 'box', label_bn: 'বক্স', label_en: 'box', sort: 3, active: true },
    { list_code: 'item_categories', value_code: 'c14', label_bn: '', label_en: 'Finished Goods Sweet', sort: 14, active: true, extra: { cat_no: '14' } },
    { list_code: 'item_categories', value_code: 'c15', label_bn: 'রিসেল', label_en: 'Resale', sort: 15, active: true, extra: { cat_no: '15' } }];
  T.item_types = [['finished_good', 'তৈরি পণ্য', 'Finished good'], ['resale', 'কিনে বিক্রি', 'Resale'], ['raw_material', 'কাঁচামাল', 'Raw material']].map(([code, bn, en], i) => ({ code, label_bn: bn, label_en: en, label_mix: en, count_in_business: true, sellable: code !== 'raw_material', active: true, sort: i + 1 }));
  T.item_class_map = [{ control_class: 'Finished Good', item_type: 'finished_good', active: true }];
  T.item_import_batches = [{ batch: 'dict-1' }];
  T.items.forEach((i) => Object.assign(i, { item_type: 'finished_good', count_in_business: true, sellable: true, hidden: false, locked: false, tracked: !!i.tracked, import_batch: null, master_code: null, retired_at: null, control_class: null }));
  T.items[0].locked = true;
  for (let n = 1; n <= 120; n++) {
    const code = '14-' + String(n).padStart(3, '0');
    T.items.push({ id: 'dict' + n, code, name_bn: 'ডিক ' + n, name_en: n === 5 ? '=SUM(1)' : 'Dict item ' + n, name_mix: null, category: 'c14', unit: 'kg', sell_price: n <= 20 ? 100 + n : null, wholesale_price: null, tracked: false, min_stock: null, is_active: true,
      item_type: n % 5 === 0 ? 'resale' : 'finished_good', count_in_business: true, sellable: true, hidden: false, locked: false, import_batch: 'dict-1', master_code: null, retired_at: null, control_class: 'Finished Good' });
  }
  const leg = T.items.filter((i) => !i.import_batch);
  T.item_mapping_review = leg.slice(0, 4).map((i, k) => ({ id: k + 1, item_id: i.id, suggested_code: '14-00' + (k + 1), confidence: [0.95, 0.9, 0.5, 0.3][k], auto_ok: k === 0, status: 'pending', note: null }));
  T.item_mapping_review[3].status = 'linked';
  T.item_costs = [{ item_id: leg[1].id, cost_price: 77 }];
  return data;
}
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc, from = c.from; window.__CALLS = []; const T = window.__DATA.tables;
 c.from = (name) => { if (name !== 'items') return from(name); const rows = T.items; let f = [], ord = null, rng = null, cnt = false, cols = null;
   const b = { select(c2, o) { cols = c2; if (o && o.count) cnt = true; return b; }, eq(k, v) { f.push((r) => r[k] === v); return b; }, in(k, arr) { f.push((r) => arr.includes(r[k])); return b; }, is(k, v) { f.push((r) => (r[k] === undefined || r[k] === null) === (v === null)); return b; },
     or(s) { const parts = s.split(',').map((x) => x.split('.')); f.push((r) => parts.some(([k, op, v]) => String(r[k] ?? '').toLowerCase().includes(v.replace(/%/g, '').toLowerCase()))); window.__OR = s; return b; },
     order(k) { ord = k; return b; }, range(a, z) { rng = [a, z]; return b; }, then(res, rej) { let o = rows.filter((r) => f.every((g) => g(r))); if (ord) o = [...o].sort((x, y) => (x[ord] > y[ord] ? 1 : -1)); const n = o.length; if (rng) o = o.slice(rng[0], rng[1] + 1); window.__CALLS.push(['items.select', { n: o.length, total: n }]); return Promise.resolve({ data: o, count: n, error: null }).then(res, rej); } };
   return b; };
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (fn === 'has_grant') return { data: window.__GRANT !== false, error: null };
  if (fn === 'items_bulk_apply') { const res = args.p_changes.map((r, i) => { const it = T.items.find((x) => x.id === r.item_id || x.code === r.code); const ch = {}; Object.keys(r).forEach((k) => { if (k !== 'item_id' && k !== 'code') ch[k] = [it ? it[k] : null, r[k]]; });
      if (!it) return { i: i + 1, item_id: null, code: r.code, status: 'error', reason: 'item_not_found', changes: {} };
      if (!args.p_dry && window.__OWNER !== false) Object.keys(ch).forEach((k) => { if (k === 'is_active' || k === 'hidden' || k === 'tracked' || k === 'sellable' || k === 'count_in_business') it[k] = r[k]; else if (k === 'reason') {} else it[k] = isNaN(Number(r[k])) ? r[k] : Number(r[k]); });
      return { i: i + 1, item_id: it.id, code: it.code, status: window.__OWNER === false ? 'requested' : 'ok', reason: null, changes: ch }; });
    return { data: { dry: args.p_dry, mode: window.__OWNER === false ? 'requests' : 'direct', rows: res.length, ok: window.__OWNER === false ? 0 : res.filter((x) => x.status === 'ok').length, requested: window.__OWNER === false ? res.length : 0, skipped: 0, error: res.filter((x) => x.status === 'error').length, results: res }, error: null }; }
  if (fn === 'option_update') { const r = T.option_lists.find((x) => x.list_code === args.p_list && x.value_code === args.p_value); r.label_bn = args.p_bn; return { data: { status: 'saved' }, error: null }; }
  if (fn === 'item_map_decide2') { const x = T.item_mapping_review.find((r) => r.item_id === args.p_item); const st = { link: 'linked', keep: 'rejected', later: 'later', undo: 'pending', use_dict: 'replaced' }[args.p_action]; x.status = st; if (args.p_action === 'use_dict') x.suggested_code = args.p_dict; return { data: { status: st }, error: null }; }
  if (fn === 'item_map_accept_confident') { return { data: { dry: args.p_dry, accepted: 2, skipped: 0, codes: ['I-001', 'I-002'] }, error: null }; }
  return rpc(fn, args); };
 return c; }; })();`;
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 1, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mkData())};${o.init || ''};try{localStorage.setItem('bos_lang','en');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1000); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__CALLS.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal page overflow ' + m);

  // ---------- owner grid ----------
  let p = await open({}, '#/bulkitems');
  const rows = await p.locator('#bk_grid tbody tr').count(); log('rows:', rows); ok(rows === 50, '50 rows per page (server paged)');
  ok(/177|\d+ total/.test(await p.textContent('#bk_count')), 'total count shown');
  await noOverflow(p, 'grid');
  const hdr = await p.locator('#bk_grid thead th').allTextContents(); ok(['Code', 'Name (Bangla)', 'Name (English)', 'Unit', 'Sell ৳', 'Wholesale ৳', 'Track stock', 'Min stock', 'Count in business', 'Sellable', 'Active'].every((h) => hdr.includes(h)), 'all columns: ' + hdr.join('|'));
  ok(!hdr.some((h) => /Cost/.test(h)), 'no cost column by default');
  await p.click('[data-act=bk_next]'); await p.waitForTimeout(300); ok((await p.textContent('#bk_pager')).includes('Page 2'), 'page 2'); await p.click('[data-act=bk_prev]'); await p.waitForTimeout(300);
  // filters (server side)
  await p.check('#bk_unpriced'); await p.waitForTimeout(400); const unp = (await calls(p, 'items.select')).pop(); log('unpriced total', unp.total); ok(unp.total === 100, 'unpriced filter -> 100 dictionary items');
  await p.uncheck('#bk_unpriced'); await p.waitForTimeout(300);
  await p.fill('#bk_q', 'Dict item 7'); await p.waitForTimeout(600); ok((await p.locator('#bk_grid tbody tr').count()) >= 1 && /ilike/.test(await p.evaluate(() => window.__OR || '')), 'search uses an ilike or() filter'); await p.fill('#bk_q', ''); await p.waitForTimeout(500);
  await p.selectOption('#bk_cat', 'c14'); await p.waitForTimeout(400); ok((await calls(p, 'items.select')).pop().total === 120, 'category filter'); await p.selectOption('#bk_cat', '');
  await p.selectOption('#bk_batch', 'dict-1'); await p.waitForTimeout(400); ok((await calls(p, 'items.select')).pop().total === 120, 'import-batch filter'); await p.selectOption('#bk_batch', ''); await p.waitForTimeout(300);
  ok((await p.locator('#bk_cat option').allTextContents()).filter((x) => /Old list/.test(x)).length === 5, 'five legacy categories labelled Old list');
  const catOpts = await p.locator('#bk_cat option').allTextContents(); ok(catOpts.indexOf('Resale') < catOpts.findIndex((x) => /Old list/.test(x)), 'dictionary categories sort before the Old list ones');
  // locked row is not editable
  await p.fill('#bk_q', 'I-001'); await p.waitForTimeout(600); ok(await p.locator('#bk_grid tbody tr').count() === 1 && await p.locator('#bk_grid tbody tr input.bk-cell').first().isDisabled(), 'locked item row is read-only'); await p.fill('#bk_q', ''); await p.waitForTimeout(500);
  // edit three cells -> one preview -> one apply
  await p.fill('#bk_q', '14-0'); await p.waitForTimeout(600);
  const r1 = p.locator('#bk_grid tbody tr').nth(25), id1 = await r1.getAttribute('data-row'); const r2 = p.locator('#bk_grid tbody tr').nth(26), id2 = await r2.getAttribute('data-row');
  await r1.locator('[data-f=sell_price]').fill('১২০'); await r1.locator('[data-f=unit]').selectOption('box'); await r2.locator('[data-f=tracked]').check(); await r2.locator('[data-f=min_stock]').fill('5');
  ok(/2 rows changed/.test(await p.textContent('#bk_n')), 'counter: 2 rows changed'); ok(await p.locator('#bk_grid .bk-cell.ed').count() === 4, 'four edited cells marked');
  ok((await calls(p, 'items_bulk_apply')).length === 0, 'nothing sent before Preview');
  await p.click('[data-act=bk_preview]'); await p.waitForTimeout(500);
  let bc = await calls(p, 'items_bulk_apply'); ok(bc.length === 1 && bc[0].p_dry === true && bc[0].p_batch === null && bc[0].p_changes.length === 2, 'Preview = one dry call with 2 rows');
  const c1 = bc[0].p_changes.find((x) => x.item_id === id1); ok(c1 && c1.sell_price === '120' && c1.unit === 'box', 'Bangla digits normalised, unit sent');
  ok(!bc[0].p_changes.some((x) => 'cost_price' in x), 'no cost column sent');
  ok(/Preview/.test(await p.textContent('.sheet h2')) && /2 will change/.test(await p.textContent('.sheet')), 'preview sheet'); await noOverflow(p, 'preview sheet');
  await p.click('[data-act=bk_apply]'); await p.waitForTimeout(600);
  bc = await calls(p, 'items_bulk_apply'); ok(bc.length === 2 && bc[1].p_dry === false && /^.{8,}-0$/.test(bc[1].p_batch), 'Apply = second call, dry false, client batch id: ' + (bc[1] && bc[1].p_batch));
  ok(/Done/.test(await p.textContent('.sheet h2')), 'done sheet'); await p.click('.sheet [data-act=closesheet]'); await p.waitForTimeout(200);
  ok(await p.locator('#bk_bar .bk-bar').count() === 0, 'edits cleared after apply');
  // select + hide
  await p.locator('.bk-sel').nth(3).check(); await p.locator('.bk-sel').nth(4).check(); ok(/2 selected/.test(await p.textContent('#bk_bar')), 'selection counter');
  await p.click('[data-act=bk_hide_sel]'); await p.waitForTimeout(400); bc = await calls(p, 'items_bulk_apply'); ok(bc[bc.length - 1].p_dry === true && bc[bc.length - 1].p_changes.length === 2 && bc[bc.length - 1].p_changes.every((x) => x.hidden === true), 'hide selected -> preview with hidden:true'); await p.click('.sheet [data-act=closesheet]');
  await p.click('[data-act=bk_inact_sel]'); await p.waitForTimeout(200); await p.click('[data-act=bk_inact_go]'); await p.waitForTimeout(200); ok(/Write the reason/.test(await p.textContent('#toast')), 'inactive needs a reason');
  await p.fill('#bk_reason', 'duplicate'); await p.click('[data-act=bk_inact_go]'); await p.waitForTimeout(400); bc = await calls(p, 'items_bulk_apply'); const lastb = bc[bc.length - 1]; ok(lastb.p_note === 'duplicate' && lastb.p_changes.every((x) => x.is_active === false && x.reason === 'duplicate'), 'inactive with reason'); await p.click('.sheet [data-act=closesheet]');
  // cost column: owner only, explicit
  await p.check('#bk_cost'); await p.waitForTimeout(500); ok((await p.locator('#bk_grid thead th').allTextContents()).some((h) => /Cost/.test(h)), 'owner can show the cost column');
  // export: no cost
  await p.uncheck('#bk_cost'); await p.waitForTimeout(300);
  const dl = p.waitForEvent('download'); await p.click('[data-act=bk_export]'); await dl; const csv = await p.evaluate(() => window.__LASTCSV);
  ok(/^﻿code,name_bn,name_en,category,item_type,unit,sell_price,wholesale_price,tracked,min_stock,count_in_business,sellable,is_active\n/.test(csv) && !/cost/i.test(csv.split('\n')[0]), 'export header has no cost column'); ok(csv.split('\n').length > 90 && csv.split('\n').slice(1).every((l) => l.startsWith('14-0')), 'export = ALL rows of the current filter (more than one page of 50): ' + csv.split('\n').length);
  ok(csv.includes(",'=SUM(1),") , 'export: a cell starting with = is prefixed with a quote (formula safety)');
  // CSV paste
  await p.click('[data-act=bk_tab][data-v=csv]'); await p.waitForTimeout(200);
  await p.fill('#bk_ta', 'code,price\n14-001,120\nbad,abc\n14-002,৯৫.৫,kg,yes,5\n14-003,,pc,no\nnope,1'); await p.click('[data-act=bk_csv_go]'); await p.waitForTimeout(500);
  ok(/lines not understood: 3/.test(await p.textContent('#bk_csvmsg')), 'bad line reported (line 3)');
  bc = await calls(p, 'items_bulk_apply'); const cb = bc[bc.length - 1]; ok(cb.p_dry === true && cb.p_changes.length === 4 && cb.p_changes[1].sell_price === '95.5' && cb.p_changes[1].tracked === true && cb.p_changes[1].min_stock === '5' && cb.p_changes[2].tracked === false && !('sell_price' in cb.p_changes[2]), 'CSV rows parsed: ' + JSON.stringify(cb.p_changes.slice(0, 3)));
  ok(/item_not_found|not found/i.test(await p.textContent('.sheet')) , 'unknown code shown as an error in the preview'); await p.click('.sheet [data-act=closesheet]');
  await p.click('[data-act=bk_tab][data-v=csv]'); await p.waitForTimeout(200);
  const nb = (await calls(p, 'items_bulk_apply')).length;
  await p.fill('#bk_ta', '14-001,10\n14-001,11'); await p.click('[data-act=bk_csv_go]'); await p.waitForTimeout(300); ok(/appears twice/.test(await p.textContent('#toast')) && (await calls(p, 'items_bulk_apply')).length === nb, 'duplicate codes in CSV refused before any call');
  await p.fill('#bk_ta', '14-001,0'); await p.click('[data-act=bk_csv_go]'); await p.waitForTimeout(300); ok(/lines not understood: 1/.test(await p.textContent('#bk_csvmsg')) && (await calls(p, 'items_bulk_apply')).length === nb, 'price 0 refused in CSV');
  // Bangla names
  await p.click('[data-act=bk_tab][data-v=bn]'); await p.waitForTimeout(200); ok(await p.locator('.bk-bn').count() === 1, 'one category needs a Bangla name (c14)');
  await p.fill('.bk-bn', 'তৈরি মিষ্টি'); await p.click('[data-act=bk_bn_save]'); await p.waitForTimeout(400); const ou = await calls(p, 'option_update'); ok(ou.length === 1 && ou[0].p_list === 'item_categories' && ou[0].p_value === 'c14' && ou[0].p_bn === 'তৈরি মিষ্টি' && ou[0].p_en === 'Finished Goods Sweet', 'option_update called with the label');
  ok(/Every category has a Bangla name/.test(await p.textContent('#bk_body')), 'list empty after saving');
  await p.close();

  // ---------- non-owner without a grant: requests ----------
  p = await open({ init: 'window.__OWNER=false;window.__GRANT=false;window.__PERMS={ITEMS:{view:true,enter:true}};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};' }, '#/bulkitems');
  ok(await p.locator('#bk_grid tbody tr').count() === 50, 'ITEMS-enter user sees the grid'); ok(await p.locator('[data-act=bk_export]').count() === 0, 'no export for non-owner'); ok(await p.locator('#bk_cost').count() === 0, 'no cost toggle for non-owner');
  await p.locator('#bk_grid tbody tr').nth(10).locator('[data-f=sell_price]').fill('55'); await p.locator('.bk-sel').nth(2).check(); ok(await p.locator('[data-act=bk_hide_sel]').count() === 0, 'no bulk hide without the direct right');
  await p.click('[data-act=bk_preview]'); await p.waitForTimeout(400); ok(/become requests|request/i.test(await p.textContent('.sheet')) && /1 will become requests/.test(await p.textContent('.sheet')), 'preview says requests for approval'); await p.close();
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:false}};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};window.__GRANT=false;' }, '#/bulkitems');
  ok(/do not have access/.test(await p.textContent('#app')), 'view-only user has no access'); await p.close();

  p = await open({ init: 'window.__OWNER=false;window.__GRANT=true;window.__PERMS={ITEMS:{view:true,enter:true}};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};window.__DATA.tables.item_mapping_review[0].status="replaced";' }, '#/itemmap');
  await p.click('[data-act=mp_tab][data-v=repl]'); await p.waitForTimeout(200);
  ok(await p.locator('.mp2').count() === 1 && await p.locator('[data-act=mp_undo]').count() === 0, 'non-owner sees a replaced row but no Undo button');
  await p.click('.mp2 .im-dots'); await p.waitForTimeout(200); ok(await p.locator('.sheet [data-act=mp_undo]').count() === 0, 'and no Undo in the menu'); await p.close();
  // ---------- old item decisions ----------
  p = await open({}, '#/itemmap');
  ok(/1 \/ 4 decided/.test(await p.textContent('#mp_prog')), 'progress counter 1 / 4'); ok(await p.locator('.mp2').count() === 3, 'three to decide');
  await noOverflow(p, 'itemmap');
  ok(/Link: the old item stays the sellable one, hide the dictionary twin/.test(await p.textContent('.mp2')), 'link action text');
  const c0 = p.locator('.mp2').first(); await c0.locator('[data-act=mp_link]').click(); await p.waitForTimeout(500);
  let dc = await calls(p, 'item_map_decide2'); ok(dc.length === 1 && dc[0].p_action === 'link' && dc[0].p_dict === '14-001', 'link calls item_map_decide2'); ok(/2 \/ 4 decided/.test(await p.textContent('#mp_prog')), 'progress moves to 2 / 4');
  await p.locator('.mp2').first().locator('[data-act=mp_later]').click(); await p.waitForTimeout(400); ok((await calls(p, 'item_map_decide2')).pop().p_action === 'later', 'decide later'); ok(/Later \(1\)/.test(await p.textContent('#app')), 'later tab count');
  await p.locator('.mp2').first().locator('[data-act=mp_keep]').click(); await p.waitForTimeout(400); ok((await calls(p, 'item_map_decide2')).pop().p_action === 'keep', 'keep separate');
  // use dictionary item: confirm sheet shows the effect
  await p.click('[data-act=mp_tab][data-v=later]'); await p.waitForTimeout(200);
  await p.locator('.mp2').first().locator('[data-act=mp_use]').click(); await p.waitForTimeout(300);
  const sh = await p.textContent('.sheet'); ok(/inactive/.test(sh) && /not deleted/.test(sh) && /undone/.test(sh) && /Data needed|৳/.test(sh), 'confirm sheet shows the effect'); await noOverflow(p, 'confirm sheet');
  ok((await calls(p, 'item_map_decide2')).filter((x) => x.p_action === 'use_dict').length === 0, 'nothing done before confirming');
  await p.click('[data-act=mp_use_do]'); await p.waitForTimeout(500); dc = await calls(p, 'item_map_decide2'); ok(dc.pop().p_action === 'use_dict', 'use_dict called after confirm');
  // undo
  await p.click('[data-act=mp_tab][data-v=repl]'); await p.waitForTimeout(200); await p.locator('.mp2').first().locator('[data-act=mp_undo]').click(); await p.waitForTimeout(400); ok((await calls(p, 'item_map_decide2')).pop().p_action === 'undo', 'undo');
  // search sheet
  await p.click('[data-act=mp_tab][data-v=todo]'); await p.waitForTimeout(200); await p.locator('.mp2').first().locator('[data-act=mp_find]').click(); await p.waitForTimeout(300);
  ok(await p.locator('#mp_fl .card').count() >= 1, 'search sheet lists dictionary items'); ok(/Suggested/.test(await p.textContent('#mp_fl .card')), 'suggested one first');
  await p.fill('#mp_fq', 'Dict item 9'); await p.waitForTimeout(300); ok((await p.locator('#mp_fl .card').count()) >= 1, 'search by name'); await p.click('.sheet [data-act=closesheet]');
  // three-dot menu and accept all
  await p.locator('.mp2 .im-dots').first().click(); await p.waitForTimeout(200); ok(await p.locator('.sheet .im-act').count() >= 4, 'three-dot menu has the actions'); await p.click('.sheet [data-act=closesheet]');
  await p.click('[data-act=mp_accept]'); await p.waitForTimeout(400); ok(/These old items will be linked: 2/.test(await p.textContent('.sheet')), 'accept-all shows the count first'); ok((await calls(p, 'item_map_accept_confident')).every((x) => x.p_dry === true), 'dry first');
  await p.click('[data-act=mp_accept_do]'); await p.waitForTimeout(400); ok((await calls(p, 'item_map_accept_confident')).pop().p_dry === false, 'then applied'); await p.close();

  // ---------- items list: unpriced chip and category labels ----------
  p = await open({}, '#/items');
  ok(/Unpriced finished goods \/ resale \(to price or hide\) · 100/.test(await p.textContent('#p2_fg')), 'chip with count 100');
  await p.click('#p2_fg'); await p.waitForTimeout(500); ok(/^100 /.test(await p.textContent('#p2_count')), 'chip filters the list to 100'); ok(await p.locator('[data-act=p2_fg_bulk]').count() === 1, 'link to the bulk editor');
  await p.click('[data-act=p2_fg_bulk]'); await p.waitForTimeout(700); ok(/bulkitems/.test(await p.evaluate(() => location.hash)), 'opens the bulk editor'); ok((await calls(p, 'items.select')).pop().total === 100, 'bulk editor opens with the unpriced preset');
  await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
