// Step Vis: web/optviews.js (owner screen + nav hook) with the real web/ia.js. Plain node, mocked rpc, no browser: node tests/web/optviews_test.js
const _P = require('./_paths');
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = _P.WEB_DIR;
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৿]/;

function mk(lang, owner = true) {
  const calls = [], toasts = [], sheets = [], handlers = {}, shells = [], els = {}, listeners = {}, capture = [];
  const impl = { rpc: async () => ({ data: null, error: null }), from: {} };
  const qb = (tbl) => { const o = { select: () => o, eq: () => o, in: () => o, order: () => o, limit: () => o, then: (res, rej) => Promise.resolve(impl.from[tbl] || { data: [] }).then(res, rej) }; return o; };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const TT = { home: L('হোম', 'Home', 'হোম'), items: L('আইটেম', 'Items', 'Item'), pos: L('POS', 'POS', 'POS'), dues: L('বাকি', 'Dues', 'বাকি'), lists: L('তালিকা', 'Lists', 'তালিকা') };
  const A = { sb: { rpc: async (fn, args) => { calls.push([fn, args]); return impl.rpc(fn, args); }, from: (t) => qb(t) },
    S: { lang, ctx: { is_owner: owner, perms: {}, profile: { id: 'me-1' } } }, esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), fail: (e) => toasts.push('FAIL:' + e.message), shell: (t, h) => shells.push([t, h]), openSheet: (h) => sheets.push(h), closeSheet: () => {}, H: handlers,
    nm: (o, a, b) => (lang === 'en' ? o[b || 'name_en'] || o.name_en : o[a || 'name_bn'] || o.name_en), t: (k) => { const x = TT[k]; return x ? (lang === 'en' ? x.en : lang === 'mix' ? x.mix : x.bn) : k; } };
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en), rule: (k, d) => d };
  const document = { querySelector: (s) => (els[s] = els[s] || { innerHTML: '', value: '', hidden: false, checked: false }), addEventListener: (ev, fn, cap) => { if (cap) capture.push(fn); else listeners[ev] = fn; } };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {} };
  const ctx = vm.createContext({ window: win, document, Number, JSON, Promise, Date, console, setTimeout, Object, Array, String, Math, crypto: { randomUUID: () => 'cid-' + Math.random().toString(16).slice(2) } });
  ['ia.js', 'optviews.js'].forEach((f) => vm.runInContext(fs.readFileSync(path.join(ROOT, f), 'utf8'), ctx, { filename: f }));
  return { A, B, O: B.optviews, calls, toasts, sheets, handlers, shells, els, impl, listeners, capture, pages: win.BOS_PAGES };
}
const html = (t) => t.shells.map((s) => s[1]).join('') + Object.values(t.els).map((e) => e.innerHTML || '').join('') + t.sheets.join('');
const click = (t, act, ds) => t.handlers[act]({ dataset: ds || {} });
const sales = { user: { id: 'u-sales', staff_id: 's1', name: 'Sales', status: 'active' }, is_owner: false, roles: ['salesperson'], locations: [1], perms: { POS: { view: true, enter: true, approve: false }, '03-1': { view: true, enter: false, approve: false } },
  grants: ['view_cost'], overrides: [], role_defaults: [], effective: [{ key: 'r:dues', mode: 'locked', src: 'role' }, { key: 'r:items', mode: 'hide', src: 'user' }] };

