-- Phase 430 (bos430) - RPT-B3 / R5a: SUPPLIER LOT AND EXPIRY CAPTURED AT THE RAW RECEIPT (audit item #83, data-capture gap 1).
-- Paste after phase99 (needs phase10 purchases and batches, phase60 grn_batch_links). Paste-twice safe. Earlier phase files are not edited and no shared function is re-created here:
-- the two places where a shared function must call this package are HOOKS (docs/integration/RPT-B3.md, tests/sql/rb3_hooks430.sql). Until the integrator pastes the hook, the screen
-- (web/purchase.js) calls receipt_lots_apply itself right after posting, so the feature works without it; only the server side "lot required" refusal needs the hook.
--
-- WHAT THIS ADDS
--   1. Table receipt_lots: the supplier's lot / batch number and expiry date typed on a purchase line (optional by default). Staged while the bill is a draft, applied (one stock batch
--      per lot, with batch_no and expiry) when the bill is posted. A line may have several lots (then each lot gives its own quantity). Stock that gets no lot stays "unbatched"
--      and is counted and printed by stock_unbatched (the lot reports never show a figure for it).
--   2. receipt_lots_stage(bill, lots), receipt_lots_get(bill), receipt_lots_apply(bill), receipt_lot_check(bill), stock_unbatched(loc, item).
--   3. Settings (rules): receipt_lot_required (OFF) and receipt_expiry_required (OFF). OFF = today's behaviour, nothing is refused. ON = a bill with tracked stock lines cannot be
--      posted until each such line has a lot number (and an expiry date when the second switch is ON). The check is _rb3_lot_gate, called by the hook in post_purchase.
--   4. Grants: none new. Writing needs purchase_entry at the bill's place (or the owner); reading needs the purchase, stock or quality report right or the same writing right.
-- The paper form code of this capture is NOT invented here: paper form code: to be given by owner. Until then the digital entry on the purchase line is the record.

do $g$ begin
  if to_regclass('public.grn_batch_links') is null or to_regclass('public.purchase_lines') is null then raise exception 'phase430 needs phase10 and phase60 first'; end if;
end $g$;

-- ---------- generic helper: exact-text patch of a LIVE function (marker = no-op on a second paste; a missing site stops everything) ----------
create or replace function public._rb3_patch(p_fn regprocedure, p_pairs text[], p_marker text) returns boolean language plpgsql set search_path = public as $$
declare def text := pg_get_functiondef(p_fn); i int;
begin
  if p_marker is null or length(p_marker) < 4 then raise exception 'marker_required'; end if;
  if position(p_marker in def) > 0 then return false; end if;
  for i in 1 .. array_length(p_pairs, 1) by 2 loop
    if position(p_pairs[i] in def) = 0 then raise exception 'patch site not found in %: %', p_fn::text, left(p_pairs[i], 90); end if;
    def := replace(def, p_pairs[i], p_pairs[i + 1]);
  end loop;
  if position(p_marker in def) = 0 then raise exception 'patch of % carries no marker %', p_fn::text, p_marker; end if;
  execute def;
  return true;
end $$;

-- ---------- settings ----------
insert into public.rules (key, module, kind, default_value, unit, choices, min_value, max_value, label_bn, label_mix, label_en, hint_en, sort) values
 ('receipt_lot_required', 'purchase', 'switch', 'false', null, null, null, null, 'ক্রয় বিলে স্টক লাইনে সাপ্লায়ারের লট নম্বর লাগবে', 'Purchase bill এর stock line এ supplier lot no লাগবে', 'A purchase bill needs the supplier lot number on every stock line before it can be posted', 'OFF by default: the lot is optional. Needs the hook in post_purchase to be refused on the server (the screen asks either way).', 130),
 ('receipt_expiry_required', 'purchase', 'switch', 'false', null, null, null, null, 'লটের সাথে মেয়াদের তারিখও লাগবে', 'Lot এর সাথে expiry date ও লাগবে', 'The lot also needs an expiry date (works together with the lot switch)', 'OFF by default', 131)
on conflict (key) do nothing;

