-- ============================================================
-- BOS tool · Phase 12 (W0 carry-over, owner's list HANDOVER §8 items 1-5, 7-12, 14): items / stock / purchase finishing work.
-- Run AFTER phase8, phase9, phase10 (phase11 may come before or after; nothing here depends on it).
-- ADDITIVE and IDEMPOTENT: safe to paste whole and run again. Nothing existing is dropped. Functions that are re-created keep ALL their old behaviour
-- (the old text is copied and extended); where another phase may also have replaced a function, a wrapper is used instead of a copy.
--
-- What is here
--   1  items.details (text) + apply_item_patch learns it (wrapper around the existing function, so any later column added by another phase is kept)
--   2  items_with_cost(): item costs for people who hold only the grant view_cost (item_costs RLS is NOT changed)
--   8  photos for stock / purchase: storage prefixes STOCK/<loc>/... and PURCHASE/<loc>/... decided by grants (photo_ok re-created, all old prefixes unchanged)
--   9  emergency keys for stock_count_adjust / stock_transfer / stock_issue / stock_production (all OFF by default)
--  10  wastage maker-checker: rule wastage_approval_limit (empty = off); above it the write-off waits for ANOTHER person holding the grant wastage_approve
--  11  supplier refund (cash back from a supplier) and sale_return (restock, batch aware, reduces the customer's due first, or refunds)
--  12  rule block_expired_sale (default OFF): on = a sale from an expired batch is refused; off = the red exception 'sold_expired' as before
--  14  stock_ledger.ref_id is no longer readable by location users directly (column privilege); stock_ledger_rows() still returns it where allowed
-- No business number is invented: the new limit is empty, the new switches are off (block_expired_sale, every em_*), sale_return_due_first is on only
-- because refunding the cash of a customer who still owes us would be silly; the owner can switch it off.
-- ============================================================

-- ---------- (1) items.details ----------
alter table public.items add column if not exists details text;

do $$
begin
  if position('bos12-details' in pg_get_functiondef('public.apply_item_patch(uuid,jsonb)'::regprocedure)) = 0 then
    drop function if exists public._apply_item_patch_base(uuid, jsonb);
    alter function public.apply_item_patch(uuid, jsonb) rename to _apply_item_patch_base;
    execute $f$
      create function public.apply_item_patch(p_item uuid, p_patch jsonb) returns uuid
      language plpgsql security definer set search_path = public as $b$
      declare iid uuid;   -- bos12-details: everything else is done by the previous version, kept as _apply_item_patch_base
      begin
        iid := public._apply_item_patch_base(p_item, p_patch);
        if p_patch ? 'details' then
          update public.items set details = left(nullif(btrim(p_patch->>'details'), ''), 2000) where id = iid;
        end if;
        return iid;
      end $b$ $f$;
  end if;
end $$;
revoke all on function public.apply_item_patch(uuid, jsonb), public._apply_item_patch_base(uuid, jsonb) from public, anon, authenticated;

-- ---------- (2) costs for view_cost holders ----------
create or replace function public.items_with_cost() returns table (item_id uuid, cost_price numeric)
language sql stable security definer set search_path = public as $$
  select c.item_id, c.cost_price from public.item_costs c
  where public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view') or public.has_grant('view_cost'));
$$;
revoke all on function public.items_with_cost() from public, anon;
grant execute on function public.items_with_cost() to authenticated;

-- ---------- rules, grants ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('wastage_approval_limit', 'stock', 'number', null, null, null, 0, 1000000000, 'এর বেশি পরিমাণ নষ্ট দেখাতে হলে আরেকজনের অনুমোদন লাগবে (বেস এককে)', 'এর বেশি quantity নষ্ট দেখাতে হলে আরেকজনের approval লাগবে (base unit এ)', 'A wastage above this quantity waits for a second person to approve (in the item base unit)', 'Empty = Data needed = off (every write-off posts at once). The owner is never held back', 103),
 ('block_expired_sale', 'stock', 'switch', 'false', null, null, null, null, 'মেয়াদোত্তীর্ণ মাল বিক্রি আটকানো', 'মেয়াদোত্তীর্ণ মাল sale আটকানো', 'Block selling expired stock', 'Off = the sale goes through and the owner gets a red line (as before). On = the sale is refused. A sale that syncs late from an offline phone is never refused', 104),
 ('sale_return_due_first', 'pos', 'switch', 'true', null, null, null, null, 'বিক্রি ফেরতে আগে গ্রাহকের বাকি কমবে, বাকি টাকা ফেরত', 'Sale return এ আগে customer এর due কমবে, বাকি টাকা ফেরত', 'A sale return first reduces what the customer owes; only the rest is refunded', 'Off = the whole value is refunded in cash / mobile / card', 90),
 ('em_stock_count_adjust', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: গণনা অনুযায়ী স্টক ঠিক', 'জরুরি request চলবে: count অনুযায়ী stock ঠিক', 'Emergency allowed for: adjusting stock to a count', 'Off by default', 127),
 ('em_stock_transfer', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: মাল পাঠানো / গ্রহণ', 'জরুরি request চলবে: মাল transfer / receive', 'Emergency allowed for: sending / receiving stock', 'Off by default', 128),
 ('em_stock_issue', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: উৎপাদনে কাঁচামাল দেওয়া', 'জরুরি request চলবে: production এ কাঁচামাল issue', 'Emergency allowed for: issuing material to production', 'Off by default', 129),
 ('em_stock_production', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: উৎপাদিত মাল স্টকে তোলা', 'জরুরি request চলবে: production এর মাল stock এ তোলা', 'Emergency allowed for: posting production into stock', 'Off by default', 130),
 ('em_sale_return', 'emergency', 'switch', 'false', null, null, null, null, 'জরুরি অনুরোধ চলবে: বিক্রি ফেরত নেওয়া', 'জরুরি request চলবে: sale return নেওয়া', 'Emergency allowed for: taking a sale return', 'Off by default', 131)
on conflict (key) do nothing;

with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('wastage_approve', 'stock', 47, 'বড় নষ্ট মাল বাদ দেওয়া অনুমোদন', 'বড় wastage write-off approve', 'Approve a large wastage write-off', 'once', null),
   ('sale_return', 'pos', 11, 'বিক্রি ফেরত নেওয়া', 'Sale return নেওয়া', 'Take a sale return', 'once', 'em_sale_return')
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values
    ('wastage_approve', 'management'),
    ('sale_return', 'management'), ('sale_return', 'showroom_manager')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- (9) the four stock grants now name their emergency switch (an owner's own choice is never overwritten: only a still-empty one is filled)
update public.grant_defs set emergency_rule = 'em_' || grant_code where grant_code in ('stock_count_adjust', 'stock_transfer', 'stock_issue', 'stock_production') and emergency_rule is null;

-- ---------- (8) photos: STOCK / PURCHASE prefixes ----------
-- path = <PREFIX or form code>/<location id>/<file>.jpg ; the old form-code prefixes behave exactly as before.
create or replace function public.photo_ok(p_name text, p_action text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active()
    and split_part(p_name, '/', 2) ~ '^[0-9]+$'
    and public.can_loc(split_part(p_name, '/', 2)::int)
    and case split_part(p_name, '/', 1)
      when 'STOCK' then
        case when p_action = 'view' then true          -- anyone who works at that location may see a stock photo (wastage, count)
             else (public.has_grant('wastage_write_off', split_part(p_name, '/', 2)::int) or public.has_grant('stock_count_adjust', split_part(p_name, '/', 2)::int)
                   or public.has_grant('stock_transfer', split_part(p_name, '/', 2)::int) or public.has_grant('stock_issue', split_part(p_name, '/', 2)::int)
                   or public.has_grant('stock_production', split_part(p_name, '/', 2)::int) or public.has_grant('stock_opening', split_part(p_name, '/', 2)::int)) end
      when 'PURCHASE' then
        case when p_action = 'view' then public._pur_ok(split_part(p_name, '/', 2)::int)      -- a bill photo shows costs: only the purchase people
             else (public.has_grant('purchase_entry', split_part(p_name, '/', 2)::int) or public.has_grant('purchase_return', split_part(p_name, '/', 2)::int)
                   or public.has_grant('supplier_pay', split_part(p_name, '/', 2)::int)) end
      else public.can_do(split_part(p_name, '/', 1), p_action) end;
$$;
revoke all on function public.photo_ok(text, text) from public, anon;
grant execute on function public.photo_ok(text, text) to authenticated;

-- ---------- (14) stock_ledger.ref_id: not readable directly (a purchase bill id would open a bill) ----------
revoke select on public.stock_ledger from authenticated;
grant select (id, item_id, location_id, qty_delta, reason, ref_type, batch_id, reverses_id, made_at, note, created_by, created_at) on public.stock_ledger to authenticated;

-- ---------- (12) stock_post: optional block of expired stock, and a sale return puts goods back into its batch ----------
-- identical to phase10 except the two marked places
create or replace function public.stock_post(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_ref_type text default null, p_ref_id text default null,
  p_unit_cost numeric default null, p_batch bigint default null, p_made_at timestamptz default null, p_note text default null,
  p_reverses bigint default null, p_neg text default 'full', p_sale uuid default null, p_client uuid default null) returns bigint
language plpgsql security definer set search_path = public as $$
declare q numeric := round(p_qty, 4); bal public.stock_balance; mode text; cost numeric; lid bigint; first_id bigint; b record; rem numeric; take numeric;
        ic text; nm text; ne text; en text; at_ timestamptz := coalesce(p_made_at, now()); ref text := coalesce(p_ref_type, '') || ':' || coalesce(p_ref_id, '');
        d date := (coalesce(p_made_at, now()) at time zone 'Asia/Dhaka')::date; form text := case when p_sale is not null then 'POS' else 'STOCK' end;
        blk boolean := false;
begin
  if q is null or not (abs(q) between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;            -- false for NaN and Infinity too
  if p_unit_cost is not null and not (p_unit_cost between 0 and 1000000000000) then raise exception 'bad_cost'; end if;
  if p_neg not in ('full', 'soft', 'none') then raise exception 'bad_neg_mode'; end if;
  if p_reason = 'sale_out' and p_neg = 'full' then blk := public.rule_on('block_expired_sale'); end if;           -- (12) read once
  insert into public.stock_balance (item_id, location_id) values (p_item, p_loc) on conflict do nothing;
  select * into bal from public.stock_balance where item_id = p_item and location_id = p_loc for update;      -- serialises everyone touching this item here
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = p_reason order by id limit 1;
    if found then return lid; end if;
  end if;
  -- negative stock
  if q < 0 and p_neg <> 'none' and bal.qty + q < 0 then
    mode := coalesce(public.rule_txt('stock_negative_mode'), 'warn');
    if mode <> 'allow' then
      select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
      if mode = 'block' and p_neg = 'full' then
        if p_sale is null or coalesce(current_setting('bos.neg_ok', true), '') <> p_sale::text then
          if not (public.has_grant('sell_below_zero', p_loc)
                  or case when p_sale is not null then public.use_emergency('sell_below_zero', p_loc, ref, null, null) else public._use_em('sell_below_zero', p_loc, ref, null) end) then
            raise exception 'insufficient_stock' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'on hand ' || bal.qty::text;
          end if;
          if p_sale is not null then perform set_config('bos.neg_ok', p_sale::text, true); end if;
        end if;
      end if;
      en := coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): more went out than the stock on hand — the stock is now negative';
      if exists (select 1 from public.stock_ledger where item_id = p_item and location_id = p_loc and qty_delta > 0)
         and not exists (select 1 from public.exceptions where flag_code = 'stock_negative' and location_id = p_loc and entry_date = d and text->>'en' = en) then
        perform public._stock_exc(p_loc, 'stock_negative', 'yellow', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): স্টকের চেয়ে বেশি বের হয়েছে — হিসাবে স্টক ঋণাত্মক', en, p_sale, d, form);
      end if;
    end if;
  end if;
  cost := coalesce(p_unit_cost, case when q < 0 then bal.avg_cost end);
  if q < 0 and p_batch is null and p_reason in ('sale_out', 'issue_out', 'wastage', 'transfer_out', 'count_adjust', 'purchase_return') then
    rem := -q;
    for b in select id, qty_remaining, expires_at from public.stock_batches where item_id = p_item and location_id = p_loc and qty_remaining > 0
             order by (expires_at is not null and expires_at <= at_), expires_at nulls last, made_at, id for update loop
      if blk and b.expires_at is not null and b.expires_at <= at_ then          -- (12) the owner switched "block expired sale" on
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        raise exception 'expired_stock_blocked' using detail = coalesce(ic, '') || ' ' || coalesce(nm, ''), hint = 'batch ' || b.id::text;
      end if;
      take := least(b.qty_remaining, rem);
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -take, cost, p_reason, p_ref_type, p_ref_id, b.id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      update public.stock_batches set qty_remaining = case when qty_remaining - take < 0.0005 then 0 else qty_remaining - take end where id = b.id;
      first_id := coalesce(first_id, lid); rem := rem - take;
      if p_reason = 'sale_out' and b.expires_at is not null and b.expires_at <= at_ then
        select code, name_bn, name_en into ic, nm, ne from public.items where id = p_item;
        perform public._stock_exc(p_loc, 'sold_expired', 'red', coalesce(nm, '') || ' (' || coalesce(ic, '') || '): মেয়াদ শেষ হওয়া মাল বিক্রি হয়েছে',
          coalesce(ne, nm, '') || ' (' || coalesce(ic, '') || '): stock past its expiry was sold', p_sale, d, form);
      end if;
      exit when rem <= 0;
    end loop;
    if rem > 0 then
      insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, reverses_id, client_id, made_at, note, created_by)
        values (p_item, p_loc, -rem, cost, p_reason, p_ref_type, p_ref_id, p_reverses, case when first_id is null then p_client end, at_, p_note, auth.uid()) returning id into lid;
      first_id := coalesce(first_id, lid);
    end if;
    return first_id;
  end if;
  insert into public.stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, batch_id, reverses_id, client_id, made_at, note, created_by)
    values (p_item, p_loc, q, cost, p_reason, p_ref_type, p_ref_id, p_batch, p_reverses, p_client, at_, p_note, auth.uid()) returning id into lid;
  if p_batch is not null then
    if q < 0 then
      update public.stock_batches set qty_remaining = case when qty_remaining + q < 0.0005 then 0 else qty_remaining + q end where id = p_batch and qty_remaining + q >= 0;
      if not found then raise exception 'batch_short'; end if;
    elsif p_reason in ('sale_void_in', 'reversal', 'sale_return') then          -- (11) 'sale_return' added
      update public.stock_batches set qty_remaining = least(qty_made, qty_remaining + q) where id = p_batch;
    end if;
  end if;
  return lid;
end $$;

-- ---------- (10) wastage maker-checker ----------
create table if not exists public.wastage_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  item_id uuid not null references public.items(id),
  location_id int not null references public.locations(id),
  qty numeric not null check (qty > 0 and qty between 0 and 1000000000000),          -- base unit
  reason_code text not null,
  note text, photo text,
  batch_id bigint,                                                   -- no foreign key: keeps the ledger tables free of dependants
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  requested_by uuid not null, requested_staff text, requested_at timestamptz not null default now(),
  decided_by uuid, decided_staff text, decided_at timestamptz, decision_note text,
  wastage_id uuid
);
create index if not exists wastage_requests_open on public.wastage_requests (location_id, status);
drop trigger if exists audit_wastage_requests on public.wastage_requests;
create trigger audit_wastage_requests after insert or update on public.wastage_requests for each row execute function public.log_change('id');
alter table public.wastage_requests enable row level security;
drop policy if exists wastage_requests_read on public.wastage_requests;
create policy wastage_requests_read on public.wastage_requests for select to authenticated
  using (public.can_loc(location_id) and (requested_by = auth.uid() or public.has_grant('wastage_approve', location_id)));
revoke all on public.wastage_requests from public, anon, authenticated;
grant select on public.wastage_requests to authenticated;

-- the posting itself (shared by a direct write-off and an approved request). Internal.
create or replace function public._wastage_post(p_item uuid, p_loc int, p_bq numeric, p_reason text, p_note text, p_photo text, p_batch bigint,
  p_client uuid, p_by uuid, p_staff text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; wid uuid := gen_random_uuid(); lid bigint;
begin
  select * into it from public.items where id = p_item;
  begin
    lid := public.stock_post(p_item, p_loc, -p_bq, 'wastage', 'wastage', wid::text, null, p_batch, now(), left(p_note, 200), null, 'full', null, p_client);
    insert into public.stock_wastage (id, item_id, location_id, qty, reason_code, note, photo, batch_id, ledger_id, created_by, created_staff)
      values (wid, p_item, p_loc, p_bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, lid, p_by, p_staff);
  exception when unique_violation then          -- the same client id arrived twice at once: the first one wins, this one is the duplicate
    select id into lid from public.stock_ledger where p_client is not null and client_id = p_client and reason = 'wastage' order by id limit 1;
    if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    raise;
  end;
  if p_reason = 'unknown' then
    perform public._stock_exc(p_loc, 'wastage_unknown', 'yellow', it.name_bn || ': নষ্ট মাল বাদ দেওয়া হয়েছে কিন্তু কারণ অজানা', coalesce(it.name_en, it.name_bn) || ': stock was written off with an unknown reason');
  end if;
  return jsonb_build_object('id', wid, 'ledger_id', lid, 'qty', p_bq);
end $$;

-- write off wasted stock (same behaviour as phase10) + maker-checker above the owner's limit
create or replace function public.stock_wastage(p_item uuid, p_loc int, p_qty numeric, p_reason text, p_note text default null, p_photo text default null,
  p_unit text default null, p_client uuid default null, p_batch bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare it public.items; bq numeric; lid bigint; lim numeric; sid text; alim numeric; rid uuid; rq public.wastage_requests;
begin
  it := public._stock_guard(p_item, p_loc, 'wastage_write_off', (now() at time zone 'Asia/Dhaka')::date);
  perform public._client_lock(p_client);
  if p_client is not null then
    select id into lid from public.stock_ledger where client_id = p_client and reason = 'wastage' order by id limit 1; if found then return jsonb_build_object('dup', true, 'ledger_id', lid); end if;
    select * into rq from public.wastage_requests where client_id = p_client;
    if found then
      if rq.requested_by is distinct from auth.uid() then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'pending', rq.status = 'pending', 'request_id', rq.id);
    end if;
  end if;
  if p_qty is null or not (p_qty between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'wastage_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  bq := public._base_qty(p_item, p_qty, p_unit);
  if bq is null then raise exception 'unit_unknown'; end if;
  lim := public.rule_num('wastage_photo_above');
  if lim is not null and bq > lim and nullif(btrim(p_photo), '') is null then raise exception 'photo_required'; end if;
  if length(coalesce(p_photo, '')) > 300 then raise exception 'bad_photo'; end if;
  if not public._may('wastage_write_off', p_loc, 'wastage:' || p_item::text, bq) then raise exception 'not allowed'; end if;
  if p_batch is not null and not exists (select 1 from public.stock_batches where id = p_batch and item_id = p_item and location_id = p_loc) then raise exception 'batch_not_found'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  alim := public.rule_num('wastage_approval_limit');
  if alim is not null and bq > alim and not public.is_owner() then
    begin
      insert into public.wastage_requests (client_id, item_id, location_id, qty, reason_code, note, photo, batch_id, requested_by, requested_staff)
        values (p_client, p_item, p_loc, bq, p_reason, left(p_note, 200), nullif(btrim(p_photo), ''), p_batch, auth.uid(), sid) returning id into rid;
    exception when unique_violation then
      select * into rq from public.wastage_requests where p_client is not null and client_id = p_client;
      if found and rq.requested_by = auth.uid() then return jsonb_build_object('dup', true, 'pending', rq.status = 'pending', 'request_id', rq.id); end if;
      raise;
    end;
    perform public._stock_exc(p_loc, 'wastage_pending', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ — অনুমোদনের অপেক্ষায় (' || bq::text || ')',
      coalesce(it.name_en, it.name_bn) || ': a large wastage write-off is waiting for approval (' || bq::text || ')');
    return jsonb_build_object('pending', true, 'request_id', rid, 'qty', bq);
  end if;
  return public._wastage_post(p_item, p_loc, bq, p_reason, p_note, p_photo, p_batch, p_client, auth.uid(), sid);
end $$;

-- a DIFFERENT person with the grant wastage_approve (or the owner) decides. Approving posts the write-off now.
create or replace function public.wastage_decide(p_id uuid, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.wastage_requests; sid text; res jsonb; it public.items;
begin
  select * into r from public.wastage_requests where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) or not public.has_grant('wastage_approve', r.location_id) then raise exception 'not allowed'; end if;
  perform 1 from public.wastage_requests where id = p_id for update;
  select * into r from public.wastage_requests where id = p_id;
  if r.status <> 'pending' then
    if r.status = (case when p_approve then 'approved' else 'rejected' end) then return jsonb_build_object('dup', true, 'status', r.status); end if;
    raise exception 'already_decided';
  end if;
  if r.requested_by = auth.uid() then raise exception 'own_request'; end if;
  if not p_approve and (p_note is null or length(btrim(p_note)) = 0) then raise exception 'note_required'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  select staff_id into sid from public.profiles where id = auth.uid();
  if p_approve then
    res := public._wastage_post(r.item_id, r.location_id, r.qty, r.reason_code, coalesce(r.note, '') || case when r.note is null then '' else ' · ' end || 'approved by ' || coalesce(sid, '?'),
                                r.photo, r.batch_id, r.client_id, r.requested_by, r.requested_staff);
    update public.wastage_requests set status = 'approved', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(nullif(btrim(p_note), ''), 300),
      wastage_id = nullif(res->>'id', '')::uuid where id = p_id;
    return jsonb_build_object('status', 'approved') || res;
  end if;
  update public.wastage_requests set status = 'rejected', decided_by = auth.uid(), decided_staff = sid, decided_at = now(), decision_note = left(btrim(p_note), 300) where id = p_id;
  select * into it from public.items where id = r.item_id;
  perform public._stock_exc(r.location_id, 'wastage_rejected', 'yellow', it.name_bn || ': বড় নষ্ট মাল বাদ নামঞ্জুর — ' || left(btrim(p_note), 100),
    coalesce(it.name_en, it.name_bn) || ': a large wastage write-off was rejected — ' || left(btrim(p_note), 100));
  return jsonb_build_object('status', 'rejected');
end $$;

-- the requester takes a pending request back
create or replace function public.wastage_cancel(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.wastage_requests;
begin
  select * into r from public.wastage_requests where id = p_id for update;
  if not found or r.requested_by <> auth.uid() then raise exception 'not allowed'; end if;
  if r.status = 'cancelled' then return jsonb_build_object('dup', true, 'status', 'cancelled'); end if;
  if r.status <> 'pending' then raise exception 'already_decided'; end if;
  update public.wastage_requests set status = 'cancelled', decided_by = auth.uid(), decided_at = now() where id = p_id;
  return jsonb_build_object('status', 'cancelled');
end $$;

-- the waiting list: approvers see every pending request of their locations, anyone sees their own
create or replace function public.wastage_pending(p_loc int default null, p_status text default 'pending')
returns table (id uuid, item_id uuid, code text, name_bn text, name_en text, location_id int, qty numeric, base_unit text, reason_code text, note text, photo text,
               status text, requested_staff text, requested_at timestamptz, mine boolean, can_decide boolean, decision_note text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  return query
    select r.id, r.item_id, i.code, i.name_bn, i.name_en, r.location_id, r.qty, public._item_base(i.id), r.reason_code, r.note, r.photo, r.status, r.requested_staff, r.requested_at,
           r.requested_by = auth.uid(), (r.status = 'pending' and r.requested_by <> auth.uid() and public.has_grant('wastage_approve', r.location_id)), r.decision_note
    from public.wastage_requests r join public.items i on i.id = r.item_id
    where public.can_loc(r.location_id) and (p_loc is null or r.location_id = p_loc) and (p_status is null or r.status = p_status)
      and (r.requested_by = auth.uid() or public.has_grant('wastage_approve', r.location_id))
    order by r.requested_at desc limit 200;
end $$;

-- ---------- (11a) supplier refund: cash back from a supplier, reduces the supplier's credit ----------
create table if not exists public.supplier_refunds (
  id bigserial primary key,
  supplier_id uuid not null references public.suppliers(id),
  location_id int not null references public.locations(id),
  mode text not null check (mode in ('cash', 'mobile', 'card', 'bank')),
  wallet text, ref text,
  amount numeric not null check (amount > 0 and amount between 0 and 1000000000000),
  refunded_at timestamptz not null default now(),
  reason_code text, note text,
  voided boolean not null default false, void_note text, void_by uuid,
  created_by uuid, created_staff text, client_id uuid
);
create index if not exists supplier_refunds_sup on public.supplier_refunds (supplier_id) where not voided;
create unique index if not exists supplier_refunds_client on public.supplier_refunds (client_id) where client_id is not null;
drop trigger if exists audit_supplier_refunds on public.supplier_refunds;
create trigger audit_supplier_refunds after insert or update on public.supplier_refunds for each row execute function public.log_change('id');
alter table public.supplier_refunds enable row level security;
drop policy if exists supplier_refunds_read on public.supplier_refunds;
create policy supplier_refunds_read on public.supplier_refunds for select to authenticated using (public._pur_ok(location_id));
revoke all on public.supplier_refunds from public, anon, authenticated;
revoke all on sequence public.supplier_refunds_id_seq from public, anon, authenticated;
grant select on public.supplier_refunds to authenticated;

-- balance owed = opening + bills - returns - payments + refunds received (a refund uses up credit, so we owe more / are owed less)
create or replace function public._sup_balance(p_supplier uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select opening_balance from public.suppliers where id = p_supplier), 0)
       + coalesce((select sum(case kind when 'bill' then total else -total end) from public.purchase_bills where supplier_id = p_supplier and status = 'posted'), 0)
       - coalesce((select sum(amount) from public.supplier_payments where supplier_id = p_supplier and not voided), 0)
       + coalesce((select sum(amount) from public.supplier_refunds where supplier_id = p_supplier and not voided), 0);
$$;

-- open-bill allocation: a refund is NEGATIVE credit at the location where it was taken (copy of phase10 + one union branch)
create or replace function public._sup_open(p_supplier uuid default null)
returns table (supplier_id uuid, bill_id uuid, bill_no text, bill_date date, location_id int, rem numeric, open_amt numeric)
language sql stable security definer set search_path = public as $$
  with bills as (
    select b.supplier_id, b.id bill_id, b.bill_no, b.bill_date, b.location_id, b.total - b.paid rem, coalesce(b.posted_at, b.created_at) ord_at, coalesce(b.location_id, -1) lk
    from public.purchase_bills b where b.status = 'posted' and b.kind = 'bill' and b.total - b.paid > 0 and (p_supplier is null or b.supplier_id = p_supplier)
    union all
    select s.id, null::uuid, 'opening', null::date, null::int, s.opening_balance, '-infinity'::timestamptz, -1
    from public.suppliers s where s.opening_balance > 0 and (p_supplier is null or s.id = p_supplier)),
  lc as (
    select z.supplier_id, z.lk, sum(z.x) credit from (
      select p.supplier_id, p.location_id lk, p.amount x from public.supplier_payments p where not p.voided and p.bill_id is null and (p_supplier is null or p.supplier_id = p_supplier)
      union all select b.supplier_id, b.location_id, b.total from public.purchase_bills b where b.status = 'posted' and b.kind = 'return' and (p_supplier is null or b.supplier_id = p_supplier)
      union all select f.supplier_id, f.location_id, -f.amount from public.supplier_refunds f where not f.voided and (p_supplier is null or f.supplier_id = p_supplier)) z
    group by 1, 2),
  oc as (select s.id supplier_id, -s.opening_balance credit from public.suppliers s where s.opening_balance < 0 and (p_supplier is null or s.id = p_supplier)),
  c1 as (select bills.*, sum(bills.rem) over (partition by bills.supplier_id, bills.lk order by bills.bill_date nulls first, bills.ord_at, bills.bill_id) c from bills),
  a1 as (
    select c1.supplier_id, c1.bill_id, c1.bill_no, c1.bill_date, c1.location_id, c1.rem, c1.ord_at,
           c1.rem - least(c1.rem, greatest(0, coalesce(lc.credit, 0) - (c1.c - c1.rem))) rem2
    from c1 left join lc on lc.supplier_id = c1.supplier_id and lc.lk = c1.lk),
  pool as (
    select z.supplier_id, sum(z.credit) - coalesce((select sum(a1.rem - a1.rem2) from a1 where a1.supplier_id = z.supplier_id), 0) spill
    from (select lc.supplier_id, lc.credit from lc union all select oc.supplier_id, oc.credit from oc) z group by 1),
  c2 as (select a1.*, sum(a1.rem2) over (partition by a1.supplier_id order by a1.bill_date nulls first, a1.ord_at, a1.bill_id) cc from a1)
  select c2.supplier_id, c2.bill_id, c2.bill_no, c2.bill_date, c2.location_id, c2.rem,
         c2.rem2 - least(c2.rem2, greatest(0, coalesce(pool.spill, 0) - (c2.cc - c2.rem2)))
  from c2 left join pool on pool.supplier_id = c2.supplier_id;
$$;

-- supplier ledger: a refund is a debit (it brings the balance back up)
create or replace function public.supplier_ledger(p_supplier uuid, p_loc int default null)
returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint, bill_id uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(p_loc) then raise exception 'not allowed'; end if;
  return query
    with e as (
      select '-infinity'::timestamptz at, 'opening'::text kind, null::text ref, null::int location_id, greatest(s.opening_balance, 0) debit, greatest(-s.opening_balance, 0) credit, null::text note, null::bigint pid, null::uuid bill_id, 0 srt
        from public.suppliers s where s.id = p_supplier and p_loc is null and coalesce(s.opening_balance, 0) <> 0
      union all
      select (b.bill_date::timestamp at time zone 'Asia/Dhaka'), case b.kind when 'bill' then 'bill' else 'return' end, coalesce(b.bill_no, '-'), b.location_id,
             case when b.kind = 'bill' then b.total else 0 end, case when b.kind = 'return' then b.total else 0 end, b.note, null::bigint, b.id, 1
        from public.purchase_bills b where b.supplier_id = p_supplier and b.status = 'posted' and (p_loc is null or b.location_id = p_loc)
      union all
      select p.paid_at, case when p.bill_id is null then 'payment' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id, p.bill_id, 2
        from public.supplier_payments p where p.supplier_id = p_supplier and not p.voided and (p_loc is null or p.location_id = p_loc)
      union all
      select f.refunded_at, 'refund', coalesce(f.wallet, f.mode), f.location_id, f.amount, 0, f.note, f.id, null::uuid, 3
        from public.supplier_refunds f where f.supplier_id = p_supplier and not f.voided and (p_loc is null or f.location_id = p_loc))
    select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, e.srt, e.pid, e.bill_id), e.note, e.pid, e.bill_id
    from e order by e.at, e.srt, e.pid, e.bill_id;
end $$;

-- record cash (or mobile / card / bank) refunded BY a supplier. Only while the supplier owes US (balance < 0), never more than that credit.
create or replace function public.supplier_refund(p_supplier uuid, p_loc int, p_amount numeric, p_mode text, p_wallet text default null, p_ref text default null,
  p_reason text default null, p_note text default null, p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare amt numeric; bal numeric; sid text; dupby uuid;
begin
  if not public.is_active() or not public.can_loc(p_loc) then raise exception 'not allowed'; end if;
  if not exists (select 1 from public.locations where id = p_loc) then raise exception 'bad_location'; end if;
  if p_mode is null or p_mode not in ('cash', 'mobile', 'card', 'bank') then raise exception 'bad_mode'; end if;
  if p_amount is null or not (p_amount between 0.01 and 999999999999) or round(p_amount, 2) <= 0 then raise exception 'bad_amount'; end if;
  amt := round(p_amount, 2);
  if p_reason is not null and not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'bad_reason'; end if;
  if p_client is not null then
    select created_by into dupby from public.supplier_refunds where client_id = p_client;
    if found then
      if not (public.has_grant('supplier_pay', p_loc) or public._pur_ok(p_loc) or dupby = auth.uid()) then raise exception 'not allowed'; end if;
      return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier));
    end if;
  end if;
  if not (public.has_grant('supplier_pay', p_loc) or public._use_em('supplier_pay', p_loc, 'supplier_refund:' || p_supplier::text, amt)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = p_supplier for update;
  if not found then raise exception 'supplier_not_found'; end if;
  if p_client is not null and exists (select 1 from public.supplier_refunds where client_id = p_client) then return jsonb_build_object('dup', true, 'balance', public._sup_balance(p_supplier)); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  bal := public._sup_balance(p_supplier);
  if bal >= 0 or amt > -bal then raise exception 'refund_exceeds_credit'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.supplier_refunds (supplier_id, location_id, mode, wallet, ref, amount, reason_code, note, created_by, created_staff, client_id)
    values (p_supplier, p_loc, p_mode, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), amt, p_reason, left(nullif(btrim(p_note), ''), 200), auth.uid(), sid, p_client);
  return jsonb_build_object('refunded', amt, 'balance', bal + amt);
end $$;

create or replace function public.void_supplier_refund(p_id bigint, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.supplier_refunds;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.supplier_refunds where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('purchase_void', r.location_id) or public._use_em('purchase_void', r.location_id, 'void_refund:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  perform 1 from public.suppliers where id = r.supplier_id for update;
  select * into r from public.supplier_refunds where id = p_id for update;
  if r.voided then raise exception 'already void'; end if;
  perform public.lock_check((r.refunded_at at time zone 'Asia/Dhaka')::date);
  update public.supplier_refunds set voided = true, void_note = left(btrim(p_note), 200), void_by = auth.uid() where id = p_id;
  perform public._stock_exc(r.location_id, 'supplier_refund_void', 'yellow', 'সাপ্লায়ার রিফান্ড বাতিল: ' || left(btrim(p_note), 100), 'A supplier refund was reversed: ' || left(btrim(p_note), 100), null, null, 'PURCHASE', r.amount);
end $$;

-- ---------- (11b) sale return ----------
create table if not exists public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique,
  sale_id uuid not null references public.sales(id),
  location_id int not null references public.locations(id),
  customer_id uuid references public.customers(id),
  lines jsonb not null,                                                -- [{item_id, name, unit, qty, price, amount}] qty in the unit of the sale line
  amount numeric not null check (amount > 0 and amount <= 1000000000000),   -- value of the goods taken back (the sale's discount share already taken off)
  credit_amount numeric not null default 0 check (credit_amount >= 0),     -- used to reduce what the customer owes
  refund_amount numeric not null default 0 check (refund_amount >= 0),     -- money handed back
  refund_mode text check (refund_mode is null or refund_mode in ('cash', 'mobile', 'card')),
  wallet text, ref text,
  reason_code text not null, note text,
  status text not null default 'done' check (status in ('done', 'void')),
  created_by uuid, created_staff text, created_at timestamptz not null default now(),
  void_by uuid, void_at timestamptz, void_note text,
  check (credit_amount + refund_amount = amount)
);
create index if not exists sale_returns_sale on public.sale_returns (sale_id);
create index if not exists sale_returns_cust on public.sale_returns (customer_id) where status = 'done';
drop trigger if exists audit_sale_returns on public.sale_returns;
create trigger audit_sale_returns after insert or update on public.sale_returns for each row execute function public.log_change('id');
alter table public.sale_returns enable row level security;
drop policy if exists sale_returns_read on public.sale_returns;
create policy sale_returns_read on public.sale_returns for select to authenticated
  using (public.can_loc(location_id) and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', location_id)));
revoke all on public.sale_returns from public, anon, authenticated;
grant select on public.sale_returns to authenticated;

-- a sale that has a live return cannot be voided (its stock would go back twice): void the return first
create or replace function public._sale_void_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.sale_returns where sale_id = new.id and status = 'done') then raise exception 'sale_has_returns'; end if;
  return new;
end $$;
drop trigger if exists sales_void_guard on public.sales;
create trigger sales_void_guard before update of status on public.sales for each row
  when (old.status is distinct from 'void' and new.status = 'void') execute function public._sale_void_guard();

-- customer balance: sold - paid - credited by returns. The gate stays as before (POS view / enter).
create or replace function public._cust_bal(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(s.total) from public.sales s where s.customer_id = p_customer and s.status = 'done'), 0)
       - coalesce((select sum(p.amount) from public.sale_payments p where p.customer_id = p_customer and not p.voided), 0)
       - coalesce((select sum(r.credit_amount) from public.sale_returns r where r.customer_id = p_customer and r.status = 'done'), 0);
$$;
create or replace function public.customer_balance(p_customer uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when public.is_active() and (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) then public._cust_bal(p_customer) end;
$$;
create or replace function public.customer_dues() returns table (id uuid, name text, mobile text, type text, credit_limit numeric, balance numeric, oldest date)
language sql stable security definer set search_path = public as $$
  with s as (
    select x.id, x.customer_id, x.sale_date, x.sold_at,
           x.total - coalesce((select sum(p.amount) from public.sale_payments p where p.sale_id = x.id and not p.voided), 0) rem
    from public.sales x where x.status = 'done' and x.customer_id is not null),
  cum as (select s.*, sum(s.rem) over (partition by s.customer_id order by s.sold_at, s.id) cr from s where s.rem > 0),
  c as (select z.customer_id, sum(z.a) coll from (
          select customer_id, amount a from public.sale_payments where kind = 'collection' and not voided and customer_id is not null
          union all select customer_id, credit_amount from public.sale_returns where status = 'done' and customer_id is not null and credit_amount > 0) z group by 1),
  t as (select customer_id, sum(rem) rem from s group by 1)
  select cu.id, cu.name, cu.mobile, cu.type, cu.credit_limit, t.rem - coalesce(c.coll, 0),
         (select min(k.sale_date) from cum k where k.customer_id = cu.id and k.cr > coalesce(c.coll, 0))
  from public.customers cu join t on t.customer_id = cu.id left join c on c.customer_id = cu.id
  where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) and t.rem - coalesce(c.coll, 0) > 0
  order by 6 desc;
$$;
create or replace function public.customer_ledger(p_customer uuid) returns table (at timestamptz, kind text, ref text, location_id int, debit numeric, credit numeric, balance numeric, note text, pid bigint)
language sql stable security definer set search_path = public as $$
  with e as (
    select s.sold_at at, 'sale'::text kind, '#' || s.receipt ref, s.location_id, s.total debit, 0::numeric credit, case when s.sale_type = 'wholesale' then 'wholesale' end note, null::bigint pid
      from public.sales s where s.customer_id = p_customer and s.status = 'done'
    union all
    select p.paid_at, case when p.kind = 'collection' then 'collection' else 'paid' end, coalesce(p.wallet, p.mode), p.location_id, 0, p.amount, p.note, p.id
      from public.sale_payments p where p.customer_id = p_customer and not p.voided
    union all
    select r.created_at, 'sale_return', '#' || s.receipt, r.location_id, 0, r.credit_amount, r.reason_code, null::bigint
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.customer_id = p_customer and r.status = 'done' and r.credit_amount > 0)
  select e.at, e.kind, e.ref, e.location_id, e.debit, e.credit, sum(e.debit - e.credit) over (order by e.at, (e.debit > 0) desc, e.kind), e.note, e.pid
  from e where (public.can_do('POS', 'view') or public.can_do('POS', 'enter')) order by e.at, (e.debit > 0) desc, e.kind;
$$;

-- take goods back from a sale. p_lines: [{"item_id":uuid,"qty":1.5}] (qty in the unit the sale line used).
-- Stock goes back (tracked items) into the batch it came out of at the cost it left with; the value first reduces the customer's due
-- (rule sale_return_due_first), the rest is refunded in p_refund_mode.
create or replace function public.sale_return(p_client uuid, p_sale uuid, p_lines jsonb, p_reason text, p_note text default null,
  p_refund_mode text default null, p_wallet text default null, p_ref text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.sales; r public.sale_returns; it public.items; ln record; rid uuid := gen_random_uuid(); sq numeric; samt numeric; su text; pq numeric; price numeric; lamt numeric;
        gross numeric := 0; amt numeric; credit numeric := 0; refund numeric; bal numeric; fac numeric; out_lines jsonb := '[]'::jsonb; sid text;
        bq numeric; prior numeric; skip numeric; rem numeric; take numeric; o record; avail numeric; lid bigint;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'sale_not_found'; end if;
  if not public.can_loc(s.location_id) then raise exception 'not allowed for this location'; end if;
  if p_client is not null then
    select * into r from public.sale_returns where client_id = p_client;
    if found then
      if r.created_by is distinct from auth.uid() and not public.has_grant('sale_return', r.location_id) then raise exception 'client_id_taken'; end if;
      return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount);
    end if;
  end if;
  if p_reason is null or not exists (select 1 from public.option_lists where list_code = 'return_reasons' and value_code = p_reason and active) then raise exception 'reason_required'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'no_lines'; end if;
  if not (public.has_grant('sale_return', s.location_id) or public._use_em('sale_return', s.location_id, 'sale_return:' || p_sale::text, null)) then raise exception 'not allowed'; end if;
  perform 1 from public.sales where id = p_sale for update;                  -- one return at a time per sale
  select * into s from public.sales where id = p_sale;
  if s.status <> 'done' then raise exception 'sale_not_done'; end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  -- same item twice in p_lines is added up
  for ln in select e->>'item_id' iid, sum((e->>'qty')::numeric) q from jsonb_array_elements(p_lines) e group by 1 loop
    if ln.iid is null or ln.q is null or not (ln.q between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0), coalesce(sum((e->>'amount')::numeric), 0), max(e->>'unit')
      into sq, samt, su from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where e->>'item_id' = ln.iid;
    if sq <= 0 then raise exception 'line_not_in_sale'; end if;
    select coalesce(sum((e->>'qty')::numeric), 0) into pq from public.sale_returns x, jsonb_array_elements(x.lines) e where x.sale_id = s.id and x.status = 'done' and e->>'item_id' = ln.iid;
    if ln.q > sq - pq + 0.00005 then raise exception 'return_exceeds_sale'; end if;
    price := samt / sq; lamt := round(ln.q * price, 2); gross := gross + lamt;
    select * into it from public.items where id = ln.iid::uuid;
    out_lines := out_lines || jsonb_build_object('item_id', ln.iid, 'name', coalesce(it.name_bn, ''), 'unit', su, 'qty', ln.q, 'price', round(price, 4), 'amount', lamt);
  end loop;
  if not (gross between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  fac := case when s.subtotal > 0 then s.total / s.subtotal else 1 end;               -- the sale's discount is shared in proportion
  amt := round(gross * fac, 2);
  if not (amt between 0.01 and 999999999999) then raise exception 'bad_amount'; end if;
  if s.customer_id is not null and public.rule_on('sale_return_due_first') then
    bal := coalesce(public._cust_bal(s.customer_id), 0);
    credit := least(amt, greatest(bal, 0));
  end if;
  refund := amt - credit;
  if refund > 0 and (p_refund_mode is null or p_refund_mode not in ('cash', 'mobile', 'card')) then raise exception 'refund_mode_required'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  begin
    insert into public.sale_returns (id, client_id, sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, refund_mode, wallet, ref, reason_code, note, created_by, created_staff)
      values (rid, p_client, s.id, s.location_id, s.customer_id, out_lines, amt, credit, refund, case when refund > 0 then p_refund_mode end, left(nullif(p_wallet, ''), 30), left(nullif(p_ref, ''), 60), p_reason, left(nullif(btrim(p_note), ''), 300), auth.uid(), sid);
  exception when unique_violation then
    select * into r from public.sale_returns where p_client is not null and client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount); end if;
    raise;
  end;
  -- stock back (tracked items), batch aware
  for ln in select e->>'item_id' iid, (e->>'qty')::numeric q, e->>'unit' u from jsonb_array_elements(out_lines) e order by 1 loop
    select * into it from public.items where id = ln.iid::uuid;
    if it.tracked is not true then continue; end if;
    bq := public._base_qty(it.id, ln.q, ln.u);
    if bq is null then
      perform public._stock_exc(s.location_id, 'stock_unit_unknown', 'yellow', 'রসিদ ' || s.receipt || ': ' || it.name_bn || ' — এককের রূপান্তর জানা নেই, ফেরত মাল স্টকে ওঠেনি',
        'Receipt ' || s.receipt || ': ' || coalesce(it.name_en, it.name_bn) || ' — the unit conversion is unknown, the returned goods were NOT put back', s.id, s.sale_date, 'POS');
      continue;
    end if;
    rem := round(bq, 4);
    -- what earlier (live) returns of this sale already put back for this item
    select coalesce(sum(l.qty_delta), 0) into prior from public.stock_ledger l
      where l.item_id = it.id and l.ref_type = 'sale_return' and l.ref_id in (select x.id::text from public.sale_returns x where x.sale_id = s.id and x.id <> rid);
    skip := prior;
    for o in select * from public.stock_ledger x where x.ref_type = 'sale' and x.ref_id = s.id::text and x.reason = 'sale_out' and x.item_id = it.id
             and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id) order by x.id loop
      exit when rem <= 0;
      avail := -o.qty_delta;
      if skip >= avail then skip := skip - avail; continue; end if;
      avail := avail - skip; skip := 0;
      take := least(avail, rem);
      perform public.stock_post(it.id, s.location_id, take, 'sale_return', 'sale_return', rid::text, o.unit_cost, o.batch_id, now(), left('return of receipt ' || s.receipt, 200), null, 'none');
      rem := rem - take;
    end loop;
    if rem >= 0.0005 then            -- the sale took this out without a ledger row (stock tracking was switched on later): put it back as plain stock
      perform public.stock_post(it.id, s.location_id, rem, 'sale_return', 'sale_return', rid::text, null, null, now(), left('return of receipt ' || s.receipt, 200), null, 'none');
    end if;
  end loop;
  perform public._stock_exc(s.location_id, 'sale_return', 'yellow', 'রসিদ ' || s.receipt || ': বিক্রি ফেরত ' || amt::text, 'Receipt ' || s.receipt || ': a sale return of ' || amt::text, s.id, s.sale_date, 'POS', amt);
  return jsonb_build_object('id', rid, 'amount', amt, 'credit', credit, 'refund', refund);
end $$;

create or replace function public.void_sale_return(p_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.sale_returns; o public.stock_ledger;
begin
  if p_note is null or length(btrim(p_note)) = 0 then raise exception 'note_required'; end if;
  select * into r from public.sale_returns where id = p_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(r.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.has_grant('sale_return', r.location_id) or public._use_em('sale_return', r.location_id, 'void_return:' || p_id::text, r.amount)) then raise exception 'not allowed'; end if;
  if r.status = 'void' then return jsonb_build_object('dup', true, 'status', 'void'); end if;
  perform public.lock_check((now() at time zone 'Asia/Dhaka')::date);
  for o in select * from public.stock_ledger x where x.ref_type = 'sale_return' and x.ref_id = p_id::text and x.reason = 'sale_return'
           and not exists (select 1 from public.stock_ledger v where v.reverses_id = x.id) order by x.id loop
    perform public.stock_post(o.item_id, o.location_id, -o.qty_delta, 'reversal', 'sale_return', p_id::text, o.unit_cost, o.batch_id, now(), left('void: ' || btrim(p_note), 200), o.id, 'none');
  end loop;
  update public.sale_returns set status = 'void', void_by = auth.uid(), void_at = now(), void_note = left(btrim(p_note), 300) where id = p_id;
  perform public._stock_exc(r.location_id, 'sale_return_void', 'yellow', 'বিক্রি ফেরত বাতিল: ' || left(btrim(p_note), 100), 'A sale return was voided: ' || left(btrim(p_note), 100), r.sale_id, null, 'POS', r.amount);
  return jsonb_build_object('id', p_id, 'status', 'void');
end $$;

-- returns of one sale (for the sale's ⋮ menu) and what can still be returned per item
create or replace function public.sale_returns_for(p_sale uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.sales;
begin
  select * into s from public.sales where id = p_sale;
  if not found then raise exception 'not found'; end if;
  if not (public.is_active() and public.can_loc(s.location_id) and (public.can_do('POS', 'view') or public.can_do('POS', 'enter') or public.has_grant('sale_return', s.location_id))) then raise exception 'not allowed'; end if;
  return jsonb_build_object('sale_id', s.id, 'receipt', s.receipt, 'status', s.status, 'location_id', s.location_id, 'customer_id', s.customer_id, 'customer', s.customer,
    'factor', case when s.subtotal > 0 then round(s.total / s.subtotal, 8) else 1 end, 'due_first', public.rule_on('sale_return_due_first'),
    'balance', case when s.customer_id is not null then public._cust_bal(s.customer_id) end,
    'can_return', public.has_grant('sale_return', s.location_id) and s.status = 'done',
    'lines', coalesce((select jsonb_agg(jsonb_build_object('item_id', z.iid, 'name', z.nm, 'unit', z.u, 'sold', z.sq, 'returned', z.pq, 'left', z.sq - z.pq, 'price', round(z.samt / nullif(z.sq, 0), 4)) order by z.nm)
      from (select l.iid, max(l.nm) nm, max(l.u) u, sum(l.q) sq, sum(l.a) samt,
                   coalesce((select sum((x2->>'qty')::numeric) from public.sale_returns r2, jsonb_array_elements(r2.lines) x2 where r2.sale_id = s.id and r2.status = 'done' and x2->>'item_id' = l.iid), 0) pq
            from (select e->>'item_id' iid, e->>'name' nm, e->>'unit' u, (e->>'qty')::numeric q, (e->>'amount')::numeric a
                  from jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e where nullif(e->>'item_id', '') is not null) l
            group by l.iid) z), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'amount', r.amount, 'credit', r.credit_amount, 'refund', r.refund_amount, 'refund_mode', r.refund_mode,
      'reason', r.reason_code, 'note', r.note, 'status', r.status, 'at', r.created_at, 'staff', r.created_staff) order by r.created_at desc) from public.sale_returns r where r.sale_id = s.id), '[]'::jsonb));
end $$;

-- suppliers that owe US (advance paid, or credit from returns): where a refund can be recorded
create or replace function public.supplier_credits() returns table (supplier_id uuid, name text, mobile text, credit numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public._pur_ok(null) then raise exception 'not allowed'; end if;
  return query select z.id, z.name, z.mobile, -z.b from (select s.id, s.name, s.mobile, public._sup_balance(s.id) b from public.suppliers s) z where z.b < 0 order by 4 desc;
end $$;

-- ---------- privileges for everything new ----------
revoke all on function public._wastage_post(uuid, int, numeric, text, text, text, bigint, uuid, uuid, text), public._cust_bal(uuid), public._sale_void_guard(),
  public.wastage_decide(uuid, boolean, text), public.wastage_cancel(uuid), public.wastage_pending(int, text),
  public.supplier_refund(uuid, int, numeric, text, text, text, text, text, uuid), public.void_supplier_refund(bigint, text),
  public.sale_return(uuid, uuid, jsonb, text, text, text, text, text), public.void_sale_return(uuid, text), public.sale_returns_for(uuid), public.supplier_credits() from public, anon, authenticated;
grant execute on function public.wastage_decide(uuid, boolean, text), public.wastage_cancel(uuid), public.wastage_pending(int, text),
  public.supplier_refund(uuid, int, numeric, text, text, text, text, text, uuid), public.void_supplier_refund(bigint, text),
  public.sale_return(uuid, uuid, jsonb, text, text, text, text, text), public.void_sale_return(uuid, text), public.sale_returns_for(uuid), public.supplier_credits() to authenticated;
-- re-created functions keep their old grants (create or replace); make sure they are exactly as before
revoke all on function public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint), public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid),
  public._sup_balance(uuid), public._sup_open(uuid), public.supplier_ledger(uuid, int), public.customer_balance(uuid), public.customer_dues(), public.customer_ledger(uuid) from public, anon;
grant execute on function public.stock_wastage(uuid, int, numeric, text, text, text, text, uuid, bigint), public.supplier_ledger(uuid, int),
  public.customer_balance(uuid), public.customer_dues(), public.customer_ledger(uuid) to authenticated;
revoke all on function public.stock_post(uuid, int, numeric, text, text, text, numeric, bigint, timestamptz, text, bigint, text, uuid, uuid), public._sup_balance(uuid), public._sup_open(uuid) from authenticated;

notify pgrst, 'reload schema';
