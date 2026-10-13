-- ============================================================
-- PHASE 41 (module B1): EMPLOYEES - registration, pay structure, facilities, documents, roles and DEEDS.
-- Additive and idempotent (paste twice = no error). Needs phase8..phase28 (uses phase11/15 no_hard_delete, norm_mobile, log_change,
-- is_active / is_owner / can_loc / has_grant, rules, grant_defs, rule_grants, option_lists / list_defs). Depends on no other new phase.
-- Nothing is deleted: people, pay versions, deeds, documents are retired by a status / void flag; records are append-only or guarded by triggers.
-- Rule switches: employees_module_on (ON), employee_mobile_unique (ON), deed_expiry_warn_days (30).
--
-- ---------------------------------------------------------------------------------------------------------------------------
-- SCHEMA CHEAT SHEET FOR THE NEXT MODULE (B2 attendance / payroll).  Today in all code = (now() at time zone 'Asia/Dhaka')::date.
-- ---------------------------------------------------------------------------------------------------------------------------
-- WHO IS AN EMPLOYEE:  public.employees  where status in ('active','on_leave')   ('draft' = wizard not finished, 'discarded' = abandoned draft;
--   neither is a person yet). resigned / terminated / retired are kept for history.
--   employees(id uuid pk, client_id uuid unique, employee_no text unique  -- 'E-0001'.. assigned when the draft is submitted, immutable, never reused
--     , full_name_bn, full_name_en, nickname, photo_path (Storage path EMP/<loc>/<id>.jpg in the private bucket 'photos'), gender male|female|other,
--     date_of_birth, blood_group, nid_no (digits only, unique), mobile (01XXXXXXXXX via norm_mobile), email, present_address, permanent_address,
--     emergency_name, emergency_relation, emergency_mobile, marital_status single|married|divorced|widowed, education, joining_date, probation_end,
--     designation text (code of option_lists 'emp_designation' or free text), department text (option_lists 'emp_department'),
--     primary_location_id int -> locations, primary_role_code -> staff_roles(code),
--     employment_type permanent|contract|daily|part_time|trainee,
--     status draft|active|on_leave|resigned|terminated|retired|discarded, status_date, status_reason,
--     profile_id uuid unique -> profiles (login account, optional), device_user_id text unique (fingerprint device id),
--     bank_account, mobile_wallet   -- PAY ACCOUNT: column NOT selectable by the browser; read with employee_pay_account_get() (salary_view)
--     , notes, created_by, created_at, updated_by, updated_at)
--   employee_locations(employee_id, location_id, active, added_by, added_at)  -- other places the person may work (primary one is on employees)
--   employee_status_log(id, employee_id, from_status, to_status, status_date, reason, by, at)   -- append-only history of status changes
--   employee_documents(id, employee_id, kind nid|contract|cv|certificate|guarantor|photo|other, file_path (EMPDOC/<loc>/.. or EMP/<loc>/..), note, uploaded_by, uploaded_at, void, void_by/at/reason)
-- PAY (salary-sensitive: rows are visible ONLY to the owner or a holder of grant salary_view at the person's location; writes owner / salary_manage):
--   employee_pay(id, employee_id, effective_from, pay_basis monthly|daily|hourly, basic, ot_rule none|rate_per_hour|multiple_of_hourly, ot_value
--     (amount per hour, or the multiple e.g. 1.5 / 2.0), ot_hours_basis (hours in a normal day, 8), bonus_rules jsonb
--     [{name, months_of_basic, min_service_months}], note, client_id, created_by, created_at)      -- APPEND-ONLY. CURRENT = latest effective_from <= today, ties -> highest id
--   employee_pay_components(id, pay_id -> employee_pay, kind allowance|deduction, name, amount | percent_of_basic (exactly one), taxable, active)
--     -- amount of a percent line = round(basic * percent / 100, 2). gross = basic + allowances; net = gross - deductions.
--   Helper for server code (not callable from the browser): public._emp_pay_on(employee uuid, date) returns the employee_pay row in force on that date;
--     public._emp_pay_json(pay_id) returns it with computed lines. Browser: employee_pay_current(emp [, on date]), employee_pay_history(emp).
--   employee_benefits(id, employee_id, kind meal|uniform|accommodation|transport|phone|insurance|other, description, value_per_month (column hidden
--     from the browser; employee_benefits_list() shows it to salary_view only), from_date, to_date, active)
--   leave_types(code, name_bn, name_en, paid, default_days, active, sort) seeded annual / sick / casual / unpaid / maternity / paternity
--   employee_leave_entitlements(id, employee_id, leave_type -> leave_types, days_per_year)   unique(employee_id, leave_type)
-- ROLES AND DEEDS:
--   staff_roles(code, name_bn, name_en, major, description, active, sort)   -- job roles (NOT the login roles of table roles)
--   deed_templates(id, family_id, version, role_code, title_bn, title_en, clauses jsonb, active, created_by, created_at)  -- content immutable, a change = new version
--     clauses = [{no, text_bn, text_en, kind rule|amount|duration|text, value, unit}]
--   employee_deeds(id, client_id, employee_id, template_id, role_code, title, clauses, start_date, end_date, probation_days, notice_days, security_deposit,
--     guarantor_name, guarantor_mobile, guarantor_nid, status draft|active|expired|terminated|superseded, signed_at, signed_doc_path,
--     revision_no, supersedes_id, created_by/at, activated_by/at, ended_by/at, end_reason)
--     -- immutable once active; a change = deed_revise() (new draft, revision_no + 1, supersedes_id) then deed_activate() which marks the old one superseded.
--     -- one ACTIVE deed per (employee, role) (partial unique index).
-- GRANTS (grant_defs): employee_view (see staff of own places, no pay; given by default to roles management / showroom_manager / factory_incharge),
--   employee_manage (register / edit / documents / draft deeds), salary_view (existing), salary_manage (write pay, accounts, benefit values), deed_manage (templates, activate / end deeds).
--   The owner passes all. Access is always scoped by the person's location (can_loc + has_grant(code, location)).
-- BROWSER FUNCTIONS: employee_save, employee_submit, employee_discard, employee_status_set, employee_locations_set, employee_link_profile, employee_set_photo,
--   employee_dup_check, employee_doc_add / employee_doc_void, employee_pay_set (p_dry = preview), employee_pay_current / _history, employee_pay_account_set / _get,
--   leave_entitlement_set, employee_benefit_save / _end / employee_benefits_list, staff_role_save, deed_template_save / _retire, deed_save, deed_revise,
--   deed_activate, deed_end, deed_attach_signed, deed_expire_due, deeds_expiring(days).
-- ============================================================

-- ---------- rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('employees_module_on', 'people', 'switch', 'true', null, null, null, null, 'কর্মচারী নিবন্ধন (নতুন যোগ / বদল) চালু', 'Employee নিবন্ধন (নতুন যোগ / বদল) চালু', 'Employee registration (add / change) is on',
  'বন্ধ করলে কেউ নতুন কর্মচারী যোগ বা তথ্য বদলাতে পারবে না; দেখা চলবে।', 'Off = nobody can add or change employees; viewing still works.', 160),
 ('employee_mobile_unique', 'people', 'switch', 'true', null, null, null, null, 'একই মোবাইল দুই কর্মচারীতে নয়', 'একই mobile দুই employee-তে নয়', 'One mobile number per employee',
  'চালু = আগে থেকে থাকা নম্বরে নতুন কর্মচারী সংরক্ষণ হবে না। বন্ধ = শুধু সতর্কবার্তা।', 'On = a number already used by another employee is refused. Off = only a warning.', 161),
 ('deed_expiry_warn_days', 'people', 'number', '30', 'days', null, 1, 365, 'চুক্তি (ডিড) শেষ হওয়ার কত দিন আগে সতর্ক করবে', 'Deed শেষ হওয়ার কত দিন আগে সতর্ক করবে', 'Warn this many days before a deed ends',
  null, null, 162)
 on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select v.c, 'people', v.s, v.bn, v.mx, v.en, 'window', null
from (values
 ('employee_view', 70, 'কর্মচারীর তথ্য দেখা (বেতন ছাড়া)', 'Employee-র তথ্য দেখা (salary ছাড়া)', 'See employee records (no pay)'),
 ('employee_manage', 71, 'কর্মচারী নিবন্ধন ও তথ্য বদল', 'Employee নিবন্ধন ও তথ্য বদল', 'Register and edit employees'),
 ('salary_manage', 72, 'বেতন কাঠামো বদলানো', 'Salary কাঠামো বদলানো', 'Set pay structures'),
 ('deed_manage', 73, 'ডিড টেমপ্লেট ও ডিড চালু/শেষ করা', 'Deed template ও deed চালু/শেষ করা', 'Manage deed templates, activate / end deeds')
) as v(c, s, bn, mx, en)
where not exists (select 1 from public.grant_defs g where g.grant_code = v.c);

insert into public.rule_grants (grant_code, role_code)
select 'employee_view', r.code from public.roles r where r.code in ('management', 'showroom_manager', 'factory_incharge')
on conflict do nothing;

-- ---------- lists (designation / department) ----------
insert into public.list_defs (list_code, add_rule) values ('emp_designation', 'owner'), ('emp_department', 'owner') on conflict (list_code) do nothing;
insert into public.option_lists (list_code, value_code, label_bn, label_en, sort) values
 ('emp_designation', 'manager', 'ম্যানেজার', 'Manager', 1), ('emp_designation', 'cashier', 'ক্যাশিয়ার', 'Cashier', 2), ('emp_designation', 'salesperson', 'সেলসম্যান', 'Salesperson', 3),
 ('emp_designation', 'storekeeper', 'স্টোরকিপার', 'Storekeeper', 4), ('emp_designation', 'factory_incharge', 'কারখানা ইনচার্জ', 'Factory in-charge', 5),
 ('emp_designation', 'head_artisan', 'প্রধান কারিগর', 'Head artisan (Karigor)', 6), ('emp_designation', 'artisan', 'কারিগর', 'Artisan', 7),
 ('emp_designation', 'helper', 'হেল্পার', 'Helper', 8), ('emp_designation', 'delivery', 'ডেলিভারি', 'Delivery', 9), ('emp_designation', 'accountant', 'হিসাবরক্ষক', 'Accountant', 10),
 ('emp_designation', 'guard', 'গার্ড', 'Guard', 11), ('emp_designation', 'cleaner', 'ক্লিনার', 'Cleaner', 12),
 ('emp_department', 'showroom', 'শোরুম', 'Showroom', 1), ('emp_department', 'factory', 'কারখানা', 'Factory', 2), ('emp_department', 'store', 'স্টোর', 'Store', 3),
 ('emp_department', 'accounts', 'হিসাব', 'Accounts', 4), ('emp_department', 'delivery', 'ডেলিভারি', 'Delivery', 5), ('emp_department', 'admin', 'প্রশাসন', 'Admin', 6)
 on conflict (list_code, value_code) do nothing;

-- ---------- core: roles, leave types ----------
create table if not exists public.staff_roles (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  name_bn text not null, name_en text not null, major boolean not null default false, description text,
  active boolean not null default true, sort int not null default 0
);
insert into public.staff_roles (code, name_bn, name_en, major, description, sort) values
 ('manager', 'ম্যানেজার (মালিকের প্রতিনিধি)', 'Manager (owner''s representative)', true, 'Runs a place on behalf of the owner', 1),
 ('cashier', 'ক্যাশিয়ার', 'Cashier', true, 'Handles cash', 2),
 ('salesperson', 'বিক্রয়কর্মী', 'Salesperson', false, 'Sells to customers', 3),
 ('storekeeper', 'স্টোরকিপার', 'Storekeeper', true, 'Responsible for stock', 4),
 ('factory_incharge', 'কারখানা ইনচার্জ', 'Factory in-charge', true, 'Runs production', 5),
 ('head_artisan', 'প্রধান কারিগর', 'Head artisan / Karigor', true, 'Leads the artisans', 6),
 ('helper', 'হেল্পার', 'Helper', false, null, 7),
 ('delivery', 'ডেলিভারি', 'Delivery', false, null, 8),
 ('accountant', 'হিসাবরক্ষক', 'Accountant', true, 'Keeps the books', 9),
 ('guard', 'গার্ড', 'Guard', false, null, 10),
 ('cleaner', 'ক্লিনার', 'Cleaner', false, null, 11)
 on conflict (code) do nothing;

create table if not exists public.leave_types (
  code text primary key, name_bn text not null, name_en text not null, paid boolean not null, default_days numeric not null default 0 check (default_days between 0 and 366),
  active boolean not null default true, sort int not null default 0
);
-- default_days are SUGGESTIONS only (the wizard pre-fills them, the owner edits); verify against the Bangladesh Labour Act before relying on them
insert into public.leave_types (code, name_bn, name_en, paid, default_days, sort) values
 ('annual', 'বার্ষিক ছুটি (বেতনসহ)', 'Annual leave (paid)', true, 0, 1), ('sick', 'অসুস্থতার ছুটি (বেতনসহ)', 'Sick leave (paid)', true, 14, 2),
 ('casual', 'নৈমিত্তিক ছুটি (বেতনসহ)', 'Casual leave (paid)', true, 10, 3), ('unpaid', 'বিনা বেতনের ছুটি', 'Unpaid leave', false, 0, 4),
 ('maternity', 'মাতৃত্বকালীন ছুটি', 'Maternity leave', true, 112, 5), ('paternity', 'পিতৃত্বকালীন ছুটি', 'Paternity leave', true, 0, 6)
 on conflict (code) do nothing;

-- ---------- employees ----------
create sequence if not exists public.employee_no_seq;
revoke all on sequence public.employee_no_seq from public, anon, authenticated;

create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  employee_no text unique,
  full_name_bn text not null check (char_length(btrim(full_name_bn)) between 1 and 120),
  full_name_en text, nickname text,
  photo_path text check (photo_path is null or photo_path ~ '^EMP/[0-9]+/[A-Za-z0-9_.-]{1,120}$'),
  gender text check (gender in ('male', 'female', 'other')),
  date_of_birth date, blood_group text check (blood_group in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  nid_no text check (nid_no is null or nid_no ~ '^([0-9]{10}|[0-9]{13}|[0-9]{17})$'),
  mobile text, email text, present_address text, permanent_address text,
  emergency_name text, emergency_relation text, emergency_mobile text,
  marital_status text check (marital_status in ('single', 'married', 'divorced', 'widowed')), education text,
  joining_date date, probation_end date, designation text, department text,
  primary_location_id int references public.locations(id), primary_role_code text references public.staff_roles(code),
  employment_type text not null default 'permanent' check (employment_type in ('permanent', 'contract', 'daily', 'part_time', 'trainee')),
  status text not null default 'draft' check (status in ('draft', 'active', 'on_leave', 'resigned', 'terminated', 'retired', 'discarded')),
  status_date date, status_reason text,
  profile_id uuid unique references public.profiles(id),
  device_user_id text, bank_account text, mobile_wallet text, notes text,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists employees_nid_uq on public.employees (nid_no) where nid_no is not null;
create unique index if not exists employees_device_uq on public.employees (device_user_id) where device_user_id is not null;
create index if not exists employees_loc on public.employees (primary_location_id, status);
create index if not exists employees_mobile on public.employees (mobile) where mobile is not null;

create table if not exists public.employee_locations (
  employee_id uuid not null references public.employees(id), location_id int not null references public.locations(id),
  active boolean not null default true, added_by uuid, added_at timestamptz not null default now(), primary key (employee_id, location_id)
);
create table if not exists public.employee_status_log (
  id bigserial primary key, employee_id uuid not null references public.employees(id), from_status text, to_status text not null,
  status_date date, reason text, by uuid, at timestamptz not null default now()
);
create index if not exists employee_status_log_emp on public.employee_status_log (employee_id, id);
create table if not exists public.employee_documents (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id),
  kind text not null check (kind in ('nid', 'contract', 'cv', 'certificate', 'guarantor', 'photo', 'other')),
  file_path text not null check (file_path ~ '^(EMP|EMPDOC)/[0-9]+/[A-Za-z0-9_.-]{1,120}$'), note text,
  uploaded_by uuid, uploaded_at timestamptz not null default now(), void boolean not null default false, void_by uuid, void_at timestamptz, void_reason text
);
create index if not exists employee_documents_emp on public.employee_documents (employee_id);

-- ---------- pay ----------
create table if not exists public.employee_pay (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), effective_from date not null,
  pay_basis text not null check (pay_basis in ('monthly', 'daily', 'hourly')), basic numeric not null check (basic > 0 and basic <= 1000000000000),
  ot_rule text not null default 'none' check (ot_rule in ('none', 'rate_per_hour', 'multiple_of_hourly')),
  ot_value numeric check (ot_value is null or (ot_value > 0 and ot_value <= 1000000)),
  ot_hours_basis numeric not null default 8 check (ot_hours_basis between 1 and 24),
  bonus_rules jsonb not null default '[]', note text, created_by uuid, created_at timestamptz not null default now(),
  check ((ot_rule = 'none') = (ot_value is null))
);
create index if not exists employee_pay_emp on public.employee_pay (employee_id, effective_from desc, id desc);
create table if not exists public.employee_pay_components (
  id bigserial primary key, pay_id bigint not null references public.employee_pay(id), kind text not null check (kind in ('allowance', 'deduction')),
  name text not null check (char_length(btrim(name)) between 1 and 60), amount numeric check (amount is null or (amount >= 0 and amount <= 1000000000000)),
  percent_of_basic numeric check (percent_of_basic is null or (percent_of_basic >= 0 and percent_of_basic <= 100)),
  taxable boolean not null default false, active boolean not null default true,
  check ((amount is null) <> (percent_of_basic is null))
);
create index if not exists employee_pay_components_pay on public.employee_pay_components (pay_id);

