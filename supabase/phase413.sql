-- Phase 413 (bos413) - RPT-B4 / R8b: OUTPUT PER LABOUR HOUR (#48) AND CAPACITY UTILIZATION (#51).
-- Paste after phase412. Paste-twice safe. Read only: nothing here moves stock or money. No earlier phase file is edited.
--
--   rb4_labour_productivity(from, to, place, item)   per finished run: the output, the labour hours recorded for it (people x hours each, summed over the crews) and the output per labour hour.
--                                                    A run with no labour record is "labour not captured": it is not counted in any total and its figure is empty (never 0). Units are never mixed: totals are per item.
--   rb4_capacity_utilization(from, to, place)        per place (and per line that has a rating): the batches made against the rated capacity. Capacity of a day = batches per day x working days per week / 7,
--                                                    taken from the rating in force on that day. Days with no rating are not judged (the batches made on them are shown apart); no rating at all = "rated capacity not captured".
--                                                    A place-level rating is compared with ALL runs of the place; a line rating with the runs recorded on that line.

do $g$ begin
  if to_regprocedure('public.prod_labour_list(date,date,int)') is null then raise exception 'phase413 needs phase412 first'; end if;
end $g$;

create or replace function public.rb4_labour_productivity(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; by_item jsonb; by_place jsonb; trunc boolean; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with runs as (
    select r.* from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and (p_item is null or r.item_id = p_item) and public._rb4_prod_view(r.location_id)
     order by r.made_at desc limit 2001),
  lab as (select x.run_id, sum(x.people * x.hours_each) as hrs, sum(x.people) as ppl, count(*) as crews from public.production_labour x where x.status = 'active' and x.run_id in (select id from runs) group by 1)
  select (select count(*) > 2000 from runs),
         coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', public._rb4_day(r.made_at), 'location_id', r.location_id, 'location', l.name_bn, 'location_en', l.name_en,
           'item_id', r.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches, 'output', r.yield_base,
           'line_id', k.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en, 'labour_hours', lab.hrs, 'people', lab.ppl, 'crews', lab.crews,
           'output_per_hour', case when lab.hrs > 0 then round(r.yield_base / lab.hrs, 4) end, 'hours_per_unit', case when lab.hrs > 0 and r.yield_base > 0 then round(lab.hrs / r.yield_base, 4) end,
           'status', case when lab.hrs is null then 'labour_not_captured' else 'measured' end) order by r.made_at desc), '[]'::jsonb)
    into trunc, rows_
    from (select * from runs limit 2000) r join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id
    left join lab on lab.run_id = r.id left join public.production_run_links k on k.run_id = r.id left join public.production_lines ln on ln.id = k.line_id;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', g.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(g.item_id),
        'runs', g.runs, 'measured', g.m, 'labour_not_captured', g.runs - g.m, 'output_measured', case when g.m > 0 then g.out_m end, 'labour_hours', case when g.m > 0 then g.hrs end,
        'output_per_hour', case when g.m > 0 and g.hrs > 0 then round(g.out_m / g.hrs, 4) end) order by i.code), '[]'::jsonb) into by_item
    from (select (e ->> 'item_id')::uuid as item_id, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as m, sum((e ->> 'output')::numeric) filter (where e ->> 'status' = 'measured') as out_m,
                 sum((e ->> 'labour_hours')::numeric) filter (where e ->> 'status' = 'measured') as hrs from jsonb_array_elements(rows_) e group by 1) g join public.items i on i.id = g.item_id;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', g.loc, 'location', l.name_bn, 'location_en', l.name_en, 'runs', g.runs, 'measured', g.m, 'labour_not_captured', g.runs - g.m,
        'labour_hours', case when g.m > 0 then g.hrs end, 'batches_measured', case when g.m > 0 then g.b end, 'batches_per_hour', case when g.m > 0 and g.hrs > 0 then round(g.b / g.hrs, 4) end) order by l.sort, g.loc), '[]'::jsonb) into by_place
    from (select (e ->> 'location_id')::int as loc, count(*) as runs, count(*) filter (where e ->> 'status' = 'measured') as m, sum((e ->> 'labour_hours')::numeric) filter (where e ->> 'status' = 'measured') as hrs,
                 sum((e ->> 'batches')::numeric) filter (where e ->> 'status' = 'measured') as b from jsonb_array_elements(rows_) e group by 1) g join public.locations l on l.id = g.loc;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' = 'measured') then notes := notes || jsonb_build_object('code', 'labour_not_captured', 'field', 'labour hours per run'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'by_item', by_item, 'by_place', by_place, 'truncated', coalesce(trunc, false), 'notes', notes,
    'basis', 'Labour hours = people x hours each, summed over the crews recorded for the run. Output of different items is never added; totals are per item. Runs with no labour record are left out of every total.');
