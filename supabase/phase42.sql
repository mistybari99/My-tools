-- ============================================================
-- PHASE 42 (module B2): ATTENDANCE, LEAVE, AUTOMATIC PAYROLL and FINGERPRINT DEVICE integration.
-- Additive and idempotent (paste twice = no error). Needs phase8..phase28 and phase41 (employees, employee_pay, employee_pay_components,
-- leave_types, employee_leave_entitlements, _emp_ok / _emp_any / _loc_ok / _emp_pay_on / _pay_calc / _dhaka_today). No other new phase.
-- Nothing is deleted: punches are append-only (only a void flag / a late employee mapping may be written), payroll documents are voided, never removed.
--
-- WORKING STAFF = employees.status in ('active', 'on_leave'). A person who left this month (resigned / terminated / retired, status_date = last day
--   worked) is still paid up to status_date (final settlement). draft / discarded are not people yet.
--
-- TABLES
--   shifts(id, name_bn, name_en, location_id null = every place, start_time, end_time, grace_late_min, grace_early_min, break_min, crosses_midnight,
--     min_hours_full_day, min_hours_half_day, is_default, active)       -- one default per place (or a company default with location_id null)
--   employee_shift_assignments(id, employee_id, shift_id, weekday_mask (bit 0 = Sunday .. bit 6 = Saturday, 127 = every day), off_mask null = use rule
--     att_weekly_off, from_date, to_date null, active)
--   holidays(id, day, location_id null = everywhere, name_bn, name_en, paid, active)
--   attendance_devices(id, name, location_id, vendor zkteco|hikvision|suprema|other, serial, token_hash (NOT readable), active, last_seen, rl_minute, rl_count)
--   attendance_import_batches(id uuid, location_id, device_id, file_name, rows_total, rows_new, rows_dup, rows_bad, rows_unmapped, date_from, date_to,
--     status active|void, created_by/at, void_by/at/reason)
--   attendance_punches(id, employee_id null = unmapped, device_id null, location_id, device_user_id, punched_at, direction in|out|unknown,
--     source device|file|manual|app, raw, import_batch, void)   unique (device_id, device_user_id, punched_at) nulls not distinct among non-void rows
--   attendance_days(employee_id, day) pk: status present|absent|late|half_day|leave|off|holiday|unpaid, day_kind normal|off|holiday, first_in, last_out,
--     worked_minutes, late_minutes, early_leave_minutes, ot_minutes, ot_approved, punch_count, single_punch, shift_id, location_id, leave_type, paid_day,
--     source auto|manual, marked_by/at, approved_by/at, override_reason, note, computed_at
--   leave_requests(id, client_id, employee_id, leave_type, from_date, to_date, days, reason, status pending|approved|rejected|cancelled, requested_by/at,
--     decided_by/at, decision_note)
--   employee_advances(id, client_id, employee_id, location_id, adv_date, amount, instalment, recover_from, mode none|cash|bank|mobile, note, status active|void)
--   employee_advance_recoveries(id, advance_id, run_id, line_id, amount, status active|void)       -- written when a payroll run is approved
--   payroll_bonus_events(id, month, name, location_id null, active)   -- "the Eid bonus is paid with the salary of this month" (matches employee_pay.bonus_rules[].name)
--   payroll_runs(id, client_id, month (first day), location_id null = whole company (owner only), status draft|approved|paid|void, created_by/at,
--     approved_by/at, paid_at, void_by/at/reason, notes)
--   payroll_lines(id, run_id, month, employee_id, location_id, ... every figure of the calculation ..., gross, deductions, net, calc_detail, payment_status
--     unpaid|partly|paid, paid_amount, active)
--   payroll_payments(id, client_batch, run_id, line_id, employee_id, location_id, pay_date, mode cash|bank|mobile, amount, ref, note, status done|void)
--
-- PRIVACY: attendance (no money) = owner, the person himself (profile link), or attendance_manage / employee_view / employee_manage at the person's place.
--   Payroll, advances and pay figures = owner, salary_view or payroll_manage at the place. Payroll approve = owner only. Devices = owner registers.
-- FINGERPRINT: attendance_punch_push(token, rows) is the ONLY function anon may execute; it inserts punches for the token's device and nothing else.
-- RULES (module people, Switchboard): attendance_on, app_punch_on (OFF), att_weekly_off ("fri"), att_double_punch_min (5), att_ot_min_minutes (30),
--   att_ot_cap_hours (2), att_late_mode (count), att_lates_per_day (3), pay_weekly_off_paid, pay_holiday_paid, ot_mult_holiday (2), att_bonus_amount (0 = off),
--   pay_round_net (nearest), payroll_on, att_push_per_min (30).
-- GRANTS: attendance_manage (new; default for management / showroom_manager / factory_incharge / hr), payroll_manage (new), salary_view (existing).
-- ============================================================

-- ---------- rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('attendance_on', 'people', 'switch', 'true', null, null, null, null, 'হাজিরা ও ছুটি চালু', 'Attendance ও leave চালু', 'Attendance and leave are on', 'বন্ধ করলে হাজিরা / ছুটি লেখা বন্ধ; দেখা চলবে।', 'Off = no attendance / leave writes; viewing still works.', 170),
 ('app_punch_on', 'people', 'switch', 'false', null, null, null, null, 'অ্যাপ থেকে হাজিরা (চেক ইন / আউট)', 'App থেকে check in / out', 'Staff may check in / out from the app', 'লগইন আছে এমন কর্মী নিজের ফোনে চেক ইন করতে পারবে।', 'Staff with a login can check in from their phone.', 171),
 ('att_weekly_off', 'people', 'text', '"fri"', null, null, null, null, 'সাপ্তাহিক ছুটির দিন (fri / fri,sat)', 'Weekly off দিন (fri / fri,sat)', 'Weekly off days (fri / fri,sat)', 'ইংরেজি তিন অক্ষর, কমা দিয়ে: sun mon tue wed thu fri sat', 'Three letters, comma separated: sun mon tue wed thu fri sat', 172),
 ('att_double_punch_min', 'people', 'number', '5', 'min', null, 1, 120, 'এত মিনিটের মধ্যে দুবার আঙুল দিলে একবার ধরা হবে', 'এত মিনিটের মধ্যে double punch = একবার', 'Punches closer than this are one punch', null, null, 173),
 ('att_ot_min_minutes', 'people', 'number', '30', 'min', null, 0, 240, 'এর কম ওভারটাইম গোনা হবে না (মিনিট)', 'এর কম overtime গোনা হবে না (min)', 'Overtime below this is ignored (minutes)', null, null, 174),
 ('att_ot_cap_hours', 'people', 'number', '2', 'hours', null, 0, 24, 'দিনে এর বেশি ওভারটাইম হলে অনুমোদন লাগবে (ঘণ্টা)', 'দিনে এর বেশি OT হলে approval লাগবে (ঘণ্টা)', 'Overtime above this per day needs approval (hours)', 'অনুমোদন না হলে বাড়তি অংশ বেতনে যোগ হবে না।', 'Without approval the extra part is not paid.', 175),
 ('att_late_mode', 'people', 'choice', '"count"', null, '["count","per_minute","none"]', null, null, 'দেরির কর্তন: count = কয়েক দিন দেরি = ১ দিনের বেতন, per_minute = মিনিট হিসাবে, none = নেই', 'Late কর্তন: count / per_minute / none', 'Late cut: count = N lates = 1 day, per_minute = by the minute, none', null, null, 176),
 ('att_lates_per_day', 'people', 'number', '3', 'lates', null, 1, 31, 'কতবার দেরি = ১ দিনের বেতন কাটা', 'কতবার late = ১ দিনের বেতন কাটা', 'This many late arrivals = one day cut', null, null, 177),
 ('pay_weekly_off_paid', 'people', 'switch', 'true', null, null, null, null, 'সাপ্তাহিক ছুটির দিনের বেতন আছে', 'Weekly off-এর বেতন আছে', 'Weekly off days are paid', null, null, 178),
 ('pay_holiday_paid', 'people', 'switch', 'true', null, null, null, null, 'সরকারি / উৎসব ছুটির বেতন আছে (ছুটির নিজস্ব সেটিং মেনে)', 'Holiday-র বেতন আছে', 'Holidays are paid (as each holiday says)', null, null, 179),
 ('ot_mult_holiday', 'people', 'number', '2', 'x', null, 1, 5, 'ছুটির দিনে ওভারটাইমের গুণ', 'Holiday / off-day OT গুণ', 'Overtime multiple on a holiday / weekly off', 'সাধারণ দিনের গুণ কর্মচারীর বেতন কাঠামোতে (যেমন ১.৫)।', 'The normal-day multiple is in the person''s pay structure (e.g. 1.5).', 180),
 ('att_bonus_amount', 'people', 'number', '0', 'BDT', null, 0, 1000000, 'হাজিরা বোনাস (মাসে কোনো অনুপস্থিতি / দেরি না হলে); ০ = বন্ধ', 'Attendance bonus; 0 = বন্ধ', 'Attendance bonus (no absence / late in the month); 0 = off', null, null, 181),
 ('pay_round_net', 'people', 'choice', '"nearest"', null, '["nearest","none"]', null, null, 'হাতে পাওয়া বেতন পূর্ণ টাকায় (nearest)', 'Net বেতন পূর্ণ টাকায়', 'Round the net pay to the nearest taka', null, null, 182),
 ('payroll_on', 'people', 'switch', 'true', null, null, null, null, 'বেতন শিট (payroll) চালু', 'Payroll চালু', 'Payroll is on', null, null, 183),
 ('att_push_per_min', 'people', 'number', '30', 'calls', null, 1, 600, 'একটি মেশিন মিনিটে কতবার পাঠাতে পারবে', 'Device মিনিটে কতবার push করতে পারবে', 'Device pushes allowed per minute', null, null, 184)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'people', v.s, v.bn, v.mx, v.en, 'window', null
from (values
 ('attendance_manage', 74, 'হাজিরা হাতে লেখা / সংশোধন, ছুটি অনুমোদন, মেশিনের ফাইল আনা', 'Attendance লেখা / সংশোধন, leave approve, device file import', 'Mark / correct attendance, approve leave, import device files'),
 ('payroll_manage', 75, 'বেতন শিট তৈরি, সমন্বয় ও বেতন দেওয়া', 'Payroll তৈরি, adjust ও pay', 'Prepare payroll, adjust lines and pay salaries')
) as v(c, s, bn, mx, en)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rule_grants (grant_code, role_code)
select 'attendance_manage', r.code from public.roles r where r.code in ('management', 'showroom_manager', 'factory_incharge', 'hr')
on conflict do nothing;

-- ---------- shifts, roster, holidays ----------
create table if not exists public.shifts (
  id serial primary key, name_bn text not null check (char_length(btrim(name_bn)) between 1 and 60), name_en text,
  location_id int references public.locations(id), start_time time not null, end_time time not null,
  grace_late_min int not null default 10 check (grace_late_min between 0 and 240), grace_early_min int not null default 10 check (grace_early_min between 0 and 240),
  break_min int not null default 60 check (break_min between 0 and 600), crosses_midnight boolean not null default false,
  min_hours_full_day numeric not null default 7 check (min_hours_full_day between 0 and 24), min_hours_half_day numeric not null default 4 check (min_hours_half_day between 0 and 24),
  is_default boolean not null default false, active boolean not null default true, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists shifts_one_default on public.shifts (coalesce(location_id, 0)) where is_default and active;
insert into public.shifts (name_bn, name_en, location_id, start_time, end_time, grace_late_min, grace_early_min, break_min, crosses_midnight, min_hours_full_day, min_hours_half_day, is_default)
select 'সাধারণ শিফট', 'General shift', null, '09:00', '18:00', 10, 10, 60, false, 7, 4, true
where not exists (select 1 from public.shifts);

create table if not exists public.employee_shift_assignments (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), shift_id int not null references public.shifts(id),
  weekday_mask int not null default 127 check (weekday_mask between 1 and 127), off_mask int check (off_mask is null or off_mask between 0 and 127),
  from_date date not null, to_date date, active boolean not null default true, created_by uuid, created_at timestamptz not null default now(),
  check (to_date is null or to_date >= from_date)
);
create index if not exists esa_emp on public.employee_shift_assignments (employee_id, from_date desc);

create table if not exists public.holidays (
  id serial primary key, day date not null, location_id int references public.locations(id), name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80),
  name_en text, paid boolean not null default true, active boolean not null default true, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists holidays_one on public.holidays (day, coalesce(location_id, 0)) where active;

-- ---------- devices, punches, days ----------
create table if not exists public.attendance_devices (
  id serial primary key, name text not null check (char_length(btrim(name)) between 1 and 60), location_id int not null references public.locations(id),
  vendor text not null default 'zkteco' check (vendor in ('zkteco', 'hikvision', 'suprema', 'other')), serial text,
  token_hash text not null unique, active boolean not null default true, last_seen timestamptz, rl_minute timestamptz, rl_count int not null default 0,
  pushed_rows bigint not null default 0, created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.attendance_import_batches (
  id uuid primary key default gen_random_uuid(), client_id uuid unique, location_id int not null references public.locations(id), device_id int references public.attendance_devices(id),
  file_name text, rows_total int not null default 0, rows_new int not null default 0, rows_dup int not null default 0, rows_bad int not null default 0, rows_unmapped int not null default 0,
  date_from timestamptz, date_to timestamptz, status text not null default 'active' check (status in ('active', 'void')),
  created_by uuid, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_reason text
);
create table if not exists public.attendance_punches (
  id bigserial primary key, employee_id uuid references public.employees(id), device_id int references public.attendance_devices(id), location_id int references public.locations(id),
  device_user_id text not null check (char_length(device_user_id) between 1 and 60), punched_at timestamptz not null,
  direction text not null default 'unknown' check (direction in ('in', 'out', 'unknown')), source text not null check (source in ('device', 'file', 'manual', 'app')),
  raw jsonb, import_batch uuid references public.attendance_import_batches(id), void boolean not null default false, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists attendance_punches_uq on public.attendance_punches (device_id, device_user_id, punched_at) nulls not distinct where not void;
create index if not exists attendance_punches_emp on public.attendance_punches (employee_id, punched_at) where not void;
create index if not exists attendance_punches_unmapped on public.attendance_punches (location_id, device_user_id) where employee_id is null and not void;
create index if not exists attendance_punches_batch on public.attendance_punches (import_batch) where import_batch is not null;

create table if not exists public.attendance_days (
  employee_id uuid not null references public.employees(id), day date not null,
  status text not null check (status in ('present', 'absent', 'late', 'half_day', 'leave', 'off', 'holiday', 'unpaid')),
  day_kind text not null default 'normal' check (day_kind in ('normal', 'off', 'holiday')),
  first_in timestamptz, last_out timestamptz, worked_minutes int not null default 0, late_minutes int not null default 0, early_leave_minutes int not null default 0,
  ot_minutes int not null default 0 check (ot_minutes between 0 and 1440), ot_approved boolean not null default false, punch_count int not null default 0, single_punch boolean not null default false,
  shift_id int references public.shifts(id), location_id int references public.locations(id), leave_type text references public.leave_types(code), paid_day boolean,
  source text not null default 'auto' check (source in ('auto', 'manual')), marked_by uuid, marked_at timestamptz, approved_by uuid, approved_at timestamptz,
  override_reason text, note text, computed_at timestamptz not null default now(),
  primary key (employee_id, day)
);
create index if not exists attendance_days_day on public.attendance_days (day, location_id);

-- ---------- leave ----------
create table if not exists public.leave_requests (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), leave_type text not null references public.leave_types(code),
  from_date date not null, to_date date not null, days numeric not null check (days >= 0 and days <= 366), reason text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid, requested_at timestamptz not null default now(), decided_by uuid, decided_at timestamptz, decision_note text,
  check (to_date >= from_date)
);
create index if not exists leave_requests_emp on public.leave_requests (employee_id, from_date);

-- ---------- advances, bonus events, payroll ----------
create table if not exists public.employee_advances (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), location_id int references public.locations(id),
  adv_date date not null, amount numeric not null check (amount > 0 and amount <= 1000000000000), instalment numeric check (instalment is null or (instalment > 0 and instalment <= 1000000000000)),
  recover_from date not null, mode text not null default 'none' check (mode in ('none', 'cash', 'bank', 'mobile')), note text,
  status text not null default 'active' check (status in ('active', 'void')), created_by uuid, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_reason text
);
create index if not exists employee_advances_emp on public.employee_advances (employee_id);

