-- ============================================================
-- Phase 115 (bos115) - BATCH 2 "stock safety", part 2 (factory-to-branch transfers).
--   Source: docs/audit2/A5_factory_branch_reconciliation.md (GAP-2, GAP-3, GAP-4, GAP-6, GAP-8 is rule transfer_needs_stock of phase114).
--   Needs phases 72..103 pasted first (guard below); phase114 is NOT required (its own rule is used only by phase114). Independent of 112/113/116..121.
--   Paste twice = no change. EVERY behaviour change is behind a rules switch, default OFF = today's behaviour. Nothing here is switched on by this file.
--
--   Rules (switches, default false)
--     transfer_late_receive     GAP-2 a short receipt can be completed later: stock_receive_more(id, qty) books the rest (second lorry) at the sent cost,
--                                     same batch / expiry, as long as the shortage was not written off (transit_loss) or booked in the accounts.
--     transfer_return_marker    GAP-3 stock_return_transfer(...) sends goods back to the factory as a MARKED return: kind = return, a reason
--                                     (damaged / expired / excess / wrong_item / other) and a link to the original transfer; it is an ordinary transfer otherwise.
--     transfer_notify_receiver  GAP-6 when goods are sent, a notification goes to the receiving place's managers (kind transfer_sent, once per transfer).
--     transit_loss_gl_fix       GAP-4 location-tagged accounting: transit_short_mode = loss / transit_short_resolve no longer leave a phantom inventory
--                                     (+short transfer_in leg without a matching leg) and the transit-loss entry is no longer stuck on cost_missing.
--                                     Entries already posted wrongly are NOT rewritten (see the report).
--   Columns  stock_transfers.kind (null = normal send, 'return'), .reason, .ref_transfer_id   (all nullable; old rows unchanged)
--   Functions new: stock_receive_more(id, qty, note, client), stock_return_transfer(from, to, item, qty, reason, ref, unit, note, client)
--             patched by exact-text insert (helper _b2_patch115, dropped at the end; older bosNN tags stay): stock_transfer (tag bos115), _acct_stock_moves85 and _acct_docs.
--             These two carry the marker b2s115, NOT a bosNN tag, on purpose (same as perf110 / sec2-L6): the body guards of phase98 / 103 / 110 refuse to overwrite a function with a bosNN
--             tag they do not know, so a bos115 tag there would make an out-of-order re-paste of those phases impossible. Re-paste rule: after phase98 / 103 / 110 paste phase115 again.
--   Not done: factory-branch statement report (GAP-1), challan header (GAP-7), transfer price (GAP-9), paused-location check (GAP-5), offline outbox (GAP-12),
--             returns valued at the original send cost (G8: needs a cost-aware return post; risky), form 03-1 path (GAP-11).
--   Money / cost secrecy: no cost is shown by anything new (costs are read only inside stock_post / the accounts, as before); RLS / grants unchanged.
-- ============================================================
begin;

do $g$
declare miss text := ''; m record;
begin
  for m in select * from (values
    ('72', 'public._cogs_lines72(date,date,integer[])'), ('73', 'public._recipe_gate73(uuid)'), ('74', 'public._pool_rate(integer,date,text)'),
    ('75', 'public._cs_alloc(bigint)'), ('76', 'public._inb_gate(integer,text)'), ('77', 'public._oo_short77(uuid)'), ('78', 'public._c78_main_loc(date)'),
    ('80', 'public._cost_free80(uuid)'), ('81', 'public._setup_chk81(text)'), ('82', 'public.grn_bill_link(uuid,uuid,text)'), ('83', 'public._pf83_ro()'),
    ('84', 'public._aud84()'), ('85', 'public._acct_from85()'), ('86', 'public._tg_hash(text)'), ('87', 'public._prod_double_issue87()'),
    ('88', 'public._rcs88()'), ('90', 'public._scan_clean(text,jsonb,boolean)'), ('91', 'public._ov_key(text,text)'),
    ('92', 'public.invoice_data92(uuid,uuid)'), ('93', 'public.get_doc_templates(integer)'), ('94', 'public._intake_proof_ok94(text,text)'),
    ('95', 'public.drawer_settings(integer)'), ('96', 'public._cw_docs96()'), ('97', 'public._landed_jlines97(uuid,text)'),
    ('99', 'public._inb_pii_f99(text,text)'), ('103', 'public._cust_pii103(text,text)')) v(ph, fn)
  loop
    if to_regprocedure(m.fn) is null then miss := miss || ' ' || m.ph; end if;
  end loop;
  if to_regclass('public.item_categories') is null then miss := miss || ' 100'; end if;
  if to_regclass('public.setup_rec_defs81') is null or not exists (select 1 from public.setup_rec_defs81 where code = 'purchase_grn_guard' and phase = '82') then miss := miss || ' 101'; end if;
  if to_regclass('public.stock_transfers') is null or to_regclass('public.journal_entries') is null or to_regclass('public.notifications') is null then miss := miss || ' base'; end if;
  if miss <> '' then
    raise exception 'phase115 needs phases 72..103 pasted first (see docs/PASTE_ORDER.md); missing:%', miss;
  end if;
