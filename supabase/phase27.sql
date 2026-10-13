-- ============================================================
-- PHASE 27 (group profit, engine 3 reports): L1 L2 L3 L4 L5 T3 T4
--   l1_pnl            profit & loss by month and shop            (cost, owner only)
--   l2_margin         margin by item and by category             (cost)
--   l3_shop_pnl       shop P&L side by side                      (cost, owner only)
--   l4_owner_sheet    owner's 01-2 sheet vs computed system      (cost, owner only)
--   l5_breakeven      break-even and cost coverage               (cost)
--   t3_payroll        payroll & advances (02-2, 02-3)            (owner only)
--   t4_staff_cost_ratio  salary / sales % by shop                (owner only)
-- Needs phase24 (report_defs3). Additive, idempotent. Costs only for cost-right holders; salary only for the owner.
-- Sources: sales (status done) net of sale_returns (rule reports_net_of_returns, default ON) exactly like biz_daily (phase23);
--   COGS only on lines whose item has a cost (item_costs, count_in_business) - the rest is shown as "uncosted %", never guessed;
--   expenses = 10-2 lines (as expense_by_head); salary = 02-2 pay lines; fixed = location setting fixed_cost_month (prorated by days of the month inside the period).
-- ============================================================

-- shared P&L builder: one row per month x shop. Private (no grants), called only from the _r3q_ functions (definer).
create or replace function public._p27_pl(d1 date, d2 date, locs int[])
returns table (o_m date, o_loc int, o_gross numeric, o_ret numeric, o_net numeric, o_costed numeric, o_cogs numeric, o_exp numeric, o_sal numeric, o_fixed numeric)
language sql stable security definer set search_path = public as $$
  with net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.id, date_trunc('month', x.sale_date)::date as m, x.location_id, x.total, x.subtotal, x.lines from public.sales x
        where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  tot as (select m, location_id, sum(total) as rev from s group by 1, 2),
  ln as (
    select s.m, s.location_id, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty,
           case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end as iid
    from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  ag as (
    select ln.m, ln.location_id, sum(ln.amt * ln.f) filter (where c.cost_price is not null) as cr, sum(ln.qty * c.cost_price) filter (where c.cost_price is not null) as cg
    from ln left join cst c on c.item_id = ln.iid group by 1, 2),
  rr as (select r.id, date_trunc('month', (r.created_at at time zone 'Asia/Dhaka')::date)::date as m, r.location_id, r.amount, r.lines
         from public.sale_returns r, net_on
         where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  rt as (select m, location_id, sum(amount) as ra from rr group by 1, 2),
  rl as (
    select rr.m, rr.location_id, c.cost_price,
           case when e->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'amount')::numeric end as amt,
           case when e->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (e->>'qty')::numeric end as qty
    from rr cross join lateral jsonb_array_elements(case when jsonb_typeof(rr.lines) = 'array' then rr.lines else '[]'::jsonb end) e
    left join cst c on c.item_id = (case when e->>'item_id' ~ '^[0-9a-f-]{36}$' then (e->>'item_id')::uuid end)),
  rg as (select m, location_id, sum(amt) filter (where cost_price is not null) as rcr, sum(qty * cost_price) filter (where cost_price is not null) as rcg from rl group by 1, 2),
  ex as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id, sum(public._r2_num(ln -> 'amount')) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'lines') = 'array' then e.data -> 'lines' else '[]'::jsonb end) ln
    where e.form_code = '10-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  sa as (
    select date_trunc('month', e.entry_date)::date as m, e.location_id,
           sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as amt
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs) group by 1, 2),
  k as (select m, location_id from tot union select m, location_id from rt union select m, location_id from ex union select m, location_id from sa)
  select k.m, k.location_id,
         coalesce(t.rev, 0), coalesce(x.ra, 0), coalesce(t.rev, 0) - coalesce(x.ra, 0),
         round(coalesce(a.cr, 0) - coalesce(g.rcr, 0), 2), round(coalesce(a.cg, 0) - coalesce(g.rcg, 0), 2),
         e.amt, s2.amt,
         case when fm.v is not null then round(fm.v * (least(d2, (k.m + interval '1 month')::date - 1) - greatest(d1, k.m) + 1)
                / extract(day from (k.m + interval '1 month' - interval '1 day')), 2) end
  from k
  left join tot t on t.m = k.m and t.location_id = k.location_id
  left join rt x on x.m = k.m and x.location_id = k.location_id
  left join ag a on a.m = k.m and a.location_id = k.location_id
  left join rg g on g.m = k.m and g.location_id = k.location_id
  left join ex e on e.m = k.m and e.location_id = k.location_id
  left join sa s2 on s2.m = k.m and s2.location_id = k.location_id
  left join lateral (select public._r2_num(ls.value) as v from public.location_settings ls where ls.location_id = k.location_id and ls.key = 'fixed_cost_month') fm on true;
