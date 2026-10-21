// Step Q4 (bos107): the real app at 360 px with a mocked rpc - attention badges (Home), GRN picker in the landed bill picker, setup advisor Undo, languages, no overflow.
// Run on its own: node tests/web/q4_pw_test.js <abs tests/web dir> [shots dir]      (serves ../../web of THIS checkout)
// reminder list, the guarded link on the purchase bill page, owner settings, three languages, English without Bangla letters, no horizontal overflow.
// Run on its own: node tests/web/landed_pw_test.js <abs tests/web dir> [shots dir]      (serves ../../web of THIS checkout)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname;
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web'); const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = 8498;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from(b.toString('utf8').includes('src="landed.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="landed.js"></script></body>'));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const RET1 = '55555555-5555-4555-8555-555555555555', BILL1 = '11111111-1111-4111-8111-111111111111', BILL2 = '22222222-2222-4222-8222-222222222222', COST1 = '33333333-3333-4333-8333-333333333333', COSTP = '44444444-4444-4444-8444-444444444444';
function mk(o = {}) { const data = C.mkData(base, o); data.tables.entries = [{ id: 'g1', form_code: '13-1', serial: 7, entry_date: '2026-10-12', status: 'approved', location_id: 1 }, { id: 'g2', form_code: '13-1', serial: 8, entry_date: '2026-10-13', status: 'submitted', location_id: 1 }, { id: 'g3', form_code: '18-1', serial: 9, entry_date: '2026-10-13', status: 'approved', location_id: 1 }, { id: 'g4', form_code: '13-1', serial: 3, entry_date: '2026-10-01', status: 'draft', location_id: 1 }]; data.tables.suppliers = [{ id: 'sp1', name: 'Importer Ltd', active: true }, { id: 'sp2', name: 'Transporter', active: true }]; return data; }
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

