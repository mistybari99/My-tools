-- Phase 407 (bos407) - RPT-B4 / R4b: REAL CONSUMPTION VS RECIPE (#44), STANDARD VS ACTUAL COST AND THE PRICE / USAGE / YIELD VARIANCE (#33, #43, #55).
-- Paste after phase406. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
-- BASIS (said on the screen too)
--   Standard quantity   = what the production screen booked out for the run (the recipe need). It is read from the stock ledger (ref production + run id), so it is exactly what was booked.
--   Real quantity       = the record a person made with prod_actual_issue_set. Nothing is guessed: a run or ingredient without a record is "not captured" and is left out of every total.
--   Booked price        = the average cost the ledger used when the standard quantity went out (blank or 0 = unknown).
--   Standard price      = the owner's price list (item_costs). An ingredient without a list price has no price variance.
--   Standard output     = production_runs.yield_std (the recipe yield x batches). Real output = the quantity the person typed at production (yield_actual); blank = "not captured".
--   Material variance of one fully measured run (all inputs present):
--       price  = sum (booked price - standard price) x real qty
--       usage  = sum (real qty - standard qty) x standard price
--       yield  = (standard output - real output) x (sum standard qty x standard price / standard output)
--       total  = sum real qty x booked price - real output x (sum standard qty x standard price / standard output)       and  total = price + usage + yield   exactly
--   Positive = more cost than the standard (unfavourable). Each part is also given alone when only its own inputs exist. Conversion cost (labour, overhead) has no standard in the system: it is shown as booked, not split.
--   Money is shown only with the cost right (_cost_ok at the run's place); otherwise the answer says cost_hidden and gives quantities only.

do $g$ begin
  if to_regprocedure('public.rb4_dispatch_recon(date,date,int)') is null then raise exception 'phase407 needs phase406 first'; end if;
end $g$;

create or replace function public.rb4_consumption_vs_recipe(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; sm jsonb; runs_n int; runs_any int; notes jsonb := '[]'::jsonb; trunc boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  select count(*), count(*) filter (where exists (select 1 from public.production_issue_actual a where a.run_id = r.id and a.status = 'active')) into runs_n, runs_any
    from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id);
  if runs_any = 0 then notes := notes || jsonb_build_object('code', 'actual_issue_not_captured', 'field', 'real use of ingredients'); end if;

  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  lines as (
    select r.id as run_id, r.made_at, r.location_id, r.item_id as fg_id, x.item_id, x.std_qty, a.actual_qty
      from runs r
      cross join lateral (select b.item_id, b.qty as std_qty from public._rb4_run_booked(r.id) b
                          union all
                          select a2.item_id, null::numeric from public.production_issue_actual a2 where a2.run_id = r.id and a2.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) b2 where b2.item_id = a2.item_id)) x
      left join public.production_issue_actual a on a.run_id = r.id and a.item_id = x.item_id and a.status = 'active')
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', l.run_id, 'day', public._rb4_day(l.made_at), 'location_id', l.location_id, 'location', lo.name_bn, 'location_en', lo.name_en,
           'fg_code', fi.code, 'fg_name_bn', fi.name_bn, 'fg_name_en', fi.name_en, 'item_id', l.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(l.item_id),
           'std_qty', l.std_qty, 'actual_qty', l.actual_qty, 'diff', case when l.std_qty is not null and l.actual_qty is not null then round(l.actual_qty - l.std_qty, 4) end,
           'diff_pct', case when l.std_qty > 0 and l.actual_qty is not null then round((l.actual_qty - l.std_qty) / l.std_qty * 100, 2) end,
           'status', case when l.std_qty is null then 'not_in_recipe' when l.actual_qty is null then 'not_captured' else 'measured' end)
           order by l.made_at desc, ii.code), '[]'::jsonb)
    into trunc, rows_
    from lines l join public.items ii on ii.id = l.item_id join public.items fi on fi.id = l.fg_id join public.locations lo on lo.id = l.location_id;

  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', ii.code, 'name_bn', ii.name_bn, 'name_en', ii.name_en, 'base_unit', public._item_base(g.item_id),
        'runs_issued', g.runs_total, 'runs_measured', g.runs_measured, 'runs_not_captured', g.runs_total - g.runs_measured,
        'std_qty_measured', case when g.runs_measured > 0 then g.std_sum end, 'actual_qty_measured', case when g.runs_measured > 0 then g.act_sum end,
        'diff', case when g.runs_measured > 0 then round(g.act_sum - g.std_sum, 4) end,
        'diff_pct', case when g.runs_measured > 0 and g.std_sum > 0 then round((g.act_sum - g.std_sum) / g.std_sum * 100, 2) end) order by ii.code), '[]'::jsonb) into sm
    from (select e ->> 'item_id' as item_id_t, (e ->> 'item_id')::uuid as item_id,
                 count(*) filter (where e ->> 'status' in ('measured', 'not_captured')) as runs_total, count(*) filter (where e ->> 'status' = 'measured') as runs_measured,
                 sum((e ->> 'std_qty')::numeric) filter (where e ->> 'status' = 'measured') as std_sum, sum((e ->> 'actual_qty')::numeric) filter (where e ->> 'status' = 'measured') as act_sum
            from jsonb_array_elements(rows_) e group by 1, 2) g
    join public.items ii on ii.id = g.item_id;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'runs', runs_n, 'runs_with_real_use', runs_any, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'Standard = the recipe quantity booked out by the production screen (stock ledger). Real = what a person recorded. Runs or ingredients with no record are not captured and are left out of the totals.');
