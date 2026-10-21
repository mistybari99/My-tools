-- Phase 323 (bos323, package CRM-G label 123, part 1 of 5) - ENQUIRY AND LEAD PIPELINE, TASKS: SETTINGS, RIGHTS, LISTS, TABLES, GUARDS.
-- Paste AFTER phase98 (needs the rules table, grants, the Exceptions list of phase87, online orders of phase61/76, notifications). Paste-twice safe.
-- No earlier phase file is edited and no shared function is re-created: every new name starts crm_ (tables) or _crmg_ (functions). Nothing here posts to the books.
--
-- WHAT THE FIVE FILES ADD
--   323  settings (rules, module crm, all OFF or blank), rights (grants), three owner-editable lists (lost reasons, sources, occasions), the tables, their guards
--   324  leads: save, notes, assign, stage moves, lost with a reason, reopen with a reason (an exception), quotes with items and validity, one lead
--   325  convert a won lead through the EXISTING order functions (online_order_save2 / save_entry) or link an existing record; lead list, board, win/loss report
--   326  tasks: add, done, snooze, skip, reassign, My tasks, counts for the Home strip, optional in-app reminders (OFF)
--   327  settings overview, hook state, readiness check
--
-- OWNER RULES MET: (1) every policy is a setting with a safe default; modules are OFF; nothing starts by itself; no reminder unless switched on.
-- (2) a lead, a quote and a task post NOTHING (no journal, no sale, no payment, no stock). (3) exceptions with a reason: reopen a lost lead, late quote,
-- win without a quote. (4) no approver is hard-coded: rights are grants the owner gives to roles or people. (5) English labels only. (7) a lead is visible to
-- the owner, to holders of crm_lead_all, and otherwise only inside the outlets the person works in (assignee, maker or holder of crm_lead_manage).

do $g$ begin
  if to_regprocedure('public._w1g_present()') is null then raise exception 'phase323 needs phase98 (and 80-97) first'; end if;
  if to_regclass('public.money_exceptions') is null or to_regclass('public.notifications') is null or to_regclass('public.online_orders') is null
     or to_regprocedure('public.online_order_save2(uuid,uuid,integer,integer,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text,text,text,text,text,text,bigint,boolean)') is null
     or to_regprocedure('public.save_entry(uuid,text,integer,date,jsonb,jsonb,text,jsonb)') is null then
    raise exception 'phase323 needs the online order channel (phase 61, 76), the paper forms (phase 17) and the Exceptions list (phase 87)';
  end if;
end $g$;

create or replace function public._crmg_present() returns boolean language sql immutable as $$ select true $$;

-- ============================================================================
-- 1. EXCEPTIONS LIST: three more kinds (additive: keeps every kind another package added; same method as phase94)
-- ============================================================================
create or replace function public._crmg_add_exc_kinds(p_kinds text[]) returns void language plpgsql set search_path = public as $$
declare con text; def text; cur text[]; allk text[]; k text;
begin
  select c.conname, pg_get_constraintdef(c.oid) into con, def from pg_constraint c
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%';
  if con is null then raise exception 'phase323: money_exceptions kind check not found'; end if;
  select array_agg(m[1]) into cur from regexp_matches(def, '''([a-z_0-9]+)''', 'g') m;
  if cur is null then cur := string_to_array(substring(def from '\{([^}]*)\}'), ','); end if;
  if cur is null or cardinality(cur) = 0 then raise exception 'phase323: money_exceptions kind check has an unknown shape'; end if;
  allk := cur;
  foreach k in array p_kinds loop if not (k = any (allk)) then allk := allk || k; end if; end loop;
  if allk = cur then return; end if;
  execute format('alter table public.money_exceptions drop constraint %I', con);
  execute format('alter table public.money_exceptions add constraint %I check (kind = any (array[%s]))', con, (select string_agg(quote_literal(x), ', ' order by x) from unnest(allk) x));
end $$;
select public._crmg_add_exc_kinds(array['crmg_lead_reopen', 'crmg_late_quote', 'crmg_win_without_quote']);