const EXTRA2 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const Q = window.__Q4 = Object.assign({ calls: [], err: {}, slow: {}, hist: [{ client_id: 'c1', applied_at: '2026-10-13T10:00:00', applied_by: 'u', overwrite: false, ignore_ready: false, lines: [{ code: 'a', rule_key: 'k_one', old: null, new: true, overwrote: false }, { code: 'b', rule_key: 'k_two', old: false, new: true, overwrote: true }] }],
   data: { ledger_problem_count: 3, cost_wait_list96: { total: 2 }, acct_pending_alert85: { old_count: 4 }, unmatched_forms: { lines_unmatched: 5 }, bills_without_payment99: { rows: [{ ref: 'a' }, { ref: 'b' }] }, inbox_board: { on: true, new_count: 6 } }, unlinked: ['g2'] }, window.__Q40 || {});
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 c.rpc = async (fn, args) => {
  if (!/^(ledger_problem_count|cost_wait_list96|acct_pending_alert85|unmatched_forms|bills_without_payment99|inbox_board|items_with_cost|landed_resolve_docs|setup_apply_history)$/.test(fn)) return rpc(fn, args);
  Q.calls.push([fn, clone(args || {})]);
  if (Q.slow[fn]) await new Promise((r) => setTimeout(r, 6000));
  if (Q.err[fn]) return { data: null, error: { message: Q.err[fn] } };
  if (fn === 'items_with_cost') return { data: [{ item_id: window.__DATA.tables.items[0].id, cost_price: 5 }], error: null };
  if (fn === 'landed_resolve_docs') { const d = args.p_docs[0]; if (Q.unlinked.includes(d.id)) return { data: null, error: { message: 'grn_not_linked' } }; return { data: [{ type: 'grn', doc_id: d.id, bill_id: '${BILL2}' }], error: null }; }
  if (fn === 'setup_apply_history') return { data: clone(Q.hist), error: null };
  return { data: clone(Q.data[fn]), error: null }; };
 return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  const BN = /[ঀ-৲৴-৿]/;      // Bangla letters; the taka sign (U+09F3) is the currency mark the whole English UI already uses
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage(); p.setDefaultTimeout(6000);
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|favicon/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA + EXTRA2 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__LC0=${JSON.stringify(o.lc || {})};window.__Q40=${JSON.stringify(o.q || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__LC.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => { const w = window.innerWidth; const out = []; document.querySelectorAll('body *').forEach((e) => { const b = e.getBoundingClientRect(); if (b.width && b.right > w + 1 && !e.closest('.sheet')) out.push(e.tagName + '.' + e.className); }); return { sw: document.documentElement.scrollWidth, w, out: out.slice(0, 3) }; }); ok(r.sw <= r.w + 1, 'no horizontal overflow: ' + m + ' ' + JSON.stringify(r)); };
  const txt = (p, sel) => p.textContent(sel).then((s) => (s || '').replace(/\s+/g, ' '));


  const qc = (p, fn) => p.evaluate((f) => window.__Q4.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const chips = (p) => p.locator('#q4_badges [data-act=q4_badge]');
  const strip = (p) => p.evaluate(() => { const b = document.getElementById('q4_badges'); return b ? { hidden: b.hidden, text: b.innerText.replace(/\s+/g, ' ').trim() } : null; });

  log('-- 1. badges on Home (owner, all seven)');
  let p = await open({}, '#/home'); await wait(p, 1500);
  let s = await strip(p);
  ok(s && !s.hidden, 'strip is shown');
  ok(await chips(p).count() === 7, 'seven chips for the owner (got ' + (await chips(p).count()) + ')');
  ok(/Ledger problems\s*3/.test(s.text) && /Waiting for cost\s*2/.test(s.text) && /Pending auto-posts\s*4/.test(s.text) && /Forms with no screen record\s*5/.test(s.text) && /Bills without payment\s*2/.test(s.text) && /New messages\s*6/.test(s.text), 'counts and English labels: ' + (s && s.text));
  ok(/Items with unknown cost\s*\d+/.test(s.text), 'unknown-cost chip has a count');
  ok(!BN.test(s.text), 'English mode: no Bangla letters in the strip');
  await noOverflow(p, 'home badges'); await p.screenshot({ path: OUT + '/q4_badges.png' });
  await p.click('#q4_badges [data-b=billpay]'); await wait(p, 300);
  ok(/#\/billpay/.test(await p.evaluate(() => location.hash)), 'tap opens the screen (billpay)');
  await p.goto(`http://localhost:${PORT}/#/home`); await wait(p, 900);
  const nLed = (await qc(p, 'ledger_problem_count')).length;
  ok(nLed >= 1, 'ledger rpc called');
  await p.close();

  log('-- 2. zero hidden, missing rpc hidden, slow rpc capped');
  p = await open({ q: { data: { ledger_problem_count: 0, cost_wait_list96: { total: 0 }, acct_pending_alert85: { old_count: 0 }, unmatched_forms: { lines_unmatched: 0 }, bills_without_payment99: { rows: [] }, inbox_board: { on: false } } } }, '#/home'); await wait(p, 1500);
  s = await strip(p); ok(s && s.hidden && (await chips(p).count()) === 0 || (s && !s.text.match(/Ledger|Waiting|Pending|Forms|Bills|messages/)), 'all zero: no chip about those (unknown-cost may remain)');
  await p.close();
  p = await open({ q: { err: { ledger_problem_count: 'Could not find the function public.ledger_problem_count in the schema cache', cost_wait_list96: 'not allowed' } } }, '#/home'); await wait(p, 1500);
  s = await strip(p); ok(s && !/Ledger/.test(s.text) && !/Waiting for cost/.test(s.text) && /Pending auto-posts\s*4/.test(s.text), 'missing / refused rpc: only that chip is gone, no error shown');
  await p.close();
  const t0 = Date.now();
  p = await open({ q: { slow: { bills_without_payment99: true } } }, '#/home'); await wait(p, 2900);
  s = await strip(p); ok(s && /Ledger problems\s*3/.test(s.text) && !/Bills without payment/.test(s.text), 'slow rpc: the fast chips are there, the slow one is dropped after the 2 s cap');
  await p.close();

  log('-- 3. not an owner: no chip, no owner-only rpc');
  p = await open({ owner: false }, '#/home'); await wait(p, 1500);
  s = await strip(p); ok(!s || s.hidden || (await chips(p).count()) === 0, 'non-owner without grants sees no chip');
  ok((await qc(p, 'ledger_problem_count')).length === 0 && (await qc(p, 'cost_wait_list96')).length === 0, 'owner-only rpcs are not even called');
  await p.close();

  log('-- 4. languages');
  p = await open({ lang: 'bn' }, '#/home'); await wait(p, 1500);
  s = await strip(p); ok(BN.test(s.text) && /Ledger|লেজার|খাতায়/.test(s.text), 'Bangla mode strip: ' + s.text);
  await noOverflow(p, 'bn badges'); await p.close();
  p = await open({ lang: 'mix' }, '#/home'); await wait(p, 1500);
  s = await strip(p); ok(BN.test(s.text) && /Ledger post|Cost|Auto post/.test(s.text), 'mix strip: ' + s.text); await p.close();

  log('-- 5. GRN picker in the landed bill picker');
  p = await open({}, '#/landed'); await p.click('[data-act=lc_new]'); await wait(p, 600);
  ok(await p.locator('#q4_grn [data-act=q4_grnload]').count() === 1, 'GRN picker is offered next to the bill picker');
  ok(await p.locator('[data-lcpk]').count() === 2, 'bill list is unchanged');
  await p.click('[data-act=q4_grnload]'); await wait(p, 500);
  ok(await p.locator('[data-q4g]').count() === 2, 'only submitted / approved GRNs (form 13-1) are listed');
  await p.check('[data-q4g="g1"]'); await p.click('[data-act=q4_grnadd]'); await wait(p, 600);
  let rc = await qc(p, 'landed_resolve_docs'); ok(rc.length === 1 && rc[0].p_docs[0].type === 'grn' && rc[0].p_docs[0].id === 'g1', 'landed_resolve_docs called with the GRN');
  ok(await p.locator(`[data-lcpk="${BILL2}"]`).isChecked(), 'the linked bill is ticked in the bill list');
  await p.check('[data-q4g="g2"]'); await p.click('[data-act=q4_grnadd]'); await wait(p, 600);
  ok(/not linked to a purchase bill/.test(await txt(p, '#q4_grnmsg')), 'a GRN with no linked bill says so');
  await noOverflow(p, 'grn picker'); await p.screenshot({ path: OUT + '/q4_grn.png' });
  ok(!BN.test(await p.evaluate(() => document.getElementById('q4_grn').innerText)), 'English: no Bangla letters in the GRN box');
  await p.click('[data-act=lc_pickgo]'); await wait(p, 600);
  ok(new RegExp('#/landed/new/.*' + BILL2).test(await p.evaluate(() => location.hash)), 'Continue opens the editor with the GRN bill');
  await p.close();
  p = await open({ lc: { info: { mode: 'per_shipment', alloc_default: 'value', late_mode: 'split_remaining_and_cogs', requires_approval: 'warn', reminder_on: false, base_currency: 'BDT', can_entry: true, can_approve: true, charge_types: [] } } }, '#/landed'); await p.click('[data-act=lc_new]'); await wait(p, 600);
  ok(/one shipment/.test(await txt(p, '#q4_mh')), 'per_shipment: hint to tick several bills / GRNs'); await p.close();
  p = await open({ lang: 'bn' }, '#/landed'); await p.click('[data-act=lc_new]'); await wait(p, 600);
  ok(/GRN/.test(await txt(p, '#q4_grn')) && BN.test(await txt(p, '#q4_grn')), 'Bangla mode GRN box'); await noOverflow(p, 'bn grn'); await p.close();

  log('-- 6. setup advisor: Undo');
  p = await open({}, '#/setupadvisor'); await wait(p, 700);
  await p.click('[data-act=sadv_tab][data-t=hist]'); await wait(p, 600);
  ok(await p.locator('[data-act=q4_undo]').count() === 1, 'history card has the Undo button (owner)');
  await p.click('[data-act=q4_undo]'); await wait(p, 400);
  const sh = await p.evaluate(() => document.body.innerText.replace(/\s+/g, ' '));
  ok(/k_one/.test(sh) && /k_two/.test(sh) && /Default/.test(sh), 'sheet lists both rows, null shown as Default');
  await noOverflow(p, 'undo sheet'); await p.screenshot({ path: OUT + '/q4_undo.png' });
  await p.click('[data-act=q4_undogo]'); await wait(p, 600);
  const sr = await calls(p, 'set_rule'); ok(sr.length === 2 && sr[0].p_key === 'k_one' && sr[0].p_value === null && sr[1].p_key === 'k_two' && sr[1].p_value === false, 'set_rule once per row with the OLD value (null = default, false)');
  await p.close();
  p = await open({ owner: false }, '#/setupadvisor'); await wait(p, 700);
  ok(await p.locator('[data-act=q4_undo]').count() === 0, 'non-owner: no Undo button'); await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
  if (bad || errors.length) process.exitCode = 1;
} catch (e) { console.log('TEST CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
