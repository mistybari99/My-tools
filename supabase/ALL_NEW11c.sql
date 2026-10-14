-- ===== phase60 =====
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

-- ===== phase61 =====
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

-- ===== phase62 =====
-- ============================================================
-- Phase 62 (bos62) - P3 gaps #21 SMS/WhatsApp queue, #22 payment-gateway intents + webhook log + reconciliation,
--                    #23 accounting CSV export, #30 AI Assistant access (owner by default, others only with grant assistant_use).
-- Additive + paste-twice safe. No provider credentials anywhere: sending SMS/WhatsApp is done by tools/notify_sms.py (env secrets, default OFF);
-- the payment gateway is called ONLY by a (not yet deployed) Edge function whose contract is in docs/INTEGRATIONS_P3C.md. Nothing here calls a provider.
-- Runs after phase51 (uses phase40 accounts, phase46 ops bot (_is_ops 'notify'), phase47 assistant).
--   #21  tables: notify_templates, notify_optin, notify_outbox (queue: status, attempts, next_try_at) ; rule notify_sms_on (OFF)
--        browser: notify_template_save, notify_optin_set, notify_enqueue, notify_cancel, notify_outbox_summary
--        worker (ops bot purpose 'notify' or owner): notify_outbox_claim, notify_outbox_report
--   #22  tables: payment_intents, payment_webhook_log (append-only, unique (provider, event_id)) ; view payment_recon_v (not browser-readable) ;
--        rule pay_gateway_on (OFF) ; fns payment_intent_create, payment_intent_set_ref, payment_intent_link, payment_webhook_receive, payment_recon
--   #23  acct_export_csv(kind, from, to, loc) read-only; owner or accounts_manage (columns documented in docs/INTEGRATIONS_P3C.md)
--   #30  _assistant_ok() tightened (owner or explicit assistant_use only); grant_defs row (idempotent); assistant_access_list() owner-only
-- ============================================================

-- ---------- rules (default OFF) ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_bn, hint_en, sort) values
 ('notify_sms_on', 'integrations', 'switch', 'false', null, null, null, null, 'SMS / WhatsApp কিউ চালু', 'SMS / WhatsApp queue চালু', 'SMS / WhatsApp queue is on',
  'বন্ধ থাকলে কিছু কিউতে ঢোকে না ও কিছু পাঠানো হয় না। পাঠায় tools/notify_sms.py (গোপন চাবি শুধু GitHub secret-এ)।', 'Off = nothing is queued or sent. Sending is done by tools/notify_sms.py (secrets live only in GitHub secrets).', 620),
 ('notify_sms_max_tries', 'integrations', 'number', '5', 'times', null, 1, 20, 'একটি বার্তা সর্বোচ্চ কতবার চেষ্টা', 'একটি message সর্বোচ্চ কতবার try', 'Most send attempts per message', null, null, 621),
 ('pay_gateway_on', 'integrations', 'switch', 'false', null, null, null, null, 'পেমেন্ট গেটওয়ে রেকর্ড চালু', 'Payment gateway record চালু', 'Payment-gateway records are on',
  'শুধু রেকর্ড ও মিলানো; অ্যাপ কোনো গেটওয়ে কল করে না। চালু করার আগে Edge function লাগবে।', 'Records and reconciliation only; the app never calls a gateway. An Edge function is needed first.', 622)
on conflict (key) do nothing;

-- ---------- grants (idempotent) ----------
insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule)
select 'assistant_use', 'reports', 90, 'ব্যবসার সহকারী ব্যবহার', 'Business assistant ব্যবহার', 'Use the business assistant', 'once', null
where not exists (select 1 from public.grant_defs where grant_code = 'assistant_use');

-- ---------- small helpers (closed to browsers) ----------
create or replace function public._i62_ok() returns boolean   -- owner or customer manager: SMS queue / opt-in / templates
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('customer_manage')
    or exists (select 1 from public.locations l where public.has_grant('customer_manage', l.id)));
$$;
create or replace function public._i62_ops() returns boolean   -- the ops bot (purpose notify) or the owner
language sql stable security definer set search_path = public as $$
  select public.is_active() and public.is_owner() or public._is_ops('notify');
