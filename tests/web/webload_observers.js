// Cost of every MutationObserver (the "decorators": itemimg, a11yfix, kbdfix, errlog, controls, catpick, badges107, landed, purchaseprint, pay, dashx ...) per interaction.
// For each observer (identified by the script that created it) it records calls, mutation records and callback time while POS opens with 1369 items and while a few screens open;
// then re-runs the same interaction with that script's observers switched off (observe() ignored) and prints the scripting time saved.
// Run: node tests/web/webload_observers.js      env: WEB_DIR (default web/)  CPU=4  JSON_OUT=file
// Not a *_test.js file (informational; run_all.sh skips it).
const _P = require('./_paths');
const fs = require('fs');
const L = require('./webload_lib');
const CPU = Number(process.env.CPU || 4);
const SEED = fs.readFileSync(require('path').join(__dirname, 'posload_test.js'), 'utf8');
const SEEDJS = SEED.slice(SEED.indexOf('const T = window.__DATA.tables'), SEED.indexOf(" window.__rt = ")).replace(/\$\{RTT\}/g, '0');
const INIT = (off) => `(function(){ ${SEEDJS}
 window.__MO = {}; window.__OFF = ${JSON.stringify(off)};
 const MO = window.MutationObserver;
 const who = () => { const st = (new Error().stack || '').split('\\n'); for (const l of st) { const m = l.match(/\\/([A-Za-z0-9_]+\\.js)(\\?[^:]*)?:\\d+:\\d+/); if (m && !/lazy\\.js/.test(m[1])) return m[1]; } return '?'; };
 window.MutationObserver = function (cb) { const f = who(); const S = window.__MO[f] = window.__MO[f] || { observers: 0, calls: 0, records: 0, ms: 0 }; S.observers++;
   const o = new MO(function (recs, ob) { const t = performance.now(); S.calls++; S.records += recs.length; try { return cb.call(this, recs, ob); } finally { S.ms += performance.now() - t; } });
   const ob = o.observe.bind(o); o.observe = function () { if (window.__OFF.includes(f)) return; return ob.apply(o, arguments); }; return o; };
 window.MutationObserver.prototype = MO.prototype;
})();`;
async function run(off) {
  const srv = await L.makeServer({ root: _P.WEB_DIR }); const br = await L.launch();
  const { ctx } = await L.newCtx(br, { init: INIT(off), noSW: true }); const p = await ctx.newPage(); const cdp = await ctx.newCDPSession(p); await cdp.send('Performance.enable');
  await p.goto(srv.url + '#/home'); await p.waitForSelector('#app .tile', { timeout: 60000 }); await p.waitForTimeout(1500);
  if (CPU > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: CPU });
  const met = async () => { const r = await cdp.send('Performance.getMetrics'); const o = {}; r.metrics.forEach((m) => (o[m.name] = m.value)); return o; };
  const out = {};
  const step = async (name, hash, sel) => { await p.evaluate(() => { location.hash = '#/home'; }); await p.waitForTimeout(700); const m0 = await met(); const s0 = await p.evaluate(() => JSON.stringify(window.__MO));
    await p.evaluate((h) => { location.hash = h; }, hash); await p.waitForSelector(sel, { timeout: 60000 }); await p.waitForTimeout(2500); const m1 = await met();
    const s1 = JSON.parse(await p.evaluate(() => JSON.stringify(window.__MO))), a = JSON.parse(s0), per = {};
    for (const f of Object.keys(s1)) per[f] = { calls: s1[f].calls - ((a[f] || {}).calls || 0), records: s1[f].records - ((a[f] || {}).records || 0), ms: Math.round(s1[f].ms - ((a[f] || {}).ms || 0)) };
    out[name] = { script_ms: Math.round((m1.ScriptDuration - m0.ScriptDuration) * 1000), task_ms: Math.round((m1.TaskDuration - m0.TaskDuration) * 1000), observers: per }; };
  await step('pos_1369_items', '#/pos', '.pos-item');
  await step('home', '#/home', '#app .tile');
  await step('customers', '#/customers', '#app h1');
  await step('stock', '#/stock', '#app h1');
  await br.close(); srv.close(); return out;
}
(async () => {
  const base = await run([]); const res = { base, off: {} };
  const files = [...new Set(Object.values(base).flatMap((s) => Object.keys(s.observers)))].filter((f) => Object.values(base).some((s) => (s.observers[f] || {}).calls > 0));
  console.log('observer (script)       | POS calls/records/callback-ms | Home | Customers | Stock');
  for (const f of files.sort()) console.log(f.padEnd(22), ['pos_1369_items', 'home', 'customers', 'stock'].map((k) => { const o = base[k].observers[f] || { calls: 0, records: 0, ms: 0 }; return `${o.calls}/${o.records}/${o.ms}ms`; }).join(' | '));
  console.log('scripting ms (all):', Object.entries(base).map(([k, v]) => k + '=' + v.script_ms + ' task=' + v.task_ms).join('  '));
  for (const f of files) { const r = await run([f]); res.off[f] = r; console.log('off ' + f.padEnd(18), Object.entries(r).map(([k, v]) => k + ' script ' + (v.script_ms - base[k].script_ms) + ' task ' + (v.task_ms - base[k].task_ms)).join('  ')); }
  if (process.env.JSON_OUT) fs.writeFileSync(process.env.JSON_OUT, JSON.stringify(res, null, 1));
})().catch((e) => { console.error(e); process.exit(1); });
