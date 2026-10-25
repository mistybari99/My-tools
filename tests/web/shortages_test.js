// Shortages page (#/shortages): cash short / over cases and goods short in transit. Server calls are stand-ins; the real SQL is tested in supabase/phase81_test.sql.
// Covers: nothing offered without the right (server refusal shown), approve / reject / void, employee picker when the owner chose "staff receivable",
// duplicate warning confirm, transit claim / recover / write-off / set cost, bearer setting hides the wrong button, notes required, 360px width, Bangla.
// Run: node shortages_test.js <abs tests/web dir> [shots dir]     (serves ../../web of THIS checkout and injects the script tag; the route is not in ia.js yet)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web'); const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = 8381;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from((b.toString('utf8').includes('src="shortages.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="shortages.js"></script></body>')));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const day = new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 10);
const CASH = [
  { id: 'c1', entry_id: 'e1', form_code: '06-1', location_id: 1, location: 'Test place', case_date: day, amount: -200, kind: 'short', status: 'open', can_decide: true, posted: false },
  { id: 'c2', entry_id: 'e2', form_code: '06-1', location_id: 1, location: 'Test place', case_date: day, amount: 50, kind: 'over', status: 'open', can_decide: true, posted: false },
  { id: 'c3', entry_id: 'e3', form_code: '06-1', location_id: 1, location: 'Test place', case_date: day, amount: -30, kind: 'short', status: 'approved', can_decide: false, posted: true, decide_note: 'slip checked' }];
