-- FRESH DB ONLY. Phase 41 tests (module B1: employees, pay, facilities, roles and deeds).
--   ORDER="phase8 ... phase28 phase41" bash tests/sql/build_fresh_db.sh a41db ; psql -h /tmp -p 5544 -U postgres -d a41db -qAt -f supabase/phase41_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set h '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
\set p '00000000-0000-0000-0000-000000000006'
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
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager One"}'), (:'k','store3@s.app','{"full_name":"Store"}'), (:'h','head4@s.app','{"full_name":"Head"}'), (:'t','mgr5@s.app','{"full_name":"Manager Two"}'), (:'p','sales6@s.app','{"full_name":"Sales Person"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper'),(:'h','management'),(:'t','showroom_manager'),(:'p','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'h',1),(:'t',2),(:'p',1) on conflict do nothing;
select ((now() at time zone 'Asia/Dhaka')::date)::text as td \gset
select ((now() at time zone 'Asia/Dhaka')::date - 60)::text as dm60, ((now() at time zone 'Asia/Dhaka')::date - 10)::text as dm10, ((now() at time zone 'Asia/Dhaka')::date - 30)::text as dm30,
       ((now() at time zone 'Asia/Dhaka')::date + 30)::text as dp30, ((now() at time zone 'Asia/Dhaka')::date + 10)::text as dp10, ((now() at time zone 'Asia/Dhaka')::date + 31)::text as dp31,
       ((now() at time zone 'Asia/Dhaka')::date - 100)::text as dm100, ((now() at time zone 'Asia/Dhaka')::date - 1)::text as dm1, ((now() at time zone 'Asia/Dhaka')::date - 5)::text as dm5 \gset

\echo == shape
select tt.chk('T0 tables have RLS', (select count(*) from pg_class where relname in ('employees','employee_locations','employee_status_log','employee_documents','employee_pay','employee_pay_components','employee_benefits','employee_leave_entitlements','staff_roles','leave_types','deed_templates','employee_deeds') and relrowsecurity)=12);
select tt.chk('T0 browser has no write grant on any table', not exists (select 1 from information_schema.role_table_grants where grantee='authenticated' and table_schema='public' and table_name in ('employees','employee_locations','employee_status_log','employee_documents','employee_pay','employee_pay_components','employee_benefits','employee_leave_entitlements','staff_roles','leave_types','deed_templates','employee_deeds') and privilege_type in ('INSERT','UPDATE','DELETE')));
select tt.chk('T0 pay account columns are not readable', not has_column_privilege('authenticated','employees','bank_account','select') and not has_column_privilege('authenticated','employees','mobile_wallet','select') and has_column_privilege('authenticated','employees','mobile','select'));
select tt.chk('T0 benefit value column is not readable', not has_column_privilege('authenticated','employee_benefits','value_per_month','select') and has_column_privilege('authenticated','employee_benefits','kind','select'));
select tt.chk('T0 anon has no execute', not has_function_privilege('anon','employee_save(uuid,uuid,jsonb,boolean)','execute') and not has_function_privilege('anon','employee_pay_current(uuid,date)','execute'));
select tt.chk('T0 helpers closed to the browser', not has_function_privilege('authenticated','_emp_pay_on(uuid,date)','execute') and not has_function_privilege('authenticated','_pay_calc(numeric,jsonb)','execute') and has_function_privilege('authenticated','employee_save(uuid,uuid,jsonb,boolean)','execute'));
select tt.chk('T0 seeds: 11 roles (6 major), 6 leave types, 4 grants, 3 rules', (select count(*) from staff_roles)=11 and (select count(*) from staff_roles where major)=6 and (select count(*) from leave_types)=6
  and (select count(*) from grant_defs where grant_code in ('employee_view','employee_manage','salary_manage','deed_manage'))=4 and (select count(*) from rules where key in ('employees_module_on','employee_mobile_unique','deed_expiry_warn_days'))=3);
select tt.chk('T0 default: employee_view only for management / showroom_manager / factory_incharge', (select count(*) from rule_grants where grant_code='employee_view')=3 and not exists (select 1 from rule_grants where grant_code in ('employee_manage','salary_manage','deed_manage','salary_view')));
select tt.chk('T0 designation and department lists seeded', (select count(*) from option_lists where list_code='emp_designation')=12 and (select count(*) from option_lists where list_code='emp_department')=6);
select tt.chk('T0 module switch and mobile rule default ON', (select default_value from rules where key='employees_module_on')='true'::jsonb and (select default_value from rules where key='employee_mobile_unique')='true'::jsonb);

