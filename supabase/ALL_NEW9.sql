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
-- ============================================================
-- PHASE 24 (group C): report engine 3 = a registry of reports (table report_defs3) + one function per report
--   _r3q_<key>(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb   (one jsonb object per row, keys = the column keys; private: nobody may call it directly)
--   report_run3(key, filters, group, sort, page) does access, locations, dates, sort, paging, totals - same answer shape as report_run2, so the reports hub shows them with no new screen.
--   report_catalog2 / report_run2 / log_report_export2 are wrapped: a key that is in report_defs3 goes to engine 3, every other key to the old code (renamed *_core).
-- Needs phase21. Run in order after it (do not paste phase21 again afterwards). Additive and idempotent. Costs only for cost-right holders; owner-only reports stay owner-only.
-- ============================================================
create table if not exists public.report_defs3 (
  key text primary key check (key ~ '^[a-z0-9_]{2,40}$'),
  code text,                                   -- number in docs/plan_v2/REPORTS.md (S10, P2 ...)
  grp text not null,                           -- access group: report_<grp> grant (or view_reports)
  name_bn text not null, name_en text not null, name_mix text,
  cols jsonb not null,                         -- [[key, label_bn, label_en, type]]  type: text | id | date | int | num | money | pct
  tot text[] not null default '{}',            -- column keys summed into the totals
  sort_key text, sort_dir text not null default 'desc',
  allow text[] not null default array['locations'],
  nodate boolean not null default false, cost boolean not null default false, owner_only boolean not null default false,
  sort int not null default 0, is_active boolean not null default true
);
alter table public.report_defs3 enable row level security;
drop policy if exists report_defs3_read on public.report_defs3;
create policy report_defs3_read on public.report_defs3 for select to authenticated using (public.is_active());
revoke all on public.report_defs3 from public, anon, authenticated;
grant select on public.report_defs3 to authenticated;

do $$
declare r record;
begin
  for r in select * from (values
    ('report_profit',    69, 'রিপোর্ট: লাভ-ক্ষতি', 'Report: Profit & loss', 'Reports: Profit and loss'),
    ('report_quality',   70, 'রিপোর্ট: মান ও পরিচ্ছন্নতা', 'Report: Quality & hygiene', 'Reports: Quality and hygiene'),
    ('report_marketing', 71, 'রিপোর্ট: মার্কেটিং', 'Report: Marketing', 'Reports: Marketing'),
    ('report_orders',    72, 'রিপোর্ট: অর্ডার ও ডেলিভারি', 'Report: Orders & delivery', 'Reports: Orders and delivery')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
    end if;
  end loop;
end $$;

create or replace function public._r3_ok(d public.report_defs3) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  return d.is_active and public.rpt_access(d.grp) and (not d.cost or public.rpt_cost_ok()) and (not d.owner_only or public.is_owner());
end $$;

create or replace function public.report_catalog3() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d public.report_defs3; out_ jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  for d in select * from public.report_defs3 where is_active order by sort, key loop
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', d.key, 'code', d.code, 'group', d.grp, 'grant', 'report_' || d.grp, 'allowed', public._r3_ok(d), 'kind', 'raw', 'engine', 2,
      'name_bn', d.name_bn, 'name_en', d.name_en, 'name_mix', coalesce(d.name_mix, d.name_bn),
      'filters', to_jsonb(case when d.nodate then '{}'::text[] else array['date'] end || d.allow),
      'dims', '[]'::jsonb, 'default_group', null, 'columns', '[]'::jsonb, 'compare', false, 'needs_date', not d.nodate, 'cost_only', d.cost));
  end loop;
  return out_;
end $$;

create or replace function public.report_run3(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d public.report_defs3; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date; eff int[]; d1 date; d2 date; pr jsonb; preset text;
  pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500; c jsonb; outc jsonb := '[]'::jsonb; keys text[] := '{}'; types jsonb := '{}'::jsonb;
  sk text; sd text; sraw text; sparts text[]; ordr text; rows_ jsonb; totals_ jsonb; ng bigint := 0; hm boolean; dn boolean := false; fn text; k text; targs text := ''; g text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into d from public.report_defs3 where key = p_key and is_active;
  if not found then raise exception 'unknown_report'; end if;
  if not public._r3_ok(d) then raise exception 'not allowed'; end if;
  fn := '_r3q_' || d.key;
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  for c in select jsonb_array_elements(d.cols) loop
    outc := outc || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3,
      'role', case when c ->> 3 in ('money', 'int', 'num', 'pct') then 'measure' else 'dim' end, 'cost', d.cost));
    keys := keys || (c ->> 0); types := types || jsonb_build_object(c ->> 0, c ->> 3);
  end loop;
  if to_regprocedure('public.' || fn || '(date,date,int[],jsonb)') is null then
    return jsonb_build_object('report', p_key, 'columns', outc, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
      'page', jsonb_build_object('n', pg, 'size', 0, 'groups', 0, 'cap', cap), 'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'text_en', 'This report is not installed yet', 'text_bn', 'এই রিপোর্ট এখনও বসানো হয়নি')));
  end if;
  eff := public._r2_locs(flt);
  if cardinality(eff) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you', 'text_bn', 'কোনো লোকেশন আপনার জন্য খোলা নেই')); end if;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);
  for g in select jsonb_object_keys(flt) loop
    if g in ('from', 'to', 'preset', 'compare_mode') or jsonb_typeof(flt -> g) = 'null' then continue; end if;
    if not (g = any (d.allow)) then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', left(g, 40))); end if;
  end loop;
  if not d.nodate then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', outc, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap), 'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset', 'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
      end if;
      d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date;
    else
      d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
      if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'default_period', 'text_en', 'No period given: this month to date', 'text_bn', 'সময় দেওয়া হয়নি: এই মাসের শুরু থেকে আজ পর্যন্ত'));
      elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
    end if;
    if d2 < d1 or d2 - d1 > 365 then raise exception 'bad_range'; end if;
  else d1 := today; d2 := today;
  end if;
  sraw := lower(btrim(coalesce(p_sort, '')));
  if sraw <> '' then
    if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
    sparts := regexp_split_to_array(sraw, '[: ]+');
    if sparts[1] = any (keys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
    else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
  end if;
  if sk is null then
    if d.sort_key is not null and d.sort_key = any (keys) then sk := d.sort_key; sd := d.sort_dir;
    else sk := coalesce((select c2 ->> 0 from jsonb_array_elements(d.cols) c2 where c2 ->> 3 <> 'id' limit 1), keys[1]); sd := 'asc'; end if;
  end if;
  ordr := case when types ->> sk in ('money', 'int', 'num', 'pct') then format('(r ->> %L)::numeric', sk) else format('r ->> %L', sk) end || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last';
  execute format('select coalesce(jsonb_agg(x.r order by x.rn), ''[]''::jsonb), coalesce(max(x.n), 0) from (select r, count(*) over () as n, row_number() over (order by %s) as rn from public.%I($1, $2, $3, $4) r order by %s limit %s offset %s) x',
    ordr, fn, ordr, lim, off) into rows_, ng using d1, d2, eff, flt;
  if cardinality(d.tot) > 0 then
    foreach k in array d.tot loop targs := targs || format('%L, round(coalesce(sum((r ->> %L)::numeric), 0), 4), ', k, k); end loop;
    execute format('select jsonb_build_object(%s) from public.%I($1, $2, $3, $4) r', left(targs, length(targs) - 2), fn) into totals_ using d1, d2, eff, flt;
  end if;
  hm := (off + pgsize) < least(ng, cap);
  if ng > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ng)); end if;
  if jsonb_array_length(rows_) = 0 or ng = 0 then
    dn := true; notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', outc, 'rows', rows_, 'totals', totals_, 'compare', null,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ng, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', '[]'::jsonb, 'sort', sk, 'dir', sd, 'cost_shown', public.rpt_cost_ok(), 'today', today));
end $$;

-- ---------- wrap the engine-2 entry points (renamed once; a re-run keeps the wrappers) ----------
do $$ begin
  if to_regprocedure('public.report_run2_core(text,jsonb,text,text,int)') is null then alter function public.report_run2(text, jsonb, text, text, int) rename to report_run2_core; end if;
  if to_regprocedure('public.report_catalog2_core()') is null then alter function public.report_catalog2() rename to report_catalog2_core; end if;
end $$;
revoke all on function public.report_run2_core(text, jsonb, text, text, int), public.report_catalog2_core() from public, anon, authenticated;

create or replace function public.report_run2(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null, p_page int default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if exists (select 1 from public.report_defs3 where key = p_key and is_active) then return public.report_run3(p_key, p_filters, p_group, p_sort, p_page); end if;
  return public.report_run2_core(p_key, p_filters, p_group, p_sort, p_page);
end $$;
create or replace function public.report_catalog2() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return public.report_catalog2_core() || public.report_catalog3();
end $$;

create or replace function public.log_report_export2(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public._r2_keys()) or exists (select 1 from public.report_defs3 d where d.key = p_key and d.is_active)) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- every _r3q_* report function is private (they run as definer and do no access checks of their own): report files end with  select public._r3_lockdown();
create or replace function public._r3_lockdown() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select p.oid::regprocedure::text as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_r3q\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig); n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._r3_lockdown() from public, anon, authenticated;

revoke all on function public.report_run3(text, jsonb, text, text, int), public.report_catalog3(), public._r3_ok(public.report_defs3), public.report_run2(text, jsonb, text, text, int), public.report_catalog2(), public.log_report_export2(text, text, jsonb, int) from public, anon;
grant execute on function public.report_run3(text, jsonb, text, text, int), public.report_catalog3(), public.report_run2(text, jsonb, text, text, int), public.report_catalog2(), public.log_report_export2(text, text, jsonb, int) to authenticated;
revoke all on function public._r3_ok(public.report_defs3) from authenticated;
notify pgrst, 'reload schema';
-- ============================================================
-- PHASE 25 (report builder 25): reports on engine 3 (needs phase24; read-only, additive, paste-twice safe)
--   s10_orders  S10  orders / online / delivery            (20-1, 20-6)
--   d5_lapsed   D5   lapsed customers, new vs repeat       (sales)
--   m1_rfm      M1   RFM customer segments                 (sales)
--   x2_bypass   X2   releases / emergency / grant use      (release_requests, emergency_requests)
--   x3_audit_log X3  audit & correction log (owner only)   (audit_log)
--   x4_compliance X4 form submission compliance            (entries 14-1, 10-1)
--   x5_staff_trend X5 staff indicators, monthly            (sales, same logic as biz_staff)
--   g2_paper_numbers G2 duplicate / out-of-order paper no. (entries.data.paper_no)
--   k3_store_ledger K3 store ledger per item and kind      (stock_ledger; quantities only)
--   e2_expense_trend E2 expense trend vs previous period   (10-2)
--   e3_weak_control E3 no-receipt / over-limit / imprest   (10-2, 14-1)
--   e4_marketing_limit E4 marketing spend vs head limit    (18-1, option_lists, location_settings)
--   w1_cash_flow W1  daily cash flow per location          (_daybook_lines*)
--   w2_handover_vs_hub W2 handover (10-1) vs hub count     (10-1, entry_counts, check_data)
-- ============================================================

