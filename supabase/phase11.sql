-- BOS tool · Phase 11 (W1 hardening): audit_log append-only, immutable codes, no hard deletes, server-side PIN lockout + failed-login log.
-- Additive and re-runnable. Run AFTER phase8, phase9, phase10. Paste whole in the Supabase SQL editor.
-- No client behaviour changes: login_precheck(text)->jsonb, login_failed(text)->void, login_success()->void, unlock_staff(text)->void keep their signatures.

-- ---------- (a) audit_log is append-only (rows can never be changed, deleted or truncated, by anyone, not even postgres) ----------
create or replace function public.audit_log_append_only() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'audit_log is append-only'; end $$;

drop trigger if exists audit_log_no_change on public.audit_log;
create trigger audit_log_no_change before update or delete on public.audit_log for each row execute function public.audit_log_append_only();
drop trigger if exists audit_log_no_truncate on public.audit_log;
create trigger audit_log_no_truncate before truncate on public.audit_log for each statement execute function public.audit_log_append_only();
-- ENABLE ALWAYS: still fires when session_replication_role = replica (so a bulk-restore tool cannot bypass it either)
alter table public.audit_log enable always trigger audit_log_no_change;
alter table public.audit_log enable always trigger audit_log_no_truncate;
revoke update, delete, truncate on public.audit_log from anon, authenticated;

-- ---------- (b) codes are immutable (a code is never changed or reused for something else; same-value updates and first assignment of an empty code are allowed) ----------
create or replace function public.code_immutable() returns trigger
language plpgsql set search_path = public as $$
declare c text; o text; n text;
begin
  foreach c in array tg_argv loop
    o := to_jsonb(old) ->> c; n := to_jsonb(new) ->> c;
    if o is not null and o is distinct from n then raise exception 'code is immutable'; end if;
  end loop;
  return new;
end $$;

drop trigger if exists locations_code_immutable on public.locations;
create trigger locations_code_immutable before update on public.locations for each row execute function public.code_immutable('code');
drop trigger if exists forms_code_immutable on public.forms;
create trigger forms_code_immutable before update on public.forms for each row execute function public.code_immutable('code');
drop trigger if exists option_lists_code_immutable on public.option_lists;
create trigger option_lists_code_immutable before update on public.option_lists for each row execute function public.code_immutable('list_code', 'value_code');
drop trigger if exists items_code_immutable on public.items;
create trigger items_code_immutable before update on public.items for each row execute function public.code_immutable('code');
drop trigger if exists roles_code_immutable on public.roles;
create trigger roles_code_immutable before update on public.roles for each row execute function public.code_immutable('code');

-- ---------- (c) nothing is hard-deleted ----------
create or replace function public.no_hard_delete() returns trigger
language plpgsql set search_path = public as $$
begin raise exception 'nothing is deleted – retire instead'; end $$;

-- exceptions: only an OPEN flag may be dropped (submit_entry / decide_entry re-evaluate open flags); a decided/closed exception is never deleted
create or replace function public.no_hard_delete_exceptions() returns trigger
language plpgsql set search_path = public as $$
begin
  if old.status = 'open' then return old; end if;
  raise exception 'nothing is deleted – retire instead';
end $$;

do $$
declare t text;
begin
  foreach t in array array['option_lists','locations','forms','items','profiles','entries','sales','customers','suppliers'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_no_delete', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_no_delete', t);
  end loop;
end $$;
drop trigger if exists exceptions_no_delete on public.exceptions;
create trigger exceptions_no_delete before delete on public.exceptions for each row execute function public.no_hard_delete_exceptions();

-- the client can no longer delete from these (the web UI retires them with active=false). Personal convenience tables
-- (report_views, user_favourites, role_favourites) and the permission matrices (role_form_perms, user_roles, user_locations, rule_grants,
-- user_grants; all have audit triggers) keep DELETE because the permission screens switch a tick off by deleting its row.
revoke delete on public.option_lists, public.unit_conversions, public.shelf_life_rules, public.invoice_templates,
  public.print_profiles, public.report_brand_map from anon, authenticated;

-- ---------- unit_conversions: retire, never delete (readers such as _unit_hop already filter active) ----------
create or replace function public.set_unit_conversion(p_item uuid, p_from text, p_to text, p_factor numeric, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_factor is null then
    update public.unit_conversions set active = false, updated_at = now(), updated_by = auth.uid()
      where coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_item, '00000000-0000-0000-0000-000000000000'::uuid) and from_unit = p_from and to_unit = p_to;
    return;
  end if;
  if not (p_factor > 0 and p_factor < 1e12) then raise exception 'bad_factor'; end if;
  insert into public.unit_conversions (item_id, from_unit, to_unit, factor, note, updated_by) values (p_item, p_from, p_to, p_factor, left(p_note, 200), auth.uid())
    on conflict (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid), from_unit, to_unit)
    do update set factor = excluded.factor, note = excluded.note, active = true, updated_at = now(), updated_by = auth.uid();
