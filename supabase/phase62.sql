-- ============================================================
-- Phase 62 (bos62) - P3 gaps #21 SMS/WhatsApp queue, #22 payment-gateway intents + webhook log + reconciliation,
--                    #23 accounting CSV export, #30 AI Assistant access (owner by default, others only with grant assistant_use).
-- Additive + paste-twice safe. No provider credentials anywhere: sending SMS/WhatsApp is done by tools/notify_sms.py (env secrets, default OFF);
-- the payment gateway is called ONLY by a (not yet deployed) Edge function whose contract is in docs/INTEGRATIONS_P3C.md. Nothing here calls a provider.
-- Runs after phase51 (uses phase40 accounts, phase46 ops bot (_is_ops 'notify'), phase47 assistant).
--   #21  tables: notify_templates, notify_optin, notify_outbox (queue: status, attempts, next_try_at) ; rule notify_sms_on (OFF)
--        browser: notify_template_save, notify_optin_set, notify_enqueue, notify_cancel, notify_outbox_summary
--        worker (ops bot purpose 'notify' or owner): notify_outbox_claim, notify_outbox_report
--   #22  tables: payment_intents, payment_webhook_log (append-only, unique (provider, event_id)) ; view payment_recon_v (not browser-readable) ;
--        rule pay_gateway_on (OFF) ; fns payment_intent_create, payment_intent_set_ref, payment_intent_link, payment_webhook_receive, payment_recon
--   #23  acct_export_csv(kind, from, to, loc) read-only; owner or accounts_manage (columns documented in docs/INTEGRATIONS_P3C.md)
--   #30  _assistant_ok() tightened (owner or explicit assistant_use only); grant_defs row (idempotent); assistant_access_list() owner-only
-- ============================================================

-- ---------- rules (default OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('notify_sms_on', 'integrations', 'switch', 'false', null, null, null, null, 'SMS / WhatsApp কিউ চালু', 'SMS / WhatsApp queue চালু', 'SMS / WhatsApp queue is on',
  'বন্ধ থাকলে কিছু কিউতে ঢোকে না ও কিছু পাঠানো হয় না। পাঠায় tools/notify_sms.py (গোপন চাবি শুধু GitHub secret-এ)।', 'Off = nothing is queued or sent. Sending is done by tools/notify_sms.py (secrets live only in GitHub secrets).', 620),
 ('notify_sms_max_tries', 'integrations', 'number', '5', 'times', null, 1, 20, 'একটি বার্তা সর্বোচ্চ কতবার চেষ্টা', 'একটি message সর্বোচ্চ কতবার try', 'Most send attempts per message', null, null, 621),
 ('pay_gateway_on', 'integrations', 'switch', 'false', null, null, null, null, 'পেমেন্ট গেটওয়ে রেকর্ড চালু', 'Payment gateway record চালু', 'Payment-gateway records are on',
  'শুধু রেকর্ড ও মিলানো; অ্যাপ কোনো গেটওয়ে কল করে না। চালু করার আগে Edge function লাগবে।', 'Records and reconciliation only; the app never calls a gateway. An Edge function is needed first.', 622)
on conflict (key) do nothing;

-- ---------- grants (idempotent) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'assistant_use', 'reports', 90, 'ব্যবসার সহকারী ব্যবহার', 'Business assistant ব্যবহার', 'Use the business assistant', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'assistant_use');

-- ---------- small helpers (closed to browsers) ----------
create or replace function public._i62_ok() returns boolean   -- owner or customer manager: SMS queue / opt-in / templates
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('customer_manage')
    or exists (select 1 from public.locations l where public.has_grant('customer_manage', l.id)));
$$;
create or replace function public._i62_ops() returns boolean   -- the ops bot (purpose notify) or the owner
language sql stable security definer set search_path = public as $$
  select public.is_active() and public.is_owner() or public._is_ops('notify');
