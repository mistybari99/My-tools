-- Phase 303 (CRM package B, local label 103) - CONSENT: record and withdraw a customer's yes / no per channel, with evidence and a log; do-not-contact.
-- Paste AFTER phase62 and phase43 (it reuses notify_optin and notify_optin_log). Paste-twice safe. No earlier phase file is edited and NO shared function is re-created.
-- The integrator wires the hooks written in docs/integration/CRM-B.md (two small lines in notify_enqueue / notify_optin_set, a few lines in customers.js and pos.js).
--
-- WHY (CRM audit rows 13, 14): notify_optin_set exists but no screen or script calls it, so a customer's yes or no could never be recorded, and a "no" could not be
-- written down with where it came from. Existing customers have NO row = "Not asked" = nothing may be sent (unchanged). Nothing here sends anything.
-- WHAT THIS FILE ADDS (functions start _crmb_, tables start crm_)
--   1. crm_consent_events      append-only evidence: who recorded a yes / no / do-not-contact, for which customer and channel, how it was given (counter tick, phone,
--                              paper form, message reply, owner entry, import), where (outlet), the wording version, a note. notify_optin / notify_optin_log stay the single
--                              truth that notify_enqueue reads; every change here also writes them (same rows the old owner-only function writes).
--   2. crm_contact_prefs       one row per customer that ever had a do-not-contact flag. Do-not-contact beats any opt-in.
--   3. _crmb_consent_set / _crmb_consent_set_mobile   record a yes or a no (idempotent by client id). A "no" cancels queued messages at once. A "yes" after a "no" needs a reason.
--   4. _crmb_prefs_set         do-not-contact on / off (on is open to the people who may record; off needs a manager and a reason).
--   5. _crmb_consent_get / _crmb_consent_get_mobile / _crmb_consent_history / _crmb_consent_summary   read side (no phone number in the summary).
--   6. _crmb_consent_import    paper list import (dry run first). An import never turns a withdrawn "no" back into a "yes".
--   7. _crmb_send_allowed / _crmb_enqueue_guard   one answer to "may this customer be messaged", used by the hook in notify_enqueue and by the campaign package.
--   8. _crmb_patch             exact-text patch helper for the hooks (closed to browsers).
-- SETTINGS (rules, module crm; all default OFF or blank, the owner changes them in the Switchboard / settings hub):
--   crm_consent_pos_on (OFF)   counter staff with POS enter may record a customer's yes / no. OFF = only the owner or a customer manager (today).
--   crm_quiet_from / crm_quiet_to (blank)   a quiet time window; blank = none. Read by _crmb_send_allowed only.
-- Accounting: nothing here reads or writes sales, payments or the journal.

do $g$ begin
  if to_regprocedure('public._i62_ok()') is null or to_regclass('public.notify_optin') is null or to_regclass('public.notify_optin_log') is null
     or to_regclass('public.notify_outbox') is null or to_regprocedure('public.customer_directory(integer)') is null or to_regprocedure('public._cust_pos43()') is null then
    raise exception 'phase303 needs phase 62 (notify_optin) and phase 43 (customers) first';
  end if;
end $g$;

create or replace function public._crmb_present() returns boolean language sql immutable as $$ select true $$;

-- ---------- generic: patch a live function by exact text (reads the CURRENT definition, so it sits on top of whatever is installed) ----------
-- p_pairs = [old1, new1, old2, new2 ...]. Every old text must exist (otherwise nothing is changed and the call stops). Already patched (marker found) = no-op.
create or replace function public._crmb_patch(p_fn regprocedure, p_pairs text[], p_marker text default 'bosCRMB') returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'patch of % carries no marker %', p_fn::text, p_marker; end if;
  execute def;
  return true;
end $$;

-- ---------- settings seed (used by phases 303 to 305; closed to browsers) ----------
create or replace function public._crmb_rule_seed(p_key text, p_kind text, p_default jsonb, p_unit text, p_choices jsonb, p_min numeric, p_max numeric, p_label text, p_hint text, p_sort int)
returns void language plpgsql set search_path = public as $$
begin
  insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort)
    values (p_key, 'crm', p_kind, p_default, p_unit, p_choices, p_min, p_max, p_label, p_label, p_label, p_hint, p_hint, p_hint, p_sort)
    on conflict (key) do nothing;
