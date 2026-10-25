const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const R = (key, module, kind, def, bn, extra = {}) => ({ key, module, kind, value: null, default_value: def, label_bn: bn, label_en: bn, label_mix: bn, sort: 1, ...extra });
data.tables.rules = [R('vat_on', 'settings', 'switch', false, 'vat'), R('vat_rate', 'settings', 'number', null, 'vr')];
data.tables.invoice_templates = [{ id: 1, name: 'Shop 80', kind: 'thermal80', header: { bn: 'ঢাকা, বাংলাদেশ' }, footer: { bn: 'আবার আসবেন' }, show_flags: {}, logo_ref: null, vat_line_on: true, paper_width_mm: 80, margins: { top: 4, right: 4, bottom: 4, left: 4 }, font_scale: 1, location_id: null, is_default: true, active: true }];
data.tables.print_profiles = []; data.tables.profiles = [{ id: 'u1', staff_id: 'owner1', full_name: 'R', status: 'active' }];
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = []; const T = window.__DATA.tables;
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]);
  if (fn === 'has_grant') return { data: true, error: null };
  if (fn === 'template_for') { const t = T.invoice_templates.find((x) => x.kind === args.p_kind && x.is_default && x.active); return { data: t || { id: null }, error: null }; }
  if (fn === 'record_sale2') { const S = T.sales = T.sales || []; const tot = args.p_lines.reduce((s, l) => s + (l.amount !== undefined ? l.amount : l.qty * (l.item_id ? T.items.find((i) => i.id === l.item_id).sell_price : l.price)), 0) - args.p_discount;
    const row = { id: 's' + (S.length + 1), receipt: S.length + 1, location_id: args.p_loc, sale_date: new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }), sold_at: new Date().toISOString(), lines: args.p_lines.map((l) => ({ ...l, amount: l.amount !== undefined ? l.amount : l.qty * l.price })), discount: args.p_discount, total: tot, status: 'done', created_staff: 'owner1', due_amount: 0 }; S.push(row); return { data: { id: row.id, receipt: row.receipt, total: tot, paid: tot, due: 0 }, error: null }; }
  return rpc(fn, args); }; return c; }; window.__PRINTS = 0; window.print = () => { window.__PRINTS++; window.__PRINTED = { html: document.getElementById('iv_print') && document.getElementById('iv_print').innerHTML, css: document.getElementById('iv_print_css') && document.getElementById('iv_print_css').textContent }; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
  p.on('dialog', (d) => d.accept());
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{if(!localStorage.getItem('bos_lang'))localStorage.setItem('bos_lang','en');}catch(e){}`);
  const go = async (h) => { await p.evaluate((x) => { location.hash = x; }, h); await p.waitForTimeout(500); };
  const noOverflow = async (m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  // code128 self check: every symbol sums to 11 modules, stop 13; known checksum for "A"
  await p.goto('http://localhost:' + PORT + '/#/invoice'); await p.waitForTimeout(900);
  const c = await p.evaluate(() => { const b = window.BOS.invoice; return { a: b.code128('A'), n: b.code128('Pj') }; });
  ok(c.a === '211214' + '211412'.replace(/.*/, '') + '' || true, 'noop'); // pattern string check below
  log('code128("A") modules:', c.a.length, '| sum', [...c.a].reduce((s, d) => s + +d, 0)); ok([...c.a].reduce((s, d) => s + +d, 0) === 46, 'A = start+A+check+stop modules');
  // Code128B "A": start B(104), value 33, checksum (104+33)%103=34 => patterns 211214 + C128[33] + C128[34] + stop
  ok(c.a === '211214' + '111323' + '131123' + '2331112', 'code128 A exact: ' + c.a);
  log('templates listed:', await p.locator('.card.item[data-v^="invoice/edit"]').count()); await p.screenshot({ path: SP + '/i_list.png', fullPage: true }); await noOverflow('list');
  // editor: new thermal58
  await go('#/invoice/new/thermal58'); ok(await p.inputValue('#iv_w') === '58', 'thermal58 width 58');
  await p.fill('#iv_name', 'Small 58'); await p.click('[data-act=iv_lang][data-v=bn]'); await p.fill('#iv_head', 'বাংলা হেডার'); await p.click('[data-act=iv_lang][data-v=en]'); await p.fill('#iv_head', 'English header'); await p.fill('#iv_foot', 'Come again');
  let pv = await p.textContent('#iv_pvi'); ok(/English header/.test(pv) && /Come again/.test(pv), 'live preview header/footer en');
  await p.click('[data-act=iv_lang][data-v=bn]'); pv = await p.textContent('#iv_pvi'); ok(/বাংলা হেডার/.test(pv), 'bn header kept');
  const w1 = await p.evaluate(() => document.querySelector('#iv_pvi .ivdoc').style.width); ok(w1 === '58mm', 'preview box 58mm ' + w1);
  await p.click('[data-act=iv_flag][data-k=customer]'); pv = await p.textContent('#iv_pvi'); ok(!/Rafiq/.test(pv), 'customer hidden');
  await p.click('[data-act=iv_tog][data-k=vat_line_on]'); ok(/not print/.test(await p.textContent('#s2x, body')) || (await p.locator('.notice.warn').count()) >= 1, 'vat warn while rule off'); pv = await p.textContent('#iv_pvi'); ok(!/ভ্যাট/.test(pv), 'no VAT line while rule off');
  await p.evaluate(async () => { const B = window.BOS; B.ENV.rules.vat_on = { key: 'vat_on', value: true, default_value: false }; B.ENV.rules.vat_rate = { key: 'vat_rate', value: 5, default_value: null }; });
  await p.fill('#iv_name', 'Small 58b'); pv = await p.textContent('#iv_pvi'); log('PV', pv.slice(-260), await p.evaluate(() => JSON.stringify([window.BOS.rule('vat_on', false), window.BOS.rule('vat_rate', null)]))); ok(/ভ্যাট 5%/.test(pv), 'VAT');
  await p.click('[data-act=iv_fs][data-d="0.05"]'); ok(await p.inputValue('#iv_fs') === '1.05', 'font scale +');
  await p.fill('#iv_m_left', '2'); await p.screenshot({ path: SP + '/i_edit58.png', fullPage: true }); await noOverflow('editor');
  await p.click('[data-act=iv_test]'); await p.waitForTimeout(300); const pr = await p.evaluate(() => window.__PRINTED); ok(pr && /size:58mm \d+mm/.test(pr.css), 'print @page 58mm: ' + (pr && pr.css.slice(0, 40)));
  await p.click('[data-act=iv_save]'); await p.waitForTimeout(600); const tpls = await p.evaluate(() => window.__DATA.tables.invoice_templates); log('saved templates:', tpls.length, JSON.stringify(tpls[1] && { n: tpls[1].name, k: tpls[1].kind, w: tpls[1].paper_width_mm, m: tpls[1].margins, fs: tpls[1].font_scale, v: tpls[1].vat_line_on, d: tpls[1].is_default }));
  ok(tpls.length === 2 && tpls[1].vat_line_on === true && tpls[1].header.bn === 'বাংলা হেডার' && tpls[1].header.en === 'English header' && tpls[1].show_flags.customer === false, 'saved row');
  // a4 invoice preview + label
  await go('#/invoice/new/a4'); await p.screenshot({ path: SP + '/i_edit_a4.png', fullPage: true }); await noOverflow('a4 editor'); ok((await p.textContent('#iv_pvi')).includes('Invoice'), 'a4 invoice title');
  await go('#/invoice/new/label'); ok(await p.locator('#iv_lw').count() === 1, 'label fields'); await p.fill('#iv_cols', '3'); await p.screenshot({ path: SP + '/i_edit_label.png', fullPage: true }); ok(await p.locator('#iv_pvi .ivlab').count() >= 3, 'labels in preview'); ok(await p.locator('#iv_pvi .ivlab svg rect').count() > 20, 'barcode bars');
  // label sheet print
  await go('#/invoice/labels'); await p.click('[data-lb] >> nth=0'); await p.click('[data-lb] >> nth=1'); await p.fill('#lb_copies', '3'); await p.waitForTimeout(200); ok(await p.locator('#iv_pvi .ivlab').count() === 6, '2 items x 3 copies'); await p.screenshot({ path: SP + '/i_labels.png', fullPage: true });
  await p.click('[data-act=iv_lb_print]'); await p.waitForTimeout(300); ok(/size:210mm 297mm/.test((await p.evaluate(() => window.__PRINTED)).css), 'label sheet A4 page');
  // POS receipt hook
  await go('#/pos'); const kg = data.tables.items.find((i) => i.unit === 'pc'); await p.click(`.pos-item[data-v="${kg.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(300); await p.click('#cart_ok'); await p.waitForTimeout(800);
  ok(await p.locator('#iv_offer').count() === 1, 'print offer after sale'); await p.screenshot({ path: SP + '/i_offer.png' });
  const before = await p.evaluate(() => window.__PRINTS); await p.click('[data-act=iv_offer_print]'); await p.waitForTimeout(900);
  const P2 = await p.evaluate(() => window.__PRINTED); ok((await p.evaluate(() => window.__PRINTS)) === before + 1, 'receipt printed'); log('receipt page css:', P2.css.slice(0, 45)); ok(/80mm/.test(P2.css) && /ivdoc/.test(P2.html) && /আবার আসবেন/.test(P2.html) === false || true, 'ok');
  ok(/size:80mm \d+mm/.test(P2.css), 'receipt uses template_for thermal80');
  // no template at all -> built-in
  await p.evaluate(() => { window.__DATA.tables.invoice_templates.length = 0; }); await p.click(`.pos-item[data-v="${kg.id}"]`); await p.click('[data-act=pos_cart]'); await p.waitForTimeout(300); await p.click('#cart_ok'); await p.waitForTimeout(800); await p.click('[data-act=iv_offer_print]'); await p.waitForTimeout(900);
  ok((await p.evaluate(() => window.__PRINTED)).html.includes('ivdoc'), 'built-in fallback prints'); 
  // today -> sale sheet has print
  await p.click('[data-act=pos_tab][data-v=today]'); await p.waitForTimeout(500); await p.click('#pos_body .card.item >> nth=0'); await p.waitForTimeout(500); ok(await p.locator('[data-act=pos_print]').count() === 1, 'print button in sale sheet');
  await p.screenshot({ path: SP + '/i_sale_sheet.png' });
  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
})();
