-- ============================================================
-- Phase 122 (marker org122) - GROUP ERP, STAGE B1: the organization layer (ADDITIVE ONLY, ZERO behaviour change).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 10-11 (owner approved Stage A with changes and B1).
-- Canonical order: after phase121 (docs/PASTE_ORDER.md row 50). Needs only the base objects (no phase 72..121 function is touched or read).
-- Paste twice = no change, no error. Nothing existing is altered except ONE nullable column: locations.org_unit_id.
--   Tables (RLS on, no browser write, audit trigger, no hard delete)
--     business_templates  code, name, modules jsonb, status (available | configured | needs_setup | planned | not_implemented). Seeded; food_manufacturing = available
--                         (the sweets business), dealership / hardware_paint / technology / construction / online_store = not_implemented (a record only, no screens).
--     org_units           id, parent_id, kind (group | legal_entity | business | branch | site | department | cost_centre | project), code (unique), names, template_code,
--                         status (planned | active | inactive), effective_from / effective_to, currency, tz, attrs jsonb, audit columns. Never deleted.
--     legal_entities      org_unit_id, trade_licence_ref, tax_cfg jsonb, fiscal_start, base_currency, owner_pct (0..100, default 100). One row per legal_entity unit.
--     locations.org_unit_id  nullable. Seed: ONE group, ONE legal entity, ONE business for the existing sweets business; the existing locations are mapped to that
--                         business (fill-null-only, never overwrites, a later paste maps only locations that existed at the first paste).
--   Rule org_scope_on (switch, default OFF). NOTHING reads it yet: can_loc() and every existing function / report / policy are unchanged (that is Stage C1).
--   Functions
--     org_tree()                       read: owner or grant org_manage see every unit; anybody else only the units (and their parents) of locations they are assigned to.
--                                      Ownership %, tax config and licence number: owner only (licence also org_manage).
--     org_unit_scope(location_id)      read: location -> unit -> business -> legal entity -> group (same visibility rule).
--     org_unit_save(...)               create / update one unit (owner or grant org_manage). Create needs p_client (idempotent). Kind and code never change.
--     org_unit_deactivate(id, reason)  status inactive + effective_to; history stays; refused while active children or active locations hang under it.
--   Grant org_manage (grant_defs). Advisor row for org_scope_on (setup_rec_defs81, no value recommended).
--   No function of this file is called by any existing code.
-- Rollback: leave org_scope_on OFF (default). To remove: drop the four functions, the three tables and locations.org_unit_id (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.locations') is null or to_regclass('public.audit_log') is null or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null
     or to_regclass('public.user_locations') is null or to_regclass('public.setup_rec_defs81') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public.rule_on(text)') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase122 needs the base schema and phases up to 121 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. tables ----------
create table if not exists public.business_templates (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,40}$'),
  name_bn text not null, name_en text not null,
  modules jsonb not null default '[]'::jsonb check (jsonb_typeof(modules) = 'array'),
  status text not null default 'not_implemented' check (status in ('available', 'configured', 'needs_setup', 'planned', 'not_implemented')),
  sort int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.org_units (
  id bigserial primary key,
  parent_id bigint references public.org_units(id),
  kind text not null check (kind in ('group', 'legal_entity', 'business', 'branch', 'site', 'department', 'cost_centre', 'project')),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or length(name_en) <= 120),
  template_code text references public.business_templates(code),
  status text not null default 'active' check (status in ('planned', 'active', 'inactive')),
  effective_from date,
  effective_to date,
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  tz text not null default 'Asia/Dhaka',
  attrs jsonb not null default '{}'::jsonb check (jsonb_typeof(attrs) = 'object'),
  client_id uuid unique,
  deactivated_reason text, deactivated_by uuid, deactivated_at timestamptz,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  check (effective_to is null or effective_from is null or effective_to >= effective_from),
  check ((kind = 'group') = (parent_id is null)),
  check (template_code is null or kind = 'business')
);
create index if not exists org_units_parent122 on public.org_units (parent_id);
create unique index if not exists org_units_one_group122 on public.org_units (kind) where kind = 'group';

create table if not exists public.legal_entities (
  org_unit_id bigint primary key references public.org_units(id),
  trade_licence_ref text check (trade_licence_ref is null or length(trade_licence_ref) <= 80),
  tax_cfg jsonb not null default '{}'::jsonb check (jsonb_typeof(tax_cfg) = 'object'),
  fiscal_start date,
  base_currency text not null default 'BDT' check (base_currency ~ '^[A-Z]{3}$'),
  owner_pct numeric(7,4) not null default 100 check (owner_pct >= 0 and owner_pct <= 100),
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now()
);

