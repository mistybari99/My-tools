-- RPT-C2 staff data set (neutral test_* data). Needs tests/sql/c2_fixture.sql first. T = today (Dhaka).
--   shift test_shift 09:00-17:00, break 30 -> 450 scheduled minutes
--   emp1 test_emp_1 (place 1), emp2 test_emp_2 (place 1, no attendance record at all), emp3 test_emp_3 (place 2)
--   emp1 days T-6 .. T-1:  d1 present shift worked 480 ot 30 approved | d2 late (20 min) shift worked 430 ot 15 waiting | d3 present NO shift worked 300 | d4 absent | d5 off | d6 half_day shift worked 240 single punch, manual
--   one paper 02-1 sheet in range; one paper 02-2 sheet this month (pay due 7000) and one PAID payroll run this month (8000)
\set ON_ERROR_STOP off
select tt.as(:'o');
set session_replication_role = replica;
insert into shifts (name_bn, name_en, location_id, start_time, end_time, break_min) values ('test_shift', 'test_shift', 1, '09:00', '17:00', 30);
select id as sh1 from shifts where name_en = 'test_shift' \gset
insert into employees (employee_no, full_name_bn, full_name_en, primary_location_id, joining_date, status) values
 ('TST-E1', 'test_emp_1', 'test_emp_1', 1, tt.today() - 400, 'active'), ('TST-E2', 'test_emp_2', 'test_emp_2', 1, tt.today() - 400, 'active'), ('TST-E3', 'test_emp_3', 'test_emp_3', 2, tt.today() - 400, 'active');
select id as emp1 from employees where employee_no = 'TST-E1' \gset
select id as emp2 from employees where employee_no = 'TST-E2' \gset
select id as emp3 from employees where employee_no = 'TST-E3' \gset
insert into attendance_days (employee_id, day, status, shift_id, location_id, worked_minutes, late_minutes, ot_minutes, ot_approved, punch_count, single_punch, source) values
 (:'emp1'::uuid, tt.today()-6, 'present',  :'sh1', 1, 480,  0, 30, true,  2, false, 'auto'),
 (:'emp1'::uuid, tt.today()-5, 'late',     :'sh1', 1, 430, 20, 15, false, 2, false, 'auto'),
 (:'emp1'::uuid, tt.today()-4, 'present',  null,   1, 300,  0,  0, false, 2, false, 'auto'),
 (:'emp1'::uuid, tt.today()-3, 'absent',   null,   1,   0,  0,  0, false, 0, false, 'auto'),
 (:'emp1'::uuid, tt.today()-2, 'off',      null,   1,   0,  0,  0, false, 0, false, 'auto'),
 (:'emp1'::uuid, tt.today()-1, 'half_day', :'sh1', 1, 240,  0,  0, false, 1, true,  'manual'),
 (:'emp3'::uuid, tt.today()-1, 'present',  null,   2, 400,  0,  0, false, 2, false, 'auto');
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff, submitted_at) values
 ('02-1', 1, 9301, tt.today()-1, 'submitted', '{}'::jsonb, :'p', 'test_sales1', now()),
 ('02-2', 1, 9302, tt.today(), 'submitted', jsonb_build_object('pay', jsonb_build_array(jsonb_build_object('due','7000','overtime','0','other','0'))), :'p', 'test_sales1', now());
insert into payroll_runs (month, location_id, status, created_by, approved_at, paid_at) values (date_trunc('month', tt.today())::date, 1, 'paid', :'o', now(), now());
select id as run1 from payroll_runs order by id desc limit 1 \gset
insert into payroll_lines (run_id, month, employee_id, location_id, net, advance_recovery, active) values (:'run1'::bigint, date_trunc('month', tt.today())::date, :'emp1'::uuid, 1, 8000, 0, true);
set session_replication_role = origin;
select tt.as(:'o');
