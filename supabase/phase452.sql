-- ============================================================
-- Phase 452 - RPT-C2 / R4 part 8 (reports #160 order-wise production and material cost, #161 order profitability). READ for the reports; one small capture: the ORDER on a production run.
-- Run AFTER phase 451. New file only. Paste twice = no error.
--
--   production_run_orders   links a production run to an app order (a run can serve several orders; an order can use several runs). qty = how much of the run's output is for that order (blank is
--                           allowed only when the run has this one link: then the whole run belongs to the order). Append-only: a wrong link is VOIDED with a reason.
--   c2_production_link_order / c2_production_link_void   write. Allowed: owner, the stock_production right at the run's place, or a POS-enter person at the order's place. Module online_orders_on needed.
--   c2_orders_for_production(place)   the open app orders a factory person may pick from (order number, customer name, delivery day, cake summary - no mobile number, no money).
--   c2_order_production_cost(from, to, place, order)   #160   cost of each linked run share: material and conversion cost split by quantity. Costs that the run could not know (cost_complete false) are
--                           shown as "cost not complete", never as 0. Needs the cost right.
--   c2_order_profit(from, to, place)   #161   delivered app orders: sale value - cost of the goods sold (stock ledger at the time of the sale) - the delivery cost written. A profit is shown ONLY when every
--                           part is known; otherwise the row lists what is missing. Pickup orders need no delivery cost. A sale with returns is not judged (the goods cost of returned items is not reversed here).
--                           Needs the cost right. The linked production cost is shown beside it for comparison and is NOT subtracted again (the goods cost is already in the sale cost).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_delivery_cost_report(date,date,int)') is null then raise exception 'phase452 needs phase451 pasted first'; end if;
end $guard$;

