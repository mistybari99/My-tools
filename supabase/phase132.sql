-- Phase 132 (package R2-C) - SHIFT SCHEDULE: shift templates, a weekly roster per person and place, off-days, leave / swap notes,
-- "my upcoming shifts and who else is on at my place", and a soft roster-versus-attendance report.
-- Paste after phase99 (needs phase41/42: employees, shifts, employee_shift_assignments, holidays, leave_requests). Independent of phases 130 and 131.
-- Paste-twice safe. No earlier phase file is edited and NO shared function is patched or re-created (nothing to hook): with shift_on OFF (the default)
-- nothing here reads or writes anything, and attendance, leave and payroll work exactly as before.
--
-- REUSE (nothing is duplicated):
--   * Shift TEMPLATES are the existing `shifts` table (name, start, end, place). A person holding shift_manage may add or retire a template at his place
--     through r2_shift_template_save (same table, same checks as shift_save, but with the new grant instead of attendance_manage).
--   * The recurring weekly pattern already exists: employee_shift_assignments (weekday mask, off mask) written by shift_assign. It is READ here as the base
--     of the roster; this file never writes it.
--   * Holidays (holidays) and approved leave (leave_requests) are READ to mark a day. Attendance (attendance_days) is READ by the report only when it exists.
-- WHAT THIS FILE ADDS (every new name starts r2_ / _r2_)
--   1. Settings  shift_on (OFF)           the whole shift schedule. OFF = no screen data, no edits (shift_off).
--                shift_mates_on (ON)      staff see who else is on at their place (only when shift_on is ON). OFF = a person sees only his own shifts.
--   2. Grant     shift_manage             who may schedule (templates, roster cells). Nobody holds it by default except the owner. Scope: the person's
--                                         PRIMARY place, the same rule as attendance_manage (_emp_ok); a grant limited to one place covers that place.
--   3. Table     r2_roster_days           one row per person and day that SAYS something: a shift (a template) or an off-day, with a leave / swap note.
--                                         A day with no row follows the weekly pattern (employee_shift_assignments), or shows nothing. Row level security: no
--                                         browser access at all (read through the functions); never deleted (clear = active false; the audit log keeps every change).
--   4. API       r2_shift_state()          switch, may I schedule, places I may schedule, am I linked to an employee record
--                r2_shift_my(from, days)   MY days (default 14): shift, off, note, holiday, approved leave, and (if shift_mates_on) who else is on at my place
--                r2_shift_roster(loc, from, days)   the roster grid for one place (schedulers only): people x days + the templates
--                r2_roster_set / r2_roster_clear / r2_roster_week / r2_roster_copy_week   edit cells (schedulers only)
--                r2_shift_template_save(id, data)   add / edit / retire a template (schedulers; owner may use "every place")
--                r2_shift_report(loc, from, to)     roster versus actual attendance, only if attendance_days exists (soft link, read only)

do $g$ begin
  if to_regclass('public.shifts') is null or to_regclass('public.employees') is null or to_regclass('public.employee_shift_assignments') is null
     or to_regprocedure('public._emp_ok(uuid,text[],boolean)') is null or to_regprocedure('public._loc_ok(integer,text)') is null
     or to_regprocedure('public._att_is_off(uuid,date)') is null or to_regprocedure('public._hhmm(text)') is null then
    raise exception 'phase132 needs phase 41 and 42 (employees, shifts, shift pattern, attendance helpers) first';
  end if;
  if to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null then
    raise exception 'phase132 needs the rules and grants engine (phase 7, 8, 11) first';
  end if;
end $g$;

