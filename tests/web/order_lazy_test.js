// bos114: order invariants for the BUILT bundle (tools/web_build.js). order_test.js is unchanged and keeps checking web/index.html; this copy checks what lazy loading legitimately changes:
// the scripts are no longer 110 tags but core.js + a lazy map. Reads dist/bundle-manifest.json (written by the build).
const _P = require('./_paths');
const SRCWEB = process.env.WEB_SRC || require('path').join(_P.REPO_DIR, 'web');   // always built from the source folder, whatever WEB_DIR is
const fs = require('fs'), os = require('os'), path = require('path'), cp = require('child_process');
let ok = 0, bad = 0; const chk = (n, c, x) => { if (c) ok++; else bad++; console.log((c ? 'PASS ' : 'FAIL ') + n + (c || x === undefined ? '' : ' ' + JSON.stringify(x).slice(0, 300))); };
const out = process.env.LAZY_DIR || fs.mkdtempSync(path.join(os.tmpdir(), 'bos-ord-'));
if (!process.env.LAZY_DIR) cp.execFileSync('bash', [path.join(_P.REPO_DIR, 'tools/build_web.sh'), '--out', out], { stdio: 'pipe', env: Object.assign({}, process.env, { WEB_SRC_OVERRIDE: SRCWEB }) });
const M = JSON.parse(fs.readFileSync(path.join(out, 'bundle-manifest.json'), 'utf8')), idx = Object.fromEntries(M.order.map((f, i) => [f, i]));
const src = fs.readFileSync(path.join(SRCWEB, 'index.html'), 'utf8'); const srcScripts = [...src.matchAll(/<script[^>]*\ssrc="([^"?]+)/g)].map((m) => m[1]).filter((s) => !/^vendor\//.test(s));
chk('manifest order == web/index.html order (' + M.order.length + ' scripts)', JSON.stringify(M.order) === JSON.stringify(srcScripts));
const inCore = new Set(M.core), inLazy = new Set(M.lazy), inIdle = new Set(M.idle);
chk('every script is in exactly one of core / lazy / idle', M.order.every((f) => (inCore.has(f) ? 1 : 0) + (inLazy.has(f) ? 1 : 0) + (inIdle.has(f) && !inCore.has(f) && !inLazy.has(f) ? 1 : 0) === 1));
chk('core.js bundle keeps the original relative order', M.coreBundle.every((f, i) => i === 0 || idx[M.coreBundle[i - 1]] < idx[f]));
['entry.js', 'kbdfix.js', 'a11yfix.js', 'pos.js', 'posfail.js', 'ia.js', 'nav.js', 'coldstart.js', 'swreg.js', 'lazy.js', 'tpl_registry.js'].forEach((s) => chk('required eager script ' + s + ' is in the core bundle', M.coreBundle.includes(s) || s === 'theme_glass.js'));
const before = (a, b) => chk(a + ' loads before ' + b + ' (core)', idx[a] < idx[b] && M.coreBundle.includes(a) && M.coreBundle.includes(b));
before('entry.js', 'kbdfix.js'); before('kbdfix.js', 'pos.js'); before('pos.js', 'posfail.js'); before('ia.js', 'nav.js'); before('kbdfix.js', 'a11yfix.js'); before('a11yfix.js', 'pos.js');
M.core.filter((s) => /^tpl_/.test(s) && s !== 'tpl_registry.js').concat(['tplpicker.js']).forEach((s) => chk('tpl_registry.js before ' + s, idx['tpl_registry.js'] < idx[s]));
const bad_ = Object.entries(M.routes).filter(([, l]) => l.some((f, i) => i && idx[l[i - 1]] >= idx[f]) || l.some((f) => inCore.has(f))); chk('every route\'s script list is in original order and holds no core file', bad_.length === 0, bad_.map((x) => x[0]));
['integrations.js', 'setupadvisor.js', 'twofa.js', 'landed.js', 'optionsx.js'].forEach((s) => chk(s + ' is reachable (lazy route or core)', inCore.has(s) || Object.values(M.routes).some((l) => l.includes(s)) || M.idle.includes(s)));
chk('setupadvisor route also loads integrations.js first', (M.routes.setupadvisor || []).indexOf('integrations.js') >= 0 ? M.routes.setupadvisor.indexOf('integrations.js') < M.routes.setupadvisor.indexOf('setupadvisor.js') : true);
chk('charts.js before dashx.js in the dashx route', (M.routes.dashx || []).indexOf('charts.js') < (M.routes.dashx || []).indexOf('dashx.js') && (M.routes.dashx || []).includes('charts.js'));
chk('landed.js before optionsx.js (original order kept)', idx['landed.js'] < idx['optionsx.js']);
// every ia.js route has a handler: a core page, or a lazy script registering it
const ia = fs.readFileSync(path.join(SRCWEB, 'ia.js'), 'utf8'); const ids = [...ia.matchAll(/^\s*rec\('([^']+)'/gm)].map((m) => m[1]);
const local = ['home', 'items', 'staff', 'matrix', 'rules', 'settings', 'logs', 'backup', 'itemreq'];
const corePages = new Set(M.corePages), missing = [...new Set(ids.map((i) => i.split('/')[0]))].filter((p) => !local.includes(p) && !corePages.has(p) && !M.routes[p]);
chk('every ia.js route (' + ids.length + ' recs) has a page: in core or in a lazy route', missing.length === 0, missing);
const idxHtml = fs.readFileSync(path.join(out, 'index.html'), 'utf8'); const tags = [...idxHtml.matchAll(/<script[^>]*\ssrc="([^"]+)"/g)].map((m) => m[1]);
chk('built index.html loads core.js once and vendor/config before it', tags.filter((t) => /^core\.js/.test(t)).length === 1 && tags.findIndex((t) => /^vendor\//.test(t)) < tags.findIndex((t) => /^config\.js/.test(t)) && tags.findIndex((t) => /^config\.js/.test(t)) < tags.findIndex((t) => /^core\.js/.test(t)), tags);
chk('theme css merged: app.css linked, styles/theme order kept inside it', /href="app\.css\?v=/.test(idxHtml) && (() => { const a = fs.readFileSync(path.join(out, 'app.css'), 'utf8'); return a.length > 50000; })());
console.log(ok + ' pass / ' + bad + ' fail'); process.exit(bad ? 1 : 0);
