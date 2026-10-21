-- ============================================================
-- Phase 454 - RPT-C2 / R5 part 2 (reports #139 customer lifetime value, #140 complaints and returns per customer, #141 special-order (cake) history per customer, and the customer card). READ ONLY.
-- Run AFTER phase 453. New file only. Does not touch the CRM tables (phases 300-340). Paste twice = no error.
--
--   c2_customer_ltv(from, to, search, limit, customer)   all-time by default - NO 365-day cap (the hub report refuses ranges over 365 days). Orders, revenue, returns, net revenue, first and last sale, days
--        as a customer. Gross margin only with the cost right and only over the sales whose cost is fully known, with the coverage shown (sales with a known cost / all sales) - never an estimate.
--        Sales with no customer are counted apart so the reader sees how much of the revenue the table covers.
--   c2_customer_returns(from, to, search, customer)   sale returns (sale_returns) per customer + complaints written on the paper register 20-3, matched by the phone number written on the sheet.
--        A sheet with no phone, or a phone that is not a customer, cannot be linked: they are COUNTED apart (the paper form has the phone as an optional box).
--   c2_customer_special_orders(from, to, search, customer)   cake / custom orders per customer: app orders with a cake specification (phase 445) and paper 20-1 custom sheets, matched by mobile number;
--        flavours and weights as written, last special order, birthday and anniversary as entered (blank = not entered, never a guess).
--   c2_customer_card(customer)   one customer: terms and dues (phase 453), lifetime value, returns and complaints, the last special orders.
--   Open to the existing customer-report access (owner, report_customers, view_reports, or POS view). Mobile numbers are shown to POS viewers and people with the mobile right only.
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_credit_risk(date,boolean,text)') is null then raise exception 'phase454 needs phase453 pasted first'; end if;
end $guard$;

create or replace function public._c2_mob(p text) returns text language plpgsql immutable as $$
begin return public.norm_mobile(p); exception when others then return null; end $$;

-- #139
create or replace function public.c2_customer_ltv(p_from date default null, p_to date default null, p_search text default null, p_limit int default 200, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare lim int := least(greatest(coalesce(p_limit, 200), 1), 2000); mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); cost boolean := public.rpt_cost_ok();
        q text := nullif(lower(btrim(p_search)), ''); d1 date := coalesce(p_from, date '2000-01-01'); d2 date := coalesce(p_to, public._dhaka_today()); rows jsonb; sm jsonb; today date := public._dhaka_today();
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  if (p_from is null) <> (p_to is null) then raise exception 'bad_date: give both dates or none (none = all time)'; end if;
  if p_from is not null and p_to < p_from then raise exception 'bad_date'; end if;
  with s as (select x.id, x.customer_id, x.sale_date, x.total,
                    (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = x.id::text) as lrows,
                    (select count(*) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = x.id::text and coalesce(l.unit_cost, 0) <= 0) as lnocost,
                    (select sum(-l.qty_delta * l.unit_cost) from public.stock_ledger l where l.ref_type = 'sale' and l.ref_id = x.id::text) as gcost
               from public.sales x where x.status = 'done' and x.sale_date between d1 and d2),
       a as (select s.customer_id, count(*) as orders, sum(s.total) as revenue, min(s.sale_date) as first_sale, max(s.sale_date) as last_sale,
                    count(*) filter (where s.lrows > 0 and s.lnocost = 0) as costed, sum(s.total - s.gcost) filter (where s.lrows > 0 and s.lnocost = 0) as margin
               from s where s.customer_id is not null group by s.customer_id),
       rt as (select r.customer_id, count(*) as n, sum(r.amount) as amt from public.sale_returns r where r.status = 'done' and r.customer_id is not null and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 group by 1),
       j as (select cu.id, cu.name, cu.mobile, cu.type, cu.active, a.orders, a.revenue, coalesce(rt.amt, 0) as returns, coalesce(rt.n, 0) as return_count, a.revenue - coalesce(rt.amt, 0) as net_revenue, a.first_sale, a.last_sale,
                    a.last_sale - a.first_sale as days_as_customer, today - a.last_sale as days_since_last, round(a.revenue / a.orders, 2) as avg_order, a.costed, a.margin
               from a join public.customers cu on cu.id = a.customer_id left join rt on rt.customer_id = a.customer_id
              where (p_customer is null or cu.id = p_customer) and (q is null or lower(cu.name) like '%' || q || '%' or cu.mobile like '%' || q || '%')),
       t as (select * from j order by net_revenue desc, orders desc limit lim)
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', id, 'name', name, 'mobile', case when mob then mobile end, 'type', type, 'active', active, 'orders', orders, 'revenue', revenue, 'returns', returns, 'return_count', return_count,
            'net_revenue', net_revenue, 'avg_order', avg_order, 'first_sale', first_sale, 'last_sale', last_sale, 'days_as_customer', days_as_customer, 'days_since_last', days_since_last,
            'gross_margin', case when cost then margin end, 'sales_with_known_cost', case when cost then costed end) order by net_revenue desc, orders desc), '[]'::jsonb) from t),
         (select jsonb_build_object('customers', count(*), 'orders', coalesce(sum(orders), 0), 'revenue', coalesce(sum(revenue), 0), 'returns', coalesce(sum(returns), 0), 'net_revenue', coalesce(sum(net_revenue), 0),
            'shown', least(count(*), lim), 'window_from', p_from, 'window_to', p_to,
            'sales_without_customer', (select count(*) from s where s.customer_id is null), 'revenue_without_customer', (select coalesce(sum(total), 0) from s where s.customer_id is null)) from j)
    into rows, sm;
  return jsonb_build_object('all_time', p_from is null, 'notes', (case when cost then '[]'::jsonb else '["cost_hidden"]'::jsonb end) || '["margin_only_where_cost_known"]'::jsonb || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end),
    'summary', sm, 'rows', rows);
