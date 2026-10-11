// Purchases + payables (purchase.js). Run: node purchase_test.js <scratchpad>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), srv = C.serve(8095);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(C.mkData(base, o))};window.__M0=${JSON.stringify(o.m || {})};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:8095/' + hash); await p.waitForTimeout(1000); return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const hash = (p) => p.evaluate(() => location.hash);
  const NO = 'window.__OWNER=false;window.__PERMS={};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};';

  // ---------- list + filters ----------
  let p = await open({}, '#/purchase');
  ok(await p.locator('#pl_list .card').count() === 4, 'four bills'); ok(await p.locator('#pl_list .mk.info').count() === 1 && await p.locator('#pl_list .mk.bad').count() === 1 && await p.locator('#pl_list .mk.warn').count() === 1, 'status edge bars: draft info, void bad, due warn');
  ok(/Due ৳ 600/.test(await p.textContent('#pl_list')), 'due on posted bill'); ok(await p.locator('#pl_list .chip', { hasText: 'Return' }).count() === 1, 'return chip');
  ok(await p.locator('.s2-bar .primary').count() === 1 && /New purchase bill/.test(await p.textContent('.s2-bar .primary')), 'one primary: New bill'); await p.screenshot({ path: SP + '/pu_list.png' }); await noOverflow(p, 'list');
  await p.click('#pl_fb'); await wait(p, 250); await p.screenshot({ path: SP + '/pu_filter.png' }); await noOverflow(p, 'filter');
  await p.selectOption('#pf_sup', 'sp1'); await p.selectOption('#pf_st', 'posted'); await p.fill('#pf_from', '2026-10-05'); await p.fill('#pf_to', '2026-10-31'); await p.click('[data-act=pu_fapply]'); await wait(p, 500);
  let pl = await calls(p, 'purchase_list'); const lp = pl[pl.length - 1]; ok(lp.p_supplier === 'sp1' && lp.p_status === 'posted' && lp.p_from === '2026-10-05' && lp.p_to === '2026-10-31', 'filters sent to purchase_list'); ok(await p.locator('#pl_list .card').count() === 2, 'filtered rows (posted bill + return)'); ok((await p.textContent('#pl_fb .cnt')) === '4', 'filter badge');
  await p.click('#pl_fb'); await wait(p, 200); await p.click('[data-act=pu_freset]'); await wait(p, 400); ok(await p.locator('#pl_list .card').count() === 4, 'reset');
  await p.close();

  // ---------- new bill: lines, totals, bank payment, idempotency ----------
  p = await open({}, '#/purchase/new'); await p.screenshot({ path: SP + '/pu_new.png' });
  await p.fill('#pe_sup', 'Dudh Ghor'); await p.fill('#pe_no', 'D-200'); await p.fill('[data-ln="0.item"]', 'I-001'); await p.dispatchEvent('[data-ln="0.item"]', 'change'); await wait(p, 200);
  ok((await p.inputValue('[data-ln="0.item"]')).startsWith('I-001 · '), 'item resolved'); ok(await p.locator('[data-ln="0.desc"]').count() === 0, 'description hidden when item chosen');
  await p.fill('[data-ln="0.qty"]', '5'); await p.fill('[data-ln="0.cost"]', '100'); await p.click('[data-act=pu_addline]'); await wait(p, 150);
  await p.fill('[data-ln="1.desc"]', 'Gas cylinder'); await p.fill('[data-ln="1.qty"]', '1'); await p.fill('[data-ln="1.cost"]', '50'); await p.fill('#pe_disc', '25'); await wait(p, 100);
  ok(/৳ 525/.test(await p.textContent('#pe_tot')), 'total 525 = 500+50-25');
  ok(await p.locator('[data-act=pay_add][data-m=bank]').count() === 1, 'bank payment mode offered'); await p.click('[data-act=pay_add][data-m=bank]'); await wait(p, 150); ok(/Bank/.test(await p.textContent('#pay_box')), 'bank row labelled');
  await p.fill('[data-pay="0.amount"]', '200'); await wait(p, 100); await p.screenshot({ path: SP + '/pu_new_filled.png' }); await noOverflow(p, 'editor');
  // save draft: duplicate bill first
  await p.evaluate(() => { window.__M.fail.save_purchase = { msg: 'duplicate_bill', once: true }; }); await p.click('#pe_save'); await wait(p, 300); ok(/already has this bill number/.test(await toastTxt(p)), 'duplicate_bill localized'); ok((await hash(p)) === '#/purchase/new', 'stays on editor');
  await p.click('#pe_save'); await wait(p, 600); let sp = await calls(p, 'save_purchase'); ok(sp.length === 2 && sp[0].p_client === sp[1].p_client && /^[0-9a-f-]{36}$/.test(sp[0].p_client), 'retry reuses client id');
  const a = sp[1]; ok(a.p_id === null && a.p_supplier === 'sp1' && a.p_loc === 1 && a.p_bill_no === 'D-200' && a.p_kind === 'bill' && a.p_discount === 25 && a.p_lines.length === 2, 'save args');
  ok(a.p_lines[0].item_id === 'i0' && a.p_lines[0].qty === 5 && a.p_lines[0].unit_cost === 100 && !('description' in a.p_lines[0]) && a.p_lines[1].description === 'Gas cylinder' && !('item_id' in a.p_lines[1]), 'line shapes (item vs free text)');
  ok((await hash(p)) === '#/purchase/b9', 'goes to the draft detail');
  await p.close();

  // post with payments: first fail (poster must differ), retry updates the same draft
  p = await open({}, '#/purchase/new'); await p.fill('#pe_sup', 'Dudh Ghor'); await p.fill('[data-ln="0.item"]', 'I-002'); await p.dispatchEvent('[data-ln="0.item"]', 'change'); await p.fill('[data-ln="0.qty"]', '2'); await p.fill('[data-ln="0.cost"]', '50');
  await p.click('[data-act=pay_add][data-m=bank]'); await p.fill('[data-pay="0.amount"]', '60'); await p.click('[data-act=pay_add][data-m=cash]'); await p.fill('[data-pay="1.amount"]', '40');
  await p.evaluate(() => { window.__M.fail.post_purchase = { msg: 'poster_must_differ', once: true }; }); await p.click('#pe_post'); await wait(p, 500); ok(/cannot post it/.test(await toastTxt(p)), 'poster_must_differ localized'); ok((await hash(p)) === '#/purchase/new', 'stay on editor after post error');
  await p.click('#pe_post'); await wait(p, 800); sp = await calls(p, 'save_purchase'); ok(sp.length === 2 && sp[1].p_id === 'b9' && sp[1].p_client === null, 'second save is an update by id (no client id)');
  const pp = await calls(p, 'post_purchase'); ok(pp.length === 2 && pp[1].p_id === 'b9' && JSON.stringify(pp[1].p_payments) === JSON.stringify([{ mode: 'bank', amount: 60 }, { mode: 'cash', amount: 40 }]), 'post with bank + cash payments: ' + JSON.stringify(pp[1].p_payments));
  ok((await hash(p)) === '#/purchase/b9', 'detail after post');
  // overpay stays on editor
  await p.close();
  p = await open({}, '#/purchase/new'); await p.fill('#pe_sup', 'Chini Mill'); await p.fill('[data-ln="0.desc"]', 'x'); await p.fill('[data-ln="0.qty"]', '1'); await p.fill('[data-ln="0.cost"]', '10'); await p.click('[data-act=pay_add][data-m=bank]'); await p.fill('[data-pay="0.amount"]', '99'); await p.click('#pe_post'); await wait(p, 300);
  ok(/more than what is owed/.test(await toastTxt(p)) && (await calls(p, 'save_purchase')).length === 0, 'overpay blocked client side before saving');
  await p.fill('[data-pay="0.amount"]', '5'); await p.fill('#pe_sup', 'Nobody'); await p.click('#pe_save'); await wait(p, 200); ok(/Choose a supplier/.test(await toastTxt(p)), 'supplier required');
  await p.fill('#pe_sup', 'Chini Mill'); await p.fill('[data-ln="0.qty"]', '0'); await p.click('#pe_save'); await wait(p, 200); ok(/wrong quantity or cost/.test(await toastTxt(p)), 'bad line'); await p.close();

  // ---------- detail + void ----------
  p = await open({}, '#/purchase/b1'); ok(/Dudh Ghor/.test(await p.textContent('header h1')), 'detail header'); ok(/Gas cylinder/.test(await p.textContent('.card')) || /Gas cylinder/.test(await p.textContent('body')), 'free-text line shown'); ok(/৳ 250/.test(await p.textContent('body')), 'line cost shown');
  ok(await p.locator('[data-act=pu_void]').count() === 1 && await p.locator('.s2-bar .primary').count() === 1, 'void + one primary (pay supplier)'); await p.screenshot({ path: SP + '/pu_detail.png' }); await noOverflow(p, 'detail');
  await p.click('[data-act=pu_void]'); await wait(p, 250); await p.screenshot({ path: SP + '/pu_void.png' }); await p.click('#vn_go'); await wait(p, 150); ok(/Write the reason/.test(await toastTxt(p)) && (await calls(p, 'void_purchase')).length === 0, 'void note required');
  await p.fill('#vn_note', 'wrong supplier'); await p.click('#vn_go'); await wait(p, 500); const vp = await calls(p, 'void_purchase'); ok(vp.length === 1 && vp[0].p_id === 'b1' && vp[0].p_note === 'wrong supplier', 'void_purchase args'); await p.close();
  p = await open({ m: { detail: { b1: { status: 'void', void_note: 'dup entry' } } } }, '#/purchase/b1'); ok(/dup entry/.test(await p.textContent('body')) && await p.locator('[data-act=pu_void]').count() === 0, 'voided bill shows note and no void button'); await p.close();
  // draft detail: post sheet with payments
  p = await open({}, '#/purchase/b2'); ok(await p.locator('[data-act=pu_postd]').count() === 1 && await p.locator('[data-act=pu_edit]').count() === 1, 'draft actions'); await p.click('[data-act=pu_postd]'); await wait(p, 400); ok(await p.locator('#pp_pay').count() === 1, 'post sheet has payments'); await p.screenshot({ path: SP + '/pu_post.png' });
  await p.click('[data-act=pay_add][data-m=bank]'); await p.fill('[data-pay="0.amount"]', '100'); await p.click('#pp_go'); await wait(p, 600); const p2 = await calls(p, 'post_purchase'); ok(p2.length === 1 && p2[0].p_id === 'b2' && p2[0].p_payments[0].mode === 'bank', 'post from draft detail'); await p.close();
  // edit draft
  p = await open({}, '#/purchase/edit/b2'); ok((await p.inputValue('#pe_sup')) === 'Chini Mill' && (await p.inputValue('[data-ln="0.qty"]')) === '4', 'draft loaded into editor'); await p.click('#pe_save'); await wait(p, 500); sp = await calls(p, 'save_purchase'); ok(sp.length === 1 && sp[0].p_id === 'b2' && sp[0].p_client === null, 'edit saves by id'); await p.close();

  // ---------- return flow ----------
  p = await open({}, '#/purchase/return/b1'); ok(await p.locator('#pe_reason').count() === 1 && await p.locator('#pe_pay').count() === 0, 'return: reason, no payments'); await wait(p, 300); ok((await p.inputValue('#pe_sup')) === 'Dudh Ghor', 'supplier from original bill'); ok(await p.locator('#pe_ref option').count() >= 2, 'against-bill list'); await p.screenshot({ path: SP + '/pu_return.png' });
  await p.fill('[data-ln="0.desc"]', 'Spoiled milk'); await p.fill('[data-ln="0.qty"]', '2'); await p.fill('[data-ln="0.cost"]', '40'); await p.click('#pe_save'); await wait(p, 200); ok(/Choose the return reason/.test(await toastTxt(p)), 'return reason required');
  await p.selectOption('#pe_reason', 'damaged'); await p.click('#pe_post'); await wait(p, 600); sp = await calls(p, 'save_purchase'); ok(sp.length === 1 && sp[0].p_kind === 'return' && sp[0].p_reason === 'damaged' && sp[0].p_ref_bill === 'b1', 'return args'); const pr = await calls(p, 'post_purchase'); ok(pr.length === 1 && pr[0].p_payments === null, 'return posted without payments'); await p.close();

  // ---------- photo path ----------
  p = await open({}, '#/purchase/new'); fs.writeFileSync(SP + '/pic.png', C.PNGBUF); await p.setInputFiles('#pe_file', SP + '/pic.png'); await wait(p, 700);
  const up = await p.evaluate(() => window.__UP); ok(up.length === 1 && /^PURCHASE\/1\/[0-9a-f-]+\.jpg$/.test(up[0][0]), 'bill photo path ' + JSON.stringify(up[0] && up[0][0])); await p.close();

  // ---------- payables ----------
  p = await open({}, '#/payables'); ok(/1,100/.test(await p.textContent('.plate')), 'total payable plate'); ok(await p.locator('#py_list .mk.bad').count() === 1, 'overdue edge bar'); ok(/7 credit days/.test(await p.textContent('#py_list')), 'credit days chip'); ok(/Overdue ৳ 600/.test(await p.textContent('#py_list')), 'overdue chip');
  await p.screenshot({ path: SP + '/py_list.png' }); await noOverflow(p, 'payables');
  await p.click('#py_list .card >> nth=0'); await wait(p, 600); await p.screenshot({ path: SP + '/py_ledger.png' }); await noOverflow(p, 'ledger sheet'); ok(/oldest bills first/.test(await p.textContent('.sheet')), 'oldest-first note'); ok(/Open bills/.test(await p.textContent('.sheet')), 'open bills listed');
  ok(await p.locator('[data-act=py_void]').count() === 1, 'void payment button for owner');
  await p.fill('[data-pay="0.amount"]', '700'); await wait(p, 100); await p.click('[data-act=py_pay]'); await wait(p, 200); ok(/more than what is owed/.test(await toastTxt(p)) && (await calls(p, 'pay_supplier')).length === 0, 'overpay blocked');
  await p.fill('[data-pay="0.amount"]', '100'); await p.click('[data-act=pay_add][data-m=bank]'); await p.fill('[data-pay="1.amount"]', '50'); await p.fill('#py_note', 'part'); await p.evaluate(() => { window.__M.fail.pay_supplier = { msg: 'overpaid', once: true }; });
  await p.click('[data-act=py_pay]'); await wait(p, 300); ok(/more than what is owed/.test(await toastTxt(p)), 'server overpaid localized'); await p.click('[data-act=py_pay]'); await wait(p, 600);
  const ps = await calls(p, 'pay_supplier'); ok(ps.length === 2 && ps[0].p_client === ps[1].p_client && ps[1].p_supplier === 'sp1' && JSON.stringify(ps[1].p_payments) === JSON.stringify([{ mode: 'cash', amount: 100 }, { mode: 'bank', amount: 50 }]) && ps[1].p_note === 'part', 'pay_supplier args + same client on retry: ' + JSON.stringify(ps[1]));
  await p.click('#py_list .card >> nth=0'); await wait(p, 500); await p.click('[data-act=py_void]'); await wait(p, 250); await p.click('[data-act=py_voidgo]'); await wait(p, 150); ok(/Write the reason/.test(await toastTxt(p)), 'payment void needs a reason');
  await p.fill('#vn_note', 'typo'); await p.click('[data-act=py_voidgo]'); await wait(p, 500); const vs = await calls(p, 'void_supplier_payment'); ok(vs.length === 1 && vs[0].p_id === 7 && vs[0].p_note === 'typo', 'void_supplier_payment args');
  await p.close();
  p = await open({ m: { dues: [], summary: { total_payable: 0, suppliers_owed: 0, overdue: 0, overdue_suppliers: 0, oldest: null, credit_total: 0 } } }, '#/payables'); ok(/owe no supplier/.test(await p.textContent('#py_list')), 'empty payables state'); await p.close();

  // ---------- permissions ----------
  p = await open({ init: NO, m: { grants: [], ctx: { locations: [1], roles: ['purchasing'] } } }, '#/purchase');
  ok(await p.locator('.s2-bar .primary').count() === 0 && await p.locator('.s2-bar button[disabled]').count() === 2, 'lock mode: both new buttons locked'); await p.screenshot({ path: SP + '/pu_lock.png' }); await p.close();
  p = await open({ hide: true, init: NO, m: { grants: [], ctx: { locations: [1], roles: ['purchasing'] } } }, '#/purchase'); ok(await p.locator('.s2-bar button').count() === 0, 'hide mode: no new buttons'); await p.close();
  p = await open({ init: NO, m: { grants: ['purchase_entry'], ctx: { locations: [1], roles: ['purchasing'] } } }, '#/purchase');
  ok(await p.locator('.s2-bar .primary').count() === 1 && await p.locator('.s2-bar button[disabled]').count() === 1, 'entry grant only: new bill ok, return locked');
  await p.click('.s2-bar .primary'); await wait(p, 600); ok(await p.locator('#pe_pay').count() === 0, 'no payments section without supplier_pay'); await p.close();
  p = await open({ init: NO, m: { grants: ['purchase_entry'], ctx: { locations: [1], roles: ['purchasing'] } } }, '#/purchase/b1'); ok(await p.locator('[data-act=pu_void]').count() === 0 && await p.locator('button[disabled]').count() >= 1, 'void locked without purchase_void'); await p.close();
  p = await open({ init: NO, m: { grants: [], ctx: { locations: [1], roles: ['purchasing'] }, fail: { purchase_list: { msg: 'not allowed' } } } }, '#/purchase'); ok(await p.locator('.lockcard').count() === 1, 'lock card when the server refuses purchase_list'); await p.close();
  p = await open({ init: NO, m: { grants: ['supplier_pay'], ctx: { locations: [1], roles: ['purchasing'] } } }, '#/payables'); await p.click('#py_list .card >> nth=0'); await wait(p, 500); ok(await p.locator('[data-act=py_pay]').count() === 1 && await p.locator('[data-act=py_void]').count() === 0, 'pay allowed, void payment hidden without purchase_void'); await p.close();
  p = await open({ init: NO, m: { grants: [], ctx: { locations: [1], roles: ['purchasing'] } } }, '#/payables'); await p.click('#py_list .card >> nth=0'); await wait(p, 500); ok(await p.locator('[data-act=py_pay]').count() === 0 && await p.locator('.s2-lockrow').count() === 1, 'pay locked without supplier_pay'); await p.close();

  // ---------- languages ----------
  for (const lang of ['bn', 'mix']) { p = await open({ lang }, '#/purchase'); await p.screenshot({ path: SP + `/pu_${lang}.png` }); await noOverflow(p, 'list ' + lang); await p.evaluate(() => { location.hash = '#/purchase/new'; }); await wait(p, 600); await p.screenshot({ path: SP + `/pu_new_${lang}.png` }); await noOverflow(p, 'new ' + lang);
    await p.evaluate(() => { location.hash = '#/payables'; }); await wait(p, 600); await p.screenshot({ path: SP + `/py_${lang}.png` }); await noOverflow(p, 'payables ' + lang); await p.close(); }

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
