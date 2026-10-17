-- Phase 328 (bos328, package CRM-H, part 1 of 2: label 128) - CUSTOMER COMPLAINTS WITH AN SLA CLOCK.
-- Paste AFTER phase98 (needs the sale return, exceptions, rules, grants and option lists of the older phases). Paste-twice safe.
-- No earlier phase file is edited and no shared function is re-created. Every new name starts _crmh_ / crm_ so it cannot clash with another package.
-- Part 2 (phase329) adds ratings, repeat-complaint lists and the report.
--
-- WHY (CRM design 3.1.H, audit rows 46-48): today a complaint is a paper-replica line in form 20-3 (free-text customer, no due time, no owner, no clock).
-- A food-safety complaint needs a clock and the owner needs to see which outlet and which item keep producing complaints.
-- WHAT THIS FILE ADDS
--   1. Settings (rules, module crm), all OFF or blank: crm_complaints_on, one SLA target (hours) per severity, food-safety routing, repeat detection.
--   2. Three grants: crm_complaint_log, crm_complaint_manage, crm_feedback_view (nobody gets them by default; the owner always has them).
--   3. Three editable lists (option_lists): complaint categories, resolution types, reasons for closing without a resolution.
--   4. Tables: crm_complaints, crm_complaint_events (append only), crm_complaint_returns (link to the EXISTING sale return, never a second refund path).
--   5. A status guard trigger: illegal status changes are refused by the database itself; a closed complaint is locked; nothing is deleted.
--   6. API functions (all _crmh_*, SECURITY DEFINER, gated first, idempotent where a client id is given):
--        _crmh_complaint_save, _crmh_complaint_assign, _crmh_complaint_note, _crmh_complaint_move, _crmh_complaint_severity_set,
--        _crmh_complaint_link_return, _crmh_complaint_list, _crmh_complaint_get, _crmh_sla_scan, _crmh_counts, _crmh_settings
-- ACCOUNTING: a complaint posts nothing. No function here touches sales, sale_returns, sale_payments, journal_entries or journal_lines.
--   A refund goes through the existing sale_return function; this file only LINKS a finished return to a complaint (read only on sale_returns).
-- DEFAULTS: with crm_complaints_on OFF every write function answers 'complaints_off' and no report, screen or workflow changes.

do $g$ begin
  if to_regclass('public.sale_returns') is null or to_regclass('public.exceptions') is null or to_regclass('public.option_lists') is null
     or to_regclass('public.grant_defs') is null or to_regclass('public.customers') is null or to_regclass('public.online_orders') is null
     or to_regprocedure('public.rpt_mobile_ok()') is null or to_regprocedure('public._is_ops(text)') is null or to_regprocedure('public.has_grant(text,integer)') is null then
    raise exception 'phase328 needs the older phases (sale return, online orders, reports, notify, grants) first';
  end if;
end $g$;

create or replace function public._crmh_present() returns boolean language sql immutable as $$ select true $$;

-- ============================================================================
-- 1. SETTINGS (rules). English text only. Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_complaints_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
  'Record customer complaints and track them to a result',
  'OFF = nothing changes (today). ON = staff can log a complaint with outlet, item, severity and owner, and it has a status and a result. A complaint never posts any money; a refund is still made on the sale return screen.', 1280),
 ('crm_complaint_sla_hours_low', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a LOW severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1281),
 ('crm_complaint_sla_hours_medium', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a MEDIUM severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1282),
 ('crm_complaint_sla_hours_high', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a HIGH severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1283),
 ('crm_complaint_sla_hours_critical', 'number', null, 'hours', null, 1, 8760,
  'Target hours to resolve a CRITICAL severity complaint',
  'Blank = no clock for this severity. The clock starts when the complaint is logged and shows OVERDUE after this many hours.', 1284),
 ('crm_complaint_fs_exception_on', 'switch', 'true'::jsonb, null, null, null, null,
  'Put a food-safety complaint on the Exceptions list',
  'Only used while complaints are ON. ON = a complaint marked food safety adds one red line to the Exceptions list so the owner sees it at once. OFF = it is only marked on the complaint.', 1285),
 ('crm_complaint_fs_categories', 'text', '"sick"'::jsonb, null, null, null, null,
  'Complaint categories that always count as food safety',
  'A comma list of category codes (for example sick). A complaint in one of these categories is marked food safety even if the box is not ticked. Blank = only the box decides. The default sick is the same "fell ill" cause that form 20-3 already flags.', 1286),
 ('crm_complaint_fs_severity', 'choice', '"keep"'::jsonb, null, '["keep","high","critical"]'::jsonb, null, null,
  'Lowest severity given to a food-safety complaint',
  'keep = the severity chosen by the person (today). high or critical = a food-safety complaint is never logged below that severity, so it gets the shorter clock.', 1287),
 ('crm_complaint_breach_exception_on', 'switch', 'true'::jsonb, null, null, null, null,
  'Put an overdue complaint on the Exceptions list',
  'Only used while complaints are ON and only when an SLA clock is set. ON = when the overdue check runs, each newly overdue complaint adds one yellow line to the Exceptions list. OFF = it is only marked on the complaint.', 1288),
 ('crm_repeat_days', 'number', null, 'days', null, 1, 3650,
  'Repeat complaint check: look back this many days',
  'Blank = no repeat check (today). A number marks a new complaint as a REPEAT when the same customer (and, by the next setting, the same item) already complained inside this many days.', 1289),
 ('crm_repeat_min', 'number', '2'::jsonb, 'complaints', null, 2, 50,
  'Repeat complaint check: complaints needed (this one included)',
  'Used only when the look-back days above are set. 2 = flag the second complaint. 3 = flag from the third.', 1290),
 ('crm_repeat_scope', 'choice', '"customer_item"'::jsonb, null, '["customer_item","customer"]'::jsonb, null, null,
  'Repeat complaint check: same customer and same item, or same customer only',
  'Used only when the look-back days above are set. customer_item = the same customer complained about the same item. customer = any complaint by the same customer.', 1291)
 ) v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ============================================================================