end $g$;

-- ---------- helper: exact-text patch of a live function body (dropped at the end of this file) ----------
create or replace function public._b2_patch115(p_sig text, p_anchor text, p_repl text, p_marker text) returns void
language plpgsql set search_path = public as $$
declare d text; f regprocedure := to_regprocedure(p_sig); n int;
begin
  if f is null then raise exception 'phase115: function % not found - paste phases 72..103 first', p_sig; end if;
  d := pg_get_functiondef(f);
  if position(p_marker in d) > 0 then return; end if;                               -- already patched: paste twice = no change
  n := (length(d) - length(replace(d, p_anchor, ''))) / length(p_anchor);
  if n <> 1 then raise exception 'phase115: % expected text found % times (need exactly 1) in %; the function changed - merge by hand', p_marker, n, p_sig; end if;
  execute replace(d, p_anchor, p_repl);
end $$;

-- ---------- columns (additive, nullable) ----------
alter table public.stock_transfers add column if not exists kind text;
alter table public.stock_transfers add column if not exists reason text;
alter table public.stock_transfers add column if not exists ref_transfer_id uuid;
do $c$ begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.stock_transfers'::regclass and conname = 'stock_transfers_kind115') then
    alter table public.stock_transfers add constraint stock_transfers_kind115 check (kind is null or kind = 'return');
  end if;
end $c$;

