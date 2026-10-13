-- ============================================================
-- Phase 61 - P3 slice b: gaps #11 online order channel, #12 forms 20-1/20-2/20-4 linked to sales, #13 benefits depth, #14 BI export.
-- Run AFTER phase51 (needs the phase48 shadow engine, phase41 employees, phase13 export_data grant). Additive + idempotent (paste twice = no error).
-- Nothing existing is changed: no existing function is re-created, no existing row is edited. Every new switch is OFF by default.
--
--   #11 ORDERS    online_orders (+ online_order_events trail). Flow new -> confirmed -> packed -> delivered | cancelled.
--                 Delivering calls the EXISTING record_sale2 once (sale client id is stored on the order) or links an already-made sale
--                 (online_order_link_sale). One order = at most one sale (unique sale_id). Create takes a client id (idempotent).
--   #12 FORMS     path domain 'sale_forms' (owner switch: b_open=false stops new links). sale_form_links: primary = the sales row,
--                 forms 20-1 / 20-2 / 20-4 = locked shadows (shadow_type 'entries:20-x'); they never post. Owner links / unlinks;
--                 unlinked_sale_forms() lists the 20-x entries that have no sale.
--   #13 BENEFITS  benefit_types (paid_in_payroll flag, eligible_after_days) + employee_benefit_grants (grant dates, eligible_from, paid flag,
--                 value hidden without salary_view). benefits_report() is REPORT ONLY - payroll maths is not touched.
--   #14 EXPORT    bi_export(dataset, from, to, loc, format, limit): sales / sale_lines / purchases / stock_ledger / journal as json or csv.
--                 Owner or grant export_data; row cap (rule bi_export_max_rows, hard max 20000); <= 366 days; one bi_export_log row per call;
--                 cost columns only with rpt_cost_ok() (stock_ledger.unit_cost is blanked, purchases need the cost right).
-- Rules (all default OFF): online_orders_on, sale_forms_link_on, benefit_grants_on, bi_export_on; number bi_export_max_rows.
-- ============================================================

insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('online_orders_on', 'pos', 'switch', 'false', null, null, null, null, 'অনলাইন অর্ডার চ্যানেল চালু', 'Online order channel চালু', 'Online order channel is on',
  'চালু হলে ফেসবুক/হোয়াটসঅ্যাপ/ফোন অর্ডার লিখে রাখা যায়; ডেলিভারিতে একটাই বিক্রি তৈরি হয়।', 'When on, social / phone orders can be recorded; delivery makes exactly one sale.', 610),
 ('sale_forms_link_on', 'entries', 'switch', 'false', null, null, null, null, 'ফর্ম 20-১/২/৪ বিক্রির সাথে জোড়া চালু', 'Form 20-1/2/4 ↔ sale link চালু', 'Link forms 20-1 / 20-2 / 20-4 to sales',
  'মালিক একটি ফর্ম এন্ট্রিকে একটি বিক্রির সাথে জুড়বেন; ফর্ম তখন লক শ্যাডো কপি, কিছু পোস্ট হয় না।', 'The owner links a form entry to a sale; the form becomes a locked shadow copy and posts nothing.', 611),
 ('benefit_grants_on', 'people', 'switch', 'false', null, null, null, null, 'কর্মীর সুবিধা (গভীর) চালু', 'Employee benefits (depth) চালু', 'Employee benefit grants are on',
  'সুবিধার ধরন, প্রাপ্যতার তারিখ, বেতনের সাথে দেওয়া কিনা। শুধু রিপোর্ট; বেতনের হিসাব বদলায় না।', 'Benefit types, eligibility dates, paid-in-payroll flag. Report only; payroll maths is unchanged.', 612),
 ('bi_export_on', 'reports', 'switch', 'false', null, null, null, null, 'BI এক্সপোর্ট চালু', 'BI export চালু', 'BI export is on',
  'বিক্রি/ক্রয়/স্টক/জার্নাল CSV-JSON এক্সপোর্ট; শুধু মালিক বা export_data অনুমতি; প্রতিবার লগ।', 'Sales / purchases / stock / journal CSV-JSON export; owner or export_data only; every call is logged.', 613),
 ('bi_export_max_rows', 'reports', 'number', '5000', 'rows', null, 100, 20000, 'BI এক্সপোর্ট: সর্বোচ্চ সারি', 'BI export: max rows', 'BI export: row cap',
  'প্রতি এক্সপোর্টে এর বেশি সারি যাবে না (সর্বোচ্চ ২০০০০)।', 'No export returns more rows than this (hard max 20000).', 614)
 on conflict (key) do nothing;

-- =====================================================================
-- #11 ONLINE ORDER CHANNEL
-- =====================================================================
create table if not exists public.online_orders (
  id uuid primary key default gen_random_uuid(),
  client_id uuid, order_no int not null, location_id int not null references public.locations(id),
  channel text not null check (channel in ('website', 'facebook', 'instagram', 'whatsapp', 'phone', 'foodapp', 'other')),
  customer_name text not null check (char_length(btrim(customer_name)) between 1 and 80),
  customer_mobile text not null check (char_length(customer_mobile) between 6 and 20),
  address text check (address is null or char_length(address) <= 300),
  lines jsonb not null check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) between 1 and 100),
  subtotal numeric not null check (subtotal >= 0 and subtotal <= 1000000000000),
  discount numeric not null default 0 check (discount >= 0 and discount <= 1000000000000),
  delivery_mode text not null check (delivery_mode in ('pickup', 'home', 'courier')),
  delivery_by text check (delivery_by is null or char_length(delivery_by) <= 60),
  delivery_date date, delivery_charge numeric not null default 0 check (delivery_charge >= 0 and delivery_charge <= 1000000),
  advance numeric not null default 0 check (advance >= 0 and advance <= 1000000000000),
  advance_mode text check (advance_mode is null or advance_mode in ('cash', 'mobile', 'card')), advance_wallet text check (advance_wallet is null or char_length(advance_wallet) <= 30),
  note text check (note is null or char_length(note) <= 300),
  status text not null default 'new' check (status in ('new', 'confirmed', 'packed', 'delivered', 'cancelled')),
  sale_client uuid not null default gen_random_uuid(),           -- the client id given to record_sale2, so a retry can never make a 2nd sale
  sale_id uuid unique references public.sales(id),
  cancel_reason text, advance_fate text check (advance_fate is null or advance_fate in ('refund', 'adjust', 'income', 'none')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  delivered_by uuid, delivered_at timestamptz,
  check ((advance > 0) = (advance_mode is not null))
);
create unique index if not exists online_orders_no on public.online_orders (location_id, order_no);
create unique index if not exists online_orders_client on public.online_orders (created_by, client_id) where client_id is not null;
create index if not exists online_orders_by_status on public.online_orders (location_id, status, created_at desc);

