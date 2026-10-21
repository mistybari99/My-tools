// CRM-G screens: Party and gift enquiries (#/crmleads) and My tasks (#/crmtasks). Server calls are stand-ins; the real SQL is tested in supabase/phase323_test.sql .. phase327_test.sql.
// Covers: modules OFF note, board with flags and filters, new enquiry (essentials first, More fold, validation before the server), enquiry sheet buttons by right, quote with items and validity,
// lost needs a reason, reopen needs a reason, convert (channel needed), report, lists (owner only), server refusals shown in words, My tasks (overdue first, done, snooze, skip with a reason,
// new task, assign only with the right), Home strip text, info sheet texts, 360px width with no horizontal scroll, no console errors.
// Run: node crm_leads_test.js <abs tests/web dir> [shots dir]     (serves ../../web of THIS checkout and injects the two script tags; the routes are registered in ia.js by the integrator)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web'); const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = 8575;
const TAGS = ['crm_leads.js', 'crm_tasks.js'];
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') { let h = b.toString('utf8'); TAGS.forEach((t) => { if (!h.includes('src="' + t + '"')) h = h.replace('</body>', '<script src="' + t + '"></script></body>'); }); b = Buffer.from(h); }
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const now = Date.now(); const iso = (ms) => new Date(now + ms).toISOString(); const day = new Date(now + 6 * 3600e3).toISOString().slice(0, 10);
const LISTS = { can_edit: true,
  lost_reason: [{ code: 'price_high', label: 'Price was too high', active: true }, { code: 'other', label: 'Other (write a note)', active: true }],
  source: [{ code: 'phone', label: 'Phone call', active: true }, { code: 'other', label: 'Other', active: true }], occasion: [{ code: 'wedding', label: 'Wedding or engagement', active: true }, { code: 'other', label: 'Other', active: true }] };
const ST = { signed_in: true, uid: 'u1', lead_on: true, task_on: true, reminder_on: false, is_owner: true, can_create_lead: true, can_manage_leads: true, sees_all_outlets: true, can_assign_tasks: true, sees_all_tasks: true, can_edit_lists: true,
  win_needs_quote: false, quote_valid_days: null, task_default_due_hours: null, my_outlets: [{ id: 1, name: 'Main showroom' }, { id: 2, name: 'Second branch' }], staff_here: [{ id: 'u1', staff_id: 'test_s1', name: 'test_one' }, { id: 'u2', staff_id: 'test_s2', name: 'test_two' }] };
const card = (o) => Object.assign({ id: 'l1', lead_no: 1, location_id: 1, contact_name: 'test_party_one', contact_phone: '01812345678', stage: 'enquiry', est_value: 50000, event_date: day, owner_staff: 'test_s1', next_follow_up: null, overdue: false, stale: false, quote_total: null, converted: false }, o);
const BOARD = { on: true, today: day, overdue: 1, stale: 1, stages: [
  { stage: 'enquiry', count: 1, value: 50000, cards: [card({})] }, { stage: 'quoted', count: 1, value: 9000, cards: [card({ id: 'l2', lead_no: 2, contact_name: 'test_party_two', stage: 'quoted', quote_total: 9000, overdue: true, next_follow_up: iso(-3600e3) })] },
  { stage: 'following_up', count: 1, value: 0, cards: [card({ id: 'l3', lead_no: 3, contact_name: 'test_party_three', stage: 'following_up', stale: true, est_value: null })] },
  { stage: 'won', count: 0, value: 0, cards: [] }, { stage: 'lost', count: 0, value: 0, cards: [] }] };
const SHEET = (o) => ({ lead: Object.assign({ id: 'l1', lead_no: 1, location_id: 1, contact_name: 'test_party_one', contact_phone: '01812345678', customer_name: null, source: 'phone', occasion: 'wedding', event_date: day, guests: 120, est_value: 50000, stage: 'enquiry', lost_reason: null,
    owner_staff: 'test_s1', owner_user: 'u1', next_follow_up: null, overdue: false, stale: false, online_order_id: null, entry_id: null, note: null }, (o && o.lead) || {}),
  quotes: (o && o.quotes) || [], events: [{ id: 1, at: iso(-86400e3), kind: 'created', from: null, to: 'enquiry', note: null, by: 'test_s1' }], tasks: [],
  can: Object.assign({ edit: true, note: true, quote: true, move: true, assign: true, close_lost: true, reopen: false, convert: true }, (o && o.can) || {}) });
