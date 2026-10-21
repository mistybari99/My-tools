-- ============================================================
-- Phase 456 - RPT-C2 / R6 part 2 (reports #148 sales per labour hour with punch coverage, #150 cashier-wise cash variance with shift). READ ONLY.
-- Run AFTER phase 455. New file only. Paste twice = no error.
--
--   #150  The daily showroom sheet 14-1 gets a "Cashier" box (web/forms_cash.js, additive; the shift box already exists on the sheet). Data is kept in the sheet's own data (key cashier), so no table changes.
--         c2_cashier_variance(from, to, place)  short / over of each sheet (the flag the phone wrote when the sheet was saved, the same figure as the hub report) grouped by cashier and shift;
--         sheets with no cashier written are listed apart ("cashier not written", with the sheet writer shown) - never given to a guessed person. The status of the shortage case (open / approved /
--         rejected / void) is shown beside the sheet, which the hub report ignores.
--   #148  c2_sales_per_labour_hour(from, to, place)  per place: sales (done sales, returns shown apart), labour hours = worked minutes of present / late / half-day records, and the punch coverage =
--         records with punches / records. Sales per hour is shown ONLY when the hours exist; the coverage is always beside it. Labour hours come from the app's day records, not from paper 02-1.
--   Open to the owner and to holders of the existing report rights (report_cash / report_pos for #150; report_staff / report_sales for #148, view_reports for both).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_att_period_summary(date,date,int,uuid)') is null then raise exception 'phase456 needs phase455 pasted first'; end if;
end $guard$;

create or replace function public.c2_cashier_variance(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb; sheets jsonb;
begin
  if not public.is_active() or not (public.rpt_access('cash') or public.rpt_access('pos') or public.can_do('14-1', 'view')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with x as (
    select e.id, e.location_id, e.entry_date, coalesce(nullif(btrim(e.data ->> 'shift'), ''), 'not_written') as shift, nullif(btrim(e.data ->> 'cashier'), '') as cashier,
           coalesce(nullif(btrim(e.created_staff), ''), '-') as writer,
           coalesce((select sum(public._c2_num(f -> 'amount')) from jsonb_array_elements(case when jsonb_typeof(e.flags) = 'array' then e.flags else '[]'::jsonb end) f where f ->> 'code' = 'cash_short_over'), 0) as so,
           (select c.status from public.shortage_cash_cases c where c.entry_id = e.id) as case_status
      from public.entries e where e.form_code = '14-1' and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to and public.can_loc(e.location_id) and (p_loc is null or e.location_id = p_loc)),
       n as (select x.*, (select coalesce(emp.full_name_en, emp.full_name_bn) from public.profiles pr join public.employees emp on emp.profile_id = pr.id where pr.staff_id = x.cashier limit 1) as cashier_name from x),
       g as (select cashier, max(cashier_name) as cashier_name, shift, count(*) as sheets, count(*) filter (where so < 0) as short_sheets, count(*) filter (where so > 0) as over_sheets,
                    coalesce(-sum(so) filter (where so < 0), 0) as short_amount, coalesce(sum(so) filter (where so > 0), 0) as over_amount, coalesce(sum(so), 0) as net, coalesce(max(abs(so)), 0) as worst,
                    count(*) filter (where case_status = 'open') as cases_open, count(*) filter (where case_status = 'approved') as cases_approved, count(*) filter (where case_status = 'rejected') as cases_rejected, count(*) filter (where case_status = 'void') as cases_void
               from n group by cashier, shift)
  select (select coalesce(jsonb_agg(to_jsonb(g) - 'cashier' || jsonb_build_object('cashier', coalesce(cashier, ''), 'cashier_written', cashier is not null) order by cashier is null, net, cashier), '[]'::jsonb) from g),
         (select jsonb_build_object('sheets', count(*), 'sheets_without_cashier', count(*) filter (where cashier is null), 'sheets_without_shift', count(*) filter (where shift = 'not_written'), 'short_amount', coalesce(-sum(so) filter (where so < 0), 0),
            'over_amount', coalesce(sum(so) filter (where so > 0), 0), 'net', coalesce(sum(so), 0)) from n),
         (select coalesce(jsonb_agg(jsonb_build_object('entry_id', id, 'loc', location_id, 'day', entry_date, 'shift', shift, 'cashier', cashier, 'writer', writer, 'variance', so, 'case_status', case_status) order by entry_date desc, id) filter (where cashier is null and so <> 0), '[]'::jsonb) from n)
    into rows, sm, sheets;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["same_flag_as_hub_cash_short_over","case_status_shown","cashier_box_new_on_14_1"]'::jsonb || (case when (sm ->> 'sheets_without_cashier')::int > 0 then '["cashier_not_written_on_some_sheets"]'::jsonb else '[]'::jsonb end),
    'summary', sm, 'rows', rows, 'uncredited_sheets_with_a_variance', sheets);
end $$;

create or replace function public.c2_sales_per_labour_hour(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare rows jsonb; sm jsonb;
begin
  if not public.is_active() or not (public.is_owner() or public.rpt_access('staff') or public.rpt_access('sales')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with l as (select l.id, l.name_bn, l.name_en from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc)),
       s as (select x.location_id, sum(x.total) as sales, count(*) as bills from public.sales x where x.status = 'done' and x.sale_date between p_from and p_to group by 1),
       r as (select y.location_id, sum(y.amount) as returns from public.sale_returns y where y.status = 'done' and (y.created_at at time zone 'Asia/Dhaka')::date between p_from and p_to group by 1),
       a as (select d.location_id, count(*) as staff_days, count(*) filter (where d.punch_count > 0) as days_with_punches, sum(d.worked_minutes) as worked, count(*) filter (where d.single_punch) as single_punch_days
               from public.attendance_days d where d.day between p_from and p_to and d.status in ('present', 'late', 'half_day') and d.location_id is not null group by 1),
       j as (select l.id, l.name_bn, l.name_en, coalesce(s.sales, 0) as sales, coalesce(s.bills, 0) as bills, coalesce(r.returns, 0) as returns, a.staff_days, a.days_with_punches, a.worked, a.single_punch_days
               from l left join s on s.location_id = l.id left join r on r.location_id = l.id left join a on a.location_id = l.id where s.location_id is not null or a.location_id is not null)
  select coalesce(jsonb_agg(jsonb_build_object('loc', id, 'name_bn', name_bn, 'name_en', name_en, 'sales', sales, 'bills', bills, 'returns', returns, 'net_sales', sales - returns,
            'staff_days', coalesce(staff_days, 0), 'labour_hours', case when coalesce(worked, 0) > 0 then round(worked / 60.0, 1) end,
            'punch_coverage_pct', case when coalesce(staff_days, 0) > 0 then round(100.0 * days_with_punches / staff_days, 1) end, 'single_punch_days', coalesce(single_punch_days, 0),
            'sales_per_hour', case when coalesce(worked, 0) > 0 then round((sales - returns) / (worked / 60.0), 2) end,
            'status', case when coalesce(staff_days, 0) = 0 then 'no_attendance_records' when coalesce(worked, 0) = 0 then 'no_hours' when days_with_punches < staff_days then 'partial_punches' else 'ok' end) order by id), '[]'::jsonb),
         jsonb_build_object('places', count(*), 'sales', coalesce(sum(sales), 0), 'returns', coalesce(sum(returns), 0), 'labour_hours', case when coalesce(sum(worked), 0) > 0 then round(sum(worked) / 60.0, 1) end,
            'punch_coverage_pct', case when coalesce(sum(staff_days), 0) > 0 then round(100.0 * sum(days_with_punches) / sum(staff_days), 1) end,
            'sales_per_hour', case when coalesce(sum(worked), 0) > 0 and bool_and(coalesce(worked, 0) > 0) then round((sum(sales) - sum(returns)) / (sum(worked) / 60.0), 2) end,
            'places_without_hours', count(*) filter (where coalesce(worked, 0) = 0))
    into rows, sm from j;
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["hours_from_app_day_records","returns_shown_apart","per_hour_only_where_hours_exist"]'::jsonb, 'summary', sm, 'rows', rows);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
