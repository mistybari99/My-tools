-- Phase 467 (RPT-C3, package R9 part 3) - PLANNING: expected cash in / out calendar (#188), upcoming supplier payments (#189), expected wastage and expiry risk (#190).
-- Paste AFTER phase466. Paste-twice safe. Read-only functions. No earlier phase file is edited.
--
--   fc_supplier_payments  open supplier bills with a DUE DATE = bill date + the supplier's credit days. Overdue, due inside the horizon, and "date unknown" (no credit days or no bill date,
--                         e.g. an opening balance) are kept apart. An unknown date is never placed on the calendar.
--   fc_cash_calendar      known future money only, by day:
--                         IN   open online orders: the balance (subtotal - discount + delivery charge - advance) on the delivery date;
--                              customer dues: on oldest bill date + the customer's credit days WHEN the customers table has credit_days (otherwise "date unknown");
--                         OUT  supplier bills as above; salary: bills of an approved payroll run not yet paid, else (only if the owner set the pay day, fc_payroll_day) the LAST payroll run
--                              repeated on the next pay day - marked as an assumption; bank charges of recurring transfers.
--                         Recurring transfers between own accounts are listed apart and are not in the net. No opening balance, no forecast sales and no tax are included.
--   fc_expiry_risk        stock batches with an expiry date inside N days (the person types N, or the existing setting report_expiry_soon_days): units expected to be sold before expiry
--                         (first-expiring-first-out, the window's average sales per calendar day continuing) and the rest = at risk; already-expired stock apart; value at cost for people who may see cost.
-- Access: cash calendar / supplier payments rpt_access('cash') (supplier payments also 'purchase'); expiry rpt_access('stock'). Salary lines only for the owner and salary_view holders.
-- Test data only (test_*).

do $g$ begin
  if to_regprocedure('public.fc_raw_purchase(integer,integer,integer,text,boolean)') is null then raise exception 'phase467 needs phase466 first'; end if;
end $g$;

-- ---------- supplier bills with due dates ----------
create or replace function public._c3_sup_due(locs int[], p_all_places boolean)
returns table (supplier_id uuid, supplier text, bill_id uuid, bill_no text, bill_date date, credit_days int, open_amt numeric, due_date date, location_id int)
language sql stable security definer set search_path = public as $$
  select o.supplier_id, s.name, o.bill_id, o.bill_no, o.bill_date, s.credit_days, o.open_amt,
         case when o.bill_date is not null and s.credit_days is not null then o.bill_date + s.credit_days end, o.location_id
    from public._sup_open(null) o join public.suppliers s on s.id = o.supplier_id
   where o.open_amt > 0 and ((o.location_id is null and p_all_places) or o.location_id = any (locs))
$$;

create or replace function public.fc_supplier_payments(p_days int, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; td date := public._c3_today(); rows_ jsonb; tot jsonb; cov jsonb;
begin
  if not public.is_active() or not (public.rpt_access('cash') or public.rpt_access('purchase')) then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'bad_range'; end if;
  locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('supplier_id', d.supplier_id, 'supplier', d.supplier, 'bill_id', d.bill_id, 'bill_no', d.bill_no, 'bill_date', d.bill_date, 'credit_days', d.credit_days,
        'open_amount', d.open_amt, 'due_date', d.due_date, 'days_overdue', case when d.due_date < td then td - d.due_date end, 'location_id', d.location_id,
        'status', case when d.due_date is null then 'date_unknown' when d.due_date < td then 'overdue' when d.due_date < td + p_days then 'due' else 'later' end)
        order by d.due_date nulls last, d.supplier), '[]'::jsonb) into rows_ from public._c3_sup_due(locs, p_loc is null) d;
  select jsonb_build_object('overdue', round(coalesce(sum(d.open_amt) filter (where d.due_date < td), 0), 2), 'due_in_horizon', round(coalesce(sum(d.open_amt) filter (where d.due_date >= td and d.due_date < td + p_days), 0), 2),
         'later', round(coalesce(sum(d.open_amt) filter (where d.due_date >= td + p_days), 0), 2), 'date_unknown', round(coalesce(sum(d.open_amt) filter (where d.due_date is null), 0), 2),
         'all_open', round(coalesce(sum(d.open_amt), 0), 2)),
         jsonb_build_object('bills', count(*), 'bills_with_a_date', count(*) filter (where d.due_date is not null), 'dated_pct', case when count(*) > 0 then round(100.0 * count(*) filter (where d.due_date is not null) / count(*), 1) end,
           'suppliers', count(distinct d.supplier_id), 'suppliers_without_credit_days', count(distinct d.supplier_id) filter (where d.credit_days is null))
    into tot, cov from public._c3_sup_due(locs, p_loc is null) d;
  return jsonb_build_object('key', 'fc_suppliers', 'from', td, 'days', p_days, 'loc', p_loc, 'rows', rows_, 'totals', tot, 'coverage', cov,
    'notes', jsonb_build_array('due_date_is_bill_date_plus_credit_days', 'unknown_date_is_not_placed_on_the_calendar', 'payments_already_made_are_taken_off_oldest_bill_first', 'no_discount_or_penalty_modelled'),
    'basis', 'Open supplier bills with the date they fall due. A supplier with no credit days has no due date; set it on the supplier to see it here.');
