-- FRESH DB ONLY. Phase 94 tests (cash and payment controls: owner money, bank slip, supplier payment guard, duplicate vendor, one pay account per employee, approver logic, exceptions).
--   ORDER="phase8 ... phase87 phase94" bash tests/sql/build_fresh_db.sh a94db        (any port; this run used 5565)
--   psql -h /tmp -p 5565 -U postgres -d a94db -qAt -f supabase/phase94_test.sql | grep -E 'FAIL|RESULT'
-- The pay_supplier and cash_move_add hooks of docs/integration/W1-E.md are applied INSIDE this test (section T4 and T9) on the scratch database and the original
-- function bodies are restored at the end of the file: the shared functions are left exactly as the build made them.
-- Test data only (test_* names).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000094'
\set u_cash '00000000-0000-0000-0000-000000000194'
\set u_pay '00000000-0000-0000-0000-000000000294'
\set u_rl '00000000-0000-0000-0000-000000000394'
\set u_nm '00000000-0000-0000-0000-000000000494'
\set u_x '00000000-0000-0000-0000-000000000594'
\set u_acc '00000000-0000-0000-0000-000000000694'
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
create or replace function tt.exc(p_kind text) returns bigint language sql stable security definer as $$ select count(*) from public.money_exceptions where kind = p_kind $$;
create or replace function tt.req(p_kind text, p_status text) returns bigint language sql stable security definer as $$ select count(*) from public.w1e_requests where kind = p_kind and status = p_status $$;
create or replace function tt.cm(p_ref text) returns bigint language sql stable security definer as $$ select count(*) from public.cash_moves where ref = p_ref $$;
create or replace function tt.qid(p_ref text) returns bigint language sql stable security definer as $$ select max(id) from public.w1e_requests where payload ->> 'ref' = p_ref $$;
create or replace function tt.qk(p_kind text) returns bigint language sql stable security definer as $$ select max(id) from public.w1e_requests where kind = p_kind and status = 'pending' $$;
create or replace function tt.sp(p_sup uuid) returns bigint language sql stable security definer as $$ select count(*) from public.supplier_payments where supplier_id = p_sup $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner94@s.app','{"full_name":"test_owner"}'), (:'u_cash','test_cash94@s.app','{"full_name":"test_cash"}'), (:'u_pay','test_pay94@s.app','{"full_name":"test_pay"}'),
 (:'u_rl','test_role94@s.app','{"full_name":"test_role"}'), (:'u_nm','test_named94@s.app','{"full_name":"test_named"}'), (:'u_x','test_other94@s.app','{"full_name":"test_other"}'),
 (:'u_acc','test_acct94@s.app','{"full_name":"test_acct"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_cash','salesperson'),(:'u_pay','salesperson'),(:'u_rl','purchasing'),(:'u_nm','salesperson'),(:'u_x','salesperson'),(:'u_acc','salesperson') on conflict do nothing;
