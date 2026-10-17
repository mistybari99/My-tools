-- Phase 406 (bos406) - RPT-B4 / R4a: PLAN VS ACTUAL (#40), ORDER STATUS AND PENDING ORDERS (#52), PRODUCTION-TO-DISPATCH RECONCILIATION (#53).
-- Paste after phase405. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
-- Who may read: the owner, the stock report right (report_stock), the recipe / production readers, and the stock-transfer staff of the place. Every figure is limited to the places the reader may see.
-- What a report cannot know is said in words: "plan_not_captured", "qty_not_captured" ... a blank is never turned into 0 and never added into a total.
--
--   rb4_plan_vs_actual(from, to, place)   one row per plan key (place + item + plan day): planned batches / quantity against what was really made (finished runs, quantity actually booked);
--                                         runs with no plan are listed apart. A run belongs to its linked plan; an unlinked run belongs to the plan of the same place + item + day.
--   rb4_order_status(from, to, place, status)   orders of the period and every order still open: made so far (linked finished runs), balance, overdue days, a derived state.
--   rb4_dispatch_recon(from, to, place)   per day, producing place and item: made - sent - received - in transit - short, and the quantity on hand now at the producing place.

do $g$ begin
  if to_regprocedure('public.prod_run_link(uuid,uuid,bigint,boolean,boolean)') is null then raise exception 'phase406 needs phase405 first'; end if;
end $g$;

-- every finished run with the plan day it belongs to (linked plan first, else its own Dhaka day), limited to the places the reader may see
create or replace function public._rb4_pva_runs(f date, t date, p_loc int) returns table (run_id uuid, location_id int, item_id uuid, kday date, batches numeric, qty numeric)
language sql stable security definer set search_path = public as $$
  select r.id, r.location_id, r.item_id, coalesce(pp.plan_date, public._rb4_day(r.made_at)), r.batches, r.yield_base
    from public.production_runs r
    left join public.production_run_links k on k.run_id = r.id
    left join public.production_plans pp on pp.id = k.plan_id and pp.status = 'planned'
   where r.status = 'done' and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)
     and coalesce(pp.plan_date, public._rb4_day(r.made_at)) between f and t;
$$;

create or replace function public.rb4_plan_vs_actual(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; un jsonb; sm jsonb; nplans int; ncancel int; notes jsonb := '[]'::jsonb; td date := public._rb4_today();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select count(*) into nplans from public.production_plans p where p.status = 'planned' and p.plan_date between f and t and (p_loc is null or p.location_id = p_loc) and public._rb4_prod_view(p.location_id);
  select count(*) into ncancel from public.production_plans p where p.status = 'cancelled' and p.plan_date between f and t and (p_loc is null or p.location_id = p_loc) and public._rb4_prod_view(p.location_id);
  if nplans = 0 then notes := notes || jsonb_build_object('code', 'plan_not_captured', 'field', 'production plan'); end if;

  select coalesce(jsonb_agg(z.j order by z.pd desc, z.code, z.lid), '[]'::jsonb) into rows_ from (
    select k.plan_date as pd, i.code, k.location_id as lid, jsonb_build_object('plan_date', k.plan_date, 'location_id', k.location_id, 'location', l.name_bn, 'location_en', l.name_en,
        'item_id', k.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(k.item_id),
        'plans_n', k.plans_n, 'plan_ids', k.plan_ids,
        'planned_batches', case when k.batches_missing = 0 then k.batches end, 'planned_qty', case when k.qty_missing = 0 then k.qty end, 'planned_qty_missing_n', k.qty_missing,
        'actual_batches', coalesce(a.batches, 0), 'actual_qty', coalesce(a.qty, 0), 'runs_n', coalesce(a.runs_n, 0), 'run_ids', coalesce(a.run_ids, '[]'::jsonb),
        'achievement_pct', case when k.qty_missing = 0 and k.qty > 0 and (coalesce(a.runs_n, 0) > 0 or k.plan_date <= td) then round(coalesce(a.qty, 0) / k.qty * 100, 1) end,
        'status', case when k.qty_missing > 0 then 'qty_not_captured'
                       when coalesce(a.runs_n, 0) = 0 and k.plan_date > td then 'not_due_yet'
                       when coalesce(a.runs_n, 0) = 0 then 'not_made'
                       when a.qty < k.qty then 'short' when a.qty = k.qty then 'met' else 'over' end) as j
      from (select p.location_id, p.item_id, p.plan_date, count(*) as plans_n, jsonb_agg(p.id order by p.created_at) as plan_ids,
                   sum(p.planned_batches) as batches, count(*) filter (where p.planned_batches is null) as batches_missing,
                   sum(p.planned_qty) as qty, count(*) filter (where p.planned_qty is null) as qty_missing
              from public.production_plans p
             where p.status = 'planned' and p.plan_date between f and t and (p_loc is null or p.location_id = p_loc) and public._rb4_prod_view(p.location_id)
             group by p.location_id, p.item_id, p.plan_date) k
      left join (select ra.location_id, ra.item_id, ra.kday, sum(ra.batches) as batches, sum(ra.qty) as qty, count(*) as runs_n, jsonb_agg(ra.run_id) as run_ids from public._rb4_pva_runs(f, t, p_loc) ra group by 1, 2, 3) a
             on a.location_id = k.location_id and a.item_id = k.item_id and a.kday = k.plan_date
      join public.items i on i.id = k.item_id join public.locations l on l.id = k.location_id) z;

  select coalesce(jsonb_agg(jsonb_build_object('day', u.kday, 'location_id', u.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', u.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en,
      'base_unit', public._item_base(u.item_id), 'runs_n', u.runs_n, 'run_ids', u.run_ids, 'batches', u.batches, 'qty', u.qty) order by u.kday desc, i.code), '[]'::jsonb) into un
    from (select ra.location_id, ra.item_id, ra.kday, sum(ra.batches) as batches, sum(ra.qty) as qty, count(*) as runs_n, jsonb_agg(ra.run_id) as run_ids
            from public._rb4_pva_runs(f, t, p_loc) ra
           where not exists (select 1 from public.production_plans p where p.status = 'planned' and p.location_id = ra.location_id and p.item_id = ra.item_id and p.plan_date = ra.kday)
           group by 1, 2, 3) u join public.items i on i.id = u.item_id join public.locations l on l.id = u.location_id;

  select jsonb_build_object('plans', nplans, 'cancelled_plans', ncancel,
      'rows_met', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' in ('met', 'over')),
      'rows_short', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'short'),
      'rows_not_made', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'not_made'),
      'rows_qty_not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'qty_not_captured'),
      'unplanned_runs', coalesce((select sum((e ->> 'runs_n')::int) from jsonb_array_elements(un) e), 0)) into sm;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'unplanned', un, 'summary', sm, 'notes', notes);
