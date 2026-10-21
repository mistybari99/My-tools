-- ============================================================
-- Phase 451 - RPT-C2 / R4 part 7 (reports #157 order cancellation and refunds, #162 delivery cost and performance). READ ONLY.
-- Run AFTER phase 450. New file only. Paste twice = no error.
--
--   c2_order_cancellations(from, to, place)   app orders cancelled in the range (the day the cancel was written in the order trail) with reason, advance, what was decided for it and where the refund stands
--       (paid / due / closed without payment / NOT RECORDED because the refund switch is off / kept as customer advance / taken as income), plus the paper 20-1 sheets marked "not collected".
--   c2_delivery_cost_report(from, to, place)  home and courier orders taken in the range: what the customer paid for delivery, the actual cost written at delivery (phase 446), the margin ONLY where a cost
--       was written. Orders with no cost written are COUNTED apart ("cost not captured"), never treated as cost 0. Paper 20-6 ledger lines show their delivery charge; the paper sheet has no cost side.
--   Delivery cost needs the cost right (rpt_cost_ok); without it the cost columns are empty and the note cost_hidden says why. Open to the existing order-report access; only places the person may see.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_orders_ontime(date,date,int)') is null then raise exception 'phase451 needs phase450 pasted first'; end if;
end $guard$;

create or replace function public.c2_order_cancellations(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; paper jsonb; reasons jsonb; created_n int; created_c int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with c as (
    select o.id, o.order_no, o.location_id, o.customer_name, o.channel, o.cancel_reason, o.advance, o.advance_fate, o.advance_mode,
           o.subtotal - o.discount + o.delivery_charge as total,
           (select e.at from public.online_order_events e where e.order_id = o.id and e.to_status = 'cancelled' order by e.id desc limit 1) as cancelled_at,
           (select r.state from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1) as rstate,
           (select r.paid_at from public.order_refunds r where r.order_id = o.id and r.state = 'paid' limit 1) as paid_at,
           (select r.refund_mode from public.order_refunds r where r.order_id = o.id order by r.id desc limit 1) as rmode,
           exists (select 1 from public.order_advance_posts a where a.order_id = o.id and a.state = 'posted') as held_posted
      from public.online_orders o where o.status = 'cancelled' and public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc)),
       d as (select c.*, case when c.advance = 0 then 'none' when c.rstate = 'paid' then 'refunded' when c.rstate = 'due' then 'refund_due' when c.rstate = 'void' then 'refund_closed'
                              else case c.advance_fate when 'refund' then 'refund_not_recorded' when 'adjust' then case when c.held_posted then 'kept_as_customer_advance' else 'kept_for_adjustment' end
                                                       when 'income' then 'taken_as_income' else 'unknown' end end as advance_state
               from c where (c.cancelled_at at time zone 'Asia/Dhaka')::date between p_from and p_to)
  select (select coalesce(jsonb_agg(jsonb_build_object('ref', '#' || order_no, 'order_id', id, 'loc', location_id, 'customer_name', customer_name, 'channel', channel, 'cancelled_at', cancelled_at at time zone 'Asia/Dhaka',
            'reason', cancel_reason, 'total', total, 'advance', advance, 'advance_fate', advance_fate, 'advance_state', advance_state, 'refund_mode', rmode, 'refund_paid_at', paid_at at time zone 'Asia/Dhaka') order by cancelled_at desc), '[]'::jsonb) from d),
         jsonb_build_object('cancelled', (select count(*) from d), 'cancelled_value', (select coalesce(sum(total), 0) from d), 'advance_total', (select coalesce(sum(advance), 0) from d),
           'refunded', (select coalesce(sum(advance), 0) from d where advance_state = 'refunded'), 'refund_due', (select coalesce(sum(advance), 0) from d where advance_state = 'refund_due'),
           'refund_not_recorded', (select coalesce(sum(advance), 0) from d where advance_state = 'refund_not_recorded'), 'refund_closed_unpaid', (select coalesce(sum(advance), 0) from d where advance_state = 'refund_closed'),
           'kept_as_customer_advance', (select coalesce(sum(advance), 0) from d where advance_state in ('kept_as_customer_advance', 'kept_for_adjustment')), 'taken_as_income', (select coalesce(sum(advance), 0) from d where advance_state = 'taken_as_income'),
           'fate_unknown', (select count(*) from d where advance_state = 'unknown')),
         (select coalesce(jsonb_agg(jsonb_build_object('reason', reason, 'orders', n, 'advance', adv) order by n desc), '[]'::jsonb) from (select coalesce(nullif(lower(btrim(cancel_reason)), ''), '(no reason written)') as reason, count(*) as n, sum(advance) as adv from d group by 1) z)
    into rows, sm, reasons;
  select count(*), count(*) filter (where status = 'cancelled') into created_n, created_c
    from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app';
  select jsonb_build_object('sheets_not_collected', count(*), 'advance', coalesce(sum(adv), 0), 'by_fate', coalesce(jsonb_object_agg(f, n) filter (where f is not null), '{}'::jsonb)) into paper from (
    select coalesce(nullif(x.advance_fate, ''), 'not_written') as f, count(*) as n, sum(x.advance) as adv from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'paper_20_1' and x.status = 'not_collected' group by 1) q;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'record_on', public.rule_on('order_refund_record_on'),
    'notes', public._c2_order_notes(true) || case when public.rule_on('order_refund_record_on') then '[]'::jsonb else '["refund_switch_off"]'::jsonb end,
    'summary', sm || jsonb_build_object('orders_taken_in_range', created_n, 'of_those_cancelled', created_c, 'cancel_rate_pct', case when created_n = 0 then null else round(100.0 * created_c / created_n, 1) end),
    'by_reason', reasons, 'paper_20_1', paper, 'rows', rows);
