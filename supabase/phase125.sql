-- ============================================================
-- Phase 125 (marker var125) - VARIANT ITEM MODEL, per-business items, price lists by channel (ADDITIVE ONLY, default behaviour unchanged).
-- Plan: docs/GROUP_ERP_STAGE_A.md sections 13-14 (fashion / cloth, large catalogues). Canonical order: after phase124 (docs/PASTE_ORDER.md).
-- Needs phase122 (org_units). Does NOT need phase123 / 124. Paste twice = no change, no error.
--   items (existing table): + org_unit_id (nullable, the BUSINESS that owns the item), + style_id, + variant_key, + variant_opts.
--       Existing items are filled with the sweets business (fill-null-only). A BEFORE INSERT trigger fills a new item's org_unit_id (caller's only business, else SWEETS),
--       so every old item-create flow keeps working. items.code stays GLOBALLY unique (old constraint untouched); a NEW unique index (org_unit_id, code) is added:
--       with one business it can never fire, with several businesses it is the constraint that will remain after the global one is relaxed (plan in docs/regs/variants125.md).
--   option_sets / option_values   configurable lists per business (size alpha / numeric / free / kids age band, colour, fabric ...). NOTHING hardcoded: the owner creates them.
--   item_styles / style_axes      a style (parent) and the ordered option sets (axes, max 4) that make its variants.
--   variants_generate(style, pick, dry)   style x option values -> one items row per combination (a variant IS an item, so stock_ledger / stock_balance / POS / purchase
--                                 work unchanged, stock per variant per location). Idempotent (unique style_id + variant_key), barcode per variant (internal EAN-13), dry-run first.
--   price_lists / price_list_items   channel retail | wholesale | online, scoped per business, date validity. items.sell_price / wholesale_price are NEVER overwritten.
--   price_for125(item, channel, date, qty)   read: list price when a valid list row exists, else the item's own price (no existing flow calls it).
--   Rule variants_on (switch, default OFF). OFF: every write function refuses ('variants_off'), items_read stays "any active user" exactly as before. ON: items_read also hides
--       other businesses' items (only if the policy is still the original one: a policy already changed by Stage C1 is left to C1).
--   Grant variants_manage. RLS on every new table, no browser write, audit triggers, no hard delete, anon has nothing.
-- Rollback: leave variants_on OFF. To remove: drop the functions, the new tables, the items trigger/columns/indexes (nothing else refers to them).
-- ============================================================
begin;

do $g$
declare miss text := '';
begin
  if to_regclass('public.items') is null or to_regclass('public.org_units') is null or to_regclass('public.locations') is null or to_regclass('public.user_locations') is null
     or to_regclass('public.grant_defs') is null or to_regclass('public.rules') is null or to_regclass('public.stock_balance') is null or to_regclass('public.item_types') is null then miss := miss || ' tables'; end if;
  if to_regprocedure('public.is_owner()') is null or to_regprocedure('public.is_active()') is null or to_regprocedure('public.has_grant(text,integer)') is null
     or to_regprocedure('public.log_change()') is null or to_regprocedure('public.no_hard_delete()') is null or to_regprocedure('public._client_lock(uuid)') is null
     or to_regprocedure('public.rule_on(text)') is null or to_regprocedure('public.can_loc(integer)') is null then miss := miss || ' functions'; end if;
  if miss <> '' then raise exception 'phase125 needs the base schema and phases up to 122 pasted first (docs/PASTE_ORDER.md); missing:%', miss; end if;
end $g$;

-- ---------- 1. scope helpers (business of a unit; which businesses may the caller see) ----------
-- walk up from any unit to its business ancestor (null when the unit is not under a business)
create or replace function public._biz_of125(p_unit bigint) returns bigint
language sql stable security definer set search_path = public as $$
  with recursive up(id, parent_id, kind) as (
    select o.id, o.parent_id, o.kind from public.org_units o where o.id = p_unit
    union all
    select p.id, p.parent_id, p.kind from public.org_units p join up on up.parent_id = p.id)
  select id from up where kind = 'business' limit 1;
$$;

-- the businesses the caller may work in: owner = every business; others = the businesses of the locations explicitly assigned in user_locations
-- (the 'management' role bypass of can_loc is deliberately NOT used)
create or replace function public._my_biz125() returns setof bigint
language sql stable security definer set search_path = public as $$
  select o.id from public.org_units o where o.kind = 'business' and public.is_active() and public.is_owner()
  union
  select public._biz_of125(l.org_unit_id) from public.locations l join public.user_locations ul on ul.location_id = l.id
   where public.is_active() and ul.user_id = auth.uid() and l.org_unit_id is not null and public._biz_of125(l.org_unit_id) is not null;
$$;

