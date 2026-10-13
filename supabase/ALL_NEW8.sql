-- ============================================================
-- PHASE 23 (group A: wrong-number fixes). Additive and idempotent (paste twice = no error). Needs phase8..phase22.
--   A1  GRN (04-1) vs purchase page: only ONE of them adds bought goods to stock. Rule grn_receipt_source (purchase | grn, default purchase).
--       Cross-check function receipt_duplicates().
--   A2  Sales figures net of sale returns: biz_daily revenue minus returns (rule reports_net_of_returns, ON); sale_returns_summary(from).
--   A4  Day-book gaps: table cash_moves (bank deposit / withdraw, owner top-up / draw, customer advance in / refund / used, hub receipt)
--       with cash_move_add / cash_move_void / customer_advances(); the day book reads them (day_book re-created, one added union).
--   A5  Production void: production_void(run, note) reverses the ingredient-out and finished-good-in ledger rows.
-- Nothing is deleted. No cost price is exposed. Dry-run first: cash_move_add(..., p_dry := true) validates and writes nothing.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('grn_receipt_source', 'stock', 'choice', '"purchase"', null, '["purchase","grn"]'::jsonb, null, null,
  'কেনা মাল স্টকে কোথা থেকে ওঠে: ক্রয় পেজ না GRN', 'কেনা মাল stock-এ কোথা থেকে ওঠে: Purchase page না GRN', 'Bought goods enter stock from: purchase page or GRN',
  'দুটোর একটাই স্টক বাড়ায়, যাতে দুবার না গোনা হয়। ডিফল্ট = ক্রয় পেজ; GRN ফর্মের "ইন" লাইন তখন বাদ পড়ে (কারণ: covered_by_purchase_page)।',
  'Only one of the two adds stock, so nothing is counted twice. Default = purchase page; GRN in-lines are then skipped (reason covered_by_purchase_page). Choose grn if you stop using the purchase page for stock.', 72),
 ('reports_net_of_returns', 'reports', 'switch', 'true', null, null, null, null,
  'বিক্রির হিসাব থেকে বিক্রি-ফেরত বাদ', 'বিক্রির হিসাব থেকে sale return বাদ', 'Sales figures are net of sale returns',
  'চালু = দৈনিক বিক্রি/মুনাফার রিপোর্টে ফেরত দেওয়া পণ্যের দাম ফেরতের দিনে বাদ যায়।',
  'On = daily sales/profit figures subtract the value of goods taken back, on the day of the return.', 73)
 on conflict (key) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('ia_home_v2', 'ui', 'switch', 'true', null, null, null, null, 'নতুন হোম পেজ ও নিচের বার', 'নতুন Home page ও নিচের bar', 'New home page and bottom bar',
  'বন্ধ করলে সবাই আগের হোম পেজ ও মেনু দেখবে। চালু = নতুন বিন্যাস (ডিফল্ট)।', 'Off = everyone sees the old home page and menu. On = the new layout (default). A phone can also turn it off for itself.', 80),
 ('ui_collapsed_controls', 'ui', 'switch', 'true', null, null, null, null, 'ছোট করা অপশন (ড্রপডাউন / ⋮ মেনু)', 'ছোট করা option (dropdown / ⋮ menu)', 'Collapsed options (dropdowns / ⋮ menus)',
  'বন্ধ করলে সব অপশন আগের মতো খোলা বোতাম হয়ে দেখাবে।', 'Off = every option shows as open buttons again, as before.', 81)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'cash_move', 'cash', 62, 'ব্যাংক জমা / মালিকের টাকা / অগ্রিম এন্ট্রি', 'Bank জমা / owner-এর টাকা / advance entry', 'Record bank deposits, owner top-ups and customer advances', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'cash_move');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'production_void', 'stock', 63, 'উৎপাদন বাতিল', 'Production বাতিল', 'Void a production run', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'production_void');

-- ---------- A1 ----------
create or replace function public._elp_post_line(e public.entries, g int, sg text, l jsonb) returns void
language plpgsql security definer set search_path = public as $$
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
end $$;
-- biz_daily (A2)
create or replace function public.biz_daily(p_from date, p_to date, p_loc int default null)
returns table (sale_date date, location_id int, n bigint, revenue numeric, discount numeric,
               void_n bigint, void_amt numeric, costed_rev numeric, cogs numeric)
