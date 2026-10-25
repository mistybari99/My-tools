-- Phase 479 (bos480) - X1 FOUNDATION, part 1: connection registry, job runs, one gate for every outside or AI call, agent identities, audit actor columns, public site config.
-- Paste after phase 478 (tests/sql/ORDER.txt). Paste-twice safe. Earlier phase files are not edited. No existing function is patched: the audit actor columns use a NEW trigger.
-- Defaults (every new behaviour OFF / safe):
--   rule automation_on = false  -> the gate denies every call and job_run_start records a skipped run.
--   every integration is disabled, not_connected, read_only, dry_run, with monthly_call_cap = 0 (= budget not set, denies).
--   Secrets are NEVER stored: config is non-secret fields only (trigger refuses secret-looking keys and values); env_names holds the NAMES of server secrets only.
--   The Connect Center shows the owner where to set a secret; the value never comes back to the database or the browser.
-- Who may do what:
--   owner               : integration_add / integration_set / site_config_set / agent_account_set / webhook_rotation_record, reads everything here.
--   ops bot (backup / notify purpose, phase46): job_run_start / job_run_finish / job_heartbeat / integration_test_record, and x1_gate.
--   agent account (agent_accounts, below): x1_gate only. It can never hold a role or a grant (triggers below).
-- Tags: bos480. Test data only (test_*). Tests: supabase/phase479_test.sql.

