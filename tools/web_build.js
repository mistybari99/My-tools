#!/usr/bin/env node
// Web bundle builder (bos114, step WebLoad). Reads web/, writes dist/ (see tools/build_web.sh for the public-repo sync).
//   node tools/web_build.js [--src web] [--out dist] [--minify-only] [--no-minify]
// dist/ holds:
//   index.html     3 script tags (vendor/supabase.js, config.js, core.js) + one merged stylesheet; every local file has ?v=<its own content hash>
//   core.js        the scripts of the first download, minified and joined in the original index.html order, + lazy loader map (window.BOS_LAZY_MAP)
//   <name>.js      EVERY original script, minified, under its old name: the lazy screens (fetched when their route opens), the idle decorators, and (unused by the new index.html)
//                  the core ones, so an old cached index.html never meets a 404
//   app.css        styles.css + theme.css + controls.css + theme_glass.css, minified (the four originals are kept too, minified)
//   sw.js          VERSION = bos-sw-<build id>, PRECACHE = the exact offline-start file list
//   everything else from web/ that the old make_bundle published (images, manifest, vendor/, data/), unchanged
// --minify-only : same index.html as web/ (one tag per script), only minified + ?v stamped (used to prove the minifier alone changes no behaviour)
// --no-minify   : bundling and lazy map, files copied as they are (debugging)
// Deterministic: same input => same output bytes (no timestamps).
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const arg = (k, d) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : d; };
const flag = (k) => process.argv.includes(k);
const ROOT = path.resolve(__dirname, '..');
const SRC = path.resolve(arg('--src', path.join(ROOT, 'web'))), OUT = path.resolve(arg('--out', path.join(ROOT, 'dist')));
const MINIFY_ONLY = flag('--minify-only'), NOMIN = flag('--no-minify'), NOSTAMP = flag('--no-stamp');   // --no-stamp: no ?v= on any URL (test builds whose Playwright routes match plain file names)
const D = require('./web_deps.js');
function req(name, extra) { for (const p of [name, ...(extra || []).map((e) => path.join(e, name))]) { try { return require(p); } catch (e) { /* next */ } } return null; }
const NM = [process.env.WEB_BUILD_NM, '/opt/node-tools/node_modules', path.join(ROOT, 'tools/node_modules'), path.join(process.env.HOME || '', '.cache/bos-build/node_modules'), '/opt/node22/lib/node_modules'].filter(Boolean);
const terser = NOMIN ? null : req('terser', NM), esbuild = NOMIN ? null : req('esbuild', NM);
if (!NOMIN && !(terser && esbuild)) { console.error('terser / esbuild not found. Install once:  npm install --prefix ~/.cache/bos-build terser esbuild   (or set WEB_BUILD_NM=<node_modules dir>)'); process.exit(2); }
const sha = (b) => crypto.createHash('sha256').update(b).digest('hex');
const h10 = (b) => sha(b).slice(0, 10);
const html = fs.readFileSync(path.join(SRC, 'index.html'), 'utf8');
const tagRe = /<script\b[^>]*\ssrc="([^"?#]+)(?:\?[^"]*)?"[^>]*><\/script>\s*/g;
const allScripts = [...html.matchAll(tagRe)].map((m) => m[1]);
const local = allScripts.filter((u) => !/^(https?:)?\/\//.test(u));
const order = local.filter((f) => !/^vendor\//.test(f));      // scripts that share window.BOS (vendor/supabase.js is a library)
const dup = order.filter((f, i) => order.indexOf(f) !== i); if (dup.length) { console.error('duplicate <script src> in index.html:', dup); process.exit(3); }
const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'web_lazy.json'), 'utf8'));
const A = D.analyze(SRC, order), C = D.classify(A, cfg);
const HEAD_ONLY = ['theme_glass.js'];     // loaded in <head> (theme before first paint)
const SEPARATE = ['config.js'];           // the public repo keeps its own config.js: never merged into a bundle
const coreFiles = C.core.filter((f) => !HEAD_ONLY.includes(f) && !SEPARATE.includes(f));
const info = (m) => console.log(m);
info(`scripts ${order.length}: core ${C.core.length} (${coreFiles.length} in core.js), idle ${C.idle.length}, lazy-only ${C.lazy.length - C.idle.filter((f) => C.lazy.includes(f)).length}, routes ${Object.keys(C.routes).length}`);
for (const [f, w] of Object.entries(C.pulled)) info(`  pulled into core: ${f.padEnd(16)} ${w.join(' ')}`);
const reach = new Set([...C.idle, ...Object.values(C.routes).flat()]);
const orphans = C.lazy.filter((f) => !reach.has(f)); if (orphans.length && !MINIFY_ONLY) { console.error('lazy scripts that no route or idle list would ever load:', orphans, '\n -> add them to idle/attach in tools/web_lazy.json'); process.exit(4); }