language plpgsql stable security definer set search_path = public as $$
declare cost_ok boolean := public.biz_cost_ok(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and x.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  ok as (select * from s where s.status = 'done'),
  ln as (
    select o.sale_date, o.location_id, (case when o.subtotal > 0 then o.total / o.subtotal else 1 end) f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end iid
    from ok o, jsonb_array_elements(case when jsonb_typeof(o.lines) = 'array' then o.lines else '[]'::jsonb end) e),
  lc as (select l.*, c.cost_price from ln l left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = l.iid),
  ag as (
    select lc.sale_date, lc.location_id,
           sum(lc.amt * lc.f) filter (where lc.cost_price is not null) cr,
           sum(lc.qty * lc.cost_price) filter (where lc.cost_price is not null) cg
    from lc group by 1, 2),
  tot as (select ok.sale_date, ok.location_id, count(*) n, sum(ok.total) rev, sum(ok.discount) disc from ok group by 1, 2),
  vd as (select s.sale_date, s.location_id, count(*) vn, sum(s.total) va from s where s.status = 'void' group by 1, 2),
  rr as (select r.id, (r.created_at at time zone 'Asia/Dhaka')::date sale_date, r.location_id, r.amount from public.sale_returns r
         where net_on and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
           and (p_loc is null or r.location_id = p_loc) and r.location_id in (select l.id from public.locations l where public.can_loc(l.id))),
  rl as (select rr.id, rr.sale_date, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end amt, case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end qty
         from rr join public.sale_returns r on r.id = rr.id, jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
         left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c
           on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rt as (select rr.sale_date, rr.location_id, sum(rr.amount) ra,
           (select sum(x.amt) filter (where x.cost_price is not null) from rl x where x.sale_date = rr.sale_date and x.location_id = rr.location_id) rcr,
           (select sum(x.qty * x.cost_price) filter (where x.cost_price is not null) from rl x where x.sale_date = rr.sale_date and x.location_id = rr.location_id) rcg
         from rr group by 1, 2),
  k as (select t.sale_date, t.location_id from tot t union select v.sale_date, v.location_id from vd v union select x.sale_date, x.location_id from rt x)
  select k.sale_date, k.location_id,
         coalesce(t.n, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0), coalesce(t.disc, 0), coalesce(v.vn, 0), coalesce(v.va, 0),
         case when cost_ok then round(coalesce(a.cr, 0) - coalesce(x.rcr, 0), 2) end, case when cost_ok then round(coalesce(a.cg, 0) - coalesce(x.rcg, 0), 2) end
  from k
  left join tot t on t.sale_date = k.sale_date and t.location_id = k.location_id
  left join vd v on v.sale_date = k.sale_date and v.location_id = k.location_id
  left join rt x on x.sale_date = k.sale_date and x.location_id = k.location_id
  left join ag a on a.sale_date = k.sale_date and a.location_id = k.location_id
  order by 1, 2;
end $$;
create or replace function public.receipt_duplicates(p_days int default 3) returns table (item_id uuid, location_id int, purchase_ledger bigint, entry_ledger bigint, qty numeric, purchase_at timestamptz, entry_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  p_days := least(greatest(coalesce(p_days, 3), 0), 30);
  return query
    select a.item_id, a.location_id, a.id, b.id, a.qty_delta, a.created_at, b.created_at
      from public.stock_ledger a join public.stock_ledger b on b.item_id = a.item_id and b.location_id = a.location_id
       and b.reason = 'purchase_in' and b.ref_type = 'entry' and abs(b.qty_delta - a.qty_delta) <= a.qty_delta * 0.01
       and abs(extract(epoch from (b.created_at - a.created_at))) <= p_days * 86400
     where a.reason = 'purchase_in' and a.ref_type = 'purchase' and a.qty_delta > 0
       and not exists (select 1 from public.stock_ledger v where v.reverses_id = a.id) and not exists (select 1 from public.stock_ledger v where v.reverses_id = b.id)
     order by a.created_at desc limit 500;
end $$;
revoke all on function public.receipt_duplicates(int) from public, anon;
grant execute on function public.receipt_duplicates(int) to authenticated;

-- ---------- A2 ----------
create or replace function public.sale_returns_summary(p_from date) returns table (return_date date, location_id int, n bigint, amount numeric, refund numeric, credit numeric)
language sql stable security definer set search_path = public as $$
  select (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, count(*), sum(r.amount), sum(r.refund_amount), sum(r.credit_amount)
    from public.sale_returns r
   where r.status = 'done' and public.is_active() and public.can_loc(r.location_id) and (r.created_at at time zone 'Asia/Dhaka')::date >= p_from
     and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', r.location_id) or public.is_owner())
   group by 1, 2;
$$;
revoke all on function public.sale_returns_summary(date) from public, anon;
grant execute on function public.sale_returns_summary(date) to authenticated;


-- sales_summary: same columns; when reports_net_of_returns is ON, each day's sale returns come as an extra 'done' row (pay_mode 'return', n 0, negative total)
-- so every screen that adds the totals is automatically net.
create or replace function public.sales_summary(p_from date) returns table (sale_date date, location_id int, pay_mode text, status text, n bigint, total numeric, discount numeric, due numeric)
language sql stable set search_path = public as $$
  select s.sale_date, s.location_id, s.pay_mode, s.status, count(*), sum(s.total), sum(s.discount), sum(s.due_amount)
    from public.sales s where s.sale_date >= p_from group by 1, 2, 3, 4
  union all
  select (r.created_at at time zone 'Asia/Dhaka')::date, r.location_id, 'return'::text, 'done'::text, 0::bigint, -sum(r.amount), 0::numeric, 0::numeric
    from public.sale_returns r
   where public.rule_on('reports_net_of_returns') and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date >= p_from
   group by 1, 2;
$$;
grant execute on function public.sales_summary(date) to authenticated;

-- ---------- A4 ----------
create table if not exists public.cash_moves (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  location_id int not null references public.locations(id),
  kind text not null check (kind in ('bank_deposit', 'bank_withdraw', 'owner_topup', 'owner_draw', 'cust_advance', 'cust_advance_refund', 'cust_advance_used', 'hub_receipt')),
  mode text check (mode is null or mode in ('cash', 'bank', 'mobile')),
  amount numeric not null check (amount >= 0.01 and amount <= 1000000000000),
  move_date date not null,
  customer_id uuid references public.customers(id),
  ref text, note text,
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check ((kind in ('bank_deposit', 'bank_withdraw', 'cust_advance_used') and mode is null) or (kind not in ('bank_deposit', 'bank_withdraw', 'cust_advance_used') and mode is not null)),
  check (kind not like 'cust_advance%' or customer_id is not null)
);
create index if not exists cash_moves_loc_date on public.cash_moves (location_id, move_date);
create index if not exists cash_moves_cust on public.cash_moves (customer_id) where status = 'done' and customer_id is not null;
drop trigger if exists audit_cash_moves on public.cash_moves;
create trigger audit_cash_moves after insert or update on public.cash_moves for each row execute function public.log_change('id');
alter table public.cash_moves enable row level security;
drop policy if exists cash_moves_read on public.cash_moves;
create policy cash_moves_read on public.cash_moves for select to authenticated
  using (public.can_loc(location_id) and (public.is_owner() or public.has_grant('cash_move', location_id) or public.has_grant('view_daybook', location_id)));
revoke all on public.cash_moves from public, anon, authenticated;
grant select on public.cash_moves to authenticated;

create or replace function public.cash_move_add(p_loc int, p_kind text, p_amount numeric, p_date date default null, p_mode text default null, p_customer uuid default null,
  p_ref text default null, p_note text default null, p_client uuid default null, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); sid text; r public.cash_moves; id_ uuid := gen_random_uuid(); bal numeric;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('cash_move', p_loc)) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_kind is null or p_kind not in ('bank_deposit', 'bank_withdraw', 'owner_topup', 'owner_draw', 'cust_advance', 'cust_advance_refund', 'cust_advance_used', 'hub_receipt') then raise exception 'bad_kind'; end if;
  if p_amount is null or not (p_amount between 0.01 and 1000000000000) or round(p_amount, 2) <= 0 then raise exception 'bad_amount'; end if;
  if d < date '2000-01-01' or d > today + 1 then raise exception 'bad_date'; end if;
  if p_kind = 'hub_receipt' then p_mode := 'cash'; end if;
  if p_kind in ('bank_deposit', 'bank_withdraw', 'cust_advance_used') then p_mode := null;
  elsif p_mode is null or p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode';
  end if;
  if p_kind = 'hub_receipt' then p_mode := 'cash'; end if;
  if p_kind like 'cust_advance%' and p_customer is not null then perform pg_advisory_xact_lock(hashtext('adv:' || p_customer::text)); end if;
  if p_kind like 'cust_advance%' then
    if p_customer is null or not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_required'; end if;
    if p_kind in ('cust_advance_refund', 'cust_advance_used') then
      select coalesce(sum(case when kind = 'cust_advance' then amount else -amount end), 0) into bal from public.cash_moves where customer_id = p_customer and status = 'done' and kind like 'cust_advance%';
      if round(p_amount, 2) > bal then raise exception 'exceeds_advance' using detail = bal::text; end if;
    end if;
  else p_customer := null;
  end if;
  perform public.lock_check(d);
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.cash_moves where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id);
    end if;
  end if;
  if p_dry then
    return jsonb_build_object('dry', true, 'kind', p_kind, 'mode', p_mode, 'amount', round(p_amount, 2), 'date', d, 'location_id', p_loc, 'customer_id', p_customer,
      'daybook', case p_kind when 'bank_deposit' then 'cash out, bank in' when 'bank_withdraw' then 'bank out, cash in' when 'owner_topup' then p_mode || ' in' when 'owner_draw' then p_mode || ' out'
                             when 'cust_advance' then p_mode || ' in' when 'cust_advance_refund' then p_mode || ' out' when 'hub_receipt' then 'cash in (internal)' else 'no money moves (advance used)' end);
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.cash_moves (id, client_id, location_id, kind, mode, amount, move_date, customer_id, ref, note, created_by, created_staff)
    values (id_, p_client, p_loc, p_kind, p_mode, round(p_amount, 2), d, p_customer, left(btrim(p_ref), 80), left(btrim(p_note), 300), auth.uid(), sid);
  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2));
