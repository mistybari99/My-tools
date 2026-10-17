-- ============================================================
-- Phase 542 - XB package part 3: riders, delivery status, delivery zones, COD collected and deposited per rider per day.
-- Run AFTER phase 541. New file only; no old phase or function is edited. Paste twice = no error, no second row.
--
--   * riders                 staff or external rider master (name_bn / name_en, kind, optional employee link, phone, place, active). Owner or grant rider_manage.
--   * delivery_zones        zone fee table (owner or rider_manage). A zone with no fee cannot be assigned (nothing invented).
--   * delivery_jobs         one per app order: rider, zone, fee, attempts, live-location link (a https maps link the rider shares; no tracking is built),
--                           COD amount (= the order balance at handover). States: assigned -> out -> delivered | failed;
--                           failed -> assigned (reattempt, attempts + 1) or failed -> returned (back to the shop). Every move in delivery_events.
--   * cod_deposits          money a rider hands in (append-only, client id).
--   * xb_cod_reconcile      per rider per day: COD collected on delivered jobs, deposited, difference (short / over). Information only.
--   * cod_cases             one open case per rider per day with a difference; the owner explains it. NOTHING is posted to cash or the books:
--                           linking a short to the existing shortage cases needs an entry row and is an owner decision (not built).
--   * xb_rider_perf         deliveries, failed, returned, average minutes from handover to delivered, per rider for a date range.
--   * Rules: xb_delivery_on (OFF). When OFF every writer here is refused. Nothing is sent to riders or customers by this phase.
-- ============================================================
do $guard$ begin
  if to_regclass('public.online_orders') is null or to_regclass('public.employees') is null or to_regprocedure('public.xb_cake_create(uuid,uuid,date,time,numeric,text,int,text,text[],text,boolean,boolean,text,text[],numeric)') is null then
    raise exception 'phase542 needs phase541 (and phase61 / phase41 employees) pasted first';
  end if;
end $guard$;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('xb_delivery_on', 'pos', 'switch', 'false', null, null, null, null, 'রাইডার ও ডেলিভারি ট্র্যাকিং চালু', 'Rider & delivery tracking চালু', 'Rider and delivery tracking is on',
  'চালু হলে রাইডার, ডেলিভারির অবস্থা, COD জমা ও হিসাব লেখা যাবে। কিছু পাঠানো হয় না।', 'When on, riders, delivery status and COD deposits can be recorded. Nothing is sent by this.', 546)
on conflict (key) do nothing;
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('rider_manage', 'pos', 92, 'রাইডার ও জোন ঠিক করা', 'Rider ও zone ঠিক করা', 'Manage riders and delivery zones', 'once', null)
on conflict (grant_code) do nothing;

create or replace function public._xb542_gate(p_loc int) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('xb_delivery_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', 'enter') or (p_loc is not null and not public.can_loc(p_loc)) then raise exception 'not allowed'; end if;
end $$;
create or replace function public._xb542_manage() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'rider_manage' and g.location_id is null));
$$;
create or replace function public._xb542_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: this trail or deposit is never changed or deleted'; end $$;

