// B.barcode.scan(): camera (mock BarcodeDetector + getUserMedia), device input, rule gating; POS scan. Run: node barcode_test.js <scratchpad>
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs'), path = require('path'), http = require('http');
const SP = process.argv[2], ROOT = '/home/user/My-tools/web';
const src = fs.readFileSync(SP + '/smoke.js', 'utf8'); const dataFn = new Function('fs', src.slice(src.indexOf('const csv'), src.indexOf('const srv')).replace(/const fs = require.*\n/, '') + ';return data;'); const base = dataFn(fs);
const R = (key, kind, def, extra = {}) => ({ key, module: 'settings', kind, value: null, default_value: def, label_bn: key, label_en: key, label_mix: key, sort: 1, ...extra });
function mkData(o) {
  const data = JSON.parse(JSON.stringify(base)); const T = data.tables;
  T.rules = [R('vat_on', 'switch', false), R('barcode_camera_on', 'switch', false, o.cam ? { value: true } : {}), R('barcode_device_on', 'switch', false, o.dev ? { value: true } : {}), R('ui_noperm_mode', 'choice', 'lock')];
  T.items[0].barcode = '8901'; T.items[1].barcode = '8902'; return data;
}
const MOCK = `(function(){
  window.__STOPS = 0; window.__GUM = 0; window.__DET = 0;
  window.BarcodeDetector = class { static async getSupportedFormats() { return ['ean_13','ean_8','code_128','code_39','qr_code','upc_a','itf']; } constructor(o) { window.__FORMATS = o && o.formats; } async detect() { window.__DET++; return window.__BC ? [{ rawValue: window.__BC }] : []; } };
  const md = navigator.mediaDevices || {};
  md.getUserMedia = async () => { window.__GUM++; const c = document.createElement('canvas'); c.width = 64; c.height = 48; c.getContext('2d').fillRect(0, 0, 64, 48); const s = c.captureStream(5);
    s.getTracks().forEach((t) => { const st = t.stop.bind(t); t.stop = () => { window.__STOPS++; st(); }; }); return s; };
  if (!navigator.mediaDevices) Object.defineProperty(navigator, 'mediaDevices', { value: md, configurable: true });
})();`;
const NOCAM = `delete window.BarcodeDetector; window.BarcodeDetector = undefined; try { delete window.BarcodeDetector; } catch (e) {} try { Object.defineProperty(navigator, 'mediaDevices', { value: {}, configurable: true }); } catch (e) {}`;   // X5: no camera API at all -> 'not supported' (with a BarcodeDetector missing but a camera present, the vendored ZXing fallback is used instead)
const srv = http.createServer((q, r) => { const f = path.join(ROOT, q.url.split('?')[0] === '/' ? 'index.html' : q.url.split('?')[0]); fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); return r.end(); } const ext = path.extname(f); r.writeHead(200, { 'content-type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.webp': 'image/webp' }[ext] || 'application/octet-stream' }); r.end(b); }); }).listen(8196);
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(o, hash) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error') errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.addInitScript(`window.__DATA=${JSON.stringify(mkData(o))};${o.mock === false ? NOCAM : MOCK};try{localStorage.setItem('bos_lang','${o.lang || 'en'}');}catch(e){}`);
    await p.goto('http://localhost:8196/' + hash); await p.waitForTimeout(900); return p;
  }
  const scan = (p) => p.evaluate(() => { window.__R = 'pending'; window.BOS.barcode.scan().then((c) => { window.__R = c; }); });
  const res = (p) => p.evaluate(() => window.__R);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'horizontal overflow ' + m);

  // ---- none enabled
  let p = await open({}, '#/home'); await scan(p); await p.waitForTimeout(400);
  ok(/Data needed/.test(await p.textContent('#bcOverlay')), 'none enabled -> Data needed message'); ok(await p.locator('#bcOverlay button.primary').count() === 1, 'owner gets settings button (only)');
  await p.screenshot({ path: SP + '/bc_none.png' }); await noOverflow(p, 'none');
  await p.click('#bcOverlay [data-bc=cancel]'); await p.waitForTimeout(200); ok((await res(p)) === null && await p.locator('#bcOverlay').count() === 0, 'cancel -> null, overlay gone');
  await scan(p); await p.waitForTimeout(300); await p.keyboard.press('Escape'); await p.waitForTimeout(200); ok((await res(p)) === null && await p.locator('#bcOverlay').count() === 0, 'Escape closes');
  await p.close();

  // ---- device only
  p = await open({ dev: true }, '#/home'); await scan(p); await p.waitForTimeout(400);
  ok(await p.locator('#bc_in').isVisible() && await p.locator('#bcOverlay [data-bc=cam]').count() === 0, 'device only -> input, no camera button'); ok(await p.evaluate(() => document.activeElement.id) === 'bc_in', 'input focused'); ok((await p.evaluate(() => window.__GUM)) === 0, 'camera not started');
  await p.screenshot({ path: SP + '/bc_dev.png' }); await noOverflow(p, 'device');
  await p.keyboard.press('Enter'); await p.waitForTimeout(150); ok((await res(p)) === 'pending', 'empty Enter does nothing');
  await p.keyboard.type('  8901234567890'); await p.keyboard.press('Enter'); await p.waitForTimeout(200); ok((await res(p)) === '8901234567890', 'scanner keystrokes + Enter -> trimmed code'); ok(await p.locator('#bcOverlay').count() === 0, 'closed after code');
  await scan(p); await p.waitForTimeout(300); await p.keyboard.type('typed-77'); await p.click('#bcOverlay [data-bc=use]'); await p.waitForTimeout(200); ok((await res(p)) === 'typed-77', 'typed code + Use button');
  await scan(p); await p.waitForTimeout(300); await p.click('#bcOverlay h2'); await p.waitForTimeout(150); ok(await p.evaluate(() => document.activeElement.id) === 'bc_in', 'focus returns to the input'); await p.keyboard.press('Escape');
  await p.close();

  // ---- camera only
  p = await open({ cam: true }, '#/home'); await p.evaluate(() => { window.__BC = null; }); await scan(p); await p.waitForTimeout(700);
  ok(await p.locator('#bcOverlay video').count() === 1 && await p.locator('#bcOverlay [data-bc=dev]').count() === 0, 'camera only -> video, no device button'); ok((await p.evaluate(() => window.__GUM)) === 1, 'getUserMedia once');
  ok(JSON.stringify(await p.evaluate(() => window.__FORMATS)) === JSON.stringify(['ean_13', 'ean_8', 'code_128', 'code_39', 'qr_code', 'upc_a']), 'detector formats');
  await p.screenshot({ path: SP + '/bc_cam.png' }); await noOverflow(p, 'camera'); ok((await p.evaluate(() => window.__DET)) >= 1, 'detector is polled');
  await p.evaluate(() => { window.__BC = '5901234123457'; }); await p.waitForTimeout(700); ok((await res(p)) === '5901234123457', 'camera detection resolves with rawValue'); ok(await p.locator('#bcOverlay').count() === 0, 'overlay closed after scan'); ok((await p.evaluate(() => window.__STOPS)) >= 1, 'camera tracks stopped');
  // cancel stops the stream too
  await p.evaluate(() => { window.__BC = null; window.__STOPS = 0; }); await scan(p); await p.waitForTimeout(600); await p.click('#bcOverlay [data-bc=cancel]'); await p.waitForTimeout(200);
  ok((await res(p)) === null && (await p.evaluate(() => window.__STOPS)) >= 1, 'cancel stops the camera'); const det0 = await p.evaluate(() => window.__DET); await p.waitForTimeout(600); ok((await p.evaluate(() => window.__DET)) === det0, 'detector polling stopped');
  // leaving the page also stops it
  await scan(p); await p.waitForTimeout(500); await p.evaluate(() => { window.__STOPS = 0; location.hash = '#/dues'; }); await p.waitForTimeout(400); ok(await p.locator('#bcOverlay').count() === 0 && (await p.evaluate(() => window.__STOPS)) >= 1, 'route change closes + stops');
  await p.close();

  // ---- both -> two buttons; camera permission denied falls back to device
  p = await open({ cam: true, dev: true }, '#/home'); await scan(p); await p.waitForTimeout(400);
  ok(await p.locator('#bcOverlay [data-bc=cam]').count() === 1 && await p.locator('#bcOverlay [data-bc=dev]').count() === 1, 'both on -> two buttons'); await p.screenshot({ path: SP + '/bc_both.png' }); await noOverflow(p, 'both');
  await p.click('#bcOverlay [data-bc=dev]'); await p.waitForTimeout(200); ok(await p.locator('#bc_in').isVisible(), 'device button -> input'); ok((await p.evaluate(() => window.__GUM)) === 0, 'camera not started by device choice');
  await p.click('#bcOverlay [data-bc=cam]'); await p.waitForTimeout(600); ok(await p.locator('#bcOverlay video').count() === 1, 'switch to camera'); await p.click('#bcOverlay [data-bc=dev]'); await p.waitForTimeout(200); ok((await p.evaluate(() => window.__STOPS)) >= 1, 'switching away stops the camera'); await p.keyboard.press('Escape'); await p.waitForTimeout(150);
  await p.evaluate(() => { navigator.mediaDevices.getUserMedia = async () => { throw new Error('denied'); }; }); await scan(p); await p.waitForTimeout(300); await p.click('#bcOverlay [data-bc=cam]'); await p.waitForTimeout(500);
  ok(await p.locator('#bc_in').isVisible() && /Could not start the camera/.test(await p.textContent('#bcOverlay')), 'permission denied -> message + device input'); await p.keyboard.press('Escape'); await p.close();

  // ---- camera on, BarcodeDetector missing: fallback message
  p = await open({ cam: true, mock: false }, '#/home'); await scan(p); await p.waitForTimeout(500);
  ok(/not supported/.test(await p.textContent('#bcOverlay')), 'unsupported -> message'); ok(await p.locator('#bcOverlay .notice.warn').count() === 1, 'message styled'); await p.screenshot({ path: SP + '/bc_nosupport.png' }); await p.keyboard.press('Escape'); await p.close();

  // ---- POS: scan -> add by barcode; typed + Enter (device mode); unknown code
  p = await open({ dev: true }, '#/pos'); await p.waitForTimeout(500);
  const it0 = base.tables.items[0], it1 = base.tables.items[1];
  ok(await p.locator('[data-act=pos_scan]').count() === 1, 'POS scan button'); await p.screenshot({ path: SP + '/bc_pos.png' }); await noOverflow(p, 'pos');
  await p.click('[data-act=pos_scan]'); await p.waitForTimeout(300); await p.keyboard.type('8901'); await p.keyboard.press('Enter'); await p.waitForTimeout(400);
  const sheetOrCart = async () => (await p.locator('.sheet h2').count()) ? (await p.textContent('.sheet h2')) : 'cart:' + (await p.locator('.pos-item.in').count());
  const r1 = await sheetOrCart(); log('after scan 8901 ->', r1); ok(r1.includes(it0.name_bn) || r1.includes('cart:1') || /Rasa|rasa/.test(r1) || r1 !== 'cart:0', 'known barcode opens qty sheet / adds the item');
  await p.evaluate(() => { const c = document.querySelector('[data-act=closesheet]'); if (c) c.click(); });
  await p.click('[data-act=pos_scan]'); await p.waitForTimeout(300); await p.keyboard.type('000000'); await p.keyboard.press('Enter'); await p.waitForTimeout(300); ok(/No product has this barcode/.test(await p.textContent('#toast')), 'unknown barcode toast');
  await p.evaluate(() => { const c = document.querySelector('[data-act=closesheet]'); if (c) c.click(); });
  const before = await p.locator('.pos-item.in').count(); await p.fill('#pos_q', '8902'); await p.press('#pos_q', 'Enter'); await p.waitForTimeout(400);
  ok((await p.inputValue('#pos_q')) === '', 'Enter in search with a known barcode clears the box'); log('item 1 unit:', it1.unit);
  await p.close();
  p = await open({}, '#/pos'); await p.waitForTimeout(400); await p.fill('#pos_q', '8902'); await p.press('#pos_q', 'Enter'); await p.waitForTimeout(300); ok((await p.inputValue('#pos_q')) === '8902', 'search Enter does not scan when device mode is off');
  await p.close();

  // ---- scanItem / enabled helpers (used by the purchase bill lines and the stock actions) ----
  p = await open({ dev: true }, '#/pos'); await p.waitForTimeout(500);
  ok(await p.evaluate(() => window.BOS.barcode.enabled() === true), 'enabled() true when a scan option is on');
  await p.evaluate(() => { window.__R = 'wait'; window.BOS.barcode.scanItem([{ id: 'x1', code: 'T-1', barcode: '5551' }, { id: 'x2', code: 'T-2', barcode: '5552' }]).then((it) => { window.__R = it ? it.id : null; }); });
  await p.waitForTimeout(300); await p.keyboard.type('5552'); await p.keyboard.press('Enter'); await p.waitForTimeout(300); ok((await p.evaluate(() => window.__R)) === 'x2', 'scanItem resolves to the item with that barcode');
  await p.evaluate(() => { window.__R = 'wait'; window.BOS.barcode.scanItem([{ id: 'x1', code: 'T-1', barcode: '5551' }]).then((it) => { window.__R = it ? it.id : null; }); });
  await p.waitForTimeout(300); await p.keyboard.type('9999'); await p.keyboard.press('Enter'); await p.waitForTimeout(300); ok((await p.evaluate(() => window.__R)) === null && /No product has this barcode/.test(await p.textContent('#toast')), 'unknown code: null and a message');
  await p.evaluate(() => { window.__R = 'wait'; window.BOS.barcode.scanItem([{ id: 'x1', barcode: '5551' }]).then((it) => { window.__R = it ? it.id : null; }); });
  await p.waitForTimeout(300); await p.keyboard.press('Escape'); await p.waitForTimeout(200); ok((await p.evaluate(() => window.__R)) === null, 'cancel resolves to null'); await p.close();
  p = await open({}, '#/pos'); await p.waitForTimeout(400); ok(await p.evaluate(() => window.BOS.barcode.enabled() === false), 'enabled() false while both options are off'); await p.close();

  log('errors:', errors.length ? [...new Set(errors)] : 'none'); log('assert failures:', bad); await br.close(); srv.close();
} catch (e) { console.log('TEST CRASH:', e.message.split('\n').slice(0,6).join(' | ')); process.exit(1); } })();
