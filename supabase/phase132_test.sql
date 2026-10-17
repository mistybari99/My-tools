-- FRESH DB ONLY. Phase 132 tests (R2-C: shift schedule). Build: owner order phase8..99, then phase132 (a copy of the database, then this file):
--   psql -h /tmp -p 5600 -U postgres -d <db> -qAt -f supabase/phase132_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000013201'
\set u_s '00000000-0000-0000-0000-000000013202'
\set u_a '00000000-0000-0000-0000-000000013204'
\set u_b '00000000-0000-0000-0000-000000013205'
\set u_c '00000000-0000-0000-0000-000000013206'
\set u_d '00000000-0000-0000-0000-000000013207'
\set u_t '00000000-0000-0000-0000-000000013208'
\set u_x '00000000-0000-0000-0000-000000013209'
\set e1 'e1320000-0000-0000-0000-000000000001'
\set e2 'e1320000-0000-0000-0000-000000000002'
\set e3 'e1320000-0000-0000-0000-000000000003'
\set e4 'e1320000-0000-0000-0000-000000000004'
\set e5 'e1320000-0000-0000-0000-000000000005'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$
declare r text; begin execute p_sql into r; return r; end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
-- the entry of a jsonb array of days whose "day" equals p_day
create or replace function tt.dayrow(j jsonb, p_day date) returns jsonb language sql immutable as $$ select x from jsonb_array_elements(coalesce(case when jsonb_typeof(j) = 'object' then j -> 'days' else j end, '[]'::jsonb)) x where (x ->> 'day')::date = p_day limit 1 $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner132@s.app','{"full_name":"test_owner132"}'), (:'u_s','test_sched132@s.app','{"full_name":"test_sched132"}'), (:'u_a','test_emp1_132@s.app','{"full_name":"test_emp1_132"}'),
 (:'u_b','test_emp2_132@s.app','{"full_name":"test_emp2_132"}'), (:'u_c','test_emp3_132@s.app','{"full_name":"test_emp3_132"}'), (:'u_d','test_noemp132@s.app','{"full_name":"test_noemp132"}'),
 (:'u_t','test_attmgr132@s.app','{"full_name":"test_attmgr132"}'), (:'u_x','test_pending132@s.app','{"full_name":"test_pending132"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_s', :'u_a', :'u_b', :'u_c', :'u_d', :'u_t');
insert into user_roles values (:'u_o','owner'),(:'u_s','salesperson'),(:'u_a','salesperson'),(:'u_b','salesperson'),(:'u_c','salesperson'),(:'u_d','salesperson'),(:'u_t','salesperson') on conflict do nothing;
insert into user_locations values (:'u_s',1),(:'u_a',1),(:'u_b',1),(:'u_c',2),(:'u_d',1),(:'u_t',1) on conflict do nothing;
insert into employees (id, full_name_bn, full_name_en, primary_location_id, status, joining_date, profile_id) values
 (:'e1', 'test_emp1', 'test_emp1', 1, 'active', '2025-01-01', :'u_a'),
 (:'e2', 'test_emp2', 'test_emp2', 1, 'active', '2025-01-01', :'u_b'),
 (:'e3', 'test_emp3', 'test_emp3', 2, 'active', '2025-01-01', :'u_c'),
 (:'e4', 'test_emp4_nologin', 'test_emp4_nologin', 1, 'active', '2025-01-01', null),
 (:'e5', 'test_emp5_draft', 'test_emp5_draft', 1, 'draft', '2025-01-01', null);
insert into user_grants (user_id, grant_code, location_id) values (:'u_s','shift_manage',1), (:'u_t','attendance_manage',1);
select tt.today() as td \gset

\echo == T0 shape, safe defaults, nothing shared patched
select tt.chk('T0 phase132 present', to_regprocedure('public._r2c_present()') is not null);
select tt.chk('T0 shift_on OFF and shift_mates_on ON by default, bn + en labels', (select count(*) from rules where key in ('shift_on','shift_mates_on') and kind = 'switch' and coalesce(label_bn,'') <> '' and coalesce(label_en,'') <> '') = 2
  and not rule_on('shift_on') and rule_on('shift_mates_on'));
