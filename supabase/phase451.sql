-- Phase 451 (RPT-HUB, part 2): "What happened?" day replay.
--   _rh_events(...)    one chronological event set read from the real tables (internal; closed to browsers)
--   rpt_hub_day(...)   day replay: events of one day (+ one outlet), day totals, reconciliation with the existing daily summary (biz_daily)
-- READ ONLY. A person sees only the kinds of record their report rights allow and only their locations; kinds they may not see are listed by
-- NAME in "masked" (never with counts or amounts). A figure that is not recorded is null ("not recorded"), never invented.
-- Safe to paste twice. Needs phase450.
do $$ begin if to_regprocedure('public._rh_area_ok(text)') is null then raise exception 'rpthub_needs_phase450'; end if; end $$;

drop function if exists public._rh_events(date, date, int, text[], text, text, boolean);
create or replace function public._rh_events(p_from date, p_to date, p_loc int default null, p_kinds text[] default null,
                                             p_ent text default null, p_eid text default null, p_ledger boolean default false)
returns table (ts timestamptz, day date, kind text, area text, loc int, who text, who_id uuid, amount numeric, qty numeric, dir text, title text, status text, detail jsonb,
               ref_table text, ref_id text, link text, item_id uuid, cust_id uuid, sup_id uuid, emp_id uuid, batch_id bigint, delta numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  t0 timestamptz := (p_from::timestamp at time zone 'Asia/Dhaka');
  t1 timestamptz := ((p_to + 1)::timestamp at time zone 'Asia/Dhaka');
  locs int[] := public._rh_locs();
  own boolean := public.is_owner();
  a_sales boolean := public._rh_area_ok('sales');  a_pos boolean := public._rh_area_ok('pos');  a_cust boolean := public._rh_area_ok('customers');
  a_cash boolean := public._rh_area_ok('cash');    a_stock boolean := public._rh_area_ok('stock'); a_purch boolean := public._rh_area_ok('purchase');
  a_exp boolean := public._rh_area_ok('expense');  a_pay boolean := public._rh_area_ok('payroll'); a_hr boolean := public._rh_area_ok('hr');
  a_ctl boolean := public._rh_area_ok('control');  a_acc boolean := public._rh_area_ok('accounts'); costok boolean := public._rh_area_ok('cost');
  k text[] := p_kinds;
  ne boolean := p_ent is null;              -- no entity filter
  max_days int;
begin
  if not public.is_active() then return; end if;
  max_days := case when p_ent in ('customer', 'supplier') then 40000 else 3700 end;
  if p_to < p_from or p_to - p_from > max_days then raise exception 'bad_range'; end if;
  -- a customer's own ledger is open to the holder of the customers right even without the sales right
  a_sales := a_sales or (p_ent = 'customer' and a_cust);
  return query
  with ap as (          -- approval requests of every kind, one shape
    select 'release'::text src, r.id::text rid, r.requested_at, r.requested_by, r.requested_staff, r.decided_at, r.decided_by, r.decided_staff, r.status, r.flag_amount amt, e.location_id lc, r.reason note, null::uuid itm
      from public.release_requests r left join public.entries e on e.id = r.entry_id where a_ctl and (r.requested_at >= t0 and r.requested_at < t1 or r.decided_at >= t0 and r.decided_at < t1)
    union all
    select 'emergency', q.id::text, q.created_at, q.requested_by, q.requested_staff, q.decided_at, q.decided_by, q.decided_staff, q.status, q.amount, q.location_id, q.reason, null::uuid
      from public.emergency_requests q where a_ctl and (q.created_at >= t0 and q.created_at < t1 or q.decided_at >= t0 and q.decided_at < t1)
    union all
    select 'change', c.id::text, c.created_at, c.requested_by, c.requested_staff, c.decided_at, c.decided_by, c.decided_staff, c.status, null::numeric, e.location_id, c.reason, null::uuid
      from public.entry_change_requests c left join public.entries e on e.id = c.entry_id where a_ctl and (c.created_at >= t0 and c.created_at < t1 or c.decided_at >= t0 and c.decided_at < t1)
    union all
    select 'wastage', w.id::text, w.requested_at, w.requested_by, w.requested_staff, w.decided_at, w.decided_by, w.decided_staff, w.status, null::numeric, w.location_id, w.note, w.item_id
      from public.wastage_requests w where a_ctl and (w.requested_at >= t0 and w.requested_at < t1 or w.decided_at >= t0 and w.decided_at < t1)
    union all
    select 'item_change', i.id::text, i.requested_at, i.requested_by, i.requested_staff, i.decided_at, i.decided_by, i.decided_staff, i.status, null::numeric, null::int, i.note, i.item_id
      from public.item_changes i where a_ctl and (i.requested_at >= t0 and i.requested_at < t1 or i.decided_at >= t0 and i.decided_at < t1)
    union all
    select 'party_adjustment', o.id::text, o.requested_at, o.requested_by, null::text, o.decided_at, o.decided_by, null::text, o.status, o.delta, null::int, o.reason, null::uuid
      from public.open_party_adjustments o where a_ctl and (o.requested_at >= t0 and o.requested_at < t1 or o.decided_at >= t0 and o.decided_at < t1)
  )
  -- 1 sales (the receipt itself; a voided sale stays listed with status void)
  select s.sold_at, s.sale_date, 'sale'::text, 'sales'::text, s.location_id, s.created_staff, s.created_by, s.total, null::numeric, 'in'::text, 'sale'::text, s.status,
         jsonb_build_object('receipt', s.receipt, 'pay_mode', s.pay_mode, 'discount', s.discount, 'due', s.due_amount, 'customer', s.customer, 'sale_type', s.sale_type, 'quick', s.quick,
                            'lines', case when jsonb_typeof(s.lines) = 'array' then jsonb_array_length(s.lines) end, 'paid', s.paid),
         'sales'::text, s.id::text, 'report/receipt_register'::text, null::uuid, s.customer_id, null::uuid, null::uuid, null::bigint, case when p_ent = 'customer' and s.status = 'done' then s.total end
    from public.sales s
   where a_sales and (k is null or 'sale' = any (k)) and s.sale_date between p_from and p_to and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc)
     and (ne or (p_ent = 'customer' and s.customer_id::text = p_eid) or (p_ent = 'staff' and s.created_by::text = p_eid))
  union all   -- 2 voids (shown on the day the void was made)
  select s.void_at, public._rh_day(s.void_at), 'void', 'sales', s.location_id, coalesce(s.void_staff, public._rh_staff(s.void_by)), s.void_by, s.total, null::numeric, 'out', 'void', 'void',
         jsonb_build_object('receipt', s.receipt, 'note', s.void_note, 'sold_at', s.sold_at, 'sale_date', s.sale_date), 'sales', s.id::text, 'report/voids', null::uuid, s.customer_id, null::uuid, null::uuid, null::bigint, null::numeric
    from public.sales s
   where a_sales and (k is null or 'void' = any (k)) and s.status = 'void' and s.void_at >= t0 and s.void_at < t1 and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc)
     and (ne or (p_ent = 'customer' and s.customer_id::text = p_eid) or (p_ent = 'staff' and s.void_by::text = p_eid))
  union all   -- 3 returns and refunds
  select r.created_at, public._rh_day(r.created_at), 'return', 'sales', r.location_id, r.created_staff, r.created_by, r.amount, null::numeric, 'out', 'sale_return', r.status,
         jsonb_build_object('refund', r.refund_amount, 'credit', r.credit_amount, 'refund_mode', r.refund_mode, 'reason', r.reason_code, 'note', r.note, 'sale_id', r.sale_id),
         'sale_returns', r.id::text, 'salereturn', null::uuid, r.customer_id, null::uuid, null::uuid, null::bigint, case when p_ent = 'customer' and r.status = 'done' then -r.credit_amount end
    from public.sale_returns r
   where a_sales and (k is null or 'return' = any (k)) and r.created_at >= t0 and r.created_at < t1 and r.location_id = any (locs) and (p_loc is null or r.location_id = p_loc)
     and (ne or (p_ent = 'customer' and r.customer_id::text = p_eid) or (p_ent = 'staff' and r.created_by::text = p_eid))
  union all   -- 4 collections of old dues (and, for a customer timeline only, the money paid on each sale)
  select p.paid_at, public._rh_day(p.paid_at), case when p.kind = 'collection' then 'collection' else 'sale_payment' end, 'customers', p.location_id, p.created_staff, p.created_by, p.amount, null::numeric, 'in',
         case when p.kind = 'collection' then 'collection' else 'sale_payment' end, case when p.voided then 'void' else 'done' end,
         jsonb_build_object('mode', p.mode, 'wallet', p.wallet, 'ref', p.ref, 'note', p.note, 'sale_id', p.sale_id, 'void_note', p.void_note),
         'sale_payments', p.id::text, 'dues', null::uuid, p.customer_id, null::uuid, null::uuid, null::bigint, case when p_ent = 'customer' and not p.voided then -p.amount end
    from public.sale_payments p
   where (a_cust or a_sales) and p.paid_at >= t0 and p.paid_at < t1 and p.location_id = any (locs) and (p_loc is null or p.location_id = p_loc)
     and ((k is null and (p.kind = 'collection' or p_ent = 'customer')) or (p.kind = 'collection' and 'collection' = any (k)) or (p.kind = 'sale' and 'sale_payment' = any (k)))
     and (ne or (p_ent = 'customer' and p.customer_id::text = p_eid) or (p_ent = 'staff' and p.created_by::text = p_eid))
  union all   -- 5 quick expenses
  select public._rh_ts(q.exp_date, q.created_at), q.exp_date, 'expense', 'expense', q.location_id, q.created_staff, q.created_by, q.amount, null::numeric, 'out', 'quick_expense', q.status,
         jsonb_build_object('head', q.head, 'paid_to', q.paid_to, 'mode', q.mode, 'receipt', q.receipt, 'note', q.note, 'recorded_at', q.created_at), 'quick_expenses', q.id::text, 'quickexp',
         null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.quick_expenses q
   where a_exp and (k is null or 'expense' = any (k)) and q.exp_date between p_from and p_to and q.location_id = any (locs) and (p_loc is null or q.location_id = p_loc)
     and (ne or (p_ent = 'staff' and q.created_by::text = p_eid))
  union all   -- 6 expense vouchers (paper form 10-2)
  select public._rh_ts(e.entry_date, e.submitted_at), e.entry_date, 'voucher', 'expense', e.location_id, e.created_staff, e.created_by, v.total, null::numeric, 'out', 'expense_voucher', e.status,
         jsonb_build_object('serial', e.serial, 'lines', v.n, 'form', e.form_code), 'entries', e.id::text, 'forms', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.entries e cross join lateral (
      select count(*) n, coalesce(sum(public._r2_num(x -> 'amount')), 0) total
        from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) x) v
   where a_exp and (k is null or 'voucher' = any (k)) and e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to
     and e.location_id = any (locs) and (p_loc is null or e.location_id = p_loc) and not public.is_shadow('entries', e.id::text)
     and (ne or (p_ent = 'staff' and e.created_by::text = p_eid))
  union all   -- 7 supplier payments and refunds
  select sp.paid_at, public._rh_day(sp.paid_at), 'supplier_payment', 'purchase', sp.location_id, sp.created_staff, sp.created_by, sp.amount, null::numeric, 'out', 'supplier_payment', case when sp.voided then 'void' else 'done' end,
         jsonb_build_object('mode', sp.mode, 'wallet', sp.wallet, 'ref', sp.ref, 'bill_id', sp.bill_id, 'note', sp.note, 'supplier', su.name), 'supplier_payments', sp.id::text, 'payables',
         null::uuid, null::uuid, sp.supplier_id, null::uuid, null::bigint, case when p_ent = 'supplier' and not sp.voided then -sp.amount end
    from public.supplier_payments sp left join public.suppliers su on su.id = sp.supplier_id
   where a_purch and (k is null or 'supplier_payment' = any (k)) and sp.paid_at >= t0 and sp.paid_at < t1 and (sp.location_id is null or sp.location_id = any (locs)) and (p_loc is null or sp.location_id = p_loc)
     and (ne or (p_ent = 'supplier' and sp.supplier_id::text = p_eid) or (p_ent = 'staff' and sp.created_by::text = p_eid))
  union all
  select sf.refunded_at, public._rh_day(sf.refunded_at), 'supplier_refund', 'purchase', sf.location_id, sf.created_staff, sf.created_by, sf.amount, null::numeric, 'in', 'supplier_refund', case when sf.voided then 'void' else 'done' end,
         jsonb_build_object('mode', sf.mode, 'ref', sf.ref, 'reason', sf.reason_code, 'note', sf.note, 'supplier', su.name), 'supplier_refunds', sf.id::text, 'payables',
         null::uuid, null::uuid, sf.supplier_id, null::uuid, null::bigint, case when p_ent = 'supplier' and not sf.voided then sf.amount end
    from public.supplier_refunds sf left join public.suppliers su on su.id = sf.supplier_id
   where a_purch and (k is null or 'supplier_refund' = any (k)) and sf.refunded_at >= t0 and sf.refunded_at < t1 and (sf.location_id is null or sf.location_id = any (locs)) and (p_loc is null or sf.location_id = p_loc)
     and (ne or (p_ent = 'supplier' and sf.supplier_id::text = p_eid) or (p_ent = 'staff' and sf.created_by::text = p_eid))
  union all   -- 8 purchase bills and purchase returns (posted or voided; a draft is not a business event yet)
  select public._rh_ts(b.bill_date, coalesce(b.posted_at, b.created_at)), b.bill_date, case when b.kind = 'return' then 'purchase_return' else 'purchase' end, 'purchase', b.location_id, b.created_staff, b.created_by, b.total,
         null::numeric, case when b.kind = 'return' then 'in' else 'out' end, case when b.kind = 'return' then 'purchase_return' else 'purchase_bill' end, b.status,
         jsonb_build_object('bill_no', b.bill_no, 'paid', b.paid, 'due', b.due, 'supplier', su.name, 'note', b.note, 'reason', b.reason_code), 'purchase_bills', b.id::text, 'purchase',
         null::uuid, null::uuid, b.supplier_id, null::uuid, null::bigint, case when p_ent = 'supplier' and b.status = 'posted' then case when b.kind = 'return' then -b.total else b.total end end
    from public.purchase_bills b left join public.suppliers su on su.id = b.supplier_id
   where a_purch and (k is null or 'purchase' = any (k) or 'purchase_return' = any (k)) and b.status in ('posted', 'void') and b.bill_date between p_from and p_to
     and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc)
     and (ne or (p_ent = 'supplier' and b.supplier_id::text = p_eid) or (p_ent = 'staff' and b.created_by::text = p_eid))
  union all   -- 9 production runs (cost only with the cost right)
  select pr.made_at, public._rh_day(pr.made_at), 'production', 'stock', pr.location_id, public._rh_staff(pr.created_by), pr.created_by,
         case when costok then coalesce(pr.actual_cost, pr.std_cost) end, pr.yield_base * pr.batches, null::text, 'production_run', pr.status,
         jsonb_build_object('batches', pr.batches, 'yield_actual', pr.yield_actual, 'item', i.name_en, 'item_bn', i.name_bn, 'note', pr.note, 'cost_hidden', not costok), 'production_runs', pr.id::text, 'recipes',
         pr.item_id, null::uuid, null::uuid, null::uuid, pr.batch_id, null::numeric
    from public.production_runs pr left join public.items i on i.id = pr.item_id
   where a_stock and (k is null or 'production' = any (k)) and pr.made_at >= t0 and pr.made_at < t1 and pr.location_id = any (locs) and (p_loc is null or pr.location_id = p_loc)
     and (ne or (p_ent = 'item' and pr.item_id::text = p_eid) or (p_ent = 'batch' and pr.batch_id::text = p_eid) or (p_ent = 'staff' and pr.created_by::text = p_eid))
  union all   -- 10 transfers: sent, received (with the short quantity), cancelled
  select tr.sent_at, public._rh_day(tr.sent_at), 'transfer_sent', 'stock', tr.from_location_id, tr.sent_staff, tr.sent_by, null::numeric, tr.qty, 'out', 'transfer_sent', tr.status,
         jsonb_build_object('to', tr.to_location_id, 'item', i.name_en, 'item_bn', i.name_bn, 'note', tr.note), 'stock_transfers', tr.id::text, 'stock', tr.item_id, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.stock_transfers tr left join public.items i on i.id = tr.item_id
   where a_stock and (k is null or 'transfer_sent' = any (k)) and tr.sent_at >= t0 and tr.sent_at < t1 and tr.from_location_id = any (locs) and (p_loc is null or tr.from_location_id = p_loc or tr.to_location_id = p_loc)
     and (ne or (p_ent = 'item' and tr.item_id::text = p_eid) or (p_ent = 'staff' and tr.sent_by::text = p_eid))
  union all
  select tr.received_at, public._rh_day(tr.received_at), 'transfer_received', 'stock', tr.to_location_id, tr.received_staff, tr.received_by, null::numeric, tr.received_qty, 'in', 'transfer_received', tr.status,
         jsonb_build_object('from', tr.from_location_id, 'sent_qty', tr.qty, 'short', tr.qty - tr.received_qty, 'item', i.name_en, 'item_bn', i.name_bn, 'note', tr.receive_note), 'stock_transfers', tr.id::text, 'stock',
         tr.item_id, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.stock_transfers tr left join public.items i on i.id = tr.item_id
   where a_stock and (k is null or 'transfer_received' = any (k)) and tr.received_at >= t0 and tr.received_at < t1 and tr.to_location_id = any (locs) and (p_loc is null or tr.to_location_id = p_loc or tr.from_location_id = p_loc)
     and (ne or (p_ent = 'item' and tr.item_id::text = p_eid) or (p_ent = 'staff' and tr.received_by::text = p_eid))
  union all
  select tr.cancelled_at, public._rh_day(tr.cancelled_at), 'transfer_cancelled', 'stock', tr.from_location_id, public._rh_staff(tr.cancelled_by), tr.cancelled_by, null::numeric, tr.qty, null::text, 'transfer_cancelled', tr.status,
         jsonb_build_object('to', tr.to_location_id, 'item', i.name_en, 'item_bn', i.name_bn), 'stock_transfers', tr.id::text, 'stock', tr.item_id, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.stock_transfers tr left join public.items i on i.id = tr.item_id
   where a_stock and (k is null or 'transfer_cancelled' = any (k)) and tr.cancelled_at >= t0 and tr.cancelled_at < t1 and tr.from_location_id = any (locs) and (p_loc is null or tr.from_location_id = p_loc or tr.to_location_id = p_loc)
     and (ne or (p_ent = 'item' and tr.item_id::text = p_eid) or (p_ent = 'staff' and tr.cancelled_by::text = p_eid))
  union all   -- 11 wastage (value only with the cost right)
  select w.made_at, public._rh_day(w.made_at), 'wastage', 'stock', w.location_id, w.created_staff, w.created_by, case when costok then abs(w.qty * sl.unit_cost) end, w.qty, 'out', 'wastage', 'done',
         jsonb_build_object('reason', w.reason_code, 'note', w.note, 'item', i.name_en, 'item_bn', i.name_bn, 'cost_hidden', not costok), 'stock_wastage', w.id::text, 'stock', w.item_id, null::uuid, null::uuid, null::uuid, w.batch_id, null::numeric
    from public.stock_wastage w left join public.items i on i.id = w.item_id left join public.stock_ledger sl on sl.id = w.ledger_id
   where a_stock and (k is null or 'wastage' = any (k)) and w.made_at >= t0 and w.made_at < t1 and w.location_id = any (locs) and (p_loc is null or w.location_id = p_loc)
     and (ne or (p_ent = 'item' and w.item_id::text = p_eid) or (p_ent = 'batch' and w.batch_id::text = p_eid) or (p_ent = 'staff' and w.created_by::text = p_eid))
  union all   -- 12 stock ledger: count adjustments always; every movement of one item / batch when an item or batch timeline asks for it
  select l.made_at, public._rh_day(l.made_at), case when l.reason = 'count_adjust' and not p_ledger then 'count_adjust' else 'ledger' end, 'stock', l.location_id, public._rh_staff(l.created_by), l.created_by,
         case when costok then l.qty_delta * l.unit_cost end, l.qty_delta, case when l.qty_delta < 0 then 'out' else 'in' end, l.reason, 'done',
         jsonb_build_object('reason', l.reason, 'ref_type', l.ref_type, 'ref_id', l.ref_id, 'note', l.note, 'item', i.name_en, 'item_bn', i.name_bn, 'reverses_id', l.reverses_id, 'cost_hidden', not costok),
         'stock_ledger', l.id::text, 'stock', l.item_id, null::uuid, null::uuid, null::uuid, l.batch_id, l.qty_delta
    from public.stock_ledger l left join public.items i on i.id = l.item_id
   where a_stock and l.made_at >= t0 and l.made_at < t1 and l.location_id = any (locs) and (p_loc is null or l.location_id = p_loc)
     and ((p_ledger and (p_ent = 'item' and l.item_id::text = p_eid or p_ent = 'batch' and l.batch_id::text = p_eid) and (k is null or 'ledger' = any (k)))
          or (not p_ledger and l.reason = 'count_adjust' and (k is null or 'count_adjust' = any (k)) and (ne or (p_ent = 'item' and l.item_id::text = p_eid) or (p_ent = 'batch' and l.batch_id::text = p_eid) or (p_ent = 'staff' and l.created_by::text = p_eid))))
  union all   -- 13 cash moves, cash short cases, other income, money transfers
  select public._rh_ts(c.move_date, c.created_at), c.move_date, 'cash_move', 'cash', c.location_id, c.created_staff, c.created_by, c.amount, null::numeric, null::text, 'cash_move', c.status,
         jsonb_build_object('move_kind', c.kind, 'mode', c.mode, 'ref', c.ref, 'note', c.note), 'cash_moves', c.id::text, 'cashmoves', null::uuid, c.customer_id, null::uuid, null::uuid, null::bigint, null::numeric
    from public.cash_moves c
   where a_cash and (k is null or 'cash_move' = any (k)) and c.move_date between p_from and p_to and c.location_id = any (locs) and (p_loc is null or c.location_id = p_loc)
     and (ne or (p_ent = 'customer' and c.customer_id::text = p_eid) or (p_ent = 'staff' and c.created_by::text = p_eid))
  union all
  select public._rh_ts(sc.case_date, sc.created_at), sc.case_date, 'cash_short', 'cash', sc.location_id, public._rh_staff(sc.decided_by), sc.decided_by, sc.amount, null::numeric, 'out', 'cash_short', sc.status,
         jsonb_build_object('treatment', sc.treatment, 'reason', sc.reason, 'decided_at', sc.decided_at, 'decide_note', sc.decide_note, 'form', sc.form_code), 'shortage_cash_cases', sc.id::text, 'shortages',
         null::uuid, null::uuid, null::uuid, sc.employee_id, null::bigint, null::numeric
    from public.shortage_cash_cases sc
   where a_cash and ne and (k is null or 'cash_short' = any (k)) and sc.case_date between p_from and p_to and sc.location_id = any (locs) and (p_loc is null or sc.location_id = p_loc)
  union all
  select public._rh_ts(oi.income_date, oi.created_at), oi.income_date, 'other_income', 'cash', oi.location_id, oi.created_staff, oi.created_by, oi.amount, null::numeric, 'in', 'other_income', oi.status,
         jsonb_build_object('head', oi.head, 'mode', oi.mode, 'from', oi.received_from, 'note', oi.note), 'other_income', oi.id::text, 'otherincome', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.other_income oi
   where a_cash and (k is null or 'other_income' = any (k)) and oi.income_date between p_from and p_to and oi.location_id = any (locs) and (p_loc is null or oi.location_id = p_loc)
     and (ne or (p_ent = 'staff' and oi.created_by::text = p_eid))
  union all
  select public._rh_ts(mt.xfer_date, mt.created_at), mt.xfer_date, 'money_transfer', 'cash', mt.location_id, mt.created_staff, mt.created_by, mt.amount, null::numeric, null::text, 'money_transfer', mt.status,
         jsonb_build_object('fee', mt.fee, 'ref', mt.ref, 'note', mt.note), 'money_transfers', mt.id::text, 'moneyaccounts', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.money_transfers mt
   where a_cash and (k is null or 'money_transfer' = any (k)) and mt.xfer_date between p_from and p_to and (mt.location_id is null or mt.location_id = any (locs)) and (p_loc is null or mt.location_id = p_loc)
     and (ne or (p_ent = 'staff' and mt.created_by::text = p_eid))
  union all   -- 14 saved paper sheets (cash handover 10-1, daily showroom sheet 14-1, stock count 04-3, factory sheet 05-1). Only the fact and the status: a blind count figure is never shown here.
  select public._rh_ts(e.entry_date, coalesce(e.submitted_at, e.created_at)), e.entry_date,
         case e.form_code when '10-1' then 'handover' when '14-1' then 'day_sheet' when '04-3' then 'count_sheet' else 'factory_sheet' end,
         case e.form_code when '10-1' then 'cash' when '14-1' then 'pos' else 'stock' end, e.location_id, e.created_staff, e.created_by, null::numeric, null::numeric, null::text,
         case e.form_code when '10-1' then 'cash_handover' when '14-1' then 'daily_showroom_sheet' when '04-3' then 'stock_count' else 'factory_daily_sheet' end, e.status,
         jsonb_build_object('form', e.form_code, 'serial', e.serial, 'checked_by', e.checked_staff, 'paper_serial', e.paper_serial, 'entered_later', e.entered_later), 'entries', e.id::text, 'forms',
         null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.entries e
   where e.form_code in ('10-1', '14-1', '04-3', '05-1') and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to and e.location_id = any (locs) and (p_loc is null or e.location_id = p_loc)
     and case e.form_code when '10-1' then a_cash when '14-1' then a_pos else a_stock end
     and (k is null or (case e.form_code when '10-1' then 'handover' when '14-1' then 'day_sheet' when '04-3' then 'count_sheet' else 'factory_sheet' end) = any (k))
     and (ne or (p_ent = 'staff' and e.created_by::text = p_eid))
  union all   -- 15 goods short in transit
  select public._rh_ts(public._rh_day(st.created_at), st.created_at), public._rh_day(st.created_at), 'transit_short', 'stock', st.to_location_id, null::text, null::uuid, case when costok then st.value end, st.qty_short, 'out', 'transit_short', st.status,
         jsonb_build_object('from', st.from_location_id, 'claimed', case when costok then st.claimed_amount end, 'recovered', case when costok then st.recovered_amount end, 'item', i.name_en, 'item_bn', i.name_bn, 'cost_hidden', not costok),
         'shortage_transit', st.id::text, 'shortages', st.item_id, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.shortage_transit st left join public.items i on i.id = st.item_id
   where a_stock and (k is null or 'transit_short' = any (k)) and st.created_at >= t0 and st.created_at < t1 and st.to_location_id = any (locs) and (p_loc is null or st.to_location_id = p_loc)
     and (ne or (p_ent = 'item' and st.item_id::text = p_eid))
  union all   -- 16 approvals: the request and the decision are two events
  select x.requested_at, public._rh_day(x.requested_at), 'approval', 'control', x.lc, coalesce(x.requested_staff, public._rh_staff(x.requested_by)), x.requested_by, x.amt, null::numeric, null::text, x.src || '_requested', 'requested',
         jsonb_build_object('reason', x.note, 'result', x.status), 'approval_' || x.src, x.rid, 'pending', x.itm, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from ap x
   where (k is null or 'approval' = any (k)) and x.requested_at >= t0 and x.requested_at < t1 and (x.lc is null or x.lc = any (locs)) and (p_loc is null or x.lc = p_loc)
     and (ne or (p_ent = 'staff' and x.requested_by::text = p_eid) or (p_ent = 'item' and x.itm::text = p_eid))
  union all
  select x.decided_at, public._rh_day(x.decided_at), 'approval', 'control', x.lc, coalesce(x.decided_staff, public._rh_staff(x.decided_by)), x.decided_by, x.amt, null::numeric, null::text, x.src || '_decided', x.status,
         jsonb_build_object('reason', x.note, 'requested_by', coalesce(x.requested_staff, public._rh_staff(x.requested_by)), 'requested_at', x.requested_at), 'approval_' || x.src, x.rid, 'pending', x.itm, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from ap x
   where (k is null or 'approval' = any (k)) and x.decided_at is not null and x.decided_at >= t0 and x.decided_at < t1 and (x.lc is null or x.lc = any (locs)) and (p_loc is null or x.lc = p_loc)
     and (ne or (p_ent = 'staff' and x.decided_by::text = p_eid) or (p_ent = 'item' and x.itm::text = p_eid))
  union all   -- 17 exceptions raised and resolved
  select public._rh_ts(ex.entry_date, ex.created_at), ex.entry_date, 'exception', 'control', ex.location_id, null::text, null::uuid, ex.amount, null::numeric, null::text, ex.flag_code, ex.status,
         jsonb_build_object('level', ex.level, 'form', ex.form_code, 'text', ex.text, 'sale_id', ex.sale_id, 'raised_at', ex.created_at), 'exceptions', ex.id::text, 'exceptions', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.exceptions ex
   where a_ctl and ne and (k is null or 'exception' = any (k)) and ex.created_at >= t0 and ex.created_at < t1 and (ex.location_id is null or ex.location_id = any (locs)) and (p_loc is null or ex.location_id = p_loc)
     and (own or public.can_do(ex.form_code, 'approve'))
  union all
  select ex.resolved_at, public._rh_day(ex.resolved_at), 'exception_resolved', 'control', ex.location_id, coalesce(ex.resolved_staff, public._rh_staff(ex.resolved_by)), ex.resolved_by, ex.amount, null::numeric, null::text, ex.flag_code, 'resolved',
         jsonb_build_object('level', ex.level, 'form', ex.form_code, 'note', ex.resolved_note), 'exceptions', ex.id::text, 'exceptions', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.exceptions ex
   where a_ctl and ne and (k is null or 'exception' = any (k) or 'exception_resolved' = any (k)) and ex.resolved_at >= t0 and ex.resolved_at < t1 and (ex.location_id is null or ex.location_id = any (locs)) and (p_loc is null or ex.location_id = p_loc)
     and (own or public.can_do(ex.form_code, 'approve'))
  union all   -- 18 period and lock events
  select m.created_at, public._rh_day(m.created_at), 'period', 'accounts', null::int, m.created_staff, m.created_by, null::numeric, null::numeric, null::text, 'month_' || m.action, 'done',
         jsonb_build_object('month', m.month, 'note', m.note), 'c_month_close_log', m.id::text, 'monthclose', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.c_month_close_log m
   where a_acc and ne and p_loc is null and (k is null or 'period' = any (k)) and m.created_at >= t0 and m.created_at < t1
  union all
  select y.closed_at, public._rh_day(y.closed_at), 'period', 'accounts', null::int, public._rh_staff(y.closed_by), y.closed_by, case when a_acc then y.net_profit end, null::numeric, null::text, 'year_closed', y.status,
         jsonb_build_object('from', y.fiscal_from, 'to', y.fiscal_to, 'note', y.note), 'year_closes', y.id::text, 'finance2', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.year_closes y
   where a_acc and ne and p_loc is null and (k is null or 'period' = any (k)) and y.closed_at >= t0 and y.closed_at < t1
  union all
  select y.reopened_at, public._rh_day(y.reopened_at), 'period', 'accounts', null::int, public._rh_staff(y.reopened_by), y.reopened_by, null::numeric, null::numeric, null::text, 'year_reopened', y.status,
         jsonb_build_object('from', y.fiscal_from, 'to', y.fiscal_to, 'note', y.reopen_note), 'year_closes', y.id::text, 'finance2', null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.year_closes y
   where a_acc and ne and p_loc is null and (k is null or 'period' = any (k)) and y.reopened_at >= t0 and y.reopened_at < t1
  union all
  select po.started_at, public._rh_day(po.started_at), 'period', 'accounts', null::int, public._rh_staff(po.started_by), po.started_by, null::numeric, null::numeric, null::text, 'lock_override_started', case when po.ended_at is null then 'open' else 'ended' end,
         jsonb_build_object('scope', po.scope, 'from', po.from_date, 'to', po.to_date, 'doc_type', po.doc_type, 'reason', po.reason, 'uses', po.uses, 'ended_at', po.ended_at), 'period_overrides', po.id::text, 'periodlock',
         null::uuid, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.period_overrides po
   where a_acc and ne and p_loc is null and (k is null or 'period' = any (k)) and po.started_at >= t0 and po.started_at < t1
  union all   -- 19 staff status changes and exits (HR right)
  select sl.at, public._rh_day(sl.at), 'staff_status', 'hr', em.primary_location_id, public._rh_staff(sl."by"), sl."by", null::numeric, null::numeric, null::text, 'staff_' || sl.to_status, sl.to_status,
         jsonb_build_object('from', sl.from_status, 'to', sl.to_status, 'effective', sl.status_date, 'reason', sl.reason, 'employee', coalesce(em.full_name_en, em.full_name_bn), 'employee_no', em.employee_no),
         'employee_status_log', sl.id::text, 'employees', null::uuid, null::uuid, null::uuid, sl.employee_id, null::bigint, null::numeric
    from public.employee_status_log sl left join public.employees em on em.id = sl.employee_id
   where a_hr and (k is null or 'staff_status' = any (k)) and sl.at >= t0 and sl.at < t1 and (em.primary_location_id is null or em.primary_location_id = any (locs)) and (p_loc is null or em.primary_location_id = p_loc)
     and (ne or (p_ent = 'employee' and sl.employee_id::text = p_eid) or (p_ent = 'staff' and em.profile_id::text = p_eid))
  union all
  select xl.at, public._rh_day(xl.at), 'staff_exit', 'hr', em.primary_location_id, public._rh_staff(xl.by_user), xl.by_user, null::numeric, null::numeric, null::text, 'staff_exit_' || coalesce(xl.action, ''), xl.to_status,
         jsonb_build_object('action', xl.action, 'grants_ended', xl.grants_ended, 'lists_ended', xl.lists_ended, 'devices_off', xl.devices_off, 'reason', xl.reason, 'employee', coalesce(em.full_name_en, em.full_name_bn)),
         'w1c_exit_log', xl.id::text, 'employees', null::uuid, null::uuid, null::uuid, xl.employee_id, null::bigint, null::numeric
    from public.w1c_exit_log xl left join public.employees em on em.id = xl.employee_id
   where a_hr and (k is null or 'staff_exit' = any (k)) and xl.at >= t0 and xl.at < t1 and (em.primary_location_id is null or em.primary_location_id = any (locs)) and (p_loc is null or em.primary_location_id = p_loc)
     and (ne or (p_ent = 'employee' and xl.employee_id::text = p_eid) or (p_ent = 'staff' and em.profile_id::text = p_eid))
  union all   -- 20 pay: salary payments and advances (payroll right only)
  select public._rh_ts(pp.pay_date, pp.created_at), pp.pay_date, 'payroll', 'payroll', pp.location_id, public._rh_staff(pp.created_by), pp.created_by, pp.amount, null::numeric, 'out', 'salary_payment', pp.status,
         jsonb_build_object('mode', pp.mode, 'employee', coalesce(em.full_name_en, em.full_name_bn), 'note', pp.note), 'payroll_payments', pp.id::text, 'payroll', null::uuid, null::uuid, null::uuid, pp.employee_id, null::bigint, null::numeric
    from public.payroll_payments pp left join public.employees em on em.id = pp.employee_id
   where a_pay and (k is null or 'payroll' = any (k)) and pp.pay_date between p_from and p_to and (pp.location_id is null or pp.location_id = any (locs)) and (p_loc is null or pp.location_id = p_loc)
     and (ne or (p_ent = 'employee' and pp.employee_id::text = p_eid) or (p_ent = 'staff' and em.profile_id::text = p_eid))
  union all
  select public._rh_ts(ad.adv_date, ad.created_at), ad.adv_date, 'advance', 'payroll', ad.location_id, public._rh_staff(ad.created_by), ad.created_by, ad.amount, null::numeric, 'out', 'staff_advance', ad.status,
         jsonb_build_object('mode', ad.mode, 'employee', coalesce(em.full_name_en, em.full_name_bn), 'instalment', ad.instalment, 'note', ad.note), 'employee_advances', ad.id::text, 'payroll', null::uuid, null::uuid, null::uuid, ad.employee_id, null::bigint, null::numeric
    from public.employee_advances ad left join public.employees em on em.id = ad.employee_id
   where a_pay and (k is null or 'advance' = any (k)) and ad.adv_date between p_from and p_to and (ad.location_id is null or ad.location_id = any (locs)) and (p_loc is null or ad.location_id = p_loc)
     and (ne or (p_ent = 'employee' and ad.employee_id::text = p_eid) or (p_ent = 'staff' and em.profile_id::text = p_eid))
  union all   -- 21 price changes (item timelines)
  select ph.changed_at, public._rh_day(ph.changed_at), 'price_change', 'stock', null::int, public._rh_staff(ph.changed_by), ph.changed_by, ph.sell_price, null::numeric, null::text, 'price_change', 'done',
         jsonb_build_object('sell_price', ph.sell_price, 'cost_price', case when costok then ph.cost_price end, 'item', i.name_en, 'item_bn', i.name_bn, 'cost_hidden', not costok), 'item_price_history', ph.id::text, 'items',
         ph.item_id, null::uuid, null::uuid, null::uuid, null::bigint, null::numeric
    from public.item_price_history ph left join public.items i on i.id = ph.item_id
   where a_stock and p_ent = 'item' and p_loc is null and (k is null or 'price_change' = any (k)) and ph.changed_at >= t0 and ph.changed_at < t1 and ph.item_id::text = p_eid;
