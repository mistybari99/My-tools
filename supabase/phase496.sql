-- Phase 496 (XC-3) - SUPPLIER PRICE INTELLIGENCE: last price, 90-day trend, cheapest supplier, costliest ingredients, rise alerts and a recipe-cost preview.
-- Paste AFTER phase551. Paste-twice safe. Earlier phase files are not edited. It does NOT duplicate the purchase-rate trend report (p2_rate_trend, phase434): it links to it.
-- Prices are costs: readable only by the owner, the cost right (rpt_cost_ok) or the recipe-cost right. Browsers never read the tables directly.
-- OFF by default: switch xc_price_alert_on (false). The rise threshold xc_price_rise_pct is BLANK by default: with it blank the alert says "threshold not set" and writes nothing.
-- The alert compares the latest purchase rate of an item from a supplier with the one before it (the same supplier), inside the last 90 days. An alert is an in-app warning only.
-- The recipe preview changes ONE ingredient price on paper and shows the change per batch and per unit. It saves nothing.

do $g$ begin
  if to_regprocedure('public._p26_rates(date,date,integer[])') is null then raise exception 'phase552 needs phase434 (purchase rates)'; end if;
  if to_regprocedure('public._recipe_need(uuid,numeric,integer)') is null then raise exception 'phase552 needs phase74 (recipe need)'; end if;
  if to_regprocedure('public._notif_add(text,text,text,text,text,text,text,text,text,integer)') is null then raise exception 'phase552 needs the notifications helper'; end if;
