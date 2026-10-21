// X5 recognition core (web/scan_core.js): engine selection and honest reasons, label parsing, Bangla/English matching,
// nearest-neighbour unit tests, photo rules. Pure node, no browser, no network. Run: node tests/web/scan_core_test.js <abs tests/web>
const path = require('path');
const core = require(path.join(__dirname, '..', '..', 'web', 'scan_core.js'));
let fail = 0, pass = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL:', m); } };
const eq = (a, b, m) => ok(JSON.stringify(a) === JSON.stringify(b), m + ' (got ' + JSON.stringify(a) + ')');
const PWA = { https: true, native: false, barcodeDetector: true, camera: true, wasm: true, indexedDb: true, networkOnline: true, x1Gate: false, modelLoaded: false, onWifi: true, cachedLang: false };
const NATIVE = { ...PWA, native: true };
const OFF = {};

// ---- T1 defaults: every recognition switch OFF, the barcode device/camera switches OFF
eq(core.chooseEngine('ocr', OFF, PWA).usable, false, 'T1 OCR OFF by default');
eq(core.chooseEngine('ocr', OFF, PWA).reason, 'off', 'T1 OCR reason is off');
eq(core.chooseEngine('image', OFF, PWA).reason, 'off', 'T1 image match off by default');
eq(core.chooseEngine('vision', OFF, PWA).reason, 'off', 'T1 vision off by default');
eq(core.chooseEngine('barcode', OFF, PWA).usable, false, 'T1 barcode off by default');

// ---- T2 barcode: native BarcodeDetector, ZXing fallback, typed entry, https and camera checks
eq(core.chooseEngine('barcode', { barcode_camera_on: true }, PWA).engine, 'barcode_detector', 'T2 camera on, BarcodeDetector present');
eq(core.chooseEngine('barcode', { barcode_camera_on: true }, { ...PWA, barcodeDetector: false }).engine, 'zxing_fallback', 'T2 no BarcodeDetector -> ZXing fallback');
eq(core.chooseEngine('barcode', { barcode_camera_on: true }, { ...PWA, barcodeDetector: false, wasm: false }).usable, false, 'T2 no wasm -> fallback not usable');
eq(core.chooseEngine('barcode', { barcode_camera_on: true }, { ...PWA, https: false }).reason, 'needs_https', 'T2 camera needs https');
eq(core.chooseEngine('barcode', { barcode_camera_on: true }, { ...PWA, camera: false }).reason, 'no_camera', 'T2 no camera reported');
eq(core.chooseEngine('barcode', { barcode_device_on: true }, OFF).engine, 'device_typed', 'T2 device scanner on -> typed entry');
eq(core.chooseEngine('barcode', { barcode_camera_on: true }, NATIVE).engine, 'native_barcode', 'T2 inside the wrapper the native scanner is preferred');

// ---- T3 OCR: needs its own switch, a max size, a language and (optionally) Wi-Fi
const OCR_ON = { recog_ocr_on: true, recog_ocr_max_px: 1024, recog_ocr_langs: 'eng+ben', recog_ocr_wifi_only: true };
eq(core.chooseEngine('ocr', OCR_ON, { ...PWA, onWifi: false }).reason, 'wifi_only', 'T3 OCR waits for Wi-Fi when the switch says so');
eq(core.chooseEngine('ocr', OCR_ON, { ...PWA, onWifi: false, cachedLang: true }).usable, true, 'T3 cached language works without Wi-Fi');
eq(core.chooseEngine('ocr', { ...OCR_ON, recog_ocr_max_px: null }, PWA).reason, 'setting_needed', 'T3 blank max size blocks OCR (no invented limit)');
eq(core.chooseEngine('ocr', { ...OCR_ON, recog_ocr_langs: null }, PWA).reason, 'setting_needed', 'T3 no language chosen blocks OCR');
eq(core.chooseEngine('ocr', OCR_ON, { ...PWA, wasm: false }).reason, 'no_wasm', 'T3 OCR needs wasm');
eq(core.chooseEngine('ocr', OCR_ON, PWA).usable, true, 'T3 OCR usable with every setting and capability');

