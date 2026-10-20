// Sale returns page + sheet (salereturn.js). Run: node salereturn_test.js <dir with smoke.js, stub.js>
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), srv = C.serve(PORT);
const today = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' });
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(C.mkData(base, o))};window.__M0=${JSON.stringify(o.m || {})};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1000); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const sales = [{ id: 's1', receipt: 12, sold_at: today + 'T05:00:00Z', total: 1040, status: 'done', customer: 'Rahim', location_id: 1, pay_mode: 'split', sale_date: today }, { id: 's2', receipt: 11, sold_at: today + 'T04:00:00Z', total: 300, status: 'void', customer: null, location_id: 1, pay_mode: 'cash', sale_date: today }];
  const mk = (x = {}) => ({ sale_id: 's1', receipt: 12, status: 'done', location_id: 1, customer_id: 'c1', customer: 'Rahim', factor: 1, due_first: true, balance: 500, can_return: true,
    lines: [{ item_id: 'i0', name: 'White sweet', unit: 'kg', sold: 4, returned: 0, left: 4, price: 260 }, { item_id: 'i2', name: 'Rasmalai', unit: 'piece', sold: 10, returned: 10, left: 0, price: 20 }],
    returns: [{ id: 'r0', amount: 100, credit: 100, refund: 0, refund_mode: null, reason: 'damaged', note: 'one box', status: 'done', at: '2026-10-10T05:00:00Z', staff: 'owner1' }], ...x });

  let p = await open({ sales, m: { saleRet: mk() } }, '#/salereturn');
  ok(await p.locator('#sr_list .card').count() === 2, 'two receipts listed'); ok(await p.locator('#sr_list .s2-dots').count() === 2, '⋮ on every receipt'); ok(await p.locator('#sr_list .mk.bad').count() === 1, 'voided receipt has the red edge');
  await p.screenshot({ path: SP + '/sr_list.png' }); await noOverflow(p, 'list');
  await p.click('#sr_list .card:has-text("#12") .s2-dots'); await wait(p, 400); ok(/Take goods back/.test(await p.textContent('.sheet')) && /Returns of this receipt/.test(await p.textContent('.sheet')), 'menu of a done receipt');
  await p.click('.sheet [data-act=closesheet]'); await wait(p, 200); await p.click('#sr_list .card:has-text("#11") .s2-dots'); await wait(p, 400); ok(!/Take goods back/.test(await p.textContent('.sheet')) && /Returns of this receipt/.test(await p.textContent('.sheet')), 'a voided receipt cannot take a return'); await p.click('.sheet [data-act=closesheet]');
  await wait(p, 200); await p.click('#sr_list .card:has-text("#12")'); await wait(p, 600);
  ok(/Customer: Rahim · Customer owes ৳ 500/.test(await p.textContent('.sheet')), 'customer and what they owe'); ok(await p.locator('[data-rq]').count() === 1, 'a line with nothing left has no quantity box');
  ok(/Left 4 kg/.test(await p.textContent('.sheet')), 'sold / returned / left'); ok(/one box/.test(await p.textContent('.sheet')) && /Taken off what the customer owes ৳ 100/.test(await p.textContent('.sheet')), 'history of earlier returns');
  await p.screenshot({ path: SP + '/sr_sheet.png' }); await noOverflow(p, 'sheet');
  await p.fill('[data-rq="0"]', '2'); await wait(p, 150); let sm = (await p.innerText('#sr_sum')).replace(/\s+/g, ' '); ok(/Value of the return ৳ 520/.test(sm) && /Taken off what the customer owes ৳ 500/.test(sm) && /To hand back ৳ 20/.test(sm), 'value 520 = 500 off the due + 20 to hand back: ' + sm);
  ok(await p.locator('#sr_mw').isVisible(), 'refund mode asked when something is handed back');
  await p.fill('[data-rq="0"]', '1'); await wait(p, 150); sm = (await p.innerText('#sr_sum')).replace(/\s+/g, ' '); ok(/To hand back ৳ 0/.test(sm) && await p.locator('#sr_mw').isHidden(), 'fully covered by the due: no refund mode');
  await p.fill('[data-rq="0"]', '5'); await p.click('#sr_go'); await wait(p, 200); ok(/wrong or more than what is left/.test(await toastTxt(p)) && (await calls(p, 'sale_return')).length === 0, 'more than left is stopped client side');
  await p.fill('[data-rq="0"]', ''); await p.click('#sr_go'); await wait(p, 200); ok(/at least one item/.test(await toastTxt(p)), 'a quantity is needed');
  await p.fill('[data-rq="0"]', '2'); await p.click('#sr_go'); await wait(p, 200); ok(/Choose a reason/.test(await toastTxt(p)), 'reason needed');
  await p.selectOption('#sr_reason', 'damaged'); await p.click('#sr_go'); await wait(p, 200); ok(/Choose how it was handed back/.test(await toastTxt(p)), 'refund mode needed when handing back');
  await p.selectOption('#sr_mode', 'mobile'); ok(await p.locator('#sr_ww').isVisible(), 'wallet for mobile'); await p.click('#sr_go'); await wait(p, 200); ok(/Enter the wallet/.test(await toastTxt(p)), 'wallet needed');
  await p.selectOption('#sr_mode', 'cash'); await p.fill('#sr_note', 'two came back'); await p.evaluate(() => { window.__M.fail.sale_return = { msg: 'return_exceeds_sale', once: true }; }); await p.click('#sr_go'); await wait(p, 300);
  ok(/More than what is left/.test(await toastTxt(p)), 'server refusal text'); await p.click('#sr_go'); await wait(p, 400);
  const sr = await calls(p, 'sale_return'); ok(sr.length === 2 && sr[0].p_client === sr[1].p_client && /^[0-9a-f-]{36}$/.test(sr[0].p_client), 'retry keeps the client id');
  ok(sr[1].p_sale === 's1' && JSON.stringify(sr[1].p_lines) === '[{"item_id":"i0","qty":2}]' && sr[1].p_reason === 'damaged' && sr[1].p_refund_mode === 'cash' && sr[1].p_note === 'two came back', 'sale_return args: ' + JSON.stringify(sr[1]));
  ok(/Return recorded/.test(await toastTxt(p)), 'saved toast'); await p.close();

  // fully covered by the due -> no mode sent; discount factor; rule off
  p = await open({ sales, m: { saleRet: mk({ factor: 0.9 }) } }, '#/salereturn/s1'); await wait(p, 300);
  ok(await p.locator('[data-rq]').count() === 1, 'route with an id opens the sheet'); await p.fill('[data-rq="0"]', '1'); await wait(p, 150); ok(/Value of the return ৳ 234/.test((await p.innerText('#sr_sum')).replace(/\s+/g, ' ')), 'sale discount share applied (260 x 0.9 = 234)');
  await p.selectOption('#sr_reason', 'damaged'); await p.click('#sr_go'); await wait(p, 400); const s1 = (await calls(p, 'sale_return'))[0]; ok(s1 && s1.p_refund_mode === null, 'no refund mode when the due covers it'); await p.close();
  p = await open({ sales, m: { saleRet: mk({ due_first: false }) } }, '#/salereturn/s1'); await p.fill('[data-rq="0"]', '1'); await wait(p, 150); const s2 = (await p.innerText('#sr_sum')).replace(/\s+/g, ' '); ok(/To hand back ৳ 260/.test(s2) && !/Taken off/.test(s2) && /whole value is handed back/.test(s2), 'rule off: everything is handed back'); await p.close();
  p = await open({ sales, m: { saleRet: mk({ customer_id: null, customer: null, balance: null }) } }, '#/salereturn/s1'); await p.fill('[data-rq="0"]', '1'); await wait(p, 150); ok(/To hand back ৳ 260/.test((await p.innerText('#sr_sum')).replace(/\s+/g, ' ')), 'no customer: all handed back'); await p.close();

  // no permission: lock row; history only
  const NO = 'window.__OWNER=false;window.__PERMS={POS:{view:true,enter:true}};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};';
  p = await open({ init: NO, sales, m: { saleRet: mk({ can_return: false }), grants: [], ctx: { locations: [1], roles: ['salesperson'] } } }, '#/salereturn/s1'); await wait(p, 300);
  ok(await p.locator('[data-rq]').count() === 0 && await p.locator('#sr_go').count() === 0 && await p.locator('.sheet .s2-lockrow').count() === 1, 'no sale_return grant: locked row, no form'); ok(await p.locator('[data-act=sr_void]').count() === 0, 'no void either'); await p.close();

  // void a return from the history
  p = await open({ sales, m: { saleRet: mk() } }, '#/salereturn/s1'); await wait(p, 300); await p.click('[data-act=sr_void]'); await wait(p, 300); await p.click('[data-act=sr_voidgo]'); await wait(p, 150); ok(/Reason for voiding/.test(await toastTxt(p)), 'void needs a reason');
  await p.fill('#vn_note', 'entered twice'); await p.click('[data-act=sr_voidgo]'); await wait(p, 400); const vr = await calls(p, 'void_sale_return'); ok(vr.length === 1 && vr[0].p_id === 'r0' && vr[0].p_note === 'entered twice', 'void_sale_return call'); await p.close();
  // missing server part
  p = await open({ sales, m: { fail: { sale_returns_for: { msg: 'could not find the function public.sale_returns_for' } } } }, '#/salereturn'); await p.click('#sr_list .card:has-text("#12")'); await wait(p, 500); ok(/not installed yet/.test(await toastTxt(p)), 'phase12 missing -> clear message'); await p.close();
  for (const lang of ['bn', 'mix']) { p = await open({ lang, sales, m: { saleRet: mk() } }, '#/salereturn/s1'); await wait(p, 300); await p.screenshot({ path: SP + `/sr_${lang}.png` }); await noOverflow(p, lang); ok(/Rahim/.test(await p.textContent('.sheet')), 'sheet in ' + lang); await p.close(); }

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