create or replace function public._r2c_present() returns boolean language sql stable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS and GRANT
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('shift_on', 'people', 'switch', 'false'::jsonb, null, null, null, null,
  'শিফট রোস্টার চালু (কে কোন দিন কোন শিফটে)', 'শিফট roster চালু', 'Shift schedule is on (who works which shift on which day)',
  'বন্ধ থাকলে রোস্টারের কিছুই দেখা বা লেখা যায় না; হাজিরা, ছুটি ও বেতন আগের মতোই। চালু করলে কর্মী নিজের আগামী শিফট দেখে, নির্ধারিত ব্যক্তি রোস্টার সাজায়।',
  'বন্ধ থাকলে roster কিছুই দেখা বা লেখা যায় না; হাজিরা, ছুটি, বেতন আগের মতোই। চালু করলে কর্মী নিজের শিফট দেখে, নির্ধারিত ব্যক্তি roster সাজায়।',
  'OFF = no roster can be seen or written; attendance, leave and payroll are as before. ON = staff see their own coming shifts and a person holding shift_manage edits the roster.', 1320),
 ('shift_mates_on', 'people', 'switch', 'true'::jsonb, null, null, null, null,
  'রোস্টারে নিজের জায়গায় আর কে ডিউটিতে আছে তা কর্মী দেখবে', 'Roster-এ নিজের জায়গায় আর কে on আছে তা দেখবে', 'Staff see who else is on at their place',
  'শিফট রোস্টার চালু থাকলে কাজ করে। বন্ধ করলে কর্মী শুধু নিজের শিফট দেখে, সহকর্মীর নাম দেখে না।',
  'Shift roster চালু থাকলে কাজ করে। বন্ধ করলে কর্মী শুধু নিজের শিফট দেখে।',
  'Works only while shift_on is ON. OFF = a person sees only his own shifts, not his colleagues'' names.', 1321)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('shift_manage', 'people', 78, 'শিফট ও রোস্টার সাজানো (টেমপ্লেট, দিনের শিফট, অফ-ডে, ছুটি / বদলের নোট)', 'Shift ও roster সাজানো (template, শিফট, off-day, note)', 'Schedule shifts and the roster (templates, shifts, off-days, leave / swap notes)', 'window', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 2. TABLE
-- ============================================================================
create table if not exists public.r2_roster_days (
  id bigserial primary key,
  employee_id uuid not null references public.employees(id),
  day date not null,
  shift_id int references public.shifts(id),
  is_off boolean not null default false,
  note text check (note is null or char_length(note) <= 200),
  location_id int references public.locations(id),
  active boolean not null default true,
  set_by uuid, set_at timestamptz not null default now(),
  check (is_off or shift_id is not null),
  check (not (is_off and shift_id is not null))
);
create unique index if not exists r2_roster_days_uq on public.r2_roster_days (employee_id, day) where active;
create index if not exists r2_roster_days_day on public.r2_roster_days (day, location_id) where active;

drop trigger if exists r2_roster_days_no_delete on public.r2_roster_days;
create trigger r2_roster_days_no_delete before delete on public.r2_roster_days for each row execute function public.no_hard_delete();
drop trigger if exists audit_r2_roster_days on public.r2_roster_days;
create trigger audit_r2_roster_days after insert or update on public.r2_roster_days for each row execute function public.log_change('id');

alter table public.r2_roster_days enable row level security;
revoke all on public.r2_roster_days from public, anon, authenticated;

-- ============================================================================
-- 3. HELPERS
-- ============================================================================
create or replace function public._r2c_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('shift_on') then raise exception 'shift_off'; end if;
end $$;

-- may the caller schedule this person?
create or replace function public._r2c_ok(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public._emp_ok(p_emp, array['shift_manage']);
$$;

-- The plan for a range of days: roster rows first, then the weekly pattern (employee_shift_assignments), else nothing.
-- One row per person and day that has a shift or an off-day. place_id = the row's place, else the template's place, else the person's primary place.
create or replace function public._r2_plan(p_from date, p_to date, p_emp uuid default null, p_loc int default null)
returns table (employee_id uuid, day date, shift_id int, is_off boolean, note text, source text, place_id int, holiday_bn text, holiday_en text)
language sql stable security definer set search_path = public as $$
  with days as (select g::date as d from generate_series(p_from, least(p_to, p_from + 92), interval '1 day') g),
  emps as (select e.id, e.primary_location_id from public.employees e where e.status in ('active', 'on_leave') and (p_emp is null or e.id = p_emp)),
  rd as (select r.* from public.r2_roster_days r where r.active and r.day between p_from and least(p_to, p_from + 92) and (p_emp is null or r.employee_id = p_emp)),
  cov as (select distinct on (a.employee_id, d.d) a.employee_id, d.d as day, a.shift_id, a.weekday_mask
            from public.employee_shift_assignments a join days d on d.d >= a.from_date and (a.to_date is null or d.d <= a.to_date)
           where a.active and (p_emp is null or a.employee_id = p_emp)
           order by a.employee_id, d.d, a.from_date desc, a.id desc),
  base as (
    select e.id as emp, d.d as day, e.primary_location_id as ploc,
           case when rd.id is not null then rd.shift_id
                when cov.employee_id is not null and (cov.weekday_mask & (1 << extract(dow from d.d)::int)) <> 0 and not public._att_is_off(e.id, d.d) then cov.shift_id end as sid,
           case when rd.id is not null then rd.is_off
                when cov.employee_id is not null then not ((cov.weekday_mask & (1 << extract(dow from d.d)::int)) <> 0 and not public._att_is_off(e.id, d.d)) else false end as off_,
           rd.note as note_, rd.location_id as rloc,
           case when rd.id is not null then 'day' when cov.employee_id is not null then 'pattern' end as src
      from emps e cross join days d
      left join rd on rd.employee_id = e.id and rd.day = d.d
      left join cov on cov.employee_id = e.id and cov.day = d.d
     where rd.id is not null or cov.employee_id is not null),
  placed as (select b.*, coalesce(b.rloc, sh.location_id, b.ploc) as pl from base b left join public.shifts sh on sh.id = b.sid)
  select p.emp, p.day, p.sid, p.off_, p.note_, p.src, p.pl, (public._att_holiday(p.pl, p.day)).name_bn, (public._att_holiday(p.pl, p.day)).name_en
    from placed p where (p_loc is null or p.pl = p_loc);
$$;

-- ============================================================================
-- 4. READ API
-- ============================================================================
create or replace function public.r2_shift_state() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_on boolean := public.rule_on('shift_on');
begin
  if not public.is_active() or not v_on then return jsonb_build_object('on', false, 'can_manage', false, 'locations', '[]'::jsonb, 'linked', false, 'mates_on', false); end if;
  return jsonb_build_object('on', true, 'mates_on', public.rule_on('shift_mates_on'),
    'can_manage', (public.is_owner() or exists (select 1 from public.locations l where l.is_active and public._loc_ok(l.id, 'shift_manage'))),
    'locations', coalesce((select jsonb_agg(l.id order by l.sort, l.id) from public.locations l where l.is_active and public._loc_ok(l.id, 'shift_manage')), '[]'::jsonb),
    'linked', exists (select 1 from public.employees e where e.profile_id = auth.uid() and e.status in ('active', 'on_leave')));
end $$;

create or replace function public.r2_shift_my(p_from date default null, p_days int default 14) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_from date := coalesce(p_from, public._dhaka_today()); v_days int := greatest(1, least(coalesce(p_days, 14), 62)); v_emp uuid; v_mates boolean := public.rule_on('shift_mates_on');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('shift_on') then return jsonb_build_object('on', false, 'linked', false, 'days', '[]'::jsonb); end if;
  select id into v_emp from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if v_emp is null then return jsonb_build_object('on', true, 'linked', false, 'days', '[]'::jsonb); end if;
  return jsonb_build_object('on', true, 'linked', true, 'employee_id', v_emp, 'mates_on', v_mates, 'days', coalesce((
    select jsonb_agg(jsonb_build_object('day', m.day, 'dow', extract(dow from m.day)::int, 'off', m.is_off, 'note', m.note, 'source', m.source, 'place_id', m.place_id,
        'holiday_bn', m.holiday_bn, 'holiday_en', m.holiday_en,
        'leave', exists (select 1 from public.leave_requests lr where lr.employee_id = v_emp and lr.status = 'approved' and m.day between lr.from_date and lr.to_date),
        'shift', case when m.shift_id is null then null else (select jsonb_build_object('id', s.id, 'name_bn', s.name_bn, 'name_en', s.name_en, 'start', to_char(s.start_time, 'HH24:MI'),
                  'end', to_char(s.end_time, 'HH24:MI'), 'crosses_midnight', s.crosses_midnight) from public.shifts s where s.id = m.shift_id) end,
        'mates', case when not v_mates or m.is_off or m.shift_id is null or m.place_id is null then '[]'::jsonb else coalesce((
            select jsonb_agg(jsonb_build_object('name_bn', e2.full_name_bn, 'name_en', e2.full_name_en, 'shift_bn', s2.name_bn, 'shift_en', s2.name_en,
                   'start', to_char(s2.start_time, 'HH24:MI'), 'end', to_char(s2.end_time, 'HH24:MI')) order by s2.start_time, e2.full_name_bn)
              from public._r2_plan(m.day, m.day, null, m.place_id) o join public.employees e2 on e2.id = o.employee_id left join public.shifts s2 on s2.id = o.shift_id
             where o.employee_id <> v_emp and not o.is_off and o.shift_id is not null), '[]'::jsonb) end) order by m.day)
      from public._r2_plan(v_from, v_from + v_days - 1, v_emp) m), '[]'::jsonb));
end $$;

-- the roster grid of one place (schedulers only): people x days, plus the templates that can be used there
create or replace function public.r2_shift_roster(p_loc int, p_from date default null, p_days int default 7) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_from date := coalesce(p_from, public._dhaka_today()); v_days int := greatest(1, least(coalesce(p_days, 7), 31));
begin
  perform public._r2c_gate();
  if not public._loc_ok(p_loc, 'shift_manage') then raise exception 'not allowed'; end if;
  return jsonb_build_object('loc', p_loc, 'from', v_from, 'days', v_days,
    'templates', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name_bn', s.name_bn, 'name_en', s.name_en, 'location_id', s.location_id,
                'start', to_char(s.start_time, 'HH24:MI'), 'end', to_char(s.end_time, 'HH24:MI'), 'crosses_midnight', s.crosses_midnight) order by s.start_time, s.id)
              from public.shifts s where s.active and (s.location_id is null or s.location_id = p_loc)), '[]'::jsonb),
    'employees', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name_bn', e.full_name_bn, 'name_en', e.full_name_en, 'nickname', e.nickname,
        'days', coalesce((select jsonb_agg(jsonb_build_object('day', m.day, 'shift_id', m.shift_id, 'off', m.is_off, 'note', m.note, 'source', m.source,
                  'holiday_bn', m.holiday_bn, 'holiday_en', m.holiday_en,
                  'leave', exists (select 1 from public.leave_requests lr where lr.employee_id = e.id and lr.status = 'approved' and m.day between lr.from_date and lr.to_date)) order by m.day)
                   from public._r2_plan(v_from, v_from + v_days - 1, e.id) m), '[]'::jsonb)) order by e.full_name_bn, e.id)
              from public.employees e where e.primary_location_id = p_loc and e.status in ('active', 'on_leave')), '[]'::jsonb));
