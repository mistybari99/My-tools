-- ============================================================
-- Phase 14 (W2): ITEM MASTER (additive, safe to run twice, paste whole into the Supabase SQL editor)
--   Needs phase8..phase13 applied first (phase11 / phase12 / phase13 are optional but expected).
--   * items: item_type, control_class, count_in_business, sellable, locked, hidden, master_code, retired_at/reason, import_batch
--   * item_types (defaults per type, editable) + item_class_map (dictionary class -> type, editable)
--   * rules tools_stock_on (off), asset_register_on (on), item_create_needs_approval (on), item_master_apply_ok (off); grants item_create, asset_manage
--   * item codes: dictionary code is the permanent code; item_next_code() = max numeric suffix in the category + 1 (advisory lock), retired codes stay reserved
--   * item_new / item_apply (owner or grant item_create act at once; others file a request through item_changes, approved as before)
--   * dictionary import: item_master_import_preview (writes NOTHING) and item_master_import_apply (owner only, idempotent, batch id, one audit line per batch)
--   * old seed items -> dictionary: item_mapping_review / item_master_links (only high-confidence rows auto-link; the rest wait for a decision)
--   * asset register: assets + asset_costs (cost visible only to owner / ITEM_COST / view_cost), RPCs asset_add / asset_update / asset_retire,
--     purchase of an asset-type item auto-adds register rows (hook around post_purchase), voiding the bill retires them
--   * server enforcement: a sale line must be a sellable, priced item; stock ledger refuses items that are not counted in the business;
--     stock value / COGS / profit reports skip count_in_business = false items
--   Nothing is deleted. No price, cost, VAT or limit is invented: imported items have NO selling price ("Data needed").
-- ============================================================

-- ---------- (1) items: new columns (existing items keep behaving exactly as before) ----------
alter table public.items add column if not exists item_type text;
alter table public.items add column if not exists control_class text;
alter table public.items add column if not exists count_in_business boolean not null default true;
alter table public.items add column if not exists sellable boolean not null default true;
alter table public.items add column if not exists locked boolean not null default false;
alter table public.items add column if not exists hidden boolean not null default false;
alter table public.items add column if not exists master_code text;
alter table public.items add column if not exists retired_at timestamptz;
alter table public.items add column if not exists retired_reason text;
alter table public.items add column if not exists import_batch text;
create index if not exists items_type_idx on public.items (item_type);
create index if not exists items_code_prefix_idx on public.items (code text_pattern_ops);

-- ---------- (2) item types (editable defaults) and the dictionary-class map ----------
create table if not exists public.item_types (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,30}$'),
  label_bn text not null, label_mix text, label_en text,
  count_in_business boolean not null default true,    -- default of the flag for new items of this type
  sellable boolean not null default false,            -- default of the flag
  sort int not null default 0, active boolean not null default true,
  note_en text,
  updated_at timestamptz not null default now(), updated_by uuid
);
create table if not exists public.item_class_map (
  control_class text primary key,
  item_type text not null references public.item_types(code),
  active boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid
);
insert into public.item_types (code, label_bn, label_mix, label_en, count_in_business, sellable, sort, note_en) values
 ('finished_good',  'তৈরি পণ্য',        'Finished good',   'Finished good',  true,  true,  1, 'Made here, then sold'),
 ('resale',         'কিনে বিক্রি',       'Resale',          'Resale',         true,  true,  2, 'Bought, then sold'),
 ('raw_material',   'কাঁচামাল',         'Raw material',    'Raw material',   true,  false, 3, 'Consumed in production, never sold'),
 ('packaging',      'প্যাকেজিং',        'Packaging',       'Packaging',      true,  false, 4, 'Goes out with a sale by the per-product rule'),
 ('consumable',     'ভোগ্য সামগ্রী',     'Consumable',      'Consumable',     false, false, 5, 'An expense: not stock, not COGS'),
 ('asset',          'সম্পদ',            'Asset',           'Asset',          false, false, 6, 'Never in stock, sales or COGS; kept in the asset register'),
 ('controlled',     'নিয়ন্ত্রিত (যন্ত্রপাতি)', 'Controlled (tools)', 'Controlled (tools)', false, false, 7, 'Tools: counted separately; off until the tools-stock switch is on'),
 ('infrastructure', 'অবকাঠামো সামগ্রী',  'Infrastructure',  'Infrastructure', false, false, 8, 'Treated like a consumable by default')
on conflict (code) do nothing;
insert into public.item_class_map (control_class, item_type) values
 ('Finished Good', 'finished_good'), ('Stock/Direct Sale', 'resale'), ('Raw Material', 'raw_material'), ('Packaging', 'packaging'),
 ('Consumable', 'consumable'), ('Asset', 'asset'), ('Controlled Item', 'controlled'), ('Infrastructure Material', 'infrastructure')
on conflict (control_class) do nothing;

-- legacy items: type from the old data (a selling price = finished good, else resale); nothing else changes
update public.items set item_type = case when sell_price is not null then 'finished_good' else 'resale' end where item_type is null;
alter table public.items alter column item_type set default 'finished_good';
alter table public.items alter column item_type set not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'items_item_type_fk') then
    alter table public.items add constraint items_item_type_fk foreign key (item_type) references public.item_types(code);
  end if;
end $$;

-- ---------- (3) rules and grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('tools_stock_on', 'items', 'switch', 'false', null, null, null, null, 'যন্ত্রপাতির (নিয়ন্ত্রিত আইটেম) আলাদা স্টক গণনা চালু', 'Tools (controlled item) এর আলাদা stock count চালু', 'Tools stock count (controlled items) on',
   'বন্ধ থাকলে যন্ত্রপাতি ব্যবসার স্টকে ধরা হয় না', 'Off হলে tools business stock এ ধরা হয় না', 'Off = tools are not counted in the business stock. On = every controlled item is counted (its own flag can still be changed). Turning it off needs zero tool stock', 200),
 ('asset_register_on', 'items', 'switch', 'true', null, null, null, null, 'সম্পদ কিনলে সম্পদ-খাতায় নিজে যোগ হবে', 'Asset কিনলে asset register এ নিজে যোগ হবে', 'Buying an asset adds it to the asset register',
   'চালু থাকলে ক্রয় বিল পোস্ট করলে প্রতিটি সম্পদের জন্য একটি সারি', 'On থাকলে purchase bill post করলে প্রতিটি asset এর জন্য একটি row', 'On = posting a purchase bill adds one register row per asset bought (never stock). Off = no rows are added', 201),
 ('item_create_needs_approval', 'items', 'switch', 'true', null, null, null, null, 'নতুন আইটেম যোগে মালিকের অনুমোদন লাগবে (মালিক বা অনুমতিপ্রাপ্ত ছাড়া)', 'নতুন item যোগে owner approval লাগবে (owner বা grant-holder ছাড়া)', 'A new item needs approval (unless added by the owner or a person with the item_create grant)',
   'বন্ধ করলে আইটেম-অনুমতিধারী সবাই সরাসরি যোগ করতে পারবে', 'Off করলে Item-permission আছে এমন সবাই সরাসরি যোগ করতে পারবে', 'Off = anyone who may enter items adds a new item at once', 202),
 ('item_master_apply_ok', 'items', 'switch', 'false', null, null, null, null, 'ডিকশনারি ইমপোর্ট SQL চালানোর অনুমতি (শুধু মালিকের জন্য)', 'Dictionary import SQL চালানোর অনুমতি (শুধু owner)', 'Allow the dictionary import SQL file to write (owner only)',
   null, null, 'Used only by supabase/phase14_import.sql. The owner turns it on by one statement, runs the import, then turns it off again', 203)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('item_create', 'master', 60, 'নতুন আইটেম সরাসরি যোগ ও আইটেমের ফ্ল্যাগ বদল (অনুমোদন ছাড়া)', 'নতুন item সরাসরি যোগ ও item flag বদল (approval ছাড়া)', 'Add new items and change item flags at once (no approval)', 'once', null),
 ('asset_manage', 'master', 61, 'সম্পদ-খাতা সম্পাদনা', 'Asset register edit', 'Edit the asset register', 'once', null)
