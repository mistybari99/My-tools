-- ============================================================
-- BOS tool · Phase 8 (plan B1): masters + settings + grants + invoice templates + saved views + favourites + discount by amount OR percent.
-- Run AFTER phase7 (ALL_NEW.sql already contains phases 5-7). ADDITIVE and IDEMPOTENT: safe to run again; nothing is dropped except the
-- old 11-argument record_sale2 signature, which is replaced by the same function with two extra OPTIONAL arguments (old calls keep working).
--
-- Principles kept:
--   * no business number is invented: every new number/choice is null (= feature off) unless the owner wrote it, except safe switches
--     (vat_on false, stock_negative_mode warn, costing_method avg, ui_noperm_mode lock, both discount modes on = today's behaviour + percent).
--   * cost stays in item_costs (ITEM_COST). Nothing added to items is secret (wholesale price is a selling price).
--   * every new table has RLS; staff only read, the owner (or a person the owner granted) edits.
-- ============================================================

-- ---------- (a) lists: supplier types, customer types, units (all editable by the owner in Edit lists) ----------
insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('supplier_types', 'milk', 'দুধ / ছানা', 'দুধ / ছানা', 'Milk / chhana', 1), ('supplier_types', 'sugar', 'চিনি', 'চিনি', 'Sugar', 2),
 ('supplier_types', 'packaging', 'প্যাকেজিং', 'Packaging', 'Packaging', 3), ('supplier_types', 'fuel', 'জ্বালানি', 'Fuel', 'Fuel', 4),
 ('supplier_types', 'gas', 'গ্যাস', 'Gas', 'Gas', 5), ('supplier_types', 'services', 'সেবা', 'Services', 'Services', 6),
 ('supplier_types', 'other', 'অন্যান্য', 'Other', 'Other', 9),
 ('customer_types', 'retail', 'খুচরা', 'Retail', 'Retail', 1), ('customer_types', 'wholesale', 'পাইকারি', 'Wholesale', 'Wholesale', 2),
 ('customer_types', 'party', 'পার্টি / অনুষ্ঠান', 'Party / event', 'Party / event', 3), ('customer_types', 'corporate', 'কর্পোরেট', 'Corporate', 'Corporate', 4),
 ('customer_types', 'online', 'অনলাইন', 'Online', 'Online', 5), ('customer_types', 'staff', 'স্টাফ', 'Staff', 'Staff', 6),
 ('units', 'kg', 'কেজি', 'kg', 'kg', 1), ('units', 'piece', 'পিস', 'piece', 'piece', 2), ('units', 'box', 'বক্স', 'box', 'box', 3),
 ('units', 'pack', 'প্যাক', 'pack', 'pack', 4), ('units', 'pound', 'পাউন্ড', 'pound', 'pound', 5), ('units', 'gram', 'গ্রাম', 'gram', 'gram', 6)
on conflict (list_code, value_code) do nothing;

-- customer type taken from the editable list (the old retail/wholesale column stays for the POS)
alter table public.customers add column if not exists type_code text;

-- ---------- (g) grants: new controlled actions; plus who-may per PERSON (and per location), not only per role ----------
insert into public.rules (key, module, kind, default_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('em_view_cost', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: ক্রয়মূল্য দেখা', 'জরুরি request চলবে: cost দেখা', 'Emergency allowed for: seeing cost', 'Off by default', 50),
 ('em_view_profit', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: লাভ/ক্ষতি দেখা', 'জরুরি request চলবে: profit/loss দেখা', 'Emergency allowed for: seeing profit / loss', 'Off by default', 51),
 ('em_view_reports', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: রিপোর্ট দেখা', 'জরুরি request চলবে: report দেখা', 'Emergency allowed for: seeing reports', 'Off by default', 52),
 ('em_export_data', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: ডেটা এক্সপোর্ট', 'জরুরি request চলবে: data export', 'Emergency allowed for: exporting data', 'Off by default', 53),
 ('em_salary_view', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: বেতন দেখা', 'জরুরি request চলবে: salary দেখা', 'Emergency allowed for: seeing salaries', 'Off by default', 54),
 ('em_supplier_manage', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: সাপ্লায়ার পরিচালনা', 'জরুরি request চলবে: supplier পরিচালনা', 'Emergency allowed for: managing suppliers', 'Off by default', 55),
 ('em_settings_invoice', 'emergency', 'switch', 'false', 'জরুরি অনুরোধ চলবে: ইনভয়েস সেটিংস', 'জরুরি request চলবে: invoice settings', 'Emergency allowed for: invoice settings', 'Off by default', 56)
on conflict (key) do nothing;

insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
 ('view_cost', 'cost', 20, 'ক্রয়মূল্য ভিত্তিক হিসাব দেখা', 'Cost ভিত্তিক হিসাব দেখা', 'See cost-based figures', 'window', 'em_view_cost'),
 ('view_profit', 'cost', 21, 'লাভ/ক্ষতি দেখা', 'Profit/loss দেখা', 'See profit / loss', 'window', 'em_view_profit'),
 ('view_reports', 'reports', 22, 'রিপোর্ট দেখা', 'Report দেখা', 'See reports', 'window', 'em_view_reports'),
 ('export_data', 'reports', 23, 'ডেটা এক্সপোর্ট করা', 'Data export করা', 'Export data', 'once', 'em_export_data'),
 ('salary_view', 'people', 24, 'বেতন দেখা', 'Salary দেখা', 'See salaries', 'window', 'em_salary_view'),
 ('supplier_manage', 'master', 25, 'সাপ্লায়ার যোগ/বদলানো', 'Supplier যোগ/বদলানো', 'Add / change suppliers', 'window', 'em_supplier_manage'),
 ('settings_invoice', 'settings', 26, 'ইনভয়েস টেমপ্লেট ও প্রিন্ট সেটিংস বদলানো', 'Invoice template ও print settings বদলানো', 'Change invoice templates and print settings', 'window', 'em_settings_invoice')
on conflict (grant_code) do nothing;

-- a grant given to ONE PERSON (anyone, any role), for all locations (location_id null) or one, optionally until a date
create table if not exists public.user_grants (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  grant_code text not null references public.grant_defs(grant_code),
  location_id int references public.locations(id),
  valid_until timestamptz,
  note text,
  granted_by uuid, granted_at timestamptz not null default now()
);
create unique index if not exists user_grants_uq on public.user_grants (user_id, grant_code, coalesce(location_id, 0));
drop trigger if exists audit_user_grants on public.user_grants;
create trigger audit_user_grants after insert or update or delete on public.user_grants for each row execute function public.log_change('id');
alter table public.user_grants enable row level security;
drop policy if exists user_grants_read on public.user_grants;
create policy user_grants_read on public.user_grants for select to authenticated using (user_id = auth.uid() or public.is_owner());
revoke all on public.user_grants from anon, authenticated;
grant select on public.user_grants to authenticated;

-- owner gives / takes a grant to a person (p_allowed false = remove)
create or replace function public.set_user_grant(p_user uuid, p_code text, p_loc int default null, p_until timestamptz default null, p_allowed boolean default true, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.grant_defs where grant_code = p_code) then raise exception 'unknown grant'; end if;
  if not exists (select 1 from public.profiles where id = p_user) then raise exception 'unknown user'; end if;
  if p_loc is not null and not exists (select 1 from public.locations where id = p_loc) then raise exception 'unknown location'; end if;
  if p_allowed then
    insert into public.user_grants (user_id, grant_code, location_id, valid_until, note, granted_by) values (p_user, p_code, p_loc, p_until, left(p_note, 200), auth.uid())
      on conflict (user_id, grant_code, coalesce(location_id, 0)) do update set valid_until = excluded.valid_until, note = excluded.note, granted_by = auth.uid(), granted_at = now();
  else
    delete from public.user_grants where user_id = p_user and grant_code = p_code and coalesce(location_id, 0) = coalesce(p_loc, 0);
  end if;
end $$;

-- may the caller do p_code (at location p_loc, or anywhere when null)?  owner · role grant · personal grant · approved emergency WINDOW (read only: nothing is consumed)
-- With p_loc null only personal grants that cover every location count; give a location to include location-limited personal grants.
-- KNOWN, DELIBERATE: an approved emergency WINDOW still counts when p_loc is null, even though request_emergency always ties a window to one
-- location (the only location-less requests are closed_period_edit / form_access, which are not windows). Making p_loc null require a
-- location-less window would switch every window approval off (supplier_manage, settings_invoice and the biz_ok / biz_cost_ok checks, whose callers
-- and RLS policies have no location to pass), so the approver's choice to open a window is what limits it: it is time boxed (em_minutes), needs the
-- em_* rule on, is decided by a second person and leaves a trace. Callers that DO have a location should pass it: has_grant(code, loc) then
-- accepts only a window for that location (or for all locations).
create or replace function public.has_grant(p_code text, p_loc int default null) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_owner() or (public.is_active() and (
    public.can_grant(p_code)
    or exists (select 1 from public.user_grants g where g.user_id = auth.uid() and g.grant_code = p_code
               and (g.valid_until is null or g.valid_until > now()) and (g.location_id is null or g.location_id = p_loc))
    or exists (select 1 from public.emergency_requests e join public.grant_defs d on d.grant_code = e.grant_code and d.window_type = 'window'
               where e.requested_by = auth.uid() and e.grant_code = p_code and e.status = 'approved' and e.valid_until > now()
               and (p_loc is null or e.location_id is null or e.location_id = p_loc))));
$$;

-- report / cost visibility now also honours the new grants (owner and the old POS-approver / ITEM_COST paths work exactly as before)
create or replace function public.biz_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('POS', 'approve') or public.has_grant('view_reports'));
$$;
create or replace function public.biz_cost_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost') or public.has_grant('view_profit'));
$$;

-- ---------- (e) settings keys in the existing rules table (null default = not set = feature off) ----------
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('fiscal_year_start_month', 'settings', 'number', null, null, 1, 12, 'অর্থবছর শুরুর মাস (১-১২)', 'Fiscal year শুরুর মাস (1-12)', 'Fiscal year start month (1-12)', 'Empty = calendar year', 60),
 ('fiscal_year_start_day', 'settings', 'number', null, null, 1, 31, 'অর্থবছর শুরুর দিন', 'Fiscal year শুরুর দিন', 'Fiscal year start day', 'Empty = day 1', 61),
 ('week_start', 'settings', 'choice', null, '["sat","sun","mon","tue","wed","thu","fri"]', null, null, 'সপ্তাহ শুরু হয় যে দিনে', 'Week শুরু হয় যে দিনে', 'Week starts on', 'Empty = Saturday in reports', 62),
 ('ui_noperm_mode', 'settings', 'choice', '"lock"', '["lock","hide"]', null, null, 'অনুমতি না থাকলে মডিউল: lock = তালা কার্ড, hide = লুকানো', 'Permission না থাকলে module: lock = তালা card, hide = লুকানো', 'Module without permission: lock card or hide', null, 63),
 ('barcode_camera_on', 'settings', 'switch', 'false', null, null, null, 'বারকোড: ক্যামেরা স্ক্যান চালু', 'Barcode: camera scan চালু', 'Barcode: camera scan on', 'Separate from the device option', 64),
 ('barcode_device_on', 'settings', 'switch', 'false', null, null, null, 'বারকোড: ডিভাইস/স্ক্যানার (টাইপ) চালু', 'Barcode: device scanner (typed) চালু', 'Barcode: device / hardware scanner on', 'Separate from the camera option', 65),
 ('costing_method', 'settings', 'choice', '"avg"', '["avg"]', null, null, 'ক্রয়মূল্য হিসাব পদ্ধতি', 'Costing method', 'Costing method', 'Only average for now; more can be added later', 66),
 ('discount_mode_amount_on', 'pos', 'switch', 'true', null, null, null, 'ডিসকাউন্ট: টাকার অঙ্কে দেওয়া চালু', 'Discount: amount (টাকা) চালু', 'Discount by amount is allowed', null, 67),
 ('discount_mode_percent_on', 'pos', 'switch', 'true', null, null, null, 'ডিসকাউন্ট: শতাংশে দেওয়া চালু', 'Discount: percent চালু', 'Discount by percent is allowed', 'Same limits apply (the limit is checked on the computed amount)', 68),
 ('vat_on', 'settings', 'switch', 'false', null, null, null, 'ভ্যাট চালু', 'VAT চালু', 'VAT is on', 'Off until the adviser confirms', 70),
 ('vat_rate', 'settings', 'number', null, null, 0, 100, 'ভ্যাটের হার (%)', 'VAT rate (%)', 'VAT rate (%)', 'No default: the owner enters it after the adviser answers', 71),
 ('stock_negative_mode', 'settings', 'choice', '"warn"', '["allow","warn","block"]', null, null, 'স্টকের চেয়ে বেশি বিক্রি: allow / warn / block', 'Stock এর চেয়ে বেশি sale: allow / warn / block', 'Selling more than the stock: allow, warn or block', 'Used when the stock ledger arrives (B2)', 72)
on conflict (key) do nothing;

-- fiscal-year / week helpers that follow the settings above (reports use these instead of a fixed January / Saturday)
create or replace function public.fiscal_year_start(p_date date default null) returns date
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); m int := coalesce(public.rule_num('fiscal_year_start_month'), 1)::int;
        dd int := coalesce(public.rule_num('fiscal_year_start_day'), 1)::int; y int := extract(year from d)::int; s date;
begin
  s := make_date(y, m, least(dd, extract(day from (make_date(y, m, 1) + interval '1 month - 1 day'))::int));
  if d < s then y := y - 1; s := make_date(y, m, least(dd, extract(day from (make_date(y, m, 1) + interval '1 month - 1 day'))::int)); end if;
  return s;
end $$;
create or replace function public.fiscal_year_end(p_date date default null) returns date
language sql stable security definer set search_path = public as $$
  select public.fiscal_year_start((public.fiscal_year_start(p_date) + 400)) - 1;
$$;
create or replace function public.week_start_date(p_date date default null) returns date
language sql stable security definer set search_path = public as $$
  with d as (select coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date) x),
       w as (select array_position(array['mon','tue','wed','thu','fri','sat','sun'], coalesce(public.rule_txt('week_start'), 'sat')) n)
  select (d.x - (((extract(isodow from d.x)::int - w.n) + 7) % 7))::date from d, w;
$$;

-- ---------- (a) suppliers master ----------
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  mobile text,
  type_code text,                                         -- from the editable list supplier_types
  address text,
  credit_days int check (credit_days is null or credit_days >= 0),      -- owner enters; empty = unknown
  opening_balance numeric,                                -- empty = not entered; positive = we owe the supplier
  nid text, tin text, note text,
  active boolean not null default true,
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists suppliers_name on public.suppliers (lower(name));
drop trigger if exists audit_suppliers on public.suppliers;
create trigger audit_suppliers after insert or update on public.suppliers for each row execute function public.log_change('id');
alter table public.suppliers enable row level security;
drop policy if exists suppliers_read on public.suppliers;
create policy suppliers_read on public.suppliers for select to authenticated using (public.has_grant('supplier_manage'));
revoke all on public.suppliers from anon, authenticated;
grant select on public.suppliers to authenticated;

-- add (p_id null) or change a supplier; p_patch keys: name, mobile, type_code, address, credit_days, opening_balance, nid, tin, note, active
create or replace function public.save_supplier(p_id uuid, p_patch jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid := p_id; p jsonb := coalesce(p_patch, '{}');
begin
  if not public.has_grant('supplier_manage') then raise exception 'not allowed'; end if;
  if sid is null then
    if nullif(btrim(p->>'name'), '') is null then raise exception 'name_required'; end if;
    insert into public.suppliers (name, created_by) values (left(btrim(p->>'name'), 120), auth.uid()) returning id into sid;
  elsif not exists (select 1 from public.suppliers where id = sid) then raise exception 'not found';
  end if;
  update public.suppliers set
    name = case when p ? 'name' and nullif(btrim(p->>'name'), '') is not null then left(btrim(p->>'name'), 120) else name end,
    mobile = case when p ? 'mobile' then nullif(public.norm_mobile(p->>'mobile'), '') else mobile end,
    type_code = case when p ? 'type_code' then nullif(p->>'type_code', '') else type_code end,
    address = case when p ? 'address' then left(nullif(p->>'address', ''), 300) else address end,
    credit_days = case when p ? 'credit_days' then nullif(p->>'credit_days', '')::int else credit_days end,
    opening_balance = case when p ? 'opening_balance' then nullif(p->>'opening_balance', '')::numeric else opening_balance end,
    nid = case when p ? 'nid' then left(nullif(p->>'nid', ''), 40) else nid end,
    tin = case when p ? 'tin' then left(nullif(p->>'tin', ''), 40) else tin end,
    note = case when p ? 'note' then left(nullif(p->>'note', ''), 300) else note end,
    active = case when p ? 'active' then (p->>'active')::boolean else active end,
    updated_at = now()
  where id = sid;
  return sid;
end $$;

-- picker for forms: any active user sees only id, name, type of ACTIVE suppliers (no balances / ids)
create or replace function public.supplier_pick() returns table (id uuid, name text, type_code text)
language sql stable security definer set search_path = public as $$
  select s.id, s.name, s.type_code from public.suppliers s where public.is_active() and s.active order by lower(s.name);
$$;

-- ---------- (b) items: additive columns (all nullable / off by default; cost is NOT here) ----------
alter table public.items add column if not exists sub_category text;
alter table public.items add column if not exists base_unit text;
alter table public.items add column if not exists sell_units text[] not null default '{}';
alter table public.items add column if not exists wholesale_price numeric(12,2) check (wholesale_price is null or wholesale_price >= 0);
alter table public.items add column if not exists tracked boolean not null default false;      -- stock-tracked? off until the owner decides per item
alter table public.items add column if not exists min_stock numeric check (min_stock is null or min_stock >= 0);
alter table public.items add column if not exists barcode text;
alter table public.items add column if not exists source text check (source is null or source in ('made', 'bought'));
alter table public.items add column if not exists vat_applicable boolean;                       -- null = undecided
alter table public.items add column if not exists images text[] not null default '{}';
create unique index if not exists items_barcode_uq on public.items (barcode) where barcode is not null;

-- items are written only through the patch workflow; teach it the new columns (same signature, old patches behave as before)
create or replace function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare iid uuid := p_item; cp numeric;
begin
  if iid is null then
    insert into public.items (name_bn, name_en, name_mix, category, category_bn, unit, sell_price, is_active)
    values (p_patch->>'name_bn', p_patch->>'name_en', p_patch->>'name_mix', p_patch->>'category', p_patch->>'category_bn',
            p_patch->>'unit', nullif(p_patch->>'sell_price','')::numeric, coalesce((p_patch->>'is_active')::boolean, true))
    returning id into iid;
  else
    update public.items set
      name_bn = coalesce(p_patch->>'name_bn', name_bn),
      name_en = case when p_patch ? 'name_en' then p_patch->>'name_en' else name_en end,
      name_mix = case when p_patch ? 'name_mix' then p_patch->>'name_mix' else name_mix end,
      category = case when p_patch ? 'category' then p_patch->>'category' else category end,
      category_bn = case when p_patch ? 'category_bn' then p_patch->>'category_bn' else category_bn end,
      unit = case when p_patch ? 'unit' then p_patch->>'unit' else unit end,
      sell_price = case when p_patch ? 'sell_price' then nullif(p_patch->>'sell_price','')::numeric else sell_price end,
      is_active = case when p_patch ? 'is_active' then (p_patch->>'is_active')::boolean else is_active end
    where id = iid;
  end if;
  update public.items set
    sub_category = case when p_patch ? 'sub_category' then nullif(btrim(p_patch->>'sub_category'), '') else sub_category end,
    base_unit = case when p_patch ? 'base_unit' then nullif(btrim(p_patch->>'base_unit'), '') else base_unit end,
    sell_units = case when p_patch ? 'sell_units' then case when jsonb_typeof(p_patch->'sell_units') = 'array' then array(select jsonb_array_elements_text(p_patch->'sell_units')) else '{}'::text[] end else sell_units end,
    wholesale_price = case when p_patch ? 'wholesale_price' then nullif(p_patch->>'wholesale_price', '')::numeric else wholesale_price end,
    tracked = case when p_patch ? 'tracked' then coalesce((p_patch->>'tracked')::boolean, false) else tracked end,
    min_stock = case when p_patch ? 'min_stock' then nullif(p_patch->>'min_stock', '')::numeric else min_stock end,
    barcode = case when p_patch ? 'barcode' then nullif(btrim(p_patch->>'barcode'), '') else barcode end,
    source = case when p_patch ? 'source' then nullif(p_patch->>'source', '') else source end,
    vat_applicable = case when p_patch ? 'vat_applicable' then nullif(p_patch->>'vat_applicable', '')::boolean else vat_applicable end,
    images = case when p_patch ? 'images' then case when jsonb_typeof(p_patch->'images') = 'array' then array(select jsonb_array_elements_text(p_patch->'images')) else '{}'::text[] end else images end
  where id = iid and (p_patch ?| array['sub_category','base_unit','sell_units','wholesale_price','tracked','min_stock','barcode','source','vat_applicable','images']);
  if p_patch ? 'cost_price' then
    cp := nullif(p_patch->>'cost_price','')::numeric;
    insert into public.item_costs (item_id, cost_price) values (iid, cp)
      on conflict (item_id) do update set cost_price = excluded.cost_price;
  end if;
  return iid;
end $$;

-- ---------- (c) unit conversions: global (item_id null) or per item. "1 from_unit = factor to_unit" ----------
create table if not exists public.unit_conversions (
  id bigserial primary key,
  item_id uuid references public.items(id) on delete cascade,
  from_unit text not null, to_unit text not null,
  factor numeric not null check (factor > 0),
  active boolean not null default true,
  note text,
  updated_at timestamptz not null default now(), updated_by uuid,
  check (from_unit <> to_unit)
);
create unique index if not exists unit_conv_uq on public.unit_conversions (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid), from_unit, to_unit);
drop trigger if exists audit_unit_conversions on public.unit_conversions;
create trigger audit_unit_conversions after insert or update or delete on public.unit_conversions for each row execute function public.log_change('id');
alter table public.unit_conversions enable row level security;
drop policy if exists unit_conv_read on public.unit_conversions;
drop policy if exists unit_conv_owner on public.unit_conversions;
create policy unit_conv_read on public.unit_conversions for select to authenticated using (public.is_active());
create policy unit_conv_owner on public.unit_conversions for all to authenticated using (public.is_owner()) with check (public.is_owner());
revoke all on public.unit_conversions from anon, authenticated;
grant select, insert, update, delete on public.unit_conversions to authenticated;
grant usage on sequence public.unit_conversions_id_seq to authenticated;

-- one hop: item rule first, then global; a rule works in both directions. null = unknown (nothing is guessed)
create or replace function public._unit_hop(p_item uuid, p_from text, p_to text) returns numeric
language sql stable security definer set search_path = public as $$
  select case when c.from_unit = p_from then c.factor else 1 / c.factor end
  from public.unit_conversions c
  where c.active and (c.item_id = p_item or c.item_id is null)
    and ((c.from_unit = p_from and c.to_unit = p_to) or (c.from_unit = p_to and c.to_unit = p_from))
  order by (c.item_id is null), (c.from_unit <> p_from) limit 1;
$$;
-- factor so that  qty_in_to = qty_in_from * factor ; tries a direct rule, then via the item's base_unit
create or replace function public.unit_factor(p_item uuid, p_from text, p_to text) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare f numeric; b text; x numeric; y numeric;
begin
  if p_from is null or p_to is null then return null; end if;
  if p_from = p_to then return 1; end if;
  f := public._unit_hop(p_item, p_from, p_to);
  if f is not null then return f; end if;
  select base_unit into b from public.items where id = p_item;
  if b is not null and b <> p_from and b <> p_to then
    x := public._unit_hop(p_item, p_from, b); y := public._unit_hop(p_item, b, p_to);
    if x is not null and y is not null then return x * y; end if;
  end if;
  return null;
end $$;
create or replace function public.convert_qty(p_item uuid, p_qty numeric, p_from text, p_to text) returns numeric
language sql stable security definer set search_path = public as $$
  select p_qty * public.unit_factor(p_item, p_from, p_to);
$$;
-- owner sets / changes / removes a rule (p_factor null removes it)
create or replace function public.set_unit_conversion(p_item uuid, p_from text, p_to text, p_factor numeric, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_factor is null then
    delete from public.unit_conversions where coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_item, '00000000-0000-0000-0000-000000000000'::uuid) and from_unit = p_from and to_unit = p_to;
    return;
  end if;
  if p_factor <= 0 or p_factor = 'NaN'::numeric then raise exception 'bad_factor'; end if;
  insert into public.unit_conversions (item_id, from_unit, to_unit, factor, note, updated_by) values (p_item, p_from, p_to, p_factor, left(p_note, 200), auth.uid())
    on conflict (coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid), from_unit, to_unit)
    do update set factor = excluded.factor, note = excluded.note, active = true, updated_at = now(), updated_by = auth.uid();
end $$;

-- ---------- (d) shelf life rules: per item or category (or everything), optionally for a season (month-day range, may wrap the year end) ----------
create table if not exists public.shelf_life_rules (
  id bigserial primary key,
  item_id uuid references public.items(id) on delete cascade,
  category text,                                          -- matches items.category
  season_label text,
  start_month smallint check (start_month between 1 and 12), start_day smallint check (start_day between 1 and 31),
  end_month smallint check (end_month between 1 and 12), end_day smallint check (end_day between 1 and 31),
  value numeric not null check (value > 0),
  unit text not null check (unit in ('hours', 'days')),
  active boolean not null default true,
  note text,
  updated_at timestamptz not null default now(), updated_by uuid,
  check (item_id is null or category is null),
  check ((start_month is null and start_day is null and end_month is null and end_day is null)
      or (start_month is not null and start_day is not null and end_month is not null and end_day is not null))
);
drop trigger if exists audit_shelf_life_rules on public.shelf_life_rules;
create trigger audit_shelf_life_rules after insert or update or delete on public.shelf_life_rules for each row execute function public.log_change('id');
alter table public.shelf_life_rules enable row level security;
drop policy if exists shelf_read on public.shelf_life_rules;
drop policy if exists shelf_owner on public.shelf_life_rules;
create policy shelf_read on public.shelf_life_rules for select to authenticated using (public.is_active());
create policy shelf_owner on public.shelf_life_rules for all to authenticated using (public.is_owner()) with check (public.is_owner());
revoke all on public.shelf_life_rules from anon, authenticated;
grant select, insert, update, delete on public.shelf_life_rules to authenticated;
grant usage on sequence public.shelf_life_rules_id_seq to authenticated;

-- the most specific active rule for an item on a date:  item+season > item > category+season > category > everything+season > everything.
-- Among seasons, the shorter range wins, then the newer rule. No rule at all -> null (feature off).
create or replace function public.shelf_life_for(p_item uuid, p_date date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_date, (now() at time zone 'Asia/Dhaka')::date); md int := extract(month from d)::int * 100 + extract(day from d)::int;
        it public.items; r public.shelf_life_rules;
begin
  select * into it from public.items where id = p_item;
  if not found then return null; end if;
  select * into r from public.shelf_life_rules s
  where s.active
    and (s.item_id = p_item or (s.item_id is null and s.category is not null and s.category = it.category) or (s.item_id is null and s.category is null))
    and (s.start_month is null
         or (case when s.start_month * 100 + s.start_day <= s.end_month * 100 + s.end_day
                  then md between s.start_month * 100 + s.start_day and s.end_month * 100 + s.end_day
                  else md >= s.start_month * 100 + s.start_day or md <= s.end_month * 100 + s.end_day end))
  order by (case when s.item_id is not null then 3 when s.category is not null then 2 else 1 end) desc,
           (s.start_month is not null) desc,
           (case when s.start_month is null then 0
                 when s.start_month * 31 + s.start_day <= s.end_month * 31 + s.end_day then (s.end_month * 31 + s.end_day) - (s.start_month * 31 + s.start_day)
                 else 372 - ((s.start_month * 31 + s.start_day) - (s.end_month * 31 + s.end_day)) end) asc,
           s.id desc
  limit 1;
  if not found then return null; end if;
  return jsonb_build_object('rule_id', r.id, 'scope', case when r.item_id is not null then 'item' when r.category is not null then 'category' else 'all' end,
    'season', r.season_label, 'value', r.value, 'unit', r.unit, 'hours', case r.unit when 'days' then r.value * 24 else r.value end, 'date', d);
end $$;
create or replace function public.shelf_life_hours(p_item uuid, p_date date default null) returns numeric
language sql stable security definer set search_path = public as $$
  select (public.shelf_life_for(p_item, p_date) ->> 'hours')::numeric;
$$;

-- ---------- (f) invoice templates and print profiles ----------
create table if not exists public.invoice_templates (
  id bigserial primary key,
  name text not null check (length(btrim(name)) > 0),
  kind text not null check (kind in ('a4', 'thermal58', 'thermal80', 'label', 'common')),
  header jsonb not null default '{}',                    -- per language: {"bn": "...", "mix": "...", "en": "..."}
  footer jsonb not null default '{}',
  show_flags jsonb not null default '{}',               -- e.g. {"logo":true,"customer":true,"receipt_no":true,"item_code":false,"discount":true,"barcode":false}
  logo_ref text,                                         -- storage path or url
  vat_line_on boolean not null default false,           -- a printed VAT line also needs the rule vat_on
  paper_width_mm numeric check (paper_width_mm is null or paper_width_mm > 0),
  margins jsonb not null default '{}',                   -- {"top":..,"right":..,"bottom":..,"left":..} mm
  font_scale numeric not null default 1 check (font_scale > 0),
  location_id int references public.locations(id),      -- null = all locations
  is_default boolean not null default false,            -- the default of its kind for its location (or for all)
  active boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid
);
create unique index if not exists invoice_templates_default_uq on public.invoice_templates (kind, coalesce(location_id, 0)) where is_default and active;
drop trigger if exists audit_invoice_templates on public.invoice_templates;
create trigger audit_invoice_templates after insert or update or delete on public.invoice_templates for each row execute function public.log_change('id');

create table if not exists public.print_profiles (
  id bigserial primary key,
  name text not null check (length(btrim(name)) > 0),
  location_id int references public.locations(id),      -- null = all
  device_key text,                                       -- a device name the app stores; null = any device
  printer_type text not null check (printer_type in ('a4', 'thermal', 'label', 'other')),
  paper_size text,                                       -- free text from an editable list, e.g. A4 / 58mm / 80mm
  paper_width_mm numeric check (paper_width_mm is null or paper_width_mm > 0),
  template_id bigint references public.invoice_templates(id) on delete set null,
  active boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid
);
drop trigger if exists audit_print_profiles on public.print_profiles;
create trigger audit_print_profiles after insert or update or delete on public.print_profiles for each row execute function public.log_change('id');

alter table public.invoice_templates enable row level security;
alter table public.print_profiles enable row level security;
drop policy if exists invtpl_read on public.invoice_templates;
drop policy if exists invtpl_write on public.invoice_templates;
drop policy if exists printprof_read on public.print_profiles;
drop policy if exists printprof_write on public.print_profiles;
create policy invtpl_read on public.invoice_templates for select to authenticated using (public.is_active());
create policy invtpl_write on public.invoice_templates for all to authenticated using (public.has_grant('settings_invoice')) with check (public.has_grant('settings_invoice'));
create policy printprof_read on public.print_profiles for select to authenticated using (public.is_active());
create policy printprof_write on public.print_profiles for all to authenticated using (public.has_grant('settings_invoice')) with check (public.has_grant('settings_invoice'));
revoke all on public.invoice_templates, public.print_profiles from anon, authenticated;
grant select, insert, update, delete on public.invoice_templates, public.print_profiles to authenticated;
grant usage on sequence public.invoice_templates_id_seq, public.print_profiles_id_seq to authenticated;

-- the template to print with: the location's default of that kind, else the all-location default, else null
create or replace function public.template_for(p_kind text, p_loc int) returns public.invoice_templates
language sql stable security definer set search_path = public as $$
  select t.* from public.invoice_templates t
  where public.is_active() and t.active and t.is_default and t.kind = p_kind and (t.location_id = p_loc or t.location_id is null)
  order by (t.location_id is null) limit 1;
$$;

-- ---------- (h) saved report views, (i) favourites ----------
create table if not exists public.report_views (
  id bigserial primary key,
  owner_id uuid not null default auth.uid(),
  name text not null check (length(btrim(name)) > 0),
  report_code text not null,
  params jsonb not null default '{}',                    -- filters / grouping / period the view remembers (no data is stored)
  shared boolean not null default false,                 -- shared = every active user may open the view (the report's own access still applies)
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists report_views_owner on public.report_views (owner_id, report_code);
drop trigger if exists audit_report_views on public.report_views;
create trigger audit_report_views after insert or update or delete on public.report_views for each row execute function public.log_change('id');
alter table public.report_views enable row level security;
drop policy if exists rv_read on public.report_views;
drop policy if exists rv_ins on public.report_views;
drop policy if exists rv_upd on public.report_views;
drop policy if exists rv_del on public.report_views;
create policy rv_read on public.report_views for select to authenticated using (owner_id = auth.uid() or (shared and public.is_active()) or public.is_owner());
create policy rv_ins on public.report_views for insert to authenticated with check (owner_id = auth.uid() and public.is_active());
create policy rv_upd on public.report_views for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy rv_del on public.report_views for delete to authenticated using (owner_id = auth.uid() or public.is_owner());
revoke all on public.report_views from anon, authenticated;
grant select, insert, update, delete on public.report_views to authenticated;
grant usage on sequence public.report_views_id_seq to authenticated;

create table if not exists public.user_favourites (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null,                                    -- form | report | item | module ...
  key text not null,
  pinned boolean not null default false,
  uses int not null default 0 check (uses >= 0),
  last_used timestamptz,
  primary key (user_id, kind, key)
);
alter table public.user_favourites enable row level security;
drop policy if exists fav_own on public.user_favourites;
create policy fav_own on public.user_favourites for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.user_favourites from anon, authenticated;
grant select, insert, update, delete on public.user_favourites to authenticated;

-- count one use (most-used list) / pin or unpin
create or replace function public.touch_favourite(p_kind text, p_key text) returns void
language sql security definer set search_path = public as $$
  insert into public.user_favourites (user_id, kind, key, uses, last_used) select auth.uid(), left(p_kind, 40), left(p_key, 120), 1, now() where public.is_active()
  on conflict (user_id, kind, key) do update set uses = public.user_favourites.uses + 1, last_used = now();
$$;
create or replace function public.set_pin(p_kind text, p_key text, p_pinned boolean) returns void
language sql security definer set search_path = public as $$
  insert into public.user_favourites (user_id, kind, key, pinned) select auth.uid(), left(p_kind, 40), left(p_key, 120), coalesce(p_pinned, false) where public.is_active()
  on conflict (user_id, kind, key) do update set pinned = coalesce(p_pinned, false);
$$;

-- owner-set defaults per role (shown in front for anyone with that role until they pin their own)
create table if not exists public.role_favourites (
  role_code text not null references public.roles(code) on delete cascade,
  kind text not null, key text not null, sort int not null default 0,
  primary key (role_code, kind, key)
);
alter table public.role_favourites enable row level security;
drop policy if exists rolefav_read on public.role_favourites;
drop policy if exists rolefav_owner on public.role_favourites;
create policy rolefav_read on public.role_favourites for select to authenticated using (public.is_active());
create policy rolefav_owner on public.role_favourites for all to authenticated using (public.is_owner()) with check (public.is_owner());
revoke all on public.role_favourites from anon, authenticated;
grant select, insert, update, delete on public.role_favourites to authenticated;

-- ---------- (j) discount by amount OR percent ----------
alter table public.sales add column if not exists discount_kind text check (discount_kind is null or discount_kind in ('amount', 'percent'));
alter table public.sales add column if not exists discount_input numeric check (discount_input is null or discount_input >= 0);   -- what was typed: the amount, or the percent

-- the old 11-argument signature is replaced by the same function with two OPTIONAL trailing arguments (old calls resolve to it unchanged)
drop function if exists public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz);

create or replace function public.record_sale2(
  p_client uuid, p_loc int, p_lines jsonb, p_discount numeric, p_payments jsonb,
  p_customer_mobile text, p_customer_name text, p_sale_type text, p_note text, p_quick boolean, p_sold_at timestamptz default null,
  p_discount_kind text default null, p_discount_input numeric default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  n int; sid text; s public.sales; ln jsonb; it public.items; qty numeric; pr numeric; amt numeric; shown numeric;
  out_lines jsonb := '[]'; sub numeric := 0; disc numeric := coalesce(p_discount, 0); ov boolean;
  any_ov boolean := false; any_drift boolean := false; any_custom boolean := false;
  at_ timestamptz := coalesce(p_sold_at, now()); stype text := coalesce(p_sale_type, 'retail');
  pay jsonb; paid_sum numeric := 0; due numeric; mob text; cust public.customers; tend numeric; modes text[] := '{}'; pm text; lim jsonb; bal numeric;
  needcust boolean; dkind text; dinput numeric; credit_over boolean := false; em text; ov_ok boolean;
begin
  perform set_config('bos.em_used', '', true);
  if not public.can_do('POS', 'enter') then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
  end if;
  if at_ > now() + interval '10 minutes' or at_ < now() - make_interval(hours => coalesce(public.rule_num('pos_offline_hours'), 72)::int) then at_ := now(); end if;
  if stype not in ('retail', 'wholesale') then raise exception 'bad_sale_type'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  -- discount given as an AMOUNT (default, also every old call) or as a PERCENT of the subtotal (computed here, 2 decimals)
  dkind := coalesce(nullif(btrim(p_discount_kind), ''), 'amount');
  if dkind not in ('amount', 'percent') then raise exception 'bad_discount_kind'; end if;
  if dkind = 'percent' then
    dinput := p_discount_input;
    if dinput is null or dinput = 'NaN'::numeric or dinput < 0 or dinput > 100 then raise exception 'bad_discount'; end if;
    disc := 0;                                        -- computed after the subtotal is known
  else
    dinput := coalesce(p_discount_input, p_discount, 0);
    if dinput = 'NaN'::numeric then raise exception 'bad_discount'; end if;
    dinput := round(dinput, 2); disc := dinput;
  end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    ov := false;
    if nullif(ln->>'item_id', '') is not null then
      select * into it from public.items where id = (ln->>'item_id')::uuid;
      if not found or not it.is_active then raise exception 'item_not_found'; end if;
      qty := (ln->>'qty')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      pr := it.sell_price;
      if (ln->>'override')::boolean is true then
        if public.rule_on('pos_override_manager') then
          if ov_ok is null then ov_ok := public.rule_ok('price_override', p_loc, null, null, 'sale'); end if;      -- one approval covers every price change in this sale
          if not ov_ok then raise exception 'override_needs_approval'; end if;
        end if;
        pr := (ln->>'price')::numeric;
        if pr is null or pr = 'NaN'::numeric or pr < 0 then raise exception 'bad_price'; end if;
        if pr is distinct from it.sell_price then ov := true; any_ov := true; end if;
      else
        shown := nullif(ln->>'price', '')::numeric;
        if shown is not null and shown is distinct from it.sell_price then any_drift := true; end if;
      end if;
      if pr is null then raise exception 'no_price'; end if;
      amt := round(qty * pr, 2);
      out_lines := out_lines || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'unit', it.unit, 'qty', qty, 'price', pr, 'amount', amt, 'override', ov);
    elsif ln ? 'qty' and ln ? 'price' then            -- an item that is not in the list
      qty := (ln->>'qty')::numeric; pr := (ln->>'price')::numeric;
      if qty is null or qty = 'NaN'::numeric or qty <= 0 then raise exception 'bad_qty'; end if;
      if pr is null or pr = 'NaN'::numeric or pr <= 0 then raise exception 'bad_price'; end if;
      if nullif(btrim(ln->>'name'), '') is null then raise exception 'name_required'; end if;
      if public.rule_txt('pos_unlisted') = 'block' then raise exception 'unlisted_blocked'; end if;
      amt := round(qty * pr, 2); any_custom := coalesce(public.rule_txt('pos_unlisted'), 'flag') = 'flag';
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(btrim(ln->>'name'), 80), 'unit', left(coalesce(ln->>'unit', ''), 20), 'qty', qty, 'price', pr, 'amount', amt, 'override', false, 'custom', true);
    else                                              -- quick sale
      amt := (ln->>'amount')::numeric;
      if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
      out_lines := out_lines || jsonb_build_object('item_id', null, 'name', left(coalesce(nullif(ln->>'name', ''), 'Quick sale'), 80), 'qty', 1, 'price', amt, 'amount', amt, 'override', false);
    end if;
    sub := sub + amt;
  end loop;
  if dkind = 'percent' then
    disc := round(sub * dinput / 100, 2);
    -- the phone shows the discount it computed from the percent; a half-cent case can round the other way here. Within one paisa (0.01) the amount the
    -- customer was shown wins, so the bill never asks for a paisa more or less than the screen said (never beyond 0.01, never outside 0..subtotal).
    if p_discount is not null and abs(p_discount - disc) <= 0.01 and p_discount between 0 and sub then disc := round(p_discount, 2); end if;
  end if;
  if disc < 0 or disc > sub then raise exception 'bad_discount'; end if;
  if disc > 0 and not public.rule_on(case dkind when 'percent' then 'discount_mode_percent_on' else 'discount_mode_amount_on' end) then raise exception 'discount_mode_off'; end if;
  select value into lim from public.location_settings where location_id = p_loc and key = 'discount_limit';
  if disc > 0 and public.rule_on('pos_discount_manager') and (lim is null or jsonb_typeof(lim) = 'null' or disc > (lim #>> '{}')::numeric)
     and not public.rule_ok('discount_over_limit', p_loc, disc, null, 'sale') then raise exception 'discount_needs_approval'; end if;   -- no limit written = a granted role is needed
  -- payments
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    pm := pay->>'mode';
    if pm is null or pm not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
    amt := (pay->>'amount')::numeric;
    if amt is null or amt = 'NaN'::numeric or amt <= 0 then raise exception 'bad_amount'; end if;
    amt := round(amt, 2); paid_sum := paid_sum + amt;
    if not pm = any (modes) then modes := modes || pm; end if;
  end loop;
  if paid_sum > sub - disc then raise exception 'overpaid'; end if;
  due := sub - disc - paid_sum;
  -- customer
  mob := case when nullif(btrim(p_customer_mobile), '') is not null then public.norm_mobile(p_customer_mobile) end;
  needcust := (due > 0 and public.rule_on('pos_customer_on_due')) or (stype = 'wholesale' and public.rule_on('pos_customer_on_wholesale')) or (disc > 0 and public.rule_on('pos_customer_on_discount'));
  if needcust and mob is null and not public.rule_ok('sale_without_customer', p_loc, null, null, 'sale') then raise exception 'customer_required'; end if;
  if mob is not null then
    select * into cust from public.customers where mobile = mob for update;
    if not found then
      if nullif(btrim(p_customer_name), '') is null then raise exception 'customer_name_required'; end if;
      insert into public.customers (mobile, name, type, created_by) values (mob, left(btrim(p_customer_name), 80), stype, auth.uid()) returning * into cust;
    elsif stype = 'wholesale' and cust.type <> 'wholesale' then
      update public.customers set type = 'wholesale' where id = cust.id;
    end if;
    if not cust.active then raise exception 'customer_inactive'; end if;
    if due > 0 and cust.credit_limit is not null and coalesce(public.rule_txt('pos_credit_mode'), 'block') <> 'off' then
      bal := coalesce(public.customer_balance(cust.id), 0);
      if bal + due > cust.credit_limit then
        credit_over := true;
        if coalesce(public.rule_txt('pos_credit_mode'), 'block') = 'block' and not public.rule_ok('credit_over_limit', p_loc, due, null, 'sale') then raise exception 'over_credit_limit'; end if;
      end if;
    end if;
  end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.serials (form_code, location_id, last) values ('POS', p_loc, 1)
    on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
  begin
    insert into public.sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, tendered, customer, note, quick,
        created_by, created_staff, customer_id, sale_type, paid, due_amount, discount_kind, discount_input)
      values (p_client, p_loc, n, at_, (at_ at time zone 'Asia/Dhaka')::date, out_lines, sub, disc, sub - disc,
        case when paid_sum = 0 then 'due' when due = 0 and array_length(modes, 1) = 1 then modes[1] else 'split' end,
        (select nullif(x->>'tendered', '')::numeric from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) x where x->>'mode' = 'cash' limit 1),
        case when cust.id is not null then cust.name end, left(nullif(btrim(p_note), ''), 200), coalesce(p_quick, false),
        auth.uid(), sid, cust.id, stype, paid_sum, due, case when disc > 0 then dkind end, case when disc > 0 then dinput end)
      returning * into s;
  exception when unique_violation then
    select * into s from public.sales where client_id = p_client and created_by = auth.uid();
    if found then return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', s.paid, 'due', s.due_amount, 'dup', true); end if;
    raise;
  end;
  for pay in select * from jsonb_array_elements(coalesce(p_payments, '[]'::jsonb)) loop
    insert into public.sale_payments (sale_id, customer_id, location_id, kind, mode, wallet, ref, amount, paid_at, created_by, created_staff)
      values (s.id, cust.id, p_loc, 'sale', pay->>'mode', left(nullif(pay->>'wallet', ''), 30), left(nullif(pay->>'ref', ''), 60), round((pay->>'amount')::numeric, 2), at_, auth.uid(), sid);
  end loop;
  -- exceptions for the owner (nothing is blocked here except the customer / credit rules above)
  if any_ov or any_drift then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, case when any_ov then 'price_override' else 'price_changed' end, 'yellow', s.total,
        case when any_ov then jsonb_build_object('bn', 'রসিদ ' || n || ': নির্ধারিত দামের বদলে অন্য দামে বিক্রি', 'en', 'Receipt ' || n || ': sold at a price different from the list price')
          else jsonb_build_object('bn', 'রসিদ ' || n || ': ফোনে দেখানো দাম আর তালিকার দাম আলাদা ছিল (তালিকার দাম ধরা হয়েছে)', 'en', 'Receipt ' || n || ': the price shown on the phone differed from the list price (list price used)') end);
  end if;
  if any_custom then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unlisted_item', 'yellow', s.total,
        jsonb_build_object('bn', 'রসিদ ' || n || ': তালিকায় নেই এমন আইটেম বিক্রি — আইটেম তালিকায় যোগ করুন', 'en', 'Receipt ' || n || ': an item that is not in the list was sold — add it to the item list'));
  end if;
  if disc > 0 then
    if lim is null or jsonb_typeof(lim) = 'null' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_no_limit', 'yellow', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট দেওয়া হয়েছে কিন্তু ডিসকাউন্টের সীমা সেটিংসে নেই', 'en', 'Receipt ' || n || ': a discount was given but no discount limit is set'));
    elsif disc > (lim #>> '{}')::numeric then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'discount_over_limit', 'red', disc,
          jsonb_build_object('bn', 'রসিদ ' || n || ': ডিসকাউন্ট সীমার উপরে', 'en', 'Receipt ' || n || ': discount above the limit'));
    end if;
  end if;
  if due > 0 and cust.id is null then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'unattributed_due', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': বাকি আছে কিন্তু কোনো গ্রাহক নেই — এই বাকি কোনো গ্রাহকের খাতায় নেই', 'en', 'Receipt ' || n || ': an amount is due but there is no customer — it is on nobody’s ledger'));
  end if;
  if credit_over then
    insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
      values (null, s.id, 'POS', p_loc, s.sale_date, 'credit_limit_override', 'yellow', due,
        jsonb_build_object('bn', 'রসিদ ' || n || ': গ্রাহকের বাকির সীমা পার হয়েছে (অনুমোদনকারী দিয়েছেন)', 'en', 'Receipt ' || n || ': the customer’s credit limit was exceeded (given by an approver)'));
  end if;
  for em in select unnest(string_to_array(nullif(current_setting('bos.em_used', true), ''), ',')) loop
    if em <> '' then
      insert into public.exceptions (entry_id, sale_id, form_code, location_id, entry_date, flag_code, level, amount, text)
        values (null, s.id, 'POS', p_loc, s.sale_date, 'emergency_used', 'yellow', s.total,
          jsonb_build_object('bn', 'রসিদ ' || n || ': জরুরি অনুমোদনে সেল (' || split_part(em, ':', 2) || ')', 'en', 'Receipt ' || n || ': sold on an emergency approval (' || split_part(em, ':', 2) || ')'));
    end if;
  end loop;
  return jsonb_build_object('id', s.id, 'receipt', s.receipt, 'total', s.total, 'paid', paid_sum, 'due', due, 'customer_id', cust.id, 'discount', disc);
