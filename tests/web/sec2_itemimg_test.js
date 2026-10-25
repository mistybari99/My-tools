// Step Sec2 (bos111, M4): item photo cache is emptied on sign-out and on a change of user; signed links are never stored. Same harness as itemimg_test.js.
// Run: node tests/web/sec2_itemimg_test.js [<abs tests/web dir>]      (serves web/ of this checkout, or $WEB_DIR). FAILING-BEFORE: run it with WEB_DIR=<web without the bos111 edits>.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const _P = require('./_paths'); const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR, PORT = _P.freePort();
const SHOT = process.env.SHOT_DIR || '';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8');
const mkData = () => new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
// window.__IMG = { map: {itemId: path}, thumbs: [paths that have a .t.jpg], failRpc, failSign }
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); window.__AUTHCB = []; c.auth.onAuthStateChange = (cb) => { window.__AUTHCB.push(cb); return { data: { subscription: { unsubscribe() {} } } }; }; const rpc = c.rpc; window.__CALLS = []; window.__SIGN = [];
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]);
  if (fn === 'items_first_image') { const I = window.__IMG || {}; if (I.failRpc) return { data: null, error: { message: 'function does not exist' } };
    return { data: (args.item_ids || []).filter((id) => I.map && I.map[id]).map((id) => ({ item_id: id, path: I.map[id] })), error: null }; }
  if (fn === 'set_rule') { const t = window.__DATA.tables.rules; const r = t.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; else t.push({ key: args.p_key, value: args.p_value }); return { data: null, error: null }; }
  return rpc(fn, args); };
 c.storage = { from: () => ({ createSignedUrls: async (paths) => { const I = window.__IMG || {}; window.__SIGN.push(paths.slice()); if (I.failSign) throw new Error('offline');
    return { data: paths.map((p) => { const isT = /\\.t\\.jpg$/.test(p), base = p.replace(/\\.t\\.jpg$/, ''); const ok = isT ? (I.thumbs || []).includes(base) : true; return ok ? { path: p, signedUrl: 'https://mock.local/' + p + '?t=1', error: null } : { path: p, signedUrl: null, error: 'Object not found' }; }), error: null }; },
   upload: async (p) => { (window.__UP = window.__UP || []).push(p); return { data: { path: p }, error: null }; } }) };
 return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, pass = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else pass++; };
  const base = mkData();
  const withImg = base.tables.items.filter((i) => i.sell_price && i.is_active !== false).slice(0, 3);
  async function open(hash, rules, pre) {
    const data = mkData(); data.tables.rules = Object.entries(rules).map(([key, value]) => ({ key, value, default_value: null, kind: 'choice', sort: 1 }));
    const ctx = await br.newContext({ viewport: { width: 360, height: 760 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route('https://mock.local/**', (r) => r.fulfill({ contentType: 'image/png', body: PNG }));
    const map = {}; withImg.forEach((i, k) => { map[i.id] = 'ITEMS/1/p' + k + '.jpg'; });
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__IMG=${JSON.stringify({ map, thumbs: [map[withImg[0].id]] })};try{localStorage.setItem('bos_lang','en');}catch(e){}` + (pre || ''));
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1300);
    return { p, ctx, map };
  }
  const cnt = (p) => p.evaluate(() => ({ imgs: document.querySelectorAll('.pos-item .iimg img.on').length, rpc: window.__CALLS.filter((c) => c[0] === 'items_first_image').length, sign: window.__SIGN.length }));
  const store = (p) => p.evaluate(async () => { let ls = null; try { ls = JSON.parse(localStorage.getItem('bos_iimg1') || 'null'); } catch (e) { ls = 'bad'; }
    let keys = []; try { if (await caches.has('bos-itemimg')) keys = (await (await caches.open('bos-itemimg')).keys()).map((r) => r.url); } catch (e) { keys = ['ERR']; } return { ls, keys, cb: (window.__AUTHCB || []).length }; });

  // 1. with cache hours: paths (not signed links) persisted, tied to a user; picture bytes under a user-bound key
  let { p, ctx } = await open('#/pos', { item_images_mode: 'pos_only', item_images_cache_hours: 6 });
  let c = await cnt(p), s = await store(p);
  ok(c.imgs === 3, 'pictures shown (' + c.imgs + ')');
  ok(s.ls && s.ls.v === 1 && s.ls.p && Object.keys(s.ls.p).length >= 3, 'paths are persisted');
  ok(s.ls && !('u' in s.ls) && !/signedUrl|token=|mock\.local/.test(JSON.stringify(s.ls)), 'M4: no signed link is persisted in localStorage');
  ok(s.ls && typeof s.ls.uid === 'string' && s.ls.uid.length > 0, 'M4: the stored paths carry the user id (' + (s.ls && s.ls.uid) + ')');
  ok(s.keys.length >= 1 && s.keys.every((k) => k.includes('/__itemimg/' + encodeURIComponent(s.ls.uid) + '/')), 'M4: the picture cache key contains the user id (' + s.keys.length + ' keys)');
  ok(s.cb === 1, 'M4: itemimg listens to the sign-in state (callbacks ' + s.cb + ')');
  // 2. a reload of the same user still shows pictures from the stored paths + bytes with no network call
  await p.reload(); await p.waitForTimeout(1300); c = await cnt(p);
  ok(c.sign === 0 && c.rpc === 0 && c.imgs === 3, 'same user after reload: pictures from the cache, no rpc / sign call (rpc ' + c.rpc + ', sign ' + c.sign + ', imgs ' + c.imgs + ')');
  // 3. sign-out empties everything
  await p.evaluate(() => window.__AUTHCB.forEach((cb) => cb('SIGNED_OUT', null))); await p.waitForTimeout(400); s = await store(p);
  ok(s.ls === null && s.keys.length === 0, 'M4: SIGNED_OUT empties localStorage and the picture cache (ls ' + JSON.stringify(s.ls) + ', keys ' + s.keys.length + ')');
  await ctx.close();
  // 4. another person on the same device: stored data of user X is not used for user Y (restore refuses it and empties it)
  ({ p, ctx } = await open('#/pos', { item_images_mode: 'pos_only', item_images_cache_hours: 6 }));
  await p.evaluate(() => { const o = JSON.parse(localStorage.getItem('bos_iimg1')); o.uid = 'someone-else'; localStorage.setItem('bos_iimg1', JSON.stringify(o)); });
  await p.reload(); await p.waitForTimeout(1500); c = await cnt(p);
  ok(c.rpc >= 1 && c.imgs === 3, 'M4: stored paths of ANOTHER user are not reused: they are fetched again (rpc ' + c.rpc + ', imgs ' + c.imgs + ')');
  s = await store(p); ok(s.ls && s.ls.uid !== 'someone-else', 'M4: and the stored data now belongs to the current user');
  // 5. user change event
  await p.evaluate(() => { window.__AUTHCB.forEach((cb) => cb('SIGNED_IN', { user: { id: 'A' } })); }); await p.waitForTimeout(200); s = await store(p);
  ok(s.ls !== null, 'M4: the first sign-in event (no earlier user) does not clear');
  await p.evaluate(() => { window.__AUTHCB.forEach((cb) => cb('TOKEN_REFRESHED', { user: { id: 'A' } })); }); await p.waitForTimeout(200); s = await store(p);
  ok(s.ls !== null, 'M4: a token refresh of the same user does not clear');
  await p.evaluate(() => { window.__AUTHCB.forEach((cb) => cb('SIGNED_IN', { user: { id: 'B' } })); }); await p.waitForTimeout(400); s = await store(p);
  ok(s.ls === null && s.keys.length === 0, 'M4: a different user signing in empties both stores');
  await ctx.close();
  // 6. off (default): no storage, no listener side effects
  ({ p, ctx } = await open('#/pos', {})); s = await store(p); c = await cnt(p);
  ok(s.ls === null && c.rpc === 0 && c.sign === 0, 'mode off: nothing stored, no rpc, no sign call');
  await p.evaluate(() => window.__AUTHCB.forEach((cb) => cb('SIGNED_OUT', null))); await ctx.close();
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('pass', pass, 'assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad || errors.length ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