alter table public.locations add column if not exists org_unit_id bigint references public.org_units(id);
create index if not exists locations_org_unit122 on public.locations (org_unit_id);

-- a legal_entities row may belong only to a unit of kind legal_entity
create or replace function public._le_kind_check122() returns trigger
language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.org_units u where u.id = new.org_unit_id and u.kind = 'legal_entity') then raise exception 'not_a_legal_entity'; end if;
  return new;
end $$;
drop trigger if exists le_kind_check122 on public.legal_entities;
create trigger le_kind_check122 before insert or update on public.legal_entities for each row execute function public._le_kind_check122();

-- never hard delete, history is audited
drop trigger if exists bt122_no_delete on public.business_templates;
create trigger bt122_no_delete before delete on public.business_templates for each row execute function public.no_hard_delete();
drop trigger if exists ou122_no_delete on public.org_units;
create trigger ou122_no_delete before delete on public.org_units for each row execute function public.no_hard_delete();
drop trigger if exists le122_no_delete on public.legal_entities;
create trigger le122_no_delete before delete on public.legal_entities for each row execute function public.no_hard_delete();
drop trigger if exists audit_bt122 on public.business_templates;
create trigger audit_bt122 after insert or update on public.business_templates for each row execute function public.log_change('code');
drop trigger if exists audit_ou122 on public.org_units;
create trigger audit_ou122 after insert or update on public.org_units for each row execute function public.log_change('id');
drop trigger if exists audit_le122 on public.legal_entities;
create trigger audit_le122 after insert or update on public.legal_entities for each row execute function public.log_change('org_unit_id');

-- RLS: no browser write at all; direct read only for the owner / org_manage (templates: any active user). Everything else goes through the functions.
alter table public.business_templates enable row level security;
alter table public.org_units enable row level security;
alter table public.legal_entities enable row level security;
drop policy if exists bt122_read on public.business_templates;
create policy bt122_read on public.business_templates for select to authenticated using (public.is_active());
drop policy if exists ou122_read on public.org_units;
create policy ou122_read on public.org_units for select to authenticated using (public.is_owner() or public.has_grant('org_manage'));
drop policy if exists le122_read on public.legal_entities;
create policy le122_read on public.legal_entities for select to authenticated using (public.is_owner());
revoke all on public.business_templates, public.org_units, public.legal_entities from public, anon, authenticated;
grant select on public.business_templates, public.org_units, public.legal_entities to authenticated;
revoke all on sequence public.org_units_id_seq from public, anon, authenticated;

-- ---------- 2. grant + rule + advisor row ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'org_manage', 'settings', 99, 'প্রতিষ্ঠানের কাঠামো (ব্যবসা, শাখা, সাইট) তৈরি ও বদলানো', 'Organization কাঠামো (business, branch, site) তৈরি ও বদলানো', 'Create and change the organization structure (businesses, branches, sites)', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'org_manage');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('org_scope_on', 'settings', 'switch', 'false', null, null, null, null,
  'ব্যবসা অনুযায়ী আলাদা ডেটা-সীমা (পরের ধাপে চালু হবে)', 'Business অনুযায়ী আলাদা data-scope (পরের ধাপে কাজ করবে)', 'Per-business data scope (takes effect in a later stage)',
  'এখন কিছুই বদলায় না। বন্ধ রাখুন। পরের ধাপে (C1) এটি অ্যাক্সেস-সীমা ব্যবসা অনুযায়ী করবে।',
  'এখন কিছুই বদলায় না। off রাখুন। পরের ধাপে (C1) এটি access-scope business অনুযায়ী করবে।',
  'Does nothing yet; keep it off. In Stage C1 it will make access scope follow the business. Nothing reads this switch in phase 122.', 990)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'org_scope_on', 'org_scope_on', '122', 'settings', null::jsonb, '{}'::text[],
  'এখন চালু করার দরকার নেই: এই ধাপে এটি কোনো কাজ করে না। বন্ধ থাকুক।',
  'এখন চালু করার দরকার নেই: এই ধাপে এটি কোনো কাজ করে না। off থাকুক।',
  'Leave it off: phase 122 only adds the organization tables; the switch is read by nothing until Stage C1.', 990
where not exists (select 1 from public.setup_rec_defs81 where code = 'org_scope_on');

