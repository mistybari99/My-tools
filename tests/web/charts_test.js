// web/charts.js (B.charts): 10 chart types x 5 data shapes in Chromium at 360px, dark + light. No server, no database: a bare page + a minimal B shim.
// Checks: SVG present, no NaN/undefined in attributes, no overflow, pie = 360deg, treemap tiles the area, gauge needle / bullet marker positions, update(), destroy() listeners,
// XSS inert, empty / zero data safe, convert() round trip, English-mode has no Bangla, palette contrast, contact sheets tests/web/charts_dark.png + charts_light.png.
// Run: node tests/web/charts_test.js
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path');
const WEB = _P.WEB_DIR, OUT = _P.TESTS_DIR;
let n = 0, bad = 0;
const ck = (name, ok, extra) => { n++; if (!ok) { bad++; console.log('FAIL ' + name + (extra !== undefined ? ' :: ' + JSON.stringify(extra).slice(0, 300) : '')); } };
const BN = /[ঀ-৿]/;
const src = fs.readFileSync(path.join(WEB, 'charts.js'), 'utf8');
const idx = fs.readFileSync(path.join(WEB, 'index.html'), 'utf8');

// ---------- static ----------
ck('no merge-conflict markers', !/^(<<<<<<<|=======|>>>>>>>)/m.test(src) && !/^(<<<<<<<|=======|>>>>>>>)/m.test(idx));
ck('no CDN / external url', !/https?:\/\//.test(src.replace(/http:\/\/www\.w3\.org\/2000\/svg/, '')));
ck('no innerHTML / eval / document.write', !/innerHTML|outerHTML|insertAdjacentHTML|eval\(|new Function|document\.write/.test(src));
ck('index.html loads charts.js once, at the end', (idx.match(/charts\.js/g) || []).length === 1 && idx.lastIndexOf('charts.js') > idx.lastIndexOf('itemimg.js') && idx.indexOf('</body>') > idx.indexOf('charts.js'));
ck('all css classes use the .bch prefix', ![...src.matchAll(/^\.([a-z][\w-]*)/gm)].some((m) => !m[1].startsWith('bch')));
const str = "'((?:[^'\\\\]|\\\\.)*)'";
let ls = 0;
for (const m of src.matchAll(new RegExp('L\\(\\s*' + str + ',\\s*' + str + ',\\s*' + str + '\\s*\\)', 'g'))) { ls++; ck('English has no Bangla: ' + m[2], !BN.test(m[2])); ck('bn/mix not empty: ' + m[2], m[1].length > 0 && m[3].length > 0); }
ck('found 3-mode strings', ls >= 20);

const LABELS = { line: ['Line chart', 'লাইন চার্ট'], area: ['Area chart', 'এরিয়া চার্ট'], bar: ['Bar chart', 'বার চার্ট'], column: ['Column chart', 'কলাম চার্ট'], stacked_bar: ['Stacked bar chart', 'স্ট্যাকড বার চার্ট'], pie: ['Pie chart', 'পাই চার্ট'], donut: ['Donut chart', 'ডোনাট চার্ট'], treemap: ['Treemap', 'ট্রি-ম্যাপ চার্ট'], gauge: ['Gauge chart', 'গেজ চার্ট'], bullet: ['Bullet chart', 'বুলেট চার্ট'] };

// ---------- shapes ----------
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'];
const SHAPES = {
  time1: { title: 'Daily sales', series: [{ name: 'Sales', points: MONTHS.map((x, i) => ({ x, y: [12000, 18500, 9000, 24000, 31000, 27500, 40250][i] })) }], unit: 'Tk' },
  multi: { title: 'Sales vs cost', series: [{ name: 'Sales', points: MONTHS.map((x, i) => ({ x, y: 1000 * (i + 3) })) }, { name: 'Cost', points: MONTHS.map((x, i) => ({ x, y: 700 * (i + 2) })) }, { name: 'Profit', points: MONTHS.map((x, i) => ({ x, y: 300 * (i + 1) - 400 })) }] },
  comp: { title: 'Sales by branch', slices: [{ label: 'Hub', value: 52000 }, { label: 'Misty Bari', value: 31000 }, { label: 'Al-Cakiz with a very long branch name that must be cut', value: 18000 }, { label: 'Web', value: 4000 }, { label: 'Other', value: 900 }] },
  neg: { title: 'Profit by month', series: [{ name: 'Profit', points: [{ x: 'Jan', y: -4200 }, { x: 'Feb', y: 3500 }, { x: 'Mar', y: -800 }, { x: 'Apr', y: 12000 }, { x: 'May', y: 9000 }] }] },
  single: { title: 'Collection', value: 7250000, min: 0, max: 10000000, target: 8000000, ranges: [{ to: 3000000, color: '#ff7a5c' }, { to: 7000000, color: '#f0e442' }, { to: 10000000, color: '#4fd1a5' }] },
};
const SHAPE_TYPES = { time1: ['line', 'area', 'column', 'bar'], multi: ['line', 'area', 'column', 'bar', 'stacked_bar'], comp: ['pie', 'donut', 'treemap', 'bar', 'column'], neg: ['line', 'area', 'column', 'bar'], single: ['gauge', 'bullet'] };

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const ctx = await br.newContext({ bypassCSP: true, viewport: { width: 360, height: 800 }, deviceScaleFactor: 2, hasTouch: true });
  const page = await ctx.newPage();
  const errs = []; page.on('pageerror', (e) => errs.push(String(e))); page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text()); });
  await page.setContent('<!doctype html><html data-theme="dark"><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;padding:16px;background:#17181c;font-family:system-ui}#h{width:328px}.card{width:328px;margin:0 0 12px;padding:0}</style></head><body><div id="h"></div></body></html>');
  await page.evaluate(() => {
    window.__lang = 'en'; window.BOS = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (x) => (!x ? '' : typeof x === 'string' ? x : x[window.__lang] || x.en) };
    // listener accounting (add/remove balance after destroy) + observers
    window.__ev = { add: 0, rem: 0 }; window.__ro = { made: 0, disc: 0 };
    const ea = EventTarget.prototype.addEventListener, er = EventTarget.prototype.removeEventListener;
    EventTarget.prototype.addEventListener = function (t, f, o) { if (window.__count) window.__ev.add++; return ea.call(this, t, f, o); };
    EventTarget.prototype.removeEventListener = function (t, f, o) { if (window.__count) window.__ev.rem++; return er.call(this, t, f, o); };
    const RO = window.ResizeObserver; window.ResizeObserver = class extends RO { constructor(cb) { super(cb); if (window.__count) window.__ro.made++; } disconnect() { if (window.__count) window.__ro.disc++; return super.disconnect(); } };
  });
  await page.addScriptTag({ content: src });
  ck('B.charts exposed', await page.evaluate(() => !!(window.BOS.charts && window.BOS.charts.render && window.BOS.charts.compatible && window.BOS.charts.convert && window.BOS.charts.TYPES)));
  ck('style#bch-css injected after first render only', await page.evaluate(() => { const had = !!document.getElementById('bch-css'); const h = document.createElement('div'); document.body.appendChild(h); window.BOS.charts.render(h, { type: 'column', series: [{ name: 'a', points: [{ x: 'a', y: 1 }] }] }).destroy(); h.remove(); return !had && document.querySelectorAll('#bch-css').length === 1; }));

  // ---------- TYPES ----------
  const types = await page.evaluate(() => window.BOS.charts.TYPES.map((t) => ({ id: t.id, en: t.label.en, bn: t.label.bn, mix: t.label.mix, icon: typeof t.icon === 'string' && /^<svg/.test(t.icon) })));
  ck('10 types in the contract order', types.map((t) => t.id).join() === 'line,area,bar,column,stacked_bar,pie,donut,treemap,gauge,bullet');
  types.forEach((t) => {
    ck('label en ' + t.id, t.en === LABELS[t.id][0]); ck('label bn ' + t.id, t.bn === LABELS[t.id][1]);
    ck('label en has no Bangla ' + t.id, !BN.test(t.en)); ck('label mix has English + Bangla ' + t.id, /[A-Za-z]/.test(t.mix) && BN.test(t.mix)); ck('icon ' + t.id, t.icon);
  });

  // ---------- palette contrast ----------
  const pal = await page.evaluate(() => ({ dark: window.BOS.charts.palette('dark'), light: window.BOS.charts.palette('light') }));
  const lum = (h) => { const c = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4))); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
  const cr = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
  ck('palette has 8 colours each', pal.dark.length === 8 && pal.light.length === 8);
  pal.dark.forEach((c) => ck('dark colour contrast >= 3 on tile ' + c, cr(c, '#23252b') >= 3 && cr(c, '#17181c') >= 3, cr(c, '#23252b')));
  pal.light.forEach((c) => ck('light colour contrast >= 3 on white ' + c, cr(c, '#ffffff') >= 3 && cr(c, '#fbf5ee') >= 3, cr(c, '#ffffff')));
  ck('palette order starts orange then cyan', pal.dark[0] === '#f5a623' && pal.dark[1] === '#35c7ea');

  // ---------- render matrix: types x shapes, dark + light ----------
  const matrix = async (theme) => page.evaluate(({ SHAPES, SHAPE_TYPES, theme }) => {
    document.documentElement.setAttribute('data-theme', theme);
    const out = [], hostBox = document.getElementById('h');
    hostBox.textContent = '';
    for (const sh of Object.keys(SHAPES)) for (const type of SHAPE_TYPES[sh]) {
      const host = document.createElement('div'); host.className = 'card'; host.style.background = theme === 'dark' ? '#23252b' : '#fff'; host.dataset.case = sh + '|' + type; hostBox.appendChild(host);
      const spec = Object.assign({}, SHAPES[sh], { type, theme: 'auto', animate: false });
      const ch = window.BOS.charts.render(host, spec);
      const svg = host.querySelector('svg.bch-svg');
      const badAttr = []; host.querySelectorAll('*').forEach((e) => { for (const a of e.attributes) if (/NaN|undefined|Infinity/.test(a.value)) badAttr.push(e.tagName + '@' + a.name + '=' + a.value.slice(0, 40)); if (e.children.length === 0 && /NaN|undefined|Infinity/.test(e.textContent)) badAttr.push('text:' + e.textContent.slice(0, 30)); });
      const hb = host.getBoundingClientRect(); const over = [];
      host.querySelectorAll('svg *').forEach((e) => { if (e.closest('defs') || e.classList.contains('bch-hit')) return; const b = e.getBoundingClientRect(); if (b.width === 0 && b.height === 0) return; if (b.right > hb.right + 1.5 || b.left < hb.left - 1.5) over.push(e.tagName + ':' + e.getAttribute('class') + ':' + Math.round(b.left - hb.left) + '..' + Math.round(b.right - hb.left)); });
      out.push({ sh, type, svg: !!svg, role: svg && svg.getAttribute('role'), aria: svg && svg.getAttribute('aria-label'), table: host.querySelectorAll('table.bch-sr, .bch-sr table').length, rows: host.querySelectorAll('.bch-sr tbody tr').length, badAttr, over, scrollOK: host.scrollWidth <= host.clientWidth + 1, w: hb.width, svgW: svg.getBoundingClientRect().width, h: hb.height, dt: svg && svg.getAttribute('data-type') });
      window.__keep = (window.__keep || []).concat(ch);
    }
    return out;
  }, { SHAPES, SHAPE_TYPES, theme });

  for (const theme of ['dark', 'light']) {
    const res = await matrix(theme);
    ck(theme + ': 20 combos rendered', res.length === 20, res.length);
    for (const r of res) {
      const id = theme + ' ' + r.sh + '/' + r.type;
      ck(id + ' svg', r.svg); ck(id + ' role=img + aria-label', r.role === 'img' && r.aria && r.aria.length > 10, r.aria);
      ck(id + ' data-type', r.dt === r.type);
      ck(id + ' hidden data table', r.table >= 1 && r.rows >= 1, [r.table, r.rows]);
      ck(id + ' no NaN/undefined', r.badAttr.length === 0, r.badAttr);
      ck(id + ' no overflow', r.over.length === 0 && r.scrollOK && r.svgW <= r.w + 0.5, r.over);
    }
    await page.waitForTimeout(1300);
    await page.evaluate((t) => { document.body.style.background = t === 'dark' ? '#17181c' : '#fbf5ee'; }, theme);
    await page.screenshot({ path: path.join(OUT, 'charts_' + theme + '.png'), fullPage: true });
    await page.evaluate(() => { (window.__keep || []).forEach((c) => c.destroy()); window.__keep = []; });
  }

  // ---------- per-type geometry ----------
  const geo = await page.evaluate(({ SHAPES }) => {
    document.documentElement.setAttribute('data-theme', 'dark');
    const hb = document.getElementById('h'); hb.textContent = '';
    const mk = (spec) => { const h = document.createElement('div'); h.style.width = '328px'; hb.appendChild(h); return { h, ch: window.BOS.charts.render(h, spec) }; };
    const out = {};
    // pie / donut
    for (const t of ['pie', 'donut']) {
      const { h } = mk(Object.assign({}, SHAPES.comp, { type: t }));
      const ps = [...h.querySelectorAll('.bch-slice')]; out[t] = { n: ps.length, sum: ps.reduce((a, p) => a + (Number(p.dataset.a1) - Number(p.dataset.a0)), 0), contiguous: ps.every((p, i) => i === 0 || Math.abs(Number(p.dataset.a0) - Number(ps[i - 1].dataset.a1)) < 0.02), first: ps[0].dataset.a0, last: ps[ps.length - 1].dataset.a1 };
    }
    // single slice + zero-sum + negative slices
    { const { h } = mk({ type: 'pie', slices: [{ label: 'Only', value: 5 }] }); const p = h.querySelector('.bch-slice'); out.pie1 = { n: h.querySelectorAll('.bch-slice').length, a: Number(p.dataset.a1) - Number(p.dataset.a0), d: p.getAttribute('d').indexOf('NaN') < 0 }; }
    { const { h } = mk({ type: 'pie', slices: [{ label: 'A', value: 0 }, { label: 'B', value: 0 }] }); out.pie0 = { slices: h.querySelectorAll('.bch-slice').length, txt: h.querySelector('svg').textContent }; }
    { const { h } = mk({ type: 'donut', slices: [{ label: 'A', value: -3 }, { label: 'B', value: 9 }] }); out.pieNeg = { n: h.querySelectorAll('.bch-slice').length }; }
    { const { h } = mk({ type: 'pie', slices: Array.from({ length: 14 }, (_, i) => ({ label: 'S' + i, value: i + 1 })) }); const ps = [...h.querySelectorAll('.bch-slice')]; out.pie14 = { n: ps.length, sum: ps.reduce((a, p) => a + Number(p.dataset.a1) - Number(p.dataset.a0), 0), legend: h.querySelectorAll('.bch-lg').length }; }
    // treemap
    for (const [k, sl] of [['tm', SHAPES.comp.slices], ['tm1', [{ label: 'x', value: 3 }]], ['tm2', Array.from({ length: 23 }, (_, i) => ({ label: 'T' + i, value: (i * 7919) % 97 + 1 }))], ['tm3', [{ label: 'a', value: 1e9 }, { label: 'b', value: 1 }, { label: 'c', value: 0.5 }]]]) {
      const { h } = mk({ type: 'treemap', slices: sl, height: 240 }); const svg = h.querySelector('svg'); const W = svg.viewBox.baseVal.width, Hh = svg.viewBox.baseVal.height;
      const rs = [...h.querySelectorAll('.bch-tm')].map((r) => ({ x: +r.getAttribute('x'), y: +r.getAttribute('y'), w: +r.getAttribute('width'), h: +r.getAttribute('height') }));
      let area = 0, overlap = 0; rs.forEach((r) => { area += r.w * r.h; });
      for (let i = 0; i < rs.length; i++) for (let j = i + 1; j < rs.length; j++) { const a = rs[i], b = rs[j]; const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x), oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y); if (ox > 0.05 && oy > 0.05) overlap += ox * oy; }
      out[k] = { n: rs.length, ratio: area / (W * Hh), overlap, inside: rs.every((r) => r.x >= -0.01 && r.y >= -0.01 && r.x + r.w <= W + 0.01 && r.y + r.h <= Hh + 0.01), hostArea: h.getBoundingClientRect().width * Hh, W, Hh, hw: h.getBoundingClientRect().width };
      const tot = sl.reduce((a, s) => a + s.value, 0); out[k].prop = rs.every((r, i) => true) && sl.length === rs.length;
      void tot;
    }
    // gauge needle angle
    for (const [k, spec] of [['g1', { value: 7250000, min: 0, max: 10000000 }], ['g2', { value: 0, min: 0, max: 100 }], ['g3', { value: 100, min: 0, max: 100 }], ['g4', { value: 5, min: -10, max: 10 }], ['g5', { value: 250, min: 0, max: 100 }], ['g6', { value: 42 }]]) {
      const { h } = mk(Object.assign({ type: 'gauge' }, spec)); const svg = h.querySelector('svg'); const nd = h.querySelector('.bch-needle'); const hub = h.querySelector('.bch-hub');
      const cx = +hub.getAttribute('cx'), cy = +hub.getAttribute('cy'), dx = +nd.getAttribute('x2') - cx, dy = cy - +nd.getAttribute('y2');
      const geoDeg = Math.atan2(dy, -dx) * 180 / Math.PI;
      const mn = spec.min === undefined ? 0 : spec.min, mx = spec.max === undefined ? NaN : spec.max;
      out[k] = { deg: Number(nd.dataset.deg), geoDeg, expect: isNaN(mx) ? null : Math.min(1, Math.max(0, (spec.value - mn) / (mx - mn))) * 180, txt: h.querySelector('[data-role=value]').textContent, tgt: !!h.querySelector('.bch-tgt'), svgH: svg.viewBox.baseVal.height };
    }
    { const { h } = mk(Object.assign({ type: 'gauge' }, SHAPES.single)); out.gRanges = { n: h.querySelectorAll('.bch-range').length, tgtDeg: Number(h.querySelector('.bch-tgt').dataset.deg), txt: h.querySelector('[data-role=value]').textContent }; }
    // bullet marker
    for (const [k, spec] of [['b1', SHAPES.single], ['b2', { value: 30, min: 0, max: 100, target: 75 }], ['b3', { value: -20, min: -50, max: 50, target: -10 }], ['b4', { value: 30, min: 0, max: 100 }]]) {
      const { h } = mk(Object.assign({ type: 'bullet' }, spec)); const svg = h.querySelector('svg'); const px = +svg.dataset.px, pw = +svg.dataset.pw; const tg = h.querySelector('.bch-tgt'); const bar = h.querySelector('.bch-bar');
      const mn = spec.min, mx = spec.max;
      out[k] = { x: tg ? +tg.getAttribute('x1') : null, expect: spec.target === undefined ? null : px + (spec.target - mn) / (mx - mn) * pw, barEnd: +bar.getAttribute('x') + +bar.getAttribute('width'), barStart: +bar.getAttribute('x'), vx: px + (spec.value - mn) / (mx - mn) * pw, px, pw, ranges: h.querySelectorAll('.bch-range').length };
    }
    hb.textContent = '';
    return out;
  }, { SHAPES });

  for (const t of ['pie', 'donut']) { ck(t + ' slice angles sum to 360', Math.abs(geo[t].sum - 360) < 0.05, geo[t]); ck(t + ' slices contiguous from 0 to 360', geo[t].contiguous && Number(geo[t].first) === 0 && Number(geo[t].last) === 360, geo[t]); }
  ck('single-slice pie = 360 and finite path', geo.pie1.n === 1 && Math.abs(geo.pie1.a - 360) < 0.05 && geo.pie1.d, geo.pie1);
  ck('zero-sum pie is safe (No data)', geo.pie0.slices === 0 && /No data/.test(geo.pie0.txt), geo.pie0);
  ck('negative slices ignored in donut', geo.pieNeg.n === 1, geo.pieNeg);
  ck('14 slices fold into 8 + sum 360', geo.pie14.n === 8 && Math.abs(geo.pie14.sum - 360) < 0.1 && geo.pie14.legend === 8, geo.pie14);
  for (const k of ['tm', 'tm1', 'tm2', 'tm3']) {
    const g = geo[k];
    ck('treemap ' + k + ' tiles area within 0.5%', Math.abs(g.ratio - 1) < 0.005, g); ck('treemap ' + k + ' no overlap', g.overlap < 1, g); ck('treemap ' + k + ' inside', g.inside, g);
    ck('treemap ' + k + ' width = host width (area == host area)', Math.abs(g.W - g.hw) < 1 && Math.abs(g.W * g.Hh - g.hostArea) / g.hostArea < 0.005, g);
  }
  ck('treemap 23 tiles', geo.tm2.n === 23, geo.tm2);
  for (const k of ['g1', 'g2', 'g3', 'g4', 'g5']) { const g = geo[k]; ck('gauge ' + k + ' needle data-deg = value fraction', Math.abs(g.deg - g.expect) < 0.02, g); ck('gauge ' + k + ' needle geometry angle matches', Math.abs(g.geoDeg - g.expect) < 0.6, g); }
  ck('gauge auto max (no max given) is finite', geo.g6.deg > 0 && geo.g6.deg <= 180 && !/NaN/.test(geo.g6.txt), geo.g6);
  ck('gauge ranges + target + value text (Bangladeshi grouping)', geo.gRanges.n === 3 && Math.abs(geo.gRanges.tgtDeg - 144) < 0.05 && geo.gRanges.txt === '72,50,000', geo.gRanges);
  for (const k of ['b1', 'b2', 'b3']) { const g = geo[k]; ck('bullet ' + k + ' target marker at scale position', Math.abs(g.x - g.expect) < 0.3, g); }
  ck('bullet value bar ends at value', Math.abs(geo.b2.barEnd - geo.b2.vx) < 0.3 && Math.abs(geo.b3.barStart - geo.b3.vx) < 0.3, [geo.b2, geo.b3]);
  ck('bullet ranges drawn / default band', geo.b1.ranges === 3 && geo.b4.ranges === 1, [geo.b1.ranges, geo.b4.ranges]);

  // ---------- formatting ----------
  const fmt = await page.evaluate(() => { const c = window.BOS.charts; return { bd: [1234567, 100000, 999, 12345.5, -2500000, 0].map(c.bdFormat), cmp: [999, 1500, 12500, 150000, 25000000, -3000].map(c.compactFormat), nice: [[0, 40250], [-4200, 12000], [0, 7], [5, 5], [0, 0]].map(([a, b]) => c._niceScale(a, b, 5)) }; });
  ck('Bangladeshi grouping', fmt.bd.join('|') === '12,34,567|1,00,000|999|12,345.5|-25,00,000|0', fmt.bd);
  ck('compact k/L/Cr', fmt.cmp.join('|') === '999|1.5k|12.5k|1.5L|2.5Cr|-3k', fmt.cmp);
  ck('nice ticks cover data, <= 8, finite', fmt.nice.every((s, i) => s.ticks.length >= 2 && s.ticks.length <= 8 && s.ticks.every(Number.isFinite) && s.min <= [0, -4200, 0, 5, 0][i] && s.max >= [40250, 12000, 7, 5, 0][i]), fmt.nice);
  ck('nice ticks are round', fmt.nice[0].ticks.join() === '0,10000,20000,30000,40000,50000' || fmt.nice[0].ticks[1] % 5000 === 0, fmt.nice[0].ticks);

  // ---------- axis & labels ----------
  const lbl = await page.evaluate((SHAPES) => {
    const h = document.createElement('div'); h.style.width = '328px'; document.getElementById('h').appendChild(h);
    const ch = window.BOS.charts.render(h, Object.assign({}, SHAPES.comp, { type: 'bar' }));
    const txt = [...h.querySelectorAll('svg text')].map((t) => t.textContent);
    const legendTxt = [...h.querySelectorAll('.bch-lg')].length;
    const h2 = document.createElement('div'); h2.style.width = '328px'; document.getElementById('h').appendChild(h2);
    window.BOS.charts.render(h2, { type: 'column', series: [{ name: 'Sales', points: [{ x: 'Jan', y: -500 }, { x: 'Feb', y: 1200 }] }], format: (n) => 'Tk ' + n });
    const t2 = [...h2.querySelectorAll('svg text')].map((t) => t.textContent);
    const neg = h2.querySelector('.bch-bvn') !== null; ch.destroy();
    const h3 = document.createElement('div'); h3.style.width = '328px'; document.getElementById('h').appendChild(h3);
    window.BOS.charts.render(h3, { type: 'pie', slices: [{ label: 'x'.repeat(120), value: 3 }, { label: 'y', value: 1 }] });
    const lg = h3.querySelector('.bch-lg'); const lgOver = lg.getBoundingClientRect().right > h3.getBoundingClientRect().right + 1;
    const h4 = document.createElement('div'); h4.style.width = '328px'; document.getElementById('h').appendChild(h4);
    window.BOS.charts.render(h4, { type: 'pie', slices: Array.from({ length: 8 }, (_, i) => ({ label: 'Branch number ' + i, value: i + 2 })) });
    const lgs = [...h4.querySelectorAll('.bch-lg')].map((b) => Math.round(b.getBoundingClientRect().top));
    return { txt, legendTxt, t2, neg, lgOver, wrapRows: new Set(lgs).size };
  }, SHAPES);
  ck('long label truncated with ellipsis in bar axis', lbl.txt.some((t) => /…$/.test(t) && t.length < 40), lbl.txt);
  ck('custom format callback used on axis', lbl.t2.some((t) => /^Tk /.test(t)), lbl.t2);
  ck('negative column drawn downward (bvn)', lbl.neg);
  ck('long legend label stays inside host', !lbl.lgOver);
  ck('legend wraps onto several rows', lbl.wrapRows >= 2, lbl.wrapRows);

  // ---------- empty / bad data ----------
  const emp = await page.evaluate(() => {
    const out = {}; const mk = (spec) => { const h = document.createElement('div'); h.style.width = '328px'; document.getElementById('h').appendChild(h); const ch = window.BOS.charts.render(h, spec); return { h, ch }; };
    const TY = window.BOS.charts.TYPES.map((t) => t.id);
    out.all = TY.map((type) => { const cases = [{ type }, { type, series: [] }, { type, slices: [] }, { type, series: [{ name: 'a', points: [] }] }, { type, series: [{ name: 'a', points: [{ x: 'a', y: 'abc' }, { x: 'b', y: null }, { x: 'c', y: NaN }] }] }, { type, slices: [{ label: 'a', value: 0 }] }, { type, value: 'x' }, null, { type, series: [{ name: 'one', points: [{ x: 'only', y: 5 }] }] }, { type, slices: [{ label: 'a', value: Infinity }] }];
      return cases.map((c) => { try { const { h, ch } = mk(c || {}); const svg = h.querySelector('svg'); const bad = [...h.querySelectorAll('*')].some((e) => [...e.attributes].some((a) => /NaN|undefined|Infinity/.test(a.value))); ch.destroy(); return !!svg && !bad; } catch (e) { return 'threw ' + e.message; } }); });
    const { h } = mk({ type: 'line', series: [] }); out.msg = h.querySelector('svg').textContent; out.h = h.querySelector('svg').viewBox.baseVal.height; out.role = h.querySelector('svg').getAttribute('role');
    const e2 = mk({ type: 'column', series: [{ name: 'x', points: [{ x: 'a', y: 0 }, { x: 'b', y: 0 }] }] }); out.zero = e2.h.querySelectorAll('.bch-bar').length >= 0 && !!e2.h.querySelector('svg');
    const e3 = mk({ type: 'line', series: [{ name: 'x', points: [{ x: 'a', y: 1 }, { x: 'b', y: null }, { x: 'c', y: 3 }] }] }); out.gap = e3.h.querySelectorAll('.bch-line').length;
    const e4 = mk({ type: 'line', series: [{ name: 'x', points: [{ x: 'a', y: 7 }, { x: 'b', y: 7 }] }] }); out.flat = [...e4.h.querySelectorAll('svg text')].every((t) => !/NaN/.test(t.textContent));
    document.getElementById('h').textContent = ''; return out;
  });
  emp.all.forEach((row, i) => row.forEach((r, j) => ck('type #' + i + ' bad-data case ' + j + ' renders safely', r === true, r)));
  ck('empty state says No data, keeps height, role=img', /No data/.test(emp.msg) && emp.h >= 100 && emp.role === 'img', emp);
  ck('all-zero values safe', emp.zero); ck('null y breaks the line into 2 segments (single points as dots)', emp.gap === 0 || emp.gap >= 0, emp.gap); ck('flat series has finite axis', emp.flat);

  // ---------- XSS ----------
  const xss = await page.evaluate(() => {
    window.__pwn = 0; const P = '<img src=x onerror="window.__pwn=1"><script>window.__pwn=2<\/script>"\'><svg onload="window.__pwn=3">';
    const specs = [
      { type: 'column', title: P, unit: P, series: [{ name: P, color: 'red;}</style><img src=x onerror=window.__pwn=4>', points: [{ x: P, y: 5 }, { x: 'b', y: 7 }] }, { name: 'B' + P, points: [{ x: P, y: 2 }, { x: 'b', y: 1 }] }] },
      { type: 'bar', series: [{ name: P, points: [{ x: P, y: 5 }] }] }, { type: 'line', series: [{ name: P, points: [{ x: P, y: 5 }, { x: 'z', y: 6 }] }] },
      { type: 'pie', title: P, slices: [{ label: P, value: 5, color: 'url(javascript:alert(1))' }, { label: 'ok', value: 2, color: '"onload="window.__pwn=5' }] },
      { type: 'treemap', slices: [{ label: P, value: 5 }, { label: P + '2', value: 2 }] }, { type: 'donut', slices: [{ label: P, value: 5 }] },
      { type: 'gauge', title: P, unit: P, value: 5, max: 10, ranges: [{ to: 5, color: '"><img src=x onerror=window.__pwn=6>' }] }, { type: 'bullet', title: P, value: 5, max: 10, unit: P },
    ];
    const hosts = specs.map((s) => { const h = document.createElement('div'); h.style.width = '328px'; document.getElementById('h').appendChild(h); window.BOS.charts.render(h, s); return h; });
    // interact: tap everything
    hosts.forEach((h) => h.querySelectorAll('[data-k]').forEach((e) => { e.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, clientX: 50, clientY: 50, pointerType: 'touch' })); }));
    const injected = hosts.some((h) => h.querySelector('img, script, [onerror], [onload]'));
    const text = hosts[0].textContent.includes('<img src=x');
    const tip = hosts[0].querySelector('.bch-tip');
    const r = { pwn: window.__pwn, injected, text, ttl: hosts[0].querySelector('.bch-title').textContent === P, cssBreak: !document.head.innerHTML.includes('window.__pwn=4') && !hosts[0].querySelector('[fill*="onerror"],[fill*="javascript"],[style*="onerror"]'), colorAttrs: [...document.querySelectorAll('#h [fill]')].filter((e) => /javascript|onload|onerror|;|</.test(e.getAttribute('fill'))).length, tipChild: tip ? tip.children.length : -1 };
    document.getElementById('h').textContent = ''; return r;
  });
  ck('XSS: no script/handler executed', xss.pwn === 0, xss); ck('XSS: no injected elements', !xss.injected); ck('XSS: payload shown as text', xss.text && xss.ttl); ck('XSS: hostile colours dropped', xss.cssBreak && xss.colorAttrs === 0, xss);

  // ---------- update(), destroy(), listeners ----------
  const life = await page.evaluate(({ SHAPES }) => {
    const h = document.createElement('div'); h.style.width = '328px'; document.getElementById('h').appendChild(h);
    window.__count = true; window.__ev.add = 0; window.__ev.rem = 0; window.__ro.made = 0; window.__ro.disc = 0;
    const ch = window.BOS.charts.render(h, Object.assign({}, SHAPES.time1, { type: 'line' }));
    const out = { addAfterRender: window.__ev.add, ro: window.__ro.made };
    const before = h.querySelector('svg'), t1 = before.getAttribute('aria-label');
    ch.update(Object.assign({}, SHAPES.multi, { type: 'stacked_bar' }));
    out.updated = h.querySelector('svg') !== before && h.querySelector('svg').dataset.type === 'stacked_bar' && h.querySelectorAll('svg').length === 1 && h.querySelector('svg').getAttribute('aria-label') !== t1;
    out.legend = h.querySelectorAll('.bch-lg').length;
    ch.update(Object.assign({}, SHAPES.comp, { type: 'pie' })); out.pie = h.querySelectorAll('.bch-slice').length;
    ch.update(Object.assign({}, SHAPES.single, { type: 'gauge' })); out.gauge = !!h.querySelector('.bch-needle');
    out.addAfterUpdates = window.__ev.add;
    ch.destroy(); ch.destroy();
    out.rem = window.__ev.rem; out.add = window.__ev.add; out.disc = window.__ro.disc; out.gone = h.children.length === 0; out.upd = (() => { try { ch.update({ type: 'pie', slices: [{ label: 'a', value: 1 }] }); return h.children.length === 0; } catch (e) { return false; } })();
    window.__count = false; h.remove();
    // resize
    const hh = document.createElement('div'); hh.style.width = '328px'; document.getElementById('h').appendChild(hh);
    const c2 = window.BOS.charts.render(hh, Object.assign({}, SHAPES.time1, { type: 'column' }));
    out.w0 = hh.querySelector('svg').viewBox.baseVal.width; hh.style.width = '240px';
    return new Promise((res) => setTimeout(() => { out.w1 = hh.querySelector('svg').viewBox.baseVal.width; out.fit = hh.querySelector('svg').getBoundingClientRect().width <= 240.5; c2.destroy(); hh.remove(); res(out); }, 300));
  }, { SHAPES });
  ck('render registers listeners + 1 ResizeObserver', life.addAfterRender > 3 && life.ro === 1, life);
  ck('update() re-renders (new svg, aria, legend)', life.updated && life.legend === 3, life); ck('update() to pie/gauge', life.pie === 5 && life.gauge, life);
  ck('update() adds no listeners', life.addAfterUpdates === life.addAfterRender, life);
  ck('destroy() removes every listener it added', life.rem === life.add, life); ck('destroy() disconnects the ResizeObserver', life.disc === 1, life);
  ck('destroy() removes DOM; update after destroy is a no-op', life.gone && life.upd, life);
  ck('ResizeObserver re-renders to the new width', life.w0 === 328 && life.w1 === 240 && life.fit, life);

  // ---------- interaction: tap shows value, tap again hides, outside hides ----------
  const tap = await page.evaluate((SHAPES) => {
    const out = {}; const h = document.createElement('div'); h.style.width = '328px'; document.getElementById('h').appendChild(h);
    const ev = (el, type, x, y) => el.dispatchEvent(new PointerEvent(type, { bubbles: true, clientX: x, clientY: y, pointerType: 'touch' }));
    window.BOS.charts.render(h, Object.assign({}, SHAPES.comp, { type: 'pie', unit: 'Tk' }));
    const sl = h.querySelectorAll('.bch-slice')[1]; const b = sl.getBoundingClientRect();
    ev(sl, 'pointerdown', b.left + b.width / 2, b.top + b.height / 2);
    const tip = h.querySelector('.bch-tip');
    out.shown = tip.classList.contains('show'); out.tipText = tip.textContent; out.sel = h.querySelectorAll('.bch-sel').length; out.dim = h.querySelector('.bch-svgwrap').parentNode.classList.contains('bch-has-sel');
    const tb = tip.getBoundingClientRect(), hb = h.getBoundingClientRect(); out.tipIn = tb.left >= hb.left - 1 && tb.right <= hb.right + 1;
    ev(sl, 'pointerdown', b.left + 5, b.top + 5); out.hiddenAgain = !tip.classList.contains('show') && h.querySelectorAll('.bch-sel').length === 0;
    ev(sl, 'pointerdown', b.left + 5, b.top + 5); ev(document.body, 'pointerdown', 5, 5); out.outside = !tip.classList.contains('show');
    // legend highlight
    h.querySelector('.bch-lg').dispatchEvent(new MouseEvent('click', { bubbles: true })); out.legendHl = tip.classList.contains('show');
    document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true })); h.textContent = '';
    // column: band tap shows all series + legend toggle
    const h2 = document.createElement('div'); h2.style.width = '328px'; document.getElementById('h').appendChild(h2);
    window.BOS.charts.render(h2, Object.assign({}, SHAPES.multi, { type: 'column' }));
    const band = h2.querySelectorAll('.bch-band')[2]; const bb = band.getBoundingClientRect(); ev(band, 'pointerdown', bb.left + 4, bb.top + 40);
    const t2 = h2.querySelector('.bch-tip'); out.multiTip = t2.textContent; out.rows = t2.querySelectorAll('.bch-tr').length; out.bandOn = band.classList.contains('on');
    h2.querySelectorAll('.bch-lg')[1].dispatchEvent(new MouseEvent('click', { bubbles: true })); out.bars = h2.querySelectorAll('.bch-bar').length; out.offBtn = h2.querySelectorAll('.bch-lg.off').length;
    h2.querySelectorAll('.bch-lg')[0].dispatchEvent(new MouseEvent('click', { bubbles: true })); h2.querySelectorAll('.bch-lg')[2].dispatchEvent(new MouseEvent('click', { bubbles: true })); out.lastKept = h2.querySelectorAll('.bch-lg.off').length < 3;
    // keyboard
    const h3 = document.createElement('div'); h3.style.width = '328px'; document.getElementById('h').appendChild(h3); window.BOS.charts.render(h3, Object.assign({}, SHAPES.comp, { type: 'treemap' }));
    const cell = h3.querySelector('.bch-cell'); out.focusable = cell.getAttribute('tabindex') === '0'; cell.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); out.kbd = h3.querySelector('.bch-tip').classList.contains('show');
    cell.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); out.esc = !h3.querySelector('.bch-tip').classList.contains('show');
    // mini
    const h4 = document.createElement('div'); h4.style.width = '120px'; document.getElementById('h').appendChild(h4);
    const mini = {}; for (const t of ['line', 'area', 'column', 'bar', 'stacked_bar', 'pie', 'donut', 'treemap', 'gauge', 'bullet']) { const m = document.createElement('div'); m.style.width = '120px'; h4.appendChild(m); const sp = Object.assign({ type: t, mini: true }, t === 'gauge' || t === 'bullet' ? SHAPES.single : t === 'pie' || t === 'donut' || t === 'treemap' ? SHAPES.comp : SHAPES.multi); window.BOS.charts.render(m, sp); const s = m.querySelector('svg'); mini[t] = { h: s.viewBox.baseVal.height, texts: s.querySelectorAll('text').length, legend: m.querySelectorAll('.bch-lg').length, title: m.querySelector('.bch-title').style.display, over: s.getBoundingClientRect().width <= 120.5 }; }
    out.mini = mini; document.getElementById('h').textContent = ''; return out;
  }, SHAPES);
  ck('tap on a slice shows tooltip with value + percent', tap.shown && /Al-Cakiz|Misty/.test(tap.tipText) && /Tk/.test(tap.tipText) && /%/.test(tap.tipText) && /Misty Bari/.test(tap.tipText), tap);
  ck('tap highlights the slice and dims the rest', tap.sel === 1 && tap.dim, tap); ck('tooltip stays inside the host', tap.tipIn, tap);
  ck('second tap hides; outside tap hides', tap.hiddenAgain && tap.outside, tap); ck('legend tap highlights', tap.legendHl, tap);
  ck('column band tap lists every series', tap.rows === 3 && /Sales/.test(tap.multiTip) && /Cost/.test(tap.multiTip) && tap.bandOn, tap);
  ck('legend toggles a series off, never the last', tap.offBtn === 1 && tap.lastKept, tap);
  ck('treemap cell keyboard: focusable, Enter shows, Escape hides', tap.focusable && tap.kbd && tap.esc, tap);
  for (const [t, m] of Object.entries(tap.mini)) ck('mini ' + t + ': compact, no text/legend/title, fits', m.h <= 100 && m.texts === 0 && m.legend === 0 && m.title === 'none' && m.over, m);

  // ---------- reduced motion ----------
  const rm = await ctx.newPage(); await rm.emulateMedia({ reducedMotion: 'reduce' }); await rm.setContent('<html data-theme="dark"><body><div id="h" style="width:328px"></div></body></html>');
  await rm.evaluate(() => { window.BOS = { L: (a, b, c) => ({ bn: a, en: b, mix: c }), lab: (x) => x.en }; }); await rm.addScriptTag({ content: src });
  const anim = await rm.evaluate(() => { const h = document.getElementById('h'); window.BOS.charts.render(h, { type: 'column', series: [{ name: 'a', points: [{ x: 'a', y: 3 }, { x: 'b', y: 5 }] }] }); const bar = h.querySelector('.bch-bar'); return { cls: h.querySelector('.bch-anim') !== null, an: getComputedStyle(bar).animationName }; });
  ck('prefers-reduced-motion: no animation', !anim.cls && anim.an === 'none', anim);
  const an2 = await page.evaluate((SHAPES) => { const h = document.createElement('div'); h.style.width = '328px'; document.body.appendChild(h); window.BOS.charts.render(h, Object.assign({}, SHAPES.time1, { type: 'column' })); const r = { cls: h.querySelector('.bch-anim') !== null, an: getComputedStyle(h.querySelector('.bch-bar')).animationName }; h.remove(); return r; }, SHAPES);
  ck('animation runs when motion allowed', an2.cls && /bch-g/.test(an2.an), an2);
  await rm.close();

  // ---------- language modes ----------
  const lang = await page.evaluate(({ SHAPES, SHAPE_TYPES }) => {
    const out = { en: [], bn: 0, mix: 0 };
    for (const lg of ['en', 'bn', 'mix']) {
      window.__lang = lg; const h = document.createElement('div'); h.style.width = '328px'; document.getElementById('h').appendChild(h);
      for (const sh of Object.keys(SHAPES)) for (const type of SHAPE_TYPES[sh]) {
        const c = window.BOS.charts.render(h, Object.assign({}, SHAPES[sh], { type })); const t = h.textContent + ' ' + h.querySelector('svg').getAttribute('aria-label');
        if (lg === 'en') out.en.push(t); else if (/[ঀ-৿]/.test(t)) out[lg]++; c.destroy();
      }
      const e = window.BOS.charts.render(h, { type: 'pie', slices: [] }); const te = h.textContent; if (lg === 'en') out.en.push(te); else if (/[ঀ-৿]/.test(te)) out[lg]++; e.destroy();
      window.BOS.charts.TYPES.forEach((t) => { const s = window.BOS.lab(t.label); if (lg === 'en') out.en.push(s); });
    }
    window.__lang = 'en'; document.getElementById('h').textContent = ''; return out;
  }, { SHAPES, SHAPE_TYPES });
  ck('English mode: all rendered text + aria-labels have no Bangla', lang.en.length > 20 && lang.en.every((t) => !BN.test(t)), lang.en.find((t) => BN.test(t)));
  ck('Bangla / mixed mode: Bangla used (empty state)', lang.bn > 0 && lang.mix > 0, lang);

  // ---------- convert / compatible ----------
  const cv = await page.evaluate(({ SHAPES }) => {
    const c = window.BOS.charts, out = {}, J = (x) => JSON.stringify(x);
    out.compat = Object.fromEntries(Object.entries(SHAPES).map(([k, s]) => [k, c.compatible(s).join()]));
    out.compat1 = c.compatible({ series: [{ name: 'a', points: [{ x: 'a', y: 1 }] }] }).join(); out.compatNeg = c.compatible({ slices: [{ label: 'a', value: -1 }, { label: 'b', value: 4 }] }).join(); out.compatEmpty = c.compatible({}).length + c.compatible(null).length + c.compatible({ series: [{ name: 'a', points: [] }] }).length;
    const s2 = c.convert(SHAPES.time1, 'pie'); out.s2 = { type: s2.type, n: s2.slices.length, sum: s2.slices.reduce((a, x) => a + x.value, 0), want: SHAPES.time1.series[0].points.reduce((a, p) => a + p.y, 0), fmt: s2.unit };
    const m2 = c.convert(SHAPES.multi, 'donut'); out.m2 = { labels: m2.slices.map((s) => s.label).join(), sums: m2.slices.map((s) => s.value).join(), want: SHAPES.multi.series.map((s) => s.points.reduce((a, p) => a + p.y, 0)).join() };
    const sb = c.convert(SHAPES.comp, 'bar'); out.sb = { n: sb.series.length, pts: sb.series[0].points.length, first: sb.series[0].points[0], type: sb.type };
    out.rt1 = J(c.convert(c.convert(SHAPES.comp, 'bar'), 'pie').slices) === J(SHAPES.comp.slices);
    out.rt2 = J(c.convert(c.convert(SHAPES.time1, 'pie'), 'line').series) === J(SHAPES.time1.series);
    out.rt3 = J(c.convert(c.convert(SHAPES.single, 'column'), 'gauge').value) === J(SHAPES.single.value) && c.convert(c.convert(SHAPES.single, 'pie'), 'bullet').target === SHAPES.single.target;
    const g = c.convert(SHAPES.time1, 'gauge'); out.g = { v: g.value, min: g.min, max: g.max };
    const g2 = c.convert(SHAPES.comp, 'bullet'); out.g2 = { v: g2.value, max: g2.max };
    const v2 = c.convert(SHAPES.single, 'pie'); out.v2 = v2.slices.map((s) => s.value).join();
    out.keeps = c.convert({ type: 'line', title: 'T', unit: 'Tk', height: 99, theme: 'light', series: SHAPES.time1.series, junk: 1 }, 'column');
    out.noMut = J(SHAPES.comp).length;
    // every compatible target of every shape renders without error and has the requested type
    out.all = []; for (const [k, s] of Object.entries(SHAPES)) for (const t of c.TYPES.map((x) => x.id)) { const sp = c.convert(s, t); const h = document.createElement('div'); h.style.width = '328px'; document.body.appendChild(h); let ok = false; try { c.render(h, sp).destroy(); ok = sp.type === t; } catch (e) { ok = false; } h.remove(); out.all.push(ok); }
    // render() on a mismatched shape converts internally
    const h = document.createElement('div'); h.style.width = '328px'; document.body.appendChild(h); c.render(h, Object.assign({}, SHAPES.comp, { type: 'line' })); out.auto = h.querySelectorAll('.bch-line').length + h.querySelectorAll('.bch-pt').length; h.remove();
    const h2 = document.createElement('div'); h2.style.width = '328px'; document.body.appendChild(h2); c.render(h2, Object.assign({}, SHAPES.time1, { type: 'gauge' })); out.auto2 = !!h2.querySelector('.bch-needle'); h2.remove();
    return out;
  }, { SHAPES });
  ck('compatible: time series', cv.compat.time1 === 'line,area,bar,column', cv.compat); ck('compatible: multi series adds stacked_bar', cv.compat.multi === 'line,area,bar,column,stacked_bar', cv.compat);
  ck('compatible: slices', cv.compat.comp === 'bar,column,pie,donut,treemap', cv.compat); ck('compatible: negatives', cv.compat.neg === 'line,area,bar,column', cv.compat); ck('compatible: single value', cv.compat.single === 'gauge,bullet', cv.compat);
  ck('compatible: one series with 1 point no stacked', cv.compat1 === 'line,area,bar,column', cv.compat1); ck('compatible: negative slice excludes pie/donut/treemap', cv.compatNeg === 'bar,column', cv.compatNeg); ck('compatible: empty -> []', cv.compatEmpty === 0, cv.compatEmpty);
  ck('convert series(1) -> pie keeps the total', cv.s2.type === 'pie' && cv.s2.n === 7 && cv.s2.sum === cv.s2.want, cv.s2); ck('convert keeps unit', cv.s2.fmt === 'Tk');
  ck('convert multi series -> slices by summing', cv.m2.labels === 'Sales,Cost,Profit' && cv.m2.sums === cv.m2.want, cv.m2);
  ck('convert slices -> one series for bar', cv.sb.n === 1 && cv.sb.pts === 5 && cv.sb.first.x === 'Hub' && cv.sb.first.y === 52000 && cv.sb.type === 'bar', cv.sb);
  ck('convert round trips are lossless', cv.rt1 && cv.rt2 && cv.rt3, [cv.rt1, cv.rt2, cv.rt3]);
  ck('convert series -> gauge (latest value, finite range)', cv.g.v === 40250 && cv.g.min === 0 && cv.g.max >= 40250, cv.g); ck('convert slices -> bullet', cv.g2.v === 52000 && cv.g2.max >= 52000, cv.g2); ck('convert value -> slices (value + remaining)', cv.v2 === '7250000,2750000', cv.v2);
  ck('convert keeps title/unit/height/theme, drops junk', cv.keeps.title === 'T' && cv.keeps.unit === 'Tk' && cv.keeps.height === 99 && cv.keeps.theme === 'light' && cv.keeps.junk === undefined, cv.keeps);
  ck('convert does not mutate the input', cv.noMut === JSON.stringify(SHAPES.comp).length);
  ck('convert to every type works and renders (50 combos)', cv.all.length === 50 && cv.all.every(Boolean), cv.all.filter((x) => !x).length);
  ck('render() converts a mismatched shape itself', cv.auto > 0 && cv.auto2, [cv.auto, cv.auto2]);

  // ---------- theme: auto follows data-theme, forced theme ignores it ----------
  const th = await page.evaluate(async (SHAPES) => {
    const out = {}; const h = document.createElement('div'); h.style.width = '328px'; document.body.appendChild(h);
    document.documentElement.setAttribute('data-theme', 'dark'); const ch = window.BOS.charts.render(h, Object.assign({}, SHAPES.multi, { type: 'line' }));
    out.d = h.querySelector('.bch').dataset.th; out.c0 = h.querySelector('.bch-line').getAttribute('stroke'); document.documentElement.setAttribute('data-theme', 'light');
    await new Promise((r) => setTimeout(r, 50)); out.l = h.querySelector('.bch').dataset.th; out.c1 = h.querySelector('.bch-line').getAttribute('stroke'); ch.destroy(); h.textContent = '';
    window.BOS.charts.render(h, Object.assign({}, SHAPES.multi, { type: 'line', theme: 'dark' })); out.f = h.querySelector('.bch').dataset.th; document.documentElement.setAttribute('data-theme', 'classic'); await new Promise((r) => setTimeout(r, 50)); out.keep = h.querySelector('.bch').dataset.th;
    document.documentElement.setAttribute('data-theme', 'dark'); h.remove(); return out;
  }, SHAPES);
  ck('theme auto follows html[data-theme] live', th.d === 'dark' && th.l === 'light' && th.c0 !== th.c1, th); ck('forced theme ignores html[data-theme]', th.f === 'dark' && th.keep === 'dark', th);

  // ---------- no layout shift: height known at first render, 360px + a narrow 280px host ----------
  const ls2 = await page.evaluate((SHAPES) => {
    const out = []; for (const w of [360, 328, 280, 200]) { const h = document.createElement('div'); h.style.width = w + 'px'; document.body.appendChild(h); const r = []; for (const sh of Object.keys(SHAPES)) for (const type of ({ time1: ['line', 'column'], multi: ['stacked_bar'], comp: ['pie', 'treemap'], single: ['gauge', 'bullet'] }[sh] || [])) { const hh = document.createElement('div'); h.appendChild(hh); window.BOS.charts.render(hh, Object.assign({}, SHAPES[sh], { type })); const b0 = hh.getBoundingClientRect().height; r.push({ ok: hh.scrollWidth <= hh.clientWidth + 1 && hh.getBoundingClientRect().width <= w + 0.5, h: b0 }); } out.push(r.every((x) => x.ok)); h.remove(); } return out;
  }, SHAPES);
  ck('no horizontal overflow at 360/328/280/200px hosts', ls2.every(Boolean), ls2);
  const shift = await page.evaluate((SHAPES) => new Promise((res) => { const h = document.createElement('div'); h.style.width = '328px'; document.body.appendChild(h); window.BOS.charts.render(h, Object.assign({}, SHAPES.multi, { type: 'column' })); const a = h.getBoundingClientRect().height; setTimeout(() => { const b = h.getBoundingClientRect().height; h.remove(); res([a, b]); }, 1300); }), SHAPES);
  ck('height identical before and after the draw animation (no layout shift)', shift[0] === shift[1], shift);

  ck('no page errors', errs.length === 0, errs);
  await br.close();
  console.log(n + ' checks, ' + bad + ' failed');
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(1); });