$$;
create or replace function public._i62_pay_ok() returns boolean   -- owner or accounts manager
language sql stable security definer set search_path = public as $$ select public._acct_manage(); $$;
create or replace function public._i62_ro() returns trigger language plpgsql set search_path = public as $$
begin raise exception '% is append-only', tg_table_name; end $$;
create or replace function public._i62_phone(p text) returns text language plpgsql immutable set search_path = public as $$
declare d text := regexp_replace(coalesce(p, ''), '[\s\-\(\)]', '', 'g');
begin
  if d ~ '^01[0-9]{9}$' then return '+880' || substr(d, 2); end if;
  if d ~ '^8801[0-9]{9}$' then return '+' || d; end if;
  if d ~ '^\+[1-9][0-9]{7,14}$' then return d; end if;
  return null;
end $$;
create or replace function public._i62_csv(p text) returns text language sql immutable set search_path = public as $$
  -- RFC 4180 quoting + spreadsheet formula guard (a cell never starts with = + - @ tab CR)
  select case when p is null then ''
    else (select case when v ~ '[",\r\n]' then '"' || replace(v, '"', '""') || '"' else v end
            from (select case when p ~ '^[=+\-@\t\r]' then '''' || p else p end v) s) end;
$$;

-- ============================================================
-- #21  SMS / WhatsApp queue
-- ============================================================
create table if not exists public.notify_templates (
  code text primary key check (code ~ '^[a-z0-9_]{2,40}$'),
  channel text not null default 'sms' check (channel in ('sms', 'whatsapp')),
  body_bn text not null check (length(body_bn) between 1 and 480),
  body_en text not null check (length(body_en) between 1 and 480),
  active boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now()
);
create table if not exists public.notify_optin (
  id bigserial primary key,
  customer_id uuid not null references public.customers(id),
  channel text not null check (channel in ('sms', 'whatsapp')),
  status text not null check (status in ('in', 'out')),
  source text not null default 'owner_entry' check (source in ('customer_consent', 'owner_entry')),
  note text check (note is null or length(note) <= 200),
  changed_by uuid, changed_at timestamptz not null default now(),
  unique (customer_id, channel)
);
create table if not exists public.notify_optin_log (          -- append-only history of every opt-in / opt-out
  id bigserial primary key, customer_id uuid not null, channel text not null, status text not null, source text, note text,
  changed_by uuid, changed_at timestamptz not null default now()
);
create table if not exists public.notify_outbox (
  id bigserial primary key,
  client_id uuid unique,
  customer_id uuid references public.customers(id),
  channel text not null check (channel in ('sms', 'whatsapp')),
  to_phone text not null check (to_phone ~ '^\+[1-9][0-9]{7,14}$'),
  template_code text not null references public.notify_templates(code),
  body text not null check (length(body) between 1 and 480),
  status text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed', 'cancelled')),
  attempts int not null default 0 check (attempts >= 0),
  max_attempts int not null default 5 check (max_attempts between 1 and 20),
  next_try_at timestamptz not null default now(),
  last_error text check (last_error is null or length(last_error) <= 300),
  provider_ref text check (provider_ref is null or length(provider_ref) <= 100),
  source_type text, source_id text,
  created_by uuid, created_at timestamptz not null default now(),
  claimed_at timestamptz, sent_at timestamptz
);
create unique index if not exists notify_outbox_src_uq on public.notify_outbox (source_type, source_id, template_code) where source_type is not null and source_id is not null;
create index if not exists notify_outbox_due on public.notify_outbox (status, next_try_at);

do $$ declare t text; begin
  foreach t in array array['notify_templates', 'notify_optin', 'notify_optin_log', 'notify_outbox'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_ok())', t || '_read', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists notify_optin_log_ro on public.notify_optin_log;
create trigger notify_optin_log_ro before update or delete on public.notify_optin_log for each row execute function public._i62_ro();
drop trigger if exists audit_notify_outbox on public.notify_outbox;
create trigger audit_notify_outbox after insert or update on public.notify_outbox for each row execute function public.log_change('id');
drop trigger if exists audit_notify_templates on public.notify_templates;
create trigger audit_notify_templates after insert or update on public.notify_templates for each row execute function public.log_change('code');
revoke usage, select on sequence public.notify_optin_id_seq, public.notify_optin_log_id_seq, public.notify_outbox_id_seq from public, anon, authenticated;

insert into public.notify_templates (code, channel, body_bn, body_en) values
 ('due_reminder', 'sms', 'প্রিয় {name}, আপনার বাকি {amount} টাকা। ধন্যবাদ। - {shop}', 'Dear {name}, your balance due is {amount} Taka. Thank you. - {shop}'),
 ('order_ready', 'sms', '{name}, আপনার অর্ডার {ref} প্রস্তুত। - {shop}', '{name}, your order {ref} is ready. - {shop}'),
 ('thanks', 'sms', '{name}, কেনাকাটার জন্য ধন্যবাদ। - {shop}', '{name}, thank you for shopping with us. - {shop}')
on conflict (code) do nothing;

create or replace function public.notify_template_save(p_code text, p_channel text, p_body_bn text, p_body_en text, p_active boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_code is null or p_code !~ '^[a-z0-9_]{2,40}$' or p_channel not in ('sms', 'whatsapp') or p_active is null
     or coalesce(length(btrim(p_body_bn)), 0) not between 1 and 480 or coalesce(length(btrim(p_body_en)), 0) not between 1 and 480 then raise exception 'bad_input'; end if;
  insert into public.notify_templates (code, channel, body_bn, body_en, active, updated_by) values (p_code, p_channel, btrim(p_body_bn), btrim(p_body_en), p_active, auth.uid())
    on conflict (code) do update set channel = excluded.channel, body_bn = excluded.body_bn, body_en = excluded.body_en, active = excluded.active, updated_by = auth.uid(), updated_at = now();
  return jsonb_build_object('code', p_code, 'active', p_active);
end $$;

create or replace function public.notify_optin_set(p_customer uuid, p_channel text, p_in boolean, p_source text default 'owner_entry', p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare st text := case when p_in then 'in' else 'out' end;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if p_customer is null or p_in is null or p_channel not in ('sms', 'whatsapp') or coalesce(p_source, 'owner_entry') not in ('customer_consent', 'owner_entry')
     or (p_note is not null and length(p_note) > 200) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.customers where id = p_customer) then raise exception 'customer_not_found'; end if;
  if p_in and public._i62_phone((select mobile from public.customers where id = p_customer)) is null then raise exception 'bad_phone'; end if;
  insert into public.notify_optin (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid())
    on conflict (customer_id, channel) do update set status = excluded.status, source = excluded.source, note = excluded.note, changed_by = auth.uid(), changed_at = now();
  insert into public.notify_optin_log (customer_id, channel, status, source, note, changed_by) values (p_customer, p_channel, st, coalesce(p_source, 'owner_entry'), p_note, auth.uid());
  if not p_in then   -- opting out cancels what is still waiting
    update public.notify_outbox set status = 'cancelled', last_error = 'opted_out' where customer_id = p_customer and channel = p_channel and status = 'queued';
  end if;
  return jsonb_build_object('customer_id', p_customer, 'channel', p_channel, 'status', st);
end $$;

create or replace function public.notify_enqueue(p_client uuid, p_customer uuid, p_channel text, p_template text, p_vars jsonb default '{}'::jsonb, p_lang text default 'bn',
                                                 p_source_type text default null, p_source_id text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t public.notify_templates; c public.customers; ph text; b text; k text; v text; ex public.notify_outbox; nid bigint; mt int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_sms_on') then raise exception 'sms_off'; end if;
  if p_client is null or p_customer is null or p_channel not in ('sms', 'whatsapp') or p_template is null or coalesce(p_lang, 'bn') not in ('bn', 'en')
     or (p_vars is not null and jsonb_typeof(p_vars) <> 'object') or (p_source_type is null) <> (p_source_id is null)
     or (p_source_type is not null and (length(p_source_type) > 40 or length(p_source_id) > 80)) then raise exception 'bad_input'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.notify_outbox where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true); end if;
  select * into t from public.notify_templates where code = p_template and active;
  if not found then raise exception 'template_not_found'; end if;
  if t.channel <> p_channel then raise exception 'template_channel_mismatch'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  if not exists (select 1 from public.notify_optin o where o.customer_id = p_customer and o.channel = p_channel and o.status = 'in') then raise exception 'not_opted_in'; end if;
  ph := public._i62_phone(c.mobile);
  if ph is null then raise exception 'bad_phone'; end if;
  b := case when coalesce(p_lang, 'bn') = 'en' then t.body_en else t.body_bn end;
  b := replace(b, '{name}', coalesce(left(c.name, 60), ''));
  for k, v in select key, left(value, 100) from jsonb_each_text(coalesce(p_vars, '{}'::jsonb)) loop
    if k ~ '^[a-z_]{1,20}$' then b := replace(b, '{' || k || '}', v); end if;
  end loop;
  b := regexp_replace(b, '\{[a-z_]{1,20}\}', '', 'g');
  if length(btrim(b)) not between 1 and 480 then raise exception 'bad_body'; end if;
  mt := greatest(least(coalesce(public.rule_num('notify_sms_max_tries'), 5)::int, 20), 1);
  begin
    insert into public.notify_outbox (client_id, customer_id, channel, to_phone, template_code, body, max_attempts, source_type, source_id, created_by)
      values (p_client, p_customer, p_channel, ph, p_template, btrim(b), mt, p_source_type, p_source_id, auth.uid()) returning id into nid;
  exception when unique_violation then
    select * into ex from public.notify_outbox where source_type = p_source_type and source_id = p_source_id and template_code = p_template;
    return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true);
  end;
  return jsonb_build_object('id', nid, 'status', 'queued', 'duplicate', false);
end $$;

create or replace function public.notify_cancel(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  update public.notify_outbox set status = 'cancelled', last_error = 'cancelled_by_staff' where id = p_id and status in ('queued', 'failed');
  get diagnostics n = row_count;
  if n = 0 then raise exception 'not_cancellable'; end if;
  return jsonb_build_object('id', p_id, 'status', 'cancelled');
end $$;

create or replace function public.notify_outbox_summary() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._i62_ok() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('notify_sms_on'),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.notify_outbox group by status) s), '{}'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'status', status, 'attempts', attempts, 'max_attempts', max_attempts, 'template', template_code,
        'to', left(to_phone, 6) || '****' || right(to_phone, 2), 'last_error', last_error, 'created_at', created_at, 'sent_at', sent_at) order by id desc)
        from (select * from public.notify_outbox order by id desc limit 50) r), '[]'::jsonb));
end $$;

-- worker side (tools/notify_sms.py): claim due rows, then report each result. A stale 'sending' (> 15 min) is claimable again.
create or replace function public.notify_outbox_claim(p_limit int default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 20), 1), 100); res jsonb;
begin
  if not public._i62_ops() then raise exception 'not allowed'; end if;
  if not public.rule_on('notify_sms_on') then return jsonb_build_object('on', false, 'rows', '[]'::jsonb); end if;
  with c as (
    select id from public.notify_outbox
     where ((status = 'queued' and next_try_at <= now()) or (status = 'sending' and claimed_at < now() - interval '15 minutes')) and attempts < max_attempts
     order by id limit lim for update skip locked),
  u as (update public.notify_outbox o set status = 'sending', attempts = o.attempts + 1, claimed_at = now() from c where o.id = c.id
        returning o.id, o.channel, o.to_phone, o.body, o.attempts)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'channel', channel, 'to', to_phone, 'body', body, 'attempt', attempts) order by id), '[]'::jsonb) into res from u;
  return jsonb_build_object('on', true, 'rows', res);
end $$;

create or replace function public.notify_outbox_report(p_id bigint, p_ok boolean, p_provider_ref text default null, p_error text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.notify_outbox;
begin
  if not public._i62_ops() then raise exception 'not allowed'; end if;
  if p_id is null or p_ok is null then raise exception 'bad_input'; end if;
  select * into r from public.notify_outbox where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'sending' then return jsonb_build_object('id', p_id, 'status', r.status, 'ignored', true); end if;
  if p_ok then
    update public.notify_outbox set status = 'sent', sent_at = now(), provider_ref = left(p_provider_ref, 100), last_error = null where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'sent');
  end if;
  if r.attempts >= r.max_attempts then
    update public.notify_outbox set status = 'failed', last_error = left(coalesce(p_error, 'error'), 300) where id = p_id;
    return jsonb_build_object('id', p_id, 'status', 'failed');
  end if;
  update public.notify_outbox set status = 'queued', last_error = left(coalesce(p_error, 'error'), 300),
      next_try_at = now() + (interval '1 minute' * power(2, r.attempts)::int) where id = p_id;   -- back-off 2, 4, 8, 16 ... minutes
  return jsonb_build_object('id', p_id, 'status', 'queued', 'retry', true);
end $$;

-- ============================================================
-- #22  payment gateway: intents + webhook receipt log + reconciliation (no live call anywhere)
-- ============================================================
create table if not exists public.payment_intents (
  id bigserial primary key,
  client_id uuid unique,
  provider text not null check (provider ~ '^[a-z0-9_]{2,24}$'),
  provider_ref text check (provider_ref is null or length(provider_ref) between 3 and 100),
  sale_id uuid references public.sales(id),
  customer_id uuid references public.customers(id),
  location_id int not null references public.locations(id),
  amount numeric not null check (amount > 0 and amount <= 1000000000000),
  currency text not null default 'BDT' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'created' check (status in ('created', 'pending', 'succeeded', 'failed', 'cancelled', 'refunded')),
  paid_amount numeric check (paid_amount is null or (paid_amount >= 0 and paid_amount <= 1000000000000)),
  sale_payment_id bigint references public.sale_payments(id),   -- manual link; otherwise matched by ref
  created_by uuid, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists payment_intents_ref_uq on public.payment_intents (provider, provider_ref) where provider_ref is not null;
create table if not exists public.payment_webhook_log (
  id bigserial primary key,
  provider text not null check (provider ~ '^[a-z0-9_]{2,24}$'),
  event_id text not null check (length(event_id) between 1 and 120),
  provider_ref text, event_type text check (event_type is null or length(event_type) <= 60),
  status text, amount numeric, signature_ok boolean not null,
  payload jsonb not null default '{}'::jsonb,
  applied boolean not null default false, note text,
  received_at timestamptz not null default now(),
  unique (provider, event_id)
);
do $$ declare t text; begin
  foreach t in array array['payment_intents', 'payment_webhook_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (public._i62_pay_ok())', t || '_read', t);
    execute format('drop trigger if exists %I on public.%I', t || '_nodel', t);
    execute format('create trigger %I before delete on public.%I for each row execute function public.no_hard_delete()', t || '_nodel', t);
  end loop;
end $$;
drop trigger if exists payment_webhook_log_ro on public.payment_webhook_log;
create trigger payment_webhook_log_ro before update or delete on public.payment_webhook_log for each row execute function public._i62_ro();
drop trigger if exists audit_payment_intents on public.payment_intents;
create trigger audit_payment_intents after insert or update on public.payment_intents for each row execute function public.log_change('id');
revoke usage, select on sequence public.payment_intents_id_seq, public.payment_webhook_log_id_seq from public, anon, authenticated;


create or replace function public.payment_intent_create(p_client uuid, p_provider text, p_sale uuid, p_customer uuid, p_loc int, p_amount numeric,
                                                        p_provider_ref text default null, p_currency text default 'BDT') returns jsonb
language plpgsql security definer set search_path = public as $$
declare ex public.payment_intents; nid bigint;
begin
  if not (public._i62_pay_ok() or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_gateway_on') then raise exception 'gateway_off'; end if;
  if p_client is null or p_provider is null or p_provider !~ '^[a-z0-9_]{2,24}$' or p_loc is null or p_amount is null or p_amount <= 0 or p_amount > 1000000000000
     or p_amount <> round(p_amount, 2) or coalesce(p_currency, 'BDT') !~ '^[A-Z]{3}$' or (p_provider_ref is not null and length(p_provider_ref) not between 3 and 100) then raise exception 'bad_input'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if not (public._acct_all() or public.can_loc(p_loc) or public._is_ops('notify')) then raise exception 'not allowed for this location'; end if;
  perform public._client_lock(p_client);
  select * into ex from public.payment_intents where client_id = p_client;
  if found then return jsonb_build_object('id', ex.id, 'status', ex.status, 'duplicate', true); end if;
  insert into public.payment_intents (client_id, provider, provider_ref, sale_id, customer_id, location_id, amount, currency, created_by)
    values (p_client, p_provider, p_provider_ref, p_sale, p_customer, p_loc, round(p_amount, 2), coalesce(p_currency, 'BDT'), auth.uid()) returning id into nid;
  return jsonb_build_object('id', nid, 'status', 'created', 'duplicate', false);
end $$;

create or replace function public.payment_intent_set_ref(p_id bigint, p_provider_ref text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.payment_intents;
begin
  if not (public._i62_pay_ok() or public._is_ops('notify')) then raise exception 'not allowed'; end if;
  if p_provider_ref is null or length(p_provider_ref) not between 3 and 100 then raise exception 'bad_input'; end if;
  select * into r from public.payment_intents where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if r.provider_ref is not null and r.provider_ref <> p_provider_ref then raise exception 'ref_already_set'; end if;
  update public.payment_intents set provider_ref = p_provider_ref, status = case when status = 'created' then 'pending' else status end, updated_at = now() where id = p_id;
  return jsonb_build_object('id', p_id, 'provider_ref', p_provider_ref);
end $$;

create or replace function public.payment_intent_link(p_id bigint, p_sale_payment bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.sale_payments where id = p_sale_payment) then raise exception 'payment_not_found'; end if;
  if exists (select 1 from public.payment_intents where sale_payment_id = p_sale_payment and id <> p_id) then raise exception 'payment_already_linked'; end if;
  update public.payment_intents set sale_payment_id = p_sale_payment, updated_at = now() where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return jsonb_build_object('id', p_id, 'sale_payment_id', p_sale_payment);
end $$;

-- called ONLY by the Edge function (logged in as the ops bot) AFTER it verified the provider signature. Idempotent on (provider, event_id).
create or replace function public.payment_webhook_receive(p_provider text, p_event_id text, p_provider_ref text, p_event_type text, p_status text, p_amount numeric,
                                                          p_signature_ok boolean, p_payload jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.payment_intents; ap boolean := false; nt text; rk int; rk0 int; n int; pl jsonb;
begin
  if not (public._is_ops('notify') or public.is_owner()) then raise exception 'not allowed'; end if;
  if not public.rule_on('pay_gateway_on') then return jsonb_build_object('off', true); end if;
  if p_provider is null or p_provider !~ '^[a-z0-9_]{2,24}$' or p_event_id is null or length(p_event_id) not between 1 and 120 or p_signature_ok is null
     or (p_status is not null and p_status not in ('pending', 'succeeded', 'failed', 'cancelled', 'refunded'))
     or (p_amount is not null and (p_amount < 0 or p_amount > 1000000000000)) or (p_provider_ref is not null and length(p_provider_ref) > 100)
     or (p_event_type is not null and length(p_event_type) > 60) or length(coalesce(p_payload, '{}'::jsonb)::text) > 20000 then raise exception 'bad_input'; end if;
  pl := coalesce(p_payload, '{}'::jsonb);
  if jsonb_typeof(pl) = 'object' then pl := pl - array['authorization', 'signature', 'secret', 'token', 'password', 'api_key', 'apikey', 'card', 'card_number', 'cvv']; end if;
  if not p_signature_ok then nt := 'bad_signature';
  else
    select * into it from public.payment_intents where provider = p_provider and provider_ref = p_provider_ref for update;
    if not found then nt := 'no_intent';
    elsif p_status is null then nt := 'no_status';
    else
      rk := case p_status when 'pending' then 1 when 'failed' then 2 when 'cancelled' then 2 when 'succeeded' then 3 else 4 end;
      rk0 := case it.status when 'created' then 0 when 'pending' then 1 when 'failed' then 2 when 'cancelled' then 2 when 'succeeded' then 3 else 4 end;
      if rk > rk0 or (rk = rk0 and rk = 2 and it.status <> p_status) then ap := true; nt := 'applied'; else nt := 'stale_event'; end if;
    end if;
  end if;
  insert into public.payment_webhook_log (provider, event_id, provider_ref, event_type, status, amount, signature_ok, payload, applied, note)
    values (p_provider, p_event_id, p_provider_ref, p_event_type, p_status, p_amount, p_signature_ok, pl, ap, nt) on conflict (provider, event_id) do nothing;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('duplicate', true); end if;
  if ap then
    update public.payment_intents set status = p_status, updated_at = now(),
        paid_amount = case when p_status = 'succeeded' then p_amount else paid_amount end where id = it.id;
  end if;
  return jsonb_build_object('duplicate', false, 'applied', ap, 'note', nt);
end $$;

-- reconciliation: one row per intent against sale_payments (matched by explicit link, else mobile payment with the same ref). Not readable by browsers: use payment_recon().
create or replace view public.payment_recon_v as
  select i.id as intent_id, i.provider, i.provider_ref, i.sale_id, i.location_id, i.amount as intent_amount, i.status as intent_status, i.paid_amount,
         sp.id as sale_payment_id, sp.amount as payment_amount, sp.voided as payment_voided,
         case when i.status in ('created', 'pending') then 'open'
              when i.status in ('failed', 'cancelled') then 'closed_unpaid'
              when i.status = 'refunded' then 'refunded'
              when sp.id is null then 'missing_payment'
              when sp.voided then 'voided_payment'
              when sp.amount <> coalesce(i.paid_amount, i.amount) or coalesce(i.paid_amount, i.amount) <> i.amount then 'amount_mismatch'
              else 'matched' end as state,
         coalesce(i.paid_amount, 0) - coalesce(sp.amount, 0) as diff
    from public.payment_intents i
    left join lateral (select p.* from public.sale_payments p
                        where p.id = i.sale_payment_id
                           or (i.sale_payment_id is null and i.provider_ref is not null and p.mode = 'mobile' and p.ref = i.provider_ref and not exists
                               (select 1 from public.payment_intents i2 where i2.sale_payment_id = p.id))
                        order by (p.id = i.sale_payment_id) desc, p.id limit 1) sp on true;
revoke all on public.payment_recon_v from public, anon, authenticated;

create or replace function public.payment_recon(p_from date default null, p_to date default null, p_state text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare fr timestamptz; tt timestamptz; v_all boolean := public._acct_all();
begin
  if not public._i62_pay_ok() then raise exception 'not allowed'; end if;
  if p_state is not null and p_state not in ('open', 'closed_unpaid', 'refunded', 'missing_payment', 'voided_payment', 'amount_mismatch', 'matched') then raise exception 'bad_input'; end if;
  fr := coalesce(p_from, (now() at time zone 'Asia/Dhaka')::date - 30)::timestamp at time zone 'Asia/Dhaka';
  tt := (coalesce(p_to, (now() at time zone 'Asia/Dhaka')::date) + 1)::timestamp at time zone 'Asia/Dhaka';
  if tt - fr > interval '400 days' then raise exception 'bad_range'; end if;
  return jsonb_build_object('on', public.rule_on('pay_gateway_on'),
    'counts', coalesce((select jsonb_object_agg(state, n) from (select v.state, count(*) n from public.payment_recon_v v join public.payment_intents i on i.id = v.intent_id
                          where i.created_at >= fr and i.created_at < tt and (v_all or public.can_loc(v.location_id)) group by v.state) s), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.intent_id desc) from (
        select v.* from public.payment_recon_v v join public.payment_intents i on i.id = v.intent_id
         where i.created_at >= fr and i.created_at < tt and (v_all or public.can_loc(v.location_id)) and (p_state is null or v.state = p_state)
         order by v.intent_id desc limit 500) x), '[]'::jsonb),
    'orphan_events', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'provider', w.provider, 'event_id', w.event_id, 'provider_ref', w.provider_ref, 'status', w.status,
          'amount', w.amount, 'note', w.note, 'received_at', w.received_at) order by w.id desc)
        from (select * from public.payment_webhook_log where received_at >= fr and received_at < tt and note in ('no_intent', 'bad_signature') order by id desc limit 200) w), '[]'::jsonb));
end $$;

-- ============================================================
-- #23  accounting export (read-only, generic CSV)
-- ============================================================
create or replace function public.acct_export_csv(p_kind text, p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare st date := public._acct_start(); to_ date := coalesce(p_to, public._acct_today()); fr date; v_all boolean := public._acct_all(); cr text := E'\r\n';
  hdr text; body text; n int; tot int; cap constant int := 50000; tb jsonb; td numeric := 0; tc numeric := 0;
begin
  if not public._acct_manage() then raise exception 'not allowed'; end if;
  if p_kind is null or p_kind not in ('journal', 'trial_balance') then raise exception 'bad_input'; end if;
  if st is null then return jsonb_build_object('data_needed', true); end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  fr := coalesce(p_from, st);
  if fr > to_ or to_ - fr > 3660 then raise exception 'bad_range'; end if;
  if p_kind = 'journal' then
    hdr := 'entry_id,entry_date,location_code,source_type,source_id,subtype,status,reverses_id,entry_memo,line_no,account_code,account_name_en,account_type,debit,credit,line_location_code,party_type,party_id,line_memo';
    select count(*) into tot from public.journal_entries e where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc);
    select count(*), string_agg(r.line, cr order by r.entry_date, r.entry_id, r.line_no) into n, body from (
      select e.entry_date, e.id entry_id, l.line_no,
        concat_ws(',', e.id::text, e.entry_date::text, public._i62_csv(le.code), public._i62_csv(e.source_type), public._i62_csv(e.source_id), public._i62_csv(e.subtype), e.status,
          coalesce(e.reverses_id::text, ''), public._i62_csv(e.memo), l.line_no::text, public._i62_csv(a.code), public._i62_csv(a.name_en), a.type,
          to_char(l.debit, 'FM999999999999990.00'), to_char(l.credit, 'FM999999999999990.00'), public._i62_csv(ll.code), coalesce(l.party_type, ''), public._i62_csv(l.party_id), public._i62_csv(l.memo)) line
        from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
        left join public.locations le on le.id = e.location_id left join public.locations ll on ll.id = l.location_id
       where e.entry_date between fr and to_ and (v_all or (e.location_id is not null and public.can_loc(e.location_id))) and (p_loc is null or e.location_id = p_loc)
       order by e.entry_date, e.id, l.line_no limit cap) r;
    return jsonb_build_object('kind', 'journal', 'filename', 'journal_' || fr || '_' || to_ || '.csv', 'mime', 'text/csv', 'from', fr, 'to', to_, 'entries', tot, 'rows', coalesce(n, 0),
      'truncated', coalesce(n, 0) >= cap, 'csv', hdr || cr || coalesce(body, ''), 'columns', string_to_array(hdr, ','));
  end if;
  tb := public.acct_trial_balance(fr, to_, p_loc);
  hdr := 'account_code,account_name_en,account_name_bn,account_type,is_group,opening_debit,opening_credit,period_debit,period_credit,closing_debit,closing_credit';
  select count(*), string_agg(concat_ws(',', public._i62_csv(x ->> 'code'), public._i62_csv(x ->> 'name_en'), public._i62_csv(x ->> 'name_bn'), x ->> 'type', x ->> 'is_group',
          to_char((x ->> 'open_dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'open_cr')::numeric, 'FM999999999999990.00'),
          to_char((x ->> 'dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'cr')::numeric, 'FM999999999999990.00'),
          to_char((x ->> 'close_dr')::numeric, 'FM999999999999990.00'), to_char((x ->> 'close_cr')::numeric, 'FM999999999999990.00')), cr order by x ->> 'code')
    into n, body from jsonb_array_elements(tb -> 'rows') x;
  return jsonb_build_object('kind', 'trial_balance', 'filename', 'trial_balance_' || fr || '_' || to_ || '.csv', 'mime', 'text/csv', 'from', fr, 'to', to_, 'rows', coalesce(n, 0),
    'total_debit', tb -> 'total_debit', 'total_credit', tb -> 'total_credit', 'balanced', tb -> 'balanced', 'csv', hdr || cr || coalesce(body, ''), 'columns', string_to_array(hdr, ','));
end $$;

-- ============================================================
-- #30  AI Assistant access: owner by default, anyone else ONLY with the explicit grant assistant_use (bos62)
-- ============================================================
create or replace function public._assistant_ok() returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_active() then return false; end if;
  if not public.rule_on('assistant_on') then return false; end if;
  -- bos62: head_management and the assistant_roles rule no longer open the assistant; only the owner or an explicit assistant_use grant (any place) does
  return public.is_owner() or public._assistant_any_grant('assistant_use');
end $$;

create or replace function public.assistant_access_list() returns jsonb   -- owner only: who holds assistant_use (per person, per role)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  return jsonb_build_object('on', public.rule_on('assistant_on'),
    'users', coalesce((select jsonb_agg(jsonb_build_object('user_id', g.user_id, 'name', p.full_name, 'location_id', g.location_id, 'valid_until', g.valid_until) order by p.full_name)
                         from public.user_grants g join public.profiles p on p.id = g.user_id where g.grant_code = 'assistant_use' and (g.valid_until is null or g.valid_until > now())), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(rg.role_code order by rg.role_code) from public.rule_grants rg where rg.grant_code = 'assistant_use' and rg.allowed), '[]'::jsonb));
end $$;

-- ---------- privileges ----------
revoke all on function public._i62_ok(), public._i62_ops(), public._i62_ro(), public._i62_phone(text), public._i62_csv(text), public._i62_pay_ok() from public, anon, authenticated;
grant execute on function public._i62_ok(), public._i62_pay_ok() to authenticated;      -- used inside RLS policies
revoke all on function public.notify_template_save(text, text, text, text, boolean), public.notify_optin_set(uuid, text, boolean, text, text),
  public.notify_enqueue(uuid, uuid, text, text, jsonb, text, text, text), public.notify_cancel(bigint), public.notify_outbox_summary(),
  public.notify_outbox_claim(int), public.notify_outbox_report(bigint, boolean, text, text),
  public.payment_intent_create(uuid, text, uuid, uuid, int, numeric, text, text), public.payment_intent_set_ref(bigint, text), public.payment_intent_link(bigint, bigint),
  public.payment_webhook_receive(text, text, text, text, text, numeric, boolean, jsonb), public.payment_recon(date, date, text),
  public.acct_export_csv(text, date, date, int), public.assistant_access_list() from public, anon;
grant execute on function public.notify_template_save(text, text, text, text, boolean), public.notify_optin_set(uuid, text, boolean, text, text),
  public.notify_enqueue(uuid, uuid, text, text, jsonb, text, text, text), public.notify_cancel(bigint), public.notify_outbox_summary(),
  public.notify_outbox_claim(int), public.notify_outbox_report(bigint, boolean, text, text),
  public.payment_intent_create(uuid, text, uuid, uuid, int, numeric, text, text), public.payment_intent_set_ref(bigint, text), public.payment_intent_link(bigint, bigint),
  public.payment_webhook_receive(text, text, text, text, text, numeric, boolean, jsonb), public.payment_recon(date, date, text),
  public.acct_export_csv(text, date, date, int), public.assistant_access_list() to authenticated;

