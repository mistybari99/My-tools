-- Phase 300 (bos300, package CRM-A, local label 100) - CUSTOMER PROFILE PLUS: schema, settings, grants, helpers.
-- Paste AFTER phase99 (works on a database built through phase 98 as well). Paste-twice safe. Earlier phase files are not edited and NO shared function is patched or re-created.
-- Phase files 301 (write functions) and 302 (read functions: Customer 360, timeline, favourites, masked directory) follow.
--
-- WHAT THIS ADDS (all new objects; prefix crm_ for tables the CRM family shares, crma_ / _crma_ for the functions of this package)
--   customers (+4 nullable columns)  preferred_location_id, language ('bn' | 'en'), owner_user (the staff member who looks after the customer), credit_days (credit terms; informational)
--                                    type_code already exists (phase 8) and becomes writable through crma_customer_extras_save.
--   customer_phones      extra phone numbers (label, WhatsApp yes/no). The main number stays customers.mobile (the key POS and record_sale2 use) and customers.whatsapp.
--   customer_addresses   delivery points (label, area, landmark, delivery note, one default). The main address stays customers.address.
--   customer_dates       family dates (spouse, child, parent ... birthday / anniversary / other), month + day, year optional. Own birthday / anniversary stay in customers.
--   crm_tags, customer_tags   owner-editable tag list; tags on a customer (retired, never deleted).
--   crm_notes            notes with author and time (append-only; a note is retired with a reason, never changed or deleted). The old single customers.note is shown as the first note.
--   Settings (rules, module crm): crm_on (OFF), crm_second_phone_on (OFF), crm_mask_phone (OFF). Grants: crm_view, crm_contact_view (nobody holds them until the owner gives them).
--
-- NO BACKFILL ON PURPOSE. The customer screen reads the main mobile, WhatsApp, address, birthday and anniversary straight from customers, so the old customer form
-- (customer_save) and this package can never drift apart, and an existing customer shows a complete profile with no migration. The side tables hold only what is ADDITIONAL.
--
-- PRIVACY: the new tables are closed to browsers (no select grant, row security on). Everything is read through SECURITY DEFINER functions that mask phone numbers
-- when the owner switches crm_mask_phone ON and the caller has no right (owner, grant crm_contact_view, or the existing report right rpt_mobile_ok).
-- ACCOUNTING: nothing here touches sales, payments, journal_entries or journal_lines. The CRM never posts to the journal.
-- NOTHING CHANGES FOR AN EXISTING INSTALL until the owner switches crm_on (and, for extra phones, crm_second_phone_on) ON. Reading the 360 view is always allowed to people
-- who may already see customers; masking applies only when crm_mask_phone is ON.

do $g$ begin
  if to_regprocedure('public._cust_pos43()') is null or to_regprocedure('public._cust_mgr43()') is null or to_regprocedure('public._cust_stats43(uuid,boolean)') is null
     or to_regprocedure('public.customer_directory(integer)') is null or to_regprocedure('public.rpt_mobile_ok()') is null then
    raise exception 'phase300 needs phase 43 (customers), phase 9 (rpt_mobile_ok) first';
  end if;
  if to_regclass('public.notify_outbox') is null or to_regclass('public.online_orders') is null or to_regclass('public.inbound_messages') is null then
    raise exception 'phase300 needs phase 61, 62 and 76 first';
  end if;
end $g$;