select tt.chk('T0 grant shift_manage defined and held by no role', exists (select 1 from grant_defs where grant_code = 'shift_manage') and not exists (select 1 from rule_grants where grant_code = 'shift_manage'));
select tt.chk('T0 roster table: RLS on, NO browser access at all', (select relrowsecurity from pg_class where relname = 'r2_roster_days')
  and not has_table_privilege('authenticated','public.r2_roster_days','select') and not has_table_privilege('authenticated','public.r2_roster_days','insert') and not has_table_privilege('anon','public.r2_roster_days','select'));
select tt.chk('T0 no existing attendance / shift function was patched or re-created', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname !~ 'r2' and p.prosrc ~ 'r2_roster|r2_shift|_r2_plan') = 0);
select tt.chk('T0 API for signed-in users only; helpers closed', has_function_privilege('authenticated','public.r2_shift_my(date,integer)','execute') and not has_function_privilege('anon','public.r2_shift_my(date,integer)','execute')
  and not has_function_privilege('authenticated','public._r2_plan(date,date,uuid,integer)','execute') and not has_function_privilege('authenticated','public._r2c_gate()','execute'));
select count(*) as sh0 from shifts \gset
select count(*) as esa0 from employee_shift_assignments \gset
select count(*) as hol0 from holidays \gset

\echo == T1 default OFF: nothing readable, nothing writable, existing tables untouched
select count(*) as audit0 from audit_log \gset
set role authenticated; select tt.as(:'u_o');
select tt.err('T1 OFF: the owner cannot write a roster cell (shift_off)', format($q$select r2_roster_set(%L, %L::date + 1, null, true, null)$q$, :'e1', :'td'), 'shift_off');
select tt.err('T1 OFF: the owner cannot save a template (shift_off)', $q$select r2_shift_template_save(null, '{"name_bn":"test x","start_time":"06:00","end_time":"14:00"}')$q$, 'shift_off');
select tt.err('T1 OFF: roster grid refused', $q$select r2_shift_roster(1)$q$, 'shift_off');
select tt.chk('T1 OFF: state off', (r2_shift_state() ->> 'on') = 'false' and (r2_shift_state() ->> 'can_manage') = 'false');
select tt.as(:'u_a');
select tt.chk('T1 OFF: my shifts answer on:false with no days', (r2_shift_my() ->> 'on') = 'false' and r2_shift_my() -> 'days' = '[]'::jsonb);
reset role;
select tt.chk('T1 OFF: nothing written anywhere (roster, templates, patterns, holidays, audit)', tt.q('select count(*) from r2_roster_days') = '0' and (select count(*) from shifts) = :sh0
  and (select count(*) from employee_shift_assignments) = :esa0 and (select count(*) from audit_log) = :audit0);

