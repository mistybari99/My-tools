// POS open with the owner's real catalogue size: 1369 items, 231 categories (mock seed, no images). Measures tap -> cards visible, scripting, DOM nodes, long tasks, database round trips
// (rpc + from() calls) per POS open and per sale, and asserts the loading state + chunked rendering + that all cards are eventually drawn.
// Run: node tests/web/posload_test.js      env: WEB_DIR  CPU=4 (throttle, default 4)  NET=none|slow4g|fast3g (default slow4g: 75 ms RTT)  JSON_OUT=file
const _P = require('./_paths');
const fs = require('fs');
const L = require('./webload_lib');
const CPU = Number(process.env.CPU || 4), NETN = process.env.NET || 'slow4g';
const RTT = { none: 0, slow4g: 75, fast3g: 280 }[NETN];
let pass = 0, failn = 0; const chk = (n, ok, x) => { if (ok) { pass++; console.log('  ok  ', n); } else { failn++; console.log('  FAIL', n, x === undefined ? '' : JSON.stringify(x)); } };
const INIT = `(function(){
 const T = window.__DATA.tables, base = T.items.slice(), N = 1369, C = 231, out = [];
 for (let i = 0; i < N; i++) { const b = base[i % base.length]; out.push(Object.assign({}, b, { id: 'x' + i, code: 'I-' + String(i + 1).padStart(4, '0'), name_bn: 'আইটেম ' + i, name_en: 'Item ' + i, category: 'cat' + (i % C), category_bn: 'ক্যাট ' + (i % C), sub_category: null, sell_price: 20 + (i % 90) * 5, sellable: true, hidden: false, item_type: 'finished', is_active: true, barcode: null })); }
 T.items = out;
 window.__rt = { rpc: [], from: [] }; let real;
 Object.defineProperty(window, 'supabase', { configurable: true, get() { return real; }, set(v) { real = v; const cc = v.createClient; v.createClient = (...a) => { const c = cc(...a); const r = c.rpc.bind(c), f = c.from.bind(c);
   c.rpc = (fn, ar) => { window.__rt.rpc.push(fn); (window.__rt.tl = window.__rt.tl || []).push('rpc:' + fn + '@' + Math.round(performance.now() - (window.__tTap || 0))); return new Promise((res) => setTimeout(() => res(r(fn, ar)), ${RTT})); };
   c.from = (t) => { window.__rt.from.push(t); (window.__rt.tl = window.__rt.tl || []).push('from:' + t + '@' + Math.round(performance.now() - (window.__tTap || 0))); const b = f(t); const th = b.then.bind(b); b.then = (a, z) => new Promise((res) => setTimeout(res, ${RTT})).then(() => th(a, z)); return b; }; return c; }; } });
 window.__lt = []; try { new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__lt.push(Math.round(e.duration)))).observe({ type: 'longtask', buffered: true }); } catch (e) {}
})();`;
async function scrollAll(p, n) { for (let i = 0; i < 80; i++) { if ((await p.locator('.pos-item').count()) >= n) return true; await p.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight)); await p.waitForTimeout(60); } return false; }
(async () => {
  const srv = await L.makeServer({ root: _P.WEB_DIR }); const br = await L.launch();
  const { ctx, errs, sales } = await L.newCtx(br, { init: INIT, noSW: true }); const p = await ctx.newPage(); const cdp = await ctx.newCDPSession(p);
  await cdp.send('Performance.enable');
  await p.goto(srv.url + '#/home'); await p.waitForSelector('#app .tile', { timeout: 60000 }); await p.waitForTimeout(1500);
  if (CPU > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: CPU });
  const met = async () => { const r = await cdp.send('Performance.getMetrics'); const o = {}; r.metrics.forEach((m) => (o[m.name] = m.value)); return o; };
  const res = {};
  for (const open of ['first', 'second']) {
    if (open === 'second') { await p.evaluate(() => { location.hash = '#/home'; }); await p.waitForTimeout(800); }
    const rt0 = await p.evaluate(() => ({ r: window.__rt.rpc.length, f: window.__rt.from.length, lt: window.__lt.length })); const m0 = await met();
    const t0 = Date.now();
    await p.evaluate(() => { window.__sawLoading = false; window.__tTap = performance.now(); window.__tFirst = window.__tAll = null; new MutationObserver(() => { const n = document.querySelectorAll('.pos-item').length; if (n && window.__tFirst === null) { window.__tFirst = -1; requestAnimationFrame(() => requestAnimationFrame(() => { window.__tFirst = Math.round(performance.now() - window.__tTap); })); } if (n >= 1369 && window.__tAll === null) window.__tAll = Math.round(performance.now() - window.__tTap); const a = document.querySelector('#app'); if (a && /Loading|লোড/.test(a.textContent) && !document.querySelector('.pos-item')) window.__sawLoading = true; }).observe(document.body, { childList: true, subtree: true }); location.hash = '#/pos'; });
    await p.waitForSelector('.pos-item', { timeout: 60000 }); const tCards = Date.now() - t0;
    const firstN = await p.locator('.pos-item').count();
    const drawn0 = await p.locator('.pos-item').count(); await p.waitForTimeout(1500);
    const m1 = await met(); const rt1 = await p.evaluate(() => ({ r: window.__rt.rpc.length, f: window.__rt.from.length, lt: window.__lt.length, ltl: window.__lt.slice(), nodes: document.getElementsByTagName('*').length, saw: window.__sawLoading }));
    res[open] = { ms_to_first_cards: await p.evaluate(() => window.__tFirst), first_paint_cards: firstN, drawn_before_scroll: drawn0, script_ms: Math.round((m1.ScriptDuration - m0.ScriptDuration) * 1000), task_ms: Math.round((m1.TaskDuration - m0.TaskDuration) * 1000), layout_ms: Math.round((m1.LayoutDuration - m0.LayoutDuration) * 1000), style_ms: Math.round((m1.RecalcStyleDuration - m0.RecalcStyleDuration) * 1000), nodes: rt1.nodes,
      longtasks: rt1.lt - rt0.lt, longest: Math.max(0, ...rt1.ltl.slice(rt0.lt)), rpc: rt1.r - rt0.r, from: rt1.f - rt0.f, loading_shown: rt1.saw };
    await scrollAll(p, 1369); res[open].ms_scroll_to_all = Date.now() - t0; await p.evaluate(() => window.scrollTo(0, 0));
  }
  // search + category filter over the in-memory list, and one sale
  const s0 = Date.now(); await p.fill('#pos_q', 'Item 77'); await p.waitForFunction(() => document.querySelectorAll('.pos-item').length < 30, null, { timeout: 20000 }); res.search_ms = Date.now() - s0;
  await p.fill('#pos_q', ''); chk('scrolling the list draws all 1369 cards', await scrollAll(p, 1369)); await p.evaluate(() => window.scrollTo(0, 0));
  await p.fill('#pos_q', 'Item 5'); await p.waitForTimeout(400);
  const rtS = await p.evaluate(() => ({ r: window.__rt.rpc.length, f: window.__rt.from.length }));
  await p.click('.pos-item >> nth=0'); await p.waitForTimeout(200); const q = await p.$('[data-act=pos_q_ok]'); if (q) await q.click();
  await p.click('[data-act=pos_cart]'); await p.waitForSelector('#cart_ok'); await p.click('#cart_ok'); await p.waitForTimeout(1500);
  const rtE = await p.evaluate(() => ({ r: window.__rt.rpc.slice(0), f: window.__rt.from.slice(0) }));
  res.sale_rpc = rtE.r.length - rtS.r; res.sale_from = rtE.f.length - rtS.f; res.sale_rpc_names = rtE.r.slice(rtS.r).concat(rtE.f.slice(rtS.f).map((x) => 'from:' + x));
  res.sales_recorded = Object.keys(sales).length; res.sale_rpc_calls = Object.values(sales).reduce((n, x) => n + x.calls.length, 0);
  res.timeline = await p.evaluate(() => (window.__rt.tl || []).filter((x) => Number(x.split('@')[1]) > -1e9).slice(0, 60));
  console.log(JSON.stringify(res, null, 1));
  chk('POS shows cards (first open)', res.first.first_paint_cards > 0);
  chk('only a window of cards is in the page before scrolling (<= 200 of 1369)', res.first.drawn_before_scroll <= 200 && res.second.drawn_before_scroll <= 200, [res.first.drawn_before_scroll, res.second.drawn_before_scroll]);
  chk('loading state is shown while the POS loads (first open)', res.first.loading_shown === true);
  chk('one sale recorded with ONE record_sale call and no extra database reads', res.sales_recorded === 1 && res.sale_rpc_calls === 1 && res.sale_rpc_names.filter((n) => !['_w1f_receipt_settings', 'crmf_status', 'notifications_unread_count'].includes(n)).length === 0, { calls: res.sale_rpc_calls, rpc: res.sale_rpc, from: res.sale_from });   // union merge: our two settings reads (receipt channels phase 97, coupon status CRM-F) happen once per session, on the first sale
  chk('POS cards visible fast (<= 1500 ms at 4x CPU, ' + NETN + ') on the first open and <= 800 ms on the second', res.first.ms_to_first_cards <= 1500 && res.second.ms_to_first_cards <= 800, [res.first.ms_to_first_cards, res.second.ms_to_first_cards]);
  chk('no single long task above 600 ms while the POS opens with 1369 items', res.first.longest <= 600 && res.second.longest <= 600, [res.first.longest, res.second.longest]);
  chk('second open reads at most 3 tables/functions (items + unit_conversions + favourite)', res.second.rpc + res.second.from <= 3, res.second);
  chk('search over the 1369 items answers (filter in memory)', res.search_ms < 3000, res.search_ms);
  chk('no page errors', errs.length === 0, errs.slice(0, 3));
  if (process.env.JSON_OUT) fs.writeFileSync(process.env.JSON_OUT, JSON.stringify(res, null, 1));
  console.log(`${pass} passed, ${failn} failed`);
  await br.close(); srv.close(); process.exit(failn ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
