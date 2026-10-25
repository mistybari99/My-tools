// C2: transfer challan print, marked return and receiver count (rules of phase115), batch check in the reconcile sheet (phase114). Headless Chromium, stubbed rpc.
// Run: node tests/web/transfer_c2_test.js [tests/web dir]
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), srv = C.serve(PORT);
const RULE = (k) => `window.__DATA.tables.rules.push({key:'${k}',module:'x',kind:'switch',value:true,default_value:false,label_bn:'${k}',label_en:'${k}',label_mix:'${k}',sort:1});`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, pass = 0; const ok = (c, m) => { if (c) pass++; else { bad++; log('FAIL:', m); } };
  const BN = /[ঀ-৿]/;
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(C.mkData(base, o))};window.__M0=${JSON.stringify(o.m || {})};${o.init || ''};window.__IFR=[];
      (function(){ const d = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'srcdoc'); Object.defineProperty(HTMLIFrameElement.prototype, 'srcdoc', { set(v) { window.__IFR.push(v); d.set.call(this, v); }, get() { return d.get.call(this); } }); })();
      try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1000); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const xferSheet = async (p) => { await p.click('[data-act=s2_actions]'); await wait(p, 300); await p.click('[data-act=s2_do][data-v=xfer]'); await wait(p, 300); };
  const SENT = { id: 'ab12cd34-0000-4000-8000-000000000001', status: 'sent', qty: 2 };

  // ---------- 1. rules OFF: no return switch; challan print after sending and on the transfer card ----------
  let p = await open({}, '#/stock');
  await xferSheet(p);
  ok(await p.locator('#a_ret').count() === 0, 'rule off: no return switch in the transfer sheet');
  await p.evaluate((s) => { window.__M.xferResp = s; }, SENT);
  await p.evaluate((s) => { const o = window.BOS_APP.sb.rpc; window.BOS_APP.sb.rpc = async (fn, a) => (fn === 'stock_transfer' ? (window.__M.calls.push([fn, JSON.parse(JSON.stringify(a))]), { data: s, error: null }) : o(fn, a)); }, SENT);
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '2'); await p.selectOption('#a_to', '2'); await p.fill('#a_note', 'van 7'); await p.click('#a_go'); await wait(p, 500);
  ok(await p.locator('#s2_chbtn').count() === 1, 'after sending: Print challan button in the sheet');
  ok(/Sent/.test(await p.textContent('#sheet')), 'sent text: ' + (await p.textContent('#sheet')).slice(0, 80));
  await noOverflow(p, 'sent sheet'); await p.screenshot({ path: SP + '/c2_sent.png' });
  await p.click('#s2_chbtn'); await wait(p, 500);
  let ifr = await p.evaluate(() => window.__IFR);
  ok(ifr.length === 1 && /TR-AB12CD34/.test(ifr[0]) && /I-001/.test(ifr[0]) && /van 7/.test(ifr[0]) && !BN.test(ifr[0].replace(/<style[\s\S]*?<\/style>/, '').replace(/<td[^>]*>[^<]*<\/td>/g, '')), 'built-in challan printed: number, item, note, English only ' + JSON.stringify([ifr.length, /TR-AB12CD34/.test(ifr[0]), /I-001/.test(ifr[0]), /van 7/.test(ifr[0]), (ifr[0] || '').replace(/<style[\s\S]*?<\/style>/, '').slice(0, 700)]));
  ok(!/cost|price|rate|value/i.test(ifr[0].replace(/<style[\s\S]*?<\/style>/, '').replace(/<[^>]+>/g, ' ')), 'challan has no cost words');
  await p.close();

  // transfer card
  p = await open({}, '#/stock'); await p.click('[data-act=s2_tab][data-v=tr]'); await wait(p, 500);
  ok(await p.locator('[data-act=s2_chal]').count() === 2, 'print button on each transfer card');
  ok(await p.locator('[data-act=s2_xrecv]').count() === 2 && await p.locator('[data-act=s2_xcancel]').count() === 2, 'receive / take back untouched');
  await noOverflow(p, 'transit tab'); await p.screenshot({ path: SP + '/c2_transit.png' });
  // owner template chosen -> the chosen template is used
  await p.evaluate(() => { window.BOS.tpl.ensure = async () => true; window.BOS.tpl.setChoices([{ doc_type: 'stock_transfer', template_id: 'a4_classic', location_id: null }]); });
  await p.click('[data-act=s2_chal] >> nth=0'); await wait(p, 500);
  ifr = await p.evaluate(() => window.__IFR);
  ok(ifr.length === 1 && /@page/.test(ifr[0]) && /I-001/.test(ifr[0]) && /TR-/.test(ifr[0]) && !/data-ch="builtin"/.test(ifr[0]), 'chosen stock_transfer template rendered with the transfer data');
  await p.close();

  // ---------- 2. return rule ON ----------
  const RET = { id: 'ff000000-0000-4000-8000-0000000000aa', status: 'sent', qty: 2, kind: 'return' };
  p = await open({ init: RULE('transfer_return_marker') + `window.__DATA.tables.stock_transfers=[{id:'orig1',item_id:'${base.tables.items[0].id}',from_location_id:2,to_location_id:1,status:'received',qty:10,received_qty:9,sent_at:'2026-10-10T08:00:00Z',kind:null}];` }, '#/stock');
  await xferSheet(p);
  ok(await p.locator('#a_ret').count() === 1 && await p.locator('#a_retbox').isHidden(), 'rule on: return switch shown, reason box hidden');
  await p.evaluate((s) => { const o = window.BOS_APP.sb.rpc; window.BOS_APP.sb.rpc = async (fn, a) => (fn === 'stock_return_transfer' ? (window.__M.calls.push([fn, JSON.parse(JSON.stringify(a))]), { data: s, error: null }) : o(fn, a)); }, RET);
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '2'); await p.selectOption('#a_to', '2');
  await p.click('#a_ret'); await wait(p, 400);
  ok(await p.locator('#a_retbox').isVisible(), 'switch shows the reason box'); await noOverflow(p, 'return sheet'); await p.screenshot({ path: SP + '/c2_return.png' });
  ok(await p.locator('#a_rreason option').count() === 6, 'five reasons + blank');
  ok(!BN.test(await p.textContent('#a_retbox')), 'English mode: return box all English');
  await p.click('#a_go'); await wait(p, 200);
  ok(/Choose the reason/.test(await p.textContent('#toast')) && (await calls(p, 'stock_return_transfer')).length === 0, 'reason required before any call');
  await p.selectOption('#a_rreason', 'other'); await p.click('#a_go'); await wait(p, 200);
  ok(/Write a note/.test(await p.textContent('#toast')) && (await calls(p, 'stock_return_transfer')).length === 0, 'reason Other needs a note');
  await p.selectOption('#a_rreason', 'damaged');
  await p.evaluate(() => { const s = document.querySelector('#a_to'); s.dispatchEvent(new Event('change', { bubbles: true })); }); await wait(p, 300);
  ok(await p.locator('#a_rref option').count() === 2, 'original-transfer choice lists the received transfer: ' + await p.locator('#a_rref option').count());
  await p.selectOption('#a_rref', 'orig1'); await p.click('#a_go'); await wait(p, 500);
  const rc = await calls(p, 'stock_return_transfer');
  ok(rc.length === 1 && rc[0].p_reason === 'damaged' && rc[0].p_ref === 'orig1' && rc[0].p_from === 1 && rc[0].p_to === 2 && rc[0].p_qty === 2 && rc[0].p_client, 'return RPC args: ' + JSON.stringify(rc[0]));
  ok((await calls(p, 'stock_transfer')).length === 0, 'plain stock_transfer not called for a return');
  ok(await p.locator('#s2_chbtn').count() === 1 && /Return sent/.test(await p.textContent('#sheet')), 'return sent sheet with Print challan');
  await p.close();
  // server refuses -> readable message
  p = await open({ init: RULE('transfer_return_marker') }, '#/stock'); await xferSheet(p);
  await p.fill('#a_item', 'I-001'); await p.fill('#a_qty', '2'); await p.selectOption('#a_to', '2'); await p.click('#a_ret'); await p.selectOption('#a_rreason', 'excess');
  await p.evaluate(() => { window.__M.fail.stock_return_transfer = { msg: 'return_exceeds_receipt' }; }); await p.click('#a_go'); await wait(p, 300);
  ok(/Cannot return more than was received/.test(await p.textContent('#toast')), 'return_exceeds_receipt readable: ' + await p.textContent('#toast'));
  await p.close();
  // Bangla mode shows Bangla
  p = await open({ lang: 'bn', init: RULE('transfer_return_marker') }, '#/stock'); await xferSheet(p);
  ok(BN.test(await p.textContent('#a_ret')), 'Bangla mode: return switch label in Bangla'); await p.close();

  // ---------- 3. receiver count ----------
  p = await open({ init: RULE('transfer_notify_receiver') }, '#/stock'); await wait(p, 300);
  ok(await p.locator('#s2_incnt').count() === 1 && (await p.textContent('#s2_incnt')).trim() === '2', 'rule on, owner: tab shows both open transfers');
  await p.close();
  p = await open({ init: RULE('transfer_notify_receiver'), m: { ctx: { is_owner: false, roles: ['storekeeper'], locations: [1] } } }, '#/stock'); await wait(p, 300);
  ok(await p.locator('#s2_incnt').count() === 1 && (await p.textContent('#s2_incnt')).trim() === '1', 'rule on, branch user at place 1: only the transfer coming to place 1'); await p.close();
  p = await open({}, '#/stock'); ok(await p.locator('#s2_incnt').count() === 0, 'rule off: no number on the tab'); await p.close();

  // ---------- 4. batch check in the reconcile sheet (owner) ----------
  p = await open({}, '#/stock');
  await p.evaluate(() => { const o = window.BOS_APP.sb.rpc; window.BOS_APP.sb.rpc = async (fn, a) => (fn === 'stock_batch_reconcile' ? (window.__M.calls.push([fn, a]), { data: window.__BR, error: null }) : o(fn, a)); window.__BR = []; });
  await p.click('[data-act=s2_recon]'); await wait(p, 500);
  ok(await p.locator('#s2_batchok').count() === 1 && (await calls(p, 'stock_batch_reconcile'))[0].p_fix === false, 'batches match line, read-only call (p_fix false)');
  await p.click('#sheet [data-act=closesheet]'); await wait(p, 200);
  await p.evaluate((id) => { window.__BR = [{ item_id: id, location_id: 1, balance: 5, batch_sum: 7, diff: 2, fixed: false }]; }, base.tables.items[0].id);
  await p.click('[data-act=s2_recon]'); await wait(p, 500);
  ok(await p.locator('#s2_batchbad').count() === 1 && /stock 5/.test(await p.textContent('#s2_batchbad')) && /batches 7/.test(await p.textContent('#s2_batchbad')), 'mismatch listed');
  await noOverflow(p, 'recon sheet'); await p.screenshot({ path: SP + '/c2_batch.png' });
  await p.close();
  p = await open({}, '#/stock'); await p.click('[data-act=s2_recon]'); await wait(p, 500);
  ok(await p.locator('#s2_batchok, #s2_batchbad').count() === 0, 'function missing/no answer: nothing extra shown'); await p.close();
  p = await open({ m: { ctx: { is_owner: false, roles: ['storekeeper'], locations: [1] } } }, '#/stock'); ok(await p.locator('[data-act=s2_recon]').count() === 0, 'non-owner: no reconcile button'); await p.close();

  const real = errors.filter((e) => !/Content Security Policy/.test(e));   // inline-script CSP notice of the harness: same in every test
  ok(real.length === 0, 'no page errors: ' + real.slice(0, 3).join(' | '));
  log(`transfer_c2_test: ${pass} pass, ${bad} fail`); await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('ERR', e); process.exit(1); } })();
