-- Phase 410 (bos410) - RPT-B4 / R5b: TARGET VS ACHIEVEMENT (#9, #24), DAILY KPI SNAPSHOTS, KPI TRENDS AND EXCEPTION ALERTS (#10).
-- Paste after phase409. Paste-twice safe. No earlier phase file is edited. Reads existing sales data; writes only kpi_snapshots (a copy of already recorded figures).
--
--   rb4_target_report(from_month, to_month, place)   per place and month: target, achieved (net of returns while the rule reports_net_of_returns is on, same basis as the dashboard),
--                                                    pace (the share of the month gone, today counted), status, and the gross-profit % against its target when the reader has the cost right.
--   kpi_snapshot_take(from, to, redo)                keeps one row per closed day, place and measure. Idempotent: an existing day is left alone unless redo (owner / target manager) asks.
--                                                    Who: the owner, the sales report right, or the scheduler account that already runs notify_scan (select kpi_snapshot_take() after it).
--   rb4_kpi_trend(from, to, place)                   the daily series from the snapshots (days without a snapshot are listed as missing, never drawn as 0), and the alerts of the three owner limits.
-- Alerts are display only. A blank limit means no alert of that kind and the answer says so. Nothing is moved or posted.

do $g$ begin
  if to_regclass('public.kpi_snapshots') is null then raise exception 'phase410 needs phase409 first'; end if;
end $g$;

-- per day and place: what was sold, discounted, voided and returned (the raw material of both the target report and the snapshots)
create or replace function public._rb4_sales_days(f date, t date, locs int[]) returns table (d date, loc int, gross numeric, subtotal numeric, discount numeric, bills bigint, void_n bigint, void_amt numeric, returns_amt numeric)
language sql stable security definer set search_path = public as $$
  with s as (
    select x.sale_date as d, x.location_id as loc, sum(x.total) filter (where x.status = 'done') as gross, sum(x.subtotal) filter (where x.status = 'done') as subtotal, sum(x.discount) filter (where x.status = 'done') as discount,
           count(*) filter (where x.status = 'done') as bills, count(*) filter (where x.status = 'void') as void_n, sum(x.total) filter (where x.status = 'void') as void_amt
      from public.sales x where x.sale_date between f and t and x.location_id = any (locs) group by 1, 2),
  r as (
    select (c.created_at at time zone 'Asia/Dhaka')::date as d, c.location_id as loc, sum(c.amount) as returns_amt
      from public.sale_returns c where c.status = 'done' and (c.created_at at time zone 'Asia/Dhaka')::date between f and t and c.location_id = any (locs) group by 1, 2)
  select coalesce(s.d, r.d), coalesce(s.loc, r.loc), coalesce(s.gross, 0), coalesce(s.subtotal, 0), coalesce(s.discount, 0), coalesce(s.bills, 0), coalesce(s.void_n, 0), coalesce(s.void_amt, 0), coalesce(r.returns_amt, 0)
    from s full join r on s.d = r.d and s.loc = r.loc;
$$;

create or replace function public.rb4_target_report(p_from_month date default null, p_to_month date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date := date_trunc('month', coalesce(p_from_month, public._rb4_today()))::date; t date := date_trunc('month', coalesce(p_to_month, public._rb4_today()))::date; td date := public._rb4_today();
        net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true); locs int[]; costlocs int[]; rows_ jsonb; sm jsonb; notes jsonb := '[]'::jsonb; tend date;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  if t < f or t - f > 800 then raise exception 'bad_range'; end if;
  if p_loc is not null and not public._rb4_target_view(p_loc) then raise exception 'not allowed'; end if;
  select coalesce(array_agg(l.id), '{}') into locs from public.locations l where (p_loc is null or l.id = p_loc) and public._rb4_target_view(l.id);
  select coalesce(array_agg(l.id), '{}') into costlocs from public.locations l where l.id = any (locs) and public._cost_ok(l.id);
  tend := least((t + interval '1 month')::date - 1, td);
  with sd as (select date_trunc('month', x.d)::date as m, x.loc, sum(x.gross) as gross, sum(x.returns_amt) as ret, sum(x.bills) as bills from public._rb4_sales_days(f, greatest(tend, f), locs) x group by 1, 2),
  cg as (select date_trunc('month', h.d)::date as m, h.loc, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_rev + h.fb_rev)) as crev, sum((case h.src when 'sale' then 1 else -1 end) * (h.led_cogs + h.fb_cogs)) as cogs,
                sum((case h.src when 'sale' then 1 else -1 end) * h.unk_rev) as unk
           from public._cogs_lines72(f, greatest(tend, f), costlocs) h group by 1, 2),
  tg as (select s.* from public.sales_targets s where s.status = 'active' and s.month between f and t and s.location_id = any (locs)),
  keys as (select tg.month as m, tg.location_id as loc from tg union select sd.m, sd.loc from sd where sd.gross <> 0 or sd.ret <> 0),
  z as (
    select k.m, k.loc, tg.id as tid, tg.amount as target, tg.gp_pct as gp_target, coalesce(sd.gross, 0) as gross, coalesce(sd.ret, 0) as ret, coalesce(sd.bills, 0) as bills,
           coalesce(sd.gross, 0) - case when net_on then coalesce(sd.ret, 0) else 0 end as achieved,
           extract(day from (k.m + interval '1 month' - interval '1 day'))::int as dim,
           least(extract(day from (k.m + interval '1 month' - interval '1 day'))::int, greatest(0, td - k.m + 1)) as elapsed,
           cg.crev, cg.cogs, cg.unk, k.loc = any (costlocs) as money
      from keys k left join tg on tg.month = k.m and tg.location_id = k.loc left join sd on sd.m = k.m and sd.loc = k.loc left join cg on cg.m = k.m and cg.loc = k.loc)
  select coalesce(jsonb_agg(jsonb_build_object('month', z.m, 'location_id', z.loc, 'location', l.name_bn, 'location_en', l.name_en, 'target_id', z.tid,
      'target', z.target, 'achieved', round(z.achieved, 2), 'gross_sales', z.gross, 'returns', z.ret, 'bills', z.bills,
      'achievement_pct', case when z.target > 0 then round(z.achieved / z.target * 100, 1) end, 'shortfall', case when z.target is not null then round(greatest(z.target - z.achieved, 0), 2) end,
      'days_in_month', z.dim, 'days_elapsed', z.elapsed, 'pace_pct', case when z.target is not null then round(z.elapsed::numeric / z.dim * 100, 1) end,
      'pace_amount', case when z.target is not null then round(z.target * z.elapsed / z.dim, 2) end,
      'status', case when z.target is null then 'target_not_set' when z.m > td then 'not_started'
                     when (z.m + interval '1 month')::date <= td then case when z.achieved >= z.target then 'closed_met' else 'closed_missed' end
                     when z.achieved >= z.target then 'met' when z.achieved >= z.target * z.elapsed / z.dim then 'on_track' else 'behind' end,
      'gp_target_pct', z.gp_target,
      'gp_pct', case when z.money and z.crev > 0 then round((z.crev - z.cogs) / z.crev * 100, 2) end,
      'gp_gap_pp', case when z.money and z.crev > 0 and z.gp_target is not null then round((z.crev - z.cogs) / z.crev * 100 - z.gp_target, 2) end,
      'uncosted_pct', case when z.money and z.crev + coalesce(z.unk, 0) > 0 then round(coalesce(z.unk, 0) / (z.crev + coalesce(z.unk, 0)) * 100, 1) end,
      'gp_state', case when not z.money then 'cost_hidden' when z.crev is null or z.crev <= 0 then 'cost_not_captured' when z.gp_target is null then 'gp_target_not_set' else 'known' end) order by z.m desc, l.sort, z.loc), '[]'::jsonb)
    into rows_
    from z join public.locations l on l.id = z.loc;
  select jsonb_build_object('rows_with_target', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'target_id' is not null),
      'rows_without_target', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'target_id' is null),
      'target_total', (select sum((e ->> 'target')::numeric) from jsonb_array_elements(rows_) e where e ->> 'target_id' is not null),
      'achieved_total_for_targets', (select sum((e ->> 'achieved')::numeric) from jsonb_array_elements(rows_) e where e ->> 'target_id' is not null),
      'behind', (select count(*) from jsonb_array_elements(rows_) e where e ->> 'status' in ('behind', 'closed_missed')),
      'costs_hidden', exists (select 1 from public.locations l where l.id = any (locs) and not public._cost_ok(l.id))) into sm;
  if (sm ->> 'rows_with_target')::int = 0 then notes := notes || jsonb_build_object('code', 'target_not_set', 'field', 'sales target'); end if;
  return jsonb_build_object('from', f, 'to', t, 'rows', rows_, 'summary', sm, 'net_of_returns', net_on, 'notes', notes,
    'basis', 'Achieved = sales of the month that are done, less sale returns (while the rule reports_net_of_returns is on); the same basis as the dashboard. Pace = the share of the month that has passed (today counted) times the target. GP % is on the part of the sales whose cost is known.');