create table if not exists public.online_order_events (
  id bigint generated always as identity primary key, order_id uuid not null references public.online_orders(id),
  from_status text, to_status text not null, note text, by_user uuid, by_staff text, at timestamptz not null default now()
);
create index if not exists online_order_events_o on public.online_order_events (order_id, id);

create or replace function public._oo_ro61() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_table_name = 'online_order_events' then raise exception 'append_only: the order trail cannot be changed or deleted'; end if;
  if tg_op = 'DELETE' then raise exception 'append_only: an order is never deleted, cancel it'; end if;
  if old.status in ('delivered', 'cancelled') then raise exception 'order_closed: a delivered or cancelled order cannot change'; end if;
  return new;
end $$;
drop trigger if exists online_orders_ro61 on public.online_orders;
create trigger online_orders_ro61 before update or delete on public.online_orders for each row execute function public._oo_ro61();
drop trigger if exists online_order_events_ro61 on public.online_order_events;
create trigger online_order_events_ro61 before update or delete on public.online_order_events for each row execute function public._oo_ro61();
drop trigger if exists audit_online_orders on public.online_orders;
create trigger audit_online_orders after insert or update on public.online_orders for each row execute function public.log_change('id');

-- normalise the order lines: item lines only, list price of today, qty > 0
create or replace function public._oo_lines61(p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ln jsonb; it public.items; q numeric; out jsonb := '[]'; sub numeric := 0;
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'no_lines'; end if;
  for ln in select * from jsonb_array_elements(p_lines) loop
    if nullif(ln->>'item_id', '') is null then raise exception 'item_required'; end if;
    select * into it from public.items where id = (ln->>'item_id')::uuid and is_active;
    if not found then raise exception 'item_not_found'; end if;
    q := (ln->>'qty')::numeric;
    if q is null or q = 'NaN'::numeric or q <= 0 or q > 1000000 then raise exception 'bad_qty'; end if;
    if it.sell_price is null then raise exception 'no_price'; end if;
    out := out || jsonb_build_object('item_id', it.id, 'code', it.code, 'name', it.name_bn, 'qty', q, 'price', it.sell_price, 'amount', round(q * it.sell_price, 2));
    sub := sub + round(q * it.sell_price, 2);
  end loop;
  return jsonb_build_object('lines', out, 'subtotal', sub);
end $$;

create or replace function public._oo_event61(p_order uuid, p_from text, p_to text, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.online_order_events (order_id, from_status, to_status, note, by_user, by_staff)
    values (p_order, p_from, p_to, left(nullif(btrim(p_note), ''), 300), auth.uid(), (select staff_id from public.profiles where id = auth.uid()));
end $$;

create or replace function public._oo_gate61(p_loc int, p_action text default 'enter') returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('online_orders_on') then raise exception 'module_off'; end if;
  if not public.can_do('POS', p_action) then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
end $$;

-- create (p_id null) or edit (status new / confirmed). Idempotent on p_client.
create or replace function public.online_order_save(p_id uuid, p_client uuid, p_loc int, p_channel text, p_name text, p_mobile text, p_address text, p_lines jsonb,
  p_delivery_mode text, p_delivery_by text, p_delivery_date date, p_charge numeric, p_discount numeric, p_advance numeric, p_adv_mode text, p_adv_wallet text, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; nl jsonb; sub numeric; n int; mob text; chg numeric := coalesce(p_charge, 0); dsc numeric := coalesce(p_discount, 0); adv numeric := coalesce(p_advance, 0); loc int := p_loc; sid text;
begin
  if p_id is not null then
    select * into o from public.online_orders where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    loc := o.location_id;
  else
    perform public._client_lock(p_client);
    if p_client is not null then
      select * into o from public.online_orders where client_id = p_client and created_by = auth.uid();
      if found then return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'dup', true); end if;
    end if;
  end if;
  perform public._oo_gate61(loc);
  if p_id is not null and o.status not in ('new', 'confirmed') then raise exception 'order_closed: only a new or confirmed order can be edited'; end if;
  if p_channel not in ('website', 'facebook', 'instagram', 'whatsapp', 'phone', 'foodapp', 'other') then raise exception 'bad_channel'; end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 80 then raise exception 'customer_name_required'; end if;
  mob := public.norm_mobile(p_mobile);
  if mob is null or char_length(mob) < 6 then raise exception 'bad_mobile'; end if;
  if p_delivery_mode not in ('pickup', 'home', 'courier') then raise exception 'bad_delivery_mode'; end if;
  if p_delivery_mode <> 'pickup' and nullif(btrim(p_address), '') is null then raise exception 'address_required'; end if;
  if char_length(coalesce(p_address, '')) > 300 or char_length(coalesce(p_note, '')) > 300 or char_length(coalesce(p_delivery_by, '')) > 60 then raise exception 'too_long'; end if;
  if p_delivery_date is not null and not (p_delivery_date between public._dhaka_today() - 1 and public._dhaka_today() + 365) then raise exception 'bad_date'; end if;
  if chg = 'NaN'::numeric or chg < 0 or chg > 1000000 then raise exception 'bad_amount'; end if;
  if dsc = 'NaN'::numeric or dsc < 0 or adv = 'NaN'::numeric or adv < 0 then raise exception 'bad_amount'; end if;
  nl := public._oo_lines61(p_lines); sub := (nl->>'subtotal')::numeric;
  dsc := round(dsc, 2); adv := round(adv, 2); chg := round(chg, 2);
  if dsc > sub then raise exception 'bad_discount'; end if;
  if adv > sub - dsc + chg then raise exception 'advance_over_total'; end if;
  if adv > 0 and coalesce(p_adv_mode, '') not in ('cash', 'mobile', 'card') then raise exception 'bad_mode'; end if;
  if adv = 0 then p_adv_mode := null; p_adv_wallet := null; end if;
  if p_id is null then
    select staff_id into sid from public.profiles where id = auth.uid();
    insert into public.serials (form_code, location_id, last) values ('ORD', loc, 1)
      on conflict (form_code, location_id) do update set last = public.serials.last + 1 returning last into n;
    insert into public.online_orders (client_id, order_no, location_id, channel, customer_name, customer_mobile, address, lines, subtotal, discount, delivery_mode, delivery_by, delivery_date,
        delivery_charge, advance, advance_mode, advance_wallet, note, created_by, created_staff)
      values (p_client, n, loc, p_channel, left(btrim(p_name), 80), mob, nullif(btrim(p_address), ''), nl->'lines', sub, dsc, p_delivery_mode, nullif(btrim(p_delivery_by), ''), p_delivery_date,
        chg, adv, p_adv_mode, left(nullif(btrim(p_adv_wallet), ''), 30), nullif(btrim(p_note), ''), auth.uid(), sid) returning * into o;
    perform public._oo_event61(o.id, null, 'new', 'created');
    return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'subtotal', sub, 'balance', sub - dsc + chg - adv);
  end if;
  update public.online_orders set channel = p_channel, customer_name = left(btrim(p_name), 80), customer_mobile = mob, address = nullif(btrim(p_address), ''), lines = nl->'lines', subtotal = sub,
      discount = dsc, delivery_mode = p_delivery_mode, delivery_by = nullif(btrim(p_delivery_by), ''), delivery_date = p_delivery_date, delivery_charge = chg, advance = adv,
      advance_mode = p_adv_mode, advance_wallet = left(nullif(btrim(p_adv_wallet), ''), 30), note = nullif(btrim(p_note), ''), updated_at = now()
    where id = o.id returning * into o;
  perform public._oo_event61(o.id, o.status, o.status, 'edited');
  return jsonb_build_object('id', o.id, 'order_no', o.order_no, 'status', o.status, 'subtotal', sub, 'balance', sub - dsc + chg - adv);
end $$;

-- confirm / pack (forward only)
create or replace function public.online_order_status(p_id uuid, p_to text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if p_to not in ('confirmed', 'packed') then raise exception 'bad_status'; end if;
  if o.status = p_to then return jsonb_build_object('id', o.id, 'status', o.status, 'noop', true); end if;
  if not ((o.status = 'new' and p_to = 'confirmed') or (o.status = 'confirmed' and p_to = 'packed')) then raise exception 'bad_status: % -> % is not allowed', o.status, p_to; end if;
  update public.online_orders set status = p_to, updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, p_to, p_note);
  return jsonb_build_object('id', o.id, 'status', p_to);
end $$;

create or replace function public.online_order_cancel(p_id uuid, p_reason text, p_advance_fate text default 'none') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.status = 'cancelled' then return jsonb_build_object('id', o.id, 'status', 'cancelled', 'noop', true); end if;
  if o.status = 'delivered' then raise exception 'order_closed: a delivered order has a sale; use the sale return'; end if;
  if nullif(btrim(p_reason), '') is null or char_length(p_reason) > 300 then raise exception 'reason_required'; end if;
  if coalesce(p_advance_fate, 'none') not in ('refund', 'adjust', 'income', 'none') then raise exception 'bad_fate'; end if;
  if o.advance > 0 and coalesce(p_advance_fate, 'none') = 'none' then raise exception 'advance_fate_required'; end if;
  update public.online_orders set status = 'cancelled', cancel_reason = btrim(p_reason), advance_fate = case when o.advance > 0 then p_advance_fate else 'none' end, updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, 'cancelled', btrim(p_reason) || case when o.advance > 0 then ' | advance: ' || p_advance_fate else '' end);
  return jsonb_build_object('id', o.id, 'status', 'cancelled', 'advance', o.advance, 'advance_fate', p_advance_fate);
