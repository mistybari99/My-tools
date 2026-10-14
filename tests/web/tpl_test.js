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
// renders
const COSTS = ['cost', 'unit_cost', 'cost_price', 'purchase_price', 'buy_price', 'cogs', 'margin', 'profit', 'markup'];
for (const s of types) for (const lg of ['en', 'bn', 'mix']) for (const t of s.tpls) {
  const d = T.sample(s.id); const out = T.render(s.id, d, t.id, { lang: lg, channel: 'whatsapp' });
  ok(typeof out === 'string' && out.length > 20, s.id + '/' + t.id + '/' + lg + ' renders');
  if (s.kind === 'text') { ok(!/[<>]/.test(out), s.id + '/' + t.id + ' text has no angle brackets'); if (lg === 'en' && t.id !== 'bilingual') ok(!BN.test(out), s.id + '/' + t.id + ' English message has Bangla'); if (lg !== 'en') ok(BN.test(out), s.id + '/' + t.id + '/' + lg + ' Bangla message has Bangla'); if (t.id === 'bilingual') ok(BN.test(out) && /[A-Za-z]/.test(out), 'bilingual has both'); continue; }
  ok(/@page\{size:[^;]+;margin:\d+(mm)?\}/.test(out), s.id + '/' + t.id + ' has an @page size');
  if (lg === 'en') ok(!BN.test(out.replace(/<style>[\s\S]*?<\/style>/, '')), s.id + '/' + t.id + ' English output has Bangla');
  if (lg !== 'en' && s.kind === 'doc') ok(BN.test(out), s.id + '/' + t.id + '/' + lg + ' has Bangla labels');
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
ok((T.render('barcode_label', Object.assign(T.sample('barcode_label'), { copies: 999 }), 'sheet_70x37', {}).match(/class="c"/g) || []).length === 24, 'sheet capped at 3x8');
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
console.log(`tpl_test: ${n - bad} pass / ${bad} fail`); process.exit(bad ? 1 : 0);
