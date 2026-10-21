// Static dependency analysis of web/*.js (classic scripts that share window.BOS / window.BOS_APP / window.BOS_PAGES).
// Used by tools/web_build.js to decide which scripts can be loaded lazily. Pure analysis, writes nothing.
//   exports  : what a script puts on the shared objects  (B.x = ..., window.X = ..., Object.assign(H, {...}) action handlers, BOS_PAGES routes)
//   uses     : which OTHER scripts mention those names (B.x, window X, data-act="x" / H.x, BOS_PAGES.x)
//   wraps    : scripts that replace a route page or handler registered by an earlier script (they must stay in order with it)
// A script can only be lazy when no eager script mentions its exports (the build moves such scripts to the core automatically).
const fs = require('fs'), path = require('path');
let acorn; for (const p of ['acorn', '/opt/node-tools/node_modules/acorn', '/opt/node22/lib/node_modules/acorn']) { try { acorn = require(p); break; } catch (e) { /* next */ } }
if (!acorn) throw new Error('acorn not found (npm i acorn, or /opt/node-tools/node_modules)');

function walk(n, f) { if (!n || typeof n.type !== 'string') return; f(n); for (const k in n) { const v = n[k]; if (Array.isArray(v)) v.forEach((c) => c && typeof c.type === 'string' && walk(c, f)); else if (v && typeof v.type === 'string') walk(v, f); } }
const isId = (n, name) => n && n.type === 'Identifier' && n.name === name;
const member = (n) => { // "window.BOS_PAGES.x" -> ['window','BOS_PAGES','x'] (identifiers / string literals only)
  const out = []; while (n && n.type === 'MemberExpression') { out.unshift(n.computed ? (n.property.type === 'Literal' ? String(n.property.value) : '?') : n.property.name); n = n.object; }
  if (n && n.type === 'Identifier') out.unshift(n.name); else out.unshift('?'); return out; };
const keysOf = (o) => (o && o.type === 'ObjectExpression' ? o.properties.filter((p) => p.type === 'Property').map((p) => (p.key.type === 'Identifier' ? p.key.name : String(p.key.value))) : []);

