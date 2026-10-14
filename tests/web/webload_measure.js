// Web-load benchmark. Usage: node tests/web/webload_measure.js label=dir [label=dir ...]
//   env: NET=fast3g|slow4g|none (default slow4g)  CPU=4 (throttle rate, default 4)  HOME=1 (default: wait for Home tiles)  SETTLE=ms (default 8000)  OUT=file.json  TRACE=1 (per-script evaluate/compile times)
//   each dir is a web root (index.html + scripts). The server serves it over https/h2 with gzip and a SHARED link of NET speed (page AND service worker fetches), signed-in mock Supabase.
const fs = require('fs');
const L = require('./webload_lib');
const PROFILES = { fast3g: { rttMs: 280, kBps: 188 }, slow4g: { rttMs: 75, kBps: 188 }, none: { rttMs: 0, kBps: 0 } };   // RTT is added once per response (h2: requests overlap); 188 KB/s = 1.6 Mbit/s * 0.9 like DevTools
const NET = process.env.NET || 'slow4g', CPU = Number(process.env.CPU || 4), SETTLE = Number(process.env.SETTLE || 8000);
const INIT = `(function(){
 window.__m = { lt: [], cls: 0, fcp: null, inter: null, tiles: null };
 try { new PerformanceObserver((l) => l.getEntries().forEach((e) => window.__m.lt.push([Math.round(e.startTime), Math.round(e.duration)]))).observe({ type: 'longtask', buffered: true }); } catch (e) {}
 try { new PerformanceObserver((l) => l.getEntries().forEach((e) => { if (e.name === 'first-contentful-paint') window.__m.fcp = e.startTime; })).observe({ type: 'paint', buffered: true }); } catch (e) {}
 try { new PerformanceObserver((l) => l.getEntries().forEach((e) => { if (!e.hadRecentInput) window.__m.cls += e.value; })).observe({ type: 'layout-shift', buffered: true }); } catch (e) {}
 const chk = () => { if (window.__m.inter === null && document.querySelector('#app .tile, #app .pos-item')) { window.__m.inter = performance.now(); window.__m.tiles = document.querySelectorAll('#app .tile').length; } };
 const go = () => { new MutationObserver(chk).observe(document.documentElement, { childList: true, subtree: true }); chk(); };
 if (document.documentElement) go(); else document.addEventListener('readystatechange', go);
})();`;
async function cdpMetrics(cdp) { const r = await cdp.send('Performance.getMetrics'); const o = {}; r.metrics.forEach((m) => (o[m.name] = m.value)); return o; }
const ms = (s) => Math.round(s * 1000);
async function visit(ctx, srv, url, label, o) {
  const p = await ctx.newPage(); const cdp = await ctx.newCDPSession(p);
  await cdp.send('Performance.enable'); if (CPU > 1) await cdp.send('Emulation.setCPUThrottlingRate', { rate: CPU });
  const i0 = srv.log.length; const t0 = Date.now();
  await p.goto(url, { waitUntil: 'commit' });
  await p.waitForFunction(() => window.__m && window.__m.inter !== null, null, { timeout: 120000, polling: 50 });
  const tI = Date.now() - t0; const mI = await cdpMetrics(cdp);
  const iLog = srv.log.slice(i0); const bytesI = iLog.reduce((s, r) => s + r.bytes, 0), reqI = iLog.length;
  const pm = await p.evaluate(() => ({ fcp: window.__m.fcp, inter: window.__m.inter, tiles: window.__m.tiles, lt: window.__m.lt, cls: window.__m.cls }));
  await p.waitForTimeout(SETTLE);
  const mE = await cdpMetrics(cdp); const eLog = srv.log.slice(i0); const bytesE = eLog.reduce((s, r) => s + r.bytes, 0);
  const pm2 = await p.evaluate(() => ({ lt: window.__m.lt, cls: window.__m.cls }));
  const swBytes = eLog.filter((r) => r.sw).reduce((s, r) => s + r.bytes, 0);
  const row = { label, req_at_interactive: reqI, kb_at_interactive: Math.round(bytesI / 1024), req_total: eLog.length, kb_total: Math.round(bytesE / 1024), kb_by_service_worker: Math.round(swBytes / 1024),
    fcp_ms: Math.round(pm.fcp), interactive_ms: Math.round(pm.inter), tiles: pm.tiles,
    script_ms_at_interactive: ms(mI.ScriptDuration), task_ms_at_interactive: ms(mI.TaskDuration), script_ms_total: ms(mE.ScriptDuration), task_ms_total: ms(mE.TaskDuration), layout_style_ms: ms((mE.LayoutDuration || 0) + (mE.RecalcStyleDuration || 0)),
    longtasks_gt50: pm2.lt.length, longtask_ms_sum: pm2.lt.reduce((s, x) => s + x[1], 0), longest_ms: Math.max(0, ...pm2.lt.map((x) => x[1])), cls: Math.round(pm2.cls * 1000) / 1000 };
  row.files = eLog.map((r) => ({ p: r.p, b: r.bytes, raw: r.raw }));
  await p.close(); return row;
}
(async () => {
  const targets = process.argv.slice(2).map((a) => { const i = a.indexOf('='); return [a.slice(0, i), a.slice(i + 1)]; });
  const br = await L.launch(); const out = [];
  for (const [label, dir] of targets) {
    for (const mode of ['cold', 'warm', 'hot']) {   // cold = first ever visit; warm = returning visit after the 10-min HTTP max-age (every file is revalidated, 304); hot = returning within 10 min (HTTP cache fresh)
      const srv = await L.makeServer(Object.assign({ root: dir, maxAge: mode === 'warm' ? 0 : 600 }, PROFILES[NET])); const { ctx, errs } = await L.newCtx(br, { init: INIT });
      let row;
      if (mode === 'cold') row = await visit(ctx, srv, srv.url, label, {});
      else { const prep = PROFILES[NET]; srv.kBps = 0; srv.rttMs = 0; const w = await ctx.newPage(); await w.goto(srv.url); await w.waitForSelector('#app .tile', { timeout: 60000 }); await w.waitForTimeout(4000); await w.reload(); await w.waitForTimeout(4000); await w.close();   // fill HTTP + SW caches on a fast link
        srv.kBps = prep.kBps; srv.rttMs = prep.rttMs; row = await visit(ctx, srv, srv.url, label, {}); }
      row.mode = mode; row.net = NET; row.cpu = CPU; row.errors = errs.length; row.errs = errs.slice(0, 3); out.push(row);
      console.log(JSON.stringify(Object.assign({}, row, { files: undefined })));
      await ctx.close(); srv.close();
    }
  }
  await br.close();
  if (process.env.OUT) fs.writeFileSync(process.env.OUT, JSON.stringify(out, null, 1));
  console.log('\n' + ['label', 'mode', 'req@int', 'KB@int', 'req', 'KB', 'KB(SW)', 'FCP', 'interactive', 'script@int', 'script', 'longtasks', 'CLS'].join('\t'));
  out.forEach((r) => console.log([r.label, r.mode, r.req_at_interactive, r.kb_at_interactive, r.req_total, r.kb_total, r.kb_by_service_worker, r.fcp_ms, r.interactive_ms, r.script_ms_at_interactive, r.script_ms_total, r.longtasks_gt50 + '/' + r.longtask_ms_sum + 'ms', r.cls].join('\t')));
})().catch((e) => { console.error(e); process.exit(1); });