end $$;

-- ---------- (d) server-side PIN lockout + failed-login log ----------
insert into public.settings (key, value, label_bn, label_mix, label_en) values
 ('lock_minutes', '10', 'ভুল PIN-এ লক কত মিনিট (এবং গণনার সময়সীমা)', 'ভুল PIN-এ Lock কত মিনিট (ও গণনার সময়)', 'Lock minutes after too many wrong PINs (also the counting window)'),
 ('lockout_auto_release', 'true', 'সময় শেষে লক নিজে খুলবে (false = শুধু মালিক খুলবে)', 'সময় শেষে Lock নিজে খুলবে (false = শুধু owner)', 'Lock releases by itself after the time (false = only the owner unlocks)')
on conflict (key) do nothing;

create table if not exists public.login_attempts (
  id bigserial primary key,
  staff_id text not null,
  at timestamptz not null default now(),
  ok boolean not null,
  ip_hint text
);
create index if not exists login_attempts_staff_at on public.login_attempts (staff_id, at desc);
alter table public.login_attempts enable row level security;
drop policy if exists login_attempts_owner_read on public.login_attempts;
create policy login_attempts_owner_read on public.login_attempts for select to authenticated using (public.is_owner());
revoke all on public.login_attempts from anon, authenticated;
grant select on public.login_attempts to authenticated;
revoke all on sequence public.login_attempts_id_seq from anon, authenticated;

-- global / per-bucket spam counters (one row per bucket per minute); nobody but the security-definer functions touches it
create table if not exists public.login_throttle (
  bucket text primary key,
  window_start timestamptz not null default now(),
  n int not null default 0
);
alter table public.login_throttle enable row level security;
revoke all on public.login_throttle from anon, authenticated;

alter table public.login_failures add column if not exists locked_until timestamptz;
alter table public.login_failures add column if not exists window_start timestamptz not null default now();

-- true if this call may be written to login_attempts (max p_limit per bucket per minute; the counter row is the throttle)
create or replace function public._login_throttle(p_bucket text, p_limit int) returns boolean
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into public.login_throttle (bucket, window_start, n) values (p_bucket, now(), 1)
  on conflict (bucket) do update set
    window_start = case when public.login_throttle.window_start < now() - interval '1 minute' then now() else public.login_throttle.window_start end,
    n = case when public.login_throttle.window_start < now() - interval '1 minute' then 1 else public.login_throttle.n + 1 end
  returning n into k;
  return k <= p_limit;
end $$;

create or replace function public._login_setting_num(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select case when jsonb_typeof(value) = 'number' then
                            case when (value #>> '{}')::numeric between 1 and 100000 then (value #>> '{}')::numeric end end
                   from public.settings where key = p_key), p_default);
$$;

create or replace function public._login_auto_release() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select value = 'true'::jsonb from public.settings where key = 'lockout_auto_release' and value is not null), true);
$$;

-- auto-release applies when the setting is on, and ALWAYS for an owner account (an owner can never be locked out for good by someone typing wrong PINs)
create or replace function public._login_auto_release_for(p_staff text) returns boolean
language sql stable security definer set search_path = public as $$
  select public._login_auto_release() or exists (
    select 1 from public.profiles p join public.user_roles ur on ur.user_id = p.id where p.staff_id = lower(btrim(coalesce(p_staff, ''))) and ur.role_code = 'owner');
$$;