insert into user_locations values (:'u_cash',1),(:'u_pay',1),(:'u_rl',1),(:'u_nm',1),(:'u_x',1),(:'u_acc',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_cash','cash_move',null),(:'u_pay','supplier_pay',null),(:'u_nm','cash_move',null),(:'u_nm','supplier_pay',null),
  (:'u_acc','accounts_manage',1),(:'u_acc','cash_move',null);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset

\echo == T0 shape, safe defaults, nothing replaced
select tt.chk('T0 phase94 present and the request table exists, no hard delete', to_regprocedure('public._p94_present()') is not null and to_regclass('public.w1e_requests') is not null);
select tt.chk('T0 ten settings exist in module books with the SAFE defaults (today): open, slip off, blanks, off, off, flag off',
  (select count(*) from rules where key in ('owner_money_entry_mode','bank_slip_required','bank_move_large_over','bank_move_backdate_days','supplier_pay_dup_mode','supplier_pay_dup_hours','supplier_pay_over','supplier_dup_mode','employee_pay_dup_mode','employee_pay_change_flag') and module='books')=10
  and rule_txt('owner_money_entry_mode')='open' and not rule_on('bank_slip_required') and rule_num('bank_move_large_over') is null and rule_num('bank_move_backdate_days') is null
  and rule_txt('supplier_pay_dup_mode')='off' and rule_num('supplier_pay_dup_hours') is null and rule_num('supplier_pay_over') is null and rule_txt('supplier_dup_mode')='off'
  and rule_txt('employee_pay_dup_mode')='off' and not rule_on('employee_pay_change_flag'));
select tt.chk('T0 every label is English and has a hint', not exists (select 1 from rules where key in ('owner_money_entry_mode','bank_slip_required','bank_move_large_over','bank_move_backdate_days','supplier_pay_dup_mode','supplier_pay_dup_hours','supplier_pay_over','supplier_dup_mode','employee_pay_dup_mode','employee_pay_change_flag')
   and (label_en !~ '^[ -~]+$' or coalesce(hint_en,'') = '' or label_bn <> label_en)));
select tt.chk('T0 the old exception kinds survive and the new ones are added', (select count(*) from pg_constraint where conrelid='money_exceptions'::regclass and conname='money_exceptions_kind_check'
   and pg_get_constraintdef(oid) like '%negative_warn%' and pg_get_constraintdef(oid) like '%recon_diff%' and pg_get_constraintdef(oid) like '%w1e_pay_account_changed%' and pg_get_constraintdef(oid) like '%w1e_journal_request%')=1);
select tt.chk('T0 the shared functions are untouched (no w1e marker in pay_supplier, cash_move_add, acct_journal_post)',
  position('w1e' in pg_get_functiondef('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure))=0 and position('w1e' in pg_get_functiondef('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure))=0
  and position('w1e' in pg_get_functiondef('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure))=0);
select tt.chk('T0 internals closed to browsers, API open', not has_function_privilege('authenticated','public._w1e_pay_gate(uuid,int,jsonb,uuid,text,numeric)','execute') and not has_function_privilege('authenticated','public._w1e_apply(public.w1e_requests)','execute')
  and not has_function_privilege('anon','public.w1e_state()','execute') and has_function_privilege('authenticated','public.w1e_request_decide(bigint,boolean,text)','execute'));
select tt.chk('T0 the request table cannot be read or written by a browser role', not has_table_privilege('authenticated','public.w1e_requests','select') and not has_table_privilege('authenticated','public.w1e_requests','insert') and not has_table_privilege('anon','public.w1e_requests','select'));
select tt.chk('T0 nine separation pairs now (2 old + 7 new) and every grant code exists', (select count(*) from grant_separation_pairs)=9
  and not exists (select 1 from grant_separation_pairs p where not exists (select 1 from grant_defs d where d.grant_code=p.entry_grant) or not exists (select 1 from grant_defs d where d.grant_code=p.approve_grant)));

select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset

\echo == T1 defaults keep today: a cashier records owner money, a bank move without slip, no flags, no holds
select tt.as(:'u_cash');
select cash_move_add(1,'owner_draw',100,tt.today(),'cash',null,'t1-draw',null,gen_random_uuid(),false) ->> 'id' as t1a \gset
select cash_move_add(1,'owner_topup',200,tt.today(),'cash',null,'t1-top',null,gen_random_uuid(),false) ->> 'id' as t1b \gset
select cash_move_add(1,'bank_deposit',300,tt.today() - 40,null,null,null,null,gen_random_uuid(),false) ->> 'id' as t1c \gset
select tt.chk('T1 open mode: both owner moves are saved as today, the bank deposit without a slip, 40 days back and 300 is saved', tt.cm('t1-draw')=1 and tt.cm('t1-top')=1 and (select count(*) from cash_moves where kind='bank_deposit' and ref is null)=1);
select tt.chk('T1 open mode leaves an audit line for each non-owner owner-money entry, no request, no exception row', (select count(*) from audit_log where action='w1e_owner_money_open')=2 and (select count(*) from w1e_requests)=0 and (select count(*) from money_exceptions where kind like 'w1e%')=0);

\echo == T2 owner_money_entry_mode = owner: only the owner; one-off exception with reason
select tt.as(:'u_o'); 
select set_rule('owner_money_entry_mode','"owner"') is null as m1 \gset
select tt.as(:'u_cash');
select tt.err('T2 a cashier cannot record an owner draw', $$select cash_move_add(1,'owner_draw',100,tt.today(),'cash',null,'t2-draw',null,gen_random_uuid(),false)$$, 'owner_money_owner_only');
select tt.err('T2 a cashier cannot record an owner top-up', $$select cash_move_add(1,'owner_topup',100,tt.today(),'cash',null,'t2-top',null,gen_random_uuid(),false)$$, 'owner_money_owner_only');
select tt.chk('T2 nothing was written by the refused requests', tt.cm('t2-draw')=0 and tt.cm('t2-top')=0);
select cash_move_add(1,'bank_withdraw',100,tt.today(),null,null,'t2-bw',null,gen_random_uuid(),false) is not null as bw \gset
select cash_move_add(1,'hub_receipt',100,tt.today(),null,null,'t2-hub',null,gen_random_uuid(),false) is not null as hr \gset
select tt.chk('T2 other kinds are not affected', tt.cm('t2-bw')=1 and tt.cm('t2-hub')=1);
select tt.as(:'u_o');
select cash_move_add(1,'owner_draw',100,tt.today(),'cash',null,'t2-own',null,gen_random_uuid(),false) is not null as ow \gset
select tt.chk('T2 the owner still records his own draw', tt.cm('t2-own')=1);
select tt.err('T2 an exception needs a reason', format($$select money_exception_grant('override', '', %L::uuid, null, 'w1e_owner_money')$$, :'u_cash'), 'reason_required');
select money_exception_grant('override','test: owner asked the cashier to enter it',:'u_cash'::uuid,null,'w1e_owner_money') ->> 'id' as gx1 \gset
select tt.as(:'u_cash');
select cash_move_add(1,'owner_draw',100,tt.today(),'cash',null,'t2-exc',null,gen_random_uuid(),false) is not null as ex1 \gset
select tt.chk('T2 the one-off exception lets exactly one entry through, with an Exceptions row and an audit line', tt.cm('t2-exc')=1 and (select count(*) from money_exceptions where kind='override_exception' and event_type='w1e_owner_money')=1
  and (select count(*) from audit_log where action='money_exception_used' and detail ->> 'rule'='override')>=1);
select tt.err('T2 the second entry is refused again (the exception was used up)', $$select cash_move_add(1,'owner_draw',100,tt.today(),'cash',null,'t2-exc2',null,gen_random_uuid(),false)$$, 'owner_money_owner_only');
select tt.as(:'u_x');
select tt.err('T2 a person without the cash right is refused as always', $$select cash_move_add(1,'owner_draw',100,tt.today(),'cash',null,'t2-x',null,gen_random_uuid(),false)$$, 'not allowed');

\echo == T3 owner_money_entry_mode = approval: the entry waits, nothing is posted; the approver chosen under phase87 decides
select tt.as(:'u_o');
select set_rule('owner_money_entry_mode','"approval"') is null as m2 \gset
select (select count(*) from journal_entries) as je0 \gset
select tt.as(:'u_cash');
select gen_random_uuid() as c3 \gset
select cash_move_add(1,'owner_draw',700,tt.today(),'cash',null,'t3-draw',null,:'c3'::uuid,false) as r3 \gset
select tt.chk('T3 the response is a normal answer but the row is NOT in cash_moves; one pending request holds it', tt.cm('t3-draw')=0 and tt.req('owner_money','pending')=1);
select cash_move_add(1,'owner_draw',700,tt.today(),'cash',null,'t3-draw',null,:'c3'::uuid,false) is not null as r3b \gset
select tt.chk('T3 the same client id sent again (offline retry) does not make a second request', tt.req('owner_money','pending')=1);
select cash_move_add(1,'owner_topup',900,tt.today(),'bank',null,'t3-top',null,gen_random_uuid(),false) is not null as r3c \gset
select tt.as(:'u_o');
select acct_post_pending(false) is not null as pp0 \gset
select tt.chk('T3 pending money is not in the day book and not in the journal', (select count(*) from journal_entries where source_type='cash_move' and source_id in (select id::text from cash_moves where ref like 't3-%'))=0
  and not exists (select 1 from _daybook_lines23(array[1], tt.today(), tt.today()) where ref like 't3-%'));
select tt.chk('T3 a yellow Exceptions row and an audit line exist for each request', tt.exc('w1e_owner_money_request')=2 and (select count(*) from audit_log where action='w1e_request_create')>=2);
select tt.qid('t3-draw') as q1 \gset
select tt.qid('t3-top') as q2 \gset
select tt.as(:'u_cash');
select tt.err('T3 the maker cannot decide his own request', format($$select w1e_request_decide(%s, true, null)$$, :'q1'), 'self_approval');
select tt.as(:'u_x');
select tt.err('T3 someone who is not the approver cannot decide it', format($$select w1e_request_decide(%s, true, null)$$, :'q1'), 'approver_only');
select tt.chk('T3 a person with no part in it does not even see it', jsonb_array_length(w1e_requests_list('pending',50) -> 'rows')=0);
select tt.as(:'u_cash');
select tt.chk('T3 the maker sees his own requests, cannot decide them', jsonb_array_length(w1e_requests_list('pending',50) -> 'rows')=2 and not exists (select 1 from jsonb_array_elements(w1e_requests_list('pending',50) -> 'rows') x where (x ->> 'can_decide')::boolean));
select tt.as(:'u_o');
select tt.err('T3 a rejection needs a note', format($$select w1e_request_decide(%s, false, null)$$, :'q2'), 'note_required');
select w1e_request_decide(:'q2'::bigint, false, 'test: not agreed') ->> 'status' as rj \gset
select tt.chk('T3 rejected: still not in cash_moves, status rejected', :'rj'='rejected' and tt.cm('t3-top')=0 and tt.req('owner_money','rejected')=1);
select tt.err('T3 a decided request cannot be decided again', format($$select w1e_request_decide(%s, true, null)$$, :'q2'), 'request_not_pending');
select w1e_request_decide(:'q1'::bigint, true, 'test ok') ->> 'status' as ap1 \gset
select tt.chk('T3 approved by the owner (mode self): the cash move now exists with the MAKER as created_by, same id, and the request keeps the note', :'ap1'='approved' and tt.cm('t3-draw')=1
  and (select created_by from cash_moves where ref='t3-draw')=:'u_cash'::uuid and (select applied_ref from w1e_requests where id=:'q1'::bigint) like 'cash_moves:%');
select acct_post_pending(false) is not null as pp1 \gset
select tt.chk('T3 it is posted like any cash move and the journal balances', (select count(*) from journal_entries where source_type='cash_move' and source_id=(select id::text from cash_moves where ref='t3-draw'))=1 and tt.unbalanced()=0);
select tt.chk('T3 the audit log has the decision line', exists (select 1 from audit_log where action='w1e_request_decide' and record_id=:'q1' and detail ->> 'approve'='true'));
-- cancel by the maker
select tt.as(:'u_cash');
select cash_move_add(1,'owner_draw',55,tt.today(),'cash',null,'t3-cancel',null,gen_random_uuid(),false) is not null as r3d \gset
select tt.qid('t3-cancel') as q3 \gset
select tt.err('T3 cancel needs a reason', format($$select w1e_request_cancel(%s, '')$$, :'q3'), 'note_required');
select w1e_request_cancel(:'q3'::bigint, 'test: entered by mistake') ->> 'status' as cn \gset
select tt.chk('T3 the maker can cancel his own pending request', :'cn'='cancelled');
select tt.as(:'u_x');
select tt.err('T3 a person without the cash right cannot even ask', $$select cash_move_add(1,'owner_draw',55,tt.today(),'cash',null,'t3-x',null,gen_random_uuid(),false)$$, 'not allowed');

\echo == T4 the approver is the one chosen under phase87: a role, named people, or one request's own approver; the owner needs a logged exception in named mode
select tt.as(:'u_o');
select owner_approval_mode_set2('named','purchasing',null,'test named role') ->> 'mode' as nm1 \gset
select tt.as(:'u_cash');
select cash_move_add(1,'owner_topup',420,tt.today(),'cash',null,'t4-a',null,gen_random_uuid(),false) is not null as r4a \gset
select tt.qid('t4-a') as q4 \gset
select tt.as(:'u_o');
select tt.err('T4 in named mode the owner is not the approver of owner money', format($$select w1e_request_decide(%s, true, null)$$, :'q4'), 'approver_only');
select tt.as(:'u_rl');
select tt.chk('T4 the role holder sees the request and can decide it', (select (x ->> 'can_decide')::boolean from jsonb_array_elements(w1e_requests_list('pending',50) -> 'rows') x where (x ->> 'id')::bigint=:'q4'));
select w1e_request_decide(:'q4'::bigint, true, 'test by role') ->> 'status' as ap4 \gset
select tt.chk('T4 approved by the role holder (the owner never named a person: nothing hard-coded)', :'ap4'='approved' and tt.cm('t4-a')=1);
-- named people only
select tt.as(:'u_o');
select owner_approval_mode_set2('named','-',array[:'u_nm'::uuid],'test named person') ->> 'mode' as nm2 \gset
select tt.as(:'u_cash');
select cash_move_add(1,'owner_draw',430,tt.today(),'cash',null,'t4-b',null,gen_random_uuid(),false) is not null as r4b \gset
select tt.qid('t4-b') as q5 \gset
select tt.as(:'u_rl');
select tt.err('T4 the role is no longer the approver when only a person is named', format($$select w1e_request_decide(%s, true, null)$$, :'q5'), 'approver_only');
select tt.as(:'u_nm');
select w1e_request_decide(:'q5'::bigint, true, 'test by person') ->> 'status' as ap5 \gset
select tt.chk('T4 the named person approves', :'ap5'='approved' and tt.cm('t4-b')=1);
-- maker equals approver (the maker is also one of the named people)
select tt.as(:'u_o');
select owner_approval_mode_set2('named','-',array[:'u_nm'::uuid, :'u_rl'::uuid],'test two named people') ->> 'mode' as nm2b \gset
select tt.as(:'u_nm');
select cash_move_add(1,'owner_draw',440,tt.today(),'cash',null,'t4-self',null,gen_random_uuid(),false) is not null as r4c \gset
select tt.qid('t4-self') as q6 \gset
select tt.err('T4 maker equals approver is refused even for the named approver', format($$select w1e_request_decide(%s, true, null)$$, :'q6'), 'self_approval');
-- the owner names ONE approver for ONE request
select tt.as(:'u_o');
select tt.err('T4 a reason is required to set a request approver', format($$select w1e_request_approver_set(%s, %L::uuid, null, 'x')$$, :'q6', :'u_x'), 'reason_required');
select tt.as(:'u_x');
select tt.err('T4 a non-owner cannot set a request approver', format($$select w1e_request_approver_set(%s, %L::uuid, null, 'test reason')$$, :'q6', :'u_x'), 'not allowed');
select tt.as(:'u_o');
select tt.err('T4 the maker cannot be the approver of his own request', format($$select w1e_request_approver_set(%s, %L::uuid, null, 'test reason')$$, :'q6', :'u_nm'), 'approver_is_maker');
select w1e_request_approver_set(:'q6'::bigint, :'u_x'::uuid, null, 'test: this one goes to the other person') ->> 'approver_user' as sa \gset
select tt.as(:'u_rl');
select tt.err('T4 once a request has its own approver the general approver is out', format($$select w1e_request_decide(%s, true, null)$$, :'q6'), 'approver_only');
select tt.as(:'u_x');
select w1e_request_decide(:'q6'::bigint, true, 'test by the chosen one') ->> 'status' as ap6 \gset
select tt.chk('T4 the chosen approver decides it', :'ap6'='approved' and tt.cm('t4-self')=1);
-- owner exception in named mode
select tt.as(:'u_cash');
select cash_move_add(1,'owner_draw',450,tt.today(),'cash',null,'t4-owner',null,gen_random_uuid(),false) is not null as r4d \gset
select tt.qid('t4-owner') as q7 \gset
select tt.as(:'u_o');
select money_exception_grant('approver','test: the named approver is away today',:'u_o'::uuid,null,'w1e_owner_money') ->> 'id' as gx2 \gset
select w1e_request_decide(:'q7'::bigint, true, 'test by owner exception') ->> 'status' as ap7 \gset
select tt.chk('T4 the owner can decide once, with a granted one-off approver exception: Exceptions row + audit line', :'ap7'='approved' and tt.cm('t4-owner')=1
  and (select count(*) from money_exceptions where kind='approver_exception' and event_type='w1e_owner_money')=1);
select owner_approval_mode_set2('self') ->> 'mode' as nm3 \gset
select tt.chk('T4 back to self: the owner decides again (recovery path of phase87)', rule_txt('owner_approval_mode')='self');

\echo == T5 bank slip, large and back-dated bank moves
select tt.as(:'u_o'); 
select set_rule('owner_money_entry_mode','"open"') is null as m3 \gset
select set_rule('bank_slip_required','true') is null as s1 \gset
select tt.as(:'u_cash');
select tt.err('T5 a bank deposit without a slip number is refused', $$select cash_move_add(1,'bank_deposit',500,tt.today(),null,null,null,null,gen_random_uuid(),false)$$, 'bank_slip_required');
select tt.err('T5 a blank slip number is refused', $$select cash_move_add(1,'bank_withdraw',500,tt.today(),null,null,'   ',null,gen_random_uuid(),false)$$, 'bank_slip_required');
select tt.err('T5 a payment-source tag alone is not a slip', $$select cash_move_add(1,'bank_deposit',500,tt.today(),null,null,'ma#1;',null,gen_random_uuid(),false)$$, 'bank_slip_required');
select cash_move_add(1,'bank_deposit',500,tt.today(),null,null,'SLIP-5001',null,gen_random_uuid(),false) is not null as sl1 \gset
select cash_move_add(1,'bank_withdraw',250,tt.today(),null,null,'SLIP-5002',null,gen_random_uuid(),false) is not null as sl2 \gset
select tt.chk('T5 with a slip number both are saved', tt.cm('SLIP-5001')=1 and tt.cm('SLIP-5002')=1);
select cash_move_add(1,'owner_topup',100,tt.today(),'cash',null,null,null,gen_random_uuid(),false) is not null as sl3 \gset
select tt.chk('T5 other kinds need no slip', (select count(*) from cash_moves where kind='owner_topup' and ref is null)=1);
select tt.as(:'u_o');
select tt.err('T5 the owner needs the slip too', $$select cash_move_add(1,'bank_deposit',500,tt.today(),null,null,null,null,gen_random_uuid(),false)$$, 'bank_slip_required');
select gen_random_uuid() as c5 \gset
select money_exception_grant('override','test: slip lost, bank confirmed by phone',null,:'c5'::uuid,'w1e_bank_slip') ->> 'id' as gx3 \gset
select cash_move_add(1,'bank_deposit',500,tt.today(),null,null,null,null,:'c5'::uuid,false) is not null as sl4 \gset
select tt.chk('T5 a one-off exception for that entry (client id) lets it through, with Exceptions row', (select count(*) from cash_moves where client_id=:'c5'::uuid)=1 and (select count(*) from money_exceptions where kind='override_exception' and event_type='w1e_bank_slip')=1);
select set_rule('bank_slip_required','false') is null as s2 \gset
select cash_move_add(1,'bank_deposit',510,tt.today(),null,null,null,null,gen_random_uuid(),false) is not null as sl5 \gset
select tt.chk('T5 switched off: no slip needed again (old behaviour)', (select count(*) from cash_moves where kind='bank_deposit' and amount=510)=1);
select set_rule('bank_move_large_over','1000') is null as l1 \gset
select set_rule('bank_move_backdate_days','3') is null as l2 \gset
select (select count(*) from money_exceptions where kind='w1e_bank_move_flag') as f0 \gset
select cash_move_add(1,'bank_deposit',1500,tt.today(),null,null,'t5-big',null,gen_random_uuid(),false) is not null as lg1 \gset
select cash_move_add(1,'bank_withdraw',200,tt.today() - 5,null,null,'t5-old',null,gen_random_uuid(),false) is not null as lg2 \gset
select cash_move_add(1,'bank_deposit',200,tt.today() - 2,null,null,'t5-ok',null,gen_random_uuid(),false) is not null as lg3 \gset
select tt.chk('T5 a large one and a back-dated one are saved AND flagged (2 yellow rows); a small recent one is not', tt.cm('t5-big')=1 and tt.cm('t5-old')=1 and tt.cm('t5-ok')=1
  and (select count(*) from money_exceptions where kind='w1e_bank_move_flag')=:'f0'::int+2 and exists (select 1 from money_exceptions where event_type='w1e_bank_large' and amount=1500) and exists (select 1 from money_exceptions where event_type='w1e_bank_backdated' and amount=200));
select set_rule('bank_move_large_over',null) is null as l3 \gset
select set_rule('bank_move_backdate_days',null) is null as l4 \gset
select cash_move_add(1,'bank_deposit',99999,tt.today() - 60,null,null,'t5-blank',null,gen_random_uuid(),false) is not null as lg4 \gset
select tt.chk('T5 blank limits = off: no new flag', (select count(*) from money_exceptions where kind='w1e_bank_move_flag')=:'f0'::int+2);

\echo == T6 supplier payment guard (the pay_supplier hook of docs/integration/W1-E.md is applied here, on this scratch database)
insert into suppliers (name, opening_balance) values ('test_supplier_w1e', 500000) returning id as sup \gset
select set_config('w1e.orig_pay', pg_get_functiondef('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure), false) is not null as sv1 \gset
select tt.as(:'u_pay'); 
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 't6-first') ->> 'paid' as p0 \gset
select tt.chk('T6 BEFORE the hook is installed nothing changes (settings are off anyway): paid 1000', :'p0'::numeric=1000);
select _m_patch('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure, array[
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid;$h$,
 $h$declare pay jsonb; pm text; amt numeric; tot numeric := 0; bal numeric; sid text; dupby uuid; gate jsonb; /* bos87 w1e94 */$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
$h$,
 $h$  if tot > bal then raise exception 'overpaid'; end if;
  gate := public._w1e_pay_gate(p_supplier, p_loc, p_payments, p_client, p_note, tot);
  if gate is not null then return gate; end if;
$h$]) as hooked \gset
select tt.chk('T6 the hook text patches pay_supplier exactly once (second call is a no-op)', :'hooked'='t' and not _m_patch('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure, array['x','y']) and position('w1e94' in pg_get_functiondef('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure))>0);
select tt.as(:'u_pay'); 
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 't6-defaults') ->> 'paid' as p1 \gset
select tt.chk('T6 hook installed, all settings at default: the same payment again is simply paid (today)', :'p1'::numeric=1000 and (select count(*) from supplier_payments where supplier_id=:'sup'::uuid)=2);
select tt.as(:'u_o'); 
select set_rule('supplier_pay_dup_mode','"flag"') is null as d1 \gset
select tt.as(:'u_pay');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 't6-flag') ->> 'paid' as p2 \gset
select tt.chk('T6 flag mode: the repeat is paid AND a yellow duplicate_payment line is written', :'p2'::numeric=1000 and tt.exc('w1e_duplicate_payment')=1);
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":777}]'::jsonb, gen_random_uuid(), 't6-other') ->> 'paid' as p3 \gset
select tt.chk('T6 a different total is not a repeat', tt.exc('w1e_duplicate_payment')=1);
select tt.as(:'u_o');
select set_rule('supplier_pay_dup_mode','"block"') is null as d2 \gset
select tt.as(:'u_pay');
select tt.err('T6 block mode: the same supplier and total again is refused', format($$select pay_supplier(%L::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 't6-block')$$, :'sup'), 'duplicate_payment');
select tt.err('T6 block mode: a split of the same total (600 + 400) is the same payment', format($$select pay_supplier(%L::uuid, 1, '[{"mode":"cash","amount":600},{"mode":"mobile","amount":400,"wallet":"bkash"}]'::jsonb, gen_random_uuid(), 't6-split')$$, :'sup'), 'duplicate_payment');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":1001}]'::jsonb, gen_random_uuid(), 't6-1001') ->> 'paid' as p4 \gset
select tt.chk('T6 a different total passes in block mode', :'p4'::numeric=1001);
select gen_random_uuid() as c6 \gset
select tt.as(:'u_o');
select money_exception_grant('override','test: two real invoices of the same amount',null,:'c6'::uuid,'w1e_dup_payment') ->> 'id' as gx4 \gset
select tt.as(:'u_pay');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, :'c6'::uuid, 't6-exc') ->> 'paid' as p5 \gset
select tt.chk('T6 one-off exception (reason, this entry) lets the repeat through; Exceptions row exists', :'p5'::numeric=1000 and (select count(*) from money_exceptions where kind='override_exception' and event_type='w1e_dup_payment')=1);
-- the window
update supplier_payments set paid_at = now() - interval '3 hours' where supplier_id=:'sup'::uuid;
select tt.as(:'u_o'); 
select set_rule('supplier_pay_dup_hours','1') is null as w1 \gset
select tt.as(:'u_pay');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 't6-win') ->> 'paid' as p6 \gset
select tt.chk('T6 window 1 hour: payments three hours old are outside the window, so no block', :'p6'::numeric=1000);
update supplier_payments set paid_at = now() - interval '2 days' where supplier_id=:'sup'::uuid and note <> 't6-win';
select tt.as(:'u_o'); 
select set_rule('supplier_pay_dup_hours',null) is null as w2 \gset
select tt.as(:'u_pay');
select tt.err('T6 blank window = same calendar day: today''s 1000 (t6-win) blocks a new 1000', format($$select pay_supplier(%L::uuid, 1, '[{"mode":"cash","amount":1000}]'::jsonb, gen_random_uuid(), 't6-day')$$, :'sup'), 'duplicate_payment');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":888}]'::jsonb, gen_random_uuid(), 't6-888') ->> 'paid' as p6b \gset
select tt.chk('T6 payments from 2 days ago are not a repeat of 888', :'p6b'::numeric=888);
select tt.as(:'u_o');
select set_rule('supplier_pay_dup_mode','"off"') is null as d3 \gset