-- ---------- riders and zones ----------
create table if not exists public.riders (
  id bigint generated always as identity primary key,
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or char_length(name_en) <= 80),
  kind text not null check (kind in ('staff', 'external')),
  employee_id uuid references public.employees(id),
  phone text check (phone is null or char_length(phone) between 6 and 20),
  location_id int references public.locations(id),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  check ((kind = 'staff') = (employee_id is not null) or kind = 'external')
);
create table if not exists public.delivery_zones (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text not null check (char_length(btrim(name_en)) between 1 and 80),
  fee numeric not null check (fee >= 0 and fee <= 1000000),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
drop trigger if exists riders_nodel on public.riders;
create trigger riders_nodel before delete on public.riders for each row execute function public._xb542_ro();
drop trigger if exists delivery_zones_nodel on public.delivery_zones;
create trigger delivery_zones_nodel before delete on public.delivery_zones for each row execute function public._xb542_ro();
drop trigger if exists audit_riders on public.riders;
create trigger audit_riders after insert or update on public.riders for each row execute function public.log_change('id');
drop trigger if exists audit_delivery_zones on public.delivery_zones;
create trigger audit_delivery_zones after insert or update on public.delivery_zones for each row execute function public.log_change('code');

create or replace function public.xb_rider_save(p_id bigint, p_name_bn text, p_name_en text, p_kind text, p_employee uuid, p_phone text, p_loc int, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if not public._xb542_manage() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null or p_kind not in ('staff', 'external') or p_active is null then raise exception 'bad_input'; end if;
  if p_kind = 'staff' and (p_employee is null or not exists (select 1 from public.employees e where e.id = p_employee)) then raise exception 'employee_required'; end if;
  if p_kind = 'external' then p_employee := null; end if;
  if p_id is null then
    insert into public.riders (name_bn, name_en, kind, employee_id, phone, location_id, active, created_by)
      values (left(btrim(p_name_bn), 80), left(nullif(btrim(p_name_en), ''), 80), p_kind, p_employee, nullif(btrim(p_phone), ''), p_loc, p_active, auth.uid()) returning id into id_;
  else
    update public.riders set name_bn = left(btrim(p_name_bn), 80), name_en = left(nullif(btrim(p_name_en), ''), 80), kind = p_kind, employee_id = p_employee,
      phone = nullif(btrim(p_phone), ''), location_id = p_loc, active = p_active where id = p_id returning id into id_;
    if id_ is null then raise exception 'not_found'; end if;
  end if;
  return jsonb_build_object('id', id_);
end $$;

create or replace function public.xb_delivery_zone_save(p_code text, p_name_bn text, p_name_en text, p_fee numeric, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._xb542_manage() then raise exception 'not allowed'; end if;
  if p_code !~ '^[a-z0-9_]{2,30}$' or p_fee is null or p_fee < 0 or p_fee > 1000000 or p_active is null then raise exception 'bad_input'; end if;
  insert into public.delivery_zones (code, name_bn, name_en, fee, active, updated_by) values (p_code, left(btrim(p_name_bn), 80), left(btrim(p_name_en), 80), p_fee, p_active, auth.uid())
    on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en, fee = excluded.fee, active = excluded.active, updated_by = excluded.updated_by, updated_at = now();
  return jsonb_build_object('code', p_code, 'fee', p_fee);
end $$;

-- ---------- delivery jobs ----------
create table if not exists public.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.online_orders(id),
  location_id int not null references public.locations(id),
  rider_id bigint references public.riders(id),
  zone_code text references public.delivery_zones(code),
  fee numeric check (fee is null or fee >= 0),
  attempts int not null default 0 check (attempts >= 0 and attempts <= 10),
  map_link text check (map_link is null or (map_link ~ '^https://' and char_length(map_link) <= 300)),
  cod_amount numeric check (cod_amount is null or cod_amount >= 0),
  state text not null default 'unassigned' check (state in ('unassigned', 'assigned', 'out', 'delivered', 'failed', 'returned')),
  handed_at timestamptz, delivered_at timestamptz, failed_reason text check (failed_reason is null or char_length(failed_reason) <= 300),
  cod_collected numeric check (cod_collected is null or cod_collected >= 0),
  created_by uuid, created_at timestamptz not null default now(), state_at timestamptz not null default now()
);
create table if not exists public.delivery_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.delivery_jobs(id),
  from_state text, to_state text not null, note text check (note is null or char_length(note) <= 300),
  by_user uuid, by_staff text, at timestamptz not null default now()
);
create table if not exists public.cod_deposits (
  id bigint generated always as identity primary key,
  client_id uuid unique,
  rider_id bigint not null references public.riders(id),
  location_id int not null references public.locations(id),
  deposit_day date not null,
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  note text check (note is null or char_length(note) <= 300),
  deposited_by uuid, deposited_staff text, deposited_at timestamptz not null default now()
);
create table if not exists public.cod_cases (
  id bigint generated always as identity primary key,
  rider_id bigint not null references public.riders(id),
  location_id int not null references public.locations(id),
  case_day date not null,
  collected numeric not null, deposited numeric not null, difference numeric not null check (difference <> 0),
  state text not null default 'open' check (state in ('open', 'explained')),
  explain_note text check (explain_note is null or char_length(explain_note) <= 300),
  explained_by uuid, explained_at timestamptz,
  opened_at timestamptz not null default now(),
  unique (rider_id, case_day)
);
drop trigger if exists delivery_events_ro on public.delivery_events;
create trigger delivery_events_ro before update or delete on public.delivery_events for each row execute function public._xb542_ro();
drop trigger if exists cod_deposits_ro on public.cod_deposits;
create trigger cod_deposits_ro before update or delete on public.cod_deposits for each row execute function public._xb542_ro();
drop trigger if exists audit_delivery_jobs on public.delivery_jobs;
create trigger audit_delivery_jobs after insert or update on public.delivery_jobs for each row execute function public.log_change('id');
drop trigger if exists audit_cod_deposits on public.cod_deposits;
create trigger audit_cod_deposits after insert on public.cod_deposits for each row execute function public.log_change('id');

-- delivery_jobs: state, attempts, link, cod and the rider move; the order and zone fee are fixed once a job exists
create or replace function public._xb542_job_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted: a delivery is returned or closed'; end if;
  if old.state in ('delivered', 'returned') and new.state is distinct from old.state then raise exception 'closed: a delivered or returned job cannot change'; end if;
  if (to_jsonb(new) - 'state' - 'state_at' - 'attempts' - 'rider_id' - 'handed_at' - 'delivered_at' - 'failed_reason' - 'map_link' - 'cod_collected' - 'updated_at')
     is distinct from (to_jsonb(old) - 'state' - 'state_at' - 'attempts' - 'rider_id' - 'handed_at' - 'delivered_at' - 'failed_reason' - 'map_link' - 'cod_collected' - 'updated_at') then
    raise exception 'the order, zone and fee of a delivery are fixed';
  end if;
  return new;
end $$;
drop trigger if exists delivery_jobs_guard on public.delivery_jobs;
create trigger delivery_jobs_guard before update or delete on public.delivery_jobs for each row execute function public._xb542_job_guard();

-- assign a rider and a zone (fee from the zone table; a zone with no fee is refused by the table itself)
create or replace function public.xb_delivery_assign(p_order uuid, p_rider bigint, p_zone text, p_map_link text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; z public.delivery_zones; r public.riders; j public.delivery_jobs; bal numeric;
begin
  select * into o from public.online_orders where id = p_order;
  if not found then raise exception 'not_found'; end if;
  perform public._xb542_gate(o.location_id);
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
  select * into r from public.riders where id = p_rider and active;
  if not found then raise exception 'rider_not_found_or_inactive'; end if;
  if r.location_id is not null and r.location_id <> o.location_id then raise exception 'rider_other_location'; end if;
  select * into z from public.delivery_zones where code = p_zone and active;
  if not found then raise exception 'zone_not_found_or_inactive'; end if;
  bal := o.subtotal - o.discount + o.delivery_charge - o.advance;
  select * into j from public.delivery_jobs where order_id = o.id for update;
  if not found then
    insert into public.delivery_jobs (order_id, location_id, rider_id, zone_code, fee, map_link, cod_amount, state, created_by)
      values (o.id, o.location_id, r.id, z.code, z.fee, nullif(btrim(p_map_link), ''), greatest(bal, 0), 'assigned', auth.uid()) returning * into j;
    insert into public.delivery_events (job_id, from_state, to_state, note, by_user, by_staff) values (j.id, 'unassigned', 'assigned', 'rider ' || r.name_en, auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  else
    if j.state not in ('unassigned', 'assigned') then raise exception 'bad_status: a job on the road cannot change rider'; end if;
    update public.delivery_jobs set rider_id = r.id, state = 'assigned', state_at = now(), map_link = coalesce(nullif(btrim(p_map_link), ''), map_link) where id = j.id returning * into j;
  end if;
  return jsonb_build_object('id', j.id, 'state', j.state, 'rider_id', r.id, 'zone', z.code, 'fee', z.fee, 'cod_amount', j.cod_amount);
end $$;

-- out (handed to rider), delivered (COD collected stated), failed (reason), reattempt (failed -> assigned), returned (failed -> back to shop)
create or replace function public.xb_delivery_move(p_job uuid, p_to text, p_cod numeric default null, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare j public.delivery_jobs; from_s text; n int;
begin
  select * into j from public.delivery_jobs where id = p_job for update;
  if not found then raise exception 'not_found'; end if;
  perform public._xb542_gate(j.location_id);
  from_s := j.state;
  if p_to not in ('out', 'delivered', 'failed', 'reattempt', 'returned') then raise exception 'bad_status'; end if;
  if p_to = 'out' and from_s = 'assigned' then
    update public.delivery_jobs set state = 'out', handed_at = now(), state_at = now() where id = j.id;
  elsif p_to = 'delivered' and from_s = 'out' then
    if p_cod is not null and (p_cod < 0 or p_cod > 1000000000) then raise exception 'bad_amount'; end if;
    update public.delivery_jobs set state = 'delivered', delivered_at = now(), state_at = now(), cod_collected = coalesce(p_cod, cod_amount) where id = j.id;
  elsif p_to = 'failed' and from_s = 'out' then
    if nullif(btrim(coalesce(p_reason, '')), '') is null then raise exception 'reason_required'; end if;
    update public.delivery_jobs set state = 'failed', failed_reason = left(btrim(p_reason), 300), state_at = now(), attempts = attempts + 1 where id = j.id;
  elsif p_to = 'reattempt' and from_s = 'failed' then
    if j.attempts >= 3 then raise exception 'too_many_attempts: return the goods to the shop'; end if;
    update public.delivery_jobs set state = 'assigned', state_at = now(), handed_at = null where id = j.id;
    p_to := 'assigned';
  elsif p_to = 'returned' and from_s = 'failed' then
    update public.delivery_jobs set state = 'returned', state_at = now() where id = j.id;
  else
    raise exception 'bad_status: % -> % is not allowed', from_s, p_to;
  end if;
  insert into public.delivery_events (job_id, from_state, to_state, note, by_user, by_staff)
    values (j.id, from_s, p_to, left(nullif(btrim(coalesce(p_reason, '')), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
  return jsonb_build_object('id', j.id, 'state', p_to, 'attempts', (select attempts from public.delivery_jobs where id = j.id));
end $$;

-- COD deposit: what a rider hands in on a day (no cash move is posted here)
create or replace function public.xb_cod_deposit(p_client uuid, p_rider bigint, p_loc int, p_day date, p_amount numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare id_ bigint;
begin
  if p_client is not null and exists (select 1 from public.cod_deposits where client_id = p_client) then
    return jsonb_build_object('dup', true, 'id', (select id from public.cod_deposits where client_id = p_client));
  end if;
  perform public._xb542_gate(p_loc);
  if p_amount is null or p_amount <= 0 or p_amount > 1000000000 then raise exception 'bad_amount'; end if;
  if p_day is null or p_day > (now() at time zone 'Asia/Dhaka')::date then raise exception 'bad_date'; end if;
  if not exists (select 1 from public.riders where id = p_rider and active) then raise exception 'rider_not_found_or_inactive'; end if;
  insert into public.cod_deposits (client_id, rider_id, location_id, deposit_day, amount, note, deposited_by, deposited_staff)
    values (p_client, p_rider, p_loc, p_day, round(p_amount, 2), left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()))
    returning id into id_;
  return jsonb_build_object('id', id_, 'dup', false);
end $$;

-- per rider per day: collected (delivered jobs of that day) versus deposited. A difference opens one case (owner explains it).
create or replace function public.xb_cod_reconcile(p_day date, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rr record; col numeric; dep numeric; rows_ jsonb := '[]';
begin
  if not public.is_active() or not (public.is_owner() or public.can_do('POS', 'view')) then raise exception 'not allowed'; end if;
  for rr in select r.id, r.name_en, r.name_bn from public.riders r where r.active and (p_loc is null or r.location_id is null or r.location_id = p_loc) order by r.id loop
    select coalesce(sum(j.cod_collected), 0) into col from public.delivery_jobs j
     where j.rider_id = rr.id and j.state = 'delivered' and (j.delivered_at at time zone 'Asia/Dhaka')::date = p_day and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id);
    select coalesce(sum(d.amount), 0) into dep from public.cod_deposits d where d.rider_id = rr.id and d.deposit_day = p_day and (p_loc is null or d.location_id = p_loc) and public.can_loc(d.location_id);
    rows_ := rows_ || jsonb_build_object('rider_id', rr.id, 'rider', coalesce(rr.name_en, rr.name_bn), 'collected', col, 'deposited', dep, 'difference', col - dep,
      'status', case when col - dep = 0 then 'matched' when col - dep > 0 then 'short' else 'over' end);
    if col - dep <> 0 and (p_loc is not null) then
      insert into public.cod_cases (rider_id, location_id, case_day, collected, deposited, difference)
        values (rr.id, p_loc, p_day, col, dep, col - dep) on conflict (rider_id, case_day) do nothing;
    end if;
  end loop;
  return jsonb_build_object('day', p_day, 'riders', rows_, 'notes', jsonb_build_array('information_only_no_cash_is_posted', 'a_difference_opens_a_case_for_the_owner_to_explain'));
end $$;

create or replace function public.xb_cod_case_explain(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.cod_cases;
begin
  if not public._xb542_manage() and not public.is_owner() then raise exception 'not allowed'; end if;
  select * into c from public.cod_cases where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if c.state <> 'open' then raise exception 'already_explained'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.cod_cases set state = 'explained', explain_note = left(btrim(p_note), 300), explained_by = auth.uid(), explained_at = now() where id = c.id;
  return jsonb_build_object('id', c.id, 'state', 'explained');
end $$;

-- performance per rider over a date range (handover date)
create or replace function public.xb_rider_perf(p_from date, p_to date, p_loc int default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_active() or not (public.is_owner() or public.can_do('POS', 'view')) then '[]'::jsonb else coalesce((
    select jsonb_agg(z.row_json order by z.rid) from (
      select r.id as rid, jsonb_build_object('rider_id', r.id, 'rider', coalesce(r.name_en, r.name_bn),
        'jobs', count(j.id), 'delivered', count(j.id) filter (where j.state = 'delivered'), 'failed', count(j.id) filter (where j.state in ('failed', 'returned')),
        'returned', count(j.id) filter (where j.state = 'returned'), 'open', count(j.id) filter (where j.state in ('unassigned', 'assigned', 'out')),
        'avg_minutes_to_deliver', round(avg(extract(epoch from (j.delivered_at - j.handed_at)) / 60) filter (where j.state = 'delivered' and j.handed_at is not null), 1)) as row_json
      from public.riders r left join public.delivery_jobs j on j.rider_id = r.id and (j.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to
        and (p_loc is null or j.location_id = p_loc) and public.can_loc(j.location_id)
      where r.active group by r.id) z), '[]'::jsonb) end;
$$;

-- ---------- privileges and RLS ----------
alter table public.riders enable row level security;
alter table public.delivery_zones enable row level security;
alter table public.delivery_jobs enable row level security;
alter table public.delivery_events enable row level security;
alter table public.cod_deposits enable row level security;
alter table public.cod_cases enable row level security;
revoke all on public.riders, public.delivery_zones, public.delivery_jobs, public.delivery_events, public.cod_deposits, public.cod_cases from public, anon, authenticated;
grant select on public.riders, public.delivery_zones, public.delivery_jobs, public.delivery_events, public.cod_deposits, public.cod_cases to authenticated;
drop policy if exists riders_sel on public.riders;
create policy riders_sel on public.riders for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists delivery_zones_sel on public.delivery_zones;
create policy delivery_zones_sel on public.delivery_zones for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')));
drop policy if exists delivery_jobs_sel on public.delivery_jobs;
create policy delivery_jobs_sel on public.delivery_jobs for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists delivery_events_sel on public.delivery_events;
create policy delivery_events_sel on public.delivery_events for select to authenticated
  using (public.is_active() and exists (select 1 from public.delivery_jobs j where j.id = job_id and public.can_loc(j.location_id)));
drop policy if exists cod_deposits_sel on public.cod_deposits;
create policy cod_deposits_sel on public.cod_deposits for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));
drop policy if exists cod_cases_sel on public.cod_cases;
create policy cod_cases_sel on public.cod_cases for select to authenticated using (public.is_active() and (public.is_owner() or public.can_do('POS', 'view')) and public.can_loc(location_id));

do $x$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like 'xb\_rider\_%' or p.proname like 'xb\_delivery\_%' or p.proname like 'xb\_cod\_%' or p.proname like 'xb\_rider\_perf%'
                  or p.proname like '\_xb542\_%') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname not like '\_xb542\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $x$;
notify pgrst, 'reload schema';
