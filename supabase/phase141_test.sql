-- FRESH DB ONLY. Phase 141 tests (W1-FIX finding 5: supplier_pay_over can count the payments of the same person to the same supplier over N days).
--   build a database through phase 99 (tests/sql/ORDER.txt), paste phase141.sql once, then:
--   psql -h /tmp -p 5610 -U postgres -d a141db -qAt -f supabase/phase141_test.sql | grep -E 'FAIL|RESULT'      (run from the repository root)
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000141'
\set u_p1 '00000000-0000-0000-0000-000000000241'
\set u_p2 '00000000-0000-0000-0000-000000000341'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.paid(p_sup uuid, p_user uuid) returns numeric language sql stable security definer as $$
  select coalesce(sum(amount), 0) from public.supplier_payments where supplier_id = p_sup and created_by = p_user and not voided $$;
create or replace function tt.req(p_sup uuid, p_status text) returns bigint language sql stable security definer as $$
  select count(*) from public.w1e_requests where kind = 'supplier_pay' and status = p_status and payload ->> 'supplier' = p_sup::text $$;
create or replace function tt.qid(p_sup uuid, p_amt numeric, p_status text) returns bigint language sql stable security definer as $$
  select max(id) from public.w1e_requests where kind = 'supplier_pay' and status = p_status and payload ->> 'supplier' = p_sup::text and amount = p_amt $$;