(async () => {
  // ---- 1. languages ----
  {
    const t = mk('en'); let n = 0, ok3 = true, okEn = true, bad = '';
    Object.entries(t.O.X).forEach(([k, v]) => { n++; if (!(v.bn && v.en && v.mix)) { ok3 = false; bad += ' 3:' + k; } if (BN.test(v.en)) { okEn = false; bad += ' en:' + k; } });
    chk('all ' + n + ' strings have bn, en and mix' + bad, ok3);
    chk('no English-slot string has a Bangla letter' + bad, okEn);
    chk('Bangla mode shows Bangla, mix mode mixes', BN.test(mk('bn').O.T('show')) && /Show/.test(mk('mix').O.T('show')) && /Hide/.test(mk('mix').O.T('bHide')) && BN.test(mk('mix').O.T('intro')));
    const rec = t.B.IA.find((r) => r.id === 'optviews');
    chk('ia.js record: settings group, 3 labels, English label has no Bangla, owner only', rec && rec.group === 'settings' && rec.label.length === 3 && !BN.test(rec.label[1]) && BN.test(rec.label[0]));
    chk('ia.js record visible to the owner only', rec.ok({ own: true }) === true && rec.ok({ own: false }) === false);
    chk('route is registered as a page', typeof t.pages.optviews === 'function');
  }
  // ---- 2. cache / load / missing data ----
  {
    const t = mk('en');
    t.impl.rpc = async () => ({ data: [{ key: 'r:items', mode: 'hide', src: 'user' }, { key: 'r:dues', mode: 'locked', src: 'role' }, { key: 'r:lists', mode: 'show', src: 'user' }, { key: 'r:home', mode: 'hide', src: 'user' }, { key: 'bad', mode: 'zz' }], error: null });
    chk('before load: nothing hidden, apply is identity', t.O.hidden('r:items') === false && t.O.mode('r:items') === 'show');
    const list0 = [{ key: 'r:items', label: 'Items', ok: true }];
    chk('apply with no data returns the same list', t.O.apply(list0) === list0);
    chk('load resolves true and asks the server once', (await t.O.load()) === true && (await t.O.load()) === true && t.calls.filter((c) => c[0] === 'my_option_views').length === 1);
    chk('hide / locked kept, show and protected r:home and bad rows ignored', t.O.mode('r:items') === 'hide' && t.O.mode('r:dues') === 'locked' && t.O.mode('r:lists') === 'show' && t.O.mode('r:home') === 'show' && t.O.mode('bad') === 'show');
    const out = t.O.apply([{ key: 'r:items', label: 'Items', ok: true }, { key: 'r:dues', label: 'Dues', ok: false }, { key: 'r:pos', label: 'POS', ok: true }, { key: 'r:lists', label: 'Lists', ok: false }]);
    chk('hide removes the entry, even when permitted', !out.some((e) => e.key === 'r:items'));
    const dues = out.find((e) => e.key === 'r:dues');
    chk('locked stays, becomes visible (ok true), tagged, flag vlock', dues && dues.ok === true && dues.vlock === true && /locked/.test(dues.label));
    chk('untouched entries stay as they were (show = today)', out.find((e) => e.key === 'r:pos').ok === true && out.find((e) => e.key === 'r:lists').ok === false && out.length === 3);
    // a failing server leaves everything as before
    const u = mk('en'); u.impl.rpc = async () => ({ data: null, error: { message: 'Could not find the function public.my_option_views' } });
    chk('missing database function: load false, apply identity, no throw', (await u.O.load()) === false && u.O.apply(list0) === list0);
    const w = mk('en'); w.impl.rpc = async () => { throw new Error('network'); };
    chk('network error: load false, nothing hidden', (await w.O.load()) === false && w.O.hidden('r:items') === false);
    const x = mk('en'); x.A.S.ctx = null;
    chk('no logged-in person: load false', (await x.O.load()) === false && x.calls.length === 0);
  }
  // ---- 3. keys and the locked click ----
  {
    const t = mk('en');
    t.impl.rpc = async () => ({ data: [{ key: 'r:dues', mode: 'locked', src: 'user' }, { key: 'f:03-1', mode: 'locked', src: 'user' }], error: null });
    await t.O.load();
    chk('route -> key: page, two-segment route, form, entry', t.O.keyOfRoute('dues') === 'r:dues' && t.O.keyOfRoute('#/settings2/units') === 'r:settings2/units' && t.O.keyOfRoute('form/03-1') === 'f:03-1' && t.O.keyOfRoute('entry/new/03-1') === 'f:03-1' && t.O.keyOfRoute('') === null);
    const cap = t.capture[0];
    const ev = (v, act) => { const e = { prevented: false, stopped: false, target: { closest: () => ({ dataset: { act: act || 'nav_go', v } }) }, preventDefault() { e.prevented = true; }, stopPropagation() { e.stopped = true; }, stopImmediatePropagation() { e.stopped = true; } }; return e; };
    const e1 = ev('dues'); cap(e1);
    chk('tapping a locked entry is caught and opens the ask-the-owner sheet', e1.prevented && e1.stopped && t.sheets.length === 1 && /Ask the owner|ask the owner/.test(t.sheets[0]) && /locked/i.test(t.sheets[0]));
    chk('the sheet names the option and has a close button', /Dues/.test(t.sheets[0]) && /closesheet/.test(t.sheets[0]));
    const e2 = ev('items'); cap(e2);
    chk('a normal entry is not touched', !e2.prevented && !e2.stopped && t.sheets.length === 1);
    const e3 = ev('form/03-1', 'go'); cap(e3);
    chk('a locked form (go) is caught too', e3.prevented && t.sheets.length === 2);
    const e4 = { target: { closest: () => { throw new Error('boom'); } }, preventDefault() { throw new Error('x'); } };
    let thrown = false; try { cap(e4); } catch (e) { thrown = true; }
    chk('a failure in the hook never breaks navigation', !thrown);
    const u = mk('en'); const e5 = ev('dues'); u.capture[0](e5);
    chk('no data loaded: clicks pass through', !e5.prevented && u.sheets.length === 0);
  }
  // ---- 4. owner screen ----
  {
    const t = mk('en', false);
    await t.pages.optviews();
    chk('non-owner: notice only, no rpc, no list', /Only the owner/.test(html(t)) && t.calls.length === 0 && !/ov_set/.test(html(t)));
  }
  {
    const t = mk('en', true);
    t.impl.from.profiles = { data: [{ id: 'u-sales', staff_id: 's1', full_name: 'Sales One', status: 'active' }] };
    t.impl.from.roles = { data: [{ code: 'storekeeper', name_bn: 'স্টোর', name_en: 'Storekeeper' }] };
    t.impl.from.forms = { data: [{ code: '03-1', area: 'cash', name_bn: 'ক্যাশ', name_en: 'Cash voucher', sort: 1, enabled: true }, { code: '39-1', area: 'stock', name_bn: 'স্টক', name_en: 'Stock form', sort: 2, enabled: true }] };
    t.impl.rpc = async (fn) => {
      if (fn === 'option_views_for_user') return { data: sales, error: null };
      if (fn === 'permission_recommendations') return { data: { is_owner: false,
        recommended_missing: [{ item: 'miss:report_sales', grant: 'report_sales', label: { bn: 'বিক্রির রিপোর্ট', mix: 'Sales report', en: 'Reports: Sales' }, reason: { bn: 'দরকার', mix: 'দরকার', en: 'Usually needed by this role' }, ignored: false }],
        not_recommended_combo: [{ item: 'combo:purchase_entry|supplier_pay', a: 'purchase_entry', b: 'supplier_pay', reason: { bn: 'ঝুঁকি', mix: 'ঝুঁকি', en: 'Enter and pay should be two people' }, ignored: false }, { item: 'combo:view_cost|price_override', a: 'view_cost', b: 'price_override', reason: { bn: 'ঝুঁকি', mix: 'ঝুঁকি', en: 'Cost and price' }, ignored: true }],
        unused: [{ item: 'unused:f:39-1', key: 'f:39-1', suggest: 'hide', reason: { bn: 'অনুমতি নেই', mix: 'অনুমতি নেই', en: 'No permission for this form; hide it if never needed' }, ignored: false }], ignored: [] }, error: null };
      return { data: { changed: 1 }, error: null };
    };
    await t.pages.optviews();
    const body = t.els['#ov_body'].innerHTML;
    chk('owner: person picker lists people and roles', /id="ov_who"/.test(body) && /u:u-sales/.test(body) && /r:storekeeper/.test(body) && /s1 · Sales One/.test(body));
    chk('no rpc before a person is picked', t.calls.length === 0);
    await t.O.pick('u:u-sales');
    chk('picking a person reads that person and the advice', t.calls[0][0] === 'option_views_for_user' && t.calls[0][1].p_user === 'u-sales' && t.calls[1][0] === 'permission_recommendations');
    const lst = t.els['#ov_list'].innerHTML;
    chk('list is grouped like ia.js (English group names) with 3 chips per option', /Sales &amp; POS/.test(lst) && /Staff, Roles &amp; Permissions|Administration &amp; Settings/.test(lst) && (lst.match(/data-act="ov_set"/g) || []).length === 3 * (lst.match(/class="ov-row"/g) || []).length);
    const rowOf = (k) => { const i = lst.indexOf('data-k="' + k + '"'); return i < 0 ? '' : lst.slice(i, i + 1400); };
    const rowPos = rowOf('r:pos').split('class="ov-row"')[0], rowItems = rowOf('r:items').split('class="ov-row"')[0], rowDues = rowOf('r:dues').split('class="ov-row"')[0];
    chk('permission status: POS granted, items not granted (from the chosen person, not the owner)', /Granted/.test(rowPos) && /Not granted/.test(rowItems));
    chk('current mode marks: items = Hide (user), dues = Locked (from role)', /data-m="hide"[^>]*>|aria-pressed="true"[^>]*data-m="hide"/.test(rowItems) && /class="mini on primary" data-act="ov_set" data-k="r:items" data-m="hide"/.test(rowItems) && /class="mini on primary" data-act="ov_set" data-k="r:dues" data-m="locked"/.test(rowDues) && /from role/.test(rowDues));
    chk('forms are listed too (cash form granted from perms, stock form not)', /f:03-1/.test(lst) && /f:39-1/.test(lst) && /Granted/.test(rowOf('f:03-1').split('class="ov-row"')[0]) && /Not granted/.test(rowOf('f:39-1').split('class="ov-row"')[0]));
    chk('home is not an option row; optviews row cannot be hidden or locked (buttons disabled)', !/data-k="r:home"/.test(lst) && /data-m="hide" aria-pressed="false" disabled/.test(rowOf('r:optviews')) && /data-m="locked" aria-pressed="false" disabled/.test(rowOf('r:optviews')));
    chk('hint next to the chips for a never-needed form, with a one-tap apply', /Suggest: Hide/.test(rowOf('f:39-1')) && /ov_reco_apply" data-i="unused:f:39-1"/.test(rowOf('f:39-1')));
    chk('bulk buttons present', ['hide_ng', 'show_all', 'locked_ng', 'reset'].every((m) => new RegExp('data-act="ov_bulk" data-m="' + m + '"').test(t.els['#ov_bulk'].innerHTML)));
    const rec = t.els['#ov_reco'].innerHTML;
    chk('advice panel: says advice only, 3 sections, grant label, combo with both grants and reason', /advice only/.test(rec) && /Usually needed, not given/.test(rec) && /Reports: Sales/.test(rec) && /purchase_entry \+ supplier_pay/.test(rec) && /Enter and pay should be two people/.test(rec) && /Hide if never needed/.test(rec));
    chk('ignored item is dimmed, labelled, offers Undo and no Apply', /Cost and price/.test(rec) && /\(ignored\)/.test(rec) && /ov_reco_unign" data-i="combo:view_cost\|price_override"/.test(rec) && !/ov_reco_apply" data-i="combo:view_cost/.test(rec));
    chk('English screen has no Bangla letter anywhere', !BN.test(body + lst + rec + t.els['#ov_bulk'].innerHTML + t.shells.map((s) => s[0] + s[1]).join('')));
    // set one
    t.calls.length = 0; await click(t, 'ov_set', { k: 'r:lists', m: 'hide' });
    const c0 = t.calls[0];
    chk('chip tap calls set_option_view with user, key, mode and a client id, then reloads the person', c0[0] === 'set_option_view' && c0[1].p_user === 'u-sales' && c0[1].p_key === 'r:lists' && c0[1].p_mode === 'hide' && !!c0[1].p_client && t.calls.some((c) => c[0] === 'option_views_for_user'));
    // bulk
    const ids = (kind) => t.O.bulkItems(kind);
    const hng = ids('hide_ng'), lng = ids('locked_ng'), sa = ids('show_all'), rs = ids('reset');
    chk('hide-all-not-granted: only not-granted, never protected, not the ones already hidden', hng.length > 3 && hng.every((x) => x.mode === 'hide') && !hng.some((x) => x.key === 'r:pos' || x.key === 'r:items' || x.key === 'r:optviews' || x.key === 'r:home') && hng.some((x) => x.key === 'f:39-1'));
    chk('locked-for-not-granted: includes items (hidden now) and not-granted forms, not granted ones', lng.some((x) => x.key === 'r:items') && lng.every((x) => x.mode === 'locked') && !lng.some((x) => x.key === 'r:pos' || x.key === 'f:03-1'));
    chk('show-all: only entries that are not Show now (items, dues)', sa.length === 2 && sa.every((x) => x.mode === 'show') && sa.some((x) => x.key === 'r:items') && sa.some((x) => x.key === 'r:dues'));
    chk('reset: removes only existing choices with mode default', rs.length === 2 && rs.every((x) => x.mode === 'default'));
    t.calls.length = 0; await click(t, 'ov_bulk', { m: 'hide_ng' });
    chk('bulk tap sends ONE set_option_view_bulk with all items and a client id', t.calls[0][0] === 'set_option_view_bulk' && t.calls[0][1].p_items.length === hng.length && !!t.calls[0][1].p_client && t.calls[0][1].p_user === 'u-sales');
    // advice actions
    t.calls.length = 0; await click(t, 'ov_reco_apply', { i: 'miss:report_sales' });
    chk('apply -> reco_apply with the item and a client id', t.calls[0][0] === 'reco_apply' && t.calls[0][1].p_item === 'miss:report_sales' && !!t.calls[0][1].p_client);
    t.calls.length = 0; await click(t, 'ov_reco_ign', { i: 'miss:report_sales' }); await click(t, 'ov_reco_unign', { i: 'miss:report_sales' });
    chk('ignore / undo -> reco_ignore_set true / false', t.calls[0][0] === 'reco_ignore_set' && t.calls[0][1].p_ignore === true && t.calls.filter((c) => c[0] === 'reco_ignore_set')[1][1].p_ignore === false);
    t.impl.rpc = async (fn) => (fn === 'reco_apply' ? { data: null, error: { message: 'not_personal_grant' } } : fn === 'set_option_view' ? { data: null, error: { message: 'protected_option' } } : { data: sales, error: null });
    await click(t, 'ov_reco_apply', { i: 'combo:purchase_entry|supplier_pay' }); await click(t, 'ov_set', { k: 'r:optviews', m: 'hide' });
    chk('friendly messages: grant comes from the role / protected option', t.toasts.includes('This permission comes from the role - change it in the role') && t.toasts.includes('This option cannot be hidden or locked'));
    // role target
    t.impl.rpc = async (fn) => (fn === 'role_option_views' ? { data: [{ role: 'storekeeper', key: 'r:payables', mode: 'hide' }], error: null } : { data: { changed: 1 }, error: null });
    t.calls.length = 0; await t.O.pick('r:storekeeper');
    chk('role target reads role defaults, shows no per-person permission status, no advice call', t.calls.length === 1 && t.calls[0][0] === 'role_option_views' && !/Not granted/.test(t.els['#ov_list'].innerHTML) && /Permission: role default/.test(t.els['#ov_list'].innerHTML) && t.els['#ov_reco'].innerHTML === '');
    t.calls.length = 0; await click(t, 'ov_set', { k: 'r:stock', m: 'locked' });
    chk('role chip tap -> set_role_option_view', t.calls[0][0] === 'set_role_option_view' && t.calls[0][1].p_role === 'storekeeper' && t.calls[0][1].p_mode === 'locked');
    t.calls.length = 0; await click(t, 'ov_bulk', { m: 'hide_ng' });
    chk('role target: hide-not-granted does nothing (no single permission status)', t.calls.length === 0);
    t.calls.length = 0; await click(t, 'ov_bulk', { m: 'reset' });
    chk('role reset -> set_role_option_view_bulk with mode default', t.calls[0][0] === 'set_role_option_view_bulk' && t.calls[0][1].p_items[0].mode === 'default' && t.calls[0][1].p_role === 'storekeeper');
  }
  // ---- 5. other languages render ----
  {
    const t = mk('bn'); t.impl.from.profiles = { data: [] }; await t.pages.optviews();
    chk('Bangla mode: title and intro in Bangla', BN.test(t.shells[0][0]) && BN.test(t.shells[0][1]));
    const m = mk('mix'); await m.pages.optviews(); chk('mix mode: title mixes', /Show/.test(m.shells[0][0]) && BN.test(m.shells[0][0]));
  }
  // ---- 6. wiring ----
  {
    const idx = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8'), nav = fs.readFileSync(path.join(ROOT, 'nav.js'), 'utf8'), ia = fs.readFileSync(path.join(ROOT, 'ia.js'), 'utf8');
    chk('index.html has exactly one optviews.js tag, after packflags.js', (idx.match(/optviews\.js/g) || []).length === 1 && idx.indexOf('optviews.js') > idx.indexOf('packflags.js'));
    chk('nav.js hook is guarded (entries + load)', /B\.optviews && B\.optviews\.apply \? B\.optviews\.apply\(out\) : out/.test(nav) && /if \(B\.optviews && B\.optviews\.load\)/.test(nav));
    chk('ia.js visible() guarded by B.optviews', /B\.optviews && B\.optviews\.hidden/.test(ia));
    const others = fs.readdirSync(ROOT).filter((f) => f.endsWith('.js') && f !== 'optviews.js').map((f) => fs.readFileSync(path.join(ROOT, f), 'utf8')).join('\n');
    const acts = [...fs.readFileSync(path.join(ROOT, 'optviews.js'), 'utf8').matchAll(/\b(ov_[a-z_]+)\b/g)].map((m) => m[1]).filter((a) => /^ov_(set|bulk|reco_apply|reco_ign|reco_unign)$/.test(a));
    chk('data-act names are unique to this file (no clash with any other web file)', acts.length > 0 && acts.every((a) => !new RegExp('\\b' + a + '\\b').test(others)));
  }
  {
    const t = mk('en'); t.impl.rpc = async () => ({ data: [{ key: 'r:items', mode: 'hide' }], error: null }); await t.O.load();
    const c = { own: true, P: () => true, GF: {}, locOk: () => true, canPos: () => true, anyApprove: () => true, ctlOk: () => true };
    chk('ia.visible: hidden route is not visible even for a permitted person; others unaffected', t.B.ia.visible(t.B.ia.byRoute('items'), c) === false && t.B.ia.visible(t.B.ia.byRoute('pos'), c) === true);
    chk('ia.search skips a hidden route', !t.B.ia.search('item', c).some((r) => r.route === 'items'));
  }
  console.log('optviews_test: pass=' + pass + ' fail=' + failn);
  process.exit(failn ? 1 : 0);
})().catch((e) => { console.log('CRASH', e && e.stack || e); process.exit(2); });