\echo == T2 ON: templates
set role authenticated; select tt.as(:'u_o'); select set_rule('shift_on', 'true'::jsonb) is null as on1 \gset
reset role;
select tt.chk('T2 shift_on is true', rule_on('shift_on'));
set role authenticated; select tt.as(:'u_a');
select tt.chk('T2 staff state: on, cannot manage', (r2_shift_state() ->> 'on') = 'true' and (r2_shift_state() ->> 'can_manage') = 'false' and (r2_shift_state() ->> 'linked') = 'true');
select tt.err('T2 staff cannot save a template', $q$select r2_shift_template_save(null, '{"name_bn":"test x","location_id":1,"start_time":"06:00","end_time":"14:00"}')$q$, 'not allowed');
select tt.as(:'u_s');
select tt.chk('T2 scheduler state: can manage place 1 only', (r2_shift_state() ->> 'can_manage') = 'true' and (r2_shift_state() -> 'locations') = '[1]'::jsonb);
select (r2_shift_template_save(null, '{"name_bn":"test morning","name_en":"test morning","location_id":1,"start_time":"06:00","end_time":"14:00"}') ->> 'id')::int as s_m \gset
select (r2_shift_template_save(null, '{"name_bn":"test evening","name_en":"test evening","location_id":1,"start_time":"14:00","end_time":"22:00"}') ->> 'id')::int as s_e \gset
select (r2_shift_template_save(null, '{"name_bn":"test night","location_id":1,"start_time":"22:00","end_time":"06:00"}') ->> 'id')::int as s_n \gset
select tt.chk('T2 a night template crosses midnight', (select crosses_midnight from shifts where id = :s_n) and not (select crosses_midnight from shifts where id = :s_m));
select tt.chk('T2 templates are plain rows of the existing shifts table, not default, active', (select count(*) from shifts where id in (:s_m, :s_e, :s_n) and active and not is_default and location_id = 1) = 3);
select tt.err('T2 scheduler cannot make a template for another place', $q$select r2_shift_template_save(null, '{"name_bn":"test x","location_id":2,"start_time":"06:00","end_time":"14:00"}')$q$, 'not allowed');
select tt.err('T2 scheduler cannot make an every-place template (owner only)', $q$select r2_shift_template_save(null, '{"name_bn":"test x","start_time":"06:00","end_time":"14:00"}')$q$, 'not allowed');
select tt.err('T2 bad time refused', $q$select r2_shift_template_save(null, '{"name_bn":"test x","location_id":1,"start_time":"25:99","end_time":"14:00"}')$q$, 'bad_time');
select tt.err('T2 name required', $q$select r2_shift_template_save(null, '{"location_id":1,"start_time":"06:00","end_time":"14:00"}')$q$, 'name_required');
select (r2_shift_template_save(:s_m, '{"end_time":"15:00"}') ->> 'id')::int as s_m2 \gset
select tt.chk('T2 edit a template (new end time)', :s_m2 = :s_m and (select end_time::text from shifts where id = :s_m) = '15:00:00');
select (r2_shift_template_save(null, '{"name_bn":"test spare","location_id":1,"start_time":"10:00","end_time":"12:00"}') ->> 'id')::int as s_x \gset
select (r2_shift_template_save(:s_x, '{"active":false}') ->> 'id')::int as s_x2 \gset
select tt.chk('T2 retire a template (active false, the row stays)', :s_x2 = :s_x and not (select active from shifts where id = :s_x));
select tt.as(:'u_o');
select tt.chk('T2 the owner may make an every-place template', (r2_shift_template_save(null, '{"name_bn":"test everywhere","start_time":"09:00","end_time":"17:00"}') ->> 'id') is not null);
reset role;

\echo == T3 roster cells
set role authenticated; select tt.as(:'u_s');
select tt.chk('T3 morning for emp1 tomorrow', (r2_roster_set(:'e1', :'td'::date + 1, :s_m, false) ->> 'id') is not null);
select tt.chk('T3 morning for emp2 tomorrow', (r2_roster_set(:'e2', :'td'::date + 1, :s_m, false) ->> 'id') is not null);
select tt.chk('T3 evening for emp4 (no login) tomorrow', (r2_roster_set(:'e4', :'td'::date + 1, :s_e, false) ->> 'id') is not null);
select tt.chk('T3 an off-day with a leave note for emp1', (r2_roster_set(:'e1', :'td'::date + 2, null, true, 'test family event') ->> 'id') is not null);
select tt.chk('T3 a swap note on a shift (emp2 takes emp4''s evening on day 3)', (r2_roster_set(:'e2', :'td'::date + 3, :s_e, false, 'test swap with emp4') ->> 'id') is not null);
select tt.chk('T3 setting the same cell again replaces it (one active row per person and day)', (r2_roster_set(:'e2', :'td'::date + 1, :s_e, false, 'test changed') ->> 'id') is not null
  and tt.q(format('select count(*) from r2_roster_days where employee_id = %L and day = %L and active', :'e2', :'td'::date + 1)) = '1');
select tt.chk('T3 and puts it back', (r2_roster_set(:'e2', :'td'::date + 1, :s_m, false, null) ->> 'id') is not null);
select tt.err('T3 a person of another place cannot be scheduled by the place-1 scheduler', format($q$select r2_roster_set(%L, %L::date + 1, %s, false)$q$, :'e3', :'td', :s_m), 'not allowed');
select tt.err('T3 a draft employee is not found', format($q$select r2_roster_set(%L, %L::date + 1, %s, false)$q$, :'e5', :'td', :s_m), 'not_found');
select tt.err('T3 shift AND off together refused', format($q$select r2_roster_set(%L, %L::date + 4, %s, true)$q$, :'e1', :'td', :s_m), 'bad_shift');
select tt.err('T3 neither a shift nor off refused', format($q$select r2_roster_set(%L, %L::date + 4, null, false)$q$, :'e1', :'td'), 'bad_shift');
select tt.err('T3 a retired template cannot be used', format($q$select r2_roster_set(%L, %L::date + 4, %s, false)$q$, :'e1', :'td', :s_x), 'bad_shift');
select tt.err('T3 a day too far in the past refused', format($q$select r2_roster_set(%L, %L::date - 30, %s, false)$q$, :'e1', :'td', :s_m), 'bad_date');
select tt.err('T3 a note over 200 characters refused', format($q$select r2_roster_set(%L, %L::date + 4, %s, false, repeat('x', 201))$q$, :'e1', :'td', :s_m), 'text_too_long');
select tt.as(:'u_a');
select tt.err('T3 staff cannot write a cell, not even their own', format($q$select r2_roster_set(%L, %L::date + 5, %s, false)$q$, :'e1', :'td', :s_m), 'not allowed');
select tt.err('T3 staff cannot write a cell (second check)', format($q$select r2_roster_set(%L, %L::date + 5, %s, false)$q$, :'e1', :'td', :s_m), 'not allowed');
select tt.as(:'u_t');
select tt.err('T3 the attendance_manage grant does not give shift_manage', format($q$select r2_roster_set(%L, %L::date + 5, %s, false)$q$, :'e1', :'td', :s_m), 'not allowed');
reset role;