\echo -- T6b supplier_pay_over: a non-owner payment above the amount waits for the approver
select set_rule('supplier_pay_over','5000') is null as o1 \gset
select tt.as(:'u_pay');
select (select count(*) from supplier_payments where supplier_id=:'sup'::uuid) as np0, _sup_balance(:'sup'::uuid) as bal0 \gset
select gen_random_uuid() as c7 \gset
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":4000},{"mode":"bank","amount":2000}]'::jsonb, :'c7'::uuid, 't6-over') ->> 'pending' as pend \gset
select tt.chk('T6b 6000 (split over two modes) is above 5000: nothing is paid, one pending request, the balance is unchanged', :'pend'='true' and (select count(*) from supplier_payments where supplier_id=:'sup'::uuid)=:'np0'::int
  and _sup_balance(:'sup'::uuid)=:'bal0'::numeric and tt.req('supplier_pay','pending')=1);
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":4000},{"mode":"bank","amount":2000}]'::jsonb, :'c7'::uuid, 't6-over') ->> 'pending' as pend2 \gset
select tt.chk('T6b the same client id sent again returns the same pending request', :'pend2'='true' and tt.req('supplier_pay','pending')=1);
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":4999}]'::jsonb, gen_random_uuid(), 't6-under') ->> 'paid' as p7 \gset
select tt.chk('T6b below the limit is paid at once', :'p7'::numeric=4999);
select tt.as(:'u_o');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":6001}]'::jsonb, gen_random_uuid(), 't6-owner') ->> 'paid' as p8 \gset
select tt.chk('T6b the owner is not held', :'p8'::numeric=6001);
select tt.qk('supplier_pay') as q8 \gset
select tt.as(:'u_pay');
select tt.err('T6b the maker cannot approve', format($$select w1e_request_decide(%s, true, null)$$, :'q8'), 'self_approval');
select tt.as(:'u_o');
select w1e_request_decide(:'q8'::bigint, true, 'test ok') ->> 'status' as ap8 \gset
select tt.chk('T6b approved: both payment rows exist, made by the maker, same client id, balance down by 6000', :'ap8'='approved' and (select count(*) from supplier_payments where client_id=:'c7'::uuid)=2
  and (select created_by from supplier_payments where client_id=:'c7'::uuid limit 1)=:'u_pay'::uuid and (select sum(amount) from supplier_payments where client_id=:'c7'::uuid)=6000);
