-- Phase 466 (RPT-C3, package R9 part 2) - PLANNING: production requirement (#186) and recipe-exploded raw material purchase forecast (#187).
-- Paste AFTER phase465. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   fc_production_requirement  for ONE place: finished goods that have an active recipe. Expected demand over the horizon (phase465 item forecast: same-weekday average, low/high range)
--                              + open online orders due inside the horizon - stock on hand = what to make. Shown as units and as recipe batches. Two columns, because the average
--                              already contains past order sales: "without orders" and "with open orders on top" (the person chooses; the page says the second may count some demand twice).
--   fc_raw_purchase            the same quantities pushed through the recipes (waste % included, like production preview): ingredient need, stock on hand, shortfall, lead days
--                              (setting reorder_lead_days) and, only for people who may see costs, the cost at the chosen costing method. Ingredients with no cost are counted, not priced.
-- Assumptions are returned with every answer. Nothing is posted or ordered. Access: rpt_access('stock'); item demand also needs a sales or stock report right. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.fc_item_demand(integer,integer,integer,boolean,integer)') is null then raise exception 'phase466 needs phase465 first'; end if;
end $g$;

create or replace function public.fc_production_requirement(p_loc int, p_ahead int, p_window int default null, p_basis text default 'expected') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare dem jsonb; td date := public._c3_today(); rows_ jsonb; norec jsonb; n_undated bigint; basis text := coalesce(p_basis, 'expected');
begin
  perform public._c3_need('stock');
  if p_loc is null or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if basis not in ('expected', 'high') then raise exception 'bad_basis'; end if;
  dem := public.fc_item_demand(p_loc, p_ahead, p_window, false, 2000);
  if dem ? 'data_needed' then return dem || jsonb_build_object('key', 'fc_production'); end if;
  with d as (select (x ->> 'item_id')::uuid as item_id, (x ->> 'expected')::numeric as e, (x ->> 'low')::numeric as lo, (x ->> 'high')::numeric as hi, (x ->> 'on_hand')::numeric as oh
               from jsonb_array_elements(dem -> 'rows') x),
  o as (select (l ->> 'item_id')::uuid as item_id, sum(public._base_qty((l ->> 'item_id')::uuid, (l ->> 'qty')::numeric, i.unit)) as q, count(*) filter (where public._base_qty((l ->> 'item_id')::uuid, (l ->> 'qty')::numeric, i.unit) is null) as bad
          from public.online_orders oo cross join lateral jsonb_array_elements(oo.lines) l join public.items i on i.id = (l ->> 'item_id')::uuid
         where oo.location_id = p_loc and oo.status in ('new', 'confirmed', 'packed') and oo.delivery_date between td and td + p_ahead - 1 group by 1),
  rc as (select distinct on (r.item_id) r.item_id, r.id as recipe_id, r.version, public._base_qty(r.item_id, r.yield_qty, r.yield_unit) as yb from public.recipes r where r.active order by r.item_id, r.version desc),
  j as (select coalesce(d.item_id, o.item_id) as item_id, d.e, d.lo, d.hi, coalesce(o.q, 0) as oq, o.bad, coalesce(d.oh, (select sum(b.qty) from public.stock_balance b where b.item_id = coalesce(d.item_id, o.item_id) and b.location_id = p_loc), 0) as oh
          from d full join o on o.item_id = d.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(i.id), 'recipe_id', rc.recipe_id, 'recipe_version', rc.version,
           'yield_per_batch', rc.yb, 'demand_expected', round(j.e, 3), 'demand_low', round(j.lo, 3), 'demand_high', round(j.hi, 3), 'open_orders', round(j.oq, 3), 'orders_unit_problem', coalesce(j.bad, 0),
           'on_hand', round(j.oh, 3),
           'to_make', case when j.e is null and j.oq = 0 then null else round(greatest((case when basis = 'high' then j.hi else j.e end) - j.oh, 0), 3) end,
           'to_make_with_orders', case when j.e is null and j.oq = 0 then null else round(greatest(coalesce(case when basis = 'high' then j.hi else j.e end, 0) + j.oq - j.oh, 0), 3) end,
           'batches', case when rc.yb > 0 and j.e is not null then round(greatest((case when basis = 'high' then j.hi else j.e end) - j.oh, 0) / rc.yb, 3) end,
           'batches_with_orders', case when rc.yb > 0 then round(greatest(coalesce(case when basis = 'high' then j.hi else j.e end, 0) + j.oq - j.oh, 0) / rc.yb, 3) end,
           'batches_whole_with_orders', case when rc.yb > 0 then ceil(greatest(coalesce(case when basis = 'high' then j.hi else j.e end, 0) + j.oq - j.oh, 0) / rc.yb) end,
           'no_demand_history', j.e is null) order by i.code), '[]'::jsonb)
    into rows_ from j join rc on rc.item_id = j.item_id join public.items i on i.id = j.item_id;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'name_en', i.name_en)), '[]'::jsonb) into norec
    from jsonb_array_elements(dem -> 'rows') x join public.items i on i.id = (x ->> 'item_id')::uuid
   where not exists (select 1 from public.recipes r where r.item_id = i.id and r.active);
  select count(*) into n_undated from public.online_orders oo where oo.location_id = p_loc and oo.status in ('new', 'confirmed', 'packed') and oo.delivery_date is null;
  return jsonb_build_object('key', 'fc_production', 'loc', p_loc, 'ahead', p_ahead, 'basis', basis, 'rows', rows_, 'sold_without_recipe', norec, 'assumptions', dem -> 'assumptions' ||
      jsonb_build_object('orders_counted', 'online orders new / confirmed / packed with a delivery date inside the horizon', 'orders_without_a_date_not_counted', n_undated, 'recipe', 'the active recipe with the highest version'),
    'notes', dem -> 'notes' || jsonb_build_array('orders_on_top_may_count_some_demand_twice', 'stock_on_hand_is_this_place_only', 'items_without_a_recipe_listed_apart', 'nothing_is_ordered_or_produced_by_this_report'),
    'basis_text', 'What to make = ' || case when basis = 'high' then 'the HIGH past same-weekday demand' else 'the expected (average) demand' end || ' over the horizon, minus stock on hand; the second column adds open orders due in the horizon.');