\echo == who may register
set role authenticated; select tt.as(:'s');
select tt.err('T1 view-only manager cannot register', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":1}')$$, 'not allowed');
select tt.as(:'o'); select set_user_grant(:'s'::uuid,'employee_manage') is null as g1 \gset
select tt.as(:'s');
select tt.err('T1 manager cannot register at a place that is not theirs', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":2}')$$, 'not allowed');
select tt.err('T1 name is required', $$select employee_save(null, gen_random_uuid(), '{"primary_location_id":1}')$$, 'name_required');
select tt.err('T1 place is required', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম"}')$$, 'location_required');
select tt.err('T1 bad mobile', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":1,"mobile":"12345"}')$$, 'bad_mobile');
select tt.err('T1 bad NID', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":1,"nid_no":"123"}')$$, 'bad_nid');
select tt.err('T1 bad birth date', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":1,"date_of_birth":"2025-01-01"}')$$, 'bad_date');
select tt.err('T1 bad gender', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":1,"gender":"x"}')$$, 'bad_gender');
select tt.err('T1 bad email', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":1,"email":"nope"}')$$, 'bad_email');
select tt.err('T1 too long name', format($$select employee_save(null, gen_random_uuid(), jsonb_build_object('full_name_bn', %L, 'primary_location_id', 1))$$, repeat('x',130)), 'too_long');
select tt.err('T1 unknown place', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"রহিম","primary_location_id":99}')$$, 'bad_location');
select employee_save(null, null, '{"full_name_bn":"ড্রাই","primary_location_id":1}', true) ->> 'dry' as dr \gset
select tt.chk('T1 dry run answers and writes nothing', :'dr'='true' and (select count(*) from employees)=0);
select '11111111-1111-1111-1111-111111111111' as c1 \gset
select employee_save(null, :'c1'::uuid, '{"full_name_bn":"আব্দুল করিম","full_name_en":"Abdul TestF","primary_location_id":1,"mobile":"+8801711000001","nid_no":"1990123456789","gender":"male","blood_group":"B+"}') as a1 \gset
select (:'a1'::jsonb ->> 'id') as aid, (:'a1'::jsonb ->> 'status') as ast \gset
select tt.chk('T1 draft saved, no number yet', :'ast'='draft' and (:'a1'::jsonb ->> 'employee_no') is null);
select tt.chk('T1 same client key = same row (idempotent)', (employee_save(null, :'c1'::uuid, '{"full_name_bn":"আব্দুল করিম","primary_location_id":1}') ->> 'id') = :'aid' and (select count(*) from employees)=1);
select tt.chk('T1 mobile normalised', (select mobile from employees where id=:'aid'::uuid)='01711000001');
select tt.as(:'o'); select set_rule('employees_module_on','false'::jsonb) is null as r0 \gset
select tt.as(:'s'); select tt.err('T1 module switched off refuses writes', format($$select employee_save(%L::uuid, null, '{"notes":"x"}')$$, :'aid'), 'module_off');
select tt.as(:'o'); select set_rule('employees_module_on','true'::jsonb) is null as r1 \gset

\echo == submit and number
select tt.as(:'s');
select tt.err('T2 joining date needed to finish', format($$select employee_submit(%L::uuid)$$, :'aid'), 'joining_date_required');
select employee_save(:'aid'::uuid, null, format('{"joining_date":"%s","designation":"cashier","employment_type":"permanent","department":"showroom","primary_role_code":"cashier","probation_end":"%s"}', :'dm60', :'dp30')::jsonb) is not null as u1 \gset
select tt.chk('T2 partial update keeps other fields', (select full_name_en from employees where id=:'aid'::uuid)='Abdul TestF' and (select designation from employees where id=:'aid'::uuid)='cashier');
select employee_submit(:'aid'::uuid) ->> 'employee_no' as n1 \gset
select tt.chk('T2 first number is E-0001', :'n1'='E-0001');
select tt.chk('T2 submit again is a no-op', (employee_submit(:'aid'::uuid) ->> 'employee_no')='E-0001' and (employee_submit(:'aid'::uuid) ->> 'repeat')='true');
select employee_save(null, gen_random_uuid(), '{"full_name_bn":"বাতিল","primary_location_id":1}') ->> 'id' as dd \gset
select employee_discard(:'dd'::uuid, 'typo') ->> 'status' as dst \gset
select tt.chk('T2 a draft can be discarded (kept, status discarded)', :'dst'='discarded' and (select count(*) from employees where status='discarded')=1);
select tt.err('T2 a registered person cannot be discarded', format($$select employee_discard(%L::uuid)$$, :'aid'), 'not_a_draft');
select tt.as(:'o');
select employee_save(null, gen_random_uuid(), format('{"full_name_bn":"সালমা বেগম","full_name_en":"TestM Begum","primary_location_id":2,"mobile":"01811000002","nid_no":"19901234567890123","joining_date":"%s","designation":"salesperson","department":"showroom","gender":"female"}', :'dm60')::jsonb) ->> 'id' as bid \gset
select employee_submit(:'bid'::uuid) ->> 'employee_no' as n2 \gset
select tt.chk('T2 numbers keep counting, no gap after a discarded draft', :'n2'='E-0002');
reset role;
select tt.err('T2 employee_no cannot be changed', format($$update employees set employee_no='E-9999' where id=%L::uuid$$, :'aid'), 'employee_no_immutable');
select tt.err('T2 an employee cannot be deleted', format($$delete from employees where id=%L::uuid$$, :'aid'), 'nothing is deleted');
set role authenticated; select tt.as(:'o');

\echo == duplicates
select tt.as(:'s');
select tt.err('T3 same NID refused', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"অন্য","primary_location_id":1,"nid_no":"1990-1234-56789"}')$$, 'duplicate_nid');
select tt.err('T3 same mobile refused (rule on)', $$select employee_save(null, gen_random_uuid(), '{"full_name_bn":"অন্য","primary_location_id":1,"mobile":"01711000001"}')$$, 'duplicate_mobile');
select employee_dup_check('1990123456789','01811000002',null) as dc \gset
select tt.chk('T3 dup check lists the other person for NID and for mobile', jsonb_array_length(:'dc'::jsonb->'nid')=1 and (:'dc'::jsonb->'nid'->0->>'employee_no')='E-0001' and jsonb_array_length(:'dc'::jsonb->'mobile')=1 and (:'dc'::jsonb->>'mobile_blocks')='true');
select tt.chk('T3 dup check ignores the person themself', jsonb_array_length(employee_dup_check('1990123456789',null,:'aid'::uuid)->'nid')=0);
select tt.as(:'o'); select set_rule('employee_mobile_unique','false'::jsonb) is null as r2 \gset
select tt.as(:'s');
select employee_save(null, gen_random_uuid(), '{"full_name_bn":"যমজ","primary_location_id":1,"mobile":"01711000001"}') as tw \gset
select tt.chk('T3 rule off: same mobile saved with a warning', jsonb_array_length(:'tw'::jsonb->'warnings'->'mobile')=1);
select employee_discard((:'tw'::jsonb->>'id')::uuid,'test') is not null as dx \gset
select tt.as(:'o'); select set_rule('employee_mobile_unique','true'::jsonb) is null as r3 \gset
select tt.as(:'k'); select tt.err('T3 dup check needs the register right', $$select employee_dup_check('1990123456789',null,null)$$, 'not allowed');

\echo == who sees whom
select tt.as(:'s'); select tt.chk('T4 manager of place 1 sees only place 1', (select count(*) from employees where status<>'discarded')=1 and (select count(*) from employees where id=:'bid'::uuid)=0);
select tt.as(:'t'); select tt.chk('T4 manager of place 2 sees only place 2', (select count(*) from employees where id=:'bid'::uuid)=1 and (select count(*) from employees where id=:'aid'::uuid)=0);
select tt.as(:'k'); select tt.chk('T4 storekeeper (no right) sees nobody', (select count(*) from employees)=0);
select tt.as(:'h'); select tt.chk('T4 head of management sees both places', (select count(*) from employees where status='active')=2);
select tt.as(:'t'); select tt.err('T4 view-only manager cannot edit', format($$select employee_save(%L::uuid, null, '{"notes":"x"}')$$, :'bid'), 'not allowed');
select tt.as(:'s'); select tt.err('T4 pay account column is closed', $$select bank_account from employees$$, 'permission denied');
select tt.as(:'o'); select employee_locations_set(:'aid'::uuid, array[2]) ->> 'id' as ls \gset
select tt.as(:'t'); select tt.chk('T4 a place where the person also works can see them', (select count(*) from employees where id=:'aid'::uuid)=1);
select tt.err('T4 ...but cannot edit them (only the main place can)', format($$select employee_save(%L::uuid, null, '{"notes":"x"}')$$, :'aid'), 'not allowed');
select tt.as(:'s'); select employee_locations_set(:'aid'::uuid, array[1]) is not null as ls2 \gset
select tt.as(:'t'); select tt.chk('T4 removing the other place removes the view', (select count(*) from employees where id=:'aid'::uuid)=0 and (select count(*) from employee_locations where active)=0);
select tt.as(:'s'); select tt.err('T4 transfer to a place the manager does not own is refused', format($$select employee_save(%L::uuid, null, '{"primary_location_id":2}')$$, :'aid'), 'not allowed');

\echo == pay (salary is sensitive)
select tt.as(:'s');
select tt.err('T5 manager without salary right cannot set pay', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 20000, 'none', null, '[]', '[]', null)$$, :'aid', :'dm60'), 'not allowed');
select tt.as(:'o'); select set_user_grant(:'h'::uuid,'salary_manage') is null as g2, set_user_grant(:'h'::uuid,'salary_view') is null as g3 \gset
select tt.as(:'h');
select employee_pay_set(:'aid'::uuid, :'dm60'::date, 'monthly', 20000, 'multiple_of_hourly', 1.5, '[{"name":"Eid","months_of_basic":1,"min_service_months":6}]',
  '[{"kind":"allowance","name":"House rent","percent_of_basic":40,"taxable":false},{"kind":"allowance","name":"Medical","amount":1500},{"kind":"deduction","name":"Provident fund","percent_of_basic":5}]', 'preview', null, true) as pv \gset
select tt.chk('T5 preview computes gross 29500 and net 28500, writes nothing', (:'pv'::jsonb->>'gross')::numeric=29500 and (:'pv'::jsonb->>'net')::numeric=28500 and (:'pv'::jsonb->>'deductions')::numeric=1000 and (:'pv'::jsonb->>'allowances')::numeric=9500
  and (select count(*) from employee_pay)=0);
select '22222222-2222-2222-2222-222222222222' as pc1 \gset
select employee_pay_set(:'aid'::uuid, :'dm60'::date, 'monthly', 20000, 'multiple_of_hourly', 1.5, '[{"name":"Eid","months_of_basic":1,"min_service_months":6}]',
  '[{"kind":"allowance","name":"House rent","percent_of_basic":40,"taxable":false},{"kind":"allowance","name":"Medical","amount":1500},{"kind":"deduction","name":"Provident fund","percent_of_basic":5}]', 'first', :'pc1'::uuid) as pv1 \gset
select tt.chk('T5 pay v1 saved with its lines', (select count(*) from employee_pay)=1 and (select count(*) from employee_pay_components)=3 and (:'pv1'::jsonb->>'net')::numeric=28500);
select tt.chk('T5 same client key = no second row', (employee_pay_set(:'aid'::uuid, :'dm60'::date, 'monthly', 20000, 'none', null, '[]', '[]', null, :'pc1'::uuid) ->> 'repeat')='true' and (select count(*) from employee_pay)=1);
select employee_pay_set(:'aid'::uuid, :'dm10'::date, 'monthly', 25000, 'rate_per_hour', 150, '[]', '[{"kind":"allowance","name":"House rent","percent_of_basic":40}]', 'raise') is not null as v2 \gset
select employee_pay_set(:'aid'::uuid, :'dp30'::date, 'monthly', 30000, 'none', null, '[]', '[]', 'future') is not null as v3 \gset
select tt.chk('T5 current pay = latest effective_from <= today (25000)', (employee_pay_current(:'aid'::uuid) ->> 'basic')::numeric=25000 and (employee_pay_current(:'aid'::uuid) ->> 'gross')::numeric=35000);
select tt.chk('T5 pay on an older date = 20000', (employee_pay_current(:'aid'::uuid, :'dm30'::date) ->> 'basic')::numeric=20000);
select tt.chk('T5 pay on a future date = 30000', (employee_pay_current(:'aid'::uuid, :'dp31'::date) ->> 'basic')::numeric=30000);
select tt.chk('T5 before the first version there is no pay', employee_pay_current(:'aid'::uuid, (:'dm100')::date) is null);
select tt.chk('T5 history has 3 versions, newest effective date first', jsonb_array_length(employee_pay_history(:'aid'::uuid))=3 and (employee_pay_history(:'aid'::uuid)->0->>'basic')::numeric=30000);
select employee_pay_set(:'aid'::uuid, :'dm10'::date, 'monthly', 26000, 'rate_per_hour', 150, '[]', '[]', 'correction') is not null as v2b \gset
select tt.chk('T5 same-day correction: the later row wins', (employee_pay_current(:'aid'::uuid) ->> 'basic')::numeric=26000 and (select count(*) from employee_pay)=4);
select tt.chk('T5 bonus rule and OT stored', (select bonus_rules->0->>'name' from employee_pay where effective_from=:'dm60'::date)='Eid' and (select ot_value from employee_pay where effective_from=:'dm60'::date)=1.5 and (select ot_hours_basis from employee_pay where effective_from=:'dm60'::date)=8);
select tt.err('T5 OT multiple above 5 refused', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 100, 'multiple_of_hourly', 6, '[]', '[]', null)$$, :'aid', :'td'), 'bad_ot_value');
select tt.err('T5 OT none must not carry a value', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 100, 'none', 2, '[]', '[]', null)$$, :'aid', :'td'), 'bad_ot_value');
select tt.err('T5 negative basic refused', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', -5, 'none', null, '[]', '[]', null)$$, :'aid', :'td'), 'bad_amount');
select tt.err('T5 absurd basic refused', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 1e13, 'none', null, '[]', '[]', null)$$, :'aid', :'td'), 'bad_amount');
select tt.err('T5 bad basis refused', format($$select employee_pay_set(%L::uuid, %L::date, 'weekly', 100, 'none', null, '[]', '[]', null)$$, :'aid', :'td'), 'bad_basis');
select tt.err('T5 date far in the future refused', format($$select employee_pay_set(%L::uuid, (%L::date + 900), 'monthly', 100, 'none', null, '[]', '[]', null)$$, :'aid', :'td'), 'bad_date');
select tt.err('T5 both amount and percent refused', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 100, 'none', null, '[]', '[{"kind":"allowance","name":"X","amount":5,"percent_of_basic":5}]', null)$$, :'aid', :'td'), 'component_amount_or_percent');
select tt.err('T5 duplicate component name refused', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 100, 'none', null, '[]', '[{"kind":"allowance","name":"X","amount":5},{"kind":"allowance","name":"x","amount":6}]', null)$$, :'aid', :'td'), 'duplicate_component');
select tt.err('T5 deductions above gross refused', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 100, 'none', null, '[]', '[{"kind":"deduction","name":"Fine","amount":500}]', null)$$, :'aid', :'td'), 'deductions_exceed_gross');
select tt.err('T5 bonus without months refused', format($$select employee_pay_set(%L::uuid, %L::date, 'monthly', 100, 'none', null, '[{"name":"Eid"}]', '[]', null)$$, :'aid', :'td'), 'bad_bonus');
select tt.chk('T5 rejected writes left nothing behind', (select count(*) from employee_pay)=4);
select employee_pay_account_set(:'aid'::uuid, 'DBBL 1234567890', '01711000001') is not null as pa \gset
select tt.chk('T5 pay account readable with salary_view', (employee_pay_account_get(:'aid'::uuid)->>'bank_account')='DBBL 1234567890' and (employee_pay_account_get(:'aid'::uuid)->>'mobile_wallet')='01711000001');
select tt.as(:'s');
select tt.chk('T5 table read returns nothing without salary_view', (select count(*) from employee_pay)=0 and (select count(*) from employee_pay_components)=0);
select tt.err('T5 pay function refuses', format($$select employee_pay_current(%L::uuid)$$, :'aid'), 'not allowed');
select tt.err('T5 history function refuses', format($$select employee_pay_history(%L::uuid)$$, :'aid'), 'not allowed');
select tt.err('T5 pay account refuses', format($$select employee_pay_account_get(%L::uuid)$$, :'aid'), 'not allowed');
select tt.err('T5 pay account write refuses', format($$select employee_pay_account_set(%L::uuid, 'x', null)$$, :'aid'), 'not allowed');
select tt.chk('T5 an ordinary employee row exposes no pay', (select row_to_json(x)::text from (select id, full_name_bn, mobile, designation, notes from employees where id=:'aid'::uuid) x) !~ '25000|26000|DBBL');
select tt.as(:'o'); select set_user_grant(:'t'::uuid,'salary_view',2) is null as g4 \gset
select tt.as(:'t');
select tt.err('T5 ...place 1 pay refused', format($$select employee_pay_current(%L::uuid)$$, :'aid'), 'not allowed');
select tt.as(:'h');
reset role;
select tt.err('T5 pay rows cannot be updated', $$update employee_pay set basic=1$$, 'append_only');
select tt.err('T5 pay rows cannot be deleted', $$delete from employee_pay$$, 'append_only');
select tt.err('T5 pay lines cannot be edited', $$update employee_pay_components set amount=1$$, 'append_only');
select tt.err('T5 pay lines cannot be deleted', $$delete from employee_pay_components$$, 'append_only');
update employee_pay_components set active = false where id = (select min(id) from employee_pay_components);
select tt.chk('T5 only the active flag of a line may change', (select count(*) from employee_pay_components where not active)=1);
set role authenticated; select tt.as(:'o');
select tt.chk('T5 owner reads the pay table', (select count(*) from employee_pay)=4);

