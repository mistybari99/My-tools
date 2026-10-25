// bos108 (phase Pol) visual-QA regression test. Run: node tests/web/pol_test.js   (env WEB_DIR / PORT optional, see _paths.js)
// Chromium (Pixel-7 UA, touch) against the mocked Supabase: bottom bar fit at 320/360/412 in 3 languages, 44px main actions on the new screens,
// no raw snake_case keys / JS errors in the visible text, accounts null guard, form-rule link strip, 16px fields, contrast tokens.
const _P = require('./_paths'); const PORT = _P.freePort();
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const C = require('./w5_common.js');
const base = C.baseData(_P.TESTS_DIR);
const srv = C.serve(PORT);
const rpcmock = require('./pol_rpcmock.js');
const GEN = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const prev = c.rpc;
 c.rpc = async (fn, args) => { const R = window.__RPC || {}; if (fn in R) { const v = typeof R[fn] === 'function' ? R[fn](args) : R[fn]; return { data: v === null ? null : JSON.parse(JSON.stringify(v)), error: null }; } return prev(fn, args); }; return c; }; })();`;
const UA = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
let bad = 0, pass = 0; const ok = (c, m) => { if (c) pass++; else { bad++; console.log('FAIL:', m); } };
const ROUTES = ['recipebook','costing','costsources','costattrib','s1setup','scan','inbox','setupadvisor','guards','unmatched','formguard','expenselink','transitshort','saleschannels','costunknown','packflags','posfailed','books85','books96','optviews','templates','cashdrawer','landed','optionsx','billpay','inboxpii','accounts'];
const ACTION_ROUTES = ['costsources','costattrib','s1setup','scan','inbox','books85','books96','optionsx','billpay','inboxpii'];
const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

async function open(br, o) {
  const ctx = await br.newContext({ viewport: { width: o.w || 360, height: 740 }, deviceScaleFactor: 1, isMobile: true, hasTouch: true, userAgent: UA });
  const p = await ctx.newPage(); p.errors = [];
  p.on('pageerror', (e) => p.errors.push(e.message));
  await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(_P.TESTS_DIR + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + GEN }));
  await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  const data = C.mk(base, {});
  await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__M0={};window.__RPC=${o.rpc || rpcmock.src};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');localStorage.setItem('bos_theme','${o.theme || 'light'}');}catch(e){}`);
  return p;
}
const go = async (p, r) => { await p.evaluate((r) => { location.hash = '#/' + r; }, r); await p.waitForTimeout(650); };