-- ---------- table ----------
create table if not exists public.receipt_lots (
  id bigserial primary key,
  bill_id uuid not null references public.purchase_bills(id),
  line_no int not null,
  item_id uuid not null references public.items(id),
  supplier_id uuid not null references public.suppliers(id),
  location_id int not null references public.locations(id),
  lot_no text check (lot_no is null or length(btrim(lot_no)) between 1 and 40),
  expiry_date date,
  qty numeric check (qty is null or (qty > 0 and qty <= 1000000000000)),           -- in the unit written on the line; null = the whole line
  status text not null default 'staged' check (status in ('staged', 'applied', 'no_stock')),
  batch_id bigint,                                                                 -- the stock batch made when the bill was posted (no FK on purpose, like grn_batch_links)
  qty_base numeric,
  created_by uuid, created_at timestamptz not null default now(), applied_at timestamptz,
  check (lot_no is not null or expiry_date is not null)
);
create index if not exists receipt_lots_bill on public.receipt_lots (bill_id, line_no);
create index if not exists receipt_lots_batch on public.receipt_lots (batch_id) where batch_id is not null;
create index if not exists receipt_lots_item on public.receipt_lots (item_id, supplier_id);
drop trigger if exists audit_receipt_lots on public.receipt_lots;
create trigger audit_receipt_lots after insert or update or delete on public.receipt_lots for each row execute function public.log_change('id');
alter table public.receipt_lots enable row level security;
drop policy if exists receipt_lots_read on public.receipt_lots;
create policy receipt_lots_read on public.receipt_lots for select to authenticated using (public.can_loc(location_id));
revoke all on public.receipt_lots from public, anon, authenticated;
grant select on public.receipt_lots to authenticated;
revoke all on sequence public.receipt_lots_id_seq from public, anon, authenticated;

-- ---------- who may read / write ----------
create or replace function public._rb3_view_ok(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and public.can_loc(p_loc) and (public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public.rpt_access('purchase')
    or public.has_grant('purchase_entry', p_loc) or public.has_grant('grn_batch', p_loc));
$$;

-- the lines of a bill that take stock (tracked, not an asset, not a free-text line)
create or replace function public._rb3_stock_lines(p_bill uuid) returns table (line_no int, item_id uuid, code text, name_bn text, name_en text, qty numeric, unit text, base_qty numeric)
language sql stable security definer set search_path = public as $$
  select l.line_no, l.item_id, i.code, i.name_bn, i.name_en, l.qty, l.unit, l.base_qty
    from public.purchase_lines l join public.items i on i.id = l.item_id
   where l.bill_id = p_bill and i.tracked and coalesce(i.item_type, '') <> 'asset' order by l.line_no;
$$;

-- ---------- stage the lots of a DRAFT bill (replaces the staged rows of that bill; applied rows are never touched) ----------
-- p_lots: [{"line_no":1,"lot_no":"L-1","expiry":"2026-12-31","qty":50}]   (qty optional = the whole line)
create or replace function public.receipt_lots_stage(p_bill uuid, p_lots jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; x jsonb; ln record; lot text; ex date; q numeric; n int := 0; today date := (now() at time zone 'Asia/Dhaka')::date; seen jsonb := '{}'::jsonb; sumq numeric;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select * into pb from public.purchase_bills where id = p_bill for update;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('purchase_entry', pb.location_id)) then raise exception 'not allowed'; end if;
  if pb.kind <> 'bill' then raise exception 'lots_only_on_bills'; end if;
  if pb.status <> 'draft' then raise exception 'not_draft'; end if;
  if p_lots is null or jsonb_typeof(p_lots) <> 'array' or jsonb_array_length(p_lots) > 200 then raise exception 'bad_lots'; end if;
  delete from public.receipt_lots where bill_id = p_bill and status = 'staged';
  for x in select * from jsonb_array_elements(p_lots) loop
    if jsonb_typeof(x) <> 'object' then raise exception 'bad_lots'; end if;
    lot := nullif(btrim(x ->> 'lot_no'), ''); ex := nullif(x ->> 'expiry', '')::date;
    q := nullif(x ->> 'qty', '')::numeric;
    if lot is null and ex is null and q is null then continue; end if;
    if lot is null and ex is null then raise exception 'lot_or_expiry_needed'; end if;
    if lot is not null and length(lot) > 40 then raise exception 'bad_lot_no'; end if;
    if ex is not null and (ex < pb.bill_date or ex > today + 3650) then raise exception 'bad_expiry'; end if;
    if q is not null and not (q between 0.0001 and 999999999) then raise exception 'bad_qty'; end if;
    select * into ln from public._rb3_stock_lines(p_bill) l where l.line_no = (x ->> 'line_no')::int;
    if not found then raise exception 'line_not_stock'; end if;
    insert into public.receipt_lots (bill_id, line_no, item_id, supplier_id, location_id, lot_no, expiry_date, qty, created_by)
      values (p_bill, ln.line_no, ln.item_id, pb.supplier_id, pb.location_id, lot, ex, q, auth.uid());
    n := n + 1;
  end loop;
  -- several lots on one line: each needs its own quantity and together they cannot exceed the line
  for ln in select l.line_no, count(*) as c, count(*) filter (where r.qty is null) as nq, sum(r.qty) as sq from public.receipt_lots r join public.purchase_lines l on l.bill_id = r.bill_id and l.line_no = r.line_no
             where r.bill_id = p_bill and r.status = 'staged' group by l.line_no loop
    if ln.c > 1 and ln.nq > 0 then raise exception 'qty_needed_for_each_lot'; end if;
    select qty into sumq from public.purchase_lines where bill_id = p_bill and line_no = ln.line_no;
    if ln.sq is not null and ln.sq > sumq + 0.00005 then raise exception 'lots_exceed_line'; end if;
  end loop;
  return jsonb_build_object('staged', n);
end $$;

-- ---------- read the lots of a bill (staged and applied) ----------
create or replace function public.receipt_lots_get(p_bill uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pb public.purchase_bills;
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._rb3_view_ok(pb.location_id) then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'line_no', r.line_no, 'item_id', r.item_id, 'lot_no', r.lot_no, 'expiry', r.expiry_date, 'qty', r.qty, 'status', r.status,
    'batch_id', r.batch_id, 'qty_base', r.qty_base) order by r.line_no, r.id) from public.receipt_lots r where r.bill_id = p_bill), '[]'::jsonb);
