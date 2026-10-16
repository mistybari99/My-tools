// Shift schedule: the screen #/shifts (web/shifts.js): my upcoming shifts, the roster grid, templates, the roster-vs-attendance report. Package R2-C.
// Run: node shifts_test.js <abs tests/web dir>      Headless Chromium 360x780 against this checkout's web/. Server stand-in: r2_common.js (R2 RPCs only).
const SP = process.argv[2];
const R = require(SP + '/r2_common.js')(SP, 9313);
const td = R.today(), dow = (d) => new Date(d + 'T00:00:00Z').getUTCDay();
const SHIFT = (id, nm, st, en) => ({ id, name_bn: nm, name_en: nm, start: st, end: en, crosses_midnight: false });
const MORN = SHIFT(1, 'test morning', '06:00', '14:00'), EVE = SHIFT(2, 'test evening', '14:00', '22:00');
const mate = (n, s) => ({ name_bn: n, name_en: n, shift_bn: s.name_bn, shift_en: s.name_en, start: s.start, end: s.end });
const day = (o, extra) => Object.assign({ day: R.addDays(td, o), dow: dow(R.addDays(td, o)), off: false, note: null, source: 'day', place_id: 1, holiday_bn: null, holiday_en: null, leave: false, shift: null, mates: [] }, extra);
const MY = { on: true, linked: true, mates_on: true, days: [day(0, { shift: MORN, mates: [mate('test_mate_one', MORN), mate('test_mate_two', EVE)] }), day(1, { off: true, note: 'test family event' }), day(2, { off: true, leave: true }),
  day(3, { shift: EVE, note: 'test swap with mate one', holiday_en: 'test holiday', holiday_bn: 'test holiday' })] };
const SCHED = { state: { on: true, mates_on: true, can_manage: true, locations: [1, 2], linked: true } };
const ROSTER = { templates: [{ id: 1, name_bn: 'test morning', name_en: 'test morning', location_id: 1, start: '06:00', end: '14:00' }, { id: 2, name_bn: 'test evening', name_en: 'test evening', location_id: 1, start: '14:00', end: '22:00' }, { id: 3, name_bn: 'test everywhere', name_en: 'test everywhere', location_id: null, start: '09:00', end: '17:00' }],
  employees: [{ id: 'e1', name_bn: 'test_emp1', name_en: 'test_emp1', nickname: null, d: [{ o: 0, shift_id: 1 }, { o: 1, off: true, note: 'test family event' }, { o: 2, shift_id: 2, note: 'test swap', source: 'day' }, { o: 3, shift_id: 1, source: 'pattern' }, { o: 4, shift_id: 1, leave: true }] },
              { id: 'e2', name_bn: 'test_emp2', name_en: 'test_emp2', nickname: null, d: [] }] };
const REP = { attendance: true, from: R.addDays(td, -6), to: td, totals: { late: 1, absent: 1, ok: 3, worked_off: 1 }, rows: [
  { employee_id: 'e1', name_bn: 'test_emp1', name_en: 'test_emp1', day: R.addDays(td, -2), planned: true, shift_bn: 'test morning', start: '06:00', end: '14:00', attendance: 'late', first_in: null, late_minutes: 12, result: 'late' },
  { employee_id: 'e2', name_bn: 'test_emp2', name_en: 'test_emp2', day: R.addDays(td, -2), planned: true, shift_bn: 'test morning', start: '06:00', end: '14:00', attendance: 'absent', first_in: null, late_minutes: 0, result: 'absent' },
  { employee_id: 'e1', name_bn: 'test_emp1', name_en: 'test_emp1', day: R.addDays(td, -1), planned: false, shift_bn: null, start: null, end: null, attendance: 'present', first_in: null, late_minutes: 0, result: 'worked_off' },
  { employee_id: 'e2', name_bn: 'test_emp2', name_en: 'test_emp2', day: R.addDays(td, -3), planned: true, shift_bn: 'test morning', start: '06:00', end: '14:00', attendance: 'present', first_in: null, late_minutes: 0, result: 'ok' }] };
