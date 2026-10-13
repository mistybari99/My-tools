-- ============================================================
-- PHASE 25 (report builder 25): reports on engine 3 (needs phase24; read-only, additive, paste-twice safe)
--   s10_orders  S10  orders / online / delivery            (20-1, 20-6)
--   d5_lapsed   D5   lapsed customers, new vs repeat       (sales)
--   m1_rfm      M1   RFM customer segments                 (sales)
--   x2_bypass   X2   releases / emergency / grant use      (release_requests, emergency_requests)
--   x3_audit_log X3  audit & correction log (owner only)   (audit_log)
--   x4_compliance X4 form submission compliance            (entries 14-1, 10-1)
--   x5_staff_trend X5 staff indicators, monthly            (sales, same logic as biz_staff)
--   g2_paper_numbers G2 duplicate / out-of-order paper no. (entries.data.paper_no)
--   k3_store_ledger K3 store ledger per item and kind      (stock_ledger; quantities only)
--   e2_expense_trend E2 expense trend vs previous period   (10-2)
--   e3_weak_control E3 no-receipt / over-limit / imprest   (10-2, 14-1)
--   e4_marketing_limit E4 marketing spend vs head limit    (18-1, option_lists, location_settings)
--   w1_cash_flow W1  daily cash flow per location          (_daybook_lines*)
--   w2_handover_vs_hub W2 handover (10-1) vs hub count     (10-1, entry_counts, check_data)
-- ============================================================

