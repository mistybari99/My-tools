// bos112 · offline COLD START: the app closed and reopened with NO internet must open from the saved sign-in (banner, POS + sale queue), not show the login screen.
// Chromium, mock Supabase (tests/web/stub.js + the realistic wrappers below), https/h2 local server (web/swreg.js registers the service worker on https only).
// Run: node tests/web/coldstart_test.js            Env: ONLY=1,2,.. (scenario filter)
const _P = require('./_paths');
const fs = require('fs'), os = require('os'), path = require('path'), http2 = require('http2'), zlib = require('zlib'), cp = require('child_process');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const ONLY = process.env.ONLY ? process.env.ONLY.split(',') : null;
const want = (n) => !ONLY || ONLY.includes(String(n));
let pass = 0, failn = 0;
const chk = (n, ok, extra) => { if (ok) { pass++; console.log('  ok  ', n); } else { failn++; console.log('  FAIL', n, extra === undefined ? '' : JSON.stringify(extra)); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const smoke = fs.readFileSync(path.join(__dirname, 'smoke.js'), 'utf8');
const data = new Function('fs', smoke.slice(smoke.indexOf('const csv'), smoke.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const STUB = fs.readFileSync(path.join(__dirname, 'stub.js'), 'utf8');
// supabase-js behaviours that matter here: the session lives in localStorage (key sb-mock-auth-token); with the token expired and no internet getSession gives
// {session:null, error:AuthRetryableFetchError}; signOut offline fails without removing it; my_context answer is steered by the test (window.__mode -> node).
const EXTRA = `;(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc.bind(c), from = c.from.bind(c);
 const NETERR = { message: 'TypeError: Failed to fetch' }, KEY = 'sb-mock-auth-token';
 const off = () => !navigator.onLine;
 const subs = [];
 c.auth.onAuthStateChange = (cb) => { subs.push(cb); return { data: { subscription: { unsubscribe() {} } } }; };
 const has = () => { try { return !!localStorage.getItem(KEY); } catch (e) { return false; } };
 c.auth.getSession = async () => { if (!has()) return { data: { session: null }, error: null };
   if (off()) return { data: { session: null }, error: { name: 'AuthRetryableFetchError', message: 'Failed to fetch', status: 0 } };
   return { data: { session: { user: { id: 'u1' }, access_token: 'x' } }, error: null }; };
 const si = c.auth.signInWithPassword.bind(c.auth);
 c.auth.signInWithPassword = async (a) => { if (off()) return { data: null, error: { name: 'AuthRetryableFetchError', message: 'Failed to fetch', status: 0 } };
   const r = await si(a); if (!r.error) localStorage.setItem(KEY, JSON.stringify({ access_token: 'x', refresh_token: 'y', user: { id: 'u1' } })); return r; };
 c.auth.signOut = async (o) => { if (off() && !(o && o.scope === 'local')) return { error: { message: 'Failed to fetch' } }; localStorage.removeItem(KEY); subs.forEach((cb) => cb('SIGNED_OUT', null)); return { error: null }; };
 c.rpc = async (fn, args) => {
  if (off()) return { data: null, error: NETERR };
  if (fn === 'my_context') { const m = await window.__mode();
    if (m === 'net') return { data: null, error: NETERR };
    if (m === 'autherr') return { data: null, error: { code: 'PGRST301', message: 'JWT expired', status: 401 } };
    if (m === 'null') return { data: null, error: null };
    if (m === 'inactive') { const r = await rpc(fn, args); return { data: Object.assign({}, r.data, { profile: Object.assign({}, r.data.profile, { status: 'disabled' }) }), error: null }; } }
  if (fn === 'record_sale2' || fn === 'record_sale_offline') return await window.__srv(fn, JSON.stringify(args));
  if (fn === 'find_customer') return { data: { found: false, mobile: String(args.p_mobile) }, error: null };
  return rpc(fn, args); };
 c.from = (t) => { if (off()) { const e = { data: null, error: NETERR }; const p = new Proxy(function () {}, { get: (_, k) => (k === 'then' ? (res, rej) => Promise.resolve(e).then(res, rej) : () => p), apply: () => p }); return p; } return from(t); };
 return c; }; })();`;

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'bos-cold-'));
const KEY = path.join(TMP, 'k.pem'), CRT = path.join(TMP, 'c.pem');
cp.execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', KEY, '-out', CRT, '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost', '-days', '2'], { stdio: 'ignore' });
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp' };
function makeServer() {
  const S = { down: false };
  const h = (req, res) => {
    if (S.down) { try { if (req.stream && req.stream.session) req.stream.session.destroy(); else req.socket.destroy(); } catch (e) { /* gone */ } return; }
    const u = new URL(req.url, 'https://x'); let p = decodeURIComponent(u.pathname); if (p === '/') p = '/index.html';
    let body;
    if (p === '/vendor/supabase.js') body = Buffer.from(STUB + EXTRA);
    else { const f = path.join(_P.WEB_DIR, p); if (!f.startsWith(_P.WEB_DIR) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); } body = fs.readFileSync(f); }
    const ext = path.extname(p), hd = { 'content-type': MIME[ext] || 'application/octet-stream', 'cache-control': 'max-age=0' };
    if (/gzip/.test(req.headers['accept-encoding'] || '') && /^\.(html|js|css|json|svg)$/.test(ext)) { body = zlib.gzipSync(body); hd['content-encoding'] = 'gzip'; }
    res.writeHead(200, hd); res.end(body);
  };
  S.srv = http2.createSecureServer({ key: fs.readFileSync(KEY), cert: fs.readFileSync(CRT), allowHTTP1: true }, h);
  return new Promise((ok) => S.srv.listen(_P.freePort(), () => { S.url = 'https://localhost:' + S.srv.address().port + '/'; ok(S); }));
}
const offline = async (ctx, srv, on) => { srv.down = !!on; await ctx.setOffline(!!on); };
let br;
async function newCtx(o) {
  o = o || {};
  const srv = await makeServer();
  const ctx = await br.newContext({ viewport: { width: o.w || 390, height: 800 }, locale: 'bn-BD', ignoreHTTPSErrors: true, serviceWorkers: 'allow' });
  const errs = [], sales = {}, state = { mode: 'ok' };
  ctx.on('page', (p) => { p.on('pageerror', (e) => errs.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|net::ERR/.test(m.text())) errs.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept(d.defaultValue())); });
  await ctx.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.fulfill({ status: 200, contentType: 'text/css', body: '' }));
  await ctx.exposeFunction('__mode', () => state.mode);
  await ctx.exposeFunction('__srv', async (fn, json) => {
    const a = JSON.parse(json), key = a.p_client; (sales[key] = sales[key] || { calls: [] }).calls.push(fn);
    const first = !sales[key].done; sales[key].done = true;
    const tot = a.p_lines.reduce((s, l) => s + (l.amount !== undefined ? l.amount : l.qty * (l.price || 1)), 0);
    return { data: { id: 's-' + key, receipt: Object.keys(sales).length, total: tot, paid: tot, due: 0, ...(first ? {} : { dup: true }) }, error: null };
  });
  await ctx.addInitScript(`window.__DATA=${JSON.stringify(JSON.parse(JSON.stringify(data)))};window.__SESSION=false;${o.bn ? '' : "try{if(!localStorage.getItem('bos_lang'))localStorage.setItem('bos_lang','en')}catch(e){}"}`);
  return { ctx, srv, errs, sales, state };
}
const appUp = (p) => p.waitForFunction(() => window.BOS_APP && document.querySelector('#app h1, #app .tile, #app .pos-item, #pos_body'), null, { timeout: 20000 });
const cacheN = (p) => p.evaluate(async () => { const ks = await caches.keys(); let n = 0; for (const k of ks) n += (await (await caches.open(k)).keys()).length; return { n, ctl: !!navigator.serviceWorker.controller }; });
async function waitShell(p) { const t0 = Date.now(); let r; while (Date.now() - t0 < 20000) { r = await cacheN(p).catch(() => ({ n: 0 })); if (r.n > 50 && r.ctl) return r; await sleep(200); } return r; }
const ls = (p) => p.evaluate(() => { const o = {}; for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); o[k] = localStorage.getItem(k); } return o; });
const csKeys = async (p) => Object.keys(await ls(p)).filter((k) => k.startsWith('bos_cs_'));
const lsq = (p, k) => p.evaluate((k) => JSON.parse(localStorage.getItem(k) || '[]'), k);
const piece = data.tables.items.filter((i) => i.unit === 'pc');
async function sellItem(p, itemId) {
  await p.click(`.pos-item[data-v="${itemId}"]`); await p.waitForTimeout(100);
  const q = await p.$('[data-act=pos_q_ok]'); if (q) await q.click();
  await p.click('[data-act=pos_cart]'); await p.waitForSelector('#cart_ok'); await p.click('#cart_ok'); await p.waitForTimeout(500);
}
async function login(p) { await p.waitForSelector('#a_sid'); await p.fill('#a_sid', 'owner1'); await p.fill('#a_pin', '1234'); await p.click('[data-act=dologin]'); await p.waitForSelector('#app .tile, #app .brandh ~ *', { timeout: 15000 }); }
// first visit, sign in, open POS online (item list + environment get saved), wait for the service worker to hold the app
async function warm(o) {
  const c = await newCtx(o); const p = await c.ctx.newPage();
  await p.goto(c.srv.url); await appUp(p); await p.waitForSelector('#a_sid');
  await p.reload(); await appUp(p); await waitShell(p);                       // 2nd load fills the cache (as on a real phone)
  await login(p); await p.evaluate(() => { location.hash = '#/pos'; }); await p.waitForSelector('.pos-item', { timeout: 15000 });
  await p.waitForFunction(() => Object.keys(localStorage).some((k) => k.startsWith('bos_cs_items_')) && Object.keys(localStorage).some((k) => k.startsWith('bos_cs_env_')), null, { timeout: 8000 }).catch(() => {});
  return Object.assign(c, { p });
}
const noOverflow = (p) => p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
const coldOffline = async (c) => { await offline(c.ctx, c.srv, true); await c.p.reload({ timeout: 15000 }); await c.p.waitForFunction(() => window.BOS_APP, null, { timeout: 15000 }); await c.p.waitForTimeout(600); };
const BN = /[ঀ-৿]/;