\echo == T4 my upcoming shifts, and who else is on at my place
set role authenticated; select tt.as(:'u_a');
select r2_shift_my(:'td'::date, 14) as my1 \gset
select tt.chk('T4 emp1: linked, 2 days listed (tomorrow shift, day 2 off); empty days are not invented', (:'my1'::jsonb ->> 'linked') = 'true' and jsonb_array_length(:'my1'::jsonb -> 'days') = 2);
select tt.chk('T4 tomorrow: morning 06:00-15:00', tt.dayrow(:'my1'::jsonb, :'td'::date + 1) -> 'shift' ->> 'name_bn' = 'test morning' and tt.dayrow(:'my1'::jsonb, :'td'::date + 1) -> 'shift' ->> 'start' = '06:00'
  and tt.dayrow(:'my1'::jsonb, :'td'::date + 1) -> 'shift' ->> 'end' = '15:00' and tt.dayrow(:'my1'::jsonb, :'td'::date + 1) ->> 'source' = 'day');
select tt.chk('T4 day 2: an off-day with the note', (tt.dayrow(:'my1'::jsonb, :'td'::date + 2) ->> 'off') = 'true' and tt.dayrow(:'my1'::jsonb, :'td'::date + 2) ->> 'note' = 'test family event' and tt.dayrow(:'my1'::jsonb, :'td'::date + 2) -> 'shift' = 'null'::jsonb);
select tt.chk('T4 tomorrow, who else is on at place 1: emp2 (morning) and emp4 (evening); NOT emp3 (place 2), NOT the draft, NOT me', jsonb_array_length(tt.dayrow(:'my1'::jsonb, :'td'::date + 1) -> 'mates') = 2
  and (select string_agg(m ->> 'name_en', ',' order by m ->> 'name_en') from jsonb_array_elements(tt.dayrow(:'my1'::jsonb, :'td'::date + 1) -> 'mates') m) = 'test_emp2,test_emp4_nologin');
select tt.chk('T4 on an off-day nobody is listed as "on with me"', tt.dayrow(:'my1'::jsonb, :'td'::date + 2) -> 'mates' = '[]'::jsonb);
select tt.as(:'u_b');
select tt.chk('T4 emp2 sees tomorrow''s morning and, on day 3, the swap note', tt.dayrow(r2_shift_my(:'td'::date, 14), :'td'::date + 3) ->> 'note' = 'test swap with emp4' and tt.dayrow(r2_shift_my(:'td'::date, 14), :'td'::date + 3) -> 'shift' ->> 'name_bn' = 'test evening');
select tt.as(:'u_c');
select tt.chk('T4 emp3 (place 2) sees no shifts of place 1 at all', jsonb_array_length(r2_shift_my(:'td'::date, 14) -> 'days') = 0);
select tt.as(:'u_d');
select tt.chk('T4 a login with no employee record: linked false, no days', (r2_shift_my() ->> 'linked') = 'false' and r2_shift_my() -> 'days' = '[]'::jsonb);
select tt.as(:'u_x');
select tt.err('T4 a pending login is refused', $q$select r2_shift_my()$q$, 'not allowed');
-- the mates setting
select tt.as(:'u_o'); select set_rule('shift_mates_on', 'false'::jsonb) is null as m1 \gset
select tt.as(:'u_a');
select tt.chk('T4 shift_mates_on OFF: my own shifts still show, nobody else is named', tt.dayrow(r2_shift_my(:'td'::date, 14), :'td'::date + 1) -> 'shift' ->> 'name_bn' = 'test morning' and tt.dayrow(r2_shift_my(:'td'::date, 14), :'td'::date + 1) -> 'mates' = '[]'::jsonb);
select tt.as(:'u_o'); select set_rule('shift_mates_on', 'true'::jsonb) is null as m2 \gset
reset role;

