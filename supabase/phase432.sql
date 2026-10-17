-- Phase 432 (bos432) - RPT-B3 / R6a: QUALITY CHECK WITH ITEM, QUANTITY AND SUPPLIER (#89) and DAMAGED QUANTITY ON TRANSFER RECEIVE (#65).
-- Paste after phase431 (needs phase60 qc_records and phase10 stock_transfers). Paste-twice safe. Earlier phase files are not edited. No shared function is changed in behaviour:
--   * qc_record keeps its 7-argument signature (now a thin wrapper that passes nulls); the new 11-argument function carries the same rules plus the new fields.
--   * stock_receive_transfer keeps its 3-argument function untouched; the new 5-argument function validates the damage fields, calls the 3-argument one (every rule of today) and then records them.
--   * qc_list is re-created with two more optional filters and more columns (an old call with 4 arguments still works).
--
-- WHAT THIS ADDS
--   1. qc_records gains item_id, qty (base unit; the quantity this check is about: rejected / held for hold and reject, checked for pass) and supplier_id. All optional. Old rows keep null
--      and the screens say "not captured"; nothing is guessed back. The supplier and item are read from the source (purchase bill, paper GRN 04-1, production run) when not typed.
--   2. qc_list(loc, from, to, status, item, supplier): the latest check per source with the new columns and filters.
--   3. stock_transfers gains received_damaged_qty and damaged_reason (list transfer_damage_reasons: editable, Add new and Other like every list). Blank = not captured, never 0.
--      stock_receive_transfer(id, received, note, damaged, reason), transfer_damage_report(from, to, loc).
-- The damaged quantity is a RECORD. The goods stay in the receiving stock until they are written off with the wastage screen (reason Broken); nothing is written to stock or money here.
-- Paper form code of these two captures: to be given by owner (digital entry screens only for now).

do $g$ begin
  if to_regclass('public.qc_records') is null or to_regclass('public.stock_transfers') is null then raise exception 'phase432 needs phase10 and phase60 first'; end if;
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase432 needs phase430 first'; end if;
end $g$;

-- ---------- columns ----------
alter table public.qc_records add column if not exists item_id uuid references public.items(id);
alter table public.qc_records add column if not exists qty numeric;
alter table public.qc_records add column if not exists supplier_id uuid references public.suppliers(id);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'qc_records_qty_range' and conrelid = 'public.qc_records'::regclass) then
    alter table public.qc_records add constraint qc_records_qty_range check (qty is null or (qty > 0 and qty <= 1000000000000));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'qc_records_qty_needs_item' and conrelid = 'public.qc_records'::regclass) then
    alter table public.qc_records add constraint qc_records_qty_needs_item check (qty is null or item_id is not null);
  end if;
end $$;
create index if not exists qc_records_supplier on public.qc_records (supplier_id, created_at) where supplier_id is not null;
create index if not exists qc_records_item on public.qc_records (item_id, created_at) where item_id is not null;

alter table public.stock_transfers add column if not exists received_damaged_qty numeric;
alter table public.stock_transfers add column if not exists damaged_reason text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'stock_transfers_damaged_range' and conrelid = 'public.stock_transfers'::regclass) then
    alter table public.stock_transfers add constraint stock_transfers_damaged_range check (received_damaged_qty is null or (received_damaged_qty between 0 and 1000000000000));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'stock_transfers_damaged_le_received' and conrelid = 'public.stock_transfers'::regclass) then
    alter table public.stock_transfers add constraint stock_transfers_damaged_le_received check (received_damaged_qty is null or received_qty is null or received_damaged_qty <= received_qty);
  end if;
end $$;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('transfer_damage_reasons', 'broken', 'ভেঙে গেছে', 'ভেঙে গেছে (broken)', 'Broken', 1),
 ('transfer_damage_reasons', 'leaked', 'চুইয়ে / ছিটকে গেছে', 'Leaked / spilled', 'Leaked / spilled', 2),
 ('transfer_damage_reasons', 'crushed', 'চাপা পড়ে নষ্ট', 'Crushed', 'Crushed', 3),
 ('transfer_damage_reasons', 'spoiled', 'পথে নষ্ট / পচে গেছে', 'পথে spoiled', 'Spoiled on the way', 4),
 ('transfer_damage_reasons', 'packaging', 'প্যাকেট ছেঁড়া / খোলা', 'Packaging torn / open', 'Packaging torn / open', 5),
 ('transfer_damage_reasons', 'other', 'অন্যান্য', 'Other', 'Other', 9)
