-- Phase 433 (bos433) - RPT-B3 / R6b: STOCKOUT LOG (#74), "SHELF LIFE NOT SET" NOTICE (#81), ACTUAL YIELD REPORT (#78).
-- Paste after phase432. Paste-twice safe. Earlier phase files are not edited; no shared function is re-created.
--
-- WHAT THIS ADDS
--   1. stockout_log: a simple digital entry at the shop (date, place, item, note, estimated missed quantity - optional). stockout_add / stockout_void / stockout_list / stockout_summary.
--      Every number is what a person wrote. A blank estimate is "not captured", never 0, and is never added into a total.
--      New grant stockout_log (owner, management, showroom_manager, storekeeper, salesperson get it the first time it is created; the owner can change that). Paper form code: to be given by owner.
--   2. shelf_life_missing(loc): the products that are made in the factory (an active recipe or a production run) and have NO shelf-life rule that applies today. Their batches get no expiry,
--      so every expiry list is silent about them. The screens show this as a notice and link to Settings > Shelf life (the maintenance screen already exists; this package only adds the notice).
--   3. yield_report(from, to, loc): production runs with the standard yield, the actual yield the person typed at production (blank = "not captured") and the difference.
-- Nothing here moves stock or money.

do $g$ begin
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase433 needs phase430 first'; end if;
  if not exists (select 1 from information_schema.columns where table_name = 'production_runs' and column_name = 'yield_actual') then raise exception 'phase433 needs phase74 (production_runs.yield_actual)'; end if;
end $g$;

-- ---------- grant ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('stockout_log', 'stock', 50, 'স্টক শেষ (চাহিদা পূরণ হয়নি) লেখা', 'Stockout (চাহিদা পূরণ হয়নি) লেখা', 'Log a stockout (unmet demand)', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('stockout_log', 'management'), ('stockout_log', 'showroom_manager'), ('stockout_log', 'storekeeper'), ('stockout_log', 'salesperson')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- ---------- table ----------
create table if not exists public.stockout_log (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  log_date date not null,
  location_id int not null references public.locations(id),
  item_id uuid not null references public.items(id),
  note text check (note is null or length(note) <= 300),
  est_missed_qty numeric check (est_missed_qty is null or (est_missed_qty > 0 and est_missed_qty <= 1000000000000)),       -- item base unit; a person's estimate, optional
  status text not null default 'open' check (status in ('open', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text
);
create index if not exists stockout_log_loc on public.stockout_log (location_id, log_date);
create index if not exists stockout_log_item on public.stockout_log (item_id, log_date);
drop trigger if exists audit_stockout_log on public.stockout_log;
create trigger audit_stockout_log after insert or update on public.stockout_log for each row execute function public.log_change('id');
alter table public.stockout_log enable row level security;
drop policy if exists stockout_log_read on public.stockout_log;
create policy stockout_log_read on public.stockout_log for select to authenticated using (public.can_loc(location_id));
revoke all on public.stockout_log from public, anon, authenticated;
grant select on public.stockout_log to authenticated;

create or replace function public._rb3_stockout_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('stockout_log', p_loc));
$$;
create or replace function public._rb3_stockout_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('stock') or public.has_grant('stockout_log', p_loc));
$$;

create or replace function public.stockout_add(p_date date, p_loc int, p_item uuid, p_note text default null, p_est_qty numeric default null, p_unit text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.stockout_log; it public.items; sid text; bq numeric; id_ uuid; today date := (now() at time zone 'Asia/Dhaka')::date; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.stockout_log where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb3_stockout_ok(p_loc) then raise exception 'not allowed'; end if;
  if p_date is null or p_date > today then raise exception 'bad_date'; end if;
  select * into it from public.items where id = p_item;
  if not found or not it.is_active then raise exception 'item_not_found'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if p_est_qty is not null then
    bq := public._base_qty(p_item, p_est_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.stockout_log (client_id, log_date, location_id, item_id, note, est_missed_qty, created_by, created_staff) values (p_client, p_date, p_loc, p_item, n, bq, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'est_missed_qty', bq);
end $$;

create or replace function public.stockout_void(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.stockout_log;
begin
  select * into r from public.stockout_log where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not (public._rb3_stockout_ok(r.location_id) and (r.created_by = auth.uid() or public.is_owner() or public.has_grant('stockout_log', r.location_id))) then raise exception 'not allowed'; end if;
  if r.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.stockout_log set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('status', 'void');
end $$;

create or replace function public.stockout_list(p_from date default null, p_to date default null, p_loc int default null, p_item uuid default null, p_with_void boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb3_stockout_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'log_date', s.log_date, 'location_id', s.location_id, 'location', l.name_bn, 'location_en', l.name_en,
      'item_id', s.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(s.item_id), 'note', s.note, 'est_missed_qty', s.est_missed_qty,
      'status', s.status, 'created_staff', s.created_staff, 'created_at', s.created_at, 'void_note', s.void_note) order by s.log_date desc, s.created_at desc)
    from public.stockout_log s join public.items i on i.id = s.item_id join public.locations l on l.id = s.location_id
   where s.log_date between f and t and public._rb3_stockout_view(s.location_id) and (p_loc is null or s.location_id = p_loc) and (p_item is null or s.item_id = p_item)
     and (coalesce(p_with_void, false) or s.status = 'open')), '[]'::jsonb));
end $$;

create or replace function public.stockout_summary(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb3_stockout_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', coalesce((select jsonb_agg(jsonb_build_object('location_id', z.location_id, 'location', l.name_bn, 'location_en', l.name_en, 'item_id', z.item_id, 'code', i.code,
      'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(z.item_id), 'events', z.ev, 'days', z.dy, 'last_date', z.last_d, 'est_missed_total', z.est, 'est_captured_n', z.estn,
      'est_not_captured_n', z.ev - z.estn, 'on_hand_now', (select b.qty from public.stock_balance b where b.item_id = z.item_id and b.location_id = z.location_id), 'tracked', i.tracked)
      order by z.ev desc, i.code)
    from (select s.location_id, s.item_id, count(*) as ev, count(distinct s.log_date) as dy, max(s.log_date) as last_d, sum(s.est_missed_qty) as est, count(s.est_missed_qty) as estn
            from public.stockout_log s where s.status = 'open' and s.log_date between f and t and public._rb3_stockout_view(s.location_id) and (p_loc is null or s.location_id = p_loc)
           group by s.location_id, s.item_id) z join public.items i on i.id = z.item_id join public.locations l on l.id = z.location_id), '[]'::jsonb));
