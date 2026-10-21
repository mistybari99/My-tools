// Desktop layout suite (docs/DESKTOP_LAYOUT.md section 5). Mocked Supabase stub only, no live backend, no demo data.
// desktop.css is not linked from index.html yet (plan step 5), so the test injects web/desktop.css itself.
// PENDING checks (only when index.html does not link desktop.css) print "PEND" and are not failures.
const _P = require('./_paths');
const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2] || _P.TESTS_DIR, ROOT = process.env.WEBROOT || _P.WEB_DIR;
const LINKED = process.env.DESK_LINKED ? process.env.DESK_LINKED === '1' : fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8').includes('href="desktop.css"');   // linked in index.html (plan step 5): the pending checks run for real
const CSS = fs.readFileSync(path.join(ROOT, 'desktop.css'), 'utf8');
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const data = dataFn(fs);
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(PORT);

// key elements whose computed style is snapshotted (phone must be identical with and without desktop.css)
const KEYS = { app: '#app', header: 'header.top', h1: 'header.top h1', hamburger: 'header.top [data-act=nav_open]', drawer: '.drawer', scrim: '.scrim', bnav: '.bnav', toast: '#toast', body: 'body' };
const PROPS = ['display', 'position', 'width', 'maxWidth', 'minWidth', 'marginLeft', 'marginRight', 'marginTop', 'marginBottom', 'paddingLeft', 'paddingRight', 'paddingTop', 'paddingBottom', 'transform', 'visibility', 'left', 'right', 'bottom', 'top', 'flexWrap', 'overflowX', 'zIndex', 'boxShadow', 'borderInlineEndWidth'];
const snapshot = (p) => p.evaluate(([keys, props]) => { const o = {}; for (const [k, sel] of Object.entries(keys)) { const e = document.querySelector(sel); if (!e) { o[k] = null; continue; } const cs = getComputedStyle(e); o[k] = {}; props.forEach((pr) => { o[k][pr] = cs[pr]; }); const r = e.getBoundingClientRect(); o[k].rect = [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)]; } return o; }, [KEYS, PROPS]);

