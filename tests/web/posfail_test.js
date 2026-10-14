// Step E-b / E8: web/posfail.js (offline POS failed cards: manager override re-send, JSON export, board count, replay through record_sale_offline).
// Plain node, no browser: node tests/web/posfail_test.js
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = path.join(__dirname, '..', '..', 'web');
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৿]/;

function mk(lang) {
  const calls = [], toasts = [], sheets = [], mem = {}, handlers = {};
  const rpcImpl = { fn: async () => ({ data: null, error: null }) };
  const A = { sb: { rpc: async (fn, args) => { calls.push([fn, args]); return rpcImpl.fn(fn, args); }, from: () => ({ select: () => ({ order: () => ({ limit: async () => ({ data: [] }) }) }) }) },
    S: { lang, ctx: { profile: { id: 'u1' } } }, esc: (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), fail: (e) => toasts.push('FAIL:' + e.message), shell: () => {}, openSheet: (h) => sheets.push(h), closeSheet: () => {},
    store: { get: (k) => (k in mem ? mem[k] : null), set: (k, v) => { mem[k] = v; } }, H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en) };
  const els = {};
  const document = { querySelector: (s) => els[s] || null, createElement: () => ({ click() {}, remove() {} }), body: { appendChild() {} } };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, location: { hash: '#/pos' } };
  const ctx = vm.createContext({ window: win, document, location: win.location, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Blob: function () {}, navigator: { clipboard: { writeText: async () => {} } }, setTimeout: () => 0, console });
  vm.runInContext(fs.readFileSync(path.join(ROOT, 'posfail.js'), 'utf8'), ctx);
  return { A, B, calls, toasts, sheets, mem, els, handlers, rpcImpl, pf: B.posfail, pages: win.BOS_PAGES };
}

