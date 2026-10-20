// Step S1: cost marks & intake bot page (#/s1setup): the cost-really-zero marks and the cost_missing list, the intake-bot setup (owner only), no access without the cost right,
// English mode without Bangla characters, Bangla labels, 360px phone width.
// Run: node s1setup_test.js <abs tests/web dir> [shots dir]      (serves ../../web of THIS checkout and injects the script tag)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/s10_common.js');
const WEB = _P.WEB_DIR; const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = _P.freePort();
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from((b.toString('utf8').includes('src="s1setup.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="s1setup.js"></script></body>')));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.locations = [{ id: 1, code: 'main', name_bn: 'মেইন শোরুম', name_en: 'Main showroom', kind: 'showroom' }, { id: 5, code: 'fac', name_bn: 'মিষ্টি কারখানা', name_en: 'Sweet factory', kind: 'factory' }];
  T.profiles = [{ id: 'u-bot', staff_id: 'S-9', full_name: 'Order bot', status: 'active' }, { id: 'u-pos', staff_id: 'S-3', full_name: 'Counter user', status: 'active' }];
  return data;
}
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.s1 = { flags: [{ item_id: 'w1', code: 'I-WA', name_bn: 'পানি', name_en: 'Water', reason: 'own water', set_at: '2026-10-01' }], unk: [{ item_id: 'i1', code: 'I-IC', name_bn: 'বরফ', name_en: 'Ice', qty: 50, label: 'cost_missing' }], err: {}, chk: { user_id: 'u-bot', is_bot: true, has_intake_role: true, pos_enter: false } };
 c.rpc = async (fn, args) => {
  if (!/^(item_cost_free_set|item_cost_flags_list|cost_unknown_items|intake_bot_create|intake_bot_check)$/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === 'item_cost_flags_list') return { data: clone(W.flags), error: null };
  if (fn === 'cost_unknown_items') return { data: clone(W.unk), error: null };
  if (fn === 'item_cost_free_set') { if (args.p_free) { W.flags.push({ item_id: args.p_item, code: 'I-IC', name_bn: 'বরফ', name_en: 'Ice', reason: args.p_reason }); W.unk = []; } else W.flags = W.flags.filter((f) => f.item_id !== args.p_item); return { data: { item_id: args.p_item, cost_free: args.p_free }, error: null }; }
  if (fn === 'intake_bot_create') return { data: { user_id: args.p_user, role: 'intake_bot', location_id: args.p_loc, active: true }, error: null };
  if (fn === 'intake_bot_check') return { data: clone(W.chk), error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept(o.reason === undefined ? 'tap water, no purchase cost' : o.reason));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => ({ ok: document.documentElement.scrollWidth <= window.innerWidth + 1 })); ok(r.ok, 'no horizontal overflow: ' + m); };
  const BN = /[ঀ-৿]/;

  // ---- no access without the cost right
  let p = await open({ owner: false, m: { grants: [] } }, '#/s1setup');
  ok(/cost right is needed/.test(await p.textContent('#s1_body')) && await p.locator('[data-act=s1_free]').count() === 0, 'no cost right: nothing is shown');
  await p.close();

  // ---- owner, English: marked + unknown lists, no Bangla characters in the page text
  p = await open({}, '#/s1setup');
  ok(await p.locator('[data-act=s1_tab]').count() === 2, 'two tabs');
  ok(await p.locator('[data-act=s1_unfree]').count() === 1 && await p.locator('[data-act=s1_free]').count() === 1, 'one marked item, one unknown-cost item');
  ok(/Cost missing/.test(await p.textContent('#s1_body')), 'the cost_missing label is shown for the unknown-cost item');
  const txt = await p.textContent('#s1_body'); ok(!BN.test(txt.replace(/বরফ|পানি/g, '')), 'English mode: no Bangla characters in the screen text (item names are data)');
  const c0 = await calls(p, 'cost_unknown_items'); ok(c0.length >= 1 && c0[0].p_loc === null, 'unknown list asked for all places');
  await p.screenshot({ path: OUT + '/s1_free.png' }); await noOverflow(p, 'free tab');
  // mark free: asks the reason, sends item + reason + client id
  await p.click('[data-act=s1_free]'); await wait(p, 400);
  let c = await calls(p, 'item_cost_free_set'); ok(c.length === 1 && c[0].p_item === 'i1' && c[0].p_free === true && c[0].p_reason === 'tap water, no purchase cost' && typeof c[0].p_client === 'string', 'mark sends item, reason, client id');
  ok(await p.locator('[data-act=s1_unfree]').count() === 2 && await p.locator('[data-act=s1_free]').count() === 0, 'the item moved to the marked list');
  await p.click('[data-act=s1_unfree][data-id=i1]'); await wait(p, 400);
  c = await calls(p, 'item_cost_free_set'); ok(c.length === 2 && c[1].p_free === false && c[1].p_reason === null, 'unmark sends free=false without a reason');
  await p.close();
  // short reason is not sent
  p = await open({ reason: 'ab' }, '#/s1setup'); await p.click('[data-act=s1_free]'); await wait(p, 300);
  ok((await calls(p, 'item_cost_free_set')).length === 0, 'a reason shorter than 3 characters is not sent');
  await p.close();
  // server error shown (no technical text)
  p = await open({}, '#/s1setup'); await p.evaluate(() => { window.__M.s1.err.item_cost_free_set = 'reason_required'; }); await p.click('[data-act=s1_free]'); await wait(p, 400);
  ok(/reason is needed/i.test(await p.textContent('body')), 'server error reason_required is shown in words');
  await p.close();

  // ---- bot tab
  p = await open({}, '#/s1setup'); await p.click('[data-act=s1_tab][data-v=bot]'); await wait(p, 400);
  ok(/cannot sell \(POS\)/.test(await p.textContent('#s1_body')), 'the bot note says it cannot sell');
  await p.selectOption('#s1_user', 'u-bot'); await p.selectOption('#s1_bloc', '1'); await p.click('[data-act=s1_botmake]'); await wait(p, 500);
  c = await calls(p, 'intake_bot_create'); ok(c.length === 1 && c[0].p_user === 'u-bot' && c[0].p_loc === 1, 'intake_bot_create with user and place');
  ok((await calls(p, 'intake_bot_check')).length === 1 && /Has a POS right: No/.test((await p.textContent('#s1_body')).replace(/\s+/g, ' ')), 'the check result shows no POS right');
  await p.screenshot({ path: OUT + '/s1_bot.png' }); await noOverflow(p, 'bot tab');
  await p.evaluate(() => { window.__M.s1.err.intake_bot_create = 'bot_has_pos_role'; }); await p.click('[data-act=s1_botmake]'); await wait(p, 400);
  ok(/already has a POS right/.test(await p.textContent('body')), 'bot_has_pos_role is shown in words');
  await p.close();
  p = await open({ owner: false, m: { grants: ['view_cost'] } }, '#/s1setup'); await p.click('[data-act=s1_tab][data-v=bot]'); await wait(p, 300);
  ok(await p.locator('[data-act=s1_botmake]').count() === 0, 'a cost-right holder who is not the owner cannot set up a bot');
  await p.close();

  // ---- Bangla
  p = await open({ lang: 'bn' }, '#/s1setup');
  ok(/খরচ/.test(await p.textContent('header.top h1')), 'Bangla title');
  ok(/খরচ অজানা/.test(await p.textContent('#s1_body')), 'Bangla label for cost_missing');
  await p.screenshot({ path: OUT + '/s1_bn.png' }); await noOverflow(p, 'Bangla');
  await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