create table if not exists public.employee_benefits (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id),
  kind text not null check (kind in ('meal', 'uniform', 'accommodation', 'transport', 'phone', 'insurance', 'other')), description text,
  value_per_month numeric check (value_per_month is null or (value_per_month >= 0 and value_per_month <= 1000000000000)),
  from_date date not null, to_date date, active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (to_date is null or to_date >= from_date)
);
create index if not exists employee_benefits_emp on public.employee_benefits (employee_id);
create table if not exists public.employee_leave_entitlements (
  id bigserial primary key, employee_id uuid not null references public.employees(id), leave_type text not null references public.leave_types(code),
  days_per_year numeric not null check (days_per_year between 0 and 366), updated_by uuid, updated_at timestamptz not null default now(), unique (employee_id, leave_type)
);

-- ---------- deeds ----------
create table if not exists public.deed_templates (
  id bigserial primary key, client_id uuid unique, family_id bigint not null, version int not null check (version >= 1), role_code text not null references public.staff_roles(code),
  title_bn text not null, title_en text, clauses jsonb not null default '[]', active boolean not null default true, created_by uuid, created_at timestamptz not null default now(),
  unique (family_id, version)
);
create table if not exists public.employee_deeds (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), template_id bigint references public.deed_templates(id),
  role_code text not null references public.staff_roles(code), title text not null, clauses jsonb not null default '[]',
  start_date date, end_date date, probation_days int check (probation_days between 0 and 365), notice_days int check (notice_days between 0 and 365),
  security_deposit numeric check (security_deposit is null or (security_deposit >= 0 and security_deposit <= 1000000000000)),
  guarantor_name text, guarantor_mobile text, guarantor_nid text,
  status text not null default 'draft' check (status in ('draft', 'active', 'expired', 'terminated', 'superseded')),
  signed_at date, signed_doc_path text check (signed_doc_path is null or signed_doc_path ~ '^EMPDOC/[0-9]+/[A-Za-z0-9_.-]{1,120}$'),
  revision_no int not null default 1, supersedes_id bigint references public.employee_deeds(id),
  created_by uuid, created_at timestamptz not null default now(), activated_by uuid, activated_at timestamptz, ended_by uuid, ended_at timestamptz, end_reason text,
  check (end_date is null or start_date is null or end_date >= start_date)
);
create unique index if not exists employee_deeds_one_active on public.employee_deeds (employee_id, role_code) where status = 'active';
create unique index if not exists employee_deeds_one_revision on public.employee_deeds (supersedes_id) where supersedes_id is not null and status in ('draft', 'active');
create index if not exists employee_deeds_emp on public.employee_deeds (employee_id);