create or replace function public._crma_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('crm_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Customer profile extras are on', 'Customer profile extras are on', 'Customer profile extras are on',
  'OFF = the customer screens work exactly as today and nothing can be added to a profile. ON = staff can add extra phones, delivery points, family dates, tags, notes, language, preferred outlet and customer type.',
  'OFF = the customer screens work exactly as today and nothing can be added to a profile. ON = staff can add extra phones, delivery points, family dates, tags, notes, language, preferred outlet and customer type.',
  'OFF = the customer screens work exactly as today and nothing can be added to a profile. ON = staff can add extra phones, delivery points, family dates, tags, notes, language, preferred outlet and customer type.', 1300),
 ('crm_second_phone_on', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Allow extra phone numbers on a customer', 'Allow extra phone numbers on a customer', 'Allow extra phone numbers on a customer',
  'OFF = only the main mobile and the WhatsApp number are used. ON = a customer can have more numbers (home, work, family). A number held by another customer is accepted and shown as a possible duplicate; a sale is never blocked.',
  'OFF = only the main mobile and the WhatsApp number are used. ON = a customer can have more numbers (home, work, family). A number held by another customer is accepted and shown as a possible duplicate; a sale is never blocked.',
  'OFF = only the main mobile and the WhatsApp number are used. ON = a customer can have more numbers (home, work, family). A number held by another customer is accepted and shown as a possible duplicate; a sale is never blocked.', 1301),
 ('crm_mask_phone', 'crm', 'switch', 'false'::jsonb, null, null, null, null,
  'Hide customer phone numbers and addresses from people without the right', 'Hide customer phone numbers and addresses from people without the right', 'Hide customer phone numbers and addresses from people without the right',
  'OFF = lists and profiles show full numbers to everyone who can see customers (today). ON = they show 017******78 unless the person is the owner, holds the grant "See full customer phone and address", or already sees mobiles in reports.',
  'OFF = lists and profiles show full numbers to everyone who can see customers (today). ON = they show 017******78 unless the person is the owner, holds the grant "See full customer phone and address", or already sees mobiles in reports.',
  'OFF = lists and profiles show full numbers to everyone who can see customers (today). ON = they show 017******78 unless the person is the owner, holds the grant "See full customer phone and address", or already sees mobiles in reports.', 1302)
on conflict (key) do nothing;

-- ---------- grants (idempotent; no role holds them until the owner gives them) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_view', 'master', 72, 'See customer notes, messages and the full timeline', 'See customer notes, messages and the full timeline', 'See customer notes, messages and the full timeline', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'crm_contact_view', 'master', 73, 'See full customer phone and address', 'See full customer phone and address', 'See full customer phone and address', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'crm_contact_view');

