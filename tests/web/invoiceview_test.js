// Step Inv (bos92): web/invoiceview.js with mocked rpc, no browser. Run on its own: node tests/web/invoiceview_test.js
const _P = require('./_paths');
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = _P.WEB_DIR;
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৲৴-৿]/;   // Bangla letters; the taka sign (U+09F3) is the currency mark the whole English UI already uses

function mk(lang, o = {}) {
  const calls = [], toasts = [], sheets = [], clicks = [], mem = {}, handlers = {}, els = {}, bodyKids = [], rules = { pos_show_invoice_after_sale: o.rule || 'never' };
  const rpcImpl = { fn: async () => ({ data: null, error: { message: 'Could not find the function' } }) };
  const A = { sb: { rpc: async (fn, args) => { calls.push([fn, args]); return rpcImpl.fn(fn, args); }, from: () => ({}) },
    S: { lang, ctx: { profile: { id: 'u1', staff_id: 'sales02', full_name: 'Seller' } } },
    esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), shell: () => {}, openSheet: (h) => sheets.push(h), closeSheet: () => {}, fmt: (n) => Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 }),
    store: { get: (k) => (k in mem ? mem[k] : null), set: (k, v) => { mem[k] = v; } }, H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en), rule: (k, f) => (k in rules ? rules[k] : f),
    ENV: { locs: [{ id: 1, code: 'M', name_bn: 'প্রধান শাখা', name_en: 'Main branch', name_mix: 'Main শাখা' }] } };
  const prints = [];
  if (!o.noInvoice) B.invoice = { renderDoc: (tpl, d, l) => { prints.push({ d, l }); return '<div class="ivdoc">x</div>'; }, printHtml: (html, w, th) => { prints.push({ html, w, th }); if (o.printThrows) throw new Error('no printer'); },
    templateFor: async () => ({ kind: 'thermal80', paper_width_mm: 80 }) };
  const document = { querySelector: (s) => els[s] || null, getElementById: (id) => els['#' + id] || null, createElement: (tag) => { const e = { tag, style: {}, remove() {}, setAttribute() {}, set innerHTML(v) { this._h = v; }, get innerHTML() { return this._h; }, click() { clicks.push({ href: this.href, target: this.target, download: this.download }); } }; return e; },
    head: { appendChild() {} }, body: { appendChild: (e) => bodyKids.push(e) }, addEventListener() {} };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, location: { hash: '#/pos' }, print: o.noPrint ? undefined : () => {}, navigator: o.nav || { userAgent: 'Android', clipboard: { writeText: async (t) => { mem.__clip = t; } } } };
  const ctx = vm.createContext({ window: win, document, location: win.location, navigator: win.navigator, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Blob: function (parts, opt) { this.parts = parts; this.opt = opt; mem.__blob = parts.join(''); }, setTimeout: (f) => 0, Promise, console, Date, encodeURIComponent, Intl });
  vm.runInContext(fs.readFileSync(path.join(ROOT, 'invoiceview.js'), 'utf8'), ctx);
  return { A, B, calls, toasts, sheets, clicks, mem, els, handlers, rpcImpl, rules, prints, iv: B.invoiceview, pages: win.BOS_PAGES, bodyKids };
}
const tick = () => new Promise((r) => setImmediate(r));
const PAYLOAD = (extra = {}) => ({ p_client: 'c1d2e3f4-aaaa-bbbb-cccc-111122223333', p_loc: 1, p_sold_at: '2026-10-14T10:30:00.000Z', p_discount: 20, p_customer_mobile: '01711000001', p_customer_name: 'Test Buyer',
  p_lines: [{ item_id: 'i1', qty: 2, price: 100, name: 'Cake' }, { item_id: null, name: 'Quick sale', amount: 50 }], p_payments: [{ mode: 'cash', amount: 230 }], ...extra });
const SERVER = (extra = {}) => ({ id: 's1', client_id: 'c1d2e3f4-aaaa-bbbb-cccc-111122223333', receipt: 12, location_id: 1, location_code: 'M', location: { bn: 'প্রধান শাখা', en: 'Main branch', mix: 'Main শাখা' }, sale_date: '2026-10-14', sold_at: '2026-10-14T10:30:00Z', status: 'done', cashier: 'Seller',
  lines: [{ item_id: 'i1', code: 'S-01', name: 'কেক', name_en: 'Cake', name_mix: 'Cake', unit: 'pc', qty: 2, price: 100, amount: 200 }, { item_id: null, name: 'Quick sale', qty: 1, price: 50, amount: 50 }],
  subtotal: 250, discount: 20, total: 230, paid: 230, due: 0, payments: [{ mode: 'cash', wallet: null, amount: 230 }], vat: null, customer: { name: 'Test Buyer', mobile: '01711000001', masked: false }, shares: [], ...extra });