-- ---------- triggers: number, immutability, no delete, audit ----------
create or replace function public._emp_no_set() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.employee_no is not null and new.employee_no is distinct from old.employee_no then raise exception 'employee_no_immutable'; end if;
  if new.employee_no is null and new.status not in ('draft', 'discarded') then new.employee_no := 'E-' || lpad(nextval('public.employee_no_seq')::text, 4, '0'); end if;
  if tg_op = 'INSERT' and new.employee_no is not null and new.status in ('draft', 'discarded') then new.employee_no := null; end if;
  return new;
end $$;
drop trigger if exists employees_no on public.employees;
create trigger employees_no before insert or update on public.employees for each row execute function public._emp_no_set();

create or replace function public._append_only41() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists employee_pay_ro on public.employee_pay;
create trigger employee_pay_ro before update or delete on public.employee_pay for each row execute function public._append_only41();
drop trigger if exists employee_status_log_ro on public.employee_status_log;
create trigger employee_status_log_ro before update or delete on public.employee_status_log for each row execute function public._append_only41();

-- pay components: only the active flag may change
create or replace function public._pay_comp_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  return new;
end $$;
drop trigger if exists employee_pay_components_ro on public.employee_pay_components;
create trigger employee_pay_components_ro before update or delete on public.employee_pay_components for each row execute function public._pay_comp_guard();

-- deed templates: only the active flag may change (a new version is a new row)
create or replace function public._deed_tpl_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if (to_jsonb(new) - 'active') is distinct from (to_jsonb(old) - 'active') then raise exception 'template_immutable: make a new version'; end if;
  return new;
end $$;
drop trigger if exists deed_templates_ro on public.deed_templates;
create trigger deed_templates_ro before update or delete on public.deed_templates for each row execute function public._deed_tpl_guard();

-- deeds: a draft is free; once active only the end of life may be written (status, ended_*, end_reason) and a signed scan may be attached once
create or replace function public._deed_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end if;
  if old.status = 'draft' then
    if new.status not in ('draft', 'active', 'terminated') then raise exception 'deed_bad_status'; end if;
    return new;
  end if;
  if old.status <> 'active' then raise exception 'deed_immutable: this deed is %', old.status; end if;
  if new.status not in ('active', 'expired', 'terminated', 'superseded') then raise exception 'deed_bad_status'; end if;
  if (to_jsonb(new) - array['status', 'ended_by', 'ended_at', 'end_reason', 'signed_doc_path']) is distinct from (to_jsonb(old) - array['status', 'ended_by', 'ended_at', 'end_reason', 'signed_doc_path'])
     or (old.signed_doc_path is not null and new.signed_doc_path is distinct from old.signed_doc_path) then
    raise exception 'deed_immutable: an active deed cannot be changed - make a revision';
  end if;
  return new;
end $$;
drop trigger if exists employee_deeds_guard on public.employee_deeds;
create trigger employee_deeds_guard before update or delete on public.employee_deeds for each row execute function public._deed_guard();

do $$
declare t text;
begin
  foreach t in array array['employees', 'employee_locations', 'employee_documents', 'employee_benefits', 'employee_leave_entitlements', 'staff_roles', 'leave_types', 'employee_deeds', 'deed_templates'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists audit_employees on public.employees;
create trigger audit_employees after insert or update on public.employees for each row execute function public.log_change('id');
drop trigger if exists audit_employee_locations on public.employee_locations;
create trigger audit_employee_locations after insert or update on public.employee_locations for each row execute function public.log_change('employee_id,location_id');
drop trigger if exists audit_employee_documents on public.employee_documents;
create trigger audit_employee_documents after insert or update on public.employee_documents for each row execute function public.log_change('id');
drop trigger if exists audit_employee_pay on public.employee_pay;
create trigger audit_employee_pay after insert on public.employee_pay for each row execute function public.log_change('id');
drop trigger if exists audit_employee_pay_components on public.employee_pay_components;
create trigger audit_employee_pay_components after insert or update on public.employee_pay_components for each row execute function public.log_change('id');
drop trigger if exists audit_employee_benefits on public.employee_benefits;
create trigger audit_employee_benefits after insert or update on public.employee_benefits for each row execute function public.log_change('id');
drop trigger if exists audit_employee_leave on public.employee_leave_entitlements;
create trigger audit_employee_leave after insert or update on public.employee_leave_entitlements for each row execute function public.log_change('id');
drop trigger if exists audit_staff_roles on public.staff_roles;
create trigger audit_staff_roles after insert or update on public.staff_roles for each row execute function public.log_change('code');
drop trigger if exists audit_deed_templates on public.deed_templates;
create trigger audit_deed_templates after insert or update on public.deed_templates for each row execute function public.log_change('id');
drop trigger if exists audit_employee_deeds on public.employee_deeds;
create trigger audit_employee_deeds after insert or update on public.employee_deeds for each row execute function public.log_change('id');

-- ---------- access helpers (also used by the policies, so authenticated may execute them; they only answer about the caller) ----------
-- may the caller act on this employee with any of these grants? Scoped by the person's primary location (and, for viewing, the other places they work).
create or replace function public._emp_ok(p_emp uuid, p_codes text[], p_secondary boolean default false) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (
    select 1 from public.employees e
    cross join lateral (select e.primary_location_id as l
                        union select el.location_id from public.employee_locations el where p_secondary and el.employee_id = e.id and el.active) x
    cross join unnest(p_codes) c
    where e.id = p_emp and x.l is not null and public.can_loc(x.l) and public.has_grant(c, x.l)));
$$;
-- may the caller use this grant at some place (for things without a location: templates, lists)?
create or replace function public._emp_any(p_codes text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or exists (
    select 1 from public.locations l cross join unnest(p_codes) c where public.can_loc(l.id) and public.has_grant(c, l.id)));
