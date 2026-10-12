// Forms <-> stock ledger links (forms_stock.js read views + #/ledgerlinks), 06-5 supplier_pick master column, 05-1 output table, brand P&L and discounts pages (reports.js).
// Run: node forms_links_test.js /home/user/My-tools/tests/web
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), srv = C.serve(8321);
// extra RPCs of phase20 on top of the phase10 mock
const EXTRA2 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M; const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const L2 = window.__L2 = Object.assign({ prob: [{ entry_id: 'e1', form_code: '04-2', serial: 7, location_id: 1, entry_date: '2026-10-10', failed: 2, skipped: 1, first_reason: 'insufficient_stock' }],
   brand: [{ brand_code: 'islamiya', brand_bn: 'ইসলামিয়া', brand_en: 'ISLAMIYA', locations: 2, n: 10, revenue: 1000, discount: 50, void_n: 1, void_amt: 30, costed_rev: 800, cogs: 500, gross_profit: 300, gp_pct: 37.5 },
           { brand_code: 'misty_bari', brand_bn: 'মিষ্টি বাড়ি', brand_en: 'MISTY BARI', locations: 1, n: 4, revenue: 400, discount: 0, void_n: 0, void_amt: 0, costed_rev: 400, cogs: 100, gross_profit: 300, gp_pct: 75 }],
   disc: [{ sale_id: 's1', location_id: 1, receipt: 12, sale_date: '2026-10-10', status: 'done', subtotal: 500, discount: 150, discount_kind: 'percent', discount_input: 30, total: 350, seller_staff: 'karim02', approver_staff: 'owner1', approval: 'emergency', over_limit: true, customer: null },
          { sale_id: 's2', location_id: 1, receipt: 11, sale_date: '2026-10-10', status: 'done', subtotal: 500, discount: 50, discount_kind: 'amount', discount_input: 50, total: 450, seller_staff: 'karim02', approver_staff: null, approval: null, over_limit: false, customer: null }],
   sup: [{ supplier_id: 'sp1', name: 'Dudh Ghor', balance: 600 }] }, window.__L20 || {});
 const OWN = ['ledger_post_problems', 'entry_post_ledger_retry', 'set_rule', 'forms_ledger_cfg_set', 'brand_pnl', 'discounts_report', 'report_catalog', 'report_presets'];
 c.rpc = async (fn, args) => { if (!OWN.includes(fn) || (fn === 'set_rule' && args.p_key !== 'forms_post_to_ledger')) return rpc(fn, args); M.calls.push([fn, clone(args || {})]);
  const f = M.fail[fn]; if (f) { if (f.once) delete M.fail[fn]; return { data: null, error: { message: f.msg } }; }
  if (fn === 'report_catalog') return { data: [{ key: 'sales_summary', group: 'sales', name_bn: 'বিক্রি', name_en: 'Sales summary', name_mix: 'Sales', allowed: true }], error: null };
  if (fn === 'report_presets') return { data: { today: { from: '2026-10-11', to: '2026-10-11' } }, error: null };
  if (fn === 'ledger_post_problems') return { data: clone(L2.prob), error: null };
  if (fn === 'entry_post_ledger_retry') { L2.prob = []; return { data: { ok: true, posted: 2, failed: 0 }, error: null }; }
  if (fn === 'set_rule' && args.p_key === 'forms_post_to_ledger') { const r = T.rules.find((x) => x.key === 'forms_post_to_ledger'); r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'forms_ledger_cfg_set') { const r = T.forms_ledger_cfg.find((x) => x.form_code === args.p_form); r.is_on = args.p_on; return { data: { form_code: args.p_form, is_on: args.p_on }, error: null }; }
  if (fn === 'brand_pnl') return { data: clone(window.__NOCOST ? L2.brand.map((x) => Object.assign({}, x, { costed_rev: null, cogs: null, gross_profit: null, gp_pct: null })) : L2.brand), error: null };
  if (fn === 'discounts_report') return { data: clone(L2.disc.filter((x) => !args.p_only_approved || x.approval)), error: null };
  return rpc(fn, args); };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA2 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const d = C.mkData(base, o);
    d.tables.rules.push({ key: 'forms_post_to_ledger', module: 'stock', kind: 'switch', value: o.on ? true : null, default_value: false, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 });
    d.tables.forms_ledger_cfg = ['04-1', '04-2', '04-3', '03-1', '05-1'].map((c) => ({ form_code: c, is_on: true }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(d)};window.__M0=${JSON.stringify(o.m || {})};window.__NOCOST=${!!o.noCost};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:8321/' + hash); await p.waitForTimeout(1000); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);

  // ---- switch OFF: the old paper form list stays ----
  let p = await open({}, '#/form/04-4');
  ok(await p.locator('#lk_loc').count() === 0 && await p.locator('[data-act=newentry]').count() === 1, 'switch off: 04-4 is the normal paper-form list with a new-entry button');
  await p.close();
  p = await open({}, '#/form/06-5');
  ok(await p.locator('#lk_loc').count() === 0 && await p.locator('[data-act=newentry]').count() === 1, 'switch off: 06-5 is the normal list');
  await p.close();

  // ---- switch ON: 04-4 read view ----
  p = await open({ on: true }, '#/form/04-4');
  ok(await p.locator('#lk_loc').count() === 1 && await p.locator('[data-act=newentry]').count() === 0, 'switch on: read view, no new-entry button');
  ok(await p.locator('.lk-row').count() === 3, 'three items listed from stock_levels');
  let lv = await calls(p, 'stock_levels'); ok(lv.length >= 1, 'stock_levels called'); await p.screenshot({ path: SP + '/fl_store.png' }); await noOverflow(p, 'store list');
  await p.click('[data-act=lk_item] >> nth=0'); await wait(p, 500);
  const lr = await calls(p, 'stock_ledger_rows'); ok(lr.length >= 1 && lr[lr.length - 1].p_item === 'i0', 'ledger rows of the picked item requested');
  const txt = await p.textContent('#app');
  ok(/Sale/.test(txt) && /−1\.5/.test(txt) && /\+5/.test(txt), 'rows shown signed'); ok(/Balance 3\.5/.test(txt) && /Balance 5/.test(txt), 'running balance computed back from the current quantity (3.5 then 5)');
  ok(await p.locator('input,textarea').filter({ hasNot: p.locator('#lk_loc') }).count() <= 1, 'no typing fields in the read view'); await p.screenshot({ path: SP + '/fl_store_item.png' }); await noOverflow(p, 'store item');
  await p.click('[data-act=lk_back]'); await wait(p, 400); ok(await p.locator('.lk-row').count() === 3, 'back to the list');
  await p.click('[data-act=lk_paper]'); await wait(p, 500); ok(await p.locator('[data-act=newentry]').count() === 1 && await p.locator('#lk_loc').count() === 0, 'paper entries button opens the old list');
  await p.close();

  // ---- 06-5 read view ----
  p = await open({ on: true }, '#/form/06-5');
  ok(await p.locator('[data-act=lk_sup]').count() === 2, 'suppliers with dues listed'); ok(/Dudh Ghor/.test(await p.textContent('#app')) && /600/.test(await p.textContent('#app')), 'balance shown'); await noOverflow(p, 'supplier list');
  await p.click('[data-act=lk_sup] >> nth=0'); await wait(p, 500);
  const sl = await calls(p, 'supplier_ledger'); ok(sl.length === 1 && sl[0].p_supplier === 'sp1', 'supplier_ledger requested for the picked supplier');
  ok(/Bill/.test(await p.textContent('#app')) && /Due now/.test(await p.textContent('#app')), 'ledger rows and the due now figure'); await p.screenshot({ path: SP + '/fl_supplier.png' }); await noOverflow(p, 'supplier ledger');
  await p.close();

  // ---- 06-5 paper form: master list name column is the supplier picker ----
  p = await open({}, '#/form/06-5'); await p.click('[data-act=newentry]'); await wait(p, 700);
  ok(await p.locator('input[data-sup]').count() >= 2, 'supplier pickers on the head and in the master list rows'); const mi = p.locator('[data-p^="master."][data-sup]'); ok(await mi.count() >= 1, 'master-list name cells use the supplier picker');
  await p.close();

  // ---- 05-1: optional finished-goods table ----
  p = await open({}, '#/form/05-1'); await p.click('[data-act=newentry]'); await wait(p, 700);
  ok(await p.locator('[data-p^="output."][data-item]').count() >= 1, '05-1 has the optional finished-goods item rows'); await p.close();

  // ---- #/ledgerlinks ----
  p = await open({ on: true }, '#/ledgerlinks');
  ok(await p.locator('[data-act=lk_set]').count() === 12, 'master + 5 forms, on/off each'); ok(await p.locator('[data-act=lk_set][data-v="master:1"].on').count() === 1, 'master shows On');
  ok(await p.locator('[data-act=lk_retry]').count() === 1 && /2 failed/.test(await p.textContent('#app')) && /1 skipped/.test(await p.textContent('#app')), 'retry list with counts'); await p.screenshot({ path: SP + '/fl_links.png' }); await noOverflow(p, 'links');
  await p.click('[data-act=lk_set][data-v="04-2:0"]'); await wait(p, 400); let cf = await calls(p, 'forms_ledger_cfg_set'); ok(cf.length === 1 && cf[0].p_form === '04-2' && cf[0].p_on === false, 'per-form switch sent');
  await p.click('[data-act=lk_set][data-v="master:0"]'); await wait(p, 400); let sr = await calls(p, 'set_rule'); ok(sr.length === 1 && sr[0].p_key === 'forms_post_to_ledger' && sr[0].p_value === false, 'master switch sent as a rule');
  await p.click('[data-act=lk_retry]'); await wait(p, 400); const rt = await calls(p, 'entry_post_ledger_retry'); ok(rt.length === 1 && rt[0].p_entry === 'e1', 'retry sent for the entry'); ok(await p.locator('[data-act=lk_retry]').count() === 0 && /No problems/.test(await p.textContent('#app')), 'list refreshed');
  await p.close();
  // non-owner: buttons disabled
  p = await open({ on: true, init: 'window.__OWNER=false;window.__PERMS={};window.__PROFILE={id:"u3",staff_id:"karim02",full_name:"Karim",status:"active",lang:"en"};', m: { ctx: { locations: [1], roles: ['storekeeper'] } } }, '#/ledgerlinks');
  ok(await p.locator('[data-act=lk_set][disabled]').count() === 12, 'non-owner cannot change the switches'); await p.close();

  // ---- brand P&L ----
  p = await open({}, '#/brandpnl');
  ok(await p.locator('.card.panel').count() === 2, 'two brand cards'); let bt = await p.textContent('#app'); ok(/ISLAMIYA/.test(bt) && /MISTY BARI/.test(bt), 'brand names'); ok(/300/.test(bt) && /37\.5%/.test(bt), 'gross profit and GP% shown when cost is returned');
  const bc = await calls(p, 'brand_pnl'); ok(bc.length >= 1 && /^\d{4}-\d{2}-01$/.test(bc[0].p_from), 'period defaults to this month'); await p.screenshot({ path: SP + '/fl_brand.png' }); await noOverflow(p, 'brand');
  await p.click('[data-act=px_mode][data-v=comb]'); await wait(p, 400); ok(await p.locator('.card.panel').count() === 1, 'combined = one card'); bt = await p.textContent('#app'); ok(/1,400|1400/.test(bt) && /600/.test(bt), 'combined sums revenue (1400) and gross profit (600)');
  await p.fill('#px_from', '2026-09-01'); await p.dispatchEvent('#px_from', 'change'); await wait(p, 400); const bc2 = await calls(p, 'brand_pnl'); ok(bc2[bc2.length - 1].p_from === '2026-09-01', 'date change re-queries'); await p.close();
  p = await open({ noCost: true }, '#/brandpnl'); bt = await p.textContent('#app'); ok(/hidden for your role/.test(bt) && !/Gross profit/.test(bt), 'cost-less caller: no profit, no cost'); await p.close();

  // ---- discounts ----
  p = await open({}, '#/discounts');
  ok(await p.locator('#px_body .row.between').count() >= 2, 'two discount rows'); bt = await p.textContent('#app'); ok(/Approver: owner1 \(by emergency approval\)/.test(bt) && /within the limit/.test(bt) && /30%/.test(bt), 'approver and kind shown; within-limit row says so');
  await p.screenshot({ path: SP + '/fl_disc.png' }); await noOverflow(p, 'discounts');
  await p.click('[data-act=px_onlyap]'); await wait(p, 400); const dc = await calls(p, 'discounts_report'); ok(dc[dc.length - 1].p_only_approved === true, 'approved-only filter sent'); ok(!/within the limit/.test(await p.textContent('#app')), 'filtered list'); await p.close();

  // ---- reports hub lists the new pages ----
  p = await open({}, '#/reports'); await wait(p, 500); bt = await p.textContent('#app'); ok(/Brand-level P&L/.test(bt) && /Discounts and approvers/.test(bt) && /Forms and the stock ledger/.test(bt), 'hub lists the three pages'); await p.close();

  // ---- Bangla mode ----
  p = await open({ on: true, lang: 'bn' }, '#/ledgerlinks'); ok(/ফর্ম/.test(await p.textContent('#app')), 'bangla labels'); await p.close();

  if (errors.length) { log('ERRORS:'); errors.forEach((e) => log(' ', e)); } else log('errors: none');
  log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('TEST CRASH', e); } srv.close(); process.exit(0); })();
