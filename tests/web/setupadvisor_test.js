// web/setupadvisor.js - stub-DOM test (no browser): tabs render from mocked RPCs in 3 language modes, apply buttons, confirm flow, friendly errors, no Bangla in English mode.
// Run: node tests/web/setupadvisor_test.js
const _P = require('./_paths');
const fs = require('fs'), vm = require('vm'), path = require('path');
const src = fs.readFileSync(path.join(_P.WEB_DIR, 'setupadvisor.js'), 'utf8');
let pass = 0, fail = 0; const ok = (n, c) => { if (c) pass++; else { fail++; console.log('FAIL ' + n); } };
const BN = /[ঀ-৿]/;
const body = { innerHTML: '' }, acts = {}, toasts = [], calls = [];
let MODE = 'en', RPC = {}, CONFIRM = true;
const els = { sadv_body: body };
const doc = { addEventListener() {}, getElementById: (i) => els[i] || null, querySelector: (s) => (s[0] === '#' ? els[s.slice(1)] || null : null) };
const B = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (o) => (typeof o === 'string' ? o : o[MODE]), loadStatic: async () => {} };
const A = { sb: { rpc: async (fn, a) => { calls.push([fn, a]); const r = RPC[fn]; if (r instanceof Error) return { data: null, error: r }; return { data: r === undefined ? null : r, error: null }; } },
  esc: (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
  toast: (m) => toasts.push(m), shell: () => {}, H: acts };
const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, confirm: () => CONFIRM };
const ctx = { window: win, document: doc, setTimeout, Date, Number, String, Object, Array, Math, JSON, crypto: { randomUUID: () => '11111111-2222-4333-8444-555555555555' } };
vm.createContext(ctx); vm.runInContext(src, ctx);
const view = win.BOS_PAGES.setupadvisor; const mk = (o) => ({ dataset: o });
const item = (o) => Object.assign({ code: 'c', rule_key: 'k', kind: 'switch', status: 'recommended', recommended: true, current: false, default: false, owner_chosen: false, ready: true, ready_issues: [],
  rule_label_bn: 'বাংলা লেবেল', rule_label_mix: 'Mix label', rule_label_en: 'English label', reason_bn: 'কারণ', reason_mix: 'Reason mix', reason_en: 'English reason' }, o);