(async () => {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; let ok = 0, bad = 0, pend = 0;
  const chk = (n, c) => { if (c) ok++; else bad++; console.log((c ? 'PASS ' : 'FAIL ') + n); };
  const pending = (n, c, note) => { if (LINKED) return chk(n, c); pend++; console.log('PEND ' + n + ' (needs ' + note + (c ? '; would pass now' : '') + ')'); };
  const NAVJS = 'nav.js adding body.desk-sb', LINK = 'index.html <link rel="stylesheet" href="desktop.css"> after theme_glass.css';
  async function open(w, h, withCss, route) {
    const ctx = await br.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push(e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};try{localStorage.setItem('bos_lang','en')}catch(e){}`);
    await p.goto('http://localhost:' + PORT + '/#/' + (route || 'home')); await p.waitForTimeout(1300);
    if (withCss && !LINKED) await p.addStyleTag({ content: CSS });
    if (!withCss && LINKED) await p.evaluate(() => document.querySelectorAll('link[href$="desktop.css"]').forEach((l) => l.remove()));
    await p.waitForTimeout(250);
    return { p, ctx };
  }
  const noOverflow = (p) => p.evaluate(() => document.documentElement.scrollWidth <= innerWidth);
  const vis = (p, sel) => p.evaluate((s) => { const e = document.querySelector(s); if (!e) return false; const cs = getComputedStyle(e), r = e.getBoundingClientRect(); return cs.display !== 'none' && cs.visibility !== 'hidden' && r.width > 0 && r.right > 0 && r.left < innerWidth; }, sel);

  // 0. static guards on the file
  chk('desktop.css has no rule outside a media block', (() => { let d = 0, top = ''; for (const ch of CSS.replace(/\/\*[\s\S]*?\*\//g, '')) { if (ch === '{') { if (d === 0 && !/^\s*@media/.test(top)) return false; d++; if (d === 1) top = ''; } else if (ch === '}') d--; else if (d === 0) top += ch; } return true; })());
  chk('desktop.css under 12 KB', CSS.length < 12 * 1024);
  chk('desktop.css has no !important beyond .bnav/.scrim', (CSS.replace(/\/\*[\s\S]*?\*\//g, '').match(/!important/g) || []).length === 2);

  // 1. phone 360 and 599: identical computed style with and without desktop.css
  for (const w of [360, 599]) {
    const a = await open(w, 740, false); const base = await snapshot(a.p); const bo = await noOverflow(a.p); await a.ctx.close();
    const b = await open(w, 740, true); const withCss = await snapshot(b.p); const wo = await noOverflow(b.p); await b.ctx.close();
    chk(w + ': home has header and bottom bar', !!base.header && !!base.app);
    chk(w + ': computed styles of key elements unchanged by desktop.css', JSON.stringify(base) === JSON.stringify(withCss));
    chk(w + ': no horizontal overflow (without and with css)', bo && wo);
    chk(w + ': #app width <= 640 (phone column)', base.app.rect[2] <= 640);
  }
  { const a = await open(360, 740, true); chk('360: hamburger visible', await vis(a.p, 'header.top [data-act=nav_open]')); chk('360: drawer closed by default', !(await vis(a.p, '.drawer'))); await a.ctx.close(); }

  // 2. tablet 768: phone shell kept, no horizontal overflow
  { const a = await open(768, 1024, true); chk('768: no horizontal overflow', await noOverflow(a.p)); chk('768: no persistent sidebar', !(await vis(a.p, '.drawer'))); chk('768: hamburger visible', await vis(a.p, 'header.top [data-act=nav_open]')); await a.ctx.close(); }

  // 3. desktop 1024 and 1440
  for (const w of [1024, 1440]) {
    const { p, ctx } = await open(w, w === 1024 ? 768 : 900, true);
    chk(w + ': no horizontal overflow', await noOverflow(p));
    const s = await snapshot(p);
    chk(w + ': #app wider than the 640 phone column', s.app.rect[2] > 640);
    chk(w + ': header spans the full #app width', Math.abs(s.header.rect[2] - s.app.rect[2]) <= 1);
    chk(w + ': header is a single row (no wrap)', s.header.flexWrap === 'nowrap');
    chk(w + ': content blocks capped to --ct-w', await p.evaluate((vw) => { const lim = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--ct-w')); return [...document.querySelectorAll('#app > :not(header.top)')].every((e) => e.getBoundingClientRect().width <= lim + 1); }, w));
    chk(w + ': focus-visible ring is 2px solid', await (async () => { await p.evaluate(() => { const b = document.createElement('button'); b.id = 't_fb'; b.textContent = 'x'; document.querySelector('#app').appendChild(b); }); await p.keyboard.press('Tab'); const r = await p.evaluate(() => { const b = document.querySelector('#t_fb'); b.focus({ focusVisible: true }); const cs = getComputedStyle(b); const o = [cs.outlineStyle, cs.outlineWidth]; b.remove(); return o; }); return r[0] === 'solid' && r[1] === '2px'; })());
    chk(w + ': --sb-w variable', await p.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--sb-w').trim()) === (w === 1024 ? '264px' : '288px'));
    // table full width
    await p.evaluate(() => { const t = document.createElement('table'); t.className = 'bz'; t.innerHTML = '<tbody><tr><td>test_row</td></tr></tbody>'; document.querySelector('#app').appendChild(t); });
    chk(w + ': table.bz fills its container', await p.evaluate(() => { const t = document.querySelector('#app table.bz'); const a = document.querySelector('#app'); return t.getBoundingClientRect().width >= Math.min(a.getBoundingClientRect().width, parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--ct-w'))) - 70; }));
    // sheet is a centred dialog
    await p.evaluate(() => { document.body.insertAdjacentHTML('beforeend', '<div class="sheet-bg" id="t_sb"><div class="sheet" id="t_sh"><p>test_sheet</p></div></div>'); });
    chk(w + ': sheet is centred dialog, not bottom aligned', await p.evaluate(() => { const r = document.querySelector('#t_sh').getBoundingClientRect(); return r.bottom < innerHeight - 20 && r.width <= 720.5 && Math.abs((r.left + r.right) / 2 - innerWidth / 2) < 2; }));
    await p.evaluate(() => document.querySelector('#t_sb').remove());
    // forced phone escape hatch
    await p.evaluate(() => document.documentElement.setAttribute('data-layout', 'phone')); await p.waitForTimeout(150);
    const f = await snapshot(p); chk(w + ': data-layout=phone restores the 640 phone column', f.app.rect[2] <= 640 && f.header.flexWrap === 'wrap');
    await p.evaluate(() => document.documentElement.removeAttribute('data-layout'));
    // pending: parts that need nav.js / index.html
    pending(w + ': sidebar (.drawer) visible without clicking', await vis(p, '.drawer'), NAVJS);
    pending(w + ': bottom bar hidden', !(await vis(p, '.bnav')), NAVJS);
    pending(w + ': hamburger hidden', !(await vis(p, 'header.top [data-act=nav_open]')), NAVJS);
    pending(w + ': #app starts after the sidebar', await p.evaluate(() => { const d = document.querySelector('.drawer'), a = document.querySelector('#app'); return !!d && a.getBoundingClientRect().left >= d.getBoundingClientRect().right - 1; }), NAVJS);
    pending(w + ': desktop.css is linked in index.html', await p.evaluate(() => !!document.querySelector('link[href$="desktop.css"]')), LINK);
    await ctx.close();
  }
  // 4. per-pattern desktop assertions (docs/DESKTOP_LAYOUT.md 2.5, 3.1): body[data-pat] from ia.js; no overflow; table full width with a sticky header;
  //    form and list widths; dashboard four-column grid; POS items left and a sticky pay panel right. Test rows are injected, the mocked data may be empty.
  const PATS = [['pos', 'pos'], ['daybook', 'table'], ['items/new', 'form'], ['customers', 'list'], ['home', 'dash'], ['settings', 'set']];
  for (const w of [1024, 1440]) for (const [route, pat] of PATS) {
    const { p, ctx } = await open(w, 900, true, route);
    const tag = w + ' ' + route + ': ';
    chk(tag + 'body[data-pat] is ' + pat, await p.evaluate((x) => document.body.dataset.pat === x, pat));
    chk(tag + 'no horizontal overflow', await noOverflow(p));
    const lim = { form: w === 1024 ? 760 : 880, list: 960, set: w === 1024 ? 880 : 1040 }[pat];
    if (lim) chk(tag + 'content blocks at most ' + lim + 'px wide', await p.evaluate((l) => [...document.querySelectorAll('#app > :not(header.top):not(nav.crumb)')].every((e) => e.getBoundingClientRect().width <= l + 1), lim));
    if (pat === 'table') {
      await p.evaluate(() => { const t = document.createElement('table'); t.className = 'bz'; t.id = 't_tbl'; t.innerHTML = '<thead><tr><th>test_h1</th><th>test_h2</th></tr></thead><tbody><tr><td>test_c1</td><td>test_c2</td></tr></tbody>'; document.querySelector('#app').appendChild(t); });
      chk(tag + 'bare table fills the content area (same gutters, no overflow)', await p.evaluate(() => { const t = document.querySelector('#t_tbl').getBoundingClientRect(), a = document.querySelector('#app').getBoundingClientRect(); return Math.abs((t.left - a.left) - 32) <= 2 && Math.abs(a.right - t.right - 32) <= 2; }));
      chk(tag + 'bare table does not overflow the page', await noOverflow(p));
      chk(tag + 'table header cells are sticky', await p.evaluate(() => getComputedStyle(document.querySelector('#t_tbl th')).position === 'sticky'));
      await p.evaluate(() => { const d = document.createElement('div'); d.id = 't_wrap'; d.innerHTML = '<table class="bz"><tbody><tr><td>test_w</td></tr></tbody></table>'; document.querySelector('#app').appendChild(d); });
      chk(tag + 'table.bz inside a wrapper fills the wrapper', await p.evaluate(() => { const t = document.querySelector('#t_wrap table').getBoundingClientRect(), d = document.querySelector('#t_wrap').getBoundingClientRect(); return Math.abs(t.width - d.width) <= 1; }));
    }
    if (pat === 'dash') {
      await p.evaluate(() => { const d = document.createElement('div'); d.className = 'stats'; d.id = 't_stats'; d.innerHTML = '<div>a</div><div>b</div><div>c</div><div>d</div>'; document.querySelector('#app').appendChild(d); });
      chk(tag + 'stat tiles four to a row', await p.evaluate(() => getComputedStyle(document.querySelector('#t_stats')).gridTemplateColumns.split(' ').length === 4));
    }
    if (pat === 'pos') {
      chk(tag + 'POS pay panel sits in a second column beside the items', await p.evaluate(() => { const bar = document.querySelector('#pos_bar'), g = document.querySelector('#pos_items'); if (!bar || !g) return false; return bar.getBoundingClientRect().left >= g.getBoundingClientRect().right - 1 && getComputedStyle(bar).position === 'sticky'; }));
      chk(tag + 'POS pay panel is not viewport-fixed', await p.evaluate(() => getComputedStyle(document.querySelector('#pos_bar')).position !== 'fixed'));
    }
    await ctx.close();
  }
  chk('no page errors', errors.length === 0); if (errors.length) console.log(errors.slice(0, 5));
  console.log('RESULT ' + ok + ' passed, ' + bad + ' failed, ' + pend + ' pending' + (LINKED ? ' (DESK_LINKED=1)' : ''));
  await br.close(); srv.close(); process.exit(bad ? 1 : 0);
})();
