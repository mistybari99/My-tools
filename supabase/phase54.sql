-- ============================================================
-- Phase 54 - P2c: attendance, two paths counted once (gap #29) + form equation recompute (gap #20, safe core).
-- Run AFTER phase51 (needs phase42 attendance + phase48-50 path engine). Idempotent (paste twice = no error). No existing row is changed or deleted.
--
--   ATTENDANCE  path A = staff attendance (device / finger file / app punch / manager entry -> attendance_punches + attendance_days),
--               path B = the monthly paper register, form 02-1.   Same place + month = same event.
--               Owner default: path A is the record; an 02-1 that is submitted/approved for a month that path A already holds becomes a LOCKED SHADOW
--               copy (kept, shown, never counted again). Owner may switch primary to the form, or lock either path (Switch board, domain 'attendance').
--               Form 14-1 (daily showroom sheet) is NOT mapped to this domain: it is the cash drawer sheet, locking it would stop the drawer count.
--   (a) SELF PUNCH  staff punch from the phone (attendance_self_punch). Master switch = existing rule app_punch_on (OFF). Owner can lock one person
--               or one role (att_self_lock). A lock never deletes anything; it only refuses NEW self punches.
--   (b) EVIDENCE    fingerprint / face / browser-passkey registration is EVIDENCE ONLY: a flag + a reference (photo path, passkey id, device user id).
--               No biometric template is stored. The server cannot verify a passkey assertion or a face, so nothing here proves identity.
--               GPS is a SOFT flag (rule att_geo_check_on, OFF): a punch outside the radius is recorded and flagged, never refused.
--   (c) MARK OTHERS new grant attendance_mark_others (no role has it by default; the owner gives it to a person). Lets a manager mark another person's
--               day status, rest time and closing time by hand with a source tag device/finger/face/manual. Every call is written to an append-only log.
--               The tag is the manager's declaration, not a proof. Cannot mark himself. A month locked by approved/paid payroll is refused (month_locked).
--   EQUATIONS   entry_equation_check(entry) re-works the key totals of 10-2 and 02-2 on the server and lists differences against the flags the phone
--               stored. Rule entry_equation_flag_on (OFF): when ON, a submitted 10-2 / 02-2 that differs gets one red exception 'equation_mismatch'.
--   Re-created from the latest definition: attendance_app_punch (now a thin wrapper of attendance_self_punch; same errors, same 1-minute rule).
-- ============================================================

-- ---------- 1. the shadow engine: new domain ----------
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('attendance', 'কর্মী হাজিরা (মেশিন / অ্যাপ পাঞ্চ)', 'Staff attendance (device / app punch)', 'ফর্ম 02-1 (মাসিক হাজিরা রেজিস্টার)', 'Form 02-1 (monthly attendance register)', 'a',
  'ডিফল্ট: পাঞ্চ/হাজিরা রেকর্ড মূল; সেই মাসের 02-1 লক করা শ্যাডো কপি। শুধু মাস-পর্যায়ের মিল; কাউকে শনাক্তের প্রমাণ নয়।',
  'Default: punch / attendance record is primary; the 02-1 of a month that path A holds is a locked shadow. Month-level match only; not proof of anybody''s identity.', 60)
on conflict (domain) do nothing;

-- ---------- 2. columns ----------
alter table public.attendance_days add column if not exists rest_minutes int check (rest_minutes is null or rest_minutes between 0 and 720);
alter table public.attendance_days add column if not exists mark_source text check (mark_source is null or mark_source in ('device', 'finger', 'face', 'manual'));
alter table public.attendance_punches add column if not exists evidence_kind text check (evidence_kind is null or evidence_kind in ('webauthn', 'face_photo'));
alter table public.attendance_punches add column if not exists evidence_ref text check (evidence_ref is null or char_length(evidence_ref) <= 300);
alter table public.attendance_punches add column if not exists evidence_state text check (evidence_state is null or evidence_state in ('registered', 'unregistered', 'none'));
alter table public.attendance_punches add column if not exists geo_lat numeric check (geo_lat is null or geo_lat between -90 and 90);
alter table public.attendance_punches add column if not exists geo_lng numeric check (geo_lng is null or geo_lng between -180 and 180);
alter table public.attendance_punches add column if not exists geo_flag text check (geo_flag is null or geo_flag in ('ok', 'outside', 'no_fix', 'unchecked'));

-- ---------- 3. tables ----------
create table if not exists public.att_self_lock (               -- owner's lock: this person / role may NOT self-punch
  scope text not null check (scope in ('person', 'role')),
  ref text not null check (char_length(ref) between 1 and 60),   -- employee id (uuid text) or role code
  locked boolean not null default true,
  note text check (note is null or char_length(note) <= 300),
  set_by uuid, set_at timestamptz not null default now(),
  primary key (scope, ref)
);
create table if not exists public.att_site_geo (                -- optional place coordinates for the soft GPS flag
  location_id int primary key references public.locations(id),
  lat numeric not null check (lat between -90 and 90), lng numeric not null check (lng between -180 and 180),
  set_by uuid, set_at timestamptz not null default now()
);
create table if not exists public.att_evidence_reg (            -- registration FLAG + reference. Never a biometric template. Evidence only.
  id bigserial primary key,
  employee_id uuid not null references public.employees(id),
  kind text not null check (kind in ('webauthn', 'face_photo', 'finger_device')),
  ref text not null check (char_length(ref) between 1 and 300),
  label text check (label is null or char_length(label) <= 80),
  active boolean not null default true,
  registered_by uuid, registered_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_reason text check (void_reason is null or char_length(void_reason) <= 300)
);
create unique index if not exists att_evidence_reg_uq on public.att_evidence_reg (employee_id, kind, ref) where active;
create table if not exists public.att_mark_log54 (              -- append-only audit of every "mark others" call
  id bigserial primary key, client_id uuid unique,
  employee_id uuid not null references public.employees(id), location_id int, day date not null,
  source_tag text not null check (source_tag in ('device', 'finger', 'face', 'manual')),
  status text not null, first_in timestamptz, last_out timestamptz, rest_minutes int, ot_minutes int,
  reason text not null, note text, prev jsonb, approved boolean not null default false,
  marked_by uuid, marked_staff text, marked_at timestamptz not null default now()
);
create or replace function public._att_log_ro54() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists att_mark_log54_ro on public.att_mark_log54;
create trigger att_mark_log54_ro before update or delete on public.att_mark_log54 for each row execute function public._att_log_ro54();

drop trigger if exists audit_att_self_lock on public.att_self_lock;
create trigger audit_att_self_lock after insert or update on public.att_self_lock for each row execute function public.log_change('scope,ref');
drop trigger if exists audit_att_site_geo on public.att_site_geo;
create trigger audit_att_site_geo after insert or update on public.att_site_geo for each row execute function public.log_change('location_id');
drop trigger if exists audit_att_evidence_reg on public.att_evidence_reg;
create trigger audit_att_evidence_reg after insert or update on public.att_evidence_reg for each row execute function public.log_change('id');

alter table public.att_self_lock enable row level security;
alter table public.att_site_geo enable row level security;
alter table public.att_evidence_reg enable row level security;
alter table public.att_mark_log54 enable row level security;
revoke all on public.att_self_lock, public.att_site_geo, public.att_evidence_reg, public.att_mark_log54 from public, anon, authenticated;
revoke all on sequence public.att_evidence_reg_id_seq, public.att_mark_log54_id_seq from public, anon, authenticated;
grant select on public.att_self_lock, public.att_site_geo, public.att_evidence_reg, public.att_mark_log54 to authenticated;
drop policy if exists att_self_lock_read on public.att_self_lock;
create policy att_self_lock_read on public.att_self_lock for select to authenticated using (public.is_owner());
drop policy if exists att_site_geo_read on public.att_site_geo;
create policy att_site_geo_read on public.att_site_geo for select to authenticated using (public.is_active());
drop policy if exists att_evidence_reg_read on public.att_evidence_reg;
create policy att_evidence_reg_read on public.att_evidence_reg for select to authenticated using (public._att_view(employee_id));
drop policy if exists att_mark_log54_read on public.att_mark_log54;
create policy att_mark_log54_read on public.att_mark_log54 for select to authenticated using (public.is_owner()
  or (location_id is not null and public.can_loc(location_id) and (public.has_grant('attendance_mark_others', location_id) or public.has_grant('attendance_manage', location_id))));

-- ---------- 4. rules and grant ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('att_geo_check_on', 'people', 'switch', 'false', null, null, null, null, 'স্ব-পাঞ্চে জিপিএস দূরত্বের নরম পতাকা', 'Self punch এ GPS দূরত্বের soft flag', 'Soft GPS flag on self punches',
  'চালু থাকলে অফিস/শোরুমের স্থানাঙ্ক থেকে দূরে পাঞ্চ হলে পতাকা পড়বে; পাঞ্চ বাতিল হবে না। জিপিএস সহজে ভুল/নকল হয়।', 'When ON, a punch far from the place coordinates is flagged, never refused. GPS can be wrong or faked.', 190),
 ('att_geo_radius_m', 'people', 'number', '300', 'm', null, 20, 20000, 'জিপিএস সীমা (মিটার)', 'GPS radius (meter)', 'GPS radius (metres)', null, null, 191),
 ('entry_equation_flag_on', 'entries', 'switch', 'false', null, null, null, null, 'জমা দেওয়ার সময় সার্ভারে হিসাব মিলিয়ে লাল ব্যতিক্রম', 'Submit এ server হিসাব মিলিয়ে red exception', 'Server re-check of 10-2 / 02-2 totals at submit (red exception)',
  'চালু থাকলে ফোনের হিসাব আর সার্ভারের পুনঃহিসাব না মিললে একটি লাল ব্যতিক্রম পড়বে; জমা আটকায় না।', 'When ON, a submitted 10-2 / 02-2 whose stored flags differ from the server re-work gets one red exception; the submit is not blocked.', 320)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'people', v.s, v.bn, v.mx, v.en, 'window', null
from (values
 ('attendance_mark_others', 76, 'অন্যের দৈনিক হাজিরা, বিরতি ও বন্ধের সময় হাতে লেখা (সোর্স ট্যাগসহ)', 'অন্যের daily attendance, rest ও closing time হাতে লেখা (source tag সহ)', 'Mark other people''s daily attendance, rest and closing time by hand (with a source tag)')
) as v(c, s, bn, mx, en)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

-- ---------- 5. helpers ----------
create or replace function public._att_geo_m54(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric) returns numeric
language sql immutable as $$
  select (2 * 6371000 * asin(least(1, sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))))::numeric;