-- ============================================================================
-- 2. SETTINGS (rules, module crm). Every row: safe default, plain English label and hint. Changes are logged by the existing audit_rules trigger.
-- ============================================================================
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
select v.key, 'crm', v.kind, v.dv, v.unit, v.ch, v.mn, v.mx, v.lab, v.lab, v.lab, v.hint, v.hint, v.hint, v.srt
  from (values
 ('crm_lead_on', 'switch', 'false'::jsonb, null::text, null::jsonb, null::numeric, null::numeric,
   'Track party, wholesale, corporate and gift enquiries',
   'OFF = no lead screens work (today). ON = staff can record an enquiry, send a quote, follow it up and mark it won or lost. A lead or quote never posts to the books.', 3200),
 ('crm_task_on', 'switch', 'false'::jsonb, null, null, null, null,
   'Use follow-up tasks and the My tasks list',
   'OFF = no task can be added (today). ON = staff can add a task with a due time, tick it done, snooze it, and see overdue ones on My tasks. A task never posts to the books.', 3201),
 ('crm_lead_lost_by', 'choice', '"manager"'::jsonb, null, '["manager","assignee"]'::jsonb, null, null,
   'Who may close an enquiry as lost',
   'manager = only the owner or a person holding the right Manage enquiries (default). assignee = the person the enquiry is assigned to may also close it. A lost reason from the list is always needed.', 3202),
 ('crm_lead_reopen_mode', 'choice', '"reason"'::jsonb, null, '["reason","owner","off"]'::jsonb, null, null,
   'Reopening a lost enquiry',
   'reason = a manager may reopen with a written reason; it goes to the Exceptions list (default). owner = only the owner may reopen. off = a lost enquiry can never be reopened (start a new one).', 3203),
 ('crm_lead_win_needs_quote', 'switch', 'false'::jsonb, null, null, null, null,
   'An enquiry can be won only after a quote was sent',
   'OFF = an enquiry can be marked won without a quote (today). ON = a sent quote is needed first; a manager can still win it with a written reason, which goes to the Exceptions list.', 3204),
 ('crm_lead_quote_valid_days', 'number', null, 'days', null, 1::numeric, 365::numeric,
   'Quote validity: default number of days',
   'Blank = the person must type the valid-until date for every quote (a quote without a date is refused). A number = the date is filled in as today plus this many days; it can still be changed.', 3205),
 ('crm_quote_min_lead_days', 'number', null, 'days', null, 0::numeric, 365::numeric,
   'Late quote: least days between the quote and the event',
   'Blank = no check. A number = a quote sent when the event is closer than this many days (or already past), or with a valid-until date in the past, needs a written reason and goes to the Exceptions list.', 3206),
 ('crm_lead_stale_days', 'number', null, 'days', null, 1::numeric, 365::numeric,
   'Flag an open enquiry as stale after this many days of silence',
   'Blank = no stale flag. A number = an open enquiry with no note, quote or stage change for this many days shows a Stale flag on the board and in the report.', 3207),
 ('crm_lead_list_add_mode', 'choice', '"owner"'::jsonb, null, '["owner","manager"]'::jsonb, null, null,
   'Who may add a lost reason, source or occasion to the lists',
   'owner = only the owner (default). manager = also a person holding the right Manage enquiries. The entry Other can never be removed.', 3208),
 ('crm_task_default_due_hours', 'number', null, 'hours', null, 1::numeric, 720::numeric,
   'Task due time when none is typed',
   'Blank = a task must have a due date and time typed (a task without one is refused). A number = the due time is filled in as now plus this many hours.', 3209),
 ('crm_task_snooze_max_days', 'number', null, 'days', null, 1::numeric, 90::numeric,
   'Longest snooze for a task',
   'Blank = no limit on how far a task can be snoozed. A number = a snooze cannot go further than this many days from now.', 3210),
 ('crm_order_task_days', 'number', null, 'days', null, 0::numeric, 30::numeric,
   'Add a delivery task when an enquiry becomes an order',
   'Blank = no task is added (today). A number = when a won enquiry is turned into an order that has a delivery date, a task for the assigned person is added that many days before the delivery (0 = on the day). It closes by itself when the order is delivered or cancelled. Needs tasks switched on.', 3212),
 ('crm_task_reminder_on', 'switch', 'false'::jsonb, null, null, null, null,
   'Send staff an in-app reminder for due tasks and stale enquiries',
   'OFF = nothing is sent; staff only see their list when they open My tasks (today). ON = the 30-minute notify job adds one in-app line per person per day with counts only (no customer name or phone). It never messages a customer.', 3211)
  ) as v(key, kind, dv, unit, ch, mn, mx, lab, hint, srt)
