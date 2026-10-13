// Groups A and B web pieces: cash moves page, switchboard, production void button, forms reading the locations table.
// Run: node groupab_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8353, srv = C.serve(PORT);
const EXTRA8 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 c.rpc = async (fn, args) => {
  (window.__AC8 = window.__AC8 || []).push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (fn === 'cash_move_add') { if (window.__ERR8) { const m = window.__ERR8; window.__ERR8 = null; return { data: null, error: { message: m, code: 'P0001' } }; } if (args.p_dry) return { data: { dry: true, daybook: 'cash out, bank in' }, error: null };
    T.cash_moves.unshift({ id: 'cm' + T.cash_moves.length, kind: args.p_kind, mode: args.p_mode, amount: args.p_amount, move_date: args.p_date, ref: args.p_ref, note: args.p_note, status: 'done', customer_id: args.p_customer, created_at: '2026-10-13T10:00:00Z' }); return { data: { id: 'x' }, error: null }; }
  if (fn === 'cash_move_void') { const r = T.cash_moves.find((x) => x.id === args.p_id); if (r) r.status = 'void'; return { data: { status: 'void' }, error: null }; }
  if (fn === 'customer_advances') return { data: [{ customer_id: 'c1', name: 'Karim', mobile: '01711', balance: 600 }], error: null };
  if (fn === 'has_grant') return { data: true, error: null };
  if (fn === 'production_void') return { data: { status: 'void', reversed_lines: 4 }, error: null };
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'blind_cfg_set') { T.blind_count_cfg.push({ form_code: args.p_form, location_id: args.p_loc, enabled: args.p_enabled }); return { data: {}, error: null }; }
  if (fn === 'pin_sig_cfg_set') { T.pin_sig_cfg.push({ form_code: args.p_form, enabled: args.p_enabled }); return { data: {}, error: null }; }
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, extra = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('reason text'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA8 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const T = data.tables;
    T.cash_moves = [{ id: 'cm0', kind: 'bank_deposit', mode: null, amount: 500, move_date: '2026-10-12', ref: 'slip1', note: 'x', status: 'done', created_at: '2026-10-12T10:00:00Z' }];
    T.rules = [
      { key: 'blind_count_on', module: 'entries', kind: 'switch', default_value: false, value: null, label_bn: 'অন্ধ গণনা', label_en: 'Blind count', sort: 1 },
      { key: 'pin_signature_on', module: 'entries', kind: 'switch', default_value: false, value: true, label_bn: 'পিন স্বাক্ষর', label_en: 'PIN signature', sort: 2 },
      { key: 'grn_receipt_source', module: 'stock', kind: 'choice', default_value: 'purchase', value: null, choices: ['purchase', 'grn'], label_bn: 'কেনা মাল কোথা থেকে', label_en: 'Bought goods source', sort: 3 },
      { key: 'ia_home_v2', module: 'ui', kind: 'switch', default_value: true, value: null, label_bn: 'নতুন হোম', label_en: 'New home', sort: 4 },
      { key: 'wastage_approval_limit', module: 'stock', kind: 'number', default_value: null, value: null, label_bn: 'সীমা', label_en: 'Limit', sort: 5 }];
    T.blind_count_cfg = []; T.pin_sig_cfg = [];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1200); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC8 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // ---- cash moves ----
  let p = await open('#/cashmoves');
  ok(await p.locator('#cm_body').count() === 1 && /Bank deposit/.test(await p.evaluate(() => document.body.innerText)), 'cash moves page lists the existing row');
  ok(/Karim/.test(await p.evaluate(() => document.body.innerText)), 'customer advances held are shown');
  ok(await p.locator('#cm_modew').isHidden(), 'mode hidden for a bank deposit');
  await p.selectOption('#cm_kind', 'owner_topup'); await wait(p, 100);
  ok(await p.locator('#cm_modew').isVisible(), 'mode shown for an owner top-up');
  await p.selectOption('#cm_kind', 'cust_advance'); await wait(p, 100);
  ok(await p.locator('#cm_custw').isVisible(), 'customer mobile shown for an advance');
  await p.selectOption('#cm_kind', 'bank_deposit'); await wait(p, 100);
  await p.fill('#cm_amt', '1500'); await p.click('[data-act=cm_dry]'); await wait(p, 300);
  let c = await calls(p, 'cash_move_add'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_amount === 1500 && c[0].p_kind === 'bank_deposit', 'dry check sent first');
  ok(/nothing was saved/.test(await p.textContent('#cm_out')), 'dry result text shown');
  await p.click('[data-act=cm_save]'); await wait(p, 500);
  c = await calls(p, 'cash_move_add'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_client, 'real save sent with a client id');
  ok((await p.locator('#cm_body .card').count()) >= 3, 'new row listed'); await noOverflow(p, 'cash moves');
  await p.click('[data-act=cm_void] >> nth=0'); await wait(p, 400);
  ok((await calls(p, 'cash_move_void')).length === 1, 'void sends the reason');
  await p.evaluate(() => { window.__ERR8 = 'exceeds_advance'; });
  await p.fill('#cm_amt', '10'); await p.click('[data-act=cm_save]'); await wait(p, 400);
  ok(/More than the advance held/.test(await p.evaluate(() => document.body.innerText)), 'friendly error text');
  await p.screenshot({ path: SP + '/ab_cash.png', fullPage: true });

  // ---- switchboard ----
  p = await open('#/switchboard');
  ok(await p.locator('.sw-row').count() === 4, 'four switch/choice rows (number rule excluded)');
  ok(await p.locator('.sw-row[data-key="pin_signature_on"] .chip.warn').count() === 1, 'changed marker on a changed rule');
  await p.fill('#sw_q', 'blind'); await wait(p, 200); ok(await p.locator('.sw-row').count() === 1, 'search narrows the list');
  await p.click('[data-act=sw_set]'); await wait(p, 500);
  c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'blind_count_on' && c[0].p_value === true, 'switching ON sends set_rule true');
  ok(await p.locator('.sw-row[data-key="blind_count_on"] [aria-checked="true"]').count() === 1, 'row now ON');
  await p.fill('#sw_q', ''); await wait(p, 200);
  await p.click('.sw-row[data-key="pin_signature_on"] [data-act=sw_reset]'); await wait(p, 400);
  c = await calls(p, 'set_rule'); ok(c.length === 2 && c[1].p_value === null, 'back to default sends null');
  await p.evaluate(() => { document.querySelector('#sw_perform').open = true; }); await wait(p, 100);
  await p.click('#sw_perform [data-act=sw_pin][data-f="04-3"]'); await wait(p, 400);
  c = await calls(p, 'pin_sig_cfg_set'); ok(c.length === 1 && c[0].p_form === '04-3' && c[0].p_enabled === false, 'per-form PIN switch');
  await noOverflow(p, 'switchboard'); await p.screenshot({ path: SP + '/ab_switch.png', fullPage: true });
  p = await open('#/switchboard'); await p.selectOption('#sw_mod', 'ui'); await wait(p, 150); ok(await p.locator('.sw-row').count() === 1, 'section filter');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