\echo == leave and facilities
select tt.as(:'s');
select leave_entitlement_set(:'aid'::uuid,'casual',10) is not null as l1 \gset
select leave_entitlement_set(:'aid'::uuid,'casual',12) is not null as l2 \gset
select leave_entitlement_set(:'aid'::uuid,'sick',14) is not null as l3 \gset
select tt.chk('T6 leave days saved, one row per type, change in place', (select count(*) from employee_leave_entitlements)=2 and (select days_per_year from employee_leave_entitlements where leave_type='casual')=12);
select tt.err('T6 unknown leave type', format($$select leave_entitlement_set(%L::uuid,'holiday',3)$$, :'aid'), 'bad_leave_type');
select tt.err('T6 negative days', format($$select leave_entitlement_set(%L::uuid,'casual',-1)$$, :'aid'), 'bad_days');
select employee_benefit_save(null, null, :'aid'::uuid, 'meal', 'Lunch daily', null, :'dm60'::date, null) ->> 'id' as b1 \gset
select tt.err('T6 a value needs the salary right', format($$select employee_benefit_save(null, null, %L::uuid, 'phone', 'SIM', 300, %L::date, null)$$, :'aid', :'dm60'), 'not allowed');
select tt.as(:'h');
select employee_benefit_save(null, null, :'aid'::uuid, 'transport', 'Bus pass', 1200, :'dm60'::date, null) ->> 'id' as b2 \gset
select tt.chk('T6 salary people see the monthly value', (select (x->>'value_per_month')::numeric from jsonb_array_elements(employee_benefits_list(:'aid'::uuid)) x where x->>'kind'='transport')=1200);
select tt.as(:'s');
select tt.chk('T6 others see the facility but not its value', jsonb_array_length(employee_benefits_list(:'aid'::uuid))=2 and not exists (select 1 from jsonb_array_elements(employee_benefits_list(:'aid'::uuid)) x where x->>'value_per_month' is not null));
select tt.err('T6 value column is closed on the table', $$select value_per_month from employee_benefits$$, 'permission denied');
select tt.chk('T6 table read still lists kinds', (select count(*) from employee_benefits)=2);
select employee_benefit_end(:'b1'::bigint, :'td'::date) ->> 'id' as be \gset
select tt.chk('T6 ending a facility keeps it, inactive', (select active from employee_benefits where id=:'b1'::bigint)=false and (select to_date from employee_benefits where id=:'b1'::bigint)=:'td'::date);
select tt.err('T6 end before start refused', format($$select employee_benefit_end(%L::bigint, %L::date)$$, :'b2', :'dm100'), 'bad_date');
select tt.as(:'k'); select tt.err('T6 storekeeper cannot add facilities', format($$select employee_benefit_save(null, null, %L::uuid, 'meal', 'x', null, %L::date, null)$$, :'aid', :'td'), 'not allowed');
select tt.chk('T6 storekeeper reads none of it', (select count(*) from employee_benefits)=0 and (select count(*) from employee_leave_entitlements)=0);

