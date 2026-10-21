-- FRESH DB ONLY. Phase 120 tests (pay requests: salary / advance / supplier payment requests, one approver, due list, payment through the existing functions, the "required" policy, exceptions, limits).
--   ORDER=all bash tests/sql/build_fresh_db.sh r1db        (builds through phase 99; then paste supabase/phase120.sql; any port)
--   psql -h /tmp -p 5595 -U postgres -d r1db -qAt -f supabase/phase120_test.sql | grep -E 'FAIL|RESULT'
-- No shared function is patched by phase 120 (the policy is a trigger), so no hook is applied here. Test data only (test_* names).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000120'
\set u_s1 '00000000-0000-0000-0000-000000000220'
\set u_s2 '00000000-0000-0000-0000-000000000320'
\set u_ap '00000000-0000-0000-0000-000000000420'
\set u_sa '00000000-0000-0000-0000-000000000520'
\set u_x '00000000-0000-0000-0000-000000000620'
\set u_hr '00000000-0000-0000-0000-000000000720'
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
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.cc(p_id bigint) returns text language sql stable as $$ select c.code from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id where a.id = p_id $$;
create or replace function tt.bal(p_id bigint) returns numeric language sql stable as $$ select tt.nd(tt.cc(p_id)) $$;
-- helpers that read the protected tables (security definer, test only)
create or replace function tt.st(p_id bigint) returns text language sql stable security definer as $$ select status from public.pay_requests where id = p_id $$;
create or replace function tt.nreq() returns bigint language sql stable security definer as $$ select count(*) from public.pay_requests $$;
create or replace function tt.nexc(p_kind text) returns bigint language sql stable security definer as $$ select count(*) from public.money_exceptions where kind = p_kind $$;
create or replace function tt.nev(p_id bigint, p_action text) returns bigint language sql stable security definer as $$ select count(*) from public.pay_request_events where request_id = p_id and action = p_action $$;
create or replace function tt.nnote(p_user uuid) returns bigint language sql stable security definer as $$ select count(*) from public.notifications where user_id = p_user and kind = 'pay_request' $$;
create or replace function tt.naud(p_action text) returns bigint language sql stable security definer as $$ select count(*) from public.audit_log where action = p_action $$;
create or replace function tt.cnt(p_sql text) returns bigint language plpgsql as $$ declare n bigint; begin execute p_sql into n; return n; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner120@s.app','{"full_name":"test_owner"}'), (:'u_s1','test_staff1_120@s.app','{"full_name":"test_staff1"}'), (:'u_s2','test_staff2_120@s.app','{"full_name":"test_staff2"}'),
 (:'u_ap','test_approver120@s.app','{"full_name":"test_approver"}'), (:'u_sa','test_store120@s.app','{"full_name":"test_store"}'), (:'u_x','test_other120@s.app','{"full_name":"test_other"}'),
 (:'u_hr','test_hr120@s.app','{"full_name":"test_hr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_s1','salesperson'),(:'u_s2','salesperson'),(:'u_ap','purchasing'),(:'u_sa','storekeeper'),(:'u_x','salesperson'),(:'u_hr','hr') on conflict do nothing;
insert into user_locations values (:'u_s1',1),(:'u_s2',1),(:'u_ap',1),(:'u_sa',1),(:'u_x',1),(:'u_hr',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_hr','payroll_manage',null),(:'u_hr','supplier_pay',null);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
with x as (insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id, profile_id) values ('TEST120_1','test_emp_1','test_emp_1','active',1,:'u_s1') returning id) select id as e1 from x \gset
with x as (insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id, profile_id) values ('TEST120_2','test_emp_2','test_emp_2','active',1,:'u_s2') returning id) select id as e2 from x \gset
with x as (insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id) values ('TEST120_3','test_emp_3','test_emp_3','active',1) returning id) select id as e3 from x \gset
with x as (insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id, profile_id) values ('TEST120_4','test_emp_4','test_emp_4','active',1,:'u_ap') returning id) select id as e4 from x \gset
with x as (insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id, profile_id) values ('TEST120_6','test_emp_6','test_emp_6','active',1,:'u_o') returning id) select id as e6 from x \gset
with x as (insert into employees (employee_no, full_name_bn, full_name_en, status, primary_location_id) values ('TEST120_5','test_emp_5','test_emp_5','active',1) returning id) select id as e5 from x \gset
with x as (insert into suppliers (name, opening_balance) values ('test_supplier_120', 50000) returning id) select id as sup from x \gset
select set_config('tt.e1', :'e1', false), set_config('tt.e2', :'e2', false), set_config('tt.e3', :'e3', false), set_config('tt.e4', :'e4', false), set_config('tt.e5', :'e5', false), set_config('tt.sup', :'sup', false) is not null as cfg \gset
-- an approved payroll run of last month: e1 net 8000, e2 net 6000, e5 net 3000
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 1, 'draft') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'e1', 1, 8000, 8000) returning id) select id as l1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'e2', 1, 6000, 6000) returning id) select id as l2 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'e5', 1, 3000, 3000) returning id) select id as l5 from x \gset

select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset
select acct_journal_post(:'pm'::date, 1, 'test opening', '[{"code":"1110","debit":900000},{"code":"1120","debit":300000},{"code":"3100","credit":1200000}]'::jsonb) is not null as s3 \gset
select payroll_approve(:'run1'::bigint) ->> 'status' as ap1 \gset
select (money_account_add('cash','test_drawer_120',null,null,null,null,1,null,0) ->> 'id')::bigint as mac \gset
select (money_account_add('bank','test_bank_120',null,'TestBank','Main','120-0001',null,null,0) ->> 'id')::bigint as mab \gset
select (money_account_add('wallet','test_wallet_120',null,'TestPay','','01700000120',null,null,0) ->> 'id')::bigint as maw \gset
select money_account_add('cash','test_drawer_120b',null,null,null,null,1,null,0) is not null as dummy \gset
select acct_journal_post(:'pm'::date, 1, 'test fund accounts', format('[{"account_id":%s,"debit":50000},{"account_id":%s,"debit":50000},{"account_id":%s,"debit":50000},{"code":"3100","credit":150000}]',
   (select coa_account_id from money_accounts where id=:'mac'), (select coa_account_id from money_accounts where id=:'mab'), (select coa_account_id from money_accounts where id=:'maw'))::jsonb) is not null as fund \gset

