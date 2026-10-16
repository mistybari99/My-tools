-- Phase 431 (bos431) - RPT-B3 / R5b: TRACEABILITY AND RECALL (audit items #83 and #85).
-- Paste after phase430. Paste-twice safe. Earlier phase files are not edited; no shared function is re-created.
--
-- WHAT THIS ADDS
--   1. trace_batch(batch, dir)        raw material lot -> finished batch -> transfers -> outlets / customers (sales), and back from a finished batch to the raw lots it was made from.
--                                     Built only from records that already exist (stock_ledger batch_id, production_runs, stock_transfers, sales, receipt_lots, grn_batch_links).
--   2. trace_batch_find(...)          find a batch by lot number, item, place.
--   3. recall_cases, recall_batches   a recall case (digital entry, paper form code: to be given by owner) with the batches under recall and what was done with each.
--      recall_open / recall_add_batch / recall_batch_mark / recall_close / recall_list
--   4. recall_affected(case)          the affected-stock report: every batch reached from the recalled ones, what is still in stock where, what was sold at which outlet, to which
--                                     named customers, what is in transit, and the UNBATCHED quantity of the same items (stock that cannot be shown to be free of the lot), and
--                                     receipts of the same item and supplier that have no lot recorded.
-- Nothing here moves stock or money. Holding, removing or writing off recalled stock is done with the existing wastage / return screens; the case only records what was done.
-- Reading: the owner or a holder of the stock or quality report right (rpt_access). Writing a case: the owner or the new grant recall_manage. A person sees only the places they may see
-- (management and the owner see all); anything hidden is counted in the answer (hidden_places), never silently dropped. Customer mobile numbers are never returned.
-- Missing data is said, never shown as 0: a batch with no recorded origin says "origin not captured"; unlotted receipts and unbatched quantities are listed as such.

do $g$ begin
  if to_regprocedure('public._rb3_view_ok(int)') is null then raise exception 'phase431 needs phase430 first'; end if;
end $g$;

-- ---------- grant ----------
with ins as (
  insert into public.grant_defs (grant_code, module, sort, label_bn, label_mix, label_en, window_type, emergency_rule) values
   ('recall_manage', 'stock', 49, 'রিকল কেস খোলা ও চালানো', 'Recall case খোলা ও চালানো', 'Open and run a recall case', 'once', null)
  on conflict (grant_code) do nothing returning grant_code)
insert into public.rule_grants (grant_code, role_code)
  select s.g, s.r from (values ('recall_manage', 'management'), ('recall_manage', 'factory_incharge'), ('recall_manage', 'storekeeper')) s(g, r)
  join ins on ins.grant_code = s.g
  where exists (select 1 from public.roles ro where ro.code = s.r)
  on conflict do nothing;

-- ---------- tables ----------
create sequence if not exists public.recall_case_no_seq;
create table if not exists public.recall_cases (
  id uuid primary key default gen_random_uuid(),
  case_no bigint not null default nextval('public.recall_case_no_seq') unique,
  client_id uuid unique,
  title text not null check (length(btrim(title)) between 3 and 120),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  hazard text check (hazard is null or length(hazard) <= 300),
  status text not null default 'open' check (status in ('open', 'closed')),
  opened_by uuid, opened_staff text, opened_at timestamptz not null default now(),
  closed_by uuid, closed_staff text, closed_at timestamptz, close_note text check (close_note is null or length(close_note) <= 500)
);
create table if not exists public.recall_batches (
  id bigserial primary key,
  case_id uuid not null references public.recall_cases(id),
  batch_id bigint not null references public.stock_batches(id),
  added_by uuid, added_at timestamptz not null default now(), note text check (note is null or length(note) <= 300),
  action_status text not null default 'to_do' check (action_status in ('to_do', 'removed_from_shelf', 'returned_to_supplier', 'written_off', 'not_found', 'nothing_left')),
  action_by uuid, action_at timestamptz, action_note text check (action_note is null or length(action_note) <= 300),
  unique (case_id, batch_id)
);
create index if not exists recall_batches_batch on public.recall_batches (batch_id);
drop trigger if exists audit_recall_cases on public.recall_cases;
create trigger audit_recall_cases after insert or update on public.recall_cases for each row execute function public.log_change('id');
drop trigger if exists audit_recall_batches on public.recall_batches;
create trigger audit_recall_batches after insert or update on public.recall_batches for each row execute function public.log_change('id');
alter table public.recall_cases enable row level security;
alter table public.recall_batches enable row level security;
-- no direct browser access: the tables are read only through the functions below (they check rpt_access / recall_manage themselves)
revoke all on public.recall_cases, public.recall_batches from public, anon, authenticated;
revoke all on sequence public.recall_case_no_seq, public.recall_batches_id_seq from public, anon, authenticated;

-- ---------- access ----------
create or replace function public._rb3_trace_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.rpt_access('stock') or public.rpt_access('quality') or public.has_grant('recall_manage'));
$$;
create or replace function public._rb3_loc_vis(p_loc int) returns boolean language sql stable security definer set search_path = public as $$
  select public._all_locs() or public.can_loc(p_loc);
