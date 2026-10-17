-- Phase 412 (bos412) - RPT-B4 / R8a: RATED CAPACITY, PRODUCTION LINES AND LABOUR HOURS PER RUN (data capture).
-- Paste after phase405 (it extends the run link table of phase 404). Paste-twice safe. No earlier phase file is edited; no shared function is re-created.
-- Requirements: docs/REPORTS_AUDIT_1.md items #48 (output per labour hour) and #51 (capacity utilization). Attendance exists at day level only; the hours of a crew on one run were never captured.
--
--   production_lines     a named line / section of a producing place (name_bn + name_en, retired never deleted).
--   capacity_ratings     the owner's rated capacity of a place (or one of its lines): batches per day and working days per week, from a day on. A blank rating = "rated capacity not captured".
--   production_labour    who worked on a run: number of people and the hours each worked (more than one crew = more than one line). Voided, never deleted.
--   production_run_links.line_id   which line a run was made on (optional).
--   grant capacity_manage   who may set lines and ratings. By default only the owner. Labour hours are entered with the production grant stock_production, like the rest of the production capture.
-- Nothing here moves stock or money. Paper form code of these entry screens: to be given by owner.

do $g$ begin
  if to_regclass('public.production_run_links') is null then raise exception 'phase412 needs phase404 first'; end if;
  if to_regprocedure('public.prod_run_link(uuid,uuid,bigint,boolean,boolean)') is null then raise exception 'phase412 needs phase405 first'; end if;
end $g$;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('capacity_manage', 'stock', 60, 'উৎপাদন লাইন ও ক্ষমতা ঠিক করা', 'Production line ও capacity ঠিক করা', 'Set production lines and rated capacity', 'once', null)
on conflict (grant_code) do nothing;

create table if not exists public.production_lines (
  id serial primary key,
  location_id int not null references public.locations(id),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(btrim(name_en)) between 1 and 80),
  active boolean not null default true,
  retired_note text, retired_by uuid, retired_at timestamptz,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists production_lines_name on public.production_lines (location_id, lower(btrim(name_bn)));

create table if not exists public.capacity_ratings (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  line_id int references public.production_lines(id),
  batches_per_day numeric not null check (batches_per_day > 0 and batches_per_day <= 100000),
  days_per_week numeric not null check (days_per_week > 0 and days_per_week <= 7),
  effective_from date not null,
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'retired')),
  retired_note text, retired_by uuid, retired_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create unique index if not exists capacity_ratings_one on public.capacity_ratings (location_id, coalesce(line_id, 0), effective_from) where status = 'active';

create table if not exists public.production_labour (
  id bigserial primary key,
  client_id uuid unique,
  run_id uuid not null references public.production_runs(id),
  people int not null check (people > 0 and people <= 1000),
  hours_each numeric not null check (hours_each > 0 and hours_each <= 24),
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'void')),
  void_note text, void_by uuid, void_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists production_labour_run on public.production_labour (run_id);

alter table public.production_run_links add column if not exists line_id int references public.production_lines(id);

