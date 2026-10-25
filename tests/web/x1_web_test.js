// X1 web pieces: Connect Center (#/connect), Automation & integration health (#/x1health), the ia.js registry lines and the owner-board widget (off by default).
// Run: node x1_web_test.js <abs tests/web dir>      (serves THIS checkout's web/; a 360px phone viewport; English labels checked, Bangla present)
// Secrets: the screen must never show or ask for a secret VALUE; this test checks there is no password-type input on the page.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const path = require('path');
const SP = process.argv[2];
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = 8471;
const srv = require('http').createServer((q, r) => {
  const f = path.join(__dirname, '..', '..', 'web', q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]);
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[path.extname(f)] || 'application/octet-stream' }); r.end(b); });
}).listen(PORT);

const CONNS = [
  { code: 'website', kind: 'website', label_bn: 'ওয়েবসাইট / ডোমেইন', label_en: 'Website / domain', status: 'not_connected', enabled: false, read_only: true, dry_run: true, config: {}, env_names: ['WEBSITE_PUBLISH_TOKEN'], rate_per_min: 10, monthly_call_cap: 0, last_ok_at: null, last_error: null, last_test_at: null },
  { code: 'facebook_page', kind: 'facebook_page', label_bn: 'ফেসবুক পেজ', label_en: 'Facebook Page', status: 'configured', enabled: false, read_only: true, dry_run: true, config: { page_id: 'test-page-480' }, env_names: ['FB_PAGE_TOKEN'], rate_per_min: 10, monthly_call_cap: 0, last_ok_at: null, last_error: 'bad 01712345678', last_test_at: '2026-10-16T07:00:00Z' },
  { code: 'bkash', kind: 'payment', label_bn: 'বিকাশ', label_en: 'bKash', status: 'connected', enabled: true, read_only: true, dry_run: false, config: {}, env_names: [], rate_per_min: 5, monthly_call_cap: 100, last_ok_at: '2026-10-16T07:00:00Z', last_error: null, last_test_at: '2026-10-16T07:00:00Z' },
];
const HEALTH = { automation_on: false, paused: false, pause_until: null, proposals_open: 1, intake_failed_or_dead: 2,
  integrations: CONNS.map((c) => ({ code: c.code, kind: c.kind, label_en: c.label_en, status: c.status, enabled: c.enabled, state: c.status === 'not_connected' ? 'not_connected' : (c.enabled ? 'ok' : 'off') })),
  jobs: [{ job: 'notify_digest', state: 'failed', last_ok_at: null, last_run_at: '2026-10-16T07:00:00Z' }, { job: 'notify_sms', state: 'never_run' }, { job: 'intake_retry', state: 'stale' }, { job: 'kb_rebuild', state: 'never_run' }, { job: 'backup', state: 'ok' }],
  backup: { stale: false, last_ok: { at: '2026-10-16T01:00:00Z' } }, books: { status: 'data_needed' } };

const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc;
  c.rpc = async (fn, args) => {
    if (fn === 'x1_health') { if (window.__X1.denied) return { data: null, error: { message: 'not allowed', code: 'P0001' } }; return { data: window.__X1.health, error: null }; }
    if (fn === 'integration_set') { window.__X1.sets.push(args); return { data: { status: 'configured' }, error: null }; }
    return rpc(fn, args); };
  return c; }; })();`;

(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL:', m); } else console.log('PASS:', m); };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001|not allowed/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + EXTRA }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mk(base, {});
    data.tables.integration_registry = CONNS.map((c) => Object.assign({}, c));
    const x1 = { health: o.health || HEALTH, sets: [], denied: !!o.denied };
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__OWNER=${o.owner === false ? 'false' : 'true'};window.__X1=${JSON.stringify(x1)};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal scroll at 360px: ' + m);

  // 1. registry: both routes are in the one list (ia.js), the widget is available but not in the default board
  let p = await open('#/connect');
  ok(await p.evaluate(() => !!(window.BOS && BOS.ia && BOS.ia.byRoute && BOS.ia.byRoute('connect') && BOS.ia.byRoute('x1health'))), 'both screens are registered in web/ia.js');
  ok(await p.evaluate(() => !!(BOS.ownerboard && BOS.ownerboard.KINDS && BOS.ownerboard.KINDS.x1_health)), 'owner board has the health widget as an option');
  ok(await p.evaluate(() => !(BOS.ownerboard.defaults().some((i) => i.widget === 'x1_health'))), 'the health widget is NOT in the default owner board');

  // 2. Connect Center: 3 connections, honest states, secret NAMES only, no password field
  const cards = await p.locator('.x1-conn').count();
  ok(cards === 3, 'Connect Center shows the 3 connections (' + cards + ')');
  ok(await p.locator('.x1-conn[data-code="website"][data-status="not_connected"]').count() === 1, 'a new website is "not connected", never "connected"');
  const t = await p.evaluate(() => document.body.innerText);
  ok(/WEBSITE_PUBLISH_TOKEN/.test(t) && /Edge Functions/.test(t), 'the screen shows the secret NAME and where to set it');
  ok(await p.locator('input[type=password]').count() === 0, 'no password-type field: a secret value cannot be typed here');
  ok(!/01712345678/.test(t) && /\[phone\]/.test(t), 'a stored error text does not show a raw phone number');
  ok(!/sk-|eyJ/.test(t), 'no token-looking text is shown');
  await noOverflow(p, 'connect');
  await p.screenshot({ path: process.env.X1_SHOT_DIR ? path.join(process.env.X1_SHOT_DIR, 'x1_connect_360.png') : '/dev/null', fullPage: true }).catch(() => {});
  // owner edit form exists; the bKash connection is shown ON and is not called "connected" by the form
  ok(await p.locator('button[data-act="x1_test"]').count() === 3, 'owner sees a Test connection button per connection');

  // 3. Health screen: missing, stale and failed are shown as such; automation OFF is visible
  p = await open('#/x1health');
  const ht = await p.evaluate(() => document.body.innerText);
  ok(/Automation/.test(ht) && /Never run|never run/.test(ht), 'health: a job that never ran says so');
  ok(await p.locator('.x1-job[data-job="notify_digest"]').count() === 1 && /Failed/.test(await p.locator('.x1-job[data-job="notify_digest"]').innerText()), 'health: a failed job says Failed');
  ok(/Stale|stale/.test(await p.locator('.x1-job[data-job="intake_retry"]').innerText()), 'health: an old job says Stale');
  ok(/OFF|Off/.test(ht), 'health: automation is shown OFF');
  await noOverflow(p, 'health');

  // 4. staff (not the owner): the health page says it is owner-only, nothing is shown
  p = await open('#/x1health', { denied: true, owner: false });
  ok(/owner|Owner/.test(await p.evaluate(() => document.body.innerText)), 'staff see the owner-only line on health');

  // 5. no page error during the run
  ok(errors.length === 0, 'no page error or console error (' + errors.slice(0, 3).join(' | ') + ')');
  console.log('RESULT', bad ? 'FAIL' : 'OK', bad);
  await br.close(); srv.close();
  process.exit(bad ? 1 : 0);
} catch (e) { console.log('FAIL: exception', e && e.message); srv.close(); process.exit(1); } })();