$$;

-- may this login punch itself right now? (shared by status + punch)
create or replace function public._att_self_state54(p_emp public.employees) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.rule_on('attendance_on') then return 'attendance_off'; end if;
  if not public.rule_on('app_punch_on') then return 'app_punch_off'; end if;
  if exists (select 1 from public.att_self_lock where scope = 'person' and ref = p_emp.id::text and locked) then return 'self_punch_locked'; end if;
  if exists (select 1 from public.att_self_lock l where l.scope = 'role' and l.locked
              and (l.ref = p_emp.primary_role_code or l.ref in (select ur.role_code from public.user_roles ur where ur.user_id = p_emp.profile_id))) then return 'self_punch_locked'; end if;
  if not public.path_allowed('attendance', coalesce(p_emp.primary_location_id, 0), 'a') then return 'path_locked'; end if;
  return 'ok';
end $$;

-- ---------- 6. SELF PUNCH (a) + EVIDENCE flags (b) ----------
create or replace function public.attendance_self_punch(p_dir text default 'unknown', p_lat numeric default null, p_lng numeric default null, p_acc numeric default null,
                                                         p_ev_kind text default null, p_ev_ref text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_id bigint; st text; dir text := case when p_dir in ('in', 'out') then p_dir else 'unknown' end; g public.att_site_geo; gf text := 'unchecked'; dist numeric;
        evs text := 'none'; evk text := null; evr text := null; rad numeric := coalesce(public.rule_num('att_geo_radius_m'), 300);
begin
  perform public._att_gate();
  if not public.rule_on('app_punch_on') then raise exception 'app_punch_off'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then raise exception 'no_employee_record'; end if;
  st := public._att_self_state54(e);
  if st = 'self_punch_locked' then raise exception 'self_punch_locked: the owner has locked self punch for you or your role'; end if;
  if st = 'path_locked' then raise exception 'path_locked: attendance path A is locked here by the owner'; end if;
  if (p_lat is null) <> (p_lng is null) or abs(coalesce(p_lat, 0)) > 90 or abs(coalesce(p_lng, 0)) > 180 or abs(coalesce(p_acc, 0)) > 1e7 then raise exception 'bad_geo'; end if;
  if p_ev_kind is not null and p_ev_kind not in ('webauthn', 'face_photo') then raise exception 'bad_evidence'; end if;
  if p_ev_kind is not null and (nullif(btrim(p_ev_ref), '') is null or char_length(p_ev_ref) > 300) then raise exception 'bad_evidence'; end if;
  if exists (select 1 from public.attendance_punches where employee_id = e.id and source = 'app' and punched_at > now() - interval '1 minute' and not void) then raise exception 'too_soon'; end if;
  if p_ev_kind is not null then
    evk := p_ev_kind; evr := btrim(p_ev_ref);
    evs := case when exists (select 1 from public.att_evidence_reg r where r.employee_id = e.id and r.kind = p_ev_kind and r.ref = evr and r.active) then 'registered' else 'unregistered' end;
  end if;
  if public.rule_on('att_geo_check_on') then
    select * into g from public.att_site_geo where location_id = e.primary_location_id;
    if p_lat is null then gf := 'no_fix';
    elsif not found then gf := 'unchecked';
    else dist := public._att_geo_m54(p_lat, p_lng, g.lat, g.lng); gf := case when dist > rad then 'outside' else 'ok' end; end if;
  end if;
  insert into public.attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source, created_by, evidence_kind, evidence_ref, evidence_state, geo_lat, geo_lng, geo_flag, raw)
    values (e.id, null, e.primary_location_id, 'app:' || e.id::text, date_trunc('second', now()), dir, 'app', auth.uid(), evk, evr, evs, p_lat, p_lng, gf,
            case when p_acc is null then null else jsonb_build_object('geo_accuracy_m', p_acc) end) returning id into v_id;
  perform public._att_store(e.id, public._dhaka_today());
  if (now() at time zone 'Asia/Dhaka')::time < time '06:00' then perform public._att_store(e.id, public._dhaka_today() - 1); end if;
  return jsonb_build_object('id', v_id, 'at', now(), 'direction', dir, 'evidence_state', evs, 'geo_flag', gf, 'geo_distance_m', case when dist is null then null else round(dist) end,
    'note', 'evidence_only_not_identity_proof');
