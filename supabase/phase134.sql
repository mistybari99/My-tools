-- ============================================================
-- Phase 134 (marker prof134) - GROUP ERP, STAGE D: one PROFILE per business, and the upper layers are INVISIBLE to the people of a business.
-- Owner requirement: the top owner/group is named 'MD-AL AMIN'. Every business has its OWN profile (name, logo, address, receipt text, colour). Entering the sweets business shows
-- 'ইসলামিয়া মিষ্টি ঘর / ISLAMIYA MISTY GHAR'; entering another business shows that business. A person who is given access to a business sees ONLY that business: not the group name,
-- not the legal entity above it, not another business, not a sibling, not the tree above it, not a count or total of the group. Only the owner sees the group layer and the master view.
-- Canonical order: after phase133 (docs/PASTE_ORDER.md row 61). Paste twice = no change, no error. Needs phases 122, 123, 132, 133 (checked below).
--
--   1  business_profiles   one row per business unit (org_unit_id unique): display_name_bn / en, short_name, logo_path, address, phone, email, receipt_header, receipt_footer,
--                          theme_color, trade_licence_ref (owner / the manager of THAT business only; the column is not granted to the browser), audit trigger, RLS (the owner,
--                          or the people of that business), no browser write. Writes: business_profile_save (owner, or the holder of org_manage inside that business; p_client key
--                          kept in business_profile_ops134), reads: business_profile_get / business_profile_list134.
--      Seed (idempotent, never overwrites): a profile for every business (the sweets business gets the brand the app has always shown: 'ইসলামিয়া মিষ্টি ঘর' / 'ISLAMIYA MISTY GHAR';
--      any other business gets its unit name); a new business unit gets its profile through a trigger. The group unit is renamed to 'MD-AL AMIN' ONLY while it still holds the
--      phase122 placeholder ('গ্রুপ' / 'Group') and only once (attrs.seed134), so a name the owner chose is never touched.
--   2  UPPER-LAYER BLINDNESS (server side, switch ON and OFF alike, owner view unchanged). For a caller who is not the owner:
--        org_tree()          only the caller's own business subtree, the business is the ROOT (parent_id null, depth 0), no group / legal entity / sibling row, the business row carries
--                            the profile name, no owner %, no tax config; the legal entity's base currency is copied onto the business row so the import-export helper keeps working
--        org_unit_scope()    no legal entity id / code, no group id, the path starts at the business
--        org_scope_list()    only own scopes (a manager of a business: the scopes inside that business); a unit above the business is shown as null
--        org_unit_save / org_unit_deactivate   a holder of org_manage can only touch plain units INSIDE his own business (the codes are namespaced by the business code, a foreign
--                            or missing unit answers 'unit_not_found' / 'bad_parent' alike), never a legal entity / business / group
--        master_share_list(), master_scope_report132()   owner only (they name or count several businesses)
--        policies on org_units, user_org_scopes, master_shares132 follow the same rule (a manager sees the units inside his business, nothing above)
--        master_context_set132 / daily_digest_biz133 / rule_val_in133   a foreign business id answers 'not allowed' exactly like a missing one (no existence oracle)
--      The helper _vis_biz134() is the one definition of "the businesses this caller may know": owner = every business, others = their own business(es) (and, while org_scope_on is
--      OFF and there is a single business, that one business: everybody works in it). Nothing of phases 72..133 is changed except the functions named above.
-- Rollback: nothing else reads the new objects except the functions re-created here; to go back re-paste phase122 (org_tree, org_unit_scope, org_unit_save, org_unit_deactivate,
--   _org_visible122), phase123 (org_scope_list), phase132 (master_share_list, master_scope_report132, master_context_set132) and phase124 (_ie_base124), re-apply the policies of those
--   phases, drop the trigger / table / functions of this file. The group rename is a normal update (the old name is in audit_log).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.org_units') is null or to_regclass('public.legal_entities') is null or to_regclass('public.user_org_scopes') is null or to_regclass('public.master_shares132') is null
     or to_regclass('public.locations') is null or to_regclass('public.user_locations') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public._user_biz123(uuid)') is null or to_regprocedure('public._business_of_unit123(bigint)') is null or to_regprocedure('public._org_on123()') is null
     or to_regprocedure('public._org_anc123(bigint)') is null or to_regprocedure('public._patch133(regprocedure,text,text[])') is null or to_regprocedure('public._caller_biz133()') is null
     or to_regprocedure('public.master_context_set132(bigint)') is null or to_regprocedure('public.master_scope_report132()') is null or to_regprocedure('public.daily_digest_biz133(bigint,date)') is null
     or to_regprocedure('public.rule_val_in133(text,bigint)') is null or to_regprocedure('public._ie_base124(bigint)') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public._client_lock(uuid)') is null or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase134 needs the base schema and phases up to 133 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. the profile table ----------
