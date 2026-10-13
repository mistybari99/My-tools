// Groups C and D web pieces: parallel month, print & books, guided flows, delegation board, Needs-you list, item badges, service worker files.
// Run: node cd_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8354, srv = C.serve(PORT);
const EXTRA9 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 c.rpc = async (fn, args) => {
  (window.__AC9 = window.__AC9 || []).push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (fn === 'parallel_month_status') return { data: { form: args.p_form, location_id: args.p_loc, month: args.p_month, mode: 'parallel', pairs: T.comparison_pairs.length, days: T.comparison_days.length, match: T.comparison_days.filter((d) => d.result === 'match').length, differ: T.comparison_days.filter((d) => d.result === 'differ').length, differ_explained: 0, waiting: T.comparison_days.filter((d) => d.result === 'waiting').length, month_ended: !!window.__ENDED, decision: null, pass_ready: false }, error: null };
  if (fn === 'comparison_pair_save') { T.comparison_pairs.push({ id: 7, form_code: args.p_form, name_bn: args.p_name_bn, name_en: args.p_name_en, how_paper: args.p_how_paper, how_app: args.p_how_app, is_active: true }); return { data: { id: 7 }, error: null }; }
  if (fn === 'comparison_record') { if (window.__ERR9) { const m = window.__ERR9; window.__ERR9 = null; return { data: null, error: { message: m, code: 'P0001' } }; } T.comparison_days.push({ id: 1, pair_id: args.p_pair, form_code: '14-1', location_id: args.p_loc, day: args.p_day, paper_value: args.p_role === 'paper' ? args.p_value : null, app_value: args.p_role === 'app' ? args.p_value : null, result: 'waiting' }); return { data: { id: 1, result: 'waiting' }, error: null }; }
  if (fn === 'parallel_month_decide') return { data: { result: args.p_pass ? 'pass' : 'fail' }, error: null };
  if (fn === 'paper_books_check') return { data: { issues: [{ type: 'gap', from: 51, to: 60 }], last_paper_no: 100, app_continues_from: 101 }, error: null };
  if (fn === 'paper_book_add') { T.paper_books.push({ id: 5, form_code: args.p_form, location_id: args.p_loc, prefix: args.p_prefix, first_no: args.p_first, last_no: args.p_last, status: 'active', holder: args.p_holder }); return { data: { id: 5 }, error: null }; }
  if (fn === 'print_note_clear') { const n = T.print_notes.find((x) => x.id === args.p_id); if (n) { n.cleared_at = 'now'; n.cleared_on = args.p_printed_on; } return { data: { id: args.p_id }, error: null }; }
  if (fn === 'flow_skip') { T.flow_skips.push({ flow: args.p_flow, step: args.p_step, location_id: args.p_loc, day: args.p_day }); return { data: { ok: true }, error: null }; }
  if (fn === 'set_user_grant') { if (!args.p_allowed) T.user_grants = T.user_grants.filter((g) => !(g.user_id === args.p_user && g.grant_code === args.p_code)); else T.user_grants.push({ id: 9, user_id: args.p_user, grant_code: args.p_code, location_id: args.p_loc, valid_until: args.p_until }); return { data: null, error: null }; }
  if (fn === 'needs_you_oldest') return { data: [{ kind: 'entry', id: 'e1', label: '10-2 #9002', location_id: 1, since: new Date(Date.now() - 9 * 3600e3).toISOString(), route: 'entry/e1' }, { kind: 'release', id: '3', label: 'cash_over', location_id: 1, since: new Date(Date.now() - 3 * 3600e3).toISOString(), route: 'releases' }], error: null };
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('slip written on paper'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA9 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const T = data.tables;
    T.form_rollout = [{ form_code: '14-1', location_id: 1, mode: 'parallel' }]; T.comparison_pairs = o.pairs ? [{ id: 7, form_code: '14-1', name_bn: 'ড্রয়ার', name_en: 'Drawer', how_paper: 'paper page', how_app: 'app calc', is_active: true }] : []; T.comparison_days = []; T.parallel_months = [];
    T.paper_books = [{ id: 1, form_code: '14-1', location_id: 1, prefix: null, first_no: 1, last_no: 50, status: 'active', holder: 'Karim', issued_on: '2026-10-01' }];
    T.print_notes = [{ id: 3, form_code: null, location_id: 1, reason: 'place renamed: A -> B', change_to: 'Change the place line', created_at: '2026-10-10T00:00:00Z', cleared_at: null }];
    T.flow_skips = []; T.exceptions = T.exceptions || []; T.grant_defs = [{ grant_code: 'cash_move', module: 'cash', sort: 1, label_bn: 'ক্যাশ লেনদেন', label_en: 'Cash moves', window_type: 'once' }]; T.user_grants = [{ id: 1, user_id: 'u1', grant_code: 'cash_move', location_id: 1, valid_until: new Date(Date.now() + 2 * 864e5).toISOString() }];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__ENDED=${o.ended ? 'true' : 'false'};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1300); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC9 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // parallel: no pair
  let p = await open('#/parallel');
  ok(/No pair yet/.test(await p.evaluate(() => document.body.innerText)), 'no pair yet message (nothing invented)');
  await p.evaluate(() => { document.querySelector('#pl_body details').open = true; }); await p.fill('#pp_bn', 'ড্রয়ার'); await p.click('[data-act=pl_pair]'); await wait(p, 500);
  ok((await calls(p, 'comparison_pair_save')).length === 1, 'owner names a pair'); await noOverflow(p, 'parallel');
  p = await open('#/parallel', { pairs: true });
  await p.fill('#pr_val', '1000'); await p.click('[data-act=pl_rec][data-v=paper]'); await wait(p, 500);
  let c = await calls(p, 'comparison_record'); ok(c.length === 1 && c[0].p_role === 'paper' && c[0].p_value === 1000 && c[0].p_pair === 7, 'paper figure sent');
  await p.evaluate(() => { window.__ERR9 = 'keeper_is_enterer'; }); await p.fill('#pr_val', '1000'); await p.click('[data-act=pl_rec][data-v=app]'); await wait(p, 400);
  ok(/keeper cannot also record/.test(await p.evaluate(() => document.body.innerText)), 'friendly keeper/enterer text');
  ok(await p.locator('[data-act=pl_decide]').count() === 0 || /not over/.test(await p.evaluate(() => document.body.innerText)), 'pass/fail not offered before the month ends');
  p = await open('#/parallel', { pairs: true, ended: true });
  ok(await p.locator('[data-act=pl_decide]').count() === 2, 'pass and fail offered after the month ends');
  await p.screenshot({ path: SP + '/cd_parallel.png', fullPage: true });
  await p.click('[data-act=pl_decide][data-v="0"]'); await wait(p, 400); c = await calls(p, 'parallel_month_decide'); ok(c.length === 1 && c[0].p_pass === false, 'fail sent');

  // print & books
  p = await open('#/printbooks');
  ok(/Gap/.test(await p.evaluate(() => document.body.innerText)) && /101/.test(await p.evaluate(() => document.body.innerText)), 'gap flagged and the app continues from 101');
  ok(/place renamed/.test(await p.evaluate(() => document.body.innerText)), 'print note listed');
  await p.click('[data-act=pb_clear]'); await wait(p, 500); c = await calls(p, 'print_note_clear'); ok(c.length === 1 && c[0].p_id === 3, 'note cleared with a date');
  await p.evaluate(() => { document.querySelector('#pb_body details').open = true; }); await p.fill('#bk_first', '61'); await p.fill('#bk_last', '100'); await p.click('[data-act=pb_add]'); await wait(p, 500);
  c = await calls(p, 'paper_book_add'); ok(c.length === 1 && c[0].p_first === 61 && c[0].p_last === 100, 'book added'); await noOverflow(p, 'printbooks'); await p.screenshot({ path: SP + '/cd_books.png', fullPage: true });

  // flows
  p = await open('#/flow');
  ok(await p.locator('a.card.item').count() === 4, 'four routines listed');
  p = await open('#/flow/close');
  ok(await p.locator('[data-step]').count() === 8, 'close day has 8 steps'); ok(await p.locator('[data-step="deposit"] .chip').first().textContent().then((t) => /Check manually/.test(t)), 'a link-only step is never ticked');
  await p.click('[data-step="deposit"] [data-act=fl_skip]'); await wait(p, 500); c = await calls(p, 'flow_skip'); ok(c.length === 1 && c[0].p_step === 'deposit' && c[0].p_note.length >= 3, 'skip with a note');
  ok(/Skipped/.test(await p.textContent('[data-step="deposit"]')), 'skipped step shown'); await noOverflow(p, 'flow'); await p.screenshot({ path: SP + '/cd_flow.png', fullPage: true });

  // delegation
  p = await open('#/delegation');
  ok(/Cash moves/.test(await p.evaluate(() => document.body.innerText)) && /Ends soon/.test(await p.evaluate(() => document.body.innerText)), 'right listed with an ends-soon marker');
  await p.click('[data-act=dg_remove]'); await wait(p, 500); c = await calls(p, 'set_user_grant'); ok(c.length === 1 && c[0].p_allowed === false, 'remove sends allowed=false'); await noOverflow(p, 'delegation');

  // home needs-you list
  p = await open('#/home');
  ok(await p.locator('.dash-row .dl', { hasText: '#9002' }).count() === 1, 'Needs-you row shows the oldest entry'); 
  const rowsTxt = await p.locator('.dash-row .dl').allTextContents(); const i1 = rowsTxt.findIndex((t) => /9002/.test(t)), i2 = rowsTxt.findIndex((t) => /cash_over/.test(t)); ok(i1 >= 0 && i2 > i1, 'oldest first');

  // files
  ok(fs.existsSync('/home/user/My-tools/web/sw.js') && /bos-sw-/.test(fs.readFileSync('/home/user/My-tools/web/sw.js', 'utf8')), 'service worker file present');
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
