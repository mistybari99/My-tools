// Backup button (Home > Backup, owner): the JSON download must work on every tap, not only the first one or two.
// The real app (web/app.js) with the in-page supabase stub (tests/web/stub.js) at 360 px.
// Taps the "all data" backup 5 times in a row; each tap must start one download (Playwright download event),
// the file must be non-empty JSON with the expected top-level keys, and a failed backup must show a Bengali message and a retry button.
// Run: node tests/web/backup_button_test.js <abs tests/web dir>   (LAT=400 adds a 400 ms delay per table read, like a phone on mobile data)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname;
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web');
const base = C.baseData(SP), PORT = Number(process.env.PORT) || 8611, LAT = Number(process.env.LAT || 0);
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f);
    r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
// latency wrapper: every table read / rpc takes LAT ms before it resolves (the stub builder is thenable, so wrapping then() is enough)
const LATWRAP = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const from = c.from; const rpc = c.rpc;
  const lat = () => new Promise((r) => setTimeout(r, Number(window.__LAT) || 0));
  // window.__FAIL = true: every table read fails (network down); window.__FAILTABLE = 'name': only that table fails
  c.from = (t) => { const q = from(t); const then = q.then; q.then = (res, rej) => lat().then(() => (window.__FAIL || window.__FAILTABLE === t) ? res({ data: null, error: { message: 'Failed to fetch' } }) : then.call(q, res, rej)); return q; };
  c.rpc = async (fn, args) => { await lat(); if (window.__FAIL) return { data: null, error: { message: 'Failed to fetch' } }; return rpc(fn, args); };
  return c; }; })();`;
const TABLE_COUNT_MIN = 60; const LAT_DEFAULT = LAT;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } else log('ok:', m); };
  const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/every table failed|Failed to fetch/.test(m.text())) errors.push('console: ' + m.text()); });   // the failure runs (section C) log their own error on purpose
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + LATWRAP + C.EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  const data = C.mkData(base, {});
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__LAT=${LAT};try{localStorage.setItem('bos_lang','bn');}catch(e){}`);
  await p.goto(`http://localhost:${PORT}/#/backup`); await p.waitForTimeout(1500);
  await p.waitForSelector('[data-act=bk_all]', { timeout: 8000 });
  ok(await p.locator('[data-act=bk_all]').count() === 1, 'backup button on the Backup screen');
  const noOverflow = async (m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal overflow ' + m);
  await noOverflow('at 360 px');

  // ---- A: five taps in a row, each one must start one download with a valid JSON file ----
  const names = []; const dlCount = { n: 0 }; p.on('download', () => { dlCount.n++; });
  const check = async (dl, tag) => {
    const file = await dl.path(); const txt = file ? fs.readFileSync(file, 'utf8') : '';
    let j = null; try { j = JSON.parse(txt); } catch (e) { /* reported below */ }
    ok(/^bos-backup-\d{4}-\d{2}-\d{2}\.json$/.test(dl.suggestedFilename()), `${tag}: file name ${dl.suggestedFilename()}`);
    ok(txt.length > 0 && j !== null, `${tag}: non-empty and parses (${txt.length} bytes)`);
    ok(j && ['exported_at', 'tables', 'row_counts', 'errors'].every((k) => k in j), `${tag}: top-level keys`);
    ok(j && j.tables && Object.keys(j.tables).length >= TABLE_COUNT_MIN, `${tag}: at least ${TABLE_COUNT_MIN} tables (${j && j.tables ? Object.keys(j.tables).length : 0})`);
    ok(j && j.tables && Array.isArray(j.tables.items) && j.tables.items.length > 0, `${tag}: items table is a non-empty array`);
    return j;
  };
  for (let i = 1; i <= 5; i++) {
    await p.waitForFunction(() => { const b = document.querySelector('#bk_box > [data-act=bk_all]'); return b && !b.disabled; }, null, { timeout: 120000 });
    const [dl] = await Promise.all([p.waitForEvent('download', { timeout: 60000 }).catch(() => null), p.click('#bk_box > [data-act=bk_all]')]);
    if (!dl) { ok(false, `tap ${i}: download event fired`); continue; }
    names.push(dl.suggestedFilename()); await check(dl, `tap ${i}`);
  }
  ok(names.length === 5, 'five taps, five downloads: ' + names.length);
  await p.waitForFunction(() => { const b = document.querySelector('#bk_box > [data-act=bk_all]'); return b && !b.disabled; }, null, { timeout: 120000 });
  await noOverflow('after 5 taps');

  // ---- B: a second tap while a run is busy does nothing (one run, one file) ----
  await p.evaluate(() => { window.__LAT = 250; });
  const before = dlCount.n;
  await p.click('#bk_box > [data-act=bk_all]');
  ok(await p.evaluate(() => document.querySelector('#bk_box > [data-act=bk_all]').disabled), 'busy: the main button is disabled while the run goes on');
  ok(/\d+ \/ 77/.test(await p.textContent('#bk_box')), 'busy: progress shows the count');
  await p.evaluate(() => { const b = document.querySelector('#bk_box > [data-act=bk_all]'); b.click(); b.click(); });
  await p.waitForFunction(() => { const b = document.querySelector('#bk_box > [data-act=bk_all]'); return b && !b.disabled; }, null, { timeout: 120000 });
  await p.waitForTimeout(500);
  ok(dlCount.n - before === 1, 'double tap while busy: exactly one download (got ' + (dlCount.n - before) + ')');
  await p.evaluate((v) => { window.__LAT = v; }, LAT_DEFAULT);

  // ---- C: every read fails: Bengali message + retry, no file; retry then works ----
  await p.evaluate(() => { window.__FAIL = true; });
  const before2 = dlCount.n;
  await p.click('#bk_box > [data-act=bk_all]');
  await p.waitForFunction(() => document.querySelector('.notice.bad'), null, { timeout: 120000 });
  const badTxt = await p.textContent('.notice.bad');
  ok(/ব্যাকআপ হয়নি/.test(badTxt), 'failure: Bengali message shown');
  ok(await p.locator('.notice.bad [data-act=bk_all]').count() === 1, 'failure: retry button shown');
  await p.waitForTimeout(300);
  ok(dlCount.n === before2, 'failure: no file saved');
  await noOverflow('failure');
  await p.evaluate(() => { window.__FAIL = false; });
  const [dlR] = await Promise.all([p.waitForEvent('download', { timeout: 60000 }).catch(() => null), p.click('.notice.bad [data-act=bk_all]')]);
  ok(!!dlR, 'retry: download fires');
  if (dlR) await check(dlR, 'retry');
  ok(await p.locator('.notice.bad').count() === 0, 'retry: error message cleared');

  // ---- D: one table unreadable: the file is saved without it and the screen says so, with retry ----
  await p.evaluate(() => { window.__FAILTABLE = 'supplier_refunds'; });
  const [dlP] = await Promise.all([p.waitForEvent('download', { timeout: 60000 }).catch(() => null), p.click('#bk_box > [data-act=bk_all]')]);
  ok(!!dlP, 'partial: download still fires');
  if (dlP) { const j = await check(dlP, 'partial'); ok(j && j.errors && 'supplier_refunds' in j.errors && j.tables && !('supplier_refunds' in j.tables), 'partial: the failed table is listed in errors, not in tables'); }
  ok(/supplier_refunds/.test(await p.textContent('.notice.warn')), 'partial: warning names the table');
  await p.evaluate(() => { window.__FAILTABLE = null; });

  // ---- E: save again (a fresh tap) gives the same file without reading the data again ----
  const [dlA] = await Promise.all([p.waitForEvent('download', { timeout: 20000 }).catch(() => null), p.click('[data-act=bk_again]')]);
  ok(!!dlA && dlA.suggestedFilename() === (dlP ? dlP.suggestedFilename() : ''), 'save again: download with the same file name');
  ok(errors.length === 0, 'no page errors: ' + errors.slice(0, 3).join(' | '));
  log(bad ? `RESULT: ${bad} FAILED` : 'RESULT: all pass');
  await br.close(); srv.close();
  process.exit(bad ? 1 : 0);
} catch (e) { console.log('FAIL: exception', e && e.stack || e); srv.close(); process.exit(1); } })();
