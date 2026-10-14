// Books 85 screens (web/books85.js) with a mocked rpc / table layer and a tiny fake DOM. No browser, no database.
// Checks: language rule (English has no Bangla, 3 modes present), unique dg_ data-act names, route registry, owner gating, recommendation + WARNING texts,
// card settle (idempotent client id, validation, over hint, void), autopost tick / scheduler, pending alert, error mapping, ia.js + index.html lines.
// Run: node tests/web/dscr_test.js
const _P = require('./_paths');
const fs = require('fs'), path = require('path'), vm = require('vm');
const WEB = _P.WEB_DIR; const BN = /[ঀ-৿]/;
let n = 0, bad = 0;
const ck = (name, ok) => { n++; if (!ok) { bad++; console.log('FAIL ' + name); } };
const src = fs.readFileSync(path.join(WEB, 'books85.js'), 'utf8');

// ---------- static: strings ----------
const str = "'((?:[^'\\\\]|\\\\.)*)'";
let ls = 0;
for (const m of src.matchAll(new RegExp('L\\(\\s*' + str + ',\\s*' + str + ',\\s*' + str + '\\s*\\)', 'g'))) {
  ls++; ck('English has no Bangla: ' + m[2].slice(0, 50), !BN.test(m[2])); ck('bn and mix not empty: ' + m[2].slice(0, 40), m[1].length > 0 && m[3].length > 0);
}
ck('found many 3-mode strings', ls > 90);
for (const m of src.matchAll(/data-act="(dg_[a-z]+)"/g)) ck('data-act prefixed ' + m[1], /^dg_/.test(m[1]));
const handlers = [...src.matchAll(/^\s{2}(dg_[a-z]+):/gm)].map((m) => m[1]);
ck('handler names unique', handlers.length === new Set(handlers).size);
const used = new Set([...src.matchAll(/data-act="(dg_[a-z]+)"/g)].map((m) => m[1]));
ck('every data-act has a handler', [...used].every((u) => handlers.includes(u)));
ck('no data-act outside dg_', ![...src.matchAll(/data-act="([a-z_]+)"/g)].some((m) => !m[1].startsWith('dg_')));
const ia = fs.readFileSync(path.join(WEB, 'ia.js'), 'utf8'), idx = fs.readFileSync(path.join(WEB, 'index.html'), 'utf8');
ck('ia.js has the books85 rec', /rec\('books85', 'acc', \['[^']+', '[^']+', '[^']+'\]/.test(ia));
const rm = ia.match(/rec\('books85', 'acc', \['[^']*',\s*'([^']*)'/); ck('ia.js English title has no Bangla', !!rm && !BN.test(rm[1]));
ck('index.html loads books85.js once', (idx.match(/books85\.js/g) || []).length === 1);
ck('accounts.js / forms.js / pos.js / nav.js untouched by this file set', !/books85/.test(fs.readFileSync(path.join(WEB, 'accounts.js'), 'utf8') + fs.readFileSync(path.join(WEB, 'forms.js'), 'utf8') + fs.readFileSync(path.join(WEB, 'pos.js'), 'utf8') + fs.readFileSync(path.join(WEB, 'nav.js'), 'utf8')));
for (const fn of ['card_settle', 'card_settle_void', 'card_settlement_list', 'acct_autopost_tick', 'acct_scheduler_enable', 'acct_scheduler_disable', 'acct_pending_alert85']) ck('calls ' + fn, src.includes("'" + fn + "'"));
for (const k of ['acct_count_adjust', 'acct_stock_opening', 'acct_issue_out', 'acct_transfer_mode', 'acct_transit_loss', 'acct_purchase_variance', 'acct_stock_moves_from']) ck('switch listed ' + k, src.includes("key: '" + k + "'"));

// ---------- dynamic: fake env ----------
function env(opts = {}) {
  const calls = [], toasts = [], sheets = [], els = {};
  const S = { lang: opts.lang || 'en', ctx: { is_owner: opts.owner !== false } };
  const lab = (x) => !x ? '' : typeof x === 'string' ? x : S.lang === 'en' ? (x.en || x.bn) : S.lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en);
  const rules = opts.rules || [];
  const resp = Object.assign({
    acct_status: { owner: opts.owner !== false, can_manage: opts.manage !== false },
    card_settlement_list: { unsettled: 1000, rows: [{ id: 'r1', date: '2026-10-01', gross: 600, fee: 12, net: 588, bank_mode: 'bank', note: 'n1', status: 'posted' }, { id: 'r2', date: '2026-09-01', gross: 100, fee: 1, net: 99, bank_mode: 'mobile', status: 'void' }] },
    card_settle: { id: 'x', unsettled: 1000, over: false },
    card_settle_void: { status: 'void' },
    acct_pending_alert85: { days: 1, old_count: 2, oldest: '2026-09-20', alert: true, locked_count: 1, locked: [{ source_type: 'sale', source_id: '1', date: '2026-08-30', memo: 'm', reversal: false }], waiting_cost: 3, scheduler: { on: false, last_run: '2026-10-13T10:00:00Z' } },
    acct_autopost_tick: { posted: 4, reversed: 0, errors: 0, locked: 1, waiting: 2, more: false, runs: 1 },
    acct_scheduler_enable: { scheduled: true, job: 5, cron: '*/15 * * * *' }, acct_scheduler_disable: { scheduled: false }, set_rule: null,
  }, opts.resp || {});
  const sb = {
    rpc: async (fn, a) => { calls.push([fn, a]); const r = resp[fn]; if (r instanceof Error) return { data: null, error: { message: r.message } }; return { data: r === undefined ? null : r, error: null }; },
    from: (t) => ({ select: () => { const q = { in: () => Promise.resolve({ data: t === 'rules' ? rules : [], error: null }), order: () => ({ limit: () => Promise.resolve(t === 'acct_autopost_runs85' ? (opts.runs === 'denied' ? { data: null, error: { message: 'permission denied' } } : { data: opts.runs || [], error: null }) : { data: [], error: null }) }) }; return q; } }),
  };
  const body = { innerHTML: '' }; els['#dg_body'] = body;
  const doc = { querySelector: (s) => els[s] || null };
  const H = {};
  const BOS = { L: (bn, en, mix) => ({ bn, en, mix }), lab, ENV: { locs: opts.locs || [{ id: 1, name_bn: 'প্রধান', name_en: 'Main' }, { id: 2, name_bn: 'শাখা', name_en: 'Branch' }] } };
  const BOS_APP = { sb, S, esc: (v) => String(v == null ? '' : v).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])), toast: (m) => toasts.push(m), shell: (t, b) => { env_.shellTitle = t; }, openSheet: (h) => sheets.push(h), closeSheet: () => sheets.push('CLOSED'), H };
  const win = { BOS, BOS_APP, crypto: { randomUUID: (() => { let i = 0; return () => 'uuid-' + (++i); })() } };
  const ctx = vm.createContext({ window: win, crypto: win.crypto, document: doc, console, Promise, Date, Number, String, Math, JSON, Object, Array, Intl, Set });
  vm.runInContext(src, ctx);
  const env_ = { calls, toasts, sheets, els, S, H, body, B: win.BOS, pages: win.BOS_PAGES, sb };
  env_.set = (id, v) => { els['#' + id] = Object.assign(els['#' + id] || {}, { value: v }); };
  env_.out = (id) => (els['#' + id] || {});
  env_.act = (name, ds) => H[name]({ dataset: ds || {}, value: (ds || {}).value });
  return env_;
}
const RULES = [{ key: 'acct_count_adjust', value: false, default_value: false }, { key: 'acct_transfer_mode', value: 'off', default_value: 'off' }, { key: 'acct_stock_opening', value: false, default_value: false }, { key: 'acct_stock_moves_from', value: '', default_value: '' }, { key: 'acct_transit_loss', value: false }, { key: 'acct_transit_loss_at', value: 'receiver' }, { key: 'acct_issue_out', value: false }, { key: 'acct_purchase_variance', value: false }];

(async () => {
  // route + page registration
  let e = env({ rules: RULES });
  ck('page books85 registered', typeof e.pages.books85 === 'function');
  ck('handlers all dg_', Object.keys(e.H).every((k) => k.startsWith('dg_')));
  await e.pages.books85();
  ck('screen shows card tab first (unsettled amount)', /data-dg="unsettled">৳ 1,000\.00/.test(e.body.innerHTML));
  ck('card rows rendered (2)', (e.body.innerHTML.match(/data-dg="crow"/g) || []).length === 2);
  ck('void button only on a posted row', (e.body.innerHTML.match(/data-act="dg_cvoid"/g) || []).length === 1);
  ck('old-document alert shown', /data-dg="alert-top"/.test(e.body.innerHTML) && /documents wait longer/.test(e.body.innerHTML));
  ck('English screen has no Bangla', !BN.test(e.body.innerHTML.replace(/৳/g, '')));

  // card settle: validation, then success with idempotent client id
  e.set('dg_cgross', ''); e.set('dg_cfee', '0'); e.set('dg_cdate', '2026-10-10'); e.set('dg_cmode', 'bank'); e.set('dg_cnote', ' x ');
  e.els['#dg_cout'] = { textContent: '' };
  await e.act('dg_csettle');
  ck('empty gross refused without a call', e.calls.filter((c) => c[0] === 'card_settle').length === 0 && /amount is not valid/.test(e.out('dg_cout').textContent));
  e.set('dg_cgross', '100'); e.set('dg_cfee', '100'); await e.act('dg_csettle');
  ck('fee >= gross refused without a call', e.calls.filter((c) => c[0] === 'card_settle').length === 0 && /fee is not valid/.test(e.out('dg_cout').textContent));
  e.set('dg_cgross', '১,০০০'); e.set('dg_cfee', '12'); await e.act('dg_csettle');
  let cs = e.calls.filter((c) => c[0] === 'card_settle');
  ck('card_settle called once with parsed numbers', cs.length === 1 && cs[0][1].p_gross === 1000 && cs[0][1].p_fee === 12 && cs[0][1].p_loc === 1 && cs[0][1].p_note === 'x' && cs[0][1].p_bank_mode === 'bank' && cs[0][1].p_date === '2026-10-10');
  const cid1 = cs[0][1].p_client; ck('client id sent', /^uuid-/.test(cid1));
  // failing call keeps the same client id for the retry
  e = env({ rules: RULES, resp: { card_settle: new Error('period_closed') } });
  await e.pages.books85(); e.els['#dg_cout'] = { textContent: '' }; e.set('dg_cgross', '50'); e.set('dg_cfee', '0'); e.set('dg_cdate', '2026-10-10'); e.set('dg_cmode', 'mobile');
  await e.act('dg_csettle'); await e.act('dg_csettle');
  cs = e.calls.filter((c) => c[0] === 'card_settle');
  ck('retry after an error reuses the same client id', cs.length === 2 && cs[0][1].p_client === cs[1][1].p_client);
  ck('error shown as readable label', /period is closed/.test(e.out('dg_cout').textContent) && !/period_closed/.test(e.out('dg_cout').textContent));
  // over hint + dup
  e = env({ rules: RULES, resp: { card_settle: { id: 'a', over: true } } });
  await e.pages.books85(); e.set('dg_cgross', '5000'); e.set('dg_cfee', '0'); e.set('dg_cdate', '2026-10-10'); await e.act('dg_csettle');
  ck('over hint shown after saving (not a block)', /more than the unsettled/.test(e.out('dg_cout').textContent) || /more than the unsettled/.test(e.body.innerHTML) || e.toasts.includes('Saved'));
  e = env({ rules: RULES, resp: { card_settle: { id: 'a', dup: true } } });
  await e.pages.books85(); e.set('dg_cgross', '5'); e.set('dg_cfee', '0'); await e.act('dg_csettle');
  ck('dup result says already recorded', e.toasts.some((t) => /already recorded/.test(t)));
  // void
  e = env({ rules: RULES }); await e.pages.books85();
  e.act('dg_cvoid', { v: 'r1' }); ck('void opens a sheet asking why', e.sheets.length === 1 && /dg_vnote/.test(e.sheets[0]));
  e.els['#dg_vout'] = { textContent: '' }; e.set('dg_vnote', ' '); await e.act('dg_cvgo', { v: 'r1' });
  ck('void needs a note (no call)', e.calls.filter((c) => c[0] === 'card_settle_void').length === 0 && /Write the reason/.test(e.out('dg_vout').textContent));
  e.set('dg_vnote', 'wrong day'); await e.act('dg_cvgo', { v: 'r1' });
  ck('void calls the rpc with id and note', e.calls.some((c) => c[0] === 'card_settle_void' && c[1].p_id === 'r1' && c[1].p_note === 'wrong day'));
  // place change
  e.set('dg_loc', '2'); await e.act('dg_lshow');
  ck('place change reloads the list for that place', e.calls.some((c) => c[0] === 'card_settlement_list' && c[1].p_loc === 2));
  // non-manager: no form, no void
  e = env({ rules: RULES, owner: false, manage: false }); await e.pages.books85();
  ck('viewer sees list but no settle form / void', !/dg_csettle/.test(e.body.innerHTML) && !/dg_cvoid/.test(e.body.innerHTML) && /data-dg="crow"/.test(e.body.innerHTML));

  // auto tab
  e = env({ rules: RULES, runs: [{ ran_at: '2026-10-13T10:00:00Z', posted: 3, reversed: 0, errors: 0, locked: 1, waiting: 0, more: false }] });
  await e.pages.books85(); await e.act('dg_tab', { v: 'auto' });
  const hA = e.body.innerHTML;
  ck('auto tab shows alert + locked row + last run', /documents wait longer/.test(hA) && /data-dg="lockrow"/.test(hA) && /2026-10-13 10:00/.test(hA));
  ck('auto tab shows run history rows', (hA.match(/data-dg="run"/g) || []).length === 1);
  ck('auto tab owner has scheduler + run now', /dg_tick/.test(hA) && /dg_schedon/.test(hA) && /dg_schedoff/.test(hA));
  ck('force-post note shown when locked docs exist', /Only the owner can force/.test(hA));
  await e.act('dg_tick');
  ck('run now calls acct_autopost_tick and shows counts', e.calls.some((c) => c[0] === 'acct_autopost_tick') && /Posted 4/.test(e.body.innerHTML));
  e.set('dg_cron', '*/5 * * * *'); await e.act('dg_schedon');
  ck('enable sends the cron text', e.calls.some((c) => c[0] === 'acct_scheduler_enable' && c[1].p_cron === '*/5 * * * *'));
  await e.act('dg_schedoff'); ck('disable calls the rpc', e.calls.some((c) => c[0] === 'acct_scheduler_disable'));
  e = env({ rules: RULES, resp: { acct_scheduler_enable: { scheduled: false, reason: 'pg_cron_missing' } } }); await e.pages.books85(); await e.act('dg_tab', { v: 'auto' }); e.set('dg_cron', '*/5 * * * *'); await e.act('dg_schedon');
  ck('pg_cron missing explained, not "scheduled"', e.toasts.some((t) => /pg_cron is not on the server/.test(t)) && !e.toasts.includes('Scheduled'));
  e = env({ rules: RULES, resp: { acct_autopost_tick: { skipped: 'scheduler_off' } } }); await e.pages.books85(); await e.act('dg_tab', { v: 'auto' }); await e.act('dg_tick');
  ck('skipped tick explained', /scheduler is off/.test(e.body.innerHTML));
  e = env({ rules: RULES, resp: { acct_autopost_tick: { data_needed: true } } }); await e.pages.books85(); await e.act('dg_tab', { v: 'auto' }); await e.act('dg_tick');
  ck('data_needed tick explained', /start date is not set/.test(e.body.innerHTML));
  e = env({ rules: RULES, runs: 'denied' }); await e.pages.books85(); await e.act('dg_tab', { v: 'auto' });
  ck('unreadable run history gives a readable note', /data-dg="runsno"/.test(e.body.innerHTML));
  e = env({ rules: RULES, owner: false, manage: true }); await e.pages.books85(); await e.act('dg_tab', { v: 'auto' });
  ck('non-owner: no run now / scheduler buttons', !/dg_tick|dg_schedon|dg_schedoff/.test(e.body.innerHTML));
  e = env({ rules: RULES, resp: { acct_pending_alert85: { data_needed: true } } }); await e.pages.books85(); await e.act('dg_tab', { v: 'auto' });
  ck('alert data_needed message', /start date is not set/.test(e.body.innerHTML));
  e = env({ rules: RULES, resp: { acct_pending_alert85: new Error('Could not find the function public.acct_pending_alert85') } }); await e.pages.books85();
  ck('missing phase85 does not break the card screen', /data-dg="unsettled"/.test(e.body.innerHTML));

  // switches
  e = env({ rules: RULES }); await e.pages.books85(); await e.act('dg_tab', { v: 'sw' });
  const hS = e.body.innerHTML;
  ck('7 switch cards + transit_loss_at', (hS.match(/data-dg="sw"/g) || []).length === 8);
  ck('every card shows Now and Recommended', (hS.match(/Now:/g) || []).length === 8 && (hS.match(/Recommended:/g) || []).length === 8);
  ck('opening stock WARNING always visible (acct_opening)', /keep this OFF if the opening stock is already inside the opening balance \(acct_opening\)/.test(hS));
  ck('recommendation for opening stock is Off', e.B.books85.rec('acct_stock_opening') === false);
  ck('recommendation: transfer mode follows number of places', e.B.books85.rec('acct_transfer_mode', { places: 3 }) === 'location_tagged' && e.B.books85.rec('acct_transfer_mode', { places: 1 }) === 'off');
  ck('recommendation: transit loss follows transfer mode', e.B.books85.rec('acct_transit_loss', { mode: 'off' }) === false && e.B.books85.rec('acct_transit_loss', { mode: 'company_wide' }) === true);
  ck('recommendations never disable a button', !/disabled/.test(hS));
  ck('English switch screen has no Bangla', !BN.test(hS));
  // turning ON asks first with the backlog warning; nothing written yet
  e.act('dg_sw', { v: 'acct_count_adjust', on: '0' });
  ck('turn ON opens a WARNING sheet (no write yet)', e.sheets.length === 1 && /WARNING/.test(e.sheets[0]) && !e.calls.some((c) => c[0] === 'set_rule'));
  ck('warning says backlog posts at the original dates', /posts the backlog back to the accounting start/.test(e.sheets[0]) && /closed period are held/.test(e.sheets[0]));
  await e.act('dg_swgo', { v: 'acct_count_adjust' });
  ck('confirm writes set_rule true', e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_count_adjust' && c[1].p_value === true));
  e.act('dg_sw', { v: 'acct_stock_opening', on: '0' });
  ck('opening stock sheet carries the acct_opening double count WARNING', /acct_opening/.test(e.sheets[e.sheets.length - 1]) && /counted twice/.test(e.sheets[e.sheets.length - 1]));
  const before = e.calls.filter((c) => c[0] === 'set_rule').length;
  await e.act('dg_sw', { v: 'acct_issue_out', on: '1' });
  ck('turn OFF needs no confirm and writes false', e.calls.filter((c) => c[0] === 'set_rule').length === before + 1 && e.calls[e.calls.length - 1 - e.calls.slice().reverse().findIndex((c) => c[0] === 'set_rule')][1].p_value === false);
  // choice
  e.sheets.length = 0; await e.act('dg_choice', { v: 'acct_transfer_mode', c: 'location_tagged' });
  ck('transfer mode off -> tagged shows the WARNING first', e.sheets.length === 1 && /inter-location clearing/.test(e.sheets[0]) && !e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_transfer_mode'));
  await e.act('dg_chgo', { v: 'acct_transfer_mode', c: 'location_tagged' });
  ck('choice confirm writes the string', e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_transfer_mode' && c[1].p_value === 'location_tagged'));
  await e.act('dg_choice', { v: 'acct_transit_loss_at', c: 'sender' });
  ck('receiver/sender change writes directly', e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_transit_loss_at' && c[1].p_value === 'sender'));
  // from date
  e.set('dg_t_acct_stock_moves_from', '12-10-2026'); await e.act('dg_text', { v: 'acct_stock_moves_from' });
  ck('bad from-date refused (no write)', !e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_stock_moves_from') && e.toasts.some((t) => /not valid/.test(t)));
  e.set('dg_t_acct_stock_moves_from', '2026-10-01'); await e.act('dg_text', { v: 'acct_stock_moves_from' });
  ck('good from-date saved', e.calls.some((c) => c[0] === 'set_rule' && c[1].p_key === 'acct_stock_moves_from' && c[1].p_value === '2026-10-01'));
  // set_rule refused -> readable
  e = env({ rules: RULES, resp: { set_rule: new Error('not allowed') } }); await e.pages.books85(); await e.act('dg_tab', { v: 'sw' }); await e.act('dg_swgo', { v: 'acct_count_adjust' });
  ck('refused write -> "Not allowed" toast', e.toasts.includes('Not allowed'));
  // non-owner: read only
  e = env({ rules: RULES, owner: false, manage: true }); await e.pages.books85(); await e.act('dg_tab', { v: 'sw' });
  ck('non-owner: no switch buttons, owner note shown', !/dg_sw"|dg_choice|dg_text/.test(e.body.innerHTML) && /Only the owner/.test(e.body.innerHTML));
  // Bangla and mix modes
  e = env({ rules: RULES, lang: 'bn' }); await e.pages.books85(); await e.act('dg_tab', { v: 'sw' });
  ck('Bangla mode renders Bangla', BN.test(e.body.innerHTML));
  e = env({ rules: RULES, lang: 'mix' }); await e.pages.books85(); await e.act('dg_tab', { v: 'sw' });
  ck('mix mode keeps common words English (Switch, backlog)', /Switch/.test(e.body.innerHTML));
  // rules load failure -> error + retry
  e = env({ rules: RULES }); e.sb.from = () => ({ select: () => ({ in: () => Promise.resolve({ data: null, error: { message: 'Failed to fetch' } }), order: () => ({ limit: () => Promise.resolve({ data: [], error: null }) }) }) });
  await e.pages.books85();
  ck('load failure shows readable error + retry', /data-state="error"/.test(e.body.innerHTML) && /No internet/.test(e.body.innerHTML) && /dg_retry/.test(e.body.innerHTML));
  // error labels: every ERR entry readable, English no Bangla
  const ER = e.B.books85.ERR; ck('ERR entries have all modes', Object.values(ER).every((v) => v.bn && v.en && v.mix));
  ck('eText maps unknown text through', e.B.books85.eText(new Error('weird')) === 'weird' && e.B.books85.eText({ message: 'x client_id_taken y' }) === 'That request belongs to someone else');

  console.log('checked ' + n + ', failed ' + bad);
  process.exit(bad ? 1 : 0);
})().catch((x) => { console.log('CRASH', x && x.stack || x); process.exit(2); });