\echo == documents and photo
select tt.as(:'s');
select employee_doc_add(:'aid'::uuid,'nid','EMPDOC/1/nid1.jpg','front side',gen_random_uuid()) ->> 'id' as d1 \gset
select tt.chk('T7 document recorded', (select count(*) from employee_documents)=1);
select tt.err('T7 file of another place refused', format($$select employee_doc_add(%L::uuid,'cv','EMPDOC/2/x.jpg',null)$$, :'aid'), 'bad_path');
select tt.err('T7 odd path refused', format($$select employee_doc_add(%L::uuid,'cv','../../etc/passwd',null)$$, :'aid'), 'bad_path');
select tt.err('T7 portrait kind must use the portrait folder', format($$select employee_doc_add(%L::uuid,'photo','EMPDOC/1/x.jpg',null)$$, :'aid'), 'bad_path');
select tt.err('T7 unknown kind refused', format($$select employee_doc_add(%L::uuid,'selfie','EMPDOC/1/x.jpg',null)$$, :'aid'), 'bad_kind');
select employee_set_photo(:'aid'::uuid,'EMP/1/portrait.jpg') ->> 'photo_path' as ph \gset
select tt.chk('T7 photo path set', :'ph'='EMP/1/portrait.jpg');
select tt.err('T7 photo of another place refused', format($$select employee_set_photo(%L::uuid,'EMP/2/p.jpg')$$, :'aid'), 'bad_path');
select tt.err('T7 void needs a reason', format($$select employee_doc_void(%L::bigint, '')$$, :'d1'), 'reason_required');
select tt.chk('T7 photo folder: manager of the place may upload and view', _emp_photo_ok('EMP/1/a.jpg','enter') and _emp_photo_ok('EMP/1/a.jpg','view') and _emp_photo_ok('EMPDOC/1/a.jpg','enter'));
select tt.chk('T7 photo folder: not other places', not _emp_photo_ok('EMP/2/a.jpg','enter') and not _emp_photo_ok('EMP/2/a.jpg','view'));
select tt.as(:'t'); select tt.chk('T7 view-only manager sees portraits of own place, not upload, not documents', _emp_photo_ok('EMP/2/a.jpg','view') and not _emp_photo_ok('EMP/2/a.jpg','enter') and not _emp_photo_ok('EMPDOC/2/a.jpg','view'));
select tt.as(:'k'); select tt.chk('T7 storekeeper has no access to either folder', not _emp_photo_ok('EMP/1/a.jpg','view') and not _emp_photo_ok('EMPDOC/1/a.jpg','view'));
select tt.chk('T7 documents invisible to non-managers', (select count(*) from employee_documents)=0);
select tt.as(:'s'); select employee_doc_void(:'d1'::bigint,'wrong person') is not null as dv \gset
select tt.chk('T7 voided document is kept', (select void from employee_documents where id=:'d1'::bigint) and (select count(*) from employee_documents)=1);