end $$;

-- ============================================================================
-- 5. WRITE API (schedulers only; every move is an audit_log line through the table trigger)
-- ============================================================================
create or replace function public.r2_roster_set(p_emp uuid, p_day date, p_shift int, p_off boolean, p_note text default null, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; v_off boolean := coalesce(p_off, false); v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_place int; v_id bigint;
begin
  perform public._r2c_gate();
  select * into e from public.employees where id = p_emp and status in ('active', 'on_leave');
  if not found then raise exception 'not_found'; end if;
  if not public._r2c_ok(p_emp) then raise exception 'not allowed'; end if;
  if p_day is null or p_day < public._dhaka_today() - 7 or p_day > public._dhaka_today() + 400 then raise exception 'bad_date'; end if;
  if v_note is not null and char_length(v_note) > 200 then raise exception 'text_too_long'; end if;
  if v_off = (p_shift is not null) then raise exception 'bad_shift'; end if;                 -- exactly one of: a shift, or an off-day
  if p_shift is not null then
    select * into s from public.shifts where id = p_shift and active;
    if not found then raise exception 'bad_shift'; end if;
  end if;
  v_place := coalesce(p_loc, s.location_id, e.primary_location_id);
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc and is_active) then raise exception 'bad_location'; end if;
  insert into public.r2_roster_days (employee_id, day, shift_id, is_off, note, location_id, set_by)
    values (p_emp, p_day, p_shift, v_off, v_note, v_place, auth.uid())
    on conflict (employee_id, day) where active do update set shift_id = excluded.shift_id, is_off = excluded.is_off, note = excluded.note, location_id = excluded.location_id, set_by = auth.uid(), set_at = now()
    returning id into v_id;
  return jsonb_build_object('id', v_id, 'employee_id', p_emp, 'day', p_day);
