// Customer feedback and complaints web piece (#/crmfeedback). Package CRM-H.
// Run: node crm_feedback_test.js <abs tests/web dir>      (web/crm_feedback.js, the index.html script tag and the one ia.js registry line are injected here; the integrator adds the real ones, docs/integration/CRM-H.md)
// English labels only (owner rule 5): the page must read the same in bn, mix and en. 360 px wide, no horizontal scroll.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8468, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
// the exact registry line printed in docs/integration/CRM-H.md (the test injects the same text after the freshness line)
const IA_LINE = fs.readFileSync(__dirname + '/../../docs/integration/CRM-H.md', 'utf8').split('\n').find((l) => l.trim().startsWith("rec('crmfeedback'"));
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__CF = window.__CF || {};
 R.calls = R.calls || [];
 c.rpc = async (fn, args) => {
  if (!/^_crmh_|^sale_returns_for$/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.missing && /^_crmh_/.test(fn)) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + fn } };
  if (R.deny && fn === '_crmh_settings') return { data: null, error: { message: 'not allowed', code: 'P0001' } };
  if (R.err && R.err[fn]) { const m = R.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  const map = { _crmh_settings: R.set, _crmh_feedback_settings: R.fset, _crmh_counts: R.cnt, _crmh_complaint_list: R.list, _crmh_feedback_list: R.rat, _crmh_report: R.rep, _crmh_repeat_list: R.repeats,
    _crmh_complaint_get: R.get, sale_returns_for: R.sr };
  if (fn === '_crmh_complaint_get' && R.getById) return { data: R.getById[args.p_id], error: null };
  if (fn in map) return { data: map[fn], error: null };
  if (fn === '_crmh_complaint_save') return { data: { id: 'new1', ticket_no: 99, dup: false }, error: null };
  if (fn === '_crmh_sla_scan') return { data: { marked: R.scanMarked === undefined ? 2 : R.scanMarked, ran: true }, error: null };
  return { data: { ok: true }, error: null };
 }; return c; }; })();`;
const clone = (x) => JSON.parse(JSON.stringify(x));
const CATS = [{ code: 'taste', label: 'Taste' }, { code: 'smell', label: 'Smell or spoiled' }, { code: 'sick', label: 'Customer fell ill' }, { code: 'other', label: 'Other' }];
const SET = { on: true, sla_hours: { low: null, medium: 48, high: 8, critical: 2 }, categories: CATS, resolutions: [{ code: 'explained', label: 'Explained to the customer' }, { code: 'replaced', label: 'Goods replaced' }],
  close_reasons: [{ code: 'no_contact', label: 'Customer could not be reached' }, { code: 'duplicate', label: 'Same as another complaint' }], may_log: true, may_manage: true, may_view: true, is_owner: true };
const FSET = { on: true, low_max: 2, window_days: null, may_log: true, may_manage: true };
const row = (o) => Object.assign({ id: 'c1', ticket_no: 7, location_id: 1, location: 'Islamia Main', customer_id: null, customer_name: 'test_cust_a', customer_phone: '018****01', sale_id: 'sale1', item_name: 'test_item_a', category: 'taste', category_label: 'Taste',
  severity: 'medium', food_safety: false, description: 'test too sweet', status: 'open', owner_user: null, owner_name: null, due_at: '2026-10-18T08:00:00Z', sla_state: 'running', minutes_left: 1200, repeat_flag: false, repeat_count: 0, returns: { n: 0, amount: 0 }, created_at: '2026-10-16T08:00:00Z' }, o || {});
const LIST = { total: 3, rows: [
  row({ id: 'c1', ticket_no: 7, sla_state: 'overdue', minutes_left: -150, severity: 'high', category: 'sick', category_label: 'Customer fell ill', food_safety: true }),
  row({ id: 'c2', ticket_no: 8, repeat_flag: true, repeat_count: 2, status: 'in_progress' }),
  row({ id: 'c3', ticket_no: 9, severity: 'low', sla_state: 'none', minutes_left: null, due_at: null })] };
const RAT = { total: 2, average: 3.5, needs_call: 1, rows: [
  { id: 'f1', at: '2026-10-16T08:00:00Z', location: 'Islamia Main', rating: 1, comment: 'test cold and stale', channel: 'counter', receipt: 77, customer_name: 'test_cust_a', follow_up: 'needed', complaint_id: null },
  { id: 'f2', at: '2026-10-16T07:00:00Z', location: 'Islamia Main', rating: 5, comment: null, channel: 'phone', order_no: 12, follow_up: 'none', complaint_id: null }] };
const REP = { from: '2026-09-17', to: '2026-10-16', by: 'outlet', note: null, totals: { complaints: 4, ratings: 2, average_rating: 3.5 },
  complaints: [{ key: '1', label: 'Islamia Main', total: 4, open: 2, resolved: 1, closed_no_result: 1, overdue_now: 1, breached: 1, sla_met: 1, sla_missed: 0, food_safety: 1, repeat: 2, avg_resolve_hours: 3.5, refund_total: 100 }],
  ratings: [{ key: '1', label: 'Islamia Main', n: 2, average: 3.5, stars: { 1: 1, 2: 0, 3: 0, 4: 0, 5: 1 }, needs_call: 1 }] };
const DETAIL = (status, extra) => ({ complaint: row(Object.assign({ id: 'c1', status, sla_state: status === 'open' ? 'running' : 'met' }, extra || {})), events: [{ at: '2026-10-16T08:00:00Z', kind: 'created', to: 'open', note: 'test too sweet', by: 't' }],
  returns: [], return_hint: { sale_id: 'sale1', receipt: 5, can_return: true, note: 'x' }, earlier_by_same_customer: [{ id: 'p', ticket_no: 3, at: '2026-10-01T08:00:00Z', status: 'closed', category: 'taste' }], can_manage: true });
const BASE = () => ({ calls: [], set: SET, fset: FSET, cnt: { on: true, open: 3, overdue: 1, food_safety: 1, repeat: 1, unowned: 2 }, list: LIST, rat: RAT, rep: REP, repeats: { days: 30, min: 2, scope: 'customer_item', rows: [{ customer_name: 'test_cust_a', item_name: 'test_item_a', complaints: 3, open: 1 }] },
  get: DETAIL('open'), sr: { returns: [{ id: 'ret1', amount: 100, status: 'done', at: '2026-10-16T09:00:00Z' }, { id: 'ret2', amount: 20, status: 'void', at: '2026-10-16T09:00:00Z' }] } });

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/crm_feedback\.js/.test(h) ? h : h.replace('</body>', '<script src="crm_feedback.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    await p.route('**/ia.js', async (r) => { const res = await r.fetch(); const t = await res.text(); const a = "  rec('freshness', 'acc'"; await r.fulfill({ response: res, body: IA_LINE && t.includes(a) ? t.replace(a, IA_LINE + '\n' + a) : t }); });
    const data = C.mk(base, {});
    data.tables.sales = [{ id: 'sale1', receipt: 77, location_id: 1, lines: [{ item_id: 'it1', name: 'test_item_a', qty: 1 }, { item_id: 'it2', name: 'test_item_b', qty: 1 }] }];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__CF=${JSON.stringify(o.cf || BASE())};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__CF.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const sheet = (p) => p.evaluate(() => (document.querySelector('#sheet') || {}).innerText || '');

  ok(!!IA_LINE, 'the ia.js registry line is printed in docs/integration/CRM-H.md');

  // 1. the list
  let p = await open('#/crmfeedback');
  let t = await text(p);
  ok(/Feedback and complaints/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('#cf_strip').count() === 1 && /3 Open/.test(t) && /1 Overdue/.test(t) && /1 Food safety/.test(t) && /1 Calls needed/.test(t), 'strip: open, overdue, food safety, calls needed: ' + (await p.locator('#cf_strip').innerText()).replace(/\n/g, ' '));
  ok(await p.locator('.cf-row').count() === 3, 'three complaint rows');
  ok(/#7 · Customer fell ill/.test(t) && /Overdue · over by 3 h/.test(t) || /Overdue · over by 150 min/.test(t), 'overdue text on the first row: ' + (t.match(/Overdue · [^\n]*/) || [''])[0]);
  ok(await p.locator('.cf-row[data-id=c1] .chip.bad').count() >= 1 && /Food safety/.test(await p.locator('.cf-row[data-id=c1]').innerText()), 'overdue chip is red and the food-safety chip shows');
  ok(/Repeat/.test(await p.locator('.cf-row[data-id=c2]').innerText()) && /In progress/.test(await p.locator('.cf-row[data-id=c2]').innerText()), 'repeat chip and status on row 2');
  ok(/No clock/.test(await p.locator('.cf-row[data-id=c3]').innerText()), 'a complaint with no SLA hours says "No clock"');
  ok(await p.locator('#cf_new').count() === 1 && await p.locator('#cf_scan').count() === 1, 'log button and overdue check for a manager');
  const l0 = await calls(p, '_crmh_complaint_list'); ok(l0.length >= 1 && l0[l0.length - 1].status === 'active', 'default filter asks for open complaints');
  await noOverflow(p, 'list'); await p.screenshot({ path: SP + '/cf_list.png', fullPage: true });
  // filters
  await p.click('[data-act=cf_filt][data-k=overdue]'); await wait(p);
  let lc = await calls(p, '_crmh_complaint_list'); ok(lc[lc.length - 1].overdue === true, 'overdue filter sends overdue:true');
  await p.click('[data-act=cf_filt][data-k=fs]'); await wait(p);
  lc = await calls(p, '_crmh_complaint_list'); ok(lc[lc.length - 1].food_safety === true, 'food safety filter');
  await p.click('[data-act=cf_filt][data-k=repeat]'); await wait(p); lc = await calls(p, '_crmh_complaint_list'); ok(lc[lc.length - 1].repeat === true, 'repeat filter');
  await p.click('[data-act=cf_filt][data-k=mine]'); await wait(p); lc = await calls(p, '_crmh_complaint_list'); ok(lc[lc.length - 1].mine === true, 'mine filter');
  await p.click('[data-act=cf_filt][data-k=all]'); await wait(p); lc = await calls(p, '_crmh_complaint_list'); ok(lc[lc.length - 1].status === 'all', 'all filter');
  // overdue check button
  await p.click('#cf_scan'); await wait(p, 400);
  ok((await calls(p, '_crmh_sla_scan')).length === 1 && (await calls(p, '_crmh_sla_scan'))[0].p_dry === false && /Marked as overdue: 2/.test(await text(p)), 'the overdue check marks and reports 2');

  // 2. log a complaint
  p = await open('#/crmfeedback');
  await p.click('#cf_new'); await wait(p);
  ok(/Log a complaint/.test(await sheet(p)) && await p.locator('#cfa_cat').count() === 1 && await p.locator('#cfa_desc').count() === 1, 'the log sheet shows category and what happened first');
  ok(await p.evaluate(() => !document.querySelector('#cf_more').open), 'severity, food-safety box, receipt and phone are folded under More');
  await p.click('#cf_ask_go'); await wait(p);
  ok((await calls(p, '_crmh_complaint_save')).length === 0 && /Choose a category/.test(await text(p)), 'no category: nothing is sent');
  await p.selectOption('#cfa_cat', 'sick'); await p.click('#cf_ask_go'); await wait(p);
  ok((await calls(p, '_crmh_complaint_save')).length === 0 && /Write what happened/.test(await text(p)), 'no description: nothing is sent');
  await p.fill('#cfa_desc', 'test customer fell ill after the cake');
  await p.click('#cf_more summary'); await p.selectOption('#cfa_sev', 'high'); await p.check('#cfa_fs'); await p.fill('#cfa_rcpt', '77'); await p.click('[data-act=cf_find]'); await wait(p, 500);
  ok(/Receipt found/.test(await text(p)) && await p.locator('#cfa_item option').count() === 3, 'receipt lookup fills the item list from the sale lines');
  await p.selectOption('#cfa_item', 'it1'); await p.fill('#cfa_phone', '01800000001');
  await noOverflow(p, 'log sheet'); await p.screenshot({ path: SP + '/cf_new.png' });
  await p.click('#cf_ask_go'); await wait(p, 500);
  const sv = await calls(p, '_crmh_complaint_save');
  ok(sv.length === 1 && sv[0].p.category === 'sick' && sv[0].p.severity === 'high' && sv[0].p.food_safety === true && sv[0].p.location_id === 1 && sv[0].p.sale_id === 'sale1' && sv[0].p.item_id === 'it1' && sv[0].p.customer_phone === '01800000001' && sv[0].p.description.startsWith('test customer'), 'the save carries outlet, category, severity, food safety, receipt, item, phone: ' + JSON.stringify(sv[0] && sv[0].p));
  ok(/Saved\. #99/.test(await text(p)), 'ticket number shown');

  // 3. detail and actions by status
  async function detail(status, extra, errs) {
    const cf = BASE(); cf.get = DETAIL(status, extra); if (errs) cf.err = errs;
    const q = await open('#/crmfeedback', { cf }); await q.click('.cf-row[data-id=c1]'); await wait(q); return q;
  }
  p = await detail('open');
  let s = await sheet(p);
  ok(await p.locator('#cf_detail[data-status=open]').count() === 1 && /test too sweet/.test(s) && /Earlier complaints by this customer/.test(s) && /#3/.test(s) && /History/.test(s), 'detail shows the text, earlier complaints, history');
  ok(await p.locator('[data-act=cf_start]').count() === 1 && await p.locator('[data-act=cf_resolve]').count() === 1 && await p.locator('[data-act=cf_closenr]').count() === 1 && await p.locator('[data-act=cf_close]').count() === 0 && await p.locator('[data-act=cf_reopen]').count() === 0, 'open: Start, Resolve, Close without a result (no Close, no Reopen)');
  ok(/never refunds/.test(s) && await p.locator('[data-act=cf_openret]').count() === 1 && await p.locator('[data-act=cf_linkret]').count() === 1, 'refund box: says the screen never refunds, offers the sale return screen and the link');
  await noOverflow(p, 'detail'); await p.screenshot({ path: SP + '/cf_detail.png' });
  await p.click('[data-act=cf_start]'); await wait(p, 400);
  let mv = await calls(p, '_crmh_complaint_move'); ok(mv.length === 1 && mv[0].p_to === 'in_progress' && mv[0].p_id === 'c1', 'Start sends in_progress');
  // resolve needs a result and a note
  p = await detail('in_progress');
  await p.click('[data-act=cf_resolve]'); await wait(p);
  await p.click('#cf_ask_go'); await wait(p);
  ok((await calls(p, '_crmh_complaint_move')).length === 0 && /Choose a result/.test(await text(p)), 'resolve without a result or note: nothing is sent');
  await p.selectOption('#cfa_res', 'explained'); await p.fill('#cfa_note', 'test explained on the phone'); await p.click('#cf_ask_go'); await wait(p, 400);
  mv = await calls(p, '_crmh_complaint_move'); ok(mv.length === 1 && mv[0].p_to === 'resolved' && mv[0].p_resolution === 'explained' && mv[0].p_note === 'test explained on the phone', 'resolve sends result and note');
  // close without a result needs a reason
  p = await detail('in_progress');
  await p.click('[data-act=cf_closenr]'); await wait(p); await p.click('#cf_ask_go'); await wait(p);
  ok((await calls(p, '_crmh_complaint_move')).length === 0, 'close without a result: no reason, nothing sent');
  await p.selectOption('#cfa_reason', 'no_contact'); await p.fill('#cfa_note', 'test phone off'); await p.click('#cf_ask_go'); await wait(p, 400);
  mv = await calls(p, '_crmh_complaint_move'); ok(mv.length === 1 && mv[0].p_to === 'closed_no_resolution' && mv[0].p_close_reason === 'no_contact', 'close without a result sends the reason code');
  // resolved: close or reopen
  p = await detail('resolved');
  ok(await p.locator('[data-act=cf_close]').count() === 1 && await p.locator('[data-act=cf_reopen]').count() === 1 && await p.locator('[data-act=cf_resolve]').count() === 0, 'resolved: Close and Reopen only');
  await p.click('[data-act=cf_reopen]'); await wait(p); await p.click('#cf_ask_go'); await wait(p); ok((await calls(p, '_crmh_complaint_move')).length === 0, 'reopen needs a reason');
  // closed: locked, no actions
  p = await detail('closed');
  ok(await p.locator('#cf_acts').count() === 0 && await p.locator('[data-act=cf_linkret]').count() === 0, 'closed: no action buttons, no link button');
  // server refusal is said in words
  p = await detail('open', null, { '_crmh_complaint_move': 'illegal_status_change' });
  await p.click('[data-act=cf_start]'); await wait(p, 400);
  ok(/not allowed from the current status/.test(await text(p)), 'a refused move shows a plain sentence: ' + (await text(p)).slice(-120).replace(/\n/g, ' '));
  // notes, contact, owner, severity
  p = await detail('open');
  await p.click('[data-act=cf_contact]'); await wait(p); await p.fill('#cfa_note', 'test called the customer'); await p.click('#cf_ask_go'); await wait(p, 400);
  let nt = await calls(p, '_crmh_complaint_note'); ok(nt.length === 1 && nt[0].p_kind === 'contact' && nt[0].p_body === 'test called the customer', 'record a call sends kind contact');
  p = await detail('open');
  await p.click('[data-act=cf_assign]'); await wait(p, 400);
  let as = await calls(p, '_crmh_complaint_assign'); ok(as.length === 1 && as[0].p_user === 'u1', 'Take it assigns the signed-in user (the owner is never hard-coded)');
  p = await detail('open');
  await p.click('[data-act=cf_sev]'); await wait(p); await p.selectOption('#cfa_sev', 'critical'); await p.fill('#cfa_note', 'test it is food related'); await p.click('#cf_ask_go'); await wait(p, 400);
  let sg = await calls(p, '_crmh_complaint_severity_set'); ok(sg.length === 1 && sg[0].p_severity === 'critical' && sg[0].p_note === 'test it is food related', 'severity change sends severity and reason');
  // return link
  p = await detail('open');
  await p.click('[data-act=cf_linkret]'); await wait(p, 400);
  ok(await p.locator('[data-act=cf_linkgo]').count() === 1 && /value 100/.test(await sheet(p)), 'only finished returns are offered (the cancelled one is not)');
  await p.click('[data-act=cf_linkgo]'); await wait(p, 400);
  let lk = await calls(p, '_crmh_complaint_link_return'); ok(lk.length === 1 && lk[0].p_return === 'ret1' && lk[0].p_id === 'c1', 'link sends the return id');
  ok((await calls(p, 'sale_returns_for')).length === 1, 'returns are read through the existing sale_returns_for');
  // no manager rights: no actions
  const nm = BASE(); nm.set = Object.assign(clone(SET), { may_manage: false }); nm.get = Object.assign(DETAIL('open'), { can_manage: false });
  p = await open('#/crmfeedback', { cf: nm }); ok(await p.locator('#cf_scan').count() === 0, 'a person without manage rights has no overdue-check button');
  await p.click('.cf-row[data-id=c1]'); await wait(p); ok(await p.locator('#cf_acts').count() === 0 && await p.locator('[data-act=cf_linkret]').count() === 0, 'and no action buttons in the detail');

  // 4. ratings
  p = await open('#/crmfeedback');
  await p.click('[data-act=cf_tab][data-t=r]'); await wait(p, 400);
  t = await text(p);
  ok(await p.locator('.cf-rate').count() === 2 && /3\.5 \/ 5/.test(t) && /★☆☆☆☆/.test(t) && /needs a call/.test(t) && /#77/.test(t) && /Order 12/.test(t), 'ratings: two rows, average, stars, needs a call, receipt, order');
  await noOverflow(p, 'ratings'); await p.screenshot({ path: SP + '/cf_ratings.png', fullPage: true });
  await p.click('[data-act=cf_calldone]'); await wait(p); await p.click('#cf_ask_go'); await wait(p, 300);
  ok((await calls(p, '_crmh_feedback_followup')).length === 1, 'the call button asks for the note and sends it (the server refuses a short one)');
  p = await open('#/crmfeedback'); await p.click('[data-act=cf_tab][data-t=r]'); await wait(p, 300);
  await p.click('[data-act=cf_tocomplaint]'); await wait(p); await p.click('#cf_ask_go'); await wait(p, 300);
  ok((await calls(p, '_crmh_feedback_to_complaint')).length === 0 && /Choose a category/.test(await text(p)), 'make a complaint: category is required');
  await p.selectOption('#cfa_cat', 'taste'); await p.click('#cf_ask_go'); await wait(p, 400);
  const tc = await calls(p, '_crmh_feedback_to_complaint'); ok(tc.length === 1 && tc[0].p_id === 'f1' && tc[0].p.category === 'taste', 'make a complaint sends the rating id and category');
  p = await open('#/crmfeedback'); await p.click('[data-act=cf_tab][data-t=r]'); await wait(p, 300);
  await p.click('#cf_newr'); await wait(p);
  await p.fill('#cfa_rcpt', '77'); await p.selectOption('#cfa_st', '2'); await p.fill('#cfa_cm', 'test too dry'); await p.selectOption('#cfa_ch', 'phone'); await p.click('#cf_ask_go'); await wait(p, 600);
  const fa = await calls(p, '_crmh_feedback_add'); ok(fa.length === 1 && fa[0].p.sale_id === 'sale1' && fa[0].p.rating === 2 && fa[0].p.comment === 'test too dry' && fa[0].p.channel === 'phone', 'add a rating: sale found by receipt, stars, comment, channel');
  p = await open('#/crmfeedback'); await p.click('[data-act=cf_tab][data-t=r]'); await wait(p, 300);
  await p.click('#cf_newr'); await wait(p); await p.fill('#cfa_rcpt', '999'); await p.click('#cf_ask_go'); await wait(p, 400);
  ok((await calls(p, '_crmh_feedback_add')).length === 0 && /not found/.test(await text(p)), 'an unknown receipt number sends nothing');
  const rof = BASE(); rof.fset = Object.assign(clone(FSET), { on: false });
  p = await open('#/crmfeedback', { cf: rof }); await p.click('[data-act=cf_tab][data-t=r]'); await wait(p, 300); ok(await p.locator('#cf_roff').count() === 1 && /Ratings are switched off/.test(await text(p)), 'ratings off: a plain message');

  // 5. report
  p = await open('#/crmfeedback');
  await p.click('[data-act=cf_tab][data-t=p]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('.cf-rep').count() === 1 && /4 total/.test(t) && /2 open/.test(t) && /1 food safety/.test(t) && /2 repeats/.test(t) && /3\.5 average hours to resolve/.test(t) && /value of linked returns 100/.test(t), 'report: complaint card with the numbers');
  ok(await p.locator('.cf-repr').count() === 1 && /3\.5 \/ 5/.test(t) && /1 needs a call/.test(t) && await p.locator('.cf-rpt').count() === 1, 'report: ratings card and the repeat customers');
  await noOverflow(p, 'report'); await p.screenshot({ path: SP + '/cf_report.png', fullPage: true });
  await p.selectOption('#cf_by', 'item'); await p.fill('#cf_from', '2026-09-01'); await p.fill('#cf_to', '2026-09-30'); await p.click('#cf_run'); await wait(p, 400);
  const rr = await calls(p, '_crmh_report'); ok(rr.length >= 2 && rr[rr.length - 1].by === 'item' && rr[rr.length - 1].from === '2026-09-01' && rr[rr.length - 1].to === '2026-09-30', 'run sends the period and the grouping');
  const roff = BASE(); roff.repeats = { off: true };
  // the repeat check being off is told in words (the server answers days_required)
  const rr2 = BASE(); rr2.err = { '_crmh_repeat_list': 'days_required' };
  p = await open('#/crmfeedback', { cf: rr2 }); await p.click('[data-act=cf_tab][data-t=p]'); await wait(p, 500); ok(/repeat check is off/.test(await text(p)), 'repeat check off is explained');

  // 6. states
  const off = BASE(); off.set = Object.assign(clone(SET), { on: false });
  p = await open('#/crmfeedback', { cf: off }); ok(await p.locator('#cf_off').count() === 1 && /Complaints are switched off/.test(await text(p)) && await p.locator('#cf_new').count() === 0, 'complaints off: plain message and no log button');
  const ms = BASE(); ms.missing = true; p = await open('#/crmfeedback', { cf: ms }); ok(/have not been run on the server/.test(await text(p)), 'friendly message when the SQL is not installed');
  const dn = BASE(); dn.deny = true; p = await open('#/crmfeedback', { cf: dn }); ok(/do not have permission/.test(await text(p)), 'denied message');

  // 7. English only: bn and mix read the same
  p = await open('#/crmfeedback', { lang: 'bn' }); t = await p.locator('#cf_body').innerText();
  ok(/Complaints/.test(t) && !/[ঀ-৿]/.test(t) && /Feedback and complaints/.test(await p.locator('h1').textContent()), 'bn mode: still English, no Bangla on the page');
  await noOverflow(p, 'bn');
  p = await open('#/crmfeedback', { lang: 'mix' }); ok(/Overdue/.test(await text(p)), 'mix mode renders the same text');

  // 8. registry: the screen is reachable from the Customers group for a person with the grant
  p = await open('#/group/cust'); ok(/Feedback and complaints/.test(await text(p)), 'the category page lists the screen (owner)');

  log(errors.length ? 'ERRORS:\n' + errors.join('\n') : 'no console errors');
  if (errors.length) bad++;
  log(bad ? 'RESULT: ' + bad + ' failure(s)' : 'RESULT: all passed');
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e); srv.close(); process.exit(2); } })();