-- ---------- S10 orders, online & delivery ----------
create or replace function public._r3q_s10_orders(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('source', '20-1', 'channel', x.channel, 'online', x.online, 'delivery', x.delivery, 'orders', count(*),
      'amount', coalesce(sum(x.total), 0), 'advance', coalesce(sum(x.adv), 0), 'balance', coalesce(sum(x.total - x.disc - x.adv), 0),
      'handed', count(*) filter (where x.signed), 'not_collected', count(*) filter (where x.nc), 'returned', null, 'delivery_charge', null)
    from (select coalesce(nullif(btrim(e.data ->> 'channel'), ''), '-') as channel, coalesce(nullif(btrim(e.data ->> 'online'), ''), '-') as online,
                 coalesce(nullif(btrim(e.data ->> 'deliv_by'), ''), '-') as delivery,
                 coalesce(public._r2_num(e.data -> 'total'), 0) as total, coalesce(public._r2_num(e.data -> 'discount'), 0) as disc, coalesce(public._r2_num(e.data -> 'advance'), 0) as adv,
                 (e.data ->> 'cust_signed') = 'true' as signed, (e.data ->> 'not_collected') = 'true' as nc
            from public.entries e
           where e.form_code = '20-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) x
   group by x.channel, x.online, x.delivery
  union all
  select jsonb_build_object('source', '20-6', 'channel', 'ledger', 'online', y.platform, 'delivery', y.delivery, 'orders', count(*),
      'amount', coalesce(sum(y.amt), 0), 'advance', null, 'balance', null,
      'handed', count(*) filter (where y.outcome = 'handed'), 'not_collected', null, 'returned', count(*) filter (where y.outcome = 'returned'),
      'delivery_charge', coalesce(sum(y.dch), 0))
    from (select coalesce(nullif(lower(btrim(l ->> 'platform')), ''), '-') as platform, coalesce(nullif(btrim(l ->> 'delivery'), ''), '-') as delivery,
                 public._r2_num(l -> 'amt') as amt, public._r2_num(l -> 'dcharge') as dch, l ->> 'outcome' as outcome
            from public.entries e
            cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
           where e.form_code = '20-6' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) y
   group by y.platform, y.delivery;
$$;

-- ---------- D5 lapsed & new vs repeat customers ----------
create or replace function public._r3q_d5_lapsed(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with s as (select x.customer_id, x.sale_date, x.total from public.sales x
              where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs) and x.sale_date <= d2),
  c as (select customer_id, min(sale_date) as first_d, max(sale_date) as last_d, count(*) as n_all,
               count(*) filter (where sale_date >= d1) as n_p, coalesce(sum(total) filter (where sale_date >= d1), 0) as amt_p
          from s group by customer_id)
  select jsonb_build_object('customer_id', cu.id, 'name', cu.name, 'mobile', cu.mobile,
      'kind', case when c.first_d >= d1 then 'new' when c.n_p > 0 then 'repeat' else 'lapsed' end,
      'first_date', c.first_d, 'last_date', c.last_d, 'days_silent', d2 - c.last_d, 'orders_period', c.n_p, 'amount_period', c.amt_p, 'orders_total', c.n_all)
    from c join public.customers cu on cu.id = c.customer_id
   where c.n_p > 0 or c.last_d >= d1 - 180;
$$;

-- ---------- M1 RFM segments (window = the chosen period) ----------
create or replace function public._r3q_m1_rfm(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with c as (select x.customer_id, max(x.sale_date) as last_d, count(*) as n, coalesce(sum(x.total), 0) as amt
               from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs) and x.sale_date between d1 and d2
              group by x.customer_id)
  select jsonb_build_object('customer_id', cu.id, 'name', cu.name, 'mobile', cu.mobile,
      'segment', case when c.n >= 3 and d2 - c.last_d <= 30 then 'Champion' when c.n >= 2 and d2 - c.last_d > 60 then 'At-risk' when c.n = 1 then 'One-time' else 'Regular' end,
      'recency_days', d2 - c.last_d, 'frequency', c.n, 'monetary', c.amt, 'last_date', c.last_d)
    from c join public.customers cu on cu.id = c.customer_id;
$$;

-- ---------- X2 releases / emergency / grant use ----------
create or replace function public._r3q_x2_bypass(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('staff_id', u.staff, 'staff_name', max(pr.full_name), 'kind', u.kind, 'code', u.code, 'requests', count(*),
      'approved', count(*) filter (where u.st in ('approved', 'used')), 'rejected', count(*) filter (where u.st = 'rejected'),
      'pending', count(*) filter (where u.st = 'pending'), 'other', count(*) filter (where u.st in ('expired', 'cancelled')), 'amount', coalesce(sum(u.amt), 0))
    from (select coalesce(r.requested_staff, '-') as staff, 'release'::text as kind, r.flag_code as code, r.status as st, r.flag_amount as amt
            from public.release_requests r join public.entries e on e.id = r.entry_id
           where (r.requested_at at time zone 'Asia/Dhaka')::date between d1 and d2 and e.location_id = any (locs)
          union all
          select coalesce(q.requested_staff, '-'), 'emergency', q.grant_code, q.status, q.amount
            from public.emergency_requests q
           where (q.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and q.location_id = any (locs)) u
    left join public.profiles pr on pr.staff_id = u.staff
   group by u.staff, u.kind, u.code;
$$;

-- ---------- X3 audit log (owner only) ----------
create or replace function public._r3q_x3_audit_log(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('table_name', a.table_name, 'action', a.action, 'staff_id', coalesce(a.staff_id, '-'), 'events', count(*),
      'first_day', min((a.at at time zone 'Asia/Dhaka')::date), 'last_day', max((a.at at time zone 'Asia/Dhaka')::date))
    from public.audit_log a
   where cardinality(locs) > 0 and (a.at at time zone 'Asia/Dhaka')::date between d1 and d2
   group by a.table_name, a.action, coalesce(a.staff_id, '-');
$$;

-- ---------- X4 form submission compliance (14-1 and 10-1 per shop) ----------
create or replace function public._r3q_x4_compliance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with today as (select (now() at time zone 'Asia/Dhaka')::date as t),
  hi as (select least(d2, (select t from today)) as h),
  n as (select greatest((select h from hi) - d1 + 1, 0) as days)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'form', f.code, 'days', (select days from n), 'submitted_days', coalesce(s.sd, 0),
      'missing_days', greatest((select days from n) - coalesce(s.sd, 0), 0),
      'compliance_pct', case when (select days from n) > 0 then round(100.0 * coalesce(s.sd, 0) / (select days from n), 2) end,
      'stale_drafts', coalesce(s.stale, 0), 'late_submits', coalesce(s.late, 0))
    from public.locations l
    cross join (values ('14-1'), ('10-1')) f(code)
    left join lateral (
      select count(distinct e.entry_date) filter (where e.status in ('submitted', 'approved')) as sd,
             count(*) filter (where e.status = 'draft' and e.entry_date < (select t from today) - 1) as stale,
             count(*) filter (where e.status in ('submitted', 'approved') and not e.entered_later and e.submitted_at is not null
                                and (e.submitted_at at time zone 'Asia/Dhaka')::date > e.entry_date) as late
        from public.entries e where e.form_code = f.code and e.location_id = l.id and e.entry_date between d1 and d2) s on true
   where l.id = any (locs) and l.kind = 'showroom' and l.is_active and l.status = 'live';
$$;

-- ---------- X5 staff indicators, monthly (same logic as biz_staff, month by month) ----------
create or replace function public._r3q_x5_staff_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with s as (select x.*, date_trunc('month', x.sale_date)::date as mon from public.sales x where x.sale_date between d1 and d2 and x.location_id = any (locs)),
  ovr as (select s.id, bool_or(e ->> 'override' = 'true') as o from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e group by s.id),
  per as (select s.created_staff as st, s.mon, count(*) filter (where s.status = 'done') as n, coalesce(sum(s.total) filter (where s.status = 'done'), 0) as rev,
                 coalesce(sum(s.discount) filter (where s.status = 'done'), 0) as disc, count(*) filter (where s.status = 'void') as vn,
                 count(*) filter (where s.status = 'done' and o.o) as onum, count(*) filter (where s.status = 'done' and s.quick) as qn,
                 coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) as duea
            from s left join ovr o on o.id = s.id group by s.created_staff, s.mon)
  select jsonb_build_object('staff_id', coalesce(p.st, '-'), 'staff_name', pr.full_name, 'month', p.mon, 'orders', p.n, 'revenue', p.rev,
      'discount_pct', case when p.rev + p.disc > 0 then round(100 * p.disc / (p.rev + p.disc), 2) end,
      'void_pct', case when p.n + p.vn > 0 then round(100 * p.vn::numeric / (p.n + p.vn), 2) end,
      'override_pct', case when p.n > 0 then round(100 * p.onum::numeric / p.n, 2) end,
      'quick_pct', case when p.n > 0 then round(100 * p.qn::numeric / p.n, 2) end,
      'due_pct', case when p.rev > 0 then round(100 * p.duea / p.rev, 2) end)
    from per p left join public.profiles pr on pr.staff_id = p.st;
$$;

-- ---------- G2 duplicate / out-of-order paper numbers and book usage ----------
create or replace function public._r3q_g2_paper_numbers(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select e.location_id, e.form_code, e.entry_date, e.serial,
                    public.norm_paper_serial(coalesce(nullif(btrim(e.data ->> 'paper_no'), ''), nullif(btrim(e.paper_serial), ''))) as pn
               from public.entries e where e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  q as (select p.*, case when p.pn ~ '^[0-9]{1,9}$' then p.pn::int end as num from p),
  dup as (select location_id, form_code, pn, count(*) as c from q where pn is not null group by location_id, form_code, pn having count(*) > 1),
  dsum as (select location_id, form_code, count(*) as dup_numbers from dup group by location_id, form_code),
  ord as (select location_id, form_code, count(*) filter (where entry_date < prev_d) as ooo
            from (select q.*, lag(entry_date) over (partition by location_id, form_code order by num, entry_date, serial) as prev_d from q where num is not null) z
           group by location_id, form_code),
  agg as (select location_id, form_code, count(*) as entries, count(*) filter (where pn is null) as no_pn, count(distinct pn) as dist,
                 min(num) as mn, max(num) as mx, count(distinct num) as dnum from q group by location_id, form_code)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'form', a.form_code, 'entries', a.entries, 'no_paper_no', a.no_pn,
      'distinct_numbers', a.dist, 'duplicate_numbers', coalesce(ds.dup_numbers, 0), 'out_of_order', coalesce(o.ooo, 0),
      'first_no', a.mn, 'last_no', a.mx, 'missing_numbers', case when a.mn is not null then (a.mx - a.mn + 1) - a.dnum end)
    from agg a join public.locations l on l.id = a.location_id
    left join dsum ds on ds.location_id = a.location_id and ds.form_code = a.form_code
    left join ord o on o.location_id = a.location_id and o.form_code = a.form_code;
$$;

-- ---------- K3 store ledger per item and kind (quantities only, no cost) ----------
create or replace function public._r3q_k3_store_ledger(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'unit', it.unit, 'kind', sl.reason, 'movements', count(*),
      'in_qty', coalesce(sum(sl.qty_delta) filter (where sl.qty_delta > 0), 0), 'out_qty', coalesce(-sum(sl.qty_delta) filter (where sl.qty_delta < 0), 0),
      'net_qty', sum(sl.qty_delta))
    from public.stock_ledger sl join public.items it on it.id = sl.item_id
   where sl.location_id = any (locs) and (sl.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
     and sl.reverses_id is null and not exists (select 1 from public.stock_ledger r where r.reverses_id = sl.id)
     and (public.rpt_arr_text(flt -> 'categories') is null or it.category = any (public.rpt_arr_text(flt -> 'categories')))
   group by it.id, it.code, it.name_bn, it.unit, sl.reason;
$$;

-- ---------- E2 expense trend with the previous period ----------
create or replace function public._r3q_e2_expense_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ln as (select e.entry_date as d, coalesce(nullif(btrim(l ->> 'head'), ''), '-') as head, public._r2_num(l -> 'amount') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (locs)
                 and e.entry_date between d1 - (d2 - d1 + 1) and d2),
  g as (select head, coalesce(sum(amt) filter (where d >= d1), 0) as cur, coalesce(sum(amt) filter (where d < d1), 0) as prev from ln group by head)
  select jsonb_build_object('head', coalesce(o.label_bn, g.head), 'current', g.cur, 'previous', g.prev, 'change', g.cur - g.prev,
      'change_pct', case when g.prev > 0 then round(100 * (g.cur - g.prev) / g.prev, 2) end)
    from g left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = g.head;
$$;

-- ---------- E3 no-receipt / over-limit / imprest ----------
create or replace function public._r3q_e3_weak_control(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', '10-2', 'approver', v.appr, 'vouchers', count(*),
      'no_receipt_lines', coalesce(sum(v.nr_lines), 0), 'no_receipt_amount', coalesce(sum(v.nr_amt), 0),
      'over_limit_vouchers', count(*) filter (where v.over), 'over_limit_amount', coalesce(sum(v.over_amt), 0),
      'approval_missing', count(*) filter (where v.appr_miss), 'reason_missing', count(*) filter (where v.reason_miss),
      'imprest_diff_sheets', count(*) filter (where v.imp_diff), 'imprest_diff_amount', coalesce(sum(v.imp_amt), 0))
    from (select e.location_id, coalesce(nullif(btrim(e.data ->> 'approved_by'), ''), '-') as appr, x.nr_lines, x.nr_amt,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'over_limit') as over,
                 (select coalesce(sum(public._r2_num(fe -> 'amount')), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'over_limit') as over_amt,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'approval_missing') as appr_miss,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'receipt_reason_missing') as reason_miss,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'imprest_mismatch') as imp_diff,
                 (select coalesce(sum(abs(public._r2_num(fe -> 'amount'))), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'imprest_mismatch') as imp_amt
            from public.entries e
            cross join lateral (select case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end as fa) fl
            cross join lateral (select count(*) filter (where ln ->> 'receipt' = 'no' and public._r2_num(ln -> 'amount') > 0) as nr_lines,
                                       sum(public._r2_num(ln -> 'amount')) filter (where ln ->> 'receipt' = 'no') as nr_amt
                                  from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln) x
           where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn, v.appr
  union all
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', '14-1', 'approver', '-', 'vouchers', count(*),
      'no_receipt_lines', null, 'no_receipt_amount', null, 'over_limit_vouchers', null, 'over_limit_amount', null, 'approval_missing', null, 'reason_missing', null,
      'imprest_diff_sheets', count(*) filter (where v.imp_diff), 'imprest_diff_amount', coalesce(sum(v.imp_amt), 0))
    from (select e.location_id,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'open_imprest_diff') as imp_diff,
                 (select coalesce(sum(abs(public._r2_num(fe -> 'amount'))), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'open_imprest_diff') as imp_amt
            from public.entries e
            cross join lateral (select case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end as fa) fl
           where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn;
$$;

-- ---------- E4 marketing spend vs the monthly head limit ----------
create or replace function public._r3q_e4_marketing_limit(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ln as (select e.location_id, date_trunc('month', coalesce(public._db_date(l ->> 'date'), e.entry_date))::date as mon,
                     case when l ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(l ->> 'head'), ''), '-') end as head,
                     public._r2_num(l -> 'amt') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)
                 and coalesce(public._db_date(l ->> 'date'), e.entry_date) between d1 and d2),
  g as (select location_id, mon, head, sum(amt) filter (where amt > 0) as spend from ln group by location_id, mon, head having sum(amt) filter (where amt > 0) is not null),
  w as (select g.*, o.label_bn,
               coalesce(case when o.extra ->> 'limit_month' ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then (o.extra ->> 'limit_month')::numeric end,
                        (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = g.location_id and ls.key = 'mkt_limit_' || g.head)) as lim
          from g left join public.option_lists o on o.list_code = 'marketing_heads' and o.value_code = g.head)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'month', w.mon, 'head', coalesce(w.label_bn, w.head), 'spend', w.spend, 'limit', w.lim,
      'used_pct', case when w.lim > 0 then round(100 * w.spend / w.lim, 2) end, 'over_amount', case when w.lim is not null then greatest(w.spend - w.lim, 0) end)
    from w join public.locations l on l.id = w.location_id;
$$;

-- ---------- W1 daily cash flow per location (cash-flow only: no salary lines, no internal lines) ----------
create or replace function public._r3q_w1_cash_flow(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'day', u.d,
      'cash_in', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode = 'cash'), 0), 'cash_out', coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode = 'cash'), 0),
      'net_cash', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode = 'cash'), 0) - coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode = 'cash'), 0),
      'other_in', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode <> 'cash'), 0), 'other_out', coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode <> 'cash'), 0))
    from (select * from public._daybook_lines(locs, '{}'::int[], d1, d2) union all select * from public._daybook_lines12(locs, d1, d2) union all select * from public._daybook_lines23(locs, d1, d2)) u
    join public.locations l on l.id = u.loc
   where not u.internal and not u.sensitive
   group by l.id, l.name_bn, u.d;
$$;

-- ---------- W2 handover (10-1) vs hub count ----------
create or replace function public._r3q_w2_handover_vs_hub(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'carrier', v.carrier, 'slips', count(*), 'handover', coalesce(sum(v.handover), 0),
      'hub_counted_slips', count(*) filter (where v.hub is not null), 'hub_received', sum(v.hub),
      'diff', sum(v.hub - v.handover) filter (where v.hub is not null),
      'short_slips', count(*) filter (where v.hub is not null and v.hub < v.handover), 'over_slips', count(*) filter (where v.hub is not null and v.hub > v.handover),
      'not_counted', count(*) filter (where v.hub is null))
    from (select e.location_id, coalesce(nullif(btrim(e.data ->> 'carrier'), ''), '-') as carrier, h.amt as handover,
                 case when ec.counted is not null then ec.counted
                      when e.check_data ? 'rcount' and public._den_total18(e.check_data -> 'rcount', false) > 0 then public._den_total18(e.check_data -> 'rcount', false) end as hub
            from public.entries e
            left join public.entry_counts ec on ec.entry_id = e.id and ec.section = 'hub'
            cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
                + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
                + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
                + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
                + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
                + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
           where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn, v.carrier;
$$;

-- ---------- registry ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('s10_orders', 'S10', 'orders', 'অর্ডার, অনলাইন ও ডেলিভারি', 'Orders, online & delivery', 'Order, online ও delivery',
  '[["source","উৎস ফর্ম","Source form","text"],["channel","মাধ্যম","Channel","text"],["online","অনলাইন/প্ল্যাটফর্ম","Online / platform","text"],["delivery","ডেলিভারি","Delivery","text"],["orders","অর্ডার","Orders","int"],["amount","অঙ্ক","Amount","money"],["advance","অ্যাডভান্স","Advance","money"],["balance","বাকি","Balance","money"],["handed","হাতে দেওয়া","Handed over","int"],["not_collected","নেওয়া হয়নি","Not collected","int"],["returned","ফেরত","Returned","int"],["delivery_charge","ডেলিভারি চার্জ","Delivery charge","money"]]'::jsonb,
  array['orders','amount','advance','balance','handed','not_collected','returned','delivery_charge'], 'amount', 'desc', array['locations'], false, false, false, 2500),
 ('d5_lapsed', 'D5', 'sales', 'নিষ্ক্রিয় ও নতুন-পুরনো গ্রাহক', 'Lapsed, new vs repeat customers', 'Lapsed ও নতুন-পুরনো গ্রাহক',
  '[["customer_id","","","id"],["name","নাম","Name","text"],["mobile","মোবাইল","Mobile","text"],["kind","ধরন (new/repeat/lapsed)","Kind (new/repeat/lapsed)","text"],["first_date","প্রথম কেনা","First purchase","date"],["last_date","শেষ কেনা","Last purchase","date"],["days_silent","নীরব দিন","Days silent","int"],["orders_period","এই সময়ের অর্ডার","Orders in period","int"],["amount_period","এই সময়ের টাকা","Amount in period","money"],["orders_total","মোট অর্ডার","Orders to date","int"]]'::jsonb,
  array['orders_period','amount_period'], 'amount_period', 'desc', array['locations'], false, false, false, 2510),
 ('m1_rfm', 'M1', 'sales', 'গ্রাহক সেগমেন্ট (RFM)', 'Customer segments (RFM)', 'Customer segment (RFM)',
  '[["customer_id","","","id"],["name","নাম","Name","text"],["mobile","মোবাইল","Mobile","text"],["segment","সেগমেন্ট","Segment","text"],["recency_days","শেষ কেনার পর দিন","Days since last purchase","int"],["frequency","বার","Orders","int"],["monetary","টাকা","Spend","money"],["last_date","শেষ কেনা","Last purchase","date"]]'::jsonb,
  array['frequency','monetary'], 'monetary', 'desc', array['locations'], false, false, false, 2520),
 ('x2_bypass', 'X2', 'control', 'ছাড়, জরুরি অনুমোদন ও গ্রান্ট ব্যবহার', 'Releases, emergency & grant use', 'Release, emergency ও grant ব্যবহার',
  '[["staff_id","স্টাফ আইডি","Staff ID","text"],["staff_name","নাম","Name","text"],["kind","ধরন","Kind","text"],["code","কোড","Code","text"],["requests","অনুরোধ","Requests","int"],["approved","অনুমোদিত","Approved","int"],["rejected","বাতিল","Rejected","int"],["pending","অপেক্ষায়","Pending","int"],["other","মেয়াদ শেষ/বাতিল","Expired/cancelled","int"],["amount","অঙ্ক","Amount","money"]]'::jsonb,
  array['requests','approved','rejected','pending','other','amount'], 'requests', 'desc', array['locations'], false, false, false, 2530),
 ('x3_audit_log', 'X3', 'control', 'অডিট ও সংশোধন লগ', 'Audit & correction log', 'Audit ও correction log',
  '[["table_name","টেবিল","Table","text"],["action","কাজ","Action","text"],["staff_id","স্টাফ","Staff","text"],["events","ঘটনা","Events","int"],["first_day","প্রথম দিন","First day","date"],["last_day","শেষ দিন","Last day","date"]]'::jsonb,
  array['events'], 'events', 'desc', '{}'::text[], false, false, true, 2540),
 ('x4_compliance', 'X4', 'control', 'ফর্ম জমার নিয়ম-পালন', 'Form submission compliance', 'Form জমার compliance',
  '[["location_id","","","id"],["location","শোরুম","Shop","text"],["form","ফর্ম","Form","text"],["days","দিন","Days","int"],["submitted_days","জমা-দেওয়া দিন","Days submitted","int"],["missing_days","বাদ-পড়া দিন","Days missing","int"],["compliance_pct","পালন %","Compliance %","pct"],["stale_drafts","পুরনো খসড়া","Stale drafts","int"],["late_submits","দেরিতে জমা","Late submits","int"]]'::jsonb,
  array['days','submitted_days','missing_days','stale_drafts','late_submits'], 'missing_days', 'desc', array['locations'], false, false, false, 2550),
 ('x5_staff_trend', 'X5', 'staff', 'স্টাফ সূচক ধারা (মাসওয়ারি)', 'Staff indicators by month', 'Staff সূচক ধারা (monthly)',
  '[["staff_id","স্টাফ আইডি","Staff ID","text"],["staff_name","নাম","Name","text"],["month","মাস","Month","date"],["orders","বিক্রি","Sales","int"],["revenue","বিক্রয়","Revenue","money"],["discount_pct","ছাড় %","Discount %","pct"],["void_pct","বাতিল %","Void %","pct"],["override_pct","দাম বদল %","Override %","pct"],["quick_pct","কুইক %","Quick %","pct"],["due_pct","বাকি %","Due %","pct"]]'::jsonb,
  array['orders','revenue'], 'month', 'desc', array['locations'], false, false, false, 2560),
 ('g2_paper_numbers', 'G2', 'control', 'ডুপ্লিকেট/উল্টো ক্রম ও বই-ব্যবহার', 'Duplicate / out-of-order paper numbers', 'Duplicate/উল্টো ক্রম ও বই-ব্যবহার',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["entries","এন্ট্রি","Entries","int"],["no_paper_no","নম্বর ছাড়া","Without number","int"],["distinct_numbers","আলাদা নম্বর","Distinct numbers","int"],["duplicate_numbers","ডুপ্লিকেট নম্বর","Duplicate numbers","int"],["out_of_order","উল্টো ক্রম","Out of order","int"],["first_no","প্রথম নম্বর","First no.","int"],["last_no","শেষ নম্বর","Last no.","int"],["missing_numbers","বাদ-পড়া নম্বর","Missing numbers","int"]]'::jsonb,
  array['entries','no_paper_no','duplicate_numbers','out_of_order','missing_numbers'], 'duplicate_numbers', 'desc', array['locations'], false, false, false, 2570),
 ('k3_store_ledger', 'K3', 'stock', 'স্টক মুভমেন্ট (আইটেম ও ধরন)', 'Store ledger movement', 'Stock movement (item ও kind)',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["unit","একক","Unit","text"],["kind","ধরন","Kind","text"],["movements","মুভমেন্ট","Movements","int"],["in_qty","ঢুকেছে","In","num"],["out_qty","বেরিয়েছে","Out","num"],["net_qty","নিট","Net","num"]]'::jsonb,
  array['movements'], 'movements', 'desc', array['locations','brands','categories'], false, false, false, 2580),
 ('e2_expense_trend', 'E2', 'expense', 'খরচের ধারা ও আগের সময়ের তুলনা', 'Expense trend vs previous period', 'খরচের ধারা (আগের সময়ের সাথে)',
  '[["head","খাত","Head","text"],["current","এই সময়","Current","money"],["previous","আগের সময়","Previous","money"],["change","পরিবর্তন","Change","money"],["change_pct","পরিবর্তন %","Change %","pct"]]'::jsonb,
  array['current','previous','change'], 'change', 'desc', array['locations'], false, false, false, 2590),
 ('e3_weak_control', 'E3', 'expense', 'রসিদহীন, সীমা-ছাড়া ও ইমপ্রেস্ট', 'No-receipt, over-limit & imprest', 'রসিদহীন/সীমা-ছাড়া/imprest',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["source","ফর্ম","Form","text"],["approver","অনুমোদনকারী","Approver","text"],["vouchers","ভাউচার/শিট","Vouchers / sheets","int"],["no_receipt_lines","রসিদ ছাড়া লাইন","No-receipt lines","int"],["no_receipt_amount","রসিদ ছাড়া টাকা","No-receipt amount","money"],["over_limit_vouchers","সীমার উপরে ভাউচার","Over-limit vouchers","int"],["over_limit_amount","সীমার উপরের লাইন (বড়)","Over-limit line (largest)","money"],["approval_missing","অনুমোদনকারী নেই","Approver missing","int"],["reason_missing","কারণ নেই","Reason missing","int"],["imprest_diff_sheets","ইমপ্রেস্ট অমিল","Imprest mismatch","int"],["imprest_diff_amount","ইমপ্রেস্ট অমিলের টাকা","Imprest mismatch amount","money"]]'::jsonb,
  array['vouchers','no_receipt_lines','no_receipt_amount','over_limit_vouchers','over_limit_amount','approval_missing','reason_missing','imprest_diff_sheets','imprest_diff_amount'], 'no_receipt_amount', 'desc', array['locations'], false, false, false, 2600),
 ('e4_marketing_limit', 'E4', 'marketing', 'মার্কেটিং খরচ বনাম মাসিক সীমা', 'Marketing spend vs monthly head limit', 'মার্কেটিং খরচ vs monthly limit',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["month","মাস","Month","date"],["head","খাত","Head","text"],["spend","খরচ","Spend","money"],["limit","মাসিক সীমা","Monthly limit","money"],["used_pct","ব্যবহার %","Used %","pct"],["over_amount","সীমার বেশি","Over limit","money"]]'::jsonb,
  array['spend','over_amount'], 'spend', 'desc', array['locations'], false, false, false, 2610),
 ('w1_cash_flow', 'W1', 'cash', 'দৈনিক ক্যাশ প্রবাহ', 'Daily cash flow', 'Daily cash flow',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["day","দিন","Day","date"],["cash_in","নগদ ঢুকেছে","Cash in","money"],["cash_out","নগদ বেরিয়েছে","Cash out","money"],["net_cash","নিট নগদ","Net cash","money"],["other_in","ব্যাংক/মোবাইল ঢুকেছে","Bank/mobile in","money"],["other_out","ব্যাংক/মোবাইল বেরিয়েছে","Bank/mobile out","money"]]'::jsonb,
  array['cash_in','cash_out','net_cash','other_in','other_out'], 'day', 'desc', array['locations'], false, false, false, 2620),
 ('w2_handover_vs_hub', 'W2', 'cash', 'হ্যান্ডওভার বনাম হাব গণনা', 'Handover vs hub count', 'Handover vs hub গণনা',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["carrier","বহনকারী","Carrier","text"],["slips","স্লিপ","Slips","int"],["handover","হ্যান্ডওভার","Handover","money"],["hub_counted_slips","হাবে গোনা স্লিপ","Slips counted at hub","int"],["hub_received","হাবে প্রাপ্ত","Hub received","money"],["diff","পার্থক্য (হাব − হ্যান্ডওভার)","Difference (hub − handover)","money"],["short_slips","কম স্লিপ","Short slips","int"],["over_slips","বেশি স্লিপ","Over slips","int"],["not_counted","হাবে গোনা হয়নি","Not counted at hub","int"]]'::jsonb,
  array['slips','handover','hub_counted_slips','hub_received','diff','short_slips','over_slips','not_counted'], 'diff', 'asc', array['locations'], false, false, false, 2630)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols,
  tot = excluded.tot, sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort;