end $$;

-- deliver: ONE sale through record_sale2 (advance counted as the first payment, p_payments = what is collected now). Retrying never makes a second sale.
create or replace function public.online_order_deliver(p_id uuid, p_payments jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; sl jsonb := '[]'; ln jsonb; pay jsonb := '[]'; res jsonb; sid uuid;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id);
  if o.sale_id is not null then return jsonb_build_object('id', o.id, 'status', o.status, 'sale_id', o.sale_id, 'dup', true); end if;
  if o.status <> 'packed' then raise exception 'bad_status: only a packed order can be delivered (now %)', o.status; end if;
  if p_payments is not null and jsonb_typeof(p_payments) <> 'array' then raise exception 'bad_payments'; end if;
  for ln in select * from jsonb_array_elements(o.lines) loop
    sl := sl || jsonb_build_object('item_id', ln->>'item_id', 'qty', (ln->>'qty')::numeric, 'price', (ln->>'price')::numeric);
  end loop;
  if o.delivery_charge > 0 then sl := sl || jsonb_build_object('name', 'Delivery charge', 'amount', o.delivery_charge); end if;
  if o.advance > 0 then pay := pay || jsonb_build_object('mode', o.advance_mode, 'amount', o.advance, 'wallet', o.advance_wallet, 'ref', 'online order #' || o.order_no || ' advance'); end if;
  pay := pay || coalesce(p_payments, '[]'::jsonb);
  res := public.record_sale2(o.sale_client, o.location_id, sl, o.discount, pay, o.customer_mobile, o.customer_name, 'retail', 'Online order #' || o.order_no, false, null);
  sid := (res->>'id')::uuid;
  if exists (select 1 from public.online_orders x where x.sale_id = sid and x.id <> o.id) then raise exception 'sale_already_linked'; end if;
  update public.online_orders set status = 'delivered', sale_id = sid, delivered_by = auth.uid(), delivered_at = now(), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, 'packed', 'delivered', 'sale receipt ' || (res->>'receipt'));
  return jsonb_build_object('id', o.id, 'status', 'delivered', 'sale_id', sid, 'receipt', res->'receipt', 'total', res->'total', 'paid', res->'paid', 'due', res->'due');
end $$;

