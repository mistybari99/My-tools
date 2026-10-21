// scan_b2_test.js = scan_test.js adapted to the phase108 Bangla-wording step and later registry/script appends (QA webfull). Only the listed assertions differ.
// Phase 90 / Scan: web/scan.js with a mocked rpc + storage (plain node, no browser): node tests/web/scan_test.js
// Covers: 3 languages (English mode has no Bangla letters), unique data-act names, ia.js + index.html lines, OCR text parser, payload + client checks,
// upload path / client id idempotency, offline queue, confirm key stability, error texts, no public URL, no secret in the Scan files, edge-function validator.
const fs = require('fs'), vm = require('vm'), path = require('path'), cp = require('child_process'), os = require('os');
const _P = require('./_paths');
const ROOT = _P.REPO_DIR;
const WEB = _P.WEB_DIR;
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৿]/;

function mk(lang, opt) {
  opt = opt || {};
  const calls = [], uploads = [], toasts = [], sheets = [], pages = [], handlers = {}, listeners = {};
  const rpcImpl = { fn: async () => ({ data: null, error: null }) }, upImpl = { fn: async () => ({ error: null }) };
  const A = { sb: { rpc: async (fn, args) => { calls.push([fn, args]); return rpcImpl.fn(fn, args); },
      storage: { from: () => ({ upload: async (p, b, o) => { uploads.push([p, b, o]); return upImpl.fn(p); }, createSignedUrl: async (p, s) => ({ data: { signedUrl: 'https://signed.example/' + p + '?t=1&s=' + s } }) }) },
      auth: { getSession: async () => ({ data: { session: { access_token: 'tok' } } }) } },
    S: { lang, ctx: { is_owner: true, roles: [], locations: [1], profile: { id: 'u1' } } },
    esc: (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), fail: (e) => toasts.push('FAIL:' + e.message), shell: (t, h, b) => pages.push([t, h, b]), openSheet: (h) => sheets.push(h), closeSheet: () => {}, H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const rules = Object.assign({ scan_enabled: true, scan_engine: 'manual', scan_min_confidence: 0.6 }, opt.rules || {});
  const B = { L, lab: (x) => (!x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en)), rule: (k, f) => (k in rules ? rules[k] : f), ENV: { locs: [{ id: 1, name_bn: 'মেইন', name_en: 'Main', name_mix: 'Main' }] }, liveLocs: (a) => a };
  const els = {};
  const document = { querySelector: (s) => els[s] || null, createElement: () => ({ click() {}, remove() {}, set textContent(v) { this._t = v; }, get textContent() { return this._t; } }), head: { appendChild() {} }, body: { appendChild() {} }, addEventListener: (t, f) => { (listeners[t] = listeners[t] || []).push(f); }, activeElement: null };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, location: { hash: '#/scan' }, addEventListener() {}, BOS_CONFIG: { url: 'https://x.supabase.co', key: 'pub' }, crypto: { randomUUID: (() => { let n = 0; return () => '00000000-0000-4000-8000-' + String(++n).padStart(12, '0'); })() } };
  const ctx = vm.createContext({ window: win, document, location: win.location, navigator: { onLine: true }, URL: { createObjectURL: () => 'blob:x', revokeObjectURL() {} }, Blob: function () {}, Image: function () {}, Response: function () {}, fetch: async () => ({ ok: true, json: async () => ({ ok: true }) }),
    crypto: win.crypto, setTimeout, clearTimeout, console, JSON, Math, Date, Promise, Object, Array, String, Number, Set, Map, Error, RegExp, Uint8Array, Boolean, isNaN, parseInt, parseFloat });
  vm.runInContext(fs.readFileSync(path.join(WEB, 'scan.js'), 'utf8'), ctx);
  return { A, B, calls, uploads, toasts, sheets, pages, handlers, rpcImpl, upImpl, els, S: B.scan, listeners, win, ctx };
}

