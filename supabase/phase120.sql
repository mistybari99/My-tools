-- Phase 120 (bos120) - PAY REQUESTS (package R1). Paste AFTER phase99 (needs phase 87 and the staff, payroll, purchase and notification phases). Paste-twice safe. Earlier phase files are not edited.
-- Purpose: nobody has to ask for salary, an advance or a supplier payment by word of mouth. A person writes a request in the app (amount, reason, needed-by date); ONE responsible
-- person decides it (approve on the date asked, approve on another date, or reject with a reason); on the pay date it shows in a due list; the payment is made by the EXISTING functions
-- (staff_advance_add, payroll_pay, pay_supplier) with the payment source chosen at that moment (cash, mobile banking, bank: never fixed), so the ledger entry is the same as today.
-- EVERY choice is a setting; every default keeps TODAY'S behaviour (nothing changes when the settings are left alone):
--   pay_requests_on               OFF   staff can send salary / advance requests
--   pay_requests_required         OFF   ("verbal request policy") salary and advance are paid only against an approved request; one exception with a reason is logged to the Exceptions list
--   pay_requests_required_kinds   both  which payments the policy covers: both | advance | salary
--   pay_request_approver_mode     owner who decides staff requests: owner | role | user  (+ pay_request_approver_role / pay_request_approver_user); the owner can always decide
--   pay_request_exception_mode    reason  how an unbacked payment can still be made: reason (the payer writes why) | owner (only the owner) | never
--   pay_request_max_per_month     blank = no limit   requests one staff member may send per month
--   pay_request_advance_ceiling   blank = no limit   open advances + open advance requests + this one may not pass this amount
--   party_requests_on / party_requests_required / party_request_approver_mode (same | owner | role | user) + _role / _user   the same for supplier payments
-- NO shared function is replaced and NO hook is needed: the "required" policy is a BEFORE INSERT trigger (a0_r1_gate_bi) on employee_advances, payroll_payments and supplier_payments, so every
-- path that pays (old screens, the due list, a W1-E approved request) meets it, and re-pasting an older phase cannot remove it. The trigger is inert while the settings are at the default.
-- The maker never decides or pays his own request (BUILD-RULES 8); the owner may do it only where the project already lets him approve his own entries (owner_self_approve, not in named mode).
-- Notifications: in-app rows in public.notifications (phase 46), aimed at one person. Test data only (test_*).

do $g$ begin
  if to_regprocedure('public._p87_present()') is null or to_regprocedure('public._m_grant_take(text,text,uuid,bigint,numeric,date,text)') is null
     or to_regprocedure('public._m_mode_of_kind(text)') is null then raise exception 'phase120 needs phase87 (and 80-86) first'; end if;
  if to_regprocedure('public.staff_advance_add(uuid,date,numeric,numeric,text,date,text,uuid)') is null or to_regprocedure('public.payroll_pay(bigint,bigint[],text,date,text,text,uuid,numeric)') is null
     or to_regprocedure('public.pay_supplier(uuid,integer,jsonb,uuid,text)') is null then raise exception 'phase120 needs the payroll (phase 42) and supplier payment (phase 10) functions'; end if;
  if to_regclass('public.notifications') is null or to_regclass('public.employees') is null or to_regclass('public.money_exceptions') is null then raise exception 'phase120 needs phases 46, 87 and the employee tables'; end if;
end $g$;

create or replace function public._p120_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- Exceptions list: one more kind (merged with the live list, same pattern as phase 94 / 99; every kind found is kept) ----------
create or replace function public._r1_exc_kinds_apply() returns jsonb language plpgsql security definer set search_path = public as $$
declare con text; def text; cur text[]; want text[];
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase120: the money_exceptions kind check was not found (phase87 missing?)'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  if cur is null then cur := string_to_array(substring(def from '\{([^}]*)\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase120: the money_exceptions kind check has an unknown shape: %', left(def, 120); end if;
  select array_agg(x order by x) into want from (select unnest(cur) x union select unnest(array['r1_unbacked_payment']::text[])) z;
  if cur = want and position('ARRAY[' in def) > 0 then return jsonb_build_object('changed', false, 'kinds', cardinality(want)); end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(want) x));
  return jsonb_build_object('changed', true, 'kinds', cardinality(want));
end $$;
select public._r1_exc_kinds_apply();