create or replace function public._biz_vis125(p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_biz is not null and (public.is_owner() or p_biz in (select public._my_biz125()));
$$;

-- may the caller change variant / price data of this business? owner, or grant variants_manage AND the business is one of theirs
create or replace function public._biz_mgr125(p_biz bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or (public.has_grant('variants_manage') and public._biz_vis125(p_biz)));
$$;

-- the sweets business = the business of the lowest-id mapped location (phase122 maps all existing locations to it); fallback: code SWEETS
create or replace function public._biz_default125() returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select public._biz_of125(l.org_unit_id) from public.locations l where l.org_unit_id is not null order by l.id limit 1),
    (select o.id from public.org_units o where o.code = 'SWEETS' and o.kind = 'business'));
$$;

-- common write gate: switch ON, business exists and is active, caller may manage it
create or replace function public._var_gate125(p_biz bigint) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('variants_on') then raise exception 'variants_off'; end if;
  if p_biz is null or not exists (select 1 from public.org_units o where o.id = p_biz and o.kind = 'business' and o.status <> 'inactive') then raise exception 'bad_business'; end if;
  if not public._biz_mgr125(p_biz) then raise exception 'not allowed'; end if;
end $$;

-- ---------- 2. items: per-business scope + style / variant link ----------
alter table public.items add column if not exists org_unit_id bigint references public.org_units(id);
alter table public.items add column if not exists style_id bigint;
alter table public.items add column if not exists variant_key text;
alter table public.items add column if not exists variant_opts jsonb;
create index if not exists items_org_unit125 on public.items (org_unit_id);

-- ---------- 3. new tables ----------
create table if not exists public.option_sets (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_]{0,23}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(name_en) <= 80),
  kind text not null default 'other' check (kind in ('size', 'colour', 'fabric', 'age', 'other')),
  product_group text check (product_group is null or length(product_group) <= 80),     -- the item category this list is meant for (informational; null = any)
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code)
);
create table if not exists public.option_values (
  id bigserial primary key,
  set_id bigint not null references public.option_sets(id),
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9._]{0,15}$'),
  label_bn text not null check (length(btrim(label_bn)) between 1 and 60),
  label_en text check (label_en is null or length(label_en) <= 60),
  sort int not null default 0 check (sort between 0 and 100000),
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (set_id, code)
);
create table if not exists public.item_styles (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_]{0,23}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 120),
  name_en text check (name_en is null or length(name_en) <= 120),
  product_group text check (product_group is null or length(product_group) <= 80),
  sub_category text check (sub_category is null or length(sub_category) <= 80),
  unit text not null default 'pc' check (length(unit) between 1 and 20),
  item_type text not null default 'resale' references public.item_types(code),
  base_price numeric(12,2) check (base_price is null or (base_price >= 0 and base_price <= 1000000000)),
  status text not null default 'active' check (status in ('active', 'inactive')),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code)
);
create table if not exists public.style_axes (
  style_id bigint not null references public.item_styles(id),
  axis_no int not null check (axis_no between 1 and 4),
  set_id bigint not null references public.option_sets(id),
  primary key (style_id, axis_no),
  unique (style_id, set_id)
);
create table if not exists public.price_lists (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z0-9][A-Z0-9_-]{0,23}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(name_en) <= 80),
  channel text not null check (channel in ('retail', 'wholesale', 'online')),
  valid_from date not null default date '2000-01-01',
  valid_to date,
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code),
  check (valid_to is null or valid_to >= valid_from)
);
create table if not exists public.price_list_items (
  id bigserial primary key,
  price_list_id bigint not null references public.price_lists(id),
  org_unit_id bigint not null references public.org_units(id),
  item_id uuid not null references public.items(id),
  price numeric(12,2) not null check (price >= 0 and price <= 1000000000),
  min_qty numeric(12,3) not null default 1 check (min_qty > 0 and min_qty <= 1000000000),
  valid_from date not null default date '2000-01-01',
  valid_to date,
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  unique (price_list_id, item_id, min_qty, valid_from)
);
create index if not exists price_list_items_item125 on public.price_list_items (item_id);

do $f$ begin
  if not exists (select 1 from pg_constraint where conname = 'items_style_fk125') then
    alter table public.items add constraint items_style_fk125 foreign key (style_id) references public.item_styles(id);
  end if;
end $f$;
create index if not exists items_style125 on public.items (style_id) where style_id is not null;
create unique index if not exists items_style_variant_uq125 on public.items (style_id, variant_key) where style_id is not null;
-- per-business item code uniqueness (the global items.code unique constraint is untouched; see docs/regs/variants125.md for the plan to relax it)
create unique index if not exists items_org_code_uq125 on public.items (org_unit_id, code);

-- audit + never hard delete
do $a$
declare t text;
begin
  foreach t in array array['option_sets', 'option_values', 'item_styles', 'price_lists', 'price_list_items'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_nodel125', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel125', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t || '125', t);
    execute format('create trigger %I after insert or update on public.%I for each row execute function public.log_change(%L)', 'audit_' || t || '125', t, 'id');
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read125', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._biz_vis125(org_unit_id))', t || '_read125', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('revoke all on sequence public.%I from public, anon, authenticated', t || '_id_seq');
  end loop;