-- link an order to a sale that already exists (sold over the counter meanwhile). Needs POS approve (or the owner). Never creates a sale.
create or replace function public.online_order_link_sale(p_id uuid, p_sale uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.online_orders; s public.sales;
begin
  select * into o from public.online_orders where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  perform public._oo_gate61(o.location_id, 'approve');
  if o.sale_id = p_sale then return jsonb_build_object('id', o.id, 'status', o.status, 'sale_id', o.sale_id, 'dup', true); end if;
  if o.status in ('delivered', 'cancelled') then raise exception 'order_closed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if s.location_id <> o.location_id then raise exception 'sale_other_location'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  if exists (select 1 from public.online_orders x where x.sale_id = p_sale) then raise exception 'sale_already_linked'; end if;
  update public.online_orders set status = 'delivered', sale_id = p_sale, delivered_by = auth.uid(), delivered_at = now(), updated_at = now() where id = o.id;
  perform public._oo_event61(o.id, o.status, 'delivered', 'linked to existing sale receipt ' || s.receipt || coalesce(' | ' || nullif(btrim(p_note), ''), ''));
  return jsonb_build_object('id', o.id, 'status', 'delivered', 'sale_id', p_sale, 'receipt', s.receipt, 'linked', true);
end $$;

create or replace function public.online_orders_list(p_loc int default null, p_status text default null, p_from date default null, p_to date default null, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() or not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
    select o.id, o.order_no, o.location_id, o.channel, o.customer_name, o.customer_mobile, o.delivery_mode, o.delivery_date, o.subtotal, o.discount, o.delivery_charge, o.advance,
           o.subtotal - o.discount + o.delivery_charge - o.advance as balance, o.status, o.sale_id, o.created_at
      from public.online_orders o
     where (p_loc is null or o.location_id = p_loc) and public.can_loc(o.location_id) and (p_status is null or o.status = p_status)
       and (p_from is null or o.created_at::date >= p_from) and (p_to is null or o.created_at::date <= p_to)
     order by o.created_at desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

create or replace function public.online_order_get(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.online_orders;
begin
  select * into o from public.online_orders where id = p_id;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(o.location_id) then raise exception 'not allowed'; end if;
  return to_jsonb(o) - 'sale_client' || jsonb_build_object('events', coalesce((select jsonb_agg(jsonb_build_object('from', e.from_status, 'to', e.to_status, 'note', e.note, 'by', e.by_staff, 'at', e.at) order by e.id)
                                                                                  from public.online_order_events e where e.order_id = o.id), '[]'::jsonb));
end $$;

-- =====================================================================
-- #12 FORMS 20-1 / 20-2 / 20-4 LINKED TO SALES (shadow engine)
-- =====================================================================
insert into public.path_domains (domain, a_bn, a_en, b_bn, b_en, default_primary, note_bn, note_en, sort) values
 ('sale_forms', 'বিক্রি (POS / ইনভয়েস)', 'Sale (POS / invoice)', 'ফর্ম 20-1 / 20-2 / 20-4', 'Forms 20-1 / 20-2 / 20-4', 'a',
  'বিক্রিই মূল রেকর্ড; জোড়া দেওয়া ফর্ম লক শ্যাডো কপি, কিছু পোস্ট করে না। পথ খ লক = নতুন জোড়া বন্ধ।', 'The sale is the record; a linked form is a locked shadow copy and posts nothing. Locking path B stops new links.', 80)
 on conflict (domain) do nothing;

create table if not exists public.sale_form_links (
  id bigint generated always as identity primary key,
  sale_id uuid not null references public.sales(id), entry_id uuid not null references public.entries(id),
  form_code text not null check (form_code in ('20-1', '20-2', '20-4')), location_id int not null,
  shadow_link_id bigint references public.shadow_links(id), amount_diff numeric,
  state text not null default 'active' check (state in ('active', 'void')), note text check (note is null or char_length(note) <= 300),
  linked_by uuid, linked_at timestamptz not null default now(), void_by uuid, void_at timestamptz, void_note text
);
create unique index if not exists sale_form_links_entry on public.sale_form_links (entry_id) where state = 'active';
create unique index if not exists sale_form_links_sale_form on public.sale_form_links (sale_id, form_code) where state = 'active';
create index if not exists sale_form_links_sale on public.sale_form_links (sale_id);
create or replace function public._sfl_ro61() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.state = 'active' and new.state = 'void'
     and (to_jsonb(new) - 'state' - 'void_by' - 'void_at' - 'void_note') = (to_jsonb(old) - 'state' - 'void_by' - 'void_at' - 'void_note') then return new; end if;
  raise exception 'append_only: sale_form_links is a trail, void it instead';
end $$;
drop trigger if exists sale_form_links_ro61 on public.sale_form_links;
create trigger sale_form_links_ro61 before update or delete on public.sale_form_links for each row execute function public._sfl_ro61();
drop trigger if exists audit_sale_form_links on public.sale_form_links;
create trigger audit_sale_form_links after insert or update on public.sale_form_links for each row execute function public.log_change('id');

-- a linked 20-x entry is a locked copy: no data change, no re-open (same lock the phase50 shadows have)
create or replace function public._entries_saleform_lock61() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.form_code in ('20-1', '20-2', '20-4') and old.status in ('submitted', 'approved') and (new.data is distinct from old.data or new.status = 'draft')
     and exists (select 1 from public.sale_form_links l where l.entry_id = old.id and l.state = 'active') then
    raise exception 'shadow_locked: this form is a locked copy of a sale; it cannot be changed or re-opened (the owner can unlink it first)';
  end if;
  return new;
end $$;
drop trigger if exists entries_saleform_lock61 on public.entries;
create trigger entries_saleform_lock61 before update on public.entries for each row execute function public._entries_saleform_lock61();

create or replace function public._sfl_total61(p_form text, p_data jsonb) returns numeric
language sql immutable as $$
  select case when p_form = '20-1' and (p_data->>'total') ~ '^-?[0-9]+(\.[0-9]+)?$' then round((p_data->>'total')::numeric - case when (p_data->>'discount') ~ '^-?[0-9]+(\.[0-9]+)?$' then (p_data->>'discount')::numeric else 0 end, 2) end;
$$;

create or replace function public.sale_form_link(p_entry uuid, p_sale uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e public.entries; s public.sales; ex public.sale_form_links; lk bigint; id_ bigint; tot numeric; diff numeric;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if not public.rule_on('sale_forms_link_on') then raise exception 'module_off'; end if;
  select * into e from public.entries where id = p_entry for update;
  if not found or e.form_code not in ('20-1', '20-2', '20-4') then raise exception 'form_not_linkable: only 20-1, 20-2 and 20-4'; end if;
  if e.status not in ('submitted', 'approved') then raise exception 'form_not_final: submit the form first'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  if s.location_id <> e.location_id then raise exception 'other_location'; end if;
  select * into ex from public.sale_form_links where entry_id = p_entry and state = 'active';
  if found then
    if ex.sale_id = p_sale then return jsonb_build_object('id', ex.id, 'dup', true); end if;
    raise exception 'entry_already_linked';
  end if;
  if exists (select 1 from public.sale_form_links where sale_id = p_sale and form_code = e.form_code and state = 'active') then raise exception 'sale_already_has_form'; end if;
  perform public.path_guard('sale_forms', e.location_id, 'b');
  lk := public.shadow_link_add('sale_forms', e.location_id, 'sales', p_sale::text, 'entries:' || e.form_code, p_entry::text, coalesce(nullif(btrim(p_note), ''), 'form ' || e.form_code || ' kept as a copy'));
  tot := public._sfl_total61(e.form_code, e.data);
  diff := case when tot is not null then round(tot - s.total, 2) end;
  insert into public.sale_form_links (sale_id, entry_id, form_code, location_id, shadow_link_id, amount_diff, note, linked_by)
    values (p_sale, p_entry, e.form_code, e.location_id, lk, diff, left(nullif(btrim(p_note), ''), 300), auth.uid()) returning id into id_;
  return jsonb_build_object('id', id_, 'shadow_link', lk, 'form', e.form_code, 'amount_diff', diff, 'amount_matches', coalesce(diff = 0, null));
end $$;

create or replace function public.sale_form_unlink(p_link bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l public.sale_form_links;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if nullif(btrim(p_note), '') is null then raise exception 'note_needed'; end if;
  select * into l from public.sale_form_links where id = p_link for update;
  if not found then raise exception 'not_found'; end if;
  if l.state = 'void' then return jsonb_build_object('id', l.id, 'state', 'void', 'noop', true); end if;
  if l.shadow_link_id is not null then perform public.shadow_void(l.shadow_link_id, p_note); end if;
  update public.sale_form_links set state = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = l.id;
  return jsonb_build_object('id', l.id, 'state', 'void');
end $$;

-- forms linked to one sale (anyone who may view the sale)
create or replace function public.sale_forms_for(p_sale uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales;
begin
  select * into s from public.sales where id = p_sale;
  if not found or not public.is_active() or not public.can_do('POS', 'view') or not public.can_loc(s.location_id) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'entry_id', l.entry_id, 'form_code', l.form_code, 'amount_diff', l.amount_diff, 'linked_at', l.linked_at) order by l.id)
                     from public.sale_form_links l where l.sale_id = p_sale and l.state = 'active'), '[]'::jsonb);
end $$;

-- report: 20-1 / 20-2 / 20-4 entries (submitted / approved) with no sale link, with up to 3 candidate sales
create or replace function public.unlinked_sale_forms(p_from date, p_to date, p_loc int default null, p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_date'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.entry_date, z.serial) from (
    select e.id as entry_id, e.form_code, e.serial, e.entry_date, e.location_id,
           coalesce(nullif(e.data->>'cust_name', ''), nullif(e.data->>'party', '')) as customer, public._sfl_total61(e.form_code, e.data) as form_total,
           coalesce((select jsonb_agg(c.id order by abs(c.sale_date - e.entry_date), c.receipt) from (
               select s.id, s.sale_date, s.receipt from public.sales s
                where s.location_id = e.location_id and s.status = 'done' and s.sale_date between e.entry_date - 3 and e.entry_date + 3
                  and (public._sfl_total61(e.form_code, e.data) is null or s.total = public._sfl_total61(e.form_code, e.data))
                  and not exists (select 1 from public.sale_form_links l where l.sale_id = s.id and l.form_code = e.form_code and l.state = 'active')
                order by abs(s.sale_date - e.entry_date), s.receipt limit 3) c), '[]'::jsonb) as candidate_sales
      from public.entries e
     where e.form_code in ('20-1', '20-2', '20-4') and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to
       and (p_loc is null or e.location_id = p_loc) and public.can_loc(e.location_id) and (public.is_owner() or public.can_do(e.form_code, 'view'))
       and not exists (select 1 from public.sale_form_links l where l.entry_id = e.id and l.state = 'active')
     order by e.entry_date, e.serial limit least(greatest(coalesce(p_limit, 200), 1), 1000)) z), '[]'::jsonb);
