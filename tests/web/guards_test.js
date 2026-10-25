// Phase 82 web: node tests/web/guards_test.js   (plain node, no browser): 3-language texts, English has no Bangla letters, page renders, apply calls set_rule.
const _P = require('./_paths');
const fs = require('fs'), path = require('path'), vm = require('vm');
const src = fs.readFileSync(path.join(_P.WEB_DIR, 'guards.js'), 'utf8');
let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; console.log('FAIL:', m); } };
const BN = /[ঀ-৿]/;
function run(lang) {
  const calls = [], toasts = []; const H = {}; const els = { gd_body: { innerHTML: '' } };
  const B = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (o) => (lang === 'bn' ? o.bn : lang === 'en' ? o.en : (o.mix || o.bn)) };
  const rec = [{ key: 'purchase_void_guard', current: 'off', recommended: 'refuse', reason_bn: 'ক', reason_mix: 'm', reason_en: 'Because' }, { key: 'neg_grant_log', current: true, recommended: true, reason_bn: 'ক', reason_mix: 'm', reason_en: 'ok' }];
  const sb = { rpc: async (fn, a) => { calls.push([fn, a]); const d = { guard_recommendations: rec, unit_unknown_items: { count: 1, items: [{ code: 'UB', unit: 'box', base_unit: 'pc' }] }, never_opened_negative_items: { count: 0, items: [] }, grn_pending_report: { receipts_without_bill: [{ date: '2026-10-14', supplier: 'S' }], bills_without_receipt: [] } }[fn]; return { data: d === undefined ? null : d, error: null }; } };
  const A = { sb, esc: (s) => String(s), toast: (m) => toasts.push(m), fail: (e) => { throw e; }, shell: () => {}, H };
  const win = { BOS_APP: A, BOS: B }; const doc = { querySelector: (s) => (s === '#gd_body' ? els.gd_body : null) };
  vm.runInNewContext(src, { window: win, document: doc, console });
  return { win, B, H, els, calls, toasts };
}
(async () => {
  for (const lang of ['bn', 'mix', 'en']) {
    const r = run(lang);
    for (const c of r.B.guardErrCodes) { const m = r.B.guardMsg(c); ok(!!m, lang + ' message for ' + c); if (lang === 'en') ok(!BN.test(m), 'English message of ' + c + ' has Bangla: ' + m); }
    await r.win.BOS_PAGES.guards();
    const h = r.els.gd_body.innerHTML; ok(h.includes('gd_apply') && h.includes('UB'), lang + ' page renders recommendation + unit list');
    if (lang === 'en') ok(!BN.test(h.replace(/ক/g, '')), 'English page has no Bangla letters (except test fixture)');
    if (lang === 'en') { ok(/Recommended/.test(h) && /Receives with no bill/.test(h), 'English labels shown'); }
    const a = { dataset: { k: 'purchase_void_guard' } }; await r.H.gd_apply(a);
    ok(r.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'purchase_void_guard' && c[1].p_value === 'refuse'), lang + ' apply sends the recommended value via set_rule');
    ok(r.calls.filter((c) => c[0] === 'set_rule').length === 1, lang + ' nothing else is written');
  }
  console.log(`guards_test: ${n - bad} pass / ${bad} fail`); process.exit(bad ? 1 : 0);
})();