on conflict (grant_code) do nothing;
insert into public.rule_grants (grant_code, role_code)
  select 'asset_manage', 'management' where exists (select 1 from public.roles where code = 'management') and exists (select 1 from public.grant_defs where grant_code = 'asset_manage')
  and not exists (select 1 from public.rule_grants where grant_code = 'asset_manage')
on conflict do nothing;

-- ---------- (4) option lists: units added (existing values are never renamed), asset condition list ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('units', 'ltr', 'লিটার', 'ltr', 'litre', 7), ('units', 'set', 'সেট', 'set', 'set', 8), ('units', 'pair', 'জোড়া', 'pair', 'pair', 9), ('units', 'meter', 'মিটার', 'meter', 'metre', 10),
 ('asset_conditions', 'new', 'নতুন', 'New', 'New', 1), ('asset_conditions', 'good', 'ভালো', 'Good', 'Good', 2), ('asset_conditions', 'fair', 'মোটামুটি', 'Fair', 'Fair', 3),
 ('asset_conditions', 'poor', 'খারাপ', 'Poor', 'Poor', 4), ('asset_conditions', 'broken', 'নষ্ট', 'Broken', 'Broken', 5)
on conflict (list_code, value_code) do nothing;

-- dictionary unit -> the unit code an item stores (old items use kg / pc / lb; the rest are values of the editable units list)
create or replace function public._item_unit_code(p text) returns text language sql immutable set search_path = public as $$
  select case lower(btrim(p)) when 'kg' then 'kg' when 'pc' then 'pc' when 'pound' then 'lb' when 'lb' then 'lb' when 'gm' then 'gram' when 'gram' then 'gram'
    when 'pack' then 'pack' when 'box' then 'box' when 'ltr' then 'ltr' when 'set' then 'set' when 'pair' then 'pair' when 'meter' then 'meter' end;
$$;

-- ---------- (5) type flag defaults ----------
create or replace function public._item_type_flags(p_type text, out o_count boolean, out o_sell boolean) language plpgsql stable security definer set search_path = public as $$
declare t public.item_types;
begin
  select * into t from public.item_types where code = p_type;
  if not found then return; end if;
  o_count := t.count_in_business or (p_type = 'controlled' and public.rule_on('tools_stock_on'));
  o_sell := t.sellable;
  if p_type = 'asset' then o_count := false; o_sell := false; end if;
  if p_type = 'raw_material' then o_sell := false; end if;
end $$;

-- ---------- (6) guard on items: locked, type rules, counted-in-business ----------
create or replace function public._items_p14_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare sys boolean := coalesce(current_setting('bos.item_sys', true), '') = '1'; busy boolean;
begin
  if tg_op = 'UPDATE' and old.locked and not sys and not public.is_owner() then
    if (to_jsonb(new) - 'updated_at' - 'updated_by') is distinct from (to_jsonb(old) - 'updated_at' - 'updated_by') then raise exception 'item_locked'; end if;
  end if;
  if tg_op = 'INSERT' or new.item_type is distinct from old.item_type then
    if not exists (select 1 from public.item_types where code = new.item_type) then raise exception 'bad_item_type'; end if;
  end if;
  if new.item_type = 'asset' then new.sellable := false; new.count_in_business := false; end if;      -- an asset is never sold or counted
  if new.item_type = 'raw_material' then new.sellable := false; end if;                             -- a raw material is never sold
  if not new.count_in_business then
    if tg_op = 'UPDATE' and old.count_in_business then          -- switching off needs an empty shelf: stock would vanish from the books
      select exists (select 1 from public.stock_balance where item_id = new.id and qty <> 0) into busy;
      if busy then raise exception 'item_has_stock'; end if;
    end if;
    new.tracked := false;
  end if;
  if new.sub_category is not null and new.sub_category = '' then new.sub_category := null; end if;
  return new;
end $$;
drop trigger if exists items_p14_guard on public.items;
create trigger items_p14_guard before insert or update on public.items for each row execute function public._items_p14_guard();

-- the per-row audit line is skipped while a dictionary import runs (the import writes ONE audit line per batch instead)
drop trigger if exists audit_items on public.items;
create trigger audit_items after insert or update on public.items for each row
  when (coalesce(current_setting('bos.item_import', true), '') <> '1') execute function public.log_change('id');

-- ---------- (7) server enforcement: sales and stock ----------
create or replace function public._sale_item_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare ln jsonb; it public.items;
begin
  if new.lines is null or jsonb_typeof(new.lines) <> 'array' then return new; end if;
  for ln in select x from jsonb_array_elements(new.lines) x where nullif(x->>'item_id', '') is not null loop
    select * into it from public.items where id = (ln->>'item_id')::uuid;
    if not found then continue; end if;
    -- sold only when the item is a sellable type, switched on for sale and has a selling price ("Data needed" otherwise)
    if not it.sellable or it.sell_price is null or it.item_type in ('asset', 'raw_material') then
      raise exception 'item_not_sellable' using detail = it.code || ' ' || it.name_bn;
    end if;
  end loop;
  return new;
end $$;
drop trigger if exists sales_item_guard on public.sales;
create trigger sales_item_guard before insert on public.sales for each row execute function public._sale_item_guard();

create or replace function public._ledger_item_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare ok boolean;
begin
  if new.reverses_id is not null then return new; end if;                  -- undoing an earlier line is always allowed
  select count_in_business into ok from public.items where id = new.item_id;
  if ok is distinct from true then raise exception 'item_not_counted' using detail = new.item_id::text; end if;
  return new;
end $$;
drop trigger if exists stock_ledger_item_guard on public.stock_ledger;
create trigger stock_ledger_item_guard before insert on public.stock_ledger for each row execute function public._ledger_item_guard();

-- reports: stock value, COGS and profit leave out items that are not counted in the business (text patch of the current definitions, run once)
do $$
declare d text; o oid;
begin
  select oid into o from pg_proc where proname = 'stock_valuation' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('where b.qty <> 0' in d) > 0 then execute replace(d, 'where b.qty <> 0', 'where i.count_in_business /* bos14 */ and b.qty <> 0'); end if; end if;
  select oid into o from pg_proc where proname = 'rpt_agg_sql' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('left join public.item_costs c on c.item_id = ' in d) > 0 then
      execute replace(d, 'left join public.item_costs c on c.item_id = ', 'left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = '); end if; end if;
  select oid into o from pg_proc where proname = 'biz_daily' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('left join public.item_costs c on c.item_id = l.iid' in d) > 0 then
      execute replace(d, 'left join public.item_costs c on c.item_id = l.iid', 'left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = l.iid'); end if; end if;
  select oid into o from pg_proc where proname = 'biz_items' and pronamespace = 'public'::regnamespace;
  if o is not null then d := pg_get_functiondef(o);
    if position('bos14' in d) = 0 and position('left join public.item_costs c on c.item_id = i.id' in d) > 0 then
      d := replace(d, 'left join public.item_costs c on c.item_id = i.id', 'left join (select ic.item_id, ic.cost_price from public.item_costs ic join public.items cbi on cbi.id = ic.item_id where cbi.count_in_business /* bos14 */) c on c.item_id = i.id');
      d := replace(d, 'where i.is_active or b.iid is not null', 'where (i.is_active and i.sellable) or b.iid is not null');
      execute d; end if; end if;
end $$;

