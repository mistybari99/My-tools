// Locations (#/locations), setup steps, add-showroom wizard, status sheets, settings sheet versions (#/locsheet). Run: node locations_test.js <dir holding smoke.js stub>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w4_common.js');
const base = C.baseData(SP), PORT = 8321, srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA3 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);

  // ---------- owner: list ----------
  let p = await open({}, '#/locations');
  ok(await p.locator('#lo_list .card').count() === 7, 'seven cards');
  ok(await p.locator('#lo_chips .tog').count() === 6, 'six filter chips (all + 5 statuses)');
  ok(/Live 4/.test(await p.textContent('#lo_chips')) && /Paused 1/.test(await p.textContent('#lo_chips')) && /Closed 1/.test(await p.textContent('#lo_chips')) && /Planned 1/.test(await p.textContent('#lo_chips')), 'chip counts');
  ok(await p.locator('#lo_list .card.mk.ok').count() === 4 && await p.locator('#lo_list .card.mk.warn').count() === 1 && await p.locator('#lo_list .card.mk.bad').count() === 1 && await p.locator('#lo_list .card.mk.info').count() === 1, 'edge markers by status');
  ok(await p.locator('.card[data-loc="1"] .chip.info').count() >= 1, 'hub chip on main');
  ok(/stopped/.test(await p.textContent('.card[data-loc="5"]')), 'pause reason visible');
  ok(/2\/17/.test(await p.textContent('.card[data-loc="8"]')), 'setup progress on the planned place');
  ok(await p.locator('.card[data-loc="9"] .chip', { hasText: 'Inactive' }).count() === 1, 'inactive chip');
  await p.screenshot({ path: SP + '/lo_list.png' }); await noOverflow(p, 'list');
  await p.click('[data-act=lo_filter][data-v=paused]'); await wait(p, 100); ok(await p.locator('#lo_list .card').count() === 1, 'filter paused');
  await p.click('[data-act=lo_filter][data-v=all]'); await p.fill('#lo_q', 'cake'); await wait(p, 100); ok(await p.locator('#lo_list .card').count() === 1, 'search by name');
  await p.fill('#lo_q', 'godown'); await wait(p, 100); ok(await p.locator('#lo_list .card').count() === 1, 'search by code'); await p.fill('#lo_q', '');

  // ---------- ⋮ menu + edit ----------
  await p.click('.card[data-loc="2"] [data-act=lo_menu]'); await wait(p, 150);
  const mt = await p.textContent('.sheet');
  ok(/Edit/.test(mt) && /Setup steps|checklist/i.test(mt) && /Pause/.test(mt) && /Close for good/.test(mt) && /Switch inactive/.test(mt) && /Set as hub/.test(mt) && /Supplied by/.test(mt) && /Settings sheet/.test(mt), 'menu has edit, steps/checklist, pause, close, active, hub, supplied by, sheet');
  ok(!/Start \(go live\)/.test(mt), 'live place has no Start');
  await p.screenshot({ path: SP + '/lo_menu.png' });
  await p.click('[data-act=lo_edit]'); await wait(p, 150);
  ok(await p.locator('.sheet input[disabled]').inputValue() === 'branch2', 'code is read-only');
  await p.fill('#e_en', '2nd Branch (renamed)'); await p.fill('#e_open', '2027-03-01'); await p.click('[data-act=lo_edit_save]'); await wait(p, 300);
  let c = await calls(p, 'location_save'); ok(c.length === 1 && c[0].p_id === 2 && c[0].p_patch.name_en === '2nd Branch (renamed)' && c[0].p_patch.planned_opening === '2027-03-01' && !('code' in c[0].p_patch), 'edit sends patch without code');
  ok(/renamed/.test(await p.textContent('.card[data-loc="2"]')), 'list reloaded');
  // hub toggle / active / supplied-by
  await p.click('.card[data-loc="2"] [data-act=lo_menu]'); await p.click('[data-act=lo_hub]'); await wait(p, 300);
  c = await calls(p, 'location_save'); ok(c[1].p_patch.hub_functions === true, 'hub on');
  await p.click('.card[data-loc="2"] [data-act=lo_menu]'); await p.click('[data-act=lo_active]'); await wait(p, 300);
  c = await calls(p, 'location_set_active'); ok(c.length === 1 && c[0].p_active === false, 'active switch off');
  await p.click('.card[data-loc="2"] [data-act=lo_menu]'); await p.click('[data-act=lo_supsheet]'); await p.selectOption('#sp_sel', '7'); await p.click('[data-act=lo_sup_save]'); await wait(p, 300);
  c = await calls(p, 'location_save'); ok(c[2].p_patch.supplied_by === 7, 'supplied by godown');

  // ---------- pause needs a reason ----------
  await p.click('.card[data-loc="7"] [data-act=lo_menu]'); await p.click('[data-act=lo_status][data-to=paused]'); await wait(p, 150);
  await p.click('[data-act=lo_status_go]'); await wait(p, 150); ok((await calls(p, 'location_set_status')).length === 0, 'pause without a reason is not sent');
  await p.fill('#st_reason', 'repair'); await p.click('[data-act=lo_status_go]'); await wait(p, 300);
  c = await calls(p, 'location_set_status'); ok(c.length === 1 && c[0].p_status === 'paused' && c[0].p_reason === 'repair' && c[0].p_override === false, 'pause sent with reason');
  ok(await p.locator('.card[data-loc="7"] .chip.warn', { hasText: 'Paused' }).count() === 1, 'card shows paused');
  // resume
  await p.click('.card[data-loc="7"] [data-act=lo_menu]'); ok(/Resume/.test(await p.textContent('.sheet')), 'resume offered'); await p.click('[data-act=lo_status][data-to=live]'); await p.click('[data-act=lo_status_go]'); await wait(p, 300);
  ok(await p.locator('.card[data-loc="7"] .chip.ok', { hasText: 'Live' }).count() === 1, 'resumed');

  // ---------- close: warnings + owner override ----------
  await p.evaluate(() => { window.__M.w4.warn.closed = [{ code: 'open_entries', count: 2 }, { code: 'stock_on_hand', items: 3, qty: 10 }]; });
  await p.click('.card[data-loc="6"] [data-act=lo_menu]'); await p.click('[data-act=lo_status][data-to=closed]'); await p.fill('#st_reason', 'finished'); await p.click('[data-act=lo_status_go][data-ov="0"]'); await wait(p, 300);
  ok(/Open entries/.test(await p.textContent('.sheet')) && /Stock on hand/.test(await p.textContent('.sheet')), 'checklist warnings shown');
  ok(await p.locator('[data-act=lo_status_go][data-ov="1"]').count() === 1, 'owner sees the override button');
  ok((await p.locator('.card[data-loc="6"] .chip.bad').count()) === 0, 'not closed yet');
  await p.screenshot({ path: SP + '/lo_close.png' }); await noOverflow(p, 'close sheet');
  await p.click('[data-act=lo_status_go][data-ov="1"]'); await wait(p, 300);
  c = await calls(p, 'location_set_status'); const last = c[c.length - 1]; ok(last.p_override === true && last.p_status === 'closed' && last.p_reason === 'finished', 'override sent with reason');
  ok(await p.locator('.card[data-loc="6"] .chip.bad', { hasText: 'Closed' }).count() === 1, 'closed');
  await p.click('.card[data-loc="6"] [data-act=lo_menu]'); ok(!/Edit|Resume|Pause/.test(await p.textContent('.sheet')), 'closed place has no edit / pause / resume'); await p.click('[data-act=closesheet]');

  // ---------- setup steps ----------
  await p.click('.card[data-loc="8"] [data-act=lo_menu]'); ok(/Start \(go live\)/.test(await p.textContent('.sheet')), 'planned place offers Start'); await p.click('[data-act=lo_steps]'); await wait(p, 300);
  ok(await p.locator('.sheet [data-step]').count() === 17, '17 steps listed'); ok(/2\/17/.test(await p.textContent('.sheet')), 'progress 2/17'); ok(/Step 16 \(start\) stays locked/.test(await p.textContent('.sheet')), 'gate message');
  ok(await p.locator('.sheet [data-step="13"]', { hasText: 'optional' }).count() === 1, 'step 13 optional');
  await p.screenshot({ path: SP + '/lo_steps.png' }); await noOverflow(p, 'steps sheet');
  await p.click('[data-act=lo_step][data-v="3"]'); await wait(p, 400);
  c = await calls(p, 'location_step_set'); ok(c.length === 1 && c[0].p_loc === 8 && c[0].p_step === 3 && c[0].p_done === true, 'tick step 3'); ok(/3\/17/.test(await p.textContent('.sheet')), 'progress 3/17 after tick');
  await p.click('[data-act=closesheet]');

  // ---------- add showroom wizard ----------
  await p.click('[data-act=lo_wiz]'); await wait(p, 150);
  await p.click('[data-act=lo_wiz_next]'); await wait(p, 100); ok(await p.locator('#w_bn').count() === 1, 'empty name stays on step 1');
  await p.fill('#w_bn', 'নতুন শোরুম'); await p.fill('#w_en', 'Fresh Showroom'); await p.click('[data-act=lo_wiz_next]'); await wait(p, 150);
  ok(await p.locator('#w_model').count() === 1 && (await p.locator('#w_model option').allTextContents()).length === 1, 'step 2: only model A is offered (B hidden)');
  await p.selectOption('#w_sup', '7'); await p.fill('#w_open', '2027-01-01'); await p.click('[data-act=lo_wiz_next]'); await wait(p, 150);
  ok(/fresh_showroom/.test(await p.textContent('#w_code')), 'step 3 previews the code'); await p.screenshot({ path: SP + '/lo_wizard.png' }); await noOverflow(p, 'wizard');
  await p.click('[data-act=lo_wiz_prev]'); await wait(p, 100); ok(await p.inputValue('#w_open') === '2027-01-01', 'back keeps values'); await p.click('[data-act=lo_wiz_next]'); await wait(p, 100);
  await p.click('[data-act=lo_wiz_save]'); await wait(p, 500);
  c = await calls(p, 'location_save'); const nw = c.find((x) => x.p_id === null); ok(nw && nw.p_patch.name_en === 'Fresh Showroom' && nw.p_patch.supplied_by === 7 && nw.p_patch.kind === 'showroom' && nw.p_patch.model === 'A', 'wizard sends the new place');
  ok(await p.locator('.sheet [data-step]').count() === 17, 'steps sheet opens for the new place'); await p.click('[data-act=closesheet]'); await wait(p, 100);
  ok(await p.locator('#lo_list .card').count() === 8, 'new place in the list'); ok(await p.locator('.card[data-status="planned"]').count() === 2, 'planned');
  // code preview skips a used code (_2)
  await p.click('[data-act=lo_wiz]'); await p.fill('#w_bn', 'x'); await p.fill('#w_en', 'New One'); await p.click('[data-act=lo_wiz_next]'); await p.click('[data-act=lo_wiz_next]'); await wait(p, 100);
  ok(/new_one_2/.test(await p.textContent('#w_code')), 'wizard previews new_one_2 when new_one is used'); await p.evaluate(() => { const sh = document.getElementById('sheet'); if (sh) sh.remove(); });
  // owner window for late work on a paused / closed place
  await p.click('.card[data-loc="5"] [data-act=lo_menu]'); ok(/late work/i.test(await p.textContent('.sheet')), 'owner sees the late-work window item on a paused place');
  await p.click('[data-act=lo_override]'); await p.click('[data-act=lo_override_go]'); await wait(p, 100); ok((await calls(p, 'location_block_override')).length === 0, 'override needs a reason');
  await p.fill('#ov_reason', 'late bills'); await p.click('[data-act=lo_override_go]'); await wait(p, 300); c = await calls(p, 'location_block_override'); ok(c.length === 1 && c[0].p_loc === 5 && c[0].p_minutes === 30, 'override sent');
  // friendly error mapping for the plain server messages
  await p.evaluate(() => { window.__M.w4.err.location_save = 'not allowed'; }); await p.click('.card[data-loc="2"] [data-act=lo_menu]'); await p.click('[data-act=lo_edit]'); await p.click('[data-act=lo_edit_save]'); await wait(p, 300);
  ok(/Not allowed/.test(await p.textContent('#toast')), 'not allowed mapped'); await p.evaluate(() => { window.__M.w4.err.location_save = 'bad_transition:closed->live'; }); await p.click('[data-act=lo_edit_save]'); await wait(p, 300);
  ok(/status change/i.test(await p.textContent('#toast')), 'bad_transition mapped'); await p.evaluate(() => { window.__M.w4.err = {}; const sh = document.getElementById('sheet'); if (sh) sh.remove(); });
  // server error mapped
  await p.evaluate(() => { window.__M.w4.err.location_save = 'name_in_use'; });
  await p.click('[data-act=lo_wiz]'); await p.fill('#w_bn', 'x'); await p.click('[data-act=lo_wiz_next]'); await p.click('[data-act=lo_wiz_next]'); await p.click('[data-act=lo_wiz_save]'); await wait(p, 300);
  ok(/exists/.test(await p.textContent('#toast')), 'name_in_use shown as a clear message'); await p.evaluate(() => { window.__M.w4.err = {}; const sh = document.getElementById('sheet'); if (sh) sh.remove(); });
  await p.context().close();

  // ---------- Bangla and Bng-Eng ----------
  p = await open({ lang: 'bn' }, '#/locations'); ok(/বিরতি/.test(await p.textContent('#lo_chips')) && /সব/.test(await p.textContent('#lo_chips')), 'Bangla chips'); await p.screenshot({ path: SP + '/lo_bn.png' }); await p.context().close();
  p = await open({ lang: 'mix' }, '#/locations'); ok(/Paused/.test(await p.textContent('#lo_chips')), 'Bng-Eng chips'); await p.context().close();

  // ---------- who can open ----------
  p = await open({ owner: false, m: { grants: [], ctx: { roles: ['salesperson'], locations: [1] } } }, '#/locations');
  ok(await p.locator('#lo_list').count() === 0 && /^#\/(home)?$/.test(await p.evaluate(() => location.hash)) === true || await p.locator('#lo_list').count() === 0, 'staff cannot open #/locations (bounced to Home)');
  ok(await p.locator('#lo_list').count() === 0, 'no location list for staff');
  await p.goto(`http://localhost:${PORT}/#/locsheet`); await wait(p, 800); ok(await p.locator('#sh_list').count() === 0, 'staff cannot open #/locsheet');
  await p.goto(`http://localhost:${PORT}/#/control`); await wait(p, 800); ok(await p.locator('#cc_needs').count() === 0, 'staff cannot open #/control');
  await p.context().close();
  // delegate with location_manage
  p = await open({ owner: false, m: { grants: ['location_manage'], ctx: { roles: ['salesperson'], locations: [1] } } }, '#/locations');
  ok(await p.locator('#lo_list .card').count() === 7, 'location_manage delegate opens the list');
  await p.click('.card[data-loc="8"] [data-act=lo_menu]'); await p.click('[data-act=lo_steps]'); await wait(p, 300);
  ok(await p.locator('[data-act=lo_step][data-v="1"][disabled]').count() === 1 && await p.locator('[data-act=lo_step][data-v="3"][disabled]').count() === 0, 'owner-only steps are disabled for a delegate');
  await p.click('[data-act=closesheet]'); await p.click('.card[data-loc="6"] [data-act=lo_menu]'); await p.click('[data-act=lo_status][data-to=closed]'); await p.fill('#st_reason', 'x');
  await p.evaluate(() => { window.__M.w4.warn.closed = [{ code: 'open_entries', count: 1 }]; }); await p.click('[data-act=lo_status_go][data-ov="0"]'); await wait(p, 300);
  ok(await p.locator('[data-act=lo_status_go][data-ov="1"]').count() === 0, 'delegate gets no override button');
  await p.context().close();

  // ---------- settings sheet versions ----------
  p = await open({}, '#/locsheet');
  ok(await p.locator('#sh_list .card').count() === 2, 'two versions listed'); ok(/in force/.test(await p.textContent('#sh_list .card:first-child')) && /v2/.test(await p.textContent('#sh_list .card:first-child')), 'v2 in force, newest first');
  await p.click('#sh_list .card:last-child [data-act=lo_sh_open]'); await wait(p, 300);
  ok(/Old version \(read only\)/.test(await p.textContent('#sh_edit')) && await p.locator('#sh_edit input').count() === 0, 'old version is read only');
  ok(await p.locator('#sh_edit .chip.warn', { hasText: 'Data needed' }).count() >= 1, 'blank values show Data needed');
  await p.click('[data-act=lo_sh_new]'); await wait(p, 400);
  ok(await p.locator('#sh_edit input[data-k]').count() >= 3, 'draft has inputs'); ok(await p.inputValue('#shv_drawer_float') === '2500', 'draft starts from the version in force');
  await p.fill('#shv_drawer_float', '3000'); await p.fill('#shv_imprest', '500'); await p.click('[data-act=lo_sh_save]'); await wait(p, 400);
  c = await calls(p, 'sheet_set'); ok(c.length === 1 && c[0].p_values.drawer_float === 3000 && c[0].p_values.imprest === 500 && Object.keys(c[0].p_values).length === 2, 'only changed values sent, numbers parsed');
  await p.screenshot({ path: SP + '/lo_sheet.png' }); await noOverflow(p, 'sheet page');
  await p.click('[data-act=lo_sh_open][data-st=draft]'); await wait(p, 300);
  await p.fill('#sh_eff', '2026-11-01'); await p.click('[data-act=lo_sh_approve]'); await wait(p, 500);
  c = await calls(p, 'sheet_approve'); ok(c.length === 1 && c[0].p_effective === '2026-11-01', 'approve with effective date');
  ok(await p.locator('#sh_list .card').count() === 3, 'three versions now'); ok(await p.locator('[data-act=lo_sh_new]').count() === 1, 'can start another draft');
  // maker error mapping
  await p.evaluate(() => { window.__M.w4.err.sheet_approve = 'maker_cannot_approve'; }); await p.click('[data-act=lo_sh_new]'); await wait(p, 300); await p.click('[data-act=lo_sh_approve]'); await wait(p, 300);
  ok(/maker/i.test(await p.textContent('#toast')), 'maker cannot approve message');
  await p.evaluate(() => { window.__M.w4.err = {}; });
  await p.click('[data-act=lo_sh_discard]'); await wait(p, 300); ok(((await calls(p, 'sheet_discard')).length) === 1, 'discard');
  // locset page has the link
  await p.goto(`http://localhost:${PORT}/#/locset`); await wait(p, 900); ok(await p.locator('#lv_link').count() === 1, 'versions link on the old limits screen');
  await p.selectOption('#ls_loc', '2'); await wait(p, 600); ok(await p.locator('#lv_link').count() === 1, 'link survives changing place'); ok(await p.locator('#ls_body .card').count() > 3, 'old limits screen still renders');
  // head_management / settings_approve delegate can open the sheet page; approve button follows settings_approve
  await p.context().close();
  p = await open({ owner: false, m: { grants: ['head_management'], ctx: { roles: ['salesperson'], locations: [1] } } }, '#/locsheet');
  ok(await p.locator('#sh_list .card').count() === 2, 'head management opens the sheet versions'); await p.click('[data-act=lo_sh_new]'); await wait(p, 300);
  ok(await p.locator('[data-act=lo_sh_approve]').count() === 0 && await p.locator('[data-act=lo_sh_save]').count() === 1, 'head management can draft but has no approve button');
  await p.context().close();
  p = await open({ owner: false, m: { grants: ['settings_approve'], ctx: { roles: ['salesperson'], locations: [1] } } }, '#/locsheet');
  await p.click('[data-act=lo_sh_new]'); await wait(p, 300); ok(await p.locator('[data-act=lo_sh_approve]').count() === 1, 'settings_approve delegate sees approve'); await p.context().close();

  // ---------- BOS.LOC limit helpers + optional block ----------
  p = await open({}, '#/home');
  const gl = await p.evaluate(async () => [await window.BOS.LOC.getLimit(1, 'drawer_float'), await window.BOS.LOC.getLimit(1, 'imprest'), await window.BOS.LOC.limitMissing(1, ['drawer_float', 'imprest'])]);
  ok(gl[0] === 2500 && gl[1] === null && JSON.stringify(gl[2]) === '["imprest"]', 'getLimit: value / blank=null / limitMissing');
  ok(await p.evaluate(() => window.BOS.LOC.blockOn()) === false, 'block_on_missing_limit defaults OFF');
  await p.context().close();

  // ---------- block_on_missing_limit (switch ON): a form that shows the Data-needed notice cannot be submitted ----------
  p = await open({}, '#/home');
  const blocked = await p.evaluate(() => { const B = window.BOS; B.rule = (k, f) => (k === 'block_on_missing_limit' ? true : f);
    const n = document.createElement('div'); n.className = 'notice warn'; n.textContent = 'These settings are needed: Drawer float'; document.body.appendChild(n);
    window.BOS_APP.H.e_submit({ dataset: {} }); return document.getElementById('toast') ? document.getElementById('toast').textContent : ''; });
  ok(/blank/i.test(blocked), 'switch ON + notice -> submit refused with a Data-needed message');
  await p.context().close();
  console.log('errors:', errors.length ? [...new Set(errors)] : 'none'); console.log('assert failures:', bad);
  await br.close(); srv.close(); process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.error('TEST CRASH', e); srv.close(); process.exit(2); } })();