// ---- 1. languages: every string has bn / en / mix; English mode never shows a Bangla letter ----
{
  const t = mk('en'); const X = t.pf.X; const keys = Object.keys(X);
  chk('all strings have bn, en and mix', keys.every((k) => X[k].bn && X[k].en && X[k].mix));
  chk('English text has no Bangla letters (all ' + keys.length + ' strings)', keys.every((k) => !BN.test(X[k].en)));
  chk('English mode shows English', t.pf.T('resend') === 'Re-send on manager override');
  chk('Bangla mode shows the agreed label', mk('bn').pf.T('resend') === 'ম্যানেজার-ওভাররাইডে আবার পাঠাও');
  chk('mix mode shows mixed text', /override/.test(mk('mix').pf.T('resend')) && BN.test(mk('mix').pf.T('resend')));
  const html = t.pf.buttons({ p_client: 'c-1"x' });
  chk('English buttons: no Bangla, ids escaped, two actions', !BN.test(html) && /posfail_resend/.test(html) && /posfail_export/.test(html) && !/c-1"x/.test(html));
  chk('a page and three handlers are registered', typeof t.pages.posfailed === 'function' && ['posfail_resend', 'posfail_go', 'posfail_export'].every((k) => typeof t.handlers[k] === 'function'));
}

// ---- 2. replay through record_sale_offline, with the old-database fallback ----
(async () => {
  {
    const t = mk('en'); const args = { p_client: 'c1', p_loc: 1 };
    await t.pf.sendOffline(args);
    chk('replay calls record_sale_offline first', t.calls[0][0] === 'record_sale_offline' && t.calls[0][1] === args);
    t.rpcImpl.fn = async (fn) => (fn === 'record_sale_offline' ? { data: null, error: { message: 'Could not find the function public.record_sale_offline in the schema cache' } } : { data: { id: 's1' }, error: null });
    const r = await t.pf.sendOffline(args);
    chk('database without phase83: falls back to record_sale2 with the same arguments', t.calls[t.calls.length - 1][0] === 'record_sale2' && t.calls[t.calls.length - 1][1] === args && r.data.id === 's1');
    const n = t.calls.length; await t.pf.sendOffline(args);
    chk('and it remembers (no repeated failing call)', t.calls.length === n + 1 && t.calls[n][0] === 'record_sale2');
  }
  {
    const t = mk('en'); t.rpcImpl.fn = async () => ({ data: null, error: { message: 'insufficient_stock' } });
    const r = await t.pf.sendOffline({ p_client: 'c1' });
    chk('a business refusal is returned as it is (no fallback, no second call)', r.error.message === 'insufficient_stock' && t.calls.length === 1);
  }
  // ---- 3. manager override ----
  {
    const t = mk('en'); const card = { p_client: 'c9', p_loc: 1, p_lines: [{ item_id: 'i1', qty: 2 }], _err: 'Not enough stock', _total: 200, _t: 5 };
    t.mem['bos_pos_failed_u1'] = JSON.stringify([card, { p_client: 'c10', p_loc: 1 }]);
    t.handlers.posfail_resend({ dataset: { v: 'c9' } });
    chk('override sheet opens, English only', t.sheets.length === 1 && !BN.test(t.sheets[0]) && /pf_reason/.test(t.sheets[0]));
    t.els['#pf_reason'] = { value: ' ' };
    await t.handlers.posfail_go({ dataset: { v: 'c9' } });
    chk('no reason = no call, a message', t.calls.length === 0 && t.toasts.pop() === 'Write a reason first');
    t.els['#pf_reason'] = { value: 'goods already handed over' };
    t.rpcImpl.fn = async () => ({ data: null, error: { message: 'replay_override_needs_approval' } });
    await t.handlers.posfail_go({ dataset: { v: 'c9' } });
    chk('no permission: message shown, the card stays on the phone', /manager permission/.test(t.toasts.pop()) && JSON.parse(t.mem['bos_pos_failed_u1']).length === 2);
    t.rpcImpl.fn = async () => ({ data: { id: 's9', receipt: 4 }, error: null });
    await t.handlers.posfail_go({ dataset: { v: 'c9' } });
    const c = t.calls[t.calls.length - 1];
    chk('override sends the ORIGINAL client id, the reason, the refusal, and no private underscore keys', c[0] === 'pos_replay_override' && c[1].p_payload.p_client === 'c9' && c[1].p_reason === 'goods already handed over' && c[1].p_err === 'Not enough stock'
      && !Object.keys(c[1].p_payload).some((k) => k[0] === '_') && c[1].p_payload.p_lines.length === 1);
    chk('success: the card leaves the phone list, only that one', JSON.parse(t.mem['bos_pos_failed_u1']).map((x) => x.p_client).join() === 'c10' && t.toasts.pop() === 'Sale recorded');
    t.rpcImpl.fn = async () => ({ data: { id: 's9', dup: true }, error: null });
    t.mem['bos_pos_failed_u1'] = JSON.stringify([card]);
    await t.handlers.posfail_go({ dataset: { v: 'c9' } });
    chk('already recorded (dup) is said plainly', t.toasts.pop() === 'This sale was already recorded');
  }
  // ---- 4. export, report, discard ----
  {
    const t = mk('en'); t.mem['bos_pos_failed_u1'] = JSON.stringify([{ p_client: 'c9', p_loc: 1 }]);
    t.handlers.posfail_export({ dataset: { v: 'c9' } });
    chk('export says so', t.toasts.pop() === 'JSON copied / downloaded');
    await t.pf.report([{ p_client: 'c9', p_loc: 1, _total: 50, _err: 'x'.repeat(400), p_sold_at: '2026-10-14T01:00:00Z', p_lines: [1, 2] }]);
    const c = t.calls[t.calls.length - 1];
    chk('report sends a summary only (no lines, no customer data), error cut to 300', c[0] === 'pos_failed_note' && c[1].p_items[0].lines_n === 2 && c[1].p_items[0].err.length === 300 && !('p_lines' in c[1].p_items[0]));
    t.rpcImpl.fn = async () => { throw new Error('offline'); };
    let ok = true; try { await t.pf.report([{ p_client: 'c9', p_loc: 1 }]); await t.pf.discarded('c9'); } catch (e) { ok = false; }
    chk('reporting / closing never throws on a bad network', ok);
  }
  // ---- 5. the small tagged edits in web/pos.js are guarded ----
  {
    const s = fs.readFileSync(path.join(ROOT, 'pos.js'), 'utf8');
    const tagged = s.split('\n').filter((l) => /bos83/.test(l));
    chk('pos.js: 5 tagged lines (buttons, discard, send, flush, report)', tagged.length === 5);
    chk('pos.js: every hook is guarded by B.posfail', tagged.every((l) => /B\.posfail/.test(l) || /replay/.test(l)));
    chk('pos.js: only the queue replay passes replay=true', (s.match(/send\(p, true\)/g) || []).length === 1 && (s.match(/await send\(p\)/g) || []).length === 1);
  }
  console.log('RESULT ' + pass + ' pass / ' + failn + ' fail'); process.exit(failn ? 1 : 0);
})();
