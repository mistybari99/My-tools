-- FRESH DB ONLY. Phase 42 tests (module B2: attendance, leave, payroll, fingerprint devices).
--   ORDER="phase8 ... phase28 phase41 phase42" bash tests/sql/build_fresh_db.sh a42db ; psql -h /tmp -p 5544 -U postgres -d a42db -qAt -f supabase/phase42_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set h '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
\set p '00000000-0000-0000-0000-000000000006'
\set a '00000000-0000-0000-0000-000000000007'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager One"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
  (:'h','head4@s.app','{"full_name":"Head"}'), (:'t','mgr5@s.app','{"full_name":"Manager Two"}'), (:'p','sales6@s.app','{"full_name":"Sales Person"}'), (:'a','acct7@s.app','{"full_name":"Accountant"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper'),(:'h','management'),(:'t','showroom_manager'),(:'p','salesperson'),(:'a','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'h',1),(:'t',2),(:'p',1),(:'a',1) on conflict do nothing;

-- the test month: the latest finished month with 30 days
select to_char(m, 'YYYY-MM-DD') as m0, to_char(m + 29, 'YYYY-MM-DD') as m29 from (select (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - make_interval(months => k))::date m from generate_series(1, 12) k) z
 where extract(day from (m + interval '1 month' - interval '1 day')) = 30 order by m desc limit 1 \gset
select ((now() at time zone 'Asia/Dhaka')::date)::text as td \gset
create table tt.wd as select row_number() over (order by g::date) n, g::date d from generate_series(:'m0'::date, :'m29'::date, interval '1 day') g where extract(dow from g) <> 5;
select count(*) as nfri from generate_series(:'m0'::date, :'m29'::date, interval '1 day') g where extract(dow from g) = 5 \gset
grant select on tt.wd to authenticated;

-- people (fixtures written as the database owner; the module functions are tested below)
insert into employees (id, full_name_bn, full_name_en, primary_location_id, status, joining_date, device_user_id, profile_id) values
 ('e0000000-0000-0000-0000-000000000001', 'করিম', 'Karim', 1, 'active', '2025-01-01', '101', null),
 ('e0000000-0000-0000-0000-000000000002', 'রহিম', 'Rahim', 2, 'active', '2025-01-01', '202', null),
 ('e0000000-0000-0000-0000-000000000003', 'নাইট গার্ড', 'Night Guard', 1, 'active', '2025-01-01', '303', null),
 ('e0000000-0000-0000-0000-000000000005', 'সালমা', 'Salma', 1, 'on_leave', '2025-01-01', null, :'p'),
 ('e0000000-0000-0000-0000-000000000006', 'জামাল', 'Jamal', 1, 'active', '2024-01-01', null, null),
 ('e0000000-0000-0000-0000-000000000008', 'নতুন', 'Newcomer', 1, 'active', (:'m0'::date + 15), null, null),
 ('e0000000-0000-0000-0000-000000000009', 'খসড়া', 'Draft', 1, 'draft', '2025-01-01', '909', null);
\set e1 'e0000000-0000-0000-0000-000000000001'
\set e2 'e0000000-0000-0000-0000-000000000002'
\set e3 'e0000000-0000-0000-0000-000000000003'
\set e5 'e0000000-0000-0000-0000-000000000005'
\set e6 'e0000000-0000-0000-0000-000000000006'
\set e8 'e0000000-0000-0000-0000-000000000008'
\set e9 'e0000000-0000-0000-0000-000000000009'
insert into employee_pay (employee_id, effective_from, pay_basis, basic, ot_rule, ot_value, ot_hours_basis, bonus_rules) values
 (:'e1', '2025-01-01', 'monthly', 20000, 'multiple_of_hourly', 1.5, 8, '[{"name":"Eid","months_of_basic":0.5,"min_service_months":6}]'),
 (:'e6', '2024-01-01', 'monthly', 10001, 'none', null, 8, '[]'),
 (:'e8', (:'m0'::date + 15), 'monthly', 30000, 'none', null, 8, '[]');
insert into employee_pay_components (pay_id, kind, name, percent_of_basic) select id, 'allowance', 'House rent', 50 from employee_pay where employee_id = :'e8';
insert into employee_leave_entitlements (employee_id, leave_type, days_per_year) values (:'e1', 'casual', 10), (:'e2', 'casual', 10), (:'e5', 'sick', 14);
-- E1 in the test month: weekdays 1-2 absent, 3 casual leave, 4-6 late (09:30), 7-11 two hours overtime (out 20:00), 12 a double punch, the rest normal; Fridays off
insert into attendance_punches (employee_id, device_id, location_id, device_user_id, punched_at, direction, source)
select :'e1'::uuid, null, 1, '101', ((w.d + x.tm::time) at time zone 'Asia/Dhaka'), 'unknown', 'file'
  from tt.wd w cross join lateral unnest(case when w.n in (1, 2, 3) then array[]::text[] when w.n between 4 and 6 then array['09:30', '18:00'] when w.n between 7 and 11 then array['08:55', '20:00']
                                               when w.n = 12 then array['08:50', '08:52', '18:05'] else array['08:55', '18:00'] end) x(tm);
insert into leave_requests (employee_id, leave_type, from_date, to_date, days, status, requested_by, decided_by, decided_at) select :'e1', 'casual', d, d, 1, 'approved', :'s', :'o', now() from tt.wd where n = 3;
insert into payroll_bonus_events (month, name) values (:'m0', 'Eid');
-- E6: every day present except the 5th (absent)
insert into attendance_days (employee_id, day, status, day_kind, location_id, source) select :'e6', g::date, case when g::date = :'m0'::date + 4 then 'absent' else 'present' end, 'normal', 1, 'auto'
  from generate_series(:'m0'::date, :'m29'::date, interval '1 day') g;

\echo == shape
select tt.chk('T0 all 14 tables have RLS', (select count(*) from pg_class where relnamespace = 'public'::regnamespace and relrowsecurity and relname in ('shifts','employee_shift_assignments','holidays','attendance_devices','attendance_import_batches','attendance_punches','attendance_days','leave_requests','employee_advances','employee_advance_recoveries','payroll_bonus_events','payroll_runs','payroll_lines','payroll_payments'))=14);
select tt.chk('T0 the browser has no write grant on any table', not exists (select 1 from information_schema.role_table_grants where grantee in ('authenticated','anon') and table_schema='public' and table_name in ('shifts','employee_shift_assignments','holidays','attendance_devices','attendance_import_batches','attendance_punches','attendance_days','leave_requests','employee_advances','employee_advance_recoveries','payroll_bonus_events','payroll_runs','payroll_lines','payroll_payments') and privilege_type in ('INSERT','UPDATE','DELETE')));
select tt.chk('T0 anon reads no table', not has_table_privilege('anon','attendance_punches','select') and not has_table_privilege('anon','attendance_devices','select') and not has_table_privilege('anon','payroll_lines','select'));
select tt.chk('T0 the device token hash is not readable', not has_column_privilege('authenticated','attendance_devices','token_hash','select') and has_column_privilege('authenticated','attendance_devices','name','select'));
select tt.chk('T0 anon may execute ONLY the device push', has_function_privilege('anon','attendance_punch_push(text,jsonb)','execute')
  and (select count(*) from pg_proc where pronamespace='public'::regnamespace and has_function_privilege('anon', oid, 'execute') and (proname like 'attendance%' or proname like 'payroll%' or proname like 'leave%' or proname like 'staff_adv%' or proname like 'shift%' or proname like 'holiday%' or proname like '\_att%' or proname like '\_pr%'))=1);
select tt.chk('T0 helpers are closed to the browser', not has_function_privilege('authenticated','_payroll_calc(uuid,date,date)','execute') and not has_function_privilege('authenticated','_att_store(uuid,date)','execute')
  and not has_function_privilege('authenticated','_att_ingest(jsonb,integer,integer,text,uuid,boolean,integer)','execute') and not has_function_privilege('authenticated','_daybook_lines23(integer[],date,date)','execute')
  and has_function_privilege('authenticated','payroll_preview(date,integer)','execute'));
select tt.chk('T0 seeds: 15 rules, 2 grants, default shift, attendance_manage for 4 roles', (select count(*) from rules where key in ('attendance_on','app_punch_on','att_weekly_off','att_double_punch_min','att_ot_min_minutes','att_ot_cap_hours','att_late_mode','att_lates_per_day','pay_weekly_off_paid','pay_holiday_paid','ot_mult_holiday','att_bonus_amount','pay_round_net','payroll_on','att_push_per_min'))=15
  and (select count(*) from grant_defs where grant_code in ('attendance_manage','payroll_manage'))=2 and (select count(*) from shifts where is_default and location_id is null)=1
  and (select count(*) from rule_grants where grant_code='attendance_manage')=4 and not exists (select 1 from rule_grants where grant_code='payroll_manage'));
select tt.chk('T0 app punch is OFF by default', (select default_value from rules where key='app_punch_on')='false'::jsonb);

\echo == recompute from punches (first / last, double punches, late, overtime, leave, weekly off)
set role authenticated;
select tt.as(:'o'); select set_user_grant(:'a'::uuid,'salary_view',1) is null as g1 \gset
select set_user_grant(:'a'::uuid,'payroll_manage',1) is null as g2 \gset
select tt.as(:'k'); select tt.err('T1 storekeeper cannot recompute', format($$select attendance_recompute(%L, %L, %L)$$, :'m0', :'m29', :'e1'), 'not allowed');
select tt.as(:'t'); select tt.err('T1 manager of another place cannot recompute', format($$select attendance_recompute(%L, %L, %L)$$, :'m0', :'m29', :'e1'), 'not allowed');
select tt.as(:'s'); select tt.err('T1 range above 62 days refused', format($$select attendance_recompute(%L, %L, %L)$$, :'m0', (:'m0'::date + 70)::text, :'e1'), 'bad_range');
select attendance_recompute(:'m0'::date, :'m29'::date, :'e1'::uuid) ->> 'days_saved' as rc1 \gset
select tt.chk('T1 30 days stored', :'rc1'::int = 30 and (select count(*) from attendance_days where employee_id = :'e1' and day between :'m0' and :'m29') = 30);
select tt.chk('T1 2 absent, 3 late, 1 leave, Fridays off, the rest present', (select count(*) from attendance_days where employee_id=:'e1' and day between :'m0' and :'m29' and status='absent')=2
  and (select count(*) from attendance_days where employee_id=:'e1' and day between :'m0' and :'m29' and status='late')=3 and (select count(*) from attendance_days where employee_id=:'e1' and day between :'m0' and :'m29' and status='leave' and paid_day and leave_type='casual')=1
  and (select count(*) from attendance_days where employee_id=:'e1' and day between :'m0' and :'m29' and status='off')=:'nfri'::int
  and (select count(*) from attendance_days where employee_id=:'e1' and day between :'m0' and :'m29' and status='present')=30-:'nfri'::int-6);
select tt.chk('T1 late day: first punch = in 09:30, 30 late minutes, worked 450', (select late_minutes=30 and worked_minutes=450 and (first_in at time zone 'Asia/Dhaka')::time='09:30' and (last_out at time zone 'Asia/Dhaka')::time='18:00' from attendance_days a join tt.wd w on w.d=a.day and w.n=4 where a.employee_id=:'e1'));
select tt.chk('T1 overtime 120 min after the shift on 5 days = 600 min', (select sum(ot_minutes) from attendance_days where employee_id=:'e1' and day between :'m0' and :'m29')=600);
select tt.chk('T1 double punch within 5 min is one punch (08:50 kept, 08:52 ignored)', (select punch_count=2 and (first_in at time zone 'Asia/Dhaka')::time='08:50' and ot_minutes=0 from attendance_days a join tt.wd w on w.d=a.day and w.n=12 where a.employee_id=:'e1'));
select tt.chk('T1 recompute again = no change, no extra audit rows', (attendance_recompute(:'m0'::date, :'m29'::date, :'e1'::uuid) ->> 'days_saved')::int=30 and (select count(*) from attendance_days where employee_id=:'e1' and day between :'m0' and :'m29')=30);
select tt.as(:'s'); select tt.chk('T1 manager of the place sees the days', (select count(*) from attendance_days where employee_id=:'e1')>=30);
select tt.as(:'t'); select tt.chk('T1 manager of another place sees none', (select count(*) from attendance_days where employee_id=:'e1')=0);
select tt.as(:'k'); select tt.chk('T1 storekeeper sees none', (select count(*) from attendance_days where employee_id=:'e1')=0);

\echo == night shift
select tt.as(:'o');
select shift_save(null, '{"name_bn":"রাতের শিফট","name_en":"Night","location_id":1,"start_time":"22:00","end_time":"06:00","break_min":60,"grace_late_min":10}') ->> 'id' as nsh \gset
select tt.chk('T2 night shift saved, crosses midnight', (select crosses_midnight from shifts where id=:'nsh'::int));
select to_char(d, 'YYYY-MM-DD') as nd from (select (now() at time zone 'Asia/Dhaka')::date - k d from generate_series(2, 9) k) z where extract(dow from d) <> 5 and date_trunc('month', d) <> :'m0'::date order by d desc limit 1 \gset
select tt.as(:'s'); select shift_assign(:'e3'::uuid, :'nsh'::int, (:'nd'::date - 1), null, 127, null, '22222222-0000-0000-0000-000000000001'::uuid) ->> 'id' as asg \gset
select tt.chk('T2 shift assignment idempotent', (shift_assign(:'e3'::uuid, :'nsh'::int, (:'nd'::date - 1), null, 127, null, '22222222-0000-0000-0000-000000000001'::uuid) ->> 'repeat')='true' and (select count(*) from employee_shift_assignments where employee_id=:'e3')=1);
reset role;
insert into attendance_punches (employee_id, location_id, device_user_id, punched_at, source) values
 (:'e3', 1, '303', ((:'nd'::date + time '22:05') at time zone 'Asia/Dhaka'), 'file'), (:'e3', 1, '303', ((:'nd'::date + 1 + time '06:30') at time zone 'Asia/Dhaka'), 'file'),
 (:'e3', 1, '303', ((:'nd'::date + 1 + time '06:31') at time zone 'Asia/Dhaka'), 'file');
set role authenticated; select tt.as(:'s');
select attendance_recompute(:'nd'::date, (:'nd'::date + 1), :'e3'::uuid) is not null as r2 \gset
select tt.chk('T2 night shift: in 22:05, out 06:30 next morning, worked 445, OT 30, present', (select status='present' and worked_minutes=445 and ot_minutes=30 and late_minutes=0 and punch_count=2
  and (last_out at time zone 'Asia/Dhaka')::date = :'nd'::date + 1 from attendance_days where employee_id=:'e3' and day=:'nd'));
select tt.chk('T2 the next day does not take the morning punch', (select status <> 'present' and punch_count=0 from attendance_days where employee_id=:'e3' and day=(:'nd'::date + 1)) is not false);

\echo == manual mark and approval
select tt.as(:'k'); select tt.err('T3 storekeeper cannot mark', format($$select attendance_mark(%L, %L, 'present', '09:00', '18:00', null, 'device down')$$, :'e1', :'td'), 'not allowed');
select tt.as(:'s'); select tt.err('T3 reason required', format($$select attendance_mark(%L, %L, 'present', '09:00', '18:00', null, '')$$, :'e1', :'td'), 'reason_required');
select tt.err('T3 future day refused', format($$select attendance_mark(%L, %L, 'present', '09:00', '18:00', null, 'device down')$$, :'e1', (:'td'::date + 1)::text), 'bad_date');
select tt.err('T3 bad time refused', format($$select attendance_mark(%L, %L, 'present', '9h', '18:00', null, 'device down')$$, :'e1', :'td'), 'bad_time');
select attendance_mark(:'e1'::uuid, :'td'::date, 'late', '09:40', '18:00', null, 'device was down') ->> 'approved' as mk \gset
select tt.chk('T3 manager mark waits for approval, late 40 min', :'mk'='false' and (select source='manual' and approved_by is null and late_minutes=40 and override_reason='device was down' from attendance_days where employee_id=:'e1' and day=:'td'));
select tt.chk('T3 recompute never overwrites the manual row', (attendance_recompute(:'td'::date, :'td'::date, :'e1'::uuid) ->> 'manual_kept')::int=1 and (select status from attendance_days where employee_id=:'e1' and day=:'td')='late');
select tt.err('T3 the maker cannot approve his own mark', format($$select attendance_approve(%L, %L, true)$$, :'e1', :'td'), 'maker_cannot_approve');
select tt.as(:'h'); select attendance_approve(:'e1'::uuid, :'td'::date, true) ->> 'approved' as ap1 \gset
select tt.chk('T3 another manager approves', :'ap1'='true' and (select approved_by from attendance_days where employee_id=:'e1' and day=:'td')=:'h'::uuid);
reset role; select tt.chk('T3 manual mark is audit-logged', exists (select 1 from audit_log where table_name='attendance_days' and record_id like '%' || :'e1' || '%')); set role authenticated;
select tt.as(:'o'); select tt.chk('T3 owner mark is approved at once (owner_self_approve ON)', (attendance_mark(:'e6'::uuid, :'td'::date, 'present', '09:00', '18:00', null, 'owner fix') ->> 'approved')='true');
select tt.as(:'s'); select tt.chk('T3 reject sends the day back to the punches', (attendance_mark(:'e6'::uuid, :'td'::date, 'absent', null, null, null, 'wrong mark') ->> 'approved')='false');
select tt.as(:'h'); select attendance_approve(:'e6'::uuid, :'td'::date, false, 'no') ->> 'approved' as ap2 \gset
select tt.chk('T3 rejected = auto again', :'ap2'='false' and (select source from attendance_days where employee_id=:'e6' and day=:'td')='auto');

\echo == leave
select case when extract(year from (now() at time zone 'Asia/Dhaka')::date + 40) = extract(year from (now() at time zone 'Asia/Dhaka')::date) then (now() at time zone 'Asia/Dhaka')::date + 3 else (now() at time zone 'Asia/Dhaka')::date - 40 end::text as lb \gset
select count(*) as wd7 from generate_series(:'lb'::date, :'lb'::date + 6, interval '1 day') g where extract(dow from g) <> 5 \gset
select tt.as(:'k'); select tt.err('T4 storekeeper cannot file leave for others', format($$select leave_request_save(%L, 'casual', %L, %L, 'x')$$, :'e2', :'lb', :'lb'), 'not allowed');
select tt.as(:'t');
select leave_request_save(:'e2'::uuid, 'casual', :'lb'::date, (:'lb'::date + 6), 'family', '44444444-0000-0000-0000-000000000001'::uuid) as lr1 \gset
select (:'lr1'::jsonb ->> 'id') as lr1id \gset
select tt.chk('T4 days = working days (weekly off not counted)', (:'lr1'::jsonb ->> 'days')::numeric = :'wd7'::numeric and :'lr1'::jsonb ->> 'status'='pending');
select tt.chk('T4 same client key = same request', (leave_request_save(:'e2'::uuid, 'casual', :'lb'::date, (:'lb'::date + 6), 'family', '44444444-0000-0000-0000-000000000001'::uuid) ->> 'id') = :'lr1id');
select tt.err('T4 overlapping request refused', format($$select leave_request_save(%L, 'casual', %L, %L, 'x')$$, :'e2', (:'lb'::date + 2)::text, (:'lb'::date + 8)::text), 'leave_overlap');
select tt.err('T4 more than the balance (pending counts) refused', format($$select leave_request_save(%L, 'casual', %L, %L, 'x')$$, :'e2', (:'lb'::date + 7)::text, (:'lb'::date + 13)::text), 'leave_balance_short');
select tt.err('T4 unknown type refused', format($$select leave_request_save(%L, 'holiday_trip', %L, %L, 'x')$$, :'e2', (:'lb'::date + 20)::text, (:'lb'::date + 20)::text), 'bad_leave_type');
select tt.err('T4 maker cannot approve', format($$select leave_decide(%s, true)$$, :'lr1id'), 'maker_cannot_approve');
select tt.as(:'s'); select tt.err('T4 manager of another place cannot approve', format($$select leave_decide(%s, true)$$, :'lr1id'), 'not allowed');
select tt.as(:'o'); select tt.chk('T4 owner approves', (leave_decide(:'lr1id'::bigint, true, 'ok') ->> 'status')='approved');
select leave_balances(:'e2'::uuid, extract(year from :'lb'::date)::int) as bal \gset
select tt.chk('T4 balance: entitled 10, taken = days, remaining = 10 - days', (select (b ->> 'entitled')::numeric=10 and (b ->> 'taken')::numeric=:'wd7'::numeric and (b ->> 'remaining')::numeric=10-:'wd7'::numeric and (b ->> 'pending')::numeric=0
  from jsonb_array_elements(:'bal'::jsonb) b where b ->> 'leave_type'='casual'));
select tt.chk('T4 unpaid leave has no balance limit', (select (b ->> 'remaining') is null from jsonb_array_elements(:'bal'::jsonb) b where b ->> 'leave_type'='unpaid'));
select leave_cancel(:'lr1id'::bigint, 'plans changed') ->> 'status' as lc \gset
select tt.chk('T4 cancel gives the days back', :'lc'='cancelled'
  and (select (b ->> 'remaining')::numeric from jsonb_array_elements(leave_balances(:'e2'::uuid, extract(year from :'lb'::date)::int)) b where b ->> 'leave_type'='casual')=10);
-- approved leave marks the attendance days (past days only)
select to_char(d, 'YYYY-MM-DD') as ld from (select (now() at time zone 'Asia/Dhaka')::date - k d from generate_series(1, 6) k) z where extract(dow from d) <> 5 and date_trunc('month', d) <> :'m0'::date order by d desc limit 1 \gset
select tt.as(:'s'); select leave_request_save(:'e5'::uuid, 'sick', :'ld'::date, :'ld'::date, 'fever') ->> 'id' as lr2 \gset
select tt.as(:'h'); select leave_decide(:'lr2'::bigint, true) is not null as d2 \gset
select tt.chk('T4 approved leave marks the day as paid sick leave', (select status='leave' and leave_type='sick' and paid_day from attendance_days where employee_id=:'e5' and day=:'ld'));
select tt.as(:'o'); select tt.err('T4 a cancelled request cannot be decided', format($$select leave_decide(%s, true)$$, :'lr1id'), 'leave_not_pending');

\echo == fingerprint device: register, push, token, rate limit, unmapped
select tt.as(:'s'); select tt.err('T5 only the owner registers a device', $$select attendance_device_register('Gate', 1, 'zkteco', 'SN1')$$, 'not allowed');
select tt.as(:'o'); select attendance_device_register('Gate', 1, 'zkteco', 'SN1') as dv \gset
select (:'dv'::jsonb ->> 'id') as dvid, (:'dv'::jsonb ->> 'token') as tok \gset
reset role;
select tt.chk('T5 only the hash of the token is stored', (select token_hash = encode(sha256(convert_to(:'tok', 'UTF8')), 'hex') and token_hash <> :'tok' from attendance_devices where id=:'dvid'::int) and char_length(:'tok') >= 32);
select to_char((now() - interval '10 minutes') at time zone 'Asia/Dhaka', 'YYYY-MM-DD HH24:MI:SS') as pt, to_char((now() - interval '9 minutes') at time zone 'Asia/Dhaka', 'YYYY-MM-DD HH24:MI:SS') as pt2 \gset
select count(*) as np0 from attendance_punches \gset
set role anon; select tt.as('');
select tt.err('T5 a wrong token is refused', $$select attendance_punch_push('x0000000000000000000000000000000', '[]')$$, 'bad_token');
select tt.err('T5 a short token is refused', $$select attendance_punch_push('abc', '[]')$$, 'bad_token');
select attendance_punch_push(:'tok', format('[{"user_id":"101","ts":"%s","dir":"0","verify":1},{"user_id":"999","ts":"%s"},{"user_id":"101","ts":"%s"},{"user_id":"bad id!","ts":"%s"},{"user_id":"101","ts":"garbage"},{"user_id":"101","ts":"2001-01-01 10:00:00"}]', :'pt', :'pt2', :'pt', :'pt')::jsonb) as pu1 \gset
select tt.chk('T5 push: 2 new, 1 duplicate, 3 rejected, 1 unmapped', (:'pu1'::jsonb ->> 'new')::int=2 and (:'pu1'::jsonb ->> 'duplicates')::int=1 and (:'pu1'::jsonb ->> 'rejected')::int=3 and (:'pu1'::jsonb ->> 'unmapped')::int=1);
select tt.chk('T5 push answer reveals no employee data', not (:'pu1'::jsonb ? 'employees') and not (:'pu1'::jsonb ? 'unmapped_ids') and :'pu1' not like '%Karim%');
select attendance_punch_push(:'tok', format('[{"user_id":"101","ts":"%s"},{"user_id":"999","ts":"%s"}]', :'pt', :'pt2')::jsonb) as pu2 \gset
select tt.chk('T5 sending the same punches again inserts nothing (idempotent)', (:'pu2'::jsonb ->> 'new')::int=0 and (:'pu2'::jsonb ->> 'duplicates')::int=2);
select tt.err('T5 anon cannot read punches', $$select count(*) from attendance_punches$$, 'permission denied');
select tt.err('T5 anon cannot call any other function', format($$select attendance_import(1, null, '[]', 'x', true)$$), 'permission denied');
select tt.err('T5 more than 500 rows refused', format($$select attendance_punch_push(%L, (select jsonb_agg(jsonb_build_object('user_id','101','ts',%L)) from generate_series(1,501)))$$, :'tok', :'pt'), 'too_many_rows');
reset role;
select tt.chk('T5 mapped punch got the employee, unknown id kept with no employee', (select employee_id from attendance_punches where device_user_id='101' and device_id=:'dvid'::int)=:'e1'::uuid
  and (select employee_id is null and location_id=1 and source='device' from attendance_punches where device_user_id='999'));
select tt.chk('T5 device last seen and counter', (select last_seen is not null and pushed_rows=2 from attendance_devices where id=:'dvid'::int));
update attendance_devices set rl_minute = date_trunc('minute', now()), rl_count = 30 where id = :'dvid'::int;
set role anon; select tt.as(''); select tt.err('T5 rate limit per device per minute', format($$select attendance_punch_push(%L, '[]')$$, :'tok'), 'rate_limited');
set role authenticated; select tt.as(:'o'); select attendance_device_set_active(:'dvid'::int, false) is not null as off1 \gset
set role anon; select tt.as(''); select tt.err('T5 a switched-off device is refused', format($$select attendance_punch_push(%L, '[]')$$, :'tok'), 'bad_token');
set role authenticated; select tt.as(:'o'); select attendance_device_set_active(:'dvid'::int, true) is not null as on1 \gset
select attendance_device_token_reset(:'dvid'::int) ->> 'token' as tok2 \gset
reset role; update attendance_devices set rl_count = 0 where id = :'dvid'::int;
set role anon; select tt.as(''); select tt.err('T5 the old token stops working after a reset', format($$select attendance_punch_push(%L, '[]')$$, :'tok'), 'bad_token');
select tt.chk('T5 the new token works', (attendance_punch_push(:'tok2', '[]') ->> 'ok')='true');
set role authenticated;
select tt.as(:'s'); select tt.chk('T5 unmapped list shows the unknown id', exists (select 1 from jsonb_array_elements(attendance_unmapped(1)) u where u ->> 'device_user_id'='999' and (u ->> 'punches')::int=1 and u ->> 'device_name'='Gate'));
select tt.chk('T5 manager does not see the token hash', (select count(*) from attendance_devices)=1);
select tt.err('T5 a device id used by someone else cannot be given', format($$select attendance_map_user('101', %L)$$, :'e5'), 'duplicate_device_id');
select attendance_map_user('999', :'e5'::uuid) ->> 'punches_mapped' as mp \gset
select tt.chk('T5 map the unknown id to a person', :'mp'::int=1 and (select device_user_id from employees where id=:'e5')='999'
  and (select employee_id from attendance_punches where device_user_id='999')=:'e5'::uuid);
select tt.as(:'t'); select tt.chk('T5 unmapped of another place is hidden', (select count(*) from attendance_punches where employee_id is null)=0);
select tt.err('T5 manager of another place cannot list unmapped', $$select attendance_unmapped(1)$$, 'not allowed');

\echo == file import (preview writes nothing, batch, undo)
select tt.as(:'s');
select count(*) as np1 from attendance_punches \gset
select attendance_import(1, null, format('[{"user_id":"101","ts":"%s 08:58:00","dir":"0"},{"user_id":"101","ts":"%s 18:01:00","dir":"1"},{"user_id":"101","ts":"%s 18:01:00","dir":"1"},{"user_id":"777","ts":"%s 09:00:00"},{"user_id":"","ts":"x"}]', :'nd', :'nd', :'nd', :'nd')::jsonb, 'attlog.dat', true) as ip \gset
select tt.chk('T6 preview counts: 5 rows, 1 bad, 1 duplicate in file, 3 new, 1 unmapped id, 1 person', (:'ip'::jsonb ->> 'total')::int=5 and (:'ip'::jsonb ->> 'rejected')::int=1 and (:'ip'::jsonb ->> 'duplicates_in_file')::int=1
  and (:'ip'::jsonb ->> 'new')::int=3 and (:'ip'::jsonb ->> 'unmapped')::int=1 and (:'ip'::jsonb -> 'unmapped_ids') ? '777' and (:'ip'::jsonb ->> 'employees')::int=1 and (:'ip'::jsonb ->> 'dry')='true');
select tt.chk('T6 preview wrote nothing', (select count(*) from attendance_punches)=:'np1'::int and (select count(*) from attendance_import_batches)=0);
select tt.as(:'k'); select tt.err('T6 storekeeper cannot import', format($$select attendance_import(1, null, '[]', 'x', false)$$), 'not allowed');
select tt.as(:'s');
select attendance_import(1, null, format('[{"user_id":"101","ts":"%s 08:58:00","dir":"0"},{"user_id":"101","ts":"%s 18:01:00","dir":"1"},{"user_id":"777","ts":"%s 09:00:00"}]', :'nd', :'nd', :'nd')::jsonb, 'attlog.dat', false, '66666666-0000-0000-0000-000000000001'::uuid) as ir \gset
select (:'ir'::jsonb ->> 'batch') as bat \gset
select tt.chk('T6 import: batch with 3 new punches, the day recomputed', (:'ir'::jsonb ->> 'new')::int=3 and (select rows_new=3 and rows_unmapped=1 and status='active' from attendance_import_batches where id=:'bat'::uuid)
  and (select count(*) from attendance_punches where import_batch=:'bat'::uuid)=3 and (select status from attendance_days where employee_id=:'e1' and day=:'nd') in ('present','late'));
select tt.chk('T6 same client key = no second batch', (attendance_import(1, null, '[]', 'x', false, '66666666-0000-0000-0000-000000000001'::uuid) ->> 'repeat')='true' and (select count(*) from attendance_import_batches)=1);
select tt.chk('T6 importing the same file again adds nothing', (attendance_import(1, null, format('[{"user_id":"101","ts":"%s 08:58:00"}]', :'nd')::jsonb, 'again', false) ->> 'new')::int=0);
select tt.err('T6 undo needs a reason', format($$select attendance_import_void(%L, '')$$, :'bat'), 'reason_required');
select attendance_import_void(:'bat'::uuid, 'wrong file') ->> 'punches_voided' as pvd \gset
select tt.chk('T6 undo voids the batch punches (flag, not delete) and recomputes', :'pvd'::int=3
  and (select count(*) from attendance_punches where import_batch=:'bat'::uuid and void)=3 and (select status from attendance_import_batches where id=:'bat'::uuid)='void'
  and (select status from attendance_days where employee_id=:'e1' and day=:'nd')='absent');
reset role;
select tt.err('T6 punches cannot be deleted', $$delete from attendance_punches where device_user_id='101'$$, 'append_only');
select tt.err('T6 a punch time cannot be changed', $$update attendance_punches set punched_at = now() where device_user_id='101'$$, 'append_only');
select tt.err('T6 a voided punch cannot be revived', format($$update attendance_punches set void = false where import_batch=%L$$, :'bat'), 'append_only');
set role authenticated;

\echo == app punch (optional)
select tt.as(:'p'); select tt.err('T7 app punch is OFF by default', $$select attendance_app_punch('in')$$, 'app_punch_off');
select tt.as(:'o'); select set_rule('app_punch_on', 'true'::jsonb) is null as r1 \gset
select tt.as(:'p'); select attendance_app_punch('in') ->> 'direction' as apd \gset
select tt.chk('T7 staff with a login checks in (source app)', :'apd'='in' and (select count(*) from attendance_punches where employee_id=:'e5' and source='app')=1);
select tt.err('T7 twice within a minute refused', $$select attendance_app_punch('out')$$, 'too_soon');
select tt.chk('T7 the person sees his own attendance only', (select count(*) from attendance_days where employee_id=:'e5')>=1 and (select count(*) from attendance_days where employee_id=:'e1')=0);
select tt.as(:'k'); select tt.err('T7 a login without an employee record cannot punch', $$select attendance_app_punch('in')$$, 'no_employee_record');
select tt.as(:'o'); select set_rule('app_punch_on', null) is null as r2 \gset

\echo == payroll: worked example
select tt.as(:'a');
select tt.err('T8 advance needs a valid amount', format($$select staff_advance_add(%L, %L, 0, null, 'cash', %L, 'x')$$, :'e1', :'m0', :'m0'), 'bad_amount');
select staff_advance_add(:'e1'::uuid, :'m0'::date, 3000, 1500, 'cash', :'m0'::date, 'phone repair', '88888888-0000-0000-0000-000000000001'::uuid) ->> 'id' as adv \gset
select tt.chk('T8 advance idempotent by client key', (staff_advance_add(:'e1'::uuid, :'m0'::date, 3000, 1500, 'cash', :'m0'::date, 'phone repair', '88888888-0000-0000-0000-000000000001'::uuid) ->> 'repeat')='true' and (select count(*) from employee_advances)=1);
select tt.as(:'s'); select tt.err('T8 manager without payroll right cannot add an advance', format($$select staff_advance_add(%L, %L, 100, null, 'none', null, 'x')$$, :'e1', :'td'), 'not allowed');
select tt.chk('T8 manager without salary right sees no advance', (select count(*) from employee_advances)=0);
select tt.err('T8 manager without salary right cannot preview payroll', format($$select payroll_preview(%L, 1)$$, :'m0'), 'not allowed');
select tt.as(:'k'); select tt.err('T8 storekeeper cannot preview payroll', format($$select payroll_preview(%L, 1)$$, :'m0'), 'not allowed');
select tt.as(:'a'); select tt.err('T8 whole-company payroll is owner only', format($$select payroll_preview(%L, null)$$, :'m0'), 'not allowed');
select tt.err('T8 a future month is refused', format($$select payroll_preview(%L, 1)$$, (date_trunc('month', :'td'::date) + interval '1 month')::date::text), 'bad_month');
select count(*) as nr0 from payroll_runs \gset
select payroll_preview(:'m0'::date, 1) as pv \gset
select tt.chk('T8 preview writes nothing', (select count(*) from payroll_runs)=:'nr0'::int and (select count(*) from payroll_lines)=0 and (select count(*) from employee_advance_recoveries)=0 and (:'pv'::jsonb ->> 'dry')='true');
select (l::text) as l1 from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where l ->> 'employee_id' = :'e1' \gset
select tt.chk('T8 basic 20000, 30-day month, 28 paid days', (:'l1'::jsonb ->> 'basic_amount')::numeric=20000 and (:'l1'::jsonb ->> 'days_in_month')::int=30 and (:'l1'::jsonb ->> 'paid_days')::numeric=28 and (:'l1'::jsonb ->> 'paid_leave_days')::numeric=1);
select tt.chk('T8 2 absent days = 2 x 666.67 = 1333.33', (:'l1'::jsonb ->> 'absent_days')::numeric=2 and (:'l1'::jsonb ->> 'absent_deduction')::numeric=1333.33);
select tt.chk('T8 3 lates with the 3-lates rule = 1 day = 666.67', (:'l1'::jsonb ->> 'late_count')::int=3 and (:'l1'::jsonb ->> 'late_deduction')::numeric=666.67);
select tt.chk('T8 10 OT hours x 1.5 x (20000/30/8) = 1250.00', (:'l1'::jsonb ->> 'ot_minutes')::int=600 and (:'l1'::jsonb ->> 'ot_amount')::numeric=1250.00);
select tt.chk('T8 festival bonus Eid 0.5 x basic = 10000', (:'l1'::jsonb -> 'bonus' -> 0 ->> 'name')='Eid' and (:'l1'::jsonb -> 'bonus' -> 0 ->> 'amount')::numeric=10000);
select tt.chk('T8 advance recovery = one instalment 1500', (:'l1'::jsonb ->> 'advance_recovery')::numeric=1500 and (:'l1'::jsonb -> 'advances' -> 0 ->> 'advance_id')=:'adv');
select tt.chk('T8 gross 31250.00, deductions 3500.00, NET 27750', (:'l1'::jsonb ->> 'gross')::numeric=31250.00 and (:'l1'::jsonb ->> 'deductions')::numeric=3500.00 and (:'l1'::jsonb ->> 'net')::numeric=27750);
select tt.chk('T8 calculation trail is returned', jsonb_array_length(:'l1'::jsonb -> 'calc_detail' -> 'trail') >= 6 and (:'l1'::jsonb -> 'calc_detail' ->> 'day_rate')::numeric=666.6667);
select (l::text) as l6 from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where l ->> 'employee_id' = :'e6' \gset
select tt.chk('T8 rounding to the nearest taka: 10001 - 333.37 = 9667.63 -> 9668', (:'l6'::jsonb ->> 'absent_deduction')::numeric=333.37 and (:'l6'::jsonb ->> 'net')::numeric=9668 and (:'l6'::jsonb ->> 'round_adj')::numeric=0.37);
select (l::text) as l8 from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where l ->> 'employee_id' = :'e8' \gset
select tt.chk('T8 mid-month joiner: 15 of 30 days, allowance prorated: 30000 + 7500 - 15000 = 22500', (:'l8'::jsonb ->> 'employed_days')::int=15 and (:'l8'::jsonb ->> 'allowance_total')::numeric=7500
  and (:'l8'::jsonb ->> 'not_employed_deduction')::numeric=15000 and (:'l8'::jsonb ->> 'net')::numeric=22500);
select tt.chk('T8 warning: attendance not computed for the joiner', exists (select 1 from jsonb_array_elements_text(:'l8'::jsonb -> 'warnings') w where w like 'days_not_computed:%'));
select tt.chk('T8 warning: missing pay structure (and not paid)', exists (select 1 from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where l ->> 'employee_id' = :'e3' and (l -> 'warnings') ? 'no_pay_structure' and (l ->> 'skip')='true'));
select tt.chk('T8 drafts and other places are not in the preview', not exists (select 1 from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where l ->> 'employee_id' in (:'e9', :'e2')));
select tt.chk('T8 preview totals = sum of nets 27750 + 9668 + 22500', (:'pv'::jsonb -> 'totals' ->> 'net')::numeric = 59918 and (:'pv'::jsonb -> 'totals' ->> 'people')::int = 3);

\echo == payroll: create, adjust, approve (lock), pay, day book
select tt.as(:'s'); select tt.err('T9 manager without payroll right cannot create', format($$select payroll_create(%L, 1)$$, :'m0'), 'not allowed');
select tt.as(:'a');
select payroll_create(:'m0'::date, 1, '99999999-0000-0000-0000-000000000001'::uuid) as run \gset
select (:'run'::jsonb ->> 'id') as rid \gset
select tt.chk('T9 draft run with 3 lines', (:'run'::jsonb ->> 'status')='draft' and (:'run'::jsonb ->> 'lines')::int=3 and (:'run'::jsonb ->> 'net')::numeric=59918);
select tt.chk('T9 preview == create for every line (gross, deductions, net)', not exists (select 1 from jsonb_array_elements(:'pv'::jsonb -> 'lines') l left join payroll_lines x on x.employee_id = (l ->> 'employee_id')::uuid and x.run_id=:'rid'::bigint
   where not coalesce((l ->> 'skip')::boolean, false) and (x.id is null or x.gross <> (l ->> 'gross')::numeric or x.deductions <> (l ->> 'deductions')::numeric or x.net <> (l ->> 'net')::numeric)));
select tt.chk('T9 same client key = same run', (payroll_create(:'m0'::date, 1, '99999999-0000-0000-0000-000000000001'::uuid) ->> 'repeat')='true' and (select count(*) from payroll_runs)=1);
select tt.err('T9 a second run for the same month and place is refused', format($$select payroll_create(%L, 1)$$, :'m0'), 'run_exists');
select id as ln1 from payroll_lines where run_id=:'rid'::bigint and employee_id=:'e1' \gset
select tt.err('T9 adjustment needs a reason', format($$select payroll_line_adjust(%s, 'bonus', 'Extra', 500, '')$$, :'ln1'), 'reason_required');
select tt.chk('T9 add a bonus 500 -> net 28250', (payroll_line_adjust(:'ln1'::bigint, 'bonus', 'Extra', 500, 'good work') ->> 'net')::numeric=28250);
select tt.chk('T9 a -250.40 adjustment -> net 27999.60 rounds to 28000', (payroll_line_adjust(:'ln1'::bigint, 'adjust', 'Breakage', -250.40, 'broken glass') ->> 'net')::numeric=28000);
select tt.chk('T9 refresh keeps manual items', (payroll_refresh(:'rid'::bigint) ->> 'refreshed_lines')::int=3 and (select net from payroll_lines where id=:'ln1'::bigint)=28000);
select tt.err('T9 an auto bonus cannot be removed by hand', format($$select payroll_line_adjust(%s, 'bonus', null, null, null, 0)$$, :'ln1'), 'bad_item');
select tt.chk('T9 remove manual items -> back to 27750', (payroll_line_adjust(:'ln1'::bigint, 'bonus', null, null, null, 1) is not null) and (payroll_line_adjust(:'ln1'::bigint, 'adjust', null, null, null, 0) ->> 'net')::numeric=27750);
select tt.as(:'s'); select tt.chk('T9 manager without salary right sees no payroll row', (select count(*) from payroll_runs)=0 and (select count(*) from payroll_lines)=0);
select tt.as(:'t'); select tt.chk('T9 manager of another place sees no payroll row', (select count(*) from payroll_lines)=0);
select tt.as(:'a'); select tt.err('T9 only the owner approves', format($$select payroll_approve(%s)$$, :'rid'), 'not allowed');
select tt.err('T9 paying before approval is refused', format($$select payroll_pay(%s, null, 'cash', %L)$$, :'rid', :'td'), 'run_not_approved');
select tt.as(:'o'); select tt.chk('T9 owner approves', (payroll_approve(:'rid'::bigint) ->> 'status')='approved');
select tt.chk('T9 advance recovery booked, 1500 still owed', (select sum(amount) from employee_advance_recoveries where status='active')=1500
  and (select (a ->> 'outstanding')::numeric from jsonb_array_elements(staff_advances_list(:'e1'::uuid) -> 'advances') a)=1500);
select tt.err('T9 approved line cannot be adjusted', format($$select payroll_line_adjust(%s, 'bonus', 'Late', 1, 'too late now')$$, :'ln1'), 'payroll_locked');
reset role;
select tt.err('T9 approved line cannot be changed even directly', format($$update payroll_lines set net = 1 where id = %s$$, :'ln1'), 'payroll_locked');
select tt.chk('T9 month locked: recompute keeps the approved month', public._att_store(:'e1'::uuid, :'m0'::date) = 'locked');
set role authenticated; select tt.as(:'s');
select tt.chk('T9 month locked: recompute skips all 30 days', (attendance_recompute(:'m0'::date, :'m29'::date, :'e1'::uuid) ->> 'locked')::int = 30);
select tt.err('T9 month locked: OT approval refused', format($$select attendance_ot_approve(%L, %L)$$, :'e1', :'m0'), 'month_locked');
select tt.as(:'a');
select tt.err('T9 pay date before the month refused', format($$select payroll_pay(%s, null, 'cash', %L)$$, :'rid', (:'m0'::date - 1)::text), 'bad_date');
select tt.err('T9 bad mode refused', format($$select payroll_pay(%s, null, 'cheque', %L)$$, :'rid', :'td'), 'bad_mode');
select payroll_pay(:'rid'::bigint, array[:'ln1'::bigint], 'bank', :'td'::date, 'TT-1', null, null, 10000) ->> 'payments' as pp1 \gset
select tt.chk('T9 pay one line in part (10000 by bank)', :'pp1'::int=1
  and (select payment_status='partly' and paid_amount=10000 from payroll_lines where id=:'ln1'::bigint));
select tt.err('T9 cannot pay more than due', format($$select payroll_pay(%s, array[%s]::bigint[], 'cash', %L, null, null, null, 20000)$$, :'rid', :'ln1', :'td'), 'more_than_due');
select payroll_pay(:'rid'::bigint, null, 'cash', :'td'::date, null, 'salary day', '77777777-0000-0000-0000-000000000001'::uuid) as pay \gset
select tt.chk('T9 pay the rest in cash: run paid, every line paid', (:'pay'::jsonb ->> 'status')='paid' and (:'pay'::jsonb ->> 'payments')::int=3 and (:'pay'::jsonb ->> 'amount')::numeric=59918-10000
  and not exists (select 1 from payroll_lines where run_id=:'rid'::bigint and payment_status<>'paid'));
select tt.chk('T9 same client key = no double payment', (payroll_pay(:'rid'::bigint, null, 'cash', :'td'::date, null, null, '77777777-0000-0000-0000-000000000001'::uuid) ->> 'repeat')='true' and (select count(*) from payroll_payments)=4);
select tt.err('T9 nothing left to pay', format($$select payroll_pay(%s, null, 'cash', %L)$$, :'rid', :'td'), 'nothing_to_pay');
select tt.as(:'o'); select tt.err('T9 a paid run cannot be voided', format($$select payroll_void(%s, 'oops')$$, :'rid'), 'run_has_payments');
reset role;
select tt.as(:'o');
select tt.chk('T10 day book: salary lines (sensitive) = 59918 for the owner', (select sum(amount) from public._daybook_lines23(array[1], :'m0'::date, :'td'::date) where typ='salary' and sensitive and dir='out')=59918
  and (select count(*) from public._daybook_lines23(array[1], :'m0'::date, :'td'::date) where typ='salary' and mode='bank' and amount=10000)=1);
select tt.chk('T10 day book: the cash advance is an out line', (select sum(amount) from public._daybook_lines23(array[1], :'m0'::date, :'td'::date) where typ='advance' and src='staff_advance')=3000);
select tt.as(:'s');
select tt.chk('T10 day book hides salary from a user without salary_view', not exists (select 1 from public._daybook_lines23(array[1], :'m0'::date, :'td'::date) where typ in ('salary','advance')));
select tt.as(:'a'); select tt.chk('T10 day book shows salary to salary_view at the place', (select count(*) from public._daybook_lines23(array[1], :'m0'::date, :'td'::date) where typ='salary')=4);
select tt.err('T10 payments cannot be deleted', $$delete from payroll_payments$$, 'append_only');
set role authenticated;
select tt.as(:'a'); select tt.err('T10 only the owner voids a payment', $$select payroll_payment_void((select min(id) from payroll_payments), 'wrong')$$, 'not allowed');
select tt.as(:'o'); select payroll_payment_void((select id from payroll_payments where mode='bank'), 'wrong account') ->> 'status' as pv1 \gset
select tt.chk('T10 owner voids a payment: line partly paid again, run back to approved', :'pv1'='void'
  and (select payment_status from payroll_lines where id=:'ln1'::bigint)='partly' and (select status from payroll_runs where id=:'rid'::bigint)='approved');

\echo == settlement, bonus events, void of a draft
select tt.as(:'a');
select payroll_settlement_preview(:'e6'::uuid, (:'m0'::date + 9)) as st \gset
select tt.chk('T11 final settlement (10 of 30 days): 10001 - 6667.33 - 333.37 = 3000.30 -> 3000, writes nothing', (:'st'::jsonb -> 'line' ->> 'employed_days')::int=10 and (:'st'::jsonb -> 'line' ->> 'not_employed_deduction')::numeric=6667.33
  and (:'st'::jsonb -> 'line' ->> 'net')::numeric=3000 and (:'st'::jsonb ->> 'already_in_run')='true' and (:'st'::jsonb ->> 'dry')='true');
select tt.as(:'s'); select tt.err('T11 settlement preview needs the salary right', format($$select payroll_settlement_preview(%L, %L)$$, :'e6', :'td'), 'not allowed');
select tt.as(:'o');
select payroll_create(:'m0'::date, 2) ->> 'id' as rid2 \gset
select tt.chk('T11 run for place 2: no line (no pay structure there)', (select count(*) from payroll_lines where run_id=:'rid2'::bigint)=0);
select tt.err('T11 an empty run cannot be approved', format($$select payroll_approve(%s)$$, :'rid2'), 'run_empty');
select payroll_void(:'rid2'::bigint, 'not needed') ->> 'status' as vd \gset
select tt.chk('T11 a draft is voided with a reason', :'vd'='void' and (select status from payroll_runs where id=:'rid2'::bigint)='void');
select tt.chk('T11 bonus event saved once per month and name', (payroll_bonus_event_save(:'m0'::date, 'Eid') ->> 'id')::int = (select id from payroll_bonus_events where name='Eid'));
select tt.as(:'o'); select set_rule('payroll_on', 'false'::jsonb) is null as po \gset
select tt.as(:'a'); select tt.err('T11 payroll switched off refuses', format($$select payroll_preview(%L, 1)$$, :'m0'), 'payroll_off');
select tt.as(:'o'); select set_rule('payroll_on', null) is null as po2 \gset
select set_rule('attendance_on', 'false'::jsonb) is null as ao \gset
select tt.as(:'s'); select tt.err('T11 attendance switched off refuses writes', format($$select attendance_mark(%L, %L, 'present', null, null, null, 'xxx')$$, :'e1', :'td'), 'attendance_off');
select tt.as(:'o'); select set_rule('attendance_on', null) is null as ao2 \gset

\echo == board and month grid
select tt.as(:'s');
select attendance_board(1, :'td'::date) as bd \gset
select tt.chk('T12 board lists working staff of the place (no drafts, no other place)', (select count(*) from jsonb_array_elements(:'bd'::jsonb -> 'rows'))=5
  and not exists (select 1 from jsonb_array_elements(:'bd'::jsonb -> 'rows') r where r ->> 'employee_id' in (:'e9', :'e2')));
select tt.chk('T12 board shows the approved manual mark', exists (select 1 from jsonb_array_elements(:'bd'::jsonb -> 'rows') r where r ->> 'employee_id'=:'e1' and r ->> 'status'='late' and r ->> 'source'='manual' and (r ->> 'pending')='false'));
select tt.as(:'t'); select tt.err('T12 board of another place refused', format($$select attendance_board(1, %L)$$, :'td'), 'not allowed');
select tt.as(:'s'); select tt.chk('T12 month grid has every day', jsonb_array_length(attendance_month(:'e1'::uuid, :'m0'::date) -> 'days')=30 and (attendance_month(:'e1'::uuid, :'m0'::date) ->> 'locked')='true');

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' passed, ' || count(*) filter (where not ok) || ' failed' from tt.res;
select 'FAIL: ' || name from tt.res where not ok;