on conflict (list_code, value_code) do nothing;

-- ---------- where a quality-check source sits and who supplied it ----------
create or replace function public._rb3_qc_source(p_type text, p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare loc int; sup uuid; itm uuid; it_codes text[];
begin
  if p_type = 'production' then
    select location_id, item_id into loc, itm from public.production_runs where id = p_id;
    return case when loc is null then null else jsonb_build_object('location_id', loc, 'supplier_id', null, 'item_id', itm, 'item_ids', jsonb_build_array(itm)) end;
  end if;
  select location_id, supplier_id into loc, sup from public.purchase_bills where id = p_id and kind = 'bill' and status = 'posted';
  if found then
    return jsonb_build_object('location_id', loc, 'supplier_id', sup, 'item_ids', coalesce((select jsonb_agg(distinct l.item_id) from public.purchase_lines l where l.bill_id = p_id and l.item_id is not null), '[]'::jsonb));
  end if;
  select e.location_id,
         case when (e.data ->> 'supplier_id') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (e.data ->> 'supplier_id')::uuid end,
         coalesce((select array_agg(distinct x ->> 'item') from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) x), '{}')
    into loc, sup, it_codes from public.entries e where e.id = p_id and e.form_code = '04-1';
  if loc is null then return null; end if;
  if sup is not null and not exists (select 1 from public.suppliers where id = sup) then sup := null; end if;
  return jsonb_build_object('location_id', loc, 'supplier_id', sup, 'item_ids', coalesce((select jsonb_agg(i.id) from public.items i where i.code = any (it_codes)), '[]'::jsonb));
end $$;

-- ---------- qc_record: the full function (same rules as phase60 plus item, quantity, supplier) ----------
create or replace function public.qc_record(p_source_type text, p_source_id uuid, p_status text, p_checks jsonb, p_note text, p_photo text, p_client uuid,
  p_item uuid, p_qty numeric, p_unit text, p_supplier uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; sid text; prev public.qc_records; rid uuid; c jsonb; codes text[] := '{}'; code text; bad int := 0; n text := nullif(btrim(p_note), '');
        src jsonb; sup uuid := p_supplier; bq numeric; itm uuid := p_item;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.qc_records where client_id = p_client;
    if found then
      if prev.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', prev.id, 'status', prev.status);
    end if;
  end if;
  if p_source_type is null or p_source_type not in ('production', 'grn') then raise exception 'bad_source'; end if;
  if p_source_id is null then raise exception 'bad_source'; end if;
  if p_status is null or p_status not in ('pass', 'hold', 'reject') then raise exception 'bad_status'; end if;
  src := public._rb3_qc_source(p_source_type, p_source_id);
  if src is null then raise exception 'source_not_found'; end if;
  loc := (src ->> 'location_id')::int;
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('qc_record', loc)) then raise exception 'not allowed'; end if;
  if p_checks is null or jsonb_typeof(p_checks) <> 'array' or jsonb_array_length(p_checks) > 30 then raise exception 'bad_checks'; end if;
  for c in select * from jsonb_array_elements(p_checks) loop
    if jsonb_typeof(c) <> 'object' or jsonb_typeof(c->'ok') <> 'boolean' or jsonb_typeof(c->'code') <> 'string' then raise exception 'bad_checks'; end if;
    code := c->>'code';
    if code = any (codes) then raise exception 'bad_checks'; end if;
    if not exists (select 1 from public.option_lists where list_code = 'qc_checks' and value_code = code and active) then raise exception 'bad_check_code'; end if;
    codes := codes || code;
    if not (c->>'ok')::boolean then bad := bad + 1; end if;
  end loop;
  if p_status = 'pass' and bad > 0 then raise exception 'pass_has_failed_check'; end if;
  if p_status <> 'pass' and (n is null or length(n) < 3) then raise exception 'note_required'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  -- the new optional fields
  if itm is null and p_source_type = 'production' then itm := (src ->> 'item_id')::uuid; end if;
  if itm is not null then
    if not exists (select 1 from public.items where id = itm) then raise exception 'item_not_found'; end if;
    if p_item is not null and not (src -> 'item_ids') ? itm::text then raise exception 'item_not_in_source'; end if;
  end if;
  if sup is not null and not exists (select 1 from public.suppliers where id = sup) then raise exception 'supplier_not_found'; end if;
  if (src ->> 'supplier_id') is not null then
    if sup is not null and sup <> (src ->> 'supplier_id')::uuid then raise exception 'supplier_mismatch'; end if;
    sup := (src ->> 'supplier_id')::uuid;
  end if;
  if p_qty is not null then
    if itm is null then raise exception 'item_required_for_qty'; end if;
    bq := public._base_qty(itm, p_qty, p_unit);
    if bq is null then raise exception 'unit_unknown'; end if;
    if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  end if;
  select * into prev from public.qc_records where source_type = p_source_type and source_id = p_source_id order by created_at desc, id desc limit 1;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.qc_records (client_id, source_type, source_id, location_id, status, checks, note, photo, supersedes_id, created_by, created_staff, item_id, qty, supplier_id)
    values (p_client, p_source_type, p_source_id, loc, p_status, p_checks, n, nullif(btrim(p_photo), ''), prev.id, auth.uid(), sid, itm, bq, sup) returning id into rid;
  if p_status in ('hold', 'reject') then
    perform public._stock_exc(loc, 'qc_' || p_status, case when public.rule_on('quality_block_on') then 'red' else 'yellow' end,
      'কোয়ালিটি চেকে ' || case p_status when 'hold' then 'আটক' else 'বাতিল' end || ' (' || p_source_type || ')',
      'Quality check: ' || p_status || ' (' || p_source_type || ')', null, null, 'QC');
  end if;
  return jsonb_build_object('id', rid, 'status', p_status, 'failed', bad, 'blocked', public.rule_on('quality_block_on') and p_status in ('hold', 'reject'), 'item_id', itm, 'qty', bq, 'supplier_id', sup);
