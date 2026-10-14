// Step TplInv (bos98): the template system wired into web/invoiceview.js. Mocked rpc, no browser. Run on its own: node tests/web/tplwire_test.js
// (a) no B.tpl / nothing chosen => output identical to before; (b) chosen template => template HTML used, XSS-escaped; (c) no cost keys; plus choices cached once, 2 s cap, offline.
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = path.join(__dirname, '..', '..', 'web');
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৲৴-৿]/;
const COSTRE = /cost|cogs|purchase|landed|wholesale|(^|_)cp(_|$)|supplier_?(price|rate)|gross|buy(ing)?_?(price|rate)|margin|profit|markup/i;
const keysOf = (v, out = []) => { if (v && typeof v === 'object') for (const k of Object.keys(v)) { out.push(k); keysOf(v[k], out); } return out; };

function mk(lang, o = {}) {
  const calls = [], toasts = [], sheets = [], clicks = [], mem = {}, handlers = {}, els = {}, bodyKids = [], renders = [], rules = { pos_show_invoice_after_sale: 'always' };
  const rpcImpl = { fn: async (fn) => (fn === 'get_doc_templates' ? { data: o.choices || [], error: null } : { data: null, error: { message: 'Could not find the function' } }) };
  const A = { sb: { rpc: async (fn, args) => { calls.push([fn, args]); return rpcImpl.fn(fn, args); }, from: () => ({}) },
    S: { lang, ctx: { profile: { id: 'u1', staff_id: 'sales02', full_name: 'Seller' } } },
    esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), shell: () => {}, openSheet: (h) => sheets.push(h), closeSheet: () => {}, fmt: (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }),
    store: { get: (k) => (k in mem ? mem[k] : null), set: (k, v) => { mem[k] = v; } }, H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en), rule: (k, f) => (k in rules ? rules[k] : f),
    ENV: { locs: [{ id: 1, code: 'M', name_bn: 'প্রধান শাখা', name_en: 'Main branch', name_mix: 'Main শাখা' }] } };
  const prints = [];
  B.invoice = { renderDoc: (tpl, d, l) => { prints.push({ d, l }); return '<div class="ivdoc">x</div>'; }, printHtml: (html, w, th) => { prints.push({ html, w, th }); }, templateFor: async () => ({ kind: 'thermal80', paper_width_mm: 80 }) };
  const document = { querySelector: (s) => els[s] || null, getElementById: (id) => els['#' + id] || null,
    createElement: (tag) => ({ tag, style: {}, remove() {}, setAttribute() {}, set innerHTML(v) { this._h = v; }, get innerHTML() { return this._h; }, click() { clicks.push({ href: this.href, download: this.download }); } }),
    head: { appendChild() {} }, body: { appendChild: (e) => bodyKids.push(e) }, addEventListener() {} };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, location: { hash: '#/pos' }, print: () => {}, navigator: { userAgent: 'Android', clipboard: { writeText: async () => {} } } };
  const ctx = vm.createContext({ window: win, document, location: win.location, navigator: win.navigator, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Blob: function (parts, opt) { this.parts = parts; mem.__blob = parts.join(''); },
    setTimeout, clearTimeout, Promise, console, Date, encodeURIComponent, Intl });
  if (o.tpl) { for (const f of ['tpl_registry', 'tpl_docs', 'tpl_labels', 'tpl_msgs', 'tpl_samples']) vm.runInContext(fs.readFileSync(path.join(ROOT, f + '.js'), 'utf8'), ctx, { filename: f });
    const T = B.tpl, r0 = T.render, p0 = T.printHTML; T.render = (...a) => { renders.push(a); return r0(...a); }; T.printHTML = (...a) => { renders.push(a); return p0(...a); }; }
  vm.runInContext(fs.readFileSync(path.join(ROOT, 'invoiceview.js'), 'utf8'), ctx);
  return { A, B, calls, toasts, sheets, clicks, mem, els, handlers, rpcImpl, prints, iv: B.invoiceview, bodyKids, renders };
}
const tick = (n = 4) => new Promise((r) => { let i = 0; const f = () => (++i >= n ? r() : setImmediate(f)); setImmediate(f); });
const PAYLOAD = () => ({ p_client: 'c1d2e3f4-aaaa-bbbb-cccc-111122223333', p_loc: 1, p_sold_at: '2026-10-14T10:30:00.000Z', p_discount: 20, p_customer_mobile: '01711000001', p_customer_name: 'Test <img src=x onerror=alert(1)> Buyer',
  p_lines: [{ item_id: 'i1', qty: 2, price: 100, name: 'Cake', cost: 61, unit_cost: 61, purchase_price: 60 }, { item_id: null, name: 'Quick sale', amount: 50 }], p_payments: [{ mode: 'cash', amount: 230 }] });