function analyzeFile(code) {
  const ast = acorn.parse(code, { ecmaVersion: 'latest', sourceType: 'script', allowReturnOutsideFunction: true });
  const r = { pages: new Set(), pageWraps: new Set(), H: new Set(), B: new Set(), win: new Set() };
  walk(ast, (n) => {
    if (n.type === 'AssignmentExpression' && n.operator === '=') {
      const m = member(n.left);
      if (m[0] === 'window' && m.length === 2) { if (m[1] === 'BOS_PAGES') keysOf(n.right).forEach((k) => r.pages.add(k)); else r.win.add(m[1]); }
      if ((m[0] === 'window' && m[1] === 'BOS_PAGES' && m.length === 3) || (m[0] === 'BOS_PAGES' && m.length === 2)) r.pages.add(m[m.length - 1]);
      if ((m[0] === 'window' && m[1] === 'BOS' && m.length === 3) || (m[0] === 'B' && m.length === 2)) r.B.add(m[m.length - 1]);
      if (m[0] === 'H' && m.length === 2) r.H.add(m[1]);
    }
    if (n.type === 'CallExpression' && member(n.callee).join('.') === 'Object.assign' && n.arguments.length >= 2) {
      const t = member(n.arguments[0]).join('.');
      for (const a of n.arguments.slice(1)) {
        if (t === 'H' || t === 'A.H' || t === 'window.BOS_APP.H') keysOf(a).forEach((k) => r.H.add(k));
        if (t === 'B' || t === 'window.BOS') keysOf(a).forEach((k) => r.B.add(k));
        if (/BOS_PAGES/.test(t) || (n.arguments[0].type === 'LogicalExpression' && /BOS_PAGES/.test(code.slice(n.arguments[0].start, n.arguments[0].end)))) keysOf(a).forEach((k) => r.pages.add(k));
      }
    }
  });
  // screens registered through a helper: R.page({ route: 'prodplan', ... }) (web/rb4common.js)
  for (const m of code.matchAll(/\.page\(\s*\{\s*route:\s*['"]([A-Za-z0-9_]+)['"]/g)) r.pages.add(m[1]);
  // wrappers: a read of BOS_PAGES.<k> / (BOS_PAGES||{}).<k> that is also assigned by this file
  for (const m of code.matchAll(/(?:const|let|var)\s+\w+\s*=\s*\(?(?:window\.)?BOS_PAGES(?:\s*\|\|\s*\{\})?\)?\.(\w+)/g)) r.pageWraps.add(m[1]);
  return r;
}

// order: script file names in load order; dir: web dir. returns {order, info, uses, deps}
function analyze(dir, order) {
  const src = {}, info = {};
  for (const f of order) { src[f] = fs.readFileSync(path.join(dir, f), 'utf8'); const a = analyzeFile(src[f]); info[f] = { pages: [...a.pages], pageWraps: [...a.pageWraps], H: [...a.H], B: [...a.B], win: [...a.win] }; }
  const uses = {}, why = {};
  for (const f of order) {
    const s = new Set(), w = [];
    const add = (g, what) => { s.add(g); w.push(what + '<-' + g); };
    for (const n of new Set(info[f].B)) { const re = new RegExp('(?:BOS|\\bB)\\.' + n + '\\b|BOS\\[[\'"]' + n + '[\'"]\\]'); for (const g of order) if (g !== f && re.test(src[g])) add(g, 'B.' + n); }
    for (const n of new Set(info[f].win)) { if (['BOS_PAGES', 'BOS', 'BOS_APP', 'BOS_LAZY', 'BOS_LAZY_MAP'].includes(n) || n.length <= 3) continue; const re = new RegExp('\\b' + n + '\\b'); for (const g of order) if (g !== f && re.test(src[g])) add(g, 'W.' + n); }
    for (const n of new Set(info[f].H)) { const re = new RegExp('data-act=["\']' + n + '["\']|\\bH\\.' + n + '\\b|H\\[[\'"]' + n + '[\'"]\\]'); for (const g of order) if (g !== f && re.test(src[g])) add(g, 'H.' + n); }
    for (const n of new Set(info[f].pages)) { const re = new RegExp('BOS_PAGES\\.' + n + '\\b|BOS_PAGES\\[[\'"]' + n + '[\'"]\\]|\\bextra\\.' + n + '\\b'); for (const g of order) if (g !== f && re.test(src[g]) && !info[g].pages.includes(n)) add(g, 'page.' + n); }
    uses[f] = [...s]; why[f] = w;
  }
  return { order, info, uses, why, src };
}

// classify. cfg = { eager:[...], idle:[...], attach:{file:[route,...]} }
//   core  = cfg.eager + every script (transitively) mentioned by a core script's exports (auto-pulled; reasons returned)
//   idle  = cfg.idle that are not core: loaded after the first screen, in the background
//   lazy  = the rest, loaded when a route needs them (routes = pages it registers + routes of scripts that depend on it + cfg.attach)
function classify(A, cfg) {
  const { order, info, uses, why } = A, idx = Object.fromEntries(order.map((f, i) => [f, i]));
  for (const f of [...cfg.eager, ...cfg.idle]) if (!(f in idx)) throw new Error('web_lazy.json names a script that is not in index.html: ' + f);
  const core = new Set(cfg.eager), pulled = {};
  const ign = (a, b) => ((cfg.ignore || {})[b] || []).includes(a);   // ignore[consumer] = [exporters]: "consumer only names it, never calls it"
  for (let ch = true; ch;) { ch = false; for (const f of order) { if (core.has(f)) continue; const eu = uses[f].filter((g) => core.has(g) && !ign(f, g)); if (eu.length) { core.add(f); ch = true; pulled[f] = why[f].filter((x) => core.has(x.split('<-')[1])).slice(0, 3); } } }
  const idle = cfg.idle.filter((f) => !core.has(f));
  // an idle script that something else needs must be loaded with it (its users are lazy or idle); idle files are loaded in the background, so lazy users must also load them
  const lazy = order.filter((f) => !core.has(f) && !idle.includes(f));
  const loadWith = {};   // lazy/idle file -> files that must be loaded before it (lazy/idle scripts whose exports it mentions)
  for (const f of order) { if (core.has(f)) continue; loadWith[f] = order.filter((g) => !core.has(g) && g !== f && uses[g].includes(f) && !ign(g, f)).sort((a, b) => idx[a] - idx[b]); }
  // routes: page -> files
  const routeFiles = {};
  for (const f of order) { if (core.has(f)) continue; for (const p of info[f].pages) (routeFiles[p] = routeFiles[p] || new Set()).add(f); }
  for (const [r, fl] of Object.entries(cfg.attach || {})) for (const f of fl) if (!core.has(f)) (routeFiles[r] = routeFiles[r] || new Set()).add(f);
  for (const [r, fl] of Object.entries(cfg.routeNeeds || {})) for (const f of fl) if (!core.has(f)) (routeFiles[r] = routeFiles[r] || new Set()).add(f);
  const closure = (files) => { const out = new Set(), q = [...files]; while (q.length) { const f = q.pop(); if (out.has(f) || core.has(f)) continue; out.add(f); (loadWith[f] || []).forEach((g) => q.push(g)); } return [...out].sort((a, b) => idx[a] - idx[b]); };
  const routes = {}; for (const [p, fs_] of Object.entries(routeFiles)) routes[p] = closure(fs_);
  const idleAll = closure(idle);
  return { core: order.filter((f) => core.has(f)), idle: idleAll, lazy, routes, pulled, loadWith, idx };
}
module.exports = { analyze, classify, analyzeFile };