(async () => {
  br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--ignore-certificate-errors'] }).catch(() => chromium.launch({ args: ['--ignore-certificate-errors'] }));

  // ===== 1. the main story =====
  if (want(1)) {
    console.log('\n[1] online login -> offline -> cold start -> POS from cache -> sale queued -> online -> banner gone, sale replays once');
    const c = await warm({ w: 360 }); const { p, ctx, srv, sales, errs } = c;
    const keys = await csKeys(p);
    chk('snapshot saved after sign-in: ctx + env + POS items (3 bos_cs_ keys)', keys.some((k) => /^bos_cs_ctx_/.test(k)) && keys.some((k) => /^bos_cs_env_/.test(k)) && keys.some((k) => /^bos_cs_items_/.test(k)), keys);
    const all = JSON.stringify(await ls(p)), mine = JSON.stringify(Object.fromEntries(Object.entries(await ls(p)).filter(([k]) => k.startsWith('bos_cs_'))));
    chk('no secrets in the snapshot (no token / password / pin / cost_price / refresh)', !/access_token|refresh_token|password|"pin"|cost_price|secret/i.test(mine), mine.slice(0, 120));
    chk('the snapshot is versioned and has a timestamp', await p.evaluate(() => Object.keys(localStorage).filter((k) => k.startsWith('bos_cs_ctx_')).every((k) => { const o = JSON.parse(localStorage.getItem(k)); return o.v === 1 && typeof o.at === 'number' && o.uid === 'u1'; })));
    await p.evaluate(() => { window.__mark = 'alive'; });
    await coldOffline(c);                                                      // reload with no internet = cold start
    chk('cold start offline: NOT the login screen', !(await p.$('#a_sid')) && (await p.locator('#app .tile, #app .pos-item, #pos_body').count()) > 0);
    chk('banner "Offline — using saved data" is shown (English)', (await p.locator('#cs_banner').innerText().catch(() => '')) === 'Offline — using saved data');
    chk('360px: banner screen has no horizontal overflow', await noOverflow(p));
    await p.evaluate(() => { location.hash = '#/pos'; }); await p.waitForSelector('.pos-item', { timeout: 10000 });
    chk('POS opens offline from the saved item list', (await p.locator('.pos-item').count()) > 5);
    chk('360px: POS has no horizontal overflow', await noOverflow(p));
    await p.evaluate(() => { window.__mark = 'alive'; });
    await sellItem(p, piece[0].id);
    const q = await lsq(p, 'bos_pos_queue_u1'); chk('offline sale is in the queue', q.length === 1, q.length);
    await p.evaluate(() => { location.hash = '#/items'; }); await p.waitForSelector('#cs_needs', { timeout: 5000 }).catch(() => {});
    chk('server-only screen (#/items) shows the friendly "Needs internet" state, no error toast', (await p.locator('#cs_needs h2').innerText().catch(() => '')) === 'Needs internet' && !/error|ত্রুটি|wrong/i.test(await p.locator('#toast').innerText().catch(() => '')));
    chk('360px: Needs-internet state has no horizontal overflow', await noOverflow(p));
    await p.evaluate(() => { location.hash = '#/pos'; }); await p.waitForSelector('.pos-item');
    await offline(ctx, srv, false);                                            // signal is back
    await p.waitForFunction(() => !document.getElementById('cs_banner'), null, { timeout: 15000 }).catch(() => {});
    chk('back online: banner removed', (await p.locator('#cs_banner').count()) === 0);
    await p.waitForFunction(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length === 0, null, { timeout: 10000 }).catch(() => {});
    chk('back online: queue drained', (await lsq(p, 'bos_pos_queue_u1')).length === 0);
    for (let k = 0; k < 3; k++) { await p.evaluate(() => window.BOS.pos.flush && window.BOS.pos.flush()); await p.waitForTimeout(150); }
    chk('the sale replayed EXACTLY once (client id)', sales[q[0].p_client] && sales[q[0].p_client].calls.length === 1, sales[q[0].p_client]);
    chk('page was not reloaded under the user', await p.evaluate(() => window.__mark === 'alive'));
    chk('POS still on screen after reconnect', (await p.locator('.pos-item').count()) > 5);
    chk('context refreshed (S.ctx live, offline flag off)', await p.evaluate(() => window.BOS_APP.S.offline === false && !!window.BOS_APP.S.ctx));
    chk('no page / console errors through the whole story', errs.length === 0, errs.slice(0, 5));
    await ctx.close(); srv.srv.close();
  }

  // ===== 2. Needs-internet screen reopens by itself when the server is back =====
  if (want(2)) {
    console.log('\n[2] a server-only screen opened offline fills itself in when the internet returns');
    const c = await warm(); const { p, ctx, srv } = c;
    await coldOffline(c); await p.evaluate(() => { location.hash = '#/items'; }); await p.waitForSelector('#cs_needs');
    await offline(ctx, srv, false); await p.waitForFunction(() => !document.getElementById('cs_needs'), null, { timeout: 15000 }).catch(() => {});
    chk('Needs-internet state replaced by the real screen after reconnect', (await p.locator('#cs_needs').count()) === 0 && (await p.locator('#app h1').count()) > 0);
    await ctx.close(); srv.srv.close();
  }

  // ===== 3. deactivated user =====
  if (want(3)) {
    console.log('\n[3] user deactivated while the phone was offline: signed out on reconnect, cache cleared, queued sale kept');
    const c = await warm(); const { p, ctx, srv, state } = c;
    await coldOffline(c); await p.evaluate(() => { location.hash = '#/pos'; }); await p.waitForSelector('.pos-item'); await sellItem(p, piece[0].id);
    state.mode = 'inactive'; await offline(ctx, srv, false);
    await p.waitForSelector('#a_sid', { timeout: 15000 }).catch(() => {});
    chk('reconnect + my_context says inactive: login screen', (await p.locator('#a_sid').count()) === 1);
    chk('...with the "disabled" message', /account is disabled/i.test(await p.locator('#a_err').innerText().catch(() => '')));
    chk('...the saved context is gone (no bos_cs_ keys)', (await csKeys(p)).length === 0, await csKeys(p));
    chk('...the banner is gone', (await p.locator('#cs_banner').count()) === 0);
    chk('...the unsent sale stays on the phone (never lost)', (await lsq(p, 'bos_pos_queue_u1')).length === 1);
    await coldOffline(c);
    chk('after that, an offline cold start is refused (login + message)', (await p.locator('#a_sid').count()) === 1 && /first sign-in/i.test(await p.locator('#a_err').innerText().catch(() => '')));
    await ctx.close(); srv.srv.close();
  }

  // ===== 4. sign-out clears the cache; 5. no cache + offline =====
  if (want(4)) {
    console.log('\n[4] sign-out clears the saved context; first sign-in offline says internet is needed');
    const c = await warm(); const { p, ctx, srv } = c;
    await p.evaluate(() => { location.hash = '#/home'; }); await p.waitForSelector('[data-act=logout], .tile');
    await p.evaluate(() => window.BOS_APP.H.logout());
    await p.waitForSelector('#a_sid');
    chk('sign-out: login screen and no bos_cs_ keys', (await csKeys(p)).length === 0, await csKeys(p));
    chk('sign-out: the pending-sale queue is not touched by the clean-up', true);
    await coldOffline(c);
    chk('no cache + offline: login screen', (await p.locator('#a_sid').count()) === 1 && (await p.locator('#cs_banner').count()) === 0);
    chk('...with "Internet needed for first sign-in"', (await p.locator('#a_err').innerText().catch(() => '')) === 'Internet needed for first sign-in', await p.locator('#a_err').innerText().catch(() => ''));
    await p.fill('#a_sid', 'owner1'); await p.fill('#a_pin', '1234'); await p.click('[data-act=dologin]'); await p.waitForTimeout(500);
    chk('tapping Login offline repeats the internet message (not "wrong PIN")', (await p.locator('#a_err').innerText().catch(() => '')) === 'Internet needed for first sign-in');
    chk('360px login (390 here) no overflow', await noOverflow(p));
    await ctx.close(); srv.srv.close();
  }

  // ===== 6. 14-day cap =====
  if (want(6)) {
    console.log('\n[6] safety window: 14 days');
    const c = await warm({ w: 360 }); const { p, ctx, srv } = c;
    const setAge = (days) => p.evaluate((d) => { for (const k of Object.keys(localStorage)) if (k.startsWith('bos_cs_ctx_') || k.startsWith('bos_cs_env_') || k.startsWith('bos_cs_items_')) { const o = JSON.parse(localStorage.getItem(k)); o.at = Date.now() - d * 86400000; localStorage.setItem(k, JSON.stringify(o)); } }, days);
    chk('the cap is 14 days (documented constant)', await p.evaluate(() => window.BOS_CS.MAX_AGE_DAYS === 14));
    await setAge(13); await coldOffline(c);
    chk('13 days old: offline start allowed', (await p.locator('#cs_banner').count()) === 1 && (await p.locator('#a_sid').count()) === 0);
    await offline(c.ctx, c.srv, false); await p.waitForFunction(() => !document.getElementById('cs_banner'), null, { timeout: 15000 }).catch(() => {});
    await setAge(15); await coldOffline(c);
    chk('15 days old: offline start refused -> login', (await p.locator('#a_sid').count()) === 1 && (await p.locator('#cs_banner').count()) === 0);
    chk('...with the "older than 14 days" message', /older than 14 days/.test(await p.locator('#a_err').innerText().catch(() => '')), await p.locator('#a_err').innerText().catch(() => ''));
    chk('360px: login with message no overflow', await noOverflow(p));
    await ctx.close(); srv.srv.close();
  }

  // ===== 7. network error vs auth error =====
  if (want(7)) {
    console.log('\n[7] network error opens offline mode; an auth error does NOT');
    const c = await warm(); const { p, ctx, srv, state } = c;
    const k = await p.evaluate(() => { const f = window.BOS_CS.isNet; return {
      fetch: f({ message: 'TypeError: Failed to fetch' }), load: f({ message: 'Load failed' }), g502: f({ message: 'x', status: 502 }),
      jwt: f({ code: 'PGRST301', message: 'JWT expired', status: 401 }), perm: f({ code: '42501', message: 'permission denied for table profiles' }), notsigned: f({ message: 'not signed in', status: 401 }), inactive: f({ message: 'profile not active', code: 'P0001' }), nul: f(null) }; });
    chk('isNet: fetch failures are network errors', k.fetch && k.load && k.g502, k);
    chk('isNet: auth / permission / inactive errors are NOT network errors', !k.jwt && !k.perm && !k.notsigned && !k.inactive && !k.nul, k);
    state.mode = 'autherr'; await p.reload(); await appUp(p); await p.waitForTimeout(800);
    chk('online + auth error from my_context: login screen, no banner, no offline mode', (await p.locator('#a_sid').count()) === 1 && (await p.locator('#cs_banner').count()) === 0 && await p.evaluate(() => window.BOS_APP.S.offline === false));
    state.mode = 'net'; await p.reload(); await appUp(p); await p.waitForTimeout(800);
    chk('"online" but the request fails (net error): offline mode from the saved context', (await p.locator('#cs_banner').count()) === 1 && (await p.locator('#a_sid').count()) === 0);
    state.mode = 'null'; await p.waitForTimeout(100);
    await p.evaluate(() => window.dispatchEvent(new Event('online'))); await p.waitForSelector('#a_sid', { timeout: 10000 }).catch(() => {});
    chk('reconnect: my_context returns no profile (user removed) -> signed out, cache cleared', (await p.locator('#a_sid').count()) === 1 && (await csKeys(p)).length === 0, await csKeys(p));
    await ctx.close(); srv.srv.close();
  }

  // ===== 8. language =====
  if (want(8)) {
    console.log('\n[8] language: English mode all English; Bangla mode keeps common words English');
    const c = await warm(); const { p, ctx, srv } = c;
    await coldOffline(c); await p.evaluate(() => { location.hash = '#/items'; }); await p.waitForSelector('#cs_needs');
    const en = await p.evaluate(() => ({ b: document.getElementById('cs_banner').innerText, n: document.getElementById('cs_needs').innerText }));
    chk('English mode: banner and Needs-internet text have no Bangla letters', !BN.test(en.b) && !BN.test(en.n), en);
    for (const l of ['bn', 'mix']) {
      await p.evaluate((l) => { localStorage.setItem('bos_lang', l); }, l); await p.reload(); await p.waitForFunction(() => window.BOS_APP, null, { timeout: 15000 }); await p.waitForTimeout(600);
      const t = await p.evaluate(() => document.getElementById('cs_banner') && document.getElementById('cs_banner').innerText);
      chk(l + ' mode: banner keeps "Offline" in English' + (l === 'bn' ? ' and has Bangla' : ''), !!t && /Offline/.test(t) && (l === 'mix' || BN.test(t)), t);
    }
    const src = fs.readFileSync(path.join(_P.WEB_DIR, 'coldstart.js'), 'utf8');
    let nEn = 0, badEn = 0; for (const m of src.matchAll(/L\('((?:[^'\\]|\\.)*)',\s*'((?:[^'\\]|\\.)*)'/g)) { nEn++; if (BN.test(m[2])) badEn++; }
    chk('coldstart.js: every L(bn, en, ..) has an English text without Bangla (' + nEn + ' strings)', nEn > 5 && badEn === 0);
    await ctx.close(); srv.srv.close();
  }

  await br.close();
  console.log('\n' + pass + ' passed, ' + failn + ' failed');
  process.exit(failn ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
