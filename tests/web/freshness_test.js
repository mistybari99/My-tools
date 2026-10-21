// Books freshness web piece (#/freshness) + the switch-coupling warning API (BOS.freshness.confirmSwitch / mount). W1-G, item U-11.
// Run: node freshness_test.js <abs tests/web dir>      (web/freshness.js and the one ia.js registry line are injected here; the integrator adds the real ones, docs/integration/W1-G.md)
// English labels only (owner rule 5): the page must read the same in bn, mix and en.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8467, srv = require('http').createServer((q, r) => { const f = require('path').join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const x = require('path').extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[x] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);   // serves THIS checkout's web/
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
 const R = window.__FR = window.__FR || { calls: [], fresh: null, ready: null, dry: null, warn: null, missing: false, deny: false, warnErr: false, ackErr: null, ruleErr: null };
 c.rpc = async (fn, args) => {
  if (!/^_w1g_|^set_rule$/.test(fn)) return rpc(fn, args);
  R.calls.push([fn, JSON.parse(JSON.stringify(args || {}))]);
  if (R.missing && /^_w1g_/.test(fn)) return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + fn } };
  if (R.deny && /^_w1g_(freshness|acct_readiness|post_scheduled)$/.test(fn)) return { data: null, error: { message: 'not allowed', code: 'P0001' } };
  if (fn === '_w1g_freshness') return { data: R.fresh, error: null };
  if (fn === '_w1g_acct_readiness') return { data: R.ready, error: null };
  if (fn === '_w1g_post_scheduled') return { data: R.dry, error: null };
  if (fn === '_w1g_switch_coupling_warning') { if (R.warnErr) return { data: null, error: { message: 'boom', code: 'P0001' } }; return { data: R.warn, error: null }; }
  if (fn === '_w1g_switch_coupling_ack') { if (R.ackErr) return { data: null, error: { message: R.ackErr, code: 'P0001' } }; return { data: { ack_id: 1 }, error: null }; }
  if (fn === 'set_rule') { if (R.ruleErr) return { data: null, error: { message: R.ruleErr, code: 'P0001' } }; if (args.p_key === 'journal_sched_post_on') { R.fresh = Object.assign({}, R.fresh, { sched_on: args.p_value === true }); } return { data: null, error: null }; }
  return { data: null, error: null };
 }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    // the registry line is in web/ia.js (phase 99 integration)
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/freshness\.js/.test(h) ? h : h.replace('</body>', '<script src="freshness.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__FR=${JSON.stringify(o.fr || undefined) || 'undefined'};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__FR.calls || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  const NOW = '2026-10-16T08:00:00Z';
  const FRESH = { status: 'fresh', now: NOW, accounting_on: true, start: '2026-10-01', sched_on: true, last_posted_at: '2026-10-16T07:50:00Z', last_posted_source: 'sale', age_minutes: 10,
    last_check_at: '2026-10-16T07:55:00Z', last_check_via: 'notify_bot', last_check_result: { posted: 0 }, pending: 0, oldest_pending: null, waiting: 0, errors: 0, stale_after_hours: null, stale: false,
    by_type: [{ source_type: 'sale', last_posted_at: '2026-10-16T07:50:00Z', last_posted_date: '2026-10-16', watermark_date: '2026-10-16', pending_after: 0, posted_total: 12, reversed_total: 1 },
              { source_type: 'quick_expense', last_posted_at: '2026-10-16T06:00:00Z', last_posted_date: '2026-10-16', watermark_date: '2026-10-15', pending_after: 2, posted_total: 3, reversed_total: 0 }] };
  const READY = { ready: true, blockers: [], checks: [{ key: 'start_date', ok: true, text: 'Accounting start date is set' }, { key: 'accounting_on', ok: true, text: 'Accounting is switched on' }, { key: 'opening', ok: true, text: 'An opening balance entry exists' },
    { key: 'mappings', ok: true, text: 'Every account mapping points to an active, postable account' }, { key: 'no_errors', ok: true, text: 'No document failed to post' }], pending: 0, errors: 0 };
  const NOTREADY = JSON.parse(JSON.stringify(READY)); NOTREADY.ready = false; NOTREADY.blockers = ['opening']; NOTREADY.checks[2].ok = false;
  const clone = (x) => JSON.parse(JSON.stringify(x));
  const WARN_HIGH = { key: 'forms_post_to_ledger', known: true, mode: 'warn', show: true, confirm: false, on_now: false, new_value: true, severity: 'high', locks: 4, unlocks: 0,
    actions: [{ domain: 'stock_issue', screen: 'Stock screen issue', form: 'Form 18-1 (issue slip)', places: [{ location_id: 0, from: 'a', to: 'b' }] }, { domain: 'production', screen: 'Recipe production run', form: 'Form 12-1 (factory daily sheet)', places: [{ location_id: 0, from: 'a', to: 'b' }] }],
    text: 'Turning this ON makes the paper form the only record for: Stock screen issue -> Form 18-1. The matching stock screens REFUSE new records ("path_locked").', fix: 'First set its owner switch on #/paths to "Screen" (path a).' };
  const base0 = { calls: [], fresh: FRESH, ready: READY, dry: { dry: true, ran: false, posted: 0, reversed: 0, by_type: {} }, warn: WARN_HIGH, missing: false, deny: false };

  // 1. owner, fresh
  let p = await open('#/freshness', { fr: clone(base0) });
  let t = await text(p);
  ok(/Books freshness/.test(await p.locator('h1').textContent()), 'title (English)');
  ok(await p.locator('#fr_strip[data-status=fresh]').count() === 1 && /Up to date/.test(t), 'strip: fresh');
  ok(/Last posted: 16 Oct, 13:50 \(10 min ago\)/.test(t), 'last posted at (Dhaka time) and age: ' + (t.match(/Last posted[^\n]*/) || [''])[0]);
  ok(/0 waiting/.test(t) && /Scheduled posting: ON/.test(t) && /Scheduler last checked: 16 Oct, 13:55/.test(t), 'counts, scheduler on, last check');
  ok(await p.locator('#fr_ready .fr-check').count() === 5 && /Ready to post automatically/.test(t), 'readiness checklist (5 checks, ready)');
  ok(await p.locator('#fr_types .fr-type').count() === 2 && /quick_expense/.test(t) && /Posted up to 15 Oct 2026/.test(t), 'per-kind watermark rows');
  ok(await p.locator('#fr_sched_btn').count() === 1 && /Turn scheduled posting OFF/.test(t), 'owner sees the OFF button while it is ON');
  ok((await calls(p, '_w1g_post_scheduled')).length === 0 && (await calls(p, 'set_rule')).length === 0, 'opening the page changes nothing (no post, no rule call)');
  await noOverflow(p, 'fresh'); await p.screenshot({ path: SP + '/fr_fresh.png', fullPage: true });

  // 2. dry run button
  const FD = clone(base0); FD.dry = { dry: true, ran: false, posted: 3, reversed: 1, by_type: { sale: { posted: 2, reversed: 1 }, quick_expense: { posted: 1 } } };
  p = await open('#/freshness', { fr: FD });
  await p.click('#fr_dry_btn'); await wait(p, 400);
  const dc = await calls(p, '_w1g_post_scheduled');
  ok(dc.length === 1 && dc[0].p_dry === true, 'the check button sends a DRY run only');
  ok(/it would post: 4 documents/.test(await text(p)) && await p.locator('#fr_dry').count() === 1, 'dry result shown (3 posted + 1 reversed = 4)');

  // 3. states: waiting, stale (red), off, data_needed
  const W = clone(base0); W.fresh = Object.assign(clone(FRESH), { status: 'waiting', pending: 7, sched_on: false, last_check_at: null });
  p = await open('#/freshness', { fr: W }); t = await text(p);
  ok(await p.locator('#fr_strip[data-status=waiting]').count() === 1 && /7 waiting/.test(t) && /Documents waiting/.test(t) && /Scheduled posting: OFF/.test(t), 'strip: waiting, scheduler OFF');
  ok(/Turn scheduled posting ON/.test(t), 'owner sees the ON button while it is OFF');
  const ST = clone(base0); ST.fresh = Object.assign(clone(FRESH), { status: 'stale', pending: 7, errors: 2, stale: true });
  p = await open('#/freshness', { fr: ST }); t = await text(p);
  ok(await p.locator('#fr_strip[data-status=stale] .chip.bad').count() === 1 && /2 failed/.test(t) && /Not posted for too long/.test(t), 'strip: stale is red and shows failures');
  await noOverflow(p, 'stale'); await p.screenshot({ path: SP + '/fr_stale.png', fullPage: true });
  const OFFS = clone(base0); OFFS.fresh = Object.assign(clone(FRESH), { status: 'off', accounting_on: false, last_posted_at: null, age_minutes: null });
  p = await open('#/freshness', { fr: OFFS }); t = await text(p);
  ok(await p.locator('#fr_strip[data-status=off]').count() === 1 && /Accounting is off/.test(t) && /Nothing posted yet/.test(t), 'strip: accounting off');
  const DN = clone(base0); DN.fresh = Object.assign(clone(FRESH), { status: 'data_needed', start: null });
  p = await open('#/freshness', { fr: DN }); t = await text(p);
  ok(await p.locator('#fr_strip[data-status=data_needed]').count() === 1 && /Start date not set/.test(t), 'strip: data needed');
  const NR = clone(base0); NR.ready = NOTREADY;
  p = await open('#/freshness', { fr: NR }); t = await text(p);
  ok(/Not ready yet/.test(t) && await p.locator('#fr_ready .fr-check[data-k=opening] .chip.bad').count() === 1, 'readiness: a failed check is marked Fix');

  // 4. English only: Bangla and mix modes read the same
  p = await open('#/freshness', { lang: 'bn', fr: clone(base0) }); t = await text(p);
  ok(/Books freshness/.test(await p.locator('h1').textContent()) && /Up to date/.test(t) && !/[ঀ-৿]/.test((await p.locator('#fr_body').innerText())), 'bn mode: still English, no Bangla text on the page');
  await noOverflow(p, 'bn');
  p = await open('#/freshness', { lang: 'mix', fr: clone(base0) });
  ok(/Up to date/.test(await text(p)), 'mix mode renders the same text');

  // 5. non-owner: no switch button, dry run still there
  p = await open('#/freshness', { owner: false, fr: clone(base0) });
  ok(await p.locator('#fr_sched_btn').count() === 0 && await p.locator('#fr_dry_btn').count() === 1, 'non-owner: no ON/OFF button');

  // 6. function missing / denied
  const MS = clone(base0); MS.missing = true;
  p = await open('#/freshness', { fr: MS }); ok(/phase98\.sql has not been run/.test(await text(p)), 'friendly message when phase98 is not installed');
  const DE = clone(base0); DE.deny = true;
  p = await open('#/freshness', { fr: DE }); ok(/do not have permission/.test(await text(p)), 'denied message');

  // 7. the scheduler switch goes through the warning, then set_rule
  const SW = clone(base0); SW.fresh = Object.assign(clone(FRESH), { sched_on: false, status: 'waiting', pending: 1 });
  SW.warn = { key: 'journal_sched_post_on', known: true, mode: 'warn', show: true, confirm: false, severity: 'info', text: 'Turning this ON lets the 30-minute notify job post every waiting sale by itself.' };
  p = await open('#/freshness', { fr: SW });
  await p.click('#fr_sched_btn'); await wait(p, 300);
  ok(await p.locator('#fr_warn').count() === 1 && /30-minute notify job/.test(await text(p)), 'warning is shown BEFORE the switch is saved');
  ok((await calls(p, 'set_rule')).length === 0, 'nothing saved while the warning is open');
  await p.click('[data-act=fr_back]'); await wait(p, 300);
  ok((await calls(p, 'set_rule')).length === 0 && await p.locator('#fr_warn').count() === 0, 'Cancel: nothing saved, sheet closed');
  await p.click('#fr_sched_btn'); await wait(p, 300); await p.click('#fr_go'); await wait(p, 600);
  const sr = await calls(p, 'set_rule');
  ok(sr.length === 1 && sr[0].p_key === 'journal_sched_post_on' && sr[0].p_value === true, 'continue: set_rule called once with true');
  ok(/Scheduled posting: ON/.test(await text(p)), 'page reloaded with the new state');
  ok((await calls(p, '_w1g_switch_coupling_ack')).length === 0, 'warn mode: no confirmation call');

  // 8. confirmSwitch API on any page: high severity, confirm mode, cancel, backdrop, no warning, errors
  const API = clone(base0);
  p = await open('#/freshness', { fr: API });
  let res = p.evaluate(() => window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true)); await wait(p, 300);
  ok(await p.locator('#fr_warn[data-sev=high]').count() === 1 && /Stop - this switch locks other screens/.test(await text(p)) && /path_locked/.test(await text(p)) && await p.locator('.fr-acts li').count() === 2, 'high severity: stop title, the text and the two locked actions');
  ok(/How to keep a screen working/.test(await text(p)) && /#\/paths/.test(await text(p)), 'the fix text points to #/paths');
  const wc = await calls(p, '_w1g_switch_coupling_warning');
  ok(wc.length === 1 && wc[0].p_key === 'forms_post_to_ledger' && wc[0].p_value === true, 'the warning is asked for key and new value');
  await noOverflow(p, 'sheet'); await p.screenshot({ path: SP + '/fr_warn.png', fullPage: true });
  await p.click('[data-act=fr_back]'); ok((await res) === false, 'Cancel resolves false');
  res = p.evaluate(() => window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true)); await wait(p, 300);
  await p.click('#fr_go'); ok((await res) === true, 'Turn it on anyway resolves true');
  ok((await calls(p, '_w1g_switch_coupling_ack')).length === 0, 'warn mode never calls the confirmation function');
  res = p.evaluate(() => window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true)); await wait(p, 300);
  await p.mouse.click(5, 5); await wait(p, 300);
  ok((await res) === false && await p.locator('#fr_warn').count() === 0, 'closing the sheet (outside tap) counts as Cancel');

  // confirm mode: checkbox needed, ack recorded, then true
  await p.evaluate(() => { window.__FR.warn = Object.assign({}, window.__FR.warn, { mode: 'confirm', confirm: true }); });
  res = p.evaluate(() => window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true)); await wait(p, 300);
  ok(await p.locator('#fr_go[disabled]').count() === 1, 'confirm mode: the button is disabled until the box is ticked');
  await p.check('#fr_ack'); await p.click('#fr_go'); const rv = await res;
  const ac = await calls(p, '_w1g_switch_coupling_ack');
  ok(rv === true && ac.length === 1 && ac[0].p_key === 'forms_post_to_ledger' && ac[0].p_value === true, 'confirm mode: the confirmation is recorded on the server, then true');
  await p.evaluate(() => { window.__FR.ackErr = 'not allowed'; });
  res = p.evaluate(() => window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true)); await wait(p, 300);
  await p.check('#fr_ack'); await p.click('#fr_go'); ok((await res) === false, 'confirm mode: if the server refuses the confirmation the answer is false');
  await p.evaluate(() => { window.__FR.ackErr = null; window.__FR.warn = Object.assign({}, window.__FR.warn, { show: false, confirm: false }); });
  res = await p.evaluate(() => window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true));
  ok(res === true && await p.locator('#fr_warn').count() === 0, 'show:false (mode off / no change) resolves true with no sheet');
  await p.evaluate(() => { window.__FR.warnErr = true; });
  res = await p.evaluate(() => window.BOS.freshness.confirmSwitch('forms_post_to_ledger', true));
  ok(res === true, 'if the warning cannot be read the switch is not blocked (the server decides)');

  // 9. mount(): the strip for Home / Accounts
  p = await open('#/freshness', { fr: clone(base0) });
  await p.evaluate(() => { const d = document.createElement('div'); d.id = 'mnt'; document.body.appendChild(d); return window.BOS.freshness.mount(d); }); await wait(p, 300);
  ok(await p.locator('#mnt .fr-strip').count() === 1, 'mount() draws the strip into any element');
  await p.evaluate(() => { window.__FR.missing = true; document.getElementById('mnt').innerHTML = 'x'; return window.BOS.freshness.mount(document.getElementById('mnt')); }); await wait(p, 300);
  ok((await p.locator('#mnt').innerHTML()) === '', 'mount() draws nothing when the server has no phase98');
  await p.evaluate(() => { window.__FR.missing = false; window.__FR.deny = true; document.getElementById('mnt').innerHTML = 'x'; return window.BOS.freshness.mount(document.getElementById('mnt')); }); await wait(p, 300);
  ok((await p.locator('#mnt').innerHTML()) === '', 'mount() draws nothing for a person without the accounts view');

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
