-- ============================================================
-- Phase 51 - P1 slice 4: stock issue / transfer / count (gaps #25), production (#26), owner top-up / draw (#27).
-- Run AFTER phase50. Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   STOCK + PRODUCTION  path A = the stock screen / recipe run, path B = the paper form (04-2 issue, 03-1 transfer, 04-3 count, 05-1 factory sheet).
--       Rule "never both posting": exactly one of them posts to the stock ledger.
--       primary a (owner default): the screen / recipe run posts; an approved form is a reference - its lines are kept as "skipped: covered_by_screen",
--                                  nothing is posted twice.
--       primary b:                 the form posts (needs forms_post_to_ledger ON as before); the stock screen / recipe run cannot post the same action.
--       A path the owner has locked takes no new record.  Reversals / voids are never blocked.
--   OWNER MONEY  path A = partner capital (contribution / owner_drawing), path B = cash move (owner_topup / owner_draw).
--       Today only the cash move reaches the day book and the journal, partner capital is an equity sub-ledger, so nothing is counted twice now.
--       owner_money_link() joins the two records of one event (primary per the switch); the shadow is excluded from counting once partner capital
--       is auto-posted (P2, gap #6). Guards refuse a new record on a locked path.
--   Re-created from their latest definitions (only lines marked bos51 differ): entry_post_ledger, _elp_post_line.
-- ============================================================

-- ---------- 1. screen / recipe-run side: BEFORE INSERT guard on the stock ledger ----------
create or replace function public._stock_ledger_path_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
declare d text;
begin
  if new.reverses_id is not null or coalesce(current_setting('bos.form_post', true), '') = '1' then return new; end if;
  d := case when new.reason = 'issue_out' and new.ref_type = 'issue' then 'stock_issue'
            when new.reason = 'count_adjust' and new.ref_type = 'count' then 'stock_count'
            when new.reason = 'transfer_out' and new.ref_type = 'transfer' then 'stock_transfer'
            when new.reason = 'production_in' and new.ref_type = 'production' then 'production' end;
  if d is null then return new; end if;
  perform public.path_guard(d, new.location_id, 'a');
  if public.path_primary(d, new.location_id) = 'b' then
    raise exception 'path_locked: % - the paper form is the record here (owner switch), the screen cannot post this action', d;
  end if;
  return new;
end $$;
drop trigger if exists stock_ledger_path_guard51 on public.stock_ledger;
create trigger stock_ledger_path_guard51 before insert on public.stock_ledger for each row execute function public._stock_ledger_path_guard51();

-- ---------- 2. owner money: guards + the link ----------
create or replace function public._partner_capital_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('contribution', 'owner_drawing') then perform public.path_guard('owner_money', 0, 'a'); end if;
  return new;
end $$;
drop trigger if exists partner_capital_path_guard51 on public.partner_capital;
create trigger partner_capital_path_guard51 before insert on public.partner_capital for each row execute function public._partner_capital_guard51();

create or replace function public._cash_moves_guard51() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('owner_topup', 'owner_draw') then perform public.path_guard('owner_money', new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists cash_moves_path_guard51 on public.cash_moves;
create trigger cash_moves_path_guard51 before insert on public.cash_moves for each row execute function public._cash_moves_guard51();

-- owner joins the two records of ONE event: contribution <-> owner_topup, owner_drawing <-> owner_draw (same amount). The primary follows the switch:
-- a = partner capital is the record (cash move = shadow), b = cash move is the record, first = the earlier record.
create or replace function public.owner_money_link(p_capital bigint, p_cash uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.partner_capital; m public.cash_moves; prim text; cash_first boolean; lk bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into c from public.partner_capital where id = p_capital;
  if not found or c.status <> 'posted' then raise exception 'capital_not_found'; end if;
  select * into m from public.cash_moves where id = p_cash;
  if not found or m.status <> 'done' then raise exception 'cash_move_not_found'; end if;
  if not ((c.kind = 'contribution' and m.kind = 'owner_topup') or (c.kind = 'owner_drawing' and m.kind = 'owner_draw')) then raise exception 'kind_mismatch'; end if;
  if c.amount <> m.amount then raise exception 'amount_mismatch'; end if;
  prim := public.path_primary('owner_money', m.location_id);
  if prim = 'first' then cash_first := m.created_at < c.created_at; else cash_first := (prim = 'b'); end if;
  if cash_first then lk := public.shadow_link_add('owner_money', m.location_id, 'cash_moves', m.id::text, 'partner_capital', c.id::text, coalesce(p_note, 'partner capital kept as a copy'));
  else lk := public.shadow_link_add('owner_money', m.location_id, 'partner_capital', c.id::text, 'cash_moves', m.id::text, coalesce(p_note, 'cash move kept as a copy')); end if;
  return jsonb_build_object('link', lk, 'primary', case when cash_first then 'cash_move' else 'partner_capital' end);
end $$;
revoke all on function public.owner_money_link(bigint, uuid, text) from public, anon;
grant execute on function public.owner_money_link(bigint, uuid, text) to authenticated;
revoke all on function public._stock_ledger_path_guard51(), public._partner_capital_guard51(), public._cash_moves_guard51() from public, anon, authenticated;

-- ---------- 3. form side: a form is a reference while the screen is primary ----------
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
    lid := public.stock_post(it.id, e.location_id, bq, 'production_in', 'entry', ref, null, bid, at_, left(note, 200), null, 'none');
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

CREATE OR REPLACE FUNCTION public.entry_post_ledger(p_entry uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.entries; lines jsonb; sg text; g int; cur text; l jsonb; n int; nposted int := 0; nfail int := 0; nskip int := 0; msg text; sid text;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or e.status <> 'approved' then return jsonb_build_object('ok', false, 'why', 'not_approved'); end if;
  if not public._elp_enabled(e.form_code) then return jsonb_build_object('ok', true, 'enabled', false); end if;
  lines := public._elp_lines(e); sg := md5(lines::text);
  select max(gen) into g from public.entry_ledger_posts where entry_id = e.id;
  if g is null then g := 1;
  else
    select sig into cur from public.entry_ledger_posts where entry_id = e.id and gen = g limit 1;
    if cur is distinct from sg then
      begin
        perform public._elp_reverse(e, g);
        g := g + 1;
      exception when others then
        msg := sqlerrm;
        delete from public.exceptions where entry_id = e.id and status = 'open' and flag_code = 'ledger_post_failed';
        insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
          values (e.id, e.form_code, e.location_id, e.entry_date, 'ledger_post_failed', 'yellow', null,
            jsonb_build_object('bn', e.form_code || '-' || e.serial || ': সংশোধিত ফর্মের আগের লেজার পোস্টিং ফেরানো যায়নি — ' || left(msg, 200),
                               'en', e.form_code || '-' || e.serial || ': the earlier ledger posting of the revised form could not be undone — ' || left(msg, 200)));
        return jsonb_build_object('ok', false, 'why', 'reverse_failed', 'error', msg);
      end;
    end if;
  end if;
  perform set_config('bos.form_post', '1', true);  -- bos51: rows posted by a form are not blocked by the screen guard
  for l in select * from jsonb_array_elements(lines) loop
    n := (l->>'n')::int;
    if exists (select 1 from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status in ('posted', 'skipped')) then continue; end if;
    delete from public.entry_ledger_posts where entry_id = e.id and gen = g and line_no = n and status = 'failed';
    begin
      perform public._elp_post_line(e, g, sg, l);
    exception when others then
      insert into public.entry_ledger_posts (entry_id, gen, line_no, form_code, location_id, to_location_id, kind, item_code, qty_base, sig, status, reason, posted_by)
        values (e.id, g, n, e.form_code, e.location_id, nullif(l->>'to', '')::int, coalesce(l->>'kind', 'none'), left(l->>'item', 60), null, sg, 'failed', left(sqlerrm, 200), auth.uid());
    end;
  end loop;
  perform set_config('bos.form_post', '', true);  -- bos51
  select count(*) filter (where status = 'posted'), count(*) filter (where status = 'failed'), count(*) filter (where status = 'skipped') into nposted, nfail, nskip
    from public.entry_ledger_posts where entry_id = e.id and gen = g;
  perform public._elp_exceptions(e, g);
  return jsonb_build_object('ok', true, 'enabled', true, 'gen', g, 'posted', nposted, 'failed', nfail, 'skipped', nskip);
end $function$;

notify pgrst, 'reload schema';
