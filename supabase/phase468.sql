-- Phase 468 (RPT-C3, package R9 part 4) - PLANNING: sales and profit what-if scenarios (#192) and seasonal / festival demand analysis (#193).
-- Paste AFTER phase467. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   fc_scenario   starts from what really happened in a chosen period (the management profit view's own building blocks: net sales, the costed part and its cost, vouchers, salary, fixed cost) and
--                 applies the percent changes the PERSON types: volume, price, unit cost, expenses, salary, fixed cost. No percent is suggested or assumed (all blank = the baseline unchanged).
--                 Costs of goods move with volume and unit cost only. The "result after costs" appears ONLY when every part is captured (costed share 100%, vouchers, salary and fixed cost all
--                 present); otherwise it is blank and the missing parts are named. A scenario is arithmetic on the owner's numbers, not a forecast.
--   fc_seasonal   for each past festival the owner entered: sales per trading day during it against the sales per trading day of the ordinary trading days in the N days before it (N is typed),
--                 the observed difference in %, and the uplift the owner entered for comparison; the same festival in several years is grouped. Plus sales by month with trading days, so the
--                 yearly pattern is visible. Observed differences are history, not promises; the number of days behind each figure is always shown.
-- Access: scenario rpt_access('profit') (costs also need rpt_cost_ok); seasonal rpt_access('sales'). Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.fc_expiry_risk(integer,integer,integer)') is null then raise exception 'phase468 needs phase467 first'; end if;
end $g$;

create or replace function public.fc_scenario(p_loc int, p_from date, p_to date, p_inputs jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; cost_ok boolean := public.rpt_cost_ok(); k text; v text; inp jsonb := coalesce(p_inputs, '{}'::jsonb); vol numeric := 0; prc numeric := 0; cst numeric := 0; exp_ numeric := 0; sal numeric := 0; fix numeric := 0;
        b record; lines_ jsonb := '[]'; miss jsonb := '[]'; n2 numeric; c2 numeric; g2 numeric; e2 numeric; s2 numeric; f2 numeric; res0 numeric; res1 numeric; full_cost boolean;
begin
  perform public._c3_need('profit'); perform public._c3_range(p_from, p_to); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if jsonb_typeof(inp) <> 'object' then raise exception 'bad_input'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(inp) loop
    if k not in ('volume_pct', 'price_pct', 'cost_pct', 'expense_pct', 'salary_pct', 'fixed_pct') then raise exception 'bad_input'; end if;
    if nullif(btrim(v), '') is null then continue; end if;
    if v !~ '^-?[0-9]{1,5}(\.[0-9]{1,2})?$' or v::numeric <= -100 then raise exception 'bad_input'; end if;
    case k when 'volume_pct' then vol := v::numeric; when 'price_pct' then prc := v::numeric; when 'cost_pct' then cst := v::numeric;
           when 'expense_pct' then exp_ := v::numeric; when 'salary_pct' then sal := v::numeric; else fix := v::numeric; end case;
  end loop;
  select sum(o_net) as net, sum(o_costed) as costed, sum(o_cogs) as cogs, sum(o_exp) as exp_, sum(o_sal) as sal, sum(o_fixed) as fixed, count(*) as n into b from public._p27_pl(p_from, p_to, locs);
  if coalesce(b.n, 0) = 0 or b.net is null then
    return jsonb_build_object('key', 'fc_scenario', 'from', p_from, 'to', p_to, 'loc', p_loc, 'data_needed', jsonb_build_array('sales_in_period'), 'lines', '[]'::jsonb, 'notes', jsonb_build_array('no_sales_in_the_period'));
  end if;
  n2 := b.net * (1 + vol / 100) * (1 + prc / 100);
  c2 := b.costed * (1 + vol / 100) * (1 + prc / 100);
  g2 := b.cogs * (1 + vol / 100) * (1 + cst / 100);
  e2 := b.exp_ * (1 + exp_ / 100); s2 := b.sal * (1 + sal / 100); f2 := b.fixed * (1 + fix / 100);
  full_cost := cost_ok and b.costed is not null and b.cogs is not null and b.net > 0 and abs(b.costed - b.net) < 0.005;
  if not cost_ok then miss := miss || to_jsonb('cost_hidden'::text); elsif b.costed is null or b.cogs is null or not full_cost then miss := miss || to_jsonb('cost_coverage_not_full'::text); end if;
  if b.exp_ is null then miss := miss || to_jsonb('expense_vouchers_not_captured'::text); end if;
  if b.sal is null then miss := miss || to_jsonb('salary_not_captured'::text); end if;
  if b.fixed is null then miss := miss || to_jsonb('fixed_cost_not_set'::text); end if;
  if jsonb_array_length(miss) = 0 then res0 := b.net - b.cogs - b.exp_ - b.sal - b.fixed; res1 := n2 - g2 - e2 - s2 - f2; end if;
  lines_ := jsonb_build_array(
    jsonb_build_object('key', 'net_sales', 'baseline', round(b.net, 2), 'scenario', round(n2, 2)),
    jsonb_build_object('key', 'costed_sales', 'baseline', case when cost_ok then round(b.costed, 2) end, 'scenario', case when cost_ok and b.costed is not null then round(c2, 2) end),
    jsonb_build_object('key', 'cost_of_goods_costed_part', 'baseline', case when cost_ok then round(b.cogs, 2) end, 'scenario', case when cost_ok and b.cogs is not null then round(g2, 2) end),
    jsonb_build_object('key', 'contribution_costed_part', 'baseline', case when cost_ok and b.costed is not null then round(b.costed - b.cogs, 2) end, 'scenario', case when cost_ok and b.costed is not null then round(c2 - g2, 2) end),
    jsonb_build_object('key', 'expense_vouchers', 'baseline', round(b.exp_, 2), 'scenario', round(e2, 2)),
    jsonb_build_object('key', 'salary', 'baseline', round(b.sal, 2), 'scenario', round(s2, 2)),
    jsonb_build_object('key', 'fixed_cost', 'baseline', round(b.fixed, 2), 'scenario', round(f2, 2)),
    jsonb_build_object('key', 'result_after_costs', 'baseline', round(res0, 2), 'scenario', round(res1, 2)));
  select jsonb_agg(l || jsonb_build_object('delta', case when l ->> 'baseline' is not null and l ->> 'scenario' is not null then round((l ->> 'scenario')::numeric - (l ->> 'baseline')::numeric, 2) end,
           'delta_pct', case when l ->> 'baseline' is not null and l ->> 'scenario' is not null and (l ->> 'baseline')::numeric <> 0 then round(100 * ((l ->> 'scenario')::numeric - (l ->> 'baseline')::numeric) / abs((l ->> 'baseline')::numeric), 1) end))
    into lines_ from jsonb_array_elements(lines_) l;
  return jsonb_build_object('key', 'fc_scenario', 'from', p_from, 'to', p_to, 'loc', p_loc, 'inputs', jsonb_build_object('volume_pct', vol, 'price_pct', prc, 'cost_pct', cst, 'expense_pct', exp_, 'salary_pct', sal, 'fixed_pct', fix),
    'lines', lines_, 'result_missing', miss,
    'notes', jsonb_build_array('arithmetic_on_typed_percents_not_a_forecast', 'goods_cost_moves_with_volume_and_unit_cost_only', 'no_percent_is_suggested', 'result_shown_only_when_every_part_is_captured', 'baseline_is_the_management_view_not_the_journal'),
    'basis', 'Baseline = what happened in the period (net sales after returns, the costed part and its cost, expense vouchers, salary sheets, fixed cost). Scenario = the same figures with the percent changes you typed.');
end $$;

create or replace function public.fc_seasonal(p_loc int, p_baseline_days int, p_months int default 24) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; td date := public._c3_today(); fest jsonb; mon jsonb; grp jsonb; up jsonb;
begin
  perform public._c3_need('sales'); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if p_baseline_days is null or p_baseline_days < 7 or p_baseline_days > 90 or p_months is null or p_months < 1 or p_months > 60 then raise exception 'bad_range'; end if;
  with f as (select * from public.festival_calendar where active and end_date < td and (location_id is null or location_id = any (locs))),
  r as (
    select f.id, f.name_bn, f.name_en, f.start_date, f.end_date, f.uplift_pct,
           (select count(*) from public._c3_fc_days(f.start_date, f.end_date, locs)) as fdays,
           (select sum(net) from public._c3_fc_days(f.start_date, f.end_date, locs)) as fnet,
           (select count(*) from public._c3_fc_days(f.start_date - p_baseline_days, f.start_date - 1, locs) b where not b.is_fest) as bdays,
           (select sum(net) from public._c3_fc_days(f.start_date - p_baseline_days, f.start_date - 1, locs) b where not b.is_fest) as bnet
      from f)
  select coalesce(jsonb_agg(jsonb_build_object('festival_id', r.id, 'name_bn', r.name_bn, 'name_en', r.name_en, 'start', r.start_date, 'end', r.end_date, 'calendar_days', r.end_date - r.start_date + 1,
          'trading_days', r.fdays, 'net_sales', round(r.fnet, 2), 'avg_per_trading_day', case when r.fdays > 0 then round(r.fnet / r.fdays, 2) end,
          'baseline_trading_days', r.bdays, 'baseline_avg_per_trading_day', case when r.bdays > 0 then round(r.bnet / r.bdays, 2) end,
          'observed_difference_pct', case when r.fdays > 0 and r.bdays > 0 and r.bnet > 0 then round(100 * ((r.fnet / r.fdays) / (r.bnet / r.bdays) - 1), 1) end,
          'owner_uplift_pct', r.uplift_pct) order by r.start_date desc), '[]'::jsonb) into fest from r;
  select coalesce(jsonb_agg(jsonb_build_object('name', g.nm, 'occurrences', g.n, 'with_data', g.nd, 'average_observed_difference_pct', g.av) order by g.nm), '[]'::jsonb) into grp
    from (select lower(coalesce(x ->> 'name_en', x ->> 'name_bn')) as nm, count(*) as n, count(*) filter (where x ->> 'observed_difference_pct' is not null) as nd,
                 round(avg((x ->> 'observed_difference_pct')::numeric), 1) as av from jsonb_array_elements(fest) x group by 1) g;
  select coalesce(jsonb_agg(jsonb_build_object('name_bn', f.name_bn, 'name_en', f.name_en, 'start', f.start_date, 'end', f.end_date, 'owner_uplift_pct', f.uplift_pct) order by f.start_date), '[]'::jsonb) into up
    from public.festival_calendar f where f.active and f.end_date >= td and (f.location_id is null or f.location_id = any (locs));
  select coalesce(jsonb_agg(jsonb_build_object('month', m.mo, 'net_sales', round(m.net, 2), 'bills', m.bills, 'trading_days', m.td, 'avg_per_trading_day', case when m.td > 0 then round(m.net / m.td, 2) end,
          'festival_trading_days', m.ftd) order by m.mo), '[]'::jsonb) into mon
    from (select date_trunc('month', d.day)::date as mo, sum(d.net) as net, sum(d.bills) as bills, count(*) as td, count(*) filter (where d.is_fest) as ftd
            from public._c3_fc_days((date_trunc('month', td) - (p_months - 1) * interval '1 month')::date, td, locs) d group by 1) m;
  return jsonb_build_object('key', 'fc_seasonal', 'loc', p_loc, 'baseline_days', p_baseline_days, 'months', p_months, 'festivals', fest, 'grouped', grp, 'upcoming', up, 'by_month', mon,
    'notes', jsonb_build_array('observed_differences_are_history_not_promises', 'days_behind_each_figure_are_shown', 'baseline_is_ordinary_trading_days_before_the_festival', 'days_without_a_bill_are_closed_not_zero', 'owner_uplift_shown_for_comparison_only'),
    'basis', 'Per festival: sales per trading day during it against sales per trading day on ordinary trading days in the ' || p_baseline_days || ' days before it.');
end $$;

revoke all on function public.fc_scenario(int, date, date, jsonb), public.fc_seasonal(int, int, int) from public, anon;
grant execute on function public.fc_scenario(int, date, date, jsonb), public.fc_seasonal(int, int, int) to authenticated;
notify pgrst, 'reload schema';