end $a$;
-- style_axes: no id column; scoped through its style. Axes of a style WITHOUT variants may be replaced (so no no-delete trigger here); once variants exist they are locked.
alter table public.style_axes enable row level security;
drop policy if exists style_axes_read125 on public.style_axes;
create policy style_axes_read125 on public.style_axes for select to authenticated using (exists (select 1 from public.item_styles s where s.id = style_id and public._biz_vis125(s.org_unit_id)));
revoke all on public.style_axes from public, anon, authenticated;
grant select on public.style_axes to authenticated;

-- ---------- 4. items trigger: the owning business of a new item; never moves later ----------
create or replace function public._items_org125() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int; b bigint;
begin
  if tg_op = 'UPDATE' then
    if old.org_unit_id is not null and new.org_unit_id is distinct from old.org_unit_id then raise exception 'item_org_fixed'; end if;
  end if;
  if new.org_unit_id is null then
    select count(*), max(x) into n, b from (select distinct public._my_biz125() as x) q;
    if n = 1 then new.org_unit_id := b; else new.org_unit_id := public._biz_default125(); end if;
  elsif tg_op = 'INSERT' or new.org_unit_id is distinct from old.org_unit_id then
    if not exists (select 1 from public.org_units o where o.id = new.org_unit_id and o.kind = 'business') then raise exception 'bad_business'; end if;
  end if;
  return new;
end $$;
drop trigger if exists items_org125 on public.items;
create trigger items_org125 before insert or update on public.items for each row execute function public._items_org125();

-- backfill: every existing item belongs to the sweets business (fill-null-only). The user triggers are paused for the statement so that updated_at / audit rows / guards
-- are not touched by a pure column fill.
do $b$
declare bz bigint := public._biz_default125();
begin
  if bz is not null and exists (select 1 from public.items where org_unit_id is null) then
    alter table public.items disable trigger user;
    update public.items set org_unit_id = bz where org_unit_id is null;
    alter table public.items enable trigger user;
  end if;
end $b$;

-- ---------- 5. rule + grant + advisor row ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'variants_manage', 'stock', 99, 'ভ্যারিয়েন্ট (সাইজ/রং), অপশন তালিকা ও দামের তালিকা তৈরি ও বদলানো', 'Variant (size/colour), option list ও price list তৈরি ও বদলানো', 'Create and change variants (size / colour), option lists and price lists', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'variants_manage');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('variants_on', 'stock', 'switch', 'false', null, null, null, null,
  'ভ্যারিয়েন্ট আইটেম (সাইজ/রং) ও দামের তালিকা', 'Variant item (size/colour) ও price list', 'Variant items (size / colour) and price lists',
  'বন্ধ থাকলে মিষ্টির সব কাজ আগের মতোই। চালু করলে ভ্যারিয়েন্ট তৈরি ও দামের তালিকা কাজ করে এবং এক ব্যবসার আইটেম অন্য ব্যবসা দেখে না।',
  'off থাকলে মিষ্টির সব কাজ আগের মতোই। on করলে variant তৈরি ও price list কাজ করে এবং এক business-এর item অন্য business দেখে না।',
  'Off: sweets works exactly as before. On: variant generation and price lists work and one business can no longer read another business''s items.', 991)
on conflict (key) do nothing;

insert into public.setup_rec_defs81 (code, rule_key, phase, module, rec_value, ready_checks, reason_bn, reason_mix, reason_en, sort)
select 'variants_on', 'variants_on', '125', 'stock', null::jsonb, '{}'::text[],
  'শুধু যখন দ্বিতীয় ব্যবসা (কাপড়/হার্ডওয়্যার) শুরু হবে তখন চালু করুন। মিষ্টির জন্য বন্ধ থাকুক।',
  'শুধু যখন দ্বিতীয় business (কাপড়/hardware) শুরু হবে তখন on করুন। মিষ্টির জন্য off থাকুক।',
  'Turn on only when a second business (cloth / hardware) starts. Keep it off for sweets.', 991
where not exists (select 1 from public.setup_rec_defs81 where code = 'variants_on');

-- ---------- 6. items_read: with the switch ON an item is visible only inside the caller's business ----------
-- Replaces the policy only while it is still the original "any active user" one; a policy already tightened by Stage C1 is left alone.
do $p$
declare q text;
begin
  select qual into q from pg_policies where schemaname = 'public' and tablename = 'items' and policyname = 'items_read';
  if q is null or q ~* 'variants_on' or regexp_replace(q, '[\s()]', '', 'g') ~ '^(public\.)?is_active$' then
    drop policy if exists items_read on public.items;
    create policy items_read on public.items for select to authenticated using (
      public.is_active() and (
        not (select public.rule_on('variants_on'))
        or org_unit_id is null
        or (select public.is_owner())
        or org_unit_id in (select public._my_biz125())));
  else
    raise notice 'phase125: items_read was changed by another phase (%); left as is', q;
  end if;