-- ---------- (8) item codes ----------
-- category value (c14) or category number (14) -> the two-digit number used in codes; a category without one gets the next free number (only inside item_new)
create or replace function public._cat_no(p_cat text, p_make boolean default false) returns text language plpgsql security definer set search_path = public as $$
declare n text; mx int;
begin
  if p_cat is null or btrim(p_cat) = '' then return null; end if;
  if p_cat ~ '^[0-9]{2,3}$' then return p_cat; end if;
  select extra->>'cat_no' into n from public.option_lists where list_code = 'item_categories' and value_code = p_cat;
  if n is not null and n <> '' then return n; end if;
  if not p_make or not exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = p_cat) then return null; end if;
  perform pg_advisory_xact_lock(hashtext('item_cat_no'));
  select coalesce(max((extra->>'cat_no')::int), 0) + 1 into mx from public.option_lists where list_code = 'item_categories' and (extra->>'cat_no') ~ '^[0-9]+$';
  n := lpad(mx::text, 2, '0');
  update public.option_lists set extra = extra || jsonb_build_object('cat_no', n) where list_code = 'item_categories' and value_code = p_cat;
  return n;
end $$;

-- next code in a category: highest numeric suffix + 1, zero-padded to 3 digits. Retired items keep their row, so a retired code is never handed out again.
create or replace function public._next_code(p_cat_no text, p_lock boolean) returns text language plpgsql security definer set search_path = public as $$
declare mx int;
begin
  if p_cat_no !~ '^[0-9]{2,3}$' then raise exception 'bad_category'; end if;
  if p_lock then perform pg_advisory_xact_lock(hashtext('item_code:' || p_cat_no)); end if;
  select coalesce(max(substring(code from '^[0-9]+-([0-9]+)$')::int), 0) + 1 into mx from public.items where code like p_cat_no || '-%' and code ~ ('^' || p_cat_no || '-[0-9]+$');
  return p_cat_no || '-' || lpad(mx::text, 3, '0');
end $$;
-- what the screen shows before saving (no lock; the real code is taken inside item_new / apply_item_patch)
create or replace function public.item_next_code(p_category text) returns text language plpgsql stable security definer set search_path = public as $$
declare n text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  n := public._cat_no(p_category, false);
  if n is null then return null; end if;
  return public._next_code(n, false);
end $$;

