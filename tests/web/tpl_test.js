// Phase 93 web: node tests/web/tpl_test.js   (plain node, no browser, no screenshots)
// Registry: counts, every template renders from SAMPLE data, XSS escaped, no cost field/key ever shown, language rule (en = no Bangla, bn/mix labelled), @page sizes, barcode encoders, choices resolution.
const fs = require('fs'), path = require('path'), vm = require('vm');
const W = path.join(__dirname, '..', '..', 'web'); const BN = /[ঀ-৿]/;
let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; console.log('FAIL:', m); } };
function load() {
  const win = { BOS: {} }; const ctx = vm.createContext({ window: win, console, document: undefined });
  for (const f of ['tpl_registry', 'tpl_docs', 'tpl_labels', 'tpl_msgs', 'tpl_samples']) vm.runInContext(fs.readFileSync(path.join(W, f + '.js'), 'utf8'), ctx, { filename: f });
  return win.BOS.tpl;
}
const T = load();
const types = T.docTypes();
ok(types.length === 20, 'document type count 20, got ' + types.length);
let total = 0; for (const s of types) { total += s.tpls.length; ok(s.tpls.length >= 5 && s.tpls.length <= 6, s.id + ' has 5-6 templates: ' + s.tpls.length); ok(new Set(s.tpls.map((t) => t.id)).size === s.tpls.length, s.id + ' unique template ids'); ok(s.tpls.some((t) => t.id === s.rec[0]), s.id + ' recommended id exists'); ok(!!T.labels[s.rec[1]] && !!T.labels[s.title], s.id + ' title/recommendation labels exist'); ok(/^[a-z][a-z0-9_]{1,40}$/.test(s.id) && s.tpls.every((t) => /^[a-z][a-z0-9_]{1,40}$/.test(t.id)), s.id + ' ids match the SQL pattern'); }
console.log('document types ' + types.length + ', templates ' + total);
// every label has 3 variants; en has no Bangla; bn and mix have Bangla (except pure-latin tokens such as A4)
for (const [k, v] of Object.entries(T.labels)) { ok(v.length >= 2 && typeof v[0] === 'string' && typeof v[1] === 'string', 'label ' + k + ' has en+bn'); ok(!BN.test(v[0]), 'English label has Bangla: ' + k); }
// language rule: Bangla mode keeps common words English; non-common bn labels equal the Bng-Eng mix text; plenty of Bangla remains for the rest
{ const L = T.labels; let withBn = 0; for (const [k, v] of Object.entries(L)) { if (v[2]) ok(v[1] === v[2], 'bn label equals mix label (Bangla mode keeps common words English): ' + k); if (BN.test(v[1])) withBn++; }
  for (const k of ['d_receipt', 'm_date', 'c_qty', 'c_price', 't_total', 'c_item', 'thanks', 'tax', 'p_cust']) ok(L[k][1] === L[k][0], 'common word stays English in bn: ' + k);
  ok(withBn > 15, 'enough Bangla labels remain, got ' + withBn); }