on conflict (key) do nothing;

-- ============================================================================
-- 3. RIGHTS (grants). None is given to anyone by default except through the owner.
-- ============================================================================
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('crm_lead_manage', 'crm', 3200, 'Manage enquiries of my outlets (see all, assign, close as lost, reopen, convert)', 'Manage enquiries of my outlets (see all, assign, close as lost, reopen, convert)', 'Manage enquiries of my outlets (see all, assign, close as lost, reopen, convert)', 'once', null),
 ('crm_lead_all', 'crm', 3201, 'See and work on the enquiries of every outlet', 'See and work on the enquiries of every outlet', 'See and work on the enquiries of every outlet', 'once', null),
 ('crm_task_assign', 'crm', 3202, 'Give tasks to other people', 'Give tasks to other people', 'Give tasks to other people', 'once', null),
 ('crm_task_all', 'crm', 3203, 'See the tasks of every person', 'See the tasks of every person', 'See the tasks of every person', 'once', null)
on conflict (grant_code) do nothing;

-- ============================================================================
-- 4. LISTS (lost reasons, sources, occasions). Rule 4 of the build rules: every list has Add new and Other; nothing is deleted, an entry is retired.
-- ============================================================================
create table if not exists public.crm_lead_lists (
  kind text not null check (kind in ('lost_reason', 'source', 'occasion')),
  code text not null check (code ~ '^[a-z][a-z0-9_]{1,30}$'),
  label text not null check (char_length(btrim(label)) between 1 and 60),
  active boolean not null default true,
  sort int not null default 100,
  created_by uuid, created_at timestamptz not null default now(),
  primary key (kind, code)
);
insert into public.crm_lead_lists (kind, code, label, sort) values
 ('lost_reason', 'price_high', 'Price was too high', 10), ('lost_reason', 'other_shop', 'Chose another shop', 20), ('lost_reason', 'date_not_possible', 'We could not do the date', 30),
 ('lost_reason', 'plan_cancelled', 'The plan was cancelled', 40), ('lost_reason', 'no_reply', 'No reply after follow-ups', 50), ('lost_reason', 'other', 'Other (write a note)', 900),
 ('source', 'walk_in', 'Walked in', 10), ('source', 'phone', 'Phone call', 20), ('source', 'message', 'Message', 30), ('source', 'web_form', 'Web form', 40),
 ('source', 'referral', 'Referred by someone', 50), ('source', 'other', 'Other', 900),
 ('occasion', 'birthday', 'Birthday', 10), ('occasion', 'wedding', 'Wedding or engagement', 20), ('occasion', 'corporate', 'Corporate or office', 30),
 ('occasion', 'wholesale', 'Wholesale', 40), ('occasion', 'gift', 'Gift box or hamper', 50), ('occasion', 'festival', 'Festival', 60), ('occasion', 'other', 'Other', 900)
on conflict (kind, code) do nothing;

-- ============================================================================
-- 5. TABLES (RLS on, closed to browser roles, read and written only through the definer functions of phases 324 to 327)
-- ============================================================================
create table if not exists public.crm_leads (
  id uuid primary key default gen_random_uuid(),
  lead_no bigint generated always as identity,
  client_id uuid,
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  contact_name text not null check (char_length(btrim(contact_name)) between 1 and 80),
  contact_phone text check (contact_phone is null or char_length(contact_phone) between 6 and 20),
  source text,
  inbound_message_id bigint,
  occasion text,
  event_date date,
  guests int check (guests is null or guests between 1 and 100000),
  est_value numeric check (est_value is null or (est_value >= 0 and est_value <= 1000000000000)),
  stage text not null default 'enquiry' check (stage in ('enquiry', 'quoted', 'following_up', 'won', 'lost')),
  lost_reason text,
  lost_note text check (lost_note is null or char_length(lost_note) <= 300),
  owner_user uuid not null,
  next_follow_up timestamptz,
  quote_ref text check (quote_ref is null or char_length(quote_ref) <= 80),
  online_order_id uuid references public.online_orders(id),
  entry_id uuid references public.entries(id),
  converted_at timestamptz, converted_by uuid, convert_client uuid,
  reopened_count int not null default 0,
  note text check (note is null or char_length(note) <= 300),
  stage_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  closed_at timestamptz,
  created_by uuid not null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check ((stage = 'lost') = (lost_reason is not null)),
  check (online_order_id is null or entry_id is null)
);
create unique index if not exists crm_leads_client_uq on public.crm_leads (created_by, client_id) where client_id is not null;
create unique index if not exists crm_leads_msg_uq on public.crm_leads (inbound_message_id) where inbound_message_id is not null;
create unique index if not exists crm_leads_order_uq on public.crm_leads (online_order_id) where online_order_id is not null;
create unique index if not exists crm_leads_entry_uq on public.crm_leads (entry_id) where entry_id is not null;
create index if not exists crm_leads_board on public.crm_leads (location_id, stage, next_follow_up);
create index if not exists crm_leads_owner on public.crm_leads (owner_user, stage);
create index if not exists crm_leads_customer on public.crm_leads (customer_id) where customer_id is not null;