select acct_post_pending(false) is not null as pp2 \gset
select tt.chk('T6b the journal still balances after the posting of the approved payments', tt.unbalanced()=0);
-- overpaid at approval time
select tt.as(:'u_pay');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":9000}]'::jsonb, gen_random_uuid(), 't6-late') ->> 'pending' as pend3 \gset
select tt.qk('supplier_pay') as q9 \gset
update suppliers set opening_balance = 0 where id=:'sup'::uuid;
select tt.as(:'u_o');
select tt.err('T6b the balance is checked again at approval: overpaid is refused and the request stays pending', format($$select w1e_request_decide(%s, true, null)$$, :'q9'), 'overpaid');
select tt.chk('T6b the failed approval changed nothing', (select status from w1e_requests where id=:'q9'::bigint)='pending');
update suppliers set opening_balance = 500000 where id=:'sup'::uuid;
select tt.as(:'u_o');
select w1e_request_decide(:'q9'::bigint, false, 'test: not needed') ->> 'status' as rj9 \gset
select gen_random_uuid() as c8 \gset
select money_exception_grant('override','test: urgent payment agreed by phone',:'u_pay'::uuid,null,'w1e_pay_over') ->> 'id' as gx5 \gset
select tt.as(:'u_pay');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":8000}]'::jsonb, :'c8'::uuid, 't6-exc2') ->> 'paid' as p9 \gset
select tt.chk('T6b one-off exception skips the wait once; Exceptions row exists', :'p9'::numeric=8000 and (select count(*) from money_exceptions where kind='override_exception' and event_type='w1e_pay_over')=1);
select tt.as(:'u_o');
select set_rule('supplier_pay_over',null) is null as o2 \gset
select tt.as(:'u_pay');
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":20000}]'::jsonb, gen_random_uuid(), 't6-blank') ->> 'paid' as p10 \gset
select tt.chk('T6b blank limit = off: 20000 paid at once', :'p10'::numeric=20000);
-- put the original body back
select set_config('w1e.dummy','1',false) is not null as dd \gset
do $r$ begin execute current_setting('w1e.orig_pay'); end $r$;
select tt.chk('T6 the original pay_supplier is restored (no marker)', position('w1e' in pg_get_functiondef('public.pay_supplier(uuid,integer,jsonb,uuid,text)'::regprocedure))=0);

