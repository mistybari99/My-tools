// Phase 95 web: node tests/web/cashdrawer_test.js  (plain node, mocked rpc, fake drivers)
// Mode off = nothing; mode/when matrix; fail-soft; offline log queue + idempotent replay; no-sale reason; real drivers against fake browser APIs (bytes = ESC p 0 25 250);
// owner screen in 3 languages (English has no Bangla letters); XSS; unique cdr_ data-act names; ia / index / pos.js wiring and guards.
const _P = require('./_paths');
const fs = require('fs'), path = require('path'), vm = require('vm');
const W = _P.WEB_DIR; const BN = /[ঀ-৿]/;
let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; console.log('FAIL:', m); } };
const rd = (f) => fs.readFileSync(path.join(W, f), 'utf8');
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
async function mk(o) {
  o = o || {}; const lang = o.lang || 'en';
  const calls = [], toasts = [], fails = [], H = {}, mem = {}, els = { cdr_body: { innerHTML: '' }, cdr_slot: { innerHTML: '' }, cdr_why: { value: '' } }, wl = [];
  const rules = Object.assign({ cash_drawer_mode: 'off', cash_drawer_when: 'after_payment', cash_drawer_method: 'web_serial', cash_drawer_no_sale_requires_reason: true }, o.rules || {});
  const win = { BOS: { L: (bn, en, mix) => ({ bn, en, mix }), lab: (x) => (lang === 'bn' ? x.bn : lang === 'en' ? x.en : (x.mix || x.bn)), rule: (k, f) => (k in rules ? rules[k] : f), reloadRules: async () => { calls.push(['reload']); } }, addEventListener: (t, f) => wl.push([t, f]) };
  const state = { net: o.net !== false, rpcErr: null };
  const nav = { get onLine() { return state.net; } };
  const settings = Object.assign({ mode: 'off', can_no_sale: false, can_report: false, is_owner: false }, o.settings || {});
  const sb = { rpc: async (fn, a) => {
    calls.push([fn, a]);
    if (o.throwAll) throw new Error('boom');
    if (!state.net) return { data: null, error: { message: 'Failed to fetch' } };
    if (state.rpcErr && fn === 'drawer_event_log') return { data: null, error: { message: state.rpcErr } };
    if (fn === 'drawer_settings') return o.noSql ? { data: null, error: { message: 'Could not find the function' } } : { data: settings, error: null };
    if (fn === 'drawer_report') return { data: o.report || { totals: { no_sale_open: 3, auto_open: 5, test_open: 1, failed: 2 }, by_user: [{ user_id: 'u1', staff: 'S1', name: '<img src=x onerror=alert(1)>', no_sale_open: 3, auto_open: 5, failed: 2 }], recent_no_sale: [{ at: '2026-01-02T10:00:00Z', staff: 'S1', reason: '<b>why</b>' }] }, error: null };
    if (fn === 'set_rule') return o.setErr ? { data: null, error: { message: o.setErr } } : { data: null, error: null };
    if (fn === 'drawer_event_log') return { data: { id: 1, dup: false }, error: null };
    return { data: null, error: null };
  } };
  const sheets = [];
  const A = { sb, esc, toast: (m) => toasts.push(m), fail: (e) => fails.push(e), shell: () => {}, H, S: { lang, ctx: { is_owner: !!o.owner, profile: { id: 'u1' }, locations: [1] } }, store: { get: (k) => (k in mem ? mem[k] : null), set: (k, v) => { mem[k] = v; } }, openSheet: (h) => sheets.push(h), closeSheet: () => sheets.push('closed') };
  win.BOS_APP = A;
  const doc = o.doc || { querySelector: (s) => els[s.replace('#', '')] || null };
  const ctx = vm.createContext({ window: win, document: doc, navigator: o.nav || nav, console, setInterval: () => 0, setTimeout, crypto: { randomUUID: (() => { let i = 0; return () => '00000000-0000-4000-8000-' + String(++i).padStart(12, '0'); })() }, Uint8Array, Date, Promise });
  vm.runInContext(rd('cashdrawer.js'), ctx, { filename: 'cashdrawer' });
  const opens = []; const fake = { supported: () => true, connected: async () => !o.disconnected, connect: async () => true, open: async () => { if (o.driverThrows) throw new Error('write failed'); opens.push(1); } };
  if (!o.noFake) win.BOS.drawer.register('web_serial', fake);
  return { win, B: win.BOS, D: win.BOS.drawer, H, els, calls, toasts, fails, mem, wl, state, rules, opens, sheets, A };
}
const cashSale = { p_client: 'c-1', p_loc: 1, p_payments: [{ mode: 'cash', amount: 100 }] };
const mobSale = { p_client: 'c-2', p_loc: 1, p_payments: [{ mode: 'mobile', amount: 100 }] };
const logs = (r) => r.calls.filter((c) => c[0] === 'drawer_event_log').map((c) => c[1]);
const tick = () => new Promise((res) => setTimeout(res, 15));
(async () => {
  // ---- mode off: nothing at all
  let r = await mk({ rules: { cash_drawer_mode: 'off' } });
  r.D.beforeSale(cashSale); r.D.afterSale(cashSale); await tick();
  ok(r.opens.length === 0 && r.calls.length === 0 && r.toasts.length === 0, 'mode off: no open, no rpc, no toast');
  ok(r.D.noSaleButton(1) === '', 'mode off: no No-sale button and no settings call'); await tick(); ok(r.calls.length === 0, 'mode off: still no rpc after button');
  ok(Object.keys(mkSafe()).length >= 0, 'sanity');
  function mkSafe() { return {}; }
  // ---- matrix
  const cases = [
    ['on_cash_sale', 'after_payment', 'before', cashSale, 0], ['on_cash_sale', 'after_payment', 'after', cashSale, 1], ['on_cash_sale', 'after_payment', 'after', mobSale, 0],
    ['on_cash_sale', 'before_payment', 'before', cashSale, 1], ['on_cash_sale', 'before_payment', 'after', cashSale, 0], ['on_any_sale', 'after_payment', 'after', mobSale, 1],
    ['on_any_sale', 'before_payment', 'before', mobSale, 1], ['manual_only', 'after_payment', 'after', cashSale, 0], ['manual_only', 'before_payment', 'before', cashSale, 0],
    ['on_cash_sale', 'after_payment', 'after', { p_client: 'c-3', p_loc: 1, p_payments: [{ mode: 'cash', amount: 0 }] }, 0], ['on_cash_sale', 'after_payment', 'after', { p_client: 'c-4', p_loc: 1 }, 0],
  ];
  for (const [mode, when, hook, sale, want] of cases) {
    r = await mk({ rules: { cash_drawer_mode: mode, cash_drawer_when: when } });
    r.D[hook === 'before' ? 'beforeSale' : 'afterSale'](sale); await tick();
    ok(r.opens.length === want, `${mode}/${when}/${hook}/${sale.p_payments && sale.p_payments[0].mode}/${sale.p_payments && sale.p_payments[0].amount} opens ${want} (got ${r.opens.length})`);
    ok(logs(r).length === want && (want === 0 || (logs(r)[0].p_event === 'auto_open' && logs(r)[0].p_sale_ref === sale.p_client && logs(r)[0].p_loc === 1 && logs(r)[0].p_method === 'web_serial')), `${mode}/${when}/${hook}: auto_open logged with the sale client id`);
  }
  // ---- fail soft
  for (const [label, opt] of [['driver throws', { driverThrows: true }], ['not connected', { disconnected: true }]]) {
    r = await mk(Object.assign({ rules: { cash_drawer_mode: 'on_cash_sale' } }, opt));
    let thrown = false; try { r.D.afterSale(cashSale); await tick(); } catch (e) { thrown = true; }
    ok(!thrown && r.toasts.length === 1 && /Drawer not connected/.test(r.toasts[0]) && logs(r).length === 1 && logs(r)[0].p_event === 'failed' && /auto_open/.test(logs(r)[0].p_reason), 'fail soft (' + label + '): toast + failed event, no throw');
  }
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale', cash_drawer_method: 'kiosk_url' } });
  r.D.afterSale(cashSale); await tick(); ok(r.toasts.length === 1 && logs(r)[0].p_event === 'failed' && /planned/.test(logs(r)[0].p_reason), 'planned kiosk_url fails soft and says planned in the log');
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale', cash_drawer_method: 'none' } });
  r.D.afterSale(cashSale); await tick(); ok(r.toasts.length === 1 && logs(r)[0].p_event === 'failed', 'method none with mode on fails soft');
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale', cash_drawer_method: 'web_usb' }, noFake: true });
  r.D.afterSale(cashSale); await tick(); ok(/cannot open/.test(r.toasts[0] || '') && /unsupported/.test(logs(r)[0].p_reason), 'browser without the API: unsupported message, failed event');
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale' }, throwAll: true });
  r.D.afterSale(cashSale); await tick(); ok(r.opens.length === 1 && r.fails.length === 0, 'server rpc throwing never breaks the open or the sale');
  // ---- offline queue
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale' }, net: false });
  r.D.afterSale(cashSale); r.D.afterSale(Object.assign({}, cashSale, { p_client: 'c-9' })); await tick();
  const qk = Object.keys(r.mem).find((k) => k.startsWith('bos_cdr_q_'));
  ok(r.opens.length === 2 && JSON.parse(r.mem[qk]).length === 2, 'offline: drawer still opens, 2 events queued on the device');
  ok(JSON.parse(r.mem[qk])[0].at, 'offline: event carries the device time');
  r.state.net = true; r.calls.length = 0; await r.D.flushLog(); await tick();
  ok(logs(r).length === 2 && JSON.parse(r.mem[qk]).length === 0, 'online again: both events sent in order and the queue is empty');
  ok(new Set(logs(r).map((x) => x.p_client)).size === 2 && /^[0-9a-f-]{36}$/.test(logs(r)[0].p_client), 'each event has its own client id (server dedupes a replay)');
  r.state.rpcErr = 'not allowed'; r.D.log('auto_open', { loc: 1 }); await tick(); ok(JSON.parse(r.mem[qk]).length === 0, 'a refused event (rules / SQL not run) is dropped, not retried forever');
  r.state.rpcErr = 'Failed to fetch'; r.D.log('auto_open', { loc: 1 }); await tick(); ok(JSON.parse(r.mem[qk]).length === 1, 'a network error keeps the event');
  // ---- No sale
  r = await mk({ rules: { cash_drawer_mode: 'manual_only' }, owner: true });
  const btn = r.D.noSaleButton(1); ok(/id="cdr_slot"/.test(btn) && /cdr_nosale/.test(btn), 'owner sees the No sale button when mode is on');
  await tick(); ok(r.els.cdr_slot.innerHTML.includes('cdr_nosale'), 'slot filled after settings arrive');
  r.H.cdr_nosale({ dataset: { v: '1' } }); ok(r.sheets.length === 1 && /cdr_why/.test(r.sheets[0]) && /cdr_nosale_go/.test(r.sheets[0]), 'No sale sheet opens');
  r.els.cdr_why.value = ''; await r.H.cdr_nosale_go({ dataset: { v: '1' } }); ok(r.opens.length === 0 && r.toasts.length === 1 && /reason/i.test(r.toasts[0]), 'no reason: nothing opens (rule on)');
  r.els.cdr_why.value = 'Making change'; await r.H.cdr_nosale_go({ dataset: { v: '1' } }); await tick();
  ok(r.opens.length === 1 && logs(r).some((x) => x.p_event === 'no_sale_open' && x.p_reason === 'Making change' && x.p_loc === 1), 'with a reason: opens and logs no_sale_open with the reason');
  r.rules.cash_drawer_no_sale_requires_reason = false; r.els.cdr_why.value = ''; await r.H.cdr_nosale_go({ dataset: { v: '1' } }); await tick(); ok(r.opens.length === 2, 'reason rule off: no reason needed');
  r = await mk({ rules: { cash_drawer_mode: 'manual_only' }, owner: false, settings: { can_no_sale: false } });
  r.D.noSaleButton(1); await tick(); ok(!r.els.cdr_slot.innerHTML.includes('cdr_nosale'), 'a user without the grant gets no No sale button');
  r = await mk({ rules: { cash_drawer_mode: 'manual_only' }, owner: false, settings: { can_no_sale: true } });
  r.D.noSaleButton(1); await tick(); ok(r.els.cdr_slot.innerHTML.includes('cdr_nosale'), 'a user with the grant gets the button');
  r = await mk({ rules: { cash_drawer_mode: 'manual_only' }, owner: false, noSql: true });
  ok(typeof r.D.noSaleButton(1) === 'string', 'SQL not run: button call does not throw'); await tick();

  // ---- real drivers against fake browser APIs: bytes must be ESC p 0 25 250
  const PULSE = [27, 112, 0, 25, 250];
  const got = [];
  const port = { open: async () => {}, close: async () => {}, writable: { getWriter: () => ({ write: async (u) => got.push(['serial', [...u]]), releaseLock: () => {} }) } };
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale' }, noFake: true, nav: { onLine: true, serial: { getPorts: async () => [], requestPort: async () => port } } });
  let res = await r.D.open('t', { event: 'test_open', quiet: true }); ok(!res.ok && res.err === 'not_connected', 'web_serial before pairing: not_connected');
  ok(await r.D.drivers.web_serial.connect(), 'web_serial connect'); res = await r.D.open('t', { event: 'test_open' });
  ok(res.ok && JSON.stringify(got[0]) === JSON.stringify(['serial', PULSE]), 'web_serial writes ESC p 0 25 250 (got ' + JSON.stringify(got[0]) + ')');
  const usbDev = { opened: false, configuration: null, open: async function () { this.opened = true; }, selectConfiguration: async function () { this.configuration = { interfaces: [{ interfaceNumber: 0, alternates: [{ interfaceClass: 7, endpoints: [{ direction: 'in', type: 'bulk', endpointNumber: 1 }, { direction: 'out', type: 'bulk', endpointNumber: 2 }] }] }] }; }, claimInterface: async () => {}, transferOut: async (ep, u) => got.push(['usb', ep, [...u]]) };
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale', cash_drawer_method: 'web_usb' }, noFake: true, nav: { onLine: true, usb: { getDevices: async () => [usbDev], requestDevice: async () => usbDev } } });
  res = await r.D.open('t', { event: 'test_open' }); ok(res.ok && JSON.stringify(got[1]) === JSON.stringify(['usb', 2, PULSE]), 'web_usb transfers the pulse to the OUT bulk endpoint (got ' + JSON.stringify(got[1]) + ')');
  const ch = { properties: { write: true, writeWithoutResponse: false }, writeValue: async (u) => got.push(['bt', [...u]]) };
  const btDev = { gatt: { connected: false, connect: async () => ({ getPrimaryServices: async () => [{ getCharacteristics: async () => [{ properties: { read: true } }, ch] }] }) } };
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale', cash_drawer_method: 'bluetooth' }, noFake: true, nav: { onLine: true, bluetooth: { requestDevice: async () => btDev } } });
  res = await r.D.open('t', { event: 'test_open', quiet: true }); ok(!res.ok, 'bluetooth before pairing fails soft');
  await r.D.drivers.bluetooth.connect(); res = await r.D.open('t', { event: 'test_open' }); ok(res.ok && JSON.stringify(got[2]) === JSON.stringify(['bt', PULSE]), 'bluetooth writes the pulse to the first writable characteristic');
  ok(r.D.drivers.bluetooth.status === 'experimental' && r.D.drivers.kiosk_url.status === 'planned' && r.D.drivers.web_serial.status === 'ready', 'driver status labels (bluetooth experimental, kiosk_url planned)');
  ok(JSON.stringify(r.D.PULSE) === JSON.stringify(PULSE), 'exported PULSE constant = ESC p 0 25 250');
  const printed = []; const frame = { setAttribute() {}, style: {}, remove() {}, contentWindow: { document: { open() {}, write() {}, close() {} }, focus() {}, print: () => printed.push(1) } };
  r = await mk({ rules: { cash_drawer_mode: 'on_cash_sale', cash_drawer_method: 'browser_print_pulse' }, noFake: true, doc: { body: { appendChild() {} }, createElement: () => frame, querySelector: () => null } , nav: { onLine: true } });
  res = await r.D.open('t', { event: 'test_open' }); ok(res.ok && printed.length === 1, 'print pulse prints one tiny job');

  // ---- owner screen
  for (const lang of ['bn', 'mix', 'en']) {
    r = await mk({ lang, owner: true, settings: { can_report: true, can_no_sale: true, is_owner: true }, rules: { cash_drawer_mode: 'on_cash_sale' } });
    await r.win.BOS_PAGES.cashdrawer(); const h = r.els.cdr_body.innerHTML;
    ok(/cdr_set" data-k="cash_drawer_mode" data-v="manual_only"/.test(h) && /data-k="cash_drawer_when"/.test(h) && /data-k="cash_drawer_method" data-v="web_serial"/.test(h), lang + ' owner sees all rule buttons');
    ok(!/data-k="cash_drawer_method" data-v="kiosk_url"/.test(h) && /planned|পরিকল্পিত/i.test(h), lang + ' planned method is shown but cannot be chosen');
    ok(/cdr_connect/.test(h) && /cdr_test/.test(h) && /cdr_range/.test(h), lang + ' connect, test and report controls');
    ok(!/<img src=x/.test(h) && h.includes('&lt;img src=x') && h.includes('&lt;b&gt;why'), lang + ' staff names and reasons escaped in the report');
    ok(/Suggested|Suggestion|Suggested|প্রস্তাব/.test(h), lang + ' recommendation text present');
    if (lang === 'en') ok(!BN.test(h), 'English page has no Bangla letters'); else ok(BN.test(h) && /Cash drawer|drawer|Connect/.test(h), lang + ' page has Bangla and keeps common words English');
    ok(r.calls.every((c) => ['drawer_settings', 'drawer_report'].includes(c[0])), lang + ' opening the page only reads');
  }
  r = await mk({ lang: 'en', owner: true, settings: { can_report: true } }); await r.win.BOS_PAGES.cashdrawer();
  await r.H.cdr_set({ dataset: { k: 'cash_drawer_mode', v: 'on_any_sale' } }); const sr = r.calls.find((c) => c[0] === 'set_rule');
  ok(sr && sr[1].p_key === 'cash_drawer_mode' && sr[1].p_value === 'on_any_sale' && r.toasts.includes('Saved'), 'owner set sends set_rule with the string');
  await r.H.cdr_set({ dataset: { k: 'cash_drawer_no_sale_requires_reason', v: 'false' } }); ok(r.calls.filter((c) => c[0] === 'set_rule')[1][1].p_value === false, 'switch sends a real boolean');
  await r.H.cdr_test({}); await tick(); ok(logs(r).some((x) => x.p_event === 'test_open') && r.toasts.includes('Test sent'), 'Test open logs test_open');
  await r.H.cdr_connect({}); ok(r.toasts.includes('Device connected'), 'Connect works with the fake driver');
  r = await mk({ lang: 'en', owner: true, setErr: 'bad_value' }); await r.win.BOS_PAGES.cashdrawer(); await r.H.cdr_set({ dataset: { k: 'cash_drawer_mode', v: 'x' } }); ok(r.toasts.includes('That value was refused') && r.fails.length === 0, 'bad_value shows a plain message');
  r = await mk({ lang: 'en', owner: true, setErr: 'not allowed' }); await r.win.BOS_PAGES.cashdrawer(); await r.H.cdr_set({ dataset: { k: 'cash_drawer_mode', v: 'off' } }); ok(r.fails.length === 1, 'server refusal surfaces');
  r = await mk({ lang: 'en', owner: false }); await r.win.BOS_PAGES.cashdrawer(); const hn = r.els.cdr_body.innerHTML;
  ok(!/data-act="cdr_set"/.test(hn) && /Only the owner/.test(hn) && /cdr_connect/.test(hn) && !/cdr_range/.test(hn), 'non-owner: read-only settings, can Connect/Test at the till, no report');
  await r.H.cdr_set({ dataset: { k: 'cash_drawer_mode', v: 'off' } }); ok(!r.calls.some((c) => c[0] === 'set_rule'), 'non-owner cannot send set_rule even by calling the handler');
  r = await mk({ lang: 'en', owner: true, noSql: true }); await r.win.BOS_PAGES.cashdrawer(); ok(/phase95/.test(r.els.cdr_body.innerHTML), 'SQL not run: run-the-SQL notice');

  // ---- wiring
  const src = rd('cashdrawer.js'); const acts = [...new Set([...src.matchAll(/data-act="(\w+)"/g)].map((m) => m[1]))].filter((a) => a !== 'closesheet');   // closesheet is the app's own shared action
  ok(acts.length >= 7 && acts.every((a) => a.startsWith('cdr_')), 'all data-act names use the cdr_ prefix (' + acts.join(',') + ')');
  const hs = [...src.matchAll(/^\s*(cdr_\w+):/gm)].map((m) => m[1]); ok(acts.every((a) => hs.includes(a)), 'every data-act has a handler');
  const others = fs.readdirSync(W).filter((f) => f.endsWith('.js') && f !== 'cashdrawer.js' && f !== 'a11yfix.js')   // a11yfix.js (advanced line) names cdr_set on purpose, to keep the screen's own action reachable;.map((f) => rd(f)).join('\n'); ok(!acts.some((a) => others.includes(a)), 'cdr_ names are used nowhere else');
  const ia = rd('ia.js'); ok(/rec\('cashdrawer', 'sale'/.test(ia) && ia.indexOf("rec('cashdrawer'") > ia.indexOf("rec('books85'"), 'ia.js has the cashdrawer line appended after the previous ones'); ok(!/^<<<<<<<|^>>>>>>>|^=======$/m.test(ia), 'ia.js has no merge markers');
  const ix = rd('index.html'); ok(ix.includes('<script src="cashdrawer.js"></script>') && ix.indexOf('cashdrawer.js') > ix.indexOf('pos.js') && ix.indexOf('cashdrawer.js') > ix.indexOf('books85.js'), 'index.html loads cashdrawer.js after pos.js, at the end');
  const pos = rd('pos.js'); const lines = pos.split('\n').filter((l) => /B\.drawer/.test(l));
  ok(lines.length === 4 && lines.every((l) => /bos95/.test(l) && /(B\.drawer \?|if \(B\.drawer\))/.test(l)), 'pos.js: exactly 4 edits, each tagged bos95 and guarded by B.drawer (got ' + lines.length + ')');
  ok(!/await\s+B\.drawer|B\.drawer\.\w+\([^)]*\)\.then/.test(pos), 'pos.js never awaits the drawer');
  ok(pos.indexOf('B.drawer.beforeSale(p)') < pos.indexOf('await send(p)') && pos.indexOf('B.drawer.afterSale(p);   // bos95') > pos.indexOf('B.invoiceview.afterSale({ p, data, change })'), 'beforeSale runs before send; afterSale after the success toast');
  ok(!/B\.drawer/.test(pos.slice(pos.indexOf('async function flush'), pos.indexOf("window.addEventListener('online', flush)"))), 'a queue replay (flush) never opens the drawer');
  const lg = rd('cashdrawer.js').match(/const X = \{[\s\S]*?\n\};/)[0]; ok(!/[ঀ-৿]{1,}.*\bEnglish-only\b/.test(lg), 'text table parsed');
  console.log(`cashdrawer_test: ${n - bad} pass / ${bad} fail`); process.exit(bad ? 1 : 0);
})();