create table if not exists public.crm_lead_events (               -- append only trail of everything that happens to a lead
  id bigint generated always as identity primary key,
  lead_id uuid not null references public.crm_leads(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  kind text not null check (kind in ('created', 'edited', 'stage', 'note', 'quote', 'assign', 'follow_up', 'convert', 'reopen', 'task')),
  from_stage text, to_stage text,
  note text check (note is null or char_length(note) <= 1000),
  detail jsonb
);
create index if not exists crm_lead_events_lead on public.crm_lead_events (lead_id, id);

create table if not exists public.crm_lead_quotes (                -- a quote is a priced list with a validity date; it is NOT an invoice and posts nothing
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.crm_leads(id),
  version int not null,
  client_id uuid,
  status text not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'declined', 'superseded')),
  valid_until date,
  items jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 100),
  subtotal numeric not null check (subtotal >= 0 and subtotal <= 1000000000000),
  discount numeric not null default 0 check (discount >= 0 and discount <= 1000000000000),
  total numeric not null check (total >= 0 and total <= 1000000000000),
  note text check (note is null or char_length(note) <= 300),
  late_reason text check (late_reason is null or char_length(late_reason) <= 300),
  created_by uuid not null, created_at timestamptz not null default now(),
  sent_at timestamptz, responded_at timestamptz, response_note text check (response_note is null or char_length(response_note) <= 300),
  unique (lead_id, version)
);
create unique index if not exists crm_lead_quotes_client_uq on public.crm_lead_quotes (created_by, client_id) where client_id is not null;

create table if not exists public.crm_tasks (
  id uuid primary key default gen_random_uuid(),
  client_id uuid,
  location_id int references public.locations(id),
  customer_id uuid references public.customers(id),
  lead_id uuid references public.crm_leads(id),
  order_id uuid references public.online_orders(id),
  kind text not null default 'other' check (kind in ('call', 'message', 'visit', 'follow_up', 'other')),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  due_at timestamptz not null,
  snooze_until timestamptz,
  snooze_count int not null default 0,
  assigned_to uuid not null,
  status text not null default 'open' check (status in ('open', 'done', 'skipped')),
  done_note text check (done_note is null or char_length(done_note) <= 300),
  skip_reason text check (skip_reason is null or char_length(skip_reason) <= 300),
  source text not null default 'manual' check (source in ('manual', 'lead', 'order', 'auto')),
  created_by uuid not null, created_at timestamptz not null default now(),
  done_by uuid, done_at timestamptz, updated_at timestamptz not null default now(),
  check ((status = 'done') = (done_at is not null))
);
create unique index if not exists crm_tasks_client_uq on public.crm_tasks (created_by, client_id) where client_id is not null;
create index if not exists crm_tasks_mine on public.crm_tasks (assigned_to, status, due_at);
create index if not exists crm_tasks_lead on public.crm_tasks (lead_id) where lead_id is not null;

create table if not exists public.crm_task_events (
  id bigint generated always as identity primary key,
  task_id uuid not null references public.crm_tasks(id),
  at timestamptz not null default now(),
  by_user uuid, by_staff text,
  kind text not null check (kind in ('created', 'edited', 'assigned', 'snoozed', 'done', 'skipped')),
  note text check (note is null or char_length(note) <= 300),
  detail jsonb
);
create index if not exists crm_task_events_task on public.crm_task_events (task_id, id);