end $p$;

-- ---------- 7. option sets and values (owner editable, nothing hardcoded) ----------
create or replace function public.option_set_save(p_org bigint, p_id bigint, p_code text, p_name_bn text, p_name_en text default null, p_kind text default 'other',
  p_group text default null, p_active boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); s public.option_sets; c text := upper(btrim(coalesce(p_code, ''))); nid bigint;
begin
  perform public._var_gate125(p_org);
  perform public._client_lock(p_client);
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 80 or length(coalesce(p_name_en, '')) > 80 then raise exception 'bad_name'; end if;
  if p_kind is null or p_kind not in ('size', 'colour', 'fabric', 'age', 'other') then raise exception 'bad_kind'; end if;
  if length(coalesce(p_group, '')) > 80 then raise exception 'bad_group'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into s from public.option_sets where client_id = p_client;
    if found then
      if s.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', s.id, 'code', s.code);
    end if;
    if c !~ '^[A-Z0-9][A-Z0-9_]{0,23}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.option_sets where org_unit_id = p_org and code = c) then raise exception 'code_taken'; end if;
    insert into public.option_sets (org_unit_id, code, name_bn, name_en, kind, product_group, active, client_id, created_by, updated_by)
    values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_kind, nullif(btrim(coalesce(p_group, '')), ''), coalesce(p_active, true), p_client, me, me) returning id into nid;
    return jsonb_build_object('dup', false, 'id', nid, 'code', c);
  end if;
  select * into s from public.option_sets where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'set_not_found'; end if;
  if p_code is not null and c <> s.code then raise exception 'code_fixed'; end if;
  update public.option_sets set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), kind = p_kind,
    product_group = nullif(btrim(coalesce(p_group, '')), ''), active = coalesce(p_active, active), updated_by = me, updated_at = now() where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', s.code);
end $$;

-- upsert many values of one set: [{"code":"M","label_bn":"M","label_en":"Medium","sort":20,"active":true}, ...]. A value is never deleted: set active=false.
create or replace function public.option_values_save(p_set bigint, p_values jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.option_sets; v jsonb; n int := 0; c text; lb text; le text; so int; ac boolean; me uuid := auth.uid();
begin
  select * into s from public.option_sets where id = p_set;
  if not found then raise exception 'set_not_found'; end if;
  perform public._var_gate125(s.org_unit_id);
  if p_values is null or jsonb_typeof(p_values) <> 'array' or jsonb_array_length(p_values) not between 1 and 200 then raise exception 'bad_values'; end if;
  for v in select * from jsonb_array_elements(p_values) loop
    if jsonb_typeof(v) <> 'object' then raise exception 'bad_values'; end if;
    c := upper(btrim(coalesce(v->>'code', '')));
    if c !~ '^[A-Z0-9][A-Z0-9._]{0,15}$' then raise exception 'bad_code'; end if;
    lb := btrim(coalesce(v->>'label_bn', v->>'label_en', c)); le := nullif(btrim(coalesce(v->>'label_en', '')), '');
    if length(lb) not between 1 and 60 or length(coalesce(le, '')) > 60 then raise exception 'bad_name'; end if;
    so := coalesce(nullif(v->>'sort', '')::int, 0); if so not between 0 and 100000 then raise exception 'bad_sort'; end if;
    ac := coalesce(nullif(v->>'active', '')::boolean, true);
    insert into public.option_values (set_id, org_unit_id, code, label_bn, label_en, sort, active, created_by, updated_by)
    values (s.id, s.org_unit_id, c, lb, le, so, ac, me, me)
    on conflict (set_id, code) do update set label_bn = excluded.label_bn, label_en = excluded.label_en, sort = excluded.sort, active = excluded.active, updated_by = me, updated_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('saved', n, 'set_id', s.id);
end $$;

-- ---------- 8. styles ----------
create or replace function public.style_save(p_org bigint, p_id bigint, p_code text, p_name_bn text, p_name_en text default null, p_group text default null,
  p_sub text default null, p_unit text default 'pc', p_item_type text default 'resale', p_price numeric default null, p_axes bigint[] default null,
  p_status text default 'active', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); st public.item_styles; c text := upper(btrim(coalesce(p_code, ''))); nid bigint; i int; a bigint; cur bigint[]; has_var boolean;
begin
  perform public._var_gate125(p_org);
  perform public._client_lock(p_client);
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 120 or length(coalesce(p_name_en, '')) > 120 then raise exception 'bad_name'; end if;
  if length(coalesce(p_group, '')) > 80 or length(coalesce(p_sub, '')) > 80 then raise exception 'bad_group'; end if;
  if p_unit is null or length(btrim(p_unit)) not between 1 and 20 then raise exception 'bad_unit'; end if;
  if not exists (select 1 from public.item_types where code = p_item_type) then raise exception 'bad_item_type'; end if;
  if p_price is not null and (p_price <> p_price or p_price < 0 or p_price > 1000000000) then raise exception 'bad_price'; end if;
  if p_status not in ('active', 'inactive') then raise exception 'bad_status'; end if;
  if p_axes is not null then
    if coalesce(array_length(p_axes, 1), 0) not between 1 and 4 then raise exception 'bad_axes'; end if;
    if (select count(distinct x) from unnest(p_axes) x) <> array_length(p_axes, 1) then raise exception 'bad_axes'; end if;
    foreach a in array p_axes loop
      if not exists (select 1 from public.option_sets s where s.id = a and s.org_unit_id = p_org and s.active) then raise exception 'bad_axes'; end if;
    end loop;
  end if;
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into st from public.item_styles where client_id = p_client;
    if found then
      if st.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', st.id, 'code', st.code);
    end if;
    if c !~ '^[A-Z0-9][A-Z0-9_]{0,23}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.item_styles where org_unit_id = p_org and code = c) then raise exception 'code_taken'; end if;
    if p_axes is null then raise exception 'bad_axes'; end if;
    insert into public.item_styles (org_unit_id, code, name_bn, name_en, product_group, sub_category, unit, item_type, base_price, status, client_id, created_by, updated_by)
    values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), nullif(btrim(coalesce(p_group, '')), ''), nullif(btrim(coalesce(p_sub, '')), ''),
            btrim(p_unit), p_item_type, round(p_price, 2), p_status, p_client, me, me) returning id into nid;
    for i in 1 .. array_length(p_axes, 1) loop insert into public.style_axes (style_id, axis_no, set_id) values (nid, i, p_axes[i]); end loop;
    return jsonb_build_object('dup', false, 'id', nid, 'code', c);
  end if;
  select * into st from public.item_styles where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'style_not_found'; end if;
  if p_code is not null and c <> st.code then raise exception 'code_fixed'; end if;
  if p_axes is not null then
    select array_agg(set_id order by axis_no) into cur from public.style_axes where style_id = p_id;
    if cur is distinct from p_axes then
      select exists (select 1 from public.items where style_id = p_id) into has_var;
      if has_var then raise exception 'axes_locked'; end if;       -- variants already exist: the axes can no longer change
      delete from public.style_axes where style_id = p_id;
    end if;
  end if;
  update public.item_styles set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), product_group = nullif(btrim(coalesce(p_group, '')), ''),
    sub_category = nullif(btrim(coalesce(p_sub, '')), ''), unit = btrim(p_unit), item_type = p_item_type, base_price = round(p_price, 2), status = p_status,
    updated_by = me, updated_at = now() where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', st.code);