end $$;

-- ---------- #188 expected cash in / out ----------
create or replace function public.fc_cash_calendar(p_days int, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; td date := public._c3_today(); sal boolean; pay_day int := public.rule_num('fc_payroll_day')::int; has_cd boolean; ev jsonb := '[]'; cust_cd jsonb := '{}'; r record; days_ jsonb; buckets jsonb; tot jsonb;
        last_run record; outstanding numeric; outstanding_n int; nxt date; ass jsonb := '[]'; hid boolean := false;
begin
  if not public.is_active() or not public.rpt_access('cash') then raise exception 'not allowed'; end if;
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'bad_range'; end if;
  locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  sal := public.is_owner() or public.rpt_grant('salary_view');
  -- build the event list in a temp-free way: one jsonb array of {d, kind, dir, amt, ref, assumed}
  -- orders
  for r in select oo.id, oo.order_no, oo.delivery_date as d, oo.subtotal - oo.discount + oo.delivery_charge - oo.advance as bal from public.online_orders oo
            where oo.status in ('new', 'confirmed', 'packed') and oo.delivery_date is not null and oo.location_id = any (locs) and (oo.subtotal - oo.discount + oo.delivery_charge - oo.advance) > 0 loop
    ev := ev || jsonb_build_object('d', r.d, 'kind', 'order_balance', 'dir', 'in', 'amt', r.bal, 'ref', 'Order #' || r.order_no);
  end loop;
  -- customers (credit days only if that column exists)
  has_cd := exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'customers' and column_name = 'credit_days');
  if has_cd then execute 'select coalesce(jsonb_object_agg(id::text, credit_days), ''{}''::jsonb) from public.customers where credit_days is not null' into cust_cd; end if;
  for r in select c.id, c.name, c.balance, c.oldest from public.customer_dues() c loop
    if has_cd and r.oldest is not null and cust_cd ? r.id::text then
      ev := ev || jsonb_build_object('d', r.oldest + (cust_cd ->> r.id::text)::int, 'kind', 'customer_due', 'dir', 'in', 'amt', r.balance, 'ref', r.name);
    else
      ev := ev || jsonb_build_object('d', null, 'kind', 'customer_due', 'dir', 'in', 'amt', r.balance, 'ref', r.name);
    end if;
  end loop;
  -- suppliers
  for r in select * from public._c3_sup_due(locs, p_loc is null) loop
    ev := ev || jsonb_build_object('d', r.due_date, 'kind', 'supplier_bill', 'dir', 'out', 'amt', r.open_amt, 'ref', r.supplier || coalesce(' / ' || r.bill_no, ''));
  end loop;
  -- salary
  if not sal then hid := true;
  else
    select coalesce(sum(l.net - coalesce(l.paid_amount, 0)), 0), count(*) into outstanding, outstanding_n from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
     where pr.status = 'approved' and l.active and l.payment_status in ('unpaid', 'partly') and l.location_id = any (locs);
    if outstanding > 0 then
      nxt := case when pay_day is null then null else (case when make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28)) >= td
            then make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28)) else (make_date(extract(year from td)::int, extract(month from td)::int, 1) + interval '1 month')::date + least(pay_day, 28) - 1 end) end;
      ev := ev || jsonb_build_object('d', nxt, 'kind', 'salary_owed', 'dir', 'out', 'amt', outstanding, 'ref', 'Approved payroll not yet paid (' || outstanding_n || ' lines)');
    elsif pay_day is not null then
      select pr.month, sum(l.net) as net into last_run from public.payroll_runs pr join public.payroll_lines l on l.run_id = pr.id and l.active
       where pr.status in ('approved', 'paid') and pr.location_id = any (locs) group by pr.month order by pr.month desc limit 1;
      if last_run.net is not null then
        nxt := case when make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28)) >= td then make_date(extract(year from td)::int, extract(month from td)::int, least(pay_day, 28))
                    else (make_date(extract(year from td)::int, extract(month from td)::int, 1) + interval '1 month')::date + least(pay_day, 28) - 1 end;
        ev := ev || jsonb_build_object('d', nxt, 'kind', 'salary_assumed', 'dir', 'out', 'amt', last_run.net, 'ref', 'Same as the payroll of ' || to_char(last_run.month, 'YYYY-MM'), 'assumed', true);
        ass := ass || to_jsonb('salary repeats the last payroll run on day ' || pay_day || ' of the month (the owner set the day)');
      end if;
    end if;
  end if;
  -- recurring transfers: fees are real money out, the transfer itself moves between own accounts
  for r in select m.id, m.name, m.amount, m.fee, m.day_of_month, m.start_date, m.end_date,
                  (date_trunc('month', td) + (g * interval '1 month'))::date as mon from public.money_recurring m cross join generate_series(0, (p_days / 28) + 1) g
            where m.active and (m.location_id is null or m.location_id = any (locs)) loop
    declare od date := r.mon + (least(r.day_of_month, extract(day from (r.mon + interval '1 month' - interval '1 day'))::int) - 1);
    begin
      if od >= td and od < td + p_days and od >= r.start_date and (r.end_date is null or od <= r.end_date) then
        ev := ev || jsonb_build_object('d', od, 'kind', 'recurring_transfer', 'dir', 'transfer', 'amt', r.amount, 'ref', r.name);
        if coalesce(r.fee, 0) > 0 then ev := ev || jsonb_build_object('d', od, 'kind', 'transfer_fee', 'dir', 'out', 'amt', r.fee, 'ref', r.name); end if;
      end if;
    end;
  end loop;
  with e as (select (x ->> 'd')::date as d, x ->> 'kind' as kind, x ->> 'dir' as dir, (x ->> 'amt')::numeric as amt, x ->> 'ref' as ref, coalesce((x ->> 'assumed')::boolean, false) as assumed from jsonb_array_elements(ev) x)
  select coalesce(jsonb_agg(jsonb_build_object('date', z.d, 'in', z.i, 'out', z.o, 'transfers', z.t, 'net_known', z.i - z.o, 'items', z.items) order by z.d), '[]'::jsonb) into days_
    from (select e.d, round(sum(e.amt) filter (where e.dir = 'in'), 2) as i0, coalesce(round(sum(e.amt) filter (where e.dir = 'in'), 2), 0) as i, coalesce(round(sum(e.amt) filter (where e.dir = 'out'), 2), 0) as o,
                 coalesce(round(sum(e.amt) filter (where e.dir = 'transfer'), 2), 0) as t, jsonb_agg(jsonb_build_object('kind', e.kind, 'dir', e.dir, 'amount', e.amt, 'ref', e.ref, 'assumed', e.assumed) order by e.kind, e.ref) as items
            from e where e.d >= td and e.d < td + p_days group by e.d) z;
  with e as (select (x ->> 'd')::date as d, x ->> 'kind' as kind, x ->> 'dir' as dir, (x ->> 'amt')::numeric as amt from jsonb_array_elements(ev) x)
  select jsonb_build_object('overdue_in', round(coalesce(sum(amt) filter (where dir = 'in' and d < td), 0), 2), 'overdue_out', round(coalesce(sum(amt) filter (where dir = 'out' and d < td), 0), 2),
         'date_unknown_in', round(coalesce(sum(amt) filter (where dir = 'in' and d is null), 0), 2), 'date_unknown_out', round(coalesce(sum(amt) filter (where dir = 'out' and d is null), 0), 2)),
         jsonb_build_object('in', round(coalesce(sum(amt) filter (where dir = 'in' and d >= td and d < td + p_days), 0), 2), 'out', round(coalesce(sum(amt) filter (where dir = 'out' and d >= td and d < td + p_days), 0), 2),
           'in_dated_later', round(coalesce(sum(amt) filter (where dir = 'in' and d >= td + p_days), 0), 2), 'out_dated_later', round(coalesce(sum(amt) filter (where dir = 'out' and d >= td + p_days), 0), 2))
    into buckets, tot from e;
  return jsonb_build_object('key', 'fc_cash', 'from', td, 'days', p_days, 'loc', p_loc, 'rows', days_, 'buckets', buckets, 'totals', tot,
    'assumptions', ass, 'coverage', jsonb_build_object('customer_credit_days_column', has_cd, 'salary_pay_day_set', pay_day is not null),
    'notes', jsonb_build_array('only_known_future_money', 'no_opening_balance_no_forecast_sales_no_tax', 'unknown_dates_are_not_placed_on_the_calendar', 'transfers_between_own_accounts_are_not_in_the_net') ||
             case when has_cd then '[]'::jsonb else jsonb_build_array('customers_have_no_credit_days_so_dues_are_undated') end ||
             case when hid then jsonb_build_array('salary_hidden') else '[]'::jsonb end,
    'basis', 'Money that is already owed or promised, on the day it is expected. It is not a prediction of sales or of the cash balance.');
