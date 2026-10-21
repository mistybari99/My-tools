// Dealer business web pieces (phases 127-129): cheques / PDC, principal schemes, tinting. RPCs are mocked; the three screen files are injected after the app has loaded
// (index.html is not edited by this task - the exact tags are in docs/regs/dealer127.md).
// Run: node dealer127_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const EXTRA9 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const W = window.__DL = window.__DL || { err: {}, cheques: [
   { id: 'k1', location_id: 1, direction: 'received', party_kind: 'customer', party_name: 'test_user_b <b>Traders</b>', bank_name: 'Sonali', cheque_no: 'CH-1', amount: 6000.5, cheque_date: '2026-10-01', due_date: '2026-10-01', status: 'deposited', bounce_reason: null, bounce_charge: 0 },
   { id: 'k2', location_id: 1, direction: 'issued', party_kind: 'supplier', party_name: 'Principal One', bank_name: 'City', cheque_no: 'ISS-1', amount: 12000, cheque_date: '2026-10-20', due_date: '2026-10-20', status: 'registered', bounce_reason: null, bounce_charge: 0 },
   { id: 'k3', location_id: 1, direction: 'received', party_kind: 'customer', party_name: 'test_user_a', bank_name: 'Islami', cheque_no: 'CH-3', amount: 4000, cheque_date: '2026-09-20', due_date: '2026-09-20', status: 'bounced', bounce_reason: 'Insufficient funds', bounce_charge: 150.56 }],
   schemes: [{ id: 's1', supplier_id: 'u1', supplier_name: 'Principal One', name: 'Quarterly slab', kind: 'slab', basis: 'purchase', measure: 'value', valid_from: '2026-09-01', valid_to: '2026-12-31', status: 'active', accrued: 3180.02, claimed: 2000, received: 2000 },
     { id: 's2', supplier_id: 'u1', supplier_name: 'Principal One', name: 'Draft target', kind: 'target', basis: 'purchase', measure: 'value', valid_from: '2026-09-01', valid_to: '2026-12-31', status: 'draft', accrued: 0, claimed: 0, received: 0 }],
   claims: [{ id: 'c1', scheme_id: 's1', scheme_name: 'Quarterly slab', supplier_id: 'u1', supplier_name: 'Principal One', claim_no: 'CL-1', claim_date: '2026-10-10', amount: 2000, status: 'part_settled', received: 1500, outstanding: 500 }],
   forms: [{ id: 'f1', shade_code: 'BR-101', shade_name: 'Brick red', base_item_id: 'i1', pack_label: '4L', base_qty_per_pack: 1, version: 2, status: 'active', used: true, colorants: 2 }],
   jobs: [{ id: 'j1', job_no: 7, location_id: 1, shade_code: 'BR-101', formula_version: 2, base_item_id: 'i1', customer_id: 'cu1', customer_name: 'test_user_b Traders', packs: 3, job_date: '2026-10-12', charge_amount: 4200.5, status: 'done' }] };
 c.rpc = async (fn, args) => {
  (window.__AC9 = window.__AC9 || []).push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (!/^(org_unit_scope|cheque_|cheques_|post_dated_exposure|scheme_|claim_|tint_)/.test(fn)) return rpc(fn, args);
  if (W.err[fn]) { const m = W.err[fn]; delete W.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  const ok = (d) => ({ data: d, error: null });
  if (fn === 'org_unit_scope') return ok({ location_id: args.p_location, mapped: true, business_id: 7, business_code: 'HARDWARE' });
  if (fn === 'cheque_list') return ok(W.cheques);
  if (fn === 'cheques_due') return ok(W.cheques.filter((x) => x.status === 'registered' || x.status === 'deposited').map((x) => Object.assign({}, x, { days_to_due: x.status === 'deposited' ? -12 : 7, bucket: x.status === 'deposited' ? 'overdue' : 'this_week' })));
  if (fn === 'cheques_bounced') return ok(W.cheques.filter((x) => x.status === 'bounced').map((x) => Object.assign({}, x, { bounced_on: '2026-10-02' })));
  if (fn === 'post_dated_exposure') return ok([{ direction: 'issued', party_kind: 'supplier', party_id: 'u1', party_name: 'Principal One', cheques: 1, total: 12000, earliest_due: '2026-10-20', latest_due: '2026-10-20' }]);
  if (fn === 'cheque_register') { W.cheques.unshift({ id: 'kn' + W.cheques.length, location_id: args.p_loc, direction: args.p_dir, party_kind: args.p_party_kind, party_name: args.p_party_name || 'New party', bank_name: args.p_bank, cheque_no: args.p_no, amount: args.p_amount, cheque_date: args.p_cheque_date, due_date: args.p_due_date || args.p_cheque_date, status: 'registered', bounce_charge: 0 }); return ok({ id: 'kn', status: 'registered' }); }
  if (fn === 'cheque_deposit') { const r = W.cheques.find((x) => x.id === args.p_id); if (r) r.status = 'deposited'; return ok({ status: 'deposited' }); }
  if (fn === 'cheque_clear') { if (args.p_dry) return ok({ dry: true, amount: 6000.5, balance_before: 10000, balance_after: 3999.5 }); const r = W.cheques.find((x) => x.id === args.p_id); if (r) r.status = 'cleared'; return ok({ status: 'cleared' }); }
  if (fn === 'cheque_bounce') { const r = W.cheques.find((x) => x.id === args.p_id); if (r) { r.status = 'bounced'; r.bounce_reason = args.p_reason; r.bounce_charge = args.p_charge; } return ok({ status: 'bounced' }); }
  if (fn === 'cheque_cancel') { const r = W.cheques.find((x) => x.id === args.p_id); if (r) r.status = 'cancelled'; return ok({ status: 'cancelled' }); }
  if (fn === 'cheque_replace') { const r = W.cheques.find((x) => x.id === args.p_old); if (r) r.status = 'replaced'; return ok({ id: 'kr', status: 'registered' }); }
  if (fn === 'scheme_list') return ok(W.schemes);
  if (fn === 'claim_list') return ok(W.claims);
  if (fn === 'scheme_reconciliation') return ok([{ scheme_id: 's1', supplier_id: 'u1', supplier_name: 'Principal One', scheme_name: 'Quarterly slab', status: 'active', accrued: 1320.01, claimed: 2000, received: 2000, rejected: 1180.02, unclaimed: 0, outstanding: 0, over_claimed: 679.99 }]);
  if (fn === 'scheme_accrue') return ok({ base_value: 106000.5, base_qty: 160, earned: 3180.02, already_accrued: 3000, delta: 180.02, dry: !!args.p_dry });
  if (fn === 'scheme_save') { W.schemes.unshift({ id: 'sn', supplier_id: args.p_supplier, supplier_name: 'Principal One', name: args.p_name, kind: args.p_kind, basis: args.p_basis, measure: args.p_measure, valid_from: args.p_from, valid_to: args.p_to, status: 'draft', accrued: 0, claimed: 0, received: 0 }); return ok({ id: 'sn', status: 'draft' }); }
  if (fn === 'scheme_activate') { const r = W.schemes.find((x) => x.id === args.p_id); if (r) r.status = 'active'; return ok({ status: 'active' }); }
  if (fn === 'scheme_close') return ok({ status: 'closed' });
  if (fn === 'claim_create') { W.claims.unshift({ id: 'cn', scheme_id: args.p_scheme, scheme_name: 'Quarterly slab', supplier_name: 'Principal One', claim_no: args.p_claim_no, claim_date: args.p_date, amount: args.p_amount, status: 'submitted', received: 0, outstanding: args.p_amount }); return ok({ id: 'cn', status: 'submitted' }); }
  if (fn === 'claim_receive') return ok({ status: 'settled' });
  if (fn === 'claim_reject') return ok({ status: 'rejected' });
  if (fn === 'tint_formula_list') return ok(W.forms);
  if (fn === 'tint_job_list') return ok(W.jobs);
  if (fn === 'tint_cost_report') return W.noCost ? { data: null, error: { message: 'not allowed', code: 'P0001' } } : ok([{ shade_code: 'BR-101', jobs: 2, packs: 4, cost_total: 3246.31, cost_per_pack: 811.5775, charge_total: 4200.5, unknown_cost_jobs: 0 }]);
  if (fn === 'tint_job_run') { const lines = [{ role: 'base', item_id: 'i1', qty: 3, on_hand: 17, short: false }, { role: 'colorant', item_id: 'i2', qty: 37.5, on_hand: 20, short: true }];
    if (args.p_dry) return ok({ dry: true, lines, short: true, estimated_cost: 2434.58 });
    W.jobs.unshift({ id: 'jn', job_no: 8, location_id: args.p_loc, shade_code: 'BR-101', formula_version: 2, base_item_id: 'i1', customer_id: args.p_customer, customer_name: 'test_user_b Traders', packs: args.p_packs, job_date: '2026-10-14', charge_amount: args.p_charge, status: 'done' }); return ok({ id: 'jn', status: 'done' }); }
  if (fn === 'tint_job_void') { const r = W.jobs.find((x) => x.id === args.p_job); if (r) r.status = 'void'; return ok({ status: 'void' }); }
  if (fn === 'tint_customer_shades') return ok([{ shade_code: 'BR-101', jobs: 2, packs: 4, last_date: '2026-10-12', last_base_item: 'i1', last_formula_version: 2 }, { shade_code: 'GR-202', jobs: 1, packs: 1, last_date: '2026-10-05', last_base_item: 'i1', last_formula_version: 1 }]);
  if (fn === 'tint_formula_save') { W.forms.unshift({ id: 'fn', shade_code: String(args.p_shade_code).toUpperCase(), shade_name: args.p_shade_name, base_item_id: args.p_base_item, pack_label: args.p_pack_label, base_qty_per_pack: args.p_base_qty, version: 1, status: 'active', used: false, colorants: args.p_lines.length }); return ok({ id: 'fn', version: 1 }); }
  return rpc(fn, args);
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, lang = 'en') {
    const ctx = await br.newContext({ bypassCSP: true, viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => { const q = (window_prompts.shift() || {}); if (d.type() === 'prompt') d.accept(q.v !== undefined ? q.v : (d.defaultValue() || 'reason test')); else d.accept(); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA9 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {}); const T = data.tables;
    T.customers = [{ id: 'cu1', name: 'test_user_b Traders', mobile: '01700000001' }]; T.suppliers = [{ id: 'u1', name: 'Principal One' }];
    T.items = (T.items || []).concat([{ id: 'i1', code: 'I-101', name_bn: 'ইমালশন বেস', name_en: 'Emulsion base', name_mix: 'Emulsion base' }, { id: 'i2', code: 'I-102', name_bn: 'কালারেন্ট', name_en: 'Colorant', name_mix: 'Colorant' }]);
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','${lang}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/`); await p.waitForTimeout(1200);
    for (const f of ['cheques127.js', 'schemes128.js', 'tinting129.js']) await p.addScriptTag({ url: `http://localhost:${PORT}/${f}` });
    await p.evaluate((h) => { location.hash = h; }, hash); await p.waitForTimeout(900); return p;
  }
  const window_prompts = [];
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC9 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const text = (p) => p.evaluate(() => document.body.innerText);

  // ---- cheques ----
  let p = await open('#/cheques');
  ok(await p.locator('#ch_body').count() === 1, 'cheques page renders');
  let t = await text(p); ok(/Sonali/.test(t) && /ISS-1/.test(t) && /Cheque \/ PDC register/.test(t), 'cheque list shows rows (English)');
  ok(await p.locator('#ch_body b:has-text("Traders")').count() === 1 && (await p.locator('#ch_body b >> text=<b>').count()) === 0 || /test_user_b <b>Traders<\/b>/.test(t), 'party name is escaped (no injected element)');
  ok((await p.locator('#ch_body .card b b').count()) === 0, 'escaped markup creates no nested element');
  await noOverflow(p, 'cheques list');
  window_prompts.push({ v: '2026-10-14' });
  await p.click('[data-act=ch_clear] >> nth=0'); await wait(p, 400);
  let c = await calls(p, 'cheque_clear'); ok(c.length === 2 && c[0].p_dry === true && c[1].p_dry === false && c[1].p_client, 'clear = dry run first, then the real call with a client id');
  ok(/cleared/.test(await text(p)), 'row is cleared after the call');
  await p.click('[data-act=ch_tab][data-v=due]'); await wait(p, 200); ok(/late/.test(await text(p)) || /days/.test(await text(p)), 'due tab shows aging');
  await p.click('[data-act=ch_tab][data-v=bounced]'); await wait(p, 200); ok(/Insufficient funds/.test(await text(p)) && /150/.test(await text(p)), 'bounced tab shows reason and charge');
  await p.click('[data-act=ch_tab][data-v=exp]'); await wait(p, 200); ok(/Principal One/.test(await text(p)) && /12,000/.test(await text(p)), 'post-dated exposure per party');
  await p.click('[data-act=ch_tab][data-v=new]'); await wait(p, 300);
  await p.selectOption('#ch_party', 'other'); await wait(p, 100); ok(await p.locator('#ch_namew').isVisible(), 'name field shown for party "other"');
  await p.fill('#ch_pname', 'Walk-in Co'); await p.fill('#ch_bank', 'Brac'); await p.fill('#ch_no', 'W-9'); await p.fill('#ch_amt', '500.505');
  await p.click('[data-act=ch_save]'); await wait(p, 500);
  c = await calls(p, 'cheque_register'); ok(c.length === 1 && c[0].p_client && c[0].p_party_kind === 'other' && c[0].p_party_name === 'Walk-in Co' && c[0].p_bank === 'Brac', 'register sent with a client id');
  ok(/W-9/.test(await text(p)), 'new cheque listed');
  await p.click('[data-act=ch_tab][data-v=new]'); await wait(p, 200); await p.fill('#ch_amt', '10'); await p.fill('#ch_bank', 'X'); await p.fill('#ch_no', 'X1');
  await p.evaluate(() => { window.__DL.err.cheque_register = 'feature_off'; });
  await p.click('[data-act=ch_save]'); await wait(p, 400);
  ok(/switched off/.test(await text(p)), 'friendly error for the switch being off');
  await p.evaluate(() => { window.__DL.err.cheque_register = 'duplicate_cheque'; }); await p.click('[data-act=ch_save]'); await wait(p, 400);
  ok(/already exists/.test(await text(p)), 'friendly error for a duplicate cheque');
  await p.screenshot({ path: SP + '/dl_cheques.png', fullPage: true }); await noOverflow(p, 'cheques form');
  p = await open('#/cheques', 'bn'); ok(/চেক/.test(await text(p)), 'Bangla labels'); await noOverflow(p, 'cheques bn');

  // ---- schemes ----
  p = await open('#/schemes');
  t = await text(p); ok(/Quarterly slab/.test(t) && /Principal One/.test(t) && /Draft target/.test(t), 'schemes listed'); await noOverflow(p, 'schemes');
  await p.click('[data-act=sc_prev] >> nth=0'); await wait(p, 300);
  c = await calls(p, 'scheme_accrue'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_client === null, 'preview is a dry run without a client id');
  ok(/nothing was saved/.test(await text(p)) && /3,180/.test(await text(p)), 'preview text and numbers shown');
  await p.click('[data-act=sc_accr]'); await wait(p, 500);
  c = await calls(p, 'scheme_accrue'); ok(c.length === 3 && c[1].p_dry === true && c[2].p_dry === false && c[2].p_client, 'accrue = preview, confirm, then the real call with a client id');
  await p.click('[data-act=sc_act]'); await wait(p, 300); ok((await calls(p, 'scheme_activate')).length === 1, 'draft scheme activated');
  window_prompts.push({ v: '1500' }, { v: 'CL-9' });
  await p.click('[data-act=sc_claim] >> nth=0'); await wait(p, 500);
  c = await calls(p, 'claim_create'); ok(c.length === 1 && c[0].p_amount === 1500 && c[0].p_client && c[0].p_claim_no === 'CL-9', 'claim created with a client id');
  ok(/CL-9/.test(await text(p)), 'claims tab lists the new claim');
  await p.evaluate(() => { window.__DL.err.claim_receive = 'overpaid'; }); window_prompts.push({ v: '99999' }, { v: 'R1' });
  await p.click('[data-act=sc_recv] >> nth=0'); await wait(p, 400); ok(/More than the claim/.test(await text(p)), 'friendly error: receipt above the outstanding');
  await p.evaluate(() => { window.__DL.err.claim_create = 'exceeds_accrual'; }); await p.click('[data-act=sc_tab][data-v=s]'); await wait(p, 200);
  window_prompts.push({ v: '5' }, { v: 'CL-10' }); await p.click('[data-act=sc_claim] >> nth=0'); await wait(p, 400); ok(/more than what is accrued/.test(await text(p)), 'friendly error: claim above the accrual');
  await p.click('[data-act=sc_tab][data-v=r]'); await wait(p, 200); t = await text(p); ok(/Over-claimed/.test(t) && /679/.test(t), 'reconciliation shows the over-claim');
  await p.click('[data-act=sc_tab][data-v=n]'); await wait(p, 300);
  await p.selectOption('#sc_sup', 'u1'); await p.fill('#sc_name', 'New slab'); await p.fill('#sc_to', '2026-12-31'); await p.fill('#sc_slabs', '0,50000,1\n50000,,2');
  await p.click('[data-act=sc_save]'); await wait(p, 500);
  c = await calls(p, 'scheme_save'); ok(c.length === 1 && c[0].p_client && c[0].p_kind === 'slab' && c[0].p_slabs.length === 2 && c[0].p_slabs[1].to === null && c[0].p_slabs[0].rate === 1, 'scheme saved with parsed slabs and a client id');
  await p.click('[data-act=sc_tab][data-v=n]'); await wait(p, 200); await p.selectOption('#sc_kind', 'flat_pack'); await wait(p, 100); ok(await p.locator('#sc_ppw').isVisible() && await p.locator('#sc_slabw').isHidden(), 'form switches with the kind');
  await p.screenshot({ path: SP + '/dl_schemes.png', fullPage: true }); await noOverflow(p, 'schemes form');
  p = await open('#/schemes', 'bn'); ok(/স্কিম/.test(await text(p)), 'Bangla labels (schemes)'); await noOverflow(p, 'schemes bn');

  // ---- tinting ----
  p = await open('#/tinting');
  t = await text(p); ok(/Tinting machine/.test(t) && /#7/.test(t) && /BR-101/.test(t), 'tinting jobs listed'); await noOverflow(p, 'tinting');
  await p.selectOption('#tj_f', 'f1'); await p.fill('#tj_p', '3'); await p.fill('#tj_ch', '4200.50');
  await p.click('[data-act=tj_check]'); await wait(p, 500);
  c = await calls(p, 'tint_job_run'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_packs === 3, 'check sends a dry run');
  t = await text(p); ok(/short/.test(t) && /2,434/.test(t) && /nothing was saved/.test(t), 'check shows shortage, estimated cost and "nothing saved"');
  ok(await p.inputValue('#tj_p') === '3', 'form values kept after the check');
  await p.click('[data-act=tj_run]'); await wait(p, 600);
  c = await calls(p, 'tint_job_run'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_client && c[1].p_formula === 'f1' && c[1].p_charge === 4200.5, 'run sends a real call with a client id');
  ok(/#8/.test(await text(p)), 'new job listed');
  await p.selectOption('#tj_f', 'f1'); await p.evaluate(() => { window.__DL.err.tint_job_run = 'insufficient_stock'; }); await p.click('[data-act=tj_run]'); await wait(p, 400); ok(/Not enough stock/.test(await text(p)), 'friendly error: insufficient stock');
  await p.click('[data-act=tn_hist][data-v=cu1]'); await wait(p, 400); ok(/GR-202/.test(await text(p)), 'customer shade history shown');
  window_prompts.push({ v: 'wrong packs' }); await p.click('[data-act=tn_void] >> nth=0'); await wait(p, 400); c = await calls(p, 'tint_job_void'); ok(c.length === 1 && c[0].p_reason === 'wrong packs' && c[0].p_client, 'void sends the reason');
  await p.click('[data-act=tn_tab][data-v=f]'); await wait(p, 200); ok(/Brick red/.test(await text(p)) && /version 2/.test(await text(p)), 'formula tab');
  await p.click('[data-act=tn_tab][data-v=c]'); await wait(p, 300); ok(/3,246/.test(await text(p)), 'cost tab shows the cost for a cost-right user');
  await p.evaluate(() => { window.__DL.noCost = true; }); await p.click('[data-act=tn_tab][data-v=j]'); await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 200); await p.evaluate(() => { location.hash = '#/tinting'; }); await wait(p, 700);
  await p.click('[data-act=tn_tab][data-v=c]'); await wait(p, 200); ok(/not allowed/i.test(await text(p)), 'cost tab says not allowed for a user without the cost right');
  await p.click('[data-act=tn_tab][data-v=n]'); await wait(p, 300);
  await p.fill('#tf_code', 'br-102'); await p.fill('#tf_base', 'I-101'); await p.fill('#tf_pack', '4L'); await p.fill('#tf_lines', 'I-102, 12.5');
  await p.click('[data-act=tn_fsave]'); await wait(p, 500);
  c = await calls(p, 'tint_formula_save'); ok(c.length === 1 && c[0].p_client && c[0].p_base_item === 'i1' && c[0].p_lines[0].item === 'i2' && c[0].p_lines[0].qty === 12.5, 'formula saved with ids resolved from item codes');
  await p.click('[data-act=tn_tab][data-v=n]'); await wait(p, 200); await p.fill('#tf_code', 'x'); await p.fill('#tf_base', 'I-101'); await p.fill('#tf_lines', 'NOPE, 1'); await p.click('[data-act=tn_fsave]'); await wait(p, 400);
  ok(/item code was not found/.test(await text(p)), 'unknown item code gives a friendly error');
  await p.screenshot({ path: SP + '/dl_tinting.png', fullPage: true }); await noOverflow(p, 'tinting form');
  p = await open('#/tinting', 'bn'); ok(/টিন্টিং/.test(await text(p)), 'Bangla labels (tinting)'); await noOverflow(p, 'tinting bn');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
