-- ============================================================
-- Phase 124 (marker ie124) - IMPORT-EXPORT, a basic module for ONE business of the group (template import_export). ADDITIVE, idempotent.
-- Needs phase122 (org_units, org_unit_scope, org_tree). Canonical order: after phase123. Changes NO existing function, policy or rule.
-- Scope: every table carries org_unit_id (the import_export BUSINESS unit). A user reaches a business only through a location they are assigned to
--   (user_locations + can_loc + org_unit_scope(location).business_id) AND the grant impexp_view / impexp_manage on that location. The owner reaches all.
--   This does not read the rule org_scope_on: isolation by business is built in, so it already holds when that switch is turned ON later.
-- Tables (RLS on, NO browser read or write at all: everything goes through the functions below)
--   ie_currencies       per business: code (3 letters), name, decimals 0..4, active. The base currency is the legal entity's base_currency (never hard-coded).
--   ie_fx_rates         per business: currency, rate = base units per 1 foreign unit, valid_from, entered_by. APPEND-ONLY history.
--   ie_shipments        business register: direction import|export, reference, counterparty, status draft|booked|in_transit|received|closed|cancelled,
--                       currency, amount (document currency), rate used, amount_base = round(amount * rate, 2), dates, notes,
--                       landed-cost lines typed by the user in the BASE currency (freight, insurance, duty_tax, other_cost). Nothing is invented or estimated.
--   ie_shipment_events  append-only log of create / edit / status change.
-- Functions (browser): ie_businesses124, ie_currencies_list, ie_fx_rates_list, currency_save, fx_rate_set, shipment_save, shipment_set_status,
--   shipments_list, shipment_events_list, shipment_cost_summary, shipments_by_currency. Writes need rule impexp_on (default OFF) + grant impexp_manage.
-- NOT built (stated in business_templates.modules): letters of credit, customs automation, bank/payment tracking, accounting (GL) posting, stock link, multi-line shipments.
-- Rollback: leave impexp_on OFF. To remove: drop the functions and the four ie_ tables (nothing else refers to them).
-- ============================================================
begin;

do $g$ begin
  if to_regclass('public.org_units') is null or to_regprocedure('public.org_unit_scope(integer)') is null then
    raise exception 'phase124 needs phase122 (organization layer) first';
  end if;
end $g$;

-- ---------- 1. grants, rule, template row ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'impexp_view', 'impexp', 90, 'আমদানি-রপ্তানি: দেখা', 'Import-Export: দেখা', 'Import-Export: view', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'impexp_view');
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type)
select 'impexp_manage', 'impexp', 91, 'আমদানি-রপ্তানি: শিপমেন্ট, মুদ্রা ও রেট লেখা', 'Import-Export: shipment, currency ও rate লেখা', 'Import-Export: write shipments, currencies and rates', 'once'
where not exists (select 1 from public.grant_defs where grant_code = 'impexp_manage');

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_mix, hint_en, sort) values
 ('impexp_on', 'impexp', 'switch', 'false', null, null, null, null,
  'আমদানি-রপ্তানি মডিউল চালু', 'Import-Export module চালু', 'Import-Export module on',
  'বন্ধ থাকলে শিপমেন্ট, মুদ্রা ও রেট লেখা যায় না (দেখা যায়)। হিসাবে (GL) কিছু পোস্ট হয় না।',
  'off থাকলে shipment, currency ও rate লেখা যায় না (দেখা যায়)। হিসাবে (GL) কিছু post হয় না।',
  'When off, shipments, currencies and rates cannot be written (reading works). Nothing is posted to the GL.', 991)
on conflict (key) do nothing;

-- template row: honest state. Built and tested = the register, currencies, rates, landed cost, report. Not built = the rest.
insert into public.business_templates (code, name_bn, name_en, modules, status, sort) values
 ('import_export', 'আমদানি-রপ্তানি', 'Import-Export',
  '[{"code":"shipments","state":"built"},{"code":"currencies","state":"built"},{"code":"fx_rates","state":"built"},{"code":"landed_cost","state":"built","note":"amounts typed by the user, nothing estimated"},{"code":"report_by_currency","state":"built"},{"code":"letter_of_credit","state":"not_built"},{"code":"customs_automation","state":"not_built"},{"code":"accounting_posting","state":"not_built","note":"nothing is posted to the GL yet (pending)"},{"code":"stock_link","state":"not_built"},{"code":"bank_payments","state":"not_built"}]'::jsonb,
  'needs_setup', 70)