-- ---------- 3. seed (templates, one group, one legal entity + business for sweets, location mapping) ----------
insert into public.business_templates (code, name_bn, name_en, modules, status, sort) values
 ('food_manufacturing', 'খাদ্য উৎপাদন ও খুচরা (মিষ্টি, বেকারি)', 'Food manufacturing and retail (sweets, bakery)',
  '["pos","stock","purchase","production","costing","accounting","reports"]'::jsonb, 'available', 10),
 ('dealership', 'ডিলারশিপ (যানবাহন)', 'Dealership', '[]'::jsonb, 'not_implemented', 20),
 ('hardware_paint', 'হার্ডওয়্যার ও রং', 'Hardware and paint', '[]'::jsonb, 'not_implemented', 30),
 ('technology', 'প্রযুক্তি', 'Technology', '[]'::jsonb, 'not_implemented', 40),
 ('construction', 'নির্মাণ', 'Construction', '[]'::jsonb, 'not_implemented', 50),
 ('online_store', 'অনলাইন স্টোর', 'Online store', '[]'::jsonb, 'not_implemented', 60)
on conflict (code) do nothing;

do $seed$
declare g bigint; le bigint; bz bigint; maxloc int; seeded boolean;
begin
  select id into g from public.org_units where kind = 'group' limit 1;
  if g is null then
    insert into public.org_units (kind, code, name_bn, name_en, status) values ('group', 'GROUP', 'গ্রুপ', 'Group', 'active') returning id into g;
  end if;
  select id into bz from public.org_units where code = 'SWEETS';
  seeded := bz is not null;
  if not seeded then
    insert into public.org_units (parent_id, kind, code, name_bn, name_en, status) values (g, 'legal_entity', 'LE-SWEETS', 'মিষ্টি ব্যবসা (প্রতিষ্ঠান)', 'Sweets business (legal entity)', 'active')
      on conflict (code) do nothing;
    select id into le from public.org_units where code = 'LE-SWEETS';
    insert into public.legal_entities (org_unit_id) values (le) on conflict (org_unit_id) do nothing;
    insert into public.org_units (parent_id, kind, code, name_bn, name_en, template_code, status, attrs)
      values (le, 'business', 'SWEETS', 'মিষ্টি ব্যবসা', 'Sweets business', 'food_manufacturing', 'active', '{}'::jsonb)
      on conflict (code) do nothing;
    select id into bz from public.org_units where code = 'SWEETS';
    select coalesce(max(id), 0) into maxloc from public.locations;
    update public.org_units set attrs = attrs || jsonb_build_object('seed122', jsonb_build_object('locations_up_to_id', maxloc)) where id = bz;
  end if;
  -- fill nulls only, never overwrite; only locations that existed when the sweets business was seeded
  select coalesce((attrs->'seed122'->>'locations_up_to_id')::int, 0) into maxloc from public.org_units where id = bz;
  update public.locations set org_unit_id = bz where org_unit_id is null and id <= maxloc;
end $seed$;

-- ---------- 4. functions ----------
-- may the caller manage the structure? (owner or a GLOBAL org_manage grant)
create or replace function public._org_mgr122() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('org_manage'));
$$;

-- which parent kinds a kind may sit under
create or replace function public._org_parent_ok122(p_kind text, p_parent_kind text) returns boolean
language sql immutable set search_path = public as $$
  select case p_kind
    when 'group' then false
    when 'legal_entity' then p_parent_kind = 'group'
    when 'business' then p_parent_kind = 'legal_entity'
    when 'branch' then p_parent_kind in ('business', 'branch')
    when 'site' then p_parent_kind in ('business', 'branch', 'site')
    when 'department' then p_parent_kind in ('business', 'branch', 'site', 'department')
    when 'cost_centre' then p_parent_kind in ('business', 'branch', 'site', 'department', 'cost_centre')
    when 'project' then p_parent_kind in ('business', 'branch', 'site')
    else false end;
$$;

-- units the caller may see: managers all; others the units (and their parents) of locations they are explicitly assigned to (NOT the management-role bypass of can_loc)
create or replace function public._org_visible122() returns setof bigint
language sql stable security definer set search_path = public as $$
  select u.id from public.org_units u where public._org_mgr122()
  union
  select a.id from (
    with recursive anc(id, parent_id) as (
      select u.id, u.parent_id from public.org_units u
       where public.is_active() and u.id in (select l.org_unit_id from public.locations l join public.user_locations ul on ul.location_id = l.id
                                              where ul.user_id = auth.uid() and l.org_unit_id is not null)
      union
      select p.id, p.parent_id from public.org_units p join anc on anc.parent_id = p.id)
    select id from anc) a;