$$;
create or replace function public._loc_ok(p_loc int, p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_loc is not null and (public.is_owner() or (public.can_loc(p_loc) and public.has_grant(p_code, p_loc)));
$$;

-- ---------- RLS: reads only; every write goes through the functions below ----------
do $$
declare t text;
begin
  foreach t in array array['employees', 'employee_locations', 'employee_status_log', 'employee_documents', 'employee_pay', 'employee_pay_components', 'employee_benefits',
                           'employee_leave_entitlements', 'staff_roles', 'leave_types', 'deed_templates', 'employee_deeds'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $$;

drop policy if exists employees_read on public.employees;
create policy employees_read on public.employees for select to authenticated using (
  public.is_active() and (public.is_owner() or profile_id = auth.uid() or (status = 'draft' and created_by = auth.uid())
    or public._emp_ok(id, array['employee_view', 'employee_manage'], true)));
-- the pay account columns are NOT selectable: employee_pay_account_get() (salary_view) is the only way
do $$
declare cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position) into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'employees' and column_name not in ('bank_account', 'mobile_wallet');
  execute 'revoke all on public.employees from authenticated';
  execute 'grant select (' || cols || ') on public.employees to authenticated';
end $$;

drop policy if exists employee_locations_read on public.employee_locations;
create policy employee_locations_read on public.employee_locations for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists employee_status_log_read on public.employee_status_log;
create policy employee_status_log_read on public.employee_status_log for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists employee_documents_read on public.employee_documents;
create policy employee_documents_read on public.employee_documents for select to authenticated using (public._emp_ok(employee_id, array['employee_manage']));
drop policy if exists employee_pay_read on public.employee_pay;
create policy employee_pay_read on public.employee_pay for select to authenticated using (public._emp_ok(employee_id, array['salary_view']));
drop policy if exists employee_pay_components_read on public.employee_pay_components;
create policy employee_pay_components_read on public.employee_pay_components for select to authenticated
  using (exists (select 1 from public.employee_pay p where p.id = pay_id and public._emp_ok(p.employee_id, array['salary_view'])));
drop policy if exists employee_benefits_read on public.employee_benefits;
create policy employee_benefits_read on public.employee_benefits for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists employee_leave_read on public.employee_leave_entitlements;
create policy employee_leave_read on public.employee_leave_entitlements for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage'], true));
drop policy if exists staff_roles_read on public.staff_roles;
create policy staff_roles_read on public.staff_roles for select to authenticated using (public.is_active());
drop policy if exists leave_types_read on public.leave_types;
create policy leave_types_read on public.leave_types for select to authenticated using (public.is_active());
drop policy if exists deed_templates_read on public.deed_templates;
create policy deed_templates_read on public.deed_templates for select to authenticated using (public._emp_any(array['deed_manage', 'employee_manage']));
drop policy if exists employee_deeds_read on public.employee_deeds;
create policy employee_deeds_read on public.employee_deeds for select to authenticated using (public._emp_ok(employee_id, array['employee_manage', 'deed_manage']));

grant select on public.employee_locations, public.employee_status_log, public.employee_documents, public.employee_pay, public.employee_pay_components,
  public.employee_leave_entitlements, public.staff_roles, public.leave_types, public.deed_templates, public.employee_deeds to authenticated;
-- the monthly value of a facility is pay information
grant select (id, client_id, employee_id, kind, description, from_date, to_date, active, created_by, created_at, updated_by, updated_at) on public.employee_benefits to authenticated;

-- ---------- storage: private bucket 'photos', prefixes EMP/<loc>/ (portrait) and EMPDOC/<loc>/ (documents). The old photos_* policies stay; policies are OR-ed. ----------
create or replace function public._emp_photo_ok(p_name text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and split_part(p_name, '/', 2) ~ '^[0-9]+$' and case split_part(p_name, '/', 1)
    when 'EMP' then public._loc_ok(split_part(p_name, '/', 2)::int, 'employee_manage')
                    or (p_action = 'view' and public.can_loc(split_part(p_name, '/', 2)::int) and public.has_grant('employee_view', split_part(p_name, '/', 2)::int))
    when 'EMPDOC' then public._loc_ok(split_part(p_name, '/', 2)::int, 'employee_manage')
    else false end;
$$;
do $$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists emp_photos_insert on storage.objects';
    execute 'create policy emp_photos_insert on storage.objects for insert to authenticated with check (bucket_id = ''photos'' and public._emp_photo_ok(name, ''enter''))';
    execute 'drop policy if exists emp_photos_read on storage.objects';
    execute 'create policy emp_photos_read on storage.objects for select to authenticated using (bucket_id = ''photos'' and public._emp_photo_ok(name, ''view''))';
  end if;
end $$;

-- ---------- small pure helpers ----------
create or replace function public._e_txt(d jsonb, k text, n int default 200) returns text language plpgsql immutable as $$
declare v text := nullif(btrim(d ->> k), '');
begin if v is not null and char_length(v) > n then raise exception 'too_long: %', k; end if; return v; end $$;
create or replace function public._e_date(d jsonb, k text) returns date language plpgsql immutable as $$
begin return nullif(btrim(d ->> k), '')::date; exception when others then raise exception 'bad_date: %', k; end $$;
create or replace function public._e_num(d jsonb, k text, lo numeric, hi numeric) returns numeric language plpgsql immutable as $$
declare v numeric;
begin
  begin v := nullif(btrim(d ->> k), '')::numeric; exception when others then raise exception 'bad_number: %', k; end;
  if v is not null and not (v between lo and hi) then raise exception 'bad_number: %', k; end if;
  return v;
end $$;
create or replace function public._e_nid(p text) returns text language plpgsql immutable as $$
declare v text;
begin
  if nullif(btrim(p), '') is null then return null; end if;
  v := regexp_replace(translate(p, '০১২৩৪৫৬৭৮৯', '0123456789'), '[^0-9]', '', 'g');
  if v !~ '^([0-9]{10}|[0-9]{13}|[0-9]{17})$' then raise exception 'bad_nid'; end if;
  return v;
end $$;
create or replace function public._emp_gate() returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('employees_module_on') then raise exception 'module_off'; end if;
end $$;
create or replace function public._dhaka_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;

-- ---------- employee_save: create a draft / change fields (partial: only the keys present in p_data change) ----------
create or replace function public.employee_save(p_id uuid, p_client uuid, p_data jsonb, p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb := coalesce(p_data, '{}'); e public.employees; v_old_loc int; v_today date := public._dhaka_today(); v_warn jsonb := '{}'; v_dup jsonb; v_no text; v_new boolean := (p_id is null);
begin
  perform public._emp_gate();
  if jsonb_typeof(d) <> 'object' then raise exception 'bad_data'; end if;
  if v_new then
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into e from public.employees where client_id = p_client;
      if found then
        if not public._emp_ok(e.id, array['employee_manage']) and not (e.created_by = auth.uid()) then raise exception 'not allowed'; end if;
        return jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'status', e.status, 'repeat', true);
      end if;
    end if;
    e.id := gen_random_uuid(); e.client_id := p_client; e.status := 'draft'; e.employment_type := 'permanent'; e.status_date := v_today; e.created_by := auth.uid(); e.created_at := now();
  else
    select * into e from public.employees where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
    if e.status in ('discarded') then raise exception 'employee_discarded'; end if;
    v_old_loc := e.primary_location_id;
  end if;
  if d ? 'full_name_bn' then e.full_name_bn := public._e_txt(d, 'full_name_bn', 120); end if;
  if d ? 'full_name_en' then e.full_name_en := public._e_txt(d, 'full_name_en', 120); end if;
  if d ? 'nickname' then e.nickname := public._e_txt(d, 'nickname', 60); end if;
  if d ? 'gender' then e.gender := public._e_txt(d, 'gender', 10); end if;
  if d ? 'date_of_birth' then e.date_of_birth := public._e_date(d, 'date_of_birth'); end if;
  if d ? 'blood_group' then e.blood_group := public._e_txt(d, 'blood_group', 3); end if;
  if d ? 'nid_no' then e.nid_no := public._e_nid(d ->> 'nid_no'); end if;
  if d ? 'mobile' then e.mobile := case when public._e_txt(d, 'mobile', 30) is null then null else public.norm_mobile(d ->> 'mobile') end; end if;
  if d ? 'email' then e.email := lower(public._e_txt(d, 'email', 120)); end if;
  if d ? 'present_address' then e.present_address := public._e_txt(d, 'present_address', 400); end if;
  if d ? 'permanent_address' then e.permanent_address := public._e_txt(d, 'permanent_address', 400); end if;
  if d ? 'emergency_name' then e.emergency_name := public._e_txt(d, 'emergency_name', 120); end if;
  if d ? 'emergency_relation' then e.emergency_relation := public._e_txt(d, 'emergency_relation', 60); end if;
  if d ? 'emergency_mobile' then e.emergency_mobile := case when public._e_txt(d, 'emergency_mobile', 30) is null then null else public.norm_mobile(d ->> 'emergency_mobile') end; end if;
  if d ? 'marital_status' then e.marital_status := public._e_txt(d, 'marital_status', 10); end if;
  if d ? 'education' then e.education := public._e_txt(d, 'education', 300); end if;
  if d ? 'joining_date' then e.joining_date := public._e_date(d, 'joining_date'); end if;
  if d ? 'probation_end' then e.probation_end := public._e_date(d, 'probation_end'); end if;
  if d ? 'designation' then e.designation := public._e_txt(d, 'designation', 80); end if;
  if d ? 'department' then e.department := public._e_txt(d, 'department', 80); end if;
  if d ? 'primary_location_id' then e.primary_location_id := public._e_num(d, 'primary_location_id', 1, 100000)::int; end if;
  if d ? 'primary_role_code' then e.primary_role_code := public._e_txt(d, 'primary_role_code', 41); end if;
  if d ? 'employment_type' then e.employment_type := coalesce(public._e_txt(d, 'employment_type', 12), 'permanent'); end if;
  if d ? 'device_user_id' then e.device_user_id := public._e_txt(d, 'device_user_id', 40); end if;
  if d ? 'notes' then e.notes := public._e_txt(d, 'notes', 1000); end if;
  -- checks
  if e.full_name_bn is null then raise exception 'name_required'; end if;
  if e.primary_location_id is null then raise exception 'location_required'; end if;
  if not exists (select 1 from public.locations l where l.id = e.primary_location_id) then raise exception 'bad_location'; end if;
  if e.gender is not null and e.gender not in ('male', 'female', 'other') then raise exception 'bad_gender'; end if;
  if e.blood_group is not null and e.blood_group not in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-') then raise exception 'bad_blood_group'; end if;
  if e.marital_status is not null and e.marital_status not in ('single', 'married', 'divorced', 'widowed') then raise exception 'bad_marital_status'; end if;
  if e.employment_type not in ('permanent', 'contract', 'daily', 'part_time', 'trainee') then raise exception 'bad_employment_type'; end if;
  if e.email is not null and e.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'bad_email'; end if;
  if e.date_of_birth is not null and not (e.date_of_birth between date '1930-01-01' and v_today - 10 * 365) then raise exception 'bad_date: date_of_birth'; end if;
  if e.joining_date is not null and not (e.joining_date between date '1990-01-01' and v_today + 90) then raise exception 'bad_date: joining_date'; end if;
  if e.probation_end is not null and (e.joining_date is null or e.probation_end < e.joining_date or e.probation_end > e.joining_date + 1100) then raise exception 'bad_date: probation_end'; end if;
  if e.primary_role_code is not null and not exists (select 1 from public.staff_roles r where r.code = e.primary_role_code and r.active) then raise exception 'bad_role'; end if;
  if (v_new or e.primary_location_id is distinct from v_old_loc) and not public._loc_ok(e.primary_location_id, 'employee_manage') then raise exception 'not allowed'; end if;
  -- duplicates: NID is always refused (one person, one NID); mobile follows the rule employee_mobile_unique
  if e.nid_no is not null and exists (select 1 from public.employees x where x.nid_no = e.nid_no and x.id <> e.id) then raise exception 'duplicate_nid'; end if;
  if e.device_user_id is not null and exists (select 1 from public.employees x where x.device_user_id = e.device_user_id and x.id <> e.id) then raise exception 'duplicate_device_id'; end if;
  if e.mobile is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'employee_no', x.employee_no, 'name', x.full_name_bn)), '[]') into v_dup
      from public.employees x where x.mobile = e.mobile and x.id <> e.id and x.status <> 'discarded';
    if jsonb_array_length(v_dup) > 0 then
      if public.rule_on('employee_mobile_unique') then raise exception 'duplicate_mobile'; end if;
      v_warn := v_warn || jsonb_build_object('mobile', v_dup);
    end if;
  end if;
  if p_dry then return jsonb_build_object('dry', true, 'ok', true, 'warnings', v_warn); end if;
  if v_new then
    insert into public.employees (id, client_id, full_name_bn, full_name_en, nickname, gender, date_of_birth, blood_group, nid_no, mobile, email, present_address, permanent_address,
        emergency_name, emergency_relation, emergency_mobile, marital_status, education, joining_date, probation_end, designation, department, primary_location_id, primary_role_code,
        employment_type, status, status_date, device_user_id, notes, created_by, created_at, updated_by, updated_at)
      values (e.id, e.client_id, e.full_name_bn, e.full_name_en, e.nickname, e.gender, e.date_of_birth, e.blood_group, e.nid_no, e.mobile, e.email, e.present_address, e.permanent_address,
        e.emergency_name, e.emergency_relation, e.emergency_mobile, e.marital_status, e.education, e.joining_date, e.probation_end, e.designation, e.department, e.primary_location_id, e.primary_role_code,
        e.employment_type, 'draft', v_today, e.device_user_id, e.notes, auth.uid(), now(), auth.uid(), now());
  else
    update public.employees set full_name_bn = e.full_name_bn, full_name_en = e.full_name_en, nickname = e.nickname, gender = e.gender, date_of_birth = e.date_of_birth, blood_group = e.blood_group,
        nid_no = e.nid_no, mobile = e.mobile, email = e.email, present_address = e.present_address, permanent_address = e.permanent_address, emergency_name = e.emergency_name,
        emergency_relation = e.emergency_relation, emergency_mobile = e.emergency_mobile, marital_status = e.marital_status, education = e.education, joining_date = e.joining_date,
        probation_end = e.probation_end, designation = e.designation, department = e.department, primary_location_id = e.primary_location_id, primary_role_code = e.primary_role_code,
        employment_type = e.employment_type, device_user_id = e.device_user_id, notes = e.notes, updated_by = auth.uid(), updated_at = now()
      where id = e.id;
  end if;
  select employee_no into v_no from public.employees where id = e.id;
  return jsonb_build_object('id', e.id, 'employee_no', v_no, 'status', (select status from public.employees where id = e.id), 'warnings', v_warn);
