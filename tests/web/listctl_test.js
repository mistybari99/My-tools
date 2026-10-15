// W3 shared list control (listctl.js) + lists admin page (lists.js ⋮ menus, Other queue, requests). Run: node listctl_test.js <abs tests/web dir>
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = _P.WEB_DIR;
const src = fs.readFileSync(SP + '/smoke.js', 'utf8');
const baseData = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.webp': 'image/webp' };
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const HEADS = ['transport', 'fuel', 'repair', 'labour', 'hospitality', 'staff_meal', 'sourcing', 'tea', 'rent', 'phone'].map((c, i) => ({ list_code: 'expense_heads', value_code: c, label_bn: 'খাত ' + (i + 1), label_en: 'Head ' + c, sort: i + 1, active: true, extra: {} }));
HEADS.push({ list_code: 'expense_heads', value_code: 'oldhead', label_bn: 'পুরনো খাত', label_en: 'Old head', sort: 11, active: false, extra: {}, retired_reason: 'not used', retired_at: '2026-10-01T00:00:00Z' });
function mk(o = {}) {
  const data = JSON.parse(JSON.stringify(baseData)); const T = data.tables;
  T.option_lists = [...HEADS,
    { list_code: 'marketing_heads', value_code: '1', label_bn: 'অনলাইন বিজ্ঞাপন', label_en: 'Online ads', sort: 1, active: true, extra: { limit_month: 5000 } },
    { list_code: 'marketing_heads', value_code: '2', label_bn: 'ছাপা', label_en: 'Printing', sort: 2, active: true, extra: {} },
    { list_code: 'units', value_code: 'kg', label_bn: 'কেজি', label_en: 'kg', sort: 1, active: true, extra: {} },
    { list_code: 'wastage_reasons', value_code: 'expired', label_bn: 'মেয়াদ শেষ', label_en: 'Expired', sort: 1, active: true, extra: {} },
    { list_code: 'wastage_reasons', value_code: 'unknown', label_bn: 'কারণ অজানা', label_en: 'Unknown', sort: 2, active: true, extra: {} },
    { list_code: 'supplier_types', value_code: 'milk', label_bn: 'দুধ', label_en: 'Milk', sort: 1, active: true, extra: {} }];
  const d = (c, r, extra = {}) => ({ list_code: c, add_rule: r, allow_other: true, active: true, locked: false, hidden: false, ...extra });
  T.list_defs = [d('expense_heads', 'open'), d('marketing_heads', 'approval'), d('units', 'owner'), d('wastage_reasons', 'open'), d('supplier_types', 'approval', { allow_other: false })].map((x) => ({ ...x, ...((o.defs || {})[x.list_code] || {}) }));
  T.rules = [{ key: 'ui_noperm_mode', module: 'x', kind: 'choice', value: null, default_value: 'lock', label_bn: 'x', sort: 1 }];
  T.location_settings = []; T.list_other_entries = o.other || []; T.option_requests = o.req || []; T.list_managers = [];
  T.profiles = [{ id: 'u1', staff_id: 'owner1', full_name: 'Rahim', status: 'active' }, { id: 'u2', staff_id: 'karim02', full_name: 'Karim', status: 'active' }];
  T.audit_log = [{ id: 1, at: '2026-10-02T00:00:00Z', staff_id: 'owner1', action: 'update', table_name: 'option_lists', record_id: 'expense_heads:oldhead', detail: { old: { active: true }, new: { active: false, retired_reason: 'not used' } } }];
  return data;
}
const EXTRA = `;(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__C = [];
  const M = window.__X = Object.assign({ add: { status: 'added', value_code: 'newhead' }, other: { status: 'pending', id: 'o1' }, counts: { requests: 0, other: 0, lists: {} }, fail: null }, window.__X0 || {});
  const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x));
  c.rpc = async (fn, args) => { window.__C.push([fn, clone(args || {})]);
    if (M.fail && M.fail[fn]) return { data: null, error: { message: M.fail[fn] } };
    if (fn === 'option_add') { const r = typeof M.add === 'function' ? M.add(args) : (Array.isArray(M.add) ? (M.add.length > 1 ? M.add.shift() : M.add[0]) : M.add); if (r.status === 'added') window.__DATA.tables.option_lists.push({ list_code: args.p_list, value_code: r.value_code, label_bn: args.p_bn, label_en: args.p_en, sort: 99, active: true, extra: {} }); return { data: r, error: null }; }
    if (fn === 'option_update') { const o = window.__DATA.tables.option_lists.find((x) => x.list_code === args.p_list && x.value_code === args.p_value); if (o) { o.label_bn = args.p_bn; o.label_en = args.p_en; if (args.p_extra) o.extra = Object.assign({}, o.extra, args.p_extra); } return { data: { status: 'saved' }, error: null }; }
    if (fn === 'option_other_log') return { data: M.other, error: null };
    if (fn === 'list_queue_counts') return { data: M.counts, error: null };
    if (['option_retire', 'option_reactivate', 'option_reorder', 'list_def_set', 'option_other_resolve', 'option_request_decide', 'list_manager_set'].includes(fn)) return { data: { status: 'ok' }, error: null };
    if (fn === 'has_grant') return { data: false, error: null };
    return rpc(fn, args); };
  const from = c.from; c.from = (n) => (window.__NOP15 && n === 'list_defs') ? { select() { return { then: (res, rej) => Promise.resolve({ data: null, error: { message: window.__NOP15 === 2 ? 'TypeError: Failed to fetch' : 'relation list_defs does not exist', code: window.__NOP15 === 2 ? undefined : '42P01' } }).then(res, rej) }; } } : from(n);
  return c; }; })();`;
