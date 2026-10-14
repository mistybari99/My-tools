// English mode must contain no Bangla characters: checks the 2nd (English) title of every rec(...) line in ia.js and the 2nd argument of every B.L(bn, en, mix) call in the integrated web files.
// Run: node tests/web/lang_en_test.js
const _P = require('./_paths');
const fs = require('fs'), path = require('path');
const WEB = _P.WEB_DIR; const BN = /[ঀ-৿]/;
let bad = 0, n = 0;
const ia = fs.readFileSync(path.join(WEB, 'ia.js'), 'utf8');
for (const m of ia.matchAll(/rec\('([^']+)',\s*'[^']+',\s*\[\s*'[^']*',\s*'([^']*)'/g)) { n++; if (BN.test(m[2])) { bad++; console.log('FAIL ia.js rec ' + m[1] + ': ' + m[2]); } }
for (const f of ['accounts', 'recipebook', 'costing', 'costsources', 'costattrib', 's1setup', 'inbox', 'salesx', 'ia', 'dashx', 'dashx_metrics']) {
  const s = fs.readFileSync(path.join(WEB, f + '.js'), 'utf8');
  for (const m of s.matchAll(/B\.L\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'/g)) { n++; if (BN.test(m[2])) { bad++; console.log('FAIL ' + f + '.js B.L en: ' + m[2].slice(0, 70)); } }
}
console.log('checked ' + n + ' English strings, bangla found in ' + bad);
process.exit(bad ? 1 : 0);
