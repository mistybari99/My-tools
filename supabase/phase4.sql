-- ============================================================
-- BOS tool · Phase 4: business-logic functions (read-only analytics).
-- Run AFTER schema.sql, phase2.sql and phase3.sql. Run once. It changes no data.
--
-- Principle: nothing here is a fixed number. Every figure is computed from what staff entered
-- (sales, costs, expense vouchers), over a period the owner chooses, and limits are SUGGESTED from
-- history for the owner to accept, never applied automatically.
--   Cost-based figures (COGS, gross profit) need the cost-price permission (ITEM_COST view).
--   Costs use the CURRENT cost price of each item (price history is not re-costed).
--   Quick sales have no item, so they carry no cost: they are reported as "uncosted".
-- ============================================================

-- who may look at sales analytics: owner, or a role with approve on the POS form
create or replace function public.biz_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('POS', 'approve'));
$$;
create or replace function public.biz_cost_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_active() and (public.is_owner() or public.can_do('ITEM_COST', 'view'));
$$;

-- ---------- 1. day x location: revenue, discount, voids, cost of goods ----------
create or replace function public.biz_daily(p_from date, p_to date, p_loc int default null)
returns table (sale_date date, location_id int, n bigint, revenue numeric, discount numeric,
               void_n bigint, void_amt numeric, costed_rev numeric, cogs numeric)
language plpgsql stable security definer set search_path = public as $$
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and public.can_loc(x.location_id)),
  ok as (select * from s where s.status = 'done'),
  ln as (
    select o.sale_date, o.location_id, (case when o.subtotal > 0 then o.total / o.subtotal else 1 end) f,
           (e->>'amount')::numeric amt, (e->>'qty')::numeric qty, nullif(e->>'item_id', '')::uuid iid
    from ok o, jsonb_array_elements(o.lines) e),
  lc as (select l.*, c.cost_price from ln l left join public.item_costs c on c.item_id = l.iid),
  ag as (
    select lc.sale_date, lc.location_id,
           sum(lc.amt * lc.f) filter (where lc.cost_price is not null) cr,
           sum(lc.qty * lc.cost_price) filter (where lc.cost_price is not null) cg
    from lc group by 1, 2),
  tot as (select ok.sale_date, ok.location_id, count(*) n, sum(ok.total) rev, sum(ok.discount) disc from ok group by 1, 2),
  vd as (select s.sale_date, s.location_id, count(*) vn, sum(s.total) va from s where s.status = 'void' group by 1, 2)
  select coalesce(t.sale_date, v.sale_date), coalesce(t.location_id, v.location_id),
         coalesce(t.n, 0), coalesce(t.rev, 0), coalesce(t.disc, 0), coalesce(v.vn, 0), coalesce(v.va, 0),
         case when cost_ok then coalesce(a.cr, 0) end, case when cost_ok then coalesce(a.cg, 0) end
  from tot t
  full join vd v on v.sale_date = t.sale_date and v.location_id = t.location_id
  left join ag a on a.sale_date = coalesce(t.sale_date, v.sale_date) and a.location_id = coalesce(t.location_id, v.location_id)
  order by 1, 2;
end $$;

-- ---------- 2. item velocity, margin and Pareto (ABC) class ----------
-- ABC: items are ranked by revenue; A = the items that make the first 80% of revenue, B = up to 95%, C = the rest
-- (standard Pareto cut-offs). Items with no sale in the period are listed with zero (candidates for review).
create or replace function public.biz_items(p_from date, p_to date, p_loc int default null)
returns table (item_id uuid, code text, name_bn text, name_en text, unit text, qty numeric, revenue numeric,
               cogs numeric, share_pct numeric, cum_pct numeric, abc text)