end $$;

-- ---------- 9. variant generator ----------
-- internal EAN-13 (prefix 2 = in-store use), 11 digits from the sequence + check digit
create sequence if not exists public.variant_barcode_seq125;
create or replace function public._ean13_125(p_n bigint) returns text
language sql immutable set search_path = public as $$
  with d as (select '2' || lpad(p_n::text, 11, '0') as s)
  select s || ((10 - (select sum(substr(s, k, 1)::int * case when k % 2 = 0 then 3 else 1 end) % 10 from generate_series(1, 12) k)) % 10)::text from d;
$$;

-- p_pick: optional {"<option set code>": ["S","M"]} to generate only a subset. p_dry (default true) writes nothing and returns the plan. Max 500 combinations per call.
-- Idempotent: a combination that already exists (style_id + variant_key) is left alone, so running it twice creates nothing new.
create or replace function public.variants_generate(p_style bigint, p_pick jsonb default null, p_dry boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st public.item_styles; naxes int; total int; created int := 0; existing int := 0; r record; bc text; nid uuid; clash text; out jsonb := '[]'::jsonb; tries int;
begin
  select * into st from public.item_styles where id = p_style;
  if not found then raise exception 'style_not_found'; end if;
  perform public._var_gate125(st.org_unit_id);
  if st.status <> 'active' then raise exception 'style_inactive'; end if;
  if p_pick is not null and jsonb_typeof(p_pick) <> 'object' then raise exception 'bad_pick'; end if;
  perform 1 from public.item_styles where id = p_style for update;       -- one generator per style at a time
  select count(*) into naxes from public.style_axes where style_id = p_style;
  if naxes = 0 then raise exception 'no_axes'; end if;
  create temp table if not exists _vg125 (vkey text, vcode text, name_bn text, name_en text, opts jsonb) on commit drop;
  truncate _vg125;
  with recursive ax as (
    select a.axis_no, a.set_id, s.code scode from public.style_axes a join public.option_sets s on s.id = a.set_id where a.style_id = p_style),
  combos(n, vkey, vcode, lbn, len, opts) as (
    select 0, ''::text, ''::text, ''::text, ''::text, '{}'::jsonb
    union all
    select c.n + 1, case when c.n = 0 then v.code else c.vkey || '|' || v.code end, c.vcode || '-' || v.code, c.lbn || ' ' || v.label_bn,
           c.len || ' ' || coalesce(v.label_en, v.label_bn), c.opts || jsonb_build_object(ax.scode, v.code)
      from combos c join ax on ax.axis_no = c.n + 1
      join public.option_values v on v.set_id = ax.set_id and v.active
       and (p_pick is null or not (p_pick ? ax.scode) or (jsonb_typeof(p_pick->ax.scode) = 'array' and (p_pick->ax.scode) ? v.code)))
  insert into _vg125 select vkey, st.code || vcode, regexp_replace(btrim(st.name_bn || ' ' || lbn), '\s+', ' ', 'g'), regexp_replace(btrim(coalesce(st.name_en, st.name_bn) || ' ' || len), '\s+', ' ', 'g'), opts from combos where n = naxes;
  select count(*) into total from _vg125;
  if total = 0 then raise exception 'no_values'; end if;
  if total > 500 then raise exception 'too_many' using hint = total::text; end if;
  -- a code that already belongs to some other item (global items.code is still unique) would break the run: refuse before writing anything
  select string_agg(g.vcode, ', ') into clash from _vg125 g join public.items i on i.code = g.vcode and (i.style_id is distinct from p_style or i.variant_key is distinct from g.vkey);
  if clash is not null then raise exception 'code_taken' using hint = left(clash, 200); end if;
  select count(*) into existing from _vg125 g where exists (select 1 from public.items i where i.style_id = p_style and i.variant_key = g.vkey);
  if p_dry then
    return jsonb_build_object('dry', true, 'total', total, 'would_create', total - existing, 'existing', existing,
      'sample', (select coalesce(jsonb_agg(vcode order by vcode), '[]'::jsonb) from (select g.vcode from _vg125 g where not exists
                  (select 1 from public.items i where i.style_id = p_style and i.variant_key = g.vkey) order by g.vcode limit 20) q));
  end if;
  for r in select g.* from _vg125 g where not exists (select 1 from public.items i where i.style_id = p_style and i.variant_key = g.vkey) order by g.vcode loop
    tries := 0;
    loop
      bc := public._ean13_125(nextval('public.variant_barcode_seq125'));
      exit when not exists (select 1 from public.items where barcode = bc);
      tries := tries + 1; if tries > 50 then raise exception 'barcode_failed'; end if;
    end loop;
    insert into public.items (code, name_bn, name_en, name_mix, category, sub_category, unit, sell_price, item_type, tracked, barcode, org_unit_id, style_id, variant_key, variant_opts)
    values (r.vcode, r.name_bn, r.name_en, r.name_en, st.product_group, st.sub_category, st.unit, st.base_price, st.item_type, true, bc, st.org_unit_id, p_style, r.vkey, r.opts)
    on conflict (style_id, variant_key) where style_id is not null do nothing returning id into nid;
    if nid is not null then
      created := created + 1;
      if jsonb_array_length(out) < 50 then out := out || jsonb_build_object('id', nid, 'code', r.vcode, 'barcode', bc); end if;
    end if;
    nid := null;
  end loop;
  return jsonb_build_object('dry', false, 'total', total, 'created', created, 'existing', total - created, 'items', out);
end $$;

-- ---------- 10. reads: overview + size x colour matrix ----------
create or replace function public.my_businesses125() returns table (id bigint, code text, name_bn text, name_en text, template_code text, variants_on boolean)
language sql stable security definer set search_path = public as $$
  select o.id, o.code, o.name_bn, o.name_en, o.template_code, public.rule_on('variants_on')
    from public.org_units o where o.kind = 'business' and o.status <> 'inactive' and o.id in (select public._my_biz125()) order by o.id;
$$;

create or replace function public.variants_overview(p_org bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._biz_vis125(p_org) then raise exception 'not allowed'; end if;
  return jsonb_build_object('org', p_org, 'variants_on', public.rule_on('variants_on'), 'can_manage', public._biz_mgr125(p_org),
    'option_sets', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'code', s.code, 'name_bn', s.name_bn, 'name_en', s.name_en, 'kind', s.kind, 'product_group', s.product_group, 'active', s.active,
        'values', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'code', v.code, 'label_bn', v.label_bn, 'label_en', v.label_en, 'sort', v.sort, 'active', v.active) order by v.sort, v.code), '[]'::jsonb)
                     from public.option_values v where v.set_id = s.id)) order by s.code), '[]'::jsonb) from public.option_sets s where s.org_unit_id = p_org),
    'styles', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'code', t.code, 'name_bn', t.name_bn, 'name_en', t.name_en, 'product_group', t.product_group, 'unit', t.unit,
        'item_type', t.item_type, 'base_price', t.base_price, 'status', t.status,
        'axes', (select coalesce(jsonb_agg(a.set_id order by a.axis_no), '[]'::jsonb) from public.style_axes a where a.style_id = t.id),
        'variant_count', (select count(*) from public.items i where i.style_id = t.id)) order by t.code), '[]'::jsonb) from public.item_styles t where t.org_unit_id = p_org),
    'price_lists', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name_bn', p.name_bn, 'name_en', p.name_en, 'channel', p.channel, 'valid_from', p.valid_from,
        'valid_to', p.valid_to, 'active', p.active, 'rows', (select count(*) from public.price_list_items x where x.price_list_id = p.id)) order by p.code), '[]'::jsonb)
        from public.price_lists p where p.org_unit_id = p_org));
