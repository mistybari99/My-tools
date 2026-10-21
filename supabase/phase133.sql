-- ============================================================
-- Phase 133 (marker scope133) - GROUP ERP, STAGE C3: strict separation of BEHAVIOUR, PERMISSIONS and REPORTS between businesses, behind the switch org_scope_on (DEFAULT OFF).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 3.4, 10; audit docs/audit_c1/RLS_ISOLATION_AUDIT.md (Appendix B, sections 5, 6, 9 tests 9-11, 13); coverage table docs/audit_c1/C3_COVERAGE.md.
-- Canonical order: after phase528 (C2, master data) and phase527 (docs/PASTE_ORDER.md). Paste twice = no change, no error. Needs phases 122 and 123 (phase528 is used when present, not required).
-- With org_scope_on OFF (the default) every behaviour is the one of phase527: each function re-created below keeps its old text as the OFF branch (tests/sql/c3_before_after.sh
-- fingerprints them before / after), every new policy / trigger returns at once while the switch is OFF, and the new tables are read by nothing.
--
--   1  PER-BUSINESS SETTINGS (switch ON only)
--        rule_overrides              business x rule key -> value. rule_val / rule_on / rule_num / rule_txt answer with the business value of the CALLER when there is one
--                                    (caller's working business = the single business of the user, or the working business of phase528 when present; the group owner without a working
--                                    business gets the group value), else the global value. Group-only keys (security, assistant, ui, integrations, backup, scan quota ...) cannot be overridden.
--        rule_override_set133 (owner) / rule_overrides_list133 (owner, management of the business) / rule_val_in133(key, business) / rules_effective133()
--        rule_grant_overrides133      business x grant x role -> allowed / not allowed (a business can take a role grant away or give one the global matrix does not have)
--        role_form_overrides133       the same for the form rights of a role (can_do)
--        can_grant / has_grant / can_do honour them ON; OFF they are the old text.
--        roles.org_unit_id, grant_defs.org_unit_id (nullable: NULL = shared catalogue): a role / grant that belongs to ONE business is invisible to the others (restrictive read policies)
--        rule_grants, role_form_perms, rule_grant_overrides133, role_form_overrides133: rows of a business role / grant are hidden the same way.
--        `management` per business: the role bypass is gone since phase123; the last readers that named the role (assistant_health, org_scope_preflight) are listed in the coverage doc.
--   2  THE BUSINESS BORDER FOR WRITES: a BEFORE INSERT / UPDATE / DELETE trigger <table>_xb133 on every table that has a place column (95 tables; not the system tables listed in the file).
--        While the switch is OFF it returns at once (the switch is read once per transaction). ON: the group owner and the server (no login) pass; anybody else may write a row only at a place of
--        one of his businesses - whatever function does it (so a function that never looked at the place cannot write across the border). Insert = 'not allowed', update / delete of a
--        foreign row = 'not found' (the answer for a missing id).
--   3  READERS AND WRITERS PATCHED BY EXACT-TEXT INSERT (41 functions, marker /* scope133 */, old text kept as the OFF branch; a second paste is a no-op): the books engine (acct_post_pending,
--        acct_status, acct_pending_alert85, profit_source_check count only the documents of the caller's places), the controls (count_unsubmitted_scan, control_counts, void_collection,
--        payment_intent_link, intake_failures_list, assistant_health), customer balances (_cust_bal, customer_dues_net113), place-bound configuration lookups (rollout_mode, blind_active,
--        stock_blind_active, path_cfg, template_for, get_doc_templates, sheet_sync_all, _qc_latest60, cost_source_set_active), the company-level books records and queues that have no business
--        column (chart, mappings, opening journal, bank statements, scheduler, main cost place, setup advisors, outbox): OWNER ONLY while the switch is ON, and login_failed (an unknown staff id
--        is counted and locked like a known one while ON: the lock state is no signal that the id exists, audit test 13).
--   4  DAILY DIGEST PER BUSINESS: daily_digest_biz133(business, date) (owner, the notify bot, or the management of that business); daily_digest() stays the GROUP digest.
--   5  STORAGE: object paths already carry the place (<PREFIX>/<place>/<file>) and the read / insert policies call can_loc, which is business-safe ON. Added: photo_business133(path),
--        photo_path133(prefix, place, name), photo_unmapped133() (owner) and restrictive policies photos_scope133_read / _write on storage.objects: ON, the place in the path must be one of
--        the caller's businesses (the backup bot may read everything). A free Supabase plan has ONE bucket and no per-bucket quota; the isolation is by policy, not by bucket.
--   6  BOT IDENTITY: a message / order written by a bot for a channel outside the bot's businesses is refused by the border trigger; one bot per business (intake_bot_create, owner) is the
--        supported set-up. Group scans (notify_scan, daily_digest, urgent_alerts) stay with the owner and the notify bot (group infrastructure).
--   7  THE COVERAGE CHECKER scope_gaps133() (owner): the exposed SECURITY DEFINER functions that are not scope-aware, by construction (a call of a scope primitive, directly or through a callee).
--        tests/sql/scope_allowlist.txt is the reviewed list (class + reason); phase133_test fails when the two lists differ, so a future function without a scope call cannot slip in.
-- Rollback: leave the switch OFF. To remove: re-paste the older phase files that own the re-created functions (phase7 rule_val / can_grant / can_do, phase123 has_grant ...), drop the
--   policies *_scope133, the triggers *_xb133 and the new tables / functions. Nothing else reads them.
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.user_org_scopes') is null or to_regclass('public.rules') is null or to_regclass('public.rule_grants') is null
     or to_regclass('public.roles') is null or to_regclass('public.grant_defs') is null or to_regclass('public.role_form_perms') is null or to_regclass('public.locations') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public._org_on123()') is null or to_regprocedure('public._my_biz123()') is null or to_regprocedure('public._biz_ok123(integer)') is null
     or to_regprocedure('public._business_of_loc123(integer)') is null or to_regprocedure('public._user_biz123(uuid)') is null or to_regprocedure('public.can_scope(bigint,text)') is null
     or to_regprocedure('public.has_grant(text,integer)') is null or to_regprocedure('public.can_grant(text)') is null or to_regprocedure('public.can_do(text,text)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null then miss := miss || ' functions(phase123)'; end if;
  if miss <> '' then raise exception 'phase133 needs the base schema and phases up to 123 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 0. small helpers ----------
-- the caller's working business: phase528's working business when that phase is pasted, else the ONE business the caller belongs to; null for the group owner without a working
-- business, for a user with no business and for a user in several businesses (then the group value applies).
create or replace function public._caller_biz133() returns bigint
language plpgsql stable security definer set search_path = public as $$
declare b bigint;
begin
  if auth.uid() is null then return null; end if;
  if to_regprocedure('public._m132_caller_biz()') is not null then execute 'select public._m132_caller_biz()' into b; return b; end if;
  select case when count(*) = 1 then min(q.x) end into b from (select distinct x from public._user_biz123(auth.uid()) x) q;
  return b;
end $$;

-- keys that are group infrastructure: never overridden per business
create or replace function public._rule_group_only133(p_key text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_key = 'org_scope_on'
      or p_key ~ '^(twofa|client_error|scan_|backup_|restore_|notify_backup|notify_email|notify_digest|notify_sms|owner_self_approve|intake_|meta_intake|inbox_rate|item_images_|bi_export|barcode_|ia_home|offline_cache|pay_gateway|assistant_)'
      or exists (select 1 from public.rules r where r.key = p_key and r.module in ('security', 'assistant', 'ui', 'integrations'));
$$;

-- the row of a business is for the owner and for the members of that business (used by the read policies of the override tables)
create or replace function public._unit_mine133(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or p_unit in (select public._my_biz123()));
$$;

-- ---------- 1. per-business rule values ----------
create table if not exists public.rule_overrides (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  key text not null references public.rules(key),
  value jsonb not null,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists rule_overrides_uq133 on public.rule_overrides (org_unit_id, key);
create index if not exists rule_overrides_key133 on public.rule_overrides (key) where active;
drop trigger if exists ro133_no_delete on public.rule_overrides;
create trigger ro133_no_delete before delete on public.rule_overrides for each row execute function public.no_hard_delete();
drop trigger if exists audit_ro133 on public.rule_overrides;
create trigger audit_ro133 after insert or update on public.rule_overrides for each row execute function public.log_change('id');
alter table public.rule_overrides enable row level security;
drop policy if exists ro133_read on public.rule_overrides;
create policy ro133_read on public.rule_overrides for select to authenticated using (public._unit_mine133(org_unit_id));
revoke all on public.rule_overrides from public, anon, authenticated;
grant select on public.rule_overrides to authenticated;
revoke all on sequence public.rule_overrides_id_seq from public, anon, authenticated;

-- rule_val: OFF = the text of phase7 (the same expression, read for the same key). ON = the business value of the caller, else the global value.
-- The switch is read once per transaction and kept in the transaction-local setting bos.orgon133 (rule_val is called hundreds of times per request; a lookup of the switch on every call
-- would triple its cost). The switch is flipped by the owner in a request of its own, so a transaction never sees it change.
create or replace function public.rule_val(p_key text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare sw text := current_setting('bos.orgon133', true); v jsonb;
begin
  if sw is null or sw = '' then
    sw := case when coalesce((select (coalesce(x.value, x.default_value) #>> '{}')::boolean from public.rules x where x.key = 'org_scope_on'), false) then '1' else '0' end;
    perform set_config('bos.orgon133', sw, true);
  end if;
  select coalesce(r.value, r.default_value) into v from public.rules r where r.key = p_key;                                       -- OFF: phase7
  if sw = '1' then
    v := coalesce((select o.value from public.rule_overrides o where o.key = p_key and o.active and o.org_unit_id = public._caller_biz133()), v);   -- ON (scope133)
  end if;
  return v;
end $$;

-- the value of one rule for one named business (owner, or a member of that business); the global value when the business has none
create or replace function public.rule_val_in133(p_key text, p_unit bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb; r public.rules;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business') then raise exception 'bad_business'; end if;
  if not (public.is_owner() or p_unit in (select public._my_biz123())) then raise exception 'not allowed'; end if;
  select * into r from public.rules where key = p_key;
  if not found then return null; end if;
  select o.value into v from public.rule_overrides o where o.key = p_key and o.active and o.org_unit_id = p_unit;
  return coalesce(v, r.value, r.default_value);
end $$;

-- every rule as the caller sees it: key, effective value, where it comes from. p_unit null = the caller's own working business (or the group values).
create or replace function public.rules_effective133(p_unit bigint default null) returns table (key text, value jsonb, source text)
language plpgsql stable security definer set search_path = public as $$
declare u bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  u := coalesce(p_unit, public._caller_biz133());
  if u is not null and not (public.is_owner() or u in (select public._my_biz123())) then raise exception 'not allowed'; end if;
  return query select r.key, coalesce(o.value, r.value, r.default_value),
                      case when o.id is not null then 'business' when r.value is not null then 'group' else 'default' end
                 from public.rules r left join public.rule_overrides o on o.key = r.key and o.active and o.org_unit_id = u and public._org_on123()
                order by r.module, r.sort, r.key;
end $$;

-- owner: set / reset (p_value null) the value of a rule for ONE business. Same validation as set_rule; group-only keys are refused.
create or replace function public.rule_override_set133(p_unit bigint, p_key text, p_value jsonb, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.rules; o public.rule_overrides; nid bigint; have boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.rule_overrides where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  select * into r from public.rules where key = p_key;
  if not found then raise exception 'rule not found'; end if;
  if public._rule_group_only133(p_key) then raise exception 'group_only_rule'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into o from public.rule_overrides where org_unit_id = p_unit and key = p_key for update;
  have := found;
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    if not have then return jsonb_build_object('dup', false, 'reset', true, 'id', null); end if;
    update public.rule_overrides set active = false, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'reset', true, 'id', o.id);
  end if;
  if r.kind = 'switch' and jsonb_typeof(p_value) <> 'boolean' then raise exception 'bad_value'; end if;
  if r.kind = 'number' and (jsonb_typeof(p_value) <> 'number' or (p_value #>> '{}')::numeric < coalesce(r.min_value, 0) or (p_value #>> '{}')::numeric > coalesce(r.max_value, 1000000000)) then raise exception 'bad_value'; end if;
  if r.kind = 'choice' and not (r.choices @> jsonb_build_array(p_value #>> '{}')) then raise exception 'bad_value'; end if;
  if r.kind = 'text' and jsonb_typeof(p_value) <> 'string' then raise exception 'bad_value'; end if;
  if p_key = 'period_closed_until' then
    if (p_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_value'; end if;
    begin perform (p_value #>> '{}')::date; exception when others then raise exception 'bad_value'; end;
  end if;
  if have then
    update public.rule_overrides set value = p_value, active = true, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id);
  end if;
  insert into public.rule_overrides (org_unit_id, key, value, note, client_id, created_by, updated_by) values (p_unit, p_key, p_value, p_note, p_client, auth.uid(), auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

-- owner, or the management of that business: the business's own values (and which keys it may not change)
create or replace function public.rule_overrides_list133(p_unit bigint) returns table (id bigint, org_unit_id bigint, key text, value jsonb, global_value jsonb, active boolean, note text, updated_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.can_scope(p_unit, 'management')) then raise exception 'not allowed'; end if;
  return query select o.id, o.org_unit_id, o.key, o.value, coalesce(r.value, r.default_value), o.active, o.note, o.updated_at
                 from public.rule_overrides o join public.rules r on r.key = o.key where o.org_unit_id = p_unit order by o.key;
end $$;

-- ---------- 2. per-business role grants and role form rights ----------
create table if not exists public.rule_grant_overrides133 (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  grant_code text not null references public.grant_defs(grant_code),
  role_code text not null references public.roles(code),
  allowed boolean not null,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists rule_grant_overrides_uq133 on public.rule_grant_overrides133 (org_unit_id, grant_code, role_code);
create table if not exists public.role_form_overrides133 (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  role_code text not null references public.roles(code),
  form_code text not null,
  can_view boolean not null default false, can_enter boolean not null default false, can_approve boolean not null default false,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now()
);
create unique index if not exists role_form_overrides_uq133 on public.role_form_overrides133 (org_unit_id, role_code, form_code);
do $t$
declare t text;
begin
  foreach t in array array['rule_grant_overrides133', 'role_form_overrides133'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nd', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nd', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t, t, 'id');
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._unit_mine133(org_unit_id))', t || '_read', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('revoke all on sequence public.%I from public, anon, authenticated', t || '_id_seq');
  end loop;
end $t$;

-- does the role hold the grant in this business? business row (if any) wins, else the global matrix. p_biz null = the global matrix only.
create or replace function public._grant_eff133(p_code text, p_role text, p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select o.allowed from public.rule_grant_overrides133 o where o.org_unit_id = p_biz and o.grant_code = p_code and o.role_code = p_role and o.active),
    (select g.allowed from public.rule_grants g where g.grant_code = p_code and g.role_code = p_role),
    false);
$$;
-- can the caller (by role) hold the grant in this business?
create or replace function public._can_grant_in133(p_code text, p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and exists (
    select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code and r.active
     where ur.user_id = auth.uid() and public._grant_eff133(p_code, ur.role_code, p_biz)));
$$;
-- form right of the caller's roles in this business (p_biz null = any business of the caller / the global matrix)
create or replace function public._form_eff133(p_role text, p_form text, p_action text, p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select case p_action when 'view' then o.can_view when 'enter' then o.can_enter when 'approve' then o.can_approve else false end
       from public.role_form_overrides133 o where o.org_unit_id = p_biz and o.role_code = p_role and o.form_code = p_form and o.active),
    (select case p_action when 'view' then p.can_view when 'enter' then p.can_enter when 'approve' then p.can_approve else false end
       from public.role_form_perms p where p.role_code = p_role and p.form_code = p_form),
    false);
$$;

-- can_grant: OFF = phase7 text. ON = the role matrix of the caller's business(es): any business of his that gives the role the grant; a person with no business keeps the global matrix.
create or replace function public.can_grant(p_code text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when not coalesce((select (coalesce(x.value, x.default_value) #>> '{}')::boolean from public.rules x where x.key = 'org_scope_on'), false) then (
      public.is_owner() or (public.is_active() and exists (       -- OFF: phase7
        select 1 from public.user_roles ur join public.rule_grants g on g.role_code = ur.role_code and g.grant_code = p_code and g.allowed
        join public.roles r on r.code = ur.role_code and r.active where ur.user_id = auth.uid())))
    else (
      public.is_owner() or (public.is_active() and exists (       -- ON (scope133)
        select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code and r.active
         where ur.user_id = auth.uid() and (
               exists (select 1 from public._my_biz123() b where public._grant_eff133(p_code, ur.role_code, b))
            or (not exists (select 1 from public._my_biz123()) and public._grant_eff133(p_code, ur.role_code, null)))))) end;
$$;

-- can_do: OFF = phase7 text. ON = the form rights of the caller's roles in his business(es).
create or replace function public.can_do(p_form text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when not coalesce((select (coalesce(x.value, x.default_value) #>> '{}')::boolean from public.rules x where x.key = 'org_scope_on'), false) then (
    public.is_owner() or (
      public.is_active() and (exists (       -- OFF: phase7
        select 1 from public.user_roles ur
        join public.role_form_perms p on p.role_code = ur.role_code and p.form_code = p_form
        join public.roles r on r.code = ur.role_code and r.active
        where ur.user_id = auth.uid()
          and case p_action when 'view' then p.can_view when 'enter' then p.can_enter
                            when 'approve' then p.can_approve else false end)
      or (p_action in ('view', 'enter') and exists (
        select 1 from public.emergency_requests e
        where e.requested_by = auth.uid() and e.grant_code = 'form_access' and e.status = 'approved' and e.valid_until > now()
          and p_form <> 'ITEM_COST' and e.context->>'form' = p_form and (e.context->>'action' is null or e.context->>'action' = p_action or p_action = 'view'))))))
  else (
    public.is_owner() or (
      public.is_active() and (exists (       -- ON (scope133)
        select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code and r.active
         where ur.user_id = auth.uid() and (
               exists (select 1 from public._my_biz123() b where public._form_eff133(ur.role_code, p_form, p_action, b))
            or (not exists (select 1 from public._my_biz123()) and public._form_eff133(ur.role_code, p_form, p_action, null))))
      or (p_action in ('view', 'enter') and exists (
        select 1 from public.emergency_requests e
        where e.requested_by = auth.uid() and e.grant_code = 'form_access' and e.status = 'approved' and e.valid_until > now()
          and p_form <> 'ITEM_COST' and e.context->>'form' = p_form and (e.context->>'action' is null or e.context->>'action' = p_action or p_action = 'view')))))) end;
$$;

-- has_grant: the text of phase123 with ONE change in the ON branch: a role grant is looked up in the matrix of the place's business.
create or replace function public.has_grant(p_code text, p_loc int default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (case when not coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then (   -- the switch read inline
    -- OFF: exactly the rule of phase8
    public.can_grant(p_code)
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
               and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
    or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
               where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
               and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  else (
    -- ON (scope123 + scope133): with a location it must be one of the caller's businesses; the role matrix is the one of THAT business; a personal grant without a location = the caller's businesses
    (p_loc is null or public._biz_ok123(p_loc)) and (
      (case when p_loc is null then public.can_grant(p_code) else public._can_grant_in133(p_code, public._business_of_loc123(p_loc)) end)
      or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
                 and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
      or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
                 where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
                 and (p_loc is null or e.location_id is null or e.location_id = p_loc)))
  ) end));
$$;

-- owner: set / reset (p_allowed null) one role grant for ONE business
create or replace function public.rule_grant_override_set133(p_unit bigint, p_grant text, p_role text, p_allowed boolean, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.rule_grant_overrides133; nid bigint; have boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.rule_grant_overrides133 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_grant) then raise exception 'unknown grant'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into o from public.rule_grant_overrides133 where org_unit_id = p_unit and grant_code = p_grant and role_code = p_role for update;
  have := found;
  if p_allowed is null then
    if not have then return jsonb_build_object('dup', false, 'reset', true, 'id', null); end if;
    update public.rule_grant_overrides133 set active = false, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'reset', true, 'id', o.id);
  end if;
  if have then
    update public.rule_grant_overrides133 set allowed = p_allowed, active = true, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id);
  end if;
  insert into public.rule_grant_overrides133 (org_unit_id, grant_code, role_code, allowed, note, client_id, created_by, updated_by) values (p_unit, p_grant, p_role, p_allowed, p_note, p_client, auth.uid(), auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

-- owner: set / reset (all three null) the form rights of a role for ONE business
create or replace function public.role_form_override_set133(p_unit bigint, p_role text, p_form text, p_view boolean, p_enter boolean, p_approve boolean, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.role_form_overrides133; nid bigint; have boolean;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.role_form_overrides133 where client_id = p_client;
  if found then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = 'business' and status <> 'inactive') then raise exception 'bad_business'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if p_form is null or not exists (select 1 from public.forms where code = p_form) then raise exception 'unknown form'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  select * into o from public.role_form_overrides133 where org_unit_id = p_unit and role_code = p_role and form_code = p_form for update;
  have := found;
  if p_view is null and p_enter is null and p_approve is null then
    if not have then return jsonb_build_object('dup', false, 'reset', true, 'id', null); end if;
    update public.role_form_overrides133 set active = false, updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'reset', true, 'id', o.id);
  end if;
  if have then
    update public.role_form_overrides133 set can_view = coalesce(p_view, false), can_enter = coalesce(p_enter, false), can_approve = coalesce(p_approve, false), active = true,
           updated_by = auth.uid(), updated_at = now(), note = coalesce(p_note, note) where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id);
  end if;
  insert into public.role_form_overrides133 (org_unit_id, role_code, form_code, can_view, can_enter, can_approve, note, client_id, created_by, updated_by)
    values (p_unit, p_role, p_form, coalesce(p_view, false), coalesce(p_enter, false), coalesce(p_approve, false), p_note, p_client, auth.uid(), auth.uid()) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

-- the role matrix of a business as the owner / the management of it sees it: global rows plus the business's own rows
create or replace function public.role_matrix_list133(p_unit bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not (public.is_owner() or public.can_scope(p_unit, 'management')) then raise exception 'not allowed'; end if;
  return jsonb_build_object('unit', p_unit,
    'grants', coalesce((select jsonb_agg(jsonb_build_object('grant', g.grant_code, 'role', g.role_code, 'allowed', public._grant_eff133(g.grant_code, g.role_code, p_unit),
                'source', case when exists (select 1 from public.rule_grant_overrides133 o where o.org_unit_id = p_unit and o.grant_code = g.grant_code and o.role_code = g.role_code and o.active) then 'business' else 'group' end) order by g.grant_code, g.role_code)
                from (select grant_code, role_code from public.rule_grants union select grant_code, role_code from public.rule_grant_overrides133 where org_unit_id = p_unit and active) g), '[]'::jsonb),
    'forms', coalesce((select jsonb_agg(jsonb_build_object('role', f.role_code, 'form', f.form_code, 'view', public._form_eff133(f.role_code, f.form_code, 'view', p_unit),
                'enter', public._form_eff133(f.role_code, f.form_code, 'enter', p_unit), 'approve', public._form_eff133(f.role_code, f.form_code, 'approve', p_unit),
                'source', case when exists (select 1 from public.role_form_overrides133 o where o.org_unit_id = p_unit and o.role_code = f.role_code and o.form_code = f.form_code and o.active) then 'business' else 'group' end) order by f.role_code, f.form_code)
                from (select role_code, form_code from public.role_form_perms union select role_code, form_code from public.role_form_overrides133 where org_unit_id = p_unit and active) f), '[]'::jsonb));
end $$;

-- roles and grant definitions that belong to ONE business (NULL = the shared catalogue, as today)
alter table public.roles add column if not exists org_unit_id bigint references public.org_units(id);
alter table public.grant_defs add column if not exists org_unit_id bigint references public.org_units(id);
create or replace function public.role_scope_set133(p_role text, p_unit bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_role is null or p_role = 'owner' or not exists (select 1 from public.roles where code = p_role) then raise exception 'unknown role'; end if;
  if p_unit is not null and not exists (select 1 from public.org_units where id = p_unit and kind = 'business') then raise exception 'bad_business'; end if;
  update public.roles set org_unit_id = p_unit where code = p_role;
end $$;
create or replace function public.grant_scope_set133(p_grant text, p_unit bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if p_grant is null or not exists (select 1 from public.grant_defs where grant_code = p_grant) then raise exception 'unknown grant'; end if;
  if p_unit is not null and not exists (select 1 from public.org_units where id = p_unit and kind = 'business') then raise exception 'bad_business'; end if;
  update public.grant_defs set org_unit_id = p_unit where grant_code = p_grant;
end $$;
-- the row of a business role / grant is hidden from the other businesses (restrictive, true while the switch is OFF; NULL = shared)
create or replace function public._unit_vis133(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or p_unit is null or public.is_owner() or p_unit in (select public._my_biz123());
$$;
create or replace function public._role_vis133(p_role text) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public.is_owner() or coalesce((select public._unit_vis133(r.org_unit_id) from public.roles r where r.code = p_role), true);
$$;
create or replace function public._grant_vis133(p_grant text) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public.is_owner() or coalesce((select public._unit_vis133(d.org_unit_id) from public.grant_defs d where d.grant_code = p_grant), true);
$$;
drop policy if exists roles_scope133 on public.roles;
create policy roles_scope133 on public.roles as restrictive for select to authenticated using (public._unit_vis133(org_unit_id));
drop policy if exists grant_defs_scope133 on public.grant_defs;
create policy grant_defs_scope133 on public.grant_defs as restrictive for select to authenticated using (public._unit_vis133(org_unit_id));
drop policy if exists rule_grants_scope133 on public.rule_grants;
create policy rule_grants_scope133 on public.rule_grants as restrictive for select to authenticated using (public._role_vis133(role_code) and public._grant_vis133(grant_code));
drop policy if exists role_form_perms_scope133 on public.role_form_perms;
create policy role_form_perms_scope133 on public.role_form_perms as restrictive for select to authenticated using (public._role_vis133(role_code));

-- ---------- 3. the text-patch helper for the readers / writers of section 4 (current live body + exact-text anchors; marker makes a second paste a no-op) ----------
create or replace function public._patch133(p_fn regprocedure, p_marker text, p_pairs text[]) returns void
language plpgsql security definer set search_path = public as $$
declare d text; i int;
begin
  d := pg_get_functiondef(p_fn);
  if position(p_marker in d) > 0 then return; end if;
  for i in 1..array_length(p_pairs, 1) by 2 loop
    if (length(d) - length(replace(d, p_pairs[i], ''))) / greatest(length(p_pairs[i]), 1) <> 1 then
      raise exception 'phase133: the anchor "%" is not in % exactly once (a newer body? merge by hand)', left(p_pairs[i], 70), p_fn;
    end if;
    d := replace(d, p_pairs[i], p_pairs[i + 1]);
  end loop;
  execute d;
end $$;

-- ---------- 4. the business border for WRITES (switch ON): a user cannot insert / update / delete a row of a place outside his businesses, whatever function does it ----------
-- The trigger passes at once while the switch is OFF, for the group owner and for the server (no login). INSERT into a foreign place = 'not allowed'; UPDATE / DELETE of a foreign row =
-- 'not found' (the answer for a missing id); moving a row into a foreign place = 'not allowed'.
create or replace function public._xb133() returns trigger
language plpgsql security definer set search_path = public as $$
declare c text; v int; o int; cache text; uid text := auth.uid()::text; st text := current_setting('bos.xbst133', true);
begin
  if st = '0' then return coalesce(new, old); end if;                                   -- OFF, already read in this transaction (one lookup per transaction, not per row)
  if uid is null then return coalesce(new, old); end if;
  if st is null or st = '' then
    st := case when coalesce((select (coalesce(r.value, r.default_value) #>> '{}')::boolean from public.rules r where r.key = 'org_scope_on'), false) then '1' else '0' end;
    perform set_config('bos.xbst133', st, true);
    if st = '0' then return coalesce(new, old); end if;
  end if;
  cache := coalesce(current_setting('bos.xbok133', true), '');                        -- places already proven for this person in this transaction
  if position(',own:' || uid || ',' in cache) > 0 then return coalesce(new, old); end if;
  if public.is_owner() then perform set_config('bos.xbok133', cache || ',own:' || uid || ',', true); return coalesce(new, old); end if;
  foreach c in array tg_argv loop
    v := null; o := null;
    if tg_op <> 'DELETE' then v := nullif(to_jsonb(new) ->> c, '')::int; end if;
    if tg_op <> 'INSERT' then o := nullif(to_jsonb(old) ->> c, '')::int; end if;
    if o is not null and position(',' || uid || ':' || o || ',' in cache) = 0 then
      if not public._biz_ok123(o) then raise exception 'not found'; end if;
      cache := cache || ',' || uid || ':' || o || ',';
    end if;
    if v is not null and position(',' || uid || ':' || v || ',' in cache) = 0 then
      if not public._biz_ok123(v) then raise exception 'not allowed'; end if;
      cache := cache || ',' || uid || ':' || v || ',';
    end if;
  end loop;
  perform set_config('bos.xbok133', cache, true);
  return coalesce(new, old);
end $$;

do $xb$
declare r record; cols text[]; skip text[] := array['locations', 'user_locations', 'user_grants', 'user_org_scopes', 'notifications', 'exceptions', 'sales_fact_t', 'bi_export_log', 'items', 'option_sets', 'option_values',
  'item_styles', 'price_lists', 'price_list_items', 'legal_entities', 'ie_currencies', 'ie_fx_rates', 'ie_shipments', 'ie_shipment_events'];
begin
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' and not c.relispartition and c.relname <> all (skip)
              and exists (select 1 from pg_attribute a where a.attrelid = c.oid and not a.attisdropped and a.attname in ('location_id', 'from_location_id', 'to_location_id', 'primary_location_id'))
            order by 1 loop
    select array_agg(a.attname::text order by a.attname) into cols from pg_attribute a
     where a.attrelid = ('public.' || quote_ident(r.relname))::regclass and not a.attisdropped and a.attname in ('location_id', 'from_location_id', 'to_location_id', 'primary_location_id');
    execute format('drop trigger if exists %I on public.%I', r.relname || '_xb133', r.relname);
    execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public._xb133(%s)', r.relname || '_xb133', r.relname,
                   (select string_agg(quote_literal(x), ', ') from unnest(cols) x));
  end loop;
end $xb$;

-- ---------- 5. storage (bucket photos): paths are <PREFIX>/<place>/<file>, so the place - and with it the business - is in every path ----------
create or replace function public.photo_business133(p_name text) returns bigint
language sql stable security definer set search_path = public as $$
  select case when p_name ~ '^[A-Za-z0-9_.-]+/[0-9]{1,9}/' and (public.is_owner() or public._biz_ok123(split_part(p_name, '/', 2)::int))
              then public._business_of_loc123(split_part(p_name, '/', 2)::int) end;
$$;
-- the path a NEW upload should use: <PREFIX>/<place>/<name>; refused for a place outside the caller's businesses
create or replace function public.photo_path133(p_prefix text, p_loc int, p_name text) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_prefix is null or p_prefix !~ '^[A-Za-z0-9_.-]{1,30}$' or p_name is null or p_name !~ '^[A-Za-z0-9_.-]{1,120}$' or p_loc is null then raise exception 'bad_input'; end if;
  if public._org_on123() and not public._biz_ok123(p_loc) then raise exception 'not allowed'; end if;
  if not public._org_on123() and not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  return p_prefix || '/' || p_loc || '/' || p_name;
end $$;
-- may the caller touch an object of the photos bucket under this path? OFF: true (the permissive policies decide, as today). ON: the place in the path must be one of his businesses; the
-- backup bot (ops purpose backup) may read everything (group infrastructure, read only).
create or replace function public._photo_scope133(p_name text, p_read boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or public.is_owner() or (p_read and public._is_ops('backup'))
         or (p_name ~ '^[A-Za-z0-9_.-]+/[0-9]{1,9}/' and public._biz_ok123(split_part(p_name, '/', 2)::int));
$$;
-- owner: what is in the bucket per business (object count by business, objects whose path has no mapped place)
create or replace function public.photo_unmapped133() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb;
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  if to_regclass('storage.objects') is null then return jsonb_build_object('storage', false); end if;
  execute $q$select jsonb_build_object('storage', true, 'objects', coalesce(sum(n), 0), 'by_business', coalesce(jsonb_object_agg(coalesce(b::text, 'none'), n), '{}'::jsonb))
    from (select public._business_of_loc123(case when name ~ '^[A-Za-z0-9_.-]+/[0-9]{1,9}/' then split_part(name, '/', 2)::int end) b, count(*) n
            from storage.objects where bucket_id = 'photos' group by 1) z$q$ into res;
  return res;
end $$;
do $st$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists photos_scope133_read on storage.objects';
    execute 'create policy photos_scope133_read on storage.objects as restrictive for select to authenticated using (bucket_id <> ''photos'' or public._photo_scope133(name, true))';
    execute 'drop policy if exists photos_scope133_write on storage.objects';
    execute 'create policy photos_scope133_write on storage.objects as restrictive for insert to authenticated with check (bucket_id <> ''photos'' or public._photo_scope133(name, false))';
  end if;
end $st$;

-- ---------- 6. exposed functions that read or write business data with a gate that does not look at the place (old text kept as the OFF branch) ----------
-- gate helper: the same exact-text patch, but the text is inserted right after the first `begin` of a plpgsql body (the body starts with a gate that is true while the switch is OFF)
create or replace function public._gate133(p_fn regprocedure, p_marker text, p_gate text) returns void
language plpgsql security definer set search_path = public as $$
declare d text; n text;
begin
  d := pg_get_functiondef(p_fn);
  if position(p_marker in d) > 0 then return; end if;
  if d !~ E'\nbegin[^\n]*\n' then raise exception 'phase133: no plpgsql begin in %', p_fn; end if;
  n := regexp_replace(d, E'\nbegin([^\n]*)\n', E'\nbegin\\1\n  ' || replace(p_gate, '\', '\\') || '   ' || p_marker || E'\n');
  execute n;
end $$;

-- a place-bound configuration lookup may answer for a place outside the caller's businesses only to the owner, the server (no login) and the notify / backup bots (group infrastructure)
create or replace function public._cfgvis133(p_loc int) returns boolean
language sql stable security definer set search_path = public as $$
  select not public._org_on123() or auth.uid() is null or public.is_owner() or public._is_ops('notify') or public._is_ops('backup') or public._biz_ok123(p_loc);
$$;

do $p$
declare f text;
begin
-- 6.1 login lockout: with the switch ON an unknown staff id is counted and locked like a known one, so the lock state is no signal that the id exists (audit test 13)
perform public._patch133('public.login_failed(text)'::regprocedure, 'scope133', array[
  E'  if not known then return; end if;',
  E'  if not known and not public._org_on123() then return; end if;   /* scope133 */\n  if not known and random() < 0.02 then delete from public.login_failures lf where lf.last_fail < now() - interval ''1 day'' and not exists (select 1 from public.profiles p where p.staff_id = lf.staff_id); end if;']);

-- 6.2 the books engine: a business accountant posts / counts only the documents of his places (owner and the scheduler: all)
perform public._patch133('public.acct_post_pending(boolean,integer)'::regprocedure, 'scope133', array[
  'for d in select * from public._acct_docs(st) order by 3, 1, 2 loop',
  'for d in select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id)) /* scope133 */ order by 3, 1, 2 loop']);
perform public._patch133('public.acct_status()'::regprocedure, 'scope133', array[
  'with dd as materialized (select * from public._acct_docs(st)),',
  'with dd as materialized (select * from public._acct_docs(st) x where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(x.location_id))), /* scope133 */',
  '''entries'', (select count(*) from public.journal_entries),',
  '''entries'', (select count(*) from public.journal_entries je where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(je.location_id))),']);

-- 6.3 company-level books records (chart of accounts, mappings, opening journal, bank statements, the scheduler, the main cost place): owner only while the switch is ON
-- (one chart and one set of bank statements for the whole database until the per-entity books of Stage C2b; year closes were closed the same way in phase123)
  foreach f in array array['public.acct_account_save(bigint,text,text,text,text,bigint,boolean,integer,boolean)', 'public.acct_mapping_set(text,bigint)', 'public.acct_opening(jsonb,boolean,text,uuid,boolean)',
      'public.acct_scheduler_enable(text)', 'public.acct_scheduler_disable()', 'public.bank_recon_candidates(bigint,integer)', 'public.bank_recon_lines(bigint,text,integer)', 'public.bank_recon_report(bigint,date,date)',
      'public.bank_recon_suggest(bigint,date,date,integer)', 'public.bank_recon_unmatch(bigint,text)', 'public.bank_recon_match(bigint,bigint,integer,text)', 'public.bank_recon_match_many(jsonb,boolean)',
      'public.bank_stmt_import(bigint,jsonb,uuid,boolean)', 'public.cost_attrib_main_set(integer,date,text,uuid)',
      'public.setup_flow_check()', 'public.setup_readiness(text)', 'public.notify_outbox_summary()', 'public.notify_cancel(bigint)', 'public.setup_recommendations()'] loop
    perform public._gate133(f::regprocedure, '/* scope133 */', 'if public._org_on123() and auth.uid() is not null and not public.is_owner() then raise exception ''not allowed''; end if;');
  end loop;

-- 6.4 readers / writers of the dashboards and the controls
perform public._patch133('public.count_unsubmitted_scan()'::regprocedure, 'scope133', array[
  'and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = ''count_unsubmitted'');',
  'and not exists (select 1 from public.exceptions x where x.entry_id = e.id and x.flag_code = ''count_unsubmitted'')
      and ((select not public._org_on123()) or public.can_loc(e.location_id));   /* scope133: only the places of the caller */']);
perform public._patch133('public.control_counts()'::regprocedure, 'scope133', array[
  'select count(*) into n from public.locations where status in (''planned'', ''setting_up'');',
  'select count(*) into n from public.locations where status in (''planned'', ''setting_up'') and ((select not public._org_on123()) or public.can_loc(id));   /* scope133 */',
  'select count(*) into n from public.settings_sheets where status = ''draft'';',
  'select count(*) into n from public.settings_sheets where status = ''draft'' and ((select not public._org_on123()) or public.can_loc(location_id));   /* scope133 */']);
perform public._patch133('public.void_collection(bigint,text)'::regprocedure, 'scope133', array[
  '  if p.voided then raise exception ''already void''; end if;',
  E'  if public._org_on123() and not public._biz_ok123(p.location_id) then raise exception ''not found''; end if;   /* scope133: the same answer as a missing id */\n  if p.voided then raise exception ''already void''; end if;']);
perform public._patch133('public.payment_intent_link(bigint,bigint)'::regprocedure, 'scope133', array[
  'if not exists (select 1 from public.sale_payments where id = p_sale_payment) then',
  'if not exists (select 1 from public.sale_payments where id = p_sale_payment and ((select not public._org_on123()) or auth.uid() is null or public._biz_ok123(location_id))) then   /* scope133 */']);
perform public._patch133('public.customer_dues_net113()'::regprocedure, 'scope133', array[
  'where m.kind = ''cust_advance_used'' and m.status = ''done'' and m.customer_id is not null group by 1),',
  'where m.kind = ''cust_advance_used'' and m.status = ''done'' and m.customer_id is not null and ((select not public._org_on123()) or public.can_loc(m.location_id)) group by 1),   /* scope133 */',
  'from public.sales x where x.status = ''done'' and x.customer_id in (select b2.id from b b2)),',
  'from public.sales x where x.status = ''done'' and x.customer_id in (select b2.id from b b2) and ((select not public._org_on123()) or public.can_loc(x.location_id))),']);
perform public._patch133('public.sheet_sync_all()'::regprocedure, 'scope133', array[
  'for l in select id from public.locations loop',
  'for l in select id from public.locations where ((select not public._org_on123()) or public.is_owner() or public._biz_ok123(id)) loop   /* scope133 */']);

perform public._patch133('public.assistant_health()'::regprocedure, 'scope133', array[
  'where coalesce(l.status, ''live'') in (''live'', ''setting_up'') and (public.is_owner() or public.has_grant(''head_management'') or public.can_loc(l.id));',
  'where coalesce(l.status, ''live'') in (''live'', ''setting_up'') and (public.is_owner() or (public.has_grant(''head_management'') and ((select not public._org_on123()) or public._biz_ok123(l.id))) or public.can_loc(l.id));   /* scope133 */']);
perform public._patch133('public.profit_source_check(date,date,integer)'::regprocedure, 'scope133', array[
  'and (p_loc is null or d.location_id = p_loc);',
  'and (p_loc is null or d.location_id = p_loc) and ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(d.location_id));   /* scope133 */']);

perform public._patch133('public._cust_bal(uuid)'::regprocedure, 'scope133', array[
  'where s.customer_id = p_customer and s.status = ''done''),',
  'where s.customer_id = p_customer and s.status = ''done'' and ((select not public._org_on123()) or public._cfgvis133(s.location_id))),   /* scope133: a customer balance counts the sales of the caller''s businesses (owner, server and the notify bot: all) */',
  'where p.customer_id = p_customer and not p.voided),',
  'where p.customer_id = p_customer and not p.voided and ((select not public._org_on123()) or public._cfgvis133(p.location_id))),',
  'where r.customer_id = p_customer and r.status = ''done''),',
  'where r.customer_id = p_customer and r.status = ''done'' and ((select not public._org_on123()) or public._cfgvis133(r.location_id))),']);

perform public._patch133('public.cost_source_set_active(bigint,boolean,text)'::regprocedure, 'scope133', array[
  '  if p_active is null then raise exception ''bad_value''; end if;',
  E'  if p_active is null then raise exception ''bad_value''; end if;\n  if public._org_on123() and auth.uid() is not null and not public._cs_src_ok(p_id) then raise exception ''source_not_found''; end if;   /* scope133: a cost source of another business is a missing id */']);
perform public._patch133('public._qc_latest60(text,uuid)'::regprocedure, 'scope133', array[
  'where source_type = p_type and source_id = p_id order by created_at desc, id desc limit 1;',
  'where source_type = p_type and source_id = p_id and ((select not public._org_on123()) or public._cfgvis133(location_id)) /* scope133 */ order by created_at desc, id desc limit 1;']);

perform public._patch133('public.acct_pending_alert85(integer)'::regprocedure, 'scope133', array[
  'd.live, d.waiting from public._acct_docs(st) d)',
  'd.live, d.waiting from public._acct_docs(st) d where ((select not public._org_on123()) or auth.uid() is null or public.is_owner() or public._biz_ok123(d.location_id)))   /* scope133 */']);

perform public._patch133('public.intake_failures_list(text,integer)'::regprocedure, 'scope133', array[
  'from public.intake_failures f where p_state is null or f.state = p_state order by f.id desc limit',
  'from public.intake_failures f where (p_state is null or f.state = p_state) and ((select not public._org_on123()) or public.is_owner() or exists (select 1 from public.sales_channels sc where sc.id = f.channel_id and public._biz_ok123(sc.location_id))) /* scope133 */ order by f.id desc limit']);

-- 6.5 place-bound configuration lookups
perform public._patch133('public.rollout_mode(text,integer)'::regprocedure, 'scope133', array[
  'where form_code = p_form and location_id = p_loc), ''app'');',
  'where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), ''app'');   /* scope133 */']);
perform public._patch133('public.blind_active(text,integer)'::regprocedure, 'scope133', array[
  'where form_code = p_form and location_id = p_loc), true);',
  'where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */']);
perform public._patch133('public.stock_blind_active(text,integer)'::regprocedure, 'scope133', array[
  'where form_code = p_form and location_id = p_loc), true);',
  'where form_code = p_form and location_id = p_loc and public._cfgvis133(p_loc)), true);   /* scope133 */']);
perform public._patch133('public.path_cfg(text,integer)'::regprocedure, 'scope133', array[
  'order by s.location_id desc limit 1) x on true',
  'and (s.location_id = 0 or public._cfgvis133(s.location_id)) /* scope133 */ order by s.location_id desc limit 1) x on true']);
perform public._patch133('public.template_for(text,integer)'::regprocedure, 'scope133', array[
  'and (t.location_id = p_loc or t.location_id is null)',
  'and (t.location_id = p_loc or t.location_id is null) and (t.location_id is null or public._cfgvis133(t.location_id)) /* scope133 */']);
perform public._patch133('public.get_doc_templates(integer)'::regprocedure, 'scope133', array[
  'from public.doc_template_choice c), ''[]''::jsonb);',
  'from public.doc_template_choice c where (c.location_id is null or public._cfgvis133(c.location_id))), ''[]''::jsonb);   /* scope133 */']);
end $p$;

-- ---------- 7. the daily digest per business ----------
-- daily_digest() is the GROUP digest (owner or the notify bot; all places; unchanged). daily_digest_biz133(business, date) is the same digest for ONE business: only the places of that business,
-- the rules of that business (reports_net_of_returns, notify_expiry_days), no group-level parts (backup status, item change requests, pending staff). Owner, the notify bot, or the
-- management of that business.
create or replace function public._rule_in133(p_key text, p_unit bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce((select o.value from public.rule_overrides o where o.key = p_key and o.active and o.org_unit_id = p_unit and public._org_on123()), r.value, r.default_value) from public.rules r where r.key = p_key;
$$;
create or replace function public.daily_digest_biz133(p_biz bigint, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, public._today()); locs int[]; neg boolean; expd int; td jsonb; yd jsonb; lw jsonb; byloc jsonb; top5 jsonb; cash jsonb; coll numeric; custdue numeric; custn int;
        sup jsonb; waste jsonb; voids jsonb; ex jsonb; appr int; lowc int; expc int; closes jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_biz is null or not exists (select 1 from public.org_units where id = p_biz and kind = 'business') then raise exception 'bad_business'; end if;
  if not (public.is_owner() or public._is_ops('notify') or public.can_scope(p_biz, 'management')) then raise exception 'not allowed'; end if;
  if d > public._today() or d < public._today() - 400 then raise exception 'bad_date'; end if;
  select coalesce(array_agg(l.id), '{}'::int[]) into locs from public.locations l where public._business_of_loc123(l.id) = p_biz;
  neg := coalesce((public._rule_in133('reports_net_of_returns', p_biz) #>> '{}')::boolean, false);
  expd := coalesce(nullif(public._rule_in133('notify_expiry_days', p_biz) #>> '{}', '')::numeric, 3)::int;
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a, 'net', case when neg then s.t - r.a else s.t end) into td
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = d and location_id = any (locs)) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = d and location_id = any (locs)) r;
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a, 'net', case when neg then s.t - r.a else s.t end) into yd
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = d - 1 and location_id = any (locs)) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = d - 1 and location_id = any (locs)) r;
  select jsonb_build_object('bills', s.n, 'total', s.t, 'discount', s.d, 'returns', r.a, 'net', case when neg then s.t - r.a else s.t end) into lw
    from (select count(*) n, coalesce(sum(total), 0) t, coalesce(sum(discount), 0) d from public.sales where status = 'done' and sale_date = d - 7 and location_id = any (locs)) s,
         (select coalesce(sum(amount), 0) a from public.sale_returns where status = 'done' and (created_at at time zone 'Asia/Dhaka')::date = d - 7 and location_id = any (locs)) r;
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en, 'net', v.net) order by l.sort), '[]'::jsonb) into byloc
    from public.locations l cross join lateral (
      select coalesce((select sum(total) from public.sales where status = 'done' and sale_date = d and location_id = l.id), 0)
           - case when neg then coalesce((select sum(amount) from public.sale_returns where status = 'done' and location_id = l.id and (created_at at time zone 'Asia/Dhaka')::date = d), 0) else 0 end as net) v
   where l.id = any (locs) and l.is_active and l.status = 'live' and l.kind = 'showroom';
  select coalesce(jsonb_agg(jsonb_build_object('name', z.nm, 'qty', z.q, 'amount', z.a) order by z.a desc), '[]'::jsonb) into top5 from (
    select coalesce(x.ln ->> 'name', '?') nm, round(sum((x.ln ->> 'qty')::numeric), 3) q, round(sum((x.ln ->> 'amount')::numeric), 2) a
      from (select jsonb_array_elements(s.lines) ln from public.sales s where s.status = 'done' and s.sale_date = d and s.location_id = any (locs)) x
     where (x.ln ->> 'amount') ~ '^-?[0-9.]+$' and (x.ln ->> 'qty') ~ '^-?[0-9.]+$' group by coalesce(x.ln ->> 'name', '?') order by sum((x.ln ->> 'amount')::numeric) desc limit 5) z;
  select jsonb_build_object('count', count(*), 'short', coalesce(sum(-amount) filter (where amount < 0), 0), 'over', coalesce(sum(amount) filter (where amount > 0), 0)) into cash
    from public.exceptions where flag_code = 'cash_short_over' and entry_date = d and location_id = any (locs);
  select coalesce(sum(amount), 0) into coll from public.sale_payments where kind = 'collection' and not voided and (paid_at at time zone 'Asia/Dhaka')::date = d and location_id = any (locs);
  with s as (select x.id, x.customer_id, x.sold_at, x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
               from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs)),
       c as (select z.customer_id, sum(z.a) coll from (select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null and location_id = any (locs)
               union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0 and location_id = any (locs)) z group by 1),
       t as (select customer_id, sum(rem) rem from s group by 1)
  select coalesce(sum(t.rem - coalesce(c.coll, 0)), 0), count(*) into custdue, custn from t left join c on c.customer_id = t.customer_id where t.rem - coalesce(c.coll, 0) > 0;
  select jsonb_build_object('payable', coalesce(sum(o.open_amt), 0), 'suppliers', count(distinct o.supplier_id),
           'overdue', coalesce(sum(o.open_amt) filter (where s.credit_days is not null and o.bill_date is not null and o.bill_date + s.credit_days < public._today()), 0)) into sup
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id where o.open_amt > 0 and o.location_id = any (locs);
  select jsonb_build_object('count', count(*), 'value', coalesce(round(sum(x.qty * coalesce(b.avg_cost, 0)), 2), 0)) into waste
    from public.stock_wastage x left join public.stock_balance b on b.item_id = x.item_id and b.location_id = x.location_id where (x.made_at at time zone 'Asia/Dhaka')::date = d and x.location_id = any (locs);
  select jsonb_build_object('void_count', count(*) filter (where status = 'void'), 'void_total', coalesce(sum(total) filter (where status = 'void'), 0),
           'discount_count', count(*) filter (where status = 'done' and discount > 0), 'discount_total', coalesce(sum(discount) filter (where status = 'done'), 0)) into voids
    from public.sales where sale_date = d and location_id = any (locs);
  select jsonb_build_object('red', count(*) filter (where level = 'red'), 'yellow', count(*) filter (where level = 'yellow')) into ex from public.exceptions where status = 'open' and location_id = any (locs);
  select count(*) into appr from (
      select 1 from public.entries where status = 'submitted' and location_id = any (locs)
      union all select 1 from public.release_requests q join public.entries e on e.id = q.entry_id where q.status = 'pending' and e.location_id = any (locs)
      union all select 1 from public.emergency_requests where status = 'pending' and location_id = any (locs)
      union all select 1 from public.wastage_requests where status = 'pending' and location_id = any (locs)) u;
  select count(*) into lowc from public.stock_balance b join public.items i on i.id = b.item_id where i.is_active and coalesce(i.min_stock, 0) > 0 and b.qty <= i.min_stock and b.location_id = any (locs);
  select count(*) into expc from public.stock_batches where qty_remaining > 0 and expires_at is not null and expires_at < now() + make_interval(days => expd) and location_id = any (locs);
  select coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name_bn', l.name_bn, 'name_en', l.name_en,
           'closed', exists (select 1 from public.entries e where e.form_code = '14-1' and e.location_id = l.id and e.entry_date = d and e.status in ('submitted', 'approved')),
           'mode', public.rollout_mode('14-1', l.id)) order by l.sort), '[]'::jsonb) into closes
    from public.locations l where l.id = any (locs) and l.is_active and l.status = 'live' and l.kind = 'showroom';
  return jsonb_build_object('business', p_biz, 'date', d, 'generated_at', now(),
    'sales', jsonb_build_object('today', td, 'yesterday', yd, 'last_week', lw,
       'vs_yesterday_pct', case when (yd ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (yd ->> 'net')::numeric) * 100 / (yd ->> 'net')::numeric, 1) end,
       'vs_last_week_pct', case when (lw ->> 'net')::numeric > 0 then round(((td ->> 'net')::numeric - (lw ->> 'net')::numeric) * 100 / (lw ->> 'net')::numeric, 1) end,
       'by_location', byloc),
    'top_items', top5, 'cash', cash, 'collections', coll,
    'dues', jsonb_build_object('customers_total', round(custdue, 2), 'customers', custn, 'suppliers', sup),
    'wastage', waste, 'voids_discounts', voids, 'exceptions_open', ex, 'approvals_pending', appr,
    'stock_alerts', jsonb_build_object('low_items', lowc, 'expiring_batches', expc),
    'day_close', closes);
end $$;

-- ---------- 8. the coverage checker: every exposed SECURITY DEFINER function that is NOT scope-aware ----------
-- Scope-aware = its body calls a scope primitive (can_loc, can_scope, _biz_ok123, _my_biz123 ... or has_grant / can_do with a place argument), or it calls a function that is (fixpoint over
-- the call graph; a callee without arguments only counts when it returns a set). The OWNER reads the rest; tests/sql/scope_allowlist.txt is the reviewed list (class + reason per function)
-- and phase133_test fails when a function is in one list and not in the other, so a new function without a scope call cannot slip in. docs/audit_c1/C3_COVERAGE.md explains the classes.
create or replace function public.scope_gaps133() returns table (fn text, args text, gate text, tables_ text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;
  return query
  with recursive
  prim(n) as (select unnest(array['can_loc', 'can_scope', 'business_of_location', '_biz_ok123', '_my_biz123', '_user_biz123', '_business_of_loc123', 'org_unit_scope', '_loc_vis123', '_shares_biz123',
                                  '_mgmt_covers123', '_biz_vis125', '_my_biz125', '_dl_ok127', '_caller_biz133', '_can_grant_in133', '_acct_locs', '_acct_all', '_all_locs', '_cfgvis133', '_unit_vis133', '_unit_mine133', '_photo_scope133'])),
  noprop(n) as (select unnest(array['has_grant', 'can_grant', 'can_do', 'is_owner', 'is_active', 'rule_on', 'rule_num', 'rule_txt', 'rule_val', '_acct_view', 'biz_ok', 'biz_cost_ok',
                                    'rpt_cost_ok', 'rpt_access', '_is_ops', '_org_on123'])),
  fns as (
    select p.oid, p.proname::text as nm, pg_get_function_identity_arguments(p.oid) as args, p.pronargs,
           (p.proretset or p.prorettype = 'record'::regtype) as isset,
           (p.prosecdef and p.prorettype <> 'trigger'::regtype and has_function_privilege('authenticated', p.oid, 'execute')) as shown,
           lower(regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')) as src
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'),
  direct(oid) as (
    select f.oid from fns f
     where f.nm in (select n from prim)
        or exists (select 1 from prim x where f.src ~ ('(^|[^a-z0-9_])' || x.n || '\s*\('))
        or f.src ~ 'has_grant\(\s*[^,()]+,\s*(p_[a-z_]*(loc|place|site)[a-z_]*|[a-z]+\.(location_id|from_location_id|to_location_id|primary_location_id)|v_loc[a-z_]*|loc|new\.[a-z_]*location_id|old\.[a-z_]*location_id)\s*\)'
        or f.src ~ 'can_do\(\s*[^,()]+,\s*[^,()]+,\s*(p_[a-z_]*(loc|place|site)[a-z_]*|[a-z]+\.(location_id|from_location_id|to_location_id|primary_location_id)|v_loc[a-z_]*|loc|new\.[a-z_]*location_id|old\.[a-z_]*location_id)\s*\)'),
  edges as (
    select f.oid as caller, g.oid as callee
      from fns f cross join lateral (select distinct m[1] as n from regexp_matches(f.src, '([a-z_][a-z0-9_]*)\s*\(', 'g') m) x
      join fns g on g.nm = x.n and g.oid <> f.oid
     where x.n not in (select n from noprop) and (g.pronargs > 0 or g.isset)),
  aw(oid) as (select oid from direct union select e.caller from edges e join aw on aw.oid = e.callee)
  select f.nm, f.args,
         concat_ws('+', case when f.src ~ 'is_owner\(\)' then 'owner' end, case when f.src ~ '(has_grant|can_grant)\(' then 'grant' end, case when f.src ~ 'can_do\(' then 'can_do' end,
                   case when f.src ~ 'auth\.uid\(\)' then 'uid' end, case when f.src ~ 'is_active\(\)' then 'active' end),
         (select string_agg(t.tablename::text, ',' order by t.tablename) from pg_tables t where t.schemaname = 'public' and f.src ~ ('(^|[^a-z0-9_])' || t.tablename || '([^a-z0-9_(]|$)'))
    from fns f where f.shown and f.oid not in (select oid from aw) order by f.nm, f.args;
end $$;

-- ---------- 9. privileges ----------
do $pv$
declare r record;
begin
  -- internal helpers and the trigger function: closed to the browser
  for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('_caller_biz133', '_rule_group_only133', '_grant_eff133', '_can_grant_in133', '_form_eff133', '_patch133', '_gate133', '_xb133', '_rule_in133', '_cfgvis133') loop
    execute format('revoke all on function %s from public, anon, authenticated', r.sig);
  end loop;
  -- used inside the restrictive policies: the browser role needs EXECUTE, nobody else
  for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_unit_vis133', '_unit_mine133', '_role_vis133', '_grant_vis133', '_photo_scope133') loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
  -- the screens / owner tools
  for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('rule_val_in133', 'rules_effective133', 'rule_override_set133', 'rule_overrides_list133', 'rule_grant_override_set133', 'role_form_override_set133', 'role_matrix_list133',
                              'role_scope_set133', 'grant_scope_set133', 'photo_business133', 'photo_path133', 'photo_unmapped133', 'scope_gaps133', 'daily_digest_biz133') loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $pv$;

commit;