-- ---------- rules (all OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('transfer_late_receive', 'stock', 'switch', 'false', null, null, null, null,
  'কম গ্রহণ করা transfer-এর বাকি মাল পরে গ্রহণ করা যাবে', 'কম receive করা transfer-এর বাকি মাল পরে receive করা যাবে', 'The rest of a short transfer can be received later',
  'বন্ধ = আগের মতোই (ডিফল্ট): প্রথম গ্রহণেই transfer বন্ধ হয়, দ্বিতীয় গাড়ির মাল "ঘাটতি" থেকে যায়। চালু = ঘাটতি অবশিষ্টের মধ্যে পরে আরও গ্রহণ করা যায় (যতক্ষণ ঘাটতি "পথে ক্ষতি" হিসেবে লেখা বা হিসাবে তোলা হয়নি)।',
  'Off = আগের মতোই (default): প্রথম receive-এই transfer বন্ধ হয়, দ্বিতীয় গাড়ির মাল "short" থেকে যায়। On = ঘাটতি অবশিষ্টের মধ্যে পরে আরও receive করা যায় (যতক্ষণ ঘাটতি transit loss হিসেবে লেখা বা accounts-এ তোলা হয়নি)।',
  'Off = as before (default): the first receipt closes the transfer and the second lorry stays "short" for ever. On = more can be received later up to the shortage, as long as the shortage was not written off as a transit loss or booked in the accounts.', 1150),
 ('transfer_return_marker', 'stock', 'switch', 'false', null, null, null, null,
  'কারখানায় ফেরত পাঠানো মাল কারণ ও মূল transfer-সহ চিহ্নিত হবে', 'Factory-তে ফেরত পাঠানো মাল কারণ ও মূল transfer-সহ চিহ্নিত হবে', 'Returns to the factory are marked with a reason and a link',
  'বন্ধ = আগের মতোই (ডিফল্ট): ফেরত পাঠানো একটি সাধারণ উল্টো transfer, কারণ বা যোগসূত্র থাকে না। চালু = "ফেরত" transfer-এ কারণ (নষ্ট / মেয়াদ শেষ / বাড়তি / ভুল মাল / অন্য) ও মূল transfer লেখা থাকে।',
  'Off = আগের মতোই (default): ফেরত পাঠানো একটি সাধারণ উল্টো transfer, reason বা link থাকে না। On = return transfer-এ reason (damaged / expired / excess / wrong item / other) ও মূল transfer লেখা থাকে।',
  'Off = as before (default): a return to the factory is an ordinary reverse transfer with no reason or link. On = a return transfer records its reason (damaged / expired / excess / wrong item / other) and the original transfer.', 1151),
 ('transfer_notify_receiver', 'notify', 'switch', 'false', null, null, null, null,
  'মাল পাঠালে গ্রহণকারী শাখাকে জানানো হবে', 'মাল পাঠালে গ্রহণকারী শাখাকে জানানো হবে', 'Tell the receiving branch when goods are sent',
  'বন্ধ = আগের মতোই (ডিফল্ট): গ্রহণকারী শাখা জানে না মাল পথে আছে (মালিক শুধু অনেক দেরি হলে সতর্কতা পান)। চালু = মাল পাঠানোর সঙ্গে সঙ্গে ওই শাখার ম্যানেজাররা বিজ্ঞপ্তি পান।',
  'Off = আগের মতোই (default): receiving branch জানে না goods পথে আছে (owner শুধু অনেক দেরি হলে alert পান)। On = goods পাঠানোর সঙ্গে সঙ্গে ওই branch-এর manager-রা notification পান।',
  'Off = as before (default): the receiving branch is not told that goods are on the way (the owner only gets an alert after a long delay). On = the managers of that place get a notification as soon as goods are sent.', 1152),
 ('transit_loss_gl_fix', 'stock', 'switch', 'false', null, null, null, null,
  'পথে ক্ষতি (loss মোড) হিসাবে ভুতুড়ে inventory তৈরি করবে না', 'Transit loss (loss mode) accounts-এ phantom inventory তৈরি করবে না', 'Transit loss no longer creates phantom inventory in the accounts',
  'বন্ধ = আগের মতোই (ডিফল্ট)। চালু = location-tagged transfer হিসাবে transit_short_mode = loss বা "ঘাটতি নিষ্পত্তি" করলে inventory-র হিসাব শেষে stock মূল্যের সমান থাকে এবং পথে-ক্ষতির entry আটকে থাকে না। আগে ভুল ওঠা entry বদলায় না।',
  'Off = আগের মতোই (default)। On = location-tagged transfer accounts-এ transit_short_mode = loss বা short resolve করলে inventory GL শেষে stock valuation-এর সমান থাকে এবং transit-loss entry আটকে থাকে না। আগে ভুল ওঠা entry বদলায় না।',
  'Off = as before (default). On = with location-tagged transfer accounting, transit_short_mode = loss or resolving a short leaves the inventory GL equal to the stock valuation and the transit-loss entry is no longer stuck. Entries already posted wrongly are not rewritten.', 1153)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort) values
 ('transfer_late_receive', 'transfer_late_receive', '115', 'stock', 'true'::jsonb, '{}'::text[],
  'দুই গাড়িতে মাল এলে প্রথম গ্রহণেই transfer বন্ধ হয়ে বাকি মাল চিরকাল "ঘাটতি" দেখায়। চালু করলে বাকিটা পরে গ্রহণ করা যায়; আগের কোনো হিসাব বদলায় না।',
  'দুই গাড়িতে মাল এলে প্রথম receive-এই transfer বন্ধ হয়ে বাকি মাল চিরকাল short দেখায়। চালু করলে বাকিটা পরে receive করা যায়; আগের কোনো হিসাব বদলায় না।',
  'When goods arrive in two lorries the first receipt closes the transfer and the rest shows as short for ever. With this on the rest can be received later; nothing already booked changes.', 1150),
 ('transfer_return_marker', 'transfer_return_marker', '115', 'stock', 'true'::jsonb, '{}'::text[],
  'কারখানায় ফেরত মাল এখন সাধারণ transfer থেকে আলাদা করা যায় না। চালু করলে কারণ ও মূল transfer লেখা থাকে, ফলে নষ্ট/মেয়াদ-শেষ/বাড়তি ফেরত আলাদা চেনা যায়।',
  'Factory-তে ফেরত মাল এখন সাধারণ transfer থেকে আলাদা করা যায় না। চালু করলে reason ও মূল transfer লেখা থাকে, ফলে damaged/expired/excess return আলাদা চেনা যায়।',
  'A return to the factory cannot be told apart from a normal transfer. With this on the reason and the original transfer are recorded, so damaged / expired / excess returns can be told apart.', 1151),
 ('transfer_notify_receiver', 'transfer_notify_receiver', '115', 'notify', 'true'::jsonb, '{}'::text[],
  'মাল পাঠানোর খবর গ্রহণকারী শাখা পায় না, তাই মাল পড়ে থাকে। চালু করলে ওই শাখার ম্যানেজাররা সঙ্গে সঙ্গে বিজ্ঞপ্তি পান; কোনো stock বা হিসাব বদলায় না।',
  'Goods পাঠানোর খবর receiving branch পায় না, তাই মাল পড়ে থাকে। চালু করলে ওই branch-এর manager-রা সঙ্গে সঙ্গে notification পান; কোনো stock বা হিসাব বদলায় না।',
  'The receiving branch is not told that goods are on the way, so they sit unreceived. With this on the managers of that place are notified at once; no stock or book changes.', 1152),
 ('transit_loss_gl_fix', 'transit_loss_gl_fix', '115', 'stock', 'true'::jsonb, '{}'::text[],
  'transfer-এর হিসাব (location-tagged) চালু থাকলে এবং কম পৌঁছানো মাল "loss" ধরলে inventory-র হিসাব stock-এর চেয়ে বেশি দেখায়। চালু করলে ঠিক মেলে। শুধু এখন থেকে ওঠা entry-তে কাজ করে।',
  'Transfer accounting (location-tagged) চালু থাকলে এবং short মাল loss ধরলে inventory GL stock-এর চেয়ে বেশি দেখায়। চালু করলে ঠিক মেলে। শুধু এখন থেকে ওঠা entry-তে কাজ করে।',
  'With location-tagged transfer accounting and short goods booked as loss, the inventory in the books ends above the stock. With this on it matches. It only affects entries posted from now on.', 1153)