end $$;

-- ---------- #190 expected wastage and expiry risk ----------
create or replace function public.fc_expiry_risk(p_loc int, p_days int default null, p_window int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; n int := coalesce(p_days, public.rule_num('report_expiry_soon_days')::int); w int := coalesce(p_window, public.rule_num('fc_window_days')::int); td date := public._c3_today(); d1 date; first_sale date; eff int;
        cost_ok boolean := public.rpt_cost_ok(); rows_ jsonb; expired jsonb; noexp bigint; tot jsonb;
begin
  perform public._c3_need('stock'); locs := public._c3_locs(p_loc);
  if p_loc is not null and cardinality(locs) = 0 then raise exception 'not allowed'; end if;
  if n is null or w is null then
    return jsonb_build_object('key', 'fc_expiry', 'data_needed', (case when n is null then jsonb_build_array('report_expiry_soon_days') else '[]'::jsonb end) || (case when w is null then jsonb_build_array('fc_window_days') else '[]'::jsonb end),
      'rows', '[]'::jsonb, 'notes', jsonb_build_array('days_not_set'), 'basis', 'Type the days (or let the owner set the settings). Nothing is assumed.');
  end if;
  if n < 1 or n > 365 or w < 7 or w > 365 then raise exception 'bad_range'; end if;
  d1 := td - w;
  select min(s.sale_date) into first_sale from public.sales s where s.status = 'done' and s.location_id = any (locs);
  eff := greatest(td - greatest(d1, coalesce(first_sale, td)), 1);
  with u as (select l.item_id, l.location_id, sum(-l.qty_delta) as units from public.stock_ledger l
              where l.reason in ('sale_out', 'sale_void_in', 'sale_return') and l.location_id = any (locs) and (l.made_at at time zone 'Asia/Dhaka')::date between d1 and td - 1 group by 1, 2),
  wa as (select s.item_id, s.location_id, sum(s.qty) as q from public.stock_wastage s where s.location_id = any (locs) and (s.made_at at time zone 'Asia/Dhaka')::date between d1 and td - 1 group by 1, 2),
  b as (select b.id, b.item_id, b.location_id, b.batch_no, b.qty_remaining, b.expires_at, b.made_at, (b.expires_at at time zone 'Asia/Dhaka')::date as exp_d,
               greatest(extract(epoch from (b.expires_at - now())) / 86400.0, 0) as dte,
               coalesce(sum(b.qty_remaining) over (partition by b.item_id, b.location_id order by b.expires_at, b.id rows between unbounded preceding and 1 preceding), 0) as before_
          from public.stock_batches b where b.qty_remaining > 0 and b.expires_at is not null and b.expires_at > now() and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc)),
  c as (select b.*, greatest(coalesce(u.units, 0), 0) / eff as per_day, wa.q as wasted,
               coalesce(ic.cost_price, (select sb.avg_cost from public.stock_balance sb where sb.item_id = b.item_id and sb.location_id = b.location_id)) as uc
          from b left join u on u.item_id = b.item_id and u.location_id = b.location_id left join wa on wa.item_id = b.item_id and wa.location_id = b.location_id left join public.item_costs ic on ic.item_id = b.item_id),
  r as (select c.*, least(c.qty_remaining, greatest(c.per_day * c.dte - c.before_, 0)) as sold_before from c)
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', r.id, 'batch_no', r.batch_no, 'item_id', i.id, 'code', i.code, 'name_en', i.name_en, 'name_bn', i.name_bn, 'location_id', r.location_id, 'qty_remaining', r.qty_remaining,
           'expires_on', r.exp_d, 'days_to_expiry', round(r.dte, 1), 'avg_sold_per_day', round(r.per_day, 4), 'expected_sold_before_expiry', round(r.sold_before, 3), 'at_risk_qty', round(r.qty_remaining - r.sold_before, 3),
           'at_risk_value', case when cost_ok and r.uc is not null then round((r.qty_remaining - r.sold_before) * r.uc, 2) end, 'wasted_in_window', r.wasted,
           'no_sales_history', coalesce(r.per_day, 0) = 0) order by r.exp_d, i.code), '[]'::jsonb)
    into rows_ from r join public.items i on i.id = r.item_id where r.exp_d <= td + n and r.expires_at > now();
  select coalesce(jsonb_agg(jsonb_build_object('batch_id', b.id, 'batch_no', b.batch_no, 'code', i.code, 'name_en', i.name_en, 'location_id', b.location_id, 'qty_remaining', b.qty_remaining, 'expired_on', (b.expires_at at time zone 'Asia/Dhaka')::date) order by b.expires_at), '[]'::jsonb)
    into expired from public.stock_batches b join public.items i on i.id = b.item_id where b.qty_remaining > 0 and b.expires_at <= now() and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc);
  select count(*) into noexp from public.stock_batches b where b.qty_remaining > 0 and b.expires_at is null and b.location_id = any (locs) and (p_loc is null or b.location_id = p_loc);
  select jsonb_build_object('batches', jsonb_array_length(rows_), 'at_risk_value', case when cost_ok then (select round(sum((x ->> 'at_risk_value')::numeric), 2) from jsonb_array_elements(rows_) x) end,
         'at_risk_value_missing_cost', case when cost_ok then (select count(*) from jsonb_array_elements(rows_) x where x ->> 'at_risk_value' is null and (x ->> 'at_risk_qty')::numeric > 0) end) into tot;
  return jsonb_build_object('key', 'fc_expiry', 'loc', p_loc, 'days', n, 'window_days', w, 'rows', rows_, 'already_expired', expired, 'totals', tot,
    'assumptions', jsonb_build_object('sales_per_day', 'units sold in the window / calendar days of the window (' || eff || '), continuing unchanged', 'order_of_use', 'first expiring batch first', 'no_new_stock_assumed', true,
        'batches_without_expiry_not_covered', noexp),
    'notes', jsonb_build_array('at_risk_is_stock_left_after_expected_sales_not_a_prediction_of_waste', 'no_restock_or_price_cut_modelled', 'batches_without_expiry_are_not_covered') || case when cost_ok then '[]'::jsonb else jsonb_build_array('cost_hidden') end,
    'basis', 'For each batch expiring within ' || n || ' days: units the shop is expected to sell before it expires (the average of the last ' || w || ' days, oldest batch first) and the units that would be left.');
end $$;

revoke all on function public._c3_sup_due(int[], boolean) from public, anon, authenticated;
revoke all on function public.fc_supplier_payments(int, int), public.fc_cash_calendar(int, int), public.fc_expiry_risk(int, int, int) from public, anon;
grant execute on function public.fc_supplier_payments(int, int), public.fc_cash_calendar(int, int), public.fc_expiry_risk(int, int, int) to authenticated;
notify pgrst, 'reload schema';
