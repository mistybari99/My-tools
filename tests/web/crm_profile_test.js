// CRM-A web pieces: Customer 360 (#/crm360/<id>, web/crm_360.js) and the profile editor sheet (web/crm_profile.js).
// Run: node crm_profile_test.js <abs tests/web dir>     (the server functions are mocked in the page; the database side is supabase/phase300..302_test.sql)
// web/crm_360.js and web/crm_profile.js are injected into index.html here; the integrator adds the real <script> tags (docs/integration/CRM-A.md).
// The hooks into customers.js are proved on a PATCHED COPY served by this test (the exact text of docs/integration/CRM-A.md); web/customers.js itself is not changed.
// Screenshots go to CRM_SHOTS if that variable is set (never into the repository).
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const WEB = require('path').join(__dirname, '..', '..', 'web');
const base = C.baseData(SP), PORT = 8573;
const srv = require('http').createServer((q, r) => { const f = require('path').join(WEB, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

// ---- the exact hook text (the same pairs are written in docs/integration/CRM-A.md) ----
const HOOKS_CUSTOMERS = [
  ["const r = await sb.rpc('customer_directory'); if (r.error) {",
    "let r = await sb.rpc('crma_customer_directory'); if (r.error && /crma_customer_directory/.test(r.error.message || '')) r = await sb.rpc('customer_directory'); if (r.error) {"],
  ['async function openProfile(id) {', "async function openProfile(id) {\n  if (B.crm && B.crm.open360) return B.crm.open360(id);"],
  ['    <div class="row"><button class="full" data-act="closesheet">${esc(T(\'cancel\'))}</button><button class="primary full" data-act="cu_save">${esc(T(\'save\'))}</button></div></div>`);',
    '    ${edit && B.crm && B.crm.openEdit ? `<button type="button" class="full" data-act="crm_more" data-v="${esc(e.id)}">More profile details</button>` : \'\'}\n    <div class="row"><button class="full" data-act="closesheet">${esc(T(\'cancel\'))}</button><button class="primary full" data-act="cu_save">${esc(T(\'save\'))}</button></div></div>`);'],
  ['    <a class="full tog" href="tel:${esc(c.mobile)}" style="text-align:center;padding:10px">${esc(T(\'menuCall\'))}</a>',
    '    ${/\\*/.test(c.mobile || \'\') ? \'\' : `<a class="full tog" href="tel:${esc(c.mobile)}" style="text-align:center;padding:10px">${esc(T(\'menuCall\'))}</a>`}'],
  ['    <a class="full tog" href="${esc(wa)}" target="_blank" rel="noopener" style="text-align:center;padding:10px">${esc(T(\'menuWa\'))}</a>',
    '    ${/\\*/.test(c.whatsapp || c.mobile || \'\') ? \'\' : `<a class="full tog" href="${esc(wa)}" target="_blank" rel="noopener" style="text-align:center;padding:10px">${esc(T(\'menuWa\'))}</a>`}'],
];
const HOOKS_POS = [
  ['P.cust.found = r.data; if (r.data && r.data.found) P.cust.name = r.data.name;',
    "let mm = m; if (r.data && !r.data.found && B.crm && B.crm.findAny) { const a = await B.crm.findAny(m); if (a) { r.data = a; mm = a.mobile; P.cust.mobile = a.mobile; } }\n    P.cust.found = r.data; if (r.data && r.data.found) P.cust.name = r.data.name;"],
  ["const ri = await sb.rpc('customer_pos_info', { p_mobile: m }); if (!ri.error && ri.data && normMobile(P.cust.mobile) === m)",
    "const ri = await sb.rpc('customer_pos_info', { p_mobile: mm }); if (!ri.error && ri.data && normMobile(P.cust.mobile) === mm)"],
];
function applyHooks(src, pairs) { let s = src; for (const [a, b] of pairs) { const n = s.split(a).length - 1; if (n !== 1) throw new Error('hook site found ' + n + ' times: ' + a.slice(0, 60)); s = s.replace(a, () => b); } return s; }

const ID = '11111111-0000-0000-0000-000000000001';
const K360 = (o) => Object.assign({
  customer: { id: ID, name: 'test_cust_one', active: true, type: 'retail', type_code: 'party', type_label: 'Party / event', tier: { id: 2, name: 'Regular', color: '#0ea5e9', badge: 'R' }, tier_locked: false, source: 'test_source', language: 'en',
    preferred_location: { id: 1, name: 'main' }, owner: { id: 'u9', name: 'test_staff' }, credit_limit: 5000, credit_days: 15, customer_since: '2026-01-02', created_at: '2026-01-02T00:00:00Z', note: 'test_old_note' },
  stats: { spend: 1100, orders: 3, orders_12m: 3, first_sale: '2026-02-01', last_sale: '2026-10-10', avg_bill: 366.67, balance: 100, points: 40 },
  phones: [{ id: null, kind: 'main', label: 'mobile', phone: '01711032001', wa_ok: false, masked: false }, { id: null, kind: 'whatsapp', label: 'mobile', phone: '01711032009', wa_ok: true, masked: false },
    { id: 5, kind: 'extra', label: 'home', phone: '01711032011', wa_ok: true, note: null, masked: false, shared: true }],
  addresses: [{ id: null, kind: 'main', label: 'home', address: 'test_addr_main_1', is_default: false, hidden: false }, { id: 3, kind: 'extra', label: 'office', address: 'test_addr_office_1', area: 'test_area', landmark: 'near test_mosque', delivery_note: 'ring twice', is_default: true, hidden: false }],
  dates: [{ id: null, kind: 'birthday', person: 'Customer', month: 3, day: 15, year: 1990, own: true, next_date: '2027-03-15', days_until: 150, turning: 37 }, { id: 7, kind: 'birthday', person: 'Spouse', month: 7, day: 4, year: 1992, remind_days_before: 7, own: false, next_date: '2027-07-04', days_until: 260, turning: 35 }],
  tags: [{ id: 1, code: 'test_tag', label: 'Test tag' }],
  next_date: { person: 'Customer', kind: 'birthday', next_date: '2027-03-15', days_until: 150 },
  favourites: [{ item_id: 'i1', name: 'test_item_a', name_en: 'Test item A', unit: 'kg', orders: 2, qty: 5, amount: 1000, last_date: '2026-10-05' }],
  counts: { notes: 1, open_orders: 1, messages_waiting: 0 },
  can: { crm_on: true, edit: true, manage: true, view: true, contact: true, shows_phone: true, second_phone: true },
}, o || {});
const MASKED = K360({ phones: [{ id: null, kind: 'main', label: 'mobile', phone: '017******01', wa_ok: false, masked: true }, { id: 5, kind: 'extra', label: 'home', phone: '017******11', wa_ok: true, masked: true }],
  addresses: [{ id: null, kind: 'main', label: 'home', address: null, hidden: true, is_default: true }], counts: { open_orders: 1 }, customer: Object.assign({}, K360().customer, { note: null }),
  can: { crm_on: true, edit: true, manage: false, view: false, contact: false, shows_phone: false, second_phone: true } });
const TL1 = { items: [{ at: '2026-10-10T10:00:00Z', key: 's:1', kind: 'sale', title: 'Sale #932002', amount: 600, status: 'done', location_id: 1, detail: { due: 200 } }, { at: '2026-10-09T10:00:00Z', key: 'c:1', kind: 'collection', title: 'Due payment received', amount: 100, status: 'done', detail: {} }], has_more: true, next: { before: '2026-10-09T10:00:00Z', key: 'c:1' } };
const TL2 = { items: [{ at: '2026-10-01T10:00:00Z', key: 'p:1', kind: 'points', title: 'Points earned', amount: null, status: 'done', detail: { points: 55 } }, { at: '2026-09-30T10:00:00Z', key: 'm:1', kind: 'message', title: 'Sms: thanks', amount: null, status: 'sent', detail: { to: '01711032001', text: 'test_body_sms' } }], has_more: false, next: null };
const NOTES = { items: [{ at: '2026-10-08T10:00:00Z', key: 'n:1', kind: 'note', title: 'Call', amount: null, status: 'done', detail: { text: 'test_note_new', by: 'test_viewer', note_id: 11 } }], has_more: false, next: null };
const STATE = (o) => Object.assign({ crm_on: true, second_phone_on: true, mask_phone: false, is_owner: true, can_see_customers: true, can_write: true, can_manage: true, can_view: true, contact_ok: true, shows_phone: true }, o || {});
const LOCS = [{ id: 1, name_en: 'main', name_bn: 'main', is_active: true, sort: 1 }, { id: 2, name_en: 'branch2', name_bn: 'branch2', is_active: true, sort: 2 }];
const DIR = [{ id: 'c1', mobile: '01711111111', name: 'test_dir_one', type: 'retail', active: true, tier_id: 1, tier_locked: false, birthday: null, anniversary: null, address: 'test_addr', whatsapp: null, note: null, credit_limit: null, customer_since: '2026-01-01', balance: 0, spend: 10, orders: 1, last_sale: '2026-10-01', points: 0 }];

const EXTRA_SRC = (K) => `(function(){ const K = ${JSON.stringify(K)}; const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__CR = window.__CR || {}; R.calls = R.calls || []; R.o = R.o || {};
 c.rpc = async (fn, args) => {
  if (!/^(crma_|customer_directory$|customer_profile$|find_customer$|customer_pos_info$)/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  const O = R.o;
  if (O.err && O.err[fn]) return { data: null, error: { message: O.err[fn], code: 'P0001' } };
  if (fn === 'crma_state') return { data: Object.assign({}, K.STATE, O.state || {}), error: null };
  if (fn === 'crma_customer_360') return { data: O.k360 || K.K360, error: null };
  if (fn === 'crma_timeline') { if (args.p_kinds && args.p_kinds.length === 1 && args.p_kinds[0] === 'note') return { data: K.NOTES, error: null }; if (args.p_before) return { data: K.TL2, error: null }; return { data: K.TL1, error: null }; }
  if (fn === 'crma_note_add' || fn === 'crma_note_retire') return { data: { dup: false, id: 12 }, error: null };
  if (fn === 'crma_phone_reveal') return { data: { mobile: '01711032001', whatsapp: null, logged: true }, error: null };
  if (fn === 'crma_customer_extras_save') return { data: { id: args.p_id, saved: true }, error: null };
  if (fn === 'crma_phone_add') return { data: { dup: false, id: 9, warning: O.shared ? 'phone_shared' : null }, error: null };
  if (fn === 'crma_customer_directory' || fn === 'customer_directory') { if (O.noCrmDir && fn === 'crma_customer_directory') return { data: null, error: { message: 'Could not find the function public.crma_customer_directory', code: 'PGRST202' } }; return { data: K.DIR, error: null }; }
  if (fn === 'customer_profile') return { data: { customer: { id: 'c1', name: 'test_dir_one', mobile: '01711111111' } }, error: null };
  if (fn === 'find_customer') return { data: { found: false, mobile: args.p_mobile }, error: null };
  return { data: { dup: false, id: 1 }, error: null };
 }; return c; }; })();`;
const EXTRA = EXTRA_SRC({ K360: K360(), STATE: STATE(), TL1, TL2, NOTES, DIR });

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage(); p.setDefaultTimeout(5000);
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    if (o.hooks) await p.route((u) => u.pathname === '/customers.js', (r) => r.fulfill({ contentType: 'text/javascript', body: applyHooks(fs.readFileSync(WEB + '/customers.js', 'utf8'), HOOKS_CUSTOMERS) }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); let h = await res.text();
      for (const f of ['crm_360.js', 'crm_profile.js']) if (!new RegExp(f.replace('.', '\\.')).test(h)) h = h.replace('</body>', `<script src="${f}"></script></body>`);
      await r.fulfill({ response: res, body: h }); });
    const data = C.mk(base, {}); data.tables.locations = LOCS; data.tables.crm_tags = [{ id: 1, code: 'test_tag', label: 'Test tag', active: true }, { id: 2, code: 'test_tag_2', label: 'Second tag', active: true }];
    data.tables.option_lists = (data.tables.option_lists || []).filter((x) => x.list_code !== 'customer_types').concat([{ list_code: 'customer_types', value_code: 'party', label_en: 'Party / event', active: true, sort: 3 }, { list_code: 'customer_types', value_code: 'retail', label_en: 'Retail', active: true, sort: 1 }]);
    const cr = { calls: [], o: o.o || {} };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__CR=${JSON.stringify(cr)};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}${o.noStorage ? ";Storage.prototype.getItem=function(){throw new Error('blocked')};Storage.prototype.setItem=function(){throw new Error('blocked')};" : ''}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1500); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__CR.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);
  const shot = async (p, n) => { if (process.env.CRM_SHOTS) await p.screenshot({ path: process.env.CRM_SHOTS + '/' + n + '.png', fullPage: true }); };
  const click = async (p, sel) => { await p.click(sel); await wait(p, 350); };
  let p, t; const mark = (m) => console.log('>>', m);

  mark('1'); // ---- 1. Customer 360: essentials first
  p = await open('#/crm360/' + ID);
  t = await text(p);
  ok(/Customer 360/.test(await p.locator('h1').textContent()), 'title');
  ok(await p.locator('#c360_head').count() === 1 && /test_cust_one/.test(t) && /Regular/.test(t) && /Party \/ event/.test(t) && /Test tag/.test(t), 'header: name, tier, type, tag');
  ok(/Spent/.test(t) && /1,100/.test(t) && /Last purchase/.test(t) && /2026-10-10/.test(t) && /Due/.test(t) && /Points/.test(t), 'header: spend, last purchase, due, points');
  ok(await p.locator('a[href="tel:01711032001"]').count() === 1 && await p.locator('a[href^="https://wa.me/8801711032001"]').count() === 1, 'Call and WhatsApp buttons use the main number');
  ok((await calls(p, 'crma_customer_360')).length === 1 && (await calls(p, 'crma_customer_360'))[0].p_customer === ID && (await calls(p, 'crma_timeline')).length === 0, 'one 360 call, no timeline call before the Timeline tab');
  ok(await p.locator('#c360_tabs button').count() === 4, 'four tabs (Notes shown because the person may view notes)');
  ok(/Next date/.test(t) && /Usually buys/.test(t) && /Test item A/.test(t) && /Open online orders/.test(t), 'overview: next date, favourites, open orders');
  ok(await p.locator('#c360_more').count() === 1 && await p.locator('#c360_more[open]').count() === 0, 'the More fold is closed by default');
  await noOverflow(p, '360 overview'); await shot(p, 'crm_360_overview');
  await p.click('#c360_more summary'); await wait(p, 200);
  ok(/Credit days/.test(await text(p)) && /Looked after by/.test(await text(p)), 'More fold shows type, credit terms, language, outlet, owner');
  await p.reload(); await wait(p, 1500);
  ok(await p.locator('#c360_more[open]').count() === 1, 'the More fold stays open after a reload (remembered on this phone)');
  ok(await p.evaluate(() => { const b = document.getElementById('c360_bar'); return !!b && getComputedStyle(b).position === 'sticky'; }), 'the action bar is sticky');

  mark('2'); // ---- 2. Timeline
  await click(p, '[data-act=crm_tab][data-v=timeline]');
  t = await text(p);
  let tc = await calls(p, 'crma_timeline');
  ok(tc.length === 1 && tc[0].p_limit === 30 && tc[0].p_kinds === null && tc[0].p_before === undefined, 'first page: 30 rows, all kinds');
  ok(/Sale #932002/.test(t) && /Due payment received/.test(t) && /Show more/.test(t), 'rows and Show more');
  await click(p, '[data-act=crm_tlmore]');
  tc = await calls(p, 'crma_timeline');
  ok(tc.length === 2 && tc[1].p_before === '2026-10-09T10:00:00Z' && tc[1].p_before_key === 'c:1', 'the next page is asked with the cursor (time and key)');
  t = await text(p);
  ok(/Points earned/.test(t) && /\+55 pts/.test(t) && /Sms: thanks/.test(t) && /test_body_sms/.test(t) && !/Show more/.test(t), 'second page appended, no more button');
  await p.selectOption('#c360_kind', 'sale'); await wait(p, 400);
  tc = await calls(p, 'crma_timeline');
  ok(tc[tc.length - 1].p_kinds.length === 1 && tc[tc.length - 1].p_kinds[0] === 'sale' && tc[tc.length - 1].p_before === undefined, 'a filter restarts from the top with the kind');
  await noOverflow(p, 'timeline'); await shot(p, 'crm_360_timeline');

  mark('3'); // ---- 3. Contacts
  await click(p, '[data-act=crm_tab][data-v=contacts]');
  t = await text(p);
  ok(/01711032001/.test(t) && /01711032009/.test(t) && /01711032011/.test(t) && /also on another customer/.test(t), 'phones: main, WhatsApp, extra; the shared number is flagged');
  ok(/test_addr_main_1/.test(t) && /test_addr_office_1/.test(t) && /default/.test(t) && /near test_mosque/.test(t) && /ring twice/.test(t), 'addresses and delivery points');
  ok(/Spouse/.test(t) && /turns 35/.test(t), 'family dates with the age they turn');
  await noOverflow(p, 'contacts');

  mark('4'); // ---- 4. Notes
  await click(p, '[data-act=crm_tab][data-v=notes]');
  ok(/test_note_new/.test(await text(p)) && (await calls(p, 'crma_timeline')).slice(-1)[0].p_kinds[0] === 'note', 'notes tab lists notes through the timeline function');
  await click(p, '[data-act=crm_noteadd]');
  await click(p, '[data-act=crm_notego]');
  ok((await calls(p, 'crma_note_add')).length === 0 && /Write the note first/.test(await text(p)), 'an empty note is not sent');
  await p.fill('#nt_body', 'test_note_typed'); await p.selectOption('#nt_kind', 'visit'); await click(p, '[data-act=crm_notego]');
  const na = await calls(p, 'crma_note_add');
  ok(na.length === 1 && na[0].p_body === 'test_note_typed' && na[0].p_kind === 'visit' && /^[0-9a-f-]{36}$/.test(na[0].p_client) && na[0].p_customer === ID, 'note sent with kind, text and a client id');
  ok(await p.locator('#nt_body').count() === 0, 'the sheet closes after saving');
  await click(p, '[data-act=crm_noteretire]');
  await p.fill('#nr_why', 'ab'); await click(p, '[data-act=crm_noteretirego]');
  ok((await calls(p, 'crma_note_retire')).length === 0, 'a 2-character reason is not a reason');
  await p.fill('#nr_why', 'wrong customer'); await click(p, '[data-act=crm_noteretirego]');
  const nr = await calls(p, 'crma_note_retire');
  ok(nr.length === 1 && nr[0].p_id === 11 && nr[0].p_reason === 'wrong customer', 'retire sent with the note id and the reason');
  await noOverflow(p, 'notes'); await shot(p, 'crm_360_notes');

  mark('5'); // ---- 5. Masked caller: no number, no notes, reveal needs a reason
  p = await open('#/crm360/' + ID, { owner: false, o: { k360: MASKED, state: { is_owner: false, can_view: false, can_manage: false, shows_phone: false, contact_ok: false } } });
  t = await text(p);
  ok(/017\*\*\*\*\*\*01/.test(t) && /\(hidden\)/.test(t) && await p.locator('a[href^="tel:"]').count() === 0 && await p.locator('a[href^="https://wa.me"]').count() === 0, 'masked: hidden number, no Call or WhatsApp link');
  ok(await p.locator('[data-act=crm_reveal]').count() === 1 && await p.locator('#c360_tabs button').count() === 3 && await p.locator('[data-act=crm_noteadd]').count() === 0, 'masked: Show number button, no Notes tab, no Add note');
  ok(!/01711032001/.test(await p.evaluate(() => document.documentElement.innerHTML)), 'the full number is nowhere in the page');
  await click(p, '[data-act=crm_reveal]'); await p.fill('#rv_why', 'x'); await click(p, '[data-act=crm_revealgo]');
  ok((await calls(p, 'crma_phone_reveal')).length === 0, 'reveal without a reason is not sent');
  await p.fill('#rv_why', 'customer asked for a call-back'); await click(p, '[data-act=crm_revealgo]');
  ok((await calls(p, 'crma_phone_reveal')).length === 1 && await p.locator('#rv_out a[href="tel:01711032001"]').count() === 1, 'reveal sends the reason and then offers one Call link');
  await noOverflow(p, 'masked'); await shot(p, 'crm_360_masked');

  mark('6'); // ---- 6. errors and bad route
  p = await open('#/crm360/' + ID, { o: { err: { crma_customer_360: 'not allowed' } } });
  ok(/do not have permission/.test(await text(p)), 'denied: friendly text');
  p = await open('#/crm360/not-an-id');
  ok(/Open a customer from the customer list/.test(await text(p)) && (await calls(p, 'crma_customer_360')).length === 0, 'a bad id is not sent to the server');

  mark('7'); // ---- 7. Profile editor sheet
  p = await open('#/crm360/' + ID);
  await click(p, '[data-act=crm_edit]');
  ok(await p.locator('#crmp_form').count() === 1 && await p.locator('#crmp_lang').count() === 1 && await p.locator('#crmp_loc').count() === 1 && await p.locator('#crmp_tags .tog').count() === 2, 'editor: language, outlet, tags first');
  ok(await p.locator('#crmp_more[open]').count() === 0 && await p.locator('#crmp_type').count() === 1 && await p.locator('#crmp_cdays').count() === 1, 'the More fold is closed and holds type and credit days for a manager');
  await p.click('#crmp_more summary'); await wait(p, 200);
  ok(/Extra phone numbers/.test(await text(p)) && /Delivery points/.test(await text(p)) && /Family dates/.test(await text(p)) && /also on another customer/.test(await text(p)), 'More: phones, delivery points, family dates');
  await noOverflow(p, 'editor'); await shot(p, 'crm_edit');
  await p.selectOption('#crmp_lang', 'bn'); await p.selectOption('#crmp_loc', '2'); await p.selectOption('#crmp_type', 'retail'); await p.fill('#crmp_cdays', 'abc'); await click(p, '[data-act=crmp_save]');
  ok((await calls(p, 'crma_customer_extras_save')).length === 0 && /number is not valid/.test(await text(p)), 'credit days must be a whole number');
  await p.fill('#crmp_cdays', '30'); await click(p, '[data-act=crmp_save]');
  const ex = await calls(p, 'crma_customer_extras_save');
  ok(ex.length === 1 && ex[0].p_id === ID && ex[0].p.language === 'bn' && ex[0].p.preferred_location_id === '2' && ex[0].p.type_code === 'retail' && ex[0].p.credit_days === 30 && /^[0-9a-f-]{36}$/.test(ex[0].p_client), 'extras saved with language, outlet, type, credit days and a client id');
  ok(await p.locator('#crmp_form').count() === 0, 'the sheet closes after saving');
  await click(p, '[data-act=crm_edit]');
  await p.click('#crmp_tags .tog:has-text("Second tag")'); await wait(p, 300);
  const ts = await calls(p, 'crma_tag_set');
  ok(ts.length === 1 && ts[0].p_tag === 2 && ts[0].p_on === true && ts[0].p_customer === ID, 'a tag is put on with one tap');
  ok(await p.locator('#crmp_more[open]').count() === 1, 'the editor More fold opens as the person left it last time (remembered)');
  await p.fill('#crmp_ph', '০১৭১১০৩২০৯৯'); await click(p, '[data-act=crmp_phone_add]');
  const pa = await calls(p, 'crma_phone_add');
  ok(pa.length === 1 && pa[0].p_phone === '01711032099' && pa[0].p_customer === ID && /^[0-9a-f-]{36}$/.test(pa[0].p_client), 'an extra phone is sent with Latin digits and a client id');
  await p.fill('#crmp_dp', ''); await click(p, '[data-act=crmp_date_add]');
  ok((await calls(p, 'crma_date_save')).length === 0 && /whose date/.test(await text(p)), 'a family date needs the person');
  await p.fill('#crmp_dp', 'Child 1'); await p.fill('#crmp_dd', '30'); await p.fill('#crmp_dm', '2'); await p.fill('#crmp_dy', '2015'); await click(p, '[data-act=crmp_date_add]');
  const ds = await calls(p, 'crma_date_save');
  ok(ds.length === 1 && ds[0].p.person_label === 'Child 1' && ds[0].p.day === 30 && ds[0].p.month === 2 && ds[0].p.year === 2015 && ds[0].p_customer === ID, 'a family date is sent (the server checks the calendar)');
  await p.fill('#crmp_ad', 'test_addr_new'); await p.fill('#crmp_ar', 'test_area'); await click(p, '[data-act=crmp_addr_add]');
  const as = await calls(p, 'crma_address_save');
  ok(as.length === 1 && as[0].p.address === 'test_addr_new' && as[0].p.area === 'test_area' && as[0].p.is_default === false, 'a delivery point is sent');

  mark('8'); // ---- 8. Editor when the owner has not switched the feature on, and for a cashier (no manager fields)
  p = await open('#/crm360/' + ID, { o: { state: { crm_on: false }, k360: K360({ can: { crm_on: false, edit: false, manage: true, view: true, contact: true, shows_phone: true, second_phone: false } }) } });
  ok(await p.locator('[data-act=crm_edit]').count() === 0, 'switch OFF: no Edit profile button on the 360 view');
  p = await open('#/crm360/' + ID, { owner: false, o: { state: { crm_on: false, is_owner: false, can_manage: false, can_view: false } } });
  await p.evaluate(() => window.BOS.crm.openEdit('11111111-0000-0000-0000-000000000001')); await wait(p, 600);
  ok(await p.locator('#crmp_off').count() === 1 && await p.locator('[data-act=crmp_save][disabled]').count() === 1 && await p.locator('#crmp_type').count() === 0, 'switch OFF: notice, disabled Save, no manager fields');
  p = await open('#/crm360/' + ID, { owner: false, o: { state: { is_owner: false, can_manage: false, can_view: false } } });
  await p.evaluate(() => window.BOS.crm.openEdit('11111111-0000-0000-0000-000000000001')); await wait(p, 600);
  ok(await p.locator('#crmp_form').count() === 1 && await p.locator('#crmp_type').count() === 0 && await p.locator('#crmp_cdays').count() === 0, 'a cashier does not see customer type or credit days');

  mark('9'); // ---- 9. Hooks into customers.js, proved on the patched copy served by this test
  p = await open('#/customers', { hooks: true });
  ok((await calls(p, 'crma_customer_directory')).length === 1 && (await calls(p, 'customer_directory')).length === 0, 'hook: the list asks for the masked directory');
  ok(await p.locator('#cu_list .cu-row').count() === 1 && /test_dir_one/.test(await text(p)), 'hook: the list still renders');
  await p.click('#cu_list .cu-row'); await wait(p, 400);
  await p.evaluate(() => { const b = document.querySelector('[data-act=cu_open]'); if (b) b.click(); }); await wait(p, 800);
  ok(/#\/crm360\/c1/.test(await p.evaluate(() => location.hash)), 'hook: opening a profile goes to Customer 360');
  p = await open('#/customers', { hooks: true, o: { noCrmDir: true } });
  ok((await calls(p, 'crma_customer_directory')).length === 1 && (await calls(p, 'customer_directory')).length === 1 && /test_dir_one/.test(await text(p)), 'hook: if the new function is not installed the old directory is used');
  const patched = applyHooks(fs.readFileSync(WEB + '/customers.js', 'utf8'), HOOKS_CUSTOMERS);
  ok(!/crm_more/.test(fs.readFileSync(WEB + '/customers.js', 'utf8')) && /crm_more/.test(patched), 'web/customers.js in the repository is NOT patched; the copy is');
  const posOk = (() => { try { applyHooks(fs.readFileSync(WEB + '/pos.js', 'utf8'), HOOKS_POS); return true; } catch (e) { return String(e); } })();
  ok(posOk === true, 'hook text for pos.js applies exactly once at each site (text proof only, no browser run): ' + posOk);

  mark('10'); // ---- 10. Bangla / mix modes and blocked storage still render (English labels only for now)
  p = await open('#/crm360/' + ID, { lang: 'bn' });
  ok(/Customer 360/.test(await p.locator('h1').textContent()) && /test_cust_one/.test(await text(p)), 'bn mode: English labels');
  await noOverflow(p, 'bn');
  p = await open('#/crm360/' + ID, { lang: 'mix', noStorage: true });
  ok(/test_cust_one/.test(await text(p)), 'blocked storage: the screen still renders');
  await click(p, '#c360_more summary');
  await noOverflow(p, 'mix, storage blocked');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