end $$;

-- the matrix of one style: axes with their values and one cell per variant (stock summed over the locations the caller may see; optional single location)
create or replace function public.variant_matrix(p_style bigint, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st public.item_styles;
begin
  select * into st from public.item_styles where id = p_style;
  if not found or not public._biz_vis125(st.org_unit_id) then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  return jsonb_build_object('style', jsonb_build_object('id', st.id, 'code', st.code, 'name_bn', st.name_bn, 'name_en', st.name_en, 'base_price', st.base_price),
    'axes', (select coalesce(jsonb_agg(jsonb_build_object('axis_no', a.axis_no, 'set_id', s.id, 'code', s.code, 'name_bn', s.name_bn, 'name_en', s.name_en,
        'values', (select coalesce(jsonb_agg(jsonb_build_object('code', v.code, 'label_bn', v.label_bn, 'label_en', v.label_en, 'active', v.active) order by v.sort, v.code), '[]'::jsonb)
                     from public.option_values v where v.set_id = s.id)) order by a.axis_no), '[]'::jsonb)
               from public.style_axes a join public.option_sets s on s.id = a.set_id where a.style_id = p_style),
    'cells', (select coalesce(jsonb_agg(jsonb_build_object('item_id', i.id, 'code', i.code, 'barcode', i.barcode, 'key', i.variant_key, 'opts', i.variant_opts, 'active', i.is_active,
        'sell_price', i.sell_price,
        'stock', (select coalesce(sum(b.qty), 0) from public.stock_balance b where b.item_id = i.id and public.can_loc(b.location_id) and (p_loc is null or b.location_id = p_loc))) order by i.code), '[]'::jsonb)
              from public.items i where i.style_id = p_style));
end $$;

-- ---------- 11. price lists by channel ----------
create or replace function public.price_list_save(p_org bigint, p_id bigint, p_code text, p_name_bn text, p_name_en text default null, p_channel text default 'retail',
  p_from date default null, p_to date default null, p_active boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); pl public.price_lists; c text := upper(btrim(coalesce(p_code, ''))); nid bigint; today date := (now() at time zone 'Asia/Dhaka')::date; f date;
begin
  perform public._var_gate125(p_org);
  perform public._client_lock(p_client);
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 80 or length(coalesce(p_name_en, '')) > 80 then raise exception 'bad_name'; end if;
  if p_channel is null or p_channel not in ('retail', 'wholesale', 'online') then raise exception 'bad_channel'; end if;
  f := coalesce(p_from, date '2000-01-01');
  if f < date '2000-01-01' or f > today + 3660 or (p_to is not null and (p_to < f or p_to > today + 36600)) then raise exception 'bad_date'; end if;
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into pl from public.price_lists where client_id = p_client;
    if found then
      if pl.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', pl.id, 'code', pl.code);
    end if;
    if c !~ '^[A-Z0-9][A-Z0-9_-]{0,23}$' then raise exception 'bad_code'; end if;
    if exists (select 1 from public.price_lists where org_unit_id = p_org and code = c) then raise exception 'code_taken'; end if;
    insert into public.price_lists (org_unit_id, code, name_bn, name_en, channel, valid_from, valid_to, active, client_id, created_by, updated_by)
    values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_channel, f, p_to, coalesce(p_active, true), p_client, me, me) returning id into nid;
    return jsonb_build_object('dup', false, 'id', nid, 'code', c);
  end if;
  select * into pl from public.price_lists where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'list_not_found'; end if;
  if p_code is not null and c <> pl.code then raise exception 'code_fixed'; end if;
  if p_channel <> pl.channel then raise exception 'channel_fixed'; end if;
  update public.price_lists set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), valid_from = f, valid_to = p_to,
    active = coalesce(p_active, active), updated_by = me, updated_at = now() where id = p_id;
  return jsonb_build_object('dup', false, 'id', p_id, 'code', pl.code);
