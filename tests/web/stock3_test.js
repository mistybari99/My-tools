// Stock hub carry-over (phase12): category labels, unit lists, name search, row menus, barcode scan on stock actions, photo prefix STOCK,
// wastage maker-checker (pending result + approvals tab). Run: node stock3_test.js <dir with smoke.js, stub.js>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), srv = C.serve(8311);
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
    await p.goto('http://localhost:8311/' + hash); await p.waitForTimeout(1000); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const lv = (i, id, code, bn, en, cat, bu, q, min) => ({ item_id: id, code, name_bn: bn, name_en: en, category: cat, base_unit: bu, location_id: 1, qty: q, min_stock: min, below_min: min !== null && q < min, avg_cost: null, value: null });
  const levels = [lv(0, IT[0].id, 'I-001', 'সাদা মিষ্টি', 'White sweet', 'sweet_kg', 'kg', 3.5, 5), lv(1, IT[1].id, 'I-002', 'কালো মিষ্টি', 'Black sweet', 'sweet_kg', 'kg', 8, null), lv(2, IT[2].id, 'I-003', 'রসমালাই', 'Rasmalai', 'sweet_pc', 'piece', 40, 10)];
  const patch = [{ sell_units: ['kg', 'box'], name_mix: 'Shada Mishti', barcode: '8801' }, {}, { barcode: '8803' }];
  const wa = [{ id: 'w1', item_id: IT[0].id, code: 'I-001', name_bn: 'সাদা মিষ্টি', name_en: 'White sweet', location_id: 1, qty: 10, base_unit: 'kg', reason_code: 'spoiled', note: 'tray fell', photo: null, status: 'pending', requested_staff: 'karim02', requested_at: '2026-10-11T05:00:00Z', mine: false, can_decide: true, decision_note: null }];

  // ---------- category labels, unit lists, search, row menu ----------
  let p = await open({ itemPatch: patch, m: { levels } }, '#/stock');
  ok(await p.locator('.s2-row').count() === 3, 'three rows');
  const t0 = await p.textContent('#s2_list');
  ok(/Sweets \(kg\)/.test(t0) && /Sweets \(piece\)/.test(t0) && !/sweet_kg/.test(t0), 'category shown by its list label, not the code');
  ok(/Buy: kg, gram, box · Sell: kg, box/.test(t0), 'buy / sell unit list of the item from unit_conversions + sell_units: ' + (t0.match(/Buy:[^\n]*?(?=I-00|$)/) || [''])[0].slice(0, 90));
  ok(/Buy: piece, box/.test(t0), 'second item buy units (item-specific box -> piece)');
  await p.fill('#s2_q', 'shada'); await wait(p, 200); ok(await p.locator('.s2-row').count() === 1, 'search finds the Bng-Eng name');
  await p.fill('#s2_q', 'sweets (piece)'); await wait(p, 200); ok(await p.locator('.s2-row').count() === 1, 'search finds the category label');
  await p.fill('#s2_q', '8803'); await wait(p, 200); ok(await p.locator('.s2-row').count() === 1, 'search finds the barcode');
  await p.fill('#s2_q', 'RASMA'); await wait(p, 200); ok(await p.locator('.s2-row').count() === 1, 'case-insensitive');
  await p.fill('#s2_q', 'I-00'); await wait(p, 200); ok(await p.locator('.s2-row').count() === 3, 'code search'); await p.fill('#s2_q', '');
  await p.click('#s2_fb'); await wait(p, 250); ok((await p.locator('#sf_cat option').allTextContents()).join('|').includes('Sweets (kg)'), 'filter category options use labels'); await p.click('[data-act=s2_fapply]'); await wait(p, 500);
  await p.click('.s2-dots >> nth=0'); await wait(p, 400);
  ok(await p.locator('.sheet [data-act=s2_item]').count() === 1 && await p.locator('.sheet [data-act=s2_do]').count() >= 1, 'row ⋮ menu: ledger + the actions the person may do');
  ok((await calls(p, 'stock_ledger_rows')).length === 0, 'opening the ⋮ menu does not open the ledger by itself');
  await p.screenshot({ path: SP + '/st3_menu.png' }); await noOverflow(p, 'row menu');
  await p.click('.sheet [data-act=s2_item]'); await wait(p, 500); ok((await calls(p, 'stock_ledger_rows')).length === 1, 'ledger entry of the menu works');
  await p.close();

  // ---------- barcode scan on stock actions ----------
  p = await open({ dev: true, itemPatch: patch, m: { levels } }, '#/stock');
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=count]'); await wait(p, 300);
  ok(await p.locator('[data-act=s2_scan]').count() === 1, 'scan button on the item field when a scan option is on');
  await p.click('[data-act=s2_scan]'); await wait(p, 300); ok(await p.locator('#bc_in').isVisible(), 'device scan input appears');
  await p.keyboard.type('8803'); await p.keyboard.press('Enter'); await wait(p, 300);
  ok((await p.inputValue('#a_item')).startsWith('I-003'), 'scanned code fills the item'); ok(/Base unit: piece/.test(await p.textContent('#a_item_h')), 'base-unit hint follows the scan');
  await p.click('[data-act=s2_scan]'); await wait(p, 300); await p.keyboard.type('0000'); await p.keyboard.press('Enter'); await wait(p, 300);
  ok(/No product has this barcode/.test(await toastTxt(p)), 'unknown barcode says so'); ok((await p.inputValue('#a_item')).startsWith('I-003'), 'unknown barcode leaves the item as it was');
  for (const k of ['xfer', 'issue', 'waste']) { await p.click('.sheet [data-act=closesheet]').catch(() => {}); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click(`[data-act=s2_do][data-v=${k}]`); await wait(p, 300); ok(await p.locator('[data-act=s2_scan]').count() === 1, 'scan button on ' + k); }
  await p.close();
  p = await open({ itemPatch: patch, m: { levels } }, '#/stock');
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=count]'); await wait(p, 300);
  ok(await p.locator('[data-act=s2_scan]').count() === 0, 'no scan button while both scan options are off'); await p.close();

  // ---------- photo prefix ----------
  fs.writeFileSync(SP + '/pic.png', C.PNGBUF);
  p = await open({ photoAbove: 5, m: { levels } }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=waste]'); await wait(p, 300);
  await p.setInputFiles('#a_file', SP + '/pic.png'); await wait(p, 700);
  let up = await p.evaluate(() => window.__UP); ok(up.length === 1 && /^STOCK\/1\/[0-9a-f-]+\.jpg$/.test(up[0][0]), 'wastage photo goes to the STOCK prefix: ' + JSON.stringify(up[0] && up[0][0])); await p.close();
  p = await open({ photoAbove: 5, m: { levels, upFail: 'STOCK/' } }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=waste]'); await wait(p, 300);
  await p.setInputFiles('#a_file', SP + '/pic.png'); await wait(p, 700);
  up = await p.evaluate(() => window.__UP); ok(up.length === 1 && /^04-1\/1\//.test(up[0][0]), 'database without phase12: falls back to the old form prefix: ' + JSON.stringify(up[0] && up[0][0])); await p.close();

  // ---------- wastage above the owner limit: pending ----------
  p = await open({ m: { levels, pendingWaste: true, wa } }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=waste]'); await wait(p, 300);
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '10'); await p.selectOption('#a_reason', 'spoiled'); await p.click('#a_go'); await wait(p, 500);
  ok(/Sent for approval/.test(await toastTxt(p)), 'pending result says it waits for approval (not "Saved")');
  const wc = await calls(p, 'stock_wastage'); ok(wc.length === 1 && wc[0].p_qty === 10 && wc[0].p_client, 'wastage call made once with a client id');
  // approvals tab (owner can decide)
  ok(await p.locator('.ptabs [data-v=wa]').count() === 1 && /1/.test(await p.textContent('.ptabs [data-v=wa]')), 'approvals tab with a count');
  await p.click('.ptabs [data-v=wa]'); await wait(p, 500); ok(await p.locator('.s2-row').count() === 1 && /10 kg/.test(await p.textContent('#s2_main')) && /tray fell/.test(await p.textContent('#s2_main')), 'pending request row');
  await p.screenshot({ path: SP + '/st3_wa.png' }); await noOverflow(p, 'approvals tab');
  await p.click('.s2-dots >> nth=0'); await wait(p, 300); ok(await p.locator('[data-act=s2_wa_yes]').count() === 1 && await p.locator('[data-act=s2_wa_no]').count() === 1, '⋮ has approve + reject');
  await p.click('[data-act=s2_wa_yes]'); await wait(p, 500); let wd = await calls(p, 'wastage_decide'); ok(wd.length === 1 && wd[0].p_id === 'w1' && wd[0].p_approve === true, 'approve call');
  await p.click('.ptabs [data-v=wa]'); await wait(p, 400); await p.click('.s2-dots >> nth=0'); await wait(p, 300); await p.click('[data-act=s2_wa_no]'); await wait(p, 300);
  await p.click('[data-act=s2_wa_go_no]'); await wait(p, 200); ok(/Write a note/.test(await toastTxt(p)) && (await calls(p, 'wastage_decide')).length === 1, 'reject needs a reason');
  await p.fill('#a_note', 'not wasted'); await p.click('[data-act=s2_wa_go_no]'); await wait(p, 500); wd = await calls(p, 'wastage_decide'); ok(wd.length === 2 && wd[1].p_approve === false && wd[1].p_note === 'not wasted', 'reject call with the note');
  await p.close();
  // the maker sees own request, cannot decide, can take it back
  const NO = 'window.__OWNER=false;window.__PERMS={};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};';
  const mine = [{ ...wa[0], mine: true, can_decide: false }];
  p = await open({ init: NO, m: { levels, wa: mine, grants: ['wastage_write_off'], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock');
  ok(await p.locator('.ptabs [data-v=wa]').count() === 1, 'a maker with a waiting request sees the tab'); await p.click('.ptabs [data-v=wa]'); await wait(p, 500);
  await p.click('.s2-dots >> nth=0'); await wait(p, 300); ok(await p.locator('[data-act=s2_wa_yes]').count() === 0 && await p.locator('[data-act=s2_wa_cancel]').count() === 1 && /Someone else must approve/.test(await p.textContent('.sheet')), 'maker: no approve, only take back');
  await p.click('[data-act=s2_wa_cancel]'); await wait(p, 400); ok((await calls(p, 'wastage_cancel')).length === 1, 'cancel call'); await p.close();
  // nobody to approve and nothing waiting: no tab
  p = await open({ init: NO, m: { levels, wa: [], grants: ['wastage_write_off'], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock');
  ok(await p.locator('.ptabs [data-v=wa]').count() === 0, 'no approvals tab without the grant and without own requests'); await p.close();
  // server error texts
  p = await open({ m: { levels } }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=waste]'); await wait(p, 300);
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '1'); await p.selectOption('#a_reason', 'spoiled'); await p.evaluate(() => { window.__M.fail.stock_wastage = { msg: 'own_request', once: true }; }); await p.click('#a_go'); await wait(p, 300);
  ok(/cannot approve your own/.test(await toastTxt(p)), 'own_request text'); await p.close();
  // exception flag labels
  p = await open({}, '#/stock'); ok(await p.evaluate(() => ['wastage_pending', 'sale_return', 'supplier_refund_void'].every((k) => /chip/.test(window.BOS.flagChip(k)))), 'flag labels for the new exception codes'); await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