end $$;

-- #140
create or replace function public.c2_customer_returns(p_from date, p_to date, p_search text default null, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); q text := nullif(lower(btrim(p_search)), ''); rows jsonb; sm jsonb;
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  with r as (select x.customer_id, count(*) as returns, sum(x.amount) as ret_amt, max((x.created_at at time zone 'Asia/Dhaka')::date) as last_return,
                    (select y.reason_code from public.sale_returns y where y.customer_id = x.customer_id and y.status = 'done' and (y.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to group by y.reason_code order by count(*) desc, y.reason_code limit 1) as top_reason
               from public.sale_returns x where x.status = 'done' and x.customer_id is not null and (x.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and public.can_loc(x.location_id) group by x.customer_id),
       e as (select public._c2_mob(en.data ->> 'cust_phone') as mobile, en.id, en.entry_date,
                    (en.data ->> 'c_sick') = 'true' as sick, coalesce(public._c2_num(en.data -> 'refund_amt'), 0) as refund_amt,
                    array_remove(array[case when (en.data ->> 'c_taste') = 'true' then 'taste' end, case when (en.data ->> 'c_smell') = 'true' then 'smell' end, case when (en.data ->> 'c_broken') = 'true' then 'broken' end,
                                       case when (en.data ->> 'c_short') = 'true' then 'short' end, case when (en.data ->> 'c_wrong') = 'true' then 'wrong' end, case when (en.data ->> 'c_late') = 'true' then 'late' end,
                                       case when (en.data ->> 'c_staff') = 'true' then 'staff' end, case when (en.data ->> 'c_sick') = 'true' then 'sick' end, case when (en.data ->> 'c_other') = 'true' then 'other' end], null) as causes
               from public.entries en where en.form_code = '20-3' and en.status in ('submitted', 'approved') and en.entry_date between p_from and p_to and public.can_loc(en.location_id)),
       ec as (select cu.id as customer_id, count(*) as complaints, count(*) filter (where e.sick) as sick_cases, sum(e.refund_amt) as refund_amt, max(e.entry_date) as last_complaint,
                     (select coalesce(jsonb_object_agg(c, n), '{}'::jsonb) from (select u.c, count(*) as n from e e2 cross join lateral unnest(e2.causes) as u(c) where e2.mobile = cu.mobile group by u.c) z) as causes
                from e join public.customers cu on cu.mobile = e.mobile group by cu.id, cu.mobile),
       j as (select cu.id, cu.name, cu.mobile, coalesce(r.returns, 0) as returns, coalesce(r.ret_amt, 0) as return_amount, r.last_return, r.top_reason, coalesce(ec.complaints, 0) as complaints, coalesce(ec.sick_cases, 0) as sick_cases,
                    coalesce(ec.refund_amt, 0) as complaint_refunds, ec.last_complaint, coalesce(ec.causes, '{}'::jsonb) as causes
               from public.customers cu left join r on r.customer_id = cu.id left join ec on ec.customer_id = cu.id
              where (r.customer_id is not null or ec.customer_id is not null) and (p_customer is null or cu.id = p_customer) and (q is null or lower(cu.name) like '%' || q || '%' or cu.mobile like '%' || q || '%'))
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', id, 'name', name, 'mobile', case when mob then mobile end, 'returns', returns, 'return_amount', return_amount, 'last_return', last_return, 'top_reason', top_reason,
            'complaints', complaints, 'sick_cases', sick_cases, 'complaint_refunds', complaint_refunds, 'last_complaint', last_complaint, 'causes', causes) order by returns + complaints desc, return_amount desc), '[]'::jsonb) from j),
         jsonb_build_object('customers', (select count(*) from j), 'returns', (select coalesce(sum(returns), 0) from j), 'return_amount', (select coalesce(sum(return_amount), 0) from j), 'complaints_linked', (select coalesce(sum(complaints), 0) from j),
           'complaint_sheets_total', (select count(*) from e), 'complaint_sheets_without_phone', (select count(*) from e where e.mobile is null),
           'complaint_sheets_phone_not_a_customer', (select count(*) from e where e.mobile is not null and not exists (select 1 from public.customers c2 where c2.mobile = e.mobile)),
           'returns_without_customer', (select count(*) from public.sale_returns x where x.status = 'done' and x.customer_id is null and (x.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to and public.can_loc(x.location_id)))
    into rows, sm;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["complaints_matched_by_phone","paper_20_3_phone_optional"]'::jsonb || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end), 'summary', sm, 'rows', rows);
end $$;

-- the next yearly date (birthday, anniversary) on or after today; 29 February falls on 1 March in a year that has none
create or replace function public._c2_next_annual(p_date date, p_today date) returns date language plpgsql immutable as $$
declare y int := extract(year from p_today)::int; d date;
begin
  if p_date is null then return null; end if;
  for i in 0..1 loop
    begin d := make_date(y + i, extract(month from p_date)::int, extract(day from p_date)::int);
    exception when others then d := make_date(y + i, 3, 1); end;
    if d >= p_today then return d; end if;
  end loop;
  return null;
end $$;

-- #141
create or replace function public.c2_customer_special_orders(p_from date, p_to date, p_search text default null, p_customer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); q text := nullif(lower(btrim(p_search)), ''); rows jsonb; per jsonb; cnt int; unmatched int; today date := public._dhaka_today();
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  with base as (select * from public._c2_orders_base(p_from, p_to, null, 'order')),
       t as (
         select 'app'::text as source, b.ref, b.order_id, null::uuid as entry_id, public._c2_mob(o.customer_mobile) as mobile, b.customer_name, b.order_date, b.promised_date as delivery_date, b.status, b.total,
                c.flavour, c.weight_kg, c.message, c.design
           from base b join public.online_orders o on o.id = b.order_id join public.order_cake_specs c on c.order_id = b.order_id and c.state = 'active' where b.source = 'app'
         union all
         select 'paper_20_1', b.ref, null::uuid, b.entry_id, public._c2_mob(e.data ->> 'cust_phone'), b.customer_name, b.order_date, b.promised_date, b.status, b.total,
                nullif(btrim(i.v ->> 'desc'), ''), null::numeric, nullif(btrim(i.v ->> 'msg'), ''), nullif(btrim(i.v ->> 'design'), '')
           from base b join public.entries e on e.id = b.entry_id
           cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'items') = 'array' and jsonb_array_length(e.data -> 'items') > 0 then e.data -> 'items' else '[{}]'::jsonb end) as i(v)
          where b.source = 'paper_20_1' and b.order_type = 'cake'),
       m as (select t.*, cu.id as customer_id, cu.name as cname, cu.mobile as cmobile, cu.birthday, cu.anniversary from t left join public.customers cu on cu.mobile = t.mobile
              where (p_customer is null or cu.id = p_customer) and (q is null or lower(coalesce(cu.name, t.customer_name, '')) like '%' || q || '%' or coalesce(t.mobile, '') like '%' || q || '%'))
  select (select coalesce(jsonb_agg(jsonb_build_object('customer_id', customer_id, 'name', coalesce(cname, customer_name), 'mobile', case when mob then mobile end, 'source', source, 'ref', ref, 'order_id', order_id, 'entry_id', entry_id,
            'order_date', order_date, 'delivery_date', delivery_date, 'status', status, 'total', total, 'flavour', flavour, 'weight_kg', weight_kg, 'message', message, 'design', design) order by order_date desc, ref), '[]'::jsonb) from m),
         (select coalesce(jsonb_agg(jsonb_build_object('customer_id', z.customer_id, 'name', z.cname, 'mobile', case when mob then z.cmobile end, 'special_orders', z.n, 'first', z.first_d, 'last', z.last_d, 'flavours', z.flavours,
            'birthday', z.birthday, 'anniversary', z.anniversary, 'next_birthday_in_days', case when z.birthday is null then null else public._c2_next_annual(z.birthday, today) - today end,
            'next_anniversary_in_days', case when z.anniversary is null then null else public._c2_next_annual(z.anniversary, today) - today end) order by z.n desc, z.last_d desc), '[]'::jsonb) from (
            select customer_id, cname, cmobile, birthday, anniversary, count(*) as n, min(order_date) as first_d, max(order_date) as last_d,
                   (select coalesce(jsonb_agg(f), '[]'::jsonb) from (select distinct lower(m2.flavour) as f from m m2 where m2.customer_id = m.customer_id and m2.flavour is not null limit 5) fl) as flavours
              from m where customer_id is not null group by customer_id, cname, cmobile, birthday, anniversary) z),
         (select count(*) from m), (select count(*) from m where customer_id is null), (select count(distinct customer_id) from m where customer_id is not null)
    into rows, per, cnt, unmatched;
  return jsonb_build_object('from', p_from, 'to', p_to, 'module_on', public.rule_on('online_orders_on'), 'notes', '["matched_by_mobile","sources_not_merged"]'::jsonb || (case when public.rule_on('online_orders_on') then '[]'::jsonb else '["module_off"]'::jsonb end) || (case when mob then '[]'::jsonb else '["mobile_hidden"]'::jsonb end),
    'summary', jsonb_build_object('special_order_rows', cnt, 'rows_without_a_customer_match', unmatched, 'customers', (select count(*) from jsonb_array_elements(per))), 'customers', per, 'rows', rows);
