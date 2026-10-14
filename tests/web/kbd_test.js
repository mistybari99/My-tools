// bos102 keyboard test. Run: node tests/web/kbd_test.js <abs tests/web dir of this worktree>
// Emulates Android Chrome 360x740, then shrinks the viewport to ~300px (= keyboard open) and checks that the primary
// action button of each sheet is fully inside the visible area and really receives a tap.
// A second page runs the same app with kbdfix.js and the bos102 CSS removed ("before") for screenshots + closed-layout comparison.
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || __dirname, ROOT = path.resolve(SP, '../../web');
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const data = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;')(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'content-type': f.endsWith('.js') ? 'text/javascript' : f.endsWith('.css') ? 'text/css' : 'text/html' }); r.end(b); }); }).listen(8102);
const EXTRA = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; window.__CALLS = [];
 c.rpc = async (fn, args) => { window.__CALLS.push([fn, args]); if (fn === 'record_sale2') { window.__LAST = args; return { data: { id: 's1', receipt: 1, total: 0, paid: 0, due: 0 }, error: null }; } if (['find_customer','customer_dues','payments_summary','sales_summary'].includes(fn)) return { data: fn === 'find_customer' ? null : [], error: null }; return rpc(fn, args); }; return c; }; })();`;
const UA = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
let bad = 0, pass = 0; const errors = [];
const ok = (c, m) => { if (c) pass++; else { bad++; console.log('FAIL:', m); } };
const W = 360, H = 740, KH = 300;

async function mk(br, off, theme) {
  const ctx = await br.newContext({ viewport: { width: W, height: H }, userAgent: UA, isMobile: true, hasTouch: true, deviceScaleFactor: 1 }); const p = await ctx.newPage();
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push('console: ' + m.text()); }); p.on('dialog', (d) => d.accept('4'));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  if (off) {
    await p.route('**/kbdfix.js', (r) => r.fulfill({ contentType: 'text/javascript', body: '' }));
    await p.route('**/theme.css', (r) => { const s = fs.readFileSync(ROOT + '/theme.css', 'utf8'); r.fulfill({ contentType: 'text/css', body: s.slice(0, s.indexOf('/* bos102')) }); });
  }
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en');${theme ? `localStorage.setItem('bos_theme','${theme}');` : ''}}catch(e){}`);
  return p;
}
const wait = (p, ms) => p.waitForTimeout(ms);
async function kbd(p, on) { await p.setViewportSize({ width: W, height: on ? KH : H }); await wait(p, 450); }
// is the button fully inside the visible viewport, and does a tap at its centre land on it?
async function probe(p, sel) {
  return p.evaluate((sel) => {
    const b = document.querySelector(sel); if (!b) return { missing: true };
    const r = b.getBoundingClientRect(), vv = window.visualViewport, vh = vv ? vv.height : innerHeight, cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const el = document.elementFromPoint(cx, cy);
    return { top: r.top, bottom: r.bottom, vh, hit: !!el && (el === b || b.contains(el)), inside: r.top >= -0.5 && r.bottom <= vh + 0.5, hscroll: document.documentElement.scrollWidth > innerWidth + 1, sheetBottom: (document.querySelector('.sheet') || { getBoundingClientRect: () => ({ bottom: 0 }) }).getBoundingClientRect().bottom };
  }, sel);
}
async function layoutSig(p) { // bounding boxes of the sheet and every direct/nested control, keyboard closed
  return p.evaluate(() => { const s = document.querySelector('.sheet'); if (!s) return null; const q = (e) => { const r = e.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)].join(','); }; return [q(s), ...[...s.querySelectorAll('h2,input,button,label')].map(q)]; });
}