end $$;

create or replace function public.cash_move_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.cash_moves; bal numeric;
begin
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into r from public.cash_moves where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(r.location_id) or not (public.is_owner() or public.has_grant('cash_move', r.location_id)) then raise exception 'not allowed'; end if;
  if r.status = 'void' then return jsonb_build_object('id', r.id, 'status', 'void', 'dup', true); end if;
  perform public.lock_check(r.move_date);
  if r.customer_id is not null then perform pg_advisory_xact_lock(hashtext('adv:' || r.customer_id::text)); end if;
  if r.kind = 'cust_advance' then   -- cannot void an advance that was already refunded or used
    select coalesce(sum(case when kind = 'cust_advance' then amount else -amount end), 0) - r.amount into bal from public.cash_moves where customer_id = r.customer_id and status = 'done' and kind like 'cust_advance%';
    if bal < 0 then raise exception 'advance_already_used'; end if;
  end if;
  update public.cash_moves set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'void');
end $$;

create or replace function public.customer_advances() returns table (customer_id uuid, name text, mobile text, balance numeric, last_at date)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.mobile, sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end), max(m.move_date)
    from public.cash_moves m join public.customers c on c.id = m.customer_id
   where m.status = 'done' and m.kind like 'cust_advance%' and public.is_active() and public.can_loc(m.location_id) and (public.is_owner() or public.has_grant('cash_move', m.location_id) or public.has_grant('view_daybook', m.location_id))
   group by c.id, c.name, c.mobile having sum(case when m.kind = 'cust_advance' then m.amount else -m.amount end) <> 0;