$$;
create or replace function public._i62_pay_ok() returns boolean   -- owner or accounts manager
language sql stable security definer set search_path = public as $$ select public._acct_manage(); $$;
create or replace function public._i62_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
create or replace function public._i62_phone(p text) returns text language plpgsql immutable set search_path = public as $$
declare d text := regexp_replace(coalesce(p, ''), '[\s\-\(\)]', '', 'g');
begin
  if d ~ '^01[0-9]{9}$' then return '+880' || substr(d, 2); end if;
  if d ~ '^8801[0-9]{9}$' then return '+' || d; end if;
  if d ~ '^\+[1-9][0-9]{7,14}$' then return d; end if;
  return null;
end $$;
create or replace function public._i62_csv(p text) returns text language sql immutable set search_path = public as $$
  -- RFC 4180 quoting + spreadsheet formula guard (a cell never starts with = + - @ tab CR)
  select case when p is null then ''
    else (select case when v ~ '[",\r\n]' then '"' || replace(v, '"', '""') || '"' else v end
            from (select case when p ~ '^[=+\-@\t\r]' then '''' || p else p end v) s) end;
$$;

-- ============================================================
-- #21  SMS / WhatsApp queue
-- ============================================================
create table if not exists public.notify_templates (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  channel text not null default 'sms' check (channel in ('sms', 'whatsapp')),
  body_bn text not null check (length(body_bn) between 1 and 480),
  body_en text not null check (length(body_en) between 1 and 480),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
create table if not exists public.notify_optin (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  channel text not null check (channel in ('sms', 'whatsapp')),
  status text not null check (status in ('in', 'out')),
  source text not null default 'owner_entry' check (source in ('customer_consent', 'owner_entry')),
  note text check (note is null or length(note) <= 200),
  changed_by uuid, changed_at timestamptz not null default now(),
  unique (customer_id, channel)
);
create table if not exists public.notify_optin_log (          -- append-only history of every opt-in / opt-out
  id bigserial primary key, customer_id uuid not null, channel text not null, status text not null, source text, note text,
  changed_by uuid, changed_at timestamptz not null default now()
);
create table if not exists public.notify_outbox (
  id bigserial primary key,
  client_id uuid unique,
  customer_id uuid references public.customers(id),
  channel text not null check (channel in ('sms', 'whatsapp')),
  to_phone text not null check (to_phone ~ '^\+[1-9][0-9]{7,14}$'),
  template_code text not null references public.notify_templates(code),
  body text not null check (length(body) between 1 and 480),
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed', 'cancelled')),
  attempts int not null default 0 check (attempts >= 0),
  max_attempts int not null default 5 check (max_attempts between 1 and 20),
  next_try_at timestamptz not null default now(),
  last_error text check (last_error is null or length(last_error) <= 300),
  provider_ref text check (provider_ref is null or length(provider_ref) <= 100),
  source_type text, source_id text,
  created_by uuid, created_at timestamptz not null default now(),
  claimed_at timestamptz, sent_at timestamptz
);
create unique index if not exists notify_outbox_src_uq on public.notify_outbox (source_type, source_id, template_code) where source_type is not null and source_id is not null;
create index if not exists notify_outbox_due on public.notify_outbox (status, next_try_at);

do $$ declare t text; begin
  foreach t in array array['notify_templates', 'notify_optin', 'notify_optin_log', 'notify_outbox'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_ok())', t || '_read', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists notify_optin_log_ro on public.notify_optin_log;
create trigger notify_optin_log_ro before update or delete on public.notify_optin_log for each row execute function public._i62_ro();
drop trigger if exists audit_notify_outbox on public.notify_outbox;
create trigger audit_notify_outbox after insert or update on public.notify_outbox for each row execute function public.log_change('id');
drop trigger if exists audit_notify_templates on public.notify_templates;
create trigger audit_notify_templates after insert or update on public.notify_templates for each row execute function public.log_change('code');
revoke usage, select on sequence public.notify_optin_id_seq, public.notify_optin_log_id_seq, public.notify_outbox_id_seq from public, anon, authenticated;

insert into public.notify_templates (code, channel, body_bn, body_en) values
 ('due_reminder', 'sms', 'প্রিয় {name}, আপনার বাকি {amount} টাকা। ধন্যবাদ। - {shop}', 'Dear {name}, your balance due is {amount} Taka. Thank you. - {shop}'),
 ('order_ready', 'sms', '{name}, আপনার অর্ডার {ref} প্রস্তুত। - {shop}', '{name}, your order {ref} is ready. - {shop}'),
 ('thanks', 'sms', '{name}, কেনাকাটার জন্য ধন্যবাদ। - {shop}', '{name}, thank you for shopping with us. - {shop}')
on conflict (code) do nothing;

create or replace function public.notify_template_save(p_code text, p_channel text, p_body_bn text, p_body_en text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,40}$' or p_channel not in ('sms', 'whatsapp') or p_active is null
     or coalesce(length(btrim(p_body_bn)), 0) not between 1 and 480 or coalesce(length(btrim(p_body_en)), 0) not between 1 and 480 then raise exception 'bad_input'; end if;
  insert into public.notify_templates (code, channel, body_bn, body_en, active, updated_by) values (p_code, p_channel, btrim(p_body_bn), btrim(p_body_en), p_active, auth.uid())
    on conflict (code) do update set channel = excluded.channel, body_bn = excluded.body_bn, body_en = excluded.body_en, active = excluded.active, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('code', p_code, 'active', p_active);
end $$;

create or replace function public.notify_optin_set(p_customer uuid, p_channel text, p_in boolean, p_source text default 'owner_entry', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st text := case when p_in then 'in' else 'out' end;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_customer is null or p_in is null or p_channel not in ('sms', 'whatsapp') or coalesce(p_source, 'owner_entry') not in ('customer_consent', 'owner_entry')
     or (p_note is not null and length(p_note) > 200) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  if p_in and public._i62_phone((select mobile from public.customers where id = p_customer)) is null then raise exception 'bad_phone'; end if;
  insert into public.notify_optin (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid())
    on conflict (customer_id, channel) do update set status = excluded.status, source = excluded.source, note = excluded.note, changed_by = auth.uid(), changed_at = now();
  insert into public.notify_optin_log (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid());
  if not p_in then   -- opting out cancels what is still waiting
    update public.notify_outbox set status = 'cancelled', last_error = 'opted_out' where customer_id = p_customer and channel = p_channel and status = 'queued';
  end if;
  return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st);
end $$;

create or replace function public.notify_enqueue(p_client uuid, p_customer uuid, p_channel text, p_template text, p_vars jsonb default '{}'::jsonb, p_lang text default 'bn',
                                                 p_source_type text default null, p_source_id text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.notify_templates; c public.customers; ph text; b text; k text; v text; ex public.notify_outbox; nid bigint; mt int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_sms_on') then raise exception 'sms_off'; end if;
  if p_client is null or p_customer is null or p_channel not in ('sms', 'whatsapp') or p_template is null or coalesce(p_lang, 'bn') not in ('bn', 'en')
     or (p_vars is not null and jsonb_typeof(p_vars) <> 'object') or (p_source_type is null) <> (p_source_id is null)
     or (p_source_type is not null and (length(p_source_type) > 40 or length(p_source_id) > 80)) then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.notify_outbox where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true); end if;
  select * into t from public.notify_templates where code = p_template and active;
  if not found then raise exception 'template_not_found'; end if;
  if t.channel <> p_channel then raise exception 'template_channel_mismatch'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then raise exception 'not_opted_in'; end if;
  ph := public._i62_phone(c.mobile);
  if ph is null then raise exception 'bad_phone'; end if;
  b := case when coalesce(p_lang, 'bn') = 'en' then t.body_en else t.body_bn end;
  b := replace(b, '{name}', coalesce(left(c.name, 60), ''));
  for k, v in select key, left(value, 100) from jsonb_each_text(coalesce(p_vars, '{}'::jsonb)) loop
    if k ~ '^[a-z_]{1,20}$' then b := replace(b, '{' || k || '}', v); end if;
  end loop;
  b := regexp_replace(b, '\{[a-z_]{1,20}\}', '', 'g');
  if length(btrim(b)) not between 1 and 480 then raise exception 'bad_body'; end if;
  mt := greatest(least(coalesce(public.rule_num('notify_sms_max_tries'), 5)::int, 20), 1);
  begin
    insert into public.notify_outbox (client_id, customer_id, channel, to_phone, template_code, body, max_attempts, source_type, source_id, created_by)
      values (p_client, p_customer, p_channel, ph, p_template, btrim(b), mt, p_source_type, p_source_id, auth.uid()) returning id into nid;
  exception when unique_violation then
    select * into ex from public.notify_outbox where source_type = p_source_type and source_id = p_source_id and template_code = p_template;
    return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true);
  end;
  return jsonb_build_object('id', nid, 'status', 'queued', 'duplicate', false);
end $$;

create or replace function public.notify_cancel(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  update public.notify_outbox set status = 'cancelled', last_error = 'cancelled_by_staff' where id = p_id and status in ('queued', 'failed');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_cancellable'; end if;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

create or replace function public.notify_outbox_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('notify_sms_on'),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.notify_outbox group by status) s), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'status', status, 'attempts', attempts, 'max_attempts', max_attempts, 'template', template_code,
        'to', left(to_phone, 6) || '****' || right(to_phone, 2), 'last_error', last_error, 'created_at', created_at, 'sent_at', sent_at) order by id desc)
        from (select * from public.notify_outbox order by id desc limit 50) r), '[]'::jsonb));
end $$;

-- worker side (tools/notify_sms.py): claim due rows, then report each result. A stale 'sending' (> 15 min) is claimable again.
create or replace function public.notify_outbox_claim(p_limit int default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 20), 1), 100); res jsonb;
begin
  if not public._i62_ops() then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_sms_on') then return jsonb_build_object('on', false, 'rows', '[]'::jsonb); end if;
  with c as (
    select id from public.notify_outbox
     where ((status = 'queued' and next_try_at <= now()) or (status = 'sending' and claimed_at < now() - interval '15 minutes')) and attempts < max_attempts
     order by id limit lim for update skip locked),
  u as (update public.notify_outbox o set status = 'sending', attempts = o.attempts + 1, claimed_at = now() from c where o.id = c.id
        returning o.id, o.channel, o.to_phone, o.body, o.attempts)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'to', to_phone, 'body', body, 'attempt', attempts) order by id), '[]'::jsonb) into res from u;
  return jsonb_build_object('on', true, 'rows', res);
end $$;

create or replace function public.notify_outbox_report(p_id bigint, p_ok boolean, p_provider_ref text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.notify_outbox;
begin
  if not public._i62_ops() then raise exception 'not allowed'; end if;
  if p_id is null or p_ok is null then raise exception 'bad_input'; end if;
  select * into r from public.notify_outbox where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'sending' then return jsonb_build_object('id', p_id, 'status', r.status, 'ignored', true); end if;
  if p_ok then
    update public.notify_outbox set status = 'sent', sent_at = now(), provider_ref = left(p_provider_ref, 100), last_error = null where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'sent');
  end if;
  if r.attempts >= r.max_attempts then
    update public.notify_outbox set status = 'failed', last_error = left(coalesce(p_error, 'error'), 300) where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'failed');
  end if;
  update public.notify_outbox set status = 'queued', last_error = left(coalesce(p_error, 'error'), 300),
      next_try_at = now() + (interval '1 minute' * power(2, r.attempts)::int) where id = p_id;   -- back-off 2, 4, 8, 16 ... minutes
  return jsonb_build_object('id', p_id, 'status', 'queued', 'retry', true);
end $$;

-- ============================================================
-- #22  payment gateway: intents + webhook receipt log + reconciliation (no live call anywhere)
-- ============================================================
create table if not exists public.payment_intents (
  id bigserial primary key,
  client_id uuid unique,
  provider text not null check (provider ~ '^[a-z0-9_]{2,24}$'),
  provider_ref text check (provider_ref is null or length(provider_ref) between 3 and 100),
  sale_id uuid references public.sales(id),
  customer_id uuid references public.customers(id),
  location_id int not null references public.locations(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'created' check (status in ('created', 'pending', 'succeeded', 'failed', 'cancelled', 'refunded')),
  paid_amount numeric check (paid_amount is null or (paid_amount >= 0 and paid_amount <= 1000000000000)),
  sale_payment_id bigint references public.sale_payments(id),   -- manual link; otherwise matched by ref
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists payment_intents_ref_uq on public.payment_intents (provider, provider_ref) where provider_ref is not null;
create table if not exists public.payment_webhook_log (
  id bigserial primary key,
  provider text not null check (provider ~ '^[a-z0-9_]{2,24}$'),
  event_id text not null check (length(event_id) between 1 and 120),
  provider_ref text, event_type text check (event_type is null or length(event_type) <= 60),
  status text, amount numeric, signature_ok boolean not null,
  payload jsonb not null default '{}'::jsonb,
  applied boolean not null default false, note text,
  received_at timestamptz not null default now(),
  unique (provider, event_id)
);
do $$ declare t text; begin
  foreach t in array array['payment_intents', 'payment_webhook_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_pay_ok())', t || '_read', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists payment_webhook_log_ro on public.payment_webhook_log;
create trigger payment_webhook_log_ro before update or delete on public.payment_webhook_log for each row execute function public._i62_ro();
drop trigger if exists audit_payment_intents on public.payment_intents;
create trigger audit_payment_intents after insert or update on public.payment_intents for each row execute function public.log_change('id');
revoke usage, select on sequence public.payment_intents_id_seq, public.payment_webhook_log_id_seq from public, anon, authenticated;


create or replace function public.payment_intent_create(p_client uuid, p_provider text, p_sale uuid, p_customer uuid, p_loc int, p_amount numeric,
                                                        p_provider_ref text default null, p_currency text default 'BDT') returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.payment_intents; nid bigint;
begin
  if not (public._i62_pay_ok() or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_gateway_on') then raise exception 'gateway_off'; end if;
  if p_client is null or p_provider is null or p_provider !~ '^[a-z0-9_]{2,24}$' or p_loc is null or p_amount is null or p_amount <= 0 or p_amount > 1000000000000
     or p_amount <> round(p_amount, 2) or coalesce(p_currency, 'BDT') !~ '^[A-Z]{3}$' or (p_provider_ref is not null and length(p_provider_ref) not between 3 and 100) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not (public._acct_all() or public.can_loc(p_loc) or public._is_ops('notify')) then raise exception 'not allowed for this location'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.payment_intents where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true); end if;
  insert into public.payment_intents (client_id, provider, provider_ref, sale_id, customer_id, location_id, amount, currency, created_by)
    values (p_client, p_provider, p_provider_ref, p_sale, p_customer, p_loc, round(p_amount, 2), coalesce(p_currency, 'BDT'), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid, 'status', 'created', 'duplicate', false);
end $$;

create or replace function public.payment_intent_set_ref(p_id bigint, p_provider_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payment_intents;
begin
  if not (public._i62_pay_ok() or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  if p_provider_ref is null or length(p_provider_ref) not between 3 and 100 then raise exception 'bad_input'; end if;
  select * into r from public.payment_intents where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.provider_ref is not null and r.provider_ref <> p_provider_ref then raise exception 'ref_already_set'; end if;
  update public.payment_intents set provider_ref = p_provider_ref, status = case when status = 'created' then 'pending' else status end, updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'provider_ref', p_provider_ref);
end $$;

create or replace function public.payment_intent_link(p_id bigint, p_sale_payment bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.sale_payments where id = p_sale_payment) then raise exception 'payment_not_found'; end if;
  if exists (select 1 from public.payment_intents where sale_payment_id = p_sale_payment and id <> p_id) then raise exception 'payment_already_linked'; end if;
  update public.payment_intents set sale_payment_id = p_sale_payment, updated_at = now() where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'sale_payment_id', p_sale_payment);
end $$;

-- called ONLY by the Edge function (logged in as the ops bot) AFTER it verified the provider signature. Idempotent on (provider, event_id).
create or replace function public.payment_webhook_receive(p_provider text, p_event_id text, p_provider_ref text, p_event_type text, p_status text, p_amount numeric,
                                                          p_signature_ok boolean, p_payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.payment_intents; ap boolean := false; nt text; rk int; rk0 int; n int; pl jsonb;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_gateway_on') then return jsonb_build_object('off', true); end if;
  if p_provider is null or p_provider !~ '^[a-z0-9_]{2,24}$' or p_event_id is null or length(p_event_id) not between 1 and 120 or p_signature_ok is null
     or (p_status is not null and p_status not in ('pending', 'succeeded', 'failed', 'cancelled', 'refunded'))
     or (p_amount is not null and (p_amount < 0 or p_amount > 1000000000000)) or (p_provider_ref is not null and length(p_provider_ref) > 100)
     or (p_event_type is not null and length(p_event_type) > 60) or length(coalesce(p_payload, '{}'::jsonb)::text) > 20000 then raise exception 'bad_input'; end if;
  pl := coalesce(p_payload, '{}'::jsonb);
  if jsonb_typeof(pl) = 'object' then pl := pl - array['authorization', 'signature', 'secret', 'token', 'password', 'api_key', 'apikey', 'card', 'card_number', 'cvv']; end if;
  if not p_signature_ok then nt := 'bad_signature';
  else
    select * into it from public.payment_intents where provider = p_provider and provider_ref = p_provider_ref for update;
    if not found then nt := 'no_intent';
    elsif p_status is null then nt := 'no_status';
    else
      rk := case p_status when 'pending' then 1 when 'failed' then 2 when 'cancelled' then 2 when 'succeeded' then 3 else 4 end;
      rk0 := case it.status when 'created' then 0 when 'pending' then 1 when 'failed' then 2 when 'cancelled' then 2 when 'succeeded' then 3 else 4 end;
      if rk > rk0 or (rk = rk0 and rk = 2 and it.status <> p_status) then ap := true; nt := 'applied'; else nt := 'stale_event'; end if;
    end if;
  end if;
  insert into public.payment_webhook_log (provider, event_id, provider_ref, event_type, status, amount, signature_ok, payload, applied, note)
    values (p_provider, p_event_id, p_provider_ref, p_event_type, p_status, p_amount, p_signature_ok, pl, ap, nt) on conflict (provider, event_id) do nothing;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  if ap then
    update public.payment_intents set status = p_status, updated_at = now(),
        paid_amount = case when p_status = 'succeeded' then p_amount else paid_amount end where id = it.id;
  end if;
  return jsonb_build_object('duplicate', false, 'applied', ap, 'note', nt);
end $$;

-- reconciliation: one row per intent against sale_payments (matched by explicit link, else mobile payment with the same ref). Not readable by browsers: use payment_recon().
create or replace view public.payment_recon_v as
  select i.id as intent_id, i.provider, i.provider_ref, i.sale_id, i.location_id, i.amount as intent_amount, i.status as intent_status, i.paid_amount,
         sp.id as sale_payment_id, sp.amount as payment_amount, sp.voided as payment_voided,
         case when i.status in ('created', 'pending') then 'open'
              when i.status in ('failed', 'cancelled') then 'closed_unpaid'
              when i.status = 'refunded' then 'refunded'
              when sp.id is null then 'missing_payment'
              when sp.voided then 'voided_payment'
              when sp.amount <> coalesce(i.paid_amount, i.amount) or coalesce(i.paid_amount, i.amount) <> i.amount then 'amount_mismatch'
              else 'matched' end as state,
         coalesce(i.paid_amount, 0) - coalesce(sp.amount, 0) as diff
    from public.payment_intents i
    left join lateral (select p.* from public.sale_payments p
                        where p.id = i.sale_payment_id
                           or (i.sale_payment_id is null and i.provider_ref is not null and p.mode = 'mobile' and p.ref = i.provider_ref and not exists
                               (select 1 from public.payment_intents i2 where i2.sale_payment_id = p.id))
                        order by (p.id = i.sale_payment_id) desc, p.id limit 1) sp on true;
revoke all on public.payment_recon_v from public, anon, authenticated;

create or replace function public.payment_recon(p_from date default null, p_to date default null, p_state text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fr timestamptz; tt timestamptz; v_all boolean := public._acct_all();
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if p_state is not null and p_state not in ('open', 'closed_unpaid', 'refunded', 'missing_payment', 'voided_payment', 'amount_mismatch', 'matched') then raise exception 'bad_input'; end if;
  fr := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30)::timestamp at time zone 'Asia/Dhaka';
  tt := (coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date) + 1)::timestamp at time zone 'Asia/Dhaka';
  if tt - fr > interval '400 days' then raise exception 'bad_range'; end if;
  return jsonb_build_object('on', public.rule_on('pay_gateway_on'),
    'counts', coalesce((select jsonb_object_agg(state, n) from (select v.state, count(*) n from public.payment_recon_v v join public.payment_intents i on i.id = v.intent_id
                          where i.created_at >= fr and i.created_at < tt and (v_all or public.can_loc(v.location_id)) group by v.state) s), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.intent_id desc) from (
        select v.* from public.payment_recon_v v join public.payment_intents i on i.id = v.intent_id
         where i.created_at >= fr and i.created_at < tt and (v_all or public.can_loc(v.location_id)) and (p_state is null or v.state = p_state)
         order by v.intent_id desc limit 500) x), '[]'::jsonb),
    'orphan_events', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'provider', w.provider, 'event_id', w.event_id, 'provider_ref', w.provider_ref, 'status', w.status,
          'amount', w.amount, 'note', w.note, 'received_at', w.received_at) order by w.id desc)
        from (select * from public.payment_webhook_log where received_at >= fr and received_at < tt and note in ('no_intent', 'bad_signature') order by id desc limit 200) w), '[]'::jsonb));
end $$;

-- ============================================================
-- #23  accounting export (read-only, generic CSV)
-- ============================================================
create or replace function public.acct_export_csv(p_kind text, p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); cr text := E'\r\n';
  hdr text; body text; n int; tot int; cap constant int := 50000; tb jsonb; td numeric := 0; tc numeric := 0;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('journal', 'trial_balance') then raise exception 'bad_input'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  if fr > to_ or to_ - fr > 3660 then raise exception 'bad_range'; end if;
  if p_kind = 'journal' then
    hdr := 'entry_id,entry_date,location_code,source_type,source_id,subtype,status,reverses_id,entry_memo,line_no,account_code,account_name_en,account_type,debit,credit,line_location_code,party_type,party_id,line_memo';
    select count(*) into tot from public.journal_entries e where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
    select count(*), string_agg(r.line, cr order by r.entry_date, r.entry_id, r.line_no) into n, body from (
      select e.entry_date, e.id entry_id, l.line_no,
        concat_ws(',', e.id::text, e.entry_date::text, public._i62_csv(le.code), public._i62_csv(e.source_type), public._i62_csv(e.source_id), public._i62_csv(e.subtype), e.status,
          coalesce(e.reverses_id::text, ''), public._i62_csv(e.memo), l.line_no::text, public._i62_csv(a.code), public._i62_csv(a.name_en), a.type,
          to_char(l.debit, 'FM999999999999990.00'), to_char(l.credit, 'FM999999999999990.00'), public._i62_csv(ll.code), coalesce(l.party_type, ''), public._i62_csv(l.party_id), public._i62_csv(l.memo)) line
        from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
        left join public.locations le on le.id = e.location_id left join public.locations ll on ll.id = l.location_id
       where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc)
       order by e.entry_date, e.id, l.line_no limit cap) r;
    return jsonb_build_object('kind', 'journal', 'filename', 'journal_' || fr || '_' || to_ || '.csv', 'mime', 'text/csv', 'from', fr, 'to', to_, 'entries', tot, 'rows', coalesce(n, 0),
      'truncated', coalesce(n, 0) >= cap, 'csv', hdr || cr || coalesce(body, ''), 'columns', string_to_array(hdr, ','));
  end if;
  tb := public.acct_trial_balance(fr, to_, p_loc);
  hdr := 'account_code,account_name_en,account_name_bn,account_type,is_group,opening_debit,opening_credit,period_debit,period_credit,closing_debit,closing_credit';
  select count(*), string_agg(concat_ws(',', public._i62_csv(x ->> 'code'), public._i62_csv(x ->> 'name_en'), public._i62_csv(x ->> 'name_bn'), x ->> 'type', x ->> 'is_group',
          to_char((x ->> 'open_dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'open_cr')::numeric, 'FM999999999999990.00'),
          to_char((x ->> 'dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'cr')::numeric, 'FM999999999999990.00'),
          to_char((x ->> 'close_dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'close_cr')::numeric, 'FM999999999999990.00')), cr order by x ->> 'code')
    into n, body from jsonb_array_elements(tb -> 'rows') x;
  return jsonb_build_object('kind', 'trial_balance', 'filename', 'trial_balance_' || fr || '_' || to_ || '.csv', 'mime', 'text/csv', 'from', fr, 'to', to_, 'rows', coalesce(n, 0),
    'total_debit', tb -> 'total_debit', 'total_credit', tb -> 'total_credit', 'balanced', tb -> 'balanced', 'csv', hdr || cr || coalesce(body, ''), 'columns', string_to_array(hdr, ','));
end $$;

-- ============================================================
-- #30  AI Assistant access: owner by default, anyone else ONLY with the explicit grant assistant_use (bos62)
-- ============================================================
create or replace function public._assistant_ok() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then return false; end if;
  if not public.rule_on('assistant_on') then return false; end if;
  -- bos62: head_management and the assistant_roles rule no longer open the assistant; only the owner or an explicit assistant_use grant (any place) does
  return public.is_owner() or public._assistant_any_grant('assistant_use');
end $$;

create or replace function public.assistant_access_list() returns jsonb   -- owner only: who holds assistant_use (per person, per role)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('assistant_on'),
    'users', coalesce((select jsonb_agg(jsonb_build_object('user_id', g.user_id, 'name', p.full_name, 'location_id', g.location_id, 'valid_until', g.valid_until) order by p.full_name)
                         from public.user_grants g join public.profiles p on p.id = g.user_id where g.grant_code = 'assistant_use' and (g.valid_until is null or g.valid_until > now())), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(rg.role_code order by rg.role_code) from public.rule_grants rg where rg.grant_code = 'assistant_use' and rg.allowed), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
revoke all on function public._i62_ok(), public._i62_ops(), public._i62_ro(), public._i62_phone(text), public._i62_csv(text), public._i62_pay_ok() from public, anon, authenticated;
grant execute on function public._i62_ok(), public._i62_pay_ok() to authenticated;      -- used inside RLS policies
revoke all on function public.notify_template_save(text, text, text, text, boolean), public.notify_optin_set(uuid, text, boolean, text, text),
  public.notify_enqueue(uuid, uuid, text, text, jsonb, text, text, text), public.notify_cancel(bigint), public.notify_outbox_summary(),
  public.notify_outbox_claim(int), public.notify_outbox_report(bigint, boolean, text, text),
  public.payment_intent_create(uuid, text, uuid, uuid, int, numeric, text, text), public.payment_intent_set_ref(bigint, text), public.payment_intent_link(bigint, bigint),
  public.payment_webhook_receive(text, text, text, text, text, numeric, boolean, jsonb), public.payment_recon(date, date, text),
  public.acct_export_csv(text, date, date, int), public.assistant_access_list() from public, anon;
grant execute on function public.notify_template_save(text, text, text, text, boolean), public.notify_optin_set(uuid, text, boolean, text, text),
  public.notify_enqueue(uuid, uuid, text, text, jsonb, text, text, text), public.notify_cancel(bigint), public.notify_outbox_summary(),
  public.notify_outbox_claim(int), public.notify_outbox_report(bigint, boolean, text, text),
  public.payment_intent_create(uuid, text, uuid, uuid, int, numeric, text, text), public.payment_intent_set_ref(bigint, text), public.payment_intent_link(bigint, bigint),
  public.payment_webhook_receive(text, text, text, text, text, numeric, boolean, jsonb), public.payment_recon(date, date, text),
  public.acct_export_csv(text, date, date, int), public.assistant_access_list() to authenticated;