end $$;

-- ---------- day replay ----------
create or replace function public.rpt_hub_day(p_date date, p_loc int default null, p_kinds text[] default null, p_limit int default 100, p_offset int default 0)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0);
  a_sales boolean := public._rh_area_ok('sales'); a_cust boolean := public._rh_area_ok('customers'); a_cash boolean := public._rh_area_ok('cash'); a_stock boolean := public._rh_area_ok('stock');
  a_purch boolean := public._rh_area_ok('purchase'); a_exp boolean := public._rh_area_ok('expense'); a_pay boolean := public._rh_area_ok('payroll'); a_hr boolean := public._rh_area_ok('hr');
  a_ctl boolean := public._rh_area_ok('control'); a_acc boolean := public._rh_area_ok('accounts'); a_pos boolean := public._rh_area_ok('pos');
  locs int[] := public._rh_locs(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
  tot jsonb := '{}'::jsonb; rec jsonb := null; masked jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb;
  ev jsonb; kc jsonb; n bigint;
  s_n bigint; s_tot numeric; s_disc numeric; v_n bigint; v_amt numeric; r_n bigint; r_tot numeric; ref record; checks jsonb := '[]'::jsonb; allok boolean := true; ref_ok boolean;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if p_date is null then raise exception 'bad_date'; end if;
  if p_loc is not null and not (p_loc = any (locs)) then raise exception 'not allowed'; end if;
  -- what this person may not see (names only)
  if not (a_sales) then masked := masked || jsonb_build_array(jsonb_build_object('area', 'sales', 'kinds', jsonb_build_array('sale', 'void', 'return'))); end if;
  if not (a_cust or a_sales) then masked := masked || jsonb_build_array(jsonb_build_object('area', 'customers', 'kinds', jsonb_build_array('collection'))); end if;
  if not a_cash then masked := masked || jsonb_build_array(jsonb_build_object('area', 'cash', 'kinds', jsonb_build_array('cash_move', 'cash_short', 'other_income', 'money_transfer', 'handover'))); end if;
  if not a_pos then masked := masked || jsonb_build_array(jsonb_build_object('area', 'pos', 'kinds', jsonb_build_array('day_sheet'))); end if;
  if not a_stock then masked := masked || jsonb_build_array(jsonb_build_object('area', 'stock', 'kinds', jsonb_build_array('production', 'transfer_sent', 'transfer_received', 'transfer_cancelled', 'wastage', 'count_adjust', 'count_sheet', 'factory_sheet', 'transit_short'))); end if;
  if not a_purch then masked := masked || jsonb_build_array(jsonb_build_object('area', 'purchase', 'kinds', jsonb_build_array('purchase', 'purchase_return', 'supplier_payment', 'supplier_refund'))); end if;
  if not a_exp then masked := masked || jsonb_build_array(jsonb_build_object('area', 'expense', 'kinds', jsonb_build_array('expense', 'voucher'))); end if;
  if not a_pay then masked := masked || jsonb_build_array(jsonb_build_object('area', 'payroll', 'kinds', jsonb_build_array('payroll', 'advance'))); end if;
  if not a_hr then masked := masked || jsonb_build_array(jsonb_build_object('area', 'hr', 'kinds', jsonb_build_array('staff_status', 'staff_exit'))); end if;
  if not a_ctl then masked := masked || jsonb_build_array(jsonb_build_object('area', 'control', 'kinds', jsonb_build_array('approval', 'exception', 'exception_resolved'))); end if;
  if not a_acc then masked := masked || jsonb_build_array(jsonb_build_object('area', 'accounts', 'kinds', jsonb_build_array('period'))); end if;
  if not public._rh_area_ok('cost') then notes := notes || jsonb_build_array('cost_hidden'); end if;

  -- the one event set (read once)
  with e as materialized (select * from public._rh_events(p_date, p_date, p_loc, p_kinds))
  select (select count(*) from e),
         (select coalesce(jsonb_object_agg(z.kind, jsonb_build_object('n', z.c, 'amount', z.a)), '{}'::jsonb)
            from (select e1.kind, count(*) c, sum(e1.amount) filter (where coalesce(e1.status, 'done') not in ('void', 'cancelled', 'rejected')) a from e e1 group by e1.kind) z),
         (select coalesce(jsonb_agg(jsonb_build_object('ts', x.ts, 'time', to_char(x.ts at time zone 'Asia/Dhaka', 'HH24:MI'), 'day', x.day, 'kind', x.kind, 'area', x.area, 'loc', x.loc, 'who', x.who, 'who_id', x.who_id,
            'amount', x.amount, 'qty', x.qty, 'dir', x.dir, 'title', x.title, 'status', x.status, 'detail', x.detail, 'ref_table', x.ref_table, 'ref_id', x.ref_id, 'link', x.link, 'item_id', x.item_id,
            'cust_id', x.cust_id, 'sup_id', x.sup_id, 'emp_id', x.emp_id, 'batch_id', x.batch_id) order by x.ts, x.kind, x.ref_id), '[]'::jsonb)
            from (select * from e order by e.ts, e.kind, e.ref_id limit lim offset off) x)
    into n, kc, ev;

  -- day totals (computed from the tables with the same rules as the daily summary, not by adding the listed rows)
  if a_sales then
    select count(*), coalesce(sum(s.total), 0), coalesce(sum(s.discount), 0) into s_n, s_tot, s_disc from public.sales s
      where s.sale_date = p_date and s.status = 'done' and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc);
    select count(*), coalesce(sum(s.total), 0) into v_n, v_amt from public.sales s
      where s.sale_date = p_date and s.status = 'void' and s.location_id = any (locs) and (p_loc is null or s.location_id = p_loc);
    select count(*), coalesce(sum(r.amount), 0) into r_n, r_tot from public.sale_returns r
      where r.status = 'done' and r.created_at >= (p_date::timestamp at time zone 'Asia/Dhaka') and r.created_at < ((p_date + 1)::timestamp at time zone 'Asia/Dhaka') and r.location_id = any (locs) and (p_loc is null or r.location_id = p_loc);
    tot := tot || jsonb_build_object('sales_n', s_n, 'sales_total', s_tot, 'sales_discount', s_disc, 'void_n', v_n, 'void_amount', v_amt, 'returns_n', r_n, 'returns_total', r_tot,
                                     'net_sales', s_tot - case when net_on then r_tot else 0 end, 'returns_netted', net_on);
  end if;
  if a_cust or a_sales then
    tot := tot || jsonb_build_object('collections_total', (select coalesce(sum(p.amount), 0) from public.sale_payments p where p.kind = 'collection' and not p.voided
        and p.paid_at >= (p_date::timestamp at time zone 'Asia/Dhaka') and p.paid_at < ((p_date + 1)::timestamp at time zone 'Asia/Dhaka') and p.location_id = any (locs) and (p_loc is null or p.location_id = p_loc)));
  end if;
  if a_exp then
    tot := tot || jsonb_build_object('expense_total',
      (select coalesce(sum(q.amount), 0) from public.quick_expenses q where q.status = 'done' and q.exp_date = p_date and q.location_id = any (locs) and (p_loc is null or q.location_id = p_loc))
      + (select coalesce(sum(public._r2_num(x -> 'amount')), 0) from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) x
          where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date = p_date and e.location_id = any (locs) and (p_loc is null or e.location_id = p_loc) and not public.is_shadow('entries', e.id::text)));
  end if;
  if a_purch then
    tot := tot || jsonb_build_object('purchases_total', (select coalesce(sum(case when b.kind = 'return' then -b.total else b.total end), 0) from public.purchase_bills b where b.status = 'posted' and b.bill_date = p_date and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc)),
      'supplier_paid_total', (select coalesce(sum(sp.amount), 0) from public.supplier_payments sp where not sp.voided and sp.paid_at >= (p_date::timestamp at time zone 'Asia/Dhaka') and sp.paid_at < ((p_date + 1)::timestamp at time zone 'Asia/Dhaka')
          and (sp.location_id is null or sp.location_id = any (locs)) and (p_loc is null or sp.location_id = p_loc)));
  end if;
  tot := tot || jsonb_build_object('events', n);

  -- reconcile with the existing daily summary (biz_daily) for the sales figures
  if a_sales then
    if public.biz_ok() then
      begin
        select coalesce(sum(d.n), 0) sn, coalesce(sum(d.revenue), 0) rev, coalesce(sum(d.discount), 0) disc, coalesce(sum(d.void_n), 0) vn, coalesce(sum(d.void_amt), 0) va into ref
          from public.biz_daily(p_date, p_date, p_loc) d;
        checks := jsonb_build_array(
          jsonb_build_object('field', 'sales_n', 'hub', s_n, 'summary', ref.sn, 'ok', s_n = ref.sn),
          jsonb_build_object('field', 'net_sales', 'hub', s_tot - case when net_on then r_tot else 0 end, 'summary', ref.rev, 'ok', (s_tot - case when net_on then r_tot else 0 end) = ref.rev),
          jsonb_build_object('field', 'sales_discount', 'hub', s_disc, 'summary', ref.disc, 'ok', s_disc = ref.disc),
          jsonb_build_object('field', 'void_n', 'hub', v_n, 'summary', ref.vn, 'ok', v_n = ref.vn),
          jsonb_build_object('field', 'void_amount', 'hub', v_amt, 'summary', ref.va, 'ok', v_amt = ref.va));
        select bool_and((c ->> 'ok')::boolean) into allok from jsonb_array_elements(checks) c;
        rec := jsonb_build_object('status', case when allok then 'match' else 'mismatch' end, 'against', 'biz_daily', 'checks', checks);
      exception when others then
        rec := jsonb_build_object('status', 'not_available', 'against', 'biz_daily', 'why', 'summary_failed');
      end;
    else
      rec := jsonb_build_object('status', 'not_available', 'against', 'biz_daily', 'why', 'no_summary_right');
    end if;
  else
    rec := jsonb_build_object('status', 'not_available', 'against', 'biz_daily', 'why', 'no_sales_right');
  end if;

  return jsonb_build_object('generated_at', now(), 'filters', jsonb_build_object('date', p_date, 'loc', p_loc, 'kinds', p_kinds), 'total_events', n, 'limit', lim, 'offset', off,
    'events', ev, 'kind_counts', kc, 'totals', tot, 'reconcile', rec, 'masked', masked, 'notes', notes);
end $$;

revoke all on function public._rh_events(date, date, int, text[], text, text, boolean) from public, anon, authenticated;
revoke all on function public.rpt_hub_day(date, int, text[], int, int) from public, anon;
grant execute on function public.rpt_hub_day(date, int, text[], int, int) to authenticated;
