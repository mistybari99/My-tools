-- ALL_NEW4 = phase11 + phase12 + phase13 (hardening, stock/purchase carry-over, day book & salary). Safe to re-run. TAKE A BACKUP FIRST, run at a quiet time.

-- ===== phase11 =====
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

-- ===== phase12 =====
-- ============================================================
-- BOS tool · Phase 12 (W0 carry-over, owner's list HANDOVER §8 items 1-5, 7-12, 14): items / stock / purchase finishing work.
-- Run AFTER phase8, phase9, phase10 (phase11 may come before or after; nothing here depends on it).
-- ADDITIVE and IDEMPOTENT: safe to paste whole and run again. Nothing existing is dropped. Functions that are re-created keep ALL their old behaviour
-- (the old text is copied and extended); where another phase may also have replaced a function, a wrapper is used instead of a copy.
--
-- What is here
--   1  items.details (text) + apply_item_patch learns it (wrapper around the existing function, so any later column added by another phase is kept)
--   2  items_with_cost(): item costs for people who hold only the grant view_cost (item_costs RLS is NOT changed)
--   8  photos for stock / purchase: storage prefixes STOCK/<loc>/... and PURCHASE/<loc>/... decided by grants (photo_ok re-created, all old prefixes unchanged)
--   9  emergency keys for stock_count_adjust / stock_transfer / stock_issue / stock_production (all OFF by default)
--  10  wastage maker-checker: rule wastage_approval_limit (empty = off); above it the write-off waits for ANOTHER person holding the grant wastage_approve
--  11  supplier refund (cash back from a supplier) and sale_return (restock, batch aware, reduces the customer's due first, or refunds)
--  12  rule block_expired_sale (default OFF): on = a sale from an expired batch is refused; off = the red exception 'sold_expired' as before
--  14  stock_ledger.ref_id is no longer readable by location users directly (column privilege); stock_ledger_rows() still returns it where allowed
-- No business number is invented: the new limit is empty, the new switches are off (block_expired_sale, every em_*), sale_return_due_first is on only
-- because refunding the cash of a customer who still owes us would be silly; the owner can switch it off.
-- ============================================================

-- ---------- (1) items.details ----------
alter table public.items add column if not exists details text;

do $$
begin
  if position('bos12-details' in pg_get_functiondef('public.apply_item_patch(uuid,jsonb)'::regprocedure)) = 0 then
    drop function if exists public._apply_item_patch_base(uuid, jsonb);
    alter function public.apply_item_patch(uuid, jsonb) rename to _apply_item_patch_base;
    execute $f$
      create function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
      language plpgsql security definer set search_path = public as $b$
      declare iid uuid;   -- bos12-details: everything else is done by the previous version, kept as _apply_item_patch_base
      begin
        iid := public._apply_item_patch_base(p_item, p_patch);
        if p_patch ? 'details' then
          update public.items set details = left(nullif(btrim(p_patch->>'details'), ''), 2000) where id = iid;
        end if;
        return iid;
      end $b$ $f$;
  end if;
end $$;
revoke all on function public.apply_item_patch(uuid, jsonb), public._apply_item_patch_base(uuid, jsonb) from public, anon, authenticated;

-- ---------- (2) costs for view_cost holders ----------
create or replace function public.items_with_cost() returns table (item_id uuid, cost_price numeric)
language sql stable security definer set search_path = public as $$
  select c.item_id, c.cost_price from public.item_costs c
  -- a location-scoped personal view_cost grant counts too (the list is company wide, so any location grant is enough; role grants and the owner as before)
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost')
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = 'view_cost' and (g.valid_until is null or g.valid_until > now())));
$$;
revoke all on function public.items_with_cost() from public, anon;
grant execute on function public.items_with_cost() to authenticated;

