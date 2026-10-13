// Module F web piece: the bell + #/notifications (list, filters, open + mark read, mark all read, friendly errors, backup card, 60 s poll, 360px width).
// Run: node notifications_test.js <abs tests/web dir>      (web/notifications.js is injected into index.html here; the lead adds the real <script> tag, see docs/regs/notifications.md)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8361, srv = C.serve(PORT);
const iso = (minAgo) => new Date(Date.now() - minAgo * 60000).toISOString();
const NOTES = () => [
  { id: 14, kind: 'red_exceptions', level: 'bad', title_bn: '৩টি লাল এক্সেপশন খোলা পড়ে আছে', title_en: '3 red exception(s) still open', body_bn: 'সবচেয়ে পুরনোটি ৩০ ঘণ্টা', body_en: 'The oldest has been open 30 hours', route: 'exceptions', location_id: null, created_at: iso(5), is_read: false },
  { id: 13, kind: 'low_stock', level: 'warn', title_bn: '২টি আইটেমের স্টক কম', title_en: '2 item(s) low in stock', body_bn: null, body_en: null, route: 'stock', location_id: 1, created_at: iso(125), is_read: false },
  { id: 12, kind: 'parallel_decision', level: 'info', title_bn: '14-1: গত মাসের সিদ্ধান্ত বাকি', title_en: '14-1: last month decision waiting', body_bn: null, body_en: null, route: 'parallel', location_id: 1, created_at: iso(3000), is_read: true },
  { id: 11, kind: 'x', level: 'warn', title_bn: '<img src=x onerror=window.__XSS=1>', title_en: '<img src=x onerror=window.__XSS=1>', body_bn: null, body_en: null, route: '', location_id: null, created_at: iso(10), is_read: false },
];
const EXTRA10 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 window.__INT = []; const si = window.setInterval; window.setInterval = function(f, ms) { window.__INT.push(ms); return si.apply(window, arguments); };
 window.__NT = window.__NT || { rows: window.__NOTES, unread: 3 };
 c.rpc = async (fn, args) => {
  (window.__AC10 = window.__AC10 || []).push([fn, JSON.parse(JSON.stringify(args || {}))]);
  const N = window.__NT;
  if (fn === 'notifications_for_me') { let r = N.rows.slice(); if (args.p_unread_only) r = r.filter((x) => !x.is_read); if (args.p_level) r = r.filter((x) => x.level === args.p_level); return { data: r, error: null }; }
  if (fn === 'notifications_unread_count') { N.polls = (N.polls || 0) + 1; return { data: N.rows.filter((x) => !x.is_read).length + (N.extra || 0), error: null }; }
  if (fn === 'notification_read') { if (window.__NERR) { return { data: null, error: { message: 'not allowed', code: 'P0001' } }; } const x = N.rows.find((y) => y.id === args.p_id); if (x) x.is_read = true; return { data: true, error: null }; }
  if (fn === 'notification_read_all') { N.rows.forEach((x) => { x.is_read = true; }); return { data: 4, error: null }; }
  if (fn === 'backup_status') return { data: { configured: true, max_age_hours: 36, age_hours: 52.5, last_ok: { at: '2026-10-11T02:40:00Z', tables: 60, rows: 12345 }, last_run: { at: '2026-10-12T02:40:00Z', status: 'failed' }, failed_last: true, stale: true }, error: null };
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA10 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/notifications\.js/.test(h) ? h : h.replace('</body>', '<script src="notifications.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {}); data.tables.backup_runs = [{ finished_at: '2026-10-12T02:40:00Z', status: 'failed', tables: 60, rows: 0 }, { finished_at: '2026-10-11T02:40:00Z', status: 'ok', tables: 60, rows: 12345 }];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__NOTES=${JSON.stringify(o.empty ? [] : NOTES())};window.__OWNER=${o.owner === false ? 'false' : 'true'};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC10 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // list
  let p = await open('#/notifications');
  ok(await p.locator('.nt-row').count() === 4, 'four notes listed');
  let t = await text(p);
  ok(/3 red exception/.test(t) && /Urgent/.test(t) && /Warning/.test(t) && /Info/.test(t), 'titles and level labels (English)');
  const order = await p.locator('.nt-row b').allTextContents(); ok(/red exception/.test(order[0]), 'newest (server order) first');
  ok(await p.locator('.nt-row.unread').count() === 3 && await p.locator('.nt-row.read').count() === 1, 'unread and read styled apart');
  ok(await p.evaluate(() => !window.__XSS) && await p.locator('.nt-row img').count() === 0, 'note text is escaped (no HTML injected)');
  ok(/Automatic backup/.test(t), 'owner sees the backup card');
  await p.evaluate(() => { document.querySelector('#nt_body details').open = true; }); await wait(p, 100);
  t = await text(p); ok(/Out of date/.test(t) && /52\.5/.test(t) && /failed/.test(t), 'backup card shows stale + last runs');
  ok(await p.locator('a[href="#/switchboard"]').count() === 1, 'link to the Switchboard');
  await noOverflow(p, 'list'); await p.screenshot({ path: SP + '/nt_list.png', fullPage: true });
  ok((await p.locator('.nt-row').first().boundingBox()).height >= 40, 'tap size >= 40px');

  // filters
  await p.selectOption('#nt_unread', '1'); await wait(p, 400);
  let c = await calls(p, 'notifications_for_me'); ok(c[c.length - 1].p_unread_only === true, 'unread filter sent'); ok(await p.locator('.nt-row').count() === 3, 'only unread shown');
  await p.selectOption('#nt_level', 'bad'); await wait(p, 400);
  c = await calls(p, 'notifications_for_me'); ok(c[c.length - 1].p_level === 'bad' && c[c.length - 1].p_unread_only === true, 'level filter sent with the unread filter'); ok(await p.locator('.nt-row').count() === 1, 'one urgent unread');

  // open + mark read -> goes to its screen
  await p.locator('.nt-row').first().click(); await wait(p, 500);
  c = await calls(p, 'notification_read'); ok(c.length === 1 && c[0].p_id === 14, 'tap marks that note read');
  ok(/#\/exceptions/.test(p.url()), 'tap opens the note screen (exceptions)');

  // mark all read
  p = await open('#/notifications');
  await p.click('[data-act=nt_all]'); await wait(p, 500);
  c = await calls(p, 'notification_read_all'); ok(c.length === 1, 'mark all read sent');
  ok(await p.locator('.nt-row.unread').count() === 0, 'nothing unread after mark all');

  // friendly error
  p = await open('#/notifications');
  await p.evaluate(() => { window.__NERR = true; }); await p.locator('.nt-row.warn').first().click(); await wait(p, 500);
  ok(/Not allowed/.test(await p.evaluate(() => document.getElementById('toast').textContent)), 'friendly "Not allowed" text, not a raw error');

  // bell + 60 s poll
  p = await open('#/notifications');
  const html = await p.evaluate(() => window.BOS.notifications.badge());
  ok(/nt-bell/.test(html) && /data-v="notifications"/.test(html), 'badge() returns the bell button');
  ok(await p.evaluate(() => window.__INT.includes(60000)), 'the poll runs every 60 s');
  await p.evaluate(() => { document.body.insertAdjacentHTML('beforeend', window.BOS.notifications.badge()); window.__NT.extra = 4; });
  await p.evaluate(() => window.BOS.notifications.refresh()); await wait(p, 300);
  ok(await p.evaluate(() => window.BOS.notifications.count()) === 7, 'unread count = 3 + 4 after a poll');
  ok(await p.evaluate(() => [...document.querySelectorAll('.nt-badge')].every((e) => e.textContent === '7' && !e.hidden)), 'every badge shows 7');
  ok(await p.evaluate(() => { const b = document.querySelector('.nt-bell'); const r = b.getBoundingClientRect(); return r.width >= 40 && r.height >= 40; }), 'bell tap size >= 40px');
  ok((await calls(p, 'notifications_unread_count')).length >= 2, 'the count is a cheap RPC (no list loaded)');

  // empty + Bangla + non-owner
  p = await open('#/notifications', { empty: true, lang: 'bn', owner: false });
  t = await text(p); ok(/কোনো নোটিফিকেশন নেই/.test(t), 'Bangla empty state'); ok(!/ব্যাকআপ/.test(t), 'non-owner has no backup card'); ok(/নোটিফিকেশন/.test(await p.locator('h1').textContent()), 'Bangla title');
  await noOverflow(p, 'empty'); await p.screenshot({ path: SP + '/nt_bn.png', fullPage: true });

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