// ---- T4 image match: threshold blank = not set, index needed; vision: consent, X1, budget
eq(core.chooseEngine('image', { recog_image_match_on: true, recog_image_threshold: null }, { ...PWA, modelLoaded: true }).reason, 'threshold_not_set', 'T4 blank threshold -> not set');
eq(core.chooseEngine('image', { recog_image_match_on: true, recog_image_threshold: 0.3 }, { ...PWA, modelLoaded: false }).reason, 'no_index', 'T4 no model/index -> no index');
eq(core.chooseEngine('image', { recog_image_match_on: true, recog_image_threshold: 0.3 }, { ...PWA, modelLoaded: true }).usable, true, 'T4 image match usable when set');
const V = { recog_vision_on: true, recog_vision_consent_on: true, recog_vision_budget: 500 };
eq(core.chooseEngine('vision', { recog_vision_on: true }, PWA).reason, 'needs_consent', 'T4 vision needs consent');
eq(core.chooseEngine('vision', V, PWA).reason, 'needs_x1', 'T4 vision needs the X1 gate');
eq(core.chooseEngine('vision', { ...V, recog_vision_budget: null }, { ...PWA, x1Gate: true }).reason, 'budget_not_set', 'T4 vision needs a budget');
eq(core.chooseEngine('vision', V, { ...PWA, x1Gate: true }).usable, true, 'T4 vision usable only with all four');

// ---- T5 status table: one row per engine, no guessed success
const table = core.statusTable(OFF, PWA);
eq(table.map((r) => r.id), ['barcode', 'ocr', 'image', 'vision', 'native'], 'T5 status table has every engine');
eq(table.find((r) => r.id === 'native').choice.reason, 'pwa_engine', 'T5 PWA reports the native wrapper as not present');

// ---- T6 label parsing: price, weight, expiry-like, name guess, Bangla digits
const p = core.parseLabel('Brand Sugar\nNet 1kg\nMRP Tk 120.50\nEXP 12/2026\nচিনি ৫০০ গ্রাম\n৳ ১২০');
eq(p.prices.map((x) => x.value), [120.5, 120], 'T6 prices from English and Bangla digits');
eq(p.weights.map((x) => x.unit), ['kg', 'g'], 'T6 weights in kg and grams (Bangla unit word)');
eq(p.expiry.map((x) => x.raw), ['12/2026'], 'T6 expiry-like date kept as raw text');
ok(p.nameGuess.length > 0, 'T6 a name guess is produced');
eq(core.parseLabel('').prices, [], 'T6 empty text is empty');
eq(core.parseLabel('x'.repeat(9000)).text.length, 4000, 'T6 text is capped at 4000 characters');

// ---- T7 names: Bangla, English, Banglish, spacing and case, one-letter difference
eq(core.key('টেস্ট  চিনি'), core.key('টেস্টচিনি'), 'T7 spaces ignored (Bangla)');
eq(core.key('Test Sugar'), core.key('test-sugar'), 'T7 case and punctuation ignored');
eq(core.key('১২০'), core.key('120'), 'T7 Bangla digits equal ASCII digits');
eq(core.lev1(core.key('Sugar'), core.key('Sugr')), true, 'T7 one letter missing is close');
eq(core.lev1(core.key('Sugar'), core.key('Salt')), false, 'T7 different word is not close');

