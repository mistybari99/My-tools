-- ============================================================
-- BOS tool · Phase 422 (RPT-B2 R2b): the stock MOVEMENT LEDGER of one item at one place (#63): opening, every movement with its running balance, closing, a check against the
-- cached balance, and for every row the source document (sale, refund, bill, transfer, production, wastage, count). Read-only. Paste after phase421. Safe to paste twice.
-- Opens to report_stock holders (rpt_access('stock')) at their own places; the cost of a row is shown only to who may see cost. Used by web/stockrep.js (#/stockrep/ledger),
-- which every "drill" link of the stock reports points to.
-- ============================================================

-- the source document of one ledger row: kind, a short label, and a few plain facts (no money unless the caller may see cost)
create or replace function public._r4_doc(p_reason text, p_ref_type text, p_ref_id text, p_cost boolean) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j jsonb;
begin
  if p_ref_type is null then return jsonb_build_object('kind', coalesce(p_reason, 'other'), 'label', coalesce(p_reason, '')); end if;
  if p_ref_type = 'sale' then
    select jsonb_build_object('kind', 'sale', 'label', 'Sale #' || s.receipt, 'detail', jsonb_build_object('receipt', s.receipt, 'sale_date', s.sale_date, 'status', s.status, 'pay_mode', s.pay_mode, 'location_id', s.location_id)) into j
      from public.sales s where s.id::text = p_ref_id;
  elsif p_ref_type = 'sale_return' then
    select jsonb_build_object('kind', 'refund', 'label', 'Refund of sale #' || s.receipt, 'detail', jsonb_build_object('receipt', s.receipt, 'reason_code', r.reason_code, 'status', r.status, 'refund_mode', r.refund_mode, 'created_at', r.created_at)) into j
      from public.sale_returns r join public.sales s on s.id = r.sale_id where r.id::text = p_ref_id;
  elsif p_ref_type = 'purchase' then
    select jsonb_build_object('kind', case b.kind when 'return' then 'purchase_return' else 'purchase' end, 'label', case b.kind when 'return' then 'Purchase return ' else 'Bill ' end || coalesce(b.bill_no, '-') || ' · ' || su.name,
      'detail', jsonb_build_object('bill_no', b.bill_no, 'supplier', su.name, 'bill_date', b.bill_date, 'status', b.status, 'reason_code', b.reason_code) || case when p_cost then jsonb_build_object('total', b.total) else '{}'::jsonb end) into j
      from public.purchase_bills b join public.suppliers su on su.id = b.supplier_id where b.id::text = p_ref_id;
  elsif p_ref_type = 'transfer' then
    select jsonb_build_object('kind', 'transfer', 'label', 'Transfer ' || coalesce(lf.name_en, lf.name_bn) || ' > ' || coalesce(lt.name_en, lt.name_bn),
      'detail', jsonb_build_object('status', x.status, 'sent_qty', x.qty, 'received_qty', x.received_qty, 'sent_at', x.sent_at, 'received_at', x.received_at, 'sent_staff', x.sent_staff, 'received_staff', x.received_staff, 'note', coalesce(x.receive_note, x.note))) into j
      from public.stock_transfers x join public.locations lf on lf.id = x.from_location_id join public.locations lt on lt.id = x.to_location_id where x.id::text = p_ref_id;
  elsif p_ref_type = 'wastage' then
    select jsonb_build_object('kind', 'wastage', 'label', 'Wastage · ' || coalesce(o.label_en, w.reason_code), 'detail', jsonb_build_object('reason_code', w.reason_code, 'note', w.note, 'made_at', w.made_at, 'staff', w.created_staff)) into j
      from public.stock_wastage w left join public.option_lists o on o.list_code = 'wastage_reasons' and o.value_code = w.reason_code where w.id::text = p_ref_id;
  elsif p_ref_type = 'production' then
    select jsonb_build_object('kind', 'production', 'label', 'Production run ' || to_char(pr.made_at at time zone 'Asia/Dhaka', 'YYYY-MM-DD'),
      'detail', jsonb_build_object('run_id', pr.id, 'made_at', pr.made_at, 'batches', pr.batches, 'yield_base', pr.yield_base, 'batch_id', pr.batch_id)) into j
      from public.production_runs pr where pr.id::text = p_ref_id;
    if j is null and p_ref_id ~ '^[0-9]{1,18}$' then          -- a direct production entry: the reference is the batch
      select jsonb_build_object('kind', 'production', 'label', 'Production batch #' || b.id, 'detail', jsonb_build_object('batch_id', b.id, 'made_at', b.made_at, 'expires_at', b.expires_at, 'qty_made', b.qty_made, 'note', b.note)) into j
        from public.stock_batches b where b.id::text = p_ref_id;
    end if;
  end if;
  return coalesce(j, jsonb_build_object('kind', coalesce(p_ref_type, p_reason), 'label', case p_ref_type when 'count' then 'Count adjust' when 'opening' then 'Opening stock' when 'issue' then 'Issue to production' else coalesce(p_ref_type, '') end));
end $$;
revoke all on function public._r4_doc(text, text, text, boolean) from public, anon, authenticated;

create or replace function public.stock_movement_ledger(p_item uuid, p_loc int, p_from date default null, p_to date default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := (now() at time zone 'Asia/Dhaka')::date; f date; t date; it public.items; lo public.locations; opening numeric; total_all numeric; cached numeric; avgc numeric;
        rows_ jsonb; sumry jsonb; n bigint; cost_ok boolean; closing numeric; first_run numeric; later bigint; cap constant int := 1000;
begin
  if not public.is_active() or not public.rpt_access('stock') then raise exception 'not allowed'; end if;
  if p_loc is null or not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  f := coalesce(p_from, today - 30); t := coalesce(p_to, today);
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  select * into it from public.items where id = p_item; if not found then raise exception 'item_not_found'; end if;
  select * into lo from public.locations where id = p_loc;
  cost_ok := public.rpt_cost_ok();
  select coalesce(sum(qty_delta), 0) into opening from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date < f;
  select coalesce(sum(qty_delta), 0) into total_all from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc;
  select b.qty, b.avg_cost into cached, avgc from public.stock_balance b where b.item_id = p_item and b.location_id = p_loc;
  select count(*) into n from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t;
  select count(*) into later from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date > t;
  select coalesce(jsonb_agg(jsonb_build_object('id', z.id, 'at', z.made_at, 'day', z.d, 'time', z.tm, 'reason', z.reason, 'ref_type', z.ref_type, 'ref_id', z.ref_id, 'qty_delta', z.qty_delta, 'running', z.running,
      'unit_cost', case when cost_ok then z.unit_cost end, 'value', case when cost_ok and z.unit_cost is not null then round(z.qty_delta * z.unit_cost, 2) end,
      '_nc', case when cost_ok and z.unit_cost is null and z.reason in ('purchase_in', 'production_in', 'opening', 'count_adjust') then '["unit_cost","value"]'::jsonb end,
      'batch_id', z.batch_id, 'batch_no', z.batch_no, 'note', z.note, 'who', z.who, 'reverses_id', z.reverses_id, 'doc', public._r4_doc(z.reason, z.ref_type, z.ref_id, cost_ok)) order by z.made_at, z.id), '[]'::jsonb)
    into rows_
    from (select q.*, row_number() over (order by q.made_at, q.id) as rn, count(*) over () as cnt from (
            select l.id, l.made_at, (l.made_at at time zone 'Asia/Dhaka')::date as d, to_char(l.made_at at time zone 'Asia/Dhaka', 'HH24:MI') as tm, l.reason, l.ref_type, l.ref_id, l.qty_delta, l.unit_cost, l.batch_id, sb.batch_no, l.note,
                   coalesce(nullif(btrim(p.full_name), '') || ' · ' || p.staff_id, p.staff_id) as who, l.reverses_id,
                   opening + sum(l.qty_delta) over (order by l.made_at, l.id) as running
              from public.stock_ledger l left join public.stock_batches sb on sb.id = l.batch_id left join public.profiles p on p.id = l.created_by
             where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t) q) z
   where z.rn > z.cnt - cap;
  closing := opening + coalesce((select sum(l.qty_delta) from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t), 0);
  first_run := case when n > cap then closing - coalesce((select sum(x.qty_delta) from (select l.qty_delta from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc
                       and (l.made_at at time zone 'Asia/Dhaka')::date between f and t order by l.made_at desc, l.id desc limit cap) x), 0) end;
  select coalesce(jsonb_agg(jsonb_build_object('reason', s.reason, 'rows', s.c, 'in_qty', s.i, 'out_qty', s.o, 'net', s.i - s.o) order by s.reason), '[]'::jsonb) into sumry
    from (select l.reason, count(*) as c, coalesce(sum(l.qty_delta) filter (where l.qty_delta > 0), 0) as i, coalesce(-sum(l.qty_delta) filter (where l.qty_delta < 0), 0) as o
            from public.stock_ledger l where l.item_id = p_item and l.location_id = p_loc and (l.made_at at time zone 'Asia/Dhaka')::date between f and t group by l.reason) s;
  return jsonb_build_object('item', jsonb_build_object('id', it.id, 'code', it.code, 'name_bn', it.name_bn, 'name_en', coalesce(it.name_en, it.name_bn), 'unit', public._item_base(it.id), 'item_type', it.item_type),
    'location', jsonb_build_object('id', lo.id, 'name_bn', lo.name_bn, 'name_en', coalesce(lo.name_en, lo.name_bn)), 'from', f, 'to', t,
    'opening', opening, 'closing', closing, 'rows', rows_, 'row_count', n, 'truncated', n > cap, 'shown_from_running', first_run, 'summary', sumry,
    'check', jsonb_build_object('ledger_total_all', total_all, 'cached', coalesce(cached, 0), 'ok', total_all = coalesce(cached, 0), 'later_rows', later, 'closing_is_latest', later = 0),
    'avg_cost', case when cost_ok then avgc end, 'cost_shown', cost_ok,
    'notes', case when n > cap then jsonb_build_array(public._r4_note('truncated', 'Only the last ' || cap || ' of ' || n || ' rows are shown; narrow the dates for the rest. The opening and closing are for the whole period.',
        'শেষ ' || cap || 'টি সারি (মোট ' || n || ') দেখানো হয়েছে; বাকিটা দেখতে তারিখ ছোট করুন। শুরু ও শেষের ব্যালান্স পুরো সময়ের।')) else '[]'::jsonb end);
end $$;
revoke all on function public.stock_movement_ledger(uuid, int, date, date) from public, anon;
grant execute on function public.stock_movement_ledger(uuid, int, date, date) to authenticated;

select public._r4_lockdown();
notify pgrst, 'reload schema';