\echo == T0 shape, safe defaults, nothing replaced, internals closed
select tt.chk('T0 phase120 present, tables exist', to_regprocedure('public._p120_present()') is not null and to_regclass('public.pay_requests') is not null and to_regclass('public.pay_request_events') is not null and to_regclass('public.pay_request_exceptions') is not null);
select tt.chk('T0 14 settings exist with the SAFE defaults (all off / owner / reason / blank)',
  (select count(*) from rules where key in ('pay_requests_on','pay_requests_required','pay_requests_required_kinds','pay_request_approver_mode','pay_request_approver_role','pay_request_approver_user','pay_request_exception_mode','pay_request_max_per_month','pay_request_advance_ceiling','party_requests_on','party_requests_required','party_request_approver_mode','party_request_approver_role','party_request_approver_user'))=14
  and not rule_on('pay_requests_on') and not rule_on('pay_requests_required') and rule_txt('pay_requests_required_kinds')='both' and rule_txt('pay_request_approver_mode')='owner' and rule_txt('pay_request_approver_role') is null
  and rule_txt('pay_request_exception_mode')='reason' and rule_num('pay_request_max_per_month') is null and rule_num('pay_request_advance_ceiling') is null and not rule_on('party_requests_on') and not rule_on('party_requests_required')
  and rule_txt('party_request_approver_mode')='same');
select tt.chk('T0 every setting has a Bangla label, an English label and a hint', not exists (select 1 from rules where (key like 'pay_request%' or key like 'party_request%') and (label_bn is null or label_en is null or label_en !~ '^[ -~]+$')) and not exists (select 1 from rules where key in ('pay_requests_on','pay_requests_required','party_requests_on','party_requests_required') and (coalesce(hint_en,'')='' or coalesce(hint_bn,'')='')));
select tt.chk('T0 the Exceptions list has 19 kinds: the 18 old ones are all still there and r1_unbacked_payment is new', (select count(*) from pg_constraint where conrelid='money_exceptions'::regclass and conname='money_exceptions_kind_check' and pg_get_constraintdef(oid) like '%r1_unbacked_payment%'
   and pg_get_constraintdef(oid) like '%negative_warn%' and pg_get_constraintdef(oid) like '%recon_diff%' and pg_get_constraintdef(oid) like '%backdate_exception%' and pg_get_constraintdef(oid) like '%w1e_journal_request%' and pg_get_constraintdef(oid) like '%late_sale_held%')=1
  and (select cardinality(array(select m[1] from regexp_matches((select pg_get_constraintdef(oid) from pg_constraint where conname='money_exceptions_kind_check'), '''([a-z_0-9]+)''', 'g') m)))=19);