(async () => {
  ok('page registered', typeof view === 'function' && win.BOS.setupadvisor);
  RPC.setup_recommendations = { advisory: true, can_apply: true, summary: { ok: 1, recommended: 2, owner_chosen: 1, info: 1, not_installed: 1 }, items: [
    item({ code: 'a1' }), item({ code: 'a2', ready: false, ready_issues: [{ code: 'onl_channels', n: 1, label_bn: 'ব', label_mix: 'm', label_en: 'No active sales channel' }] }),
    item({ code: 'a3', status: 'owner_chosen', current: false, owner_chosen: true }), item({ code: 'a4', status: 'ok', current: true }),
    item({ code: 'a5', kind: 'number', status: 'info', recommended: null, current: 10, default: 10, min: 0, max: 1000, unit: 'x' }), item({ code: 'a6', status: 'not_installed' })] };
  await view();
  ok('recommended tab: counts, apply-all, per-row buttons', /Apply all recommended/.test(body.innerHTML) && /data-act="sadv_apply" data-code="a1" data-ready="1"/.test(body.innerHTML) && /data-act="sadv_apply" data-code="a2" data-ready="0"/.test(body.innerHTML));
  ok('not-ready row names the missing check; apply-anyway wording', /No active sales channel/.test(body.innerHTML) && /Apply anyway/.test(body.innerHTML));
  ok('owner-chosen row offers Replace, not Apply', /data-act="sadv_replace" data-code="a3"/.test(body.innerHTML) && !/data-act="sadv_apply" data-code="a3"/.test(body.innerHTML));
  ok('ok row has no button; number row shows default and range, links to Switchboard', !/data-code="a4"/.test(body.innerHTML) && /Default: 10/.test(body.innerHTML) && /Range: 0.1000 x/.test(body.innerHTML.replace('–', '.')) && /#\/switchboard/.test(body.innerHTML));
  ok('not_installed rows are hidden', !/a6/.test(body.innerHTML));
  ok('English mode contains no Bangla characters', !BN.test(body.innerHTML));
  MODE = 'bn'; await view(); ok('Bangla mode renders Bangla', /প্রস্তাবিত/.test(body.innerHTML) && /কারণ/.test(body.innerHTML));
  MODE = 'mix'; await view(); ok('mix mode renders Mix label and English words', /Mix label/.test(body.innerHTML) && /Reason mix/.test(body.innerHTML)); MODE = 'en';
  await view();
  RPC.setup_recommend_apply = { count: 1, applied: [{ code: 'a1' }], skipped: [{ code: 'a2', reason: 'not_ready' }, { code: 'x', reason: 'already' }] };
  await acts.sadv_apply(mk({ code: 'a1', ready: '1' }));
  const ap = calls.filter((c) => c[0] === 'setup_recommend_apply').pop()[1];
  ok('apply sends one code, a client id, no overwrite, no ignore', ap.p_codes.length === 1 && ap.p_codes[0] === 'a1' && /^[0-9a-f-]{36}$/.test(ap.p_client) && ap.p_overwrite === false && ap.p_ignore_ready === false);
  ok('toast tells applied count and skipped reason (not the quiet ones)', /Applied: 1/.test(toasts[toasts.length - 1]) && /not ready/.test(toasts[toasts.length - 1]) && !/already/.test(toasts[toasts.length - 1]));
  const n0 = calls.length; CONFIRM = false;
  await acts.sadv_apply_all(); await acts.sadv_replace(mk({ code: 'a3' })); await acts.sadv_apply(mk({ code: 'a2', ready: '0' }));
  ok('declined confirm sends nothing', calls.length === n0);
  CONFIRM = true; await acts.sadv_apply_all();
  const all = calls.filter((c) => c[0] === 'setup_recommend_apply').pop()[1];
  ok('apply-all = no code list, never overwrite', all.p_codes === null && all.p_overwrite === false && all.p_ignore_ready === false);
  await acts.sadv_replace(mk({ code: 'a3' })); const rp = calls.filter((c) => c[0] === 'setup_recommend_apply').pop()[1];
  ok('replace names the code and sets overwrite', rp.p_codes[0] === 'a3' && rp.p_overwrite === true);
  await acts.sadv_apply(mk({ code: 'a2', ready: '0' })); const ig = calls.filter((c) => c[0] === 'setup_recommend_apply').pop()[1];
  ok('apply-anyway sets ignore_ready only for that row', ig.p_codes[0] === 'a2' && ig.p_ignore_ready === true && ig.p_overwrite === false);
  RPC.setup_recommend_apply = new Error('not allowed'); await acts.sadv_apply(mk({ code: 'a1', ready: '1' }));
  ok('refused apply shows a friendly line', /do not have access/.test(toasts[toasts.length - 1]));
  RPC.setup_readiness = { topics: [{ topic: 'accounting', ready: false, problem_checks: 1, label_bn: 'ব', label_mix: 'm', label_en: 'Before you switch accounting on', checks: [
    { code: 'acc_start', applies: true, ok: false, problems: 1, level: 'warn', label_bn: 'ব', label_mix: 'm', label_en: 'No accounting start date', fix_bn: 'ফ', fix_mix: 'f', fix_en: 'Set the start date', nav: 'accounts' },
    { code: 'acc_coa', applies: true, ok: true, problems: 0, level: 'warn', label_bn: 'ব', label_mix: 'm', label_en: 'The chart of accounts is empty' }, { code: 'onl_url', applies: false, ok: false, level: 'info', label_en: 'hidden check', label_bn: 'ব' }] }] };
  await acts.sadv_tab(mk({ t: 'ready' }));
  ok('readiness tab: topic, problem check with fix and link; ok check; not-applicable hidden', /Before you switch accounting on/.test(body.innerHTML) && /Set the start date/.test(body.innerHTML) && /#\/accounts/.test(body.innerHTML) && !/hidden check/.test(body.innerHTML) && !BN.test(body.innerHTML));
  RPC.setup_flow_check = { warnings: 1, checks: [{ code: 'f1', level: 'warn', problems: 3, label_bn: 'ব', label_mix: 'm', label_en: 'Failed intakes are waiting', fix_en: 'Open the failed list', nav: 'inbox' }, { code: 'f2', level: 'na', label_bn: 'ব', label_en: 'Documents from earlier days' }, { code: 'f3', level: 'ok', problems: 0, label_bn: 'ব', label_en: 'Negative stock' }] };
  await acts.sadv_tab(mk({ t: 'flow' }));
  ok('flow tab: warning with count and link, na and ok rows, no Bangla in English', /Failed intakes are waiting \(3\)/.test(body.innerHTML) && /Off - nothing to check/.test(body.innerHTML) && /Flowing/.test(body.innerHTML) && !BN.test(body.innerHTML));
  RPC.setup_apply_history = [{ applied_at: '2026-10-14T10:00:00Z', lines: [{ rule_key: 'inbox_on', old: null, new: true, overwrote: false }, { rule_key: 'x', old: false, new: true, overwrote: true }] }];
  await acts.sadv_tab(mk({ t: 'hist' }));
  ok('history tab lists old to new, marks an overwrite', /inbox_on/.test(body.innerHTML) && /- → ON/.test(body.innerHTML) && /OFF → ON \*/.test(body.innerHTML));
  RPC.setup_apply_history = []; await acts.sadv_tab(mk({ t: 'hist' })); ok('empty history line', /Nothing has been applied yet/.test(body.innerHTML));
  RPC.setup_apply_history = new Error('not allowed'); await acts.sadv_tab(mk({ t: 'hist' })); ok('history refusal is friendly', /do not have access/.test(body.innerHTML));
  // data-act names are unique to this module
  const acts_ = [...src.matchAll(/data-act="(sadv_[a-z_]+)"/g)].map((m) => m[1]); ok('all data-act names carry the sadv_ prefix', acts_.length > 0 && acts_.every((a) => a.indexOf('sadv_') === 0));
  console.log(`setupadvisor: ${pass} pass, ${fail} fail`); process.exit(fail ? 1 : 0);
})();
