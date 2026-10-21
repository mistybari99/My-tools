-- ============================================================
-- Phase 450 - RPT-C2 / R4 part 6 (reports #159 delayed and undelivered orders, #158 on-time delivery performance, #163 order fulfilment rate). READ ONLY.
-- Run AFTER phase 449. New file only. Paste twice = no error.
--
--   The promised moment of an app order = its delivery date + the END of the promised time slot (phase 445); a point time uses that time; no slot = the end of the promised day (basis "date_only", said on screen).
--   Grace: rule order_late_grace_minutes - blank = none. Orders with NO delivery date cannot be judged: they are COUNTED apart ("not judged"), never treated as on time or as late.
--   Paper form 20-1 sheets: promised date and time are on the sheet (deliv_date, deliv_time); the sheet has no delivery timestamp, so paper rows appear in the delayed list (still open after the promise)
--   and in the fulfilment counts, but are never part of the on-time percentage (note paper_delivery_time_not_captured).
--   Open to the existing order-report access; only the places the person may see.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_order_register(date,date,int,text,text,text,int)') is null then raise exception 'phase450 needs phase449 pasted first'; end if;
end $guard$;

-- the promised end moment (Dhaka time) of a row of _c2_orders_base; null when there is no promised date
create or replace function public._c2_promised_end(p_date date, p_from time, p_to time) returns timestamptz language sql immutable as $$
  select case when p_date is null then null else ((p_date::timestamp + coalesce(p_to, p_from, time '23:59:59')) at time zone 'Asia/Dhaka') end;
$$;
create or replace function public._c2_grace() returns interval language sql stable security definer set search_path = public as $$
  select make_interval(mins => coalesce(public.rule_num('order_late_grace_minutes'), 0)::int);
$$;

-- #159 delayed and undelivered orders (open orders whose promised moment has passed)
create or replace function public.c2_orders_delayed(p_loc int default null, p_as_of timestamptz default null, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare nowts timestamptz := coalesce(p_as_of, now()); d1 date := coalesce(p_from, (nowts at time zone 'Asia/Dhaka')::date - 365); d2 date := coalesce(p_to, (nowts at time zone 'Asia/Dhaka')::date + 365); rows jsonb; sm jsonb; g interval := public._c2_grace();
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  perform public._c2_range(d1, d2);
  with b as (select x.*, public._c2_promised_end(x.promised_date, x.promised_from, x.promised_to) as pend
               from public._c2_orders_base(d1, d2, p_loc, 'promised') x where x.source in ('app', 'paper_20_1') and x.status in ('new', 'confirmed', 'packed', 'open')),
       o as (select b.*, nowts - b.pend as over, (b.promised_from is not null) as slot_known from b where b.pend is not null and nowts > b.pend + g)
  select (select coalesce(jsonb_agg(jsonb_build_object('source', source, 'ref', ref, 'order_id', order_id, 'entry_id', entry_id, 'loc', loc, 'customer_name', customer_name, 'customer_mobile', customer_mobile, 'status', status,
            'channel', channel, 'order_type', order_type, 'delivery_mode', delivery_mode, 'promised_date', promised_date, 'promised_from', promised_from, 'promised_to', promised_to, 'basis', case when slot_known then 'slot' else 'date_only' end,
            'overdue_hours', case when slot_known then round(extract(epoch from over) / 3600, 1) end, 'overdue_days', (nowts at time zone 'Asia/Dhaka')::date - promised_date, 'advance', advance, 'balance', balance, 'total', total)
            order by over desc), '[]'::jsonb) from o),
         jsonb_build_object('delayed', (select count(*) from o), 'delayed_app', (select count(*) from o where source = 'app'), 'delayed_paper_20_1', (select count(*) from o where source = 'paper_20_1'),
           'oldest_days', (select max((nowts at time zone 'Asia/Dhaka')::date - promised_date) from o),
           'judged_by_slot', (select count(*) from o where slot_known), 'judged_by_date_only', (select count(*) from o where not slot_known),
           'open_without_promised_date', (select count(*) from public._c2_orders_base((nowts at time zone 'Asia/Dhaka')::date - 365, (nowts at time zone 'Asia/Dhaka')::date + 1, p_loc, 'order') y
                                           where y.source in ('app', 'paper_20_1') and y.status in ('new', 'confirmed', 'packed', 'open') and y.promised_date is null),
           'open_not_yet_due', (select count(*) from b where b.pend is not null and nowts <= b.pend + g), 'grace_minutes', public.rule_num('order_late_grace_minutes'))
    into rows, sm;
  return jsonb_build_object('as_of', nowts at time zone 'Asia/Dhaka', 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true) || '"open_without_date_not_judged"'::jsonb, 'summary', sm, 'rows', rows);
end $$;

-- #158 on-time delivery performance (app orders delivered; the promised date is inside the range)
create or replace function public.c2_orders_ontime(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; byx jsonb; g interval := public._c2_grace(); nj int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select x.*, public._c2_promised_end(x.promised_date, x.promised_from, x.promised_to) as pend
               from public._c2_orders_base(p_from, p_to, p_loc, 'promised') x where x.source = 'app' and x.status = 'delivered' and x.delivered_at is not null),
       j as (select b.*, (b.delivered_at <= b.pend + g) as on_time, (b.promised_from is not null) as slot_known,
                    round(extract(epoch from (b.delivered_at - b.pend)) / 60) as late_minutes from b where b.pend is not null)
  select (select coalesce(jsonb_agg(jsonb_build_object('ref', ref, 'order_id', order_id, 'loc', loc, 'customer_name', customer_name, 'channel', channel, 'delivery_mode', delivery_mode, 'delivery_by', delivery_by,
            'promised_date', promised_date, 'promised_from', promised_from, 'promised_to', promised_to, 'delivered_at', delivered_at at time zone 'Asia/Dhaka', 'basis', case when slot_known then 'slot' else 'date_only' end,
            'on_time', on_time, 'late_minutes', case when on_time then null else late_minutes end) order by delivered_at desc), '[]'::jsonb) from j),
         jsonb_build_object('judged', (select count(*) from j), 'on_time', (select count(*) from j where on_time), 'late', (select count(*) from j where not on_time),
           'on_time_pct', (select case when count(*) = 0 then null else round(100.0 * count(*) filter (where on_time) / count(*), 1) end from j),
           'judged_by_slot', (select count(*) from j where slot_known), 'judged_by_date_only', (select count(*) from j where not slot_known),
           'on_time_by_slot_pct', (select case when count(*) filter (where slot_known) = 0 then null else round(100.0 * count(*) filter (where slot_known and on_time) / count(*) filter (where slot_known), 1) end from j),
           'avg_late_minutes', (select round(avg(late_minutes)) from j where not on_time), 'grace_minutes', public.rule_num('order_late_grace_minutes')),
         (select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) from (select 'by_mode:' || coalesce(delivery_mode, '-') as k, jsonb_build_object('judged', count(*), 'on_time', count(*) filter (where on_time)) as v from j group by delivery_mode
              union all select 'by_channel:' || coalesce(channel, '-'), jsonb_build_object('judged', count(*), 'on_time', count(*) filter (where on_time)) from j group by channel) q)
    into rows, sm, byx;
  select count(*) into nj from public._c2_orders_base(p_from, p_to, p_loc, 'order') y where y.source = 'app' and y.status = 'delivered' and y.promised_date is null;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'),
    'notes', public._c2_order_notes(true) || '"paper_delivery_time_not_captured"'::jsonb, 'summary', sm || jsonb_build_object('delivered_without_promised_date_not_judged', nj), 'breakdown', byx,
    'still_open_overdue', (public.c2_orders_delayed(p_loc, null, p_from, p_to) -> 'summary' ->> 'delayed_app')::int, 'rows', rows);
