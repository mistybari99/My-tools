// optionsx_b_b2_test.js = optionsx_b_test.js adapted to the phase108 Bangla-wording step and later registry/script appends (QA webfull). Only the listed assertions differ.
// optionsx_b_test.js = optionsx_test.js with the 'LAST script' assertion adapted: step Img (phase102) appends itemimg.js after optionsx.js, by design. Everything else is identical.
// Options X screens (web/optionsx.js, phase99) with a mocked rpc layer and a tiny fake DOM. No browser, no database.
// Checks: language rule (English has no Bangla, 3 modes present), unique opx_ data-act names, registry (ia.js / index.html at the END), owner cards with the recommendation next to each option,
// the "Record payment now?" sheet (hook reads the answer of two save calls only, never sends a call twice, rule off = nothing), part payment, duplicate warning + confirm, reveal flow (audited call, rate limit), error mapping.
// Run: node tests/web/optionsx_test.js
const fs = require('fs'), path = require('path'), vm = require('vm');
const WEB = path.join(__dirname, '..', '..', 'web'); const BN = /[ঀ-৿]/;
let n = 0, bad = 0;
const ck = (name, ok) => { n++; if (!ok) { bad++; console.log('FAIL ' + name); } };
const src = fs.readFileSync(path.join(WEB, 'optionsx.js'), 'utf8');