end $$;

-- =====================================================================
-- #13 BENEFITS DEPTH (report only; payroll maths untouched)
-- =====================================================================
create table if not exists public.benefit_types (
  code text primary key check (code ~ '^[a-z][a-z0-9_]{1,30}$'), name_bn text not null check (char_length(btrim(name_bn)) between 1 and 80), name_en text,
  paid_in_payroll boolean not null default false,                       -- default for new grants: the value is paid through the salary sheet
  eligible_after_days int not null default 0 check (eligible_after_days between 0 and 3650),   -- days after the joining date
  default_for_all boolean not null default false,                       -- every active employee should hold it once eligible (feeds the "missing" list)
  active boolean not null default true, sort int not null default 100, updated_by uuid, updated_at timestamptz not null default now()
);
insert into public.benefit_types (code, name_bn, name_en, sort) values
 ('meal', 'খাবার', 'Meal', 10), ('uniform', 'ইউনিফর্ম', 'Uniform', 20), ('accommodation', 'থাকার ব্যবস্থা', 'Accommodation', 30), ('transport', 'যাতায়াত', 'Transport', 40),
 ('phone', 'ফোন', 'Phone', 50), ('insurance', 'বিমা', 'Insurance', 60), ('other', 'অন্যান্য', 'Other', 90)
 on conflict (code) do nothing;