end $$;

do $r$ begin
  perform public._crmb_rule_seed('crm_consent_pos_on', 'switch', 'false'::jsonb, null, null, null, null,
  'Let counter staff record a customer''s yes or no to messages',
  'OFF = only the owner or a customer manager can record a customer''s consent (today). ON = anyone who can enter POS sales can tick yes or no at the counter. Staff can never use the owner-entry or import ways.', 3000);
  perform public._crmb_rule_seed('crm_quiet_from', 'text', null, null, null, null, null,
  'Quiet time starts (24-hour clock, for example 21:00)',
  'Blank = no quiet time. With both quiet times set, the message check says "quiet hours" inside the window. Shop time (Dhaka).', 3001);
  perform public._crmb_rule_seed('crm_quiet_to', 'text', null, null, null, null, null,
  'Quiet time ends (24-hour clock, for example 08:00)',
  'Blank = no quiet time. A window that runs past midnight is fine (21:00 to 08:00).', 3002);
end $r$;

-- ---------- tables ----------
create table if not exists public.crm_consent_events (        -- append-only evidence of every yes / no / do-not-contact
  id bigserial primary key,
  client_id uuid unique,
  batch_id uuid,
  customer_id uuid not null references public.customers(id),
  kind text not null check (kind in ('optin', 'dnc')),
  channel text check (channel in ('sms', 'whatsapp')),
  status text not null check (status in ('in', 'out', 'on', 'off')),
  how text not null check (how in ('pos_tick', 'phone', 'paper_form', 'message_reply', 'owner_entry', 'import', 'other')),
  location_id int references public.locations(id),
  note text check (note is null or length(note) <= 300),
  text_version text check (text_version is null or length(text_version) <= 40),
  recorded_by uuid, staff_id text,
  at timestamptz not null default now(),
  check ((kind = 'optin' and channel is not null and status in ('in', 'out')) or (kind = 'dnc' and channel is null and status in ('on', 'off')))
);
create index if not exists crm_consent_events_cust on public.crm_consent_events (customer_id, id desc);
create index if not exists crm_consent_events_batch on public.crm_consent_events (batch_id) where batch_id is not null;

create table if not exists public.crm_contact_prefs (         -- do-not-contact: wins over every opt-in
  customer_id uuid primary key references public.customers(id),
  dnc boolean not null default false,
  note text check (note is null or length(note) <= 300),
  updated_by uuid, updated_at timestamptz not null default now()
);

create or replace function public._crmb_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
drop trigger if exists crm_consent_events_ro on public.crm_consent_events;
create trigger crm_consent_events_ro before update or delete on public.crm_consent_events for each row execute function public._crmb_ro();
drop trigger if exists crm_contact_prefs_nodel on public.crm_contact_prefs;
create trigger crm_contact_prefs_nodel before delete on public.crm_contact_prefs for each row execute function public.no_hard_delete();
drop trigger if exists audit_crm_contact_prefs on public.crm_contact_prefs;
create trigger audit_crm_contact_prefs after insert or update on public.crm_contact_prefs for each row execute function public.log_change('customer_id');

do $t$ declare t text; begin
  foreach t in array array['crm_consent_events', 'crm_contact_prefs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_ok())', t || '_read', t);
  end loop;
end $t$;
revoke usage, select on sequence public.crm_consent_events_id_seq from public, anon, authenticated;

-- ---------- who may record ----------
-- owner / customer manager (as today), plus POS-enter staff only while crm_consent_pos_on is ON
create or replace function public._crmb_consent_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public._i62_ok() or (public.rule_on('crm_consent_pos_on') and public.can_do('POS', 'enter')));
$$;

create or replace function public._crmb_staff() returns text language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where id = auth.uid();
$$;

