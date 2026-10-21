// Step PBill (bos104): web/purchaseprint.js with mocked rpc, no browser. Run on its own: node tests/web/purchaseprint_test.js
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = path.join(__dirname, '..', '..', 'web');
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৲৴-৿]/;
const BILL = (x = {}) => ({ id: 'b1', kind: 'bill', status: 'posted', supplier_id: 's1', supplier_name: 'Test Supplier', bill_no: 'PB-7', bill_date: '2026-10-14', location_id: 1, subtotal: 300, discount: 20, total: 280, paid: 100, due: 180,
  note: 'Deliver <b>early</b>', lines: [{ item_id: 'i1', qty: 2, unit: 'kg', unit_cost: 100, amount: 200 }, { description: '<img src=x onerror=alert(1)>', qty: 1, unit: 'pc', unit_cost: 100, amount: 100 }], payments: [], ...x });
function mk(lang, o = {}) {
  const calls = [], toasts = [], sheets = [], clicks = [], frames = [], mem = {}, handlers = {};
  const rpcImpl = { fn: async (fn) => {
    if (fn === 'get_doc_templates') return { data: o.choices || [], error: null };
    if (fn === 'purchase_get') return o.refuse ? { data: null, error: { message: 'not allowed' } } : { data: o.bill || BILL(), error: null };
    if (fn === 'purchase_list') return o.refuse ? { data: null, error: { message: 'not allowed' } } : { data: [{ id: 'b1', supplier_name: 'Test Supplier', bill_no: 'PB-7', bill_date: '2026-10-14', total: 280, status: 'posted' }], error: null };
    return { data: null, error: { message: 'x' } }; } };
  const A = { sb: { rpc: async (fn, args) => { calls.push([fn, args]); return rpcImpl.fn(fn, args); } }, S: { lang, ctx: {} },
    esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), shell: (t, h) => { mem.shell = h; }, openSheet: (h) => sheets.push(h), closeSheet: () => {}, fmt: (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }), H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en),
    ENV: { locs: [{ id: 1, code: 'M', name_bn: 'প্রধান শাখা', name_en: 'Main branch', name_mix: 'Main শাখা' }], sup: [{ id: 's1', name: 'Test Supplier', mobile: '01711000002' }], items: [{ id: 'i1', name_bn: 'চিনি', name_en: 'Sugar', name_mix: 'Sugar' }] } };
  const els = {};
  const document = { getElementById: (id) => els['#' + id] || null, querySelector: (s) => els[s] || null,
    createElement: (tag) => { const e = { tag, style: {}, remove() {}, setAttribute() {}, click() { clicks.push({ href: this.href, download: this.download, target: this.target }); }, contentWindow: { focus() {}, print() { mem.printed = (mem.printed || 0) + 1; if (o.printThrows) throw new Error('no printer'); } } };
      if (tag === 'iframe') { Object.defineProperty(e, 'srcdoc', { set(v) { frames.push(v); setTimeout(() => e.onload && e.onload(), 0); }, get() { return ''; } }); } return e; },
    body: { appendChild() {} }, addEventListener() {} };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, location: { hash: '#/purchase/b1' }, print: o.noPrint ? undefined : () => {}, navigator: { userAgent: 'Android', clipboard: { writeText: async (t) => { mem.copied = t; } } }, addEventListener() {} };
  const ctx = vm.createContext({ window: win, document, location: win.location, navigator: win.navigator, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Blob: function (parts) { mem.blob = parts.join(''); }, setTimeout, clearTimeout, Promise, console, Date, encodeURIComponent, decodeURIComponent, Intl });
  if (o.tpl) for (const f of ['tpl_registry', 'tpl_docs', 'tpl_labels', 'tpl_msgs', 'tpl_samples']) vm.runInContext(fs.readFileSync(path.join(ROOT, f + '.js'), 'utf8'), ctx, { filename: f });
  win.BOS.ENV.locs = B.ENV.locs;
  vm.runInContext(fs.readFileSync(path.join(ROOT, 'purchaseprint.js'), 'utf8'), ctx, { filename: 'purchaseprint.js' });
  return { A, B, calls, toasts, sheets, clicks, frames, mem, els, handlers, pp: B.purchaseprint, pages: win.BOS_PAGES };
}
const tick = (ms) => new Promise((r) => setTimeout(r, ms || 10));
const CHOICE = [{ doc_type: 'purchase_bill', template_id: 'a4_formal', location_id: null }];
(async () => {
  // 1. language: every string has bn/en/mix
  for (const lang of ['bn', 'en', 'mix']) { const t = mk(lang); const k = Object.keys(t.pp.X); chk(`${lang}: strings complete (${k.length})`, k.every((x) => t.pp.X[x].bn && t.pp.X[x].en && t.pp.X[x].mix)); }
  // 2. built-in layout (nothing chosen / no B.tpl)
  for (const withTpl of [false, true]) {
    const t = mk('en', { tpl: withTpl }); chk(`route page registered (${withTpl})`, typeof t.pages.purchaseprint === 'function');
    await t.handlers.pbp_open({ dataset: { v: 'b1' } }); chk('sheet opened', t.sheets.length === 1);
    chk('purchase_get called with id', t.calls.some((c) => c[0] === 'purchase_get' && c[1].p_id === 'b1'));
    const sh = t.sheets[0]; for (const a of ['pbp_print', 'pbp_grn', 'pbp_share', 'pbp_dl', 'pbp_email_go', 'pbp_sms', 'pbp_wa']) chk('button ' + a, sh.includes(`data-act="${a}"`));
    chk('supplier mobile prefilled', sh.includes('value="01711000002"'));
    const f = await t.pp.fragment(t.pp.modelOf(BILL()), false); chk('built-in used when nothing chosen', f.used === 'builtin' && f.html.includes('data-pbp="builtin"'));
    chk('built-in has rate and total', f.html.includes('Rate') && f.html.includes('Total') && f.html.includes('৳ 100') && f.html.includes('৳ 280') && f.html.includes('Due'));
    chk('item name from item list', f.html.includes('Sugar'));
    chk('XSS: description escaped', !f.html.includes('<img') && f.html.includes('&lt;img') && !f.html.includes('<b>early'));
    chk('English: no Bangla letters in document', !BN.test(f.html.replace(/৳/g, '')));
    chk('no sale price / margin words', !/margin|sale price|selling|profit/i.test(f.html.replace(/<[^>]*>/g, ' ')));
    await t.handlers.pbp_print(); await tick(); chk('print through hidden iframe', t.frames.length === 1 && t.mem.printed === 1 && t.frames[0].includes('data-pbp="builtin"'));
    chk('English: no Bangla in whole sheet', !BN.test(sh.replace(/৳/g, '')));
  }
  // 3. template chosen
  { const t = mk('en', { tpl: true, choices: CHOICE }); await t.handlers.pbp_open({ dataset: { v: 'b1' } });
    const f = await t.pp.fragment(t.pp.modelOf(BILL()), false); chk('template used when chosen', f.used === 'tpl' && f.html.includes('data-tpl="a4_formal"') && f.html.includes('data-doc="purchase_bill"'));
    chk('template: XSS escaped', !f.html.includes('<img') && f.html.includes('&lt;img'));
    chk('template: rate and total present', f.html.includes('280') && /Rate/i.test(f.html));
    chk('template: English no Bangla', !BN.test(f.html.replace(/৳/g, '')));
    chk('choices fetched', t.calls.some((c) => c[0] === 'get_doc_templates'));
    await t.handlers.pbp_print(); await tick(); chk('print uses the template page', t.frames.length === 1 && t.frames[0].includes('data-tpl="a4_formal"'));
    const g = await t.pp.fragment(t.pp.modelOf(BILL()), true); chk('GRN without a choice -> built-in with no rate/amount column', g.used === 'builtin' && !/Rate|Amount|Total/.test(g.html) && g.html.includes('Goods Received Note'));
    const gd = t.pp.tplData(t.pp.modelOf(BILL()), true); chk('GRN data has no rate / amount / total', !JSON.stringify(gd).match(/rate|amount|total|paid/));
    const g2 = mk('en', { tpl: true, choices: [{ doc_type: 'grn', template_id: 'a4_classic', location_id: null }] }); const g3 = await g2.pp.fragment(g2.pp.modelOf(BILL()), true);
    chk('GRN template used when chosen', g3.used === 'tpl' && g3.html.includes('data-doc="grn"')); }
  // 4. cost secrecy: purchase_get refuses
  { const t = mk('en', { tpl: true, refuse: true }); const r = await t.handlers.pbp_open({ dataset: { v: 'b1' } });
    chk('refused: no sheet, no data', t.sheets.length === 0 && r === false && t.toasts.length === 1);
    await t.handlers.pbp_print(); await tick(); chk('refused: print does nothing', t.frames.length === 0);
    await t.handlers.pbp_quick({ dataset: { v: 'b1' } }); await tick(); chk('refused: quick print does nothing', t.frames.length === 0 && t.sheets.length === 0);
    const lst = { innerHTML: '' }; t.els['#pbp_list'] = lst; await t.pages.purchaseprint(); await tick(); chk('refused: list shows no bills/amounts', /not allowed/i.test(lst.innerHTML) && !/280|Test Supplier/.test(lst.innerHTML));
    chk('refused: no template/choices fetch', !t.calls.some((c) => c[0] === 'get_doc_templates')); }
  { const t = mk('en'); const lst = { innerHTML: '' }; t.els['#pbp_list'] = lst; await t.pages.purchaseprint(); await tick(); chk('list shows the bill and a Print button', /Test Supplier/.test(lst.innerHTML) && /data-act="pbp_quick"/.test(lst.innerHTML)); }
  // 5. draft / void marking
  for (const [st, word] of [['draft', 'DRAFT'], ['void', 'VOID']]) {
    const t = mk('en', { tpl: true, choices: CHOICE }); const m = t.pp.modelOf(BILL({ status: st, void_note: 'wrong supplier' }));
    const b = await t.pp.fragment(m, false); const bi = t.pp.builtin(m, false);
    chk(`${st}: marked in template page`, b.html.includes('data-pbp="status"') && b.html.includes(word)); chk(`${st}: marked in built-in`, bi.includes(word));
    chk(`${st}: marked in message`, t.pp.textOf(m, false).includes(word)); chk(`${st}: no paid/due`, m.paid === null && !/Paid|Due/.test(bi));
    t.pp.modelOf(BILL()); const ok = t.pp.builtin(t.pp.modelOf(BILL()), false); chk('posted: no status band', !ok.includes('data-pbp="status"') && ok.includes('Paid'));
  }
  // 6. message links
  { const t = mk('en'); await t.handlers.pbp_open({ dataset: { v: 'b1' } });
    const dom = { '#pbp_phone': { value: '01711 000002' }, '#pbp_email': { value: 'sup@example.com' } }; Object.assign(t.els, dom);
    t.handlers.pbp_wa(); t.handlers.pbp_sms(); t.handlers.pbp_email_go(); await tick();
    chk('3 links', t.clicks.length === 3);
    chk('whatsapp link', /^https:\/\/wa\.me\/8801711000002\?text=/.test(t.clicks[0].href) && decodeURIComponent(t.clicks[0].href).includes('Total: ৳ 280') && t.clicks[0].target === '_blank');
    chk('sms link', /^sms:\+8801711000002\?body=/.test(t.clicks[1].href)); chk('mailto link', /^mailto:sup@example\.com\?subject=Purchase%20Bill%20PB-7&body=/.test(t.clicks[2].href));
    chk('message English no Bangla', !BN.test(decodeURIComponent(t.clicks.map((c) => c.href).join(' ')).replace(/৳/g, '')));
    t.els['#pbp_phone'].value = 'abc'; t.handlers.pbp_wa(); chk('bad phone -> toast, no link', t.clicks.length === 3);
    t.els['#pbp_email'].value = 'nope'; t.handlers.pbp_email_go(); chk('bad email -> no link', t.clicks.length === 3);
    await t.handlers.pbp_share(); chk('share falls back to copy', /Purchase Bill PB-7/.test(t.mem.copied || ''));
    await t.handlers.pbp_dl(); await tick(); chk('download file', t.clicks[3] && /^purchase-bill-PB-7\.html$/.test(t.clicks[3].download) && t.mem.blob.includes('Purchase Bill')); }
  // 7. no printer: friendly fallback
  { const t = mk('en', { noPrint: true }); await t.handlers.pbp_open({ dataset: { v: 'b1' } }); const np = { innerHTML: '' }; t.els['#pbp_np'] = np; await t.handlers.pbp_print(); chk('no window.print -> notice', /Printing did not work/.test(np.innerHTML) && t.frames.length === 0);
    const t2 = mk('en', { printThrows: true }); await t2.handlers.pbp_open({ dataset: { v: 'b1' } }); const np2 = { innerHTML: '' }; t2.els['#pbp_np'] = np2; await t2.handlers.pbp_print(); await tick(); chk('print throws -> notice', /Printing did not work/.test(np2.innerHTML)); }
  // 8. broken B.tpl falls back
  { const t = mk('en'); t.B.tpl = { render() { throw new Error('boom'); }, ensure: async () => { throw new Error('x'); } }; const f = await t.pp.fragment(t.pp.modelOf(BILL()), false); chk('tpl throws -> built-in', f.used === 'builtin'); }
  // 9. Bangla / mix: labels on the document keep common words English
  for (const lang of ['bn', 'mix']) { const t = mk(lang); const h = t.pp.builtin(t.pp.modelOf(BILL()), false); chk(`${lang}: common words English on the bill`, ['Purchase Bill', 'Supplier', 'Date', 'Qty', 'Rate', 'Total', 'Paid', 'Due'].every((w) => h.includes(w)));
    await t.handlers.pbp_open({ dataset: { v: 'b1' } }); chk(`${lang}: sheet has Bangla heading`, BN.test(t.sheets[0]) || lang === 'mix'); }
  // 10. decorator
  { const t = mk('en'); const inserted = []; const bar = { insertAdjacentHTML: (w, h) => { inserted.push(h); t.els['#pbp_grp'] = true; } };
    const root = { querySelector: (s) => (s === '#pbp_grp' ? t.els['#pbp_grp'] || null : s === '#pe_save, #pe_post' ? null : s === '.s2-bar' ? bar : s === '.s2-led' ? { closest: () => bar } : null) }; t.els['#app'] = root;
    t.pp.decorate(); chk('group injected once', inserted.length === 1 && inserted[0].includes('data-act="pbp_quick"') && inserted[0].includes('data-v="b1"')); t.pp.decorate(); chk('not injected twice', inserted.length === 1);
    const t2 = mk('en'); t2.els['#app'] = { querySelector: (s) => (s === '.s2-bar' ? bar : s === '.s2-led' ? { closest: () => bar } : null) }; t2.A.H; t2.B.purchaseprint.decorate(); }
  { const t = mk('en'); const ins = []; t.els['#app'] = { querySelector: (s) => (s === '#pe_save, #pe_post' ? {} : { insertAdjacentHTML: (w, h) => ins.push(h) }) }; t.pp.decorate(); chk('editor: nothing injected', ins.length === 0); }
  console.log(`purchaseprint_test: ${pass} pass / ${failn} fail`); process.exit(failn ? 1 : 0);
})();