end $$;

-- ---------- shelf life not set ----------
create or replace function public.shelf_life_missing(p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', x.id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'why', x.why, 'last_run', x.last_run) order by x.code), '[]'::jsonb) into out_
    from (select i.id, i.code, i.name_bn, i.name_en,
                 case when exists (select 1 from public.recipes r where r.item_id = i.id and r.active) then 'recipe' else 'production_runs' end as why,
                 (select max(pr.made_at) from public.production_runs pr where pr.item_id = i.id and pr.status = 'done' and (p_loc is null or pr.location_id = p_loc)) as last_run
            from public.items i
           where i.is_active and i.tracked and public.shelf_life_for(i.id) is null
             and (exists (select 1 from public.recipes r where r.item_id = i.id and r.active)
                  or exists (select 1 from public.production_runs pr where pr.item_id = i.id and pr.status = 'done' and (p_loc is null or pr.location_id = p_loc) and public.can_loc(pr.location_id)))) x;
  return jsonb_build_object('count', jsonb_array_length(out_), 'items', out_);
end $$;

-- ---------- actual yield ----------
create or replace function public.yield_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); rows_ jsonb; sm jsonb;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public._recipe_read())) then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('run_id', r.id, 'day', (r.made_at at time zone 'Asia/Dhaka')::date, 'made_at', r.made_at, 'location_id', r.location_id, 'location', l.name_bn, 'item_id', r.item_id,
      'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(r.item_id), 'batches', r.batches, 'batch_id', r.batch_id, 'yield_std', r.yield_std, 'yield_actual', r.yield_actual,
      'booked', r.yield_base, 'var_pct', case when r.yield_actual is not null and r.yield_std > 0 then round((r.yield_actual - r.yield_std) / r.yield_std * 100, 2) end, 'note', r.note) order by r.made_at desc, r.id), '[]'::jsonb)
    into rows_
    from public.production_runs r join public.items i on i.id = r.item_id join public.locations l on l.id = r.location_id
   where r.status = 'done' and (r.made_at at time zone 'Asia/Dhaka')::date between f and t and public.can_loc(r.location_id) and (p_loc is null or r.location_id = p_loc);
  select coalesce(jsonb_agg(jsonb_build_object('item_id', z.item_id, 'code', z.code, 'name_bn', z.name_bn, 'name_en', z.name_en, 'runs', z.n, 'actual_captured', z.na, 'actual_not_captured', z.n - z.na,
      'std_of_captured', z.sstd, 'actual_total', z.sact, 'var_pct', case when z.sstd > 0 then round((z.sact - z.sstd) / z.sstd * 100, 2) end) order by z.code), '[]'::jsonb) into sm
    from (select r.item_id, i.code, i.name_bn, i.name_en, count(*) as n, count(r.yield_actual) filter (where r.yield_std is not null) as na,
                 sum(r.yield_std) filter (where r.yield_actual is not null) as sstd, sum(r.yield_actual) filter (where r.yield_std is not null) as sact
            from public.production_runs r join public.items i on i.id = r.item_id
           where r.status = 'done' and (r.made_at at time zone 'Asia/Dhaka')::date between f and t and public.can_loc(r.location_id) and (p_loc is null or r.location_id = p_loc)
           group by r.item_id, i.code, i.name_bn, i.name_en) z;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm);
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_stockout_ok', '_rb3_stockout_view') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('stockout_add', 'stockout_void', 'stockout_list', 'stockout_summary', 'shelf_life_missing', 'yield_report') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
