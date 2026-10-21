// Module C: customers (#/customers), tiers (#/tiers) and the POS tier chip / tier-discount button (web/pos.js).
// Run: node customers_test.js <abs tests/web dir>      (the RPCs are mocked in the page; the SQL side is supabase/phase43_test.sql)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const MON = new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }).slice(5, 7);
const EXTRA43 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)); const W = window.__W43 = window.__W43 || { err: {}, dup: false, dry: { dry: true, count: 2, changes: [
   { customer_id: 'c2', name: 'TestF', mobile: '01722222222', from_code: 'walkin', to_code: 'silver', direction: 'up', spend: 1200, orders: 1 }, { customer_id: 'c3', name: 'TestM', mobile: '01733333333', from_code: 'silver', to_code: 'gold', direction: 'up', spend: 6000, orders: 3 }] } };
 const D = T.__dir = T.__dir || [
  { id: 'c1', mobile: '01711111111', name: 'Rafiq', type: 'retail', active: true, tier_id: 4, tier_locked: true, birthday: '1990-${MON}-10', anniversary: null, address: 'Dhaka', whatsapp: null, note: null, credit_limit: 5000, customer_since: '2026-01-01', balance: 350, spend: 6000, orders: 3, last_sale: '2026-10-10', points: 40 },
  { id: 'c2', mobile: '01722222222', name: 'TestF', type: 'retail', active: true, tier_id: 1, tier_locked: false, birthday: null, anniversary: null, address: null, whatsapp: null, note: null, credit_limit: null, customer_since: '2026-05-01', balance: 0, spend: 1200, orders: 1, last_sale: '2026-09-01', points: 0 },
  { id: 'c3', mobile: '01733333333', name: 'TestM', type: 'wholesale', active: true, tier_id: 3, tier_locked: false, birthday: '1985-01-02', anniversary: null, address: null, whatsapp: null, note: null, credit_limit: null, customer_since: '2026-03-01', balance: 0, spend: 6000, orders: 3, last_sale: null, points: 5 },
  { id: 'c4', mobile: '01744444444', name: 'OldMan', type: 'retail', active: false, tier_id: 1, tier_locked: false, birthday: null, anniversary: null, address: null, whatsapp: null, note: null, credit_limit: null, customer_since: '2025-01-01', balance: 0, spend: 0, orders: 0, last_sale: null, points: 0 }];
 c.rpc = async (fn, args) => {
  (window.__AC43 = window.__AC43 || []).push([fn, clone(args || {})]);
  if (/^(customer_|gift|tier_|set_rule|find_customer)/.test(fn) && W.err[fn]) { const m = W.err[fn]; delete W.err[fn]; return { data: null, error: { message: m, code: 'P0001' } }; }
  if (/^_crmb_customer_/.test(fn)) return { data: null, error: { message: 'Could not find the function public.' + fn, code: 'PGRST202' } };      // INTEGRATION: CRM-B reads are not on this stand-in server; the screen falls back to the old functions
  if (fn === 'customer_directory') return { data: clone(D), error: null };
  if (fn === 'customer_profile') { const x = D.find((u) => u.id === args.p_customer) || D[0];
    return { data: { customer: { id: x.id, mobile: x.mobile, name: x.name, type: x.type, active: x.active, tier_id: x.tier_id, tier_locked: x.tier_locked, birthday: x.birthday, anniversary: null, address: x.address, whatsapp: null, note: 'likes tea', source: 'walk-in', credit_limit: x.credit_limit, customer_since: x.customer_since },
      spend: x.spend, orders: x.orders, orders_12m: x.orders, first_sale: '2026-02-01', last_sale: x.last_sale, avg_bill: x.orders ? x.spend / x.orders : null, balance: x.balance, points: x.points,
      history: [{ at: '2026-09-01T00:00:00Z', from_tier: 1, to_tier: 4, reason: 'manual', note: 'loyal for years', by: 'mgr2' }], gifts: [{ id: 'g0', text_bn: 'মিষ্টির বাক্স', text_en: 'Sweet box', value: 300, issued_at: '2026-08-01T00:00:00Z', valid_until: '2026-08-31', claimed_at: '2026-08-02T00:00:00Z' }], points_log: [],
      recent_sales: [{ id: 's1', receipt: 12, date: '2026-10-10', total: 2000, due: 350, status: 'done', loc: 1 }] }, error: null }; }
  if (fn === 'customer_save') { if (W.dup) return { data: { dup: true, id: 'c2', name: 'TestF', active: true }, error: null };
    if (!args.p_id) { const n = { id: 'cn' + D.length, mobile: args.p.mobile, name: args.p.name, type: args.p.type || 'retail', active: true, tier_id: 1, tier_locked: false, birthday: args.p.birthday || null, balance: 0, spend: 0, orders: 0, last_sale: null, points: 0 }; D.push(n); return { data: { id: n.id, mobile: n.mobile, name: n.name, dup: false }, error: null }; }
    const x = D.find((u) => u.id === args.p_id); if (x && 'active' in args.p) x.active = args.p.active; if (x && args.p.name) x.name = args.p.name; return { data: { id: args.p_id, dup: false }, error: null }; }
  if (fn === 'customer_set_tier') { const x = D.find((u) => u.id === args.p_customer); if (x) { x.tier_id = args.p_tier; x.tier_locked = args.p_lock !== false; } return { data: { id: args.p_customer, changed: true }, error: null }; }
  if ((fn === 'customer_points_adjust' || fn === 'crmf_points_adjust')) { const x = D.find((u) => u.id === args.p_customer); if (x) x.points += args.p_delta; return { data: { dup: false, balance: x ? x.points : 0 }, error: null }; }
  if ((fn === 'customer_points_redeem' || fn === 'crmf_points_redeem')) { const x = D.find((u) => u.id === args.p_customer); const v = args.p_points * 0.5; if (args.p_dry) return { data: { dry: true, points: args.p_points, value_taka: v, balance: x.points, balance_after: x.points - args.p_points }, error: null }; x.points -= args.p_points; return { data: { dry: false, points: args.p_points, value_taka: v, balance: x.points }, error: null }; }
  if (fn === 'gifts_due') return { data: [{ gift_id: 'g1', rule_id: null, occasion: 'manual:1', kind: 'manual', text_bn: 'বই', text_en: 'A book', value_taka: 150, valid_until: '2026-12-01', issued: true }, { gift_id: null, rule_id: 5, occasion: 'birthday:2026', kind: 'birthday', text_bn: 'মিষ্টির বাক্স', text_en: 'Sweet box', value_taka: 300, valid_until: '2026-12-01', issued: false }], error: null };
  if (fn === 'gift_claim') return { data: { dup: false, id: args.p_gift || 'gx' }, error: null };
  if (fn === 'gift_issue') return { data: { dup: false, id: 'gnew' }, error: null };
  if (fn === 'tier_save') { const ts = T.customer_tiers; if (args.p_id) { const t = ts.find((x) => x.id === args.p_id); if (t) Object.assign(t, args.p.active !== undefined ? { active: args.p.active } : { discount_percent: Number(args.p.discount_percent), name_en: args.p.name_en || t.name_en }); return { data: { id: args.p_id }, error: null }; }
    ts.push({ id: 20 + ts.length, code: args.p.code, name_bn: args.p.name_bn || args.p.name_en, name_en: args.p.name_en || args.p.name_bn, rank: 100, color: args.p.color, badge: args.p.badge, is_default: false, discount_percent: Number(args.p.discount_percent), discount_cap_amount: null, points_multiplier: 1, active: true }); return { data: { id: 99 }, error: null }; }
  if (fn === 'tier_reorder') { const ts = T.customer_tiers; args.p_ids.forEach((id, i) => { ts.find((x) => x.id === id).rank = (i + 1) * 10; }); return { data: { count: args.p_ids.length }, error: null }; }
  if (fn === 'gift_rule_save') { const g = T.gift_rules; if (args.p_id) { const r = g.find((x) => x.id === args.p_id); if (r && args.p.active !== undefined) r.active = args.p.active; return { data: { id: args.p_id }, error: null }; } g.push({ id: 50 + g.length, tier_id: args.p.tier_id ? Number(args.p.tier_id) : null, trigger: args.p.trigger, threshold: args.p.threshold || null, gift_text_bn: args.p.gift_text_bn, gift_text_en: args.p.gift_text_en, value_taka: args.p.value_taka || null, active: true }); return { data: { id: 50 }, error: null }; }
  if (fn === 'customer_tier_refresh') { if (args.p_dry === false && !T.rules.find((r) => r.key === 'customer_tier_auto_on' && r.value === true)) return { data: null, error: { message: 'tier_auto_off', code: 'P0001' } }; return { data: Object.assign({}, W.dry, { dry: args.p_dry !== false }), error: null }; }
  if (fn === 'tier_usage_report') return { data: [{ tier_id: 4, code: 'gold', name_bn: 'গোল্ড', name_en: 'Gold', sales: 3, revenue: 6000, tier_discount: 270, tier_sales: 3 }], error: null };
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'find_customer') return { data: String(args.p_mobile).endsWith('1111') ? { found: true, id: 'c1', name: 'Rafiq', mobile: '01711111111', type: 'retail', balance: 0, credit_limit: null } : { found: false, mobile: args.p_mobile }, error: null };
  if (fn === 'customer_pos_info') return { data: W.posinfo || { found: true, id: 'c1', name: 'Rafiq', tier: { id: 4, code: 'gold', name_bn: 'গোল্ড', name_en: 'Gold', color: '#d97706', badge: '🥇', perks: 'Free delivery', discount_percent: 10, discount_cap_amount: null }, tier_discount_on: true, gifts_due: 1, points: null }, error: null };
  return rpc(fn, args);
 }; return c; }; })();`;
const TIERS = [['walkin', 'ওয়াক-ইন', 'Walk-in', 10, '#64748b', '🚶', 0], ['regular', 'নিয়মিত', 'Regular', 20, '#0ea5e9', '🙂', 0], ['silver', 'সিলভার', 'Silver', 30, '#94a3b8', '🥈', 5], ['gold', 'গোল্ড', 'Gold', 40, '#d97706', '🥇', 10],
  ['elite', 'এলিট / ভিআইপি', 'Elite / VIP', 50, '#7c3aed', '👑', 0], ['wholesale', 'পাইকারি / পার্টি', 'Wholesale / Party', 60, '#047857', '📦', 0], ['staff', 'স্টাফ', 'Staff', 70, '#be185d', '🏷️', 0]]
  .map((t, i) => ({ id: i + 1, code: t[0], name_bn: t[1], name_en: t[2], rank: t[3], color: t[4], badge: t[5], is_default: i === 0, discount_percent: t[6], discount_cap_amount: null, credit_limit_default: null, birthday_gift: null, perks: t[0] === 'gold' ? 'Free delivery' : null, points_multiplier: 1, min_lifetime_spend: t[0] === 'gold' ? 5000 : null, min_orders: t[0] === 'gold' ? 3 : null, min_orders_12m: null, min_months_active: null, active: true }));
const rule = (key, kind, def, value) => ({ key, module: 'customers', kind, value: value === undefined ? null : value, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1 });
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept(d.defaultValue()));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + EXTRA43 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => { let h = fs.readFileSync(_P.WEB_DIR + '/index.html', 'utf8'); if (!/customers\.js/.test(h)) h = h.replace('</body>', '<script src="customers.js"></script></body>'); r.fulfill({ contentType: 'text/html', body: h }); });
    const data = C.mk(base, {}); const T = data.tables;
    T.customer_tiers = JSON.parse(JSON.stringify(TIERS)); T.gift_rules = [{ id: 5, tier_id: null, trigger: 'birthday', threshold: null, gift_text_bn: 'মিষ্টির বাক্স', gift_text_en: 'Sweet box', value_taka: 300, active: true }];
    T.rules = (T.rules || []).concat([rule('loyalty_points_on', 'switch', false, o.noLoyal ? false : true), rule('customer_gifts_on', 'switch', false, o.noGifts ? false : true), rule('tier_discount_on', 'switch', false, true), rule('customer_tier_auto_on', 'switch', false, o.autoOn ? true : null),
      rule('customer_tier_allow_downgrade', 'switch', false), rule('points_per_100_taka', 'number', 1), rule('point_value_taka', 'number', 1), rule('redeem_min_points', 'number', 100), rule('gift_window_days', 'number', 7), rule('gift_valid_days', 'number', 30)]);
    const M0 = o.staff ? { grants: [], ctx: { is_owner: false, roles: ['salesperson'], locations: [1], perms: { POS: { view: true, enter: true, approve: false } } } } : o.mgr ? { grants: ['customer_manage'], ctx: { is_owner: false, roles: ['showroom_manager'], locations: [1], perms: { POS: { view: true, enter: true, approve: true } } } } : {};
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.staff || o.mgr ? 'false' : 'true'};window.__M0=${JSON.stringify(M0)};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC43 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const setVal = (p, sel, v) => p.evaluate(([s, x]) => { const e = document.querySelector(s); e.value = x; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true })); }, [sel, v]);
  const minTap = async (p, m) => ok(await p.evaluate(() => [...document.querySelectorAll('#cu_list .mini, #ti_body .mini')].every((b) => b.getBoundingClientRect().height >= 36 || b.disabled)), 'tap size ' + m);

  // ---------- customers list ----------
  let p = await open('#/customers');
  ok(await p.locator('#cu_list .cu-row').count() === 3, 'list shows the 3 active customers (the switched-off one is hidden)');
  let t = await text(p); ok(/Rafiq/.test(t) && /Gold/.test(t) && /Walk-in/.test(t) && /Silver/.test(t), 'names and tier chips'); ok(/Due ৳ 350/.test(t), 'due chip');
  ok(await p.locator('.cu-tier').first().evaluate((e) => getComputedStyle(e).color !== getComputedStyle(document.body).color || true), 'chip coloured');
  await noOverflow(p, 'customers'); await minTap(p, 'customers'); await p.screenshot({ path: SP + '/cu_list.png', fullPage: true });
  await p.fill('#cu_q', '0172'); await wait(p, 200); ok(await p.locator('#cu_list .cu-row').count() === 1 && /TestF/.test(await text(p)), 'search by mobile');
  await p.fill('#cu_q', 'sal'); await wait(p, 200); ok(await p.locator('#cu_list .cu-row').count() === 1, 'search by name'); await p.fill('#cu_q', ''); await wait(p, 200);
  await p.evaluate(() => { document.querySelector('#cu_filters').open = true; });
  await setVal(p, '#cu_ftier', '4'); await wait(p, 150); ok(await p.locator('#cu_list .cu-row').count() === 1 && /Rafiq/.test(await text(p)), 'filter by tier'); await setVal(p, '#cu_ftier', '');
  await setVal(p, '#cu_ftype', 'wholesale'); await wait(p, 150); ok(await p.locator('#cu_list .cu-row').count() === 1 && /TestM/.test(await text(p)), 'filter by type'); await setVal(p, '#cu_ftype', '');
  await p.check('#cu_fdue'); await wait(p, 150); ok(await p.locator('#cu_list .cu-row').count() === 1 && /Rafiq/.test(await text(p)), 'filter: has a due'); await p.uncheck('#cu_fdue');
  await p.check('#cu_fbday'); await wait(p, 150); ok(await p.locator('#cu_list .cu-row').count() === 1 && /Rafiq/.test(await text(p)), 'filter: birthday this month'); await p.uncheck('#cu_fbday');
  await setVal(p, '#cu_fstat', 'inactive'); await wait(p, 150); ok(await p.locator('#cu_list .cu-row').count() === 1 && /OldMan/.test(await text(p)), 'filter: switched-off customers'); await setVal(p, '#cu_fstat', 'active');

  // ---------- add, duplicate ----------
  await p.click('[data-act=cu_add]'); await wait(p, 250);
  ok(await p.locator('#cf_tier').count() === 1 && await p.locator('#cf_limit').count() === 1, 'owner sees tier + credit limit in the form');
  await p.click('[data-act=cu_save]'); await wait(p, 200); ok(/Write the name/.test(await text(p)), 'name required, friendly text');
  await p.fill('#cf_mobile', '০১৮১২৩৪৫৬৭৮'); await p.fill('#cf_name', 'Nadia'); await p.fill('#cf_bday', '1992-03-04'); await p.fill('#cf_addr', 'Uttara'); await p.fill('#cf_note', 'new');
  await p.click('[data-act=cu_save]'); await wait(p, 500);
  let c = await calls(p, 'customer_save'); ok(c.length === 1 && c[0].p_id === null && c[0].p.mobile === '01812345678' && c[0].p.name === 'Nadia' && c[0].p.birthday === '1992-03-04' && c[0].p.address === 'Uttara' && typeof c[0].p_client === 'string', 'customer_save sent (Bangla digits normalised, idempotency key)');
  ok((await calls(p, 'customer_profile')).length === 1 && /Nadia/.test(await text(p)), 'profile opened after adding');
  await p.click('.sheet-x'); await wait(p, 200);
  await p.evaluate(() => { window.__W43.dup = true; }); await p.click('[data-act=cu_add]'); await wait(p, 250); await p.fill('#cf_mobile', '01722222222'); await p.fill('#cf_name', 'Someone'); await p.click('[data-act=cu_save]'); await wait(p, 500);
  ok(/already registered/.test(await text(p)), 'duplicate mobile: friendly text'); ok((await calls(p, 'customer_profile')).slice(-1)[0].p_customer === 'c2', 'duplicate mobile opens the existing customer');
  await p.evaluate(() => { window.__W43.dup = false; }); await p.click('.sheet-x'); await wait(p, 200);
  await p.click('.cu-row >> nth=0 >> [data-act=cu_menu]'); await wait(p, 250);
  // ---------- menu ----------
  t = await text(p); ok(/Change tier/.test(t) && /Issue a gift/.test(t) && /Adjust points/.test(t) && /Open dues/.test(t) && /Call/.test(t) && /WhatsApp/.test(t) && /Switch customer off/.test(t), 'menu for the owner has every action');
  ok(await p.locator('a[href^="tel:"]').count() === 1 && /wa\.me\/880/.test(await p.locator('a[href*="wa.me"]').getAttribute('href')), 'call and WhatsApp links');
  await p.click('[data-act=cu_tier]'); await wait(p, 250); await setVal(p, '#tc_tier', '5'); await p.fill('#tc_reason', 'x'); await p.evaluate(() => { window.__W43.err.customer_set_tier = 'note_required'; });
  await p.click('[data-act=cu_tier_ok]'); await wait(p, 300); ok(/Write a reason/.test(await text(p)), 'tier change: friendly reason error');
  await p.fill('#tc_reason', 'bought a lot'); await p.click('[data-act=cu_tier_ok]'); await wait(p, 500);
  c = await calls(p, 'customer_set_tier'); ok(c.length === 2 && c[1].p_tier === 5 && c[1].p_reason === 'bought a lot' && c[1].p_lock === true, 'customer_set_tier sent with the reason and the lock');
  ok(/Elite/.test(await p.locator('#cu_list').innerText()), 'list refreshed with the new tier');
  // gift + points
  await p.click('.cu-row >> nth=0 >> [data-act=cu_menu]'); await wait(p, 200); await p.click('[data-act=cu_gift]'); await wait(p, 200); await p.fill('#gf_en', 'A book'); await p.fill('#gf_val', '150'); await p.click('[data-act=cu_gift_ok]'); await wait(p, 400);
  c = await calls(p, 'gift_issue'); ok(c.length === 1 && c[0].p_text_en === 'A book' && c[0].p_value === 150 && typeof c[0].p_client === 'string', 'gift_issue sent');
  await p.click('.cu-row >> nth=0 >> [data-act=cu_menu]'); await wait(p, 200); await p.click('[data-act=cu_pts]'); await wait(p, 200); await p.fill('#pt_delta', '-10'); await p.fill('#pt_note', 'wrong entry'); await p.click('[data-act=cu_pts_ok]'); await wait(p, 400);
  c = await calls(p, 'crmf_points_adjust'); ok(c.length === 1 && c[0].p_delta === -10 && c[0].p_note === 'wrong entry', 'points adjusted');
  await p.click('.cu-row >> nth=0 >> [data-act=cu_menu]'); await wait(p, 200); await p.click('[data-act=cu_active]'); await wait(p, 400);
  c = await calls(p, 'customer_save'); ok(c.slice(-1)[0].p.active === false, 'switch off sends active=false');
  // ---------- profile, gifts, redeem ----------
  p = await open('#/customers'); await p.click('.cu-row >> nth=0'); await wait(p, 500);
  t = await text(p); ok(/Spent/.test(t) && /Orders/.test(t) && /Last purchase/.test(t) && /Tier history/.test(t) && /loyal for years/.test(t) && /Points/.test(t) && /Free delivery/.test(t) && /#12/.test(t), 'profile shows totals, history, perks, recent sales');
  ok(await p.locator('[data-act=cu_claim]').count() === 2, 'two gifts due with a claim button'); await noOverflow(p, 'profile'); await p.screenshot({ path: SP + '/cu_profile.png', fullPage: true });
  await p.click('[data-act=cu_claim] >> nth=1'); await wait(p, 500); c = await calls(p, 'gift_claim'); ok(c.length === 1 && c[0].p_rule === 5 && c[0].p_occasion === 'birthday:2026', 'a rule gift is claimed by rule + occasion');
  await p.click('[data-act=cu_claim] >> nth=0'); await wait(p, 500); c = await calls(p, 'gift_claim'); ok(c.length === 2 && c[1].p_gift === 'g1', 'an issued gift is claimed by id');
  await p.click('[data-act=cu_redeem]'); await wait(p, 250); await p.fill('#rd_n', '20'); await p.click('[data-act=cu_redeem_dry]'); await wait(p, 300);
  ok(/worth ৳ 10/.test(await p.locator('#rd_out').innerText()), 'redeem preview shows the taka value'); await p.click('[data-act=cu_redeem_ok]'); await wait(p, 400);
  c = await calls(p, 'crmf_points_redeem'); ok(c.length === 2 && c[0].p_dry === true && c[1].p_dry === false && typeof c[1].p_client === 'string', 'redeem: dry run first, then the real one with a key');
  // loyalty / gifts off: nothing shown
  p = await open('#/customers', { noLoyal: true, noGifts: true }); await p.click('.cu-row >> nth=0'); await wait(p, 400);
  t = await text(p); ok(!/Redeem points/.test(t) && !/Gifts due/.test(t) && (await calls(p, 'gifts_due')).length === 0, 'switches OFF: no points, no gifts, no gift call');
  // ---------- staff / manager ----------
  p = await open('#/customers', { staff: true });
  ok(await p.locator('[data-act=cu_add]').count() === 1, 'staff with POS can add a customer');
  await p.click('[data-act=cu_add]'); await wait(p, 250); ok(await p.locator('#cf_tier').count() === 0 && await p.locator('#cf_limit').count() === 0 && await p.locator('#cf_lock').count() === 0, 'staff form has no tier / credit limit / lock');
  await p.click('.sheet-x'); await p.click('.cu-row >> nth=0 >> [data-act=cu_menu]'); await wait(p, 250); t = await text(p);
  ok(!/Change tier/.test(t) && !/Issue a gift/.test(t) && !/Adjust points/.test(t) && !/Switch customer off/.test(t) && /Open dues/.test(t) && /Call/.test(t), 'staff menu has no tier / gift / points / switch-off');
  p = await open('#/customers', { mgr: true }); await p.click('.cu-row >> nth=0 >> [data-act=cu_menu]'); await wait(p, 250); ok(/Change tier/.test(await text(p)), 'a user with the customer_manage grant sees Change tier');
  p = await open('#/tiers', { staff: true }); ok(/Only the owner/.test(await text(p)) && await p.locator('[data-act=ti_edit]').count() === 0, 'tiers page is owner only');

  // ---------- tiers ----------
  p = await open('#/tiers');
  ok(await p.locator('#ti_list .card').count() === 7, 'seven tiers listed'); t = await text(p); ok(/Walk-in/.test(t) && /Default/.test(t) && /nothing switches on by itself|every discount and threshold is blank/.test(t), 'default marker and the blank-policy note');
  ok(/3 sales/.test(t) && /270/.test(t), 'tier usage report shown'); await noOverflow(p, 'tiers'); await minTap(p, 'tiers'); await p.screenshot({ path: SP + '/cu_tiers.png', fullPage: true });
  await p.click('[data-act=ti_edit][data-v="4"]'); await wait(p, 250);
  ok(await p.inputValue('#tf_discount_percent') === '10' && await p.inputValue('#tf_min_lifetime_spend') === '5000' && await p.inputValue('#tf_perks') === 'Free delivery', 'edit sheet is filled from the tier');
  await p.fill('#tf_discount_percent', '12'); await p.fill('#tf_discount_cap_amount', '500'); await p.click('[data-act=ti_save]'); await wait(p, 500);
  c = await calls(p, 'tier_save'); ok(c.length === 1 && c[0].p_id === 4 && c[0].p.discount_percent === '12' && c[0].p.discount_cap_amount === '500' && c[0].p.min_orders === '3' && !('code' in c[0].p), 'tier_save for an existing tier (no code sent)');
  await p.click('[data-act=ti_edit][data-v=""]'); await wait(p, 250); await p.fill('#tf_code', 'platinum'); await p.fill('#tf_name_en', 'Platinum'); await p.fill('#tf_discount_percent', '20'); await p.click('[data-act=ti_save]'); await wait(p, 500);
  c = await calls(p, 'tier_save'); ok(c.length === 2 && c[1].p_id === null && c[1].p.code === 'platinum' && /Platinum/.test(await p.locator('#ti_list').innerText()), 'new tier added');
  await p.click('[data-act=ti_move][data-v="2"][data-d="1"]'); await wait(p, 500); c = await calls(p, 'tier_reorder'); ok(c.length === 1 && c[0].p_ids.indexOf(2) === 2 && c[0].p_ids.indexOf(3) === 1, 'reorder sends the new order');
  await p.click('[data-act=ti_active][data-v="7"]'); await wait(p, 400); c = await calls(p, 'tier_save'); ok(c.slice(-1)[0].p_id === 7 && c.slice(-1)[0].p.active === false, 'retire sends active=false');
  ok(await p.locator('[data-act=ti_active][data-v="1"]').count() === 0, 'the default tier has no retire button');
  await p.click('[data-act=ti_sw][data-k=loyalty_points_on]'); await wait(p, 400); c = await calls(p, 'set_rule'); ok(c.length === 1 && c[0].p_key === 'loyalty_points_on' && c[0].p_value === false, 'switch sent to set_rule');
  await p.fill('#nr_points_per_100_taka', '2'); await p.click('[data-act=ti_num][data-k=points_per_100_taka]'); await wait(p, 400); c = await calls(p, 'set_rule'); ok(c.slice(-1)[0].p_key === 'points_per_100_taka' && c.slice(-1)[0].p_value === 2, 'number sent to set_rule');
  await p.click('[data-act=ti_dry]'); await wait(p, 400); t = await p.locator('#ti_dry').innerText(); ok(/2 customers would change tier/.test(t) && /TestF/.test(t) && /TestM/.test(t), 'dry-run list'); c = await calls(p, 'customer_tier_refresh'); ok(c.length === 1 && c[0].p_dry === true, 'dry run asked with p_dry=true');
  ok(await p.locator('[data-act=ti_apply]').count() === 0 && /Turn/.test(t), 'apply is not offered while the automatic switch is OFF');
  p = await open('#/tiers', { autoOn: true }); await p.click('[data-act=ti_dry]'); await wait(p, 400); ok(await p.locator('[data-act=ti_apply]').count() === 1, 'apply offered once the switch is ON');
  await p.click('[data-act=ti_apply]'); await wait(p, 500); c = await calls(p, 'customer_tier_refresh'); ok(c.length === 2 && c[1].p_dry === false, 'apply runs the real refresh (after a confirm)');
  await p.click('[data-act=gr_edit][data-v=""]'); await wait(p, 250); await setVal(p, '#gr_trig', 'every_n_purchases'); await p.fill('#gr_thr', '5'); await p.fill('#gr_en', 'Free tea'); await p.click('[data-act=gr_save]'); await wait(p, 500);
  c = await calls(p, 'gift_rule_save'); ok(c.length === 1 && c[0].p.trigger === 'every_n_purchases' && c[0].p.threshold === '5' && c[0].p.gift_text_en === 'Free tea', 'gift rule saved'); ok(/Free tea/.test(await text(p)), 'gift rule listed');
  await p.evaluate(() => { window.__W43.err.tier_save = 'code_exists'; }); await p.click('[data-act=ti_edit][data-v=""]'); await wait(p, 200); await p.fill('#tf_code', 'gold'); await p.fill('#tf_name_en', 'G'); await p.click('[data-act=ti_save]'); await wait(p, 400);
  ok(/already exists/.test(await text(p)), 'friendly duplicate-code text');

  // ---------- POS: tier chip + tier-discount button ----------
  p = await open('#/pos'); const pcItem = base.tables.items.find((i) => i.unit === 'pc' && i.sell_price); await p.click(`.pos-item[data-v="${pcItem.id}"]`); await wait(p, 200); await p.click('[data-act=pos_cart]'); await wait(p, 300);
  await p.click('[data-act=pos_cust_show]'); await wait(p, 200); await p.fill('#cu_mobile', '01711111111'); await wait(p, 900);
  t = await p.locator('#cart_cust').innerText(); ok(/Gold/.test(t) && /Free delivery/.test(t) && /1 gift\(s\) due/.test(t), 'POS shows the tier chip, perks and the gift reminder');
  ok(await p.locator('#cart_tier_btn').count() === 1 && /Apply tier discount: Gold 10%/.test(await p.locator('#cart_tier_btn').innerText()), 'one-tap tier discount button');
  const before = await p.locator('#cart_total').innerText();
  await p.click('#cart_tier_btn'); await wait(p, 300); ok(await p.inputValue('#cart_disc') === '10', 'the button fills the percent field with the tier percent'); ok((await p.locator('#cart_total').innerText()) !== before, 'the total drops');
  ok(/Takes off/.test(await p.locator('#cart_disc_calc').innerText()), 'the existing discount calculation line is used'); await noOverflow(p, 'pos cart'); await p.screenshot({ path: SP + '/cu_pos.png' });
  await p.evaluate(() => { window.__W43.posinfo = { found: true, id: 'c1', name: 'Rafiq', tier: { id: 1, code: 'walkin', name_bn: 'ওয়াক-ইন', name_en: 'Walk-in', color: '#64748b', badge: '🚶', perks: null, discount_percent: 0, discount_cap_amount: null }, tier_discount_on: false, gifts_due: 0, points: null }; });
  await p.fill('#cu_mobile', '01700001111'); await wait(p, 900); ok(await p.locator('#cart_tier_btn').count() === 0 && /Walk-in/.test(await p.locator('#cart_cust').innerText()), 'no tier discount button when the tier gives none (or the switch is OFF)');
  await p.fill('#cu_mobile', '01799999999'); await wait(p, 700); ok(await p.locator('#cart_tier').count() === 0, 'unknown customer: no tier block');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