-- 2. GRANTS (nobody holds them by default; the owner always passes)
-- ============================================================================
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type) values
 ('crm_complaint_log', 'crm', 920, 'Log a customer complaint or rating', 'Log a customer complaint or rating', 'Log a customer complaint or rating', 'once'),
 ('crm_complaint_manage', 'crm', 921, 'Assign, resolve and close customer complaints', 'Assign, resolve and close customer complaints', 'Assign, resolve and close customer complaints', 'once'),
 ('crm_feedback_view', 'crm', 922, 'See customer complaint and rating lists and reports', 'See customer complaint and rating lists and reports', 'See customer complaint and rating lists and reports', 'once')
on conflict (grant_code) do nothing;

-- ============================================================================
-- 3. EDITABLE LISTS (BUILD-RULES 4: a list, not free text; the owner can add or retire entries on the lists screen)
--    Categories mirror the causes already on form 20-3 so the two registers speak the same words.
-- ============================================================================
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('crm_complaint_cats', 'taste', 'Taste', 'Taste', 'Taste', 1), ('crm_complaint_cats', 'smell', 'Smell or spoiled', 'Smell or spoiled', 'Smell or spoiled', 2),
 ('crm_complaint_cats', 'broken', 'Broken or damaged', 'Broken or damaged', 'Broken or damaged', 3), ('crm_complaint_cats', 'short', 'Short quantity', 'Short quantity', 'Short quantity', 4),
 ('crm_complaint_cats', 'wrong', 'Wrong goods', 'Wrong goods', 'Wrong goods', 5), ('crm_complaint_cats', 'late', 'Late delivery', 'Late delivery', 'Late delivery', 6),
 ('crm_complaint_cats', 'staff', 'Staff behaviour', 'Staff behaviour', 'Staff behaviour', 7), ('crm_complaint_cats', 'sick', 'Customer fell ill', 'Customer fell ill', 'Customer fell ill', 8),
 ('crm_complaint_cats', 'other', 'Other', 'Other', 'Other', 99),
 ('crm_resolution_types', 'explained', 'Explained to the customer', 'Explained to the customer', 'Explained to the customer', 1),
 ('crm_resolution_types', 'replaced', 'Goods replaced', 'Goods replaced', 'Goods replaced', 2),
 ('crm_resolution_types', 'refunded', 'Refund or credit given (sale return)', 'Refund or credit given (sale return)', 'Refund or credit given (sale return)', 3),
 ('crm_resolution_types', 'other', 'Other', 'Other', 'Other', 99),
 ('crm_close_reasons', 'no_contact', 'Customer could not be reached', 'Customer could not be reached', 'Customer could not be reached', 1),
 ('crm_close_reasons', 'not_valid', 'Not a valid complaint', 'Not a valid complaint', 'Not a valid complaint', 2),
 ('crm_close_reasons', 'duplicate', 'Same as another complaint', 'Same as another complaint', 'Same as another complaint', 3),
 ('crm_close_reasons', 'other', 'Other', 'Other', 'Other', 99)
on conflict (list_code, value_code) do nothing;

-- ============================================================================
-- 4. TABLES (closed to browser roles; read and written only through the definer functions below)
-- ============================================================================
create sequence if not exists public.crm_complaints_no_seq;
create table if not exists public.crm_complaints (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  ticket_no bigint not null default nextval('public.crm_complaints_no_seq'),
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  customer_name text check (customer_name is null or char_length(customer_name) <= 80),
  customer_phone text check (customer_phone is null or char_length(customer_phone) <= 20),
  sale_id uuid references public.sales(id),
  order_id uuid references public.online_orders(id),
  item_id uuid references public.items(id),
  category text not null,
  severity text not null check (severity in ('low', 'medium', 'high', 'critical')),
  food_safety boolean not null default false,
  description text not null check (char_length(btrim(description)) between 3 and 1000),
  batch_ref text check (batch_ref is null or char_length(batch_ref) <= 60),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved', 'closed', 'closed_no_resolution')),
  owner_user uuid references public.profiles(id),
  due_at timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz, resolution_type text, resolution_note text check (resolution_note is null or char_length(resolution_note) <= 1000),
  closed_at timestamptz, close_reason text,
  sla_met boolean,
  breached_at timestamptz,
  repeat_flag boolean not null default false,
  repeat_count int not null default 0,
  created_by uuid not null, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists crm_complaints_loc_status on public.crm_complaints (location_id, status, created_at desc);
create index if not exists crm_complaints_cust on public.crm_complaints (customer_id, created_at desc) where customer_id is not null;
create index if not exists crm_complaints_item on public.crm_complaints (item_id, created_at desc) where item_id is not null;
create index if not exists crm_complaints_due on public.crm_complaints (due_at) where status in ('open', 'in_progress');

create table if not exists public.crm_complaint_events (            -- append only trail: who did what, when
  id bigserial primary key,
  complaint_id uuid not null references public.crm_complaints(id),
  at timestamptz not null default now(),
  kind text not null check (kind in ('created', 'assigned', 'status', 'note', 'contact', 'severity', 'link_return', 'sla_breach', 'repeat', 'food_safety', 'reopen')),
  from_status text, to_status text, note text check (note is null or char_length(note) <= 1000),
  by_user uuid, by_staff text
);
create index if not exists crm_complaint_events_c on public.crm_complaint_events (complaint_id, id);

create table if not exists public.crm_complaint_returns (           -- a finished sale return linked to a complaint (the refund itself stays on the sale return screen)
  id bigserial primary key,
  complaint_id uuid not null references public.crm_complaints(id),
  return_id uuid not null unique references public.sale_returns(id),
  linked_by uuid, linked_at timestamptz not null default now()
);
create index if not exists crm_complaint_returns_c on public.crm_complaint_returns (complaint_id);

do $t$ declare t text; begin
  foreach t in array array['crm_complaints', 'crm_complaint_events', 'crm_complaint_returns'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $t$;
drop trigger if exists audit_crm_complaints on public.crm_complaints;
create trigger audit_crm_complaints after insert or update on public.crm_complaints for each row execute function public.log_change('id');

-- the events table is append only
create or replace function public._crmh_append_only() returns trigger language plpgsql as $$
begin raise exception 'append_only'; end $$;
drop trigger if exists crm_complaint_events_ro on public.crm_complaint_events;
create trigger crm_complaint_events_ro before update on public.crm_complaint_events for each row execute function public._crmh_append_only();

-- the status guard: the database itself refuses an illegal move, whoever asks (a hidden button is also a refused request)
--   open -> in_progress | resolved | closed_no_resolution ;  in_progress -> resolved | closed_no_resolution ;  resolved -> closed | in_progress (reopen)
--   closed and closed_no_resolution are final: the row is locked.
create or replace function public._crmh_complaint_guard() returns trigger language plpgsql as $$
begin
  if old.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  if new.id is distinct from old.id or new.client_id is distinct from old.client_id or new.ticket_no is distinct from old.ticket_no
     or new.location_id is distinct from old.location_id or new.created_by is distinct from old.created_by or new.created_at is distinct from old.created_at then
    raise exception 'complaint_immutable';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'open' and new.status in ('in_progress', 'resolved', 'closed_no_resolution'))
    or (old.status = 'in_progress' and new.status in ('resolved', 'closed_no_resolution'))
    or (old.status = 'resolved' and new.status in ('closed', 'in_progress'))) then
    raise exception 'illegal_status_change';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists crm_complaints_guard on public.crm_complaints;
