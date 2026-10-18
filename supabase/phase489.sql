-- Phase 489 (X6) - GROWTH INTELLIGENCE FROM OWN DATA (works today, no provider). Read-only functions. Paste AFTER phase488. Paste-twice safe.
-- Every answer carries its ASSUMPTIONS and its DATA COVERAGE (trading days of each window). A day with no bill is not counted as zero sales.
-- Money and quantities come from sales_fact (status 'done' only, net of returns as the sales screens show them), filtered by can_loc, so a person sees only their places.
-- Correlation is not causation: every result says so in its "warning" text.
-- Access: the market_view / market_manage rights OR the sales report right (rpt_access('sales')). Module switch mi_on is NOT needed to read own-data growth.

do $g$ begin
  if to_regclass('public.sales_fact') is null or to_regprocedure('public._mi_can_view()') is null then raise exception 'phase532 needs phases 531 and 459 first'; end if;
end $g$;

create or replace function public._mi_growth_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public._mi_can_view() or public.rpt_access('sales') $$;

create or replace function public._mi_growth_warning() returns text language sql immutable as $$
  select 'These are past sales patterns. They show what changed, not why. Season, festivals, price, stock, staff and weather can explain them too.' $$;

-- item growth and decline between two windows. growth_pct is blank when the base window had no sales (never a fake percentage).
create or replace function public.mi_growth_items(p_d1 date, p_d2 date, p_c1 date, p_c2 date, p_loc int default null, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; cur_days int; base_days int; cal_cur int := p_d2 - p_d1 + 1; cal_base int := p_c2 - p_c1 + 1;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  if p_d2 < p_d1 or p_c2 < p_c1 then raise exception 'bad_window'; end if;
  select count(distinct day) into cur_days from public.sales_fact where status = 'done' and day between p_d1 and p_d2 and (p_loc is null or location_id = p_loc) and public.can_loc(location_id);
  select count(distinct day) into base_days from public.sales_fact where status = 'done' and day between p_c1 and p_c2 and (p_loc is null or location_id = p_loc) and public.can_loc(location_id);
  select coalesce(jsonb_agg(to_jsonb(z) order by abs(coalesce(z.change_value, 0)) desc, z.item_name), '[]'::jsonb) into rows_ from (
    select coalesce(x.item_id::text, 'quick') as item_id, coalesce(max(x.item_name), 'Quick sale') as item_name, coalesce(max(x.category), '') as category,
           round(sum(case when x.in_cur then x.net else 0 end), 2) as cur_net, round(sum(case when x.in_base then x.net else 0 end), 2) as base_net,
           round(sum(case when x.in_cur then x.net else 0 end) - sum(case when x.in_base then x.net else 0 end), 2) as change_value,
           case when sum(case when x.in_base then x.net else 0 end) > 0
                then round(100 * (sum(case when x.in_cur then x.net else 0 end) - sum(case when x.in_base then x.net else 0 end)) / sum(case when x.in_base then x.net else 0 end), 1) end as growth_pct,
           round(sum(case when x.in_cur then x.qty else 0 end), 2) as cur_qty, round(sum(case when x.in_base then x.qty else 0 end), 2) as base_qty
      from (select f.item_id, f.item_name, f.category, f.net, f.qty, f.day between p_d1 and p_d2 as in_cur, f.day between p_c1 and p_c2 as in_base
              from public.sales_fact f
             where f.status = 'done' and ((f.day between p_d1 and p_d2) or (f.day between p_c1 and p_c2))
               and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id)) x
     group by coalesce(x.item_id::text, 'quick')
     order by abs(sum(case when x.in_cur then x.net else 0 end) - sum(case when x.in_base then x.net else 0 end)) desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200)
  ) z;
  return jsonb_build_object('rows', rows_, 'coverage', jsonb_build_object('current_trading_days', cur_days, 'current_calendar_days', cal_cur,
           'base_trading_days', base_days, 'base_calendar_days', cal_base),
         'assumptions', jsonb_build_array('Net sales of done bills, per window.', 'A blank growth_pct means the base window had no sales of the item.', 'Items with no sales in either window are not listed.'),
         'warning', public._mi_growth_warning());
end $$;

-- outlet comparison: sales per trading day (not per calendar day), so a shop with more closed days is not made to look worse
create or replace function public.mi_outlet_compare(p_d1 date, p_d2 date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  if p_d2 < p_d1 then raise exception 'bad_window'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.net_total desc), '[]'::jsonb) into rows_ from (
    select f.location_id, max(f.location_en) as outlet, count(distinct f.day) as trading_days, count(distinct f.sale_id) as bills,
           round(sum(f.net), 2) as net_total, round(sum(f.net) / nullif(count(distinct f.day), 0), 2) as net_per_trading_day
      from public.sales_fact f
     where f.status = 'done' and f.day between p_d1 and p_d2 and public.can_loc(f.location_id)
     group by f.location_id) z;
  return jsonb_build_object('rows', rows_, 'calendar_days', p_d2 - p_d1 + 1,
    'assumptions', jsonb_build_array('Per trading day = net sales divided by the days that had at least one bill.', 'Outlets with different sizes or products are not like for like.'),
    'warning', public._mi_growth_warning());
end $$;

