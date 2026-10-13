// Module D web piece: #/partners (owner only) - overview, parties, ventures, the deed editor with the rule builder, trial calculation, settlements, capital ledger, party statement.
// Run: node partners_test.js <abs tests/web dir>      (web/partners.js is injected into index.html here; the lead adds the <script> tag for real)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8356, srv = C.serve(PORT);
const EXTRA44 = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 c.rpc = async (fn, args) => {
  if (!/^partner_/.test(fn)) return rpc(fn, args);
  (window.__AC44 = window.__AC44 || []).push([fn, clone(args || {})]);
  if (window.__ERR44 && window.__ERR44.fn === fn) { const m = window.__ERR44.msg; window.__ERR44 = null; return { data: null, error: { message: m, code: 'P0001' } }; }
  if (fn === 'partner_overview') return { data: { ventures: [{ id: 1, name_bn: 'শো-রুম ১ ফ্র্যাঞ্চাইজ', name_en: 'Showroom 1 franchise', scope: 'location', model: 'franchise', status: 'active', agreements: 1, drafts: 1, capital: 100000, next_due: '2026-03-01', owed: 4200 }], owed_total: 4200, capital_total: 100000 }, error: null };
  if (fn === 'partner_party_save') { const n = { id: 50 + T.partner_parties.length, name: args.p_name, kind: args.p_kind, mobile: args.p_mobile, active: args.p_active }; T.partner_parties.push(n); return { data: n, error: null }; }
  if (fn === 'partner_venture_save') { const n = { id: 9, name_bn: args.p_name_bn, name_en: args.p_name_en, scope: args.p_scope, model: args.p_model, status: args.p_status }; T.partner_ventures.push(n); return { data: n, error: null }; }
  if (fn === 'partner_agreement_save') { const d = T.partner_agreements.find((x) => x.id === args.p_id); if (d) { d.title = args.p_title; d.clauses = (args.p_clauses || []).map((cl, i) => Object.assign({}, cl, { no: i + 1 })); d.effective_from = args.p_from; return { data: d, error: null }; }
    const n = { id: 30, venture_id: args.p_venture, title: args.p_title || 'New', version: 1, status: 'draft', clauses: [], effective_from: null, effective_to: null, is_example: false }; T.partner_agreements.push(n); return { data: n, error: null }; }
  if (fn === 'partner_agreement_from_template') { const n = { id: 31, venture_id: args.p_venture, title: 'EXAMPLE - Franchise (EXAMPLE)', version: 1, status: 'draft', clauses: [], is_example: true }; T.partner_agreements.push(n); return { data: n, error: null }; }
  if (fn === 'partner_agreement_party_set') { const r = T.agreement_parties.find((x) => x.agreement_id === args.p_agr && x.party_id === args.p_party && x.role === args.p_role); if (r) r.active = args.p_active; else T.agreement_parties.push({ id: 90, agreement_id: args.p_agr, party_id: args.p_party, role: args.p_role, share_percent: args.p_share, active: true }); return { data: {}, error: null }; }
  if (fn === 'partner_rule_save') { const n = args.p_step_no || (T.partner_rules.filter((r) => r.agreement_id === args.p_agr).length + 1); const r = T.partner_rules.find((x) => x.agreement_id === args.p_agr && x.step_no === n);
    if (r) Object.assign(r, { name: args.p_name, kind: args.p_kind, config: args.p_config, active: args.p_active }); else T.partner_rules.push({ id: 200 + n, agreement_id: args.p_agr, step_no: n, step_key: 'k' + n, name: args.p_name, kind: args.p_kind, config: args.p_config, active: args.p_active }); return { data: {}, error: null }; }
  if (fn === 'partner_rules_reorder') { const rs = T.partner_rules.filter((x) => x.agreement_id === args.p_agr); args.p_order.forEach((o, i) => { rs.find((x) => x.step_no === o).tmp = i + 1; }); rs.forEach((x) => { x.step_no = x.tmp; }); return { data: {}, error: null }; }
  if (fn === 'partner_agreement_activate') { const d = T.partner_agreements.find((x) => x.id === args.p_agr); d.status = 'active'; return { data: d, error: null }; }
  if (fn === 'partner_agreement_amend') { const n = { id: 40, venture_id: 1, title: 'Franchise v2', version: 2, status: 'draft', supersedes_id: args.p_agr, clauses: [], is_example: false }; T.partner_agreements.push(n); return { data: n, error: null }; }
  if (fn === 'partner_calculate') { const man = args.p_manual; const ok = !!man;
    return { data: { status: ok ? 'ok' : 'incomplete', bases: { gross_sales: null, net_sales: man ? man.net_sales || null : null, gross_profit: null, net_profit_before_fees: man ? man.net_profit_before_fees : null }, sources: { net_profit_before_fees: ok ? 'manual' : 'unavailable' },
      steps: [{ step_no: 1, name: 'Base', kind: 'base', skipped: false, pool_before: null, pool_after: ok ? 90000 : null, amount: 0 }, { step_no: 2, name: 'Royalty 5%', kind: 'royalty', skipped: !ok, pool_before: 90000, pool_after: 70000, amount: 20000 }, { step_no: 3, name: 'Rest to franchisee', kind: 'split', skipped: false, pool_before: 70000, pool_after: 0, amount: 70000 }],
      party_totals: ok ? [{ party_id: 1, name: 'Owner Party', amount: 20000 }, { party_id: 4, name: 'Franchisee Fay', amount: 70000 }] : [], total_distributable: ok ? 90000 : 0, outside_total: 0, retained: 0, carry_out: 0,
      warnings: ok ? [{ code: 'manual_only' }] : [{ code: 'base_unavailable', base: 'net_profit_before_fees' }, { code: 'uncosted_sales', detail: 500 }] }, error: null }; }
  if (fn === 'partner_settlement_save') { const n = { id: 70, agreement_id: args.p_agr, period_from: args.p_from, period_to: args.p_to, status: 'draft', total_distributable: 90000, calc: { steps: [], party_totals: [], warnings: [], bases: {} } }; T.partner_settlements.push(n); return { data: n, error: null }; }
  if (fn === 'partner_settlement_approve') { T.partner_settlements.find((x) => x.id === args.p_id).status = 'approved'; return { data: {}, error: null }; }
  if (fn === 'partner_settlement_void') { T.partner_settlements.find((x) => x.id === args.p_id).status = 'void'; return { data: {}, error: null }; }
  if (fn === 'partner_settlement_pay') { const l = T.partner_settlement_lines.find((x) => x.id === args.p_line); l.paid_amount += args.p_amount; return { data: {}, error: null }; }
  if (fn === 'partner_capital_balances') return { data: [{ party_id: 2, name: 'Investor Ivy', contributed: 100000, loan_in: 0, returned: 0, repaid: 0, drawings: 0, balance: 100000, paid_back: 6000, outstanding_payback: 94000 }], error: null };
  if (fn === 'partner_capital_add') { T.partner_capital.push({ id: 300, agreement_id: args.p_agr, party_id: args.p_party, kind: args.p_kind, amount: args.p_amount, cap_date: args.p_date, mode: args.p_mode, status: 'posted' }); return { data: {}, error: null }; }
  if (fn === 'partner_capital_void') { T.partner_capital.find((x) => x.id === args.p_id).status = 'void'; return { data: {}, error: null }; }
  if (fn === 'partner_party_statement') return { data: { party: { id: args.p_party, name: 'Investor Ivy', mobile: '01811000000' }, from: args.p_from, to: args.p_to, capital_opening: 0, capital_movements: [{ date: '2025-12-01', kind: 'contribution', amount: 100000, mode: 'bank' }], capital_closing: 100000, drawings: 0,
      shares_due: [{ period_from: '2026-01-01', period_to: '2026-01-31', kind: 'payback', amount: 6000, paid: 6000 }], payments: [{ date: '2026-02-05', mode: 'bank', amount: 6000, ref: 'chq-1' }], due_in_period: 6000, paid_in_period: 6000, due_to_date: 6000, paid_to_date: 6000, balance_owed: 0 }, error: null };
  return { data: {}, error: null };
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('reason text'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA44 }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(/localhost:\d+\/(index\.html)?(\?.*)?$/, async (r) => { const resp = await r.fetch(); const body = (await resp.text()).replace('<script src="parallel.js"></script>', '<script src="parallel.js"></script><script src="partners.js"></script>'); r.fulfill({ response: resp, body }); });
    const data = C.mk(base, {}); const T = data.tables;
    T.partner_parties = [{ id: 1, name: 'Owner Party', kind: 'company', mobile: '01711000000', active: true }, { id: 2, name: 'Investor Ivy', kind: 'individual', mobile: '01811000000', active: true }, { id: 4, name: 'Franchisee Fay', kind: 'individual', active: true }];
    T.partner_ventures = [{ id: 1, name_bn: 'শো-রুম ১ ফ্র্যাঞ্চাইজ', name_en: 'Showroom 1 franchise', scope: 'location', location_id: 1, model: 'franchise', status: 'active' }];
    T.partner_agreements = [{ id: 10, venture_id: 1, title: 'Franchise deed', version: 1, status: 'active', effective_from: '2026-01-01', effective_to: null, clauses: [{ no: 1, title_en: 'Purpose', text_en: 'Run the shop' }], is_example: false },
      { id: 11, venture_id: 1, title: 'Draft deed', version: 1, status: 'draft', effective_from: null, effective_to: null, clauses: [{ no: 1, title_en: 'First', text_en: 'a' }, { no: 2, title_en: 'Second', text_en: 'b' }], is_example: true }];
    T.agreement_parties = [{ id: 1, agreement_id: 10, party_id: 1, role: 'owner', active: true }, { id: 2, agreement_id: 10, party_id: 4, role: 'franchisee', active: true }, { id: 3, agreement_id: 11, party_id: 1, role: 'owner', active: true }, { id: 4, agreement_id: 11, party_id: 4, role: 'franchisee', active: true }, { id: 5, agreement_id: 11, party_id: 2, role: 'investor', active: true }];
    T.partner_rules = [{ id: 1, agreement_id: 10, step_no: 1, step_key: 'a', name: 'Base', kind: 'base', config: { base: 'net_profit_before_fees' }, active: true }, { id: 2, agreement_id: 10, step_no: 2, step_key: 'b', name: 'Royalty', kind: 'royalty', config: { role: 'owner', percent: 5, base: 'net_sales' }, active: true },
      { id: 3, agreement_id: 10, step_no: 3, step_key: 'c', name: 'Rest', kind: 'split', config: { shares: [{ role: 'franchisee', percent: 100 }] }, active: true },
      { id: 4, agreement_id: 11, step_no: 1, step_key: 'd', name: 'Base', kind: 'base', config: { base: 'net_profit_before_fees' }, active: true }, { id: 5, agreement_id: 11, step_no: 2, step_key: 'e', name: 'Investor payback', kind: 'payback', config: { party_id: 2, percent: 50, then_percent: 20 }, active: true }];
    T.partner_capital = [{ id: 1, agreement_id: 10, party_id: 2, kind: 'contribution', amount: 100000, cap_date: '2025-12-01', mode: 'bank', status: 'posted' }];
    T.partner_settlements = [{ id: 60, agreement_id: 10, period_from: '2026-01-01', period_to: '2026-01-31', status: 'draft', total_distributable: 90000, calc: { steps: [{ step_no: 1, name: 'Base', kind: 'base', pool_before: null, pool_after: 90000, amount: 0 }], party_totals: [{ name: 'Owner Party', amount: 20000 }], warnings: [], bases: {} }, note: 'Jan' }];
    T.partner_settlement_lines = [{ id: 1, settlement_id: 60, party_id: 1, amount: 20000, kind: 'royalty', funded_outside: false, paid_amount: 0 }, { id: 2, settlement_id: 60, party_id: 4, amount: 70000, kind: 'share', funded_outside: false, paid_amount: 0 }];
    T.partner_settlement_payments = [];
    T.partner_templates = [{ code: 'franchise', name_bn: 'উদাহরণ - ফ্র্যাঞ্চাইজ', name_en: 'Franchise (EXAMPLE)', description_en: 'Royalty on net sales + a monthly fee', description_bn: 'রয়্যালটি' }];
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}window.print=function(){window.__PRINTED=(window.__PRINTED||0)+1};`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__AC44 || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const tab = async (p, t) => { await p.selectOption('#pt_tab', t); await wait(p, 300); };

  // ---- overview + owner only
  let p = await open('#/partners');
  ok(await p.locator('#pt_tab').count() === 1, 'section select present');
  let t = await text(p); ok(/Showroom 1 franchise/.test(t) && /100,000/.test(t) && /4,200/.test(t), 'overview shows venture, capital and what is owed'); ok(/2026-03-01/.test(t), 'next settlement date shown');
  await noOverflow(p, 'overview'); await p.screenshot({ path: SP + '/pt_overview.png', fullPage: true });
  const np = await open('#/partners', { owner: false }); ok(/Only the owner/.test(await text(np)) && await np.locator('#pt_tab').count() === 0, 'a non-owner sees only the owner-only note');

  // ---- parties
  await tab(p, 'parties'); t = await text(p); ok(/Investor Ivy/.test(t) && /Franchisee Fay/.test(t), 'parties listed'); await noOverflow(p, 'parties');
  await p.click('[data-act=pt_newparty]'); await wait(p, 200);
  await p.fill('#pp_name', 'Partner Pat'); await p.fill('#pp_mobile', '01999'); await p.click('[data-act=pt_saveparty]'); await wait(p, 500);
  let c = await calls(p, 'partner_party_save'); ok(c.length === 1 && c[0].p_name === 'Partner Pat' && c[0].p_client && c[0].p_id === null, 'party saved with a client key');
  ok(/Partner Pat/.test(await text(p)), 'new party listed');
  await p.evaluate(() => { window.__ERR44 = { fn: 'partner_party_save', msg: 'name_required' }; }); await p.click('[data-act=pt_newparty]'); await wait(p, 200); await p.click('[data-act=pt_saveparty]'); await wait(p, 400);
  ok(/A name is needed/.test(await text(p)), 'friendly error for a missing name'); await p.keyboard.press('Escape'); await p.evaluate(() => { const s = document.querySelector('#sheet'); if (s) s.remove(); });

  // ---- ventures
  await tab(p, 'ventures'); ok(/Showroom 1 franchise/.test(await text(p)), 'ventures listed');
  await p.click('[data-act=pt_newvent]'); await wait(p, 200); await p.fill('#pv_bn', 'নতুন ডিল'); await p.selectOption('#pv_model', 'loan'); await p.click('[data-act=pt_savevent]'); await wait(p, 500);
  c = await calls(p, 'partner_venture_save'); ok(c.length === 1 && c[0].p_model === 'loan' && c[0].p_name_bn === 'নতুন ডিল' && c[0].p_client, 'venture saved'); await noOverflow(p, 'ventures');

  // ---- deeds: list, open a draft with the rule builder
  await tab(p, 'deeds'); t = await text(p); ok(/Franchise deed/.test(t) && /Draft deed/.test(t) && /EXAMPLE/.test(t), 'deeds listed with the example flag');
  await p.click('[data-act=pt_opendeed][data-v="11"]'); await wait(p, 300); t = await text(p);
  ok(/Investor Ivy gets 50% of the profit until the capital is paid back, then 20%/.test(t), 'the rule shows as a plain sentence'); ok(await p.locator('[data-act=pt_ruleedit],[data-act=pt_ruledit]').count() >= 1, 'a draft deed can be edited');
  await p.click('[data-act=pt_addcl]'); await wait(p, 400); c = await calls(p, 'partner_agreement_save'); ok(c.length === 1 && c[0].p_clauses.length === 3, 'adding a clause saves 3 clauses');
  await p.click('[data-act=pt_clmv][data-v="0"][data-d="1"]'); await wait(p, 400); c = await calls(p, 'partner_agreement_save'); ok(c.length === 2 && c[1].p_clauses[0].title_en === 'Second' && c[1].p_clauses[1].title_en === 'First', 'moving a clause down reorders it');
  await p.click('[data-act=pt_cldel][data-v="2"]'); await wait(p, 400); c = await calls(p, 'partner_agreement_save'); ok(c[2].p_clauses.length === 2, 'removing a clause saves two');
  // new step: royalty, live sentence
  await p.click('[data-act=pt_rulenew]'); await wait(p, 300); await p.selectOption('#pr_kind', 'royalty'); await wait(p, 200);
  await p.selectOption('#pt_f_party', 'p:2'); await p.fill('#pt_f_pct', '7'); await wait(p, 200);
  ok(/Investor Ivy gets 7% of net sales/.test(await p.textContent('#pr_sum')), 'live sentence while building a royalty step');
  await p.click('[data-act=pt_rulesave]'); await wait(p, 500); c = await calls(p, 'partner_rule_save'); ok(c.length === 1 && c[0].p_kind === 'royalty' && c[0].p_config.party_id === 2 && c[0].p_config.percent === 7 && c[0].p_config.base === 'net_sales', 'royalty config sent as JSON built from the fields');
  ok(/Investor Ivy gets 7%/.test(await text(p)), 'new step listed');
  // split step: shares and the running total
  await p.click('[data-act=pt_rulenew]'); await wait(p, 300); ok(await p.locator('#pt_f_shares .pt-share').count() === 2, 'split starts with two share rows');
  await p.selectOption('#pt_f_shares .pt-share:nth-child(1) .sh-p', 'r:owner'); await p.fill('#pt_f_shares .pt-share:nth-child(1) .sh-pc', '60');
  await p.selectOption('#pt_f_shares .pt-share:nth-child(2) .sh-p', 'r:franchisee'); await p.fill('#pt_f_shares .pt-share:nth-child(2) .sh-pc', '30'); await wait(p, 150);
  ok(/Σ 90%/.test(await p.textContent('.pt-sum')) && await p.locator('.pt-sum.warn').count() === 1, 'the share total shows 90% in red');
  await p.evaluate(() => { window.__ERR44 = { fn: 'partner_rule_save', msg: 'split_not_100' }; }); await p.click('[data-act=pt_rulesave]'); await wait(p, 400);
  ok(/add up to exactly 100%/.test(await text(p)), 'friendly error when the split is not 100'); await p.fill('#pt_f_shares .pt-share:nth-child(2) .sh-pc', '40'); await wait(p, 150);
  ok(await p.locator('.pt-sum.ok').count() === 1, 'the total turns green at 100%');
  await p.click('[data-act=pt_rulesave]'); await wait(p, 500); c = await calls(p, 'partner_rule_save'); const sp = c[c.length - 1]; ok(sp.p_kind === 'split' && sp.p_config.shares.length === 2 && sp.p_config.shares[0].role === 'owner' && sp.p_config.shares[1].percent === 40, 'split sent with roles and percents');
  // tiered split builder
  await p.click('[data-act=pt_rulenew]'); await wait(p, 300); await p.selectOption('#pr_kind', 'tiered_split'); await wait(p, 200); ok(await p.locator('.pt-slab').count() === 2, 'tiered split starts with two slabs');
  await p.click('[data-act=pt_addslab]'); await wait(p, 100); ok(await p.locator('.pt-slab').count() === 3, 'a slab can be added'); await p.evaluate(() => document.querySelector('#sheet').remove());
  // reorder + retire a rule
  await p.click('[data-act=pt_rulemv][data-v="2"][data-d="-1"]'); await wait(p, 400); c = await calls(p, 'partner_rules_reorder'); ok(c.length === 1 && c[0].p_order[0] === 2 && c[0].p_order[1] === 1, 'moving a step up sends the new order');
  await p.click('[data-act=pt_ruleoff][data-v="1"]'); await wait(p, 400); c = await calls(p, 'partner_rule_save'); ok(c[c.length - 1].p_active === false, 'a step is retired, not deleted');
  await noOverflow(p, 'draft deed'); await p.screenshot({ path: SP + '/pt_deed.png', fullPage: true });
  // activate an EXAMPLE deed asks for confirmation of the numbers
  await p.click('[data-act=pt_activate]'); await wait(p, 500); c = await calls(p, 'partner_agreement_activate'); ok(c.length === 1 && c[0].p_numbers_confirmed === true, 'activating an example deed sends numbers_confirmed');
  ok(await p.locator('[data-act=pt_ruledit],[data-act=pt_rulenew],[data-act=pt_addcl]').count() === 0, 'once active the editing buttons are gone');
  ok(await p.locator('[data-act=pt_amend]').count() === 1, 'an active deed offers an amendment');
  await p.click('[data-act=pt_amend]'); await wait(p, 500); c = await calls(p, 'partner_agreement_amend'); ok(c.length === 1 && c[0].p_client, 'amend creates a revision with a client key'); ok(/Previous revision/.test(await text(p)), 'the revision links back to the previous one');
  // new deed from a template
  await tab(p, 'deeds'); await p.click('[data-act=pt_newdeed]'); await wait(p, 200); await p.selectOption('#nd_tpl', 'franchise'); await wait(p, 100); ok(/Royalty on net sales/.test(await p.textContent('#nd_hint')), 'template hint shown');
  await p.click('[data-act=pt_makedeed]'); await wait(p, 500); c = await calls(p, 'partner_agreement_from_template'); ok(c.length === 1 && c[0].p_code === 'franchise' && c[0].p_client, 'deed created from the template'); ok(/EXAMPLE/.test(await text(p)), 'the template deed is marked EXAMPLE');

  // ---- trial calculation
  p = await open('#/partners'); await tab(p, 'calc'); ok(await p.locator('#pc_deed').count() === 1, 'trial form');
  await p.selectOption('#pc_deed', '10'); await p.click('[data-act=pt_calc]'); await wait(p, 500); c = await calls(p, 'partner_calculate'); ok(c.length === 1 && c[0].p_manual === null && c[0].p_agr === 10, 'calculate without typed figures sends no manual base');
  t = await text(p); ok(/not available/.test(t) && /type it|Type|uncosted|no cost price/i.test(t), 'an incomplete calculation explains what to type'); ok(await p.locator('[data-act=pt_savecalc]').count() === 0, 'an incomplete calculation cannot be saved');
  await p.locator('details summary').first().click(); await p.fill('#pc_m_net_profit_before_fees', '90000'); await p.fill('#pc_m_net_sales', '400000'); await p.click('[data-act=pt_calc]'); await wait(p, 500);
  c = await calls(p, 'partner_calculate'); ok(c.length === 2 && c[1].p_manual.net_profit_before_fees === 90000 && c[1].p_manual.net_sales === 400000, 'typed figures sent as the manual base');
  t = await text(p); ok(/Royalty 5%/.test(t) && /Rest to franchisee/.test(t) && /70,000/.test(t) && /Total shared/.test(t) && /90,000/.test(t), 'the waterfall is shown step by step with the totals');
  await noOverflow(p, 'trial'); await p.screenshot({ path: SP + '/pt_calc.png', fullPage: true });
  await p.click('[data-act=pt_savecalc]'); await wait(p, 500); c = await calls(p, 'partner_settlement_save'); ok(c.length === 1 && c[0].p_manual.net_profit_before_fees === 90000 && c[0].p_client, 'save as a draft settlement carries the same typed figures and a client key');
  ok(/Settlements|settlement/i.test(await p.evaluate(() => document.querySelector('#pt_tab').selectedOptions[0].textContent)), 'moves to the settlements section');
  await p.evaluate(() => { window.__ERR44 = null; });
  // ---- settlements
  await tab(p, 'settle'); t = await text(p); ok(/2026-01-01/.test(t), 'settlement listed'); await p.click('[data-act=pt_openset][data-v="60"]'); await wait(p, 300);
  ok(/Owner Party/.test(await text(p)) && await p.locator('[data-act=pt_approve]').count() === 1, 'a draft settlement offers approval');
  await p.click('[data-act=pt_approve]'); await wait(p, 500); c = await calls(p, 'partner_settlement_approve'); ok(c.length === 1 && c[0].p_id === 60, 'approve sent');
  await p.click('[data-act=pt_openset][data-v="60"]'); await wait(p, 300); ok(await p.locator('[data-act=pt_approve]').count() === 0 && await p.locator('[data-act=pt_payline]').count() === 2, 'approved: no more approve button, payments possible');
  await p.click('[data-act=pt_payline][data-v="1"]'); await wait(p, 300); await p.fill('#pp_amt', '5000'); await p.selectOption('#pp_mode', 'bank'); await p.click('[data-act=pt_paysave]'); await wait(p, 500);
  c = await calls(p, 'partner_settlement_pay'); ok(c.length === 1 && c[0].p_line === 1 && c[0].p_amount === 5000 && c[0].p_mode === 'bank' && c[0].p_client, 'payment sent with a client key');
  await p.click('[data-act=pt_openset][data-v="60"]'); await wait(p, 300); await p.click('[data-act=pt_payline][data-v="2"]'); await wait(p, 300); await p.evaluate(() => { window.__ERR44 = { fn: 'partner_settlement_pay', msg: 'overpay' }; }); await p.click('[data-act=pt_paysave]'); await wait(p, 400);
  ok(/Cannot pay more than is due/.test(await text(p)), 'friendly overpay error'); await noOverflow(p, 'settlements');

  // ---- capital
  await p.evaluate(() => { const s = document.querySelector('#sheet'); if (s) s.remove(); }); await tab(p, 'capital'); t = await text(p);
  ok(/Investor Ivy/.test(t) && /94,000/.test(t) && /Contribution/.test(t), 'capital balances and entries shown'); await p.click('[data-act=pt_capnew]'); await wait(p, 300);
  await p.selectOption('#ck_p', '2'); await p.selectOption('#ck_k', 'return_of_capital'); await p.fill('#ck_a', '999999'); await p.evaluate(() => { window.__ERR44 = { fn: 'partner_capital_add', msg: 'exceeds_capital' }; }); await p.click('[data-act=pt_capsave]'); await wait(p, 400);
  ok(/More than the capital held/.test(await text(p)), 'friendly error for returning more than the capital'); await p.fill('#ck_a', '1000'); await p.click('[data-act=pt_capsave]'); await wait(p, 500);
  c = await calls(p, 'partner_capital_add'); ok(c.length === 2 && c[1].p_amount === 1000 && c[1].p_kind === 'return_of_capital' && c[1].p_agr === 10, 'capital entry sent');
  await p.click('[data-act=pt_capvoid] >> nth=0'); await wait(p, 400); c = await calls(p, 'partner_capital_void'); ok(c.length === 1 && c[0].p_reason === 'reason text', 'void asks for a reason'); await noOverflow(p, 'capital');

  // ---- statement + print
  await tab(p, 'stmt'); await p.selectOption('#pst_p', '2'); await p.click('[data-act=pt_stmtgo]'); await wait(p, 500);
  c = await calls(p, 'partner_party_statement'); ok(c.length === 1 && c[0].p_party === 2 && c[0].p_from && c[0].p_to, 'statement requested'); t = await text(p);
  ok(/Investor Ivy/.test(t) && /Still owed/.test(t) && /chq-1/.test(t), 'statement shows the party, the payments and what is still owed'); await p.click('[data-act=pt_print]'); await wait(p, 200);
  ok(await p.evaluate(() => window.__PRINTED === 1), 'print button calls print'); await noOverflow(p, 'statement'); await p.screenshot({ path: SP + '/pt_stmt.png', fullPage: true });

  // ---- Bangla view: no raw keys, no overflow
  const pb = await open('#/partners', { lang: 'bn' }); t = await text(pb); ok(/অংশীদারি|পুঁজি/.test(t) && !/undefined|\[object/.test(t), 'Bangla page renders cleanly'); await noOverflow(pb, 'bn overview');
  for (const k of ['parties', 'ventures', 'deeds', 'calc', 'settle', 'capital', 'stmt']) { await tab(pb, k); t = await text(pb); ok(!/undefined|\[object|NaN/.test(t), 'bn ' + k + ' has no raw values'); await noOverflow(pb, 'bn ' + k); }
  await pb.screenshot({ path: SP + '/pt_bn.png', fullPage: true });

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