create trigger crm_complaints_guard before update on public.crm_complaints for each row execute function public._crmh_complaint_guard();

-- ============================================================================
-- 5. INTERNAL HELPERS (closed to browsers)
-- ============================================================================
create or replace function public._crmh_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid() $$;

-- who may do what, per outlet (the server decides; owner always)
create or replace function public._crmh_log_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.can_loc(p_loc) and (public.has_grant('crm_complaint_log', p_loc) or public.has_grant('crm_complaint_manage', p_loc) or public.can_do('POS', 'enter')))) $$;
create or replace function public._crmh_manage_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.can_loc(p_loc) and public.has_grant('crm_complaint_manage', p_loc))) $$;
create or replace function public._crmh_view_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.can_loc(p_loc) and (public.has_grant('crm_feedback_view', p_loc) or public.has_grant('crm_complaint_manage', p_loc)))) $$;
create or replace function public._crmh_phone_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_mobile_ok() or public._crmh_manage_ok(p_loc)) $$;
create or replace function public._crmh_mask(p text) returns text language sql immutable as $$
  select case when p is null or p = '' then p when char_length(p) <= 5 then '****' else left(p, 3) || '****' || right(p, 2) end $$;

create or replace function public._crmh_j_uuid(p jsonb, k text) returns uuid language plpgsql immutable as $$
declare v text := nullif(btrim(p ->> k), '');
begin
  if v is null then return null; end if;
  if v !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'bad_%', k; end if;
  return v::uuid;
end $$;
create or replace function public._crmh_j_bool(p jsonb, k text) returns boolean language sql immutable as $$
  select coalesce(lower(p ->> k) in ('true', 't', '1', 'yes'), false) $$;

create or replace function public._crmh_sla_hours(p_sev text) returns numeric language sql stable security definer set search_path = public as $$
  select public.rule_num('crm_complaint_sla_hours_' || p_sev) $$;
create or replace function public._crmh_sla_state(st text, due timestamptz, met boolean) returns text language sql stable as $$
  select case when st in ('resolved', 'closed') then case when met is true then 'met' when met is false then 'missed' else 'none' end
              when st = 'closed_no_resolution' then 'none'
              when due is null then 'none' when now() > due then 'overdue' else 'running' end $$;

create or replace function public._crmh_ev(p_c uuid, p_kind text, p_from text, p_to text, p_note text) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_complaint_events (complaint_id, kind, from_status, to_status, note, by_user, by_staff)
    values (p_c, p_kind, p_from, p_to, left(p_note, 1000), auth.uid(), public._crmh_staff());
end $$;
create or replace function public._crmh_audit(p_action text, p_rec text, p_detail jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), public._crmh_staff(), p_action, 'crm_complaints', p_rec, coalesce(p_detail, '{}'::jsonb));
end $$;
-- one row in the Exceptions list; the same open flag for the same complaint is not written twice
create or replace function public._crmh_exc(p_loc int, p_flag text, p_level text, p_en text, p_ref text) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.exceptions x where x.flag_code = p_flag and x.status = 'open' and x.text ->> 'ref' = p_ref) then return false; end if;
  insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
    values (null, null, 'CRM', p_loc, (now() at time zone 'Asia/Dhaka')::date, p_flag, p_level, null, jsonb_build_object('bn', p_en, 'en', p_en, 'ref', p_ref));
  return true;
end $$;

-- may this user take part in an outlet (used before a complaint is assigned to them)
create or replace function public._crmh_user_loc_ok(p_user uuid, p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p_user and status = 'active')
     and (exists (select 1 from public.user_roles where user_id = p_user and role_code in ('owner', 'management'))
          or exists (select 1 from public.user_locations where user_id = p_user and location_id = p_loc)) $$;

-- how many earlier complaints match (repeat detection). 0 when the check is off or there is nothing to match on.
create or replace function public._crmh_repeat_prior(p_cust uuid, p_phone text, p_item uuid, p_before timestamptz) returns int
language plpgsql stable security definer set search_path = public as $$
declare days numeric := public.rule_num('crm_repeat_days'); scope text := coalesce(public.rule_txt('crm_repeat_scope'), 'customer_item'); n int;
begin
  if days is null then return 0; end if;
  if p_cust is null and nullif(btrim(coalesce(p_phone, '')), '') is null then return 0; end if;
  if scope = 'customer_item' and p_item is null then return 0; end if;
  select count(*) into n from public.crm_complaints x
   where x.created_at < p_before and x.created_at >= p_before - make_interval(days => days::int)
     and coalesce(x.close_reason, '') <> 'duplicate'
     and ((p_cust is not null and x.customer_id = p_cust)
          or (nullif(btrim(coalesce(p_phone, '')), '') is not null and nullif(public.norm_mobile(x.customer_phone), '') = public.norm_mobile(p_phone)))
     and (scope = 'customer' or x.item_id = p_item);
  return n;
end $$;

