// (i) information hints: web/infohint.js + web/data/info.json. Headless Chromium, 360px.
// Run: node infohint_test.js <abs tests/web dir>      (serves THIS checkout's web/; no database, no network)
// Page 1: a small harness page (real styles.css + theme.css) for the button, the sheet, keyboard, dark/light, big text, missing data.
// Page 2: the real index.html with the script injected (the integrator adds the real <script> tag), only a smoke check.
// Node-side: info.json shape (every key has all sections or verified:false), rule/grant/screen/switch keys exist in the repository, no demo name, coverage tool.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), cp = require('child_process');
const SP = process.argv[2] || __dirname;
const ROOT = path.join(__dirname, '..', '..'), WEB = path.join(ROOT, 'web');
const PORT = 8493;
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' };
const HARNESS = `<!doctype html><html lang="en" data-theme="dark" data-skin="1"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="styles.css"><link rel="stylesheet" href="theme.css"></head><body>
<div id="app"><div class="pad" id="host">
 <h1 id="t1" data-info="screen:periodlock">Period lock</h1>
 <div id="row" style="display:flex;gap:8px;align-items:center"><span id="lab">Owner approval mode</span><span id="rowinfo"></span></div>
 <div id="clickrow" data-hits="0" style="padding:8px;border:1px solid"><span data-info="rule:owner_approval_mode">Row text</span></div>
 <p id="missing" data-info="rule:does_not_exist_zz">No hint here</p>
 <p><button id="after">After</button></p>
</div></div><script src="infohint.js"></script></body></html>`;
const sources = new Set();
const srv = require('http').createServer((q, r) => {
  const u = q.url.split('?')[0];
  if (u === '/harness.html') { r.writeHead(200, { 'content-type': 'text/html' }); return r.end(HARNESS); }
  const f = path.join(WEB, u === '/' ? 'index.html' : u);
  if (!f.startsWith(WEB)) { r.writeHead(403); return r.end(); }
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } sources.add(u); r.writeHead(200, { 'content-type': MIME[path.extname(f)] || 'application/octet-stream' }); r.end(b); });
}).listen(PORT);