$$;

create or replace function public._daybook_lines23(p_locs int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language sql stable as $$
  select m.location_id, m.move_date, x.dir, x.mode, m.kind, m.amount, m.ref, nullif(btrim(concat_ws(' · ', c.name, m.note)), ''), m.created_staff, m.created_at,
         case when m.customer_id is not null then 'customer' else 'cash_move' end, coalesce(m.customer_id::text, m.id::text), (m.kind = 'hub_receipt'), false
    from public.cash_moves m
    left join public.customers c on c.id = m.customer_id
    cross join lateral (values (1)) one
    cross join lateral (
      select * from (values
        ('bank_deposit', 'out', 'cash'), ('bank_deposit', 'in', 'bank'), ('bank_withdraw', 'out', 'bank'), ('bank_withdraw', 'in', 'cash'),
        ('owner_topup', 'in', m.mode), ('owner_draw', 'out', m.mode), ('cust_advance', 'in', m.mode), ('cust_advance_refund', 'out', m.mode), ('hub_receipt', 'in', 'cash')
      ) v(k, dir, mode) where v.k = m.kind) x
   where m.status = 'done' and m.location_id = any (p_locs) and m.move_date between p_from and p_to;
$$;

-- ---------- A5 ----------
alter table public.production_runs add column if not exists status text not null default 'done';
alter table public.production_runs add column if not exists void_by uuid;
alter table public.production_runs add column if not exists void_at timestamptz;
alter table public.production_runs add column if not exists void_note text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'production_runs_status_chk') then
    alter table public.production_runs add constraint production_runs_status_chk check (status in ('done', 'void'));
  end if;
end $$;

create or replace function public.production_void(p_run uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare run public.production_runs; r record; b public.stock_batches; n int := 0;
begin
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into run from public.production_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not public.can_loc(run.location_id) or not (public.is_owner() or public.has_grant('production_void', run.location_id)) then raise exception 'not allowed'; end if;
  if run.status = 'void' then return jsonb_build_object('id', run.id, 'status', 'void', 'dup', true); end if;
  perform public.lock_check((run.made_at at time zone 'Asia/Dhaka')::date);
  -- the finished goods must still be unsold: a partly sold batch cannot be undone (use wastage / count instead)
  if run.batch_id is not null then
    select * into b from public.stock_batches where id = run.batch_id for update;
    if found and b.qty_remaining < b.qty_made - 0.0001 then raise exception 'batch_partly_used'; end if;
  end if;
  for r in select o.* from public.stock_ledger o where o.ref_type = 'production' and o.ref_id = run.id::text and o.reason in ('issue_out', 'production_in')
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = o.id) order by o.item_id, o.id loop
    perform public.stock_post(r.item_id, r.location_id, -r.qty_delta, 'reversal', 'production', run.id::text, r.unit_cost, r.batch_id, now(), left('void: ' || btrim(p_note), 200), r.id, 'soft');
    n := n + 1;
  end loop;
  update public.production_runs set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = run.id;
  return jsonb_build_object('id', run.id, 'status', 'void', 'reversed_lines', n);
end $$;

revoke all on function public.cash_move_add(int, text, numeric, date, text, uuid, text, text, uuid, boolean), public.cash_move_void(uuid, text), public.customer_advances(),
  public._daybook_lines23(int[], date, date), public.production_void(uuid, text), public._elp_post_line(public.entries, int, text, jsonb) from public, anon;
revoke all on function public._daybook_lines23(int[], date, date), public._elp_post_line(public.entries, int, text, jsonb) from authenticated;
grant execute on function public.cash_move_add(int, text, numeric, date, text, uuid, text, text, uuid, boolean), public.cash_move_void(uuid, text), public.customer_advances(),
  public.production_void(uuid, text) to authenticated;