end $$;

create or replace function public.r2_roster_clear(p_emp uuid, p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public._r2c_gate();
  if not exists (select 1 from public.employees where id = p_emp) then raise exception 'not_found'; end if;
  if not public._r2c_ok(p_emp) then raise exception 'not allowed'; end if;
  update public.r2_roster_days set active = false, set_by = auth.uid(), set_at = now() where employee_id = p_emp and day = p_day and active returning id into v_id;
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'cleared', v_id is not null);
end $$;

-- one person, seven days at once: p_days is a JSON array of up to 7 items, item i = day p_from + i; null = clear that day,
-- {"shift_id": n} or {"off": true}, optional "note"
create or replace function public.r2_roster_week(p_emp uuid, p_from date, p_days jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i int; it jsonb; n_set int := 0; n_clear int := 0;
begin
  perform public._r2c_gate();
  if p_days is null or jsonb_typeof(p_days) <> 'array' or jsonb_array_length(p_days) > 7 or p_from is null then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.employees where id = p_emp) then raise exception 'not_found'; end if;
  if not public._r2c_ok(p_emp) then raise exception 'not allowed'; end if;
  for i in 0 .. jsonb_array_length(p_days) - 1 loop
    it := p_days -> i;
    if it is null or jsonb_typeof(it) = 'null' then perform public.r2_roster_clear(p_emp, p_from + i); n_clear := n_clear + 1;
    else
      perform public.r2_roster_set(p_emp, p_from + i, nullif(it ->> 'shift_id', '')::int, coalesce((it ->> 'off')::boolean, false), it ->> 'note');
      n_set := n_set + 1;
    end if;
  end loop;
  return jsonb_build_object('employee_id', p_emp, 'set', n_set, 'cleared', n_clear);