-- ============================================================================
-- 6. GUARDS
-- ============================================================================
-- the trail tables can never be changed or deleted
create or replace function public._crmg_append_only() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the trail of a lead or a task cannot be changed or deleted'; end $$;

-- a lead moves only along the allowed lines. A direct change in the database is refused too (a hidden button is also a refused request).
-- won and lost are final; a lost lead can go back to enquiry or following_up ONLY through _crmg_lead_reopen (it sets crmg.reopen for its own transaction).
create or replace function public._crmg_stage_ok(p_from text, p_to text) returns boolean language sql immutable as $$
  select case p_from
    when 'enquiry' then p_to in ('quoted', 'following_up', 'won', 'lost')
    when 'quoted' then p_to in ('following_up', 'won', 'lost')
    when 'following_up' then p_to in ('quoted', 'won', 'lost')
    else false end $$;
create or replace function public._crmg_leads_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted - close the enquiry as lost instead'; end if;
  if new.stage is distinct from old.stage then
    if old.stage = 'lost' and new.stage in ('enquiry', 'following_up') and coalesce(current_setting('crmg.reopen', true), '') = '1' then
      null;
    elsif not public._crmg_stage_ok(old.stage, new.stage) then
      raise exception 'illegal_stage_move: % to % is not allowed', old.stage, new.stage;
    end if;
    if new.stage = 'lost' and (new.lost_reason is null or not exists (select 1 from public.crm_lead_lists where kind = 'lost_reason' and code = new.lost_reason)) then
      raise exception 'lost_reason_required: choose a lost reason from the list';
    end if;
    new.stage_at := now();
    new.closed_at := case when new.stage in ('won', 'lost') then now() else null end;
  elsif old.stage in ('won', 'lost') then
    -- a closed lead keeps its facts; only the link to the created record and the activity clock may be filled in
    if (new.contact_name, new.contact_phone, new.customer_id, new.event_date, new.guests, new.est_value, new.occasion, new.source, new.owner_user, new.location_id, new.lost_reason, new.lost_note)
       is distinct from (old.contact_name, old.contact_phone, old.customer_id, old.event_date, old.guests, old.est_value, old.occasion, old.source, old.owner_user, old.location_id, old.lost_reason, old.lost_note)
       and not (old.stage = 'won' and old.converted_at is null) then
      raise exception 'lead_closed: a won or lost enquiry cannot be edited';
    end if;
  end if;
  if old.online_order_id is not null and new.online_order_id is distinct from old.online_order_id then raise exception 'already_converted: the linked order cannot be changed'; end if;
  if old.entry_id is not null and new.entry_id is distinct from old.entry_id then raise exception 'already_converted: the linked form cannot be changed'; end if;
  if old.converted_at is not null and new.converted_at is distinct from old.converted_at then raise exception 'already_converted: the conversion cannot be changed'; end if;
  new.updated_at := now();
  return new;
end $$;

-- a quote that was sent keeps its items, prices and validity; only its status and the answer can change
create or replace function public._crmg_quotes_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted - a quote is replaced by a new version'; end if;
  if old.status <> 'draft' and (new.items, new.subtotal, new.discount, new.total, new.valid_until, new.version, new.lead_id) is distinct from (old.items, old.subtotal, old.discount, old.total, old.valid_until, old.version, old.lead_id) then
    raise exception 'quote_sent: a sent quote cannot be changed - make a new version';
  end if;
  return new;
end $$;

create or replace function public._crmg_tasks_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'nothing is deleted - skip the task with a reason instead'; end if;
  if old.status <> 'open' and (new.title, new.due_at, new.assigned_to, new.kind, new.lead_id, new.customer_id, new.order_id) is distinct from (old.title, old.due_at, old.assigned_to, old.kind, old.lead_id, old.customer_id, old.order_id) then
    raise exception 'task_closed: a done or skipped task cannot be changed';
  end if;
  if old.status <> 'open' and new.status is distinct from old.status then raise exception 'task_closed: a done or skipped task cannot be reopened'; end if;
  new.updated_at := now();
  return new;
end $$;