\echo == login link
select tt.as(:'s');
select employee_link_profile(:'aid'::uuid, :'p'::uuid) ->> 'profile_id' as lp \gset
select tt.chk('T8 login account linked', :'lp'=:'p');
select tt.as(:'o'); select tt.err('T8 one login = one person', format($$select employee_link_profile(%L::uuid, %L::uuid)$$, :'bid', :'p'), 'profile_already_linked');
select tt.err('T8 unknown account', format($$select employee_link_profile(%L::uuid, gen_random_uuid())$$, :'bid'), 'profile_not_found');
select tt.as(:'p'); select tt.chk('T8 the person sees their own record', (select count(*) from employees)=1);
select tt.as(:'o');

\echo == roles and deed templates
select tt.as(:'s'); select tt.err('T9 manager without deed right cannot make templates', $$select deed_template_save(null,'cashier','ক্যাশিয়ার চুক্তি','Cashier deed','[]')$$, 'not allowed');
select tt.as(:'o');
select staff_role_save('driver','ড্রাইভার','Driver',false,'Drives the van') ->> 'code' as nr \gset
select tt.chk('T9 owner adds a role', :'nr'='driver' and (select count(*) from staff_roles)=12);
select tt.as(:'s'); select tt.err('T9 staff cannot add roles', $$select staff_role_save('x1','x','x',false,null)$$, 'not allowed');
select tt.as(:'o');
select deed_template_save(null,'cashier','ক্যাশিয়ার চুক্তি','Cashier deed',
  '[{"text_bn":"ক্যাশ সীমা","text_en":"Cash limit","kind":"amount","value":"50000","unit":"BDT"},{"text_en":"Count cash with a second person","kind":"rule"},{"text_en":"Notice period","kind":"duration","value":"30","unit":"days"}]') as t1 \gset