select public._r3_lockdown();
-- ============================================================
-- PHASE 26 (report engine 3, batch R3-26): 13 reports on the engine of phase24
--   P2 p2_rate_trend      purchase-rate trend per item / supplier        (cost)
--   P4 p4_supplier_score  supplier scorecard                              (cost)
--   P5 p5_po_match        PO - GRN - bill 3-way match and open POs        (cost)
--   P6 p6_purchase_budget purchase spent vs the 10-4 budget and outlook   (cost)
--   K2 k2_count_variance  stock-count variance, repeat offenders          (quantities only)
--   F1 f1_production      production runs, sheet output, dispatch         (void runs shown as a status)
--   F2 f2_yield           yield vs the approved 05-4 standard
--   F3 f3_raw_vs_recipe   raw material really issued vs the recipe
--   F4 f4_breakdowns      machine breakdowns and maintenance requests
--   M2 m2_marketing_vs_sales  marketing spend and sales side by side per day
--   Q1 q1_fridge_temp     fridge temperature log, out-of-range readings
--   Q2 q2_hygiene         hygiene / expiry / checklist compliance
--   Q3 q3_complaints      complaints and sale-return root causes
-- Needs phase24 (and phase17 paper_serial, phase19 production_runs, phase23 production_runs.status). Additive and idempotent: paste twice is safe.
-- Form field ids were checked in web/forms.js, forms_stock.js, forms_factory.js, forms_cash.js, forms_sales.js.
-- ============================================================

-- ---------- private helpers (called only from the report functions below) ----------
create or replace function public._p26_d(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return t::date;
exception when others then return null;
end $$;

create or replace function public._p26_b(j jsonb) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(j in ('true'::jsonb, '"true"'::jsonb, '"yes"'::jsonb, '1'::jsonb, '"1"'::jsonb), false);
$$;

create or replace function public._p26_arr(j jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end;
$$;

-- rate observations: posted purchase bills (lines) and submitted/approved 04-1 GRN lines. Cost data: only called from cost reports.
create or replace function public._p26_rates(d1 date, d2 date, locs int[]) returns table (item_id uuid, sk text, sname text, dt date, qty numeric, rate numeric, ord text)
language sql stable security definer set search_path = public as $$
  select pl.item_id, lower(btrim(s.name)), btrim(s.name), b.bill_date, coalesce(pl.base_qty, pl.qty), coalesce(pl.unit_cost_base, pl.unit_cost), b.id::text || ':' || pl.line_no::text
    from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id join public.suppliers s on s.id = b.supplier_id
   where b.status = 'posted' and b.kind = 'bill' and pl.item_id is not null and b.bill_date between d1 and d2 and b.location_id = any (locs)
     and coalesce(pl.unit_cost_base, pl.unit_cost) > 0 and coalesce(pl.base_qty, pl.qty) > 0
  union all
  select i.id, lower(btrim(coalesce(s.name, e.data ->> 'supplier'))), btrim(coalesce(s.name, e.data ->> 'supplier')), e.entry_date, public._r2_num(r -> 'counted'), public._r2_num(r -> 'rate'), e.id::text || ':' || n.ord::text
    from public.entries e
    cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'lines')) with ordinality n(r, ord)
    join public.items i on i.code = n.r ->> 'item'
    left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
   where e.form_code = '04-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
     and nullif(btrim(coalesce(s.name, e.data ->> 'supplier')), '') is not null
     and public._r2_num(n.r -> 'rate') > 0 and public._r2_num(n.r -> 'counted') > 0
     -- a delivery entered as a purchase bill AND a GRN is counted once (the bill wins): no posted bill line for the same item and place within 3 days
     and not exists (select 1 from public.purchase_bills b2 join public.purchase_lines pl2 on pl2.bill_id = b2.id join public.suppliers s2 on s2.id = b2.supplier_id
                      where b2.status = 'posted' and b2.kind = 'bill' and pl2.item_id = i.id and b2.location_id = e.location_id and abs(b2.bill_date - e.entry_date) <= 3
                        and lower(btrim(s2.name)) = lower(btrim(coalesce(s.name, e.data ->> 'supplier'))));
$$;

-- one row per purchase order (06-3, not cancelled) with what was received (04-1 on that PO number) and what was billed (06-4)
create or replace function public._p26_po(d1 date, d2 date, locs int[])
returns table (entry_id uuid, location_id int, entry_date date, po_no text, sk text, supplier text, delivery_date date, po_lines int, po_total numeric, lines_open int,
               grn_n int, first_grn date, last_grn date, grn_value numeric, bill_n int, bill_amount numeric)