const TRANSIT = [
  { id: 's1', item_bn: 'test_item_a', item_en: 'test_item_a', from_name: 'Place A', to_name: 'Place B', qty_short: 1, value: 20, cost_missing: false, status: 'open', outstanding_claim: 0, received_on: day, can_decide: true },
  { id: 's2', item_bn: 'test_item_b', item_en: 'test_item_b', from_name: 'Place A', to_name: 'Place B', qty_short: 2, value: null, cost_missing: true, status: 'open', outstanding_claim: 0, received_on: day, can_decide: true },
  { id: 's3', item_bn: 'test_item_c', item_en: 'test_item_c', from_name: 'Place A', to_name: 'Place B', qty_short: 3, value: 60, cost_missing: false, status: 'claimed', outstanding_claim: 50, received_on: day, can_decide: true },
  { id: 's4', item_bn: 'test_item_d', item_en: 'test_item_d', from_name: 'Place A', to_name: 'Place B', qty_short: 4, value: 80, cost_missing: false, status: 'written_off', outstanding_claim: 0, received_on: day, can_decide: false }];
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.rules = (T.rules || []).filter((r) => !/^(cash_short|transit_short)/.test(r.key));
  T.rules.push({ key: 'cash_short_post_on', value: o.postOn === undefined ? null : o.postOn, default_value: false }, { key: 'cash_short_treatment', value: o.treat || null, default_value: 'expense' }, { key: 'transit_short_bearer', value: o.bearer || null, default_value: 'ask' });
  T.employees = [{ id: 'emp1', employee_no: 'E1', full_name_bn: 'test_emp', full_name_en: 'test_emp' }];
  return data;
}
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.sh = Object.assign({ err: {}, cash: ${JSON.stringify(CASH)}, transit: ${JSON.stringify(TRANSIT)} }, window.__W || {});
 c.rpc = async (fn, args) => {
  if (!/^(cash_short|transit_short)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === 'cash_short_list') return { data: clone(W.cash), error: null };
  if (fn === 'transit_short_list') return { data: clone(W.transit), error: null };
  return { data: { ok: true }, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } else if (process.env.DBG) log('ok:', m); };
  async function open(o, hash) {
    if (process.env.DBG) console.log("open", hash);
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__W=${JSON.stringify(o.w || {})};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); if (process.env.DBG) { console.log((await p.textContent('body')).slice(0, 300)); console.log(errors.join('|')); } return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const txt = (p, s) => p.textContent(s);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth); ok(r <= 1, 'no horizontal scroll at 360px: ' + m + ' (' + r + ')'); };

  // ---- cash tab
  let p = await open({}, '#/shortages');
  let t = await txt(p, '#sh_body');
  ok(await p.locator('[data-case]').count() === 3, 'three cash cases listed');
  ok(/Short ৳ ?200/.test(t) && /Over ৳ ?50/.test(t), 'short and over shown with the amount without sign');
  ok(/Nothing is written to the books until the owner decides/.test(t) && /Posting to books: Off/.test(t), 'the plain rule: nothing posts before a decision; posting setting shown (default off)');
  ok(/In the books/.test(await txt(p, '[data-case="c3"]')), 'an approved and posted case says it is in the books');
  ok(await p.locator('[data-case="c3"] [data-act=sh_open][data-k=approve]').count() === 0 && await p.locator('[data-case="c3"] [data-act=sh_open][data-k=void]').count() === 1, 'an approved case offers only Void; open cases offer Approve and Reject');
  await p.click('[data-case="c1"] [data-act=sh_open][data-k=approve]'); await wait(p, 150);
  ok(await p.locator('#sh_emp').count() === 0, 'treatment = expense: no employee picker');
  await p.click('[data-act=sh_go]'); await wait(p, 150);
  ok(/Write a reason/.test(await txt(p, '#toast')) && (await calls(p, 'cash_short_decide')).length === 0, 'a note is required, nothing sent without it');
  await p.fill('#sh_note', 'count slip checked'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  let c = await calls(p, 'cash_short_decide');
  ok(c.length === 1 && c[0].p_id === 'c1' && c[0].p_approve === true && c[0].p_note === 'count slip checked' && c[0].p_employee === null && c[0].p_force === false, 'approve sends id, note, no employee, not forced');
  await p.click('[data-case="c2"] [data-act=sh_open][data-k=reject]'); await wait(p, 150); await p.fill('#sh_note', 'recounted'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  c = await calls(p, 'cash_short_decide'); ok(c.length === 2 && c[1].p_id === 'c2' && c[1].p_approve === false, 'reject sends approve=false');
  await p.click('[data-case="c3"] [data-act=sh_open][data-k=void]'); await wait(p, 150); await p.fill('#sh_note', 'wrong day'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  c = await calls(p, 'cash_short_void'); ok(c.length === 1 && c[0].p_id === 'c3' && c[0].p_note === 'wrong day', 'void sends the case and the note');
  await p.screenshot({ path: OUT + '/sh_cash.png' }); await noOverflow(p, 'cash tab'); await p.close();

  // ---- staff receivable: a SHORT needs an employee, an OVER does not
  p = await open({ treat: 'staff_receivable' }, '#/shortages');
  await p.click('[data-case="c1"] [data-act=sh_open][data-k=approve]'); await wait(p, 150);
  ok(await p.locator('#sh_emp').count() === 1, 'staff_receivable: a short shows the employee picker');
  await p.fill('#sh_note', 'collect from cashier'); await p.click('[data-act=sh_go]'); await wait(p, 200);
  ok(/Choose the employee/.test(await txt(p, '#toast')) && (await calls(p, 'cash_short_decide')).length === 0, 'no employee chosen: stopped before the server');
  await p.selectOption('#sh_emp', 'emp1'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  c = await calls(p, 'cash_short_decide'); ok(c.length === 1 && c[0].p_employee === 'emp1', 'employee id sent');
  await p.click('[data-case="c2"] [data-act=sh_open][data-k=approve]'); await wait(p, 150); ok(await p.locator('#sh_emp').count() === 0, 'an over never asks for an employee'); await p.close();

  // ---- server refusals shown in words
  p = await open({ w: { err: { cash_short_decide: 'own_count' } } }, '#/shortages');
  await p.click('[data-case="c1"] [data-act=sh_open][data-k=approve]'); await wait(p, 150); await p.fill('#sh_note', 'my own count'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  ok(/Nobody decides the count they made/.test(await txt(p, '#toast')), 'own count refusal in words'); await p.close();
  p = await open({ w: { err: { cash_short_decide: 'possible_duplicate' } } }, '#/shortages');
  await p.click('[data-case="c1"] [data-act=sh_open][data-k=approve]'); await wait(p, 150); await p.fill('#sh_note', 'different amount'); await p.click('[data-act=sh_go]'); await wait(p, 400);
  c = await calls(p, 'cash_short_decide'); ok(c.length === 2 && c[0].p_force === false && c[1].p_force === true, 'possible_duplicate: confirm, then the same call is repeated with force'); await p.close();
  p = await open({ w: { err: { cash_short_list: 'not allowed' } } }, '#/shortages');
  ok(/Not allowed/.test(await txt(p, '#sh_body')) && await p.locator('[data-case]').count() === 0, 'a person without the right sees "Not allowed", no data'); await p.close();

  // ---- transit tab
  p = await open({}, '#/shortages'); await p.click('[data-act=sh_tab][data-v=transit]'); await wait(p, 200);
  t = await txt(p, '#sh_body');
  ok(await p.locator('[data-short]').count() === 4, 'four transit rows');
  ok(/Cost missing/.test(await txt(p, '[data-short="s2"]')) && await p.locator('[data-short="s2"] [data-act=sh_open][data-k=claim]').count() === 0 && await p.locator('[data-short="s2"] [data-act=sh_open][data-k=setcost]').count() === 1, 'cost missing: only "Enter cost" is offered');
  ok(await p.locator('[data-short="s1"] [data-act=sh_open][data-k=claim]').count() === 1 && await p.locator('[data-short="s1"] [data-act=sh_open][data-k=writeoff]').count() === 1, 'open + known cost: claim and write off');
  ok(await p.locator('[data-short="s3"] [data-act=sh_open][data-k=recover]').count() === 1 && /Claim outstanding ৳ ?50/.test(await txt(p, '[data-short="s3"]')), 'claimed: recover offered, outstanding 50 shown');
  ok(await p.locator('[data-short="s4"] button').count() === 0, 'a written-off row has no actions');
  await p.click('[data-short="s1"] [data-act=sh_open][data-k=claim]'); await wait(p, 150); await p.fill('#sh_note', 'claimed to the carrier'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  c = await calls(p, 'transit_short_claim'); ok(c.length === 1 && c[0].p_id === 's1' && c[0].p_note === 'claimed to the carrier', 'claim sent');
  await p.click('[data-short="s1"] [data-act=sh_open][data-k=writeoff]'); await wait(p, 150); await p.fill('#sh_note', 'shop takes it'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  c = await calls(p, 'transit_short_writeoff'); ok(c.length === 1 && c[0].p_id === 's1', 'write-off sent');
  await p.click('[data-short="s2"] [data-act=sh_open][data-k=setcost]'); await wait(p, 150); await p.fill('#sh_note', 'price list'); await p.fill('#sh_cost', '0'); await p.click('[data-act=sh_go]'); await wait(p, 200);
  ok((await calls(p, 'transit_short_set_cost')).length === 0, 'a zero cost is stopped');
  await p.fill('#sh_cost', '7.5'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  c = await calls(p, 'transit_short_set_cost'); ok(c.length === 1 && c[0].p_unit_cost === 7.5, 'owner cost sent');
  await p.click('[data-short="s3"] [data-act=sh_open][data-k=recover]'); await wait(p, 150);
  ok(await p.inputValue('#sh_amt') === '50', 'recover amount is pre-filled with the outstanding claim');
  await p.fill('#sh_amt', '20'); await p.selectOption('#sh_mode', 'mobile'); await p.fill('#sh_note', 'part paid'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  c = await calls(p, 'transit_short_recover'); ok(c.length === 1 && c[0].p_id === 's3' && c[0].p_amount === 20 && c[0].p_mode === 'mobile', 'recover sends amount and mode');
  await p.screenshot({ path: OUT + '/sh_transit.png' }); await noOverflow(p, 'transit tab'); await p.close();

  // ---- who bears the loss hides the wrong button (the server still refuses it)
  p = await open({ bearer: 'carrier' }, '#/shortages'); await p.click('[data-act=sh_tab][data-v=transit]'); await wait(p, 200);
  ok(await p.locator('[data-short="s1"] [data-act=sh_open][data-k=writeoff]').count() === 0 && await p.locator('[data-short="s1"] [data-act=sh_open][data-k=claim]').count() === 1, 'bearer = carrier: only claim on an open row'); await p.close();
  p = await open({ bearer: 'shop' }, '#/shortages'); await p.click('[data-act=sh_tab][data-v=transit]'); await wait(p, 200);
  ok(await p.locator('[data-short="s1"] [data-act=sh_open][data-k=claim]').count() === 0 && await p.locator('[data-short="s1"] [data-act=sh_open][data-k=writeoff]').count() === 1, 'bearer = shop: only write off on an open row'); await p.close();
  p = await open({ w: { err: { transit_short_claim: 'cost_missing' } } }, '#/shortages'); await p.click('[data-act=sh_tab][data-v=transit]'); await wait(p, 200);
  await p.click('[data-short="s1"] [data-act=sh_open][data-k=claim]'); await wait(p, 150); await p.fill('#sh_note', 'to carrier'); await p.click('[data-act=sh_go]'); await wait(p, 300);
  ok(/Enter the cost first/.test(await txt(p, '#toast')), 'server refusal cost_missing in words'); await p.close();

  // ---- Bangla
  p = await open({ lang: 'bn' }, '#/shortages'); t = await txt(p, '#sh_body');
  ok(/ক্যাশ কম \/ বেশি/.test(t) && /অনুমোদন/.test(t) && /মালিক সিদ্ধান্ত না নিলে|মালিক সিদ্ধান্ত/.test(t), 'Bangla labels');
  await noOverflow(p, 'Bangla'); await p.screenshot({ path: OUT + '/sh_bn.png' }); await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