-- ---------- (9) create / apply: wrapper around the phase12 apply_item_patch (marker keeps phase12 re-runs a no-op) ----------
create or replace function public._item_create_p14(p_patch jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare iid uuid; cat text := nullif(btrim(p_patch->>'category'), ''); cn text; cd text; ty text := coalesce(nullif(p_patch->>'item_type', ''), 'finished_good'); f record; nbn text;
begin
  nbn := coalesce(nullif(btrim(p_patch->>'name_bn'), ''), nullif(btrim(p_patch->>'name_en'), ''));
  if nbn is null then raise exception 'name_required'; end if;
  if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
  cn := public._cat_no(cat, true);
  if cn is not null then cd := public._next_code(cn, true); end if;       -- locked until this transaction ends; the unique index is the backstop
  select * into f from public._item_type_flags(ty);
  insert into public.items (code, name_bn, name_en, name_mix, category, category_bn, unit, sell_price, is_active, item_type, control_class, count_in_business, sellable)
    values (coalesce(cd, 'I-' || lpad(nextval('item_code_seq')::text, 3, '0')), nbn, nullif(btrim(p_patch->>'name_en'), ''), nullif(btrim(p_patch->>'name_mix'), ''), cat, p_patch->>'category_bn',
            p_patch->>'unit', nullif(p_patch->>'sell_price', '')::numeric, coalesce((p_patch->>'is_active')::boolean, true), ty, nullif(btrim(p_patch->>'control_class'), ''),
            coalesce((p_patch->>'count_in_business')::boolean, f.o_count), coalesce((p_patch->>'sellable')::boolean, f.o_sell))
    returning id into iid;
  return iid;
end $$;

create or replace function public._item_flags_apply(p_item uuid, p_patch jsonb) returns void language plpgsql security definer set search_path = public as $$
declare it public.items; f record; ty text;
begin
  select * into it from public.items where id = p_item;
  if not found then raise exception 'item_not_found'; end if;
  if p_patch ? 'item_type' and nullif(p_patch->>'item_type', '') is not null and (p_patch->>'item_type') is distinct from it.item_type then
    ty := p_patch->>'item_type';
    if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
    select * into f from public._item_type_flags(ty);
    -- a changed type starts from the defaults of the new type, unless the same request also says the flags itself
    update public.items set item_type = ty,
      count_in_business = case when p_patch ? 'count_in_business' then (p_patch->>'count_in_business')::boolean else f.o_count end,
      sellable = case when p_patch ? 'sellable' then (p_patch->>'sellable')::boolean else f.o_sell end where id = p_item;
  else
    if p_patch ? 'count_in_business' then update public.items set count_in_business = (p_patch->>'count_in_business')::boolean where id = p_item; end if;
    if p_patch ? 'sellable' then update public.items set sellable = (p_patch->>'sellable')::boolean where id = p_item; end if;
  end if;
  if p_patch ? 'control_class' then update public.items set control_class = nullif(btrim(p_patch->>'control_class'), '') where id = p_item; end if;
  if p_patch ? 'hidden' then update public.items set hidden = (p_patch->>'hidden')::boolean where id = p_item; end if;
  if p_patch ? 'master_code' then update public.items set master_code = nullif(btrim(p_patch->>'master_code'), '') where id = p_item; end if;
  if p_patch ? 'is_active' then
    if (p_patch->>'is_active')::boolean then update public.items set retired_at = null, retired_reason = null where id = p_item and retired_at is not null;
    else update public.items set retired_at = coalesce(retired_at, now()), retired_reason = coalesce(left(nullif(btrim(p_patch->>'retired_reason'), ''), 200), retired_reason) where id = p_item;
    end if;
  end if;
  if p_patch ? 'locked' then
    if not (public.is_owner() or coalesce(current_setting('bos.item_sys', true), '') = '1') then raise exception 'not allowed'; end if;      -- only the owner locks / unlocks
    update public.items set locked = (p_patch->>'locked')::boolean where id = p_item;
  end if;      -- last: the lock never blocks the changes of the same request
end $$;

do $$
declare d text := pg_get_functiondef('public.apply_item_patch(uuid,jsonb)'::regprocedure); mk text; done boolean;
begin
  -- already installed? (the marker can sit one level down when phase12 was run after phase14)
  done := position('bos14-master' in d) > 0
       or coalesce(position('bos14-master' in pg_get_functiondef(to_regprocedure('public._apply_item_patch_base(uuid,jsonb)'))) > 0, false);
  if not done then
    -- when phase12 is already in place the new wrapper carries its marker too, so a later re-run of phase12 stays a no-op; without phase12 the marker is left out and phase12 can still add its details step on top
    mk := case when position('bos12-details' in d) > 0 then 'bos12-details' else '' end;
    drop function if exists public._apply_item_patch_p12(uuid, jsonb);
    alter function public.apply_item_patch(uuid, jsonb) rename to _apply_item_patch_p12;
    execute replace($f$
      create function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
      language plpgsql security definer set search_path = public as $b$
      declare iid uuid;   -- bos14-master @MK@ : creation (next code per category) and the item-master fields are done here, everything else by the previous version
      begin
        if p_item is null then iid := public._item_create_p14(p_patch); else iid := p_item; end if;
        iid := public._apply_item_patch_p12(iid, p_patch);
        perform public._item_flags_apply(iid, p_patch);
        return iid;
      end $b$ $f$, '@MK@', mk);
  end if;
end $$;
revoke all on function public.apply_item_patch(uuid, jsonb), public._apply_item_patch_p12(uuid, jsonb), public._item_create_p14(jsonb), public._item_flags_apply(uuid, jsonb),
  public._cat_no(text, boolean), public._next_code(text, boolean), public._item_type_flags(text) from public, anon, authenticated;

-- a request to create an item can also be approved by a person holding item_create (the owner as before; ITEMS approve as before)
create or replace function public.decide_item_change(p_id bigint, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.item_changes; sid text; self_ok boolean;
begin
  if not (public.is_owner() or public.can_do('ITEMS', 'approve') or (public.is_active() and public.has_grant('item_create'))) then raise exception 'not allowed'; end if;
  select * into c from public.item_changes where id = p_id for update;
  if not found or c.status <> 'pending' then raise exception 'request is not pending'; end if;
  self_ok := public.is_owner() or exists (select 1 from public.user_roles ur join public.roles r on r.code = ur.role_code
              where ur.user_id = auth.uid() and r.allow_self_approve);
  if c.requested_by = auth.uid() and not self_ok then raise exception 'you cannot approve your own request'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then perform public.apply_item_patch(c.item_id, c.patch); end if;
  update public.item_changes set status = case when p_approve then 'approved' else 'rejected' end,
    decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = p_note where id = p_id;
  return jsonb_build_object('status', case when p_approve then 'approved' else 'rejected' end);
end $$;
revoke all on function public.decide_item_change(bigint, boolean, text) from public, anon;
grant execute on function public.decide_item_change(bigint, boolean, text) to authenticated;

-- item_changes: the approval list also shows to item_create holders
drop policy if exists item_changes_read on public.item_changes;
create policy item_changes_read on public.item_changes for select to authenticated
  using (requested_by = auth.uid() or public.is_owner() or public.can_do('ITEMS', 'approve') or public.has_grant('item_create'));

-- item_apply: change an existing item (any field of apply_item_patch + type / flags). Owner or item_create holder = at once, otherwise a request.
create or replace function public.item_apply(p_item uuid, p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint; k text;
begin
  if p_item is null or p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item) then raise exception 'item_not_found'; end if;
  if not (public.is_owner() or public.can_do('ITEMS', 'enter') or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  if p_patch ? 'locked' and not public.is_owner() then raise exception 'not allowed'; end if;               -- only the owner locks / unlocks
  for k in select jsonb_object_keys(p_patch) loop
    if k not in ('name_bn','name_en','name_mix','category','category_bn','unit','sell_price','is_active','sub_category','base_unit','sell_units','wholesale_price','tracked','min_stock',
                 'barcode','source','vat_applicable','images','details','cost_price','item_type','control_class','count_in_business','sellable','locked','hidden','master_code','retired_reason') then
      raise exception 'bad_field';
    end if;
  end loop;
  if public.is_owner() or public.has_grant('item_create') then
    return jsonb_build_object('status', 'applied', 'item_id', public.apply_item_patch(p_item, p_patch));
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (p_item, p_patch, left(p_note, 300), auth.uid(), sid) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;

-- item_new: add a new item under a category with the next code. Owner / item_create holder: at once. Others: a request (rule item_create_needs_approval off = at once).
create or replace function public.item_new(p_patch jsonb, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare sid text; cid bigint; iid uuid; direct boolean; ty text; cat text;
begin
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'bad_request'; end if;
  if not (public.is_owner() or public.can_do('ITEMS', 'enter') or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_patch ? 'cost_price' and not public.can_do('ITEM_COST', 'enter') then raise exception 'not allowed to change cost'; end if;
  if p_patch ? 'locked' and not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(coalesce(p_patch->>'name_bn', p_patch->>'name_en')), '') is null then raise exception 'name_required'; end if;
  ty := coalesce(nullif(p_patch->>'item_type', ''), 'finished_good'); cat := nullif(btrim(p_patch->>'category'), '');
  if not exists (select 1 from public.item_types where code = ty and active) then raise exception 'bad_item_type'; end if;
  if cat is not null and not exists (select 1 from public.option_lists where list_code = 'item_categories' and value_code = cat and active)
     and not exists (select 1 from public.items where category = cat) then raise exception 'bad_category'; end if;
  direct := public.is_owner() or public.has_grant('item_create') or not public.rule_on('item_create_needs_approval');
  if direct then
    iid := public.apply_item_patch(null, p_patch);
    return jsonb_build_object('status', 'created', 'item_id', iid, 'code', (select code from public.items where id = iid));
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.item_changes (item_id, patch, note, requested_by, requested_staff) values (null, p_patch, left(p_note, 300), auth.uid(), sid) returning id into cid;
  return jsonb_build_object('status', 'pending', 'id', cid);
end $$;

-- look-alike check for the ⋮ menu: same name (Bangla / English, ignoring case and spaces), same code prefix, or the same barcode
create or replace function public.item_dup_check(p_name_bn text, p_name_en text, p_exclude uuid default null)
returns table (id uuid, code text, name_bn text, name_en text, why text) language sql stable security definer set search_path = public as $$
  select i.id, i.code, i.name_bn, i.name_en,
         case when lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(coalesce(p_name_bn, ''), '\s+', '', 'g')) then 'same_name_bn' else 'same_name_en' end
  from public.items i
  where public.is_active() and (p_exclude is null or i.id <> p_exclude)
    and ((nullif(btrim(p_name_bn), '') is not null and lower(regexp_replace(i.name_bn, '\s+', '', 'g')) = lower(regexp_replace(p_name_bn, '\s+', '', 'g')))
      or (nullif(btrim(p_name_en), '') is not null and i.name_en is not null and lower(regexp_replace(i.name_en, '\s+', '', 'g')) = lower(regexp_replace(p_name_en, '\s+', '', 'g'))))
  order by i.code limit 20;
$$;

-- owner edits of the settings tables (nothing is deleted: active = false retires)
create or replace function public.item_type_set(p_code text, p_patch jsonb) returns void language plpgsql security definer set search_path = public as $$
declare c text := lower(btrim(p_code));
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if c !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_code'; end if;
  if not exists (select 1 from public.item_types where code = c) then
    if nullif(btrim(p_patch->>'label_bn'), '') is null then raise exception 'name_required'; end if;
    insert into public.item_types (code, label_bn, sort) values (c, btrim(p_patch->>'label_bn'), coalesce((select max(sort) + 1 from public.item_types), 1));
  end if;
  update public.item_types set
    label_bn = coalesce(nullif(btrim(p_patch->>'label_bn'), ''), label_bn),
    label_mix = case when p_patch ? 'label_mix' then nullif(btrim(p_patch->>'label_mix'), '') else label_mix end,
    label_en = case when p_patch ? 'label_en' then nullif(btrim(p_patch->>'label_en'), '') else label_en end,
    count_in_business = case when p_patch ? 'count_in_business' then (p_patch->>'count_in_business')::boolean else count_in_business end,
    sellable = case when p_patch ? 'sellable' then (p_patch->>'sellable')::boolean else sellable end,
    active = case when p_patch ? 'active' then (p_patch->>'active')::boolean else active end,
    updated_at = now(), updated_by = auth.uid()
  where code = c;
  if c = 'asset' then update public.item_types set count_in_business = false, sellable = false where code = 'asset'; end if;       -- fixed by the rule "an asset is never in stock or sales"
  if c = 'raw_material' then update public.item_types set sellable = false where code = 'raw_material'; end if;
end $$;
create or replace function public.item_class_map_set(p_class text, p_type text, p_active boolean default true) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_class), '') is null then raise exception 'bad_code'; end if;
  if not exists (select 1 from public.item_types where code = p_type) then raise exception 'bad_item_type'; end if;
  insert into public.item_class_map (control_class, item_type, active, updated_by) values (btrim(p_class), p_type, coalesce(p_active, true), auth.uid())
    on conflict (control_class) do update set item_type = excluded.item_type, active = excluded.active, updated_at = now(), updated_by = auth.uid();
end $$;

-- tools stock switch: turning it on counts every controlled item; turning it off needs zero tool stock
create or replace function public._tools_switch() returns trigger language plpgsql security definer set search_path = public as $$
declare v boolean := coalesce((new.value #>> '{}')::boolean, (new.default_value #>> '{}')::boolean, false); n int;
begin
  if new.key <> 'tools_stock_on' then return new; end if;
  perform set_config('bos.item_sys', '1', true); perform set_config('bos.item_import', '1', true);
  if v then update public.items set count_in_business = true where item_type = 'controlled' and not count_in_business and is_active;
  else
    if exists (select 1 from public.stock_balance b join public.items i on i.id = b.item_id where i.item_type = 'controlled' and b.qty <> 0) then raise exception 'tools_stock_has_stock'; end if;
    update public.items set count_in_business = false where item_type = 'controlled' and count_in_business;
  end if;
  get diagnostics n = row_count;
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'update', 'items', 'tools_stock_on', jsonb_build_object('tools_stock_on', v, 'items_changed', n));
  perform set_config('bos.item_sys', '', true); perform set_config('bos.item_import', '', true);
  return new;
end $$;
drop trigger if exists rules_tools_switch on public.rules;
create trigger rules_tools_switch after update on public.rules for each row when (new.key = 'tools_stock_on' and new.value is distinct from old.value) execute function public._tools_switch();

-- ---------- (10) dictionary import: classify (shared by preview and apply), preview, apply ----------
create table if not exists public.item_import_batches (
  batch_id text primary key check (batch_id ~ '^[A-Za-z0-9_.:-]{3,60}$'),
  started_at timestamptz not null default now(), started_by uuid, last_at timestamptz not null default now(),
  chunks int not null default 0, rows_seen int not null default 0, created int not null default 0, skipped int not null default 0,
  retired int not null default 0, conflicts int not null default 0, expected_rows int,
  detail jsonb not null default '{}'::jsonb
);
alter table public.item_import_batches enable row level security;
drop policy if exists item_import_batches_read on public.item_import_batches;
create policy item_import_batches_read on public.item_import_batches for select to authenticated using (public.is_owner());
revoke all on public.item_import_batches from public, anon, authenticated; grant select on public.item_import_batches to authenticated;

create or replace function public._item_master_classify(p_rows jsonb) returns table (
  ord int, code text, cat_no text, category text, name_en text, name_bn text, subcategory text, unit text, control_class text, note text,
  item_type text, unit_code text, retired boolean, status text, reason text) language sql stable security definer set search_path = public as $$
  with r as (
    select e.ord::int ord, btrim(coalesce(e.v->>'code', '')) code, btrim(coalesce(e.v->>'cat_no', '')) cat_no, btrim(coalesce(e.v->>'category', '')) category,
           btrim(coalesce(e.v->>'name_en', '')) name_en, btrim(coalesce(e.v->>'name_bn', '')) name_bn, btrim(coalesce(e.v->>'subcategory', '')) subcategory,
           btrim(coalesce(e.v->>'unit', '')) unit, btrim(coalesce(e.v->>'control_class', '')) control_class, btrim(coalesce(e.v->>'note', '')) note
    from jsonb_array_elements(case when jsonb_typeof(p_rows) = 'array' then p_rows else '[]'::jsonb end) with ordinality e(v, ord)),
  c as (
    select r.*, m.item_type, public._item_unit_code(r.unit) unit_code,
           (r.name_en ~* '^\s*RETIRED' or r.name_bn ~* '^\s*RETIRED' or r.note ~* '^\s*Retired') retired,
           row_number() over (partition by r.code order by r.ord) dup_n
    from r left join public.item_class_map m on m.control_class = r.control_class and m.active)
  select c.ord, c.code, c.cat_no, c.category, c.name_en, c.name_bn, c.subcategory, c.unit, c.control_class, c.note, c.item_type, c.unit_code, c.retired,
    case when c.code !~ '^[0-9]{2}-[0-9]{3,}$' or c.dup_n > 1 or (c.name_en = '' and c.name_bn = '') or c.item_type is null or c.unit_code is null
              or c.cat_no !~ '^[0-9]{2}$' or left(c.code, 2) <> c.cat_no or c.category = '' then 'conflict'
         when exists (select 1 from public.items i where i.code = c.code) then 'skip_existing' else 'create' end,
    case when c.code !~ '^[0-9]{2}-[0-9]{3,}$' then 'bad_code' when c.dup_n > 1 then 'duplicate_in_file' when c.name_en = '' and c.name_bn = '' then 'no_name'
         when c.item_type is null then 'unmapped_class' when c.unit_code is null then 'unknown_unit'
         when c.cat_no !~ '^[0-9]{2}$' or left(c.code, 2) <> c.cat_no or c.category = '' then 'category_mismatch'
         when exists (select 1 from public.items i where i.code = c.code) then 'exists' end
  from c order by c.ord;
$$;

create or replace function public.item_master_import_preview(p_rows jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_request'; end if;
  if jsonb_array_length(p_rows) > 5000 then raise exception 'too_many_rows'; end if;
  with k as (select * from public._item_master_classify(p_rows))
  select jsonb_build_object(
    'total', (select count(*) from k),
    'to_create', (select count(*) from k where status = 'create'),
    'to_create_active', (select count(*) from k where status = 'create' and not retired),
    'to_create_retired', (select count(*) from k where status = 'create' and retired),
    'skip_existing', (select count(*) from k where status = 'skip_existing'),
    'retired_rows', (select count(*) from k where retired),
    'conflicts', (select count(*) from k where status = 'conflict'),
    'conflict_list', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'reason', reason, 'name', coalesce(nullif(name_en, ''), name_bn)) order by ord) from (select * from k where status = 'conflict' order by ord limit 100) z), '[]'::jsonb),
    'by_type', coalesce((select jsonb_object_agg(item_type, n) from (select item_type, count(*) n from k where status = 'create' group by 1) z), '{}'::jsonb),
    'by_unit', coalesce((select jsonb_object_agg(unit_code, n) from (select unit_code, count(*) n from k where status = 'create' group by 1) z), '{}'::jsonb),
    'by_category', coalesce((select jsonb_agg(jsonb_build_object('cat_no', cat_no, 'category', category, 'to_create', cr, 'skip_existing', sk, 'retired', rt, 'conflicts', cf) order by cat_no)
        from (select cat_no, max(category) category, count(*) filter (where status = 'create') cr, count(*) filter (where status = 'skip_existing') sk,
                     count(*) filter (where retired) rt, count(*) filter (where status = 'conflict') cf from k group by cat_no) z), '[]'::jsonb),
    'unmapped_classes', coalesce((select jsonb_agg(distinct control_class) from k where reason = 'unmapped_class'), '[]'::jsonb),
    'priced', 0, 'note', 'No selling price is imported: every new item shows Data needed until a price is written')
  into out_;
  return out_;