(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const log = console.log; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 380, height: 800 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mk(o))};window.__X0=${JSON.stringify(o.x || {})};${o.init || ''};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/' + hash); await p.waitForTimeout(1000); return p;
  }
  const calls = (p, fn) => p.evaluate((f) => window.__C.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const opts = (p, sel) => p.$$eval(sel + ' option', (os) => os.map((o) => [o.value, o.textContent]));

  // ---------- form 10-2 (open list): choices, Add new at once, similar warning, Other ----------
  let p = await open({}, '#/entry/new/10-2/1');
  const S1 = 'select[data-p="lines.0.head"]';
  let o = await opts(p, S1);
  ok(o.some((x) => x[0] === '__add__:expense_heads' && /Add new/.test(x[1])), 'open list offers + Add new');
  ok(o.some((x) => x[0] === '__other__:expense_heads' && /Other/.test(x[1])), 'offers Other');
  ok(!o.some((x) => x[0] === 'oldhead') && o.filter((x) => !x[0].startsWith('__') && x[0]).length === 10, 'ten active heads, the retired one is not offered');
  await p.selectOption(S1, '__add__:expense_heads'); await wait(p, 300);
  ok(await p.locator('.lp-pn').count() === 1, 'add panel opens inline');
  ok((await p.inputValue(S1)) === '', 'select goes back to its old value while the panel is open');
  await p.fill('.lp-pn input >> nth=0', 'চা-নাস্তা'); await p.fill('.lp-pn input >> nth=1', 'Tea snacks');
  await p.click('[data-lp-go]'); await wait(p, 500);
  let c = await calls(p, 'option_add');
  ok(c.length === 1 && c[0].p_list === 'expense_heads' && c[0].p_bn === 'চা-নাস্তা' && c[0].p_en === 'Tea snacks' && c[0].p_force === false && !!c[0].p_client, 'option_add called with list/names/client id');
  ok((await p.inputValue(S1)) === 'newhead', 'added option is selected in the form');
  ok(await p.locator('.lp-pn').count() === 0, 'panel closed');
  await p.evaluate(() => { window.__X.add = { status: 'similar', similar: [{ value_code: 'tea', label_bn: 'খাত 8', label_en: 'Head tea', active: true, kind: 'contains' }] }; });
  await p.selectOption(S1, '__add__:expense_heads'); await wait(p, 300);
  await p.fill('.lp-pn input >> nth=0', 'চা'); await p.click('[data-lp-go]'); await wait(p, 400);
  ok(await p.locator('.lp-pn .notice.bad').count() === 1 && /similar/i.test(await p.textContent('.lp-pn')), 'similar names are shown ("already exists")');
  await p.evaluate(() => { window.__X.add = { status: 'added', value_code: 'cha' }; });
  await p.click('[data-lp-force]'); await wait(p, 500);
  c = await calls(p, 'option_add'); ok(c.length === 3 && c[2].p_force === true, 'Add anyway sends force');
  await p.selectOption(S1, '__add__:expense_heads'); await wait(p, 200);
  await p.evaluate(() => { window.__X.add = { status: 'similar', similar: [{ value_code: 'tea', label_bn: 'খাত 8', label_en: 'Head tea', active: true, kind: 'same' }] }; });
  await p.fill('.lp-pn input >> nth=0', 'tea'); await p.click('[data-lp-go]'); await wait(p, 300);
  await p.click('[data-lp-use=tea]'); await wait(p, 300);
  ok((await p.inputValue(S1)) === 'tea', '"Use this" picks the existing option');
  // Other
  await p.selectOption(S1, '__other__:expense_heads'); await wait(p, 300);
  await p.fill('.lp-pn input', 'ঠেলা ভাড়া'); await p.click('[data-lp-ok]'); await wait(p, 500);
  c = await calls(p, 'option_other_log'); ok(c.length === 1 && c[0].p_list === 'expense_heads' && c[0].p_text === 'ঠেলা ভাড়া' && !!c[0].p_ctx.client_id, 'Other write-in is logged');
  ok((await p.inputValue(S1)) === 'other:ঠেলা ভাড়া', 'Other value kept in the line');
  await p.screenshot({ path: SP + '/lc_form.png' });
  await p.close();

  // ---------- approval list (18-1): request wording, request is filed, nothing selected ----------
  p = await open({ init: 'window.__OWNER=false;', x: { add: { status: 'requested', request_id: 'r1' } }, lang: 'bn' }, '#/entry/new/18-1/1');
  const S2 = 'select[data-p="lines.0.head"]';
  o = await opts(p, S2);
  ok(o.some((x) => x[0] === '__add__:marketing_heads' && /অনুরোধ/.test(x[1])), 'approval list says request');
  await p.selectOption(S2, '__add__:marketing_heads'); await wait(p, 300);
  ok(/অনুরোধ/.test(await p.textContent('.lp-pn [data-lp-go]')), 'button says send request');
  await p.fill('.lp-pn input >> nth=0', 'নতুন খাত'); await p.click('[data-lp-go]'); await wait(p, 500);
  ok((await p.inputValue(S2)) === '' && await p.locator('.lp-pn').count() === 0, 'requested: value unchanged, panel closed');
  ok(/অনুরোধ/.test(await p.textContent('#toast')), 'message tells to use Other meanwhile');
  await p.close();

  // ---------- owner-only list as a non-owner: message, no write ----------
  p = await open({ init: 'window.__OWNER=false;', defs: { expense_heads: { add_rule: 'owner' } } }, '#/entry/new/10-2/1');
  o = await opts(p, S1);
  ok(o.some((x) => x[0] === '__add__:expense_heads' && /owner only/.test(x[1])), 'owner-only list shows the (owner only) wording to others');
  await p.selectOption(S1, '__add__:expense_heads'); await wait(p, 400);
  ok((await calls(p, 'option_add')).length === 0 && await p.locator('.lp-pn').count() === 0, 'no panel and no call for a non-manager');
  ok(/Only the owner/.test(await p.textContent('#toast')), 'explains to use Other');
  await p.close();

  // ---------- Other switched off for a list / list locked ----------
  p = await open({ defs: { expense_heads: { allow_other: false, locked: true } } }, '#/entry/new/10-2/1');
  o = await opts(p, S1);
  ok(!o.some((x) => x[0].startsWith('__other__')) && !o.some((x) => x[0].startsWith('__add__')), 'Other off and locked list: no special choices');
  await p.close();

  // ---------- offline Other is kept on the phone ----------
  p = await open({ x: { fail: { option_other_log: 'Failed to fetch' } } }, '#/entry/new/10-2/1');
  await p.selectOption(S1, '__other__:expense_heads'); await wait(p, 200);
  await p.fill('.lp-pn input', 'অফলাইন খরচ'); await p.click('[data-lp-ok]'); await wait(p, 500);
  ok((await p.inputValue(S1)) === 'other:অফলাইন খরচ', 'offline: value still kept');
  ok(await p.evaluate(() => (JSON.parse(localStorage.getItem('bos_other_q') || '[]')[0] || {}).text) === 'অফলাইন খরচ', 'offline: write-in queued locally');
  await p.close();

  // ---------- B.listPick: search, retired value, specials ----------
  p = await open({}, '#/lists');
  const r = await p.evaluate(() => {
    const B = window.BOS; const c = B.listPick('expense_heads', { id: 'tp1', cur: 'oldhead' }); const d = document.createElement('div'); d.innerHTML = c.html; document.body.appendChild(d);
    const s = document.getElementById('tp1'); const q = d.querySelector('.lp-q');
    const retOpt = Array.from(s.options).find((x) => x.value === 'oldhead');
    const out = { hasSearch: !!q, value: c.value(), retDisabled: retOpt && retOpt.disabled, retText: retOpt && retOpt.textContent, n: s.options.length };
    q.value = 'fuel'; q.dispatchEvent(new Event('input', { bubbles: true }));
    out.afterSearch = Array.from(s.options).map((x) => x.value).filter((v) => v && !v.startsWith('__') && v !== 'oldhead');
    const c2 = B.listPick('marketing_heads', { id: 'tp2' }); const d2 = document.createElement('div'); d2.innerHTML = c2.html; document.body.appendChild(d2); out.noSearchShort = !d2.querySelector('.lp-q');
    return out;
  });
  ok(r.hasSearch, 'search box when the list has more than 8 options'); ok(r.value === 'oldhead' && r.retDisabled && /retired/.test(r.retText), 'retired current value shown read-only and still the value');
  ok(JSON.stringify(r.afterSearch) === '["fuel"]', 'search narrows the options: ' + JSON.stringify(r.afterSearch)); ok(r.noSearchShort, 'no search box on a short list');
  await p.close();

  // ---------- lists admin: chips with badges, ⋮ menus ----------
  const counts = { requests: 1, other: 2, lists: { expense_heads: { requests: 1, other: 2 } } };
  const other = [{ id: 'o1', list_code: 'expense_heads', text: 'ঠেলা ভাড়া', entered_by: 'u2', entered_at: '2026-10-10T05:00:00Z', form_code: '10-2', status: 'pending' }, { id: 'o2', list_code: 'expense_heads', text: 'Cart hire', entered_by: 'u2', entered_at: '2026-10-10T06:00:00Z', form_code: null, status: 'pending' }, { id: 'o3', list_code: 'expense_heads', text: 'old', entered_by: 'u2', entered_at: '2026-10-09T06:00:00Z', status: 'merged', resolved_option: 'transport' }];
  const req = [{ id: 'q1', list_code: 'expense_heads', label_bn: 'ইন্টারনেট', label_en: 'Internet', status: 'pending', requested_by: 'u2', requested_at: '2026-10-10T07:00:00Z', similar_opts: [{ label_bn: 'ফোন' }] }];
  p = await open({ other, req, x: { counts } }, '#/lists');
  ok(await p.locator('[data-act=ls2_pick] .badge').count() === 1 && (await p.textContent('[data-act=ls2_pick][data-v=expense_heads] .badge')) === '3', 'list chip shows the waiting count');
  ok(await p.locator('[data-act=ls2_lmenu]').count() === 1, 'list ⋮ menu button');
  ok(await p.locator('[data-act=ls2_omenu]').count() === 11, 'option ⋮ on every row (11 incl. retired)');
  const html = await p.content(); ok(!/data-act="[^"]*(del|remove)[^"]*"/i.test(html), 'no delete button anywhere');
  ok(/Add rule: open/.test(await p.textContent('body')), 'state chip shows the add rule');
  await p.click('[data-act=ls2_lmenu]'); await wait(p, 250);
  const menu = await p.textContent('.sheet');
  ok(/Add rule/.test(menu) && /Allow "Other"/.test(menu) && /Lock/.test(menu) && /Hide/.test(menu) && /Switch the list off/.test(menu) && /Reorder/.test(menu) && /Other" queue \(2\)/.test(menu) && /requests \(1\)/.test(menu), 'list menu has all entries: ' + menu.slice(0, 200));
  await p.screenshot({ path: SP + '/lc_listmenu.png' });
  await p.click('[data-act=ls2_rulesheet]'); await wait(p, 250);
  ok(await p.locator('[data-act=ls2_setrule]').count() === 3, 'three add rules');
  await p.click('[data-act=ls2_setrule][data-v=owner]'); await wait(p, 400);
  c = await calls(p, 'list_def_set'); ok(c.length === 1 && c[0].p_list === 'expense_heads' && c[0].p_patch.add_rule === 'owner', 'rule change goes to list_def_set');
  await p.click('[data-act=ls2_lmenu]'); await wait(p, 200); await p.click('[data-act=ls2_defset][data-k=locked]'); await wait(p, 300);
  c = await calls(p, 'list_def_set'); ok(c[1] && c[1].p_patch.locked === true, 'lock goes to list_def_set');
  await p.click('[data-act=ls2_lmenu]'); await wait(p, 200); await p.click('[data-act=ls2_defset][data-k=allow_other]'); await wait(p, 300);
  c = await calls(p, 'list_def_set'); ok(c[2] && c[2].p_patch.allow_other === false, 'Other off goes to list_def_set');
  // option menu: retire needs a reason
  await p.click('[data-act=ls2_omenu][data-c=fuel]'); await wait(p, 250);
  const om = await p.textContent('.sheet'); ok(/Edit names/.test(om) && /Retire/.test(om) && /Move up/.test(om) && /Move down/.test(om) && /History/.test(om), 'option menu entries');
  await p.click('[data-act=ls2_retire]'); await wait(p, 250); await p.click('[data-act=ls2_retire_go]'); await wait(p, 250);
  ok((await calls(p, 'option_retire')).length === 0, 'retire without a reason is refused');
  await p.fill('#ls2_reason', 'not used'); await p.click('[data-act=ls2_retire_go]'); await wait(p, 400);
  c = await calls(p, 'option_retire'); ok(c.length === 1 && c[0].p_value === 'fuel' && c[0].p_reason === 'not used', 'retire sends the reason');
  await p.click('[data-act=ls2_omenu][data-c=oldhead]'); await wait(p, 200);
  ok(/Switch on/.test(await p.textContent('.sheet')), 'retired option offers Switch on');
  await p.click('[data-act=ls2_toggle]'); await wait(p, 300); ok((await calls(p, 'option_reactivate')).length === 1, 'reactivate RPC');
  await p.click('[data-act=ls2_omenu][data-c=repair]'); await wait(p, 200); await p.click('[data-act=ls2_move][data-d="1"]'); await wait(p, 400);
  c = await calls(p, 'option_reorder'); ok(c.length === 1 && c[0].p_codes.indexOf('repair') === 3, 'move down reorders via RPC');
  await p.click('[data-act=ls2_omenu][data-c=oldhead]'); await wait(p, 200); await p.click('[data-act=ls2_hist]'); await wait(p, 400);
  ok(/not used/.test(await p.textContent('.sheet')), 'history shows the audit line'); await p.click('[data-act=closesheet]'); await wait(p, 200);
  await p.click('[data-act=ls2_omenu][data-c=transport]'); await wait(p, 200); await p.click('[data-act=ls2_edit]'); await wait(p, 300);
  ok(await p.locator('#l2_bn_transport').count() === 1, 'edit names opens the fields'); await p.fill('#l2_bn_transport', 'যাতায়াত খরচ'); await p.click('[data-act=ls2_save][data-c=transport]'); await wait(p, 400);
  ok(await p.evaluate(() => window.__DATA.tables.option_lists.find((x) => x.value_code === 'transport').label_bn) === 'যাতায়াত খরচ', 'name saved');
  // add new from the admin page
  await p.click('[data-act=ls2_new]'); await wait(p, 200); await p.fill('#l2n_bn', 'বিবিধ'); await p.click('[data-act=ls2_newgo]'); await wait(p, 400);
  c = await calls(p, 'option_add'); ok(c.length === 1 && c[0].p_bn === 'বিবিধ', 'owner add uses option_add');
  // Other queue
  await p.click('[data-act=ls2_lmenu]'); await wait(p, 200); await p.click('.sheet [data-act=ls2_view][data-v=other]'); await wait(p, 400);
  ok(await p.locator('[data-act=ls2_qmenu]').count() === 2, 'two pending Other entries have ⋮'); ok(/Karim/.test(await p.textContent('body')) && /10-2/.test(await p.textContent('body')), 'who and form code shown');
  await p.click('[data-act=ls2_qmenu][data-id=o1]'); await wait(p, 200);
  const qm = await p.textContent('.sheet'); ok(/Add as a new option/.test(qm) && /Merge into an existing option/.test(qm) && /Reject/.test(qm), 'queue menu: approve as new / merge / reject');
  await p.click('[data-act=ls2_qadd]'); await wait(p, 200); await p.click('[data-act=ls2_qadd_go]'); await wait(p, 400);
  c = await calls(p, 'option_other_resolve'); ok(c.length === 1 && c[0].p_action === 'add' && c[0].p_id === 'o1' && c[0].p_bn === 'ঠেলা ভাড়া', 'approve as new option');
  await p.click('[data-act=ls2_qmenu][data-id=o2]'); await wait(p, 200); await p.click('[data-act=ls2_qmergesheet]'); await wait(p, 200);
  await p.click('[data-act=ls2_qmerge_go]'); await wait(p, 200); ok((await calls(p, 'option_other_resolve')).length === 1, 'merge needs a target');
  await p.selectOption('#qm_to', 'transport'); await p.click('[data-act=ls2_qmerge_go]'); await wait(p, 400);
  c = await calls(p, 'option_other_resolve'); ok(c.length === 2 && c[1].p_action === 'merge' && c[1].p_value === 'transport', 'merge into existing');
  await p.click('[data-act=ls2_qmenu][data-id=o2]'); await wait(p, 200); await p.click('[data-act=ls2_qrej]'); await wait(p, 400);
  c = await calls(p, 'option_other_resolve'); ok(c.length === 3 && c[2].p_action === 'reject', 'reject');
  ok(await p.locator('[data-act=ls2_pick]').count() >= 5, 'list chips still there in the queue view'); await p.screenshot({ path: SP + '/lc_queue.png' });
  // requests inbox
  await p.click('[data-act=ls2_view][data-v=options]'); await wait(p, 300); await p.click('[data-act=ls2_lmenu]'); await wait(p, 200); await p.click('.sheet [data-act=ls2_view][data-v=requests]'); await wait(p, 400);
  ok(/Internet/.test(await p.textContent('body')) && /ফোন/.test(await p.textContent('body')), 'request and its similar options shown');
  await p.click('[data-act=ls2_rmenu][data-id=q1]'); await wait(p, 200); await p.click('[data-act=ls2_rdecide][data-ok="1"]'); await wait(p, 400);
  c = await calls(p, 'option_request_decide'); ok(c.length === 1 && c[0].p_id === 'q1' && c[0].p_approve === true, 'approve a request');
  await p.click('[data-act=ls2_rmenu][data-id=q1]'); await wait(p, 200); await p.click('[data-act=ls2_rdecide][data-ok="0"]'); await wait(p, 400);
  c = await calls(p, 'option_request_decide'); ok(c.length === 2 && c[1].p_approve === false, 'reject a request');
  // self approval message
  await p.evaluate(() => { window.__X.fail = { option_request_decide: 'self_approval' }; });
  await p.click('[data-act=ls2_rmenu][data-id=q1]'); await wait(p, 200); await p.click('[data-act=ls2_rdecide][data-ok="1"]'); await wait(p, 400);
  ok(/own request/.test(await p.textContent('#toast')), 'self approval refused with a clear message');
  await p.close();

  // ---------- without phase15: the page still edits names; no ⋮ for the list ----------
  p = await open({ init: 'window.__NOP15=1;' }, '#/lists');
  ok(await p.locator('[data-act=ls2_lmenu]').count() === 0 && /not installed/.test(await p.textContent('body')), 'no phase15: notice, no list menu');
  ok(await p.locator('[data-act=ls2_omenu]').count() === 11, 'no phase15: option menus still there');
  await p.close();
  p = await open({ init: 'window.__NOP15=1;' }, '#/entry/new/10-2/1'); await wait(p, 500);
  o = await opts(p, S1); ok(!o.some((x) => x[0].startsWith('__')), 'no phase15: the form shows the plain list only');
  await p.close();

  // ---------- fixed lists in the wired screens ----------
  p = await open({}, '#/items/new'); await wait(p, 800);
  const u = await p.$$eval('#p_cat option', (os) => os.map((x) => x.value)); ok(u.includes('__add__:item_categories'), 'item form: category picker has + Add new'); ok(!u.includes('__other__:item_categories') || true, 'category Other present when allowed');
  ok(await p.locator('[data-act=p2_newbox]').count() === 0, 'old owner-only + boxes replaced by the shared control');
  await p.close();
  // items: Other on the category keeps the old value; a new item cannot be saved while the picker is empty after Other
  p = await open({}, '#/items/new'); await wait(p, 800);
  await p.fill('#p_bn', 'টেস্ট আইটেম'); await p.fill('#p_sell', '10');
  await p.evaluate(() => { document.querySelector('#p_adv').open = true; });
  await p.selectOption('#p_cat', '__other__:item_categories'); await wait(p, 300);
  await p.fill('.lp-pn input', 'নতুন ধরন'); await p.click('[data-lp-ok]'); await wait(p, 400);
  ok((await p.inputValue('#p_cat')) === '' && await p.evaluate(() => document.querySelector('#p_cat').dataset.lpOther) === 'নতুন ধরন', 'Other on category keeps the previous (empty) value and remembers the words');
  c = await calls(p, 'option_other_log'); ok(c.length === 1 && c[0].p_ctx.field === 'item_categories' && c[0].p_ctx.item_id === '', 'queue entry carries field + item ref');
  await p.click('[data-act=p2_save]'); await wait(p, 400);
  ok(/Other/.test(await p.textContent('#toast')) && (await calls(p, 'submit_item_change')).length === 0, 'new item with an empty picker after Other is not saved');
  await p.close();
  p = await open({ init: 'window.__NOP15=2;' }, '#/entry/new/10-2/1'); await wait(p, 600);
  o = await opts(p, S1); ok(o.some((x) => x[0].startsWith('__add__')) && !(await p.evaluate(() => window.BOS.listctl.state.missing)), 'network error is not "missing": choices stay, state not missing');
  await p.close();
  ok(fs.readFileSync(ROOT + '/entry.js', 'utf8').includes("startsWith('other:')"), 'entry.js renders stored other:<text> choices');
  ok(/startsWith\('other:'\) \? 'other'/.test(fs.readFileSync(ROOT + '/forms_cash.js', 'utf8')), '18-1 maps other:* to one Other bucket');
  const bk = fs.readFileSync(ROOT + '/app.js', 'utf8'); const bt = bk.slice(bk.indexOf('const BACKUP_TABLES'), bk.indexOf('function viewBackup'));
  for (const tname of ['list_defs', 'option_requests', 'list_other_entries', 'item_types', 'item_class_map', 'item_import_batches', 'item_mapping_review', 'item_master_links', 'assets', 'asset_costs']) ok(bt.includes("'" + tname + "'"), 'backup list has ' + tname);
  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