end $$;

-- bos54: the old one-argument entry point keeps its name, errors and 1-minute rule; it now goes through the same locks.
create or replace function public.attendance_app_punch(p_dir text default 'unknown') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public.attendance_self_punch(p_dir);   -- bos54
end $$;

-- what the logged-in person may do now (for the screen)
create or replace function public.att_my_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; st text; ev jsonb; last_p jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then return jsonb_build_object('employee', false, 'can_punch', false, 'state', 'no_employee_record'); end if;
  st := public._att_self_state54(e);
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'label', r.label, 'registered_at', r.registered_at) order by r.id), '[]') into ev
    from public.att_evidence_reg r where r.employee_id = e.id and r.active;
  select to_jsonb(x) into last_p from (select punched_at, direction, evidence_state, geo_flag from public.attendance_punches
                                        where employee_id = e.id and source = 'app' and not void order by punched_at desc limit 1) x;
  return jsonb_build_object('employee', true, 'employee_id', e.id, 'name_bn', e.full_name_bn, 'name_en', e.full_name_en, 'can_punch', st = 'ok', 'state', st, 'evidence', ev, 'last_punch', last_p,
    'geo_check_on', public.rule_on('att_geo_check_on'));
end $$;

-- owner: lock / unlock self punch for one person or one role
create or replace function public.att_self_lock_set(p_scope text, p_ref text, p_locked boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if p_scope not in ('person', 'role') then raise exception 'bad_scope'; end if;
  if nullif(btrim(p_ref), '') is null or char_length(p_ref) > 60 then raise exception 'bad_ref'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if p_scope = 'person' and not exists (select 1 from public.employees where id::text = btrim(p_ref)) then raise exception 'not_found'; end if;
  if p_scope = 'role' and not exists (select 1 from public.roles where code = btrim(p_ref)) and not exists (select 1 from public.staff_roles where code = btrim(p_ref)) then raise exception 'not_found'; end if;
  insert into public.att_self_lock (scope, ref, locked, note, set_by, set_at) values (p_scope, btrim(p_ref), coalesce(p_locked, true), nullif(btrim(p_note), ''), auth.uid(), now())
    on conflict (scope, ref) do update set locked = excluded.locked, note = excluded.note, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('scope', p_scope, 'ref', btrim(p_ref), 'locked', coalesce(p_locked, true));
end $$;

create or replace function public.att_site_geo_set(p_loc int, p_lat numeric, p_lng numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() or not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'not_found'; end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'bad_geo'; end if;
  insert into public.att_site_geo (location_id, lat, lng, set_by, set_at) values (p_loc, p_lat, p_lng, auth.uid(), now())
    on conflict (location_id) do update set lat = excluded.lat, lng = excluded.lng, set_by = excluded.set_by, set_at = now();
  return jsonb_build_object('location_id', p_loc, 'lat', p_lat, 'lng', p_lng);
end $$;

-- owner / attendance manager: people at a place with their lock + evidence status
create or replace function public.att_staff_overview(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows_ jsonb; roles_ jsonb;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.id, 'employee_no', x.employee_no, 'name_bn', x.full_name_bn, 'name_en', x.full_name_en, 'role', x.primary_role_code,
      'has_login', x.profile_id is not null,
      'person_locked', exists (select 1 from public.att_self_lock l where l.scope = 'person' and l.ref = x.id::text and l.locked) and public.is_owner(),
      'evidence', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'label', r.label)) from public.att_evidence_reg r where r.employee_id = x.id and r.active), '[]'::jsonb))
      order by x.employee_no nulls last, x.full_name_bn), '[]') into rows_
    from public.employees x where x.primary_location_id = p_loc and x.status in ('active', 'on_leave');
  select coalesce(jsonb_agg(jsonb_build_object('role', l.ref, 'locked', l.locked)), '[]') into roles_ from public.att_self_lock l where l.scope = 'role' and public.is_owner();
  return jsonb_build_object('location_id', p_loc, 'rows', rows_, 'role_locks', roles_, 'self_punch_master', public.rule_on('app_punch_on'),
    'limits', 'evidence_only: registration is a flag + reference, not proof of identity; fingerprint only through the external device bridge; GPS is a soft flag');