-- ---------- columns on customers (all nullable: an existing customer needs no migration) ----------
alter table public.customers add column if not exists preferred_location_id integer references public.locations(id);
alter table public.customers add column if not exists language text;
alter table public.customers add column if not exists owner_user uuid references public.profiles(id);
alter table public.customers add column if not exists credit_days integer;
do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'customers_language_crma' and conrelid = 'public.customers'::regclass) then
    alter table public.customers add constraint customers_language_crma check (language is null or language in ('bn', 'en'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'customers_credit_days_crma' and conrelid = 'public.customers'::regclass) then
    alter table public.customers add constraint customers_credit_days_crma check (credit_days is null or (credit_days >= 0 and credit_days <= 365));
  end if;
end $c$;

-- ---------- small helpers (closed to browsers; SECURITY DEFINER callers use them) ----------
-- a phone as 01XXXXXXXXX, or NULL (never raises): used to match online orders and messages typed in any format
create or replace function public._crma_norm(p text) returns text language plpgsql immutable set search_path = public as $$
begin return public.norm_mobile(p); exception when others then return null; end $$;

-- 01712345678 -> 017******78 (first 3 and last 2 digits)
create or replace function public._crma_mask(p text) returns text language sql immutable set search_path = public as $$
  select case when p is null then null
              when length(p) < 6 then repeat('*', length(p))
              else left(p, 3) || repeat('*', length(p) - 5) || right(p, 2) end;
$$;

create or replace function public._crma_valid_md(m integer, d integer) returns boolean language sql immutable as $$
  select m between 1 and 12 and d between 1 and 31
     and d <= extract(day from (make_date(2024, m, 1) + interval '1 month' - interval '1 day'))::int;
$$;

-- the next date on or after p_from for a month and day (29 February falls on 28 February in a year that has no 29th)
create or replace function public._crma_next_date(m integer, d integer, p_from date) returns date language plpgsql immutable set search_path = public as $$
declare y int := extract(year from p_from)::int; dd int; c date;
begin
  if not public._crma_valid_md(m, d) then return null; end if;
  loop
    dd := least(d, extract(day from (make_date(y, m, 1) + interval '1 month' - interval '1 day'))::int);
    c := make_date(y, m, dd);
    if c >= p_from then return c; end if;
    y := y + 1;
  end loop;
end $$;

create or replace function public._crma_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_on'); $$;
create or replace function public._crma_mask_on() returns boolean language sql stable security definer set search_path = public as $$ select public.rule_on('crm_mask_phone'); $$;
-- may the caller see full phone numbers and addresses?  owner, grant crm_contact_view, or the existing report right
create or replace function public._crma_contact_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_contact_view') or public.rpt_mobile_ok());
$$;
-- shows the full number? (guard OFF = today = everybody who can see customers)
create or replace function public._crma_show_phone() returns boolean language sql stable security definer set search_path = public as $$
  select not public.rule_on('crm_mask_phone') or public._crma_contact_ok();
$$;
create or replace function public._crma_ph(p text) returns text language sql stable security definer set search_path = public as $$
  select case when public._crma_show_phone() then p else public._crma_mask(p) end;
$$;
-- notes, messages and enquiries in the timeline
create or replace function public._crma_view_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('crm_view'));
$$;
-- who may add to a profile: the people who may already register customers (POS enter or customer manager)
create or replace function public._crma_write_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._cust_mgr43() or public.can_do('POS', 'enter'));
$$;
-- ---------- tables ----------
create table if not exists public.customer_phones (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  phone text not null check (phone ~ '^01[3-9][0-9]{8}$'),
  label text not null default 'mobile' check (label in ('mobile', 'home', 'work', 'other')),
  wa_ok boolean not null default false,
  note text check (note is null or length(note) <= 100),
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz
);
create unique index if not exists customer_phones_one on public.customer_phones (customer_id, phone) where active;
create index if not exists customer_phones_phone on public.customer_phones (phone) where active;

create table if not exists public.customer_addresses (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  label text not null default 'home' check (label in ('home', 'office', 'gift', 'other')),
  address text not null check (length(btrim(address)) between 1 and 200),
  area text check (area is null or length(area) <= 80),
  landmark text check (landmark is null or length(landmark) <= 120),
  delivery_note text check (delivery_note is null or length(delivery_note) <= 200),
  is_default boolean not null default false,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz
);
create unique index if not exists customer_addresses_default on public.customer_addresses (customer_id) where is_default and active;
create index if not exists customer_addresses_cust on public.customer_addresses (customer_id) where active;

