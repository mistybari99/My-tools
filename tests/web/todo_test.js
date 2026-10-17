// To-do list: the screen #/todo and the small Home card (web/todo.js hooked from nav.js home()). Package R2-B.
// Run: node todo_test.js <abs tests/web dir>      Headless Chromium 360x780 against this checkout's web/. Server stand-in: r2_common.js (R2 RPCs only).
const SP = process.argv[2];
const R = require(SP + '/r2_common.js')(SP, 9312);
const td = R.today();
const task = (id, title, o = {}) => Object.assign({ id, title, detail: '', due_date: null, priority: 'normal', status: 'open', status_note: null, status_at: null, assignee: 'test_me', assigner: 'test_boss', repeat_kind: 'none', overdue: false }, o);
const MINE = [task(1, 'test mop the floor', { due_date: R.addDays(td, -2), overdue: true, priority: 'high', detail: 'test detail line' }), task(2, 'test count the boxes', { due_date: R.addDays(td, 3) }), task(3, 'test wipe the shelf', { priority: 'low' }),
  task(4, 'test already finished', { status: 'done', status_note: 'test did it', status_at: new Date().toISOString() })];
const GIVEN = [task(31, 'test given open', { assignee: 'test_person_a', due_date: R.addDays(td, 1) }), task(32, 'test given done', { assignee: 'test_person_b', status: 'done', status_note: 'test all fine' }), task(33, 'test given cannot', { assignee: 'test_person_a', status: 'cannot', status_note: 'test no key' })];
const ON = { todo_on: true };
(async () => { try {
  await R.start(); const ok = R.ok, wait = R.wait;
  const names = async (p) => (await R.callNames(p)).filter((n) => /^r2_todo/.test(n));

  // 1. OFF: no card on Home, no request, no menu entry, the screen says it is off
  let p = await R.open('#/home', { rules: { todo_on: false }, init: { todo: { mine: MINE, on: false } } });
  ok(await p.locator('#hv_todo').count() === 0 && await p.locator('[data-r2-card]').count() === 0, 'OFF: nothing on Home');
  ok((await names(p)).length === 0, 'OFF: no to-do request at all');
  ok(await p.evaluate(() => { const r = window.BOS.IA.find((x) => x.route === 'todo'); return !!r && r.ok({}) === false; }), 'OFF: the registry hides the menu entry');
  await p.goto('http://localhost:9312/#/todo'); await wait(p, 900);
  ok(/switched off/i.test(await R.text(p)), 'OFF: the screen says it is off');
  const homeOff = await p.evaluate(() => 0);
  p = await R.open('#/home', { init: { todo: { mine: MINE } } });
  ok(await p.locator('#hv_todo').count() === 0 && (await names(p)).length === 0, 'rule absent: same as OFF');

  // 2. ON but nothing open: no card at all
  p = await R.open('#/home', { rules: ON, init: { todo: { mine: [MINE[3]] } } });
  ok(await p.locator('[data-r2-card]').count() === 0 && (await p.locator('#hv_todo').innerHTML()) === '', 'ON, nothing open: the card is not drawn');
  const refCount = await p.evaluate(() => document.querySelectorAll('#hv_main > *').length);

  // 3. ON with open tasks: the small card
  p = await R.open('#/home', { rules: ON, init: { todo: { mine: MINE } } });
  ok(await p.locator('[data-r2-card="todo"]').count() === 1, 'ON with open tasks: the card is drawn');
  let t = await p.locator('#hv_todo').innerText();
  ok(/My to-do/.test(t) && /3/.test(t) && /1 Overdue/i.test(t), 'card shows the open count and the overdue count (' + t.replace(/\n/g, ' | ') + ')');
  ok(/test mop the floor/.test(t) && /test count the boxes/.test(t) && /test wipe the shelf/.test(t) && !/already finished/.test(t), 'card lists the open ones, not the finished one');
  ok(await p.locator('#hv_todo .hrow.bad').count() === 1, 'the overdue row is highlighted');
  ok(await p.evaluate(() => document.querySelector('#hv_todo').getBoundingClientRect().height < 330), 'the card is small');
  await R.noOverflow(p, 'Home with the card'); await R.shot(p, 'todo_home_card');
  await p.click('#hv_todo .hrow'); await wait(p, 800);
  ok(/#\/todo/.test(p.url()) && /To-do list/.test(await p.locator('h1').innerText()), 'tapping the card opens the list');

  // 4. my list: overdue highlighted, done / cannot
  ok(await p.locator('.r2t-card').count() === 3, 'the list shows the 3 open tasks');
  ok(await p.locator('.r2t-card.overdue').count() === 1 && /Overdue/.test(await p.locator('.r2t-card.overdue').innerText()), 'overdue task is highlighted with a word');
  ok(await p.locator('.r2t-card').first().getAttribute('data-id') === '1', 'order as the server gave it (overdue first)');
  ok(/test detail line/.test(await p.locator('.r2t-card[data-id="1"]').innerText()) && /high/i.test(await p.locator('.r2t-card[data-id="1"]').innerText()), 'detail and priority shown');
  ok(await p.locator('[data-act="r2t_new"]').count() === 0 && await p.locator('.seg').count() === 0, 'a person who cannot assign sees no New button and no second tab');
  await R.noOverflow(p, 'my list'); await R.shot(p, 'todo_mine');
  await p.click('.r2t-card[data-id="1"] [data-act="r2t_ask"][data-k="cannot"]'); await wait(p, 300);
  await p.click('[data-act="r2t_set"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_todo_set')).length === 0, 'cannot-do without a reason sends nothing');
  await p.fill('#r2t_n', 'test no mop today'); await p.click('[data-act="r2t_set"]'); await wait(p, 700);
  let c = (await R.calls(p, 'r2_todo_set'))[0] || {};
  ok(c.p_id === 1 && c.p_status === 'cannot' && c.p_note === 'test no mop today', 'cannot-do sends id, status and the reason');
  ok(await p.locator('.r2t-card').count() === 2, 'the task left the open list');
  await p.click('.r2t-card[data-id="2"] [data-act="r2t_ask"][data-k="done"]'); await wait(p, 300);
  await p.click('[data-act="r2t_set"]'); await wait(p, 600);
  c = (await R.calls(p, 'r2_todo_set'))[1] || {};
  ok(c.p_id === 2 && c.p_status === 'done' && c.p_note === null, 'done with no note is allowed (note optional)');
  await p.check('#r2t_all'); await wait(p, 600);
  ok((await R.calls(p, 'r2_todo_mine')).some((a) => a.p_all === true), 'the finished-too box asks for the history');
  ok(await p.locator('.r2t-card.finished').count() === 3 && /test did it/.test(await p.locator('.r2t-card[data-id="4"]').innerText()) && /test no mop today/.test(await p.locator('.r2t-card[data-id="1"]').innerText()), 'finished tasks show their notes');
  ok(await p.locator('.r2t-card.finished [data-act="r2t_ask"]').count() === 0, 'a finished task has no Done / Cannot buttons');

  // 5. a giver: new task, both targets, repeat only when the setting is on
  p = await R.open('#/todo', { rules: ON, init: { todo: { mine: [], given: GIVEN, can_assign: true } } });
  ok(await p.locator('.seg button').count() === 2 && await p.locator('[data-act="r2t_new"]').count() === 1, 'giver: two tabs and the New button');
  ok(/nothing to do/i.test(await R.text(p)), 'giver: own list is empty');
  await p.click('.seg button[data-v="given"]'); await wait(p, 300);
  ok(await p.locator('.r2t-card').count() === 3, 'I gave: all three');
  ok(/test_person_a/.test(await p.locator('.r2t-card[data-id="31"]').innerText()) && await p.locator('.r2t-card[data-id="32"] .chip.ok').count() === 1 && /test all fine/.test(await p.locator('.r2t-card[data-id="32"]').innerText()), 'assignee, status chip and the done-note are visible to the giver');
  ok(/test no key/.test(await p.locator('.r2t-card[data-id="33"]').innerText()), 'the cannot-do reason is visible to the giver');
  await R.noOverflow(p, 'given list'); await R.shot(p, 'todo_given');
  await p.selectOption('#r2t_f', 'done'); await wait(p, 500);
  ok((await R.calls(p, 'r2_todo_given')).some((a) => a.p_status === 'done') && await p.locator('.r2t-card').count() === 1, 'the status filter asks the server');
  await p.selectOption('#r2t_f', ''); await wait(p, 500);
  await p.click('.r2t-card[data-id="31"] [data-act="r2t_cancel"]'); await wait(p, 300);
  await p.click('[data-act="r2t_cgo"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_todo_manage')).length === 0, 'cancel without a reason sends nothing');
  await p.fill('#r2t_cr', 'test not needed'); await p.click('[data-act="r2t_cgo"]'); await wait(p, 600);
  c = (await R.calls(p, 'r2_todo_manage'))[0] || {};
  ok(c.p_id === 31 && c.p_action === 'cancel' && c.p_note === 'test not needed', 'cancel sends id, action and reason');
  await p.click('.r2t-card[data-id="33"] [data-act="r2t_reopen"]'); await wait(p, 600);
  ok((await R.calls(p, 'r2_todo_manage')).some((a) => a.p_id === 33 && a.p_action === 'reopen'), 'reopen is one tap');
  // new task
  await p.click('[data-act="r2t_new"]'); await wait(p, 400);
  ok(await p.locator('#r2t_rp').count() === 0, 'no repeat field while todo_repeat_on is OFF');
  await R.noOverflow(p, 'new task sheet'); await R.shot(p, 'todo_new');
  await p.click('[data-act="r2t_give"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_todo_assign')).length === 0, 'no title: nothing sent');
  await p.fill('#r2t_ti', 'test clean the oven'); await p.click('[data-act="r2t_give"]'); await wait(p, 300);
  ok((await R.calls(p, 'r2_todo_assign')).length === 0, 'no target: nothing sent');
  ok(await p.locator('#r2t_x option').count() === 3, 'person list from the staff directory');
  await p.selectOption('#r2t_x', 'p1'); await p.fill('#r2t_de', 'test detail'); await p.fill('#r2t_du', R.addDays(td, 2)); await p.selectOption('#r2t_pr', 'urgent');
  await p.click('[data-act="r2t_give"]'); await wait(p, 700);
  c = (await R.calls(p, 'r2_todo_assign'))[0] || {};
  ok(c.p_title === 'test clean the oven' && c.p_kind === 'person' && c.p_target === 'p1' && c.p_due === R.addDays(td, 2) && c.p_priority === 'urgent' && c.p_detail === 'test detail' && c.p_repeat === 'none', 'person task sends all fields');
  ok(typeof c.p_client === 'string' && c.p_client.length > 20, 'client id sent');
  ok(await p.locator('#sheet').count() === 0 && /test clean the oven/.test(await p.locator('.r2t-card').first().innerText()), 'sheet closed, the new task heads the I-gave list');
  await p.click('[data-act="r2t_new"]'); await wait(p, 300);
  await p.fill('#r2t_ti', 'test for a role'); await p.selectOption('#r2t_k', 'role'); await wait(p, 100);
  ok(await p.locator('#r2t_x option').count() > 2, 'role list from the roles table');
  await p.selectOption('#r2t_x', 'salesperson'); await p.click('[data-act="r2t_give"]'); await wait(p, 700);
  c = (await R.calls(p, 'r2_todo_assign'))[1] || {};
  ok(c.p_kind === 'role' && c.p_target === 'salesperson', 'role task sends the role code');
  ok(/3 people|3 /.test(await p.locator('#toast').innerText()), 'toast says how many people got it');
  await p.evaluate(() => { window.__R2.err.r2_todo_assign = 'repeat_off'; });
  await p.click('[data-act="r2t_new"]'); await wait(p, 300); await p.fill('#r2t_ti', 'test x'); await p.selectOption('#r2t_x', 'p1'); await p.click('[data-act="r2t_give"]'); await wait(p, 500);
  ok(/switched off/i.test(await p.locator('#toast').innerText()), 'a refused assign shows a readable message');
  // repeat on
  p = await R.open('#/todo', { rules: { todo_on: true, todo_repeat_on: true }, init: { todo: { mine: [], given: [], can_assign: true, repeat_on: true } } });
  await p.click('[data-act="r2t_new"]'); await wait(p, 300);
  ok(await p.locator('#r2t_rp option').count() === 3, 'repeat field (once / daily / weekly) appears when todo_repeat_on is ON');
  await p.fill('#r2t_ti', 'test daily sweep'); await p.selectOption('#r2t_x', 'p2'); await p.selectOption('#r2t_rp', 'daily'); await p.click('[data-act="r2t_give"]'); await wait(p, 600);
  ok(((await R.calls(p, 'r2_todo_assign'))[0] || {}).p_repeat === 'daily', 'repeat daily is sent');

  // 6. the owner label, and a refusal of a done by the server
  p = await R.open('#/todo', { rules: ON, init: { todo: { mine: [MINE[1]], given: GIVEN, can_assign: true } } });
  ok(/All given/.test(await p.locator('.seg').innerText()), 'the owner tab is called All given');
  p = await R.open('#/todo', { rules: ON, owner: false, init: { todo: { mine: [MINE[1]], given: [], can_assign: false } } });
  await p.evaluate(() => { window.__R2.err.r2_todo_set = 'not_open'; });
  await p.click('.r2t-card[data-id="2"] [data-act="r2t_ask"][data-k="done"]'); await wait(p, 300); await p.click('[data-act="r2t_set"]'); await wait(p, 500);
  ok(/not open/i.test(await p.locator('#toast').innerText()), 'a server refusal is shown in plain words');

  // 7. an old server: nothing breaks
  p = await R.open('#/home', { rules: ON, init: { missing: { all: true } } });
  ok(await p.locator('[data-r2-card]').count() === 0, 'missing server function: no card and no error');
  p = await R.open('#/todo', { rules: ON, init: { missing: { all: true } } });
  ok(/does not have this yet/i.test(await R.text(p)), 'missing server function: the page says so');

  // 8. three languages and 360px
  for (const lang of ['bn', 'mix', 'en']) {
    p = await R.open('#/home', { rules: ON, lang, init: { todo: { mine: MINE, given: GIVEN, can_assign: true } } });
    await R.noOverflow(p, 'Home card ' + lang);
    await p.goto('http://localhost:9312/#/todo'); await wait(p, 900); await R.noOverflow(p, 'list ' + lang);
    await p.click('.seg button[data-v="given"]'); await wait(p, 300); await R.noOverflow(p, 'given ' + lang);
    await p.click('[data-act="r2t_new"]'); await wait(p, 300); await R.noOverflow(p, 'new ' + lang);
  }
  p = await R.open('#/todo', { rules: ON, lang: 'bn', init: { todo: { mine: MINE } } });
  ok(/করণীয়/.test(await p.locator('h1').innerText()) && /দেরি/.test(await p.locator('.r2t-card.overdue').innerText()), 'Bangla title and overdue word');

  console.log('errors:', R.errors.length ? R.errors.join('\n') : 'none'); console.log('assertions:', R.n); console.log('assert failures:', R.bad);
  await R.stop();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; try { R.srv.close(); } catch (e2) { /* ignore */ } } })();