end $$;

create or replace function public.item_master_import_apply(p_rows jsonb, p_batch text, p_expected int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r record; f record; nb boolean := false; cr int := 0; sk int := 0; rt int := 0; cf int := 0; seen int := 0; catv text; subv text; iid uuid; n int; confl jsonb := '[]'::jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'bad_request'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'too_many_rows'; end if;
  if p_batch is null or p_batch !~ '^[A-Za-z0-9_.:-]{3,60}$' then raise exception 'bad_batch'; end if;
  perform pg_advisory_xact_lock(hashtext('item_master_import'));              -- one chunk at a time
  perform set_config('bos.item_import', '1', true); perform set_config('bos.item_sys', '1', true);
  insert into public.item_import_batches (batch_id, started_by, expected_rows) values (p_batch, auth.uid(), p_expected) on conflict (batch_id) do nothing;
  get diagnostics n = row_count; nb := n > 0;
  for r in select * from public._item_master_classify(p_rows) loop
    seen := seen + 1;
    if r.status = 'conflict' then cf := cf + 1; if jsonb_array_length(confl) < 50 then confl := confl || jsonb_build_object('code', r.code, 'reason', r.reason); end if; continue; end if;
    if r.status = 'skip_existing' then sk := sk + 1; continue; end if;
    catv := 'c' || r.cat_no;
    insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, extra)
      values ('item_categories', catv, '', r.category, r.cat_no::int, jsonb_build_object('cat_no', r.cat_no, 'source', 'dictionary')) on conflict (list_code, value_code) do nothing;
    subv := null;
    if r.subcategory <> '' then
      subv := catv || '_' || left(md5(lower(r.subcategory)), 8);
      insert into public.option_lists (list_code, value_code, label_bn, label_en, sort, extra)
        values ('item_subcategories', subv, '', r.subcategory, r.cat_no::int, jsonb_build_object('category', catv, 'cat_no', r.cat_no, 'source', 'dictionary')) on conflict (list_code, value_code) do nothing;
    end if;
    select * into f from public._item_type_flags(r.item_type);
    insert into public.items (code, name_bn, name_en, category, unit, sub_category, sell_price, is_active, item_type, control_class, count_in_business, sellable, tracked, source, import_batch, retired_at, retired_reason)
      values (r.code, coalesce(nullif(r.name_bn, ''), r.name_en), nullif(r.name_en, ''), catv, r.unit_code, subv, null, not r.retired, r.item_type, r.control_class,
              f.o_count and not r.retired, f.o_sell, false, case r.item_type when 'finished_good' then 'made' when 'resale' then 'bought' end, p_batch,
              case when r.retired then now() end, case when r.retired then left(coalesce(nullif(r.note, ''), 'Retired in the dictionary'), 200) end)
      on conflict (code) do nothing;
    get diagnostics n = row_count;
    if n = 0 then sk := sk + 1; continue; end if;
    cr := cr + 1; if r.retired then rt := rt + 1; end if;
  end loop;
  update public.item_import_batches set chunks = chunks + 1, rows_seen = rows_seen + seen, created = created + cr, skipped = skipped + sk, retired = retired + rt,
    conflicts = conflicts + cf, last_at = now(), expected_rows = coalesce(p_expected, expected_rows),
    detail = jsonb_set(detail, '{conflicts}', coalesce(detail->'conflicts', '[]'::jsonb) || confl) where batch_id = p_batch;
  if nb then      -- ONE audit line per batch (the per-row audit is switched off during the import)
    insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
      values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), 'import', 'items', p_batch, jsonb_build_object('batch', p_batch, 'source', 'item dictionary', 'expected_rows', p_expected));
  end if;
  begin perform public.item_mapping_autolink(); exception when undefined_function then null; end;
  perform set_config('bos.item_import', '', true); perform set_config('bos.item_sys', '', true);
  return jsonb_build_object('batch', p_batch, 'rows', seen, 'created', cr, 'skipped_existing', sk, 'retired_created', rt, 'conflicts', cf, 'conflict_list', confl);