end $$;

create or replace function public.rb4_cost_variance(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; r record; ln record; rows_ jsonb := '[]'::jsonb; lines jsonb; money boolean; hidden boolean := false; trunc boolean := false; cnt int := 0;
        n_ing int; n_sp int; n_aq int; n_ap int; extra_n int; sq_sp numeric; aq_ap numeric; aq_sp numeric; sq_ap numeric; yb numeric; ao numeric; stdunit numeric;
        pv numeric; uv numeric; yvv numeric; tv numeric; yield_ok boolean; usage_ok boolean; price_ok boolean; total_ok boolean; miss text[]; sm jsonb; ap_ numeric; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  for r in select pr.* from public.production_runs pr where pr.status = 'done' and public._rb4_day(pr.made_at) between f and t and (p_loc is null or pr.location_id = p_loc) and (p_item is null or pr.item_id = p_item)
              and public._rb4_prod_view(pr.location_id) order by pr.made_at desc limit 501 loop
    cnt := cnt + 1;
    if cnt > 500 then trunc := true; exit; end if;
    money := public._cost_ok(r.location_id); if not money then hidden := true; end if;
    n_ing := 0; n_sp := 0; n_aq := 0; n_ap := 0; sq_sp := 0; aq_ap := 0; aq_sp := 0; sq_ap := 0; lines := '[]'::jsonb; miss := '{}';
    for ln in select b.item_id, b.qty as sq, b.unit_cost as ap, ic.cost_price as sp, a.actual_qty as aq, i.code, i.name_bn, i.name_en
                from public._rb4_run_booked(r.id) b join public.items i on i.id = b.item_id
                left join public.item_costs ic on ic.item_id = b.item_id
                left join public.production_issue_actual a on a.run_id = r.id and a.item_id = b.item_id and a.status = 'active' order by i.code loop
      ap_ := case when ln.ap is null or ln.ap <= 0 then null else ln.ap end;       -- cost 0 or blank = unknown
      n_ing := n_ing + 1;
      if ln.sp is not null then n_sp := n_sp + 1; sq_sp := sq_sp + ln.sq * ln.sp; end if;
      if ln.aq is not null then n_aq := n_aq + 1; end if;
      if ap_ is not null then n_ap := n_ap + 1; end if;
      if ln.aq is not null and ln.sp is not null then aq_sp := aq_sp + ln.aq * ln.sp; end if;
      if ln.aq is not null and ap_ is not null then aq_ap := aq_ap + ln.aq * ap_; end if;
      lines := lines || jsonb_build_object('item_id', ln.item_id, 'code', ln.code, 'name_bn', ln.name_bn, 'name_en', ln.name_en, 'std_qty', ln.sq, 'actual_qty', ln.aq,
          'booked_price', case when money then ap_ end, 'std_price', case when money then ln.sp end,
          'price_var', case when money and ln.aq is not null and ln.sp is not null and ap_ is not null then round((ap_ - ln.sp) * ln.aq, 2) end,
          'usage_var', case when money and ln.aq is not null and ln.sp is not null then round((ln.aq - ln.sq) * ln.sp, 2) end);
    end loop;
    select count(*) into extra_n from public.production_issue_actual a where a.run_id = r.id and a.status = 'active' and not exists (select 1 from public._rb4_run_booked(r.id) b where b.item_id = a.item_id);
    yb := r.yield_std; ao := r.yield_actual;
    stdunit := case when yb > 0 and n_ing > 0 and n_sp = n_ing then sq_sp / yb end;
    yield_ok := ao is not null and stdunit is not null;
    usage_ok := n_ing > 0 and n_aq = n_ing and n_sp = n_ing and extra_n = 0;
    price_ok := usage_ok and n_ap = n_ing;
    total_ok := yield_ok and price_ok;
    pv := case when price_ok then round(aq_ap - aq_sp, 2) end;
    uv := case when usage_ok then round(aq_sp - sq_sp, 2) end;
    yvv := case when yield_ok then round((yb - ao) * stdunit, 2) end;
    tv := case when total_ok then round(aq_ap - ao * stdunit, 2) end;
    if n_ing = 0 then miss := array_append(miss, 'booked ingredients'::text); end if;
    if n_aq < n_ing or extra_n > 0 then miss := array_append(miss, 'real use of ingredients'::text); end if;
    if n_sp < n_ing then miss := array_append(miss, 'standard price (price list)'::text); end if;
    if n_ap < n_ing then miss := array_append(miss, 'booked cost'::text); end if;
    if ao is null then miss := array_append(miss, 'actual yield'::text); end if;
    rows_ := rows_ || jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'item_id', r.item_id,
        'yield_std', r.yield_std, 'yield_actual', r.yield_actual, 'yield_var_qty', case when ao is not null and yb is not null then round(yb - ao, 4) end,
        'booked_unit_cost', case when money then r.unit_cost end, 'std_unit_cost_booked', case when money then r.std_cost end, 'material_cost', case when money then r.material_cost end,
        'conversion_cost', case when money then r.conversion_cost end, 'conversion_complete', r.conversion_complete, 'conversion_mode', r.conversion_mode,
        'std_unit_cost_list', case when money then round(stdunit, 6) end,
        'std_cost_for_real_output', case when money and total_ok then round(ao * stdunit, 2) end, 'real_material_cost', case when money and price_ok then round(aq_ap, 2) end,
        'price_var', case when money then pv end, 'usage_var', case when money then uv end, 'yield_var', case when money then yvv end, 'total_var', case when money then tv end,
        'price_var_ok', price_ok, 'usage_var_ok', usage_ok, 'yield_var_ok', yield_ok, 'measured', total_ok,
        'status', case when total_ok then 'measured' when yield_ok or usage_ok then 'partly' else 'not_measured' end, 'missing', to_jsonb(miss), 'lines', lines);
  end loop;
  -- names for the rows (kept out of the loop to keep it short)
  select coalesce(jsonb_agg(e || jsonb_build_object('location', l.name_bn, 'location_en', l.name_en, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base((e ->> 'item_id')::uuid))
         order by e ->> 'day' desc), '[]'::jsonb) into rows_
    from jsonb_array_elements(rows_) e join public.items i on i.id = (e ->> 'item_id')::uuid join public.locations l on l.id = (e ->> 'location_id')::int;
  -- summary per finished item: only runs where the part could be measured are added; the counts say how many
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'runs_measured', g.rm, 'runs_partly', g.rp, 'runs_not_measured', g.runs - g.rm - g.rp,
        'price_var', case when g.n_price > 0 then g.s_price end, 'price_var_runs', g.n_price, 'usage_var', case when g.n_usage > 0 then g.s_usage end, 'usage_var_runs', g.n_usage,
        'yield_var', case when g.n_yield > 0 then g.s_yield end, 'yield_var_runs', g.n_yield,
        'total_var', case when g.rm > 0 then g.s_total end, 'std_cost_for_real_output', case when g.rm > 0 then g.s_std end, 'real_material_cost', case when g.rm > 0 then g.s_real end,
        'total_var_pct', case when g.rm > 0 and g.s_std > 0 then round(g.s_total / g.s_std * 100, 2) end) order by i.code), '[]'::jsonb) into sm
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as rm, count(*) filter (where e ->> 'status' = 'partly') as rp,
                 count(*) filter (where (e ->> 'price_var_ok')::boolean) as n_price, sum((e ->> 'price_var')::numeric) filter (where (e ->> 'price_var_ok')::boolean) as s_price,
                 count(*) filter (where (e ->> 'usage_var_ok')::boolean) as n_usage, sum((e ->> 'usage_var')::numeric) filter (where (e ->> 'usage_var_ok')::boolean) as s_usage,
                 count(*) filter (where (e ->> 'yield_var_ok')::boolean) as n_yield, sum((e ->> 'yield_var')::numeric) filter (where (e ->> 'yield_var_ok')::boolean) as s_yield,
                 sum((e ->> 'total_var')::numeric) filter (where (e ->> 'measured')::boolean) as s_total, sum((e ->> 'std_cost_for_real_output')::numeric) filter (where (e ->> 'measured')::boolean) as s_std,
                 sum((e ->> 'real_material_cost')::numeric) filter (where (e ->> 'measured')::boolean) as s_real
            from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then
    notes := notes || jsonb_build_object('code', 'no_run_fully_measured', 'field', 'real use of ingredients, standard price, actual yield');
  end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'cost_hidden', hidden, 'truncated', trunc, 'notes', notes,
    'basis', 'Standard price = the owner price list (item_costs). Booked price = the average cost the ledger used for the run. Positive variance = more cost than the standard. Conversion cost has no standard and is not split. A part is shown only when all of its inputs were captured.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_consumption_vs_recipe', 'rb4_cost_variance') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