const ON = { shift_on: true };
const weekStartSat = (iso) => R.addDays(iso, -((dow(iso) - 6 + 7) % 7));
(async () => { try {
  await R.start(); const ok = R.ok, wait = R.wait;
  const names = async (p) => (await R.callNames(p)).filter((n) => /^r2_(shift|roster)/.test(n));

  // 1. OFF: nothing offered, nothing asked, the screen says it is off
  let p = await R.open('#/home', { rules: { shift_on: false }, init: { shift: { my: MY, state: { on: false, can_manage: false, locations: [], linked: false, mates_on: false } } } });
  ok((await names(p)).length === 0, 'OFF: no shift request on Home');
  ok(await p.evaluate(() => { const r = window.BOS.IA.find((x) => x.route === 'shifts'); return !!r && r.ok({}) === false; }), 'OFF: the registry hides the menu entry');
  await p.goto('http://localhost:9313/#/shifts'); await wait(p, 900);
  ok(/switched off/i.test(await R.text(p)), 'OFF: the screen says it is off');
  ok(await p.locator('.seg').count() === 0, 'OFF: no tabs');
  p = await R.open('#/home', { init: { shift: { my: MY } } });
  ok((await names(p)).length === 0, 'rule absent: same as OFF');
  p = await R.open('#/home', { rules: ON, init: { shift: { my: MY } } });
  ok(await p.evaluate(() => { const r = window.BOS.IA.find((x) => x.route === 'shifts'); return !!r && r.ok({}) === true && r.group === 'people'; }), 'ON: the entry is offered, under Staff (people)');
  ok((await names(p)).length === 0, 'ON: Home itself still makes no shift request (only the screen does)');

  // 2. a member of staff: my shifts
  p = await R.open('#/shifts', { rules: ON, owner: false, init: { shift: { my: MY, state: { on: true, mates_on: true, can_manage: false, locations: [], linked: true } } } });
  ok(/Shift schedule/.test(await p.locator('h1').innerText()), 'title');
  ok(await p.locator('.seg').count() === 0, 'staff: no tabs (only the own list)');
  ok(await p.locator('.r2s-day').count() === 4, 'four days are listed; days with nothing planned are not invented');
  ok(await p.locator('.r2s-day.today').count() === 1 && /Today/.test(await p.locator('.r2s-day.today').innerText()), 'today is marked');
  let t = await p.locator('.r2s-day').nth(0).innerText();
  ok(/test morning 06:00.14:00/.test(t), 'shift name and times: ' + t.replace(/\n/g, ' | '));
  ok(/Off/.test(await p.locator('.r2s-day').nth(1).innerText()) && /test family event/.test(await p.locator('.r2s-day').nth(1).innerText()), 'off-day with its note');
  ok(/Approved leave/.test(await p.locator('.r2s-day.leave').innerText()), 'approved leave is flagged');
  t = await p.locator('.r2s-day').nth(3).innerText();
  ok(/test evening 14:00.22:00/.test(t) && /test swap with mate one/.test(t) && /Holiday: test holiday/.test(t), 'swap note and holiday on a shift day');
  ok(await p.locator('.r2s-day').nth(0).locator('details').count() === 1 && /\(2\)/.test(await p.locator('.r2s-day').nth(0).locator('summary').innerText()), 'who else is on: summary with the count');
  await p.locator('.r2s-day').nth(0).locator('summary').click(); await wait(p, 200);
  t = await p.locator('.r2s-day').nth(0).locator('details').innerText();
  ok(/test_mate_one/.test(t) && /test_mate_two/.test(t) && /14:00.22:00/.test(t), 'colleagues at my place with their times');
  ok(await p.locator('.r2s-day').nth(1).locator('details').count() === 0, 'no colleague list on an off-day');
  await R.noOverflow(p, 'my shifts'); await R.shot(p, 'shifts_my');
  const mine = (await R.calls(p, 'r2_shift_my'))[0] || {};
  ok(mine.p_from === td && mine.p_days === 14, 'asks for 14 days from today');
  // colleagues switch off
  p = await R.open('#/shifts', { rules: ON, owner: false, init: { shift: { my: Object.assign({}, MY, { mates_on: false }), state: { on: true, mates_on: false, can_manage: false, locations: [], linked: true } } } });
  ok(await p.locator('.r2s-day details').count() === 0 && /test morning/.test(await p.locator('.r2s-day').first().innerText()), 'shift_mates_on OFF: my own shifts only, no colleague list');
  // not linked / empty
  p = await R.open('#/shifts', { rules: ON, owner: false, init: { shift: { my: { on: true, linked: false, days: [] }, state: { on: true, mates_on: true, can_manage: false, locations: [], linked: false } } } });
  ok(/not linked to an employee record/i.test(await R.text(p)), 'a login with no employee record is told why');
  p = await R.open('#/shifts', { rules: ON, owner: false, init: { shift: { my: { on: true, linked: true, mates_on: true, days: [] }, state: { on: true, mates_on: true, can_manage: false, locations: [], linked: true } } } });
  ok(/No shifts are planned/i.test(await R.text(p)), 'empty plan: a plain sentence');

  // 3. a scheduler: tabs and the roster grid
  const SC = { shift: Object.assign({ my: MY, roster: ROSTER, report: REP }, SCHED) };
  p = await R.open('#/shifts', { rules: ON, init: SC });
  ok(await p.locator('.seg button').count() === 3, 'scheduler: three tabs');
  await p.click('.seg button[data-v="roster"]'); await wait(p, 700);
  ok(await p.locator('#r2s_loc option').count() === 2, 'place picker offers only the places he may schedule');
  const rc = (await R.calls(p, 'r2_shift_roster'))[0] || {};
  ok(rc.p_loc === 1 && rc.p_from === weekStartSat(td) && rc.p_days === 7, 'roster is requested for place 1 and the week containing today (' + JSON.stringify(rc) + ')');
  ok(await p.locator('.r2s-emp').count() === 2 && await p.locator('.r2s-emp').first().locator('.r2s-cell').count() === 7, 'two people, seven cells each');
  ok(await p.locator('.r2s-leg .chip').count() === 4, 'legend: three templates + off');
  t = await p.locator('.r2s-emp').first().innerText();
  ok(/A/.test(t) && /B/.test(t) && /×/.test(t), 'cells carry the template letter and the off mark');
  ok(await p.locator('.r2s-emp').first().locator('.r2s-cell.off').count() === 1 && await p.locator('.r2s-emp').first().locator('.r2s-cell.pat').count() === 1 && await p.locator('.r2s-emp').first().locator('.r2s-cell.note').count() === 2 && await p.locator('.r2s-emp').first().locator('.r2s-cell.lv').count() === 1, 'off, pattern (dashed), note and leave marks');
  ok(await p.evaluate(() => Array.from(document.querySelectorAll('.r2s-cell')).every((b) => b.getBoundingClientRect().height >= 44)), 'cells are at least 44px tall');
  await R.noOverflow(p, 'roster'); await R.shot(p, 'shifts_roster');
  // edit a cell
  const emptyCell = p.locator('.r2s-emp').nth(1).locator('.r2s-cell').nth(5);
  await emptyCell.click(); await wait(p, 300);
  ok(await p.locator('#r2s_sel option').count() === 5, 'cell sheet: nothing + 3 templates + off');
  await p.selectOption('#r2s_sel', '2'); await p.fill('#r2s_note', 'test swap with emp1'); await p.click('[data-act="r2s_cellsave"]'); await wait(p, 600);
  let c = (await R.calls(p, 'r2_roster_set'))[0] || {};
  ok(c.p_emp === 'e2' && c.p_shift === 2 && c.p_off === false && c.p_note === 'test swap with emp1' && c.p_day === R.addDays(weekStartSat(td), 5), 'a shift + note sends emp, day, template id and note (' + JSON.stringify(c) + ')');
  await p.locator('.r2s-emp').nth(1).locator('.r2s-cell').nth(6).click(); await wait(p, 300);
  await p.selectOption('#r2s_sel', 'off'); await p.click('[data-act="r2s_cellsave"]'); await wait(p, 600);
  c = (await R.calls(p, 'r2_roster_set'))[1] || {};
  ok(c.p_shift === null && c.p_off === true && c.p_note === null, 'an off-day sends off true and no shift');
  await p.locator('.r2s-emp').first().locator('.r2s-cell').nth(0).click(); await wait(p, 300);
  ok(await p.locator('#r2s_sel').inputValue() === '1', 'the sheet opens on the current template');
  await p.selectOption('#r2s_sel', ''); await p.click('[data-act="r2s_cellsave"]'); await wait(p, 600);
  c = (await R.calls(p, 'r2_roster_clear'))[0] || {};
  ok(c.p_emp === 'e1' && c.p_day === weekStartSat(td), 'the "nothing set" choice clears the cell');
  // server refusal
  await p.evaluate(() => { window.__R2.err.r2_roster_set = 'not allowed'; });
  await p.locator('.r2s-emp').nth(1).locator('.r2s-cell').nth(1).click(); await wait(p, 300); await p.selectOption('#r2s_sel', '1'); await p.click('[data-act="r2s_cellsave"]'); await wait(p, 500);
  ok(/not allowed/i.test(await p.locator('#toast').innerText()), 'a refused cell shows a readable message');
  await p.click('[data-act="closesheet"]'); await wait(p, 200);
  // week navigation and copy
  await p.click('[data-act="r2s_wk"][data-v="7"]'); await wait(p, 600);
  ok(((await R.calls(p, 'r2_shift_roster')).slice(-1)[0] || {}).p_from === R.addDays(weekStartSat(td), 7), 'next week asks for the next week');
  await p.click('[data-act="r2s_copy"]'); await wait(p, 600);
  c = (await R.calls(p, 'r2_roster_copy_week'))[0] || {};
  ok(c.p_loc === 1 && c.p_from === weekStartSat(td) && c.p_to === R.addDays(weekStartSat(td), 7), 'copy last week sends place, last week and this week');
  ok(/4/.test(await p.locator('#toast').innerText()) && /1/.test(await p.locator('#toast').innerText()), 'copy tells how many were copied and skipped');
  await p.selectOption('#r2s_loc', '2'); await wait(p, 600);
  ok(((await R.calls(p, 'r2_shift_roster')).slice(-1)[0] || {}).p_loc === 2, 'changing the place reloads the roster');
  await p.selectOption('#r2s_loc', '1'); await wait(p, 500);
  // templates
  await p.click('[data-act="r2s_tpls"]'); await wait(p, 300);
  ok(await p.locator('#r2s_tpllist .card').count() === 3 && /Every place/.test(await p.locator('#r2s_tpllist').innerText()), 'template list, the every-place one is marked');
  await R.noOverflow(p, 'template list');
  await p.click('[data-act="r2s_tplnew"]'); await wait(p, 300);
  await p.click('[data-act="r2s_tplsave"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_shift_template_save')).length === 0, 'a template with no name sends nothing');
  await p.fill('#r2s_nb', 'test night'); await p.fill('#r2s_ne', 'test night'); await p.fill('#r2s_st', '22:00'); await p.fill('#r2s_en', '06:00');
  ok(await p.locator('#r2s_all0').count() === 1, 'the owner may make an every-place template');
  await p.click('[data-act="r2s_tplsave"]'); await wait(p, 700);
  c = (await R.calls(p, 'r2_shift_template_save'))[0] || {};
  ok(c.p_id === null && c.p_data.name_bn === 'test night' && c.p_data.start_time === '22:00' && c.p_data.end_time === '06:00' && c.p_data.location_id === 1, 'a new template goes to the place being edited');
  ok(await p.locator('.r2s-leg .chip').count() === 5, 'the new template appears in the legend after saving');
  await p.click('[data-act="r2s_tpls"]'); await wait(p, 300);
  await p.click('[data-act="r2s_tplretire"][data-v="2"]'); await wait(p, 600);
  c = (await R.calls(p, 'r2_shift_template_save'))[1] || {};
  ok(c.p_id === 2 && c.p_data.active === false, 'retire sends active false (nothing is deleted)');
  await R.shot(p, 'shifts_roster_after');
  // a place-limited scheduler is not offered every-place templates
  p = await R.open('#/shifts', { rules: ON, owner: false, init: { shift: Object.assign({ my: MY, roster: ROSTER, report: REP }, { state: { on: true, mates_on: true, can_manage: true, locations: [1], linked: true } }) } });
  await p.click('.seg button[data-v="roster"]'); await wait(p, 600);
  ok(await p.locator('#r2s_loc option').count() === 1, 'a scheduler of one place sees one place');
  await p.click('[data-act="r2s_tpls"]'); await wait(p, 300); await p.click('[data-act="r2s_tplnew"]'); await wait(p, 300);
  ok(await p.locator('#r2s_all0').count() === 0, 'a non-owner cannot choose "every place"');

  // 4. the report
  p = await R.open('#/shifts', { rules: ON, init: SC });
  await p.click('.seg button[data-v="report"]'); await wait(p, 400);
  ok(await p.locator('#r2s_rf').inputValue() === R.addDays(td, -6) && await p.locator('#r2s_rt').inputValue() === td, 'report defaults to the last 7 days');
  ok(await p.locator('.r2s-row').count() === 0, 'nothing is shown before Show is pressed');
  await p.click('[data-act="r2s_rep"]'); await wait(p, 600);
  c = (await R.calls(p, 'r2_shift_report'))[0] || {};
  ok(c.p_loc === 1 && c.p_from === R.addDays(td, -6) && c.p_to === td, 'report asks with place and dates');
  ok(await p.locator('.r2s-row').count() === 3 && await p.locator('.r2s-row[data-result="ok"]').count() === 0, 'matching rows are hidden by default (3 exceptions)');
  t = await p.locator('#r2s_tot').innerText();
  ok(/Late: 1/.test(t) && /Absent: 1/.test(t) && /Present: 3/.test(t) && /Worked on an off-day: 1/.test(t), 'totals by kind: ' + t.replace(/\n/g, ' | '));
  ok(/\+12 min/.test(await p.locator('.r2s-row[data-result="late"]').innerText()), 'minutes late shown');
  await p.check('#r2s_all'); await wait(p, 300);
  ok(await p.locator('.r2s-row').count() === 4, 'show the matching ones too');
  await R.noOverflow(p, 'report'); await R.shot(p, 'shifts_report');
  p = await R.open('#/shifts', { rules: ON, init: { shift: Object.assign({ my: MY, roster: ROSTER, report: { attendance: false, rows: [], totals: {} } }, SCHED) } });
  await p.click('.seg button[data-v="report"]'); await wait(p, 300); await p.click('[data-act="r2s_rep"]'); await wait(p, 500);
  ok(/no attendance data/i.test(await R.text(p)) && await p.locator('.r2s-row').count() === 0, 'no attendance table on the server: a plain notice, no failure (soft link)');

  // 5. old server
  p = await R.open('#/shifts', { rules: ON, init: { missing: { all: true } } });
  ok(/does not have this yet/i.test(await R.text(p)), 'missing server function: the page says so');

  // 6. languages, 360px
  for (const lang of ['bn', 'mix', 'en']) {
    p = await R.open('#/shifts', { rules: ON, lang, init: SC });
    await R.noOverflow(p, 'my ' + lang);
    await p.click('.seg button[data-v="roster"]'); await wait(p, 600); await R.noOverflow(p, 'roster ' + lang);
    await p.locator('.r2s-emp').first().locator('.r2s-cell').nth(2).click(); await wait(p, 300); await R.noOverflow(p, 'cell sheet ' + lang); await p.click('[data-act="closesheet"]'); await wait(p, 200);
    await p.click('.seg button[data-v="report"]'); await wait(p, 300); await p.click('[data-act="r2s_rep"]'); await wait(p, 500); await R.noOverflow(p, 'report ' + lang);
  }
  p = await R.open('#/shifts', { rules: ON, lang: 'bn', init: SC });
  ok(/শিফট রোস্টার/.test(await p.locator('h1').innerText()) && /আমার শিফট/.test(await p.locator('.seg').innerText()), 'Bangla title and tabs');

  console.log('errors:', R.errors.length ? R.errors.join('\n') : 'none'); console.log('assertions:', R.n); console.log('assert failures:', R.bad);
  await R.stop();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; try { R.srv.close(); } catch (e2) { /* ignore */ } } })();