-- one complaint as JSON. The phone is masked unless the caller may see it for that outlet.
create or replace function public._crmh_row(cx public.crm_complaints) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ret jsonb; st text;
begin
  select jsonb_build_object('n', count(*), 'amount', coalesce(sum(r.amount), 0)) into ret
    from public.crm_complaint_returns lr join public.sale_returns r on r.id = lr.return_id and r.status = 'done' where lr.complaint_id = cx.id;
  st := public._crmh_sla_state(cx.status, cx.due_at, cx.sla_met);
  return jsonb_build_object(
    'id', cx.id, 'ticket_no', cx.ticket_no, 'location_id', cx.location_id, 'location', (select coalesce(l.name_en, l.name_bn) from public.locations l where l.id = cx.location_id),
    'customer_id', cx.customer_id, 'customer_name', cx.customer_name,
    'customer_phone', case when public._crmh_phone_ok(cx.location_id) then cx.customer_phone else public._crmh_mask(cx.customer_phone) end,
    'sale_id', cx.sale_id, 'order_id', cx.order_id, 'item_id', cx.item_id,
    'item_name', (select coalesce(i.name_en, i.name_bn) from public.items i where i.id = cx.item_id),
    'category', cx.category, 'category_label', (select o.label_en from public.option_lists o where o.list_code = 'crm_complaint_cats' and o.value_code = cx.category),
    'severity', cx.severity, 'food_safety', cx.food_safety, 'description', cx.description, 'batch_ref', cx.batch_ref,
    'status', cx.status, 'owner_user', cx.owner_user, 'owner_name', (select p.full_name from public.profiles p where p.id = cx.owner_user),
    'due_at', cx.due_at, 'first_response_at', cx.first_response_at, 'resolved_at', cx.resolved_at, 'resolution_type', cx.resolution_type, 'resolution_note', cx.resolution_note,
    'closed_at', cx.closed_at, 'close_reason', cx.close_reason,
    'sla_state', st, 'sla_met', cx.sla_met, 'breached_at', cx.breached_at,
    'minutes_left', case when st in ('running', 'overdue') then floor(extract(epoch from (cx.due_at - now())) / 60)::int end,
    'repeat_flag', cx.repeat_flag, 'repeat_count', cx.repeat_count, 'returns', ret,
    'created_by', cx.created_by, 'created_staff', cx.created_staff, 'created_at', cx.created_at, 'updated_at', cx.updated_at);
end $$;