create or replace function public.login_precheck(p_staff text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f public.login_failures; sec int := 0; lk boolean := false; s text := lower(btrim(coalesce(p_staff, '')));
begin
  select * into f from public.login_failures where staff_id = s;
  if found and f.locked then
    if f.locked_until is null or not public._login_auto_release_for(s) then lk := true; sec := null;      -- locked until the owner unlocks
    elsif f.locked_until > now() then lk := true; sec := ceil(extract(epoch from (f.locked_until - now())))::int;
    end if;
  end if;
  -- same shape for known and unknown ids; no per-id counters are returned (they would reveal which ids exist)
  return jsonb_build_object('locked', lk, 'seconds_left', sec);
end $$;

create or replace function public.login_failed(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
declare s text := left(lower(btrim(coalesce(p_staff, ''))), 64); mx int := public._login_setting_num('max_fails', 5)::int;
        lm int := public._login_setting_num('lock_minutes', 10)::int; known boolean; f public.login_failures; nf int;
begin
  if s = '' then return; end if;
  select exists (select 1 from public.profiles where staff_id = s) into known;
  -- spam guard: unknown ids share ONE global bucket; known ids get 50 log rows per minute each. Unknown/known look the same to the caller.
  if not public._login_throttle(case when known then 'sid:' || s else 'unknown' end, case when known then 20 else 60 end) then return; end if;
  insert into public.login_attempts (staff_id, ok, ip_hint) values (s, false, null);
  if not known then return; end if;
  select * into f from public.login_failures where staff_id = s for update;
  if not found then
    insert into public.login_failures (staff_id, fails, locked, locked_until, window_start, last_fail)
      values (s, 1, 1 >= mx, case when 1 >= mx and public._login_auto_release_for(s) then now() + make_interval(mins => lm) end, now(), now())
    on conflict (staff_id) do nothing;
    return;
  end if;
  if f.locked then
    if f.locked_until is not null and f.locked_until <= now() and public._login_auto_release_for(s) then
      update public.login_failures set fails = 1, locked = (1 >= mx), locked_until = case when 1 >= mx then now() + make_interval(mins => lm) end,
        window_start = now(), last_fail = now() where staff_id = s;
    else
      update public.login_failures set last_fail = now() where staff_id = s;   -- still locked: attempts do not extend the lock
    end if;
    return;
  end if;
  if f.window_start < now() - make_interval(mins => lm) then nf := 1; else nf := f.fails + 1; end if;
  update public.login_failures set
    fails = nf, last_fail = now(),
    window_start = case when nf = 1 then now() else f.window_start end,
    locked = nf >= mx,
    locked_until = case when nf >= mx and public._login_auto_release_for(s) then now() + make_interval(mins => lm) else null end
  where staff_id = s;
end $$;

create or replace function public.login_success() returns void
language plpgsql security definer set search_path = public as $$
declare s text := (select staff_id from public.profiles where id = auth.uid());
begin
  if s is null then return; end if;
  delete from public.login_failures where staff_id = s;
  if public._login_throttle('sid:' || s, 50) then insert into public.login_attempts (staff_id, ok) values (s, true); end if;
end $$;

create or replace function public.unlock_staff(p_staff text) returns void
language plpgsql security definer set search_path = public as $$
declare s text := lower(btrim(coalesce(p_staff, '')));
begin
  if not public.is_owner() then raise exception 'owner only'; end if;
  delete from public.login_failures where staff_id = s;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'unlock', 'login_failures', s, jsonb_build_object('staff_id', s));
end $$;

revoke execute on function public.login_precheck(text), public.login_failed(text), public.login_success(), public.unlock_staff(text),
  public._login_throttle(text, int), public._login_setting_num(text, numeric), public._login_auto_release(), public.audit_log_append_only(),
  public.code_immutable(), public.no_hard_delete(), public.no_hard_delete_exceptions() from public;
revoke execute on function public._login_throttle(text, int), public._login_setting_num(text, numeric), public._login_auto_release(),
  public.audit_log_append_only(), public.code_immutable(), public.no_hard_delete(), public.no_hard_delete_exceptions() from anon, authenticated;
grant execute on function public.login_precheck(text), public.login_failed(text) to anon, authenticated;
grant execute on function public.login_success(), public.unlock_staff(text) to authenticated;
revoke execute on function public.login_success(), public.unlock_staff(text) from anon;

-- ---------- OPTIONAL Supabase Auth hook (NOT enabled automatically) ----------
-- The lockout above guards the app's login screen only; the Auth endpoint itself can still be called directly. To make the lock real, the owner can enable
-- this function in Supabase Dashboard > Authentication > Hooks > "Password verification attempt" (Postgres function public.hook_password_verification_attempt).
-- It rejects a sign-in while the account is locked and records a failed attempt on a wrong password. Until enabled it has no effect.
create or replace function public.hook_password_verification_attempt(event jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s text; locked boolean;
begin
  select staff_id into s from public.profiles where id = nullif(event ->> 'user_id', '')::uuid;
  if s is not null then
    locked := (public.login_precheck(s) ->> 'locked')::boolean;
    if locked then return jsonb_build_object('decision', 'reject', 'message', 'Account locked, try later or ask the owner'); end if;
    if not coalesce((event ->> 'valid')::boolean, true) then perform public.login_failed(s); end if;
  end if;
  return jsonb_build_object('decision', 'continue');
end $$;
revoke execute on function public.hook_password_verification_attempt(jsonb) from public, anon, authenticated;
revoke execute on function public._login_auto_release_for(text) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant execute on function public.hook_password_verification_attempt(jsonb) to supabase_auth_admin;
    grant select on public.profiles, public.login_failures to supabase_auth_admin;
  end if;
end $$;
