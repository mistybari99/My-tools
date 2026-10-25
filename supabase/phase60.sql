-- ============================================================
-- BOS tool · Phase 60 (P3 gaps #7-#10): reorder suggestion, wastage reasons report, batch/expiry on GRN, QC records.
-- ADDITIVE + paste-twice safe. stock_post / stock_wastage are NOT changed. Everything is tagged bos60.
--  #7 reorder_report()      read-only: stock on hand, min_stock, average daily usage over N days, owner-set lead days. No purchase order is made.
--  #8 wastage reasons       more reasons in option_lists 'wastage_reasons' (insert-if-missing); wastage_by_reason() report. Old rows untouched.
--  #9 grn_batch_add()       capture batch no + expiry for goods received (purchase bill or GRN 04-1) into the EXISTING stock_batches
--                           (+ batch_no column, append-only link table). near_expiry_report(), fefo_hint(). stock_post already picks FEFO.
--  #10 qc_record()          append-only quality check per production run or GRN: checklist from option list 'qc_checks', pass/hold/reject.
--                           Nothing is blocked unless the owner switches quality_block_on ON (default OFF).
-- ============================================================

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('reorder_lookback_days', 'stock', 'number', '30', 'days', null, 1, 365, 'রিঅর্ডার: কত দিনের গড় ব্যবহার দেখা হবে', 'Reorder: কত দিনের গড় usage', 'Reorder: days of usage to average', 'Average daily usage = sales + production issues over this many days', 600),
 ('reorder_lead_days', 'stock', 'number', '3', 'days', null, 0, 120, 'সাপ্লায়ার মাল দিতে কত দিন লাগে (লিড ডে)', 'Supplier lead days (মাল আসতে কত দিন)', 'Supplier lead days', 'Set by the owner. Used only for the suggestion; no order is placed', 601),
 ('reorder_cover_days', 'stock', 'number', '7', 'days', null, 0, 365, 'রিঅর্ডারে কত দিনের বাড়তি মাল চাই', 'Reorder এ কত দিনের extra cover', 'Extra days of cover to order', 'Suggested qty = average daily usage x (lead + cover days) - on hand', 602),
 ('expiry_warn_days', 'stock', 'number', '7', 'days', null, 0, 365, 'মেয়াদ শেষের কত দিন আগে সতর্কতা', 'মেয়াদ শেষের কত দিন আগে warning', 'Warn this many days before expiry', 'Used by the near-expiry report', 603),
 ('quality_block_on', 'stock', 'switch', 'false', null, null, null, null, 'কোয়ালিটি হোল্ড/রিজেক্ট হলে ব্যাচ আটকাও', 'Quality hold/reject হলে batch আটকাও', 'Block held / rejected batches', 'OFF = QC is only a record. ON = a held/rejected GRN cannot get new batches and its batches are marked blocked; a red line is raised', 604)
on conflict (key) do nothing;

with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('grn_batch', 'stock', 47, 'প্রাপ্ত মালের ব্যাচ নং ও মেয়াদ লেখা', 'Receive করা মালের batch no ও expiry লেখা', 'Record batch no and expiry of received goods', 'once', null),
   ('qc_record', 'stock', 48, 'কোয়ালিটি চেক লেখা', 'Quality check লেখা', 'Record a quality check', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('grn_batch', 'storekeeper'), ('grn_batch', 'purchasing'), ('grn_batch', 'factory_incharge'),
    ('qc_record', 'storekeeper'), ('qc_record', 'factory_incharge'), ('qc_record', 'management')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

insert into public.option_lists (list_code, value_code, label_bn, label_mix, label_en, sort) values
 ('wastage_reasons', 'qc_reject', 'কোয়ালিটিতে বাতিল', 'Quality তে reject', 'Rejected by quality check', 7),
 ('wastage_reasons', 'spillage', 'ছিটকে / পড়ে গেছে', 'ছিটকে / spillage', 'Spillage', 8),
 ('wastage_reasons', 'overproduction', 'বেশি বানানো হয়েছে', 'বেশি production', 'Over-production', 10),
 ('wastage_reasons', 'weight_loss', 'ওজন কমে গেছে', 'ওজন loss', 'Weight loss / shrinkage', 11),
 ('wastage_reasons', 'pest', 'পোকা / ইঁদুর', 'পোকা / pest', 'Pest damage', 12),
 ('wastage_reasons', 'power_cut', 'বিদ্যুৎ না থাকায় নষ্ট', 'Power cut এ নষ্ট', 'Lost to power cut', 13),
 ('qc_checks', 'appearance', 'দেখতে ঠিক', 'দেখতে ঠিক (appearance)', 'Appearance', 1),
 ('qc_checks', 'smell', 'গন্ধ ঠিক', 'গন্ধ ঠিক (smell)', 'Smell', 2),
 ('qc_checks', 'taste', 'স্বাদ ঠিক', 'স্বাদ ঠিক (taste)', 'Taste', 3),
 ('qc_checks', 'weight', 'ওজন ঠিক', 'ওজন ঠিক (weight)', 'Weight', 4),
 ('qc_checks', 'packaging', 'প্যাকেট ঠিক', 'প্যাকেট ঠিক (packaging)', 'Packaging intact', 5),
 ('qc_checks', 'label', 'লেবেল / মেয়াদ লেখা', 'Label / expiry printed', 'Label / expiry printed', 6),
 ('qc_checks', 'temperature', 'তাপমাত্রা ঠিক', 'তাপমাত্রা (temperature)', 'Temperature', 7),
 ('qc_checks', 'foreign', 'বাইরের কিছু নেই', 'কোনো foreign matter নেই', 'No foreign matter', 8)
on conflict (list_code, value_code) do nothing;

-- ---------- tables ----------
alter table public.stock_batches add column if not exists batch_no text;      -- bos60: the supplier's / our own batch number (null on older batches)

create table if not exists public.grn_batch_links (
  id bigserial primary key,
  batch_id bigint not null unique,                       -- (no FK on purpose: a truncate of the stock tables must still hit the ledger trigger first)
  source_type text not null check (source_type in ('purchase', 'grn')),
  source_id uuid not null,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  batch_no text not null check (length(batch_no) between 1 and 40),
  expiry_date date not null,
  qty_base numeric not null check (qty_base > 0 and qty_base <= 1000000000000),
  client_id uuid unique,
  created_by uuid, created_at timestamptz not null default now()
);
create unique index if not exists grn_batch_links_no on public.grn_batch_links (item_id, location_id, lower(batch_no));
create index if not exists grn_batch_links_src on public.grn_batch_links (source_type, source_id);

create table if not exists public.qc_records (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  source_type text not null check (source_type in ('production', 'grn')),
  source_id uuid not null,
  location_id int not null references public.locations(id),
  status text not null check (status in ('pass', 'hold', 'reject')),
  checks jsonb not null default '[]'::jsonb,
  note text check (note is null or length(note) <= 300),
  photo text check (photo is null or length(photo) <= 300),
  supersedes_id uuid references public.qc_records(id),
  created_by uuid, created_staff text, created_at timestamptz not null default now()
);
create index if not exists qc_records_src on public.qc_records (source_type, source_id, created_at desc);
create index if not exists qc_records_loc on public.qc_records (location_id, created_at);

create or replace function public._append_only60() returns trigger language plpgsql set search_path = public as $$
begin raise exception 'append_only: % is a record, it cannot be changed or deleted', tg_table_name; end $$;
drop trigger if exists qc_records_ro on public.qc_records;
create trigger qc_records_ro before update or delete on public.qc_records for each row execute function public._append_only60();
drop trigger if exists qc_records_ro_t on public.qc_records;
create trigger qc_records_ro_t before truncate on public.qc_records for each statement execute function public._append_only60();
drop trigger if exists grn_batch_links_ro on public.grn_batch_links;
create trigger grn_batch_links_ro before update or delete on public.grn_batch_links for each row execute function public._append_only60();
drop trigger if exists grn_batch_links_ro_t on public.grn_batch_links;
create trigger grn_batch_links_ro_t before truncate on public.grn_batch_links for each statement execute function public._append_only60();
drop trigger if exists audit_qc_records on public.qc_records;
create trigger audit_qc_records after insert on public.qc_records for each row execute function public.log_change('id');
drop trigger if exists audit_grn_batch_links on public.grn_batch_links;
create trigger audit_grn_batch_links after insert on public.grn_batch_links for each row execute function public.log_change('id');

alter table public.grn_batch_links enable row level security;
alter table public.qc_records enable row level security;
drop policy if exists grn_batch_links_read on public.grn_batch_links;
create policy grn_batch_links_read on public.grn_batch_links for select to authenticated using (public.can_loc(location_id));
drop policy if exists qc_records_read on public.qc_records;
create policy qc_records_read on public.qc_records for select to authenticated using (public.can_loc(location_id));
revoke all on public.grn_batch_links, public.qc_records from public, anon, authenticated;
grant select on public.grn_batch_links, public.qc_records to authenticated;
revoke all on sequence public.grn_batch_links_id_seq from public, anon, authenticated;

-- ---------- #10 helpers + QC ----------
-- latest QC status of one source (null = never checked)
create or replace function public._qc_latest60(p_type text, p_id uuid) returns text
language sql stable security definer set search_path = public as $$
  select status from public.qc_records where source_type = p_type and source_id = p_id order by created_at desc, id desc limit 1;
$$;

-- is this batch blocked by quality? Only when the owner switched quality_block_on ON.
create or replace function public._qc_batch_blocked60(p_batch bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select public.rule_on('quality_block_on') and (
    exists (select 1 from public.grn_batch_links l where l.batch_id = p_batch and public._qc_latest60('grn', l.source_id) in ('hold', 'reject'))
    or exists (select 1 from public.production_runs r where r.batch_id = p_batch and public._qc_latest60('production', r.id) in ('hold', 'reject')));
$$;

-- QC state of a source for any screen: {status, blocked, switch_on}
create or replace function public.qc_gate(p_source_type text, p_source_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  st := public._qc_latest60(p_source_type, p_source_id);
  return jsonb_build_object('status', st, 'switch_on', public.rule_on('quality_block_on'),
    'blocked', public.rule_on('quality_block_on') and st in ('hold', 'reject'));
end $$;

create or replace function public.qc_record(p_source_type text, p_source_id uuid, p_status text, p_checks jsonb default '[]'::jsonb,
  p_note text default null, p_photo text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; sid text; prev public.qc_records; rid uuid; c jsonb; codes text[] := '{}'; code text; bad int := 0; n text := nullif(btrim(p_note), '');
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
  if p_source_type = 'production' then
    select location_id into loc from public.production_runs where id = p_source_id;
  else
    select location_id into loc from public.entries where id = p_source_id and form_code = '04-1';
    if loc is null then select location_id into loc from public.purchase_bills where id = p_source_id and kind = 'bill' and status = 'posted'; end if;
  end if;
  if loc is null then raise exception 'source_not_found'; end if;
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
  select * into prev from public.qc_records where source_type = p_source_type and source_id = p_source_id order by created_at desc, id desc limit 1;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.qc_records (client_id, source_type, source_id, location_id, status, checks, note, photo, supersedes_id, created_by, created_staff)
    values (p_client, p_source_type, p_source_id, loc, p_status, p_checks, n, nullif(btrim(p_photo), ''), prev.id, auth.uid(), sid) returning id into rid;
  if p_status in ('hold', 'reject') then
    perform public._stock_exc(loc, 'qc_' || p_status, case when public.rule_on('quality_block_on') then 'red' else 'yellow' end,
      'কোয়ালিটি চেকে ' || case p_status when 'hold' then 'আটক' else 'বাতিল' end || ' (' || p_source_type || ')',
      'Quality check: ' || p_status || ' (' || p_source_type || ')', null, null, 'QC');
  end if;
  return jsonb_build_object('id', rid, 'status', p_status, 'failed', bad, 'blocked', public.rule_on('quality_block_on') and p_status in ('hold', 'reject'));
end $$;

-- latest QC per source (one line each), newest first
create or replace function public.qc_list(p_loc int default null, p_from date default null, p_to date default null, p_status text default null)
returns table (id uuid, source_type text, source_id uuid, location_id int, status text, checks jsonb, note text, created_at timestamptz, created_staff text, history_n bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if p_status is not null and p_status not in ('pass', 'hold', 'reject') then raise exception 'bad_status'; end if;
  return query
    select q.id, q.source_type, q.source_id, q.location_id, q.status, q.checks, q.note, q.created_at, q.created_staff,
           (select count(*) from public.qc_records h where h.source_type = q.source_type and h.source_id = q.source_id)
    from public.qc_records q
    where q.id = (select x.id from public.qc_records x where x.source_type = q.source_type and x.source_id = q.source_id order by x.created_at desc, x.id desc limit 1)
      and public.can_loc(q.location_id) and (p_loc is null or q.location_id = p_loc)
      and (p_status is null or q.status = p_status)
      and (p_from is null or (q.created_at at time zone 'Asia/Dhaka')::date >= p_from)
      and (p_to is null or (q.created_at at time zone 'Asia/Dhaka')::date <= p_to)
    order by q.created_at desc limit 200;
end $$;

-- full trail of one source
create or replace function public.qc_history(p_source_type text, p_source_id uuid)
returns table (id uuid, status text, checks jsonb, note text, photo text, supersedes_id uuid, created_at timestamptz, created_staff text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query select q.id, q.status, q.checks, q.note, q.photo, q.supersedes_id, q.created_at, q.created_staff
    from public.qc_records q where q.source_type = p_source_type and q.source_id = p_source_id and public.can_loc(q.location_id)
    order by q.created_at, q.id;
end $$;

-- ---------- #9 batch + expiry on received goods ----------
create or replace function public.grn_batch_add(p_source_type text, p_source_id uuid, p_item uuid, p_qty numeric, p_unit text,
  p_batch_no text, p_expiry date, p_made date default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare loc int; it public.items; bq numeric; bn text := btrim(p_batch_no); today date := (now() at time zone 'Asia/Dhaka')::date; bid bigint; lk public.grn_batch_links;
        recv numeric; used numeric; free numeric; code text;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into lk from public.grn_batch_links where client_id = p_client;
    if found then
      if lk.created_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'batch_id', lk.batch_id);
    end if;
  end if;
  if p_source_type is null or p_source_type not in ('purchase', 'grn') or p_source_id is null then raise exception 'bad_source'; end if;
  if p_source_type = 'purchase' then
    select location_id into loc from public.purchase_bills where id = p_source_id and kind = 'bill' and status = 'posted';
  else
    select location_id into loc from public.entries where id = p_source_id and form_code = '04-1' and status in ('submitted', 'approved');
  end if;
  if loc is null then raise exception 'source_not_found'; end if;
  if not public.can_loc(loc) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('grn_batch', loc)) then raise exception 'not allowed'; end if;
  it := public._stock_guard(p_item, loc, 'grn_batch', today);
  if bn is null or length(bn) not between 1 and 40 then raise exception 'bad_batch_no'; end if;
  if p_expiry is null or p_expiry < today or p_expiry > today + 3650 then raise exception 'bad_expiry'; end if;
  if p_made is not null and (p_made > today or p_made < today - 3650) then raise exception 'bad_made_date'; end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  if not (bq between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if public.rule_on('quality_block_on') and public._qc_latest60('grn', p_source_id) in ('hold', 'reject') then raise exception 'qc_blocked'; end if;
  if exists (select 1 from public.grn_batch_links where item_id = p_item and location_id = loc and lower(batch_no) = lower(bn)) then raise exception 'batch_no_exists'; end if;
  -- the stock row is locked: nobody else changes this item's balance or batches meanwhile
  insert into public.stock_balance (item_id, location_id) values (p_item, loc) on conflict do nothing;
  perform 1 from public.stock_balance where item_id = p_item and location_id = loc for update;
  if p_source_type = 'purchase' then
    select coalesce(sum(base_qty), 0) into recv from public.purchase_lines where bill_id = p_source_id and item_id = p_item;
    if recv <= 0 then raise exception 'item_not_in_source'; end if;
    select coalesce(sum(qty_base), 0) into used from public.grn_batch_links where source_type = 'purchase' and source_id = p_source_id and item_id = p_item;
    if used + bq > recv + 0.0005 then raise exception 'more_than_received'; end if;
  else
    if not exists (select 1 from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) l
                    where e.id = p_source_id and l->>'item' = it.code) then raise exception 'item_not_in_source'; end if;
  end if;
  -- batches can only describe stock that is really on hand and not yet in another batch
  select b.qty - coalesce((select sum(qty_remaining) from public.stock_batches where item_id = p_item and location_id = loc and qty_remaining > 0), 0) into free
    from public.stock_balance b where b.item_id = p_item and b.location_id = loc;
  if free + 0.0005 < bq then raise exception 'more_than_on_hand'; end if;
  insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by, batch_no)
    values (p_item, loc, coalesce(p_made, today)::timestamp at time zone 'Asia/Dhaka', bq, bq,
            (p_expiry::timestamp + interval '23 hours 59 minutes') at time zone 'Asia/Dhaka',
            jsonb_build_object('source', 'grn_batch_add', 'source_type', p_source_type, 'source_id', p_source_id), 'GRN batch ' || bn, auth.uid(), bn)
    returning id into bid;
  insert into public.grn_batch_links (batch_id, source_type, source_id, item_id, location_id, batch_no, expiry_date, qty_base, client_id, created_by)
    values (bid, p_source_type, p_source_id, p_item, loc, bn, p_expiry, bq, p_client, auth.uid());
  return jsonb_build_object('batch_id', bid, 'batch_no', bn, 'expiry', p_expiry, 'qty_base', bq);
end $$;

-- near-expiry report (reuses expiry_list): batches expiring within p_days days, expired ones included
create or replace function public.near_expiry_report(p_loc int default null, p_days numeric default null)
returns table (batch_id bigint, batch_no text, item_id uuid, code text, name_bn text, name_en text, location_id int, expires_at timestamptz, qty_remaining numeric, days_left numeric, expired boolean, qc_blocked boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare d numeric := coalesce(p_days, public.rule_num('expiry_warn_days'), 7);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if not (d between 0 and 3650) then d := 7; end if;
  return query
    select e.batch_id, b.batch_no, e.item_id, e.code, e.name_bn, e.name_en, e.location_id, e.expires_at, e.qty_remaining,
           round(e.hours_left / 24, 2), e.expired, public._qc_batch_blocked60(e.batch_id)
    from public.expiry_list(p_loc, d * 24) e join public.stock_batches b on b.id = e.batch_id
    order by e.expires_at, e.batch_id;
end $$;

-- FEFO hint: the order stock_post will take batches in (not-expired first, soonest expiry first, expired last)
create or replace function public.fefo_hint(p_item uuid, p_loc int)
returns table (rank int, batch_id bigint, batch_no text, expires_at timestamptz, qty_remaining numeric, expired boolean, qc_blocked boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  return query
    select (row_number() over (order by (b.expires_at is not null and b.expires_at <= now()), b.expires_at nulls last, b.made_at, b.id))::int,
           b.id, b.batch_no, b.expires_at, b.qty_remaining, (b.expires_at is not null and b.expires_at <= now()), public._qc_batch_blocked60(b.id)
    from public.stock_batches b where b.item_id = p_item and b.location_id = p_loc and b.qty_remaining > 0
    order by 1;
end $$;

-- ---------- #8 wastage by reason ----------
create or replace function public.wastage_by_reason(p_loc int default null, p_from date default null, p_to date default null)
returns table (reason_code text, label_bn text, label_mix text, label_en text, entries bigint, items bigint, qty numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare f date := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30); t date := coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  return query
    select w.reason_code, coalesce(o.label_bn, w.reason_code), coalesce(o.label_mix, o.label_bn, w.reason_code), coalesce(o.label_en, w.reason_code),
           count(*), count(distinct w.item_id), round(sum(w.qty), 4)
    from public.stock_wastage w left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code
    where public.can_loc(w.location_id) and (p_loc is null or w.location_id = p_loc)
      and (w.made_at at time zone 'Asia/Dhaka')::date between f and t
    group by w.reason_code, o.label_bn, o.label_mix, o.label_en
    order by sum(w.qty) desc, w.reason_code;
end $$;

-- ---------- #7 reorder suggestion (read-only) ----------
create or replace function public.reorder_report(p_loc int default null, p_days int default null)
returns table (item_id uuid, code text, name_bn text, name_en text, location_id int, base_unit text, on_hand numeric, min_stock numeric,
               avg_daily numeric, days_left numeric, lead_days numeric, suggest_qty numeric, why text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare d int := coalesce(p_days, public.rule_num('reorder_lookback_days')::int, 30); lead numeric := coalesce(public.rule_num('reorder_lead_days'), 3);
        cover numeric := coalesce(public.rule_num('reorder_cover_days'), 7);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  if d is null or d not between 1 and 365 then raise exception 'bad_days'; end if;
  return query
    with u as (
      select l.item_id, l.location_id,
             sum(case when l.reason in ('sale_out', 'issue_out') then -l.qty_delta when l.reason in ('sale_void_in', 'sale_return') then -l.qty_delta else 0 end) as used
      from public.stock_ledger l
      where l.made_at >= now() - (d * interval '1 day') and l.reason in ('sale_out', 'issue_out', 'sale_void_in', 'sale_return')
      group by l.item_id, l.location_id),
    r as (
      select i.id as item_id, i.code, i.name_bn, i.name_en, b.location_id, public._item_base(i.id) as base_unit, b.qty as on_hand, i.min_stock,
             round(greatest(coalesce(u.used, 0), 0) / d, 4) as avg_daily
      from public.stock_balance b join public.items i on i.id = b.item_id and i.tracked and i.is_active
      left join u on u.item_id = b.item_id and u.location_id = b.location_id
      where public.can_loc(b.location_id) and (p_loc is null or b.location_id = p_loc))
    select r.item_id, r.code, r.name_bn, r.name_en, r.location_id, r.base_unit, r.on_hand, r.min_stock, r.avg_daily,
           case when r.avg_daily > 0 then round(r.on_hand / r.avg_daily, 1) end, lead,
           round(greatest(greatest(r.avg_daily * (lead + cover), coalesce(r.min_stock, 0)) - r.on_hand, 0), 4),
           case when r.min_stock is not null and r.on_hand < r.min_stock then 'below_min'
                when r.avg_daily > 0 and r.on_hand <= r.avg_daily * lead then 'runs_out_in_lead'
                else 'cover' end
    from r
    where greatest(greatest(r.avg_daily * (lead + cover), coalesce(r.min_stock, 0)) - r.on_hand, 0) > 0
      and (r.avg_daily > 0 or (r.min_stock is not null and r.on_hand < r.min_stock))
    order by (case when r.min_stock is not null and r.on_hand < r.min_stock then 0 when r.avg_daily > 0 and r.on_hand <= r.avg_daily * lead then 1 else 2 end), r.code, r.location_id;
end $$;

-- ---------- grants ----------
revoke all on function public._qc_latest60(text, uuid), public._qc_batch_blocked60(bigint), public._append_only60() from public, anon, authenticated;
revoke all on function public.qc_gate(text, uuid), public.qc_record(text, uuid, text, jsonb, text, text, uuid), public.qc_list(int, date, date, text), public.qc_history(text, uuid),
  public.grn_batch_add(text, uuid, uuid, numeric, text, text, date, date, uuid), public.near_expiry_report(int, numeric), public.fefo_hint(uuid, int),
  public.wastage_by_reason(int, date, date), public.reorder_report(int, int) from public, anon;
grant execute on function public.qc_gate(text, uuid), public.qc_record(text, uuid, text, jsonb, text, text, uuid), public.qc_list(int, date, date, text), public.qc_history(text, uuid),
  public.grn_batch_add(text, uuid, uuid, numeric, text, text, date, date, uuid), public.near_expiry_report(int, numeric), public.fefo_hint(uuid, int),
  public.wastage_by_reason(int, date, date), public.reorder_report(int, int) to authenticated;

notify pgrst, 'reload schema';