language sql stable security definer set search_path = public as $$
  with po as (
    select e.id, e.location_id, e.entry_date, e.data,
           coalesce(nullif(btrim(e.paper_serial), ''), nullif(btrim(e.data ->> 'paper_no'), ''), e.serial::text) as po_no,
           array_remove(array[public.norm_paper_serial(e.paper_serial), public.norm_paper_serial(e.data ->> 'paper_no'), e.serial::text], null) as keys,
           btrim(coalesce(s.name, e.data ->> 'supplier')) as sname
      from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
     where e.form_code = '06-3' and e.status in ('submitted', 'approved') and not public._p26_b(e.data -> 'cancel')
       and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  grn as (
    select g.id, g.entry_date, g.data, public.norm_paper_serial(g.data ->> 'po_no') as pk
      from public.entries g
     where g.form_code = '04-1' and g.status in ('submitted', 'approved') and g.data ->> 'paper' = 'po' and g.location_id = any (locs)
       and public.norm_paper_serial(g.data ->> 'po_no') is not null),
  bil as (
    select b.id, public.norm_paper_serial(b.data -> 'tri' -> 0 ->> 'po') as pk, public._r2_num(b.data -> 'bill_amount') as amt
      from public.entries b
     where b.form_code = '06-4' and b.status in ('submitted', 'approved') and b.location_id = any (locs)
       and public.norm_paper_serial(b.data -> 'tri' -> 0 ->> 'po') is not null)
  select po.id, po.location_id, po.entry_date, po.po_no, lower(po.sname), po.sname, public._p26_d(po.data ->> 'delivery_date'),
    (select count(*)::int from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0),
    (select sum(public._r2_num(r -> 'qty') * public._r2_num(r -> 'rate')) from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0),
    (select count(*)::int from (select r ->> 'item' as it, sum(public._r2_num(r -> 'qty')) as oq from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0 group by 1) o
      where o.oq > coalesce((select sum(public._r2_num(gl -> 'counted')) from grn g, jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl where g.pk = any (po.keys) and gl ->> 'item' = o.it), 0)),
    (select count(*)::int from grn g where g.pk = any (po.keys)),
    (select min(g.entry_date) from grn g where g.pk = any (po.keys)),
    (select max(g.entry_date) from grn g where g.pk = any (po.keys)),
    (select sum(public._r2_num(gl -> 'counted') * public._r2_num(gl -> 'rate')) from grn g, jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl where g.pk = any (po.keys)),
    (select count(*)::int from bil b where b.pk = any (po.keys)),
    (select sum(b.amt) from bil b where b.pk = any (po.keys))
  from po;
$$;

-- the purchase outlook of phase4 needs the caller's business-view right: where it is missing the figure is simply null
create or replace function public._p26_outlook(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return public.biz_outlook(p_loc, 7, 28);
exception when others then
  return null;
end $$;

-- ============================================================
-- P2 purchase-rate trend per item and supplier
-- ============================================================
create or replace function public._r3q_p2_rate_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  x as (
    select r.item_id, r.sk, min(r.sname) as sname, count(*) as n, sum(r.qty) as qty,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           min(r.rate) as min_rate, max(r.rate) as max_rate, sum(r.qty * r.rate) / nullif(sum(r.qty), 0) as avg_rate, max(r.dt) as last_date
      from public._p26_rates(d1, d2, locs) r group by r.item_id, r.sk)
  select jsonb_build_object('item_code', i.code, 'item_bn', i.name_bn, 'supplier', x.sname, 'n', x.n, 'qty', round(x.qty, 3),
    'first_rate', round(x.first_rate, 4), 'last_rate', round(x.last_rate, 4), 'min_rate', round(x.min_rate, 4), 'max_rate', round(x.max_rate, 4), 'avg_rate', round(x.avg_rate, 4),
    'change_pct', case when x.n > 1 and x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end, 'last_date', x.last_date)
    from x join public.items i on i.id = x.item_id cross join cat
   where cat.c is null or i.category = any (cat.c);
$$;

-- ============================================================
-- P4 supplier scorecard
-- ============================================================
create or replace function public._r3q_p4_supplier_score(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with sup as (
    select e.id, e.form_code, e.data, lower(btrim(coalesce(s.name, e.data ->> 'supplier'))) as sk, btrim(coalesce(s.name, e.data ->> 'supplier')) as sname
      from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
     where e.form_code in ('04-1', '06-4') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
       and nullif(btrim(coalesce(s.name, e.data ->> 'supplier')), '') is not null),
  gl as (
    select s.sk, s.sname, s.id, r ->> 'quality' as q, public._r2_num(r -> 'counted') as cnt, public._r2_num(r -> 'memo') as memo
      from sup s cross join lateral jsonb_array_elements(public._p26_arr(s.data -> 'lines')) r where s.form_code = '04-1'),
  grn as (
    select sk, min(sname) as sname, count(distinct id) as grns, count(*) as lines, count(*) filter (where memo is not null and cnt is not null and cnt < memo) as short_lines,
           count(*) filter (where q = 'return') as rejected, count(*) filter (where q = 'hold') as held, count(*) filter (where q = 'reduced') as reduced
      from gl group by sk),
  bil as (
    select sk, min(sname) as sname, count(*) as bills, count(*) filter (where data ->> 'short' = 'yes') as short_claims, count(*) filter (where data ->> 'returned' = 'yes') as return_claims
      from sup where form_code = '06-4' group by sk),
  po as (
    select p.sk, min(p.supplier) as sname, count(*) as pos, count(*) filter (where p.grn_n > 0 and p.delivery_date is not null) as pos_matched,
           count(*) filter (where p.grn_n > 0 and p.delivery_date is not null and p.first_grn > p.delivery_date) as late_pos,
           count(*) filter (where p.grn_n = 0 and p.delivery_date is not null and p.delivery_date < (now() at time zone 'Asia/Dhaka')::date) as overdue_open
      from public._p26_po(d1, d2, locs) p where p.sk is not null and p.sk <> '' group by p.sk),
  rr as (select * from public._p26_rates(d1, d2, locs)),
  rc as (
    select sk, avg(chg) as chg, count(*) as items
      from (select sk, item_id, (l - f) / f * 100 as chg
              from (select sk, item_id, (array_agg(rate order by dt, ord))[1] as f, (array_agg(rate order by dt desc, ord desc))[1] as l, count(*) as n from rr group by sk, item_id) a
             where n > 1 and f > 0) b group by sk),
  keys as (select sk, sname from grn union select sk, sname from bil union select sk, sname from po union select sk, min(sname) from rr group by sk)
  select jsonb_build_object('supplier', k.sname, 'grns', coalesce(g.grns, 0), 'lines', coalesce(g.lines, 0), 'short_lines', coalesce(g.short_lines, 0), 'rejected', coalesce(g.rejected, 0),
    'held', coalesce(g.held, 0), 'reduced', coalesce(g.reduced, 0), 'bills_checked', coalesce(b.bills, 0), 'short_claims', coalesce(b.short_claims, 0), 'return_claims', coalesce(b.return_claims, 0),
    'pos', coalesce(p.pos, 0), 'late_pos', case when coalesce(p.pos_matched, 0) > 0 then p.late_pos end, 'overdue_open', coalesce(p.overdue_open, 0),
    'rate_change_pct', case when c.chg is not null then round(c.chg, 2) end, 'rate_items', coalesce(c.items, 0))
    from (select sk, min(sname) as sname from keys where sk is not null and sk <> '' group by sk) k
    left join grn g on g.sk = k.sk left join bil b on b.sk = k.sk left join po p on p.sk = k.sk left join rc c on c.sk = k.sk;
$$;

-- ============================================================
-- P5 PO - GRN - bill match and open POs
-- ============================================================
create or replace function public._r3q_p5_po_match(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today)
  select jsonb_build_object('po_no', p.po_no, 'day', p.entry_date, 'location_bn', l.name_bn, 'supplier', coalesce(p.supplier, '-'), 'delivery_date', p.delivery_date,
    'po_lines', p.po_lines, 'lines_open', p.lines_open, 'po_total', round(coalesce(p.po_total, 0), 2), 'grn_n', p.grn_n, 'grn_value', case when p.grn_n > 0 then round(coalesce(p.grn_value, 0), 2) end,
    'bill_n', p.bill_n, 'bill_amount', case when p.bill_n > 0 then round(coalesce(p.bill_amount, 0), 2) end,
    'bill_diff', case when p.bill_n > 0 and p.grn_n > 0 and p.bill_amount is not null then round(p.bill_amount - coalesce(p.grn_value, 0), 2) end,
    'days_late', case when p.delivery_date is null then null
                      when p.grn_n = 0 or p.lines_open > 0 then greatest(t.today - p.delivery_date, 0)
                      else greatest(p.last_grn - p.delivery_date, 0) end,
    'status', case when p.grn_n = 0 then 'খোলা / open'
                   when p.lines_open > 0 then 'আংশিক / partial'
                   when p.bill_n = 0 then 'প্রাপ্ত, বিল নেই / received, not billed'
                   when p.bill_amount is not null and abs(p.bill_amount - coalesce(p.grn_value, 0)) <= 0.5 then 'বিল মিলেছে / matched'
                   else 'বিল অমিল / bill differs' end)
    from public._p26_po(d1, d2, locs) p join public.locations l on l.id = p.location_id cross join t;
$$;

-- ============================================================
-- P6 purchase spent vs the 10-4 purchase budget (+ the phase4 outlook for the latest sheet of each place)
--   budget = hub cash + showroom floats + bank + mobile + receivable(7d) - payable(7d) - protected minimum cash (location setting hub_min_cash), exactly as the 10-4 sheet works it out.
--   No hub_min_cash setting = the budget was never captured = null. Spent = posted purchase bills of the 7 days from the sheet date; where there are none, the 04-1 GRN value.
-- ============================================================
create or replace function public._r3q_p6_purchase_budget(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with b as (
    select e.id, e.location_id, e.entry_date,
      coalesce(public._r2_num(e.data -> 'hub_cash'), 0) + coalesce(public._r2_num(e.data -> 'sr_float'), 0) + coalesce(public._r2_num(e.data -> 'bank'), 0) + coalesce(public._r2_num(e.data -> 'mobile'), 0) as a,
      (select coalesce(sum(public._r2_num(x -> 'amt')), 0) from jsonb_array_elements(public._p26_arr(e.data -> 'recv')) x) as bt,
      (select coalesce(sum(public._r2_num(x -> 'amt')), 0) from jsonb_array_elements(public._p26_arr(e.data -> 'pay')) x) as ct,
      (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = e.location_id and ls.key = 'hub_min_cash') as mn,
      row_number() over (partition by e.location_id order by e.entry_date desc, e.serial desc) as rn
      from public.entries e
     where e.form_code = '10-4' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  c as (
    select b.*, case when b.mn is not null then b.a + b.bt - b.ct - b.mn end as budget,
      (select coalesce(sum(case when pb.kind = 'bill' then pb.total else -pb.total end), 0) from public.purchase_bills pb
        where pb.status = 'posted' and pb.location_id = b.location_id and pb.bill_date between b.entry_date and b.entry_date + 6) as bills,
      (select coalesce(sum(public._r2_num(gl -> 'counted') * public._r2_num(gl -> 'rate')), 0) from public.entries g
        cross join lateral jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl
        where g.form_code = '04-1' and g.status in ('submitted', 'approved') and g.location_id = b.location_id and g.entry_date between b.entry_date and b.entry_date + 6
          and public._r2_num(gl -> 'counted') > 0 and public._r2_num(gl -> 'rate') > 0) as grn,
      case when b.rn = 1 then public._p26_outlook(b.location_id) end as ol
      from b),
  d as (select c.*, case when c.bills > 0 then c.bills else c.grn end as spent from c)
  select jsonb_build_object('location_bn', l.name_bn, 'day', d.entry_date, 'cash_total', round(d.a, 2), 'receivable', round(d.bt, 2), 'payable', round(d.ct, 2), 'min_cash', d.mn, 'budget', round(d.budget, 2),
    'bills_7d', round(d.bills, 2), 'grn_7d', round(d.grn, 2), 'spent', round(d.spent, 2),
    'used_pct', case when d.budget > 0 then round(d.spent / d.budget * 100, 1) end, 'budget_left', case when d.budget is not null then round(d.budget - d.spent, 2) end,
    'outlook_low', case when d.ol is not null and jsonb_typeof(d.ol -> 'est_purchase_low') = 'number' then (d.ol ->> 'est_purchase_low')::numeric end,
    'outlook_high', case when d.ol is not null and jsonb_typeof(d.ol -> 'est_purchase_high') = 'number' then (d.ol ->> 'est_purchase_high')::numeric end)
    from d join public.locations l on l.id = d.location_id;
$$;

-- ============================================================
-- K2 stock-count variance per counter and item (quantities only; rows need both the counted and the book figure)
-- ============================================================
create or replace function public._r3q_k2_count_variance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  ln as (
    select e.location_id, e.entry_date, e.serial, nullif(btrim(e.data ->> 'counted_by'), '') as cb, r ->> 'item' as icode,
           public._r2_num(r -> 'count') as cnt, public._r2_num(r -> 'book') as bk, nullif(btrim(r ->> 'reason'), '') as reason
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'rows')) r
     where e.form_code = '04-3' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  g as (
    select ln.location_id, ln.cb, i.id as item_id, i.code, i.name_bn, count(*) as counts, count(*) filter (where ln.cnt <> ln.bk) as off_n,
           count(*) filter (where ln.cnt < ln.bk) as short_n, count(*) filter (where ln.cnt > ln.bk) as over_n,
           sum(ln.cnt - ln.bk) as net_var, sum(abs(ln.cnt - ln.bk)) as abs_var, max(ln.entry_date) as last_date,
           (array_agg(ln.reason order by ln.entry_date desc, ln.serial desc) filter (where ln.reason is not null and ln.cnt <> ln.bk))[1] as last_reason
      from ln join public.items i on i.code = ln.icode cross join cat
     where ln.cnt is not null and ln.bk is not null and (cat.c is null or i.category = any (cat.c))
     group by ln.location_id, ln.cb, i.id, i.code, i.name_bn)
  select jsonb_build_object('location_bn', l.name_bn, 'counter', coalesce(nullif(btrim(p.full_name), '') || ' · ' || g.cb, g.cb, '-'), 'item_code', g.code, 'item_bn', g.name_bn,
    'counts', g.counts, 'off_n', g.off_n, 'short_n', g.short_n, 'over_n', g.over_n, 'net_var', round(g.net_var, 3), 'abs_var', round(g.abs_var, 3),
    'off_pct', round(g.off_n * 100.0 / g.counts, 1), 'last_date', g.last_date, 'last_reason', g.last_reason)
    from g join public.locations l on l.id = g.location_id left join public.profiles p on p.staff_id = g.cb;
$$;

-- ============================================================
-- F1 production and dispatch: production_runs (void runs kept, status void), 05-1 sheets, stock transfers sent
-- ============================================================
create or replace function public._r3q_f1_production(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with u as (
    select 'রান / run'::text as source, (r.made_at at time zone 'Asia/Dhaka')::date as day, r.location_id, r.item_id, r.batches as batches, r.yield_base as qty, r.status as status, null::int as to_loc
      from public.production_runs r
     where r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
    union all
    select 'শিট / sheet', e.entry_date, e.location_id, i.id, case when o.rn = 1 then public._r2_num(e.data -> 'batches') end, public._r2_num(o.r -> 'qty'), e.status, null
      from public.entries e
      cross join lateral (select t.r, row_number() over (order by t.ord) as rn from jsonb_array_elements(public._p26_arr(e.data -> 'output')) with ordinality t(r, ord)
                           where public._r2_num(t.r -> 'qty') > 0 and nullif(t.r ->> 'item', '') is not null) o
      left join public.items i on i.code = o.r ->> 'item'
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
    union all
    select 'শিট / sheet', e.entry_date, e.location_id, null::uuid, public._r2_num(e.data -> 'batches'), null::numeric, e.status, null
      from public.entries e
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
       and public._r2_num(e.data -> 'batches') is not null
       and not exists (select 1 from jsonb_array_elements(public._p26_arr(e.data -> 'output')) t(r) where public._r2_num(t.r -> 'qty') > 0 and nullif(t.r ->> 'item', '') is not null)
    union all
    select 'চালান / dispatch', (t.sent_at at time zone 'Asia/Dhaka')::date, t.from_location_id, t.item_id, null, t.qty, t.status, t.to_location_id
      from public.stock_transfers t
     where t.from_location_id = any (locs) and (t.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2)
  select jsonb_build_object('source', u.source, 'day', u.day, 'location_bn', l.name_bn, 'product_code', i.code, 'product_bn', i.name_bn, 'unit', i.unit,
    'batches', u.batches, 'qty', u.qty, 'status', u.status, 'to_location_bn', lt.name_bn)
    from u join public.locations l on l.id = u.location_id left join public.items i on i.id = u.item_id left join public.locations lt on lt.id = u.to_loc;
$$;

-- ============================================================
-- F2 yield vs the approved 05-4 standard (per place and product), with what the production runs and the sheets made in the same period
--   standard = average good-per-input of the latest APPROVED 05-4 sheet up to the end of the period. production_runs post the recipe yield by definition, so they are shown as quantities, not as a yield test.
-- ============================================================
create or replace function public._r3q_f2_yield(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (
    select e.location_id, i.id as item_id, e.entry_date, e.serial, e.status, coalesce(public._p26_d(r ->> 'date'), e.entry_date) as bdate,
           public._r2_num(r -> 'input') as inp, public._r2_num(r -> 'good') as good, public._r2_num(r -> 'second') as sec, public._r2_num(r -> 'waste') as wst
      from public.entries e join public.items i on i.code = e.data ->> 'item'
      cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'b')) r
     where e.form_code = '05-4' and e.status in ('submitted', 'approved') and e.entry_date <= d2 and e.location_id = any (locs)),
  std as (
    select distinct on (location_id, item_id) location_id, item_id, y
      from (select location_id, item_id, entry_date, serial, avg(good / inp) as y from t where status = 'approved' and inp > 0 and good is not null group by 1, 2, 3, 4) s
     order by location_id, item_id, entry_date desc, serial desc),
  p as (
    select location_id, item_id, count(*) as n, avg(good / inp) as ty,
           avg(coalesce(sec, 0) / nullif(good + coalesce(sec, 0) + coalesce(wst, 0), 0) * 100) as sec_pct, avg(coalesce(wst, 0) / nullif(good + coalesce(sec, 0) + coalesce(wst, 0), 0) * 100) as wst_pct
      from t where inp > 0 and good is not null and bdate between d1 and d2 group by 1, 2),
  runs as (
    select r.location_id, r.item_id, sum(r.batches) as b, sum(r.yield_base) as q
      from public.production_runs r
     where r.status = 'done' and r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 group by 1, 2),
  sh as (
    select e.location_id, i.id as item_id, sum(public._base_qty(i.id, public._r2_num(o -> 'qty'), i.unit)) as q
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'output')) o join public.items i on i.code = o ->> 'item'
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) and public._r2_num(o -> 'qty') > 0
     group by 1, 2),
  k as (select location_id, item_id from p union select location_id, item_id from runs union select location_id, item_id from sh)
  select jsonb_build_object('location_bn', l.name_bn, 'item_code', i.code, 'item_bn', i.name_bn, 'std_yield', round(s.y, 4), 'tests_n', coalesce(p.n, 0), 'test_yield', round(p.ty, 4),
    'yield_diff_pct', case when s.y > 0 and p.ty is not null then round((p.ty - s.y) / s.y * 100, 2) end, 'second_pct', round(p.sec_pct, 2), 'waste_pct', round(p.wst_pct, 2),
    'run_batches', runs.b, 'run_qty', round(runs.q, 3), 'sheet_qty', round(sh.q, 3),
    'qty_gap', case when sh.q is not null and runs.q is not null then round(sh.q - runs.q, 3) end)
    from k join public.locations l on l.id = k.location_id join public.items i on i.id = k.item_id
    left join std s on s.location_id = k.location_id and s.item_id = k.item_id left join p on p.location_id = k.location_id and p.item_id = k.item_id
    left join runs on runs.location_id = k.location_id and runs.item_id = k.item_id left join sh on sh.location_id = k.location_id and sh.item_id = k.item_id;
$$;

-- ============================================================
-- F3 raw material really issued to production (stock_ledger issue_out, ref_type production) vs recipe lines x batches (_recipe_need). Quantities only.
-- ============================================================
create or replace function public._r3q_f3_raw_vs_recipe(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with runs as (
    select r.id, r.location_id, r.item_id as prod, r.recipe_id, r.batches
      from public.production_runs r
     where r.status = 'done' and r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  need as (
    select r.id as run_id, r.location_id, r.prod, r.batches, n.item_id as ing, n.need, n.waste_missing, n.base_unit, n.code, n.name_bn
      from runs r cross join lateral public._recipe_need(r.recipe_id, r.batches, r.location_id) n where n.kind = 'ingredient'),
  act as (
    select n.run_id, n.ing, -sum(l.qty_delta) as used
      from need n join public.stock_ledger l on l.ref_type = 'production' and l.ref_id = n.run_id::text and l.reason = 'issue_out' and l.item_id = n.ing
       and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
     group by n.run_id, n.ing),
  g as (
    select n.location_id, n.prod, n.ing, min(n.code) as code, min(n.name_bn) as name_bn, min(n.base_unit) as base_unit, count(*) as runs, sum(n.batches) as batches,
           sum(n.need) as expected, sum(a.used) as actual, count(*) filter (where n.waste_missing) as waste_missing
      from need n left join act a on a.run_id = n.run_id and a.ing = n.ing group by n.location_id, n.prod, n.ing)
  select jsonb_build_object('location_bn', l.name_bn, 'product_code', p.code, 'product_bn', p.name_bn, 'ingredient_code', g.code, 'ingredient_bn', g.name_bn, 'base_unit', g.base_unit,
    'runs', g.runs, 'batches', g.batches, 'expected', round(g.expected, 4), 'actual', round(g.actual, 4),
    'diff', case when g.actual is not null then round(g.actual - g.expected, 4) end,
    'diff_pct', case when g.actual is not null and g.expected > 0 then round((g.actual - g.expected) / g.expected * 100, 2) end, 'waste_missing', g.waste_missing)
    from g join public.locations l on l.id = g.location_id join public.items p on p.id = g.prod;
$$;

-- ============================================================
-- F4 machine breakdown (05-1 breakdown fields) and maintenance requests (08-1); open requests are listed whatever their date
-- ============================================================
create or replace function public._r3q_f4_breakdowns(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with m as (
    select e.id, e.location_id, e.entry_date, e.data, nullif(btrim(e.data ->> 'machine'), '') as machine,
           coalesce(public._p26_d(e.data ->> 'found_date'), e.entry_date) as fd,
           public._p26_d(e.data ->> 'done_date') as dd,
           case when e.data ->> 'found_time' ~ '^\d{1,2}:\d{2}' then (e.data ->> 'found_time')::time end as ft,
           case when e.data ->> 'done_time' ~ '^\d{1,2}:\d{2}' then (e.data ->> 'done_time')::time end as dt
      from public.entries e
     where e.form_code = '08-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)),
  r8 as (
    select m.*, (m.fd + coalesce(m.ft, time '00:00')) as fts, case when m.dd is not null then m.dd + coalesce(m.dt, time '00:00') end as dts,
           (select string_agg(pr.lbl, ', ') from (values ('p_stop', 'চলছে না / not running'), ('p_cool', 'ঠান্ডা হচ্ছে না / not cooling'), ('p_noise', 'শব্দ / noise'), ('p_leak', 'লিক / leak'),
              ('p_power', 'বিদ্যুৎ / electrical'), ('p_other', 'অন্য / other')) pr(k, lbl) where public._p26_b(m.data -> pr.k)) as problem
      from m),
  a as (
    select r8.*, (select count(*) from r8 o where o.location_id = r8.location_id and lower(o.machine) = lower(r8.machine) and o.fd between r8.fd - 365 and r8.fd)::int as repeat_n
      from r8 where r8.fd <= d2 and (r8.fd >= d1 or r8.dd is null)),
  s as (
    select '08-1'::text as source, a.fd as day, a.location_id, a.machine, a.problem,
           case when a.dd is null then 'খোলা / open' else 'শেষ / closed' end as status, a.ft::text as ftime,
           case when a.dts is not null and a.dts >= a.fts then round(extract(epoch from (a.dts - a.fts))::numeric / 3600, 1) end as downtime_h,
           public._r2_num(a.data -> 'est_cost') as est_cost, public._r2_num(a.data -> 'actual_cost') as actual_cost, a.repeat_n, null::text as ref
      from a
    union all
    select '05-1', e.entry_date, e.location_id, nullif(btrim(e.data ->> 'bd_machine'), ''), null, 'শিটে লেখা / on sheet', nullif(e.data ->> 'bd_time', ''), null, null, null, null, nullif(btrim(e.data ->> 'bd_request'), '')
      from public.entries e
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.data ->> 'breakdown' = 'yes' and e.entry_date between d1 and d2 and e.location_id = any (locs))
  select jsonb_build_object('source', s.source, 'day', s.day, 'location_bn', l.name_bn, 'machine', coalesce(s.machine, '-'), 'problem', s.problem, 'status', s.status, 'found_time', s.ftime,
    'downtime_h', s.downtime_h, 'est_cost', s.est_cost, 'actual_cost', s.actual_cost, 'repeat_n', s.repeat_n, 'request_ref', s.ref)
    from s join public.locations l on l.id = s.location_id;
$$;

-- ============================================================
-- M2 marketing spend (18-1 lines, dated by the line date, else the sheet date) and sales (status done) side by side per day and place. No ratio, no causal claim.
-- ============================================================
create or replace function public._r3q_m2_marketing_vs_sales(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ml as (
    select e.location_id, coalesce(public._p26_d(ln ->> 'date'), e.entry_date) as day,
           public._r2_num(ln -> 'amt') as amt, public._r2_num(ln -> 'nonpay') as nonpay,
           case when ln ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(ln ->> 'head'), ''), '-') end as head
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'lines')) ln
     where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)),
  mh as (
    select ml.location_id, ml.day, ml.head, sum(coalesce(ml.amt, 0)) as amt, sum(coalesce(ml.nonpay, 0)) as nonpay, count(*) as n
      from ml where ml.day between d1 and d2 and (ml.amt is not null or ml.nonpay is not null) group by 1, 2, 3),
  mk as (
    select h.location_id, h.day, sum(h.amt) as spend, sum(h.nonpay) as nonpay, sum(h.n) as n,
           string_agg(coalesce(o.label_bn, h.head) || ' ' || to_char(h.amt, 'FM999999999990.##'), ', ' order by h.amt desc) as heads
      from mh h left join public.option_lists o on o.list_code = 'marketing_heads' and o.value_code = h.head group by 1, 2),
  sl as (
    select s.location_id, s.sale_date as day, sum(s.total) as total, count(*) as n
      from public.sales s where s.status = 'done' and s.location_id = any (locs) and s.sale_date between d1 and d2 group by 1, 2)
  select jsonb_build_object('day', coalesce(mk.day, sl.day), 'location_bn', l.name_bn, 'spend', round(coalesce(mk.spend, 0), 2), 'nonpay_value', round(coalesce(mk.nonpay, 0), 2),
    'mkt_lines', coalesce(mk.n, 0), 'heads', mk.heads, 'sales_total', round(coalesce(sl.total, 0), 2), 'sales_n', coalesce(sl.n, 0))
    from mk full join sl on sl.location_id = mk.location_id and sl.day = mk.day
    join public.locations l on l.id = coalesce(mk.location_id, sl.location_id);
$$;

-- ============================================================
-- Q1 fridge temperature log: 05-1 (fridges, fridges2 rows 1-2) and 14-1 (fridges rows 1-3, t2_1 / t2_2 second reading on busy days).
--   limits from location_settings fridgeN_min / fridgeN_max; no limit set = out_n null (never guessed).
-- ============================================================
create or replace function public._r3q_q1_fridge_temp(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with rd as (
    select e.location_id, e.entry_date as day, e.serial, e.form_code as form, f.n,
           public._r2_num(case when jsonb_typeof(e.data -> 'fridges') = 'array' then e.data -> 'fridges' -> (f.n - 1) -> 'temp' end) as r1,
           case when e.form_code = '05-1' then public._r2_num(case when jsonb_typeof(e.data -> 'fridges2') = 'array' then e.data -> 'fridges2' -> (f.n - 1) -> 'temp' end)
                when f.n = 1 then public._r2_num(e.data -> 't2_1') when f.n = 2 then public._r2_num(e.data -> 't2_2') end as r2
      from public.entries e
      cross join lateral generate_series(1, case when e.form_code = '05-1' then 2 else 3 end) f(n)
     where e.form_code in ('05-1', '14-1') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  x as (
    select rd.*, (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_min') as lo,
           (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_max') as hi,
           (select ls.value #>> '{}' from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_name') as fname
      from rd where rd.r1 is not null or rd.r2 is not null)
  select jsonb_build_object('day', x.day, 'location_bn', l.name_bn, 'form', x.form, 'fridge', x.n, 'fridge_name', x.fname, 'reading1', x.r1, 'reading2', x.r2, 'min_c', x.lo, 'max_c', x.hi,
    'out_n', case when x.lo is null or x.hi is null then null
                  else (case when x.r1 is not null and (x.r1 < x.lo or x.r1 > x.hi) then 1 else 0 end) + (case when x.r2 is not null and (x.r2 < x.lo or x.r2 > x.hi) then 1 else 0 end) end)
    from x join public.locations l on l.id = x.location_id;
$$;

-- ============================================================
-- Q2 hygiene / expiry / checklist compliance per sheet: 14-1 (16 closing steps c1..c16, expired goods shown but not removed), 05-1 (hygiene, pots, equipment, cleaning, shut-down ticks)
-- ============================================================
create or replace function public._r3q_q2_hygiene(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with e0 as (
    select e.id, e.location_id, e.entry_date, e.form_code, e.data,
           case when e.form_code = '14-1' then array['c1','c2','c3','c4','c5','c6','c7','c8','c9','c10','c11','c12','c13','c14','c15','c16']
                else array['pots_done','hygiene_done','machines_done','clean_done','machines_off','gas_off','power_off','fire_safe'] end as ks
      from public.entries e
     where e.form_code in ('14-1', '05-1') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  c as (
    select e0.*, cardinality(e0.ks) as total, (select count(*) from unnest(e0.ks) k where public._p26_b(e0.data -> k))::int as done,
           (select string_agg(k, ', ' order by ordinality) from unnest(e0.ks) with ordinality u(k, ordinality) where not public._p26_b(e0.data -> k)) as missed_list
      from e0)
  select jsonb_build_object('day', c.entry_date, 'location_bn', l.name_bn, 'form', c.form_code, 'checks', c.total, 'done', c.done, 'missed', c.total - c.done,
    'compliance_pct', round(c.done * 100.0 / c.total, 1),
    'expired_shown', case when c.form_code = '14-1' then (case when c.data ->> 'expired_shown' = 'yes' then 1 else 0 end) end,
    'expired_not_removed', case when c.form_code = '14-1' then (case when c.data ->> 'expired_shown' = 'yes' and not public._p26_b(c.data -> 'expired_removed') then 1 else 0 end) end,
    'missed_list', c.missed_list)
    from c join public.locations l on l.id = c.location_id;
$$;

-- ============================================================
-- Q3 complaints (20-3, one count per ticked cause) and sale returns (reason_code, per returned line) grouped by cause, product and place
-- ============================================================
create or replace function public._r3q_q3_complaints(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  lbl(k, t) as (values ('taste', 'স্বাদ / taste'), ('smell', 'গন্ধ, নষ্ট / smell, spoiled'), ('broken', 'ভাঙা / broken'), ('short', 'পরিমাণে কম / short quantity'), ('wrong', 'ভুল পণ্য / wrong goods'),
                       ('late', 'দেরি / late'), ('staff', 'কর্মীর আচরণ / staff behaviour'), ('sick', 'খেয়ে অসুস্থ / fell ill'), ('other', 'অন্য / other'), ('none', 'কারণ টিক নেই / no cause ticked')),
  c1 as (
    select e.location_id, i.id as item_id, public._r2_num(e.data -> 'qty') as qty, public._r2_num(e.data -> 'refund_amt') as refund,
           nullif(btrim(e.check_data ->> 'root_cause'), '') is null as no_root, not public._p26_b(e.check_data -> 'resolved') as unresolved, public._p26_b(e.data -> 'c_sick') as sick,
           coalesce((select array_agg(k) from unnest(array['taste','smell','broken','short','wrong','late','staff','sick','other']) k where public._p26_b(e.data -> ('c_' || k))), array['none']) as ks
      from public.entries e left join public.items i on i.code = e.data ->> 'item'
     where e.form_code = '20-3' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  a as (
    select '20-3 অভিযোগ / complaint'::text as source, k as cause_code, c1.location_id, c1.item_id, count(*) as n, sum(c1.qty) as qty, sum(c1.refund) as refund,
           count(*) filter (where c1.unresolved) as unresolved, count(*) filter (where c1.sick) as sick, count(*) filter (where c1.no_root) as no_root
      from c1, unnest(c1.ks) k group by k, c1.location_id, c1.item_id),
  b as (
    select 'রিটার্ন / sale return'::text as source, sr.reason_code as cause_code, sr.location_id, nullif(x ->> 'item_id', '')::uuid as item_id, count(*) as n,
           sum(public._r2_num(x -> 'qty')) as qty, sum(public._r2_num(x -> 'amount')) as refund, null::bigint as unresolved, null::bigint as sick, null::bigint as no_root
      from public.sale_returns sr cross join lateral jsonb_array_elements(public._p26_arr(sr.lines)) x
     where sr.status = 'done' and sr.location_id = any (locs) and (sr.created_at at time zone 'Asia/Dhaka')::date between d1 and d2
       and (x ->> 'item_id') ~ '^[0-9a-f-]{36}$'
     group by sr.reason_code, sr.location_id, nullif(x ->> 'item_id', '')::uuid),
  u as (select * from a union all select * from b)
  select jsonb_build_object('source', u.source, 'cause', case when u.source like '20-3%' then coalesce(lbl.t, u.cause_code) else coalesce(o.label_bn, u.cause_code) end,
    'location_bn', l.name_bn, 'product_code', i.code, 'product_bn', coalesce(i.name_bn, '-'), 'n', u.n, 'qty', round(u.qty, 3), 'refund_amt', round(u.refund, 2),
    'unresolved', u.unresolved, 'sick', u.sick, 'no_root_cause', u.no_root)
    from u join public.locations l on l.id = u.location_id left join public.items i on i.id = u.item_id cross join cat
    left join lbl on u.source like '20-3%' and lbl.k = u.cause_code
    left join public.option_lists o on u.source not like '20-3%' and o.list_code = 'return_reasons' and o.value_code = u.cause_code
   where cat.c is null or i.category = any (cat.c);
$$;

-- ============================================================
-- the registry rows
-- ============================================================
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('p2_rate_trend', 'P2', 'purchase', 'ক্রয়-দর ধারা (আইটেম ও সাপ্লায়ার)', 'Purchase rate trend per item and supplier', 'ক্রয়-দর ধারা (Item ও Supplier)',
  '[["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["supplier","সাপ্লায়ার","Supplier","text"],["n","বার","Times","int"],["qty","পরিমাণ","Quantity","num"],["first_rate","প্রথম দর","First rate","money"],["last_rate","শেষ দর","Last rate","money"],["min_rate","সর্বনিম্ন","Lowest","money"],["max_rate","সর্বোচ্চ","Highest","money"],["avg_rate","গড় দর","Average rate","money"],["change_pct","বদল %","Change %","pct"],["last_date","শেষ তারিখ","Last date","date"]]'::jsonb,
  '{}', 'change_pct', 'desc', array['locations','categories'], false, true, false, 2601),
 ('p4_supplier_score', 'P4', 'purchase', 'সাপ্লায়ার স্কোরকার্ড', 'Supplier scorecard', 'Supplier স্কোরকার্ড',
  '[["supplier","সাপ্লায়ার","Supplier","text"],["grns","গ্রহণ রসিদ","GRNs","int"],["lines","লাইন","Lines","int"],["short_lines","কম পাওয়া লাইন","Short lines","int"],["rejected","ফেরত লাইন","Returned lines","int"],["held","আটক লাইন","Held lines","int"],["reduced","দর কমানো লাইন","Reduced-rate lines","int"],["bills_checked","যাচাই বিল","Bills checked","int"],["short_claims","ঘাটতির দাবি","Shortage claims","int"],["return_claims","ফেরতের দাবি","Return claims","int"],["pos","পারচেজ অর্ডার","POs","int"],["late_pos","দেরিতে আসা PO","Late POs","int"],["overdue_open","মেয়াদ পেরোনো খোলা PO","Overdue open POs","int"],["rate_change_pct","গড় দর বদল %","Avg rate change %","pct"],["rate_items","তুলনার আইটেম","Items compared","int"]]'::jsonb,
  array['grns','lines','short_lines','rejected','held','reduced','bills_checked','short_claims','return_claims','pos','late_pos','overdue_open'], 'rejected', 'desc', array['locations'], false, true, false, 2602),
 ('p5_po_match', 'P5', 'purchase', 'PO-GRN-বিল মিল ও খোলা PO', 'PO - GRN - bill match and open POs', 'PO-GRN-Bill মিল ও খোলা PO',
  '[["po_no","PO নং","PO no.","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["supplier","সাপ্লায়ার","Supplier","text"],["delivery_date","ডেলিভারির তারিখ","Delivery date","date"],["po_lines","PO লাইন","PO lines","int"],["lines_open","বাকি লাইন","Lines still open","int"],["po_total","PO মোট","PO total","money"],["grn_n","GRN সংখ্যা","GRNs","int"],["grn_value","GRN মূল্য","GRN value","money"],["bill_n","বিল","Bills","int"],["bill_amount","বিলের অঙ্ক","Bill amount","money"],["bill_diff","বিল − GRN","Bill − GRN","money"],["days_late","দেরি (দিন)","Days late","int"],["status","অবস্থা","Status","text"]]'::jsonb,
  '{}', 'days_late', 'desc', array['locations'], false, true, false, 2603),
 ('p6_purchase_budget', 'P6', 'purchase', 'ক্রয় বনাম বাজেট ও পূর্বাভাস', 'Purchases vs budget and outlook', 'ক্রয় বনাম Budget ও Outlook',
  '[["location_bn","লোকেশন","Location","text"],["day","শিটের তারিখ","Sheet date","date"],["cash_total","মোট হাতে","Total cash","money"],["receivable","প্রাপ্য (৭ দিন)","Receivable (7d)","money"],["payable","দেয় (৭ দিন)","Payable (7d)","money"],["min_cash","ন্যূনতম নগদ","Minimum cash","money"],["budget","পারচেজ বাজেট","Purchase budget","money"],["bills_7d","ক্রয় বিল (৭ দিন)","Purchase bills (7d)","money"],["grn_7d","GRN মূল্য (৭ দিন)","GRN value (7d)","money"],["spent","খরচ","Spent","money"],["used_pct","ব্যবহার %","Used %","pct"],["budget_left","বাজেটের বাকি","Budget left","money"],["outlook_low","পূর্বাভাস কম","Outlook low","money"],["outlook_high","পূর্বাভাস বেশি","Outlook high","money"]]'::jsonb,
  '{}', 'day', 'desc', array['locations'], false, true, false, 2604),
 ('k2_count_variance', 'K2', 'stock', 'স্টক গণনার পার্থক্য', 'Stock count variance', 'Stock গণনার পার্থক্য',
  '[["location_bn","লোকেশন","Location","text"],["counter","গণনাকারী","Counter","text"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["counts","গণনা","Counts","int"],["off_n","পার্থক্য হয়েছে","Times off","int"],["short_n","কম","Short","int"],["over_n","বেশি","Over","int"],["net_var","নিট পার্থক্য","Net variance","num"],["abs_var","মোট পার্থক্য (চিহ্ন ছাড়া)","Absolute variance","num"],["off_pct","পার্থক্য %","Off %","pct"],["last_date","শেষ তারিখ","Last date","date"],["last_reason","শেষ কারণ","Last reason","text"]]'::jsonb,
  array['counts','off_n','short_n','over_n'], 'off_n', 'desc', array['locations','categories'], false, false, false, 2605),
 ('f1_production', 'F1', 'stock', 'দৈনিক উৎপাদন ও চালান', 'Production and dispatch', 'দৈনিক উৎপাদন ও Dispatch',
  '[["source","উৎস","Source","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["product_code","কোড","Code","text"],["product_bn","পণ্য","Product","text"],["unit","একক","Unit","text"],["batches","ব্যাচ","Batches","num"],["qty","পরিমাণ","Quantity","num"],["status","অবস্থা","Status","text"],["to_location_bn","গন্তব্য","To","text"]]'::jsonb,
  '{}', 'day', 'desc', array['locations'], false, false, false, 2606),
 ('f2_yield', 'F2', 'stock', 'ফলন বনাম স্ট্যান্ডার্ড', 'Yield vs standard', 'ফলন বনাম Standard',
  '[["location_bn","লোকেশন","Location","text"],["item_code","কোড","Code","text"],["item_bn","পণ্য","Product","text"],["std_yield","স্ট্যান্ডার্ড ফলন","Standard yield","num"],["tests_n","মাপ","Measurements","int"],["test_yield","মাপা ফলন","Measured yield","num"],["yield_diff_pct","পার্থক্য %","Difference %","pct"],["second_pct","২য় গ্রেড %","2nd grade %","pct"],["waste_pct","নষ্ট %","Waste %","pct"],["run_batches","রানের ব্যাচ","Run batches","num"],["run_qty","রানের পরিমাণ","Run quantity","num"],["sheet_qty","শিটের পরিমাণ","Sheet quantity","num"],["qty_gap","শিট − রান","Sheet − run","num"]]'::jsonb,
  '{}', 'yield_diff_pct', 'asc', array['locations'], false, false, false, 2607),
 ('f3_raw_vs_recipe', 'F3', 'stock', 'কাঁচামাল ব্যবহার বনাম রেসিপি', 'Raw material use vs recipe', 'কাঁচামাল ব্যবহার বনাম Recipe',
  '[["location_bn","লোকেশন","Location","text"],["product_code","পণ্যের কোড","Product code","text"],["product_bn","পণ্য","Product","text"],["ingredient_code","উপকরণের কোড","Ingredient code","text"],["ingredient_bn","উপকরণ","Ingredient","text"],["base_unit","একক","Unit","text"],["runs","রান","Runs","int"],["batches","ব্যাচ","Batches","num"],["expected","রেসিপি অনুযায়ী","Per recipe","num"],["actual","আসলে ইস্যু","Actually issued","num"],["diff","পার্থক্য","Difference","num"],["diff_pct","পার্থক্য %","Difference %","pct"],["waste_missing","অপচয়-% নেই","No waste % set","int"]]'::jsonb,
  '{}', 'diff_pct', 'desc', array['locations'], false, false, false, 2608),
 ('f4_breakdowns', 'F4', 'stock', 'মেশিন বন্ধ ও মেইনটেন্যান্স', 'Machine breakdowns and maintenance', 'Machine বন্ধ ও Maintenance',
  '[["source","উৎস","Source","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["machine","যন্ত্র","Machine","text"],["problem","সমস্যা","Problem","text"],["status","অবস্থা","Status","text"],["found_time","সময়","Time","text"],["downtime_h","বন্ধ (ঘণ্টা)","Down (hours)","num"],["est_cost","আনুমানিক খরচ","Estimated cost","money"],["actual_cost","প্রকৃত খরচ","Actual cost","money"],["repeat_n","এক বছরে বার","Times in a year","int"],["request_ref","অনুরোধ নং","Request no.","text"]]'::jsonb,
  array['downtime_h','est_cost','actual_cost'], 'day', 'desc', array['locations'], false, false, false, 2609),
 ('m2_marketing_vs_sales', 'M2', 'marketing', 'মার্কেটিং খরচ ও বিক্রি (একই দিন)', 'Marketing spend and sales, same days', 'Marketing খরচ ও বিক্রি (একই দিন)',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["spend","মার্কেটিং খরচ","Marketing spend","money"],["nonpay_value","টাকা ছাড়া মূল্য","Non-cash value","money"],["mkt_lines","খরচের লাইন","Expense lines","int"],["heads","খাত","Heads","text"],["sales_total","বিক্রি","Sales","money"],["sales_n","বিক্রির সংখ্যা","Sales count","int"]]'::jsonb,
  array['spend','nonpay_value','mkt_lines','sales_total','sales_n'], 'day', 'desc', array['locations'], false, false, false, 2610),
 ('q1_fridge_temp', 'Q1', 'quality', 'ফ্রিজ তাপমাত্রা লগ', 'Fridge temperature log', 'ফ্রিজ Temperature লগ',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["fridge","ফ্রিজ নং","Fridge no.","int"],["fridge_name","ফ্রিজের নাম","Fridge name","text"],["reading1","প্রথম পাঠ °C","Reading 1 °C","num"],["reading2","দ্বিতীয় পাঠ °C","Reading 2 °C","num"],["min_c","সর্বনিম্ন সীমা","Lower limit","num"],["max_c","সর্বোচ্চ সীমা","Upper limit","num"],["out_n","সীমার বাইরে (পাঠ)","Readings out of range","int"]]'::jsonb,
  array['out_n'], 'out_n', 'desc', array['locations'], false, false, false, 2611),
 ('q2_hygiene', 'Q2', 'quality', 'হাইজিন, মেয়াদ ও চেকলিস্ট পালন', 'Hygiene, expiry and checklist compliance', 'Hygiene, মেয়াদ ও Checklist পালন',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["checks","ধাপ","Steps","int"],["done","সম্পন্ন","Done","int"],["missed","বাদ","Missed","int"],["compliance_pct","পালন %","Compliance %","pct"],["expired_shown","মেয়াদ-শেষ ডিসপ্লেতে","Expired shown","int"],["expired_not_removed","না সরানো","Not removed","int"],["missed_list","বাদ পড়া ধাপ","Missed steps","text"]]'::jsonb,
  array['checks','done','missed','expired_shown','expired_not_removed'], 'compliance_pct', 'asc', array['locations'], false, false, false, 2612),
 ('q3_complaints', 'Q3', 'quality', 'অভিযোগ ও রিটার্নের কারণ', 'Complaints and return causes', 'অভিযোগ ও Return-এর কারণ',
  '[["source","উৎস","Source","text"],["cause","কারণ","Cause","text"],["location_bn","লোকেশন","Location","text"],["product_code","কোড","Code","text"],["product_bn","পণ্য","Product","text"],["n","সংখ্যা","Count","int"],["qty","পরিমাণ","Quantity","num"],["refund_amt","ফেরত/মূল্য","Refund / value","money"],["unresolved","অমীমাংসিত","Unresolved","int"],["sick","অসুস্থ","Fell ill","int"],["no_root_cause","মূল কারণ নেই","No root cause","int"]]'::jsonb,
  array['n','unresolved','sick','no_root_cause'], 'n', 'desc', array['locations','categories'], false, false, false, 2613)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

revoke all on function public._p26_d(text), public._p26_b(jsonb), public._p26_arr(jsonb), public._p26_rates(date, date, int[]), public._p26_po(date, date, int[]), public._p26_outlook(int) from public, anon, authenticated;
select public._r3_lockdown();
notify pgrst, 'reload schema';
-- ============================================================
-- PHASE 27 (group profit, engine 3 reports): L1 L2 L3 L4 L5 T3 T4
--   l1_pnl            profit & loss by month and shop            (cost, owner only)
--   l2_margin         margin by item and by category             (cost)
--   l3_shop_pnl       shop P&L side by side                      (cost, owner only)
--   l4_owner_sheet    owner's 01-2 sheet vs computed system      (cost, owner only)
--   l5_breakeven      break-even and cost coverage               (cost)
--   t3_payroll        payroll & advances (02-2, 02-3)            (owner only)
--   t4_staff_cost_ratio  salary / sales % by shop                (owner only)
-- Needs phase24 (report_defs3). Additive, idempotent. Costs only for cost-right holders; salary only for the owner.
-- Sources: sales (status done) net of sale_returns (rule reports_net_of_returns, default ON) exactly like biz_daily (phase23);
--   COGS only on lines whose item has a cost (item_costs, count_in_business) - the rest is shown as "uncosted %", never guessed;
--   expenses = 10-2 lines (as expense_by_head); salary = 02-2 pay lines; fixed = location setting fixed_cost_month (prorated by days of the month inside the period).
-- ============================================================

-- shared P&L builder: one row per month x shop. Private (no grants), called only from the _r3q_ functions (definer).
create or replace function public._p27_pl(d1 date, d2 date, locs int[])
returns table (o_m date, o_loc int, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
language sql stable security definer set search_path = public as $$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ln as (
    select s.m, s.location_id, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end as iid
    from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (
    select ln.m, ln.location_id, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
    from ln left join cst c on c.item_id = ln.iid group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  rl as (
    select rr.m, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty
    from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
    left join cst c on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rg as (select m, location_id, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1, 2),
  ex as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id, sum(public._r2_num(ln -> 'amount')) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
    where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  sa as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0) - coalesce(g.rcr, 0), 2), round(coalesce(a.cg, 0) - coalesce(g.rcg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join rg g on g.m = k.m and g.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$$;
revoke all on function public._p27_pl(date, date, int[]) from public, anon, authenticated;

-- ---------- L1 profit & loss by month and shop ----------
create or replace function public._r3q_l1_pnl(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'month', to_char(p.o_m, 'YYYY-MM'), 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'sales', round(p.o_gross, 2), 'returns', round(p.o_ret, 2), 'net_sales', round(p.o_net, 2),
    'cogs', round(p.o_cogs, 2),
    'uncosted_pct', case when p.o_net > 0 then round(100 * greatest(p.o_net - p.o_costed, 0) / p.o_net, 2) end,
    'expenses', round(p.o_exp, 2), 'salary', round(p.o_sal, 2), 'fixed', p.o_fixed,
    'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),
    'gaps', nullif(concat_ws(', ', case when p.o_exp is null then 'expenses' end, case when p.o_sal is null then 'salary' end, case when p.o_fixed is null then 'fixed' end, case when p.o_net > 0 and p.o_costed < p.o_net then 'cogs(uncosted)' end), ''))
  from public._p27_pl(d1, d2, locs) p join public.locations l on l.id = p.o_loc;
$$;

-- ---------- L3 shop P&L comparison ----------
create or replace function public._r3q_l3_shop_pnl(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), ''))
  from a join public.locations l on l.id = a.o_loc;
$$;

-- ---------- L2 margin by item and by category ----------
create or replace function public._r3q_l2_margin(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cats as (select public.rpt_arr_text(flt -> 'categories') as c),
  net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.total, x.subtotal, x.lines from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  sl as (
    select 1 as sg, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f, e as le from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  rl as (
    select -1 as sg, 1::numeric as f, e as le from public.sale_returns r, net_on, jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
    where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  u as (select sg, f, le from sl union all select sg, f, le from rl),
  p as (
    select sg * f as sf, sg,
           case when le->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (le->>'amount')::numeric end as amt,
           case when le->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (le->>'qty')::numeric end as qty,
           case when le->>'item_id' ~ '^[0-9a-f-]{36}$' then (le->>'item_id')::uuid end as iid
    from u),
  j as (
    select i.id as item_id, coalesce(i.code, '-') as icode, coalesce(i.name_bn, '(item not linked)') as nbn, coalesce(i.name_en, i.name_bn, '(item not linked)') as nen,
           coalesce(nullif(btrim(i.category), ''), '-') as cat, p.sf, p.sg, p.amt, p.qty, c.cost_price
    from p left join public.items i on i.id = p.iid left join cst c on c.item_id = p.iid),
  jf as (select j.* from j, cats where cats.c is null or j.cat = any (cats.c)),
  ia as (
    select item_id, icode, nbn, nen, cat, sum(sf * amt) as rev, sum(sg * qty) as qty,
           sum(sf * amt) filter (where cost_price is not null) as crev, sum(sg * qty * cost_price) filter (where cost_price is not null) as cg
    from jf group by item_id, icode, nbn, nen, cat),
  ca as (select cat, sum(rev) as rev, sum(crev) as crev, sum(cg) as cg from ia group by cat)
  select jsonb_build_object('level', 'item', 'category', ia.cat, 'item_code', ia.icode, 'item_name', ia.nbn, 'item_name_en', ia.nen,
    'qty', round(ia.qty, 3), 'revenue', round(ia.rev, 2), 'cogs', round(ia.cg, 2),
    'margin', case when ia.crev is not null then round(ia.crev - ia.cg, 2) end,
    'margin_pct', case when ia.crev > 0 then round(100 * (ia.crev - ia.cg) / ia.crev, 2) end,
    'uncosted_pct', case when ia.rev > 0 then round(100 * greatest(ia.rev - coalesce(ia.crev, 0), 0) / ia.rev, 2) end)
  from ia
  union all
  select jsonb_build_object('level', 'category', 'category', ca.cat, 'item_code', null, 'item_name', null, 'item_name_en', null,
    'qty', null, 'revenue', round(ca.rev, 2), 'cogs', round(ca.cg, 2),
    'margin', case when ca.crev is not null then round(ca.crev - ca.cg, 2) end,
    'margin_pct', case when ca.crev > 0 then round(100 * (ca.crev - ca.cg) / ca.crev, 2) end,
    'uncosted_pct', case when ca.rev > 0 then round(100 * greatest(ca.rev - coalesce(ca.crev, 0), 0) / ca.rev, 2) end)
  from ca;
$$;

-- ---------- L4 owner's monthly sheet (01-2) vs system ----------
create or replace function public._r3q_l4_owner_sheet(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with sh as (
    select e.id, e.location_id, e.entry_date, e.data ->> 'scope' as scope, btrim(e.data ->> 'month') as mon,
           public._r2_num(e.data -> 'sales') as s_sales,
           case when public._r2_num(e.data -> 'open_stock') is not null and public._r2_num(e.data -> 'purchases') is not null and public._r2_num(e.data -> 'close_stock') is not null
                then public._r2_num(e.data -> 'open_stock') + public._r2_num(e.data -> 'purchases') - public._r2_num(e.data -> 'close_stock') end as s_cogs,
           (select sum(public._r2_num(kv.value)) from jsonb_each(e.data) kv where kv.key like 'x\_%') as s_exp,
           public._r2_num(e.data -> 'salary') as s_sal, public._r2_num(e.data -> 'bank_charges') as s_bank
    from public.entries e
    where e.form_code = '01-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  mm as (
    select sh.*, case when sh.mon ~ '^[0-9]{4}-([1-9]|0[1-9]|1[0-2])$' then to_date(sh.mon || '-01', 'YYYY-MM-DD') end as ms from sh),
  sy as (
    select mm.id, case when mm.ms is null or mm.scope not in ('all', 'loc') then false else true end as ok,
           (select array[sum(p.o_net), sum(p.o_costed), sum(p.o_cogs), sum(p.o_exp), sum(p.o_sal)] from public._p27_pl(mm.ms, (mm.ms + interval '1 month')::date - 1,
              case when mm.scope = 'all' then locs else array[mm.location_id] end) p) as v
    from mm)
  select jsonb_build_object('month', mm.mon, 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en, 'scope', mm.scope,
    'sheet_sales', mm.s_sales, 'sys_sales', case when sy.ok then round(sy.v[1], 2) end,
    'diff_sales', case when sy.ok and mm.s_sales is not null then round(mm.s_sales - sy.v[1], 2) end,
    'sheet_cogs', mm.s_cogs, 'sys_cogs', case when sy.ok then round(sy.v[3], 2) end,
    'sys_uncosted_pct', case when sy.ok and sy.v[1] > 0 then round(100 * greatest(sy.v[1] - sy.v[2], 0) / sy.v[1], 2) end,
    'sheet_expenses', mm.s_exp, 'sys_expenses', case when sy.ok then round(sy.v[4], 2) end,
    'diff_expenses', case when sy.ok and mm.s_exp is not null and sy.v[4] is not null then round(mm.s_exp - sy.v[4], 2) end,
    'sheet_salary', mm.s_sal, 'sys_salary', case when sy.ok then round(sy.v[5], 2) end,
    'diff_salary', case when sy.ok and mm.s_sal is not null and sy.v[5] is not null then round(mm.s_sal - sy.v[5], 2) end,
    'sheet_net', case when mm.s_sales is not null and mm.s_cogs is not null then round(mm.s_sales - mm.s_cogs - coalesce(mm.s_exp, 0) - coalesce(mm.s_sal, 0) - coalesce(mm.s_bank, 0), 2) end,
    'sys_net', case when sy.ok then round(sy.v[1] - sy.v[3] - coalesce(sy.v[4], 0) - coalesce(sy.v[5], 0), 2) end)
  from mm join sy on sy.id = mm.id join public.locations l on l.id = mm.location_id;
$$;

-- ---------- L5 break-even and cost coverage ----------
create or replace function public._r3q_l5_breakeven(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  b as (select a.*, case when a.costed > 0 and a.costed - a.cogs > 0 then (a.costed - a.cogs) / a.costed end as gm,
          (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = a.o_loc and ls.key = 'fixed_cost_month') as fm from a)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(b.net, 2),
    'uncosted_pct', case when b.net > 0 then round(100 * greatest(b.net - b.costed, 0) / b.net, 2) end,
    'gm_pct', case when b.gm is not null then round(100 * b.gm, 2) end,
    'fixed', b.fx,
    'be_sales', case when b.gm is not null and b.fx is not null then round(b.fx / b.gm, 2) end,
    'gap', case when b.gm is not null and b.fx is not null then round(b.net - b.fx / b.gm, 2) end,
    'coverage_pct', case when b.gm is not null and b.fx > 0 then round(100 * b.net / (b.fx / b.gm), 2) end,
    'fixed_month', b.fm,
    'be_month', case when b.gm is not null and b.fm is not null then round(b.fm / b.gm, 2) end)
  from b join public.locations l on l.id = b.o_loc;
$$;

-- ---------- T3 payroll & advances (02-2 salary sheets, 02-3 advance register) ----------
create or replace function public._r3q_t3_payroll(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with pay as (
    select e.id, e.location_id, btrim(r ->> 'name') as nm,
           coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0) as gross,
           coalesce(public._r2_num(r -> 'adv_ded'), 0) as adv_ded, coalesce(public._r2_num(r -> 'other_ded'), 0) as oth_ded
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
      and btrim(coalesce(r ->> 'name', '')) <> ''),
  pg as (select location_id, lower(nm) as k, min(nm) as nm, count(distinct id) as sheets, sum(gross) as gross, sum(adv_ded) as adv_ded, sum(oth_ded) as oth_ded from pay group by 1, 2),
  av as (
    select e.location_id, lower(btrim(e.data ->> 'staff')) as k, min(btrim(e.data ->> 'staff')) as nm,
           sum(public._r2_num(r -> 'amount')) as given, sum(public._r2_num(r -> 'ded_now')) as ded_now
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) r
    where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (locs) and btrim(coalesce(e.data ->> 'staff', '')) <> ''
      and coalesce(case when r ->> 'date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (r ->> 'date')::date end, e.entry_date) between d1 and d2
    group by 1, 2),
  ob as (
    select distinct on (e.location_id, lower(btrim(e.data ->> 'staff'))) e.location_id, lower(btrim(e.data ->> 'staff')) as k, btrim(e.data ->> 'staff') as nm,
           (select sum(public._r2_num(r -> 'balance')) from jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) r) as outstanding
    from public.entries e
    where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (locs) and btrim(coalesce(e.data ->> 'staff', '')) <> '' and e.entry_date <= d2
    order by e.location_id, lower(btrim(e.data ->> 'staff')), e.entry_date desc, e.created_at desc),
  ks as (select location_id, k from pg union select location_id, k from av union select location_id, k from ob)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'person', coalesce(pg.nm, av.nm, ob.nm), 'sheets', pg.sheets,
    'gross_pay', round(pg.gross, 2), 'adv_deducted', round(pg.adv_ded, 2), 'other_deducted', round(pg.oth_ded, 2),
    'net_pay', round(pg.gross - pg.adv_ded - pg.oth_ded, 2),
    'adv_given', round(av.given, 2), 'adv_register_deduction', round(av.ded_now, 2), 'adv_outstanding', round(ob.outstanding, 2))
  from ks join public.locations l on l.id = ks.location_id
  left join pg on pg.location_id = ks.location_id and pg.k = ks.k
  left join av on av.location_id = ks.location_id and av.k = ks.k
  left join ob on ob.location_id = ks.location_id and ob.k = ks.k;
$$;

-- ---------- T4 staff cost / sales % by shop ----------
create or replace function public._r3q_t4_staff_cost_ratio(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_sal) sal from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'salary', round(a.sal, 2),
    'salary_pct', case when a.net > 0 and a.sal is not null then round(100 * a.sal / a.net, 2) end)
  from a join public.locations l on l.id = a.o_loc;
$$;

-- ---------- registry ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('l1_pnl', 'L1', 'profit', 'লাভ-ক্ষতি (মাস ও দোকান অনুযায়ী)', 'Profit & loss by month and shop', 'লাভ-ক্ষতি (P&L)',
  '[["month","মাস","Month","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],
    ["sales","বিক্রি (সম্পন্ন বিক্রি)","Sales (done sales)","money"],["returns","রিটার্ন (বিক্রি-রিটার্ন)","Returns (sale returns)","money"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["cogs","মালের খরচ (শুধু খরচ-ধরা লাইন; আইটেম খরচ)","COGS (costed lines only; item costs)","money"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],
    ["expenses","ব্যয় (ভাউচার ১০-২)","Expenses (voucher 10-2)","money"],["salary","বেতন (বেতন শিট ০২-২)","Salary (salary sheet 02-2)","money"],
    ["fixed","স্থির খরচ (লোকেশন সেটিং, দিন অনুপাতে)","Fixed cost (location setting, pro rata)","money"],["profit","লাভ / (ক্ষতি)","Profit / (loss)","money"],["gaps","যা পাওয়া যায়নি","Missing inputs","text"]]'::jsonb,
  array['sales','returns','net_sales','cogs','expenses','salary','fixed','profit'], 'month', 'desc', array['locations','brands'], false, true, true, 270),
 ('l2_margin', 'L2', 'profit', 'আইটেম ও ক্যাটাগরি মার্জিন', 'Margin by item and category', 'আইটেম / Category margin',
  '[["level","স্তর","Level","text"],["category","ক্যাটাগরি","Category","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],
    ["qty","পরিমাণ","Qty","num"],["revenue","বিক্রি (রিটার্ন বাদে)","Sales (net of returns)","money"],["cogs","মালের খরচ (খরচ-ধরা লাইন)","COGS (costed lines)","money"],
    ["margin","মার্জিন (খরচ-ধরা লাইনে)","Margin (costed lines)","money"],["margin_pct","মার্জিন %","Margin %","pct"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"]]'::jsonb,
  '{}', 'revenue', 'desc', array['locations','brands','categories'], false, true, false, 271),
 ('l3_shop_pnl', 'L3', 'profit', 'দোকান P&L তুলনা', 'Shop P&L comparison', 'দোকান P&L তুলনা',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["cogs","মালের খরচ (খরচ-ধরা লাইন)","COGS (costed lines)","money"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],["expenses","ব্যয় (১০-২)","Expenses (10-2)","money"],
    ["salary","বেতন (০২-২)","Salary (02-2)","money"],["fixed","স্থির খরচ","Fixed cost","money"],["profit","লাভ / (ক্ষতি)","Profit / (loss)","money"],["profit_pct","লাভ %","Profit %","pct"],["gaps","যা পাওয়া যায়নি","Missing inputs","text"]]'::jsonb,
  array['net_sales','cogs','expenses','salary','fixed','profit'], 'profit_pct', 'asc', array['locations','brands'], false, true, true, 272),
 ('l4_owner_sheet', 'L4', 'profit', 'মালিকের মাসিক শিট বনাম সিস্টেম', 'Owner monthly sheet vs system', 'মালিকের শিট (01-2) vs system',
  '[["month","মাস","Month","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["scope","পরিধি","Scope","text"],
    ["sheet_sales","শিট: বিক্রি","Sheet: sales","money"],["sys_sales","সিস্টেম: নিট বিক্রি","System: net sales","money"],["diff_sales","পার্থক্য: বিক্রি","Diff: sales","money"],
    ["sheet_cogs","শিট: মালের খরচ (শুরু+ক্রয়−শেষ)","Sheet: COGS (open+purch−close)","money"],["sys_cogs","সিস্টেম: মালের খরচ (খরচ-ধরা লাইন)","System: COGS (costed lines)","money"],["sys_uncosted_pct","সিস্টেম: খরচ-ছাড়া বিক্রি %","System: uncosted sales %","pct"],
    ["sheet_expenses","শিট: ব্যয়","Sheet: expenses","money"],["sys_expenses","সিস্টেম: ব্যয় (১০-২)","System: expenses (10-2)","money"],["diff_expenses","পার্থক্য: ব্যয়","Diff: expenses","money"],
    ["sheet_salary","শিট: বেতন","Sheet: salary","money"],["sys_salary","সিস্টেম: বেতন (০২-২)","System: salary (02-2)","money"],["diff_salary","পার্থক্য: বেতন","Diff: salary","money"],
    ["sheet_net","শিট: নিট লাভ","Sheet: net profit","money"],["sys_net","সিস্টেম: নিট লাভ (স্থির খরচ ছাড়া)","System: net profit (before fixed cost)","money"]]'::jsonb,
  '{}', 'month', 'desc', array['locations','brands'], false, true, true, 273),
 ('l5_breakeven', 'L5', 'profit', 'ব্রেক-ইভেন ও খরচ কভারেজ', 'Break-even and cost coverage', 'Break-even ও cost coverage',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],["gm_pct","গ্রস মার্জিন % (খরচ-ধরা লাইনে)","Gross margin % (costed lines)","pct"],["fixed","স্থির খরচ (সময়ের জন্য)","Fixed cost (for the period)","money"],
    ["be_sales","ব্রেক-ইভেন বিক্রি (সময়ের)","Break-even sales (period)","money"],["gap","বিক্রি − ব্রেক-ইভেন","Sales − break-even","money"],["coverage_pct","কভারেজ %","Coverage %","pct"],
    ["fixed_month","মাসিক স্থির খরচ","Monthly fixed cost","money"],["be_month","মাসিক ব্রেক-ইভেন বিক্রি","Monthly break-even sales","money"]]'::jsonb,
  array['net_sales','fixed','be_sales'], 'coverage_pct', 'asc', array['locations','brands'], false, true, false, 274),
 ('t3_payroll', 'T3', 'profit', 'বেতন ও অ্যাডভান্স', 'Payroll and advances', 'বেতন ও Advance',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["person","কর্মী (নাম মিলিয়ে)","Person (matched by name)","text"],["sheets","বেতন শিট","Salary sheets","int"],
    ["gross_pay","মোট পাওনা (০২-২)","Total due (02-2)","money"],["adv_deducted","অ্যাডভান্স কর্তন (০২-২)","Advance deducted (02-2)","money"],["other_deducted","অন্য কর্তন","Other deduction","money"],["net_pay","নিট বেতন","Net pay","money"],
    ["adv_given","অ্যাডভান্স দেওয়া (০২-৩)","Advance given (02-3)","money"],["adv_register_deduction","রেজিস্টারে কর্তন (০২-৩)","Deduction in register (02-3)","money"],["adv_outstanding","বকেয়া অ্যাডভান্স (০২-৩, সর্বশেষ পাতা)","Advance outstanding (02-3, latest page)","money"]]'::jsonb,
  array['gross_pay','adv_deducted','other_deducted','net_pay','adv_given','adv_register_deduction','adv_outstanding'], 'net_pay', 'desc', array['locations','brands'], false, false, true, 275),
 ('t4_staff_cost_ratio', 'T4', 'profit', 'স্টাফ খরচ ÷ বিক্রি', 'Staff cost / sales %', 'Staff খরচ ÷ বিক্রি %',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],["salary","বেতন (০২-২)","Salary (02-2)","money"],["salary_pct","বেতন ÷ বিক্রি %","Salary ÷ sales %","pct"]]'::jsonb,
  array['net_sales','salary'], 'salary_pct', 'desc', array['locations','brands'], false, false, true, 276)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix,
  cols = excluded.cols, tot = excluded.tot, sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate,
  cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

select public._r3_lockdown();
-- ============================================================
-- PHASE 28 (groups C+D): parallel-month comparison (pairs, daily rows, month-end Pass / Fail), Print & books (paper book register, print notes),
--   "Needs you" oldest-first list. Additive and idempotent (paste twice = no error). Needs phase17 (form_rollout, rollout_set) and phase8.
--   * comparison_pairs: named by the OWNER (created empty - nothing is invented). comparison_days: one row per pair x place x day, the keeper writes the paper figure,
--     another person the app figure; the same person cannot do both on a row; result match / differ / waiting is computed.
--   * parallel_month_decide(form, place, month, pass, note): owner only, after the month has ended. Pass needs at least one comparison day, none waiting, every differ with a
--     reason and a fix; it then sets the form x place to 'app' (rollout_set) and records the decision. Fail records why; the form stays parallel.
--   * paper_books: first / last serial of each printed book per form x place; paper_books_check() lists gaps and overlaps; print_notes: what to change at the next print
--     (created when a place is renamed or closed, or by hand), cleared only by recording the new print (date + who).
--   * needs_you_oldest(limit): the oldest waiting things the caller may decide, oldest first.
-- Nothing is hard-deleted. Settings switches: rules parallel_compare_on (ON) and print_notes_auto (ON).
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('parallel_compare_on', 'entries', 'switch', 'true', null, null, null, null, 'পাশাপাশি মাস: দৈনিক তুলনা ও মাস-শেষের পাস/ফেল', 'Parallel মাস: daily comparison ও month-end pass/fail', 'Parallel month: daily comparison and month-end pass / fail',
  'বন্ধ করলে মাস-শেষে পাস/ফেল ছাড়াই মালিক নিজে কাগজ→অ্যাপ বদলাতে পারবেন (আগের মতো)।', 'Off = the owner can move paper→app without the month-end pass / fail (as before).', 90),
 ('smart_defaults_on', 'entries', 'switch', 'true', null, null, null, null, 'নতুন ফর্মে "আগেরটা থেকে নিন" বোতাম', 'নতুন form-এ "আগেরটা থেকে নিন" button', 'A "Start from my last one" button on a new form',
  'আগের এন্ট্রি থেকে শুধু আইটেম, সরবরাহকারী ও পছন্দের ঘর নেয়; কোনো পরিমাণ, টাকা, তারিখ বা সই নেয় না।', 'Copies only items, suppliers and choices from your last entry - never quantities, money, dates, signatures or photos.', 92),
 ('offline_cache_on', 'ui', 'switch', 'true', null, null, null, null, 'ইন্টারনেট ছাড়া অ্যাপ খোলা (ফোনে সংরক্ষণ)', 'Internet ছাড়া app খোলা (phone-এ cache)', 'Open the app without internet (cached on the phone)',
  'বন্ধ করলে ফোন থেকে সংরক্ষিত কপি মুছে যায়; অ্যাপ আগের মতো ইন্টারনেট লাগবে।', 'Off = the saved copy is removed from the phone; the app needs internet to start, as before.', 93),
 ('print_notes_auto', 'settings', 'switch', 'true', null, null, null, null, 'জায়গার নাম বদল/বন্ধে ছাপার নোট নিজে হবে', 'জায়গার নাম বদল/বন্ধে print note নিজে হবে', 'Print note is made when a place is renamed or closed',
  'পরের ছাপায় কী বদলাতে হবে তার নোট। ছাপার তারিখ লেখা না হওয়া পর্যন্ত নোট থাকে।', 'A note of what to change at the next print; it stays until the new print is recorded.', 91)
 on conflict (key) do nothing;

-- ---------- parallel comparison ----------
create table if not exists public.comparison_pairs (
  id bigserial primary key,
  form_code text not null references public.forms(code),
  name_bn text not null, name_en text,
  how_paper text, how_app text,                     -- how each figure is read, in words (the owner defines them)
  is_active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.comparison_days (
  id bigserial primary key,
  pair_id bigint not null references public.comparison_pairs(id),
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  day date not null,
  paper_value numeric check (paper_value is null or abs(paper_value) <= 1000000000000),
  app_value numeric check (app_value is null or abs(app_value) <= 1000000000000),
  result text not null default 'waiting' check (result in ('match', 'differ', 'waiting')),
  reason text, fix text,
  keeper_user uuid, enterer_user uuid,
  keeper_at timestamptz, enterer_at timestamptz,
  unique (pair_id, location_id, day),
  check (keeper_user is null or enterer_user is null or keeper_user <> enterer_user)
);
create table if not exists public.parallel_months (
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  month date not null,                              -- first day of the month
  result text not null check (result in ('pass', 'fail')),
  note text, days int, differ int,
  decided_by uuid, decided_at timestamptz not null default now(),
  primary key (form_code, location_id, month)
);
do $$ declare t text; begin
  foreach t in array array['comparison_pairs', 'comparison_days', 'parallel_months'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_active()%s)', t || '_read', t, case when t = 'comparison_days' or t = 'parallel_months' then ' and public.can_loc(location_id)' else '' end);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, case when t = 'parallel_months' then 'form_code,location_id,month' else 'id' end);
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;

create or replace function public._par_mgr() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('rollout_manage'));
$$;

create or replace function public.comparison_pair_save(p_form text, p_name_bn text, p_name_en text default null, p_how_paper text default null, p_how_app text default null,
  p_id bigint default null, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) < 2 then raise exception 'name_required'; end if;
  if not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  if p_id is null then
    insert into public.comparison_pairs (form_code, name_bn, name_en, how_paper, how_app, is_active, created_by)
      values (p_form, left(btrim(p_name_bn), 120), left(nullif(btrim(p_name_en), ''), 120), left(nullif(btrim(p_how_paper), ''), 300), left(nullif(btrim(p_how_app), ''), 300), coalesce(p_active, true), auth.uid()) returning id into nid;
  else
    update public.comparison_pairs set name_bn = left(btrim(p_name_bn), 120), name_en = left(nullif(btrim(p_name_en), ''), 120), how_paper = left(nullif(btrim(p_how_paper), ''), 300),
      how_app = left(nullif(btrim(p_how_app), ''), 300), is_active = coalesce(p_active, true) where id = p_id and form_code = p_form returning id into nid;
    if nid is null then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', nid);
end $$;

-- the keeper writes the paper figure, someone else the app figure; role = 'paper' | 'app'
create or replace function public.comparison_record(p_pair bigint, p_loc int, p_day date, p_role text, p_value numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr public.comparison_pairs; r public.comparison_days; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_role not in ('paper', 'app') then raise exception 'bad_role'; end if;
  if p_value is null or abs(p_value) > 1000000000000 then raise exception 'bad_amount'; end if;
  if p_day is null or p_day > today or p_day < today - 62 then raise exception 'bad_date'; end if;
  select * into pr from public.comparison_pairs where id = p_pair and is_active;
  if not found then raise exception 'pair_not_found'; end if;
  if public.rollout_mode(pr.form_code, p_loc) is distinct from 'parallel' then raise exception 'not_parallel'; end if;
  if exists (select 1 from public.parallel_months m where m.form_code = pr.form_code and m.location_id = p_loc and m.month = date_trunc('month', p_day)::date) then raise exception 'month_decided'; end if;
  if not (public.is_owner() or public.can_do(pr.form_code, 'enter') or public.can_do(pr.form_code, 'approve') or public.has_grant('rollout_manage', p_loc)) then raise exception 'not allowed'; end if;
  insert into public.comparison_days (pair_id, form_code, location_id, day) values (p_pair, pr.form_code, p_loc, p_day) on conflict (pair_id, location_id, day) do nothing;
  select * into r from public.comparison_days where pair_id = p_pair and location_id = p_loc and day = p_day for update;
  if p_role = 'paper' then
    if r.enterer_user = auth.uid() then raise exception 'keeper_is_enterer'; end if;
    if r.paper_value is not null and r.keeper_user is distinct from auth.uid() then raise exception 'already_recorded'; end if;
    update public.comparison_days set paper_value = round(p_value, 4), keeper_user = auth.uid(), keeper_at = now() where id = r.id;
  else
    if r.keeper_user = auth.uid() then raise exception 'keeper_is_enterer'; end if;
    if r.app_value is not null and r.enterer_user is distinct from auth.uid() then raise exception 'already_recorded'; end if;
    update public.comparison_days set app_value = round(p_value, 4), enterer_user = auth.uid(), enterer_at = now() where id = r.id;
  end if;
  update public.comparison_days set result = case when paper_value is null or app_value is null then 'waiting' when abs(paper_value - app_value) < 0.005 then 'match' else 'differ' end
    where id = r.id returning * into r;
  return jsonb_build_object('id', r.id, 'result', r.result);
end $$;

create or replace function public.comparison_explain(p_id bigint, p_reason text, p_fix text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.comparison_days;
begin
  select * into r from public.comparison_days where id = p_id for update;
  if not found or not public.can_loc(r.location_id) then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.has_grant('rollout_manage', r.location_id) or r.keeper_user = auth.uid() or r.enterer_user = auth.uid()) then raise exception 'not allowed'; end if;
  if r.result <> 'differ' then raise exception 'not_differ'; end if;
  if exists (select 1 from public.parallel_months m where m.form_code = r.form_code and m.location_id = r.location_id and m.month = date_trunc('month', r.day)::date) then raise exception 'month_decided'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 or p_fix is null or length(btrim(p_fix)) < 3 then raise exception 'reason_and_fix_required'; end if;
  update public.comparison_days set reason = left(btrim(p_reason), 300), fix = left(btrim(p_fix), 300) where id = r.id;
  return jsonb_build_object('id', r.id);
end $$;

create or replace function public.parallel_month_status(p_form text, p_loc int, p_month date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', coalesce(p_month, (now() at time zone 'Asia/Dhaka')::date))::date; today date := (now() at time zone 'Asia/Dhaka')::date;
        n int; mt int; df int; dfx int; wt int; pairs int; dec public.parallel_months; ended boolean;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  select count(*) into pairs from public.comparison_pairs where form_code = p_form and is_active;
  select count(*), count(*) filter (where result = 'match'), count(*) filter (where result = 'differ'), count(*) filter (where result = 'differ' and nullif(btrim(coalesce(reason, '')), '') is not null and nullif(btrim(coalesce(fix, '')), '') is not null),
         count(*) filter (where result = 'waiting')
    into n, mt, df, dfx, wt from public.comparison_days where form_code = p_form and location_id = p_loc and day >= m and day < (m + interval '1 month')::date;
  select * into dec from public.parallel_months where form_code = p_form and location_id = p_loc and month = m;
  ended := (m + interval '1 month')::date <= today;
  return jsonb_build_object('form', p_form, 'location_id', p_loc, 'month', m, 'mode', public.rollout_mode(p_form, p_loc), 'pairs', pairs, 'days', n, 'match', mt, 'differ', df, 'differ_explained', dfx, 'waiting', wt,
    'month_ended', ended, 'decision', case when dec.form_code is null then null else jsonb_build_object('result', dec.result, 'note', dec.note, 'at', dec.decided_at) end,
    'pass_ready', ended and pairs > 0 and n > 0 and wt = 0 and df = dfx and dec.form_code is null);
end $$;

create or replace function public.parallel_month_decide(p_form text, p_loc int, p_month date, p_pass boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; st jsonb; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_pass is null then raise exception 'bad_value'; end if;
  if public.rollout_mode(p_form, p_loc) is distinct from 'parallel' then raise exception 'not_parallel'; end if;
  if (m + interval '1 month')::date > today then raise exception 'month_not_ended'; end if;
  if exists (select 1 from public.parallel_months where form_code = p_form and location_id = p_loc and month = m) then raise exception 'already_decided'; end if;
  if not p_pass and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  st := public.parallel_month_status(p_form, p_loc, m);
  if p_pass and public.rule_on('parallel_compare_on') then
    if (st ->> 'pairs')::int = 0 then raise exception 'no_pair_named'; end if;
    if (st ->> 'days')::int = 0 then raise exception 'no_comparison_days'; end if;
    if (st ->> 'waiting')::int > 0 then raise exception 'days_waiting'; end if;
    if (st ->> 'differ')::int <> (st ->> 'differ_explained')::int then raise exception 'differ_without_reason'; end if;
  end if;
  insert into public.parallel_months (form_code, location_id, month, result, note, days, differ, decided_by)
    values (p_form, p_loc, m, case when p_pass then 'pass' else 'fail' end, left(nullif(btrim(p_note), ''), 300), (st ->> 'days')::int, (st ->> 'differ')::int, auth.uid());
  if p_pass then perform public.rollout_set(p_form, p_loc, 'app', 'parallel month ' || to_char(m, 'YYYY-MM') || ' passed'); end if;
  return jsonb_build_object('result', case when p_pass then 'pass' else 'fail' end, 'month', m);
end $$;

-- forms x places that are in parallel and whose last full month still has no decision (the owner's waiting list)
create or replace function public.parallel_waiting() returns table (form_code text, location_id int, month date)
language sql stable security definer set search_path = public as $$
  select r.form_code, r.location_id, (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date
    from public.form_rollout r
   where r.mode = 'parallel' and public.is_owner() and public.rule_on('parallel_compare_on')
     and exists (select 1 from public.comparison_days d where d.form_code = r.form_code and d.location_id = r.location_id
                   and d.day >= (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date and d.day < date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date)
     and not exists (select 1 from public.parallel_months p where p.form_code = r.form_code and p.location_id = r.location_id
                   and p.month = (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 month')::date);
$$;

-- ---------- print & books ----------
create table if not exists public.paper_books (
  id bigserial primary key,
  form_code text not null references public.forms(code),
  location_id int not null references public.locations(id),
  prefix text, first_no bigint not null check (first_no >= 0), last_no bigint not null,
  issued_on date, holder text, note text,
  status text not null default 'active' check (status in ('active', 'used', 'void')),
  created_by uuid, created_at timestamptz not null default now(),
  check (last_no >= first_no)
);
create index if not exists paper_books_fl on public.paper_books (form_code, location_id, first_no);
create table if not exists public.print_notes (
  id bigserial primary key,
  form_code text references public.forms(code),   -- null = every printed form that carries a place line
  location_id int not null references public.locations(id),
  reason text not null, change_to text,
  created_by uuid, created_at timestamptz not null default now(),
  cleared_on date, cleared_by uuid, cleared_at timestamptz
);
do $$ declare t text; begin
  foreach t in array array['paper_books', 'print_notes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public.is_owner() or public.has_grant(%L) or public.has_grant(%L, location_id))', t || '_read', t, 'head_management', 'print_books');
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'print_books', 'master', 64, 'ছাপা ও বই: সিরিয়াল ও ছাপার নোট লেখা', 'Print ও books: serial ও print note লেখা', 'Print & books: record serials and print notes', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'print_books');

create or replace function public._books_mgr(p_loc int default null) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('head_management') or public.has_grant('print_books', p_loc));
$$;

create or replace function public.paper_book_add(p_form text, p_loc int, p_first bigint, p_last bigint, p_prefix text default null, p_issued date default null, p_holder text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint; ov record;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.forms where code = p_form) or not exists (select 1 from public.locations where id = p_loc) then raise exception 'not_found'; end if;
  if p_first is null or p_last is null or p_first < 0 or p_last < p_first or p_last > 999999999999 then raise exception 'bad_range'; end if;
  select * into ov from public.paper_books b where b.form_code = p_form and b.location_id = p_loc and b.status <> 'void' and coalesce(b.prefix, '') = coalesce(nullif(btrim(p_prefix), ''), '') and p_first <= b.last_no and p_last >= b.first_no limit 1;
  if found then raise exception 'books_overlap' using detail = ov.first_no::text || '-' || ov.last_no::text; end if;
  insert into public.paper_books (form_code, location_id, prefix, first_no, last_no, issued_on, holder, note, created_by)
    values (p_form, p_loc, nullif(btrim(p_prefix), ''), p_first, p_last, p_issued, left(nullif(btrim(p_holder), ''), 80), left(nullif(btrim(p_note), ''), 300), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.paper_book_set_status(p_id bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.paper_books;
begin
  select * into b from public.paper_books where id = p_id for update;
  if not found or not public._books_mgr(b.location_id) or not public.can_loc(b.location_id) then raise exception 'not allowed'; end if;
  if p_status not in ('active', 'used', 'void') then raise exception 'bad_value'; end if;
  if p_status = 'void' and (p_note is null or length(btrim(p_note)) < 3) then raise exception 'note_required'; end if;
  if p_status <> 'void' and b.status = 'void' and exists (select 1 from public.paper_books o where o.id <> b.id and o.form_code = b.form_code and o.location_id = b.location_id and o.status <> 'void' and coalesce(o.prefix, '') = coalesce(b.prefix, '') and b.first_no <= o.last_no and b.last_no >= o.first_no) then raise exception 'books_overlap'; end if;
  update public.paper_books set status = p_status, note = coalesce(left(nullif(btrim(p_note), ''), 300), note) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', p_status);
end $$;

-- gaps and overlaps between the books of one form x place, and the first serial the app may use next
create or replace function public.paper_books_check(p_form text, p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prev public.paper_books; b public.paper_books; issues jsonb := '[]'::jsonb; mx bigint;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  for b in select * from public.paper_books where form_code = p_form and location_id = p_loc and status <> 'void' order by coalesce(prefix, ''), first_no loop
    if prev.id is not null and coalesce(prev.prefix, '') = coalesce(b.prefix, '') then
      if b.first_no <= prev.last_no then issues := issues || jsonb_build_array(jsonb_build_object('type', 'overlap', 'from', prev.last_no, 'to', b.first_no));
      elsif b.first_no > prev.last_no + 1 then issues := issues || jsonb_build_array(jsonb_build_object('type', 'gap', 'from', prev.last_no + 1, 'to', b.first_no - 1)); end if;
    end if;
    prev := b;
  end loop;
  select max(last_no) into mx from public.paper_books where form_code = p_form and location_id = p_loc and status <> 'void';
  return jsonb_build_object('issues', issues, 'last_paper_no', mx, 'app_continues_from', case when mx is null then null else mx + 1 end);
end $$;

create or replace function public.print_note_add(p_loc int, p_form text, p_reason text, p_change text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not public._books_mgr(p_loc) or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_form is not null and not exists (select 1 from public.forms where code = p_form) then raise exception 'form_not_found'; end if;
  insert into public.print_notes (form_code, location_id, reason, change_to, created_by) values (p_form, p_loc, left(btrim(p_reason), 300), left(nullif(btrim(p_change), ''), 300), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid);
end $$;

create or replace function public.print_note_clear(p_id bigint, p_printed_on date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n public.print_notes;
begin
  select * into n from public.print_notes where id = p_id for update;
  if not found or not public._books_mgr(n.location_id) or not public.can_loc(n.location_id) then raise exception 'not allowed'; end if;
  if n.cleared_at is not null then return jsonb_build_object('id', n.id, 'dup', true); end if;
  if p_printed_on is null or p_printed_on > (now() at time zone 'Asia/Dhaka')::date + 1 or p_printed_on < date '2000-01-01' then raise exception 'bad_date'; end if;
  update public.print_notes set cleared_on = p_printed_on, cleared_by = auth.uid(), cleared_at = now() where id = n.id;
  return jsonb_build_object('id', n.id);
end $$;

-- a place renamed or closed -> one note (null form = every printed form with a place line)
create or replace function public._loc_print_note() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.rule_on('print_notes_auto') then return new; end if;
  if new.name_bn is distinct from old.name_bn or new.name_en is distinct from old.name_en or new.name_mix is distinct from old.name_mix then
    insert into public.print_notes (form_code, location_id, reason, change_to, created_by)
      values (null, new.id, 'place renamed: ' || coalesce(old.name_bn, '') || ' -> ' || coalesce(new.name_bn, ''), 'Change the place line at the next print', auth.uid());
  end if;
  if new.status is distinct from old.status and new.status = 'closed' then
    insert into public.print_notes (form_code, location_id, reason, change_to, created_by) values (null, new.id, 'place closed: ' || coalesce(new.name_bn, ''), 'Remove the place from the next print', auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists locations_print_note on public.locations;
create trigger locations_print_note after update on public.locations for each row execute function public._loc_print_note();

-- ---------- Needs you: the oldest waiting things the caller may decide ----------
create or replace function public.needs_you_oldest(p_limit int default 8) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb; lim int := least(greatest(coalesce(p_limit, 8), 1), 30);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.since), '[]'::jsonb) into out_ from (
    select * from (
      select 'entry'::text kind, e.id::text id, e.form_code || ' #' || coalesce(e.serial::text, '') as label, e.location_id, coalesce(e.submitted_at, e.created_at) as since, ('entry/' || e.id)::text as route
        from public.entries e where e.status = 'submitted' and public.can_loc(e.location_id) and (public.is_owner() or public.can_do(e.form_code, 'approve')) and e.created_by is distinct from auth.uid()
      union all
      select 'release', r.id::text, r.flag_code, (select en.location_id from public.entries en where en.id = r.entry_id), r.requested_at, 'releases'
        from public.release_requests r where r.status = 'pending' and public._release_can_see(r.entry_id)
      union all
      select 'emergency', q.id::text, q.grant_code, q.location_id, q.created_at, 'emergency' from public.emergency_requests q where q.status = 'pending' and public.is_owner()
      union all
      select 'item_change', c.id::text, 'item change', null::int, c.requested_at, 'itemreq' from public.item_changes c where c.status = 'pending' and (public.is_owner() or public.has_grant('item_create') or public.can_do('ITEMS', 'approve'))
      union all
      select 'staff', p.id::text, coalesce(p.full_name, p.staff_id), null::int, p.created_at, 'staff' from public.profiles p where p.status = 'pending' and public.is_owner()
      union all
      select 'wastage', w.id::text, 'wastage', w.location_id, w.requested_at, 'stock' from public.wastage_requests w where w.status = 'pending' and public.can_loc(w.location_id) and public.has_grant('wastage_approve', w.location_id) and w.requested_by is distinct from auth.uid()
      union all
      select 'parallel', pw.form_code || ':' || pw.location_id, pw.form_code || ' ' || to_char(pw.month, 'YYYY-MM'), pw.location_id, (pw.month + interval '1 month')::timestamptz, 'parallel' from public.parallel_waiting() pw
    ) u where u.since is not null order by u.since limit lim
  ) x;
  return out_;
end $$;


-- ---------- guided flows: a skipped step is recorded with a note (never silently ticked) ----------
create table if not exists public.flow_skips (
  id bigserial primary key,
  flow text not null check (flow ~ '^[a-z_]{2,30}$'), step text not null check (step ~ '^[a-z0-9_]{1,40}$'),
  location_id int references public.locations(id), day date not null,
  note text not null check (length(btrim(note)) >= 3),
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(),
  unique (flow, step, location_id, day, created_by)
);
alter table public.flow_skips enable row level security;
drop policy if exists flow_skips_read on public.flow_skips;
create policy flow_skips_read on public.flow_skips for select to authenticated using (created_by = auth.uid() or public.is_owner());
revoke all on public.flow_skips from public, anon, authenticated; grant select on public.flow_skips to authenticated;
drop trigger if exists audit_flow_skips on public.flow_skips;
create trigger audit_flow_skips after insert on public.flow_skips for each row execute function public.log_change('id');
drop trigger if exists flow_skips_no_change on public.flow_skips;
create trigger flow_skips_no_change before update or delete on public.flow_skips for each row execute function public.no_hard_delete();
create or replace function public.flow_skip(p_flow text, p_step text, p_loc int, p_day date, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text;
begin
  if not public.is_active() or (p_loc is not null and not public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  if p_day is null or p_day > (now() at time zone 'Asia/Dhaka')::date or p_day < (now() at time zone 'Asia/Dhaka')::date - 31 then raise exception 'bad_date'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.flow_skips (flow, step, location_id, day, note, created_by, created_staff) values (p_flow, p_step, p_loc, p_day, left(btrim(p_note), 300), auth.uid(), sid)
    on conflict (flow, step, location_id, day, created_by) do nothing;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.flow_skip(text, text, int, date, text) from public, anon; grant execute on function public.flow_skip(text, text, int, date, text) to authenticated;

revoke all on function public._par_mgr(), public._books_mgr(int), public._loc_print_note(), public.comparison_pair_save(text, text, text, text, text, bigint, boolean), public.comparison_record(bigint, int, date, text, numeric),
  public.comparison_explain(bigint, text, text), public.parallel_month_status(text, int, date), public.parallel_month_decide(text, int, date, boolean, text), public.parallel_waiting(),
  public.paper_book_add(text, int, bigint, bigint, text, date, text, text), public.paper_book_set_status(bigint, text, text), public.paper_books_check(text, int),
  public.print_note_add(int, text, text, text), public.print_note_clear(bigint, date), public.needs_you_oldest(int) from public, anon;
revoke all on function public._par_mgr(), public._books_mgr(int), public._loc_print_note() from authenticated;
grant execute on function public.comparison_pair_save(text, text, text, text, text, bigint, boolean), public.comparison_record(bigint, int, date, text, numeric),
  public.comparison_explain(bigint, text, text), public.parallel_month_status(text, int, date), public.parallel_month_decide(text, int, date, boolean, text), public.parallel_waiting(),
  public.paper_book_add(text, int, bigint, bigint, text, date, text, text), public.paper_book_set_status(bigint, text, text), public.paper_books_check(text, int),
  public.print_note_add(int, text, text, text), public.print_note_clear(bigint, date), public.needs_you_oldest(int) to authenticated;
notify pgrst, 'reload schema';
