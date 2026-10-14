-- ============================================================
-- Phase 83 (bos83) - STEP E-b: form vs screen (E5), expense double count (E6), transit shortage (E7), offline POS failed sales (E8).
--   Needs phase8 ... phase71 (phase72 is on another branch and is NOT needed). Additive; paste-twice safe. No old phase file is edited. Nothing is posted by this file.
--   NEW SWITCHES - every default is today's behaviour; the app shows a RECOMMENDED value with a reason (form_guard_recommendations()) but never forces it:
--     form_051_mode        reference | post | refuse   default reference = unchanged (form 05-1 behaves exactly as before; a NULL-cost finished line is now FLAGGED)
--                          post   = a posted 05-1 line also takes the recipe ingredients OUT of stock at the average cost and costs the finished goods
--                          refuse = 05-1 is never a posting source (lines kept as 'skipped: form051_not_a_source')
--     transit_short_mode   keep_in_transit | loss   default keep_in_transit = unchanged (a short receipt books nothing, only the yellow flag as before)
--                          loss = the shortfall is booked in the ledger as reason transit_loss (cost = the sender's cost)
--     transit_open_hours   blank (no limit written in code); a number = open transit older than that many hours becomes an urgent notification
--     offline_soft_stock   off (default) | on : a sale replayed from the offline queue that is refused only for 'insufficient_stock' is accepted and flagged instead
--   E5 : unmatched_forms() ; pending shadow link when a form is skipped because the screen is the record ; dup_suspects 'production_screens' branch
--   E6 : dup_suspects 'expense' branch ; suggest_expense_link(entry) ; expense_link_apply(entry, note)
--   E7 : transit_loss ledger reason ; transit_short_open() ; transit_short_resolve() ; transit_open_list() ; urgent_alerts() also scans old open transit
--   E8 : record_sale_offline() (same arguments as record_sale2) ; pos_replay_override() manager override with the ORIGINAL client_id ; pos_failed_* board table
--   RE-CREATED from their LATEST definition (only lines marked bos83 differ): _elp_post_line, dup_suspects, stock_receive_transfer, urgent_alerts, _sale_stock_out.
--   NOT re-created (another agent owns them): production_post, recipe_cost, _acct_docs, _p27_pl, biz_daily, acct_status, post_purchase, void_purchase.
-- ============================================================

-- ---------- 1. switches ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('form_051_mode', 'stock', 'choice', '"reference"', null, '["reference","post","refuse"]'::jsonb, null, null,
  'কারখানা দৈনিক শিট (05-1): stock-এ কীভাবে ধরা হবে', 'Factory daily sheet (05-1): stock-এ কীভাবে ধরা হবে', 'Factory daily sheet (05-1): how it reaches stock',
  'reference = আগের মতোই (ডিফল্ট)। post = শিট stock-এ গেলে recipe-র ingredientও গড় দামে বের হবে ও তৈরি মালের cost বসবে। refuse = 05-1 কখনো stock পোস্ট করবে না।',
  'reference = আগের মতোই (default)। post = sheet stock-এ গেলে recipe-র ingredient-ও average cost-এ বের হবে ও finished goods-এর cost বসবে। refuse = 05-1 কখনো stock post করবে না।',
  'reference = exactly as before (default). post = when the sheet posts to stock, the recipe ingredients also go out at the average cost and the finished goods get a cost. refuse = 05-1 never posts to stock.', 840),
 ('transit_short_mode', 'stock', 'choice', '"keep_in_transit"', null, '["keep_in_transit","loss"]'::jsonb, null, null,
  'transfer-এ কম পৌঁছালে ঘাটতি কীভাবে ধরা হবে', 'Transfer-এ কম পৌঁছালে ঘাটতি কীভাবে ধরা হবে', 'How a short transfer receipt is booked',
  'keep_in_transit = আগের মতোই (ডিফল্ট; শুধু হলুদ সতর্কতা, ঘাটতি তালিকায় থাকে)। loss = ঘাটতি stock খাতায় "পথে ক্ষতি" হিসেবে ওঠে।',
  'keep_in_transit = আগের মতোই (default; শুধু yellow flag, ঘাটতি list-এ থাকে)। loss = ঘাটতি stock ledger-এ transit loss হিসেবে ওঠে।',
  'keep_in_transit = as before (default; only the yellow flag, the shortfall stays on a list). loss = the shortfall is booked in the stock ledger as a transit loss.', 841),
 ('transit_open_hours', 'stock', 'number', null, 'hours', null, 1, 8760,
  'পথে থাকা transfer কত ঘণ্টা পর জরুরি সতর্কতা', 'Transit-এ থাকা transfer কত ঘণ্টা পর urgent alert', 'Open transfers older than this many hours raise an urgent alert',
  'ঘর খালি = কোনো সতর্কতা নয় (ডিফল্ট)। সংখ্যা দিলে সেই ঘণ্টার বেশি "পাঠানো হয়েছে, গ্রহণ হয়নি" থাকলে জরুরি বার্তা আসে।',
  'ঘর খালি = কোনো alert নয় (default)। সংখ্যা দিলে সেই ঘণ্টার বেশি sent-but-not-received থাকলে urgent notification আসে।',
  'Blank = no alert (default). A number: a transfer that stays sent but not received for longer than that raises an urgent notification.', 842),
 ('offline_soft_stock', 'pos', 'switch', 'false', null, null, null, null,
  'offline-এ করা sale stock-এ না কুলালেও গ্রহণ', 'Offline-এ করা sale stock-এ না কুলালেও গ্রহণ', 'Accept offline sales even when stock is short',
  'বন্ধ = আগের মতোই (ডিফল্ট)। চালু = offline সারি থেকে আবার পাঠানো sale শুধু stock কম বলে আটকালে সেটা গ্রহণ হয় ও হলুদ সতর্কতা থাকে (পণ্য আগেই দেওয়া হয়ে গেছে)। অনলাইন sale বদলায় না।',
  'Off = আগের মতোই (default)। On = offline queue থেকে replay করা sale শুধু stock কম বলে আটকালে accept হয় ও yellow flag থাকে (goods আগেই দেওয়া হয়ে গেছে)। Online sale বদলায় না।',
  'Off = as before (default). On = a sale re-sent from the offline queue that is refused only because stock is short is accepted and flagged yellow (the goods were already handed over). Online sales do not change.', 843)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('pos_replay_override', 'pos', 84, 'offline sale manager override-এ আবার পাঠানো', 'Offline sale manager override-এ আবার পাঠানো', 'Re-send a refused offline sale on manager override', 'window', null)
on conflict (grant_code) do nothing;

-- ---------- 2. ledger reason transit_loss (merge-safe: the current list is read and one value added) ----------
do $$
declare d text; vals text;
begin
  select pg_get_constraintdef(oid) into d from pg_constraint where conrelid = 'public.stock_ledger'::regclass and conname = 'stock_ledger_reason_check';
  if d is not null and d not like '%transit_loss%' then
    vals := substring(d from 'ARRAY\[(.*)\]\)');
    alter table public.stock_ledger drop constraint stock_ledger_reason_check;
    execute 'alter table public.stock_ledger add constraint stock_ledger_reason_check check (reason = any (array[' || regexp_replace(vals, '::text', '', 'g') || ', ''transit_loss'']))';
  end if;
end $$;

-- ---------- 3. E7 helpers ----------
-- the shortfall of a received transfer is written off: +short (cost blank, so the average does not move) then -short as transit_loss at the SENDER's cost. Net balance change 0.
create or replace function public._transit_loss83(p_transfer uuid, p_short numeric, p_note text) returns bigint
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; cost numeric; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_transfer;
  if not found or p_short is null or p_short <= 0 then return null; end if;
  if exists (select 1 from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transit_loss') then return null; end if;
  select case when sum(-qty_delta) > 0 then sum(-qty_delta * unit_cost) / sum(-qty_delta) end into cost
    from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' and unit_cost is not null;
  perform public.stock_post(t.item_id, t.to_location_id, p_short, 'transfer_in', 'transfer', t.id::text, null, null, now(), left('transit short: counted in to be written off ' || coalesce(p_note, ''), 200), null, 'none', null, md5(t.id::text || ':tl_in')::uuid);
  lid := public.stock_post(t.item_id, t.to_location_id, -p_short, 'transit_loss', 'transfer', t.id::text, case when cost is null then null else round(cost, 6) end, null, now(), left('transit loss ' || coalesce(p_note, ''), 200), null, 'none', null, md5(t.id::text || ':tl')::uuid);
  return lid;
end $$;

-- open transit older than the owner's limit -> an urgent notification (once per transfer per day). Blank limit = nothing happens.
create or replace function public._transit_open_scan83() returns int
language plpgsql security definer set search_path = public as $$
declare h numeric := public.rule_num('transit_open_hours'); r record; n int := 0;
begin
  if h is null or h <= 0 then return 0; end if;
  for r in select t.id, t.qty, t.from_location_id, t.to_location_id, t.sent_at, i.name_bn, i.name_en, i.code
             from public.stock_transfers t join public.items i on i.id = t.item_id
            where t.status = 'sent' and t.sent_at < now() - make_interval(secs => (h * 3600)::double precision) order by t.sent_at limit 200 loop
    if public._notif_add('transit_open', 'bad', 'পথে থাকা transfer এখনো গ্রহণ হয়নি', 'A transfer is still in transit',
         r.name_bn || ' ' || r.qty::text || ': পাঠানো হয়েছে, গ্রহণ হয়নি', coalesce(r.name_en, r.code) || ' ' || r.qty::text || ': sent, not yet received',
         'stock', r.id::text, 'owner', r.to_location_id) then n := n + 1; end if;
  end loop;
  return n;
end $$;

-- ---------- 4. re-created functions (latest definitions; lines marked bos83 differ) ----------
CREATE OR REPLACE FUNCTION public._elp_post_line(e entries, g integer, sg text, l jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it public.items; n int := (l->>'n')::int; kind text := l->>'kind'; qty numeric := nullif(l->>'qty', '')::numeric; bq numeric; f numeric; ucb numeric;
        ref text := e.id::text || ':g' || g::text || ':' || n::text; lid bigint; olid bigint; bal public.stock_balance; d numeric; tid uuid; fl int := nullif(l->>'from', '')::int;
        tl int := nullif(l->>'to', '')::int; rq numeric; rbq numeric; note text := nullif(l->>'note', ''); at_ timestamptz := now(); sl jsonb; exp timestamptz; bid bigint; sid text;
        stt text := 'posted'; why text; ucost numeric;
        fmode text; rc public.recipes; nr record; tot numeric := 0; cok boolean := true; av numeric; yf numeric;   -- bos83
begin
  -- phase 23: the purchase page already posts bought goods; a GRN (04-1) 'in' line would count them twice unless the owner chose the GRN as the source
  if l->>'skip' is null and kind = 'in' and e.form_code = '04-1' and coalesce(public.rule_txt('grn_receipt_source'), 'purchase') = 'purchase' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_purchase_page', ref, auth.uid());
    return;
  end if;
  -- bos51: while the stock screen / recipe run is the record (owner switch), a form line is a reference: kept, shown as skipped, never posted a second time
  if l->>'skip' is null and public._entry_domain(e.form_code) is not null and public.path_primary(public._entry_domain(e.form_code), e.location_id) = 'a' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'covered_by_screen', ref, auth.uid());
    -- bos83: the slip has no screen record yet: a PENDING link (form -> screen record owed) so unmatched_forms() can list it
    begin perform public.shadow_link_add(public._entry_domain(e.form_code), e.location_id, 'entries', e.id::text, 'stock_screen', null, 'form ' || e.form_code || ' skipped: the screen is the record, screen record owed'); exception when others then null; end;
    return;
  end if;
  -- bos83: owner switch form_051_mode = refuse: the factory daily sheet is not a posting source at all (kept as a reference, line shown as skipped)
  fmode := coalesce(public.rule_txt('form_051_mode'), 'reference');
  if l->>'skip' is null and kind = 'prod' and e.form_code = '05-1' and fmode = 'refuse' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, null, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', 'form051_not_a_source', ref, auth.uid());
    return;
  end if;
  if l->>'skip' is null and kind = 'transfer' then
    if (fl is not null and fl <> e.location_id) or (fl is null and tl is not null and tl <> e.location_id) then why := 'location_mismatch'; stt := 'skipped';
    elsif not (public.is_owner() or ((fl is null or public.can_loc(fl)) and (tl is null or public.can_loc(tl)))) then why := 'location_mismatch'; stt := 'skipped';
    end if;
  end if;
  if l->>'skip' is not null then why := l->>'skip'; stt := 'skipped';
  elsif stt = 'skipped' then null;
  else
    if l->>'item' is null then raise exception 'item_missing'; end if;
    select * into it from public.items where code = l->>'item';
    if not found then raise exception 'item_not_found: %', l->>'item'; end if;
    if not it.is_active then raise exception 'item_not_active: %', it.code; end if;
    if not it.tracked then why := 'not_tracked'; stt := 'skipped';
    elsif not it.count_in_business then why := 'not_counted'; stt := 'skipped';
    end if;
  end if;
  if stt = 'skipped' then
    insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
      values (e.id, g, n, e.form_code, e.location_id, tl, kind, (select i.id from public.items i where i.code = l->>'item'), left(l->>'item', 60), null, sg, 'skipped', why, ref, auth.uid());
    return;
  end if;
  if qty is null then raise exception 'qty_missing'; end if;
  if kind <> 'count' and not (qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if kind = 'count' and not (qty between 0 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(it.id, qty, it.unit);
  if bq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  if not (bq between case when kind = 'count' then 0 else 0.0001 end and 999999999) then raise exception 'bad_qty'; end if;
  f := public._unit_factor_base(it.id, it.unit);
  if f is null or not (f > 0) then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
  ucost := nullif(l->>'cost', '')::numeric;
  if ucost is not null and not (ucost between 0 and 1000000000000) then ucost := null; end if;
  ucb := case when ucost is null then null else ucost / f end;

  if kind = 'in' then
    lid := public.stock_post(it.id, e.location_id, bq, 'purchase_in', 'entry', ref, ucb, null, at_, note, null, 'none');
  elsif kind = 'out' then
    lid := public.stock_post(it.id, e.location_id, -bq, 'issue_out', 'entry', ref, null, null, at_, note, null, 'full');
  elsif kind = 'count' then
    -- the count is against the system balance written on the sheet at COUNT time (a snapshot of the live balance is not possible later): delta = counted - that figure, applied to the CURRENT balance
    insert into public.stock_balance (item_id, location_id) values (it.id, e.location_id) on conflict do nothing;
    select * into bal from public.stock_balance where item_id = it.id and location_id = e.location_id for update;
    rbq := public._base_qty(it.id, nullif(l->>'book', '')::numeric, it.unit);
    if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
    d := round(bq - rbq, 4);
    if d <> 0 then lid := public.stock_post(it.id, e.location_id, d, 'count_adjust', 'entry', ref, null, null, at_, left(coalesce(note, 'stock count'), 200), null, 'none'); end if;
    why := case when d = 0 then 'no_change' else 'delta ' || d::text end;
  elsif kind = 'prod' then
    sl := public.shelf_life_for(it.id, (at_ at time zone 'Asia/Dhaka')::date);
    exp := case when sl is null then null else at_ + ((sl->>'hours')::float8 * interval '1 hour') end;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
      values (it.id, e.location_id, at_, bq, bq, exp, sl, left(note, 200), auth.uid()) returning id into bid;
    ucb := null;
    if e.form_code = '05-1' and fmode = 'post' then      -- bos83: the finished goods are made FROM the recipe's ingredients, taken out at the average cost
      select r.* into rc from public.recipes r where r.item_id = it.id and r.active and exists (select 1 from public.recipe_lines x where x.recipe_id = r.id and x.active) order by r.version desc limit 1;
      if not found then raise exception 'no_recipe_for_051: %', it.code; end if;
      perform public._recipe_gate73(rc.id);
      yf := public._base_qty(rc.item_id, rc.yield_qty, rc.yield_unit);
      if yf is null or not (yf > 0) then raise exception 'unit_unknown: %', it.code; end if;
      for nr in select * from public._recipe_need(rc.id, bq / yf, e.location_id) order by item_id loop
        if not nr.tracked then raise exception 'ingredient_not_tracked: %', coalesce(nr.code, ''); end if;
        if not nr.unit_ok then raise exception 'unit_unknown: %', coalesce(nr.code, ''); end if;
        if nr.need < 0.0001 then continue; end if;
        select b.avg_cost into av from public.stock_balance b where b.item_id = nr.item_id and b.location_id = e.location_id;
        if av is null then cok := false; else tot := tot + nr.need * av; end if;
        perform public.stock_post(nr.item_id, e.location_id, -nr.need, 'issue_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
      end loop;
      ucb := case when cok and bq > 0 then round(tot / bq, 6) end;
    end if;
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, ucb, bid, at_, left(note, 200), null, 'none');
    if ucb is null and e.form_code = '05-1' and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'form051_cost_null' and x.status = 'open') then      -- bos83
      insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (e.id, e.form_code, e.location_id, e.entry_date, 'form051_cost_null', 'yellow', null,
          jsonb_build_object('bn', e.form_code || '-' || e.serial || ': ' || it.name_bn || ' তৈরি মাল cost ছাড়া stock-এ ঢুকেছে (cost অজানা)',
                             'en', e.form_code || '-' || e.serial || ': ' || coalesce(it.name_en, it.name_bn) || ' entered stock with NO cost (cost unknown)'));
    end if;
  elsif kind = 'transfer' then
    if fl is not null and tl is not null then
      if fl = tl then raise exception 'same_location'; end if;
      rq := nullif(l->>'recv', '')::numeric;
      if rq is not null then
        if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
        rbq := public._base_qty(it.id, rq, it.unit);
        if rbq is null then raise exception 'unit_unknown: % %', it.code, coalesce(it.unit, ''); end if;
        if rbq > bq then raise exception 'over_received'; end if;
      end if;
      tid := gen_random_uuid(); select staff_id into sid from public.profiles where id = auth.uid();
      insert into public.stock_transfers (id, from_location_id, to_location_id, item_id, qty, status, received_qty, note, sent_by, sent_staff, sent_at,
          received_by, received_staff, received_at)
        values (tid, fl, tl, it.id, bq, case when rq is null then 'sent' else 'received' end, rbq, left(note, 200), auth.uid(), sid, at_,
          case when rq is null then null else auth.uid() end, case when rq is null then null else sid end, case when rq is null then null else at_ end);
      olid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'transfer', tid::text, null, null, at_, left(note, 200), null, 'full');
      if rq is not null and rbq > 0 then
        select unit_cost into ucost from public.stock_ledger where id = olid;
        perform public.stock_post(it.id, tl, rbq, 'transfer_in', 'transfer', tid::text, ucost, null, at_, left(note, 200), null, 'none');
      end if;
      why := case when rq is null then 'in_transit' when rbq < bq then 'short ' || (bq - rbq)::text else null end;
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, transfer_id, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, tid, auth.uid());
      return;
    elsif fl is not null then          -- goods leave for a place outside the tracked places (customer, party ...): the sender's out leg only
      lid := public.stock_post(it.id, fl, -bq, 'transfer_out', 'entry', ref, null, null, at_, left(note, 200), null, 'full');
    elsif tl is not null then          -- goods come in from outside (party return ...): the receiver's in leg only
      lid := public.stock_post(it.id, tl, coalesce(public._base_qty(it.id, nullif(l->>'recv', '')::numeric, it.unit), bq), 'transfer_in', 'entry', ref, null, null, at_, left(note, 200), null, 'none');
    else raise exception 'location_missing';
    end if;
  end if;
  insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_id, item_code, qty_base, sig, status, reason, ref, posted_by)
    values (e.id, g, n, e.form_code, coalesce(fl, e.location_id), tl, kind, it.id, it.code, bq, sg, 'posted', why, ref, auth.uid());