-- ---------- S10 orders, online & delivery ----------
create or replace function public._r3q_s10_orders(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('source', '20-1', 'channel', x.channel, 'online', x.online, 'delivery', x.delivery, 'orders', count(*),
      'amount', coalesce(sum(x.total), 0), 'advance', coalesce(sum(x.adv), 0), 'balance', coalesce(sum(x.total - x.disc - x.adv), 0),
      'handed', count(*) filter (where x.signed), 'not_collected', count(*) filter (where x.nc), 'returned', null, 'delivery_charge', null)
    from (select coalesce(nullif(btrim(e.data ->> 'channel'), ''), '-') as channel, coalesce(nullif(btrim(e.data ->> 'online'), ''), '-') as online,
                 coalesce(nullif(btrim(e.data ->> 'deliv_by'), ''), '-') as delivery,
                 coalesce(public._r2_num(e.data -> 'total'), 0) as total, coalesce(public._r2_num(e.data -> 'discount'), 0) as disc, coalesce(public._r2_num(e.data -> 'advance'), 0) as adv,
                 (e.data ->> 'cust_signed') = 'true' as signed, (e.data ->> 'not_collected') = 'true' as nc
            from public.entries e
           where e.form_code = '20-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) x
   group by x.channel, x.online, x.delivery
  union all
  select jsonb_build_object('source', '20-6', 'channel', 'ledger', 'online', y.platform, 'delivery', y.delivery, 'orders', count(*),
      'amount', coalesce(sum(y.amt), 0), 'advance', null, 'balance', null,
      'handed', count(*) filter (where y.outcome = 'handed'), 'not_collected', null, 'returned', count(*) filter (where y.outcome = 'returned'),
      'delivery_charge', coalesce(sum(y.dch), 0))
    from (select coalesce(nullif(lower(btrim(l ->> 'platform')), ''), '-') as platform, coalesce(nullif(btrim(l ->> 'delivery'), ''), '-') as delivery,
                 public._r2_num(l -> 'amt') as amt, public._r2_num(l -> 'dcharge') as dch, l ->> 'outcome' as outcome
            from public.entries e
            cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
           where e.form_code = '20-6' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) y
   group by y.platform, y.delivery;
$$;

-- ---------- D5 lapsed & new vs repeat customers ----------
create or replace function public._r3q_d5_lapsed(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with s as (select x.customer_id, x.sale_date, x.total from public.sales x
              where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs) and x.sale_date <= d2),
  c as (select customer_id, min(sale_date) as first_d, max(sale_date) as last_d, count(*) as n_all,
               count(*) filter (where sale_date >= d1) as n_p, coalesce(sum(total) filter (where sale_date >= d1), 0) as amt_p
          from s group by customer_id)
  select jsonb_build_object('customer_id', cu.id, 'name', cu.name, 'mobile', cu.mobile,
      'kind', case when c.first_d >= d1 then 'new' when c.n_p > 0 then 'repeat' else 'lapsed' end,
      'first_date', c.first_d, 'last_date', c.last_d, 'days_silent', d2 - c.last_d, 'orders_period', c.n_p, 'amount_period', c.amt_p, 'orders_total', c.n_all)
    from c join public.customers cu on cu.id = c.customer_id
   where c.n_p > 0 or c.last_d >= d1 - 180;
$$;

-- ---------- M1 RFM segments (window = the chosen period) ----------
create or replace function public._r3q_m1_rfm(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with c as (select x.customer_id, max(x.sale_date) as last_d, count(*) as n, coalesce(sum(x.total), 0) as amt
               from public.sales x where x.status = 'done' and x.customer_id is not null and x.location_id = any (locs) and x.sale_date between d1 and d2
              group by x.customer_id)
  select jsonb_build_object('customer_id', cu.id, 'name', cu.name, 'mobile', cu.mobile,
      'segment', case when c.n >= 3 and d2 - c.last_d <= 30 then 'Champion' when c.n >= 2 and d2 - c.last_d > 60 then 'At-risk' when c.n = 1 then 'One-time' else 'Regular' end,
      'recency_days', d2 - c.last_d, 'frequency', c.n, 'monetary', c.amt, 'last_date', c.last_d)
    from c join public.customers cu on cu.id = c.customer_id;
$$;

-- ---------- X2 releases / emergency / grant use ----------
create or replace function public._r3q_x2_bypass(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('staff_id', u.staff, 'staff_name', max(pr.full_name), 'kind', u.kind, 'code', u.code, 'requests', count(*),
      'approved', count(*) filter (where u.st in ('approved', 'used')), 'rejected', count(*) filter (where u.st = 'rejected'),
      'pending', count(*) filter (where u.st = 'pending'), 'other', count(*) filter (where u.st in ('expired', 'cancelled')), 'amount', coalesce(sum(u.amt), 0))
    from (select coalesce(r.requested_staff, '-') as staff, 'release'::text as kind, r.flag_code as code, r.status as st, r.flag_amount as amt
            from public.release_requests r join public.entries e on e.id = r.entry_id
           where (r.requested_at at time zone 'Asia/Dhaka')::date between d1 and d2 and e.location_id = any (locs)
          union all
          select coalesce(q.requested_staff, '-'), 'emergency', q.grant_code, q.status, q.amount
            from public.emergency_requests q
           where (q.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and q.location_id = any (locs)) u
    left join public.profiles pr on pr.staff_id = u.staff
   group by u.staff, u.kind, u.code;
$$;

-- ---------- X3 audit log (owner only) ----------
create or replace function public._r3q_x3_audit_log(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('table_name', a.table_name, 'action', a.action, 'staff_id', coalesce(a.staff_id, '-'), 'events', count(*),
      'first_day', min((a.at at time zone 'Asia/Dhaka')::date), 'last_day', max((a.at at time zone 'Asia/Dhaka')::date))
    from public.audit_log a
   where cardinality(locs) > 0 and (a.at at time zone 'Asia/Dhaka')::date between d1 and d2
   group by a.table_name, a.action, coalesce(a.staff_id, '-');
$$;

-- ---------- X4 form submission compliance (14-1 and 10-1 per shop) ----------
create or replace function public._r3q_x4_compliance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with today as (select (now() at time zone 'Asia/Dhaka')::date as t),
  hi as (select least(d2, (select t from today)) as h),
  n as (select greatest((select h from hi) - d1 + 1, 0) as days)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'form', f.code, 'days', (select days from n), 'submitted_days', coalesce(s.sd, 0),
      'missing_days', greatest((select days from n) - coalesce(s.sd, 0), 0),
      'compliance_pct', case when (select days from n) > 0 then round(100.0 * coalesce(s.sd, 0) / (select days from n), 2) end,
      'stale_drafts', coalesce(s.stale, 0), 'late_submits', coalesce(s.late, 0))
    from public.locations l
    cross join (values ('14-1'), ('10-1')) f(code)
    left join lateral (
      select count(distinct e.entry_date) filter (where e.status in ('submitted', 'approved')) as sd,
             count(*) filter (where e.status = 'draft' and e.entry_date < (select t from today) - 1) as stale,
             count(*) filter (where e.status in ('submitted', 'approved') and not e.entered_later and e.submitted_at is not null
                                and (e.submitted_at at time zone 'Asia/Dhaka')::date > e.entry_date) as late
        from public.entries e where e.form_code = f.code and e.location_id = l.id and e.entry_date between d1 and d2) s on true
   where l.id = any (locs) and l.kind = 'showroom' and l.is_active and l.status = 'live';
$$;

-- ---------- X5 staff indicators, monthly (same logic as biz_staff, month by month) ----------
create or replace function public._r3q_x5_staff_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with s as (select x.*, date_trunc('month', x.sale_date)::date as mon from public.sales x where x.sale_date between d1 and d2 and x.location_id = any (locs)),
  ovr as (select s.id, bool_or(e ->> 'override' = 'true') as o from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e group by s.id),
  per as (select s.created_staff as st, s.mon, count(*) filter (where s.status = 'done') as n, coalesce(sum(s.total) filter (where s.status = 'done'), 0) as rev,
                 coalesce(sum(s.discount) filter (where s.status = 'done'), 0) as disc, count(*) filter (where s.status = 'void') as vn,
                 count(*) filter (where s.status = 'done' and o.o) as onum, count(*) filter (where s.status = 'done' and s.quick) as qn,
                 coalesce(sum(s.due_amount) filter (where s.status = 'done'), 0) as duea
            from s left join ovr o on o.id = s.id group by s.created_staff, s.mon)
  select jsonb_build_object('staff_id', coalesce(p.st, '-'), 'staff_name', pr.full_name, 'month', p.mon, 'orders', p.n, 'revenue', p.rev,
      'discount_pct', case when p.rev + p.disc > 0 then round(100 * p.disc / (p.rev + p.disc), 2) end,
      'void_pct', case when p.n + p.vn > 0 then round(100 * p.vn::numeric / (p.n + p.vn), 2) end,
      'override_pct', case when p.n > 0 then round(100 * p.onum::numeric / p.n, 2) end,
      'quick_pct', case when p.n > 0 then round(100 * p.qn::numeric / p.n, 2) end,
      'due_pct', case when p.rev > 0 then round(100 * p.duea / p.rev, 2) end)
    from per p left join public.profiles pr on pr.staff_id = p.st;
$$;

-- ---------- G2 duplicate / out-of-order paper numbers and book usage ----------
create or replace function public._r3q_g2_paper_numbers(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with p as (select e.location_id, e.form_code, e.entry_date, e.serial,
                    public.norm_paper_serial(coalesce(nullif(btrim(e.data ->> 'paper_no'), ''), nullif(btrim(e.paper_serial), ''))) as pn
               from public.entries e where e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  q as (select p.*, case when p.pn ~ '^[0-9]{1,9}$' then p.pn::int end as num from p),
  dup as (select location_id, form_code, pn, count(*) as c from q where pn is not null group by location_id, form_code, pn having count(*) > 1),
  dsum as (select location_id, form_code, count(*) as dup_numbers from dup group by location_id, form_code),
  ord as (select location_id, form_code, count(*) filter (where entry_date < prev_d) as ooo
            from (select q.*, lag(entry_date) over (partition by location_id, form_code order by num, entry_date, serial) as prev_d from q where num is not null) z
           group by location_id, form_code),
  agg as (select location_id, form_code, count(*) as entries, count(*) filter (where pn is null) as no_pn, count(distinct pn) as dist,
                 min(num) as mn, max(num) as mx, count(distinct num) as dnum from q group by location_id, form_code)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'form', a.form_code, 'entries', a.entries, 'no_paper_no', a.no_pn,
      'distinct_numbers', a.dist, 'duplicate_numbers', coalesce(ds.dup_numbers, 0), 'out_of_order', coalesce(o.ooo, 0),
      'first_no', a.mn, 'last_no', a.mx, 'missing_numbers', case when a.mn is not null then (a.mx - a.mn + 1) - a.dnum end)
    from agg a join public.locations l on l.id = a.location_id
    left join dsum ds on ds.location_id = a.location_id and ds.form_code = a.form_code
    left join ord o on o.location_id = a.location_id and o.form_code = a.form_code;
$$;

-- ---------- K3 store ledger per item and kind (quantities only, no cost) ----------
create or replace function public._r3q_k3_store_ledger(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('item_code', it.code, 'item_name', it.name_bn, 'unit', it.unit, 'kind', sl.reason, 'movements', count(*),
      'in_qty', coalesce(sum(sl.qty_delta) filter (where sl.qty_delta > 0), 0), 'out_qty', coalesce(-sum(sl.qty_delta) filter (where sl.qty_delta < 0), 0),
      'net_qty', sum(sl.qty_delta))
    from public.stock_ledger sl join public.items it on it.id = sl.item_id
   where sl.location_id = any (locs) and (sl.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
     and sl.reverses_id is null and not exists (select 1 from public.stock_ledger r where r.reverses_id = sl.id)
     and (public.rpt_arr_text(flt -> 'categories') is null or it.category = any (public.rpt_arr_text(flt -> 'categories')))
   group by it.id, it.code, it.name_bn, it.unit, sl.reason;
$$;

-- ---------- E2 expense trend with the previous period ----------
create or replace function public._r3q_e2_expense_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ln as (select e.entry_date as d, coalesce(nullif(btrim(l ->> 'head'), ''), '-') as head, public._r2_num(l -> 'amount') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.location_id = any (locs)
                 and e.entry_date between d1 - (d2 - d1 + 1) and d2),
  g as (select head, coalesce(sum(amt) filter (where d >= d1), 0) as cur, coalesce(sum(amt) filter (where d < d1), 0) as prev from ln group by head)
  select jsonb_build_object('head', coalesce(o.label_bn, g.head), 'current', g.cur, 'previous', g.prev, 'change', g.cur - g.prev,
      'change_pct', case when g.prev > 0 then round(100 * (g.cur - g.prev) / g.prev, 2) end)
    from g left join public.option_lists o on o.list_code = 'expense_heads' and o.value_code = g.head;
$$;

-- ---------- E3 no-receipt / over-limit / imprest ----------
create or replace function public._r3q_e3_weak_control(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', '10-2', 'approver', v.appr, 'vouchers', count(*),
      'no_receipt_lines', coalesce(sum(v.nr_lines), 0), 'no_receipt_amount', coalesce(sum(v.nr_amt), 0),
      'over_limit_vouchers', count(*) filter (where v.over), 'over_limit_amount', coalesce(sum(v.over_amt), 0),
      'approval_missing', count(*) filter (where v.appr_miss), 'reason_missing', count(*) filter (where v.reason_miss),
      'imprest_diff_sheets', count(*) filter (where v.imp_diff), 'imprest_diff_amount', coalesce(sum(v.imp_amt), 0))
    from (select e.location_id, coalesce(nullif(btrim(e.data ->> 'approved_by'), ''), '-') as appr, x.nr_lines, x.nr_amt,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'over_limit') as over,
                 (select coalesce(sum(public._r2_num(fe -> 'amount')), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'over_limit') as over_amt,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'approval_missing') as appr_miss,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'receipt_reason_missing') as reason_miss,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'imprest_mismatch') as imp_diff,
                 (select coalesce(sum(abs(public._r2_num(fe -> 'amount'))), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'imprest_mismatch') as imp_amt
            from public.entries e
            cross join lateral (select case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end as fa) fl
            cross join lateral (select count(*) filter (where ln ->> 'receipt' = 'no' and public._r2_num(ln -> 'amount') > 0) as nr_lines,
                                       sum(public._r2_num(ln -> 'amount')) filter (where ln ->> 'receipt' = 'no') as nr_amt
                                  from jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln) x
           where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn, v.appr
  union all
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'source', '14-1', 'approver', '-', 'vouchers', count(*),
      'no_receipt_lines', null, 'no_receipt_amount', null, 'over_limit_vouchers', null, 'over_limit_amount', null, 'approval_missing', null, 'reason_missing', null,
      'imprest_diff_sheets', count(*) filter (where v.imp_diff), 'imprest_diff_amount', coalesce(sum(v.imp_amt), 0))
    from (select e.location_id,
                 exists (select 1 from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'open_imprest_diff') as imp_diff,
                 (select coalesce(sum(abs(public._r2_num(fe -> 'amount'))), 0) from jsonb_array_elements(fl.fa) fe where fe ->> 'code' = 'open_imprest_diff') as imp_amt
            from public.entries e
            cross join lateral (select case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end as fa) fl
           where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn;
$$;

-- ---------- E4 marketing spend vs the monthly head limit ----------
create or replace function public._r3q_e4_marketing_limit(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ln as (select e.location_id, date_trunc('month', coalesce(public._db_date(l ->> 'date'), e.entry_date))::date as mon,
                     case when l ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(l ->> 'head'), ''), '-') end as head,
                     public._r2_num(l -> 'amt') as amt
                from public.entries e
                cross join lateral jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) l
               where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)
                 and coalesce(public._db_date(l ->> 'date'), e.entry_date) between d1 and d2),
  g as (select location_id, mon, head, sum(amt) filter (where amt > 0) as spend from ln group by location_id, mon, head having sum(amt) filter (where amt > 0) is not null),
  w as (select g.*, o.label_bn,
               coalesce(case when o.extra ->> 'limit_month' ~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then (o.extra ->> 'limit_month')::numeric end,
                        (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = g.location_id and ls.key = 'mkt_limit_' || g.head)) as lim
          from g left join public.option_lists o on o.list_code = 'marketing_heads' and o.value_code = g.head)
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'month', w.mon, 'head', coalesce(w.label_bn, w.head), 'spend', w.spend, 'limit', w.lim,
      'used_pct', case when w.lim > 0 then round(100 * w.spend / w.lim, 2) end, 'over_amount', case when w.lim is not null then greatest(w.spend - w.lim, 0) end)
    from w join public.locations l on l.id = w.location_id;
$$;

-- ---------- W1 daily cash flow per location (cash-flow only: no salary lines, no internal lines) ----------
create or replace function public._r3q_w1_cash_flow(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'day', u.d,
      'cash_in', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode = 'cash'), 0), 'cash_out', coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode = 'cash'), 0),
      'net_cash', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode = 'cash'), 0) - coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode = 'cash'), 0),
      'other_in', coalesce(sum(u.amount) filter (where u.dir = 'in' and u.mode <> 'cash'), 0), 'other_out', coalesce(sum(u.amount) filter (where u.dir = 'out' and u.mode <> 'cash'), 0))
    from (select * from public._daybook_lines(locs, '{}'::int[], d1, d2) union all select * from public._daybook_lines12(locs, d1, d2) union all select * from public._daybook_lines23(locs, d1, d2)) u
    join public.locations l on l.id = u.loc
   where not u.internal and not u.sensitive
   group by l.id, l.name_bn, u.d;