end $$;

-- finish the wizard: draft -> active (gets the number E-0001..)
create or replace function public.employee_submit(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_today date := public._dhaka_today();
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if e.status <> 'draft' then return jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'status', e.status, 'repeat', true); end if;
  if e.joining_date is null then raise exception 'joining_date_required'; end if;
  if nullif(btrim(coalesce(e.designation, '')), '') is null then raise exception 'designation_required'; end if;
  update public.employees set status = 'active', status_date = v_today, updated_by = auth.uid(), updated_at = now() where id = e.id returning * into e;
  insert into public.employee_status_log (employee_id, from_status, to_status, status_date, reason, by) values (e.id, 'draft', 'active', v_today, 'registered', auth.uid());
  return jsonb_build_object('id', e.id, 'employee_no', e.employee_no, 'status', e.status);
end $$;

create or replace function public.employee_discard(p_id uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (public._emp_ok(e.id, array['employee_manage']) or e.created_by = auth.uid()) then raise exception 'not allowed'; end if;
  if e.status <> 'draft' then raise exception 'not_a_draft'; end if;
  update public.employees set status = 'discarded', status_date = public._dhaka_today(), status_reason = left(btrim(coalesce(p_reason, '')), 300), updated_by = auth.uid(), updated_at = now() where id = e.id;
  insert into public.employee_status_log (employee_id, from_status, to_status, status_date, reason, by) values (e.id, 'draft', 'discarded', public._dhaka_today(), left(btrim(coalesce(p_reason, '')), 300), auth.uid());
  return jsonb_build_object('id', e.id, 'status', 'discarded');
end $$;

-- who else looks the same? (wizard warnings while typing); needs employee_manage somewhere
create or replace function public.employee_dup_check(p_nid text, p_mobile text, p_exclude uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_nid text; v_mob text; r_nid jsonb := '[]'; r_mob jsonb := '[]';
begin
  if not public._emp_any(array['employee_manage']) then raise exception 'not allowed'; end if;
  begin v_nid := public._e_nid(p_nid); exception when others then v_nid := null; end;
  begin v_mob := case when nullif(btrim(p_mobile), '') is null then null else public.norm_mobile(p_mobile) end; exception when others then v_mob := null; end;
  if v_nid is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'employee_no', x.employee_no, 'name', x.full_name_bn, 'status', x.status)), '[]') into r_nid
      from public.employees x where x.nid_no = v_nid and x.id is distinct from p_exclude and x.status <> 'discarded';
  end if;
  if v_mob is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'employee_no', x.employee_no, 'name', x.full_name_bn, 'status', x.status)), '[]') into r_mob
      from public.employees x where x.mobile = v_mob and x.id is distinct from p_exclude and x.status <> 'discarded';
  end if;
  return jsonb_build_object('nid', r_nid, 'mobile', r_mob, 'mobile_blocks', public.rule_on('employee_mobile_unique'));
end $$;

