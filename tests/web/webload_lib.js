// Shared helpers for the web-load tools (webload_measure.js, lazy_test.js): bandwidth-shaped https/h2 server (gzip like GitHub Pages), signed-in Supabase mock, Chromium launcher.
// Not a *_test.js file on purpose (run_all.sh only runs *_test.js).
const crypto = require('crypto'), fs = require('fs'), os = require('os'), path = require('path'), http2 = require('http2'), zlib = require('zlib'), cp = require('child_process');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const smoke = fs.readFileSync(path.join(__dirname, 'smoke.js'), 'utf8');
process.env.BOS_REPO_DIR = process.env.BOS_REPO_DIR || path.resolve(__dirname, '..', '..');
const data = new Function('fs', smoke.slice(smoke.indexOf('const csv'), smoke.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const STUB = fs.readFileSync(path.join(__dirname, 'stub.js'), 'utf8');
// realistic wrappers: offline => database calls fail (like production), sales go to the test's __srv
const EXTRA = `;(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc.bind(c), from = c.from.bind(c);
 const NETERR = { message: 'TypeError: Failed to fetch' }, KEY = 'sb-mock-auth-token';
 const off = () => !navigator.onLine;
 const subs = [];
 c.auth.onAuthStateChange = (cb) => { subs.push(cb); return { data: { subscription: { unsubscribe() {} } } }; };
 const has = () => { try { return !!localStorage.getItem(KEY); } catch (e) { return false; } };
 c.auth.getSession = async () => { if (off()) { if (!has()) return { data: { session: null }, error: null }; return { data: { session: null }, error: { name: 'AuthRetryableFetchError', message: 'Failed to fetch', status: 0 } }; }
   try { localStorage.setItem(KEY, JSON.stringify({ access_token: 'x', refresh_token: 'y', user: { id: 'u1' } })); } catch (e) { /* none */ }
   return { data: { session: { user: { id: 'u1' }, access_token: 'x' } }, error: null }; };
 c.rpc = async (fn, args) => {
  if (off()) return { data: null, error: NETERR };
  if (fn === 'record_sale2' || fn === 'record_sale_offline') return await window.__srv(fn, JSON.stringify(args));
  if (fn === 'find_customer') return { data: { found: false, mobile: String(args.p_mobile) }, error: null };
  return rpc(fn, args); };
 c.from = (t) => { if (off()) { const e = { data: null, error: NETERR }; const p = new Proxy(function () {}, { get: (_, k) => (k === 'then' ? (res, rej) => Promise.resolve(e).then(res, rej) : () => p), apply: () => p }); return p; } return from(t); };
 return c; }; })();`;
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp' };
let TMP = null, KEY, CRT;
function certs() { if (TMP) return; TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'bos-wl-')); KEY = path.join(TMP, 'k.pem'); CRT = path.join(TMP, 'c.pem');
  cp.execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', KEY, '-out', CRT, '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost', '-days', '2'], { stdio: 'ignore' }); }
// opts: root, rttMs (added before each response), kBps (shared link speed; 0 = unlimited), transform(path, Buffer) => Buffer, maxAge
async function makeServer(o) {
  certs();
  const S = { root: o.root, log: [], down: false, rttMs: o.rttMs || 0, kBps: o.kBps || 0, maxAge: o.maxAge === undefined ? 0 : o.maxAge, free: 0, t0: Date.now() };
  const share = async (n) => { if (!S.kBps) return; const now = Date.now(), slot = Math.max(now, S.free); S.free = slot + (n / (S.kBps * 1024)) * 1000; if (slot > now) await sleep(slot - now); };
  const h = async (req, res) => {
    if (S.down) { try { if (req.stream && req.stream.session) req.stream.session.destroy(); else req.socket.destroy(); } catch (e) { /* gone */ } return; }
    const u = new URL(req.url, 'https://x'); let p = decodeURIComponent(u.pathname); if (p === '/') p = '/index.html';
    let body;
    if (p === '/vendor/supabase.js' && o.stub !== false) body = Buffer.from(STUB + EXTRA);
    else { const f = path.join(S.root, p); if (!f.startsWith(S.root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { S.log.push({ p, status: 404, bytes: 0, at: Date.now() - S.t0 }); res.writeHead(404); return res.end(); } body = fs.readFileSync(f); }
    if (o.transform) body = o.transform(p, body) || body;
    const ext = path.extname(p), etag = '"' + crypto.createHash('md5').update(body).digest('hex') + '"', hd = { 'content-type': MIME[ext] || 'application/octet-stream', 'cache-control': 'max-age=' + S.maxAge, etag };
    const isSW = /no-cache/.test(req.headers['cache-control'] || '') && !/navigate|document/.test(req.headers['sec-fetch-mode'] || '');
    if (req.headers['if-none-match'] === etag) { S.log.push({ p: p + u.search, status: 304, bytes: 0, raw: 0, at: Date.now() - S.t0, sw: isSW }); if (S.rttMs) await sleep(S.rttMs); res.writeHead(304, hd); return res.end(); }
    let wire = body;
    if (/gzip/.test(req.headers['accept-encoding'] || '') && /^\.(html|js|css|json|svg)$/.test(ext)) { wire = zlib.gzipSync(body, { level: 6 }); hd['content-encoding'] = 'gzip'; }
    const rec = { p: p + u.search, status: 200, bytes: wire.length, raw: body.length, at: Date.now() - S.t0, ref: req.headers['referer'] || '', sw: isSW };
    S.log.push(rec);
    if (S.rttMs) await sleep(S.rttMs);
    res.writeHead(200, Object.assign(hd, { 'content-length': wire.length }));
    const CH = 8192; for (let i = 0; i < wire.length; i += CH) { const part = wire.subarray(i, i + CH); await share(part.length); if (res.destroyed) return; res.write(part); }
    res.end();
  };
  S.srv = http2.createSecureServer({ key: fs.readFileSync(KEY), cert: fs.readFileSync(CRT), allowHTTP1: true }, (a, b) => { h(a, b).catch(() => { try { b.end(); } catch (e) { /* x */ } }); });
  await new Promise((ok) => S.srv.listen(0, () => { S.port = S.srv.address().port; S.url = 'https://localhost:' + S.port + '/'; ok(); }));
  S.close = () => { try { S.srv.close(); } catch (e) { /* x */ } };
  S.bytesSince = (i) => S.log.slice(i).reduce((s, r) => s + r.bytes, 0);
  return S;
}
async function launch(extra) {
  certs();   // --ignore-certificate-errors disables the HTTP cache for the origin; trusting this one key (SPKI pin) keeps Chrome's HTTP cache working like on a real https site
  const spki = cp.execSync(`openssl x509 -in '${CRT}' -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`, { encoding: 'utf8' }).trim();
  const args = ['--ignore-certificate-errors-spki-list=' + spki, '--host-resolver-rules=MAP fonts.googleapis.com 127.0.0.1:9, MAP fonts.gstatic.com 127.0.0.1:9']   // route() would disable the HTTP cache, so Google Fonts are blocked at DNS level instead
  .concat(extra || []);
  return chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args }).catch(() => chromium.launch({ args }));
}
// a signed-in owner context with the Supabase stand-in; sales go to a counter
async function newCtx(br, o) {
  o = o || {};
  const ctx = await br.newContext({ viewport: { width: 390, height: 800 }, locale: 'bn-BD', ignoreHTTPSErrors: false, serviceWorkers: o.noSW ? 'block' : 'allow', deviceScaleFactor: 2, isMobile: !!o.mobile, hasTouch: !!o.mobile });
  const errs = [], sales = {};
  ctx.on('page', (p) => { p.on('pageerror', (e) => errs.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/fonts\.g|ERR_CONNECTION_REFUSED|Failed to load resource/.test(m.text())) errs.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept(d.defaultValue())); });
  await ctx.exposeFunction('__srv', async (fn, json) => { const a = JSON.parse(json), key = a.p_client; (sales[key] = sales[key] || { calls: [] }).calls.push(fn);
    const tot = a.p_lines.reduce((s, l) => s + (l.amount !== undefined ? l.amount : l.qty * (l.price || 1)), 0);
    return { data: { id: 's-' + key, receipt: Object.keys(sales).length, total: tot, paid: tot, due: 0 }, error: null }; });
  await ctx.addInitScript(`window.__DATA=${JSON.stringify(JSON.parse(JSON.stringify(data)))};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}${o.init || ''}`);
  return { ctx, errs, sales };
}
const offline = async (ctx, srv, on) => { srv.down = !!on; await ctx.setOffline(!!on); };
// extract a git tree (any repo/ref) into a dir
function extract(repo, ref, dir, sub) { fs.mkdirSync(dir, { recursive: true }); cp.execFileSync('bash', ['-c', `git -C '${repo}' archive '${ref}' ${sub || ''} | tar -x -C '${dir}'`]); return dir; }
module.exports = { data, STUB, EXTRA, makeServer, launch, newCtx, offline, extract, sleep, MIME };