-- ---------- rules, grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('wastage_approval_limit', 'stock', 'number', null, null, null, 0, 1000000000, 'এর বেশি পরিমাণ নষ্ট দেখাতে হলে আরেকজনের অনুমোদন লাগবে (বেস এককে)', 'এর বেশি quantity নষ্ট দেখাতে হলে আরেকজনের approval লাগবে (base unit এ)', 'A wastage above this quantity waits for a second person to approve (in the item base unit)', 'Empty = Data needed = off (every write-off posts at once). The owner is never held back', 103),
 ('wastage_limit_daily_sum', 'stock', 'switch', 'true', null, null, null, null, 'একই ব্যক্তির একই দিনে একই পণ্যের নষ্ট মালের যোগফলও সীমার সাথে মেলানো হবে', 'একই person এর একই দিনে একই item এর wastage এর যোগফলও limit এর সাথে মেলানো হবে', 'The same person''s wastage of the same item on the same day is added up against the limit (stops splitting a big write-off)', 'Only matters when wastage_approval_limit is set', 105),
 ('block_expired_sale', 'stock', 'switch', 'false', null, null, null, null, 'মেয়াদোত্তীর্ণ মাল বিক্রি আটকানো', 'মেয়াদোত্তীর্ণ মাল sale আটকানো', 'Block selling expired stock', 'Off = the sale goes through and the owner gets a red line (as before). On = the sale is refused. A sale that syncs late from an offline phone is never refused', 104),
 ('sale_return_due_first', 'pos', 'switch', 'true', null, null, null, null, 'বিক্রি ফেরতে আগে গ্রাহকের বাকি কমবে, বাকি টাকা ফেরত', 'Sale return এ আগে customer এর due কমবে, বাকি টাকা ফেরত', 'A sale return first reduces what the customer owes; only the rest is refunded', 'Off = the whole value is refunded in cash / mobile / card', 90),
 ('em_stock_count_adjust', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: গণনা অনুযায়ী স্টক ঠিক', 'জরুরি request চলবে: count অনুযায়ী stock ঠিক', 'Emergency allowed for: adjusting stock to a count', 'Off by default', 127),
 ('em_stock_transfer', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: মাল পাঠানো / গ্রহণ', 'জরুরি request চলবে: মাল transfer / receive', 'Emergency allowed for: sending / receiving stock', 'Off by default', 128),
 ('em_stock_issue', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: উৎপাদনে কাঁচামাল দেওয়া', 'জরুরি request চলবে: production এ কাঁচামাল issue', 'Emergency allowed for: issuing material to production', 'Off by default', 129),
 ('em_stock_production', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: উৎপাদিত মাল স্টকে তোলা', 'জরুরি request চলবে: production এর মাল stock এ তোলা', 'Emergency allowed for: posting production into stock', 'Off by default', 130),
 ('em_sale_return', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: বিক্রি ফেরত নেওয়া', 'জরুরি request চলবে: sale return নেওয়া', 'Emergency allowed for: taking a sale return', 'Off by default', 131)
on conflict (key) do nothing;

with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('wastage_approve', 'stock', 47, 'বড় নষ্ট মাল বাদ দেওয়া অনুমোদন', 'বড় wastage write-off approve', 'Approve a large wastage write-off', 'once', null),
   ('sale_return', 'pos', 11, 'বিক্রি ফেরত নেওয়া', 'Sale return নেওয়া', 'Take a sale return', 'once', 'em_sale_return')
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('wastage_approve', 'management'),
    ('sale_return', 'management'), ('sale_return', 'showroom_manager')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- (9) the four stock grants now name their emergency switch (an owner's own choice is never overwritten: only a still-empty one is filled)
update public.grant_defs set emergency_rule = 'em_' || grant_code where grant_code in ('stock_count_adjust', 'stock_transfer', 'stock_issue', 'stock_production') and emergency_rule is null;

-- ---------- (8) photos: STOCK / PURCHASE prefixes ----------
-- path = <PREFIX or form code>/<location id>/<file>.jpg ; the old form-code prefixes behave exactly as before.
create or replace function public.photo_ok(p_name text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active()
    and split_part(p_name, '/', 2) ~ '^[0-9]+$'
    and public.can_loc(split_part(p_name, '/', 2)::int)
    and case split_part(p_name, '/', 1)
      when 'STOCK' then
        case when p_action = 'view' then true          -- anyone who works at that location may see a stock photo (wastage, count)
             else (public.has_grant('wastage_write_off', split_part(p_name, '/', 2)::int) or public.has_grant('stock_count_adjust', split_part(p_name, '/', 2)::int)
                   or public.has_grant('stock_transfer', split_part(p_name, '/', 2)::int) or public.has_grant('stock_issue', split_part(p_name, '/', 2)::int)
                   or public.has_grant('stock_production', split_part(p_name, '/', 2)::int) or public.has_grant('stock_opening', split_part(p_name, '/', 2)::int)) end
      when 'PURCHASE' then
        case when p_action = 'view' then public._pur_ok(split_part(p_name, '/', 2)::int)      -- a bill photo shows costs: only the purchase people
             else (public.has_grant('purchase_entry', split_part(p_name, '/', 2)::int) or public.has_grant('purchase_return', split_part(p_name, '/', 2)::int)
                   or public.has_grant('supplier_pay', split_part(p_name, '/', 2)::int)) end
      else public.can_do(split_part(p_name, '/', 1), p_action) end;
$$;
revoke all on function public.photo_ok(text, text) from public, anon;
grant execute on function public.photo_ok(text, text) to authenticated;

-- ---------- (14) stock_ledger.ref_id: not readable directly (a purchase bill id would open a bill) ----------
revoke select on public.stock_ledger from authenticated;
grant select (id, item_id, location_id, qty_delta, reason, ref_type, batch_id, reverses_id, made_at, note, created_by, created_at) on public.stock_ledger to authenticated;

-- ---------- (12) stock_post: optional block of expired stock, and a sale return puts goods back into its batch ----------
-- identical to phase10 except the two marked places
create or replace function public.stock_post(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_ref_type text default null, p_ref_id text default null,
  p_unit_cost numeric default null, p_batch bigint default null, p_made_at timestamptz default null, p_note text default null,
  p_reverses bigint default null, p_neg text default 'full', p_sale uuid default null, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
        blk boolean := false;
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale'); end if;           -- (12) read once
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        if p_sale is null or coalesce(current_setting('bos.neg_ok', true), '') <> p_sale::text then
          if not (public.has_grant('sell_below_zero', p_loc)
                  or case when p_sale is not null then public.use_emergency('sell_below_zero', p_loc, ref, null, null) else public._use_em('sell_below_zero', p_loc, ref, null) end) then
            raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
          end if;
          if p_sale is not null then perform set_config('bos.neg_ok', p_sale::text, true); end if;
        end if;
      end if;
      en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): more went out than the stock on hand — the stock is now negative';
      if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and qty_delta > 0)
         and not exists (select 1 from public.exceptions where flag_code = 'stock_negative' and location_id = p_loc and entry_date = d and text->>'en' = en) then
        perform public._stock_exc(p_loc, 'stock_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): স্টকের চেয়ে বেশি বের হয়েছে — হিসাবে স্টক ঋণাত্মক', en, p_sale, d, form);
      end if;
    end if;
  end if;
  cost := coalesce(p_unit_cost, case when q < 0 then bal.avg_cost end);
  if q < 0 and p_batch is null and p_reason in ('sale_out', 'issue_out', 'wastage', 'transfer_out', 'count_adjust', 'purchase_return') then
    rem := -q;
    for b in select id, qty_remaining, expires_at from public.stock_batches where item_id = p_item and location_id = p_loc and qty_remaining > 0
             order by (expires_at is not null and expires_at <= at_), expires_at nulls last, made_at, id for update loop
      if blk and b.expires_at is not null and b.expires_at <= at_ then          -- (12) the owner switched "block expired sale" on
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে',
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold', p_sale, d, form);
      end if;
      exit when rem <= 0;
    end loop;
    if rem > 0 then
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -rem, cost, p_reason, p_ref_type, p_ref_id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      first_id := coalesce(first_id, lid);
    end if;
    return first_id;
  end if;
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
    values (p_item, p_loc, q, cost, p_reason, p_ref_type, p_ref_id, p_batch, p_reverses, p_client, at_, p_note, auth.uid()) returning id into lid;
  if p_batch is not null then
    if q < 0 then
      update public.stock_batches set qty_remaining = case when qty_remaining + q < 0.0005 then 0 else qty_remaining + q end where id = p_batch and qty_remaining + q >= 0;
      if not found then raise exception 'batch_short'; end if;
    elsif p_reason in ('sale_void_in', 'reversal', 'sale_return') then          -- (11) 'sale_return' added
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $$;

-- ---------- (10) wastage maker-checker ----------
create table if not exists public.wastage_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty numeric not null check (qty > 0 and qty between 0 and 1000000000000),          -- base unit
  reason_code text not null,
  note text, photo text,
  batch_id bigint,                                                   -- no foreign key: keeps the ledger tables free of dependants
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text,
  wastage_id uuid
);
create index if not exists wastage_requests_open on public.wastage_requests (location_id, status);
drop trigger if exists audit_wastage_requests on public.wastage_requests;
create trigger audit_wastage_requests after insert or update on public.wastage_requests for each row execute function public.log_change('id');
alter table public.wastage_requests enable row level security;
drop policy if exists wastage_requests_read on public.wastage_requests;
create policy wastage_requests_read on public.wastage_requests for select to authenticated
  using (public.can_loc(location_id) and (requested_by = auth.uid() or public.has_grant('wastage_approve', location_id)));
revoke all on public.wastage_requests from public, anon, authenticated;
grant select on public.wastage_requests to authenticated;

-- the posting itself (shared by a direct write-off and an approved request). Internal.
create or replace function public._wastage_post(p_item uuid, p_loc int, p_bq numeric, p_reason text, p_note text, p_photo text, p_batch bigint,
  p_client uuid, p_by uuid, p_staff text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; wid uuid := gen_random_uuid(); lid bigint;
begin
  select * into it from public.items where id = p_item;
  begin
    lid := public.stock_post(p_item, p_loc, -p_bq, 'wastage', 'wastage', wid::text, null, p_batch, now(), left(p_note, 200), null, 'full', null, p_client);
    insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, photo, batch_id, ledger_id, created_by, created_staff)
      values (wid, p_item, p_loc, p_bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, lid, p_by, p_staff);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins, this one is the duplicate
    select id into lid from public.stock_ledger where p_client is not null and client_id = p_client and reason = 'wastage' order by id limit 1;
    if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    raise;
  end;
  if p_reason = 'unknown' then
    perform public._stock_exc(p_loc, 'wastage_unknown', 'yellow', it.name_bn || ': নষ্ট মাল বাদ দেওয়া হয়েছে কিন্তু কারণ অজানা', coalesce(it.name_en, it.name_bn) || ': stock was written off with an unknown reason');
  end if;
  return jsonb_build_object('id', wid, 'ledger_id', lid, 'qty', p_bq);
end $$;

-- write off wasted stock (same behaviour as phase10) + maker-checker above the owner's limit
create or replace function public.stock_wastage(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_note text default null, p_photo text default null,
  p_unit text default null, p_client uuid default null, p_batch bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; lim numeric; sid text; alim numeric; rid uuid; rq public.wastage_requests; dsum numeric := 0; dd date := (now() at time zone 'Asia/Dhaka')::date;
begin
  it := public._stock_guard(p_item, p_loc, 'wastage_write_off', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = 'wastage' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    select * into rq from public.wastage_requests where client_id = p_client;
    if found then
      if rq.requested_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'pending', rq.status = 'pending', 'request_id', rq.id);
    end if;
  end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'wastage_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  lim := public.rule_num('wastage_photo_above');
  if lim is not null and bq > lim and nullif(btrim(p_photo), '') is null then raise exception 'photo_required'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if not public._may('wastage_write_off', p_loc, 'wastage:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if p_batch is not null and not exists (select 1 from public.stock_batches where id = p_batch and item_id = p_item and location_id = p_loc) then raise exception 'batch_not_found'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  alim := public.rule_num('wastage_approval_limit');
  if alim is not null and public.rule_on('wastage_limit_daily_sum') then        -- today's wastage of this person for this item here, posted + still pending
    select coalesce((select sum(w.qty) from public.stock_wastage w where w.created_by = auth.uid() and w.item_id = p_item and w.location_id = p_loc and (w.made_at at time zone 'Asia/Dhaka')::date = dd), 0)
         + coalesce((select sum(r.qty) from public.wastage_requests r where r.requested_by = auth.uid() and r.item_id = p_item and r.location_id = p_loc and r.status = 'pending' and (r.requested_at at time zone 'Asia/Dhaka')::date = dd), 0) into dsum;
  end if;
  if alim is not null and (bq > alim or dsum + bq > alim) and not public.is_owner() then
    begin
      insert into public.wastage_requests (client_id, item_id, location_id, qty, reason_code, note, photo, batch_id, requested_by, requested_staff)
        values (p_client, p_item, p_loc, bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, auth.uid(), sid) returning id into rid;
    exception when unique_violation then
      select * into rq from public.wastage_requests where p_client is not null and client_id = p_client;
      if found and rq.requested_by = auth.uid() then return jsonb_build_object('dup', true, 'pending', rq.status = 'pending', 'request_id', rq.id); end if;
      raise;
    end;
    perform public._stock_exc(p_loc, 'wastage_pending', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ — অনুমোদনের অপেক্ষায় (' || bq::text || ')',
      coalesce(it.name_en, it.name_bn) || ': a large wastage write-off is waiting for approval (' || bq::text || ')');
    return jsonb_build_object('pending', true, 'request_id', rid, 'qty', bq);
  end if;
  return public._wastage_post(p_item, p_loc, bq, p_reason, p_note, p_photo, p_batch, p_client, auth.uid(), sid);
end $$;

-- a DIFFERENT person with the grant wastage_approve (or the owner) decides. Approving posts the write-off now.
create or replace function public.wastage_decide(p_id uuid, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.wastage_requests; sid text; res jsonb; it public.items;
begin
  select * into r from public.wastage_requests where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) or not public.has_grant('wastage_approve', r.location_id) then raise exception 'not allowed'; end if;
  perform 1 from public.wastage_requests where id = p_id for update;
  select * into r from public.wastage_requests where id = p_id;
  if r.status <> 'pending' then
    if r.status = (case when p_approve then 'approved' else 'rejected' end) then return jsonb_build_object('dup', true, 'status', r.status); end if;
    raise exception 'already_decided';
  end if;
  if r.requested_by = auth.uid() then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then
    res := public._wastage_post(r.item_id, r.location_id, r.qty, r.reason_code, coalesce(r.note, '') || case when r.note is null then '' else ' · ' end || 'approved by ' || coalesce(sid, '?'),
                                r.photo, r.batch_id, r.client_id, r.requested_by, r.requested_staff);
    update public.wastage_requests set status = 'approved', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(nullif(btrim(p_note), ''), 300),
      wastage_id = nullif(res->>'id', '')::uuid where id = p_id;
    return jsonb_build_object('status', 'approved') || res;
  end if;
  update public.wastage_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
  select * into it from public.items where id = r.item_id;
  perform public._stock_exc(r.location_id, 'wastage_rejected', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ নামঞ্জুর — ' || left(btrim(p_note), 100),
    coalesce(it.name_en, it.name_bn) || ': a large wastage write-off was rejected — ' || left(btrim(p_note), 100));
  return jsonb_build_object('status', 'rejected');
end $$;

-- the requester takes a pending request back
create or replace function public.wastage_cancel(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.wastage_requests;
begin
  select * into r from public.wastage_requests where id = p_id for update;
  if not found or r.requested_by <> auth.uid() then raise exception 'not allowed'; end if;
  if r.status = 'cancelled' then return jsonb_build_object('dup', true, 'status', 'cancelled'); end if;
  if r.status <> 'pending' then raise exception 'already_decided'; end if;
  update public.wastage_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now() where id = p_id;
  return jsonb_build_object('status', 'cancelled');
end $$;

-- the waiting list: approvers see every pending request of their locations, anyone sees their own
create or replace function public.wastage_pending(p_loc int default null, p_status text default 'pending')
returns table (id uuid, item_id uuid, code text, name_bn text, name_en text, location_id int, qty numeric, base_unit text, reason_code text, note text, photo text,
               status text, requested_staff text, requested_at timestamptz, mine boolean, can_decide boolean, decision_note text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select r.id, r.item_id, i.code, i.name_bn, i.name_en, r.location_id, r.qty, public._item_base(i.id), r.reason_code, r.note, r.photo, r.status, r.requested_staff, r.requested_at,
           r.requested_by = auth.uid(), (r.status = 'pending' and r.requested_by <> auth.uid() and public.has_grant('wastage_approve', r.location_id)), r.decision_note
    from public.wastage_requests r join public.items i on i.id = r.item_id
    where public.can_loc(r.location_id) and (p_loc is null or r.location_id = p_loc) and (p_status is null or r.status = p_status)
      and (r.requested_by = auth.uid() or public.has_grant('wastage_approve', r.location_id))
    order by r.requested_at desc limit 200;
end $$;

-- ---------- (11a) supplier refund: cash back from a supplier, reduces the supplier's credit ----------
create table if not exists public.supplier_refunds (
  id bigserial primary key,
  supplier_id uuid not null references public.suppliers(id),
  location_id int not null references public.locations(id),
  mode text not null check (mode in ('cash', 'mobile', 'card', 'bank')),
  wallet text, ref text,
  amount numeric not null check (amount > 0 and amount between 0 and 1000000000000),
  refunded_at timestamptz not null default now(),
  reason_code text, note text,
  voided boolean not null default false, void_note text, void_by uuid,
  created_by uuid, created_staff text, client_id uuid
);
create index if not exists supplier_refunds_sup on public.supplier_refunds (supplier_id) where not voided;
create unique index if not exists supplier_refunds_client on public.supplier_refunds (client_id) where client_id is not null;
drop trigger if exists audit_supplier_refunds on public.supplier_refunds;
create trigger audit_supplier_refunds after insert or update on public.supplier_refunds for each row execute function public.log_change('id');
alter table public.supplier_refunds enable row level security;
drop policy if exists supplier_refunds_read on public.supplier_refunds;
create policy supplier_refunds_read on public.supplier_refunds for select to authenticated using (public._pur_ok(location_id));
revoke all on public.supplier_refunds from public, anon, authenticated;
revoke all on sequence public.supplier_refunds_id_seq from public, anon, authenticated;
grant select on public.supplier_refunds to authenticated;

-- balance owed = opening + bills - returns - payments + refunds received (a refund uses up credit, so we owe more / are owed less)
create or replace function public._sup_balance(p_supplier uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select opening_balance from public.suppliers where id = p_supplier), 0)
       + coalesce((select sum(case kind when 'bill' then total else -total end) from public.purchase_bills where supplier_id = p_supplier and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.supplier_payments where supplier_id = p_supplier and not voided), 0)
       + coalesce((select sum(amount) from public.supplier_refunds where supplier_id = p_supplier and not voided), 0);
$$;

-- open-bill allocation: a refund is NEGATIVE credit at the location where it was taken (copy of phase10 + one union branch)
create or replace function public._sup_open(p_supplier uuid default null)
returns table (supplier_id uuid, bill_id uuid, bill_no text, bill_date date, location_id int, rem numeric, open_amt numeric)
language sql stable security definer set search_path = public as $$
  with bills as (
    select b.supplier_id, b.id bill_id, b.bill_no, b.bill_date, b.location_id, b.total - b.paid rem, coalesce(b.posted_at, b.created_at) ord_at, coalesce(b.location_id, -1) lk
    from public.purchase_bills b where b.status = 'posted' and b.kind = 'bill' and b.total - b.paid > 0 and (p_supplier is null or b.supplier_id = p_supplier)
    union all
    select s.id, null::uuid, 'opening', null::date, null::int, s.opening_balance, '-infinity'::timestamptz, -1
    from public.suppliers s where s.opening_balance > 0 and (p_supplier is null or s.id = p_supplier)),
  lc as (
    select z.supplier_id, z.lk, sum(z.x) credit from (
      select p.supplier_id, p.location_id lk, p.amount x from public.supplier_payments p where not p.voided and p.bill_id is null and (p_supplier is null or p.supplier_id = p_supplier)
      union all select b.supplier_id, b.location_id, b.total from public.purchase_bills b where b.status = 'posted' and b.kind = 'return' and (p_supplier is null or b.supplier_id = p_supplier)
      union all select f.supplier_id, f.location_id, -f.amount from public.supplier_refunds f where not f.voided and (p_supplier is null or f.supplier_id = p_supplier)) z
    group by 1, 2),
  oc as (select s.id supplier_id, -s.opening_balance credit from public.suppliers s where s.opening_balance < 0 and (p_supplier is null or s.id = p_supplier)),
  c1 as (select bills.*, sum(bills.rem) over (partition by bills.supplier_id, bills.lk order by bills.bill_date nulls first, bills.ord_at, bills.bill_id) c from bills),
  a1 as (
    select c1.supplier_id, c1.bill_id, c1.bill_no, c1.bill_date, c1.location_id, c1.rem, c1.ord_at,
           c1.rem - least(c1.rem, greatest(0, coalesce(lc.credit, 0) - (c1.c - c1.rem))) rem2
    from c1 left join lc on lc.supplier_id = c1.supplier_id and lc.lk = c1.lk),
  pool as (
    select z.supplier_id, sum(z.credit) - coalesce((select sum(a1.rem - a1.rem2) from a1 where a1.supplier_id = z.supplier_id), 0) spill
    from (select lc.supplier_id, lc.credit from lc union all select oc.supplier_id, oc.credit from oc) z group by 1),
  c2 as (select a1.*, sum(a1.rem2) over (partition by a1.supplier_id order by a1.bill_date nulls first, a1.ord_at, a1.bill_id) cc from a1)
  select c2.supplier_id, c2.bill_id, c2.bill_no, c2.bill_date, c2.location_id, c2.rem,
         c2.rem2 - least(c2.rem2, greatest(0, coalesce(pool.spill, 0) - (c2.cc - c2.rem2)))
  from c2 left join pool on pool.supplier_id = c2.supplier_id;
$$;

-- supplier ledger: a refund is a debit (it brings the balance back up)
create or replace function public.supplier_ledger(p_supplier uuid, p_loc int default null)
returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint, bill_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    with e as (
      select '-infinity'::timestamptz at, 'opening'::text kind, null::text ref, null::int location_id, greatest(s.opening_balance, 0) debit, greatest(-s.opening_balance, 0) credit, null::text note, null::bigint pid, null::uuid bill_id, 0 srt
        from public.suppliers s where s.id = p_supplier and p_loc is null and coalesce(s.opening_balance, 0) <> 0
      union all
      select (b.bill_date::timestamp at time zone 'Asia/Dhaka'), case b.kind when 'bill' then 'bill' else 'return' end, coalesce(b.bill_no, '-'), b.location_id,
             case when b.kind = 'bill' then b.total else 0 end, case when b.kind = 'return' then b.total else 0 end, b.note, null::bigint, b.id, 1
        from public.purchase_bills b where b.supplier_id = p_supplier and b.status = 'posted' and (p_loc is null or b.location_id = p_loc)
      union all
      select p.paid_at, case when p.bill_id is null then 'payment' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id, p.bill_id, 2
        from public.supplier_payments p where p.supplier_id = p_supplier and not p.voided and (p_loc is null or p.location_id = p_loc)
      union all
      select f.refunded_at, 'refund', coalesce(f.wallet, f.mode), f.location_id, f.amount, 0, f.note, f.id, null::uuid, 3
        from public.supplier_refunds f where f.supplier_id = p_supplier and not f.voided and (p_loc is null or f.location_id = p_loc))
    select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, e.srt, e.pid, e.bill_id), e.note, e.pid, e.bill_id
    from e order by e.at, e.srt, e.pid, e.bill_id;
end $$;

-- record cash (or mobile / card / bank) refunded BY a supplier. Only while the supplier owes US (balance < 0), never more than that credit.
create or replace function public.supplier_refund(p_supplier uuid, p_loc int, p_amount numeric, p_mode text, p_wallet text default null, p_ref text default null,
  p_reason text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare amt numeric; bal numeric; sid text; dupby uuid;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_mode is null or p_mode not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
  if p_amount is null or not (p_amount between 0.01 and 999999999999) or round(p_amount, 2) <= 0 then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if p_reason is not null and not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  if p_client is not null then
    select created_by into dupby from public.supplier_refunds where client_id = p_client;
    if found then
      if not (public.has_grant('supplier_pay', p_loc) or public._pur_ok(p_loc) or dupby = auth.uid()) then raise exception 'not allowed'; end if;
      return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
    end if;
  end if;
  if not (public.has_grant('supplier_pay', p_loc) or public._use_em('supplier_pay', p_loc, 'supplier_refund:' || p_supplier::text, amt)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p_supplier for update;
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_refunds where client_id = p_client) then return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier)); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if bal >= 0 or amt > -bal then raise exception 'refund_exceeds_credit'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.supplier_refunds (supplier_id, location_id, mode, wallet, ref, amount, reason_code, note, created_by, created_staff, client_id)
    values (p_supplier, p_loc, p_mode, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), amt, p_reason, left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  return jsonb_build_object('refunded', amt, 'balance', bal + amt);
end $$;

create or replace function public.void_supplier_refund(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.supplier_refunds;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.supplier_refunds where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', r.location_id) or public._use_em('purchase_void', r.location_id, 'void_refund:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = r.supplier_id for update;
  select * into r from public.supplier_refunds where id = p_id for update;
  if r.voided then raise exception 'already void'; end if;
  perform public.lock_check((r.refunded_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_refunds set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(r.location_id, 'supplier_refund_void', 'yellow', 'সাপ্লায়ার রিফান্ড বাতিল: ' || left(btrim(p_note), 100), 'A supplier refund was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', r.amount);
end $$;

-- ---------- (11b) sale return ----------
create table if not exists public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  sale_id uuid not null references public.sales(id),
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  lines jsonb not null,                                                -- [{item_id, name, unit, qty, price, amount}] qty in the unit of the sale line
  amount numeric not null check (amount > 0 and amount <= 1000000000000),   -- value of the goods taken back (the sale's discount share already taken off)
  credit_amount numeric not null default 0 check (credit_amount >= 0),     -- used to reduce what the customer owes
  refund_amount numeric not null default 0 check (refund_amount >= 0),     -- money handed back
  refund_mode text check (refund_mode is null or refund_mode in ('cash', 'mobile', 'card')),
  wallet text, ref text,
  reason_code text not null, note text,
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check (credit_amount + refund_amount = amount)
);
create index if not exists sale_returns_sale on public.sale_returns (sale_id);
create index if not exists sale_returns_cust on public.sale_returns (customer_id) where status = 'done';
drop trigger if exists audit_sale_returns on public.sale_returns;
create trigger audit_sale_returns after insert or update on public.sale_returns for each row execute function public.log_change('id');
alter table public.sale_returns enable row level security;
drop policy if exists sale_returns_read on public.sale_returns;
create policy sale_returns_read on public.sale_returns for select to authenticated
  using (public.can_loc(location_id) and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', location_id)));
revoke all on public.sale_returns from public, anon, authenticated;
grant select on public.sale_returns to authenticated;

-- a sale that has a live return cannot be voided (its stock would go back twice): void the return first
create or replace function public._sale_void_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.sale_returns where sale_id = new.id and status = 'done') then raise exception 'sale_has_returns'; end if;
  return new;
end $$;
drop trigger if exists sales_void_guard on public.sales;
create trigger sales_void_guard before update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_void_guard();

-- customer balance: sold - paid - credited by returns. The gate stays as before (POS view / enter).
create or replace function public._cust_bal(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$$;
create or replace function public.customer_balance(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then public._cust_bal(p_customer) end;
$$;
create or replace function public.customer_dues() returns table (id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
language sql stable security definer set search_path = public as $$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$$;
create or replace function public.customer_ledger(p_customer uuid) returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint)
language sql stable security definer set search_path = public as $$
  with e as (
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done'
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided
    union all
    select r.created_at, 'sale_return', '#' || s.receipt, r.location_id, 0, r.credit_amount, r.reason_code, null::bigint
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and r.credit_amount > 0)
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$$;

-- take goods back from a sale. p_lines: [{"item_id":uuid,"qty":1.5}] (qty in the unit the sale line used).
-- Stock goes back (tracked items) into the batch it came out of at the cost it left with; the value first reduces the customer's due
-- (rule sale_return_due_first), the rest is refunded in p_refund_mode.
create or replace function public.sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text default null,
  p_refund_mode text default null, p_wallet text default null, p_ref text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.sales; r public.sale_returns; it public.items; ln record; rid uuid := gen_random_uuid(); pamt numeric; sq numeric; samt numeric; su text; pq numeric; price numeric; lamt numeric;
        gross numeric := 0; amt numeric; credit numeric := 0; refund numeric; bal numeric; fac numeric; out_lines jsonb := '[]'::jsonb; sid text;
        bq numeric; prior numeric; skip numeric; rem numeric; take numeric; o record; avail numeric; lid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into r from public.sale_returns where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() and not public.has_grant('sale_return', r.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount);
    end if;
  end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if not (public.has_grant('sale_return', s.location_id) or public._use_em('sale_return', s.location_id, 'sale_return:' || p_sale::text, null)) then raise exception 'not allowed'; end if;
  -- every line is checked before anything is cast: a malformed uuid / quantity is bad_item / bad_qty, never a raw cast error
  for ln in select e from jsonb_array_elements(p_lines) e loop
    if jsonb_typeof(ln.e) <> 'object' or coalesce(ln.e->>'item_id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then raise exception 'bad_item'; end if;
    if coalesce(ln.e->>'qty', '') !~ '^[0-9]{1,9}(\.[0-9]{1,6})?$' then raise exception 'bad_qty'; end if;
  end loop;
  perform 1 from public.sales where id = p_sale for update;                  -- one return at a time per sale
  select * into s from public.sales where id = p_sale;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  -- same item twice in p_lines is added up
  for ln in select e->>'item_id' iid, sum((e->>'qty')::numeric) q from jsonb_array_elements(p_lines) e group by 1 loop
    if ln.iid is null or ln.q is null or not (ln.q between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0), coalesce(sum((e->>'amount')::numeric), 0), max(e->>'unit')
      into sq, samt, su from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = ln.iid;
    if sq <= 0 then raise exception 'line_not_in_sale'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0) into pq from public.sale_returns x, jsonb_array_elements(x.lines) e where x.sale_id = s.id and x.status = 'done' and e->>'item_id' = ln.iid;
    if ln.q > sq - pq + 0.00005 then raise exception 'return_exceeds_sale'; end if;
    select coalesce(sum((e->>'amount')::numeric), 0) into pamt from public.sale_returns x, jsonb_array_elements(x.lines) e where x.sale_id = s.id and x.status = 'done' and e->>'item_id' = ln.iid;
    price := samt / sq;
    -- the last unit takes what is left of the line's money, so partial returns add up to the line exactly
    lamt := case when ln.q >= sq - pq - 0.00005 then greatest(samt - pamt, 0) else round(ln.q * price, 2) end; gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);
  end loop;
  if not (gross between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  fac := case when s.subtotal > 0 then s.total / s.subtotal else 1 end;               -- the sale's discount is shared in proportion
  amt := round(gross * fac, 2);
  if not (amt between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  if s.customer_id is not null then perform pg_advisory_xact_lock(hashtextextended('bos12c:' || s.customer_id::text, 0)); end if;
  if s.customer_id is not null and public.rule_on('sale_return_due_first') then
    bal := coalesce(public._cust_bal(s.customer_id), 0);
    credit := least(amt, greatest(bal, 0));
  end if;
  refund := amt - credit;
  if refund > 0 and (p_refund_mode is null or p_refund_mode not in ('cash', 'mobile', 'card')) then raise exception 'refund_mode_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.sale_returns (id, client_id, sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, refund_mode, wallet, ref, reason_code, note, created_by, created_staff)
      values (rid, p_client, s.id, s.location_id, s.customer_id, out_lines, amt, credit, refund, case when refund > 0 then p_refund_mode end, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), p_reason, left(nullif(btrim(p_note), ''), 300), auth.uid(), sid);
  exception when unique_violation then
    select * into r from public.sale_returns where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount); end if;
    raise;
  end;
  -- stock back (tracked items), batch aware
  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid;
    if it.tracked is not true then continue; end if;
    bq := public._base_qty(it.id, ln.q, ln.u);
    if bq is null then
      perform public._stock_exc(s.location_id, 'stock_unit_unknown', 'yellow', 'রসিদ ' || s.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, ফেরত মাল স্টকে ওঠেনি',
        'Receipt ' || s.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, the returned goods were NOT put back', s.id, s.sale_date, 'POS');
      continue;
    end if;
    rem := round(bq, 4);
    -- what earlier (live) returns of this sale already put back for this item
    select coalesce(sum(l.qty_delta), 0) into prior from public.stock_ledger l
      where l.item_id = it.id and l.ref_type = 'sale_return' and l.ref_id in (select x.id::text from public.sale_returns x where x.sale_id = s.id and x.id <> rid);
    skip := prior;
    for o in select * from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
             and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id) order by x.id loop
      exit when rem <= 0;
      avail := -o.qty_delta;
      if skip >= avail then skip := skip - avail; continue; end if;
      avail := avail - skip; skip := 0;
      take := least(avail, rem);
      perform public.stock_post(it.id, s.location_id, take, 'sale_return', 'sale_return', rid::text, o.unit_cost, o.batch_id, now(), left('return of receipt ' || s.receipt, 200), null, 'none');
      rem := rem - take;
    end loop;
    if rem >= 0.0005 then            -- no sale_out ledger row covers this (stock tracking was switched on after the sale): nothing is invented, the owner is told
      perform public._stock_exc(s.location_id, 'return_no_stock_trace', 'yellow', 'রসিদ ' || s.receipt || ': ' || it.name_bn || ' — বিক্রির স্টক-হিসাব নেই, ফেরত মাল স্টকে ওঠেনি (টাকা ফেরত/বাকি কমা হয়েছে)',
        'Receipt ' || s.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the sale has no stock ledger trace, the returned goods were NOT put back (money / due credit was still given)', s.id, s.sale_date, 'POS');
    end if;
  end loop;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $$;

create or replace function public.void_sale_return(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sale_returns; o public.stock_ledger;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.sale_returns where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('sale_return', r.location_id) or public._use_em('sale_return', r.location_id, 'void_return:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  if r.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  for o in select * from public.stock_ledger x where x.ref_type = 'sale_return' and x.ref_id = p_id::text and x.reason = 'sale_return'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id) order by x.id loop
    perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', 'sale_return', p_id::text, o.unit_cost, o.batch_id, now(), left('void: ' || btrim(p_note), 200), o.id, 'none');
  end loop;
  update public.sale_returns set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_id;
  perform public._stock_exc(r.location_id, 'sale_return_void', 'yellow', 'বিক্রি ফেরত বাতিল: ' || left(btrim(p_note), 100), 'A sale return was voided: ' || left(btrim(p_note), 100), r.sale_id, null, 'POS', r.amount);
  return jsonb_build_object('id', p_id, 'status', 'void');
end $$;

-- returns of one sale (for the sale's ⋮ menu) and what can still be returned per item
create or replace function public.sale_returns_for(p_sale uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales;
begin
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'not found'; end if;
  if not (public.is_active() and public.can_loc(s.location_id) and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', s.location_id))) then raise exception 'not allowed'; end if;
  return jsonb_build_object('sale_id', s.id, 'receipt', s.receipt, 'status', s.status, 'location_id', s.location_id, 'customer_id', s.customer_id, 'customer', s.customer,
    'factor', case when s.subtotal > 0 then round(s.total / s.subtotal, 8) else 1 end, 'due_first', public.rule_on('sale_return_due_first'),
    'balance', case when s.customer_id is not null then public._cust_bal(s.customer_id) end,
    'can_return', public.has_grant('sale_return', s.location_id) and s.status = 'done',
    'lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', z.iid, 'name', z.nm, 'unit', z.u, 'sold', z.sq, 'returned', z.pq, 'left', z.sq - z.pq, 'price', round(z.samt / nullif(z.sq, 0), 4)) order by z.nm)
      from (select l.iid, max(l.nm) nm, max(l.u) u, sum(l.q) sq, sum(l.a) samt,
                   coalesce((select sum((x2->>'qty')::numeric) from public.sale_returns r2, jsonb_array_elements(r2.lines) x2 where r2.sale_id = s.id and r2.status = 'done' and x2->>'item_id' = l.iid), 0) pq
            from (select e->>'item_id' iid, e->>'name' nm, e->>'unit' u, (e->>'qty')::numeric q, (e->>'amount')::numeric a
                  from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where nullif(e->>'item_id', '') is not null) l
            group by l.iid) z), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount, 'refund_mode', r.refund_mode,
      'reason', r.reason_code, 'note', r.note, 'status', r.status, 'at', r.created_at, 'staff', r.created_staff) order by r.created_at desc) from public.sale_returns r where r.sale_id = s.id), '[]'::jsonb));
end $$;

-- suppliers that owe US (advance paid, or credit from returns): where a refund can be recorded
create or replace function public.supplier_credits() returns table (supplier_id uuid, name text, mobile text, credit numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(null) then raise exception 'not allowed'; end if;
  return query select z.id, z.name, z.mobile, -z.b from (select s.id, s.name, s.mobile, public._sup_balance(s.id) b from public.suppliers s) z where z.b < 0 order by 4 desc;
end $$;

-- owner-only copies of the two tables whose cost columns are not granted (for the app's backup)
create or replace function public.backup_stock_ledger(p_from bigint default 0, p_limit int default 1000) returns setof public.stock_ledger
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return query select * from public.stock_ledger where id > coalesce(p_from, 0) order by id limit least(greatest(coalesce(p_limit, 1000), 1), 5000);
end $$;
create or replace function public.backup_stock_balance() returns setof public.stock_balance
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return query select * from public.stock_balance order by item_id, location_id;
end $$;
revoke all on function public.backup_stock_ledger(bigint, int), public.backup_stock_balance() from public, anon, authenticated;
grant execute on function public.backup_stock_ledger(bigint, int), public.backup_stock_balance() to authenticated;

-- ---------- privileges for everything new ----------
revoke all on function public._wastage_post(uuid, int, numeric, text, text, text, bigint, uuid, uuid, text), public._cust_bal(uuid), public._sale_void_guard(),
  public.wastage_decide(uuid, boolean, text), public.wastage_cancel(uuid), public.wastage_pending(int, text),
  public.supplier_refund(uuid, int, numeric, text, text, text, text, text, uuid), public.void_supplier_refund(bigint, text),
  public.sale_return(uuid, uuid, jsonb, text, text, text, text, text), public.void_sale_return(uuid, text), public.sale_returns_for(uuid), public.supplier_credits() from public, anon, authenticated;
grant execute on function public.wastage_decide(uuid, boolean, text), public.wastage_cancel(uuid), public.wastage_pending(int, text),
  public.supplier_refund(uuid, int, numeric, text, text, text, text, text, uuid), public.void_supplier_refund(bigint, text),
  public.sale_return(uuid, uuid, jsonb, text, text, text, text, text), public.void_sale_return(uuid, text), public.sale_returns_for(uuid), public.supplier_credits() to authenticated;
-- re-created functions keep their old grants (create or replace); make sure they are exactly as before
revoke all on function public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint), public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid),
  public._sup_balance(uuid), public._sup_open(uuid), public.supplier_ledger(uuid, int), public.customer_balance(uuid), public.customer_dues(), public.customer_ledger(uuid) from public, anon;
grant execute on function public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint), public.supplier_ledger(uuid, int),
  public.customer_balance(uuid), public.customer_dues(), public.customer_ledger(uuid) to authenticated;
revoke all on function public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid), public._sup_balance(uuid), public._sup_open(uuid) from authenticated;

notify pgrst, 'reload schema';

-- ===== phase13 =====
-- ============================================================
-- BOS tool · Phase 13: DAY BOOK (cash / bank / mobile in and out by day) + SALARY REPORT (forms 02-1 / 02-2 / 02-3) + audited exports.
-- Run AFTER phase8, phase9, phase10 (phases 11 / 12 are independent). ADDITIVE and IDEMPOTENT: safe to run again, paste whole.
--
-- Principles kept:
--   * nothing is invented: the day book only adds up rows that really exist (POS payments, due collections, expense vouchers 10-2,
--     supplier payments, cash handover slips 10-1, staff advances 02-3, salary receipts 02-2). A day book start date is the owner's choice:
--     empty = no opening / closing figures at all ("Data needed"), only the movements.
--   * new grant `view_daybook` (owner can delegate to a role or a person, per location, with an end date, emergency window off by default).
--   * salary lines (advances, salary payments) inside the day book are only returned for people who also hold `salary_view`.
--   * salary_report is for the owner or `salary_view` holders only, and only returns what the forms contain; the sums are exactly the
--     formulas of form 02-2 (gross = due + overtime + other; net = gross - advance deduction - other deduction).
--   * export of either page is audited by log_page_export, which needs the owner or the grant export_data (same rpt_grant as the reports).
--   * RLS untouched (no new tables); new functions are SECURITY DEFINER, search_path=public, no anon, authenticated only.
-- ============================================================

-- ---------- (a) settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('daybook_enabled', 'books', 'switch', 'true', null, null, null, null, 'দিনের খাতা (Day book) চালু', 'Day book চালু', 'Day book is on',
  'বন্ধ করলে মালিক ছাড়া কেউ খুলতে পারবে না', 'When off, only the owner can open it', 160),
 ('daybook_start', 'books', 'text', null, 'YYYY-MM-DD', null, null, null, 'দিনের খাতার শুরুর তারিখ (এই তারিখ থেকে চলতি জের গোনা হয়)', 'Day book শুরুর তারিখ (এই তারিখ থেকে running total)', 'Day book start date (running totals count from here)',
  'খালি থাকলে শুরু/শেষ জের দেখানো হয় না — শুধু লেনদেন', 'Empty = no opening / closing figures, movements only', 161),
 ('em_view_daybook', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: দিনের খাতা দেখা', 'জরুরি request চলবে: day book দেখা', 'Emergency allowed for: seeing the day book', 'ডিফল্টে বন্ধ', 'Off by default', 55)
on conflict (key) do nothing;

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('daybook_open_cash', 'books', 'number', null, '৳', null, -1000000000000, 1000000000000, 'শুরুর তারিখে নগদ জের', 'Start তারিখে Cash জের', 'Opening cash balance at the start date', 'খালি = জের দেখানো হয় না (Data needed)', 'Empty = balances are not shown (Data needed)', 162),
 ('daybook_open_bank', 'books', 'number', null, '৳', null, -1000000000000, 1000000000000, 'শুরুর তারিখে ব্যাংক জের', 'Start তারিখে Bank জের', 'Opening bank balance at the start date', 'খালি = জের দেখানো হয় না (Data needed)', 'Empty = balances are not shown (Data needed)', 163),
 ('daybook_open_mobile', 'books', 'number', null, '৳', null, -1000000000000, 1000000000000, 'শুরুর তারিখে মোবাইল জের', 'Start তারিখে Mobile জের', 'Opening mobile balance at the start date', 'খালি = জের দেখানো হয় না (Data needed)', 'Empty = balances are not shown (Data needed)', 164),
 ('daybook_mask_names', 'books', 'switch', 'false', null, null, null, null, 'দিনের খাতায় নাম/রেফারেন্স লুকানো (মালিক ছাড়া)', 'Day book-এ নাম/ref লুকানো (Owner ছাড়া)', 'Mask customer / supplier names and references in the day book (non-owners)', 'ডিফল্টে বন্ধ', 'Off by default', 165)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('view_daybook', 'reports', 27, 'দিনের খাতা দেখা', 'Day book দেখা', 'See the day book', 'window', 'em_view_daybook')
on conflict (grant_code) do nothing;

-- ---------- (b) small safe parsers (never raise; Infinity / NaN / absurd sizes come back null) ----------
create or replace function public._db_num(j jsonb) returns numeric
language plpgsql immutable set search_path = public as $$
declare s text;
begin
  if j is null or jsonb_typeof(j) not in ('number', 'string') then return null; end if;
  s := translate(btrim(j #>> '{}'), '০১২৩৪৫৬৭৮৯', '0123456789');
  s := regexp_replace(s, '(৳|tk\.?|bdt|taka|\s)', '', 'gi');          -- currency signs and spaces
  s := replace(s, ',', '');                                           -- thousands commas
  if s ~ '^-?\.' then s := regexp_replace(s, '^(-?)\.', '\10.'); end if;   -- ".5" -> "0.5"
  s := regexp_replace(s, '\.$', '');                                  -- "5." -> "5"
  if s !~ '^-?[0-9]{1,13}(\.[0-9]{1,6})?$' then return null; end if;
  return s::numeric;
end $$;

create or replace function public._db_date(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or btrim(t) !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return btrim(t)::date;
exception when others then return null;
end $$;

create or replace function public._db_int(j jsonb) returns int
language plpgsql immutable set search_path = public as $$
declare n numeric := public._db_num(j);
begin
  if n is null or n <> trunc(n) or not (n between -100000 and 100000) then return null; end if;
  return n::int;
end $$;

-- the day book start date setting, null when empty / malformed
create or replace function public._db_start() returns date
language sql stable security definer set search_path = public as $$
  select public._db_date(public.rule_txt('daybook_start'));
$$;

-- owner sets / clears the start date (validated here because set_rule only checks "is a string")
create or replace function public.set_daybook_start(p_date date) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_date is not null and not (p_date between date '2000-01-01' and (now() at time zone 'Asia/Dhaka')::date + 1) then raise exception 'bad_date'; end if;
  perform public.set_rule('daybook_start', case when p_date is null then null else to_jsonb(to_char(p_date, 'YYYY-MM-DD')) end);
end $$;

-- owner sets the opening balances AT THE START DATE (null = not set = balances show "Data needed")
create or replace function public.set_daybook_opening(p_cash numeric, p_bank numeric, p_mobile numeric) returns void
language plpgsql security definer set search_path = public as $$
declare v numeric; k text;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  foreach v in array array[p_cash, p_bank, p_mobile] loop
    if v is not null and not (v between -1000000000000 and 1000000000000) then raise exception 'bad_amount'; end if;
  end loop;
  update public.rules set value = case when p_cash is null then null else to_jsonb(p_cash) end, updated_at = now(), updated_by = auth.uid() where key = 'daybook_open_cash';
  update public.rules set value = case when p_bank is null then null else to_jsonb(p_bank) end, updated_at = now(), updated_by = auth.uid() where key = 'daybook_open_bank';
  update public.rules set value = case when p_mobile is null then null else to_jsonb(p_mobile) end, updated_at = now(), updated_by = auth.uid() where key = 'daybook_open_mobile';
end $$;

-- ---------- (c) the raw movements ----------
-- one row per real money movement. p_locs = locations the caller may see; p_sal = the subset where the caller may also see salary lines.
create or replace function public._daybook_lines(p_locs int[], p_sal int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language sql stable as $$
  -- POS: money taken with a sale (kind sale) and due collections (kind collection); card settles to the bank
  select p.location_id, (p.paid_at at time zone 'Asia/Dhaka')::date, 'in'::text,
         case p.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case p.kind when 'collection' then 'collection' else 'sale' end,
         p.amount,
         case when s.receipt is not null then '#' || s.receipt::text end,
         nullif(btrim(concat_ws(' · ', c.name, p.wallet, p.ref)), ''), p.created_staff, p.paid_at,
         case when p.sale_id is not null then 'sale' else 'customer' end, coalesce(p.sale_id::text, p.customer_id::text), false, false
    from public.sale_payments p
    left join public.sales s on s.id = p.sale_id
    left join public.customers c on c.id = p.customer_id
   where not p.voided and p.location_id = any (p_locs) and p.amount between 0.01 and 1000000000000
     and p.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and p.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- supplier payments (with or without a bill)
  select sp.location_id, (sp.paid_at at time zone 'Asia/Dhaka')::date, 'out',
         case sp.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end,
         case when sp.bill_id is not null then 'bill' else 'supplier' end,
         sp.amount, pb.bill_no, nullif(btrim(concat_ws(' · ', su.name, sp.wallet, sp.ref)), ''), sp.created_staff, sp.paid_at,
         case when sp.bill_id is not null then 'bill' else 'supplier' end, coalesce(sp.bill_id::text, sp.supplier_id::text), false, false
    from public.supplier_payments sp
    left join public.suppliers su on su.id = sp.supplier_id
    left join public.purchase_bills pb on pb.id = sp.bill_id
   where not sp.voided and sp.location_id = any (p_locs) and sp.amount between 0.01 and 1000000000000
     and sp.paid_at >= (p_from::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_to + 1)::timestamp at time zone 'Asia/Dhaka')
  union all
  -- 10-2 expense vouchers (submitted or approved): one line per voucher = the sum of its lines
  select e.location_id, e.entry_date, 'out', 'cash', 'expense', x.tot, '#' || e.serial::text,
         x.n::text || ' line(s)', e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, false
    from public.entries e
    cross join lateral (select coalesce(sum(public._db_num(l -> 'amount')) filter (where public._db_num(l -> 'amount') > 0), 0) as tot,
                               count(*) filter (where public._db_num(l -> 'amount') > 0) as n
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l) x
   where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and x.tot between 0.01 and 1000000000000
  union all
  -- 10-1 cash handover slips: counted notes - float left behind. Cash leaves the showroom for the hub (hub side is not recorded -> internal).
  select e.location_id, e.entry_date, 'out', 'cash', 'handover', h.amt, '#' || e.serial::text, nullif(btrim(e.data ->> 'carrier'), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, true, false
    from public.entries e
    cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
        + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
        + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
        + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
        + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
        + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
   where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs)
     and e.entry_date between p_from and p_to and h.amt between 0.01 and 1000000000000
  union all
  -- 02-3 staff advances given in cash / bank / mobile (goods and owner's personal money are not business cash). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(a ->> 'date'), e.entry_date), 'out', a ->> 'method', 'advance', public._db_num(a -> 'amount'),
         '#' || e.serial::text, nullif(btrim(concat_ws(' · ', coalesce(pr.full_name, e.data ->> 'staff'), a ->> 'reason')), ''), e.created_staff,
         coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and (a ->> 'method') in ('cash', 'bank', 'mobile') and public._db_num(a -> 'amount') between 0.01 and 1000000000000
     and coalesce(public._db_date(a ->> 'date'), e.entry_date) between p_from and p_to
  union all
  -- 02-2 salary actually paid (receipt acknowledgement lines: net, method, date). Salary-sensitive.
  select e.location_id, coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date), 'out',
         coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method'), 'salary', public._db_num(r -> 'net'),
         '#' || e.serial::text, nullif(btrim(r ->> 'name'), ''), e.created_staff, coalesce(e.submitted_at, e.created_at), 'entry', e.id::text, false, true
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
   where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal)
     and coalesce(nullif(r ->> 'method', ''), e.data ->> 'pay_method') in ('cash', 'bank', 'mobile') and public._db_num(r -> 'net') between 0.01 and 1000000000000
     and coalesce(public._db_date(r ->> 'date'), public._db_date(e.data ->> 'pay_date'), e.entry_date) between p_from and p_to;
$$;


-- phase12 money flows, only when those tables exist (phase12 may not be installed): refunds paid to customers (OUT) and refunds received from suppliers (IN)
create or replace function public._daybook_lines12(p_locs int[], p_from date, p_to date)
returns table (loc int, d date, dir text, mode text, typ text, amount numeric, ref text, txt text, who text, at timestamptz, src text, src_id text, internal boolean, sensitive boolean)
language plpgsql stable as $$
declare ts timestamptz := p_from::timestamp at time zone 'Asia/Dhaka'; te timestamptz := (p_to + 1)::timestamp at time zone 'Asia/Dhaka';
begin
  if to_regclass('public.sale_returns') is not null then
    return query execute $q$
      select r.location_id, (r.created_at at time zone 'Asia/Dhaka')::date, 'out'::text,
             (case r.refund_mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end)::text, 'sale_return'::text, r.refund_amount::numeric,
             (case when s.receipt is not null then '#' || s.receipt::text end)::text, nullif(btrim(concat_ws(' · ', c.name, r.wallet, r.ref)), '')::text, r.created_staff::text, r.created_at,
             'sale'::text, r.sale_id::text, false, false
        from public.sale_returns r left join public.sales s on s.id = r.sale_id left join public.customers c on c.id = r.customer_id
       where r.status = 'done' and r.refund_amount > 0 and r.refund_mode is not null and r.location_id = any ($1)
         and r.refund_amount between 0.01 and 1000000000000 and r.created_at >= $2 and r.created_at < $3 $q$ using p_locs, ts, te;
  end if;
  if to_regclass('public.supplier_refunds') is not null then
    return query execute $q$
      select f.location_id, (f.refunded_at at time zone 'Asia/Dhaka')::date, 'in'::text,
             (case f.mode when 'cash' then 'cash' when 'mobile' then 'mobile' else 'bank' end)::text, 'supplier_refund'::text, f.amount::numeric,
             null::text, nullif(btrim(concat_ws(' · ', su.name, f.wallet, f.ref)), '')::text, f.created_staff::text, f.refunded_at,
             'supplier'::text, f.supplier_id::text, false, false
        from public.supplier_refunds f left join public.suppliers su on su.id = f.supplier_id
       where not f.voided and f.location_id = any ($1) and f.amount between 0.01 and 1000000000000 and f.refunded_at >= $2 and f.refunded_at < $3 $q$ using p_locs, ts, te;
  end if;
end $$;

-- how many form lines were skipped because their amount could not be read as a number (shown by the page as "N lines could not be read")
create or replace function public._daybook_skipped(p_locs int[], p_sal int[], p_from date, p_to date) returns int
language sql stable as $$
  select (
    (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
      where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_locs) and e.entry_date between p_from and p_to
        and nullif(btrim(l ->> 'amount'), '') is not null and public._db_num(l -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a
      where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(a ->> 'amount'), '') is not null and public._db_num(a -> 'amount') is null)
  + (select count(*) from public.entries e cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'receipts') = 'array' then e.data -> 'receipts' else '[]'::jsonb end) r
      where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (p_sal) and e.entry_date between p_from and p_to
        and nullif(btrim(r ->> 'net'), '') is not null and public._db_num(r -> 'net') is null))::int;
$$;

-- ---------- (d) the day book ----------
-- Result: { from, to (capped at today), loc, start, opening_known, balances, enabled, salary_hidden, names_masked, skipped_rows,
--           days:[{date, open, close, net_open, net_close, in, out, transfers, lines}], totals:{...}, notes:[...] }
-- net_open / net_close = running NET of counted movements since daybook_start (null when no start / day before it).
-- open / close = real balances = the owner's opening balances (daybook_open_*) + net; only when the opening balance of that mode is set AND the view is
--   all locations (the opening balances are business-wide) -> otherwise null ("Data needed").
-- Cash handover slips (10-1) are INTERNAL transfers: always listed as their own lines and summed separately in `transfers`; counted as cash OUT only in a
--   single-location view (the cash really left that showroom), never in the all-locations totals (the hub side has no location on record).
-- Only lines up to today (Dhaka) are returned; p_to beyond today is capped.
create or replace function public.day_book(p_loc int, p_from date, p_to date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_locs int[]; v_sal int[]; v_start date; v_all boolean := (p_loc is null); v_to date; v_today date := (now() at time zone 'Asia/Dhaka')::date;
  v_days jsonb; v_tot jsonb; v_hidden boolean; v_mask boolean; v_known boolean; v_skipped int; v_allseen boolean;
  v_ob numeric[] := array[null, null, null]::numeric[]; v_base numeric[] := array[0, 0, 0]::numeric[]; v_bal boolean;
  v_netopen jsonb; v_netclose jsonb; v_open jsonb; v_close jsonb; v_i1 numeric; v_i2 numeric; v_i3 numeric; v_o1 numeric; v_o2 numeric; v_o3 numeric; v_n1 numeric; v_n2 numeric; v_n3 numeric; v_tr numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_from in (date 'infinity', date '-infinity') or p_to in (date 'infinity', date '-infinity')
     or not (p_from between date '2000-01-01' and date '2100-01-01') or not (p_to between date '2000-01-01' and date '2100-01-01')
     or p_to < p_from or p_to - p_from + 1 > 366 then raise exception 'bad_range'; end if;
  if not public.is_owner() and not public.rule_on('daybook_enabled') then raise exception 'daybook_off'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('view_daybook', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l), '{}') into v_sal from unnest(v_locs) l where public.has_grant('salary_view', l);
  v_hidden := cardinality(v_sal) < cardinality(v_locs);
  v_mask := (not public.is_owner()) and public.rule_on('daybook_mask_names');
  v_start := public._db_start();
  v_to := least(p_to, v_today);
  v_allseen := v_all and (select count(*) from public.locations) = cardinality(v_locs);
  v_ob := array[public.rule_num('daybook_open_cash'), public.rule_num('daybook_open_bank'), public.rule_num('daybook_open_mobile')];
  v_bal := v_allseen and v_ob[1] is not null and v_ob[2] is not null and v_ob[3] is not null;
  v_known := v_start is not null and v_to >= v_start;

  -- opening net: ONE aggregate over [start, p_from - 1] (only rows dated on/after the start date)
  if v_start is not null and v_start < p_from then
    select array[coalesce(sum(s) filter (where mode = 'cash'), 0), coalesce(sum(s) filter (where mode = 'bank'), 0), coalesce(sum(s) filter (where mode = 'mobile'), 0)] into v_base
      from (select u.mode, case when u.dir = 'in' then u.amount else -u.amount end as s
              from (select * from public._daybook_lines(v_locs, v_sal, v_start, p_from - 1) union all select * from public._daybook_lines12(v_locs, v_start, p_from - 1)) u
             where not (u.internal and v_all)) z;
  end if;

  with rl as (select * from public._daybook_lines(v_locs, v_sal, p_from, v_to) union all select * from public._daybook_lines12(v_locs, p_from, v_to)),
  c as (select d, mode, case when dir = 'in' then amount else -amount end as s from rl where not (internal and v_all) and v_start is not null and d >= v_start),
  perday as (select d, sum(s) filter (where mode = 'cash') cash, sum(s) filter (where mode = 'bank') bank, sum(s) filter (where mode = 'mobile') mobile from c group by d),
  cum as (select d, coalesce(cash, 0) cash, coalesce(bank, 0) bank, coalesce(mobile, 0) mobile,
                 coalesce(sum(cash) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[1] pc,
                 coalesce(sum(bank) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[2] pb,
                 coalesce(sum(mobile) over (order by d rows between unbounded preceding and 1 preceding), 0) + v_base[3] pm from perday),
  x as (select t.d,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'cash' and not (t.internal and v_all)), 0) i_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'bank' and not (t.internal and v_all)), 0) i_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'in' and t.mode = 'mobile' and not (t.internal and v_all)), 0) i_mobile,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'cash' and not (t.internal and v_all)), 0) o_cash,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'bank' and not (t.internal and v_all)), 0) o_bank,
          coalesce(sum(t.amount) filter (where t.dir = 'out' and t.mode = 'mobile' and not (t.internal and v_all)), 0) o_mobile,
          coalesce(sum(t.amount) filter (where t.internal), 0) tr,
          jsonb_agg(jsonb_build_object('loc', t.loc, 'dir', t.dir, 'mode', t.mode, 'type', t.typ, 'amount', t.amount,
                    'ref', case when v_mask then null else t.ref end, 'text', case when v_mask then null else t.txt end, 'who', t.who,
                    'at', t.at, 'src', t.src, 'src_id', t.src_id, 'internal', t.internal, 'sensitive', t.sensitive) order by t.at, t.typ) lines
          from rl t group by t.d)
  select coalesce(jsonb_agg(jsonb_build_object(
      'date', x.d,
      'net_open', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc, 'bank', cm.pb, 'mobile', cm.pm, 'total', cm.pc + cm.pb + cm.pm) end,
      'net_close', case when v_start is not null and x.d >= v_start then jsonb_build_object('cash', cm.pc + cm.cash, 'bank', cm.pb + cm.bank, 'mobile', cm.pm + cm.mobile, 'total', cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'open', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc, 'bank', v_ob[2] + cm.pb, 'mobile', v_ob[3] + cm.pm, 'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm) end,
      'close', case when v_bal and x.d >= v_start then jsonb_build_object('cash', v_ob[1] + cm.pc + cm.cash, 'bank', v_ob[2] + cm.pb + cm.bank, 'mobile', v_ob[3] + cm.pm + cm.mobile,
                    'total', v_ob[1] + v_ob[2] + v_ob[3] + cm.pc + cm.pb + cm.pm + cm.cash + cm.bank + cm.mobile) end,
      'in', jsonb_build_object('cash', x.i_cash, 'bank', x.i_bank, 'mobile', x.i_mobile, 'total', x.i_cash + x.i_bank + x.i_mobile),
      'out', jsonb_build_object('cash', x.o_cash, 'bank', x.o_bank, 'mobile', x.o_mobile, 'total', x.o_cash + x.o_bank + x.o_mobile),
      'transfers', x.tr, 'lines', x.lines) order by x.d), '[]'::jsonb),
    coalesce(sum(x.i_cash), 0), coalesce(sum(x.i_bank), 0), coalesce(sum(x.i_mobile), 0), coalesce(sum(x.o_cash), 0), coalesce(sum(x.o_bank), 0), coalesce(sum(x.o_mobile), 0), coalesce(sum(x.tr), 0),
    coalesce(sum(x.i_cash - x.o_cash) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_bank - x.o_bank) filter (where v_start is not null and x.d >= v_start), 0), coalesce(sum(x.i_mobile - x.o_mobile) filter (where v_start is not null and x.d >= v_start), 0)
    into v_days, v_i1, v_i2, v_i3, v_o1, v_o2, v_o3, v_tr, v_n1, v_n2, v_n3
    from x left join cum cm on cm.d = x.d;

  v_tot := jsonb_build_object(
    'in', jsonb_build_object('cash', v_i1, 'bank', v_i2, 'mobile', v_i3, 'total', v_i1 + v_i2 + v_i3),
    'out', jsonb_build_object('cash', v_o1, 'bank', v_o2, 'mobile', v_o3, 'total', v_o1 + v_o2 + v_o3), 'transfers', v_tr);
  if v_known then
    -- start of the range = running net before p_from (rows on/after the start date only); end = that + what happened in the range on/after the start date
    select jsonb_build_object('cash', v_base[1], 'bank', v_base[2], 'mobile', v_base[3], 'total', v_base[1] + v_base[2] + v_base[3]) into v_netopen;
    v_netclose := jsonb_build_object('cash', v_base[1] + v_n1, 'bank', v_base[2] + v_n2, 'mobile', v_base[3] + v_n3, 'total', v_base[1] + v_base[2] + v_base[3] + v_n1 + v_n2 + v_n3);
    v_tot := v_tot || jsonb_build_object('net_open', v_netopen, 'net_close', v_netclose);
    if v_bal then
      v_tot := v_tot || jsonb_build_object('open', jsonb_build_object('cash', v_ob[1] + v_base[1], 'bank', v_ob[2] + v_base[2], 'mobile', v_ob[3] + v_base[3], 'total', v_ob[1] + v_ob[2] + v_ob[3] + v_base[1] + v_base[2] + v_base[3]),
        'close', jsonb_build_object('cash', v_ob[1] + (v_netclose ->> 'cash')::numeric, 'bank', v_ob[2] + (v_netclose ->> 'bank')::numeric, 'mobile', v_ob[3] + (v_netclose ->> 'mobile')::numeric,
                                    'total', v_ob[1] + v_ob[2] + v_ob[3] + (v_netclose ->> 'total')::numeric));
    end if;
  end if;
  v_skipped := public._daybook_skipped(v_locs, v_sal, p_from, v_to);

  return jsonb_build_object('from', p_from, 'to', v_to, 'capped', p_to > v_today, 'loc', p_loc, 'start', v_start, 'opening_known', v_known, 'balances', v_bal,
    'enabled', public.rule_on('daybook_enabled'), 'salary_hidden', v_hidden, 'names_masked', v_mask, 'skipped_rows', v_skipped, 'days', v_days,
    'totals', v_tot || jsonb_build_object('net_open', coalesce(v_tot -> 'net_open', 'null'::jsonb), 'net_close', coalesce(v_tot -> 'net_close', 'null'::jsonb), 'open', coalesce(v_tot -> 'open', 'null'::jsonb), 'close', coalesce(v_tot -> 'close', 'null'::jsonb)),
    'notes', jsonb_build_array('card_as_bank', 'imprest_in_cash', 'bank_deposit_not_dated', 'hub_receipt_not_recorded', 'drafts_excluded', 'refunds_included', 'future_dates_capped'));