select (:'t1'::jsonb->>'id')::bigint as tid, (:'t1'::jsonb->>'family_id')::bigint as tfam \gset
select tt.chk('T9 new template = version 1 of its own family', (:'t1'::jsonb->>'version')::int=1 and :'tid'=:'tfam');
select tt.chk('T9 clauses are numbered', (select clauses->2->>'no' from deed_templates where id=:'tid')='3');
select tt.chk('T9 identical save changes nothing', (deed_template_save(:'tfam'::bigint,'cashier','ক্যাশিয়ার চুক্তি','Cashier deed', (select clauses from deed_templates where id=:'tid')) ->> 'unchanged')='true' and (select count(*) from deed_templates)=1);
select deed_template_save(:'tfam'::bigint,'cashier','ক্যাশিয়ার চুক্তি','Cashier deed',
  '[{"text_bn":"ক্যাশ সীমা","text_en":"Cash limit","kind":"amount","value":"60000","unit":"BDT"},{"text_en":"Count cash with a second person","kind":"rule"},{"text_en":"Notice period","kind":"duration","value":"30","unit":"days"},{"text_en":"Security deposit held","kind":"text"}]') as t2 \gset
select (:'t2'::jsonb->>'id')::bigint as tid2 \gset
select tt.chk('T9 a change is a new version; the old one is kept unchanged but inactive', (:'t2'::jsonb->>'version')::int=2 and (select active from deed_templates where id=:'tid')=false and (select clauses->0->>'value' from deed_templates where id=:'tid')='50000' and (select active from deed_templates where id=:'tid2'));
reset role;
select tt.err('T9 template content is immutable', format($$update deed_templates set title_bn='x' where id=%L$$, :'tid'), 'template_immutable');
select tt.err('T9 templates are never deleted', format($$delete from deed_templates where id=%L$$, :'tid'), 'nothing is deleted');
set role authenticated; select tt.as(:'o');
select tt.err('T9 bad clause kind', $$select deed_template_save(null,'guard','t','t','[{"text_en":"x","kind":"magic"}]')$$, 'bad_clause_kind');
select tt.err('T9 empty clause refused', $$select deed_template_save(null,'guard','t','t','[{"kind":"rule"}]')$$, 'clause_text_required');
select tt.err('T9 unknown role', $$select deed_template_save(null,'astronaut','t','t','[]')$$, 'bad_role');
select tt.err('T9 amount clause must be a number', $$select deed_template_save(null,'guard','t','t','[{"text_en":"x","kind":"amount","value":"lots"}]')$$, 'bad_clause_value');