$$;
revoke all on function public._p27_pl(date, date, int[]) from public, anon, authenticated;

-- ---------- L1 profit & loss by month and shop ----------
create or replace function public._r3q_l1_pnl(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'month', to_char(p.o_m, 'YYYY-MM'), 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'sales', round(p.o_gross, 2), 'returns', round(p.o_ret, 2), 'net_sales', round(p.o_net, 2),
    'cogs', round(p.o_cogs, 2),
    'uncosted_pct', case when p.o_net > 0 then round(100 * greatest(p.o_net - p.o_costed, 0) / p.o_net, 2) end,
    'expenses', round(p.o_exp, 2), 'salary', round(p.o_sal, 2), 'fixed', p.o_fixed,
    'profit', round(p.o_net - p.o_cogs - coalesce(p.o_exp, 0) - coalesce(p.o_sal, 0) - coalesce(p.o_fixed, 0), 2),
    'gaps', nullif(concat_ws(', ', case when p.o_exp is null then 'expenses' end, case when p.o_sal is null then 'salary' end, case when p.o_fixed is null then 'fixed' end, case when p.o_net > 0 and p.o_costed < p.o_net then 'cogs(uncosted)' end), ''))
  from public._p27_pl(d1, d2, locs) p join public.locations l on l.id = p.o_loc;
$$;

-- ---------- L3 shop P&L comparison ----------
create or replace function public._r3q_l3_shop_pnl(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_exp) ex, sum(o_sal) sal, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object(
    'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'cogs', round(a.cogs, 2),
    'uncosted_pct', case when a.net > 0 then round(100 * greatest(a.net - a.costed, 0) / a.net, 2) end,
    'expenses', round(a.ex, 2), 'salary', round(a.sal, 2), 'fixed', a.fx,
    'profit', round(a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0), 2),
    'profit_pct', case when a.net > 0 then round(100 * (a.net - a.cogs - coalesce(a.ex, 0) - coalesce(a.sal, 0) - coalesce(a.fx, 0)) / a.net, 2) end,
    'gaps', nullif(concat_ws(', ', case when a.ex is null then 'expenses' end, case when a.sal is null then 'salary' end, case when a.fx is null then 'fixed' end, case when a.net > 0 and a.costed < a.net then 'cogs(uncosted)' end), ''))
  from a join public.locations l on l.id = a.o_loc;
$$;

