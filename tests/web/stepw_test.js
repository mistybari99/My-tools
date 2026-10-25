// Step W: new screens for phase 72-84 (formscreens.js, chanedit.js, costboard.js, packflags.js + stepw_common.js). Plain node, mocked rpc, no browser: node tests/web/stepw_test.js
const _P = require('./_paths');
const fs = require('fs'), vm = require('vm'), path = require('path');
const ROOT = _P.WEB_DIR;
let pass = 0, failn = 0;
const chk = (n, ok) => { if (ok) pass++; else { failn++; console.log('FAIL', n); } };
const BN = /[ঀ-৿]/;
const FILES = ['stepw_common.js', 'formscreens.js', 'chanedit.js', 'costboard.js', 'packflags.js'];

function mk(lang, owner = true, rules = {}) {
  const calls = [], toasts = [], sheets = [], handlers = {}, shells = [], els = {}, listeners = {};
  const impl = { rpc: async () => ({ data: null, error: null }), from: {} };
  const qb = (tbl) => { const o = { select: () => o, eq: () => o, in: () => o, order: () => o, limit: () => o, then: (res, rej) => Promise.resolve(impl.from[tbl] || { data: [] }).then(res, rej) }; return o; };
  const A = { sb: { rpc: async (fn, args) => { calls.push([fn, args]); return impl.rpc(fn, args); }, from: (t) => qb(t) },
    S: { lang, ctx: { is_owner: owner, perms: {} } }, esc: (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    toast: (m) => toasts.push(m), fail: (e) => toasts.push('FAIL:' + e.message), shell: (t, h) => shells.push([t, h]), openSheet: (h) => sheets.push(h), closeSheet: () => {}, H: handlers };
  const L = (bn, en, mix) => ({ bn, en, mix });
  const B = { L, lab: (x) => !x ? '' : typeof x === 'string' ? x : lang === 'en' ? (x.en || x.bn) : lang === 'mix' ? (x.mix || x.bn) : (x.bn || x.en), rule: (k, d) => (k in rules ? rules[k] : d), reloadRules: async () => {} };
  const document = { querySelector: (s) => (els[s] = els[s] || { innerHTML: '', value: '', hidden: false, checked: false }), addEventListener: (ev, fn) => { listeners[ev] = fn; } };
  const win = { BOS_APP: A, BOS: B, BOS_PAGES: {} };
  const ctx = vm.createContext({ window: win, document, Number, JSON, Promise, Date, console, setTimeout });
  FILES.forEach((f) => vm.runInContext(fs.readFileSync(path.join(ROOT, f), 'utf8'), ctx, { filename: f }));
  return { A, B, W: B.w, calls, toasts, sheets, handlers, shells, els, impl, listeners, pages: win.BOS_PAGES };
}
const html = (t) => t.shells.map((s) => s[1]).join('') + Object.values(t.els).map((e) => e.innerHTML || '').join('') + t.sheets.join('');
const click = (t, act, ds) => t.handlers[act]({ dataset: ds || {} });

(async () => {
  // ---- 1. languages: every string has bn / en / mix; English slot never has a Bangla letter ----
  {
    const t = mk('en'); const mods = { common: t.W.X, forms: t.B.formscreens.X, chan: t.B.chanedit.X, cost: t.B.costboard.X, pack: t.B.packflags.X };
    let n = 0, ok3 = true, okEn = true, bad = '';
    Object.entries(mods).forEach(([m, X]) => Object.entries(X).forEach(([k, v]) => { n++; if (!(v.bn && v.en && v.mix)) { ok3 = false; bad += ' 3:' + m + '.' + k; } if (BN.test(v.en)) { okEn = false; bad += ' en:' + m + '.' + k; } }));
    chk('all ' + n + ' strings have bn, en and mix' + bad, ok3);
    chk('no English-slot string has a Bangla letter' + bad, okEn);
    chk('channel kinds + error labels: en has no Bangla, all 3 languages', t.B.chanedit.KINDS.every(([, l]) => l.bn && l.en && l.mix && !BN.test(l.en)) && t.W.ERRS.every(([, l]) => l.bn && l.en && l.mix && !BN.test(l.en)));
    chk('choice labels in formscreens: en has no Bangla', Object.values(t.B.formscreens.CH).flat().every((c) => !BN.test(c.l.en) && c.l.bn && c.l.mix));
    chk('Bangla mode shows Bangla, mix mode mixes', BN.test(mk('bn').B.formscreens.T('tUn')) && /Screen/.test(mk('mix').B.formscreens.T('tUn')) && BN.test(mk('mix').B.formscreens.T('tUn')));
  }
  // ---- 2. error labels ----
  {
    const t = mk('en'); const e = (m, d) => t.W.errText({ message: m, details: d });
    chk('not_fully_covered readable', /no matching quick expense/.test(e('not_fully_covered: some lines')));
    chk('note_needed / reason_required', /reason/.test(e('note_needed')) && /reason/.test(e('reason_required')));
    chk('cost_missing names the ingredient from details', /unknown/.test(e('cost_missing', 'Sugar')) && /Sugar/.test(e('cost_missing', 'Sugar')));
    chk('place before plain not allowed', /place/.test(e('not allowed for this location')) && e('not allowed') === 'Not allowed');
    chk('old database (function missing) is said plainly', /not installed/.test(e('Could not find the function public.x in the schema cache')));
    chk('bad_code / name_required / other_text_required', /Code/.test(e('bad_code')) && /name/i.test(e('name_required')) && /Other/.test(e('other_text_required')));
    chk('unknown error falls to fail()', t.W.errText({ message: 'weird' }) === null && (t.W.err({ message: 'weird' }), t.toasts.pop() === 'FAIL:weird'));
    chk('Bangla mode error label is Bangla', BN.test(mk('bn').W.errText({ message: 'bad_status' })));
  }
  // ---- 3. recommendation card ----
  {
    const t = mk('en', true); const h = t.W.recCard({ key: 'k1', kind: 'choice', label: 'Lbl', current: 'a', recommended: 'b', reason: 'because', choices: [{ v: 'a', l: { bn: 'ক', en: 'A', mix: 'ক' } }, { v: 'b', l: { bn: 'খ', en: 'B', mix: 'খ' } }] });
    chk('card shows now, recommendation, reason, advice-only line and a button per choice', /Now: <b>A/.test(h) && /System recommends: <b>B/.test(h) && /because/.test(h) && /Advice only/.test(h) && (h.match(/wx_set"/g) || []).length === 2 && !BN.test(h));
    const n = t.W.recCard({ key: 'h', kind: 'number', label: 'H', current: null, recommended: null, reason: '', unit: 'hours' });
    chk('number with no recommendation says so, has a save box', /No fixed number/.test(n) && /wx_set_num/.test(n) && /Blank/.test(n));
    const s = mk('en', false).W.recCard({ key: 'k', kind: 'switch', label: 'S', current: false, recommended: true, reason: 'r' });
    chk('non-owner: recommendation visible, no switch buttons', /System recommends/.test(s) && !/wx_set"/.test(s) && /Only the owner/.test(s));
    t.impl.rpc = async () => ({ data: null, error: null });
    await click(t, 'wx_set', { k: 'online_pack_warn_on', v: 'true' });
    chk('switch calls set_rule with a real boolean', t.calls[0][0] === 'set_rule' && t.calls[0][1].p_key === 'online_pack_warn_on' && t.calls[0][1].p_value === true && t.toasts.pop() === 'Saved');
    await click(t, 'wx_set', { k: 'form_051_mode', v: 'post' });
    chk('choice sends the text value', t.calls[1][1].p_value === 'post');
    t.els['#wx_n_transit_open_hours'] = { value: '৩' }; await click(t, 'wx_set_num', { k: 'transit_open_hours' });
    chk('Bangla digits are read as a number', t.calls[2][1].p_value === 3);
    t.els['#wx_n_transit_open_hours'] = { value: 'abc' }; const n0 = t.calls.length; await click(t, 'wx_set_num', { k: 'transit_open_hours' });
    chk('bad number: no call, message', t.calls.length === n0 && t.toasts.pop() === 'Number is not valid');
    t.els['#wx_n_transit_open_hours'] = { value: '' }; await click(t, 'wx_set_num', { k: 'transit_open_hours' });
    chk('blank clears the rule (null)', t.calls[t.calls.length - 1][1].p_value === null);
    t.impl.rpc = async () => ({ data: null, error: { message: 'not allowed' } }); await click(t, 'wx_set', { k: 'x', v: 'true' });
    chk('refusal is a readable label, not raw text', t.toasts.pop() === 'Not allowed');
  }
  // ---- 4. E5: form guard + unmatched ----
  {
    const t = mk('en', true);
    const recs = [{ key: 'form_051_mode', current: 'reference', recommended: 'post', reason_bn: 'ক', reason_mix: 'm', reason_en: 'Post because 05-1 is the record' },
      { key: 'transit_short_mode', current: 'keep_in_transit', recommended: 'loss', reason_bn: 'ক', reason_mix: 'm', reason_en: 'Book the loss' },
      { key: 'transit_open_hours', current: null, recommended: null, reason_bn: 'ক', reason_mix: 'm', reason_en: 'Enter a little more than normal' },
      { key: 'offline_soft_stock', current: false, recommended: true, reason_bn: 'ক', reason_mix: 'm', reason_en: 'Goods already handed over' }];
    t.impl.rpc = async (fn) => (fn === 'form_guard_recommendations' ? { data: recs, error: null } : { data: null, error: null });
    await t.pages.formguard(); const h = html(t);
    chk('guard page: 4 cards, each with the server recommendation text, English only', (h.match(/data-rule=/g) || []).length === 4 && /Post because 05-1/.test(h) && /Goods already handed over/.test(h) && !BN.test(h));
    chk('guard page: form 05-1 has reference/post/refuse buttons, switch has On/Off', /wx_set" data-k="form_051_mode" data-v="refuse"/.test(h) && /data-k="offline_soft_stock" data-v="true"/.test(h));
    const tb = mk('bn', true); tb.impl.rpc = async () => ({ data: recs, error: null }); await tb.pages.formguard();
    chk('Bangla mode picks reason_bn', /ক/.test(html(tb)));
    const no = mk('en', false); await no.pages.formguard();
    chk('non-owner: no recommendation call, owner-only note', !no.calls.some((c) => c[0] === 'form_guard_recommendations') && /Owner only/.test(html(no)));

    const u = mk('en', true);
    u.impl.rpc = async (fn, a) => (fn === 'unmatched_forms' ? { data: { lines_checked: 5, lines_unmatched: 2, rows: [{ entry_id: 'e1', form_code: '05-1', serial: 7, location_id: 1, entry_date: '2026-10-01', line_no: 2, item_code: 'F-001', qty: 5, link_id: 9 }] }, error: null } : { data: { confirmed: 3 }, error: null });
    await u.pages.unmatched(); await new Promise((r) => setTimeout(r, 0)); const uh = html(u);
    chk('unmatched: rpc args default last 30 days, no place', u.calls[0][0] === 'unmatched_forms' && /^\d{4}-\d\d-\d\d$/.test(u.calls[0][1].p_from) && u.calls[0][1].p_loc === null);
    chk('unmatched: row, counts, link flag, note, English only', /05-1/.test(uh) && /Unmatched: 2/.test(uh) && /F-001/.test(uh) && /link exists/.test(uh) && /count slip/.test(uh) && !BN.test(uh));
    await click(u, 'wfg_sync'); chk('sync (owner) calls unmatched_forms_sync and reports the count', u.calls.some((c) => c[0] === 'unmatched_forms_sync') && u.toasts.some((m) => m === 'Confirmed: 3'));
    u.impl.rpc = async () => ({ data: null, error: { message: 'bad_range' } }); await click(u, 'wfg_un_go');
    chk('bad range shown as readable text in the body', /366 days/.test(u.els['#wfg_body'].innerHTML));
    const us = mk('en', false); await us.pages.unmatched(); chk('non-owner has no sync button', !/wfg_sync/.test(html(us)));
  }
  // ---- 5. E6: expense link ----
  {
    const t = mk('en', true);
    t.impl.from.entries = { data: [{ id: 'v1', serial: 11, entry_date: '2026-10-02', location_id: 1, status: 'submitted' }] };
    await t.pages.expenselink(); await new Promise((r) => setTimeout(r, 0));
    chk('voucher list shows 10-2 with a Check button', /#11/.test(html(t)) && /wfg_el_check/.test(html(t)));
    t.impl.rpc = async () => ({ data: { fully_covered: true, is_shadow: false, matched: 2, lines: [{ n: 1, head: 'gas', amount: 100, quick_id: 'q1' }, { n: 2, head: 'tea', amount: 20, quick_id: 'q2' }] }, error: null });
    await click(t, 'wfg_el_check', { v: 'v1' });
    let box = t.els['#wfg_r_v1'].innerHTML;
    chk('fully covered: recommendation = link, link button, English only', /Recommendation: link/.test(box) && /wfg_el_apply/.test(box) && /matched: 2 \/ 2/.test(box) && !BN.test(box));
    t.impl.rpc = async () => ({ data: { fully_covered: false, is_shadow: false, matched: 1, lines: [{ head: 'gas', amount: 100, quick_id: 'q1' }, { head: 'tea', amount: 20, quick_id: null }] }, error: null });
    await click(t, 'wfg_el_check', { v: 'v1' }); box = t.els['#wfg_r_v1'].innerHTML;
    chk('partly covered: advice says do not link (non-blocking: button still there, server decides)', /do not link/.test(box) && /wfg_el_apply/.test(box));
    t.impl.rpc = async () => ({ data: { fully_covered: true, is_shadow: true, matched: 0, lines: [] }, error: null });
    await click(t, 'wfg_el_check', { v: 'v1' }); chk('already linked: no link button', !/wfg_el_apply/.test(t.els['#wfg_r_v1'].innerHTML) && /Already linked/.test(t.els['#wfg_r_v1'].innerHTML));
    t.impl.rpc = async (fn) => (fn === 'expense_link_apply' ? { data: null, error: { message: 'not_fully_covered: some' } } : { data: { lines: [], matched: 0, fully_covered: false }, error: null });
    t.els['#wfg_n_v1'] = { value: ' ok ' }; await click(t, 'wfg_el_apply', { v: 'v1' });
    const ap = t.calls.find((c) => c[0] === 'expense_link_apply');
    chk('apply sends entry + trimmed note; server refusal readable', ap[1].p_entry === 'v1' && ap[1].p_note === 'ok' && /no matching quick expense/.test(t.toasts.pop()));
    t.impl.rpc = async (fn) => (fn === 'expense_link_apply' ? { data: { linked: 2 }, error: null } : { data: { lines: [], matched: 0, fully_covered: false }, error: null });
    await click(t, 'wfg_el_apply', { v: 'v1' }); chk('success says Linked (2)', t.toasts.some((m) => m === 'Linked (2)'));
  }
  // ---- 6. E7: transit ----
  {
    const t = mk('en', true);
    t.impl.rpc = async (fn) => ({ transit_open_list: { data: { limit_hours: 2, rows: [{ transfer_id: 't1', code: 'F-1', name_en: 'Cake', name_bn: 'কেক', qty: 10, from_location_id: 1, to_location_id: 2, hours: 3.5, over_limit: true }] }, error: null },
      transit_short_open: { data: [{ transfer_id: 't9', code: 'F-2', name_en: 'Milk', name_bn: 'দুধ', sent: 10, received: 6, short: 4, value: 160, from_location_id: 1, to_location_id: 2, received_at: '2026-10-01T10:00:00Z' }], error: null },
      form_guard_recommendations: { data: [{ key: 'transit_short_mode', current: 'keep_in_transit', recommended: 'loss', reason_en: 'Book the loss', reason_bn: 'ক', reason_mix: 'm' }, { key: 'form_051_mode', current: 'reference', recommended: 'reference', reason_en: 'x', reason_bn: 'ক', reason_mix: 'm' }], error: null } }[fn] || { data: null, error: null });
    await t.pages.transitshort(); const h = html(t);
    chk('transit: open list with hours + over-limit, short list with value, only the 2 transit cards, English only', /3\.5/.test(h) && /over the limit/.test(h) && /Short 4/.test(h) && /Value 160/.test(h) && (h.match(/data-rule=/g) || []).length === 1 && /Book the loss/.test(h) && !BN.test(h));
    const nl = mk('en', true); nl.impl.rpc = async (fn) => (fn === 'transit_open_list' ? { data: { limit_hours: null, rows: [] }, error: null } : { data: [], error: null }); await nl.pages.transitshort();
    chk('no limit: says alert is off', /no alert/i.test(html(nl)));
    click(t, 'wfg_tr_resolve', { v: 't9' }); chk('resolve opens a sheet asking for a reason', /wfg_why/.test(t.sheets[t.sheets.length - 1]));
    t.els['#wfg_why'] = { value: 'a' }; const n0 = t.calls.length; await click(t, 'wfg_tr_go', { v: 't9' });
    chk('short reason: no call', t.calls.length === n0 && /reason/.test(t.toasts.pop()));
    t.els['#wfg_why'] = { value: 'milk spilled on the road' }; t.impl.rpc = async (fn) => (fn === 'transit_short_resolve' ? { data: { id: 't9', ledger_id: 5 }, error: null } : { data: fn === 'transit_open_list' ? { rows: [] } : [], error: null });
    await click(t, 'wfg_tr_go', { v: 't9' });
    const rc = t.calls.filter((c) => c[0] === 'transit_short_resolve').pop();
    chk('resolve sends id + note, then says Loss booked', rc[1].p_id === 't9' && rc[1].p_note === 'milk spilled on the road' && t.toasts.includes('Loss booked'));
  }
  // ---- 7. sales channel ----
  {
    const t = mk('en', true);
    const rows = [{ id: 3, code: 'wa_main', kind: 'other', other_text: 'Telegram', name_bn: 'Main chat', location_id: 1, role_code: 'cashier', active: true, account_ref: 'x' }, { id: 4, code: 'old_fb', kind: 'facebook', other_text: null, name_bn: 'Old page', location_id: null, role_code: null, active: false }];
    t.impl.rpc = async (fn) => (fn === 'sales_channels_list' ? { data: rows, error: null } : { data: { id: 9 }, error: null });
    t.impl.from.roles = { data: [{ code: 'cashier', name_bn: 'ক্যাশিয়ার', name_en: 'Cashier' }] };
    await t.pages.saleschannels(); const h = html(t);
    chk('list: both channels, kind text, inactive marked, list called with p_all true', t.calls[0][1].p_all === true && /Main chat/.test(h) && /Other: Telegram/.test(h) && /inactive/.test(h) && /wch_edit/.test(h) && !BN.test(h));
    await click(t, 'wch_new'); const f = t.sheets[t.sheets.length - 1];
    chk('form: 7 kinds, advice line next to the Active switch, role list, English only', (f.match(/<option value="(web_form|facebook|instagram|whatsapp|phone|walkin|other)"/g) || []).length === 7 && /Recommendation: keep it active/.test(f) && /Cashier/.test(f) && !BN.test(f));
    const set = (o) => Object.entries(o).forEach(([k, v]) => { t.els['#wch_' + k] = v === true || v === false ? { checked: v, value: '' } : { value: v }; });
    set({ code: 'Bad Code', kind: 'phone', other: '', name: 'Phone', loc: '', role: '', acct: '', active: true });
    const n0 = t.calls.length; await click(t, 'wch_save', { v: '' });
    chk('bad code stopped before the server with a readable message', t.calls.length === n0 && /Code:/.test(t.toasts.pop()));
    set({ code: 'phone_1', kind: 'other', other: ' ', name: 'Phone', loc: '', role: '', acct: '', active: true }); await click(t, 'wch_save', { v: '' });
    chk('other without text stopped', t.calls.length === n0 && /Other/.test(t.toasts.pop()));
    set({ code: 'phone_1', kind: 'phone', other: 'ignored', name: ' Phone line ', loc: '2', role: 'cashier', acct: ' ', active: false });
    await click(t, 'wch_save', { v: '' });
    const sv = t.calls.filter((c) => c[0] === 'sales_channel_save').pop()[1];
    chk('new channel args exactly as the server wants', JSON.stringify(sv) === JSON.stringify({ p_id: null, p_code: 'phone_1', p_kind: 'phone', p_other: null, p_name: 'Phone line', p_loc: 2, p_role: 'cashier', p_account_ref: null, p_active: false }));
    await click(t, 'wch_save', { v: '3' }); chk('edit sends the id as a number', t.calls.filter((c) => c[0] === 'sales_channel_save').pop()[1].p_id === 3);
    t.impl.rpc = async (fn) => (fn === 'sales_channels_list' ? { data: rows, error: null } : { data: null, error: { message: 'duplicate key value violates unique constraint' } });
    await click(t, 'wch_save', { v: '' }); chk('duplicate code readable', t.toasts.pop() === 'This code is already used');
    await click(t, 'wch_edit', { v: '3' }); chk('edit form pre-filled and shows the Other box', /value="wa_main"/.test(t.sheets[t.sheets.length - 1]) && !/id="wch_oth" hidden/.test(t.sheets[t.sheets.length - 1]) && /selected>Cashier|value="cashier" selected/.test(t.sheets[t.sheets.length - 1]));
    t.listeners.change({ target: { id: 'wch_kind', value: 'phone' } }); chk('picking another type hides the Other box', t.els['#wch_oth'].hidden === true);
    const ns = mk('en', false); ns.impl.rpc = async () => ({ data: null, error: { message: 'not allowed' } }); await ns.pages.saleschannels();
    chk('non-owner: owner-only note, no new button, refusal shown', /Only the owner/.test(html(ns)) && !/wch_new/.test(html(ns)) && /Not allowed/.test(html(ns)));
  }
  // ---- 8. cost board ----
  {
    const t = mk('en', true, { production_requires_cost: 'warn' });
    t.impl.rpc = async (fn) => (fn === 'profit_source_check' ? { data: { net_revenue: 1000, unknown_cost_rev: 250, fallback_rev: 300, fallback_cogs: 180, ledger_cogs: 400, difference: null, agree: false, notes: ['unknown_cost', 'fallback_used', 'journal_unavailable'] }, error: null }
      : fn === 'items_with_cost' ? { data: [{ item_id: 'i1', cost_price: 10 }, { item_id: 'i2', cost_price: 0 }], error: null } : { data: null, error: null });
    t.impl.from.production_runs = { data: [{ id: 'r1', item_id: 'i1', location_id: 1, made_at: '2026-10-03T05:00:00Z' }] };
    t.impl.from.items = { data: [{ id: 'i1', code: 'R-1', name_en: 'Flour', name_bn: 'ময়দা' }, { id: 'i2', code: 'R-2', name_en: 'Sugar', name_bn: 'চিনি' }, { id: 'i3', code: 'R-3', name_en: 'Ghee', name_bn: 'ঘি' }] };
    await t.pages.costunknown(); const h = html(t);
    chk('board: unknown revenue + share, notes mapped to labels, English only', /250/.test(h) && /25% share of net sales/.test(h) && /no cost at all/.test(h) && /Could not compare/.test(h) && !BN.test(h));
    chk('board: incomplete run named, items with zero / no cost listed, item with cost not', /Flour/.test(h.split('Production: cost incomplete')[1].split('Items with no cost')[0]) && /R-2/.test(h) && /R-3/.test(h) && !/<div class="card">R-1/.test(h));
    chk('board: switch card recommends warn while costs are missing (non-blocking, owner can still pick refuse)', /System recommends: <b>Warn/.test(h) && /data-k="production_requires_cost" data-v="refuse"/.test(h));
    chk('recommend(): clean = refuse', t.B.costboard.recommend(0, 0, 0) === 'refuse' && t.B.costboard.recommend(0, 1, 0) === 'warn' && t.B.costboard.recommend(5, 0, 0) === 'warn');
    chk('links to biz and reports are present, ia pages not edited', /#\/biz/.test(h) && /#\/reports/.test(h));
    const np = mk('en', false); np.impl.rpc = async () => ({ data: null, error: { message: 'not allowed' } }); np.impl.from.production_runs = { data: null, error: { message: 'x' } };
    np.impl.from.items = { data: [], error: null };
    await np.pages.costunknown(); chk('no cost right: one readable note instead of numbers', /cost right is needed/.test(html(np)));
  }
  // ---- 9. pack flags ----
  {
    const t = mk('en', true, { online_pack_warn_on: false });
    t.impl.rpc = async (fn, a) => ({
      online_orders_list: { data: [{ id: 'o1', order_no: 41, location_id: 1 }], error: null },
      online_order_stock_check: { data: { on: true, reserve: true, short: [{ name: 'Rasmalai', need: 5, have: 2, reserved: 1, short_by: 4 }] }, error: null },
      online_order_flags_list: { data: [{ id: 8, order_id: 'o1', order_no: 41, note: 'sale receipt 9 was voided', location_id: 1, at: '2026-10-05T01:00:00Z' }], error: null },
      order_dup_flags_list: { data: [{ id: 5, order_no_a: 40, order_no_b: 41, channel_a: 'web', channel_b: 'whatsapp', day: '2026-10-05', location_id: 1 }], error: null },
      online_order_flag_review: { data: { id: 8 }, error: null }, order_dup_flag_review: { data: { id: 5 }, error: null } }[fn] || { data: null, error: null });
    await t.pages.packflags(); await new Promise((r) => setTimeout(r, 0));
    chk('packed orders listed with a stock check button, English only', /Order #41/.test(html(t)) && /wpf_check/.test(html(t)) && t.calls[0][1].p_status === 'packed' && !BN.test(html(t)));
    await click(t, 'wpf_check', { v: 'o1' }); const c = t.els['#wpf_c_o1'].innerHTML;
    chk('stock warning shows need/have/held/short', /Rasmalai/.test(c) && /need 5/.test(c) && /have 2/.test(c) && /held by other packed orders 1/.test(c) && /short by 4/.test(c));
    t.impl.rpc = async () => ({ data: { on: false, short: [] }, error: null }); await click(t, 'wpf_check', { v: 'o1' });
    chk('warning off: tells where to switch it on', /pack warning is off/i.test(t.els['#wpf_c_o1'].innerHTML));
    t.impl.rpc = async () => ({ data: { on: true, short: [] }, error: null }); await click(t, 'wpf_check', { v: 'o1' }); chk('enough stock message', /Stock is enough/.test(t.els['#wpf_c_o1'].innerHTML));
    t.impl.rpc = async (fn) => (fn === 'online_order_flags_list' ? { data: [{ id: 8, order_no: 41, note: 'sale receipt 9 was voided', location_id: 1, at: '2026-10-05T01:00:00Z' }], error: null } : { data: { id: 8 }, error: null });
    await click(t, 'wpf_tab', { v: 'flag' }); chk('flag tab: open flags listed with the order and a review button', /Order #41/.test(html(t)) && /voided/.test(html(t)) && /wpf_review/.test(html(t)) && t.calls.pop()[1].p_state === 'open');
    click(t, 'wpf_review', { v: '8' }); t.els['#wpf_why'] = { value: 'x' }; const n0 = t.calls.length; await click(t, 'wpf_go', { v: '8' });
    chk('review needs a reason (no call without)', t.calls.length === n0 && /reason/.test(t.toasts.pop()));
    t.els['#wpf_why'] = { value: 'receipt checked, order cancelled' }; await click(t, 'wpf_go', { v: '8' });
    const rv = t.calls.filter((c2) => c2[0] === 'online_order_flag_review').pop();
    chk('review sends numeric id + note, then Saved', rv[1].p_id === 8 && rv[1].p_note === 'receipt checked, order cancelled' && t.toasts.includes('Saved'));
    t.impl.rpc = async (fn) => (fn === 'order_dup_flags_list' ? { data: [{ id: 5, order_no_a: 40, order_no_b: 41, channel_a: 'web', channel_b: 'whatsapp', day: '2026-10-05', location_id: 1 }], error: null } : { data: { id: 5 }, error: null });
    await click(t, 'wpf_tab', { v: 'dup' }); chk('dup tab lists both order numbers', /#40 \/ #41/.test(html(t)));
    t.els['#wpf_why'] = { value: 'same customer, cancel one' }; await click(t, 'wpf_go', { v: '5' });
    chk('dup review uses order_dup_flag_review', t.calls.some((c2) => c2[0] === 'order_dup_flag_review' && c2[1].p_id === 5));
    t.impl.rpc = async () => ({ data: null, error: { message: 'not allowed' } }); await click(t, 'wpf_tab', { v: 'flag' }); chk('no permission: readable text', /Not allowed/.test(t.els['#wpf_body'].innerHTML));
    await click(t, 'wpf_tab', { v: 'sw' }); const sw = html(t);
    chk('switch tab: 3 switches each with the system recommendation + advice-only line, English only', (sw.match(/data-rule=/g) || []).length === 3 && (sw.match(/System recommends/g) || []).length === 3 && /Warn at pack time/.test(sw) && !BN.test(sw));
    chk('warn recommendation = On, current Off shown', /data-rule="online_pack_warn_on"[\s\S]*?Now: <b>Off[\s\S]*?System recommends: <b>On/.test(sw));
  }
  // ---- 10. wiring: ia.js lines, index.html tags, route ids, unique data-act names ----
  {
    const ia = fs.readFileSync(path.join(ROOT, 'ia.js'), 'utf8'), idx = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
    const routes = ['unmatched', 'formguard', 'expenselink', 'transitshort', 'saleschannels', 'costunknown', 'packflags', 'posfailed'];
    chk('ia.js has a rec line for every new route', routes.every((r) => new RegExp("rec\\('" + r + "'").test(ia)));
    chk('index.html has the script tags, common before the pages, after twofa.js', ['stepw_common.js', 'formscreens.js', 'chanedit.js', 'costboard.js', 'packflags.js', 'posfail.js'].every((f) => idx.includes('src="' + f + '"')) && idx.indexOf('stepw_common.js') < idx.indexOf('formscreens.js') && idx.indexOf('twofa.js') < idx.indexOf('stepw_common.js'));
    const t = mk('en'); chk('every route is registered as a page', ['unmatched', 'formguard', 'expenselink', 'transitshort', 'saleschannels', 'costunknown', 'packflags'].every((r) => typeof t.pages[r] === 'function'));
    const mine = FILES.map((f) => fs.readFileSync(path.join(ROOT, f), 'utf8')), acts = new Set(); mine.forEach((s) => (s.match(/data-act="(w[a-z]{1,3}_[a-z_0-9]+)"/g) || []).forEach((m) => acts.add(m.slice(10, -1))));
    const others = fs.readdirSync(ROOT).filter((f) => f.endsWith('.js') && !FILES.includes(f)).map((f) => fs.readFileSync(path.join(ROOT, f), 'utf8')).join('\n');
    const clash = [...acts].filter((a) => new RegExp('(data-act="|\\b)' + a + '\\b').test(others));
    chk('data-act names are unique (no clash with any other web file): ' + clash.join(','), clash.length === 0);
    const hs = Object.keys(t.handlers); chk('every data-act used has a handler', [...acts].filter((a) => a !== 'closesheet').every((a) => hs.includes(a)));
  }
  console.log(`stepw_test: ${pass} pass / ${failn} fail`);
  process.exit(failn ? 1 : 0);
})().catch((e) => { console.log('CRASH', e); process.exit(2); });