create table if not exists public.payroll_bonus_events (
  id serial primary key, month date not null check (extract(day from month) = 1), name text not null check (char_length(btrim(name)) between 1 and 60),
  location_id int references public.locations(id), active boolean not null default true, created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists payroll_bonus_events_one on public.payroll_bonus_events (month, lower(name), coalesce(location_id, 0)) where active;

create table if not exists public.payroll_runs (
  id bigserial primary key, client_id uuid unique, month date not null check (extract(day from month) = 1), location_id int references public.locations(id),
  status text not null default 'draft' check (status in ('draft', 'approved', 'paid', 'void')), notes text,
  created_by uuid, created_at timestamptz not null default now(), approved_by uuid, approved_at timestamptz, paid_at timestamptz, void_by uuid, void_at timestamptz, void_reason text
);
create unique index if not exists payroll_runs_one on public.payroll_runs (month, coalesce(location_id, 0)) where status <> 'void';

create table if not exists public.payroll_lines (
  id bigserial primary key, run_id bigint not null references public.payroll_runs(id), month date not null, employee_id uuid not null references public.employees(id),
  location_id int references public.locations(id), employee_no text, name text, pay_id bigint, pay_basis text,
  basic numeric not null default 0, basic_amount numeric not null default 0, allowances jsonb not null default '[]', allowance_total numeric not null default 0,
  structure_deductions jsonb not null default '[]', structure_deduction_total numeric not null default 0,
  days_in_month int not null default 0, employed_days int not null default 0, paid_days numeric not null default 0, absent_days numeric not null default 0, half_days int not null default 0,
  unpaid_leave_days numeric not null default 0, paid_leave_days numeric not null default 0, off_days int not null default 0, holiday_days int not null default 0,
  late_count int not null default 0, late_minutes int not null default 0, late_deduction numeric not null default 0, absent_deduction numeric not null default 0,
  unpaid_deduction numeric not null default 0, not_employed_deduction numeric not null default 0, ot_minutes int not null default 0, ot_amount numeric not null default 0,
  bonus jsonb not null default '[]', advance_recovery numeric not null default 0, advances jsonb not null default '[]', other_deductions jsonb not null default '[]',
  adjustments jsonb not null default '[]', gross numeric not null default 0, deductions numeric not null default 0, round_adj numeric not null default 0, net numeric not null default 0,
  warnings jsonb not null default '[]', calc_detail jsonb not null default '{}', payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'partly', 'paid')),
  paid_amount numeric not null default 0, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists payroll_lines_one on public.payroll_lines (employee_id, month) where active;
create index if not exists payroll_lines_run on public.payroll_lines (run_id);

create table if not exists public.employee_advance_recoveries (
  id bigserial primary key, advance_id bigint not null references public.employee_advances(id), run_id bigint not null references public.payroll_runs(id),
  line_id bigint not null references public.payroll_lines(id), amount numeric not null check (amount > 0), status text not null default 'active' check (status in ('active', 'void')),
  created_at timestamptz not null default now()
);
create index if not exists employee_advance_recoveries_adv on public.employee_advance_recoveries (advance_id) where status = 'active';

create table if not exists public.payroll_payments (
  id bigserial primary key, client_batch uuid, run_id bigint not null references public.payroll_runs(id), line_id bigint not null references public.payroll_lines(id),
  employee_id uuid not null references public.employees(id), location_id int references public.locations(id), pay_date date not null,
  mode text not null check (mode in ('cash', 'bank', 'mobile')), amount numeric not null check (amount > 0 and amount <= 1000000000000), ref text, note text,
  status text not null default 'done' check (status in ('done', 'void')), created_by uuid, created_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_reason text
);
create index if not exists payroll_payments_line on public.payroll_payments (line_id) where status = 'done';
create index if not exists payroll_payments_day on public.payroll_payments (location_id, pay_date) where status = 'done';

-- ---------- guards: append-only records, immutable money documents ----------
create or replace function public._punch_guard42() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - array['employee_id', 'void']) is distinct from (to_jsonb(old) - array['employee_id', 'void'])
     or (old.employee_id is not null and new.employee_id is distinct from old.employee_id) or (old.void and not new.void) then
    raise exception 'append_only: a punch cannot be changed (only mapped once or voided)';
  end if;
  return new;
end $$;
drop trigger if exists attendance_punches_guard on public.attendance_punches;
create trigger attendance_punches_guard before update or delete on public.attendance_punches for each row execute function public._punch_guard42();

create or replace function public._status_guard42() returns trigger language plpgsql set search_path = public as $$
declare keep text[] := tg_argv;
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - keep) is distinct from (to_jsonb(old) - keep) then raise exception 'append_only: % cannot be changed', tg_table_name; end if;
  if (to_jsonb(old) ->> 'status') in ('void', 'cancelled', 'rejected') and (to_jsonb(new) ->> 'status') is distinct from (to_jsonb(old) ->> 'status') then raise exception 'append_only: % is closed', tg_table_name; end if;
  return new;
end $$;
drop trigger if exists payroll_payments_guard on public.payroll_payments;
create trigger payroll_payments_guard before update or delete on public.payroll_payments for each row execute function public._status_guard42('status', 'void_by', 'void_at', 'void_reason');
drop trigger if exists employee_advance_recoveries_guard on public.employee_advance_recoveries;
create trigger employee_advance_recoveries_guard before update or delete on public.employee_advance_recoveries for each row execute function public._status_guard42('status');
drop trigger if exists employee_advances_guard on public.employee_advances;
create trigger employee_advances_guard before update or delete on public.employee_advances for each row execute function public._status_guard42('status', 'void_by', 'void_at', 'void_reason');
drop trigger if exists attendance_import_batches_guard on public.attendance_import_batches;
create trigger attendance_import_batches_guard before update or delete on public.attendance_import_batches for each row execute function public._status_guard42('status', 'void_by', 'void_at', 'void_reason',
  'rows_total', 'rows_new', 'rows_dup', 'rows_bad', 'rows_unmapped', 'date_from', 'date_to');
drop trigger if exists leave_requests_guard on public.leave_requests;
create trigger leave_requests_guard before update or delete on public.leave_requests for each row execute function public._status_guard42('status', 'decided_by', 'decided_at', 'decision_note');

create or replace function public._run_guard42() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if new.month is distinct from old.month or new.location_id is distinct from old.location_id or new.created_by is distinct from old.created_by then raise exception 'payroll_run_immutable'; end if;
  if old.status = 'void' then raise exception 'payroll_run_void'; end if;
  return new;
end $$;
drop trigger if exists payroll_runs_guard on public.payroll_runs;
create trigger payroll_runs_guard before update or delete on public.payroll_runs for each row execute function public._run_guard42();

-- a line changes freely only while its run is a draft; afterwards only the payment state (and active, when the run is voided)
create or replace function public._line_guard42() returns trigger language plpgsql set search_path = public as $$
declare st text;
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  select status into st from public.payroll_runs where id = old.run_id;
  if new.run_id <> old.run_id or new.employee_id <> old.employee_id or new.month <> old.month then raise exception 'payroll_line_immutable'; end if;
  if st <> 'draft' and (to_jsonb(new) - array['payment_status', 'paid_amount', 'active', 'updated_at']) is distinct from (to_jsonb(old) - array['payment_status', 'paid_amount', 'active', 'updated_at']) then
    raise exception 'payroll_locked: the run is %', st;
  end if;
  return new;
end $$;
drop trigger if exists payroll_lines_guard on public.payroll_lines;
create trigger payroll_lines_guard before update or delete on public.payroll_lines for each row execute function public._line_guard42();

do $$
declare t text;
begin
  foreach t in array array['shifts', 'employee_shift_assignments', 'holidays', 'attendance_devices', 'attendance_days', 'payroll_bonus_events'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;

-- audit (the device counters are not audited: they change on every push)
drop trigger if exists audit_shifts on public.shifts;
create trigger audit_shifts after insert or update on public.shifts for each row execute function public.log_change('id');
drop trigger if exists audit_employee_shift_assignments on public.employee_shift_assignments;
create trigger audit_employee_shift_assignments after insert or update on public.employee_shift_assignments for each row execute function public.log_change('id');
drop trigger if exists audit_holidays on public.holidays;
create trigger audit_holidays after insert or update on public.holidays for each row execute function public.log_change('id');
drop trigger if exists audit_attendance_devices on public.attendance_devices;
create trigger audit_attendance_devices after insert or update of name, location_id, vendor, serial, token_hash, active on public.attendance_devices for each row execute function public.log_change('id');
drop trigger if exists audit_attendance_import_batches on public.attendance_import_batches;
create trigger audit_attendance_import_batches after insert or update on public.attendance_import_batches for each row execute function public.log_change('id');
drop trigger if exists audit_attendance_days on public.attendance_days;
create trigger audit_attendance_days after insert or update on public.attendance_days for each row execute function public.log_change('employee_id,day');
drop trigger if exists audit_leave_requests on public.leave_requests;
create trigger audit_leave_requests after insert or update on public.leave_requests for each row execute function public.log_change('id');
drop trigger if exists audit_employee_advances on public.employee_advances;
create trigger audit_employee_advances after insert or update on public.employee_advances for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_bonus_events on public.payroll_bonus_events;
create trigger audit_payroll_bonus_events after insert or update on public.payroll_bonus_events for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_runs on public.payroll_runs;
create trigger audit_payroll_runs after insert or update on public.payroll_runs for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_lines on public.payroll_lines;
create trigger audit_payroll_lines after insert or update on public.payroll_lines for each row execute function public.log_change('id');
drop trigger if exists audit_payroll_payments on public.payroll_payments;
create trigger audit_payroll_payments after insert or update on public.payroll_payments for each row execute function public.log_change('id');

-- ---------- access helpers ----------
create or replace function public._att_view(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner()
    or exists (select 1 from public.employees e where e.id = p_emp and e.profile_id = auth.uid() and e.profile_id is not null)
    or public._emp_ok(p_emp, array['attendance_manage', 'employee_view', 'employee_manage'], true));
$$;
create or replace function public._att_loc_view(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (p_loc is not null and public.can_loc(p_loc)
    and (public.has_grant('attendance_manage', p_loc) or public.has_grant('employee_view', p_loc) or public.has_grant('employee_manage', p_loc))));
$$;
-- payroll / salary figures at a place: p_manage = payroll_manage needed (else salary_view or payroll_manage). Null place = owner only.
create or replace function public._pr_ok(p_loc int, p_manage boolean default false) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (p_loc is not null and public.can_loc(p_loc)
    and (public.has_grant('payroll_manage', p_loc) or (not p_manage and public.has_grant('salary_view', p_loc)))));
$$;

-- ---------- RLS: reads only; writes go through the functions ----------
do $$
declare t text;
begin
  foreach t in array array['shifts', 'employee_shift_assignments', 'holidays', 'attendance_devices', 'attendance_import_batches', 'attendance_punches', 'attendance_days',
                           'leave_requests', 'employee_advances', 'employee_advance_recoveries', 'payroll_bonus_events', 'payroll_runs', 'payroll_lines', 'payroll_payments'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;
drop policy if exists shifts_read on public.shifts;
create policy shifts_read on public.shifts for select to authenticated using (public.is_active());
drop policy if exists esa_read on public.employee_shift_assignments;
create policy esa_read on public.employee_shift_assignments for select to authenticated using (public._att_view(employee_id));
drop policy if exists holidays_read on public.holidays;
create policy holidays_read on public.holidays for select to authenticated using (public.is_active());
drop policy if exists attendance_devices_read on public.attendance_devices;
create policy attendance_devices_read on public.attendance_devices for select to authenticated using (public.is_owner() or (public.can_loc(location_id) and public.has_grant('attendance_manage', location_id)));
drop policy if exists attendance_import_batches_read on public.attendance_import_batches;
create policy attendance_import_batches_read on public.attendance_import_batches for select to authenticated using (public.is_owner() or (public.can_loc(location_id) and public.has_grant('attendance_manage', location_id)));
drop policy if exists attendance_punches_read on public.attendance_punches;
create policy attendance_punches_read on public.attendance_punches for select to authenticated using (
  case when employee_id is null then public.is_owner() or (public.can_loc(location_id) and public.has_grant('attendance_manage', location_id)) else public._att_view(employee_id) end);
drop policy if exists attendance_days_read on public.attendance_days;
create policy attendance_days_read on public.attendance_days for select to authenticated using (public._att_view(employee_id));
drop policy if exists leave_requests_read on public.leave_requests;
create policy leave_requests_read on public.leave_requests for select to authenticated using (public._att_view(employee_id));
drop policy if exists employee_advances_read on public.employee_advances;
create policy employee_advances_read on public.employee_advances for select to authenticated using (public._emp_ok(employee_id, array['salary_view', 'payroll_manage']));
drop policy if exists employee_advance_recoveries_read on public.employee_advance_recoveries;
create policy employee_advance_recoveries_read on public.employee_advance_recoveries for select to authenticated
  using (exists (select 1 from public.employee_advances a where a.id = advance_id and public._emp_ok(a.employee_id, array['salary_view', 'payroll_manage'])));
drop policy if exists payroll_bonus_events_read on public.payroll_bonus_events;
create policy payroll_bonus_events_read on public.payroll_bonus_events for select to authenticated using (public._emp_any(array['salary_view', 'payroll_manage']));
drop policy if exists payroll_runs_read on public.payroll_runs;
create policy payroll_runs_read on public.payroll_runs for select to authenticated using (public._pr_ok(location_id));
drop policy if exists payroll_lines_read on public.payroll_lines;
create policy payroll_lines_read on public.payroll_lines for select to authenticated using (public._pr_ok(location_id));
drop policy if exists payroll_payments_read on public.payroll_payments;
create policy payroll_payments_read on public.payroll_payments for select to authenticated using (public._pr_ok(location_id));

grant select on public.shifts, public.employee_shift_assignments, public.holidays, public.attendance_import_batches, public.attendance_punches, public.attendance_days,
  public.leave_requests, public.employee_advances, public.employee_advance_recoveries, public.payroll_bonus_events, public.payroll_runs, public.payroll_lines, public.payroll_payments to authenticated;
-- the token hash is never readable
grant select (id, name, location_id, vendor, serial, active, last_seen, pushed_rows, created_by, created_at) on public.attendance_devices to authenticated;

-- ---------- small helpers ----------
create or replace function public._att_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('attendance_on') then raise exception 'attendance_off'; end if;
end $$;
create or replace function public._pr_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('payroll_on') then raise exception 'payroll_off'; end if;
end $$;
-- weekly off mask from the rule: "fri" / "fri,sat" (bit 0 = Sunday)
create or replace function public._att_rule_off_mask() returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(distinct case btrim(lower(x)) when 'sun' then 1 when 'mon' then 2 when 'tue' then 4 when 'wed' then 8 when 'thu' then 16 when 'fri' then 32 when 'sat' then 64 else 0 end), 0)::int
    from unnest(string_to_array(coalesce(public.rule_txt('att_weekly_off'), 'fri'), ',')) x;
$$;
create or replace function public._att_is_off(p_emp uuid, p_day date) returns boolean language sql stable security definer set search_path = public as $$
  select (coalesce((select a.off_mask from public.employee_shift_assignments a where a.employee_id = p_emp and a.active and a.off_mask is not null
                     and a.from_date <= p_day and (a.to_date is null or a.to_date >= p_day) order by a.from_date desc, a.id desc limit 1),
                   public._att_rule_off_mask()) & (1 << extract(dow from p_day)::int)) <> 0;