-- ---------- L2 margin by item and by category ----------
create or replace function public._r3q_l2_margin(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with cats as (select public.rpt_arr_text(flt -> 'categories') as c),
  net_on as (select coalesce(public.rule_on('reports_net_of_returns'), true) as v),
  cst as (select ic.item_id, ic.cost_price from public.item_costs ic join public.items i on i.id = ic.item_id where i.count_in_business and ic.cost_price is not null),
  s as (select x.total, x.subtotal, x.lines from public.sales x where x.status = 'done' and x.sale_date between d1 and d2 and x.location_id = any (locs)),
  sl as (
    select 1 as sg, (case when s.subtotal > 0 then s.total / s.subtotal else 1 end) as f, e as le from s, jsonb_array_elements(case when jsonb_typeof(s.lines) = 'array' then s.lines else '[]'::jsonb end) e),
  rl as (
    select -1 as sg, 1::numeric as f, e as le from public.sale_returns r, net_on, jsonb_array_elements(case when jsonb_typeof(r.lines) = 'array' then r.lines else '[]'::jsonb end) e
    where net_on.v and r.status = 'done' and (r.created_at at time zone 'Asia/Dhaka')::date between d1 and d2 and r.location_id = any (locs)),
  u as (select sg, f, le from sl union all select sg, f, le from rl),
  p as (
    select sg * f as sf, sg,
           case when le->>'amount' ~ '^[0-9]+(\.[0-9]+)?$' then (le->>'amount')::numeric end as amt,
           case when le->>'qty' ~ '^[0-9]+(\.[0-9]+)?$' then (le->>'qty')::numeric end as qty,
           case when le->>'item_id' ~ '^[0-9a-f-]{36}$' then (le->>'item_id')::uuid end as iid
    from u),
  j as (
    select i.id as item_id, coalesce(i.code, '-') as icode, coalesce(i.name_bn, '(item not linked)') as nbn, coalesce(i.name_en, i.name_bn, '(item not linked)') as nen,
           coalesce(nullif(btrim(i.category), ''), '-') as cat, p.sf, p.sg, p.amt, p.qty, c.cost_price
    from p left join public.items i on i.id = p.iid left join cst c on c.item_id = p.iid),
  jf as (select j.* from j, cats where cats.c is null or j.cat = any (cats.c)),
  ia as (
    select item_id, icode, nbn, nen, cat, sum(sf * amt) as rev, sum(sg * qty) as qty,
           sum(sf * amt) filter (where cost_price is not null) as crev, sum(sg * qty * cost_price) filter (where cost_price is not null) as cg
    from jf group by item_id, icode, nbn, nen, cat),
  ca as (select cat, sum(rev) as rev, sum(crev) as crev, sum(cg) as cg from ia group by cat)
  select jsonb_build_object('level', 'item', 'category', ia.cat, 'item_code', ia.icode, 'item_name', ia.nbn, 'item_name_en', ia.nen,
    'qty', round(ia.qty, 3), 'revenue', round(ia.rev, 2), 'cogs', round(ia.cg, 2),
    'margin', case when ia.crev is not null then round(ia.crev - ia.cg, 2) end,
    'margin_pct', case when ia.crev > 0 then round(100 * (ia.crev - ia.cg) / ia.crev, 2) end,
    'uncosted_pct', case when ia.rev > 0 then round(100 * greatest(ia.rev - coalesce(ia.crev, 0), 0) / ia.rev, 2) end)
  from ia
  union all
  select jsonb_build_object('level', 'category', 'category', ca.cat, 'item_code', null, 'item_name', null, 'item_name_en', null,
    'qty', null, 'revenue', round(ca.rev, 2), 'cogs', round(ca.cg, 2),
    'margin', case when ca.crev is not null then round(ca.crev - ca.cg, 2) end,
    'margin_pct', case when ca.crev > 0 then round(100 * (ca.crev - ca.cg) / ca.crev, 2) end,
    'uncosted_pct', case when ca.rev > 0 then round(100 * greatest(ca.rev - coalesce(ca.crev, 0), 0) / ca.rev, 2) end)
  from ca;
$$;

-- ---------- L4 owner's monthly sheet (01-2) vs system ----------
create or replace function public._r3q_l4_owner_sheet(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with sh as (
    select e.id, e.location_id, e.entry_date, e.data ->> 'scope' as scope, btrim(e.data ->> 'month') as mon,
           public._r2_num(e.data -> 'sales') as s_sales,
           case when public._r2_num(e.data -> 'open_stock') is not null and public._r2_num(e.data -> 'purchases') is not null and public._r2_num(e.data -> 'close_stock') is not null
                then public._r2_num(e.data -> 'open_stock') + public._r2_num(e.data -> 'purchases') - public._r2_num(e.data -> 'close_stock') end as s_cogs,
           (select sum(public._r2_num(kv.value)) from jsonb_each(e.data) kv where kv.key like 'x\_%') as s_exp,
           public._r2_num(e.data -> 'salary') as s_sal, public._r2_num(e.data -> 'bank_charges') as s_bank
    from public.entries e
    where e.form_code = '01-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)),
  mm as (
    select sh.*, case when sh.mon ~ '^[0-9]{4}-([1-9]|0[1-9]|1[0-2])$' then to_date(sh.mon || '-01', 'YYYY-MM-DD') end as ms from sh),
  sy as (
    select mm.id, case when mm.ms is null or mm.scope not in ('all', 'loc') then false else true end as ok,
           (select array[sum(p.o_net), sum(p.o_costed), sum(p.o_cogs), sum(p.o_exp), sum(p.o_sal)] from public._p27_pl(mm.ms, (mm.ms + interval '1 month')::date - 1,
              case when mm.scope = 'all' then locs else array[mm.location_id] end) p) as v
    from mm)
  select jsonb_build_object('month', mm.mon, 'location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en, 'scope', mm.scope,
    'sheet_sales', mm.s_sales, 'sys_sales', case when sy.ok then round(sy.v[1], 2) end,
    'diff_sales', case when sy.ok and mm.s_sales is not null then round(mm.s_sales - sy.v[1], 2) end,
    'sheet_cogs', mm.s_cogs, 'sys_cogs', case when sy.ok then round(sy.v[3], 2) end,
    'sys_uncosted_pct', case when sy.ok and sy.v[1] > 0 then round(100 * greatest(sy.v[1] - sy.v[2], 0) / sy.v[1], 2) end,
    'sheet_expenses', mm.s_exp, 'sys_expenses', case when sy.ok then round(sy.v[4], 2) end,
    'diff_expenses', case when sy.ok and mm.s_exp is not null and sy.v[4] is not null then round(mm.s_exp - sy.v[4], 2) end,
    'sheet_salary', mm.s_sal, 'sys_salary', case when sy.ok then round(sy.v[5], 2) end,
    'diff_salary', case when sy.ok and mm.s_sal is not null and sy.v[5] is not null then round(mm.s_sal - sy.v[5], 2) end,
    'sheet_net', case when mm.s_sales is not null and mm.s_cogs is not null then round(mm.s_sales - mm.s_cogs - coalesce(mm.s_exp, 0) - coalesce(mm.s_sal, 0) - coalesce(mm.s_bank, 0), 2) end,
    'sys_net', case when sy.ok then round(sy.v[1] - sy.v[3] - coalesce(sy.v[4], 0) - coalesce(sy.v[5], 0), 2) end)
  from mm join sy on sy.id = mm.id join public.locations l on l.id = mm.location_id;
$$;

-- ---------- L5 break-even and cost coverage ----------
create or replace function public._r3q_l5_breakeven(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_costed) costed, sum(o_cogs) cogs, sum(o_fixed) fx from public._p27_pl(d1, d2, locs) group by o_loc),
  b as (select a.*, case when a.costed > 0 and a.costed - a.cogs > 0 then (a.costed - a.cogs) / a.costed end as gm,
          (select public._r2_num(ls.value) from public.location_settings ls where ls.location_id = a.o_loc and ls.key = 'fixed_cost_month') as fm from a)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(b.net, 2),
    'uncosted_pct', case when b.net > 0 then round(100 * greatest(b.net - b.costed, 0) / b.net, 2) end,
    'gm_pct', case when b.gm is not null then round(100 * b.gm, 2) end,
    'fixed', b.fx,
    'be_sales', case when b.gm is not null and b.fx is not null then round(b.fx / b.gm, 2) end,
    'gap', case when b.gm is not null and b.fx is not null then round(b.net - b.fx / b.gm, 2) end,
    'coverage_pct', case when b.gm is not null and b.fx > 0 then round(100 * b.net / (b.fx / b.gm), 2) end,
    'fixed_month', b.fm,
    'be_month', case when b.gm is not null and b.fm is not null then round(b.fm / b.gm, 2) end)
  from b join public.locations l on l.id = b.o_loc;
$$;

-- ---------- T3 payroll & advances (02-2 salary sheets, 02-3 advance register) ----------
create or replace function public._r3q_t3_payroll(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with pay as (
    select e.id, e.location_id, btrim(r ->> 'name') as nm,
           coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0) as gross,
           coalesce(public._r2_num(r -> 'adv_ded'), 0) as adv_ded, coalesce(public._r2_num(r -> 'other_ded'), 0) as oth_ded
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
    where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between d1 and d2 and e.location_id = any (locs)
      and btrim(coalesce(r ->> 'name', '')) <> ''),
  pg as (select location_id, lower(nm) as k, min(nm) as nm, count(distinct id) as sheets, sum(gross) as gross, sum(adv_ded) as adv_ded, sum(oth_ded) as oth_ded from pay group by 1, 2),
  av as (
    select e.location_id, lower(btrim(e.data ->> 'staff')) as k, min(btrim(e.data ->> 'staff')) as nm,
           sum(public._r2_num(r -> 'amount')) as given, sum(public._r2_num(r -> 'ded_now')) as ded_now
    from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) r
    where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (locs) and btrim(coalesce(e.data ->> 'staff', '')) <> ''
      and coalesce(case when r ->> 'date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (r ->> 'date')::date end, e.entry_date) between d1 and d2
    group by 1, 2),
  ob as (
    select distinct on (e.location_id, lower(btrim(e.data ->> 'staff'))) e.location_id, lower(btrim(e.data ->> 'staff')) as k, btrim(e.data ->> 'staff') as nm,
           (select sum(public._r2_num(r -> 'balance')) from jsonb_array_elements(case when jsonb_typeof(e.data -> 'adv') = 'array' then e.data -> 'adv' else '[]'::jsonb end) r) as outstanding
    from public.entries e
    where e.form_code = '02-3' and e.status in ('submitted', 'approved') and e.location_id = any (locs) and btrim(coalesce(e.data ->> 'staff', '')) <> '' and e.entry_date <= d2
    order by e.location_id, lower(btrim(e.data ->> 'staff')), e.entry_date desc, e.created_at desc),
  ks as (select location_id, k from pg union select location_id, k from av union select location_id, k from ob)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'person', coalesce(pg.nm, av.nm, ob.nm), 'sheets', pg.sheets,
    'gross_pay', round(pg.gross, 2), 'adv_deducted', round(pg.adv_ded, 2), 'other_deducted', round(pg.oth_ded, 2),
    'net_pay', round(pg.gross - pg.adv_ded - pg.oth_ded, 2),
    'adv_given', round(av.given, 2), 'adv_register_deduction', round(av.ded_now, 2), 'adv_outstanding', round(ob.outstanding, 2))
  from ks join public.locations l on l.id = ks.location_id
  left join pg on pg.location_id = ks.location_id and pg.k = ks.k
  left join av on av.location_id = ks.location_id and av.k = ks.k
  left join ob on ob.location_id = ks.location_id and ob.k = ks.k;
