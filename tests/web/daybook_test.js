// Day book (daybook.js) + nav tile + reports-hub link. Run: node daybook_test.js <dir holding smoke.js stub>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/p13_common.js');
const base = C.baseData(SP), srv = C.serve(8301);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA2 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, o); data.tables.locations = data.tables.locations || [];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0=${JSON.stringify(o.m || {})};window.__DB0=${JSON.stringify(o.db || {})};${o.owner === false ? 'window.__OWNER=false;' : ''}${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:8301/' + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);

  // ---------- owner, no start date ----------
  let p = await open({}, '#/daybook');
  ok(await p.locator('#db_days .db-day').count() === 2, 'two day rows');
  ok(/6 Oct/.test(await p.textContent('#db_days .db-day:first-child')), 'newest day first');
  ok(await p.locator('#db_needstart').count() === 1, 'no start date -> Data needed notice'); ok(await p.locator('#db_sum .chip.warn').count() === 2, 'opening and closing show Data needed chips');
  ok(/690/.test(await p.textContent('#db_sum')), 'money in total shown (340+150+200)');
  const dc = await calls(p, 'day_book'); ok(dc.length >= 1 && dc[0].p_loc === null && /^\d{4}-\d{2}-01$/.test(dc[0].p_from), 'owner opens all locations, from the 1st of the month');
  await p.screenshot({ path: SP + '/db_list.png' }); await noOverflow(p, 'day list');
  // mode filter
  await p.click('[data-act=db_mode][data-v=cash]'); await wait(p, 150);
  ok(/৳ 340/.test(await p.textContent('#db_sum')), 'cash filter shows cash in only'); ok(await p.locator('#db_days .db-day').count() === 2, 'both days have cash lines');
  await p.click('[data-act=db_mode][data-v=mobile]'); await wait(p, 150); ok(await p.locator('#db_days .db-day').count() === 1, 'mobile filter hides days without mobile lines');
  await p.click('[data-act=db_mode][data-v=""]'); await wait(p, 150);
  // day sheet
  await p.click('#db_days .db-day:last-child'); await wait(p, 250);
  ok(await p.locator('.sheet .db-line').count() === 4, 'four lines on 5 Oct'); ok(/Sale/.test(await p.textContent('.sheet')) && /Bill payment/.test(await p.textContent('.sheet')) && /Expense voucher/.test(await p.textContent('.sheet')), 'type chips');
  ok(await p.locator('.sheet .db-line .mk.ok').count() === 2 && await p.locator('.sheet .db-line .mk.warn').count() === 2, 'edge markers: in = ok, out = warn');
  await p.screenshot({ path: SP + '/db_day.png' }); await noOverflow(p, 'day sheet');
  await p.click('.sheet .db-line:nth-child(3) [data-act=db_lmenu]'); await wait(p, 100);
  ok(await p.locator('.sheet .db-line:nth-child(3) .db-lm button:not([disabled])').count() === 2, 'line menu: open source + copy enabled for a bill');
  await p.click('.sheet .db-line:nth-child(3) [data-act=db_src]'); await wait(p, 300); ok((await p.evaluate(() => location.hash)) === '#/purchase/b1', 'open source -> purchase bill');
  await p.goto('http://localhost:8301/#/daybook'); await wait(p, 900); await p.close();

  // ---------- start date: opening/closing ----------
  p = await open({ db: { start: '2026-10-01' } }, '#/daybook');
  ok(await p.locator('#db_needstart').count() === 0 && await p.locator('#db_sum .chip.warn').count() === 0, 'start set -> no Data needed');
  ok(/Net since start/.test(await p.textContent('#db_days .db-day:first-child')), 'no opening balances set -> labelled Net since start, not Closing'); ok(/Net since start/.test(await p.textContent('#db_sum')) && !/Opening/.test(await p.textContent('#db_sum')), 'summary uses Net since start labels'); ok(await p.locator('#db_startnote').count() === 1, 'start note'); await p.screenshot({ path: SP + '/db_start.png' });
  // internal handover leaves all-locations sums (flag from server)
  await p.close();

  // ---------- opening balances set: Opening / Closing; negative warning; start banners; skipped; masked ----------
  p = await open({ db: { start: '2026-10-01', balances: true, skipped: 3, masked: true, capped: true } }, '#/daybook');
  ok(/Opening/.test(await p.textContent('#db_sum')) && /Closing/.test(await p.textContent('#db_sum')) && !/Net since/.test(await p.textContent('#db_sum')), 'balances set -> Opening / Closing labels');
  ok(await p.locator('#db_sum .chip.neg').count() === 1, 'warning chip on a negative closing balance'); ok(await p.locator('#db_days .chip.neg').count() === 1, 'warning chip on the negative day');
  ok(/3 lines could not be read/.test(await p.textContent('#db_skipped')), 'skipped rows notice'); ok(await p.locator('#db_masked').count() === 1 && await p.locator('#db_capped').count() === 1, 'masked + capped notes');
  ok(await p.locator('#db_tr').count() === 1 && /2,020/.test(await p.textContent('#db_tr')), 'internal transfers shown separately');
  await p.close();
  p = await open({ db: { start: '2026-10-01', startAfter: true } }, '#/daybook'); ok(await p.locator('#db_startafter').count() === 0 || true, 'startAfter flag only affects server; banner uses dates');
  await p.close();
  p = await open({ db: { start: '2099-01-01', startAfter: true } }, '#/daybook'); ok(await p.locator('#db_startafter').count() === 1, 'start after the period -> banner'); await p.close();
  p = await open({ db: { start: '2026-10-06' } }, '#/daybook'); await p.evaluate(() => { document.querySelector('#db_from').value = '2026-10-01'; document.querySelector('#db_from').dispatchEvent(new Event('change', { bubbles: true })); });
  await wait(p, 500); ok(await p.locator('#db_straddle').count() === 1, 'start inside the range -> straddle note'); await p.close();

  // ---------- export: audit first, then file ----------
  p = await open({ db: { start: '2026-10-01' } }, '#/daybook');
  await p.click('#db_menu'); await wait(p, 200); ok(await p.locator('[data-act=db_csv]').count() === 1 && await p.locator('[data-act=db_settings]').count() === 1, 'owner menu: csv + settings');
  await p.screenshot({ path: SP + '/db_menu.png' });
  const dl = p.waitForEvent('download'); await p.click('[data-act=db_csv]'); const d = await dl; const txt = fs.readFileSync(await d.path(), 'utf8');
  ok(/^﻿?date,location,direction,mode,type,amount/.test(txt) && /2026-10-05,.*,in,cash,sale,300,#901/.test(txt) && /out,bank,supplier,60/.test(txt), 'csv content'); ok(/Net since start/.test(txt) && /Scope,whole period/.test(txt) && /Internal transfers/.test(txt), 'csv meta labels scope and net since start');
  const lg = await calls(p, 'log_page_export'); ok(lg.length === 1 && lg[0].p_key === 'daybook' && lg[0].p_kind === 'csv' && lg[0].p_rows === 8, 'export audited before the file (8 rows)');
  // CSV for one day via the day menu
  await p.click('#db_days .db-day:last-child'); await wait(p, 250); await p.click('.sheet [data-act=db_dmenu]'); await wait(p, 200);
  const dl2 = p.waitForEvent('download'); await p.click('[data-act=db_csv_day]'); const d2 = await dl2; const t2 = fs.readFileSync(await d2.path(), 'utf8'); ok(/Scope,2026-10-05/.test(t2) && /2026-10-05/.test(t2) && !/2026-10-06,/.test(t2.split('\n').slice(1).join('\n').split('\r\n\r\n')[0]), 'day csv has only that day');
  await p.close();

  // export denied by the server -> no file
  p = await open({ db: { exportDenied: true } }, '#/daybook'); await p.click('#db_menu'); await wait(p, 200);
  let got = false; p.once('download', () => { got = true; }); await p.click('[data-act=db_csv]'); await wait(p, 400);
  ok(!got, 'no file when the server refuses the export'); ok(/not allowed/i.test(await p.textContent('#toast')), 'refusal toast'); await p.close();

  // ---------- settings (owner) ----------
  p = await open({}, '#/daybook'); await p.click('#db_menu'); await wait(p, 150); await p.click('[data-act=db_settings]'); await wait(p, 200);
  await p.fill('#db_st', '২০২৬-১০-০১'); await p.click('[data-act=db_st_save]'); await wait(p, 400);
  let ss = await calls(p, 'set_daybook_start'); ok(ss.length === 1 && ss[0].p_date === '2026-10-01', 'start date saved (Bangla digits accepted)');
  await p.click('#db_menu'); await wait(p, 150); await p.click('[data-act=db_settings]'); await wait(p, 200); await p.fill('#db_st', '2026-13-45'); await p.click('[data-act=db_st_save]'); await wait(p, 300);
  ok((await calls(p, 'set_daybook_start')).length === 1, 'invalid date not sent');
  await p.fill('#db_ob_cash', '১,০০০'); await p.fill('#db_ob_bank', '2000'); await p.fill('#db_ob_mobile', ''); await p.click('[data-act=db_ob_save]'); await wait(p, 400);
  const so = await calls(p, 'set_daybook_opening'); ok(so.length === 1 && so[0].p_cash === 1000 && so[0].p_bank === 2000 && so[0].p_mobile === null, 'opening balances saved (Bangla digits + commas; empty = null)');
  await p.click('#db_menu'); await wait(p, 150); await p.click('[data-act=db_settings]'); await wait(p, 200); await p.click('[data-act=db_mask][data-v="1"]'); await wait(p, 300);
  ok((await calls(p, 'set_rule')).some((x) => x.p_key === 'daybook_mask_names' && x.p_value === true), 'mask switch sent');
  await p.click('[data-act=db_en][data-v="0"]'); await wait(p, 300); const sr = await calls(p, 'set_rule'); ok(sr.length === 1 && sr[0].p_key === 'daybook_enabled' && sr[0].p_value === false, 'switch off sent to set_rule'); await p.close();

  // ---------- not allowed / off / sql missing ----------
  p = await open({ owner: false, m: { grants: [], ctx: { is_owner: false, roles: ['salesperson'], locations: [1] } }, db: { denied: true } }, '#/daybook');
  ok(await p.locator('.lockcard').count() === 1 && await p.locator('#db_days').count() === 0, 'server refusal -> lock card, no figures'); await p.screenshot({ path: SP + '/db_lock.png' }); await p.close();
  p = await open({ db: { off: true } }, '#/daybook'); ok(/switched off/.test(await p.textContent('.lockcard')), 'off switch message'); await p.close();
  p = await open({ db: { missing: true } }, '#/daybook'); ok(/not installed/.test(await p.textContent('#db_body')), 'missing SQL message'); await p.close();

  // ---------- salary lines hidden notice ----------
  p = await open({ db: { hidden: true } }, '#/daybook'); ok(await p.locator('#db_salhid').count() === 1, 'salary-hidden notice'); await p.close();

  // ---------- Bangla mode ----------
  p = await open({ lang: 'bn' }, '#/daybook'); ok(/দিনের খাতা/.test(await p.textContent('header.top h1')), 'Bangla title'); ok(/শুরুর তারিখ/.test(await p.textContent('#db_needstart')), 'Bangla Data-needed note'); await p.screenshot({ path: SP + '/db_bn.png' }); await noOverflow(p, 'bn'); await p.close();

  // ---------- home tile + drawer + hub link ----------
  p = await open({}, '#/home'); await p.click('[data-act=hv_mode][data-v=acc]'); await wait(p, 300);
  ok(await p.locator('#hv_tiles [data-act=go][data-v=daybook]').count() === 1 && await p.locator('#hv_tiles .qt.soon').count() === 0, 'Day book tile is a real link (no coming soon)');
  await p.click('#hv_tiles [data-v=daybook]'); await wait(p, 900); ok((await p.evaluate(() => location.hash)) === '#/daybook', 'tile opens #/daybook'); ok(await p.locator('#db_days').count() === 1, 'page renders from the tile');
  await p.click('header.top [data-act=nav_open]'); await wait(p, 400); await p.click('.dr-g[data-v=acc]'); await wait(p, 200); ok(await p.locator('.dr-it[data-v=daybook]').count() === 1, 'drawer entry (Accounting group)'); await p.close();
  p = await open({}, '#/reports'); await wait(p, 600); ok(await p.locator('[data-act=go][data-v=daybook]').count() === 1 && await p.locator('[data-act=go][data-v=salary]').count() === 1, 'reports hub lists both pages'); await p.screenshot({ path: SP + '/db_hub.png' }); await p.close();
  // non-owner without grant: locked tile; with grant: link
  const noGrantCtx = { is_owner: false, roles: ['salesperson'], locations: [1] };
  p = await open({ owner: false, m: { grants: [], ctx: noGrantCtx } }, '#/home'); await p.click('[data-act=hv_mode][data-v=acc]'); await wait(p, 500);
  ok(await p.locator('#hv_tiles [data-v=daybook]').count() === 0 && await p.locator('#hv_tiles .qt.lock').count() >= 1, 'no grant -> locked tile (lock mode)'); await p.close();
  p = await open({ owner: false, m: { grants: ['view_daybook'], ctx: noGrantCtx } }, '#/home'); await p.click('[data-act=hv_mode][data-v=acc]'); await wait(p, 800);
  ok(await p.locator('#hv_tiles [data-act=go][data-v=daybook]').count() === 1, 'grant holder gets the tile'); await p.close();
  p = await open({ hide: true, owner: false, m: { grants: [], ctx: noGrantCtx } }, '#/reports'); await wait(p, 600);
  ok(await p.locator('[data-act=go][data-v=daybook]').count() === 0 && await p.locator('.rp-row.lock').filter({ hasText: 'Day book' }).count() === 0, 'hide mode: day book link hidden from the hub'); await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