-- ---------- group helpers (the soft link of phase305 may not exist yet: everything answers "just this customer") ----------
create or replace function public._crmb_links_active() returns table (primary_id uuid, linked_id uuid) language plpgsql stable security definer set search_path = public as $$
begin
  if to_regclass('public.crm_customer_links') is null then return; end if;
  return query execute 'select l.primary_id, l.linked_id from public.crm_customer_links l where l.undone_at is null';
end $$;
create or replace function public._crmb_group_root(p_customer uuid) returns uuid language sql stable security definer set search_path = public as $$
  select coalesce((select l.primary_id from public._crmb_links_active() l where l.linked_id = p_customer), p_customer);
$$;
create or replace function public._crmb_group_ids(p_customer uuid) returns uuid[] language sql stable security definer set search_path = public as $$
  with r as (select public._crmb_group_root(p_customer) root)
  select array_agg(distinct x) from (select root x from r union select l.linked_id from public._crmb_links_active() l, r where l.primary_id = r.root union select p_customer) z;
$$;

-- ---------- the one answer to "may this customer be messaged?" ----------
-- Blocks that nothing may override: do-not-contact (this customer or anyone linked to the same person) and a withdrawn "no" (same). Returns the reason or null.
create or replace function public._crmb_block_reason(p_customer uuid, p_channel text) returns text language plpgsql stable security definer set search_path = public as $$
declare ids uuid[] := public._crmb_group_ids(p_customer);
begin
  if exists (select 1 from public.crm_contact_prefs p where p.customer_id = p_customer and p.dnc) then return 'dnc'; end if;
  if exists (select 1 from public.crm_contact_prefs p where p.customer_id = any(ids) and p.dnc) then return 'group_dnc'; end if;
  if exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'out') then return 'opted_out'; end if;
  if exists (select 1 from public.notify_optin o where o.customer_id = any(ids) and o.channel = p_channel and o.status = 'out') then return 'group_opted_out'; end if;
  return null;
end $$;

create or replace function public._crmb_in_quiet(p_now timestamptz) returns boolean language plpgsql stable security definer set search_path = public as $$
declare f text := public.rule_txt('crm_quiet_from'); t text := public.rule_txt('crm_quiet_to'); n time := (p_now at time zone 'Asia/Dhaka')::time;
begin
  if f is null or t is null or f !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or t !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or f = t then return false; end if;
  if f::time < t::time then return n >= f::time and n < t::time; end if;
  return n >= f::time or n < t::time;
end $$;

-- p_purpose is accepted for the campaign package ('promo' / 'transactional'); today both need the customer's yes, exactly like notify_enqueue.
create or replace function public._crmb_send_allowed(p_customer uuid, p_channel text, p_purpose text default 'promo', p_now timestamptz default now()) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; b text;
begin
  if p_channel not in ('sms', 'whatsapp') then return jsonb_build_object('ok', false, 'reason', 'bad_channel', 'overridable', false); end if;
  select * into c from public.customers where id = p_customer;
  if not found then return jsonb_build_object('ok', false, 'reason', 'customer_not_found', 'overridable', false); end if;
  b := public._crmb_block_reason(p_customer, p_channel);
  if b is not null then return jsonb_build_object('ok', false, 'reason', b, 'overridable', false); end if;
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then
    return jsonb_build_object('ok', false, 'reason', 'not_asked', 'overridable', false);
  end if;
  if public._i62_phone(c.mobile) is null then return jsonb_build_object('ok', false, 'reason', 'bad_phone', 'overridable', false); end if;
  if public._crmb_in_quiet(coalesce(p_now, now())) then return jsonb_build_object('ok', false, 'reason', 'quiet_hours', 'overridable', true); end if;
  return jsonb_build_object('ok', true, 'reason', null, 'overridable', false);
end $$;

-- the hook line inside notify_enqueue calls this after its own opt-in check: it refuses only the blocks above (never adds a way to send)
create or replace function public._crmb_enqueue_guard(p_customer uuid, p_channel text) returns void language plpgsql stable security definer set search_path = public as $$
declare b text := public._crmb_block_reason(p_customer, p_channel);
begin
  if b in ('dnc', 'group_dnc') then raise exception 'do_not_contact'; end if;
  if b in ('opted_out', 'group_opted_out') then raise exception 'not_opted_in'; end if;