do $t$
declare t text;
begin
  foreach t in array array['production_lines', 'capacity_ratings', 'production_labour'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update on public.%1$s for each row execute function public.log_change(%2$L)', t, 'id');
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $t$;
revoke all on sequence public.production_lines_id_seq, public.capacity_ratings_id_seq, public.production_labour_id_seq from public, anon, authenticated;

create or replace function public._rb4_cap_edit(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('capacity_manage', p_loc));
$$;
drop policy if exists production_lines_read on public.production_lines;
create policy production_lines_read on public.production_lines for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists capacity_ratings_read on public.capacity_ratings;
create policy capacity_ratings_read on public.capacity_ratings for select to authenticated using (public._rb4_prod_view(location_id));
drop policy if exists production_labour_read on public.production_labour;
create policy production_labour_read on public.production_labour for select to authenticated using (exists (select 1 from public.production_runs r where r.id = run_id and public._rb4_prod_view(r.location_id)));

-- ---------- lines ----------
create or replace function public.production_line_set(p_id int, p_loc int, p_name_bn text, p_name_en text default null, p_active boolean default true, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_lines; nb text := nullif(btrim(p_name_bn), ''); ne text := nullif(btrim(p_name_en), ''); id_ int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_id is not null then
    select * into l from public.production_lines where id = p_id for update;
    if not found then raise exception 'not found'; end if;
    if not public._rb4_cap_edit(l.location_id) then raise exception 'not allowed'; end if;
  else
    if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
    if not public._rb4_cap_edit(p_loc) then raise exception 'not allowed'; end if;
  end if;
  if nb is null or length(nb) > 80 or (ne is not null and length(ne) > 80) then raise exception 'bad_name'; end if;
  if p_id is null then
    insert into public.production_lines (location_id, name_bn, name_en, created_by) values (p_loc, nb, ne, auth.uid()) returning id into id_;
    return jsonb_build_object('id', id_);
  end if;
  if coalesce(p_active, true) = false and l.active then
    if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;      -- retiring a line needs a reason
    update public.production_lines set name_bn = nb, name_en = ne, active = false, retired_note = left(btrim(p_note), 300), retired_by = auth.uid(), retired_at = now() where id = p_id;
  else
    update public.production_lines set name_bn = nb, name_en = ne, active = coalesce(p_active, true), retired_note = case when coalesce(p_active, true) then null else retired_note end where id = p_id;
  end if;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.production_line_list(p_loc int default null, p_with_retired boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'location_id', l.location_id, 'location', lo.name_bn, 'location_en', lo.name_en, 'name_bn', l.name_bn, 'name_en', l.name_en, 'active', l.active, 'retired_note', l.retired_note,
      'can_edit', public._rb4_cap_edit(l.location_id)) order by lo.sort, l.id)
    from public.production_lines l join public.locations lo on lo.id = l.location_id
   where (p_loc is null or l.location_id = p_loc) and public._rb4_prod_view(l.location_id) and (coalesce(p_with_retired, false) or l.active)), '[]'::jsonb);
end $$;

-- ---------- rated capacity ----------
create or replace function public.capacity_rating_set(p_loc int, p_line int, p_batches_per_day numeric, p_days_per_week numeric, p_from date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old public.capacity_ratings; sid text; id_ bigint; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public._rb4_cap_edit(p_loc) then raise exception 'not allowed'; end if;
  if p_line is not null and not exists (select 1 from public.production_lines where id = p_line and location_id = p_loc and active) then raise exception 'line_not_found'; end if;
  if p_batches_per_day is null or not (p_batches_per_day > 0 and p_batches_per_day <= 100000) then raise exception 'bad_capacity'; end if;
  if p_days_per_week is null or not (p_days_per_week > 0 and p_days_per_week <= 7) then raise exception 'bad_days'; end if;
  if p_from is null or abs(p_from - public._rb4_today()) > 800 then raise exception 'bad_date'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select * into old from public.capacity_ratings where location_id = p_loc and line_id is not distinct from p_line and effective_from = p_from and status = 'active' for update;
  if found and old.batches_per_day = p_batches_per_day and old.days_per_week = p_days_per_week then return jsonb_build_object('dup', true, 'id', old.id); end if;
  if found then update public.capacity_ratings set status = 'retired', retired_note = 'replaced by a new rating', retired_by = auth.uid(), retired_at = now() where id = old.id; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.capacity_ratings (location_id, line_id, batches_per_day, days_per_week, effective_from, note, created_by, created_staff) values (p_loc, p_line, p_batches_per_day, p_days_per_week, p_from, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'replaced', old.id);
end $$;

create or replace function public.capacity_rating_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.capacity_ratings;
begin
  select * into r from public.capacity_ratings where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_cap_edit(r.location_id) then raise exception 'not allowed'; end if;
  if r.status = 'retired' then return jsonb_build_object('dup', true, 'status', 'retired'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.capacity_ratings set status = 'retired', retired_note = left(btrim(p_note), 300), retired_by = auth.uid(), retired_at = now() where id = p_id;
  return jsonb_build_object('status', 'retired');
end $$;

create or replace function public.capacity_rating_list(p_loc int default null, p_with_retired boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'location_id', c.location_id, 'location', lo.name_bn, 'location_en', lo.name_en, 'line_id', c.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en,
      'batches_per_day', c.batches_per_day, 'days_per_week', c.days_per_week, 'effective_from', c.effective_from, 'note', c.note, 'status', c.status, 'retired_note', c.retired_note, 'created_staff', c.created_staff,
      'can_edit', public._rb4_cap_edit(c.location_id)) order by lo.sort, c.location_id, c.line_id nulls first, c.effective_from desc, c.id)
    from public.capacity_ratings c join public.locations lo on lo.id = c.location_id left join public.production_lines ln on ln.id = c.line_id
   where (p_loc is null or c.location_id = p_loc) and public._rb4_prod_view(c.location_id) and (coalesce(p_with_retired, false) or c.status = 'active')), '[]'::jsonb);