end $function$;
CREATE OR REPLACE FUNCTION public.dup_suspects(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_range'; end if;
  return jsonb_build_object('from', p_from, 'to', p_to,
    -- D1: a payroll month paid in the app AND a 02-2 sheet for the same place and month
    'payroll', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.id as run_id, r.month, r.location_id, e.id as entry_id, e.serial, e.status as form_status
          from public.payroll_runs r join public.entries e on e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = coalesce(r.location_id, e.location_id)
            and date_trunc('month', e.entry_date) = date_trunc('month', r.month::timestamp)
         where r.status <> 'void' and r.month between date_trunc('month', p_from)::date and p_to
           and not public.is_shadow('entries', e.id::text) order by r.month, r.id limit 200) z), '[]'::jsonb),
    -- D2: a form-posted stock line (ref_type entry) and a screen-posted line for the same item, place, day, reason and quantity
    'stock', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.reason, f.qty_delta, f.id as form_ledger_id, s.id as screen_ledger_id
          from public.stock_ledger f join public.stock_ledger s on s.item_id = f.item_id and s.location_id = f.location_id and s.reason = f.reason and s.qty_delta = f.qty_delta
            and (s.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date and coalesce(s.ref_type, '') <> 'entry' and s.id <> f.id and s.reverses_id is null
         where f.ref_type = 'entry' and f.reverses_id is null and f.reason in ('issue_out', 'transfer_out', 'transfer_in', 'count_adjust', 'production_in', 'purchase_in')
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and coalesce(s.ref_type, '') not in ('sale', 'sale_pack', 'sale_return') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D3: a 05-1 output line posted from the form and a production run for the same finished item, place and day
    'production', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select f.item_id, f.location_id, (f.made_at at time zone 'Asia/Dhaka')::date as day, f.qty_delta, f.id as form_ledger_id, r.id as run_id
          from public.stock_ledger f join public.production_runs r on r.item_id = f.item_id and r.location_id = f.location_id and r.status = 'done'
            and (r.made_at at time zone 'Asia/Dhaka')::date = (f.made_at at time zone 'Asia/Dhaka')::date
         where f.ref_type = 'entry' and f.reason = 'production_in' and f.reverses_id is null
           and f.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and f.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka') order by f.made_at limit 200) z), '[]'::jsonb),
    -- D4: an owner top-up / draw in partner capital and the same amount on a cash move within 3 days
    'owner_money', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select pc.id as capital_id, pc.cap_date, pc.kind as capital_kind, pc.amount, m.id as cash_move_id, m.move_date, m.kind as cash_kind, m.location_id
          from public.partner_capital pc join public.cash_moves m on m.kind in ('owner_topup', 'owner_draw') and m.status = 'done' and m.amount = pc.amount and abs(m.move_date - pc.cap_date) <= 3
         where pc.status = 'posted' and pc.cap_date between p_from and p_to and not public.is_shadow('cash_moves', m.id::text) order by pc.cap_date limit 200) z), '[]'::jsonb),
    -- D8: a hub receipt (cash move) and a cash handover slip 10-1 for the same place and day
    'handover', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select m.id as cash_move_id, m.move_date, m.location_id, m.amount, e.id as entry_id, e.serial
          from public.cash_moves m join public.entries e on e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date = m.move_date
         where m.kind = 'hub_receipt' and m.status = 'done' and m.move_date between p_from and p_to order by m.move_date limit 200) z), '[]'::jsonb),
    -- bos83 F10: two finished-goods screens for the same item, place and day - a recipe run (production_post) and a plain finished-goods entry (stock_production_in)
    'production_screens', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select r.item_id, r.location_id, (r.made_at at time zone 'Asia/Dhaka')::date as day, r.id as run_id, s.id as plain_ledger_id, s.qty_delta as plain_qty, r.yield_base as run_qty
          from public.production_runs r join public.stock_ledger s on s.item_id = r.item_id and s.location_id = r.location_id and s.reason = 'production_in' and s.ref_type = 'production'
            and s.reverses_id is null and s.id is distinct from r.ledger_in_id and (s.made_at at time zone 'Asia/Dhaka')::date = (r.made_at at time zone 'Asia/Dhaka')::date
         where r.status = 'done' and r.made_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and r.made_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
           and not exists (select 1 from public.production_runs r2 where r2.ledger_in_id = s.id) order by r.made_at limit 200) z), '[]'::jsonb),
    -- bos83 E6 (a4-F5): a quick expense and an approved 10-2 voucher line for the same place, day, head and amount that are NOT linked as a shadow
    'expense', coalesce((select jsonb_agg(to_jsonb(z)) from (
        select q.id as quick_id, q.location_id, q.exp_date as day, q.head, q.amount, e.id as entry_id, e.serial
          from public.quick_expenses q
          join public.entries e on e.form_code = '10-2' and e.status = 'approved' and e.location_id = q.location_id and e.entry_date = q.exp_date
            and jsonb_typeof(e.data -> 'lines') = 'array' and not public.is_shadow('entries', e.id::text)
          join lateral jsonb_array_elements(e.data -> 'lines') ln on lower(btrim(ln ->> 'head')) = q.head and public._db_num(ln -> 'amount') = q.amount
         where q.status = 'done' and q.exp_date between p_from and p_to
           and not exists (select 1 from public.shadow_links x where x.primary_type = 'quick_expenses' and x.primary_id = q.id::text and x.state = 'confirmed')
         order by q.exp_date, q.id limit 200) z), '[]'::jsonb));