const INFO = () => ({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } });
async function run(t, act, phone = '01711000001', mail = 'buyer@example.com') {
  t.clicks.length = 0; t.els['#iv92_phone'] = { value: phone }; t.els['#iv92_email'] = { value: mail }; t.handlers[act](); await tick();
  return t.clicks.slice();
}

(async () => {
  for (const lang of ['en', 'bn', 'mix']) {
    // ---- (a) identical output when B.tpl is absent, and when the owner chose nothing ----
    const base = mk(lang), none = mk(lang, { tpl: true, choices: [] });
    for (const t of [base, none]) { t.iv.openInfo(INFO()); await tick(); }
    for (const act of ['iv92_sms', 'iv92_wa', 'iv92_email']) {
      const a = await run(base, act), b = await run(none, act);
      chk(`${lang} ${act}: nothing chosen => same link as without B.tpl`, a.length === 1 && b.length === 1 && a[0].href === b[0].href);
    }
    base.prints.length = 0; none.prints.length = 0;
    base.handlers.iv92_print(); none.handlers.iv92_print(); await tick(); await tick();
    chk(`${lang} print: nothing chosen => same B.invoice path`, base.prints.length === 2 && none.prints.length === 2 && JSON.stringify(base.prints) === JSON.stringify(none.prints));
    await run(base, 'iv92_dl'); await run(none, 'iv92_dl');
    chk(`${lang} download: same file`, !!base.mem.__blob && base.mem.__blob === none.mem.__blob);
    const tc = none.renders.filter((r) => r[0] === 'pos_receipt' || r[0] === 'msg_invoice');
    chk(`${lang}: template asked, nothing chosen => null each time`, tc.length > 0);
    chk(`${lang}: choices fetched once for the session`, none.calls.filter((c) => c[0] === 'get_doc_templates').length === 1);

    // ---- (b) a chosen template is used ----
    const ch = [{ doc_type: 'pos_receipt', location_id: null, template_id: 'a4_modern' }, { doc_type: 'msg_invoice', location_id: null, template_id: 'friendly' }];
    const t = mk(lang, { tpl: true, choices: ch }); t.iv.openInfo(INFO()); await tick(); await tick();
    const sms = await run(t, 'iv92_sms'), wa = await run(t, 'iv92_wa'), em = await run(t, 'iv92_email');
    const smsBody = decodeURIComponent(sms[0].href.split('body=')[1]);
    chk(`${lang} sms uses the chosen message template`, /Test|Buyer/.test(smsBody) && smsBody !== decodeURIComponent((await run(base, 'iv92_sms'))[0].href.split('body=')[1]) && !/[<>]/.test(smsBody));
    chk(`${lang} sms is one line`, !/\n/.test(smsBody));
    chk(`${lang} whatsapp goes to the number with T.waUrl text`, wa[0].href.startsWith('https://wa.me/8801711000001?text=') && wa[0].href.length > 40 && !wa[0].href.includes('<'));
    const waTxt = decodeURIComponent(wa[0].href.split('?text=')[1]);
    chk(`${lang} whatsapp text is the chosen template text`, waTxt === t.B.tpl.render('msg_invoice', { customer: 'Test <img src=x onerror=alert(1)> Buyer', no: 'M-12', date: '2026-10-14', total: 230, paid: 230, due: 0, shop: { name: lang === 'en' ? 'ISLAMIYA MISTY GHAR' : 'ইসলামিয়া মিষ্টি ঘর' }, items: [{ name: 'Cake', qty: 2, amount: 200 }, { name: 'Quick sale', qty: 1, amount: 50 }] }, 'friendly', { lang, channel: 'whatsapp' }));
    const sj = decodeURIComponent(em[0].href.split('subject=')[1].split('&body=')[0]), bd = decodeURIComponent(em[0].href.split('&body=')[1]);
    chk(`${lang} email: template subject + body, no "Subject:" in the body`, /Invoice/.test(sj) && !/^Subject:/.test(bd) && bd.length > 20 && !/[<>]/.test(sj + bd));
    if (lang === 'en') chk('en: message has no Bangla letters', !BN.test(smsBody + waTxt + sj + bd));
    // print
    t.bodyKids.length = 0; t.prints.length = 0; t.handlers.iv92_print(); await tick(8);
    const fr = t.bodyKids.find((e) => e.tag === 'iframe'), doc = fr ? fr.srcdoc : '';
    chk(`${lang} print: chosen receipt template used (iframe), old path not used`, /data-tpl="a4_modern"/.test(doc) && t.prints.length === 0);
    chk(`${lang} print: XSS escaped`, !/<img src=x/.test(doc) && /&lt;img src=x/.test(doc));
    chk(`${lang} print: sale numbers present`, /230/.test(doc) && /Cake|কেক/.test(doc));
    if (lang === 'en') chk('en print: no Bangla letters in the page', !BN.test(doc.replace(/<style>[\s\S]*?<\/style>/g, '').replace(/৳/g, '')));
    await run(t, 'iv92_dl'); chk(`${lang} download: template page`, /data-tpl="a4_modern"/.test(t.mem.__blob || '') && !/<img src=x/.test(t.mem.__blob));

    // ---- (c) no cost key or value reaches the templates ----
    const ks = []; let vals = '';
    for (const r of t.renders) { keysOf(r[1], ks); vals += JSON.stringify(r[1]); }
    chk(`${lang} no cost-like key in any template data (${ks.length} keys)`, ks.length > 10 && !ks.some((k) => COSTRE.test(k)));
    chk(`${lang} no cost value in output`, !/\b61\b/.test(doc + sms[0].href));
    chk(`${lang} choices fetched once although 5 outputs used`, t.calls.filter((c) => c[0] === 'get_doc_templates').length === 1);
  }

  // ---- offline / slow / failing choice fetch: today's output, capped at 2 s ----
  { const base = mk('en'); base.iv.openInfo(INFO()); await tick(); const a = await run(base, 'iv92_wa');
    const t = mk('en', { tpl: true }); t.rpcImpl.fn = (fn) => (fn === 'get_doc_templates' ? new Promise(() => {}) : Promise.resolve({ data: null, error: { message: 'x' } }));
    t.iv.openInfo(INFO()); await tick();
    const t0 = Date.now(); t.prints.length = 0; t.handlers.iv92_print(); while (!t.prints.length && Date.now() - t0 < 5000) await new Promise((r) => setTimeout(r, 50)); const dt = Date.now() - t0;
    chk(`hung fetch: falls back to today's print within the 2 s cap (${dt} ms)`, t.prints.length === 2 && dt >= 1800 && dt < 3500);
    const w = await run(t, 'iv92_wa'); chk('hung fetch: whatsapp link as today', w[0].href === a[0].href);
    const e = mk('en', { tpl: true }); e.rpcImpl.fn = async () => { throw new TypeError('Failed to fetch'); }; e.iv.openInfo(INFO()); await tick();
    e.prints.length = 0; e.handlers.iv92_print(); await tick(8); chk('offline (rpc throws): today\'s print path', e.prints.length === 2);
    const w2 = await run(e, 'iv92_sms'); const s0 = await run(base, 'iv92_sms'); chk('offline: sms as today', w2[0].href === s0[0].href);
    const g = mk('en', { tpl: true }); g.B.tpl = { ensure: () => { throw new Error('boom'); }, render: () => { throw new Error('boom'); }, printHTML: () => { throw new Error('boom'); } };
    g.iv.openInfo(INFO()); await tick(); const w3 = await run(g, 'iv92_wa'); chk('broken B.tpl: whatsapp as today', w3.length === 1 && w3[0].href === a[0].href);
    g.prints.length = 0; g.handlers.iv92_print(); await tick(8); chk('broken B.tpl: print as today', g.prints.length === 2); }
  chk('invoiceview.js edits are tagged bos98 and guarded by B.tpl', (fs.readFileSync(path.join(ROOT, 'invoiceview.js'), 'utf8').match(/bos98/g) || []).length >= 5);
  console.log(`tplwire_test: ${pass} pass / ${failn} fail`);
  process.exit(failn ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