end $$;

-- ---------- privileges: every new function is closed first, then opened to signed-in users only ----------
revoke all on function public.set_user_grant(uuid, text, int, timestamptz, boolean, text), public.has_grant(text, int),
  public.biz_ok(), public.biz_cost_ok(),
  public.fiscal_year_start(date), public.fiscal_year_end(date), public.week_start_date(date),
  public.save_supplier(uuid, jsonb), public.supplier_pick(), public.apply_item_patch(uuid, jsonb),
  public._unit_hop(uuid, text, text), public.unit_factor(uuid, text, text), public.convert_qty(uuid, numeric, text, text),
  public.set_unit_conversion(uuid, text, text, numeric, text), public.shelf_life_for(uuid, date), public.shelf_life_hours(uuid, date),
  public.template_for(text, int), public.touch_favourite(text, text), public.set_pin(text, text, boolean),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric) from public, anon, authenticated;
grant execute on function public.set_user_grant(uuid, text, int, timestamptz, boolean, text), public.has_grant(text, int),
  public.biz_ok(), public.biz_cost_ok(),
  public.fiscal_year_start(date), public.fiscal_year_end(date), public.week_start_date(date),
  public.save_supplier(uuid, jsonb), public.supplier_pick(),
  public.unit_factor(uuid, text, text), public.convert_qty(uuid, numeric, text, text),
  public.set_unit_conversion(uuid, text, text, numeric, text), public.shelf_life_for(uuid, date), public.shelf_life_hours(uuid, date),
  public.template_for(text, int), public.touch_favourite(text, text), public.set_pin(text, text, boolean),
  public.record_sale2(uuid, int, jsonb, numeric, jsonb, text, text, text, text, boolean, timestamptz, text, numeric) to authenticated;
