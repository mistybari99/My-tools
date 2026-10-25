// Error log (web/errlog.js, phase107 step Errlog) in Chromium with a mocked supabase client (tests/web/stub.js + extra rpc handlers).
// Run: node tests/web/errlog_test.js [abs tests/web dir]      (serves ../../web of this checkout)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR, PORT = _P.freePort();
const SHOT = process.env.SHOT_DIR || '';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8');
const mkData = () => new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
// window.__SENT = batches received by client_error_log ; __LOGMODE ok|error|throw ; __RPCERR = { fn: {code,message} | {reject} } ; __LIST/__LISTERR for client_errors_list
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = []; window.__SENT = []; window.__RESOLVED = [];
 c.rpc = async (fn, args) => { window.__CALLS.push(fn);
  if (fn === 'client_error_log') { const m = window.__LOGMODE || 'ok'; window.__SENT.push(JSON.parse(JSON.stringify(args))); if (m === 'throw') throw new Error('log boom'); if (m === 'error') return { data: null, error: { message: 'down', code: 'XX000' } }; return { data: { ok: true, accepted: (args.p_batch || []).length }, error: null }; }
  if (fn === 'client_errors_list') return window.__LISTERR ? { data: null, error: { message: 'not allowed', code: 'P0001' } } : { data: JSON.parse(JSON.stringify(window.__LIST || [])), error: null };
  if (fn === 'client_error_resolve') { window.__RESOLVED.push(args); const row = (window.__LIST || []).find((r) => r.id === args.p_id); (window.__LIST || []).forEach((r) => { if (row && r.fingerprint === row.fingerprint) r.resolved_at = '2026-10-14T01:00:00Z'; }); return { data: { ok: true, resolved: 1 }, error: null }; }
  const e = (window.__RPCERR || {})[fn]; if (e) { if (e.reject) throw new TypeError(e.reject); return { data: null, error: e }; }
  return rpc(fn, args); };
 return c; }; })();`;
const SPY = `(function(){ window.__LIS = []; const ae = window.addEventListener; window.addEventListener = function(t){ window.__LIS.push(t); return ae.apply(this, arguments); }; const de = document.addEventListener; document.addEventListener = function(t){ window.__LIS.push('doc:' + t); return de.apply(this, arguments); };
 window.__TIM = 0; const si = window.setInterval; window.setInterval = function(){ window.__TIM++; return si.apply(this, arguments); }; })();`;
const R = (key, value) => ({ key, value, default_value: null, kind: 'switch', sort: 1 });
const lroot = (id, fp, o) => Object.assign({ id, at: '2026-10-14T01:00:00Z', last_at: '2026-10-14T02:00:00Z', user_id: 'u1', staff_id: 'owner1', app_build: 'b9', route: '#/items', kind: 'js_error', message: 'TypeError: x is undefined', stack: 'TypeError: x\n  at foo (app.js:1:1)', ua: 'UA', lang: 'en', extra: null, user_note: null, fingerprint: fp, count: 1, resolved_at: null, resolve_note: null }, o || {});
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0, pass = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else pass++; };
  async function open(hash, o = {}) {
    const data = mkData(); data.tables.rules = (data.tables.rules || []).filter((r) => !/^client_err/.test(r.key)); if (o.rule !== undefined) data.tables.rules.push(R('client_errors_on', o.rule));
    const ctx = await br.newContext({ viewport: { width: 360, height: 760 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => { if (!/PLANTED/.test(e.message)) errors.push('pageerror: ' + e.message); });
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|ERR_|PLANTED/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};${o.owner === false ? 'window.__OWNER=false;' : ''}window.__ER_FLUSH_MS=${o.flushMs || 400};${o.spy ? SPY : ''}window.__LIST=${JSON.stringify(o.list || [])};window.__LOGMODE=${JSON.stringify(o.logmode || 'ok')};window.__RPCERR=${JSON.stringify(o.rpcerr || {})};
      try{localStorage.setItem('bos_lang',${JSON.stringify(o.lang || 'en')});${o.ls ? Object.entries(o.ls).map(([k, v]) => `if(!sessionStorage.getItem('__seed')){localStorage.setItem(${JSON.stringify(k)},${JSON.stringify(v)});}`).join('') : ''}sessionStorage.setItem('__seed','1')}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(o.wait || 1400);
    return { p, ctx };
  }
  const st = (p) => p.evaluate(() => window.BOS.errlog && window.BOS.errlog.state());
  const sent = (p) => p.evaluate(() => window.__SENT);
  const items = (p) => p.evaluate(() => window.__SENT.flatMap((b) => b.p_batch));
  const plant = (p, msg) => p.evaluate((m) => { setTimeout(() => { throw new Error(m); }, 0); }, msg);
  const flush = (p) => p.evaluate(() => window.BOS.errlog.flush());

  // 1. rule ON: script error + rejection captured, batched, route cleaned, build from ?v=, no secrets
  let { p, ctx } = await open('#/items?search=milk&token=SECRETTOKEN', { rule: true, flushMs: 60000 });
  let s = await st(p);
  ok(s && s.ruleDone && s.installed && s.on && s.patched, 'rule on: confirmed, listeners + rpc wrapper installed ' + JSON.stringify(s));
  ok(await p.evaluate(() => localStorage.getItem('bos_er_on')) === '1', 'the answer is remembered for the next start');
  await p.evaluate(() => { const sc = document.createElement('script'); sc.type = 'text/plain'; sc.src = 'x.js?v=b77'; document.head.appendChild(sc); });
  await plant(p, 'PLANTED boom 123456789 for bob@example.com'); await p.waitForTimeout(100);
  await p.evaluate(() => { Promise.reject(new Error('PLANTED rejection')); }); await p.waitForTimeout(100);
  s = await st(p); ok(s.queue === 2, 'two errors queued (' + s.queue + ')');
  ok((await sent(p)).length === 0, 'nothing sent before the flush (batching)');
  await flush(p); const it = await items(p);
  ok(it.length === 2 && it.some((x) => x.kind === 'js_error') && it.some((x) => x.kind === 'unhandled_rejection'), 'one batch with both kinds');
  const je = it.find((x) => x.kind === 'js_error');
  ok(!/123456789|bob@example/.test(je.message) && /\[num\]/.test(je.message) && /\[email\]/.test(je.message), 'digits and e-mail scrubbed on the phone: ' + je.message);
  ok(!/\?|SECRETTOKEN/.test(je.route) && /^#\/items/.test(je.route), 'route has no query / token: ' + je.route);
  ok(je.app_build === 'b77' || je.app_build === 'dev', 'app_build taken from the ?v= param (' + je.app_build + ')');
  ok(JSON.stringify(await sent(p)).indexOf('SECRETTOKEN') < 0, 'no token in anything sent');
  ok(je.lang === 'en' && je.ua && je.cid, 'lang, ua and a client id are sent');
  s = await st(p); ok(s.queue === 0, 'queue emptied after a successful flush');
  const build = await p.evaluate(() => { const sc = document.createElement('script'); sc.type = 'text/plain'; sc.src = 'x.js?v=b77'; document.head.appendChild(sc); return [...document.querySelectorAll('script[src]')].map((x) => x.getAttribute('src')).some((x) => /v=b77/.test(x)); });
  ok(build, 'build param detectable');
  await ctx.close();

  // 1b. app_build really read from a script src with ?v= present BEFORE errlog runs
  ({ p, ctx } = await open('#/home', { rule: true, flushMs: 60000 }));
  ok(await p.evaluate(() => { const sc = document.createElement('script'); sc.type = 'text/plain'; sc.src = 'x.js?v=b78'; document.head.appendChild(sc); window.BOS.errlog.report('js_error', 'PLANTED build test'); return true; }), 'report call ok');
  await flush(p); ok((await items(p)).some((x) => x.app_build === 'b78'), 'app_build = b78 from the script tag ?v=b78'); await ctx.close();

  // 2. rpc errors: system errors logged, business errors / offline network not; arguments never read
  ({ p, ctx } = await open('#/home', { rule: true, flushMs: 60000, rpcerr: { fn_missing: { code: 'PGRST202', message: 'Could not find the function public.fn_missing' }, fn_biz: { code: 'P0001', message: 'not allowed' }, fn_dup: { code: '23505', message: 'duplicate key value' }, fn_perm: { code: '42501', message: 'permission denied' }, fn_net: { reject: 'Failed to fetch' }, fn_syntax: { code: '42883', message: 'function fn_syntax(text) does not exist' } } }));
  await p.evaluate(async () => { const sb = window.BOS_APP.sb; for (const f of ['fn_missing', 'fn_biz', 'fn_dup', 'fn_perm', 'fn_syntax']) await sb.rpc(f, { p_body: 'SENSITIVE-BODY-1', p_token: 'TOK' }); try { await sb.rpc('fn_net', { p_body: 'SENSITIVE-BODY-2' }); } catch (e) { /* rethrown to the caller as before */ } });
  await flush(p); let all = await items(p);
  ok(all.filter((x) => x.kind === 'rpc_error').length === 3, 'rpc_error for missing function, 42883 and online network failure only (' + all.map((x) => x.message).join(' | ') + ')');
  ok(!all.some((x) => /not allowed|duplicate key|permission denied/.test(x.message)), 'business errors (P0001, 23505, 42501) are not logged');
  ok(JSON.stringify(all).indexOf('SENSITIVE') < 0 && JSON.stringify(all).indexOf('TOK') < 0, 'rpc arguments / bodies are never in the log');
  ok(all.some((x) => x.extra && x.extra.fn === 'fn_missing' && x.extra.code === 'PGRST202'), 'extra carries fn + code only');
  ok(await p.evaluate(async () => { try { await window.BOS_APP.sb.rpc('fn_net', {}); return 'no throw'; } catch (e) { return e instanceof TypeError; } }), 'the original rejection still reaches the caller (wrapper is transparent)');
  const calls0 = await p.evaluate(() => window.__CALLS.filter((c) => c === 'client_error_log').length);
  ok(await p.evaluate(() => window.BOS_APP.sb.rpc('my_context').then((r) => !!(r && r.data))), 'normal rpc results are untouched');
  await ctx.close();

  // 2b. offline: network failures not logged
  ({ p, ctx } = await open('#/home', { rule: true, flushMs: 60000, rpcerr: { fn_net: { reject: 'Failed to fetch' } } }));
  await ctx.setOffline(true); await p.waitForTimeout(100);
  await p.evaluate(async () => { try { await window.BOS_APP.sb.rpc('fn_net', {}); } catch (e) { /* ok */ } });
  s = await st(p); ok(s.queue === 0, 'offline: a network failure is not logged');
  // 3. offline queue: a script error offline is queued (localStorage), sent after "online"
  await plant(p, 'PLANTED offline error'); await p.waitForTimeout(150);
  s = await st(p); ok(s.queue === 1, 'offline: script error queued'); ok(await p.evaluate(() => JSON.parse(localStorage.getItem('bos_er_q') || '[]').length) === 1, 'queue mirrored to localStorage');
  await flush(p); ok((await sent(p)).length === 0, 'offline: no call is made');
  await ctx.setOffline(false); await p.waitForTimeout(500);
  ok((await items(p)).some((x) => /offline error/.test(x.message)), 'back online: the queued error is sent (online event)'); await ctx.close();

  // 3b. queue survives a reload
  ({ p, ctx } = await open('#/home', { rule: true, flushMs: 60000, ls: { bos_er_q: JSON.stringify([{ cid: 'old1', kind: 'js_error', message: 'PLANTED from last session', route: '#/x', k: 'k1', count: 1 }]), bos_er_on: '1' }, wait: 1200 }));
  s = await st(p); ok(s.queue >= 0, 'start with stored queue ok'); await flush(p);
  ok((await items(p)).some((x) => x.cid === 'old1'), 'a queue stored by the last session is sent'); await ctx.close();

  // 4. batching: 25 distinct errors -> batches of 20 + 5 ; same error 3x -> one item count 3 ; max 50
  ({ p, ctx } = await open('#/home', { rule: true, flushMs: 60000 }));
  await p.evaluate(() => { for (let i = 0; i < 3; i++) window.BOS.errlog.report('js_error', 'same error ' + i, '', null); });
  s = await st(p); ok(s.queue === 1, 'same error three times = one queued item (' + s.queue + ')');
  await p.evaluate(() => { for (let i = 0; i < 15; i++) window.BOS.errlog.report('js_error', 'distinct error ' + String.fromCharCode(65 + i), '', null); });
  s = await st(p); ok(s.queue === 16, 'distinct errors queued (' + s.queue + ')');
  await flush(p); const b = await sent(p); ok(b.length === 1 && b[0].p_batch.length === 16 && b[0].p_batch.find((x) => /same error/.test(x.message)).count === 3, 'one batch, the repeated error carries count 3');
  // runaway guard: a loop of errors cannot flood the phone (20 per minute) and the queue is capped at 50
  await p.evaluate(() => { window.__SENT.length = 0; for (let i = 0; i < 200; i++) window.BOS.errlog.report('js_error', 'flood ' + 'abcdefghij'.charAt(i % 10) + 'x'.repeat(i % 7) + 'y' + (i % 13 > 99 ? 1 : 0) + String.fromCharCode(97 + (i % 26)) + String.fromCharCode(97 + ((i / 26) | 0)), '', null); });
  s = await st(p); ok(s.queue <= 20 && s.dropped > 0, 'flood of 200 reports: capped on the phone (queue ' + s.queue + ', dropped ' + s.dropped + ')');
  await ctx.close();

  // 4b. timer flush: no manual flush, the 30 s timer (here 400 ms) sends
  ({ p, ctx } = await open('#/home', { rule: true, flushMs: 400 }));
  await plant(p, 'PLANTED timer error'); await p.waitForTimeout(1300);
  ok((await items(p)).some((x) => /timer error/.test(x.message)), 'the timer flushes without a manual call');
  // pagehide / visibilitychange flush
  await plant(p, 'PLANTED hide error'); await p.waitForTimeout(80);
  await p.evaluate(() => window.dispatchEvent(new Event('pagehide'))); await p.waitForTimeout(150);
  ok((await items(p)).some((x) => /hide error/.test(x.message)), 'pagehide flushes the queue'); await ctx.close();

  // 5. rule OFF (row false): nothing installed, nothing sent, no listener / timer cost
  ({ p, ctx } = await open('#/home', { rule: false, spy: true, flushMs: 400 }));
  s = await st(p); ok(s && s.ruleDone && !s.installed && !s.on && !s.patched && !s.infra, 'rule off: nothing installed ' + JSON.stringify(s));
  const lis = await p.evaluate(() => ({ l: window.__LIS.slice(), t: window.__TIM }));
  const afterErrlog = await p.evaluate(() => window.__LIS.filter((t) => t === 'error' || t === 'unhandledrejection' || t === 'doc:visibilitychange' || t === 'pagehide' || t === 'online'));
  ok(!afterErrlog.includes('error') && !afterErrlog.includes('unhandledrejection') && !afterErrlog.includes('pagehide'), 'rule off: no error / unhandledrejection / pagehide listener from errlog (' + afterErrlog + ')');
  ok(!(await p.evaluate(() => !!(window.BOS_APP.sb.rpc && window.BOS_APP.sb.rpc.__erWrap))), 'rule off: sb.rpc is not wrapped');
  await plant(p, 'PLANTED off'); await p.evaluate(() => { Promise.reject(new Error('PLANTED off rej')); }); await p.waitForTimeout(1200);
  s = await st(p); ok(s.queue === 0 && (await sent(p)).length === 0, 'rule off: nothing queued, nothing sent');
  ok(await p.evaluate(() => localStorage.getItem('bos_er_on')) === '0', 'rule off remembered');
  ok((await p.evaluate(() => window.__CALLS.filter((c) => c === 'client_error_log').length)) === 0, 'no client_error_log call at all'); await ctx.close();
  // 5b. no rule row at all = default off
  ({ p, ctx } = await open('#/home', { flushMs: 400 })); s = await st(p); ok(s.ruleDone && !s.installed, 'no rule row = off'); await plant(p, 'PLANTED nothing'); await p.waitForTimeout(700); ok((await sent(p)).length === 0, 'no rule row: nothing sent'); await ctx.close();
  // 5c. stale "on" flag from last start, rule now off: uninstalled once the rule is read
  ({ p, ctx } = await open('#/home', { rule: false, ls: { bos_er_on: '1' } })); s = await st(p); ok(s.ruleDone && !s.installed && !s.patched, 'stale on-flag is corrected by the rule'); ok(await p.evaluate(() => localStorage.getItem('bos_er_on')) === '0', 'flag updated to 0'); await ctx.close();

  // 6. logging that itself fails never loops, never throws, never floods
  for (const mode of ['error', 'throw']) {
    ({ p, ctx } = await open('#/home', { rule: true, flushMs: 150, logmode: mode }));
    await plant(p, 'PLANTED log fail ' + mode); await p.waitForTimeout(1800);
    const n = await p.evaluate(() => window.__CALLS.filter((c) => c === 'client_error_log').length); s = await st(p);
    ok(n >= 1 && n <= 2, mode + ': the failing log call is not retried in a storm (' + n + ' calls in 1.8 s with a 150 ms timer)');
    ok(s.queue === 1 && s.fails >= 1, mode + ': the item stays queued, back-off active (queue ' + s.queue + ', fails ' + s.fails + ')');
    await ctx.close();
  }
  // 6b. localStorage that throws on write
  { const data = mkData(); data.tables.rules = (data.tables.rules || []).concat([R('client_errors_on', true)]);
    const c2 = await br.newContext({ viewport: { width: 360, height: 760 } }); const q = await c2.newPage(); q.on('pageerror', (e) => { if (!/PLANTED/.test(e.message)) errors.push('pageerror(ls): ' + e.message); });
    await q.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA })); await q.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await q.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__ER_FLUSH_MS=60000;window.__LIST=[];window.__LOGMODE='ok';try{localStorage.setItem('bos_lang','en')}catch(e){}; const _s = Storage.prototype.setItem; Storage.prototype.setItem = function(k,v){ if (/^bos_er_/.test(k)) throw new Error('quota'); return _s.apply(this, arguments); };`);
    await q.goto('http://localhost:' + PORT + '/#/home'); await q.waitForTimeout(1300);
    await plant(q, 'PLANTED ls broken'); await q.waitForTimeout(150); s = await st(q); ok(s && s.queue === 1, 'localStorage write throws: the error is still queued in memory'); await flush(q);
    ok((await items(q)).some((x) => /ls broken/.test(x.message)), 'and still sent'); await c2.close(); }

  // 7. Report a problem
  ({ p, ctx } = await open('#/reportproblem', { rule: false, owner: false, flushMs: 60000 }));
  let t = await p.evaluate(() => document.body.innerText);
  ok(/Report a problem/.test(t) && /What will be sent/.test(t) && /Last 5 errors/.test(t) && /App build/.test(t) && /Language/.test(t), 'form shows what will be sent (route, build, language, last 5)');
  ok(await p.evaluate(() => { const a = document.querySelector('#er_note'); return !!a && a.maxLength === 1000; }), 'note box limited to 1000');
  await p.click('[data-act=er_send]'); await p.waitForTimeout(150);
  ok((await sent(p)).length === 0, 'empty note: nothing sent');
  await p.fill('#er_note', 'The total on the sale screen looks wrong'); ok(await p.evaluate(() => /40 \/ 1000/.test(document.getElementById('er_cnt').textContent)), 'character counter');
  await p.click('[data-act=er_send]'); await p.waitForTimeout(400);
  let ur = (await items(p)).find((x) => x.kind === 'user_report');
  ok(ur && ur.note === 'The total on the sale screen looks wrong' && ur.extra && Array.isArray(ur.extra.recent), 'Send -> kind user_report with the note (rule is OFF and it still goes)');
  ok(await p.evaluate(() => /Sent\. Thank you/.test(document.getElementById('er_res').textContent)), 'confirmation shown');
  s = await st(p); ok(s.queue === 0 && !s.installed, 'queue empty, capture still off');
  await ctx.close();
  // 7b. offline: queued, then sent
  ({ p, ctx } = await open('#/reportproblem', { rule: false, owner: false, flushMs: 60000 }));
  await ctx.setOffline(true); await p.waitForTimeout(100);
  await p.fill('#er_note', 'offline note'); await p.click('[data-act=er_send]'); await p.waitForTimeout(300);
  ok(await p.evaluate(() => /Saved on this phone/.test(document.getElementById('er_res').textContent)), 'offline: "saved on this phone" message');
  ok(await p.evaluate(() => JSON.parse(localStorage.getItem('bos_er_q') || '[]').some((x) => x.kind === 'user_report' && x.note === 'offline note')), 'offline: the report is in the localStorage queue');
  ok((await sent(p)).length === 0, 'offline: nothing sent yet');
  await ctx.setOffline(false); await p.waitForTimeout(500);
  ok((await items(p)).some((x) => x.note === 'offline note'), 'online again: the report is sent'); await ctx.close();
  // 7c. a note waiting in storage at start (rule off) is sent
  ({ p, ctx } = await open('#/home', { rule: false, flushMs: 300, ls: { bos_er_q: JSON.stringify([{ cid: 'rr1', kind: 'user_report', message: 'User report', note: 'older note', route: '#/x', k: 'x', count: 1 }]) }, wait: 1500 }));
  ok((await items(p)).some((x) => x.cid === 'rr1'), 'a stored user_report is sent at the next start even with the rule off'); await ctx.close();

  // 8. drawer footer entry + menu route
  ({ p, ctx } = await open('#/home', { rule: false, flushMs: 60000 }));
  await p.evaluate(() => window.BOS_NAV.open()); await p.waitForTimeout(500);
  ok(await p.evaluate(() => !!document.querySelector('#navDrawer .dr-fbar [data-act=er_open]')), 'drawer footer bar has the Report a problem button');
  ok(await p.evaluate(() => /Report a problem/.test(document.querySelector('#navDrawer .dr-fbar [data-act=er_open]').textContent)), 'English label');
  if (SHOT) await p.screenshot({ path: SHOT + '/errlog_drawer_360.png' });
  await p.click('#navDrawer [data-act=er_open]'); await p.waitForTimeout(500);
  ok(await p.evaluate(() => location.hash) === '#/reportproblem' && /What will be sent/.test(await p.evaluate(() => document.body.innerText)), 'tap opens #/reportproblem');
  ok(/dev|#\/home/.test(await p.evaluate(() => document.body.innerText)), 'the page names the screen the person came from');
  const ow = await p.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  ok(ow.sw <= ow.cw, 'Report a problem: no horizontal overflow at 360px (' + ow.sw + '/' + ow.cw + ')');
  if (SHOT) await p.screenshot({ path: SHOT + '/errlog_report_360.png' });
  const ia = await p.evaluate(() => { const IA = window.BOS.IA; const c = (own) => ({ own, P: () => false, GF: {}, locOk: () => true, canPos: () => false, anyApprove: () => false, ctlOk: () => false }); const a = IA.find((x) => x.id === 'reportproblem'), b = IA.find((x) => x.id === 'problems');
    return { a: !!a && a.ok(c(false)) && a.ok(c(true)) && a.group === 'settings', b: !!b && b.ok(c(true)) && !b.ok(c(false)), pages: !!window.BOS_PAGES.reportproblem && !!window.BOS_PAGES.problems }; });
  ok(ia.a && ia.b && ia.pages, 'IA: reportproblem for everybody, problems for the owner only; both have page handlers ' + JSON.stringify(ia));
  await ctx.close();

  // 9. Problems page (owner)
  const list = [lroot(1, 'fpA', { count: 3, last_at: '2026-10-14T03:00:00Z' }), lroot(2, 'fpA', { count: 4, at: '2026-10-14T02:30:00Z', last_at: '2026-10-14T02:40:00Z', user_id: 'u2' }), lroot(3, 'fpB', { kind: 'rpc_error', message: 'rpc stock_levels: function does not exist', route: '#/stock', count: 2, last_at: '2026-10-14T01:30:00Z' }),
    lroot(4, 'fpC', { kind: 'user_report', message: 'User report', user_note: 'the total looks wrong', route: '#/sale', last_at: '2026-10-14T00:30:00Z', resolved_at: '2026-10-14T05:00:00Z' })];
  ({ p, ctx } = await open('#/problems', { rule: true, list, flushMs: 60000, wait: 1600 }));
  let g = await p.evaluate(() => [...document.querySelectorAll('.er-grp')].map((e) => ({ t: e.innerText.replace(/\s+/g, ' '), res: e.classList.contains('res') })));
  ok(g.length === 2, 'open filter: two groups (fpA merged from 2 rows, fpB); resolved one hidden (' + g.length + ')');
  ok(/7 times/.test(g[0].t) && /2 users/.test(g[0].t) && /TypeError/.test(g[0].t) && /#\/items/.test(g[0].t) && /b9/.test(g[0].t), 'group shows count 3+4=7, users, route, build: ' + g[0].t);
  ok(/last 14 Oct/.test(g[0].t) || /last/.test(g[0].t), 'last seen shown');
  ok(g[0].t.indexOf('TypeError') < g[0].t.length && /rpc stock_levels/.test(g[1].t), 'newest first');
  await p.click('[data-act=er_filter][data-v=resolved]'); await p.waitForTimeout(100);
  g = await p.evaluate(() => [...document.querySelectorAll('.er-grp')].map((e) => e.innerText.replace(/\s+/g, ' '))); ok(g.length === 1 && /User report|total looks wrong/.test(g[0]), 'resolved filter shows the resolved group with its note');
  ok(await p.evaluate(() => document.querySelectorAll('.er-grp [data-act=er_resolve]').length) === 0, 'a resolved group has no Resolve button');
  await p.click('[data-act=er_filter][data-v=all]'); await p.waitForTimeout(100); ok(await p.evaluate(() => document.querySelectorAll('.er-grp').length) === 3, 'all filter: 3 groups');
  await p.click('[data-act=er_filter][data-v=open]'); await p.waitForTimeout(100);
  await p.fill('#er_rnote', 'fixed in b10'); await p.click('.er-grp >> nth=0 >> [data-act=er_resolve]'); await p.waitForTimeout(500);
  const rs = await p.evaluate(() => window.__RESOLVED); ok(rs.length === 1 && rs[0].p_note === 'fixed in b10' && (rs[0].p_id === 1 || rs[0].p_id === 2), 'Resolve calls client_error_resolve with an id and the note ' + JSON.stringify(rs));
  g = await p.evaluate(() => document.querySelectorAll('.er-grp').length); ok(g === 1, 'after resolve the list reloads: one open group left (' + g + ')');
  await p.click('[data-act=er_filter][data-v=all]'); await p.waitForTimeout(100);
  await p.evaluate(() => { window.__CLIP = null; Object.defineProperty(navigator, 'clipboard', { value: { writeText: async (x) => { window.__CLIP = x; } }, configurable: true }); });
  await p.click('[data-act=er_copy]'); await p.waitForTimeout(200);
  const clip = await p.evaluate(() => window.__CLIP); ok(clip && /BOS problems \(all\)/.test(clip) && /7x/.test(clip) && /TypeError: x is undefined/.test(clip) && /\[rpc_error\]/.test(clip) && /note: the total looks wrong/.test(clip), 'copy as text puts a pasteable summary on the clipboard');
  ok(!/ya29|token|password/i.test(clip), 'copied text has no secrets');
  const pw = await p.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth }));
  ok(pw.sw <= pw.cw, 'Problems page: no horizontal overflow at 360px (' + pw.sw + '/' + pw.cw + ')');
  if (SHOT) await p.screenshot({ path: SHOT + '/errlog_problems_360.png' });
  await ctx.close();
  // 9b. refused for someone without access; clipboard fallback
  { const o = await open('#/problems', { rule: true, list: [], flushMs: 60000, wait: 300 });
    await o.p.evaluate(() => { window.__LISTERR = true; }); await o.p.click('[data-act=er_refresh]'); await o.p.waitForTimeout(400);
    ok(await o.p.evaluate(() => /owner or have permission/.test(document.body.innerText)), 'no access: friendly notice, no crash'); await o.ctx.close(); }
  { const o = await open('#/problems', { rule: true, list: [], flushMs: 60000, wait: 1000 });
    ok(await o.p.evaluate(() => /No problems/.test(document.body.innerText)), 'empty list: "No problems"'); await o.ctx.close(); }
  { const o = await open('#/problems', { rule: false, list, flushMs: 60000, wait: 1600 });
    await o.p.evaluate(() => { Object.defineProperty(navigator, 'clipboard', { value: undefined, configurable: true }); }); await o.p.click('[data-act=er_copy]'); await o.p.waitForTimeout(300);
    ok(await o.p.evaluate(() => { const b = document.getElementById('er_copybox'); return !b.hidden && /BOS problems/.test(b.value); }), 'copy fallback box shown when the clipboard API is unavailable'); await o.ctx.close(); }

  // 10. languages
  for (const lg of ['bn', 'mix', 'en']) {
    const o = await open('#/reportproblem', { rule: false, lang: lg, flushMs: 60000, wait: 1000 });
    const tx = await o.p.evaluate(() => document.querySelector('#app, main, body').innerText);
    if (lg === 'en') ok(!/[ঀ-৿]/.test(tx.replace(/\s/g, '')) || !/[ঀ-৿]/.test(await o.p.evaluate(() => document.getElementById('er_body').innerText)), 'English mode: the Report a problem page has no Bangla');
    if (lg === 'bn') ok(/সমস্যা জানান/.test(tx) && /Last|শেষ ৫টি/.test(tx), 'Bangla mode shows Bangla');
    if (lg === 'mix') ok(/Problem জানান/.test(tx), 'mix mode: Bng/Eng');
    await o.ctx.close();
  }
  { const o = await open('#/problems', { rule: true, lang: 'en', list, flushMs: 60000, wait: 1500 });
    ok(!/[ঀ-৿]/.test(await o.p.evaluate(() => document.getElementById('er_body').innerText)), 'English mode: Problems page has no Bangla'); await o.ctx.close(); }

  // 11. existing screens keep working with the rule on (home, items, pos): no page errors from errlog
  { const o = await open('#/pos', { rule: true, flushMs: 60000, wait: 1400 }); ok((await o.p.evaluate(() => document.querySelectorAll('.pos-item').length)) > 3, 'POS still renders with capture on'); await o.ctx.close(); }

  ok(errors.length === 0, 'no unexpected page errors: ' + errors.join(' | '));
  await br.close(); srv.close();
  console.log(`errlog_test: ${pass} passed, ${bad} failed`);
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(2); });
