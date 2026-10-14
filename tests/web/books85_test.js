// Phase 85 web pieces: new strings follow the language rule (English text has no Bangla characters, every string has all modes) and the 10-2 form has the optional pay_mode field.
// Run: node tests/web/books85_test.js
const _P = require('./_paths');
const fs = require('fs'), path = require('path');
const WEB = _P.WEB_DIR; const BN = /[ঀ-৿]/;
let n = 0, bad = 0;
const ck = (name, ok) => { n++; if (!ok) { bad++; console.log('FAIL ' + name); } };
const acc = fs.readFileSync(path.join(WEB, 'accounts.js'), 'utf8'), frm = fs.readFileSync(path.join(WEB, 'forms.js'), 'utf8');
const str = "'((?:[^'\\\\]|\\\\.)*)'";
for (const k of ['stock_adjust', 'stock_opening', 'stock_issue', 'stock_transfer', 'transit_loss', 'purchase_variance', 'card_settlement', 'reason_required', 'bad_reason', 'party_required', 'jreason']) {
  const m = acc.match(new RegExp('\\b' + k + ': L\\(' + str + ',\\s*' + str + ',\\s*' + str + '\\)'));
  ck('accounts.js has a 3-mode string for ' + k, !!m);
  if (m) { ck(k + ' English has no Bangla', !BN.test(m[2])); ck(k + ' Bangla/mix texts are not empty', m[1].length > 0 && m[3].length > 0); }
}
const pm = frm.match(new RegExp("SEL\\('pay_mode', L\\(" + str + ',\\s*' + str + '\\)'));
ck('forms.js 10-2 has the optional pay_mode select', !!pm);
if (pm) ck('pay_mode English label has no Bangla', !BN.test(pm[2]));
const opts = frm.match(/SEL\('pay_mode'[\s\S]*?\]\)\] \},/);
ck('pay_mode offers cash, bank, mobile, card', !!opts && ['cash', 'bank', 'mobile', 'card'].every((o) => opts[0].includes("['" + o + "'")));
ck('pay_mode is not required (empty = cash as before)', !!opts && !/req:\s*true/.test(opts[0]));
ck('p_reason is sent only when a reason is picked (old databases keep working)', /\.\.\.\(\(\$\('#ac_jreason'\) \|\| \{\}\)\.value \? \{ p_reason/.test(acc));
console.log('checked ' + n + ', failed ' + bad);
process.exit(bad ? 1 : 0);