end $$;

-- ---------- the write core (no permission check here: the callers decide) ----------
create or replace function public._crmb_consent_apply(p_customer uuid, p_channel text, p_in boolean, p_how text, p_note text, p_loc int, p_text_version text, p_client uuid, p_batch uuid, p_require_reason boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur text; st text := case when p_in then 'in' else 'out' end; src text; c public.customers; cancelled int := 0; ev bigint;
begin
  select * into c from public.customers where id = p_customer for update;
  if not found then raise exception 'customer_not_found'; end if;
  select status into cur from public.notify_optin where customer_id = p_customer and channel = p_channel for update;
  if cur = st then return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st, 'unchanged', true); end if;
  if p_in then
    if public._i62_phone(c.mobile) is null then raise exception 'bad_phone'; end if;
    if cur = 'out' and p_require_reason and coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'reason_required'; end if;
  end if;
  src := case when p_how in ('pos_tick', 'phone', 'paper_form', 'message_reply') then 'customer_consent' else 'owner_entry' end;
  insert into public.notify_optin (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, src, left(p_how || coalesce(': ' || nullif(btrim(p_note), ''), ''), 200), auth.uid())
    on conflict (customer_id, channel) do update set status = excluded.status, source = excluded.source, note = excluded.note, changed_by = auth.uid(), changed_at = now();
  insert into public.notify_optin_log (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, src, left(p_how || coalesce(': ' || nullif(btrim(p_note), ''), ''), 200), auth.uid());
  insert into public.crm_consent_events (client_id, batch_id, customer_id, kind, channel, status, how, location_id, note, text_version, recorded_by, staff_id)
    values (p_client, p_batch, p_customer, 'optin', p_channel, st, p_how, p_loc, nullif(btrim(p_note), ''), nullif(btrim(p_text_version), ''), auth.uid(), public._crmb_staff()) returning id into ev;
  if not p_in then   -- a withdrawn yes cancels what still waits (the same rule as the old owner-only function)
    update public.notify_outbox set status = 'cancelled', last_error = 'opted_out' where customer_id = p_customer and channel = p_channel and status = 'queued';
    get diagnostics cancelled = row_count;
  end if;
  if cur = 'out' and p_in then
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), public._crmb_staff(), 'crm_consent_resubscribe', 'notify_optin', p_customer::text || ':' || p_channel, jsonb_build_object('how', p_how, 'note', p_note));
  end if;
  return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st, 'unchanged', false, 'event_id', ev, 'cancelled', cancelled);
end $$;

create or replace function public._crmb_consent_check_input(p_channel text, p_how text, p_note text, p_loc int, p_text_version text) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_channel not in ('sms', 'whatsapp') or p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply', 'owner_entry', 'import', 'other')
     or (p_note is not null and length(p_note) > 300) or (p_text_version is not null and length(p_text_version) > 40) then raise exception 'bad_input'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  -- counter staff (not a manager) may only use the ways that need the customer in front of them or on the phone
  if not public._i62_ok() and p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply') then raise exception 'not allowed'; end if;
end $$;