\echo == T5 the weekly pattern, holidays and leave are read, not copied
-- emp2 has a pattern: the evening template every day from 10 days ago; the weekly off rule (fri) makes Fridays off
insert into employee_shift_assignments (employee_id, shift_id, weekday_mask, from_date, created_by) values (:'e2', :s_e, 127, :'td'::date - 10, :'u_o');
select (:'td'::date + ((5 - extract(dow from :'td'::date)::int + 7) % 7) + 7)::date as fri \gset
select (:'fri'::date + 1) as sat \gset
insert into holidays (day, location_id, name_bn, name_en) values (:'sat'::date, null, 'test holiday', 'test holiday');
insert into leave_requests (employee_id, leave_type, from_date, to_date, days, status, reason) values (:'e1', 'casual', :'td'::date + 2, :'td'::date + 2, 1, 'approved', 'test leave');
set role authenticated; select tt.as(:'u_b');
select r2_shift_my(:'td'::date, 21) as my2 \gset
select tt.chk('T5 a day with a roster row beats the pattern (tomorrow stays morning, source day)', tt.dayrow(:'my2'::jsonb, :'td'::date + 1) -> 'shift' ->> 'name_bn' = 'test morning' and tt.dayrow(:'my2'::jsonb, :'td'::date + 1) ->> 'source' = 'day');
select tt.chk('T5 on the Friday the pattern gives an off-day', (tt.dayrow(:'my2'::jsonb, :'fri'::date) ->> 'off') = 'true' and tt.dayrow(:'my2'::jsonb, :'fri'::date) ->> 'source' = 'pattern');
select tt.chk('T5 on the Saturday the pattern gives the evening shift, and the holiday is named', tt.dayrow(:'my2'::jsonb, :'sat'::date) -> 'shift' ->> 'name_bn' = 'test evening' and tt.dayrow(:'my2'::jsonb, :'sat'::date) ->> 'holiday_en' = 'test holiday');
select tt.chk('T5 every one of the 21 days is listed for a person with a daily pattern', jsonb_array_length(:'my2'::jsonb -> 'days') = 21);
select tt.as(:'u_a');
select tt.chk('T5 approved leave is flagged on emp1''s day 2', (tt.dayrow(r2_shift_my(:'td'::date, 14), :'td'::date + 2) ->> 'leave') = 'true' and (tt.dayrow(r2_shift_my(:'td'::date, 14), :'td'::date + 1) ->> 'leave') = 'false');
reset role;
select tt.chk('T5 the pattern table and holidays were only read (counts as inserted, no more)', (select count(*) from employee_shift_assignments) = :esa0 + 1 and (select count(*) from holidays) = :hol0 + 1);

\echo == T6 the roster grid
set role authenticated; select tt.as(:'u_s');
select r2_shift_roster(1, :'td'::date, 7) as g1 \gset
select tt.chk('T6 grid of place 1: emp1, emp2, emp4 (not emp3 of place 2, not the draft)', jsonb_array_length(:'g1'::jsonb -> 'employees') = 3);
select tt.chk('T6 grid templates: place-1 templates and every-place ones, not the retired one', (select count(*) from jsonb_array_elements(:'g1'::jsonb -> 'templates') t where t ->> 'name_bn' in ('test morning','test evening','test night','test everywhere')) = 4
  and not exists (select 1 from jsonb_array_elements(:'g1'::jsonb -> 'templates') t where t ->> 'name_bn' = 'test spare'));
select tt.chk('T6 emp1 row has its two cells', (select jsonb_array_length(e -> 'days') from jsonb_array_elements(:'g1'::jsonb -> 'employees') e where e ->> 'name_en' = 'test_emp1') = 2);
select tt.err('T6 the place-1 scheduler cannot open place 2', $q$select r2_shift_roster(2)$q$, 'not allowed');
select tt.as(:'u_a');
select tt.err('T6 staff cannot open the grid', $q$select r2_shift_roster(1)$q$, 'not allowed');
select tt.as(:'u_o');
select tt.chk('T6 the owner opens any place', jsonb_array_length(r2_shift_roster(2) -> 'employees') = 1);
reset role;

