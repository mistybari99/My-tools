// Stock hub (stock2.js). Run: node stock2_test.js <scratchpad>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), srv = C.serve(8094);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(C.mkData(base, o))};window.__M0=${JSON.stringify(o.m || {})};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:8094/' + hash); await p.waitForTimeout(1000); return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };
  const wait = (p, n = 300) => p.waitForTimeout(n);

  // ---------- levels ----------
  let p = await open({}, '#/stock');
  ok(await p.locator('.s2-row').count() === 3, 'three level rows'); ok(await p.locator('.s2-row.mk.warn').count() === 1, 'below-min edge bar (warn)'); ok(await p.locator('.s2-row.mk.bad').count() === 1, 'zero stock edge bar (bad)');
  ok(/3\.5 kg/.test(await p.textContent('.s2-row')), 'qty in base unit'); ok(/avg cost ৳ 210/.test(await p.textContent('#s2_list')), 'avg cost shown when returned'); ok(await p.locator('#s2_val').count() === 1, 'stock value stat shown');
  await p.screenshot({ path: SP + '/st_levels.png' }); await noOverflow(p, 'levels');
  await p.fill('#s2_q', 'rasma'); await wait(p, 200); ok(await p.locator('.s2-row').count() === 1, 'search narrows'); await p.fill('#s2_q', '');
  await wait(p, 200);
  await p.click('#s2_fb'); await wait(p, 250); await p.screenshot({ path: SP + '/st_filter.png' }); await noOverflow(p, 'filter sheet');
  await p.click('#sf_below'); await p.selectOption('#sf_cat', 'sweet_kg'); await p.click('[data-act=s2_fapply]'); await wait(p, 400);
  let lc = await calls(p, 'stock_levels'); const last = lc[lc.length - 1]; ok(last.p_filters.below_min === true && last.p_filters.category === 'sweet_kg', 'filters sent to stock_levels'); ok(await p.locator('.s2-row').count() === 1, 'filtered rows'); ok((await p.textContent('#s2_fb .cnt')) === '2', 'filter count badge');
  await p.click('#s2_fb'); await wait(p, 200); await p.click('[data-act=s2_freset]'); await wait(p, 400); ok(await p.locator('.s2-row').count() === 3, 'reset restores');
  // drill
  await p.click('.s2-row >> nth=0'); await wait(p, 500); const dr = await calls(p, 'stock_ledger_rows'); ok(dr.length === 1 && dr[0].p_item === 'i0' && dr[0].p_loc === 1, 'ledger rows requested for item and location');
  ok(/Sale/.test(await p.textContent('.sheet')) && /−1\.5/.test(await p.textContent('.sheet')) && /\+5/.test(await p.textContent('.sheet')), 'ledger rows signed'); ok(/৳ 210/.test(await p.textContent('.sheet')), 'ledger cost shown when returned');
  await p.screenshot({ path: SP + '/st_drill.png' }); await noOverflow(p, 'drill'); await p.click('.sheet [data-act=closesheet]');
  await p.close();

  // cost hidden when the server returns null
  p = await open({ m: { noCost: true } }, '#/stock');
  ok(await p.locator('.s2-row').count() === 3, 'rows still listed'); ok(!/avg|৳/.test(await p.textContent('#s2_list')), 'no cost or value text when null'); ok(await p.locator('#s2_val').count() === 0, 'no value stat when null');
  await p.click('.s2-row >> nth=0'); await wait(p, 400); ok(!/৳/.test(await p.textContent('.sheet')), 'no cost in drill when null'); await p.close();

  // ---------- expiring ----------
  p = await open({}, '#/stock'); await p.click('[data-v=exp]'); await wait(p, 500);
  ok(await p.locator('.s2-row').count() === 2, 'two expiring batches'); ok(await p.locator('.s2-row.mk.bad').count() === 1 && await p.locator('.s2-row.mk.warn').count() === 1, 'expired = bad bar, soon = warn bar'); ok(/5\.5 h left/.test(await p.textContent('#s2_main')), 'hours left'); ok(/Expired 3 h ago/.test(await p.textContent('#s2_main')), 'expired ago');
  let ex = await calls(p, 'expiry_list'); ok(ex[ex.length - 1].p_hours_ahead === 24, 'expiry 24h default'); await p.screenshot({ path: SP + '/st_expiry.png' }); await noOverflow(p, 'expiry');
  await p.click('[data-act=s2_exph][data-v="48"]'); await wait(p, 400); ex = await calls(p, 'expiry_list'); ok(ex[ex.length - 1].p_hours_ahead === 48, 'hours switch');
  await p.click('[data-act=s2_expwo] >> nth=0'); await wait(p, 300); await p.click('[data-act=s2_go_expwo]'); await wait(p, 400);
  const ew = await calls(p, 'stock_expire_batch'); ok(ew.length === 1 && ew[0].p_batch === 11 && ew[0].p_reason === 'expired', 'expire batch called'); await p.close();
  p = await open({ m: { exp: [] } }, '#/stock'); await p.click('[data-v=exp]'); await wait(p, 400); ok(/Expiry is off/.test(await p.textContent('#s2_main')), 'expiry-off empty state'); await p.screenshot({ path: SP + '/st_expiry_off.png' }); await p.close();

  // ---------- in transit ----------
  p = await open({}, '#/stock'); await p.click('[data-v=tr]'); await wait(p, 500);
  ok(await p.locator('#s2_main .card').count() === 2, 'two transfers'); ok(await p.locator('[data-act=s2_xrecv]').count() === 2 && await p.locator('[data-act=s2_xcancel]').count() === 2, 'owner can receive and take back'); await p.screenshot({ path: SP + '/st_transit.png' }); await noOverflow(p, 'transit');
  await p.click('[data-act=s2_xrecv] >> nth=0'); await wait(p, 300); ok(await p.locator('#r_short').isHidden(), 'no short warning at full qty'); await p.fill('#r_qty', '8'); await wait(p, 100); ok(await p.locator('#r_short').isVisible(), 'short warning when less'); await p.screenshot({ path: SP + '/st_recv.png' });
  await p.click('[data-act=s2_go_recv]'); await wait(p, 400); const rv = await calls(p, 'stock_receive_transfer'); ok(rv.length === 1 && rv[0].p_id === 't1' && rv[0].p_received_qty === 8, 'short receive qty sent');
  await p.click('[data-act=s2_xcancel] >> nth=1'); await wait(p, 300); await p.click('[data-act=s2_go_xcancel]'); await wait(p, 400); const cn = await calls(p, 'stock_cancel_transfer'); ok(cn.length === 1 && cn[0].p_id === 't2', 'cancel transfer called');
  await p.close();
  // non-owner: only the destination can receive; sender can take back own transfer
  p = await open({ init: 'window.__OWNER=false;window.__PERMS={};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};', m: { grants: ['stock_transfer'], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock');
  await p.click('[data-v=tr]'); await wait(p, 500); ok(await p.locator('[data-act=s2_xrecv]').count() === 1, 'storekeeper receives only at own location'); ok(await p.locator('[data-act=s2_xcancel]').count() >= 1, 'sender sees take back'); await p.close();

  // ---------- actions: opening / idempotency / unit error ----------
  p = await open({}, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 400); ok(await p.locator('.s2-act').count() === 6, 'owner sees 6 actions'); await p.screenshot({ path: SP + '/st_actions.png' });
  await p.click('[data-act=s2_do][data-v=open]'); await wait(p, 300); await p.screenshot({ path: SP + '/st_open.png' }); await noOverflow(p, 'opening sheet');
  await p.click('#a_go'); await wait(p, 100); ok((await toastTxt(p)).includes('Choose an item'), 'item required toast'); ok((await calls(p, 'stock_opening')).length === 0, 'no call without item');
  await p.fill('#a_item', 'I-001 · সাদা মিষ্টি'); await p.dispatchEvent('#a_item', 'change'); ok(/Base unit: kg/.test(await p.textContent('#a_item_h')), 'base unit hint');
  await p.fill('#a_qty', '12.5'); await p.selectOption('#a_unit', 'box'); await p.fill('#a_cost', '180'); await p.fill('#a_note', 'start');
  await p.evaluate(() => { window.__M.fail.stock_opening = { msg: 'unit_unknown', once: true }; }); await p.click('#a_go'); await wait(p, 300);
  ok(/no conversion/.test(await toastTxt(p)), 'unit_unknown shown nicely'); ok(await p.locator('#a_go').isEnabled(), 'button re-enabled after error');
  await p.selectOption('#a_unit', ''); await p.click('#a_go'); await wait(p, 400);
  const op = await calls(p, 'stock_opening'); ok(op.length === 2, 'two attempts'); ok(op[0].p_client === op[1].p_client && /^[0-9a-f-]{36}$/.test(op[0].p_client), 'retry reuses the same client id (idempotent)');
  ok(op[1].p_item === 'i0' && op[1].p_loc === 1 && op[1].p_qty === 12.5 && op[1].p_unit === null && op[1].p_unit_cost === 180 && op[1].p_note === 'start', 'opening args');
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=open]'); await wait(p, 200); await p.fill('#a_item', 'I-002'); await p.fill('#a_qty', '1'); await p.click('#a_go'); await wait(p, 300);
  const op2 = await calls(p, 'stock_opening'); ok(op2[2].p_client !== op2[1].p_client, 'new sheet = new client id');
  // error messages
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=open]'); await wait(p, 200); await p.fill('#a_item', 'I-002'); await p.fill('#a_qty', '1');
  await p.evaluate(() => { window.__M.fail.stock_opening = { msg: 'opening_exists', once: true }; }); await p.click('#a_go'); await wait(p, 300); ok(/already set/.test(await toastTxt(p)), 'opening_exists text');
  await p.evaluate(() => { window.__M.fail.stock_opening = { msg: 'item_not_tracked', once: true }; }); await p.click('#a_go'); await wait(p, 300); ok(/tracking is off/.test(await toastTxt(p)), 'item_not_tracked text');
  await p.close();

  // ---------- wastage ----------
  p = await open({ photoAbove: 5 }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=waste]'); await wait(p, 300); await p.screenshot({ path: SP + '/st_waste.png' }); await noOverflow(p, 'wastage sheet');
  ok(await p.locator('#a_reason option:not([value^="__"])').count() === 4, 'reasons from the list (3 + blank)');
  ok(await p.locator('#a_reason option[value^="__"]').count() === 2, 'W3: wastage reasons also offer + Add new and Other (shared list control)');
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '2'); await p.click('#a_go'); await wait(p, 150); ok(/Choose a reason/.test(await toastTxt(p)), 'reason required');
  await p.selectOption('#a_reason', 'spoiled'); await p.fill('#a_qty', '9'); await p.click('#a_go'); await wait(p, 150); ok(/photo is needed/.test(await toastTxt(p)) && (await calls(p, 'stock_wastage')).length === 0, 'photo precheck above the rule limit');
  fs.writeFileSync(SP + '/pic.png', C.PNGBUF);
  await p.setInputFiles('#a_file', SP + '/pic.png'); await wait(p, 700);
  const up = await p.evaluate(() => window.__UP); ok(up.length === 1 && /^STOCK\/1\/[0-9a-f-]+\.jpg$/.test(up[0][0]) && up[0][0].length < 300, 'photo stored as <prefix>/<loc>/<id>.jpg path: ' + JSON.stringify(up[0] && up[0][0]));
  await p.click('#a_go'); await wait(p, 400); const wc = await calls(p, 'stock_wastage'); ok(wc.length === 1 && wc[0].p_photo === up[0][0] && wc[0].p_reason === 'spoiled' && wc[0].p_qty === 9 && wc[0].p_batch === null, 'wastage args with photo path');
  await p.close();
  p = await open({}, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=waste]'); await wait(p, 300);
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '2'); await p.selectOption('#a_reason', 'unknown'); await p.evaluate(() => { window.__M.fail.stock_wastage = { msg: 'photo_required', once: true }; }); await p.click('#a_go'); await wait(p, 300);
  ok(/photo is required/.test(await toastTxt(p)) && /photo is needed/.test(await p.textContent('#a_ph_h')), 'server photo_required shows hint'); await p.close();

  // ---------- count / issue / production / transfer ----------
  p = await open({}, '#/stock'); await p.click('.s2-row >> nth=0'); await wait(p, 400); await p.click('.sheet [data-act=s2_do][data-v=count]'); await wait(p, 300);
  ok((await p.inputValue('#a_item')).startsWith('I-001'), 'drill preselects item'); await p.fill('#a_qty', '2'); await p.click('#a_go'); await wait(p, 150); ok(/Write a note/.test(await toastTxt(p)) && (await calls(p, 'stock_count_adjust')).length === 0, 'count note required (client)');
  await p.fill('#a_note', 'shelf count'); await p.click('#a_go'); await wait(p, 400); const cc = await calls(p, 'stock_count_adjust'); ok(cc.length === 1 && cc[0].p_counted === 2 && cc[0].p_note === 'shelf count' && cc[0].p_item === 'i0' && cc[0].p_loc === 1, 'count args'); ok(/Difference -1\.5/.test(await toastTxt(p)), 'count shows difference');
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=issue]'); await wait(p, 300); await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '3'); await p.evaluate(() => { window.__M.fail.stock_issue = { msg: 'insufficient_stock', hint: 'on hand 1', once: true }; }); await p.click('#a_go'); await wait(p, 300);
  ok(/Not enough stock/.test(await toastTxt(p)) && /on hand 1/.test(await toastTxt(p)), 'insufficient stock text'); await p.click('#a_go'); await wait(p, 300); const is = await calls(p, 'stock_issue'); ok(is.length === 2 && is[0].p_client === is[1].p_client && is[1].p_qty === 3, 'issue retried with same client');
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=prod]'); await wait(p, 300); await p.screenshot({ path: SP + '/st_prod.png' }); await noOverflow(p, 'production sheet');
  await p.fill('#a_item', 'I-003'); await p.fill('#a_qty', '24'); await p.fill('#a_made', '2026-10-11T06:30'); await p.click('#a_go'); await wait(p, 300); const pr = await calls(p, 'stock_production_in'); ok(pr.length === 1 && pr[0].p_made_at === '2026-10-11T06:30:00+06:00' && pr[0].p_qty === 24, 'production made_at');
  await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=xfer]'); await wait(p, 300); await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '2'); await p.click('#a_go'); await wait(p, 150); ok(/Choose where/.test(await toastTxt(p)), 'destination required');
  await p.selectOption('#a_to', '2'); await p.click('#a_go'); await wait(p, 300); const tf = await calls(p, 'stock_transfer'); ok(tf.length === 1 && tf[0].p_from === 1 && tf[0].p_to === 2 && tf[0].p_item === 'i0', 'transfer args'); ok(await p.locator('#a_to option[value="1"]').count() === 0, 'to-location excludes from');
  await p.close();

  // ---------- reconcile (owner) ----------
  p = await open({ m: { recon: [{ item_id: 'i0', location_id: 1, ledger_qty: 3, cached_qty: 4, qty_diff: 1 }] } }, '#/stock'); await p.click('[data-act=s2_recon]'); await wait(p, 400);
  ok(/Mismatch: 1/.test(await p.textContent('.sheet')), 'reconcile mismatch'); await p.screenshot({ path: SP + '/st_recon.png' }); await p.click('[data-act=s2_fix]'); await wait(p, 300); const rf = await calls(p, 'stock_reconcile'); ok(rf.length === 2 && rf[0].p_fix === false && rf[1].p_fix === true, 'fix only on request'); await p.close();
  p = await open({}, '#/stock'); await p.click('[data-act=s2_recon]'); await wait(p, 300); ok(/matches/.test(await p.textContent('.sheet')), 'reconcile ok'); await p.close();
  const NO = 'window.__OWNER=false;window.__PERMS={};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};';
  p = await open({ init: NO, m: { grants: [], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock'); ok(await p.locator('[data-act=s2_recon]').count() === 0, 'no reconcile for non-owner');

  // ---------- permissions: lock mode ----------
  await p.click('[data-act=s2_actions]'); await wait(p, 400); ok(await p.locator('.s2-act').count() === 0 && await p.locator('.s2-lockrow').count() === 6, 'lock mode: 6 locked rows, no buttons'); await p.screenshot({ path: SP + '/st_lock.png' }); await p.close();
  p = await open({ init: NO, m: { grants: ['wastage_write_off'], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 400);
  ok(await p.locator('.s2-act').count() === 1 && await p.locator('.s2-lockrow').count() === 5, 'partial grants: 1 action + 5 locks'); await p.close();
  // hide mode
  p = await open({ hide: true, init: NO, m: { grants: ['wastage_write_off'], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 400);
  ok(await p.locator('.s2-act').count() === 1 && await p.locator('.s2-lockrow').count() === 0, 'hide mode: only allowed action'); await p.close();
  p = await open({ hide: true, init: NO, m: { grants: [], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock'); ok(await p.locator('[data-act=s2_actions]').count() === 0, 'hide mode with no grants: no actions button'); await p.close();
  // server "not allowed": toast (emergency off)
  p = await open({ init: NO, m: { grants: ['stock_issue'], ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/stock'); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=issue]'); await wait(p, 300);
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '1'); await p.evaluate(() => { window.__M.fail.stock_issue = { msg: 'not allowed', once: true }; }); await p.click('#a_go'); await wait(p, 400);
  ok(/Blocked|not allowed/i.test(await p.textContent('body')), 'not allowed handled (toast or emergency sheet)'); await p.close();

  // ---------- languages ----------
  for (const lang of ['bn', 'mix']) { p = await open({ lang }, '#/stock'); await p.screenshot({ path: SP + `/st_${lang}.png` }); await noOverflow(p, lang); await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.screenshot({ path: SP + `/st_actions_${lang}.png` }); await p.close(); }

  // ---------- exceptions labels + home tiles + drawer ----------
  p = await open({}, '#/exceptions'); await p.evaluate(() => { window.__DATA.tables.exceptions = [{ id: 1, status: 'open', level: 'yellow', flag_code: 'transit_short', text: { bn: 'পথে কম', en: 'short' }, entry_date: '2026-10-10', location_id: 1, amount: null, form_code: 'STOCK', entry_id: null }]; });
  await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 200); await p.evaluate(() => { location.hash = '#/exceptions'; }); await wait(p, 600);
  ok(/Short in transit/.test(await p.textContent('#ex_body')), 'exception flag label'); await p.screenshot({ path: SP + '/st_exc.png' }); await p.close();
  p = await open({}, '#/home'); await p.click('[data-act=hv_mode][data-v=acc]'); await wait(p, 300);
  ok(await p.locator('#hv_tiles [data-act=go][data-v=payables]').count() === 1, 'Supplier payables tile is a real link'); await p.click('[data-act=hv_mode][data-v=biz]'); await wait(p, 300); ok(await p.locator('#hv_tiles [data-act=go][data-v=stock]').count() === 1, 'Stock balance tile is a real link');
  await p.click('#hv_tiles [data-v=stock]'); await wait(p, 800); ok((await p.evaluate(() => location.hash)) === '#/stock', 'tile navigates to #/stock');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 500); const gl = await p.locator('.dr-g .gl').allTextContents(); ok(gl.some((x) => /Suppliers/.test(x)) && gl.some((x) => /Purchas/.test(x)) && gl.some((x) => /Stock/.test(x)), 'drawer groups: ' + gl.join('|'));
  await p.click('.dr-g[data-v=stock]'); await p.click('.dr-g[data-v=purch]'); await wait(p, 200); await p.screenshot({ path: SP + '/st_drawer.png' });
  ok(await p.locator('.dr-it[data-v=stock]').count() === 1 && await p.locator('.dr-it[data-v=payables]').count() === 1, 'drawer entries'); await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