end $$;

-- ---------- (11) old seed items -> dictionary ----------
create table if not exists public.item_mapping_review (
  id bigserial primary key,
  item_id uuid not null unique references public.items(id),
  suggested_code text, confidence numeric(5,3) check (confidence is null or confidence between 0 and 1), auto_ok boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'linked', 'rejected')),
  decided_by uuid, decided_at timestamptz, note text, created_at timestamptz not null default now()
);
create table if not exists public.item_master_links (
  id bigserial primary key,
  item_id uuid not null references public.items(id),          -- the old item (keeps its code and price)
  dict_code text not null,                                    -- the dictionary item it stands for
  active boolean not null default true,
  via text, linked_by uuid, linked_at timestamptz not null default now(), unlinked_at timestamptz
);
create unique index if not exists item_master_links_item_uq on public.item_master_links (item_id) where active;
create unique index if not exists item_master_links_code_uq on public.item_master_links (dict_code) where active;
do $$ declare t text; begin
  foreach t in array array['item_mapping_review', 'item_master_links', 'item_types', 'item_class_map'] loop
    execute format('drop trigger if exists audit_%1$s on public.%1$s', t);
    execute format('create trigger audit_%1$s after insert or update on public.%1$s for each row execute function public.log_change(%2$L)', t, case t when 'item_types' then 'code' when 'item_class_map' then 'control_class' else 'id' end);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
drop policy if exists item_mapping_review_read on public.item_mapping_review;
create policy item_mapping_review_read on public.item_mapping_review for select to authenticated using (public.is_owner() or public.has_grant('item_create'));
drop policy if exists item_master_links_read on public.item_master_links;
create policy item_master_links_read on public.item_master_links for select to authenticated using (public.is_active());
drop policy if exists item_types_read on public.item_types;
create policy item_types_read on public.item_types for select to authenticated using (public.is_active());
drop policy if exists item_class_map_read on public.item_class_map;
create policy item_class_map_read on public.item_class_map for select to authenticated using (public.is_active());
revoke all on public.item_mapping_review, public.item_master_links, public.item_types, public.item_class_map from public, anon, authenticated;
grant select on public.item_mapping_review, public.item_master_links, public.item_types, public.item_class_map to authenticated;
do $$ begin execute 'grant usage, select on sequence public.item_mapping_review_id_seq, public.item_master_links_id_seq to authenticated'; exception when others then null; end $$;

