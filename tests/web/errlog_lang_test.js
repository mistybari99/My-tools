// English mode must contain no Bangla in web/errlog.js (every B.L(bn, en, mix) 2nd argument) and in the two ia.js recs it adds; Bangla/mix strings must exist (3 arguments).
// Run: node tests/web/errlog_lang_test.js
const _P = require('./_paths');
const fs = require('fs'), path = require('path');
const BN = /[ঀ-৿]/; let bad = 0, n = 0;
const chk = (c, m) => { if (!c) { bad++; console.log('FAIL ' + m); } };
const js = fs.readFileSync(path.join(_P.WEB_DIR, 'errlog.js'), 'utf8');
const Ls = [...js.matchAll(/L\(\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*,\s*'((?:[^'\\]|\\.)*)'\s*\)/g)];
chk(Ls.length >= 35, 'errlog.js has the expected number of L(bn, en, mix) texts (' + Ls.length + ')');
for (const m of Ls) { n++; chk(!BN.test(m[2]), 'errlog.js English text has Bangla: ' + m[2].slice(0, 60)); chk(m[2].trim() !== '' && m[3].trim() !== '', 'empty en/mix text: ' + m[1].slice(0, 40)); chk(/'/.test(m[2]) === false, 'apostrophe in English text'); }
const open = (js.match(/\bL\(/g) || []).length - 1;    // minus the "const L = B.L" mention is not matched by \bL\( ; keep a sanity bound
chk(Ls.length >= open - 2, 'every L(...) call in errlog.js has exactly three string arguments (' + Ls.length + ' of ' + open + ')');
const ia = fs.readFileSync(path.join(_P.WEB_DIR, 'ia.js'), 'utf8');
for (const id of ['reportproblem', 'problems']) {
  const m = ia.match(new RegExp("rec\\('" + id + "',\\s*'[^']+',\\s*\\[\\s*'([^']*)',\\s*'([^']*)',\\s*'([^']*)'"));
  n++; chk(!!m, 'ia.js rec ' + id + ' exists'); if (m) { chk(!BN.test(m[2]), 'ia.js ' + id + ' English title has Bangla'); chk(BN.test(m[1]) && /[ঀ-৿]/.test(m[3]) && /[A-Za-z]/.test(m[3]), 'ia.js ' + id + ' bn is Bangla and mix is Bng/Eng'); }
}
// data-act names added by errlog.js all start with er_
const acts = [...js.matchAll(/data-act="([a-z_]+)"/g)].map((m) => m[1]).concat([...js.matchAll(/setAttribute\('data-act', '([a-z_]+)'\)/g)].map((m) => m[1]));
chk(acts.length >= 6 && acts.every((a) => /^er_/.test(a)), 'every data-act in errlog.js starts with er_: ' + [...new Set(acts)]);
const H = [...js.matchAll(/^\s{2}(er_[a-z]+):/gm)].map((m) => m[1]); chk(H.length >= 6 && H.every((h) => new Set(acts).has(h)), 'handler names match the data-act names: ' + H);
console.log('checked ' + n + ' items, problems: ' + bad); process.exit(bad ? 1 : 0);