-- ============================================================================
-- 6. API
-- ============================================================================
-- 6.1 log a complaint. p keys: location_id, sale_id, order_id, item_id, customer_id, customer_name, customer_phone, category, severity, food_safety, description, batch_ref, owner_user
create or replace function public._crmh_complaint_save(p_client uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); cx public.crm_complaints; s public.sales; o public.online_orders; cu public.customers; it public.items;
        loc int; sale_ uuid; ord_ uuid; item_ uuid; cust_ uuid; cat text; sev text; fs boolean; descr text; nm text; ph text; batch text; own uuid;
        fs_cats text[]; hrs numeric; due timestamptz; prior int := 0; rmin int; rflag boolean := false; fs_min text; t0 timestamptz := now(); item_name text := 'no item named';
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_input'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if p_client is not null then
    select * into cx from public.crm_complaints where client_id = p_client;
    if found then
      if cx.created_by is distinct from uid and not public._crmh_manage_ok(cx.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', cx.id, 'ticket_no', cx.ticket_no, 'due_at', cx.due_at, 'food_safety', cx.food_safety, 'repeat_flag', cx.repeat_flag);
    end if;
  end if;
  sale_ := public._crmh_j_uuid(p, 'sale_id'); ord_ := public._crmh_j_uuid(p, 'order_id'); item_ := public._crmh_j_uuid(p, 'item_id');
  cust_ := public._crmh_j_uuid(p, 'customer_id'); own := public._crmh_j_uuid(p, 'owner_user');
  cat := nullif(btrim(p ->> 'category'), ''); sev := coalesce(nullif(btrim(p ->> 'severity'), ''), 'medium');
  descr := btrim(coalesce(p ->> 'description', '')); nm := nullif(btrim(coalesce(p ->> 'customer_name', '')), ''); ph := nullif(btrim(coalesce(p ->> 'customer_phone', '')), '');
  batch := nullif(btrim(coalesce(p ->> 'batch_ref', '')), ''); fs := public._crmh_j_bool(p, 'food_safety');
  if sev not in ('low', 'medium', 'high', 'critical') then raise exception 'bad_severity'; end if;
  if char_length(descr) < 3 or char_length(descr) > 1000 then raise exception 'description_required'; end if;
  if cat is null or not exists (select 1 from public.option_lists where list_code = 'crm_complaint_cats' and value_code = cat and active) then raise exception 'bad_category'; end if;
  if nm is not null and char_length(nm) > 80 then raise exception 'bad_name'; end if;
  if ph is not null and ph !~ '^[0-9+ -]{6,20}$' then raise exception 'bad_phone'; end if;
  if batch is not null and char_length(batch) > 60 then raise exception 'bad_batch'; end if;
  -- the outlet comes from the sale or the order when one is given; the caller cannot name a different outlet
  if nullif(p ->> 'location_id', '') is not null and (p ->> 'location_id') !~ '^[0-9]{1,9}$' then raise exception 'bad_location'; end if;
  loc := nullif(p ->> 'location_id', '')::int;
  if sale_ is not null then
    select * into s from public.sales where id = sale_;
    if not found then raise exception 'sale_not_found'; end if;
    if loc is not null and loc <> s.location_id then raise exception 'sale_other_outlet'; end if;
    loc := s.location_id; if cust_ is null then cust_ := s.customer_id; end if;
  end if;
  if ord_ is not null then
    select * into o from public.online_orders where id = ord_;
    if not found then raise exception 'order_not_found'; end if;
    if loc is not null and loc <> o.location_id then raise exception 'order_other_outlet'; end if;
    loc := o.location_id;
    if sale_ is null and o.sale_id is not null then sale_ := o.sale_id; select * into s from public.sales where id = sale_; end if;
    if nm is null then nm := left(o.customer_name, 80); end if; if ph is null and o.customer_mobile ~ '^[0-9+ -]{6,20}$' then ph := o.customer_mobile; end if;
  end if;
  if loc is null then raise exception 'location_required'; end if;
  if not exists (select 1 from public.locations where id = loc and is_active) then raise exception 'bad_location'; end if;
  if not public._crmh_log_ok(loc) then raise exception 'not allowed'; end if;
  if item_ is not null then
    select * into it from public.items where id = item_;
    if not found then raise exception 'item_not_found'; end if;
    item_name := coalesce(it.name_en, it.name_bn);
    if sale_ is not null and jsonb_typeof(s.lines) = 'array' and jsonb_array_length(s.lines) > 0
       and not exists (select 1 from jsonb_array_elements(s.lines) e where e ->> 'item_id' = item_::text) then raise exception 'item_not_in_sale'; end if;
  end if;
  if cust_ is not null then
    select * into cu from public.customers where id = cust_;
    if not found then raise exception 'customer_not_found'; end if;
    if nm is null then nm := left(cu.name, 80); end if; if ph is null and cu.mobile ~ '^[0-9+ -]{6,20}$' then ph := cu.mobile; end if;
  end if;
  if own is not null then
    if not public._crmh_manage_ok(loc) then raise exception 'not allowed'; end if;
    if not public._crmh_user_loc_ok(own, loc) then raise exception 'owner_other_outlet'; end if;
  end if;
  -- food safety: the box, or a category the owner listed
  fs_cats := string_to_array(replace(coalesce(public.rule_txt('crm_complaint_fs_categories'), ''), ' ', ''), ',');
  if cat = any (fs_cats) then fs := true; end if;
  fs_min := coalesce(public.rule_txt('crm_complaint_fs_severity'), 'keep');
  if fs and fs_min = 'high' and sev in ('low', 'medium') then sev := 'high'; end if;
  if fs and fs_min = 'critical' then sev := 'critical'; end if;
  hrs := public._crmh_sla_hours(sev);
  due := case when hrs is null then null else t0 + hrs * interval '1 hour' end;
  -- repeat check (off while crm_repeat_days is blank)
  prior := public._crmh_repeat_prior(cust_, ph, item_, t0);
  rmin := coalesce(public.rule_num('crm_repeat_min'), 2)::int;
  rflag := public.rule_num('crm_repeat_days') is not null and (prior + 1) >= rmin;
  insert into public.crm_complaints (client_id, location_id, customer_id, customer_name, customer_phone, sale_id, order_id, item_id, category, severity, food_safety, description, batch_ref,
                                     status, owner_user, due_at, repeat_flag, repeat_count, created_by, created_staff, created_at)
    values (p_client, loc, cust_, nm, ph, sale_, ord_, item_, cat, sev, fs, descr, batch, 'open', own, due, rflag, prior, uid, public._crmh_staff(), t0)
    returning * into cx;
  perform public._crmh_ev(cx.id, 'created', null, 'open', descr);
  if own is not null then perform public._crmh_ev(cx.id, 'assigned', null, null, 'owner set when logged'); end if;
  if fs then
    perform public._crmh_ev(cx.id, 'food_safety', null, null, 'marked food safety');
    if public.rule_on('crm_complaint_fs_exception_on') then
      perform public._crmh_exc(loc, 'crmh_food_safety', 'red', 'Food-safety complaint no. ' || cx.ticket_no || ' (' || item_name || ')', cx.id::text);
    end if;
  end if;
  if rflag then perform public._crmh_ev(cx.id, 'repeat', null, null, 'repeat complaint: ' || prior || ' earlier in the last ' || public.rule_num('crm_repeat_days')::int || ' days'); end if;
  perform public._crmh_audit('crmh_complaint_new', cx.id::text, jsonb_build_object('ticket_no', cx.ticket_no, 'severity', sev, 'food_safety', fs, 'repeat', rflag));
  return jsonb_build_object('dup', false, 'id', cx.id, 'ticket_no', cx.ticket_no, 'due_at', cx.due_at, 'severity', sev, 'food_safety', fs, 'repeat_flag', rflag, 'repeat_count', prior);
end $function$;

-- 6.2 set (or clear) the person who owns a complaint
create or replace function public._crmh_complaint_assign(p_id uuid, p_user uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not public._crmh_manage_ok(cx.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status not in ('open', 'in_progress') then raise exception 'complaint_locked'; end if;
  if p_user is not null and not public._crmh_user_loc_ok(p_user, cx.location_id) then raise exception 'owner_other_outlet'; end if;
  if cx.owner_user is not distinct from p_user then return public._crmh_row(cx); end if;
  update public.crm_complaints set owner_user = p_user where id = p_id returning * into cx;
  perform public._crmh_ev(cx.id, 'assigned', null, null, coalesce(nullif(btrim(p_note), ''), case when p_user is null then 'owner cleared' else 'owner set' end));
  return public._crmh_row(cx);
end $function$;

-- 6.3 add a note, or record that the customer was contacted (the first contact stops the "first response" clock)
create or replace function public._crmh_complaint_note(p_id uuid, p_kind text, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; b text := btrim(coalesce(p_body, ''));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_kind not in ('note', 'contact') then raise exception 'bad_kind'; end if;
  if char_length(b) < 3 or char_length(b) > 1000 then raise exception 'note_required'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not (public._crmh_manage_ok(cx.location_id) or (coalesce(cx.owner_user = auth.uid(), false) and public.can_loc(cx.location_id))) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  if p_kind = 'contact' and cx.first_response_at is null then update public.crm_complaints set first_response_at = now() where id = p_id returning * into cx; end if;
  perform public._crmh_ev(cx.id, p_kind, null, null, b);
  return public._crmh_row(cx);
end $function$;

-- marks one overdue complaint (no new status; breached_at + one event + one yellow Exceptions line when the setting is ON)
create or replace function public._crmh_mark_breach(p_id uuid) returns boolean language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints;
begin
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found or cx.breached_at is not null or cx.due_at is null or now() <= cx.due_at then return false; end if;
  update public.crm_complaints set breached_at = now() where id = p_id returning * into cx;
  perform public._crmh_ev(cx.id, 'sla_breach', cx.status, cx.status, 'target was ' || to_char(cx.due_at at time zone 'Asia/Dhaka', 'DD Mon HH24:MI'));
  perform public._crmh_audit('crmh_sla_breach', cx.id::text, jsonb_build_object('ticket_no', cx.ticket_no, 'due_at', cx.due_at, 'severity', cx.severity));
  if public.rule_on('crm_complaint_breach_exception_on') then
    perform public._crmh_exc(cx.location_id, 'crmh_sla_breach', case when cx.food_safety then 'red' else 'yellow' end, 'Complaint no. ' || cx.ticket_no || ' is overdue (' || cx.severity || ')', cx.id::text);
  end if;
  return true;
end $function$;

-- 6.4 move a complaint along. p_to: in_progress | resolved | closed | closed_no_resolution | in_progress again from resolved (reopen)
create or replace function public._crmh_complaint_move(p_id uuid, p_to text, p_note text default null, p_resolution text default null, p_close_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; uid uuid := auth.uid(); b text := btrim(coalesce(p_note, '')); mgr boolean; own boolean; from_ text; met boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_to not in ('in_progress', 'resolved', 'closed', 'closed_no_resolution') then raise exception 'illegal_status_change'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  mgr := public._crmh_manage_ok(cx.location_id); own := coalesce(cx.owner_user = uid, false) and public.can_loc(cx.location_id);
  if not (mgr or own) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  from_ := cx.status;
  if not ((from_ = 'open' and p_to in ('in_progress', 'resolved', 'closed_no_resolution'))
       or (from_ = 'in_progress' and p_to in ('resolved', 'closed_no_resolution'))
       or (from_ = 'resolved' and p_to in ('closed', 'in_progress'))) then raise exception 'illegal_status_change'; end if;
  -- the person who only owns the complaint may start it and resolve it; closing, closing without a result and reopening are for the managers
  if not mgr and p_to in ('closed', 'closed_no_resolution') then raise exception 'not allowed'; end if;
  if not mgr and from_ = 'resolved' then raise exception 'not allowed'; end if;

  if p_to = 'in_progress' and from_ = 'open' then
    update public.crm_complaints set status = 'in_progress', first_response_at = coalesce(first_response_at, now()), owner_user = coalesce(owner_user, uid) where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'in_progress', nullif(b, ''));
  elsif p_to = 'in_progress' then                                           -- reopen a resolved complaint: needs a reason
    if char_length(b) < 3 then raise exception 'reason_required'; end if;
    update public.crm_complaints set status = 'in_progress', resolved_at = null, resolution_type = null, resolution_note = null, sla_met = null where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'reopen', from_, 'in_progress', b);
    perform public._crmh_audit('crmh_complaint_reopen', cx.id::text, jsonb_build_object('reason', b));
  elsif p_to = 'resolved' then
    if p_resolution is null or not exists (select 1 from public.option_lists where list_code = 'crm_resolution_types' and value_code = p_resolution and active) or char_length(b) < 3 then raise exception 'resolution_required'; end if;
    met := case when cx.due_at is null then null else now() <= cx.due_at end;
    update public.crm_complaints set status = 'resolved', resolved_at = now(), resolution_type = p_resolution, resolution_note = left(b, 1000), sla_met = met,
           first_response_at = coalesce(first_response_at, now()) where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'resolved', b);
    if met is false then perform public._crmh_mark_breach(cx.id); select * into cx from public.crm_complaints where id = p_id; end if;
  elsif p_to = 'closed' then
    update public.crm_complaints set status = 'closed', closed_at = now() where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'closed', nullif(b, ''));
  else                                                                       -- closed_no_resolution: an exception with a reason (owner rule 3)
    if p_close_reason is null or not exists (select 1 from public.option_lists where list_code = 'crm_close_reasons' and value_code = p_close_reason and active) or char_length(b) < 3 then raise exception 'reason_required'; end if;
    update public.crm_complaints set status = 'closed_no_resolution', closed_at = now(), close_reason = p_close_reason, sla_met = null where id = p_id returning * into cx;
    perform public._crmh_ev(cx.id, 'status', from_, 'closed_no_resolution', p_close_reason || ': ' || b);
    perform public._crmh_audit('crmh_closed_no_resolution', cx.id::text, jsonb_build_object('reason_code', p_close_reason, 'note', b, 'food_safety', cx.food_safety));
    perform public._crmh_exc(cx.location_id, 'crmh_closed_unresolved', case when cx.food_safety then 'red' else 'yellow' end,
                             'Complaint no. ' || cx.ticket_no || ' closed without a result (' || p_close_reason || ')', cx.id::text);
  end if;
  return public._crmh_row(cx);
end $function$;

-- 6.5 change the severity (the clock restarts from the time the complaint was logged, with the new target)
create or replace function public._crmh_complaint_severity_set(p_id uuid, p_severity text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; hrs numeric; b text := btrim(coalesce(p_note, ''));
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_severity not in ('low', 'medium', 'high', 'critical') then raise exception 'bad_severity'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not public._crmh_manage_ok(cx.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  if cx.severity = p_severity then return public._crmh_row(cx); end if;
  if char_length(b) < 3 then raise exception 'reason_required'; end if;
  hrs := public._crmh_sla_hours(p_severity);
  update public.crm_complaints set severity = p_severity, due_at = case when hrs is null then null else created_at + hrs * interval '1 hour' end where id = p_id returning * into cx;
  perform public._crmh_ev(cx.id, 'severity', null, null, cx.severity || ': ' || b);
  perform public._crmh_audit('crmh_severity_change', cx.id::text, jsonb_build_object('to', p_severity, 'reason', b));
  return public._crmh_row(cx);
end $function$;

-- 6.6 link a finished sale return to a complaint. READ ONLY on sale_returns: no refund is made, nothing is posted. The refund is made on the sale return screen first.
create or replace function public._crmh_complaint_link_return(p_id uuid, p_return uuid) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare cx public.crm_complaints; r public.sale_returns; other uuid;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into cx from public.crm_complaints where id = p_id for update;
  if not found then raise exception 'complaint_not_found'; end if;
  if not public._crmh_manage_ok(cx.location_id) then raise exception 'not allowed'; end if;
  if not public.rule_on('crm_complaints_on') then raise exception 'complaints_off'; end if;
  select * into r from public.sale_returns where id = p_return;
  if not found then raise exception 'return_not_found'; end if;
  if r.status <> 'done' then raise exception 'return_not_done'; end if;
  if r.location_id <> cx.location_id then raise exception 'return_other_outlet'; end if;
  if cx.sale_id is not null and cx.sale_id <> r.sale_id then raise exception 'return_other_sale'; end if;
  select complaint_id into other from public.crm_complaint_returns where return_id = p_return;
  if other is not null then
    if other = p_id then return public._crmh_row(cx); end if;
    raise exception 'return_already_linked';
  end if;
  if cx.status in ('closed', 'closed_no_resolution') then raise exception 'complaint_locked'; end if;
  insert into public.crm_complaint_returns (complaint_id, return_id, linked_by) values (p_id, p_return, auth.uid());
  if cx.sale_id is null then update public.crm_complaints set sale_id = r.sale_id where id = p_id returning * into cx; end if;
  perform public._crmh_ev(cx.id, 'link_return', null, null, 'sale return linked, value ' || r.amount);
  perform public._crmh_audit('crmh_link_return', cx.id::text, jsonb_build_object('return_id', p_return, 'amount', r.amount));
  return public._crmh_row(cx);
end $function$;

-- 6.7 the list. p keys: status (active | all | open | in_progress | resolved | closed | closed_no_resolution; default active), location_id, severity, food_safety, overdue, mine, repeat, item_id, customer_id, from, to, limit, offset
create or replace function public._crmh_complaint_list(p jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); st text := coalesce(nullif(p ->> 'status', ''), 'active'); loc int := nullif(p ->> 'location_id', '')::int; sev text := nullif(p ->> 'severity', '');
        d1 date := nullif(p ->> 'from', '')::date; d2 date := nullif(p ->> 'to', '')::date; lim int := least(greatest(coalesce(nullif(p ->> 'limit', '')::int, 30), 1), 100); off_ int := greatest(coalesce(nullif(p ->> 'offset', '')::int, 0), 0);
        item_ uuid := public._crmh_j_uuid(p, 'item_id'); cust_ uuid := public._crmh_j_uuid(p, 'customer_id'); rows jsonb; total int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if st not in ('active', 'all', 'open', 'in_progress', 'resolved', 'closed', 'closed_no_resolution') then raise exception 'bad_status'; end if;
  if sev is not null and sev not in ('low', 'medium', 'high', 'critical') then raise exception 'bad_severity'; end if;
  with f as (
    select x.* from public.crm_complaints x
     where (public._crmh_view_ok(x.location_id) or x.created_by = uid or (x.owner_user = uid and public.can_loc(x.location_id)))
       and (loc is null or x.location_id = loc)
       and (st = 'all' or (st = 'active' and x.status in ('open', 'in_progress')) or x.status = st)
       and (sev is null or x.severity = sev)
       and (not public._crmh_j_bool(p, 'food_safety') or x.food_safety)
       and (not public._crmh_j_bool(p, 'repeat') or x.repeat_flag)
       and (not public._crmh_j_bool(p, 'mine') or x.owner_user = uid)
       and (not public._crmh_j_bool(p, 'overdue') or (x.status in ('open', 'in_progress') and x.due_at is not null and now() > x.due_at))
       and (item_ is null or x.item_id = item_) and (cust_ is null or x.customer_id = cust_)
       and (d1 is null or (x.created_at at time zone 'Asia/Dhaka')::date >= d1) and (d2 is null or (x.created_at at time zone 'Asia/Dhaka')::date <= d2)),
  pg as (
    select f.id, row_number() over (order by case when f.status in ('open', 'in_progress') and f.due_at is not null and now() > f.due_at then 0 when f.food_safety and f.status in ('open', 'in_progress') then 1 else 2 end,
                                             f.due_at nulls last, f.created_at desc) as ord
      from f order by ord limit lim offset off_)
  select (select count(*) from f), coalesce((select jsonb_agg(public._crmh_row(c2) order by pg.ord) from pg join public.crm_complaints c2 on c2.id = pg.id), '[]'::jsonb) into total, rows;
  return jsonb_build_object('total', total, 'rows', rows, 'limit', lim, 'offset', off_, 'on', public.rule_on('crm_complaints_on'));
end $function$;

-- 6.8 one complaint with its trail and the linked returns. Also tells the screen which existing sale return to open (the refund is made THERE).
create or replace function public._crmh_complaint_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare cx public.crm_complaints; uid uuid := auth.uid(); ev jsonb; rets jsonb; hint jsonb := null; prev jsonb; s public.sales;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into cx from public.crm_complaints where id = p_id;
  if not found then raise exception 'complaint_not_found'; end if;
  if not (public._crmh_view_ok(cx.location_id) or cx.created_by = uid or (coalesce(cx.owner_user = uid, false) and public.can_loc(cx.location_id))) then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff) order by e.id), '[]'::jsonb) into ev
    from public.crm_complaint_events e where e.complaint_id = p_id;
  select coalesce(jsonb_agg(jsonb_build_object('return_id', r.id, 'amount', r.amount, 'refund', r.refund_amount, 'credit', r.credit_amount, 'status', r.status, 'at', r.created_at) order by lr.id), '[]'::jsonb) into rets
    from public.crm_complaint_returns lr join public.sale_returns r on r.id = lr.return_id where lr.complaint_id = p_id;
  if cx.sale_id is not null then
    select * into s from public.sales where id = cx.sale_id;
    hint := jsonb_build_object('sale_id', s.id, 'receipt', s.receipt, 'sold_at', s.sold_at, 'total', s.total,
                               'can_return', public.has_grant('sale_return', s.location_id), 'open', 'B.saleReturn.open(sale_id)',
                               'note', 'Make the refund on the sale return screen first, then link the finished return here. This screen never refunds.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'ticket_no', x.ticket_no, 'at', x.created_at, 'status', x.status, 'category', x.category) order by x.created_at desc), '[]'::jsonb) into prev
    from (select * from public.crm_complaints z where z.id <> p_id and z.created_at < cx.created_at
            and ((cx.customer_id is not null and z.customer_id = cx.customer_id)
                 or (nullif(public.norm_mobile(cx.customer_phone), '') is not null and public.norm_mobile(z.customer_phone) = public.norm_mobile(cx.customer_phone)))
            and (public._crmh_view_ok(z.location_id) or z.created_by = uid)
          order by z.created_at desc limit 10) x;
  return jsonb_build_object('complaint', public._crmh_row(cx), 'events', ev, 'returns', rets, 'return_hint', hint, 'earlier_by_same_customer', prev,
                            'can_manage', public._crmh_manage_ok(cx.location_id));
end $function$;

-- 6.9 the overdue check. Marks every open complaint that has passed its due time (once each). A dry run writes nothing and works while the switch is OFF.
--     Called by the owner, by a holder of crm_complaint_manage (their outlets only), by the notify bot (see docs/integration/CRM-H.md), or by the database's own scheduler.
create or replace function public._crmh_sla_scan(p_dry boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $function$
declare uid uuid := auth.uid(); via text; r record; n int := 0; ids jsonb := '[]'::jsonb; all_ boolean := false;
begin
  if uid is not null then
    all_ := public._is_ops('notify') or public.is_owner();
    if not (all_ or (public.is_active() and exists (select 1 from public.locations l where public._crmh_manage_ok(l.id)))) then raise exception 'not allowed'; end if;
    via := case when public._is_ops('notify') then 'notify_bot' else 'manual' end;
  else
    if not (session_user in ('postgres', 'supabase_admin') and coalesce(nullif(current_setting('role', true), ''), 'none') = 'none') then raise exception 'not allowed'; end if;
    all_ := true; via := 'database_scheduler';
  end if;
  if not p_dry and not public.rule_on('crm_complaints_on') then return jsonb_build_object('ran', false, 'skipped', 'switch_off'); end if;
  for r in select x.id, x.ticket_no, x.location_id from public.crm_complaints x
            where x.status in ('open', 'in_progress') and x.due_at is not null and now() > x.due_at and x.breached_at is null
              and (all_ or public._crmh_manage_ok(x.location_id)) order by x.due_at loop
    if p_dry then n := n + 1; ids := ids || to_jsonb(r.ticket_no);
    elsif public._crmh_mark_breach(r.id) then n := n + 1; ids := ids || to_jsonb(r.ticket_no); end if;
  end loop;
  return jsonb_build_object('ran', not p_dry, 'dry', p_dry, 'marked', n, 'tickets', ids, 'via', via);
end $function$;

-- 6.10 small numbers for a badge (only the outlets the caller may see)
create or replace function public._crmh_counts() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
declare uid uuid := auth.uid(); r record;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select count(*) filter (where x.status in ('open', 'in_progress')) as open_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.due_at is not null and now() > x.due_at) as overdue_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.food_safety) as fs_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.repeat_flag) as repeat_n,
         count(*) filter (where x.status in ('open', 'in_progress') and x.owner_user is null) as unowned_n
    into r from public.crm_complaints x where public._crmh_view_ok(x.location_id) or x.created_by = uid or (x.owner_user = uid and public.can_loc(x.location_id));
  return jsonb_build_object('on', public.rule_on('crm_complaints_on'), 'open', r.open_n, 'overdue', r.overdue_n, 'food_safety', r.fs_n, 'repeat', r.repeat_n, 'unowned', r.unowned_n);