end $$;

-- evidence registration: the person himself (passkey / face photo) or owner / attendance manager (any kind incl. finger_device)
create or replace function public.att_evidence_register(p_emp uuid, p_kind text, p_ref text, p_label text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; own boolean; v bigint;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if p_kind is null or p_kind not in ('webauthn', 'face_photo', 'finger_device') then raise exception 'bad_kind'; end if;
  own := e.profile_id is not null and e.profile_id = auth.uid();
  if not (public._emp_ok(p_emp, array['attendance_manage']) or (own and p_kind in ('webauthn', 'face_photo'))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_ref), '') is null or char_length(p_ref) > 300 then raise exception 'bad_ref'; end if;
  if char_length(coalesce(p_label, '')) > 80 then raise exception 'too_long: label'; end if;
  if (select count(*) from public.att_evidence_reg where employee_id = p_emp and active) >= 10 then raise exception 'too_many'; end if;
  insert into public.att_evidence_reg (employee_id, kind, ref, label, registered_by) values (p_emp, p_kind, btrim(p_ref), nullif(btrim(p_label), ''), auth.uid())
    on conflict (employee_id, kind, ref) where active do nothing returning id into v;
  if v is null then select id into v from public.att_evidence_reg where employee_id = p_emp and kind = p_kind and ref = btrim(p_ref) and active; return jsonb_build_object('id', v, 'repeat', true); end if;
  return jsonb_build_object('id', v, 'kind', p_kind, 'note', 'evidence_only_not_identity_proof');
end $$;

create or replace function public.att_evidence_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.att_evidence_reg; e public.employees;
begin
  perform public._att_gate();
  select * into r from public.att_evidence_reg where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  select * into e from public.employees where id = r.employee_id;
  if not (public._emp_ok(r.employee_id, array['attendance_manage']) or (e.profile_id is not null and e.profile_id = auth.uid() and r.kind in ('webauthn', 'face_photo'))) then raise exception 'not allowed'; end if;
  if nullif(btrim(p_reason), '') is null or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if not r.active then return jsonb_build_object('id', p_id, 'repeat', true); end if;
  update public.att_evidence_reg set active = false, void_by = auth.uid(), void_at = now(), void_reason = btrim(p_reason) where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

-- ---------- 7. MARK OTHERS (c) ----------
-- rest / source columns follow the row: anything that is not this function resets them (a plain attendance_mark, a recompute)
create or replace function public._att_days_guard54() returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(current_setting('bos.mark54', true), '') <> '1' then
    new.rest_minutes := null;
    new.mark_source := case when new.source = 'manual' then 'manual' end;
  end if;
  return new;
end $$;
drop trigger if exists attendance_days_guard54 on public.attendance_days;
create trigger attendance_days_guard54 before insert or update on public.attendance_days for each row execute function public._att_days_guard54();

