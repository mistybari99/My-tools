-- Phase 434 (bos434) - RPT-B3 / R7a: PRICE TREND WITH VALUE (#92), AGREED PRICE PER ITEM AND SUPPLIER (#101), PREFERRED / ALTERNATIVE SUPPLIERS PER ITEM (#104, the capture part).
-- Paste after phase433. Paste-twice safe. Earlier phase files are not edited. The only existing thing changed in place is the purchase-rate-trend report (engine 3, key p2_rate_trend): it gains
-- ONE column (value = quantity x rate, summed) and a total; every existing column, filter and the cost-right rule are unchanged.
--
-- WHAT THIS ADDS
--   1. supplier_item_prices: the standard / agreed price of an item from a supplier (per the unit the owner types; stored per base unit), with a from-date. A new price closes the previous
--      one the day before. Nothing is deleted: a price is retired with a note. supplier_price_set / supplier_price_retire / supplier_price_list.
--   2. item_suppliers: which suppliers may supply an item, "preferred" or "alternative". item_supplier_set / item_supplier_retire / item_supplier_list.
--   3. Grant supplier_terms_manage (purchasing and management get it the first time it is created). The owner always may.
-- COST IS SECRET: agreed prices are costs. They are returned only to the owner, a holder of the cost right (rpt_cost_ok) or a holder of supplier_terms_manage. The tables are not readable by browsers.
-- No price, limit or tolerance is invented: a blank is a blank. Paper form code of these two captures: to be given by owner (digital entry screens only for now).

do $g$ begin
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase434 needs phase430 first'; end if;
  if to_regclass('public.report_defs3') is null then raise exception 'phase434 needs phase24 and phase26 (report engine 3)'; end if;
end $g$;

-- ---------- #92 purchase-rate trend: a value column ----------
create or replace function public._r3q_p2_rate_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  x as (
    select r.item_id, r.sk, min(r.sname) as sname, count(*) as n, sum(r.qty) as qty,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           min(r.rate) as min_rate, max(r.rate) as max_rate, sum(r.qty * r.rate) / nullif(sum(r.qty), 0) as avg_rate, sum(r.qty * r.rate) as value, max(r.dt) as last_date
      from public._p26_rates(d1, d2, locs) r group by r.item_id, r.sk)
  select jsonb_build_object('item_code', i.code, 'item_bn', i.name_bn, 'supplier', x.sname, 'n', x.n, 'qty', round(x.qty, 3),
    'first_rate', round(x.first_rate, 4), 'last_rate', round(x.last_rate, 4), 'min_rate', round(x.min_rate, 4), 'max_rate', round(x.max_rate, 4), 'avg_rate', round(x.avg_rate, 4),
    'value', round(x.value, 2),
    'change_pct', case when x.n > 1 and x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end, 'last_date', x.last_date)
    from x join public.items i on i.id = x.item_id cross join cat
   where cat.c is null or i.category = any (cat.c);
$$;
update public.report_defs3 set
  cols = '[["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["supplier","সাপ্লায়ার","Supplier","text"],["n","বার","Times","int"],["qty","পরিমাণ","Quantity","num"],["first_rate","প্রথম দর","First rate","money"],["last_rate","শেষ দর","Last rate","money"],["min_rate","সর্বনিম্ন","Lowest","money"],["max_rate","সর্বোচ্চ","Highest","money"],["avg_rate","গড় দর","Average rate","money"],["value","মূল্য (পরিমাণ × দর)","Value (quantity x rate)","money"],["change_pct","বদল %","Change %","pct"],["last_date","শেষ তারিখ","Last date","date"]]'::jsonb,
  tot = array['value']
 where key = 'p2_rate_trend';
revoke all on function public._r3q_p2_rate_trend(date, date, int[], jsonb) from public, anon, authenticated;

-- ---------- grant ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('supplier_terms_manage', 'purchase', 54, 'সাপ্লায়ারের নির্ধারিত দাম ও পছন্দের সাপ্লায়ার ঠিক করা', 'Supplier এর agreed price ও preferred supplier ঠিক করা', 'Set agreed supplier prices and preferred / alternative suppliers', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('supplier_terms_manage', 'purchasing'), ('supplier_terms_manage', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

create or replace function public._rb3_terms_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('supplier_terms_manage'));
$$;
-- may the caller see agreed prices (costs)?
create or replace function public._rb3_terms_cost_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_cost_ok() or public.has_grant('supplier_terms_manage'));
$$;

-- ---------- tables ----------
create table if not exists public.supplier_item_prices (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  supplier_id uuid not null references public.suppliers(id),
  price numeric not null check (price > 0 and price <= 1000000000),                 -- as typed, per unit
  unit text,                                                                         -- the unit the price is per (null = the item's base unit)
  price_base numeric not null check (price_base > 0 and price_base <= 1000000000),  -- per base unit (what the bill lines are compared with)
  effective_from date not null,
  effective_to date,
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(),
  retired_by uuid, retired_at timestamptz, retired_note text,
  check (effective_to is null or effective_to >= effective_from)
);
create index if not exists supplier_item_prices_pair on public.supplier_item_prices (item_id, supplier_id, effective_from);
drop trigger if exists audit_supplier_item_prices on public.supplier_item_prices;
create trigger audit_supplier_item_prices after insert or update on public.supplier_item_prices for each row execute function public.log_change('id');
alter table public.supplier_item_prices enable row level security;
revoke all on public.supplier_item_prices from public, anon, authenticated;
revoke all on sequence public.supplier_item_prices_id_seq from public, anon, authenticated;

create table if not exists public.item_suppliers (
  id bigserial primary key,
  item_id uuid not null references public.items(id),
  supplier_id uuid not null references public.suppliers(id),
  rank text not null check (rank in ('preferred', 'alternative')),
  active boolean not null default true,
  note text check (note is null or length(note) <= 300),
  created_by uuid, created_at timestamptz not null default now(), updated_by uuid, updated_at timestamptz,
  retired_note text,
  unique (item_id, supplier_id)
);
create index if not exists item_suppliers_item on public.item_suppliers (item_id) where active;
drop trigger if exists audit_item_suppliers on public.item_suppliers;
create trigger audit_item_suppliers after insert or update on public.item_suppliers for each row execute function public.log_change('id');
alter table public.item_suppliers enable row level security;
drop policy if exists item_suppliers_read on public.item_suppliers;
create policy item_suppliers_read on public.item_suppliers for select to authenticated using (public.is_active());
revoke all on public.item_suppliers from public, anon, authenticated;
grant select on public.item_suppliers to authenticated;
revoke all on sequence public.item_suppliers_id_seq from public, anon, authenticated;

-- ---------- agreed prices ----------
create or replace function public.supplier_price_set(p_item uuid, p_supplier uuid, p_price numeric, p_unit text default null, p_from date default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; fr date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date); f numeric; prev public.supplier_item_prices; nid bigint; un text := nullif(btrim(p_unit), '');
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.items where id = p_item and is_active) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
  if p_price is null or not (p_price > 0 and p_price <= 1000000000) then raise exception 'bad_price'; end if;
  if fr > today + 366 or fr < date '2000-01-01' then raise exception 'bad_date'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'bad_note'; end if;
  f := public._unit_factor_base(p_item, un);
  if f is null or not (f > 0) then raise exception 'unit_unknown'; end if;
  select * into prev from public.supplier_item_prices where item_id = p_item and supplier_id = p_supplier and active and effective_to is null order by effective_from desc limit 1 for update;
  if found then
    if prev.effective_from >= fr then raise exception 'overlaps_existing'; end if;
    update public.supplier_item_prices set effective_to = fr - 1 where id = prev.id;
  end if;
  insert into public.supplier_item_prices (item_id, supplier_id, price, unit, price_base, effective_from, note, created_by)
    values (p_item, p_supplier, round(p_price, 4), un, round(p_price / f, 6), fr, nullif(btrim(p_note), ''), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid, 'price_base', round(p_price / f, 6), 'closed_previous', prev.id);
end $$;

create or replace function public.supplier_price_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.supplier_item_prices;
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  select * into r from public.supplier_item_prices where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not r.active then return jsonb_build_object('dup', true); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.supplier_item_prices set active = false, retired_by = auth.uid(), retired_at = now(), retired_note = left(btrim(p_note), 300),
    effective_to = coalesce(effective_to, greatest(effective_from, (now() at time zone 'Asia/Dhaka')::date)) where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

create or replace function public.supplier_price_list(p_item uuid default null, p_supplier uuid default null, p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._rb3_terms_cost_ok() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'item_id', p.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'supplier_id', p.supplier_id, 'supplier', s.name,
      'price', p.price, 'unit', p.unit, 'base_unit', public._item_base(p.item_id), 'price_base', p.price_base, 'effective_from', p.effective_from, 'effective_to', p.effective_to, 'active', p.active,
      'current', p.active and p.effective_from <= (now() at time zone 'Asia/Dhaka')::date and (p.effective_to is null or p.effective_to >= (now() at time zone 'Asia/Dhaka')::date),
      'note', p.note, 'retired_note', p.retired_note, 'can_edit', public._rb3_terms_ok()) order by i.code, s.name, p.effective_from desc)
    from public.supplier_item_prices p join public.items i on i.id = p.item_id join public.suppliers s on s.id = p.supplier_id
   where (p_item is null or p.item_id = p_item) and (p_supplier is null or p.supplier_id = p_supplier) and (coalesce(p_all, false) or p.active)), '[]'::jsonb);