end $$;

create or replace function public.rb4_capacity_utilization(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; rows_ jsonb; notes jsonb := '[]'::jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  with days as (select generate_series(f, t, interval '1 day')::date as d),
  pairs as (
    select c.location_id as loc, c.line_id from public.capacity_ratings c where c.status = 'active' and (p_loc is null or c.location_id = p_loc) and public._rb4_prod_view(c.location_id)
    union
    select r.location_id, null::int from public.production_runs r where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)),
  pd as (
    select p.loc, p.line_id, days.d, rt.batches_per_day, rt.days_per_week,
           (select coalesce(sum(r.batches), 0) from public.production_runs r left join public.production_run_links k on k.run_id = r.id
             where r.status = 'done' and r.location_id = p.loc and public._rb4_day(r.made_at) = days.d and (p.line_id is null or k.line_id = p.line_id)) as act
      from pairs p cross join days
      left join lateral (select c.batches_per_day, c.days_per_week from public.capacity_ratings c where c.status = 'active' and c.location_id = p.loc and c.line_id is not distinct from p.line_id and c.effective_from <= days.d
                          order by c.effective_from desc limit 1) rt on true),
  ag as (
    select loc, line_id, count(*) as days_n, count(*) filter (where batches_per_day is not null) as days_rated,
           sum(batches_per_day * days_per_week / 7) as cap, sum(act) filter (where batches_per_day is not null) as act_rated, sum(act) filter (where batches_per_day is null) as act_unrated, sum(act) as act_all,
           (array_agg(batches_per_day order by d desc) filter (where batches_per_day is not null))[1] as bpd_last, (array_agg(days_per_week order by d desc) filter (where batches_per_day is not null))[1] as dpw_last
      from pd group by loc, line_id)
  select coalesce(jsonb_agg(jsonb_build_object('location_id', a.loc, 'location', l.name_bn, 'location_en', l.name_en, 'line_id', a.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en,
      'days', a.days_n, 'days_rated', a.days_rated, 'days_not_rated', a.days_n - a.days_rated, 'capacity_batches', case when a.days_rated > 0 then round(a.cap, 2) end,
      'batches_made_on_rated_days', case when a.days_rated > 0 then a.act_rated end, 'batches_made_on_days_not_rated', case when a.days_n > a.days_rated then a.act_unrated end, 'batches_made', a.act_all,
      'utilization_pct', case when a.days_rated > 0 and a.cap > 0 then round(a.act_rated / a.cap * 100, 1) end,
      'rated_batches_per_day', a.bpd_last, 'rated_days_per_week', a.dpw_last,
      'status', case when a.days_rated = 0 then 'rated_capacity_not_captured' when a.days_rated < a.days_n then 'partly_rated' else 'rated' end) order by l.sort, a.loc, a.line_id nulls first), '[]'::jsonb) into rows_
    from ag a join public.locations l on l.id = a.loc left join public.production_lines ln on ln.id = a.line_id;
  if jsonb_array_length(rows_) > 0 and not exists (select 1 from jsonb_array_elements(rows_) e where e ->> 'status' <> 'rated_capacity_not_captured') then notes := notes || jsonb_build_object('code', 'capacity_not_captured', 'field', 'rated capacity'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'notes', notes,
    'basis', 'Capacity of a day = rated batches per day x working days per week / 7, from the rating in force that day. Batches made are the finished runs (batches field). Days without a rating are not judged. A place rating counts all runs of the place; a line rating counts the runs recorded on the line.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_labour_productivity', 'rb4_capacity_utilization') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