-- apply_item_patch and _unit_hop stay internal (called by other security-definer functions only)

-- phase9 (reports) shows the discount kind of a sale through two views; rebuild them now that the discount columns exist, whichever file ran first
do $$ begin
  if to_regprocedure('public.rpt_views_refresh()') is not null then perform public.rpt_views_refresh(); end if;
end $$;

notify pgrst, 'reload schema';
-- ============================================================
-- BOS tool · Phase 9: REPORT ENGINE core + the P1 reports that need no new data capture.
-- Run AFTER phase3/4/5/6/7 (ALL_NEW.sql). Additive and idempotent: safe to run again. Nothing existing is changed or dropped.
-- Does not depend on phase8, and works in EITHER order: optional phase8 columns (sales.discount_kind / discount_input) and grants
-- (has_grant, view_cost, view_reports ...) are detected when used. The two views that show the discount kind are (re)built by
-- rpt_views_refresh(); phase8 calls it at its end when phase9 is already there, and phase9 calls it below, so the order does not matter.
--
-- What is here
--   report_brand_map   location -> brand (owner editable; brand is not stored on sales)
--   rpt_bill / rpt_daily / sales_fact / rpt_pay   read-only fact views (NOT readable by the app: only report_run reads them)
--   report_presets()   date presets; a preset that needs a missing rule (fiscal year, week start) is returned as null
--   report_catalog()   the list of reports for the UI (names, group, grant, filters, dims, measures)
--   report_run(key, filters, group, sort, page, compare)   ONE server function; user input never becomes SQL
--                      (keys are looked up in a fixed whitelist; values are quoted with %L after type checks)
--
-- Security
--   * every call needs the grant report_<group> or the phase8 grant view_reports (owner always may; the owner edits them in "Who may do what")
--   * rows are limited to can_loc() locations, always
--   * cost columns (cogs, gp, gp_pct, uncosted_pct) are not even computed unless owner / ITEM_COST view / grant view_cost
--   * customer mobile numbers are masked unless owner / POS approve / grant view_customer_mobile
--   * thresholds are RULES with no invented value. Fiscal year start (month + day) and week start are the phase8 settings
--     fiscal_year_start_month / fiscal_year_start_day / week_start (sun..sat) and use exactly the fallbacks phase8 documents
--     (calendar year, Saturday); the old phase9 draft rule week_start_dow is read only when week_start is empty. Aging buckets,
--     near-limit % and page size have no value: missing -> the result says "data needed" (page size: documented 50).
-- ============================================================

create index if not exists sales_date_loc on public.sales (sale_date, location_id);
create index if not exists exceptions_sale on public.exceptions (sale_id) where sale_id is not null;
create index if not exists sale_payments_paid_at on public.sale_payments (paid_at);
create index if not exists sale_payments_sale on public.sale_payments (sale_id) where sale_id is not null;

-- ---------- brand of a location (sales do not store a brand; the owner maps locations to brands) ----------
create table if not exists public.report_brand_map (
  location_id int primary key references public.locations(id),
  brand_code text not null,
  brand_bn text not null,
  brand_en text not null
);
alter table public.report_brand_map enable row level security;
revoke all on public.report_brand_map from public, anon;
grant select, insert, update, delete on public.report_brand_map to authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'report_brand_map' and policyname = 'report_brand_map_read') then
    create policy report_brand_map_read on public.report_brand_map for select to authenticated using (public.is_active());
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'report_brand_map' and policyname = 'report_brand_map_owner') then
    create policy report_brand_map_owner on public.report_brand_map for all to authenticated using (public.is_owner()) with check (public.is_owner());
  end if;
