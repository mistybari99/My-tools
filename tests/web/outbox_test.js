// W5a: form offline queue (rule 12): Not sent yet chip, auto retry on 'online' and at start, idempotent client id, #/outbox (retry / open / discard-with-confirm).
// Run: node outbox_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = 8342, srv = C.serve(PORT);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to fetch|Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, o);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};try{localStorage.setItem('bos_lang','en')}catch(e){}${o.queue ? `try{ if(!localStorage.getItem('bos_seeded')){ localStorage.setItem('bos_eq_u1', ${JSON.stringify(JSON.stringify(o.queue))}); localStorage.setItem('bos_seeded','1'); } }catch(e){}` : ''}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(o.settle || 1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const q = (p) => p.evaluate(() => JSON.parse(localStorage.getItem('bos_eq_u1') || '[]'));
  const net = (p, v) => p.evaluate((x) => { window.__M.w5.net = x; }, v);
  const fillOk = async (p) => { await p.fill('[data-p="lines.0.amount"]', '120'); await p.selectOption('[data-p="lines.0.head"]', 'staff_meal'); await p.click('[data-act=pick][data-p="lines.0.receipt"][data-v=yes]');
    await p.fill('[data-p="cash_now"]', '3000'); await p.fill('[data-p="receipts_total"]', '120'); await p.check('[data-p="drawer_untouched"]'); };

  // ---------- save offline -> Not sent yet -> online -> sent once ----------
  let p = await open({}, '#/entry/new/10-2/1');
  await fillOk(p); await net(p, true);
  await p.click('[data-act=e_save]'); await wait(p, 400);
  let items = await q(p);
  ok(items.length === 1 && items[0].kind === 'entry' && items[0].args.p_data.lines[0].amount === '120' && /^[0-9a-f-]{36}$/.test(items[0].cid) && items[0].state === 'wait', 'record is on the phone with its client id');
  ok(await p.locator('#e_notsent').count() === 1 && /Not sent yet/.test(await p.textContent('#e_notsent')), 'chip: Not sent yet');
  ok(/No network/.test(await p.textContent('.toast, #toast, body')), 'toast says it waits on the phone');
  const cid = items[0].cid;
  await p.fill('[data-p="lines.0.amount"]', '125'); await p.click('[data-act=e_save]'); await wait(p, 400);
  items = await q(p); ok(items.length === 1 && items[0].args.p_data.lines[0].amount === '125' && items[0].cid === cid, 'saving again replaces the same line (same client id), nothing duplicated');
  await p.screenshot({ path: SP + '/ob_chip.png', fullPage: true });
  // lost answer: the server saved, the phone never heard -> the retry must not create a second entry
  await net(p, false); await p.evaluate(() => { window.__M.w5.lose = true; });
  await p.evaluate(() => window.BOS.outbox.flush()); await wait(p, 500);
  ok((await q(p)).length === 1 && (await p.evaluate(() => window.__DATA.tables.entries.length)) === 1, 'answer lost: still queued, the server has one entry');
  await p.evaluate(() => window.dispatchEvent(new Event('online'))); await wait(p, 700);
  let c = await calls(p, 'save_entry');
  ok(c.length >= 4 && c.filter((x) => x.p_meta && x.p_meta.client_id === cid).length >= 3, 'the same client id is re-sent');
  ok((await q(p)).length === 0, 'queue is empty after the retry'); ok((await p.evaluate(() => window.__DATA.tables.entries.length)) === 1, 'idempotent: still ONE entry on the server');
  ok(await p.locator('#e_notsent').count() === 0 && /#\/entry\/e1/.test(await p.evaluate(() => location.hash)), 'chip gone; the editor now points at the saved entry');
  await p.context().close();

  // ---------- submit offline ----------
  p = await open({}, '#/entry/new/10-2/1'); await fillOk(p); await net(p, true);
  await p.click('[data-act=e_submit]'); await wait(p, 500);
  items = await q(p); ok(items.length === 1 && items[0].submit === true && items[0].kind === 'entry', 'submit while offline is queued with the entry');
  ok(await p.locator('#e_notsent').count() === 1, 'Not sent yet while waiting');
  await net(p, false); await p.evaluate(() => window.dispatchEvent(new Event('online'))); await wait(p, 900);
  ok((await q(p)).length === 0 && (await p.evaluate(() => window.__DATA.tables.entries[0].status)) === 'submitted', 'online: saved and submitted by itself');
  ok((await calls(p, 'submit_entry')).length >= 1 && /Waiting for check/.test(await p.textContent('#entry')), 'screen shows submitted');
  await p.context().close();

  // ---------- submit of an already saved draft fails on the network ----------
  p = await open({}, '#/entry/new/10-2/1'); await fillOk(p); await p.click('[data-act=e_save]'); await wait(p, 400);
  ok((await q(p)).length === 0, 'online save leaves nothing in the queue');
  await net(p, true); await p.click('[data-act=e_submit]'); await wait(p, 500);
  items = await q(p); ok(items.length === 1 && items[0].kind === 'submit' && items[0].id === 'e1', 'only the submit waits');
  await net(p, false); await p.evaluate(() => window.dispatchEvent(new Event('online'))); await wait(p, 700);
  ok((await q(p)).length === 0 && (await p.evaluate(() => window.__DATA.tables.entries[0].status)) === 'submitted', 'submit goes when online');
  await p.context().close();

  // ---------- a business error is NOT a network error ----------
  p = await open({ w: { err: { save_entry: 'paper_serial_in_use' } } }, '#/entry/new/10-2/1'); await fillOk(p); await p.click('[data-act=e_save]'); await wait(p, 500);
  ok((await q(p)).length === 0 && await p.locator('#e_notsent').count() === 0, 'server refusal is shown, not queued'); await p.context().close();

  // ---------- at start: a waiting record is sent without any click ----------
  const waitItem = { k: 'c:cc111111-1111-4111-8111-111111111111', kind: 'entry', cid: 'cc111111-1111-4111-8111-111111111111', id: null, code: '10-2', loc: 1, date: '2026-10-05', args: { p_id: null, p_form: '10-2', p_loc: 1, p_date: '2026-10-05', p_data: { lines: [{ amount: '77' }] }, p_flags: [], p_note: null }, meta: { client_id: 'cc111111-1111-4111-8111-111111111111' }, submit: false, at: '2026-10-05T09:00:00Z', state: 'wait', msg: '', ps: '' };
  p = await open({ queue: [waitItem], settle: 3500 }, '#/home');
  c = await calls(p, 'save_entry'); ok(c.length === 1 && c[0].p_meta.client_id === waitItem.cid && c[0].p_data.lines[0].amount === '77', 'app start: the waiting record was sent automatically');
  ok((await q(p)).length === 0, 'and removed from the queue'); await p.context().close();

  // ---------- outbox page ----------
  const refused = { ...waitItem, k: 'c:dd222222-2222-4222-8222-222222222222', cid: 'dd222222-2222-4222-8222-222222222222', meta: { client_id: 'dd222222-2222-4222-8222-222222222222', entered_later: true, paper_serial: 'A-9', paper_at: '2026-10-04T10:00:00+06:00' }, state: 'refused', msg: 'paper_serial_in_use', ps: 'A-9', args: { ...waitItem.args, p_data: { lines: [{ amount: '5' }], paper_no: 'A-9' } } };
  p = await open({ queue: [{ ...waitItem, state: 'refused', msg: 'rollout_paper:10-2' }, refused], w: { net: true } }, '#/outbox');
  ok(await p.locator('#ob_list [data-k]').count() === 2, 'two waiting lines');
  ok(/Refused by the server/.test(await p.textContent('#ob_list')) && /rollout_paper/.test(await p.textContent('#ob_list')) && /A-9/.test(await p.textContent('#ob_list')), 'refused lines show why and the paper serial');
  await p.screenshot({ path: SP + '/ob_page.png' });
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal overflow');
  // open a line that never reached the server: the editor is restored with the same client id
  await p.click(`[data-k="${refused.k}"] [data-act=ob_open]`); await wait(p, 900);
  ok(/#\/entry\/new\/10-2\/1/.test(await p.evaluate(() => location.hash)) && (await p.inputValue('[data-p="lines.0.amount"]')) === '5' && (await p.inputValue('#el_ps')) === 'A-9', 'open restores the data, the paper serial and the original time');
  ok(await p.locator('#e_notsent').count() === 1, 'still marked Not sent yet');
  await p.evaluate(() => { location.hash = '#/outbox'; }); await wait(p, 600);
  // retry while still offline keeps it
  await p.click(`[data-k="${waitItem.k}"] [data-act=ob_retry]`); await wait(p, 500);
  items = await q(p); ok(items.length === 2 && items.find((x) => x.k === waitItem.k).state === 'wait', 'retry offline keeps the line (state back to waiting)');
  // discard needs a confirmation and is local only
  const before = (await p.evaluate(() => window.__M.calls.length));
  await p.click(`[data-k="${refused.k}"] [data-act=ob_disc]`); await wait(p, 200);
  ok(/never reached the server/.test(await p.textContent('.sheet')), 'confirm text warns the data will be lost');
  await p.click('.sheet [data-act=closesheet]'); await wait(p, 150); ok((await q(p)).length === 2, 'cancel keeps it');
  await p.click(`[data-k="${refused.k}"] [data-act=ob_disc]`); await p.click('[data-act=ob_disc_go]'); await wait(p, 300);
  items = await q(p); ok(items.length === 1 && items[0].k === waitItem.k, 'discard removes only that line');
  ok((await p.evaluate(() => window.__M.calls.length)) === before, 'discard makes no server call (local only)');
  // back online: retry all -> sent
  await net(p, false); await p.click('[data-act=ob_retry_all]'); await wait(p, 800);
  ok((await q(p)).length === 0 && /Nothing waiting/.test(await p.textContent('#app')), 'retry all sends the rest; the page shows it is empty');
  await p.context().close();

  // ---------- a server refusal during auto-send keeps the line (never lost) ----------
  p = await open({ queue: [waitItem], w: { err: { save_entry: 'rollout_paper:10-2' } }, settle: 3500 }, '#/home');
  items = await q(p); ok(items.length === 1 && items[0].state === 'refused' && /rollout_paper/.test(items[0].msg), 'refused by the server: kept, marked, with the reason');
  await p.context().close();

  // ---------- drawer has the outbox entry with the count ----------
  p = await open({ queue: [waitItem], w: { net: true } }, '#/home'); await wait(p, 600);
  ok(await p.evaluate(() => window.BOS.outbox.count()) === 1 && (await p.evaluate(() => window.BOS_NAV.entries().some((e) => e.route === 'outbox'))), 'outbox count and drawer entry');
  await p.context().close();
  // ---------- the phone cannot store it: no false “kept on this phone” ----------
  p = await open({}, '#/entry/new/10-2/1'); await fillOk(p); await net(p, true);
  await p.evaluate(() => { const o = Storage.prototype.setItem; Storage.prototype.setItem = function (k, v) { if (String(k).startsWith('bos_eq_')) throw new Error('QuotaExceeded'); return o.call(this, k, v); }; });
  await p.click('[data-act=e_save]'); await wait(p, 500);
  ok(/Could not keep it on this phone/.test(await p.textContent('.sheet')) && await p.locator('#e_notsent').count() === 0, 'storage failure: clear error, no Not-sent-yet claim');
  ok((await p.inputValue('[data-p="lines.0.amount"]')) === '120' && (await p.evaluate(() => window.BOS.outbox.count())) === 0, 'the entry stays on the page; nothing pretended');
  await p.context().close();
  // ---------- another login's records + friendly errors + expired login retried ----------
  const authItem = { ...waitItem, k: 'c:ee333333-3333-4333-8333-333333333333', cid: 'ee333333-3333-4333-8333-333333333333', meta: { client_id: 'ee333333-3333-4333-8333-333333333333' }, state: 'refused', msg: 'JWT expired' };
  p = await open({ queue: [{ ...waitItem, state: 'refused', msg: 'period_closed' }], w: { net: true } }, '#/outbox');
  await p.evaluate(() => localStorage.setItem('bos_eq_u9', JSON.stringify([{ k: 'x' }, { k: 'y' }]))); await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 300); await p.evaluate(() => { location.hash = '#/outbox'; }); await wait(p, 600);
  ok(/Not yours: 2/.test(await p.textContent('#ob_others')), 'notice for records of another login (kept, not deleted)');
  ok(/closed/.test(await p.textContent('#ob_list')) && /owner must allow/.test(await p.textContent('#ob_list')), 'period_closed shown as friendly text');
  ok((await p.evaluate(() => localStorage.getItem('bos_eq_u9'))) !== null, "the other login's queue is untouched");
  await p.context().close();
  p = await open({ queue: [authItem], settle: 3500 }, '#/home');
  ok((await calls(p, 'save_entry')).length === 1 && (await q(p)).length === 0, 'a line refused only because the login had expired is retried automatically');
  await p.context().close();
  await br.close(); srv.close();
  log('errors:', errors.length ? [...new Set(errors)].slice(0, 8) : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); srv.close(); process.exit(1); } })();