$$;

-- ---------- where a batch came from ----------
create or replace function public._rb3_origin(p_batch bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.stock_batches; r record; run record; g record; tin record; tout record;
begin
  select * into b from public.stock_batches where id = p_batch;
  if not found then return null; end if;
  select rl.lot_no, rl.expiry_date, rl.bill_id, pb.bill_no, pb.bill_date, pb.supplier_id, s.name as supplier into r
    from public.receipt_lots rl join public.purchase_bills pb on pb.id = rl.bill_id join public.suppliers s on s.id = pb.supplier_id where rl.batch_id = p_batch limit 1;
  if found then
    return jsonb_build_object('type', 'receipt', 'supplier_id', r.supplier_id, 'supplier', r.supplier, 'bill_id', r.bill_id, 'bill_no', r.bill_no, 'bill_date', r.bill_date, 'lot_no', r.lot_no, 'expiry', r.expiry_date);
  end if;
  select l.source_type, l.source_id, l.batch_no, l.expiry_date into g from public.grn_batch_links l where l.batch_id = p_batch;
  if found then
    if g.source_type = 'purchase' then
      select pb.bill_no, pb.bill_date, pb.supplier_id, s.name as supplier into r from public.purchase_bills pb join public.suppliers s on s.id = pb.supplier_id where pb.id = g.source_id;
      return jsonb_build_object('type', 'receipt', 'supplier_id', r.supplier_id, 'supplier', r.supplier, 'bill_id', g.source_id, 'bill_no', r.bill_no, 'bill_date', r.bill_date, 'lot_no', g.batch_no, 'expiry', g.expiry_date);
    end if;
    return jsonb_build_object('type', 'grn_form', 'entry_id', g.source_id, 'lot_no', g.batch_no, 'expiry', g.expiry_date,
      'supplier', (select btrim(coalesce(s.name, e.data ->> 'supplier')) from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id' where e.id = g.source_id));
  end if;
  select pr.id, pr.made_at, pr.item_id into run from public.production_runs pr where pr.batch_id = p_batch;
  if found then return jsonb_build_object('type', 'production', 'run_id', run.id, 'made_at', run.made_at); end if;
  select l.ref_id into tin from public.stock_ledger l where l.batch_id = p_batch and l.reason = 'transfer_in' and l.ref_type = 'transfer' order by l.id limit 1;
  if found then
    select l.batch_id, l.location_id into tout from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = tin.ref_id and l.reason = 'transfer_out' and l.batch_id is not null order by l.id limit 1;
    return jsonb_build_object('type', 'transfer', 'transfer_id', tin.ref_id, 'source_batch_id', tout.batch_id, 'from_location_id', tout.location_id);
  end if;
  return jsonb_build_object('type', 'unknown', 'lot_no', b.batch_no);
end $$;

-- follow transfers back to the batch that really was made or received (max 10 hops)
create or replace function public._rb3_root(p_batch bigint) returns bigint
language plpgsql stable security definer set search_path = public as $$
declare cur bigint := p_batch; o jsonb; n int := 0;
begin
  loop
    o := public._rb3_origin(cur);
    exit when o is null or o ->> 'type' <> 'transfer' or (o ->> 'source_batch_id') is null or n >= 10;
    cur := (o ->> 'source_batch_id')::bigint; n := n + 1;
  end loop;
  return cur;
end $$;

-- a one-line description of a batch
create or replace function public._rb3_batch_row(p_batch bigint) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('batch_id', b.id, 'item_id', b.item_id, 'code', i.code, 'name_bn', i.name_bn, 'name_en', i.name_en, 'location_id', b.location_id, 'location', l.name_bn, 'location_en', l.name_en,
    'made_at', b.made_at, 'expires_at', b.expires_at, 'qty_made', b.qty_made, 'qty_remaining', b.qty_remaining, 'lot_no', b.batch_no, 'base_unit', public._item_base(b.item_id), 'origin', public._rb3_origin(b.id))
    from public.stock_batches b join public.items i on i.id = b.item_id join public.locations l on l.id = b.location_id where b.id = p_batch;
$$;

-- ---------- forward trace of one or more start batches (the shared core of trace_batch and recall_affected) ----------
create or replace function public._rb3_forward(p_start bigint[]) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  queue bigint[] := p_start; seen bigint[] := '{}'; x bigint; xb public.stock_batches; s record; t record; w record; rel jsonb := '{}'::jsonb; reached jsonb := '[]'::jsonb;
  sales_ jsonb := '[]'::jsonb; tr jsonb := '[]'::jsonb; made jsonb := '[]'::jsonb; waste jsonb := '[]'::jsonb; manual jsonb := '[]'::jsonb; hidden int := 0; sales_total int := 0; sale_cap constant int := 500;
  nb bigint; rid text; run_batch bigint; row_ jsonb; tt public.stock_transfers; sent numeric;
begin
  select coalesce(array_agg(distinct u), '{}') into queue from unnest(p_start) u;
  for x in select unnest(queue) loop rel := rel || jsonb_build_object(x::text, 'start'); end loop;
  while coalesce(array_length(queue, 1), 0) > 0 and coalesce(array_length(seen, 1), 0) < 300 loop
    x := queue[1]; queue := queue[2:array_length(queue, 1)];
    if x = any (seen) then continue; end if;
    seen := seen || x;
    select * into xb from public.stock_batches where id = x;
    if not found then continue; end if;
    if not public._rb3_loc_vis(xb.location_id) then hidden := hidden + 1; continue; end if;
    row_ := public._rb3_batch_row(x) || jsonb_build_object('relation', coalesce(rel ->> x::text, 'reached'));
    reached := reached || row_;
    -- sales (net of voids and returns)
    for s in
      select q.sref, sum(q.q) as net, sum(q.q) filter (where q.kind = 'out') as gross
        from (select sl.ref_id as sref, -sl.qty_delta as q, 'out' as kind from public.stock_ledger sl where sl.batch_id = x and sl.reason = 'sale_out' and sl.ref_type = 'sale'
              union all select sl.ref_id, sl.qty_delta * -1, 'void' from public.stock_ledger sl where sl.batch_id = x and sl.reason = 'sale_void_in' and sl.ref_type = 'sale'
              union all select sr.sale_id::text, sl.qty_delta * -1, 'ret' from public.stock_ledger sl join public.sale_returns sr on sr.id::text = sl.ref_id
                         where sl.batch_id = x and sl.ref_type = 'sale_return' and sl.reason in ('sale_return', 'reversal')) q
       group by q.sref loop
      if s.net is null or s.net < 0.0005 then continue; end if;
      select sa.id, sa.receipt, sa.sale_date, sa.location_id, sa.customer, sa.customer_id, sa.status, l.name_bn as place into t
        from public.sales sa join public.locations l on l.id = sa.location_id where sa.id::text = s.sref;
      if not found then continue; end if;
      if not public._rb3_loc_vis(t.location_id) then hidden := hidden + 1; continue; end if;
      sales_total := sales_total + 1;
      if jsonb_array_length(sales_) < sale_cap then
        sales_ := sales_ || jsonb_build_object('sale_id', t.id, 'receipt', t.receipt, 'sale_date', t.sale_date, 'location_id', t.location_id, 'location', t.place, 'customer', nullif(btrim(t.customer), ''),
          'customer_id', t.customer_id, 'qty', round(s.net, 4), 'batch_id', x, 'item_id', xb.item_id, 'code', row_ ->> 'code');
      end if;
    end loop;
    -- used in production: the run's finished batch is reached
    for s in select l.ref_id as run_id, sum(-l.qty_delta) as qty from public.stock_ledger l where l.batch_id = x and l.reason = 'issue_out' and l.ref_type = 'production' group by l.ref_id loop
      select pr.batch_id into run_batch from public.production_runs pr where pr.id::text = s.run_id and pr.status = 'done';
      made := made || jsonb_build_object('run_id', s.run_id, 'from_batch_id', x, 'qty', round(s.qty, 4), 'to_batch_id', run_batch);
      if run_batch is not null and not (run_batch = any (seen)) and not (run_batch = any (queue)) then
        queue := queue || run_batch; rel := rel || jsonb_build_object(run_batch::text, 'made_from');
      end if;
    end loop;
    -- issued by hand (no production run): the destination is not recorded
    select coalesce(sum(-l.qty_delta), 0) into sent from public.stock_ledger l where l.batch_id = x and l.reason = 'issue_out' and coalesce(l.ref_type, '') <> 'production';
    if sent > 0 then manual := manual || jsonb_build_object('batch_id', x, 'qty', round(sent, 4)); end if;
    -- transfers
    for s in select l.ref_id as tid, sum(case when l.reason = 'transfer_out' then -l.qty_delta else l.qty_delta end) as qty from public.stock_ledger l
              where l.batch_id = x and l.ref_type = 'transfer' and l.reason in ('transfer_out', 'reversal') group by l.ref_id loop
      if s.qty < 0.0005 then continue; end if;
      select * into tt from public.stock_transfers where id::text = s.tid;
      tr := tr || jsonb_build_object('transfer_id', s.tid, 'from_batch_id', x, 'qty_sent', round(s.qty, 4), 'from_location_id', xb.location_id, 'to_location_id', tt.to_location_id,
        'status', tt.status, 'received_qty', tt.received_qty, 'sent_at', tt.sent_at, 'received_at', tt.received_at);
      for w in select l.batch_id as nb2 from public.stock_ledger l where l.ref_type = 'transfer' and l.ref_id = s.tid and l.reason = 'transfer_in' and l.batch_id is not null loop
        nb := w.nb2;
        if not (nb = any (seen)) and not (nb = any (queue)) then queue := queue || nb; rel := rel || jsonb_build_object(nb::text, 'transferred'); end if;
      end loop;
    end loop;
    -- written off / taken out in other ways
    for w in select l.reason, sum(-l.qty_delta) as qty from public.stock_ledger l where l.batch_id = x and l.reason in ('wastage', 'purchase_return', 'count_adjust') and l.qty_delta < 0 group by l.reason loop
      waste := waste || jsonb_build_object('batch_id', x, 'reason', w.reason, 'qty', round(w.qty, 4));
    end loop;
  end loop;
  return jsonb_build_object('batches', reached, 'sales', sales_, 'sales_total', sales_total, 'sales_truncated', sales_total > sale_cap, 'made_into', made, 'transfers', tr,
    'taken_out', waste, 'issued_without_run', manual, 'hidden_places', hidden, 'batches_truncated', coalesce(array_length(queue, 1), 0) > 0);
end $$;

-- ---------- summaries shared by trace and recall: by place, unbatched quantity ----------
create or replace function public._rb3_summary(p_fwd jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare by_loc jsonb; unb jsonb := '[]'::jsonb; u jsonb; it record; named int; walk int;
begin
  select coalesce(jsonb_agg(jsonb_build_object('location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'on_hand', z.on_hand, 'sold', z.sold, 'sales_n', z.sales_n,
      'in_transit', z.transit) order by l.name_bn), '[]'::jsonb) into by_loc
    from (select loc, sum(on_hand) as on_hand, sum(sold) as sold, sum(sales_n) as sales_n, sum(transit) as transit from (
            select (b ->> 'location_id')::int as loc, (b ->> 'qty_remaining')::numeric as on_hand, 0::numeric as sold, 0 as sales_n, 0::numeric as transit from jsonb_array_elements(p_fwd -> 'batches') b
            union all select (s ->> 'location_id')::int, 0, (s ->> 'qty')::numeric, 1, 0 from jsonb_array_elements(p_fwd -> 'sales') s
            union all select (t ->> 'to_location_id')::int, 0, 0, 0, (t ->> 'qty_sent')::numeric from jsonb_array_elements(p_fwd -> 'transfers') t where t ->> 'status' = 'sent') u2
          where loc is not null group by loc) z join public.locations l on l.id = z.loc;
  for it in select distinct (b ->> 'item_id')::uuid as item_id, (b ->> 'location_id')::int as loc from jsonb_array_elements(p_fwd -> 'batches') b loop
    for u in select * from jsonb_array_elements(public.stock_unbatched(it.loc, it.item_id)) loop
      if (u ->> 'unbatched')::numeric > 0 or (u ->> 'negative')::boolean then unb := unb || u; end if;
    end loop;
  end loop;
  select count(distinct s ->> 'customer'), count(*) filter (where s ->> 'customer' is null) into named, walk from jsonb_array_elements(p_fwd -> 'sales') s;
  return jsonb_build_object('by_place', by_loc, 'unbatched', unb, 'named_customers', named, 'sales_without_customer', walk);
end $$;

-- ---------- the trace of one batch ----------
-- dir: 'fwd' (where it went), 'back' (what it was made from), 'both'
create or replace function public.trace_batch(p_batch bigint, p_dir text default 'both') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b public.stock_batches; dir text := coalesce(p_dir, 'both'); fwd jsonb; back jsonb := null; run record; inputs jsonb := '[]'::jsonb; unb jsonb := '[]'::jsonb; ib record;
        root bigint; warn jsonb := '[]'::jsonb;
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  if dir not in ('fwd', 'back', 'both') then raise exception 'bad_dir'; end if;
  select * into b from public.stock_batches where id = p_batch;
  if not found then raise exception 'batch_not_found'; end if;
  if not public._rb3_loc_vis(b.location_id) then raise exception 'not allowed for this location'; end if;
  if dir in ('back', 'both') then
    root := public._rb3_root(p_batch);
    select pr.id, pr.made_at, pr.item_id into run from public.production_runs pr where pr.batch_id = root;
    if found then
      for ib in select l.batch_id, l.item_id, sum(-l.qty_delta) as qty from public.stock_ledger l where l.ref_type = 'production' and l.ref_id = run.id::text and l.reason = 'issue_out' group by l.batch_id, l.item_id loop
        if ib.batch_id is null then
          unb := unb || jsonb_build_object('item_id', ib.item_id, 'code', (select code from public.items where id = ib.item_id), 'name_bn', (select name_bn from public.items where id = ib.item_id),
            'qty', round(ib.qty, 4), 'note', 'unbatched');
        else
          inputs := inputs || (public._rb3_batch_row(ib.batch_id) || jsonb_build_object('qty_used', round(ib.qty, 4), 'root_origin', public._rb3_origin(public._rb3_root(ib.batch_id))));
        end if;
      end loop;
    end if;
    back := jsonb_build_object('root_batch_id', root, 'run_id', run.id, 'inputs', inputs, 'unbatched_inputs', unb);
  end if;
  if dir in ('fwd', 'both') then
    fwd := public._rb3_forward(array[p_batch]);
    fwd := fwd || jsonb_build_object('summary', public._rb3_summary(fwd));
  end if;
  if (public._rb3_origin(p_batch) ->> 'type') = 'unknown' then warn := warn || '"origin_not_captured"'::jsonb; end if;
  return jsonb_build_object('batch', public._rb3_batch_row(p_batch), 'back', back, 'forward', fwd, 'warnings', warn);
end $$;

-- find a batch: by lot number text, item, place; only batches with stock left unless p_all
create or replace function public.trace_batch_find(p_q text default null, p_item uuid default null, p_loc int default null, p_all boolean default false, p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare q text := nullif(btrim(p_q), ''); lim int := least(greatest(coalesce(p_limit, 100), 1), 300);
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  if q is not null and length(q) > 60 then raise exception 'bad_query'; end if;
  return coalesce((select jsonb_agg(public._rb3_batch_row(x.id) order by x.made_at desc, x.id desc) from (
      select b.id, b.made_at from public.stock_batches b join public.items i on i.id = b.item_id
       where public._rb3_loc_vis(b.location_id) and (p_loc is null or b.location_id = p_loc) and (p_item is null or b.item_id = p_item)
         and (coalesce(p_all, false) or b.qty_remaining > 0)
         and (q is null or b.batch_no ilike '%' || replace(replace(q, '%', ''), '_', '') || '%' or i.code ilike '%' || replace(replace(q, '%', ''), '_', '') || '%'
              or i.name_bn ilike '%' || replace(replace(q, '%', ''), '_', '') || '%' or coalesce(i.name_en, '') ilike '%' || replace(replace(q, '%', ''), '_', '') || '%' or b.id::text = q)
       order by b.made_at desc, b.id desc limit lim) x), '[]'::jsonb);
end $$;

-- ---------- recall cases ----------
create or replace function public._rb3_recall_ok() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.has_grant('recall_manage'));
$$;

create or replace function public.recall_open(p_title text, p_reason text, p_hazard text default null, p_batches bigint[] default '{}', p_client uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cid uuid; prev public.recall_cases; sid text; bid bigint; loc int; n int := 0; tt text := btrim(coalesce(p_title, '')); rr text := btrim(coalesce(p_reason, ''));
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  perform public._client_lock(p_client);
  if p_client is not null then
    select * into prev from public.recall_cases where client_id = p_client;
    if found then return jsonb_build_object('dup', true, 'id', prev.id, 'case_no', prev.case_no); end if;
  end if;
  if length(tt) < 3 or length(tt) > 120 then raise exception 'bad_title'; end if;
  if length(rr) < 3 or length(rr) > 500 then raise exception 'reason_required'; end if;
  if length(coalesce(p_hazard, '')) > 300 then raise exception 'bad_hazard'; end if;
  if coalesce(array_length(p_batches, 1), 0) > 100 then raise exception 'too_many_batches'; end if;
  select staff_id into sid from public.profiles where id = auth.uid();
  insert into public.recall_cases (client_id, title, reason, hazard, opened_by, opened_staff) values (p_client, tt, rr, nullif(btrim(p_hazard), ''), auth.uid(), sid) returning id into cid;
  foreach bid in array coalesce(p_batches, '{}') loop
    select location_id into loc from public.stock_batches where id = bid;
    if loc is null then raise exception 'batch_not_found'; end if;
    insert into public.recall_batches (case_id, batch_id, added_by) values (cid, bid, auth.uid()) on conflict do nothing;
    n := n + 1;
  end loop;
  select b.location_id into loc from public.recall_batches rb join public.stock_batches b on b.id = rb.batch_id where rb.case_id = cid order by rb.id limit 1;
  if loc is not null then
    perform public._stock_exc(loc, 'recall_opened', 'red', 'রিকল কেস খোলা হয়েছে: ' || left(tt, 80), 'A recall case was opened: ' || left(tt, 80));
  end if;
  return jsonb_build_object('id', cid, 'case_no', (select case_no from public.recall_cases where id = cid), 'batches', n);
end $$;

create or replace function public.recall_add_batch(p_case uuid, p_batch bigint, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.recall_cases;
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case for update;
  if not found then raise exception 'not found'; end if;
  if c.status <> 'open' then raise exception 'case_closed'; end if;
  if not exists (select 1 from public.stock_batches where id = p_batch) then raise exception 'batch_not_found'; end if;
  if length(coalesce(p_note, '')) > 300 then raise exception 'bad_note'; end if;
  insert into public.recall_batches (case_id, batch_id, added_by, note) values (p_case, p_batch, auth.uid(), nullif(btrim(p_note), '')) on conflict do nothing;
  return jsonb_build_object('case_id', p_case, 'batch_id', p_batch);
end $$;

-- what was done with a batch under recall (the history is in the audit log; a closed case cannot change)
create or replace function public.recall_batch_mark(p_case uuid, p_batch bigint, p_status text, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.recall_cases; n text := nullif(btrim(p_note), '');
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case for update;
  if not found then raise exception 'not found'; end if;
  if c.status <> 'open' then raise exception 'case_closed'; end if;
  if p_status is null or p_status not in ('to_do', 'removed_from_shelf', 'returned_to_supplier', 'written_off', 'not_found', 'nothing_left') then raise exception 'bad_status'; end if;
  if p_status in ('written_off', 'not_found') and (n is null or length(n) < 3) then raise exception 'note_required'; end if;
  if n is not null and length(n) > 300 then raise exception 'bad_note'; end if;
  update public.recall_batches set action_status = p_status, action_by = auth.uid(), action_at = now(), action_note = n where case_id = p_case and batch_id = p_batch;
  if not found then raise exception 'batch_not_in_case'; end if;
  return jsonb_build_object('case_id', p_case, 'batch_id', p_batch, 'status', p_status);
end $$;

create or replace function public.recall_close(p_case uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.recall_cases; n text := btrim(coalesce(p_note, '')); sid text; open_n int; loc int;
begin
  if not public._rb3_recall_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case for update;
  if not found then raise exception 'not found'; end if;
  if c.status = 'closed' then return jsonb_build_object('dup', true, 'status', 'closed'); end if;
  if length(n) < 3 or length(n) > 500 then raise exception 'note_required'; end if;
  select count(*) into open_n from public.recall_batches where case_id = p_case and action_status = 'to_do';
  select staff_id into sid from public.profiles where id = auth.uid();
  update public.recall_cases set status = 'closed', closed_by = auth.uid(), closed_staff = sid, closed_at = now(), close_note = n where id = p_case;
  if open_n > 0 then
    select b.location_id into loc from public.recall_batches rb join public.stock_batches b on b.id = rb.batch_id where rb.case_id = p_case order by rb.id limit 1;
    perform public._stock_exc(loc, 'recall_closed_open', 'yellow', 'রিকল কেস বন্ধ, কিন্তু ' || open_n::text || ' ব্যাচের কাজ বাকি', 'A recall case was closed with ' || open_n::text || ' batch(es) still to do');
  end if;
  return jsonb_build_object('status', 'closed', 'still_to_do', open_n);
end $$;

create or replace function public.recall_list(p_status text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  if p_status is not null and p_status not in ('open', 'closed') then raise exception 'bad_status'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'case_no', c.case_no, 'title', c.title, 'reason', c.reason, 'hazard', c.hazard, 'status', c.status, 'opened_at', c.opened_at,
      'opened_staff', c.opened_staff, 'closed_at', c.closed_at, 'close_note', c.close_note,
      'batches_n', (select count(*) from public.recall_batches rb where rb.case_id = c.id),
      'to_do_n', (select count(*) from public.recall_batches rb where rb.case_id = c.id and rb.action_status = 'to_do')) order by c.case_no desc)
    from public.recall_cases c where p_status is null or c.status = p_status), '[]'::jsonb);
end $$;

-- ---------- the affected-stock report of a case ----------
create or replace function public.recall_affected(p_case uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.recall_cases; starts bigint[]; fwd jsonb; summ jsonb; entered jsonb; unlot jsonb := '[]'::jsonb; r record; o jsonb;
begin
  if not public._rb3_trace_ok() then raise exception 'not allowed'; end if;
  select * into c from public.recall_cases where id = p_case;
  if not found then raise exception 'not found'; end if;
  select coalesce(array_agg(rb.batch_id order by rb.id), '{}') into starts from public.recall_batches rb where rb.case_id = p_case;
  select coalesce(jsonb_agg(public._rb3_batch_row(rb.batch_id) || jsonb_build_object('action_status', rb.action_status, 'action_note', rb.action_note, 'action_at', rb.action_at, 'note', rb.note) order by rb.id), '[]'::jsonb)
    into entered from public.recall_batches rb where rb.case_id = p_case;
  fwd := public._rb3_forward(starts);
  summ := public._rb3_summary(fwd);
  -- receipts of the same item from the same supplier that carry no lot: the recalled lot cannot be ruled out for them
  for r in select distinct (public._rb3_origin(public._rb3_root(u.bid)) ->> 'supplier_id')::uuid as sup, b.item_id from unnest(starts) as u(bid) join public.stock_batches b on b.id = u.bid loop
    if r.sup is null then continue; end if;
    unlot := unlot || coalesce((select jsonb_agg(jsonb_build_object('bill_id', pb.id, 'bill_no', pb.bill_no, 'bill_date', pb.bill_date, 'supplier_id', pb.supplier_id, 'supplier', sp.name, 'item_id', l.item_id,
          'code', i.code, 'qty', coalesce(l.base_qty, l.qty), 'location_id', pb.location_id) order by pb.bill_date desc)
        from public.purchase_bills pb join public.purchase_lines l on l.bill_id = pb.id join public.items i on i.id = l.item_id join public.suppliers sp on sp.id = pb.supplier_id
       where pb.status = 'posted' and pb.kind = 'bill' and pb.supplier_id = r.sup and l.item_id = r.item_id and public._rb3_loc_vis(pb.location_id)
         and not exists (select 1 from public.receipt_lots rl where rl.bill_id = pb.id and rl.line_no = l.line_no and rl.status = 'applied')
         and not exists (select 1 from public.grn_batch_links g where g.source_type = 'purchase' and g.source_id = pb.id and g.item_id = l.item_id)), '[]'::jsonb);
  end loop;
  return jsonb_build_object('case', to_jsonb(c) - 'client_id', 'entered', entered, 'forward', fwd, 'summary', summ, 'unlotted_receipts', unlot,
    'data_notes', to_jsonb(array_remove(array[case when jsonb_array_length(summ -> 'unbatched') > 0 then 'unbatched_stock_present' end,
                                                case when jsonb_array_length(unlot) > 0 then 'receipts_without_lot' end], null)));
end $$;

-- ---------- privileges ----------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('_rb3_trace_ok', '_rb3_loc_vis', '_rb3_origin', '_rb3_root', '_rb3_batch_row', '_rb3_forward', '_rb3_summary', '_rb3_recall_ok') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('trace_batch', 'trace_batch_find', 'recall_open', 'recall_add_batch', 'recall_batch_mark', 'recall_close', 'recall_list', 'recall_affected') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