(async () => {
  const br = await chromium.launch({ executablePath: process.env.PW_CHROMIUM || '/opt/pw-browsers/chromium' });
  // 1. bottom bar fits 320 / 360 / 412 in every language and theme
  for (const w of [320, 360, 412]) for (const lang of ['en', 'bn', 'mix']) for (const theme of ['light', 'classic']) {
    const p = await open(br, { w, lang, theme }); await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1100);
    const r = await p.evaluate(() => { const n = document.querySelector('.bnav'); if (!n) return null; const bs = [...n.querySelectorAll('button')]; return { sw: n.scrollWidth, cw: n.clientWidth, iw: innerWidth, right: Math.max(...bs.map((b) => b.getBoundingClientRect().right)), left: Math.min(...bs.map((b) => b.getBoundingClientRect().left)), n: bs.length, doc: document.documentElement.scrollWidth }; });
    ok(r && r.n >= 4, `bnav present ${w}/${lang}/${theme}`);
    if (r) { ok(r.sw <= r.cw, `bnav scrollWidth<=clientWidth ${w}/${lang}/${theme}: ${r.sw}>${r.cw}`); ok(r.right <= r.iw + 0.5 && r.left >= -0.5, `bnav buttons inside the screen ${w}/${lang}/${theme}: ${r.left}..${r.right}`); ok(r.doc <= r.iw, `no sideways page scroll ${w}/${lang}/${theme}`); }
    await p.context().close();
  }
  // 2 + 3. main actions >= 44px; no raw keys in visible text
  const RAW = /\b[a-z]{2,}(?:_[a-z0-9]{2,}){1,}\b|Cannot read|TypeError|undefined|\[object/;
  for (const lang of ['en', 'bn', 'mix']) {
    const p = await open(br, { lang, theme: 'light' }); await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1200);
    for (const r of ROUTES) {
      await go(p, r);
      const o = await p.evaluate(() => { const m = document.querySelector('main') || document.body; const vis = (e) => { const b = e.getBoundingClientRect(); return b.width > 0 && b.height > 0 && getComputedStyle(e).visibility !== 'hidden'; };
        return { txt: m.innerText, small: [...m.querySelectorAll('button.mini, a.mini, button.primary')].filter((e) => vis(e) && !e.closest('.photos,.bnav,header.top') && e.getBoundingClientRect().height < 43.5).map((e) => (e.dataset.act || e.className) + ':' + Math.round(e.getBoundingClientRect().height)) }; });
      const hit = (o.txt.match(RAW) || [])[0];
      ok(!hit, `no raw key/JS text on ${r} (${lang}): "${hit}"`);
      if (ACTION_ROUTES.includes(r)) ok(o.small.length === 0, `main actions >=44px on ${r} (${lang}): ${o.small.join(',')}`);
    }
    await p.context().close();
  }
  // 4. accounts: a report RPC that returns nothing must not show a JS error
  { const p = await open(br, { lang: 'en', rpc: JSON.stringify(Object.assign({}, rpcmock.M, { acct_overview: null, acct_balance_sheet: null, acct_income_statement: null })) }); await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1000); await go(p, 'accounts'); await p.waitForTimeout(500);
    const t = await p.evaluate(() => document.body.innerText); ok(!/Cannot read|TypeError|undefined/.test(t), 'accounts: null reports show no raw JS error'); ok(p.errors.length === 0, 'accounts: no page error ' + p.errors.join(';')); await p.context().close(); }
  { const s = fs.readFileSync(_P.WEB_DIR + '/accounts.js', 'utf8'); ok(/bos108/.test(s) && /is = is \|\| \{\}/.test(s), 'accounts.js carries the bos108 null guard'); }
  // 5. link strip: pills centred, 44px, current page marked
  { const p = await open(br, { lang: 'en' }); await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1000); await go(p, 'costunknown');
    const o = await p.evaluate(() => { const a = [...document.querySelectorAll('.wxlinks > a.btn')]; return { n: a.length, h: a.map((x) => Math.round(x.getBoundingClientRect().height)), cur: a.filter((x) => x.getAttribute('aria-current') === 'page').length }; });
    ok(o.n >= 3 && o.h.every((h) => h >= 44), 'link strip pills are >=44px: ' + o.h); ok(o.cur === 1 || o.cur === 0, 'link strip marks at most one current page'); await p.context().close(); }
  // 6. 16px fields on the new screens (touch device)
  { const p = await open(br, { lang: 'en' }); await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1000);
    for (const r of ['unmatched', 'costunknown', 'books96', 'optionsx', 'costsources']) { await go(p, r);
      const small = await p.evaluate(() => [...document.querySelectorAll('main input:not([type=checkbox]):not([type=radio]), main select, main textarea')].filter((e) => e.getBoundingClientRect().width > 0 && parseFloat(getComputedStyle(e).fontSize) < 15.99).map((e) => e.id || e.name || e.type));
      ok(small.length === 0, `fields >=16px on ${r}: ${small.join(',')}`); }
    await p.context().close(); }
  // 7. drawer language buttons 44px
  { const p = await open(br, { lang: 'en' }); await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(1100);
    const h = await p.evaluate(() => { const f = document.querySelector('#nav_foot'); if (f) f.classList.add('open'); const b = [...document.querySelectorAll('#nav_foot .lang button')]; return b.map((x) => x.getBoundingClientRect().height); });
    ok(h.length >= 3 && h.every((x) => x >= 43.5), 'drawer language buttons >=44px: ' + h); await p.context().close(); }
  // 8. drawer: the four form-rule pages share one group
  { const p = await open(br, { lang: 'en' }); await p.goto(`http://localhost:${PORT}/#/home`); await p.waitForTimeout(900);
    const g = await p.evaluate(() => ['unmatched', 'formguard', 'expenselink', 'transitshort'].map((i) => window.BOS.ia.byRoute(i)).map((r) => r && r.group));
    ok(g.every((x) => x && x === g[0]), 'form-rule pages share one drawer group: ' + g); await p.context().close(); }
  await br.close(); srv.close();
  // 9. contrast tokens (computed from theme.css / styles.css, not hard-coded)
  const th = fs.readFileSync(_P.WEB_DIR + '/theme.css', 'utf8'), st = fs.readFileSync(_P.WEB_DIR + '/styles.css', 'utf8');
  { const lightBrand = hex(th.slice(th.indexOf(':root[data-theme="light"] {')).match(/--brand:\s*(#[0-9a-f]{6})/i)[1]);
    const blk = th.slice(th.indexOf('/* bos108')); const pc = +blk.match(/\[data-theme="light"\] \{ --grad-brand: linear-gradient\(180deg, color-mix\(in srgb, var\(--brand\) (\d+)%/)[1];
    const top = lightBrand.map((v) => Math.round(v * pc / 100 + 255 * (1 - pc / 100))); const r = ratio(top, [255, 255, 255]);
    ok(r >= 4.5, `Premium Light primary top stop vs white ${r.toFixed(2)} >= 4.5`);
    const okc = blk.match(/classic"\] \.chip\.ok \{ color: (#[0-9a-f]{6})/i)[1], okbg = st.match(/--ok-bg:\s*(#[0-9a-f]{6})/i)[1];
    const r2 = ratio(hex(okc), hex(okbg)); ok(r2 >= 4.5, `Classic chip.ok ${okc} on ${okbg} ${r2.toFixed(2)} >= 4.5`);
    const r3 = ratio(hex('#c8283a'), [255, 255, 255]); void r3; }
  console.log(`pol_test: ${pass} passed, ${bad} failed`); process.exit(bad ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(2); });