end $$;
-- the three brands named in the guidebook (docs/LANGUAGE.md); factories and the godown are left UNMAPPED on purpose (owner decides)
insert into public.report_brand_map (location_id, brand_code, brand_bn, brand_en)
  select l.id, v.b, v.bn, v.en from public.locations l join (values
    ('main', 'islamiya', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR'),
    ('branch2', 'islamiya', 'ইসলামিয়া মিষ্টি ঘর', 'ISLAMIYA MISTY GHAR'),
    ('mishti_bari', 'misty_bari', 'মিষ্টি বাড়ি', 'MISTY BARI'),
    ('al_cakes', 'al_cakiz', 'AL-CAKIZ', 'AL-CAKIZ')) v(code, b, bn, en) on v.code = l.code
  on conflict (location_id) do nothing;

-- ---------- rules ----------
-- The three settings below are IDENTICAL to the rows phase8 inserts (same module, labels, hints), so "on conflict do nothing" is harmless in either order.
insert into public.rules (key, module, kind, default_value, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('fiscal_year_start_month', 'settings', 'number', null, null, 1, 12, 'অর্থবছর শুরুর মাস (১-১২)', 'Fiscal year শুরুর মাস (1-12)', 'Fiscal year start month (1-12)', 'Empty = calendar year', 60),
 ('fiscal_year_start_day', 'settings', 'number', null, null, 1, 31, 'অর্থবছর শুরুর দিন', 'Fiscal year শুরুর দিন', 'Fiscal year start day', 'Empty = day 1', 61),
 ('week_start', 'settings', 'choice', null, '["sat","sun","mon","tue","wed","thu","fri"]', null, null, 'সপ্তাহ শুরু হয় যে দিনে', 'Week শুরু হয় যে দিনে', 'Week starts on', 'Empty = Saturday in reports', 62)
 on conflict (key) do nothing;
insert into public.rules (key, module, kind, default_value, unit, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('report_aging_buckets', 'reports', 'text', null, 'দিন', null, null, 'বাকির বয়স ভাগ (দিন, কমা দিয়ে, যেমন 7,30,60)', 'বাকির বয়স bucket (দিন, comma দিয়ে)', 'Receivable aging buckets in days, comma separated (e.g. 7,30,60)', 'ফাঁকা থাকলে বয়স ভাগ দেখাবে না', 'Empty = no aging buckets are shown', 62),
 ('report_near_limit_pct', 'reports', 'number', null, '%', 1, 1000, 'ক্রেডিট সীমার কত % হলে "সীমার কাছে" ধরা হবে', 'Credit limit এর কত % হলে "কাছাকাছি"', 'Share of the credit limit that counts as "near the limit"', 'ফাঁকা থাকলে "কাছাকাছি" দেখানো হবে না', 'Empty = no "near" status is shown', 63),
 ('report_page_size', 'reports', 'number', null, 'সারি', 10, 200, 'রিপোর্টের এক পাতায় কত সারি (ফাঁকা = ৫০)', 'Report এক পাতায় কত row (ফাঁকা = 50)', 'Rows per report page (empty = 50)', null, null, 64)
 on conflict (key) do nothing;
-- the first phase9 draft had its own week_start_dow rule; it is replaced by week_start. An unused row is removed; one the owner filled stays as a fallback only.
delete from public.rules where key = 'week_start_dow' and value is null;

-- ---------- grants: who may open which report group (owner always may; the owner edits these) ----------
-- Seeded ONLY when the grant does not exist yet: running this file again never brings back a grant the owner removed from a role.
do $$
declare r record;
begin
  for r in select * from (values
    ('report_sales', 60, 'রিপোর্ট: বিক্রি', 'Report: Sales', 'Reports: Sales'),
    ('report_pos', 61, 'রিপোর্ট: POS (দিনশেষ, বাতিল, কুইক)', 'Report: POS (day close, voids, quick)', 'Reports: POS (day close, voids, quick sales)'),
    ('report_cash', 62, 'রিপোর্ট: পেমেন্ট ও ওয়ালেট', 'Report: Payments & wallets', 'Reports: Payments and wallets'),
    ('report_customers', 63, 'রিপোর্ট: গ্রাহক ও বাকি', 'Report: Customers & dues', 'Reports: Customers and dues')) v(code, sort, bn, mix, en)
  loop
    if not exists (select 1 from public.grant_defs where grant_code = r.code) then
      insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
        values (r.code, 'reports', r.sort, r.bn, r.mix, r.en, 'once', null);
      -- start the same as today: whoever may approve on the POS form gets the report grants (the owner can change this at any time)
      insert into public.rule_grants (grant_code, role_code)
        select r.code, p.role_code from public.role_form_perms p where p.form_code = 'POS' and p.can_approve
        on conflict do nothing;
    end if;
  end loop;
end $$;

-- one row per sale LINE, kept by a trigger (the json is parsed once, when the sale is written, not on every report).
-- The bill discount is spread over the lines in proportion to their amount (net). NO cost columns anywhere in here.
create table if not exists public.sales_fact_t (
  sale_id uuid not null references public.sales(id) on delete cascade, line_no int not null,
  receipt int, day date not null, sold_at timestamptz not null, location_id int not null,
  staff text, status text, sale_type text, pay_mode text, customer_id uuid,
  item_id uuid, line_name text, line_unit text, line_kind text,
  qty numeric, price numeric, gross numeric, net numeric, disc numeric, override boolean,
  sale_total numeric, sale_discount numeric,      -- (older drafts also stored discount_kind / discount_pct here: no longer filled, the views read them from sales)
  first_of_item boolean,      -- first line of this item (or custom name) in its sale: makes "bills per item" a cheap count
  primary key (sale_id, line_no)
);
alter table public.sales_fact_t add column if not exists first_of_item boolean;
delete from public.sales_fact_t where first_of_item is null;      -- facts of an older draft are derived data: reloaded below
create index if not exists sales_fact_t_day on public.sales_fact_t (day, location_id);
create index if not exists sales_fact_t_item on public.sales_fact_t (item_id, day) where item_id is not null;
alter table public.sales_fact_t enable row level security;     -- no policy: nobody reads it directly
revoke all on public.sales_fact_t from public, anon, authenticated;

-- ---------- fact views ----------
-- rpt_bill and sales_fact show the discount kind / percent of a sale. Those come from the phase8 columns sales.discount_kind and
-- sales.discount_input, read LIVE from sales (nothing is copied into the facts, so old facts are never stale and no rebuild is needed).
--   kind    = 'none' when the sale has no discount, else its stored kind (a discount from before phase8 is 'amount')
--   percent = the typed percent when kind is 'percent', else null
-- If phase8 is not there yet the two columns are null ('n/a' in the report). rpt_views_refresh() (re)builds the two views; it is called
-- here and at the end of phase8, so applying the files in either order (or again) gives the same result.
create or replace function public.rpt_views_refresh() returns void
language plpgsql set search_path = public as $v$
declare dk text := 'null::text'; dp text := 'null::numeric';
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_kind') then
    dk := 'case when s.discount > 0 then coalesce(s.discount_kind, ''amount'') else ''none'' end';
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_input') then
      dp := 'case when s.discount > 0 and s.discount_kind = ''percent'' then s.discount_input end';
    end if;
  end if;

  -- one row per sale (all statuses). Money columns bills/gross/discount/net/paid/due count only done sales; *_raw / total are as stored.
  execute $q$
  create or replace view public.rpt_bill as
  select s.id as sale_id, s.receipt, s.sale_date as day, s.sold_at,
    extract(hour from s.sold_at at time zone 'Asia/Dhaka')::int as hour,
    extract(dow from s.sale_date)::int as dow,
    s.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
    bm.brand_code, bm.brand_bn, bm.brand_en,
    s.created_staff as staff, s.status, s.pay_mode, s.sale_type, s.customer_id, cu.name as customer_name, cu.mobile, s.quick,
    s.subtotal, s.discount as discount_raw, s.total, s.paid as paid_raw, s.due_amount as due_raw,
    (s.status = 'done')::int as bills, (s.status = 'void')::int as void_bills,
    case when s.status = 'done' then s.subtotal else 0 end as gross,
    case when s.status = 'done' then s.discount else 0 end as discount,
    case when s.status = 'done' then s.total else 0 end as net,
    case when s.status = 'done' then s.paid else 0 end as paid,
    case when s.status = 'done' then s.due_amount else 0 end as due,
    (s.status = 'done' and s.quick)::int as quick_bills,
    case when s.status = 'void' then s.total else 0 end as void_amt,
    (s.status = 'done' and s.discount > 0)::int as disc_bills,
    s.void_staff, s.void_note, s.void_at,
    case when s.status = 'done' then coalesce(x.ov, 0) else 0 end as override_lines,
    case when s.status = 'done' then coalesce(x.cu_, 0) else 0 end as custom_lines,
    case when s.status = 'done' then coalesce(x.qk, 0) else 0 end as quick_lines,
    $q$ || dk || $q$ as discount_kind, $q$ || dp || $q$ as discount_pct,
    case when s.status = 'done' and coalesce(ex.ol, false) then 1 else 0 end as over_limit_bills,
    case when s.status = 'done' and coalesce(ex.nl, false) then 1 else 0 end as no_limit_bills
  from public.sales s
  join public.locations lo on lo.id = s.location_id
  left join public.report_brand_map bm on bm.location_id = s.location_id
  left join public.customers cu on cu.id = s.customer_id
  left join (select sale_id, bool_or(flag_code = 'discount_over_limit') as ol, bool_or(flag_code = 'discount_no_limit') as nl
             from public.exceptions where sale_id is not null group by sale_id) ex on ex.sale_id = s.id
  left join lateral (
    select count(*) filter (where e->>'override' = 'true') as ov,
           count(*) filter (where e->>'custom' = 'true') as cu_,
           count(*) filter (where nullif(e->>'item_id', '') is null and coalesce(e->>'custom', '') <> 'true') as qk
    from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e) x on true $q$;

  execute $q$
  create or replace view public.sales_fact as
  select t.sale_id, t.line_no, t.receipt, t.day, t.sold_at,
    extract(hour from t.sold_at at time zone 'Asia/Dhaka')::int as hour,
    extract(dow from t.day)::int as dow,
    t.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
    bm.brand_code, bm.brand_bn, bm.brand_en,
    t.staff, t.status, t.sale_type, t.pay_mode, t.customer_id,
    t.item_id, it.code as item_code,
    coalesce(it.name_bn, t.line_name, 'Quick sale') as item_name,
    coalesce(it.name_en, it.name_bn, t.line_name, 'Quick sale') as item_name_en,
    it.category, coalesce(it.unit, t.line_unit) as unit,
    t.line_kind, t.qty, t.price, t.gross, t.net, t.disc, t.override, t.sale_total, t.sale_discount,
    $q$ || dk || $q$ as discount_kind, $q$ || dp || $q$ as discount_pct, t.first_of_item
  from public.sales_fact_t t
  left join public.sales s on s.id = t.sale_id
  join public.locations lo on lo.id = t.location_id
  left join public.report_brand_map bm on bm.location_id = t.location_id
  left join public.items it on it.id = t.item_id $q$;
  revoke all on public.rpt_bill, public.sales_fact from public, anon, authenticated;      -- a rebuilt view must never be readable by the app
end $v$;
revoke all on function public.rpt_views_refresh() from public, anon, authenticated;
do $$ begin perform public.rpt_views_refresh(); end $$;

-- the day x location x staff x payment mode x sale type rollup (a plain grouped view: no lines, no customer, fast on a phone)
create or replace view public.rpt_daily as
select s.sale_date as day, s.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en, s.created_staff as staff, s.pay_mode, s.sale_type,
  count(*) filter (where s.status = 'done') as bills,
  count(*) filter (where s.status = 'void') as void_bills,
  coalesce(sum(s.subtotal) filter (where s.status = 'done'), 0) as gross,
  coalesce(sum(s.discount) filter (where s.status = 'done'), 0) as discount,
  coalesce(sum(s.total) filter (where s.status = 'done'), 0) as net,
  coalesce(sum(s.paid) filter (where s.status = 'done'), 0) as paid,
  coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) as due,
  count(*) filter (where s.status = 'done' and s.quick) as quick_bills,
  coalesce(sum(s.total) filter (where s.status = 'void'), 0) as void_amt,
  count(*) filter (where s.status = 'done' and s.discount > 0) as disc_bills
from public.sales s
join public.locations lo on lo.id = s.location_id
left join public.report_brand_map bm on bm.location_id = s.location_id
group by s.sale_date, s.location_id, lo.name_bn, lo.name_en, bm.brand_code, bm.brand_bn, bm.brand_en, s.created_staff, s.pay_mode, s.sale_type;


-- loads the line facts of one sale (or, with null, of every sale that has none yet). Cast-safe: bad json gives null/0, never an error.
create or replace function public.rpt_fact_load(p_sale uuid) returns void
language sql security definer set search_path = public as $f$
  insert into public.sales_fact_t (sale_id, line_no, receipt, day, sold_at, location_id, staff, status, sale_type, pay_mode, customer_id,
    item_id, line_name, line_unit, line_kind, qty, price, gross, net, disc, override, sale_total, sale_discount, first_of_item)
  select s.id, e.ord::int, s.receipt, s.sale_date, s.sold_at, s.location_id, s.created_staff, s.status, s.sale_type, s.pay_mode, s.customer_id,
    it.id, nullif(e.v->>'name', ''), nullif(e.v->>'unit', ''),
    case when it.id is not null then 'listed' when e.v->>'custom' = 'true' then 'unlisted' else 'quick' end,
    q.qty, q.price, q.amount, q.amount * case when s.subtotal > 0 then s.total / s.subtotal else 1 end,
    q.amount - q.amount * case when s.subtotal > 0 then s.total / s.subtotal else 1 end,
    (e.v->>'override' = 'true'), s.total, s.discount,
    (row_number() over (partition by s.id, q.iid, e.v->>'name' order by e.ord) = 1)
  from public.sales s
  cross join lateral jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) with ordinality as e(v, ord)
  cross join lateral (select
      case when e.v->>'item_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.v->>'item_id')::uuid end as iid,
      case when e.v->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'qty')::numeric end as qty,
      case when e.v->>'price' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'price')::numeric end as price,
      case when e.v->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e.v->>'amount')::numeric else 0 end as amount) q
  left join public.items it on it.id = q.iid
  where (p_sale is not null and s.id = p_sale)
     or (p_sale is null and not exists (select 1 from public.sales_fact_t t where t.sale_id = s.id))
  on conflict (sale_id, line_no) do nothing;
$f$;

create or replace function public.rpt_fact_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin      -- a problem here must never stop a sale from being saved; report_fact_rebuild() repairs the facts
    if tg_op = 'UPDATE' then delete from public.sales_fact_t where sale_id = new.id; end if;
    perform public.rpt_fact_load(new.id);
  exception when others then
    raise warning 'rpt_fact: % (sale %)', sqlerrm, new.id;
  end;
  return null;
end $$;
drop trigger if exists rpt_fact on public.sales;
do $t$      -- the discount columns are in the 'update of' list when they exist (phase8); the facts do not store them, so this is only to be complete
declare extra text := '';
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_kind') then extra := extra || ', discount_kind'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sales' and column_name = 'discount_input') then extra := extra || ', discount_input'; end if;
  execute 'create trigger rpt_fact after insert or update of lines, status, subtotal, discount, total, location_id, sale_date, sold_at, created_staff, customer_id, sale_type, pay_mode'
    || extra || ' on public.sales for each row execute function public.rpt_fact_trg()';
end $t$;

-- the owner can rebuild the facts from the sales at any time (derived data only; sales are never touched)
create or replace function public.report_fact_rebuild() returns jsonb
language plpgsql security definer set search_path = public as $$
declare n bigint;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  delete from public.sales_fact_t;
  perform public.rpt_fact_load(null);
  select count(*) into n from public.sales_fact_t;
  return jsonb_build_object('fact_rows', n, 'sales', (select count(*) from public.sales));
end $$;

do $$ begin perform public.rpt_fact_load(null); end $$;      -- back-fill existing sales (does nothing for sales that already have facts)

-- one row per payment (sale payments and later collections)
create or replace view public.rpt_pay as
select p.id as pay_id, p.sale_id, (p.paid_at at time zone 'Asia/Dhaka')::date as day, p.paid_at,
  extract(hour from p.paid_at at time zone 'Asia/Dhaka')::int as hour,
  extract(dow from (p.paid_at at time zone 'Asia/Dhaka')::date)::int as dow,
  p.location_id, lo.name_bn as location_bn, coalesce(lo.name_en, lo.name_bn) as location_en,
  bm.brand_code, bm.brand_bn, bm.brand_en,
  p.created_staff as staff, p.kind, p.mode, p.wallet, p.ref, p.amount, p.voided,
  p.customer_id, cu.name as customer_name, cu.mobile
from public.sale_payments p
join public.locations lo on lo.id = p.location_id
left join public.report_brand_map bm on bm.location_id = p.location_id
left join public.customers cu on cu.id = p.customer_id;

revoke all on public.rpt_bill, public.rpt_daily, public.sales_fact, public.rpt_pay from public, anon, authenticated;
revoke all on function public.rpt_fact_load(uuid), public.rpt_fact_trg() from public, anon, authenticated;
revoke all on function public.report_fact_rebuild() from public, anon;
grant execute on function public.report_fact_rebuild() to authenticated;

-- ---------- permission helpers ----------
-- rpt_grant: the phase8 has_grant(code) (owner, role grant, personal grant, approved emergency window) when phase8 is installed, else the role grant
-- can_grant(code). A grant code that does not exist is simply false.
create or replace function public.rpt_grant(p text) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if to_regprocedure('public.has_grant(text,integer)') is not null then return public.has_grant(p); end if;
  return public.can_grant(p);
end $$;
-- a report group is open to: the owner, a holder of report_<group>, or a holder of view_reports (the same grant that opens biz_ok)
create or replace function public.rpt_access(p_group text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_grant('report_' || p_group) or public.rpt_grant('view_reports'));
$$;
-- cost: owner, ITEM_COST view, or the grants view_cost / view_profit (same as phase8 biz_cost_ok)
create or replace function public.rpt_cost_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.rpt_grant('view_cost') or public.rpt_grant('view_profit'));
$$;
create or replace function public.rpt_mobile_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('POS', 'approve') or public.rpt_grant('view_customer_mobile'));
$$;

