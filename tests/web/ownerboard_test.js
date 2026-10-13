// Module E: Home cleanup (no Recent, no star marks, favourites in the ⋮ menu) + Owner mode board (#/owner).
// Run: node ownerboard_test.js <abs tests/web dir>      (server state lives in node: SRV, shared by every page this test opens)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/s10_common.js');
const base = C.baseData(SP), PORT = 8197, srv = C.serve(PORT);
const dh = (n = 0) => { const d = new Date(Date.now() + n * 86400000); return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Dhaka' }); };
const TD = dh(0), YD = dh(-1), WD = dh(-7);
const R = (key, def) => ({ key, module: 'ui', kind: 'switch', value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1 });

// ---- the "server" (in node) ----
const SRV = { fav: [], board: [], saves: [], boardCalls: 0 };
const srvOp = (op, a) => {
  if (op === 'set_pin') { let r = SRV.fav.find((x) => x.kind === a.p_kind && x.key === a.p_key); if (!r) SRV.fav.push(r = { kind: a.p_kind, key: a.p_key, pinned: false, uses: 0, sort: null, label: null, hidden: false }); r.pinned = !!a.p_pinned; return { ok: true }; }
  if (op === 'fav_order_set') { a.p_items.forEach((it, i) => { let r = SRV.fav.find((x) => x.kind === it.kind && x.key === it.key); if (!r) SRV.fav.push(r = { kind: it.kind, key: it.key, pinned: true, uses: 0, sort: i, label: null, hidden: false }); r.sort = i; }); return { ok: true }; }
  if (op === 'fav_meta_set') { let r = SRV.fav.find((x) => x.kind === a.p_kind && x.key === a.p_key); if (!r) SRV.fav.push(r = { kind: a.p_kind, key: a.p_key, pinned: false, uses: 0, sort: null, label: null, hidden: false }); r.label = a.p_label || null; r.hidden = !!a.p_hidden; return { ok: true }; }
  if (op === 'board_get') return SRV.board.map((r, i) => ({ id: i + 1, widget: r.widget, config: r.config, sort: i, enabled: r.enabled, updated_at: new Date().toISOString() }));
  if (op === 'board_save') { SRV.boardCalls++; if (a.length > 60) return { error: 'too_many_items' }; SRV.board = JSON.parse(JSON.stringify(a)); SRV.saves.push(a.map((x) => x.widget)); return { count: a.length }; }
  return null;
};

const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc, from = c.from; const OB = window.__OB || {};
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
 const miss = (fn) => ({ data: null, error: { message: 'Could not find the function public.' + fn + ' in the schema cache', code: 'PGRST202' } });
 const errB = () => { const b = new Proxy(function () {}, { get: (t, k) => (k === 'then' ? (res) => Promise.resolve({ data: null, count: null, error: { message: 'relation does not exist', code: '42P01' } }).then(res) : () => b), apply: () => b }); return b; };
 c.from = (name) => ((OB.missingTables || []).includes(name) ? errB() : from(name));
 c.rpc = async (fn, args) => {
  (window.__AC = window.__AC || []).push([fn, clone(args || {})]);
  if ((OB.missing || []).includes(fn)) return miss(fn);
  if (fn === 'set_pin' || fn === 'fav_order_set' || fn === 'fav_meta_set') { if (window.__NET_DOWN) return { data: null, error: { message: 'Failed to fetch' } }; await window.__srv(fn, clone(args)); return { data: null, error: null }; }
  if (fn === 'owner_board_get') return OB.noBoard ? miss(fn) : { data: await window.__srv('board_get'), error: null };
  if (fn === 'owner_board_save') { if (OB.noBoard) return miss(fn); const r = await window.__srv('board_save', clone(args.p_items)); return r.error ? { data: null, error: { message: r.error } } : { data: r, error: null }; }
  if (fn === 'sales_summary') { window.__SALES_CALLS = (window.__SALES_CALLS || 0) + 1; return { data: OB.sales || [], error: null }; }
  if (fn === 'customer_dues') return { data: OB.dues || [], error: null };
  if (fn === 'payables_summary') return { data: OB.pay || [], error: null };
  if (fn === 'stock_levels') return { data: OB.levels || [], error: null };
  if (fn === 'expiry_list') return { data: OB.expiry || [], error: null };
  if (fn === 'needs_you_oldest') return { data: OB.ny || [], error: null };
  if (fn === 'wastage_pending') return { data: [], error: null };
  if (fn === 'report_catalog') return { data: OB.catalog || [], error: null };
  if (fn === 'report_run') return { data: OB.runres, error: null };
  return rpc(fn, args); };
 return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const OBD = (o = {}) => Object.assign({
    sales: [{ sale_date: TD, location_id: 1, pay_mode: 'cash', status: 'done', n: 10, total: 5000, discount: 120, due: 0 }, { sale_date: TD, location_id: 1, pay_mode: 'cash', status: 'void', n: 2, total: 300, discount: 0, due: 0 },
      { sale_date: YD, location_id: 1, pay_mode: 'cash', status: 'done', n: 8, total: 4000, discount: 0, due: 0 }, { sale_date: WD, location_id: 1, pay_mode: 'cash', status: 'done', n: 9, total: 4500, discount: 0, due: 0 }],
    dues: [{ id: 'c1', name: 'A', balance: 1500, oldest: dh(-45) }, { id: 'c2', name: 'B', balance: 500, oldest: dh(-3) }],
    pay: [{ total_payable: 9000, suppliers_owed: 2, overdue: 2500, overdue_suppliers: 1, oldest: dh(-20), credit_total: 0 }],
    levels: [{ item_id: 'i0', below_min: true }, { item_id: 'i1', below_min: true }, { item_id: 'i2', below_min: true }],
    expiry: [{ batch_id: 1, expired: false, hours_left: 5 }, { batch_id: 2, expired: true, hours_left: -2 }],
    ny: [{ kind: 'entry', id: 'e1', label: '10-2 #9002', since: new Date(Date.now() - 9 * 3600e3).toISOString(), route: 'entry/e1' }],
  }, o);
  async function open(hash, o = {}) {
    const ctx = o.ctx || await br.newContext({ viewport: { width: 360, height: 780 } }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|PGRST|relation does not exist|Could not find|status of 4/.test(m.text())) errors.push('console: ' + m.text()); });
    p.on('dialog', (d) => d.accept());
    await p.exposeFunction('__srv', (op, a) => srvOp(op, a));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
    T.rules = [R('ui_noperm_mode', 'lock')].concat(o.ruleOff ? [R('owner_board_on', false)] : []);
    T.user_favourites = JSON.parse(JSON.stringify(SRV.fav)); T.role_favourites = [];
    T.entries = [{ id: 'd1', form_code: '14-1', location_id: 1, entry_date: TD, status: 'submitted' }];
    T.exceptions = [{ id: 1, flag_code: 'cash_short_over', level: 'red', status: 'open', amount: -700, entry_date: TD, created_at: TD + 'T10:00:00Z' }, { id: 2, flag_code: 'x', level: 'yellow', status: 'open', amount: 1, entry_date: YD, created_at: YD + 'T10:00:00Z' }];
    T.stock_wastage = [{ id: 'w1', qty: 2.5, made_at: TD + 'T09:00:00+06:00' }];
    T.sales = [{ id: 's1', sale_date: TD, status: 'done', lines: [{ name: 'Rosogolla', qty: 4, amount: 800 }, { name: 'Sandesh', qty: 2, amount: 300 }] }];
    T.form_rollout = [{ form_code: '14-1', location_id: 2, mode: 'paper' }];
    await p.addInitScript(`${o.init || ''}window.__DATA=${JSON.stringify(data)};window.__OB=${JSON.stringify(Object.assign(OBD(), o.ob || {}))};${o.owner === false ? 'window.__OWNER=false;' : ''}${o.refreshMs ? 'window.__OB_REFRESH_MS=' + o.refreshMs + ';' : ''}try{if(!localStorage.getItem('bos_lang'))localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await wait(p, o.settle || 1500); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => (window.__AC || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow: ' + m);
  const txt = (p, sel) => p.evaluate((s) => (document.querySelector(s) ? document.querySelector(s).innerText : ''), sel);
  const pins = (p) => p.evaluate(() => window.BOS_NAV.pins());
  // pick an item of the ⋮ menu sheet by its text
  const pick = async (p, re) => { const n = await p.evaluate((s) => { const bs = [...document.querySelectorAll('.ctl-sheet .ctl-opt')]; const b = bs.find((x) => new RegExp(s, 'i').test(x.textContent)); if (!b || b.disabled) return 0; b.click(); return 1; }, re); await wait(p, 250); return n; };
  const sel = (p, id, v) => p.evaluate(([i, x]) => { const e = document.getElementById(i); e.value = x; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true })); }, [id, v]);
  const dots = async (p, sel) => { await p.click(sel); await wait(p, 300); };

  // =================== A. Home cleanup ===================
  SRV.fav = [{ kind: 'route', key: 'dues', pinned: true, uses: 3, sort: 0, label: null, hidden: false }, { kind: 'route', key: 'items', pinned: true, uses: 1, sort: 1, label: null, hidden: false }, { kind: 'route', key: 'stock', pinned: true, uses: 1, sort: 2, label: null, hidden: false }];
  let p = await open('#/home');
  await p.evaluate(() => { location.hash = '#/items'; }); await wait(p, 500); await p.evaluate(() => { location.hash = '#/dues'; }); await wait(p, 500); await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 900);   // visits used to make "Recent"
  ok(await p.locator('#hv_recent').count() === 0 && !/Recent|সাম্প্রতিক/.test(await p.evaluate(() => document.querySelector('#app').innerText)), 'Home has no Recent block');
  ok(await p.locator('[aria-pressed]').filter({ has: p.locator('svg') }).evaluateAll((els) => els.filter((e) => e.classList.contains('st') || /Pin|Unpin|প্রিয়/.test(e.getAttribute('aria-label') || '')).length) === 0, 'no star (pressed) buttons on Home');
  ok(await p.locator('.qt .st').evaluateAll((els) => els.every((e) => e.textContent.trim() === '⋮' && !e.hasAttribute('aria-pressed') && !e.querySelector('svg'))) && await p.locator('.qt .st').count() >= 8, '⋮ replaces the star on every tile');
  ok(!/[☆★]/.test(await p.evaluate(() => document.querySelector('#app').innerText)), 'no star characters on Home');
  ok(await p.locator('.sellbig').count() === 1 && await p.locator('.ownbig[data-owner]').count() === 1, 'Sell and Owner mode buttons side by side');
  ok(await p.evaluate(() => { const a = document.querySelector('.sellbig').getBoundingClientRect(), b = document.querySelector('.ownbig').getBoundingClientRect(); return Math.abs(a.top - b.top) < 4 && a.left !== b.left; }), 'Owner mode button sits next to Sell');
  ok(await p.locator('#hd_dots').count() === 1, 'header has the ⋮ menu');
  await noOverflow(p, 'home');
  ok(JSON.stringify(await pins(p)) === '["r:dues","r:items","r:stock"]', 'server order pulled: ' + JSON.stringify(await pins(p)));
  await p.click('.ownbig'); await wait(p, 1200); ok(/#\/owner/.test(await p.evaluate(() => location.hash)) && await p.locator('#ob_main').count() === 1, 'Owner mode button opens #/owner');
  await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 900);
  // drawer: no recent, ⋮ on rows
  await p.click('header.top [data-act=nav_open]'); await wait(p, 600);
  ok(await p.locator('#navDrawer .dr-rc').count() === 0 && !/Recent/.test(await txt(p, '#navDrawer .dr-body')), 'drawer has no Recent block');
  ok(await p.locator('#navDrawer .dr-i .st').count() > 0 && await p.locator('#navDrawer .dr-i .st[aria-pressed]').count() === 0, 'drawer rows have ⋮, no stars');
  await p.keyboard.press('Escape'); await wait(p, 400);

  // =================== B. favourites from the ⋮ menu ===================
  await dots(p, '#hv_fav .st[data-v="r:stock"]');
  const items0 = await p.evaluate(() => [...document.querySelectorAll('.ctl-sheet .ctl-opt')].map((b) => b.textContent.trim()));
  ok(['Unpin', 'Move up', 'Move down', 'Move to top', 'Move to bottom', 'Rename', 'Hide from Home', 'Open', 'Copy link', 'Reset order'].every((w) => items0.some((x) => x.includes(w))), '⋮ menu offers the full set: ' + items0.join(' | '));
  await p.screenshot({ path: SP + '/oh_menu.png' });
  ok(await pick(p, 'Move to top'), 'Move to top clickable'); ok(JSON.stringify(await pins(p)) === '["r:stock","r:dues","r:items"]', 'Move to top: ' + JSON.stringify(await pins(p)));
  let oc = await calls(p, 'fav_order_set'); ok(oc.length === 1 && JSON.stringify(oc[0].p_items.map((x) => x.key)) === '["stock","dues","items"]', 'order pushed to the server');
  await dots(p, '#hv_fav .st[data-v="r:dues"]'); ok(await pick(p, 'Move down'), 'Move down'); ok(JSON.stringify(await pins(p)) === '["r:stock","r:items","r:dues"]', 'Move down: ' + JSON.stringify(await pins(p)));
  await dots(p, '#hv_fav .st[data-v="r:dues"]'); ok(await pick(p, 'Move up'), 'Move up'); ok(JSON.stringify(await pins(p)) === '["r:stock","r:dues","r:items"]', 'Move up');
  await dots(p, '#hv_fav .st[data-v="r:stock"]'); ok(await pick(p, 'Move to bottom'), 'Move to bottom'); ok(JSON.stringify(await pins(p)) === '["r:dues","r:items","r:stock"]', 'Move to bottom: ' + JSON.stringify(await pins(p)));
  // edit mode on the Favourites section
  await p.click('#hv_favedit'); await wait(p, 300);
  ok(await p.locator('#hv_fav .fedit').count() === 3, 'edit mode shows move/remove controls on each favourite');
  await p.click('#hv_fav .qt:nth-child(2) [data-act=fav_mv][data-d="-1"]'); await wait(p, 300); ok(JSON.stringify(await pins(p)) === '["r:items","r:dues","r:stock"]', 'edit mode: move up: ' + JSON.stringify(await pins(p)));
  await p.screenshot({ path: SP + '/oh_edit.png' });
  await p.click('#hv_favedit'); await wait(p, 200); ok(await p.locator('#hv_fav .fedit').count() === 0, 'edit mode closes');
  // persists across reload and on another device
  await p.reload(); await wait(p, 1600); ok(JSON.stringify(await pins(p)) === '["r:items","r:dues","r:stock"]', 'order survives a reload: ' + JSON.stringify(await pins(p)));
  const p2 = await open('#/home'); ok(JSON.stringify(await pins(p2)) === '["r:items","r:dues","r:stock"]', 'order synced to a second phone: ' + JSON.stringify(await pins(p2))); await p2.context().close();
  // rename (own label) + hide
  await dots(p, '#hv_fav .st[data-v="r:dues"]'); await pick(p, 'Rename'); await p.fill('#rn_in', 'My dues'); await p.click('[data-act=nav_rn_save]'); await wait(p, 300);
  ok(/My dues/.test(await txt(p, '#hv_fav')), 'own label shown on the favourite tile');
  await dots(p, '#hv_tiles .st[data-v="r:items"]'); ok(await pick(p, 'Hide from Home'), 'hide clickable'); ok(await p.locator('#hv_tiles .st[data-v="r:items"]').count() === 0, 'hidden tile leaves the Home grid');
  const mc = await calls(p, 'fav_meta_set'); ok(mc.some((c) => c.p_key === 'dues' && c.p_label === 'My dues') && mc.some((c) => c.p_key === 'items' && c.p_hidden === true), 'label and hide pushed to the server');
  await p.reload(); await wait(p, 1600);
  ok(/My dues/.test(await txt(p, '#hv_fav')) && await p.locator('#hv_tiles .st[data-v="r:items"]').count() === 0, 'label and hidden survive a reload');
  const p3 = await open('#/home'); ok(/My dues/.test(await txt(p3, '#hv_fav')), 'label synced to a second phone'); await p3.context().close();
  await p.click('#hd_dots'); await wait(p, 300); ok(await pick(p, 'Show hidden again'), 'header menu can show hidden again'); ok(await p.locator('#hv_tiles .st[data-v="r:items"]').count() === 1, 'tile is back');
  // add / remove through the menu
  await dots(p, '#hv_tiles .st[data-v="r:biz"]'); ok(await pick(p, 'Pin to favourites'), 'pin via menu'); ok((await pins(p)).includes('r:biz'), 'pinned: ' + JSON.stringify(await pins(p)));
  ok((await calls(p, 'set_pin')).some((c) => c.p_key === 'biz' && c.p_pinned === true), 'set_pin sent');
  await dots(p, '#hv_fav .st[data-v="r:biz"]'); ok(await pick(p, 'Unpin'), 'unpin via menu'); ok(!(await pins(p)).includes('r:biz'), 'unpinned');
  // reset order -> menu (registry) order
  await p.click('#hd_dots'); await wait(p, 300); ok(await pick(p, 'Reset order'), 'reset order'); const ro = await pins(p); ok(ro.length === 3, 'reset order keeps the same favourites: ' + JSON.stringify(ro));
  // header ⋮ on another page
  await p.evaluate(() => { location.hash = '#/stock'; }); await wait(p, 900);
  await p.click('#hd_dots'); await wait(p, 300); const hm = await p.evaluate(() => [...document.querySelectorAll('.ctl-sheet .ctl-opt')].map((b) => b.textContent.trim())); ok(hm.some((x) => /Unpin|Pin to/.test(x)) && hm.some((x) => /Copy link/.test(x)), 'page header ⋮ has the favourite actions: ' + hm.join('|'));
  await p.keyboard.press('Escape'); await wait(p, 200);
  await p.context().close();

  // =================== C. Owner board ===================
  SRV.board = []; SRV.saves = [];
  p = await open('#/owner', { ob: { missingTables: ['backup_runs', 'notifications', 'attendance_days'] } });
  const W = (k) => p.locator(`.ob-w[data-w="${k}"]`);
  const wt = (k) => txt(p, `.ob-w[data-w="${k}"]`);
  const kinds = await p.evaluate(() => [...document.querySelectorAll('.ob-w')].map((e) => e.dataset.w));
  ok(JSON.stringify(kinds) === JSON.stringify(['sales_vs', 'cash_short', 'day_close', 'needs_you', 'exceptions', 'approvals', 'cust_dues', 'supp_dues', 'stock_low', 'wastage', 'voids_disc', 'unsent', 'note', 'note', 'note']), 'default set in the morning-routine order, backup + notifications hidden (module missing): ' + kinds.join(','));
  ok(/5,000/.test(await wt('sales_vs')) && /\+25%/.test(await wt('sales_vs')) && /\+11%/.test(await wt('sales_vs')), 'sales vs yesterday / last week: ' + (await wt('sales_vs')).replace(/\s+/g, ' '));
  ok(/700/.test(await wt('cash_short')) && (await W('cash_short').getAttribute('class')).includes('bad'), 'cash short today is red: ' + (await wt('cash_short')).replace(/\s+/g, ' '));
  ok(/1\/1/.test(await wt('day_close')), 'day close: shop 2 is on paper, shop 1 closed -> 1/1: ' + (await wt('day_close')).replace(/\s+/g, ' '));
  ok(/1/.test(await wt('needs_you')) && /10-2 #9002/.test(await wt('needs_you')), 'needs you shows the oldest: ' + (await wt('needs_you')).replace(/\s+/g, ' '));
  ok(/Open red[\s\S]*1/.test(await wt('exceptions')), 'open exceptions: ' + (await wt('exceptions')).replace(/\s+/g, ' '));
  ok(/2,000/.test(await wt('cust_dues')) && /1,500/.test(await wt('cust_dues')), 'customer dues total + overdue: ' + (await wt('cust_dues')).replace(/\s+/g, ' '));
  ok(/9,000/.test(await wt('supp_dues')) && /2,500/.test(await wt('supp_dues')), 'supplier dues: ' + (await wt('supp_dues')).replace(/\s+/g, ' '));
  ok(/3/.test(await wt('stock_low')) && /expired 1/.test(await wt('stock_low')), 'low stock + expiring: ' + (await wt('stock_low')).replace(/\s+/g, ' '));
  ok(/1/.test(await wt('wastage')) && /2.5/.test(await wt('wastage')), 'wastage today: ' + (await wt('wastage')).replace(/\s+/g, ' '));
  ok(/2 voids/.test(await wt('voids_disc')) && /120/.test(await wt('voids_disc')), 'voids + discounts: ' + (await wt('voids_disc')).replace(/\s+/g, ' '));
  ok(/0|clear/i.test(await wt('unsent')), 'unsent forms widget present');
  ok((await p.locator('.ob-w[data-w=note]').allInnerTexts()).join(' ').match(/cash counts[\s\S]*stock counts[\s\S]*exceptions/i), 'daily checklist notes present');
  ok(/as of|As of/i.test(await txt(p, '#ob_bar')), 'shows the "as of" time');
  await noOverflow(p, 'owner board'); await p.screenshot({ path: SP + '/oh_board.png', fullPage: true });
  ok(await p.evaluate(() => [...document.querySelectorAll('.ob-main,#ob_bar button,#ob_bar .tog')].every((b) => b.getBoundingClientRect().height >= 38)), 'tap sizes >= 38px');
  // tap opens the page
  await p.click('.ob-w[data-w=cust_dues] .ob-main'); await wait(p, 700); ok(/#\/dues/.test(await p.evaluate(() => location.hash)), 'widget tap opens its page');
  await p.evaluate(() => { location.hash = '#/owner'; }); await wait(p, 1500);
  // note tick persists (no board saved yet -> defaults are written on the first change)
  const firstNote = p.locator('.ob-w[data-w=note]').first(); await firstNote.locator('.ob-main').click(); await wait(p, 500);
  ok(/☑/.test(await firstNote.innerText()), 'note ticked: ' + (await firstNote.innerText()).replace(/\s+/g, ' '));
  ok(SRV.board.length === 15 && SRV.board.filter((x) => x.widget === 'note' && x.config.done_on === TD).length === 1, 'tick saved with today on the server, whole default list stored (' + SRV.board.length + ')');
  // edit mode: add / reorder / rename / limits / size / disable / remove / reset
  await p.click('[data-act=ob_edit_toggle]'); await wait(p, 300); ok(await p.locator('.ob-ed').count() === 15, 'edit mode: controls on every widget');
  await p.click('[data-act=ob_add]'); await wait(p, 900);
  const cat = await p.evaluate(() => [...document.querySelectorAll('#ob_cat [data-act=ob_addk]')].map((b) => b.dataset.k));
  ok(cat.includes('top_sellers') && cat.includes('report') && cat.includes('page') && cat.includes('counter') && cat.includes('note') && !cat.includes('backup') && !cat.includes('notifications') && !cat.includes('attendance'), 'catalog lists what exists and hides the missing modules: ' + cat.join(','));
  await p.fill('#ob_q', 'top'); await wait(p, 200); ok(await p.locator('#ob_cat [data-act=ob_addk]').count() === 1, 'catalog is searchable');
  await p.click('#ob_cat [data-k=top_sellers]'); await wait(p, 900);
  ok(await p.locator('.ob-w[data-w=top_sellers]').count() === 1 && /Rosogolla/.test(await wt('top_sellers')), 'top sellers widget added with data: ' + (await wt('top_sellers')).replace(/\s+/g, ' '));
  ok(SRV.board.length === 16 && SRV.board[15].widget === 'top_sellers', 'add persisted through owner_board_save');
  // move to top via the widget menu
  await p.click('.ob-w[data-w=top_sellers] [data-act=ob_menu]'); await wait(p, 300); ok(await pick(p, 'Move to top'), 'widget menu: move to top');
  ok((await p.evaluate(() => document.querySelector('.ob-w').dataset.w)) === 'top_sellers' && SRV.board[0].widget === 'top_sellers', 'moved to top and saved');
  await p.click('.ob-w[data-w=top_sellers] [data-act=ob_mv][data-d="1"]'); await wait(p, 300); ok(SRV.board[1].widget === 'top_sellers', 'arrow moves it down one');
  // rename + limit on customer dues
  await p.click('.ob-w[data-w=cust_dues] .ob-main'); await wait(p, 400); await p.fill('#ob_label', 'Baki customers'); await p.fill('#ob_bad_gt', '1000'); await p.fill('#ob_warn_gt', '500'); await sel(p, 'ob_size', 'wide'); await p.click('[data-act=ob_save]'); await wait(p, 900);
  ok(/Baki customers/.test(await wt('cust_dues')) && (await W('cust_dues').getAttribute('class')).includes('bad') && (await W('cust_dues').getAttribute('class')).includes('wide'), 'rename, red limit and wide size apply: ' + (await W('cust_dues').getAttribute('class')));
  const cd = SRV.board.find((x) => x.widget === 'cust_dues'); ok(cd && cd.config.label === 'Baki customers' && cd.config.bad_gt === 1000 && cd.config.warn_gt === 500 && cd.config.size === 'wide', 'limits stored as numbers: ' + JSON.stringify(cd && cd.config));
  await p.click('.ob-w[data-w=cust_dues] .ob-main'); await wait(p, 400); await p.fill('#ob_bad_gt', 'abc'); await p.click('[data-act=ob_save]'); await wait(p, 300); ok(/not a valid number/.test(await txt(p, '#toast')), 'bad limit refused with friendly text'); await p.click('.sheet-x'); await wait(p, 200);
  // disable then remove
  await p.click('.ob-w[data-w=wastage] [data-act=ob_menu]'); await wait(p, 300); await pick(p, 'Hide \\(disable\\)'); ok(SRV.board.find((x) => x.widget === 'wastage').enabled === false, 'disabled widget stored');
  await p.click('.ob-w[data-w=voids_disc] [data-act=ob_menu]'); await wait(p, 300); await pick(p, 'Remove'); ok(!SRV.board.some((x) => x.widget === 'voids_disc') && await p.locator('.ob-w[data-w=voids_disc]').count() === 0, 'removed widget gone and saved');
  await p.click('[data-act=ob_edit_toggle]'); await wait(p, 300);
  ok(await p.locator('.ob-w[data-w=wastage]').count() === 0, 'disabled widget hidden outside edit mode');
  // page / counter / note / report shortcuts
  await p.click('[data-act=ob_edit_toggle]'); await p.click('[data-act=ob_add]'); await wait(p, 700); await p.click('#ob_cat [data-k=page]'); await wait(p, 500);
  await sel(p, 'ob_route', 'stock'); await p.click('[data-act=ob_save]'); await wait(p, 600);
  ok(await p.locator('.ob-w[data-w=page]').count() === 1 && SRV.board.some((x) => x.widget === 'page' && x.config.route === 'stock'), 'page shortcut added');
  await p.click('[data-act=ob_add]'); await wait(p, 700); await p.click('#ob_cat [data-k=counter]'); await wait(p, 500); await sel(p, 'ob_preset', 'exceptions_open'); await p.click('[data-act=ob_save]'); await wait(p, 900);
  ok(/Open exceptions/.test(await wt('counter')) && /2/.test(await wt('counter')), 'counter widget counts a table with a safe preset: ' + (await wt('counter')).replace(/\s+/g, ' '));
  await p.click('[data-act=ob_add]'); await wait(p, 700); await p.click('#ob_cat [data-k=note]'); await wait(p, 500); await p.fill('#ob_text', 'Call the baker'); await sel(p, 'ob_rep', 'weekly'); await p.click('[data-act=ob_save]'); await wait(p, 600);
  ok(SRV.board.some((x) => x.widget === 'note' && x.config.text === 'Call the baker' && x.config.repeat === 'weekly'), 'free-text reminder with weekly reset stored');
  await p.close();

  // report shortcut
  SRV.board = [{ widget: 'report', config: { report: 'sales_daily', preset: 'today', cid: 'r1' }, enabled: true }];
  p = await open('#/owner', { ob: { catalog: [{ key: 'sales_daily', name_bn: 'দৈনিক বিক্রি', name_en: 'Daily sales', allowed: true, needs_date: true }], runres: { columns: [{ key: 'net', label_bn: 'নিট', label_en: 'Net sales', type: 'money', role: 'measure' }], totals: { net: 12345 }, rows: [] } } });
  ok(/12,345/.test(await txt(p, '.ob-w[data-w=report]')) && /Net sales/.test(await txt(p, '.ob-w[data-w=report]')), 'report shortcut shows the headline total: ' + (await txt(p, '.ob-w[data-w=report]')).replace(/\s+/g, ' '));
  ok((await calls(p, 'report_run'))[0].p_filters.preset === 'today', 'report run with the chosen period');
  await p.click('.ob-w[data-w=report] .ob-main'); await wait(p, 600); ok(/#\/report\/sales_daily/.test(await p.evaluate(() => location.hash)), 'report widget opens the report');
  await p.context().close();

  // reset to default
  p = await open('#/owner'); await p.click('[data-act=ob_edit_toggle]'); await wait(p, 200); await p.click('[data-act=ob_reset]'); await wait(p, 900);
  ok(SRV.board.length === 17 && SRV.board[0].widget === 'sales_vs', 'reset puts the default set back (17 incl. backup + notifications kept in the list)');
  await p.context().close();

  // persists after reload (server list)
  SRV.board = [{ widget: 'exceptions', config: { cid: 'a' }, enabled: true }, { widget: 'sales_vs', config: { cid: 'b', label: 'Sales!' }, enabled: true }];
  p = await open('#/owner'); ok(JSON.stringify(await p.evaluate(() => [...document.querySelectorAll('.ob-w')].map((e) => e.dataset.w))) === '["exceptions","sales_vs"]' && /Sales!/.test(await txt(p, '.ob-w[data-w=sales_vs]')), 'saved board comes back in the same order with custom names');
  await p.context().close();

  // missing source modules: widget hidden, never an error text
  SRV.board = [];
  p = await open('#/owner', { ob: { missing: ['needs_you_oldest', 'payables_summary'] } });
  ok(await p.locator('.ob-w[data-w=needs_you],.ob-w[data-w=supp_dues]').count() === 0 && !/error|Error|failed/.test(await txt(p, '#ob_grid')) && await p.locator('.ob-w[data-w=cust_dues]').count() === 1, 'a missing function hides its widget (no error shown)');
  await p.close();

  // server table missing -> phone fallback
  SRV.board = [];
  p = await open('#/owner', { ob: { noBoard: true } });
  ok(await p.locator('.ob-w').count() >= 12, 'without the table the default board still shows');
  await p.click('[data-act=ob_edit_toggle]'); await p.click('.ob-w[data-w=exceptions] [data-act=ob_menu]'); await wait(p, 300); await pick(p, 'Remove'); await wait(p, 400);
  ok(/this phone/.test(await txt(p, '#ob_note')) && JSON.parse(await p.evaluate(() => localStorage.getItem('bos_ob_items_u1'))).every((x) => x.widget !== 'exceptions'), 'changes kept on the phone with a notice');
  await p.reload(); await wait(p, 1600); ok(await p.locator('.ob-w[data-w=exceptions]').count() === 0 && await p.locator('.ob-w').count() >= 11, 'phone copy survives a reload');
  await p.context().close();

  // offline: last values + banner (the phone has a copy of the board and of the last numbers)
  SRV.board = [];
  p = await open('#/owner', { init: `Object.defineProperty(navigator,'onLine',{get:()=>false,configurable:true});try{localStorage.setItem('bos_ob_items_u1',JSON.stringify([{widget:'sales_vs',config:{cid:'a'},enabled:true}]));localStorage.setItem('bos_ob_vals_u1',JSON.stringify({at:Date.now()-600000,v:{a:{value:'৳ 5,000',num:5000,tone:'ok',sub:'old numbers',route:'biz'}}}))}catch(e){}` });
  ok(/Offline/.test(await txt(p, '#ob_bar')) && /5,000/.test(await wt('sales_vs')) && /As of/i.test(await txt(p, '#ob_bar')), 'offline: banner + last numbers with their time: ' + (await txt(p, '#ob_bar')).replace(/\s+/g, ' '));
  ok((await calls(p, 'sales_summary')).length === 0, 'offline: nothing is requested'); await noOverflow(p, 'offline board'); await p.context().close();
  p = await open('#/owner'); ok(await p.evaluate(() => !!localStorage.getItem('bos_ob_vals_u1')), 'values are cached for offline use'); await p.context().close();

  // auto refresh every 2 minutes (speeded up to 1.5 s here)
  SRV.board = [{ widget: 'sales_vs', config: { cid: 'a' }, enabled: true }];
  p = await open('#/owner', { refreshMs: 1500 }); const n0 = await p.evaluate(() => window.__SALES_CALLS); await wait(p, 3600); const n1 = await p.evaluate(() => window.__SALES_CALLS);
  ok(n1 > n0, 'auto refresh runs while the board is open: ' + n0 + ' -> ' + n1); await p.evaluate(() => { location.hash = '#/home'; }); await wait(p, 800); const n2 = await p.evaluate(() => window.__SALES_CALLS); await wait(p, 3200); ok(await p.evaluate(() => window.__SALES_CALLS) === n2, 'auto refresh stops after leaving the board');
  await p.context().close();

  // Owner mode as Home (header ⋮ toggle)
  SRV.board = [];
  p = await open('#/home'); await p.click('#hd_dots'); await wait(p, 300); ok(await pick(p, 'Show the owner board as Home'), 'header ⋮ has the Owner mode toggle'); await wait(p, 1500);
  ok(await p.locator('#ob_main').count() === 1 && await p.locator('.ob-w').count() >= 12 && /#\/home/.test(await p.evaluate(() => location.hash)), 'Home now shows the owner board');
  await p.screenshot({ path: SP + '/oh_boardhome.png' });
  await p.click('[data-act=ob_home_off]'); await wait(p, 1200); ok(await p.locator('#ob_main').count() === 0 && await p.locator('#hv_main').count() === 1, 'back to the normal Home');
  await p.context().close();

  // switch OFF and non-owner
  p = await open('#/home', { ruleOff: true }); ok(await p.locator('.ownbig').count() === 0, 'switch OFF: no Owner mode button'); await p.evaluate(() => { location.hash = '#/owner'; }); await wait(p, 900); ok(/switched off/.test(await txt(p, '#ob_main')), 'switch OFF: friendly notice on #/owner'); await p.context().close();
  p = await open('#/owner', { owner: false }); ok(/#\/home/.test(await p.evaluate(() => location.hash)) && await p.locator('#ob_main').count() === 0, 'non-owner is sent home'); await p.context().close();

  log('JS errors:', errors.length ? [...new Set(errors)] : 'none'); ok(!errors.length, 'no JS errors');
  log('ownerboard_test fails:', bad);
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.error('OWNERBOARD TEST CRASH', e); process.exit(2); } })();