end $function$;

-- 6.11 the effective settings and lists, for the screen
create or replace function public._crmh_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $function$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'on', public.rule_on('crm_complaints_on'),
    'sla_hours', jsonb_build_object('low', public._crmh_sla_hours('low'), 'medium', public._crmh_sla_hours('medium'), 'high', public._crmh_sla_hours('high'), 'critical', public._crmh_sla_hours('critical')),
    'fs_exception_on', public.rule_on('crm_complaint_fs_exception_on'), 'fs_categories', public.rule_txt('crm_complaint_fs_categories'), 'fs_severity', coalesce(public.rule_txt('crm_complaint_fs_severity'), 'keep'),
    'breach_exception_on', public.rule_on('crm_complaint_breach_exception_on'),
    'repeat_days', public.rule_num('crm_repeat_days'), 'repeat_min', coalesce(public.rule_num('crm_repeat_min'), 2), 'repeat_scope', coalesce(public.rule_txt('crm_repeat_scope'), 'customer_item'),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('code', o.value_code, 'label', o.label_en) order by o.sort, o.value_code), '[]'::jsonb) from public.option_lists o where o.list_code = 'crm_complaint_cats' and o.active),
    'resolutions', (select coalesce(jsonb_agg(jsonb_build_object('code', o.value_code, 'label', o.label_en) order by o.sort, o.value_code), '[]'::jsonb) from public.option_lists o where o.list_code = 'crm_resolution_types' and o.active),
    'close_reasons', (select coalesce(jsonb_agg(jsonb_build_object('code', o.value_code, 'label', o.label_en) order by o.sort, o.value_code), '[]'::jsonb) from public.option_lists o where o.list_code = 'crm_close_reasons' and o.active),
    'may_log', exists (select 1 from public.locations l where l.is_active and public._crmh_log_ok(l.id)),
    'may_manage', exists (select 1 from public.locations l where l.is_active and public._crmh_manage_ok(l.id)),
    'may_view', exists (select 1 from public.locations l where l.is_active and public._crmh_view_ok(l.id)),
    'is_owner', public.is_owner());