\echo == T7 a whole week, copy a week, clear a cell
set role authenticated; select tt.as(:'u_s');
select r2_roster_week(:'e1', :'td'::date + 7, jsonb_build_array(jsonb_build_object('shift_id', :s_m), jsonb_build_object('shift_id', :s_m, 'note', 'test busy'), null, jsonb_build_object('off', true), jsonb_build_object('shift_id', :s_e))) as wk \gset
select tt.chk('T7 a week for emp1: 4 cells set, 1 cleared', (:'wk'::jsonb ->> 'set') = '4' and (:'wk'::jsonb ->> 'cleared') = '1');
select tt.err('T7 more than 7 days refused', format($q$select r2_roster_week(%L, %L::date + 7, '[1,2,3,4,5,6,7,8]'::jsonb)$q$, :'e1', :'td'), 'bad_date');
select r2_roster_copy_week(1, :'td'::date + 7, :'td'::date + 14) as cp \gset
select tt.chk('T7 copy the week: 4 cells copied to the next week', (:'cp'::jsonb ->> 'copied') = '4' and (:'cp'::jsonb ->> 'skipped') = '0');
select tt.chk('T7 copy again: nothing overwritten, 4 skipped', (r2_roster_copy_week(1, :'td'::date + 7, :'td'::date + 14) ->> 'copied') = '0' and (r2_roster_copy_week(1, :'td'::date + 7, :'td'::date + 14) ->> 'skipped') = '4');
select tt.err('T7 copy into the same week refused', format($q$select r2_roster_copy_week(1, %L::date + 7, %L::date + 7)$q$, :'td', :'td'), 'bad_date');
select tt.err('T7 copy for a place the scheduler does not hold refused', format($q$select r2_roster_copy_week(2, %L::date + 7, %L::date + 14)$q$, :'td', :'td'), 'not allowed');
select tt.as(:'u_a');
select tt.err('T7 staff cannot copy', format($q$select r2_roster_copy_week(1, %L::date + 7, %L::date + 21)$q$, :'td', :'td'), 'not allowed');
select tt.chk('T7 emp1 sees the copied week too', tt.dayrow(r2_shift_my(:'td'::date + 14, 7), :'td'::date + 15) ->> 'note' = 'test busy');
select tt.as(:'u_s');
select tt.chk('T7 clear a cell: it goes back to "nothing planned"', (r2_roster_clear(:'e1', :'td'::date + 1) ->> 'cleared') = 'true' and (r2_roster_clear(:'e1', :'td'::date + 1) ->> 'cleared') = 'false');
select tt.as(:'u_a');
select tt.chk('T7 emp1 no longer has tomorrow', tt.dayrow(r2_shift_my(:'td'::date, 5), :'td'::date + 1) is null);
reset role;
select tt.chk('T7 the cleared row stays (active false) and the audit log has the change', (select count(*) from r2_roster_days where employee_id = :'e1' and day = :'td'::date + 1 and not active) = 1
  and (select count(*) from audit_log where table_name = 'r2_roster_days' and action = 'update' and detail -> 'new' ->> 'active' = 'false') >= 1);
select tt.err('T7 nothing is hard-deleted', format('delete from r2_roster_days where employee_id = %L', :'e1'), 'nothing is deleted');

\echo == T8 soft link to attendance: roster versus what happened
-- yesterday (td-1) and the day before (td-2) planned for emp1, emp2, emp4; attendance filled for some
set role authenticated; select tt.as(:'u_s');
select r2_roster_set(:'e1', :'td'::date - 2, :s_m, false) is not null as r1 \gset
select r2_roster_set(:'e2', :'td'::date - 2, :s_m, false) is not null as r2 \gset
select r2_roster_set(:'e4', :'td'::date - 2, :s_m, false) is not null as r3 \gset
select r2_roster_set(:'e1', :'td'::date - 1, null, true) is not null as r4 \gset
select r2_roster_set(:'e2', :'td'::date - 1, null, true) is not null as r5 \gset
reset role;
insert into attendance_days (employee_id, day, status, day_kind, location_id, source, late_minutes) values
 (:'e1', :'td'::date - 2, 'late', 'normal', 1, 'auto', 12), (:'e2', :'td'::date - 2, 'absent', 'normal', 1, 'auto', 0), (:'e1', :'td'::date - 1, 'present', 'normal', 1, 'auto', 0);
