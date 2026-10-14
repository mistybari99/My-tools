// Step Land (bos97): the real app + web/landed.js in a phone-size browser (360 px) with a mocked rpc.
// Screens: list + mode banner, pick bills, editor (charges, method chips, live side-by-side preview, recommendation, basis inputs, late chips), save / approve / post / void,
// reminder list, the guarded link on the purchase bill page, owner settings, three languages, English without Bangla letters, no horizontal overflow.
// Run on its own: node tests/web/landed_pw_test.js <abs tests/web dir> [shots dir]      (serves ../../web of THIS checkout)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname;
const C = require(SP + '/s10_common.js');
const WEB = _P.WEB_DIR; const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = _P.freePort();
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from(b.toString('utf8').includes('src="landed.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="landed.js"></script></body>'));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const RET1 = '55555555-5555-4555-8555-555555555555', BILL1 = '11111111-1111-4111-8111-111111111111', BILL2 = '22222222-2222-4222-8222-222222222222', COST1 = '33333333-3333-4333-8333-333333333333', COSTP = '44444444-4444-4444-8444-444444444444';
function mk(o = {}) { const data = C.mkData(base, o); data.tables.suppliers = [{ id: 'sp1', name: 'Importer Ltd', active: true }, { id: 'sp2', name: 'Transporter', active: true }]; return data; }
// the in-page server stand-in: the same hand numbers as the SQL test (LA 20 kg @ 10 weight 20 kg, LB 30 pc @ 20 weight 12 kg)
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const L = window.__LC = Object.assign({ calls: [], err: {}, info: { mode: 'manual', alloc_default: 'value', late_mode: 'split_remaining_and_cogs', requires_approval: 'warn', reminder_on: true, base_currency: 'BDT', can_entry: true, can_approve: true, journal_ready: true,
   charge_types: [ ['freight','পরিবহন ভাড়া','Freight / transport in','capitalise','weight'], ['duty','আমদানি শুল্ক','Customs duty','capitalise','value'], ['loading','মাল তোলা','Loading','capitalise','qty'], ['vat_recov','ফেরতযোগ্য কর','Recoverable tax (input)','recoverable_tax',null], ['bank_exp','ব্যাংক চার্জ','Bank charge — expense only','expense_only',null] ].map((t) => ({ code: t[0], name_bn: t[1], name_en: t[2], name_mix: t[2], treatment: t[3], default_alloc: t[4], hint_bn: null, hint_mix: null, hint_en: t[3] === 'capitalise' ? 'Added to the item cost' : null, active: true, is_system: true })) },
  weightKnown: true, late: false }, window.__LC0 || {});
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const LA = { bill_line_id: 101, bill_id: '${BILL1}', bill_no: 'B-1', line_no: 1, item_id: 'ia', code: 'L97-A', name_bn: 'ময়দা', name_en: 'Flour', unit: 'kg', base_qty: 20, ucb_net: 10, value: 200, weight: 20, weight_src: 'unit', volume: null, volume_src: null, pct: null, in_scope: true };
 const LB = { bill_line_id: 102, bill_id: '${BILL1}', bill_no: 'B-1', line_no: 2, item_id: 'ib', code: 'L97-B', name_bn: 'বক্স', name_en: 'Box', unit: 'pc', base_qty: 30, ucb_net: 20, value: 600, weight: 12, weight_src: 'item', volume: null, volume_src: null, pct: null, in_scope: true };
 const msg = (bn, mix, en, code) => ({ bn, mix, en, code });
 function preview(args) {
   const ch = (args.p_charges || []); let cap = 0, exp = 0, tax = 0; ch.forEach((x) => { const am = Math.round(x.amount_ccy * (x.rate || 1) * 100) / 100; const t = (L.info.charge_types.find((y) => y.code === x.charge_type) || {}).treatment; if (t === 'capitalise') cap += am; else if (t === 'expense_only') exp += am; else tax += am; });
   const w = L.weightKnown ? [20, 12] : [20, null]; const lines = [clone(LA), clone(LB)]; if (!L.weightKnown) { lines[1].weight = null; lines[1].weight_src = null; }
   const pctOk = (args.p_basis || []).filter((b) => b.manual_pct != null).length === 2; const pcts = pctOk ? args.p_basis.map((b) => b.manual_pct) : null;
   const split = (ws) => { const t = ws.reduce((s, z) => s + z, 0); const r = ws.map((z) => Math.round(cap * z / t * 100) / 100); r[0] = Math.round((r[0] + cap - r.reduce((s, z) => s + z, 0)) * 100) / 100; return r; };
   const M = { qty: split([20, 30]), value: split([200, 600]), equal: split([1, 1]) }; if (L.weightKnown) M.weight = split(w); if (pctOk && Math.abs(pcts[0] + pcts[1] - 100) < 0.01) M.manual = split(pcts);
   const meth = args.p_method || L.info.alloc_default; const avail = { lines: 2, qty: { ok: true, mixed_units: true }, value: { ok: true }, weight: L.weightKnown ? { ok: true } : { ok: false, why: 'weight_unknown', missing: ['L97-B'] }, volume: { ok: false, why: 'volume_unknown', missing: ['L97-A', 'L97-B'] }, manual: M.manual ? { ok: true } : { ok: false, why: 'manual_missing', missing: ['L97-A', 'L97-B'], sum: 0 }, equal: { ok: true } };
   if (L.err.preview) return { error: { message: L.err.preview } };
   lines.forEach((l, i) => { l.methods = {}; Object.keys(M).forEach((m) => { const al = M[m][i]; l.methods[m] = { alloc: al, unit_add: al / l.base_qty, new_unit_cost: Math.round((l.ucb_net + al / l.base_qty) * 1e6) / 1e6, pct_up: Math.round(al / l.base_qty / l.ucb_net * 1e4) / 100 }; });
     const sel = M[meth] ? M[meth][i] : M.value[i]; l.chosen = { alloc: sel, unit_add: sel / l.base_qty, new_unit_cost: l.ucb_net + sel / l.base_qty, stock: sel, cogs: 0 }; });
   const reco = { method: L.weightKnown ? 'weight' : 'value', per_charge: [], late_mode: L.info.late_mode, reasons: [L.weightKnown ? msg('Freight ওজন ধরে ভাগ করাই ভালো: সব line-এর ওজন জানা আছে।', 'Freight weight ধরে ভাগ করাই ভালো: সব line-এর weight জানা আছে।', 'Freight is best spread by weight: every line has a known weight.', 'm_weight') : msg('ওজন ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর ওজন জানা নেই (অনুমান করা হয়নি), তাই দাম ধরা হলো।', 'Weight ধরে ভাগ করা ভালো হতো, কিন্তু কিছু line-এর weight জানা নেই (অনুমান করা হয়নি), তাই value ধরা হলো।', 'Weight would be best, but the weight of some lines is unknown (it is never guessed), so value is used.', 'm_weight_fallback')],
     warnings: L.weightKnown ? [] : [msg('ওজন জানা নেই: L97-B। অনুমান করা হয় না — line-এর ওজন বা item-এর ওজন লিখুন।', 'Weight জানা নেই: L97-B। অনুমান করা হয় না — line-এর weight বা item-এর weight লিখুন।', 'Weight is unknown for: L97-B. It is not guessed: enter the line weight or the item weight.', 'w_weight_unknown')] };
   if (L.late) reco.warnings.push(msg('এই lot-এর 4 একক আগেই বিক্রি বা ব্যবহার হয়ে গেছে।', 'এই lot-এর 4 unit আগেই sold বা used হয়ে গেছে।', '4 units of this lot are already sold or used.', 'late_goods_sold'));
   const items = [{ item_id: 'ia', loc: 1, lot_qty: 20, on_hand: L.late ? 16 : 20, avg: 10, late_qty: L.late ? 4 : 0, amount: M[meth] ? M[meth][0] : 0, stock: M[meth] ? M[meth][0] : 0, cogs: 0, avg_after: 13.625, flags: null }];
   return { data: { ok: true, error: null, method: meth, late_mode: args.p_late || L.info.late_mode, avail, lines, items, charges: ch, totals: { capitalised: cap, expense_only: exp, recoverable_tax: tax, all: cap + exp + tax }, recommendation: reco, mode: L.info.mode, location_id: 1 } };
 }
 c.rpc = async (fn, args) => {
  if (!/^(landed_|purchase_list|purchase_get|set_rule$|has_grant$)/.test(fn)) return rpc(fn, args);
  L.calls.push([fn, clone(args || {})]);
  if (L.err[fn]) return { data: null, error: { message: L.err[fn] } };
  if (fn === 'has_grant') return { data: !!(L.grants || []).includes(args.p_code), error: null };
  if (fn === 'landed_info') return { data: clone(L.info), error: null };
  if (fn === 'landed_list') return { data: clone(L.list || []), error: null };
  if (fn === 'landed_preview') { const r = preview(args); return r.error ? { data: null, error: r.error } : { data: r.data, error: null }; }
  if (fn === 'landed_save') { L.saved = clone(args); return { data: { id: '${COSTP}', status: 'draft', total: 100, dup: false }, error: null }; }
  if (fn === 'landed_approve') { L.status = 'approved'; return { data: { id: args.p_id, status: 'approved' }, error: null }; }
  if (fn === 'landed_post') { L.status = 'posted'; return { data: { id: args.p_id, status: 'posted', posted: 4, dup: false }, error: null }; }
  if (fn === 'landed_void') { L.status = 'void'; return { data: { id: args.p_id, status: 'void' }, error: null }; }
  if (fn === 'landed_get') { const st = L.status || (L.getStatus || 'draft'); return { data: { header: { id: args.p_id, status: st, location_id: 1, shipment_ref: 'SHIP-9', title: 'Main lot', note: null, cost_date: '2026-10-14', alloc_method: 'value', late_mode: null, total: 140, void_reason: st === 'void' ? 'wrong' : null },
     docs: [{ bill_id: '${BILL1}', doc_type: 'bill', doc_id: '${BILL1}', bill_no: 'B-1', bill_date: '2026-10-12', supplier: 'Importer Ltd', total: 800 }],
     lines: [{ id: 1, line_no: 1, charge_type: 'freight', amount_ccy: 100, ccy: 'BDT', rate: 1, amount: 100, alloc_method: 'weight', pay_mode: 'payable', supplier_id: 'sp2' }, { id: 2, line_no: 2, charge_type: 'duty', amount_ccy: 40, ccy: 'BDT', rate: 1, amount: 40, alloc_method: null, pay_mode: 'bank', supplier_id: null }],
     basis: [], alloc: [{ kind: 'post', charge_line_id: 1, bill_line_id: 101, item_id: 'ia', part: 'stock', amount: 72.5, dr_key: 'inv_raw' }], stock: [{ kind: 'post', item_id: 'ia', avg_before: 10, avg_after: 13.625, stock_value: 72.5, cogs_value: 0 }], preview: null, can: { approve: true, entry: true }, rules: { mode: L.info.mode } }, error: null }; }
  if (fn === 'landed_reminders') return { data: { on: !!L.info.reminder_on, mode: L.info.mode, days: 30, count: 2, rows: [{ bill_id: '${BILL1}', bill_no: 'B-1', bill_date: '2026-10-12', total: 800, supplier: 'Importer Ltd', why: 'supplier_imported', in_progress: false }, { bill_id: '${BILL2}', bill_no: 'B-2', bill_date: '2026-10-13', total: 300, supplier: 'Local Co', why: 'every_bill', in_progress: true }] }, error: null };
  if (fn === 'landed_skip' || fn === 'landed_supplier_flag_set' || fn === 'landed_charge_type_save') return { data: { ok: true }, error: null };
  if (fn === 'landed_return_info') return { data: { original: '${BILL1}', has_landed: true, items: [{ item_id: 'ia', code: 'L97-A', returned_qty: 4, lot_qty: 20, landed_per_unit: 3.625, landed_on_returned: 14.5 }], total: 14.5, note: { bn: 'ফেরতের মালের landed cost সরবরাহকারী ফেরত দেয় না।', mix: 'Return-এর মালের landed cost supplier ফেরত দেয় না।', en: 'The landed cost carried by the returned goods is not refunded by the supplier.' } }, error: null };
  if (fn === 'purchase_list') return { data: [{ id: '${BILL1}', kind: 'bill', supplier_id: 'sp1', supplier_name: 'Importer Ltd', bill_no: 'B-1', bill_date: '2026-10-12', location_id: 1, status: 'posted', total: 800 }, { id: '${BILL2}', kind: 'bill', supplier_id: 'sp2', supplier_name: 'Local Co', bill_no: 'B-2', bill_date: '2026-10-13', location_id: 1, status: 'posted', total: 300 }, { id: '${RET1}', kind: 'return', supplier_id: 'sp1', supplier_name: 'Importer Ltd', bill_no: 'R-1', bill_date: '2026-10-13', location_id: 1, status: 'posted', total: 50 }], error: null };
  if (fn === 'purchase_get') { const ret = args.p_id === '${RET1}'; return { data: { id: args.p_id, kind: ret ? 'return' : 'bill', status: 'posted', supplier_id: args.p_id === '${BILL2}' ? 'sp2' : 'sp1', supplier_name: args.p_id === '${BILL2}' ? 'Local Co' : 'Importer Ltd', bill_no: 'B-1', bill_date: '2026-10-12', location_id: 1, subtotal: 800, discount: 0, total: 800, paid: 0, due: 800, lines: [], payments: [] }, error: null }; }
  if (fn === 'set_rule') { if (args.p_key === 'landed_cost_mode') L.info.mode = args.p_value; if (args.p_key === 'landed_reminder_on') L.info.reminder_on = args.p_value; return { data: null, error: null }; }
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  const BN = /[ঀ-৲৴-৿]/;      // Bangla letters; the taka sign (U+09F3) is the currency mark the whole English UI already uses
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage(); p.setDefaultTimeout(6000);
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|favicon/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__LC0=${JSON.stringify(o.lc || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__LC.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => { const w = window.innerWidth; const out = []; document.querySelectorAll('body *').forEach((e) => { const b = e.getBoundingClientRect(); if (b.width && b.right > w + 1 && !e.closest('.sheet')) out.push(e.tagName + '.' + e.className); }); return { sw: document.documentElement.scrollWidth, w, out: out.slice(0, 3) }; }); ok(r.sw <= r.w + 1, 'no horizontal overflow: ' + m + ' ' + JSON.stringify(r)); };
  const txt = (p, sel) => p.textContent(sel).then((s) => (s || '').replace(/\s+/g, ' '));

  log('-- 1. list, mode banner, English has no Bangla letters');
  // ---- 1. list, mode banner, English has no Bangla letters
  let p = await open({}, '#/landed');
  ok(/Landed cost/.test(await txt(p, 'header.top h1')), 'title');
  ok(/Manual/.test(await txt(p, '#lc_modechip')), 'mode chip says manual');
  ok(await p.locator('[data-act=lc_new]:not([disabled])').count() === 1, 'new button enabled in manual mode');
  ok(await p.locator('[data-act=lc_settings]').count() === 1, 'owner sees settings');
  ok(!BN.test(await p.evaluate(() => document.getElementById('app').innerText.replace(/৳/g, ''))), 'English mode: no Bangla letters on the list screen');
  await noOverflow(p, 'list'); await p.screenshot({ path: OUT + '/lc_list.png' }); await p.close();

  log('-- 2. mode OFF = today: banner, new button disabled, bil');
  // ---- 2. mode OFF = today: banner, new button disabled, bill page link opens the same message
  p = await open({ lc: { info: { mode: 'off', alloc_default: 'value', late_mode: 'split_remaining_and_cogs', requires_approval: 'warn', reminder_on: false, base_currency: 'BDT', can_entry: true, can_approve: true, charge_types: [] } } }, '#/landed');
  ok(/Off/.test(await txt(p, '#lc_modechip')) && /Nothing is added to any bill price/.test(await txt(p, '#app')) && await p.locator('[data-act=lc_new][disabled]').count() === 1, 'off: banner + disabled new button');
  await p.goto(`http://localhost:${PORT}/#/landed/new/${BILL1}`); await wait(p, 700);
  ok(/Landed cost is off/.test(await txt(p, '#app')) && (await calls(p, 'landed_preview')).length === 0, 'off: the editor refuses and nothing is previewed');
  await p.close();

  log('-- 3. pick bills -> editor -> live preview');
  // ---- 3. pick bills -> editor -> live preview
  p = await open({}, '#/landed'); await p.click('[data-act=lc_new]'); await wait(p, 500);
  ok(await p.locator('[data-lcpk]').count() === 2, 'pick sheet lists the posted purchase bills only (the return is not offered)');
  await p.check(`[data-lcpk="${BILL1}"]`); await p.click('[data-act=lc_pickgo]'); await wait(p, 900);
  ok(/#\/landed\/new\//.test(await p.evaluate(() => location.hash)), 'continue opens the editor route');
  ok(await p.locator('[data-lc=type]').count() === 1 && /Importer Ltd/.test(await txt(p, '#lc_bills')), 'editor: one empty charge row, the bill chip');
  ok(/Enter at least one charge/.test(await txt(p, '#lc_pv')) && (await calls(p, 'landed_preview')).length === 0, 'no charge typed: no preview call');
  await p.fill('[data-lc=amount][data-i="0"]', '100'); await wait(p, 900);
  let c = await calls(p, 'landed_preview'); ok(c.length === 1 && c[0].p_bills[0] === BILL1 && c[0].p_charges.length === 1 && c[0].p_charges[0].charge_type === 'freight' && c[0].p_charges[0].amount_ccy === 100 && c[0].p_charges[0].ccy === 'BDT' && c[0].p_method === 'value', 'preview called with the bill, the charge and the default method: ' + JSON.stringify(c[0]));
  ok(await p.locator('.lc-line').count() === 2, 'one card per stocked line');
  const l1 = await txt(p, '.lc-line >> nth=0');
  ok(/Quantity/.test(l1) && /Value/.test(l1) && /Weight/.test(l1) && /Equal/.test(l1) && !/Volume/.test(l1) && !/Manual/.test(l1), 'side by side: qty, value, weight, equal (volume and manual are not available)');
  ok(/৳ 12\b/.test(l1) && /৳ 11\.25/.test(l1) && /৳ 13\.125/.test(l1) && /৳ 12\.5/.test(l1), 'LA new unit costs 12 / 11.25 / 13.125 / 12.5 (hand numbers)');
  const l2 = await txt(p, '.lc-line >> nth=1'); ok(/৳ 22\b/.test(l2) && /৳ 22\.5/.test(l2) && /৳ 21\.25/.test(l2), 'LB new unit costs 22 / 22.5 / 21.25');
  ok(await p.locator('.lc-m.on').count() === 2, 'the chosen method row is highlighted on each line');
  ok(/Recommended: Weight/.test(await txt(p, '.lc-reco')) && /every line has a known weight/.test(await txt(p, '.lc-reco')), 'recommendation: weight, with the reason');
  ok(await p.locator('[data-act=lc_method][data-v=weight]').innerText().then((t) => /★/.test(t)), 'the recommended chip has a star');
  ok(await p.locator('[data-act=lc_method][data-v=volume]').innerText().then((t) => /\?/.test(t)) && await p.locator('[data-act=lc_method][data-v=manual]').innerText().then((t) => /\?/.test(t)), 'unavailable methods are marked ?');
  ok(/units differ/.test(await txt(p, '#lc_pv')), 'mixed units hint');
  ok(!BN.test(await p.evaluate(() => document.getElementById('app').innerText.replace(/৳/g, ''))), 'English mode: no Bangla letters in the editor + preview');
  await noOverflow(p, 'editor'); await p.screenshot({ path: OUT + '/lc_editor.png', fullPage: true });
  // chip -> another method, preview asked again with it
  await p.click('[data-act=lc_method][data-v=weight]'); await wait(p, 900);
  c = await calls(p, 'landed_preview'); ok(c.length >= 2 && c[c.length - 1].p_method === 'weight', 'tapping Weight asks for the preview with weight');
  ok(/62\.5/.test(await txt(p, '.lc-line >> nth=0')), 'weight share 62.5 shown');
  await p.click('[data-act=lc_usereco]').catch(() => {});
  // foreign currency needs a rate (never guessed)
  await p.fill('[data-lc=ccy][data-i="0"]', 'USD'); await wait(p, 600);
  ok(await p.locator('[data-lc=rate]').count() === 1, 'a rate box appears for a foreign currency');
  const before = (await calls(p, 'landed_preview')).length;
  await p.fill('[data-lc=amount][data-i="0"]', '2'); await wait(p, 900);
  ok(/exchange rate/i.test(await txt(p, '#lc_pv')) && (await calls(p, 'landed_preview')).length === before, 'USD without a rate: warning, no call');
  await p.fill('[data-lc=rate][data-i="0"]', '110'); await wait(p, 900);
  c = await calls(p, 'landed_preview'); const last = c[c.length - 1]; ok(last.p_charges[0].ccy === 'USD' && last.p_charges[0].rate === 110 && last.p_charges[0].amount_ccy === 2, 'USD 2 x 110 sent with currency and rate');
  await p.fill('[data-lc=amount][data-i="0"]', 'abc'); await wait(p, 700);
  ok(/Number is not valid/.test(await txt(p, '#lc_pv')), 'a bad number is flagged, not sent');
  await p.fill('[data-lc=amount][data-i="0"]', '100'); await p.fill('[data-lc=ccy][data-i="0"]', 'BDT'); await wait(p, 700);
  // add a second charge, a different type, expense-only treatment text
  await p.click('[data-act=lc_chadd]'); await p.selectOption('[data-lc=type][data-i="1"]', 'bank_exp'); await wait(p, 200);
  ok(/Expense only/.test(await txt(p, '#lc_th1')), 'treatment text of an expense-only type');
  await p.fill('[data-lc=amount][data-i="1"]', '20'); await wait(p, 900);
  c = await calls(p, 'landed_preview'); ok(c[c.length - 1].p_charges.length === 2 && c[c.length - 1].p_charges[1].charge_type === 'bank_exp', 'two charges sent');
  ok(/Expense only/.test(await txt(p, '#lc_pv')), 'totals show the expense-only part');
  // basis: weight typed per line is sent
  ok(await p.locator('[data-lcb]').count() === 6, 'weight / volume / % boxes for each of the two lines');
  await p.fill('[data-lcb="102"][data-k="weight"]', '15'); await wait(p, 900);
  c = await calls(p, 'landed_preview'); ok(c[c.length - 1].p_basis.some((b) => b.bill_line_id === 102 && b.weight_kg === 15), 'typed weight sent');
  ok(/unknown|from the unit|from the item/.test(await txt(p, '[data-src="101"]')), 'weight source line shown');
  // save
  await p.fill('#lc_ref', 'SHIP-9'); await p.fill('#lc_ttl', 'Main lot');
  await p.click('[data-act=lc_save]'); await wait(p, 700);
  const sv = (await calls(p, 'landed_save'))[0]; ok(sv && typeof sv.p_client === 'string' && sv.p_id === null && sv.p_header.shipment_ref === 'SHIP-9' && sv.p_header.alloc_method === 'weight' && sv.p_docs[0].id === BILL1 && sv.p_lines.length === 2 && sv.p_basis.length === 1, 'save: client id, header, docs, lines, basis');
  await p.close();

  log('-- 4. unknown weight: method unavailable, warning lists ');
  // ---- 4. unknown weight: method unavailable, warning lists the item, nothing invented
  p = await open({ lc: { weightKnown: false } }, `#/landed/new/${BILL1}`); await p.fill('[data-lc=amount][data-i="0"]', '100'); await wait(p, 900);
  ok(await p.locator('[data-act=lc_method][data-v=weight]').innerText().then((t) => /\?/.test(t) && !/★/.test(t)), 'weight chip is marked ? and not recommended');
  ok(/never guessed/.test(await txt(p, '.lc-reco')) && /L97-B/.test(await txt(p, '.lc-warn')), 'fallback reason + the item with no weight is listed');
  ok(/Weight: unknown/.test(await txt(p, '[data-src="102"]')) && /Weight: 20 kg/.test(await txt(p, '[data-src="101"]')), 'the line with no weight says unknown, the other shows 20 kg');
  await p.close();

  log('-- 5. late goods: split chips and the warning');
  // ---- 5. late goods: split chips and the warning
  p = await open({ lc: { late: true } }, `#/landed/new/${BILL1}`); await p.fill('[data-lc=amount][data-i="0"]', '100'); await wait(p, 900);
  ok(/already sold or used/.test(await txt(p, '#lc_pv')) && await p.locator('[data-act=lc_late]').count() === 3, 'late warning + three late-mode chips');
  await p.click('[data-act=lc_late][data-v=variance_account]'); await wait(p, 900);
  c = await calls(p, 'landed_preview'); ok(c[c.length - 1].p_late === 'variance_account', 'late mode sent to the preview');
  await p.close();

  log('-- 6. open a draft: approve -> post -> void flow (warn m');
  // ---- 6. open a draft: approve -> post -> void flow (warn mode)
  p = await open({}, `#/landed/${COST1}`); await wait(p, 500);
  ok(await p.locator('[data-lc=type]').count() === 2 && (await p.locator('[data-lc=amount][data-i="0"]').inputValue()) === '100', 'a saved draft loads its charges');
  ok(await p.locator('[data-act=lc_approve]').count() === 1 && await p.locator('[data-act=lc_post]').count() === 1 && await p.locator('[data-act=lc_void]').count() === 1, 'draft + warn mode: approve, post, void');
  await p.click('[data-act=lc_approve]'); await wait(p, 900);
  ok((await calls(p, 'landed_approve')).length === 1 && (await calls(p, 'landed_save')).length === 1, 'approve saves first, then approves');
  await p.click('[data-act=lc_post]'); await wait(p, 900);
  const po = await calls(p, 'landed_post'); ok(po.length === 1 && typeof po[0].p_client === 'string', 'post sent with a client id');
  await p.close(); p = await open({ lc: { getStatus: 'posted' } }, `#/landed/${COST1}`); await wait(p, 500);
  ok(await p.locator('[data-lc=amount]:not([disabled])').count() === 0 && /Result of the posting/.test(await txt(p, '#lc_pv')) && /13\.625/.test(await txt(p, '#lc_pv')), 'a posted cost is read-only and shows the average before and after');
  await p.click('[data-act=lc_void]'); await wait(p, 300); await p.fill('#lc_vwhy', 'x'); await p.click('[data-act=lc_voidgo]'); await wait(p, 300);
  ok((await calls(p, 'landed_void')).length === 0, 'void needs a reason of 3+ letters');
  await p.fill('#lc_vwhy', 'freight was wrong'); await p.click('[data-act=lc_voidgo]'); await wait(p, 700);
  c = await calls(p, 'landed_void'); ok(c.length === 1 && c[0].p_reason === 'freight was wrong', 'void sent with the reason');
  await p.close();
  // required approval: no Post on a draft
  p = await open({ lc: { info: { mode: 'per_shipment', alloc_default: 'value', late_mode: 'split_remaining_and_cogs', requires_approval: 'required', reminder_on: true, base_currency: 'BDT', can_entry: true, can_approve: false, charge_types: [{ code: 'freight', name_bn: 'ভাড়া', name_en: 'Freight', name_mix: 'Freight', treatment: 'capitalise', default_alloc: 'weight', active: true }] } } }, `#/landed/${COST1}`); await wait(p, 500);
  ok(await p.locator('[data-act=lc_post]').count() === 0 && await p.locator('[data-act=lc_approve]').count() === 0, 'required approval and no approve right: neither Post nor Approve is offered on a draft');
  await p.close();

  log('-- 7. reminders');
  // ---- 7. reminders
  p = await open({}, '#/landed/rem'); await wait(p, 400);
  ok(await p.locator('[data-act=lc_remopen]').count() === 2 && /supplier|imported/i.test(await txt(p, '#app')) && /draft in progress/.test(await txt(p, '#app')), 'reminder rows, why, in-progress mark');
  await p.click('[data-act=lc_skip] >> nth=0'); await wait(p, 200); await p.fill('#lc_swhy', 'no extra'); await p.click('[data-act=lc_skipgo]'); await wait(p, 600);
  c = await calls(p, 'landed_skip'); ok(c.length === 1 && c[0].p_bill === BILL1 && c[0].p_reason === 'no extra', 'skip sends the bill and the reason');
  await noOverflow(p, 'reminders'); await p.screenshot({ path: OUT + '/lc_rem.png' }); await p.close();
  p = await open({ lc: { info: { mode: 'manual', alloc_default: 'value', late_mode: 'split_remaining_and_cogs', requires_approval: 'warn', reminder_on: false, base_currency: 'BDT', can_entry: true, can_approve: true, charge_types: [] } } }, '#/landed/rem'); await wait(p, 400);
  ok(/This list is off/.test(await txt(p, '#app')), 'reminder switch off: explained');
  await p.close();

  log('-- 8. owner settings sheet writes the rules');
  // ---- 8. owner settings sheet writes the rules
  p = await open({}, '#/landed'); await p.click('[data-act=lc_settings]'); await wait(p, 300);
  await p.selectOption('#lcs_mode', 'per_shipment'); await p.selectOption('#lcs_appr', 'required'); await p.selectOption('#lcs_rem', 'off'); await p.click('[data-act=lc_settings_go]'); await wait(p, 900);
  c = await calls(p, 'set_rule'); ok(c.some((x) => x.p_key === 'landed_cost_mode' && x.p_value === 'per_shipment') && c.some((x) => x.p_key === 'landed_cost_requires_approval' && x.p_value === 'required') && c.some((x) => x.p_key === 'landed_reminder_on' && x.p_value === false), 'settings call set_rule for each switch');
  await p.close();

  log('-- 9. the guarded link on the purchase bill page (purcha');
  // ---- 9. the guarded link on the purchase bill page (purchase.js untouched)
  p = await open({ m: { list: [{ id: BILL1, kind: 'bill', supplier_id: 'sp1', supplier_name: 'Importer Ltd', bill_no: 'B-1', bill_date: '2026-10-12', location_id: 1, status: 'posted', total: 800, discount: 0, paid: 0, due: 800 }] } }, `#/purchase/${BILL1}`); await wait(p, 1800);
  const hasLink = await p.locator('[data-act=lc_add]').count(); ok(hasLink === 1, 'a posted bill page gets the "Add landed costs" button');
  if (hasLink) { await p.click('[data-act=lc_add]'); await wait(p, 900); ok(new RegExp('#/landed/new/' + BILL1).test(await p.evaluate(() => location.hash)), 'the button opens the editor for this bill'); }
  await p.close();
  p = await open({ lc: { info: { mode: 'manual', alloc_default: 'value', late_mode: 'split_remaining_and_cogs', requires_approval: 'warn', reminder_on: false, base_currency: 'BDT', can_entry: false, can_approve: false, charge_types: [] } } }, `#/purchase/${BILL1}`); await wait(p, 1800);
  ok(await p.locator('[data-act=lc_add]').count() === 0, 'no landed right: no button on the bill page');
  await p.close();
  p = await open({ lc: { err: { landed_info: 'Could not find the function landed_info' } } }, `#/purchase/${BILL1}`); await wait(p, 1800);
  ok(await p.locator('[data-act=lc_add]').count() === 0 && await p.locator('[data-act=pu_void], [data-act=pu_retvs], .s2-bar').count() > 0, 'phase97 not installed: the bill page is untouched, no button, no error');
  await p.close();

  log('-- 10. return of such a purchase');
  // ---- 10. return of such a purchase
  p = await open({}, `#/landed/new/${RET1}`); await wait(p, 900);
  ok(/Landed cost of returned goods/.test(await txt(p, 'header.top h1')) && /14\.5/.test(await txt(p, '#app')) && /not refunded by the supplier/.test(await txt(p, '#app')), 'a return bill shows the landed cost carried by the returned goods');
  await p.close();

  log('-- 11. languages');
  // ---- 11. languages
  p = await open({ lang: 'bn' }, '#/landed'); await wait(p, 300);
  ok(BN.test(await txt(p, '#lc_modechip')) && /Landed cost/.test(await txt(p, 'header.top h1')), 'Bangla mode: Bangla words, common words stay English');
  await p.goto(`http://localhost:${PORT}/#/landed/new/${BILL1}`); await wait(p, 700); await p.fill('[data-lc=amount][data-i="0"]', '100'); await wait(p, 900);
  ok(/ওজন/.test(await txt(p, '#lc_pv')) && /Freight/.test(await txt(p, '.lc-reco')), 'Bangla preview + recommendation (Freight stays English)');
  await noOverflow(p, 'Bangla editor'); await p.screenshot({ path: OUT + '/lc_bn.png' }); await p.close();
  p = await open({ lang: 'mix' }, `#/landed/new/${BILL1}`); await wait(p, 600); await p.fill('[data-lc=amount][data-i="0"]', '100'); await wait(p, 900);
  ok(/weight/i.test(await txt(p, '#lc_pv')) && BN.test(await txt(p, '.lc-reco')), 'Bng/Eng mix preview');
  await noOverflow(p, 'mix editor'); await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
