// Phase 90 / Scan in a real browser at phone width (360px) with mocked scan_* RPCs: pick a photo -> draft -> check beside the photo -> map -> Confirm.
// Run: node tests/web/scan_pw_test.js <abs tests/web dir>      (mock only: no Supabase, no OCR, no AI)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || __dirname;
const C = require(SP + '/w5_common.js');
const base = C.baseData(SP), PORT = 8493;
// serve THIS worktree's web/ (the shared helper serves a fixed folder of another checkout)
const ROOT = require('path').join(__dirname, '..', '..', 'web');
const srv = require('http').createServer((q, r) => { const f = require('path').join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); }
  r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[require('path').extname(f)] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);
const EXTRA_SC = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const M = window.__M;
 const clone = (x) => JSON.parse(JSON.stringify(x === undefined ? null : x)); const S = window.__SC = { jobs: {}, n: 0, dups: [] };
 c.rpc = async (fn, args) => { if (!/^scan_/.test(fn)) return rpc(fn, args); M.calls.push([fn, clone(args || {})]);
  if (fn === 'scan_list') return { data: Object.values(S.jobs).map((j) => ({ id: j.id, kind: j.kind, location_id: 1, status: j.status, engine: 'manual', created_at: '2026-10-14T10:00:00', created_staff: 'S1', mine: true, dups: 0 })), error: null };
  if (fn === 'scan_create') { const id = '11111111-1111-4111-8111-11111111111' + (++S.n); S.jobs[id] = { id, kind: args.p_kind, location_id: 1, status: 'extracted', engine: 'manual', image_path: args.p_image_path, events: [{ at: '2026-10-14T10:00:00', action: 'created', by: 'S1' }], mine: true, can_confirm: true, cost_hidden: false,
     extracted: { supplier: { name: 'Alpha Trader' }, bill_no: 'B-1', date: '2026-10-12', total: '1150', lines: [{ desc: 'Sugar 50kg', qty: '2', unit: 'kg', unit_cost: '500' }, { desc: 'Mystery sack', qty: '1', unit: 'kg', unit_cost: '150' }] },
     confidence: { supplier: 0.9, bill_no: 0.3, lines: [{ unit_cost: 0.4 }, {}] }, edited: null, warnings: [], dups: [] }; return { data: { id, status: 'uploaded', engine: 'manual', same_photo: [] }, error: null }; }
  if (fn === 'scan_get') return S.jobs[args.p_id] ? { data: clone(S.jobs[args.p_id]), error: null } : { data: null, error: { message: 'not found' } };
  if (fn === 'scan_review_save') { const j = S.jobs[args.p_id]; j.edited = args.p_edited; j.status = args.p_final ? 'reviewed' : 'extracted'; return { data: { id: j.id, status: j.status, dups: S.dups, warnings: [] }, error: null }; }
  if (fn === 'scan_match_items') return { data: /sugar/i.test(args.p_text) ? [{ item_id: 'i-1', code: 'S9-SU', name_bn: 'চিনি', name_en: 'Refined Sugar', unit: 'kg', sell_price: null, score: 0.82 }] : [], error: null };
  if (fn === 'scan_match_suppliers') return { data: [{ supplier_id: 's-1', name: 'Alpha Traders', score: 0.9 }], error: null };
  if (fn === 'scan_confirm') { const j = S.jobs[args.p_id]; if (S.refuse) return { data: null, error: { message: S.refuse } }; j.status = 'confirmed'; j.result_type = 'purchase_bills'; j.result_id = 'b-1'; return { data: { id: j.id, status: 'confirmed', result_type: 'purchase_bills', result_id: 'b-1', warnings: [] }, error: null }; }
  if (fn === 'scan_reject') { const j = S.jobs[args.p_id]; j.status = 'rejected'; j.reject_reason = args.p_reason; return { data: { status: 'rejected' }, error: null }; }
  return { data: null, error: null }; }; return c; }; })();`;
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0, n = 0; const ok = (c, m) => { n++; if (!c) { bad++; log('FAIL:', m); } };
  async function open(lang, rules, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept());
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + EXTRA_SC }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    const data = C.mkData(base, {}); data.tables.rules = (data.tables.rules || []).concat(rules.map(([k, v], i) => ({ key: k, module: 'purchase', kind: 'switch', value: v, default_value: null, label_bn: 'x', label_en: 'x', label_mix: 'x', sort: 900 + i })));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0={};try{localStorage.setItem('bos_lang','${lang}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1200); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => window.__M.calls.filter((c) => c[0] === f).map((c) => c[1]), fn);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);

  // ---- switch off ----
  let p = await open('en', [['scan_enabled', false]], '#/scan');
  ok(/switched off/.test(await p.textContent('#sc_body')) && (await p.locator('#sc_cam').count()) === 0, 'scan OFF: message, no camera input'); await noOverflow(p, 'off');
  // ---- list + pick a photo ----
  p = await open('en', [['scan_enabled', true], ['scan_min_confidence', 0.6]], '#/scan');
  ok((await p.locator('#sc_cam').count()) === 1 && (await p.locator('#sc_gal').count()) === 1, 'camera + gallery inputs');
  ok((await p.getAttribute('#sc_cam', 'capture')) === 'environment' && (await p.getAttribute('#sc_cam', 'accept')) === 'image/*', 'capture=environment accept=image/*');
  await p.selectOption('#sc_kind', 'purchase_bill');
  await p.setInputFiles('#sc_gal', { name: 'bill.png', mimeType: 'image/png', buffer: C.PNGBUF }); await wait(p, 1500);
  const up = await p.evaluate(() => window.__UP || []); const sc = await calls(p, 'scan_create');
  ok(up.length === 1 && /^SCAN\/\d+\/[0-9a-f-]{36}\.jpg$/.test(up[0][0]), 'photo uploaded to SCAN/<place>/<uuid>.jpg: ' + JSON.stringify(up.map((u) => u[0])));
  ok(sc.length === 1 && sc[0].p_kind === 'purchase_bill' && sc[0].p_image_path === up[0][0] && /^[0-9a-f]{64}$/.test(sc[0].p_image_hash), 'scan_create with path + sha256');
  ok(/#\/scan\/1{8}-/.test(await p.evaluate(() => location.hash)) || /#\/scan\/[0-9a-f-]{36}/.test(await p.evaluate(() => location.hash)), 'goes to the review page');
  // ---- review page ----
  ok((await p.locator('#sc_img').count()) === 1, 'photo shown through the signed URL'); await noOverflow(p, 'review');
  ok(/Alpha Trader/.test(await p.inputValue('#sc_sup')), 'supplier text prefilled from the reader');
  ok((await p.locator('#sc_h_bill_no').evaluate((e) => e.parentElement.classList.contains('sc-low'))) === true, 'bill no (conf 0.3, untouched) is yellow');
  ok((await p.locator('#sc_l0_uc').evaluate((e) => e.parentElement.classList.contains('sc-low'))) === true, 'line 1 unit cost (conf 0.4) is yellow');
  ok((await p.locator('#sc_h_date').evaluate((e) => e.parentElement.classList.contains('sc-low'))) === false, 'a confident field is not yellow');
  await p.fill('#sc_h_bill_no', 'B-100'); await p.dispatchEvent('#sc_h_bill_no', 'input');
  ok(await p.locator('.sc-sugg[data-act=scan_suppick]').count() === 1, 'supplier suggestion chip appears (existing names only)');
  // nothing is chosen for the person: the lines have NO decision yet
  ok((await p.inputValue('#sc_l0_dec')) === '' && (await p.inputValue('#sc_l1_dec')) === '', 'no line is auto-matched: decision is empty');
  await p.click('[data-act=scan_done]'); await wait(p, 200);
  ok((await calls(p, 'scan_review_save')).length === 0, 'Done with an unmapped supplier is stopped before any server call');
  await p.click('.sc-sugg[data-act=scan_suppick]'); await wait(p, 200);
  ok(/Chosen: Alpha Traders/.test(await p.textContent('#sc_body')), 'supplier chosen by a tap');
  await p.selectOption('#sc_l0_dec', 'map'); await wait(p, 400);
  ok((await p.locator('[data-act=scan_itempick][data-l="0"]').count()) === 1, 'item suggestion for "Sugar 50kg"');
  await p.click('[data-act=scan_itempick][data-l="0"]'); await wait(p, 200);
  ok(/Chosen: S9-SU/.test(await p.textContent('#sc_body')), 'item chosen by a tap');
  await p.selectOption('#sc_l1_dec', 'map'); await wait(p, 400);
  ok((await p.locator('[data-act=scan_itempick][data-l="1"]').count()) === 0 && /No similar existing name/.test(await p.textContent('#sc_body')), 'no suggestion for the mystery sack: nothing invented');
  await p.selectOption('#sc_l1_dec', 'text'); await wait(p, 200);
  await noOverflow(p, 'review after edits');
  await p.screenshot({ path: require('os').tmpdir() + '/sc_review.png' });
  // save draft
  await p.click('[data-act=scan_save]'); await wait(p, 300);
  let rv = await calls(p, 'scan_review_save');
  ok(rv.length === 1 && rv[0].p_final === false && rv[0].p_edited.supplier.id === 's-1' && rv[0].p_edited.bill_no === 'B-100' && rv[0].p_edited.lines[0].item_id === 'i-1' && rv[0].p_edited.lines[0].decision === 'map' && rv[0].p_edited.lines[1].decision === 'text', 'draft saved with the person\'s choices');
  // done -> confirm sheet -> refused (dup) -> ack -> ok
  await p.evaluate(() => { window.__SC.dups = [{ type: 'purchase_bill', id: 'b0' }]; });
  await p.click('[data-act=scan_done]'); await wait(p, 400);
  ok((await p.locator('.sheet #sc_ack').count()) === 1 && /Possible duplicate/.test(await p.textContent('.sheet')) && (await p.locator('.sheet #sc_post').count()) === 1, 'confirm sheet: duplicate box + post option');
  await p.evaluate(() => { window.__SC.refuse = 'duplicate_suspect: []'; });
  await p.click('.sheet [data-act=scan_confirm_go]'); await wait(p, 300);
  ok(/Looks like a duplicate/.test(await p.textContent('#toast')), 'refusal shown in plain English');
  await p.evaluate(() => { window.__SC.refuse = null; });
  await p.check('.sheet #sc_ack'); await p.click('.sheet [data-act=scan_confirm_go]'); await wait(p, 500);
  const cf = await calls(p, 'scan_confirm');
  ok(cf.length === 2 && cf[0].p_client === cf[1].p_client && cf[1].p_ack_dup === true && cf[1].p_post === false, 'confirm retried with the SAME key, acknowledgement sent, post not ticked');
  ok(/Open the purchase bill/.test(await p.textContent('#sc_body')) && (await p.locator('[data-act=scan_save]').count()) === 0, 'after confirm: link to the bill, no more editing');
  await noOverflow(p, 'confirmed');
  // ---- reject path ----
  await p.goto(`http://localhost:${PORT}/#/scan`); await wait(p, 600);
  ok((await p.locator('.sc-row').count()) >= 1, 'list shows the job');
  // ---- Bangla mode renders ----
  p = await open('bn', [['scan_enabled', true]], '#/scan');
  ok(/[ঀ-৿]/.test(await p.textContent('#sc_body')) && (await p.locator('#sc_cam').count()) === 1, 'Bangla page renders'); await noOverflow(p, 'bn');
  ok(errors.length === 0, 'no JS errors: ' + errors.slice(0, 3).join(' | '));
  log('scan_pw_test: ' + (n - bad) + ' pass / ' + bad + ' fail');
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
} catch (e) { console.log('CRASH', e.message); srv.close(); process.exit(1); } })();