end $function$;
CREATE OR REPLACE FUNCTION public.stock_receive_transfer(p_id uuid, p_received_qty numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.stock_transfers; it public.items; rq numeric; sid text; o record; rem numeric; take numeric; nb bigint; cost numeric; ob public.stock_batches; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if t.status = 'received' then return jsonb_build_object('dup', true, 'id', t.id, 'status', t.status); end if;
  if t.status <> 'sent' then raise exception 'not_in_transit'; end if;
  it := public._stock_guard(t.item_id, t.to_location_id, 'stock_transfer', (now() at time zone 'Asia/Dhaka')::date);
  if not public._may('stock_transfer', t.to_location_id, 'receive:' || p_id::text, t.qty) then raise exception 'not allowed'; end if;
  rq := coalesce(p_received_qty, t.qty);
  if not (rq between 0 and 999999999) then raise exception 'bad_qty'; end if;
  if rq > t.qty then raise exception 'over_received'; end if;
  rem := rq;
  for o in select * from public.stock_ledger where ref_type = 'transfer' and ref_id = t.id::text and reason = 'transfer_out' order by id loop
    exit when rem <= 0;
    take := least(-o.qty_delta, rem);
    nb := null;
    if o.batch_id is not null then       -- the batch travels with the goods: same made-at and expiry at the destination
      select * into ob from public.stock_batches where id = o.batch_id;
      insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by)
        values (t.item_id, t.to_location_id, ob.made_at, take, take, ob.expires_at, ob.shelf_rule, 'transfer', auth.uid()) returning id into nb;
    end if;
    lid := public.stock_post(t.item_id, t.to_location_id, take, 'transfer_in', 'transfer', t.id::text, o.unit_cost, nb, now(), left(p_note, 200), null, 'none');
    rem := rem - take;
  end loop;
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.stock_transfers set status = 'received', received_qty = rq, receive_note = left(p_note, 200), received_by = auth.uid(), received_staff = sid, received_at = now() where id = t.id;
  if rq < t.qty then
    perform public._stock_exc(t.to_location_id, 'transit_short', 'yellow',
      it.name_bn || ': পাঠানো ' || t.qty::text || ', গ্রহণ ' || rq::text || ' — পথে কম', coalesce(it.name_en, it.name_bn) || ': sent ' || t.qty::text || ', received ' || rq::text || ' — short in transit');
  end if;
  if rq < t.qty and coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit') = 'loss' then      -- bos83: the owner chose to book the shortfall as a loss
    perform public._transit_loss83(t.id, t.qty - rq, p_note);
  end if;
  return jsonb_build_object('id', t.id, 'status', 'received', 'received_qty', rq, 'short', t.qty - rq);