-- ---------- small parsers: bad input raises 'bad_filter' and never reaches SQL as text ----------
create or replace function public.rpt_arr_text(j jsonb) returns text[]
language plpgsql immutable set search_path = public as $$
declare a text[];
begin
  if j is null or jsonb_typeof(j) = 'null' then return null; end if;
  if jsonb_typeof(j) = 'array' then
    if jsonb_array_length(j) > 200 then raise exception 'bad_filter'; end if;
    select coalesce(array_agg(e), '{}') into a from jsonb_array_elements_text(j) e;
  else a := array[j #>> '{}']; end if;
  if exists (select 1 from unnest(a) x where length(x) > 100) then raise exception 'bad_filter'; end if;
  if cardinality(a) = 0 then return null; end if;
  return a;
end $$;
create or replace function public.rpt_arr_int(j jsonb) returns int[]
language plpgsql immutable set search_path = public as $$
declare a text[] := public.rpt_arr_text(j);
begin
  if a is null then return null; end if;
  if exists (select 1 from unnest(a) x where x is null or x !~ '^[0-9]{1,9}$') then raise exception 'bad_filter'; end if;
  return a::int[];
end $$;
create or replace function public.rpt_arr_uuid(j jsonb) returns uuid[]
language plpgsql immutable set search_path = public as $$
declare a text[] := public.rpt_arr_text(j);
begin
  if a is null then return null; end if;
  if exists (select 1 from unnest(a) x where x is null or x !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then raise exception 'bad_filter'; end if;
  return a::uuid[];
end $$;
create or replace function public.rpt_num(j jsonb) returns numeric
language plpgsql immutable set search_path = public as $$
declare t text;
begin
  if j is null or jsonb_typeof(j) = 'null' then return null; end if;
  t := j #>> '{}';
  if t !~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then raise exception 'bad_filter'; end if;
  return t::numeric;
end $$;
create or replace function public.rpt_date(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or btrim(t) = '' then return null; end if;
  if t !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'bad_filter'; end if;
  return t::date;
exception when others then raise exception 'bad_filter';
end $$;

-- ---------- week / fiscal-year settings: the phase8 rules, with the fallbacks phase8 documents ----------
--   week_start (sun..sat)            -> day of week 0..6.  Empty -> the old draft rule week_start_dow (only if the owner filled it) -> Saturday
--   fiscal_year_start_month / _day   -> Empty month = calendar year (1), empty day = 1.  A day past the month end is cut to the last day.
-- The fiscal start is passed around as ONE int: month * 100 + day (e.g. 701 = 1 July). src tells whether a fallback was used.
create or replace function public.rpt_week_cfg() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i int := array_position(array['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'], lower(btrim(coalesce(public.rule_txt('week_start'), ''))));
        n numeric;
begin
  if i is not null then return jsonb_build_object('dow', i - 1, 'src', 'rule'); end if;
  n := public.rule_num('week_start_dow');
  if n is not null and n between 0 and 6 and n = trunc(n) then return jsonb_build_object('dow', n::int, 'src', 'legacy'); end if;
  return jsonb_build_object('dow', 6, 'src', 'fallback');
end $$;
create or replace function public.rpt_fy_cfg() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m numeric := public.rule_num('fiscal_year_start_month'); d numeric := public.rule_num('fiscal_year_start_day'); mm int; dd int;
begin
  mm := case when m between 1 and 12 and m = trunc(m) then m::int end;
  dd := case when d between 1 and 31 and d = trunc(d) then d::int end;
  return jsonb_build_object('code', coalesce(mm, 1) * 100 + coalesce(dd, 1), 'src', case when mm is null then 'fallback' else 'rule' end);
end $$;
-- first day of the fiscal year that contains p_date (p_code = month * 100 + day)
create or replace function public.rpt_fy_start(p_date date, p_code int) returns date
language sql immutable set search_path = public as $$
  select case when p_date < a.s then b.s else a.s end
  from (select extract(year from p_date)::int as y, (p_code / 100) as m, (p_code % 100) as d) v
  cross join lateral (select make_date(v.y, v.m, least(v.d, extract(day from (make_date(v.y, v.m, 1) + interval '1 month - 1 day'))::int)) as s) a
  cross join lateral (select make_date(v.y - 1, v.m, least(v.d, extract(day from (make_date(v.y - 1, v.m, 1) + interval '1 month - 1 day'))::int)) as s) b;
$$;

-- ---------- date presets ----------
create or replace function public.report_presets() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t date := (now() at time zone 'Asia/Dhaka')::date; ws int := (public.rpt_week_cfg() ->> 'dow')::int; fc int := (public.rpt_fy_cfg() ->> 'code')::int;
  wk date := t - ((extract(dow from t)::int - ws + 7) % 7); fs date := public.rpt_fy_start(t, fc); ms date := date_trunc('month', t)::date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'today', jsonb_build_object('from', t, 'to', t),
    'yesterday', jsonb_build_object('from', t - 1, 'to', t - 1),
    'last_7', jsonb_build_object('from', t - 6, 'to', t),
    'last_30', jsonb_build_object('from', t - 29, 'to', t),
    'this_month', jsonb_build_object('from', ms, 'to', t),
    'last_month', jsonb_build_object('from', (ms - interval '1 month')::date, 'to', ms - 1),
    'this_week', jsonb_build_object('from', wk, 'to', t),
    'last_week', jsonb_build_object('from', wk - 7, 'to', wk - 1),
    'this_fy', jsonb_build_object('from', fs, 'to', t),
    'last_fy', jsonb_build_object('from', public.rpt_fy_start(fs - 1, fc), 'to', fs - 1));
end $$;

-- ============================================================
-- THE WHITELIST CATALOGUE. Every expression that can ever appear in a report query is written here, once.
-- Tokens: {T} table alias, {D} the (possibly shifted) day, {WS} week start (0=Sun), {FYC} fiscal start (month * 100 + day), {MOBOK} mobile visible.
-- ============================================================
create or replace function public.rpt_dims(p_src text) returns jsonb
language sql immutable set search_path = public as $j$
  select $c${
   "day":{"time":1,"daily":1,"cols":[["day","{D}","দিন","Day","date"]]},
   "week":{"time":1,"daily":1,"need":"ws","cols":[["week","({D} - ((extract(dow from {D})::int - {WS} + 7) % 7))::date","সপ্তাহ (শুরুর দিন)","Week starting","date"]]},
   "month":{"time":1,"daily":1,"cols":[["month","date_trunc('month', {D})::date","মাস","Month","date"]]},
   "fy":{"time":1,"daily":1,"need":"fy","cols":[["fiscal_year","extract(year from public.rpt_fy_start({D}, {FYC}))::int","অর্থবছর (শুরুর সাল)","Fiscal year (start year)","int"]]},
   "location":{"daily":1,"cols":[["location_id","{T}.location_id","","","id"],["location_bn","{T}.location_bn","লোকেশন","Location","text"],["location_en","{T}.location_en","Location (EN)","Location (EN)","text"]]},
   "brand":{"daily":1,"cols":[["brand_code","coalesce({T}.brand_code, 'none')","","","id"],["brand_bn","coalesce({T}.brand_bn, 'ব্র্যান্ড ঠিক করা নেই')","ব্র্যান্ড","Brand","text"],["brand_en","coalesce({T}.brand_en, 'No brand set')","Brand (EN)","Brand (EN)","text"]]},
   "staff":{"daily":1,"cols":[["staff","coalesce({T}.staff, '-')","কর্মী","Staff","text"]]},
   "hour":{"cols":[["hour","{T}.hour","ঘণ্টা","Hour","int"]]},
   "weekday":{"cols":[["dow","{T}.dow","বার (০=রবি)","Weekday (0=Sun)","int"]]}
  }$c$::jsonb || case p_src
   when 'bill' then $c${
   "pay_mode":{"daily":1,"cols":[["pay_mode","{T}.pay_mode","পেমেন্ট ধরন","Payment","text"]]},
   "sale_type":{"daily":1,"cols":[["sale_type","{T}.sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"]]},
   "customer":{"cols":[["customer_id","coalesce({T}.customer_id::text, 'none')","","","id"],["customer_name","coalesce({T}.customer_name, '-')","গ্রাহক","Customer","text"],["mobile","case when {MOBOK} then {T}.mobile else left({T}.mobile, 3) || '****' || right({T}.mobile, 2) end","মোবাইল","Mobile","text"]]},
   "void_staff":{"cols":[["void_staff","coalesce({T}.void_staff, '-')","বাতিল করেছে","Voided by","text"]]},
   "void_reason":{"cols":[["void_reason","coalesce({T}.void_note, '-')","বাতিলের কারণ","Void reason","text"]]},
   "discount_kind":{"cols":[["discount_kind","coalesce({T}.discount_kind, 'n/a')","ছাড়ের ধরন","Discount kind","text"]]}
  }$c$::jsonb
   when 'line' then $c${
   "pay_mode":{"cols":[["pay_mode","{T}.pay_mode","পেমেন্ট ধরন","Payment","text"]]},
   "sale_type":{"cols":[["sale_type","{T}.sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"]]},
   "item":{"cols":[["item_id","coalesce({T}.item_id::text, 'none')","","","id"],["item_code","coalesce({T}.item_code, '-')","কোড","Code","text"],["item_name","{T}.item_name","আইটেম","Item","text"],["item_name_en","{T}.item_name_en","Item (EN)","Item (EN)","text"]]},
   "category":{"cols":[["category","coalesce({T}.category, '(none)')","ক্যাটাগরি","Category","text"]]},
   "line_kind":{"cols":[["line_kind","{T}.line_kind","লাইনের ধরন","Line kind","text"]]},
   "discount_kind":{"cols":[["discount_kind","coalesce({T}.discount_kind, 'n/a')","ছাড়ের ধরন","Discount kind","text"]]}
  }$c$::jsonb
   else $c${
   "mode":{"cols":[["mode","{T}.mode","মাধ্যম","Mode","text"]]},
   "wallet":{"cols":[["wallet","coalesce({T}.wallet, '-')","ওয়ালেট","Wallet","text"]]},
   "kind":{"cols":[["kind","{T}.kind","ধরন (সেল/আদায়)","Kind (sale/collection)","text"]]},
   "customer":{"cols":[["customer_id","coalesce({T}.customer_id::text, 'none')","","","id"],["customer_name","coalesce({T}.customer_name, '-')","গ্রাহক","Customer","text"],["mobile","case when {MOBOK} then {T}.mobile else left({T}.mobile, 3) || '****' || right({T}.mobile, 2) end","মোবাইল","Mobile","text"]]}
  }$c$::jsonb end;
$j$;

create or replace function public.rpt_meas(p_src text) returns jsonb
language sql immutable set search_path = public as $j$
  select case p_src
   when 'bill' then $c${
   "bills":{"expr":"coalesce(sum({T}.bills), 0)","bn":"বিল","en":"Bills","type":"int"},
   "gross":{"expr":"coalesce(sum({T}.gross), 0)","bn":"মোট (ছাড়ের আগে)","en":"Gross","type":"money"},
   "discount":{"expr":"coalesce(sum({T}.discount), 0)","bn":"ছাড়","en":"Discount","type":"money"},
   "net":{"expr":"coalesce(sum({T}.net), 0)","bn":"বিক্রি","en":"Sales","type":"money"},
   "discount_pct":{"expr":"round(100 * sum({T}.discount) / nullif(sum({T}.gross), 0), 2)","bn":"ছাড় %","en":"Discount %","type":"pct"},
   "avg_bill":{"expr":"round(sum({T}.net) / nullif(sum({T}.bills), 0), 2)","bn":"গড় বিল","en":"Avg bill","type":"money"},
   "paid":{"expr":"coalesce(sum({T}.paid), 0)","bn":"পরিশোধ","en":"Paid","type":"money"},
   "due":{"expr":"coalesce(sum({T}.due), 0)","bn":"বাকি","en":"Due","type":"money"},
   "void_bills":{"expr":"coalesce(sum({T}.void_bills), 0)","bn":"বাতিল বিল","en":"Voided bills","type":"int"},
   "void_amt":{"expr":"coalesce(sum({T}.void_amt), 0)","bn":"বাতিল টাকা","en":"Voided amount","type":"money"},
   "void_pct":{"expr":"round(100 * sum({T}.void_bills)::numeric / nullif(sum({T}.bills) + sum({T}.void_bills), 0), 2)","bn":"বাতিল %","en":"Void %","type":"pct"},
   "quick_bills":{"expr":"coalesce(sum({T}.quick_bills), 0)","bn":"কুইক বিল","en":"Quick bills","type":"int"},
   "disc_bills":{"expr":"coalesce(sum({T}.disc_bills), 0)","bn":"ছাড়ের বিল","en":"Bills with discount","type":"int"},
   "avg_discount":{"expr":"round(sum({T}.discount) / nullif(sum({T}.disc_bills), 0), 2)","bn":"ছাড়ের বিলে গড় ছাড়","en":"Avg discount per discounted bill","type":"money"},
   "share_pct":{"expr":"round(100 * sum({T}.net) / nullif(sum(sum({T}.net)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"},
   "override_lines":{"expr":"coalesce(sum({T}.override_lines), 0)","bn":"দাম বদলের লাইন","en":"Price-override lines","type":"int","daily":0},
   "over_limit_bills":{"expr":"coalesce(sum({T}.over_limit_bills), 0)","bn":"ছাড়ের সীমা পার বিল","en":"Bills over the discount limit","type":"int","daily":0},
   "no_limit_bills":{"expr":"coalesce(sum({T}.no_limit_bills), 0)","bn":"সীমা লেখা ছাড়া ছাড়ের বিল","en":"Discounts with no limit set","type":"int","daily":0},
   "custom_lines":{"expr":"coalesce(sum({T}.custom_lines), 0)","bn":"তালিকা-বহির্ভূত লাইন","en":"Unlisted lines","type":"int","daily":0},
   "customers":{"expr":"count(distinct {T}.customer_id)","bn":"গ্রাহক","en":"Customers","type":"int","daily":0},
   "first_sale":{"expr":"min({T}.day) filter (where {T}.bills = 1)","bn":"প্রথম কেনা","en":"First purchase","type":"date","daily":0},
   "last_sale":{"expr":"max({T}.day) filter (where {T}.bills = 1)","bn":"শেষ কেনা","en":"Last purchase","type":"date","daily":0}
  }$c$::jsonb
   when 'line' then $c${
   "qty":{"expr":"coalesce(round(sum({T}.qty), 3), 0)","bn":"পরিমাণ","en":"Qty","type":"num"},
   "lines":{"expr":"count(*)","bn":"লাইন","en":"Lines","type":"int"},
   "bills":{"expr":"count(distinct {T}.sale_id)","bn":"বিল","en":"Bills","type":"int"},
   "gross":{"expr":"coalesce(round(sum({T}.gross), 2), 0)","bn":"মোট (ছাড়ের আগে)","en":"Gross","type":"money"},
   "disc":{"expr":"coalesce(round(sum({T}.disc), 2), 0)","bn":"ছাড় (ভাগ করা)","en":"Discount (allocated)","type":"money"},
   "net":{"expr":"coalesce(round(sum({T}.net), 2), 0)","bn":"বিক্রি","en":"Sales","type":"money"},
   "avg_price":{"expr":"round(sum({T}.gross) / nullif(sum({T}.qty), 0), 2)","bn":"গড় দাম","en":"Avg price","type":"money"},
   "share_pct":{"expr":"round(100 * sum({T}.net) / nullif(sum(sum({T}.net)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"},
   "override_lines":{"expr":"count(*) filter (where {T}.override)","bn":"দাম বদলের লাইন","en":"Price-override lines","type":"int"},
   "cogs":{"expr":"round(sum({T}.qty * c.cost_price) filter (where c.cost_price is not null), 2)","bn":"পণ্যের খরচ","en":"Cost of goods","type":"money","cost":1},
   "costed_net":{"expr":"sum({T}.net) filter (where c.cost_price is not null)","bn":"খরচ জানা বিক্রি","en":"Sales with known cost","type":"money","cost":1},
   "net_all":{"expr":"sum({T}.net)","bn":"মোট বিক্রি","en":"All sales","type":"money","cost":1},
   "gp":{"expr":"round(sum({T}.net) filter (where c.cost_price is not null) - sum({T}.qty * c.cost_price) filter (where c.cost_price is not null), 2)","bn":"মোট লাভ (খরচ জানা অংশে)","en":"Gross profit (costed part)","type":"money","cost":1},
   "gp_pct":{"expr":"round(100 * (sum({T}.net) filter (where c.cost_price is not null) - sum({T}.qty * c.cost_price) filter (where c.cost_price is not null)) / nullif(sum({T}.net) filter (where c.cost_price is not null), 0), 2)","bn":"লাভ %","en":"GP %","type":"pct","cost":1},
   "uncosted_pct":{"expr":"round(100 * (sum({T}.net) - coalesce(sum({T}.net) filter (where c.cost_price is not null), 0)) / nullif(sum({T}.net), 0), 2)","bn":"খরচ অজানা বিক্রি %","en":"Uncosted sales %","type":"pct","cost":1}
  }$c$::jsonb
   else $c${
   "payments":{"expr":"count(*)","bn":"পেমেন্ট","en":"Payments","type":"int"},
   "amount":{"expr":"coalesce(sum({T}.amount), 0)","bn":"টাকা","en":"Amount","type":"money"},
   "sale_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.kind = 'sale'), 0)","bn":"সেলের সময়ে","en":"At sale","type":"money"},
   "collection_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.kind = 'collection'), 0)","bn":"বাকি আদায়","en":"Collections","type":"money"},
   "cash_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'cash'), 0)","bn":"ক্যাশ","en":"Cash","type":"money"},
   "mobile_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'mobile'), 0)","bn":"মোবাইল","en":"Mobile money","type":"money"},
   "card_amount":{"expr":"coalesce(sum({T}.amount) filter (where {T}.mode = 'card'), 0)","bn":"কার্ড","en":"Card","type":"money"},
   "missing_ref":{"expr":"count(*) filter (where {T}.mode = 'mobile' and nullif(btrim({T}.ref), '') is null)","bn":"রেফারেন্স ছাড়া","en":"Without reference","type":"int"},
   "dup_refs":{"expr":"count(nullif(btrim({T}.ref), '')) - count(distinct nullif(btrim({T}.ref), ''))","bn":"ডুপ্লিকেট রেফারেন্স","en":"Duplicate references","type":"int"},
   "share_pct":{"expr":"round(100 * sum({T}.amount) / nullif(sum(sum({T}.amount)) over (), 0), 2)","tot":"100","bn":"অংশ %","en":"Share %","type":"pct"}
  }$c$::jsonb end;
$j$;