create or replace function tt.age_pay(p_sup uuid, p_user uuid, p_days int) returns void language plpgsql security definer as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  update public.supplier_payments set paid_at = paid_at - make_interval(days => p_days) where supplier_id = p_sup and created_by = p_user;
  perform set_config('session_replication_role', 'origin', true);
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner141@s.app','{"full_name":"test_owner141"}'), (:'u_p1','test_payer141a@s.app','{"full_name":"test_payer141a"}'), (:'u_p2','test_payer141b@s.app','{"full_name":"test_payer141b"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_p1','salesperson'),(:'u_p2','salesperson') on conflict do nothing;
insert into user_locations values (:'u_p1',1),(:'u_p2',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_p1','supplier_pay',null),(:'u_p2','supplier_pay',null);
insert into suppliers (name, opening_balance) values ('test_supplier_141a', 500000) returning id as sa \gset
insert into suppliers (name, opening_balance) values ('test_supplier_141b', 500000) returning id as sb \gset
insert into suppliers (name, opening_balance) values ('test_supplier_141c', 500000) returning id as sc \gset

\echo == T0 shape, safe default, internals closed, hooks in place
select tt.chk('T0 phase141 present; marker bos141 is inside _w1e_pay_gate', to_regprocedure('public._w1x_present141()') is not null
  and position('bos141' in pg_get_functiondef('public._w1e_pay_gate(uuid,integer,jsonb,uuid,text,numeric)'::regprocedure))>0);
select tt.chk('T0 the setting is a number of days, default 0 (= per call, as today), range 0 to 365, English label and hint',
  (select kind='number' and default_value='0'::jsonb and min_value=0 and max_value=365 and unit='days' and label_en ~ '^[A-Za-z]' and hint_en ~ '^[A-Za-z]' from rules where key='supplier_pay_over_cumulative_days')
  and coalesce(rule_num('supplier_pay_over_cumulative_days'),0)=0 and rule_num('supplier_pay_over') is null);
select tt.chk('T0 internals closed to browsers', not has_function_privilege('authenticated','public._w1x_pay_prior(uuid)','execute') and not has_function_privilege('authenticated','public._w1x_pay_note(uuid)','execute')
  and not has_function_privilege('anon','public._w1x141_hooks()','execute') and not has_function_privilege('authenticated','public._w1x_patch(regprocedure,text[],text)','execute'));

\echo == T1 default (days = 0): the limit is per call, exactly as before. Splitting avoids it (this is the gap the setting closes)
set role authenticated; select tt.as(:'u_o');
select set_rule('supplier_pay_over','5000') is null as o1 \gset
select tt.as(:'u_p1');
select pay_supplier(:'sa'::uuid, 1, '[{"mode":"cash","amount":4000}]'::jsonb, gen_random_uuid(), 't1-a') ->> 'paid' as t1a \gset
select pay_supplier(:'sa'::uuid, 1, '[{"mode":"cash","amount":4000}]'::jsonb, gen_random_uuid(), 't1-b') ->> 'paid' as t1b \gset
select pay_supplier(:'sa'::uuid, 1, '[{"mode":"cash","amount":6000}]'::jsonb, gen_random_uuid(), 't1-c') ->> 'pending' as t1c \gset
reset role;
select tt.chk('T1 days = 0: 4000 and 4000 are paid at once (8000 in total), a single 6000 call waits as before', :'t1a'::numeric=4000 and :'t1b'::numeric=4000 and :'t1c'='true' and tt.paid(:'sa'::uuid,:'u_p1')=8000 and tt.req(:'sa'::uuid,'pending')=1);
select tt.as(:'u_p1');
select tt.chk('T1 the helper counts nothing while the setting is 0', _w1x_pay_prior(:'sa'::uuid)=0 and _w1x_pay_note(:'sa'::uuid)='');
select tt.chk('T1 the request text is the old one (no "plus")', (select summary from w1e_requests where kind='supplier_pay' and payload->>'supplier'=:'sa' order by id desc limit 1) like '%(limit 5000)');

\echo == T2 days = 7: the limit counts this payment PLUS what the same person paid or has waiting to the same supplier in 7 days
set role authenticated; select tt.as(:'u_o');
select tt.err('T2 a negative number of days is refused', $$select set_rule('supplier_pay_over_cumulative_days','-1')$$, 'bad_value');
select tt.err('T2 more than 365 days is refused', $$select set_rule('supplier_pay_over_cumulative_days','400')$$, 'bad_value');
select set_rule('supplier_pay_over_cumulative_days','7') is null as d1 \gset
select tt.as(:'u_p1');
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":3000}]'::jsonb, gen_random_uuid(), 't2-a') ->> 'paid' as t2a \gset
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":2500}]'::jsonb, gen_random_uuid(), 't2-b') ->> 'pending' as t2b \gset
reset role;
select tt.chk('T2 3000 is under 5000: paid. The next 2500 is alone under 5000 but 3000 + 2500 = 5500 is over: it waits for the approver, nothing paid',
  :'t2a'::numeric=3000 and :'t2b'='true' and tt.paid(:'sb'::uuid,:'u_p1')=3000 and tt.req(:'sb'::uuid,'pending')=1);
select tt.chk('T2 the request text tells the approver why (plus 3000 already paid or waiting, 7 days)',
  (select summary from w1e_requests where id=tt.qid(:'sb'::uuid,2500,'pending')) like '%limit 5000, plus 3000 already paid or waiting by this person in the last 7 day(s))');
select tt.chk('T2 the new exception line for a payment above the limit is raised as before', exists (select 1 from money_exceptions where kind='w1e_pay_over_request'));
set role authenticated; select tt.as(:'u_p1');
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 't2-c') ->> 'pending' as t2c \gset
reset role;
select tt.chk('T2 splitting while a request is waiting does not help: 3000 paid + 2500 waiting + 1000 = over, it waits too', :'t2c'='true' and tt.req(:'sb'::uuid,'pending')=2 and tt.paid(:'sb'::uuid,:'u_p1')=3000);
-- another person is not counted
set role authenticated; select tt.as(:'u_p2');
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":3000}]'::jsonb, gen_random_uuid(), 't2-d') ->> 'paid' as t2d \gset
-- the same person, another supplier, is not counted
select tt.as(:'u_p1');
select pay_supplier(:'sc'::uuid, 1, '[{"mode":"cash","amount":3000}]'::jsonb, gen_random_uuid(), 't2-e') ->> 'paid' as t2e \gset
-- the owner is never held
select tt.as(:'u_o');
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":9000}]'::jsonb, gen_random_uuid(), 't2-f') ->> 'paid' as t2f \gset
reset role;
select tt.chk('T2 a different person (3000), the same person at another supplier (3000) and the owner (9000) are paid at once',
  :'t2d'::numeric=3000 and :'t2e'::numeric=3000 and :'t2f'::numeric=9000);

\echo == T3 rejected and approved requests, no double counting, old payments drop out of the window
set role authenticated; select tt.as(:'u_o');
select w1e_request_decide(tt.qid(:'sb'::uuid,1000,'pending'), false, 'test: too many parts') is not null as rj \gset
select tt.as(:'u_p1');
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":100}]'::jsonb, gen_random_uuid(), 't3-a') ->> 'pending' as t3a \gset
select tt.as(:'u_o');
select w1e_request_decide(tt.qid(:'sb'::uuid,2500,'pending'), true, 'test: approved') is not null as ap \gset
reset role;
select tt.as(:'u_p1');
-- p1 now: payments 3000 + 2500 (the approved request became a payment made by p1), waiting 100 (t3-a); the rejected 1000 is not counted; 5600 in total, each amount once
select tt.chk('T3 prior = 3000 paid + 2500 approved (now a payment) + 100 waiting = 5600; the rejected 1000 and the approved request are not counted twice',
  tt.paid(:'sb'::uuid,:'u_p1')=5500 and _w1x_pay_prior(:'sb'::uuid)=5600 and tt.req(:'sb'::uuid,'approved')=1 and tt.req(:'sb'::uuid,'rejected')=1);
set role authenticated; select tt.as(:'u_o');
select w1e_request_decide(tt.qid(:'sb'::uuid,100,'pending'), false, 'test: not needed') is not null as rj2 \gset
reset role;
select tt.age_pay(:'sb'::uuid, :'u_p1', 10);
select tt.as(:'u_p1');
select tt.chk('T3 payments older than 7 days drop out of the count', _w1x_pay_prior(:'sb'::uuid)=0);
set role authenticated;
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":4000}]'::jsonb, gen_random_uuid(), 't3-b') ->> 'paid' as t3b \gset
reset role;
select tt.chk('T3 so a new 4000 is paid at once', :'t3b'::numeric=4000);

\echo == T4 back to 0 days = per call again; a blank limit holds nothing
set role authenticated; select tt.as(:'u_o');
select set_rule('supplier_pay_over_cumulative_days','0') is null as d0 \gset
select tt.as(:'u_p1');
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":4900}]'::jsonb, gen_random_uuid(), 't4-a') ->> 'paid' as t4a \gset
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":4900}]'::jsonb, gen_random_uuid(), 't4-b') ->> 'paid' as t4b \gset
select tt.as(:'u_o');
select set_rule('supplier_pay_over_cumulative_days','7') is null as d7 \gset
select set_rule('supplier_pay_over',null) is null as o0 \gset
select tt.as(:'u_p1');
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":20000}]'::jsonb, gen_random_uuid(), 't4-c') ->> 'paid' as t4c \gset
reset role;
select tt.chk('T4 0 days: 4900 and 4900 are both paid (per call); limit blank with 7 days: 20000 is paid (the limit is off)', :'t4a'::numeric=4900 and :'t4b'::numeric=4900 and :'t4c'::numeric=20000);

\echo == T5 the other controls of the gate are untouched (repeat-payment check still works) and nothing else changed
set role authenticated; select tt.as(:'u_o');
select set_rule('supplier_pay_dup_mode','"block"') is null as m1 \gset
select tt.as(:'u_p2');
select tt.err('T5 block mode: the same supplier and total again is refused as before', format($$select pay_supplier(%L::uuid, 1, '[{"mode":"cash","amount":20000}]'::jsonb, gen_random_uuid(), 't5-dup')$$, :'sb'), 'duplicate_payment');
reset role;
select tt.chk('T5 hook function is idempotent (second call changes nothing)', (public._w1x141_hooks() ->> '_w1e_pay_gate')='false');
select tt.chk('T5 every journal entry balances', tt.unbalanced()=0);
select tt.chk('T5 no demo data: every name in this file starts with test_', not exists (select 1 from profiles where full_name <> '' and full_name not like 'test\_%'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