end $$;

-- copy the roster rows of one week to another week for everybody whose primary place is p_loc (cells that already have a row are kept)
create or replace function public.r2_roster_copy_week(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; n_copy int := 0; n_skip int := 0; v_off int;
begin
  perform public._r2c_gate();
  if not public._loc_ok(p_loc, 'shift_manage') then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_from = p_to then raise exception 'bad_date'; end if;
  v_off := p_to - p_from;
  for r in select d.* from public.r2_roster_days d join public.employees e on e.id = d.employee_id
            where d.active and d.day between p_from and p_from + 6 and e.primary_location_id = p_loc and e.status in ('active', 'on_leave') order by d.employee_id, d.day loop
    if r.day + v_off < public._dhaka_today() - 7 or r.day + v_off > public._dhaka_today() + 400 then n_skip := n_skip + 1; continue; end if;
    if exists (select 1 from public.r2_roster_days x where x.employee_id = r.employee_id and x.day = r.day + v_off and x.active) then n_skip := n_skip + 1; continue; end if;
    insert into public.r2_roster_days (employee_id, day, shift_id, is_off, note, location_id, set_by) values (r.employee_id, r.day + v_off, r.shift_id, r.is_off, r.note, r.location_id, auth.uid());
    n_copy := n_copy + 1;
  end loop;
  return jsonb_build_object('copied', n_copy, 'skipped', n_skip);
end $$;

-- add / edit / retire a shift template (the existing `shifts` table). data: name_bn, name_en, location_id, start_time, end_time, active
create or replace function public.r2_shift_template_save(p_id int, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'); s public.shifts; v_loc int; v_id int;
begin
  perform public._r2c_gate();
  if p_id is not null then select * into s from public.shifts where id = p_id for update; if not found then raise exception 'not_found'; end if; end if;
  v_loc := case when d ? 'location_id' then public._e_num(d, 'location_id', 1, 100000)::int else s.location_id end;
  if not (public.is_owner() or (v_loc is not null and public._loc_ok(v_loc, 'shift_manage') and (p_id is null or s.location_id is not distinct from v_loc))) then raise exception 'not allowed'; end if;
  if v_loc is not null and not exists (select 1 from public.locations where id = v_loc and is_active) then raise exception 'bad_location'; end if;
  s.name_bn := coalesce(public._e_txt(d, 'name_bn', 60), s.name_bn);
  s.name_en := case when d ? 'name_en' then public._e_txt(d, 'name_en', 60) else s.name_en end;
  s.location_id := v_loc;
  s.start_time := coalesce(public._hhmm(d ->> 'start_time'), s.start_time);
  s.end_time := coalesce(public._hhmm(d ->> 'end_time'), s.end_time);
  s.active := coalesce((d ->> 'active')::boolean, s.active, true);
  if s.name_bn is null then raise exception 'name_required'; end if;
  if s.start_time is null or s.end_time is null then raise exception 'bad_time'; end if;
  s.crosses_midnight := s.end_time <= s.start_time;
  if p_id is null then
    insert into public.shifts (name_bn, name_en, location_id, start_time, end_time, crosses_midnight, active, created_by)
      values (s.name_bn, s.name_en, s.location_id, s.start_time, s.end_time, s.crosses_midnight, s.active, auth.uid()) returning id into v_id;
  else
    update public.shifts set name_bn = s.name_bn, name_en = s.name_en, location_id = s.location_id, start_time = s.start_time, end_time = s.end_time, crosses_midnight = s.crosses_midnight, active = s.active where id = p_id;
    v_id := p_id;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

-- ============================================================================
-- 6. SOFT LINK TO ATTENDANCE: roster versus what really happened (read only; answers "attendance: false" if the table is missing)
-- ============================================================================
create or replace function public.r2_shift_report(p_loc int, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_to date := least(coalesce(p_to, public._dhaka_today()), public._dhaka_today()); v_from date := coalesce(p_from, v_to - 6); v_rows jsonb; v_tot jsonb;
begin
  perform public._r2c_gate();
  if not (public._loc_ok(p_loc, 'shift_manage') or public._loc_ok(p_loc, 'attendance_manage')) then raise exception 'not allowed'; end if;
  if v_from > v_to or v_to - v_from > 61 then raise exception 'bad_date'; end if;
  if to_regclass('public.attendance_days') is null then return jsonb_build_object('attendance', false, 'from', v_from, 'to', v_to, 'rows', '[]'::jsonb, 'totals', '{}'::jsonb); end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.employee_id, 'name_bn', x.name_bn, 'name_en', x.name_en, 'day', x.day, 'planned', x.planned, 'shift_bn', x.shift_bn,
             'start', x.st, 'end', x.en, 'attendance', x.att, 'first_in', x.first_in, 'late_minutes', x.late_minutes, 'result', x.result) order by x.day, x.name_bn), '[]'::jsonb)
      from (select pl.employee_id, e.full_name_bn as name_bn, e.full_name_en as name_en, pl.day, (not pl.is_off) as planned, s.name_bn as shift_bn,
                   to_char(s.start_time, 'HH24:MI') as st, to_char(s.end_time, 'HH24:MI') as en, a.status as att, a.first_in, a.late_minutes,
                   case when not pl.is_off then case when a.employee_id is null then 'no_record' when a.status = 'present' then 'ok' when a.status = 'late' then 'late' when a.status = 'half_day' then 'half_day'
                                                    when a.status = 'leave' then 'leave' when a.status in ('absent', 'unpaid') then 'absent' else 'other' end
                        else case when a.status in ('present', 'late', 'half_day') then 'worked_off' else 'off' end end as result
              from public._r2_plan($1, $2, null, $3) pl join public.employees e on e.id = pl.employee_id
              left join public.shifts s on s.id = pl.shift_id
              left join public.attendance_days a on a.employee_id = pl.employee_id and a.day = pl.day
             where pl.day <= (now() at time zone 'Asia/Dhaka')::date
             order by pl.day, e.full_name_bn limit 600) x
  $q$ into v_rows using v_from, v_to, p_loc;
  select coalesce(jsonb_object_agg(k, c), '{}'::jsonb) into v_tot from (select r ->> 'result' as k, count(*) as c from jsonb_array_elements(v_rows) r group by 1) z;
  return jsonb_build_object('attendance', true, 'from', v_from, 'to', v_to, 'rows', v_rows, 'totals', v_tot);
end $$;

-- ============================================================================
-- 7. WHO MAY CALL WHAT
-- ============================================================================
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('r2_shift_state', 'r2_shift_my', 'r2_shift_roster', 'r2_roster_set', 'r2_roster_clear', 'r2_roster_week', 'r2_roster_copy_week',
                                                            'r2_shift_template_save', 'r2_shift_report', '_r2c_gate', '_r2c_ok', '_r2_plan', '_r2c_present') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname like 'r2\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;