do $t$ declare t text; begin
  foreach t in array array['crm_leads', 'crm_lead_events', 'crm_lead_quotes', 'crm_tasks', 'crm_task_events', 'crm_lead_lists'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
  foreach t in array array['crm_lead_events', 'crm_task_events'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_ro', t);
    execute format('create trigger %I before update on public.%I for each row execute function public._crmg_append_only()', t || '_ro', t);
  end loop;
  foreach t in array array['crm_leads', 'crm_lead_quotes', 'crm_tasks', 'crm_lead_lists'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, case when t = 'crm_lead_lists' then 'kind,code' else 'id' end);
  end loop;
end $t$;
drop trigger if exists crm_leads_guard on public.crm_leads;
create trigger crm_leads_guard before update on public.crm_leads for each row execute function public._crmg_leads_guard();
drop trigger if exists crm_lead_quotes_guard on public.crm_lead_quotes;
create trigger crm_lead_quotes_guard before update on public.crm_lead_quotes for each row execute function public._crmg_quotes_guard();
drop trigger if exists crm_tasks_guard on public.crm_tasks;
create trigger crm_tasks_guard before update on public.crm_tasks for each row execute function public._crmg_tasks_guard();

-- ============================================================================
-- 7. HELPERS (closed to browsers)
-- ============================================================================
create or replace function public._crmg_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid() $$;
create or replace function public._crmg_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function public._crmg_lead_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_lead_on') $$;
create or replace function public._crmg_task_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_task_on') $$;
create or replace function public._crmg_reason(p text) returns text language plpgsql immutable as $$
begin
  if p is null or char_length(btrim(p)) < 3 then raise exception 'reason_required: write a reason (at least 3 letters)'; end if;
  return left(btrim(p), 300);
end $$;
-- can this person work at this outlet? (owner, head office role, or listed for the outlet)
create or replace function public._crmg_user_at(p_user uuid, p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p_user and status = 'active') and (
    exists (select 1 from public.user_roles where user_id = p_user and role_code in ('owner', 'management'))
    or exists (select 1 from public.user_locations where user_id = p_user and location_id = p_loc)) $$;
-- who may see / work on a lead: owner, holders of crm_lead_all, else only inside own outlets as assignee, maker, or holder of crm_lead_manage
create or replace function public._crmg_lead_vis(p_loc int, p_owner uuid, p_created uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_lead_all')
    or (public.can_loc(p_loc) and (p_owner = auth.uid() or p_created = auth.uid() or public.has_grant('crm_lead_manage', p_loc)))) $$;
-- a manager of the outlet: owner, crm_lead_all, or crm_lead_manage inside an outlet the person works in
create or replace function public._crmg_lead_mgr(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_lead_all') or (public.can_loc(p_loc) and public.has_grant('crm_lead_manage', p_loc))) $$;
create or replace function public._crmg_can_create(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_lead_all')
    or (public.can_loc(p_loc) and (public.has_grant('crm_lead_manage', p_loc) or public.can_do('POS', 'enter') or public.can_do('20-4', 'enter') or public.can_do('20-1', 'enter')))) $$;
-- phone shown to the caller: masked only when the privacy guard of the customer package exists and is ON (setting crm_pii_guard_on, not owned here)
create or replace function public._crmg_phone(p text, p_owner uuid) returns text language sql stable security definer set search_path = public as $$
  select case when p is null then null
              when public.rule_on('crm_pii_guard_on') and not (public.is_owner() or public.has_grant('crm_contact_view') or p_owner = auth.uid())
                then left(p, 3) || repeat('*', greatest(char_length(p) - 5, 1)) || right(p, 2)
              else p end $$;
create or replace function public._crmg_ev(p_lead uuid, p_kind text, p_from text, p_to text, p_note text, p_detail jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_lead_events (lead_id, by_user, by_staff, kind, from_stage, to_stage, note, detail)
    values (p_lead, auth.uid(), public._crmg_staff(), p_kind, p_from, p_to, left(nullif(btrim(p_note), ''), 1000), p_detail);
  update public.crm_leads set last_activity_at = now() where id = p_lead and p_kind <> 'edited';
end $$;
create or replace function public._crmg_audit(p_action text, p_table text, p_id text, p_detail jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail) values (auth.uid(), public._crmg_staff(), p_action, p_table, p_id, p_detail);
end $$;
create or replace function public._crmg_exc(p_kind text, p_amount numeric, p_src_id text, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.money_exceptions (kind, event_type, amount, src_table, src_id, reason, by_user) values (p_kind, 'crm', p_amount, 'crm_leads', left(p_src_id, 120), left(p_reason, 300), auth.uid());
  perform public._crmg_audit('exception', 'crm_leads', p_src_id, jsonb_build_object('kind', p_kind, 'reason', left(p_reason, 300)));
end $$;
create or replace function public._crmg_list_ok(p_kind text, p_code text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.crm_lead_lists where kind = p_kind and code = p_code and active) $$;

-- ============================================================================
-- 8. LISTS API
-- ============================================================================
-- the three lists with their active entries (all entries for a person who may edit them)
create or replace function public._crmg_lists(p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare can_edit boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  can_edit := public.is_owner() or (public.rule_txt('crm_lead_list_add_mode') = 'manager' and public.has_grant('crm_lead_manage'));
  return jsonb_build_object('can_edit', can_edit,
    'lost_reason', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'active', active) order by sort, code) from public.crm_lead_lists where kind = 'lost_reason' and (active or (p_all and can_edit))), '[]'::jsonb),
    'source', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'active', active) order by sort, code) from public.crm_lead_lists where kind = 'source' and (active or (p_all and can_edit))), '[]'::jsonb),
    'occasion', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'label', label, 'active', active) order by sort, code) from public.crm_lead_lists where kind = 'occasion' and (active or (p_all and can_edit))), '[]'::jsonb));