end $$;

-- ---------- labour hours of a run ----------
create or replace function public.prod_labour_add(p_run uuid, p_people int, p_hours numeric, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare prev public.production_labour; r public.production_runs; sid text; id_ bigint; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.production_labour where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id);
    end if;
  end if;
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_people is null or not (p_people between 1 and 1000) then raise exception 'bad_people'; end if;
  if p_hours is null or not (p_hours > 0 and p_hours <= 24) then raise exception 'bad_hours'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.production_labour (client_id, run_id, people, hours_each, note, created_by, created_staff) values (p_client, p_run, p_people, p_hours, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'labour_hours', p_people * p_hours);
end $$;

create or replace function public.prod_labour_void(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.production_labour; r public.production_runs;
begin
  select * into l from public.production_labour where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  select * into r from public.production_runs where id = l.run_id;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if l.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.production_labour set status = 'void', void_note = left(btrim(p_note), 300), void_by = auth.uid(), void_at = now() where id = p_id;
  return jsonb_build_object('status', 'void');
end $$;

-- which line a run was made on (blank = not recorded); a finished run only
create or replace function public.prod_run_line(p_run uuid, p_line int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.production_runs;
begin
  select * into r from public.production_runs where id = p_run;
  if not found then raise exception 'not found'; end if;
  if not public._rb4_prod_entry(r.location_id) then raise exception 'not allowed'; end if;
  if r.status <> 'done' then raise exception 'run_void'; end if;
  if p_line is not null and not exists (select 1 from public.production_lines where id = p_line and location_id = r.location_id and active) then raise exception 'line_not_found'; end if;
  insert into public.production_run_links (run_id, line_id, linked_by) values (p_run, p_line, auth.uid())
    on conflict (run_id) do update set line_id = excluded.line_id, linked_by = excluded.linked_by, linked_at = now();
  return jsonb_build_object('run_id', p_run, 'line_id', p_line);
end $$;

-- labour and line of the runs of a period (the entry screen shows them next to prod_runs_recent)
create or replace function public.prod_labour_list(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_prod_view(p_loc) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('run_id', r.id, 'line_id', k.line_id, 'line_bn', ln.name_bn, 'line_en', ln.name_en,
        'labour_hours', (select sum(x.people * x.hours_each) from public.production_labour x where x.run_id = r.id and x.status = 'active'),
        'entries', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'people', x.people, 'hours_each', x.hours_each, 'note', x.note, 'created_staff', x.created_staff) order by x.id) from public.production_labour x where x.run_id = r.id and x.status = 'active'), '[]'::jsonb))
      order by r.made_at desc)
    from public.production_runs r left join public.production_run_links k on k.run_id = r.id left join public.production_lines ln on ln.id = k.line_id
   where r.status = 'done' and public._rb4_day(r.made_at) between f and t and (p_loc is null or r.location_id = p_loc) and public._rb4_prod_view(r.location_id)), '[]'::jsonb);
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_rb4_cap_edit' loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('production_line_set', 'production_line_list', 'capacity_rating_set', 'capacity_rating_retire', 'capacity_rating_list', 'prod_labour_add', 'prod_labour_void', 'prod_run_line', 'prod_labour_list') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