end $$;

-- ---------- preferred / alternative suppliers ----------
create or replace function public.item_supplier_set(p_item uuid, p_supplier uuid, p_rank text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.item_suppliers; nid bigint;
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  if p_rank is null or p_rank not in ('preferred', 'alternative') then raise exception 'bad_rank'; end if;
  if not exists (select 1 from public.items where id = p_item and is_active) then raise exception 'item_not_found'; end if;
  if not exists (select 1 from public.suppliers where id = p_supplier and active) then raise exception 'supplier_not_found'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'bad_note'; end if;
  select * into r from public.item_suppliers where item_id = p_item and supplier_id = p_supplier for update;
  if found then
    update public.item_suppliers set rank = p_rank, active = true, note = coalesce(nullif(btrim(p_note), ''), note), updated_by = auth.uid(), updated_at = now(), retired_note = null where id = r.id;
    return jsonb_build_object('id', r.id, 'updated', true);
  end if;
  insert into public.item_suppliers (item_id, supplier_id, rank, note, created_by) values (p_item, p_supplier, p_rank, nullif(btrim(p_note), ''), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid, 'updated', false);
end $$;

create or replace function public.item_supplier_retire(p_id bigint, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.item_suppliers;
begin
  if not public._rb3_terms_ok() then raise exception 'not allowed'; end if;
  select * into r from public.item_suppliers where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not r.active then return jsonb_build_object('dup', true); end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'note_required'; end if;
  update public.item_suppliers set active = false, updated_by = auth.uid(), updated_at = now(), retired_note = left(btrim(p_note), 300) where id = p_id;
  return jsonb_build_object('id', p_id, 'active', false);
end $$;

create or replace function public.item_supplier_list(p_item uuid default null, p_supplier uuid default null, p_all boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('purchase') or public.rpt_access('stock') or public.has_grant('supplier_terms_manage'))) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'supplier_id', x.supplier_id, 'supplier', s.name,
      'rank', x.rank, 'active', x.active, 'note', x.note, 'retired_note', x.retired_note, 'can_edit', public._rb3_terms_ok()) order by i.code, x.rank, s.name)
    from public.item_suppliers x join public.items i on i.id = x.item_id join public.suppliers s on s.id = x.supplier_id
   where (p_item is null or x.item_id = p_item) and (p_supplier is null or x.supplier_id = p_supplier) and (coalesce(p_all, false) or x.active)), '[]'::jsonb);
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_terms_ok', '_rb3_terms_cost_ok') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('supplier_price_set', 'supplier_price_retire', 'supplier_price_list', 'item_supplier_set', 'item_supplier_retire', 'item_supplier_list') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
select public._r3_lockdown();

notify pgrst, 'reload schema';