-- ---------- settings (rules). Every default = today. ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, v.module, v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lbn, v.lmix, v.len, v.hbn, v.hmix, v.hen, v.srt
  from (values
 ('pay_requests_on', 'people', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'স্টাফ অ্যাপে বেতন / অগ্রিম চাইতে পারবে', 'Staff Salary / Advance request পাঠাতে পারবে', 'Staff can ask for salary or an advance in the app',
   'বন্ধ থাকলে আগের মতোই। চালু হলে স্টাফ নিজের ফোন থেকে পরিমাণ, কারণ ও কবে লাগবে লিখে অনুরোধ পাঠায়।', 'Off = as today. On = a staff member sends an amount, a reason and the needed-by date from his own login.',
   'Off = as today. On = a staff member sends an amount, a reason and the needed-by date from his own login; one responsible person decides.', 1200),
 ('pay_requests_required', 'people', 'switch', 'false'::jsonb, null, null, null, null,
   'মুখের কথায় বেতন / অগ্রিম নয় (অনুমোদিত অনুরোধ ছাড়া পেমেন্ট নয়)', 'Verbal request policy: অনুমোদিত request ছাড়া payment নয়', 'Verbal request policy: pay salary and advance only against an approved request',
   'বন্ধ থাকলে আগের মতোই। চালু হলে অনুমোদিত অনুরোধ ছাড়া বেতন / অগ্রিম দেওয়া যাবে না। কারণ লিখে ব্যতিক্রম করা যায়; সেটি ব্যতিক্রম তালিকায় ওঠে।', 'Off = as today. On = refused unless an approved request backs it. One exception with a reason is possible and is written to the Exceptions list.',
   'Off = as today. On = a salary or advance payment to a staff member is refused unless an approved request backs it. One exception with a written reason is possible (see the exception setting) and is written to the Exceptions list. Also known as pay_requests_required / verbal request policy.', 1201),
 ('pay_requests_required_kinds', 'people', 'choice', '"both"'::jsonb, null, '["both","advance","salary"]'::jsonb, null, null,
   'কোন পেমেন্টে অনুরোধ লাগবে', 'Request লাগবে: salary / advance', 'Which payments need an approved request',
   'both = বেতন ও অগ্রিম, advance = শুধু অগ্রিম, salary = শুধু বেতন। শুধু উপরের নীতি চালু থাকলে কাজ করে।', 'both | advance | salary. Used only when the policy above is ON.',
   'both = salary and advance, advance = advance only, salary = salary only. Used only when the policy above is ON.', 1202),
 ('pay_request_approver_mode', 'people', 'choice', '"owner"'::jsonb, null, '["owner","role","user"]'::jsonb, null, null,
   'বেতন / অগ্রিমের অনুরোধ কে সিদ্ধান্ত দেবে', 'Staff request কে decide করবে', 'Who decides staff requests',
   'owner = মালিক, role = একটি ভূমিকা, user = একজন নির্দিষ্ট ব্যক্তি। মালিক সবসময় সিদ্ধান্ত দিতে পারেন। বদলাতে "অনুরোধের সিদ্ধান্তদাতা" পাতা ব্যবহার করুন।', 'owner | role | user. The owner can always decide. Change it on the pay-request settings page.',
   'owner | role | user. The owner can always decide. Change it on the pay-request settings page (one call, written to the change log).', 1203),
 ('pay_request_approver_role', 'people', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ভূমিকা', 'Approver role', 'Approver role (when the mode is role)', null, null, 'A role code. Set through the pay-request settings page.', 1204),
 ('pay_request_approver_user', 'people', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ব্যক্তি', 'Approver person', 'Approver person (when the mode is user)', null, null, 'A person id. Set through the pay-request settings page.', 1205),
 ('pay_request_exception_mode', 'people', 'choice', '"reason"'::jsonb, null, '["reason","owner","never"]'::jsonb, null, null,
   'অনুরোধ ছাড়া পেমেন্টের ব্যতিক্রম', 'Request ছাড়া payment: exception', 'Payment without an approved request: how an exception works',
   'reason = পেমেন্টকারী কারণ লিখে করতে পারে, owner = শুধু মালিক, never = একেবারে নয়। প্রতিটি ব্যবহার ব্যতিক্রম তালিকায় ওঠে।', 'reason = the payer writes why, owner = only the owner, never = no way past. Every use is on the Exceptions list.',
   'reason = the payer writes why (one payment, 30 minutes), owner = only the owner, never = no way past. Every use is on the Exceptions list. Used only when the policy is ON.', 1206),
 ('pay_request_max_per_month', 'people', 'number', null, 'requests', null, 1, 1000,
   'একজন স্টাফ মাসে সর্বোচ্চ কতটি অনুরোধ', 'Staff প্রতি মাসে max request', 'Most requests one staff member may send in a month',
   'ফাঁকা = সীমা নেই।', 'Blank = no limit.', 'Blank = no limit. Cancelled requests are not counted.', 1207),
 ('pay_request_advance_ceiling', 'people', 'number', null, 'Tk', null, 1, 1000000000,
   'অগ্রিমের সর্বোচ্চ সীমা (মোট বকেয়া অগ্রিম + খোলা অনুরোধ + এই অনুরোধ)', 'Advance ceiling (বকেয়া advance + খোলা request + এটি)', 'Advance ceiling for one person (open advances + open requests + this one)',
   'ফাঁকা = সীমা নেই।', 'Blank = no limit.', 'Blank = no limit. A request that would pass this total is refused when it is sent.', 1208),
 ('party_requests_on', 'purchase', 'switch', 'false'::jsonb, null, null, null, null,
   'সরবরাহকারীর পেমেন্টের অনুরোধ চালু', 'Supplier payment request চালু', 'Supplier payment requests',
   'বন্ধ থাকলে আগের মতোই। চালু হলে ক্রয় / স্টোর / যেকোনো স্টাফ সরবরাহকারীকে টাকা দেওয়ার অনুরোধ লিখতে পারে।', 'Off = as today. On = purchase, store or any staff can write a request to pay a supplier.',
   'Off = as today. On = purchase, store or any staff (or the supplier side, entered on their behalf) can write a request to pay a supplier.', 1220),
 ('party_requests_required', 'purchase', 'switch', 'false'::jsonb, null, null, null, null,
   'অনুমোদিত অনুরোধ ছাড়া সরবরাহকারীকে পেমেন্ট নয়', 'Approved request ছাড়া supplier payment নয়', 'Pay a supplier only against an approved request',
   'বন্ধ থাকলে আগের মতোই। বিলের সাথে দেওয়া পেমেন্ট এর আওতায় পড়ে না।', 'Off = as today. A payment made together with a purchase bill is not covered.',
   'Off = as today. On = the standalone supplier payment (pay_supplier) is refused unless an approved request backs it; the same exception setting applies. A payment made together with a purchase bill is not covered.', 1221),
 ('party_request_approver_mode', 'purchase', 'choice', '"same"'::jsonb, null, '["same","owner","role","user"]'::jsonb, null, null,
   'সরবরাহকারী পেমেন্টের অনুরোধ কে সিদ্ধান্ত দেবে', 'Supplier request কে decide করবে', 'Who decides supplier payment requests',
   'same = স্টাফ অনুরোধের মতোই।', 'same = the person chosen for staff requests.', 'same = the person chosen for staff requests; or owner | role | user.', 1222),
 ('party_request_approver_role', 'purchase', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ভূমিকা (সরবরাহকারী)', 'Approver role (supplier)', 'Approver role for supplier requests', null, null, 'A role code. Set through the pay-request settings page.', 1223),
 ('party_request_approver_user', 'purchase', 'text', null, null, null, null, null, 'সিদ্ধান্তদাতা ব্যক্তি (সরবরাহকারী)', 'Approver person (supplier)', 'Approver person for supplier requests', null, null, 'A person id. Set through the pay-request settings page.', 1224)
 ) v(key, module, kind, dv, unit, ch, mn, mx, lbn, lmix, len, hbn, hmix, hen, srt)
on conflict (key) do nothing;

-- ---------- tables ----------
create table if not exists public.pay_requests (
  id bigserial primary key,
  client_id uuid unique,
  kind text not null check (kind in ('salary', 'advance', 'supplier')),
  status text not null default 'received' check (status in ('received', 'approved', 'rejected', 'paid', 'cancelled')),
  requested_by uuid not null, requested_staff text, on_behalf boolean not null default false,
  employee_id uuid references public.employees(id),
  supplier_id uuid references public.suppliers(id),
  bill_id uuid references public.purchase_bills(id), bill_ref text check (bill_ref is null or length(bill_ref) <= 80),
  asked_by_name text check (asked_by_name is null or length(asked_by_name) <= 80),
  location_id int references public.locations(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000),
  reason text not null check (length(btrim(reason)) between 3 and 300),
  needed_by date not null,
  approved_amount numeric check (approved_amount is null or (approved_amount > 0 and approved_amount <= 1000000000)),
  pay_date date, date_changed boolean not null default false,
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text check (decision_note is null or length(decision_note) <= 300),
  paid_amount numeric not null default 0 check (paid_amount >= 0), paid_at timestamptz, paid_by uuid, paid_ref text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((kind = 'supplier' and supplier_id is not null and employee_id is null) or (kind in ('salary', 'advance') and employee_id is not null and supplier_id is null))
);
create index if not exists pay_requests_status on public.pay_requests (status, pay_date);
create index if not exists pay_requests_emp on public.pay_requests (employee_id, created_at);
create index if not exists pay_requests_by on public.pay_requests (requested_by);

create table if not exists public.pay_request_events (            -- the timeline a staff member sees; append only
  id bigserial primary key,
  request_id bigint not null references public.pay_requests(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  action text not null check (action in ('received', 'approved', 'redated', 'rejected', 'cancelled', 'paid', 'partly_paid', 'exception_used')),
  from_status text, to_status text, note text, data jsonb
);
create index if not exists pay_request_events_req on public.pay_request_events (request_id, id);

create table if not exists public.pay_request_exceptions (        -- a one-payment, 30 minute permission to pay without an approved request (reason required)
  id bigserial primary key,
  user_id uuid not null, kind text not null check (kind in ('salary', 'advance', 'supplier')),
  employee_id uuid, supplier_id uuid, max_amount numeric not null check (max_amount > 0),
  reason text not null check (length(btrim(reason)) >= 3 and length(reason) <= 300),
  opened_by uuid not null, opened_at timestamptz not null default now(), expires_at timestamptz not null default (now() + interval '30 minutes'),
  used_at timestamptz, used_ref text
);

do $t$ declare t text; begin
  foreach t in array array['pay_requests', 'pay_request_events', 'pay_request_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  foreach t in array array['pay_requests', 'pay_request_exceptions'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
  end loop;
  if exists (select 1 from pg_class where relname = 'pay_requests_id_seq' and relnamespace = 'public'::regnamespace) then
    execute 'revoke all on sequence public.pay_requests_id_seq, public.pay_request_events_id_seq, public.pay_request_exceptions_id_seq from public, anon, authenticated';
  end if;
end $t$;

-- ---------- small helpers ----------
create or replace function public._r1_staff(p_uid uuid default null) returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = coalesce(p_uid, auth.uid()) $$;
create or replace function public._r1_is_owner_uid(p_uid uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p join public.user_roles ur on ur.user_id = p.id where p.id = p_uid and p.status = 'active' and ur.role_code = 'owner') $$;
create or replace function public._r1_my_emp(p_uid uuid default null) returns uuid language sql stable security definer set search_path = public as $$
  select e.id from public.employees e where e.profile_id = coalesce(p_uid, auth.uid()) and e.status in ('active', 'on_leave') order by e.created_at limit 1 $$;
create or replace function public._r1_uuid(t text) returns uuid language plpgsql immutable as $$
begin return nullif(btrim(coalesce(t, '')), '')::uuid; exception when others then return null; end $$;

-- configured approver for a kind: staff requests use pay_request_approver_*; supplier requests use party_request_approver_* unless that is "same"
create or replace function public._r1_cfg(p_kind text, out mode text, out role text, out usr uuid) language plpgsql stable security definer set search_path = public as $$
declare pm text := coalesce(public.rule_txt('party_request_approver_mode'), 'same');
begin
  if p_kind = 'supplier' and pm <> 'same' then
    mode := pm; role := nullif(btrim(coalesce(public.rule_txt('party_request_approver_role'), '')), ''); usr := public._r1_uuid(public.rule_txt('party_request_approver_user'));
  else
    mode := coalesce(public.rule_txt('pay_request_approver_mode'), 'owner'); role := nullif(btrim(coalesce(public.rule_txt('pay_request_approver_role'), '')), ''); usr := public._r1_uuid(public.rule_txt('pay_request_approver_user'));
  end if;
end $$;

-- may this person decide / pay requests of this kind (before the maker rule)? The owner always; otherwise the person or role the owner named.
create or replace function public._r1_approver_ok(p_uid uuid, p_kind text) returns boolean language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  if p_uid is null or not exists (select 1 from public.profiles where id = p_uid and status = 'active') then return false; end if;
  if public._r1_is_owner_uid(p_uid) then return true; end if;
  select * into c from public._r1_cfg(p_kind);
  if c.mode = 'role' then return c.role is not null and exists (select 1 from public.user_roles where user_id = p_uid and role_code = c.role); end if;
  if c.mode = 'user' then return c.usr is not null and c.usr = p_uid; end if;
  return false;
end $$;

-- the maker rule: nobody decides or pays his own request; the owner only where the project already lets him approve his own entries
create or replace function public._r1_can_act(r public.pay_requests, p_uid uuid) returns boolean language plpgsql stable security definer set search_path = public as $$
declare maker boolean;
begin
  if not public._r1_approver_ok(p_uid, r.kind) then return false; end if;
  maker := p_uid = r.requested_by or (r.employee_id is not null and r.employee_id = public._r1_my_emp(p_uid));
  if not maker then return true; end if;
  return public._r1_is_owner_uid(p_uid) and public.rule_on('owner_self_approve') and public._owner_mode() <> 'named';
end $$;

create or replace function public._r1_visible(p_by uuid, p_emp uuid, p_kind text) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (p_by = auth.uid() or public.is_owner() or (p_emp is not null and p_emp = public._r1_my_emp()) or public._r1_approver_ok(auth.uid(), p_kind)) $$;
create or replace function public._r1_req_visible(p_id bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.pay_requests r where r.id = p_id and public._r1_visible(r.requested_by, r.employee_id, r.kind)) $$;

drop policy if exists pay_requests_read on public.pay_requests;
create policy pay_requests_read on public.pay_requests for select to authenticated using (public._r1_visible(requested_by, employee_id, kind));
drop policy if exists pay_request_events_read on public.pay_request_events;
create policy pay_request_events_read on public.pay_request_events for select to authenticated using (public._r1_req_visible(request_id));
drop policy if exists pay_request_exceptions_read on public.pay_request_exceptions;
create policy pay_request_exceptions_read on public.pay_request_exceptions for select to authenticated using (user_id = auth.uid() or public.is_owner());
grant select on public.pay_requests, public.pay_request_events, public.pay_request_exceptions to authenticated;

create or replace function public._r1_event(p_req bigint, p_action text, p_from text, p_to text, p_note text, p_data jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.pay_request_events (request_id, by_user, by_staff, action, from_status, to_status, note, data) values (p_req, auth.uid(), public._r1_staff(), p_action, p_from, p_to, left(p_note, 300), p_data);
end $$;

-- in-app note aimed at one person (notifications, phase 46). One note per request, event and person per day.
create or replace function public._r1_notify(p_user uuid, p_key text, p_tbn text, p_ten text, p_bbn text, p_ben text, p_route text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or to_regclass('public.notifications') is null then return; end if;
  insert into public.notifications (user_id, audience, kind, level, title_bn, title_en, body_bn, body_en, route, key)
    values (p_user, 'all', 'pay_request', 'info', p_tbn, p_ten, p_bbn, p_ben, p_route, left(p_key, 80)) on conflict (kind, key, day) do nothing;
exception when others then null;     -- a note that cannot be written never stops a request
end $$;

-- the people who should hear about a new request: the configured person(s); the owner when the mode is owner. Never the maker.
create or replace function public._r1_approver_users(p_kind text, p_exclude uuid) returns setof uuid language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select * into c from public._r1_cfg(p_kind);
  if c.mode = 'user' and c.usr is not null then return query select p.id from public.profiles p where p.id = c.usr and p.status = 'active' and p.id <> coalesce(p_exclude, '00000000-0000-0000-0000-000000000000'::uuid);
  elsif c.mode = 'role' and c.role is not null then return query select distinct p.id from public.profiles p join public.user_roles ur on ur.user_id = p.id where ur.role_code = c.role and p.status = 'active' and p.id <> coalesce(p_exclude, '00000000-0000-0000-0000-000000000000'::uuid);
  else return query select distinct p.id from public.profiles p join public.user_roles ur on ur.user_id = p.id where ur.role_code = 'owner' and p.status = 'active' and p.id <> coalesce(p_exclude, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;
end $$;

create or replace function public._r1_feature_on(p_kind text) returns boolean language sql stable security definer set search_path = public as $$
  select case when p_kind = 'supplier' then public.rule_on('party_requests_on') else public.rule_on('pay_requests_on') end $$;
create or replace function public._r1_required(p_kind text) returns boolean language sql stable security definer set search_path = public as $$
  select case when p_kind = 'supplier' then public.rule_on('party_requests_required')
              else public.rule_on('pay_requests_required') and coalesce(public.rule_txt('pay_requests_required_kinds'), 'both') in ('both', p_kind) end $$;

-- ============================================================================
-- Approver setting: one call, written to the audit log; the settings cannot be changed one by one from the browser
-- ============================================================================
create or replace function public._r1_rules_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if current_setting('role', true) = 'authenticated' and coalesce(new.value, new.default_value) is distinct from coalesce(old.value, old.default_value)
     and coalesce(current_setting('bos120.setting', true), '') <> '1' then raise exception 'use pay_request_approver_set'; end if;
  return new;
end $$;
drop trigger if exists r1_rules_guard on public.rules;
create trigger r1_rules_guard before update on public.rules for each row
  when (new.key in ('pay_request_approver_mode', 'pay_request_approver_role', 'pay_request_approver_user', 'party_request_approver_mode', 'party_request_approver_role', 'party_request_approver_user'))
  execute function public._r1_rules_guard();

create or replace function public.pay_request_approver_set(p_scope text, p_mode text, p_role text default null, p_user uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pfx text; rl text := nullif(btrim(coalesce(p_role, '')), ''); old jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_scope not in ('staff', 'party') then raise exception 'bad_value'; end if;
  if p_mode is null or p_mode not in ('owner', 'role', 'user') and not (p_scope = 'party' and p_mode = 'same') then raise exception 'bad_value'; end if;
  pfx := case p_scope when 'staff' then 'pay_request_approver_' else 'party_request_approver_' end;
  if p_mode = 'role' then
    if rl is null or not exists (select 1 from public.roles where code = rl and active) or rl = 'owner' then raise exception 'bad_role'; end if;
    if not exists (select 1 from public.user_roles ur join public.profiles p on p.id = ur.user_id where ur.role_code = rl and p.status = 'active') then raise exception 'no_one_holds_role'; end if;
  elsif p_mode = 'user' then
    if p_user is null or not exists (select 1 from public.profiles where id = p_user and status = 'active') then raise exception 'unknown_user'; end if;
  end if;
  old := jsonb_build_object('mode', public.rule_txt(pfx || 'mode'), 'role', public.rule_txt(pfx || 'role'), 'user', public.rule_txt(pfx || 'user'));
  perform set_config('bos120.setting', '1', true);
  update public.rules set value = to_jsonb(p_mode), updated_at = now(), updated_by = auth.uid() where key = pfx || 'mode';
  update public.rules set value = case when p_mode = 'role' then to_jsonb(rl) end, updated_at = now(), updated_by = auth.uid() where key = pfx || 'role';
  update public.rules set value = case when p_mode = 'user' then to_jsonb(p_user::text) end, updated_at = now(), updated_by = auth.uid() where key = pfx || 'user';
  perform set_config('bos120.setting', '', true);
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._r1_staff(), 'pay_request_approver_set', 'rules', p_scope, jsonb_build_object('old', old, 'new', jsonb_build_object('mode', p_mode, 'role', rl, 'user', p_user), 'note', left(p_note, 300)));
  return jsonb_build_object('scope', p_scope, 'mode', p_mode, 'role', case when p_mode = 'role' then rl end, 'user', case when p_mode = 'user' then p_user end);
end $$;

-- ============================================================================
-- Sending, deciding, cancelling
-- ============================================================================
create or replace function public.pay_request_submit(p_kind text, p_amount numeric, p_reason text, p_needed_by date, p_employee uuid default null, p_client uuid default null,
  p_supplier uuid default null, p_bill uuid default null, p_bill_ref text default null, p_asked_by text default null, p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); today date := public._dhaka_today(); emp uuid; r public.pay_requests; id_ bigint; amt numeric := round(p_amount, 2); lim numeric; n int; out_ numeric; opn numeric;
  b public.purchase_bills; loc int; behalf boolean := false; u uuid; nm text; ref text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('salary', 'advance', 'supplier') then raise exception 'bad_kind'; end if;
  if not public._r1_feature_on(p_kind) then raise exception 'requests_off'; end if;
  if p_client is not null then
    perform public._client_lock(p_client);
    select * into r from public.pay_requests where client_id = p_client;
    if found then
      if r.requested_by <> me and not public.is_owner() then raise exception 'not allowed'; end if;
      return jsonb_build_object('id', r.id, 'status', r.status, 'repeat', true);
    end if;
  end if;
  if amt is null or amt <= 0 or amt > 1000000000 then raise exception 'bad_amount'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 or length(btrim(p_reason)) > 300 then raise exception 'reason_required'; end if;
  if p_needed_by is null or p_needed_by < today or p_needed_by > today + 366 then raise exception 'bad_date'; end if;
  if p_kind in ('salary', 'advance') then
    emp := coalesce(p_employee, public._r1_my_emp());
    if emp is null then raise exception 'no_employee_profile'; end if;
    if emp is distinct from public._r1_my_emp() then
      if not public._emp_ok(emp, array['payroll_manage']) then raise exception 'not allowed'; end if;
      behalf := true;
    end if;
    select e.primary_location_id into loc from public.employees e where e.id = emp and e.status in ('active', 'on_leave');
    if not found then raise exception 'employee_not_active'; end if;
    lim := public.rule_num('pay_request_max_per_month');
    if lim is not null then
      select count(*) into n from public.pay_requests q where q.employee_id = emp and q.status <> 'cancelled'
         and date_trunc('month', q.created_at at time zone 'Asia/Dhaka') = date_trunc('month', now() at time zone 'Asia/Dhaka');
      if n >= lim then raise exception 'monthly_request_limit' using detail = 'limit ' || lim::text; end if;
    end if;
    lim := public.rule_num('pay_request_advance_ceiling');
    if p_kind = 'advance' and lim is not null then
      select coalesce(sum(public._adv_outstanding(a.id)), 0) into out_ from public.employee_advances a where a.employee_id = emp and a.status = 'active';
      select coalesce(sum(case q.status when 'received' then q.amount else greatest(q.approved_amount - q.paid_amount, 0) end), 0) into opn
        from public.pay_requests q where q.employee_id = emp and q.kind = 'advance' and q.status in ('received', 'approved');
      if out_ + opn + amt > lim then raise exception 'advance_ceiling' using detail = 'open ' || (out_ + opn)::text || ' + ' || amt::text || ' > ' || lim::text; end if;
    end if;
    if p_loc is not null and p_loc <> loc then loc := p_loc; end if;
    insert into public.pay_requests (client_id, kind, requested_by, requested_staff, on_behalf, employee_id, location_id, amount, reason, needed_by)
      values (p_client, p_kind, me, public._r1_staff(), behalf, emp, loc, amt, left(btrim(p_reason), 300), p_needed_by) returning id into id_;
    nm := (select coalesce(full_name_en, full_name_bn) from public.employees where id = emp);
  else
    loc := p_loc;
    if loc is null or not exists (select 1 from public.locations where id = loc) then raise exception 'bad_location'; end if;
    if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
    if p_supplier is null or not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
    if amt > public._sup_balance(p_supplier) then raise exception 'overpaid'; end if;
    ref := nullif(left(btrim(coalesce(p_bill_ref, '')), 80), '');
    if p_bill is not null then
      select * into b from public.purchase_bills where id = p_bill and supplier_id = p_supplier and status <> 'void';
      if not found then raise exception 'bill_not_found'; end if;
      ref := coalesce(ref, b.bill_no);
    end if;
    insert into public.pay_requests (client_id, kind, requested_by, requested_staff, on_behalf, supplier_id, bill_id, bill_ref, asked_by_name, location_id, amount, reason, needed_by)
      values (p_client, 'supplier', me, public._r1_staff(), nullif(btrim(coalesce(p_asked_by, '')), '') is not null, p_supplier, p_bill, ref, nullif(left(btrim(coalesce(p_asked_by, '')), 80), ''), loc, amt, left(btrim(p_reason), 300), p_needed_by) returning id into id_;
    nm := (select name from public.suppliers where id = p_supplier);
  end if;
  perform public._r1_event(id_, 'received', null, 'received', p_reason, jsonb_build_object('amount', amt, 'needed_by', p_needed_by));
  for u in select * from public._r1_approver_users(p_kind, me) loop
    perform public._r1_notify(u, 'r1:' || id_ || ':new:' || u::text, 'নতুন পেমেন্ট অনুরোধ: ' || amt::text, 'New pay request: ' || amt::text || ' (' || coalesce(nm, '-') || ')',
      'দেখে সিদ্ধান্ত দিন।', 'Please look and decide.', 'payapprovals');
  end loop;
  return jsonb_build_object('id', id_, 'status', 'received', 'kind', p_kind, 'amount', amt, 'needed_by', p_needed_by);
end $$;

create or replace function public.pay_request_decide(p_id bigint, p_approve boolean, p_pay_date date default null, p_amount numeric default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests; today date := public._dhaka_today(); d date; a numeric; prev text; act text; nm text;
begin
  if not public.is_active() or p_approve is null then raise exception 'not allowed'; end if;
  select * into r from public.pay_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._r1_approver_ok(auth.uid(), r.kind) then raise exception 'approver_only'; end if;
  if not public._r1_can_act(r, auth.uid()) then raise exception 'self_approval'; end if;
  if r.status not in ('received', 'approved') then raise exception 'request_not_pending'; end if;
  prev := r.status;
  if p_approve then
    d := coalesce(p_pay_date, r.needed_by);
    if d < today or d > today + 366 then raise exception 'bad_date'; end if;
    a := round(coalesce(p_amount, r.approved_amount, r.amount), 2);
    if a is null or a <= 0 or a > r.amount then raise exception 'bad_amount'; end if;
    if r.paid_amount > 0 and (a < r.paid_amount) then raise exception 'bad_amount'; end if;
    if p_note is not null and length(p_note) > 300 then raise exception 'too_long'; end if;
    act := case when prev = 'approved' then 'redated' else 'approved' end;
    update public.pay_requests set status = 'approved', approved_amount = a, pay_date = d, date_changed = (d <> r.needed_by), decided_by = auth.uid(), decided_staff = public._r1_staff(),
           decided_at = now(), decision_note = nullif(btrim(left(p_note, 300)), ''), updated_at = now() where id = p_id;
    perform public._r1_event(p_id, act, prev, 'approved', p_note, jsonb_build_object('pay_date', d, 'needed_by', r.needed_by, 'approved_amount', a, 'date_changed', d <> r.needed_by));
    nm := case when d <> r.needed_by then 'আপনার অনুরোধে অন্য তারিখ দেওয়া হয়েছে: ' || d::text else 'অনুমোদিত, তারিখ ' || d::text end;
    perform public._r1_notify(r.requested_by, 'r1:' || p_id || ':' || act || ':' || d::text, nm,
      case when d <> r.needed_by then 'Your request was approved for another date: ' || d::text else 'Your request was approved. Pay date: ' || d::text end,
      'পরিমাণ ' || a::text, 'Amount ' || a::text, case when r.kind = 'supplier' then 'partyrequest' else 'payrequest' end);
  else
    if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
    if r.paid_amount > 0 then raise exception 'already_partly_paid'; end if;
    update public.pay_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = public._r1_staff(), decided_at = now(), decision_note = left(btrim(p_note), 300), updated_at = now() where id = p_id;
    perform public._r1_event(p_id, 'rejected', prev, 'rejected', p_note);
    perform public._r1_notify(r.requested_by, 'r1:' || p_id || ':rejected', 'আপনার অনুরোধ নাকচ হয়েছে', 'Your request was rejected', left(btrim(p_note), 200), left(btrim(p_note), 200),
      case when r.kind = 'supplier' then 'partyrequest' else 'payrequest' end);
  end if;
  return (select jsonb_build_object('id', q.id, 'status', q.status, 'pay_date', q.pay_date, 'approved_amount', q.approved_amount, 'date_changed', q.date_changed) from public.pay_requests q where q.id = p_id);
end $$;

create or replace function public.pay_request_cancel(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_note is null or length(btrim(p_note)) < 3 then raise exception 'note_required'; end if;
  select * into r from public.pay_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not (r.requested_by = auth.uid() or public.is_owner() or (r.employee_id is not null and r.employee_id = public._r1_my_emp())) then raise exception 'not allowed'; end if;
  if r.status not in ('received', 'approved') then raise exception 'request_not_pending'; end if;
  if r.paid_amount > 0 then raise exception 'already_partly_paid'; end if;
  update public.pay_requests set status = 'cancelled', decision_note = coalesce(decision_note, left(btrim(p_note), 300)), updated_at = now() where id = p_id;
  perform public._r1_event(p_id, 'cancelled', r.status, 'cancelled', p_note);
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

-- ============================================================================
-- The payment gate (BEFORE INSERT on the three payment tables) and the paying call
-- ============================================================================
create or replace function public._r1_link(p_req bigint, p_amt numeric, p_tbl text, p_row text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests; full_ boolean;
begin
  select * into r from public.pay_requests where id = p_req for update;
  full_ := r.paid_amount + p_amt >= coalesce(r.approved_amount, r.amount) - 0.004;
  update public.pay_requests set paid_amount = paid_amount + p_amt, status = case when full_ then 'paid' else status end, paid_at = case when full_ then now() else paid_at end,
         paid_by = auth.uid(), paid_ref = left(coalesce(nullif(paid_ref, '') || ', ', '') || p_tbl || ':' || p_row, 300), updated_at = now() where id = p_req;
  perform public._r1_event(p_req, case when full_ then 'paid' else 'partly_paid' end, r.status, case when full_ then 'paid' else r.status end, null, jsonb_build_object('amount', p_amt, 'row', p_tbl || ':' || p_row));
  perform public._r1_notify(r.requested_by, 'r1:' || p_req || ':' || case when full_ then 'paid' else 'part' end || ':' || p_row, case when full_ then 'পেমেন্ট দেওয়া হয়েছে: ' || p_amt::text else 'আংশিক পেমেন্ট: ' || p_amt::text end,
    case when full_ then 'Paid: ' || p_amt::text else 'Part paid: ' || p_amt::text end, null, null, case when r.kind = 'supplier' then 'partyrequest' else 'payrequest' end);
end $$;

create or replace function public._r1_gate_bi() returns trigger language plpgsql security definer set search_path = public as $$
declare k text; emp uuid; sup uuid; amt numeric; d date; cl uuid; explicit bigint := nullif(current_setting('r1.req', true), '')::bigint; r public.pay_requests; t public.pay_request_exceptions;
  tbl text := tg_table_name; today date := public._dhaka_today(); rid text := new.id::text;
begin
  if auth.uid() is null then return new; end if;                                  -- the system (backup, migration): never gated
  if tbl = 'employee_advances' then
    if new.mode = 'none' or new.status <> 'active' then return new; end if;        -- a paper-register entry moves no money
    k := 'advance'; emp := new.employee_id; amt := new.amount; d := new.adv_date; cl := new.client_id;
  elsif tbl = 'payroll_payments' then
    k := 'salary'; emp := new.employee_id; amt := new.amount; d := new.pay_date; cl := new.client_batch;
  else
    if new.bill_id is not null or new.kind is distinct from 'payment' or new.voided then return new; end if;    -- a payment made with a purchase bill is not covered
    k := 'supplier'; sup := new.supplier_id; amt := new.amount; d := (new.paid_at at time zone 'Asia/Dhaka')::date; cl := new.client_id;
  end if;
  -- 1. the paying call named its request: it must fit
  if explicit is not null then
    select * into r from public.pay_requests where id = explicit for update;
    if not found or r.status <> 'approved' or r.kind <> k or r.employee_id is distinct from emp or r.supplier_id is distinct from sup then raise exception 'pay_request_mismatch'; end if;
    if r.pay_date > today then raise exception 'not_due_yet'; end if;
    if r.paid_amount + amt > coalesce(r.approved_amount, r.amount) + 0.004 then raise exception 'pay_request_amount'; end if;
    perform public._r1_link(r.id, amt, tbl, rid); return new;
  end if;
  -- 2. policy off: nothing to check (today's behaviour)
  if not public._r1_required(k) then return new; end if;
  -- 3. an approved request that is due and big enough
  select * into r from public.pay_requests q where q.kind = k and q.status = 'approved' and q.employee_id is not distinct from emp and q.supplier_id is not distinct from sup
     and q.pay_date <= today and coalesce(q.approved_amount, q.amount) - q.paid_amount >= amt - 0.004 order by q.pay_date, q.id limit 1 for update skip locked;
  if found then perform public._r1_link(r.id, amt, tbl, rid); return new; end if;
  -- 4. one exception with a reason (opened by this person, valid for 30 minutes, one payment), logged to the Exceptions list
  select * into t from public.pay_request_exceptions x where x.user_id = auth.uid() and x.kind = k and x.used_at is null and x.expires_at > now()
     and x.employee_id is not distinct from emp and x.supplier_id is not distinct from sup and x.max_amount >= amt - 0.004 order by x.id limit 1 for update skip locked;
  if found then
    update public.pay_request_exceptions set used_at = now(), used_ref = tbl || ':' || rid where id = t.id;
    insert into public.money_exceptions (kind, event_type, amount, src_table, src_id, reason, by_user)
      values ('r1_unbacked_payment', 'r1_pay_' || k, amt, tbl, rid, left('Paid without an approved request: ' || t.reason || ' (opened by ' || coalesce(public._r1_staff(t.opened_by), '-') || ')', 300), auth.uid());
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), public._r1_staff(), 'pay_request_exception_used', tbl, rid, jsonb_build_object('kind', k, 'amount', amt, 'reason', t.reason, 'exception_id', t.id));
    return new;
  end if;
  -- 5. the owner's one-off override of phase 87 (event r1_pay_<kind>), if he gave one
  if public._m_grant_take('override', 'r1_pay_' || k, cl, null, amt, d, tbl) then return new; end if;
  raise exception 'pay_request_required' using detail = k || ' ' || amt::text;
end $$;

do $trg$ declare t text; begin
  foreach t in array array['employee_advances', 'payroll_payments', 'supplier_payments'] loop
    execute format('drop trigger if exists a0_r1_gate_bi on public.%I', t);
    execute format('create trigger a0_r1_gate_bi before insert on public.%I for each row execute function public._r1_gate_bi()', t);
  end loop;
end $trg$;

-- the one-payment exception (who may open it is the setting pay_request_exception_mode)
create or replace function public.pay_request_exception_open(p_kind text, p_subject uuid, p_amount numeric, p_reason text, p_for_user uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare md text := coalesce(public.rule_txt('pay_request_exception_mode'), 'reason'); amt numeric := round(p_amount, 2); u uuid := coalesce(p_for_user, auth.uid()); id_ bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('salary', 'advance', 'supplier') then raise exception 'bad_kind'; end if;
  if not public._r1_required(p_kind) then raise exception 'not_required'; end if;
  if md = 'never' then raise exception 'exceptions_off'; end if;
  if (md = 'owner' or u <> auth.uid()) and not public.is_owner() then raise exception 'owner_only'; end if;
  if p_reason is null or length(btrim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if amt is null or amt <= 0 then raise exception 'bad_amount'; end if;
  if p_subject is null then raise exception 'subject_required'; end if;
  if p_kind = 'supplier' then
    if not exists (select 1 from public.suppliers where id = p_subject) then raise exception 'supplier_not_found'; end if;
  elsif not exists (select 1 from public.employees where id = p_subject) then raise exception 'not_found'; end if;
  insert into public.pay_request_exceptions (user_id, kind, employee_id, supplier_id, max_amount, reason, opened_by)
    values (u, p_kind, case when p_kind <> 'supplier' then p_subject end, case when p_kind = 'supplier' then p_subject end, amt, left(btrim(p_reason), 300), auth.uid()) returning id into id_;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._r1_staff(), 'pay_request_exception_open', 'pay_request_exceptions', id_::text, jsonb_build_object('kind', p_kind, 'subject', p_subject, 'amount', amt, 'for_user', u, 'reason', left(btrim(p_reason), 300)));
  return jsonb_build_object('id', id_, 'expires_at', (select expires_at from public.pay_request_exceptions where id = id_));
end $$;

-- pay an approved request through the EXISTING function; the payment source is chosen now (a money account, or a mode)
create or replace function public.pay_request_pay(p_id bigint, p_mode text default null, p_money_account bigint default null, p_ref text default null, p_note text default null,
  p_instalment numeric default null, p_recover_from date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.pay_requests; today date := public._dhaka_today(); amt numeric; md text; tag text := ''; ma public.money_accounts; ln public.payroll_lines; cid uuid; res jsonb; note_ text; q public.pay_requests;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into r from public.pay_requests where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._r1_approver_ok(auth.uid(), r.kind) then raise exception 'approver_only'; end if;
  if not public._r1_can_act(r, auth.uid()) then raise exception 'self_payment'; end if;
  if r.status <> 'approved' then raise exception 'request_not_approved'; end if;
  if r.pay_date > today then raise exception 'not_due_yet'; end if;
  amt := round(coalesce(r.approved_amount, r.amount) - r.paid_amount, 2);
  if amt <= 0 then raise exception 'request_not_approved'; end if;
  if p_money_account is not null then
    select * into ma from public.money_accounts where id = p_money_account;
    if not found or not ma.active then raise exception 'money_account_inactive'; end if;
    md := public._m_mode_of_kind(ma.kind); tag := 'ma#' || p_money_account::text || ';';
  else
    md := lower(btrim(coalesce(p_mode, '')));
    if md not in ('cash', 'mobile', 'bank') and not (r.kind = 'supplier' and md = 'card') then raise exception 'mode_required'; end if;
  end if;
  cid := md5('r1pay:' || p_id::text || ':' || r.paid_amount::text)::uuid;
  note_ := left(tag || 'Pay request #' || p_id::text || coalesce(' · ' || nullif(btrim(p_note), ''), ''), 300);
  perform set_config('r1.req', p_id::text, true);
  if r.kind = 'advance' then
    res := public.staff_advance_add(r.employee_id, today, amt, p_instalment, md, p_recover_from, note_, cid);
  elsif r.kind = 'salary' then
    select l.* into ln from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
     where l.employee_id = r.employee_id and l.active and pr.status in ('approved', 'paid') and l.net - l.paid_amount > 0 order by l.month, l.id limit 1;
    if not found then raise exception 'no_payroll_due'; end if;
    res := public.payroll_pay(ln.run_id, array[ln.id], md, today, left(tag || coalesce(nullif(btrim(p_ref), ''), 'REQ-' || p_id::text), 80), left('Pay request #' || p_id::text || coalesce(' · ' || nullif(btrim(p_note), ''), ''), 300), cid, amt);
  else
    res := public.pay_supplier(r.supplier_id, r.location_id, jsonb_build_array(jsonb_build_object('mode', md, 'amount', amt, 'wallet', nullif(tag, ''), 'ref', left(coalesce(nullif(btrim(p_ref), ''), 'REQ-' || p_id::text), 60))),
      cid, left('Pay request #' || p_id::text || coalesce(' · ' || nullif(btrim(p_note), ''), ''), 200));
    if coalesce((res ->> 'pending')::boolean, false) then raise exception 'held_by_payment_limit'; end if;
  end if;
  perform set_config('r1.req', '', true);
  select * into q from public.pay_requests where id = p_id;
  if q.paid_amount <= r.paid_amount then raise exception 'payment_not_linked'; end if;
  return jsonb_build_object('request_id', p_id, 'status', q.status, 'paid_amount', q.paid_amount, 'mode', md, 'result', res);
end $$;

-- ============================================================================
-- Reading: state, lists, counts
-- ============================================================================
create or replace function public.pay_request_state() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c1 record; c2 record; today date := public._dhaka_today(); me uuid := auth.uid();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into c1 from public._r1_cfg('salary'); select * into c2 from public._r1_cfg('supplier');
  return jsonb_build_object(
    'staff_on', public.rule_on('pay_requests_on'), 'party_on', public.rule_on('party_requests_on'),
    'staff_required', public.rule_on('pay_requests_required') , 'required_kinds', coalesce(public.rule_txt('pay_requests_required_kinds'), 'both'), 'party_required', public.rule_on('party_requests_required'),
    'exception_mode', coalesce(public.rule_txt('pay_request_exception_mode'), 'reason'),
    'max_per_month', public.rule_num('pay_request_max_per_month'), 'advance_ceiling', public.rule_num('pay_request_advance_ceiling'),
    'my_employee', public._r1_my_emp(), 'is_owner', public.is_owner(),
    'approver_staff', public._r1_approver_ok(me, 'salary'), 'approver_party', public._r1_approver_ok(me, 'supplier'),
    'can_on_behalf', public.is_owner() or exists (select 1 from public.user_grants g where g.user_id = me and g.grant_code = 'payroll_manage' and (g.valid_until is null or g.valid_until > now())),
    'approver', jsonb_build_object('staff', jsonb_build_object('mode', c1.mode, 'role', c1.role, 'user', c1.usr, 'name', (select full_name from public.profiles where id = c1.usr)),
                                   'party', jsonb_build_object('mode', c2.mode, 'role', c2.role, 'user', c2.usr, 'name', (select full_name from public.profiles where id = c2.usr)),
                                   'party_same', coalesce(public.rule_txt('party_request_approver_mode'), 'same') = 'same'),
    'gate', jsonb_build_object('advance', exists (select 1 from pg_trigger where tgname = 'a0_r1_gate_bi' and tgrelid = 'public.employee_advances'::regclass),
                               'salary', exists (select 1 from pg_trigger where tgname = 'a0_r1_gate_bi' and tgrelid = 'public.payroll_payments'::regclass),
                               'supplier', exists (select 1 from pg_trigger where tgname = 'a0_r1_gate_bi' and tgrelid = 'public.supplier_payments'::regclass)),
    'counts', public.pay_request_counts(), 'today', today);
end $$;

create or replace function public.pay_request_counts() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); today date := public._dhaka_today();
begin
  if not public.is_active() then return jsonb_build_object('inbox', 0, 'due', 0, 'mine_open', 0); end if;
  return jsonb_build_object(
    'inbox', (select count(*) from public.pay_requests r where r.status = 'received' and public._r1_can_act(r, me)),
    'due', (select count(*) from public.pay_requests r where r.status = 'approved' and r.pay_date <= today and public._r1_can_act(r, me)),
    'mine_open', (select count(*) from public.pay_requests r where r.status in ('received', 'approved') and (r.requested_by = me or r.employee_id = public._r1_my_emp())));
end $$;

-- p_scope: mine | inbox (waiting for me to decide) | due (approved, pay date today or earlier) | upcoming (approved, later date) | all (everything I may see)
create or replace function public.pay_request_list(p_scope text default 'mine', p_status text default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); today date := public._dhaka_today(); myemp uuid := public._r1_my_emp();
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_scope is null or p_scope not in ('mine', 'inbox', 'due', 'upcoming', 'all') then raise exception 'bad_value'; end if;
  return jsonb_build_object('today', today, 'rows', coalesce((select jsonb_agg(to_jsonb(z) order by z.sortkey, z.id desc) from (
    select r.id, r.kind, r.status, r.amount, r.approved_amount, r.paid_amount, r.reason, r.needed_by, r.pay_date, r.date_changed, r.decided_at, r.decision_note, r.paid_at, r.created_at as requested_at,
           r.requested_staff, r.on_behalf, r.employee_id, r.supplier_id, r.bill_id, r.bill_ref, r.asked_by_name, r.location_id, r.paid_ref,
           case when r.kind = 'supplier' then (select s.name from public.suppliers s where s.id = r.supplier_id) else (select coalesce(e.full_name_en, e.full_name_bn) from public.employees e where e.id = r.employee_id) end as subject,
           (r.requested_by = me or (r.employee_id is not null and r.employee_id = myemp)) as mine,
           (r.status in ('received', 'approved') and public._r1_can_act(r, me)) as can_decide,
           (r.status = 'approved' and r.pay_date <= today and public._r1_can_act(r, me)) as can_pay,
           (r.status in ('received', 'approved') and r.paid_amount = 0 and (r.requested_by = me or public.is_owner() or (r.employee_id is not null and r.employee_id = myemp))) as can_cancel,
           (r.status = 'approved' and r.pay_date < today) as overdue,
           coalesce((select jsonb_agg(jsonb_build_object('at', ev.at, 'action', ev.action, 'note', ev.note, 'by', ev.by_staff, 'data', ev.data) order by ev.id) from public.pay_request_events ev where ev.request_id = r.id), '[]'::jsonb) as events,
           case when r.status = 'approved' then 0 when r.status = 'received' then 1 else 2 end as sortkey
      from public.pay_requests r
     where public._r1_visible(r.requested_by, r.employee_id, r.kind)
       and (p_status is null or r.status = p_status)
       and case p_scope
             when 'mine' then (r.requested_by = me or (r.employee_id is not null and r.employee_id = myemp))
             when 'inbox' then r.status = 'received' and public._r1_can_act(r, me)
             when 'due' then r.status = 'approved' and r.pay_date <= today and public._r1_can_act(r, me)
             when 'upcoming' then r.status = 'approved' and r.pay_date > today and public._r1_can_act(r, me)
             else true end
     order by r.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb));
end $$;

-- ---------- the browser may call the API, never the helpers ----------
revoke all on function public._r1_exc_kinds_apply(), public._r1_staff(uuid), public._r1_is_owner_uid(uuid), public._r1_my_emp(uuid), public._r1_uuid(text), public._r1_cfg(text),
  public._r1_approver_ok(uuid, text), public._r1_can_act(public.pay_requests, uuid), public._r1_event(bigint, text, text, text, text, jsonb), public._r1_notify(uuid, text, text, text, text, text, text),
  public._r1_approver_users(text, uuid), public._r1_feature_on(text), public._r1_required(text), public._r1_link(bigint, numeric, text, text), public._r1_gate_bi(), public._r1_rules_guard() from public, anon, authenticated;
-- used inside row policies: they run as the caller, so the two predicates must stay callable
revoke all on function public._r1_visible(uuid, uuid, text), public._r1_req_visible(bigint) from public, anon;
grant execute on function public._r1_visible(uuid, uuid, text), public._r1_req_visible(bigint), public._r1_my_emp(uuid) to authenticated;
revoke all on function public.pay_request_approver_set(text, text, text, uuid, text), public.pay_request_submit(text, numeric, text, date, uuid, uuid, uuid, uuid, text, text, int),
  public.pay_request_decide(bigint, boolean, date, numeric, text), public.pay_request_cancel(bigint, text), public.pay_request_exception_open(text, uuid, numeric, text, uuid),
  public.pay_request_pay(bigint, text, bigint, text, text, numeric, date), public.pay_request_state(), public.pay_request_counts(), public.pay_request_list(text, text, int) from public, anon;
grant execute on function public.pay_request_approver_set(text, text, text, uuid, text), public.pay_request_submit(text, numeric, text, date, uuid, uuid, uuid, uuid, text, text, int),
  public.pay_request_decide(bigint, boolean, date, numeric, text), public.pay_request_cancel(bigint, text), public.pay_request_exception_open(text, uuid, numeric, text, uuid),
  public.pay_request_pay(bigint, text, bigint, text, text, numeric, date), public.pay_request_state(), public.pay_request_counts(), public.pay_request_list(text, text, int) to authenticated;