-- day_book re-created with the new union (A4)
create or replace function public.day_book(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_locs int[]; v_sal int[]; v_start date; v_all boolean := (p_loc is null); v_to date; v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_days jsonb; v_tot jsonb; v_hidden boolean; v_mask boolean; v_known boolean; v_skipped int; v_allseen boolean;
  v_ob numeric[] := array[null, null, null]::numeric[]; v_base numeric[] := array[0, 0, 0]::numeric[]; v_bal boolean;
  v_netopen jsonb; v_netclose jsonb; v_open jsonb; v_close jsonb; v_i1 numeric; v_i2 numeric; v_i3 numeric; v_o1 numeric; v_o2 numeric; v_o3 numeric; v_n1 numeric; v_n2 numeric; v_n3 numeric; v_tr numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_from in (date 'infinity', date '-infinity') or p_to in (date 'infinity', date '-infinity')
     or not (p_from between date '2000-01-01' and date '2100-01-01') or not (p_to between date '2000-01-01' and date '2100-01-01')
     or p_to < p_from or p_to - p_from + 1 > 366 then raise exception 'bad_range'; end if;
  if not public.is_owner() and not public.rule_on('daybook_enabled') then raise exception 'daybook_off'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('view_daybook', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l), '{}') into v_sal from unnest(v_locs) l where public.has_grant('salary_view', l);
  v_hidden := cardinality(v_sal) < cardinality(v_locs);
  v_mask := (not public.is_owner()) and public.rule_on('daybook_mask_names');
  v_start := public._db_start();
  v_to := least(p_to, v_today);
  v_allseen := v_all and (select count(*) from public.locations) = cardinality(v_locs);
  v_ob := array[public.rule_num('daybook_open_cash'), public.rule_num('daybook_open_bank'), public.rule_num('daybook_open_mobile')];
  v_bal := v_allseen and v_ob[1] is not null and v_ob[2] is not null and v_ob[3] is not null;
  v_known := v_start is not null and v_to >= v_start;

  -- opening net: ONE aggregate over [start, p_from - 1] (only rows dated on/after the start date)
  if v_start is not null and v_start < p_from then
    select array[coalesce(sum(s) filter (where mode = 'cash'), 0), coalesce(sum(s) filter (where mode = 'bank'), 0), coalesce(sum(s) filter (where mode = 'mobile'), 0)] into v_base
      from (select u.mode, case when u.dir = 'in' then u.amount else -u.amount end as s
              from (select * from public._daybook_lines(v_locs, v_sal, v_start, p_from - 1) union all select * from public._daybook_lines12(v_locs, v_start, p_from - 1) union all select * from public._daybook_lines23(v_locs, v_start, p_from - 1)) u
             where not (u.internal and v_all)) z;
  end if;

  with rl as (select * from public._daybook_lines(v_locs, v_sal, p_from, v_to) union all select * from public._daybook_lines12(v_locs, p_from, v_to) union all select * from public._daybook_lines23(v_locs, p_from, v_to)),
  c as (select d, mode, case when dir = 'in' then amount else -amount end as s from rl where not (internal and v_all) and v_start is not null and d >= v_start),
  perday as (select d, sum(s) filter (where mode = 'cash') cash, sum(s) filter (where mode = 'bank') bank, sum(s) filter (where mode = 'mobile') mobile from c group by d),
  cum as (select d, coalesce(cash, 0) cash, coalesce(bank, 0) bank, coalesce(mobile, 0) mobile,
                 coalesce(sum(cash) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[1] pc,
                 coalesce(sum(bank) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[2] pb,
                 coalesce(sum(mobile) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[3] pm from perday),
  x as (select t.d,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'cash' and not (t.internal and v_all)), 0) i_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'bank' and not (t.internal and v_all)), 0) i_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'mobile' and not (t.internal and v_all)), 0) i_mobile,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'cash' and not (t.internal and v_all)), 0) o_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'bank' and not (t.internal and v_all)), 0) o_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'mobile' and not (t.internal and v_all)), 0) o_mobile,
          coalesce(sum(t.amount) filter (where t.internal), 0) tr,
          jsonb_agg(jsonb_build_object('loc', t.loc, 'dir', t.dir, 'mode', t.mode, 'type', t.typ, 'amount', t.amount,
                    'ref', case when v_mask then null else t.ref end, 'text', case when v_mask then null else t.txt end, 'who', t.who,
                    'at', t.at, 'src', t.src, 'src_id', t.src_id, 'internal', t.internal, 'sensitive', t.sensitive) order by t.at, t.typ) lines
          from rl t group by t.d)
  select coalesce(jsonb_agg(jsonb_build_object(
      'date', x.d,
      'net_open', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc, 'bank', cm.pb, 'mobile', cm.pm, 'total', cm.pc + cm.pb + cm.pm) end,
      'net_close', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc + cm.cash, 'bank', cm.pb + cm.bank, 'mobile', cm.pm + cm.mobile, 'total', cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'open', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc, 'bank', v_ob[2] + cm.pb, 'mobile', v_ob[3] + cm.pm, 'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm) end,
      'close', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc + cm.cash, 'bank', v_ob[2] + cm.pb + cm.bank, 'mobile', v_ob[3] + cm.pm + cm.mobile,
                    'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'in', jsonb_build_object('cash', x.i_cash, 'bank', x.i_bank, 'mobile', x.i_mobile, 'total', x.i_cash + x.i_bank + x.i_mobile),
      'out', jsonb_build_object('cash', x.o_cash, 'bank', x.o_bank, 'mobile', x.o_mobile, 'total', x.o_cash + x.o_bank + x.o_mobile),
      'transfers', x.tr, 'lines', x.lines) order by x.d), '[]'::jsonb),
    coalesce(sum(x.i_cash), 0), coalesce(sum(x.i_bank), 0), coalesce(sum(x.i_mobile), 0), coalesce(sum(x.o_cash), 0), coalesce(sum(x.o_bank), 0), coalesce(sum(x.o_mobile), 0), coalesce(sum(x.tr), 0),
    coalesce(sum(x.i_cash - x.o_cash) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_bank - x.o_bank) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_mobile - x.o_mobile) filter (where v_start is not null and x.d >= v_start), 0)
    into v_days, v_i1, v_i2, v_i3, v_o1, v_o2, v_o3, v_tr, v_n1, v_n2, v_n3
    from x left join cum cm on cm.d = x.d;

  v_tot := jsonb_build_object(
    'in', jsonb_build_object('cash', v_i1, 'bank', v_i2, 'mobile', v_i3, 'total', v_i1 + v_i2 + v_i3),
    'out', jsonb_build_object('cash', v_o1, 'bank', v_o2, 'mobile', v_o3, 'total', v_o1 + v_o2 + v_o3), 'transfers', v_tr);
  if v_known then
    -- start of the range = running net before p_from (rows on/after the start date only); end = that + what happened in the range on/after the start date
    select jsonb_build_object('cash', v_base[1], 'bank', v_base[2], 'mobile', v_base[3], 'total', v_base[1] + v_base[2] + v_base[3]) into v_netopen;
    v_netclose := jsonb_build_object('cash', v_base[1] + v_n1, 'bank', v_base[2] + v_n2, 'mobile', v_base[3] + v_n3, 'total', v_base[1] + v_base[2] + v_base[3] + v_n1 + v_n2 + v_n3);
    v_tot := v_tot || jsonb_build_object('net_open', v_netopen, 'net_close', v_netclose);
    if v_bal then
      v_tot := v_tot || jsonb_build_object('open', jsonb_build_object('cash', v_ob[1] + v_base[1], 'bank', v_ob[2] + v_base[2], 'mobile', v_ob[3] + v_base[3], 'total', v_ob[1] + v_ob[2] + v_ob[3] + v_base[1] + v_base[2] + v_base[3]),
        'close', jsonb_build_object('cash', v_ob[1] + (v_netclose ->> 'cash')::numeric, 'bank', v_ob[2] + (v_netclose ->> 'bank')::numeric, 'mobile', v_ob[3] + (v_netclose ->> 'mobile')::numeric,
                                    'total', v_ob[1] + v_ob[2] + v_ob[3] + (v_netclose ->> 'total')::numeric));
    end if;
  end if;
  v_skipped := public._daybook_skipped(v_locs, v_sal, p_from, v_to);

  return jsonb_build_object('from', p_from, 'to', v_to, 'capped', p_to > v_today, 'loc', p_loc, 'start', v_start, 'opening_known', v_known, 'balances', v_bal,
    'enabled', public.rule_on('daybook_enabled'), 'salary_hidden', v_hidden, 'names_masked', v_mask, 'skipped_rows', v_skipped, 'days', v_days,
    'totals', v_tot || jsonb_build_object('net_open', coalesce(v_tot -> 'net_open', 'null'::jsonb), 'net_close', coalesce(v_tot -> 'net_close', 'null'::jsonb), 'open', coalesce(v_tot -> 'open', 'null'::jsonb), 'close', coalesce(v_tot -> 'close', 'null'::jsonb)),
    'notes', jsonb_build_array('card_as_bank', 'imprest_in_cash') || (case when exists (select 1 from public.cash_moves cm where cm.status = 'done' and cm.kind = 'hub_receipt' and cm.location_id = any (v_locs) and cm.move_date between p_from and v_to)
      then '[]'::jsonb else jsonb_build_array('hub_receipt_not_recorded') end) || jsonb_build_array('bank_deposit_not_dated') || jsonb_build_array('drafts_excluded', 'refunds_included', 'future_dates_capped'));