end $$;

-- ---------- what is missing for the "required" switches (also used by the server gate) ----------
create or replace function public.receipt_lot_check(p_bill uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; miss jsonb := '[]'::jsonb; needlot boolean := public.rule_on('receipt_lot_required'); needexp boolean := public.rule_on('receipt_expiry_required');
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public._rb3_view_ok(pb.location_id) then raise exception 'not allowed'; end if;
  if pb.kind = 'bill' then
    for ln in select * from public._rb3_stock_lines(p_bill) loop
      if (needlot and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.lot_no is not null))
         or (needexp and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.expiry_date is not null)) then
        miss := miss || jsonb_build_object('line_no', ln.line_no, 'code', ln.code, 'name_bn', ln.name_bn, 'name_en', ln.name_en,
          'lot_missing', needlot and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.lot_no is not null),
          'expiry_missing', needexp and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.expiry_date is not null));
      end if;
    end loop;
  end if;
  return jsonb_build_object('lot_required', needlot, 'expiry_required', needexp, 'missing', miss);
end $$;

-- the refusal itself (called by the hook at the start of post_purchase; harmless when both switches are OFF)
create or replace function public._rb3_lot_gate(p_bill uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; ln record; needlot boolean := public.rule_on('receipt_lot_required'); needexp boolean := public.rule_on('receipt_expiry_required');
begin
  if not (needlot or needexp) then return; end if;
  select * into pb from public.purchase_bills where id = p_bill;
  if not found or pb.kind <> 'bill' or pb.status <> 'draft' then return; end if;
  for ln in select * from public._rb3_stock_lines(p_bill) loop
    if needlot and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.lot_no is not null) then
      raise exception 'lot_required' using detail = ln.code, hint = 'line ' || ln.line_no::text;
    end if;
    if needexp and not exists (select 1 from public.receipt_lots r where r.bill_id = p_bill and r.line_no = ln.line_no and r.expiry_date is not null) then
      raise exception 'expiry_required' using detail = ln.code, hint = 'line ' || ln.line_no::text;
    end if;
  end loop;
end $$;