create table if not exists public.employee_benefit_grants (
  id bigserial primary key, client_id uuid unique, employee_id uuid not null references public.employees(id), type_code text not null references public.benefit_types(code),
  from_date date not null, eligible_from date not null, to_date date, status text not null default 'active' check (status in ('active', 'ended')),
  paid_in_payroll boolean not null default false,
  value_per_month numeric check (value_per_month is null or (value_per_month >= 0 and value_per_month <= 1000000000000)),   -- column hidden from the browser (salary_view only through the report)
  note text check (note is null or char_length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz not null default now(),
  check (to_date is null or to_date >= from_date), check (eligible_from >= from_date)
);
create index if not exists employee_benefit_grants_emp on public.employee_benefit_grants (employee_id, type_code);
drop trigger if exists audit_employee_benefit_grants on public.employee_benefit_grants;
create trigger audit_employee_benefit_grants after insert or update on public.employee_benefit_grants for each row execute function public.log_change('id');
drop trigger if exists audit_benefit_types on public.benefit_types;
create trigger audit_benefit_types after insert or update on public.benefit_types for each row execute function public.log_change('code');

create or replace function public.benefit_type_save(p_code text, p_name_bn text, p_name_en text, p_paid boolean, p_days int, p_default_all boolean, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform public._emp_gate();
  if not (public.is_owner() or public.has_grant('salary_manage')) then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,30}$' then raise exception 'bad_code'; end if;
  if nullif(btrim(coalesce(p_name_bn, '')), '') is null or char_length(p_name_bn) > 80 or char_length(coalesce(p_name_en, '')) > 80 then raise exception 'bad_name'; end if;
  if p_days is null or p_days not between 0 and 3650 then raise exception 'bad_days'; end if;
  insert into public.benefit_types (code, name_bn, name_en, paid_in_payroll, eligible_after_days, default_for_all, active, updated_by)
    values (p_code, btrim(p_name_bn), coalesce(nullif(btrim(p_name_en), ''), btrim(p_name_bn)), coalesce(p_paid, false), p_days, coalesce(p_default_all, false), coalesce(p_active, true), auth.uid())
    on conflict (code) do update set name_bn = excluded.name_bn, name_en = excluded.name_en, paid_in_payroll = excluded.paid_in_payroll, eligible_after_days = excluded.eligible_after_days,
      default_for_all = excluded.default_for_all, active = excluded.active, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('code', p_code);
end $$;

create or replace function public.employee_benefit_grant(p_id bigint, p_client uuid, p_emp uuid, p_type text, p_from date, p_to date, p_value numeric, p_paid boolean default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefit_grants; t public.benefit_types; e public.employees; v_today date := public._dhaka_today(); elig date; emp uuid := p_emp;
begin
  perform public._emp_gate();
  if not public.rule_on('benefit_grants_on') then raise exception 'module_off'; end if;
  perform public._client_lock(p_client);
  if p_id is not null then
    select * into r from public.employee_benefit_grants where id = p_id for update;
    if not found then raise exception 'not_found'; end if;
    emp := r.employee_id;
    if r.status <> 'active' then raise exception 'grant_ended'; end if;
  elsif p_client is not null then
    select * into r from public.employee_benefit_grants where client_id = p_client;
    if found then return jsonb_build_object('id', r.id, 'repeat', true); end if;
  end if;
  if not public._emp_ok(emp, array['employee_manage', 'salary_manage']) then raise exception 'not allowed'; end if;
  if p_value is not null and not public._emp_ok(emp, array['salary_manage']) then raise exception 'not allowed'; end if;
  select * into e from public.employees where id = emp;
  if not found then raise exception 'not_found'; end if;
  select * into t from public.benefit_types where code = coalesce(p_type, r.type_code);
  if not found or not t.active then raise exception 'bad_type'; end if;
  if p_value is not null and not (p_value between 0 and 1000000000000) then raise exception 'bad_amount'; end if;
  if p_from is null or not (p_from between v_today - 1830 and v_today + 366) then raise exception 'bad_date'; end if;
  if p_to is not null and p_to < p_from then raise exception 'bad_date'; end if;
  if char_length(coalesce(p_note, '')) > 300 then raise exception 'too_long: note'; end if;
  if exists (select 1 from public.employee_benefit_grants g where g.employee_id = emp and g.type_code = t.code and g.status = 'active' and (p_id is null or g.id <> p_id)
               and daterange(g.from_date, coalesce(g.to_date, 'infinity'::date), '[]') && daterange(p_from, coalesce(p_to, 'infinity'::date), '[]')) then raise exception 'overlap: this employee already holds this benefit in those dates'; end if;
  elig := greatest(p_from, case when e.joining_date is not null then e.joining_date + t.eligible_after_days else p_from end);
  if p_id is null then
    insert into public.employee_benefit_grants (client_id, employee_id, type_code, from_date, eligible_from, to_date, paid_in_payroll, value_per_month, note, created_by, updated_by)
      values (p_client, emp, t.code, p_from, elig, p_to, coalesce(p_paid, t.paid_in_payroll), p_value, nullif(btrim(p_note), ''), auth.uid(), auth.uid()) returning * into r;
  else
    update public.employee_benefit_grants set from_date = p_from, eligible_from = elig, to_date = p_to, paid_in_payroll = coalesce(p_paid, paid_in_payroll),
        value_per_month = case when p_value is not null then p_value else value_per_month end, note = nullif(btrim(p_note), ''), updated_by = auth.uid(), updated_at = now()
      where id = r.id returning * into r;
  end if;
  return jsonb_build_object('id', r.id, 'eligible_from', r.eligible_from, 'paid_in_payroll', r.paid_in_payroll);
end $$;

create or replace function public.employee_benefit_grant_end(p_id bigint, p_to date, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.employee_benefit_grants;
begin
  perform public._emp_gate();
  select * into r from public.employee_benefit_grants where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if not public._emp_ok(r.employee_id, array['employee_manage']) then raise exception 'not allowed'; end if;
  if r.status = 'ended' then return jsonb_build_object('id', r.id, 'noop', true); end if;
  if p_to is null or p_to < r.from_date or p_to > public._dhaka_today() + 366 then raise exception 'bad_date'; end if;
  update public.employee_benefit_grants set status = 'ended', to_date = p_to, note = left(coalesce(nullif(btrim(p_note), ''), note), 300), updated_by = auth.uid(), updated_at = now() where id = r.id;
  return jsonb_build_object('id', r.id, 'to_date', p_to);
end $$;

-- report: every grant (state not_yet / eligible / ended), the paid-in-payroll flag, and the people who are past eligibility for a default_for_all type but hold no grant
create or replace function public.benefits_report(p_as_of date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_as_of, public._dhaka_today()); grants jsonb; missing jsonb; tot numeric;
begin
  perform public._emp_gate();
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(to_jsonb(z) order by z.employee_name, z.type_code), '[]'::jsonb), coalesce(sum(z.value_per_month) filter (where z.state = 'eligible' and z.paid_in_payroll), 0)
    into grants, tot from (
    select g.id, g.employee_id, e.employee_no, e.full_name_bn as employee_name, e.primary_location_id as location_id, g.type_code, t.name_bn as type_name, g.from_date, g.eligible_from, g.to_date,
           case when g.status = 'ended' or (g.to_date is not null and g.to_date < d) then 'ended' when g.eligible_from > d then 'not_yet' else 'eligible' end as state,
           g.paid_in_payroll, case when public._emp_ok(g.employee_id, array['salary_view']) then g.value_per_month end as value_per_month
      from public.employee_benefit_grants g join public.employees e on e.id = g.employee_id join public.benefit_types t on t.code = g.type_code
     where (p_loc is null or e.primary_location_id = p_loc) and public._emp_ok(g.employee_id, array['employee_view', 'employee_manage', 'salary_view'], true) limit 2000) z;
  select coalesce(jsonb_agg(jsonb_build_object('employee_id', e.id, 'employee_no', e.employee_no, 'employee_name', e.full_name_bn, 'type_code', t.code, 'type_name', t.name_bn,
           'eligible_from', e.joining_date + t.eligible_after_days) order by e.full_name_bn, t.code), '[]'::jsonb) into missing
    from public.employees e cross join public.benefit_types t
   where t.active and t.default_for_all and e.status = 'active' and e.joining_date is not null and e.joining_date + t.eligible_after_days <= d
     and (p_loc is null or e.primary_location_id = p_loc) and public._emp_ok(e.id, array['employee_view', 'employee_manage', 'salary_view'], true)
     and not exists (select 1 from public.employee_benefit_grants g where g.employee_id = e.id and g.type_code = t.code and g.status = 'active' and g.from_date <= d and (g.to_date is null or g.to_date >= d));
  return jsonb_build_object('as_of', d, 'grants', grants, 'missing', missing, 'paid_in_payroll_monthly_visible', tot,
    'note', 'report only: payroll maths does not read these grants');
end $$;

-- =====================================================================
-- #14 BI EXPORT (read only data; one log row per call)
-- =====================================================================
create table if not exists public.bi_export_log (
  id bigint generated always as identity primary key, at timestamptz not null default now(), user_id uuid, staff_id text,
  dataset text not null, date_from date not null, date_to date not null, location_id int, format text not null, row_limit int not null,
  row_count int not null, truncated boolean not null, cost_included boolean not null
);
create or replace function public._bil_ro61() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: the export log cannot be changed or deleted'; end $$;
drop trigger if exists bi_export_log_ro61 on public.bi_export_log;
create trigger bi_export_log_ro61 before update or delete on public.bi_export_log for each row execute function public._bil_ro61();

create or replace function public._bi_csv61(p_cols text[], p_rows jsonb) returns text
language plpgsql immutable set search_path = public as $$
declare out text := array_to_string(p_cols, ','); r jsonb; c text; v jsonb; t text; cells text[];
begin
  for r in select * from jsonb_array_elements(p_rows) loop
    cells := '{}';
    foreach c in array p_cols loop
      v := r -> c;
      if v is null or jsonb_typeof(v) = 'null' then t := '';
      elsif jsonb_typeof(v) in ('number', 'boolean') then t := v #>> '{}';
      else
        t := v #>> '{}';
        if t ~ '^[=+@-]' or left(t, 1) in (E'\t', E'\r') then t := '''' || t; end if;      -- spreadsheet formula guard
        if t ~ '[",]' or position(E'\n' in t) > 0 or position(E'\r' in t) > 0 then t := '"' || replace(t, '"', '""') || '"'; end if;
      end if;
      cells := cells || t;
    end loop;
    out := out || E'\n' || array_to_string(cells, ',');
  end loop;
  return out;
end $$;

create or replace function public.bi_export(p_dataset text, p_from date, p_to date, p_loc int default null, p_format text default 'json', p_limit int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cap int; lim int; rows jsonb; cols text[]; trunc boolean := false; cost boolean := public.rpt_cost_ok(); logid bigint; fmt text := lower(coalesce(p_format, 'json')); n int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.rule_on('bi_export_on') then raise exception 'module_off'; end if;
  if not (public.is_owner() or public.rpt_grant('export_data')) then raise exception 'not allowed'; end if;
  if p_dataset not in ('sales', 'sale_lines', 'purchases', 'stock_ledger', 'journal') then raise exception 'bad_dataset'; end if;
  if fmt not in ('json', 'csv') then raise exception 'bad_format'; end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then raise exception 'bad_date: from/to required, at most 366 days'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  cap := least(greatest(coalesce(public.rule_num('bi_export_max_rows'), 5000), 100), 20000)::int;
  lim := least(greatest(coalesce(p_limit, cap), 1), cap);
  if p_dataset in ('sales', 'sale_lines') and not public.can_do('POS', 'view') then raise exception 'not allowed'; end if;
  if p_dataset = 'purchases' and not cost then raise exception 'cost_not_allowed: purchase data carries cost prices'; end if;
  if p_dataset = 'journal' and not public._acct_view() then raise exception 'not allowed'; end if;

  if p_dataset = 'sales' then
    cols := array['id', 'receipt', 'sale_date', 'location_id', 'status', 'sale_type', 'pay_mode', 'subtotal', 'discount', 'total', 'paid', 'due_amount', 'customer', 'line_count'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sale_date, x.location_id, x.receipt), '[]'::jsonb) into rows from (
      select s.id, s.receipt, s.sale_date, s.location_id, s.status, s.sale_type, s.pay_mode, s.subtotal, s.discount, s.total, s.paid, s.due_amount, s.customer, jsonb_array_length(s.lines) as line_count
        from public.sales s where s.sale_date between p_from and p_to and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
        order by s.sale_date, s.location_id, s.receipt limit lim + 1) x;
  elsif p_dataset = 'sale_lines' then
    cols := array['sale_id', 'receipt', 'sale_date', 'location_id', 'status', 'line_no', 'item_id', 'code', 'name', 'qty', 'price', 'amount'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sale_date, x.location_id, x.receipt, x.line_no), '[]'::jsonb) into rows from (
      select s.id as sale_id, s.receipt, s.sale_date, s.location_id, s.status, l.ord::int as line_no, l.v->>'item_id' as item_id, l.v->>'code' as code, l.v->>'name' as name,
             (l.v->>'qty')::numeric as qty, (l.v->>'price')::numeric as price, (l.v->>'amount')::numeric as amount
        from public.sales s cross join lateral jsonb_array_elements(s.lines) with ordinality as l(v, ord)
       where s.sale_date between p_from and p_to and (p_loc is null or s.location_id = p_loc) and public.can_loc(s.location_id)
       order by s.sale_date, s.location_id, s.receipt, l.ord limit lim + 1) x;
  elsif p_dataset = 'purchases' then
    cols := array['bill_id', 'bill_no', 'bill_date', 'kind', 'status', 'supplier_id', 'location_id', 'line_no', 'item_id', 'description', 'qty', 'unit', 'unit_cost', 'amount'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.bill_date, x.bill_id, x.line_no), '[]'::jsonb) into rows from (
      select b.id as bill_id, b.bill_no, b.bill_date, b.kind, b.status, b.supplier_id, b.location_id, l.line_no, l.item_id, l.description, l.qty, l.unit, l.unit_cost, l.amount
        from public.purchase_bills b join public.purchase_lines l on l.bill_id = b.id
       where b.bill_date between p_from and p_to and (p_loc is null or b.location_id = p_loc) and public._pur_ok(b.location_id)
       order by b.bill_date, b.id, l.line_no limit lim + 1) x;
  elsif p_dataset = 'stock_ledger' then
    cols := array['id', 'made_at', 'item_id', 'location_id', 'qty_delta', 'unit_cost', 'reason', 'ref_type', 'ref_id', 'reverses_id'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]'::jsonb) into rows from (
      select k.id, k.made_at, k.item_id, k.location_id, k.qty_delta, case when cost then k.unit_cost end as unit_cost, k.reason, k.ref_type, k.ref_id, k.reverses_id
        from public.stock_ledger k where (k.made_at at time zone 'Asia/Dhaka')::date between p_from and p_to and (p_loc is null or k.location_id = p_loc) and public.can_loc(k.location_id)
       order by k.id limit lim + 1) x;
  else
    cols := array['entry_id', 'entry_date', 'location_id', 'source_type', 'source_id', 'status', 'memo', 'line_no', 'account_id', 'debit', 'credit'];
    select coalesce(jsonb_agg(to_jsonb(x) order by x.entry_date, x.entry_id, x.line_no), '[]'::jsonb) into rows from (
      select j.id as entry_id, j.entry_date, j.location_id, j.source_type, j.source_id, j.status, j.memo, l.line_no, l.account_id, l.debit, l.credit
        from public.journal_entries j join public.journal_lines l on l.entry_id = j.id
       where j.entry_date between p_from and p_to and (p_loc is null or j.location_id = p_loc) and (public._acct_all() or (j.location_id is not null and public.can_loc(j.location_id)))
       order by j.entry_date, j.id, l.line_no limit lim + 1) x;
  end if;

  n := jsonb_array_length(rows);
  if n > lim then trunc := true; rows := rows - lim; n := lim; end if;
  insert into public.bi_export_log (user_id, staff_id, dataset, date_from, date_to, location_id, format, row_limit, row_count, truncated, cost_included)
    values (auth.uid(), (select staff_id from public.profiles where id = auth.uid()), p_dataset, p_from, p_to, p_loc, fmt, lim, n, trunc, cost and p_dataset in ('purchases', 'stock_ledger'))
    returning id into logid;
  return jsonb_build_object('dataset', p_dataset, 'format', fmt, 'columns', to_jsonb(cols), 'row_count', n, 'truncated', trunc, 'cap', cap, 'cost_visible', cost, 'log_id', logid)
    || case when fmt = 'csv' then jsonb_build_object('csv', public._bi_csv61(cols, rows)) else jsonb_build_object('rows', rows) end;
end $$;

create or replace function public.bi_export_log_list(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.id desc) from (select * from public.bi_export_log order by id desc limit least(greatest(coalesce(p_limit, 100), 1), 500)) z), '[]'::jsonb);
end $$;

-- =====================================================================
-- RLS + privileges
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['online_orders', 'online_order_events', 'sale_form_links', 'benefit_types', 'employee_benefit_grants', 'bi_export_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
  end loop;
end $$;
grant select on public.online_orders, public.online_order_events, public.sale_form_links, public.benefit_types, public.bi_export_log to authenticated;
-- the grant value is salary data: every column except value_per_month
grant select (id, client_id, employee_id, type_code, from_date, eligible_from, to_date, status, paid_in_payroll, note, created_by, created_at, updated_by, updated_at) on public.employee_benefit_grants to authenticated;
-- order secrets: sale_client stays server side
revoke select on public.online_orders from authenticated;
grant select (id, client_id, order_no, location_id, channel, customer_name, customer_mobile, address, lines, subtotal, discount, delivery_mode, delivery_by, delivery_date, delivery_charge,
  advance, advance_mode, advance_wallet, note, status, sale_id, cancel_reason, advance_fate, created_by, created_staff, created_at, updated_at, delivered_by, delivered_at) on public.online_orders to authenticated;

create policy online_orders_sel on public.online_orders for select to authenticated using (public.can_do('POS', 'view') and public.can_loc(location_id));
create policy online_order_events_sel on public.online_order_events for select to authenticated
  using (exists (select 1 from public.online_orders o where o.id = order_id and public.can_do('POS', 'view') and public.can_loc(o.location_id)));
create policy sale_form_links_sel on public.sale_form_links for select to authenticated using (public.is_owner() or (public.can_do('POS', 'view') and public.can_loc(location_id)));
create policy benefit_types_sel on public.benefit_types for select to authenticated using (public.is_active());
create policy employee_benefit_grants_sel on public.employee_benefit_grants for select to authenticated using (public._emp_ok(employee_id, array['employee_view', 'employee_manage', 'salary_view'], true));
create policy bi_export_log_sel on public.bi_export_log for select to authenticated using (public.is_owner());

-- browser-callable
revoke all on function public.online_order_save(uuid, uuid, int, text, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text), public.online_order_status(uuid, text, text),
  public.online_order_cancel(uuid, text, text), public.online_order_deliver(uuid, jsonb), public.online_order_link_sale(uuid, uuid, text), public.online_orders_list(int, text, date, date, int),
  public.online_order_get(uuid), public.sale_form_link(uuid, uuid, text), public.sale_form_unlink(bigint, text), public.sale_forms_for(uuid), public.unlinked_sale_forms(date, date, int, int),
  public.benefit_type_save(text, text, text, boolean, int, boolean, boolean), public.employee_benefit_grant(bigint, uuid, uuid, text, date, date, numeric, boolean, text),
  public.employee_benefit_grant_end(bigint, date, text), public.benefits_report(date, int), public.bi_export(text, date, date, int, text, int), public.bi_export_log_list(int) from public, anon;
grant execute on function public.online_order_save(uuid, uuid, int, text, text, text, text, jsonb, text, text, date, numeric, numeric, numeric, text, text, text), public.online_order_status(uuid, text, text),
  public.online_order_cancel(uuid, text, text), public.online_order_deliver(uuid, jsonb), public.online_order_link_sale(uuid, uuid, text), public.online_orders_list(int, text, date, date, int),
  public.online_order_get(uuid), public.sale_form_link(uuid, uuid, text), public.sale_form_unlink(bigint, text), public.sale_forms_for(uuid), public.unlinked_sale_forms(date, date, int, int),
  public.benefit_type_save(text, text, text, boolean, int, boolean, boolean), public.employee_benefit_grant(bigint, uuid, uuid, text, date, date, numeric, boolean, text),
  public.employee_benefit_grant_end(bigint, date, text), public.benefits_report(date, int), public.bi_export(text, date, date, int, text, int), public.bi_export_log_list(int) to authenticated;
-- helpers: never from the browser
revoke all on function public._oo_lines61(jsonb), public._oo_event61(uuid, text, text, text), public._oo_gate61(int, text), public._oo_ro61(), public._sfl_ro61(), public._entries_saleform_lock61(),
  public._sfl_total61(text, jsonb), public._bil_ro61(), public._bi_csv61(text[], jsonb) from public, anon, authenticated;
notify pgrst, 'reload schema';
