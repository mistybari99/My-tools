// Variants page #/variants (web/variants125.js), RPCs mocked with the REAL shapes of the phase125 functions.
// Checks: option lists, style list, matrix (2 axes, missing cell), dry-run then generate (pick subset), style/option/price-list saves (client ids, order of axes), friendly server errors,
// switch-off banner (no write buttons), no-business message, escaping, Bangla mode, 360px no horizontal overflow, no JS errors.
// Run: node variants125_test.js <abs tests/web dir>
const _P = require('./_paths');
const { chromium } = require('/opt/node22/lib/node_modules/playwright');
const fs = require('fs');
const SP = process.argv[2] || _P.TESTS_DIR;
const C = require(SP + '/w5b_common.js');
const base = C.baseData(SP), PORT = _P.freePort(), srv = C.serve(PORT);
const WEB = _P.WEB_DIR;
const MOCK = `(function(){ const real = window.supabase.createClient; window.supabase.createClient = (...a) => { const c = real(...a); const rpc = c.rpc; const V = window.__VR;
 const clone = (x) => JSON.parse(JSON.stringify(x));
 const fail = () => { const m = V.err; V.err = null; return { data: null, error: { message: m, code: 'P0001' } }; };
 c.rpc = async (fn, args) => {
  (window.__ACV = window.__ACV || []).push([fn, clone(args || {})]);
  if (fn === 'my_businesses125') return { data: clone(V.biz), error: null };
  if (fn === 'variants_overview') return { data: clone(V.ov), error: null };
  if (fn === 'variant_matrix') return { data: clone(V.mx), error: null };
  if (fn === 'variants_generate') { if (V.err) return fail(); return { data: args.p_dry ? { dry: true, total: 15, would_create: 5, existing: 10, sample: ['SH01-S-GREEN'] } : { dry: false, total: 15, created: 5, existing: 10, items: [] }, error: null }; }
  if (['option_set_save', 'option_values_save', 'style_save', 'price_list_save', 'price_list_items_set'].includes(fn)) { if (V.err) return fail(); return { data: { dup: false, id: 99, saved: 1 }, error: null }; }
  return rpc(fn, args);
 }; return c; }; })();`;