on conflict (code) do nothing;

-- ---------- GAP-2: receive the rest of a short transfer ----------
create or replace function public.stock_receive_more(p_id uuid, p_qty numeric, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; it public.items; rq numeric; rem numeric; skip numeric; avail numeric; take numeric; o record; ob public.stock_batches; nb bigint; lid bigint; first boolean := true; sid text;
begin
  if not public.rule_on('transfer_late_receive') then raise exception 'feature_off'; end if;
  perform public._client_lock(p_client);
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);      -- access first: nothing below is shown to a stranger
  if p_client is not null and exists (select 1 from public.stock_ledger where client_id = p_client and reason = 'transfer_in' and ref_type = 'transfer' and ref_id = t.id::text) then
    return jsonb_build_object('dup', true, 'id', t.id, 'received_qty', t.received_qty);
  end if;
  if t.status <> 'received' or t.received_qty is null or t.received_qty >= t.qty then raise exception 'not_short'; end if;
  if exists (select 1 from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transit_loss') then raise exception 'short_already_written_off'; end if;
  if exists (select 1 from public.journal_entries e where e.source_type = 'transit_loss' and e.source_id = t.id::text and e.reverses_id is null) then raise exception 'short_already_booked'; end if;
  rq := round(p_qty, 4);
  if rq is null or not (rq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > t.qty - t.received_qty + 0.00005 then raise exception 'over_received'; end if;
  if not public._may('stock_transfer', t.to_location_id, 'receive_more:' || p_id::text, rq) then raise exception 'not allowed'; end if;
  rem := least(rq, t.qty - t.received_qty); skip := t.received_qty;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    avail := -o.qty_delta;
    if skip >= avail then skip := skip - avail; continue; end if;          -- this part of the lorry was received the first time
    avail := avail - skip; skip := 0;
    take := least(avail, rem); nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none', null, case when first then p_client end);
    first := false; rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set received_qty = received_qty + rq, receive_note = left(coalesce(receive_note || ' | ', '') || coalesce(p_note, 'rest received'), 200) where id = t.id;
  perform public._stock_exc(t.to_location_id, 'transit_short_late', 'yellow',
    it.name_bn || ': বাকি মাল পরে গ্রহণ ' || rq::text || ', এখনো ঘাটতি ' || (t.qty - t.received_qty - rq)::text, coalesce(it.name_en, it.name_bn) || ': the rest was received later: ' || rq::text || ', still short ' || (t.qty - t.received_qty - rq)::text);
  return jsonb_build_object('id', t.id, 'received_qty', t.received_qty + rq, 'short', t.qty - t.received_qty - rq);
end $$;
revoke all on function public.stock_receive_more(uuid, numeric, text, uuid) from public, anon;
grant execute on function public.stock_receive_more(uuid, numeric, text, uuid) to authenticated;

-- ---------- GAP-3: a marked return to the factory ----------
create or replace function public.stock_return_transfer(p_from integer, p_to integer, p_item uuid, p_qty numeric, p_reason text, p_ref uuid default null,
                                                       p_unit text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.stock_transfers; r jsonb; bq numeric; prior numeric; t public.stock_transfers;
begin
  if not public.rule_on('transfer_return_marker') then raise exception 'feature_off'; end if;
  if not public.can_loc(p_from) then raise exception 'not allowed for this location'; end if;
  if p_reason is null or p_reason not in ('damaged', 'expired', 'excess', 'wrong_item', 'other') then raise exception 'reason_required'; end if;
  if p_reason = 'other' and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_needed'; end if;
  if p_client is not null then
    select * into t from public.stock_transfers where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status, 'kind', t.kind); end if;
  end if;
  if p_ref is not null then
    select * into o from public.stock_transfers where id = p_ref;
    if not found or o.item_id <> p_item or o.from_location_id <> p_to or o.to_location_id <> p_from or o.status <> 'received' then raise exception 'bad_ref'; end if;
    bq := public._base_qty(p_item, p_qty, p_unit);
    select coalesce(sum(x.qty), 0) into prior from public.stock_transfers x where x.ref_transfer_id = p_ref and x.kind = 'return' and x.status <> 'cancelled';
    if bq is not null and bq > coalesce(o.received_qty, 0) - prior + 0.00005 then raise exception 'return_exceeds_receipt'; end if;
  end if;
  r := public.stock_transfer(p_from, p_to, p_item, p_qty, p_unit, p_note, p_client);
  if not coalesce((r->>'dup')::boolean, false) then
    update public.stock_transfers set kind = 'return', reason = p_reason, ref_transfer_id = p_ref where id = (r->>'id')::uuid;
  end if;
  return r || jsonb_build_object('kind', 'return', 'reason', p_reason);
end $$;
revoke all on function public.stock_return_transfer(integer, integer, uuid, numeric, text, uuid, text, text, uuid) from public, anon;
grant execute on function public.stock_return_transfer(integer, integer, uuid, numeric, text, uuid, text, text, uuid) to authenticated;

-- ---------- patches of the live bodies ----------
-- GAP-6: tell the receiving place
do $do$ begin perform public._b2_patch115('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)',
$a$  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$a$,
$a$  if public.rule_on('transfer_notify_receiver') then   -- bos115:xfer-notify
    perform public._notif_add('transfer_sent', 'info', 'মাল পথে: ' || coalesce(it.name_bn, ''), 'Goods on the way: ' || coalesce(it.name_en, it.name_bn, ''),
      'পরিমাণ ' || trim_scale(bq)::text || ' — গ্রহণ করতে স্টক পাতার "পথে" ট্যাব দেখুন।', 'Quantity ' || trim_scale(bq)::text || ' — open the Stock page, tab "In transit", to receive.', 'stock', tid::text, 'manager', p_to);
  end if;
  return jsonb_build_object('id', tid, 'status', 'sent', 'qty', bq);$a$,
'bos115:xfer-notify'); end $do$;

-- GAP-4 (a): the synthetic "+short" transfer_in written by _transit_loss83 gets no inventory / clearing leg
do $do$ begin perform public._b2_patch115('public._acct_stock_moves85(date)',
$a$public.rule_on('acct_manual_prod_in103') p /* bos103 */)$a$,
$a$public.rule_on('acct_manual_prod_in103') p /* bos103 */, public.rule_on('transit_loss_gl_fix') g115 /* b2s115:cfg */)$a$,
'b2s115:cfg'); end $do$;
do $do$ begin perform public._b2_patch115('public._acct_stock_moves85(date)',
$a$l.qty_delta, l.reason = 'reversal' rv,$a$,
$a$l.qty_delta, l.reason = 'reversal' rv, (l.reason = 'transfer_in' and l.client_id is not null and l.client_id = md5(coalesce(l.ref_id, '') || ':tl_in')::uuid) syn115 /* b2s115:syn */,$a$,
'b2s115:syn'); end $do$;
do $do$ begin perform public._b2_patch115('public._acct_stock_moves85(date)',
$a$where m.cls is not null and m.d >= cfg.f$a$,
$a$where m.cls is not null and m.d >= cfg.f and not (cfg.g115 and m.syn115) /* b2s115:where */$a$,
'b2s115:where'); end $do$;

-- GAP-4 (b): the transit-loss entry counts only the real transfer rows (the synthetic pair nets to zero in the stock book and has no leg)
do $do$ begin perform public._b2_patch115('public._acct_docs(date)',
$a$from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')) c$a$,
$a$from public.stock_ledger_eff96 s /* bos96 */ where s.ref_type = 'transfer' and s.ref_id = t.id::text and s.reason in ('transfer_out', 'transfer_in')
      and (not public.rule_on('transit_loss_gl_fix') or s.client_id is distinct from md5(t.id::text || ':tl_in')::uuid) /* b2s115:docs */) c$a$,
'b2s115:docs'); end $do$;

drop function public._b2_patch115(text, text, text, text);

commit;