-- the reports. kind agg = grouped by whitelisted dims; raw = fixed query. group = access group (grant report_<group>).
create or replace function public.rpt_def(p_key text) returns jsonb
language sql immutable set search_path = public as $j$
  select ($c${
   "sales_summary":{"group":"sales","kind":"agg","src":"bill","bn":"বিক্রির সারসংক্ষেপ","en":"Sales summary","mix":"Sales সারসংক্ষেপ",
     "dims":["day","week","month","fy","location","brand","staff","pay_mode","sale_type"],"gdef":"",
     "measures":["bills","gross","discount","discount_pct","net","avg_bill","paid","due","void_bills","void_amt"],"sort":"net:desc","cmp":1,"cost_join":1},
   "sales_trend":{"group":"sales","kind":"agg","src":"bill","bn":"বিক্রির ধারা","en":"Sales trend","mix":"Sales এর ধারা",
     "dims":["day","week","month","fy","location","brand","staff"],"gdef":"day",
     "measures":["bills","net","avg_bill","discount","void_bills"],"sort":"@dim","cmp":1},
   "sales_combined":{"group":"sales","kind":"agg","src":"bill","bn":"একত্রিত দোকান/ব্র্যান্ড-ওয়াইজ","en":"Combined by shop / brand","mix":"একত্রিত দোকান/Brand-wise",
     "dims":["location","brand"],"gdef":"location",
     "measures":["bills","gross","discount","net","avg_bill","share_pct","paid","due","void_amt"],"sort":"net:desc","cmp":1,"cost_join":1},
   "item_sales":{"group":"sales","kind":"agg","src":"line","bn":"আইটেম-ওয়াইজ বিক্রি","en":"Item-wise sales","mix":"Item-wise বিক্রি",
     "dims":["item","category","day","week","month","fy","location","brand","staff","sale_type"],"gdef":"item",
     "measures":["qty","bills","gross","disc","net","avg_price","share_pct","override_lines","cogs","gp","gp_pct","uncosted_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done'"},
   "category_sales":{"group":"sales","kind":"agg","src":"line","bn":"ক্যাটাগরি-ওয়াইজ বিক্রি","en":"Category-wise sales","mix":"Category-wise বিক্রি",
     "dims":["category","item","day","week","month","fy","location","brand","staff","sale_type"],"gdef":"category",
     "measures":["qty","bills","gross","disc","net","share_pct","cogs","gp","gp_pct","uncosted_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done'"},
   "receipt_register":{"group":"sales","kind":"raw","bn":"রসিদ তালিকা","en":"Receipt register","mix":"Receipt তালিকা","nocompare":1,
     "allow":["locations","brands","staff","modes","sale_type","customer","min_amount","max_amount","status","search"],"sort":"sold_at:desc",
     "columns":[["sale_id","","","id"],["receipt","রসিদ নং","Receipt #","int"],["day","দিন","Day","date"],["time","সময়","Time","text"],["sold_at","","","id"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["staff","কর্মী","Staff","text"],["sale_type","খুচরা/পাইকারি","Retail/Wholesale","text"],["pay_mode","পেমেন্ট","Payment","text"],["status","অবস্থা","Status","text"],["customer_name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["subtotal","মোট","Subtotal","money"],["discount","ছাড়","Discount","money"],["total","পরিশোধযোগ্য","Total","money"],["paid","পরিশোধ","Paid","money"],["due","বাকি","Due","money"]]},
   "hour_weekday":{"group":"sales","kind":"agg","src":"bill","bn":"সময় ও বার অনুযায়ী","en":"Hour and weekday","mix":"ঘণ্টা ও বার অনুযায়ী",
     "dims":["hour","weekday","location","brand"],"gdef":"hour","measures":["bills","net","avg_bill","share_pct"],"sort":"@dim","cmp":1},
   "retail_wholesale":{"group":"sales","kind":"agg","src":"bill","bn":"খুচরা বনাম পাইকারি","en":"Retail vs wholesale","mix":"খুচরা vs পাইকারি",
     "dims":["sale_type","location","brand","day","week","month","fy","staff"],"gdef":"sale_type",
     "measures":["bills","gross","discount","net","avg_bill","share_pct","due"],"sort":"net:desc","cmp":1},
   "discounts":{"group":"sales","kind":"agg","src":"bill","bn":"ডিসকাউন্ট ও দাম বদল","en":"Discounts and price overrides","mix":"Discount ও দাম বদল","only_bill":1,
     "dims":["staff","location","brand","day","week","month","fy","discount_kind","sale_type"],"gdef":"staff",
     "measures":["bills","disc_bills","gross","discount","discount_pct","avg_discount","over_limit_bills","no_limit_bills","override_lines","net"],"sort":"discount:desc","cmp":1},
   "pos_day_close":{"group":"pos","kind":"raw","bn":"দিনশেষ রিপোর্ট (POS)","en":"POS day close","mix":"দিনশেষ (POS) report","nocompare":1,
     "allow":["locations","brands","staff"],"sort":"day:desc",
     "columns":[["day","দিন","Day","date"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["bills","বিল","Bills","int"],["net","বিক্রি","Sales","money"],["discount","ছাড়","Discount","money"],["void_bills","বাতিল বিল","Voided bills","int"],["void_amt","বাতিল টাকা","Voided amount","money"],["due_created","নতুন বাকি","New due","money"],["cash_in","ক্যাশ (সেল)","Cash at sale","money"],["mobile_in","মোবাইল (সেল)","Mobile at sale","money"],["card_in","কার্ড (সেল)","Card at sale","money"],["cash_collections","ক্যাশ আদায়","Cash collections","money"],["mobile_collections","মোবাইল আদায়","Mobile collections","money"],["card_collections","কার্ড আদায়","Card collections","money"],["total_in","মোট জমা","Total received","money"],["expected_cash","ড্রয়ারে থাকার কথা (ক্যাশ)","Expected cash in drawer","money"]]},
   "voids":{"group":"pos","kind":"agg","src":"bill","bn":"বাতিল বিল","en":"Voids","mix":"বাতিল Bill",
     "dims":["staff","void_staff","void_reason","location","brand","day","week","month","fy"],"gdef":"staff",
     "measures":["void_bills","void_amt","bills","void_pct"],"sort":"void_amt:desc","cmp":1,"having":"sum({T}.void_bills) > 0"},
   "quick_unlisted":{"group":"pos","kind":"agg","src":"line","bn":"কুইক ও তালিকা-বহির্ভূত বিক্রি","en":"Quick and unlisted sales","mix":"Quick ও unlisted বিক্রি",
     "dims":["line_kind","item","staff","location","brand","day","week","month","fy"],"gdef":"line_kind",
     "measures":["lines","bills","qty","net","share_pct"],"sort":"net:desc","cmp":1,"base":"{T}.status = 'done' and {T}.line_kind <> 'listed'"},
   "payment_modes":{"group":"cash","kind":"agg","src":"pay","bn":"পেমেন্ট মাধ্যম অনুযায়ী","en":"By payment mode","mix":"Payment mode অনুযায়ী",
     "dims":["mode","wallet","kind","day","week","month","fy","location","brand","staff"],"gdef":"mode",
     "measures":["payments","sale_amount","collection_amount","amount","share_pct"],"sort":"amount:desc","cmp":1,"base":"not {T}.voided"},
   "wallet_recon":{"group":"cash","kind":"agg","src":"pay","bn":"ওয়ালেট/মোবাইল পেমেন্ট মিল","en":"Wallet reconciliation","mix":"Wallet মিল",
     "dims":["wallet","day","week","month","fy","location","brand","staff"],"gdef":"wallet",
     "measures":["payments","amount","missing_ref","dup_refs"],"sort":"amount:desc","cmp":1,"base":"not {T}.voided and {T}.mode = 'mobile'"},
   "collections":{"group":"cash","kind":"agg","src":"pay","bn":"বাকি আদায়","en":"Collections","mix":"বাকি আদায়",
     "dims":["day","week","month","fy","mode","wallet","staff","customer","location","brand"],"gdef":"day",
     "measures":["payments","amount","cash_amount","mobile_amount","card_amount","share_pct"],"sort":"@dim","cmp":1,"base":"not {T}.voided and {T}.kind = 'collection'"},
   "best_customers":{"group":"customers","kind":"agg","src":"bill","bn":"সেরা গ্রাহক","en":"Best customers","mix":"সেরা Customer","only_bill":1,
     "dims":["customer"],"gdef":"customer","measures":["bills","net","avg_bill","discount","due","first_sale","last_sale"],"sort":"net:desc","cmp":1,"base":"{T}.customer_id is not null"},
   "customer_dues":{"group":"customers","kind":"raw","bn":"গ্রাহকের কাছে পাওনা","en":"Due from customers","mix":"Customer এর কাছে পাওনা","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"balance:desc",
     "columns":[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["type","ধরন","Type","text"],["credit_limit","বাকির সীমা","Credit limit","money"],["balance","বাকি","Due","money"],["oldest_due","সবচেয়ে পুরনো বাকির তারিখ","Oldest due since","date"],["days_old","কত দিনের পুরনো","Days old","int"]]},
   "receivable_aging":{"group":"customers","kind":"raw","bn":"বাকির বয়স","en":"Receivable aging","mix":"বাকির বয়স","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"balance:desc"},
   "credit_limit_use":{"group":"customers","kind":"raw","bn":"ক্রেডিট সীমা ব্যবহার","en":"Credit-limit use","mix":"Credit limit ব্যবহার","nocompare":1,"nodate":1,
     "allow":["customer","search"],"sort":"use_pct:desc",
     "columns":[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["type","ধরন","Type","text"],["credit_limit","বাকির সীমা","Credit limit","money"],["balance","বাকি","Due","money"],["use_pct","সীমার % ব্যবহার","Limit used %","pct"],["status","অবস্থা","Status","text"]]}
  }$c$::jsonb) -> p_key;
$j$;

create or replace function public.rpt_keys() returns text[]
language sql immutable set search_path = public as $$ select array['sales_summary','sales_trend','sales_combined','item_sales','category_sales','receipt_register','hour_weekday','retail_wholesale','discounts',
  'pos_day_close','voids','quick_unlisted','payment_modes','wallet_recon','collections','best_customers','customer_dues','receivable_aging','credit_limit_use']; $$;

-- which filters each source can apply
create or replace function public.rpt_filters_for(p_src text) returns text[]
language sql immutable set search_path = public as $$
  select case p_src
    when 'bill' then array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount']
    when 'line' then array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount','items','categories']
    else array['locations','brands','staff','modes','customer','min_amount','max_amount'] end;
$$;

-- token replacement
create or replace function public.rpt_tok(p_expr text, p_al text, p_dexpr text, p_ws int, p_fym int, p_mobok boolean) returns text
language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(replace(p_expr, '{D}', p_dexpr), '{T}', p_al), '{WS}', coalesce(p_ws, 6)::text), '{FYC}', coalesce(p_fym, 101)::text),
                 '{MOBOK}', case when p_mobok then 'true' else 'false' end);
$$;

-- WHERE clause from the filters. Values are type-checked and quoted with %L; keys are looked up, never pasted.
create or replace function public.rpt_where(p_src text, p_al text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_allow text[], p_mobok boolean default false) returns jsonb
language plpgsql stable set search_path = public as $$
declare w text[] := '{}'; ign text[] := '{}'; k text; locs int[]; eff int[]; tx text[]; ux uuid[]; n1 numeric; n2 numeric; nb boolean := false; v text; col text;
begin
  for k in select jsonb_object_keys(p_flt) loop
    if k in ('from', 'to', 'preset', 'compare_mode') then continue; end if;
    if jsonb_typeof(p_flt -> k) = 'null' then continue; end if;
    if not (k = any (p_allow)) then ign := ign || left(k, 40); end if;
  end loop;
  locs := public.rpt_arr_int(p_flt -> 'locations');
  eff := case when locs is null then p_allowed else array(select unnest(p_allowed) intersect select unnest(locs)) end;
  w := w || format('%s.location_id = any (%L::int[])', p_al, eff);
  if p_from is not null then w := w || format('%s.day between %L::date and %L::date', p_al, p_from, p_to); end if;
  if 'brands' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'brands'); if tx is not null then w := w || format('%s.brand_code = any (%L::text[])', p_al, tx); end if; end if;
  if 'staff' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'staff'); if tx is not null then w := w || format('%s.staff = any (%L::text[])', p_al, tx); end if; end if;
  if 'modes' = any (p_allow) then tx := public.rpt_arr_text(p_flt -> 'modes');
    if tx is not null then w := w || format('%s.%s = any (%L::text[])', p_al, case when p_src = 'pay' then 'mode' else 'pay_mode' end, tx); end if; end if;
  if 'sale_type' = any (p_allow) and p_src <> 'pay' then v := p_flt ->> 'sale_type';
    if v is not null then w := w || format('%s.sale_type = %L', p_al, v); end if; end if;
  if 'customer' = any (p_allow) then ux := public.rpt_arr_uuid(p_flt -> 'customer');
    if ux is not null then w := w || format('%s.customer_id = any (%L::uuid[])', p_al, ux); nb := true; end if; end if;
  if 'items' = any (p_allow) and p_src = 'line' then ux := public.rpt_arr_uuid(p_flt -> 'items'); if ux is not null then w := w || format('%s.item_id = any (%L::uuid[])', p_al, ux); end if; end if;
  if 'categories' = any (p_allow) and p_src = 'line' then tx := public.rpt_arr_text(p_flt -> 'categories'); if tx is not null then w := w || format('%s.category = any (%L::text[])', p_al, tx); end if; end if;
  if 'min_amount' = any (p_allow) then n1 := public.rpt_num(p_flt -> 'min_amount'); n2 := public.rpt_num(p_flt -> 'max_amount');
    col := case p_src when 'bill' then 'total' when 'line' then 'sale_total' else 'amount' end;
    if n1 is not null then w := w || format('%s.%s >= %L::numeric', p_al, col, n1); nb := true; end if;
    if n2 is not null then w := w || format('%s.%s <= %L::numeric', p_al, col, n2); nb := true; end if; end if;
  if 'status' = any (p_allow) and p_src = 'bill' then v := p_flt ->> 'status';
    if v is not null then
      if v not in ('done', 'void') then raise exception 'bad_filter'; end if;
      w := w || format('%s.status = %L', p_al, v); nb := true; end if; end if;
  if 'search' = any (p_allow) and p_src = 'bill' then v := btrim(p_flt ->> 'search');
    if v is not null and v <> '' then
      if length(v) > 60 then raise exception 'bad_filter'; end if;
      w := w || format('(%s.receipt::text = %L or position(lower(%L) in lower(coalesce(%s.customer_name, ''''))) > 0 %s)', p_al, v, v, p_al,
        case when p_mobok then format('or position(%L in coalesce(%s.mobile, '''')) > 0', v, p_al) else '' end);
      nb := true; end if; end if;
  return jsonb_build_object('w', array_to_string(w, ' and '), 'ignored', to_jsonb(ign), 'needs_bill', nb);
end $$;

-- SQL text of one grouped query (plus joins to item_costs when the cost measures are wanted)
create or replace function public.rpt_agg_sql(p_src text, p_rel text, p_al text, p_gl text[], p_mkeys text[], p_where text, p_base text, p_having text,
  p_dexpr text, p_ws int, p_fym int, p_mobok boolean, p_nodim boolean, p_withcost boolean) returns text
language plpgsql stable set search_path = public as $$
declare dims jsonb := public.rpt_dims(p_src); meas jsonb := public.rpt_meas(p_src); sel text[] := '{}'; g text; c jsonb; mk text; ex text; n int := 0; sql text;
begin
  if not p_nodim then
    foreach g in array p_gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        sel := sel || (public.rpt_tok(c ->> 1, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(c ->> 0));
        n := n + 1;
      end loop;
    end loop;
  end if;
  foreach mk in array p_mkeys loop
    ex := case when p_nodim and meas -> mk ? 'tot' then meas -> mk ->> 'tot' else meas -> mk ->> 'expr' end;
    if p_src = 'line' and mk = 'bills' then      -- exact bill count without a slow count(distinct) when the grouping allows it
      if not p_nodim and 'item' = any (p_gl) then ex := 'count(*) filter (where {T}.first_of_item)';
      elsif (p_nodim or not (p_gl && array['item', 'category', 'line_kind'])) and p_where !~ '\.(item_id|category) = any' and coalesce(p_base, '') !~ 'line_kind' then ex := 'count(*) filter (where {T}.line_no = 1)'; end if;
    end if;
    sel := sel || (public.rpt_tok(ex, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ' as ' || quote_ident(mk));
  end loop;
  sql := 'select ' || array_to_string(sel, ', ') || ' from ' || p_rel || ' ' || p_al
    || case when p_withcost then ' left join public.item_costs c on c.item_id = ' || p_al || '.item_id' else '' end
    || ' where ' || p_where || coalesce(' and (' || public.rpt_tok(p_base, p_al, p_dexpr, p_ws, p_fym, p_mobok) || ')', '');
  if n > 0 and not p_nodim then sql := sql || ' group by ' || (select string_agg(i::text, ', ') from generate_series(1, n) i); end if;
  if p_having is not null and not p_nodim then sql := sql || ' having ' || public.rpt_tok(p_having, p_al, p_dexpr, p_ws, p_fym, p_mobok); end if;
  return sql;
end $$;

-- builds the rows query and the totals query of an agg report for one period
create or replace function public.rpt_agg_build(p_def jsonb, p_gl text[], p_mkeys text[], p_flt jsonb, p_allowed int[], p_from date, p_to date,
  p_dexpr text, p_ws int, p_fym int, p_mobok boolean, p_costok boolean) returns jsonb
language plpgsql stable set search_path = public as $$
declare src text := p_def ->> 'src'; al text := case src when 'bill' then 'b' when 'line' then 'f' else 'p' end;
  dims jsonb := public.rpt_dims(src); g text; c jsonb; needb boolean := coalesce((p_def ->> 'only_bill')::int = 1, false);
  wj jsonb; wl jsonb; rel text; nodim boolean := cardinality(p_gl) = 0; mk text; meas jsonb := public.rpt_meas(src);
  t text; tot text; ts text; tj text; conds text[] := '{}'; cj text; lw text; ign jsonb;
  extra text := ', cq.cogs, round(cq.costed_net - cq.cogs, 2) as gp, round(100 * (cq.costed_net - cq.cogs) / nullif(cq.costed_net, 0), 2) as gp_pct, round(100 * (cq.net_all - cq.costed_net) / nullif(cq.net_all, 0), 2) as uncosted_pct';
begin
  wj := public.rpt_where(src, al, p_flt, p_allowed, p_from, p_to, coalesce((select array_agg(x) from jsonb_array_elements_text(p_def -> 'allow') x), public.rpt_filters_for(src)), p_mobok);
  ign := wj -> 'ignored';
  if src = 'bill' then
    foreach g in array p_gl loop if coalesce((dims -> g ->> 'daily')::int, 0) = 0 then needb := true; end if; end loop;
    foreach mk in array p_mkeys loop if coalesce((meas -> mk ->> 'daily')::int, 1) = 0 then needb := true; end if; end loop;
    if (wj ->> 'needs_bill')::boolean then needb := true; end if;
    rel := case when needb then 'public.rpt_bill' else 'public.rpt_daily' end;
  else rel := case src when 'line' then 'public.sales_fact' else 'public.rpt_pay' end; end if;
  t := public.rpt_agg_sql(src, rel, al, p_gl, p_mkeys, wj ->> 'w', p_def ->> 'base', p_def ->> 'having', p_dexpr, p_ws, p_fym, p_mobok, nodim, src = 'line' and p_costok);
  tot := public.rpt_agg_sql(src, rel, al, p_gl, p_mkeys, wj ->> 'w', p_def ->> 'base', null, p_dexpr, p_ws, p_fym, p_mobok, true, src = 'line' and p_costok);
  if p_costok and coalesce((p_def ->> 'cost_join')::int, 0) = 1 then
    wl := public.rpt_where('line', 'f', p_flt, p_allowed, p_from, p_to, array['locations','brands','staff','modes','sale_type','customer','min_amount','max_amount'], p_mobok);
    lw := wl ->> 'w';
    ts := public.rpt_agg_sql('line', 'public.sales_fact', 'f', p_gl, array['cogs','costed_net','net_all'], lw, '{T}.status = ''done''', null, p_dexpr, p_ws, p_fym, p_mobok, nodim, true);
    tj := public.rpt_agg_sql('line', 'public.sales_fact', 'f', p_gl, array['cogs','costed_net','net_all'], lw, '{T}.status = ''done''', null, p_dexpr, p_ws, p_fym, p_mobok, true, true);
    if not nodim then
      foreach g in array p_gl loop
        for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
          conds := conds || format('bq.%I = cq.%I', c ->> 0, c ->> 0);      -- dimension columns are never null, so this can be a hash join
        end loop;
      end loop;
    end if;
    cj := coalesce(array_to_string(conds, ' and '), 'true'); if cj = '' then cj := 'true'; end if;
    t := format('select bq.*%s from (%s) bq left join (%s) cq on %s', extra, t, ts, cj);
    tot := format('select bq.*%s from (%s) bq cross join (%s) cq', extra, tot, tj);
  end if;
  return jsonb_build_object('t', t, 'tot', tot, 'ignored', ign);
end $$;

-- ============================================================
-- raw (non-grouped) reports: fixed SQL, only validated literals are inserted
-- ============================================================
create or replace function public.rpt_mobx(p_col text, p_ok boolean) returns text
language sql immutable set search_path = public as $$
  select case when p_ok then p_col else 'left(' || p_col || ', 3) || ''****'' || right(' || p_col || ', 2)' end;
$$;

create or replace function public.rpt_raw(p_key text, p_flt jsonb, p_allowed int[], p_from date, p_to date, p_mobok boolean, p_buckets int[], p_near numeric, p_today date) returns jsonb
language plpgsql stable set search_path = public as $$
declare def jsonb := public.rpt_def(p_key); al text[]; wj jsonb; wb text; wp text; sql text; tot text; cols jsonb; ign jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb;
  ux uuid[]; srch text; cfilter text := ''; alist text; i int; b text[] := '{}'; cond text; lo int; hi int; clist jsonb;
begin
  al := array(select jsonb_array_elements_text(def -> 'allow'));
  if p_key = 'receipt_register' then
    wj := public.rpt_where('bill', 'b', p_flt, p_allowed, p_from, p_to, al, p_mobok); wb := wj ->> 'w'; ign := wj -> 'ignored';
    sql := format($f$select b.sale_id, b.receipt, b.day, to_char(b.sold_at at time zone 'Asia/Dhaka', 'HH24:MI') as time, b.sold_at, b.location_id, b.location_bn, b.location_en,
      b.staff, b.sale_type, b.pay_mode, b.status, b.customer_name, %s as mobile, b.subtotal, b.discount_raw as discount, b.total, b.paid_raw as paid, b.due_raw as due
      from public.rpt_bill b where %s$f$, public.rpt_mobx('b.mobile', p_mobok), wb);
    tot := $f$count(*) as receipts, count(*) filter (where status = 'void') as void_receipts, coalesce(sum(subtotal) filter (where status = 'done'), 0) as subtotal,
      coalesce(sum(discount) filter (where status = 'done'), 0) as discount, coalesce(sum(total) filter (where status = 'done'), 0) as total,
      coalesce(sum(paid) filter (where status = 'done'), 0) as paid, coalesce(sum(due) filter (where status = 'done'), 0) as due$f$;
  elsif p_key = 'pos_day_close' then
    wj := public.rpt_where('bill', 'b', p_flt, p_allowed, p_from, p_to, al, p_mobok); wb := wj ->> 'w'; ign := wj -> 'ignored';
    wj := public.rpt_where('pay', 'p', p_flt, p_allowed, p_from, p_to, al, p_mobok); wp := wj ->> 'w';
    sql := format($f$with bb as (select b.day, b.location_id, b.location_bn, b.location_en, sum(b.bills) as bills, sum(b.net) as net, sum(b.discount) as discount,
        sum(b.void_bills) as void_bills, sum(b.void_amt) as void_amt, sum(b.due) as due_created
        from public.rpt_daily b where %s group by 1, 2, 3, 4),
      pb as (select p.day, p.location_id, p.location_bn, p.location_en,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'cash'), 0) as cash_in,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'mobile'), 0) as mobile_in,
        coalesce(sum(p.amount) filter (where p.kind = 'sale' and p.mode = 'card'), 0) as card_in,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'cash'), 0) as cash_collections,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'mobile'), 0) as mobile_collections,
        coalesce(sum(p.amount) filter (where p.kind = 'collection' and p.mode = 'card'), 0) as card_collections
        from public.rpt_pay p where not p.voided and %s group by 1, 2, 3, 4)
      select coalesce(bb.day, pb.day) as day, coalesce(bb.location_id, pb.location_id) as location_id, coalesce(bb.location_bn, pb.location_bn) as location_bn,
        coalesce(bb.location_en, pb.location_en) as location_en, coalesce(bb.bills, 0) as bills, coalesce(bb.net, 0) as net, coalesce(bb.discount, 0) as discount,
        coalesce(bb.void_bills, 0) as void_bills, coalesce(bb.void_amt, 0) as void_amt, coalesce(bb.due_created, 0) as due_created,
        coalesce(pb.cash_in, 0) as cash_in, coalesce(pb.mobile_in, 0) as mobile_in, coalesce(pb.card_in, 0) as card_in,
        coalesce(pb.cash_collections, 0) as cash_collections, coalesce(pb.mobile_collections, 0) as mobile_collections, coalesce(pb.card_collections, 0) as card_collections,
        coalesce(pb.cash_in + pb.mobile_in + pb.card_in + pb.cash_collections + pb.mobile_collections + pb.card_collections, 0) as total_in,
        coalesce(pb.cash_in + pb.cash_collections, 0) as expected_cash
      from bb full join pb on pb.day = bb.day and pb.location_id = bb.location_id$f$, wb, wp);
    tot := $f$sum(bills) as bills, sum(net) as net, sum(discount) as discount, sum(void_bills) as void_bills, sum(void_amt) as void_amt, sum(due_created) as due_created,
      sum(cash_in) as cash_in, sum(mobile_in) as mobile_in, sum(card_in) as card_in, sum(cash_collections) as cash_collections, sum(mobile_collections) as mobile_collections,
      sum(card_collections) as card_collections, sum(total_in) as total_in, sum(expected_cash) as expected_cash$f$;
  else
    -- customer reports: always all locations the caller may see; only customer / search filters apply
    ux := public.rpt_arr_uuid(p_flt -> 'customer');
    if ux is not null then cfilter := cfilter || format(' and cu.id = any (%L::uuid[])', ux); end if;
    srch := btrim(p_flt ->> 'search');
    if srch is not null and srch <> '' then
      if length(srch) > 60 then raise exception 'bad_filter'; end if;
      cfilter := cfilter || format(' and (position(lower(%L) in lower(cu.name)) > 0 %s)', srch, case when p_mobok then format('or position(%L in cu.mobile) > 0', srch) else '' end);
    end if;
    ign := (select coalesce(jsonb_agg(left(k, 40)), '[]'::jsonb) from jsonb_object_keys(p_flt) k
            where k not in ('from', 'to', 'preset', 'compare_mode') and not (k = any (al)) and jsonb_typeof(p_flt -> k) <> 'null');
    alist := format('%L::int[]', p_allowed);
    if p_key = 'customer_dues' then
      sql := format($f$with s as (select x.id, x.customer_id, x.sale_date, x.sold_at,
          x.total - coalesce(pp.v, 0) as rem
          from public.sales x left join (select sale_id, sum(amount) as v from public.sale_payments where not voided and sale_id is not null group by 1) pp on pp.sale_id = x.id
          where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s)),
        cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) as cr from s where s.rem > 0),
        c as (select p.customer_id, sum(p.amount) as coll from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        t as (select customer_id, sum(rem) as rem from s group by 1)
        select cu.id as customer_id, cu.name, %s as mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0) as balance, o.od as oldest_due, %L::date - o.od as days_old
        from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
        left join lateral (select min(k.sale_date) as od from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0)) o on true
        where t.rem - coalesce(c.coll, 0) > 0%s$f$, alist, alist, public.rpt_mobx('cu.mobile', p_mobok), p_today, cfilter);
      tot := 'count(*) as customers, sum(balance) as balance, count(*) filter (where credit_limit is null) as no_limit_set';
    elsif p_key = 'receivable_aging' then
      -- buckets come from the rule report_aging_buckets (no built-in values)
      if p_buckets is not null and cardinality(p_buckets) > 0 then
        for i in 1..cardinality(p_buckets) + 1 loop
          lo := case when i = 1 then 0 else p_buckets[i - 1] + 1 end;
          hi := case when i <= cardinality(p_buckets) then p_buckets[i] end;
          cond := case when hi is null then format('age >= %s', lo) else format('age between %s and %s', lo, hi) end;
          b := b || format('coalesce(sum(portion) filter (where %s), 0) as bucket_%s', cond, i);
        end loop;
      end if;
      sql := format($f$with s as (select x.id, x.customer_id, x.sale_date, x.sold_at,
          x.total - coalesce(pp.v, 0) as rem
          from public.sales x left join (select sale_id, sum(amount) as v from public.sale_payments where not voided and sale_id is not null group by 1) pp on pp.sale_id = x.id
          where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s)),
        cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) as cr from s where s.rem > 0),
        c as (select p.customer_id, sum(p.amount) as coll from public.sale_payments p where p.kind = 'collection' and not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        pt as (select k.customer_id, %L::date - k.sale_date as age, greatest(0, least(k.rem, k.cr - coalesce(c.coll, 0))) as portion from cum k left join c on c.customer_id = k.customer_id)
        select cu.id as customer_id, cu.name, %s as mobile, coalesce(sum(pt.portion), 0) as balance%s, max(pt.age) filter (where pt.portion > 0) as oldest_days
        from pt join public.customers cu on cu.id = pt.customer_id where true%s
        group by cu.id, cu.name, cu.mobile having coalesce(sum(pt.portion), 0) > 0$f$,
        alist, alist, p_today, public.rpt_mobx('cu.mobile', p_mobok), case when cardinality(b) > 0 then ', ' || array_to_string(b, ', ') else '' end, cfilter);
      clist := '[["customer_id","","","id"],["name","গ্রাহক","Customer","text"],["mobile","মোবাইল","Mobile","text"],["balance","মোট বাকি","Total due","money"]]';
      if p_buckets is not null and cardinality(p_buckets) > 0 then
        for i in 1..cardinality(p_buckets) + 1 loop
          lo := case when i = 1 then 0 else p_buckets[i - 1] + 1 end; hi := case when i <= cardinality(p_buckets) then p_buckets[i] end;
          clist := clist || jsonb_build_array(jsonb_build_array('bucket_' || i, case when hi is null then lo || '+ দিন' else lo || '-' || hi || ' দিন' end,
                                                               case when hi is null then lo || '+ days' else lo || '-' || hi || ' days' end, 'money'));
        end loop;
        tot := 'count(*) as customers, sum(balance) as balance, ' || array_to_string(array(select format('sum(bucket_%s) as bucket_%s', gs.n, gs.n) from generate_series(1, cardinality(p_buckets) + 1) gs(n)), ', ');
      else
        tot := 'count(*) as customers, sum(balance) as balance';
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_aging_buckets', 'text_bn', 'বাকির বয়স ভাগ নিয়মে (report_aging_buckets) লেখা নেই', 'text_en', 'Aging buckets are not set in the rule report_aging_buckets'));
      end if;
      clist := clist || '[["oldest_days","সবচেয়ে পুরনো (দিন)","Oldest (days)","int"]]'::jsonb;
      cols := clist;
    elsif p_key = 'credit_limit_use' then
      sql := format($f$with sold as (select x.customer_id, sum(x.total) as v from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (%s) group by 1),
        paid as (select p.customer_id, sum(p.amount) as v from public.sale_payments p where not p.voided and p.customer_id is not null and p.location_id = any (%s) group by 1),
        r as (select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, coalesce(sold.v, 0) - coalesce(paid.v, 0) as balance
          from public.customers cu left join sold on sold.customer_id = cu.id left join paid on paid.customer_id = cu.id where cu.active%s)
        select r.id as customer_id, r.name, %s as mobile, r.type, r.credit_limit, r.balance,
          case when r.credit_limit > 0 then round(100 * r.balance / r.credit_limit, 1) end as use_pct,
          case when r.credit_limit is null then 'no_limit' when r.balance > r.credit_limit then 'over'
               %s else 'ok' end as status
        from r where r.credit_limit is not null or r.balance > 0$f$, alist, alist, cfilter, public.rpt_mobx('r.mobile', p_mobok),
        case when p_near is not null then format('when r.credit_limit > 0 and 100 * r.balance / r.credit_limit >= %L::numeric then ''near''', p_near) else '' end);
      tot := $f$count(*) as customers, count(*) filter (where status = 'over') as over_limit, count(*) filter (where status = 'near') as near_limit,
        count(*) filter (where status = 'no_limit') as no_limit_set, sum(balance) as balance$f$;
      if p_near is null then notes := notes || jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', 'report_near_limit_pct', 'text_bn', '"সীমার কাছে" দেখাতে নিয়ম report_near_limit_pct লিখুন', 'text_en', 'Set the rule report_near_limit_pct to show a "near the limit" status')); end if;
    end if;
  end if;
  return jsonb_build_object('t', sql, 'tot', tot, 'cols', cols, 'ignored', coalesce(ign, '[]'::jsonb), 'notes', notes);
