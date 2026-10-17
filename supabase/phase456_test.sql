-- Phase 456 tests (RPT-C2 R6 part 2: cashier-wise cash variance #150, sales per labour hour #148). Neutral test_* data only.  bash tests/sql/c2_run.sh phase456
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_staff_fixture.sql

select tt.as(:'p');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'ia')::jsonb,0,'[{"mode":"cash","amount":200}]'::jsonb,null,null,'retail',null,false)->>'id' as sl1 \gset
select tt.as(:'o');
set session_replication_role = replica;
insert into entries (form_code, location_id, serial, entry_date, status, data, flags, created_by, created_staff, submitted_at) values
 ('14-1', 1, 9401, tt.today()-1, 'submitted', '{"cashier":"test_staff_a","shift":"s1"}'::jsonb, '[{"code":"cash_short_over","amount":-20}]'::jsonb, :'p', 'test_sales1', now()),
 ('14-1', 1, 9402, tt.today()-2, 'submitted', '{"cashier":"test_staff_a","shift":"s1"}'::jsonb, '[{"code":"cash_short_over","amount":5}]'::jsonb, :'p', 'test_sales1', now()),
 ('14-1', 1, 9403, tt.today()-3, 'submitted', '{"cashier":"test_staff_b","shift":"s2"}'::jsonb, '[{"code":"cash_short_over","amount":-10}]'::jsonb, :'p', 'test_sales1', now()),
 ('14-1', 1, 9404, tt.today()-4, 'submitted', '{"shift":"full"}'::jsonb, '[{"code":"cash_short_over","amount":-30}]'::jsonb, :'p', 'test_sales1', now()),
 ('14-1', 1, 9405, tt.today()-5, 'submitted', '{"cashier":"test_staff_b","shift":"s2"}'::jsonb, '[]'::jsonb, :'p', 'test_sales1', now());
select id as e9401 from entries where form_code='14-1' and serial=9401 \gset
insert into shortage_cash_cases (entry_id, form_code, location_id, case_date, amount, status) values (:'e9401'::uuid, '14-1', 1, tt.today()-1, -20, 'approved');
insert into attendance_days (employee_id, day, status, location_id, worked_minutes, punch_count, source) values (:'emp2'::uuid, tt.today()-2, 'present', 1, 480, 0, 'manual');
set session_replication_role = origin;

\echo == T0 shape
select tt.chk('T0 functions open, anon none', has_function_privilege('authenticated','public.c2_cashier_variance(date,date,int)','execute') and has_function_privilege('authenticated','public.c2_sales_per_labour_hour(date,date,int)','execute')
  and not has_function_privilege('anon','public.c2_cashier_variance(date,date,int)','execute'));

