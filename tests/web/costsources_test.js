// Step C-2ক: cost sources + allocation page (#/costsources): status (বিল বাকি / ভাগ নির্ধারিত নয় / অভাগিত / duplicates), sources (a NEW location is in the picker with no code change),
// rules (blank values allowed, live percent total, approval by another person explained), bills (readings only when the rule needs them), void / duplicate ack / allocate again,
// no access without the cost right, 360px phone width, Bangla.
// Run: node costsources_test.js <abs tests/web dir> [shots dir]     (serves ../../web of THIS checkout and injects the script tag)
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/s10_common.js');
const WEB = _P.WEB_DIR; const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = _P.freePort();
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from((b.toString('utf8').includes('src="costsources.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="costsources.js"></script></body>')));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const ym = new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 7);
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.cost_source_types = [['electricity', 'বিদ্যুৎ', 'Electricity'], ['gas', 'গ্যাস', 'Gas'], ['rent', 'ঘর ভাড়া', 'Rent'], ['other', '☐ অন্য: ______', 'Other: ______']].map((t) => ({ code: t[0], label_bn: t[1], label_en: t[2], active: true }));
  T.cost_sources = [{ id: 1, code: 'src-1', cost_type: 'electricity', provider: 'main meter', kind: 'shared', dest: null, frequency: 'monthly', effective_from: ym + '-01', active: true },
                    { id: 2, code: 'src-2', cost_type: 'gas', provider: null, kind: 'separate', dest: 'factory', frequency: 'monthly', effective_from: ym + '-01', active: true }];
  T.cost_source_locs = [{ source_id: 1, location_id: 1 }, { source_id: 1, location_id: 5 }, { source_id: 1, location_id: 9 }, { source_id: 2, location_id: 5 }];
  T.cost_source_rules = [{ id: 11, source_id: 1, method: 'sub_meter', effective_from: ym + '-01', status: 'approved', complete: true }, { id: 12, source_id: 1, method: 'fixed_percent', effective_from: ym + '-01', status: 'draft', complete: false }];
  T.cost_source_rule_shares = [{ id: 1, rule_id: 11, location_id: 5, dest: 'factory', value: null }, { id: 2, rule_id: 11, location_id: 1, dest: 'showroom', value: null }, { id: 3, rule_id: 12, location_id: 5, dest: 'factory', value: 50 }, { id: 4, rule_id: 12, location_id: 1, dest: 'showroom', value: null }];
  T.cost_source_bills = [{ id: 21, source_id: 1, period_kind: 'month', period_month: ym + '-01', amount: 10000, bill_no: 'E-1', one_off: false, status: 'active', dup_entry_id: null, dup_ack: false },
                         { id: 22, source_id: 2, period_kind: 'month', period_month: ym + '-01', amount: 2500, bill_no: 'G-1', one_off: false, status: 'active', dup_entry_id: 'e9', dup_ack: false }];
  T.cost_bill_shares = [{ id: 1, bill_id: 21, kind: 'unallocated', amount: 10000, flag: 'meter_missing', active: true }, { id: 2, bill_id: 22, kind: 'share', location_id: 5, dest: 'factory', amount: 2500, active: true }];
  return data;
}
const STAT = { month: ym + '-01', bills_pending: [{ source_id: 2, label_bn: 'বিল বাকি' }], split_not_set: [{ source_id: 1, label_bn: 'ভাগ নির্ধারিত নয়' }], unallocated: [{ bill_id: 21, source_id: 1, amount: 10000, flag: 'meter_missing' }], duplicates: [{ bill_id: 22, source_id: 2, amount: 2500 }] };
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.wb = Object.assign({ err: {}, stat: null }, window.__WB || {});
 c.rpc = async (fn, args) => {
  if (!/^(cost_|branch_overhead)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === 'cost_pick_locations') return { data: [{ id: 1, code: 'main', name_bn: 'মেইন শোরুম', name_en: 'Main showroom', kind: 'showroom' }, { id: 5, code: 'fac', name_bn: 'মিষ্টি কারখানা', name_en: 'Sweet factory', kind: 'factory' }, { id: 9, code: 'new', name_bn: 'নতুন জায়গা', name_en: 'Brand new site', kind: 'factory' }], error: null };
  if (fn === 'cost_sources_status') return { data: clone(W.stat), error: null };
  if (fn === 'cost_source_save') { T.cost_sources.push({ id: 30, code: 'src-30', cost_type: args.p_type, provider: args.p_provider, kind: args.p_kind, dest: args.p_dest, frequency: args.p_frequency, effective_from: args.p_effective, active: true }); args.p_locs.forEach((l) => T.cost_source_locs.push({ source_id: 30, location_id: l })); return { data: { id: 30 }, error: null }; }
  if (fn === 'cost_source_type_add') return { data: { code: 'y1' }, error: null };
  if (fn === 'cost_rule_save') return { data: { id: 40, status: 'draft' }, error: null };
  if (fn === 'cost_rule_approve') { const r = T.cost_source_rules.find((x) => x.id === args.p_rule); if (r) r.status = 'approved'; return { data: { approved: true }, error: null }; }
  if (fn === 'cost_bill_add') return { data: { id: 50, shares: [], unallocated: 0 }, error: null };
  return { data: null, error: null }; };
 return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('a reason'));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__WB=${JSON.stringify(Object.assign({ stat: STAT }, o.w || {}))};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => { const w = window.innerWidth; const out = []; document.querySelectorAll('body *').forEach((e) => { const b = e.getBoundingClientRect(); if (b.width && b.right > w + 1) out.push(e.tagName + '.' + String(e.className).slice(0, 20) + ' r=' + Math.round(b.right)); }); return { ok: document.documentElement.scrollWidth <= w + 1, out: out.slice(0, 5) }; }); ok(r.ok, 'horizontal overflow ' + m + ' ' + JSON.stringify(r)); };

  let p = await open({ owner: false, m: { grants: [] } }, '#/costsources');
  ok(/cost right is needed/.test(await p.textContent('#cb_body')) && await p.locator('[data-act=cb_tab]').count() === 0, 'no cost right: nothing is shown'); await p.close();

  // ---- status
  p = await open({}, '#/costsources');
  ok(await p.locator('[data-act=cb_tab]').count() === 4, 'four tabs');
  const st = await p.textContent('#cb_pane');
  ok(/Bill pending/.test(st) && /Split not set/.test(st) && /Unallocated/.test(st) && /10-2 voucher/.test(st), 'status shows the four lists');
  ok(/src-2/.test(st) && /src-1/.test(st), 'sources named by code + type');
  await p.click('[data-act=cb_ack]'); await wait(p, 300); const ak = await calls(p, 'cost_bill_dup_ack'); ok(ak.length === 1 && ak[0].p_bill === 22 && ak[0].p_note === 'a reason', 'acknowledging a duplicate sends the bill and the reason');
  await p.screenshot({ path: OUT + '/cb_status.png' }); await noOverflow(p, 'status'); await p.close();

  // ---- sources: a new location is there with no code change; shared -> several places
  p = await open({}, '#/costsources'); await p.click('[data-act=cb_tab][data-v=src]'); await wait(p, 200);
  ok(await p.locator('#cb_pane .card').count() === 3, 'two sources + the add card');
  await p.click('[data-act=cb_snew]'); await wait(p, 250);
  const locTxt = await p.textContent('#cs_locs'); ok(/Brand new site/.test(locTxt) && await p.locator('[data-cs-loc]').count() === 3, 'the new location is in the picker (read from the locations list)');
  ok(/Other: add a new type/.test(await p.locator('#cs_type option').last().textContent()), 'last type option is "Other: add a new type"');
  await p.selectOption('#cs_type', 'rent'); await p.selectOption('#cs_kind', 'shared'); await p.check('[data-cs-loc][value="5"]'); await p.check('[data-cs-loc][value="9"]'); await p.selectOption('#cs_freq', 'yearly');
  await p.click('[data-act=cb_ssave]'); await wait(p, 400);
  let c = await calls(p, 'cost_source_save'); ok(c.length === 1 && c[0].p_type === 'rent' && c[0].p_kind === 'shared' && c[0].p_dest === null && c[0].p_locs.join() === '5,9' && c[0].p_frequency === 'yearly' && typeof c[0].p_client === 'string', 'shared source over the old and the NEW place, with a client id');
  await p.click('[data-act=cb_snew]'); await wait(p, 250); await p.click('[data-act=cb_ssave]'); await wait(p, 200);
  ok(/Choose the places/.test(await p.textContent('#toast')) && (await calls(p, 'cost_source_save')).length === 1, 'no place chosen: stopped');
  await p.selectOption('#cs_type', '__new'); await p.check('[data-cs-loc][value="5"]'); await p.click('[data-act=cb_ssave]'); await wait(p, 400);
  c = await calls(p, 'cost_source_type_add'); ok(c.length === 1 && c[0].p_label_bn === 'a reason' && c[0].p_component_type === 'other', 'new type added by name (maps to a pool type on the server)');
  c = await calls(p, 'cost_source_save'); ok(c.length === 2 && c[1].p_type === 'y1' && c[1].p_kind === 'separate' && c[1].p_dest === 'factory' && c[1].p_locs.join() === '5', 'separate source: one place, destination');
  await p.screenshot({ path: OUT + '/cb_sources.png' }); await noOverflow(p, 'sources'); await p.close();

  // ---- rules
  p = await open({}, '#/costsources'); await p.click('[data-act=cb_tab][data-v=rule]'); await wait(p, 250);
  ok(/Draft/.test(await p.textContent('#cb_pane')) && /Approved/.test(await p.textContent('#cb_pane')) && /Incomplete/.test(await p.textContent('#cb_pane')), 'rules list: draft + approved, incomplete flagged');
  await p.click('[data-act=cb_rapp]'); await wait(p, 300); c = await calls(p, 'cost_rule_approve'); ok(c.length === 1 && c[0].p_rule === 12, 'approve sends the draft rule');
  await p.close();
  p = await open({ w: { err: { cost_rule_approve: 'self_approve_refused' } } }, '#/costsources'); await p.click('[data-act=cb_tab][data-v=rule]'); await wait(p, 250); await p.click('[data-act=cb_rapp]'); await wait(p, 300);
  ok(/cannot approve it/.test(await p.textContent('#toast')), 'entry person cannot approve: explained'); await p.close();
  p = await open({}, '#/costsources'); await p.click('[data-act=cb_tab][data-v=rule]'); await wait(p, 200); await p.click('[data-act=cb_rnew]'); await wait(p, 250);
  await p.selectOption('#cr_meth', 'fixed_percent'); await wait(p, 150);
  ok(await p.locator('#cr_grid [data-pair]').count() === 9, 'three places x three destinations to choose from (the new place included)');
  await p.check('[data-pair="5:factory"] [data-cr-on]'); await p.fill('[data-pair="5:factory"] [data-cr-val]', '60'); await p.check('[data-pair="1:showroom"] [data-cr-on]'); await p.fill('[data-pair="1:showroom"] [data-cr-val]', '٤٠'.replace(/٤/, '4').replace(/٠/, '0'));
  await p.locator('[data-pair="1:showroom"] [data-cr-val]').dispatchEvent('input'); await wait(p, 100);
  ok(/Total: 100/.test(await p.textContent('#cr_sum')) && /must total 100/.test(await p.textContent('#cr_sum')), 'live percent total');
  await p.check('[data-pair="9:admin"] [data-cr-on]'); await p.locator('[data-pair="9:admin"] [data-cr-on]').dispatchEvent('change'); await wait(p, 100);
  ok(/Incomplete ×1/.test(await p.textContent('#cr_sum')), 'a place without a value stays blank and is counted as incomplete (nothing guessed)');
  await p.screenshot({ path: OUT + '/cb_rule.png' }); await noOverflow(p, 'rule sheet');
  await p.click('[data-act=cb_rsave]'); await wait(p, 400);
  c = await calls(p, 'cost_rule_save'); ok(c.length === 1 && c[0].p_method === 'fixed_percent' && c[0].p_shares.length === 3 && c[0].p_shares.find((s) => s.location_id === 9).value === null && c[0].p_shares.find((s) => s.location_id === 5).value === 60 && typeof c[0].p_client === 'string', 'rule saved with blank value as null, typed values as numbers, client id');
  await p.close();
  p = await open({ w: { err: { cost_rule_save: 'percent_not_100' } } }, '#/costsources'); await p.click('[data-act=cb_tab][data-v=rule]'); await wait(p, 200); await p.click('[data-act=cb_rnew]'); await wait(p, 250);
  await p.selectOption('#cr_meth', 'fixed_percent'); await p.check('[data-pair="5:factory"] [data-cr-on]'); await p.fill('[data-pair="5:factory"] [data-cr-val]', '60'); await p.check('[data-pair="1:showroom"] [data-cr-on]'); await p.fill('[data-pair="1:showroom"] [data-cr-val]', '30');
  await p.click('[data-act=cb_rsave]'); await wait(p, 300); ok(/do not total 100/.test(await p.textContent('#toast')), 'the server refusal (not 100) is shown'); await p.close();

  // ---- bills
  p = await open({}, '#/costsources'); await p.click('[data-act=cb_tab][data-v=bill]'); await wait(p, 250);
  const bt = await p.textContent('#cb_pane'); ok(/#21/.test(bt) && /#22/.test(bt) && /Unallocated/.test(bt) && /10-2 voucher/.test(bt) && /৳ 2,500/.test(bt), 'bills with shares, unallocated chip and duplicate chip');
  await p.click('[data-act=cb_bnew]'); await wait(p, 250);
  ok(await p.locator('[data-bi]').count() === 2, 'the source in force needs readings (sub-meter): two boxes, none typed');
  await p.fill('#cb_amt', '1,000'.replace(',', '')); await p.fill('[data-bi="5:factory"]', '300'); await p.fill('#cb_no', 'E-9'); await p.check('#cb_one');
  await p.click('[data-act=cb_bsave]'); await wait(p, 400);
  c = await calls(p, 'cost_bill_add'); ok(c.length === 1 && c[0].p_source === 1 && c[0].p_amount === 1000 && c[0].p_bill_no === 'E-9' && c[0].p_one_off === true && c[0].p_inputs.length === 1 && c[0].p_inputs[0].dest === 'factory' && c[0].p_period_kind === 'month' && /-01$/.test(c[0].p_month) && typeof c[0].p_client === 'string', 'bill sent with only the typed reading, one-off flag, client id');
  await p.click('[data-act=cb_bnew]'); await wait(p, 250); await p.click('[data-act=cb_bsave]'); await wait(p, 200); ok(/Write the amount/.test(await p.textContent('#toast')), 'no amount: stopped');
  await p.selectOption('#cb_src', '2'); await wait(p, 150); ok(await p.locator('[data-bi]').count() === 0, 'a separate source needs no readings');
  await p.close();
  p = await open({}, '#/costsources'); await p.click('[data-act=cb_tab][data-v=bill]'); await wait(p, 250);
  await p.click('[data-act=cb_realloc][data-id="21"]'); await wait(p, 300); ok(await p.locator('#cb_rinputs [data-bi]').count() === 2, 'allocate again asks for the missing readings');
  await p.fill('#cb_rinputs [data-bi="5:factory"]', '300'); await p.fill('#cb_rinputs [data-bi="1:showroom"]', '700'); await p.click('[data-act=cb_rgo]'); await wait(p, 300);
  c = await calls(p, 'cost_bill_reallocate'); ok(c.length === 1 && c[0].p_bill === 21 && c[0].p_inputs.length === 2, 'readings sent with the bill');
  await p.click('[data-act=cb_bvoid][data-id="22"]'); await wait(p, 300); c = await calls(p, 'cost_bill_void'); ok(c.length === 1 && c[0].p_bill === 22 && c[0].p_note === 'a reason', 'void needs and sends a reason');
  await p.screenshot({ path: OUT + '/cb_bills.png' }); await noOverflow(p, 'bills'); await p.close();

  // ---- Bangla
  p = await open({ lang: 'bn' }, '#/costsources');
  ok(/বিল/.test(await p.textContent('#cb_pane')) && /ভাগ/.test(await p.textContent('#cb_pane')) && /[\u0980-\u09FF]{3}/.test(await p.textContent('#cb_pane')), 'Bangla status labels');
  await p.screenshot({ path: OUT + '/cb_bn.png' }); await noOverflow(p, 'Bangla status'); await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
