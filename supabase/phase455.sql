-- ============================================================
-- Phase 455 - RPT-C2 / R6 part 1 (reports #142 attendance summary for a period, #147 overtime and late variance, and the salary-basis notice for the T3 / T4 staff-cost reports). READ ONLY.
-- Run AFTER phase 454. New file only. Paste twice = no error.
--
--   Source: the app's day records (attendance_days: punches, late, early, worked and overtime minutes). The hub report attendance_summary reads the paper sheet 02-1 only and shows nothing while the app
--   holds the days; this report reads the app days and says how many paper 02-1 sheets exist beside them (their data is NOT added).
--   c2_att_period_summary(from, to, place, employee)   per person: days by status, late days / minutes, early-leave minutes, worked minutes, overtime (approved / waiting), single-punch days, manual days,
--        scheduled minutes and variance (worked - scheduled) ONLY over days that have a shift - days without a shift are counted apart; calendar days with no record at all are counted apart.
--   c2_att_person_days(employee, from, to)             the day rows behind one person (drill-down).
--   c2_salary_basis(from, to, place)                   the salary figure the staff-cost and profit reports (T3, T4, L1) use, beside the 02-2 paper sheets and the counted / paid payroll runs, the two
--        settings that decide which one is used, and the difference. Needs the salary right (salary_view) or the owner. Does not change any report.
--   Who: the owner, a holder of report_staff / view_reports for the person's place, or anyone who may already see that person's attendance (own record, attendance_manage, employee_view, employee_manage).
-- ============================================================
do $guard$ begin
  if to_regprocedure('public.c2_customer_card(uuid)') is null then raise exception 'phase455 needs phase454 pasted first'; end if;
end $guard$;

create or replace function public.c2_can_read_staff() returns boolean language sql stable security definer set search_path = public as $$
  select public.is_active();
$$;
-- one employee row is visible when the existing attendance rule allows it, or the person holds a staff report right for that place
create or replace function public._c2_emp_visible(p_emp uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public._att_view(p_emp) or (public.rpt_access('staff') and exists (select 1 from public.employees e where e.id = p_emp and e.primary_location_id is not null and public.can_loc(e.primary_location_id)));
$$;
create or replace function public._c2_shift_minutes(p_start time, p_end time, p_cross boolean, p_break int) returns int language sql immutable as $$
  select ((extract(epoch from p_end) - extract(epoch from p_start)) / 60)::int + case when p_cross or p_end <= p_start then 1440 else 0 end - coalesce(p_break, 0);
$$;

create or replace function public.c2_att_period_summary(p_from date, p_to date, p_loc int default null, p_employee uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare today date := public._dhaka_today(); rows jsonb; sm jsonb; paper int; last_d date := least(p_to, today);
begin
  if not public.c2_can_read_staff() then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  with emp as (select e.id, e.employee_no, e.full_name_bn, e.full_name_en, e.primary_location_id as loc, e.joining_date, e.status
                 from public.employees e
                where e.status in ('active', 'on_leave', 'resigned', 'terminated', 'retired') and public._c2_emp_visible(e.id) and (p_loc is null or e.primary_location_id = p_loc) and (p_employee is null or e.id = p_employee)
                  and (e.status in ('active', 'on_leave') or exists (select 1 from public.attendance_days a where a.employee_id = e.id and a.day between p_from and p_to))),
       d as (select a.*, s.id as sid, case when s.id is not null then public._c2_shift_minutes(s.start_time, s.end_time, s.crosses_midnight, s.break_min) end as sched
               from public.attendance_days a join emp on emp.id = a.employee_id left join public.shifts s on s.id = a.shift_id where a.day between p_from and p_to),
       agg as (select d.employee_id,
                      count(*) as days_with_record,
                      count(*) filter (where d.status = 'present') as present, count(*) filter (where d.status = 'late') as late_status, count(*) filter (where d.status = 'absent') as absent,
                      count(*) filter (where d.status = 'half_day') as half_day, count(*) filter (where d.status = 'leave') as leave, count(*) filter (where d.status = 'unpaid') as unpaid,
                      count(*) filter (where d.status = 'off') as off, count(*) filter (where d.status = 'holiday') as holiday,
                      count(*) filter (where d.late_minutes > 0) as late_days, coalesce(sum(d.late_minutes), 0) as late_minutes, coalesce(sum(d.early_leave_minutes), 0) as early_leave_minutes,
                      coalesce(sum(d.worked_minutes), 0) as worked_minutes, coalesce(sum(d.ot_minutes), 0) as ot_minutes, coalesce(sum(d.ot_minutes) filter (where d.ot_approved), 0) as ot_approved_minutes,
                      coalesce(sum(d.ot_minutes) filter (where not d.ot_approved), 0) as ot_waiting_minutes,
                      count(*) filter (where d.single_punch) as single_punch_days, count(*) filter (where d.source = 'manual') as manual_days,
                      count(*) filter (where d.status in ('present', 'late', 'half_day') and d.sched is not null) as days_with_shift, count(*) filter (where d.status in ('present', 'late', 'half_day') and d.sched is null) as days_without_shift,
                      sum(d.sched) filter (where d.status in ('present', 'late', 'half_day') and d.sched is not null) as scheduled_minutes,
                      sum(d.worked_minutes - d.sched) filter (where d.status in ('present', 'late', 'half_day') and d.sched is not null) as variance_minutes
                 from d group by d.employee_id),
       r as (select emp.*, greatest(last_d - greatest(p_from, coalesce(emp.joining_date, p_from)) + 1, 0) as expected_days, agg.*
               from emp left join agg on agg.employee_id = emp.id)
  select (select coalesce(jsonb_agg(jsonb_build_object('employee_id', id, 'employee_no', employee_no, 'name_bn', full_name_bn, 'name_en', full_name_en, 'loc', loc, 'status', status,
            'calendar_days', expected_days, 'days_with_record', coalesce(days_with_record, 0), 'days_without_record', greatest(expected_days - coalesce(days_with_record, 0), 0),
            'present', coalesce(present, 0), 'late_status', coalesce(late_status, 0), 'absent', coalesce(absent, 0), 'half_day', coalesce(half_day, 0), 'leave', coalesce(leave, 0), 'unpaid', coalesce(unpaid, 0), 'off', coalesce(off, 0), 'holiday', coalesce(holiday, 0),
            'late_days', coalesce(late_days, 0), 'late_minutes', coalesce(late_minutes, 0), 'early_leave_minutes', coalesce(early_leave_minutes, 0), 'worked_minutes', coalesce(worked_minutes, 0),
            'ot_minutes', coalesce(ot_minutes, 0), 'ot_approved_minutes', coalesce(ot_approved_minutes, 0), 'ot_waiting_minutes', coalesce(ot_waiting_minutes, 0),
            'single_punch_days', coalesce(single_punch_days, 0), 'manual_days', coalesce(manual_days, 0), 'days_with_shift', coalesce(days_with_shift, 0), 'days_without_shift', coalesce(days_without_shift, 0),
            'scheduled_minutes', scheduled_minutes, 'variance_minutes', variance_minutes) order by coalesce(full_name_en, full_name_bn), id), '[]'::jsonb) from r),
         (select jsonb_build_object('people', count(*), 'people_with_no_record_at_all', count(*) filter (where coalesce(days_with_record, 0) = 0), 'days_with_record', coalesce(sum(days_with_record), 0),
            'days_without_record', coalesce(sum(greatest(expected_days - coalesce(days_with_record, 0), 0)), 0), 'late_days', coalesce(sum(late_days), 0), 'late_minutes', coalesce(sum(late_minutes), 0), 'absent', coalesce(sum(absent), 0),
            'worked_minutes', coalesce(sum(worked_minutes), 0), 'ot_minutes', coalesce(sum(ot_minutes), 0), 'ot_waiting_minutes', coalesce(sum(ot_waiting_minutes), 0),
            'scheduled_minutes', sum(scheduled_minutes), 'variance_minutes', sum(variance_minutes), 'days_without_shift', coalesce(sum(days_without_shift), 0)) from r)
    into rows, sm;
  select count(*) into paper from public.entries en where en.form_code = '02-1' and en.status in ('submitted', 'approved') and en.entry_date between p_from and p_to and public.can_loc(en.location_id) and (p_loc is null or en.location_id = p_loc);
  return jsonb_build_object('from', p_from, 'to', p_to, 'notes', '["app_days_only","calendar_days_without_record_counted_apart","variance_only_days_with_a_shift"]'::jsonb || (case when paper > 0 then '["paper_02_1_not_included"]'::jsonb else '[]'::jsonb end),
    'paper_02_1_sheets_in_range', paper, 'summary', sm, 'rows', rows);
end $$;

create or replace function public.c2_att_person_days(p_employee uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.c2_can_read_staff() or not public._c2_emp_visible(p_employee) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  return jsonb_build_object('employee_id', p_employee, 'from', p_from, 'to', p_to, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('day', a.day, 'status', a.status, 'day_kind', a.day_kind, 'first_in', a.first_in at time zone 'Asia/Dhaka', 'last_out', a.last_out at time zone 'Asia/Dhaka', 'worked_minutes', a.worked_minutes,
             'late_minutes', a.late_minutes, 'early_leave_minutes', a.early_leave_minutes, 'ot_minutes', a.ot_minutes, 'ot_approved', a.ot_approved, 'punch_count', a.punch_count, 'single_punch', a.single_punch, 'source', a.source,
             'shift_id', a.shift_id, 'scheduled_minutes', case when s.id is not null then public._c2_shift_minutes(s.start_time, s.end_time, s.crosses_midnight, s.break_min) end,
             'variance_minutes', case when s.id is not null and a.status in ('present', 'late', 'half_day') then a.worked_minutes - public._c2_shift_minutes(s.start_time, s.end_time, s.crosses_midnight, s.break_min) end, 'note', a.note) order by a.day)
      from public.attendance_days a left join public.shifts s on s.id = a.shift_id where a.employee_id = p_employee and a.day between p_from and p_to), '[]'::jsonb));
end $$;

-- the salary basis notice
create or replace function public.c2_salary_basis(p_from date, p_to date, p_loc int default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare locs int[]; rows jsonb; sm jsonb; src text := coalesce(public.rule_txt('report_salary_source'), 'legacy'); acc boolean := public.rule_on('payroll_accrual_on');
begin
  if not public.is_active() or not (public.is_owner() or public.has_grant('salary_view')) then raise exception 'not allowed'; end if;
  perform public._c2_range(p_from, p_to);
  if p_loc is not null and not public.can_loc(p_loc) then raise exception 'not allowed for this location'; end if;
  select coalesce(array_agg(l.id), '{}') into locs from public.locations l where public.can_loc(l.id) and (p_loc is null or l.id = p_loc);
  with u as (select o_m as m, sum(o_sal) as reports_use from public._p27_pl(p_from, p_to, locs) group by o_m),
       sh as (select date_trunc('month', e.entry_date)::date as m,
                     sum(coalesce(public._r2_num(r -> 'due'), 0) + coalesce(public._r2_num(r -> 'overtime'), 0) + coalesce(public._r2_num(r -> 'other'), 0)) as sheets, count(distinct e.id) as sheet_count
                from public.entries e, jsonb_array_elements(case when jsonb_typeof(e.data -> 'pay') = 'array' then e.data -> 'pay' else '[]'::jsonb end) r
               where e.form_code = '02-2' and e.status in ('submitted', 'approved') and e.entry_date between p_from and p_to and e.location_id = any (locs) group by 1),
       cn as (select c.m, sum(c.amt) as runs_counted from public.c_salary_by_month(p_from, p_to, locs) c group by c.m),
       pd as (select r.month as m, sum(l.net + l.advance_recovery) as runs_paid, count(distinct r.id) as paid_runs
                from public.payroll_runs r join public.payroll_lines l on l.run_id = r.id and l.active
               where r.status = 'paid' and r.month between date_trunc('month', p_from)::date and p_to and coalesce(l.location_id, r.location_id) = any (locs) group by 1),
       mm as (select m from u union select m from sh union select m from cn union select m from pd),
       j as (select mm.m, u.reports_use, sh.sheets, sh.sheet_count, cn.runs_counted, pd.runs_paid, pd.paid_runs from mm left join u using (m) left join sh using (m) left join cn using (m) left join pd using (m))
  select (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'reports_use', reports_use, 'sheets_02_2', sheets, 'sheet_count', coalesce(sheet_count, 0), 'runs_counted', runs_counted, 'runs_paid', runs_paid, 'paid_runs', coalesce(paid_runs, 0),
            'difference_runs_minus_reports', case when runs_counted is not null and reports_use is not null then runs_counted - reports_use end,
            'basis', case when runs_counted is null and sheets is not null then 'sheets_only' when runs_counted is not null and (acc or src = 'app_first') then 'runs_first' when runs_counted is not null then 'sheets_while_runs_exist' else 'none' end,
            'mismatch', runs_counted is not null and reports_use is not null and abs(runs_counted - reports_use) > 0.005) order by m), '[]'::jsonb) from j),
         (select jsonb_build_object('reports_use', sum(reports_use), 'sheets_02_2', sum(sheets), 'runs_counted', sum(runs_counted), 'runs_paid', sum(runs_paid), 'months_with_a_mismatch', count(*) filter (where runs_counted is not null and reports_use is not null and abs(runs_counted - reports_use) > 0.005)) from j)
    into rows, sm;
  return jsonb_build_object('from', p_from, 'to', p_to, 'settings', jsonb_build_object('report_salary_source', src, 'payroll_accrual_on', acc),
    'notes', '["reports_t3_t4_l1_use_this_figure","nothing_here_changes_a_report","switch_in_profit_check"]'::jsonb, 'summary', sm, 'rows', rows);
end $$;

do $c2$ declare f record; begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname ~ '^_?c2_' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname !~ '^_' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $c2$;
notify pgrst, 'reload schema';