end $$;

-- upsert rows: [{"item_id":"..","price":999,"min_qty":1,"valid_from":"2026-01-01","valid_to":null}]. The item's own price is never touched.
create or replace function public.price_list_items_set(p_list bigint, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pl public.price_lists; v jsonb; n int := 0; it uuid; pr numeric; mq numeric; vf date; vt date; me uuid := auth.uid();
begin
  select * into pl from public.price_lists where id = p_list;
  if not found then raise exception 'list_not_found'; end if;
  perform public._var_gate125(pl.org_unit_id);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) not between 1 and 1000 then raise exception 'bad_rows'; end if;
  for v in select * from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v) <> 'object' then raise exception 'bad_rows'; end if;
    it := (v->>'item_id')::uuid; pr := (v->>'price')::numeric; mq := coalesce(nullif(v->>'min_qty', '')::numeric, 1);
    vf := coalesce(nullif(v->>'valid_from', '')::date, pl.valid_from); vt := nullif(v->>'valid_to', '')::date;
    if pr is null or pr <> pr or pr < 0 or pr > 1000000000 then raise exception 'bad_price'; end if;
    if mq is null or mq <> mq or mq <= 0 or mq > 1000000000 then raise exception 'bad_qty'; end if;
    if vf < pl.valid_from or (vt is not null and vt < vf) or (pl.valid_to is not null and (vf > pl.valid_to or vt > pl.valid_to)) then raise exception 'bad_date'; end if;
    if not exists (select 1 from public.items i where i.id = it and i.org_unit_id = pl.org_unit_id) then raise exception 'item_not_in_business'; end if;
    insert into public.price_list_items (price_list_id, org_unit_id, item_id, price, min_qty, valid_from, valid_to, created_by, updated_by)
    values (pl.id, pl.org_unit_id, it, round(pr, 2), mq, vf, vt, me, me)
    on conflict (price_list_id, item_id, min_qty, valid_from) do update set price = excluded.price, valid_to = excluded.valid_to, updated_by = me, updated_at = now();
    n := n + 1;
  end loop;
  return jsonb_build_object('saved', n, 'list_id', pl.id);
