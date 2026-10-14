// web/inbox.js - stub-DOM test (no browser): board strip, masked rows, make-order pre-fill + save call, friendly errors, escaping, 3 language modes.
// Run: node tests/web/inbox_test.js
const _P = require('./_paths');
const fs = require('fs'), vm = require('vm'), path = require('path');
const src = fs.readFileSync(path.join(_P.WEB_DIR, 'inbox.js'), 'utf8');
let pass = 0, fail = 0; const ok = (n, c) => { if (c) pass++; else { fail++; console.log('FAIL ' + n); } };
const body = { innerHTML: '' }, acts = {}, toasts = [], calls = [];
let MODE = 'en', RPC = {};
const fields = {};
const els = { ib_body: body };
const doc = { addEventListener() {}, getElementById: (i) => els[i] || null, querySelector: (s) => (s[0] === '#' ? (fields[s.slice(1)] || els[s.slice(1)] || null) : null), querySelectorAll: () => [] };
const B = { L: (bn, en, mix) => ({ bn, en, mix }), lab: (o) => (typeof o === 'string' ? o : o[MODE]), loadStatic: async () => {} };
const items = [{ id: 'i1', code: 'C1', name_bn: 'রসগোল্লা', sell_price: 100 }];
const chain = { select() { return this; }, eq() { return this; }, order() { return this; }, limit() { return Promise.resolve({ data: items }); } };
const A = { sb: { rpc: async (fn, a) => { calls.push([fn, a]); const r = RPC[fn]; if (r instanceof Error) return { data: null, error: r }; return { data: r === undefined ? null : r, error: null }; }, from: () => chain },
  esc: (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
  toast: (m) => toasts.push(m), fail: (e) => toasts.push(String(e.message || e)), shell: () => {}, H: acts };
const win = { BOS_APP: A, BOS: B, BOS_PAGES: {}, prompt: () => 'spam' };
const ctx = { window: win, document: doc, crypto: { randomUUID: () => '11111111-1111-4111-8111-111111111111' }, Date, Number, String, Object, JSON, Math, Array };
vm.createContext(ctx); vm.runInContext(src, ctx);
const view = win.BOS_PAGES.inbox; const mk = (o) => ({ dataset: o });
(async () => {
  ok('page registered', typeof view === 'function');
  RPC.inbox_board = { on: true, new_count: 3, last_at: 'x', hours_since: 30, silence_hours: 24, silent: true, failed_count: 2, dup_open: 1, drafts: 1 };
  RPC.inbox_list = [
    { id: 1, channel: 'FB <page>', kind: 'facebook', status: 'new', received_at: '2026-10-14T01:02:03Z', masked: false, name: 'Cust <b>', handle: '8801711000009', text: 'two kg <script>' },
    { id: 2, channel: 'WA', kind: 'whatsapp', status: 'new', received_at: '2026-10-14T01:02:03Z', masked: true, draft_order_id: 'd1' },
    { id: 3, channel: 'WA', kind: 'whatsapp', status: 'converted', received_at: '2026-10-14T01:02:03Z', masked: false, name: 'Z', text: 't' }];
  await view();
  ok('board shows new count, failed, dup, drafts', /New messages 3/.test(body.innerHTML) && /Failed intakes 2/.test(body.innerHTML) && /Possible duplicate orders 1/.test(body.innerHTML) && /Draft, needs checking 1/.test(body.innerHTML));
  ok('board shows when the last message came and the silence warning', /Last message came: 30 hours ago/.test(body.innerHTML) && /No message for a long time/.test(body.innerHTML));
  ok('text is escaped, no raw script/tag', !/<script>/.test(body.innerHTML) && /&lt;script&gt;/.test(body.innerHTML) && /Cust &lt;b&gt;/.test(body.innerHTML));
  ok('masked row shows the hidden notice and no text', /Contact hidden/.test(body.innerHTML));
  ok('make-order button only for new/seen, draft verify button for the draft', (body.innerHTML.match(/data-act="ib_make"/g) || []).length === 2 && /data-act="ib_verify" data-id="d1"/.test(body.innerHTML));
  MODE = 'bn'; await view(); ok('Bangla mode: নতুন বার্তা + অর্ডার বানাও', /নতুন বার্তা 3/.test(body.innerHTML) && /অর্ডার বানাও/.test(body.innerHTML) && /শেষ বার্তা এসেছে/.test(body.innerHTML)); MODE = 'mix'; await view(); ok('mix mode renders', /Make order|Order বানাও/.test(body.innerHTML)); MODE = 'en';
  RPC.inbox_board = { on: false }; await view(); ok('inbox off shown', /Inbox is OFF/.test(body.innerHTML));
  RPC.inbox_board = { on: true, new_count: 0, last_at: null, hours_since: null, silent: false, failed_count: 0, dup_open: 0, drafts: 0 }; await view();
  ok('no message yet is stated', /No message has come yet/.test(body.innerHTML));
  // make order: customer + channel pre-filled, staff type items
  RPC.inbox_get = { id: 1, channel_id: 5, location_id: 1, masked: false, name: 'Rina', handle: '+880 1711-000009', text: 'x' };
  await acts.ib_make(mk({ id: '1' }));
  ok('order form opens pre-filled (name, phone from a phone-like handle, empty address and items)', /value="Rina"/.test(body.innerHTML) && /value="01711000009"/.test(body.innerHTML) && /Items and qty \(you type\)/.test(body.innerHTML));
  ok('payment mode list ends with the other option; reference and source are optional fields', /☐ Other:/.test(body.innerHTML) && /Payment reference no\. \(may be blank\)/.test(body.innerHTML) && /Source \(page \/ campaign, may be blank\)/.test(body.innerHTML));
  RPC.inbox_get = { id: 9, masked: true }; await acts.ib_make(mk({ id: '9' })); ok('masked message cannot be converted by this person', toasts.pop() === 'You do not have access to this part');
  RPC.inbox_get = { id: 1, channel_id: 5, location_id: 1, masked: false, name: 'Rina', handle: 'psid-77' };
  await acts.ib_make(mk({ id: '1' }));
  ok('non-phone handle is not put into the mobile field', /id="ib_f_mobile"[^>]*value=""/.test(body.innerHTML));
  fields.ib_f_name = { value: 'Rina' }; fields.ib_f_mobile = { value: '01711000009' }; fields.ib_f_address = { value: 'Dhaka' }; fields.ib_f_dmode = { value: 'home' };
  fields.ib_f_source = { value: 'camp' }; fields.ib_f_pay = { value: 'mobile' }; fields.ib_f_payother = { value: '' }; fields.ib_f_payref = { value: 'TX1' }; fields.ib_f_note = { value: '' };
  const A0 = win.BOS.inbox.orderArgs({ loc: 1, channel_id: 5, name: 'R', mobile: '017', address: '', lines: [{ item_id: 'i1', qty: '2' }, { item_id: '', qty: '' }], dmode: 'pickup', msg_id: 1, pay_mode: 'other', pay_other: 'cheque' }, 'cid');
  ok('orderArgs: only filled lines, ids as typed, client id, message id, draft false, other-mode text', A0.p_lines.length === 1 && A0.p_lines[0].qty === 2 && A0.p_client === 'cid' && A0.p_msg_id === 1 && A0.p_draft === false && A0.p_pay_mode_other === 'cheque' && A0.p_charge === 0);
  ok('orderArgs sends no price', !JSON.stringify(A0).includes('price'));
  RPC.online_order_save2 = { id: 'o1', order_no: 12 };
  await acts.ib_save();
  const sv = calls.filter((c) => c[0] === 'online_order_save2').pop();
  ok('save calls online_order_save2 with the form client id', !!sv && sv[1].p_client === '11111111-1111-4111-8111-111111111111' && sv[1].p_msg_id === 1 && sv[1].p_pay_ref === 'TX1');
  ok('saved toast with the order number, form closed', toasts.pop() === 'Order saved #12' && !/ib_f_name/.test(body.innerHTML));
  await acts.ib_make(mk({ id: '1' })); RPC.online_order_save2 = new Error('bad_mobile: x'); await acts.ib_save();
  ok('friendly error shown inside the form', /The mobile number is not valid/.test(body.innerHTML));
  RPC.online_order_save2 = new Error('message_closed: x'); await acts.ib_save(); ok('closed message friendly', /already became an order/.test(body.innerHTML));
  await acts.ib_back();
  // status / ignore
  RPC.inbox_set_status = { status: 'seen' }; await acts.ib_seen(mk({ id: '1' }));
  ok('seen call', calls.filter((c) => c[0] === 'inbox_set_status').pop()[1].p_to === 'seen');
  await acts.ib_ignore(mk({ id: '1' })); const ig = calls.filter((c) => c[0] === 'inbox_set_status').pop()[1];
  ok('ignore sends the reason', ig.p_to === 'ignored' && ig.p_note === 'spam');
  // other tabs
  RPC.order_dup_flags_list = [{ id: 4, order_no_a: 1, order_no_b: 2, channel_a: 'phone', channel_b: 'facebook', day: '2026-10-14' }];
  await acts.ib_tab(mk({ t: 'dup' })); ok('dup tab lists the pair and a review button (flag only, no merge)', /#1 \(phone\) ↔ #2 \(facebook\)/.test(body.innerHTML) && /ib_dupok/.test(body.innerHTML) && !/merge/i.test(body.innerHTML));
  RPC.intake_failures_list = new Error('not allowed'); await acts.ib_tab(mk({ t: 'fail' })); ok('failed tab: refused shows friendly line', /do not have access/.test(body.innerHTML));
  RPC.intake_failures_list = [{ id: 1, kind: 'message', state: 'failed', attempts: 2, error: 'channel_not_found' }]; await acts.ib_tab(mk({ t: 'fail' })); ok('failed tab lists error and tries', /channel_not_found/.test(body.innerHTML));
  RPC.sales_channels_list = [{ id: 1, code: 'webform', kind: 'web_form', name_bn: 'Web', active: true }, { id: 2, code: 'o', kind: 'other', other_text: 'TikTok', name_bn: 'TT', active: true }];
  await acts.ib_tab(mk({ t: 'ch' })); ok('channels tab: kinds named, other shows its text', /Web \/ landing form/.test(body.innerHTML) && /☐ Other: TikTok/.test(body.innerHTML));
  RPC.web_form_embed = { configured: false }; await acts.ib_embed(mk({ code: 'webform' })); ok('share link: not configured message, no fake link', /Public URL not set yet/.test(body.innerHTML));
  RPC.web_form_embed = { configured: true, link: 'https://x/fn?c=webform', embed: '<iframe src="x"></iframe>' }; await acts.ib_embed(mk({ code: 'webform' })); ok('share link and embed code shown (escaped)', /https:\/\/x\/fn\?c=webform/.test(body.innerHTML) && /&lt;iframe/.test(body.innerHTML));
  ok('helpers: phoneLike', win.BOS.inbox.phoneLike('8801711000009') === '01711000009' && win.BOS.inbox.phoneLike('psid-77') === '');
  // ---- Telegram (Step Tg) ----
  MODE = 'en'; RPC.inbox_board = { on: true, new_count: 1, last_at: 'x', hours_since: 1, silent: false, failed_count: 0, dup_open: 0, drafts: 0 };
  RPC.inbox_list = [{ id: 21, channel: 'TG <shop>', kind: 'telegram', status: 'new', received_at: '2026-10-14T01:02:03Z', masked: false, name: 'Chat <i>', handle: 'tg:555', text: 'hi' },
    { id: 22, channel: 'WA', kind: 'whatsapp', status: 'new', received_at: '2026-10-14T01:02:03Z', masked: false, name: 'W', text: 'w' }];
  await view(); await acts.ib_tab(mk({ t: 'msg' }));
  ok('telegram shows as a channel kind (English)', win.BOS.inbox.kindTxt('telegram') === 'Telegram' && /TG &lt;shop&gt; · Telegram/.test(body.innerHTML));
  ok('chat-info button only on telegram messages', (body.innerHTML.match(/data-act="ib_tg_info"/g) || []).length === 1 && /data-act="ib_tg_info" data-id="21"/.test(body.innerHTML));
  MODE = 'bn'; ok('Bangla mode: telegram label', win.BOS.inbox.kindTxt('telegram') === 'টেলিগ্রাম'); MODE = 'mix'; ok('mix mode keeps Telegram in English', win.BOS.inbox.kindTxt('telegram') === 'Telegram'); MODE = 'en';
  RPC.telegram_chat_info = { msg_id: 21, linked: true, masked: false, customer_name: 'Test <b>', customer_mobile: '01700000001', order_no: 7, message_count: 3 };
  await acts.ib_tg_info(mk({ id: '21' }));
  ok('info block: linked, customer, order no, count, escaped', /Linked/.test(body.innerHTML) && /Test &lt;b&gt;/.test(body.innerHTML) && /Order no\. #7/.test(body.innerHTML) && /Messages in this chat: 3/.test(body.innerHTML) && !/<b>Test/.test(body.innerHTML));
  ok('unlink button only while linked', /data-act="ib_tg_unlink"/.test(body.innerHTML));
  RPC.telegram_chat_info = { msg_id: 21, linked: true, masked: true, customer_name: null, customer_mobile: null, order_no: null, message_count: 3 };
  await acts.ib_tg_info(mk({ id: '21' })); await acts.ib_tg_info(mk({ id: '21' }));
  ok('masked info shows no customer name or mobile', /Linked/.test(body.innerHTML) && !/01700000001/.test(body.innerHTML));
  win.prompt = () => '+8801700000001';
  RPC.telegram_chat_link = { id: 1 }; RPC.telegram_chat_info = { msg_id: 21, linked: true, masked: false, customer_name: 'Cu', customer_mobile: '01700000001', message_count: 1 };
  await acts.ib_tg_link(mk({ id: '21' })); const lk = calls.filter((c) => c[0] === 'telegram_chat_link').pop();
  ok('link looks the customer up by mobile and calls the server function (no price, no order made)', !!lk && lk[1].p_msg_id === 21 && lk[1].p_customer === 'i1' && lk[1].p_order === null);
  win.prompt = () => ''; const nl = calls.length; await acts.ib_tg_unlink(mk({ id: '21' }));
  ok('unlink without a reason does not call the server', calls.length === nl && toasts.pop() === 'A reason is needed');
  win.prompt = () => 'wrong person'; RPC.telegram_chat_unlink = { unlinked: true }; await acts.ib_tg_unlink(mk({ id: '21' }));
  ok('unlink sends the reason', calls.filter((c) => c[0] === 'telegram_chat_unlink').pop()[1].p_reason === 'wrong person');
  RPC.telegram_chat_link = new Error('not_telegram: x'); win.prompt = () => '01700000001'; await acts.ib_tg_link(mk({ id: '21' })); ok('friendly error for a non-telegram message', toasts.pop() === 'This is not a Telegram message');
  // channels tab: owner sees setup buttons, others do not
  RPC.sales_channels_list = [{ id: 4, code: 'tg_ab12', kind: 'telegram', name_bn: 'TG', active: true }];
  RPC.telegram_status = { channels: [{ id: 4, secret_set: false }] };
  await acts.ib_tab(mk({ t: 'ch' }));
  ok('owner: token-not-set warning, set-token and add buttons, webhook code shown', /Token not set/.test(body.innerHTML) && /data-act="ib_tg_secret" data-id="4"/.test(body.innerHTML) && /data-act="ib_tg_add"/.test(body.innerHTML) && /\?c=tg_ab12/.test(body.innerHTML));
  RPC.telegram_status = new Error('not allowed'); await acts.ib_tab(mk({ t: 'ch' }));
  ok('non-owner: channel listed, no setup buttons', /Telegram/.test(body.innerHTML) && !/ib_tg_secret|ib_tg_add/.test(body.innerHTML));
  RPC.telegram_status = { channels: [{ id: 4, secret_set: true }] }; await acts.ib_tab(mk({ t: 'ch' })); ok('token set is shown', /Token set/.test(body.innerHTML));
  win.prompt = () => 'abcdefghij1234567890'; RPC.telegram_secret_set = { set: true }; await acts.ib_tg_secret(mk({ id: '4' }));
  ok('secret goes to the server function only; saved toast', calls.filter((c) => c[0] === 'telegram_secret_set').pop()[1].p_secret === 'abcdefghij1234567890' && toasts.pop() === 'Secret token saved');
  RPC.telegram_secret_set = new Error('bad_secret: x'); await acts.ib_tg_secret(mk({ id: '4' })); ok('bad token friendly error', /The token is not valid/.test(toasts.pop()));
  const q = ['My shop', 'my_shop_bot', 'i1']; win.prompt = () => q.shift(); RPC.sales_channel_save = { id: 9 };
  await acts.ib_tg_add();
  const ad = calls.filter((c) => c[0] === 'sales_channel_save').pop()[1];
  ok('add telegram channel: kind telegram, bot ref, place, generated code', ad.p_kind === 'telegram' && ad.p_account_ref === 'my_shop_bot' && ad.p_loc === 'i1' && /^tg_[0-9a-f]{6}$/.test(ad.p_code) && ad.p_id === null);
  ok('no secret appears in the page html', !/abcdefghij1234567890/.test(body.innerHTML));
  console.log(`RESULT pass=${pass} fail=${fail}`); process.exit(fail ? 1 : 0);
})();