\echo == deeds
select tt.as(:'s');
select deed_save(null, gen_random_uuid(), :'aid'::uuid, :'tid2'::bigint, 'cashier', null, null, :'dm5'::date, :'dp10'::date, 90, 30, 5000, 'TestK Uddin', '01911000003', '1990123456000') as dd1 \gset
select (:'dd1'::jsonb->>'id')::bigint as did1 \gset
select tt.chk('T10 draft deed copies the template clauses and title', (select jsonb_array_length(clauses) from employee_deeds where id=:'did1')=4 and (select title from employee_deeds where id=:'did1')='ক্যাশিয়ার চুক্তি' and (select status from employee_deeds where id=:'did1')='draft');
select tt.err('T10 the manager without deed right cannot put a deed in force', format($$select deed_activate(%L::bigint)$$, :'did1'), 'not allowed');
select tt.err('T10 template for another role refused', format($$select deed_save(null, gen_random_uuid(), %L::uuid, %L::bigint, 'guard', null, null, %L::date, null, null, null, null, null, null, null)$$, :'aid', :'tid2', :'dm5'), 'template_role_mismatch');
select tt.err('T10 end before start refused', format($$select deed_save(null, gen_random_uuid(), %L::uuid, null, 'guard', 'x', '[{"text_en":"x"}]', %L::date, %L::date, null, null, null, null, null, null)$$, :'aid', :'td', :'dm5'), 'bad_date');
select tt.err('T10 negative deposit refused', format($$select deed_save(null, gen_random_uuid(), %L::uuid, null, 'guard', 'x', '[{"text_en":"x"}]', %L::date, null, null, null, -1, null, null, null)$$, :'aid', :'td'), 'bad_amount');
select deed_save(:'did1'::bigint, null, null, :'tid2'::bigint, 'cashier', 'Cashier deed v2', null, :'dm5'::date, :'dp10'::date, 90, 30, 6000, 'TestK Uddin', '01911000003', null) is not null as dsv \gset
select tt.chk('T10 a draft can be edited', (select security_deposit from employee_deeds where id=:'did1')=6000 and (select title from employee_deeds where id=:'did1')='Cashier deed v2');
select tt.as(:'o'); select set_user_grant(:'h'::uuid,'deed_manage') is null as g5 \gset
select deed_activate(:'did1'::bigint, :'td'::date, 'EMPDOC/1/deed1.jpg') ->> 'status' as das \gset
select tt.chk('T10 deed in force', :'das'='active' and (select signed_doc_path from employee_deeds where id=:'did1')='EMPDOC/1/deed1.jpg');
select deed_save(null, gen_random_uuid(), :'aid'::uuid, :'tid2'::bigint, 'cashier', null, null, :'td'::date, null, null, null, null, null, null, null) ->> 'id' as dd2 \gset
select tt.err('T10 a second active deed for the same role is refused', format($$select deed_activate(%L::bigint)$$, :'dd2'), 'active_deed_exists');
select tt.as(:'s');
select tt.err('T10 an active deed cannot be edited', format($$select deed_save(%L::bigint, null, null, null, 'cashier', 'x', null, null, null, null, null, null, null, null, null)$$, :'did1'), 'deed_not_draft');
reset role;
select tt.err('T10 an active deed is immutable even for a direct update', format($$update employee_deeds set clauses='[]' where id=%L$$, :'did1'), 'deed_immutable');
select tt.err('T10 title immutable too', format($$update employee_deeds set title='x' where id=%L$$, :'did1'), 'deed_immutable');
select tt.err('T10 deeds are never deleted', format($$delete from employee_deeds where id=%L$$, :'did1'), 'append_only');
set role authenticated; select tt.as(:'s');
select deed_revise(:'did1'::bigint) as rv \gset
select (:'rv'::jsonb->>'id')::bigint as rid \gset
select tt.chk('T10 revision is a new draft: revision 2 supersedes the active deed', (:'rv'::jsonb->>'revision_no')::int=2 and (select supersedes_id from employee_deeds where id=:'rid')=:'did1' and (select status from employee_deeds where id=:'did1')='active');
select tt.err('T10 only one open revision', format($$select deed_revise(%L::bigint)$$, :'did1'), 'revision_already_open');
select deed_save(:'rid'::bigint, null, null, :'tid2'::bigint, 'cashier', 'Cashier deed v2 rev2', null, :'dm5'::date, :'dp10'::date, 90, 45, 6000, 'TestK Uddin', '01911000003', null) is not null as e2 \gset
select tt.as(:'h');
select deed_activate(:'rid'::bigint, :'td'::date, null) ->> 'revision_no' as ar \gset
select tt.chk('T10 activating the revision supersedes the old deed; still one active per role', :'ar'='2' and (select status from employee_deeds where id=:'did1')='superseded' and (select count(*) from employee_deeds where employee_id=:'aid'::uuid and role_code='cashier' and status='active')=1 and (select notice_days from employee_deeds where id=:'did1')=30);
select tt.chk('T10 history keeps both revisions', (select count(*) from employee_deeds where employee_id=:'aid'::uuid and role_code='cashier')=3);
select tt.err('T10 a superseded deed cannot be ended again', format($$select deed_end(%L::bigint, 'oops')$$, :'did1'), 'deed_not_active');
select deed_save(null, gen_random_uuid(), :'aid'::uuid, null, 'storekeeper', 'Stock responsibility', '[{"text_en":"Responsible for stock count","kind":"rule"}]', :'td'::date, null, null, 15, null, null, null, null) ->> 'id' as dd3 \gset
select deed_activate(:'dd3'::bigint) ->> 'status' as a3 \gset
select tt.chk('T10 a different role can be active at the same time', :'a3'='active' and (select count(*) from employee_deeds where employee_id=:'aid'::uuid and status='active')=2);
select tt.err('T10 reason needed to end a deed', format($$select deed_end(%L::bigint, '')$$, :'dd3'), 'reason_required');
select tt.as(:'k'); select tt.chk('T10 storekeeper sees no deeds', (select count(*) from employee_deeds)=0 and (select count(*) from deed_templates)=0);
select tt.as(:'t'); select tt.chk('T10 view-only manager sees no deeds or templates', (select count(*) from employee_deeds)=0 and (select count(*) from deed_templates)=0);
select tt.as(:'s'); select tt.chk('T10 register-right holders read the deeds of their place', (select count(*) from employee_deeds)=4 and (select count(*) from deed_templates)=2);