on conflict (code) do update set modules = excluded.modules, name_bn = excluded.name_bn, name_en = excluded.name_en,
  status = case when public.business_templates.status in ('not_implemented', 'planned', 'needs_setup') then excluded.status else public.business_templates.status end
  where public.business_templates.status in ('not_implemented', 'planned', 'needs_setup');

-- ---------- 2. tables ----------
create table if not exists public.ie_currencies (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  code text not null check (code ~ '^[A-Z]{3}$'),
  name_bn text not null check (length(btrim(name_bn)) between 1 and 80),
  name_en text check (name_en is null or length(name_en) <= 80),
  decimals int not null default 2 check (decimals between 0 and 4),
  active boolean not null default true,
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, code)
);
create table if not exists public.ie_fx_rates (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  rate numeric(20,8) not null check (rate > 0 and rate <= 1000000000000),
  valid_from date not null,
  note text check (note is null or length(note) <= 300),
  client_id uuid unique,
  entered_by uuid, entered_at timestamptz not null default now()
);
create index if not exists ie_fx_rates124_look on public.ie_fx_rates (org_unit_id, currency, valid_from desc, id desc);
create table if not exists public.ie_shipments (
  id bigserial primary key,
  org_unit_id bigint not null references public.org_units(id),
  direction text not null check (direction in ('import', 'export')),
  reference text not null check (length(btrim(reference)) between 1 and 60),
  counterparty text check (counterparty is null or length(counterparty) <= 200),
  status text not null default 'draft' check (status in ('draft', 'booked', 'in_transit', 'received', 'closed', 'cancelled')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount numeric(20,2) not null check (amount >= 0 and amount <= 1000000000000),
  rate numeric(20,8) not null check (rate > 0 and rate <= 1000000000000),
  amount_base numeric(20,2) not null check (amount_base >= 0 and amount_base <= 1000000000000),
  ship_date date not null,
  eta_date date,
  received_date date,
  notes text check (notes is null or length(notes) <= 1000),
  freight numeric(20,2) not null default 0 check (freight >= 0 and freight <= 1000000000000),
  insurance numeric(20,2) not null default 0 check (insurance >= 0 and insurance <= 1000000000000),
  duty_tax numeric(20,2) not null default 0 check (duty_tax >= 0 and duty_tax <= 1000000000000),
  other_cost numeric(20,2) not null default 0 check (other_cost >= 0 and other_cost <= 1000000000000),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  unique (org_unit_id, reference)
);
create index if not exists ie_shipments124_org on public.ie_shipments (org_unit_id, status, ship_date desc);
create table if not exists public.ie_shipment_events (
  id bigserial primary key,
  shipment_id bigint not null references public.ie_shipments(id),
  org_unit_id bigint not null references public.org_units(id),
  event text not null check (event in ('create', 'edit', 'status')),
  from_status text, to_status text,
  note text check (note is null or length(note) <= 500),
  client_id uuid unique,
  by_user uuid, at timestamptz not null default now()
);
create index if not exists ie_events124_ship on public.ie_shipment_events (shipment_id, id);

create or replace function public._ie_ro124() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists ie_fx_ro124 on public.ie_fx_rates;
create trigger ie_fx_ro124 before update or delete on public.ie_fx_rates for each row execute function public._ie_ro124();
drop trigger if exists ie_ev_ro124 on public.ie_shipment_events;
create trigger ie_ev_ro124 before update or delete on public.ie_shipment_events for each row execute function public._ie_ro124();
drop trigger if exists ie_cur_nd124 on public.ie_currencies;
create trigger ie_cur_nd124 before delete on public.ie_currencies for each row execute function public.no_hard_delete();
drop trigger if exists ie_shp_nd124 on public.ie_shipments;
create trigger ie_shp_nd124 before delete on public.ie_shipments for each row execute function public.no_hard_delete();
drop trigger if exists audit_ie_cur124 on public.ie_currencies;
create trigger audit_ie_cur124 after insert or update on public.ie_currencies for each row execute function public.log_change('id');
drop trigger if exists audit_ie_fx124 on public.ie_fx_rates;
create trigger audit_ie_fx124 after insert on public.ie_fx_rates for each row execute function public.log_change('id');
drop trigger if exists audit_ie_shp124 on public.ie_shipments;
create trigger audit_ie_shp124 after insert or update on public.ie_shipments for each row execute function public.log_change('id');
drop trigger if exists audit_ie_ev124 on public.ie_shipment_events;
create trigger audit_ie_ev124 after insert on public.ie_shipment_events for each row execute function public.log_change('id');

-- RLS on, no policy = no direct browser access at all (functions only)
alter table public.ie_currencies enable row level security;
alter table public.ie_fx_rates enable row level security;
alter table public.ie_shipments enable row level security;
alter table public.ie_shipment_events enable row level security;
revoke all on public.ie_currencies, public.ie_fx_rates, public.ie_shipments, public.ie_shipment_events from public, anon, authenticated;
revoke all on sequence public.ie_currencies_id_seq, public.ie_fx_rates_id_seq, public.ie_shipments_id_seq, public.ie_shipment_events_id_seq from public, anon, authenticated;

-- ---------- 3. helpers (closed to the browser) ----------
-- may the caller act on this import_export business? p_need = 'impexp_view' (manage also counts) or 'impexp_manage'. Owner: every business.
create or replace function public._ie_access124(p_org bigint, p_need text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and p_org is not null
    and exists (select 1 from public.org_tree() t where t.id = p_org and t.kind = 'business' and t.template_code = 'import_export')
    and (public.is_owner() or exists (
      select 1 from public.user_locations ul
       where ul.user_id = auth.uid() and public.can_loc(ul.location_id)
         and (public.org_unit_scope(ul.location_id)->>'business_id')::bigint = p_org
         and (public.has_grant('impexp_manage', ul.location_id) or (p_need = 'impexp_view' and public.has_grant('impexp_view', ul.location_id)))));
$$;
-- base currency of the business = base currency of its legal entity (walk up the tree)
create or replace function public._ie_base124(p_org bigint) returns text
language sql stable security definer set search_path = public as $$
  with recursive t as materialized (select x.id, x.parent_id, x.kind, x.base_currency from public.org_tree() x),
  up as (select t.* from t where t.id = p_org union all select t.* from t join up on t.id = up.parent_id)
  select (select up.base_currency from up where up.kind = 'legal_entity' limit 1);
$$;
create or replace function public._ie_write124(p_org bigint) returns void
language plpgsql stable security definer set search_path = public as $$
declare st text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public._ie_access124(p_org, 'impexp_manage') then raise exception 'not allowed'; end if;
  if not public.rule_on('impexp_on') then raise exception 'impexp_off'; end if;
  select t.status into st from public.org_tree() t where t.id = p_org;
  if st is distinct from 'active' then raise exception 'business_not_active'; end if;
end $$;
create or replace function public._ie_num124(p_x numeric, p_nullable boolean default false) returns numeric
language plpgsql immutable set search_path = public as $$
begin
  if p_x is null then if p_nullable then return null; end if; raise exception 'bad_amount'; end if;
  if p_x <> p_x or abs(p_x) > 1000000000000 then raise exception 'bad_amount'; end if;
  return p_x;
end $$;
-- the rate in force for a currency on a date (latest valid_from <= date, then latest entry); null when none
create or replace function public._ie_rate_on124(p_org bigint, p_cur text, p_date date) returns numeric
language sql stable security definer set search_path = public as $$
  select r.rate from public.ie_fx_rates r where r.org_unit_id = p_org and r.currency = p_cur and r.valid_from <= p_date order by r.valid_from desc, r.id desc limit 1;
$$;

-- ---------- 4. functions ----------
-- the import_export businesses the caller may see (for the screen's picker)
create or replace function public.ie_businesses124() returns table (id bigint, code text, name_bn text, name_en text, status text, base_currency text, can_manage boolean, impexp_on boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query select t.id, t.code, t.name_bn, t.name_en, t.status, public._ie_base124(t.id), public._ie_access124(t.id, 'impexp_manage'), public.rule_on('impexp_on')
    from public.org_tree() t where t.kind = 'business' and t.template_code = 'import_export' and public._ie_access124(t.id, 'impexp_view') order by t.code;
end $$;

create or replace function public.ie_currencies_list(p_org bigint) returns table (id bigint, code text, name_bn text, name_en text, decimals int, active boolean, is_base boolean)
language plpgsql stable security definer set search_path = public as $$
declare b text;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  b := public._ie_base124(p_org);
  return query select c.id, c.code, c.name_bn, c.name_en, c.decimals, c.active, (c.code = b) from public.ie_currencies c where c.org_unit_id = p_org order by c.code;
end $$;

create or replace function public.currency_save(p_org bigint, p_code text, p_name_bn text, p_name_en text default null, p_decimals int default 2, p_active boolean default true, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c text := upper(btrim(coalesce(p_code, ''))); o public.ie_currencies; me uuid := auth.uid(); nid bigint;
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into o from public.ie_currencies where client_id = p_client;
    if found then
      if o.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', o.id, 'code', o.code);
    end if;
  end if;
  if c !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if c = public._ie_base124(p_org) then raise exception 'is_base_currency'; end if;
  if p_name_bn is null or length(btrim(p_name_bn)) not between 1 and 80 then raise exception 'bad_name'; end if;
  if p_name_en is not null and length(p_name_en) > 80 then raise exception 'bad_name'; end if;
  if p_decimals is null or p_decimals not between 0 and 4 then raise exception 'bad_decimals'; end if;
  if p_active is null then raise exception 'bad_value'; end if;
  select * into o from public.ie_currencies where org_unit_id = p_org and code = c for update;
  if found then
    update public.ie_currencies set name_bn = btrim(p_name_bn), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), decimals = p_decimals, active = p_active, updated_by = me, updated_at = now() where id = o.id;
    return jsonb_build_object('dup', false, 'id', o.id, 'code', c);
  end if;
  insert into public.ie_currencies (org_unit_id, code, name_bn, name_en, decimals, active, client_id, created_by, updated_by)
  values (p_org, c, btrim(p_name_bn), nullif(btrim(coalesce(p_name_en, '')), ''), p_decimals, p_active, p_client, me, me) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid, 'code', c);
end $$;

create or replace function public.fx_rate_set(p_org bigint, p_currency text, p_rate numeric, p_valid_from date default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; c text := upper(btrim(coalesce(p_currency, ''))); vf date; o public.ie_fx_rates; nid bigint; me uuid := auth.uid();
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_client is null then raise exception 'client_id_needed'; end if;
  select * into o from public.ie_fx_rates where client_id = p_client;
  if found then
    if o.entered_by is distinct from me then raise exception 'client_id_taken'; end if;
    return jsonb_build_object('dup', true, 'id', o.id);
  end if;
  if c !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if not exists (select 1 from public.ie_currencies where org_unit_id = p_org and code = c and active) then raise exception 'currency_not_listed'; end if;
  p_rate := public._ie_num124(p_rate);
  if p_rate <= 0 then raise exception 'bad_rate'; end if;
  if round(p_rate, 8) <> p_rate then raise exception 'bad_rate'; end if;
  vf := coalesce(p_valid_from, today);
  if vf not between date '2000-01-01' and today + 30 then raise exception 'bad_date'; end if;
  if p_note is not null and length(p_note) > 300 then raise exception 'bad_note'; end if;
  perform public.lock_check(vf);
  insert into public.ie_fx_rates (org_unit_id, currency, rate, valid_from, note, client_id, entered_by) values (p_org, c, p_rate, vf, nullif(btrim(coalesce(p_note, '')), ''), p_client, me) returning id into nid;
  return jsonb_build_object('dup', false, 'id', nid);
end $$;

create or replace function public.ie_fx_rates_list(p_org bigint, p_currency text default null, p_limit int default 100) returns table (id bigint, currency text, rate numeric, valid_from date, note text, entered_by uuid, entered_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  return query select r.id, r.currency, r.rate, r.valid_from, r.note, r.entered_by, r.entered_at from public.ie_fx_rates r
    where r.org_unit_id = p_org and (p_currency is null or r.currency = upper(p_currency)) order by r.valid_from desc, r.id desc limit least(greatest(coalesce(p_limit, 100), 1), 500);
end $$;

-- create (p_id null, needs p_client) or edit a shipment. direction and reference never change. amount / currency / rate only while draft or booked.
-- rate: given by the user, else the rate in force on ship_date; base currency = 1. No rate = refused (nothing is guessed).
create or replace function public.shipment_save(p_org bigint, p_id bigint, p_direction text, p_reference text, p_counterparty text, p_currency text, p_amount numeric, p_rate numeric,
  p_ship_date date, p_eta_date date default null, p_notes text default null, p_freight numeric default 0, p_insurance numeric default 0, p_duty_tax numeric default 0, p_other numeric default 0,
  p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Asia/Dhaka')::date; me uuid := auth.uid(); s public.ie_shipments; cur text := upper(btrim(coalesce(p_currency, ''))); ref text := btrim(coalesce(p_reference, ''));
  base text; rt numeric; amt numeric; ab numeric; nid bigint; fr numeric; ins numeric; dty numeric; oth numeric;
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_id is null then
    if p_client is null then raise exception 'client_id_needed'; end if;
    select * into s from public.ie_shipments where client_id = p_client;
    if found then
      if s.created_by is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', s.id, 'amount_base', s.amount_base);
    end if;
  end if;
  base := public._ie_base124(p_org);
  if base is null then raise exception 'no_base_currency'; end if;
  if cur !~ '^[A-Z]{3}$' then raise exception 'bad_currency'; end if;
  if cur <> base and not exists (select 1 from public.ie_currencies where org_unit_id = p_org and code = cur and active) then raise exception 'currency_not_listed'; end if;
  amt := public._ie_num124(p_amount);
  if amt < 0 then raise exception 'bad_amount'; end if;
  amt := round(amt, 2);                                   -- the document amount is kept to 2 places; the base amount is round(amount * rate, 2)
  fr := round(public._ie_num124(coalesce(p_freight, 0)), 2); ins := round(public._ie_num124(coalesce(p_insurance, 0)), 2); dty := round(public._ie_num124(coalesce(p_duty_tax, 0)), 2); oth := round(public._ie_num124(coalesce(p_other, 0)), 2);
  if least(fr, ins, dty, oth) < 0 then raise exception 'bad_amount'; end if;
  if p_ship_date is null or p_ship_date not between date '2000-01-01' and today + 3660 then raise exception 'bad_date'; end if;
  if p_eta_date is not null and p_eta_date not between date '2000-01-01' and today + 3660 then raise exception 'bad_date'; end if;
  if p_notes is not null and length(p_notes) > 1000 then raise exception 'bad_notes'; end if;
  if p_counterparty is not null and length(p_counterparty) > 200 then raise exception 'bad_counterparty'; end if;
  if p_rate is not null then
    rt := public._ie_num124(p_rate);
    if rt <= 0 or round(rt, 8) <> rt then raise exception 'bad_rate'; end if;
  elsif cur = base then rt := 1;
  else rt := public._ie_rate_on124(p_org, cur, p_ship_date);
    if rt is null then raise exception 'no_rate'; end if;
  end if;
  if cur = base and rt <> 1 then raise exception 'bad_rate'; end if;
  ab := round(amt * rt, 2);
  if ab > 1000000000000 then raise exception 'bad_amount'; end if;
  perform public.lock_check(p_ship_date);

  if p_id is null then
    if p_direction is null or p_direction not in ('import', 'export') then raise exception 'bad_direction'; end if;
    if length(ref) not between 1 and 60 then raise exception 'bad_reference'; end if;
    if exists (select 1 from public.ie_shipments where org_unit_id = p_org and reference = ref) then raise exception 'reference_taken'; end if;
    insert into public.ie_shipments (org_unit_id, direction, reference, counterparty, status, currency, amount, rate, amount_base, ship_date, eta_date, notes, freight, insurance, duty_tax, other_cost, client_id, created_by, updated_by)
    values (p_org, p_direction, ref, nullif(btrim(coalesce(p_counterparty, '')), ''), 'draft', cur, amt, rt, ab, p_ship_date, p_eta_date, nullif(btrim(coalesce(p_notes, '')), ''), fr, ins, dty, oth, p_client, me, me) returning id into nid;
    insert into public.ie_shipment_events (shipment_id, org_unit_id, event, to_status, by_user) values (nid, p_org, 'create', 'draft', me);
    return jsonb_build_object('dup', false, 'id', nid, 'amount_base', ab, 'landed_base', ab + fr + ins + dty + oth);
  end if;

  select * into s from public.ie_shipments where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'shipment_not_found'; end if;
  if s.status in ('closed', 'cancelled') then raise exception 'shipment_final'; end if;
  if p_direction is not null and p_direction <> s.direction then raise exception 'direction_fixed'; end if;
  if p_reference is not null and ref <> s.reference then raise exception 'reference_fixed'; end if;
  if s.status not in ('draft', 'booked') and (cur <> s.currency or amt <> s.amount or rt <> s.rate) then raise exception 'amount_locked'; end if;
  perform public.lock_check(s.ship_date);
  update public.ie_shipments set counterparty = nullif(btrim(coalesce(p_counterparty, '')), ''), currency = cur, amount = amt, rate = rt, amount_base = ab, ship_date = p_ship_date, eta_date = p_eta_date,
    notes = nullif(btrim(coalesce(p_notes, '')), ''), freight = fr, insurance = ins, duty_tax = dty, other_cost = oth, updated_by = me, updated_at = now() where id = s.id;
  insert into public.ie_shipment_events (shipment_id, org_unit_id, event, from_status, to_status, by_user) values (s.id, p_org, 'edit', s.status, s.status, me);
  return jsonb_build_object('dup', false, 'id', s.id, 'amount_base', ab, 'landed_base', ab + fr + ins + dty + oth);
end $$;

create or replace function public.shipment_set_status(p_org bigint, p_id bigint, p_status text, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; me uuid := auth.uid(); s public.ie_shipments; e public.ie_shipment_events; ok boolean;
begin
  perform public._ie_write124(p_org);
  perform public._client_lock(p_client);
  if p_note is not null and length(p_note) > 500 then raise exception 'bad_note'; end if;
  if p_client is not null then
    select * into e from public.ie_shipment_events where client_id = p_client;
    if found then
      if e.by_user is distinct from me then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', e.shipment_id, 'status', e.to_status);
    end if;
  end if;
  if p_status is null or p_status not in ('draft', 'booked', 'in_transit', 'received', 'closed', 'cancelled') then raise exception 'bad_status'; end if;
  select * into s from public.ie_shipments where id = p_id and org_unit_id = p_org for update;
  if not found then raise exception 'shipment_not_found'; end if;
  if s.status = p_status then return jsonb_build_object('dup', true, 'id', s.id, 'status', s.status); end if;
  ok := (s.status = 'draft' and p_status in ('booked', 'cancelled'))
     or (s.status = 'booked' and p_status in ('in_transit', 'received', 'cancelled'))
     or (s.status = 'in_transit' and p_status in ('received', 'cancelled'))
     or (s.status = 'received' and p_status = 'closed');
  if not ok then raise exception 'bad_transition'; end if;
  perform public.lock_check(s.ship_date);
  update public.ie_shipments set status = p_status, received_date = case when p_status = 'received' and received_date is null then today else received_date end, updated_by = me, updated_at = now() where id = s.id;
  insert into public.ie_shipment_events (shipment_id, org_unit_id, event, from_status, to_status, note, client_id, by_user)
  values (s.id, p_org, 'status', s.status, p_status, nullif(btrim(coalesce(p_note, '')), ''), p_client, me);
  return jsonb_build_object('dup', false, 'id', s.id, 'status', p_status);
end $$;

create or replace function public.shipments_list(p_org bigint, p_status text default null, p_direction text default null, p_limit int default 200) returns table (
  id bigint, direction text, reference text, counterparty text, status text, currency text, amount numeric, rate numeric, amount_base numeric, ship_date date, eta_date date, received_date date,
  notes text, freight numeric, insurance numeric, duty_tax numeric, other_cost numeric, landed_base numeric, base_currency text)
language plpgsql stable security definer set search_path = public as $$
declare b text;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  b := public._ie_base124(p_org);
  return query select s.id, s.direction, s.reference, s.counterparty, s.status, s.currency, s.amount, s.rate, s.amount_base, s.ship_date, s.eta_date, s.received_date, s.notes,
      s.freight, s.insurance, s.duty_tax, s.other_cost, s.amount_base + s.freight + s.insurance + s.duty_tax + s.other_cost, b
    from public.ie_shipments s where s.org_unit_id = p_org and (p_status is null or s.status = p_status) and (p_direction is null or s.direction = p_direction)
    order by s.ship_date desc, s.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end $$;

create or replace function public.shipment_events_list(p_org bigint, p_id bigint) returns table (id bigint, event text, from_status text, to_status text, note text, by_user uuid, at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  return query select e.id, e.event, e.from_status, e.to_status, e.note, e.by_user, e.at from public.ie_shipment_events e where e.org_unit_id = p_org and e.shipment_id = p_id order by e.id;
end $$;

-- landed cost = goods in base currency + the lines the user entered (nothing else is added)
create or replace function public.shipment_cost_summary(p_org bigint, p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.ie_shipments;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  select * into s from public.ie_shipments where id = p_id and org_unit_id = p_org;
  if not found then raise exception 'shipment_not_found'; end if;
  return jsonb_build_object('id', s.id, 'reference', s.reference, 'base_currency', public._ie_base124(p_org), 'currency', s.currency, 'amount', s.amount, 'rate', s.rate,
    'goods_base', s.amount_base, 'freight', s.freight, 'insurance', s.insurance, 'duty_tax', s.duty_tax, 'other_cost', s.other_cost,
    'lines_total', s.freight + s.insurance + s.duty_tax + s.other_cost, 'landed_base', s.amount_base + s.freight + s.insurance + s.duty_tax + s.other_cost);
end $$;

-- per currency and direction (cancelled shipments are left out); optional ship_date range
create or replace function public.shipments_by_currency(p_org bigint, p_from date default null, p_to date default null) returns table (
  currency text, direction text, shipments bigint, amount numeric, amount_base numeric, landed_base numeric, base_currency text)
language plpgsql stable security definer set search_path = public as $$
declare b text;
begin
  if not public._ie_access124(p_org, 'impexp_view') then raise exception 'not allowed'; end if;
  b := public._ie_base124(p_org);
  return query select s.currency, s.direction, count(*), sum(s.amount), sum(s.amount_base), sum(s.amount_base + s.freight + s.insurance + s.duty_tax + s.other_cost), b
    from public.ie_shipments s where s.org_unit_id = p_org and s.status <> 'cancelled' and (p_from is null or s.ship_date >= p_from) and (p_to is null or s.ship_date <= p_to)
    group by s.currency, s.direction order by s.currency, s.direction;
end $$;

-- ---------- 5. privileges ----------
revoke all on function public._ie_ro124(), public._ie_access124(bigint, text), public._ie_base124(bigint), public._ie_write124(bigint), public._ie_num124(numeric, boolean), public._ie_rate_on124(bigint, text, date) from public, anon, authenticated;
revoke all on function public.ie_businesses124(), public.ie_currencies_list(bigint), public.currency_save(bigint, text, text, text, int, boolean, uuid),
  public.fx_rate_set(bigint, text, numeric, date, text, uuid), public.ie_fx_rates_list(bigint, text, int),
  public.shipment_save(bigint, bigint, text, text, text, text, numeric, numeric, date, date, text, numeric, numeric, numeric, numeric, uuid),
  public.shipment_set_status(bigint, bigint, text, text, uuid), public.shipments_list(bigint, text, text, int), public.shipment_events_list(bigint, bigint),
  public.shipment_cost_summary(bigint, bigint), public.shipments_by_currency(bigint, date, date) from public, anon;
grant execute on function public.ie_businesses124(), public.ie_currencies_list(bigint), public.currency_save(bigint, text, text, text, int, boolean, uuid),
  public.fx_rate_set(bigint, text, numeric, date, text, uuid), public.ie_fx_rates_list(bigint, text, int),
  public.shipment_save(bigint, bigint, text, text, text, text, numeric, numeric, date, date, text, numeric, numeric, numeric, numeric, uuid),
  public.shipment_set_status(bigint, bigint, text, text, uuid), public.shipments_list(bigint, text, text, int), public.shipment_events_list(bigint, bigint),
  public.shipment_cost_summary(bigint, bigint), public.shipments_by_currency(bigint, date, date) to authenticated;

commit;
