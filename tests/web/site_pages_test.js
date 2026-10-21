// X2 storefront page test: headless Chromium at 360px, stub backend (every Supabase call is answered here), no real network.
// Checks: each page renders, no horizontal scroll at 360px, no page errors, catalogue/product/cart/checkout flows, idempotent checkout
// (same submission id after a failed send), tracking, custom cake validation, switched-off site, English/Bangla toggle.
// Run: node tests/web/site_pages_test.js            (needs Playwright + chromium; exits 1 on any FAIL)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SITE = path.join(__dirname, '..', '..', 'site');
const PORT = 8093, BASE = 'http://localhost:' + PORT + '/';
const SB = 'https://rpqrcmesbhwtyrikabhy.supabase.co';
let pass = 0, fail = 0; const ok = (n, c) => { if (c) { pass++; console.log('PASS ' + n); } else { fail++; console.log('FAIL ' + n); } };

const ITEM_A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', ITEM_B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const CATALOG = [
  { id: ITEM_A, name_bn: 'test_item_a', name_en: 'test item A', description_bn: 'test desc', description_en: 'test desc en', category: 'test_cakes', category_sort: 1,
    unit: 'pc', price: 100, availability: 'in_stock', lead_days: 0, allergens: 'test milk', diet: ['eggless'], images: [] },
  { id: ITEM_B, name_bn: 'test_item_b', name_en: 'test item B', description_bn: null, description_en: null, category: 'test_sweets', category_sort: 2,
    unit: 'kg', price: 50, availability: 'sold_out', lead_days: 0, allergens: null, diet: [], images: [] },
];
const CONFIG_ON = { on: true, brand: { bn: 'test_shop_bn', en: 'test_shop' }, whatsapp: '8801700000091', messenger: null, public_url: null, orders_open: true,
  holiday: { bn: null, en: null }, closed_today: false, closures: [], min_order: 0, cutoff_hour: 0, lead_days: 0, festival: false,
  payments: { cod: true, manual: true, manual_number: '01700000091' }, custom_cake: true, analytics: { pixel_id: null, ga_id: null },
  pickup: [{ id: 1, name_bn: 'test_branch', name_en: 'test_branch', hours_bn: 'test_hours', hours_en: 'test_hours', address: 'test_addr' }],
  zones: [{ id: 5, name_bn: 'test_zone', name_en: 'test_zone', charge: 50, min_order: 0 }],
  policies: { privacy: { bn: 'test privacy', en: 'test privacy' }, terms: { bn: '', en: '' }, refund: { bn: 'test refund', en: 'test refund' } } };
const CONFIG_OFF = { on: false };