$$;

-- the tree. Owner / org_manage: every unit. Others: only their own branch of the tree. Ownership %, tax config: owner only. Licence: owner or org_manage.
create or replace function public.org_tree() returns table (
  id bigint, parent_id bigint, kind text, code text, name_bn text, name_en text, template_code text, template_status text, status text,
  effective_from date, effective_to date, currency text, tz text, attrs jsonb, depth int, path text, location_ids int[],
  trade_licence_ref text, owner_pct numeric, tax_cfg jsonb, fiscal_start date, base_currency text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
  with recursive t(id, depth, path) as (
    select u.id, 0, u.code::text from public.org_units u where u.parent_id is null
    union all
    select c.id, t.depth + 1, t.path || '/' || c.code from public.org_units c join t on c.parent_id = t.id)
  select u.id, u.parent_id, u.kind, u.code, u.name_bn, u.name_en, u.template_code, bt.status, u.status,
         u.effective_from, u.effective_to, u.currency, u.tz,
         case when public._org_mgr122() then u.attrs else '{}'::jsonb end,
         t.depth, t.path,
         coalesce((select array_agg(l.id order by l.id) from public.locations l where l.org_unit_id = u.id
                    and (public._org_mgr122() or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = l.id))), '{}'::int[]),
         case when public._org_mgr122() then le.trade_licence_ref end,
         case when public.is_owner() then le.owner_pct end,
         case when public.is_owner() then le.tax_cfg end,
         case when public._org_mgr122() then le.fiscal_start end,
         le.base_currency
    from t join public.org_units u on u.id = t.id
    left join public.legal_entities le on le.org_unit_id = u.id
    left join public.business_templates bt on bt.code = u.template_code
   where u.id in (select * from public._org_visible122())
   order by t.path;
end $$;

-- location -> unit -> business -> legal entity -> group. Managers: any location. Others: only locations they are assigned to.
create or replace function public.org_unit_scope(p_location int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc public.locations; u bigint; r jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_location is null then raise exception 'bad_location'; end if;
  select * into loc from public.locations where id = p_location;
  if not found then raise exception 'bad_location'; end if;
  if not (public._org_mgr122() or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_location)) then raise exception 'not allowed'; end if;
  u := loc.org_unit_id;
  if u is null then return jsonb_build_object('location_id', p_location, 'org_unit_id', null, 'mapped', false); end if;
  with recursive up(id, parent_id, kind, code, lvl) as (
    select o.id, o.parent_id, o.kind, o.code, 0 from public.org_units o where o.id = u
    union all
    select p.id, p.parent_id, p.kind, p.code, up.lvl + 1 from public.org_units p join up on up.parent_id = p.id)
  select jsonb_build_object('location_id', p_location, 'mapped', true, 'org_unit_id', u,
    'business_id', (select id from up where kind = 'business' order by lvl limit 1),
    'business_code', (select code from up where kind = 'business' order by lvl limit 1),
    'legal_entity_id', (select id from up where kind = 'legal_entity' order by lvl limit 1),
    'legal_entity_code', (select code from up where kind = 'legal_entity' order by lvl limit 1),
    'group_id', (select id from up where kind = 'group' order by lvl limit 1),
    'path', (select jsonb_agg(code order by lvl desc) from up))
  into r;
  return r;
end $$;