create table if not exists public.customer_dates (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  kind text not null check (kind in ('birthday', 'anniversary', 'other')),
  person_label text not null check (length(btrim(person_label)) between 1 and 40),     -- Spouse, Child 1, Mother ... (the customer's own dates live in customers)
  month integer not null, day integer not null,
  year integer check (year is null or year between 1900 and 2100),
  remind_days_before integer check (remind_days_before is null or remind_days_before between 0 and 60),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz,
  check (public._crma_valid_md(month, day))
);
create unique index if not exists customer_dates_one on public.customer_dates (customer_id, kind, lower(person_label), month, day) where active;
create index if not exists customer_dates_md on public.customer_dates (month, day) where active;

create table if not exists public.crm_tags (
  id bigserial primary key,
  code text not null unique check (code ~ '^[a-z0-9_]{2,30}$'),
  label text not null check (length(btrim(label)) between 1 and 40),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now()
);
create table if not exists public.customer_tags (
  customer_id uuid not null references public.customers(id),
  tag_id bigint not null references public.crm_tags(id),
  active boolean not null default true,
  added_by uuid, added_at timestamptz not null default now(),
  removed_by uuid, removed_at timestamptz,
  primary key (customer_id, tag_id)
);
create index if not exists customer_tags_tag on public.customer_tags (tag_id) where active;

create table if not exists public.crm_notes (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  kind text not null default 'note' check (kind in ('note', 'call', 'visit', 'message', 'other')),
  body text not null check (length(btrim(body)) between 1 and 1000),
  client_id uuid unique,
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  retired_at timestamptz, retired_by uuid, retire_reason text check (retire_reason is null or length(retire_reason) <= 300)
);
create index if not exists crm_notes_cust on public.crm_notes (customer_id, created_at desc, id desc);

-- the phones used to match a customer to online orders and inbox messages (those carry a phone number, not a customer id).
-- The main mobile always counts. The WhatsApp number and the extra numbers count only when NO other customer holds the same number (as main mobile or as an active extra number):
-- a number two customers share belongs to nobody for matching, so one customer's orders never show up on another customer's timeline.
create or replace function public._crma_phones(p_customer uuid) returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct z.x) filter (where z.x is not null), '{}'::text[])
  from (select c.mobile x from public.customers c where c.id = p_customer
        union all select public._crma_norm(c.whatsapp) from public.customers c where c.id = p_customer
        union all select p.phone from public.customer_phones p where p.customer_id = p_customer and p.active) z
  where z.x is not null and (z.x = (select mobile from public.customers where id = p_customer)
        or (not exists (select 1 from public.customers o where o.mobile = z.x and o.id <> p_customer)
            and not exists (select 1 from public.customer_phones o where o.phone = z.x and o.active and o.customer_id <> p_customer)));
$$;

-- a note is a record: only its retirement can be written, once
create or replace function public._crma_notes_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then raise exception 'append_only: a note is retired, never deleted'; end if;
  if old.retired_at is not null then raise exception 'append_only: a retired note cannot change'; end if;
  if (new.customer_id, new.kind, new.body, new.client_id, new.created_by, new.created_staff, new.created_at)
     is distinct from (old.customer_id, old.kind, old.body, old.client_id, old.created_by, old.created_staff, old.created_at) then
    raise exception 'append_only: a note cannot be edited, retire it and write a new one';
  end if;
  return new;
end $$;
drop trigger if exists crm_notes_guard on public.crm_notes;
create trigger crm_notes_guard before update or delete on public.crm_notes for each row execute function public._crma_notes_guard();

-- audit + nothing is deleted + closed to browsers
do $t$ declare t text; begin
  foreach t in array array['customer_phones', 'customer_addresses', 'customer_dates', 'crm_tags', 'customer_tags', 'crm_notes'] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t,
                   case when t = 'customer_tags' then 'customer_id,tag_id' else 'id' end);
    if t <> 'crm_notes' then
      execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
      execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
    end if;
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
  end loop;
end $t$;
-- the tag list (labels only) may be read by every active user; every other new table is read only through the masking functions
drop policy if exists crm_tags_read on public.crm_tags;
create policy crm_tags_read on public.crm_tags for select to authenticated using (public.is_active());
grant select on public.crm_tags to authenticated;
revoke usage, select on sequence public.customer_phones_id_seq, public.customer_addresses_id_seq, public.customer_dates_id_seq, public.crm_tags_id_seq, public.crm_notes_id_seq
  from public, anon, authenticated;

revoke all on function public._crma_present(), public._crma_norm(text), public._crma_mask(text), public._crma_valid_md(integer, integer), public._crma_next_date(integer, integer, date),
  public._crma_on(), public._crma_mask_on(), public._crma_contact_ok(), public._crma_show_phone(), public._crma_ph(text), public._crma_view_ok(), public._crma_write_ok(),
  public._crma_phones(uuid), public._crma_notes_guard() from public, anon, authenticated;
