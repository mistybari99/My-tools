#!/usr/bin/env node
/* UI inventory helper (read-only). Loads the browser scripts of web/ in the same order as web/index.html inside a
   throw-away node `vm` sandbox with a "ghost" DOM (every unknown browser object answers with a harmless no-op),
   then prints, as JSON on stdout, the DATA the scripts build at load time:
   route registry (BOS.IA), paper-form specs (BOS.forms), settings catalogue (BOS.SETTING_DEFS), i18n texts (BOS_T),
   registered screens (BOS_PAGES). It never touches a network or a database and writes nothing.
   Usage: node tools/ui_inventory_runtime.js <web dir>
   Requires only the preinstalled node (no npm packages). Called by tools/build_ui_inventory.py. */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const WEB = path.resolve(process.argv[2] || path.join(__dirname, '..', 'web'));
const problems = [];

// ---- ghost: callable, chainable, never throws, never "thenable" ----
function makeGhost() {
  const target = function () {};
  const handler = {
    get(_t, k) {
      if (k === 'then') return undefined;
      if (k === Symbol.toPrimitive) return () => '';
      if (k === Symbol.iterator) return function* () {};
      if (k === 'length') return 0;
      if (k === 'toString' || k === 'toJSON') return () => '';
      return ghost;
    },
    apply() { return ghost; },
    construct() { return ghost; },
    set() { return true; },
    has() { return false; },
  };
  const ghost = new Proxy(target, handler);
  return ghost;
}
const ghost = makeGhost();

const store = {};
const sandbox = {
  console: { log() {}, warn() {}, error() {}, info() {}, debug() {} },
  setTimeout: () => 0, setInterval: () => 0, clearTimeout() {}, clearInterval() {},
  requestAnimationFrame: () => 0, cancelAnimationFrame() {}, queueMicrotask() {},
  Promise, Map, Set, WeakMap, WeakSet, Symbol, JSON, Math, Date, Intl, RegExp, Error, TypeError, RangeError,
  Object, Array, String, Number, Boolean, Function, parseInt, parseFloat, isNaN, isFinite, encodeURIComponent, decodeURIComponent, encodeURI, decodeURI,
  Uint8Array, ArrayBuffer, Float64Array, BigInt, Reflect, Proxy,
  URL, URLSearchParams, TextEncoder, TextDecoder,
  localStorage: { getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); }, removeItem: (k) => { delete store[k]; } },
  document: ghost, navigator: ghost, location: ghost, history: ghost, screen: ghost, fetch: () => Promise.resolve(ghost),
  matchMedia: () => ghost, addEventListener() {}, removeEventListener() {}, dispatchEvent() {},
  Image: function () { return ghost; }, FileReader: function () { return ghost; }, Blob: function () { return ghost; },
  XMLHttpRequest: function () { return ghost; }, indexedDB: ghost, crypto: ghost, performance: { now: () => 0 }, alert() {}, confirm: () => false, prompt: () => null,
  supabase: { createClient: () => ({ auth: ghost, rpc: () => Promise.resolve({ data: null, error: null }), from: () => ghost, storage: ghost, channel: () => ghost, functions: ghost }) },
};
sandbox.window = sandbox; sandbox.self = sandbox; sandbox.globalThis = sandbox;
const ctx = vm.createContext(sandbox);

// unknown free identifiers resolve to the ghost (so a script never dies on a browser API we did not list)
const ghostScope = new Proxy({}, {
  has(_t, k) { return typeof k === 'string' && !(k in sandbox) && k !== 'undefined' && k !== 'arguments' && !/^(Infinity|NaN|eval)$/.test(k); },
  get(_t, k) { return k === Symbol.unscopables ? undefined : ghost; },
});
sandbox.__ghostScope = ghostScope;

function run(file, src) {
  try {
    vm.runInContext('with (__ghostScope) {\n' + src + '\n}', ctx, { filename: file, timeout: 8000 });
  } catch (e) {
    problems.push(file + ': ' + String(e && e.message).slice(0, 160));
  }
}