-- status changes (history kept). Leaving (resigned / terminated / retired) needs a reason and ends the person's active deeds. Coming back is owner only.
create or replace function public.employee_status_set(p_id uuid, p_status text, p_date date, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; v_today date := public._dhaka_today(); v_reason text := nullif(left(btrim(coalesce(p_reason, '')), 300), '');
begin
  perform public._emp_gate();
  if p_status not in ('active', 'on_leave', 'resigned', 'terminated', 'retired') then raise exception 'bad_status'; end if;
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if e.status in ('draft', 'discarded') then raise exception 'not_registered_yet'; end if;
  if e.status = p_status then raise exception 'same_status'; end if;
  if p_date is null or not (p_date between v_today - 400 and v_today + 60) then raise exception 'bad_date'; end if;
  if p_status in ('resigned', 'terminated', 'retired', 'on_leave') and v_reason is null then raise exception 'reason_required'; end if;
  if e.status in ('resigned', 'terminated', 'retired') then
    if not public.is_owner() then raise exception 'owner_only'; end if;
    if v_reason is null then raise exception 'reason_required'; end if;
  end if;
  update public.employees set status = p_status, status_date = p_date, status_reason = v_reason, updated_by = auth.uid(), updated_at = now() where id = e.id;
  insert into public.employee_status_log (employee_id, from_status, to_status, status_date, reason, by) values (e.id, e.status, p_status, p_date, v_reason, auth.uid());
  if p_status in ('resigned', 'terminated', 'retired') then
    update public.employee_deeds set status = 'terminated', ended_by = auth.uid(), ended_at = now(), end_reason = 'employee_' || p_status where employee_id = e.id and status = 'active';
    update public.employee_deeds set status = 'terminated', ended_by = auth.uid(), ended_at = now(), end_reason = 'employee_' || p_status where employee_id = e.id and status = 'draft';
  end if;
  return jsonb_build_object('id', e.id, 'status', p_status);
end $$;

create or replace function public.employee_locations_set(p_id uuid, p_locs int[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l int;
begin
  perform public._emp_gate();
  if not public._emp_ok(p_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if coalesce(array_length(p_locs, 1), 0) > 30 then raise exception 'too_many'; end if;
  foreach l in array coalesce(p_locs, '{}') loop
    if not exists (select 1 from public.locations x where x.id = l) then raise exception 'bad_location'; end if;
    insert into public.employee_locations (employee_id, location_id, active, added_by) values (p_id, l, true, auth.uid())
      on conflict (employee_id, location_id) do update set active = true;
  end loop;
  update public.employee_locations set active = false where employee_id = p_id and active and not (location_id = any (coalesce(p_locs, '{}')));
  return jsonb_build_object('id', p_id, 'locations', coalesce(p_locs, '{}'));
end $$;

create or replace function public.employee_link_profile(p_id uuid, p_profile uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_profile is not null then
    if not exists (select 1 from public.profiles pr where pr.id = p_profile) then raise exception 'profile_not_found'; end if;
    if exists (select 1 from public.employees x where x.profile_id = p_profile and x.id <> e.id) then raise exception 'profile_already_linked'; end if;
  end if;
  update public.employees set profile_id = p_profile, updated_by = auth.uid(), updated_at = now() where id = e.id;
  return jsonb_build_object('id', e.id, 'profile_id', p_profile);
end $$;

create or replace function public.employee_set_photo(p_id uuid, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  perform public._emp_gate();
  select * into e from public.employees where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_path is not null and (p_path !~ '^EMP/[0-9]+/[A-Za-z0-9_.-]{1,120}$' or split_part(p_path, '/', 2)::int is distinct from e.primary_location_id) then raise exception 'bad_path'; end if;
  update public.employees set photo_path = p_path, updated_by = auth.uid(), updated_at = now() where id = e.id;
  return jsonb_build_object('id', e.id, 'photo_path', p_path);
end $$;

-- ---------- documents ----------
create or replace function public.employee_doc_add(p_id uuid, p_kind text, p_path text, p_note text, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.employees; r public.employee_documents;
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  select * into e from public.employees where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(e.id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_client is not null then select * into r from public.employee_documents where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'repeat', true); end if; end if;
  if p_kind not in ('nid', 'contract', 'cv', 'certificate', 'guarantor', 'photo', 'other') then raise exception 'bad_kind'; end if;
  if p_path is null or p_path !~ '^(EMP|EMPDOC)/[0-9]+/[A-Za-z0-9_.-]{1,120}$' then raise exception 'bad_path'; end if;
  if (p_kind = 'photo') <> (split_part(p_path, '/', 1) = 'EMP') then raise exception 'bad_path'; end if;
  if split_part(p_path, '/', 2)::int is distinct from e.primary_location_id then raise exception 'bad_path'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  insert into public.employee_documents (client_id, employee_id, kind, file_path, note, uploaded_by) values (p_client, e.id, p_kind, p_path, nullif(btrim(p_note), ''), auth.uid()) returning * into r;
  return jsonb_build_object('id', r.id);
end $$;
create or replace function public.employee_doc_void(p_doc bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_documents;
begin
  perform public._emp_gate();
  select * into r from public.employee_documents where id = p_doc for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  update public.employee_documents set void = true, void_by = auth.uid(), void_at = now(), void_reason = left(btrim(p_reason), 300) where id = r.id and not void;
  return jsonb_build_object('id', r.id, 'void', true);
end $$;

-- ---------- pay structure ----------
-- validated component list (array of {kind,name,amount|percent_of_basic,taxable}); duplicate names inside a kind are refused
create or replace function public._pay_clean(p_comps jsonb) returns jsonb language plpgsql immutable as $$
declare c jsonb; out_ jsonb := '[]'; k text; n text; a numeric; pc numeric; seen text[] := '{}';
begin
  if p_comps is null or jsonb_typeof(p_comps) = 'null' then return '[]'; end if;
  if jsonb_typeof(p_comps) <> 'array' or jsonb_array_length(p_comps) > 30 then raise exception 'bad_components'; end if;
  for c in select * from jsonb_array_elements(p_comps) loop
    if jsonb_typeof(c) <> 'object' then raise exception 'bad_components'; end if;
    k := c ->> 'kind'; n := nullif(btrim(c ->> 'name'), '');
    if k not in ('allowance', 'deduction') then raise exception 'bad_component_kind'; end if;
    if n is null or char_length(n) > 60 then raise exception 'bad_component_name'; end if;
    a := public._e_num(c, 'amount', 0, 1000000000000); pc := public._e_num(c, 'percent_of_basic', 0, 100);
    if (a is null) = (pc is null) then raise exception 'component_amount_or_percent: %', n; end if;
    if (k || ':' || lower(n)) = any (seen) then raise exception 'duplicate_component: %', n; end if;
    seen := seen || (k || ':' || lower(n));
    out_ := out_ || jsonb_build_array(jsonb_build_object('kind', k, 'name', n, 'amount', a, 'percent_of_basic', pc, 'taxable', coalesce((c ->> 'taxable')::boolean, false)));
  end loop;
  return out_;
end $$;
-- computed lines and totals from a basic + cleaned components
create or replace function public._pay_calc(p_basic numeric, p_comps jsonb) returns jsonb language plpgsql immutable as $$
declare c jsonb; lines jsonb := '[]'; v numeric; al numeric := 0; de numeric := 0;
begin
  for c in select * from jsonb_array_elements(coalesce(p_comps, '[]')) loop
    if coalesce((c ->> 'active')::boolean, true) is false then continue; end if;
    v := coalesce((c ->> 'amount')::numeric, round(p_basic * (c ->> 'percent_of_basic')::numeric / 100, 2));
    if c ->> 'kind' = 'allowance' then al := al + v; else de := de + v; end if;
    lines := lines || jsonb_build_array(c || jsonb_build_object('calc', v));
  end loop;
  return jsonb_build_object('components', lines, 'allowances', al, 'deductions', de, 'gross', round(p_basic + al, 2), 'net', round(p_basic + al - de, 2));
end $$;
create or replace function public._emp_pay_json(p_pay bigint) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.employee_pay; comps jsonb;
begin
  select * into p from public.employee_pay where id = p_pay;
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'kind', c.kind, 'name', c.name, 'amount', c.amount, 'percent_of_basic', c.percent_of_basic, 'taxable', c.taxable, 'active', c.active) order by c.id), '[]')
    into comps from public.employee_pay_components c where c.pay_id = p.id;
  return jsonb_build_object('pay_id', p.id, 'employee_id', p.employee_id, 'effective_from', p.effective_from, 'pay_basis', p.pay_basis, 'basic', p.basic, 'ot_rule', p.ot_rule, 'ot_value', p.ot_value,
    'ot_hours_basis', p.ot_hours_basis, 'bonus_rules', p.bonus_rules, 'note', p.note, 'created_at', p.created_at) || public._pay_calc(p.basic, comps);
end $$;
-- for server code (payroll): the pay version in force for a person on a date
create or replace function public._emp_pay_on(p_emp uuid, p_on date) returns public.employee_pay language sql stable security definer set search_path = public as $$
  select * from public.employee_pay where employee_id = p_emp and effective_from <= coalesce(p_on, public._dhaka_today()) order by effective_from desc, id desc limit 1;
$$;

create or replace function public.employee_pay_set(p_emp uuid, p_effective date, p_basis text, p_basic numeric, p_ot_rule text, p_ot_value numeric, p_bonus jsonb, p_components jsonb,
  p_note text, p_client uuid default null, p_dry boolean default false, p_ot_hours numeric default 8) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_today date := public._dhaka_today(); v_comps jsonb; v_calc jsonb; r public.employee_pay; b jsonb; v_bonus jsonb := '[]'; c jsonb; v_id bigint; v_stat text;
begin
  perform public._emp_gate();
  if not public._emp_ok(p_emp, array['salary_manage']) then raise exception 'not allowed'; end if;
  select status into v_stat from public.employees where id = p_emp;
  if v_stat is null or v_stat = 'discarded' then raise exception 'not_found'; end if;
  if not p_dry then
    perform public._client_lock(p_client);
    if p_client is not null then select * into r from public.employee_pay where client_id = p_client; if found then return public._emp_pay_json(r.id) || jsonb_build_object('repeat', true); end if; end if;
  end if;
  if p_effective is null or not (p_effective between v_today - 1830 and v_today + 366) then raise exception 'bad_date'; end if;
  if p_basis not in ('monthly', 'daily', 'hourly') then raise exception 'bad_basis'; end if;
  if p_basic is null or not (p_basic > 0 and p_basic <= 1000000000000) then raise exception 'bad_amount'; end if;
  if p_ot_rule not in ('none', 'rate_per_hour', 'multiple_of_hourly') then raise exception 'bad_ot_rule'; end if;
  if p_ot_rule = 'none' then if p_ot_value is not null then raise exception 'bad_ot_value'; end if;
  elsif p_ot_value is null or not (p_ot_value > 0 and p_ot_value <= 1000000) or (p_ot_rule = 'multiple_of_hourly' and not (p_ot_value between 1 and 5)) then raise exception 'bad_ot_value'; end if;
  if p_ot_hours is null or not (p_ot_hours between 1 and 24) then raise exception 'bad_ot_hours'; end if;
  if char_length(coalesce(p_note, '')) > 500 then raise exception 'too_long: note'; end if;
  if p_bonus is not null and jsonb_typeof(p_bonus) <> 'null' then
    if jsonb_typeof(p_bonus) <> 'array' or jsonb_array_length(p_bonus) > 10 then raise exception 'bad_bonus'; end if;
    for b in select * from jsonb_array_elements(p_bonus) loop
      if jsonb_typeof(b) <> 'object' or nullif(btrim(b ->> 'name'), '') is null or char_length(b ->> 'name') > 60 then raise exception 'bad_bonus'; end if;
      v_bonus := v_bonus || jsonb_build_array(jsonb_build_object('name', btrim(b ->> 'name'), 'months_of_basic', public._e_num(b, 'months_of_basic', 0, 24), 'min_service_months', coalesce(public._e_num(b, 'min_service_months', 0, 600), 0)));
      if (v_bonus -> (jsonb_array_length(v_bonus) - 1) ->> 'months_of_basic') is null then raise exception 'bad_bonus'; end if;
    end loop;
  end if;
  v_comps := public._pay_clean(p_components);
  v_calc := public._pay_calc(p_basic, v_comps);
  if (v_calc ->> 'net')::numeric < 0 then raise exception 'deductions_exceed_gross'; end if;
  if p_dry then
    return jsonb_build_object('dry', true, 'effective_from', p_effective, 'pay_basis', p_basis, 'basic', p_basic, 'ot_rule', p_ot_rule, 'ot_value', p_ot_value, 'ot_hours_basis', p_ot_hours, 'bonus_rules', v_bonus) || v_calc;
  end if;
  insert into public.employee_pay (client_id, employee_id, effective_from, pay_basis, basic, ot_rule, ot_value, ot_hours_basis, bonus_rules, note, created_by)
    values (p_client, p_emp, p_effective, p_basis, round(p_basic, 2), p_ot_rule, p_ot_value, p_ot_hours, v_bonus, nullif(btrim(p_note), ''), auth.uid()) returning id into v_id;
  for c in select * from jsonb_array_elements(v_comps) loop
    insert into public.employee_pay_components (pay_id, kind, name, amount, percent_of_basic, taxable)
      values (v_id, c ->> 'kind', c ->> 'name', (c ->> 'amount')::numeric, (c ->> 'percent_of_basic')::numeric, (c ->> 'taxable')::boolean);
  end loop;
  return public._emp_pay_json(v_id);
end $$;

create or replace function public.employee_pay_current(p_emp uuid, p_on date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.employee_pay;
begin
  if not public._emp_ok(p_emp, array['salary_view']) then raise exception 'not allowed'; end if;
  select * into r from public._emp_pay_on(p_emp, p_on);
  if r.id is null then return null; end if;
  return public._emp_pay_json(r.id);
end $$;
create or replace function public.employee_pay_history(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._emp_ok(p_emp, array['salary_view']) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(public._emp_pay_json(p.id) order by p.effective_from desc, p.id desc) from public.employee_pay p where p.employee_id = p_emp), '[]');
end $$;

create or replace function public.employee_pay_account_set(p_emp uuid, p_bank text, p_wallet text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_w text := nullif(btrim(coalesce(p_wallet, '')), '');
begin
  perform public._emp_gate();
  if not public._emp_ok(p_emp, array['salary_manage']) then raise exception 'not allowed'; end if;
  if char_length(coalesce(p_bank, '')) > 120 then raise exception 'too_long: bank_account'; end if;
  if v_w is not null then v_w := public.norm_mobile(v_w); end if;
  update public.employees set bank_account = nullif(btrim(coalesce(p_bank, '')), ''), mobile_wallet = v_w, updated_by = auth.uid(), updated_at = now() where id = p_emp;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_emp);
end $$;
create or replace function public.employee_pay_account_get(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._emp_ok(p_emp, array['salary_view']) then raise exception 'not allowed'; end if;
  return (select jsonb_build_object('bank_account', e.bank_account, 'mobile_wallet', e.mobile_wallet) from public.employees e where e.id = p_emp);
end $$;

-- ---------- leave entitlements, benefits ----------
create or replace function public.leave_entitlement_set(p_emp uuid, p_type text, p_days numeric) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._emp_gate();
  if not public._emp_ok(p_emp, array['employee_manage']) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.leave_types t where t.code = p_type and t.active) then raise exception 'bad_leave_type'; end if;
  if p_days is null or not (p_days between 0 and 366) then raise exception 'bad_days'; end if;
  insert into public.employee_leave_entitlements (employee_id, leave_type, days_per_year, updated_by) values (p_emp, p_type, p_days, auth.uid())
    on conflict (employee_id, leave_type) do update set days_per_year = excluded.days_per_year, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('employee_id', p_emp, 'leave_type', p_type, 'days_per_year', p_days);
end $$;

create or replace function public.employee_benefit_save(p_id bigint, p_client uuid, p_emp uuid, p_kind text, p_desc text, p_value numeric, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefits; v_today date := public._dhaka_today();
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  if p_id is not null then select * into r from public.employee_benefits where id = p_id for update; if not found then raise exception 'not_found'; end if; end if;
  if not public._emp_ok(coalesce(r.employee_id, p_emp), array['employee_manage', 'salary_manage']) then raise exception 'not allowed'; end if;
  if p_value is not null and not public._emp_ok(coalesce(r.employee_id, p_emp), array['salary_manage']) then raise exception 'not allowed'; end if;
  if p_kind not in ('meal', 'uniform', 'accommodation', 'transport', 'phone', 'insurance', 'other') then raise exception 'bad_kind'; end if;
  if p_value is not null and not (p_value between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  if p_from is null or not (p_from between v_today - 1830 and v_today + 366) then raise exception 'bad_date'; end if;
  if p_to is not null and p_to < p_from then raise exception 'bad_date'; end if;
  if char_length(coalesce(p_desc, '')) > 300 then raise exception 'too_long: description'; end if;
  if p_id is null then
    if p_client is not null then select * into r from public.employee_benefits where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'repeat', true); end if; end if;
    if not exists (select 1 from public.employees where id = p_emp) then raise exception 'not_found'; end if;
    insert into public.employee_benefits (client_id, employee_id, kind, description, value_per_month, from_date, to_date, created_by, updated_by)
      values (p_client, p_emp, p_kind, nullif(btrim(p_desc), ''), p_value, p_from, p_to, auth.uid(), auth.uid()) returning * into r;
  else
    update public.employee_benefits set kind = p_kind, description = nullif(btrim(p_desc), ''), value_per_month = case when p_value is not null then p_value else value_per_month end,
      from_date = p_from, to_date = p_to, updated_by = auth.uid(), updated_at = now() where id = r.id returning * into r;
  end if;
  return jsonb_build_object('id', r.id);
end $$;
create or replace function public.employee_benefit_end(p_id bigint, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefits;
begin
  perform public._emp_gate();
  select * into r from public.employee_benefits where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if p_to is null or p_to < r.from_date or p_to > public._dhaka_today() + 366 then raise exception 'bad_date'; end if;
  update public.employee_benefits set to_date = p_to, active = false, updated_by = auth.uid(), updated_at = now() where id = r.id;
  return jsonb_build_object('id', r.id, 'to_date', p_to);
end $$;
create or replace function public.employee_benefits_list(p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_sal boolean;
begin
  if not public._emp_ok(p_emp, array['employee_view', 'employee_manage', 'salary_view'], true) then raise exception 'not allowed'; end if;
  v_sal := public._emp_ok(p_emp, array['salary_view']);
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'kind', b.kind, 'description', b.description, 'from_date', b.from_date, 'to_date', b.to_date, 'active', b.active,
           'value_per_month', case when v_sal then b.value_per_month end) order by b.from_date desc, b.id desc) from public.employee_benefits b where b.employee_id = p_emp), '[]');
end $$;

-- ---------- roles ----------
create or replace function public.staff_role_save(p_code text, p_name_bn text, p_name_en text, p_major boolean, p_description text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,40}$' then raise exception 'bad_code'; end if;
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null or char_length(p_name_bn) > 100 or char_length(coalesce(p_name_en, '')) > 100 or char_length(coalesce(p_description, '')) > 300 then raise exception 'bad_name'; end if;
  insert into public.staff_roles (code, name_bn, name_en, major, description, active, sort)
    values (p_code, btrim(p_name_bn), coalesce(nullif(btrim(p_name_en), ''), btrim(p_name_bn)), coalesce(p_major, false), nullif(btrim(p_description), ''), coalesce(p_active, true), 100)
    on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en, major = excluded.major, description = excluded.description, active = excluded.active;
  return jsonb_build_object('code', p_code);
end $$;

-- ---------- deeds ----------
create or replace function public._clauses_clean(p_cl jsonb) returns jsonb language plpgsql immutable as $$
declare c jsonb; out_ jsonb := '[]'; i int := 0; k text; bn text; en text; v text; u text;
begin
  if p_cl is null or jsonb_typeof(p_cl) = 'null' then return '[]'; end if;
  if jsonb_typeof(p_cl) <> 'array' or jsonb_array_length(p_cl) > 60 then raise exception 'bad_clauses'; end if;
  for c in select * from jsonb_array_elements(p_cl) loop
    if jsonb_typeof(c) <> 'object' then raise exception 'bad_clauses'; end if;
    i := i + 1; k := coalesce(nullif(c ->> 'kind', ''), 'text'); bn := nullif(btrim(c ->> 'text_bn'), ''); en := nullif(btrim(c ->> 'text_en'), '');
    v := nullif(btrim(c ->> 'value'), ''); u := nullif(btrim(c ->> 'unit'), '');
    if k not in ('rule', 'amount', 'duration', 'text') then raise exception 'bad_clause_kind'; end if;
    if bn is null and en is null then raise exception 'clause_text_required'; end if;
    if char_length(coalesce(bn, '')) > 2000 or char_length(coalesce(en, '')) > 2000 or char_length(coalesce(v, '')) > 200 or char_length(coalesce(u, '')) > 30 then raise exception 'too_long: clause'; end if;
    if k in ('amount', 'duration') and v is not null and v !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'bad_clause_value'; end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('no', i, 'text_bn', bn, 'text_en', en, 'kind', k, 'value', v, 'unit', u));
  end loop;
  return out_;
end $$;

create or replace function public.deed_template_save(p_family bigint, p_role text, p_title_bn text, p_title_en text, p_clauses jsonb, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cl jsonb; last_ public.deed_templates; r public.deed_templates; v_ver int := 1; v_fam bigint := p_family;
begin
  perform public._emp_gate();
  if not public._emp_any(array['deed_manage']) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then select * into r from public.deed_templates where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'family_id', r.family_id, 'version', r.version, 'repeat', true); end if; end if;
  if not exists (select 1 from public.staff_roles s where s.code = p_role and s.active) then raise exception 'bad_role'; end if;
  if nullif(btrim(coalesce(p_title_bn, '')), '') is null or char_length(p_title_bn) > 200 or char_length(coalesce(p_title_en, '')) > 200 then raise exception 'bad_title'; end if;
  v_cl := public._clauses_clean(p_clauses);
  if p_family is not null then
    perform pg_advisory_xact_lock(hashtextextended('bos41:tpl:' || p_family::text, 0));
    select * into last_ from public.deed_templates where family_id = p_family order by version desc limit 1;
    if not found then raise exception 'not_found'; end if;
    if last_.role_code = p_role and last_.title_bn = btrim(p_title_bn) and coalesce(last_.title_en, '') = coalesce(nullif(btrim(p_title_en), ''), '') and last_.clauses = v_cl and last_.active then
      return jsonb_build_object('id', last_.id, 'family_id', last_.family_id, 'version', last_.version, 'unchanged', true);
    end if;
    v_ver := last_.version + 1;
    update public.deed_templates set active = false where family_id = p_family and active;
  end if;
  if v_fam is null then v_fam := nextval(pg_get_serial_sequence('public.deed_templates', 'id')); end if;     -- a new template is the first member of its own family
  insert into public.deed_templates (id, client_id, family_id, version, role_code, title_bn, title_en, clauses, created_by)
    values (case when p_family is null then v_fam else nextval(pg_get_serial_sequence('public.deed_templates', 'id')) end, p_client, v_fam, v_ver, p_role, btrim(p_title_bn), nullif(btrim(p_title_en), ''), v_cl, auth.uid())
    returning * into r;
  return jsonb_build_object('id', r.id, 'family_id', r.family_id, 'version', r.version);
end $$;

-- retire / bring back the newest version of a template family (older versions stay as they were)
create or replace function public.deed_template_retire(p_family bigint, p_active boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare last_ public.deed_templates;
begin
  perform public._emp_gate();
  if not public._emp_any(array['deed_manage']) then raise exception 'not allowed'; end if;
  select * into last_ from public.deed_templates where family_id = p_family order by version desc limit 1;
  if not found then raise exception 'not_found'; end if;
  update public.deed_templates set active = coalesce(p_active, false) where id = last_.id;
  return jsonb_build_object('family_id', p_family, 'active', coalesce(p_active, false));
end $$;

-- create / change a DRAFT deed (copies the clauses of a template when none are given). Several fields are optional.
create or replace function public.deed_save(p_id bigint, p_client uuid, p_emp uuid, p_template bigint, p_role text, p_title text, p_clauses jsonb, p_start date, p_end date,
  p_probation int, p_notice int, p_deposit numeric, p_gname text, p_gmobile text, p_gnid text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds; t public.deed_templates; v_cl jsonb; v_emp uuid := p_emp; v_st text; v_title text := nullif(btrim(coalesce(p_title, '')), ''); v_today date := public._dhaka_today();
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  if p_id is not null then
    select * into r from public.employee_deeds where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    if r.status <> 'draft' then raise exception 'deed_not_draft'; end if;
    v_emp := r.employee_id;
  elsif p_client is not null then
    select * into r from public.employee_deeds where client_id = p_client;
    if found then
      if not public._emp_ok(r.employee_id, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
      return jsonb_build_object('id', r.id, 'repeat', true);
    end if;
  end if;
  if not public._emp_ok(v_emp, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  select status into v_st from public.employees where id = v_emp;
  if v_st is null then raise exception 'not_found'; end if;
  if v_st in ('resigned', 'terminated', 'retired', 'discarded') then raise exception 'employee_not_working'; end if;
  if not exists (select 1 from public.staff_roles s where s.code = p_role and s.active) then raise exception 'bad_role'; end if;
  if p_template is not null then
    select * into t from public.deed_templates where id = p_template;
    if not found then raise exception 'template_not_found'; end if;
    if t.role_code <> p_role then raise exception 'template_role_mismatch'; end if;
  end if;
  v_cl := case when p_clauses is not null and jsonb_typeof(p_clauses) <> 'null' then public._clauses_clean(p_clauses) when t.id is not null then public._clauses_clean(t.clauses) else '[]' end;
  v_title := coalesce(v_title, t.title_bn);
  if v_title is null or char_length(v_title) > 200 then raise exception 'bad_title'; end if;
  if p_start is not null and not (p_start between date '1990-01-01' and v_today + 366) then raise exception 'bad_date'; end if;
  if p_end is not null and (p_start is null or p_end < p_start or p_end > p_start + 3660) then raise exception 'bad_date'; end if;
  if p_probation is not null and not (p_probation between 0 and 365) then raise exception 'bad_days'; end if;
  if p_notice is not null and not (p_notice between 0 and 365) then raise exception 'bad_days'; end if;
  if p_deposit is not null and not (p_deposit between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  if char_length(coalesce(p_gname, '')) > 120 then raise exception 'too_long: guarantor'; end if;
  if p_id is null then
    insert into public.employee_deeds (client_id, employee_id, template_id, role_code, title, clauses, start_date, end_date, probation_days, notice_days, security_deposit,
        guarantor_name, guarantor_mobile, guarantor_nid, created_by)
      values (p_client, v_emp, p_template, p_role, v_title, v_cl, p_start, p_end, p_probation, p_notice, p_deposit, nullif(btrim(p_gname), ''),
        case when nullif(btrim(coalesce(p_gmobile, '')), '') is null then null else public.norm_mobile(p_gmobile) end, public._e_nid(p_gnid), auth.uid()) returning * into r;
  else
    update public.employee_deeds set template_id = p_template, role_code = p_role, title = v_title, clauses = v_cl, start_date = p_start, end_date = p_end, probation_days = p_probation,
        notice_days = p_notice, security_deposit = p_deposit, guarantor_name = nullif(btrim(p_gname), ''),
        guarantor_mobile = case when nullif(btrim(coalesce(p_gmobile, '')), '') is null then null else public.norm_mobile(p_gmobile) end, guarantor_nid = public._e_nid(p_gnid)
      where id = r.id returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'status', r.status, 'revision_no', r.revision_no);
end $$;

-- change an ACTIVE deed = copy it into a new draft revision (revision_no + 1). Activating the revision supersedes the old deed.
create or replace function public.deed_revise(p_id bigint, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.employee_deeds; r public.employee_deeds;
begin
  perform public._emp_gate();
  perform public._client_lock(p_client);
  select * into o from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(o.employee_id, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  if p_client is not null then select * into r from public.employee_deeds where client_id = p_client; if found then return jsonb_build_object('id', r.id, 'repeat', true); end if; end if;
  if o.status <> 'active' then raise exception 'deed_not_active'; end if;
  if exists (select 1 from public.employee_deeds x where x.supersedes_id = o.id and x.status = 'draft') then raise exception 'revision_already_open'; end if;
  insert into public.employee_deeds (client_id, employee_id, template_id, role_code, title, clauses, start_date, end_date, probation_days, notice_days, security_deposit,
      guarantor_name, guarantor_mobile, guarantor_nid, revision_no, supersedes_id, created_by)
    values (p_client, o.employee_id, o.template_id, o.role_code, o.title, o.clauses, o.start_date, o.end_date, o.probation_days, o.notice_days, o.security_deposit,
      o.guarantor_name, o.guarantor_mobile, o.guarantor_nid, o.revision_no + 1, o.id, auth.uid()) returning * into r;
  return jsonb_build_object('id', r.id, 'revision_no', r.revision_no, 'supersedes_id', o.id);
end $$;

create or replace function public.deed_activate(p_id bigint, p_signed_at date default null, p_signed_doc text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds; v_today date := public._dhaka_today(); v_emp_st text;
begin
  perform public._emp_gate();
  select * into r from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['deed_manage']) then raise exception 'not allowed'; end if;
  if r.status = 'active' then return jsonb_build_object('id', r.id, 'status', 'active', 'repeat', true); end if;
  if r.status <> 'draft' then raise exception 'deed_not_draft'; end if;
  select status into v_emp_st from public.employees where id = r.employee_id;
  if v_emp_st in ('resigned', 'terminated', 'retired', 'discarded') then raise exception 'employee_not_working'; end if;
  if r.start_date is null then raise exception 'start_date_required'; end if;
  if jsonb_array_length(r.clauses) = 0 then raise exception 'clauses_required'; end if;
  if p_signed_at is not null and not (p_signed_at between date '1990-01-01' and v_today + 1) then raise exception 'bad_date'; end if;
  if p_signed_doc is not null and p_signed_doc !~ '^EMPDOC/[0-9]+/[A-Za-z0-9_.-]{1,120}$' then raise exception 'bad_path'; end if;
  if exists (select 1 from public.employee_deeds x where x.employee_id = r.employee_id and x.role_code = r.role_code and x.status = 'active' and x.id is distinct from r.supersedes_id) then raise exception 'active_deed_exists'; end if;
  if r.supersedes_id is not null then
    update public.employee_deeds set status = 'superseded', ended_by = auth.uid(), ended_at = now(), end_reason = 'revised' where id = r.supersedes_id and status = 'active';
  end if;
  update public.employee_deeds set status = 'active', signed_at = p_signed_at, signed_doc_path = p_signed_doc, activated_by = auth.uid(), activated_at = now() where id = r.id returning * into r;
  return jsonb_build_object('id', r.id, 'status', r.status, 'revision_no', r.revision_no);
end $$;

create or replace function public.deed_attach_signed(p_id bigint, p_path text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds;
begin
  perform public._emp_gate();
  select * into r from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  if r.signed_doc_path is not null then raise exception 'already_attached'; end if;
  if p_path is null or p_path !~ '^EMPDOC/[0-9]+/[A-Za-z0-9_.-]{1,120}$' then raise exception 'bad_path'; end if;
  update public.employee_deeds set signed_doc_path = p_path where id = r.id;
  return jsonb_build_object('id', r.id);
end $$;

create or replace function public.deed_end(p_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_deeds;
begin
  perform public._emp_gate();
  select * into r from public.employee_deeds where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['deed_manage']) then raise exception 'not allowed'; end if;
  if r.status not in ('active', 'draft') then raise exception 'deed_not_active'; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  update public.employee_deeds set status = 'terminated', ended_by = auth.uid(), ended_at = now(), end_reason = btrim(p_reason) where id = r.id;
  return jsonb_build_object('id', r.id, 'status', 'terminated');
end $$;

-- mark active deeds whose end date has passed as expired (any employee_manage / deed_manage holder may run it; it only applies the calendar)
create or replace function public.deed_expire_due() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._emp_any(array['employee_manage', 'deed_manage']) then raise exception 'not allowed'; end if;
  update public.employee_deeds set status = 'expired', ended_by = auth.uid(), ended_at = now(), end_reason = 'end_date_passed' where status = 'active' and end_date < public._dhaka_today();
  get diagnostics n = row_count;
  return n;
end $$;

-- active deeds that end within p_days (null = the rule deed_expiry_warn_days) or already ended but not yet marked expired
create or replace function public.deeds_expiring(p_days int default null) returns table (deed_id bigint, employee_id uuid, employee_no text, full_name_bn text, role_code text, title text, end_date date, days_left int)
language plpgsql stable security definer set search_path = public as $$
declare v_days int := coalesce(p_days, public.rule_num('deed_expiry_warn_days')::int, 30); v_today date := public._dhaka_today();
begin
  if v_days < 0 or v_days > 3660 then raise exception 'bad_days'; end if;
  return query
    select d.id, d.employee_id, e.employee_no, e.full_name_bn, d.role_code, d.title, d.end_date, (d.end_date - v_today)::int
      from public.employee_deeds d join public.employees e on e.id = d.employee_id
     where d.status = 'active' and d.end_date is not null and d.end_date <= v_today + v_days and public._emp_ok(d.employee_id, array['employee_manage', 'deed_manage'])
     order by d.end_date, d.id;
end $$;

-- ---------- function grants: the browser calls the listed ones; helpers are closed to everybody but the definer ----------
do $$
declare p record;
begin
  for p in select oid::regprocedure as sig, proname from pg_proc where pronamespace = 'public'::regnamespace
           and (proname like 'employee\_%' escape '\' or proname like 'deed\_%' escape '\' or proname like 'deeds\_%' escape '\' or proname in ('staff_role_save', 'leave_entitlement_set', '_emp_ok', '_emp_any', '_loc_ok', '_emp_photo_ok')
                or proname in ('_e_txt', '_e_date', '_e_num', '_e_nid', '_emp_gate', '_dhaka_today', '_pay_clean', '_pay_calc', '_emp_pay_json', '_emp_pay_on', '_clauses_clean', '_emp_no_set',
                               '_append_only41', '_pay_comp_guard', '_deed_tpl_guard', '_deed_guard')) loop
    execute format('revoke all on function %s from public, anon', p.sig);
    if p.proname in ('_e_txt', '_e_date', '_e_num', '_e_nid', '_emp_gate', '_dhaka_today', '_pay_clean', '_pay_calc', '_emp_pay_json', '_emp_pay_on', '_clauses_clean', '_emp_no_set',
                     '_append_only41', '_pay_comp_guard', '_deed_tpl_guard', '_deed_guard') then
      execute format('revoke all on function %s from authenticated', p.sig);
    else
      execute format('grant execute on function %s to authenticated', p.sig);
    end if;
  end loop;
end $$;