end $function$;
CREATE OR REPLACE FUNCTION public.urgent_alerts(p_since timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._transit_open_scan83();      -- bos83: open transit older than the owner's limit becomes an urgent notification (blank limit = nothing)
  return coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title_bn', n.title_bn, 'title_en', n.title_en, 'body_bn', n.body_bn, 'body_en', n.body_en, 'route', n.route, 'created_at', n.created_at) order by n.id)
                     from public.notifications n
                    where n.level = 'bad' and n.emailed_at is null and n.user_id is null and n.audience in ('owner', 'all')
                      and n.created_at >= coalesce(p_since, now() - interval '2 days')), '[]'::jsonb);
end $function$;
CREATE OR REPLACE FUNCTION public._sale_stock_out()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ln jsonb; it public.items; q numeric; bq numeric; neg text; soft83 boolean := false; bal83 numeric;
begin
  if new.status <> 'done' or new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  -- a sale that syncs late (an offline phone) has already happened: it is recorded, it never blocks (a yellow line still tells the owner)
  neg := case when new.sold_at < now() - interval '2 minutes' then 'soft' else 'full' end;
  -- bos83: a sale replayed from the offline queue (record_sale_offline / manager override) is soft too when the owner switch offline_soft_stock is on (override: always) - flagged below
  if neg = 'full' and coalesce(current_setting('bos.offline_replay', true), '') = '1'
     and (public.rule_on('offline_soft_stock') or coalesce(current_setting('bos.replay_override', true), '') = '1') then neg := 'soft'; soft83 := true; end if;
  -- items in a fixed order, so two sales that share items can never wait on each other in a circle
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null order by x->>'item_id' loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found or not it.tracked then continue; end if;
    q := nullif(ln->>'qty', '')::numeric;
    if q is null or q <= 0 then continue; end if;
    if not (q <= 999999999) then raise exception 'bad_qty'; end if;                    -- Infinity / NaN / absurd: the sale is refused
    bq := public._base_qty(it.id, q, ln->>'unit');
    if bq is null then
      perform public._stock_exc(new.location_id, 'stock_unit_unknown', 'yellow',
        'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, stock কমানো হয়নি',
        'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, stock was NOT reduced', new.id, new.sale_date, 'POS');
      continue;
    end if;
    if not (bq <= 999999999) then raise exception 'bad_qty'; end if;
    if round(bq, 4) = 0 then continue; end if;                                          -- under 0.00005 of a base unit: nothing to take out
    if soft83 then      -- bos83
      select b.qty into bal83 from public.stock_balance b where b.item_id = it.id and b.location_id = new.location_id;
      if coalesce(bal83, 0) < bq then
        perform public._stock_exc(new.location_id, 'offline_soft_stock', 'yellow',
          'রসিদ ' || new.receipt || ': ' || it.name_bn || ' — offline sale, stock-এর চেয়ে বেশি; sale গ্রহণ হয়েছে, stock ঋণাত্মক হতে পারে',
          'Receipt ' || new.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — offline sale above the stock on hand; accepted, stock may go negative', new.id, new.sale_date, 'POS');
      end if;
    end if;
    perform public.stock_post(it.id, new.location_id, -bq, 'sale_out', 'sale', new.id::text, null, null, new.sold_at, null, null, neg, new.id);
  end loop;
  return new;
end $function$;

-- ============================================================
-- E5 : form vs screen
-- ============================================================
-- forms that were skipped because the screen is the record, and for which NO screen record exists (same item, place, day, same kind of action). Read-only.
create or replace function public.unmatched_forms(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); own boolean := public.is_owner(); rows jsonb; tot int; unm int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 366 then raise exception 'bad_range'; end if;
  with lg as (select entry_id, max(gen) g from public.entry_ledger_posts group by entry_id),
  sk as (
    select e.id as entry_id, e.form_code, e.serial, e.location_id, e.entry_date, p.line_no, p.item_id, p.item_code, p.qty_base
      from public.entries e join lg on lg.entry_id = e.id
      join public.entry_ledger_posts p on p.entry_id = e.id and p.gen = lg.g and p.status = 'skipped' and p.reason = 'covered_by_screen'
     where e.status = 'approved' and e.form_code in ('04-2', '03-1', '04-3', '05-1') and e.entry_date between f and t and (p_loc is null or e.location_id = p_loc)
       and (own or (public.can_loc(e.location_id) and public.can_do(e.form_code, 'approve')))
  ), m as (
    select sk.*, exists (select 1 from public.stock_ledger s where s.item_id = sk.item_id and s.location_id = sk.location_id and s.reverses_id is null
                 and (s.made_at at time zone 'Asia/Dhaka')::date = sk.entry_date
                 and ((sk.form_code = '04-2' and s.reason = 'issue_out' and s.ref_type = 'issue') or (sk.form_code = '04-3' and s.reason = 'count_adjust' and s.ref_type = 'count')
                   or (sk.form_code = '03-1' and s.reason = 'transfer_out' and s.ref_type = 'transfer') or (sk.form_code = '05-1' and s.reason = 'production_in' and s.ref_type = 'production'))) as matched
      from sk
  )
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', m.entry_id, 'form_code', m.form_code, 'serial', m.serial, 'location_id', m.location_id, 'entry_date', m.entry_date,
           'line_no', m.line_no, 'item_code', m.item_code, 'qty', m.qty_base,
           'link_id', (select l.id from public.shadow_links l where l.primary_type = 'entries' and l.primary_id = m.entry_id::text and l.shadow_type = 'stock_screen' and l.state <> 'void' limit 1)) order by m.entry_date, m.form_code, m.serial, m.line_no)
           filter (where not m.matched), '[]'::jsonb), count(*), count(*) filter (where not m.matched)
    into rows, tot, unm from m;
  return jsonb_build_object('from', f, 'to', t, 'label_bn', 'স্ক্রিন-রেকর্ডহীন ফর্ম', 'label_mix', 'Screen record ছাড়া form', 'label_en', 'Forms with no screen record',
    'lines_checked', tot, 'lines_unmatched', unm, 'rows', rows,
    'note_en', 'A count slip whose counted figure equals the book figure creates no ledger row on the screen either, so it can show here without being wrong.');
