// Step C-2খ: cost attribution page (#/costattrib): where showroom / admin cost shares are charged (per place, per cost type, from a month), main centre, cost view with the
// reason of every re-assignment, history, the owner switches in plain words, the "give approval to someone else" suggestion, and the same suggestion on the delegation board.
// No access without the cost right, view-only holders cannot change anything, 360px phone width, Bangla.
// Run: node costattrib_test.js <abs tests/web dir> [shots dir]     (serves ../../web of THIS checkout and injects the script tag)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const WEB = path.join(SP, '..', '..', 'web'); const OUT = process.argv[3] || SP;
const base = C.baseData(SP), PORT = 8378;
const srv = http.createServer((q, r) => { const u = q.url.split('?')[0]; const f = path.join(WEB, u === '/' ? 'index.html' : u);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
    if (u === '/' || u === '/index.html') b = Buffer.from((b.toString('utf8').includes('src="costattrib.js"') ? b.toString('utf8') : b.toString('utf8').replace('</body>', '<script src="costattrib.js"></script></body>')));
    const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const ym = new Date(Date.now() + 6 * 3600e3).toISOString().slice(0, 7);
const nx = (() => { const d = new Date(Date.now() + 6 * 3600e3); d.setUTCDate(1); d.setUTCMonth(d.getUTCMonth() + 1); return d.toISOString().slice(0, 7); })();
const LOCS = [{ id: 1, code: 'main', name_bn: 'মেইন শোরুম', name_en: 'Main showroom', kind: 'showroom' }, { id: 2, code: 'br2', name_bn: 'দ্বিতীয় শোরুম', name_en: 'Second showroom', kind: 'showroom' }, { id: 9, code: 'new', name_bn: 'নতুন শোরুম', name_en: 'Brand new shop', kind: 'showroom' }];
function mk(o = {}) {
  const data = C.mkData(base, o); const T = data.tables;
  T.rules.push({ key: 'cost_attrib_in_pl', module: 'stock', kind: 'switch', value: null, default_value: false, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 },
    { key: 'recipe_approval_required', module: 'stock', kind: 'choice', value: null, default_value: 'off', label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 },
    { key: 'production_requires_recipe', module: 'stock', kind: 'switch', value: null, default_value: false, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 1 });
  T.cost_source_types = [['internet', 'ইন্টারনেট', 'Internet'], ['water', 'পানি', 'Water']].map((t) => ({ code: t[0], label_bn: t[1], label_en: t[2], active: true }));
  T.location_cost_attribution = [
    { id: 3, location_id: 1, cost_type: null, dest: 'main_centre', effective_from: nx + '-01', active: true, reason: 'from next month', prev_dest: 'showroom', created_at: ym + '-02T00:00:00Z' },
    { id: 2, location_id: 2, cost_type: 'water', dest: 'main_centre', effective_from: ym + '-01', active: true, reason: null, prev_dest: null, created_at: ym + '-01T00:00:00Z' },
    { id: 1, location_id: 1, cost_type: null, dest: 'showroom', effective_from: ym + '-01', active: true, reason: null, prev_dest: null, created_at: ym + '-01T00:00:00Z' },
    { id: 0, location_id: 9, cost_type: null, dest: 'unallocated', effective_from: ym + '-01', active: false, reason: 'old', prev_dest: null, retired_reason: 'replaced', created_at: ym + '-01T00:00:00Z' }];
  T.cost_attrib_main = [{ id: 1, location_id: 1, effective_from: ym + '-01', active: true }];
  T.cost_share_reassign = [{ id: 1, share_id: 7, bill_id: 3, share_loc: 1, cost_type: 'internet', period_month: ym + '-01', amount: 1200, from_kind: 'location', from_loc: 1, to_kind: 'location', to_loc: 2, reason: 'serves the second showroom', locked_override: false, created_at: ym + '-03T00:00:00Z' },
                           { id: 2, share_id: 8, bill_id: 4, share_loc: 1, cost_type: 'water', period_month: ym + '-01', amount: 400, from_kind: 'location', from_loc: 1, to_kind: 'main_centre', to_loc: null, reason: 'closed month fix', locked_override: true, created_at: ym + '-04T00:00:00Z' }];
  T.profiles = [{ id: 'u-e', staff_id: 'st-e', full_name: 'Entry Person', status: 'active' }, { id: 'u-a', staff_id: 'st-a', full_name: 'Approver Person', status: 'active' }];
  T.grant_defs = [{ grant_code: 'cost_bill_entry', label_bn: 'খরচের বিল লেখা', label_en: 'Enter cost bills', sort: 1, module: 'cost', window_type: 'window' }, { grant_code: 'cost_rule_approve', label_bn: 'ভাগের নিয়ম অনুমোদন', label_en: 'Approve rule', sort: 2, module: 'cost', window_type: 'window' }];
  T.user_grants = [];
  return data;
}
const VIEW = { month: ym + '-01', location_id: null, in_pl: false, main_centre_location: 1, totals: [{ dest_kind: 'location', dest_location: 1, amount: 1700 }, { dest_kind: 'location', dest_location: 2, amount: 1200 }, { dest_kind: 'main_centre', dest_location: 1, amount: 500 }, { dest_kind: 'unallocated', dest_location: null, amount: 1000 }],
  rows: [{ share_id: 7, bill_id: 3, source: 'src-1', cost_type: 'internet', type_bn: 'ইন্টারনেট', type_en: 'Internet', share_location: 1, share_dest: 'showroom', amount: 1200, dest_kind: 'location', dest_location: 2, via: 'reassigned', reassigned: true, reason: 'serves the second showroom', locked_override: false },
         { share_id: 9, bill_id: 4, source: 'src-2', cost_type: 'water', type_bn: 'পানি', type_en: 'Water', share_location: 2, share_dest: 'admin', amount: 200, dest_kind: 'main_centre', dest_location: 1, via: 'setting', reassigned: false, reason: null, locked_override: false },
         { share_id: 10, bill_id: 5, source: 'src-3', cost_type: 'licence_fee', type_bn: 'লাইসেন্স ও ফি', type_en: 'Licence', share_location: 2, share_dest: 'showroom', amount: 1000, dest_kind: 'unallocated', dest_location: null, via: 'default', reassigned: false, reason: null, locked_override: true }] };
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const T = window.__DATA.tables; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const W = M.wb = Object.assign({ err: {}, view: null, hint: { suggest: true, blocking: false, message_bn: 'অন্য কাউকে অনুমোদনের দায়িত্ব দেওয়া ভালো — একই ব্যক্তি এন্ট্রি ও অনুমোদন দুটোই করলে ঝুঁকি', message_en: 'Better to give the approval to someone else' }, both: [] }, window.__WB || {});
 c.rpc = async (fn, args) => {
  if (!/^(cost_|branch_cost_view|grant_separation|set_rule|set_user_grant)/.test(fn)) return rpc(fn, args);
  M.calls.push([fn, clone(args || {})]);
  if (W.err[fn]) return { data: null, error: { message: W.err[fn], code: 'P0001' } };
  if (fn === 'cost_pick_locations') return { data: ${JSON.stringify(LOCS)}, error: null };
  if (fn === 'branch_cost_view') return { data: clone(W.view), error: null };
  if (fn === 'grant_separation_hint') return { data: clone(W.hint), error: null };
  if (fn === 'grant_separation_report') return { data: clone(W.both), error: null };
  if (fn === 'set_rule') { const r = T.rules.find((x) => x.key === args.p_key); if (r) r.value = args.p_value; return { data: null, error: null }; }
  if (fn === 'set_user_grant') return { data: null, error: null };
  if (fn === 'cost_attrib_set') return { data: { id: 50 }, error: null };
  if (fn === 'cost_attrib_main_set') return { data: { id: 51 }, error: null };
  if (fn === 'cost_share_reassign') return { data: { id: 52 }, error: null };
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
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__M0=${JSON.stringify(o.m || {})};window.__WB=${JSON.stringify(Object.assign({ view: VIEW }, o.w || {}))};${o.owner === false ? 'window.__OWNER=false;window.__PERMS={};' : ''}try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1100); return p;
  }
  const wait = (p, t = 250) => p.waitForTimeout(t);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => { const r = await p.evaluate(() => { const w = window.innerWidth; const out = []; document.querySelectorAll('body *').forEach((e) => { const b = e.getBoundingClientRect(); if (b.width && b.right > w + 1) out.push(e.tagName + '.' + e.className); }); return { sw: document.documentElement.scrollWidth, w, out: out.slice(0, 4) }; }); ok(r.sw <= r.w + 1, 'no horizontal overflow: ' + m + ' ' + JSON.stringify(r)); };
  const txt = (p, s) => p.textContent(s);

  // ---- no cost right
  let p = await open({ owner: false, m: { grants: [] } }, '#/costattrib');
  ok(/cost right is needed/.test(await txt(p, '#ca_body')) && await p.locator('[data-act=ca_tab]').count() === 0, 'no cost right: nothing is shown'); await p.close();

  // ---- view-only holder: reads, cannot change
  p = await open({ owner: false, m: { grants: ['view_cost'] } }, '#/costattrib');
  ok(await p.locator('[data-act=ca_tab]').count() === 4 && await p.locator('[data-act=ca_set]').count() === 0 && await p.locator('[data-act=ca_main]').count() === 0, 'view-only: options are shown but no change buttons');
  await p.click('[data-act=ca_tab][data-v=view]'); await wait(p, 200); ok(await p.locator('[data-act=ca_re]').count() === 0 && /Internet/.test(await txt(p, '#ca_pane')), 'view-only: the cost view is readable, no move button');
  await p.click('[data-act=ca_tab][data-v=rules]'); await wait(p, 200); ok(/owner only/.test(await txt(p, '#ca_pane')) && await p.locator('[data-act=ca_sw]').count() === 0, 'switches and suggestion are owner-only'); await p.close();

  // ---- options
  p = await open({}, '#/costattrib');
  let t = await txt(p, '#ca_pane');
  ok(await p.locator('.card[data-loc]').count() === 3, 'one card per place, the new place included (read from the locations list)');
  ok(/Brand new shop/.test(t) && /Not set/.test(t), 'the new place is there and says "not set — charged nowhere"');
  ok(/Charge to this showroom/.test(t) && /Keep at the main centre/.test(t) && /Upcoming/.test(t), 'current choice and the upcoming (next month) choice are both shown');
  ok(/Main showroom/.test(await txt(p, '#ca_pane .card:nth-child(2)')), 'main centre card names the chosen place');
  await p.click('[data-act=ca_set][data-loc="2"]'); await wait(p, 250);
  ok(await p.locator('input[name=ca_dest]').count() === 3 && /earlier months never change/.test(await txt(p, '#sheet, .sheet, dialog, body')), 'three destinations + the "earlier months never change" note');
  await p.selectOption('#ca_type', 'internet'); await p.check('input[name=ca_dest][value=main_centre]'); await p.click('[data-act=ca_save]'); await wait(p, 300);
  let c = await calls(p, 'cost_attrib_set'); ok(c.length === 1 && c[0].p_loc === 2 && c[0].p_cost_type === 'internet' && c[0].p_dest === 'main_centre' && c[0].p_effective === ym + '-01' && c[0].p_reason === null && typeof c[0].p_client === 'string', 'a first choice for a (place, type) needs no reason and is sent from this month with a client id');
  await p.click('[data-act=ca_set][data-loc="1"]'); await wait(p, 250); await p.click('[data-act=ca_save]'); await wait(p, 200);
  ok(/reason is needed/.test(await txt(p, '#toast')) && (await calls(p, 'cost_attrib_set')).length === 1, 'changing an existing choice without a reason is stopped');
  await p.fill('#ca_why', 'owner decided'); await p.fill('#ca_from', nx); await p.check('input[name=ca_dest][value=unallocated]'); await p.click('[data-act=ca_save]'); await wait(p, 300);
  c = await calls(p, 'cost_attrib_set'); ok(c.length === 2 && c[1].p_loc === 1 && c[1].p_cost_type === null && c[1].p_dest === 'unallocated' && c[1].p_effective === nx + '-01' && c[1].p_reason === 'owner decided', 'a change from next month with its reason');
  await p.close();
  p = await open({ w: { err: { cost_attrib_set: 'effective_in_past' } } }, '#/costattrib'); await p.click('[data-act=ca_set][data-loc="9"]'); await wait(p, 250); await p.click('[data-act=ca_save]'); await wait(p, 300);
  ok(/earlier month cannot be changed/.test(await txt(p, '#toast')), 'the server refusal "earlier month" is shown in words'); await p.close();
  p = await open({ w: { err: { cost_attrib_set: 'period_closed' } } }, '#/costattrib'); await p.click('[data-act=ca_set][data-loc="9"]'); await wait(p, 250); await p.click('[data-act=ca_save]'); await wait(p, 300);
  ok(/closed/.test(await txt(p, '#toast')), 'closed month refused for non-owner: explained'); await p.close();
  p = await open({}, '#/costattrib'); await p.click('[data-act=ca_retire]:first-of-type'); await wait(p, 300);
  c = await calls(p, 'cost_attrib_retire'); ok(c.length === 1 && c[0].p_reason === 'a reason' && typeof c[0].p_id === 'number', 'take-back sends the id and a reason');
  await p.click('[data-act=ca_main]'); await wait(p, 250); await p.selectOption('#cm_loc', '2'); await p.fill('#cm_why', 'moved the head office'); await p.click('[data-act=ca_main_save]'); await wait(p, 300);
  c = await calls(p, 'cost_attrib_main_set'); ok(c.length === 1 && c[0].p_loc === 2 && c[0].p_effective === ym + '-01' && c[0].p_reason === 'moved the head office', 'main centre place saved with its reason');
  await p.click('[data-act=ca_main]'); await wait(p, 250); await p.selectOption('#cm_loc', ''); await p.click('[data-act=ca_main_save]'); await wait(p, 300);
  c = await calls(p, 'cost_attrib_main_set'); ok(c.length === 2 && c[1].p_loc === null, 'main centre can be "no place" (blank sent as null, nothing guessed)');
  await p.screenshot({ path: OUT + '/ca_options.png' }); await noOverflow(p, 'options'); await p.close();

  // ---- cost view
  p = await open({}, '#/costattrib'); await p.click('[data-act=ca_tab][data-v=view]'); await wait(p, 250);
  t = await txt(p, '#ca_pane');
  ok(/৳ 1,700/.test(t) && /৳ 500/.test(t) && /৳ 1,000/.test(t) && /Totals by destination/.test(t), 'totals by destination');
  ok(/Not in the P&L yet/.test(t), 'tells that the switch is off');
  ok(await p.locator('[data-share]').count() === 3 && /moved by hand/.test(t) && /by setting/.test(t) && /nothing set/.test(t), 'three shares with how each destination was decided');
  ok(/serves the second showroom/.test(t) && /closed month changed/.test(t), 'the reason of a hand move and the closed-month flag are visible');
  let vc = await calls(p, 'branch_cost_view'); ok(vc.length >= 1 && vc[vc.length - 1].p_month === ym + '-01' && vc[vc.length - 1].p_loc === null, 'view asks for this month, all places');
  await p.selectOption('#ca_floc', '2'); await wait(p, 300); vc = await calls(p, 'branch_cost_view'); ok(vc[vc.length - 1].p_loc === 2, 'place filter sent to the server');
  await p.fill('#ca_month', nx); await p.locator('#ca_month').dispatchEvent('change'); await wait(p, 300); vc = await calls(p, 'branch_cost_view'); ok(vc[vc.length - 1].p_month === nx + '-01', 'month filter sent to the server');
  await p.screenshot({ path: OUT + '/ca_view.png' }); await noOverflow(p, 'cost view');
  await p.click('[data-act=ca_re][data-id="9"]'); await wait(p, 250);
  await p.click('[data-act=ca_re_save]'); await wait(p, 200); ok(/Choose/.test(await txt(p, '#toast')) && (await calls(p, 'cost_share_reassign')).length === 0, 'no target: stopped');
  await p.selectOption('#cr_to', 'loc:9'); await p.click('[data-act=ca_re_save]'); await wait(p, 200); ok(/reason is needed/.test(await txt(p, '#toast')) && (await calls(p, 'cost_share_reassign')).length === 0, 'no reason: stopped on the phone before it reaches the server');
  await p.fill('#cr_why', 'ab'); await p.click('[data-act=ca_re_save]'); await wait(p, 200); ok((await calls(p, 'cost_share_reassign')).length === 0, 'a 2-letter reason is stopped too');
  await p.fill('#cr_why', 'belongs to the new shop'); await p.click('[data-act=ca_re_save]'); await wait(p, 300);
  c = await calls(p, 'cost_share_reassign'); ok(c.length === 1 && c[0].p_share === 9 && c[0].p_to_kind === 'location' && c[0].p_to_loc === 9 && c[0].p_reason === 'belongs to the new shop' && typeof c[0].p_client === 'string', 'move to another showroom: share, target place, reason');
  await p.click('[data-act=ca_re][data-id="9"]'); await wait(p, 250); await p.selectOption('#cr_to', 'main_centre'); await p.fill('#cr_why', 'keep at the head office'); await p.click('[data-act=ca_re_save]'); await wait(p, 300);
  c = await calls(p, 'cost_share_reassign'); ok(c.length === 2 && c[1].p_to_kind === 'main_centre' && c[1].p_to_loc === null, 'move to the main centre');
  await p.click('[data-act=ca_re][data-id="9"]'); await wait(p, 250); await p.selectOption('#cr_to', 'unallocated'); await p.fill('#cr_why', 'leave it out'); await p.click('[data-act=ca_re_save]'); await wait(p, 300);
  c = await calls(p, 'cost_share_reassign'); ok(c.length === 3 && c[2].p_to_kind === 'unallocated', 'move to unallocated'); await p.close();
  p = await open({ w: { err: { cost_share_reassign: 'period_closed' } } }, '#/costattrib'); await p.click('[data-act=ca_tab][data-v=view]'); await wait(p, 200); await p.click('[data-act=ca_re][data-id="9"]'); await wait(p, 250);
  await p.selectOption('#cr_to', 'loc:1'); await p.fill('#cr_why', 'late fix'); await p.click('[data-act=ca_re_save]'); await wait(p, 300); ok(/closed/.test(await txt(p, '#toast')), 'closed month: refusal explained'); await p.close();
  p = await open({ w: { err: { cost_share_reassign: 'same_destination' } } }, '#/costattrib'); await p.click('[data-act=ca_tab][data-v=view]'); await wait(p, 200); await p.click('[data-act=ca_re][data-id="9"]'); await wait(p, 250);
  await p.selectOption('#cr_to', 'loc:1'); await p.fill('#cr_why', 'same place'); await p.click('[data-act=ca_re_save]'); await wait(p, 300); ok(/already there/.test(await txt(p, '#toast')), 'same destination: explained'); await p.close();
  p = await open({ w: { view: Object.assign({}, VIEW, { in_pl: true }) } }, '#/costattrib'); await p.click('[data-act=ca_tab][data-v=view]'); await wait(p, 200); ok(/Included in the P&L/.test(await txt(p, '#ca_pane')), 'switch on: the page says the shares are in the P&L'); await p.close();

  // ---- history
  p = await open({}, '#/costattrib'); await p.click('[data-act=ca_tab][data-v=hist]'); await wait(p, 250); t = await txt(p, '#ca_pane');
  ok(/serves the second showroom/.test(t) && /closed month fix/.test(t) && /closed month changed/.test(t), 'history lists the hand moves with reasons and the closed-month flag');
  ok(/was: Charge to this showroom/.test(t) && /replaced \/ taken back/.test(t) && /from next month/.test(t), 'history of choices shows the previous value, the replaced rows and the reasons');
  await p.screenshot({ path: OUT + '/ca_hist.png' }); await noOverflow(p, 'history'); await p.close();

  // ---- rules & duty (owner)
  p = await open({}, '#/costattrib'); await p.click('[data-act=ca_tab][data-v=rules]'); await wait(p, 250); t = await txt(p, '#ca_pane');
  ok(/Show cost shares in the branch P&L/.test(t) && /Off \(as today\)/.test(t) && /Recipe approval/.test(t) && /Recipe required for production/.test(t) && /Costing method per place/.test(t), 'the four switches are explained in words');
  ok(await p.locator('a[href="#/costing"]').count() === 1, 'costing method per place points to the costing page');
  await p.click('[data-act=ca_sw][data-k=cost_attrib_in_pl]'); await wait(p, 300); let s = await calls(p, 'set_rule'); ok(s.length === 1 && s[0].p_key === 'cost_attrib_in_pl' && s[0].p_value === true, 'P&L switch turned on (explicit)');
  await p.click('[data-act=ca_rec][data-v=warn]'); await wait(p, 300); s = await calls(p, 'set_rule'); ok(s.length === 2 && s[1].p_key === 'recipe_approval_required' && s[1].p_value === 'warn', 'recipe approval: warn is selectable');
  await p.click('[data-act=ca_rec][data-v=on]'); await wait(p, 300); s = await calls(p, 'set_rule'); ok(s[2].p_value === 'on', 'recipe approval: required is selectable');
  await p.click('[data-act=ca_sw][data-k=production_requires_recipe]'); await wait(p, 300); s = await calls(p, 'set_rule'); ok(s[3].p_key === 'production_requires_recipe' && s[3].p_value === true, 'production-needs-recipe switch');
  await p.selectOption('#ca_hp', 'u-e'); await p.selectOption('#ca_hg', 'cost_rule_approve'); await p.click('[data-act=ca_hint]'); await wait(p, 300);
  let h = await calls(p, 'grant_separation_hint'); ok(h.length === 1 && h[0].p_user === 'u-e' && h[0].p_grant === 'cost_rule_approve', 'the suggestion is asked for (person, right)');
  ok(/অন্য কাউকে অনুমোদনের দায়িত্ব দেওয়া ভালো|Better to give the approval to someone else/.test(await txt(p, '#ca_hintbox')) && /advice only/.test(await txt(p, '#ca_hintbox')), 'the suggestion is shown, marked as advice only');
  await p.screenshot({ path: OUT + '/ca_rules.png' }); await noOverflow(p, 'rules'); await p.close();
  p = await open({ w: { hint: { suggest: false, blocking: false }, both: [{ user_id: 'u-e', pair: 'cost_rules', label_bn: 'খরচের বিল / ভাগের নিয়ম লেখা ও অনুমোদন', label_en: 'Cost bill / allocation rule entry and approval' }] } }, '#/costattrib');
  await p.click('[data-act=ca_tab][data-v=rules]'); await wait(p, 250); ok(/Entry Person/.test(await txt(p, '#ca_pane')), 'people who hold both sides are listed');
  await p.selectOption('#ca_hp', 'u-a'); await p.selectOption('#ca_hg', 'cost_bill_entry'); await p.click('[data-act=ca_hint]'); await wait(p, 300); ok(/No risk seen/.test(await txt(p, '#ca_hintbox')), 'no suggestion when the same person would not hold both'); await p.close();

  // ---- the same suggestion where rights are given (delegation board)
  p = await open({}, '#/delegation'); await wait(p, 400); await p.click('#dg_body summary');
  await p.selectOption('#dg_p', 'u-e'); await p.selectOption('#dg_c', 'cost_rule_approve'); await p.click('[data-act=dg_add]'); await wait(p, 500);
  h = await calls(p, 'grant_separation_hint'); ok(h.length === 1 && h[0].p_user === 'u-e' && h[0].p_grant === 'cost_rule_approve', 'delegation board: after giving a right the suggestion is asked for');
  ok(await p.locator('#dg_hint').count() === 1 && /অন্য কাউকে অনুমোদনের দায়িত্ব|Better to give the approval/.test(await txt(p, '#dg_hint')), 'delegation board: the suggestion is shown (right already given, never blocked)');
  const gs = await calls(p, 'set_user_grant'); ok(gs.length === 1 && gs[0].p_allowed === true, 'the grant itself went through');
  await p.screenshot({ path: OUT + '/ca_deleg.png' }); await noOverflow(p, 'delegation'); await p.close();
  p = await open({ w: { hint: { suggest: false, blocking: false } } }, '#/delegation'); await wait(p, 400); await p.click('#dg_body summary');
  await p.selectOption('#dg_p', 'u-a'); await p.selectOption('#dg_c', 'cost_bill_entry'); await p.click('[data-act=dg_add]'); await wait(p, 500);
  ok(await p.locator('#dg_hint').count() === 0, 'delegation board: no suggestion when there is no risk'); await p.close();
  p = await open({ w: { err: { grant_separation_hint: 'boom' } } }, '#/delegation'); await wait(p, 400); await p.click('#dg_body summary');
  await p.selectOption('#dg_p', 'u-a'); await p.selectOption('#dg_c', 'cost_bill_entry'); await p.click('[data-act=dg_add]'); await wait(p, 500);
  ok((await calls(p, 'set_user_grant')).length === 1 && await p.locator('#dg_hint').count() === 0, 'delegation board: if the hint call fails the grant still stands (advice never blocks)'); await p.close();

  // ---- Bangla
  p = await open({ lang: 'bn' }, '#/costattrib'); t = await txt(p, '#ca_pane');
  ok(/ঠিক করা নেই/.test(t) && /মূল কেন্দ্র/.test(t) && /এই শোরুমের লাভ-ক্ষতিতে ধরুন/.test(t), 'Bangla option labels');
  await p.click('[data-act=ca_tab][data-v=view]'); await wait(p, 200); ok(/মোট কোথায় কত/.test(await txt(p, '#ca_pane')) && /হাতে বদলানো/.test(await txt(p, '#ca_pane')), 'Bangla cost view');
  await p.click('[data-act=ca_tab][data-v=rules]'); await wait(p, 200); ok(/রেসিপি অনুমোদন/.test(await txt(p, '#ca_pane')) && /উৎপাদনে রেসিপি বাধ্যতামূলক/.test(await txt(p, '#ca_pane')), 'Bangla switch labels');
  await p.screenshot({ path: OUT + '/ca_bn.png' }); await noOverflow(p, 'Bangla rules'); await p.close();

  await br.close();
  log('assertions:', n); log('errors:', errors.length ? errors.join(' | ') : 'none'); log('assert failures:', bad);
} catch (e) { console.log('TEST CRASH', e); } finally { srv.close(); } })();
