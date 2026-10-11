// Salary report (salary.js). Run: node salary_test.js <dir holding smoke.js stub>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/p13_common.js');
const base = C.baseData(SP), srv = C.serve(8302);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2, acceptDownloads: true }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA2 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(C.mkData(base, o))};window.__M0=${JSON.stringify(o.m || {})};window.__DB0=${JSON.stringify(o.db || {})};${o.owner === false ? 'window.__OWNER=false;' : ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:8302/' + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);

  let p = await open({}, '#/salary');
  ok(await p.locator('#sa_rows .sa-row').count() === 2, 'two people'); ok(/Rahim cook/.test(await p.textContent('#sa_rows')), 'name');
  ok(/18,600/.test(await p.textContent('#sa_sum')) && /1,050/.test(await p.textContent('#sa_sum')) && /17,550/.test(await p.textContent('#sa_sum')), 'gross / deductions / net totals from the server');
  ok(/10,500/.test(await p.textContent('#sa_rows .sa-row')) && /9,500/.test(await p.textContent('#sa_rows .sa-row')), 'row gross and net');
  const sc = await calls(p, 'salary_report'); ok(sc.length >= 1 && sc[0].p_loc === null && /^\d{4}-\d{2}-01$/.test(sc[0].p_month), 'month sent as first of month, owner all locations');
  ok(await p.locator('#sa_adv').count() === 1 && /1,300/.test(await p.textContent('#sa_adv')) && /1,100/.test(await p.textContent('#sa_adv')), 'advances block'); ok(/26/.test(await p.textContent('#sa_att')), 'attendance block');
  await p.screenshot({ path: SP + '/sa_list.png' }); await noOverflow(p, 'salary list');
  // month navigation
  const m0 = (await calls(p, 'salary_report'))[0].p_month; await p.click('[data-act=sa_m][data-v="-1"]'); await wait(p, 300);
  const sc2 = await calls(p, 'salary_report'); ok(sc2[sc2.length - 1].p_month < m0, 'previous month requested');
  // row sheet
  await p.click('#sa_rows .sa-row >> nth=0'); await wait(p, 250); ok(/Overtime/.test(await p.textContent('.sheet')) && /Advance deduction/.test(await p.textContent('.sheet')) && /Net/.test(await p.textContent('.sheet')), 'row detail shows form fields');
  await p.screenshot({ path: SP + '/sa_row.png' }); await noOverflow(p, 'row sheet');
  const urls = []; p.on('framenavigated', (f) => urls.push(f.url())); await p.click('.sheet [data-act=sa_rmenu]'); await wait(p, 200); await p.click('[data-act=sa_openform]'); await wait(p, 200); ok(urls.some((u) => /#\/entry\/e5$/.test(u)), 'row menu opens the source form (navigated to #/entry/e5)');
  await p.close();

  // export: audit first, file after
  p = await open({}, '#/salary'); await p.click('#sa_menu'); await wait(p, 200);
  const dl = p.waitForEvent('download'); await p.click('[data-act=sa_csv]'); const d = await dl; const txt = fs.readFileSync(await d.path(), 'utf8');
  ok(/sheet,location,name,monthly_salary/.test(txt) && /Rahim cook,10000,26,3,0,10000,500,0,10500,1000,0,9500,9500,yes/.test(txt) && /TOTAL/.test(txt) && /advances \(02-3\)/.test(txt) && /attendance \(02-1\)/.test(txt), 'csv content');
  const lg = await calls(p, 'log_page_export'); ok(lg.length === 1 && lg[0].p_key === 'salary' && lg[0].p_rows === 2, 'export audited with key salary'); await p.close();
  p = await open({ db: { exportDenied: true } }, '#/salary'); await p.click('#sa_menu'); await wait(p, 200); let got = false; p.once('download', () => { got = true; });
  await p.click('[data-act=sa_csv]'); await wait(p, 400); ok(!got, 'no file when the server refuses'); ok(/not allowed/i.test(await p.textContent('#toast')), 'refusal toast'); await p.close();

  // empty month => Data needed, no invented rows
  p = await open({ db: { empty: true } }, '#/salary'); ok(await p.locator('#sa_need').count() === 1 && await p.locator('#sa_rows').count() === 0, 'Data needed when no sheet'); await p.screenshot({ path: SP + '/sa_empty.png' });
  await p.click('#sa_menu'); await wait(p, 200); ok(await p.locator('[data-act=sa_csv]').count() === 0, 'no export of an empty month'); await p.close();

  // no permission: lock card (lock mode) / page refused
  const ctx0 = { is_owner: false, roles: ['salesperson'], locations: [1] };
  p = await open({ owner: false, m: { grants: [], ctx: ctx0 }, db: { denied: true } }, '#/salary'); ok(await p.locator('.lockcard').count() === 1 && await p.locator('#sa_rows').count() === 0, 'refused -> lock card, no figures'); await p.screenshot({ path: SP + '/sa_lock.png' }); await p.close();
  // grantee without export_data: export buttons locked (lock mode) / hidden (hide mode)
  p = await open({ owner: false, m: { grants: ['salary_view'], ctx: ctx0 } }, '#/salary'); await p.click('#sa_menu'); await wait(p, 200);
  ok(await p.locator('[data-act=sa_csv]').count() === 0 && await p.locator('.sheet button[disabled]').count() === 2, 'no export_data: export items locked'); await p.close();
  p = await open({ hide: true, owner: false, m: { grants: ['salary_view'], ctx: ctx0 } }, '#/salary'); await p.click('#sa_menu'); await wait(p, 200);
  ok(await p.locator('.sheet button[disabled]').count() === 0 && await p.locator('[data-act=sa_csv]').count() === 0, 'hide mode: export items hidden'); await p.close();
  // drawer: People group entry for owner; locked/hidden for others
  p = await open({}, '#/home'); await p.click('header.top [data-act=nav_open]'); await wait(p, 400); await p.click('.dr-g[data-v=people]'); await wait(p, 200); ok(await p.locator('.dr-it[data-v=salary]').count() === 1, 'drawer: salary report entry for the owner'); await p.close();
  p = await open({ owner: false, m: { grants: [], ctx: ctx0 } }, '#/home'); await p.click('header.top [data-act=nav_open]'); await wait(p, 600); await p.click('.dr-g[data-v=people]'); await wait(p, 200);
  ok(await p.locator('.dr-it[data-v=salary]:not(.lock)').count() === 0, 'drawer: no open salary entry without the grant'); await p.close();
  // Bangla
  p = await open({ lang: 'bn' }, '#/salary'); ok(/বেতন রিপোর্ট/.test(await p.textContent('header.top h1')), 'Bangla title'); await p.screenshot({ path: SP + '/sa_bn.png' }); await noOverflow(p, 'bn'); await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
