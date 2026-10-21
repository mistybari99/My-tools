// W5a: rollout board (#/rollout), entered-later in a real form (11-1), change request + revision history (entry menu), change requests inbox (#/changes).
// Run: node rollout_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS=' + JSON.stringify(o.perms || {}) + ';' : ''}try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const nForms = base.tables.forms.filter((f) => /^\d{1,2}-\d+$/.test(f.code) && f.code !== '0-1').length;

  // ---------- board ----------
  let p = await open({}, '#/rollout');
  ok(await p.locator('#ro_list .card').count() === nForms, 'one card per form (' + nForms + ')');
  ok(/App \d+/.test(await p.textContent('#ro_sum')) && /Paper 0/.test(await p.textContent('#ro_sum')) && /Parallel 0/.test(await p.textContent('#ro_sum')), 'summary: everything starts on App');
  ok(await p.locator('.card[data-form="11-1"] .chip').count() === 3, 'three active places as chips (closed place hidden)');
  ok(/App/.test(await p.textContent('.card[data-form="11-1"]')), 'chip says App');
  ok(await p.locator('#ro_sw .tog').count() === 4, 'four switches for the owner');
  await p.screenshot({ path: SP + '/ro_board.png' }); await noOverflow(p, 'board');
  // one cell -> Paper
  await p.click('.card[data-form="11-1"] [data-act=ro_cell][data-l="1"]'); await wait(p, 150);
  ok(/Paper/.test(await p.textContent('.sheet')) && /Parallel/.test(await p.textContent('.sheet')) && /App/.test(await p.textContent('.sheet')), 'cell sheet offers the three states');
  await p.fill('#ro_note', 'paper books for the audit'); await p.click('.sheet [data-act=ro_apply][data-m=paper]'); await wait(p, 300);
  let c = await calls(p, 'rollout_set'); ok(c.length === 1 && c[0].p_form === '11-1' && c[0].p_loc === 1 && c[0].p_mode === 'paper' && c[0].p_note === 'paper books for the audit', 'rollout_set sent');
  ok(/Paper/.test(await p.textContent('.card[data-form="11-1"] [data-l="1"]')) && /Paper 1/.test(await p.textContent('#ro_sum')), 'chip and summary follow');
  ok(await p.locator('.card[data-form="11-1"].mk.warn').count() === 1, 'edge marker warns for a form with a Paper place');
  // ⋮ menu: all places parallel
  await p.click('.card[data-form="11-1"] [data-act=ro_menu]'); await wait(p, 150);
  ok(/Set all places to/.test(await p.textContent('.sheet')) && /Open the form list/.test(await p.textContent('.sheet')), 'menu has set-all, form list');
  await p.click('.sheet [data-act=ro_apply_all][data-m=parallel]'); await wait(p, 300);
  c = await calls(p, 'rollout_set_many'); ok(c.length === 1 && JSON.stringify(c[0].p_forms) === '["11-1"]' && c[0].p_locs === null && c[0].p_mode === 'parallel', 'set all places of one form');
  ok((await p.locator('.card[data-form="11-1"] .chip.info').count()) === 3, 'three parallel chips');
  // filter + search
  await p.click('[data-act=ro_filter][data-v=parallel]'); await wait(p, 100); ok(await p.locator('#ro_list .card').count() === 1, 'filter Parallel shows one form');
  await p.click('[data-act=ro_filter][data-v=all]'); await p.fill('#ro_q', '06-1'); await wait(p, 100); ok(await p.locator('#ro_list .card').count() === 1, 'search by code');
  // bulk: paper needs the confirmation
  await p.click('[data-act=ro_bulk]'); await wait(p, 150);
  await p.click('#bk_paper'); await wait(p, 100); ok(await p.locator('#bk_ack_row:visible').count() === 1, 'Paper asks for a confirmation');
  await p.selectOption('#bk_forms', 'shown'); await p.uncheck('.bk_l[value="3"]');
  await p.click('[data-act=bk_go]'); await wait(p, 200); ok((await calls(p, 'rollout_set_many')).length === 1, 'not sent without the tick');
  await p.check('#bk_ack'); await p.fill('#ro_note', 'audit week'); await p.click('[data-act=bk_go]'); await wait(p, 400);
  c = await calls(p, 'rollout_set_many'); ok(c.length === 2 && JSON.stringify(c[1].p_forms) === '["06-1"]' && JSON.stringify(c[1].p_locs) === '[1,2]' && c[1].p_mode === 'paper' && c[1].p_note === 'audit week', 'bulk: shown forms x selected places');
  // switches
  await p.fill('#ro_q', ''); await p.dispatchEvent('#ro_q', 'input'); await wait(p, 100);
  await p.click('#ro_sw [data-v=rollout_enforce]'); await wait(p, 300);
  c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'rollout_enforce' && c[0].p_value === false, 'switch sends set_rule false');
  ok(/Off/.test(await p.textContent('#ro_sw [data-v=rollout_enforce]')), 'switch shows Off');
  await p.click('#ro_sw [data-v=owner_self_approve]'); await wait(p, 200);
  ok(/Switch off owner self-approval/.test(await p.textContent('.sheet')) && (await calls(p, 'owner_self_approve_set')).length === 0, 'switching self-approval OFF asks for a confirmation first');
  await p.click('.sheet [data-act=ro_sw_off_go]'); await wait(p, 300);
  c = await calls(p, 'owner_self_approve_set'); ok(c.length === 1 && c[0].p_on === false, 'guarded RPC owner_self_approve_set(false) is used, not set_rule');
  ok(!(await calls(p, 'set_rule')).some((x) => x.p_key === 'owner_self_approve'), 'set_rule is not used for it');
  await p.click('#ro_sw [data-v=owner_self_approve]'); await wait(p, 300);
  c = await calls(p, 'owner_self_approve_set'); ok(c.length === 2 && c[1].p_on === true, 'switching back ON needs no confirmation');
  await p.context().close();
  // place filter shows one chip per form
  p = await open({}, '#/rollout');
  await p.selectOption('#ro_loc', '2'); await wait(p, 200); ok(await p.locator('.card[data-form="11-1"] .chip').count() === 1, 'place filter: one chip');
  await p.context().close();
  // no right -> nothing; delegate with the grant -> board (no switches)
  p = await open({ owner: false, m: { grants: [] } }, '#/rollout'); ok(/cannot open/.test(await p.textContent('#app')) || (await p.locator('#ro_list').count()) === 0, 'a plain person cannot open the board'); await p.context().close();
  p = await open({ owner: false, m: { grants: ['rollout_manage'] } }, '#/rollout'); ok(await p.locator('#ro_list .card').count() === nForms && await p.locator('#ro_sw').count() === 0, 'delegate with rollout_manage sees the board, no owner switches'); await p.context().close();

  // ---------- entered later in a real form (11-1) ----------
  p = await open({ cells: [['11-1', 1, 'parallel']] }, '#/entry/new/10-2/1');
  ok(/Paper is the record this month/.test(await p.textContent('#entry')) && /Parallel/.test(await p.textContent('#entry')), 'parallel banner + chip');
  ok(await p.locator('#el_on').count() === 1 && await p.locator('[data-p="paper_no"]').count() === 1, 'toggle is there; the old printed-number field is there while off');
  await p.check('#el_on'); await wait(p, 200);
  ok(await p.locator('#el_ps').count() === 1 && await p.locator('#el_at').count() === 1, 'paper serial and original time inputs appear');
  ok(await p.locator('[data-p="paper_no"]').count() === 0, 'old printed-number field is replaced while entered-later is on');
  ok(await p.locator('#e_later_chip').count() === 1 && /Entered later/.test(await p.textContent('#e_later_chip')), 'distinct chip');
  ok(await p.locator('#e_date').count() === 0, 'the date follows the original time');
  await p.fill('[data-p="lines.0.amount"]', '120'); await p.selectOption('[data-p="lines.0.head"]', 'staff_meal');
  await p.click('[data-act=e_save]'); await wait(p, 300);
  ok((await calls(p, 'save_entry')).length === 0, 'cannot save without the paper serial and time (client check)');
  await p.fill('#el_ps', 'A-0150'); await p.fill('#el_at', '2026-10-03T22:30'); await p.dispatchEvent('#el_at', 'change'); await wait(p, 200);
  await p.fill('[data-p="lines.0.amount"]', '120');
  await p.click('[data-act=e_save]'); await wait(p, 400);
  c = await calls(p, 'save_entry');
  ok(c.length === 1 && c[0].p_meta && c[0].p_meta.entered_later === true && c[0].p_meta.paper_serial === 'A-0150' && c[0].p_meta.paper_at === '2026-10-03T22:30:00+06:00' && /^[0-9a-f-]{36}$/.test(c[0].p_meta.client_id), 'save_entry carries entered_later, serial, original time (+06:00) and a client id');
  ok(c[0].p_date === '2026-10-03' && c[0].p_data.paper_no === 'A-0150', 'date is the original date; serial mirrored to data.paper_no');
  await p.screenshot({ path: SP + '/ro_later.png', fullPage: true });
  await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 300); await p.evaluate(() => { location.hash = '#/entry/e1'; }); await wait(p, 900);
  ok(await p.locator('#e_later_chip').count() === 1 && (await p.inputValue('#el_ps')) === 'A-0150' && (await p.inputValue('#el_at')) === '2026-10-03T22:30', 'reopened from the server: still entered-later with its serial and original time');
  await p.context().close();
  // Paper mode: opens with the toggle on, banner says so
  p = await open({ cells: [['11-1', 1, 'paper']] }, '#/entry/new/10-2/1');
  ok(await p.locator('#el_on:checked').count() === 1 && /on paper here/.test(await p.textContent('#entry')), 'Paper: entered-later is on by default with the banner');
  await p.context().close();
  // switched off: no toggle on a normal form
  p = await open({ laterOff: true }, '#/entry/new/10-2/1');
  ok(await p.locator('#el_on').count() === 0, 'entered_later_on OFF: no toggle'); await p.context().close();
  // a normal app entry sends no entered_later
  p = await open({}, '#/entry/new/10-2/1'); await p.fill('[data-p="lines.0.amount"]', '50'); await p.click('[data-act=e_save]'); await wait(p, 300);
  c = await calls(p, 'save_entry'); ok(c.length === 1 && c[0].p_meta && !('entered_later' in c[0].p_meta) && c[0].p_meta.client_id, 'plain entry: only a client id in the meta'); await p.context().close();

  // ---------- locked entry: request change + revision history ----------
  const ent = { id: 'a1', form_code: '11-1', location_id: 1, serial: 7, entry_date: '2026-10-05', status: 'approved', data: { lines: [{ amount: '100', head: 'staff_meal', receipt: 'yes' }], cash_now: '500', receipts_total: '100', drawer_untouched: true }, flags: [], check_data: {}, created_by: 'u2', created_staff: 'testf02', rev_no: 2, entered_later: false };
  const revs = [{ rev_no: 2, current: true, data: { lines: [{ amount: '100' }] }, at: '2026-10-06T10:00:00Z', changed_staff: null, approved_staff: 'owner1', reason: null },
    { rev_no: 1, current: false, data: { lines: [{ amount: '90' }] }, at: '2026-10-06T10:00:00Z', changed_staff: 'testf02', approved_staff: 'owner1', reason: 'typo in amount' }];
  p = await open({ entries: [ent], w: { revs } }, '#/entry/a1');
  ok(await p.locator('#e_rev_chip').count() === 1, 'revision chip on a revised entry');
  ok(await p.locator('[data-act=e_save]').count() === 0, 'locked: no save button');
  await p.click('[data-act=e_menu]'); await wait(p, 150);
  ok(/Request change/.test(await p.textContent('.sheet')) && /Revision history/.test(await p.textContent('.sheet')) && /Reopen \(owner\)/.test(await p.textContent('.sheet')), 'menu: request change, history, owner reopen');
  await p.click('.sheet [data-act=e_rev]'); await wait(p, 300);
  ok(await p.locator('#rev_list [data-rev]').count() === 2 && /typo in amount/.test(await p.textContent('#rev_list')) && /90 → 100/.test(await p.textContent('#rev_list')), 'revision sheet lists both versions with the difference');
  await p.screenshot({ path: SP + '/ro_revs.png' }); await p.click('.sheet [data-act=closesheet]'); await wait(p, 100);
  await p.click('[data-act=e_menu]'); await p.click('.sheet [data-act=e_chg_start]'); await wait(p, 300);
  ok(await p.locator('[data-act=e_chg_send]').count() === 1 && await p.locator('[data-p="lines.0.amount"]:not([disabled])').count() === 1, 'change mode: fields editable, send button');
  await p.fill('[data-p="lines.0.amount"]', '150'); await p.click('[data-act=e_chg_send]'); await wait(p, 200);
  await p.fill('#note_in', 'amount typed wrong'); await p.click('[data-act=note_ok]'); await wait(p, 500);
  c = await calls(p, 'entry_change_request');
  ok(c.length === 1 && c[0].p_entry === 'a1' && c[0].p_reason === 'amount typed wrong' && c[0].p_patch.data.lines[0].amount === '150' && Array.isArray(c[0].p_patch.flags), 'entry_change_request sent with the new data and the reason');
  ok(await p.locator('[data-act=e_chg_send]').count() === 0 && /Change requested/.test(await p.textContent('#entry')), 'back to read-only with a “Change requested” chip');
  ok((await p.evaluate(() => window.__DATA.tables.entries[0].status + window.__DATA.tables.entries[0].rev_no)) === 'approved2', 'the locked entry keeps its status and revision until the request is decided');
  await p.click('[data-act=e_menu]'); ok(!/Request change/.test(await p.textContent('.sheet')), 'no second request while one is waiting'); await p.context().close();
  // draft/not locked: no request item
  p = await open({ entries: [{ ...ent, id: 'd1', status: 'draft', rev_no: 1 }] }, '#/entry/d1'); await p.click('[data-act=e_menu]').catch(() => {}); ok(!/Request change/.test(await p.textContent('#app')), 'a draft has no request-change item'); await p.context().close();

  // ---------- change requests inbox ----------
  const reqs = [{ id: 1, entry_id: 'a1', base_rev: 2, requested_by: 'u2', requested_staff: 'testf02', reason: 'amount typed wrong', patch: { data: { lines: [{ amount: '150', head: 'staff_meal', receipt: 'yes' }], cash_now: '500' } }, status: 'pending', created_at: '2026-10-11T09:00:00Z' },
    { id: 2, entry_id: 'a1', base_rev: 1, requested_by: 'u1', requested_staff: 'owner1', reason: 'my own ask', patch: { data: { cash_now: '600' } }, status: 'pending', created_at: '2026-10-11T10:00:00Z' },
    { id: 3, entry_id: 'a1', base_rev: 1, requested_by: 'u2', requested_staff: 'testf02', reason: 'old one', patch: { data: {} }, status: 'rejected', decision_note: 'no', created_at: '2026-10-01T10:00:00Z' }];
  p = await open({ entries: [ent], reqs }, '#/changes');
  ok(await p.locator('#ch_list [data-req]').count() === 2, 'pending tab: two waiting');
  ok(/lines\.0\.amount: 100 → 150/.test(await p.textContent('[data-req="1"]')), 'shows what changes');
  ok(await p.locator('[data-req="1"] [data-act=ch_approve]').count() === 1 && await p.locator('[data-req="2"] [data-act=ch_approve]').count() === 1, 'owner may decide his own while owner_self_approve is on');
  await p.screenshot({ path: SP + '/ro_changes.png' }); await noOverflow(p, 'changes');
  await p.click('[data-req="1"] [data-act=ch_approve]'); await wait(p, 400);
  c = await calls(p, 'entry_change_decide'); ok(c.length === 1 && c[0].p_id === 1 && c[0].p_approve === true, 'approve sent');
  await p.click('[data-req="2"] [data-act=ch_reject]'); await wait(p, 150); await p.click('[data-act=ch_reject_go]'); await wait(p, 150);
  ok((await calls(p, 'entry_change_decide')).length === 1, 'reject needs a note');
  await p.fill('#ch_note', 'not needed'); await p.click('[data-act=ch_reject_go]'); await wait(p, 400);
  c = await calls(p, 'entry_change_decide'); ok(c.length === 2 && c[1].p_id === 2 && c[1].p_approve === false && c[1].p_note === 'not needed', 'reject with a note');
  await p.click('[data-act=ch_tab][data-v=done]'); await wait(p, 150); ok(await p.locator('#ch_list [data-req]').count() === 3, 'decided tab lists the three');
  await p.context().close();
  // owner_self_approve OFF: no approve button on his own request; menu has withdraw
  p = await open({ entries: [ent], reqs, selfOff: true }, '#/changes');
  ok(await p.locator('[data-req="1"] [data-act=ch_approve]').count() === 1 && await p.locator('[data-req="2"] [data-act=ch_approve]').count() === 0, "self-approval OFF: no approve on the owner's own request");
  await p.click('[data-req="2"] [data-act=ch_menu]'); await wait(p, 150); ok(/Withdraw my request/.test(await p.textContent('.sheet')) && /Revision history/.test(await p.textContent('.sheet')), 'menu: open, history, withdraw');
  await p.click('.sheet [data-act=ch_cancel]'); await wait(p, 300); ok((await calls(p, 'entry_change_cancel')).length === 1, 'withdraw sent'); await p.context().close();
  // delegate without the grant sees only his own
  p = await open({ owner: false, entries: [ent], reqs: reqs.map((r) => ({ ...r, requested_by: r.id === 1 ? 'u1' : 'u9' })), m: { grants: [] } }, '#/changes');
  ok(await p.locator('#ch_list [data-req]').count() === 1 && await p.locator('[data-act=ch_approve]').count() === 0, 'non-approver: only own request, no approve buttons'); await p.context().close();

  // ---------- drawer entries ----------
  p = await open({}, '#/home'); await wait(p, 500);
  const names = await p.evaluate(() => window.BOS_NAV.entries().map((e) => e.route));
  ok(names.includes('rollout') && names.includes('changes') && names.includes('outbox'), 'drawer has rollout, change requests, outbox: ' + names.filter((n) => /rollout|changes|outbox/.test(n)));
  await p.context().close();
  await br.close(); srv.close();
  log('errors:', errors.length ? [...new Set(errors)].slice(0, 8) : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); srv.close(); process.exit(1); } })();
