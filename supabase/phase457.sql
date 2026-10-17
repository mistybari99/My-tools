-- ============================================================
-- Phase 457 - RPT-C2 / R6 part 3 (report #149 production output per worker / labour hour): the CREW and HOURS of a production run.
-- Run AFTER phase 456. New file only. Paste twice = no error.
--
--   production_crew   one row per worker on a production run: the employee and the minutes worked on that run. Append-only: changing the crew voids the old rows and writes new ones.
--   c2_production_crew_set(run, crew)   crew = [{employee_id, hours | minutes}]. Allowed: owner or the stock_production right at the run's place. Entered inside the software on the production sheet
--       (paper form code for a printed crew sheet: to be given by owner - none is invented here).
--   c2_crew_pick(place)                 active employees of a place (id and name only - no pay) for the picker.
--   c2_output_per_labour_hour(from, to, place)   per finished product and in total: output, crew minutes, output per labour hour, ONLY over the runs that have a crew; the share of runs with a crew
--       (coverage) is always shown beside it. A run with no crew is counted apart, never given hours.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_sales_per_labour_hour(date,date,int)') is null then raise exception 'phase457 needs phase456 pasted first'; end if;
end $guard$;

create table if not exists public.production_crew (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.production_runs(id),
  employee_id uuid not null references public.employees(id),
  minutes int not null check (minutes > 0 and minutes <= 1440),
  state text not null default 'active' check (state in ('active', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists production_crew_live on public.production_crew (run_id, employee_id) where state = 'active';
create index if not exists production_crew_run on public.production_crew (run_id) where state = 'active';
drop trigger if exists production_crew_ro on public.production_crew;
create trigger production_crew_ro before update or delete on public.production_crew for each row execute function public._c2_trail_ro();
drop trigger if exists audit_production_crew on public.production_crew;
create trigger audit_production_crew after insert or update on public.production_crew for each row execute function public.log_change('id');

create or replace function public._c2_can_crew(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('stock_production', p_loc));
$$;

create or replace function public.c2_production_crew_set(p_run uuid, p_crew jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs; w jsonb; emp public.employees; mins int; nw jsonb := '[]'::jsonb; cur jsonb; seen uuid[] := '{}'; n int := 0;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not_found'; end if;
  if not public._c2_can_crew(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_crew is null or jsonb_typeof(p_crew) <> 'array' or jsonb_array_length(p_crew) > 50 then raise exception 'bad_crew'; end if;
  for w in select * from jsonb_array_elements(p_crew) loop
    select * into emp from public.employees where id = nullif(w ->> 'employee_id', '')::uuid;
    if not found or emp.status not in ('active', 'on_leave') then raise exception 'employee_not_active'; end if;
    if emp.id = any (seen) then raise exception 'duplicate_worker'; end if;
    seen := seen || emp.id;
    mins := case when nullif(w ->> 'minutes', '') is not null then (w ->> 'minutes')::numeric::int when nullif(w ->> 'hours', '') is not null then round((w ->> 'hours')::numeric * 60)::int end;
    if mins is null or mins <= 0 or mins > 1440 then raise exception 'bad_minutes: 1 to 1440 minutes (24 hours) for one worker on one run'; end if;
    nw := nw || jsonb_build_object('employee_id', emp.id, 'minutes', mins);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', employee_id, 'minutes', minutes) order by employee_id), '[]'::jsonb) into cur from public.production_crew where run_id = r.id and state = 'active';
  if cur = (select coalesce(jsonb_agg(x order by x ->> 'employee_id'), '[]'::jsonb) from jsonb_array_elements(nw) x) then return jsonb_build_object('run_id', r.id, 'workers', jsonb_array_length(nw), 'noop', true); end if;
  update public.production_crew set state = 'void', void_by = auth.uid(), void_at = now(), void_note = left(coalesce(nullif(btrim(p_note), ''), 'replaced'), 300) where run_id = r.id and state = 'active';
  for w in select * from jsonb_array_elements(nw) loop
    insert into public.production_crew (run_id, employee_id, minutes, created_by, created_staff) values (r.id, (w ->> 'employee_id')::uuid, (w ->> 'minutes')::int, auth.uid(), public._c2_staff());
    n := n + 1;
  end loop;
  return jsonb_build_object('run_id', r.id, 'workers', n, 'minutes', (select coalesce(sum(minutes), 0) from public.production_crew where run_id = r.id and state = 'active'));
end $$;

create or replace function public.c2_production_crew_get(p_run uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.production_runs;
begin
  select * into r from public.production_runs where id = p_run;
  if not found or not public.is_active() or not (public._c2_can_crew(r.location_id) or public.rpt_access('staff') or public.rpt_access('stock')) or not public.can_loc(r.location_id) then raise exception 'not allowed'; end if;
  return jsonb_build_object('run_id', r.id, 'rows', coalesce((select jsonb_agg(jsonb_build_object('employee_id', c.employee_id, 'name', coalesce(e.full_name_en, e.full_name_bn), 'minutes', c.minutes) order by e.full_name_bn)
                                                          from public.production_crew c join public.employees e on e.id = c.employee_id where c.run_id = r.id and c.state = 'active'), '[]'::jsonb));
end $$;

create or replace function public.c2_crew_pick(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._c2_can_crew(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name_bn', e.full_name_bn, 'name_en', e.full_name_en) order by e.full_name_bn)
                     from public.employees e where e.status in ('active', 'on_leave') and e.primary_location_id = p_loc), '[]'::jsonb);
end $$;

create or replace function public.c2_output_per_labour_hour(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; runlist jsonb;
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('stock_production') or public.rpt_access('staff') or public.rpt_access('stock')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with r as (select pr.id, pr.location_id, pr.item_id, (pr.made_at at time zone 'Asia/Dhaka')::date as day, pr.yield_base as output,
                    (select count(*) from public.production_crew c where c.run_id = pr.id and c.state = 'active') as workers, (select sum(c.minutes) from public.production_crew c where c.run_id = pr.id and c.state = 'active') as minutes
               from public.production_runs pr where pr.status = 'done' and (pr.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to and public.can_loc(pr.location_id) and (p_loc is null or pr.location_id = p_loc)),
       it as (select r.item_id, i.code, i.name_bn, i.name_en, count(*) as runs, count(*) filter (where r.workers > 0) as runs_with_crew, sum(r.output) as output, sum(r.output) filter (where r.workers > 0) as output_with_crew,
                     sum(r.minutes) as crew_minutes from r join public.items i on i.id = r.item_id group by r.item_id, i.code, i.name_bn, i.name_en)
  select (select coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'code', code, 'name_bn', name_bn, 'name_en', name_en, 'runs', runs, 'runs_with_crew', runs_with_crew, 'output', output, 'output_with_crew', output_with_crew,
            'crew_hours', case when crew_minutes > 0 then round(crew_minutes / 60.0, 2) end, 'output_per_labour_hour', case when crew_minutes > 0 then round(output_with_crew / (crew_minutes / 60.0), 2) end,
            'coverage_pct', round(100.0 * runs_with_crew / runs, 1)) order by code), '[]'::jsonb) from it),
         (select jsonb_build_object('runs', coalesce(sum(runs), 0), 'runs_with_crew', coalesce(sum(runs_with_crew), 0), 'runs_without_crew', coalesce(sum(runs - runs_with_crew), 0),
            'coverage_pct', case when sum(runs) > 0 then round(100.0 * sum(runs_with_crew) / sum(runs), 1) end, 'crew_hours', case when sum(crew_minutes) > 0 then round(sum(crew_minutes) / 60.0, 2) end) from it),
         (select coalesce(jsonb_agg(jsonb_build_object('run_id', id, 'loc', location_id, 'day', day, 'item_id', item_id, 'output', output, 'workers', workers, 'crew_hours', case when minutes > 0 then round(minutes / 60.0, 2) end,
            'output_per_labour_hour', case when minutes > 0 then round(output / (minutes / 60.0), 2) end) order by day desc, id), '[]'::jsonb) from r)
    into rows, sm, runlist;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["per_hour_only_runs_with_a_crew","units_are_the_run_output_units","runs_without_crew_counted_apart"]'::jsonb, 'summary', sm, 'rows', rows, 'runs', runlist);
end $$;

alter table public.production_crew enable row level security;
revoke all on public.production_crew from public, anon, authenticated;
grant select on public.production_crew to authenticated;
drop policy if exists production_crew_sel on public.production_crew;
create policy production_crew_sel on public.production_crew for select to authenticated
  using (exists (select 1 from public.production_runs r where r.id = run_id and public.can_loc(r.location_id) and (public._c2_can_crew(r.location_id) or public.rpt_access('staff') or public.rpt_access('stock'))));

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