\echo == T7 second supplier with the same name, mobile or TIN
select tt.as(:'u_o'); 
select set_rule('supplier_dup_mode','"warn"') is null as v0 \gset
insert into suppliers (name, mobile, tin) values ('test_vendor_a', '+8801712345670', 'TIN-0001');
insert into suppliers (name, mobile, tin) values ('Test_Vendor_A ', null, null);
insert into suppliers (name, mobile, tin) values ('test_vendor_b', '01712345670', null);
insert into suppliers (name, mobile, tin) values ('test_vendor_c', '01999999999', 'tin 0001');
insert into suppliers (name, mobile, tin) values ('test_vendor_d', '01888888888', 'TIN-0002');
select tt.chk('T7 warn: all saved, three yellow lines (name with case and spaces, mobile with +880, TIN with other punctuation), the distinct one is clean', (select count(*) from suppliers where name like 'test_vendor%' or name like 'Test_Vendor%')=5
  and tt.exc('w1e_vendor_duplicate')=3);
select tt.as(:'u_o'); select set_rule('supplier_dup_mode','"block"') is null as v1 \gset
select tt.err('T7 block: same name refused', $$insert into suppliers (name) values ('test_vendor_a')$$, 'vendor_duplicate');
select tt.err('T7 block: same mobile refused', $$insert into suppliers (name, mobile) values ('test_vendor_e', '8801888888888')$$, 'vendor_duplicate');
select tt.err('T7 block: same TIN refused', $$insert into suppliers (name, tin) values ('test_vendor_f', 'tin0002')$$, 'vendor_duplicate');
select tt.chk('T7 block: a new identity passes', (select count(*) from (select 1 from suppliers where name='test_vendor_g') z)=0);
insert into suppliers (name, mobile, tin) values ('test_vendor_g', '01777777777', 'TIN-0003');
select tt.chk('T7 the distinct supplier was saved', (select count(*) from suppliers where name='test_vendor_g')=1);
update suppliers set address = 'test address' where name='test_vendor_d';
select tt.chk('T7 changing an unrelated field of a supplier is never blocked', (select address from suppliers where name='test_vendor_d')='test address');
select tt.err('T7 changing the name to an existing name is refused', $$update suppliers set name='test_vendor_g' where name='test_vendor_d'$$, 'vendor_duplicate');
update suppliers set active=false where name='test_vendor_g';
insert into suppliers (name, mobile, tin) values ('test_vendor_g', '01777777777', 'TIN-0003');
select tt.chk('T7 an inactive supplier is not compared', (select count(*) from suppliers where name='test_vendor_g')=2);
select tt.as(:'u_o'); 
select money_exception_grant('override','test: two shops, one owner family',:'u_o'::uuid,null,'w1e_vendor_dup') ->> 'id' as gx6 \gset
insert into suppliers (name) values ('test_vendor_a');
select tt.chk('T7 the owner''s one-off exception lets one duplicate in, Exceptions row exists', (select count(*) from suppliers where name='test_vendor_a')=2 and (select count(*) from money_exceptions where kind='override_exception' and event_type='w1e_vendor_dup')=1);
select tt.chk('T7 the pre-check function tells the screen who matches', jsonb_array_length(w1e_vendor_check('TEST_VENDOR_B ', '01712345670', null) -> 'matches')>=1 and (w1e_vendor_check('test_nobody') ->> 'mode')='block');
select tt.as(:'u_x');
select tt.err('T7 a person without any supplier right cannot use the pre-check', $$select w1e_vendor_check('test_vendor_a')$$, 'not allowed');
select tt.as(:'u_o');
select tt.chk('T7 the checks report lists the duplicate pairs', jsonb_array_length(w1e_checks() -> 'vendors')>=3);
select set_rule('supplier_dup_mode','"off"') is null as v2 \gset
insert into suppliers (name) values ('test_vendor_a');
select tt.chk('T7 off = today: a third copy is saved', (select count(*) from suppliers where name='test_vendor_a')=3);