-- ---------- apply the staged lots of a POSTED bill: one stock batch per lot (internal core, no permission check: the callers did it) ----------
create or replace function public._rb3_lot_apply(p_bill uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills; r public.receipt_lots; ln public.purchase_lines; f numeric; bq numeric; free numeric; done_line numeric; viaGrn numeric; bid bigint;
        applied int := 0; nostock int := 0; ids bigint[] := '{}';
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found or pb.kind <> 'bill' or pb.status <> 'posted' then return jsonb_build_object('applied', 0, 'no_stock', 0, 'batches', '[]'::jsonb, 'not_posted', true); end if;
  for r in select * from public.receipt_lots where bill_id = p_bill and status = 'staged' order by line_no, id for update loop
    select * into ln from public.purchase_lines where bill_id = p_bill and line_no = r.line_no;
    if not found or ln.base_qty is null then continue; end if;
    f := public._unit_factor_base(ln.item_id, ln.unit);
    bq := case when r.qty is null then ln.base_qty else r.qty * coalesce(ln.base_qty / nullif(ln.qty, 0), f) end;
    select coalesce(sum(x.qty_base), 0) into done_line from public.receipt_lots x where x.bill_id = p_bill and x.line_no = r.line_no and x.status = 'applied';
    select coalesce(sum(g.qty_base), 0) into viaGrn from public.grn_batch_links g where g.source_type = 'purchase' and g.source_id = p_bill and g.item_id = ln.item_id;
    bq := round(least(bq, ln.base_qty - done_line - viaGrn), 4);
    insert into public.stock_balance (item_id, location_id) values (r.item_id, r.location_id) on conflict do nothing;
    select b.qty - coalesce((select sum(sb.qty_remaining) from public.stock_batches sb where sb.item_id = r.item_id and sb.location_id = r.location_id and sb.qty_remaining > 0), 0) into free
      from public.stock_balance b where b.item_id = r.item_id and b.location_id = r.location_id for update;
    bq := round(least(bq, free), 4);
    if bq < 0.0001 then
      update public.receipt_lots set status = 'no_stock', applied_at = now() where id = r.id;
      nostock := nostock + 1; continue;
    end if;
    insert into public.stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, shelf_rule, note, created_by, batch_no)
      values (r.item_id, r.location_id, pb.bill_date::timestamp at time zone 'Asia/Dhaka', bq, bq,
              case when r.expiry_date is null then null else (r.expiry_date::timestamp + interval '23 hours 59 minutes') at time zone 'Asia/Dhaka' end,
              jsonb_build_object('source', 'receipt_lot', 'bill_id', p_bill, 'supplier_id', pb.supplier_id), left('Receipt lot ' || coalesce(r.lot_no, ''), 200), auth.uid(), r.lot_no)
      returning id into bid;
    update public.receipt_lots set status = 'applied', batch_id = bid, qty_base = bq, applied_at = now() where id = r.id;
    if r.lot_no is not null and r.expiry_date is not null then       -- the same link the paper-GRN batch uses, so a quality hold on this receipt reaches the batch
      insert into public.grn_batch_links (batch_id, source_type, source_id, item_id, location_id, batch_no, expiry_date, qty_base, created_by)
        values (bid, 'purchase', p_bill, r.item_id, r.location_id, r.lot_no, r.expiry_date, bq, auth.uid()) on conflict do nothing;
    end if;
    applied := applied + 1; ids := ids || bid;
  end loop;
  return jsonb_build_object('applied', applied, 'no_stock', nostock, 'batches', to_jsonb(ids));
end $$;

-- the public call (the screen calls it right after posting; idempotent, a second call applies nothing)
create or replace function public.receipt_lots_apply(p_bill uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pb public.purchase_bills;
begin
  select * into pb from public.purchase_bills where id = p_bill;
  if not found then raise exception 'not found'; end if;
  if not public.can_loc(pb.location_id) then raise exception 'not allowed for this location'; end if;
  if not (public.is_owner() or public.has_grant('purchase_entry', pb.location_id) or public.has_grant('grn_batch', pb.location_id)) then raise exception 'not allowed'; end if;
  if pb.status <> 'posted' then raise exception 'not_posted'; end if;
  return public._rb3_lot_apply(p_bill);
end $$;

-- ---------- unbatched stock: on hand minus what sits in open batches (quantities only, never a cost) ----------
create or replace function public.stock_unbatched(p_loc int default null, p_item uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out_ jsonb;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', x.item_id, 'code', x.code, 'name_bn', x.name_bn, 'name_en', x.name_en, 'location_id', x.location_id, 'base_unit', x.base_unit,
      'on_hand', x.qty, 'in_batches', x.inb, 'unbatched', case when x.qty - x.inb > 0.0005 then round(x.qty - x.inb, 4) else 0 end, 'negative', x.qty < 0) order by x.code, x.location_id), '[]'::jsonb) into out_
    from (select b.item_id, i.code, i.name_bn, i.name_en, b.location_id, public._item_base(b.item_id) as base_unit, b.qty,
                 coalesce((select sum(sb.qty_remaining) from public.stock_batches sb where sb.item_id = b.item_id and sb.location_id = b.location_id and sb.qty_remaining > 0), 0) as inb
            from public.stock_balance b join public.items i on i.id = b.item_id
           where i.tracked and public.can_loc(b.location_id) and (p_loc is null or b.location_id = p_loc) and (p_item is null or b.item_id = p_item) and b.qty <> 0) x;
  return out_;
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('_rb3_patch', '_rb3_view_ok', '_rb3_stock_lines', '_rb3_lot_gate', '_rb3_lot_apply') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('receipt_lots_stage', 'receipt_lots_get', 'receipt_lot_check', 'receipt_lots_apply', 'stock_unbatched') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