$$;
create or replace function public._att_holiday(p_loc int, p_day date) returns public.holidays language sql stable security definer set search_path = public as $$
  select * from public.holidays h where h.day = p_day and h.active and (h.location_id is null or h.location_id = p_loc) order by h.location_id nulls last, h.id limit 1;
$$;
-- the shift for a person on a day: assignment (weekday matches) > default of the place > company default
create or replace function public._att_shift_for(p_emp uuid, p_loc int, p_day date) returns public.shifts language plpgsql stable security definer set search_path = public as $$
declare s public.shifts;
begin
  select sh.* into s from public.employee_shift_assignments a join public.shifts sh on sh.id = a.shift_id
   where a.employee_id = p_emp and a.active and a.from_date <= p_day and (a.to_date is null or a.to_date >= p_day) and (a.weekday_mask & (1 << extract(dow from p_day)::int)) <> 0
   order by a.from_date desc, a.id desc limit 1;
  if found then return s; end if;
  select * into s from public.shifts where active and is_default and location_id = p_loc limit 1;
  if found then return s; end if;
  select * into s from public.shifts where active and is_default and location_id is null limit 1;
  return s;
end $$;
-- has an approved payroll locked this person's month?
create or replace function public._att_locked(p_emp uuid, p_day date) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
                  where l.employee_id = p_emp and l.month = date_trunc('month', p_day)::date and l.active and r.status in ('approved', 'paid'));
$$;
-- device time text -> timestamptz (no zone given = Dhaka local time)
create or replace function public._att_ts(p text) returns timestamptz language plpgsql stable as $$
declare v text := btrim(coalesce(p, ''));
begin
  if v !~ '^\d{4}-\d{2}-\d{2}[ T]\d{1,2}:\d{2}(:\d{2}(\.\d+)?)?' then return null; end if;
  if substr(v, 11) ~ '(Z|z|[+-]\d{2}(:?\d{2})?)$' then return v::timestamptz; end if;
  return (v::timestamp) at time zone 'Asia/Dhaka';
exception when others then return null;
end $$;
create or replace function public._att_dir(p text) returns text language sql immutable as $$
  select case lower(btrim(coalesce(p, ''))) when 'in' then 'in' when 'i' then 'in' when 'checkin' then 'in' when 'check_in' then 'in' when '0' then 'in' when '3' then 'in' when '4' then 'in'
    when 'out' then 'out' when 'o' then 'out' when 'checkout' then 'out' when 'check_out' then 'out' when '1' then 'out' when '2' then 'out' when '5' then 'out' else 'unknown' end;
$$;
create or replace function public._hhmm(p text) returns time language plpgsql immutable as $$
begin
  if nullif(btrim(coalesce(p, '')), '') is null then return null; end if;
  if btrim(p) !~ '^\d{1,2}:\d{2}(:\d{2})?$' then raise exception 'bad_time'; end if;
  return btrim(p)::time;
exception when others then raise exception 'bad_time';
end $$;

-- ---------- derive one day (reads only) ----------
create or replace function public._att_derive(p_emp uuid, p_day date) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare e public.employees; s public.shifts; hol public.holidays; lv record; v_kind text := 'normal';
  ws timestamptz; we timestamptz; ss timestamptz; se timestamptz; gap interval := make_interval(mins => coalesce(public.rule_num('att_double_punch_min'), 5)::int);
  p record; prev timestamptz; kept timestamptz[] := '{}'; n int; t_in timestamptz; t_out timestamptz;
  worked int := 0; late int := 0; early int := 0; ot int := 0; st text; v_paid boolean; v_leave text; otmin int := coalesce(public.rule_num('att_ot_min_minutes'), 30)::int;
