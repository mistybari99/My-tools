-- Phase 409 (bos409) - RPT-B4 / R5a: SALES TARGETS AND DAILY KPI SNAPSHOTS, TABLES, SETTINGS AND TARGET ENTRY.
-- Paste after phase404 (it uses the helpers _rb4_today / _rb4_range; phases 405-408 are not needed by this file). Paste-twice safe. No earlier phase file is edited; no shared function is re-created.
-- Requirements: docs/REPORTS_AUDIT_1.md items #9, #24 (target vs achievement) and #10 (KPI trends and exception alerts).
--
-- WHAT THIS ADDS
--   sales_targets   the owner's target per outlet and month: an amount, and optionally a gross-profit %. A change retires the old line and writes a new one (history kept). No target = "target not set".
--   kpi_snapshots   one row per day, place and measure (phase 410 fills it); only additive measures are stored, ratios are worked out when read.
--   grant sales_target_manage   who may set targets. By default NOBODY but the owner holds it (the owner can hand it to a role in the permission matrix).
--   settings (all blank = off): kpi_alert_sales_drop_pct, kpi_alert_discount_pct, kpi_alert_void_n. No limit is invented: a blank limit means no alert of that kind, and the screen says so.
-- Nothing here moves stock or money. Paper form code of the target entry screen: to be given by owner.

do $g$ begin
  if to_regclass('public.sales') is null or to_regclass('public.sale_returns') is null then raise exception 'phase409 needs the sales phases'; end if;
  if to_regprocedure('public.log_change()') is null then raise exception 'phase409 needs log_change'; end if;
  if to_regprocedure('public._rb4_today()') is null then raise exception 'phase409 needs phase404 first'; end if;
end $g$;

-- ---------- grant (nobody holds it by default except the owner, who always may) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('sales_target_manage', 'reports', 70, 'বিক্রির লক্ষ্য ঠিক করা', 'Sales target ঠিক করা', 'Set sales targets', 'once', null)
on conflict (grant_code) do nothing;

-- ---------- settings (blank = no alert of that kind) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('kpi_alert_sales_drop_pct', 'reports', 'number', null, null, 0, 100,
  'দিনের বিক্রি আগের ৪টি একই বারের গড়ের চেয়ে এর বেশি % কম হলে সতর্কতা', 'Day''s sales এর চেয়ে বেশি % কম হলে সতর্কতা (আগের ৪টি একই বারের গড়ের তুলনায়)',
  'Alert when a day''s sales are lower than the average of the previous 4 same weekdays by more than this %',
  'Blank = no sales-drop alert. Needs at least 2 earlier snapshot days of the same weekday; with fewer the screen says "not enough history". Display only: it changes nothing.', 7001),
 ('kpi_alert_discount_pct', 'reports', 'number', null, null, 0, 100,
  'দিনের ডিসকাউন্ট বিক্রির (ডিসকাউন্টের আগে) এর বেশি % হলে সতর্কতা', 'Day''s discount এর বেশি % হলে সতর্কতা (ডিসকাউন্টের আগের বিক্রির)',
  'Alert when a day''s discount is more than this % of the sales before discount',
  'Blank = no discount alert. Display only.', 7002),
 ('kpi_alert_void_n', 'reports', 'number', null, null, 0, 100000,
  'এক দিনে এর বেশি বাতিল বিক্রি হলে সতর্কতা', 'এক দিনে এর বেশি void sale হলে সতর্কতা',
  'Alert when a place has more than this many voided sales in one day',
  'Blank = no void alert. Display only.', 7003)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.sales_targets (
  id bigserial primary key,
  location_id int not null references public.locations(id),
  month date not null check (extract(day from month) = 1),          -- the first day of the month
  amount numeric not null check (amount >= 0 and amount <= 1000000000000),
  gp_pct numeric check (gp_pct is null or (gp_pct >= 0 and gp_pct <= 100)),
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'retired')),
  retired_note text, retired_by uuid, retired_at timestamptz,
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create unique index if not exists sales_targets_one_active on public.sales_targets (location_id, month) where status = 'active';
create index if not exists sales_targets_month on public.sales_targets (month, location_id);

create table if not exists public.kpi_snapshots (
  snap_date date not null,
  location_id int not null references public.locations(id),
  kpi text not null check (kpi ~ '^[a-z0-9_]{2,40}$'),
  value numeric,                                                       -- blank = could not be worked out (never 0)
  computed_at timestamptz not null default now(),
  computed_by uuid,
  primary key (snap_date, location_id, kpi)
);
create index if not exists kpi_snapshots_loc on public.kpi_snapshots (location_id, snap_date);

