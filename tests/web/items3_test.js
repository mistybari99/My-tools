// Products carry-over (phase12): details field, costs for view_cost-only people, real low-stock status. Run: node items3_test.js <dir with smoke.js, stub.js>
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const base = dataFn(fs);
const R = (key, kind, def, extra = {}) => ({ key, module: 'settings', kind, value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1, ...extra });
function mkData(o = {}) {
  const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
  T.rules = [R('vat_on', 'switch', false, o.vat ? { value: true } : {}), R('barcode_camera_on', 'switch', false), R('barcode_device_on', 'switch', false, o.dev ? { value: true } : {}), R('ui_noperm_mode', 'choice', 'lock')];
  T.option_lists = [{ list_code: 'units', value_code: 'kg', label_bn: 'কেজি', label_en: 'kg', sort: 1, active: true }, { list_code: 'units', value_code: 'piece', label_bn: 'পিস', label_en: 'piece', sort: 2, active: true },
    { list_code: 'units', value_code: 'box', label_bn: 'বক্স', label_en: 'box', sort: 3, active: true }, { list_code: 'units', value_code: 'gram', label_bn: 'গ্রাম', label_en: 'gram', sort: 4, active: true },
    { list_code: 'item_categories', value_code: 'packed', label_bn: 'প্যাকেটজাত', label_en: 'Packed', sort: 1, active: true }, { list_code: 'item_subcategories', value_code: 'syrup', label_bn: 'সিরাপ', label_en: 'Syrup', sort: 1, active: true }];
  const it = T.items; Object.assign(it[0], { barcode: '8901', min_stock: 5, tracked: true, wholesale_price: 240, source: 'made', sub_category: 'syrup', images: ['ITEMS/1/x.jpg'], sell_units: ['kg'], base_unit: 'kg' });
  Object.assign(it[1], { is_active: false, source: 'bought' }); Object.assign(it[2], { source: 'bought', barcode: '8902' });
  T.unit_conversions = [{ id: 1, item_id: null, from_unit: 'kg', to_unit: 'gram', factor: 1000, active: true }, { id: 2, item_id: it[0].id, from_unit: 'box', to_unit: 'kg', factor: 2, active: true }];
  T.suppliers = [{ id: 'sp1', name: 'Dudh Ghor', type_code: 'milk', active: true }, { id: 'sp2', name: 'Chini Mill', type_code: 'sugar', active: true }];
  return data;
}
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const GIF = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = []; window.__UP = []; const T = window.__DATA.tables;
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (fn === 'supplier_pick') return { data: T.suppliers.filter((s) => s.active).map((s) => ({ id: s.id, name: s.name, type_code: s.type_code })), error: null };
  if (fn === 'has_grant') return { data: window.__GRANT !== false, error: null };
  if (fn === 'stock_levels') return window.__NOLEVELS ? { data: null, error: { message: 'could not find the function' } } : { data: (window.__LOW || []), error: null };
  if (fn === 'items_with_cost') return { data: window.__COSTS || [], error: null };
  if (fn === 'save_supplier') { const id = 'sp' + (T.suppliers.length + 1); T.suppliers.push({ id, active: true, ...args.p_patch }); return { data: id, error: null }; }
  if (fn === 'submit_item_change') { if (window.__DUP) return { data: null, error: { message: 'duplicate key value violates unique constraint items_barcode_uq' } }; return { data: { status: window.__OWNER === false ? 'pending' : 'applied' }, error: null }; }
  return rpc(fn, args); };
 c.storage = { from: () => ({ upload: async (p, b) => { window.__UP.push([p, b.size, b.type]); return { error: null }; },
   createSignedUrls: async (ps) => ({ data: ps.map((p) => ({ path: p, signedUrl: '${GIF}' })), error: null }), createSignedUrl: async () => ({ data: { signedUrl: '${GIF}' }, error: null }) }) };
 return c; }; })();`;
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mkData(o))};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(900); return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const calls = (p, fn) => p.evaluate((f) => window.__CALLS.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const IT = base.tables.items, id0 = IT[0].id;
  const LOW = `window.__LOW=[{item_id:"${id0}",code:"${IT[0].code}",name_bn:"x",category:"c",base_unit:"kg",location_id:1,qty:2.5,min_stock:5,below_min:true}];`;
  const NO = 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:true,approve:false}};window.__PROFILE={id:"u3",staff_id:"testf02",full_name:"TestF",status:"active",lang:"en"};';

  // ---------- low stock now ----------
  let p = await open({ init: LOW }, '#/items');
  ok(await p.locator('.p2-row.warn').count() === 1, 'one row carries the low-stock edge marker (only the item below its minimum)');
  ok(/Low stock now · 2\.5 kg/.test(await p.textContent('.p2-row.warn')), 'chip says low stock with the quantity from the ledger');
  ok(await p.locator('.p2-row .chip:has-text("Alert ≤")').count() >= 1, 'the old "alert is set" chip still shows on items with a minimum');
  await p.click('#p2_fb'); await p.waitForTimeout(250); ok(await p.locator('#ff_lownow').count() === 1, 'Low stock now switch in the filter sheet'); await p.screenshot({ path: SP + '/it3_filter.png' }); await noOverflow(p, 'filter');
  await p.click('#ff_lownow'); await p.click('[data-act=p2_apply]'); await p.waitForTimeout(250);
  ok(await p.locator('.p2-row').count() === 1, 'filter: only the low item'); ok((await p.textContent('#p2_fb .cnt')) === '1' && /Low stock now/.test(await p.textContent('#p2_chips')), 'badge + chip');
  await p.click('#p2_chips .chip'); await p.waitForTimeout(250); ok(await p.locator('.p2-row').count() > 1, 'chip removes the filter');
  const lc = await calls(p, 'stock_levels'); ok(lc.length >= 1 && lc[0].p_filters.below_min === true, 'asks the stock ledger (stock_levels, below_min) - no numbers computed here');
  await p.close();
  p = await open({}, '#/items'); ok(await p.locator('.p2-row.warn').count() === 0, 'nothing below minimum: no marker (no minimum = no flag)'); await p.click('#p2_fb'); await p.waitForTimeout(200); ok(await p.locator('#ff_lownow').count() === 1, 'switch stays when the ledger answers'); await p.close();
  p = await open({ init: 'window.__NOLEVELS=true;' }, '#/items'); await p.click('#p2_fb'); await p.waitForTimeout(200); ok(await p.locator('#ff_lownow').count() === 0 && await p.locator('.p2-row.warn').count() === 0, 'stock part missing: no low-stock UI at all'); await p.close();

  // ---------- costs for view_cost-only ----------
  const COSTS = `window.__COSTS=[{item_id:"${id0}",cost_price:150}];`;
  p = await open({ init: NO + COSTS }, '#/items');
  ok(/Cost ৳ 150/.test(await p.textContent('.p2-row >> nth=0')), 'view_cost holder sees the cost on the list (through items_with_cost)'); ok((await calls(p, 'items_with_cost')).length === 1, 'the RPC was used');
  ok(await p.locator('.p2-row:has-text("Cost")').count() === 1, 'only items that have a cost row show one');
  await p.click('.p2-row >> nth=0'); await p.waitForTimeout(600); ok(await p.locator('#p_cost').count() === 1 && await p.locator('#p_cost').getAttribute('readonly') !== null && (await p.inputValue('#p_cost')) === '150', 'cost field is read-only for them');
  await p.fill('#p_sell', '321'); await p.click('[data-act=p2_save]'); await p.waitForTimeout(500); const np = (await calls(p, 'submit_item_change'))[0].p_patch; ok(!('cost_price' in np) && np.sell_price === 321, 'saving never sends the cost'); await p.close();
  p = await open({ init: NO + COSTS + 'window.__GRANT=false;' }, '#/items'); ok(!/Cost/.test(await p.textContent('#p2_list')) && (await calls(p, 'items_with_cost')).length === 0, 'without view_cost: no cost, RPC not even called'); await p.close();
  p = await open({ init: COSTS }, '#/items'); ok((await calls(p, 'items_with_cost')).length === 0 && /Cost/.test(await p.textContent('#p2_list')), 'owner reads the table directly (RPC not needed)'); await p.close();

  // ---------- details field ----------
  p = await open({}, '#/items/new'); await p.click('#p_adv summary'); ok(await p.locator('#p_details').count() === 1, 'Details field on the form'); await p.screenshot({ path: SP + '/it3_details.png', fullPage: true }); await noOverflow(p, 'details form');
  await p.fill('#p_bn', 'নতুন'); await p.fill('#p_sell', '10'); await p.fill('#p_details', '  ghee, 500 g box  '); await p.click('[data-act=p2_save]'); await p.waitForTimeout(500);
  let sc = await calls(p, 'submit_item_change'); ok(sc.length === 1 && sc[0].p_patch.details === 'ghee, 500 g box', 'new item patch carries details (trimmed)'); await p.close();
  p = await open({ init: `window.__DATA.tables.items[0].details="old text";` }, '#/items'); await p.click('.p2-row >> nth=0'); await p.waitForTimeout(600); await p.click('#p_adv summary');
  ok((await p.inputValue('#p_details')) === 'old text', 'existing details prefilled'); await p.click('[data-act=p2_save]'); await p.waitForTimeout(400); ok((await calls(p, 'submit_item_change')).length === 0, 'unchanged details: nothing sent');
  await p.click('.p2-row >> nth=0'); await p.waitForTimeout(600); await p.click('#p_adv summary'); await p.fill('#p_details', ''); await p.click('[data-act=p2_save]'); await p.waitForTimeout(500);
  sc = await calls(p, 'submit_item_change'); ok(sc.length === 1 && Object.keys(sc[0].p_patch).length === 1 && sc[0].p_patch.details === null, 'clearing sends only details: null'); await p.close();
  p = await open({ lang: 'bn', init: LOW }, '#/items'); ok(/স্টক কম/.test(await p.textContent('.p2-row.warn')), 'Bangla low-stock chip'); await p.screenshot({ path: SP + '/it3_bn.png' }); await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0,6).join(' | ')); process.exit(1); } })();