// script order from index.html (first use), then any remaining web/*.js not listed there
const html = fs.readFileSync(path.join(WEB, 'index.html'), 'utf8');
const order = []; let m; const re = /<script[^>]*\ssrc="([^"?]+)[^"]*"/g;
while ((m = re.exec(html))) if (!order.includes(m[1])) order.push(m[1]);
const skip = new Set(['vendor/supabase.js', 'sw.js', 'swreg.js']);
const loaded = [];
for (const f of order) {
  if (skip.has(f) || !f.endsWith('.js')) continue;
  const p = path.join(WEB, f); if (!fs.existsSync(p)) { problems.push(f + ': listed in index.html but missing'); continue; }
  run(f, fs.readFileSync(p, 'utf8')); loaded.push(f);
}
const notInIndex = fs.readdirSync(WEB).filter((f) => f.endsWith('.js') && !order.includes(f) && !skip.has(f)).sort();
for (const f of notInIndex) { run(f, fs.readFileSync(path.join(WEB, f), 'utf8')); loaded.push(f); }

// ---- serialise ----
const fnSrc = (f) => String(f).replace(/\s+/g, ' ').trim();
function plain(v, depth) {
  depth = depth || 0;
  if (depth > 12) return '[deep]';
  if (typeof v === 'function') { try { return { $fn: fnSrc(v) }; } catch (e) { return { $fn: '?' }; } }
  if (v === null || typeof v === 'boolean' || typeof v === 'number') return v;
  if (typeof v === 'string') return v;
  if (v === undefined) return undefined;
  if (Array.isArray(v)) return v.map((x) => plain(x, depth + 1));
  if (typeof v === 'object') {
    if (v instanceof Map) return { $map: Array.from(v.keys()).sort() };
    if (v instanceof Set) return { $set: Array.from(v).sort() };
    const o = {}; for (const k of Object.keys(v)) { const x = plain(v[k], depth + 1); if (x !== undefined) o[k] = x; } return o;
  }
  return String(v);
}
// call an option generator safely (options may be a function that reads the live environment)
function resolveOptions(opt) {
  if (typeof opt !== 'function') return { value: plain(opt), dynamic: false };
  try {
    const r = opt({ s: {}, d: {}, c: {}, v: {}, env: {}, cf: false });
    if (Array.isArray(r)) return { value: plain(r), dynamic: true, src: fnSrc(opt) };
    return { value: null, dynamic: true, src: fnSrc(opt) };
  } catch (e) { return { value: null, dynamic: true, src: fnSrc(opt), error: String(e.message).slice(0, 80) }; }
}
function field(f, walk) {
  const o = {};
  for (const k of Object.keys(f)) {
    if (k === 'options') o.options = resolveOptions(f.options);
    else if (k === 'cols') o.cols = f.cols.map((c) => field(c));
    else o[k] = plain(f[k]);
  }
  return o;
}
const B = sandbox.BOS || {};
const forms = {};
for (const code of Object.keys(B.forms || {})) {
  const sp = B.forms[code]; const o = {};
  for (const k of Object.keys(sp)) {
    if (k === 'head') o.head = (sp.head || []).map((f) => field(f));
    else if (k === 'sections') o.sections = (sp.sections || []).map((s) => { const so = {}; for (const kk of Object.keys(s)) so[kk] = kk === 'fields' ? (s.fields || []).map((f) => field(f)) : plain(s[kk]); return so; });
    else o[k] = plain(sp[k]);
  }
  forms[code] = o;
}
const IA = (B.IA || []).map((r) => plain(r));
const out = {
  loaded, not_in_index: notInIndex, problems,
  ia: IA,
  ia_extra: B.ia ? {
    groups: plain(B.ia.GROUPS), area_g: plain(B.ia.AREA_G), quick_by: plain(B.ia.QUICK_BY), slots_by: plain(B.ia.SLOTS_BY),
    dof: plain(B.ia.DOF), home_keys: (() => { const r = {}; for (const mm of ['biz', 'acc']) { try { r[mm] = B.ia.homeKeys(mm); } catch (e) { r[mm] = null; } } return r; })(),
    do_recs: (() => { try { return plain(B.ia.doRecs()); } catch (e) { return null; } })(),
  } : null,
  forms,
  setting_defs: plain(B.SETTING_DEFS || []),
  setting_groups: plain(B.GROUPS || {}),
  i18n: plain(sandbox.BOS_T || {}),
  pages: Object.keys(sandbox.BOS_PAGES || {}).sort(),
  form_pages: Object.keys(B.forms || {}).sort(),
};
const buf = Buffer.from(JSON.stringify(out), 'utf8');
let off = 0;
while (off < buf.length) { try { off += fs.writeSync(1, buf, off, buf.length - off); } catch (e) { if (e.code !== 'EAGAIN') throw e; } }
process.exit(0);