-- ---------- rules (switches; new behaviour OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('automation_on', 'automation', 'switch', 'false', null, null, null, null,
  'স্বয়ংক্রিয় কাজ (সব) চালু', 'Automation (all) ON', 'Automation ON (every outside call, AI call and scheduled job)',
  'বন্ধ থাকলে কোনো বাইরের সেবা, AI বা নির্ধারিত কাজ চলবে না।', 'OFF = no outside service, no AI call and no scheduled job runs.', 400),
 ('automation_pause_until', 'automation', 'text', null, 'YYYY-MM-DDTHH:MM:SSZ', null, null, null,
  'স্বয়ংক্রিয় কাজ এই সময় পর্যন্ত বিরতি (খালি = বিরতি নেই)', 'Automation pause until (empty = no pause)', 'Pause automation until this time (empty = not paused)',
  'যেমন 2026-11-01T00:00:00+06:00। বোঝা না গেলে বিরতি ধরা হবে।', 'Example 2026-11-01T00:00:00+06:00. A value that cannot be read counts as paused.', 401)
 on conflict (key) do nothing;

-- ---------- helpers (not callable from the browser) ----------
create or replace function public._x1_is_bot() returns boolean language sql stable security definer set search_path = public as $$
  select public._is_ops('notify') or public._is_ops('backup');
$$;
create or replace function public._x1_job_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner() or public._x1_is_bot();
$$;
-- the active agent identity of the caller (null when the caller is not an agent)
create or replace function public._x1_agent() returns text language plpgsql stable security definer set search_path = public as $$
declare ag text;
begin
  select a.agent_name into ag from public.agent_accounts a where a.user_id = auth.uid() and a.active and public.is_active() limit 1;
  return ag;
end $$;
-- true while the owner's pause is in force; an unreadable pause value counts as paused (fail closed)
create or replace function public._x1_pause_active() returns boolean language plpgsql stable security definer set search_path = public as $$
declare p text := public.rule_txt('automation_pause_until');
begin
  if p is null then return false; end if;
  return now() < p::timestamptz;
exception when others then return true;
end $$;
-- removes what looks like a secret from free text (phone numbers and e-mail addresses); used on every error text the screens show
create or replace function public.x1_redact(p_text text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(coalesce(p_text, ''),
    '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]', 'g'),
    '(\+?880|0)?1[3-9][0-9]{8}', '[phone]', 'g');
$$;

-- ---------- integration registry ----------
create table if not exists public.integration_registry (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{2,40}$'),
  kind text not null check (kind in ('website', 'hosting', 'facebook_page', 'instagram', 'whatsapp_business', 'sms_gateway', 'email_smtp', 'payment', 'ai_provider', 'vision_provider', 'analytics', 'other')),
  label_bn text not null, label_en text not null,
  status text not null default 'not_connected' check (status in ('not_connected', 'configured', 'connected', 'error', 'disabled')),
  enabled boolean not null default false,
  read_only boolean not null default true,
  dry_run boolean not null default true,
  config jsonb not null default '{}'::jsonb,                 -- NON-SECRET fields only (guarded by the trigger below)
  env_names text[] not null default '{}'::text[],            -- NAMES of server-side secrets (for example an Edge secret name). Never a value.
  rate_per_min int not null default 10 check (rate_per_min between 0 and 10000),
  monthly_call_cap int not null default 0 check (monthly_call_cap >= 0),   -- 0 = budget not set: every call is denied
  config_version int not null default 1,
  last_ok_at timestamptz, last_error_at timestamptz, last_error text,
  last_test_at timestamptz, last_test_ok boolean, last_test_detail text,
  updated_at timestamptz not null default now(), updated_by uuid
);
create table if not exists public.integration_config_versions (
  id bigserial primary key,
  code text not null references public.integration_registry(code),
  version int not null, config jsonb not null, env_names text[] not null,
  changed_by uuid, changed_at timestamptz not null default now()
);

create or replace function public._x1_registry_guard() returns trigger language plpgsql set search_path = public as $$
declare k text; v jsonb; e text;
begin
  for k in select jsonb_object_keys(coalesce(new.config, '{}'::jsonb)) loop
    if k ~* '(secret|token|passw|pwd|api_?key|private|credential|pin|bearer|signing|auth)' then raise exception 'secret_not_allowed: config key %', k; end if;
    v := new.config -> k;
    if jsonb_typeof(v) = 'string' and (length(v #>> '{}') > 300 or (v #>> '{}') ~ '^(eyJ|sk[-_]|ghp_|xox[abp]-|AKIA|Bearer )') then raise exception 'secret_not_allowed: value of %', k; end if;
  end loop;
  foreach e in array coalesce(new.env_names, '{}'::text[]) loop
    if e !~ '^[A-Z][A-Z0-9_]{2,60}$' then raise exception 'env_name_must_be_a_name: only the NAME of the secret, never its value'; end if;
  end loop;
  return new;
end $$;
drop trigger if exists integration_registry_guard on public.integration_registry;
create trigger integration_registry_guard before insert or update on public.integration_registry for each row execute function public._x1_registry_guard();

insert into public.integration_registry (code, kind, label_bn, label_en) select * from (values
  ('website', 'website', 'ওয়েবসাইট / ডোমেইন', 'Website / domain'),
  ('hosting', 'hosting', 'হোস্টিং', 'Hosting'),
  ('facebook_page', 'facebook_page', 'ফেসবুক পেজ', 'Facebook Page'),
  ('instagram', 'instagram', 'ইনস্টাগ্রাম', 'Instagram'),
  ('whatsapp_business', 'whatsapp_business', 'হোয়াটসঅ্যাপ বিজনেস', 'WhatsApp Business'),
  ('sms_gateway', 'sms_gateway', 'এসএমএস গেটওয়ে', 'SMS gateway'),
  ('email_smtp', 'email_smtp', 'ইমেইল (SMTP)', 'E-mail (SMTP)'),
  ('bkash', 'payment', 'বিকাশ', 'bKash'),
  ('nagad', 'payment', 'নগদ', 'Nagad'),
  ('ai_provider', 'ai_provider', 'AI সেবা', 'AI provider'),
  ('vision_provider', 'vision_provider', 'ছবি পড়া (OCR / vision)', 'Image reading (OCR / vision)'),
  ('analytics', 'analytics', 'বিশ্লেষণ (analytics)', 'Analytics'),
  ('other', 'other', 'অন্যান্য সংযোগ', 'Other connection')
) as v(code, kind, label_bn, label_en)
on conflict (code) do nothing;

-- ---------- job runs and heartbeat ----------
create table if not exists public.job_runs (
  id bigserial primary key,
  job text not null check (job ~ '^[a-z_]{2,40}$'),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  ok boolean,                                    -- null = skipped (automation off or paused) or still running
  dry_run boolean not null default true,
  error text,
  counts jsonb not null default '{}'::jsonb,
  bot uuid
);
create index if not exists job_runs_job_recent on public.job_runs (job, id desc);
create table if not exists public.job_heartbeat (
  job text primary key check (job ~ '^[a-z_]{2,40}$'),
  seen_at timestamptz not null default now(),
  note text
);

-- ---------- agent identities (least privilege: no role, no grant, ever) ----------
create table if not exists public.agent_accounts (
  user_id uuid primary key references public.profiles(id),
  agent_name text not null check (agent_name ~ '^[a-z][a-z0-9_]{2,40}$'),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create or replace function public._x1_agent_guard_roles() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.agent_accounts a where a.user_id = new.user_id) then raise exception 'agent_cannot_hold_roles'; end if;
  return new;
end $$;
create or replace function public._x1_agent_guard_grants() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.agent_accounts a where a.user_id = new.user_id) then raise exception 'agent_cannot_hold_grants'; end if;
  return new;
end $$;
drop trigger if exists user_roles_agent_guard on public.user_roles;
create trigger user_roles_agent_guard before insert or update on public.user_roles for each row execute function public._x1_agent_guard_roles();
drop trigger if exists user_grants_agent_guard on public.user_grants;
create trigger user_grants_agent_guard before insert or update on public.user_grants for each row execute function public._x1_agent_guard_grants();

-- ---------- the gate: every outside or AI call goes through it ----------
create table if not exists public.x1_gate_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  code text not null, kind text not null, write boolean not null default false,
  allowed boolean not null, reason text not null,
  actor uuid, actor_type text not null default 'human'
);
create index if not exists x1_gate_log_code_at on public.x1_gate_log (code, at);

-- x1_gate(kind, code, write, customer): allow / deny with a reason. Checks, in order: automation_on, pause, integration exists, enabled, configured,
-- read-only (writes), do-not-contact (crm_contact_prefs), budget (monthly_call_cap, 0 = not set), rate (rate_per_min), dry run (writes). Every decision is logged.
-- A write while dry_run is ON is never allowed: the caller only reports what it would have sent.
create or replace function public.x1_gate(p_kind text, p_code text, p_write boolean default false, p_customer uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.integration_registry; reason text := null; allow boolean := false; dry boolean := false; act_type text; ag text := public._x1_agent();
begin
  if not (public.is_owner() or public._x1_is_bot() or ag is not null) then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind !~ '^[a-z_]{2,40}$' or p_code is null then raise exception 'bad_input'; end if;
  act_type := case when ag is not null then 'agent' when public._x1_is_bot() then 'bot' else 'human' end;
  if not public.rule_on('automation_on') then reason := 'automation_off';
  elsif public._x1_pause_active() then reason := 'paused';
  else
    select * into r from public.integration_registry where code = p_code;
    if not found then reason := 'unknown_integration';
    elsif not r.enabled or r.status = 'disabled' then reason := 'integration_off';
    elsif r.status not in ('configured', 'connected') then reason := 'not_configured';
    elsif coalesce(p_write, false) and r.read_only then reason := 'read_only';
    elsif p_customer is not null and exists (select 1 from public.crm_contact_prefs c where c.customer_id = p_customer and c.dnc) then reason := 'do_not_contact';
    elsif r.monthly_call_cap = 0 then reason := 'budget_not_set';
    elsif (select count(*) from public.x1_gate_log g where g.code = p_code and g.allowed and g.at >= date_trunc('month', now())) >= r.monthly_call_cap then reason := 'budget_exhausted';
    elsif (select count(*) from public.x1_gate_log g where g.code = p_code and g.allowed and g.at >= now() - interval '1 minute') >= r.rate_per_min then reason := 'rate_limited';
    elsif coalesce(p_write, false) and r.dry_run then reason := 'dry_run'; dry := true;
    else allow := true; reason := 'ok';
    end if;
  end if;
  insert into public.x1_gate_log (code, kind, write, allowed, reason, actor, actor_type) values (p_code, p_kind, coalesce(p_write, false), allow, reason, auth.uid(), act_type);
  return jsonb_build_object('allow', allow, 'reason', reason, 'dry_run', dry, 'code', p_code, 'kind', p_kind);
end $$;

-- ---------- job functions (ops bots and the owner) ----------
create or replace function public.job_run_start(p_job text, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rid bigint; reason text := null;
begin
  if not public._x1_job_ok() then raise exception 'not allowed'; end if;
  if p_job is null or p_job !~ '^[a-z_]{2,40}$' then raise exception 'bad_input'; end if;
  if not public.rule_on('automation_on') then reason := 'automation_off'; elsif public._x1_pause_active() then reason := 'paused'; end if;
  if reason is not null then
    insert into public.job_runs (job, dry_run, finished_at, ok, error, bot) values (p_job, coalesce(p_dry, true), now(), null, 'skipped: ' || reason, auth.uid()) returning id into rid;
    return jsonb_build_object('allowed', false, 'reason', reason, 'run_id', rid, 'dry_run', coalesce(p_dry, true));
  end if;
  insert into public.job_runs (job, dry_run, bot) values (p_job, coalesce(p_dry, true), auth.uid()) returning id into rid;
  return jsonb_build_object('allowed', true, 'reason', 'ok', 'run_id', rid, 'dry_run', coalesce(p_dry, true));
end $$;

create or replace function public.job_run_finish(p_run bigint, p_ok boolean, p_error text default null, p_counts jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._x1_job_ok() then raise exception 'not allowed'; end if;
  update public.job_runs set finished_at = now(), ok = p_ok, error = left(public.x1_redact(p_error), 500), counts = coalesce(p_counts, '{}'::jsonb)
    where id = p_run and (bot = auth.uid() or public.is_owner());
  get diagnostics n = row_count;
  return jsonb_build_object('updated', n);
end $$;

create or replace function public.job_heartbeat(p_job text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._x1_job_ok() then raise exception 'not allowed'; end if;
  if p_job is null or p_job !~ '^[a-z_]{2,40}$' then raise exception 'bad_input'; end if;
  insert into public.job_heartbeat (job, seen_at, note) values (p_job, now(), left(public.x1_redact(p_note), 200))
    on conflict (job) do update set seen_at = now(), note = excluded.note;
  return jsonb_build_object('job', p_job, 'ok', true);
end $$;

-- ---------- owner: the registry ----------
create or replace function public.integration_set(p_code text, p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.integration_registry; f jsonb := coalesce(p_fields, '{}'::jsonb); k text; newcfg jsonb; newenv text[]; changed boolean := false;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  select * into r from public.integration_registry where code = p_code for update;
  if not found then raise exception 'integration_not_found'; end if;
  for k in select jsonb_object_keys(f) loop
    if k not in ('config', 'env_names', 'rate_per_min', 'monthly_call_cap', 'enabled', 'read_only', 'dry_run') then raise exception 'field_not_allowed: %', k; end if;
  end loop;
  newcfg := case when f ? 'config' then f -> 'config' else r.config end;
  newenv := case when f ? 'env_names' then array(select jsonb_array_elements_text(f -> 'env_names')) else r.env_names end;
  if jsonb_typeof(newcfg) <> 'object' then raise exception 'bad_input: config must be an object'; end if;
  changed := newcfg is distinct from r.config or newenv is distinct from r.env_names;
  update public.integration_registry set
    config = newcfg, env_names = newenv,
    rate_per_min = coalesce((f ->> 'rate_per_min')::int, rate_per_min),
    monthly_call_cap = coalesce((f ->> 'monthly_call_cap')::int, monthly_call_cap),
    enabled = coalesce((f ->> 'enabled')::boolean, enabled),
    read_only = coalesce((f ->> 'read_only')::boolean, read_only),
    dry_run = coalesce((f ->> 'dry_run')::boolean, dry_run),
    status = case when changed and status = 'not_connected' and (newcfg <> '{}'::jsonb or cardinality(newenv) > 0) then 'configured' else status end,
    config_version = config_version + case when changed then 1 else 0 end,
    updated_at = now(), updated_by = auth.uid()
  where code = p_code returning * into r;
  if changed then insert into public.integration_config_versions (code, version, config, env_names, changed_by) values (p_code, r.config_version, r.config, r.env_names, auth.uid()); end if;
  return jsonb_build_object('code', p_code, 'status', r.status, 'enabled', r.enabled, 'read_only', r.read_only, 'dry_run', r.dry_run, 'config_version', r.config_version);
end $$;

-- a test result comes from the server-side check (ops bot or owner); the detail is redacted and short. Never sets a secret.
create or replace function public.integration_test_record(p_code text, p_ok boolean, p_detail text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.integration_registry;
begin
  if not public._x1_job_ok() then raise exception 'not allowed'; end if;
  update public.integration_registry set last_test_at = now(), last_test_ok = p_ok, last_test_detail = left(public.x1_redact(p_detail), 300),
    last_ok_at = case when p_ok then now() else last_ok_at end,
    last_error_at = case when p_ok then last_error_at else now() end,
    last_error = case when p_ok then null else left(public.x1_redact(p_detail), 300) end,
    status = case when status = 'disabled' then 'disabled' when p_ok then 'connected' else 'error' end,
    updated_at = now(), updated_by = auth.uid()
  where code = p_code returning * into r;
  if not found then raise exception 'integration_not_found'; end if;
  return jsonb_build_object('code', p_code, 'status', r.status, 'last_test_ok', r.last_test_ok);
end $$;

-- the owner records that a webhook / API secret was rotated: the NAME and the time only, never the value
create table if not exists public.webhook_rotations (
  id bigserial primary key,
  code text not null references public.integration_registry(code),
  env_name text not null check (env_name ~ '^[A-Z][A-Z0-9_]{2,60}$'),
  rotated_at timestamptz not null default now(), rotated_by uuid,
  note text
);
create or replace function public.webhook_rotation_record(p_code text, p_env_name text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare rid bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  insert into public.webhook_rotations (code, env_name, rotated_by, note) values (p_code, p_env_name, auth.uid(), left(public.x1_redact(p_note), 200)) returning id into rid;
  return jsonb_build_object('id', rid, 'code', p_code);
end $$;

-- ---------- owner: agent accounts ----------
create or replace function public.agent_account_set(p_user uuid, p_agent_name text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_user is null or p_agent_name is null or p_agent_name !~ '^[a-z][a-z0-9_]{2,40}$' or p_active is null then raise exception 'bad_input'; end if;
  if p_user = auth.uid() then raise exception 'owner_cannot_be_agent'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'user_not_found'; end if;
  if exists (select 1 from public.user_roles where user_id = p_user) or exists (select 1 from public.user_grants where user_id = p_user) then
    raise exception 'agent_must_have_no_roles_or_grants';
  end if;
  insert into public.agent_accounts (user_id, agent_name, active, created_by) values (p_user, p_agent_name, p_active, auth.uid())
    on conflict (user_id) do update set agent_name = excluded.agent_name, active = excluded.active, updated_at = now();
  return jsonb_build_object('user_id', p_user, 'agent_name', p_agent_name, 'active', p_active);
end $$;

-- ---------- audit actor columns (nullable; default human) ----------
alter table public.audit_log add column if not exists actor_type text default 'human';
alter table public.audit_log add column if not exists agent_id text;
alter table public.audit_log add column if not exists on_behalf_of uuid;
create or replace function public._x1_audit_actor() returns trigger language plpgsql security definer set search_path = public as $$
declare ag text := public._x1_agent();
begin
  if ag is not null then new.actor_type := 'agent'; new.agent_id := ag;
  elsif public._x1_is_bot() then new.actor_type := 'bot';
  elsif new.actor_type is null then new.actor_type := 'human';
  end if;
  return new;
end $$;
drop trigger if exists audit_log_x1_actor on public.audit_log;
create trigger audit_log_x1_actor before insert on public.audit_log for each row execute function public._x1_audit_actor();

-- ---------- public site config (read by the website, phase X2) ----------
create table if not exists public.site_config (
  id int primary key default 1 check (id = 1),
  domain text, public_base_url text,
  brand_name_bn text, brand_name_en text,
  logo_ref text, contact_phone text, contact_email text,
  theme jsonb not null default '{}'::jsonb,
  allowed_origins text[] not null default '{}'::text[],
  published boolean not null default false,
  updated_at timestamptz not null default now(), updated_by uuid
);
insert into public.site_config (id) values (1) on conflict (id) do nothing;
create or replace function public.site_config_set(p_fields jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare f jsonb := coalesce(p_fields, '{}'::jsonb); k text; o text; r public.site_config;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  for k in select jsonb_object_keys(f) loop
    if k not in ('domain', 'public_base_url', 'brand_name_bn', 'brand_name_en', 'logo_ref', 'contact_phone', 'contact_email', 'theme', 'allowed_origins', 'published') then raise exception 'field_not_allowed: %', k; end if;
  end loop;
  if f ? 'public_base_url' and f ->> 'public_base_url' is not null and f ->> 'public_base_url' !~ '^https://[a-z0-9.-]+(/.*)?$' then raise exception 'bad_input: public_base_url must be https'; end if;
  if f ? 'allowed_origins' then
    for o in select jsonb_array_elements_text(f -> 'allowed_origins') loop
      if o !~ '^https://[a-z0-9.-]+$' then raise exception 'bad_input: allowed origin must be https://host'; end if;
    end loop;
  end if;
  if f ? 'theme' and jsonb_typeof(f -> 'theme') <> 'object' then raise exception 'bad_input: theme must be an object'; end if;
  update public.site_config set
    domain = case when f ? 'domain' then f ->> 'domain' else domain end,
    public_base_url = case when f ? 'public_base_url' then f ->> 'public_base_url' else public_base_url end,
    brand_name_bn = case when f ? 'brand_name_bn' then f ->> 'brand_name_bn' else brand_name_bn end,
    brand_name_en = case when f ? 'brand_name_en' then f ->> 'brand_name_en' else brand_name_en end,
    logo_ref = case when f ? 'logo_ref' then f ->> 'logo_ref' else logo_ref end,
    contact_phone = case when f ? 'contact_phone' then f ->> 'contact_phone' else contact_phone end,
    contact_email = case when f ? 'contact_email' then f ->> 'contact_email' else contact_email end,
    theme = case when f ? 'theme' then f -> 'theme' else theme end,
    allowed_origins = case when f ? 'allowed_origins' then array(select jsonb_array_elements_text(f -> 'allowed_origins')) else allowed_origins end,
    published = case when f ? 'published' then (f ->> 'published')::boolean else published end,
    updated_at = now(), updated_by = auth.uid()
  where id = 1 returning * into r;
  return jsonb_build_object('published', r.published, 'domain', r.domain, 'public_base_url', r.public_base_url);
end $$;
-- signed-in readers only (anon is refused); the website reads it through this function
create or replace function public.site_config_get() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_active() then (select jsonb_build_object('published', s.published, 'domain', s.domain, 'public_base_url', s.public_base_url,
      'brand_name_bn', s.brand_name_bn, 'brand_name_en', s.brand_name_en, 'logo_ref', s.logo_ref, 'contact_phone', s.contact_phone,
      'contact_email', s.contact_email, 'theme', s.theme, 'allowed_origins', to_jsonb(s.allowed_origins)) from public.site_config s where s.id = 1) end;
$$;

-- ---------- row level security: read by the owner, writes only through the functions above ----------
do $$ declare t text; begin
  foreach t in array array['integration_registry', 'integration_config_versions', 'job_runs', 'job_heartbeat', 'agent_accounts', 'x1_gate_log', 'webhook_rotations', 'site_config'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
drop policy if exists x1_registry_read on public.integration_registry;
create policy x1_registry_read on public.integration_registry for select to authenticated using (public.is_owner());
drop policy if exists x1_versions_read on public.integration_config_versions;
create policy x1_versions_read on public.integration_config_versions for select to authenticated using (public.is_owner());
drop policy if exists x1_jobs_read on public.job_runs;
create policy x1_jobs_read on public.job_runs for select to authenticated using (public.is_owner());
drop policy if exists x1_heartbeat_read on public.job_heartbeat;
create policy x1_heartbeat_read on public.job_heartbeat for select to authenticated using (public.is_owner());
drop policy if exists x1_agents_read on public.agent_accounts;
create policy x1_agents_read on public.agent_accounts for select to authenticated using (public.is_owner());
drop policy if exists x1_gate_read on public.x1_gate_log;
create policy x1_gate_read on public.x1_gate_log for select to authenticated using (public.is_owner());
drop policy if exists x1_rotations_read on public.webhook_rotations;
create policy x1_rotations_read on public.webhook_rotations for select to authenticated using (public.is_owner());
drop policy if exists x1_site_read on public.site_config;
create policy x1_site_read on public.site_config for select to authenticated using (public.is_owner());
drop trigger if exists x1_registry_audit on public.integration_registry;
create trigger x1_registry_audit after insert or update on public.integration_registry for each row execute function public.log_change('code');
drop trigger if exists x1_site_audit on public.site_config;
create trigger x1_site_audit after update on public.site_config for each row execute function public.log_change('id');
drop trigger if exists x1_agents_audit on public.agent_accounts;
create trigger x1_agents_audit after insert or update on public.agent_accounts for each row execute function public.log_change('user_id');

-- ---------- execute rights: nothing for anon; signed-in roles only where the function checks the caller ----------
do $$ declare f text; begin
  foreach f in array array['public._x1_is_bot()', 'public._x1_job_ok()', 'public._x1_agent()', 'public._x1_pause_active()', 'public._x1_registry_guard()', 'public._x1_agent_guard_roles()',
    'public._x1_agent_guard_grants()', 'public._x1_audit_actor()', 'public.x1_redact(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array['public.x1_gate(text,text,boolean,uuid)', 'public.job_run_start(text,boolean)', 'public.job_run_finish(bigint,boolean,text,jsonb)',
    'public.job_heartbeat(text,text)', 'public.integration_set(text,jsonb)', 'public.integration_test_record(text,boolean,text)', 'public.webhook_rotation_record(text,text,text)',
    'public.agent_account_set(uuid,text,boolean)', 'public.site_config_set(jsonb)', 'public.site_config_get()'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