end $$;

create or replace function public.rb4_order_status(p_from date default null, p_to date default null, p_loc int default null, p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; td date := public._rb4_today(); rows_ jsonb; sm jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  if p_status is not null and p_status not in ('open', 'closed', 'cancelled', 'pending', 'overdue') then raise exception 'bad_status'; end if;
  select coalesce(jsonb_agg(z.j order by z.so, z.due nulls last, z.id), '[]'::jsonb) into rows_ from (
    select o.id, o.due_date as due, case y.state when 'overdue' then 0 when 'not_started' then 1 when 'partly_made' then 2 when 'made_not_closed' then 3 when 'closed' then 4 else 5 end as so,
      jsonb_build_object('order_no', o.id, 'order_date', o.order_date, 'due_date', o.due_date, 'location_id', o.location_id, 'location', l.name_bn, 'location_en', l.name_en,
        'for_location_id', o.for_location_id, 'for_location', fl.name_bn, 'for_location_en', fl.name_en,
        'item_id', o.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(o.item_id),
        'qty', o.qty, 'made', y.made, 'balance', case when o.status = 'open' then greatest(o.qty - y.made, 0) end, 'runs_n', y.runs_n, 'run_ids', y.run_ids,
        'status', o.status, 'state', y.state, 'days_overdue', case when o.status = 'open' and o.due_date is not null and o.due_date < td and y.made < o.qty then td - o.due_date end,
        'due_not_captured', o.due_date is null, 'note', o.note, 'close_note', o.close_note, 'created_staff', o.created_staff) as j
      from public.production_orders o
      join public.items i on i.id = o.item_id join public.locations l on l.id = o.location_id left join public.locations fl on fl.id = o.for_location_id
      cross join lateral (select coalesce(sum(r.yield_base), 0) as made, count(r.id) as runs_n, coalesce(jsonb_agg(r.id), '[]'::jsonb) as run_ids,
          case when o.status = 'cancelled' then 'cancelled' when o.status = 'closed' then 'closed'
               when coalesce(sum(r.yield_base), 0) >= o.qty then 'made_not_closed'
               when o.due_date is not null and o.due_date < td then 'overdue'
               when coalesce(sum(r.yield_base), 0) > 0 then 'partly_made' else 'not_started' end as state
          from public.production_run_links k join public.production_runs r on r.id = k.run_id and r.status = 'done' where k.order_id = o.id) y
     where (o.order_date between f and t or o.status = 'open') and (p_loc is null or o.location_id = p_loc or o.for_location_id = p_loc)
       and (public._rb4_prod_view(o.location_id) or (o.for_location_id is not null and public._rb4_prod_view(o.for_location_id)))
       and (p_status is null or (p_status in ('open', 'closed', 'cancelled') and o.status = p_status) or (p_status = 'pending' and o.status = 'open') or (p_status = 'overdue' and y.state = 'overdue'))) z;
  select jsonb_build_object('orders', jsonb_array_length(rows_),
      'open', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'open'),
      'overdue', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'overdue'),
      'not_started', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'not_started'),
      'made_not_closed', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'state' = 'made_not_closed'),
      'due_not_captured', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' = 'open' and (e ->> 'due_not_captured')::boolean)) into sm;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm,
    'notes', case when jsonb_array_length(rows_) = 0 and not exists (select 1 from public.production_orders) then jsonb_build_array(jsonb_build_object('code', 'order_not_captured', 'field', 'production order')) else '[]'::jsonb end);
