// web/website.js (ERP Website screen) - stub-DOM test (no browser, no network). Run: node tests/web/website_test.js <abs tests/web dir>
// Checks: board numbers, go-live list with what to do, owner-only error text, settings saved one by one (only changed ones), item save payload, Bangla mode.
const fs = require('fs'), vm = require('vm'), path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', '..', 'web', 'website.js'), 'utf8');
let pass = 0, fail = 0; const ok = (n, c) => { if (c) pass++; else { fail++; console.log('FAIL ' + n); } };
const body = { innerHTML: '' }, acts = {}, toasts = [], calls = []; let MODE = 'en'; const RPC = {}; let RULES = []; let ITEMS = [], PUBS = [];
const els = { w_body: body, w_cat: { value: 'test_cakes' } };
const doc = { addEventListener() {}, getElementById: (i) => els[i] || null, querySelector: (s) => (s[0] === '#' ? (els[s.slice(1)] || null) : null), querySelectorAll: () => [] };
const B = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (o) => (typeof o === 'string' ? o : (o && o[MODE]) || (o && o.en) || ''), loadStatic: async () => {} };
const chain = (rows) => { const c = { select() { return c; }, eq(k, v) { c._f = (c._f || []).concat([[k, v]]); return c; }, like() { return c; }, order() { return c; }, limit() { return c; },
  then(res) { let r = rows; (c._f || []).forEach(([k, v]) => { r = r.filter((x) => x[k] === v); }); return Promise.resolve({ data: r, error: null }).then(res); } }; return c; };
const from = (t) => (t === 'rules' ? chain(RULES) : t === 'items' ? chain(ITEMS) : t === 'web_item_pub' ? chain(PUBS) : t === 'web_item_images' ? chain([]) : chain([]));
const A = { sb: { rpc: async (fn, a) => { calls.push([fn, a]); const r = RPC[fn]; if (r instanceof Error) return { data: null, error: r }; return { data: r === undefined ? null : r, error: null }; }, from },
  esc: (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
  toast: (m) => toasts.push(m), fail: (e) => toasts.push(String(e.message || e)), shell: () => {}, H: acts };
const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, prompt: () => '' };
const ctx = { window: win, document: doc, crypto: { randomUUID: () => '11111111-1111-4111-8111-111111111111' }, Date, Number, String, Object, JSON, Math, Array, Set, Promise, Error, Boolean, URL };
vm.createContext(ctx); vm.runInContext(src, ctx);
const view = win.BOS_PAGES.website;
const mk = (o) => ({ dataset: o, closest: () => null });