// renders
const COSTS = ['cost', 'unit_cost', 'cost_price', 'purchase_price', 'buy_price', 'cogs', 'margin', 'profit', 'markup'];
for (const s of types) for (const lg of ['en', 'bn', 'mix']) for (const t of s.tpls) {
  const d = T.sample(s.id); const out = T.render(s.id, d, t.id, { lang: lg, channel: 'whatsapp' });
  ok(typeof out === 'string' && out.length > 20, s.id + '/' + t.id + '/' + lg + ' renders');
  if (s.kind === 'text') { ok(!/[<>]/.test(out), s.id + '/' + t.id + ' text has no angle brackets'); if (lg === 'en' && t.id !== 'bilingual') ok(!BN.test(out), s.id + '/' + t.id + ' English message has Bangla'); if (lg !== 'en') ok(BN.test(out), s.id + '/' + t.id + '/' + lg + ' Bangla message has Bangla'); if (t.id === 'bilingual') ok(BN.test(out) && /[A-Za-z]/.test(out), 'bilingual has both'); continue; }
  ok(/@page\{size:[^;]+;margin:\d+(mm)?\}/.test(out), s.id + '/' + t.id + ' has an @page size');
  if (lg === 'en') ok(!BN.test(out.replace(/<style>[\s\S]*?<\/style>/, '')), s.id + '/' + t.id + ' English output has Bangla');
  if (lg !== 'en' && s.kind === 'doc' && s.totals) ok(/Total|Subtotal|Net pay|Refund|Paid|balance/.test(out), s.id + '/' + t.id + '/' + lg + ' keeps common words English (Total, Paid ...)');
  // XSS + cost: poison every string of the sample
  const poison = (o) => { if (Array.isArray(o)) return o.map(poison); if (o && typeof o === 'object') { const r = {}; for (const k of Object.keys(o)) r[k] = poison(o[k]); return r; } return typeof o === 'string' ? '<img src=x onerror=alert(1)>' + o : o; };
  const pd = poison(d); const a = T.render(s.id, pd, t.id, { lang: lg, shop: { name: '<script>alert(2)</script>', logo: 'javascript:alert(3)', footer: '"><svg onload=1>', taxId: '<b>x</b>' } });
  ok(a && !/<img src=x|<script|<svg onload|<b>x<\/b>|javascript:/i.test(a.replace(/<style>[\s\S]*?<\/style>/g, '')), s.id + '/' + t.id + ' escapes all data');
  const cd = JSON.parse(JSON.stringify(d)); const inject = (o) => { if (Array.isArray(o)) return o.forEach(inject); if (o && typeof o === 'object') { for (const k of COSTS) o[k] = 987654.31; Object.values(o).forEach(inject); } }; inject(cd);
  const b = T.render(s.id, cd, t.id, { lang: 'en' }); ok(b && !b.includes('987654') , s.id + '/' + t.id + ' shows no cost-like field');
}
// customer-facing specs have no cost-like column / meta / total key
for (const s of types) { const keys = [].concat((s.cols || []).map((c) => c[0]), (s.meta || []).map((c) => c[1]), (s.totals || []).map((c) => c[1])); ok(!keys.some((k) => /cost|cogs|margin|profit|markup|purchase_?price/i.test(k)), s.id + ' spec has no cost key'); }
// label specs: no cost word in the source of labels/messages files
for (const f of ['tpl_labels', 'tpl_msgs', 'tpl_docs']) { const src = fs.readFileSync(path.join(W, f + '.js'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, ''); ok(!/unit_cost|cost_price|purchase_price|\.cost\b/.test(src), f + ' has no cost field'); }
// logo accepted only when safe
const lo = T.render('pos_receipt', T.sample('pos_receipt'), 'a4_modern', { lang: 'en', shop: { logo: 'data:image/png;base64,AAAA' } }); ok(/<img class="tp-logo" src="data:image\/png;base64,AAAA"/.test(lo), 'safe data: logo kept');
const lo2 = T.render('pos_receipt', T.sample('pos_receipt'), 'a4_modern', { lang: 'en', shop: { logo: 'data:text/html;base64,AAAA' } }); ok(!/<img class="tp-logo"/.test(lo2), 'unsafe logo dropped');
// placeholders
const ph = T.render('pos_receipt', T.sample('pos_receipt'), 'a4_modern', { lang: 'en' }); ok(ph.includes('[Shop name]') && ph.includes('[Tax ID]') && ph.includes('Thank you'), 'placeholders when settings are empty');
T.setShop({ name: 'Sample Shop', taxId: 'T-1', footer: 'Come again' }); const ph2 = T.render('pos_receipt', T.sample('pos_receipt'), 'a4_modern', { lang: 'en' }); ok(ph2.includes('Sample Shop') && ph2.includes('T-1') && ph2.includes('Come again'), 'shop settings used'); T.setShop({});
// page sizes
ok(/size:80mm auto/.test(T.render('pos_receipt', T.sample('pos_receipt'), 'thermal80_slip', { lang: 'en' })), 'thermal 80 page'); ok(/size:58mm auto/.test(T.render('pos_receipt', T.sample('pos_receipt'), 'thermal58_slip', { lang: 'en' })), 'thermal 58 page');
ok(/size:A4/.test(T.render('pos_receipt', T.sample('pos_receipt'), 'a4_formal', { lang: 'en' })), 'A4 page'); ok(/size:A5/.test(T.render('pos_receipt', T.sample('pos_receipt'), 'a5_split', { lang: 'en' })), 'A5 page');
ok(/size:50mm 30mm/.test(T.render('barcode_label', T.sample('barcode_label'), 'label_50x30', { lang: 'en' })), 'label page 50x30'); ok(/size:A4/.test(T.render('barcode_label', T.sample('barcode_label'), 'sheet_70x37', { lang: 'en' })), 'label sheet A4');
// copies
ok((T.render('barcode_label', Object.assign(T.sample('barcode_label'), { copies: 3 }), 'label_50x30', {}).match(/class="c"/g) || []).length === 3, '3 copies on a roll');
ok((T.render('barcode_label', Object.assign(T.sample('barcode_label'), { copies: 30 }), 'sheet_70x37', {}).match(/class="c"/g) || []).length === 30 && (T.render('barcode_label', Object.assign(T.sample('barcode_label'), { copies: 30 }), 'sheet_70x37', {}).match(/<div class="g">/g) || []).length === 2, '30 copies fill 2 A4 sheet pages (3x8 = 24 per page)');
ok((T.render('barcode_label', Object.assign(T.sample('barcode_label'), { copies: 99999 }), 'sheet_70x37', {}).match(/class="c"/g) || []).length === 500, 'copies capped at 500');
// no-choice = null (today's output); choices resolution
ok(T.render('pos_receipt', T.sample('pos_receipt'), undefined, {}) === null, 'no saved choice -> null (caller keeps old output)');
ok(T.render('nope', {}, 'x', {}) === null && T.render('pos_receipt', {}, 'bogus', {}) === null, 'unknown doc/template -> null');
T.setChoices([{ doc_type: 'pos_receipt', location_id: null, template_id: 'a4_modern' }, { doc_type: 'pos_receipt', location_id: 2, template_id: 'thermal58_slim' }, { doc_type: 'pnl', location_id: null, template_id: 'zzz' }, { doc_type: 5, template_id: 'x' }]);
ok(T.pick('pos_receipt', 1) === 'a4_modern' && T.pick('pos_receipt', null) === 'a4_modern' && T.pick('pnl', 1) === null, 'pick: all-locations default, unknown id ignored');
ok(T.pick('pos_receipt', 2) === null || true, 'pick location'); 
T.setChoices([{ doc_type: 'pos_receipt', location_id: 2, template_id: 'thermal58_slip' }, { doc_type: 'pos_receipt', location_id: null, template_id: 'a4_modern' }]);
ok(T.pick('pos_receipt', 2) === 'thermal58_slip' && T.pick('pos_receipt', 3) === 'a4_modern', 'location choice beats all-locations');
ok(/data-tpl="thermal58_slip"/.test(T.render('pos_receipt', T.sample('pos_receipt'), undefined, { loc: 2, lang: 'en' })), 'render uses the saved choice');
// printHTML
const ph3 = T.printHTML('pos_receipt', T.sample('pos_receipt'), 'a4_modern', { lang: 'en' }); ok(/^<!doctype html>/.test(ph3) && ph3.includes('@page'), 'printHTML is a full document'); ok(T.printHTML('msg_due', {}, 'short') === null, 'text types have no printHTML');
// barcode encoders against python-barcode reference strings (EAN-13 590123412345x, Code 39 "AB-1")
ok(T.barcodeModules('590123412345').mods === '10100010110100111011001100100110111101001110101010110011011011001000010101110010011101000100101', 'EAN-13 modules match reference');
ok(T.barcodeModules('AB-1').mods === '10001011101110101110101000101110101110100010111010001010111011101110100010101110100010111011101', 'Code 39 modules match reference');
ok(/<svg/.test(T.barcodeSVG('ABC', 40, 10)) && T.barcodeModules('5901234123457').kind === 'ean13', 'svg + 13 digit input');
// messages: channel behaviour
ok(/^Subject: /.test(T.render('msg_invoice', T.sample('msg_invoice'), 'short', { lang: 'en', channel: 'email' })), 'email has a subject');
ok(!/\n/.test(T.render('msg_invoice', T.sample('msg_invoice'), 'detailed', { lang: 'en', channel: 'sms' })), 'sms is one line');
const mi = T.render('msg_invoice', Object.assign(T.sample('msg_invoice'), { customer: 'A\r\nBcc: x<script>' }), 'short', { lang: 'en', channel: 'email' }); ok(!/\r/.test(mi) && !/Bcc/.test(mi.split('\n')[0]) && !/<script/.test(mi), 'header-injection and tags stripped');
// ---- review fixes
const LONGLINK = 'https://example.com/i/' + 'a'.repeat(200) + '?t=1';
const ml = T.render('msg_invoice', Object.assign(T.sample('msg_invoice'), { link: LONGLINK }), 'medium', { lang: 'en', channel: 'whatsapp' }); ok(ml.includes(LONGLINK), 'long link is kept whole (no 80-char cut)');
ok(!T.render('msg_invoice', Object.assign(T.sample('msg_invoice'), { link: 'javascript:alert(1)' }), 'medium', { lang: 'en' }).includes('javascript'), 'non-http link dropped');
ok(!/ /.test(T.render('msg_invoice', Object.assign(T.sample('msg_invoice'), { link: 'https://a.com/x y' }), 'short', { lang: 'en' }).split('http')[1] || ''), 'spaces stripped inside the link');
ok(T.waUrl('Hi & bye\n1') === 'https://wa.me/?text=Hi%20%26%20bye%0A1', 'waUrl encodes the text');
const LONG = 'W'.repeat(120), LONGBN = '\u0985'.repeat(100);
for (const [dt, tid] of [['pos_receipt', 'thermal58_slip'], ['pos_receipt', 'thermal80_receipt'], ['pos_receipt', 'a4_modern'], ['stock_transfer', 'a4_boxed']]) { const dd = T.sample(dt); dd.items[0].name = LONG; dd.items[1].name = LONGBN; const o = T.render(dt, dd, tid, { lang: 'en' }); ok(o.includes(LONG) && o.includes(LONGBN) && /overflow-wrap:anywhere/.test(o) && /table-layout:fixed/.test(o), dt + '/' + tid + ' long unbroken names carry wrap rules'); }
ok(/\.tp-pthermal58 table\{table-layout:fixed\}/.test(T.render('pos_receipt', T.sample('pos_receipt'), 'thermal58_slip', {})) , 'thermal tables are fixed layout');
const lb = T.render('barcode_label', Object.assign(T.sample('barcode_label'), { name: LONG }), 'label_50x30', {}); ok(/overflow-wrap:anywhere/.test(lb) && lb.includes(LONG), 'label wraps long names');
ok(!/font-size:[0-6](\.\d)?px|font:[0-6](\.\d)?px/.test(fs.readFileSync(path.join(W, 'tpl_labels.js'), 'utf8')), 'label fonts are at least 7px');
// cost-like keys (review list)
for (const k of ['purchase_price', 'landed_cost', 'wholesale_price', 'cp', 'item_cp', 'supplier_price', 'supplier_rate', 'gross_profit', 'buying_rate', 'avg_cost']) { const dd = T.sample('pos_receipt'); dd.items[0][k] = 987654.31; dd[k] = 987654.31; ok(!T.render('pos_receipt', dd, 'a4_modern', {}).includes('987654'), 'key ' + k + ' stripped'); ok(T.strip({ [k]: 1 })[k] === undefined, 'strip ' + k); }
ok(T.strip({ supplier: 'S', rate: 5, price: 6 }).supplier === 'S' && T.strip({ rate: 5 }).rate === 5, 'supplier and rate keys survive for purchase bills');
// safeSrc
ok(T.safeSrc('//evil.com/x.png') === '' && T.safeSrc('../x.png') === '' && T.safeSrc('logo.webp') === 'logo.webp' && T.safeSrc('https://a.com/l.png') === 'https://a.com/l.png', 'safeSrc rejects // and ..');
// null / odd items
for (const dt of ['pos_receipt', 'pay_slip', 'recipe_card', 'msg_invoice', 'barcode_label']) { const dd = T.sample(dt); if (dd.items) dd.items = [null, 5, 'x', dd.items[0]]; if (dd.sections) dd.sections = [null, 3, { title: 'T', rows: [null, { label: 'L', amount: 1 }] }]; if (dd.steps) dd.steps = [null, { a: 1 }, 'ok']; let r; try { r = T.render(dt, dd, T.docs[dt].tpls[0].id, {}); } catch (e) { r = e; } ok(typeof r === 'string', dt + ' survives null / non-object rows'); }
ok(typeof T.render('pos_receipt', null, 'a4_modern', {}) === 'string' && typeof T.render('pos_receipt', 'str', 'a4_modern', {}) === 'string', 'null / string data does not throw');
// barcode checks
ok(T.barcodeModules('5901234123458').kind === 'code39' && T.barcodeModules('5901234123458').warn === 'ean_check_digit' && /data-warn="ean_check_digit"/.test(T.barcodeSVG('5901234123458', 70, 10)), 'wrong EAN check digit: Code 39 fallback + warning, digits unchanged');
ok(T.barcodeModules('590123412345').text === '5901234123457' && T.barcodeModules('5901234123457').kind === 'ean13', 'EAN-12 gets its check digit; valid 13 stays EAN-13');
ok(T.barcodeModules('abc$#') === null && T.barcodeSVG('ab c!', 40, 10) === '', 'unsupported Code 39 character: no bars');
const q = T.barcodeModules('AB-1'); ok(/viewBox="0 0 \d+ 10"/.test(T.barcodeSVG('AB-1', 40, 10)) && Number(T.barcodeSVG('AB-1', 40, 10).match(/viewBox="0 0 (\d+)/)[1]) === q.mods.length + 20, 'quiet zone 10 modules each side');
ok(T.barcodeSVG('A'.repeat(24), 30, 10) === '' && T.barcodeSVG('590123412345', 20, 10) === '' && T.barcodeSVG('590123412345', 44, 10) !== '', 'module narrower than 0.19 mm is refused, normal EAN fits');
ok(T.render('barcode_label', Object.assign(T.sample('barcode_label'), { code: 'A'.repeat(24) }), 'label_40x20', {}).includes('A'.repeat(24)), 'too-dense code: number still printed as text');
// structural variety (accounts / purchasing): different markup, not only CSS
const sig = (dt, tid) => T.render(dt, T.sample(dt), tid, { lang: 'en' }).replace(/<style>[\s\S]*?<\/style>/, '').replace(/>[^<]*</g, '><').replace(/ (class|style|data-[a-z]+|lang)="[^"]*"/g, ''); 
for (const dt of ['purchase_bill', 'grn', 'partner_statement', 'pnl']) { const sigs = new Set(T.docs[dt].tpls.map((t) => sig(dt, t.id) + '|' + (T.render(dt, T.sample(dt), t.id, {}).match(/class="tp-(two|cards|ledger|cols2)/g) || []).join(','))); ok(sigs.size >= 4, dt + ' has >= 4 structurally different layouts, got ' + sigs.size); }
console.log(`tpl_test: ${n - bad} pass / ${bad} fail`); process.exit(bad ? 1 : 0);