end $g$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'xc', v.kind, v.dv, v.unit, null, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('xc_price_alert_on', 'switch', 'false'::jsonb, null::text, null::numeric, null::numeric,
   'ক্রয়মূল্য বৃদ্ধির সতর্কতা / Supplier price-rise alert: on', 'Writes an in-app warning when a purchase rate rises by more than the threshold below. OFF = nothing is checked.', 9520),
 ('xc_price_rise_pct', 'number', null::jsonb, '%', 1::numeric, 500::numeric,
   'কত % বাড়লে সতর্কতা (ফাঁকা = সেট নেই) / Rise % that triggers the alert (blank = not set)', 'Blank = "threshold not set" and nothing is written. Nothing is assumed.', 9521)
  ) as v(key, kind, dv, unit, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- one place of truth for "the rates of the last 90 days" (all places; the cost right decides who reads)
create or replace function public._xc_rates90() returns table (item_id uuid, supplier text, dt date, rate numeric, qty numeric, ord text)
language sql stable security definer set search_path = public as $$
  select r.item_id, r.sname, r.dt, r.rate, r.qty, r.ord from public._p26_rates(public._today() - 90, public._today(), array(select l.id from public.locations l)) r;
$$;

-- the price board (read only). Owner, or a holder of the cost right.
create or replace function public.xc_price_board(p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; sup jsonb;
begin
  if not (public.is_owner() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  with r as (select * from public._xc_rates90()),
  per_sup as (   -- per item and supplier: last rate, the rate before it, first rate, last date, count
    select r.item_id, r.supplier,
           (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           (array_agg(r.rate order by r.dt desc, r.ord desc))[2] as prev_rate,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate,
           max(r.dt) as last_date, count(*) as n
      from r group by r.item_id, r.supplier),
  cheapest as (select distinct on (item_id) item_id, supplier as cheapest_supplier, last_rate as cheapest_rate
                 from per_sup order by item_id, last_rate asc, supplier),
  spend as (select item_id, sum(qty * rate) as spend90, sum(qty) as qty90 from r group by item_id),
  itm as (select ps.item_id, sum(ps.n) as n, max(ps.last_date) as last_date,
                 (select p.last_rate from per_sup p where p.item_id = ps.item_id order by p.last_date desc limit 1) as last_rate,
                 (select p.supplier from per_sup p where p.item_id = ps.item_id order by p.last_date desc limit 1) as last_supplier,
                 (select r2.rate from r r2 where r2.item_id = ps.item_id order by r2.dt, r2.ord limit 1) as first_rate
            from per_sup ps group by ps.item_id)
  select coalesce(jsonb_agg(jsonb_build_object('item_code', i.code, 'item_name', coalesce(i.name_en, i.name_bn), 'base_unit', i.base_unit,
      'last_rate', round(x.last_rate, 4), 'last_supplier', x.last_supplier, 'last_date', x.last_date,
      'trend_90d_pct', case when x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end,
      'cheapest_supplier', c.cheapest_supplier, 'cheapest_rate', round(c.cheapest_rate, 4),
      'spend_90d', round(s.spend90, 2), 'qty_90d', round(s.qty90, 3), 'purchase_lines', x.n,
      'see', '#/report/p2_rate_trend')
      order by s.spend90 desc nulls last), '[]'::jsonb)
    into rows_
    from itm x join public.items i on i.id = x.item_id left join cheapest c on c.item_id = x.item_id left join spend s on s.item_id = x.item_id
   where x.last_rate is not null;
  return jsonb_build_object('window_days', 90,
    'items', coalesce(rows_, '[]'::jsonb), 'costliest_by_last_rate', (select coalesce(jsonb_agg(z), '[]'::jsonb) from (select e ->> 'item_name' as item_name, e ->> 'last_rate' as last_rate, e ->> 'base_unit' as base_unit
       from jsonb_array_elements(coalesce(rows_, '[]'::jsonb)) e order by (e ->> 'last_rate')::numeric desc nulls last limit greatest(least(coalesce(p_limit, 50), 200), 1)) z),
    'notes', jsonb_build_array('Costs: last purchase rate per base unit. Spend = quantity x rate over the 90 days.',
      'Trend = last rate against the first rate in the window (not a forecast).', 'Full history: the purchase-rate trend report (p2_rate_trend).'));
end $$;

-- the alert scan: latest rate against the previous rate of the SAME supplier, last 90 days; one warning per item and supplier per day
create or replace function public.xc_price_alert_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare thr numeric := public.rule_num('xc_price_rise_pct'); n int := 0; x record; k text;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('xc_price_alert_on') then return jsonb_build_object('skipped', 'switch_off'); end if;
  if thr is null then return jsonb_build_object('skipped', 'threshold_not_set'); end if;
  for x in
    with r as (select * from public._xc_rates90()),
    ps as (select r.item_id, r.supplier, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[2] as prev_rate,
                  max(r.dt) as last_date from r group by r.item_id, r.supplier having count(*) >= 2)
    select ps.item_id, ps.supplier, ps.last_rate, ps.prev_rate, round((ps.last_rate - ps.prev_rate) / ps.prev_rate * 100, 2) as pct, i.code, coalesce(i.name_en, i.name_bn) as nm
      from ps join public.items i on i.id = ps.item_id
     where ps.prev_rate > 0 and (ps.last_rate - ps.prev_rate) / ps.prev_rate * 100 > thr
  loop
    k := left(x.code || '|' || x.supplier, 80);
    if not p_dry then
      perform public._notif_add('price_rise', 'warn', 'ক্রয়মূল্য বেড়েছে: ' || x.nm, 'Purchase price rose: ' || x.nm,
        x.supplier || ' থেকে ' || x.prev_rate || ' থেকে ' || x.last_rate || ' (' || x.pct || '%)।',
        'From ' || x.supplier || ': ' || x.prev_rate || ' to ' || x.last_rate || ' (' || x.pct || '%).',
        '#/report/p2_rate_trend', k, 'owner', null);
    end if;
    n := n + 1;
  end loop;
  return jsonb_build_object('alerts', n, 'threshold_pct', thr, 'dry', p_dry);
end $$;

-- the recipe-cost preview: one ingredient at a new price, on paper (saves nothing)
create or replace function public.xc_recipe_price_preview(p_recipe uuid, p_item uuid, p_new_rate numeric) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare need_ numeric; yb numeric; cur numeric; batch_now jsonb; delta numeric;
begin
  if not (public._recipe_cost_ok() or public.rpt_cost_ok()) then raise exception 'not allowed'; end if;
  if p_new_rate is null or p_new_rate < 0 or p_new_rate > 1000000000 then raise exception 'bad_value'; end if;
  select n.need into need_ from public._recipe_need(p_recipe, 1, 0) n where n.item_id = p_item limit 1;
  if need_ is null then return jsonb_build_object('ingredient_in_recipe', false); end if;
  select public._base_qty(rc.item_id, rc.yield_qty, rc.yield_unit) into yb from public.recipes rc where rc.id = p_recipe;
  select (x ->> 'last_rate')::numeric into cur from jsonb_array_elements((public.xc_price_board(1000)) -> 'items') x where x ->> 'item_code' = (select code from public.items where id = p_item);
  if public._recipe_cost_ok() then select public.recipe_cost(p_recipe, null) into batch_now; end if;
  delta := need_ * (p_new_rate - coalesce(cur, 0));
  return jsonb_build_object('ingredient_in_recipe', true, 'need_base_per_batch', round(need_, 4), 'current_rate', cur, 'new_rate', p_new_rate,
    'batch_cost_now', case when batch_now is not null then batch_now -> 'batch_cost' end, 'batch_change', case when cur is not null then round(delta, 4) end,
    'unit_change', case when cur is not null and yb > 0 then round(delta / yb, 6) end, 'yield_base', yb,
    'note', 'Preview only: nothing is saved. Uses the last purchase rate as the current price.');
end $$;

do $c$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_xc_rates90') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $c$;
revoke all on function public.xc_price_board(int) from public, anon;
revoke all on function public.xc_price_alert_scan(boolean) from public, anon;
revoke all on function public.xc_recipe_price_preview(uuid, uuid, numeric) from public, anon;
grant execute on function public.xc_price_board(int) to authenticated;
grant execute on function public.xc_price_alert_scan(boolean) to authenticated;
grant execute on function public.xc_recipe_price_preview(uuid, uuid, numeric) to authenticated;

notify pgrst, 'reload schema';