create or replace function public.attendance_mark_others(p_emp uuid, p_day date, p_status text, p_in text, p_out text, p_rest_min int, p_source text, p_reason text,
                                                         p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; v_today date := public._dhaka_today(); t1 time := public._hhmm(p_in); t2 time := public._hhmm(p_out); ti timestamptz; tout timestamptz;
        worked int := 0; late int := 0; early int := 0; ot int := 0; ss timestamptz; se timestamptz; v_kind text := 'normal'; hol public.holidays; v_appr boolean; rest int; prev jsonb; old public.attendance_days;
        lg public.att_mark_log54; sid text;
begin
  perform public._att_gate();
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into lg from public.att_mark_log54 where client_id = p_client;
    if found then
      if lg.marked_by is distinct from auth.uid() then raise exception 'client_id_in_use'; end if;
      return jsonb_build_object('employee_id', lg.employee_id, 'day', lg.day, 'status', lg.status, 'source_tag', lg.source_tag, 'duplicate', true);
    end if;
  end if;
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not (public.is_owner() or (e.primary_location_id is not null and public.can_loc(e.primary_location_id) and public.has_grant('attendance_mark_others', e.primary_location_id))) then raise exception 'not allowed'; end if;
  if e.profile_id is not null and e.profile_id = auth.uid() and not public.is_owner() then raise exception 'cannot_mark_self'; end if;
  perform public.path_guard('attendance', coalesce(e.primary_location_id, 0), 'a');
  if p_day is null or p_day > v_today or p_day < v_today - 62 then raise exception 'bad_date'; end if;
  if e.joining_date is not null and p_day < e.joining_date then raise exception 'bad_date'; end if;
  if p_status not in ('present', 'late', 'half_day', 'absent', 'off', 'holiday', 'unpaid') then raise exception 'bad_status'; end if;
  if p_source is null or p_source not in ('device', 'finger', 'face', 'manual') then raise exception 'bad_source'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if p_rest_min is not null and (p_rest_min < 0 or p_rest_min > 720) then raise exception 'bad_rest'; end if;
  if (p_in is not null and btrim(p_in) <> '' and t1 is null) or (p_out is not null and btrim(p_out) <> '' and t2 is null) then raise exception 'bad_time'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  if p_status = 'absent' then t1 := null; t2 := null; end if;
  s := public._att_shift_for(e.id, e.primary_location_id, p_day);
  hol := public._att_holiday(e.primary_location_id, p_day);
  if hol.id is not null then v_kind := 'holiday'; elsif public._att_is_off(e.id, p_day) then v_kind := 'off'; end if;
  if t1 is not null then ti := (p_day + t1) at time zone 'Asia/Dhaka'; end if;
  if t2 is not null then tout := (p_day + t2 + case when t1 is not null and t2 <= t1 then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka'; end if;
  rest := case when p_status = 'absent' then null else coalesce(p_rest_min, s.break_min, 0) end;
  if ti is not null and tout is not null then worked := greatest(0, floor(extract(epoch from (tout - ti)) / 60)::int - coalesce(rest, 0)); end if;
  if s.id is not null and ti is not null and v_kind = 'normal' then
    ss := (p_day + s.start_time) at time zone 'Asia/Dhaka';
    se := (p_day + s.end_time + case when s.crosses_midnight or s.end_time <= s.start_time then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka';
    if ti > ss + make_interval(mins => s.grace_late_min) then late := floor(extract(epoch from (ti - ss)) / 60)::int; end if;
    if tout is not null and tout < se - make_interval(mins => s.grace_early_min) then early := floor(extract(epoch from (se - tout)) / 60)::int; end if;
    if tout is not null and tout > se then ot := least(1440, floor(extract(epoch from (tout - se)) / 60)::int); end if;
  end if;
  if p_status in ('absent', 'off', 'holiday', 'unpaid') then late := 0; early := 0; end if;
  if p_status = 'late' and late = 0 then late := 1; end if;
  v_appr := public.is_owner() and public.rule_on('owner_self_approve');
  select * into old from public.attendance_days where employee_id = p_emp and day = p_day;
  prev := case when found then to_jsonb(old) end;
  perform set_config('bos.mark54', '1', true);
  insert into public.attendance_days as a (employee_id, day, status, day_kind, first_in, last_out, worked_minutes, late_minutes, early_leave_minutes, ot_minutes, ot_approved, punch_count, single_punch,
      shift_id, location_id, leave_type, paid_day, source, marked_by, marked_at, approved_by, approved_at, override_reason, note, computed_at, rest_minutes, mark_source)
    values (p_emp, p_day, p_status, v_kind, ti, tout, worked, late, early, ot, v_appr, 0, false, s.id, e.primary_location_id, null,
      case when p_status = 'holiday' then coalesce(hol.paid, true) when p_status = 'unpaid' then false end, 'manual', auth.uid(), now(),
      case when v_appr then auth.uid() end, case when v_appr then now() end, btrim(p_reason), nullif(btrim(p_note), ''), now(), rest, p_source)
  on conflict (employee_id, day) do update set status = excluded.status, day_kind = excluded.day_kind, first_in = excluded.first_in, last_out = excluded.last_out,
      worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes, early_leave_minutes = excluded.early_leave_minutes, ot_minutes = excluded.ot_minutes,
      ot_approved = excluded.ot_approved, punch_count = a.punch_count, shift_id = excluded.shift_id, location_id = excluded.location_id, leave_type = null, paid_day = excluded.paid_day,
      source = 'manual', marked_by = excluded.marked_by, marked_at = excluded.marked_at, approved_by = excluded.approved_by, approved_at = excluded.approved_at,
      override_reason = excluded.override_reason, note = excluded.note, computed_at = now(), rest_minutes = excluded.rest_minutes, mark_source = excluded.mark_source;
  perform set_config('bos.mark54', '', true);
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.att_mark_log54 (client_id, employee_id, location_id, day, source_tag, status, first_in, last_out, rest_minutes, ot_minutes, reason, note, prev, approved, marked_by, marked_staff)
    values (p_client, p_emp, e.primary_location_id, p_day, p_source, p_status, ti, tout, rest, ot, btrim(p_reason), nullif(btrim(p_note), ''), prev, v_appr, auth.uid(), sid);
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'status', p_status, 'source', 'manual', 'source_tag', p_source, 'approved', v_appr, 'late_minutes', late,
    'ot_minutes', ot, 'rest_minutes', rest, 'worked_minutes', worked, 'note', 'source_tag_is_the_markers_declaration_not_proof');
end $$;

-- the board for a person who holds the new grant (attendance_board needs attendance_manage / employee_view)
create or replace function public.att_others_board(p_loc int, p_day date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_day, public._dhaka_today()); rows_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or (p_loc is not null and public.can_loc(p_loc) and public.has_grant('attendance_mark_others', p_loc))) then raise exception 'not allowed'; end if;
  if d > public._dhaka_today() or d < date '2020-01-01' then raise exception 'bad_date'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', x.id, 'employee_no', x.employee_no, 'name_bn', x.full_name_bn, 'name_en', x.full_name_en,
      'is_me', x.profile_id is not null and x.profile_id = auth.uid(),
      'status', j ->> 'status', 'first_in', j ->> 'first_in', 'last_out', j ->> 'last_out', 'worked_minutes', (j ->> 'worked_minutes')::int, 'rest_minutes', a.rest_minutes,
      'ot_minutes', (j ->> 'ot_minutes')::int, 'source', coalesce(j ->> 'source', 'auto'), 'mark_source', a.mark_source,
      'pending', (j ->> 'source') = 'manual' and (j ->> 'approved_by') is null, 'stored', a.employee_id is not null) order by x.employee_no nulls last, x.full_name_bn), '[]')
    into rows_
    from public.employees x
    left join public.attendance_days a on a.employee_id = x.id and a.day = d
    cross join lateral (select coalesce(to_jsonb(a.*), public._att_derive(x.id, d)) as j) q
   where x.primary_location_id = p_loc and (x.status in ('active', 'on_leave') or (x.status in ('resigned', 'terminated', 'retired') and x.status_date >= d))
     and (x.joining_date is null or x.joining_date <= d);
  return jsonb_build_object('day', d, 'location_id', p_loc, 'rows', rows_);
end $$;

-- ---------- 8. TWO PATHS COUNTED ONCE: guard, link, report ----------
create or replace function public._entries_att_guard54() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.form_code = '02-1' and coalesce(current_setting('bos.shadow_create', true), '') <> '1' then perform public.path_guard('attendance', new.location_id, 'b'); end if;
  return new;
end $$;
drop trigger if exists entries_att_guard54 on public.entries;
create trigger entries_att_guard54 before insert on public.entries for each row execute function public._entries_att_guard54();

-- does path A hold records for this place + month?
create or replace function public._att_month_has_a54(p_loc int, p_month date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.attendance_days d where d.location_id = p_loc and d.day >= p_month and d.day < (p_month + interval '1 month')::date)
      or exists (select 1 from public.attendance_punches p where p.location_id = p_loc and not p.void and p.punched_at >= (p_month::timestamp at time zone 'Asia/Dhaka')
                  and p.punched_at < ((p_month + interval '1 month')::timestamp at time zone 'Asia/Dhaka'));