-- record a yes (p_in true) or a no (false). Idempotent: the same client id twice changes nothing.
create or replace function public._crmb_consent_set(p_client uuid, p_customer uuid, p_channel text, p_in boolean, p_how text default 'owner_entry', p_note text default null,
                                                    p_loc int default null, p_text_version text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.crm_consent_events; r jsonb;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_customer is null or p_in is null then raise exception 'bad_input'; end if;
  perform public._crmb_consent_check_input(p_channel, p_how, p_note, p_loc, p_text_version);
  perform public._client_lock(p_client);
  select * into ex from public.crm_consent_events where client_id = p_client;
  if found then return jsonb_build_object('customer_id', ex.customer_id, 'channel', ex.channel, 'status', ex.status, 'duplicate', true, 'event_id', ex.id); end if;
  r := public._crmb_consent_apply(p_customer, p_channel, p_in, p_how, p_note, p_loc, p_text_version, p_client, null, true);
  return r || jsonb_build_object('duplicate', false);
end $$;

-- the POS knows the mobile the cashier typed, not always the customer id (a new customer exists only after the sale): same call by mobile
create or replace function public._crmb_consent_set_mobile(p_client uuid, p_mobile text, p_channel text, p_in boolean, p_how text default 'pos_tick', p_note text default null,
                                                           p_loc int default null, p_text_version text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m text; cid uuid;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_mobile is null or p_in is null then raise exception 'bad_input'; end if;
  begin m := public.norm_mobile(p_mobile); exception when others then raise exception 'bad_mobile'; end;
  select id into cid from public.customers where mobile = m;
  if cid is null then raise exception 'customer_not_found'; end if;
  return public._crmb_consent_set(p_client, cid, p_channel, p_in, p_how, p_note, p_loc, p_text_version);
end $$;

-- do-not-contact: ON is open to everyone who may record (protective); OFF needs a manager and a reason. ON cancels what still waits on both channels.
create or replace function public._crmb_prefs_set(p_client uuid, p_customer uuid, p_dnc boolean, p_note text default null, p_how text default 'owner_entry', p_loc int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.crm_consent_events; cur boolean; cancelled int := 0;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_customer is null or p_dnc is null or p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply', 'owner_entry', 'other')
     or (p_note is not null and length(p_note) > 300) then raise exception 'bad_input'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not public._i62_ok() and p_how not in ('pos_tick', 'phone', 'paper_form', 'message_reply') then raise exception 'not allowed'; end if;
  if not p_dnc and not public._i62_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.crm_consent_events where client_id = p_client;
  if found then return jsonb_build_object('customer_id', ex.customer_id, 'dnc', ex.status = 'on', 'duplicate', true); end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  select dnc into cur from public.crm_contact_prefs where customer_id = p_customer for update;
  if coalesce(cur, false) = p_dnc then return jsonb_build_object('customer_id', p_customer, 'dnc', p_dnc, 'unchanged', true, 'duplicate', false); end if;
  if not p_dnc and coalesce(length(btrim(p_note)), 0) < 3 then raise exception 'reason_required'; end if;
  insert into public.crm_contact_prefs (customer_id, dnc, note, updated_by) values (p_customer, p_dnc, nullif(btrim(p_note), ''), auth.uid())
    on conflict (customer_id) do update set dnc = excluded.dnc, note = excluded.note, updated_by = auth.uid(), updated_at = now();
  insert into public.crm_consent_events (client_id, customer_id, kind, channel, status, how, location_id, note, recorded_by, staff_id)
    values (p_client, p_customer, 'dnc', null, case when p_dnc then 'on' else 'off' end, p_how, p_loc, nullif(btrim(p_note), ''), auth.uid(), public._crmb_staff());
  if p_dnc then
    update public.notify_outbox set status = 'cancelled', last_error = 'do_not_contact' where customer_id = p_customer and status = 'queued';
    get diagnostics cancelled = row_count;
  end if;
  return jsonb_build_object('customer_id', p_customer, 'dnc', p_dnc, 'unchanged', false, 'duplicate', false, 'cancelled', cancelled);
end $$;

-- ---------- read side ----------
create or replace function public._crmb_consent_state(p_customer uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'customer_id', p_customer,
    'dnc', coalesce((select p.dnc from public.crm_contact_prefs p where p.customer_id = p_customer), false),
    'channels', (select jsonb_object_agg(ch, jsonb_build_object(
        'status', coalesce(o.status, 'not_asked'), 'at', o.changed_at, 'source', o.source,
        'how', (select e.how from public.crm_consent_events e where e.customer_id = p_customer and e.channel = ch order by e.id desc limit 1),
        'by', (select e.staff_id from public.crm_consent_events e where e.customer_id = p_customer and e.channel = ch order by e.id desc limit 1)))
      from unnest(array['sms', 'whatsapp']) ch left join public.notify_optin o on o.customer_id = p_customer and o.channel = ch));
$$;

create or replace function public._crmb_consent_get(p_customer uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  return public._crmb_consent_state(p_customer) || jsonb_build_object('block', public._crmb_block_reason(p_customer, 'sms'), 'can_manage', public._i62_ok());
end $$;

create or replace function public._crmb_consent_get_mobile(p_mobile text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare m text; cid uuid;
begin
  if not public._crmb_consent_ok() then raise exception 'not allowed'; end if;
  begin m := public.norm_mobile(p_mobile); exception when others then return jsonb_build_object('found', false); end;
  select id into cid from public.customers where mobile = m;
  if cid is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true) || public._crmb_consent_state(cid);
end $$;

create or replace function public._crmb_consent_history(p_customer uuid, p_limit int default 30) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (
    select e.id, e.at, e.kind, e.channel, e.status, e.how, e.location_id, e.note, e.text_version, e.staff_id from public.crm_consent_events e
     where e.customer_id = p_customer order by e.id desc limit least(greatest(coalesce(p_limit, 30), 1), 200)) z), '[]'::jsonb);
end $$;

-- counts only: who has been asked, who said yes / no, who is do-not-contact. No name, no phone.
create or replace function public._crmb_consent_summary() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare tot int; r jsonb := '{}'::jsonb; ch text; n_in int; n_out int; dn int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  select count(*) into tot from public.customers where active;
  select count(*) into dn from public.crm_contact_prefs p join public.customers c on c.id = p.customer_id where p.dnc and c.active;
  foreach ch in array array['sms', 'whatsapp'] loop
    select count(*) filter (where o.status = 'in'), count(*) filter (where o.status = 'out') into n_in, n_out
      from public.notify_optin o join public.customers c on c.id = o.customer_id where o.channel = ch and c.active;
    r := r || jsonb_build_object(ch, jsonb_build_object('in', n_in, 'out', n_out, 'not_asked', greatest(tot - n_in - n_out, 0),
          'coverage_pct', case when tot = 0 then null else round(100.0 * (n_in + n_out) / tot, 1) end));
  end loop;
  return jsonb_build_object('active_customers', tot, 'dnc', dn, 'channels', r);
end $$;

-- ---------- paper list import (owner or customer manager; dry run first) ----------
-- p_rows = [{"mobile": "01XXXXXXXXX"}, ...]. p_in true = they said yes on the paper list, false = they asked not to be contacted.
-- A customer who has withdrawn (status out) is NEVER turned back to yes by an import: that needs the one-by-one yes with a reason.
create or replace function public._crmb_consent_import(p_client uuid, p_rows jsonb, p_channel text, p_in boolean, p_list_note text, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; i int := 0; m text; cid uuid; cur text; st text; out_rows jsonb := '[]'::jsonb; seen text[] := '{}'; n_ok int := 0; n_same int := 0; n_err int := 0; n_blocked int := 0; ex int; want text := case when p_in then 'in' else 'out' end;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_client is null or p_rows is null or jsonb_typeof(p_rows) <> 'array' or p_in is null or p_channel not in ('sms', 'whatsapp') then raise exception 'bad_input'; end if;
  if coalesce(length(btrim(p_list_note)), 0) < 3 or length(p_list_note) > 200 then raise exception 'reason_required'; end if;
  if jsonb_array_length(p_rows) = 0 then raise exception 'no_rows'; end if;
  if jsonb_array_length(p_rows) > 2000 then raise exception 'too_many_rows'; end if;
  if not p_dry then
    perform public._client_lock(p_client);
    select count(*) into ex from public.crm_consent_events where batch_id = p_client;
    if ex > 0 then return jsonb_build_object('dry', false, 'duplicate', true, 'changed', ex); end if;
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1; m := null; cid := null; st := null;
    begin m := public.norm_mobile(r ->> 'mobile'); exception when others then m := null; end;
    if m is null or m !~ '^01[0-9]{9}$' then st := 'bad_mobile';
    elsif m = any(seen) then st := 'duplicate_row';
    else
      seen := seen || m;
      select id into cid from public.customers where mobile = m;
      if cid is null then st := 'unknown_customer';
      else
        select status into cur from public.notify_optin where customer_id = cid and channel = p_channel;
        if cur = want then st := 'same';
        elsif p_in and cur = 'out' then st := 'withdrawn_kept';
        else st := 'will_change';
        end if;
      end if;
    end if;
    if st = 'will_change' then n_ok := n_ok + 1; elsif st = 'same' then n_same := n_same + 1; elsif st = 'withdrawn_kept' then n_blocked := n_blocked + 1; else n_err := n_err + 1; end if;
    out_rows := out_rows || jsonb_build_array(jsonb_build_object('i', i, 'mobile', m, 'status', st));
    if not p_dry and st = 'will_change' then
      perform public._crmb_consent_apply(cid, p_channel, p_in, 'import', p_list_note, null, null, null, p_client, false);
    end if;
  end loop;
  return jsonb_build_object('dry', p_dry, 'duplicate', false, 'will_change', n_ok, 'same', n_same, 'withdrawn_kept', n_blocked, 'errors', n_err, 'rows', out_rows);
end $$;

-- ---------- hook texts (single source of truth; docs/integration/CRM-B.md copies them) ----------
-- notify_enqueue: after its own opt-in check, refuse do-not-contact and a withdrawn "no" of a linked duplicate.   notify_optin_set: also write the evidence line.
create or replace function public._crmb_hook_pairs(p_fn text) returns text[] language sql immutable set search_path = public as $$
  select case p_fn
    when 'notify_enqueue' then array[
      $a$then raise exception 'not_opted_in'; end if;
  ph := public._i62_phone(c.mobile);$a$,
      $a$then raise exception 'not_opted_in'; end if;
  perform public._crmb_enqueue_guard(p_customer, p_channel); /* bosCRMB: do-not-contact and linked duplicates */
  ph := public._i62_phone(c.mobile);$a$]
    when 'notify_optin_set' then array[
      $a$  if not p_in then   -- opting out cancels what is still waiting$a$,
      $a$  perform public._crmb_legacy_evidence(p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note); /* bosCRMB: evidence line */
  if not p_in then   -- opting out cancels what is still waiting$a$]
  end;
$$;

-- evidence line for a change made through the old owner-only function (never blocks it)
create or replace function public._crmb_legacy_evidence(p_customer uuid, p_channel text, p_status text, p_source text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.crm_consent_events (customer_id, kind, channel, status, how, note, recorded_by, staff_id)
    values (p_customer, 'optin', p_channel, p_status, case when p_source = 'customer_consent' then 'other' else 'owner_entry' end, left('old function: ' || coalesce(p_note, ''), 300), auth.uid(), public._crmb_staff());
exception when others then
  raise warning 'crm evidence line skipped: %', sqlerrm;
end $$;

-- ---------- privileges (only the functions of THIS file, so pasting this file again never touches the grants of phases 304 and 305) ----------
do $p$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
            and p.proname = any (array['_crmb_present', '_crmb_patch', '_crmb_rule_seed', '_crmb_ro', '_crmb_consent_ok', '_crmb_staff', '_crmb_links_active', '_crmb_group_root', '_crmb_group_ids',
              '_crmb_block_reason', '_crmb_in_quiet', '_crmb_send_allowed', '_crmb_enqueue_guard', '_crmb_consent_apply', '_crmb_consent_check_input', '_crmb_consent_set',
              '_crmb_consent_set_mobile', '_crmb_prefs_set', '_crmb_consent_state', '_crmb_consent_get', '_crmb_consent_get_mobile', '_crmb_consent_history', '_crmb_consent_summary',
              '_crmb_consent_import', '_crmb_hook_pairs', '_crmb_legacy_evidence']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $p$;
grant execute on function public._crmb_consent_set(uuid, uuid, text, boolean, text, text, int, text), public._crmb_consent_set_mobile(uuid, text, text, boolean, text, text, int, text),
  public._crmb_prefs_set(uuid, uuid, boolean, text, text, int), public._crmb_consent_get(uuid), public._crmb_consent_get_mobile(text), public._crmb_consent_history(uuid, int),
  public._crmb_consent_summary(), public._crmb_consent_import(uuid, jsonb, text, boolean, text, boolean), public._crmb_consent_ok() to authenticated;