const INFO_PATH = path.join(WEB, 'data', 'info.json');
const raw = fs.readFileSync(INFO_PATH, 'utf8');
const DOC = JSON.parse(raw), E = DOC.entries || {};
const keys = Object.keys(E);
const sentences = (s) => (String(s).match(/[^.!?]+[.!?]+(?=\s|$)|[^.!?]+$/g) || []).map((x) => x.trim()).filter(Boolean).length;
const lum = (rgb) => { const c = rgb.map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
const parseRgb = (s) => (String(s).match(/[\d.]+/g) || []).slice(0, 3).map(Number);

(async () => { try {
  let bad = 0; const log = (...a) => console.log(...a); const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  const errors = [];

  // ---------- node side: the data file ----------
  ok(DOC.version === 1 && keys.length > 0, 'info.json has version 1 and entries');
  const KEYRE = /^(rule|screen|grant|switch|feature):[a-z0-9_:]+$/;
  const REQ = ['title', 'does', 'why', 'default', 'change', 'who'];
  let nFull = 0, nLoose = 0;
  for (const k of keys) {
    const e = E[k]; const where = k + ': ';
    ok(KEYRE.test(k), where + 'key shape');
    ok(typeof e.title === 'string' && e.title.length > 0 && e.title.length <= 120, where + 'title');
    ok(typeof e.src === 'string' && e.src.length > 0, where + 'src (where the facts come from)');
    ok(typeof e.verified === 'boolean', where + 'verified is true or false');
    if (e.verified !== false) { nFull++; REQ.forEach((f) => ok(typeof e[f] === 'string' && e[f].trim().length > 0, where + 'section ' + f)); }
    else { nLoose++; ['title', 'does'].forEach((f) => ok(typeof e[f] === 'string' && e[f].trim().length > 0, where + '(verified:false) section ' + f)); }
    if (typeof e.does === 'string') ok(sentences(e.does) >= 1 && sentences(e.does) <= 3, where + 'does is 1 to 3 sentences (' + sentences(e.does) + ')');
    if (typeof e.why === 'string') ok(sentences(e.why) === 1, where + 'why is 1 sentence (' + sentences(e.why) + ')');
    if (typeof e.change === 'string') ok(sentences(e.change) >= 1 && sentences(e.change) <= 2, where + 'change is 1 to 2 sentences (' + sentences(e.change) + ')');
    ['does', 'why', 'default', 'change', 'who', 'warn'].forEach((f) => { if (typeof e[f] === 'string') ok(!/\s{2,}|\n/.test(e[f]) && e[f].length <= 420, where + f + ' is short and on one line'); });
    if (e.related !== undefined) ok(Array.isArray(e.related) && e.related.every((r) => typeof r === 'string'), where + 'related is a list of keys');
  }
  log('entries:', keys.length, 'verified:', nFull, 'not verified:', nLoose);
  ok(nFull + nLoose === keys.length && keys.length >= 100, 'at least 100 entries');
  // related keys must point to something
  const sqlAll = fs.readdirSync(path.join(ROOT, 'supabase')).filter((f) => f.endsWith('.sql') && !f.endsWith('_test.sql')).map((f) => [f, fs.readFileSync(path.join(ROOT, 'supabase', f), 'utf8')]);
  const iaText = fs.readFileSync(path.join(WEB, 'ia.js'), 'utf8');
  const routes = new Set(Array.from(iaText.matchAll(/rec\('([a-z0-9_]+)'/g), (m) => m[1]));
  const tup = (name, text) => new RegExp("\\(\\s*'" + name + "'\\s*,").test(text);
  const ruleSql = sqlAll.filter(([, t]) => /insert\s+into\s+(public\.)?rules\b/i.test(t)).map(([, t]) => t);
  const grantSql = sqlAll.filter(([, t]) => /insert\s+into\s+(public\.)?grant_defs\b/i.test(t)).map(([, t]) => t);
  const pathSql = (sqlAll.find(([f]) => f === 'phase48.sql') || [, ''])[1];
  for (const k of keys) {
    const [kind, ...rest] = k.split(':'); const name = rest.join(':');
    if (kind === 'rule') ok(ruleSql.some((t) => tup(name, t)), k + ' is a rule in the seed SQL (supabase/*.sql)');
    if (kind === 'grant') ok(grantSql.some((t) => tup(name, t)), k + ' is a grant in the seed SQL');
    if (kind === 'screen') ok(routes.has(name), k + ' is a route in web/ia.js');
    if (kind === 'switch') ok(/^path:/.test(name) && tup(name.slice(5), pathSql), k + ' is a path domain in phase48.sql');
    (E[k].related || []).forEach((r) => { if (/^screen:/.test(r)) ok(routes.has(r.slice(7)), k + ' related ' + r + ' is a route'); else ok(!!E[r], k + ' related ' + r + ' has an entry'); });
  }
  // the owner asked for these systems: each must have at least one entry
  const MUST = ['feature:opening_balance', 'rule:owner_approval_mode', 'screen:moneyaccounts', 'feature:payment_source', 'feature:money_transfer', 'screen:exceptions', 'feature:exception_reason', 'screen:balancecheck', 'rule:allow_test_reset',
    'rule:period_lock_mode', 'rule:owner_closed_period_mode', 'rule:backdate_max_days_purchase', 'rule:late_sale_policy', 'rule:exit_revoke_mode', 'rule:return_window_hours', 'rule:return_expired_restock', 'rule:profit_one_number_on', 'rule:profit_losses_from',
    'feature:report_parity', 'rule:owner_money_entry_mode', 'rule:supplier_pay_dup_mode', 'rule:journal_loc_check', 'rule:journal_attach_over', 'rule:other_income_on', 'rule:receipt_bank_on', 'rule:journal_sched_post_on', 'rule:backup_encrypt_on',
    'rule:backup_retention_days', 'rule:forms_post_to_ledger', 'rule:accounting_on', 'screen:paths', 'rule:d_wallet_split_on', 'rule:cash_short_post_on', 'rule:transit_short_bearer', 'feature:customer_advance', 'rule:payroll_accrual_on', 'rule:partner_settlement_post_on'];
  MUST.forEach((k) => ok(!!E[k], 'owner list: ' + k));
  ok(/test project/i.test((E['rule:allow_test_reset'] || {}).warn || ''), 'test reset carries the test-projects-only warning');
  const out = cp.spawnSync('python3', [path.join(ROOT, 'tools', 'check_no_demo_leak.py')], { cwd: ROOT, encoding: 'utf8' });
  ok(out.status === 0 && /OK/.test(out.stdout), 'check_no_demo_leak.py prints OK');
  const NAMES = ['Karim', 'Salma', 'Rahim', 'Ayesha', 'Shirin', 'Lipi', 'Nasrin', 'Tania', 'Jamal', 'Selim', 'Mitu', 'Hasan', 'Fatema', 'Ruma', 'Anwar', 'Sohel', 'Nazia'];
  const mine = raw + fs.readFileSync(path.join(WEB, 'infohint.js'), 'utf8');
  ok(!new RegExp('\\b(' + NAMES.join('|') + ')\\b').test(mine) && !/docs\/demo|DEMO_|IMAGINED_/.test(mine), 'no demo name or demo file in info.json or infohint.js');
  const cov = cp.spawnSync('python3', [path.join(ROOT, 'tools', 'check_info_coverage.py')], { cwd: ROOT, encoding: 'utf8' });
  ok(cov.status === 0, 'check_info_coverage.py exits 0 (every rule added in phase 80 or later has an entry)');

  // ---------- browser ----------
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const wait = (p, n = 150) => p.waitForTimeout(n);
  async function page(url, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    if (o.info) await p.route('**/data/info.json', o.info);
    await p.goto(`http://localhost:${PORT}/${url}`); await wait(p, o.settle || 500); return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'no horizontal overflow: ' + m);
  const sheetOpen = (p) => p.locator('#ihint-sheet [role=dialog]').count();

  // (i) the button renders and opens the sheet
  let p = await page('harness.html');
  ok(await p.evaluate(() => typeof BOS.info === 'function' && typeof BOS.infoMount === 'function'), 'BOS.info and BOS.infoMount exist');
  ok(await p.locator('#t1 > button.ihint').count() === 1, 'data-info on the screen title gets one (i) button');
  const btn = p.locator('#t1 > button.ihint'); const bb = await btn.boundingBox();
  ok(bb && bb.width >= 43.5 && bb.height >= 43.5, 'touch target is 44px or more (' + (bb && bb.width) + 'x' + (bb && bb.height) + ')');
  ok(await btn.getAttribute('aria-label') === 'What is this?', 'aria-label is "What is this?"');
  ok(await btn.evaluate((b) => b.tagName === 'BUTTON' && b.type === 'button'), 'it is a real button');
  const ib = await p.locator('#t1 .ihint-i').boundingBox(); ok(ib && ib.width >= 14 && Math.abs(ib.width - ib.height) < 1, 'the visible mark is a round circle');
  ok(await sheetOpen(p) === 0, 'no sheet before the tap');
  await btn.click(); await wait(p);
  ok(await sheetOpen(p) === 1, 'tap opens the sheet');
  let txt = await p.locator('#ihint-sheet').innerText();
  ['Period lock', 'What it does', 'Why it matters', 'Default', 'What changes if you switch it', 'Who can change it', 'Related'].forEach((s) => ok(txt.includes(s), 'sheet shows: ' + s));
  ok(txt.includes(E['screen:periodlock'].does.slice(0, 30)), 'sheet shows the text from info.json');
  ok(await p.locator('#ihint-sheet [role=dialog]').getAttribute('aria-modal') === 'true', 'dialog is modal');
  await noOverflow(p, 'sheet open at 360px');
  const box = await p.locator('.ihint-sheet').boundingBox(); ok(box && box.width <= 360 + 1, 'sheet fits the 360px width');
  const hx = await p.locator('.ihint-sheet').evaluate((s) => s.scrollWidth <= s.clientWidth + 1); ok(hx, 'sheet has no sideways scroll');
  // a related screen is a link to its route
  ok(await p.locator('.ihint-rel a[href="#/periodlock"], .ihint-rel a[href^="#/"]').count() >= 0, 'related list renders');
  await p.click('.ihint-done'); await wait(p);
  ok(await sheetOpen(p) === 0, 'Done closes the sheet');
  // tap on the dark area closes it
  await btn.click(); await wait(p); ok(await sheetOpen(p) === 1, 'reopened');
  await p.mouse.click(180, 20); await wait(p); ok(await sheetOpen(p) === 0, 'tap outside closes the sheet');
  // close X
  await btn.click(); await wait(p); await p.click('.ihint-x'); await wait(p); ok(await sheetOpen(p) === 0, 'the X closes the sheet');
  // string API: a settings row written with BOS.info(key)
  await p.evaluate(() => { document.getElementById('rowinfo').innerHTML = BOS.info('rule:owner_approval_mode'); });
  ok(await p.locator('#rowinfo > button.ihint').count() === 1, 'BOS.info(key) returns the button html for a known key');
  await p.locator('#rowinfo button.ihint').click(); await wait(p);
  txt = await p.locator('#ihint-sheet').innerText();
  ok(/Approval of the owner/.test(txt) && /self/.test(txt), 'row hint opens the right entry');
  // related button inside the sheet swaps the content and Back returns
  const rel = p.locator('.ihint-link').first();
  if (await rel.count()) { const t0 = await p.locator('.ihint-head h2').innerText(); await rel.click(); await wait(p); const t1 = await p.locator('.ihint-head h2').innerText(); ok(t1 !== t0, 'a related item opens its own entry'); await p.click('.ihint-back'); await wait(p); ok(await p.locator('.ihint-head h2').innerText() === t0, 'Back returns to the first entry'); }
  await p.keyboard.press('Escape'); await wait(p); ok(await sheetOpen(p) === 0, 'sheet closed');
  // a tap on the (i) inside a clickable row does not click the row
  await p.evaluate(() => { const r = document.getElementById('clickrow'); r.addEventListener('click', () => { r.dataset.hits = String(+r.dataset.hits + 1); }); });
  await p.locator('#clickrow button.ihint').click(); await wait(p);
  ok(await p.getAttribute('#clickrow', 'data-hits') === '0', 'the (i) tap does not reach the row around it');
  ok(await sheetOpen(p) === 1, 'and it opens the sheet'); await p.keyboard.press('Escape');

  // (ii) a missing key renders nothing and never throws
  ok(await p.locator('#missing > *').count() === 0 && (await p.locator('#missing').innerText()) === 'No hint here', 'data-info with a missing key renders nothing');
  const odd = await p.evaluate(() => { const r = []; for (const v of [undefined, null, '', '   ', 'nope', 'rule:zzz', '__proto__', 'constructor', 'toString', 5, {}, []]) { try { r.push(BOS.info(v)); } catch (e) { r.push('THROW'); } } try { BOS.info.open('nope'); BOS.info.open(undefined); BOS.infoMount(null); BOS.infoMount(document.createElement('div')); } catch (e) { r.push('THROW2'); } return r; });
  ok(odd.every((x) => x === ''), 'BOS.info returns "" for every bad or missing key: ' + JSON.stringify(odd));
  ok(await sheetOpen(p) === 0, 'BOS.info.open with a missing key opens nothing');
  ok(await p.evaluate(() => BOS.info.has('rule:owner_approval_mode') === true && BOS.info.has('rule:zzz') === false), 'BOS.info.has');
  // an entry with no title, wrong shape, or html in the text is safe
  const weird = { version: 1, entries: { 'rule:notitle': { does: 'x' }, 'rule:html': { title: '<img src=x onerror=window.__pwn=1>', does: '<b>bold</b> & more', why: 'w', default: 'd', change: 'c', who: 'o', related: ['rule:nothere', 7, null, 'screen:periodlock'], verified: true, src: 't' }, 'rule:partial': { title: 'Partial', does: 'only this', verified: false, src: 't' } } };
  p = await page('harness.html', { info: (r) => r.fulfill({ contentType: 'application/json', body: JSON.stringify(weird) }) });
  ok(await p.evaluate(() => BOS.info('rule:notitle') === ''), 'entry without a title renders nothing');
  await p.evaluate(() => { document.getElementById('rowinfo').innerHTML = BOS.info('rule:html'); }); await p.locator('#rowinfo button.ihint').click(); await wait(p);
  ok(await p.evaluate(() => window.__pwn === undefined) && await p.locator('#ihint-sheet img').count() === 0 && await p.locator('#ihint-sheet b').count() === 0, 'text is escaped (no html from the data file runs)');
  ok(/<b>bold<\/b> & more/.test(await p.locator('#ihint-sheet').innerText()), 'the text is shown as plain text');
  await p.keyboard.press('Escape');
  await p.evaluate(() => { document.getElementById('rowinfo').innerHTML = BOS.info('rule:partial'); }); await p.locator('#rowinfo button.ihint').click(); await wait(p);
  txt = await p.locator('#ihint-sheet').innerText();
  ok(/Partial/.test(txt) && /not fully confirmed/.test(txt) && !/Why it matters/.test(txt), 'a verified:false entry with missing sections shows what it has and says it is not confirmed');
  await p.keyboard.press('Escape');
  // data file missing (404) and broken (not json): nothing renders, nothing throws, it recovers when the phone is online again
  for (const [label, handler] of [['404', (r) => r.fulfill({ status: 404, body: 'no' })], ['not json', (r) => r.fulfill({ contentType: 'application/json', body: '{oops' })], ['network error', (r) => r.abort()]]) {
    p = await page('harness.html', { info: handler });
    ok(await p.locator('button.ihint').count() === 0 && await p.locator('#sheet, #ihint-sheet').count() === 0, 'data file ' + label + ': no (i) button, no sheet');
    ok(await p.evaluate(() => { try { return BOS.info('screen:periodlock') === '' || /data-info/.test(BOS.info('screen:periodlock')); } catch (e) { return false; } }), 'data file ' + label + ': BOS.info does not throw');
    ok((await p.locator('#t1').innerText()) === 'Period lock', 'data file ' + label + ': the title is untouched');
  }
  await p.unroute('**/data/info.json'); await p.evaluate(() => window.dispatchEvent(new Event('online'))); await wait(p, 600);
  ok(await p.locator('#t1 > button.ihint').count() === 1, 'when the phone is back online the (i) appears (no reload)');

  // (iii) keyboard
  p = await page('harness.html');
  await p.focus('#after'); await p.keyboard.press('Shift+Tab'); await wait(p, 50);
  const focusedIsHint = await p.evaluate(() => { let a = document.activeElement; return !!(a && a.classList.contains('ihint')); });
  ok(focusedIsHint, 'Shift+Tab from the next control reaches an (i) button (they are in the tab order)');
  await p.focus('#t1 > button.ihint');
  ok(await p.evaluate(() => { const o = getComputedStyle(document.activeElement).outlineStyle; return o !== 'none'; }), 'keyboard focus shows an outline');
  await p.keyboard.press('Enter'); await wait(p);
  ok(await sheetOpen(p) === 1, 'Enter opens the sheet');
  ok(await p.evaluate(() => document.getElementById('ihint-sheet').contains(document.activeElement)), 'focus moves into the sheet');
  const labelled = await p.locator('#ihint-sheet [role=dialog]').getAttribute('aria-labelledby'); ok(labelled === 'ihint-title' && (await p.locator('#ihint-title').innerText()) === 'Period lock', 'dialog is labelled by its title');
  for (let i = 0; i < 12; i++) { await p.keyboard.press('Tab'); const inside = await p.evaluate(() => document.getElementById('ihint-sheet').contains(document.activeElement)); if (!inside) { ok(false, 'Tab left the sheet at press ' + (i + 1)); break; } }
  for (let i = 0; i < 12; i++) { await p.keyboard.press('Shift+Tab'); const inside = await p.evaluate(() => document.getElementById('ihint-sheet').contains(document.activeElement)); if (!inside) { ok(false, 'Shift+Tab left the sheet at press ' + (i + 1)); break; } }
  await p.keyboard.press('Escape'); await wait(p);
  ok(await sheetOpen(p) === 0, 'Escape closes the sheet');
  ok(await p.evaluate(() => document.activeElement && document.activeElement.classList.contains('ihint') && document.activeElement.parentElement.id === 't1'), 'focus returns to the (i) button that opened it');
  await p.keyboard.press('Space'); await wait(p); ok(await sheetOpen(p) === 1, 'Space opens the sheet too');
  await p.keyboard.press('Escape'); await wait(p);
  // a sheet of the app underneath is not closed by Escape in the hint sheet (the hint takes the key)
  await p.evaluate(() => { window.__esc = 0; document.addEventListener('keydown', (e) => { if (e.key === 'Escape') window.__esc++; }); });
  await p.focus('#t1 > button.ihint'); await p.keyboard.press('Enter'); await wait(p); await p.keyboard.press('Escape'); await wait(p);
  ok(await p.evaluate(() => window.__esc) === 0, 'Escape in the hint sheet does not reach other handlers');

  // (iv) dark, light, big text, 360px
  for (const th of ['dark', 'light']) {
    await p.evaluate((t) => { document.documentElement.setAttribute('data-theme', t); }, th);
    await p.focus('#t1 > button.ihint'); await p.keyboard.press('Enter'); await wait(p);
    const c = await p.evaluate(() => { const cs = (el) => getComputedStyle(el); const sh = document.querySelector('.ihint-sheet'); const root = cs(document.documentElement);
      return { ink: cs(sh).color, s1: root.getPropertyValue('--s1').trim(), dt: cs(document.querySelector('.ihint-dl dt')).color, dd: cs(document.querySelector('.ihint-dl dd')).color, i: cs(document.querySelector('#t1 .ihint')).color }; });
    const bgRgb = await p.evaluate(() => { const d = document.createElement('div'); d.style.color = getComputedStyle(document.documentElement).getPropertyValue('--s1').trim(); document.body.appendChild(d); const v = getComputedStyle(d).color; d.remove(); return v; });
    ok(contrast(parseRgb(c.dd), parseRgb(bgRgb)) >= 4.5, th + ': body text contrast ' + contrast(parseRgb(c.dd), parseRgb(bgRgb)).toFixed(1) + ' >= 4.5');
    ok(contrast(parseRgb(c.dt), parseRgb(bgRgb)) >= 4.5, th + ': section label contrast ' + contrast(parseRgb(c.dt), parseRgb(bgRgb)).toFixed(1) + ' >= 4.5');
    await noOverflow(p, th + ' sheet at 360px');
    await p.screenshot({ path: path.join(process.env.INFO_SHOTS || require('os').tmpdir(), 'infohint_' + th + '.png') });
    await p.keyboard.press('Escape'); await wait(p, 50);
    ok(contrast(parseRgb(c.i), parseRgb(bgRgb)) >= 3, th + ': the (i) mark contrast >= 3');
  }
  await p.evaluate(() => { document.documentElement.style.fontSize = '26px'; });
  await p.focus('#t1 > button.ihint'); await p.keyboard.press('Enter'); await wait(p);
  ok(await p.locator('.ihint-sheet').evaluate((s) => s.scrollWidth <= s.clientWidth + 1), 'big text (26px root): no sideways scroll in the sheet');
  ok(await p.locator('.ihint-done').isVisible() || await p.locator('.ihint-sheet').evaluate((s) => s.scrollHeight > s.clientHeight), 'big text: the sheet scrolls, nothing is cut');
  ok(await p.locator('.ihint-sheet').evaluate((s) => s.getBoundingClientRect().top >= 0), 'big text: the sheet top is on screen');
  await p.keyboard.press('Escape');
  // elements added later are upgraded by themselves
  await p.evaluate(() => { const d = document.createElement('div'); d.id = 'late'; d.innerHTML = '<h2 data-info="rule:period_lock_mode">Late</h2>'; document.getElementById('host').appendChild(d); });
  await wait(p, 200); ok(await p.locator('#late button.ihint').count() === 1, 'an element added later with data-info gets its (i)');
  await p.evaluate(() => { BOS.infoMount(document.getElementById('late')); BOS.infoMount(document); });
  ok(await p.locator('#late button.ihint').count() === 1, 'infoMount twice does not add a second button');
  const size = await p.evaluate(() => { const b = document.querySelector('#late .ihint').getBoundingClientRect(); return [b.width, b.height]; });
  ok(size[0] >= 43.5 && size[1] >= 43.5, 'the touch target stays 44px at big text');

  // every entry opens (all keys), a few at a time
  const opened = await p.evaluate((ks) => { let n = 0, bad = []; for (const k of ks) { BOS.info.open(k); const s = document.getElementById('ihint-sheet'); if (s && s.querySelector('h2')) n++; else bad.push(k); BOS.info.close(); } return { n, bad }; }, keys);
  ok(opened.n === keys.length, 'every key in info.json opens a sheet (' + opened.n + '/' + keys.length + ') ' + opened.bad.join(','));
  const wide = await p.evaluate(async (ks) => { document.documentElement.style.fontSize = ''; const bad = []; for (const k of ks) { BOS.info.open(k); const sh = document.querySelector('.ihint-sheet'); if (sh.scrollWidth > sh.clientWidth + 1 || document.documentElement.scrollWidth > innerWidth + 1) bad.push(k); BOS.info.close(); } return bad; }, keys);
  ok(wide.length === 0, 'no entry causes sideways scroll at 360px: ' + wide.join(','));

  // smoke: the real app with the script injected
  const C = require(SP + '/w5b_common.js'); const base = C.baseData(SP);
  const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const sp = await ctx.newPage();
  sp.on('pageerror', (e) => errors.push('app pageerror: ' + e.message)); sp.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('app console: ' + m.text()); });
  await sp.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 }));
  await sp.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await sp.route((u) => u.pathname === '/', async (r) => { const res = await r.fetch(); const body = ((h) => (/infohint\.js/.test(h) ? h : h.replace('</body>', '<script src="infohint.js"></script></body>')))(await res.text()); await r.fulfill({ response: res, body }); });
  await sp.addInitScript(`window.__DATA=${JSON.stringify(C.mk(base, {}))};window.__OWNER=true;try{localStorage.setItem('bos_lang','en')}catch(e){}`);
  await sp.goto(`http://localhost:${PORT}/#/home`); await sp.waitForTimeout(1500);
  ok(await sp.evaluate(() => typeof BOS.info === 'function' && BOS.info.has('screen:periodlock') && /ihint/.test(BOS.info('rule:owner_approval_mode'))), 'real app: BOS.info works next to the app code');
  ok(sources.has('/data/info.json'), 'the data file is fetched at start (so the service worker keeps a copy for offline use)');
  await noOverflow(sp, 'real app home with infohint.js');

  ok(errors.length === 0, 'no page errors or console errors: ' + errors.join(' | '));
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
  if (bad) process.exitCode = 1;
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