\echo == expiry warnings
select tt.as(:'s');
select tt.chk('T11 deed ending in 10 days shows with a 30-day window (rule default)', (select count(*) from deeds_expiring())=1 and (select days_left from deeds_expiring() limit 1)=10 and (select employee_no from deeds_expiring() limit 1)='E-0001');
select tt.chk('T11 not with a 5-day window', (select count(*) from deeds_expiring(5))=0);
select tt.err('T11 absurd window refused', $$select * from deeds_expiring(100000)$$, 'bad_days');
select tt.as(:'o'); select deed_save(null, gen_random_uuid(), :'bid'::uuid, null, 'salesperson', 'Sales deed', '[{"text_en":"Target as agreed","kind":"text"}]', :'dm100'::date, :'dm1'::date, null, null, null, null, null, null) ->> 'id' as dd4 \gset
select deed_activate(:'dd4'::bigint) is not null as a4 \gset
select tt.chk('T11 an ended-but-not-yet-expired deed is listed with negative days', (select days_left from deeds_expiring(0) where deed_id=:'dd4'::bigint)=-1);
select tt.as(:'t'); select tt.chk('T11 the manager of place 2 does not see place 1 deeds', (select count(*) from deeds_expiring(30))=0);
select tt.as(:'o'); select deed_expire_due() as ex \gset
select tt.chk('T11 expire_due marks only the passed deed', :'ex'=1 and (select status from employee_deeds where id=:'dd4'::bigint)='expired' and (select count(*) from employee_deeds where status='active')=2);
select tt.chk('T11 running it again does nothing', deed_expire_due()=0);

\echo == status and leaving
select tt.as(:'s');
select tt.err('T12 reason needed to leave', format($$select employee_status_set(%L::uuid,'resigned',%L::date,'')$$, :'aid', :'td'), 'reason_required');
select tt.err('T12 bad status', format($$select employee_status_set(%L::uuid,'fired',%L::date,'x')$$, :'aid', :'td'), 'bad_status');
select tt.err('T12 same status', format($$select employee_status_set(%L::uuid,'active',%L::date,'x')$$, :'aid', :'td'), 'same_status');
select employee_status_set(:'aid'::uuid,'on_leave',:'td'::date,'long leave') ->> 'status' as sl \gset
select tt.chk('T12 on leave', :'sl'='on_leave');
select employee_status_set(:'aid'::uuid,'active',:'td'::date,'back') is not null as sb \gset
select employee_status_set(:'aid'::uuid,'resigned',:'td'::date,'found another job') ->> 'status' as sr \gset
select tt.chk('T12 resigned: the person stays, active deeds end', :'sr'='resigned' and (select count(*) from employees where id=:'aid'::uuid)=1 and (select count(*) from employee_deeds where employee_id=:'aid'::uuid and status='active')=0
  and (select count(*) from employee_deeds where employee_id=:'aid'::uuid and status='terminated' and end_reason='employee_resigned')=3);
select tt.chk('T12 history logged each change', (select string_agg(to_status, ',' order by id) from employee_status_log where employee_id=:'aid'::uuid)='active,on_leave,active,resigned');
select tt.err('T12 no new deed for a person who left', format($$select deed_save(null, gen_random_uuid(), %L::uuid, null, 'guard', 'x', '[{"text_en":"x"}]', %L::date, null,null,null,null,null,null,null)$$, :'aid', :'td'), 'employee_not_working');
select tt.err('T12 only the owner can bring someone back', format($$select employee_status_set(%L::uuid,'active',%L::date,'rehired')$$, :'aid', :'td'), 'owner_only');
select tt.as(:'o'); select employee_status_set(:'aid'::uuid,'active',:'td'::date,'rehired') ->> 'status' as ra \gset
select tt.chk('T12 owner re-hires', :'ra'='active');
reset role;
select tt.err('T12 status log is append-only', $$update employee_status_log set reason='x'$$, 'append_only');
select tt.chk('T13 audit trail written for people, pay and deeds', (select count(distinct table_name) from audit_log where table_name in ('employees','employee_pay','employee_deeds','employee_documents','employee_benefits'))=5);
set role authenticated; select tt.as(:'s');
select tt.chk('T13 audit log hides pay from non-owners', (select count(*) from audit_log where table_name='employee_pay')=0);
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
