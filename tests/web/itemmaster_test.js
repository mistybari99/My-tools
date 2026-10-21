// Item master (W2): ⋮ menu + flags, add-by-category, import page (preview/apply/resume), needs-decision list, type defaults, asset register, purchase asset button, POS picker filter.
// Run: node itemmaster_test.js tests/web
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR, PORT = _P.freePort();
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP);
const TYPES = [['finished_good', 'তৈরি পণ্য', 'Finished good', true, true], ['resale', 'কিনে বিক্রি', 'Resale', true, true], ['raw_material', 'কাঁচামাল', 'Raw material', true, false], ['packaging', 'প্যাকেজিং', 'Packaging', true, false],
  ['consumable', 'ভোগ্য', 'Consumable', false, false], ['asset', 'সম্পদ', 'Asset', false, false], ['controlled', 'নিয়ন্ত্রিত', 'Controlled', false, false], ['infrastructure', 'অবকাঠামো', 'Infrastructure', false, false]]
  .map((t, i) => ({ code: t[0], label_bn: t[1], label_en: t[2], label_mix: t[2], count_in_business: t[3], sellable: t[4], sort: i + 1, active: true }));
function mkData(o = {}) {
  const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
  const R = (key, def, extra = {}) => ({ key, module: 'items', kind: 'switch', value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1, ...extra });
  T.rules = [R('vat_on', false), R('barcode_camera_on', false), R('barcode_device_on', false), { ...R('ui_noperm_mode', 'lock'), kind: 'choice' }, R('tools_stock_on', false), R('asset_register_on', true), R('item_create_needs_approval', true)];
  T.option_lists = [
    ...[['kg', 'কেজি', 'kg'], ['piece', 'পিস', 'piece'], ['box', 'বক্স', 'box'], ['ltr', 'লিটার', 'litre']].map((u, i) => ({ list_code: 'units', value_code: u[0], label_bn: u[1], label_en: u[2], sort: i + 1, active: true })),
    { list_code: 'item_categories', value_code: 'c14', label_bn: '', label_en: 'Finished Goods Sweet', sort: 14, active: true, extra: { cat_no: '14' } },
    { list_code: 'item_categories', value_code: 'c01', label_bn: '', label_en: 'Fixed Assets & Machinery', sort: 1, active: true, extra: { cat_no: '01' } },
    { list_code: 'item_subcategories', value_code: 'c14_aa', label_bn: '', label_en: 'Chhana-Based Sweets', sort: 14, active: true, extra: { category: 'c14' } },
    ...[['new', 'নতুন', 'New'], ['good', 'ভালো', 'Good']].map((u, i) => ({ list_code: 'asset_conditions', value_code: u[0], label_bn: u[1], label_en: u[2], sort: i, active: true }))];
  T.item_types = JSON.parse(JSON.stringify(TYPES)); T.item_class_map = [{ control_class: 'Asset', item_type: 'asset', active: true }, { control_class: 'Finished Good', item_type: 'finished_good', active: true }];
  const it = T.items;
  it.forEach((i) => Object.assign(i, { item_type: 'finished_good', count_in_business: true, sellable: true, locked: false, hidden: false, master_code: null, retired_at: null, control_class: null, import_batch: null }));
  Object.assign(it[1], { hidden: true }); Object.assign(it[2], { locked: true }); Object.assign(it[3], { item_type: 'resale', count_in_business: true });
  it.push({ id: 'd1', code: '14-001', name_bn: 'রসগোল্লা', name_en: 'Roshogolla', category: 'c14', sub_category: 'c14_aa', unit: 'kg', sell_price: null, is_active: true, item_type: 'finished_good', count_in_business: true, sellable: true, locked: false, hidden: false, control_class: 'Finished Good', import_batch: 'b1', tracked: false, source: 'made', images: [], sell_units: [] },
    { id: 'd2', code: '14-028', name_bn: 'রসমালাই', name_en: 'Roshomalai', category: 'c14', sub_category: 'c14_aa', unit: 'kg', sell_price: null, is_active: true, item_type: 'finished_good', count_in_business: true, sellable: true, locked: false, hidden: false, control_class: 'Finished Good', import_batch: 'b1', tracked: false, images: [], sell_units: [] },
    { id: 'a1', code: '01-001', name_bn: 'কেক মিক্সার', name_en: 'Cake Mixer', category: 'c01', unit: 'pc', sell_price: null, is_active: true, item_type: 'asset', count_in_business: false, sellable: false, locked: false, hidden: false, control_class: 'Asset', import_batch: 'b1', tracked: false, images: [], sell_units: [] });
  if (o.big) for (let i = 0; i < 1500; i++) it.push({ id: 'big' + i, code: '20-' + String(i + 1).padStart(4, '0'), name_bn: 'ডিকশনারি ' + i, name_en: 'Dict ' + i, category: 'c14', unit: 'pc', sell_price: null, is_active: true, item_type: 'consumable', count_in_business: false, sellable: false, locked: false, hidden: false, import_batch: 'b1', tracked: false, images: [], sell_units: [] });
  T.item_mapping_review = [{ id: 1, item_id: it[0].id, suggested_code: '14-028', confidence: 0.9, auto_ok: false, status: 'pending' }, { id: 2, item_id: it[5].id, suggested_code: '14-001', confidence: 0.55, auto_ok: false, status: 'pending' }, { id: 3, item_id: it[6].id, suggested_code: '14-028', confidence: 1, auto_ok: true, status: 'linked' }];
  it[6].master_code = '14-028';
  T.assets = [{ id: 'as1', item_id: 'a1', location_id: 1, tag: 'A-00001', bought_on: '2026-09-01', condition: 'new', status: 'in_use', maintenance_ref: null, note: 'main hall', active: true, purchase_bill_id: 'pb1' },
    { id: 'as2', item_id: 'a1', location_id: 1, tag: 'A-00002', bought_on: '2026-09-01', condition: 'good', status: 'under_repair', maintenance_ref: null, note: null, active: true, purchase_bill_id: null },
    { id: 'as3', item_id: 'a1', location_id: 1, tag: 'A-00003', bought_on: null, condition: null, status: 'retired', maintenance_ref: null, note: null, active: false, purchase_bill_id: null }];
  T.asset_costs = o.noCost ? [] : [{ asset_id: 'as1', cost: 25000 }, { asset_id: 'as2', cost: 24000 }];
  T.item_price_history = [{ id: 1, item_id: it[0].id, old_price: 250, new_price: 260, changed_at: '2026-09-01T00:00:00Z' }];
  T.suppliers = [{ id: 'sp1', name: 'Dudh Ghor', type_code: 'milk', active: true }];
  return data;
}
const dictRows = (n) => Array.from({ length: n }, (_, i) => ({ code: '14-' + String(100 + i).padStart(3, '0'), cat_no: '14', category: 'Finished Goods Sweet', name_en: 'Sweet ' + i, name_bn: 'মিষ্টি ' + i, subcategory: 'Chhana', unit: 'kg', control_class: 'Finished Good', note: '' }));
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const Q = window.__Q = window.__Q || { calls: [], fail: {}, applyFail: 0 };
 window.__CALLS = Q.calls;
 const rf = c.from; c.from = (name) => { const b = rf(name); const r0 = b.range, t0 = b.then; b.range = (x, y) => { b.__ranged = true; return r0.call(b, x, y); };
   b.then = (res, rej) => t0.call(b, (o) => { if (o && Array.isArray(o.data) && o.data.length > 1000) o = Object.assign({}, o, { data: o.data.slice(0, 1000) }); return res ? res(o) : o; }, rej); return b; };
 c.rpc = async (fn, args) => { Q.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (Q.fail[fn]) { const m = Q.fail[fn]; delete Q.fail[fn]; return { data: null, error: { message: m } }; }
  if (fn === 'has_grant') return { data: window.__GRANT === true, error: null };
  if (fn === 'stock_levels') return { data: [], error: null };
  if (fn === 'items_with_cost') return { data: [], error: null };
  if (fn === 'item_apply') { const it = T.items.find((x) => x.id === args.p_item); if (window.__OWNER === false && !window.__GRANT) return { data: { status: 'pending', id: 5 }, error: null }; Object.assign(it, args.p_patch); if ('is_active' in args.p_patch && !args.p_patch.is_active) it.retired_at = 'now'; return { data: { status: 'applied', item_id: it.id }, error: null }; }
  if (fn === 'item_new2') { fn = 'item_new'; }   // X5: the quick sheet calls item_new2 (client id + duplicate check) before item_new
  if (fn === 'item_new') { const code = args.p_patch.category === 'c14' ? '14-200' : args.p_patch.item_type === 'asset' ? '01-002' : 'I-100'; const n = Object.assign({ id: 'n' + T.items.length, code, is_active: true, count_in_business: true, sellable: true, tracked: false, images: [], sell_units: [] }, args.p_patch); T.items.push(n); return { data: { status: 'created', item_id: n.id, code }, error: null }; }
  if (fn === 'item_next_code') return { data: args.p_category === 'c14' ? '14-201' : args.p_category === 'c01' ? '01-002' : null, error: null };
  if (fn === 'item_dup_check') return { data: args.p_name_bn === 'কালো মিষ্টি – কেজি' ? [{ id: 'x', code: 'I-099', name_bn: 'কালো মিষ্টি – কেজি', name_en: null, why: 'same_name_bn' }] : [], error: null };
  if (fn === 'item_master_import_preview') { const rows = args.p_rows; return { data: { total: rows.length, to_create: rows.length - 1, to_create_active: rows.length - 1, to_create_retired: 0, skip_existing: 0, retired_rows: 0, conflicts: 1, conflict_list: [{ code: rows[0].code, reason: 'unknown_unit', name: rows[0].name_en }], by_type: { finished_good: rows.length - 1 }, by_unit: { kg: rows.length - 1 }, by_category: [{ cat_no: '14', category: 'Finished Goods Sweet', to_create: rows.length - 1, skip_existing: 0, retired: 0, conflicts: 1 }], unmapped_classes: [] }, error: null }; }
  if (fn === 'item_master_import_apply') { if (window.__APPLYFAIL && Q.calls.filter((c) => c[0] === 'item_master_import_apply').length === window.__APPLYFAIL) return { data: null, error: { message: 'network down' } }; return { data: { batch: args.p_batch, rows: args.p_rows.length, created: args.p_rows.length, skipped_existing: 0, retired_created: 0, conflicts: 0 }, error: null }; }
  if (fn === 'item_mapping_load') return { data: { loaded: args.p_rows.length, skipped: 0 }, error: null };
  if (fn === 'item_mapping_autolink') return { data: 1, error: null };
  if (fn === 'item_mapping_decide') { let r = T.item_mapping_review.find((x) => x.item_id === args.p_item); if (!r) { r = { id: 99, item_id: args.p_item, status: 'pending' }; T.item_mapping_review.push(r); } r.status = args.p_status; const it = T.items.find((x) => x.id === args.p_item); it.master_code = args.p_status === 'linked' ? args.p_dict : null; return { data: { status: args.p_status }, error: null }; }
  if (fn === 'item_map_decide2') { const r = T.item_mapping_review.find((x) => x.item_id === args.p_item); const st = { link: 'linked', keep: 'rejected', later: 'later', undo: 'pending', use_dict: 'replaced' }[args.p_action]; r.status = st; const it = T.items.find((x) => x.id === args.p_item); it.master_code = st === 'linked' ? args.p_dict : null; return { data: { status: st }, error: null }; }
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'item_type_set') { const t = T.item_types.find((x) => x.code === args.p_code); Object.assign(t, args.p_patch); return { data: null, error: null }; }
  if (fn === 'item_class_map_set') { const t = T.item_class_map.find((x) => x.control_class === args.p_class); t.item_type = args.p_type; return { data: null, error: null }; }
  if (fn === 'asset_update') { const a = T.assets.find((x) => x.id === args.p_id); Object.assign(a, args.p); return { data: { id: a.id }, error: null }; }
  if (fn === 'asset_add') { for (let i = 0; i < (args.p.qty || 1); i++) T.assets.push({ id: 'ax' + T.assets.length, tag: 'A-9' + T.assets.length, status: 'in_use', active: true, item_id: args.p.item_id, location_id: args.p.location_id, condition: args.p.condition, note: args.p.note }); return { data: { count: args.p.qty }, error: null }; }
  if (fn === 'asset_retire') { const a = T.assets.find((x) => x.id === args.p_id); Object.assign(a, { active: false, status: args.p_status, retired_reason: args.p_reason }); return { data: { id: a.id }, error: null }; }
  if (fn === 'asset_reactivate') { const a = T.assets.find((x) => x.id === args.p_id); Object.assign(a, { active: true, status: 'in_use' }); return { data: { id: a.id }, error: null }; }
  return rpc(fn, args); };
 return c; }; })();`;
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash, extraRoutes) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    if (o.dict) await p.route('**/data/item_dictionary.json', (r) => r.fulfill({ contentType: 'application/json', body: JSON.stringify(o.dict) }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mkData(o))};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1000); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__CALLS.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const menuHas = async (p, act) => (await p.locator(`.sheet [data-act=${act}]`).count()) > 0;

  // ---------- list: chips, ⋮ menu, flags ----------
  let p = await open({}, '#/items');
  ok(await p.locator('.p2-row .im-dots').count() >= 50, 'every row has a ⋮ button');
  ok(await p.locator('.p2-row:has-text("Locked")').count() === 1 && await p.locator('.p2-row:has-text("Hidden")').count() === 1, 'locked / hidden chips');
  ok(await p.locator('.p2-row:has-text("14-001")').count() === 1 && /Data needed/.test(await p.textContent('.p2-row:has-text("14-001")')), 'imported item without a price shows Data needed');
  ok(await p.locator('.p2-row:has-text("Cake Mixer") .chip:has-text("Not counted")').count() === 1, 'asset shows Not counted');
  await p.click('.p2-row:has-text("I-001") .im-dots'); await wait(p, 250);
  ok(await menuHas(p, 'im_edit') && await menuHas(p, 'im_lock') && await menuHas(p, 'im_hide') && await menuHas(p, 'im_active') && await menuHas(p, 'im_count') && await menuHas(p, 'im_type') && await menuHas(p, 'im_dup') && await menuHas(p, 'im_hist') && await menuHas(p, 'im_link'), 'menu has edit, lock, hide, activate, count, type, duplicate, history, link');
  await p.screenshot({ path: SP + '/im_menu.png' }); await noOverflow(p, 'menu');
  await p.click('.sheet [data-act=im_lock]'); await wait(p, 300);
  let ap = await calls(p, 'item_apply'); ok(ap.length === 1 && ap[0].p_patch.locked === true && ap[0].p_item === base.tables.items[0].id, 'Lock -> item_apply {locked:true}');
  ok(await p.locator('.p2-row:has-text("I-001"):has-text("Locked")').count() === 1, 'the list shows the lock after reload');
  await p.click('.p2-row:has-text("I-001") .im-dots'); await wait(p, 200); ok(/Unlock/.test(await p.textContent('.sheet [data-act=im_lock]')), 'menu now says Unlock'); await p.click('.sheet [data-act=closesheet]');
  await p.click('.p2-row:has-text("I-002") .im-dots'); await wait(p, 200); ok(/Show again/.test(await p.textContent('.sheet [data-act=im_hide]')), 'hidden item: Show again'); await p.click('.sheet [data-act=im_hide]'); await wait(p, 250);
  ap = await calls(p, 'item_apply'); ok(ap[1].p_patch.hidden === false, 'Show -> {hidden:false}');
  await p.click('.p2-row:has-text("I-004") .im-dots'); await wait(p, 200); await p.click('.sheet [data-act=im_active]'); await wait(p, 250);
  ok(await p.locator('#im_reason').count() === 1, 'inactivate asks for a reason'); await p.fill('#im_reason', 'no longer made'); await p.click('.sheet [data-act=im_inact_do]'); await wait(p, 300);
  ap = await calls(p, 'item_apply'); ok(ap[2].p_patch.is_active === false && ap[2].p_patch.retired_reason === 'no longer made', 'Inactivate -> {is_active:false, retired_reason}');
  await p.click('.p2-row:has-text("I-005") .im-dots'); await wait(p, 200); await p.click('.sheet [data-act=im_count]'); await wait(p, 250);
  ap = await calls(p, 'item_apply'); ok(ap[3].p_patch.count_in_business === false, 'Count off -> {count_in_business:false}');
  await p.click('.p2-row:has-text("I-006") .im-dots'); await wait(p, 200); await p.click('.sheet [data-act=im_type]'); await wait(p, 200);
  ok(await p.locator('.sheet [data-act=im_type_do]').count() === 8, 'type sheet lists all 8 types'); await p.click('.sheet [data-t=packaging]'); await wait(p, 250);
  ap = await calls(p, 'item_apply'); ok(ap[4].p_patch.item_type === 'packaging', 'Change type -> {item_type:packaging}');
  await p.click('.p2-row:has-text("I-007") .im-dots'); await wait(p, 200); await p.click('.sheet [data-act=im_dup]'); await wait(p, 300);
  ok(await p.locator('.sheet .notice.ok').count() === 1, 'duplicate check: none found'); await p.click('.sheet [data-act=closesheet]');
  await p.click('.p2-row:has-text("I-005") .im-dots'); await wait(p, 200); await p.click('.sheet [data-act=im_hist]'); await wait(p, 300);
  ok(/Price history/.test(await p.textContent('.sheet')), 'history sheet'); await p.click('.sheet [data-act=closesheet]');
  // asset row: count / sell cannot be turned on
  await p.click('.p2-row:has-text("Cake Mixer") .im-dots'); await wait(p, 200); ok(!(await menuHas(p, 'im_count')) && !(await menuHas(p, 'im_sell')), 'asset: no count / sell switches in the menu'); await p.click('.sheet [data-act=closesheet]');
  // link
  await p.click('.p2-row:has-text("I-003") .im-dots'); await wait(p, 200); await p.click('.sheet [data-act=im_link]'); await wait(p, 250);
  ok(await p.locator('#im_pk_l [data-act=im_pick_do]').count() >= 2, 'link picker lists dictionary items'); await p.fill('#im_pk_q', 'Roshomalai'); await wait(p, 250);
  ok(await p.locator('#im_pk_l [data-act=im_pick_do]').count() === 1, 'picker search'); await p.click('#im_pk_l [data-act=im_pick_do]'); await wait(p, 300);
  let dc = await calls(p, 'item_mapping_decide'); ok(dc.length === 1 && dc[0].p_dict === '14-028' && dc[0].p_status === 'linked', 'Link -> item_mapping_decide linked 14-028');
  // filters
  await p.click('#p2_fb'); await wait(p, 200); await p.selectOption('#ff_type', 'asset'); await p.click('[data-act=p2_apply]'); await wait(p, 250);
  ok(await p.locator('.p2-row').count() === 1, 'type filter: one asset'); await p.click('#p2_fb'); await wait(p, 200); await p.selectOption('#ff_type', ''); await p.selectOption('#ff_flag', 'noprice'); await p.click('[data-act=p2_apply]'); await wait(p, 250);
  ok(await p.locator('.p2-row').count() === 3, 'flag filter: no price = 3 (the two dictionary sweets and the asset)'); await p.click('#p2_chips .chip'); await wait(p, 200);
  await noOverflow(p, 'list'); await p.close();

  // ---------- non-owner: requests, no lock ----------
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:true,approve:false}};window.__PROFILE={id:"u3",staff_id:"testf02",full_name:"TestF",status:"active",lang:"en"};' }, '#/items');
  await p.click('.p2-row:has-text("I-001") .im-dots'); await wait(p, 250);
  ok(!(await menuHas(p, 'im_lock')) && await menuHas(p, 'im_hide'), 'staff: no Lock, but Hide');
  await p.click('.sheet [data-act=im_hide]'); await wait(p, 300); ok(/approval/i.test(await p.textContent('#toast')), 'staff change = sent for approval: ' + await p.textContent('#toast')); await p.close();

  // ---------- add by category + form ----------
  p = await open({}, '#/items');
  await p.click('[data-act=im_bycat]'); await wait(p, 250);
  ok(/14-029/.test(await p.textContent('#im_bc_l [data-c=c14]')) && /01-002/.test(await p.textContent('#im_bc_l [data-c=c01]')), 'by category: next code shown (14-029 after 14-028, 01-002 after 01-001): ' + await p.textContent('#im_bc_l'));
  await p.click('#im_bc_l [data-c=c01]'); await wait(p, 800);
  ok(location_hash(await p.url()) === '#/items/new/c01', 'goes to the new-item form with the category: ' + await p.url());
  ok(await p.locator('#im_type').count() === 1 && (await p.inputValue('#im_type')) === 'asset', 'type defaults to the commonest type of the category (asset)');
  ok(/Next code: 01-002/.test(await p.textContent('#im_code_h')), 'next code hint: ' + await p.textContent('#im_code_h'));
  ok((await p.getAttribute('#im_sell_f', 'disabled')) !== null, 'asset: for-sale switch is fixed off'); ok(await p.locator('#im_lock_f').count() === 1, 'owner sees the lock switch');
  await p.fill('#p_bn', 'নতুন চেয়ার'); await p.click('[data-act=p2_save]'); await wait(p, 500);
  let nw = await calls(p, 'item_new'); ok(nw.length === 1 && nw[0].p_patch.item_type === 'asset' && nw[0].p_patch.name_bn === 'নতুন চেয়ার' && nw[0].p_patch.category === 'c01' && nw[0].p_patch.sell_price === undefined, 'asset saved without a price through item_new: ' + JSON.stringify(nw[0]));
  await p.goto('http://localhost:' + PORT + '/#/items/new'); await wait(p, 700);
  await p.selectOption('#im_type', 'resale'); await wait(p, 100); ok(await p.locator('#im_sell_f.on').count() === 1, 'resale: for-sale default on');
  await p.fill('#p_bn', 'বাইরের মাল'); await p.click('[data-act=p2_save]'); await wait(p, 300); ok(/price/i.test(await p.textContent('#toast')), 'a sellable item still needs a price: ' + await p.textContent('#toast'));
  await p.selectOption('#im_type', 'raw_material'); await wait(p, 100); ok(await p.locator('#im_sell_f.on').count() === 0 && (await p.getAttribute('#im_sell_f', 'disabled')) !== null, 'raw material: for-sale off and fixed');
  await noOverflow(p, 'form'); await p.close();
  // edit a locked item as staff -> notice
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:true,approve:false}};window.__PROFILE={id:"u3",staff_id:"testf02",full_name:"TestF",status:"active",lang:"en"};' }, '#/items/edit/' + base.tables.items[2].id);
  ok(/locked/i.test(await p.textContent('#im_form')), 'locked item: the form says it is locked'); await p.close();

  // ---------- import page ----------
  const dict = dictRows(450);
  p = await open({ dict }, '#/itemimport');
  ok(await p.locator('[data-act=im_load]').count() === 1, 'import page opens'); await p.click('[data-act=im_load]'); await wait(p, 500);
  ok(/450/.test(await p.textContent('[data-act=im_load]')), 'file loaded: 450 rows'); await p.click('[data-act=im_preview]'); await wait(p, 500);
  let pv = await calls(p, 'item_master_import_preview'); ok(pv.length === 1 && pv[0].p_rows.length === 450, 'one preview call with all rows');
  ok(/449/.test(await p.textContent('.im-grid')) && /unknown_unit/.test(await p.textContent('#app')), 'preview numbers and the conflict list are shown'); ok((await calls(p, 'item_master_import_apply')).length === 0, 'preview wrote nothing (no apply call)');
  await p.screenshot({ path: SP + '/im_import.png' }); await noOverflow(p, 'import');
  await p.click('[data-act=im_apply]'); await wait(p, 300); ok(/Start the import/.test(await p.textContent('.sheet')), 'confirmation sheet'); await p.click('[data-act=im_apply_go]'); await wait(p, 900);
  let ia = await calls(p, 'item_master_import_apply'); ok(ia.length === 3 && ia[0].p_rows.length === 200 && ia[1].p_rows.length === 200 && ia[2].p_rows.length === 50, 'applied in chunks 200/200/50: ' + ia.map((x) => x.p_rows.length));
  ok(new Set(ia.map((x) => x.p_batch)).size === 1 && ia.every((x) => x.p_expected === 450), 'same batch id and expected count on every chunk');
  ok(/Import finished/.test(await p.textContent('#app')), 'finished'); await p.click('[data-act=im_map]'); await wait(p, 500);
  ok((await calls(p, 'item_mapping_load')).length >= 1 && (await calls(p, 'item_mapping_autolink')).length === 1, 'suggestions loaded then auto-link asked'); await p.close();
  // resume after a failed chunk
  p = await open({ dict, init: 'window.__APPLYFAIL=2;' }, '#/itemimport');
  await p.click('[data-act=im_load]'); await wait(p, 400); await p.click('[data-act=im_preview]'); await wait(p, 400); await p.click('[data-act=im_apply]'); await wait(p, 200); await p.click('[data-act=im_apply_go]'); await wait(p, 800);
  ok(/Stopped/.test(await p.textContent('#app')) && /200 \/ 450/.test(await p.textContent('#im_prog')), 'stops after chunk 1 when chunk 2 fails: ' + await p.textContent('#im_prog'));
  ok(/Resume/.test(await p.textContent('[data-act=im_apply]')), 'button says Resume');
  await p.evaluate(() => { window.__APPLYFAIL = 0; }); await p.click('[data-act=im_apply]'); await wait(p, 200); await p.click('[data-act=im_apply_go]'); await wait(p, 800);
  ia = await calls(p, 'item_master_import_apply'); ok(ia.length === 4 && ia[2].p_rows[0].code === dict[200].code && ia[3].p_rows.length === 50, 'resume continues from row 201 (no repeat of chunk 1): ' + ia.map((x) => x.p_rows.length)); ok(/Import finished/.test(await p.textContent('#app')), 'finished after resume'); await p.close();
  // not for staff
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={ITEMS:{view:true,enter:true,approve:false}};' }, '#/itemimport'); ok(!/Preview/.test(await p.textContent('#app')), 'staff cannot open the import page'); await p.close();

  // ---------- needs-decision list ----------
  p = await open({}, '#/itemmap');
  ok(await p.locator('#app .mp2').count() === 2, 'two rows to decide'); ok(/14-028/.test(await p.textContent('#app')) && /90%/.test(await p.textContent('#app')), 'suggestion and confidence shown');
  await p.click('#app .mp2 >> nth=0 >> .im-dots'); await wait(p, 250); ok(await menuHas(p, 'mp_link') && await menuHas(p, 'mp_find') && await menuHas(p, 'mp_keep') && await menuHas(p, 'mp_use'), 'menu: link / find / keep apart / use dictionary');
  await p.click('.sheet [data-act=mp_link]'); await wait(p, 500);
  dc = await calls(p, 'item_map_decide2'); ok(dc.length === 1 && dc[0].p_action === 'link' && dc[0].p_dict === '14-028', 'link suggestion -> item_map_decide2 link');
  ok(await p.locator('#app .mp2').count() === 1, 'one left to decide');
  await p.click('#app .mp2 >> nth=0 >> [data-act=mp_keep]'); await wait(p, 500);
  dc = await calls(p, 'item_map_decide2'); ok(dc[1].p_action === 'keep', 'keep apart'); ok(/None|Nothing/i.test(await p.textContent('#app')), 'list empty');
  await p.click('[data-act=mp_tab][data-v=linked]'); await wait(p, 200); ok(await p.locator('#app .mp2').count() === 2, 'linked tab: the auto one and the one just linked');
  await p.click('#app .mp2 >> nth=0 >> .im-dots'); await wait(p, 250); ok(await menuHas(p, 'mp_undo'), 'linked row can be undone'); await noOverflow(p, 'map'); await p.close();

  // ---------- types page ----------
  p = await open({}, '#/itemtypes');
  ok(await p.locator('#app .card').count() >= 9, 'types page lists types + switches + class map');
  await p.click('[data-act=im_rule][data-k=tools_stock_on]'); await wait(p, 400); let sr = await calls(p, 'set_rule'); ok(sr.length === 1 && sr[0].p_key === 'tools_stock_on' && sr[0].p_value === true, 'tools stock switch -> set_rule true');
  await p.click('[data-act=im_ty_tg][data-c=consumable][data-k=count_in_business]'); await wait(p, 400); let ts = await calls(p, 'item_type_set'); ok(ts.length === 1 && ts[0].p_code === 'consumable' && ts[0].p_patch.count_in_business === true, 'type default toggle -> item_type_set');
  ok((await p.getAttribute('[data-act=im_ty_tg][data-c=asset][data-k=sellable]', 'disabled')) !== null, 'asset defaults are fixed');
  await p.selectOption('[data-imcm="Asset"]', 'consumable'); await wait(p, 300); ok((await calls(p, 'item_class_map_set')).length === 1, 'class map change -> item_class_map_set'); await noOverflow(p, 'types'); await p.close();

  // ---------- asset register ----------
  p = await open({}, '#/assets');
  ok(await p.locator('#as_list .p2-row').count() === 2, 'two active assets (retired hidden)'); ok(/25,000|25000/.test(await p.textContent('#as_list')), 'owner sees the cost');
  await p.click('[data-act=as_ret]'); await wait(p, 200); ok(await p.locator('#as_list .p2-row').count() === 3, 'show retired too');
  await p.fill('#as_q', 'A-00002'); await wait(p, 500); ok(await p.locator('#as_list .p2-row').count() === 1, 'search by tag');
  await p.fill('#as_q', ''); await wait(p, 400); await p.selectOption('#as_st', 'under_repair'); await wait(p, 200); ok(await p.locator('#as_list .p2-row').count() === 1, 'status filter');
  await p.selectOption('#as_st', ''); await wait(p, 200); await p.click('#as_list .p2-row:has-text("A-00001") .im-dots'); await wait(p, 250);
  ok(await menuHas(p, 'as_edit') && await menuHas(p, 'as_retire') && (await p.locator('.sheet [data-act=as_stat]').count()) === 2, 'asset menu: edit, status changes, retire');
  await p.click('.sheet [data-act=as_stat][data-s=under_repair]'); await wait(p, 400); let au = await calls(p, 'asset_update'); ok(au.length === 1 && au[0].p_id === 'as1' && au[0].p.status === 'under_repair', 'status change -> asset_update');
  await p.click('#as_list .p2-row:has-text("A-00001") .im-dots'); await wait(p, 250); await p.click('.sheet [data-act=as_retire]'); await wait(p, 250); await p.click('.sheet [data-act=as_retire_do]'); await wait(p, 200); ok(await calls(p, 'asset_retire').then((x) => x.length) === 0, 'retire needs a reason');
  await p.fill('#ar_reason', 'scrapped'); await p.selectOption('#ar_st', 'sold'); await p.click('.sheet [data-act=as_retire_do]'); await wait(p, 400); let ar = await calls(p, 'asset_retire'); ok(ar.length === 1 && ar[0].p_reason === 'scrapped' && ar[0].p_status === 'sold', 'retire with reason and status');
  await p.click('[data-act=as_add]'); await wait(p, 300); await p.fill('#af_qty', '3'); await p.fill('#af_note', 'bought later'); await p.click('.sheet [data-act=as_save]'); await wait(p, 500);
  let aa = await calls(p, 'asset_add'); ok(aa.length === 1 && aa[0].p.qty === 3 && aa[0].p.item_id === 'a1', 'add 3 assets -> asset_add'); await noOverflow(p, 'assets'); await p.screenshot({ path: SP + '/im_assets.png' }); await p.close();
  p = await open({ noCost: true }, '#/assets'); ok(!/25,000|25000/.test(await p.textContent('#as_list')), 'no cost rows readable: no cost shown'); await p.close();

  // ---------- POS picker: only sellable, priced, visible ----------
  p = await open({ init: 'window.__DATA.tables.items[5].sell_price=null;window.__DATA.tables.items[6].hidden=true;window.__DATA.tables.items[7].sellable=false;' }, '#/pos');
  await wait(p, 600);
  const posNames = await p.evaluate(() => document.body.innerText);
  ok(!/Cake Mixer/.test(posNames) && !/Roshogolla/.test(posNames), 'POS does not offer an asset or an unpriced dictionary item'); await p.close();

  // ---------- more than 1000 items: the 57 priced items must still show ----------
  p = await open({ big: true }, '#/items'); await wait(p, 800);
  await p.fill('#p2_q', 'I-001'); await wait(p, 400); ok(await p.locator('.p2-row:has-text("I-001")').count() === 1, 'items list: the old items are still there with 1560+ items (paged read)');
  await p.fill('#p2_q', 'I-057'); await wait(p, 400); ok(await p.locator('.p2-row:has-text("I-057")').count() === 1, 'items list: last old item too'); await p.close();
  p = await open({ big: true }, '#/pos'); await wait(p, 900);
  ok(/সাদা মিষ্টি/.test(await p.evaluate(() => document.body.innerText)), 'POS: the priced old items show with 1500 more items in the table'); await p.close();

  // ---------- purchase bill: add a new asset item ----------
  const PD = { sales: [] };
  const pctx = await br.newContext({ viewport: { width: 360, height: 780 } }); const pp = await pctx.newPage();
  pp.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); pp.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  const pdata = C.mkData(JSON.parse(JSON.stringify(mkData({}))), {}); Object.assign(pdata.tables, { item_types: JSON.parse(JSON.stringify(TYPES)), item_class_map: [] });
  pdata.tables.option_lists.push({ list_code: 'item_categories', value_code: 'c01', label_bn: '', label_en: 'Fixed Assets', sort: 1, active: true, extra: { cat_no: '01' } });
  await pp.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
  await pp.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await pp.addInitScript(`window.__DATA=${JSON.stringify(pdata)};window.__GRANT=true;try{localStorage.setItem('bos_lang','en');}catch(e){}`);
  await pp.goto('http://localhost:' + PORT + '/#/purchase/new'); await pp.waitForTimeout(1200);
  ok(await pp.locator('[data-act=pu_newitem]').count() === 1, 'purchase editor: "New item (asset)" button for the owner');
  await pp.click('[data-act=pu_newitem]'); await pp.waitForTimeout(300); ok((await pp.inputValue('#ni_type')) === 'asset', 'the new-item sheet starts as type Asset');
  await pp.fill('#ni_bn', 'নতুন ফ্রিজ'); await pp.selectOption('#ni_cat', 'c01'); await pp.waitForTimeout(250); ok(/01-002/.test(await pp.textContent('#ni_code')), 'sheet shows the next code: ' + await pp.textContent('#ni_code'));
  await pp.click('#ni_go'); await pp.waitForTimeout(900);
  const nc = await pp.evaluate(() => window.__CALLS.filter((c) => c[0] === 'item_new' || c[0] === 'item_new2').map((c) => c[1]));
  ok(nc.length === 1 && nc[0].p_patch.item_type === 'asset' && nc[0].p_patch.category === 'c01', 'item_new asked with type asset + category');
  ok(/01-002/.test(await pp.inputValue('[data-ln="0.item"]')), 'the new item is on the bill line: ' + await pp.inputValue('[data-ln="0.item"]'));
  ok(/asset register/i.test(await pp.textContent('#pe_lines')), 'line hint: goes to the asset register, not to stock'); await pp.close();
  await br.close();
  log('errors:', errors.length ? errors.slice(0, 8).join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
function location_hash(u) { return u.slice(u.indexOf('#')); }