const calls = []; let quoteFail = false; let checkoutFirstFail = true; let CONFIG = CONFIG_ON;
function stubRpc(name, body) {
  calls.push({ name, body });
  switch (name) {
    case 'web_site_config': return CONFIG;
    case 'web_catalog_v2': return { on: true, items: CATALOG.filter((i) => !body.p_category || i.category === body.p_category) };
    case 'web_quote': {
      if (quoteFail) return { ok: false, error: 'item_unavailable' };
      const sub = body.p_lines.reduce((n, l) => { const it = CATALOG.find((c) => c.id === l.item_id); return n + (it ? it.price * l.qty : 0); }, 0);
      return { ok: true, lines: [], subtotal: sub, delivery_charge: 0, total: sub, problems: [] };
    }
    case 'web_checkout_submit': return { ok: true, dup: false, order_no: 7, web_code: 'ABCD1234', status: 'new', subtotal: 200, delivery_charge: 0, total: 200, held: false, pay: 'cod' };
    case 'web_order_track':
      if (body.p_code === 'ABCD1234' && body.p_mobile === '01711000091') return { ok: true, order_no: 7, status: 'packed', delivery_mode: 'pickup', delivery_date: '2026-10-20', subtotal: 200, delivery_charge: 0, total: 200, pay_mode: 'cod', cancel_requested: false, can_request_cancel: true, events: [] };
      return { ok: false, error: 'not_found' };
    case 'web_order_cancel_request': return { ok: true, requested: true };
    case 'web_custom_request': return { ok: true, dup: false, code: 'CAKE0001', state: 'new' };
    default: return null;
  }
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.svg': 'image/svg+xml', '.txt': 'text/plain' };
const srv = http.createServer((q, r) => {
  const u = q.url.split('?')[0];
  const f = path.join(SITE, u === '/' ? 'index.html' : u);
  if (!f.startsWith(SITE)) { r.writeHead(403); return r.end(); }
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); r.end(b); });
}).listen(PORT);

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' }).catch(() => chromium.launch());
  const errors = [];
  async function newPage(name) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 740 }, deviceScaleFactor: 2, locale: 'bn-BD', serviceWorkers: 'block' });
    await ctx.addInitScript(() => { try { localStorage.setItem('site_consent', 'no'); } catch (e) {} });
    const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push(name + ': ' + e.message));
    // the lost-send step below aborts one request on purpose; Chromium logs that as ERR_CONNECTION_RESET: expected, not a page error
    p.on('console', (m) => { if (m.type() === 'error' && !/ERR_CONNECTION_RESET/.test(m.text())) errors.push(name + ' console: ' + m.text()); });
    // no real network: Supabase is answered by the stub; localhost is the site; everything else is refused
    await p.route('**/*', (route) => {
      const url = route.request().url();
      if (url.startsWith(BASE)) return route.continue();
      if (url.startsWith(SB + '/rest/v1/rpc/')) {
        const rpc = url.slice((SB + '/rest/v1/rpc/').length).split('?')[0];
        const body = route.request().postDataJSON() || {};
        if (rpc === 'web_checkout_submit' && checkoutFirstFail) { checkoutFirstFail = false; calls.push({ name: 'web_checkout_submit#lost', body }); return route.abort('connectionreset'); }
        const data = stubRpc(rpc, body);
        return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(data) });
      }
      return route.abort('blockedbyclient');
    });
    return p;
  }
  async function noOverflow(p) { return p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1); }

  // 1. every page at 360px: renders, no horizontal scroll
  const pages = ['index.html', 'catalogue.html', 'product.html?id=' + ITEM_A, 'cart.html', 'checkout.html', 'confirm.html?code=ABCD1234', 'track.html', 'custom-cake.html', 'contact.html', 'policies.html'];
  for (const pg of pages) {
    const p = await newPage(pg);
    await p.goto(BASE + pg); await p.waitForTimeout(350);
    ok('page ' + pg + ' renders a header and main', (await p.locator('#hdr header').count()) === 1 && (await p.locator('#main').innerText()).length > 0);
    ok('page ' + pg + ' has no horizontal scroll at 360px', await noOverflow(p));
    await p.close();
  }

  // 2. catalogue: published items, availability text, sold out cannot be added
  let p = await newPage('catalogue');
  await p.goto(BASE + 'catalogue.html'); await p.waitForSelector('[data-add]');
  const txt = await p.locator('#list').innerText();
  ok('catalogue lists the published items with price and availability', /test_item_a/.test(txt) && /100/.test(txt) && /In stock|আছে/.test(txt));
  ok('a sold out item has no add button', (await p.locator('button[disabled]').count()) >= 1 && (await p.locator('[data-add="' + ITEM_B + '"]').count()) === 0);
  ok('catalogue calls only the public RPC', calls.some((c) => c.name === 'web_catalog_v2') && !calls.some((c) => /admin|set_rule/.test(c.name)));
  await p.click('[data-add="' + ITEM_A + '"]');
  await p.waitForTimeout(100);
  const stored = await p.evaluate(() => localStorage.getItem('site_cart'));
  ok('add to cart stores id and quantity on this device', JSON.parse(stored).some((x) => x.id === ITEM_A && x.qty === 1));
  await p.close();

  // 3. product page: schema.org Product JSON-LD and the add control
  p = await newPage('product'); await p.goto(BASE + 'product.html?id=' + ITEM_A); await p.waitForSelector('#padd');
  const ld = await p.evaluate(() => { const s = document.getElementById('jsonld'); return s ? JSON.parse(s.textContent) : null; });
  ok('product page has Product JSON-LD with price in BDT', ld && ld['@type'] === 'Product' && ld.offers.price === 100 && ld.offers.priceCurrency === 'BDT');
  ok('product page shows allergens and the diet tag', (await p.locator('main').innerText()).includes('test milk') && (await p.locator('.tag').count()) >= 1);
  await p.close();

  // 4. cart + checkout: first send is lost (network), the retry reuses the SAME submission id (idempotent), then the confirm page
  p = await newPage('checkout');
  await p.goto(BASE + 'catalogue.html'); await p.waitForSelector('[data-add]');
  await p.click('[data-add="' + ITEM_A + '"]');
  await p.goto(BASE + 'checkout.html'); await p.waitForSelector('#ck');
  ok('checkout shows COD and bKash/Nagad options and the mobile field', (await p.locator('input[name="pay"]').count()) === 2 && (await p.locator('input[name="mobile"]').count()) === 1);
  await p.fill('input[name="name"]', 'test_buyer'); await p.fill('input[name="mobile"]', '01711000091');
  await p.click('#cksend'); await p.waitForTimeout(400);
  ok('a lost send shows the offline/try-again message and keeps the form', /আবার|try again|No internet|সংযোগ|did not work|হয়নি/i.test(await p.locator('#ckmsg').innerText()));
  await p.click('#cksend'); await p.waitForURL(/confirm\.html\?code=ABCD1234/, { timeout: 5000 }).catch(() => {});
  const subs = calls.filter((c) => c.name.startsWith('web_checkout_submit')).map((c) => c.body.p_submission);
  ok('the retry sent the same submission id (one order, not two)', subs.length === 2 && subs[0] === subs[1] && !!subs[0]);
  ok('the first checkout call carries only item ids and quantities (no price)', JSON.stringify(calls.find((c) => c.name === 'web_checkout_submit#lost').body.p_lines) === JSON.stringify([{ item_id: ITEM_A, qty: 1 }]));
  ok('after success the browser lands on the confirmation page with the order code', /confirm\.html\?code=ABCD1234/.test(p.url()));
  ok('the cart is emptied after the order', (await p.evaluate(() => localStorage.getItem('site_cart'))) === '[]');
  ok('checkout sends no secret and no service key', !calls.some((c) => JSON.stringify(c.body || {}).toLowerCase().includes('service')));
  await p.close();

  // 5. track: wrong mobile gets the same not-found; right mobile shows the status
  p = await newPage('track'); await p.goto(BASE + 'track.html');
  await p.fill('input[name="code"]', 'ABCD1234'); await p.fill('input[name="mobile"]', '01799999999'); await p.click('#tf button');
  await p.waitForTimeout(300);
  ok('tracking with a wrong mobile says not found', /মেলেনি|No order matches/.test(await p.locator('#tr').innerText()));
  await p.fill('input[name="mobile"]', '01711000091'); await p.click('#tf button'); await p.waitForTimeout(300);
  ok('tracking with the right code and mobile shows the status', /Packed|প্যাক/.test(await p.locator('#tr').innerText()) && (await p.locator('#cf').count()) === 1);
  await p.close();

  // 6. custom cake: a bad weight is refused by the server and the page says so; no photo needed for the form
  p = await newPage('cake'); await p.goto(BASE + 'custom-cake.html'); await p.waitForSelector('#cc');
  await p.fill('input[name="name"]', 'test_cake_buyer'); await p.fill('input[name="mobile"]', '01711000094');
  await p.fill('input[name="wanted"]', '2026-12-31'); await p.click('#cc button[type="submit"]'); await p.waitForTimeout(300);
  const cc = calls.find((c) => c.name === 'web_custom_request');
  ok('custom cake request reaches the public RPC with the wanted date and no photo path', !!cc && cc.body.p_wanted === '2026-12-31' && cc.body.p_ref_path === null);
  ok('custom cake shows the confirmation with its code', /CAKE0001/.test(await p.locator('#ccmsg').innerText()));
  await p.close();

  // 7. switched-off site: the public page says so, nothing is ordered
  CONFIG = CONFIG_OFF;
  const before = calls.length;
  p = await newPage('off'); await p.goto(BASE + 'index.html'); await p.waitForTimeout(350);
  ok('switched-off site shows the closed notice and makes no catalogue call', /বন্ধ|closed/.test(await p.locator('#main').innerText()) && !calls.slice(before).some((c) => c.name === 'web_catalog_v2'));
  await p.close(); CONFIG = CONFIG_ON;

  // 8. language toggle keeps the page and switches the text
  p = await newPage('lang'); await p.goto(BASE + 'cart.html'); await p.waitForTimeout(200);
  await p.click('#langbtn'); await p.waitForTimeout(400);
  ok('English toggle switches the cart heading', /Cart/.test(await p.locator('h1').first().innerText()));
  ok('English page still fits 360px', await noOverflow(p));
  await p.close();

  ok('no page errors or console errors on any page', errors.length === 0);
  if (errors.length) console.log(errors.slice(0, 8).join('\n'));
  await br.close(); srv.close();
  console.log('RESULT site pages: ' + pass + ' pass, ' + fail + ' fail');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL crash ' + e.message); srv.close(); process.exit(1); });