end $$;

-- the customer card (drill-down from any customer report)
create or replace function public.c2_customer_card(p_customer uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.customers; mob boolean := public.can_do('POS', 'view') or public.rpt_mobile_ok(); risk jsonb; ltv jsonb; ret jsonb; so jsonb; d1 date := public._dhaka_today() - 365; d2 date := public._dhaka_today();
begin
  if not public.c2_can_read_customers() then raise exception 'not allowed'; end if;
  select * into c from public.customers where id = p_customer;
  if not found then raise exception 'customer_not_found'; end if;
  risk := public.c2_credit_risk(null, false, c.mobile);
  ltv := public.c2_customer_ltv(null, null, null, 1, c.id);
  ret := public.c2_customer_returns(d1, d2, null, c.id);
  so := public.c2_customer_special_orders(d1, d2, null, c.id);
  return jsonb_build_object('customer', jsonb_build_object('id', c.id, 'name', c.name, 'mobile', case when mob then c.mobile end, 'type', c.type, 'active', c.active, 'credit_limit', c.credit_limit, 'credit_days', c.credit_days,
            'default_credit_days', public.rule_num('credit_default_days'), 'birthday', c.birthday, 'anniversary', c.anniversary, 'customer_since', c.customer_since),
    'credit', (select r from jsonb_array_elements(risk -> 'rows') r where r ->> 'customer_id' = c.id::text limit 1), 'credit_notes', risk -> 'notes',
    'ltv', (select r from jsonb_array_elements(ltv -> 'rows') r limit 1), 'returns_last_365_days', (select r from jsonb_array_elements(ret -> 'rows') r limit 1), 'returns_summary', ret -> 'summary',
    'special_orders_last_365_days', so -> 'rows', 'can_edit_terms', public.is_owner() or public.has_grant('customer_manage'));
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