$$;

create or replace function public._att_form_month54(p_data jsonb, p_date date) returns date
language sql immutable as $$
  select coalesce(case when p_data->>'month' ~ '^(1[0-2]|[1-9])$' and p_data->>'year' ~ '^20[0-9]{2}$' then make_date((p_data->>'year')::int, (p_data->>'month')::int, 1) end, date_trunc('month', p_date)::date);
$$;

-- link one submitted / approved 02-1 as a shadow when path A is the record for its month. Returns 'linked' | 'already' | 'form_is_primary' | 'path_a_empty' | 'skip'
create or replace function public._att_form_link54(p_entry uuid) returns text
language plpgsql security definer set search_path = public as $$
declare e public.entries; m date; k text;
begin
  select * into e from public.entries where id = p_entry;
  if not found or e.form_code <> '02-1' or e.status not in ('submitted', 'approved') then return 'skip'; end if;
  if public.is_shadow('entries', e.id::text) then return 'already'; end if;
  if public.path_primary('attendance', e.location_id) <> 'a' then return 'form_is_primary'; end if;
  m := public._att_form_month54(e.data, e.entry_date);
  if not public._att_month_has_a54(e.location_id, m) then return 'path_a_empty'; end if;
  k := e.location_id::text || ':' || to_char(m, 'YYYY-MM');
  if exists (select 1 from public.shadow_links x where x.domain = 'attendance' and x.primary_type = 'attendance_month' and x.primary_id = k and x.shadow_type = 'entries' and x.state <> 'void') then return 'already'; end if;
  perform public.shadow_link_add('attendance', e.location_id, 'attendance_month', k, 'entries', e.id::text, 'bos54 02-1 shadow of staff attendance');
  return 'linked';
end $$;

create or replace function public._entries_att_link54() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public._att_form_link54(new.id);
  return null;
end $$;
drop trigger if exists entries_att_link54 on public.entries;
create trigger entries_att_link54 after update of status on public.entries for each row
  when (new.form_code = '02-1' and new.status in ('submitted', 'approved') and old.status is distinct from new.status) execute function public._entries_att_link54();

-- the manager's "link now" for a month whose punches arrived after the form
create or replace function public.attendance_form_link_run(p_loc int, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; m date := date_trunc('month', p_month)::date; res jsonb := '{}'::jsonb; x text;
begin
  perform public._att_gate();
  if not (public.is_owner() or (public.can_loc(p_loc) and public.has_grant('attendance_manage', p_loc))) then raise exception 'not allowed'; end if;
  for r in select e.id from public.entries e where e.form_code = '02-1' and e.location_id = p_loc and e.status in ('submitted', 'approved') and public._att_form_month54(e.data, e.entry_date) = m order by e.serial loop
    x := public._att_form_link54(r.id);
    res := res || jsonb_build_object(x, coalesce((res ->> x)::int, 0) + 1);
  end loop;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'result', res);
end $$;

-- read-only: per person, what path A says vs what the 02-1 register says, and which one is counted
create or replace function public.attendance_count_once(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; m2 date; cfg jsonb; rows_ jsonb; forms_ jsonb; mism int;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  if p_month is null or m > public._dhaka_today() or m < date '2020-01-01' then raise exception 'bad_date'; end if;
  m2 := (m + interval '1 month')::date;
  cfg := public.path_cfg('attendance', p_loc);
  with emp as (select x.id, x.employee_no, x.full_name_bn, x.full_name_en from public.employees x where x.primary_location_id = p_loc and x.status in ('active', 'on_leave', 'resigned', 'terminated', 'retired')),
  dv as (select a.employee_id,
                count(*) filter (where a.status in ('present', 'late')) + 0.5 * count(*) filter (where a.status = 'half_day') as present,
                count(*) filter (where a.status = 'late') as late, count(*) filter (where a.status = 'absent') as absent, round(sum(a.ot_minutes) / 60.0, 2) as ot_hours
           from public.attendance_days a where a.day >= m and a.day < m2 group by a.employee_id),
  fm as (select e.id as entry_id, r as row_ from public.entries e
           cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
          where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.location_id = p_loc and public._att_form_month54(e.data, e.entry_date) = m
            and btrim(coalesce(r ->> 'name', '')) <> ''),
  fx as (select emp.id as employee_id,
                sum(coalesce(public._db_num(fm.row_ -> 'present'), 0)) as present, sum(coalesce(public._db_num(fm.row_ -> 'late'), 0)) as late,
                sum(coalesce(public._db_num(fm.row_ -> 'absent'), 0)) as absent, sum(coalesce(public._db_num(fm.row_ -> 'ot_hours'), 0)) as ot_hours, count(*) as lines
           from emp join fm on lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.full_name_bn)) or (nullif(btrim(emp.full_name_en), '') is not null and lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.full_name_en)))
                                or (nullif(btrim(emp.employee_no), '') is not null and lower(btrim(fm.row_ ->> 'name')) = lower(btrim(emp.employee_no)))
          group by emp.id),
  j as (select emp.id, emp.employee_no, emp.full_name_bn, emp.full_name_en, dv.present as d_present, dv.late as d_late, dv.absent as d_absent, dv.ot_hours as d_ot,
               fx.present as f_present, fx.late as f_late, fx.absent as f_absent, fx.ot_hours as f_ot, fx.lines as f_lines,
               (dv.employee_id is not null and fx.employee_id is not null and (dv.present <> fx.present or dv.late <> fx.late or dv.absent <> fx.absent or abs(coalesce(dv.ot_hours, 0) - fx.ot_hours) > 0.5)) as mismatch
          from emp left join dv on dv.employee_id = emp.id left join fx on fx.employee_id = emp.id where dv.employee_id is not null or fx.employee_id is not null)
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', j.id, 'employee_no', j.employee_no, 'name_bn', j.full_name_bn, 'name_en', j.full_name_en,
           'device', case when j.d_present is null and j.d_absent is null then null else jsonb_build_object('present', j.d_present, 'late', j.d_late, 'absent', j.d_absent, 'ot_hours', j.d_ot) end,
           'form', case when j.f_lines is null then null else jsonb_build_object('present', j.f_present, 'late', j.f_late, 'absent', j.f_absent, 'ot_hours', j.f_ot) end,
           'mismatch', j.mismatch) order by j.employee_no nulls last, j.full_name_bn), '[]'), count(*) filter (where j.mismatch)
    into rows_, mism from j;
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'status', e.status, 'is_shadow', public.is_shadow('entries', e.id::text)) order by e.serial), '[]') into forms_
    from public.entries e where e.form_code = '02-1' and e.location_id = p_loc and e.status in ('submitted', 'approved') and public._att_form_month54(e.data, e.entry_date) = m;
  return jsonb_build_object('location_id', p_loc, 'month', m, 'primary', cfg ->> 'primary', 'a_open', cfg -> 'a_open', 'b_open', cfg -> 'b_open',
    'counted', case when cfg ->> 'primary' = 'b' then 'form_02_1' else 'attendance_record' end,
    'path_a_has_month', public._att_month_has_a54(p_loc, m), 'forms', forms_, 'rows', rows_, 'mismatches', mism,
    'limits', 'People are matched by name / employee no. written on the register; a difference is a prompt to look, not a verdict.');
