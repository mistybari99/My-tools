// X5 web test (headless Chromium, 360 px): #/camrec screen (every engine row, honest reasons, self-test), the recognition
// helpers loaded, all recognition switches OFF by default, no horizontal scroll, and the barcode ZXing fallback path (mocked).
// Run: node tests/web/scan_web_test.js <abs tests/web>   (needs playwright + chromium as the other web suites)
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = process.env.BOS_WEB || path.join(__dirname, '..', '..', 'web');
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const base = dataFn(fs);
const R = (key, kind, def, extra = {}) => ({ key, module: 'items', kind, value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1, ...extra });
function mkData(o) {
  const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
  T.rules = [R('vat_on', 'switch', false), R('barcode_camera_on', 'switch', false, o.cam ? { value: true } : {}), R('barcode_device_on', 'switch', false),
    R('item_similar_check_on', 'switch', false), R('recog_ocr_on', 'switch', false), R('recog_image_match_on', 'switch', false), R('recog_vision_on', 'switch', false),
    R('recog_vision_consent_on', 'switch', false), R('recog_ocr_wifi_only', 'switch', true), R('recog_image_threshold', 'number', null), R('recog_ocr_max_px', 'number', null),
    R('recog_ocr_langs', 'text', null), R('recog_vision_budget', 'number', null), R('ui_noperm_mode', 'choice', 'lock')];
  return data;
}
const MOCK = `(function(){ window.BarcodeDetector = undefined; try { delete window.BarcodeDetector; } catch (e) {} })();`;
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp', '.json': 'application/json' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8517);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route('https://tessdata.projectnaptha.com/**', (r) => r.abort());
    await p.addInitScript(`window.__DATA=${JSON.stringify(mkData(o))};${MOCK};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:8517/' + hash); await p.waitForTimeout(900); return p;
  }
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);

  // ---- helpers present and defaults OFF
  let p = await open({}, '#/home'); await p.waitForTimeout(300);
  ok(await p.evaluate(() => !!(window.BOS_SCAN_CORE && window.BOS.scanitems && window.BOS.photo && window.BOS_SCAN_NATIVE)), 'scan core, scan, photo and native bridge loaded');
  ok(await p.evaluate(() => window.BOS_SCAN_NATIVE.available() === false), 'native bridge is inert in the browser');
  ok(await p.evaluate(() => window.BOS.scanitems.settings().recog_ocr_on === false && window.BOS.scanitems.settings().recog_vision_on === false), 'every recognition switch reads OFF');
  ok(await p.evaluate(() => window.BOS.scanitems.settings().recog_image_threshold === null), 'blank threshold stays blank (no invented value)');
  ok(await p.evaluate(() => window.BOS.scanitems.status().find((r) => r.id === 'vision').choice.reason === 'off'), 'vision reports off, not a guess');
  await p.close();

  // ---- the screen at 360 px
  p = await open({}, '#/camrec'); await p.waitForTimeout(700);
  const rows = await p.locator('.x5-row').count();
  ok(rows === 5, 'camrec: five engine rows (got ' + rows + ')');
  ok(/Off|off|বন্ধ/.test(await p.textContent('.x5-row[data-engine=ocr]')), 'camrec: OCR row says off');
  ok(await p.locator('[data-act=x5_test]').count() === 1, 'camrec: self-test button');
  await p.screenshot({ path: SP + '/x5_camrec.png' }); await noOverflow(p, 'camrec');
  await p.click('[data-act=x5_test]'); await p.waitForTimeout(500);
  ok(await p.locator('#x5_last').count() === 1, 'camrec: self-test result shown');
  ok(await p.locator('#x5_last .row').count() === 5, 'camrec: self-test has a line per engine');
  await p.screenshot({ path: SP + '/x5_camrec_test.png' }); await noOverflow(p, 'camrec after test');
  await p.close();

  // ---- barcode fallback: no BarcodeDetector and the camera switch ON -> fallbackDetector loads the vendored reader (or says not supported)
  p = await open({ cam: true }, '#/home'); await p.waitForTimeout(400);
  ok(await p.evaluate(async () => { const d = await window.BOS.scanitems.fallbackDetector(); return d === null || typeof d.detect === 'function'; }), 'fallbackDetector returns a detector or null (never throws)');
  ok(await p.evaluate(() => typeof window.BOS.barcode.scan === 'function'), 'barcode scan still exposed');
  await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
  if (bad) process.exit(1);
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0, 6).join(' | ')); process.exit(1); } })();