select tt.chk('T0 no shared function carries a phase 120 marker (nothing hooked)', position('bos120' in pg_get_functiondef('public.staff_advance_add(uuid,date,numeric,numeric,text,date,text,uuid)'::regprocedure))=0
  and position('bos120' in pg_get_functiondef('public.payroll_pay(bigint,bigint[],text,date,text,text,uuid,numeric)'::regprocedure))=0 and position('bos120' in pg_get_functiondef('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure))=0);
select tt.chk('T0 the gate trigger sits on the three payment tables', (select count(*) from pg_trigger where tgname='a0_r1_gate_bi')=3);
select tt.chk('T0 internals closed to browsers, API open', not has_function_privilege('authenticated','public._r1_gate_bi()','execute') and not has_function_privilege('authenticated','public._r1_approver_ok(uuid,text)','execute')
  and not has_function_privilege('authenticated','public._r1_link(bigint,numeric,text,text)','execute') and not has_function_privilege('anon','public.pay_request_state()','execute') and has_function_privilege('authenticated','public.pay_request_decide(bigint,boolean,date,numeric,text)','execute'));
select tt.chk('T0 the tables cannot be read, written or deleted by anon, and cannot be written by a browser role', not has_table_privilege('anon','public.pay_requests','select') and not has_table_privilege('authenticated','public.pay_requests','insert')
  and not has_table_privilege('authenticated','public.pay_requests','update') and not has_table_privilege('authenticated','public.pay_request_events','insert') and not has_table_privilege('authenticated','public.pay_request_exceptions','update') and has_table_privilege('authenticated','public.pay_requests','select'));
select tt.chk('T0 no hard delete', (select count(*) from pg_trigger where tgname in ('pay_requests_nodel','pay_request_events_nodel','pay_request_exceptions_nodel'))=3);

\echo == T1 every setting at its default: requests are refused, the old payment functions behave exactly as before, nothing is written, nothing is gated
set role authenticated; select tt.as(:'u_s1');
select tt.err('T1 a staff request is refused while the switch is off', format($$select pay_request_submit('advance', 1000, 'test need', %L::date, null, gen_random_uuid())$$, tt.today()+2), 'requests_off');
select tt.err('T1 a supplier request is refused while the switch is off', format($$select pay_request_submit('supplier', 1000, 'test need', %L::date, null, gen_random_uuid(), current_setting('tt.sup')::uuid, null, null, null, 1)$$, tt.today()+2), 'requests_off');
select tt.as(:'u_o');
select staff_advance_add(:'e3'::uuid, tt.today(), 700, 100, 'cash', tt.today(), 'ma#' || :'mac' || ';test t1 advance', gen_random_uuid()) is not null as t1a \gset
select payroll_pay(:'run1'::bigint, array[:'l5'::bigint], 'cash', tt.today(), 'ma#' || :'mac' || ';t1-sal', null, gen_random_uuid(), 500) is not null as t1b \gset
select pay_supplier(:'sup'::uuid, 1, jsonb_build_array(jsonb_build_object('mode','cash','amount',900,'wallet','ma#' || :'mac' || ';')), gen_random_uuid(), 'test t1') is not null as t1c \gset
select staff_advance_add(:'e3'::uuid, tt.today(), 100, null, 'none', tt.today(), 'test paper', gen_random_uuid()) is not null as t1d \gset
select tt.chk('T1 advance, salary and supplier payment work with no request, as today', exists (select 1 from employee_advances where employee_id=:'e3' and amount=700 and mode='cash' and money_account_id=:'mac')
  and exists (select 1 from payroll_payments where line_id=:'l5' and amount=500) and exists (select 1 from supplier_payments where supplier_id=:'sup' and amount=900));
select tt.chk('T1 no request, no event, no note, no exception row came out of the defaults', tt.nreq()=0 and (select count(*) from pay_request_events)=0 and tt.nexc('r1_unbacked_payment')=0 and tt.nnote(:'u_o')=0);
select tt.chk('T1 the state function says everything is off', (pay_request_state() ->> 'staff_on')='false' and (pay_request_state() ->> 'party_on')='false' and (pay_request_state() ->> 'staff_required')='false'
  and (pay_request_state() -> 'gate' ->> 'advance')='true' and (pay_request_counts() ->> 'inbox')='0');
reset role;
select acct_post_pending(false) ->> 'posted' as pp1 \gset
select tt.chk('T1 the three payments post to the ledger and every entry balances', tt.unbalanced()=0 and tt.bal(:'mac')=50000-700-500-900);

\echo == T2 switch on: sending a request
reset role; select tt.as(:'u_o');
set role authenticated;
select set_rule('pay_requests_on','true') is null as r1 \gset
select set_rule('party_requests_on','true') is null as r2 \gset
select tt.as(:'u_s1');
select (pay_request_submit('advance', 3000, 'test: rent due', tt.today()+3, null, '10000000-0000-0000-0000-000000000001') ->> 'id')::bigint as q1 \gset
select tt.chk('T2 staff 1 sends an advance request: status received, own employee, amount and date kept',
  tt.st(:'q1')='received' and (select employee_id=:'e1' and amount=3000 and needed_by=tt.today()+3 and not on_behalf and requested_by=:'u_s1' from pay_requests where id=:'q1'));
select tt.chk('T2 the same client id again answers the same request (no second row)', (pay_request_submit('advance', 3000, 'test: rent due', tt.today()+3, null, '10000000-0000-0000-0000-000000000001') ->> 'repeat')='true' and tt.nreq()=1);
select tt.err('T2 an amount of 0 is refused', format($$select pay_request_submit('advance', 0, 'test x', %L::date)$$, tt.today()+1), 'bad_amount');
select tt.err('T2 a reason shorter than 3 characters is refused', format($$select pay_request_submit('advance', 100, 'ab', %L::date)$$, tt.today()+1), 'reason_required');
select tt.err('T2 a date in the past is refused', format($$select pay_request_submit('advance', 100, 'test x', %L::date)$$, tt.today()-1), 'bad_date');
select tt.err('T2 an unknown kind is refused', format($$select pay_request_submit('bonus', 100, 'test x', %L::date)$$, tt.today()+1), 'bad_kind');
select tt.err('T2 staff 1 cannot send a request for staff 2 (no payroll right)', format($$select pay_request_submit('advance', 100, 'test x', %L::date, current_setting('tt.e2')::uuid)$$, tt.today()+1), 'not allowed');
select tt.as(:'u_x');
select tt.err('T2 a person without an employee record cannot send a salary request', format($$select pay_request_submit('salary', 100, 'test x', %L::date)$$, tt.today()+1), 'no_employee_profile');
select tt.as(:'u_o');
select tt.chk('T2 the owner (the approver by default) got an in-app note', tt.nnote(:'u_o')=1);
select tt.as(:'u_hr');
select (pay_request_submit('salary', 1500, 'test: entered for a colleague without a phone', tt.today()+1, :'e2'::uuid, gen_random_uuid()) ->> 'id')::bigint as q2 \gset
select tt.chk('T2 a payroll manager can enter a request on behalf of a colleague (flagged on_behalf)', (select on_behalf and employee_id=:'e2' and requested_by=:'u_hr' from pay_requests where id=:'q2'));
select tt.as(:'u_s2');
select tt.chk('T2 the colleague sees it as his own (linked through his employee record)', (select count(*) from jsonb_array_elements(pay_request_list('mine') -> 'rows') x where (x ->> 'id')::bigint=:'q2' and (x ->> 'mine')='true')=1);

\echo -- limits (both blank = no limit; each is a setting)
select tt.as(:'u_o');
select set_rule('pay_request_max_per_month','2') is null as m1 \gset
select tt.as(:'u_s1');
select (pay_request_submit('advance', 500, 'test second', tt.today()+4, null, gen_random_uuid()) ->> 'id')::bigint as q3 \gset
select tt.err('T2 the third request in the month is refused when the limit is 2', format($$select pay_request_submit('advance', 500, 'test third', %L::date)$$, tt.today()+4), 'monthly_request_limit');
select pay_request_cancel(:'q3'::bigint, 'test: changed my mind') ->> 'status' as c3 \gset
select tt.chk('T2 a cancelled request does not count against the limit', (pay_request_submit('advance', 500, 'test third again', tt.today()+4, null, gen_random_uuid()) ->> 'status')='received');
select tt.as(:'u_o');
select set_rule('pay_request_max_per_month', null) is null as m2 \gset
select set_rule('pay_request_advance_ceiling','4000') is null as c1 \gset
select tt.as(:'u_s1');
select tt.err('T2 an advance request that would pass the ceiling is refused (open requests 3500 + 600 > 4000)', format($$select pay_request_submit('advance', 600, 'test over', %L::date)$$, tt.today()+4), 'advance_ceiling');
select tt.chk('T2 one within the ceiling is accepted (3500 + 500 = 4000)', (pay_request_submit('advance', 500, 'test within', tt.today()+4, null, gen_random_uuid()) ->> 'status')='received');
select tt.as(:'u_o');
select set_rule('pay_request_advance_ceiling', null) is null as c2 \gset

\echo == T3 deciding: only the chosen person (the owner by default); the maker never decides; a different date is shown to the staff
select tt.as(:'u_s1');
select tt.err('T3 staff cannot decide his own request', format($$select pay_request_decide(%s, true)$$, :'q1'), 'approver_only');
select tt.as(:'u_s2');
select tt.err('T3 another staff member cannot decide it', format($$select pay_request_decide(%s, true)$$, :'q1'), 'approver_only');
select tt.as(:'u_ap');
select tt.err('T3 a person who is not the chosen approver cannot decide (the default approver is the owner)', format($$select pay_request_decide(%s, true)$$, :'q1'), 'approver_only');
select tt.as(:'u_o');
select tt.err('T3 a pay date in the past is refused', format($$select pay_request_decide(%s, true, %L::date)$$, :'q1', tt.today()-1), 'bad_date');
select tt.err('T3 an approved amount above the asked amount is refused', format($$select pay_request_decide(%s, true, null, 9999)$$, :'q1'), 'bad_amount');
select tt.err('T3 a rejection needs a reason', format($$select pay_request_decide(%s, false)$$, :'q1'), 'note_required');
select pay_request_decide(:'q1'::bigint, true, tt.today()+5, 2500, 'test: part now, the rest next week') ->> 'status' as d1 \gset
select tt.chk('T3 approved on ANOTHER date and for a smaller amount: date_changed, pay date and approved amount are stored', (select status='approved' and pay_date=tt.today()+5 and date_changed and approved_amount=2500 and needed_by=tt.today()+3 from pay_requests where id=:'q1'));
select tt.as(:'u_s1');
select tt.chk('T3 staff 1 sees: approved, the new pay date, the changed flag, the note and a timeline of two lines (received, approved)',
  (select x ->> 'status'='approved' and (x ->> 'pay_date')::date=tt.today()+5 and (x ->> 'date_changed')='true' and x ->> 'decision_note' like 'test: part%' and jsonb_array_length(x -> 'events')=2
     from jsonb_array_elements(pay_request_list('mine') -> 'rows') x where (x ->> 'id')::bigint=:'q1'));
select tt.chk('T3 staff 1 got a note about the decision', tt.nnote(:'u_s1')>=1);
select tt.as(:'u_o');
select pay_request_decide(:'q2'::bigint, true) ->> 'status' as d2 \gset
select tt.chk('T3 approved on the date asked: date_changed is false and the pay date is the needed-by date', (select pay_date=needed_by and not date_changed and approved_amount=1500 from pay_requests where id=:'q2'));
select pay_request_decide(:'q1'::bigint, true, tt.today()+1, 2500, 'test: moved earlier') ->> 'status' as d3 \gset
select tt.chk('T3 the date can be changed again before payment: one redated line in the timeline', tt.nev(:'q1',  'redated')=1 and (select pay_date=tt.today()+1 from pay_requests where id=:'q1'));
select (pay_request_submit('advance', 300, 'test to be rejected', tt.today()+2, :'e3'::uuid, gen_random_uuid()) ->> 'id')::bigint as q4 \gset
select pay_request_decide(:'q4'::bigint, false, null, null, 'test: not this month') ->> 'status' as d4 \gset
select tt.chk('T3 rejected with a reason; a decided request cannot be decided again', tt.st(:'q4')='rejected');
select tt.err('T3 a rejected request cannot be approved', format($$select pay_request_decide(%s, true)$$, :'q4'), 'request_not_pending');
select tt.as(:'u_s1');
select tt.err('T3 staff can cancel only while open: a cancelled request cannot be cancelled again', format($$select pay_request_cancel(%s, 'test again')$$, :'q3'), 'request_not_pending');
select tt.err('T3 another person cannot cancel it', format($$select pay_request_cancel(%s, 'test x')$$, :'q2'), 'not allowed');

\echo == T4 the approver is a setting: a role, a person, or the owner; the maker rule holds also for the chosen approver; direct setting changes are refused
select tt.as(:'u_o');
select tt.err('T4 the approver setting cannot be changed one key at a time from the browser', $$select set_rule('pay_request_approver_mode','"role"')$$, 'use pay_request_approver_set');
select tt.err('T4 a role that nobody holds is refused', $$select pay_request_approver_set('staff','role','recipe_approver')$$, 'no_one_holds_role');
select tt.err('T4 the owner role is not a valid approver role (the owner always can decide)', $$select pay_request_approver_set('staff','role','owner')$$, 'bad_role');
select tt.err('T4 an unknown person is refused', $$select pay_request_approver_set('staff','user',null,gen_random_uuid())$$, 'unknown_user');
select tt.err('T4 mode same is only for the supplier scope', $$select pay_request_approver_set('staff','same')$$, 'bad_value');
select tt.as(:'u_s1');
select tt.err('T4 a non-owner cannot set the approver', $$select pay_request_approver_set('staff','role','purchasing')$$, 'not allowed');
select tt.as(:'u_o');
select pay_request_approver_set('staff','role','purchasing',null,'test: purchasing decides') ->> 'mode' as a1 \gset
select (pay_request_submit('advance', 400, 'test for approver role', tt.today()+2, :'e3'::uuid, gen_random_uuid()) ->> 'id')::bigint as q5 \gset
select tt.as(:'u_ap');
select pay_request_decide(:'q5'::bigint, true, tt.today()+2) ->> 'status' as d5 \gset
select tt.chk('T4 role mode: the person holding the role decides (and the setting is in the audit log)', tt.st(:'q5')='approved' and tt.naud('pay_request_approver_set')>=1);
select tt.as(:'u_x');
select tt.err('T4 role mode: a person without the role still cannot', format($$select pay_request_decide(%s, true)$$, :'q1'), 'approver_only');
select tt.as(:'u_ap');
select (pay_request_submit('advance', 200, 'test: the approver asks for himself', tt.today()+2, null, gen_random_uuid()) ->> 'id')::bigint as q6 \gset
select tt.err('T4 the chosen approver cannot decide his OWN request', format($$select pay_request_decide(%s, true)$$, :'q6'), 'self_approval');
select tt.as(:'u_o');
select pay_request_decide(:'q6'::bigint, true, tt.today()+2) ->> 'status' as d6 \gset
select tt.chk('T4 the owner can always decide it instead', tt.st(:'q6')='approved');
select pay_request_approver_set('staff','user',null,:'u_sa'::uuid,'test: store person decides') ->> 'mode' as a2 \gset
select tt.as(:'u_ap');
select tt.err('T4 user mode: the former role holder can no longer decide', format($$select pay_request_decide(%s, true)$$, :'q1'), 'approver_only');
select tt.as(:'u_sa');
select tt.chk('T4 user mode: the named person is the approver', (pay_request_state() ->> 'approver_staff')='true' and (pay_request_counts() ->> 'due')::int>=0);
select tt.as(:'u_o');
select pay_request_approver_set('staff','owner') ->> 'mode' as a3 \gset
select pay_request_approver_set('party','role','storekeeper',null,'test: store decides supplier payments') ->> 'mode' as a4 \gset

\echo == T5 who sees what (row level security): staff only his own, the approver only the kinds assigned to him, others nothing
set role authenticated; select tt.as(:'u_s1');
select tt.chk('T5 staff 1 sees only his own requests (q1, q3, q7 ... all with his employee)', (select count(*) from pay_requests)>=3 and not exists (select 1 from pay_requests where employee_id is distinct from :'e1' and requested_by is distinct from :'u_s1'));
select tt.chk('T5 staff 1 does not see staff 2 requests or the supplier requests', not exists (select 1 from pay_requests where id=:'q2') and not exists (select 1 from pay_requests where kind='supplier'));
select tt.chk('T5 staff 1 sees only the events of his own requests', not exists (select 1 from pay_request_events where request_id=:'q2') and exists (select 1 from pay_request_events where request_id=:'q1'));
select tt.as(:'u_x');
select tt.chk('T5 a person with no request and no approver role sees nothing at all', (select count(*) from pay_requests)=0 and (select count(*) from pay_request_events)=0 and (select count(*) from pay_request_exceptions)=0);
select tt.chk('T5 and the list function agrees', jsonb_array_length(pay_request_list('all') -> 'rows')=0 and jsonb_array_length(pay_request_list('mine') -> 'rows')=0);
reset role; select tt.as(:'u_o'); set role authenticated;
select tt.chk('T5 the owner sees everything', (select count(*) from pay_requests)=(select tt.nreq()));
reset role;
select tt.err('T5 anon cannot read the table', $$set role anon; select count(*) from public.pay_requests$$, 'permission denied');
reset role;
set role authenticated; select tt.as(:'u_s1');
select tt.err('T5 a browser role cannot insert a request directly', format($$insert into public.pay_requests (kind, requested_by, employee_id, amount, reason, needed_by) values ('advance', %L, %L, 5, 'test', current_date)$$, :'u_s1', :'e1'), 'permission denied');
select tt.err('T5 a browser role cannot change an approved amount', format($$update public.pay_requests set approved_amount = 9000 where id=%s$$, :'q1'), 'permission denied');
select tt.err('T5 a browser role cannot delete', format($$delete from public.pay_requests where id=%s$$, :'q1'), 'permission denied');

\echo == T6 a supplier payment request: any staff raises it, the chosen approver decides, payment goes through pay_supplier
select tt.as(:'u_x');
select (pay_request_submit('supplier', 4000, 'test: supplier asked for money for the March bill', tt.today()+1, null, gen_random_uuid(), :'sup'::uuid, null, 'BILL-120', 'test supplier contact', 1) ->> 'id')::bigint as p1 \gset
select tt.chk('T6 a staff member without any money right raised a supplier payment request (bill reference and the supplier-side contact kept)', (select kind='supplier' and bill_ref='BILL-120' and asked_by_name='test supplier contact' and on_behalf and location_id=1 from pay_requests where id=:'p1'));
select tt.err('T6 more than the supplier balance is refused', format($$select pay_request_submit('supplier', 99999999, 'test x', %L::date, null, null, current_setting('tt.sup')::uuid, null, null, null, 1)$$, tt.today()+1), 'overpaid');
select tt.err('T6 an unknown supplier is refused', format($$select pay_request_submit('supplier', 100, 'test x', %L::date, null, null, gen_random_uuid(), null, null, null, 1)$$, tt.today()+1), 'supplier_not_found');
select tt.as(:'u_sa');
select tt.chk('T6 the store approver (party setting = role storekeeper) sees the supplier request and not the staff ones', (select count(*) from jsonb_array_elements(pay_request_list('inbox') -> 'rows') x where x ->> 'kind'='supplier')=1
  and (select count(*) from jsonb_array_elements(pay_request_list('all') -> 'rows') x where x ->> 'kind' <> 'supplier')=0);
select tt.as(:'u_ap');
select tt.chk('T6 the staff approver role (purchasing) is not the supplier approver once the party approver is a different role', (pay_request_state() ->> 'approver_party')='false' and (pay_request_state() ->> 'approver_staff')='false' and (pay_request_state() -> 'approver' -> 'party' ->> 'role')='storekeeper');
select tt.as(:'u_sa');
select pay_request_decide(:'p1'::bigint, true, tt.today()) ->> 'status' as pd1 \gset
select tt.chk('T6 supplier request approved on today', tt.st(:'p1')='approved');
select tt.err('T6 the approver without the supplier payment right cannot pay it (the existing function refuses)', format($$select pay_request_pay(%s, 'cash')$$, :'p1'), 'not allowed');
select tt.chk('T6 the refused payment left the request approved and wrote nothing', tt.st(:'p1')='approved' and (select count(*) from supplier_payments where supplier_id=:'sup')=1);
reset role; select tt.as(:'u_o'); set role authenticated;
select tt.err('T6 a mode or a money account is required', format($$select pay_request_pay(%s)$$, :'p1'), 'mode_required');
select pay_request_pay(:'p1'::bigint, null, :'maw'::bigint, 'ref-p1', 'test: paid by wallet') ->> 'status' as pp_p1 \gset
reset role;
select tt.chk('T6 paid through pay_supplier from the chosen mobile wallet account (mode mobile, money account set); the request is paid with the row reference',
  tt.st(:'p1')='paid' and exists (select 1 from supplier_payments where supplier_id=:'sup' and amount=4000 and mode='mobile' and money_account_id=:'maw') and (select paid_ref like 'supplier_payments:%' and paid_amount=4000 from pay_requests where id=:'p1'));
select acct_post_pending(false) ->> 'posted' as pp2 \gset
select tt.chk('T6 ledger: the wallet account fell by 4000, payables fell by 4000 more, every entry balances', tt.bal(:'maw')=50000-4000 and tt.unbalanced()=0);
select tt.as(:'u_o'); set role authenticated;
select tt.err('T6 a paid request cannot be paid twice', format($$select pay_request_pay(%s, 'cash')$$, :'p1'), 'request_not_approved');
reset role;

\echo == T7 paying staff requests through advance and salary functions with the payment source chosen at that moment
select tt.as(:'u_o'); set role authenticated;
select tt.err('T7 not before the pay date (q1 was moved to tomorrow)', format($$select pay_request_pay(%s, 'cash')$$, :'q1'), 'not_due_yet');
select tt.err('T7 an unapproved request cannot be paid', format($$select pay_request_pay(%s, 'cash')$$, :'q4'), 'request_not_approved');
select pay_request_decide(:'q1'::bigint, true, tt.today(), 2500, 'test: now') ->> 'status' as d7 \gset
select pay_request_pay(:'q1'::bigint, null, :'mab'::bigint, null, 'test advance', 800, tt.today()) ->> 'status' as pp_q1 \gset
reset role;
select tt.chk('T7 advance paid through staff_advance_add from the BANK account: amount = approved 2500, mode bank, instalment kept, request paid',
  tt.st(:'q1')='paid' and exists (select 1 from employee_advances where employee_id=:'e1' and amount=2500 and mode='bank' and money_account_id=:'mab' and instalment=800 and note like '%Pay request #%'));
select acct_post_pending(false) ->> 'posted' as pp3 \gset
select tt.chk('T7 ledger: the bank account fell by 2500 and every entry balances', tt.bal(:'mab')=50000-2500 and tt.unbalanced()=0);
select tt.as(:'u_o');
select pay_request_decide(:'q2'::bigint, true, tt.today(), 1500) ->> 'status' as d8 \gset
set role authenticated;
select pay_request_pay(:'q2'::bigint, 'cash', :'mac'::bigint, null, 'test salary part') ->> 'status' as pp_q2 \gset
reset role;
select tt.chk('T7 salary request paid through payroll_pay (one line, 1500 of 6000): payment row from the cash drawer, line is partly paid, request is paid',
  tt.st(:'q2')='paid' and exists (select 1 from payroll_payments where line_id=:'l2' and amount=1500 and money_account_id=:'mac' and mode='cash') and (select payment_status='partly' and paid_amount=1500 from payroll_lines where id=:'l2'));
select acct_post_pending(false) ->> 'posted' as pp4 \gset
select tt.chk('T7 ledger: every entry still balances after the salary payment', tt.unbalanced()=0 and tt.bal(:'mac')=50000-700-500-900-1500);
select tt.as(:'u_hr');
select (pay_request_submit('salary', 9000, 'test: more than the net', tt.today(), :'e1'::uuid, gen_random_uuid()) ->> 'id')::bigint as q8 \gset
select tt.as(:'u_o');
select pay_request_decide(:'q8'::bigint, true, tt.today()) ->> 'status' as d9 \gset
set role authenticated;
select tt.err('T7 a salary request above what is due is refused by payroll_pay and the request stays approved', format($$select pay_request_pay(%s, 'cash')$$, :'q8'), 'more_than_due');
reset role;
select tt.chk('T7 nothing was written by the refused payment', tt.st(:'q8')='approved' and (select count(*) from payroll_payments where line_id=:'l1')=0);
select tt.as(:'u_hr');
select (pay_request_submit('salary', 100, 'test: no payroll for this person', tt.today(), :'e3'::uuid, gen_random_uuid()) ->> 'id')::bigint as q9 \gset
select tt.as(:'u_o');
select pay_request_decide(:'q9'::bigint, true, tt.today()) ->> 'status' as d10 \gset
set role authenticated;
select tt.err('T7 a salary request for a person with no approved payroll line says so', format($$select pay_request_pay(%s, 'cash')$$, :'q9'), 'no_payroll_due');
reset role;
select tt.as(:'u_o'); set role authenticated;
select (pay_request_submit('advance', 120, 'test: owner own request', tt.today(), null, gen_random_uuid()) ->> 'id')::bigint as q10 \gset
select tt.chk('T7 the owner (linked to an employee record) may decide his own request only because owner_self_approve is on (project default)', pay_request_decide(:'q10'::bigint, true, tt.today()) ->> 'status'='approved');
reset role;
select tt.as(:'u_hr');
select tt.err('T7 the person who entered a request on behalf cannot pay it (not the approver)', format($$select pay_request_pay(%s, 'cash')$$, :'q8'), 'approver_only');

\echo == T8 the policy "required" is ON: salary and advance only against an approved request
select tt.as(:'u_o'); set role authenticated;
select set_rule('pay_requests_required','true') is null as pr1 \gset
select set_rule('party_requests_required','true') is null as pr2 \gset
reset role;
select count(*) as adv_before from employee_advances \gset
select count(*) as pay_before from payroll_payments \gset
select count(*) as sp_before from supplier_payments \gset
set role authenticated; select tt.as(:'u_o');
select tt.err('T8 a direct advance without a request is refused', format($$select staff_advance_add(%L::uuid, current_date, 1000, null, 'cash', current_date, 'test direct', gen_random_uuid())$$, :'e2'), 'pay_request_required');
select tt.err('T8 a direct salary payment without a request is refused', format($$select payroll_pay(%s, array[%s], 'cash', current_date, 'x', null, gen_random_uuid(), 100)$$, :'run1', :'l5'), 'pay_request_required');
select tt.err('T8 a direct supplier payment without a request is refused', format($$select pay_supplier(%L::uuid, 1, '[{"mode":"cash","amount":100}]'::jsonb, gen_random_uuid(), 'test')$$, :'sup'), 'pay_request_required');
select staff_advance_add(:'e2'::uuid, tt.today(), 100, null, 'none', tt.today(), 'test paper register', gen_random_uuid()) is not null as paper \gset
select tt.chk('T8 a paper-register advance (mode none, no money moves) is not gated', exists (select 1 from employee_advances where employee_id=:'e2' and amount=100 and mode='none'));
reset role;
select tt.chk('T8 the refused calls wrote nothing', (select count(*) from payroll_payments)=:'pay_before'::bigint and (select count(*) from supplier_payments)=:'sp_before'::bigint and (select count(*) from employee_advances)=:'adv_before'::bigint+1);
-- an approved request, due, big enough: the OLD call is accepted and the request is linked
select tt.as(:'u_s2'); set role authenticated;
select (pay_request_submit('advance', 1500, 'test: for the policy test', tt.today(), null, gen_random_uuid()) ->> 'id')::bigint as r1 \gset
reset role; select tt.as(:'u_o'); set role authenticated;
select pay_request_decide(:'r1'::bigint, true, tt.today()) ->> 'status' as dr1 \gset
select tt.err('T8 the request is for 1500, a bigger direct advance is still refused', format($$select staff_advance_add(%L::uuid, current_date, 2000, null, 'cash', current_date, 'test direct', gen_random_uuid())$$, :'e2'), 'pay_request_required');
select tt.err('T8 a direct advance for ANOTHER person is refused (the request belongs to staff 2)', format($$select staff_advance_add(%L::uuid, current_date, 1500, null, 'cash', current_date, 'test direct', gen_random_uuid())$$, :'e3'), 'pay_request_required');
select staff_advance_add(:'e2'::uuid, tt.today(), 1500, null, 'cash', tt.today(), 'ma#' || :'mac' || ';test the old screen', gen_random_uuid()) is not null as old1 \gset
reset role;
select tt.chk('T8 the old advance call now passes and links the approved request (paid, row reference, timeline line)', tt.st(:'r1')='paid' and (select paid_ref like 'employee_advances:%' from pay_requests where id=:'r1') and tt.nev(:'r1','paid')=1);
set role authenticated; select tt.as(:'u_o');
select tt.err('T8 the same request cannot back a second payment', format($$select staff_advance_add(%L::uuid, current_date, 1500, null, 'cash', current_date, 'test again', gen_random_uuid())$$, :'e2'), 'pay_request_required');
-- not yet due
select tt.as(:'u_s2'); reset role; select tt.as(:'u_s2'); set role authenticated;
select (pay_request_submit('advance', 400, 'test: later', tt.today()+9, null, gen_random_uuid()) ->> 'id')::bigint as r2 \gset
reset role; select tt.as(:'u_o'); set role authenticated;
select pay_request_decide(:'r2'::bigint, true) ->> 'status' as dr2 \gset
select tt.err('T8 an approved request whose pay date is still ahead does not back a payment', format($$select staff_advance_add(%L::uuid, current_date, 400, null, 'cash', current_date, 'test early', gen_random_uuid())$$, :'e2'), 'pay_request_required');
-- kinds: advance only
select set_rule('pay_requests_required_kinds','"advance"') is null as k1 \gset
select payroll_pay(:'run1'::bigint, array[:'l5'::bigint], 'cash', tt.today(), 'ma#' || :'mac' || ';t8-sal', null, gen_random_uuid(), 200) is not null as k1p \gset
select tt.chk('T8 required kinds = advance: a salary payment needs no request again', exists (select 1 from payroll_payments where line_id=:'l5' and amount=200));
select set_rule('pay_requests_required_kinds','"salary"') is null as k2 \gset
select staff_advance_add(:'e3'::uuid, tt.today(), 250, null, 'cash', tt.today(), 'ma#' || :'mac' || ';t8 advance free', gen_random_uuid()) is not null as k2p \gset
select tt.err('T8 required kinds = salary: a salary payment is refused again', format($$select payroll_pay(%s, array[%s], 'cash', current_date, 'x', null, gen_random_uuid(), 100)$$, :'run1', :'l5'), 'pay_request_required');
select set_rule('pay_requests_required_kinds','"both"') is null as k3 \gset

\echo == T9 the exception: a payment without a request, with a reason, logged to the Exceptions list
select tt.chk('T9 no exception row yet', tt.nexc('r1_unbacked_payment')=0);
select tt.err('T9 opening an exception needs a reason', format($$select pay_request_exception_open('advance', %L::uuid, 800, 'x')$$, :'e2'), 'reason_required');
select pay_request_exception_open('advance', :'e2'::uuid, 800, 'test: staff has no phone and asked at the counter') ->> 'id' as x1 \gset
select staff_advance_add(:'e2'::uuid, tt.today(), 800, null, 'cash', tt.today(), 'ma#' || :'mac' || ';test unbacked', gen_random_uuid()) is not null as x1p \gset
reset role;
select tt.chk('T9 the payment went through and the Exceptions list got one r1_unbacked_payment line with the reason and the amount',
  tt.nexc('r1_unbacked_payment')=1 and (select reason like '%no phone%' and amount=800 and event_type='r1_pay_advance' and src_table='employee_advances' from money_exceptions where kind='r1_unbacked_payment') and tt.naud('pay_request_exception_used')=1);
set role authenticated; select tt.as(:'u_o');
select tt.err('T9 the exception is used up after one payment', format($$select staff_advance_add(%L::uuid, current_date, 800, null, 'cash', current_date, 'test twice', gen_random_uuid())$$, :'e2'), 'pay_request_required');
select pay_request_exception_open('advance', :'e2'::uuid, 500, 'test: smaller than the payment') ->> 'id' as x2 \gset
select tt.err('T9 an exception for 500 does not cover a payment of 900', format($$select staff_advance_add(%L::uuid, current_date, 900, null, 'cash', current_date, 'test big', gen_random_uuid())$$, :'e2'), 'pay_request_required');
select tt.err('T9 an exception for staff 2 does not cover a payment to staff 3', format($$select staff_advance_add(%L::uuid, current_date, 400, null, 'cash', current_date, 'test other', gen_random_uuid())$$, :'e3'), 'pay_request_required');
reset role; update pay_request_exceptions set expires_at = now() - interval '1 minute';
set role authenticated; select tt.as(:'u_o');
select tt.err('T9 an expired exception is refused', format($$select staff_advance_add(%L::uuid, current_date, 400, null, 'cash', current_date, 'test late', gen_random_uuid())$$, :'e2'), 'pay_request_required');
select pay_request_exception_open('salary', :'e5'::uuid, 300, 'test: salary exception') ->> 'id' as x3 \gset
select payroll_pay(:'run1'::bigint, array[:'l5'::bigint], 'cash', tt.today(), 'ma#' || :'mac' || ';t9-sal', null, gen_random_uuid(), 300) is not null as x3p \gset
select pay_request_exception_open('supplier', :'sup'::uuid, 120, 'test: supplier exception') ->> 'id' as x4 \gset
select pay_supplier(:'sup'::uuid, 1, jsonb_build_array(jsonb_build_object('mode','cash','amount',120,'wallet','ma#' || :'mac' || ';')), gen_random_uuid(), 'test t9') is not null as x4p \gset
reset role;
select tt.chk('T9 salary and supplier exceptions work the same way and each is logged', tt.nexc('r1_unbacked_payment')=3);
-- the owner's one-off override of phase 87 also works (event r1_pay_advance)
select tt.as(:'u_o'); set role authenticated;
select money_exception_grant('override', 'test: owner override', :'u_o'::uuid, null, 'r1_pay_advance') is not null as g1 \gset
select staff_advance_add(:'e3'::uuid, tt.today(), 90, null, 'cash', tt.today(), 'ma#' || :'mac' || ';t9 grant', gen_random_uuid()) is not null as g1p \gset
reset role;
select tt.chk('T9 the phase 87 one-off override also lets one payment through and is logged as override_exception', tt.nexc('override_exception')>=1 and exists (select 1 from employee_advances where employee_id=:'e3' and amount=90));
-- who may open an exception is a setting
select tt.as(:'u_hr'); set role authenticated;
select tt.chk('T9 mode reason: a payroll manager may open one', pay_request_exception_open('advance', :'e2'::uuid, 50, 'test: hr reason') is not null);
reset role; select tt.as(:'u_o'); set role authenticated;
select set_rule('pay_request_exception_mode','"owner"') is null as em1 \gset
select tt.as(:'u_hr');
select tt.err('T9 mode owner: a payroll manager cannot open one', format($$select pay_request_exception_open('advance', %L::uuid, 50, 'test: hr reason 2')$$, :'e2'), 'owner_only');
select tt.as(:'u_o');
select tt.chk('T9 mode owner: the owner can', pay_request_exception_open('advance', :'e2'::uuid, 50, 'test: owner reason') is not null);
select set_rule('pay_request_exception_mode','"never"') is null as em2 \gset
select tt.err('T9 mode never: nobody can', format($$select pay_request_exception_open('advance', %L::uuid, 50, 'test: never')$$, :'e2'), 'exceptions_off');
select set_rule('pay_request_exception_mode','"reason"') is null as em3 \gset
-- paying a request with the policy on
select tt.as(:'u_s1'); reset role; select tt.as(:'u_s1'); set role authenticated;
select (pay_request_submit('advance', 600, 'test: policy on, paid from the due list', tt.today(), null, gen_random_uuid()) ->> 'id')::bigint as r3 \gset
select tt.as(:'u_o');
select pay_request_decide(:'r3'::bigint, true, tt.today()) ->> 'status' as dr3 \gset
select tt.chk('T9 the due list shows it for the approver', (select count(*) from jsonb_array_elements(pay_request_list('due') -> 'rows') x where (x ->> 'id')::bigint=:'r3' and (x ->> 'can_pay')='true')=1 and (pay_request_counts() ->> 'due')::int>=1);
select pay_request_pay(:'r3'::bigint, 'mobile') ->> 'status' as pr3 \gset
reset role;
select tt.chk('T9 paid from the due list with the policy on (explicit link, no exception needed)', tt.st(:'r3')='paid' and exists (select 1 from employee_advances where employee_id=:'e1' and amount=600 and mode='mobile'));
select tt.chk('T9 the explicit pay path wrote no extra exception line', tt.nexc('r1_unbacked_payment')=3);
-- the system (no logged-in user) is never gated: a backup or migration insert
select set_config('request.jwt.claim.sub','',false);
insert into employee_advances (employee_id, location_id, adv_date, amount, recover_from, mode, note) values (:'e3', 1, tt.today(), 11, tt.today(), 'cash', 'test system insert');
select tt.chk('T9 an insert with no logged-in person (system) is not gated', exists (select 1 from employee_advances where note='test system insert'));
select tt.as(:'u_o');

\echo == T10 ledger, counts, notifications, paste twice, policy back to off
select acct_post_pending(false) ->> 'posted' as pp5 \gset
select tt.chk('T10 after all payments every journal entry balances (Dr = Cr)', tt.unbalanced()=0);
select tt.chk('T10 the money accounts moved only by what was paid (bank 2500; wallet 4000)', tt.bal(:'mab')=50000-2500 and tt.bal(:'maw')=50000-4000);
select tt.chk('T10 requests paid = amounts linked: the sum of paid_amount on paid requests equals the rows they point to', (select coalesce(sum(paid_amount),0) from pay_requests where status='paid')=4000+2500+1500+1500+600);
select tt.chk('T10 the timeline of a paid request: received, approved, paid', (select string_agg(action, ',' order by id) from pay_request_events where request_id=:'r1')='received,approved,paid');
select tt.chk('T10 the requester was told (note count for staff 1 and 2 grew)', tt.nnote(:'u_s1')>=3 and tt.nnote(:'u_s2')>=2);
select tt.chk('T10 the state function returns the settings and the gate flags', (pay_request_state() ->> 'staff_required')='true' and (pay_request_state() ->> 'party_required')='true' and (pay_request_state() -> 'gate' ->> 'supplier')='true');
select count(*) as n_rules_before from rules where key like 'pay_request%' or key like 'party_request%' \gset
select count(*) as n_req_before from pay_requests \gset
select set_rule('pay_requests_required','false') is null as off1 \gset
select set_rule('party_requests_required','false') is null as off2 \gset
select set_rule('pay_requests_on','false') is null as off3 \gset
select tt.as(:'u_o');
select staff_advance_add(:'e3'::uuid, tt.today(), 33, null, 'cash', tt.today(), 'ma#' || :'mac' || ';t10 back to today', gen_random_uuid()) is not null as back1 \gset
select tt.chk('T10 policy switched off again: a direct advance works with no request, as in T1', exists (select 1 from employee_advances where employee_id=:'e3' and amount=33));
select tt.chk('T10 switch off: old requests stay readable, new ones are refused', tt.nreq()=:'n_req_before'::bigint);
select tt.err('T10 a new request is refused again', format($$select pay_request_submit('advance', 100, 'test x', %L::date)$$, tt.today()+1), 'requests_off');
\echo == T11 paste twice keeps settings, rows and the trigger count
\i supabase/phase120.sql
select tt.chk('T11 second paste of phase120: rules, requests and the three triggers are unchanged', (select count(*) from rules where key like 'pay_request%' or key like 'party_request%')=:'n_rules_before'::bigint and tt.nreq()=:'n_req_before'::bigint
  and (select count(*) from pg_trigger where tgname='a0_r1_gate_bi')=3 and rule_txt('pay_requests_required_kinds')='both' and not rule_on('pay_requests_on'));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