const mkV = (o) => {
  const sizes = ['S', 'M', 'L'].map((c, i) => ({ id: i + 1, code: c, label_bn: c, label_en: c === 'S' ? 'Small <i>x</i>' : c, sort: (i + 1) * 10, active: true }));
  const cols = [{ id: 4, code: 'RED', label_bn: 'লাল', label_en: 'Red', sort: 10, active: true }, { id: 5, code: 'BLUE', label_bn: 'নীল', label_en: 'Blue', sort: 20, active: true }];
  const sets = [{ id: 11, code: 'SIZE', name_bn: 'সাইজ', name_en: 'Size <b>set</b>', kind: 'size', product_group: 'Shirts', active: true, values: sizes },
    { id: 12, code: 'COLOUR', name_bn: 'রং', name_en: 'Colour', kind: 'colour', product_group: null, active: true, values: cols }];
  return {
    biz: o.nobiz ? [] : [{ id: 7, code: 'HW', name_bn: 'কাপড় <i>ব্যবসা</i>', name_en: 'Cloth <i>biz</i>', template_code: 'fashion_apparel', variants_on: !o.off }].concat(o.two ? [{ id: 8, code: 'HW2', name_bn: 'দ্বিতীয়', name_en: 'Second', template_code: null, variants_on: true }] : []),
    ov: { org: 7, variants_on: !o.off, can_manage: !o.view, option_sets: sets,
      styles: [{ id: 21, code: 'SH01', name_bn: 'শার্ট', name_en: 'A very long style name that must wrap inside a narrow phone screen without any sideways scrolling at all <b>x</b>', product_group: 'Shirts', unit: 'pc', item_type: 'resale', base_price: 850, status: 'active', axes: [11, 12], variant_count: 5 }],
      price_lists: [{ id: 31, code: 'RET', name_bn: 'খুচরা', name_en: 'Retail', channel: 'retail', valid_from: '2026-01-01', valid_to: null, active: true, rows: 3 }] },
    mx: { style: { id: 21, code: 'SH01', name_bn: 'শার্ট', name_en: 'Shirt', base_price: 850 },
      axes: [{ axis_no: 1, set_id: 11, code: 'SIZE', name_bn: 'সাইজ', name_en: 'Size', values: sizes }, { axis_no: 2, set_id: 12, code: 'COLOUR', name_bn: 'রং', name_en: 'Colour', values: cols }],
      cells: [['S', 'RED', 10], ['M', 'RED', 0], ['L', 'RED', 4], ['S', 'BLUE', 7], ['M', 'BLUE', 2]].map(([s, c, q], i) => ({ item_id: 'it' + i, code: 'SH01-' + s + '-' + c, barcode: '2000000000' + i, key: s + '|' + c, opts: {}, active: true, sell_price: 850, stock: q })) },
  };
};
(async () => { try {
  const br = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const errors = []; const log = (...a) => console.log(...a); let bad = 0; const ok = (c, m) => { if (!c) { bad++; log('FAIL:', m); } };
  async function open(hash, o = {}) {
    const ctx = await br.newContext({ viewport: { width: 360, height: 780 }, deviceScaleFactor: 2 }); const p = await ctx.newPage();
    p.on('pageerror', (e) => errors.push('pageerror: ' + e.message)); p.on('console', (m) => { if (m.type() === 'error' && !/Failed to load resource|code: P0001/.test(m.text())) errors.push('console: ' + m.text()); });
    await p.route('**/vendor/supabase.js', (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(SP + '/stub.js', 'utf8') + C.EXTRA + C.EXTRA5 + C.EXTRA6 + MOCK }));
    await p.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
    await p.route(`http://localhost:${PORT}/`, (r) => r.fulfill({ contentType: 'text/html', body: ((h) => (/variants125\.js/.test(h) ? h : h.replace('<script src="cashmoves.js"></script>', '<script src="cashmoves.js"></script><script src="variants125.js"></script>')))(fs.readFileSync(WEB + '/index.html', 'utf8')) }));
    p.route(`http://localhost:${PORT}/variants125.js`, (r) => r.fulfill({ contentType: 'text/javascript', body: fs.readFileSync(WEB + '/variants125.js', 'utf8') }));
    const data = C.mk(base, {});
    await p.addInitScript(`window.__DATA=${JSON.stringify(data)};window.__VR=${JSON.stringify(mkV(o))};try{localStorage.setItem('bos_lang','${o.lang || 'en'}')}catch(e){}`);
    await p.goto(`http://localhost:${PORT}/` + hash); await p.waitForTimeout(1400); return p;
  }
  const wait = (p, n = 300) => p.waitForTimeout(n);
  const calls = (p, fn) => p.evaluate((f) => (window.__ACV || []).filter((c) => c[0] === f).map((c) => c[1]), fn);
  const text = (p) => p.evaluate(() => document.body.innerText);
  const noOverflow = async (p, m) => ok(await p.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1), 'overflow ' + m);

  // styles tab (default)
  let p = await open('#/variants');
  let t = await text(p);
  ok(await p.locator('.vr-sty').count() === 1, 'one style listed');
  ok(/5 variants/.test(t) && /SH01/.test(t), 'variant count shown');
  ok(/<b>x<\/b>/.test(t) && (await p.locator('.vr-sty b b').count()) === 0, 'style name escaped, not injected as HTML');
  ok(await p.locator('[data-act=vr_stynew]').count() === 1, 'owner/manager sees the add button');
  await noOverflow(p, 'styles list'); await p.screenshot({ path: SP + '/vr_styles.png', fullPage: true });

  // option lists
  await p.click('[data-act=vr_tab][data-v=sets]'); await wait(p);
  t = await text(p);
  ok(await p.locator('.vr-set').count() === 2, 'two option lists'); ok(/Size <b>set<\/b>/.test(t), 'option list name escaped');
  ok((await p.locator('.vr-vals .chip').allTextContents()).some((x) => /S · Small <i>x<\/i>/.test(x)), 'value label shown escaped');
  await noOverflow(p, 'sets');
  await p.click('[data-act=vr_valnew][data-id="11"]'); await wait(p);
  await p.fill('#vr_vals', 'xl, এক্সএল, Extra large\nxxl\n\n'); await p.click('[data-act=vr_val_save]'); await wait(p, 500);
  let c = await calls(p, 'option_values_save');
  ok(c.length === 1 && c[0].p_set === 11 && c[0].p_values.length === 2 && c[0].p_values[0].code === 'XL' && c[0].p_values[0].label_bn === 'এক্সএল' && c[0].p_values[1].label_bn === 'XXL', 'values parsed: code upper-cased, label defaults to code');
  await p.click('[data-act=vr_setnew]'); await wait(p);
  await p.fill('#vr_c', 'fabric'); await p.fill('#vr_bn', 'কাপড়'); await p.selectOption('#vr_k', 'fabric'); await p.click('[data-act=vr_set_save]'); await wait(p, 500);
  c = await calls(p, 'option_set_save'); ok(c.length === 1 && c[0].p_code === 'FABRIC' && c[0].p_kind === 'fabric' && c[0].p_org === 7 && /^[0-9a-f-]{20,}$/.test(c[0].p_client || ''), 'option list saved with business, code and client id');
  await p.click('[data-act=vr_setnew]'); await wait(p); await p.click('[data-act=vr_set_save]'); await wait(p, 200);
  ok((await calls(p, 'option_set_save')).length === 1 && /not valid/.test(await text(p)), 'empty code is stopped in the page with a friendly text');
  await p.evaluate(() => window.__VR.err = 'code_taken'); await p.fill('#vr_c', 'size'); await p.fill('#vr_bn', 'x'); await p.click('[data-act=vr_set_save]'); await wait(p, 400);
  ok(/already used/.test(await text(p)), 'server code_taken shown as friendly text');

  // style sheet
  p = await open('#/variants');
  await p.click('[data-act=vr_stynew]'); await wait(p);
  await p.fill('#vr_c', 'tr01'); await p.fill('#vr_bn', 'ট্রাউজার'); await p.fill('#vr_p', '১২০০');
  await p.selectOption('#vr_ax1', '12'); await p.selectOption('#vr_ax2', '11');
  await noOverflow(p, 'style sheet'); await p.screenshot({ path: SP + '/vr_style_sheet.png', fullPage: true });
  await p.click('[data-act=vr_sty_save]'); await wait(p, 500);
  c = await calls(p, 'style_save'); ok(c.length === 1 && c[0].p_code === 'TR01' && c[0].p_price === 1200 && JSON.stringify(c[0].p_axes) === '[12,11]' && c[0].p_id === null, 'style saved: axes in the chosen order, Bangla digits parsed');
  await p.click('[data-act=vr_stynew]'); await wait(p); await p.fill('#vr_c', 'x1'); await p.fill('#vr_bn', 'x'); await p.click('[data-act=vr_sty_save]'); await wait(p, 300);
  ok((await calls(p, 'style_save')).length === 1 && /not valid/.test(await text(p)), 'a style without any option list is stopped');

  // matrix + generate
  p = await open('#/variants');
  await p.click('[data-act=vr_open][data-id="21"]'); await wait(p, 500);
  ok(await p.locator('#vr_matrix td').count() === 6, 'matrix has 3 rows x 2 colour columns = 6 cells');
  ok(await p.locator('#vr_matrix td.muted', { hasText: '–' }).count() === 1, 'the missing variant (L/BLUE) is shown as a dash');
  ok((await p.locator('#vr_matrix td[data-k="L|RED"]').textContent()).trim() === '4', 'stock number in the cell');
  await noOverflow(p, 'matrix'); await p.screenshot({ path: SP + '/vr_matrix.png', fullPage: true });
  await p.click('[data-act=vr_dry]'); await wait(p, 400);
  c = await calls(p, 'variants_generate'); ok(c.length === 1 && c[0].p_dry === true && c[0].p_pick === null && c[0].p_style === 21, 'dry run first, all values, nothing picked out');
  ok(/Would create: 5 · 10 already exist/.test(await text(p)), 'dry-run result shown');
  await p.uncheck('.vr-pick[data-set=COLOUR][value=BLUE]'); await p.click('[data-act=vr_make]'); await wait(p, 600);
  c = await calls(p, 'variants_generate'); ok(c.length === 2 && c[1].p_dry === false && c[1].p_pick && JSON.stringify(c[1].p_pick.COLOUR) === '["RED"]' && c[1].p_pick.SIZE.length === 3, 'real generate sends the picked subset');
  ok((await calls(p, 'variant_matrix')).length >= 2, 'matrix reloaded after generating');
  await p.evaluate(() => window.__VR.err = 'too_many'); await p.click('[data-act=vr_make]'); await wait(p, 400);
  ok(/500 at once/.test(await text(p)), 'too_many friendly text');
  await p.click('[data-act=vr_back]'); await wait(p); ok(await p.locator('.vr-sty').count() === 1, 'back to the style list');

  // price lists
  await p.click('[data-act=vr_tab][data-v=prices]'); await wait(p);
  ok(await p.locator('.vr-pl').count() === 1 && /does not change|not changed/.test(await text(p)), 'price list shown with the "item price untouched" note');
  await p.click('[data-act=vr_plnew]'); await wait(p); await p.fill('#vr_c', 'ws'); await p.fill('#vr_bn', 'পাইকারি'); await p.selectOption('#vr_ch', 'wholesale'); await p.fill('#vr_from', '2026-11-01');
  await noOverflow(p, 'price list sheet'); await p.click('[data-act=vr_pl_save]'); await wait(p, 500);
  c = await calls(p, 'price_list_save'); ok(c.length === 1 && c[0].p_channel === 'wholesale' && c[0].p_from === '2026-11-01' && c[0].p_to === null && c[0].p_code === 'WS', 'price list saved with channel and date');
  await p.click('[data-act=vr_papply]'); await wait(p); await p.fill('#vr_pa', '799'); await p.click('[data-act=vr_apply_save]'); await wait(p, 600);
  c = await calls(p, 'price_list_items_set'); ok(c.length === 1 && c[0].p_list === 31 && c[0].p_rows.length === 5 && c[0].p_rows.every((r) => r.price === 799 && r.item_id), 'one price applied to every variant of the style');
  await noOverflow(p, 'prices');

  // switch off, view only, no business, two businesses
  p = await open('#/variants', { off: true });
  ok(await p.locator('#vr_off').count() === 1 && await p.locator('[data-act=vr_stynew]').count() === 0, 'switch off: banner, no write button');
  p = await open('#/variants', { view: true });
  ok(await p.locator('[data-act=vr_stynew]').count() === 0 && await p.locator('.vr-sty').count() === 1, 'view-only user: list visible, no write button');
  p = await open('#/variants', { nobiz: true });
  ok(await p.locator('#vr_noperm').count() === 1, 'no business: friendly message');
  p = await open('#/variants', { two: true });
  ok(await p.locator('#vr_biz option').count() === 2, 'business picker when the user works in two businesses');
  await p.selectOption('#vr_biz', '8'); await wait(p, 500); ok((await calls(p, 'variants_overview')).some((x) => x.p_org === 8), 'switching business reloads with the new business id');

  // Bangla mode
  p = await open('#/variants', { lang: 'bn' });
  t = await text(p);
  ok(/অপশন তালিকা/.test(t) && /স্টাইল/.test(t) && /দামের তালিকা/.test(t), 'Bangla labels'); await noOverflow(p, 'bangla'); await p.screenshot({ path: SP + '/vr_bn.png', fullPage: true });

  console.log('errors:', errors.length ? errors.join('\n') : 'none'); console.log('assert failures:', bad);
  await br.close();
} catch (e) { console.log('CRASH', e); process.exitCode = 1; } finally { srv.close(); } })();