end $$;

create or replace function public.fc_raw_purchase(p_loc int, p_ahead int, p_window int default null, p_basis text default 'expected', p_with_orders boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare prod jsonb; cost_ok boolean := public.rpt_cost_ok(); lead numeric := public.rule_num('reorder_lead_days'); rows_ jsonb; tot numeric; uncosted int; bad_units int;
begin
  perform public._c3_need('stock');
  prod := public.fc_production_requirement(p_loc, p_ahead, p_window, p_basis);
  if prod ? 'data_needed' then return prod || jsonb_build_object('key', 'fc_raw'); end if;
  with pr as (select (x ->> 'recipe_id')::uuid as recipe_id, x ->> 'code' as fg_code,
                     coalesce(case when p_with_orders then (x ->> 'batches_with_orders')::numeric else (x ->> 'batches')::numeric end, 0) as b
                from jsonb_array_elements(prod -> 'rows') x),
  n as (select pr.fg_code, pr.b, rn.* from pr cross join lateral public._recipe_need(pr.recipe_id, pr.b, p_loc) rn where pr.b > 0),
  a as (select n.item_id, n.code, n.name_bn, n.name_en, n.base_unit, n.kind, sum(n.need) as need, max(n.on_hand) as oh, bool_and(n.unit_ok) as unit_ok, bool_or(n.waste_missing) as wm, bool_and(n.tracked) as tracked,
               jsonb_agg(jsonb_build_object('product', n.fg_code, 'batches', round(n.b, 3), 'need', n.need) order by n.fg_code) as used_by
          from n group by n.item_id, n.code, n.name_bn, n.name_en, n.base_unit, n.kind),
  c as (select a.*, case when cost_ok then public._d_material_cost(a.item_id, p_loc) end as uc from a)
  select coalesce(jsonb_agg(jsonb_build_object('item_id', c.item_id, 'code', c.code, 'name_bn', c.name_bn, 'name_en', c.name_en, 'kind', c.kind, 'base_unit', c.base_unit, 'need', round(c.need, 3), 'on_hand', round(c.oh, 3),
           'shortfall', round(greatest(c.need - c.oh, 0), 3), 'lead_days', lead, 'unit_cost', round(c.uc, 4), 'est_cost', case when c.uc is not null then round(greatest(c.need - c.oh, 0) * c.uc, 2) end,
           'unit_problem', not c.unit_ok, 'waste_percent_missing', c.wm, 'stock_not_tracked', not c.tracked, 'used_by', c.used_by) order by (greatest(c.need - c.oh, 0) = 0), c.code), '[]'::jsonb),
         round(sum(greatest(c.need - c.oh, 0) * c.uc), 2), count(*) filter (where cost_ok and c.uc is null and greatest(c.need - c.oh, 0) > 0), count(*) filter (where not c.unit_ok)
    into rows_, tot, uncosted, bad_units from c;
  return jsonb_build_object('key', 'fc_raw', 'loc', p_loc, 'ahead', p_ahead, 'basis', p_basis, 'with_orders', coalesce(p_with_orders, false), 'rows', rows_,
    'totals', jsonb_build_object('estimated_cost_of_shortfall', case when cost_ok then tot end, 'shortfall_items_without_a_cost', case when cost_ok then uncosted end, 'items_with_unit_problem', bad_units),
    'assumptions', prod -> 'assumptions' || jsonb_build_object('lead_days_setting', lead, 'cost_method', coalesce(public.rule_txt('d_material_cost_method'), 'average_purchase')),
    'notes', prod -> 'notes' || jsonb_build_array('need_includes_recipe_waste_percent', 'waste_percent_missing_means_zero_waste_was_used_and_is_flagged', 'stock_on_hand_counted_once_per_ingredient', 'no_supplier_order_is_placed') ||
             case when lead is null then jsonb_build_array('lead_days_not_set') else '[]'::jsonb end || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis_text', 'Finished-goods quantities from the production requirement, exploded through each active recipe, summed per ingredient, less stock on hand.');
end $$;

revoke all on function public.fc_production_requirement(int, int, int, text), public.fc_raw_purchase(int, int, int, text, boolean) from public, anon;
grant execute on function public.fc_production_requirement(int, int, int, text), public.fc_raw_purchase(int, int, int, text, boolean) to authenticated;
notify pgrst, 'reload schema';