end $$;

-- ---------- 9. EQUATION RECOMPUTE (gap #20, read-only) ----------
create or replace function public._eq_limit54(p_loc int, p_key text, p_date date) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  begin v := public.get_limit(p_loc, p_key, p_date); exception when others then return null; end;
  return public._db_num(v);
end $$;

create or replace function public._eq_truthy54(j jsonb) returns boolean language sql immutable as $$
  select coalesce(j = 'true'::jsonb or j = '"true"'::jsonb or j = '"yes"'::jsonb or j = '"1"'::jsonb or j = '1'::jsonb, false);
$$;

-- the engine: no permission check (callers do it); returns {form, supported, recomputed, mismatches, observations, ok}
create or replace function public._eq_check54(e public.entries) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb := coalesce(e.data, '{}'::jsonb); lines jsonb; r jsonb; rc jsonb;
        total numeric := 0; amt numeric; norec numeric := 0; maxa numeric := 0; lim numeric; imp numeric; cashn numeric; rcpt numeric; diff numeric;
        exp_ jsonb := '{}'::jsonb;      -- expected flags: code -> amount (null amount = flag without amount)
        mism jsonb := '[]'::jsonb; obs jsonb := '[]'::jsonb; rec jsonb := '{}'::jsonb; k text; c text; st jsonb;
        neg int := 0; noreason int := 0; unsigned boolean := false; t_due numeric := 0; t_ot numeric := 0; t_other numeric := 0; t_adv numeric := 0; t_od numeric := 0; g numeric; n numeric; any_ boolean; t_rc numeric := 0;
        codes text[];
begin
  if e.form_code = '10-2' then
    codes := array['imprest_mismatch', 'no_receipt', 'over_limit'];
    lines := case when jsonb_typeof(d -> 'lines') = 'array' then d -> 'lines' else '[]'::jsonb end;
    lim := public._eq_limit54(e.location_id, 'expense_max', e.entry_date);
    imp := public._eq_limit54(e.location_id, 'imprest', e.entry_date);
    for r in select * from jsonb_array_elements(lines) loop
      amt := coalesce(public._db_num(r -> 'amount'), 0);
      total := total + amt; maxa := greatest(maxa, amt);
      if r ->> 'receipt' = 'no' and amt > 0 then norec := norec + amt; end if;
    end loop;
    cashn := public._db_num(d -> 'cash_now'); rcpt := coalesce(public._db_num(d -> 'receipts_total'), 0);
    if lim is not null and maxa > lim then exp_ := exp_ || jsonb_build_object('over_limit', maxa); end if;
    if norec > 0 then exp_ := exp_ || jsonb_build_object('no_receipt', norec); end if;
    if imp is not null and cashn is not null then
      diff := coalesce(cashn, 0) + rcpt - imp;
      if diff <> 0 then exp_ := exp_ || jsonb_build_object('imprest_mismatch', diff); end if;
    end if;
    rec := jsonb_build_object('total', total, 'cash_plus_receipts', coalesce(cashn, 0) + rcpt, 'imprest', imp, 'expense_max', lim, 'imprest_diff', diff, 'no_receipt_amount', norec);
  elsif e.form_code = '02-2' then
    codes := array['net_negative', 'other_no_reason', 'paid_unsigned'];
    lines := case when jsonb_typeof(d -> 'pay') = 'array' then d -> 'pay' else '[]'::jsonb end;
    for r in select * from jsonb_array_elements(lines) loop
      any_ := exists (select 1 from jsonb_each_text(case when jsonb_typeof(r) = 'object' then r else '{}'::jsonb end) kv where btrim(kv.value) <> '');
      g := coalesce(public._db_num(r -> 'due'), 0) + coalesce(public._db_num(r -> 'overtime'), 0) + coalesce(public._db_num(r -> 'other'), 0);
      n := g - coalesce(public._db_num(r -> 'adv_ded'), 0) - coalesce(public._db_num(r -> 'other_ded'), 0);
      t_due := t_due + coalesce(public._db_num(r -> 'due'), 0); t_ot := t_ot + coalesce(public._db_num(r -> 'overtime'), 0); t_other := t_other + coalesce(public._db_num(r -> 'other'), 0);
      t_adv := t_adv + coalesce(public._db_num(r -> 'adv_ded'), 0); t_od := t_od + coalesce(public._db_num(r -> 'other_ded'), 0);
      if any_ then
        if n < 0 then neg := neg + 1; end if;
        if (coalesce(public._db_num(r -> 'other'), 0) > 0 or coalesce(public._db_num(r -> 'other_ded'), 0) > 0) and nullif(btrim(coalesce(r ->> 'remark', '')), '') is null then noreason := noreason + 1; end if;
      end if;
    end loop;
    for r in select * from jsonb_array_elements(case when jsonb_typeof(d -> 'receipts') = 'array' then d -> 'receipts' else '[]'::jsonb end) loop
      t_rc := t_rc + coalesce(public._db_num(r -> 'net'), 0);
      if coalesce(public._db_num(r -> 'net'), 0) > 0 and not public._eq_truthy54(r -> 'signed') then unsigned := true; end if;
    end loop;
    if neg > 0 then exp_ := exp_ || jsonb_build_object('net_negative', neg); end if;
    if noreason > 0 then exp_ := exp_ || jsonb_build_object('other_no_reason', noreason); end if;
    if unsigned then exp_ := exp_ || jsonb_build_object('paid_unsigned', null); end if;
    rec := jsonb_build_object('t_due', t_due, 't_ot', t_ot, 't_other', t_other, 't_gross', t_due + t_ot + t_other, 't_adv', t_adv, 't_other_ded', t_od,
                              't_net', t_due + t_ot + t_other - t_adv - t_od, 't_receipts', t_rc, 'negative_net_people', neg, 'other_without_reason', noreason);
    if abs(t_rc - (t_due + t_ot + t_other - t_adv - t_od)) > 0.004 and t_rc > 0 then
      obs := obs || jsonb_build_array(jsonb_build_object('code', 'receipts_vs_net', 'receipts_total', t_rc, 'sheet_net', t_due + t_ot + t_other - t_adv - t_od,
                                                          'note', 'information only: the receipt acknowledgement does not add up to the sheet net'));
    end if;
  else
    return jsonb_build_object('form', e.form_code, 'supported', false, 'ok', true, 'mismatches', '[]'::jsonb, 'why', 'only 10-2 and 02-2 are re-worked; 14-1 is not');
  end if;
  -- compare to the flags the phone stored
  foreach c in array codes loop
    select x into st from jsonb_array_elements(coalesce(e.flags, '[]'::jsonb)) x where x ->> 'code' = c limit 1;
    if exp_ ? c and st is null then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'flag_missing', 'recomputed', exp_ -> c, 'stored', null));
    elsif not (exp_ ? c) and st is not null and st ->> 'level' = 'red' then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'flag_extra', 'recomputed', null, 'stored', st -> 'amount'));
    elsif exp_ ? c and st is not null and jsonb_typeof(exp_ -> c) = 'number' and public._db_num(st -> 'amount') is distinct from (exp_ ->> c)::numeric then
      mism := mism || jsonb_build_array(jsonb_build_object('code', c, 'kind', 'amount_differs', 'recomputed', exp_ -> c, 'stored', st -> 'amount'));
    end if;
  end loop;
  return jsonb_build_object('form', e.form_code, 'supported', true, 'recomputed', rec, 'expected_flags', exp_, 'mismatches', mism, 'observations', obs, 'ok', jsonb_array_length(mism) = 0,
    'note', 'limits (expense_max, imprest) are read as they are today; a limit changed after the sheet was saved can show as a difference');
