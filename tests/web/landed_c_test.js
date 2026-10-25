// landed_c_test.js = landed_b_test.js with the two 'LAST' assertions adapted: step Img (phase102) appends the itemimg rec / script after the phase99 ones, by design. Everything else is identical.
// landed_b_test.js = landed_test.js with the two 'LAST' assertions adapted: step Opt (phase99) appends optionsx after landed, by design. Everything else is identical.
// Step Land (bos97): web/landed.js with mocked rpc, no browser. Run on its own: node tests/web/landed_test.js
// Language rule: every new string has bn / en / mix; the English text has no Bangla letters (the taka sign U+09F3 is the currency mark); unique data-act prefix lc_;
// the module touches no existing file (purchase.js is not edited); ia.js has the rec and index.html the script tag at the END.
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = path.join(__dirname, '..', '..', 'web');
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৲৴-৿]/;
const src = fs.readFileSync(path.join(ROOT, 'landed.js'), 'utf8');

function load(lang) {
  const handlers = {}, els = {}, mem = {};
  const A = { sb: { rpc: async () => ({ data: null, error: null }), from: () => ({ select: () => ({ order: async () => ({ data: [] }) }) }) }, S: { lang, ctx: { is_owner: true, profile: { id: 'u1' } } },
    esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])), toast() {}, fail() {}, shell() {}, openSheet() {}, closeSheet() {}, H: handlers, store: { get: (k) => mem[k], set: (k, v) => { mem[k] = v; } } };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en) };
  const document = { querySelector: () => null, getElementById: () => null, createElement: () => ({ style: {}, setAttribute() {} }), head: { appendChild() {} }, body: {}, addEventListener() {} };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, location: { hash: '#/landed' }, crypto: { randomUUID: () => 'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx' }, confirm: () => true, MutationObserver: undefined };
  const ctx = vm.createContext({ window: win, document, location: win.location, navigator: {}, setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {}, console, Promise, history: { replaceState() {} } });
  vm.runInContext(src, ctx);
  return { A, B, handlers, win };
}
const en = load('en'), bn = load('bn'), mix = load('mix');
const X = en.B.landed.X, ERR = en.B.landed.ERR;
const keys = Object.keys(X);
chk('has many strings', keys.length > 150);
chk('every string has bn, en and mix', keys.every((k) => X[k].bn && X[k].en && X[k].mix));
chk('English strings have no Bangla letters', keys.filter((k) => BN.test(X[k].en.replace(/৳/g, ''))).length === 0);
chk('English error strings have no Bangla letters', Object.keys(ERR).every((k) => !BN.test(ERR[k].en)));
chk('every error has bn, en and mix', Object.keys(ERR).every((k) => ERR[k].bn && ERR[k].en && ERR[k].mix));
chk('Bangla strings contain Bangla (except short technical ones)', keys.filter((k) => !BN.test(X[k].bn) && X[k].bn.length > 12).length === 0);
chk('mix: short technical labels may be plain English words; every long sentence is real Bng/Eng mix (has Bangla)', keys.filter((k) => !BN.test(X[k].mix) && X[k].mix.length > 45).length === 0);
chk('lab() follows the language: en / bn / mix give three different texts for the title', en.B.landed.T('title') === 'Landed cost' && BN.test(bn.B.landed.T('title')) && BN.test(mix.B.landed.T('title')) && en.B.landed.T('title') !== bn.B.landed.T('title'));
const H = en.handlers;
chk('all handlers are prefixed lc_', Object.keys(H).length >= 25 && Object.keys(H).every((k) => /^lc_/.test(k)));
chk('the page is registered as landed', typeof en.win.BOS_PAGES.landed === 'function');
chk('METHODS / LATE match the server choices', JSON.stringify(en.B.landed.METHODS) === JSON.stringify(['value', 'qty', 'weight', 'volume', 'manual', 'equal']) && en.B.landed.LATE.join() === 'split_remaining_and_cogs,post_to_remaining_stock,variance_account');
// every data-act used in the source is lc_ (or the shared go / closesheet of the shell)
const acts = [...src.matchAll(/data-act="([a-z_]+)"/g)].map((m) => m[1]);
chk('every data-act in the source is lc_ or a shell act', acts.length > 20 && acts.every((a) => /^lc_/.test(a) || a === 'go' || a === 'closesheet' || a === 'pu_postd'));   // pu_postd is only READ from the purchase page (a draft bill gets no landed button)
chk('every lc_ data-act has a handler', [...new Set(acts.filter((a) => /^lc_/.test(a)))].every((a) => typeof H[a] === 'function'));
// number helper and payload: Bangla digits, blank, bad
const num = en.B.landed.num;
chk('num: Bangla digits and commas', num('১২,৩৪.৫') === 1234.5 && num('') === null && Number.isNaN(num('abc')));
// existing files stay untouched by this step
const git = require('child_process').spawnSync('git', ['-C', path.join(ROOT, '..'), 'diff', '--name-only', 'origin/integration/p72-p79', '--', 'web/purchase.js', 'web/app.js', 'web/nav.js'], { encoding: 'utf8' });
chk('purchase.js, app.js and nav.js are not edited by this step', git.status !== 0 || git.stdout.trim() === '');
const ia = fs.readFileSync(path.join(ROOT, 'ia.js'), 'utf8'), idx = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
chk('ia.js has the landed rec, followed only by the three phase99 recs (optionsx, billpay, inboxpii) before the closing bracket', /rec\('landed', 'purch'[^\n]*\n  rec\('optionsx'[^\n]*\n  rec\('billpay'[^\n]*\n  rec\('inboxpii'[^\n]*\n  rec\('itemimg'[^\n]*\n\];\n\/\/ settings2 sub pages/.test(ia));
chk('index.html loads landed.js, then only optionsx.js (the last script)', /<script src="landed\.js"><\/script><script src="optionsx\.js"><\/script><script src="itemimg\.js"><\/script>\s*\n?<\/body>/.test(idx));
chk('the module does not use inline onclick / eval', !/onclick=|eval\(|new Function/.test(src));
console.log(`landed_test: ${pass} pass / ${failn} fail`);
process.exit(failn ? 1 : 0);