\echo == T8 one pay account per employee
select tt.as(:'u_o');
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account, mobile_wallet) values ('TESTW1E_A','test_emp_a','active',1,'1234-5678-90','01711111111');
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account, mobile_wallet) values ('TESTW1E_B','test_emp_b','active',1,'1234 5678 90',null);
select tt.chk('T8 mode off = today: two employees on one bank account are saved without any line', (select count(*) from employees where employee_no in ('TESTW1E_A','TESTW1E_B'))=2 and tt.exc('w1e_pay_account_duplicate')=0);
select set_rule('employee_pay_dup_mode','"warn"') is null as e1 \gset
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account, mobile_wallet) values ('TESTW1E_C','test_emp_c','active',1,null,'+8801711111111');
select tt.chk('T8 warn: saved, ONE red line (same wallet on its last 10 digits), account number masked in the text', (select count(*) from employees where employee_no='TESTW1E_C')=1 and tt.exc('w1e_pay_account_duplicate')=1
  and not exists (select 1 from money_exceptions where kind='w1e_pay_account_duplicate' and reason like '%01711111111%'));
select set_rule('employee_pay_dup_mode','"block"') is null as e2 \gset
select tt.err('T8 block: a third employee on the same bank account is refused (spaces and dashes do not matter)', $$insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account) values ('TESTW1E_D','test_emp_d','active',1,'1234567890')$$, 'pay_account_duplicate');
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account) values ('TESTW1E_E','test_emp_e','active',1,'999-000-111');
select tt.err('T8 block: changing an existing employee onto an used account is refused', $$update employees set bank_account='9990001 11' where employee_no='TESTW1E_A'$$, 'pay_account_duplicate');
update employees set status='resigned' where employee_no='TESTW1E_B';
update employees set status='resigned' where employee_no='TESTW1E_A';
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account) values ('TESTW1E_F','test_emp_f','active',1,'1234567890');
select tt.chk('T8 an employee who has left is not compared', (select count(*) from employees where employee_no='TESTW1E_F')=1);
select tt.as(:'u_o');
select money_exception_grant('override','test: spouses share one account, agreed',:'u_o'::uuid,null,'w1e_pay_account') ->> 'id' as gx7 \gset
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account) values ('TESTW1E_G','test_emp_g','active',1,'999000111');
select tt.chk('T8 the owner''s one-off exception lets one through; Exceptions row exists', (select count(*) from employees where employee_no='TESTW1E_G')=1 and (select count(*) from money_exceptions where kind='override_exception' and event_type='w1e_pay_account')=1);
select set_rule('employee_pay_dup_mode','"off"') is null as e3 \gset
update employees set bank_account='555-666-777' where employee_no='TESTW1E_E';
select tt.chk('T8 the change flag is off by default: changing a pay account leaves no line', tt.exc('w1e_pay_account_changed')=0);
select set_rule('employee_pay_change_flag','true') is null as e4 \gset
update employees set bank_account='555-666-888' where employee_no='TESTW1E_E';
update employees set notes='x' where employee_no='TESTW1E_E';
select tt.chk('T8 flag ON: one RED line for the change (not for the other edit), only the last 4 characters are shown', tt.exc('w1e_pay_account_changed')=1
  and exists (select 1 from money_exceptions where kind='w1e_pay_account_changed' and reason like '%****-777%' and reason like '%****-888%' and reason not like '%555-666%'));