end $$;

create or replace function public.entry_equation_check(p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.entries;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into e from public.entries where id = p_entry;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (public.can_loc(e.location_id) and (public.can_do(e.form_code, 'view') or public.can_do(e.form_code, 'enter') or e.created_by = auth.uid()))) then raise exception 'not allowed'; end if;
  return public._eq_check54(e) || jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'status', e.status);
end $$;

-- optional (switch entry_equation_flag_on, default OFF): at the end of the submitting transaction, one red exception when the stored flags differ from the re-work.
-- A deferred constraint trigger, so submit_entry (which clears and rewrites open exceptions) is not touched and cannot erase it.
create or replace function public._entries_eq_flag54() returns trigger
language plpgsql security definer set search_path = public as $$
declare e public.entries; res jsonb;
begin
  if not public.rule_on('entry_equation_flag_on') then return null; end if;
  select * into e from public.entries where id = new.id;
  if not found or e.status not in ('submitted', 'approved') then return null; end if;
  res := public._eq_check54(e);
  if coalesce((res ->> 'ok')::boolean, true) then return null; end if;
  if not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = 'equation_mismatch' and x.status = 'open') then
    insert into public.exceptions (entry_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (e.id, e.form_code, e.location_id, e.entry_date, 'equation_mismatch', 'red', null,
              jsonb_build_object('bn', 'ফোনের হিসাব আর সার্ভারের পুনঃহিসাব মেলেনি — ' || (select string_agg(m ->> 'code', ', ') from jsonb_array_elements(res -> 'mismatches') m),
                                 'en', 'Phone totals and the server re-work differ: ' || (select string_agg(m ->> 'code', ', ') from jsonb_array_elements(res -> 'mismatches') m)));
  end if;
  return null;
end $$;
drop trigger if exists entries_eq_flag54 on public.entries;
create constraint trigger entries_eq_flag54 after update of status on public.entries deferrable initially deferred for each row
  when (new.form_code in ('10-2', '02-2') and new.status = 'submitted' and old.status is distinct from new.status) execute function public._entries_eq_flag54();

-- ---------- 10. rights ----------
revoke all on function public._att_geo_m54(numeric, numeric, numeric, numeric), public._att_self_state54(public.employees), public._att_log_ro54(), public._att_days_guard54(),
  public._entries_att_guard54(), public._att_month_has_a54(int, date), public._att_form_month54(jsonb, date), public._att_form_link54(uuid), public._entries_att_link54(),
  public._eq_limit54(int, text, date), public._eq_truthy54(jsonb), public._eq_check54(public.entries), public._entries_eq_flag54() from public, anon, authenticated;
revoke all on function public.attendance_self_punch(text, numeric, numeric, numeric, text, text), public.att_my_status(), public.att_self_lock_set(text, text, boolean, text),
  public.att_site_geo_set(int, numeric, numeric), public.att_staff_overview(int), public.att_evidence_register(uuid, text, text, text), public.att_evidence_void(bigint, text),
  public.attendance_mark_others(uuid, date, text, text, text, int, text, text, text, uuid), public.att_others_board(int, date), public.attendance_form_link_run(int, date),
  public.attendance_count_once(int, date), public.entry_equation_check(uuid) from public, anon;
grant execute on function public.attendance_self_punch(text, numeric, numeric, numeric, text, text), public.att_my_status(), public.att_self_lock_set(text, text, boolean, text),
  public.att_site_geo_set(int, numeric, numeric), public.att_staff_overview(int), public.att_evidence_register(uuid, text, text, text), public.att_evidence_void(bigint, text),
  public.attendance_mark_others(uuid, date, text, text, text, int, text, text, text, uuid), public.att_others_board(int, date), public.attendance_form_link_run(int, date),
  public.attendance_count_once(int, date), public.entry_equation_check(uuid) to authenticated;