language plpgsql stable security definer set search_path = public as $$
declare cost_ok boolean := public.biz_cost_ok();
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with ok as (
    select * from public.sales x
    where x.status = 'done' and x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and public.can_loc(x.location_id)),
  ln as (
    select nullif(e->>'item_id', '')::uuid iid, (e->>'qty')::numeric qty, round((e->>'amount')::numeric * (case when o.subtotal > 0 then o.total / o.subtotal else 1 end), 2) amt
    from ok o, jsonb_array_elements(o.lines) e),
  by_item as (select l.iid, sum(l.qty) q, sum(l.amt) r from ln l where l.iid is not null group by 1),
  tot as (select coalesce(sum(r), 0) t from by_item),
  j as (
    select i.id, i.code, i.name_bn, i.name_en, i.unit, coalesce(b.q, 0) q, coalesce(b.r, 0) r,
           case when cost_ok and c.cost_price is not null then coalesce(b.q, 0) * c.cost_price end cg
    from public.items i
    left join by_item b on b.iid = i.id left join public.item_costs c on c.item_id = i.id
    where i.is_active or b.iid is not null),
  r as (
    select j.*, case when (select t from tot) > 0 then round(100 * j.r / (select t from tot), 2) else 0 end sp,
           case when (select t from tot) > 0 then round(100 * sum(j.r) over (order by j.r desc, j.code) / (select t from tot), 2) else 0 end cp
    from j)
  select r.id, r.code, r.name_bn, r.name_en, r.unit, r.q, r.r, r.cg, r.sp, r.cp,
         case when r.r = 0 then '-' when r.cp - r.sp < 80 then 'A' when r.cp - r.sp < 95 then 'B' else 'C' end
  from r order by r.r desc, r.code;
end $$;

-- ---------- 3. staff control indicators vs the location's own peers ----------
-- Indicators only (not proof): each ratio is shown next to the peer MEDIAN. Whether a ratio counts as unusual is
-- the owner's call (setting `anomaly_ratio` in the app); no threshold is built in here.
create or replace function public.biz_staff(p_from date, p_to date, p_loc int default null)
returns table (staff_id text, n bigint, revenue numeric, discount_pct numeric, void_pct numeric, override_pct numeric,
               quick_pct numeric, due_pct numeric, med_discount_pct numeric, med_void_pct numeric,
               med_override_pct numeric, med_quick_pct numeric, med_due_pct numeric, peers bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_to < p_from or p_to - p_from > 400 then raise exception 'bad_range'; end if;
  return query
  with s as (
    select * from public.sales x
    where x.sale_date between p_from and p_to and (p_loc is null or x.location_id = p_loc) and public.can_loc(x.location_id)),
  ovr as (select s.id, bool_or(coalesce((e->>'override')::boolean, false)) o from s, jsonb_array_elements(s.lines) e group by s.id),
  per as (
    select s.created_staff st,
           count(*) filter (where s.status = 'done') n,
           coalesce(sum(s.total) filter (where s.status = 'done'), 0) rev,
           coalesce(sum(s.discount) filter (where s.status = 'done'), 0) disc,
           count(*) filter (where s.status = 'void') vn,
           count(*) filter (where s.status = 'done' and o.o) onum,
           count(*) filter (where s.status = 'done' and s.quick) qn,
           coalesce(sum(s.total) filter (where s.status = 'done' and s.pay_mode = 'due'), 0) duea
    from s left join ovr o on o.id = s.id group by s.created_staff),
  r as (
    select p.st, p.n, p.rev,
           case when p.rev + p.disc > 0 then round(100 * p.disc / (p.rev + p.disc), 2) end dp,
           case when p.n + p.vn > 0 then round(100 * p.vn::numeric / (p.n + p.vn), 2) end vp,
           case when p.n > 0 then round(100 * p.onum::numeric / p.n, 2) end op,
           case when p.n > 0 then round(100 * p.qn::numeric / p.n, 2) end qp,
           case when p.rev > 0 then round(100 * p.duea / p.rev, 2) end up
    from per p)
  select r.st, r.n, r.rev, r.dp, r.vp, r.op, r.qp, r.up,
         (select (percentile_cont(0.5) within group (order by x.dp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.vp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.op))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.qp))::numeric from r x),
         (select (percentile_cont(0.5) within group (order by x.up))::numeric from r x),
         (select count(*) from r)
  from r order by r.rev desc;
end $$;

-- ---------- 4. purchase outlook: what the coming days are likely to need, from actual sales ----------
-- Expected revenue for each coming day = average of the same weekday over the look-back (when at least 2 such days
-- exist, otherwise the plain daily average). Cost ratio = actual COGS / costed revenue over the look-back.
-- Estimated purchase need = expected revenue x cost ratio. It is an estimate for planning, not a limit.
create or replace function public.biz_outlook(p_loc int, p_ahead int default 7, p_lookback int default 28)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  td date := (now() at time zone 'Asia/Dhaka')::date; fr date; ndays int; rev numeric; costed numeric; cg numeric;
  avg_d numeric; exp_rev numeric; wd_used int; ratio numeric; share numeric;
