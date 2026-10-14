// Step Q4 (bos107): static + mocked-rpc checks for landed_q4.js, badges107.js, setupundo.js and the three tagged edits. No browser: node tests/web/q4_test.js
// Language rule: every string has bn / en / mix, English has no Bangla letters; unique data-act prefix q4_; scripts appended at the END of index.html; no conflict markers.
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = path.join(__dirname, '..', '..', 'web');
let pass = 0, failn = 0; const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৲৴-৿]/;
const rd = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');
function load(file, lang, extra = {}) {
  const handlers = {}, calls = [], toasts = [];
  const rpcMap = extra.rpc || {};
  const A = { sb: { rpc: async (fn, a) => { calls.push([fn, a]); const r = rpcMap[fn]; if (r instanceof Error) return { data: null, error: r }; return { data: typeof r === 'function' ? r(a) : r === undefined ? null : r, error: null }; }, from: () => ({ select: () => ({ eq: () => ({ eq: () => ({ limit: async () => ({ data: [] }) }) }) }) }) },
    S: { lang, ctx: { is_owner: extra.owner !== false, profile: { id: 'u1' } } }, esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])), toast: (m) => toasts.push(m), openSheet: (h) => { A._sheet = h; }, closeSheet() {}, H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = Object.assign({ L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en) }, extra.B || {});
  const doc = { querySelector: () => null, querySelectorAll: () => [], getElementById: () => null, createElement: () => ({ style: {}, setAttribute() {} }), head: { appendChild() {} }, body: {}, addEventListener() {} };
  const win = Object.assign({ BOS_APP: A, BOS: B, BOS_PAGES: {}, location: { hash: '#/home' }, MutationObserver: undefined }, extra.win || {});
  const ctx = vm.createContext({ window: win, document: doc, location: win.location, setTimeout, clearTimeout, console, Promise, JSON, Set, Number, String, Object, Array, Math, Date });
  vm.runInContext(rd(file), ctx);
  return { A, B, handlers, win, calls, toasts };
}
const landedStub = { landed: { _state: () => ({ pick: [], info: { mode: 'per_shipment' } }) } };
const files = [['landed_q4.js', 'landedQ4', { B: landedStub }], ['badges107.js', 'badges107', {}], ['setupundo.js', 'setupundo', {}]];
for (const [f, key, extra] of files) {
  const ms = ['en', 'bn', 'mix'].map((l) => load(f, l, extra));
  const X = ms[0].B[key].X, ks = Object.keys(X);
  chk(f + ': module registered', !!ms[0].B[key] && ks.length >= 7);
  chk(f + ': every string has bn, en, mix', ks.every((k) => X[k].bn && X[k].en && X[k].mix));
  chk(f + ': English strings have no Bangla letters', ks.every((k) => !BN.test(X[k].en)));
  chk(f + ': Bangla strings have Bangla (long ones)', ks.filter((k) => !BN.test(X[k].bn) && X[k].bn.length > 12).length === 0);
  chk(f + ': long mix sentences are real Bng/Eng mix', ks.filter((k) => !BN.test(X[k].mix) && X[k].mix.length > 30).length === 0);
  const src = rd(f);
  const acts = [...src.matchAll(/data-act="([a-z_0-9]+)"/g)].map((m) => m[1]);
  chk(f + ': every data-act is q4_ (or the shell closesheet)', acts.length >= 1 && acts.every((a) => /^q4_/.test(a) || a === 'closesheet'));
  chk(f + ': every q4_ act has a handler', [...new Set(acts.filter((a) => /^q4_/.test(a)))].every((a) => typeof ms[0].handlers[a] === 'function'));
  chk(f + ': all handlers are q4_', Object.keys(ms[0].handlers).every((k) => /^q4_/.test(k)));
  chk(f + ': no inline onclick / eval', !/onclick=|eval\(|new Function/.test(src));
}
// badges: specs and which screens they open
const bd = load('badges107.js', 'en', {}).B.badges107;
chk('badges: seven specs, each opens a real route', bd.SPECS.map((s) => s.route).join() === 'ledgerlinks,books96,books85,unmatched,costunknown,billpay,inbox');
const ia = rd('ia.js'); chk('badges: every route is a live IA record', bd.SPECS.every((s) => new RegExp("rec\\('" + s.route + "'").test(ia)));
(async () => {
  // each spec reads the documented rpc and its documented field; a missing function throws (the caller hides the chip)
  const run = async (id, rpc) => { const m = load('badges107.js', 'en', { rpc }); return m.B.badges107.SPECS.find((s) => s.id === id).get(); };
  chk('ledger: int', await run('ledger', { ledger_problem_count: 4 }) === 4);
  chk('costwait: total', await run('costwait', { cost_wait_list96: { total: 7 } }) === 7);
  chk('autopost: old_count', await run('autopost', { acct_pending_alert85: { old_count: 2, data_needed: false } }) === 2 && await run('autopost', { acct_pending_alert85: { data_needed: true } }) === 0);
  chk('unmatched: lines_unmatched', await run('unmatched', { unmatched_forms: { lines_unmatched: 9 } }) === 9);
  chk('billpay: rows length', await run('billpay', { bills_without_payment99: { rows: [1, 2, 3] } }) === 3);
  chk('inbox: new_count, off = 0', await run('inbox', { inbox_board: { on: true, new_count: 5 } }) === 5 && await run('inbox', { inbox_board: { on: false } }) === 0);
  let thr = false; try { await run('ledger', { ledger_problem_count: new Error('Could not find the function') }); } catch (e) { thr = true; } chk('a missing function throws (chip hidden by the caller)', thr);
  chk('garbage / negative counts are 0', await run('ledger', { ledger_problem_count: -3 }) === 0 && await run('ledger', { ledger_problem_count: 'x' }) === 0);
  // landed picker: resolve a GRN into the bill list
  const lq = load('landed_q4.js', 'en', { B: landedStub, rpc: { landed_resolve_docs: (a) => [{ type: 'grn', doc_id: a.p_docs[0].id, bill_id: 'b1' }] } });
  const err = lq.B.landedQ4.errTxt;
  chk('errTxt: grn_not_linked / bill_not_found / not allowed', /not linked/.test(err(new Error('grn_not_linked'))) && /No posted bill/.test(err(new Error('bill_not_found'))) && /Not allowed/.test(err(new Error('not allowed'))));
  // undo plan: first line of a rule holds the value before the batch; null = default
  const su = load('setupundo.js', 'en', {}).B.setupundo;
  const pl = su.plan({ lines: [{ rule_key: 'a', old: null, new: true }, { rule_key: 'b', old: false, new: true }, { rule_key: 'a', old: true, new: false }] });
  chk('undo plan: one row per rule, first old value kept', pl.length === 2 && pl[0].key === 'a' && pl[0].old === null && pl[1].old === false);
  const own = load('setupundo.js', 'en', { owner: true }).B.setupundo, non = load('setupundo.js', 'en', { owner: false }).B.setupundo;
  chk('undo button: owner only', /q4_undo/.test(own.btn({ client_id: 'c', lines: [{}] })) && non.btn({ client_id: 'c', lines: [{}] }) === '');
  // the tagged edits are small and tagged
  chk('landed.js edit tagged bos107', /bos107 q4: GRN picker slot/.test(rd('landed.js')) && (rd('landed.js').match(/bos107 q4/g) || []).length === 2);
  chk('recipes.js edit tagged bos107 and guarded to cost_missing', /k === 'cost_missing' && e && e\.details/.test(rd('recipes.js')) && /bos107 q4/.test(rd('recipes.js')));
  chk('setupadvisor.js edits tagged bos107', (rd('setupadvisor.js').match(/bos107 q4/g) || []).length === 2);
  const idx = rd('index.html');
  chk('index.html: the three scripts are appended at the END in order', /<script src="optionsx\.js"><\/script><script src="landed_q4\.js"><\/script><script src="badges107\.js"><\/script><script src="setupundo\.js"><\/script>\s*\n?<\/body>/.test(idx));
  const mk = ['landed.js', 'landed_q4.js', 'badges107.js', 'setupundo.js', 'setupadvisor.js', 'recipes.js', 'index.html'].every((f) => !/^(<<<<<<<|=======|>>>>>>>)/m.test(rd(f)));
  chk('no conflict markers in the touched files', mk);
  console.log(`q4_test: ${pass} pass / ${failn} fail`); process.exit(failn ? 1 : 0);
})();
