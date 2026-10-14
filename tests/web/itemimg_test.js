// Item photos decorator (web/itemimg.js, phase102 step Img) in Chromium with a mocked sb.storage / rpc.
// bos111: the mocked picture host is mock.supabase.co (the CSP of index.html allows images from *.supabase.co only); it was mock.local.
// Run: node tests/web/itemimg_test.js <abs tests/web dir>      (serves ../../web of this checkout)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname, ROOT = path.join(SP, '..', '..', 'web');
const SHOT = process.env.SHOT_DIR || '';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8');
const mkData = () => new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8087);
// window.__IMG = { map: {itemId: path}, thumbs: [paths that have a .t.jpg], failRpc, failSign }
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = []; window.__SIGN = [];
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]);
  if (fn === 'items_first_image') { const I = window.__IMG || {}; if (I.failRpc) return { data: null, error: { message: 'function does not exist' } };
    return { data: (args.item_ids || []).filter((id) => I.map && I.map[id]).map((id) => ({ item_id: id, path: I.map[id] })), error: null }; }
  if (fn === 'set_rule') { const t = window.__DATA.tables.rules; const r = t.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; else t.push({ key: args.p_key, value: args.p_value }); return { data: null, error: null }; }
  return rpc(fn, args); };
 c.storage = { from: () => ({ createSignedUrls: async (paths) => { const I = window.__IMG || {}; window.__SIGN.push(paths.slice()); if (I.failSign) throw new Error('offline');
    return { data: paths.map((p) => { const isT = /\\.t\\.jpg$/.test(p), base = p.replace(/\\.t\\.jpg$/, ''); const ok = isT ? (I.thumbs || []).includes(base) : true; return ok ? { path: p, signedUrl: 'https://mock.supabase.co/' + p + '?t=1', error: null } : { path: p, signedUrl: null, error: 'Object not found' }; }), error: null }; },
   upload: async (p) => { (window.__UP = window.__UP || []).push(p); return { data: { path: p }, error: null }; } }) };
 return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, pass = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else pass++; };
  const base = mkData();
  const sellable = base.tables.items.filter((i) => i.sell_price && i.is_active !== false).slice(0, 6);
  const withImg = sellable.slice(0, 3);
  async function open(hash, rules, img, opts = {}) {
    const data = mkData(); data.tables.rules = Object.entries(rules).map(([key, value]) => ({ key, value, default_value: null, kind: 'choice', sort: 1 }));
    const ctx = await br.newContext({ viewport: { width: 360, height: 760 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route('https://mock.supabase.co/**', (r) => { if (opts.slow) return setTimeout(() => r.fulfill({ contentType: 'image/png', body: PNG }), opts.slow); return r.fulfill({ contentType: 'image/png', body: PNG }); });
    const map = {}; withImg.forEach((i, k) => { map[i.id] = 'ITEMS/1/p' + k + '.jpg'; });
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__IMG=${JSON.stringify(Object.assign({ map, thumbs: [map[withImg[0].id]] }, img || {}))};try{localStorage.setItem('bos_lang','en');}catch(e){}`);
    await p.goto('http://localhost:8087/' + hash); await p.waitForTimeout(1300);
    return { p, ctx, map };
  }
  const info = (p) => p.evaluate(() => ({ cards: document.querySelectorAll('.pos-item').length, slots: document.querySelectorAll('.pos-item .iimg').length, imgs: document.querySelectorAll('.pos-item .iimg img.on').length,
    rpc: window.__CALLS.filter((c) => c[0] === 'items_first_image').length, sign: window.__SIGN.length, signPaths: window.__SIGN.flat(), css: !!document.getElementById('iimg-css'), anyIimg: document.querySelectorAll('.iimg, [data-iimg]').length,
    sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, html: (document.getElementById('pos_items') || {}).innerHTML || '' }));

  // 1. mode off (default: no rule rows at all) = DOM identical, no storage / rpc traffic
  let { p, ctx } = await open('#/pos', {});
  let r = await info(p);
  ok(r.cards > 3, 'POS renders cards (' + r.cards + ')'); ok(r.anyIimg === 0 && !r.css && r.rpc === 0 && r.sign === 0, 'off: no extra nodes, no style, no rpc, no signed-url call');
  const htmlOff = r.html; if (SHOT) await p.screenshot({ path: SHOT + '/pos_before_360.png' });
  ok(r.sw <= r.cw, 'off: no horizontal overflow');
  await ctx.close();
  // 1b. rule rows present but off
  ({ p, ctx } = await open('#/pos', { item_images_mode: 'off' })); r = await info(p);
  ok(r.anyIimg === 0 && r.rpc === 0 && r.sign === 0 && r.html === htmlOff, 'explicit off: identical card HTML to default'); await ctx.close();

  // 2. pos_only: cards decorated, ONE rpc and ONE signed-url call for all cards, letters first then pictures; thumb preferred when it exists
  ({ p, ctx } = await open('#/pos', { item_images_mode: 'pos_only', item_images_thumb_only: 'on' }));
  r = await info(p);
  ok(r.slots === r.cards, 'pos_only: every card has a slot (' + r.slots + '/' + r.cards + ')'); ok(r.rpc === 1, 'one items_first_image call for ' + r.cards + ' cards (got ' + r.rpc + ')');
  ok(r.sign === 1, 'one createSignedUrls call (got ' + r.sign + ')'); ok(r.imgs === 3, 'three photos shown (got ' + r.imgs + ')');
  ok(r.signPaths.includes('ITEMS/1/p0.jpg.t.jpg') && r.signPaths.includes('ITEMS/1/p0.jpg'), 'signs thumbnail and original in the same call');
  const srcs = await p.evaluate(() => [...document.querySelectorAll('.pos-item .iimg img')].map((i) => i.src));
  ok(srcs.some((s) => /p0\.jpg\.t\.jpg/.test(s)) && srcs.some((s) => /p1\.jpg\?/.test(s) && !/\.t\.jpg/.test(s)), 'thumb used when it exists, original when the thumb is missing');
  const rp = await p.evaluate(() => window.__CALLS.find((c) => c[0] === 'items_first_image')[1]); ok(Array.isArray(rp.item_ids) && rp.item_ids.length === r.cards, 'rpc gets the card ids only');
  const noPic = await p.evaluate(() => { const s = [...document.querySelectorAll('.pos-item .iimg')].find((x) => !x.querySelector('img')); return s ? { t: s.textContent, bg: getComputedStyle(s).backgroundColor, w: s.getBoundingClientRect().width } : null; });
  ok(noPic && /^\S$/.test(noPic.t) && noPic.w >= 40 && noPic.w <= 56, 'item without photo shows a letter avatar in a 44px slot: ' + JSON.stringify(noPic));
  const h1 = await p.evaluate(() => [...document.querySelectorAll('.pos-item')].slice(0, 3).map((c) => Math.round(c.getBoundingClientRect().height)));
  // 3. cache hit: add an item (grid re-renders) -> no new rpc / sign calls, pictures back at once
  await p.click('.pos-item >> nth=3'); await p.waitForTimeout(500);
  const q = await p.evaluate(() => document.querySelector('[data-act=pos_q_ok]') ? 1 : 0); if (q) { await p.click('[data-act=pos_q_ok]'); await p.waitForTimeout(400); }
  r = await info(p);
  ok(r.rpc === 1 && r.sign === 1, 'cache hit after re-render: still one rpc / one sign call (got ' + r.rpc + '/' + r.sign + ')'); ok(r.slots === r.cards && r.imgs === 3, 'slots + pictures re-attached after re-render');
  ok(await p.evaluate(() => document.querySelector('.pos-item.in') !== null), 'selling still works (item in cart)');
  ok(r.sw <= r.cw, 'pos_only: no horizontal overflow at 360px');
  const h2 = await p.evaluate(() => [...document.querySelectorAll('.pos-item')].slice(0, 3).map((c) => Math.round(c.getBoundingClientRect().height)));
  ok(JSON.stringify(h1) === JSON.stringify(h2), 'card heights do not change when pictures arrive/re-render: ' + h1 + ' vs ' + h2);
  const tap = await p.evaluate(() => { const c = document.querySelector('.pos-item'); const b = c.getBoundingClientRect(); return { w: b.width, h: b.height, pe: getComputedStyle(c.querySelector('.iimg')).pointerEvents }; });
  ok(tap.h >= 44 && tap.w >= 100 && tap.pe === 'none', 'tap target intact (card ' + Math.round(tap.w) + 'x' + Math.round(tap.h) + ', thumb ignores taps)');
  if (SHOT) await p.screenshot({ path: SHOT + '/pos_after_360.png' });
  await ctx.close();
  // pos_only: item list screen is NOT decorated
  ({ p, ctx } = await open('#/items', { item_images_mode: 'pos_only' })); r = await info(p);
  ok(r.anyIimg === 0 && r.rpc === 0, 'pos_only: item list screen has no thumbnails and no calls'); await ctx.close();
  // 4. everywhere: item list rows are decorated, with the pictures
  ({ p, ctx } = await open('#/items', { item_images_mode: 'everywhere' })); 
  r = await p.evaluate(() => ({ rows: document.querySelectorAll('.p2-row[data-act=itemedit]').length, slots: document.querySelectorAll('.p2-row .iimg').length, calls: window.__CALLS.filter((c) => c[0] === 'items_first_image').length, sign: window.__SIGN.length, sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  ok(r.rows > 0 && r.slots === r.rows, 'everywhere: every item list row has a slot (' + r.slots + '/' + r.rows + ')'); ok(r.calls <= 1 && r.sign <= 1, 'everywhere list: batched (rpc ' + r.calls + ', sign ' + r.sign + ')'); ok(r.sw <= r.cw, 'item list no overflow');
  if (SHOT) await p.screenshot({ path: SHOT + '/items_everywhere_360.png' });
  // picker preview: text box + datalist, and explicit data-iimg-id
  const it0 = withImg[0];
  await p.evaluate((o) => { const d = document.createElement('div'); d.id = 'tpick'; d.innerHTML = `<input id="t_item" list="t_dl" autocomplete="off"><datalist id="t_dl"><option value="${o.code} · ${o.name}"></option></datalist><div id="tx" data-iimg-id="${o.id}"><span class="nm">Zed</span></div>`; document.body.appendChild(d); }, { code: it0.code, name: it0.name_en || it0.name_bn, id: it0.id });
  await p.waitForTimeout(300);
  ok(await p.evaluate(() => !!document.querySelector('#tx .iimg')), 'explicit data-iimg-id element is decorated');
  await p.fill('#t_item', it0.code + ' · ' + (it0.name_en || it0.name_bn)); await p.waitForTimeout(700);
  ok(await p.evaluate(() => !!document.querySelector('#t_item + .iimg-pv')), 'picker: preview appears after an item is chosen');
  await p.fill('#t_item', 'zzz'); await p.waitForTimeout(200);
  ok(await p.evaluate(() => !document.querySelector('#t_item + .iimg-pv')), 'picker: preview removed when the text no longer matches an item');
  // clear cache button + usage count + stats
  const st = await p.evaluate(() => window.BOS.itemimg.stats()); ok(st.loaded >= 1, 'stats: pictures loaded this session counted (' + st.loaded + ')');
  await ctx.close();

  // 5. fail soft: rpc missing / signed urls fail -> letters, no page errors, selling works
  for (const f of [{ failRpc: true }, { failSign: true }]) {
    ({ p, ctx } = await open('#/pos', { item_images_mode: 'pos_only' }, f)); r = await info(p);
    ok(r.slots === r.cards && r.imgs === 0, 'fail soft ' + JSON.stringify(f) + ': letters stay, no pictures');
    await p.click('.pos-item >> nth=0'); await p.waitForTimeout(300); ok(await p.evaluate(() => !!(document.querySelector('.pos-item.in') || document.querySelector('[data-act=pos_q_ok]'))), 'fail soft ' + JSON.stringify(f) + ': item can still be sold');
    await ctx.close();
  }
  // 5b. slow image network does not block the grid: cards are interactive at once
  ({ p, ctx } = await open('#/pos', { item_images_mode: 'pos_only' }, null, { slow: 4000 })); r = await info(p);
  ok(r.cards > 3 && r.slots === r.cards && r.imgs === 0, 'slow images: grid and letters are there before any picture arrives');
  await p.click('.pos-item >> nth=0'); await p.waitForTimeout(300); ok(await p.evaluate(() => !!(document.querySelector('.pos-item.in') || document.querySelector('[data-act=pos_q_ok]'))), 'slow images: selling not blocked'); await ctx.close();
  // 6. persistent cache hours: bytes in Cache API + signed urls in localStorage; reload shows pictures with ZERO sign calls
  ({ p, ctx } = await open('#/pos', { item_images_mode: 'pos_only', item_images_cache_hours: 6 })); r = await info(p);
  ok(r.imgs === 3, 'cache hours: pictures shown (' + r.imgs + ')');
  const ls = await p.evaluate(() => { try { return !!localStorage.getItem('bos_iimg1'); } catch (e) { return false; } }); ok(ls, 'cache hours: paths + signed urls persisted in localStorage');
  const cc = await p.evaluate(async () => { try { return (await (await caches.open('bos-itemimg')).keys()).length; } catch (e) { return -1; } }); ok(cc >= 1 || cc === -1, 'cache hours: bytes in Cache API (' + cc + ')');
  await p.reload(); await p.waitForTimeout(1300); r = await info(p);
  ok(r.sign === 0 && r.rpc === 0 && r.imgs === 3, 'after reload: pictures from persisted cache, no network call (rpc ' + r.rpc + ', sign ' + r.sign + ', imgs ' + r.imgs + ')');
  // clear cache
  await p.evaluate(() => window.BOS.itemimg.clearCache()); ok(await p.evaluate(() => localStorage.getItem('bos_iimg1') === null), 'clear image cache empties localStorage'); await ctx.close();
  // 7. settings page
  ({ p, ctx } = await open('#/itemimg', {})); 
  ok(await p.locator('[data-act=img_mode]').count() === 3, 'settings: three mode chips'); ok(/POS only/.test(await p.textContent('#img_mode_card')) && /Recommended/.test(await p.textContent('#img_mode_card')), 'settings: recommendation text');
  ok(!/[ঀ-৿]/.test(await p.textContent('#img_body')), 'settings page in English mode has no Bangla');
  await p.click('[data-act=img_mode][data-v=pos_only]'); await p.waitForTimeout(500);
  ok(await p.evaluate(() => window.BOS.itemimg.mode() === 'pos_only'), 'settings: mode chip saves via set_rule and B.rule follows');
  ok(await p.locator('[data-act=img_clear]').count() === 1 && await p.locator('#img_loaded').count() === 1, 'settings: clear cache button + loaded count');
  await p.fill('#img_hours', '999'); await p.click('[data-act=img_hours_save]'); await p.waitForTimeout(300);
  ok(await p.evaluate(() => window.BOS.itemimg.hours() === null), 'settings: out-of-range hours not saved');
  await p.fill('#img_hours', '12'); await p.click('[data-act=img_hours_save]'); await p.waitForTimeout(400);
  ok(await p.evaluate(() => window.BOS.itemimg.hours() === 12), 'settings: hours saved');
  if (SHOT) await p.screenshot({ path: SHOT + '/itemimg_page_360.png', fullPage: true });
  await ctx.close();
  // 8. themes: dark scheme + classic
  for (const sc of ['dark', 'light']) { ({ p, ctx } = await open('#/pos', { item_images_mode: 'pos_only' })); await p.emulateMedia({ colorScheme: sc }); await p.waitForTimeout(300);
    ok(await p.evaluate(() => { const s = document.querySelector('.pos-item .iimg:not(:has(img))'); const c = getComputedStyle(s); return !!s && c.color === 'rgb(255, 255, 255)' && c.backgroundColor !== 'rgba(0, 0, 0, 0)'; }), sc + ': avatar colours set'); if (SHOT) await p.screenshot({ path: SHOT + '/pos_after_' + sc + '.png' }); await ctx.close(); }
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('pass', pass, 'assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad || errors.length ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