const REPORT = { on: true, from: day, to: day, created: 7, won: 3, lost: 2, won_value: 30000, lost_value: 8000, win_rate_pct: 60, avg_days_to_close: 4.5, open_now: 2, open_value: 5000, overdue_open: 1, stale_open: null, reopened: 0,
  lost_by_reason: [{ code: 'price_high', label: 'Price was too high', count: 2, value: 8000 }], by_owner: [{ owner_staff: 'test_s1', created: 4, won: 2, lost: 1, won_value: 20000 }], by_source: [{ code: 'phone', label: 'Phone call', created: 5, won: 2, lost: 1 }], by_occasion: [] };
const TASKS = { on: true, now: iso(0), scope: 'mine', counts: { overdue: 2, today: 1, upcoming: 1, snoozed: 1 },
  overdue: [{ id: 't1', kind: 'call', title: 'test_call about cake', due_at: iso(-50 * 3600e3), overdue_hours: 50, lead_id: 'l1', lead_no: 1, lead_name: 'test_party_one', assigned_staff: 'test_s1', source: 'lead' },
            { id: 't2', kind: 'visit', title: 'test_second overdue', due_at: iso(-5 * 3600e3), overdue_hours: 5, assigned_staff: 'test_s1', source: 'manual' }],
  today: [{ id: 't3', kind: 'follow_up', title: 'test_due later today', due_at: iso(3600e3), assigned_staff: 'test_s1', source: 'manual' }],
  upcoming: [{ id: 't4', kind: 'other', title: 'test_next week', due_at: iso(5 * 86400e3), assigned_staff: 'test_s1', source: 'manual' }],
  snoozed: [{ id: 't5', kind: 'message', title: 'test_snoozed one', due_at: iso(-3600e3), snooze_until: iso(4 * 3600e3), assigned_staff: 'test_s1', source: 'manual' }], recent_done: [] };