end $$;

-- owner: confirm the pending links whose slip now has a screen record for every skipped line (the last 366 days)
create or replace function public.unmatched_forms_sync() returns jsonb
language plpgsql security definer set search_path = public as $$
declare l record; n int := 0; u jsonb; lid bigint; d date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  u := public.unmatched_forms(d - 366, d, null);
  for l in select s.id, s.primary_id from public.shadow_links s where s.primary_type = 'entries' and s.shadow_type = 'stock_screen' and s.state = 'pending' order by s.id limit 500 loop
    if not exists (select 1 from jsonb_array_elements(coalesce(u -> 'rows', '[]'::jsonb)) r where r ->> 'entry_id' = l.primary_id) then
      select min(x.id) into lid from public.entry_ledger_posts p join public.entries e on e.id = p.entry_id
        join public.stock_ledger x on x.item_id = p.item_id and x.location_id = p.location_id and x.reverses_id is null and x.ref_type in ('issue', 'count', 'transfer', 'production')
         and (x.made_at at time zone 'Asia/Dhaka')::date = e.entry_date
       where p.entry_id = l.primary_id::uuid and p.status = 'skipped' and p.reason = 'covered_by_screen';
      if lid is not null then
        update public.shadow_links set state = 'confirmed', shadow_id = lid::text, confirmed_by = auth.uid(), confirmed_at = now() where id = l.id and state = 'pending';
        n := n + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('confirmed', n);