end $$;

-- ============================================================
-- the catalogue for the UI
-- ============================================================
create or replace function public.report_catalog() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare k text; d jsonb; out_ jsonb := '[]'::jsonb; cost_ok boolean; dims jsonb; meas jsonb; src text; dl jsonb; ml jsonb; g text; mk text; fl text[]; ok boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  cost_ok := public.rpt_cost_ok();
  foreach k in array public.rpt_keys() loop
    d := public.rpt_def(k); src := d ->> 'src';
    ok := public.rpt_access(d ->> 'group');
    dl := '[]'::jsonb; ml := '[]'::jsonb;
    if d ->> 'kind' = 'agg' then
      dims := public.rpt_dims(src); meas := public.rpt_meas(src);
      for g in select jsonb_array_elements_text(d -> 'dims') loop
        dl := dl || jsonb_build_array(jsonb_build_object('key', g, 'time', coalesce((dims -> g ->> 'time')::int = 1, false),
              'label_bn', dims -> g -> 'cols' -> (case when jsonb_array_length(dims -> g -> 'cols') > 1 then 1 else 0 end) ->> 2,
              'label_en', dims -> g -> 'cols' -> (case when jsonb_array_length(dims -> g -> 'cols') > 1 then 1 else 0 end) ->> 3,
              'needs_rule', null));      -- week / fiscal grouping always work now (phase8 rules, documented fallbacks): nothing to set first
      end loop;
      for mk in select jsonb_array_elements_text(d -> 'measures') loop
        if cost_ok or coalesce((meas -> mk ->> 'cost')::int, 0) = 0 then
          ml := ml || jsonb_build_array(jsonb_build_object('key', mk, 'label_bn', meas -> mk ->> 'bn', 'label_en', meas -> mk ->> 'en', 'type', meas -> mk ->> 'type', 'cost', coalesce((meas -> mk ->> 'cost')::int, 0) = 1));
        end if;
      end loop;
      if cost_ok and coalesce((d ->> 'cost_join')::int, 0) = 1 then
        ml := ml || '[{"key":"cogs","label_bn":"পণ্যের খরচ","label_en":"Cost of goods","type":"money","cost":true},{"key":"gp","label_bn":"মোট লাভ (খরচ জানা অংশে)","label_en":"Gross profit (costed part)","type":"money","cost":true},{"key":"gp_pct","label_bn":"লাভ %","label_en":"GP %","type":"pct","cost":true},{"key":"uncosted_pct","label_bn":"খরচ অজানা বিক্রি %","label_en":"Uncosted sales %","type":"pct","cost":true}]'::jsonb;
      end if;
      fl := coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), public.rpt_filters_for(src));
    else
      fl := coalesce((select array_agg(x) from jsonb_array_elements_text(d -> 'allow') x), '{}');
      ml := coalesce((select jsonb_agg(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3)) from jsonb_array_elements(d -> 'columns') c where c ->> 3 <> 'id'), '[]'::jsonb);
    end if;
    out_ := out_ || jsonb_build_array(jsonb_build_object('key', k, 'group', d ->> 'group', 'grant', 'report_' || (d ->> 'group'), 'allowed', ok,
      'kind', d ->> 'kind', 'name_bn', d ->> 'bn', 'name_en', d ->> 'en', 'name_mix', d ->> 'mix',
      'filters', to_jsonb(array['date'] || fl), 'dims', dl, 'default_group', nullif(d ->> 'gdef', ''), 'columns', ml,
      'compare', coalesce((d ->> 'cmp')::int = 1, false), 'needs_date', coalesce((d ->> 'nodate')::int, 0) = 0));
  end loop;
  return out_;
end $$;

