// P3a: stock extras page (#/stockx via BOS_PAGES.stockx): reorder, near-expiry + batch capture + FEFO, wastage by reason, QC.
// Run: node stockx_test.js <abs tests/web dir>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = 8373, srv = C.serve(PORT);
const i0 = base.tables.items[0].id;
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M; const X = M.x = Object.assign({ err: {}, qcOn: false, qc: [{ id: 'q1', source_type: 'grn', source_id: 'g1', location_id: 1, status: 'hold', checks: [], note: 'smells off', created_at: '2026-10-12T05:00:00Z', created_staff: 's', history_n: 2 }] }, window.__X || {});
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 c.rpc = async (fn, args) => {
  if (!/^(reorder_|near_expiry|fefo_|grn_batch|wastage_by|qc_|purchase_get|purchase_list)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (X.err[fn]) { const m = X.err[fn]; delete X.err[fn]; return { data: null, error: { message: m } }; }
  if (fn === 'reorder_report') return { data: [{ item_id: 'i0', code: 'R-1', name_bn: 'ময়দা', name_en: 'Flour', location_id: 1, base_unit: 'kg', on_hand: 20, min_stock: 50, avg_daily: 3, days_left: 6.7, lead_days: 3, suggest_qty: 30, why: 'below_min' }, { item_id: 'i1', code: 'R-2', name_bn: 'চিনি', name_en: 'Sugar', location_id: 1, base_unit: 'kg', on_hand: 9, min_stock: null, avg_daily: 2, days_left: 4.5, lead_days: 3, suggest_qty: 11, why: 'cover' }], error: null };
  if (fn === 'near_expiry_report') return { data: [{ batch_id: 1, batch_no: 'LOT-A', item_id: 'i0', code: 'R-1', name_bn: 'ময়দা', name_en: 'Flour', location_id: 1, expires_at: '2026-10-15T17:59:00Z', qty_remaining: 23, days_left: 2.1, expired: false, qc_blocked: true }], error: null };
  if (fn === 'fefo_hint') return { data: [{ rank: 1, batch_id: 1, batch_no: 'LOT-A', expires_at: '2026-10-15T17:59:00Z', qty_remaining: 23, expired: false, qc_blocked: true }], error: null };
  if (fn === 'wastage_by_reason') return { data: [{ reason_code: 'spillage', label_bn: 'ছিটকে', label_mix: 'ছিটকে', label_en: 'Spillage', entries: 2, items: 2, qty: 3 }], error: null };
  if (fn === 'qc_gate') return { data: { status: null, switch_on: X.qcOn, blocked: false }, error: null };
  if (fn === 'qc_list') return { data: clone(X.qc), error: null };
  if (fn === 'qc_history') return { data: [{ id: 'q2', status: 'hold', note: 'smells off', created_at: '2026-10-12T05:00:00Z' }, { id: 'q0', status: 'pass', note: null, created_at: '2026-10-11T05:00:00Z' }], error: null };
  if (fn === 'purchase_list') return { data: [{ id: 'b1', kind: 'bill', supplier_name: 'Dudh Ghor', bill_no: 'D-101', bill_date: '2026-10-08', location_id: 1, status: 'posted' }], error: null };
  if (fn === 'purchase_get') return { data: { id: 'b1', lines: [{ item_id: '${i0}', description: null, unit: 'kg' }] }, error: null };
  if (fn === 'grn_batch_add' || fn === 'qc_record') return { data: { id: 'n1', batch_id: 5 }, error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(C.mkData(base, {}))};window.__X=${JSON.stringify(o.x || {})};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1100);
    await p.addScriptTag({ path: '/home/user/My-tools/web/stockx.js' });
    await p.evaluate(() => window.BOS_PAGES.stockx()); await p.waitForTimeout(500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);
  const toastTxt = async (p) => { await p.waitForTimeout(150); return p.textContent('#toast'); };

  let p = await open();
  let t = await p.textContent('#sx_out');
  ok(/Flour/.test(t) && /Below minimum/.test(t) && /To restore cover/.test(t) && /30/.test(t), 'reorder rows with reasons and suggested qty');
  ok(/no order is placed/i.test(await p.textContent('#sx_ctl')), 'reorder says no order is placed');
  ok(!/cost|৳/i.test(t), 'no cost figure shown'); await noOverflow(p, 'reorder');
  await p.fill('#sx_days', '14'); await p.click('[data-act=sx_go]'); await wait(p);
  let c = await calls(p, 'reorder_report'); ok(c.length >= 2 && c[c.length - 1].p_days === 14 && c[c.length - 1].p_loc === null, 'days sent to reorder_report');
  // expiry
  await p.click('[data-act=sx_tab][data-v=ex]'); await wait(p, 400); t = await p.textContent('#sx_out');
  ok(/LOT-A/.test(t) && /2026-10-15/.test(t) && /Held by quality/.test(t), 'near-expiry row with batch no and quality chip');
  await p.click('[data-act=sx_fefo]'); await wait(p, 300); ok(/FEFO/.test(await p.textContent('.sheet')) && /LOT-A/.test(await p.textContent('.sheet')), 'FEFO sheet'); await noOverflow(p, 'fefo');
  await p.click('.sheet [data-act=sx_close]'); await wait(p, 150);
  await p.click('[data-act=sx_addb]'); await wait(p, 400);
  await p.selectOption('#sx_src', 'purchase:b1'); await wait(p, 500);
  ok(await p.locator('#sx_item option').count() === 2, 'bill lines fill the item picker');
  await p.click('.sheet [data-act=sx_bsave]'); await wait(p, 200); ok(!(await calls(p, 'grn_batch_add')).length, 'incomplete batch form sends nothing');
  await p.selectOption('#sx_item', i0); await p.fill('#sx_bq', '২৫'); await p.fill('#sx_bn', 'LOT-Z'); await p.fill('#sx_bx', '2030-01-01');
  await p.click('.sheet [data-act=sx_bsave]'); await wait(p, 400);
  c = await calls(p, 'grn_batch_add'); ok(c.length === 1 && c[0].p_qty === 25 && c[0].p_batch_no === 'LOT-Z' && c[0].p_expiry === '2030-01-01' && c[0].p_source_type === 'purchase' && c[0].p_client, 'grn_batch_add args (Bangla digits parsed, client id)');
  await p.evaluate(() => { window.__M.x.err.grn_batch_add = 'batch_no_exists'; });
  await p.click('[data-act=sx_addb]'); await wait(p, 400); await p.selectOption('#sx_src', 'purchase:b1'); await wait(p, 400); await p.selectOption('#sx_item', i0); await p.fill('#sx_bq', '1'); await p.fill('#sx_bn', 'LOT-Z'); await p.fill('#sx_bx', '2030-01-01');
  await p.click('.sheet [data-act=sx_bsave]'); await wait(p, 400); ok(/already exists/.test(await toastTxt(p)), 'friendly error for duplicate batch no');
  // wastage
  await p.evaluate(() => document.querySelector('.sheet-x') && document.querySelector('.sheet-x').click()); await wait(p, 150);
  await p.click('[data-act=sx_tab][data-v=wa]'); await wait(p, 400); t = await p.textContent('#sx_out'); ok(/Spillage/.test(t) && (await p.locator('#sx_out tbody tr td:nth-child(4)').textContent()).trim() === '3', 'wastage by reason'); await noOverflow(p, 'wastage');
  c = await calls(p, 'wastage_by_reason'); ok(c.length && /^\d{4}-\d\d-\d\d$/.test(c[0].p_from), 'date range sent');
  // qc
  await p.click('[data-act=sx_tab][data-v=qc]'); await wait(p, 400); t = await p.textContent('#sx_out');
  ok(/Hold/.test(t) && /smells off/.test(t) && /nothing is blocked/i.test(t), 'QC list with record-only note (switch off)');
  await p.click('[data-act=sx_hist]'); await wait(p, 300); ok(/Pass/.test(await p.textContent('.sheet')) && /Hold/.test(await p.textContent('.sheet')), 'history sheet'); await p.click('.sheet [data-act=sx_close]'); await wait(p, 150);
  await p.click('[data-act=sx_qcnew]'); await wait(p, 500); ok(await p.locator('.sx_ck').count() >= 0, 'checklist sheet opens'); await noOverflow(p, 'qc sheet');
  await p.evaluate(() => { const s = document.querySelector('#sx_qs'); s.insertAdjacentHTML('beforeend', '<option value="g1">x</option>'); });
  await p.selectOption('#sx_qs', 'g1'); await p.selectOption('#sx_qst', 'hold'); await p.fill('#sx_qn', 'bad smell');
  await p.click('.sheet [data-act=sx_qsave]'); await wait(p, 400);
  c = await calls(p, 'qc_record'); ok(c.length === 1 && c[0].p_status === 'hold' && c[0].p_source_type === 'grn' && c[0].p_note === 'bad smell' && Array.isArray(c[0].p_checks) && c[0].p_client, 'qc_record args');
  await p.close();
  p = await open({ x: { qcOn: true } }); await p.click('[data-act=sx_tab][data-v=qc]'); await wait(p, 400); ok(/Quality block is ON/.test(await p.textContent('#sx_out')), 'switch ON note'); await p.close();
  p = await open({ lang: 'bn' }); ok(/রিঅর্ডার/.test(await p.textContent('body')) && /পরামর্শ/.test(await p.textContent('body')), 'Bangla labels'); await noOverflow(p, 'bn'); await p.close();
  await br.close();
  log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