end $$;

-- one stored figure; returns 1 when a row was written
create or replace function public._rb4_kpi_put(p_d date, p_loc int, p_k text, p_v numeric, p_redo boolean) returns int
language plpgsql security definer set search_path = public as $$
declare cnt int;
begin
  if p_redo then
    insert into public.kpi_snapshots (snap_date, location_id, kpi, value, computed_by) values (p_d, p_loc, p_k, p_v, auth.uid())
      on conflict (snap_date, location_id, kpi) do update set value = excluded.value, computed_at = now(), computed_by = auth.uid();
    return 1;
  end if;
  insert into public.kpi_snapshots (snap_date, location_id, kpi, value, computed_by) values (p_d, p_loc, p_k, p_v, auth.uid()) on conflict (snap_date, location_id, kpi) do nothing;
  get diagnostics cnt = row_count;
  return cnt;
end $$;

create or replace function public.kpi_snapshot_take(p_from date default null, p_to date default null, p_redo boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare td date := public._rb4_today(); f date := coalesce(p_from, td - 1); t date := coalesce(p_to, coalesce(p_from, td - 1)); ops boolean; locs int[]; n int := 0; r record; redo boolean := coalesce(p_redo, false);
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  ops := public._is_ops('notify');
  if not (ops or public.is_owner() or public.rpt_access('sales')) then raise exception 'not allowed'; end if;
  if redo and not (public.is_owner() or public._rb4_target_edit()) then raise exception 'not allowed'; end if;
  if t < f or t - f > 100 then raise exception 'bad_range'; end if;
  if t >= td then raise exception 'day_not_closed'; end if;      -- today is not finished: a snapshot of it would mislead
  select coalesce(array_agg(l.id), '{}') into locs from public.locations l where l.is_active and (ops or public.is_owner() or public.can_loc(l.id));
  -- places that sell: every closed day gets its figures (a day with no sale is a real 0 for a place that sells at all)
  for r in
    select days.d, s.loc, coalesce(sd.gross, 0) as gross, coalesce(sd.returns_amt, 0) as ret, coalesce(sd.bills, 0) as bills, coalesce(sd.subtotal, 0) as subtotal, coalesce(sd.discount, 0) as disc,
           coalesce(sd.void_n, 0) as void_n, coalesce(sd.void_amt, 0) as void_amt
      from (select generate_series(f, t, interval '1 day')::date as d) days
      cross join (select x.location_id as loc from public.sales x where x.location_id = any (locs) group by 1 union select c.location_id from public.sale_returns c where c.location_id = any (locs) group by 1) s
      left join public._rb4_sales_days(f, t, locs) sd on sd.d = days.d and sd.loc = s.loc loop
    n := n + public._rb4_kpi_put(r.d, r.loc, 'gross_sales', r.gross, redo) + public._rb4_kpi_put(r.d, r.loc, 'returns_amt', r.ret, redo) + public._rb4_kpi_put(r.d, r.loc, 'bills_n', r.bills, redo)
           + public._rb4_kpi_put(r.d, r.loc, 'subtotal_amt', r.subtotal, redo) + public._rb4_kpi_put(r.d, r.loc, 'discount_amt', r.disc, redo)
           + public._rb4_kpi_put(r.d, r.loc, 'void_n', r.void_n, redo) + public._rb4_kpi_put(r.d, r.loc, 'void_amt', r.void_amt, redo);
  end loop;
  -- places that produce
  for r in
    select days.d, m.loc, coalesce(pr.runs_n, 0) as runs_n, pr.ys, pr.ya
      from (select generate_series(f, t, interval '1 day')::date as d) days
      cross join (select x.location_id as loc from public.production_runs x where x.location_id = any (locs) group by 1) m
      left join (select public._rb4_day(x.made_at) as d, x.location_id as loc, count(*) as runs_n, sum(x.yield_std) filter (where x.yield_actual is not null) as ys, sum(x.yield_actual) filter (where x.yield_actual is not null) as ya
                   from public.production_runs x where x.status = 'done' and public._rb4_day(x.made_at) between f and t and x.location_id = any (locs) group by 1, 2) pr on pr.d = days.d and pr.loc = m.loc loop
    n := n + public._rb4_kpi_put(r.d, r.loc, 'runs_n', r.runs_n, redo) + public._rb4_kpi_put(r.d, r.loc, 'yield_std_measured', r.ys, redo) + public._rb4_kpi_put(r.d, r.loc, 'yield_actual_measured', r.ya, redo);
  end loop;
  return jsonb_build_object('from', f, 'to', t, 'rows_written', n, 'redo', redo);
end $$;

create or replace function public.rb4_kpi_trend(p_from date default null, p_to date default null, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare f date; t date; td date := public._rb4_today(); net_on boolean := coalesce(public.rule_on('reports_net_of_returns'), true);
        l_drop numeric := public.rule_num('kpi_alert_sales_drop_pct'); l_disc numeric := public.rule_num('kpi_alert_discount_pct'); l_void numeric := public.rule_num('kpi_alert_void_n');
        days_ jsonb; places jsonb; alerts jsonb; missing jsonb; notes jsonb := '[]'::jsonb; exc jsonb; short_hist int;
begin
  if not public.is_active() then raise exception 'not allowed'; end if;
  select x.f, x.t into f, t from public._rb4_range(p_from, p_to) x;
  if p_loc is not null and not public._rb4_target_view(p_loc) then raise exception 'not allowed'; end if;
  with sn as (
    select s.snap_date as d, s.location_id as loc,
           max(s.value) filter (where s.kpi = 'gross_sales') as gross, max(s.value) filter (where s.kpi = 'returns_amt') as ret, max(s.value) filter (where s.kpi = 'bills_n') as bills,
           max(s.value) filter (where s.kpi = 'subtotal_amt') as subtotal, max(s.value) filter (where s.kpi = 'discount_amt') as disc, max(s.value) filter (where s.kpi = 'void_n') as void_n,
           max(s.value) filter (where s.kpi = 'void_amt') as void_amt, max(s.value) filter (where s.kpi = 'runs_n') as runs_n,
           max(s.value) filter (where s.kpi = 'yield_std_measured') as ys, max(s.value) filter (where s.kpi = 'yield_actual_measured') as ya
      from public.kpi_snapshots s where s.snap_date between f - 28 and t and (p_loc is null or s.location_id = p_loc) and public._rb4_target_view(s.location_id) group by 1, 2),
  nt as (select sn.*, case when sn.gross is not null then sn.gross - case when net_on then coalesce(sn.ret, 0) else 0 end end as net from sn),
  cur as (select * from nt where d between f and t)
  select coalesce((select jsonb_agg(jsonb_build_object('day', x.d, 'places_covered', x.pc, 'net_sales', x.net, 'gross_sales', x.gross, 'returns', x.ret, 'bills', x.bills,
              'avg_bill', case when x.bills > 0 then round(x.gross / x.bills, 2) end, 'discount_pct', case when x.subtotal > 0 then round(x.disc / x.subtotal * 100, 2) end,
              'void_n', x.void_n, 'void_amt', x.void_amt, 'runs_n', x.runs_n, 'yield_var_pct', case when x.ys > 0 then round((x.ya - x.ys) / x.ys * 100, 2) end) order by x.d)
            from (select d, count(*) as pc, sum(net) as net, sum(gross) as gross, sum(ret) as ret, sum(bills) as bills, sum(subtotal) as subtotal, sum(disc) as disc, sum(void_n) as void_n, sum(void_amt) as void_amt, sum(runs_n) as runs_n, sum(ys) as ys, sum(ya) as ya
                    from cur group by d) x), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('location_id', g.loc, 'location', l.name_bn, 'location_en', l.name_en, 'days', g.n, 'net_sales', g.net, 'bills', g.bills,
              'avg_bill', case when g.bills > 0 then round(g.gross / g.bills, 2) end, 'discount_pct', case when g.subtotal > 0 then round(g.disc / g.subtotal * 100, 2) end, 'void_n', g.void_n) order by l.sort, g.loc)
            from (select loc, count(*) as n, sum(net) as net, sum(gross) as gross, sum(bills) as bills, sum(subtotal) as subtotal, sum(disc) as disc, sum(void_n) as void_n from cur group by loc) g join public.locations l on l.id = g.loc), '[]'::jsonb),
         coalesce((select jsonb_agg(z.j order by z.d desc, z.loc, z.k)
            from (
              select c.d, c.loc, 'sales_drop' as k, jsonb_build_object('day', c.d, 'location_id', c.loc, 'location', lo.name_bn, 'location_en', lo.name_en, 'kind', 'sales_drop', 'value', c.net, 'reference', round(r.avg_ref, 2),
                       'drop_pct', round((r.avg_ref - c.net) / r.avg_ref * 100, 1), 'limit', l_drop, 'reference_days', r.n_ref) as j
                from cur c join public.locations lo on lo.id = c.loc
                cross join lateral (select avg(p.net) as avg_ref, count(*) as n_ref from nt p where p.loc = c.loc and p.d < c.d and p.d >= c.d - 28 and extract(dow from p.d) = extract(dow from c.d) and p.net is not null) r
               where l_drop is not null and c.net is not null and r.n_ref >= 2 and r.avg_ref > 0 and c.net < r.avg_ref * (1 - l_drop / 100)
              union all
              select c.d, c.loc, 'discount_high', jsonb_build_object('day', c.d, 'location_id', c.loc, 'location', lo.name_bn, 'location_en', lo.name_en, 'kind', 'discount_high', 'value', round(c.disc / c.subtotal * 100, 2), 'limit', l_disc)
                from cur c join public.locations lo on lo.id = c.loc where l_disc is not null and c.subtotal > 0 and c.disc / c.subtotal * 100 > l_disc
              union all
              select c.d, c.loc, 'void_high', jsonb_build_object('day', c.d, 'location_id', c.loc, 'location', lo.name_bn, 'location_en', lo.name_en, 'kind', 'void_high', 'value', c.void_n, 'limit', l_void)
                from cur c join public.locations lo on lo.id = c.loc where l_void is not null and c.void_n > l_void) z), '[]'::jsonb),
         (select count(*) from cur c cross join lateral (select count(*) as n_ref from nt p where p.loc = c.loc and p.d < c.d and p.d >= c.d - 28 and extract(dow from p.d) = extract(dow from c.d) and p.net is not null) r
           where l_drop is not null and c.net is not null and r.n_ref < 2)
    into days_, places, alerts, short_hist;
  -- closed days of the period without any snapshot: said, never drawn as 0
  select coalesce(jsonb_agg(d.d order by d.d), '[]'::jsonb) into missing
    from (select generate_series(f, least(t, td - 1), interval '1 day')::date as d) d
   where not exists (select 1 from public.kpi_snapshots s where s.snap_date = d.d and (p_loc is null or s.location_id = p_loc) and public._rb4_target_view(s.location_id));
  if l_drop is null then notes := notes || jsonb_build_object('code', 'alert_limit_not_set', 'field', 'kpi_alert_sales_drop_pct'); end if;
  if l_disc is null then notes := notes || jsonb_build_object('code', 'alert_limit_not_set', 'field', 'kpi_alert_discount_pct'); end if;
  if l_void is null then notes := notes || jsonb_build_object('code', 'alert_limit_not_set', 'field', 'kpi_alert_void_n'); end if;
  if short_hist > 0 then notes := notes || jsonb_build_object('code', 'not_enough_history', 'days', short_hist); end if;
  if jsonb_array_length(days_) = 0 then notes := notes || jsonb_build_object('code', 'snapshot_not_captured', 'field', 'daily KPI snapshot'); end if;
  select jsonb_build_object('red', count(*) filter (where e.level = 'red'), 'yellow', count(*) filter (where e.level = 'yellow')) into exc
    from public.exceptions e where e.status = 'open' and (e.location_id is null or public.can_loc(e.location_id));
  return jsonb_build_object('from', f, 'to', t, 'days', days_, 'places', places, 'alerts', alerts, 'missing_days', missing, 'net_of_returns', net_on, 'open_exceptions', exc,
    'limits', jsonb_build_object('sales_drop_pct', l_drop, 'discount_pct', l_disc, 'void_n', l_void), 'notes', notes,
    'basis', 'From the daily snapshots. A day without a snapshot is listed as missing, not drawn as 0. Sales drop = a day below the average of the previous 4 same weekdays (at least 2 needed) by more than the owner limit. Alerts are display only.');
end $$;

do $p$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_rb4_sales_days', '_rb4_kpi_put') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('rb4_target_report', 'kpi_snapshot_take', 'rb4_kpi_trend') loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;

notify pgrst, 'reload schema';