-- create / update one unit. p_id null = create (needs p_client, repeat with the same key returns the same unit). Kind and code never change.
-- p_le (kind legal_entity only): {"trade_licence_ref","tax_cfg","fiscal_start","base_currency","owner_pct"}; owner_pct and tax_cfg need the owner.
create or replace function public.org_unit_save(p_id bigint, p_parent bigint, p_kind text, p_code text, p_name_bn text, p_name_en text default null,
  p_template text default null, p_status text default null, p_from date default null, p_to date default null, p_currency text default 'BDT',
  p_tz text default 'Asia/Dhaka', p_attrs jsonb default '{}'::jsonb, p_le jsonb default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Dhaka')::date;
  me uuid := auth.uid(); o public.org_units; par public.org_units; code_ text := upper(btrim(coalesce(p_code, '')));
  st text; cur text := upper(btrim(coalesce(p_currency, 'BDT'))); tz_ text := btrim(coalesce(p_tz, 'Asia/Dhaka'));
  attrs_ jsonb := coalesce(p_attrs, '{}'::jsonb); nid bigint; k text;
  lic text; taxc jsonb; fs date; bcur text; pct numeric;
begin
  if not public._org_mgr122() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into o from public.org_units where client_id = p_client;
    if found then
      if o.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', o.id, 'code', o.code);
    end if;
  end if;
  -- shared validation
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 120 then raise exception 'bad_name'; end if;
  if p_name_en is not null and length(p_name_en) > 120 then raise exception 'bad_name'; end if;
  if p_status is not null and p_status not in ('planned', 'active') then raise exception 'bad_status'; end if;
  if cur !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if not exists (select 1 from pg_timezone_names where name = tz_) then raise exception 'bad_tz'; end if;
  if jsonb_typeof(attrs_) is distinct from 'object' or length(attrs_::text) > 20000 then raise exception 'bad_attrs'; end if;
  if p_from is not null and p_from not between date '2000-01-01' and today + 3660 then raise exception 'bad_date'; end if;
  if p_to is not null and p_to not between date '2000-01-01' and today + 36600 then raise exception 'bad_date'; end if;
  if p_from is not null and p_to is not null and p_to < p_from then raise exception 'bad_date'; end if;
  if p_template is not null and not exists (select 1 from public.business_templates where code = p_template) then raise exception 'bad_template'; end if;

  if p_id is null then
    st := coalesce(p_status, 'active');
    if p_kind is null or p_kind not in ('legal_entity', 'business', 'branch', 'site', 'department', 'cost_centre', 'project') then raise exception 'bad_kind'; end if;
    if code_ !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.org_units where code = code_) then raise exception 'code_taken'; end if;
    select * into par from public.org_units where id = p_parent;
    if not found then raise exception 'bad_parent'; end if;
    if par.status = 'inactive' then raise exception 'parent_inactive'; end if;
    if not public._org_parent_ok122(p_kind, par.kind) then raise exception 'bad_parent_kind'; end if;
    if p_template is not null and p_kind <> 'business' then raise exception 'template_only_for_business'; end if;
  else
    select * into o from public.org_units where id = p_id for update;
    if not found then raise exception 'unit_not_found'; end if;
    if o.kind = 'group' and p_parent is not null then raise exception 'bad_parent'; end if;
    st := coalesce(p_status, o.status);   -- null keeps the current status (an inactive unit stays inactive; pass 'active' to reactivate)
    if o.status = 'inactive' and st <> 'inactive' and o.parent_id is not null and exists (select 1 from public.org_units x where x.id = o.parent_id and x.status = 'inactive') then raise exception 'parent_inactive'; end if;
    if p_kind is not null and p_kind <> o.kind then raise exception 'kind_fixed'; end if;
    if p_code is not null and code_ <> o.code then raise exception 'code_fixed'; end if;
    if p_template is not null and o.kind <> 'business' then raise exception 'template_only_for_business'; end if;
    if p_parent is distinct from o.parent_id and o.kind <> 'group' then
      select * into par from public.org_units where id = p_parent;
      if not found then raise exception 'bad_parent'; end if;
      if par.status = 'inactive' then raise exception 'parent_inactive'; end if;
      if not public._org_parent_ok122(o.kind, par.kind) then raise exception 'bad_parent_kind'; end if;
      if exists (with recursive d(id) as (select o.id union select c.id from public.org_units c join d on c.parent_id = d.id) select 1 from d where d.id = p_parent) then raise exception 'parent_cycle'; end if;
    end if;
  end if;

  -- legal entity details
  if p_le is not null then
    if jsonb_typeof(p_le) <> 'object' then raise exception 'bad_legal'; end if;
    if (case when p_id is null then p_kind else o.kind end) <> 'legal_entity' then raise exception 'legal_only_for_legal_entity'; end if;
    for k in select jsonb_object_keys(p_le) loop
      if k not in ('trade_licence_ref', 'tax_cfg', 'fiscal_start', 'base_currency', 'owner_pct') then raise exception 'bad_legal'; end if;
    end loop;
    if (p_le ? 'owner_pct' or p_le ? 'tax_cfg') and not public.is_owner() then raise exception 'owner_only'; end if;
    if p_le ? 'trade_licence_ref' then lic := nullif(btrim(p_le->>'trade_licence_ref'), ''); if lic is not null and length(lic) > 80 then raise exception 'bad_legal'; end if; end if;
    if p_le ? 'tax_cfg' then taxc := p_le->'tax_cfg'; if jsonb_typeof(taxc) is distinct from 'object' or length(taxc::text) > 20000 then raise exception 'bad_legal'; end if; end if;
    if p_le ? 'fiscal_start' then fs := nullif(p_le->>'fiscal_start', '')::date; end if;
    if p_le ? 'base_currency' then bcur := upper(btrim(p_le->>'base_currency')); if bcur !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if; end if;
    if p_le ? 'owner_pct' then pct := (p_le->>'owner_pct')::numeric; if pct is null or pct <> pct or pct < 0 or pct > 100 then raise exception 'bad_owner_pct'; end if; end if;
  end if;

  if p_id is null then
    insert into public.org_units (parent_id, kind, code, name_bn, name_en, template_code, status, effective_from, effective_to, currency, tz, attrs, client_id, created_by, updated_by)
    values (p_parent, p_kind, code_, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_template, st, p_from, p_to, cur, tz_, attrs_, p_client, me, me)
    returning id into nid;
    if p_kind = 'legal_entity' then
      insert into public.legal_entities (org_unit_id, trade_licence_ref, tax_cfg, fiscal_start, base_currency, owner_pct, created_by, updated_by)
      values (nid, lic, coalesce(taxc, '{}'::jsonb), fs, coalesce(bcur, cur), coalesce(pct, 100), me, me);
    end if;
    return jsonb_build_object('dup', false, 'id', nid, 'code', code_);
  end if;

  update public.org_units set parent_id = case when kind = 'group' then null else p_parent end, name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''),
    template_code = case when kind = 'business' then p_template else null end, status = st, effective_from = p_from, effective_to = p_to, currency = cur, tz = tz_, attrs = attrs_,
    deactivated_reason = case when st <> 'inactive' then null else deactivated_reason end,
    updated_by = me, updated_at = now()
   where id = p_id;
  if o.kind = 'legal_entity' and p_le is not null then
    update public.legal_entities set trade_licence_ref = case when p_le ? 'trade_licence_ref' then lic else trade_licence_ref end,
      tax_cfg = case when p_le ? 'tax_cfg' then taxc else tax_cfg end, fiscal_start = case when p_le ? 'fiscal_start' then fs else fiscal_start end,
      base_currency = coalesce(bcur, base_currency), owner_pct = coalesce(pct, owner_pct), updated_by = me, updated_at = now()
     where org_unit_id = p_id;
  end if;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', o.code);
