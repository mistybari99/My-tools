// Books 96 screens (web/books96.js) with a mocked rpc / table layer and a tiny fake DOM. No browser, no database.
// Checks: language rule (English has no Bangla, 3 modes present), unique d23_ data-act names, route registry, owner / cost-right gating, opening-stock helper
// (check, recommendation, 4 options, dry-run preview, apply with idempotent client id), cost waiting (list, aging alert number, supply sheet with recommended method, dry run, manual reason), error mapping.
// Run: node tests/web/books96_test.js
const fs = require('fs'), path = require('path'), vm = require('vm');
const WEB = path.join(__dirname, '..', '..', 'web'); const BN = /[ঀ-৿]/;
let n = 0, bad = 0;
const ck = (name, ok) => { n++; if (!ok) { bad++; console.log('FAIL ' + name); } };
const src = fs.readFileSync(path.join(WEB, 'books96.js'), 'utf8');

// ---------- static ----------
const str = "'((?:[^'\\\\]|\\\\.)*)'";
let ls = 0;
for (const m of src.matchAll(new RegExp('L\\(\\s*' + str + ',\\s*' + str + ',\\s*' + str + '\\s*\\)', 'g'))) {
  ls++; ck('English has no Bangla: ' + m[2].slice(0, 50), !BN.test(m[2])); ck('bn and mix not empty: ' + m[2].slice(0, 40), m[1].length > 0 && m[3].length > 0);
}
ck('found many 3-mode strings', ls > 110);
for (const m of src.matchAll(/data-act="(d23_[a-z]+)"/g)) ck('data-act prefixed ' + m[1], /^d23_/.test(m[1]));
const handlers = [...src.matchAll(/^\s{2}(d23_[a-z]+):/gm)].map((m) => m[1]);
ck('handler names unique', handlers.length === new Set(handlers).size);
const used = new Set([...src.matchAll(/data-act="(d23_[a-z]+)"/g)].map((m) => m[1]));
ck('every data-act has a handler', [...used].every((u) => handlers.includes(u)));
ck('no data-act outside d23_', ![...src.matchAll(/data-act="([a-z_0-9]+)"/g)].some((m) => !m[1].startsWith('d23_')));
const ia = fs.readFileSync(path.join(WEB, 'ia.js'), 'utf8'), idx = fs.readFileSync(path.join(WEB, 'index.html'), 'utf8');
ck('ia.js has no merge-conflict markers and parses', !/^(<<<<<<<|=======|>>>>>>>)/m.test(ia) && (() => { try { new vm.Script(ia); return true; } catch (e) { return false; } })());
ck('ia.js has the books96 rec', /rec\('books96', 'acc', \['[^']+', '[^']+', '[^']+'\]/.test(ia));
const rm = ia.match(/rec\('books96', 'acc', \['[^']*',\s*'([^']*)'/); ck('ia.js English title has no Bangla', !!rm && !BN.test(rm[1]));
ck('the books96 rec is the last entry of the IA array', ia.lastIndexOf("rec('books96'") > ia.lastIndexOf("rec('books85'") && ia.lastIndexOf("rec('books96'") > ia.lastIndexOf("rec('invoiceview'"));
ck('index.html loads books96.js once, after books85.js', (idx.match(/books96\.js/g) || []).length === 1 && idx.indexOf('books96.js') > idx.indexOf('books85.js'));
ck('accounts.js / books85.js / pos.js do not mention books96', !/books96|d23_/.test(fs.readFileSync(path.join(WEB, 'accounts.js'), 'utf8') + fs.readFileSync(path.join(WEB, 'books85.js'), 'utf8') + fs.readFileSync(path.join(WEB, 'pos.js'), 'utf8')));
for (const fn of ['opening_stock_check96', 'opening_stock_preview96', 'opening_stock_apply96', 'opening_stock_recommend96', 'cost_wait_list96', 'cost_wait_preview96', 'cost_wait_recommend96', 'cost_wait_supply96', 'set_rule']) ck('calls ' + fn, src.includes("'" + fn + "'"));

// ---------- dynamic ----------
const CHECK = { start: '2026-10-09', accounting_on: true, switch_on: false, risk: true, warnings: ['opening_journal_has_inventory', 'switch_would_double_count', 'uncosted_openings'],
  rows: [{ location_id: 1, opening_value: 5750, opening_rows: 5, uncosted_rows: 2, posted_by_switch: 0, decision: null, opening_journal_inventory: 1000, gl_inventory: 1000, valuation: 5750, diff: -4750 },
         { location_id: 2, opening_value: 600, opening_rows: 1, uncosted_rows: 0, posted_by_switch: 0, decision: null, opening_journal_inventory: 0, gl_inventory: 0, valuation: 600, diff: -600 },
         { location_id: 3, opening_value: 0, opening_rows: 0, uncosted_rows: 0, posted_by_switch: 0, decision: null, opening_journal_inventory: 0, gl_inventory: 0, valuation: 0, diff: 0 }],
  total: { opening_value: 6350 } };
const REC = { recommended: 'difference', reason: { bn: 'শুরুর জের এ আংশিক ধরা আছে', mix: 'Opening journal এ আংশিক ধরা আছে', en: 'The opening journal carries only part of the stock value; post only the part that is missing.' }, numbers: { opening_value: 5750, already_in_opening_journal: 1000 }, never_auto: true,
  alternatives: [{ option: 'owner_capital', amount: 5750, possible: true }, { option: 'existing_account', amount: 5750, possible: true, needs_account: true }, { option: 'skip', amount: 0, possible: true }, { option: 'difference', amount: 4750, possible: true }] };
const PREV = { ok: true, dry: true, option: 'difference', amount: 4750, warnings: ['switch_on'], lines: [{ code: '1320', name_en: 'Inventory: raw materials', name_bn: 'কাঁচামাল', debit: 4500, credit: 0 }, { code: '3100', name_en: 'Owner capital', name_bn: 'মালিকের মূলধন', debit: 0, credit: 4750 }] };
const LIST = { alert_days: 3, alert_enabled: true, total: 2, old_count: 1, oldest_days: 4, by_kind: { wastage: 1, ledger: 1 },
  items: [{ kind: 'ledger', ref: '77', location_id: 1, date: '2026-10-10', age_days: 4, rows: 1, move: 'count_adjust', gl_post: true, over_alert: true, items: [{ code: 'I96-SU', qty: 1, unit: 'kg' }] },
          { kind: 'wastage', ref: 'w-1', location_id: 1, date: '2026-10-14', age_days: 0, rows: 1, move: 'wastage', gl_post: false, over_alert: false, items: [{ code: 'I96-GM', qty: 2, unit: 'kg' }] }] };
const RECC = { ok: true, kind: 'wastage', ref: 'w-1', never_auto: true, total: 30, needs_manual: [], derived: [],
  items: [{ item_id: 'it-gm', code: 'I96-GM', qty: 2, unit: 'kg', recommended: 'item_average', unit_cost: 15, amount: 30, candidates: { item_average: 15, last_purchase: null, recipe_standard: null },
           reason: { bn: 'stock এ average cost আছে', mix: 'Stock এ average cost আছে', en: 'The stock already carries this item at its average cost; using it keeps the books and the stock valuation in step.' } }] };
const PRVC = { ok: true, dry: true, total: 30, gl_post: true, derived: [], items: [] };

function env(opts = {}) {
  const calls = [], toasts = [], sheets = [], els = {};
  const S = { lang: opts.lang || 'en', ctx: { is_owner: opts.owner !== false } };
  const lab = (x) => !x ? '' : typeof x === 'string' ? x : S.lang === 'en' ? (x.en || x.bn) : S.lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en);
  const resp = Object.assign({
    acct_status: { owner: opts.owner !== false, can_manage: true },
    opening_stock_check96: CHECK, opening_stock_recommend96: REC, opening_stock_preview96: PREV, opening_stock_apply96: { id: 1, option: 'difference', entry_id: 5, amount: 4750 },
    cost_wait_list96: LIST, cost_wait_recommend96: RECC, cost_wait_preview96: PRVC, cost_wait_supply96: { rows: 1, total: 30, posted: true }, set_rule: null,
  }, opts.resp || {});
  const sb = {
    rpc: async (fn, a) => { calls.push([fn, a]); const r = resp[fn]; if (typeof r === 'function') return { data: r(a), error: null }; if (r instanceof Error) return { data: null, error: { message: r.message } }; return { data: r === undefined ? null : r, error: null }; },
    from: () => ({ select: () => ({ in: () => Promise.resolve({ data: opts.rules || [], error: null }) }) }),
  };
  const body = { innerHTML: '' }; els['#d23_body'] = body;
  const doc = { querySelector: (s) => els[s] || null };
  const H = {};
  const BOS = { L: (bn, en, mix) => ({ bn, en, mix }), lab, ENV: { locs: [{ id: 1, name_bn: 'প্রধান', name_en: 'Main' }, { id: 2, name_bn: 'শাখা', name_en: 'Branch' }, { id: 3, name_bn: 'গুদাম', name_en: 'Godown' }] } };
  const BOS_APP = { sb, S, esc: (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])), toast: (m) => toasts.push(m), shell: (t) => { env_.title = t; }, openSheet: (h) => sheets.push(h), closeSheet: () => sheets.push('CLOSED'), H };
  const win = { BOS, BOS_APP, crypto: { randomUUID: (() => { let i = 0; return () => 'uuid-' + (++i); })() } };
  const ctx = vm.createContext({ window: win, crypto: win.crypto, document: doc, console, Promise, Date, Number, String, Math, JSON, Object, Array, Intl, Set });
  vm.runInContext(src, ctx);
  const env_ = { calls, toasts, sheets, els, S, H, body, B: win.BOS, pages: win.BOS_PAGES, sb, resp };
  env_.set = (id, v) => { els['#' + id] = Object.assign(els['#' + id] || {}, { value: v }); };
  env_.out = (id) => (els['#' + id] || {});
  env_.act = (name, ds) => H[name]({ dataset: ds || {}, value: (ds || {}).value });
  env_.last = () => sheets[sheets.length - 1] || '';
  return env_;
}

(async () => {
  let e = env();
  ck('page books96 registered', typeof e.pages.books96 === 'function');
  ck('handlers all d23_', Object.keys(e.H).every((k) => k.startsWith('d23_')));
  await e.pages.books96();
  let h = e.body.innerHTML;
  ck('opening tab first: check + recommend called with p_loc null', e.calls.some((c) => c[0] === 'opening_stock_check96' && c[1].p_loc === null) && e.calls.some((c) => c[0] === 'opening_stock_recommend96' && c[1].p_loc === null));
  ck('two places with openings are shown, the empty place is not', (h.match(/data-d23="obrow"/g) || []).length === 2 && !/data-loc="3"/.test(h));
  ck('numbers rendered (5,750.00 / 1,000.00 / -4,750.00)', /৳ 5,750\.00/.test(h) && /৳ 1,000\.00/.test(h) && /৳ -4,750\.00/.test(h));
  ck('double count risk notice + warnings listed', /data-d23="risk"/.test(h) && /Double count risk/.test(h) && (h.match(/data-d23="warn"/g) || []).length === 3);
  ck('recommendation card names Only the difference and gives the reason', /data-d23="orec"/.test(h) && /Recommended: Only the difference/.test(h) && /carries only part of the stock value/.test(h));
  ck('4 option cards, the recommended one is marked', (h.match(/data-d23="opt"/g) || []).length === 4 && (h.match(/data-d23="optrec"/g) || []).length === 1 && /data-opt="difference"[\s\S]*?data-d23="optrec"/.test(h));
  ck('owner sees preview and apply for each option', (h.match(/data-act="d23_oprev"/g) || []).length === 4 && (h.match(/data-act="d23_oapply"/g) || []).length === 4);
  ck('recommendation text says it never blocks / nothing applied by itself', /nothing is applied by itself/.test(h));
  ck('English screen has no Bangla', !BN.test(h.replace(/৳/g, '')));
  ck('nothing was written on load', !e.calls.some((c) => /apply96|supply96|set_rule/.test(c[0])));

  // preview = dry run
  e.set('d23_acct', ' 3900 '); await e.act('d23_oprev', { v: 'existing_account' });
  let pv = e.calls.filter((c) => c[0] === 'opening_stock_preview96');
  ck('preview sends option, place null, trimmed account, no date', pv.length === 1 && pv[0][1].p_option === 'existing_account' && pv[0][1].p_loc === null && pv[0][1].p_account === '3900' && pv[0][1].p_date === null);
  ck('preview shows lines, amount and says dry run; nothing applied', /data-d23="pv"/.test(e.body.innerHTML) && (e.body.innerHTML.match(/data-d23="pvline"/g) || []).length === 2 && /dry run/.test(e.body.innerHTML) && /৳ 4,750\.00/.test(e.body.innerHTML) && !e.calls.some((c) => /apply96/.test(c[0])));
  e = env({ resp: { opening_stock_preview96: { ok: false, error: 'bad_account' } } }); await e.pages.books96(); await e.act('d23_oprev', { v: 'existing_account' });
  ck('preview error is readable', /equity or liability account/.test(e.body.innerHTML) && !/bad_account/.test(e.body.innerHTML));
  e = env({ resp: { opening_stock_preview96: new Error('place_needed') } }); await e.pages.books96(); await e.act('d23_oprev', { v: 'owner_capital' });
  ck('preview rpc error is readable', /Choose a place/.test(e.body.innerHTML));

  // apply: sheet first, then the write with an idempotent client id
  e = env(); await e.pages.books96();
  e.act('d23_oapply', { v: 'difference' });
  ck('apply opens a confirm sheet with the once-per-place warning; no write yet', e.sheets.length === 1 && /once per place/.test(e.sheets[0]) && !e.calls.some((c) => /apply96/.test(c[0])));
  e.set('d23_areason', ' journal has part '); e.set('d23_acct', ''); await e.act('d23_ago', { v: 'difference' });
  let ap = e.calls.filter((c) => c[0] === 'opening_stock_apply96');
  ck('apply sends option, place, reason, client id', ap.length === 1 && ap[0][1].p_option === 'difference' && ap[0][1].p_loc === null && ap[0][1].p_reason === 'journal has part' && /^uuid-/.test(ap[0][1].p_client) && ap[0][1].p_account === null);
  ck('success: sheet closed, toast Saved, list reloaded', e.sheets.includes('CLOSED') && e.toasts.includes('Saved') && e.calls.filter((c) => c[0] === 'opening_stock_check96').length === 2);
  e = env({ resp: { opening_stock_apply96: new Error('already_applied') } }); await e.pages.books96(); e.act('d23_oapply', { v: 'owner_capital' });
  e.els['#d23_aout'] = { textContent: '' }; await e.act('d23_ago', { v: 'owner_capital' }); await e.act('d23_ago', { v: 'owner_capital' });
  ap = e.calls.filter((c) => c[0] === 'opening_stock_apply96');
  ck('retry after an error reuses the same client id; error is readable', ap.length === 2 && ap[0][1].p_client === ap[1][1].p_client && /decision was already taken/.test(e.out('d23_aout').textContent));
  e = env({ resp: { opening_stock_apply96: { dup: true, id: 1 } } }); await e.pages.books96(); e.act('d23_oapply', { v: 'skip' }); await e.act('d23_ago', { v: 'skip' });
  ck('dup result says already recorded', e.toasts.some((t) => /already recorded/.test(t)));
  e = env({ owner: false }); await e.pages.books96();
  ck('non-owner: preview yes, apply buttons no, owner note', !/d23_oapply/.test(e.body.innerHTML) && /d23_oprev/.test(e.body.innerHTML) && /Only the owner/.test(e.body.innerHTML));
  e = env(); await e.pages.books96(); e.set('d23_loc', '2'); await e.act('d23_show');
  ck('place change passes p_loc 2 to check and recommend', e.calls.some((c) => c[0] === 'opening_stock_check96' && c[1].p_loc === 2) && e.calls.some((c) => c[0] === 'opening_stock_recommend96' && c[1].p_loc === 2));
  e = env({ resp: { opening_stock_check96: { data_needed: true } } }); await e.pages.books96();
  ck('data_needed shown readable', /start date is not set/.test(e.body.innerHTML));
  e = env({ resp: { opening_stock_check96: new Error('not allowed') } }); await e.pages.books96();
  ck('not allowed: explains the cost right is needed + retry', /data-state="error"/.test(e.body.innerHTML) && /owner or the cost right/.test(e.body.innerHTML) && /d23_retry/.test(e.body.innerHTML));
  e = env({ resp: { opening_stock_recommend96: new Error('boom') } }); await e.pages.books96();
  ck('a failing recommendation does not hide the numbers', /data-d23="obrow"/.test(e.body.innerHTML) && !/data-d23="orec"/.test(e.body.innerHTML));
  e = env({ resp: { opening_stock_check96: Object.assign({}, CHECK, { risk: false, warnings: [], rows: CHECK.rows.map((r) => Object.assign({}, r, { decision: 'skip' })) }) } }); await e.pages.books96();
  ck('no risk: shows the ✓ line; decisions are shown', /No double count risk found/.test(e.body.innerHTML) && /data-d23="decided"/.test(e.body.innerHTML));

  // cost waiting
  e = env(); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' });
  h = e.body.innerHTML;
  ck('cost tab calls cost_wait_list96', e.calls.some((c) => c[0] === 'cost_wait_list96' && c[1].p_loc === null));
  ck('two documents, oldest first as given, with kind, move, place, age', (h.match(/data-d23="doc"/g) || []).length === 2 && /Stock movement · Count difference/.test(h) && /Wastage/.test(h) && /4 days old/.test(h) && /Main/.test(h));
  ck('chips: posts when costed / will not post now (switch off)', /Posts when costed/.test(h) && /Will not post now \(switch off\)/.test(h));
  ck('alert shown: 1 document past the alert days', /data-d23="alert"/.test(h) && /1 documents wait longer than the alert days/.test(h));
  ck('count line', /2 documents wait for a cost/.test(h) && /Oldest: 4 days/.test(h));
  ck('owner has the alert number input with the typed value 3', /id="d23_days"[^>]*value="3"/.test(h) && /d23_daysset/.test(h) && /d23_daysclr/.test(h));
  ck('English cost screen has no Bangla', !BN.test(h.replace(/৳/g, '')));
  e.set('d23_days', '-1'); await e.act('d23_daysset'); e.set('d23_days', '4000'); await e.act('d23_daysset'); e.set('d23_days', 'abc'); await e.act('d23_daysset');
  ck('a bad number is refused without a call', !e.calls.some((c) => c[0] === 'set_rule') && e.toasts.filter((t) => /not valid/.test(t)).length === 3);
  e.set('d23_days', '7'); await e.act('d23_daysset');
  ck('a good number is saved with set_rule (number)', e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_cost_wait_alert_days' && c[1].p_value === 7));
  await e.act('d23_daysclr');
  ck('clear sends null (blank = no alert)', e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_cost_wait_alert_days' && c[1].p_value === null));
  e = env({ owner: false }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' });
  ck('non-owner: sees the number, no input', !/d23_days|d23_daysset/.test(e.body.innerHTML) && /<b>3<\/b>/.test(e.body.innerHTML));
  e = env({ resp: { cost_wait_list96: Object.assign({}, LIST, { alert_days: null, alert_enabled: false, old_count: null }) } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' });
  ck('blank number: "Alert is off", no warn notice', /Alert is off \(no number typed\)/.test(e.body.innerHTML) && !/class="notice warn" data-d23="alert"/.test(e.body.innerHTML));
  e = env({ resp: { cost_wait_list96: Object.assign({}, LIST, { old_count: 0 }) } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' });
  ck('number typed but nothing old: the ✓ line', /No document is past the alert days/.test(e.body.innerHTML));
  e = env({ resp: { cost_wait_list96: new Error('not allowed') } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' });
  ck('no cost right: readable message instead of the list', /owner or the cost right/.test(e.body.innerHTML) && !/data-d23="doc"/.test(e.body.innerHTML));

  // supply sheet
  e = env(); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' });
  await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' });
  let sh = e.last();
  ck('open sheet calls recommend, then a dry-run preview with the recommended method', e.calls.some((c) => c[0] === 'cost_wait_recommend96' && c[1].p_kind === 'wastage' && c[1].p_ref === 'w-1')
    && e.calls.some((c) => c[0] === 'cost_wait_preview96' && c[1].p_method === 'item_average' && c[1].p_manual === null));
  ck('sheet shows the recommended method + reason + the numbers per method', /Recommended: Item average cost/.test(sh) && /keeps the books and the stock valuation in step/.test(sh) && /15\.00 → 30\.00/.test(sh) && (sh.match(/not known/g) || []).length === 2);
  ck('sheet shows the dry-run total and that nothing is written yet', /data-d23="spv"/.test(sh) && /dry run/.test(sh) && /৳ 30\.00/.test(sh) && !e.calls.some((c) => /supply96/.test(c[0])));
  ck('4 methods offered', (sh.match(/data-act="d23_pick"/g) || []).length === 4);
  ck('English sheet has no Bangla', !BN.test(sh.replace(/৳/g, '')));
  await e.act('d23_supply');
  let sp = e.calls.filter((c) => c[0] === 'cost_wait_supply96');
  ck('supply sends kind, ref, method, null manual, client id, post true', sp.length === 1 && sp[0][1].p_kind === 'wastage' && sp[0][1].p_ref === 'w-1' && sp[0][1].p_method === 'item_average' && sp[0][1].p_manual === null && /^uuid-/.test(sp[0][1].p_client) && sp[0][1].p_post === true && sp[0][1].p_reason === null);
  ck('success: Posted toast, sheet closed, list reloaded', e.toasts.includes('Posted to the books') && e.sheets.includes('CLOSED') && e.calls.filter((c) => c[0] === 'cost_wait_list96').length === 2);
  // manual needs a reason; inputs go as item_id + cost
  e = env({ resp: { cost_wait_recommend96: Object.assign({}, RECC, { items: [Object.assign({}, RECC.items[0], { recommended: 'manual', candidates: { item_average: null, last_purchase: null, recipe_standard: null } })] }) } });
  await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' });
  ck('nothing known: the recommended method is manual, no preview call yet, a cost input is shown', /Recommended: Type it myself/.test(e.last()) && /id="d23_mc0"/.test(e.last()) && /id="d23_reason"/.test(e.last()) && !e.calls.some((c) => c[0] === 'cost_wait_preview96'));
  e.set('d23_mc0', '14'); e.set('d23_reason', ' ');
  await e.act('d23_supply');
  ck('manual without a reason: no call, message shown', !e.calls.some((c) => c[0] === 'cost_wait_supply96') && /Write the reason/.test(e.last()));
  e.set('d23_reason', 'supplier quote'); e.set('d23_mc0', '১৪.৫'); await e.act('d23_supply');
  sp = e.calls.filter((c) => c[0] === 'cost_wait_supply96');
  ck('manual sends the typed cost (Bangla digits parsed) with item id and the reason', sp.length === 1 && sp[0][1].p_method === 'manual' && sp[0][1].p_reason === 'supplier quote' && sp[0][1].p_manual.length === 1 && sp[0][1].p_manual[0].item_id === 'it-gm' && sp[0][1].p_manual[0].cost === 14.5);
  // pick another method re-runs the dry run
  e = env(); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' }); await e.act('d23_pick', { m: 'last_purchase' });
  ck('picking a method runs a dry run with that method', e.calls.filter((c) => c[0] === 'cost_wait_preview96').length === 2 && e.calls[e.calls.length - 1][1].p_method === 'last_purchase');
  e = env({ resp: { cost_wait_preview96: { ok: false, error: 'cost_unavailable', detail: 'I96-GM' } } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' });
  ck('dry run says no cost known by this method (readable, with the item)', /No cost is known by this method/.test(e.last()) && /I96-GM/.test(e.last()) && !/cost_unavailable/.test(e.last()));
  // retry keeps the client id; not-posted note; error text
  e = env({ resp: { cost_wait_supply96: new Error('already_posted') } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' });
  await e.act('d23_supply'); await e.act('d23_supply');
  sp = e.calls.filter((c) => c[0] === 'cost_wait_supply96');
  ck('retry after an error reuses the same client id; error readable in the sheet', sp.length === 2 && sp[0][1].p_client === sp[1][1].p_client && /already in the books/.test(e.last()));
  e = env({ resp: { cost_wait_supply96: { rows: 1, total: 30, posted: false } } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' }); await e.act('d23_supply');
  ck('not posted yet: the cost is kept and the next posting run books it', e.toasts.some((t) => /next posting run/.test(t)));
  e = env({ resp: { cost_wait_supply96: { dup: true, rows: 1 } } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' }); await e.act('d23_supply');
  ck('dup supply says already recorded', e.toasts.some((t) => /already recorded/.test(t)));
  e = env({ resp: { cost_wait_recommend96: { ok: false, error: 'nothing_waiting' } } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' });
  ck('nothing waiting: readable message in the sheet', /Nothing waits for a cost any more/.test(e.last()));
  e.act('d23_sclose'); ck('close sheet', e.last() === 'CLOSED');
  // derived (production) note
  e = env({ resp: { cost_wait_preview96: Object.assign({}, PRVC, { derived: [{ item_id: 'x', unit_cost: 6 }] }) } }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' });
  ck('production preview mentions the finished-good cost record and that the average is not changed', /finished good gets a cost record too/.test(e.last()) && /average cost is not changed/.test(e.last()));

  // Bangla and mix
  e = env({ lang: 'bn' }); await e.pages.books96();
  ck('Bangla mode renders Bangla', BN.test(e.body.innerHTML));
  e = env({ lang: 'mix' }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' });
  ck('mix mode keeps common words English (Cost, Stock)', /Cost|cost/.test(e.body.innerHTML) && BN.test(e.body.innerHTML));
  e = env({ lang: 'bn' }); await e.pages.books96(); await e.act('d23_tab', { v: 'cw' }); await e.act('d23_cwopen', { k: 'wastage', r: 'w-1' });
  ck('Bangla sheet keeps the common words (average, stock) in English', /average/.test(e.last()) && BN.test(e.last()));
  // load failure
  e = env(); e.sb.rpc = async () => ({ data: null, error: { message: 'Failed to fetch' } }); await e.pages.books96();
  ck('load failure shows readable error + retry', /data-state="error"/.test(e.body.innerHTML) && /No internet/.test(e.body.innerHTML) && /d23_retry/.test(e.body.innerHTML));
  const ER = e.B.books96.ERR; ck('ERR entries have all modes and English has no Bangla', Object.values(ER).every((v) => v.bn && v.en && v.mix && !BN.test(v.en)));
  ck('eText maps unknown text through; mapping_missing:x is mapped', e.B.books96.eText(new Error('weird')) === 'weird' && e.B.books96.eText({ message: 'mapping_missing:stock_opening_equity' }) === 'An account mapping is missing');
  ck('every method and option has a label in 3 modes', e.B.books96.METHODS.every((m) => e.B.books96.X['m_' + m]) && e.B.books96.OPTS.every((o) => e.B.books96.X['o_' + o] && e.B.books96.X['d_' + o]));

  console.log('checked ' + n + ', failed ' + bad);
  process.exit(bad ? 1 : 0);
})().catch((x) => { console.log('CRASH', x && x.stack || x); process.exit(2); });
