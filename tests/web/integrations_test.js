// web/integrations.js - stub-DOM test (no browser): renders each tab from mocked RPCs, friendly errors, CSV download, no secrets in markup.
// Run: node tests/web/integrations_test.js
const fs = require('fs'), vm = require('vm'), path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', '..', 'web', 'integrations.js'), 'utf8');
let pass = 0, fail = 0; const ok = (n, c) => { if (c) pass++; else { fail++; console.log('FAIL ' + n); } };
const body = { innerHTML: '' }, acts = {}, toasts = [], dl = [], calls = [];
let MODE = 'en', RPC = {};
const els = { ig_body: body };
const doc = { addEventListener() {}, getElementById: (i) => els[i] || null, querySelector: (s) => (s[0] === '#' ? els[s.slice(1)] || null : null),
  createElement: () => ({ click() { dl.push(this); }, remove() {}, set href(v) { this._h = v; }, get href() { return this._h; } }), body: { appendChild() {} } };
const B = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (o) => (typeof o === 'string' ? o : o[MODE]), loadStatic: async () => {} };
const A = { sb: { rpc: async (fn, a) => { calls.push([fn, a]); const r = RPC[fn]; if (r instanceof Error) return { data: null, error: r }; return { data: r === undefined ? null : r, error: null }; } },
  esc: (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
  toast: (m) => toasts.push(m), fail: (e) => toasts.push(String(e.message || e)), shell: () => {}, H: acts };
const win = { BOS_APP: A, BOS: B, BOS_PAGES: {} };
const ctx = { window: win, document: doc, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Blob: class { constructor(p) { this.p = p; } }, setTimeout: (f) => 0, Date, Number, String, Object, JSON, Math };
vm.createContext(ctx); vm.runInContext(src, ctx);
const view = win.BOS_PAGES.integrations; const mk = (t, extra) => Object.assign({ dataset: { t } }, extra);
(async () => {
  ok('page registered', typeof view === 'function');
  RPC.notify_outbox_summary = { on: false, counts: { queued: 2, sent: 5 }, recent: [{ id: 7, channel: 'sms', status: 'queued', attempts: 1, max_attempts: 5, template: 'thanks', to: '+88017****78', last_error: 'timeout' }] };
  await view();
  ok('sms tab shows OFF state and counts', /OFF/.test(body.innerHTML) && /Queued: 2/.test(body.innerHTML) && /Sent: 5/.test(body.innerHTML));
  ok('phone is shown masked, never a token', /\+88017\*\*\*\*78/.test(body.innerHTML) && !/bearer|eyJ|password/i.test(body.innerHTML));
  ok('cancel button only for queued', /data-act="ig_cancel" data-id="7"/.test(body.innerHTML));
  MODE = 'bn'; await view(); ok('Bangla mode renders', /অপেক্ষায়/.test(body.innerHTML)); MODE = 'mix'; await view(); ok('mix mode renders', /Queued/.test(body.innerHTML)); MODE = 'en';
  RPC.payment_recon = { on: true, counts: { matched: 1, amount_mismatch: 1 }, rows: [{ intent_id: 3, provider: 'bkash', provider_ref: 'TX1', intent_amount: 500, state: 'amount_mismatch', diff: 50 }], orphan_events: [{ provider: 'bkash', provider_ref: 'ZZ', note: 'no_intent', amount: 77 }] };
  await acts.ig_tab(mk('pay'));
  ok('payments tab shows state, difference and orphans', /Amount mismatch/.test(body.innerHTML) && /Difference 50/.test(body.innerHTML) && /Unknown events/.test(body.innerHTML));
  ok('recon call carries the date window', calls.filter((c) => c[0] === 'payment_recon').pop()[1].p_from.length === 10);
  RPC.payment_recon = new Error('not allowed'); await acts.ig_tab(mk('pay'));
  ok('refused call shows a friendly line', /do not have access/.test(body.innerHTML));
  await acts.ig_tab(mk('exp'));
  ok('export tab has both kinds', /Journal/.test(body.innerHTML) && /Trial balance/.test(body.innerHTML));
  RPC.acct_export_csv = { filename: 'trial balance;../x.csv', csv: 'a,b\r\n1,2', rows: 1, columns: ['a', 'b'], truncated: false };
  await acts.ig_export();
  ok('export downloads one sanitized file', dl.length === 1 && /^trial_balance_\._x\.csv$/.test(dl[0].download) && /Columns: a, b/.test(body.innerHTML));
  RPC.acct_export_csv = { data_needed: true }; await acts.ig_export();
  ok('data needed shown, no download', dl.length === 1 && /data needed/i.test(body.innerHTML));
  RPC.acct_export_csv = new Error('bad_range'); await acts.ig_export();
  ok('bad range friendly', /not valid/.test(body.innerHTML));
  RPC.assistant_access_list = { on: true, users: [{ name: 'Manager <b>', location_id: null, valid_until: null }], roles: [] };
  await acts.ig_tab(mk('ast'));
  ok('assistant tab lists holders (escaped) and links to delegation', /Manager &lt;b&gt;/.test(body.innerHTML) && /#\/delegation/.test(body.innerHTML));
  ok('csvFile prefixes a BOM', win.BOS.integrations.csvFile({ filename: 'a.csv', csv: 'x' }).text.charCodeAt(0) === 0xFEFF);
  console.log(`RESULT pass=${pass} fail=${fail}`); process.exit(fail ? 1 : 0);
})();