\echo == T1 cashier-wise variance (#150)
select c2_cashier_variance(tt.today()-6, tt.today()) as cv \gset
select tt.chk('T1 test_staff_a on s1: 2 sheets, short 20, over 5, net -15, worst 20; case approved counted', (select (r ->> 'sheets')::int from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_a')=2
  and (select (r ->> 'short_amount')::numeric from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_a')=20 and (select (r ->> 'over_amount')::numeric from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_a')=5
  and (select (r ->> 'net')::numeric from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_a')=-15 and (select (r ->> 'cases_approved')::int from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_a')=1
  and (select r ->> 'shift' from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_a')='s1');
select tt.chk('T1 test_staff_b on s2: 2 sheets (one exact match counts as 0), net -10', (select (r ->> 'sheets')::int from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_b')=2 and (select (r ->> 'net')::numeric from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'cashier'='test_staff_b')=-10);
select tt.chk('T1 the sheet with no cashier (-30) is a row apart ("cashier not written"), not given to anyone; listed with its writer', (select (r ->> 'net')::numeric from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where (r ->> 'cashier_written')='false')=-30
  and (:'cv'::jsonb #>> '{summary,sheets_without_cashier}')::int=1 and jsonb_array_length(:'cv'::jsonb -> 'uncredited_sheets_with_a_variance')=1 and (:'cv'::jsonb -> 'uncredited_sheets_with_a_variance' -> 0 ->> 'writer')='test_sales1');
select tt.chk('T1 totals equal the hub short/over figures: short 60, over 5, net -55', (:'cv'::jsonb #>> '{summary,short_amount}')::numeric=60 and (:'cv'::jsonb #>> '{summary,over_amount}')::numeric=5 and (:'cv'::jsonb #>> '{summary,net}')::numeric=-55);
select tt.as(:'k');
select tt.err('T1 storekeeper refused', $$select c2_cashier_variance(current_date-6, current_date)$$, 'not allowed');
select tt.as(:'x');
select tt.chk('T1 place 2 manager sees none of place 1', (c2_cashier_variance(tt.today()-6, tt.today()) #>> '{summary,sheets}')::int=0);

\echo == T2 sales per labour hour (#148)
select tt.as(:'o');
select c2_sales_per_labour_hour(tt.today()-6, tt.today()) as sp \gset
select tt.chk('T2 place 1: sales 200, 5 staff-days, 1930 minutes = 32.2 hours, punch coverage 4 of 5 = 80, sales per hour 6.21 (200 / 32.17)', (select (r ->> 'sales')::numeric from jsonb_array_elements(:'sp'::jsonb -> 'rows') r where r ->> 'loc'='1')=200
  and (select (r ->> 'staff_days')::int from jsonb_array_elements(:'sp'::jsonb -> 'rows') r where r ->> 'loc'='1')=5 and (select (r ->> 'labour_hours')::numeric from jsonb_array_elements(:'sp'::jsonb -> 'rows') r where r ->> 'loc'='1')=32.2
  and (select (r ->> 'punch_coverage_pct')::numeric from jsonb_array_elements(:'sp'::jsonb -> 'rows') r where r ->> 'loc'='1')=80.0 and (select (r ->> 'sales_per_hour')::numeric from jsonb_array_elements(:'sp'::jsonb -> 'rows') r where r ->> 'loc'='1')=6.22
  and (select r ->> 'status' from jsonb_array_elements(:'sp'::jsonb -> 'rows') r where r ->> 'loc'='1')='partial_punches');
select tt.chk('T2 place 2 has hours but no sales: sales per hour 0.00 is a real figure; place 1 coverage is always shown', (select (r ->> 'sales_per_hour')::numeric from jsonb_array_elements(:'sp'::jsonb -> 'rows') r where r ->> 'loc'='2')=0);
set session_replication_role = replica; update attendance_days set status = 'absent' where location_id = 1; set session_replication_role = origin;
select c2_sales_per_labour_hour(tt.today()-6, tt.today(), 1) as sp2 \gset
select tt.chk('T2 no present records at place 1: hours and sales per hour are null (never 0 or an estimate), status no_attendance_records', (select r -> 'sales_per_hour' from jsonb_array_elements(:'sp2'::jsonb -> 'rows') r where r ->> 'loc'='1')='null'::jsonb
  and (select r ->> 'status' from jsonb_array_elements(:'sp2'::jsonb -> 'rows') r where r ->> 'loc'='1')='no_attendance_records' and (select r -> 'labour_hours' from jsonb_array_elements(:'sp2'::jsonb -> 'rows') r where r ->> 'loc'='1')='null'::jsonb);
select tt.as(:'k');
select tt.err('T2 storekeeper refused', $$select c2_sales_per_labour_hour(current_date-6, current_date)$$, 'not allowed');
select tt.as(:'r');
select tt.chk('T2 view_reports holder reads it', c2_sales_per_labour_hour(tt.today()-6, tt.today()) -> 'rows' is not null);

\echo == T9 paste twice
\ir phase456.sql
select tt.chk('T9 pasted again without error', true);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