end $$;

-- the old 7-argument signature stays (screens, tests and the offline outbox call it): a thin wrapper, no default on the new arguments so no call is ambiguous
create or replace function public.qc_record(p_source_type text, p_source_id uuid, p_status text, p_checks jsonb default '[]'::jsonb,
  p_note text default null, p_photo text default null, p_client uuid default null) returns jsonb
language sql security definer set search_path = public as $$
  select public.qc_record(p_source_type, p_source_id, p_status, p_checks, p_note, p_photo, p_client, null::uuid, null::numeric, null::text, null::uuid);
$$;

-- ---------- qc_list with the new columns and filters ----------
drop function if exists public.qc_list(int, date, date, text);
create or replace function public.qc_list(p_loc int default null, p_from date default null, p_to date default null, p_status text default null, p_item uuid default null, p_supplier uuid default null)
returns table (id uuid, source_type text, source_id uuid, location_id int, status text, checks jsonb, note text, created_at timestamptz, created_staff text, history_n bigint,
               item_id uuid, item_code text, item_name_bn text, item_name_en text, base_unit text, qty numeric, supplier_id uuid, supplier_name text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_status is not null and p_status not in ('pass', 'hold', 'reject') then raise exception 'bad_status'; end if;
  if p_from is not null and p_to is not null and p_to < p_from then raise exception 'bad_range'; end if;
  return query
    select q.id, q.source_type, q.source_id, q.location_id, q.status, q.checks, q.note, q.created_at, q.created_staff,
           (select count(*) from public.qc_records h where h.source_type = q.source_type and h.source_id = q.source_id),
           q.item_id, i.code, i.name_bn, i.name_en, case when i.id is null then null else public._item_base(i.id) end, q.qty, q.supplier_id, s.name
    from public.qc_records q left join public.items i on i.id = q.item_id left join public.suppliers s on s.id = q.supplier_id
    where q.id = (select x.id from public.qc_records x where x.source_type = q.source_type and x.source_id = q.source_id order by x.created_at desc, x.id desc limit 1)
      and public.can_loc(q.location_id) and (p_loc is null or q.location_id = p_loc)
      and (p_status is null or q.status = p_status) and (p_item is null or q.item_id = p_item) and (p_supplier is null or q.supplier_id = p_supplier)
      and (p_from is null or (q.created_at at time zone 'Asia/Dhaka')::date >= p_from)
      and (p_to is null or (q.created_at at time zone 'Asia/Dhaka')::date <= p_to)
    order by q.created_at desc limit 200;
end $$;

-- ---------- damaged quantity on transfer receive ----------
create or replace function public.stock_receive_transfer(p_id uuid, p_received_qty numeric, p_note text, p_damaged_qty numeric, p_damaged_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.stock_transfers; rq numeric; res jsonb; dq numeric := p_damaged_qty; rs text := nullif(btrim(p_damaged_reason), ''); it public.items;
begin
  select * into t from public.stock_transfers where id = p_id;
  if not found then raise exception 'not found'; end if;
  rq := coalesce(p_received_qty, t.qty);
  if dq is not null then
    if not (dq between 0 and 999999999) then raise exception 'bad_qty'; end if;
    if dq > rq then raise exception 'damaged_over_received'; end if;
    if dq > 0 and (rs is null or not exists (select 1 from public.option_lists where list_code = 'transfer_damage_reasons' and value_code = rs and active)) then raise exception 'damage_reason_required'; end if;
    if dq = 0 then rs := null; end if;
  end if;
  res := public.stock_receive_transfer(p_id, p_received_qty, p_note);          -- the 3-argument function: every rule of today (grant, short quantity, batches, exception)
  if coalesce((res ->> 'dup')::boolean, false) then return res; end if;
  if dq is not null then
    update public.stock_transfers set received_damaged_qty = dq, damaged_reason = rs where id = p_id;
    if dq > 0 then
      select * into it from public.items where id = t.item_id;
      perform public._stock_exc(t.to_location_id, 'transit_damaged', 'yellow', it.name_bn || ': গ্রহণ ' || rq::text || ', তার মধ্যে ' || dq::text || ' ক্ষতিগ্রস্ত',
        coalesce(it.name_en, it.name_bn) || ': received ' || rq::text || ', of which ' || dq::text || ' damaged');
    end if;
  end if;
  return res || jsonb_build_object('damaged', dq);
end $$;

-- the damaged-on-receipt report (read only). Blank damaged = "not captured"; it is never added up as 0.
create or replace function public.transfer_damage_report(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date); rows_ jsonb; n int; cap int; ncap int; qd numeric; qs numeric;
begin
  if not (public.is_active() and (public.is_owner() or public.rpt_access('stock'))) then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('transfer_id', x.id, 'received_at', x.received_at, 'day', (x.received_at at time zone 'Asia/Dhaka')::date, 'from_location_id', x.from_location_id,
        'from_name', lf.name_bn, 'to_location_id', x.to_location_id, 'to_name', lt.name_bn, 'item_id', x.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'base_unit', public._item_base(x.item_id),
        'qty_sent', x.qty, 'received_qty', x.received_qty, 'short', x.qty - x.received_qty, 'damaged', x.received_damaged_qty, 'reason', x.damaged_reason,
        'reason_label', (select coalesce(o.label_en, o.value_code) from public.option_lists o where o.list_code = 'transfer_damage_reasons' and o.value_code = x.damaged_reason),
        'reason_label_bn', (select o.label_bn from public.option_lists o where o.list_code = 'transfer_damage_reasons' and o.value_code = x.damaged_reason),
        'batch_id', (select l.batch_id from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = x.id::text and l.reason = 'transfer_in' and l.batch_id is not null order by l.id limit 1))
        order by x.received_at desc, x.id), '[]'::jsonb),
    count(*), count(*) filter (where x.received_damaged_qty is null), sum(x.received_damaged_qty), sum(x.qty - x.received_qty)
    into rows_, n, ncap, qd, qs
    from public.stock_transfers x join public.items i on i.id = x.item_id join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id
   where x.status = 'received' and (x.received_at at time zone 'Asia/Dhaka')::date between f and t
     and (public.can_loc(x.to_location_id) or public.can_loc(x.from_location_id)) and (p_loc is null or x.to_location_id = p_loc or x.from_location_id = p_loc);
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'received_n', n, 'damaged_not_captured_n', ncap, 'damaged_total_captured', qd, 'short_total', qs);
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb3_qc_source') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qc_record', 'qc_list', 'transfer_damage_report')
           or (p.proname = 'stock_receive_transfer' and p.pronargs = 5) loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
