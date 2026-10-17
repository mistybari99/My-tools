// CRM-F web test: web/crm_loyalty.js (#/crmloyalty), web/crm_coupons.js (#/crmcoupons) and the till helpers BOS.crmf.
// Checks: tabs; "Set this first" notes for blank settings; coupon list / new / edit / retire / uses / liability tabs and the exact RPC arguments; the money terms are not sent after the first use;
// expiry preview / apply (apply only for a person who may, reason-free note, client id); referral reject needs a reason; hooks new / toggle / due / run; statement; summary;
// settings (owner edits, only changed values are sent, with the right types; others see them disabled); the (i) info sheets and docs/integration/CRM-F_info.json agree;
// server error text; till helpers; English labels in all three modes; 360 px, no overflow; storage blocked still renders.
// Run: node crm_loyalty_test.js <abs tests/web dir>      (the two scripts are injected here; the integrator adds the real <script> tags and the ia.js lines of docs/integration/CRM-F.md)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const SHOTS = process.env.CRMF_SHOTS || '/tmp/crmf_shots';
try { fs.mkdirSync(SHOTS, { recursive: true }); } catch (e) { /* ignore */ }
const INFO_FILE = JSON.parse(fs.readFileSync(require('path').join(SP, '..', '..', 'docs', 'integration', 'CRM-F_info.json'), 'utf8'));
const base = C.baseData(SP), PORT = 8498, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); r.end(); } else { r.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.html') ? 'text/html' : f.endsWith('.css') ? 'text/css' : 'application/octet-stream' }); r.end(d); } }); }).listen(PORT);
// ---- the exact-text hooks of docs/integration/CRM-F_hooks.json, applied to scratch copies (the real files are not edited)
const HOOKFILE = JSON.parse(fs.readFileSync(require('path').join(SP, '..', '..', 'docs', 'integration', 'CRM-F_hooks.json'), 'utf8')).hooks;
const WEB = require('path').join(SP, '..', '..', 'web');
const PATCHED = {}; const hookProblems = [];
for (const h of HOOKFILE) {
  const name = h.file.replace(/^web\//, ''); let txt = PATCHED[name] || fs.readFileSync(require('path').join(WEB, name), 'utf8');
  if (require('./hooks_util.js').integrated(txt, h.find, h.replace)) { PATCHED[name] = txt; continue; }      // INTEGRATION: already in the real file
  const cnt = txt.split(h.find).length - 1;
  if (cnt !== 1) { hookProblems.push(h.id + ': the find text appears ' + cnt + ' times in ' + h.file); continue; }
  PATCHED[name] = txt.replace(h.find, () => h.replace);
}
const PORT2 = 8499;
const srv2 = require('http').createServer((q, r) => { const u = q.url.split('?')[0]; const name = u === '/' ? 'index.html' : u.slice(1); const f = require('path').join(WEB, name);
  const send = (d) => { r.writeHead(200, { 'content-type': name.endsWith('.js') ? 'text/javascript' : name.endsWith('.html') ? 'text/html' : name.endsWith('.css') ? 'text/css' : 'application/octet-stream' }); r.end(d); };
  if (PATCHED[name] !== undefined) return send(PATCHED[name]);
  fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); r.end(); } else send(d); }); }).listen(PORT2);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__CF = window.__CF || {};
 R.calls = R.calls || [];
 c.rpc = async (fn, args) => {
  if (!/^(crmf_|set_rule$|record_sale2$)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.err && R.err[fn]) { const m = R.err[fn]; delete R.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  const f = R.fn && R.fn[fn];
  if (f !== undefined) return { data: JSON.parse(JSON.stringify(f)), error: null };
  return { data: null, error: { message: 'no mock for ' + fn, code: 'P0001' } };
 }; return c; }; })();`;
const STATUS = { loyalty_on: true, gifts_on: true, point_value_taka: 1, expiry: { months: null, from: null, warn_days: null }, burn: { max_percent: null, max_points: null, step: null },
  referral: { on: false, reward: null, referred: null, min_bill: null }, voucher: { on: false, max_percent: null, max_amount: null, liability_on: false, liability_from: null }, hooks_on: false,
  can: { manage: true, apply: true, voucher: true, override: true, accounts: true } };
const COUPONS = [
  { id: 'cp-1', code: 'TEST10', name: 'test ten percent', kind: 'percent', value: 10, min_bill: 500, max_discount: null, valid_from: '2026-10-01', valid_to: '2099-12-31', max_uses: 5, per_customer_uses: 1, customer_id: null, campaign_ref: null, note: null, post_liability: false, active: true, created_at: '2026-10-01T00:00:00Z', uses: 2, discount_total: 200, scope: [] },
  { id: 'cp-2', code: 'TESTAMT', name: 'test amount', kind: 'amount', value: 150, min_bill: null, max_discount: null, valid_from: '2026-10-01', valid_to: '2099-12-31', max_uses: null, per_customer_uses: 2, customer_id: 'c-9', campaign_ref: null, note: null, post_liability: true, active: true, created_at: '2026-10-01T00:00:00Z', uses: 0, discount_total: 0, scope: [{ kind: 'location', ref: '1' }] },
  { id: 'cp-3', code: 'TESTOLD', name: 'test expired', kind: 'amount', value: 50, min_bill: null, max_discount: null, valid_from: '2020-01-01', valid_to: '2020-02-01', max_uses: null, per_customer_uses: 1, customer_id: null, campaign_ref: null, note: null, post_liability: false, active: true, created_at: '2020-01-01T00:00:00Z', uses: 0, discount_total: 0, scope: [] }];
const USES = [{ id: 1, coupon_id: 'cp-1', code: 'TEST10', sale_id: 's-1', receipt: 101, sale_date: '2026-10-10', sale_status: 'done', location_id: 1, customer_id: 'c-1', customer_name: 'test_cust_a', bill_total: 900, discount_expected: 100, discount_given: 80, mismatch: true, override_reason: null, at: '2026-10-10T05:00:00Z', by_staff: 'test' },
  { id: 2, coupon_id: 'cp-1', code: 'TEST10', sale_id: 's-2', receipt: 102, sale_date: '2026-10-11', sale_status: 'void', location_id: 1, customer_id: 'c-2', customer_name: 'test_cust_b', bill_total: 900, discount_expected: 100, discount_given: 100, mismatch: false, override_reason: 'test_reason', at: '2026-10-11T05:00:00Z', by_staff: 'test' }];
const LIAB = { on: false, from: null, liability_account: null, expense_account: null, held_total: 400, rows: [{ code: 'TESTLIAB', name: 'x', value: 100, max_uses: 5, valid_to: '2099-01-01', active: true, should_hold: 400, held: 400 }] };
const PREV = { off: false, months: 6, from: '2026-01-01', as_of: '2026-10-16', cut: '2026-04-16', customers: 2, points: 200, value_taka: 200, rule: 'Points earned on or before the cut date, minus every point spent or expired since, never more than the balance.', sample: [{ customer_id: 'c-1', name: 'test_cust_a', points: 120, balance: 140 }, { customer_id: 'c-4', name: 'test_cust_d', points: 80, balance: 80 }] };
const REFS = [{ id: 1, status: 'pending', code: 'ABCDEF', reward_points: null, referred_points: null, reason: null, created_at: '2026-10-10', first_sale_id: null, referrer_name: 'test_ref_a', referred_name: 'test_ref_b' },
  { id: 2, status: 'rewarded', code: 'ABCDEF', reward_points: 50, referred_points: 20, reason: null, created_at: '2026-10-11', first_sale_id: 's-9', referrer_name: 'test_ref_a', referred_name: 'test_ref_d' }];
const HOOKS = [{ id: 1, kind: 'birthday', name: 'test birthday bonus', offset_days: 7, festival_date: null, bonus_points: 100, coupon_id: null, coupon_code: null, active: false, note: null, grants: 0 },
  { id: 2, kind: 'festival', name: 'test festival', offset_days: 7, festival_date: '2026-10-21', bonus_points: null, coupon_id: null, coupon_code: 'TEST10', active: true, note: null, grants: 0 }];
const STMT = { customer: { id: 'c-1', name: 'test_cust_a' }, from: '2000-01-01', to: '2026-10-16', opening: 0, closing: 140, earned: 170, used: 30, expired: 0, balance_now: 140, value_taka: 140, expiring_soon: 20,
  rows: [{ id: 4, at: '2026-10-14T00:00:00Z', reason: 'adjust', delta: 20, balance: 140, receipt: null, note: 'd', by: 't' }, { id: 3, at: '2026-10-11T00:00:00Z', reason: 'redeem', delta: -30, balance: 120, receipt: 77, note: 'c', by: 't' }] };
const SUM = { from: '2026-10-01', to: '2026-10-16', points: { earned_sales: 100, earned_referral: 50, earned_bonus: 250, adjusted_up: 170, adjusted_down: 0, redeemed: 30, expired: 200, rows: 9 }, outstanding_points: 390, outstanding_value_taka: 390, members_with_points: 4, point_value_taka: 1,
  referrals: { pending: 1, rewarded: 1, rejected: 0, reversed: 0, reward_points: 50 }, coupons: { active: 3, uses: 2, discount_given: 180, mismatches: 1, overrides: 1, top: [] }, hooks: { grants: 3, points: 250 }, voucher_liability_held: 0, note: 'Outstanding points are a figure for information. They are not booked in the accounts.' };
const FN = { crmf_status: STATUS, crmf_coupon_list: COUPONS, crmf_coupon_save: { dup: false, id: 'cp-9', code: 'NEW1' }, crmf_coupon_uses_list: USES, crmf_voucher_liability_report: LIAB, crmf_voucher_liability_sync: { off: false, entries: 1, rows: [], errors: [] },
  crmf_voucher_liability_wind_down: { coupons: 1, released: 400 }, crmf_coupon_check: { ok: true, discount: 100, eligible: 1000, overridden: [], code: 'TEST10', name: 'x', kind: 'percent', value: 10 },
  crmf_coupon_redeem_after_sale: { ok: true, dup: false, use_id: 5, discount_expected: 100, discount_given: 100, mismatch: false }, crmf_burn_check: { ok: true, balance: 500, max_points: 200, max_value_taka: 200 },
  crmf_points_redeem: { dry: true, points: 150, value_taka: 150, balance: 500, balance_after: 350, burn: { ok: true } }, crmf_referral_code: { code: 'ABCDEF', active: true, new: false }, crmf_referral_apply: { ok: true, dup: false, id: 3, status: 'pending' },
  crmf_points_expiry_preview: PREV, crmf_points_expiry_soon: { off: false, days: 30, until: '2026-11-15', customers: 1, rows: [{ customer_id: 'c-2', name: 'test_cust_b', mobile: '017****02', points: 100 }] },
  crmf_points_expiry_apply: { dup: false, run_id: 3, customers: 2, points: 200, more: false }, crmf_points_expiry_runs: [{ id: 2, as_of: '2026-09-01', cut_date: '2026-03-01', months: 6, from_date: '2026-01-01', note: 'first run', at: '2026-09-01T00:00:00Z', by_staff: 't', customers: 3, points: 310 }],
  crmf_referral_list: REFS, crmf_referral_reject: { ok: true, id: 1, status: 'rejected' }, crmf_hook_list: HOOKS, crmf_hook_save: { id: 3 },
  crmf_hooks_due: { off: false, date: '2026-10-16', rows: [{ hook_id: 1, kind: 'birthday', hook_name: 'test birthday bonus', customer_id: 'c-1', customer_name: 'test_cust_a', mobile: '017****01', occasion: '2026-10-19', occasion_year: 2026, bonus_points: 100, coupon_code: null, granted: false }] },
  record_sale2: { id: 'sale-77', receipt: 5, total: 900, paid: 900, due: 0 }, crmf_hook_run: { dry: true, date: '2026-10-16', due: 1, granted: 0, points: 0 }, crmf_points_statement: STMT, crmf_loyalty_summary: SUM, set_rule: null };
const RULES = [['crm_points_expiry_months', null, null], ['crm_points_expiry_from', null, null], ['crm_points_expiry_warn_days', null, null], ['crm_burn_max_percent', null, null], ['crm_burn_max_points', null, null], ['crm_burn_step_points', null, null],
  ['crm_points_adjust_alert_over', null, null], ['crm_referral_on', null, false], ['crm_referral_reward_points', null, null], ['crm_referral_referred_points', null, null], ['crm_referral_min_bill', null, null], ['crm_voucher_on', null, false],
  ['crm_voucher_max_percent', null, null], ['crm_voucher_max_amount', null, null], ['crm_voucher_liability_on', null, false], ['crm_voucher_liability_from', null, null], ['crm_voucher_liability_account', null, null],
  ['crm_voucher_expense_account', null, null], ['crm_hooks_on', null, false]].map(([key, value, default_value]) => ({ key, value, default_value }));
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    if (!o.patched) await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/crm_loyalty\.js/.test(h) ? h : h.replace('</body>', '<script src="crm_loyalty.js"></script><script src="crm_coupons.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {});
    data.tables.rules = o.rules || RULES;
    data.tables.customers = [{ id: 'c-1', name: 'test_cust_a', mobile: '01711000001' }];
    data.tables.items = (data.tables.items || []).concat([{ id: 'i-1', code: 'T-CRMF-X', name_bn: 'test_item_x' }]);
    const cf = { calls: [], err: o.err || {}, fn: Object.assign({}, FN, o.fn || {}) };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__CF=${JSON.stringify(cf)};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}${o.blockStorage ? "try{Object.defineProperty(window,'localStorage',{get(){throw new Error('blocked')}})}catch(e){}" : ''}`);
    await p.goto(`http://localhost:${o.patched ? PORT2 : PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, m = 300) => p.waitForTimeout(m);
  const calls = (p, fn) => p.evaluate((f) => (window.__CF.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const toastText = (p) => p.evaluate(() => { const t = document.querySelector('.toast, #toast'); return t ? t.innerText : ''; });
  const setErr = (p, fn, msg) => p.evaluate(([f, m]) => { window.__CF.err[f] = m; }, [fn, msg]);

  // ================= coupons screen
  let p = await open('#/crmcoupons');
  let t = await text(p);
  ok(/Coupons & vouchers/.test(await p.locator('h1').textContent()), 'coupons title');
  ok(await p.locator('#cp_tabs .tog').count() === 3, 'three tabs');
  ok(await p.locator('#cp_off').count() === 1 && /switched OFF/.test(t), 'coupons-off notice while the switch is OFF');
  ok(await p.locator('#cp_blank').count() === 1, 'a blank maximum shows the Set-this-first note');
  ok(await p.locator('.cp-row').count() === 3, 'three coupons listed');
  ok(/TEST10/.test(t) && /10%/.test(t) && /2 uses/.test(t) && /3 left/.test(t), 'percent coupon with uses and uses left');
  ok(/Expired/.test(t), 'an old coupon is labelled expired');
  ok(/One customer/.test(t) && /Limited/.test(t), 'personal and scoped coupons are labelled');
  await noOverflow(p, 'coupon list');
  await p.screenshot({ path: SHOTS + '/crmf_coupons.png', fullPage: true });
  // new coupon
  await p.click('[data-act=cp_new]'); await wait(p);
  ok(await p.locator('#cf_code').count() === 1 && await p.locator('#cf_more').count() === 1, 'new coupon form: essentials first, more options folded');
  await p.fill('#cf_code', 'new1'); await p.fill('#cf_name', 'test new'); await p.selectOption('#cf_kind', 'percent'); await p.fill('#cf_value', '12'); await p.fill('#cf_to', '2099-12-31');
  await p.click('#cf_more summary'); await p.fill('#cf_min', '500'); await p.fill('#cf_max', '3'); await p.check('.cf_loc >> nth=0'); await p.fill('#cf_cats', 'cat_a, cat_b');
  await p.click('[data-act=cp_savego]'); await wait(p, 500);
  let c = await calls(p, 'crmf_coupon_save');
  ok(c.length === 1 && c[0].p_id === null && c[0].p.code === 'NEW1' && c[0].p.kind === 'percent' && c[0].p.value === 12 && c[0].p.min_bill === 500 && c[0].p.max_uses === 3 && c[0].p.valid_to === '2099-12-31', 'save arguments: code in capitals, kind, value, minimum, uses, dates');
  ok(c[0].p.scope && c[0].p.scope.locations.length === 1 && c[0].p.scope.categories.join() === 'cat_a,cat_b', 'scope: one place and two categories');
  ok(/^[0-9a-f-]{36}$/.test(c[0].p_client || ''), 'a client id is sent (a repeat cannot create a second coupon)');
  ok(c[0].p.post_liability === false, 'liability is not marked unless asked');
  // server refusal text
  await p.click('[data-act=cp_new]'); await wait(p);
  await p.fill('#cf_code', 'bad1'); await p.fill('#cf_name', 'x'); await p.fill('#cf_value', '12'); await p.fill('#cf_to', '2099-12-31');
  await setErr(p, 'crmf_coupon_save', 'max_percent_not_set');
  await p.click('[data-act=cp_savego]'); await wait(p, 400);
  ok(/largest percent/.test(await toastText(p)), 'plain English for a blank maximum');
  await p.click('[data-act=closesheet]'); await wait(p);
  // edit a used coupon: money terms are not sent
  await p.click('.cp-row[data-code=TEST10] [data-act=cp_edit]'); await wait(p);
  await p.fill('#cf_name', 'test ten renamed'); await p.click('[data-act=cp_savego]'); await wait(p, 500);
  c = await calls(p, 'crmf_coupon_save'); const last = c[c.length - 1];
  ok(last.p_id === 'cp-1' && last.p.name === 'test ten renamed' && !('value' in last.p) && !('min_bill' in last.p) && !('max_discount' in last.p) && !('kind' in last.p) && !('scope' in last.p), 'a used coupon: only the free fields are sent');
  // retire
  await p.click('.cp-row[data-code=TEST10] [data-act=cp_active]'); await wait(p, 400);
  c = await calls(p, 'crmf_coupon_save');
  ok(c[c.length - 1].p_id === 'cp-1' && c[c.length - 1].p.active === false, 'retire sends active=false');
  // uses tab
  await p.click('[data-act=cp_tab][data-v=uses]'); await wait(p, 400);
  t = await text(p);
  ok(/Redemption log/.test(t) && /Different from the coupon/.test(t) && /Accepted with a reason/.test(t) && /void/.test(t), 'uses tab: mismatch, override and void marked');
  await p.selectOption('#cp_f', 'cp-1'); await wait(p, 400);
  c = await calls(p, 'crmf_coupon_uses_list'); ok(c[c.length - 1].p_coupon === 'cp-1', 'the filter asks the server for one coupon');
  // liability tab
  await p.click('[data-act=cp_tab][data-v=liab]'); await wait(p, 400);
  t = await text(p);
  ok(await p.locator('#lb_off').count() === 1 && /Nothing is booked/.test(t), 'liability OFF notice');
  await p.click('[data-act=lb_sync]'); await wait(p, 400);
  ok((await calls(p, 'crmf_voucher_liability_sync')).length === 1, 'sync calls the named function');
  await p.click('[data-act=lb_wind]'); await wait(p); await p.fill('#wd_why', 'x'); await p.click('[data-act=lb_windgo]'); await wait(p, 300);
  ok((await calls(p, 'crmf_voucher_liability_wind_down')).length === 0 && /reason/i.test(await toastText(p)), 'wind down needs a reason of 3 letters');
  await p.fill('#wd_why', 'season ended'); await p.click('[data-act=lb_windgo]'); await wait(p, 400);
  c = await calls(p, 'crmf_voucher_liability_wind_down'); ok(c.length === 1 && c[0].p_reason === 'season ended', 'wind down call carries the reason');

  // ================= till helpers
  p = await open('#/crmcoupons');
  const h1 = await p.evaluate(async () => { const B = window.BOS; await B.crmf.couponCheck('test10', 1, 'c-1', [{ item_id: 'i-1', qty: 1, price: 200 }], 1000, null); await B.crmf.couponRedeem('TEST10', 's-1', 'because', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc');
    await B.crmf.burnCheck('c-1', 150, 1000); await B.crmf.redeemPoints('c-1', 150, 1000, 'n', null, true, null); await B.crmf.referralCode('c-1'); await B.crmf.referralApply('c-2', 'ABCDEF', null); return Object.keys(window.BOS.crmf).sort().join(','); });
  ok(/couponCheck/.test(h1) && /couponRedeem/.test(h1) && /redeemPoints/.test(h1) && /referralApply/.test(h1), 'till helpers are exported on BOS.crmf');
  c = await calls(p, 'crmf_coupon_check'); ok(c.length === 1 && c[0].p_code === 'test10' && c[0].p_loc === 1 && c[0].p_customer === 'c-1' && c[0].p_subtotal === 1000 && c[0].p_lines[0].item_id === 'i-1', 'couponCheck arguments');
  c = await calls(p, 'crmf_coupon_redeem_after_sale'); ok(c.length === 1 && c[0].p_sale === 's-1' && c[0].p_override === 'because' && c[0].p_client === 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'couponRedeem arguments');
  c = await calls(p, 'crmf_points_redeem'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_bill === 1000 && c[0].p_points === 150 && /^[0-9a-f-]{36}$/.test(c[0].p_client), 'redeemPoints arguments (a client id is made when none is given)');
  c = await calls(p, 'crmf_referral_apply'); ok(c.length === 1 && c[0].p_referred === 'c-2' && c[0].p_code === 'ABCDEF', 'referralApply arguments');
  await setErr(p, 'crmf_coupon_check', 'vouchers_off');
  const eMsg = await p.evaluate(async () => { try { await window.BOS.crmf.couponCheck('X', 1, null, [], 10, null); return 'no error'; } catch (e) { return e.message; } });
  ok(/switched OFF/.test(eMsg), 'a till helper raises plain English (' + eMsg + ')');

  // ================= loyalty screen
  p = await open('#/crmloyalty');
  t = await text(p);
  ok(/Loyalty extras/.test(await p.locator('h1').textContent()), 'loyalty title');
  ok(await p.locator('#ly_tabs .tog').count() === 6, 'six tabs');
  ok(await p.locator('#ex_off').count() === 1 && /Set this first/.test(t), 'expiry: blank months / date show Set this first');
  ok(await p.locator('[data-act=ex_apply]').isDisabled(), 'apply is disabled while the settings are blank');
  await p.click('[data-act=ex_prev]'); await wait(p, 400);
  t = await text(p);
  ok(await p.locator('#ex_prev').count() === 1 && /Customers: 2/.test(t) && /Points: 200/.test(t) && /test_cust_a/.test(t), 'preview shows customers, points and a sample');
  ok(/first run/.test(t) && /Past runs/.test(t), 'past runs are listed');
  await noOverflow(p, 'expiry');
  // apply is only for a person who may
  p = await open('#/crmloyalty', { fn: { crmf_status: Object.assign({}, STATUS, { expiry: { months: 6, from: '2026-01-01', warn_days: 30 }, can: { manage: true, apply: false, voucher: false, override: false, accounts: false } }) } });
  ok(await p.locator('[data-act=ex_apply]').count() === 0, 'a person who may only preview does not see Apply');
  ok(/test_cust_b/.test(await text(p)) && /About to lose points/.test(await text(p)), 'the warning list shows when a warn period is set');
  p = await open('#/crmloyalty', { fn: { crmf_status: Object.assign({}, STATUS, { expiry: { months: 6, from: '2026-01-01', warn_days: null } }) } });
  ok(!(await p.locator('[data-act=ex_apply]').isDisabled()), 'apply is enabled when months and date are set');
  await p.click('[data-act=ex_apply]'); await wait(p); await p.fill('#ex_note', 'test note'); await p.click('[data-act=ex_applygo]'); await wait(p, 500);
  c = await calls(p, 'crmf_points_expiry_apply'); ok(c.length === 1 && c[0].p_note === 'test note' && /^[0-9a-f-]{36}$/.test(c[0].p_client), 'apply sends a client id and the note');
  ok(/Expiry applied/.test(await toastText(p)), 'apply toast');
  // referral
  await p.click('[data-act=ly_tab][data-v=referral]'); await wait(p, 400);
  t = await text(p);
  ok(await p.locator('#rf_off').count() === 1 && /test_ref_b/.test(t) && /Rewarded/.test(t) && /Pending/.test(t), 'referral tab: OFF note, pending and rewarded rows');
  await p.click('[data-act=rf_reject]'); await wait(p); await p.fill('#rf_why', 'x'); await p.click('[data-act=rf_rejectgo]'); await wait(p, 300);
  ok((await calls(p, 'crmf_referral_reject')).length === 0, 'reject needs a reason');
  await p.fill('#rf_why', 'not a real friend'); await p.click('[data-act=rf_rejectgo]'); await wait(p, 400);
  c = await calls(p, 'crmf_referral_reject'); ok(c.length === 1 && c[0].p_id === 1 && c[0].p_reason === 'not a real friend', 'reject arguments');
  // hooks
  await p.click('[data-act=ly_tab][data-v=hooks]'); await wait(p, 400);
  t = await text(p);
  ok(await p.locator('#hk_off').count() === 1 && /test birthday bonus/.test(t) && /Festival/.test(t), 'hooks tab: OFF note and the rules');
  await p.click('[data-act=hk_toggle][data-v="1"]'); await wait(p, 400);
  c = await calls(p, 'crmf_hook_save'); ok(c.length === 1 && c[0].p_id === 1 && c[0].p.active === true, 'toggle switches a hook on');
  await p.click('[data-act=hk_new]'); await wait(p); await p.fill('#hk_name', 'test anniversary'); await p.selectOption('#hk_kind', 'anniversary'); await p.fill('#hk_bonus', '50'); await p.click('[data-act=hk_newgo]'); await wait(p, 400);
  c = await calls(p, 'crmf_hook_save'); ok(c.length === 2 && c[1].p_id === null && c[1].p.kind === 'anniversary' && c[1].p.bonus_points === 50 && c[1].p.offset_days === 7 && !('festival_date' in c[1].p), 'new hook arguments');
  await p.click('[data-act=hk_due]'); await wait(p, 400);
  ok(/Who is due/.test(await text(p)) && /test_cust_a/.test(await text(p)), 'the due list shows');
  await p.click('[data-act=hk_run][data-v=dry]'); await wait(p, 400);
  c = await calls(p, 'crmf_hook_run'); ok(c.length === 1 && c[0].p_dry === true, 'preview run is a dry run');
  await p.click('[data-act=hk_run][data-v=go]'); await wait(p, 400);
  c = await calls(p, 'crmf_hook_run'); ok(c.length === 2 && c[1].p_dry === false, 'the real run is not dry');
  // statement
  await p.click('[data-act=ly_tab][data-v=stmt]'); await wait(p, 300);
  await p.fill('#st_mobile', '01711000001'); await p.click('[data-act=st_go]'); await wait(p, 500);
  t = await text(p);
  ok(/test_cust_a/.test(t) && /Closing 140/.test(t) && /-30/.test(t), 'statement shows the customer, the closing balance and a negative line');
  c = await calls(p, 'crmf_points_statement'); ok(c.length === 1 && c[0].p_customer === 'c-1', 'statement call');
  await p.fill('#st_mobile', '01999999999'); await p.click('[data-act=st_go]'); await wait(p, 400);
  ok(/Customer not found/.test(await toastText(p)), 'unknown customer');
  // summary
  await p.click('[data-act=ly_tab][data-v=sum]'); await wait(p, 300);
  await p.fill('#sm_from', '2026-10-01'); await p.fill('#sm_to', '2026-10-16'); await p.click('[data-act=sm_go]'); await wait(p, 500);
  t = await text(p);
  ok(await p.locator('#sm_body').count() === 1 && /Points outstanding/.test(t) && /not booked/.test(t), 'summary shows outstanding points and says they are not booked');
  c = await calls(p, 'crmf_loyalty_summary'); ok(c.length === 1 && c[0].p_from === '2026-10-01' && c[0].p_to === '2026-10-16', 'summary dates');
  // settings
  await p.click('[data-act=ly_tab][data-v=set]'); await wait(p, 500);
  ok(await p.locator('.set-row').count() === 19, 'nineteen settings listed');
  ok(await p.locator('.set-row .muted:text("Set this first")').count() >= 10, 'blank settings say Set this first');
  await p.fill('#sv_crm_points_expiry_months', '6'); await p.fill('#sv_crm_points_expiry_from', '2026-12-01'); await p.check('#sv_crm_hooks_on');
  await p.click('[data-act=sv_save]'); await wait(p, 500);
  c = await calls(p, 'set_rule');
  const byKey = {}; c.forEach((x) => { byKey[x.p_key] = x.p_value; });
  ok(c.length === 3 && byKey.crm_points_expiry_months === 6 && byKey.crm_points_expiry_from === '2026-12-01' && byKey.crm_hooks_on === true, 'only the changed settings are sent, with number / text / boolean types (' + JSON.stringify(byKey) + ')');
  await p.fill('#sv_crm_points_expiry_from', '12/01/2026'); await p.click('[data-act=sv_save]'); await wait(p, 300);
  ok(/date/i.test(await toastText(p)) && (await calls(p, 'set_rule')).length === 3, 'a bad date is refused before anything is saved');
  // info sheets
  const keys = await p.evaluate(() => window.BOS.crmf.settingKeys);
  const infoJs = await p.evaluate(() => window.BOS.crmf.info);
  const fromFile = {}; INFO_FILE.entries.forEach((e) => { fromFile[e.key] = e; });
  ok(JSON.stringify(infoJs) === JSON.stringify(fromFile), 'the (i) texts in web/crm_loyalty.js equal docs/integration/CRM-F_info.json');
  ok(keys.length === 19 && keys.every((k) => fromFile[k]), 'every setting has an info entry');
  ok(INFO_FILE.entries.every((e) => ['title', 'what_it_does', 'why_it_matters', 'default', 'what_changes_if_switched', 'who_can_change'].every((f) => typeof e[f] === 'string' && e[f].length > 2 && !/[^\x20-\x7e]/.test(e[f]))), 'every info entry has the six plain-English fields, ASCII only');
  ok(['points_expiry', 'burn_rules', 'referral', 'coupons', 'coupon_override', 'points_statement', 'loyalty_summary'].every((k) => fromFile[k]), 'feature entries exist');
  await p.click('.set-row[data-key=crm_voucher_liability_on] [data-act=ly_info]'); await wait(p, 300);
  t = await text(p);
  ok(await p.locator('#ly_info').count() === 1 && /What it does/.test(t) && /Why it matters/.test(t) && /Default/.test(t) && /What changes if you switch it/.test(t) && /Who can change it/.test(t) && /Book coupon liability/.test(t), 'info sheet shows the five parts');
  await p.click('#ly_info [data-act=closesheet]'); await wait(p);
  // non-owner: settings are read only
  p = await open('#/crmloyalty', { owner: false });
  await p.click('[data-act=ly_tab][data-v=set]'); await wait(p, 500);
  ok(await p.locator('[data-act=sv_save]').count() === 0 && await p.locator('#sv_crm_voucher_max_percent').isDisabled() && /Only the owner/.test(await text(p)), 'a non-owner cannot edit settings');

  // ================= languages, width, storage blocked
  for (const lang of ['en', 'bn', 'mix']) {
    p = await open('#/crmloyalty', { lang });
    ok(/Loyalty extras/.test(await p.locator('h1').textContent()) && /Expiry/.test(await text(p)), 'English labels in mode ' + lang);
    await noOverflow(p, 'loyalty ' + lang);
    p = await open('#/crmcoupons', { lang });
    ok(/Coupons & vouchers/.test(await p.locator('h1').textContent()), 'coupon title in mode ' + lang);
    await noOverflow(p, 'coupons ' + lang);
  }
  p = await open('#/crmloyalty', { blockStorage: true });
  ok(/Loyalty extras/.test(await p.locator('h1').textContent()), 'renders with storage blocked');
  p = await open('#/crmloyalty');
  await p.screenshot({ path: SHOTS + '/crmf_loyalty.png', fullPage: true });
  ok(await p.evaluate(() => !!(window.BOS_PAGES && window.BOS_PAGES.crmloyalty && window.BOS_PAGES.crmcoupons)), 'both routes are registered as pages');
  
  // ================= the hooks on scratch copies of the real files
  ok(hookProblems.length === 0, 'every hook find text appears exactly once: ' + hookProblems.join('; '));
  for (const [name, txt] of Object.entries(PATCHED)) { if (name.endsWith('.js')) { let good = true; try { new Function(txt); } catch (e) { good = false; log('syntax', name, e.message); } ok(good, 'patched ' + name + ' still parses'); } }
  ok(/crm_loyalty\.js/.test(PATCHED['index.html']) && /crm_coupons\.js/.test(PATCHED['index.html']) && PATCHED['index.html'].indexOf('customers.js') < PATCHED['index.html'].indexOf('crm_loyalty.js'), 'index.html loads the two scripts after customers.js');
  ok((PATCHED['customers.js'].match(/crmf_points_redeem/g) || []).length === 2 && /crmf_points_adjust/.test(PATCHED['customers.js']) && !/rpc\('customer_points_(redeem|adjust)'/.test(PATCHED['customers.js']), 'customers.js calls the checked redeem and adjust');
  // real registry: the screens open through ia.js without the injected scripts
  p = await open('#/crmloyalty', { patched: true });
  ok(/Loyalty extras/.test(await p.locator('h1').textContent()), 'patched ia.js + index.html: the loyalty screen opens through the registry');
  p = await open('#/crmcoupons', { patched: true });
  ok(/Coupons & vouchers/.test(await p.locator('h1').textContent()), 'patched registry: the coupon screen opens');
  // the till flow on the patched POS: the coupon box, the check fills the discount, the sale is sent, then the use is recorded
  p = await open('#/pos', { patched: true, fn: { crmf_status: Object.assign({}, STATUS, { voucher: Object.assign({}, STATUS.voucher, { on: true }) }), crmf_coupon_check: { ok: true, discount: 90, eligible: 1000, overridden: [] } } });
  const hasItem = await p.locator('.pos-item').count();
  if (hasItem === 0) { log('NOTE: the base data has no POS item, the till flow is not run'); ok(false, 'till flow needs an item in the base data'); }
  else {
    const pc = await p.evaluate(() => (window.__DATA.tables.items.find((i) => i.unit === 'pc' && i.sell_price > 100) || {}).id);
    await p.click(`.pos-item[data-v="${pc}"]`); await wait(p, 300);
    await p.click('[data-act=pos_cart]'); await wait(p, 600);
    ok(await p.locator('#crmf_cp').count() === 1, 'the coupon box shows in the cart sheet when coupons are ON');
    await p.fill('#crmf_cp', 'test10'); await p.click('[data-act=crmf_cp_check]'); await wait(p, 500);
    c = await calls(p, 'crmf_coupon_check');
    ok(c.length === 1 && c[0].p_code === 'TEST10' && c[0].p_loc > 0 && Array.isArray(c[0].p_lines) && c[0].p_subtotal > 0, 'check call carries the code, place, lines and subtotal');
    ok(await p.inputValue('#cart_disc') === '90', 'the normal discount box is filled with the coupon discount');
    ok(/Coupon accepted/.test(await text(p)), 'the coupon answer is shown');
    await p.click('#cart_ok'); await wait(p, 1200);
    c = await calls(p, 'crmf_coupon_redeem_after_sale');
    ok(c.length === 1 && c[0].p_code === 'TEST10' && c[0].p_sale === 'sale-77' && /^[0-9a-f-]{36}$/.test(c[0].p_client), 'after the sale the use is recorded against the sale id');
    c = await calls(p, 'record_sale2'); ok(c.length === 1 && !('p_coupon' in c[0]) && !Object.keys(c[0]).some((k) => /coupon/i.test(k)), 'record_sale2 is called with exactly the old arguments (no coupon field)');
  }
  // coupons OFF: no box
  p = await open('#/pos', { patched: true });
  if (await p.locator('.pos-item').count()) { const pc2 = await p.evaluate(() => (window.__DATA.tables.items.find((i) => i.unit === 'pc' && i.sell_price > 100) || {}).id); await p.click(`.pos-item[data-v="${pc2}"]`); await wait(p, 300); await p.click('[data-act=pos_cart]'); await wait(p, 600); ok(await p.locator('#crmf_cp').count() === 0, 'coupons OFF: no coupon box, the POS is as before'); }
  await br.close(); srv.close(); srv2.close();
  log(errors.length ? 'ERRORS: ' + errors.slice(0, 6).join(' | ') : 'no console errors');
  log(`RESULT ${n - bad} pass, ${bad + errors.length} fail (${n} asserts)`);
  process.exit(bad || errors.length ? 1 : 0);
} catch (e) { console.log('CRASH', e && e.stack || e); process.exit(2); } })();