drop trigger if exists audit_sales_targets on public.sales_targets;
create trigger audit_sales_targets after insert or update on public.sales_targets for each row execute function public.log_change('id');
alter table public.sales_targets enable row level security;
alter table public.kpi_snapshots enable row level security;
revoke all on public.sales_targets, public.kpi_snapshots from public, anon, authenticated;
revoke all on sequence public.sales_targets_id_seq from public, anon, authenticated;

-- ---------- who may read / write ----------
-- reading targets and KPIs: the owner or the sales report right (rpt_access('sales') also covers view_reports), and the place must be theirs
create or replace function public._rb4_target_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('sales') or public.has_grant('report_pos', p_loc));
$$;
create or replace function public._rb4_target_edit() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('sales_target_manage'));
$$;
drop policy if exists sales_targets_read on public.sales_targets;
create policy sales_targets_read on public.sales_targets for select to authenticated using (public._rb4_target_view(location_id));
drop policy if exists kpi_snapshots_read on public.kpi_snapshots;
create policy kpi_snapshots_read on public.kpi_snapshots for select to authenticated using (public._rb4_target_view(location_id));
grant select on public.sales_targets, public.kpi_snapshots to authenticated;

-- ---------- target entry ----------
-- p_month = any day of the month (the first of that month is stored). A second call for the same place + month retires the old line (kept as history) and writes the new one.
create or replace function public.sales_target_set(p_loc int, p_month date, p_amount numeric, p_gp_pct numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date; sid text; id_ bigint; old public.sales_targets; n text := nullif(btrim(p_note), '');
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._rb4_target_edit() then raise exception 'not allowed'; end if;
  if p_loc is null or not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if p_month is null then raise exception 'bad_date'; end if;
  m := date_trunc('month', p_month)::date;
  if abs(m - public._rb4_today()) > 800 then raise exception 'bad_date'; end if;
  if p_amount is null or not (p_amount >= 0 and p_amount <= 1000000000000) then raise exception 'bad_amount'; end if;
  if p_gp_pct is not null and not (p_gp_pct >= 0 and p_gp_pct <= 100) then raise exception 'bad_gp_pct'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  select * into old from public.sales_targets where location_id = p_loc and month = m and status = 'active' for update;
  if found and old.amount = p_amount and old.gp_pct is not distinct from p_gp_pct then return jsonb_build_object('dup', true, 'id', old.id); end if;
  if found then
    update public.sales_targets set status = 'retired', retired_note = 'replaced by a new target', retired_by = auth.uid(), retired_at = now() where id = old.id;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.sales_targets (location_id, month, amount, gp_pct, note, created_by, created_staff) values (p_loc, m, p_amount, p_gp_pct, n, auth.uid(), sid) returning id into id_;
  return jsonb_build_object('id', id_, 'month', m, 'replaced', old.id);
end $$;

create or replace function public.sales_target_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sales_targets;
begin
  if not public._rb4_target_edit() then raise exception 'not allowed'; end if;
  select * into r from public.sales_targets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed'; end if;
  if r.status = 'retired' then return jsonb_build_object('dup', true, 'status', 'retired'); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.sales_targets set status = 'retired', retired_note = left(btrim(p_note), 300), retired_by = auth.uid(), retired_at = now() where id = p_id;
  return jsonb_build_object('status', 'retired');
end $$;

create or replace function public.sales_target_list(p_from date default null, p_to date default null, p_loc int default null, p_with_retired boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := date_trunc('month', coalesce(p_from, public._rb4_today()))::date; t date := date_trunc('month', coalesce(p_to, public._rb4_today() + 62))::date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb4_target_view(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('from', f, 'to', t, 'can_edit', public._rb4_target_edit(), 'rows', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'location_id', s.location_id, 'location', l.name_bn, 'location_en', l.name_en,
      'month', s.month, 'amount', s.amount, 'gp_pct', s.gp_pct, 'note', s.note, 'status', s.status, 'retired_note', s.retired_note, 'created_staff', s.created_staff, 'created_at', s.created_at)
      order by s.month, l.sort, s.id)
    from public.sales_targets s join public.locations l on l.id = s.location_id
   where s.month between f and t and (p_loc is null or s.location_id = p_loc) and public._rb4_target_view(s.location_id) and (coalesce(p_with_retired, false) or s.status = 'active')), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_target_view', '_rb4_target_edit') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);      -- used by the row-level-security policies
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('sales_target_set', 'sales_target_retire', 'sales_target_list') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