end $$;
revoke all on function public.day_book(int, date, date) from public, anon; grant execute on function public.day_book(int, date, date) to authenticated;

grant select (status, void_by, void_at, void_note) on public.production_runs to authenticated;

-- ============================================================
-- B2: blind count for the stock count sheet (04-3) and the goods received note (04-1). Needs phase18 (blind_count_on, blind_count_cfg).
--   04-3: the counter never sees (and the browser never sends) the book balance. count_lines_seal() takes the SERVER's balance of every counted item at that moment
--         and locks the counted figures; the book figure is written into the sheet only when it is submitted. Posting then uses that sealed book figure.
--   04-1: the counted figures are sealed first; only then does the screen show the memo figure. A sealed count cannot be changed through the entry.
--   Off by default (rule blind_count_on, per-form/location switch blind_count_cfg - same switches as phase18). Nothing changes while it is off.
-- ============================================================
create or replace function public.stock_blind_active(p_form text, p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('04-1', '04-3') and public.rule_on('blind_count_on')
     and coalesce((select enabled from public.blind_count_cfg where form_code = p_form and location_id = p_loc), true);
$$;

create table if not exists public.entry_count_seals (
  entry_id uuid not null references public.entries(id),
  line_no int not null check (line_no >= 1),
  form_code text not null,
  item_code text not null,
  counted numeric not null check (counted >= 0),
  book_base numeric,                       -- 04-3 only: the server balance (base unit) at the moment of sealing
  sealed_by uuid, sealed_at timestamptz not null default now(),
  primary key (entry_id, line_no)
);
alter table public.entry_count_seals enable row level security;
drop policy if exists entry_count_seals_read on public.entry_count_seals;
create policy entry_count_seals_read on public.entry_count_seals for select to authenticated
  using (exists (select 1 from public.entries e where e.id = entry_id and public.can_loc(e.location_id)
        and (public.is_owner() or e.status <> 'draft' or e.created_by is distinct from auth.uid() or public.has_grant('see_expected', e.location_id))));
revoke all on public.entry_count_seals from public, anon, authenticated;
grant select on public.entry_count_seals to authenticated;
create or replace function public._append_only23() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists entry_count_seals_ro on public.entry_count_seals;
create trigger entry_count_seals_ro before update or delete on public.entry_count_seals for each row execute function public._append_only23();
drop trigger if exists entry_count_seals_ro_t on public.entry_count_seals;
create trigger entry_count_seals_ro_t before truncate on public.entry_count_seals for each statement execute function public._append_only23();

create or replace function public.blind_cfg_set(p_form text, p_loc int, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1', '04-3', '04-1') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'location_not_found'; end if;
  insert into public.blind_count_cfg (form_code, location_id, enabled, changed_by, changed_at) values (p_form, p_loc, p_enabled, auth.uid(), now())
    on conflict (form_code, location_id) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'enabled', p_enabled);
end $$;

create or replace function public.count_lines_state(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries; k text; n int; s int;
begin
  select * into e from public.entries where id = p_entry;
  if not found or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if not public.stock_blind_active(e.form_code, e.location_id) then return jsonb_build_object('blind', false); end if;
  k := case e.form_code when '04-3' then 'rows' else 'lines' end;
  select count(*) into n from jsonb_array_elements(case when jsonb_typeof(e.data -> k) = 'array' then e.data -> k else '[]'::jsonb end) r where nullif(btrim(r ->> 'item'), '') is not null;
  select count(*) into s from public.entry_count_seals where entry_id = e.id;
  return jsonb_build_object('blind', true, 'rows', n, 'sealed', s, 'all_sealed', n > 0 and s >= n);
end $$;

create or replace function public.count_lines_seal(p_entry uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; k text; cf text; r jsonb; n int; cnt numeric; it public.items; bk numeric; tot int := 0;
begin
  select * into e from public.entries where id = p_entry for update;
  if not found or not public.can_loc(e.location_id) then raise exception 'not allowed'; end if;
  if e.created_by is distinct from auth.uid() and not public.is_owner() then raise exception 'not allowed'; end if;
  if e.status <> 'draft' then raise exception 'count_not_open'; end if;
  if not public.stock_blind_active(e.form_code, e.location_id) then return jsonb_build_object('blind', false, 'sealed', 0); end if;
  k := case e.form_code when '04-3' then 'rows' else 'lines' end; cf := case e.form_code when '04-3' then 'count' else 'counted' end;
  for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(e.data -> k) = 'array' then e.data -> k else '[]'::jsonb end) with ordinality x(v, o) loop
    continue when nullif(btrim(r ->> 'item'), '') is null;
    if nullif(btrim(coalesce(r ->> cf, '')), '') is null then raise exception 'count_missing'; end if;
    cnt := public._n18(r, cf);
    if cnt < 0 then raise exception 'bad_count'; end if;
    if not exists (select 1 from public.entry_count_seals where entry_id = e.id and line_no = n) then
      select * into it from public.items where code = btrim(r ->> 'item');
      if not found then raise exception 'item_not_found'; end if;
      bk := null;
      if e.form_code = '04-3' then
        select coalesce(b.qty, 0) into bk from public.stock_balance b where b.item_id = it.id and b.location_id = e.location_id;
        bk := coalesce(bk, 0);
      end if;
      insert into public.entry_count_seals (entry_id, line_no, form_code, item_code, counted, book_base, sealed_by) values (e.id, n, e.form_code, btrim(r ->> 'item'), cnt, bk, auth.uid());
    end if;
  end loop;
  select count(*) into tot from public.entry_count_seals where entry_id = e.id;
  return jsonb_build_object('blind', true, 'sealed', tot);
end $$;

create or replace function public._entries_countseal_guard23() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; cf text; s record; r jsonb; n int; arr jsonb := '[]'::jsonb; it public.items; iid uuid; f numeric; bk numeric;
begin
  if new.form_code not in ('04-1', '04-3') or not public.stock_blind_active(new.form_code, new.location_id) then return new; end if;
  k := case new.form_code when '04-3' then 'rows' else 'lines' end; cf := case new.form_code when '04-3' then 'count' else 'counted' end;
  if tg_op = 'UPDATE' then
    for s in select * from public.entry_count_seals where entry_id = new.id loop
      r := case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k -> (s.line_no - 1) end;
      if r is null or btrim(coalesce(r ->> 'item', '')) <> s.item_code or public._n18(r, cf) <> s.counted then raise exception 'count_locked'; end if;
    end loop;
    if old.status = 'draft' and new.status <> 'draft' then
      for r, n in select x.v, x.o::int from jsonb_array_elements(case when jsonb_typeof(new.data -> k) = 'array' then new.data -> k else '[]'::jsonb end) with ordinality x(v, o) loop
        if nullif(btrim(r ->> 'item'), '') is not null and not exists (select 1 from public.entry_count_seals where entry_id = new.id and line_no = n) then raise exception 'count_not_sealed'; end if;
      end loop;
    end if;
  end if;
  if new.form_code = '04-3' and jsonb_typeof(new.data -> k) = 'array' then
    for r, n in select x.v, x.o::int from jsonb_array_elements(new.data -> k) with ordinality x(v, o) loop
      r := case when jsonb_typeof(r) = 'object' then r - 'book' else r end;
      if tg_op = 'UPDATE' and new.status <> 'draft' and jsonb_typeof(r) = 'object' then
        select sl.book_base, i.id into bk, iid from public.entry_count_seals sl left join public.items i on i.code = sl.item_code where sl.entry_id = new.id and sl.line_no = n;
        if found and bk is not null then
          select * into it from public.items where id = iid;
          f := public._unit_factor_base(it.id, it.unit);
          if f is not null and f > 0 then r := r || jsonb_build_object('book', round(bk / f, 4)::text); end if;
        end if;
      end if;
      arr := arr || jsonb_build_array(r);
    end loop;
    new.data := jsonb_set(new.data, array[k], arr);
  end if;
  return new;
end $$;
drop trigger if exists entries_countseal_guard23 on public.entries;
drop trigger if exists entries_zcountseal_guard23 on public.entries;   -- named to sort AFTER entries_sig_guard: the PIN hash is taken before the server book figure is added
create trigger entries_zcountseal_guard23 before insert or update on public.entries for each row execute function public._entries_countseal_guard23();

revoke all on function public.stock_blind_active(text, int), public.count_lines_state(uuid), public.count_lines_seal(uuid), public._entries_countseal_guard23(), public._append_only23() from public, anon;
revoke all on function public._entries_countseal_guard23(), public._append_only23() from authenticated;
grant execute on function public.stock_blind_active(text, int), public.count_lines_state(uuid), public.count_lines_seal(uuid) to authenticated;

-- ============================================================
-- B3: PIN signature (witness) also on the stock count sheet 04-3. Same switch (pin_signature_on) and per-form switch (pin_sig_cfg).
-- ============================================================
create or replace function public.pin_sig_active(p_form text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_form in ('14-1', '10-1', '04-3') and public.rule_on('pin_signature_on')
     and coalesce((select enabled from public.pin_sig_cfg where form_code = p_form), true);
$$;
create or replace function public.pin_sig_cfg_set(p_form text, p_enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_form not in ('14-1', '10-1', '04-3') then raise exception 'form_not_supported'; end if;
  if p_enabled is null then raise exception 'bad_value'; end if;
  insert into public.pin_sig_cfg (form_code, enabled, changed_by, changed_at) values (p_form, p_enabled, auth.uid(), now())
    on conflict (form_code) do update set enabled = excluded.enabled, changed_by = excluded.changed_by, changed_at = excluded.changed_at;
  return jsonb_build_object('form', p_form, 'enabled', p_enabled);
end $$;
create or replace function public.sign_entry(p_entry uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; sid text; iat numeric; h text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry for update;
  -- place first, one text for every refusal of access (no hint whether the entry exists)
  if not found or not public.can_loc(e.location_id) or not (public.can_do(e.form_code, 'enter') or public.can_do(e.form_code, 'approve')) then raise exception 'not allowed'; end if;
  if p_role not in ('witness', 'second_sig', 'hub_pair') then raise exception 'bad_role'; end if;
  if (p_role = 'witness' and e.form_code not in ('14-1', '04-3')) or (p_role = 'second_sig' and e.form_code <> '14-1') or (p_role = 'hub_pair' and e.form_code <> '10-1') then raise exception 'bad_role'; end if;   -- phase 23: the stock count sheet (04-3) has a witness too
  if not public.pin_sig_active(e.form_code) then raise exception 'pin_signature_off'; end if;
  if e.status not in ('draft', 'submitted') then raise exception 'entry is locked'; end if;
  if e.created_by = auth.uid() then raise exception 'signer_is_maker'; end if;
  -- a fresh sign-in just now (the browser signs the signer in on a second client): an old token cannot sign
  begin iat := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'iat', nullif(current_setting('request.jwt.claim.iat', true), ''))::numeric; exception when others then iat := null; end;
  if iat is null or iat < extract(epoch from now()) - 120 then raise exception 'login_not_fresh'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if exists (select 1 from public.login_failures f where f.staff_id = sid and f.locked and (f.locked_until is null or f.locked_until > now())) then raise exception 'signer_locked'; end if;
  h := public._sig_hash18(e.data);
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and signer_id = auth.uid() and data_hash = h) then raise exception 'signer_already_signed'; end if;
  if exists (select 1 from public.entry_signatures where entry_id = p_entry and role = p_role and data_hash = h) then raise exception 'role_already_signed'; end if;
  insert into public.entry_signatures (entry_id, role, signer_id, signer_staff, data_hash) values (p_entry, p_role, auth.uid(), sid, h);
  return jsonb_build_object('entry', p_entry, 'role', p_role, 'signer_staff', sid);
end $$;
create or replace function public._entries_sig_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare roles text[]; r text; s text; h text; missing text[] := '{}';
begin
  if not (old.status = 'draft' and new.status = 'submitted') then return new; end if;
  if not public.pin_sig_active(new.form_code) then return new; end if;
  roles := case new.form_code when '14-1' then array['witness', 'second_sig'] when '04-3' then array['witness'] else array['hub_pair'] end;
  h := public._sig_hash18(new.data);
  foreach r in array roles loop
    select signer_staff into s from public.entry_signatures where entry_id = new.id and role = r and data_hash = h order by id desc limit 1;
    if s is null then
      missing := missing || r;
      continue;
    end if;
    if r = 'witness' and coalesce(new.data ->> 'witness', '') <> s then raise exception 'signature_mismatch:witness'; end if;
    if r = 'second_sig' and coalesce(new.data ->> 'second_sig', '') <> s then raise exception 'signature_mismatch:second_sig'; end if;
  end loop;
  if array_length(missing, 1) > 0 then
    if new.entered_later then
      new.flags := public._addflag18(new.flags, 'unsigned_entered_later', 'yellow', 'কাগজ থেকে পরে তোলা — পিন স্বাক্ষর নেই', 'Entered later from paper - no PIN signature');
    elsif public.is_owner() and public.rule_on('pin_signature_owner_override') then
      new.flags := public._addflag18(new.flags, 'unsigned_owner_override', 'yellow', 'মালিকের ছাড়ে পিন স্বাক্ষর ছাড়া জমা', 'Submitted without PIN signatures by the owner override');
    else
      r := missing[1];
      if exists (select 1 from public.entry_signatures where entry_id = new.id and role = r) then raise exception 'pin_signature_stale:%', r; end if;
      raise exception 'pin_signature_required:%', r;
    end if;
  end if;
  return new;
end $$;