end $$;

-- add a new entry, rename, retire or bring back (p_active). Who: the owner; or, when the owner set crm_lead_list_add_mode = manager, a holder of crm_lead_manage.
create or replace function public._crmg_list_save(p_kind text, p_code text, p_label text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text := lower(btrim(coalesce(p_code, ''))); l text := btrim(coalesce(p_label, '')); r public.crm_lead_lists; srt int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or (public.rule_txt('crm_lead_list_add_mode') = 'manager' and public.has_grant('crm_lead_manage'))) then raise exception 'not allowed'; end if;
  if p_kind not in ('lost_reason', 'source', 'occasion') then raise exception 'bad_list'; end if;
  if c !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_code: use 2 to 31 small letters, digits or _'; end if;
  if char_length(l) not between 1 and 60 then raise exception 'bad_label'; end if;
  select * into r from public.crm_lead_lists where kind = p_kind and code = c for update;
  if found then
    if c = 'other' and not coalesce(p_active, true) then raise exception 'other_stays: the entry Other can never be removed'; end if;
    update public.crm_lead_lists set label = l, active = coalesce(p_active, true) where kind = p_kind and code = c;
    return jsonb_build_object('kind', p_kind, 'code', c, 'updated', true);
  end if;
  select coalesce(max(sort), 0) into srt from public.crm_lead_lists where kind = p_kind and code <> 'other' and sort < 900;
  insert into public.crm_lead_lists (kind, code, label, active, sort, created_by) values (p_kind, c, l, coalesce(p_active, true), srt + 10, auth.uid());
  return jsonb_build_object('kind', p_kind, 'code', c, 'created', true);
end $$;

-- ============================================================================
-- 9. PRIVILEGES: the API is open to signed-in users (each function checks the right itself); helpers are closed to browsers.
--    _crmg_lock(all names of THIS file, API names of THIS file) touches only the names it is given, so pasting one file never changes another file's grants.
-- ============================================================================
create or replace function public._crmg_lock(p_all text[], p_api text[]) returns void language plpgsql set search_path = public as $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (p_all) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any (p_api) then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;
revoke all on function public._crmg_lock(text[], text[]) from public, anon, authenticated;
select public._crmg_lock(array['_crmg_present', '_crmg_add_exc_kinds', '_crmg_append_only', '_crmg_stage_ok', '_crmg_leads_guard', '_crmg_quotes_guard', '_crmg_tasks_guard', '_crmg_staff', '_crmg_today',
  '_crmg_lead_on', '_crmg_task_on', '_crmg_reason', '_crmg_user_at', '_crmg_lead_vis', '_crmg_lead_mgr', '_crmg_can_create', '_crmg_phone', '_crmg_ev', '_crmg_audit', '_crmg_exc', '_crmg_list_ok',
  '_crmg_lists', '_crmg_list_save'], array['_crmg_lists', '_crmg_list_save']);