select tt.chk('T8 the exceptions list marks the two employee kinds red and the others yellow', (select count(*) from jsonb_array_elements(w1e_exceptions_list(null,500) -> 'rows') x where x ->> 'level'='red')>=2
  and (select count(*) from jsonb_array_elements(w1e_exceptions_list(null,500) -> 'rows') x where x ->> 'level'='yellow')>=3);
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account) values ('TESTW1E_H','test_emp_h','active',1,'777-888-999'), ('TESTW1E_I','test_emp_i','active',1,'7778889 99');
select tt.chk('T8 the checks report lists pay accounts shared today, masked', jsonb_array_length(w1e_checks() -> 'pay_accounts')>=1 and (w1e_checks() -> 'pay_accounts' -> 0 ->> 'account') like '****%');
select tt.chk('T8 the pre-check names who already uses an account', jsonb_array_length(w1e_pay_account_check('999000111', null) -> 'matches')>=1);

\echo == T9 hook of cash_move_add (display only): the response says pending
select set_config('w1e.orig_cm', pg_get_functiondef('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure), false) is not null as sv2 \gset
select _m_patch('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure, array[
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2));$h$,
 $h$  return jsonb_build_object('id', id_, 'kind', p_kind, 'amount', round(p_amount, 2)) || public._w1e_cash_pending(id_); /* bos87 w1e94c */$h$]) as hooked2 \gset
