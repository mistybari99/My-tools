// Static language lint over EVERY web/*.js: each L(bn, en, mix) call, {bn,en,mix} object tables, and SQL seed label_en/hint_en columns.
// Pre-existing violations live in lang_baseline.json (key = sha1(file|rule|string) -> count); the test fails ONLY on violations beyond the baseline.
// Run: node tests/web/lang_all_test.js          Rebuild baseline (deliberate, reviewed): LANG_BASELINE_WRITE=1 node tests/web/lang_all_test.js
// WEB_DIR / SQL_DIR env override the scanned folders (used to prove detection on a temp copy).
const _P = require('./_paths');
const fs = require('fs'), path = require('path'), crypto = require('crypto');
let acorn; for (const p of ['acorn', '/opt/node-tools/node_modules/acorn']) { try { acorn = require(p); break; } catch (e) { } }
if (!acorn) { console.log('FAIL acorn parser not found (npm i acorn or /opt/node-tools/node_modules)'); process.exit(1); }
const WEB = _P.WEB_DIR, SQL = process.env.SQL_DIR ? path.resolve(process.env.SQL_DIR) : path.join(_P.REPO_DIR, 'supabase');
const BASE = path.join(__dirname, 'lang_baseline.json');
const BN = /[ঀ-৿]/, LATIN = /[A-Za-z]/;
const viol = []; // {file, rule, str, line}
let strings = 0, calls = 0, dynamic = 0, tables = 0, bnLatinOnly = 0, sqlCells = 0, parseFail = 0;
const add = (file, rule, str, line) => viol.push({ file, rule, str: String(str), line });