end $function$;

-- ============================================================================
-- 7. PRIVILEGES: helpers closed to browsers; the API is open to signed-in users only (each function checks its own right)
-- ============================================================================
revoke all on function public._crmh_present(), public._crmh_append_only(), public._crmh_complaint_guard(), public._crmh_staff(), public._crmh_log_ok(int), public._crmh_manage_ok(int), public._crmh_view_ok(int),
  public._crmh_phone_ok(int), public._crmh_mask(text), public._crmh_j_uuid(jsonb, text), public._crmh_j_bool(jsonb, text), public._crmh_sla_hours(text), public._crmh_sla_state(text, timestamptz, boolean),
  public._crmh_ev(uuid, text, text, text, text), public._crmh_audit(text, text, jsonb), public._crmh_exc(int, text, text, text, text), public._crmh_user_loc_ok(uuid, int),
  public._crmh_repeat_prior(uuid, text, uuid, timestamptz), public._crmh_row(public.crm_complaints), public._crmh_mark_breach(uuid) from public, anon, authenticated;
revoke all on function public._crmh_complaint_save(uuid, jsonb), public._crmh_complaint_assign(uuid, uuid, text), public._crmh_complaint_note(uuid, text, text),
  public._crmh_complaint_move(uuid, text, text, text, text), public._crmh_complaint_severity_set(uuid, text, text), public._crmh_complaint_link_return(uuid, uuid),
  public._crmh_complaint_list(jsonb), public._crmh_complaint_get(uuid), public._crmh_sla_scan(boolean), public._crmh_counts(), public._crmh_settings() from public, anon, authenticated;
grant execute on function public._crmh_complaint_save(uuid, jsonb), public._crmh_complaint_assign(uuid, uuid, text), public._crmh_complaint_note(uuid, text, text),
  public._crmh_complaint_move(uuid, text, text, text, text), public._crmh_complaint_severity_set(uuid, text, text), public._crmh_complaint_link_return(uuid, uuid),
  public._crmh_complaint_list(jsonb), public._crmh_complaint_get(uuid), public._crmh_sla_scan(boolean), public._crmh_counts(), public._crmh_settings() to authenticated;