// ---- T8 rankSuggestions: barcode hit first, exact, close, partial, sources listed
const dict = [{ id: 'D1', code: '03-001', name_bn: 'চিনি', name_en: 'Sugar Bag' }, { id: 'D2', code: '03-002', name_bn: 'লবণ', name_en: 'Salt' }];
const items = [{ id: 'I1', code: 'test_cat-901', name_bn: 'টেস্ট চিনি', name_en: 'Test Sugar Bag', barcode: '8901' }];
const sug = core.rankSuggestions('Sugar Bag', [{ source: 'dictionary', rows: dict }, { source: 'items', rows: items }]);
eq(sug[0].id, 'D1', 'T8 exact dictionary name first');
eq(sug[0].band, 'exact', 'T8 band exact (no percentage)');
const bc = core.rankSuggestions('8901', [{ source: 'barcode', rows: items }, { source: 'dictionary', rows: dict }]);
eq([bc[0].id, bc[0].why], ['I1', 'barcode'], 'T8 barcode hit is the first suggestion');
const ocr = core.rankSuggestions('Sugr Bag', [{ source: 'label_text', rows: dict }]);
ok(ocr.length === 1 && ocr[0].id === 'D1' && ocr[0].band === 'close', 'T8 OCR text one letter off -> close match to the dictionary item');
ok(core.rankSuggestions('zzz', [{ source: 'dictionary', rows: dict }]).length === 0, 'T8 unrelated text -> no suggestion');
const same = core.rankSuggestions('Test Sugar Bag', [{ source: 'items', rows: items }, { source: 'dictionary', rows: [{ id: 'I1', code: 'test_cat-901', name_en: 'Test Sugar Bag' }] }]);
eq(same[0].sources.sort(), ['dictionary', 'items'], 'T8 the same item from two sources lists both sources');

// ---- T9 nearest neighbours (vector unit tests)
const idx = [{ item_id: 'A', vec: [1, 0, 0] }, { item_id: 'B', vec: [0, 1, 0] }, { item_id: 'C', vec: [0.9, 0.1, 0] }];
const r1 = core.nearest([1, 0, 0], idx, { k: 2, threshold: 0.2 });
eq(r1.hits.map((h) => h.item_id), ['A', 'C'], 'T9 nearest first, within threshold');
eq(r1.hits[0].distance, 0, 'T9 identical vector distance 0');
ok(r1.hits[1].distance > 0 && r1.hits[1].distance < 0.2, 'T9 distance is a number between 0 and the threshold');
eq(core.nearest([1, 0, 0], idx, { k: 5, threshold: null }).reason, 'threshold_not_set', 'T9 blank threshold -> no candidates shown');
eq(core.nearest([1, 0, 0], idx, { k: 5, threshold: 0.001 }).hits.map((h) => h.item_id), ['A'], 'T9 tight threshold keeps only the exact match');
eq(core.nearest([0, 0, 1], idx, { k: 5, threshold: 0.5 }).reason, 'no_match_within_threshold', 'T9 nothing within threshold is said plainly');
let thrown = false; try { core.nearest([1, 0], idx, { threshold: 0.5 }); } catch (e) { thrown = e.message === 'dim_mismatch'; } ok(thrown, 'T9 dimension mismatch throws');
eq(core.nearest([0, 0, 0], idx, { threshold: 0.5 }).reason, 'zero_vector', 'T9 zero query vector is refused');
eq(core.nearest([1, 0, 0], [{ item_id: 'Z', vec: [0, 0, 0] }], { threshold: 2 }).hits, [], 'T9 zero stored vector is skipped');

// ---- T10 photo rules
eq(core.validateFile({ type: 'image/jpeg', size: 1000 }), null, 'T10 small jpeg allowed');
eq(core.validateFile({ type: 'application/pdf', size: 1000 }), 'bad_type', 'T10 pdf refused');
eq(core.validateFile({ type: 'image/jpeg', size: 3145729 }), 'too_big', 'T10 over 3 MB refused');
eq(core.validateFile({ type: 'image/webp', size: 0 }), 'empty', 'T10 empty refused');
eq(core.fitSize(4000, 3000, 1280), { w: 1280, h: 960 }, 'T10 longest side fitted, aspect kept');
eq(core.fitSize(800, 600, 1280), { w: 800, h: 600 }, 'T10 never upscaled');

console.log('scan_core: ' + pass + ' pass, ' + fail + ' fail');
if (fail) process.exit(1);