end $$;

-- which price applies? list price when an active list of that channel has a valid row (highest min_qty <= qty, then latest valid_from), else the item's own price.
-- Nothing in the existing sales / POS code calls this; it is the single place a later phase wires channel prices in.
create or replace function public.price_for125(p_item uuid, p_channel text default 'retail', p_on date default null, p_qty numeric default 1) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i public.items; d date := coalesce(p_on, (now() at time zone 'Asia/Dhaka')::date); r record;
begin
  if p_channel is null or p_channel not in ('retail', 'wholesale', 'online') then raise exception 'bad_channel'; end if;
  if p_qty is null or p_qty <> p_qty or p_qty <= 0 then raise exception 'bad_qty'; end if;
  select * into i from public.items where id = p_item;
  if not found or not public._biz_vis125(i.org_unit_id) then raise exception 'not allowed'; end if;
  select x.price, x.price_list_id into r from public.price_list_items x join public.price_lists l on l.id = x.price_list_id
   where x.item_id = p_item and l.channel = p_channel and l.active and l.org_unit_id = i.org_unit_id
     and d between l.valid_from and coalesce(l.valid_to, date '9999-12-31') and d between x.valid_from and coalesce(x.valid_to, date '9999-12-31') and x.min_qty <= p_qty
   order by x.min_qty desc, x.valid_from desc, x.id desc limit 1;
  if found then return jsonb_build_object('price', r.price, 'source', 'list', 'list_id', r.price_list_id, 'channel', p_channel); end if;
  return jsonb_build_object('price', case when p_channel = 'wholesale' then coalesce(i.wholesale_price, i.sell_price) else i.sell_price end, 'source', 'item', 'list_id', null, 'channel', p_channel);
end $$;

-- ---------- 12. privileges ----------
revoke all on function public._biz_of125(bigint), public._my_biz125(), public._biz_vis125(bigint), public._biz_mgr125(bigint), public._biz_default125(), public._var_gate125(bigint),
  public._items_org125(), public._ean13_125(bigint) from public, anon, authenticated;
-- the RLS policies call these two as the signed-in user: they only answer about the caller's own scope
grant execute on function public._my_biz125(), public._biz_vis125(bigint) to authenticated;
revoke all on function public.option_set_save(bigint, bigint, text, text, text, text, text, boolean, uuid), public.option_values_save(bigint, jsonb),
  public.style_save(bigint, bigint, text, text, text, text, text, text, text, numeric, bigint[], text, uuid), public.variants_generate(bigint, jsonb, boolean),
  public.my_businesses125(), public.variants_overview(bigint), public.variant_matrix(bigint, int),
  public.price_list_save(bigint, bigint, text, text, text, text, date, date, boolean, uuid), public.price_list_items_set(bigint, jsonb),
  public.price_for125(uuid, text, date, numeric) from public, anon;
grant execute on function public.option_set_save(bigint, bigint, text, text, text, text, text, boolean, uuid), public.option_values_save(bigint, jsonb),
  public.style_save(bigint, bigint, text, text, text, text, text, text, text, numeric, bigint[], text, uuid), public.variants_generate(bigint, jsonb, boolean),
  public.my_businesses125(), public.variants_overview(bigint), public.variant_matrix(bigint, int),
  public.price_list_save(bigint, bigint, text, text, text, text, date, date, boolean, uuid), public.price_list_items_set(bigint, jsonb),
  public.price_for125(uuid, text, date, numeric) to authenticated;
revoke all on sequence public.variant_barcode_seq125 from public, anon, authenticated;

commit;
