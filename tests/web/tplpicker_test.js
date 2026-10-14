// Phase 93 web: node tests/web/tplpicker_test.js  (plain node, mocked rpc): page renders for every doc type, set/clear call the right rpc, location scope, errors surface, XSS in location names, English page has no Bangla, unique data-act names, ia + index wiring.
const _P = require('./_paths');
const fs = require('fs'), path = require('path'), vm = require('vm');
const W = _P.WEB_DIR; const BN = /[ঀ-৿]/;
let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; console.log('FAIL:', m); } };
const rd = (f) => fs.readFileSync(path.join(W, f), 'utf8');
async function run(lang, opts) {
  opts = opts || {}; const calls = [], toasts = [], fails = [], H = {}; const els = { tpl93_body: { innerHTML: '' } }; const listeners = [];
  const win = { BOS: { L: (bn, en, mix) => ({ bn, en, mix }), lab: (o) => (lang === 'bn' ? o.bn : lang === 'en' ? o.en : (o.mix || o.bn)), ENV: { locs: [{ id: 1, name_en: 'Shop <script>alert(1)</script>', name_bn: 'Shop <script>alert(1)</script>', is_active: true }, { id: 2, name_en: 'Second', name_bn: 'Second', is_active: true }] } } };
  const rows = [{ doc_type: 'pos_receipt', location_id: null, template_id: 'a4_modern' }];
  const sb = { rpc: async (fn, a) => { calls.push([fn, a]); if (fn === 'get_doc_templates') return opts.noSql ? { data: null, error: { message: 'missing' } } : { data: rows, error: null }; if (fn === 'set_doc_template') return opts.denied ? { data: null, error: { message: 'owner_only' } } : { data: {}, error: null }; return { data: null, error: null }; },
    from: () => ({ select: () => ({ in: async () => ({ data: [{ key: 'business_name', value: 'Sample Shop' }], error: null }) }) }) };
  const A = { sb, esc: (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])), toast: (m) => toasts.push(m), fail: (e) => fails.push(e), shell: () => {}, H, S: { lang }, nm: (o) => o.name_en };
  win.BOS_APP = A; const doc = { querySelector: (s) => (s === '#tpl93_body' ? els.tpl93_body : null), querySelectorAll: () => [], addEventListener: (t, f) => listeners.push([t, f]) };
  const ctx = vm.createContext({ window: win, document: doc, console });
  for (const f of ['tpl_registry', 'tpl_docs', 'tpl_labels', 'tpl_msgs', 'tpl_samples', 'tplpicker']) vm.runInContext(rd(f + '.js'), ctx, { filename: f });
  return { win, H, els, calls, toasts, fails, listeners };
}
(async () => {
  for (const lang of ['bn', 'mix', 'en']) {
    const r = await run(lang); await r.win.BOS_PAGES.templates();
    const h = r.els.tpl93_body.innerHTML;
    ok(r.win.BOS.tpl.docTypes().every((s) => h.includes('id="tpl93_' + s.id + '"')), lang + ' every document type has a card');
    ok(h.includes('tpl93_set') && h.includes('Sample') || lang !== 'en', lang + ' set button');
    ok(!/<script>alert/.test(h), lang + ' location name escaped'); ok(h.includes('&lt;script&gt;'), lang + ' location name shown escaped');
    ok(!/@page/.test(h), lang + ' preview carries no @page rule');
    r.H.tpl93_go({ dataset: { v: 'pos_receipt', i: '4' } }); ok(lang !== 'en' || r.els.tpl93_body.innerHTML.includes('This is the default'), 'current default marked when its template is shown'); r.H.tpl93_go({ dataset: { v: 'pos_receipt', i: '0' } });
    if (lang === 'en') ok(!BN.test(h), 'English page has no Bangla letters');
    else ok(BN.test(h), lang + ' page has Bangla');
    ok(/Suggested|Suggestion|প্রস্তাব/.test(h), lang + ' recommendation shown');
    ok(r.calls.every((c) => c[0] === 'get_doc_templates'), lang + ' opening the page only reads');
    // set default for the shown template of a doc type (second template after "next")
    r.H.tpl93_next({ dataset: { v: 'pnl' } }); r.H.tpl93_set && 0;
    await r.H.tpl93_set({ dataset: { v: 'pnl' } });
    const s = r.calls.find((c) => c[0] === 'set_doc_template');
    ok(s && s[1].p_doc_type === 'pnl' && s[1].p_template_id === 'a4_formal' && s[1].p_location_id === null, lang + ' set sends doc type, the previewed template id, null location (got ' + JSON.stringify(s) + ')');
    await r.H.tpl93_clear({ dataset: { v: 'pos_receipt' } });
    const c = r.calls.filter((x) => x[0] === 'set_doc_template')[1]; ok(c && c[1].p_template_id === null && c[1].p_doc_type === 'pos_receipt', lang + ' clear sends null template');
    ok(r.toasts.length === 2 && r.fails.length === 0, lang + ' toasts after save / clear');
    // location scope
    const ch = r.listeners.find((x) => x[0] === 'change'); await ch[1]({ target: { id: 'tpl93_loc', value: '2' } });
    await r.H.tpl93_set({ dataset: { v: 'pnl' } }); const s2 = r.calls.filter((x) => x[0] === 'set_doc_template').pop(); ok(s2[1].p_location_id === 2, lang + ' location scope is sent');
    // message channel + go
    r.H.tpl93_chan({ dataset: { v: 'email' } }); ok(/Subject:/.test(r.els.tpl93_body.innerHTML), lang + ' email preview has a subject'); r.H.tpl93_go({ dataset: { v: 'msg_due', i: '5' } });
    ok(/tpl93_set/.test(r.els.tpl93_body.innerHTML), lang + ' go works');
  }
  const d = await run('en', { denied: true }); await d.win.BOS_PAGES.templates(); await d.H.tpl93_set({ dataset: { v: 'pnl' } }); ok(d.fails.length === 1 && d.toasts.length === 0, 'server refusal surfaces (owner_only) and no success toast');
  const q = await run('en', { noSql: true }); await q.win.BOS_PAGES.templates(); ok(/phase93/.test(q.els.tpl93_body.innerHTML), 'missing SQL shows the run-the-SQL notice');
  // wiring and unique names
  const src = rd('tplpicker.js'); const acts = [...src.matchAll(/data-act="(\w+)"/g)].map((m) => m[1]); ok(acts.length >= 6 && acts.every((a) => a.startsWith('tpl93_')), 'all data-act names use the tpl93_ prefix');
  const others = fs.readdirSync(W).filter((f) => f.endsWith('.js') && f !== 'tplpicker.js').map((f) => rd(f)).join('\n'); ok(!acts.some((a) => others.includes(a)), 'data-act names are used nowhere else');
  ok(/rec\('templates', 'cust'/.test(rd('ia.js')), 'ia.js has the templates line'); const ix = rd('index.html'); ok(['tpl_registry', 'tpl_docs', 'tpl_labels', 'tpl_msgs', 'tpl_samples', 'tplpicker'].every((f) => ix.includes(`<script src="${f}.js"></script>`)) && ix.indexOf('tpl_registry.js') < ix.indexOf('tplpicker.js'), 'index.html has the script tags in order');
  ok(!/pos\.js|invoiceview/.test(src), 'picker does not touch pos.js / invoiceview.js');
  console.log(`tplpicker_test: ${n - bad} pass / ${bad} fail`); process.exit(bad ? 1 : 0);
})();
