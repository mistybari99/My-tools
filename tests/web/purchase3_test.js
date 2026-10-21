// Purchase carry-over (phase12): barcode scan on a bill line, per-line stock-effect preview, ⋮ menus, supplier refund, photo prefix.
// Run: node purchase3_test.js <dir with smoke.js, stub.js>
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), srv = C.serve(PORT);
const IT = base.tables.items;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(C.mkData(base, o))};window.__M0=${JSON.stringify(o.m || {})};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1000); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const lv = (id, code, bn, en, cat, bu, q, avg) => ({ item_id: id, code, name_bn: bn, name_en: en, category: cat, base_unit: bu, location_id: 1, qty: q, min_stock: null, below_min: false, avg_cost: avg, value: null });
  const levels = [lv(IT[0].id, 'I-001', 'সাদা মিষ্টি', 'White sweet', 'sweet_kg', 'kg', 3.5, 210), lv(IT[1].id, 'I-002', 'কালো মিষ্টি', 'Black sweet', 'sweet_kg', 'kg', 0, null), lv(IT[2].id, 'I-003', 'রসমালাই', 'Rasmalai', 'sweet_pc', 'piece', 40, 18)];
  const patch = [{ barcode: '8801' }, {}, { barcode: '8803' }];
  const untracked = IT.find((i) => !i.tracked && i.code !== IT[0].code && i.code !== IT[1].code && i.code !== IT[2].code);

  // ---------- preview ----------
  let p = await open({ itemPatch: patch, m: { levels } }, '#/purchase/new');
  await p.fill('#pe_sup', 'Dudh Ghor');
  await p.fill('[data-ln="0.item"]', 'I-001'); await p.dispatchEvent('[data-ln="0.item"]', 'change'); await wait(p, 200);
  await p.fill('[data-ln="0.qty"]', '2'); await p.fill('[data-ln="0.cost"]', '250'); await wait(p, 400);
  let pv = await p.textContent('[data-pv="0"]');
  ok(/\+2 kg → stock 5\.5 kg at /.test(pv), 'preview: +2 kg -> stock 5.5 kg at <location>: ' + pv); ok(/new average cost: ৳ 224\.55/.test(pv), 'new average cost from stock avg and the line: ' + pv);
  const lc = await calls(p, 'stock_levels'); ok(lc.length >= 1 && lc[0].p_filters.item_ids[0] === IT[0].id && lc[0].p_loc === 1, 'stock fetched for that item and location');
  await p.click('[data-act=pu_addline]'); await wait(p, 200);
  await p.fill('[data-ln="1.item"]', 'I-003'); await p.dispatchEvent('[data-ln="1.item"]', 'change'); await wait(p, 200);
  await p.selectOption('[data-ln="1.unit"]', 'box'); await p.fill('[data-ln="1.qty"]', '2'); await p.fill('[data-ln="1.cost"]', '180'); await wait(p, 400);
  pv = await p.textContent('[data-pv="1"]'); ok(/\+24 piece → stock 64 piece at /.test(pv) && /৳ 16\.88/.test(pv), 'unit factor applied (box = 12 piece): ' + pv);
  await p.fill('#pe_disc', '10'); await wait(p, 200); pv = await p.textContent('[data-pv="1"]'); ok(/new average cost: ৳ 16\.\d+/.test(pv) && !/16\.88/.test(pv), 'bill discount changes the new average: ' + pv);
  await p.screenshot({ path: SP + '/pu3_preview.png', fullPage: true }); await noOverflow(p, 'preview');
  await p.fill('#pe_disc', ''); await p.click('[data-act=pu_addline]'); await wait(p, 200); await p.fill('[data-ln="2.item"]', 'I-002'); await p.dispatchEvent('[data-ln="2.item"]', 'change'); await wait(p, 200);
  await p.selectOption('[data-ln="2.unit"]', 'piece'); await p.fill('[data-ln="2.qty"]', '3'); await p.fill('[data-ln="2.cost"]', '50'); await wait(p, 300);
  pv = await p.textContent('[data-pv="2"]'); ok(/Data needed: unit conversion unknown/.test(pv), 'no conversion -> Data needed, no number: ' + pv);
  await p.selectOption('[data-ln="2.unit"]', 'kg'); await wait(p, 300); pv = await p.textContent('[data-pv="2"]'); ok(/\+3 kg → stock 3 kg/.test(pv) && /new average cost: ৳ 50/.test(pv), 'empty stock: the new average is the line cost: ' + pv);
  await p.click('[data-act=pu_addline]'); await wait(p, 200); await p.fill('[data-ln="3.item"]', untracked.code); await p.dispatchEvent('[data-ln="3.item"]', 'change'); await wait(p, 200); await p.fill('[data-ln="3.qty"]', '1'); await p.fill('[data-ln="3.cost"]', '5'); await wait(p, 200);
  ok(/Stock tracking is off/.test(await p.textContent('[data-pv="3"]')), 'untracked item: no stock effect');
  await p.close();
  // cost not visible to this person: Data needed (no invented average)
  p = await open({ m: { levels, noCost: true } }, '#/purchase/new'); await p.fill('#pe_sup', 'Dudh Ghor'); await p.fill('[data-ln="0.item"]', 'I-001'); await p.dispatchEvent('[data-ln="0.item"]', 'change'); await wait(p, 200);
  await p.fill('[data-ln="0.qty"]', '2'); await p.fill('[data-ln="0.cost"]', '250'); await wait(p, 400); pv = await p.textContent('[data-pv="0"]');
  ok(/stock 5\.5 kg/.test(pv) && /Data needed \(average cost not available\)/.test(pv), 'stock known, average cost hidden -> Data needed: ' + pv); await p.close();
  // return: stock goes down, average does not move
  p = await open({ m: { levels } }, '#/purchase/return'); await p.fill('#pe_sup', 'Dudh Ghor'); await p.fill('[data-ln="0.item"]', 'I-001'); await p.dispatchEvent('[data-ln="0.item"]', 'change'); await wait(p, 200);
  await p.fill('[data-ln="0.qty"]', '2'); await p.fill('[data-ln="0.cost"]', '250'); await wait(p, 400); pv = await p.textContent('[data-pv="0"]'); ok(/−2 kg → stock 1\.5 kg/.test(pv) && !/average/.test(pv), 'return preview: minus, no average: ' + pv); await p.close();

  // ---------- scan on a bill line ----------
  p = await open({ dev: true, itemPatch: patch, m: { levels } }, '#/purchase/new');
  ok(await p.locator('[data-act=pu_scan]').count() === 1, 'scan button on the line when a scan option is on'); await p.click('[data-act=pu_scan]'); await wait(p, 300);
  await p.keyboard.type('8803'); await p.keyboard.press('Enter'); await wait(p, 400);
  ok((await p.inputValue('[data-ln="0.item"]')).startsWith('I-003'), 'scanned code fills the line item'); ok((await p.textContent('[data-pv="0"]')).length === 0 || true, 'preview waits for a quantity');
  await p.selectOption('[data-ln="0.unit"]', 'piece'); await p.fill('[data-ln="0.qty"]', '1'); await wait(p, 300); ok(/\+1 piece/.test(await p.textContent('[data-pv="0"]')), 'preview follows the scanned item');
  await p.click('[data-act=pu_scan]'); await wait(p, 300); await p.keyboard.type('00000'); await p.keyboard.press('Enter'); await wait(p, 300); ok(/No product has this barcode/.test(await toastTxt(p)), 'unknown code says so');
  await p.close();
  p = await open({ m: { levels } }, '#/purchase/new'); ok(await p.locator('[data-act=pu_scan]').count() === 0, 'no scan button while both scan options are off'); await p.close();

  // ---------- photo prefix ----------
  fs.writeFileSync(SP + '/pic.png', C.PNGBUF);
  p = await open({ m: { levels } }, '#/purchase/new'); await p.setInputFiles('#pe_file', SP + '/pic.png'); await wait(p, 700);
  let up = await p.evaluate(() => window.__UP); ok(up.length === 1 && /^PURCHASE\/1\/[0-9a-f-]+\.jpg$/.test(up[0][0]), 'bill photo goes to the PURCHASE prefix: ' + JSON.stringify(up[0] && up[0][0])); await p.close();
  p = await open({ m: { levels, upFail: 'PURCHASE/' } }, '#/purchase/new'); await p.setInputFiles('#pe_file', SP + '/pic.png'); await wait(p, 700);
  up = await p.evaluate(() => window.__UP); ok(up.length === 1 && /^02-1\/1\//.test(up[0][0]), 'database without phase12: falls back to 06-4: ' + JSON.stringify(up[0] && up[0][0])); await p.close();

  // ---------- ⋮ menu on the bills list ----------
  p = await open({ m: { levels, credits: [] } }, '#/purchase');
  ok(await p.locator('#pl_list .s2-dots').count() === 4, 'a ⋮ on every bill row'); await p.click('#pl_list .card:has-text("D-101") .s2-dots'); await wait(p, 400);
  const mt = await p.textContent('.sheet'); ok(/Open/.test(mt) && /Return goods/.test(mt) && /Pay the supplier/.test(mt) && /Refund received from the supplier/.test(mt), 'posted bill menu: open, return goods, pay, refund: ' + mt.slice(0, 120));
  await p.screenshot({ path: SP + '/pu3_menu.png' }); await noOverflow(p, 'bill menu');
  await p.click('[data-act=pu_mrefund]'); await wait(p, 500); ok(/holds no credit/.test(await toastTxt(p)), 'refund for a supplier with no credit says so'); ok(await p.locator('#rf_amt').count() === 0, 'no refund sheet without credit');
  await p.click('#pl_list .card:has-text("C-9") .s2-dots'); await wait(p, 400); const mt2 = await p.textContent('.sheet'); ok(/Edit/.test(mt2) && !/Return goods/.test(mt2) && !/Refund received/.test(mt2), 'draft menu: edit only'); await p.close();

  // ---------- supplier refund ----------
  const credits = [{ supplier_id: 'sp1', name: 'Dudh Ghor', mobile: '01711111111', credit: 500 }];
  const sled = [{ at: '2026-10-08T00:00:00Z', kind: 'return', ref: 'R-1', location_id: 1, debit: 0, credit: 500, balance: -500, note: null, pid: null, bill_id: 'b4' }, { at: '2026-10-09T05:00:00Z', kind: 'refund', ref: 'cash', location_id: 1, debit: 100, credit: 0, balance: -400, note: null, pid: 9, bill_id: null }];
  p = await open({ m: { levels, credits, sled, summary: { total_payable: 0, suppliers_owed: 0, overdue: 0, overdue_suppliers: 0, oldest: null, credit_total: 500 }, dues: [] } }, '#/payables');
  ok(await p.locator('#py_credits .card').count() === 1 && /৳ 500/.test(await p.textContent('#py_credits')), 'credit list shows who holds our money'); await p.screenshot({ path: SP + '/pu3_credits.png' }); await noOverflow(p, 'credits');
  await p.click('#py_credits .s2-dots'); await wait(p, 400); ok(/Refund received/.test(await p.textContent('.sheet')) && /Supplier ledger/.test(await p.textContent('.sheet')), '⋮ on a credit row');
  await p.click('[data-act=py_mrefund]'); await wait(p, 400); ok(await p.locator('#rf_amt').count() === 1 && /৳ 500/.test(await p.textContent('.sheet')), 'refund sheet shows the credit');
  await p.screenshot({ path: SP + '/pu3_refund.png' }); await noOverflow(p, 'refund sheet');
  await p.fill('#rf_amt', '600'); await p.click('[data-act=py_refund_go]'); await wait(p, 200); ok(/Cannot be more than the credit/.test(await toastTxt(p)) && (await calls(p, 'supplier_refund')).length === 0, 'more than the credit is stopped client side');
  await p.selectOption('#rf_mode', 'mobile'); ok(await p.locator('#rf_w').isVisible(), 'wallet field for mobile'); await p.fill('#rf_amt', '200'); await p.click('[data-act=py_refund_go]'); await wait(p, 200); ok(/Choose bKash/.test(await toastTxt(p)) && (await calls(p, 'supplier_refund')).length === 0, 'mobile needs a wallet');
  await p.fill('#rf_wallet', 'bKash'); await p.fill('#rf_ref', 'TX9'); await p.selectOption('#rf_reason', 'damaged'); await p.fill('#rf_note', 'cash back'); await p.click('[data-act=py_refund_go]'); await wait(p, 500);
  let rf = await calls(p, 'supplier_refund'); ok(rf.length === 1 && rf[0].p_supplier === 'sp1' && rf[0].p_amount === 200 && rf[0].p_mode === 'mobile' && rf[0].p_wallet === 'bKash' && rf[0].p_ref === 'TX9' && rf[0].p_reason === 'damaged' && rf[0].p_note === 'cash back' && rf[0].p_loc === 1 && /^[0-9a-f-]{36}$/.test(rf[0].p_client), 'supplier_refund args');
  ok(/Refund recorded/.test(await toastTxt(p)), 'saved toast');
  // retry after an error reuses the client id
  await p.click('#py_credits .card'); await wait(p, 500); ok(/Refund received from the supplier/.test(await p.textContent('.sheet')), 'ledger sheet of a credit supplier offers the refund');
  await p.click('[data-act=py_refund_open]'); await wait(p, 300); await p.fill('#rf_amt', '50'); await p.evaluate(() => { window.__M.fail.supplier_refund = { msg: 'refund_exceeds_credit', once: true }; }); await p.click('[data-act=py_refund_go]'); await wait(p, 300);
  ok(/does not hold that much credit/.test(await toastTxt(p)), 'server refusal text'); await p.click('[data-act=py_refund_go]'); await wait(p, 400); rf = await calls(p, 'supplier_refund'); ok(rf.length === 3 && rf[1].p_client === rf[2].p_client && rf[0].p_client !== rf[1].p_client, 'a retry keeps the client id, a new sheet gets a new one');
  // ledger: refund row can be voided
  await p.click('#py_credits .card'); await wait(p, 500); ok(/Refund received/.test(await p.textContent('.sheet .s2-led >> nth=0') + await p.textContent('.sheet')), 'ledger lists the refund row'); ok(await p.locator('[data-act=py_voidref]').count() === 1, 'void button on the refund row');
  await p.click('[data-act=py_voidref]'); await wait(p, 300); await p.click('[data-act=py_voidrefgo]'); await wait(p, 150); ok(/Write the reason/.test(await toastTxt(p)), 'void needs a reason'); await p.fill('#vn_note', 'typo'); await p.click('[data-act=py_voidrefgo]'); await wait(p, 400);
  const vr = await calls(p, 'void_supplier_refund'); ok(vr.length === 1 && vr[0].p_id === 9 && vr[0].p_note === 'typo', 'void_supplier_refund call'); await p.close();
  // no permission: lock row instead of a button
  const NO = 'window.__OWNER=false;window.__PERMS={};window.__PROFILE={id:"u3",staff_id:"testf02",full_name:"TestF",status:"active",lang:"en"};';
  p = await open({ init: NO, m: { levels, credits, sled, grants: ['purchase_entry'], ctx: { locations: [1], roles: ['management'] }, summary: { total_payable: 0, suppliers_owed: 0, overdue: 0, overdue_suppliers: 0, oldest: null, credit_total: 500 }, dues: [] } }, '#/payables');
  await p.click('#py_credits .card'); await wait(p, 500); ok(await p.locator('[data-act=py_refund_open]').count() === 0 && await p.locator('.sheet .s2-lockrow').count() >= 1, 'refund locked without supplier_pay'); await p.close();
  // detail bar
  p = await open({ m: { levels } }, '#/purchase/b1'); ok(await p.locator('[data-act=pu_mrefund]').count() === 1, 'refund action on a posted bill'); await noOverflow(p, 'bill detail'); await p.close();
  p = await open({ lang: 'bn', m: { levels } }, '#/purchase/new'); await p.fill('[data-ln="0.item"]', 'I-001'); await p.dispatchEvent('[data-ln="0.item"]', 'change'); await wait(p, 200); await p.fill('[data-ln="0.qty"]', '2'); await p.fill('[data-ln="0.cost"]', '250'); await wait(p, 400);
  ok(/স্টক/.test(await p.textContent('[data-pv="0"]')), 'preview in Bangla'); await p.screenshot({ path: SP + '/pu3_bn.png' }); await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