end $$;

-- deactivate: status inactive + effective_to; history stays. Refused while active child units or active locations hang under it. Repeating it is a no-op.
create or replace function public.org_unit_deactivate(p_id bigint, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.org_units; today date := (now() at time zone 'Asia/Dhaka')::date;
begin
  if not public._org_mgr122() then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 500 then raise exception 'bad_reason'; end if;
  perform public._client_lock(p_client);
  select * into o from public.org_units where id = p_id for update;
  if not found then raise exception 'unit_not_found'; end if;
  if o.status = 'inactive' then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if exists (select 1 from public.org_units c where c.parent_id = o.id and c.status <> 'inactive') then raise exception 'has_active_children'; end if;
  if exists (select 1 from public.locations l where l.org_unit_id = o.id and l.is_active) then raise exception 'has_active_locations'; end if;
  update public.org_units set status = 'inactive', effective_to = case when effective_to is null or effective_to > today then today else effective_to end,
    deactivated_reason = nullif(btrim(coalesce(p_reason, '')), ''), deactivated_by = auth.uid(), deactivated_at = now(), updated_by = auth.uid(), updated_at = now()
   where id = o.id;
  return jsonb_build_object('dup', false, 'id', o.id);
end $$;

-- ---------- 5. privileges: helpers closed, browser functions for signed-in users only ----------
revoke all on function public._org_mgr122(), public._org_parent_ok122(text, text), public._org_visible122(), public._le_kind_check122() from public, anon, authenticated;
revoke all on function public.org_tree(), public.org_unit_scope(int),
  public.org_unit_save(bigint, bigint, text, text, text, text, text, text, date, date, text, text, jsonb, jsonb, uuid),
  public.org_unit_deactivate(bigint, text, uuid) from public, anon;
grant execute on function public.org_tree(), public.org_unit_scope(int),
  public.org_unit_save(bigint, bigint, text, text, text, text, text, text, date, date, text, text, jsonb, jsonb, uuid),
  public.org_unit_deactivate(bigint, text, uuid) to authenticated;

commit;