-- rows: [{seed_code, best_code, confidence, auto}] from tools/map_seed_items.py ; existing rows are left alone (a decision is never overwritten)
create or replace function public.item_mapping_load(p_rows jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare e jsonb; iid uuid; n int := 0; s int := 0; cf numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 500 then raise exception 'bad_request'; end if;
  for e in select * from jsonb_array_elements(p_rows) loop
    select id into iid from public.items where code = e->>'seed_code' and import_batch is null;
    cf := nullif(e->>'confidence', '')::numeric;
    if iid is null or cf is null or not (cf between 0 and 1) then s := s + 1; continue; end if;
    insert into public.item_mapping_review (item_id, suggested_code, confidence, auto_ok) values (iid, nullif(e->>'best_code', ''), cf, coalesce((e->>'auto')::int, 0) = 1)
      on conflict (item_id) do nothing;
    get diagnostics n = row_count; if n = 0 then s := s + 1; end if;
  end loop;
  return jsonb_build_object('loaded', jsonb_array_length(p_rows) - s, 'skipped', s);
end $$;

create or replace function public._item_link(p_item uuid, p_dict text, p_via text) returns void language plpgsql security definer set search_path = public as $$
declare tid uuid; cls text;
begin
  select id, control_class into tid, cls from public.items where code = p_dict and import_batch is not null;
  if tid is null then raise exception 'master_code_not_found'; end if;
  if tid = p_item then raise exception 'bad_request'; end if;
  if exists (select 1 from public.item_master_links where dict_code = p_dict and active and item_id <> p_item) then raise exception 'master_code_taken'; end if;
  perform set_config('bos.item_sys', '1', true);
  update public.item_master_links set active = false, unlinked_at = now() where item_id = p_item and active and dict_code <> p_dict;
  insert into public.item_master_links (item_id, dict_code, via, linked_by) select p_item, p_dict, p_via, auth.uid()
    where not exists (select 1 from public.item_master_links where item_id = p_item and dict_code = p_dict and active);
  update public.items set master_code = p_dict, control_class = coalesce(control_class, cls) where id = p_item;
  update public.items set hidden = true, sellable = false where id = tid;           -- the old item stands for it: no second copy in the pickers
  perform set_config('bos.item_sys', '', true);
end $$;

create or replace function public.item_mapping_autolink() returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not (public.is_owner() or current_setting('bos.item_import', true) = '1') then raise exception 'not allowed'; end if;
  for r in select m.* from public.item_mapping_review m where m.status = 'pending' and m.auto_ok and m.suggested_code is not null
           and exists (select 1 from public.items t where t.code = m.suggested_code and t.import_batch is not null)
           and not exists (select 1 from public.item_master_links l where l.dict_code = m.suggested_code and l.active) order by m.id loop
    perform public._item_link(r.item_id, r.suggested_code, 'auto');
    update public.item_mapping_review set status = 'linked', decided_at = now(), decided_by = auth.uid(), note = 'auto (high confidence)' where id = r.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- decide: 'linked' (needs p_dict), 'rejected' (stays a stand-alone old item), 'pending' (undo)
create or replace function public.item_mapping_decide(p_item uuid, p_dict text, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare old_code text; tid uuid;
begin
  if not (public.is_owner() or public.has_grant('item_create')) then raise exception 'not allowed'; end if;
  if p_status not in ('linked', 'rejected', 'pending') then raise exception 'bad_request'; end if;
  if not exists (select 1 from public.items where id = p_item and import_batch is null) then raise exception 'item_not_found'; end if;
  insert into public.item_mapping_review (item_id) values (p_item) on conflict (item_id) do nothing;
  if p_status = 'linked' then
    if nullif(btrim(p_dict), '') is null then raise exception 'master_code_not_found'; end if;
    perform public._item_link(p_item, btrim(p_dict), 'manual');
    update public.item_mapping_review set status = 'linked', suggested_code = coalesce(suggested_code, btrim(p_dict)), decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  else
    select master_code into old_code from public.items where id = p_item;
    if old_code is not null then
      perform set_config('bos.item_sys', '1', true);
      update public.item_master_links set active = false, unlinked_at = now() where item_id = p_item and active;
      update public.items set master_code = null where id = p_item;
      select id into tid from public.items where code = old_code and import_batch is not null;
      if tid is not null then update public.items set hidden = false, sellable = (select o_sell from public._item_type_flags(items.item_type)) where id = tid; end if;
      perform set_config('bos.item_sys', '', true);
    end if;
    update public.item_mapping_review set status = p_status, decided_by = auth.uid(), decided_at = now(), note = left(p_note, 300) where item_id = p_item;
  end if;
  return jsonb_build_object('status', p_status);
end $$;

-- helper trigger functions of phase11 (W1): created here only when phase11 has not been run yet (same text, so a later phase11 changes nothing)
do $$
begin
  if to_regprocedure('public.no_hard_delete()') is null then
    execute $f$create function public.no_hard_delete() returns trigger language plpgsql set search_path = public as $b$ begin raise exception 'nothing is deleted – retire instead'; end $b$ $f$;
  end if;
  if to_regprocedure('public.code_immutable()') is null then
    execute $f$create function public.code_immutable() returns trigger language plpgsql set search_path = public as $b$
      declare c text; o text; n text;
      begin
        foreach c in array tg_argv loop
          o := to_jsonb(old) ->> c; n := to_jsonb(new) ->> c;
          if o is not null and o is distinct from n then raise exception 'code is immutable'; end if;
        end loop;
        return new;
      end $b$ $f$;
  end if;
end $$;

-- ---------- (12) asset register ----------
create sequence if not exists public.asset_tag_seq;
create table if not exists public.assets (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  tag text not null unique default ('A-' || lpad(nextval('public.asset_tag_seq')::text, 5, '0')),
  bought_on date,
  condition text,                                           -- value of the list asset_conditions
  status text not null default 'in_use' check (status in ('in_use', 'in_store', 'under_repair', 'lost', 'sold', 'retired')),
  maintenance_ref uuid references public.entries(id),       -- the 08-1 maintenance record, optional
  note text, active boolean not null default true,
  purchase_bill_id uuid, purchase_line_id bigint, seq_no int,
  retired_at timestamptz, retired_reason text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists assets_line_seq_uq on public.assets (purchase_line_id, seq_no) where purchase_line_id is not null;
create index if not exists assets_loc_idx on public.assets (location_id, active);
create index if not exists assets_item_idx on public.assets (item_id);
create table if not exists public.asset_costs (
  asset_id uuid primary key references public.assets(id),
  cost numeric(14,2) check (cost between 0 and 1000000000000),
  updated_at timestamptz not null default now(), updated_by uuid
);
create or replace function public._assets_touch() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
drop trigger if exists assets_touch on public.assets;
create trigger assets_touch before update on public.assets for each row execute function public._assets_touch();
drop trigger if exists assets_code_immutable on public.assets;
create trigger assets_code_immutable before update on public.assets for each row execute function public.code_immutable('tag');
drop trigger if exists assets_no_delete on public.assets;
create trigger assets_no_delete before delete on public.assets for each row execute function public.no_hard_delete();
drop trigger if exists audit_assets on public.assets;
create trigger audit_assets after insert or update on public.assets for each row execute function public.log_change('id');
drop trigger if exists audit_asset_costs on public.asset_costs;
create trigger audit_asset_costs after insert or update on public.asset_costs for each row execute function public.log_change('asset_id');
drop trigger if exists asset_costs_no_delete on public.asset_costs;
create trigger asset_costs_no_delete before delete on public.asset_costs for each row execute function public.no_hard_delete();
alter table public.assets enable row level security;
alter table public.asset_costs enable row level security;
drop policy if exists assets_read on public.assets;
create policy assets_read on public.assets for select to authenticated using (public.can_loc(location_id));
drop policy if exists asset_costs_read on public.asset_costs;
create policy asset_costs_read on public.asset_costs for select to authenticated
  using (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost'));
revoke all on public.assets, public.asset_costs from public, anon, authenticated;
grant select on public.assets, public.asset_costs to authenticated;

create or replace function public._asset_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.has_grant('asset_manage', p_loc));
$$;

-- p: {item_id, location_id, qty (1..200, default 1), tag, bought_on, cost, condition, status, maintenance_ref, note}; cost needs ITEM_COST enter (or the owner)
create or replace function public.asset_add(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare it public.items; loc int; q int; k int; aid uuid; ids uuid[] := '{}'; cost_ numeric; cond text; st text; mref uuid; bo date; tg text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'bad_request'; end if;
  loc := nullif(p->>'location_id', '')::int;
  if loc is null or not public._asset_ok(loc) then raise exception 'not allowed'; end if;
  select * into it from public.items where id = nullif(p->>'item_id', '')::uuid;
  if not found or it.item_type <> 'asset' then raise exception 'not_an_asset_item'; end if;
  q := coalesce(nullif(p->>'qty', '')::int, 1); if q < 1 or q > 200 then raise exception 'bad_qty'; end if;
  tg := nullif(btrim(p->>'tag'), ''); if tg is not null and q > 1 then raise exception 'tag_needs_qty_1'; end if;
  cost_ := nullif(p->>'cost', '')::numeric;
  if cost_ is not null then
    if not (cost_ between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
    if not (public.is_owner() or public.can_do('ITEM_COST', 'enter')) then raise exception 'not allowed to change cost'; end if;
  end if;
  cond := nullif(p->>'condition', ''); if cond is not null and not exists (select 1 from public.option_lists where list_code = 'asset_conditions' and value_code = cond and active) then raise exception 'bad_condition'; end if;
  st := coalesce(nullif(p->>'status', ''), 'in_use'); if st not in ('in_use', 'in_store', 'under_repair', 'lost', 'sold', 'retired') then raise exception 'bad_status'; end if;
  mref := nullif(p->>'maintenance_ref', '')::uuid;
  if mref is not null and not exists (select 1 from public.entries where id = mref and form_code = '08-1') then raise exception 'bad_maintenance_ref'; end if;
  bo := nullif(p->>'bought_on', '')::date; if bo is not null and bo > (now() at time zone 'Asia/Dhaka')::date + 1 then raise exception 'bad_date'; end if;
  for k in 1..q loop
    insert into public.assets (item_id, location_id, tag, bought_on, condition, status, maintenance_ref, note)
      values (it.id, loc, coalesce(tg, 'A-' || lpad(nextval('public.asset_tag_seq')::text, 5, '0')), bo, cond, st, mref, left(nullif(btrim(p->>'note'), ''), 300)) returning id into aid;
    if cost_ is not null then insert into public.asset_costs (asset_id, cost, updated_by) values (aid, round(cost_, 2), auth.uid()); end if;
    ids := ids || aid;
  end loop;
  return jsonb_build_object('ids', to_jsonb(ids), 'count', q);
end $$;

create or replace function public.asset_update(p_id uuid, p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assets; cond text; st text; mref uuid; cost_ numeric;
begin
  select * into a from public.assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._asset_ok(a.location_id) then raise exception 'not allowed'; end if;
  if p ? 'location_id' and nullif(p->>'location_id', '')::int is distinct from a.location_id then
    if not public._asset_ok((p->>'location_id')::int) then raise exception 'not allowed'; end if;
    if not exists (select 1 from public.locations where id = (p->>'location_id')::int) then raise exception 'bad_request'; end if;
  end if;
  if p ? 'condition' then cond := nullif(p->>'condition', ''); if cond is not null and not exists (select 1 from public.option_lists where list_code = 'asset_conditions' and value_code = cond and active) then raise exception 'bad_condition'; end if; end if;
  if p ? 'status' then st := p->>'status'; if st not in ('in_use', 'in_store', 'under_repair', 'lost', 'sold', 'retired') then raise exception 'bad_status'; end if; end if;
  if p ? 'maintenance_ref' then mref := nullif(p->>'maintenance_ref', '')::uuid; if mref is not null and not exists (select 1 from public.entries where id = mref and form_code = '08-1') then raise exception 'bad_maintenance_ref'; end if; end if;
  if p ? 'cost' then
    if not (public.is_owner() or public.can_do('ITEM_COST', 'enter')) then raise exception 'not allowed to change cost'; end if;
    cost_ := nullif(p->>'cost', '')::numeric; if cost_ is not null and not (cost_ between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
    insert into public.asset_costs (asset_id, cost, updated_by) values (p_id, round(cost_, 2), auth.uid()) on conflict (asset_id) do update set cost = excluded.cost, updated_at = now(), updated_by = auth.uid();
  end if;
  update public.assets set
    location_id = case when p ? 'location_id' then (p->>'location_id')::int else location_id end,
    condition = case when p ? 'condition' then cond else condition end,
    status = case when p ? 'status' then st else status end,
    maintenance_ref = case when p ? 'maintenance_ref' then mref else maintenance_ref end,
    bought_on = case when p ? 'bought_on' then nullif(p->>'bought_on', '')::date else bought_on end,
    note = case when p ? 'note' then left(nullif(btrim(p->>'note'), ''), 300) else note end
  where id = p_id;
  return jsonb_build_object('id', p_id);
end $$;

create or replace function public.asset_retire(p_id uuid, p_reason text, p_status text default 'retired') returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assets;
begin
  select * into a from public.assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._asset_ok(a.location_id) then raise exception 'not allowed'; end if;
  if p_status not in ('lost', 'sold', 'retired') then raise exception 'bad_status'; end if;
  if nullif(btrim(p_reason), '') is null then raise exception 'note_required'; end if;
  update public.assets set active = false, status = p_status, retired_at = coalesce(retired_at, now()), retired_reason = left(btrim(p_reason), 200) where id = p_id;
  return jsonb_build_object('id', p_id, 'status', p_status);
end $$;
create or replace function public.asset_reactivate(p_id uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare a public.assets;
begin
  select * into a from public.assets where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public._asset_ok(a.location_id) then raise exception 'not allowed'; end if;
  update public.assets set active = true, status = 'in_use', retired_at = null, retired_reason = null where id = p_id;
  return jsonb_build_object('id', p_id);
end $$;

-- asset rows from a posted purchase bill (one row per whole unit bought; the cost is the line cost after the bill discount share)
create or replace function public._assets_from_bill(p_bill uuid) returns int language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; q int; k int; net numeric; total int := 0; n int; aid uuid;
begin
  if not public.rule_on('asset_register_on') then return 0; end if;
  select * into pb from public.purchase_bills where id = p_bill;
  if not found or pb.kind <> 'bill' or pb.status <> 'posted' then return 0; end if;
  net := case when pb.subtotal > 0 then (pb.subtotal - pb.discount) / pb.subtotal else 1 end;
  for ln in select l.*, i.item_type from public.purchase_lines l join public.items i on i.id = l.item_id where l.bill_id = p_bill and i.item_type = 'asset' order by l.line_no loop
    q := least(greatest(floor(ln.qty)::int, 1), 200);
    for k in 1..q loop
      insert into public.assets (item_id, location_id, bought_on, condition, status, purchase_bill_id, purchase_line_id, seq_no, note)
        values (ln.item_id, pb.location_id, pb.bill_date, 'new', 'in_use', pb.id, ln.id, k, case when ln.qty <> floor(ln.qty) then 'bought qty ' || ln.qty::text || ' (fraction)' end)
        on conflict (purchase_line_id, seq_no) where purchase_line_id is not null do nothing returning id into aid;
      get diagnostics n = row_count;
      if n > 0 then
        insert into public.asset_costs (asset_id, cost) values (aid, round(ln.unit_cost * net, 2)) on conflict do nothing;
        total := total + 1;
      end if;
    end loop;
  end loop;
  return total;
end $$;

do $$
begin
  if position('bos14-assets' in pg_get_functiondef('public.post_purchase(uuid,jsonb)'::regprocedure)) = 0 then
    drop function if exists public._post_purchase_p13(uuid, jsonb);
    alter function public.post_purchase(uuid, jsonb) rename to _post_purchase_p13;
    execute $f$
      create function public.post_purchase(p_id uuid, p_payments jsonb default null) returns jsonb
      language plpgsql security definer set search_path = public as $b$
      declare r jsonb; n int;   -- bos14-assets: posting is done by the previous version; asset-type lines then go to the asset register (never to stock)
      begin
        r := public._post_purchase_p13(p_id, p_payments);
        if coalesce((r->>'dup')::boolean, false) then return r; end if;
        n := public._assets_from_bill(p_id);
        return r || jsonb_build_object('assets_added', n);
      end $b$ $f$;
  end if;
  if position('bos14-assets' in pg_get_functiondef('public.void_purchase(uuid,text)'::regprocedure)) = 0 then
    drop function if exists public._void_purchase_p13(uuid, text);
    alter function public.void_purchase(uuid, text) rename to _void_purchase_p13;
    execute $f$
      create function public.void_purchase(p_id uuid, p_note text) returns jsonb
      language plpgsql security definer set search_path = public as $b$
      declare r jsonb;   -- bos14-assets: the register rows of a voided bill are retired (never deleted)
      begin
        r := public._void_purchase_p13(p_id, p_note);
        update public.assets set active = false, status = 'retired', retired_at = coalesce(retired_at, now()), retired_reason = 'purchase bill voided' where purchase_bill_id = p_id and active;
        return r;
      end $b$ $f$;
  end if;
end $$;
revoke all on function public._post_purchase_p13(uuid, jsonb), public._void_purchase_p13(uuid, text), public._assets_from_bill(uuid), public._asset_ok(int) from public, anon, authenticated;
revoke all on function public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text) from public, anon;
grant execute on function public.post_purchase(uuid, jsonb), public.void_purchase(uuid, text) to authenticated;

-- ---------- (13) execute rights ----------
revoke all on function public.item_next_code(text), public.item_new(jsonb, text), public.item_apply(uuid, jsonb, text), public.item_dup_check(text, text, uuid),
  public.item_type_set(text, jsonb), public.item_class_map_set(text, text, boolean), public.item_master_import_preview(jsonb), public.item_master_import_apply(jsonb, text, int),
  public.item_mapping_load(jsonb), public.item_mapping_autolink(), public.item_mapping_decide(uuid, text, text, text),
  public.asset_add(jsonb), public.asset_update(uuid, jsonb), public.asset_retire(uuid, text, text), public.asset_reactivate(uuid),
  public._item_link(uuid, text, text), public._item_master_classify(jsonb), public._items_p14_guard(), public._sale_item_guard(), public._ledger_item_guard(), public._tools_switch(),
  public._item_create_p14(jsonb) from public, anon;
grant execute on function public.item_next_code(text), public.item_new(jsonb, text), public.item_apply(uuid, jsonb, text), public.item_dup_check(text, text, uuid),
  public.item_type_set(text, jsonb), public.item_class_map_set(text, text, boolean), public.item_master_import_preview(jsonb), public.item_master_import_apply(jsonb, text, int),
  public.item_mapping_load(jsonb), public.item_mapping_autolink(), public.item_mapping_decide(uuid, text, text, text),
  public.asset_add(jsonb), public.asset_update(uuid, jsonb), public.asset_retire(uuid, text, text), public.asset_reactivate(uuid) to authenticated;
revoke all on function public._item_link(uuid, text, text), public._item_master_classify(jsonb), public._items_p14_guard(), public._sale_item_guard(), public._ledger_item_guard(),
  public._tools_switch(), public._item_create_p14(jsonb) from authenticated;