end $$;

-- per day, producing place and item: made, sent, received, in transit, short, cancelled
create or replace function public._rb4_dr_rows(f date, t date, p_loc int) returns table (day date, location_id int, item_id uuid, made numeric, runs_n int, sent numeric, received numeric, in_transit numeric, short numeric, cancelled numeric, transfers_n int)
language sql stable security definer set search_path = public as $$
  select d.day, d.location_id, d.item_id, sum(d.made), sum(d.runs_n)::int, sum(d.sent), sum(d.received), sum(d.in_transit), sum(d.short), sum(d.cancelled), sum(d.transfers_n)::int
    from (
      select public._rb4_day(r.made_at) as day, r.location_id, r.item_id, r.yield_base as made, 1 as runs_n, 0::numeric as sent, 0::numeric as received, 0::numeric as in_transit, 0::numeric as short, 0::numeric as cancelled, 0 as transfers_n
        from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)
      union all
      select public._rb4_day(s.sent_at), s.from_location_id, s.item_id, 0, 0,
             case when s.status in ('sent', 'received') then s.qty else 0 end,
             case when s.status = 'received' then coalesce(s.received_qty, 0) else 0 end,
             case when s.status = 'sent' then s.qty else 0 end,
             case when s.status = 'received' then s.qty - coalesce(s.received_qty, 0) else 0 end,
             case when s.status = 'cancelled' then s.qty else 0 end, 1
        from public.stock_transfers s
       where public._rb4_day(s.sent_at) between f and t and (p_loc is null or s.from_location_id = p_loc) and public._rb4_prod_view(s.from_location_id)
         and exists (select 1 from public.production_runs r2 where r2.location_id = s.from_location_id and r2.item_id = s.item_id and r2.status = 'done')) d
   group by d.day, d.location_id, d.item_id;
$$;

create or replace function public.rb4_dispatch_recon(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; sm jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('day', x.day, 'location_id', x.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en,
      'base_unit', public._item_base(x.item_id), 'made', x.made, 'runs_n', x.runs_n, 'sent', x.sent, 'received', x.received, 'in_transit', x.in_transit, 'short', x.short, 'cancelled', x.cancelled, 'transfers_n', x.transfers_n,
      'tie_ok', x.sent = x.received + x.in_transit + x.short) order by x.day desc, i.code, x.location_id), '[]'::jsonb) into rows_
    from public._rb4_dr_rows(f, t, p_loc) x join public.items i on i.id = x.item_id join public.locations l on l.id = x.location_id;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', s.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', s.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(s.item_id),
      'made', s.made, 'sent', s.sent, 'received', s.received, 'in_transit', s.in_transit, 'short', s.short, 'cancelled', s.cancelled, 'made_not_sent', s.made - s.sent,
      'on_hand_now', (select b.qty from public.stock_balance b where b.item_id = s.item_id and b.location_id = s.location_id), 'tie_ok', s.sent = s.received + s.in_transit + s.short) order by i.code, s.location_id), '[]'::jsonb) into sm
    from (select x.location_id, x.item_id, sum(x.made) as made, sum(x.sent) as sent, sum(x.received) as received, sum(x.in_transit) as in_transit, sum(x.short) as short, sum(x.cancelled) as cancelled from public._rb4_dr_rows(f, t, p_loc) x group by 1, 2) s
    join public.items i on i.id = s.item_id join public.locations l on l.id = s.location_id;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm,
    'basis', 'Made = finished runs (quantity really booked). Sent / received / in transit / short = stock transfers sent on that day from the producing place, for items that place has produced. Short = sent - received on a received transfer. On hand now = the balance today, not at the end of the period.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_plan_vs_actual', 'rb4_order_status', 'rb4_dispatch_recon') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

do $q$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_pva_runs', '_rb4_dr_rows') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $q$;

notify pgrst, 'reload schema';
