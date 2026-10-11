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
-- With p_loc null only grants that cover every location count; give a location to include location-limited personal grants / window approvals.
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
  if dkind = 'percent' then disc := round(sub * dinput / 100, 2); end if;
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