begin
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then return null; end if;
  if e.joining_date is not null and p_day < e.joining_date then return null; end if;
  if e.status in ('resigned', 'terminated', 'retired') and e.status_date is not null and p_day > e.status_date then return null; end if;
  if p_day > public._dhaka_today() then return null; end if;
  s := public._att_shift_for(e.id, e.primary_location_id, p_day);
  hol := public._att_holiday(e.primary_location_id, p_day);
  if hol.id is not null then v_kind := 'holiday'; elsif public._att_is_off(e.id, p_day) then v_kind := 'off'; end if;
  select r.leave_type, t.paid into lv from public.leave_requests r join public.leave_types t on t.code = r.leave_type
   where r.employee_id = e.id and r.status = 'approved' and p_day between r.from_date and r.to_date order by r.id limit 1;
  if s.id is not null then
    ss := (p_day + s.start_time) at time zone 'Asia/Dhaka';
    se := (p_day + s.end_time + case when s.crosses_midnight or s.end_time <= s.start_time then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka';
    ws := ss - interval '4 hours';
  else
    ws := p_day::timestamp at time zone 'Asia/Dhaka';
  end if;
  we := ws + interval '24 hours';
  -- first punch = in, last = out; a punch closer than N minutes to the previous one is the same punch
  for p in select punched_at from public.attendance_punches where employee_id = e.id and not void and punched_at >= ws and punched_at < we order by punched_at loop
    if prev is null or p.punched_at - prev >= gap then kept := kept || p.punched_at; end if;
    prev := p.punched_at;
  end loop;
  n := coalesce(array_length(kept, 1), 0);
  if n = 0 then
    if lv.leave_type is not null then st := 'leave'; v_paid := lv.paid; v_leave := lv.leave_type;
    elsif v_kind = 'holiday' then st := 'holiday'; v_paid := hol.paid;
    elsif v_kind = 'off' then st := 'off';
    else st := 'absent'; end if;
  else
    t_in := kept[1]; if n > 1 then t_out := kept[n]; end if;
    if t_out is not null then worked := greatest(0, floor(extract(epoch from (t_out - t_in)) / 60)::int - coalesce(s.break_min, 0)); end if;
    if v_kind = 'normal' then
      if s.id is not null then
        if t_in > ss + make_interval(mins => s.grace_late_min) then late := floor(extract(epoch from (t_in - ss)) / 60)::int; end if;
        if t_out is not null and t_out < se - make_interval(mins => s.grace_early_min) then early := floor(extract(epoch from (se - t_out)) / 60)::int; end if;
        if t_out is not null and t_out > se then ot := floor(extract(epoch from (t_out - se)) / 60)::int; end if;
      end if;
    else
      ot := worked;                                   -- every worked minute on a holiday / weekly off is overtime
    end if;
    if ot < otmin then ot := 0; end if;
    if v_kind <> 'normal' then st := 'present';
    elsif t_out is null then st := case when late > 0 then 'late' else 'present' end;
    elsif s.id is not null and worked < s.min_hours_half_day * 60 then st := 'absent'; late := 0; early := 0; ot := 0;
    elsif s.id is not null and worked < s.min_hours_full_day * 60 then st := 'half_day';
    elsif late > 0 then st := 'late';
    else st := 'present'; end if;
  end if;
  return jsonb_build_object('employee_id', e.id, 'day', p_day, 'status', st, 'day_kind', v_kind, 'first_in', t_in, 'last_out', t_out, 'worked_minutes', worked,
    'late_minutes', late, 'early_leave_minutes', early, 'ot_minutes', least(ot, 1440), 'punch_count', n, 'single_punch', (n = 1), 'shift_id', s.id,
    'location_id', e.primary_location_id, 'leave_type', v_leave, 'paid_day', v_paid, 'holiday', hol.name_bn);
end $$;

-- store one derived day; a manual row (approved or waiting) and a locked month are never overwritten
create or replace function public._att_store(p_emp uuid, p_day date) returns text language plpgsql security definer set search_path = public as $$
declare j jsonb;
begin
  if exists (select 1 from public.attendance_days where employee_id = p_emp and day = p_day and source = 'manual') then return 'manual'; end if;
  if public._att_locked(p_emp, p_day) then return 'locked'; end if;
  j := public._att_derive(p_emp, p_day);
  if j is null then return 'none'; end if;
  insert into public.attendance_days as a (employee_id, day, status, day_kind, first_in, last_out, worked_minutes, late_minutes, early_leave_minutes, ot_minutes, punch_count, single_punch,
      shift_id, location_id, leave_type, paid_day, source, computed_at)
    values (p_emp, p_day, j ->> 'status', j ->> 'day_kind', (j ->> 'first_in')::timestamptz, (j ->> 'last_out')::timestamptz, (j ->> 'worked_minutes')::int, (j ->> 'late_minutes')::int,
      (j ->> 'early_leave_minutes')::int, (j ->> 'ot_minutes')::int, (j ->> 'punch_count')::int, (j ->> 'single_punch')::boolean, (j ->> 'shift_id')::int, (j ->> 'location_id')::int,
      j ->> 'leave_type', (j ->> 'paid_day')::boolean, 'auto', now())
  on conflict (employee_id, day) do update set status = excluded.status, day_kind = excluded.day_kind, first_in = excluded.first_in, last_out = excluded.last_out,
      worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes, early_leave_minutes = excluded.early_leave_minutes,
      ot_approved = case when a.ot_minutes = excluded.ot_minutes then a.ot_approved else false end, ot_minutes = excluded.ot_minutes,
      punch_count = excluded.punch_count, single_punch = excluded.single_punch, shift_id = excluded.shift_id, location_id = excluded.location_id, leave_type = excluded.leave_type,
      paid_day = excluded.paid_day, computed_at = now()
    where a.source = 'auto' and (a.status, a.day_kind, a.first_in, a.last_out, a.worked_minutes, a.late_minutes, a.early_leave_minutes, a.ot_minutes, a.punch_count, a.shift_id, a.location_id, a.leave_type, a.paid_day)
      is distinct from (excluded.status, excluded.day_kind, excluded.first_in, excluded.last_out, excluded.worked_minutes, excluded.late_minutes, excluded.early_leave_minutes, excluded.ot_minutes,
                        excluded.punch_count, excluded.shift_id, excluded.location_id, excluded.leave_type, excluded.paid_day);
  return 'saved';
end $$;

-- recompute a date range (max 62 days) for one person or every working person the caller manages
create or replace function public.attendance_recompute(p_from date, p_to date, p_employee uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_today date := public._dhaka_today(); v_to date; e record; d date; r text; n_saved int := 0; n_manual int := 0; n_locked int := 0; n_emp int := 0;
begin
  perform public._att_gate();
  if p_from is null or p_to is null or p_from < date '2020-01-01' or p_to < p_from or p_to - p_from > 61 then raise exception 'bad_range'; end if;
  v_to := least(p_to, v_today);
  if p_employee is not null and not public._emp_ok(p_employee, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if p_employee is null and not public._emp_any(array['attendance_manage']) then raise exception 'not allowed'; end if;
  -- late mapping: punches whose device id now belongs to a person
  update public.attendance_punches p set employee_id = x.id from public.employees x
   where p.employee_id is null and not p.void and x.device_user_id = p.device_user_id and x.status not in ('draft', 'discarded') and (p_employee is null or x.id = p_employee);
  for e in select x.id from public.employees x
            where (p_employee is null or x.id = p_employee)
              and (x.status in ('active', 'on_leave') or (x.status in ('resigned', 'terminated', 'retired') and coalesce(x.status_date, p_from) >= p_from))
              and (p_employee is not null or public._emp_ok(x.id, array['attendance_manage'])) loop
    n_emp := n_emp + 1;
    d := p_from;
    while d <= v_to loop
      r := public._att_store(e.id, d);
      if r = 'saved' then n_saved := n_saved + 1; elsif r = 'manual' then n_manual := n_manual + 1; elsif r = 'locked' then n_locked := n_locked + 1; end if;
      d := d + 1;
    end loop;
  end loop;
  return jsonb_build_object('employees', n_emp, 'days_saved', n_saved, 'manual_kept', n_manual, 'locked', n_locked, 'from', p_from, 'to', v_to);
end $$;

-- ---------- manual mark / approve / OT approve ----------
create or replace function public.attendance_mark(p_emp uuid, p_day date, p_status text, p_in text, p_out text, p_ot_minutes int, p_reason text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; v_today date := public._dhaka_today(); t1 time := public._hhmm(p_in); t2 time := public._hhmm(p_out);
  ti timestamptz; tout timestamptz; worked int := 0; late int := 0; early int := 0; ot int := coalesce(p_ot_minutes, 0); ss timestamptz; se timestamptz; v_kind text := 'normal'; hol public.holidays; v_appr boolean;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if p_day is null or p_day > v_today or p_day < v_today - 62 then raise exception 'bad_date'; end if;
  if e.joining_date is not null and p_day < e.joining_date then raise exception 'bad_date'; end if;
  if p_status not in ('present', 'late', 'half_day', 'absent', 'off', 'holiday', 'unpaid') then raise exception 'bad_status'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if ot < 0 or ot > 1440 then raise exception 'bad_ot'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  s := public._att_shift_for(e.id, e.primary_location_id, p_day);
  hol := public._att_holiday(e.primary_location_id, p_day);
  if hol.id is not null then v_kind := 'holiday'; elsif public._att_is_off(e.id, p_day) then v_kind := 'off'; end if;
  if t1 is not null then ti := (p_day + t1) at time zone 'Asia/Dhaka'; end if;
  if t2 is not null then tout := (p_day + t2 + case when t1 is not null and t2 <= t1 then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka'; end if;
  if ti is not null and tout is not null then worked := greatest(0, floor(extract(epoch from (tout - ti)) / 60)::int - coalesce(s.break_min, 0)); end if;
  if s.id is not null and ti is not null and v_kind = 'normal' then
    ss := (p_day + s.start_time) at time zone 'Asia/Dhaka';
    se := (p_day + s.end_time + case when s.crosses_midnight or s.end_time <= s.start_time then interval '1 day' else interval '0' end) at time zone 'Asia/Dhaka';
    if ti > ss + make_interval(mins => s.grace_late_min) then late := floor(extract(epoch from (ti - ss)) / 60)::int; end if;
    if tout is not null and tout < se - make_interval(mins => s.grace_early_min) then early := floor(extract(epoch from (se - tout)) / 60)::int; end if;
    if p_ot_minutes is null and tout is not null and tout > se then ot := floor(extract(epoch from (tout - se)) / 60)::int; end if;
  end if;
  if p_status in ('absent', 'off', 'holiday', 'unpaid') then late := 0; early := 0; end if;
  if p_status = 'late' and late = 0 then late := 1; end if;
  v_appr := public.is_owner() and public.rule_on('owner_self_approve');
  insert into public.attendance_days as a (employee_id, day, status, day_kind, first_in, last_out, worked_minutes, late_minutes, early_leave_minutes, ot_minutes, ot_approved, punch_count, single_punch,
      shift_id, location_id, leave_type, paid_day, source, marked_by, marked_at, approved_by, approved_at, override_reason, note, computed_at)
    values (p_emp, p_day, p_status, v_kind, ti, tout, worked, late, early, ot, v_appr, 0, false, s.id, e.primary_location_id, null,
      case when p_status = 'holiday' then coalesce(hol.paid, true) when p_status = 'unpaid' then false end, 'manual', auth.uid(), now(),
      case when v_appr then auth.uid() end, case when v_appr then now() end, btrim(p_reason), nullif(btrim(p_note), ''), now())
  on conflict (employee_id, day) do update set status = excluded.status, day_kind = excluded.day_kind, first_in = excluded.first_in, last_out = excluded.last_out,
      worked_minutes = excluded.worked_minutes, late_minutes = excluded.late_minutes, early_leave_minutes = excluded.early_leave_minutes, ot_minutes = excluded.ot_minutes,
      ot_approved = excluded.ot_approved, punch_count = a.punch_count, shift_id = excluded.shift_id, location_id = excluded.location_id, leave_type = null, paid_day = excluded.paid_day,
      source = 'manual', marked_by = excluded.marked_by, marked_at = excluded.marked_at, approved_by = excluded.approved_by, approved_at = excluded.approved_at,
      override_reason = excluded.override_reason, note = excluded.note, computed_at = now();
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'status', p_status, 'source', 'manual', 'approved', v_appr, 'late_minutes', late, 'ot_minutes', ot, 'worked_minutes', worked);
end $$;

-- approve a manual override (a second person; the owner is exempt while owner_self_approve is ON) or reject it (the day goes back to the punches)
create or replace function public.attendance_approve(p_emp uuid, p_day date, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.attendance_days;
begin
  perform public._att_gate();
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  select * into a from public.attendance_days where employee_id = p_emp and day = p_day for update;
  if not found or a.source <> 'manual' then raise exception 'not_found'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  if a.approved_by is not null and coalesce(p_approve, false) then return jsonb_build_object('approved', true, 'repeat', true); end if;
  if a.marked_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'maker_cannot_approve'; end if;
  if coalesce(p_approve, false) then
    update public.attendance_days set approved_by = auth.uid(), approved_at = now(), ot_approved = true, note = coalesce(nullif(btrim(p_note), ''), note) where employee_id = p_emp and day = p_day;
    return jsonb_build_object('approved', true);
  end if;
  update public.attendance_days set source = 'auto', approved_by = null, approved_at = null, marked_by = null, marked_at = null, ot_approved = false,
         override_reason = null, note = left('rejected: ' || coalesce(btrim(p_note), ''), 300) where employee_id = p_emp and day = p_day;
  perform public._att_store(p_emp, p_day);
  return jsonb_build_object('approved', false, 'status', (select status from public.attendance_days where employee_id = p_emp and day = p_day));
end $$;

create or replace function public.attendance_ot_approve(p_emp uuid, p_day date, p_ok boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._att_gate();
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if public._att_locked(p_emp, p_day) then raise exception 'month_locked'; end if;
  update public.attendance_days set ot_approved = coalesce(p_ok, true) where employee_id = p_emp and day = p_day and ot_minutes > 0;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('employee_id', p_emp, 'day', p_day, 'ot_approved', coalesce(p_ok, true));
end $$;

-- ---------- boards ----------
create or replace function public.attendance_board(p_loc int, p_day date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_day, public._dhaka_today()); rows_ jsonb; cnt jsonb;
begin
  if not public._att_loc_view(p_loc) then raise exception 'not allowed'; end if;
  if d > public._dhaka_today() or d < date '2020-01-01' then raise exception 'bad_date'; end if;
  with emp as (
    select x.* from public.employees x
     where x.primary_location_id = p_loc and (x.status in ('active', 'on_leave') or (x.status in ('resigned', 'terminated', 'retired') and x.status_date >= d))
       and (x.joining_date is null or x.joining_date <= d)),
  r as (select emp.id, emp.employee_no, emp.full_name_bn, emp.full_name_en, emp.photo_path, emp.device_user_id,
               coalesce(to_jsonb(a.*), public._att_derive(emp.id, d)) j, a.employee_id is not null stored
          from emp left join public.attendance_days a on a.employee_id = emp.id and a.day = d)
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', r.id, 'employee_no', r.employee_no, 'name_bn', r.full_name_bn, 'name_en', r.full_name_en, 'photo_path', r.photo_path,
           'has_device_id', r.device_user_id is not null, 'status', r.j ->> 'status', 'day_kind', r.j ->> 'day_kind', 'first_in', r.j ->> 'first_in', 'last_out', r.j ->> 'last_out',
           'worked_minutes', (r.j ->> 'worked_minutes')::int, 'late_minutes', (r.j ->> 'late_minutes')::int, 'ot_minutes', (r.j ->> 'ot_minutes')::int, 'ot_approved', coalesce((r.j ->> 'ot_approved')::boolean, false),
           'single_punch', coalesce((r.j ->> 'single_punch')::boolean, false), 'leave_type', r.j ->> 'leave_type', 'source', coalesce(r.j ->> 'source', 'auto'),
           'pending', (r.j ->> 'source') = 'manual' and (r.j ->> 'approved_by') is null, 'marked_by', r.j ->> 'marked_by', 'reason', r.j ->> 'override_reason', 'stored', r.stored)
           order by r.employee_no nulls last, r.full_name_bn), '[]'),
         jsonb_build_object('total', count(*), 'present', count(*) filter (where r.j ->> 'status' in ('present', 'late', 'half_day')), 'late', count(*) filter (where r.j ->> 'status' = 'late'),
           'absent', count(*) filter (where r.j ->> 'status' = 'absent'), 'leave', count(*) filter (where r.j ->> 'status' = 'leave'),
           'off', count(*) filter (where r.j ->> 'status' in ('off', 'holiday')), 'pending', count(*) filter (where (r.j ->> 'source') = 'manual' and (r.j ->> 'approved_by') is null))
    into rows_, cnt from r;
  return jsonb_build_object('day', d, 'location_id', p_loc, 'rows', rows_, 'counts', cnt);
end $$;

create or replace function public.attendance_month(p_emp uuid, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m0 date := date_trunc('month', p_month)::date; m1 date; out_ jsonb;
begin
  if not public._att_view(p_emp) then raise exception 'not allowed'; end if;
  if p_month is null or m0 < date '2020-01-01' or m0 > public._dhaka_today() then raise exception 'bad_date'; end if;
  m1 := (m0 + interval '1 month')::date - 1;
  select coalesce(jsonb_agg(coalesce(to_jsonb(a.*) || jsonb_build_object('stored', true), public._att_derive(p_emp, g.d::date) || jsonb_build_object('stored', false),
                                     jsonb_build_object('day', g.d::date, 'status', null)) order by g.d), '[]')
    into out_ from generate_series(m0, m1, interval '1 day') g(d) left join public.attendance_days a on a.employee_id = p_emp and a.day = g.d::date;
  return jsonb_build_object('employee_id', p_emp, 'month', m0, 'days', out_, 'locked', public._att_locked(p_emp, m0));
end $$;

-- ---------- shifts, roster, holidays: writes ----------
create or replace function public.shift_save(p_id int, p_data jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'); s public.shifts; v_loc int;
begin
  perform public._att_gate();
  if p_id is not null then select * into s from public.shifts where id = p_id for update; if not found then raise exception 'not_found'; end if; end if;
  v_loc := case when d ? 'location_id' then public._e_num(d, 'location_id', 1, 100000)::int else s.location_id end;
  if not (public.is_owner() or (v_loc is not null and public._loc_ok(v_loc, 'attendance_manage') and (p_id is null or s.location_id is not distinct from v_loc))) then raise exception 'not allowed'; end if;
  s.name_bn := coalesce(public._e_txt(d, 'name_bn', 60), s.name_bn); s.name_en := case when d ? 'name_en' then public._e_txt(d, 'name_en', 60) else s.name_en end;
  s.location_id := v_loc;
  s.start_time := coalesce(public._hhmm(d ->> 'start_time'), s.start_time); s.end_time := coalesce(public._hhmm(d ->> 'end_time'), s.end_time);
  s.grace_late_min := coalesce(public._e_num(d, 'grace_late_min', 0, 240)::int, s.grace_late_min, 10); s.grace_early_min := coalesce(public._e_num(d, 'grace_early_min', 0, 240)::int, s.grace_early_min, 10);
  s.break_min := coalesce(public._e_num(d, 'break_min', 0, 600)::int, s.break_min, 60);
  s.crosses_midnight := coalesce((d ->> 'crosses_midnight')::boolean, s.crosses_midnight, false);
  s.min_hours_full_day := coalesce(public._e_num(d, 'min_hours_full_day', 0, 24), s.min_hours_full_day, 7); s.min_hours_half_day := coalesce(public._e_num(d, 'min_hours_half_day', 0, 24), s.min_hours_half_day, 4);
  s.is_default := coalesce((d ->> 'is_default')::boolean, s.is_default, false); s.active := coalesce((d ->> 'active')::boolean, s.active, true);
  if s.name_bn is null then raise exception 'name_required'; end if;
  if s.start_time is null or s.end_time is null then raise exception 'bad_time'; end if;
  if s.min_hours_half_day > s.min_hours_full_day then raise exception 'bad_hours'; end if;
  if s.end_time <= s.start_time then s.crosses_midnight := true; end if;
  if s.is_default and s.active then update public.shifts set is_default = false where is_default and active and coalesce(location_id, 0) = coalesce(s.location_id, 0) and id is distinct from p_id; end if;
  if p_id is null then
    insert into public.shifts (name_bn, name_en, location_id, start_time, end_time, grace_late_min, grace_early_min, break_min, crosses_midnight, min_hours_full_day, min_hours_half_day, is_default, active, created_by)
      values (s.name_bn, s.name_en, s.location_id, s.start_time, s.end_time, s.grace_late_min, s.grace_early_min, s.break_min, s.crosses_midnight, s.min_hours_full_day, s.min_hours_half_day, s.is_default, s.active, auth.uid())
      returning id into s.id;
  else
    update public.shifts set name_bn = s.name_bn, name_en = s.name_en, location_id = s.location_id, start_time = s.start_time, end_time = s.end_time, grace_late_min = s.grace_late_min,
      grace_early_min = s.grace_early_min, break_min = s.break_min, crosses_midnight = s.crosses_midnight, min_hours_full_day = s.min_hours_full_day, min_hours_half_day = s.min_hours_half_day,
      is_default = s.is_default, active = s.active where id = p_id;
  end if;
  return to_jsonb(s);
end $$;

create or replace function public.shift_assign(p_emp uuid, p_shift int, p_from date, p_to date default null, p_weekdays int default 127, p_off_mask int default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public._att_gate();
  if not public._emp_ok(p_emp, array['attendance_manage']) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select id into v_id from public.employee_shift_assignments where client_id = p_client; if found then return jsonb_build_object('id', v_id, 'repeat', true); end if; end if;
  if not exists (select 1 from public.shifts where id = p_shift and active) then raise exception 'bad_shift'; end if;
  if p_from is null or p_from < public._dhaka_today() - 400 or p_from > public._dhaka_today() + 400 or (p_to is not null and p_to < p_from) then raise exception 'bad_date'; end if;
  if p_weekdays is null or p_weekdays not between 1 and 127 or (p_off_mask is not null and p_off_mask not between 0 and 127) then raise exception 'bad_mask'; end if;
  insert into public.employee_shift_assignments (client_id, employee_id, shift_id, weekday_mask, off_mask, from_date, to_date, created_by)
    values (p_client, p_emp, p_shift, p_weekdays, p_off_mask, p_from, p_to, auth.uid()) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;
create or replace function public.shift_assign_end(p_id bigint, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.employee_shift_assignments;
begin
  perform public._att_gate();
  select * into a from public.employee_shift_assignments where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(a.employee_id, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if p_to is null then update public.employee_shift_assignments set active = false where id = p_id;
  elsif p_to < a.from_date then raise exception 'bad_date';
  else update public.employee_shift_assignments set to_date = p_to where id = p_id; end if;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.holiday_save(p_day date, p_loc int, p_name_bn text, p_name_en text default null, p_paid boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int;
begin
  perform public._att_gate();
  if not (public.is_owner() or (p_loc is not null and public._loc_ok(p_loc, 'attendance_manage'))) then raise exception 'not allowed'; end if;
  if p_day is null or p_day < date '2020-01-01' or p_day > public._dhaka_today() + 730 then raise exception 'bad_date'; end if;
  if nullif(btrim(p_name_bn), '') is null or char_length(p_name_bn) > 80 or char_length(coalesce(p_name_en, '')) > 80 then raise exception 'name_required'; end if;
  select id into v_id from public.holidays where day = p_day and coalesce(location_id, 0) = coalesce(p_loc, 0) and active;
  if found then update public.holidays set name_bn = btrim(p_name_bn), name_en = nullif(btrim(p_name_en), ''), paid = coalesce(p_paid, true) where id = v_id;
  else insert into public.holidays (day, location_id, name_bn, name_en, paid, created_by) values (p_day, p_loc, btrim(p_name_bn), nullif(btrim(p_name_en), ''), coalesce(p_paid, true), auth.uid()) returning id into v_id; end if;
  return jsonb_build_object('id', v_id);
end $$;
create or replace function public.holiday_retire(p_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h public.holidays;
begin
  perform public._att_gate();
  select * into h from public.holidays where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (h.location_id is not null and public._loc_ok(h.location_id, 'attendance_manage'))) then raise exception 'not allowed'; end if;
  update public.holidays set active = false where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

-- ---------- leave ----------
create or replace function public._leave_days(p_emp uuid, p_from date, p_to date) returns numeric language sql stable security definer set search_path = public as $$
  select count(*)::numeric from generate_series(p_from, p_to, interval '1 day') g(d)
   where not public._att_is_off(p_emp, g.d::date)
     and (public._att_holiday((select primary_location_id from public.employees where id = p_emp), g.d::date)).id is null;
$$;
create or replace function public._leave_used(p_emp uuid, p_type text, p_year int, p_status text, p_exclude bigint default null) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(days), 0) from public.leave_requests where employee_id = p_emp and leave_type = p_type and status = p_status and extract(year from from_date) = p_year and id is distinct from p_exclude;
$$;
create or replace function public.leave_balances(p_emp uuid, p_year int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare y int := coalesce(p_year, extract(year from public._dhaka_today())::int);
begin
  if not public._att_view(p_emp) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('leave_type', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'paid', t.paid,
      'entitled', coalesce(en.days_per_year, 0), 'taken', public._leave_used(p_emp, t.code, y, 'approved'), 'pending', public._leave_used(p_emp, t.code, y, 'pending'),
      'remaining', case when t.paid then coalesce(en.days_per_year, 0) - public._leave_used(p_emp, t.code, y, 'approved') end) order by t.sort)
    from public.leave_types t left join public.employee_leave_entitlements en on en.employee_id = p_emp and en.leave_type = t.code where t.active), '[]');
end $$;

create or replace function public.leave_request_save(p_emp uuid, p_type text, p_from date, p_to date, p_reason text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; t public.leave_types; v_days numeric; v_ent numeric; v_id bigint; v_today date := public._dhaka_today(); r public.leave_requests;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status not in ('active', 'on_leave') then raise exception 'not_found'; end if;
  if not (public._emp_ok(p_emp, array['attendance_manage']) or (e.profile_id is not null and e.profile_id = auth.uid())) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.leave_requests where client_id = p_client; if found then return to_jsonb(r) || jsonb_build_object('repeat', true); end if; end if;
  select * into t from public.leave_types where code = p_type and active;
  if not found then raise exception 'bad_leave_type'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_from < v_today - 62 or p_to > v_today + 366 or p_to - p_from > 180 then raise exception 'bad_date'; end if;
  if extract(year from p_from) <> extract(year from p_to) then raise exception 'leave_cross_year'; end if;
  if char_length(coalesce(p_reason, '')) > 300 then raise exception 'too_long: reason'; end if;
  if exists (select 1 from public.leave_requests x where x.employee_id = p_emp and x.status in ('pending', 'approved') and x.from_date <= p_to and x.to_date >= p_from) then raise exception 'leave_overlap'; end if;
  if exists (select 1 from generate_series(p_from, p_to, interval '1 day') g(d) where public._att_locked(p_emp, g.d::date)) then raise exception 'month_locked'; end if;
  v_days := public._leave_days(p_emp, p_from, p_to);
  if v_days <= 0 then raise exception 'leave_no_working_days'; end if;
  if t.paid then
    select coalesce(days_per_year, 0) into v_ent from public.employee_leave_entitlements where employee_id = p_emp and leave_type = p_type;
    if coalesce(v_ent, 0) - public._leave_used(p_emp, p_type, extract(year from p_from)::int, 'approved') - public._leave_used(p_emp, p_type, extract(year from p_from)::int, 'pending') < v_days then
      raise exception 'leave_balance_short';
    end if;
  end if;
  insert into public.leave_requests (client_id, employee_id, leave_type, from_date, to_date, days, reason, requested_by)
    values (p_client, p_emp, p_type, p_from, p_to, v_days, nullif(btrim(p_reason), ''), auth.uid()) returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.leave_decide(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.leave_requests; t public.leave_types; v_ent numeric; d date;
begin
  perform public._att_gate();
  select * into r from public.leave_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['attendance_manage']) then raise exception 'not allowed'; end if;
  if r.status <> 'pending' then raise exception 'leave_not_pending'; end if;
  if r.requested_by = auth.uid() and not (public.is_owner() and public.rule_on('owner_self_approve')) then raise exception 'maker_cannot_approve'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if coalesce(p_approve, false) then
    select * into t from public.leave_types where code = r.leave_type;
    if exists (select 1 from generate_series(r.from_date, r.to_date, interval '1 day') g(x) where public._att_locked(r.employee_id, g.x::date)) then raise exception 'month_locked'; end if;
    if t.paid then
      select coalesce(days_per_year, 0) into v_ent from public.employee_leave_entitlements where employee_id = r.employee_id and leave_type = r.leave_type;
      if coalesce(v_ent, 0) - public._leave_used(r.employee_id, r.leave_type, extract(year from r.from_date)::int, 'approved') < r.days then raise exception 'leave_balance_short'; end if;
    end if;
    update public.leave_requests set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '') where id = p_id;
    d := r.from_date;
    while d <= least(r.to_date, public._dhaka_today()) loop perform public._att_store(r.employee_id, d); d := d + 1; end loop;
  else
    update public.leave_requests set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '') where id = p_id;
  end if;
  return (select to_jsonb(x) from public.leave_requests x where x.id = p_id);
end $$;

create or replace function public.leave_cancel(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.leave_requests; d date; mine boolean;
begin
  perform public._att_gate();
  select * into r from public.leave_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  mine := exists (select 1 from public.employees e where e.id = r.employee_id and e.profile_id = auth.uid());
  if not (public._emp_ok(r.employee_id, array['attendance_manage']) or (mine and r.status = 'pending')) then raise exception 'not allowed'; end if;
  if r.status not in ('pending', 'approved') then raise exception 'leave_not_open'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if r.status = 'approved' and exists (select 1 from generate_series(r.from_date, r.to_date, interval '1 day') g(x) where public._att_locked(r.employee_id, g.x::date)) then raise exception 'month_locked'; end if;
  update public.leave_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now(), decision_note = left(btrim(p_reason), 300) where id = p_id;
  if r.status = 'approved' then
    d := r.from_date;
    while d <= least(r.to_date, public._dhaka_today()) loop perform public._att_store(r.employee_id, d); d := d + 1; end loop;
  end if;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

-- ---------- punches: ingest (shared by the device push and the file import) ----------
create or replace function public._att_ingest(p_rows jsonb, p_device int, p_loc int, p_source text, p_batch uuid, p_dry boolean, p_max int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_now timestamptz := now(); v_ok jsonb; n_total int; n_bad int; bad jsonb; n_valid int; n_dist int; n_db int; unm jsonb; n_unm int; dmin timestamptz; dmax timestamptz; n_new int := 0; n_emp int; pair record;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_rows'; end if;
  n_total := jsonb_array_length(p_rows);
  if n_total > p_max then raise exception 'too_many_rows'; end if;
  with s as (
    select o.i, o.r, case when jsonb_typeof(o.r) = 'object' then nullif(btrim(coalesce(o.r ->> 'user_id', o.r ->> 'uid', '')), '') end uid,
           case when jsonb_typeof(o.r) = 'object' then public._att_ts(coalesce(o.r ->> 'ts', o.r ->> 'time')) end ts
      from jsonb_array_elements(p_rows) with ordinality o(r, i)),
  c as (select s.*, case when jsonb_typeof(s.r) <> 'object' then 'bad_row' when s.uid is null or s.uid !~ '^[A-Za-z0-9_.:-]{1,40}$' then 'bad_user_id' when s.ts is null then 'bad_time'
                       when s.ts < v_now - interval '400 days' or s.ts > v_now + interval '10 minutes' then 'time_out_of_range' end why from s)
  select count(*) filter (where why is not null),
         coalesce(jsonb_agg(jsonb_build_object('row', i, 'why', why) order by i) filter (where why is not null and i <= 1000), '[]'),
         coalesce(jsonb_agg(jsonb_build_object('u', uid, 't', date_trunc('second', ts), 'd', public._att_dir(coalesce(r ->> 'dir', r ->> 'state', r ->> 'direction')),
                                               'raw', jsonb_strip_nulls(jsonb_build_object('verify', r -> 'verify', 'workcode', r -> 'workcode', 'state', coalesce(r -> 'dir', r -> 'state'))))) filter (where why is null), '[]')
    into n_bad, bad, v_ok from c;
  n_valid := jsonb_array_length(v_ok);
  with v as (select distinct x ->> 'u' u, (x ->> 't')::timestamptz t from jsonb_array_elements(v_ok) x)
  select count(*), count(*) filter (where exists (select 1 from public.attendance_punches p where p.device_id is not distinct from p_device and p.device_user_id = v.u and p.punched_at = v.t and not p.void)),
         min(v.t), max(v.t)
    into n_dist, n_db, dmin, dmax from v;
  select coalesce(jsonb_agg(distinct x ->> 'u'), '[]') into unm from jsonb_array_elements(v_ok) x
   where not exists (select 1 from public.employees e where e.device_user_id = x ->> 'u' and e.status not in ('draft', 'discarded'));
  n_unm := jsonb_array_length(unm);
  select count(distinct e.id) into n_emp from jsonb_array_elements(v_ok) x join public.employees e on e.device_user_id = x ->> 'u' and e.status not in ('draft', 'discarded');
  if not p_dry then
    with v as (select distinct on (x ->> 'u', (x ->> 't')::timestamptz) x ->> 'u' u, (x ->> 't')::timestamptz t, x ->> 'd' d, x -> 'raw' raw from jsonb_array_elements(v_ok) x),
    ins as (insert into public.attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source, raw, import_batch, created_by)
            select (select e.id from public.employees e where e.device_user_id = v.u and e.status not in ('draft', 'discarded')), p_device, p_loc, v.u, v.t, v.d, p_source, nullif(v.raw, '{}'::jsonb), p_batch, auth.uid()
              from v
            on conflict (device_id, device_user_id, punched_at) where not void do nothing
            returning employee_id, punched_at)
    select count(*) into n_new from ins;
    -- the days touched (and the day before, for a night shift) are recomputed
    for pair in select distinct p.employee_id, g.d::date d from public.attendance_punches p
                  cross join lateral generate_series(((p.punched_at at time zone 'Asia/Dhaka')::date - 1), (p.punched_at at time zone 'Asia/Dhaka')::date, interval '1 day') g(d)
                 where p.employee_id is not null and not p.void and p.created_at = v_now and p.device_id is not distinct from p_device and p.import_batch is not distinct from p_batch loop
      perform public._att_store(pair.employee_id, pair.d);
    end loop;
  end if;
  return jsonb_build_object('dry', p_dry, 'total', n_total, 'rejected', n_bad, 'rejected_rows', bad, 'valid', n_valid, 'duplicates_in_file', n_valid - n_dist,
    'already_in', n_db, 'new', case when p_dry then n_dist - n_db else n_new end, 'unmapped', n_unm, 'unmapped_ids', unm, 'employees', n_emp, 'from', dmin, 'to', dmax);
end $$;

-- the device bridge (anon key + device token). Inserts punches for THAT device only; reads nothing else and returns only counts.
create or replace function public.attendance_punch_push(p_token text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.attendance_devices; v_min timestamptz := date_trunc('minute', now()); lim int := coalesce(public.rule_num('att_push_per_min'), 30)::int; j jsonb;
begin
  if p_token is null or char_length(p_token) not between 20 and 200 then raise exception 'bad_token'; end if;
  select * into d from public.attendance_devices where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') and active for update;
  if not found then raise exception 'bad_token'; end if;
  if d.rl_minute = v_min and d.rl_count >= lim then raise exception 'rate_limited'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'too_many_rows'; end if;
  update public.attendance_devices set last_seen = now(), rl_count = case when rl_minute = v_min then rl_count + 1 else 1 end, rl_minute = v_min where id = d.id;
  j := public._att_ingest(p_rows, d.id, d.location_id, 'device', null, false, 500);
  update public.attendance_devices set pushed_rows = pushed_rows + (j ->> 'new')::int where id = d.id;
  return jsonb_build_object('ok', true, 'received', j -> 'total', 'new', j -> 'new', 'duplicates', (j ->> 'already_in')::int + (j ->> 'duplicates_in_file')::int,
                            'rejected', j -> 'rejected', 'rejected_rows', j -> 'rejected_rows', 'unmapped', j -> 'unmapped');
end $$;

-- file import from the app: p_dry = preview (writes nothing)
create or replace function public.attendance_import(p_loc int, p_device int, p_rows jsonb, p_file text, p_dry boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.attendance_import_batches; j jsonb; v_id uuid := gen_random_uuid();
begin
  perform public._att_gate();
  if not public._loc_ok(p_loc, 'attendance_manage') then raise exception 'not allowed'; end if;
  if p_device is not null and not exists (select 1 from public.attendance_devices where id = p_device and location_id = p_loc) then raise exception 'bad_device'; end if;
  if char_length(coalesce(p_file, '')) > 200 then raise exception 'too_long: file'; end if;
  if p_dry then return public._att_ingest(p_rows, p_device, p_loc, 'file', null, true, 5000); end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into b from public.attendance_import_batches where client_id = p_client; if found then return to_jsonb(b) || jsonb_build_object('repeat', true); end if; end if;
  insert into public.attendance_import_batches (id, client_id, location_id, device_id, file_name, created_by) values (v_id, p_client, p_loc, p_device, nullif(btrim(p_file), ''), auth.uid());
  j := public._att_ingest(p_rows, p_device, p_loc, 'file', v_id, false, 5000);
  update public.attendance_import_batches set rows_total = (j ->> 'total')::int, rows_new = (j ->> 'new')::int, rows_dup = (j ->> 'already_in')::int + (j ->> 'duplicates_in_file')::int,
      rows_bad = (j ->> 'rejected')::int, rows_unmapped = (j ->> 'unmapped')::int, date_from = (j ->> 'from')::timestamptz, date_to = (j ->> 'to')::timestamptz where id = v_id;
  return j || jsonb_build_object('batch', v_id);
end $$;

create or replace function public.attendance_import_void(p_batch uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare b public.attendance_import_batches; pair record; n int;
begin
  perform public._att_gate();
  select * into b from public.attendance_import_batches where id = p_batch for update;
  if not found then raise exception 'not_found'; end if;
  if not public._loc_ok(b.location_id, 'attendance_manage') then raise exception 'not allowed'; end if;
  if b.status = 'void' then return jsonb_build_object('id', b.id, 'status', 'void', 'repeat', true); end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if exists (select 1 from public.attendance_punches p where p.import_batch = b.id and p.employee_id is not null and public._att_locked(p.employee_id, (p.punched_at at time zone 'Asia/Dhaka')::date)) then raise exception 'month_locked'; end if;
  update public.attendance_import_batches set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = b.id;
  update public.attendance_punches set void = true where import_batch = b.id and not void;
  get diagnostics n = row_count;
  for pair in select distinct p.employee_id, g.d::date d from public.attendance_punches p
                cross join lateral generate_series(((p.punched_at at time zone 'Asia/Dhaka')::date - 1), (p.punched_at at time zone 'Asia/Dhaka')::date, interval '1 day') g(d)
               where p.import_batch = b.id and p.employee_id is not null loop
    perform public._att_store(pair.employee_id, pair.d);
  end loop;
  return jsonb_build_object('id', b.id, 'status', 'void', 'punches_voided', n);
end $$;

create or replace function public.attendance_unmapped(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_owner() or public._loc_ok(p_loc, 'attendance_manage')) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('device_user_id', z.device_user_id, 'device_id', z.device_id, 'device_name', dv.name, 'punches', z.n, 'first_at', z.f, 'last_at', z.l) order by z.l desc)
    from (select p.device_user_id, p.device_id, count(*) n, min(p.punched_at) f, max(p.punched_at) l from public.attendance_punches p
           where p.employee_id is null and not p.void and p.location_id = p_loc group by p.device_user_id, p.device_id) z
    left join public.attendance_devices dv on dv.id = z.device_id), '[]');
end $$;

-- give a device id to a person (employees.device_user_id) and attach the waiting punches
create or replace function public.attendance_map_user(p_device_user_id text, p_emp uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; n int; pair record;
begin
  perform public._att_gate();
  select * into e from public.employees where id = p_emp for update;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not public._emp_ok(p_emp, array['attendance_manage', 'employee_manage']) then raise exception 'not allowed'; end if;
  if p_device_user_id is null or btrim(p_device_user_id) !~ '^[A-Za-z0-9_.:-]{1,40}$' then raise exception 'bad_user_id'; end if;
  if exists (select 1 from public.employees x where x.device_user_id = btrim(p_device_user_id) and x.id <> p_emp) then raise exception 'duplicate_device_id'; end if;
  if e.device_user_id is distinct from btrim(p_device_user_id) then
    if e.device_user_id is not null and exists (select 1 from public.attendance_punches p where p.employee_id = p_emp and p.device_user_id = e.device_user_id) then raise exception 'device_id_in_use'; end if;
    update public.employees set device_user_id = btrim(p_device_user_id), updated_by = auth.uid(), updated_at = now() where id = p_emp;
  end if;
  update public.attendance_punches set employee_id = p_emp where employee_id is null and not void and device_user_id = btrim(p_device_user_id);
  get diagnostics n = row_count;
  for pair in select distinct g.d::date d from public.attendance_punches p
                cross join lateral generate_series(((p.punched_at at time zone 'Asia/Dhaka')::date - 1), (p.punched_at at time zone 'Asia/Dhaka')::date, interval '1 day') g(d)
               where p.employee_id = p_emp and p.device_user_id = btrim(p_device_user_id) and not p.void and p.punched_at > now() - interval '70 days' loop
    perform public._att_store(p_emp, pair.d);
  end loop;
  return jsonb_build_object('employee_id', p_emp, 'device_user_id', btrim(p_device_user_id), 'punches_mapped', n);
end $$;

-- devices: the owner registers a device and sees its token once (only a hash is stored)
create or replace function public.attendance_device_register(p_name text, p_loc int, p_vendor text default 'zkteco', p_serial text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tok text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''); v_id int;
begin
  perform public._att_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_name), '') is null or char_length(p_name) > 60 then raise exception 'name_required'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if coalesce(p_vendor, 'zkteco') not in ('zkteco', 'hikvision', 'suprema', 'other') then raise exception 'bad_vendor'; end if;
  if char_length(coalesce(p_serial, '')) > 60 then raise exception 'too_long: serial'; end if;
  insert into public.attendance_devices (name, location_id, vendor, serial, token_hash, created_by)
    values (btrim(p_name), p_loc, coalesce(p_vendor, 'zkteco'), nullif(btrim(p_serial), ''), encode(sha256(convert_to(v_tok, 'UTF8')), 'hex'), auth.uid()) returning id into v_id;
  return jsonb_build_object('id', v_id, 'token', v_tok, 'shown_once', true);
end $$;
create or replace function public.attendance_device_token_reset(p_id int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tok text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  perform public._att_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.attendance_devices set token_hash = encode(sha256(convert_to(v_tok, 'UTF8')), 'hex') where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'token', v_tok, 'shown_once', true);
end $$;
create or replace function public.attendance_device_set_active(p_id int, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._att_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  update public.attendance_devices set active = coalesce(p_active, false) where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'active', coalesce(p_active, false));
end $$;

-- optional staff check in / out from the app (rule app_punch_on, default OFF)
create or replace function public.attendance_app_punch(p_dir text default 'unknown') returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_id bigint;
begin
  perform public._att_gate();
  if not public.rule_on('app_punch_on') then raise exception 'app_punch_off'; end if;
  select * into e from public.employees where profile_id = auth.uid() and status in ('active', 'on_leave');
  if not found then raise exception 'no_employee_record'; end if;
  if exists (select 1 from public.attendance_punches where employee_id = e.id and source = 'app' and punched_at > now() - interval '1 minute' and not void) then raise exception 'too_soon'; end if;
  insert into public.attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source, created_by)
    values (e.id, null, e.primary_location_id, 'app:' || e.id::text, date_trunc('second', now()), case when p_dir in ('in', 'out') then p_dir else 'unknown' end, 'app', auth.uid()) returning id into v_id;
  perform public._att_store(e.id, public._dhaka_today());
  if (now() at time zone 'Asia/Dhaka')::time < time '06:00' then perform public._att_store(e.id, public._dhaka_today() - 1); end if;
  return jsonb_build_object('id', v_id, 'at', now(), 'direction', case when p_dir in ('in', 'out') then p_dir else 'unknown' end);
end $$;

-- ---------- advances (salary-sensitive) ----------
create or replace function public._adv_outstanding(p_adv bigint) returns numeric language sql stable security definer set search_path = public as $$
  select a.amount - coalesce((select sum(r.amount) from public.employee_advance_recoveries r where r.advance_id = a.id and r.status = 'active'), 0) from public.employee_advances a where a.id = p_adv;
$$;
-- 02-3 register (paper form data): the latest written balance for this person, when the name / staff id matches. Information only.
create or replace function public._adv_02_3(p_emp uuid) returns numeric language sql stable security definer set search_path = public as $$
  select public._db_num(a.v -> 'balance') from public.employees e
    left join public.profiles pr on pr.id = e.profile_id
    join public.entries x on x.form_code = '02-3' and x.status in ('submitted', 'approved') and x.location_id = e.primary_location_id
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x.data -> 'adv') = 'array' then x.data -> 'adv' else '[]'::jsonb end) with ordinality a(v, n)
   where e.id = p_emp and lower(btrim(split_part(coalesce(x.data ->> 'staff', ''), ' - ', 1))) in (lower(coalesce(e.employee_no, '-')), lower(e.full_name_bn), lower(coalesce(e.full_name_en, '-')), lower(coalesce(pr.staff_id, '-')), lower(coalesce(pr.full_name, '-')))
   order by x.entry_date desc, x.serial desc, a.n desc limit 1;
$$;

create or replace function public.staff_advance_add(p_emp uuid, p_date date, p_amount numeric, p_instalment numeric, p_mode text, p_recover_from date, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; r public.employee_advances; v_today date := public._dhaka_today();
begin
  perform public._pr_gate();
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then raise exception 'not_found'; end if;
  if not public._emp_ok(p_emp, array['payroll_manage']) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.employee_advances where client_id = p_client; if found then return to_jsonb(r) || jsonb_build_object('repeat', true); end if; end if;
  if p_date is null or p_date > v_today or p_date < v_today - 400 then raise exception 'bad_date'; end if;
  if p_amount is null or not (p_amount > 0 and p_amount <= 1000000000000) then raise exception 'bad_amount'; end if;
  if p_instalment is not null and not (p_instalment > 0 and p_instalment <= p_amount) then raise exception 'bad_instalment'; end if;
  if coalesce(p_mode, 'none') not in ('none', 'cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if coalesce(p_mode, 'none') <> 'none' then perform public.lock_check(p_date); end if;
  insert into public.employee_advances (client_id, employee_id, location_id, adv_date, amount, instalment, recover_from, mode, note, created_by)
    values (p_client, p_emp, e.primary_location_id, p_date, round(p_amount, 2), round(p_instalment, 2), date_trunc('month', coalesce(p_recover_from, p_date))::date, coalesce(p_mode, 'none'), nullif(btrim(p_note), ''), auth.uid())
    returning * into r;
  return to_jsonb(r) || jsonb_build_object('outstanding', r.amount);
end $$;
create or replace function public.staff_advance_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.employee_advances;
begin
  perform public._pr_gate();
  select * into a from public.employee_advances where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(a.employee_id, array['payroll_manage']) then raise exception 'not allowed'; end if;
  if a.status = 'void' then return jsonb_build_object('id', p_id, 'status', 'void', 'repeat', true); end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if exists (select 1 from public.employee_advance_recoveries r where r.advance_id = p_id and r.status = 'active') then raise exception 'advance_partly_recovered'; end if;
  if a.mode <> 'none' then perform public.lock_check(a.adv_date); end if;
  update public.employee_advances set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', 'void');
end $$;
create or replace function public.staff_advances_list(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._emp_ok(p_emp, array['salary_view', 'payroll_manage']) then raise exception 'not allowed'; end if;
  return jsonb_build_object('advances', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('outstanding', public._adv_outstanding(a.id)) order by a.adv_date desc, a.id desc)
                                                    from public.employee_advances a where a.employee_id = p_emp), '[]'),
                            'register_02_3_balance', public._adv_02_3(p_emp));
end $$;

create or replace function public.payroll_bonus_event_save(p_month date, p_name text, p_loc int default null, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id int; m date := date_trunc('month', p_month)::date;
begin
  perform public._pr_gate();
  if not (public.is_owner() or (p_loc is not null and public._pr_ok(p_loc, true))) then raise exception 'not allowed'; end if;
  if p_month is null or m < date '2020-01-01' or m > public._dhaka_today() + 400 then raise exception 'bad_date'; end if;
  if nullif(btrim(p_name), '') is null or char_length(p_name) > 60 then raise exception 'name_required'; end if;
  select id into v_id from public.payroll_bonus_events where month = m and lower(name) = lower(btrim(p_name)) and coalesce(location_id, 0) = coalesce(p_loc, 0) and active;
  if found then
    if not coalesce(p_active, true) then update public.payroll_bonus_events set active = false where id = v_id; end if;
  elsif coalesce(p_active, true) then
    insert into public.payroll_bonus_events (month, name, location_id, created_by) values (m, btrim(p_name), p_loc, auth.uid()) returning id into v_id;
  end if;
  return jsonb_build_object('id', v_id, 'month', m, 'name', btrim(p_name), 'active', coalesce(p_active, true));
end $$;

-- ---------- payroll calculation (pure read; preview and create both use it, so their numbers are the same) ----------
create or replace function public._pr_totals(j jsonb) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare g numeric; d numeric; raw numeric; net numeric; b numeric; od numeric; ap numeric; an numeric;
begin
  select coalesce(sum((x ->> 'amount')::numeric), 0) into b from jsonb_array_elements(coalesce(j -> 'bonus', '[]')) x;
  select coalesce(sum((x ->> 'amount')::numeric), 0) into od from jsonb_array_elements(coalesce(j -> 'other_deductions', '[]')) x;
  select coalesce(sum((x ->> 'amount')::numeric) filter (where (x ->> 'amount')::numeric > 0), 0), coalesce(-sum((x ->> 'amount')::numeric) filter (where (x ->> 'amount')::numeric < 0), 0)
    into ap, an from jsonb_array_elements(coalesce(j -> 'adjustments', '[]')) x;
  g := round(coalesce((j ->> 'basic_amount')::numeric, 0) + coalesce((j ->> 'allowance_total')::numeric, 0) + coalesce((j ->> 'ot_amount')::numeric, 0) + b + ap, 2);
  d := round(coalesce((j ->> 'not_employed_deduction')::numeric, 0) + coalesce((j ->> 'absent_deduction')::numeric, 0) + coalesce((j ->> 'unpaid_deduction')::numeric, 0)
           + coalesce((j ->> 'late_deduction')::numeric, 0) + coalesce((j ->> 'structure_deduction_total')::numeric, 0) + coalesce((j ->> 'advance_recovery')::numeric, 0) + od + an, 2);
  raw := g - d;
  net := case when coalesce(public.rule_txt('pay_round_net'), 'nearest') = 'nearest' then round(raw, 0) else round(raw, 2) end;
  return jsonb_build_object('gross', g, 'deductions', d, 'round_adj', net - raw, 'net', net, 'bonus_total', b);
end $$;

create or replace function public._payroll_calc(p_emp uuid, p_month date, p_last date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; pay public.employee_pay; m0 date := date_trunc('month', p_month)::date; m1 date; dim int; v_today date := public._dhaka_today();
  ef date; et date; employed int; notemp int; comps jsonb; pc jsonb; f numeric; c jsonb; allow jsonb := '[]'; sded jsonb := '[]'; at numeric := 0; sdt numeric := 0; v numeric;
  a record; w jsonb := '[]'; trail jsonb := '[]'; day_rate numeric; hourly numeric; hb numeric; basic_amt numeric; abs_eq numeric; unpaid_total numeric; paid_days numeric;
  notemp_ded numeric := 0; abs_ded numeric := 0; unp_ded numeric := 0; late_ded numeric := 0; late_mode text := coalesce(public.rule_txt('att_late_mode'), 'count'); late_n int := greatest(coalesce(public.rule_num('att_lates_per_day'), 3)::int, 1);
  ot_amt numeric := 0; m_norm numeric := 0; m_hol numeric := 0; bonus jsonb := '[]'; ev record; br jsonb; svc int; adv record; avail numeric; take numeric; rec numeric := 0; advs jsonb := '[]';
  pre jsonb; tot jsonb; line jsonb; off_paid boolean := public.rule_on('pay_weekly_off_paid'); hol_paid boolean := public.rule_on('pay_holiday_paid'); cap int := (coalesce(public.rule_num('att_ot_cap_hours'), 2) * 60)::int;
  ab numeric := coalesce(public.rule_num('att_bonus_amount'), 0); adv0203 numeric;
begin
  select * into e from public.employees where id = p_emp;
  if not found or e.status in ('draft', 'discarded') then return null; end if;
  m1 := (m0 + interval '1 month')::date - 1; dim := m1 - m0 + 1;
  ef := greatest(m0, coalesce(e.joining_date, m0));
  et := least(m1, coalesce(p_last, case when e.status in ('resigned', 'terminated', 'retired') then e.status_date end, m1));
  if et < ef then return null; end if;
  employed := et - ef + 1; notemp := dim - employed;
  if e.joining_date is null then w := w || '["no_joining_date"]'; end if;
  pay := public._emp_pay_on(e.id, et);
  if pay.id is null then
    return jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name', e.full_name_bn, 'name_en', e.full_name_en, 'location_id', e.primary_location_id, 'month', m0,
      'days_in_month', dim, 'employed_days', employed, 'basic', 0, 'basic_amount', 0, 'gross', 0, 'deductions', 0, 'net', 0, 'round_adj', 0, 'warnings', w || '["no_pay_structure"]', 'skip', true);
  end if;
  hb := coalesce(pay.ot_hours_basis, 8);
  f := employed::numeric / dim;
  select coalesce(jsonb_agg(jsonb_build_object('kind', x.kind, 'name', x.name, 'amount', x.amount, 'percent_of_basic', x.percent_of_basic) order by x.id), '[]') into comps
    from public.employee_pay_components x where x.pay_id = pay.id and x.active;
  pc := public._pay_calc(pay.basic, comps);
  for c in select * from jsonb_array_elements(pc -> 'components') loop
    v := round((c ->> 'calc')::numeric * f, 2);
    if c ->> 'kind' = 'allowance' then allow := allow || jsonb_build_array(jsonb_build_object('name', c ->> 'name', 'amount', v)); at := at + v;
    else sded := sded || jsonb_build_array(jsonb_build_object('name', c ->> 'name', 'amount', v)); sdt := sdt + v; end if;
  end loop;
  -- attendance of the employed days
  select count(*) filter (where d.employee_id is null and g.x::date <= v_today) missing, count(*) filter (where d.employee_id is null and g.x::date > v_today) future,
         count(*) filter (where d.status = 'absent') absent, count(*) filter (where d.status = 'half_day') half, count(*) filter (where d.status = 'unpaid') unpaid,
         count(*) filter (where d.status = 'leave' and coalesce(d.paid_day, true)) lpaid, count(*) filter (where d.status = 'leave' and d.paid_day = false) lunpaid,
         count(*) filter (where d.status = 'off') off, count(*) filter (where d.status = 'holiday' and coalesce(d.paid_day, true)) hpaid, count(*) filter (where d.status = 'holiday' and d.paid_day = false) hunpaid,
         count(*) filter (where d.late_minutes > 0 and d.status in ('present', 'late', 'half_day')) late_count,
         coalesce(sum(d.late_minutes) filter (where d.status in ('present', 'late', 'half_day')), 0) late_min,
         coalesce(sum(case when d.ot_approved or (d.source = 'manual' and d.approved_by is not null) then d.ot_minutes else least(d.ot_minutes, cap) end) filter (where d.day_kind = 'normal'), 0) ot_norm,
         coalesce(sum(case when d.ot_approved or (d.source = 'manual' and d.approved_by is not null) then d.ot_minutes else least(d.ot_minutes, cap) end) filter (where d.day_kind <> 'normal'), 0) ot_hol,
         coalesce(sum(d.ot_minutes - case when d.ot_approved or (d.source = 'manual' and d.approved_by is not null) then d.ot_minutes else least(d.ot_minutes, cap) end), 0) ot_held,
         count(*) filter (where d.source = 'manual' and d.approved_by is null) pending, count(*) filter (where d.single_punch) single,
         coalesce(sum(d.worked_minutes), 0) worked
    into a from generate_series(ef, et, interval '1 day') g(x) left join public.attendance_days d on d.employee_id = e.id and d.day = g.x::date;
  if a.missing > 0 then w := w || jsonb_build_array('days_not_computed:' || a.missing); end if;
  if a.future > 0 then w := w || jsonb_build_array('month_not_finished:' || a.future); end if;
  if a.pending > 0 then w := w || jsonb_build_array('unapproved_days:' || a.pending); end if;
  if a.single > 0 then w := w || jsonb_build_array('single_punch_days:' || a.single); end if;
  if a.ot_held > 0 then w := w || jsonb_build_array('ot_waiting_approval_min:' || a.ot_held); end if;
  abs_eq := a.absent + 0.5 * a.half;
  unpaid_total := a.unpaid + a.lunpaid + a.hunpaid + case when off_paid then 0 else a.off end + case when hol_paid then 0 else a.hpaid end;
  paid_days := employed - abs_eq - unpaid_total;
  trail := trail || jsonb_build_array(jsonb_build_object('k', 'basic', 'f', pay.pay_basis || ' ' || pay.basic, 'v', pay.basic),
                                      jsonb_build_object('k', 'days', 'f', employed || ' / ' || dim, 'v', employed));
  if pay.pay_basis = 'monthly' then
    day_rate := pay.basic / dim; hourly := pay.basic / dim / hb; basic_amt := round(pay.basic, 2);
    notemp_ded := round(day_rate * notemp, 2); abs_ded := round(day_rate * abs_eq, 2); unp_ded := round(day_rate * unpaid_total, 2);
    trail := trail || jsonb_build_array(jsonb_build_object('k', 'day_rate', 'f', pay.basic || ' / ' || dim, 'v', round(day_rate, 4)));
    if notemp > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'not_employed', 'f', notemp || ' × ' || round(day_rate, 4), 'v', -notemp_ded)); end if;
    if abs_eq > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'absent', 'f', abs_eq || ' × ' || round(day_rate, 4), 'v', -abs_ded)); end if;
    if unpaid_total > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'unpaid', 'f', unpaid_total || ' × ' || round(day_rate, 4), 'v', -unp_ded)); end if;
  elsif pay.pay_basis = 'daily' then
    day_rate := pay.basic; hourly := pay.basic / hb; basic_amt := round(pay.basic * paid_days, 2);
    trail := trail || jsonb_build_array(jsonb_build_object('k', 'daily_pay', 'f', paid_days || ' × ' || pay.basic, 'v', basic_amt));
  else
    day_rate := pay.basic * hb; hourly := pay.basic;
    basic_amt := round(pay.basic * (a.worked / 60.0 + (a.lpaid + case when hol_paid then a.hpaid else 0 end + case when off_paid then a.off else 0 end) * hb), 2);
    trail := trail || jsonb_build_array(jsonb_build_object('k', 'hourly_pay', 'f', round(a.worked / 60.0, 2) || ' h × ' || pay.basic, 'v', basic_amt));
  end if;
  if at > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'allowances', 'f', case when f < 1 then 'x ' || employed || '/' || dim else '' end, 'v', at)); end if;
  -- late
  if late_mode = 'count' then
    late_ded := round(day_rate * floor(a.late_count::numeric / late_n), 2);
    if a.late_count > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'late', 'f', a.late_count || ' / ' || late_n || ' = ' || floor(a.late_count::numeric / late_n) || ' × ' || round(day_rate, 4), 'v', -late_ded)); end if;
  elsif late_mode = 'per_minute' then
    late_ded := round(a.late_min * day_rate / (hb * 60), 2);
    if a.late_min > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'late', 'f', a.late_min || ' min × ' || round(day_rate / (hb * 60), 4), 'v', -late_ded)); end if;
  end if;
  -- overtime
  if pay.ot_rule = 'multiple_of_hourly' then
    m_norm := pay.ot_value; m_hol := greatest(pay.ot_value, coalesce(public.rule_num('ot_mult_holiday'), 2));
    ot_amt := round(hourly * m_norm * a.ot_norm / 60.0 + hourly * m_hol * a.ot_hol / 60.0, 2);
  elsif pay.ot_rule = 'rate_per_hour' then
    hourly := pay.ot_value; m_norm := 1; m_hol := 1;
    ot_amt := round(pay.ot_value * (a.ot_norm + a.ot_hol) / 60.0, 2);
  elsif a.ot_norm + a.ot_hol > 0 then w := w || '["ot_not_paid_no_rule"]';
  end if;
  if ot_amt > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'ot', 'f', round(a.ot_norm / 60.0, 2) || ' h × ' || round(hourly, 4) || ' × ' || m_norm
                                       || case when a.ot_hol > 0 then ' + ' || round(a.ot_hol / 60.0, 2) || ' h × ' || round(hourly, 4) || ' × ' || m_hol else '' end, 'v', ot_amt)); end if;
  -- bonuses: attendance bonus, festival bonus (event of the month x the person's bonus rule)
  if ab > 0 and abs_eq = 0 and a.late_count = 0 and unpaid_total = 0 and a.missing = 0 and notemp = 0 then
    bonus := bonus || jsonb_build_array(jsonb_build_object('name', 'attendance_bonus', 'amount', round(ab, 2), 'auto', true));
  end if;
  for ev in select * from public.payroll_bonus_events b where b.month = m0 and b.active and (b.location_id is null or b.location_id = e.primary_location_id) order by b.id loop
    select x into br from jsonb_array_elements(coalesce(pay.bonus_rules, '[]')) x where lower(x ->> 'name') = lower(ev.name) limit 1;
    if br is null then continue; end if;
    svc := case when e.joining_date is null then 0 else (extract(year from age(m1 + 1, e.joining_date)) * 12 + extract(month from age(m1 + 1, e.joining_date)))::int end;
    if svc >= coalesce((br ->> 'min_service_months')::numeric, 0) then
      bonus := bonus || jsonb_build_array(jsonb_build_object('name', ev.name, 'amount', round(pay.basic * (br ->> 'months_of_basic')::numeric, 2), 'auto', true, 'service_months', svc));
    else
      w := w || jsonb_build_array('bonus_not_eligible:' || ev.name);
    end if;
  end loop;
  line := jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'name', e.full_name_bn, 'name_en', e.full_name_en, 'location_id', e.primary_location_id, 'month', m0,
    'pay_id', pay.id, 'pay_basis', pay.pay_basis, 'basic', pay.basic, 'basic_amount', basic_amt, 'allowances', allow, 'allowance_total', at, 'structure_deductions', sded, 'structure_deduction_total', sdt,
    'days_in_month', dim, 'employed_days', employed, 'paid_days', paid_days, 'absent_days', a.absent, 'half_days', a.half, 'unpaid_leave_days', unpaid_total, 'paid_leave_days', a.lpaid,
    'off_days', a.off, 'holiday_days', a.hpaid + a.hunpaid, 'late_count', a.late_count, 'late_minutes', a.late_min, 'late_deduction', late_ded, 'absent_deduction', abs_ded,
    'unpaid_deduction', unp_ded, 'not_employed_deduction', notemp_ded, 'ot_minutes', a.ot_norm + a.ot_hol, 'ot_amount', ot_amt, 'bonus', bonus, 'advance_recovery', 0, 'advances', '[]'::jsonb,
    'other_deductions', '[]'::jsonb, 'adjustments', '[]'::jsonb);
  -- advance recovery: oldest first, instalment by instalment, never more than what is left of the pay
  pre := public._pr_totals(line);
  avail := greatest((pre ->> 'gross')::numeric - (pre ->> 'deductions')::numeric, 0);
  for adv in select x.id, x.instalment, public._adv_outstanding(x.id) os from public.employee_advances x
              where x.employee_id = e.id and x.status = 'active' and x.recover_from <= m0 order by x.adv_date, x.id loop
    if adv.os <= 0 then continue; end if;
    take := least(adv.os, coalesce(adv.instalment, adv.os), avail);
    if take < least(adv.os, coalesce(adv.instalment, adv.os)) then w := w || '["advance_recovery_capped"]'; end if;
    if take > 0 then advs := advs || jsonb_build_array(jsonb_build_object('advance_id', adv.id, 'amount', round(take, 2), 'outstanding_before', adv.os)); rec := rec + round(take, 2); avail := avail - take; end if;
  end loop;
  if rec > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'advance', 'f', jsonb_array_length(advs) || '', 'v', -rec)); end if;
  if sdt > 0 then trail := trail || jsonb_build_array(jsonb_build_object('k', 'structure_deductions', 'f', '', 'v', -sdt)); end if;
  line := line || jsonb_build_object('advance_recovery', rec, 'advances', advs);
  tot := public._pr_totals(line);
  if (tot ->> 'net')::numeric < 0 then w := w || '["negative_net"]'; end if;
  adv0203 := public._adv_02_3(e.id);
  if coalesce(adv0203, 0) > 0 and not exists (select 1 from public.employee_advances x where x.employee_id = e.id and x.status = 'active') then w := w || jsonb_build_array('register_02_3_advance:' || adv0203); end if;
  return line || tot || jsonb_build_object('warnings', w, 'calc_detail', jsonb_build_object('trail', trail, 'day_rate', round(day_rate, 4), 'hourly', round(hourly, 4), 'ot_mult', m_norm, 'ot_mult_holiday', m_hol,
    'late_mode', late_mode, 'lates_per_day', late_n, 'missing_days', a.missing, 'future_days', a.future, 'pending_days', a.pending, 'ot_held_minutes', a.ot_held, 'register_02_3_balance', adv0203,
    'period', jsonb_build_object('from', ef, 'to', et)));