$$;

-- ---------- W2 handover (10-1) vs hub count ----------
create or replace function public._r3q_w2_handover_vs_hub(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'location', l.name_bn, 'carrier', v.carrier, 'slips', count(*), 'handover', coalesce(sum(v.handover), 0),
      'hub_counted_slips', count(*) filter (where v.hub is not null), 'hub_received', sum(v.hub),
      'diff', sum(v.hub - v.handover) filter (where v.hub is not null),
      'short_slips', count(*) filter (where v.hub is not null and v.hub < v.handover), 'over_slips', count(*) filter (where v.hub is not null and v.hub > v.handover),
      'not_counted', count(*) filter (where v.hub is null))
    from (select e.location_id, coalesce(nullif(btrim(e.data ->> 'carrier'), ''), '-') as carrier, h.amt as handover,
                 case when ec.counted is not null then ec.counted
                      when e.check_data ? 'rcount' and public._den_total18(e.check_data -> 'rcount', false) > 0 then public._den_total18(e.check_data -> 'rcount', false) end as hub
            from public.entries e
            left join public.entry_counts ec on ec.entry_id = e.id and ec.section = 'hub'
            cross join lateral (select coalesce(public._db_num(e.data #> '{count,n1000}'), 0) * 1000 + coalesce(public._db_num(e.data #> '{count,n500}'), 0) * 500
                + coalesce(public._db_num(e.data #> '{count,n200}'), 0) * 200 + coalesce(public._db_num(e.data #> '{count,n100}'), 0) * 100
                + coalesce(public._db_num(e.data #> '{count,n50}'), 0) * 50 + coalesce(public._db_num(e.data #> '{count,n20}'), 0) * 20
                + coalesce(public._db_num(e.data #> '{count,n10}'), 0) * 10 + coalesce(public._db_num(e.data #> '{count,n5}'), 0) * 5
                + coalesce(public._db_num(e.data #> '{count,n2}'), 0) * 2 + coalesce(public._db_num(e.data #> '{count,n1}'), 0)
                + coalesce(public._db_num(e.data #> '{count,coin}'), 0) - coalesce(public._db_num(e.data -> 'leave_float'), 0) as amt) h
           where e.form_code = '10-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)) v
    join public.locations l on l.id = v.location_id
   group by l.id, l.name_bn, v.carrier;
$$;

-- ---------- registry ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('s10_orders', 'S10', 'orders', 'অর্ডার, অনলাইন ও ডেলিভারি', 'Orders, online & delivery', 'Order, online ও delivery',
  '[["source","উৎস ফর্ম","Source form","text"],["channel","মাধ্যম","Channel","text"],["online","অনলাইন/প্ল্যাটফর্ম","Online / platform","text"],["delivery","ডেলিভারি","Delivery","text"],["orders","অর্ডার","Orders","int"],["amount","অঙ্ক","Amount","money"],["advance","অ্যাডভান্স","Advance","money"],["balance","বাকি","Balance","money"],["handed","হাতে দেওয়া","Handed over","int"],["not_collected","নেওয়া হয়নি","Not collected","int"],["returned","ফেরত","Returned","int"],["delivery_charge","ডেলিভারি চার্জ","Delivery charge","money"]]'::jsonb,
  array['orders','amount','advance','balance','handed','not_collected','returned','delivery_charge'], 'amount', 'desc', array['locations'], false, false, false, 2500),
 ('d5_lapsed', 'D5', 'sales', 'নিষ্ক্রিয় ও নতুন-পুরনো গ্রাহক', 'Lapsed, new vs repeat customers', 'Lapsed ও নতুন-পুরনো গ্রাহক',
  '[["customer_id","","","id"],["name","নাম","Name","text"],["mobile","মোবাইল","Mobile","text"],["kind","ধরন (new/repeat/lapsed)","Kind (new/repeat/lapsed)","text"],["first_date","প্রথম কেনা","First purchase","date"],["last_date","শেষ কেনা","Last purchase","date"],["days_silent","নীরব দিন","Days silent","int"],["orders_period","এই সময়ের অর্ডার","Orders in period","int"],["amount_period","এই সময়ের টাকা","Amount in period","money"],["orders_total","মোট অর্ডার","Orders to date","int"]]'::jsonb,
  array['orders_period','amount_period'], 'amount_period', 'desc', array['locations'], false, false, false, 2510),
 ('m1_rfm', 'M1', 'sales', 'গ্রাহক সেগমেন্ট (RFM)', 'Customer segments (RFM)', 'Customer segment (RFM)',
  '[["customer_id","","","id"],["name","নাম","Name","text"],["mobile","মোবাইল","Mobile","text"],["segment","সেগমেন্ট","Segment","text"],["recency_days","শেষ কেনার পর দিন","Days since last purchase","int"],["frequency","বার","Orders","int"],["monetary","টাকা","Spend","money"],["last_date","শেষ কেনা","Last purchase","date"]]'::jsonb,
  array['frequency','monetary'], 'monetary', 'desc', array['locations'], false, false, false, 2520),
 ('x2_bypass', 'X2', 'control', 'ছাড়, জরুরি অনুমোদন ও গ্রান্ট ব্যবহার', 'Releases, emergency & grant use', 'Release, emergency ও grant ব্যবহার',
  '[["staff_id","স্টাফ আইডি","Staff ID","text"],["staff_name","নাম","Name","text"],["kind","ধরন","Kind","text"],["code","কোড","Code","text"],["requests","অনুরোধ","Requests","int"],["approved","অনুমোদিত","Approved","int"],["rejected","বাতিল","Rejected","int"],["pending","অপেক্ষায়","Pending","int"],["other","মেয়াদ শেষ/বাতিল","Expired/cancelled","int"],["amount","অঙ্ক","Amount","money"]]'::jsonb,
  array['requests','approved','rejected','pending','other','amount'], 'requests', 'desc', array['locations'], false, false, false, 2530),
 ('x3_audit_log', 'X3', 'control', 'অডিট ও সংশোধন লগ', 'Audit & correction log', 'Audit ও correction log',
  '[["table_name","টেবিল","Table","text"],["action","কাজ","Action","text"],["staff_id","স্টাফ","Staff","text"],["events","ঘটনা","Events","int"],["first_day","প্রথম দিন","First day","date"],["last_day","শেষ দিন","Last day","date"]]'::jsonb,
  array['events'], 'events', 'desc', '{}'::text[], false, false, true, 2540),
 ('x4_compliance', 'X4', 'control', 'ফর্ম জমার নিয়ম-পালন', 'Form submission compliance', 'Form জমার compliance',
  '[["location_id","","","id"],["location","শোরুম","Shop","text"],["form","ফর্ম","Form","text"],["days","দিন","Days","int"],["submitted_days","জমা-দেওয়া দিন","Days submitted","int"],["missing_days","বাদ-পড়া দিন","Days missing","int"],["compliance_pct","পালন %","Compliance %","pct"],["stale_drafts","পুরনো খসড়া","Stale drafts","int"],["late_submits","দেরিতে জমা","Late submits","int"]]'::jsonb,
  array['days','submitted_days','missing_days','stale_drafts','late_submits'], 'missing_days', 'desc', array['locations'], false, false, false, 2550),
 ('x5_staff_trend', 'X5', 'staff', 'স্টাফ সূচক ধারা (মাসওয়ারি)', 'Staff indicators by month', 'Staff সূচক ধারা (monthly)',
  '[["staff_id","স্টাফ আইডি","Staff ID","text"],["staff_name","নাম","Name","text"],["month","মাস","Month","date"],["orders","বিক্রি","Sales","int"],["revenue","বিক্রয়","Revenue","money"],["discount_pct","ছাড় %","Discount %","pct"],["void_pct","বাতিল %","Void %","pct"],["override_pct","দাম বদল %","Override %","pct"],["quick_pct","কুইক %","Quick %","pct"],["due_pct","বাকি %","Due %","pct"]]'::jsonb,
  array['orders','revenue'], 'month', 'desc', array['locations'], false, false, false, 2560),
 ('g2_paper_numbers', 'G2', 'control', 'ডুপ্লিকেট/উল্টো ক্রম ও বই-ব্যবহার', 'Duplicate / out-of-order paper numbers', 'Duplicate/উল্টো ক্রম ও বই-ব্যবহার',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["entries","এন্ট্রি","Entries","int"],["no_paper_no","নম্বর ছাড়া","Without number","int"],["distinct_numbers","আলাদা নম্বর","Distinct numbers","int"],["duplicate_numbers","ডুপ্লিকেট নম্বর","Duplicate numbers","int"],["out_of_order","উল্টো ক্রম","Out of order","int"],["first_no","প্রথম নম্বর","First no.","int"],["last_no","শেষ নম্বর","Last no.","int"],["missing_numbers","বাদ-পড়া নম্বর","Missing numbers","int"]]'::jsonb,
  array['entries','no_paper_no','duplicate_numbers','out_of_order','missing_numbers'], 'duplicate_numbers', 'desc', array['locations'], false, false, false, 2570),
 ('k3_store_ledger', 'K3', 'stock', 'স্টক মুভমেন্ট (আইটেম ও ধরন)', 'Store ledger movement', 'Stock movement (item ও kind)',
  '[["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["unit","একক","Unit","text"],["kind","ধরন","Kind","text"],["movements","মুভমেন্ট","Movements","int"],["in_qty","ঢুকেছে","In","num"],["out_qty","বেরিয়েছে","Out","num"],["net_qty","নিট","Net","num"]]'::jsonb,
  array['movements'], 'movements', 'desc', array['locations','brands','categories'], false, false, false, 2580),
 ('e2_expense_trend', 'E2', 'expense', 'খরচের ধারা ও আগের সময়ের তুলনা', 'Expense trend vs previous period', 'খরচের ধারা (আগের সময়ের সাথে)',
  '[["head","খাত","Head","text"],["current","এই সময়","Current","money"],["previous","আগের সময়","Previous","money"],["change","পরিবর্তন","Change","money"],["change_pct","পরিবর্তন %","Change %","pct"]]'::jsonb,
  array['current','previous','change'], 'change', 'desc', array['locations'], false, false, false, 2590),
 ('e3_weak_control', 'E3', 'expense', 'রসিদহীন, সীমা-ছাড়া ও ইমপ্রেস্ট', 'No-receipt, over-limit & imprest', 'রসিদহীন/সীমা-ছাড়া/imprest',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["source","ফর্ম","Form","text"],["approver","অনুমোদনকারী","Approver","text"],["vouchers","ভাউচার/শিট","Vouchers / sheets","int"],["no_receipt_lines","রসিদ ছাড়া লাইন","No-receipt lines","int"],["no_receipt_amount","রসিদ ছাড়া টাকা","No-receipt amount","money"],["over_limit_vouchers","সীমার উপরে ভাউচার","Over-limit vouchers","int"],["over_limit_amount","সীমার উপরের লাইন (বড়)","Over-limit line (largest)","money"],["approval_missing","অনুমোদনকারী নেই","Approver missing","int"],["reason_missing","কারণ নেই","Reason missing","int"],["imprest_diff_sheets","ইমপ্রেস্ট অমিল","Imprest mismatch","int"],["imprest_diff_amount","ইমপ্রেস্ট অমিলের টাকা","Imprest mismatch amount","money"]]'::jsonb,
  array['vouchers','no_receipt_lines','no_receipt_amount','over_limit_vouchers','over_limit_amount','approval_missing','reason_missing','imprest_diff_sheets','imprest_diff_amount'], 'no_receipt_amount', 'desc', array['locations'], false, false, false, 2600),
 ('e4_marketing_limit', 'E4', 'marketing', 'মার্কেটিং খরচ বনাম মাসিক সীমা', 'Marketing spend vs monthly head limit', 'মার্কেটিং খরচ vs monthly limit',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["month","মাস","Month","date"],["head","খাত","Head","text"],["spend","খরচ","Spend","money"],["limit","মাসিক সীমা","Monthly limit","money"],["used_pct","ব্যবহার %","Used %","pct"],["over_amount","সীমার বেশি","Over limit","money"]]'::jsonb,
  array['spend','over_amount'], 'spend', 'desc', array['locations'], false, false, false, 2610),
 ('w1_cash_flow', 'W1', 'cash', 'দৈনিক ক্যাশ প্রবাহ', 'Daily cash flow', 'Daily cash flow',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["day","দিন","Day","date"],["cash_in","নগদ ঢুকেছে","Cash in","money"],["cash_out","নগদ বেরিয়েছে","Cash out","money"],["net_cash","নিট নগদ","Net cash","money"],["other_in","ব্যাংক/মোবাইল ঢুকেছে","Bank/mobile in","money"],["other_out","ব্যাংক/মোবাইল বেরিয়েছে","Bank/mobile out","money"]]'::jsonb,
  array['cash_in','cash_out','net_cash','other_in','other_out'], 'day', 'desc', array['locations'], false, false, false, 2620),
 ('w2_handover_vs_hub', 'W2', 'cash', 'হ্যান্ডওভার বনাম হাব গণনা', 'Handover vs hub count', 'Handover vs hub গণনা',
  '[["location_id","","","id"],["location","লোকেশন","Location","text"],["carrier","বহনকারী","Carrier","text"],["slips","স্লিপ","Slips","int"],["handover","হ্যান্ডওভার","Handover","money"],["hub_counted_slips","হাবে গোনা স্লিপ","Slips counted at hub","int"],["hub_received","হাবে প্রাপ্ত","Hub received","money"],["diff","পার্থক্য (হাব − হ্যান্ডওভার)","Difference (hub − handover)","money"],["short_slips","কম স্লিপ","Short slips","int"],["over_slips","বেশি স্লিপ","Over slips","int"],["not_counted","হাবে গোনা হয়নি","Not counted at hub","int"]]'::jsonb,
  array['slips','handover','hub_counted_slips','hub_received','diff','short_slips','over_slips','not_counted'], 'diff', 'asc', array['locations'], false, false, false, 2630)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols,
  tot = excluded.tot, sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort;

select public._r3_lockdown();