begin
  if not public.biz_ok() then raise exception 'not allowed'; end if;
  if p_ahead < 1 or p_ahead > 31 or p_lookback < 7 or p_lookback > 120 then raise exception 'bad_range'; end if;
  fr := td - p_lookback;
  select count(distinct b.sale_date), coalesce(sum(b.revenue), 0), sum(b.costed_rev), sum(b.cogs)
    into ndays, rev, costed, cg from public.biz_daily(fr, td - 1, p_loc) b;
  if ndays = 0 then return jsonb_build_object('lookback_days', p_lookback, 'sale_days', 0, 'enough', false); end if;
  avg_d := rev / ndays;
  with d as (select b.sale_date, sum(b.revenue) r from public.biz_daily(fr, td - 1, p_loc) b group by 1),
       wd as (select extract(dow from d.sale_date)::int dw, count(*) n, avg(d.r) a from d group by 1),
       fut as (select td + g dt from generate_series(0, p_ahead - 1) g)
  select coalesce(sum(case when wd.n >= 2 then wd.a else avg_d end), 0), count(*) filter (where wd.n >= 2)
    into exp_rev, wd_used
  from fut left join wd on wd.dw = extract(dow from fut.dt)::int;
  if costed is not null and costed > 0 then ratio := cg / costed; share := costed / nullif(rev, 0); end if;
  return jsonb_build_object('lookback_days', p_lookback, 'sale_days', ndays, 'avg_daily_revenue', round(avg_d, 2),
    'ahead_days', p_ahead, 'weekday_pattern_days', wd_used, 'expected_revenue', round(exp_rev, 2),
    'cost_ratio', case when ratio is not null then round(ratio, 4) end,
    'costed_share', case when share is not null then round(share, 4) end,
    'est_purchase_need', case when ratio is not null then round(exp_rev * ratio, 2) end,
    'enough', ndays >= 7);
end $$;

-- ---------- 5. limit suggestions from history (owner only; nothing is applied here) ----------
-- Expense voucher (10-2) lines of submitted/approved entries: spread of single expenses and of daily totals.
create or replace function public.biz_suggest(p_loc int, p_days int default 90)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare res jsonb;
begin
  if not public.is_owner() then raise exception 'not allowed'; end if;
  if p_days < 14 or p_days > 365 then raise exception 'bad_range'; end if;
  with l as (
    select e.entry_date d, case when x->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (x->>'amount')::numeric end amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data->'lines') = 'array' then e.data->'lines' else '[]'::jsonb end) x
    where e.form_code = '10-2' and e.location_id = p_loc and e.status in ('submitted', 'approved')
      and e.entry_date >= (now() at time zone 'Asia/Dhaka')::date - p_days),
  dd as (select d, sum(amt) t from l where amt is not null group by d),
  a as (select count(amt) n, (percentile_cont(0.5) within group (order by amt))::numeric med, (percentile_cont(0.9) within group (order by amt))::numeric p90, max(amt) mx from l where amt is not null),
  b as (select count(*) n, (percentile_cont(0.5) within group (order by t))::numeric med, (percentile_cont(0.9) within group (order by t))::numeric p90, max(t) mx from dd)
  select jsonb_build_object('window_days', p_days,
      'expense', jsonb_build_object('n', a.n, 'median', round(a.med, 2), 'p90', round(a.p90, 2), 'max', a.mx),
      'daily_total', jsonb_build_object('days', b.n, 'median', round(b.med, 2), 'p90', round(b.p90, 2), 'max', b.mx))
    into res from a, b;
  return res || jsonb_build_object(
    'current_expense_max', (select value from public.location_settings where location_id = p_loc and key = 'expense_max'),
    'current_imprest', (select value from public.location_settings where location_id = p_loc and key = 'imprest'));
end $$;

grant execute on function public.biz_ok(), public.biz_cost_ok(),
  public.biz_daily(date, date, int), public.biz_items(date, date, int), public.biz_staff(date, date, int),
  public.biz_outlook(int, int, int), public.biz_suggest(int, int) to authenticated;