function mk(o = {}) { return C.mkData(base, o); }
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.cg = Object.assign({ err: {}, st: ${JSON.stringify(ST)}, lists: ${JSON.stringify(LISTS)}, board: ${JSON.stringify(BOARD)}, sheet: ${JSON.stringify(SHEET())}, report: ${JSON.stringify(REPORT)}, tasks: ${JSON.stringify(TASKS)}, channels: [{ id: 7, code: 'test_ch', name_bn: 'test_phone_channel' }] }, window.__W || {});
 c.rpc = async (fn, args) => {
  if (!/^_crmg_/.test(fn) && fn !== 'sales_channels_list') return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === '_crmg_status') return { data: clone(W.st), error: null };
  if (fn === '_crmg_lists') return { data: clone(W.lists), error: null };
  if (fn === '_crmg_lead_board') return { data: clone(W.board), error: null };
  if (fn === '_crmg_lead_get') return { data: clone(W.sheet), error: null };
  if (fn === '_crmg_lead_report') return { data: clone(W.report), error: null };
  if (fn === '_crmg_my_tasks') return { data: clone(W.tasks), error: null };
  if (fn === '_crmg_task_counts') return { data: W.counts || { on: true, open: 3, overdue: 2, today: 1, snoozed: 0, lead_on: true, leads_overdue: 1 }, error: null };
  if (fn === 'sales_channels_list') return { data: clone(W.channels), error: null };
  if (fn === '_crmg_lead_save') return { data: { id: 'l9', lead_no: 9, stage: 'enquiry', same_phone_open_leads: [] }, error: null };
  if (fn === '_crmg_lead_convert') return { data: { id: 'l1', order_no: '12', online_order_id: 'o1' }, error: null };
  return { data: { ok: true }, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } else if (process.env.DBG) log('ok:', m); };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__W=${JSON.stringify(o.w || {})};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const txt = (p, s) => p.textContent(s);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth); ok(r <= 1, 'no horizontal scroll at 360px: ' + m + ' (' + r + ')'); };

  // ---- OFF: a short note, nothing else
  let p = await open({ w: { st: Object.assign({}, ST, { lead_on: false, task_on: false }) } }, '#/crmleads');
  ok(/switched off/.test(await txt(p, '#cl_body')) && await p.locator('[data-act=cl_new]').count() === 0, 'enquiries OFF: a note, no button');
  await p.goto(`http://localhost:${PORT}/#/crmtasks`); await wait(p, 900);
  ok(/Tasks are switched off/.test(await txt(p, '#ct_body')) && await p.locator('[data-act=ct_new]').count() === 0, 'tasks OFF: a note, no button');
  await noOverflow(p, 'off notes'); await p.close();

  // ---- board
  p = await open({}, '#/crmleads');
  let t = await txt(p, '#cl_body');
  ok(/Enquiry \(1\)/.test(t) && /Quoted \(1\)/.test(t) && /Following up \(1\)/.test(t) && /Won \(0\)/.test(t) && /Lost \(0\)/.test(t), 'five stages with counts');
  ok(/Follow-up missed/.test(t) && /Stale/.test(t) && /1 follow-ups missed/.test(await txt(p, '#cl_sum')), 'missed follow-up and stale flags');
  ok(await p.locator('[data-lead]').count() === 3 && /test_party_two/.test(t) && /৳ 9,000/.test(t), 'cards with the quote value');
  ok(await p.locator('#cl_loc').count() === 1 && await p.locator('#cl_mine').count() === 1, 'outlet filter (two outlets) and Mine only');
  await p.check('#cl_mine'); await wait(p, 300);
  let c = await calls(p, '_crmg_lead_board'); ok(c.length >= 2 && c[c.length - 1].p_owner === 'u1', 'Mine only asks the server for her own enquiries');
  await p.selectOption('#cl_loc', '2'); await wait(p, 300);
  c = await calls(p, '_crmg_lead_board'); ok(c[c.length - 1].p_loc === 2, 'outlet filter sent');
  await p.screenshot({ path: OUT + '/cg_board.png' }); await noOverflow(p, 'board'); await p.close();

  // ---- new enquiry: essentials first, More fold, validation, payload
  p = await open({}, '#/crmleads'); await p.click('[data-act=cl_new]'); await wait(p, 200);
  ok(await p.locator('#cf_name').isVisible() && await p.locator('#cf_phone').isVisible() && await p.locator('#cf_event').isVisible() && !(await p.locator('#cf_source').isVisible()), 'essentials visible (name, phone, event date); source and the rest are in More');
  await p.click('[data-act=cl_save]'); await wait(p, 200);
  ok(/Write the name/.test(await txt(p, '#toast')) && (await calls(p, '_crmg_lead_save')).length === 0, 'an empty name is stopped before the server');
  await p.fill('#cf_name', 'test_new_party'); await p.fill('#cf_phone', '01911112222'); await p.fill('#cf_event', day);
  await p.click('#cl_form summary'); await p.selectOption('#cf_source', 'phone'); await p.fill('#cf_guests', '0'); await p.click('[data-act=cl_save]'); await wait(p, 200);
  ok(/Guests must be/.test(await txt(p, '#toast')) && (await calls(p, '_crmg_lead_save')).length === 0, 'guests of zero stopped before the server');
  await p.fill('#cf_guests', '80'); await p.fill('#cf_value', '12,500'); await p.click('[data-act=cl_save]'); await wait(p, 300);
  c = await calls(p, '_crmg_lead_save'); ok(c.length === 1 && c[0].p_id === null && c[0].p_loc === 1 && c[0].p_data.contact_name === 'test_new_party' && c[0].p_data.guests === 80 && c[0].p_data.est_value === 12500 && c[0].p_data.source === 'phone' && !!c[0].p_client, 'enquiry sent with a client key, numbers parsed');
  await p.screenshot({ path: OUT + '/cg_new.png' }); await noOverflow(p, 'after save'); await p.close();

  // ---- the sheet, by right
  p = await open({}, '#/crmleads/l1'); await wait(p, 500); t = await txt(p, '#cl_sheet');
  ok(/#1 · test_party_one/.test(t) && /Enquiry/.test(t) && /120 guests/.test(t) && /Wedding or engagement/.test(t), 'the sheet shows the facts');
  ok(await p.locator('#cl_sheet [data-act=cl_panel][data-v=quote]').count() === 1 && await p.locator('#cl_sheet [data-act=cl_panel][data-v=won]').count() === 1, 'Quote, Follow up and Won are the visible actions');
  ok(await p.locator('#cl_sheet details [data-act=cl_panel][data-v=lost]').count() === 1 && !(await p.locator('#cl_sheet details [data-act=cl_panel][data-v=lost]').isVisible()), 'Close as lost is behind More');
  // lost: a reason is needed
  await p.click('#cl_sheet summary'); await p.click('[data-act=cl_panel][data-v=lost]'); await wait(p, 200);
  await p.click('[data-act=cl_lost_go]'); await wait(p, 200);
  ok(/Choose a lost reason/.test(await txt(p, '#toast')) && (await calls(p, '_crmg_lead_stage')).length === 0, 'lost without a reason is stopped before the server');
  await p.selectOption('#cp_reason', 'price_high'); await p.click('[data-act=cl_lost_go]'); await wait(p, 300);
  c = await calls(p, '_crmg_lead_stage'); ok(c.length === 1 && c[0].p_to === 'lost' && c[0].p_args.lost_reason === 'price_high', 'lost sent with the listed reason');
  await p.screenshot({ path: OUT + '/cg_sheet.png' }); await noOverflow(p, 'sheet'); await p.close();

  // ---- quote with items and validity; server refusal in words
  p = await open({ w: { err: { _crmg_quote_save: 'validity_required: write the date' } } }, '#/crmleads/l1'); await wait(p, 500);
  await p.click('[data-act=cl_panel][data-v=quote]'); await wait(p, 300);
  await p.fill('#ql_d0', 'test_cake 2 kg'); await p.fill('#ql_q0', '2'); await p.fill('#ql_p0', '900');
  await p.click('[data-act=cl_qsave][data-send="1"]'); await wait(p, 300);
  ok(/date until which the quote is valid/.test(await txt(p, '#toast')), 'the server refusal validity_required is shown in words');
  await p.fill('#ql_q0', '0'); await p.click('[data-act=cl_qsave][data-send="0"]'); await wait(p, 200);
  ok(/Quantity must be above zero/.test(await txt(p, '#toast')), 'a zero quantity is stopped before the server');
  await p.fill('#ql_q0', '2'); await p.fill('#qq_valid', day); await p.click('[data-act=cl_qsave][data-send="0"]'); await wait(p, 300);
  c = await calls(p, '_crmg_quote_save'); ok(c.length === 2 && c[1].p_data.items.length === 1 && c[1].p_data.items[0].desc === 'test_cake 2 kg' && c[1].p_data.items[0].price === 900 && c[1].p_data.valid_until === day && c[1].p_data.send === false && !!c[1].p_client, 'quote lines, price, validity and a client key sent');
  await p.close();

  // ---- reopen needs a reason; convert needs a channel
  p = await open({ w: { sheet: SHEET({ lead: { stage: 'lost', lost_reason: 'price_high' }, can: { reopen: true, edit: false, quote: false, move: false, close_lost: false } }) } }, '#/crmleads/l1'); await wait(p, 500);
  ok(/Lost: Price was too high/.test(await txt(p, '#cl_sheet')) && await p.locator('[data-act=cl_panel][data-v=quote]').count() === 0, 'a lost enquiry shows the reason and no quote button');
  await p.click('#cl_sheet summary'); await p.click('[data-act=cl_panel][data-v=reopen]'); await wait(p, 200); await p.fill('#cp_reason', 'ab'); await p.click('[data-act=cl_reopen_go]'); await wait(p, 200);
  ok(/Write a reason/.test(await txt(p, '#toast')) && (await calls(p, '_crmg_lead_reopen')).length === 0, 'reopen without a real reason is stopped before the server');
  await p.fill('#cp_reason', 'test_customer came back'); await p.click('[data-act=cl_reopen_go]'); await wait(p, 300);
  c = await calls(p, '_crmg_lead_reopen'); ok(c.length === 1 && c[0].p_reason === 'test_customer came back' && c[0].p_to === 'enquiry', 'reopen sent with the reason'); await p.close();
  p = await open({}, '#/crmleads/l1'); await wait(p, 500);
  await p.click('#cl_sheet summary'); await p.click('[data-act=cl_panel][data-v=convert]'); await wait(p, 300);
  ok(await p.locator('#cp_ch option').count() === 2, 'the sales channels come from the existing channel list');
  await p.click('[data-act=cl_convert_go]'); await wait(p, 200);
  ok(/Choose the sales channel/.test(await txt(p, '#toast')) && (await calls(p, '_crmg_lead_convert')).length === 0, 'an order without a channel is stopped before the server');
  await p.selectOption('#cp_ch', '7'); await p.click('[data-act=cl_convert_go]'); await wait(p, 300);
  c = await calls(p, '_crmg_lead_convert'); ok(c.length === 1 && c[0].p_kind === 'online_order' && c[0].p_args.channel_id === 7 && !!c[0].p_client, 'convert sent: order kind, channel, client key');
  ok(/Order 12 made/.test(await txt(p, '#toast')), 'the new order number is shown'); await noOverflow(p, 'convert'); await p.close();
  p = await open({ w: { err: { _crmg_lead_convert: 'already_converted: x' } } }, '#/crmleads/l1'); await wait(p, 500);
  await p.click('#cl_sheet summary'); await p.click('[data-act=cl_panel][data-v=convert]'); await wait(p, 200); await p.selectOption('#cp_kind', 'form_20_4'); await p.click('[data-act=cl_convert_go]'); await wait(p, 300);
  ok(/already has its order or form/.test(await txt(p, '#toast')), 'a second conversion is refused in words'); await p.close();

  // ---- a person without the manager right: no manager buttons
  p = await open({ w: { sheet: SHEET({ can: { assign: false, close_lost: false, convert: false, reopen: false } }), st: Object.assign({}, ST, { can_manage_leads: false, is_owner: false, can_edit_lists: false }) } }, '#/crmleads/l1'); await wait(p, 500);
  ok(await p.locator('[data-act=cl_panel][data-v=lost]').count() === 0 && await p.locator('[data-act=cl_panel][data-v=assign]').count() === 0 && await p.locator('[data-act=cl_panel][data-v=convert]').count() === 0, 'without the right: no Close as lost, Give to, Turn into an order');
  await p.close();

  // ---- report and lists
  p = await open({}, '#/crmleads'); await p.click('[data-act=cl_tab][data-v=report]'); await wait(p, 400); t = await txt(p, '#cl_body');
  ok(/Enquiries made/.test(t) && /60%/.test(t) && /Price was too high/.test(t) && /Why enquiries were lost/.test(t), 'report tiles, win rate and lost reasons');
  await p.fill('#cr_from', day); await p.click('[data-act=cl_rep_go]'); await wait(p, 300);
  c = await calls(p, '_crmg_lead_report'); ok(c.length >= 2 && c[c.length - 1].p_from === day, 'report asked for the chosen dates'); await noOverflow(p, 'report');
  await p.click('[data-act=cl_tab][data-v=lists]'); await wait(p, 300);
  ok(await p.locator('[data-list]').count() === 3 && await p.locator('[data-list=lost_reason] [data-c=other]').count() === 0, 'three lists; the entry Other has no remove button');
  await p.fill('#cl_new_source', 'Fair or exhibition'); await p.click('[data-act=cl_list_add][data-k=source]'); await wait(p, 300);
  c = await calls(p, '_crmg_list_save'); ok(c.length === 1 && c[0].p_kind === 'source' && c[0].p_code === 'fair_or_exhibition' && c[0].p_label === 'Fair or exhibition', 'a new list entry is sent with a made-up code and its label'); await p.close();
  p = await open({ w: { lists: Object.assign({}, LISTS, { can_edit: false }), st: Object.assign({}, ST, { can_edit_lists: false }) } }, '#/crmleads');
  ok(await p.locator('[data-act=cl_tab][data-v=lists]').count() === 0, 'the Lists tab is hidden for a person who cannot edit the lists'); await p.close();

  // ---- My tasks
  p = await open({}, '#/crmtasks'); t = await txt(p, '#ct_body');
  ok(/2 overdue · 1 due today · 1 later · 1 snoozed/.test(await txt(p, '#ct_sum')), 'summary line');
  const order = await p.$$eval('[data-task] b', (els) => els.map((e) => e.textContent));
  ok(order[0] === 'test_call about cake' && order[1] === 'test_second overdue' && order[2] === 'test_due later today' && order[3] === 'test_next week', 'overdue first (oldest first), then today, then later');
  ok(/50 h late|2 days late/.test(t) && /Enquiry 1 · test_party_one/.test(t), 'how late, and a link to the enquiry');
  ok(await p.locator('details[data-sec=snoozed]').count() === 1, 'snoozed tasks are in a fold');
  await p.click('[data-task=t3] [data-act=ct_done]'); await wait(p, 300);
  c = await calls(p, '_crmg_task_done'); ok(c.length === 1 && c[0].p_id === 't3', 'Done sent');
  await p.selectOption('[data-task=t1] select[data-snooze]', '3'); await wait(p, 300);
  c = await calls(p, '_crmg_task_snooze'); ok(c.length === 1 && c[0].p_id === 't1' && c[0].p_hours === 3, 'Snooze 3 hours sent');
  await p.click('[data-task=t2] [data-act=ct_more]'); await wait(p, 200); await p.click('[data-task=t2] [data-act=ct_skip]'); await wait(p, 200);
  ok(/Write a reason/.test(await txt(p, '#toast')) && (await calls(p, '_crmg_task_skip')).length === 0, 'skip without a reason is stopped before the server');
  await p.fill('#ct_skip_t2', 'test_no longer needed'); await p.click('[data-task=t2] [data-act=ct_skip]'); await wait(p, 300);
  c = await calls(p, '_crmg_task_skip'); ok(c.length === 1 && c[0].p_reason === 'test_no longer needed', 'skip sent with the reason');
  await p.click('[data-act=ct_new]'); await wait(p, 200); await p.click('[data-act=ct_save]'); await wait(p, 200);
  ok(/Write what has to be done/.test(await txt(p, '#toast')), 'a task needs a title');
  ok(await p.locator('#ct_who').count() === 1, 'the Give to choice shows only with the assign right');
  await p.fill('#ct_title', 'test_new task'); await p.fill('#ct_due', day + 'T10:30'); await p.click('[data-act=ct_save]'); await wait(p, 300);
  c = await calls(p, '_crmg_task_save'); ok(c.length === 1 && c[0].p_data.title === 'test_new task' && c[0].p_data.due_at === day + 'T10:30:00+06:00' && !!c[0].p_client, 'task sent with a Dhaka time and a client key');
  await p.screenshot({ path: OUT + '/cg_tasks.png' }); await noOverflow(p, 'my tasks'); await p.close();
  p = await open({ w: { st: Object.assign({}, ST, { can_assign_tasks: false, sees_all_tasks: false, can_manage_leads: false, is_owner: false }) } }, '#/crmtasks'); await p.click('[data-act=ct_new]'); await wait(p, 200);
  ok(await p.locator('#ct_who').count() === 0 && await p.locator('[data-act=ct_scope]').count() === 0, 'a plain user has no Give to and no Team tab'); await p.close();
  p = await open({ w: { tasks: Object.assign({}, TASKS, { counts: { overdue: 0, today: 0, upcoming: 0, snoozed: 0 }, overdue: [], today: [], upcoming: [], snoozed: [] }) } }, '#/crmtasks');
  ok(/Nothing to do/.test(await txt(p, '#ct_body')), 'an empty list says so'); await p.close();
  p = await open({ w: { err: { _crmg_task_done: 'task_closed: x' } } }, '#/crmtasks'); await p.click('[data-task=t3] [data-act=ct_done]'); await wait(p, 300);
  ok(/already done or skipped/.test(await txt(p, '#toast')), 'a server refusal is shown in words'); await p.close();

  // ---- exports for the integrator
  p = await open({}, '#/crmtasks');
  const ex = await p.evaluate(async () => ({ strip: await window.BOS.crmTasks.stripHTML(), info: Object.keys(window.BOS.crmLeads.INFO || {}).length, hasTrack: typeof window.BOS.crmLeads.track }));
  ok(/My tasks/.test(ex.strip) && /2 overdue/.test(ex.strip) && /1 due today/.test(ex.strip) && /href="#\/crmtasks"/.test(ex.strip), 'Home strip text and link');
  ok(ex.info === 19 && ex.hasTrack === 'function', 'info texts for 19 keys and the inbox hook function are exported');
  const off = await p.evaluate(async () => { window.__M.cg.counts = { on: false }; return await window.BOS.crmTasks.stripHTML(); });
  ok(off === '', 'Home strip is empty while tasks are off');
  await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