$$;

-- ---------- T4 staff cost / sales % by shop ----------
create or replace function public._r3q_t4_staff_cost_ratio(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb
language sql stable security definer set search_path = public as $$
  with a as (select o_loc, sum(o_net) net, sum(o_sal) sal from public._p27_pl(d1, d2, locs) group by o_loc)
  select jsonb_build_object('location_id', l.id, 'location_bn', l.name_bn, 'location_en', l.name_en,
    'net_sales', round(a.net, 2), 'salary', round(a.sal, 2),
    'salary_pct', case when a.net > 0 and a.sal is not null then round(100 * a.sal / a.net, 2) end)
  from a join public.locations l on l.id = a.o_loc;
$$;

-- ---------- registry ----------
insert into public.report_defs3 (key, code, grp, name_bn, name_en, name_mix, cols, tot, sort_key, sort_dir, allow, nodate, cost, owner_only, sort) values
 ('l1_pnl', 'L1', 'profit', 'লাভ-ক্ষতি (মাস ও দোকান অনুযায়ী)', 'Profit & loss by month and shop', 'লাভ-ক্ষতি (P&L)',
  '[["month","মাস","Month","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],
    ["sales","বিক্রি (সম্পন্ন বিক্রি)","Sales (done sales)","money"],["returns","রিটার্ন (বিক্রি-রিটার্ন)","Returns (sale returns)","money"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["cogs","মালের খরচ (শুধু খরচ-ধরা লাইন; আইটেম খরচ)","COGS (costed lines only; item costs)","money"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],
    ["expenses","ব্যয় (ভাউচার ১০-২)","Expenses (voucher 10-2)","money"],["salary","বেতন (বেতন শিট ০২-২)","Salary (salary sheet 02-2)","money"],
    ["fixed","স্থির খরচ (লোকেশন সেটিং, দিন অনুপাতে)","Fixed cost (location setting, pro rata)","money"],["profit","লাভ / (ক্ষতি)","Profit / (loss)","money"],["gaps","যা পাওয়া যায়নি","Missing inputs","text"]]'::jsonb,
  array['sales','returns','net_sales','cogs','expenses','salary','fixed','profit'], 'month', 'desc', array['locations','brands'], false, true, true, 270),
 ('l2_margin', 'L2', 'profit', 'আইটেম ও ক্যাটাগরি মার্জিন', 'Margin by item and category', 'আইটেম / Category margin',
  '[["level","স্তর","Level","text"],["category","ক্যাটাগরি","Category","text"],["item_code","কোড","Code","text"],["item_name","আইটেম","Item","text"],["item_name_en","Item (EN)","Item (EN)","text"],
    ["qty","পরিমাণ","Qty","num"],["revenue","বিক্রি (রিটার্ন বাদে)","Sales (net of returns)","money"],["cogs","মালের খরচ (খরচ-ধরা লাইন)","COGS (costed lines)","money"],
    ["margin","মার্জিন (খরচ-ধরা লাইনে)","Margin (costed lines)","money"],["margin_pct","মার্জিন %","Margin %","pct"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"]]'::jsonb,
  '{}', 'revenue', 'desc', array['locations','brands','categories'], false, true, false, 271),
 ('l3_shop_pnl', 'L3', 'profit', 'দোকান P&L তুলনা', 'Shop P&L comparison', 'দোকান P&L তুলনা',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["cogs","মালের খরচ (খরচ-ধরা লাইন)","COGS (costed lines)","money"],["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],["expenses","ব্যয় (১০-২)","Expenses (10-2)","money"],
    ["salary","বেতন (০২-২)","Salary (02-2)","money"],["fixed","স্থির খরচ","Fixed cost","money"],["profit","লাভ / (ক্ষতি)","Profit / (loss)","money"],["profit_pct","লাভ %","Profit %","pct"],["gaps","যা পাওয়া যায়নি","Missing inputs","text"]]'::jsonb,
  array['net_sales','cogs','expenses','salary','fixed','profit'], 'profit_pct', 'asc', array['locations','brands'], false, true, true, 272),
 ('l4_owner_sheet', 'L4', 'profit', 'মালিকের মাসিক শিট বনাম সিস্টেম', 'Owner monthly sheet vs system', 'মালিকের শিট (01-2) vs system',
  '[["month","মাস","Month","text"],["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["scope","পরিধি","Scope","text"],
    ["sheet_sales","শিট: বিক্রি","Sheet: sales","money"],["sys_sales","সিস্টেম: নিট বিক্রি","System: net sales","money"],["diff_sales","পার্থক্য: বিক্রি","Diff: sales","money"],
    ["sheet_cogs","শিট: মালের খরচ (শুরু+ক্রয়−শেষ)","Sheet: COGS (open+purch−close)","money"],["sys_cogs","সিস্টেম: মালের খরচ (খরচ-ধরা লাইন)","System: COGS (costed lines)","money"],["sys_uncosted_pct","সিস্টেম: খরচ-ছাড়া বিক্রি %","System: uncosted sales %","pct"],
    ["sheet_expenses","শিট: ব্যয়","Sheet: expenses","money"],["sys_expenses","সিস্টেম: ব্যয় (১০-২)","System: expenses (10-2)","money"],["diff_expenses","পার্থক্য: ব্যয়","Diff: expenses","money"],
    ["sheet_salary","শিট: বেতন","Sheet: salary","money"],["sys_salary","সিস্টেম: বেতন (০২-২)","System: salary (02-2)","money"],["diff_salary","পার্থক্য: বেতন","Diff: salary","money"],
    ["sheet_net","শিট: নিট লাভ","Sheet: net profit","money"],["sys_net","সিস্টেম: নিট লাভ (স্থির খরচ ছাড়া)","System: net profit (before fixed cost)","money"]]'::jsonb,
  '{}', 'month', 'desc', array['locations','brands'], false, true, true, 273),
 ('l5_breakeven', 'L5', 'profit', 'ব্রেক-ইভেন ও খরচ কভারেজ', 'Break-even and cost coverage', 'Break-even ও cost coverage',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],
    ["uncosted_pct","খরচ-ছাড়া বিক্রির %","Uncosted sales %","pct"],["gm_pct","গ্রস মার্জিন % (খরচ-ধরা লাইনে)","Gross margin % (costed lines)","pct"],["fixed","স্থির খরচ (সময়ের জন্য)","Fixed cost (for the period)","money"],
    ["be_sales","ব্রেক-ইভেন বিক্রি (সময়ের)","Break-even sales (period)","money"],["gap","বিক্রি − ব্রেক-ইভেন","Sales − break-even","money"],["coverage_pct","কভারেজ %","Coverage %","pct"],
    ["fixed_month","মাসিক স্থির খরচ","Monthly fixed cost","money"],["be_month","মাসিক ব্রেক-ইভেন বিক্রি","Monthly break-even sales","money"]]'::jsonb,
  array['net_sales','fixed','be_sales'], 'coverage_pct', 'asc', array['locations','brands'], false, true, false, 274),
 ('t3_payroll', 'T3', 'profit', 'বেতন ও অ্যাডভান্স', 'Payroll and advances', 'বেতন ও Advance',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["person","কর্মী (নাম মিলিয়ে)","Person (matched by name)","text"],["sheets","বেতন শিট","Salary sheets","int"],
    ["gross_pay","মোট পাওনা (০২-২)","Total due (02-2)","money"],["adv_deducted","অ্যাডভান্স কর্তন (০২-২)","Advance deducted (02-2)","money"],["other_deducted","অন্য কর্তন","Other deduction","money"],["net_pay","নিট বেতন","Net pay","money"],
    ["adv_given","অ্যাডভান্স দেওয়া (০২-৩)","Advance given (02-3)","money"],["adv_register_deduction","রেজিস্টারে কর্তন (০২-৩)","Deduction in register (02-3)","money"],["adv_outstanding","বকেয়া অ্যাডভান্স (০২-৩, সর্বশেষ পাতা)","Advance outstanding (02-3, latest page)","money"]]'::jsonb,
  array['gross_pay','adv_deducted','other_deducted','net_pay','adv_given','adv_register_deduction','adv_outstanding'], 'net_pay', 'desc', array['locations','brands'], false, false, true, 275),
 ('t4_staff_cost_ratio', 'T4', 'profit', 'স্টাফ খরচ ÷ বিক্রি', 'Staff cost / sales %', 'Staff খরচ ÷ বিক্রি %',
  '[["location_id","","","id"],["location_bn","লোকেশন","Location","text"],["location_en","Location (EN)","Location (EN)","text"],["net_sales","নিট বিক্রি","Net sales","money"],["salary","বেতন (০২-২)","Salary (02-2)","money"],["salary_pct","বেতন ÷ বিক্রি %","Salary ÷ sales %","pct"]]'::jsonb,
  array['net_sales','salary'], 'salary_pct', 'desc', array['locations','brands'], false, false, true, 276)
on conflict (key) do update set code = excluded.code, grp = excluded.grp, name_bn = excluded.name_bn, name_en = excluded.name_en, name_mix = excluded.name_mix,
  cols = excluded.cols, tot = excluded.tot, sort_key = excluded.sort_key, sort_dir = excluded.sort_dir, allow = excluded.allow, nodate = excluded.nodate,
  cost = excluded.cost, owner_only = excluded.owner_only, sort = excluded.sort, is_active = true;

select public._r3_lockdown();