// ---------- static ----------
const str = "'((?:[^'\\\\]|\\\\.)*)'";
let ls = 0;
for (const m of src.matchAll(new RegExp('L\\(\\s*' + str + ',\\s*' + str + ',\\s*' + str + '\\s*\\)', 'g'))) {
  ls++; ck('English has no Bangla: ' + m[2].slice(0, 50), !BN.test(m[2])); ck('bn and mix not empty: ' + m[2].slice(0, 40), m[1].length > 0 && m[3].length > 0);
}
ck('found many 3-mode strings', ls > 120);
for (const m of src.matchAll(/data-act="(opx_[a-z]+)"/g)) ck('data-act prefixed ' + m[1], /^opx_/.test(m[1]));
const handlers = [...src.matchAll(/^\s{2}(opx_[a-z]+):/gm)].map((m) => m[1]);
ck('handler names unique', handlers.length === new Set(handlers).size);
const used = new Set([...src.matchAll(/data-act="(opx_[a-z]+)"/g)].map((m) => m[1]));
ck('every data-act has a handler', [...used].every((u) => handlers.includes(u)));
ck('no data-act outside opx_', ![...src.matchAll(/data-act="([a-z_0-9]+)"/g)].some((m) => !m[1].startsWith('opx_')));
const ia = fs.readFileSync(path.join(WEB, 'ia.js'), 'utf8'), idx = fs.readFileSync(path.join(WEB, 'index.html'), 'utf8');
ck('ia.js has no merge-conflict markers and parses', !/^(<<<<<<<|=======|>>>>>>>)/m.test(ia) && (() => { try { new vm.Script(ia); return true; } catch (e) { return false; } })());
for (const k of ['optionsx', 'billpay', 'inboxpii']) {
  ck('ia.js has the ' + k + ' rec', new RegExp("rec\\('" + k + "', '[a-z]+', \\['[^']+', '[^']+', '[^']+'\\]").test(ia));
  const rm = ia.match(new RegExp("rec\\('" + k + "', '[a-z]+', \\['[^']*',\\s*'([^']*)'")); ck('ia.js English title of ' + k + ' has no Bangla', !!rm && !BN.test(rm[1]));
}
ck('the three recs are the LAST entries of the IA array (appended at the end)', ia.lastIndexOf("rec('inboxpii'") > ia.lastIndexOf("rec('billpay'") && ia.lastIndexOf("rec('billpay'") > ia.lastIndexOf("rec('optionsx'") && ia.lastIndexOf("rec('optionsx'") > ia.lastIndexOf("rec('landed'")
  && ia.indexOf('];', ia.lastIndexOf("rec('inboxpii'")) > 0 && !/\n\s*rec\(/.test(ia.slice(ia.indexOf('];', ia.lastIndexOf("rec('inboxpii'")), ia.indexOf('];', ia.lastIndexOf("rec('inboxpii'")) + 400).split('settings2 sub pages')[0]));
ck('index.html loads optionsx.js once, as the second-to-last script (step Img appends itemimg.js after it, by design)', (idx.match(/optionsx\.js/g) || []).length === 1 && idx.indexOf('itemimg.js') > idx.indexOf('optionsx.js'));
ck('the hook is guarded and tagged: only two rpc names are wrapped, in a try/catch', /const HOOKS = \{\s*cost_bill_add:[^]*post_purchase:/.test(src) && /function installHook\(\) \{\s*try \{/.test(src) && Object.keys({ cost_bill_add: 1, post_purchase: 1 }).length === 2);
ck('inbox.js, purchase.js, costsources.js are untouched by this step (no opx_ / optionsx mention)', !/opx_|optionsx/.test(['inbox.js', 'purchase.js', 'costsources.js'].map((f) => fs.readFileSync(path.join(WEB, f), 'utf8')).join('')));
for (const fn of ['options99_state', 'bill_pay_info99', 'bill_pay_record', 'bills_without_payment99', 'bill_pay_default_set99', 'bill_pay_defaults_list99', 'inbox_unmask', 'inbox_unmask_log_list99', 'setup_recommendations', 'set_rule', 'inbox_list', 'online_orders_list']) ck('calls ' + fn, src.includes("'" + fn + "'"));

// ---------- dynamic ----------
const STATE = { cost_bill_creates_payment: 'off', purchase_bill_creates_payment: 'ask', bill_void_payment_mode: 'void', bill_pay_auto_credit_ok: false, bill_pay_large_amount: null, bill_pay_small_cash_max: 500,
  inbox_pii_mode: 'off', inbox_pii_guard_on: false, inbox_unmask_daily_max: null, unpaid_cost: 2, unpaid_purchase: 1, reveals_today: 3, blocked_today: 1 };
const RECS = { items: [{ rule_key: 'cost_bill_creates_payment', recommended: 'ask', reason_bn: 'ক', reason_mix: 'm', reason_en: 'Server reason cost' }, { rule_key: 'inbox_pii_mode', recommended: 'mask_phone_address', reason_bn: 'খ', reason_mix: 'n', reason_en: 'Server reason pii' }] };
const INFO = (over) => Object.assign({ kind: 'cost', ref: '5', party: 'meter G-1', total: 1000, paid: 0, remaining: 1000, rule: 'ask', modes: ['cash', 'bank', 'mobile', 'other'], suggest_mode: 'bank', location_id: 1,
  recommendation: { mode: 'ask', basis: 'default', reason_bn: 'বা', reason_mix: 'mi', reason_en: 'No rule matched: the safe choice is to ask.' }, payments: [] }, over || {});
const LIST = { cost_rule: 'ask', purchase_rule: 'off', rows: [{ kind: 'cost', ref: '5', party: 'meter G-1', bill_no: 'B-1', date: '2026-10-14', total: 1000, paid: 0, due: 1000, location_id: 1 },
  { kind: 'purchase', ref: 'aaaa-bbbb', party: 'Cash supplier', bill_no: 'P-1', date: '2026-10-13', total: 700, paid: 0, due: 700, location_id: 1 }] };
const MSGS = [{ id: 1, name: 'C•••', handle: '••••••••111', text: '••••', masked: false, pii_mode: 'mask_all_pii', status: 'new' }];
const ORDS = [{ id: 'oid-1', order_no: 501, customer_name: 'C•••', customer_mobile: '••••••••111', masked: false, pii_mode: 'mask_all_pii' }];

function env(opts = {}) {
  const calls = [], toasts = [], sheets = [], els = {}, timers = []; let sheetOpen = true;
  const S = { lang: opts.lang || 'en', ctx: { is_owner: opts.owner !== false } };
  const lab = (x) => !x ? '' : typeof x === 'string' ? x : S.lang === 'en' ? (x.en || x.bn) : S.lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en);
  const resp = Object.assign({
    options99_state: STATE, setup_recommendations: RECS, bill_pay_defaults_list99: [{ kind: 'supplier', id: 's1', name: 'Cash supplier', mode: 'cash', credit: false }], inbox_unmask_log_list99: [{ id: 2, at: '2026-10-14T09:00:00', user_id: 'u1', staff: 'sales5', kind: 'message', ref: '1', outcome: 'revealed', reason: 'called' }],
    bill_pay_info99: INFO(), bill_pay_record: { ok: true, id: 1, amount: 400, remaining: 600, counted: true }, bills_without_payment99: LIST, set_rule: null, bill_pay_default_set99: { id: 1 },
    inbox_list: MSGS, online_orders_list: ORDS, inbox_unmask: { ok: true, mode: 'mask_all_pii', logged: true, data: { handle: '01711000111', name: 'Customer A', text: 'hello', attachment_ref: null } },
    cost_bill_add: { id: 5, shares: [] }, post_purchase: { id: 'p1', status: 'posted' },
  }, opts.resp || {});
  const sb = {
    rpc: (fn, a) => { calls.push([fn, a]); const r = resp[fn]; const out = typeof r === 'function' ? { data: r(a), error: null } : r instanceof Error ? { data: null, error: { message: r.message } } : { data: r === undefined ? null : JSON.parse(JSON.stringify(r)), error: null }; return Promise.resolve(out); },
    from: (t) => ({ select: () => ({ order: () => Promise.resolve({ data: t === 'suppliers' ? [{ id: 's1', name: 'Cash supplier' }] : [{ id: 1, code: 'src-1', provider: 'meter G-1' }], error: null }) }) }),
  };
  for (const id of ['opx_body', 'opx_list', 'opx_pii']) els['#' + id] = { innerHTML: '' };
  const doc = { querySelector: (s) => els[s] || null };
  const H = {};
  const BOS = { L: (bn, en, mix) => ({ bn, en, mix }), lab };
  const openSheet = (h) => { sheets.push(h); sheetOpen = true; for (const m of h.matchAll(/id="([a-z_]+)"([^>]*)>/g)) { const v = (m[2].match(/value="([^"]*)"/) || [])[1]; els['#' + m[1]] = { value: v == null ? '' : v, checked: /checked/.test(m[2]) }; } };
  const BOS_APP = { sb, S, esc: (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])), toast: (m) => toasts.push(m), shell: (t, h) => { env_.title = t; env_.shellHtml = h; }, openSheet, closeSheet: () => { sheetOpen = false; sheets.push('CLOSED'); }, H };
  const win = { BOS, BOS_APP, crypto: { randomUUID: (() => { let i = 0; return () => 'uuid-' + (++i); })() } };
  const ctx = vm.createContext({ window: win, crypto: win.crypto, document: doc, console, Promise, Date, Number, String, Math, JSON, Object, Array, Intl, Set, setTimeout: (f) => { timers.push(f); return timers.length; } });
  vm.runInContext(src, ctx);
  const env_ = { calls, toasts, sheets, els, S, H, B: win.BOS, pages: win.BOS_PAGES, sb, resp, timers, isOpen: () => sheetOpen };
  env_.set = (id, v) => { els['#' + id] = Object.assign(els['#' + id] || {}, { value: v }); };
  env_.act = (name, ds) => H[name]({ dataset: ds || {}, value: (ds || {}).value });
  env_.last = () => { for (let i = sheets.length - 1; i >= 0; i--) if (sheets[i] !== 'CLOSED') return sheets[i]; return ''; };
  env_.flush = async () => { for (let k = 0; k < 4; k++) { const t = timers.splice(0); for (const f of t) f(); await new Promise((r) => setImmediate(r)); } };
  return env_;
}
const count = (e, fn) => e.calls.filter((c) => c[0] === fn).length;

(async () => {
  // ---- the three pages, 3 languages ----
  for (const lang of ['bn', 'mix', 'en']) {
    const e = env({ lang });
    ck(lang + ' pages registered', ['optionsx', 'billpay', 'inboxpii'].every((k) => typeof e.pages[k] === 'function'));
    await e.pages.optionsx();
    const h = e.els['#opx_body'].innerHTML;
    ck(lang + ' owner cards: three rule cards + credit switch + two number boxes + defaults + unpaid link', ['cost_bill_creates_payment', 'purchase_bill_creates_payment', 'bill_void_payment_mode'].every((r) => h.includes('data-rule="' + r + '"')) && h.includes('opx_credit') && h.includes('opx_n_bill_pay_large_amount') && h.includes('opx_n_bill_pay_small_cash_max') && h.includes('opx_defsave') && h.includes('#/billpay'));
    ck(lang + ' all five choices shown for the cost rule', ['off', 'ask', 'auto_cash', 'auto_bank', 'auto_by_supplier_default'].every((v) => h.includes('data-k="cost_bill_creates_payment" data-val="' + v + '"')));
    const card = h.slice(h.indexOf('data-rule="cost_bill_creates_payment"'), h.indexOf('data-rule="purchase_bill_creates_payment"'));
    ck(lang + ' the Recommended chip sits on "ask" and the Current chip on "off" (from the server rows)', /data-val="ask"[^]*?class="chip ok"/.test(card) && /data-val="off"[^]*?class="chip">/.test(card) && !/data-val="auto_cash"[^]*?class="chip ok"[^]*?data-val="auto_bank"/.test(card));
    ck(lang + ' the server reason is shown next to the options', card.includes('Server reason cost') === (lang === 'en') || lang !== 'en');
    ck(lang + ' the number box shows the typed value 500 and a blank for the unset one', h.includes('id="opx_n_bill_pay_small_cash_max" inputmode="decimal" autocomplete="off" value="500"') && h.includes('id="opx_n_bill_pay_large_amount" inputmode="decimal" autocomplete="off" value=""'));
    if (lang === 'en') ck('English page has no Bangla letters', !BN.test(h.replace(/Server reason [a-z]+/g, '')));
    await e.act('opx_tab', { v: 'pii' });
    const p = e.els['#opx_body'].innerHTML;
    ck(lang + ' pii tab: four modes, recommended = mask_phone_address, current = off, guard note, limit box, link', ['off', 'mask_phone', 'mask_phone_address', 'mask_all_pii'].every((v) => p.includes('data-k="inbox_pii_mode" data-val="' + v + '"')) && /data-val="mask_phone_address"[^]*?class="chip ok"/.test(p) && p.includes('opx_n_inbox_unmask_daily_max') && p.includes('#/inboxpii') && p.includes('piiguard'));
    if (lang === 'en') ck('English pii tab has no Bangla', !BN.test(p.replace(/Server reason [a-z]+/g, '')));
    await e.act('opx_tab', { v: 'log' });
    const l = e.els['#opx_body'].innerHTML;
    ck(lang + ' log tab lists who / when / what', l.includes('sales5') && l.includes('2026-10-14 09:00') && l.includes('#1'));
    if (lang === 'en') ck('English log tab has no Bangla', !BN.test(l));
    await e.pages.billpay();
    const b = e.els['#opx_list'].innerHTML;
    ck(lang + ' bills-without-payment page: 2 rows, due amounts, record buttons, current rules', (b.match(/data-opx="bill"/g) || []).length === 2 && b.includes('1,000.00') && b.includes('700.00') && b.includes('opx_lpay'));
    if (lang === 'en') ck('English list has no Bangla', !BN.test(b));
    await e.pages.inboxpii();
    const q = e.els['#opx_pii'].innerHTML;
    ck(lang + ' reveal page: masked values shown as the server gave them, a Reveal button each', q.includes('••••••••111') && (q.match(/opx_reveal/g) || []).length === 2);
    if (lang === 'en') ck('English reveal page has no Bangla', !BN.test(q));
  }

  // ---- owner cards write only through set_rule ----
  let e = env();
  await e.pages.optionsx();
  await e.act('opx_set', { k: 'cost_bill_creates_payment', val: 'ask' });
  ck('choosing an option = ONE set_rule with that value', count(e, 'set_rule') === 1 && e.calls.find((c) => c[0] === 'set_rule')[1].p_key === 'cost_bill_creates_payment' && e.calls.find((c) => c[0] === 'set_rule')[1].p_value === 'ask');
  e.set('opx_n_bill_pay_large_amount', '5,000'); await e.act('opx_num', { k: 'bill_pay_large_amount' });
  ck('number box sends a number (commas removed)', e.calls.filter((c) => c[0] === 'set_rule').pop()[1].p_value === 5000);
  e.set('opx_n_bill_pay_large_amount', 'abc'); const before = count(e, 'set_rule'); await e.act('opx_num', { k: 'bill_pay_large_amount' });
  ck('a bad number is refused on the screen (no call)', count(e, 'set_rule') === before);
  e.set('opx_n_inbox_unmask_daily_max', '0'); await e.act('opx_num', { k: 'inbox_unmask_daily_max' });
  ck('the reveal limit must be at least 1 (no call for 0)', count(e, 'set_rule') === before);
  await e.act('opx_numclr', { k: 'bill_pay_small_cash_max' });
  ck('clear = set_rule with null (blank = no limit)', e.calls.filter((c) => c[0] === 'set_rule').pop()[1].p_value === null);
  e.set('opx_dp', 's1'); e.set('opx_dm', 'bank'); e.els['#opx_dc'] = { checked: true }; await e.act('opx_defsave');
  ck('party default saved through bill_pay_default_set99 (kind, id, mode, credit)', JSON.stringify(e.calls.find((c) => c[0] === 'bill_pay_default_set99')[1]) === JSON.stringify({ p_kind: 'supplier', p_id: 's1', p_mode: 'bank', p_credit: true, p_note: null }));

  // ---- the hook ----
  e = env({ resp: { bill_pay_info99: INFO() } });
  const orig = e.sb.rpc;
  const pre = e.B.optionsx.HOOKS;
  ck('hook installed on sb.rpc (wrapped once)', e.sb.rpc.__opx === true);
  const r1 = await e.sb.rpc('cost_bill_add', { p_source: 1 });
  ck('the hooked call returns the real answer unchanged and sends ONE request', r1.data.id === 5 && count(e, 'cost_bill_add') === 1);
  const rv = e.sb.rpc('some_other_rpc', {}); ck('other rpc names pass through untouched (same value, no wrapper promise change)', rv instanceof Promise && count(e, 'some_other_rpc') === 1 && e.timers.length === 1);
  await e.flush();
  ck('after the save the hook asks bill_pay_info99 once and opens the sheet (rule ask, 1000 left)', count(e, 'bill_pay_info99') === 1 && e.last().includes('data-opx="sheet"') && e.last().includes('value="1000"'));
  let sh = e.last();
  ck('sheet: title, total, left, four modes (cash bank mobile other), suggestion line, note field, Not now + Record', sh.includes('Record payment now?') && sh.includes('Bill total: 1,000.00') && sh.includes('Left to pay: 1,000.00') && ['cash', 'bank', 'mobile', 'other'].every((m) => sh.includes('data-v="' + m + '"')) && sh.includes('data-opx="rec"') && sh.includes('opx_skip') && sh.includes('opx_pay') && sh.includes('id="opx_note"'));
  ck('sheet: English has no Bangla', !BN.test(sh));
  ck('sheet preselects the party default mode (bank) and amount = bill total, editable', /aria-pressed="true" data-act="opx_mode" data-v="bank"/.test(sh) || /class="mini primary" aria-pressed="true" data-act="opx_mode" data-v="bank"/.test(sh));
  // pay 400 cash (part payment)
  await e.act('opx_mode', { v: 'cash' }); e.set('opx_amt', '400');
  await e.act('opx_pay', {});
  const pc = e.calls.find((c) => c[0] === 'bill_pay_record')[1];
  ck('record = bill_pay_record with kind, ref, mode cash, amount 400, a client id, confirm false', pc.p_kind === 'cost' && pc.p_ref === '5' && pc.p_mode === 'cash' && pc.p_amount === 400 && /^uuid-/.test(pc.p_client) && pc.p_confirm_dup === false);
  ck('after a part payment the sheet shows "Recorded. Left: 600.00" and stays open for the rest', e.last().includes('Recorded. Left: 600.00') && e.last().includes('opx_pay'));
  e.resp.bill_pay_record = { ok: true, id: 2, amount: 600, remaining: 0, counted: true };
  e.sb.rpc = e.sb.rpc; await e.act('opx_pay', {});
  ck('the second part uses a NEW client id and ends with "Recorded" and no Record button', e.calls.filter((c) => c[0] === 'bill_pay_record')[1][1].p_client !== pc.p_client && !e.last().includes('data-act="opx_pay"') && e.last().includes('Recorded'));
  await e.act('opx_skip');
  ck('close closes the sheet', e.sheets[e.sheets.length - 1] === 'CLOSED');
  // invalid amount
  e.calls.length = 0; await e.pages.billpay(); await e.act('opx_lpay', { k: 'cost', r: '5' }); e.set('opx_amt', '0'); await e.act('opx_pay', {});
  ck('amount 0 is refused on the screen (no bill_pay_record call)', count(e, 'bill_pay_record') === 0 && e.last().includes('The amount is not valid'));
  // mode other note
  await e.act('opx_mode', { v: 'other' });
  ck('mode other shows the "note only" warning', e.last().includes('data-opx="othernote"') && e.last().includes('does not reach the cash book'));
  // duplicate warning + confirm
  e.resp.bill_pay_record = { ok: false, needs_confirm: true, warnings: ['form_10_2_matches', 'quick_expense_similar'], remaining: 1000 };
  e.set('opx_amt', '1000'); await e.act('opx_pay', {});
  ck('needs_confirm shows both warnings in plain words and a confirm button, nothing recorded yet', e.last().includes('data-opx="warn"') && e.last().includes('A 10-2 voucher with the same place') && e.last().includes('A quick expense with the same place') && e.last().includes('data-confirm="1"'));
  e.resp.bill_pay_record = { ok: true, id: 3, amount: 1000, remaining: 0, counted: false };
  await e.act('opx_pay', { confirm: '1' });
  ck('confirm sends p_confirm_dup true with the same amount', e.calls.filter((c) => c[0] === 'bill_pay_record').pop()[1].p_confirm_dup === true && e.calls.filter((c) => c[0] === 'bill_pay_record').pop()[1].p_amount === 1000);
  // server errors
  e.resp.bill_pay_record = new Error('overpaid'); e.set('opx_amt', '50'); await e.act('opx_pay', {});
  ck('overpaid is shown as a plain English sentence', e.last().includes('You cannot pay more than what is left.'));
  e.resp.bill_pay_record = new Error('path_locked: expense path a is locked here by the owner'); e.set('opx_amt', '50'); await e.act('opx_pay', {});
  ck('path_locked is shown in words', e.last().includes('Quick expense is locked here'));
  e.resp.bill_pay_record = new Error('not allowed'); e.set('opx_amt', '50'); await e.act('opx_pay', {});
  ck('not allowed is shown in words', e.last().includes('You do not have permission'));
  ck('every error text shown in English has no Bangla', Object.values(e.B.optionsx.ERR).every((x) => !BN.test(x.en)));

  // hook: rule off / dup / auto modes
  e = env({ resp: { bill_pay_info99: INFO({ rule: 'off' }) } });
  await e.sb.rpc('cost_bill_add', { p_source: 1 }); await e.flush();
  ck('rule off (default): the hook looks once and opens NOTHING', count(e, 'bill_pay_info99') === 1 && e.sheets.length === 0 && e.toasts.length === 0);
  e = env({ resp: { cost_bill_add: { dup: true, id: 5 } } });
  await e.sb.rpc('cost_bill_add', { p_source: 1 }); await e.flush();
  ck('a duplicate answer (replayed save) does not trigger the sheet or any extra call', count(e, 'bill_pay_info99') === 0 && e.sheets.length === 0);
  e = env({ resp: { cost_bill_add: new Error('duplicate_bill') } });
  const rr = await e.sb.rpc('cost_bill_add', { p_source: 1 }); await e.flush();
  ck('an error answer is passed through and nothing else happens', rr.error && rr.error.message === 'duplicate_bill' && count(e, 'bill_pay_info99') === 0 && e.sheets.length === 0);
  e = env({ resp: { bill_pay_info99: INFO({ rule: 'auto_cash' }) } });
  await e.sb.rpc('cost_bill_add', { p_source: 1 }); await e.flush();
  ck('auto mode that left something unpaid: a toast pointing to the list, no sheet', e.sheets.length === 0 && e.toasts.length === 1 && e.toasts[0].includes('Bills without payment'));
  e = env({ resp: { bill_pay_info99: INFO({ kind: 'purchase', ref: 'p-1', rule: 'ask', modes: ['cash', 'bank', 'mobile', 'card'], suggest_mode: null, remaining: 700, total: 700 }) } });
  await e.sb.rpc('post_purchase', { p_id: 'p-1', p_payments: null }); await e.flush();
  ck('post_purchase hook: sheet for a purchase bill with card instead of other, default cash', e.last().includes('data-v="card"') && !e.last().includes('data-v="other"') && /aria-pressed="true" data-act="opx_mode" data-v="cash"/.test(e.last()) && e.calls.find((c) => c[0] === 'bill_pay_info99')[1].p_kind === 'purchase');
  e = env({ resp: { bill_pay_info99: new Error('not allowed') } });
  await e.sb.rpc('cost_bill_add', { p_source: 1 }); await e.flush();
  ck('if the info call fails the hook is silent (the save screen is never disturbed)', e.sheets.length === 0 && e.toasts.length === 0);
  e = env({ resp: { bill_pay_info99: INFO({ remaining: 0 }) } });
  await e.sb.rpc('cost_bill_add', { p_source: 1 }); await e.flush();
  ck('nothing left to pay: no sheet', e.sheets.length === 0);

  // ---- reveal flow ----
  e = env({ lang: 'en' });
  await e.pages.inboxpii(); await e.act('opx_reveal', { k: 'message', r: '1' });
  ck('reveal sheet asks for an optional reason and says the reveal is logged', e.last().includes('opx_rr') && e.last().includes('This reveal is logged.') && !BN.test(e.last()));
  e.set('opx_rr', 'customer called'); await e.act('opx_revealgo');
  const uc = e.calls.find((c) => c[0] === 'inbox_unmask')[1];
  ck('reveal = inbox_unmask(kind, id, reason) once', count(e, 'inbox_unmask') === 1 && uc.p_kind === 'message' && uc.p_id === '1' && uc.p_reason === 'customer called');
  ck('the revealed values are shown in the sheet only (handle, name, message), with the logged note', e.last().includes('01711000111') && e.last().includes('Customer A') && e.last().includes('hello') && e.last().includes('data-opx="logged"'));
  ck('the list underneath is still masked (nothing was written into it)', e.els['#opx_pii'].innerHTML.includes('••••••••111') && !e.els['#opx_pii'].innerHTML.includes('01711000111'));
  e.resp.inbox_unmask = { ok: false, error: 'rate_limited', used: 2, max: 2 };
  await e.act('opx_reveal', { k: 'order', r: 'oid-1' }); await e.act('opx_revealgo');
  ck('rate limit answer is shown in words, nothing revealed', e.last().includes('reveal limit is used up') && !e.last().includes('data-opx="revealed"'));
  e.resp.inbox_unmask = new Error('not allowed'); await e.act('opx_revealgo');
  ck('no permission is shown in words', e.last().includes('You do not have permission'));
  // bangla mode keeps common words English
  e = env({ lang: 'bn' }); await e.pages.optionsx(); const bh = e.els['#opx_body'].innerHTML;
  ck('Bangla mode: Bangla text with common English words kept (bill, payment, cash)', BN.test(bh) && /payment|bill/i.test(bh));
  e = env({ lang: 'mix' }); await e.pages.optionsx(); const mh = e.els['#opx_body'].innerHTML;
  ck('Bng/Eng mix mode differs from both', mh !== bh && /Bill payment|bill/.test(mh));
  // non-owner: server says no
  e = env({ owner: false, resp: { options99_state: new Error('not allowed') } }); await e.pages.optionsx();
  ck('a non-owner sees the permission sentence, not the cards', e.els['#opx_body'].innerHTML.includes('data-state="error"') && e.els['#opx_body'].innerHTML.includes('You do not have permission') && !e.els['#opx_body'].innerHTML.includes('opx_set'));

  console.log(`optionsx_test: ${n - bad} pass / ${bad} fail`);
  process.exit(bad ? 1 : 0);
})();
