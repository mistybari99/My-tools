// XB screens (web/xb_paycapture.js #/paycapture, web/xb_cakejobs.js #/cakejobs, web/xb_riders.js #/riders): static checks, no browser and no database.
//  * the files parse; the routes are registered in web/ia.js and loaded by web/index.html (with the SMS reader web/xb_paysms.js)
//  * every i18n key the screens use exists in web/i18n.js with bn, mix and en
//  * every RPC the screens call exists as a function in the SQL phases (phase491, phase492, phase493)
//  * the screens write only through the RPCs named in docs/integration/XB.md (no insert / update / upsert / delete on a table)
//  * the SMS reader is used only to read a paste; nothing is saved from it; no CSV export; nothing is sent to a customer or rider
//  * the SMS reader returns the fields the capture screen uses (a pure check on the sample texts is in xb_paysms_test.js)
// Run: node xb_screens_test.js <abs tests/web dir>   (the repository root is found from this file's folder)
const fs = require('fs'), path = require('path'), vm = require('vm');
const ROOT = path.join(__dirname, '..', '..');
const WEB = path.join(ROOT, 'web');
const read = (p) => fs.readFileSync(p, 'utf8');
let pass = 0, fail = 0;
const ok = (c, msg) => { if (c) { pass++; } else { fail++; console.log('FAIL: ' + msg); } };

const FILES = ['xb_paycapture.js', 'xb_cakejobs.js', 'xb_riders.js'];
const src = {};
for (const f of FILES) {
  src[f] = read(path.join(WEB, f));
  try { new vm.Script(src[f], { filename: f }); ok(true, f + ' parses'); } catch (e) { ok(false, f + ' does not parse: ' + e.message); }
}

// routes and loading
const ia = read(path.join(WEB, 'ia.js'));
ok(/rec\('paycapture',\s*'acc'/.test(ia), 'ia.js registers paycapture in group acc');
ok(/rec\('cakejobs',\s*'cust'/.test(ia), 'ia.js registers cakejobs in group cust');
ok(/rec\('riders',\s*'cust'/.test(ia), 'ia.js registers riders in group cust');
ok(!/rec\('(paycapture|cakejobs|riders)'[^\n]*ruleOn\(/.test(ia), 'XB main features are not hidden behind a switch (switches live inside the feature)');
const html = read(path.join(WEB, 'index.html'));
for (const f of ['xb_paysms.js', ...FILES]) ok(html.includes('src="' + f + '"'), 'index.html loads ' + f);
ok(/\{ paycapture: view \}/.test(src['xb_paycapture.js']), 'xb_paycapture registers route paycapture');
ok(/\{ cakejobs: view \}/.test(src['xb_cakejobs.js']), 'xb_cakejobs registers route cakejobs');
ok(/\{ riders: view \}/.test(src['xb_riders.js']), 'xb_riders registers route riders');

// i18n keys
const i18nSrc = read(path.join(WEB, 'i18n.js'));
const ctx = { window: {} };
vm.runInNewContext(i18nSrc, ctx, { filename: 'i18n.js' });
const T = ctx.window.BOS_T;
const rpcNames = new Set(), tableNames = new Set();
for (const f of FILES) {
  for (const m of src[f].matchAll(/(?:call|run)\('([a-z_0-9]+)'|sb\.rpc\('([a-z_0-9]+)'/g)) rpcNames.add(m[1] || m[2]);
  for (const m of src[f].matchAll(/from\('([a-z_0-9]+)'\)/g)) tableNames.add(m[1]);
}
const used = new Set();
for (const f of FILES) for (const m of src[f].matchAll(/'(xb_[a-z0-9_]+)'/g)) if (!rpcNames.has(m[1]) && !tableNames.has(m[1]) && !m[1].endsWith('_')) used.add(m[1]);
// the prefix-built keys: every state, action, provider, target and flag that the screens can show
for (const k of ['xb_state_quoted', 'xb_state_confirmed', 'xb_state_slip', 'xb_state_baked', 'xb_state_decorated', 'xb_state_ready', 'xb_state_delivered', 'xb_state_cancelled',
  'xb_act_confirmed', 'xb_act_slip', 'xb_act_baked', 'xb_act_decorated', 'xb_act_ready', 'xb_act_delivered',
  'xb_prov_bkash', 'xb_prov_nagad', 'xb_prov_rocket', 'xb_prov_other', 'xb_tgt_none', 'xb_tgt_order', 'xb_tgt_advance',
  'xb_pay_flag_ok', 'xb_pay_flag_overpay', 'xb_pay_flag_underpay', 'xb_pay_flag_no_target',
  'xb_rd_state_unassigned', 'xb_rd_state_assigned', 'xb_rd_state_out', 'xb_rd_state_delivered', 'xb_rd_state_failed', 'xb_rd_state_returned',
  'xb_rd_st_matched', 'xb_rd_st_short', 'xb_rd_st_over', 'xb_rd_mode_home', 'xb_rd_mode_courier']) used.add(k);
const missingKeys = [...used].filter((k) => !T[k] || !T[k].bn || !T[k].mix || !T[k].en);
ok(missingKeys.length === 0, 'every xb_ key has bn, mix and en: missing ' + missingKeys.join(', '));
ok(used.size > 100, 'the screens use a realistic number of keys (' + used.size + ')');

// RPCs and tables exist in the SQL phases
const sqlDir = path.join(ROOT, 'supabase');
const sqlText = ['phase491.sql', 'phase492.sql', 'phase493.sql'].map((f) => read(path.join(sqlDir, f))).join('\n');
const fromOld = read(path.join(sqlDir, 'phase83.sql'));
for (const r of rpcNames) {
  if (r === 'd_wallet_balances') { ok(new RegExp('function public\\.' + r + '\\(').test(fromOld), 'RPC exists in phase83: ' + r); continue; }
  ok(new RegExp('create or replace function public\\.' + r + '\\(').test(sqlText), 'RPC exists in phase491/492/493: ' + r);
}
for (const t of tableNames) {
  const allowed = ['pay_captures', 'cake_jobs', 'delivery_jobs', 'riders', 'delivery_zones', 'cod_cases', 'online_orders'];
  ok(allowed.includes(t), 'table read is one the screens may read: ' + t);
}
ok(rpcNames.has('xb_pay_capture') && rpcNames.has('xb_pay_capture_decide') && rpcNames.has('xb_cake_move') && rpcNames.has('xb_delivery_assign') && rpcNames.has('xb_cod_deposit'),
  'the main write RPCs are used');

// writes: only RPCs, never a table write; no export; nothing sent
for (const f of FILES) {
  ok(!/\.(insert|update|upsert|delete)\(/.test(src[f]), f + ' writes no table directly');
  ok(!/csv/i.test(src[f]), f + ' has no CSV export');
  ok(!/sendEmail|telegram\.org|api\.telegram|smtp|wa\.me|sms_send/i.test(src[f]), f + ' sends nothing');
}
ok(/BOS\.xbPaySms|B\.xbPaySms/.test(src['xb_paycapture.js']), 'capture screen uses the SMS reader');
ok(/p_status: 'pending'/.test(src['xb_paycapture.js']), 'capture list reads pending captures');
const sms = read(path.join(WEB, 'xb_paysms.js'));
ok(/parseMobilePaySms/.test(sms) && /root\.BOS\.xbPaySms = api/.test(sms), 'SMS reader exposes parseMobilePaySms');
ok(!/\b(sb\.|fetch\(|localStorage|sessionStorage)/.test(sms), 'SMS reader saves and sends nothing');

console.log('xb_screens_test: ' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