select tt.as(:'u_o'); 
select set_rule('owner_money_entry_mode','"approval"') is null as m9 \gset
select tt.as(:'u_cash');
select cash_move_add(1,'owner_draw',61,tt.today(),'cash',null,'t9-a',null,gen_random_uuid(),false) as r9 \gset
select tt.chk('T9 the answer carries pending=true and the request id', (:'r9'::jsonb ->> 'pending')='true' and (:'r9'::jsonb ->> 'request_id') is not null);
select cash_move_add(1,'bank_deposit',62,tt.today(),null,null,'t9-b',null,gen_random_uuid(),false) as r9b \gset
select tt.chk('T9 a normal cash move answers as before (no pending key)', not (:'r9b'::jsonb ? 'pending'));
select tt.as(:'u_o');
select set_rule('owner_money_entry_mode','"open"') is null as m10 \gset
do $r$ begin execute current_setting('w1e.orig_cm'); end $r$;
select tt.chk('T9 the original cash_move_add is restored (no marker)', position('w1e' in pg_get_functiondef('public.cash_move_add(integer,text,numeric,date,text,uuid,text,text,uuid,boolean)'::regprocedure))=0);

\echo == T10 separation pairs reach the delegation report; state; permissions; paste twice; books balance
insert into user_grants (user_id, grant_code, location_id) values (:'u_acc','cash_move',null) on conflict do nothing;
select tt.as(:'u_o');
select tt.chk('T10 the delegation report lists the person who holds cash_move and accounts_manage', exists (select 1 from jsonb_array_elements(grant_separation_report()) x where x ->> 'pair'='cash_move_accounts' and x ->> 'user_id'=:'u_acc'));
select tt.chk('T10 w1e_state reads: settings, approver, hooks flags (hooks absent after the restore)', (w1e_state() -> 'settings' ->> 'owner_money_entry_mode')='open' and (w1e_state() #>> '{hooks,pay_supplier}')='false' and (w1e_state() #>> '{hooks,cash_move_add}')='false');
select tt.as(:'u_x');
select tt.err('T10 a person without part in it cannot read the exceptions list', $$select w1e_exceptions_list()$$, 'not allowed');
select tt.err('T10 nor the checks report', $$select w1e_checks()$$, 'not allowed');
select tt.err('T10 a request is never deleted', $$delete from w1e_requests$$, 'nothing is deleted');
select tt.chk('T10 every rule change went to audit_log (settings were changed by the owner above)', (select count(*) from audit_log where table_name='rules' and record_id in ('owner_money_entry_mode','bank_slip_required','supplier_pay_dup_mode','supplier_dup_mode','employee_pay_dup_mode'))>=8);
select tt.chk('T10 no journal entry is unbalanced anywhere', tt.unbalanced()=0);
\i supabase/phase94.sql
select tt.chk('T10 paste twice: the second paste of phase94 kept every setting value and request', rule_txt('owner_money_entry_mode')='open' and rule_txt('supplier_dup_mode')='off' and (select count(*) from w1e_requests)>=10);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
