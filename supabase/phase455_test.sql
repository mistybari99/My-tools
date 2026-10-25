-- Phase 455 tests (RPT-C2 R6 part 1: attendance period summary #142, overtime and late variance #147, salary basis notice). Neutral test_* data only.  bash tests/sql/c2_run.sh phase455
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_staff_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions open to browsers, helpers closed, anon none',
  has_function_privilege('authenticated','public.c2_att_period_summary(date,date,int,uuid)','execute') and has_function_privilege('authenticated','public.c2_att_person_days(uuid,date,date)','execute')
  and has_function_privilege('authenticated','public.c2_salary_basis(date,date,int)','execute') and not has_function_privilege('anon','public.c2_att_period_summary(date,date,int,uuid)','execute')
  and not has_function_privilege('authenticated','public._c2_emp_visible(uuid)','execute') and not has_function_privilege('authenticated','public._c2_shift_minutes(time,time,boolean,int)','execute'));
select tt.chk('T0 the shift is 450 minutes (09:00-17:00 less 30); a night shift crossing midnight counts across it', _c2_shift_minutes('09:00','17:00',false,30)=450 and _c2_shift_minutes('22:00','06:00',true,0)=480 and _c2_shift_minutes('22:00','06:00',false,60)=420);

\echo == T1 the period summary
select tt.as(:'o');
select c2_att_period_summary(tt.today()-6, tt.today()-1, 1) as sm \gset
select tt.chk('T1 place 1: 2 people (emp1, emp2); emp3 is at place 2 and not listed', (:'sm'::jsonb #>> '{summary,people}')::int=2 and not exists (select 1 from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp3'));
select tt.chk('T1 emp1 day counts: present 2, late 1, absent 1, half_day 1, off 1; 6 records, no calendar day missing',
  (select (r ->> 'present')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=2 and (select (r ->> 'late_status')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1
  and (select (r ->> 'absent')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1 and (select (r ->> 'half_day')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1
  and (select (r ->> 'off')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1 and (select (r ->> 'days_with_record')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=6
  and (select (r ->> 'days_without_record')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=0);
select tt.chk('T1 emp1 late 1 day / 20 minutes, worked 1450, overtime 45 (30 approved, 15 waiting), single-punch 1, manual 1',
  (select (r ->> 'late_days')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1 and (select (r ->> 'late_minutes')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=20
  and (select (r ->> 'worked_minutes')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1450 and (select (r ->> 'ot_minutes')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=45
  and (select (r ->> 'ot_approved_minutes')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=30 and (select (r ->> 'ot_waiting_minutes')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=15
  and (select (r ->> 'single_punch_days')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1 and (select (r ->> 'manual_days')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1);
select tt.chk('T1 variance (#147): 3 days have a shift (1350 scheduled), variance (480-450)+(430-450)+(240-450) = -200; the day with no shift is counted apart (1), not guessed',
  (select (r ->> 'scheduled_minutes')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1350 and (select (r ->> 'variance_minutes')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=-200
  and (select (r ->> 'days_with_shift')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=3 and (select (r ->> 'days_without_shift')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp1')=1);
select tt.chk('T1 emp2 has no record at all: 6 calendar days without a record, scheduled and variance null (not 0), flagged in the summary', (select (r ->> 'days_without_record')::int from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp2')=6
  and (select r -> 'variance_minutes' from jsonb_array_elements(:'sm'::jsonb -> 'rows') r where r ->> 'employee_id'=:'emp2')='null'::jsonb and (:'sm'::jsonb #>> '{summary,people_with_no_record_at_all}')::int=1);
select tt.chk('T1 the paper sheet 02-1 is NOT added but counted: 1 sheet, note says so', (:'sm'::jsonb ->> 'paper_02_1_sheets_in_range')::int=1 and (:'sm'::jsonb -> 'notes') ? 'paper_02_1_not_included');

\echo == T2 person days (drill-down)
select c2_att_person_days(:'emp1'::uuid, tt.today()-6, tt.today()-1) as pd \gset
select tt.chk('T2 6 day rows; the late day has variance -20; the day without a shift has scheduled null and variance null', jsonb_array_length(:'pd'::jsonb -> 'rows')=6
  and (select (r ->> 'variance_minutes')::int from jsonb_array_elements(:'pd'::jsonb -> 'rows') r where r ->> 'status'='late')=-20
  and (select r -> 'scheduled_minutes' from jsonb_array_elements(:'pd'::jsonb -> 'rows') r where r ->> 'day'=(tt.today()-4)::text)='null'::jsonb and (select r -> 'variance_minutes' from jsonb_array_elements(:'pd'::jsonb -> 'rows') r where r ->> 'day'=(tt.today()-4)::text)='null'::jsonb);

\echo == T3 who sees whom
select tt.as(:'x');
select tt.chk('T3 place 2 manager (employee_view at place 2) sees only the place 2 person, never place 1 people', (c2_att_period_summary(tt.today()-6, tt.today()-1) #>> '{summary,people}')::int=1
  and not exists (select 1 from jsonb_array_elements(c2_att_period_summary(tt.today()-6, tt.today()-1) -> 'rows') r where r ->> 'employee_id' in (:'emp1', :'emp2')));
select tt.err('T3 place 2 manager cannot open emp1 days', format($$select c2_att_person_days('%s', current_date-6, current_date)$$, :'emp1'), 'not allowed');
select tt.as(:'r');
select tt.chk('T3 a view_reports holder at place 1 sees emp1 and emp2 (staff report right), not emp3', (c2_att_period_summary(tt.today()-6, tt.today()-1) #>> '{summary,people}')::int=2);
select tt.as(:'o');
select tt.chk('T3 the owner sees all 3 people with no place filter', (c2_att_period_summary(tt.today()-6, tt.today()-1) #>> '{summary,people}')::int=3);
select tt.err('T3 bad range', $$select c2_att_period_summary(current_date, current_date-2)$$, 'bad_date');
insert into user_grants (user_id, grant_code, location_id) values (:'k', 'attendance_manage', 1) on conflict do nothing;
select tt.as(:'k');
select tt.chk('T3 a person with attendance_manage at place 1 (and no report right) sees place 1 people', (c2_att_period_summary(tt.today()-6, tt.today()-1) #>> '{summary,people}')::int=2);

\echo == T4 salary basis notice
select tt.as(:'o');
select c2_salary_basis(date_trunc('month', tt.today())::date, tt.today()) as sb \gset
select tt.chk('T4 legacy source: reports use the 02-2 sheet 7000; the counted payroll run is 8000; difference +1000; basis says the sheet is used while a run exists; mismatch flagged',
  (:'sb'::jsonb #>> '{summary,reports_use}')::numeric=7000 and (:'sb'::jsonb #>> '{summary,sheets_02_2}')::numeric=7000 and (:'sb'::jsonb #>> '{summary,runs_counted}')::numeric=8000 and (:'sb'::jsonb #>> '{summary,runs_paid}')::numeric=8000
  and (:'sb'::jsonb -> 'rows' -> 0 ->> 'basis')='sheets_while_runs_exist' and (:'sb'::jsonb -> 'rows' -> 0 ->> 'mismatch')='true' and (:'sb'::jsonb -> 'rows' -> 0 ->> 'difference_runs_minus_reports')::numeric=1000
  and (:'sb'::jsonb #>> '{settings,report_salary_source}')='legacy');
select set_rule('report_salary_source','"app_first"'::jsonb) is null as src1 \gset
select c2_salary_basis(date_trunc('month', tt.today())::date, tt.today()) as sb2 \gset
select tt.chk('T4 app_first: reports use the run 8000, no mismatch, basis runs_first', (:'sb2'::jsonb #>> '{summary,reports_use}')::numeric=8000 and (:'sb2'::jsonb -> 'rows' -> 0 ->> 'mismatch')='false' and (:'sb2'::jsonb -> 'rows' -> 0 ->> 'basis')='runs_first');
select set_rule('report_salary_source','"legacy"'::jsonb) is null as src2 \gset
select tt.chk('T4 nothing changed in the existing figure by asking: the staff-cost source is still legacy', coalesce(rule_txt('report_salary_source'), 'legacy')='legacy');
select tt.as(:'m');
select tt.err('T4 a manager without salary_view refused', $$select c2_salary_basis(date_trunc('month', current_date)::date, current_date)$$, 'not allowed');
select tt.as(:'r');
select tt.err('T4 a report-only user without salary_view refused', $$select c2_salary_basis(date_trunc('month', current_date)::date, current_date)$$, 'not allowed');

\echo == T9 paste twice
\ir phase455.sql
select tt.chk('T9 pasted again without error', true);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