-- ============================================================
-- report_run
-- ============================================================
create or replace function public.report_run(p_key text, p_filters jsonb default '{}'::jsonb, p_group text default null, p_sort text default null,
  p_page int default 1, p_compare boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
-- Time guard: a function-level SET statement_timeout does NOT cancel the statement that is already running (tested), so the real guard is the
-- role timeout (Supabase sets 8s on the authenticated role) plus the hard limits here: 366-day range, 500-group cap, 200-row pages.
declare
  def jsonb; flt jsonb; notes jsonb := '[]'::jsonb; today date := (now() at time zone 'Asia/Dhaka')::date;
  cost_ok boolean; mob_ok boolean; allowed int[]; d1 date; d2 date; wcfg jsonb; fcfg jsonb; fym int; ws int; fgap_s bigint; fgap_f bigint;
  pgsize int; pg int := least(greatest(coalesce(p_page, 1), 1), 1000); off int; lim int; cap constant int := 500;
  kind text; src text; dims jsonb; meas jsonb; gl text[] := '{}'; tok text; g text; mk text; mkeys text[] := '{}'; gtxt text;
  cols jsonb := '[]'::jsonb; allowkeys text[] := '{}'; sk text; sd text; sraw text; sparts text[]; ordr text; dsort text;
  b jsonb; t text; tot text; rows_ jsonb; totals_ jsonb; ngroups bigint := 0; cmp_ jsonb := null; ign jsonb; c jsonb; pr jsonb; preset text;
  cmode text; cf date; ct date; shiftlit text; shiftdays int; b2 jsonb; rows2 jsonb; tot2 jsonb; buckets int[]; bk text; near numeric; extra_cols jsonb := '[]'::jsonb;
  hm boolean; dn boolean := false; i int; x record; raw jsonb; nloc int; delta jsonb := '{}'::jsonb; k text; cu numeric; pv numeric; first_dim text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  def := public.rpt_def(p_key);
  if def is null then raise exception 'unknown_report'; end if;
  if not public.rpt_access(def ->> 'group') then raise exception 'not allowed'; end if;
  kind := def ->> 'kind'; src := def ->> 'src';
  flt := case when p_filters is not null and jsonb_typeof(p_filters) = 'object' then p_filters else '{}'::jsonb end;
  cost_ok := public.rpt_cost_ok(); mob_ok := public.rpt_mobile_ok();
  allowed := coalesce((select array_agg(l.id) from public.locations l where public.can_loc(l.id)), '{}');
  if cardinality(allowed) = 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_location', 'text_en', 'No location is open to you')); end if;
  select count(*) into nloc from public.locations;
  if cardinality(allowed) < nloc then notes := notes || jsonb_build_array(jsonb_build_object('code', 'location_scope', 'text_en', 'Only your locations are included', 'text_bn', 'শুধু আপনার লোকেশনের হিসাব')); end if;
  wcfg := public.rpt_week_cfg(); ws := (wcfg ->> 'dow')::int;      -- phase8 rules week_start / fiscal_year_start_month + _day, with phase8's documented fallbacks
  fcfg := public.rpt_fy_cfg(); fym := (fcfg ->> 'code')::int;
  pgsize := least(greatest(coalesce(public.rule_num('report_page_size'), 50), 10), 200)::int;
  off := (pg - 1) * pgsize; lim := greatest(least(pgsize, cap - off), 0);

  -- period
  if coalesce((def ->> 'nodate')::int, 0) = 0 then
    preset := flt ->> 'preset';
    if preset is not null then
      pr := public.report_presets() -> preset;
      if pr is null or jsonb_typeof(pr) = 'null' then
        return jsonb_build_object('report', p_key, 'columns', '[]'::jsonb, 'rows', '[]'::jsonb, 'totals', null, 'compare', null, 'has_more', false, 'data_needed', true,
          'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', 0, 'cap', cap),
          'notes', jsonb_build_array(jsonb_build_object('code', 'data_needed', 'what', left(preset, 30), 'text_en', 'Unknown date preset',
            'text_bn', 'তারিখের প্রিসেটের নাম ভুল')));
      end if;
      d1 := (pr ->> 'from')::date; d2 := (pr ->> 'to')::date;
    else
      d1 := public.rpt_date(flt ->> 'from'); d2 := public.rpt_date(flt ->> 'to');
      if d1 is null and d2 is null then d1 := date_trunc('month', today)::date; d2 := today;
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'default_period', 'text_en', 'No period given: this month to date', 'text_bn', 'সময় দেওয়া হয়নি: এই মাসের আজ পর্যন্ত'));
      elsif d1 is null then d1 := d2; elsif d2 is null then d2 := today; end if;
    end if;
    if d2 < d1 or d2 - d1 > 365 then raise exception 'bad_range'; end if;
  end if;

  -- ---------------- grouped reports ----------------
  if kind = 'agg' then
    dims := public.rpt_dims(src); meas := public.rpt_meas(src);
    gtxt := case when p_group is null or btrim(p_group) = '' then null else lower(btrim(p_group)) end;
    if gtxt is null then gl := coalesce(string_to_array(nullif(def ->> 'gdef', ''), ','), '{}');
    elsif gtxt in ('none', 'total', '-') then gl := '{}';
    else
      foreach tok in array string_to_array(gtxt, ',') loop
        tok := btrim(tok);
        if tok = '' then continue; end if;
        if (def -> 'dims') @> to_jsonb(tok) and not (tok = any (gl)) and cardinality(gl) < 3 then gl := gl || tok;
        else notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(tok, 30))); end if;
      end loop;
      if cardinality(gl) = 0 then gl := coalesce(string_to_array(nullif(def ->> 'gdef', ''), ','), '{}'); end if;
    end if;
    -- dims that use a setting: say so when a documented fallback (calendar year / Saturday) is used
    foreach g in array gl loop
      if dims -> g ->> 'need' = 'fy' and fcfg ->> 'src' = 'fallback' then
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'fy_default', 'what', 'fiscal_year_start_month', 'text_en', 'Fiscal-year start rule not set: the calendar year (from 1 January) is used', 'text_bn', 'অর্থবছর শুরুর নিয়ম নেই: জানুয়ারি থেকে বছর ধরা হয়েছে'));
      elsif dims -> g ->> 'need' = 'ws' and wcfg ->> 'src' = 'fallback' then
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'week_default', 'what', 'week_start', 'text_en', 'Week start rule not set: weeks start on Saturday', 'text_bn', 'সপ্তাহ শুরুর নিয়ম নেই: শনিবার ধরা হয়েছে'));
      end if;
    end loop;
    -- measures
    for mk in select jsonb_array_elements_text(def -> 'measures') loop
      if meas ? mk and (cost_ok or coalesce((meas -> mk ->> 'cost')::int, 0) = 0) then mkeys := mkeys || mk; end if;
    end loop;
    if not cost_ok and (coalesce((def ->> 'cost_join')::int, 0) = 1 or exists (select 1 from jsonb_array_elements_text(def -> 'measures') m where coalesce((meas -> m ->> 'cost')::int, 0) = 1)) then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'cost_hidden', 'text_en', 'Cost and profit columns are hidden for your role', 'text_bn', 'আপনার ভূমিকার জন্য খরচ ও লাভের কলাম বন্ধ'));
    end if;
    -- output columns
    foreach g in array gl loop
      for c in select * from jsonb_array_elements(dims -> g -> 'cols') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 2, 'label_en', c ->> 3, 'type', c ->> 4, 'role', 'dim'));
        allowkeys := allowkeys || (c ->> 0);
        if first_dim is null and c ->> 4 <> 'id' then first_dim := c ->> 0; end if;
      end loop;
    end loop;
    foreach mk in array mkeys loop
      cols := cols || jsonb_build_array(jsonb_build_object('key', mk, 'label_bn', meas -> mk ->> 'bn', 'label_en', meas -> mk ->> 'en', 'type', meas -> mk ->> 'type', 'role', 'measure', 'cost', coalesce((meas -> mk ->> 'cost')::int, 0) = 1));
      allowkeys := allowkeys || mk;
    end loop;
    if cost_ok and coalesce((def ->> 'cost_join')::int, 0) = 1 then
      cols := cols || '[{"key":"cogs","label_bn":"পণ্যের খরচ","label_en":"Cost of goods","type":"money","role":"measure","cost":true},{"key":"gp","label_bn":"মোট লাভ (খরচ জানা অংশে)","label_en":"Gross profit (costed part)","type":"money","role":"measure","cost":true},{"key":"gp_pct","label_bn":"লাভ %","label_en":"GP %","type":"pct","role":"measure","cost":true},{"key":"uncosted_pct","label_bn":"খরচ অজানা বিক্রি %","label_en":"Uncosted sales %","type":"pct","role":"measure","cost":true}]'::jsonb;
      allowkeys := allowkeys || array['cogs', 'gp', 'gp_pct', 'uncosted_pct'];
    end if;
    -- sort (only whitelisted output names; anything else is ignored with a note)
    sraw := lower(btrim(coalesce(p_sort, '')));
    if sraw <> '' then
      if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
      sparts := regexp_split_to_array(sraw, '[: ]+');
      if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
      else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
    end if;
    if sk is null then
      dsort := def ->> 'sort';
      if dsort = '@dim' then sk := first_dim; sd := 'asc';
      elsif dsort is not null and split_part(dsort, ':', 1) = any (allowkeys) then sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); end if;
      if sk is null then sk := first_dim; sd := 'asc'; end if;
    end if;
    ordr := case when sk is null then '1' else quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1' end;

    -- main period
    b := public.rpt_agg_build(def, gl, mkeys, flt, allowed, d1, d2, '{T}.day', ws, fym, mob_ok, cost_ok);
    t := b ->> 't'; tot := b ->> 'tot'; ign := b -> 'ignored';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
      ordr, t, ordr, lim, off) into rows_, ngroups;
    execute format('select to_jsonb(x) from (%s) x', tot) into totals_;
    hm := (off + pgsize) < least(ngroups, cap);
    if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups, 'text_en', 'More than 500 groups: only the first 500 (in the chosen order) can be paged; narrow the filters', 'text_bn', '৫০০-র বেশি গ্রুপ: বাছাই অনুযায়ী প্রথম ৫০০টি দেখা যাবে; ফিল্টার ছোট করুন')); end if;
    if jsonb_array_length(ign) > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', ign)); end if;
    -- line reports read the facts: if some done sales in this range have no fact rows (a failed fact write), say so (the owner runs report_fact_rebuild())
    if src = 'line' then
      select count(*) into fgap_s from public.sales gs where gs.status = 'done' and gs.sale_date between d1 and d2 and gs.location_id = any (allowed)
        and jsonb_typeof(gs.lines) = 'array' and jsonb_array_length(gs.lines) > 0;
      select count(distinct t.sale_id) into fgap_f from public.sales_fact_t t where t.status = 'done' and t.day between d1 and d2 and t.location_id = any (allowed);
      if fgap_s <> fgap_f then
        notes := notes || jsonb_build_array(jsonb_build_object('code', 'fact_gap', 'sales', fgap_s, 'facts', fgap_f,
          'text_en', 'Some sales in this period are missing from the line facts (' || fgap_s || ' sales, ' || fgap_f || ' with facts): totals may be low until the owner runs report_fact_rebuild()',
          'text_bn', 'এই সময়ের কিছু বিক্রির লাইন-হিসাব তৈরি হয়নি (' || fgap_s || ' বিক্রি, ' || fgap_f || ' টির হিসাব আছে): মালিক report_fact_rebuild() চালানো পর্যন্ত যোগফল কম দেখাতে পারে'));
      end if;
    end if;

    -- compare with an earlier period (same length, same weekday last week, or last year)
    if p_compare and coalesce((def ->> 'cmp')::int, 0) = 1 and d1 is not null then
      cmode := coalesce(flt ->> 'compare_mode', 'prev');
      if cmode not in ('prev', 'week', 'year') then cmode := 'prev'; notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_mode_ignored')); end if;
      if cmode = 'prev' then shiftdays := d2 - d1 + 1; cf := d1 - shiftdays; ct := d1 - 1; shiftlit := format('interval ''%s days''', shiftdays);
      elsif cmode = 'week' then shiftdays := 7; cf := d1 - 7; ct := d2 - 7; shiftlit := 'interval ''7 days''';
      else shiftdays := 365; cf := (d1 - interval '1 year')::date; ct := (d2 - interval '1 year')::date; shiftlit := 'interval ''1 year'''; end if;
      b2 := public.rpt_agg_build(def, gl, mkeys, flt, allowed, cf, ct, format('({T}.day + %s)::date', shiftlit), ws, fym, mob_ok, cost_ok);
      execute format('select coalesce(jsonb_agg(to_jsonb(q) order by q._rn), ''[]''::jsonb) from (select z.*, row_number() over (order by %s) as _rn from (%s) z order by %s limit %s) q',
        ordr, b2 ->> 't', ordr, cap) into rows2;
      execute format('select to_jsonb(x) from (%s) x', b2 ->> 'tot') into tot2;
      rows2 := (select coalesce(jsonb_agg(e - '_rn'), '[]'::jsonb) from jsonb_array_elements(rows2) e);
      for k in select jsonb_object_keys(totals_) loop
        if jsonb_typeof(totals_ -> k) = 'number' and jsonb_typeof(tot2 -> k) = 'number' then
          cu := (totals_ ->> k)::numeric; pv := (tot2 ->> k)::numeric;
          delta := delta || jsonb_build_object(k, jsonb_build_object('current', cu, 'previous', pv, 'abs', cu - pv, 'pct', case when pv <> 0 then round(100 * (cu - pv) / abs(pv), 2) end));
        end if;
      end loop;
      cmp_ := jsonb_build_object('mode', cmode, 'from', cf, 'to', ct, 'shifted_days', case when cmode = 'year' then null else shiftdays end, 'totals', tot2, 'rows', rows2, 'delta', delta,
        'note', 'Time columns of compare rows are shifted forward to line up with the current period');
    elsif p_compare then
      notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_unavailable'));
    end if;

  -- ---------------- fixed (list) reports ----------------
  else
    bk := public.rule_txt('report_aging_buckets');
    if bk is not null and bk ~ '^[0-9]{1,4}(,[0-9]{1,4}){0,5}$' then
      buckets := string_to_array(bk, ',')::int[];
      for i in 2..cardinality(buckets) loop if buckets[i] <= buckets[i - 1] then buckets := null; exit; end if; end loop;
    end if;
    near := public.rule_num('report_near_limit_pct');
    raw := public.rpt_raw(p_key, flt, allowed, d1, d2, mob_ok, buckets, near, today);
    t := raw ->> 't'; tot := raw ->> 'tot'; ign := raw -> 'ignored';
    if raw -> 'cols' is not null and jsonb_typeof(raw -> 'cols') = 'array' then
      for c in select * from jsonb_array_elements(raw -> 'cols') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3, 'role', 'col'));
        allowkeys := allowkeys || (c ->> 0);
      end loop;
    else
      for c in select * from jsonb_array_elements(def -> 'columns') loop
        cols := cols || jsonb_build_array(jsonb_build_object('key', c ->> 0, 'label_bn', c ->> 1, 'label_en', c ->> 2, 'type', c ->> 3, 'role', 'col'));
        allowkeys := allowkeys || (c ->> 0);
      end loop;
    end if;
    notes := notes || coalesce(raw -> 'notes', '[]'::jsonb);
    if jsonb_array_length(ign) > 0 then notes := notes || jsonb_build_array(jsonb_build_object('code', 'filter_ignored', 'what', ign)); end if;
    if p_group is not null and btrim(p_group) <> '' then notes := notes || jsonb_build_array(jsonb_build_object('code', 'group_ignored', 'what', left(p_group, 30))); end if;
    if p_compare then notes := notes || jsonb_build_array(jsonb_build_object('code', 'compare_unavailable')); end if;
    sraw := lower(btrim(coalesce(p_sort, '')));
    if sraw <> '' then
      if left(sraw, 1) = '-' then sd := 'desc'; sraw := substr(sraw, 2); end if;
      sparts := regexp_split_to_array(sraw, '[: ]+');
      if sparts[1] = any (allowkeys) then sk := sparts[1]; sd := coalesce(sd, case when sparts[2] = 'desc' then 'desc' else 'asc' end);
      else notes := notes || jsonb_build_array(jsonb_build_object('code', 'sort_ignored', 'what', left(sparts[1], 30))); end if;
    end if;
    if sk is null then
      dsort := def ->> 'sort';
      if split_part(dsort, ':', 1) = any (allowkeys) then sk := split_part(dsort, ':', 1); sd := split_part(dsort, ':', 2); else sk := allowkeys[1]; sd := 'asc'; end if;
    end if;
    ordr := quote_ident(sk) || ' ' || case when sd = 'desc' then 'desc' else 'asc' end || ' nulls last, 1';
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - ''_n'' - ''_rn'' order by x._rn), ''[]''::jsonb), coalesce(max(x._n), 0) from (select q.*, count(*) over () as _n, row_number() over (order by %s) as _rn from (%s) q order by %s limit %s offset %s) x',
      ordr, t, ordr, lim, off) into rows_, ngroups;
    execute format('select to_jsonb(x) from (select %s from (%s) q) x', tot, t) into totals_;
    hm := (off + pgsize) < least(ngroups, cap);
    if ngroups > cap then notes := notes || jsonb_build_array(jsonb_build_object('code', 'truncated', 'cap', cap, 'groups', ngroups, 'text_en', 'More than 500 rows: only the first 500 (in the chosen order) can be paged; narrow the filters', 'text_bn', '৫০০-র বেশি সারি: বাছাই অনুযায়ী প্রথম ৫০০টি দেখা যাবে; ফিল্টার ছোট করুন')); end if;
  end if;

  if not mob_ok and exists (select 1 from jsonb_array_elements(cols) ce where ce ->> 'key' = 'mobile') then
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'mobile_masked', 'text_en', 'Customer mobile numbers are masked for your role', 'text_bn', 'আপনার ভূমিকার জন্য গ্রাহকের মোবাইল নম্বর ঢাকা'));
  end if;
  if jsonb_array_length(rows_) = 0 or ngroups = 0
     or (kind = 'agg' and cardinality(gl) = 0 and not exists (select 1 from jsonb_each_text(totals_) kv where kv.value ~ '^-?[0-9.]+$' and kv.value::numeric <> 0)) then
    dn := true;
    notes := notes || jsonb_build_array(jsonb_build_object('code', 'no_data', 'text_en', 'Data needed: nothing matches this period / filters', 'text_bn', 'তথ্য দরকার: এই সময়/ফিল্টারে কিছু নেই'));
  end if;
  return jsonb_build_object('report', p_key, 'columns', cols, 'rows', rows_, 'totals', totals_, 'compare', cmp_,
    'page', jsonb_build_object('n', pg, 'size', pgsize, 'groups', ngroups, 'cap', cap), 'has_more', coalesce(hm, false), 'notes', notes, 'data_needed', dn,
    'meta', jsonb_build_object('from', d1, 'to', d2, 'group', to_jsonb(gl), 'sort', sk, 'dir', sd, 'cost_shown', cost_ok, 'mobile_masked', not mob_ok, 'today', today));
end $$;

-- ---------- export log: the app calls this after it builds a CSV / print so the owner can see who took which data out ----------
-- Needs the owner or the grant export_data (role / personal / emergency window, see rpt_grant). It only WRITES one audit_log row; it does not
-- return data and is not what stops an export: the report data itself is already limited by report_run.
create or replace function public.log_report_export(p_key text, p_kind text, p_filters jsonb, p_rows int) returns void
language plpgsql security definer set search_path = public as $$
declare sid text; f jsonb := coalesce(p_filters, '{}'::jsonb);
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_key is null or not (p_key = any (public.rpt_keys())) then raise exception 'unknown_report'; end if;
  if p_kind is null or lower(p_kind) !~ '^[a-z0-9_]{1,20}$' then raise exception 'bad_kind'; end if;
  if length(f::text) > 4000 then f := jsonb_build_object('truncated', true); end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.audit_log (user_id, staff_id, action, table_name, record_id, detail)
    values (auth.uid(), sid, 'export', 'report', p_key, jsonb_build_object('kind', lower(p_kind), 'rows', least(greatest(coalesce(p_rows, 0), 0), 100000000), 'filters', f));
end $$;

-- ---------- privileges: nobody anonymous; signed-in users reach data only through the functions above ----------
revoke all on function public.rpt_grant(text), public.rpt_week_cfg(), public.rpt_fy_cfg(), public.rpt_fy_start(date, int), public.rpt_access(text), public.rpt_cost_ok(), public.rpt_mobile_ok(), public.rpt_arr_text(jsonb), public.rpt_arr_int(jsonb), public.rpt_arr_uuid(jsonb),
  public.rpt_num(jsonb), public.rpt_date(text), public.rpt_dims(text), public.rpt_meas(text), public.rpt_def(text), public.rpt_keys(), public.rpt_filters_for(text),
  public.rpt_tok(text, text, text, int, int, boolean), public.rpt_where(text, text, jsonb, int[], date, date, text[], boolean),
  public.rpt_agg_sql(text, text, text, text[], text[], text, text, text, text, int, int, boolean, boolean, boolean),
  public.rpt_agg_build(jsonb, text[], text[], jsonb, int[], date, date, text, int, int, boolean, boolean), public.rpt_mobx(text, boolean),
  public.rpt_raw(text, jsonb, int[], date, date, boolean, int[], numeric, date),
  public.report_presets(), public.report_catalog(), public.report_run(text, jsonb, text, text, int, boolean), public.log_report_export(text, text, jsonb, int) from public, anon, authenticated;
grant execute on function public.report_presets(), public.report_catalog(), public.report_run(text, jsonb, text, text, int, boolean), public.log_report_export(text, text, jsonb, int) to authenticated;

notify pgrst, 'reload schema';