(async () => {
  // ---- 1. languages ----
  {
    const t = mk('en'), X = t.S.X, keys = Object.keys(X);
    chk('all ' + keys.length + ' strings have bn, en and mix', keys.every((k) => X[k].bn && X[k].en && X[k].mix));
    chk('English text has no Bangla letters (all strings, incl. the taka sign)', keys.every((k) => !BN.test(X[k].en)));
    chk('Bangla text really is Bangla', keys.filter((k) => k !== 'qty' && !BN.test(X[k].bn)).length === 0);
    chk('mix text has Bangla and English together for the main labels', ['title', 'confirm', 'save', 'd_map', 'supplier'].every((k) => BN.test(X[k].mix) || /[A-Za-z]/.test(X[k].mix)));
    chk('English mode shows English', t.S.T('confirm') === 'Confirm' && /^Scan a bill/.test(t.S.T('title')));
    chk('Bangla mode shows Bangla', BN.test(mk('bn').S.T('save')));
    chk('the OCR weakness on Bangla / handwriting is said in the UI (all 3 modes)', /Bangla and handwriting/.test(X.eng_browser_ocr.en) && /হাতের লেখা/.test(X.eng_browser_ocr.bn) && /handwriting/.test(X.eng_browser_ocr.mix));
    chk('no placeholder left unfilled in a warning', t.S.T('w_unm').includes('{n}') && !/\{[a-z]\}/.test(String(t.S.T('confirm'))));
  }
  // ---- 2. wiring: data-act uniqueness, ia.js, index.html ----
  {
    const src = fs.readFileSync(path.join(WEB, 'scan.js'), 'utf8');
    const mine = new Set([...src.matchAll(/data-act="(\w+)"/g)].map((m) => m[1]).filter((a) => !['closesheet'].includes(a)));
    const keys = [...src.matchAll(/^\s{2}(scan_\w+):/gm)].map((m) => m[1]);
    chk('every data-act used is a handler defined in scan.js', [...mine].every((a) => keys.includes(a)));
    chk('all handler names are prefixed scan_ (' + keys.length + ')', keys.length >= 15 && keys.every((k) => k.startsWith('scan_')));
    const others = fs.readdirSync(WEB).filter((f) => f.endsWith('.js') && f !== 'scan.js').map((f) => [f, fs.readFileSync(path.join(WEB, f), 'utf8')]);
    const clash = keys.filter((k) => others.some(([f, s]) => f !== 'itemimg.js' && new RegExp('\\b' + k + '\\b').test(s)));
    chk('no handler / data-act name used by any other web file', clash.length === 0);
    const idx = fs.readFileSync(path.join(WEB, 'index.html'), 'utf8');
    chk('index.html loads scan.js once, after the existing scripts (after twofa.js, after stock2.js)', (idx.match(/<script src="scan\.js"><\/script>/g) || []).length === 1 && idx.indexOf('scan.js') > idx.indexOf('twofa.js') && idx.indexOf('scan.js') > idx.indexOf('stock2.js'));
    const ia = fs.readFileSync(path.join(WEB, 'ia.js'), 'utf8'), m = ia.match(/rec\('scan',\s*'purch',\s*\[\s*'([^']*)',\s*'([^']*)',\s*'([^']*)'/);
    chk('ia.js has the scan rec line with 3 titles; English title has no Bangla', !!m && !BN.test(m[2]) && BN.test(m[1]));
    chk('ia.js scan line comes after the purchase lines and the existing text is untouched (diff is one added line)', ia.indexOf("rec('scan'") > ia.indexOf("rec('purchase/return'"));
    const t = mk('en'); chk('page registered as BOS_PAGES.scan', typeof t.win.BOS_PAGES.scan === 'function');
    chk('Scan never builds a public storage URL and never uses a service_role key', !/getPublicUrl|service_role/i.test(src) && /createSignedUrl/.test(src));
    chk('the OCR library is pinned to an exact version on an allowed CDN', /cdn\.jsdelivr\.net\/npm\/tesseract\.js@\d+\.\d+\.\d+\/dist\/tesseract\.min\.js/.test(src));
    chk('file input offers camera and gallery (accept image/*, capture)', /accept="image\/\*" capture="environment"/.test(src) && /type="file" accept="image\/\*" id="sc_gal"/.test(src));
  }
  // ---- 3. secrets: nothing key-like in the files this feature adds ----
  {
    const files = ['web/scan.js', 'supabase/phase90.sql', 'supabase/functions/scan-extract/index.ts', 'docs/SCAN_SETUP.md'].map((f) => [f, fs.readFileSync(path.join(ROOT, f), 'utf8')]);
    chk('no API key / JWT shaped text in any Scan file', files.every(([f, s]) => !/sk-ant-[A-Za-z0-9_-]{10,}|eyJ[A-Za-z0-9_-]{20,}\.|AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9]{30,}/.test(s)));
    const ed = files[2][1];
    chk('edge function reads its key only from secrets, never uses service_role, forwards the user login', /Deno\.env\.get\("ANTHROPIC_API_KEY"\)/.test(ed) && !/SERVICE_ROLE/i.test(ed.replace(/service_role key is never used[^\n]*/i, '')) && /global: \{ headers: \{ Authorization: auth \}/.test(ed));
  }
  // ---- 4. OCR text parser ----
  {
    const S = mk('en').S;
    const bill = ['Alpha Traders', 'Invoice No: B-100', 'Date: 12/10/2026', 'Sugar 50kg  2 kg  500  1000', 'Flour  1 kg  150.25  150.25', 'Discount: 50', 'Grand Total: 1,100.25'].map((t, i) => ({ text: t, confidence: i === 4 ? 40 : 90 }));
    const p = S.parseOcr('purchase_bill', { lines: bill });
    chk('OCR bill: supplier, bill no, date, discount, total', p.extracted.supplier.name === 'Alpha Traders' && p.extracted.bill_no === 'B-100' && p.extracted.date === '12/10/2026' && p.extracted.discount === '50' && p.extracted.total === '1100.25');
    chk('OCR bill: two full lines with qty / unit / rate / amount', p.extracted.lines.length === 2 && p.extracted.lines[0].desc === 'Sugar 50kg' && p.extracted.lines[0].qty === '2' && p.extracted.lines[0].unit === 'kg' && p.extracted.lines[0].unit_cost === '500' && p.extracted.lines[0].amount === '1000');
    chk('OCR bill: low line confidence is carried to the line fields (0.4) and a high one stays', p.confidence.lines[1].unit_cost < 0.6 && p.confidence.lines[0].unit_cost > 0.6);
    chk('OCR output never carries an item id, supplier id or decision', !/item_id|decision|"id"/.test(JSON.stringify(p)));
    const e = S.parseOcr('expense', { text: 'City Transport\n2026-10-12\nRickshaw hire 120\nTotal 350' });
    chk('OCR expense: amount from the total line, paid to = first line, date', e.extracted.amount === '350' && e.extracted.paid_to === 'City Transport' && e.extracted.date === '2026-10-12');
    const pl = S.parseOcr('product_list', { text: 'Rasgulla 1kg 480\nChomchom 1kg 520\nTotal items 2' });
    chk('OCR product list: name + price per line, the total line is skipped', pl.extracted.lines.length === 2 && pl.extracted.lines[1].price === '520' && pl.extracted.lines[0].desc.startsWith('Rasgulla'));
    chk('OCR of an empty photo gives an empty draft, not an error', S.parseOcr('purchase_bill', { text: '' }).extracted.lines.length === 0);
    chk('Bangla digits in OCR text are read', S.parseOcr('expense', { text: 'বাস ভাড়া\nTotal ৫০০' }).extracted.amount === '500');
  }
  // ---- 5. payload + client checks ----
  {
    const S = mk('en').S;
    S._set({ kind: 'purchase_bill', id: 'j' }, { supplier: { name: 'Alpha', id: 's1' }, bill_no: ' B-1 ', date: '2026-10-12', note: '', lines: [{ desc: 'Sugar', qty: '2', unit_cost: '500', decision: 'map', item_id: 'i1' }, { desc: '', qty: '', unit: '' }, { desc: 'x', decision: 'skip' }] });
    const p = S.payload();
    chk('payload drops empty strings and empty lines, keeps skipped line and decisions', p.lines.length === 2 && p.lines[0].item_id === 'i1' && p.lines[1].decision === 'skip' && !('note' in p));
    chk('check: purchase needs supplier / date / a line', S.check({}, 'purchase_bill') === S.T('needSup') && S.check({ supplier: { name: 'A' } }, 'purchase_bill') === S.T('needSup') && S.check({ supplier: { id: 's' } }, 'purchase_bill') === S.T('needDate') && S.check({ supplier: { id: 's' }, date: '2026-10-12', lines: [{}] }, 'purchase_bill') === null);
    chk('check: a new supplier needs the explicit create flag + a name', S.check({ supplier: { name: 'New', create: true }, date: '2026-10-12', lines: [{}] }, 'purchase_bill') === null);
    chk('check: expense needs date, head, positive amount', S.check({ date: '2026-10-12', head: 'fuel', amount: '0' }, 'expense') === S.T('e_bad_amount') && S.check({ date: '2026-10-12', head: 'fuel', amount: '900' }, 'expense') === null);
    S._set({ kind: 'expense', id: 'j' }, { head: 'fuel', amount: '9', lines: [{ desc: 'junk' }] });
    chk('expense payload carries no lines', !('lines' in S.payload()));
    // confidence highlight: low AND unchanged only
    const t = mk('en'); t.S.D.cfg = { minc: 0.6 };
    t.S._set({ kind: 'purchase_bill' }, { bill_no: 'B-1', total: '100', lines: [{ qty: '2' }] });
    t.S.D.ex = { bill_no: 'B-1', total: '100', lines: [{ qty: '2' }] }; t.S.D.conf = { bill_no: 0.3, total: 0.4, lines: [{ qty: 0.2 }] };
    t.S.D.ed.total = '120';
    chk('highlight: unchanged low field is yellow, an edited low field is not, a line field works', t.S.isLow('bill_no') === true && t.S.isLow('total') === false && t.S.isLow('qty', 0) === true);
  }
  // ---- 6. upload path + idempotency + offline queue ----
  {
    const t = mk('en'); const blob = { size: 5 };
    t.rpcImpl.fn = async (fn, a) => ({ data: { id: 'job-1', status: 'uploaded', engine: 'manual' }, error: null });
    const en = { client: 'c-aaaa', kind: 'purchase_bill', loc: 1, hash: 'ab'.repeat(32), blob, ts: 1 };
    const job = await t.S.send(en);
    chk('upload goes to the PRIVATE photos bucket at SCAN/<place>/<client id>.jpg as image/jpeg', t.uploads[0][0] === 'SCAN/1/c-aaaa.jpg' && t.uploads[0][2].contentType === 'image/jpeg' && t.uploads[0][2].upsert === false);
    chk('scan_create gets the same client id, kind, place, path and the hash', t.calls[0][0] === 'scan_create' && t.calls[0][1].p_client === 'c-aaaa' && t.calls[0][1].p_image_path === 'SCAN/1/c-aaaa.jpg' && t.calls[0][1].p_kind === 'purchase_bill' && t.calls[0][1].p_loc === 1 && t.calls[0][1].p_image_hash.length === 64 && job.id === 'job-1');
    t.upImpl.fn = async () => ({ error: { message: 'The resource already exists', statusCode: '409' } });
    await t.S.send(en);
    chk('a re-send after a lost answer: "already exists" is fine, the same client id is sent again (server returns the same job)', t.calls.length === 2 && t.calls[1][1].p_client === 'c-aaaa');
    t.upImpl.fn = async () => ({ error: { message: 'new row violates row-level security policy' } });
    let threw = false; try { await t.S.send(en); } catch (e) { threw = true; }
    chk('a real storage refusal is raised (not hidden)', threw);
  }
  {
    const t = mk('en'); const en = { client: 'c-q1', kind: 'expense', loc: 1, hash: null, blob: { size: 1 }, ts: 1 };
    await t.S.qput(en); await t.S.qput(Object.assign({}, en, { client: 'c-q2' })); await t.S.qput(Object.assign({}, en, { client: 'c-q1' }));
    chk('offline queue keeps one entry per client id (memory fallback when IndexedDB is unavailable)', (await t.S.qall()).length === 2);
    t.upImpl.fn = async () => ({ error: { message: 'TypeError: Failed to fetch' } });
    const n0 = await t.S.flushQueue(true);
    chk('still offline: nothing is sent, nothing is lost', n0 === 0 && (await t.S.qall()).length === 2);
    t.upImpl.fn = async () => ({ error: null }); t.rpcImpl.fn = async () => ({ data: { id: 'j-' + t.calls.length, engine: 'manual' }, error: null });
    const n1 = await t.S.flushQueue(true);
    chk('back online: both are sent once and the queue empties', n1 === 2 && (await t.S.qall()).length === 0 && t.calls.filter((c) => c[0] === 'scan_create').length === 2);
    t.rpcImpl.fn = async () => ({ data: null, error: { message: 'scan_off' } });
    await t.S.qput(en); await t.S.flushQueue(true);
    chk('a business refusal (scan_off) is not retried forever: the entry leaves the queue', (await t.S.qall()).length === 0);
  }
  // ---- 7. confirm: one key per sheet, double tap, error text, ack ----
  {
    const t = mk('en'); const D = t.S.D;
    D.job = { id: 'j1', kind: 'expense', can_confirm: true, status: 'reviewed' }; D.ed = { head: 'fuel', amount: '900', date: '2026-10-12' }; D.cfg = { minc: 0.6, engine: 'manual' };
    t.rpcImpl.fn = async (fn) => (fn === 'scan_review_save' ? { data: { status: 'reviewed', dups: [{ type: 'quick_expense' }], warnings: [] }, error: null } : fn === 'scan_get' ? { data: { id: 'j1', kind: 'expense', status: 'confirmed', events: [] }, error: null } : { data: null, error: { message: 'duplicate_suspect: [...]' } });
    await t.handlers.scan_done({});
    chk('Done saves with final=true and opens the confirm sheet with a duplicate acknowledgement box', t.calls[0][0] === 'scan_review_save' && t.calls[0][1].p_final === true && t.calls[0][1].p_id === 'j1' && /sc_ack/.test(t.sheets[0]) && /Possible duplicate/.test(t.sheets[0]));
    await t.handlers.scan_confirm_go({});
    const c1 = t.calls.filter((c) => c[0] === 'scan_confirm')[0][1];
    chk('first confirm call: p_ack_dup false, no post, a client key', c1.p_id === 'j1' && c1.p_ack_dup === false && c1.p_post === false && !!c1.p_client);
    chk('the server refusal shows a friendly English text (not the raw code)', t.toasts.some((m) => /Looks like a duplicate/.test(m)));
    t.els['#sc_ack'] = { checked: true };
    t.rpcImpl.fn = async (fn) => (fn === 'scan_confirm' ? { data: { status: 'confirmed' }, error: null } : { data: { id: 'j1', kind: 'expense', status: 'confirmed', events: [] }, error: null });
    await t.handlers.scan_confirm_go({});
    const cs = t.calls.filter((c) => c[0] === 'scan_confirm');
    chk('retry after the refusal uses the SAME client key (a double tap / retry can never post twice) and now carries the acknowledgement', cs.length === 2 && cs[1][1].p_client === c1.p_client && cs[1][1].p_ack_dup === true);
    // a user without the confirm right only gets "sent for confirmation"
    const u = mk('en'); u.S.D.job = { id: 'j2', kind: 'expense', can_confirm: false, status: 'extracted' }; u.S.D.ed = { head: 'fuel', amount: '9', date: '2026-10-12' }; u.S.D.cfg = { minc: 0.6, engine: 'manual' };
    u.rpcImpl.fn = async (fn) => (fn === 'scan_review_save' ? { data: { status: 'reviewed', dups: [], warnings: [] }, error: null } : { data: { id: 'j2', kind: 'expense', status: 'reviewed', events: [] }, error: null });
    await u.handlers.scan_done({});
    chk('without the confirm right: saved as reviewed, no confirm sheet, no scan_confirm call', u.calls.filter((c) => c[0] === 'scan_confirm').length === 0 && u.sheets.length === 0 && u.toasts.some((m) => /Sent for confirmation/.test(m)));
    // incomplete drafts are stopped before any call
    const v = mk('en'); v.S.D.job = { id: 'j3', kind: 'purchase_bill', can_confirm: true }; v.S.D.ed = { supplier: { name: 'X' }, date: '2026-10-12', lines: [{ desc: 'a' }] }; v.S.D.cfg = { minc: 0.6, engine: 'manual' };
    await v.handlers.scan_done({});
    chk('unmapped supplier is stopped on the phone with a clear message, no server call', v.calls.length === 0 && v.toasts.includes('Choose a supplier'));
    // reject needs a reason
    const r = mk('en'); r.S.D.job = { id: 'j4', kind: 'other' }; r.els['#sc_why'] = { value: 'x' };
    await r.handlers.scan_reject_go({});
    chk('reject: a too-short reason is stopped on the phone', r.calls.length === 0);
  }
  // ---- 8. errors in 3 languages + old database ----
  {
    for (const lang of ['en', 'bn', 'mix']) {
      const S = mk(lang).S;
      chk('error texts (' + lang + '): known codes translated, unknown shown raw', S.errText({ message: 'already_confirmed' }) !== 'already_confirmed' && S.errText({ message: 'unmatched_lines' }) !== 'unmatched_lines' && S.errText({ message: 'duplicate_suspect: [{"a":1}]' }) !== 'duplicate_suspect: [{"a":1}]' && S.errText({ message: 'something odd' }) === 'something odd');
      chk('error text (' + lang + '): old database without phase90', S.errText({ message: 'Could not find the function public.scan_list in the schema cache' }) === S.T('nodb'));
    }
    chk('English error texts have no Bangla', !BN.test(mk('en').S.errText({ message: 'supplier_not_mapped' })));
  }
  // ---- 9. the list page: off switch, engine note ----
  {
    const t = mk('en', { rules: { scan_enabled: false } }); t.rpcImpl.fn = async () => ({ data: [], error: null });
    t.els['#sc_body'] = { innerHTML: '' }; await t.S.view();
    chk('switch OFF: the page says so and offers no camera', /switched off/.test(t.els['#sc_body'].innerHTML) && !/sc_cam/.test(t.els['#sc_body'].innerHTML));
    const o = mk('en', { rules: { scan_engine: 'browser_ocr' } }); o.rpcImpl.fn = async () => ({ data: [{ id: 'a', kind: 'expense', status: 'uploaded', created_at: '2026-10-12T10:00:00', created_staff: 'S1', dups: 0 }], error: null });
    o.els['#sc_body'] = { innerHTML: '' }; await o.S.view();
    const h = o.els['#sc_body'].innerHTML;
    chk('browser_ocr: camera + gallery inputs, the weakness note, the list row with an Open button', /sc_cam/.test(h) && /sc_gal/.test(h) && /Weak on Bangla and handwriting/.test(h) && /data-act="scan_open"/.test(h));
    chk('English page has no Bangla letters', !BN.test(h.replace(/৳/g, '')));
    const m = mk('bn'); m.rpcImpl.fn = async () => ({ data: [], error: null }); m.els['#sc_body'] = { innerHTML: '' }; await m.S.view();
    chk('Bangla page renders', BN.test(m.els['#sc_body'].innerHTML));
  }
  // ---- 10. edge-function validator (pure part, run through node type stripping) ----
  {
    const src = fs.readFileSync(path.join(ROOT, 'supabase/functions/scan-extract/index.ts'), 'utf8');
    const a = src.indexOf('const MAX_BYTES'), b = src.indexOf('const FIELDS');
    const tmp = path.join(os.tmpdir(), 'scan_validate_' + process.pid + '.mts');
    fs.writeFileSync(tmp, src.slice(a, b));
    let V = null; try { V = (await import(tmp)).validate; } catch (e) { console.log('skip typed import:', e.message); }
    if (V) {
      const raw = { fields: { supplier_name: 'Alpha Traders', bill_no: 'B-9', date: '2026-10-12', discount: '5,0', total: 'abc', evil: 'x' }, field_confidence: { supplier_name: 7, bill_no: -2, date: 0.5 },
        lines: [{ description: 'Sugar', qty: '2', unit: 'kg', unit_cost: 500, amount: '1000', item_id: 'steal', confidence: { qty: 0.2 } }, 'junk', { qty: '-3' }, { description: 'x'.repeat(500) }] };
      const r = V('purchase_bill', raw);
      chk('edge validator: strict types, bad total dropped, unknown keys + item_id dropped, comma number cleaned (50)', r.extracted.supplier.name === 'Alpha Traders' && !('total' in r.extracted) && r.extracted.discount === '50' && !JSON.stringify(r).includes('steal') && !('evil' in r.extracted));
      chk('edge validator: confidence clamped 0..1, per-line confidence kept, a line with only a negative qty is dropped, long text cut to 200', r.confidence.supplier === 1 && r.confidence.bill_no === 0 && r.confidence.lines[0].qty === 0.2 && r.extracted.lines.length === 2 && r.extracted.lines[1].desc.length === 200);
      let threw = false; try { V('expense', null); } catch (e) { threw = true; }
      chk('edge validator: non-object model output is refused', threw);
      chk('edge validator: more than 200 lines are cut', V('product_list', { fields: {}, lines: Array.from({ length: 500 }, () => ({ description: 'a' })) }).extracted.lines.length === 200);
      chk('edge validator: an expense has no lines and a head is cut to 30', !('lines' in V('expense', { fields: { head: 'h'.repeat(80), amount: '350' }, lines: [{}] }).extracted));
    }
    try { fs.unlinkSync(tmp); } catch (e) { /* ignore */ }
  }
  console.log('scan_test: ' + pass + ' pass / ' + failn + ' fail');
  process.exit(failn ? 1 : 0);
})();