const SHEETS = [
  { name: 'pos_qty', primary: '[data-act=pos_q_ok]', focus: '#pos_qty', open: async (p, c) => { await p.goto('http://localhost:8102/#/pos'); await p.reload(); await wait(p, 900); await p.click(`.pos-item[data-v="${c.kg.id}"]`); await wait(p, 300); } },
  { name: 'pos_cart', primary: '#cart_ok', focus: '#cart_note', open: async (p, c) => { await p.goto('http://localhost:8102/#/pos'); await p.reload(); await wait(p, 900); await p.click(`.pos-item[data-v="${c.pc.id}"]`); await wait(p, 200); await p.click('[data-act=pos_cart]'); await wait(p, 400); } },
  { name: 'pos_other', primary: '[data-act=pos_ot_ok]', focus: '#ot_price', open: async (p) => { await p.goto('http://localhost:8102/#/pos'); await p.reload(); await wait(p, 900); await p.evaluate(() => document.querySelector('[data-act=pos_other]') ? document.querySelector('[data-act=pos_other]').click() : 0); await wait(p, 300); } },
  // app.js itemSheet is no longer reachable (items2.js routes Add item to a full page), so its markup is replayed: h2 + .stack of fields + trailing .row
  { name: 'item_add_like', primary: '[data-act=itemsave]', focus: '#f_cost', html: `<h2>Add item</h2><div class="stack"><div><label>Name (Bangla)</label><input id="f_bn"></div><div><label>Name (English)</label><input id="f_en"></div><div class="row"><div style="flex:1"><label>Sell price</label><input id="f_sell" inputmode="decimal"></div><div style="flex:1"><label>Cost price</label><input id="f_cost" inputmode="decimal"></div></div><div><label>Category</label><select id="f_cat"><option>Sweets</option></select></div><div><label>Unit</label><select id="f_unit"><option>kg</option></select></div><div class="row"><button class="full" data-act="closesheet">Cancel</button><button class="primary full" data-act="itemsave" data-v="">Save</button></div></div>` },
  { name: 'invoiceview', primary: '[data-act=closesheet]:not(.sheet-x)', focus: '#iv92_phone', open: async (p) => { await p.goto('http://localhost:8102/#/pos'); await p.reload(); await wait(p, 900); await p.evaluate(() => window.BOS.invoiceview.openInfo({ p: { p_lines: [{ name: 'Rosogolla', qty: 2, price: 50, unit: 'pc' }], p_client: 'c1d2e3f4a5', p_loc: 1, p_payments: [] }, pending: true })); await wait(p, 400); } },
  // markup copied from purchase.js postSheet / stock2.js receive sheet (the real screens need a live ledger); same classes, same trailing button row
  { name: 'purchase_post_like', primary: '#pp_go', focus: '#pp_amt', html: `<h2>Post bill · ৳ 4,200</h2><h3>Pay now</h3><div class="stack"><div><label>Cash</label><input id="pp_c" inputmode="decimal"></div><div><label>bKash</label><input id="pp_b" inputmode="decimal"></div><div><label>Amount</label><input id="pp_amt" inputmode="decimal"></div></div><div class="hint">Leftover stays as payable.</div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">Close</button><button class="primary full" id="pp_go" data-act="pu_postgo">Post bill</button></div>` },
  { name: 'stock_issue_like', primary: '[data-act=s2_go_recv]', focus: '#r_qty', html: `<h2>Receive · Sarpuria</h2><p class="muted">Sent: 12 kg · Main → Shop 2</p><div class="stack"><div><label for="r_qty">Quantity received</label><input id="r_qty" inputmode="decimal" value="12"></div><div class="notice warn" id="r_short" hidden>Less than sent</div><div><label for="a_note">Note</label><input id="a_note" autocomplete="off"></div></div><div class="row" style="margin-top:12px"><button class="full" data-act="closesheet">Cancel</button><button class="primary full" data-act="s2_go_recv" data-i="0">Receive</button></div>` },
  { name: 'long_form_like', primary: '#lf_go', focus: '#lf_9', html: `<h2>Long form</h2><div class="stack">${Array.from({ length: 10 }, (_, i) => `<div><label>Field ${i}</label><input id="lf_${i}" inputmode="decimal"></div>`).join('')}<div class="row"><button class="full" data-act="closesheet">Cancel</button><button class="primary full" id="lf_go" data-act="x">Save</button></div></div>` },
];

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const kg = data.tables.items.find((i) => i.unit === 'kg' && i.sell_price), pc = data.tables.items.find((i) => i.unit === 'pc' && i.sell_price);
  data.tables.unit_conversions = [{ id: 1, item_id: kg.id, from_unit: 'pc', to_unit: 'kg', factor: 0.5, active: true }];
  const ctxd = { kg, pc };
  const on = await mk(br, false), off = await mk(br, true);
  for (const s of SHEETS) {
    for (const [page, tag] of [[on, 'after'], [off, 'before']]) {
      await page.setViewportSize({ width: W, height: H });
      if (s.open) await s.open(page, ctxd);
      else { await page.goto('http://localhost:8102/#/pos'); await page.reload(); await wait(page, 900); await page.evaluate((h) => window.BOS_APP.openSheet(h), s.html); await wait(page, 250); }
      const closedSig = await layoutSig(page); const fits = await page.evaluate(() => { const s = document.querySelector('.sheet'); return !!s && s.scrollHeight <= s.clientHeight + 1; }); if (tag === 'before') s._fitsOff = fits; const pClosed = await probe(page, s.primary);
      if (tag === 'after') { s._sig = closedSig; ok(pClosed.inside && pClosed.hit, `${s.name}: closed keyboard, primary visible + tappable ` + JSON.stringify(pClosed)); }
      else s._sigOff = closedSig;
      await page.screenshot({ path: `${SP}/kbd_${tag}_${s.name}_closed.png` });
      await page.focus(s.focus.split(',')[0].trim()).catch(() => page.evaluate(() => { const i = [...document.querySelectorAll('.sheet input')].pop(); if (i) i.focus(); }));
      await kbd(page, true);
      const pr = await probe(page, s.primary);
      await page.screenshot({ path: `${SP}/kbd_${tag}_${s.name}.png` });
      if (tag === 'after') {
        ok(!pr.missing && pr.inside, `${s.name}: keyboard open, primary bottom ${pr.bottom} <= visible ${pr.vh}`);
        ok(pr.hit, `${s.name}: keyboard open, elementFromPoint is the primary button`);
        ok(!pr.hscroll, `${s.name}: no horizontal overflow`);
        ok(await page.evaluate(() => document.documentElement.classList.contains('kbd-open')), `${s.name}: html.kbd-open set`);
        ok(pr.sheetBottom <= pr.vh + 1, `${s.name}: sheet sits above the keyboard (bottom ${pr.sheetBottom})`);
        const fin = await page.evaluate(() => { const a = document.activeElement, r = a.getBoundingClientRect(); return a.tagName === 'INPUT' && r.top >= 0 && r.bottom <= window.visualViewport.height; });
        ok(fin, `${s.name}: focused field is in view`);
        // really tap it
        if (s.name === 'pos_qty') { await page.tap(s.primary); await wait(page, 300); ok(await page.locator('#sheet').count() === 0 && /1/.test(await page.textContent('#pos_bar')), 'pos_qty: tapping Add under the keyboard adds the item and closes the sheet'); }
      } else if (s.name === 'pos_qty') console.log('info: before-fix pos_qty primary bottom', Math.round(pr.bottom), 'visible', Math.round(pr.vh), 'inside=' + pr.inside);
      await kbd(page, false);
      if (tag === 'after') { const back = await layoutSig(page); if (s._fitsOff) ok(JSON.stringify(back) === JSON.stringify(s._sig), `${s.name}: closing the keyboard restores the closed layout`); }
    }
    // closed layout identical with and without the fix (boxes, 1px tolerance)
    const a = s._sig, b = s._sigOff; let same = !!a && !!b && a.length === b.length;
    if (same) for (let i = 0; i < a.length; i++) { const x = a[i].split(',').map(Number), y = b[i].split(',').map(Number); if (x.some((v, k) => Math.abs(v - y[k]) > 1)) { same = false; console.log('  diff', s.name, i, a[i], b[i]); } }
    if (s._fitsOff) ok(same, `${s.name}: closed-keyboard layout identical to before`); else console.log(`info: ${s.name} is taller than the screen: the action bar is now pinned instead of scrolled off (intended difference)`);
  }
  // Enter key in the qty field presses Add
  await on.setViewportSize({ width: W, height: H }); await SHEETS[0].open(on, ctxd); await on.focus('#pos_qty'); await on.keyboard.press('Enter'); await wait(on, 300);
  ok(await on.locator('#sheet').count() === 0, 'Enter in the quantity field presses Add');
  // bottom nav hidden and POS bar above the keyboard while typing in the POS search
  await on.goto('http://localhost:8102/#/pos'); await on.reload(); await wait(on, 900); await on.click(`.pos-item[data-v="${pc.id}"]`); await wait(on, 200);
  const sq = await on.$('#pos_q, input[type=search], .pos-search input'); if (sq) { await sq.focus(); await kbd(on, true);
    const bar = await on.evaluate(() => { const b = document.querySelector('#pos_bar'), r = b.getBoundingClientRect(), n = document.querySelector('.bnav'); return { bottom: r.bottom, vh: window.visualViewport.height, nav: n ? getComputedStyle(n).display : 'none' }; });
    ok(bar.bottom <= bar.vh + 1 && bar.nav === 'none', 'POS total bar above keyboard, bottom nav hidden: ' + JSON.stringify(bar)); await kbd(on, false); } else console.log('info: no POS search field found, bar check skipped');
  // themes + desktop + iOS-like (no interactive-widget, visualViewport only shrinks)
  for (const th of ['dark', 'light', 'classic']) { const p = await mk(br, false, th); await SHEETS[0].open(p, ctxd); await p.focus('#pos_qty'); await kbd(p, true); const r = await probe(p, '[data-act=pos_q_ok]'); ok(r.inside && r.hit, `theme ${th}: primary visible under keyboard`); await p.screenshot({ path: `${SP}/kbd_after_theme_${th}.png` }); await p.close(); }
  { const ctx = await br.newContext({ viewport: { width: 1280, height: 800 } }); const p = await ctx.newPage(); p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + EXTRA })); await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en');}catch(e){}`); await p.goto('http://localhost:8102/#/pos'); await wait(p, 900); await p.click(`.pos-item[data-v="${kg.id}"]`); await wait(p, 300);
    const r = await probe(p, '[data-act=pos_q_ok]'); ok(r.inside && r.hit && !r.hscroll, 'desktop 1280x800: qty sheet primary visible, no kbd class: ' + !(await p.evaluate(() => document.documentElement.classList.contains('kbd-open')))); await ctx.close(); }
  { // iOS-style: layout viewport stays tall, only the visual viewport shrinks -> emulate by forcing visualViewport values
    const p = await mk(br, false); await SHEETS[0].open(p, ctxd); await p.focus('#pos_qty');
    await p.evaluate((kh) => { const real = window.visualViewport; const fake = new EventTarget(); Object.defineProperties(fake, { height: { get: () => kh }, width: { get: () => 360 }, offsetTop: { get: () => 0 } }); Object.defineProperty(window, 'visualViewport', { get: () => fake }); window.__fakevv = fake; }, KH);
    // kbdfix captured the real visualViewport at load; poke it via its own measure() after forcing a re-read
    await p.evaluate(() => { window.BOS_KBD.measure(); }); await wait(p, 300);
    const r = await p.evaluate(() => { const b = document.querySelector('[data-act=pos_q_ok]').getBoundingClientRect(); return { bottom: b.bottom, cls: document.documentElement.classList.contains('kbd-open') }; });
    console.log('info: iOS-style forced visualViewport (kbdfix reads the real object, so this only checks no crash):', JSON.stringify(r)); await p.close(); }
  console.log('errors:', errors.length ? errors.join('\n') : 'none'); ok(errors.length === 0, 'no page errors');
  console.log(`kbd_test: pass ${pass}, fail ${bad}`); await br.close(); srv.close(); process.exit(bad ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