// ---------- files ----------
fs.rmSync(OUT, { recursive: true, force: true }); fs.mkdirSync(OUT, { recursive: true });
const SKIP = /(^|\/)(.*_test\.js|.*\.test\.js|smoke\.js|stub\.js|.*\.(png|jpg|jpeg|gif|md|sh|sql|map))$/;
const files = []; (function walk(d, rel) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const r = rel ? rel + '/' + e.name : e.name; if (e.isDirectory()) walk(path.join(d, e.name), r); else files.push(r); } })(SRC, '');
files.sort();
const NODEY = /require\(['"](fs|path|http|child_process)['"]\)|^#!\/usr\/bin\/env node|module\.exports/m;
async function minJs(code, name) {
  if (NOMIN) return code;
  const r = await terser.minify({ [name]: code }, { compress: { passes: 1, ecma: 2020 }, mangle: { toplevel: false }, format: { comments: false, ecma: 2020 }, sourceMap: false });
  if (r.error) throw r.error; return r.code;
}
const outFiles = {};     // path -> Buffer
const put = (p, b) => { outFiles[p] = Buffer.isBuffer(b) ? b : Buffer.from(b); };
(async () => {
  const min = {};
  for (const f of files) {
    if (SKIP.test(f) || (f.endsWith('.html') && f !== 'index.html')) continue;
    const full = path.join(SRC, f);
    if (f.endsWith('.js') && !f.startsWith('vendor/') && f !== 'sw.js') {
      const code = fs.readFileSync(full, 'utf8');
      if (NODEY.test(code)) { console.error('node-style file in web/ (never publish):', f); process.exit(5); }
      min[f] = await minJs(code, f); put(f, min[f]);
    } else if (f.endsWith('.css')) { const css = fs.readFileSync(full, 'utf8'); min[f] = NOMIN ? css : esbuild.transformSync(css, { loader: 'css', minify: true }).code; put(f, min[f]); }
    else if (f !== 'index.html' && f !== 'sw.js') put(f, fs.readFileSync(full));
  }
  // the merged stylesheet, in index.html order
  const cssLinks = [...html.matchAll(/<link\b[^>]*rel="stylesheet"[^>]*\shref="([^"?#]+)"[^>]*>\s*/g)].map((m) => m[1]).filter((u) => !/^(https?:)?\/\//.test(u));
  if (!MINIFY_ONLY) { put('app.css', cssLinks.map((f) => min[f]).join('\n')); }
  // ---------- core.js ----------
  const lazyV = {};
  const urlHash = {}; // file -> 10 hex of the file as published
  for (const f of Object.keys(outFiles)) urlHash[f] = h10(outFiles[f]);
  if (!MINIFY_ONLY) {
    const parts = coreFiles.map((f) => min[f].replace(/\s*$/, '')), joined = parts.join(';\n');
    for (const f of [...Object.values(C.routes).flat(), ...C.idle]) lazyV[f] = urlHash[f];
    const map = { v: lazyV, routes: C.routes, idle: C.idle.filter((f) => !C.core.includes(f)) };
    const core = joined + ';\nwindow.BOS_LAZY_MAP=' + JSON.stringify(map) + ';\n';
    try { const ac = require('./web_deps.js'); void ac; require(NM.map((n) => path.join(n, 'acorn')).find((p) => fs.existsSync(p)) || 'acorn').parse(core, { ecmaVersion: 'latest', sourceType: 'script' }); }
    catch (e) { console.error('core.js does not parse as ONE script (two files declare the same top-level name?):', e.message); process.exit(6); }
    put('core.js', core);
    urlHash['core.js'] = h10(outFiles['core.js']); urlHash['app.css'] = h10(outFiles['app.css']);
  }
  // ---------- index.html ----------
  let ix = html;
  const stamp = (u) => (urlHash[u] && !NOSTAMP && !/^vendor\//.test(u) ? u + '?v=' + urlHash[u] : u);   // vendor/supabase.js is never stamped: the service worker serves it stale-while-revalidate
  const buildInputs = Object.keys(outFiles).sort().map((f) => f + ':' + urlHash[f]).join('\n');
  const BUILD = h10(buildInputs + '\n' + sha(fs.readFileSync(path.join(SRC, 'sw.js'))) + sha(html));
  if (!MINIFY_ONLY) for (const f of HEAD_ONLY) urlHash[f] = BUILD;   // the first script with ?v= is the one errlog.js reports as app_build: it carries the build id
  if (MINIFY_ONLY) {
    ix = ix.replace(tagRe, (m, u) => (/^(https?:)?\/\//.test(u) ? m : m.replace(u, stamp(u))));
    ix = ix.replace(/(<link\b[^>]*rel="stylesheet"[^>]*\shref=")([^"?#]+)"/g, (m, a, u) => (/^(https?:)?\/\//.test(u) ? m : a + stamp(u) + '"'));
  } else {
    const headTags = [], bodyTags = ['vendor/supabase.js', 'config.js', 'core.js'];
    ix = ix.replace(tagRe, (m, u) => (HEAD_ONLY.includes(u) ? m.replace(u, stamp(u)) : (/^(https?:)?\/\//.test(u) ? m : '')));
    // one stylesheet link where the first local one was; the others go
    let first = true;
    ix = ix.replace(/<link\b[^>]*rel="stylesheet"[^>]*\shref="([^"?#]+)"[^>]*>\s*/g, (m, u) => { if (/^(https?:)?\/\//.test(u)) return m; if (first) { first = false; return `<link rel="stylesheet" href="${stamp('app.css')}">\n`; } return ''; });
    const body = bodyTags.map((u) => `<script src="${stamp(u)}"></script>`).join('\n');
    ix = ix.replace('</body>', body + '\n</body>');
    // start fetching the core bundle as soon as the head is read
    ix = ix.replace(/(<meta name="viewport"[^>]*>)/, `$1\n<link rel="preload" as="script" href="${stamp('core.js')}">`);
    void headTags;
  }
  ix = ix.replace(/<!-- bos-build [0-9a-f]{10} -->\n?/g, '').replace('</head>', `<!-- bos-build ${BUILD} -->\n</head>`);
  put('index.html', ix);
  if (!MINIFY_ONLY) put('bundle-manifest.json', JSON.stringify({ build: BUILD, order, core: C.core, coreBundle: coreFiles, idle: C.idle, lazy: C.lazy, routes: C.routes, corePages: C.core.flatMap((f) => A.info[f].pages), pulled: C.pulled }, null, 1));
  // ---------- sw.js ----------
  let sw = fs.readFileSync(path.join(SRC, 'sw.js'), 'utf8');
  const s2 = sw.replace(/const VERSION = '[^']*';/, `const VERSION = 'bos-sw-${BUILD}';`); if (s2 === sw && !sw.includes(`bos-sw-${BUILD}'`)) { console.error('sw.js VERSION line not found'); process.exit(7); } sw = s2;
  if (!MINIFY_ONLY) {
    const pre = ['core.js', 'app.css', 'vendor/supabase.js', 'config.js', 'theme_glass.js', ...C.idle.filter((f) => !C.core.includes(f)), 'manifest.json', 'icon.svg', 'mark.svg', 'logo.webp', ...(cfg.precache || [])].filter((f, i, a) => a.indexOf(f) === i && f in outFiles).map(stamp);   // cfg.precache: explicit extra files kept for offline (camera helpers of X5)
    const s3 = sw.replace('const PRECACHE = null; /*bos114-precache*/', 'const PRECACHE = ' + JSON.stringify(pre) + ';'); if (s3 === sw) { console.error('sw.js PRECACHE marker not found'); process.exit(7); } sw = s3;
    info(`precache: ${pre.length} files`);
  }
  put('sw.js', NOMIN ? sw : (await terser.minify(sw, { compress: true, mangle: true, format: { comments: false } })).code);
  // ---------- write + checks ----------
  for (const [p, b] of Object.entries(outFiles)) { const fp = path.join(OUT, p); fs.mkdirSync(path.dirname(fp), { recursive: true }); fs.writeFileSync(fp, b); }
  let bad = 0;
  for (const m of ix.matchAll(/(?:src|href)="([^"?#:]+)(?:\?v=([0-9a-f]{10}))?"/g)) { const f = m[1]; if (/^(https?:|data:|#)/.test(f)) continue; if (!(f in outFiles)) { console.error('index.html references a missing file:', f); bad = 1; } else if (m[2] && m[2] !== urlHash[f]) { console.error('stale ?v for', f); bad = 1; } }
  if (!MINIFY_ONLY) { const need = new Set(); for (const r of Object.values(C.routes)) r.forEach((f) => need.add(f)); C.idle.forEach((f) => need.add(f)); for (const f of need) if (!(f in outFiles)) { console.error('lazy file missing in dist:', f); bad = 1; } }
  const sum = (arr) => arr.reduce((s, f) => s + (outFiles[f] ? outFiles[f].length : 0), 0), gz = (f) => require('zlib').gzipSync(outFiles[f], { level: 6 }).length;
  if (!MINIFY_ONLY) info(`core.js ${outFiles['core.js'].length} B raw, ${gz('core.js')} B gzip | app.css ${gz('app.css')} B gzip | all scripts raw ${sum(order)} B minified-individually`);
  info(`build ${BUILD}  files ${Object.keys(outFiles).length}  -> ${OUT}`);
  fs.writeFileSync(path.join(OUT, '.build-id'), BUILD + '\n');
  process.exit(bad);
})().catch((e) => { console.error(e); process.exit(1); });