end $$;

-- RECOMMENDATIONS (never forced): key, current, recommended, reason in 3 languages
create or replace function public.form_guard_recommendations() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prim text; fm text := coalesce(public.rule_txt('form_051_mode'), 'reference'); rec jsonb := '[]'::jsonb; rfm text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  prim := public.path_primary('production', 0);
  rfm := case when public.rule_on('forms_post_to_ledger') and prim = 'b' then 'post' else 'reference' end;
  rec := rec || jsonb_build_object('key', 'form_051_mode', 'current', fm, 'recommended', rfm,
    'reason_bn', case rfm when 'post' then 'এখন 05-1 শিটই production-এর record; তাই শিট stock-এ গেলে ingredient-ও বের হওয়া দরকার, নইলে তৈরি মাল বিনা cost-এ stock-এ ঢোকে।'
                                  else 'এখন recipe production screen-ই record; 05-1 শুধু রেফারেন্স। বদলানোর দরকার নেই।' end,
    'reason_mix', case rfm when 'post' then 'এখন 05-1 sheet-ই production-এর record; তাই sheet stock-এ গেলে ingredient-ও বের হওয়া দরকার, নইলে finished goods বিনা cost-এ stock-এ ঢোকে।'
                                  else 'এখন recipe production screen-ই record; 05-1 শুধু reference। বদলানোর দরকার নেই।' end,
    'reason_en', case rfm when 'post' then 'The 05-1 sheet is the production record here, so when it posts to stock the ingredients must go out too; otherwise finished goods enter stock with no cost.'
                                  else 'The recipe production screen is the record here and 05-1 is only a reference. No change is needed.' end);
  rec := rec || jsonb_build_object('key', 'transit_short_mode', 'current', coalesce(public.rule_txt('transit_short_mode'), 'keep_in_transit'), 'recommended', 'loss',
    'reason_bn', 'কম পৌঁছানো মাল এখন কোনো খাতায় নেই। loss ধরলে ঘাটতি ledger-এ cost সহ থাকে, পরে accounts-এ নেওয়া যায়।',
    'reason_mix', 'কম পৌঁছানো মাল এখন কোনো খাতায় নেই। loss ধরলে ঘাটতি ledger-এ cost সহ থাকে, পরে accounts-এ নেওয়া যায়।',
    'reason_en', 'Goods that arrive short are in no book today. With loss, the shortfall stays in the ledger with its cost and can be taken into accounts later.');
  rec := rec || jsonb_build_object('key', 'transit_open_hours', 'current', public.rule_num('transit_open_hours'), 'recommended', null,
    'reason_bn', 'কোনো সংখ্যা কোডে দেওয়া নেই। আপনার ডেলিভারি সাধারণত কত ঘণ্টায় পৌঁছায় তার চেয়ে একটু বেশি লিখুন।',
    'reason_mix', 'কোনো সংখ্যা code-এ দেওয়া নেই। আপনার delivery সাধারণত কত ঘণ্টায় পৌঁছায় তার চেয়ে একটু বেশি লিখুন।',
    'reason_en', 'No number is built in. Enter a little more than the hours a delivery normally takes to arrive.');
  rec := rec || jsonb_build_object('key', 'offline_soft_stock', 'current', public.rule_on('offline_soft_stock'), 'recommended', true,
    'reason_bn', 'offline-এ sale করার সময় মাল ক্রেতাকে আগেই দেওয়া হয়ে গেছে; stock কম বলে আটকালে sale হারিয়ে যায়। চালু থাকলে sale রেকর্ড হয় ও yellow flag থাকে।',
    'reason_mix', 'Offline-এ sale করার সময় goods ক্রেতাকে আগেই দেওয়া হয়ে গেছে; stock কম বলে আটকালে sale হারিয়ে যায়। On থাকলে sale record হয় ও yellow flag থাকে।',
    'reason_en', 'An offline sale has already handed the goods over; if stock being short refuses it, the sale is lost. When on, the sale is recorded and flagged yellow.');
  return rec;
end $$;

