// order_test.js: robust replacement for the brittle "X is the LAST script / LAST rec" assertions.
// Asserts the REAL invariants: required scripts present exactly once, load-order dependencies, theme css, ia.js ids unique, every route has a handler.
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const idx = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
let ok = 0, bad = 0; const chk = (n, c) => { if (c) ok++; else bad++; console.log((c ? 'PASS ' : 'FAIL ') + n); };
const scripts = [...idx.matchAll(/<script[^>]*\ssrc="([^"]+)"/g)].map((m) => m[1]);
const pos = (n) => scripts.indexOf(n);
const exists = (n) => fs.existsSync(path.join(ROOT, n));
// every script file that exists on disk and is a web module must be loaded at most once
const dup = scripts.filter((s, i) => scripts.indexOf(s) !== i);
chk('no script is loaded twice' + (dup.length ? ': ' + dup : ''), dup.length === 0);
const missing = scripts.filter((s) => !/^https?:/.test(s) && !exists(s));
chk('every local script in index.html exists on disk' + (missing.length ? ': ' + missing : ''), missing.length === 0);
// required scripts present exactly once
['entry.js', 'kbdfix.js', 'pos.js', 'posfail.js', 'ia.js', 'nav.js', 'integrations.js', 'setupadvisor.js', 'twofa.js', 'tpl_registry.js', 'landed.js', 'optionsx.js', 'itemimg.js']
  .forEach((s) => chk('required script ' + s + ' present exactly once', scripts.filter((x) => x === s).length === 1));
// load-order dependencies (A before B)
const before = (a, b) => chk(a + ' loads before ' + b, pos(a) >= 0 && pos(b) >= 0 && pos(a) < pos(b));
before('entry.js', 'pos.js');
before('entry.js', 'kbdfix.js'); before('kbdfix.js', 'pos.js');
before('pos.js', 'posfail.js');
before('integrations.js', 'setupadvisor.js'); before('integrations.js', 'twofa.js');
before('ia.js', 'nav.js');
before('landed.js', 'optionsx.js');
// charts.js / dashx.js exist only in some branches: when both are loaded charts must come first
if (pos('charts.js') >= 0 || pos('dashx.js') >= 0) before('charts.js', 'dashx.js'); else chk('charts.js/dashx.js not in this build (order check n/a)', true);
// templates: registry before every tpl_* consumer
const tpl = scripts.filter((s) => /^tpl_/.test(s) && s !== 'tpl_registry.js').concat(scripts.filter((s) => s === 'tplpicker.js'));
chk('tpl_registry.js before all tpl_* consumers (' + tpl.length + ')', pos('tpl_registry.js') >= 0 && tpl.length > 0 && tpl.every((s) => pos('tpl_registry.js') < pos(s)));
// theme css
const css = [...idx.matchAll(/<link[^>]*rel="stylesheet"[^>]*href="([^"]+)"/g)].map((m) => m[1]);
chk('theme.css loaded (exists on disk)', css.includes('theme.css') && exists('theme.css'));
chk('styles.css loaded before theme.css', css.indexOf('styles.css') >= 0 && css.indexOf('styles.css') < css.indexOf('theme.css'));
// ia.js: static record ids unique
const ia = fs.readFileSync(path.join(ROOT, 'ia.js'), 'utf8');
const ids = [...ia.matchAll(/^\s*rec\('([^']+)'/gm)].map((m) => m[1]);
const dids = ids.filter((s, i) => ids.indexOf(s) !== i);
chk('ia.js declares ' + ids.length + ' recs with unique ids' + (dids.length ? ': ' + dids : ''), ids.length > 50 && dids.length === 0);
['landed', 'optionsx', 'billpay', 'inboxpii', 'itemimg'].forEach((id) => { if (ia.includes("rec('" + id + "'")) chk("ia.js has rec '" + id + "' exactly once", ids.filter((x) => x === id).length === 1); });
// runtime: IA ids/routes unique and every live route has a handler
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const data = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
data.tables.option_lists = data.tables.option_lists || []; data.tables.location_settings = [];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const p = await (await br.newContext({ viewport: { width: 360, height: 760 } })).newPage();
  p.on('pageerror', (e) => errors.push(e.message));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
  await p.goto('http://localhost:' + PORT + '/#/home'); await p.waitForTimeout(1500);
  const r = await p.evaluate(() => {
    const IA = window.BOS.IA, pages = window.BOS_PAGES || {}, local = ['home', 'items', 'staff', 'matrix', 'rules', 'settings', 'logs', 'backup', 'itemreq'];
    const idl = IA.map((x) => x.id), rt = IA.map((x) => x.route);
    return { n: IA.length, dupId: idl.length - new Set(idl).size, dupRoute: rt.length - new Set(rt).size,
      noHandler: IA.filter((x) => x.status !== 'soon' && !local.includes(x.route.split('/')[0]) && !pages[x.route.split('/')[0]]).map((x) => x.route) };
  });
  chk('runtime IA has ' + r.n + ' records', r.n > 50);
  chk('runtime IA ids unique, routes unique', r.dupId === 0 && r.dupRoute === 0);
  chk('every non-soon route has a page handler' + (r.noHandler.length ? ': ' + r.noHandler : ''), r.noHandler.length === 0);
  chk('no page errors on load' + (errors.length ? ': ' + errors[0] : ''), errors.length === 0);
  console.log(ok + ' passed, ' + bad + ' failed'); await br.close(); srv.close(); process.exit(bad ? 1 : 0);
})();