function lit(n) { // fold string literals / no-expr templates / '+' concatenation; undefined when dynamic
  if (!n) return undefined;
  if (n.type === 'Literal') return typeof n.value === 'string' ? n.value : undefined;
  if (n.type === 'TemplateLiteral' && n.expressions.length === 0) return n.quasis[0].value.cooked;
  if (n.type === 'BinaryExpression' && n.operator === '+') { const a = lit(n.left), b = lit(n.right); return a !== undefined && b !== undefined ? a + b : undefined; }
  return undefined;
}
function walk(n, f, parent) { if (!n || typeof n.type !== 'string') return; f(n, parent); for (const k in n) { if (k === 'loc') continue; const v = n[k]; if (Array.isArray(v)) v.forEach((c) => c && c.type && walk(c, f, n)); else if (v && typeof v.type === 'string') walk(v, f, n); } }
const isL = (c) => (c.type === 'Identifier' && c.name === 'L') || (c.type === 'MemberExpression' && !c.computed && c.property.name === 'L');
function checkSlots(file, line, bn, en, mix, what) {
  strings += [bn, en, mix].filter((x) => x !== undefined).length;
  if (en !== undefined) { if (BN.test(en)) add(file, 'en-has-bangla', en, line); if (!en.trim()) add(file, 'en-empty', what + '@' + line, line); }
  if (mix !== undefined && !mix.trim()) add(file, 'mix-empty', what + '@' + (bn || '').slice(0, 40), line);
  if (bn !== undefined) { if (!bn.trim()) add(file, 'bn-empty', what + '@' + (en || '').slice(0, 40), line); else if (!BN.test(bn) && LATIN.test(bn)) bnLatinOnly++; } // policy: report only
}
const files = fs.readdirSync(WEB).filter((f) => f.endsWith('.js')).sort();
for (const f of files) {
  const src = fs.readFileSync(path.join(WEB, f), 'utf8'); let ast;
  for (const st of ['script', 'module']) { try { ast = acorn.parse(src, { ecmaVersion: 'latest', sourceType: st, locations: true, allowHashBang: true, allowReturnOutsideFunction: true }); break; } catch (e) { ast = null; if (st === 'module') { parseFail++; console.log('FAIL cannot parse ' + f + ': ' + e.message); } } }
  if (!ast) continue;
  walk(ast, (n) => {
    if (n.type === 'CallExpression' && isL(n.callee)) {
      calls++; const a = n.arguments; const line = n.loc.start.line;
      if (a.some((x) => x.type === 'SpreadElement')) { dynamic++; return; }
      const v = a.map(lit);
      if (a.length < 3) add(f, 'L-missing-mix(' + a.length + ' args)', v.map((x) => x === undefined ? '<dyn>' : x).join('|'), line);
      if (v.every((x) => x === undefined)) { dynamic++; return; }
      if (v.some((x) => x === undefined)) dynamic++;
      checkSlots(f, line, v[0], v[1], v[2], 'L');
    } else if (n.type === 'ObjectExpression') { // label tables: { bn:'..', en:'..', mix:'..' } literal objects (fed to L / lab / tables)
      const p = {}; for (const pr of n.properties) if (pr.type === 'Property' && !pr.computed) { const k = pr.key.name || pr.key.value; if (k === 'bn' || k === 'en' || k === 'mix') p[k] = lit(pr.value); }
      if (p.bn !== undefined && p.en !== undefined) { tables++; checkSlots(f, n.loc.start.line, p.bn, p.en, p.mix, 'obj'); }
    }
  });
}
// ---- SQL seeds: label_en / hint_en columns of INSERT ... VALUES rows in phase72..103
function sqlTuples(s, start) { // parse (a,b,...),(...) from index of first '(' after VALUES until ';' at depth 0; returns array of arrays of raw cell strings
  const rows = []; let i = start, depth = 0, cell = '', row = null, inq = false;
  for (; i < s.length; i++) {
    const c = s[i];
    if (inq) { cell += c; if (c === "'") { if (s[i + 1] === "'") { cell += "'"; i++; } else inq = false; } continue; }
    if (c === "'") { inq = true; cell += c; continue; }
    if (c === '-' && s[i + 1] === '-') { while (i < s.length && s[i] !== '\n') i++; continue; }
    if (c === '(') { depth++; if (depth === 1) { row = []; cell = ''; continue; } }
    if (c === ')') { depth--; if (depth === 0) { row.push(cell.trim()); rows.push(row); row = null; cell = ''; continue; } }
    if (c === ',' && depth === 1) { row.push(cell.trim()); cell = ''; continue; }
    if (c === ';' && depth === 0) break;
    if (depth >= 1) cell += c;
  }
  return rows;
}
const sqlFiles = fs.existsSync(SQL) ? fs.readdirSync(SQL).filter((f) => { const m = /^phase(\d+)[a-z]?\.sql$/.exec(f); return m && +m[1] >= 72 && +m[1] <= 103; }).sort() : [];
for (const f of sqlFiles) {
  const s = fs.readFileSync(path.join(SQL, f), 'utf8'); const re = /insert\s+into\s+[\w."]+\s*\(([^)]*)\)\s*values/gi; let m;
  while ((m = re.exec(s))) {
    const cols = m[1].split(',').map((x) => x.trim().toLowerCase()); const idx = ['label_en', 'hint_en'].map((c) => cols.indexOf(c));
    if (idx.every((x) => x < 0)) continue;
    for (const row of sqlTuples(s, re.lastIndex)) cols.forEach((c, k) => {
      if ((c !== 'label_en' && c !== 'hint_en') || row.length !== cols.length) return;
      const cellv = row[k]; if (!/^'/.test(cellv)) return; sqlCells++;
      const val = cellv.slice(1, -1).replace(/''/g, "'");
      if (BN.test(val)) add('sql:' + f, 'sql-' + c + '-has-bangla', val, 0);
      else if (c === 'label_en' && !val.trim()) add('sql:' + f, 'sql-label_en-empty', cols[0] + '=' + row[0], 0);
    });
  }
}
// ---- baseline compare
const h = (v) => crypto.createHash('sha1').update(v.file + '|' + v.rule + '|' + v.str).digest('hex').slice(0, 16);
const cur = {}, perFile = {};
for (const v of viol) { const k = h(v); (cur[k] = cur[k] || { file: v.file, rule: v.rule, sample: v.str.slice(0, 60), count: 0 }).count++; perFile[v.file] = (perFile[v.file] || 0) + 1; }
if (process.env.LANG_BASELINE_WRITE) { fs.writeFileSync(BASE, JSON.stringify({ note: 'Pre-existing language violations (do not edit old texts). key=sha1(file|rule|string)[0:16]. Rebuild: LANG_BASELINE_WRITE=1 node tests/web/lang_all_test.js', total: viol.length, violations: cur }, null, 1) + '\n'); console.log('baseline written: ' + viol.length + ' violations'); }
const base = JSON.parse(fs.readFileSync(BASE, 'utf8')).violations;
let fresh = 0; const freshList = [];
for (const k in cur) { const extra = cur[k].count - (base[k] ? base[k].count : 0); if (extra > 0) { fresh += extra; freshList.push(cur[k].file + ' [' + cur[k].rule + '] ' + cur[k].sample); } }
let fixed = 0; for (const k in base) fixed += Math.max(0, base[k].count - (cur[k] ? cur[k].count : 0));
console.log('--- baseline violations per file (informational) ---');
Object.keys(perFile).sort().forEach((f) => console.log('  ' + f.padEnd(34) + perFile[f]));
console.log('scanned ' + files.length + ' web files, ' + calls + ' L() calls (' + dynamic + ' with dynamic args), ' + tables + ' {bn,en} tables, ' + strings + ' strings, ' + sqlFiles.length + ' sql files / ' + sqlCells + ' label_en|hint_en cells');
console.log('policy report (not enforced): ' + bnLatinOnly + ' bn slots are Latin-only');
console.log('violations now ' + viol.length + ', baseline ' + Object.values(base).reduce((a, b) => a + b.count, 0) + ', NEW ' + fresh + ', fixed-since-baseline ' + fixed);
freshList.forEach((x) => console.log('FAIL NEW ' + x));
if (parseFail) { console.log('FAIL ' + parseFail + ' files unparsable'); }
process.exit(fresh || parseFail ? 1 : 0);