-- (emp4 has no attendance row on td-2; emp2 is rostered off on td-1 with no row)
set role authenticated; select tt.as(:'u_s');
select r2_shift_report(1, :'td'::date - 2, :'td'::date - 1) as rp \gset
select tt.chk('T8 the report knows attendance exists', (:'rp'::jsonb ->> 'attendance') = 'true');
select tt.chk('T8 emp1 on td-2: planned and late (12 minutes)', (select r ->> 'result' = 'late' and (r ->> 'late_minutes')::int = 12 from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'employee_id' = :'e1' and (r ->> 'day')::date = :'td'::date - 2));
select tt.chk('T8 emp2 on td-2: planned, attendance says absent', (select r ->> 'result' = 'absent' from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'employee_id' = :'e2' and (r ->> 'day')::date = :'td'::date - 2));
select tt.chk('T8 emp4 on td-2: planned, no attendance record at all', (select r ->> 'result' = 'no_record' from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'employee_id' = :'e4' and (r ->> 'day')::date = :'td'::date - 2));
select tt.chk('T8 emp1 on td-1: rostered OFF but attendance says present = worked_off', (select r ->> 'result' = 'worked_off' from jsonb_array_elements(:'rp'::jsonb -> 'rows') r where r ->> 'employee_id' = :'e1' and (r ->> 'day')::date = :'td'::date - 1));
select tt.chk('T8 totals count each kind: late 1, absent 1, no_record 1 (emp4), worked_off 1, off 1 (emp2 on td-1)', (:'rp'::jsonb -> 'totals' ->> 'late') = '1' and (:'rp'::jsonb -> 'totals' ->> 'absent') = '1'
  and (:'rp'::jsonb -> 'totals' ->> 'no_record') = '1' and (:'rp'::jsonb -> 'totals' ->> 'worked_off') = '1' and (:'rp'::jsonb -> 'totals' ->> 'off') = '1');
select tt.as(:'u_t');
select tt.chk('T8 an attendance manager of the place may read the report', (r2_shift_report(1, :'td'::date - 2, :'td'::date - 1) ->> 'attendance') = 'true');
select tt.as(:'u_a');
select tt.err('T8 staff cannot read the report', format('select r2_shift_report(1, %L::date - 2, %L::date - 1)', :'td', :'td'), 'not allowed');
reset role;
-- no hard coupling: without the attendance table the report answers, it does not fail
alter table attendance_days rename to attendance_days_hidden;
set role authenticated; select tt.as(:'u_s');
select tt.chk('T8 attendance table missing: the report says attendance:false instead of failing, and my shifts still work', (r2_shift_report(1, :'td'::date - 2, :'td'::date - 1) ->> 'attendance') = 'false'
  and (r2_shift_my(:'td'::date, 3) ->> 'on') = 'true');
reset role;
alter table attendance_days_hidden rename to attendance_days;

\echo == T9 existing attendance / shift behaviour is untouched
select tt.chk('T9 attendance helpers still return what they did (weekly off Friday, default shift for an unassigned person)', public._att_is_off(:'e1', :'fri'::date) and (select name_bn from public._att_shift_for(:'e1', 1, :'td'::date)) is not null);
select tt.chk('T9 shift_save still works for an attendance manager path (not routed through the new code)', position('r2_' in pg_get_functiondef('public.shift_save(integer,jsonb)'::regprocedure)) = 0 and position('r2_' in pg_get_functiondef('public.shift_assign(uuid,integer,date,date,integer,integer,uuid)'::regprocedure)) = 0);

\echo == T10 switch OFF again
set role authenticated; select tt.as(:'u_o'); select set_rule('shift_on', 'false'::jsonb) is null as off1 \gset
select tt.as(:'u_a');
select tt.chk('T10 OFF: staff see nothing again', (r2_shift_my() ->> 'on') = 'false' and r2_shift_my() -> 'days' = '[]'::jsonb);
select tt.as(:'u_s');
select tt.err('T10 OFF: the scheduler is refused', format($q$select r2_roster_set(%L, %L::date + 3, %s, false)$q$, :'e1', :'td', :s_m), 'shift_off');
reset role;

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
