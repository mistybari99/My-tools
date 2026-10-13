-- ============================================================
-- PHASE 26 (report engine 3, batch R3-26): 13 reports on the engine of phase24
--   P2 p2_rate_trend      purchase-rate trend per item / supplier        (cost)
--   P4 p4_supplier_score  supplier scorecard                              (cost)
--   P5 p5_po_match        PO - GRN - bill 3-way match and open POs        (cost)
--   P6 p6_purchase_budget purchase spent vs the 10-4 budget and outlook   (cost)
--   K2 k2_count_variance  stock-count variance, repeat offenders          (quantities only)
--   F1 f1_production      production runs, sheet output, dispatch         (void runs shown as a status)
--   F2 f2_yield           yield vs the approved 05-4 standard
--   F3 f3_raw_vs_recipe   raw material really issued vs the recipe
--   F4 f4_breakdowns      machine breakdowns and maintenance requests
--   M2 m2_marketing_vs_sales  marketing spend and sales side by side per day
--   Q1 q1_fridge_temp     fridge temperature log, out-of-range readings
--   Q2 q2_hygiene         hygiene / expiry / checklist compliance
--   Q3 q3_complaints      complaints and sale-return root causes
-- Needs phase24 (and phase17 paper_serial, phase19 production_runs, phase23 production_runs.status). Additive and idempotent: paste twice is safe.
-- Form field ids were checked in web/forms.js, forms_stock.js, forms_factory.js, forms_cash.js, forms_sales.js.
-- ============================================================

-- ---------- private helpers (called only from the report functions below) ----------
create or replace function public._p26_d(t text) returns date
language plpgsql immutable set search_path = public as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return t::date;
exception when others then return null;
end $$;

create or replace function public._p26_b(j jsonb) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(j in ('true'::jsonb, '"true"'::jsonb, '"yes"'::jsonb, '1'::jsonb, '"1"'::jsonb), false);
$$;

create or replace function public._p26_arr(j jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end;
$$;

-- rate observations: posted purchase bills (lines) and submitted/approved 04-1 GRN lines. Cost data: only called from cost reports.
create or replace function public._p26_rates(d1 date, d2 date, locs int[]) returns table (item_id uuid, sk text, sname text, dt date, qty numeric, rate numeric, ord text)
language sql stable security definer set search_path = public as $$
  select pl.item_id, lower(btrim(s.name)), btrim(s.name), b.bill_date, coalesce(pl.base_qty, pl.qty), coalesce(pl.unit_cost_base, pl.unit_cost), b.id::text || ':' || pl.line_no::text
    from public.purchase_bills b join public.purchase_lines pl on pl.bill_id = b.id join public.suppliers s on s.id = b.supplier_id
   where b.status = 'posted' and b.kind = 'bill' and pl.item_id is not null and b.bill_date between d1 and d2 and b.location_id = any (locs)
     and coalesce(pl.unit_cost_base, pl.unit_cost) > 0 and coalesce(pl.base_qty, pl.qty) > 0
  union all
  select i.id, lower(btrim(coalesce(s.name, e.data ->> 'supplier'))), btrim(coalesce(s.name, e.data ->> 'supplier')), e.entry_date, public._r2_num(r -> 'counted'), public._r2_num(r -> 'rate'), e.id::text || ':' || n.ord::text
    from public.entries e
    cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'lines')) with ordinality n(r, ord)
    join public.items i on i.code = n.r ->> 'item'
    left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
   where e.form_code = '04-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
     and nullif(btrim(coalesce(s.name, e.data ->> 'supplier')), '') is not null
     and public._r2_num(n.r -> 'rate') > 0 and public._r2_num(n.r -> 'counted') > 0;
$$;

-- one row per purchase order (06-3, not cancelled) with what was received (04-1 on that PO number) and what was billed (06-4)
create or replace function public._p26_po(d1 date, d2 date, locs int[])
returns table (entry_id uuid, location_id int, entry_date date, po_no text, sk text, supplier text, delivery_date date, po_lines int, po_total numeric, lines_open int,
               grn_n int, first_grn date, last_grn date, grn_value numeric, bill_n int, bill_amount numeric)