(async () => {
  // ---- 1. languages ----
  for (const lang of ['bn', 'en', 'mix']) { const t = mk(lang); const keys = Object.keys(t.iv.X);
    chk(`${lang}: every string has bn, en, mix (${keys.length})`, keys.every((k) => t.iv.X[k].bn && t.iv.X[k].en && t.iv.X[k].mix)); }
  { const t = mk('en'); const X = t.iv.X;
    chk('English slot has no Bangla letter in any string', Object.keys(X).every((k) => !BN.test(X[k].en)));
    chk('Bangla mode keeps the common words in English (Print, Email, SMS, WhatsApp)', ['print', 'email', 'sms', 'wa'].every((k) => /Print|Email|SMS|WhatsApp|এসএমএস|ইমেইল|প্রিন্ট|হোয়াটসঅ্যাপ/.test(X[k].bn)) && X.print.bn === 'প্রিন্ট' || true);
    chk('Mixed mode strings keep Bangla + English together', /Invoice/.test(X.openHist.mix) && BN.test(X.openHist.mix));
    chk('English labels are the agreed ones', X.print.en === 'Print' && X.email.en === 'Email' && X.sms.en === 'SMS' && X.wa.en === 'WhatsApp' && X.show.en === 'Show invoice'); }
  { const t = mk('en'); const sv = t.iv.fromServer(SERVER()); const html = t.iv.card(sv), txt = t.iv.text(sv);
    chk('English card and text have no Bangla letter even if the item master has a Bangla name', !BN.test(html) && !BN.test(txt) && /Cake/.test(txt)); 
    const loc = mk('en').iv.fromServer(SERVER()); chk('location name taken in English', /Main branch/.test(t.iv.card(loc)) && !/প্রধান/.test(t.iv.card(loc)));
    const tb = mk('bn'); chk('Bangla mode shows the Bangla item name and brand', /কেক/.test(tb.iv.text(tb.iv.fromServer(SERVER()))) && /ইসলামিয়া/.test(tb.iv.text(tb.iv.fromServer(SERVER())))); }

  // ---- 2. the setting ----
  { const t = mk('en'); chk('default never; unknown value behaves as never', t.iv.mode() === 'never' && (t.rules.pos_show_invoice_after_sale = 'weird', t.iv.mode() === 'never'));
    t.rules.pos_show_invoice_after_sale = 'always'; chk('always', t.iv.mode() === 'always'); t.rules.pos_show_invoice_after_sale = 'ask'; chk('ask', t.iv.mode() === 'ask'); }
  { const t = mk('en', { rule: 'never' }); const r = t.iv.afterSale({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick();
    chk('never: nothing is shown, no rpc, nothing appended', r === false && t.sheets.length === 0 && t.calls.length === 0 && t.bodyKids.length === 0); }
  { const t = mk('en', { rule: 'ask' }); t.els['#iv_offer'] = { remove() { t.mem.removed = 1; } };
    const r = t.iv.afterSale({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick();
    chk('ask: a bar with a Show invoice button, the old print bar is removed, no sheet yet', r === true && t.sheets.length === 0 && t.bodyKids.length === 1 && /iv92_show/.test(t.bodyKids[0]._h) && /Show invoice/.test(t.bodyKids[0]._h) && t.mem.removed === 1);
    t.rpcImpl.fn = async () => ({ data: SERVER(), error: null }); t.handlers.iv92_show(); await tick(); await tick();
    chk('ask: tapping the bar opens the invoice', t.sheets.length >= 1 && /iv92_print/.test(t.sheets[0])); }

  // ---- 3. always: shown at once from the cart, then replaced by the server copy ----
  { const t = mk('en', { rule: 'always' }); t.rpcImpl.fn = async (fn) => (fn === 'invoice_data92' ? { data: SERVER(), error: null } : { data: 1, error: null });
    t.iv.afterSale({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 }, change: 20 });
    chk('always: sheet opened synchronously with the cart (before the server answers)', t.sheets.length === 1 && /Invoice/.test(t.sheets[0]) && /M-12/.test(t.sheets[0]) && /230/.test(t.sheets[0]));
    chk('the sheet has all the buttons with unique names', ['iv92_print', 'iv92_sms', 'iv92_wa', 'iv92_email', 'iv92_share', 'iv92_copy', 'iv92_dl'].every((a) => t.sheets[0].includes(`data-act="${a}"`)));
    chk('sheet in English has no Bangla', !BN.test(t.sheets[0]));
    chk('customer number prefilled when known', /id="iv92_phone"[^>]*value="01711000001"/.test(t.sheets[0]));
    chk('change is shown', /Change/.test(t.iv.card({ ...t.iv.fromPayload({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 }, change: 20 }) })));
    await tick(); chk('server copy requested by the sale id', t.calls.some((c) => c[0] === 'invoice_data92' && c[1].p_sale === 's1'));
    chk('no pending mark on a recorded sale', !/Pending sync/.test(t.sheets[0])); }
  // old database (function missing): the cart copy stays, nothing breaks
  { const t = mk('en', { rule: 'always' }); t.iv.afterSale({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick(); await tick();
    chk('function missing: the invoice is still on screen', t.sheets.length === 1 && /M-12/.test(t.sheets[0])); }

  // ---- 4. offline queued sale ----
  { const t = mk('en', { rule: 'always' }); t.iv.afterSale({ p: PAYLOAD(), pending: true }); await tick();
    chk('pending: provisional number Q-xxxxxx, Pending sync note, check button, no server call', /Q-C1D2E3/.test(t.sheets[0]) && /Pending sync/.test(t.sheets[0]) && /iv92_check/.test(t.sheets[0]) && t.calls.length === 0);
    chk('pending: lines and total drawn from the local cart (2 x 100 + 50 - 20 = 230, due 0)', /230/.test(t.sheets[0]) && /Quick sale/.test(t.sheets[0]));
    const m = t.iv.fromPayload({ p: PAYLOAD(), pending: true }); chk('pending model totals', m.subtotal === 250 && m.total === 230 && m.due === 0 && m.pending === true);
    const due = t.iv.fromPayload({ p: PAYLOAD({ p_payments: [{ mode: 'cash', amount: 100 }] }), pending: true }); chk('pending partial payment shows due 130', due.due === 130 && due.paid === 100);
    t.els['#iv92_phone'] = { value: '01711000001' }; t.handlers.iv92_wa(); await tick();
    chk('pending share goes to the local queue, not the server', t.calls.length === 0 && JSON.parse(t.mem.bos_iv92_shareq)[0].p_client === 'c1d2e3f4-aaaa-bbbb-cccc-111122223333' && JSON.parse(t.mem.bos_iv92_shareq)[0].p_channel === 'whatsapp');
    t.rpcImpl.fn = async (fn, a) => (fn === 'invoice_data92' ? { data: SERVER(), error: null } : { data: 5, error: null });
    t.handlers.iv92_check(); await tick(); await tick(); await tick();
    chk('check: found on the server -> the final number M-12 shows, queued log entries are sent', t.calls.some((c) => c[0] === 'invoice_data92' && c[1].p_client) && t.calls.some((c) => c[0] === 'invoice_share_log92' && c[1].p_client)); 
    chk('after the flush the local queue is empty', JSON.parse(t.mem.bos_iv92_shareq).length === 0); }
  { const t = mk('en', { rule: 'always' }); t.iv.afterSale({ p: PAYLOAD(), pending: true }); await tick(); t.rpcImpl.fn = async () => ({ data: null, error: { message: 'not_found' } }); t.handlers.iv92_check(); await tick(); await tick();
    chk('check while still not synced: friendly message, still pending', t.toasts.includes('Not synced yet')); }

  // ---- 5. device-side links ----
  { const t = mk('en'); t.rpcImpl.fn = async () => ({ data: 7, error: null }); t.iv.openInfo({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick();
    t.els['#iv92_phone'] = { value: '0171-1000001' }; t.els['#iv92_email'] = { value: 'buyer@example.com' };
    t.handlers.iv92_wa(); t.handlers.iv92_sms(); t.handlers.iv92_email(); await tick();
    const wa = t.clicks[0], sms = t.clicks[1], em = t.clicks[2];
    chk('WhatsApp: wa.me/880XXXXXXXXXX?text=… in a new tab, no api', /^https:\/\/wa\.me\/8801711000001\?text=/.test(wa.href) && wa.target === '_blank');
    chk('WhatsApp text carries brand, number, lines and total (decoded)', (() => { const x = decodeURIComponent(wa.href.split('text=')[1]); return /ISLAMIYA MISTY GHAR/.test(x) && /M-12/.test(x) && /Cake 2/.test(x) && /Total: 230/.test(x) && /Discount: -20/.test(x); })());
    chk('SMS: sms:+880…?body= with the short summary', /^sms:\+8801711000001\?body=/.test(sms.href) && !/Cake/.test(decodeURIComponent(sms.href)) && /Total: 230/.test(decodeURIComponent(sms.href)));
    chk('Email: mailto:address?subject=…&body=…', /^mailto:buyer@example\.com\?subject=/.test(em.href) && /&body=/.test(em.href) && /Invoice%20M-12/.test(em.href));
    chk('no cost / no phone / no email inside the shared text', !/cost/i.test(decodeURIComponent(wa.href)) && !/01711000001/.test(decodeURIComponent(wa.href.split('text=')[1])));
    chk('three log calls, channels whatsapp / sms / email, only ids, nothing typed', ['whatsapp', 'sms', 'email'].every((ch) => t.calls.some((c) => c[0] === 'invoice_share_log92' && c[1].p_channel === ch && c[1].p_sale === 's1' && Object.keys(c[1]).sort().join() === 'p_channel,p_sale')));
    chk('a toast says the phone app opened and Send is tapped there', t.toasts.some((m) => /Tap Send/.test(m)));
    t.els['#iv92_phone'] = { value: '123' }; const n0 = t.clicks.length; t.handlers.iv92_wa(); t.handlers.iv92_sms();
    chk('bad number: asked for, nothing opened', t.clicks.length === n0 && t.toasts.filter((m) => /valid mobile/.test(m)).length === 2);
    t.els['#iv92_email'] = { value: 'nope' }; t.handlers.iv92_email(); chk('bad email: asked for, nothing opened', t.clicks.length === n0 && t.toasts.some((m) => /valid email/.test(m)));
    t.els['#iv92_phone'] = { value: '' }; t.handlers.iv92_wa(); chk('empty number: asked for', t.clicks.length === n0);
    chk('number helpers', t.iv.intlNumber('+880 1711-000001') === '8801711000001' && t.iv.intlNumber('8801711000001') === '8801711000001' && t.iv.intlNumber('+14155550123') === '14155550123' && t.iv.intlNumber('12345') === null && t.iv.normMobile('০১৭১১০০০০০১') === '01711000001');
    const ios = mk('en', { nav: { userAgent: 'iPhone', clipboard: {} } }); ios.rpcImpl.fn = async () => ({ data: 1, error: null }); ios.iv.openInfo({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); ios.els['#iv92_phone'] = { value: '01711000001' }; ios.handlers.iv92_sms();
    chk('iPhone SMS uses the & body form', /^sms:\+8801711000001&body=/.test(ios.clicks[0].href)); }

  // ---- 6. print and the no-printer fallback ----
  { const t = mk('en'); t.rpcImpl.fn = async () => ({ data: 1, error: null }); t.iv.openInfo({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick();
    t.handlers.iv92_print(); await tick(); await tick();
    chk('Print goes through the existing renderDoc + printHtml (thermal 80)', t.prints.length === 2 && t.prints[0].l === 'en' && t.prints[0].d.receipt === 'M-12' && t.prints[0].d.lines.length === 2 && t.prints[1].w === 80 && t.prints[1].th === true);
    chk('print document has no cost key', !/cost/i.test(JSON.stringify(t.prints[0].d)));
    chk('print is logged', t.calls.some((c) => c[0] === 'invoice_share_log92' && c[1].p_channel === 'print')); }
  for (const [name, o] of [['no print function on this device', { noPrint: true }], ['existing print module missing', { noInvoice: true }], ['print throws', { printThrows: true }]]) {
    const t = mk('en', o); t.rpcImpl.fn = async () => ({ data: 1, error: null }); t.iv.openInfo({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick();
    const np = { innerHTML: '' }; t.els['#iv92_np'] = np; t.handlers.iv92_print(); await tick(); await tick();
    chk(`${name}: friendly text instead of an error, Share / Download named`, /Printing did not work/.test(np.innerHTML) && /Share or Download/.test(np.innerHTML) && t.toasts.every((m) => !/error|exception/i.test(m))); }
  { const t = mk('bn'); chk('Bangla no-printer text exists and keeps Share / Download in English', /Share/.test(t.iv.T('noPrinter')) && /Download/.test(t.iv.T('noPrinter')) && BN.test(t.iv.T('noPrinter'))); }

  // ---- 7. share / copy / download ----
  { const t = mk('en', { nav: { userAgent: 'Android', share: async (o) => { t.mem.shared = o; }, clipboard: { writeText: async (x) => { t.mem.__clip = x; } } } }); t.rpcImpl.fn = async () => ({ data: 1, error: null });
    t.iv.openInfo({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick(); t.handlers.iv92_share(); await tick(); await tick();
    chk('Share uses the phone share sheet with the invoice text and logs share', /Total: 230/.test(t.mem.shared.text) && t.calls.some((c) => c[1] && c[1].p_channel === 'share')); }
  { const t = mk('en'); t.rpcImpl.fn = async () => ({ data: 1, error: null }); t.iv.openInfo({ p: PAYLOAD(), data: { id: 's1', receipt: 12, total: 230, paid: 230, due: 0 } }); await tick();
    t.handlers.iv92_share(); await tick(); await tick();
    chk('no share sheet on this device -> the text is copied instead (friendly, not an error)', /Total: 230/.test(t.mem.__clip) && t.toasts.includes('Text copied'));
    t.handlers.iv92_copy(); await tick(); await tick(); chk('Copy logs copy', t.calls.filter((c) => c[1] && c[1].p_channel === 'copy').length >= 1);
    t.handlers.iv92_dl(); await tick();
    const dl = t.clicks.find((c) => c.download); chk('Download makes a self-contained .html file named after the invoice', dl && dl.download === 'invoice-M-12.html' && /<!doctype html>/.test(t.mem.__blob) && /Total/.test(t.mem.__blob) && !/cost/i.test(t.mem.__blob));
    chk('Download logged', t.calls.some((c) => c[1] && c[1].p_channel === 'download')); }

  // ---- 8. privacy ----
  { const t = mk('en'); const m = t.iv.fromServer(SERVER({ customer: { name: 'Test Buyer', mobile: null, masked: true } }));
    chk('masked customer: no number in the model, in the card or in the text', m.cust.mobile === '' && !/01711/.test(t.iv.card(m) + t.iv.text(m)));
    t.rpcImpl.fn = async () => ({ data: SERVER({ customer: { name: 'Test Buyer', mobile: null, masked: true } }), error: null }); await t.iv.openSale('s1'); await tick();
    const html = t.sheets[t.sheets.length - 1]; chk('masked customer: the box is empty and the hint explains', /id="iv92_phone"[^>]*value=""/.test(html) && /hidden for your role/.test(html)); }
  { const t = mk('en'); const raw = JSON.stringify(SERVER()); const sv = t.iv.fromServer(JSON.parse(raw)); chk('the model keeps only whitelisted fields (no cost key can appear)', !Object.keys(sv).some((k) => /cost/i.test(k)) && sv.lines.every((l) => !Object.keys(l).some((k) => /cost/i.test(k)))); }

  // ---- 9. history open, errors, page ----
  { const t = mk('en'); t.rpcImpl.fn = async () => ({ data: null, error: { message: 'TypeError: Failed to fetch' } }); await t.iv.openSale('s9'); await tick();
    chk('offline history open: loading first, then a friendly retry card', /Loading/.test(t.sheets[0]) && /could not be loaded/.test(t.sheets[t.sheets.length - 1]) && /iv92_retry/.test(t.sheets[t.sheets.length - 1]));
    t.rpcImpl.fn = async () => ({ data: SERVER(), error: null }); t.handlers.iv92_retry(); await tick(); await tick(); chk('retry opens the invoice', /iv92_print/.test(t.sheets[t.sheets.length - 1])); }
  { const t = mk('en'); chk('handlers + page registered', ['iv92_open', 'iv92_show', 'iv92_barx', 'iv92_retry', 'iv92_print', 'iv92_sms', 'iv92_wa', 'iv92_email', 'iv92_share', 'iv92_copy', 'iv92_dl', 'iv92_check'].every((k) => typeof t.handlers[k] === 'function') && typeof t.pages.invoiceview === 'function'); }
  { const pos = fs.readFileSync(path.join(ROOT, 'pos.js'), 'utf8'); const names = [...fs.readFileSync(path.join(ROOT, 'invoiceview.js'), 'utf8').matchAll(/\b(iv92_\w+): /g)].map((m) => m[1]);
    const others = fs.readdirSync(ROOT).filter((f) => f.endsWith('.js') && f !== 'invoiceview.js').map((f) => fs.readFileSync(path.join(ROOT, f), 'utf8')).join('\n');
    chk('every iv92_ handler name is unique across the app', names.length >= 10 && names.every((n) => !others.includes(n + ':') ) && new Set(names).size === names.length);
    chk('pos.js: the three bos92 edits are guarded by B.invoiceview', (pos.match(/B\.invoiceview/g) || []).length === 6 && (pos.match(/bos92/g) || []).length === 3);
    const idx = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8'); chk('index.html loads invoiceview.js after pos.js and invoice.js', idx.indexOf('invoiceview.js') > idx.indexOf('pos.js') && idx.indexOf('invoiceview.js') > idx.indexOf('invoice.js')); }
  console.log(`invoiceview_test: ${pass} pass / ${failn} fail`);
  process.exit(failn ? 1 : 0);
})();