end $$;

-- who goes into a run: working staff + leavers of the month, at the place, the caller has payroll rights there
create or replace function public._pr_people(p_month date, p_loc int, p_manage boolean) returns setof uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e
   where (p_loc is null or e.primary_location_id = p_loc)
     and (e.status in ('active', 'on_leave') or (e.status in ('resigned', 'terminated', 'retired') and e.status_date >= p_month))
     and (e.joining_date is null or e.joining_date <= (p_month + interval '1 month')::date - 1)
     and public._pr_ok(e.primary_location_id, p_manage)
   order by e.employee_no nulls last, e.full_name_bn;
$$;
create or replace function public._pr_month(p_month date) returns date language plpgsql stable security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date;
begin
  if p_month is null or m < date '2020-01-01' or m > date_trunc('month', public._dhaka_today())::date then raise exception 'bad_month'; end if;
  return m;
end $$;

create or replace function public.payroll_preview(p_month date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m date := public._pr_month(p_month); lines jsonb := '[]'; skipped jsonb := '[]'; j jsonb; x uuid; taken uuid;
begin
  perform public._pr_gate();
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._pr_ok(p_loc, false) then raise exception 'not allowed'; end if;
  for x in select * from public._pr_people(m, p_loc, false) loop
    select l.employee_id into taken from public.payroll_lines l where l.employee_id = x and l.month = m and l.active;
    j := public._payroll_calc(x, m);
    if j is null then continue; end if;
    if taken is not null then j := j || jsonb_build_object('warnings', (j -> 'warnings') || '["already_in_run"]', 'in_run', true); end if;
    lines := lines || jsonb_build_array(j);
  end loop;
  return jsonb_build_object('dry', true, 'month', m, 'location_id', p_loc, 'lines', lines, 'totals', jsonb_build_object(
    'people', (select count(*) from jsonb_array_elements(lines) l where not coalesce((l ->> 'skip')::boolean, false)),
    'gross', (select coalesce(sum((l ->> 'gross')::numeric), 0) from jsonb_array_elements(lines) l), 'deductions', (select coalesce(sum((l ->> 'deductions')::numeric), 0) from jsonb_array_elements(lines) l),
    'net', (select coalesce(sum((l ->> 'net')::numeric), 0) from jsonb_array_elements(lines) l),
    'warnings', (select count(*) from jsonb_array_elements(lines) l where jsonb_array_length(l -> 'warnings') > 0)));
end $$;

-- write one calculated line into a draft run (keeps the manual bonus / deduction / adjustment items of an existing line)
create or replace function public._pr_put_line(p_run bigint, p_emp uuid, p_month date) returns bigint language plpgsql security definer set search_path = public as $$
declare j jsonb; old public.payroll_lines; v_id bigint; tot jsonb;
begin
  j := public._payroll_calc(p_emp, p_month);
  if j is null or coalesce((j ->> 'skip')::boolean, false) then return null; end if;
  select * into old from public.payroll_lines where run_id = p_run and employee_id = p_emp and active;
  if found then
    j := j || jsonb_build_object('bonus', (j -> 'bonus') || coalesce((select jsonb_agg(x) from jsonb_array_elements(old.bonus) x where not coalesce((x ->> 'auto')::boolean, false)), '[]'),
                                 'other_deductions', old.other_deductions, 'adjustments', old.adjustments);
  end if;
  tot := public._pr_totals(j);
  j := j || tot;
  if old.id is not null then
    update public.payroll_lines set location_id = (j ->> 'location_id')::int, employee_no = j ->> 'employee_no', name = j ->> 'name', pay_id = (j ->> 'pay_id')::bigint, pay_basis = j ->> 'pay_basis',
      basic = (j ->> 'basic')::numeric, basic_amount = (j ->> 'basic_amount')::numeric, allowances = j -> 'allowances', allowance_total = (j ->> 'allowance_total')::numeric,
      structure_deductions = j -> 'structure_deductions', structure_deduction_total = (j ->> 'structure_deduction_total')::numeric, days_in_month = (j ->> 'days_in_month')::int,
      employed_days = (j ->> 'employed_days')::int, paid_days = (j ->> 'paid_days')::numeric, absent_days = (j ->> 'absent_days')::numeric, half_days = (j ->> 'half_days')::int,
      unpaid_leave_days = (j ->> 'unpaid_leave_days')::numeric, paid_leave_days = (j ->> 'paid_leave_days')::numeric, off_days = (j ->> 'off_days')::int, holiday_days = (j ->> 'holiday_days')::int,
      late_count = (j ->> 'late_count')::int, late_minutes = (j ->> 'late_minutes')::int, late_deduction = (j ->> 'late_deduction')::numeric, absent_deduction = (j ->> 'absent_deduction')::numeric,
      unpaid_deduction = (j ->> 'unpaid_deduction')::numeric, not_employed_deduction = (j ->> 'not_employed_deduction')::numeric, ot_minutes = (j ->> 'ot_minutes')::int, ot_amount = (j ->> 'ot_amount')::numeric,
      bonus = j -> 'bonus', advance_recovery = (j ->> 'advance_recovery')::numeric, advances = j -> 'advances', other_deductions = j -> 'other_deductions', adjustments = j -> 'adjustments',
      gross = (j ->> 'gross')::numeric, deductions = (j ->> 'deductions')::numeric, round_adj = (j ->> 'round_adj')::numeric, net = (j ->> 'net')::numeric, warnings = j -> 'warnings',
      calc_detail = j -> 'calc_detail', updated_at = now() where id = old.id;
    return old.id;
  end if;
  insert into public.payroll_lines (run_id, month, employee_id, location_id, employee_no, name, pay_id, pay_basis, basic, basic_amount, allowances, allowance_total, structure_deductions,
      structure_deduction_total, days_in_month, employed_days, paid_days, absent_days, half_days, unpaid_leave_days, paid_leave_days, off_days, holiday_days, late_count, late_minutes,
      late_deduction, absent_deduction, unpaid_deduction, not_employed_deduction, ot_minutes, ot_amount, bonus, advance_recovery, advances, other_deductions, adjustments,
      gross, deductions, round_adj, net, warnings, calc_detail)
    values (p_run, p_month, p_emp, (j ->> 'location_id')::int, j ->> 'employee_no', j ->> 'name', (j ->> 'pay_id')::bigint, j ->> 'pay_basis', (j ->> 'basic')::numeric, (j ->> 'basic_amount')::numeric,
      j -> 'allowances', (j ->> 'allowance_total')::numeric, j -> 'structure_deductions', (j ->> 'structure_deduction_total')::numeric, (j ->> 'days_in_month')::int, (j ->> 'employed_days')::int,
      (j ->> 'paid_days')::numeric, (j ->> 'absent_days')::numeric, (j ->> 'half_days')::int, (j ->> 'unpaid_leave_days')::numeric, (j ->> 'paid_leave_days')::numeric, (j ->> 'off_days')::int,
      (j ->> 'holiday_days')::int, (j ->> 'late_count')::int, (j ->> 'late_minutes')::int, (j ->> 'late_deduction')::numeric, (j ->> 'absent_deduction')::numeric, (j ->> 'unpaid_deduction')::numeric,
      (j ->> 'not_employed_deduction')::numeric, (j ->> 'ot_minutes')::int, (j ->> 'ot_amount')::numeric, j -> 'bonus', (j ->> 'advance_recovery')::numeric, j -> 'advances', j -> 'other_deductions',
      j -> 'adjustments', (j ->> 'gross')::numeric, (j ->> 'deductions')::numeric, (j ->> 'round_adj')::numeric, (j ->> 'net')::numeric, j -> 'warnings', j -> 'calc_detail')
    returning id into v_id;
  return v_id;
end $$;

create or replace function public._pr_run_json(p_run bigint) returns jsonb language sql stable security definer set search_path = public as $$
  select to_jsonb(r) || jsonb_build_object('lines', (select count(*) from public.payroll_lines l where l.run_id = r.id and l.active),
    'gross', (select coalesce(sum(l.gross), 0) from public.payroll_lines l where l.run_id = r.id and l.active), 'deductions', (select coalesce(sum(l.deductions), 0) from public.payroll_lines l where l.run_id = r.id and l.active),
    'net', (select coalesce(sum(l.net), 0) from public.payroll_lines l where l.run_id = r.id and l.active), 'paid', (select coalesce(sum(l.paid_amount), 0) from public.payroll_lines l where l.run_id = r.id and l.active))
  from public.payroll_runs r where r.id = p_run;
$$;

create or replace function public.payroll_create(p_month date, p_loc int default null, p_client uuid default null, p_notes text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := public._pr_month(p_month); r public.payroll_runs; v_id bigint; x uuid; n int := 0;
begin
  perform public._pr_gate();
  if p_loc is null and not public.is_owner() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public._pr_ok(p_loc, true) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.payroll_runs where client_id = p_client; if found then return public._pr_run_json(r.id) || jsonb_build_object('repeat', true); end if; end if;
  perform pg_advisory_xact_lock(hashtextextended('payroll:' || m::text, 0));
  if exists (select 1 from public.payroll_runs where month = m and coalesce(location_id, 0) = coalesce(p_loc, 0) and status <> 'void') then raise exception 'run_exists'; end if;
  if char_length(coalesce(p_notes, '')) > 500 then raise exception 'too_long: notes'; end if;
  insert into public.payroll_runs (client_id, month, location_id, notes, created_by) values (p_client, m, p_loc, nullif(btrim(p_notes), ''), auth.uid()) returning id into v_id;
  for x in select * from public._pr_people(m, p_loc, true) loop
    if exists (select 1 from public.payroll_lines l where l.employee_id = x and l.month = m and l.active) then continue; end if;
    if public._pr_put_line(v_id, x, m) is not null then n := n + 1; end if;
  end loop;
  return public._pr_run_json(v_id) || jsonb_build_object('created_lines', n);
end $$;

-- recompute every line of a draft (after an attendance fix); manual items stay
create or replace function public.payroll_refresh(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; x uuid; n int := 0;
begin
  perform public._pr_gate();
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if not (public.is_owner() or (r.location_id is not null and public._pr_ok(r.location_id, true))) then raise exception 'not allowed'; end if;
  if r.status <> 'draft' then raise exception 'payroll_locked'; end if;
  for x in select * from public._pr_people(r.month, r.location_id, true) loop
    if exists (select 1 from public.payroll_lines l where l.employee_id = x and l.month = r.month and l.active and l.run_id <> r.id) then continue; end if;
    if public._pr_put_line(r.id, x, r.month) is not null then n := n + 1; end if;
  end loop;
  return public._pr_run_json(r.id) || jsonb_build_object('refreshed_lines', n);
end $$;

-- draft line: add a bonus, a deduction or a (+/-) adjustment, each with a reason; or remove one manual item (p_remove = index in its list)
create or replace function public.payroll_line_adjust(p_line bigint, p_kind text, p_name text, p_amount numeric, p_reason text, p_remove int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.payroll_lines; r public.payroll_runs; item jsonb; col text; arr jsonb; tot jsonb; j jsonb;
begin
  perform public._pr_gate();
  select * into l from public.payroll_lines where id = p_line for update;
  if not found or not l.active then raise exception 'not_found'; end if;
  select * into r from public.payroll_runs where id = l.run_id;
  if not (public.is_owner() or public._pr_ok(l.location_id, true)) then raise exception 'not allowed'; end if;
  if r.status <> 'draft' then raise exception 'payroll_locked'; end if;
  if p_kind not in ('bonus', 'deduction', 'adjust') then raise exception 'bad_kind'; end if;
  col := case p_kind when 'bonus' then 'bonus' when 'deduction' then 'other_deductions' else 'adjustments' end;
  arr := to_jsonb(l) -> col;
  if p_remove is not null then
    if p_remove < 0 or p_remove >= jsonb_array_length(arr) or coalesce((arr -> p_remove ->> 'auto')::boolean, false) then raise exception 'bad_item'; end if;
    arr := arr - p_remove;
  else
    if nullif(btrim(p_name), '') is null or char_length(p_name) > 60 then raise exception 'name_required'; end if;
    if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
    if p_amount is null or p_amount = 0 or abs(p_amount) > 1000000000000 or (p_kind <> 'adjust' and p_amount < 0) then raise exception 'bad_amount'; end if;
    item := jsonb_build_object('name', btrim(p_name), 'amount', round(p_amount, 2), 'reason', btrim(p_reason), 'by', auth.uid(), 'at', now());
    arr := arr || jsonb_build_array(item);
  end if;
  j := to_jsonb(l) || jsonb_build_object(col, arr);
  tot := public._pr_totals(j);
  update public.payroll_lines set bonus = j -> 'bonus', other_deductions = j -> 'other_deductions', adjustments = j -> 'adjustments', gross = (tot ->> 'gross')::numeric,
         deductions = (tot ->> 'deductions')::numeric, round_adj = (tot ->> 'round_adj')::numeric, net = (tot ->> 'net')::numeric, updated_at = now(),
         warnings = case when (tot ->> 'net')::numeric < 0 then (select coalesce(jsonb_agg(w), '[]') from jsonb_array_elements(warnings) w where w <> '"negative_net"') || '["negative_net"]'
                         else (select coalesce(jsonb_agg(w), '[]') from jsonb_array_elements(warnings) w where w <> '"negative_net"') end
   where id = p_line;
  return (select to_jsonb(x) from public.payroll_lines x where x.id = p_line);
end $$;

-- owner approves: the month is locked for these people; advance recoveries are booked
create or replace function public.payroll_approve(p_run bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; l record; a jsonb;
begin
  perform public._pr_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if r.status in ('approved', 'paid') then return public._pr_run_json(r.id) || jsonb_build_object('repeat', true); end if;
  if r.status <> 'draft' then raise exception 'payroll_locked'; end if;
  if not exists (select 1 from public.payroll_lines where run_id = r.id and active) then raise exception 'run_empty'; end if;
  if exists (select 1 from public.payroll_lines where run_id = r.id and active and net < 0) then raise exception 'negative_net'; end if;
  for l in select * from public.payroll_lines where run_id = r.id and active loop
    for a in select * from jsonb_array_elements(l.advances) loop
      if (a ->> 'amount')::numeric > public._adv_outstanding((a ->> 'advance_id')::bigint) then raise exception 'advance_changed_refresh'; end if;
      insert into public.employee_advance_recoveries (advance_id, run_id, line_id, amount) values ((a ->> 'advance_id')::bigint, r.id, l.id, (a ->> 'amount')::numeric);
    end loop;
  end loop;
  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = r.id;
  update public.payroll_lines set payment_status = case when net = 0 then 'paid' else 'unpaid' end where run_id = r.id and active;
  return public._pr_run_json(r.id);
end $$;

-- record salary payments (all unpaid lines, or the given lines; one line may be paid in part with p_amount)
create or replace function public.payroll_pay(p_run bigint, p_lines bigint[], p_mode text, p_date date, p_ref text default null, p_note text default null, p_client uuid default null, p_amount numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; l public.payroll_lines; v_due numeric; v_amt numeric; n int := 0; tot numeric := 0; v_today date := public._dhaka_today();
begin
  perform public._pr_gate();
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if r.status not in ('approved', 'paid') then raise exception 'run_not_approved'; end if;
  perform public._client_lock(p_client);
  if p_client is not null and exists (select 1 from public.payroll_payments where client_batch = p_client) then
    return public._pr_run_json(r.id) || jsonb_build_object('repeat', true);
  end if;
  if p_mode not in ('cash', 'bank', 'mobile') then raise exception 'bad_mode'; end if;
  if p_date is null or p_date > v_today or p_date < r.month then raise exception 'bad_date'; end if;
  if char_length(coalesce(p_ref, '')) > 80 or char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long'; end if;
  if p_amount is not null and (coalesce(cardinality(p_lines), 0) <> 1 or not (p_amount > 0 and p_amount <= 1000000000000)) then raise exception 'bad_amount'; end if;
  perform public.lock_check(p_date);
  for l in select * from public.payroll_lines where run_id = r.id and active and (p_lines is null or id = any (p_lines)) order by id for update loop
    if not (public.is_owner() or public._pr_ok(l.location_id, true)) then raise exception 'not allowed'; end if;
    v_due := l.net - l.paid_amount;
    if v_due <= 0 then continue; end if;
    v_amt := coalesce(round(p_amount, 2), v_due);
    if v_amt > v_due then raise exception 'more_than_due'; end if;
    insert into public.payroll_payments (client_batch, run_id, line_id, employee_id, location_id, pay_date, mode, amount, ref, note, created_by)
      values (p_client, r.id, l.id, l.employee_id, l.location_id, p_date, p_mode, v_amt, nullif(btrim(p_ref), ''), nullif(btrim(p_note), ''), auth.uid());
    update public.payroll_lines set paid_amount = paid_amount + v_amt, payment_status = case when paid_amount + v_amt >= net then 'paid' else 'partly' end, updated_at = now() where id = l.id;
    n := n + 1; tot := tot + v_amt;
  end loop;
  if n = 0 then raise exception 'nothing_to_pay'; end if;
  if not exists (select 1 from public.payroll_lines where run_id = r.id and active and payment_status <> 'paid') then update public.payroll_runs set status = 'paid', paid_at = now() where id = r.id; end if;
  return public._pr_run_json(r.id) || jsonb_build_object('payments', n, 'amount', tot);
end $$;

create or replace function public.payroll_payment_void(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.payroll_payments;
begin
  perform public._pr_gate();
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into p from public.payroll_payments where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if p.status = 'void' then return jsonb_build_object('id', p_id, 'status', 'void', 'repeat', true); end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  perform public.lock_check(p.pay_date);
  update public.payroll_payments set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = p_id;
  update public.payroll_lines set paid_amount = paid_amount - p.amount, payment_status = case when paid_amount - p.amount <= 0 then 'unpaid' else 'partly' end, updated_at = now() where id = p.line_id;
  update public.payroll_runs set status = 'approved', paid_at = null where id = p.run_id and status = 'paid';
  return jsonb_build_object('id', p_id, 'status', 'void');
end $$;

-- void a run: a draft (payroll_manage) or an approved run without payments (owner); recoveries are undone, the month opens again
create or replace function public.payroll_void(p_run bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs;
begin
  perform public._pr_gate();
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'not_found'; end if;
  if r.status = 'void' then return jsonb_build_object('id', r.id, 'status', 'void', 'repeat', true); end if;
  if r.status = 'draft' and not (public.is_owner() or (r.location_id is not null and public._pr_ok(r.location_id, true))) then raise exception 'not allowed'; end if;
  if r.status <> 'draft' and not public.is_owner() then raise exception 'not allowed'; end if;
  if exists (select 1 from public.payroll_payments where run_id = r.id and status = 'done') then raise exception 'run_has_payments'; end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  update public.employee_advance_recoveries set status = 'void' where run_id = r.id and status = 'active';
  update public.payroll_runs set status = 'void', void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = r.id;
  update public.payroll_lines set active = false, updated_at = now() where run_id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'void');
end $$;

-- final settlement helper (preview only): pay up to the last day + advances still owed
create or replace function public.payroll_settlement_preview(p_emp uuid, p_last_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j jsonb; v_today date := public._dhaka_today();
begin
  perform public._pr_gate();
  if not public._emp_ok(p_emp, array['salary_view', 'payroll_manage']) then raise exception 'not allowed'; end if;
  if p_last_day is null or p_last_day > v_today + 31 or p_last_day < v_today - 400 then raise exception 'bad_date'; end if;
  j := public._payroll_calc(p_emp, date_trunc('month', p_last_day)::date, p_last_day);
  return jsonb_build_object('dry', true, 'line', j, 'already_in_run', exists (select 1 from public.payroll_lines l where l.employee_id = p_emp and l.month = date_trunc('month', p_last_day)::date and l.active),
    'advances_left', coalesce((select sum(public._adv_outstanding(a.id)) from public.employee_advances a where a.employee_id = p_emp and a.status = 'active'), 0) - coalesce((j ->> 'advance_recovery')::numeric, 0));
end $$;

-- ---------- day book: _daybook_lines23 from phase23 re-created with payroll payments and money-moving staff advances (salary-sensitive) ----------
create or replace function public._daybook_lines23(p_locs int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language sql stable as $$
  select m.location_id, m.move_date, x.dir, x.mode, m.kind, m.amount, m.ref, nullif(btrim(concat_ws(' · ', c.name, m.note)), ''), m.created_staff, m.created_at,
         case when m.customer_id is not null then 'customer' else 'cash_move' end, coalesce(m.customer_id::text, m.id::text), (m.kind = 'hub_receipt'), false
    from public.cash_moves m
    left join public.customers c on c.id = m.customer_id
    cross join lateral (values (1)) one
    cross join lateral (
      select * from (values
        ('bank_deposit', 'out', 'cash'), ('bank_deposit', 'in', 'bank'), ('bank_withdraw', 'out', 'bank'), ('bank_withdraw', 'in', 'cash'),
        ('owner_topup', 'in', m.mode), ('owner_draw', 'out', m.mode), ('cust_advance', 'in', m.mode), ('cust_advance_refund', 'out', m.mode), ('hub_receipt', 'in', 'cash')
      ) v(k, dir, mode) where v.k = m.kind) x
   where m.status = 'done' and m.location_id = any (p_locs) and m.move_date between p_from and p_to
  union all
  -- phase42: salary paid from a payroll run (salary-sensitive: only with salary_view at that place)
  select p.location_id, p.pay_date, 'out', p.mode, 'salary', p.amount, 'PR-' || p.run_id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, p.note)), ''), pr.staff_id, p.created_at,
         'payroll', p.id::text, false, true
    from public.payroll_payments p
    join public.employees e on e.id = p.employee_id
    left join public.profiles pr on pr.id = p.created_by
   where p.status = 'done' and p.location_id = any (p_locs) and p.pay_date between p_from and p_to and (public.is_owner() or public.has_grant('salary_view', p.location_id))
  union all
  -- phase42: staff advance paid out in cash / bank / mobile from the advance register (mode none = already in a 02-3 form, not counted again)
  select a.location_id, a.adv_date, 'out', a.mode, 'advance', a.amount, 'ADV-' || a.id::text, nullif(btrim(concat_ws(' · ', e.employee_no, e.full_name_bn, a.note)), ''), pr.staff_id, a.created_at,
         'staff_advance', a.id::text, false, true
    from public.employee_advances a
    join public.employees e on e.id = a.employee_id
    left join public.profiles pr on pr.id = a.created_by
   where a.status = 'active' and a.mode in ('cash', 'bank', 'mobile') and a.location_id = any (p_locs) and a.adv_date between p_from and p_to
     and (public.is_owner() or public.has_grant('salary_view', a.location_id));
$$;
revoke all on function public._daybook_lines23(int[], date, date) from public, anon, authenticated;

-- ---------- function grants: the browser calls the listed ones; anon only the device push; helpers closed ----------
do $$
declare p record;
  browser text[] := array['attendance_recompute', 'attendance_mark', 'attendance_approve', 'attendance_ot_approve', 'attendance_board', 'attendance_month', 'shift_save', 'shift_assign',
    'shift_assign_end', 'holiday_save', 'holiday_retire', 'leave_balances', 'leave_request_save', 'leave_decide', 'leave_cancel', 'attendance_import', 'attendance_import_void',
    'attendance_unmapped', 'attendance_map_user', 'attendance_device_register', 'attendance_device_token_reset', 'attendance_device_set_active', 'attendance_app_punch',
    'staff_advance_add', 'staff_advance_void', 'staff_advances_list', 'payroll_bonus_event_save', 'payroll_preview', 'payroll_create', 'payroll_refresh', 'payroll_line_adjust',
    'payroll_approve', 'payroll_pay', 'payroll_payment_void', 'payroll_void', 'payroll_settlement_preview', 'attendance_punch_push', '_att_view', '_att_loc_view', '_pr_ok'];
  helpers text[] := array['_punch_guard42', '_status_guard42', '_run_guard42', '_line_guard42', '_att_gate', '_pr_gate', '_att_rule_off_mask', '_att_is_off', '_att_holiday', '_att_shift_for',
    '_att_locked', '_att_ts', '_att_dir', '_hhmm', '_att_derive', '_att_store', '_leave_days', '_leave_used', '_att_ingest', '_adv_outstanding', '_adv_02_3', '_pr_totals', '_payroll_calc',
    '_pr_people', '_pr_month', '_pr_put_line', '_pr_run_json'];
begin
  for p in select oid::regprocedure as sig, proname from pg_proc where pronamespace = 'public'::regnamespace and (proname = any (browser) or proname = any (helpers)) loop
    execute format('revoke all on function %s from public, anon', p.sig);
    if p.proname = any (helpers) then
      execute format('revoke all on function %s from authenticated', p.sig);
    else
      execute format('grant execute on function %s to authenticated', p.sig);
    end if;
  end loop;
end $$;
-- the device bridge uses the anon key: this one function only
grant execute on function public.attendance_punch_push(text, jsonb) to anon;