end $$;

create or replace function public.c2_delivery_cost_report(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost boolean := public.rpt_cost_ok(); rows jsonb; sm jsonb; bykind jsonb; byby jsonb; paper jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select x.* from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and x.delivery_mode in ('home', 'courier')),
       r as (select b.*, case when cost then b.delivery_cost end as cost_x from b)
  select (select coalesce(jsonb_agg(jsonb_build_object('ref', ref, 'order_id', order_id, 'loc', loc, 'order_date', order_date, 'customer_name', customer_name, 'delivery_mode', delivery_mode, 'delivery_by', delivery_by, 'status', status,
            'charge', delivery_charge, 'cost', cost_x, 'margin', case when cost and delivery_cost is not null then delivery_charge - delivery_cost end, 'cost_captured', delivery_cost is not null) order by order_date desc, ref), '[]'::jsonb) from r),
         jsonb_build_object('orders', (select count(*) from b), 'orders_not_cancelled', (select count(*) from b where status <> 'cancelled'), 'delivered', (select count(*) from b where status = 'delivered'),
           'charge_total', (select coalesce(sum(delivery_charge), 0) from b where status <> 'cancelled'),
           'with_cost_captured', case when cost then (select count(*) from b where delivery_cost is not null) end,
           'cost_not_captured', case when cost then (select count(*) from b where delivery_cost is null and status in ('delivered', 'cancelled')) end,
           'cost_total_captured', case when cost then (select sum(delivery_cost) from b) end,
           'charge_where_cost_captured', case when cost then (select sum(delivery_charge) from b where delivery_cost is not null) end,
           'margin_where_cost_captured', case when cost then (select sum(delivery_charge - delivery_cost) from b where delivery_cost is not null) end,
           'avg_cost_per_order_captured', case when cost then (select round(avg(delivery_cost), 2) from b where delivery_cost is not null) end)
    into rows, sm;
  select case when cost then coalesce(jsonb_object_agg(kind, jsonb_build_object('amount', amt, 'rows', n)), '{}'::jsonb) end into bykind from (
    select c.kind, sum(c.amount) as amt, count(*) as n from public.order_delivery_costs c join public._c2_orders_base(p_from, p_to, p_loc, 'order') x on x.order_id = c.order_id and x.source = 'app' and x.delivery_mode in ('home', 'courier')
     where c.state = 'active' group by c.kind) q;
  select case when cost then coalesce(jsonb_agg(jsonb_build_object('delivery_by', coalesce(delivery_by, '(not written)'), 'orders', orders, 'orders_with_cost', wc, 'cost', ct, 'charge', ch) order by orders desc), '[]'::jsonb) end into byby from (
    select x.delivery_by, count(*) as orders, count(*) filter (where x.delivery_cost is not null) as wc, sum(x.delivery_cost) as ct, sum(x.delivery_charge) as ch
      from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and x.delivery_mode in ('home', 'courier') and x.status <> 'cancelled' group by x.delivery_by) q;
  select jsonb_build_object('lines', count(*), 'delivery_charge', sum(delivery_charge), 'lines_without_charge_written', count(*) filter (where delivery_charge is null),
           'by_delivery', coalesce((select jsonb_agg(jsonb_build_object('delivery_by', coalesce(delivery_by, '(not written)'), 'lines', n, 'charge', ch) order by n desc) from (
              select y.delivery_by, count(*) as n, sum(y.delivery_charge) as ch from public._c2_orders_base(p_from, p_to, p_loc, 'order') y where y.source = 'paper_20_6' group by y.delivery_by) g), '[]'::jsonb))
    into paper from public._c2_orders_base(p_from, p_to, p_loc, 'order') z where z.source = 'paper_20_6';
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'),
    'notes', public._c2_order_notes(true) || '"cost_is_information_not_posted"'::jsonb || '"paper_20_6_no_cost_side"'::jsonb, 'summary', sm, 'by_kind', bykind, 'by_delivery_by', byby, 'paper_20_6', paper, 'rows', rows);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