end $$;

-- ---------- (e) salary report (forms 02-2 sheet, 02-3 advances, 02-1 attendance) ----------
-- p_month is any date inside the month. A sheet belongs to the month written on the form (month + year), else its entry date.
create or replace function public.salary_report(p_loc int, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_locs int[]; m0 date; m1 date; mm int; yy int; v_rows jsonb; v_adv jsonb; v_att jsonb; v_tot jsonb; v_n int; v_dup jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_month is null or not (p_month between date '2000-01-01' and date '2100-01-01') then raise exception 'bad_range'; end if;
  select array_agg(l.id) into v_locs from public.locations l
   where (p_loc is null or l.id = p_loc) and public.can_loc(l.id) and public.has_grant('salary_view', l.id);
  if v_locs is null or (p_loc is not null and not (p_loc = any (v_locs))) then raise exception 'not allowed'; end if;
  m0 := date_trunc('month', p_month)::date; m1 := (m0 + interval '1 month')::date;
  mm := extract(month from m0)::int; yy := extract(year from m0)::int;

  -- salary sheet lines
  with sh as (
    select e.id, e.serial, e.location_id, e.status, e.data, e.entry_date
      from public.entries e
     where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs)
       and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
       and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy),
  ln as (
    select sh.id as entry_id, sh.serial, sh.location_id, sh.status, btrim(coalesce(r ->> 'name', '')) as name,
           public._db_num(r -> 'salary') salary, public._db_num(r -> 'work_days') work_days, public._db_num(r -> 'absent') absent, public._db_num(r -> 'leave') leave_days,
           coalesce(public._db_num(r -> 'due'), 0) due, coalesce(public._db_num(r -> 'overtime'), 0) overtime, coalesce(public._db_num(r -> 'other'), 0) other,
           coalesce(public._db_num(r -> 'adv_ded'), 0) adv_ded, coalesce(public._db_num(r -> 'other_ded'), 0) other_ded, nullif(btrim(r ->> 'remark'), '') remark,
           sh.data -> 'receipts' as rc, z.ord
      from sh cross join lateral jsonb_array_elements(case when jsonb_typeof(sh.data -> 'pay') = 'array' then sh.data -> 'pay' else '[]'::jsonb end) with ordinality as z(r, ord)),
  ln2 as (select ln.*, count(*) over (partition by location_id, lower(name)) as nn from ln where name <> '' and (due <> 0 or overtime <> 0 or other <> 0 or adv_ded <> 0 or other_ded <> 0 or salary is not null))
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', entry_id, 'serial', serial, 'loc', location_id, 'status', status, 'name', name, 'salary', salary,
        'work_days', work_days, 'absent', absent, 'leave', leave_days, 'due', due, 'overtime', overtime, 'other', other,
        'gross', due + overtime + other, 'adv_ded', adv_ded, 'other_ded', other_ded, 'deductions', adv_ded + other_ded,
        'net', due + overtime + other - adv_ded - other_ded, 'remark', remark, 'ambiguous', nn > 1,
        'paid', case when nn > 1 then null else (select sum(public._db_num(q -> 'net')) from jsonb_array_elements(case when jsonb_typeof(rc) = 'array' then rc else '[]'::jsonb end) q where lower(btrim(q ->> 'name')) = lower(name)) end,
        'signed', case when nn > 1 then null else (select bool_and(coalesce((q ->> 'signed')::boolean, false)) from jsonb_array_elements(case when jsonb_typeof(rc) = 'array' then rc else '[]'::jsonb end) q where lower(btrim(q ->> 'name')) = lower(name)) end)
        order by location_id, serial, ord), '[]'::jsonb),
      jsonb_build_object('people', count(*), 'due', coalesce(sum(due), 0), 'overtime', coalesce(sum(overtime), 0), 'other', coalesce(sum(other), 0),
        'gross', coalesce(sum(due + overtime + other), 0), 'adv_ded', coalesce(sum(adv_ded), 0), 'other_ded', coalesce(sum(other_ded), 0),
        'deductions', coalesce(sum(adv_ded + other_ded), 0), 'net', coalesce(sum(due + overtime + other - adv_ded - other_ded), 0)),
      count(distinct entry_id)::int
    into v_rows, v_tot, v_n from ln2;

  -- advances (02-3): per page = per employee
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'loc', e.location_id, 'status', e.status, 'staff', e.data ->> 'staff',
        'name', coalesce(pr.full_name, e.data ->> 'staff'), 'post', e.data ->> 'post',
        'given', x.given, 'deducted', x.ded, 'outstanding', x.bal) order by e.location_id, e.serial), '[]'::jsonb)
    into v_adv
    from public.entries e
    left join public.profiles pr on pr.staff_id = e.data ->> 'staff'
    cross join lateral (select coalesce(sum(public._db_num(a -> 'amount')) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1), 0) given,
                               coalesce(sum(public._db_num(a -> 'ded_now')) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1), 0) ded,
                               coalesce(sum(public._db_num(a -> 'balance')), 0) bal,
                               count(*) filter (where coalesce(public._db_date(a ->> 'date'), e.entry_date) >= m0 and coalesce(public._db_date(a ->> 'date'), e.entry_date) < m1) n_in
                          from jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) a) x
   where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs) and (x.n_in > 0 or (e.entry_date >= m0 and e.entry_date < m1));

  -- attendance (02-1) of the same month
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', e.id, 'serial', e.serial, 'loc', e.location_id, 'name', btrim(r ->> 'name'), 'present', public._db_num(r -> 'present'),
        'late', public._db_num(r -> 'late'), 'absent', public._db_num(r -> 'absent'), 'leave_unpaid', public._db_num(r -> 'leave_unpaid'), 'leave_paid', public._db_num(r -> 'leave_paid'),
        'ot_hours', public._db_num(r -> 'ot_hours')) order by e.location_id, e.serial), '[]'::jsonb)
    into v_att
    from public.entries e
    cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'staff') = 'array' then e.data -> 'staff' else '[]'::jsonb end) r
   where e.form_code = '02-1' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs) and btrim(coalesce(r ->> 'name', '')) <> ''
     and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
     and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy;

  select coalesce(jsonb_agg(jsonb_build_object('loc', z.location_id, 'n', z.n) order by z.location_id), '[]'::jsonb) into v_dup
    from (select e.location_id, count(*) n from public.entries e
           where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.location_id = any (v_locs)
             and coalesce(public._db_int(e.data -> 'month'), extract(month from e.entry_date)::int) = mm
             and coalesce(public._db_int(e.data -> 'year'), extract(year from e.entry_date)::int) = yy group by 1 having count(*) > 1) z;

  return jsonb_build_object('month', m0, 'loc', p_loc, 'duplicate_sheets', v_dup, 'rows', v_rows, 'totals', v_tot, 'sheets', v_n, 'advances', v_adv, 'attendance', v_att,
    'data_needed', (v_n = 0), 'drafts_excluded', true);
end $$;

-- ---------- (f) audited export of these pages ----------
-- The page calls this BEFORE it builds the file and only builds it when this returns without error, so the check is server-side and the audit row exists.
create or replace function public.log_page_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or p_key not in ('daybook', 'salary') then raise exception 'unknown_report'; end if;
  if p_key = 'daybook' and not (public.is_owner() or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('view_daybook', l.id))) then raise exception 'not allowed'; end if;
  if p_key = 'salary' and not (public.is_owner() or exists (select 1 from public.locations l where public.can_loc(l.id) and public.has_grant('salary_view', l.id))) then raise exception 'not allowed'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges ----------
revoke all on function public._db_num(jsonb), public._db_date(text), public._db_int(jsonb), public._db_start(), public.set_daybook_start(date),
  public._daybook_lines(int[], int[], date, date), public._daybook_lines12(int[], date, date), public._daybook_skipped(int[], int[], date, date), public.set_daybook_opening(numeric, numeric, numeric), public.day_book(int, date, date), public.salary_report(int, date), public.log_page_export(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.set_daybook_start(date), public.set_daybook_opening(numeric, numeric, numeric), public.day_book(int, date, date), public.salary_report(int, date), public.log_page_export(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';