create table if not exists public.business_profiles (
  id bigserial primary key,
  org_unit_id bigint not null unique references public.org_units(id),
  display_name_bn text not null check (length(btrim(display_name_bn)) between 1 and 120),
  display_name_en text check (display_name_en is null or length(btrim(display_name_en)) between 1 and 120),
  short_name text check (short_name is null or length(btrim(short_name)) between 1 and 40),
  logo_path text check (logo_path is null or (length(logo_path) <= 300 and logo_path ~ '^[A-Za-z0-9_][A-Za-z0-9_./ -]*$' and logo_path !~ '\.\.')),
  address text check (address is null or length(address) <= 300),
  phone text check (phone is null or length(phone) between 3 and 40),
  email text check (email is null or (length(email) <= 120 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  receipt_header text check (receipt_header is null or length(receipt_header) <= 300),
  receipt_footer text check (receipt_footer is null or length(receipt_footer) <= 300),
  theme_color text check (theme_color is null or theme_color ~ '^#[0-9A-Fa-f]{6}$'),
  trade_licence_ref text check (trade_licence_ref is null or length(trade_licence_ref) <= 80),
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now()
);

-- idempotency keys of business_profile_save (not readable by the browser)
create table if not exists public.business_profile_ops134 (
  client_id uuid primary key,
  org_unit_id bigint not null references public.org_units(id),
  by_user uuid, at timestamptz not null default now()
);

-- a profile belongs to a unit of kind business
create or replace function public._bp_kind_check134() returns trigger
language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.org_units u where u.id = new.org_unit_id and u.kind = 'business') then raise exception 'not_a_business'; end if;
  return new;
end $$;
drop trigger if exists bp_kind_check134 on public.business_profiles;
create trigger bp_kind_check134 before insert or update on public.business_profiles for each row execute function public._bp_kind_check134();
drop trigger if exists bp134_no_delete on public.business_profiles;
create trigger bp134_no_delete before delete on public.business_profiles for each row execute function public.no_hard_delete();
drop trigger if exists bpo134_no_delete on public.business_profile_ops134;
create trigger bpo134_no_delete before delete on public.business_profile_ops134 for each row execute function public.no_hard_delete();
drop trigger if exists audit_bp134 on public.business_profiles;
create trigger audit_bp134 after insert or update on public.business_profiles for each row execute function public.log_change('id');

-- ---------- 2. who may know / manage which business (ONE definition) ----------
-- the owner: the group owner (active)
create or replace function public._grp_owner134() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and public.is_owner();
$$;

-- the businesses this caller may know. Owner: all. Others: their own (scope / assigned place); while org_scope_on is OFF and there is exactly one live business, that one business
-- (everybody works in it, so it is "their" business; this keeps the brand of the original business on every screen).
create or replace function public._vis_biz134() returns setof bigint
language sql stable security definer set search_path = public as $$
  select b.id from public.org_units b where b.kind = 'business' and public.is_active() and public.is_owner()
  union
  select x from public._user_biz123(auth.uid()) x where public.is_active()
  union
  select b.id from public.org_units b
   where b.kind = 'business' and b.status <> 'inactive' and public.is_active() and not public._org_on123()
     and (select count(*) from public.org_units z where z.kind = 'business' and z.status <> 'inactive') = 1;
$$;

-- may the caller manage this business (profile, structure inside it)? Owner: always. Others: only a business of theirs AND the grant org_manage (global, or at a place of that business)
create or replace function public._biz_mgr134(p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_biz is not null and (public.is_owner() or (
    p_biz in (select public._vis_biz134())
    and (public.has_grant('org_manage') or exists (select 1 from public.locations l where l.org_unit_id is not null and public._business_of_unit123(l.org_unit_id) = p_biz and public.has_grant('org_manage', l.id)))));
$$;

-- the same for a unit: the business above it (or the unit itself). A unit above the business level is never managed by a non-owner.
create or replace function public._unit_mgr134(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_unit is not null and (public.is_owner() or public._biz_mgr134(public._business_of_unit123(p_unit)));
$$;

-- may the caller know this unit at all (owner: yes; others: only units inside a business of theirs)
create or replace function public._unit_vis134(p_unit bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_unit is not null and (public.is_owner() or public._business_of_unit123(p_unit) in (select public._vis_biz134()));
$$;

-- the business the caller is working in when none is named: his working / single business, else the first one he may know
create or replace function public._cur_biz134() returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce((select b from (select public._caller_biz133() b) q where q.b in (select public._vis_biz134())), (select min(x) from public._vis_biz134() x));
$$;

-- ---------- 3. RLS + privileges of the new tables, then the profile functions ----------
alter table public.business_profiles enable row level security;
alter table public.business_profile_ops134 enable row level security;
drop policy if exists bp134_read on public.business_profiles;
create policy bp134_read on public.business_profiles for select to authenticated using (public.is_active() and (public.is_owner() or org_unit_id in (select public._vis_biz134())));
revoke all on public.business_profiles, public.business_profile_ops134 from public, anon, authenticated;
-- every column except the licence reference (read through business_profile_get: owner / manager of that business only)
grant select (id, org_unit_id, display_name_bn, display_name_en, short_name, logo_path, address, phone, email, receipt_header, receipt_footer, theme_color, created_at, updated_at)
  on public.business_profiles to authenticated;
revoke all on sequence public.business_profiles_id_seq from public, anon, authenticated;

-- one profile row as jsonb (licence only when asked for)
create or replace function public._bp_json134(p_biz bigint, p_lic boolean) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('business_id', u.id, 'code', u.code, 'template_code', u.template_code, 'status', u.status,
           'display_name_bn', coalesce(bp.display_name_bn, u.name_bn), 'display_name_en', coalesce(bp.display_name_en, case when bp.id is null then u.name_en end),
           'short_name', bp.short_name, 'logo_path', bp.logo_path, 'address', bp.address, 'phone', bp.phone, 'email', bp.email,
           'receipt_header', bp.receipt_header, 'receipt_footer', bp.receipt_footer, 'theme_color', bp.theme_color,
           'trade_licence_ref', case when p_lic then bp.trade_licence_ref end, 'saved', bp.id is not null, 'updated_at', bp.updated_at)
    from public.org_units u left join public.business_profiles bp on bp.org_unit_id = u.id where u.id = p_biz and u.kind = 'business';
$$;

-- the profile of ONE business: p_biz null = the caller's working business. A business the caller may not know answers 'not allowed' exactly like a missing one.
create or replace function public.business_profile_get(p_biz bigint default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b bigint; r jsonb; mgr boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  b := coalesce(p_biz, public._cur_biz134());
  if b is null or not (public.is_owner() or b in (select public._vis_biz134())) then raise exception 'not allowed'; end if;
  mgr := public._biz_mgr134(b);
  r := public._bp_json134(b, mgr);
  if r is null then raise exception 'not allowed'; end if;
  return r || jsonb_build_object('can_edit', mgr);
end $$;

-- the profiles the caller may know (owner: every active business; others: their own) - for the business switcher and the brand of a document
create or replace function public.business_profile_list134() returns table (org_unit_id bigint, code text, status text, display_name_bn text, display_name_en text, short_name text,
  logo_path text, address text, phone text, email text, receipt_header text, receipt_footer text, theme_color text, can_edit boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select u.id, u.code, u.status, coalesce(bp.display_name_bn, u.name_bn), coalesce(bp.display_name_en, case when bp.id is null then u.name_en end), bp.short_name, bp.logo_path, bp.address, bp.phone,
           bp.email, bp.receipt_header, bp.receipt_footer, bp.theme_color, public._biz_mgr134(u.id)
      from public.org_units u left join public.business_profiles bp on bp.org_unit_id = u.id
     where u.kind = 'business' and u.status <> 'inactive' and (public.is_owner() or u.id in (select public._vis_biz134())) order by u.id;
end $$;

-- create / change the profile of one business. p_patch = {"display_name_bn", "display_name_en", "short_name", "logo_path", "address", "phone", "email", "receipt_header", "receipt_footer",
-- "theme_color", "trade_licence_ref"}: only the keys present change ('' or null clears an optional text). Owner, or the holder of org_manage inside that business. p_client is required;
-- the same key again returns the first answer without a second write.
create or replace function public.business_profile_save(p_biz bigint, p_patch jsonb, p_client uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); op public.business_profile_ops134; bp public.business_profiles; k text; v text; u public.org_units;
        nbn text; nen text; sn text; lg text; ad text; ph text; em text; rh text; rf text; tc text; lic text; nid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_client is null then raise exception 'client_id_needed'; end if;
  perform public._client_lock(p_client);
  select * into op from public.business_profile_ops134 where client_id = p_client;
  if found then
    if op.by_user is distinct from me then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('dup', true, 'business_id', op.org_unit_id);
  end if;
  if p_biz is null or not public._biz_mgr134(p_biz) then raise exception 'not allowed'; end if;
  select * into u from public.org_units where id = p_biz and kind = 'business';
  if not found then raise exception 'not allowed'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or length(p_patch::text) > 5000 then raise exception 'bad_profile'; end if;
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('display_name_bn', 'display_name_en', 'short_name', 'logo_path', 'address', 'phone', 'email', 'receipt_header', 'receipt_footer', 'theme_color', 'trade_licence_ref') then raise exception 'bad_profile'; end if;
    if jsonb_typeof(p_patch -> k) not in ('string', 'null') then raise exception 'bad_profile'; end if;
  end loop;
  select * into bp from public.business_profiles where org_unit_id = p_biz for update;
  -- start from the stored row (or the unit names for a first save), then apply the keys that were sent
  nbn := coalesce(bp.display_name_bn, u.name_bn); nen := case when bp.id is null then u.name_en else bp.display_name_en end; sn := bp.short_name; lg := bp.logo_path; ad := bp.address; ph := bp.phone;
  em := bp.email; rh := bp.receipt_header; rf := bp.receipt_footer; tc := bp.theme_color; lic := bp.trade_licence_ref;
  if p_patch ? 'display_name_bn' then nbn := nullif(btrim(coalesce(p_patch ->> 'display_name_bn', '')), ''); if nbn is null or length(nbn) > 120 then raise exception 'bad_name'; end if; end if;
  if p_patch ? 'display_name_en' then nen := nullif(btrim(coalesce(p_patch ->> 'display_name_en', '')), ''); if nen is not null and length(nen) > 120 then raise exception 'bad_name'; end if; end if;
  if p_patch ? 'short_name' then sn := nullif(btrim(coalesce(p_patch ->> 'short_name', '')), ''); if sn is not null and length(sn) > 40 then raise exception 'bad_short_name'; end if; end if;
  if p_patch ? 'logo_path' then lg := nullif(btrim(coalesce(p_patch ->> 'logo_path', '')), '');
    if lg is not null and (length(lg) > 300 or lg !~ '^[A-Za-z0-9_][A-Za-z0-9_./ -]*$' or lg ~ '\.\.') then raise exception 'bad_logo'; end if; end if;
  if p_patch ? 'address' then ad := nullif(btrim(coalesce(p_patch ->> 'address', '')), ''); if ad is not null and length(ad) > 300 then raise exception 'bad_address'; end if; end if;
  if p_patch ? 'phone' then ph := nullif(btrim(coalesce(p_patch ->> 'phone', '')), ''); if ph is not null and (length(ph) not between 3 and 40 or ph !~ '^[0-9০-৯+() -]+$') then raise exception 'bad_phone'; end if; end if;
  if p_patch ? 'email' then em := nullif(btrim(coalesce(p_patch ->> 'email', '')), ''); if em is not null and (length(em) > 120 or em !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') then raise exception 'bad_email'; end if; end if;
  if p_patch ? 'receipt_header' then rh := nullif(btrim(coalesce(p_patch ->> 'receipt_header', '')), ''); if rh is not null and length(rh) > 300 then raise exception 'bad_receipt_text'; end if; end if;
  if p_patch ? 'receipt_footer' then rf := nullif(btrim(coalesce(p_patch ->> 'receipt_footer', '')), ''); if rf is not null and length(rf) > 300 then raise exception 'bad_receipt_text'; end if; end if;
  if p_patch ? 'theme_color' then tc := nullif(btrim(coalesce(p_patch ->> 'theme_color', '')), ''); if tc is not null and tc !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'bad_color'; end if; end if;
  if p_patch ? 'trade_licence_ref' then lic := nullif(btrim(coalesce(p_patch ->> 'trade_licence_ref', '')), ''); if lic is not null and length(lic) > 80 then raise exception 'bad_licence'; end if; end if;
  if nbn is null then raise exception 'bad_name'; end if;
  if bp.id is null then
    insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en, short_name, logo_path, address, phone, email, receipt_header, receipt_footer, theme_color, trade_licence_ref, created_by, updated_by)
    values (p_biz, nbn, nen, sn, lg, ad, ph, em, rh, rf, tc, lic, me, me) returning id into nid;
  else
    update public.business_profiles set display_name_bn = nbn, display_name_en = nen, short_name = sn, logo_path = lg, address = ad, phone = ph, email = em, receipt_header = rh, receipt_footer = rf,
      theme_color = tc, trade_licence_ref = lic, updated_by = me, updated_at = now() where id = bp.id;
    nid := bp.id;
  end if;
  insert into public.business_profile_ops134 (client_id, org_unit_id, by_user) values (p_client, p_biz, me);
  return jsonb_build_object('dup', false, 'id', nid, 'business_id', p_biz);
end $$;

-- a new business unit gets its profile (the unit names) at once; the owner or its manager edit it afterwards
create or replace function public._bp_seed134() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'business' then
    insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en, created_by, updated_by)
    values (new.id, new.name_bn, new.name_en, new.created_by, new.created_by) on conflict (org_unit_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists bp_seed134 on public.org_units;
create trigger bp_seed134 after insert on public.org_units for each row execute function public._bp_seed134();

-- ---------- 4. seed: profiles of the existing businesses, and the group name ----------
insert into public.business_profiles (org_unit_id, display_name_bn, display_name_en)
select u.id,
       case when u.code = 'SWEETS' and u.name_bn = 'মিষ্টি ব্যবসা' and coalesce(u.name_en, 'sweets business') ilike 'sweets business' then 'ইসলামিয়া মিষ্টি ঘর' else u.name_bn end,
       case when u.code = 'SWEETS' and u.name_bn = 'মিষ্টি ব্যবসা' and coalesce(u.name_en, 'sweets business') ilike 'sweets business' then 'ISLAMIYA MISTY GHAR' else u.name_en end
  from public.org_units u where u.kind = 'business'
on conflict (org_unit_id) do nothing;

-- the top owner / group is named 'MD-AL AMIN': only while the unit still holds the phase122 placeholder, and only once
do $seed$
begin
  update public.org_units g set name_bn = 'MD-AL AMIN', name_en = 'MD-AL AMIN',
         attrs = g.attrs || jsonb_build_object('seed134', jsonb_build_object('group_named', true)), updated_at = now()
   where g.kind = 'group' and g.name_bn = 'গ্রুপ' and g.name_en = 'Group' and coalesce((g.attrs -> 'seed134' ->> 'group_named')::boolean, false) = false;
  -- a group the owner has already named: remember that the seed has nothing to do (a later rename back to the placeholder is then the owner's choice)
  update public.org_units g set attrs = g.attrs || jsonb_build_object('seed134', jsonb_build_object('group_named', true))
   where g.kind = 'group' and coalesce((g.attrs -> 'seed134' ->> 'group_named')::boolean, false) = false;
end $seed$;

-- ---------- 5. upper-layer blindness: the tree, the scope, the lists ----------
-- units the caller may see in the tree: the owner everything; a manager of a business the units inside it; everybody else the units that hold one of his assigned places (and their parents inside the business)
create or replace function public._org_visible122() returns setof bigint
language sql stable security definer set search_path = public as $$
  select u.id from public.org_units u where public.is_active() and public.is_owner()
  union
  select u.id from public.org_units u where public.is_active() and u.kind not in ('group', 'legal_entity') and public._unit_mgr134(u.id)
  union
  select u.id from public.org_units u where public.is_active() and u.kind not in ('group', 'legal_entity') and public._unit_vis134(u.id) and public.can_scope(u.id)   -- a live role scope (for example management) over the unit
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

-- the tree. Owner: every unit (unchanged). Everybody else: ONLY the subtree of his own business, the business is the root (parent_id null, depth 0, path starts at the business code);
-- the business row carries the profile name; no group, no legal entity, no sibling, no owner %, no tax config.
create or replace function public.org_tree() returns table (
  id bigint, parent_id bigint, kind text, code text, name_bn text, name_en text, template_code text, template_status text, status text,
  effective_from date, effective_to date, currency text, tz text, attrs jsonb, depth int, path text, location_ids int[],
  trade_licence_ref text, owner_pct numeric, tax_cfg jsonb, fiscal_start date, base_currency text)
language plpgsql stable security definer set search_path = public as $$
declare own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  return query
  with recursive t(id, depth, path) as (
    select u.id, 0, u.code::text from public.org_units u
     where case when own_ then u.parent_id is null else (u.kind = 'business' and u.id in (select public._vis_biz134())) end
    union all
    select c.id, t.depth + 1, t.path || '/' || c.code from public.org_units c join t on c.parent_id = t.id)
  select u.id,
         case when own_ then u.parent_id when u.kind = 'business' then null else u.parent_id end,
         u.kind, u.code,
         case when own_ or u.kind <> 'business' or bp.display_name_bn is null then u.name_bn else bp.display_name_bn end,
         case when own_ or u.kind <> 'business' or bp.display_name_bn is null then u.name_en else bp.display_name_en end,
         u.template_code, bt.status, u.status,
         u.effective_from, u.effective_to, u.currency, u.tz,
         case when public._unit_mgr134(u.id) then u.attrs else '{}'::jsonb end,
         t.depth, t.path,
         coalesce((select array_agg(l.id order by l.id) from public.locations l where l.org_unit_id = u.id
                    and (public._unit_mgr134(u.id) or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = l.id))), '{}'::int[]),
         case when own_ then le.trade_licence_ref when u.kind = 'business' and public._unit_mgr134(u.id) then bp.trade_licence_ref end,
         case when own_ then le.owner_pct end,
         case when own_ then le.tax_cfg end,
         case when own_ then le.fiscal_start end,
         case when own_ or u.kind <> 'business' then le.base_currency
              else (select le2.base_currency from public.legal_entities le2 where le2.org_unit_id in (select public._org_anc123(u.id)) limit 1) end
    from t join public.org_units u on u.id = t.id
    left join public.legal_entities le on le.org_unit_id = u.id
    left join public.business_templates bt on bt.code = u.template_code
    left join public.business_profiles bp on bp.org_unit_id = u.id
   where u.id in (select * from public._org_visible122())
   order by t.path;
end $$;

-- location -> unit -> business (-> legal entity -> group for the OWNER). Others: only their own places, and the answer stops at the business.
create or replace function public.org_unit_scope(p_location int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc public.locations; u bigint; r jsonb; own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_location is null then raise exception 'bad_location'; end if;
  own_ := public.is_owner();
  select * into loc from public.locations where id = p_location;
  if not found then raise exception '%', case when own_ then 'bad_location' else 'not allowed' end; end if;   -- a missing place looks like a foreign one
  if not (own_ or (loc.org_unit_id is not null and public._unit_mgr134(loc.org_unit_id))
                or exists (select 1 from public.user_locations ul where ul.user_id = auth.uid() and ul.location_id = p_location)) then raise exception 'not allowed'; end if;
  u := loc.org_unit_id;
  if u is null then return jsonb_build_object('location_id', p_location, 'org_unit_id', null, 'mapped', false); end if;
  with recursive up(id, parent_id, kind, code, lvl) as (
    select o.id, o.parent_id, o.kind, o.code, 0 from public.org_units o where o.id = u
    union all
    select p.id, p.parent_id, p.kind, p.code, up.lvl + 1 from public.org_units p join up on up.parent_id = p.id)
  select jsonb_build_object('location_id', p_location, 'mapped', true, 'org_unit_id', u,
    'business_id', (select id from up where kind = 'business' order by lvl limit 1),
    'business_code', (select code from up where kind = 'business' order by lvl limit 1),
    'legal_entity_id', case when own_ then (select id from up where kind = 'legal_entity' order by lvl limit 1) end,
    'legal_entity_code', case when own_ then (select code from up where kind = 'legal_entity' order by lvl limit 1) end,
    'group_id', case when own_ then (select id from up where kind = 'group' order by lvl limit 1) end,
    'path', (select jsonb_agg(code order by lvl desc) from up where own_ or lvl <= coalesce((select min(lvl) from up where kind = 'business'), -1)))
  into r;
  return r;
end $$;

-- create / update one unit. (phase122 body; the new first block binds a non-owner to the inside of his own business)
create or replace function public.org_unit_save(p_id bigint, p_parent bigint, p_kind text, p_code text, p_name_bn text, p_name_en text default null,
  p_template text default null, p_status text default null, p_from date default null, p_to date default null, p_currency text default 'BDT',
  p_tz text default 'Asia/Dhaka', p_attrs jsonb default '{}'::jsonb, p_le jsonb default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Dhaka')::date;
  me uuid := auth.uid(); o public.org_units; par public.org_units; code_ text := upper(btrim(coalesce(p_code, '')));
  st text; cur text := upper(btrim(coalesce(p_currency, 'BDT'))); tz_ text := btrim(coalesce(p_tz, 'Asia/Dhaka'));
  attrs_ jsonb := coalesce(p_attrs, '{}'::jsonb); nid bigint; k text;
  lic text; taxc jsonb; fs date; bcur text; pct numeric; own_ boolean; bzcode text;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  if not (own_ or public.has_grant('org_manage')) then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if not own_ then
    -- a manager bound to his own business: only plain units INSIDE that business (never a legal entity, a business or the group), the code is namespaced by the business code,
    -- a unit outside the business answers exactly like a missing one
    if p_le is not null then raise exception 'not allowed'; end if;
    if p_id is null then
      if p_kind is null or p_kind not in ('branch', 'site', 'department', 'cost_centre', 'project') then raise exception 'not allowed'; end if;
      if p_parent is null or not public._unit_mgr134(p_parent) then raise exception 'bad_parent'; end if;
      select b.code into bzcode from public.org_units b where b.id = public._business_of_unit123(p_parent);
      code_ := case when code_ like bzcode || '-%' then code_ else bzcode || '-' || code_ end;
    else
      if not public._unit_mgr134(p_id) then raise exception 'unit_not_found'; end if;
      if (select x.kind from public.org_units x where x.id = p_id) in ('group', 'legal_entity', 'business') then raise exception 'not allowed'; end if;
      if p_parent is not null and not public._unit_mgr134(p_parent) then raise exception 'bad_parent'; end if;
    end if;
  end if;
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

-- deactivate: as phase122; a non-owner only a plain unit inside his own business
create or replace function public.org_unit_deactivate(p_id bigint, p_reason text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.org_units; today date := (now() at time zone 'Asia/Dhaka')::date; own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  if not (own_ or public.has_grant('org_manage')) then raise exception 'not allowed'; end if;
  if p_reason is not null and length(p_reason) > 500 then raise exception 'bad_reason'; end if;
  perform public._client_lock(p_client);
  if not own_ and not public._unit_mgr134(p_id) then raise exception 'unit_not_found'; end if;
  select * into o from public.org_units where id = p_id for update;
  if not found then raise exception 'unit_not_found'; end if;
  if not own_ and o.kind in ('group', 'legal_entity', 'business') then raise exception 'not allowed'; end if;
  if o.status = 'inactive' then return jsonb_build_object('dup', true, 'id', o.id); end if;
  if exists (select 1 from public.org_units c where c.parent_id = o.id and c.status <> 'inactive') then raise exception 'has_active_children'; end if;
  if exists (select 1 from public.locations l where l.org_unit_id = o.id and l.is_active) then raise exception 'has_active_locations'; end if;
  update public.org_units set status = 'inactive', effective_to = case when effective_to is null or effective_to > today then today else effective_to end,
    deactivated_reason = nullif(btrim(coalesce(p_reason, '')), ''), deactivated_by = auth.uid(), deactivated_at = now(), updated_by = auth.uid(), updated_at = now()
   where id = o.id;
  return jsonb_build_object('dup', false, 'id', o.id);
end $$;

-- scopes: the owner all; a manager of a business the scopes inside it; everybody else his own. A unit above the business level is never named to a non-owner.
create or replace function public.org_scope_list(p_user uuid default null) returns table (id bigint, user_id uuid, staff_id text, full_name text, org_unit_id bigint, unit_code text, role_code text,
  status text, live boolean, note text, granted_at timestamptz, revoked_at timestamptz, revoked_reason text)
language plpgsql stable security definer set search_path = public as $$
declare own_ boolean;   /* prof134 */
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  own_ := public.is_owner();
  return query
    select s.id, s.user_id, pr.staff_id, pr.full_name, case when own_ or public._unit_vis134(s.org_unit_id) then s.org_unit_id end, case when own_ or public._unit_vis134(s.org_unit_id) then u.code end,
           s.role_code, s.status,
           s.status = 'active' and exists (select 1 from public.user_roles ur where ur.user_id = s.user_id and ur.role_code = s.role_code),
           s.note, s.granted_at, s.revoked_at, s.revoked_reason
      from public.user_org_scopes s join public.profiles pr on pr.id = s.user_id join public.org_units u on u.id = s.org_unit_id
     where (own_ or s.user_id = auth.uid() or public._unit_mgr134(s.org_unit_id)) and (p_user is null or s.user_id = p_user)
     order by s.id;
end $$;

-- shares and the coverage report name or count SEVERAL businesses: owner only
create or replace function public.master_share_list() returns table (id bigint, table_name text, row_key text, from_org bigint, from_code text, to_org bigint, to_code text, status text, note text, created_at timestamptz, revoked_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and public.is_owner()) then raise exception 'not allowed'; end if;   /* prof134 */
  return query select s.id, s.table_name, s.row_key, s.from_org, f.code, s.to_org, t.code, s.status, s.note, s.created_at, s.revoked_at
    from public.master_shares132 s join public.org_units f on f.id = s.from_org join public.org_units t on t.id = s.to_org order by s.id;
end $$;

-- a business the caller may not use answers exactly like a missing one
create or replace function public.master_context_set132(p_org bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_org is null then delete from public.master_ctx132 where user_id = auth.uid(); return jsonb_build_object('org_unit_id', null); end if;
  if not (p_org in (select public._my_biz123())) or not exists (select 1 from public.org_units where id = p_org and kind = 'business' and status <> 'inactive') then raise exception 'not allowed'; end if;   /* prof134 */
  insert into public.master_ctx132 (user_id, org_unit_id) values (auth.uid(), p_org) on conflict (user_id) do update set org_unit_id = excluded.org_unit_id, set_at = now();
  return jsonb_build_object('org_unit_id', p_org);
end $$;

-- base currency of a business = that of its legal entity. Reads the tables directly (the tree no longer shows the legal entity to the people of a business)
create or replace function public._ie_base124(p_org bigint) returns text
language sql stable security definer set search_path = public as $$
  select le.base_currency from public.legal_entities le where le.org_unit_id in (select public._org_anc123(p_org));   /* prof134 */
$$;

-- text patches (exact anchors, a second paste is a no-op): the coverage report is owner only; a foreign business id looks like a missing one
select public._patch133('public.master_scope_report132()'::regprocedure, '/* prof134 */', array[
  'if not (public.is_active() and (public.is_owner() or public.has_grant(''org_manage''))) then raise exception ''not allowed''; end if;',
  'if not (public.is_active() and public.is_owner()) then raise exception ''not allowed''; end if; /* prof134 */']);
select public._patch133('public.daily_digest_biz133(bigint,date)'::regprocedure, '/* prof134 */', array[
  E'  if p_biz is null or not exists (select 1 from public.org_units where id = p_biz and kind = ''business'') then raise exception ''bad_business''; end if;\n  if not (public.is_owner() or public._is_ops(''notify'') or public.can_scope(p_biz, ''management'')) then raise exception ''not allowed''; end if;',
  E'  if not (public.is_owner() or public._is_ops(''notify'') or public.can_scope(p_biz, ''management'')) then raise exception ''not allowed''; end if; /* prof134 */\n  if p_biz is null or not exists (select 1 from public.org_units where id = p_biz and kind = ''business'') then raise exception ''bad_business''; end if;']);
select public._patch133('public.rule_val_in133(text,bigint)'::regprocedure, '/* prof134 */', array[
  E'  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = ''business'') then raise exception ''bad_business''; end if;\n  if not (public.is_owner() or p_unit in (select public._my_biz123())) then raise exception ''not allowed''; end if;',
  E'  if not (public.is_owner() or p_unit in (select public._my_biz123())) then raise exception ''not allowed''; end if; /* prof134 */\n  if p_unit is null or not exists (select 1 from public.org_units where id = p_unit and kind = ''business'') then raise exception ''bad_business''; end if;']);

-- ---------- 6. policies: a manager sees the units inside his business, nothing above ----------
drop policy if exists ou122_read on public.org_units;
create policy ou122_read on public.org_units for select to authenticated using (public.is_owner() or (kind not in ('group', 'legal_entity') and public._unit_mgr134(id)));
drop policy if exists uos123_read on public.user_org_scopes;
create policy uos123_read on public.user_org_scopes for select to authenticated using (public.is_owner() or (public._unit_vis134(org_unit_id) and (user_id = auth.uid() or public._unit_mgr134(org_unit_id))));
drop policy if exists master_shares132_read on public.master_shares132;
create policy master_shares132_read on public.master_shares132 for select to authenticated using (public.is_owner());

-- ---------- 7. privileges ----------
-- used inside the policies / by the browser: harmless (they answer about the caller himself)
revoke all on function public._vis_biz134(), public._unit_mgr134(bigint), public._unit_vis134(bigint) from public, anon;
grant execute on function public._vis_biz134(), public._unit_mgr134(bigint), public._unit_vis134(bigint) to authenticated;
revoke all on function public._grp_owner134(), public._biz_mgr134(bigint), public._cur_biz134(), public._bp_json134(bigint, boolean), public._bp_kind_check134(), public._bp_seed134() from public, anon, authenticated;
revoke all on function public.business_profile_get(bigint), public.business_profile_list134(), public.business_profile_save(bigint, jsonb, uuid) from public, anon;
grant execute on function public.business_profile_get(bigint), public.business_profile_list134(), public.business_profile_save(bigint, jsonb, uuid) to authenticated;
-- re-created functions keep their grants (create or replace); make sure none is open to anon
revoke all on function public.org_tree(), public.org_unit_scope(int), public.org_unit_deactivate(bigint, text, uuid), public.org_scope_list(uuid), public.master_share_list(),
  public.master_context_set132(bigint) from public, anon;
revoke all on function public._org_visible122(), public._ie_base124(bigint) from public, anon, authenticated;

commit;