(async () => {
  ok('page registered', typeof view === 'function');
  RPC.web_admin_board = { on: true, published_items: 3, approved_photos: 1, web_orders_today: 2, web_orders_new: 1, cancel_requests_open: 0, custom_requests_new: 0, holds_held: 0, reserve_on: false };
  RPC.web_admin_go_live = { ready: false, items: [
    { key: 'site_on', required: true, ok: true, bn: 'ওয়েবসাইট চালু', en: 'Website switched on' },
    { key: 'domain', required: false, ok: false, bn: 'ডোমেইন', en: 'Domain', how_bn: 'ডোমেইন কিনুন', how_en: 'Buy a domain' },
    { key: 'test_order', required: true, ok: false, bn: 'পরীক্ষা অর্ডার', en: 'Test order', how_bn: 'অর্ডার দিন', how_en: 'Place a test order' } ] };
  RPC.web_admin_drift = { counts: { price_changed: 1, not_sellable: 0, holds_over_stock: 0, no_category: 0 }, price_changed: [{ item_id: 'x' }], not_sellable: [] };
  RPC.web_admin_holds_report = { held_qty: 0 };
  RULES = [{ key: 'website_public_url', value: '' }];
  await view();
  ok('board shows published items and new web orders', /Published items 3/.test(body.innerHTML) && /New orders 1/.test(body.innerHTML));
  ok('board says the domain is not set (honest, not invented)', /ডোমেইন|Domain|public address|No domain/i.test(body.innerHTML));
  ok('go-live lists required and optional items with what to do', /Website switched on/.test(body.innerHTML) && /Buy a domain/.test(body.innerHTML) && /\(Required\)/.test(body.innerHTML) && /\(Optional\)/.test(body.innerHTML));
  ok('go-live is not ready while a required item is missing', /Still missing/.test(body.innerHTML) && !/Ready to go live/.test(body.innerHTML));
  ok('drift count is shown', /ERP vs web drift: 1/.test(body.innerHTML));
  MODE = 'bn'; await view(); ok('Bangla mode renders the board', /ওয়েবসাইট/.test(body.innerHTML) && /অর্ডার/.test(body.innerHTML)); MODE = 'en';

  // settings: only changed values are sent, one set_rule each; switches come as booleans, numbers as numbers
  const before = { website_on: false, website_location_id: 0, website_brand_en: '' };
  const rows = [{ key: 'website_on', kind: 'switch', value: true }, { key: 'website_location_id', kind: 'number', value: 1 }, { key: 'website_brand_en', kind: 'text', value: '' }];
  const todo = B.website.changedSettings(rows, before).map((r) => r.key);
  ok('settings diff sends only the changed keys', JSON.stringify(todo) === JSON.stringify(['website_on', 'website_location_id']));
  ok('a switch becomes a boolean and a number becomes a number', B.website.settingValue('switch', 'on') === true && B.website.settingValue('number', '12') === 12 && B.website.settingValue('number', 'x') === 0);
  ok('text is kept as text (never a number)', B.website.settingValue('text', 0) === '0');

  // go-live summary helper
  const gl = B.website.goLiveSummary(RPC.web_admin_go_live);
  ok('go-live summary separates required missing from optional', gl.missing.length === 1 && gl.missing[0].key === 'test_order' && gl.optional.length === 1 && gl.ready === false);

  // actions: an item save sends the publish flag and the typed names; the server answers "not allowed" -> friendly text
  ITEMS = [{ id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', name_bn: 'test_item', category: 'test_cakes', sell_price: 100, is_active: true, sellable: true, hidden: false, retired_at: null }];
  RPC.web_admin_item_save = { item_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', published: true };
  RPC.web_admin_publish_bulk = { items: 1 };
  RPC.web_admin_item_save = RPC.web_admin_item_save;
  await acts.web_tab(mk({ t: 'items' }));
  ok('items tab lists the active sellable item', /test_item/.test(body.innerHTML) && /data-act="web_item_save"/.test(body.innerHTML));
  RPC.web_admin_publish_bulk = new Error('not allowed');
  await acts.web_bulk(mk({ on: '1' }));
  ok('a refused bulk publish shows the owner-only text', toasts.some((t) => /শুধু মালিক|Only the owner/.test(t)));
  RPC.web_admin_item_save = new Error('item_not_sellable: an item must be active');
  const card = { querySelector: (s) => ({ '.w_pub': { checked: true }, '.w_nb': { value: 'test' }, '.w_ne': { value: '' }, '.w_db': { value: '' }, '.w_de': { value: '' }, '.w_pc': { value: 'test' }, '.w_so': { value: '1' }, '.w_ld': { value: '0' }, '.w_av': { value: 'auto' }, '.w_al': { value: 'test milk' }, '.w_dt': { value: 'eggless, halal' } }[s]) };
  const dataItem = { dataset: { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' }, closest: () => card };
  await acts.web_item_save(dataItem);
  const sent = calls.filter((c) => c[0] === 'web_admin_item_save').pop();
  ok('item save sends the diet list split and the publish flag', sent && sent[1].p.published === true && JSON.stringify(sent[1].p.diet) === JSON.stringify(['eggless', 'halal']));
  ok('a refused item save shows the readable reason', toasts.some((t) => /active, sellable and priced/.test(t)));
  ok('the screen stores no secret and calls no service key', !/service_role|sb_secret_/.test(src));
  console.log('RESULT website screen: ' + pass + ' pass, ' + fail + ' fail');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL crash ' + e.stack); process.exit(1); });
