// Mobile wallets screen (web/wallets.js). Run: node tests/web/wallets_test.js <abs dir tests/web>
// Serves THIS checkout's web/ folder (not the shared one), injects wallets.js (the integrator adds the script tag to index.html), and mocks the phase83 RPCs.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), http = require('http'), path = require('path');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web');
const base = C.baseData(SP);
const srv = http.createServer((q, r) => { const f = path.join(WEB, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
  r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8348);
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 M.w = Object.assign({ hidden: true, denied: false, negative: false, diff: 0 }, window.__W0 || {});
 const W = (id, code, en, bn, book) => ({ wallet_id: id, code, name_en: en, name_bn: bn, account: '113' + id, active: true, counted: false, book: M.w.hidden ? null : book, journal: M.w.hidden ? null : book, journal_gap: M.w.hidden ? null : 0 });
 c.rpc = async (fn, args) => {
  if (fn === 'd_wallet_balances') { M.calls.push([fn, clone(args || {})]); if (M.w.denied) return { data: null, error: { message: 'not allowed' } }; return { data: [W(1, 'bkash', 'bKash', 'বিকাশ', 500), W(2, 'nagad', 'Nagad', 'নগদ', 300)], error: null }; }
  if (fn === 'd_wallet_recon_report') { M.calls.push([fn, clone(args || {})]); return { data: { date: args.p_date, unassigned_mobile: 200, wallets: [] }, error: null }; }
  if (fn === 'd_wallet_check_save') { M.calls.push([fn, clone(args || {})]); const d = args.p_phone - 500; return { data: { id: 7, phone: args.p_phone, book: 500, book_journal: 500, diff: d, status: d === 0 ? 'matched' : 'difference' }, error: null }; }
  if (fn === 'd_wallet_check_explain') { M.calls.push([fn, clone(args || {})]); return { data: { id: args.p_check, status: 'explained' }, error: null }; }
  if (fn === 'd_wallet_fee_add' || fn === 'd_wallet_move_add') { M.calls.push([fn, clone(args || {})]); if (M.w.negative) return { data: null, error: { message: 'wallet_negative' } }; return { data: { id: 1, balance_after: 100 }, error: null }; }
  return rpc(fn, args); };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/404/.test(m.text()) && !/not allowed/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o); data.tables.locations = data.tables.locations || [];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__W0=${JSON.stringify(o.w || {})};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto('http://localhost:8348/' + hash); await p.waitForTimeout(1200);
    await p.addScriptTag({ content: fs.readFileSync(path.join(WEB, 'wallets.js'), 'utf8') });      // the integrator adds the real script tag
    await p.evaluate(() => { location.hash = '#/x'; }); await p.waitForTimeout(100);
    await p.evaluate(() => { location.hash = '#/wallets'; }); await p.waitForTimeout(900);
    return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);

  let p = await open({ w: { hidden: true } }, '');
  ok(await p.locator('#wl_body .card').count() >= 5, 'balances + count + fee + move cards are drawn');
  ok(/Shown after you count/.test(await p.textContent('#wl_body')), 'blind: the book figure is hidden before the count');
  ok(!/500/.test(await p.textContent('#wl_body .card:nth-of-type(3)') || ''), 'no book number leaked');
  ok(/200/.test(await p.textContent('#wl_body')), 'unrecognised wallet money is shown');
  ok(/bKash/.test(await p.textContent('#wl_body')) && /Nagad/.test(await p.textContent('#wl_body')), 'wallet names shown');
  await noOverflow(p, 'wallets page');
  // count: type phone first -> matched
  await p.fill('#wl_cp', '500'); await p.click('[data-act=wl_count]'); await p.waitForTimeout(400);
  let c = await calls(p, 'd_wallet_check_save'); ok(c.length === 1 && c[0].p_phone === 500 && c[0].p_wallet === 1, 'check saved with the phone figure');
  ok(/Matched/.test(await p.textContent('#wl_cout')), 'matched shown after saving');
  // count: mismatch -> reason box -> explain
  await p.fill('#wl_cp', '480'); await p.click('[data-act=wl_count]'); await p.waitForTimeout(400);
  ok(await p.locator('#wl_rs').count() === 1 && /-20/.test(await p.textContent('#wl_cout')), 'difference shown with a reason box');
  await p.click('[data-act=wl_explain]'); await p.waitForTimeout(200); ok((await calls(p, 'd_wallet_check_explain')).length === 0, 'blank reason is not sent');
  await p.fill('#wl_rs', 'test reason'); await p.click('[data-act=wl_explain]'); await p.waitForTimeout(300);
  c = await calls(p, 'd_wallet_check_explain'); ok(c.length === 1 && c[0].p_reason === 'test reason' && c[0].p_check === 7, 'reason sent once');
  // fee
  await p.fill('#wl_fa', '15'); await p.click('[data-act=wl_fee]'); await p.waitForTimeout(300);
  c = await calls(p, 'd_wallet_fee_add'); ok(c.length === 1 && c[0].p_amount === 15 && c[0].p_kind === 'cash_out' && !!c[0].p_client, 'fee sent with a client id');
  await p.fill('#wl_fa', '0'); await p.click('[data-act=wl_fee]'); await p.waitForTimeout(150); ok((await calls(p, 'd_wallet_fee_add')).length === 1, 'zero fee is not sent');
  // move to another wallet shows the second wallet box
  await p.selectOption('#wl_mc', 'wallet'); ok(await p.locator('#wl_mow:not([hidden])').count() === 1, 'other-wallet box appears');
  await p.fill('#wl_ma', '40'); await p.selectOption('#wl_md', 'out'); await p.selectOption('#wl_mo', '2'); await p.click('[data-act=wl_move]'); await p.waitForTimeout(300);
  c = await calls(p, 'd_wallet_move_add'); ok(c.length === 1 && c[0].p_direction === 'out' && c[0].p_counter === 'wallet' && c[0].p_counter_wallet === 2 && c[0].p_amount === 40, 'wallet to wallet move sent');
  await p.close();

  // server refuses (negative) -> the message is shown, nothing crashes
  p = await open({ w: { hidden: false, negative: true } }, '');
  ok(/500/.test(await p.textContent('#wl_body')), 'owner sees the book figure');
  await p.fill('#wl_fa', '9999'); await p.click('[data-act=wl_fee]'); await p.waitForTimeout(300);
  ok(/does not hold that much/.test(await p.evaluate(() => document.body.innerText)), 'negative balance message shown');
  await p.close();

  // no permission
  p = await open({ w: { denied: true } }, '');
  ok((await p.evaluate(() => document.body.innerText)).length > 0, 'denied: the page does not crash');
  await p.close();
  await br.close();
  console.log('errors:', errors.length ? errors.join(' | ') : 'none'); console.log('assert failures:', bad);
  process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.log('TEST CRASH', e); process.exit(2); } finally { srv.close(); } })();