-- basket analysis: pairs of items that appear on the same bill. support = bills with both / all bills in the window
create or replace function public.mi_basket_pairs(p_d1 date, p_d2 date, p_loc int default null, p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; bills int;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  select count(distinct f.sale_id) into bills from public.sales_fact f where f.status = 'done' and f.day between p_d1 and p_d2 and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id);
  select coalesce(jsonb_agg(to_jsonb(z) order by z.bills_together desc, z.item_a), '[]'::jsonb) into rows_ from (
    select a.item_name as item_a, b.item_name as item_b, count(*) as bills_together,
           round(100.0 * count(*) / nullif(bills, 0), 1) as share_of_bills_pct
      from (select distinct f.sale_id, f.item_id, f.item_name from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between p_d1 and p_d2
             and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id)) a
      join (select distinct f.sale_id, f.item_id, f.item_name from public.sales_fact f where f.status = 'done' and f.item_id is not null and f.day between p_d1 and p_d2
             and (p_loc is null or f.location_id = p_loc) and public.can_loc(f.location_id)) b on b.sale_id = a.sale_id and b.item_id > a.item_id
     group by a.item_name, b.item_name
     order by count(*) desc
     limit least(greatest(coalesce(p_limit, 20), 1), 100)) z;
  return jsonb_build_object('bills', bills, 'rows', rows_,
    'assumptions', jsonb_build_array('Items bought on the same bill. Not a recommendation by itself: check margin and stock before acting.'),
    'warning', 'Bought together is a pattern in past bills. It does not show that one item makes the customer buy the other.');
end $$;

-- price response hint: only when the owner typed the minimum days; only prices with enough trading days are compared
create or replace function public.mi_price_response(p_item uuid, p_d1 date, p_d2 date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mind int := public.rule_num('mi_elast_min_days')::int; levels jsonb; n int; hint text; lv record; parts text[] := '{}';
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  if mind is null then return jsonb_build_object('hint', null, 'why', 'Blank setting: no price-response hint is shown. The owner types the minimum days in settings (mi_elast_min_days).'); end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.price), '[]'::jsonb) into levels from (
    select f.price, count(distinct f.day) as days, round(sum(f.qty) / nullif(count(distinct f.day), 0), 2) as qty_per_trading_day
      from public.sales_fact f where f.status = 'done' and f.item_id = p_item and f.day between p_d1 and p_d2 and public.can_loc(f.location_id)
     group by f.price) z;
  select count(*) into n from jsonb_array_elements(levels) x where (x->>'days')::int >= mind;
  if n < 2 then
    return jsonb_build_object('hint', null, 'levels', levels, 'min_days', mind, 'why', 'Fewer than two prices with at least ' || mind || ' trading days in the window: no hint.');
  end if;
  for lv in select * from jsonb_to_recordset(levels) as x(price numeric, days int, qty_per_trading_day numeric) where days >= mind order by price loop
    parts := parts || (lv.price::text || ': ' || lv.qty_per_trading_day || ' units per trading day over ' || lv.days || ' days');
  end loop;
  hint := 'In this window: ' || array_to_string(parts, ' | ') || '. A past pattern only; a price change is never the only thing that changed.';
  return jsonb_build_object('hint', hint, 'levels', levels, 'min_days', mind,
    'assumptions', jsonb_build_array('Units per trading day at each price actually charged.', 'No cost, competitor or weather effect is modelled.'),
    'warning', public._mi_growth_warning());
end $$;

-- festival uplift review: the owner's festival window against the same number of days just before it (per trading day)
create or replace function public.mi_festival_uplift(p_festival bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fc public.festival_calendar; len int; bf date; bt date; fa numeric; fd int; ba numeric; bd int;
begin
  if not public._mi_growth_ok() then raise exception 'not allowed'; end if;
  select * into fc from public.festival_calendar where id = p_festival;
  if not found then raise exception 'not_found'; end if;
  len := fc.end_date - fc.start_date + 1; bt := fc.start_date - 1; bf := bt - len + 1;
  select coalesce(sum(f.net), 0), count(distinct f.day) into fa, fd from public.sales_fact f
    where f.status = 'done' and f.day between fc.start_date and fc.end_date and (fc.location_id is null or f.location_id = fc.location_id) and public.can_loc(f.location_id);
  select coalesce(sum(f.net), 0), count(distinct f.day) into ba, bd from public.sales_fact f
    where f.status = 'done' and f.day between bf and bt and (fc.location_id is null or f.location_id = fc.location_id) and public.can_loc(f.location_id);
  return jsonb_build_object('festival', fc.name_en, 'festival_bn', fc.name_bn, 'festival_from', fc.start_date, 'festival_to', fc.end_date,
    'comparison_from', bf, 'comparison_to', bt,
    'festival_net_per_trading_day', round(fa / nullif(fd, 0), 2), 'comparison_net_per_trading_day', round(ba / nullif(bd, 0), 2),
    'observed_uplift_pct', case when ba > 0 and bd > 0 and fd > 0 then round(100 * ((fa / fd) - (ba / bd)) / (ba / bd), 1) end,
    'owner_entered_uplift_pct', fc.uplift_pct,
    'coverage', jsonb_build_object('festival_trading_days', fd, 'festival_calendar_days', len, 'comparison_trading_days', bd),
    'assumptions', jsonb_build_array('The comparison is the same number of days just before the festival.', 'The owner uplift % is shown as typed; nothing is guessed.'),
    'warning', public._mi_growth_warning());
end $$;

revoke all on function public._mi_growth_ok(), public._mi_growth_warning(), public.mi_growth_items(date, date, date, date, int, int), public.mi_outlet_compare(date, date),
  public.mi_basket_pairs(date, date, int, int), public.mi_price_response(uuid, date, date), public.mi_festival_uplift(bigint) from public, anon;
grant execute on function public.mi_growth_items(date, date, date, date, int, int), public.mi_outlet_compare(date, date), public.mi_basket_pairs(date, date, int, int),
  public.mi_price_response(uuid, date, date), public.mi_festival_uplift(bigint) to authenticated;

notify pgrst, 'reload schema';