language sql stable security definer set search_path = public as $$
  with po as (
    select e.id, e.location_id, e.entry_date, e.data,
           coalesce(nullif(btrim(e.paper_serial), ''), nullif(btrim(e.data ->> 'paper_no'), ''), e.serial::text) as po_no,
           array_remove(array[public.norm_paper_serial(e.paper_serial), public.norm_paper_serial(e.data ->> 'paper_no'), e.serial::text], null) as keys,
           btrim(coalesce(s.name, e.data ->> 'supplier')) as sname
      from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
     where e.form_code = '06-3' and e.status in ('submitted', 'approved') and not public._p26_b(e.data -> 'cancel')
       and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  grn as (
    select g.id, g.entry_date, g.data, public.norm_paper_serial(g.data ->> 'po_no') as pk
      from public.entries g
     where g.form_code = '04-1' and g.status in ('submitted', 'approved') and g.data ->> 'paper' = 'po' and g.location_id = any (locs)
       and public.norm_paper_serial(g.data ->> 'po_no') is not null),
  bil as (
    select b.id, public.norm_paper_serial(b.data -> 'tri' -> 0 ->> 'po') as pk, public._r2_num(b.data -> 'bill_amount') as amt
      from public.entries b
     where b.form_code = '06-4' and b.status in ('submitted', 'approved') and b.location_id = any (locs)
       and public.norm_paper_serial(b.data -> 'tri' -> 0 ->> 'po') is not null)
  select po.id, po.location_id, po.entry_date, po.po_no, lower(po.sname), po.sname, public._p26_d(po.data ->> 'delivery_date'),
    (select count(*)::int from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0),
    (select sum(public._r2_num(r -> 'qty') * public._r2_num(r -> 'rate')) from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0),
    (select count(*)::int from (select r ->> 'item' as it, sum(public._r2_num(r -> 'qty')) as oq from jsonb_array_elements(public._p26_arr(po.data -> 'lines')) r where public._r2_num(r -> 'qty') > 0 group by 1) o
      where o.oq > coalesce((select sum(public._r2_num(gl -> 'counted')) from grn g, jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl where g.pk = any (po.keys) and gl ->> 'item' = o.it), 0)),
    (select count(*)::int from grn g where g.pk = any (po.keys)),
    (select min(g.entry_date) from grn g where g.pk = any (po.keys)),
    (select max(g.entry_date) from grn g where g.pk = any (po.keys)),
    (select sum(public._r2_num(gl -> 'counted') * public._r2_num(gl -> 'rate')) from grn g, jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl where g.pk = any (po.keys)),
    (select count(*)::int from bil b where b.pk = any (po.keys)),
    (select sum(b.amt) from bil b where b.pk = any (po.keys))
  from po;
$$;

-- the purchase outlook of phase4 needs the caller's business-view right: where it is missing the figure is simply null
create or replace function public._p26_outlook(p_loc int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  return public.biz_outlook(p_loc, 7, 28);
exception when others then
  return null;
end $$;

-- ============================================================
-- P2 purchase-rate trend per item and supplier
-- ============================================================
create or replace function public._r3q_p2_rate_trend(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  x as (
    select r.item_id, r.sk, min(r.sname) as sname, count(*) as n, sum(r.qty) as qty,
           (array_agg(r.rate order by r.dt, r.ord))[1] as first_rate, (array_agg(r.rate order by r.dt desc, r.ord desc))[1] as last_rate,
           min(r.rate) as min_rate, max(r.rate) as max_rate, sum(r.qty * r.rate) / nullif(sum(r.qty), 0) as avg_rate, max(r.dt) as last_date
      from public._p26_rates(d1, d2, locs) r group by r.item_id, r.sk)
  select jsonb_build_object('item_code', i.code, 'item_bn', i.name_bn, 'supplier', x.sname, 'n', x.n, 'qty', round(x.qty, 3),
    'first_rate', round(x.first_rate, 4), 'last_rate', round(x.last_rate, 4), 'min_rate', round(x.min_rate, 4), 'max_rate', round(x.max_rate, 4), 'avg_rate', round(x.avg_rate, 4),
    'change_pct', case when x.n > 1 and x.first_rate > 0 then round((x.last_rate - x.first_rate) / x.first_rate * 100, 2) end, 'last_date', x.last_date)
    from x join public.items i on i.id = x.item_id cross join cat
   where cat.c is null or i.category = any (cat.c);
$$;

-- ============================================================
-- P4 supplier scorecard
-- ============================================================
create or replace function public._r3q_p4_supplier_score(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with sup as (
    select e.id, e.form_code, e.data, lower(btrim(coalesce(s.name, e.data ->> 'supplier'))) as sk, btrim(coalesce(s.name, e.data ->> 'supplier')) as sname
      from public.entries e left join public.suppliers s on s.id::text = e.data ->> 'supplier_id'
     where e.form_code in ('04-1', '06-4') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
       and nullif(btrim(coalesce(s.name, e.data ->> 'supplier')), '') is not null),
  gl as (
    select s.sk, s.sname, s.id, r ->> 'quality' as q, public._r2_num(r -> 'counted') as cnt, public._r2_num(r -> 'memo') as memo
      from sup s cross join lateral jsonb_array_elements(public._p26_arr(s.data -> 'lines')) r where s.form_code = '04-1'),
  grn as (
    select sk, min(sname) as sname, count(distinct id) as grns, count(*) as lines, count(*) filter (where memo is not null and cnt is not null and cnt < memo) as short_lines,
           count(*) filter (where q = 'return') as rejected, count(*) filter (where q = 'hold') as held, count(*) filter (where q = 'reduced') as reduced
      from gl group by sk),
  bil as (
    select sk, min(sname) as sname, count(*) as bills, count(*) filter (where data ->> 'short' = 'yes') as short_claims, count(*) filter (where data ->> 'returned' = 'yes') as return_claims
      from sup where form_code = '06-4' group by sk),
  po as (
    select p.sk, min(p.supplier) as sname, count(*) as pos, count(*) filter (where p.grn_n > 0 and p.delivery_date is not null) as pos_matched,
           count(*) filter (where p.grn_n > 0 and p.delivery_date is not null and p.first_grn > p.delivery_date) as late_pos,
           count(*) filter (where p.grn_n = 0 and p.delivery_date is not null and p.delivery_date < (now() at time zone 'Asia/Dhaka')::date) as overdue_open
      from public._p26_po(d1, d2, locs) p where p.sk is not null and p.sk <> '' group by p.sk),
  rr as (select * from public._p26_rates(d1, d2, locs)),
  rc as (
    select sk, avg(chg) as chg, count(*) as items
      from (select sk, item_id, (l - f) / f * 100 as chg
              from (select sk, item_id, (array_agg(rate order by dt, ord))[1] as f, (array_agg(rate order by dt desc, ord desc))[1] as l, count(*) as n from rr group by sk, item_id) a
             where n > 1 and f > 0) b group by sk),
  keys as (select sk, sname from grn union select sk, sname from bil union select sk, sname from po union select sk, min(sname) from rr group by sk)
  select jsonb_build_object('supplier', k.sname, 'grns', coalesce(g.grns, 0), 'lines', coalesce(g.lines, 0), 'short_lines', coalesce(g.short_lines, 0), 'rejected', coalesce(g.rejected, 0),
    'held', coalesce(g.held, 0), 'reduced', coalesce(g.reduced, 0), 'bills_checked', coalesce(b.bills, 0), 'short_claims', coalesce(b.short_claims, 0), 'return_claims', coalesce(b.return_claims, 0),
    'pos', coalesce(p.pos, 0), 'late_pos', case when coalesce(p.pos_matched, 0) > 0 then p.late_pos end, 'overdue_open', coalesce(p.overdue_open, 0),
    'rate_change_pct', case when c.chg is not null then round(c.chg, 2) end, 'rate_items', coalesce(c.items, 0))
    from (select sk, min(sname) as sname from keys where sk is not null and sk <> '' group by sk) k
    left join grn g on g.sk = k.sk left join bil b on b.sk = k.sk left join po p on p.sk = k.sk left join rc c on c.sk = k.sk;
$$;

-- ============================================================
-- P5 PO - GRN - bill match and open POs
-- ============================================================
create or replace function public._r3q_p5_po_match(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (select (now() at time zone 'Asia/Dhaka')::date as today)
  select jsonb_build_object('po_no', p.po_no, 'day', p.entry_date, 'location_bn', l.name_bn, 'supplier', coalesce(p.supplier, '-'), 'delivery_date', p.delivery_date,
    'po_lines', p.po_lines, 'lines_open', p.lines_open, 'po_total', round(coalesce(p.po_total, 0), 2), 'grn_n', p.grn_n, 'grn_value', case when p.grn_n > 0 then round(coalesce(p.grn_value, 0), 2) end,
    'bill_n', p.bill_n, 'bill_amount', case when p.bill_n > 0 then round(coalesce(p.bill_amount, 0), 2) end,
    'bill_diff', case when p.bill_n > 0 and p.grn_n > 0 and p.bill_amount is not null then round(p.bill_amount - coalesce(p.grn_value, 0), 2) end,
    'days_late', case when p.delivery_date is null then null
                      when p.grn_n = 0 or p.lines_open > 0 then greatest(t.today - p.delivery_date, 0)
                      else greatest(p.last_grn - p.delivery_date, 0) end,
    'status', case when p.grn_n = 0 then 'খোলা / open'
                   when p.lines_open > 0 then 'আংশিক / partial'
                   when p.bill_n = 0 then 'প্রাপ্ত, বিল নেই / received, not billed'
                   when p.bill_amount is not null and abs(p.bill_amount - coalesce(p.grn_value, 0)) <= 0.5 then 'বিল মিলেছে / matched'
                   else 'বিল অমিল / bill differs' end)
    from public._p26_po(d1, d2, locs) p join public.locations l on l.id = p.location_id cross join t;
$$;

-- ============================================================
-- P6 purchase spent vs the 10-4 purchase budget (+ the phase4 outlook for the latest sheet of each place)
--   budget = hub cash + showroom floats + bank + mobile + receivable(7d) - payable(7d) - protected minimum cash (location setting hub_min_cash), exactly as the 10-4 sheet works it out.
--   No hub_min_cash setting = the budget was never captured = null. Spent = posted purchase bills of the 7 days from the sheet date; where there are none, the 04-1 GRN value.
-- ============================================================
create or replace function public._r3q_p6_purchase_budget(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with b as (
    select e.id, e.location_id, e.entry_date,
      coalesce(public._r2_num(e.data -> 'hub_cash'), 0) + coalesce(public._r2_num(e.data -> 'sr_float'), 0) + coalesce(public._r2_num(e.data -> 'bank'), 0) + coalesce(public._r2_num(e.data -> 'mobile'), 0) as a,
      (select coalesce(sum(public._r2_num(x -> 'amt')), 0) from jsonb_array_elements(public._p26_arr(e.data -> 'recv')) x) as bt,
      (select coalesce(sum(public._r2_num(x -> 'amt')), 0) from jsonb_array_elements(public._p26_arr(e.data -> 'pay')) x) as ct,
      (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = e.location_id and ls.key = 'hub_min_cash') as mn,
      row_number() over (partition by e.location_id order by e.entry_date desc, e.serial desc) as rn
      from public.entries e
     where e.form_code = '10-4' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  c as (
    select b.*, case when b.mn is not null then b.a + b.bt - b.ct - b.mn end as budget,
      (select coalesce(sum(case when pb.kind = 'bill' then pb.total else -pb.total end), 0) from public.purchase_bills pb
        where pb.status = 'posted' and pb.location_id = b.location_id and pb.bill_date between b.entry_date and b.entry_date + 6) as bills,
      (select coalesce(sum(public._r2_num(gl -> 'counted') * public._r2_num(gl -> 'rate')), 0) from public.entries g
        cross join lateral jsonb_array_elements(public._p26_arr(g.data -> 'lines')) gl
        where g.form_code = '04-1' and g.status in ('submitted', 'approved') and g.location_id = b.location_id and g.entry_date between b.entry_date and b.entry_date + 6
          and public._r2_num(gl -> 'counted') > 0 and public._r2_num(gl -> 'rate') > 0) as grn,
      case when b.rn = 1 then public._p26_outlook(b.location_id) end as ol
      from b),
  d as (select c.*, case when c.bills > 0 then c.bills else c.grn end as spent from c)
  select jsonb_build_object('location_bn', l.name_bn, 'day', d.entry_date, 'cash_total', round(d.a, 2), 'receivable', round(d.bt, 2), 'payable', round(d.ct, 2), 'min_cash', d.mn, 'budget', round(d.budget, 2),
    'bills_7d', round(d.bills, 2), 'grn_7d', round(d.grn, 2), 'spent', round(d.spent, 2),
    'used_pct', case when d.budget > 0 then round(d.spent / d.budget * 100, 1) end, 'budget_left', case when d.budget is not null then round(d.budget - d.spent, 2) end,
    'outlook_low', case when d.ol is not null and jsonb_typeof(d.ol -> 'est_purchase_low') = 'number' then (d.ol ->> 'est_purchase_low')::numeric end,
    'outlook_high', case when d.ol is not null and jsonb_typeof(d.ol -> 'est_purchase_high') = 'number' then (d.ol ->> 'est_purchase_high')::numeric end)
    from d join public.locations l on l.id = d.location_id;
$$;

-- ============================================================
-- K2 stock-count variance per counter and item (quantities only; rows need both the counted and the book figure)
-- ============================================================
create or replace function public._r3q_k2_count_variance(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  ln as (
    select e.location_id, e.entry_date, e.serial, nullif(btrim(e.data ->> 'counted_by'), '') as cb, r ->> 'item' as icode,
           public._r2_num(r -> 'count') as cnt, public._r2_num(r -> 'book') as bk, nullif(btrim(r ->> 'reason'), '') as reason
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'rows')) r
     where e.form_code = '04-3' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  g as (
    select ln.location_id, ln.cb, i.id as item_id, i.code, i.name_bn, count(*) as counts, count(*) filter (where ln.cnt <> ln.bk) as off_n,
           count(*) filter (where ln.cnt < ln.bk) as short_n, count(*) filter (where ln.cnt > ln.bk) as over_n,
           sum(ln.cnt - ln.bk) as net_var, sum(abs(ln.cnt - ln.bk)) as abs_var, max(ln.entry_date) as last_date,
           (array_agg(ln.reason order by ln.entry_date desc, ln.serial desc) filter (where ln.reason is not null and ln.cnt <> ln.bk))[1] as last_reason
      from ln join public.items i on i.code = ln.icode cross join cat
     where ln.cnt is not null and ln.bk is not null and (cat.c is null or i.category = any (cat.c))
     group by ln.location_id, ln.cb, i.id, i.code, i.name_bn)
  select jsonb_build_object('location_bn', l.name_bn, 'counter', coalesce(nullif(btrim(p.full_name), '') || ' · ' || g.cb, g.cb, '-'), 'item_code', g.code, 'item_bn', g.name_bn,
    'counts', g.counts, 'off_n', g.off_n, 'short_n', g.short_n, 'over_n', g.over_n, 'net_var', round(g.net_var, 3), 'abs_var', round(g.abs_var, 3),
    'off_pct', round(g.off_n * 100.0 / g.counts, 1), 'last_date', g.last_date, 'last_reason', g.last_reason)
    from g join public.locations l on l.id = g.location_id left join public.profiles p on p.staff_id = g.cb;
$$;

-- ============================================================
-- F1 production and dispatch: production_runs (void runs kept, status void), 05-1 sheets, stock transfers sent
-- ============================================================
create or replace function public._r3q_f1_production(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with u as (
    select 'রান / run'::text as source, (r.made_at at time zone 'Asia/Dhaka')::date as day, r.location_id, r.item_id, r.batches as batches, r.yield_base as qty, r.status as status, null::int as to_loc
      from public.production_runs r
     where r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2
    union all
    select 'শিট / sheet', e.entry_date, e.location_id, i.id, case when o.rn = 1 then public._r2_num(e.data -> 'batches') end, public._r2_num(o.r -> 'qty'), e.status, null
      from public.entries e
      cross join lateral (select t.r, row_number() over (order by t.ord) as rn from jsonb_array_elements(public._p26_arr(e.data -> 'output')) with ordinality t(r, ord)
                           where public._r2_num(t.r -> 'qty') > 0 and nullif(t.r ->> 'item', '') is not null) o
      left join public.items i on i.code = o.r ->> 'item'
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
    union all
    select 'শিট / sheet', e.entry_date, e.location_id, null::uuid, public._r2_num(e.data -> 'batches'), null::numeric, e.status, null
      from public.entries e
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
       and public._r2_num(e.data -> 'batches') is not null
       and not exists (select 1 from jsonb_array_elements(public._p26_arr(e.data -> 'output')) t(r) where public._r2_num(t.r -> 'qty') > 0 and nullif(t.r ->> 'item', '') is not null)
    union all
    select 'চালান / dispatch', (t.sent_at at time zone 'Asia/Dhaka')::date, t.from_location_id, t.item_id, null, t.qty, t.status, t.to_location_id
      from public.stock_transfers t
     where t.from_location_id = any (locs) and (t.sent_at at time zone 'Asia/Dhaka')::date between d1 and d2)
  select jsonb_build_object('source', u.source, 'day', u.day, 'location_bn', l.name_bn, 'product_code', i.code, 'product_bn', i.name_bn, 'unit', i.unit,
    'batches', u.batches, 'qty', u.qty, 'status', u.status, 'to_location_bn', lt.name_bn)
    from u join public.locations l on l.id = u.location_id left join public.items i on i.id = u.item_id left join public.locations lt on lt.id = u.to_loc;
$$;

-- ============================================================
-- F2 yield vs the approved 05-4 standard (per place and product), with what the production runs and the sheets made in the same period
--   standard = average good-per-input of the latest APPROVED 05-4 sheet up to the end of the period. production_runs post the recipe yield by definition, so they are shown as quantities, not as a yield test.
-- ============================================================
create or replace function public._r3q_f2_yield(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with t as (
    select e.location_id, i.id as item_id, e.entry_date, e.serial, e.status, coalesce(public._p26_d(r ->> 'date'), e.entry_date) as bdate,
           public._r2_num(r -> 'input') as inp, public._r2_num(r -> 'good') as good, public._r2_num(r -> 'second') as sec, public._r2_num(r -> 'waste') as wst
      from public.entries e join public.items i on i.code = e.data ->> 'item'
      cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'b')) r
     where e.form_code = '05-4' and e.status in ('submitted', 'approved') and e.entry_date <= d2 and e.location_id = any (locs)),
  std as (
    select distinct on (location_id, item_id) location_id, item_id, y
      from (select location_id, item_id, entry_date, serial, avg(good / inp) as y from t where status = 'approved' and inp > 0 and good is not null group by 1, 2, 3, 4) s
     order by location_id, item_id, entry_date desc, serial desc),
  p as (
    select location_id, item_id, count(*) as n, avg(good / inp) as ty,
           avg(coalesce(sec, 0) / nullif(good + coalesce(sec, 0) + coalesce(wst, 0), 0) * 100) as sec_pct, avg(coalesce(wst, 0) / nullif(good + coalesce(sec, 0) + coalesce(wst, 0), 0) * 100) as wst_pct
      from t where inp > 0 and good is not null and bdate between d1 and d2 group by 1, 2),
  runs as (
    select r.location_id, r.item_id, sum(r.batches) as b, sum(r.yield_base) as q
      from public.production_runs r
     where r.status = 'done' and r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2 group by 1, 2),
  sh as (
    select e.location_id, i.id as item_id, sum(public._base_qty(i.id, public._r2_num(o -> 'qty'), i.unit)) as q
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'output')) o join public.items i on i.code = o ->> 'item'
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) and public._r2_num(o -> 'qty') > 0
     group by 1, 2),
  k as (select location_id, item_id from p union select location_id, item_id from runs union select location_id, item_id from sh)
  select jsonb_build_object('location_bn', l.name_bn, 'item_code', i.code, 'item_bn', i.name_bn, 'std_yield', round(s.y, 4), 'tests_n', coalesce(p.n, 0), 'test_yield', round(p.ty, 4),
    'yield_diff_pct', case when s.y > 0 and p.ty is not null then round((p.ty - s.y) / s.y * 100, 2) end, 'second_pct', round(p.sec_pct, 2), 'waste_pct', round(p.wst_pct, 2),
    'run_batches', runs.b, 'run_qty', round(runs.q, 3), 'sheet_qty', round(sh.q, 3),
    'qty_gap', case when sh.q is not null and runs.q is not null then round(sh.q - runs.q, 3) end)
    from k join public.locations l on l.id = k.location_id join public.items i on i.id = k.item_id
    left join std s on s.location_id = k.location_id and s.item_id = k.item_id left join p on p.location_id = k.location_id and p.item_id = k.item_id
    left join runs on runs.location_id = k.location_id and runs.item_id = k.item_id left join sh on sh.location_id = k.location_id and sh.item_id = k.item_id;
$$;

-- ============================================================
-- F3 raw material really issued to production (stock_ledger issue_out, ref_type production) vs recipe lines x batches (_recipe_need). Quantities only.
-- ============================================================
create or replace function public._r3q_f3_raw_vs_recipe(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with runs as (
    select r.id, r.location_id, r.item_id as prod, r.recipe_id, r.batches
      from public.production_runs r
     where r.status = 'done' and r.location_id = any (locs) and (r.made_at at time zone 'Asia/Dhaka')::date between d1 and d2),
  need as (
    select r.id as run_id, r.location_id, r.prod, r.batches, n.item_id as ing, n.need, n.waste_missing, n.base_unit, n.code, n.name_bn
      from runs r cross join lateral public._recipe_need(r.recipe_id, r.batches, r.location_id) n where n.kind = 'ingredient'),
  act as (
    select n.run_id, n.ing, -sum(l.qty_delta) as used
      from need n join public.stock_ledger l on l.ref_type = 'production' and l.ref_id = n.run_id::text and l.reason = 'issue_out' and l.item_id = n.ing
       and not exists (select 1 from public.stock_ledger v where v.reverses_id = l.id)
     group by n.run_id, n.ing),
  g as (
    select n.location_id, n.prod, n.ing, min(n.code) as code, min(n.name_bn) as name_bn, min(n.base_unit) as base_unit, count(*) as runs, sum(n.batches) as batches,
           sum(n.need) as expected, sum(a.used) as actual, count(*) filter (where n.waste_missing) as waste_missing
      from need n left join act a on a.run_id = n.run_id and a.ing = n.ing group by n.location_id, n.prod, n.ing)
  select jsonb_build_object('location_bn', l.name_bn, 'product_code', p.code, 'product_bn', p.name_bn, 'ingredient_code', g.code, 'ingredient_bn', g.name_bn, 'base_unit', g.base_unit,
    'runs', g.runs, 'batches', g.batches, 'expected', round(g.expected, 4), 'actual', round(g.actual, 4),
    'diff', case when g.actual is not null then round(g.actual - g.expected, 4) end,
    'diff_pct', case when g.actual is not null and g.expected > 0 then round((g.actual - g.expected) / g.expected * 100, 2) end, 'waste_missing', g.waste_missing)
    from g join public.locations l on l.id = g.location_id join public.items p on p.id = g.prod;
$$;

-- ============================================================
-- F4 machine breakdown (05-1 breakdown fields) and maintenance requests (08-1); open requests are listed whatever their date
-- ============================================================
create or replace function public._r3q_f4_breakdowns(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with m as (
    select e.id, e.location_id, e.entry_date, e.data, nullif(btrim(e.data ->> 'machine'), '') as machine,
           coalesce(public._p26_d(e.data ->> 'found_date'), e.entry_date) as fd,
           public._p26_d(e.data ->> 'done_date') as dd,
           case when e.data ->> 'found_time' ~ '^\d{1,2}:\d{2}' then (e.data ->> 'found_time')::time end as ft,
           case when e.data ->> 'done_time' ~ '^\d{1,2}:\d{2}' then (e.data ->> 'done_time')::time end as dt
      from public.entries e
     where e.form_code = '08-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)),
  r8 as (
    select m.*, (m.fd + coalesce(m.ft, time '00:00')) as fts, case when m.dd is not null then m.dd + coalesce(m.dt, time '00:00') end as dts,
           (select string_agg(pr.lbl, ', ') from (values ('p_stop', 'চলছে না / not running'), ('p_cool', 'ঠান্ডা হচ্ছে না / not cooling'), ('p_noise', 'শব্দ / noise'), ('p_leak', 'লিক / leak'),
              ('p_power', 'বিদ্যুৎ / electrical'), ('p_other', 'অন্য / other')) pr(k, lbl) where public._p26_b(m.data -> pr.k)) as problem
      from m),
  a as (
    select r8.*, (select count(*) from r8 o where o.location_id = r8.location_id and lower(o.machine) = lower(r8.machine) and o.fd between r8.fd - 365 and r8.fd)::int as repeat_n
      from r8 where r8.fd <= d2 and (r8.fd >= d1 or r8.dd is null)),
  s as (
    select '08-1'::text as source, a.fd as day, a.location_id, a.machine, a.problem,
           case when a.dd is null then 'খোলা / open' else 'শেষ / closed' end as status, a.ft::text as ftime,
           case when a.dts is not null and a.dts >= a.fts then round(extract(epoch from (a.dts - a.fts))::numeric / 3600, 1) end as downtime_h,
           public._r2_num(a.data -> 'est_cost') as est_cost, public._r2_num(a.data -> 'actual_cost') as actual_cost, a.repeat_n, null::text as ref
      from a
    union all
    select '05-1', e.entry_date, e.location_id, nullif(btrim(e.data ->> 'bd_machine'), ''), null, 'শিটে লেখা / on sheet', nullif(e.data ->> 'bd_time', ''), null, null, null, null, nullif(btrim(e.data ->> 'bd_request'), '')
      from public.entries e
     where e.form_code = '05-1' and e.status in ('submitted', 'approved') and e.data ->> 'breakdown' = 'yes' and e.entry_date between d1 and d2 and e.location_id = any (locs))
  select jsonb_build_object('source', s.source, 'day', s.day, 'location_bn', l.name_bn, 'machine', coalesce(s.machine, '-'), 'problem', s.problem, 'status', s.status, 'found_time', s.ftime,
    'downtime_h', s.downtime_h, 'est_cost', s.est_cost, 'actual_cost', s.actual_cost, 'repeat_n', s.repeat_n, 'request_ref', s.ref)
    from s join public.locations l on l.id = s.location_id;
$$;

-- ============================================================
-- M2 marketing spend (18-1 lines, dated by the line date, else the sheet date) and sales (status done) side by side per day and place. No ratio, no causal claim.
-- ============================================================
create or replace function public._r3q_m2_marketing_vs_sales(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with ml as (
    select e.location_id, coalesce(public._p26_d(ln ->> 'date'), e.entry_date) as day,
           public._r2_num(ln -> 'amt') as amt, public._r2_num(ln -> 'nonpay') as nonpay,
           case when ln ->> 'head' like 'other:%' then 'other' else coalesce(nullif(btrim(ln ->> 'head'), ''), '-') end as head
      from public.entries e cross join lateral jsonb_array_elements(public._p26_arr(e.data -> 'lines')) ln
     where e.form_code = '18-1' and e.status in ('submitted', 'approved') and e.location_id = any (locs)),
  mh as (
    select ml.location_id, ml.day, ml.head, sum(coalesce(ml.amt, 0)) as amt, sum(coalesce(ml.nonpay, 0)) as nonpay, count(*) as n
      from ml where ml.day between d1 and d2 and (ml.amt is not null or ml.nonpay is not null) group by 1, 2, 3),
  mk as (
    select h.location_id, h.day, sum(h.amt) as spend, sum(h.nonpay) as nonpay, sum(h.n) as n,
           string_agg(coalesce(o.label_bn, h.head) || ' ' || to_char(h.amt, 'FM999999999990.##'), ', ' order by h.amt desc) as heads
      from mh h left join public.option_lists o on o.list_code = 'marketing_heads' and o.value_code = h.head group by 1, 2),
  sl as (
    select s.location_id, s.sale_date as day, sum(s.total) as total, count(*) as n
      from public.sales s where s.status = 'done' and s.location_id = any (locs) and s.sale_date between d1 and d2 group by 1, 2)
  select jsonb_build_object('day', coalesce(mk.day, sl.day), 'location_bn', l.name_bn, 'spend', round(coalesce(mk.spend, 0), 2), 'nonpay_value', round(coalesce(mk.nonpay, 0), 2),
    'mkt_lines', coalesce(mk.n, 0), 'heads', mk.heads, 'sales_total', round(coalesce(sl.total, 0), 2), 'sales_n', coalesce(sl.n, 0))
    from mk full join sl on sl.location_id = mk.location_id and sl.day = mk.day
    join public.locations l on l.id = coalesce(mk.location_id, sl.location_id);
$$;

-- ============================================================
-- Q1 fridge temperature log: 05-1 (fridges, fridges2 rows 1-2) and 14-1 (fridges rows 1-3, t2_1 / t2_2 second reading on busy days).
--   limits from location_settings fridgeN_min / fridgeN_max; no limit set = out_n null (never guessed).
-- ============================================================
create or replace function public._r3q_q1_fridge_temp(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with rd as (
    select e.location_id, e.entry_date as day, e.serial, e.form_code as form, f.n,
           public._r2_num(case when jsonb_typeof(e.data -> 'fridges') = 'array' then e.data -> 'fridges' -> (f.n - 1) -> 'temp' end) as r1,
           case when e.form_code = '05-1' then public._r2_num(case when jsonb_typeof(e.data -> 'fridges2') = 'array' then e.data -> 'fridges2' -> (f.n - 1) -> 'temp' end)
                when f.n = 1 then public._r2_num(e.data -> 't2_1') when f.n = 2 then public._r2_num(e.data -> 't2_2') end as r2
      from public.entries e
      cross join lateral generate_series(1, case when e.form_code = '05-1' then 2 else 3 end) f(n)
     where e.form_code in ('05-1', '14-1') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  x as (
    select rd.*, (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_min') as lo,
           (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_max') as hi,
           (select ls.value #>> '{}' from public.location_settings ls where ls.location_id = rd.location_id and ls.key = 'fridge' || rd.n || '_name') as fname
      from rd where rd.r1 is not null or rd.r2 is not null)
  select jsonb_build_object('day', x.day, 'location_bn', l.name_bn, 'form', x.form, 'fridge', x.n, 'fridge_name', x.fname, 'reading1', x.r1, 'reading2', x.r2, 'min_c', x.lo, 'max_c', x.hi,
    'out_n', case when x.lo is null or x.hi is null then null
                  else (case when x.r1 is not null and (x.r1 < x.lo or x.r1 > x.hi) then 1 else 0 end) + (case when x.r2 is not null and (x.r2 < x.lo or x.r2 > x.hi) then 1 else 0 end) end)
    from x join public.locations l on l.id = x.location_id;
$$;

-- ============================================================
-- Q2 hygiene / expiry / checklist compliance per sheet: 14-1 (16 closing steps c1..c16, expired goods shown but not removed), 05-1 (hygiene, pots, equipment, cleaning, shut-down ticks)
-- ============================================================
create or replace function public._r3q_q2_hygiene(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with e0 as (
    select e.id, e.location_id, e.entry_date, e.form_code, e.data,
           case when e.form_code = '14-1' then array['c1','c2','c3','c4','c5','c6','c7','c8','c9','c10','c11','c12','c13','c14','c15','c16']
                else array['pots_done','hygiene_done','machines_done','clean_done','machines_off','gas_off','power_off','fire_safe'] end as ks
      from public.entries e
     where e.form_code in ('14-1', '05-1') and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  c as (
    select e0.*, cardinality(e0.ks) as total, (select count(*) from unnest(e0.ks) k where public._p26_b(e0.data -> k))::int as done,
           (select string_agg(k, ', ' order by ordinality) from unnest(e0.ks) with ordinality u(k, ordinality) where not public._p26_b(e0.data -> k)) as missed_list
      from e0)
  select jsonb_build_object('day', c.entry_date, 'location_bn', l.name_bn, 'form', c.form_code, 'checks', c.total, 'done', c.done, 'missed', c.total - c.done,
    'compliance_pct', round(c.done * 100.0 / c.total, 1),
    'expired_shown', case when c.form_code = '14-1' then (case when c.data ->> 'expired_shown' = 'yes' then 1 else 0 end) end,
    'expired_not_removed', case when c.form_code = '14-1' then (case when c.data ->> 'expired_shown' = 'yes' and not public._p26_b(c.data -> 'expired_removed') then 1 else 0 end) end,
    'missed_list', c.missed_list)
    from c join public.locations l on l.id = c.location_id;
$$;

-- ============================================================
-- Q3 complaints (20-3, one count per ticked cause) and sale returns (reason_code, per returned line) grouped by cause, product and place
-- ============================================================
create or replace function public._r3q_q3_complaints(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cat as (select public.rpt_arr_text(flt -> 'categories') as c),
  lbl(k, t) as (values ('taste', 'স্বাদ / taste'), ('smell', 'গন্ধ, নষ্ট / smell, spoiled'), ('broken', 'ভাঙা / broken'), ('short', 'পরিমাণে কম / short quantity'), ('wrong', 'ভুল পণ্য / wrong goods'),
                       ('late', 'দেরি / late'), ('staff', 'কর্মীর আচরণ / staff behaviour'), ('sick', 'খেয়ে অসুস্থ / fell ill'), ('other', 'অন্য / other'), ('none', 'কারণ টিক নেই / no cause ticked')),
  c1 as (
    select e.location_id, i.id as item_id, public._r2_num(e.data -> 'qty') as qty, public._r2_num(e.data -> 'refund_amt') as refund,
           nullif(btrim(e.check_data ->> 'root_cause'), '') is null as no_root, not public._p26_b(e.check_data -> 'resolved') as unresolved, public._p26_b(e.data -> 'c_sick') as sick,
           coalesce((select array_agg(k) from unnest(array['taste','smell','broken','short','wrong','late','staff','sick','other']) k where public._p26_b(e.data -> ('c_' || k))), array['none']) as ks
      from public.entries e left join public.items i on i.code = e.data ->> 'item'
     where e.form_code = '20-3' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  a as (
    select '20-3 অভিযোগ / complaint'::text as source, k as cause_code, c1.location_id, c1.item_id, count(*) as n, sum(c1.qty) as qty, sum(c1.refund) as refund,
           count(*) filter (where c1.unresolved) as unresolved, count(*) filter (where c1.sick) as sick, count(*) filter (where c1.no_root) as no_root
      from c1, unnest(c1.ks) k group by k, c1.location_id, c1.item_id),
  b as (
    select 'রিটার্ন / sale return'::text as source, sr.reason_code as cause_code, sr.location_id, nullif(x ->> 'item_id', '')::uuid as item_id, count(*) as n,
           sum(public._r2_num(x -> 'qty')) as qty, sum(public._r2_num(x -> 'amount')) as refund, null::bigint as unresolved, null::bigint as sick, null::bigint as no_root
      from public.sale_returns sr cross join lateral jsonb_array_elements(public._p26_arr(sr.lines)) x
     where sr.status = 'done' and sr.location_id = any (locs) and (sr.created_at at time zone 'Asia/Dhaka')::date between d1 and d2
       and (x ->> 'item_id') ~ '^[0-9a-f-]{36}$'
     group by sr.reason_code, sr.location_id, nullif(x ->> 'item_id', '')::uuid),
  u as (select * from a union all select * from b)
  select jsonb_build_object('source', u.source, 'cause', case when u.source like '20-3%' then coalesce(lbl.t, u.cause_code) else coalesce(o.label_bn, u.cause_code) end,
    'location_bn', l.name_bn, 'product_code', i.code, 'product_bn', coalesce(i.name_bn, '-'), 'n', u.n, 'qty', round(u.qty, 3), 'refund_amt', round(u.refund, 2),
    'unresolved', u.unresolved, 'sick', u.sick, 'no_root_cause', u.no_root)
    from u join public.locations l on l.id = u.location_id left join public.items i on i.id = u.item_id cross join cat
    left join lbl on u.source like '20-3%' and lbl.k = u.cause_code
    left join public.option_lists o on u.source not like '20-3%' and o.list_code = 'return_reasons' and o.value_code = u.cause_code
   where cat.c is null or i.category = any (cat.c);
$$;

-- ============================================================
-- the registry rows
-- ============================================================
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('p2_rate_trend', 'P2', 'purchase', 'ক্রয়-দর ধারা (আইটেম ও সাপ্লায়ার)', 'Purchase rate trend per item and supplier', 'ক্রয়-দর ধারা (Item ও Supplier)',
  '[["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["supplier","সাপ্লায়ার","Supplier","text"],["n","বার","Times","int"],["qty","পরিমাণ","Quantity","num"],["first_rate","প্রথম দর","First rate","money"],["last_rate","শেষ দর","Last rate","money"],["min_rate","সর্বনিম্ন","Lowest","money"],["max_rate","সর্বোচ্চ","Highest","money"],["avg_rate","গড় দর","Average rate","money"],["change_pct","বদল %","Change %","pct"],["last_date","শেষ তারিখ","Last date","date"]]'::jsonb,
  '{}', 'change_pct', 'desc', array['locations','categories'], false, true, false, 2601),
 ('p4_supplier_score', 'P4', 'purchase', 'সাপ্লায়ার স্কোরকার্ড', 'Supplier scorecard', 'Supplier স্কোরকার্ড',
  '[["supplier","সাপ্লায়ার","Supplier","text"],["grns","গ্রহণ রসিদ","GRNs","int"],["lines","লাইন","Lines","int"],["short_lines","কম পাওয়া লাইন","Short lines","int"],["rejected","ফেরত লাইন","Returned lines","int"],["held","আটক লাইন","Held lines","int"],["reduced","দর কমানো লাইন","Reduced-rate lines","int"],["bills_checked","যাচাই বিল","Bills checked","int"],["short_claims","ঘাটতির দাবি","Shortage claims","int"],["return_claims","ফেরতের দাবি","Return claims","int"],["pos","পারচেজ অর্ডার","POs","int"],["late_pos","দেরিতে আসা PO","Late POs","int"],["overdue_open","মেয়াদ পেরোনো খোলা PO","Overdue open POs","int"],["rate_change_pct","গড় দর বদল %","Avg rate change %","pct"],["rate_items","তুলনার আইটেম","Items compared","int"]]'::jsonb,
  array['grns','lines','short_lines','rejected','held','reduced','bills_checked','short_claims','return_claims','pos','late_pos','overdue_open'], 'rejected', 'desc', array['locations'], false, true, false, 2602),
 ('p5_po_match', 'P5', 'purchase', 'PO-GRN-বিল মিল ও খোলা PO', 'PO - GRN - bill match and open POs', 'PO-GRN-Bill মিল ও খোলা PO',
  '[["po_no","PO নং","PO no.","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["supplier","সাপ্লায়ার","Supplier","text"],["delivery_date","ডেলিভারির তারিখ","Delivery date","date"],["po_lines","PO লাইন","PO lines","int"],["lines_open","বাকি লাইন","Lines still open","int"],["po_total","PO মোট","PO total","money"],["grn_n","GRN সংখ্যা","GRNs","int"],["grn_value","GRN মূল্য","GRN value","money"],["bill_n","বিল","Bills","int"],["bill_amount","বিলের অঙ্ক","Bill amount","money"],["bill_diff","বিল − GRN","Bill − GRN","money"],["days_late","দেরি (দিন)","Days late","int"],["status","অবস্থা","Status","text"]]'::jsonb,
  '{}', 'days_late', 'desc', array['locations'], false, true, false, 2603),
 ('p6_purchase_budget', 'P6', 'purchase', 'ক্রয় বনাম বাজেট ও পূর্বাভাস', 'Purchases vs budget and outlook', 'ক্রয় বনাম Budget ও Outlook',
  '[["location_bn","লোকেশন","Location","text"],["day","শিটের তারিখ","Sheet date","date"],["cash_total","মোট হাতে","Total cash","money"],["receivable","প্রাপ্য (৭ দিন)","Receivable (7d)","money"],["payable","দেয় (৭ দিন)","Payable (7d)","money"],["min_cash","ন্যূনতম নগদ","Minimum cash","money"],["budget","পারচেজ বাজেট","Purchase budget","money"],["bills_7d","ক্রয় বিল (৭ দিন)","Purchase bills (7d)","money"],["grn_7d","GRN মূল্য (৭ দিন)","GRN value (7d)","money"],["spent","খরচ","Spent","money"],["used_pct","ব্যবহার %","Used %","pct"],["budget_left","বাজেটের বাকি","Budget left","money"],["outlook_low","পূর্বাভাস কম","Outlook low","money"],["outlook_high","পূর্বাভাস বেশি","Outlook high","money"]]'::jsonb,
  '{}', 'day', 'desc', array['locations'], false, true, false, 2604),
 ('k2_count_variance', 'K2', 'stock', 'স্টক গণনার পার্থক্য', 'Stock count variance', 'Stock গণনার পার্থক্য',
  '[["location_bn","লোকেশন","Location","text"],["counter","গণনাকারী","Counter","text"],["item_code","কোড","Code","text"],["item_bn","আইটেম","Item","text"],["counts","গণনা","Counts","int"],["off_n","পার্থক্য হয়েছে","Times off","int"],["short_n","কম","Short","int"],["over_n","বেশি","Over","int"],["net_var","নিট পার্থক্য","Net variance","num"],["abs_var","মোট পার্থক্য (চিহ্ন ছাড়া)","Absolute variance","num"],["off_pct","পার্থক্য %","Off %","pct"],["last_date","শেষ তারিখ","Last date","date"],["last_reason","শেষ কারণ","Last reason","text"]]'::jsonb,
  array['counts','off_n','short_n','over_n'], 'off_n', 'desc', array['locations','categories'], false, false, false, 2605),
 ('f1_production', 'F1', 'stock', 'দৈনিক উৎপাদন ও চালান', 'Production and dispatch', 'দৈনিক উৎপাদন ও Dispatch',
  '[["source","উৎস","Source","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["product_code","কোড","Code","text"],["product_bn","পণ্য","Product","text"],["unit","একক","Unit","text"],["batches","ব্যাচ","Batches","num"],["qty","পরিমাণ","Quantity","num"],["status","অবস্থা","Status","text"],["to_location_bn","গন্তব্য","To","text"]]'::jsonb,
  '{}', 'day', 'desc', array['locations'], false, false, false, 2606),
 ('f2_yield', 'F2', 'stock', 'ফলন বনাম স্ট্যান্ডার্ড', 'Yield vs standard', 'ফলন বনাম Standard',
  '[["location_bn","লোকেশন","Location","text"],["item_code","কোড","Code","text"],["item_bn","পণ্য","Product","text"],["std_yield","স্ট্যান্ডার্ড ফলন","Standard yield","num"],["tests_n","মাপ","Measurements","int"],["test_yield","মাপা ফলন","Measured yield","num"],["yield_diff_pct","পার্থক্য %","Difference %","pct"],["second_pct","২য় গ্রেড %","2nd grade %","pct"],["waste_pct","নষ্ট %","Waste %","pct"],["run_batches","রানের ব্যাচ","Run batches","num"],["run_qty","রানের পরিমাণ","Run quantity","num"],["sheet_qty","শিটের পরিমাণ","Sheet quantity","num"],["qty_gap","শিট − রান","Sheet − run","num"]]'::jsonb,
  '{}', 'yield_diff_pct', 'asc', array['locations'], false, false, false, 2607),
 ('f3_raw_vs_recipe', 'F3', 'stock', 'কাঁচামাল ব্যবহার বনাম রেসিপি', 'Raw material use vs recipe', 'কাঁচামাল ব্যবহার বনাম Recipe',
  '[["location_bn","লোকেশন","Location","text"],["product_code","পণ্যের কোড","Product code","text"],["product_bn","পণ্য","Product","text"],["ingredient_code","উপকরণের কোড","Ingredient code","text"],["ingredient_bn","উপকরণ","Ingredient","text"],["base_unit","একক","Unit","text"],["runs","রান","Runs","int"],["batches","ব্যাচ","Batches","num"],["expected","রেসিপি অনুযায়ী","Per recipe","num"],["actual","আসলে ইস্যু","Actually issued","num"],["diff","পার্থক্য","Difference","num"],["diff_pct","পার্থক্য %","Difference %","pct"],["waste_missing","অপচয়-% নেই","No waste % set","int"]]'::jsonb,
  '{}', 'diff_pct', 'desc', array['locations'], false, false, false, 2608),
 ('f4_breakdowns', 'F4', 'stock', 'মেশিন বন্ধ ও মেইনটেন্যান্স', 'Machine breakdowns and maintenance', 'Machine বন্ধ ও Maintenance',
  '[["source","উৎস","Source","text"],["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["machine","যন্ত্র","Machine","text"],["problem","সমস্যা","Problem","text"],["status","অবস্থা","Status","text"],["found_time","সময়","Time","text"],["downtime_h","বন্ধ (ঘণ্টা)","Down (hours)","num"],["est_cost","আনুমানিক খরচ","Estimated cost","money"],["actual_cost","প্রকৃত খরচ","Actual cost","money"],["repeat_n","এক বছরে বার","Times in a year","int"],["request_ref","অনুরোধ নং","Request no.","text"]]'::jsonb,
  array['downtime_h','est_cost','actual_cost'], 'day', 'desc', array['locations'], false, false, false, 2609),
 ('m2_marketing_vs_sales', 'M2', 'marketing', 'মার্কেটিং খরচ ও বিক্রি (একই দিন)', 'Marketing spend and sales, same days', 'Marketing খরচ ও বিক্রি (একই দিন)',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["spend","মার্কেটিং খরচ","Marketing spend","money"],["nonpay_value","টাকা ছাড়া মূল্য","Non-cash value","money"],["mkt_lines","খরচের লাইন","Expense lines","int"],["heads","খাত","Heads","text"],["sales_total","বিক্রি","Sales","money"],["sales_n","বিক্রির সংখ্যা","Sales count","int"]]'::jsonb,
  array['spend','nonpay_value','mkt_lines','sales_total','sales_n'], 'day', 'desc', array['locations'], false, false, false, 2610),
 ('q1_fridge_temp', 'Q1', 'quality', 'ফ্রিজ তাপমাত্রা লগ', 'Fridge temperature log', 'ফ্রিজ Temperature লগ',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["fridge","ফ্রিজ নং","Fridge no.","int"],["fridge_name","ফ্রিজের নাম","Fridge name","text"],["reading1","প্রথম পাঠ °C","Reading 1 °C","num"],["reading2","দ্বিতীয় পাঠ °C","Reading 2 °C","num"],["min_c","সর্বনিম্ন সীমা","Lower limit","num"],["max_c","সর্বোচ্চ সীমা","Upper limit","num"],["out_n","সীমার বাইরে (পাঠ)","Readings out of range","int"]]'::jsonb,
  array['out_n'], 'out_n', 'desc', array['locations'], false, false, false, 2611),
 ('q2_hygiene', 'Q2', 'quality', 'হাইজিন, মেয়াদ ও চেকলিস্ট পালন', 'Hygiene, expiry and checklist compliance', 'Hygiene, মেয়াদ ও Checklist পালন',
  '[["day","তারিখ","Date","date"],["location_bn","লোকেশন","Location","text"],["form","ফর্ম","Form","text"],["checks","ধাপ","Steps","int"],["done","সম্পন্ন","Done","int"],["missed","বাদ","Missed","int"],["compliance_pct","পালন %","Compliance %","pct"],["expired_shown","মেয়াদ-শেষ ডিসপ্লেতে","Expired shown","int"],["expired_not_removed","না সরানো","Not removed","int"],["missed_list","বাদ পড়া ধাপ","Missed steps","text"]]'::jsonb,
  array['checks','done','missed','expired_shown','expired_not_removed'], 'compliance_pct', 'asc', array['locations'], false, false, false, 2612),
 ('q3_complaints', 'Q3', 'quality', 'অভিযোগ ও রিটার্নের কারণ', 'Complaints and return causes', 'অভিযোগ ও Return-এর কারণ',
  '[["source","উৎস","Source","text"],["cause","কারণ","Cause","text"],["location_bn","লোকেশন","Location","text"],["product_code","কোড","Code","text"],["product_bn","পণ্য","Product","text"],["n","সংখ্যা","Count","int"],["qty","পরিমাণ","Quantity","num"],["refund_amt","ফেরত/মূল্য","Refund / value","money"],["unresolved","অমীমাংসিত","Unresolved","int"],["sick","অসুস্থ","Fell ill","int"],["no_root_cause","মূল কারণ নেই","No root cause","int"]]'::jsonb,
  array['n','unresolved','sick','no_root_cause'], 'n', 'desc', array['locations','categories'], false, false, false, 2613)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix, cols = excluded.cols, tot = excluded.tot,
  sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate, cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

revoke all on function public._p26_d(text), public._p26_b(jsonb), public._p26_arr(jsonb), public._p26_rates(date, date, int[]), public._p26_po(date, date, int[]), public._p26_outlook(int) from public, anon, authenticated;
select public._r3_lockdown();
notify pgrst, 'reload schema';