end $$;

-- #163 order fulfilment rate (by the day the order was taken)
create or replace function public.c2_order_fulfilment(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sm jsonb; byx jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select * from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source in ('app', 'paper_20_1')),
       a as (select source,
              count(*) as orders,
              count(*) filter (where status in ('delivered', 'handed')) as delivered,
              count(*) filter (where status in ('cancelled', 'not_collected')) as cancelled,
              count(*) filter (where status in ('new', 'confirmed', 'packed', 'open')) as still_open
             from b group by source)
  select coalesce(jsonb_object_agg(source, jsonb_build_object('orders', orders, 'delivered', delivered, 'cancelled', cancelled, 'still_open', still_open,
            'rate_of_closed_pct', case when delivered + cancelled = 0 then null else round(100.0 * delivered / (delivered + cancelled), 1) end,
            'rate_of_all_pct', case when orders = 0 then null else round(100.0 * delivered / orders, 1) end)), '{}'::jsonb) into sm from a;
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into byx from (
    select 'app:channel:' || coalesce(channel, '-') as k, jsonb_build_object('orders', count(*), 'delivered', count(*) filter (where status = 'delivered'), 'cancelled', count(*) filter (where status = 'cancelled')) as v
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' group by channel
    union all select 'app:mode:' || coalesce(delivery_mode, '-'), jsonb_build_object('orders', count(*), 'delivered', count(*) filter (where status = 'delivered'), 'cancelled', count(*) filter (where status = 'cancelled'))
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' group by delivery_mode) q;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(true) || '"rate_formulas"'::jsonb, 'summary', sm, 'breakdown', byx);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
