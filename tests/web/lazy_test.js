// bos114 (WebLoad): lazy screen loading in the built bundle (tools/web_build.js). Builds web/ into a temp dir (or uses LAZY_DIR) and checks, in Chromium with the Supabase stand-in:
//  1 the built index.html has a handful of script tags and the lazy map; 2 deep links to 15 representative routes render on a COLD start; 3 EVERY route of ia.js renders with no page error and the same title
//  as the plain web/ folder; 4 a route's script is requested/run exactly once, revisits add no listeners; 5 a failed script fetch shows the retry screen and Retry works;
//  6 service worker: first visit keeps only the core (no lazy screens), offline POS after a cold start still works; 7 a route opened offline says "needs internet" (no blank screen).
// Run: node tests/web/lazy_test.js        env: LAZY_DIR=<built dir>  WEB_BUILD_NM=<node_modules with terser+esbuild>
const _P = require('./_paths');
const SRCWEB = process.env.WEB_SRC || require('path').join(_P.REPO_DIR, 'web');   // always built from the source folder, whatever WEB_DIR is
const fs = require('fs'), os = require('os'), path = require('path'), cp = require('child_process');
const L = require('./webload_lib');
let pass = 0, failn = 0; const chk = (n, ok, x) => { if (ok) { pass++; console.log('  ok  ', n); } else { failn++; console.log('  FAIL', n, x === undefined ? '' : JSON.stringify(x).slice(0, 400)); } };
const REPO = _P.REPO_DIR;
function build() {
  if (process.env.LAZY_DIR) return process.env.LAZY_DIR;
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'bos-lazy-'));
  cp.execFileSync('bash', [path.join(REPO, 'tools/build_web.sh'), '--out', out], { stdio: 'pipe', env: Object.assign({}, process.env, { WEB_SRC_OVERRIDE: SRCWEB }) }); return out;
}
const DEEP = ['employees', 'accounts', 'purchase', 'landed', 'assistant', 'customers', 'dashx', 'whatsnew', 'settings2', 'payroll', 'attendance', 'finance2', 'partners', 'costing', 'books85'];
(async () => {
  const dist = build(); const br = await L.launch();
  const ix = fs.readFileSync(path.join(dist, 'index.html'), 'utf8'), tags = [...ix.matchAll(/<script\b[^>]*\ssrc="([^"]+)"/g)].map((m) => m[1]);
  chk('built index.html has <= 5 script tags: ' + tags.join(' '), tags.length <= 5 && tags.some((t) => /^core\.js\?v=[0-9a-f]{10}$/.test(t)), tags);
  const core = fs.readFileSync(path.join(dist, 'core.js'), 'utf8'); const mapM = core.match(/window\.BOS_LAZY_MAP=(\{.*\});\s*$/s); const MAP = mapM ? JSON.parse(mapM[1]) : null;
  chk('core.js carries the lazy map with routes + hashes', !!MAP && Object.keys(MAP.routes).length > 40 && Object.keys(MAP.v).length > 40);
  // ---- 2. deep links on a cold start ----
  const srv = await L.makeServer({ root: dist }); const srvSrc = await L.makeServer({ root: SRCWEB });
  for (const r of DEEP) {
    const { ctx, errs } = await L.newCtx(br, { noSW: true }); const p = await ctx.newPage();
    await p.goto(srv.url + '#/' + r); await p.waitForFunction(() => window.BOS_APP && document.querySelector('#app h1'), null, { timeout: 30000 }).catch(() => {});
    await p.waitForFunction((k) => window.BOS_LAZY && (window.BOS_LAZY.files(k).length === 0 || window.BOS_LAZY.files(k).every((f) => window.BOS_LAZY.loaded[f])), r, { timeout: 30000 }).catch(() => {});
    await p.waitForTimeout(500);
    const st = await p.evaluate((k) => ({ h1: (document.querySelector('#app h1') || {}).textContent, files: window.BOS_LAZY.files(k), loaded: window.BOS_LAZY.files(k).filter((f) => window.BOS_LAZY.loaded[f]).length, hash: location.hash }), r);
    chk(`deep link #/${r}: screen script(s) [${st.files.join(',')}] loaded, title "${(st.h1 || '').trim()}", no errors`, st.files.length > 0 && st.loaded === st.files.length && !!st.h1 && st.hash === '#/' + r && errs.length === 0, { st, errs: errs.slice(0, 2) });
    await ctx.close();
  }
  // ---- 3. every ia.js route: same title as the plain folder, no page errors ----
  async function sweep(S, label) {
    const { ctx, errs } = await L.newCtx(br, { noSW: true }); const p = await ctx.newPage();
    await p.goto(S.url + '#/home'); await p.waitForSelector('#app .tile', { timeout: 30000 });
    const routes = await p.evaluate(() => [...new Set((window.BOS.IA || []).map((r) => r.route))]);
    const titles = {};
    for (const r of routes) {
      await p.evaluate((h) => { location.hash = '#/' + h; }, r);
      await p.waitForFunction((h) => location.hash === '#/' + h, r).catch(() => {});
      // settle: no loading bar, the title stopped changing
      let prev = null, same = 0; for (let i = 0; i < 40 && same < 3; i++) { await p.waitForTimeout(120); const t = await p.evaluate(() => !document.documentElement.classList.contains('lz-busy') && ((document.querySelector('#app h1') || {}).textContent || '')); if (t !== false && t === prev) same++; else same = 0; prev = t; }
      titles[r] = (prev || '').trim();
    }
    return { routes, titles, errs, p, ctx };
  }
  const logAt = srv.log.length;
  const A = await sweep(srv, 'lazy'), B = await sweep(srvSrc, 'plain');
  const diff = A.routes.filter((r) => A.titles[r] !== B.titles[r]);
  chk(`all ${A.routes.length} ia.js routes: same screen title in the lazy build and in plain web/ (${diff.length} differ)`, diff.length === 0, diff.map((r) => [r, A.titles[r], B.titles[r]]).slice(0, 6));
  const blank = A.routes.filter((r) => !A.titles[r]); chk('no route is blank in the lazy build', blank.length === 0, blank.slice(0, 8));
  const realErr = (e) => !/Failed to load resource|ERR_|Refused to (load|connect)|favicon/i.test(e);
  const norm = (e) => e.split('\n')[0].replace(/https?:\/\/\S+/g, '').replace(/\s+/g, ' ');
  const ea = new Set(A.errs.filter(realErr).map(norm)), eb = new Set(B.errs.filter(realErr).map(norm)); const newErr = [...ea].filter((e) => !eb.has(e));
  chk(`no page error in the lazy build that the plain web/ folder does not have (${ea.size} vs ${eb.size} distinct mock-data errors)`, newErr.length === 0, newErr.slice(0, 4));
  // ---- 4. once only ----
  const reqs = {}; srv.log.slice(logAt).forEach((r) => { if (/\.js$/.test(r.p.split('?')[0]) && !/^\/(core|theme_glass|config)\.js|^\/vendor\//.test(r.p)) reqs[r.p] = (reqs[r.p] || 0) + 1; });
  const twice = Object.entries(reqs).filter(([, n]) => n > 1);
  chk('every script file was requested at most once during the sweep (cold, no cache)', twice.length === 0, twice.slice(0, 5));
  const tagsNow = await A.p.evaluate(() => [...document.querySelectorAll('script[src]')].map((s) => s.getAttribute('src')));
  chk('no duplicated <script src> in the page after the sweep (' + tagsNow.length + ' tags)', new Set(tagsNow).size === tagsNow.length);
  // revisit a route that has its own document listeners: no new listeners
  const cnt = await A.p.evaluate(async () => { let n = 0; const EA = EventTarget.prototype.addEventListener; EventTarget.prototype.addEventListener = function () { n++; return EA.apply(this, arguments); };
    const go = async (h) => { location.hash = '#/' + h; await new Promise((r) => setTimeout(r, 700)); };
    await go('employees'); const n0 = n; await go('home'); await go('employees'); await go('customers'); const n1 = n; await go('home'); await go('customers'); return { first: n0, afterRevisit: n - n1, total: n }; });
  chk('revisiting a screen adds no event listeners / handlers more than a plain redraw would (delta ' + cnt.afterRevisit + ')', cnt.afterRevisit <= 12, cnt);
  await A.ctx.close(); await B.ctx.close();
  // ---- 5. failed fetch -> retry screen ----
  {
    const { ctx, errs } = await L.newCtx(br, { noSW: true }); const p = await ctx.newPage();
    await p.goto(srv.url + '#/home'); await p.waitForSelector('#app .tile', { timeout: 30000 });
    const target = MAP.routes.employees[MAP.routes.employees.length - 1];
    await p.route(new RegExp(target.replace('.', '\\.') + '\\?v='), (r) => r.abort());
    await p.evaluate(() => { location.hash = '#/employees'; });
    await p.waitForSelector('#lz_fail', { timeout: 15000 }).catch(() => {});
    chk('a lazy script that cannot be fetched shows the retry screen (not a blank page)', (await p.locator('#lz_fail').count()) === 1);
    await p.unroute(new RegExp(target.replace('.', '\\.') + '\\?v='));
    await p.click('[data-act=lz_retry]'); await p.waitForFunction(() => (document.querySelector('#app h1') || {}).textContent && !document.querySelector('#lz_fail'), null, { timeout: 15000 }).catch(() => {});
    chk('Retry loads the screen', (await p.locator('#lz_fail').count()) === 0 && /./.test(await p.evaluate(() => (document.querySelector('#app h1') || {}).textContent || '')));
    await ctx.close();
  }
  srv.close(); srvSrc.close();
  // ---- 6/7. service worker: core only, offline POS after a cold start ----
  {
    const s2 = await L.makeServer({ root: dist }); const { ctx, errs } = await L.newCtx(br, {}); const p = await ctx.newPage();
    await p.goto(s2.url + '#/pos'); await p.waitForSelector('.pos-item', { timeout: 30000 });
    await p.waitForFunction(() => navigator.serviceWorker.controller, null, { timeout: 15000 }).catch(() => {}); await p.waitForTimeout(3500);
    await p.reload(); await p.waitForSelector('.pos-item', { timeout: 30000 }); await p.waitForTimeout(3500);
    const sw = await p.evaluate(async () => { const ks = await caches.keys(); const out = {}; for (const k of ks) out[k] = (await (await caches.open(k)).keys()).map((r) => r.url.replace(location.origin, '')); return out; });
    const ents = Object.values(sw)[0] || [];
    chk('SW cache after the first visits: one cache, core + css + decorators only (' + ents.length + ' entries)', Object.keys(sw).length === 1 && ents.length > 4 && ents.length < 30, ents.length);
    chk('SW cache holds core.js and index.html', ents.some((u) => /^\/core\.js\?v=/.test(u)) && ents.some((u) => /index\.html|^\/$/.test(u)), ents.slice(0, 6));
    chk('SW did NOT pre-download lazy screens (employees.js, accounts.js ...)', !ents.some((u) => /^\/(employees|accounts|partners|payroll)\.js/.test(u)), ents.filter((u) => /employees|accounts/.test(u)));
    await L.offline(ctx, s2, true);
    let shell = true; try { await p.reload({ timeout: 15000 }); await p.waitForFunction(() => window.BOS_APP, null, { timeout: 15000 }); } catch (e) { shell = false; }
    chk('offline cold start: app shell opens from the saved files', shell);
    let pos = false; try { await p.waitForSelector('.pos-item', { timeout: 15000 }); pos = true; } catch (e) { /* no */ }
    chk('offline cold start: POS shows its item cards', pos);
    if (pos) { await p.click('.pos-item >> nth=0'); await p.waitForTimeout(200); const q = await p.$('[data-act=pos_q_ok]'); if (q) await q.click(); await p.click('[data-act=pos_cart]'); await p.waitForSelector('#cart_ok'); await p.click('#cart_ok'); await p.waitForTimeout(800);
      const qn = await p.evaluate(() => JSON.parse(localStorage.getItem('bos_pos_queue_u1') || '[]').length); chk('offline sale is queued', qn === 1, qn); }
    if (shell) { await p.evaluate(() => { location.hash = '#/employees'; }); await p.waitForTimeout(1500);
      chk('a lazy screen opened offline says it needs internet (no blank page)', await p.locator('#cs_needs, #lz_fail').count() === 1); }
    await ctx.close(); s2.close();
  }
  console.log(`${pass} passed, ${failn} failed`);
  await br.close(); process.exit(failn ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