create table if not exists public.production_run_orders (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.production_runs(id),
  order_id uuid not null references public.online_orders(id),
  qty numeric check (qty is null or (qty > 0 and qty <= 1000000000)),
  note text check (note is null or char_length(note) <= 300),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists production_run_orders_live on public.production_run_orders (run_id, order_id) where state = 'active';
create index if not exists production_run_orders_order on public.production_run_orders (order_id) where state = 'active';
drop trigger if exists production_run_orders_ro on public.production_run_orders;
create trigger production_run_orders_ro before update or delete on public.production_run_orders for each row execute function public._c2_trail_ro();
drop trigger if exists audit_production_run_orders on public.production_run_orders;
create trigger audit_production_run_orders after insert or update on public.production_run_orders for each row execute function public.log_change('id');

create or replace function public.c2_production_link_order(p_run uuid, p_order uuid, p_qty numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; o public.online_orders; id_ bigint; q numeric := case when p_qty is null then null else round(p_qty, 4) end;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not_found'; end if;
  select * into o from public.online_orders where id = p_order for update;
  if not found then raise exception 'not_found'; end if;
  if not public.rule_on('online_orders_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.has_grant('stock_production', r.location_id) or (public.can_do('POS', 'enter') and public.can_loc(o.location_id))) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void: a voided production run cannot be linked'; end if;
  if q is not null and (q = 'NaN'::numeric or q <= 0) then raise exception 'bad_qty'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long'; end if;
  if exists (select 1 from public.production_run_orders where run_id = r.id and order_id = o.id and state = 'active') then return jsonb_build_object('run_id', r.id, 'order_id', o.id, 'noop', true); end if;
  if q is not null and q + coalesce((select sum(x.qty) from public.production_run_orders x where x.run_id = r.id and x.state = 'active'), 0) > r.yield_base then
    raise exception 'qty_over_output: the quantities linked to this run would be more than the run made (%)', r.yield_base;
  end if;
  insert into public.production_run_orders (run_id, order_id, qty, note, created_by, created_staff) values (r.id, o.id, q, left(nullif(btrim(p_note), ''), 300), auth.uid(), public._c2_staff()) returning id into id_;
  perform public._oo_event61(o.id, o.status, o.status, 'production run linked' || coalesce(' (' || q::text || ')', ''));
  return jsonb_build_object('id', id_, 'run_id', r.id, 'order_id', o.id, 'qty', q);
end $$;

create or replace function public.c2_production_link_void(p_link bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_run_orders; r public.production_runs; o public.online_orders;
begin
  select * into l from public.production_run_orders where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  select * into r from public.production_runs where id = l.run_id; select * into o from public.online_orders where id = l.order_id;
  if not public.rule_on('online_orders_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.has_grant('stock_production', r.location_id) or (public.can_do('POS', 'enter') and public.can_loc(o.location_id))) then raise exception 'not allowed'; end if;
  if l.state = 'void' then return jsonb_build_object('id', l.id, 'noop', true); end if;
  if nullif(btrim(p_note), '') is null or char_length(p_note) > 300 then raise exception 'reason_required'; end if;
  update public.production_run_orders set state = 'void', void_by = auth.uid(), void_at = now(), void_note = btrim(p_note) where id = l.id;
  perform public._oo_event61(o.id, o.status, o.status, 'production run link voided: ' || btrim(p_note));
  return jsonb_build_object('id', l.id, 'state', 'void');
end $$;

-- the open orders a factory person can pick from (no mobile number, no money)
create or replace function public.c2_orders_for_production(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('stock_production') or public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('module_on', public.rule_on('online_orders_on'), 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('order_id', o.id, 'order_no', o.order_no, 'loc', o.location_id, 'customer_name', o.customer_name, 'status', o.status, 'delivery_date', o.delivery_date,
             'slot_from', pr.slot_from, 'slot_to', pr.slot_to, 'cake', exists (select 1 from public.order_cake_specs c where c.order_id = o.id and c.state = 'active')) order by o.delivery_date nulls last, o.order_no)
      from public.online_orders o left join lateral (select x.slot_from, x.slot_to from public.order_promises x where x.order_id = o.id and x.state = 'active' order by x.id desc limit 1) pr on true
     where o.status in ('new', 'confirmed', 'packed') and (p_loc is null or o.location_id = p_loc)), '[]'::jsonb));
end $$;

-- #160 cost of the production linked to orders
create or replace function public.c2_order_production_cost(p_from date, p_to date, p_loc int default null, p_order uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost boolean := public.rpt_cost_ok(); rows jsonb; per jsonb; nolink int;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with b as (select x.order_id, x.ref, x.order_date, x.customer_name, x.status, x.loc, x.promised_date from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and (p_order is null or x.order_id = p_order)),
       l as (select b.*, k.id as link_id, k.qty as link_qty, r.id as run_id, r.status as run_status, (r.made_at at time zone 'Asia/Dhaka')::date as made_on, r.location_id as run_loc, r.item_id, it.code, it.name_bn, it.name_en,
                    r.yield_base, r.material_cost, r.conversion_cost, r.unit_cost, r.cost_complete, r.conversion_complete,
                    (select count(*) from public.production_run_orders k2 where k2.run_id = r.id and k2.state = 'active') as links_on_run
               from b join public.production_run_orders k on k.order_id = b.order_id and k.state = 'active' join public.production_runs r on r.id = k.run_id join public.items it on it.id = r.item_id),
       a as (select l.*, case when l.link_qty is not null then l.link_qty when l.links_on_run = 1 then l.yield_base end as qty_used from l)
  select coalesce(jsonb_agg(jsonb_build_object('order_ref', ref, 'order_id', order_id, 'customer_name', customer_name, 'order_status', status, 'link_id', link_id, 'run_id', run_id, 'made_on', made_on, 'run_loc', run_loc,
            'item_code', code, 'item_name_bn', name_bn, 'item_name_en', name_en, 'run_output', yield_base, 'qty_for_order', qty_used,
            'share_pct', case when qty_used is not null and yield_base > 0 then round(100.0 * qty_used / yield_base, 1) end,
            'allocation_known', qty_used is not null, 'run_void', run_status = 'void',
            'material_cost', case when cost and run_status = 'done' and qty_used is not null and yield_base > 0 and material_cost is not null then round(material_cost * qty_used / yield_base, 2) end,
            'conversion_cost', case when cost and run_status = 'done' and qty_used is not null and yield_base > 0 and conversion_cost is not null then round(conversion_cost * qty_used / yield_base, 2) end,
            'cost_complete', coalesce(cost_complete, false) and coalesce(conversion_complete, true)) order by order_date desc, ref, made_on), '[]'::jsonb) into rows from a;
  select coalesce(jsonb_agg(y.x order by y.rf), '[]'::jsonb) into per from (
    with b as (select x.order_id, x.ref from public._c2_orders_base(p_from, p_to, p_loc, 'order') x where x.source = 'app' and (p_order is null or x.order_id = p_order)),
         z as (select b.order_id, b.ref, r.status as run_status, r.yield_base, r.material_cost, r.conversion_cost, r.cost_complete,
                      case when k.qty is not null then k.qty when (select count(*) from public.production_run_orders k2 where k2.run_id = r.id and k2.state = 'active') = 1 then r.yield_base end as qty_used
                 from b join public.production_run_orders k on k.order_id = b.order_id and k.state = 'active' join public.production_runs r on r.id = k.run_id)
    select min(z.ref) as rf, jsonb_build_object('order_id', z.order_id, 'order_ref', min(z.ref), 'runs', count(*),
             'material_cost', case when cost and bool_and(z.material_cost is not null and z.qty_used is not null and z.run_status = 'done') then round(sum(z.material_cost * z.qty_used / nullif(z.yield_base, 0)), 2) end,
             'conversion_cost', case when cost and bool_and(z.conversion_cost is not null and z.qty_used is not null and z.run_status = 'done') then round(sum(z.conversion_cost * z.qty_used / nullif(z.yield_base, 0)), 2) end,
             'complete', bool_and(coalesce(z.cost_complete, false) and z.qty_used is not null and z.run_status = 'done')) as x
      from z group by z.order_id) y;
  select count(*) into nolink from public._c2_orders_base(p_from, p_to, p_loc, 'order') x
   where x.source = 'app' and x.has_spec and x.status <> 'cancelled' and not exists (select 1 from public.production_run_orders k where k.order_id = x.order_id and k.state = 'active');
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(false) || '"run_cost_split_by_quantity"'::jsonb,
    'cake_orders_without_a_linked_run', nolink, 'per_order', per, 'rows', rows);
end $$;

-- #161 order profitability (delivered app orders, by the day of delivery)
create or replace function public.c2_order_profit(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare cost boolean := public.rpt_cost_ok(); rows jsonb; sm jsonb;
begin
  if not public.c2_can_read_orders() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with o as (
    select o.id, o.order_no, o.location_id, o.customer_name, o.delivery_mode, o.delivery_charge, s.id as sale_id, s.receipt, s.status as sale_status, s.total as revenue, (o.delivered_at at time zone 'Asia/Dhaka')::date as delivered_on,
           (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text) as ledger_rows,
           (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text and coalesce(l.unit_cost, 0) <= 0) as ledger_no_cost,
           (select sum(-l.qty_delta * l.unit_cost) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = s.id::text) as goods_cost,
           (select sum(c.amount) from public.order_delivery_costs c where c.order_id = o.id and c.state = 'active') as delivery_cost,
           (select coalesce(sum(r.amount), 0) from public.sale_returns r where r.sale_id = s.id and r.status = 'done') as returns,
           (select case when count(*) = 0 or count(*) filter (where public._c2_run_alloc(k.id) is null) > 0 then null else sum(public._c2_run_alloc(k.id)) end from public.production_run_orders k where k.order_id = o.id and k.state = 'active') as linked_production_cost
      from public.online_orders o join public.sales s on s.id = o.sale_id
     where o.status = 'delivered' and public.can_loc(o.location_id) and (p_loc is null or o.location_id = p_loc) and (o.delivered_at at time zone 'Asia/Dhaka')::date between p_from and p_to),
       p as (select o.*, array_remove(array[case when o.ledger_rows = 0 or o.ledger_no_cost > 0 then 'goods_cost' end,
                                            case when o.delivery_mode in ('home', 'courier') and o.delivery_cost is null then 'delivery_cost' end,
                                            case when o.sale_status = 'void' then 'sale_voided' end,
                                            case when o.returns > 0 then 'sale_has_returns' end], null) as missing from o)
  select coalesce(jsonb_agg(jsonb_build_object('ref', '#' || order_no, 'order_id', id, 'loc', location_id, 'customer_name', customer_name, 'delivery_mode', delivery_mode, 'delivered_on', delivered_on, 'receipt', receipt, 'revenue', revenue,
            'goods_cost', case when cost then goods_cost end, 'delivery_cost', case when cost then case when delivery_mode = 'pickup' then coalesce(delivery_cost, 0) else delivery_cost end end,
            'linked_production_cost', case when cost then linked_production_cost end,
            'profit', case when cost and cardinality(missing) = 0 then revenue - goods_cost - coalesce(delivery_cost, 0) end,
            'missing', case when cost then to_jsonb(missing) else '["cost_hidden"]'::jsonb end) order by delivered_on desc, order_no), '[]'::jsonb),
         jsonb_build_object('delivered_orders', count(*), 'revenue_all', coalesce(sum(revenue), 0),
           'orders_with_every_cost_known', case when cost then count(*) filter (where cardinality(missing) = 0) end,
           'orders_with_something_missing', case when cost then count(*) filter (where cardinality(missing) > 0) end,
           'revenue_of_full_cost_orders', case when cost then sum(revenue) filter (where cardinality(missing) = 0) end,
           'profit_of_full_cost_orders', case when cost then sum(revenue - goods_cost - coalesce(delivery_cost, 0)) filter (where cardinality(missing) = 0) end,
           'margin_pct_of_full_cost_orders', case when cost and sum(revenue) filter (where cardinality(missing) = 0) > 0 then round(100.0 * sum(revenue - goods_cost - coalesce(delivery_cost, 0)) filter (where cardinality(missing) = 0) / sum(revenue) filter (where cardinality(missing) = 0), 1) end)
    into rows, sm from p;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', public._c2_order_notes(false) || '"profit_only_when_every_cost_known"'::jsonb || '"linked_production_not_subtracted"'::jsonb,
    'summary', sm, 'rows', rows);
end $$;

-- the allocated total cost (material + conversion) of one production link; null when it cannot be known
create or replace function public._c2_run_alloc(p_link bigint) returns numeric language sql stable security definer set search_path = public as $$
  select case when r.status <> 'done' or r.material_cost is null or r.yield_base <= 0 then null
              else round((r.material_cost + coalesce(r.conversion_cost, 0)) * coalesce(k.qty, case when (select count(*) from public.production_run_orders k2 where k2.run_id = r.id and k2.state = 'active') = 1 then r.yield_base end) / r.yield_base, 2) end
    from public.production_run_orders k join public.production_runs r on r.id = k.run_id where k.id = p_link;
$$;

alter table public.production_run_orders enable row level security;
revoke all on public.production_run_orders from public, anon, authenticated;
grant select on public.production_run_orders to authenticated;
drop policy if exists production_run_orders_sel on public.production_run_orders;
create policy production_run_orders_sel on public.production_run_orders for select to authenticated using (public.c2_can_read_orders() and public.c2_order_visible(order_id));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