-- ============================================================
-- E6 : expense double count
-- ============================================================
-- which pending quick entries cover which lines of a 10-2 voucher (same place, day, head, amount; each quick entry used once)
create or replace function public._expense_cover83(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; ln record; q uuid; used uuid[] := '{}'; out jsonb := '[]'::jsonb;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '10-2' or jsonb_typeof(e.data -> 'lines') <> 'array' then return '[]'::jsonb; end if;
  for ln in select x.o as n, lower(btrim(x.v ->> 'head')) as head, public._db_num(x.v -> 'amount') as amt from jsonb_array_elements(e.data -> 'lines') with ordinality x(v, o) loop
    continue when ln.amt is null or ln.amt <= 0;
    select qe.id into q from public.quick_expenses qe
      join public.shadow_links l on l.primary_type = 'quick_expenses' and l.primary_id = qe.id::text and l.shadow_type = 'entries' and l.state = 'pending'
     where qe.status = 'done' and qe.location_id = e.location_id and qe.exp_date = e.entry_date and qe.head = ln.head and qe.amount = ln.amt and not (qe.id = any (used)) order by qe.created_at, qe.id limit 1;
    if q is not null then used := used || q; end if;
    out := out || jsonb_build_object('n', ln.n, 'head', ln.head, 'amount', ln.amt, 'quick_id', q);
    q := null;
  end loop;
  return out;
end $$;

-- offered on the approval screen of a 10-2 voucher: does a same-day quick entry already count this money?
create or replace function public.suggest_expense_link(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; c jsonb;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '10-2' then raise exception 'not_a_voucher'; end if;
  if not (public.is_owner() or (public.can_do('10-2', 'approve') and public.can_loc(e.location_id))) then raise exception 'not allowed'; end if;
  c := public._expense_cover83(p_entry);
  return jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'is_shadow', public.is_shadow('entries', e.id::text), 'lines', c,
    'matched', (select count(*) from jsonb_array_elements(c) x where x ->> 'quick_id' is not null),
    'fully_covered', jsonb_array_length(c) > 0 and not exists (select 1 from jsonb_array_elements(c) x where x ->> 'quick_id' is null));
end $$;

-- the owner / approver accepts the offer: the voucher becomes the locked copy of those quick entries (counted once). Only when EVERY line is covered.
create or replace function public.expense_link_apply(p_entry uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; c jsonb; x jsonb; n int := 0;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or e.form_code <> '10-2' then raise exception 'not_a_voucher'; end if;
  if not (public.is_owner() or (public.can_do('10-2', 'approve') and public.can_loc(e.location_id))) then raise exception 'not allowed'; end if;
  if e.status not in ('submitted', 'approved') then raise exception 'bad_status'; end if;
  if public.is_shadow('entries', e.id::text) then return jsonb_build_object('entry_id', e.id, 'noop', true); end if;
  if exists (select 1 from public.shadow_links s where s.primary_type = 'entries' and s.primary_id = e.id::text and s.state <> 'void') then raise exception 'entry_is_a_primary'; end if;
  c := public._expense_cover83(p_entry);
  if jsonb_array_length(c) = 0 or exists (select 1 from jsonb_array_elements(c) y where y ->> 'quick_id' is null) then raise exception 'not_fully_covered: some voucher lines have no matching quick entry'; end if;
  for x in select * from jsonb_array_elements(c) loop
    update public.shadow_links set state = 'confirmed', shadow_id = e.id::text, confirmed_by = auth.uid(), confirmed_at = now(), note = left(coalesce(note || ' | ', '') || 'linked at approval ' || coalesce(btrim(p_note), ''), 300)
     where primary_type = 'quick_expenses' and primary_id = x ->> 'quick_id' and shadow_type = 'entries' and state = 'pending';
    n := n + 1;
  end loop;
  return jsonb_build_object('entry_id', e.id, 'linked', n);
end $$;

-- ============================================================
-- E7 : transit shortage
-- ============================================================
create or replace function public.transit_short_open(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare own boolean := public.is_owner();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('transfer_id', t.id, 'item_id', t.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'from_location_id', t.from_location_id,
        'to_location_id', t.to_location_id, 'sent', t.qty, 'received', t.received_qty, 'short', t.qty - t.received_qty, 'received_at', t.received_at,
        'value', case when public._cost_ok(t.to_location_id) then (select round(sum(-l.qty_delta * l.unit_cost), 2) from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transfer_out' and l.unit_cost is not null) / nullif(t.qty, 0) * (t.qty - t.received_qty) end)
        order by t.received_at)
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status = 'received' and t.received_qty < t.qty and (p_loc is null or t.to_location_id = p_loc or t.from_location_id = p_loc)
       and (own or public.can_loc(t.to_location_id) or public.can_loc(t.from_location_id))
       and not exists (select 1 from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = t.id::text and l.reason = 'transit_loss')), '[]'::jsonb);
end $$;

-- book an older short receipt as a loss now (a reason is required)
create or replace function public.transit_short_resolve(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; lid bigint;
begin
  select * into t from public.stock_transfers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(t.to_location_id) then raise exception 'not allowed'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_needed'; end if;
  if t.status <> 'received' or t.received_qty is null or t.received_qty >= t.qty then raise exception 'not_short'; end if;
  if not public._may('stock_transfer', t.to_location_id, 'transit_loss:' || t.id::text, t.qty - t.received_qty) then raise exception 'not allowed'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  lid := public._transit_loss83(t.id, t.qty - t.received_qty, p_note);
  if lid is null then return jsonb_build_object('id', t.id, 'dup', true); end if;
  return jsonb_build_object('id', t.id, 'ledger_id', lid, 'short', t.qty - t.received_qty);
end $$;

create or replace function public.transit_open_list(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare h numeric := public.rule_num('transit_open_hours');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object('limit_hours', h, 'rows', coalesce((select jsonb_agg(jsonb_build_object('transfer_id', t.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'qty', t.qty,
        'from_location_id', t.from_location_id, 'to_location_id', t.to_location_id, 'sent_at', t.sent_at, 'hours', round((extract(epoch from now() - t.sent_at) / 3600)::numeric, 1),
        'over_limit', h is not null and t.sent_at < now() - make_interval(secs => (h * 3600)::double precision)) order by t.sent_at)
      from public.stock_transfers t join public.items i on i.id = t.item_id
     where t.status = 'sent' and (p_loc is null or t.to_location_id = p_loc or t.from_location_id = p_loc)
       and (public.is_owner() or public.can_loc(t.to_location_id) or public.can_loc(t.from_location_id))), '[]'::jsonb));
end $$;

-- ============================================================
-- E8 : offline POS failed sales
-- ============================================================
-- (a) same arguments as record_sale2; the queue replay calls this one. With offline_soft_stock off it is exactly record_sale2.
create or replace function public.record_sale_offline(p_client uuid, p_loc integer, p_lines jsonb, p_discount numeric, p_payments jsonb, p_customer_mobile text, p_customer_name text,
    p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamptz default null, p_discount_kind text default null, p_discount_input numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  perform set_config('bos.offline_replay', '1', true);
  r := public.record_sale2(p_client, p_loc, p_lines, p_discount, p_payments, p_customer_mobile, p_customer_name, p_sale_type, p_note, p_quick, p_sold_at, p_discount_kind, p_discount_input);
  perform set_config('bos.offline_replay', '', true);
  return r;
end $$;

-- (b) device-reported failed cards (summary only; the full sale stays on the device and in its JSON export) so the owner board can count them
create table if not exists public.pos_failed_cards (
  client_id uuid primary key,
  location_id int not null references public.locations(id),
  total numeric, err text check (err is null or length(err) <= 300), sold_at timestamptz, lines_n int,
  status text not null default 'open' check (status in ('open', 'resent', 'discarded')),
  reported_by uuid, reported_staff text, reported_at timestamptz not null default now(),
  closed_by uuid, closed_at timestamptz, close_note text check (close_note is null or length(close_note) <= 300)
);
create index if not exists pos_failed_open on public.pos_failed_cards (location_id) where status = 'open';
drop trigger if exists audit_pos_failed_cards on public.pos_failed_cards;
create trigger audit_pos_failed_cards after insert or update on public.pos_failed_cards for each row execute function public.log_change('client_id');
create or replace function public._pf83_nodel() returns trigger language plpgsql as $$ begin raise exception 'append_only: this trail cannot be deleted'; end $$;
drop trigger if exists pos_failed_nodel on public.pos_failed_cards;
create trigger pos_failed_nodel before delete on public.pos_failed_cards for each row execute function public._pf83_nodel();

create table if not exists public.pos_replay_log (
  id bigint generated always as identity primary key,
  client_id uuid not null, location_id int not null, reason text not null check (length(reason) between 3 and 300), refused_with text,
  sale_id uuid, result text not null check (result in ('sold', 'dup')),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create or replace function public._pf83_ro() returns trigger language plpgsql as $$ begin raise exception 'append_only: the override trail cannot be changed or deleted'; end $$;
drop trigger if exists pos_replay_log_ro on public.pos_replay_log;
create trigger pos_replay_log_ro before update or delete on public.pos_replay_log for each row execute function public._pf83_ro();

do $$ declare t text; begin
  foreach t in array array['pos_failed_cards', 'pos_replay_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
create policy pos_failed_cards_sel on public.pos_failed_cards for select to authenticated
  using (public.is_owner() or reported_by = auth.uid() or (public.can_loc(location_id) and public.has_grant('pos_replay_override', location_id)));
create policy pos_replay_log_sel on public.pos_replay_log for select to authenticated
  using (public.is_owner() or (public.can_loc(location_id) and public.has_grant('pos_replay_override', location_id)));

-- p_items: [{client_id, loc, total, err, sold_at, lines_n}] ; idempotent per client_id
create or replace function public.pos_failed_note(p_items jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare x jsonb; n int := 0; sid text; cid uuid; loc int;
begin
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'bad_items'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  for x in select * from jsonb_array_elements(p_items) loop
    begin cid := (x ->> 'client_id')::uuid; loc := (x ->> 'loc')::int; exception when others then continue; end;
    continue when cid is null or loc is null or not public.can_loc(loc);
    insert into public.pos_failed_cards (client_id, location_id, total, err, sold_at, lines_n, status, reported_by, reported_staff)
      values (cid, loc, nullif(x ->> 'total', '')::numeric, left(x ->> 'err', 300), nullif(x ->> 'sold_at', '')::timestamptz, nullif(x ->> 'lines_n', '')::int,
              case when exists (select 1 from public.sales s where s.client_id = cid) then 'resent' else 'open' end, auth.uid(), sid)
      on conflict (client_id) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;

create or replace function public.pos_failed_close(p_client uuid, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.pos_failed_cards;
begin
  select * into c from public.pos_failed_cards where client_id = p_client for update;
  if not found then return jsonb_build_object('client_id', p_client, 'noop', true); end if;
  if p_status not in ('resent', 'discarded') then raise exception 'bad_status'; end if;
  if not (public.is_owner() or c.reported_by = auth.uid() or (public.can_loc(c.location_id) and public.has_grant('pos_replay_override', c.location_id))) then raise exception 'not allowed'; end if;
  if c.status <> 'open' then return jsonb_build_object('client_id', p_client, 'status', c.status, 'noop', true); end if;
  update public.pos_failed_cards set status = p_status, closed_by = auth.uid(), closed_at = now(), close_note = left(btrim(p_note), 300) where client_id = p_client;
  return jsonb_build_object('client_id', p_client, 'status', p_status);
end $$;

-- the owner-board count: open failed cards per place (a card whose sale now exists is closed first)
create or replace function public.pos_failed_board() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  update public.pos_failed_cards c set status = 'resent', closed_at = now(), close_note = 'sale found'
   where c.status = 'open' and exists (select 1 from public.sales s where s.client_id = c.client_id);
  return jsonb_build_object('open', (select count(*) from public.pos_failed_cards c where c.status = 'open' and (public.is_owner() or public.can_loc(c.location_id))),
    'by_location', coalesce((select jsonb_agg(jsonb_build_object('location_id', z.location_id, 'n', z.n, 'total', z.t) order by z.location_id)
        from (select c.location_id, count(*) n, coalesce(sum(c.total), 0) t from public.pos_failed_cards c where c.status = 'open' and (public.is_owner() or public.can_loc(c.location_id)) group by 1) z), '[]'::jsonb));
end $$;

-- (c) manager override: send the refused sale again with its ORIGINAL client_id (so it can never become a second sale). Reason required.
-- Stock being short is the thing it overrides (the goods are already with the customer); every other rule (closed period, credit limit, customer rules) still applies and its error is returned.
create or replace function public.pos_replay_override(p_payload jsonb, p_reason text, p_err text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cid uuid; loc int; r jsonb; sid text; s public.sales; res text := 'sold';
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception 'bad_payload'; end if;
  begin cid := (p_payload ->> 'p_client')::uuid; loc := (p_payload ->> 'p_loc')::int; exception when others then raise exception 'bad_payload'; end;
  if cid is null or loc is null then raise exception 'bad_payload'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'note_needed'; end if;
  if not public.can_loc(loc) then raise exception 'not allowed'; end if;
  if not public.has_grant('pos_replay_override', loc) then raise exception 'replay_override_needs_approval'; end if;
  select * into s from public.sales where client_id = cid;
  if found then
    update public.pos_failed_cards set status = 'resent', closed_by = auth.uid(), closed_at = now(), close_note = 'already recorded' where client_id = cid and status = 'open';
    return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'dup', true);
  end if;
  perform set_config('bos.offline_replay', '1', true);
  perform set_config('bos.replay_override', '1', true);
  r := public.record_sale2(cid, loc, p_payload -> 'p_lines', coalesce(nullif(p_payload ->> 'p_discount', '')::numeric, 0), p_payload -> 'p_payments',
         nullif(p_payload ->> 'p_customer_mobile', ''), nullif(p_payload ->> 'p_customer_name', ''), coalesce(nullif(p_payload ->> 'p_sale_type', ''), 'retail'),
         left('manager override: ' || btrim(p_reason) || coalesce(' | ' || nullif(p_payload ->> 'p_note', ''), ''), 200), coalesce((p_payload ->> 'p_quick')::boolean, false),
         nullif(p_payload ->> 'p_sold_at', '')::timestamptz, nullif(p_payload ->> 'p_discount_kind', ''), nullif(p_payload ->> 'p_discount_input', '')::numeric);
  perform set_config('bos.offline_replay', '', true);
  perform set_config('bos.replay_override', '', true);
  select staff_id into sid from public.profiles where id = auth.uid();
  if (r ->> 'dup')::boolean is true then res := 'dup'; end if;
  insert into public.pos_replay_log (client_id, location_id, reason, refused_with, sale_id, result, by_user, by_staff)
    values (cid, loc, left(btrim(p_reason), 300), left(p_err, 300), (r ->> 'id')::uuid, res, auth.uid(), sid);
  if res = 'sold' then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, (r ->> 'id')::uuid, 'POS', loc, (now() at time zone 'Asia/Dhaka')::date, 'pos_replay_override', 'yellow', (r ->> 'total')::numeric,
        jsonb_build_object('bn', 'রসিদ ' || (r ->> 'receipt') || ': refused sale manager override-এ আবার পাঠানো হয়েছে — ' || left(btrim(p_reason), 120),
                           'en', 'Receipt ' || (r ->> 'receipt') || ': a refused sale was re-sent on manager override - ' || left(btrim(p_reason), 120)));
  end if;
  update public.pos_failed_cards set status = 'resent', closed_by = auth.uid(), closed_at = now(), close_note = 'manager override' where client_id = cid and status = 'open';
  return r;
end $$;

-- ---------- privileges ----------
revoke all on function public._transit_loss83(uuid, numeric, text), public._transit_open_scan83(), public._expense_cover83(uuid) from public, anon, authenticated;
revoke all on function public.unmatched_forms(date, date, int), public.unmatched_forms_sync(), public.form_guard_recommendations(), public.suggest_expense_link(uuid), public.expense_link_apply(uuid, text),
  public.transit_short_open(int), public.transit_short_resolve(uuid, text), public.transit_open_list(int),
  public.record_sale_offline(uuid, integer, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric),
  public.pos_failed_note(jsonb), public.pos_failed_close(uuid, text, text), public.pos_failed_board(), public.pos_replay_override(jsonb, text, text),
  public._pf83_nodel(), public._pf83_ro() from public, anon;
grant execute on function public.unmatched_forms(date, date, int), public.unmatched_forms_sync(), public.form_guard_recommendations(), public.suggest_expense_link(uuid), public.expense_link_apply(uuid, text),
  public.transit_short_open(int), public.transit_short_resolve(uuid, text), public.transit_open_list(int),
  public.record_sale_offline(uuid, integer, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric),
  public.pos_failed_note(jsonb), public.pos_failed_close(uuid, text, text), public.pos_failed_board(), public.pos_replay_override(jsonb, text, text) to authenticated;
revoke all on function public._pf83_nodel(), public._pf83_ro() from authenticated;
notify pgrst, 'reload schema';
