-- FRESH DB ONLY. Phase 87 tests (money accounts, payment source on every event, transfers, statements, exceptions, approver choice).
--   ORDER="phase8 ... phase86 phase87" bash tests/sql/build_fresh_db.sh a87db        (port 5553 here)
--   psql -h /tmp -p 5553 -U postgres -d a87db -qAt -f supabase/phase87_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block. Run it once on a DB WITHOUT phase 87 pasted after the build and the T0 shape checks fail by design.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000087'
\set u_o2 '00000000-0000-0000-0000-000000000187'
\set u_acc '00000000-0000-0000-0000-000000000287'
\set u_st '00000000-0000-0000-0000-000000000387'
\set u_m1 '00000000-0000-0000-0000-000000000487'
\set u_m2 '00000000-0000-0000-0000-000000000587'
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
-- net debit of an account code over all entries (reversals included), debit positive
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.ndt(p_type text, p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
   where e.source_type = p_type and a.code = p_code $$;
create or replace function tt.n(p_type text) returns bigint language sql stable as $$ select count(*) from public.journal_entries where source_type = p_type and reverses_id is null and status = 'posted' $$;
-- chart code of a money account
create or replace function tt.cc(p_id bigint) returns text language sql stable as $$ select c.code from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id where a.id = p_id $$;
create or replace function tt.bal(p_id bigint) returns numeric language sql stable as $$ select tt.nd(tt.cc(p_id)) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner@s.app','{"full_name":"test_owner"}'), (:'u_o2','test_owner2@s.app','{"full_name":"test_owner2"}'), (:'u_acc','test_acct@s.app','{"full_name":"test_acct"}'),
 (:'u_st','test_staff@s.app','{"full_name":"test_staff"}'), (:'u_m1','test_mgmt1@s.app','{"full_name":"test_mgmt1"}'), (:'u_m2','test_mgmt2@s.app','{"full_name":"test_mgmt2"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_o2','owner'),(:'u_acc','management'),(:'u_st','salesperson'),(:'u_m1','management'),(:'u_m2','management') on conflict do nothing;
insert into user_locations values (:'u_acc',1),(:'u_acc',2),(:'u_st',1),(:'u_m1',1),(:'u_m2',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_acc','accounts_manage',null),(:'u_acc','accounts_view',null);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
select (:'pm'::date - 1) as pm0 \gset
select (:'pm'::date + interval '1 month' - interval '1 day')::date as pme \gset

\echo == T0 shape, safe defaults, patches in place, internals closed
select tt.chk('T0 phase87 present, 14 event settings, none has a default, override allowed, source not required, no money account exists',
  to_regprocedure('public._p87_present()') is not null and (select count(*) from money_event_settings where event_type in ('salary_payment','salary_advance','expense_10_2','quick_expense','supplier_payment','purchase_payment','owner_topup','owner_draw','partner_capital','partner_payout','customer_refund','supplier_refund','customer_advance','cash_handover'))=14   -- phase99: phases 96 and 97 add other_income, customer_collection and pos_split_payment, so the 14 original events are checked by name, not the total
  and not exists (select 1 from money_event_settings where default_account_id is not null or not allow_override or require_source) and not exists (select 1 from money_accounts));
select tt.chk('T0 the patches are in place (marker bos87) in the 10 shared functions',
  (select count(*) from (values ('public._acct_docs(date)'),('public._c_docs(date)'),('public._daybook_lines(int[],int[],date,date)'),('public._daybook_lines12(int[],date,date)'),('public._daybook_lines23(int[],date,date)'),
    ('public.daybook_vs_journal(date,date,int)'),('public.acct_cash_flow(date,date,int)'),('public._e_balance_check(date,int,int)'),('public.opening_balance_post(jsonb,uuid,boolean,boolean)'),('public.lock_check(date)')) v(f)
   where position('bos87' in pg_get_functiondef(v.f::regprocedure))>0)=10);
select tt.chk('T0 earlier tags survive inside _acct_docs (bos85, bos72, bos52, bos50) and phase82 still sees its hooks', position('bos85' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos52' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos50' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and _c_hooks_ok());
select tt.chk('T0 internals closed to browsers, API open',
  not has_function_privilege('authenticated','public._m_src(bigint)','execute') and not has_function_privilege('anon','public._m_reg(bigint)','execute') and not has_function_privilege('authenticated','public._m_docs(date)','execute')
  and not has_function_privilege('authenticated','public._m_patch(regprocedure,text[])','execute') and not has_function_privilege('authenticated','public._m_grant_take(text,text,uuid,bigint,numeric,date,text)','execute')
  and has_function_privilege('authenticated','public.money_account_add(text,text,text,text,text,text,int,text,numeric,date,text,text)','execute') and not has_function_privilege('anon','public.money_statement(bigint,date,date,int,int)','execute'));
select tt.chk('T0 nothing else switched on', not rule_on('payroll_accrual_on') and not rule_on('cash_short_post_on') and not rule_on('partner_settlement_post_on') and not rule_on('d_wallet_split_on')
  and rule_txt('owner_approval_mode')='self' and rule_txt('owner_approver_role') is null and public._owner_approver_users()='{}' and rule_txt('salary_pay_source')='by_payment');
select tt.chk('T0 the tables cannot be written by a browser role and have no delete', not has_table_privilege('authenticated','public.money_accounts','insert') and not has_table_privilege('authenticated','public.money_transfers','update')
  and not has_table_privilege('anon','public.money_accounts','select'));

select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset

\echo == T1 registry: add, rename, mapping, permissions, bad input
set role authenticated; select tt.as(:'u_o');
select (money_account_add('cash','test_drawer_a',null,null,null,null,1,null,30000,:'pm'::date) ->> 'id')::bigint as ma1 \gset
select (money_account_add('wallet','test_wallet_main',null,'TestPay','','01700000001',null,null,0) ->> 'id')::bigint as ma2 \gset
select (money_account_add('bank','test_bank_one',null,'Test Bank','Main Branch','1234567',null,null,200000,:'pm'::date) ->> 'id')::bigint as ma3 \gset
select (money_account_add('cash','test_drawer_b',null,null,null,null,2) ->> 'id')::bigint as ma4 \gset
select tt.chk('T1 four accounts, each on its OWN new child account under 1100 (Cash and bank), asset, debit side, mapping key m_acct_<id>',
  (select count(*) from money_accounts)=4 and (select count(distinct coa_account_id) from money_accounts)=4
  and (select count(*) from money_accounts a join coa_accounts c on c.id=a.coa_account_id join coa_accounts p on p.id=c.parent_id where p.code='1100' and c.type='asset' and c.normal_side='debit' and not c.is_group)=4
  and (select count(*) from acct_mappings m join money_accounts a on m.key='m_acct_'||a.id and m.account_id=a.coa_account_id)=4);
select tt.chk('T1 codes: cash 1110-nnn, wallet 1130-nnn, bank 1120-nnn', tt.cc(:'ma1') like '1110-%' and tt.cc(:'ma2') like '1130-%' and tt.cc(:'ma3') like '1120-%' and tt.cc(:'ma4') like '1110-%');
select tt.chk('T1 the add left an audit_log line', exists (select 1 from audit_log where action='money_account_add' and record_id=:'ma1'));
select tt.err('T1 a cash drawer needs a place', $$select money_account_add('cash','test_x')$$, 'place_required');
select tt.err('T1 a wallet needs provider and number', $$select money_account_add('wallet','test_x',null,'TestPay')$$, 'provider_and_number_required');
select tt.err('T1 a bank account needs bank and number', $$select money_account_add('bank','test_x')$$, 'provider_and_number_required');
select tt.err('T1 bad kind', $$select money_account_add('purse','test_x',null,null,null,null,1)$$, 'bad_kind');
select tt.err('T1 same wallet and number twice is refused', $$select money_account_add('wallet','test_dup',null,'testpay','','01700000001')$$, 'account_exists');
select tt.err('T1 place is only for cash', $$select money_account_add('bank','test_x',null,'B','','9',1)$$, 'place_only_for_cash');
select tt.err('T1 pick an existing chart account: a header is refused', $$select money_account_add('cash','test_x',null,null,null,null,1,'1100')$$, 'coa_not_usable');
select tt.err('T1 pick an existing chart account: a legacy wallet account (phase83) is refused', $$select money_account_add('wallet','test_x',null,'P','','7',null,'1131')$$, 'coa_is_legacy_wallet');
select tt.err('T1 pick an existing chart account: general bank account 1120 as a cash kind is refused', $$select money_account_add('cash','test_x',null,null,null,null,1,'1120')$$, 'coa_kind_mismatch');
select tt.err('T1 an unknown chart code', $$select money_account_add('cash','test_x',null,null,null,null,1,'9999')$$, 'unknown_account');
select (money_account_add('cash','test_general_cash',null,null,null,null,null,'1110') ->> 'id')::bigint as ma5 \gset
select tt.chk('T1 the owner can pick an EXISTING chart account (general cash 1110) as a money account', tt.cc(:'ma5')='1110');
select tt.err('T1 the same chart account cannot be mapped twice', $$select money_account_add('cash','test_again',null,null,null,null,null,'1110')$$, 'coa_already_mapped');
select money_account_update(:'ma4'::bigint,'test_drawer_b2') is not null as rn1 \gset
select tt.chk('T1 rename: the money account and its chart account follow', (select name_en from money_accounts where id=:'ma4')='test_drawer_b2'
  and (select c.name_en from money_accounts a join coa_accounts c on c.id=a.coa_account_id where a.id=:'ma4')='test_drawer_b2');
select money_account_update(:'ma5'::bigint,'test_general_cash_x') is not null as rn2 \gset
select tt.chk('T1 rename of the general account does not touch the chart name of 1110', (select name_en from coa_accounts where code='1110')<>'test_general_cash_x');
select money_account_update(:'ma4'::bigint,'test_drawer_b') is not null as ren \gset
select tt.as(:'u_st');
select tt.err('T1 no permission: a salesperson cannot add', $$select money_account_add('cash','test_x',null,null,null,null,1)$$, 'not allowed');
select tt.err('T1 no permission: a salesperson cannot read the list', $$select money_accounts_list()$$, 'not allowed');
select tt.err('T1 no permission: a salesperson cannot change a setting', $$select money_event_setting_set('quick_expense', 1, true, false)$$, 'not allowed');
select tt.err('T1 no permission: a salesperson cannot transfer', format($$select money_transfer_add(%s,%s,10,tt.today())$$, :'ma1', :'ma3'), 'not allowed');
reset role;
select tt.chk('T1 general cash is generic (journal based)', _m_is_generic(:'ma5'));
select tt.err('T1 a money account is never deleted', $$delete from money_accounts$$, 'nothing is deleted');
set role authenticated;
select tt.as(:'u_acc');
select tt.chk('T1 the accounts grant holder can add (owner/accounts grant)', (money_account_add('cash','test_drawer_c',null,null,null,null,1) ->> 'id') is not null);
select tt.as(:'u_o');

\echo == T2 opening balance goes through the existing path (opening_balance_post, section money)
-- Dr drawer A 30000 + bank 200000 + general cash 50000 = 280000 ; Cr owner capital 280000
select tt.err('T2 unbalanced opening is refused (money without the other side)', format($$select opening_balance_post('{"money":[{"money_account_id":%s,"amount":"30000"}]}'::jsonb, null, false, false)$$, :'ma1'), 'unbalanced');
select tt.err('T2 unknown money account in the opening is refused', $$select opening_balance_post('{"money":[{"money_account_id":9999,"amount":"30"}],"capital":[{"kind":"owner","amount":30}]}'::jsonb, null, false, false)$$, 'unknown_money_account');
select tt.chk('T2 money_opening_json lists the two typed openings', jsonb_array_length(money_opening_json())=2);
select opening_balance_post(format('{"money":[{"money_account_id":%s,"amount":"30000"},{"money_account_id":%s,"amount":"200000"}],"cash":[{"location_id":1,"mode":"cash","amount":50000}],"capital":[{"kind":"owner","amount":280000}]}', :'ma1', :'ma3')::jsonb, null, true, false) as dry \gset
select tt.chk('T2 the dry run is balanced and writes nothing', (:'dry'::jsonb ->> 'balanced')='true' and (select count(*) from journal_entries where source_type='opening')=0);
select opening_balance_post(format('{"money":[{"money_account_id":%s,"amount":"30000"},{"money_account_id":%s,"amount":"200000"}],"cash":[{"location_id":1,"mode":"cash","amount":50000}],"capital":[{"kind":"owner","amount":280000}]}', :'ma1', :'ma3')::jsonb, gen_random_uuid(), false, false) ->> 'id' as opj \gset
select tt.chk('T2 ONE opening entry: Dr drawer A 30000, Dr bank 200000, Dr 1110 50000, Cr 3100 280000, balanced', tt.bal(:'ma1')=30000 and tt.bal(:'ma3')=200000 and tt.nd('1110')=50000 and tt.nd('3100')=-280000 and tt.unbalanced()=0
  and (select count(*) from journal_entries where source_type='opening')=1);
select tt.chk('T2 the accounts are marked opening_posted and the typed list is empty now', (select count(*) from money_accounts where opening_posted)=2 and jsonb_array_length(money_opening_json())=0);
select tt.err('T2 a second opening is refused (existing rule)', format($$select opening_balance_post('{"money":[{"money_account_id":%s,"amount":"1"}],"capital":[{"kind":"owner","amount":1}]}'::jsonb, null, false, false)$$, :'ma4'), 'opening_exists');
select tt.err('T2 a new account with an opening figure after the opening exists is refused (fund it by owner top-up or transfer)', $$select money_account_add('cash','test_late',null,null,null,null,1,null,500)$$, 'opening_exists_use_topup');

\echo == T3 event settings: default, override, require; the tag; every event hits exactly its account
-- funding: wallet <- bank 20000 with a fee of 20 taken from the bank (one balanced entry: Dr wallet 20000, Dr bank charges 20, Cr bank 20020)
select money_transfer_add(:'ma3'::bigint, :'ma2'::bigint, 20000, tt.today(), 20, 'from', 'fund1', 'test fund', 1, gen_random_uuid()) ->> 'id' as tr1 \gset
-- drawer B <- general cash 1110: 5000 (both accounts registered, the general one is the journal-only legacy account)
select money_transfer_add(:'ma5'::bigint, :'ma4'::bigint, 5000, tt.today(), 0, 'from', 'fund2', null, 2, gen_random_uuid()) ->> 'id' as tr2 \gset
select acct_post_pending(false) ->> 'posted' as pp1 \gset
select tt.chk('T3 transfers posted as ONE balanced entry each: wallet +20000, bank 200000-20020=179980, bank charge 20, drawer B 5000, general cash 50000-5000=45000',
  tt.bal(:'ma2')=20000 and tt.bal(:'ma3')=179980 and tt.nd('5810')=20 and tt.bal(:'ma4')=5000 and tt.nd('1110')=45000 and tt.n('money_transfer')=2 and tt.unbalanced()=0);

\echo -- T3a quick expense: default source + no override + tag
select money_event_setting_set('quick_expense', :'ma1'::bigint, false, false) is not null as s1 \gset
select tt.chk('T3a setting saved with an audit line', (select default_account_id from money_event_settings where event_type='quick_expense')=:'ma1' and exists (select 1 from audit_log where table_name='money_event_settings' and record_id='quick_expense'));
-- no tag, mode cash: the DEFAULT (drawer A) is used. 700 out of drawer A
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 700, 'cash', false, null, gen_random_uuid()) ->> 'id' as q1 \gset
select tt.chk('T3a default applied: money_account_id = drawer A, mode cash', (select money_account_id from quick_expenses where id=:'q1'::uuid)=:'ma1');
-- a different account is refused while override is not allowed
select tt.err('T3a override not allowed: the bank account is refused', format($$select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 100, 'cash', false, 'ma#%s;', gen_random_uuid())$$, :'ma3'), 'money_source_fixed');
-- the owner allows ONE exception for ONE payment (client id) with a reason
select gen_random_uuid() as cq \gset
select money_exception_grant('override', 'test: drawer empty, pay from bank this once', null, :'cq'::uuid, 'quick_expense') ->> 'id' as g1 \gset
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 120, 'cash', false, 'ma#' || :'ma3' || ';', :'cq'::uuid) ->> 'id' as q2 \gset
select tt.chk('T3a owner exception: the bank is used for that one payment (mode follows the account = bank)', (select money_account_id from quick_expenses where id=:'q2'::uuid)=:'ma3' and (select mode from quick_expenses where id=:'q2'::uuid)='bank');
select tt.chk('T3a the exception is on record: Exceptions list (override_exception) + audit_log (grant and use), the grant is used up',
  exists (select 1 from money_exceptions where kind='override_exception' and reason like '%drawer empty%') and (select count(*) from audit_log where action in ('money_exception_grant','money_exception_used') and (detail->>'reason') like '%drawer empty%')=2
  and (select used_at from money_exception_grants where id=:'g1'::bigint) is not null);
select tt.err('T3a the same exception cannot be used twice', format($$select quick_expense_add(1, tt.today(), 'transport', 'x', 100, 'cash', false, 'ma#%s;', gen_random_uuid())$$, :'ma3'), 'money_source_fixed');
select tt.as(:'u_acc');
select tt.err('T3a only the owner can grant an exception', $$select money_exception_grant('override','test no',null,gen_random_uuid(),'quick_expense')$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T3a an exception needs a reason', $$select money_exception_grant('override','',null,gen_random_uuid(),'quick_expense')$$, 'reason_required');
select tt.err('T3a an exception needs a target (payment or person)', $$select money_exception_grant('override','test reason')$$, 'target_required');
-- mode mismatch: the default (cash drawer) is not applied to a bank payment; it stays on the generic bank account as today
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 55, 'bank', false, null, gen_random_uuid()) ->> 'id' as q3 \gset
select tt.chk('T3a a bank payment is not forced into the cash default: no money account, legacy generic bank', (select money_account_id from quick_expenses where id=:'q3'::uuid) is null);
-- the place check: drawer B belongs to place 2
select tt.err('T3a a drawer of another place is refused', format($$select quick_expense_add(1, tt.today(), 'transport', 'x', 10, 'cash', false, 'ma#%s;', gen_random_uuid())$$, :'ma4'), 'money_source_fixed');
select money_event_setting_set('quick_expense', null, true, false, true) is not null as s2 \gset
select tt.err('T3a a drawer of another place is refused (override allowed again)', format($$select quick_expense_add(1, tt.today(), 'transport', 'x', 10, 'cash', false, 'ma#%s;', gen_random_uuid())$$, :'ma4'), 'money_account_place');
select tt.err('T3a unknown money account in the tag', $$select quick_expense_add(1, tt.today(), 'transport', 'x', 10, 'cash', false, 'ma#99999;', gen_random_uuid())$$, 'unknown_money_account');
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 40, 'cash', false, 'ma#' || :'ma1' || ';keep this note', gen_random_uuid()) ->> 'id' as q4 \gset
select tt.chk('T3a the tag is removed from the text, the user note is kept', (select note from quick_expenses where id=:'q4'::uuid)='keep this note' and (select money_account_id from quick_expenses where id=:'q4'::uuid)=:'ma1');
select acct_post_pending(false) ->> 'posted' as pp2 \gset
-- drawer A: 30000 - 700 - 40 = 29260 ; bank: 179980 - 120 = 179860 ; transport 5700 gets 700+120+55+40 = 915 ; general bank 1120 gets the 55
select tt.chk('T3a journal hits exactly the chosen accounts: drawer A 29260, bank 179860, 5700 = 915, generic bank 1120 = -55', tt.bal(:'ma1')=29260 and tt.bal(:'ma3')=179860 and tt.nd('5700')=915 and tt.nd('1120')=-55 and tt.nd('1110')=45000);

\echo -- T3b require source
select money_event_setting_set('supplier_payment', null, true, true) is not null as s3 \gset
reset role;
insert into suppliers (name) values ('test_supplier_87');
select id as sup1 from suppliers where name='test_supplier_87' \gset
set role authenticated; select tt.as(:'u_o');
reset role;
select tt.err('T3b required source: a payment with none is refused (trigger, server side)', format($$insert into supplier_payments (supplier_id, location_id, mode, amount, created_by) values (%L, 1, 'cash', 10, %L)$$, :'sup1', :'u_o'), 'money_source_required');
select money_exception_grant('require_source', 'test: old paper slip, source unknown', :'u_o'::uuid, null, 'supplier_payment') ->> 'id' as g2 \gset
insert into supplier_payments (supplier_id, location_id, mode, amount, created_by) values (:'sup1', 1, 'cash', 10, :'u_o');
select tt.chk('T3b the owner exception lets exactly ONE payment through without a source; Exceptions list shows source_required_exception', exists (select 1 from money_exceptions where kind='source_required_exception') and (select count(*) from supplier_payments where supplier_id=:'sup1')=1);
select tt.err('T3b the second one is refused again', format($$insert into supplier_payments (supplier_id, location_id, mode, amount, created_by) values (%L, 1, 'cash', 10, %L)$$, :'sup1', :'u_o'), 'money_source_required');
-- with the tag the payment is accepted; the wallet: 1000 out of the wallet, the wallet column is cleared (no legacy split)
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, created_by) values (:'sup1', 1, 'mobile', 'ma#' || :'ma2' || ';bkash', 1000, :'u_o');
select tt.chk('T3b the wallet money account: mode mobile, legacy wallet text cleared, account set', (select money_account_id from supplier_payments where amount=1000)=:'ma2' and (select mode from supplier_payments where amount=1000)='mobile' and (select wallet from supplier_payments where amount=1000) is null);
set role authenticated; select tt.as(:'u_o');
select money_event_setting_set('supplier_payment', null, true, false) is not null as s4 \gset
select acct_post_pending(false) ->> 'posted' as pp3 \gset
-- wallet 20000 - 1000 = 19000 ; the 10 from the exception payment sits on generic cash 1110 : 45000 - 10 = 44990
select tt.chk('T3b journal: wallet account 19000 (not the generic 1130), payable debited, generic cash 44990', tt.bal(:'ma2')=19000 and tt.nd('1130')=0 and tt.nd('1110')=44990 and tt.ndt('supplier_payment','2100')=1010);

\echo == T4 every event type: the journal line hits exactly the chosen account
reset role;
insert into customers (mobile, name) values ('01800000087', 'test_customer_87');
select id as cu1 from customers where name='test_customer_87' \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST87_A','test_emp_a','active',1) returning id) select id as ea from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST87_B','test_emp_b','active',1) returning id) select id as eb from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST87_C','test_emp_c','active',1) returning id) select id as ec from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST87_D','test_emp_d','active',1) returning id) select id as ed from x \gset
set role authenticated; select tt.as(:'u_o');
select tt.bal(:'ma1') as d1_0, tt.bal(:'ma2') as w_0, tt.bal(:'ma3') as b_0, tt.nd('1110') as g_0, tt.nd('5200') as sal_0 \gset

\echo -- T4a salary payment 8000 from the BANK (the screen sent mode cash, the account decides) and 4000 from the WALLET in one payment run
reset role;
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 1, 'draft') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'ea', 1, 8000, 8000) returning id) select id as l1a from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'eb', 1, 4000, 4000) returning id) select id as l1b from x \gset
set role authenticated; select tt.as(:'u_o');
select payroll_approve(:'run1'::bigint) ->> 'status' as ap1 \gset
select payroll_pay(:'run1'::bigint, array[:'l1a'::bigint], 'cash', tt.today(), 'ma#' || :'ma3' || ';sal-a', null, gen_random_uuid(), null) is not null as pay1 \gset
select payroll_pay(:'run1'::bigint, array[:'l1b'::bigint], 'cash', tt.today(), 'ma#' || :'ma2' || ';sal-b', null, gen_random_uuid(), null) is not null as pay2 \gset
select acct_post_pending(false) ->> 'posted' as ppa \gset
select tt.chk('T4a salary: Dr 5200 12000, Cr bank 8000, Cr wallet 4000, the general cash is untouched; refs kept without the tag',
  tt.nd('5200')=:'sal_0'::numeric+12000 and tt.bal(:'ma3')=:'b_0'::numeric-8000 and tt.bal(:'ma2')=:'w_0'::numeric-4000 and tt.nd('1110')=:'g_0'::numeric
  and (select count(*) from payroll_payments where ref in ('sal-a','sal-b'))=2 and (select mode from payroll_payments where ref='sal-a')='bank' and (select mode from payroll_payments where ref='sal-b')='mobile');
-- the fixed salary source setting (phase82) is only the fallback: with salary_pay_source = cash a payment that names the bank still goes to the bank
select set_rule('salary_pay_source','"cash"'::jsonb) is null as sps \gset
reset role;
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'ec', 1, 500, 500) returning id) select id as l1c from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'ed', 1, 100, 100) returning id) select id as l1d from x \gset
set role authenticated; select tt.as(:'u_o');
select payroll_pay(:'run1'::bigint, array[:'l1c'::bigint], 'cash', tt.today(), 'ma#' || :'ma3' || ';sal-c', null, gen_random_uuid(), null) is not null as pay3 \gset
select payroll_pay(:'run1'::bigint, array[:'l1d'::bigint], 'cash', tt.today(), 'sal-nosrc', null, gen_random_uuid(), null) is not null as pay4 \gset
select acct_post_pending(false) ->> 'posted' as ppa2 \gset
select tt.chk('T4a salary_pay_source=cash (fixed source) is only the fallback: tagged -> bank; untagged -> cash by that old setting',
  tt.bal(:'ma3')=:'b_0'::numeric-8500 and exists (select 1 from payroll_payments where ref='sal-nosrc' and money_account_id is null));
select set_rule('salary_pay_source','"by_payment"'::jsonb) is null as sps2 \gset
select tt.nd('1110') as g_0 \gset

\echo -- T4b salary advance 3000 from drawer A
select staff_advance_add(:'ea'::uuid, tt.today(), 3000, 1000, 'cash', tt.today() + 30, 'ma#' || :'ma1' || ';test advance', gen_random_uuid()) is not null as adv1 \gset
select acct_post_pending(false) ->> 'posted' as ppb \gset
select tt.chk('T4b advance: Dr 1220 3000, Cr drawer A 3000, note kept', tt.bal(:'ma1')=:'d1_0'::numeric-3000 and tt.nd('1220')>=3000 and exists (select 1 from employee_advances where note='test advance' and money_account_id=:'ma1'));

\echo -- T4c expense voucher 10-2 paid from the wallet 500 (source inside the form data) + day book mode
select save_entry(null,'10-2',1,tt.today(),format('{"lines":[{"head":"transport","amount":"500"}],"money_account_id":"%s"}', :'ma2')::jsonb,'[]') ->> 'id' as e1 \gset
select submit_entry(:'e1'::uuid) is not null as s1 \gset
select decide_entry(:'e1'::uuid,true,null,'{}','[]') ->> 'status' as d1 \gset
select acct_post_pending(false) ->> 'posted' as ppc \gset
select tt.chk('T4c 10-2: Cr wallet 500 (not general cash), approved', :'d1'='approved' and tt.bal(:'ma2')=:'w_0'::numeric-4500 and tt.nd('1110')=:'g_0'::numeric and tt.ndt('expense_voucher','1110')=0);
reset role;
select tt.chk('T4c day book: the 10-2 line is mobile (account kind), and the line text names the account', exists (select 1 from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='expense' and mode='mobile' and txt like '%test_wallet_main%'));
select tt.err('T4c 10-2 with an unknown account in the data is refused', $$select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"5"}],"money_account_id":"99999"}'::jsonb,'[]')$$, 'unknown_money_account');
select tt.err('T4c 10-2 with garbage in the account key is refused', $$select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"5"}],"money_account_id":"abc"}'::jsonb,'[]')$$, 'unknown_money_account');

set role authenticated; select tt.as(:'u_o');
\echo -- T4d owner top-up 10000 into the bank, owner draw 2000 from drawer A, customer advance 1500 into the wallet, advance refund 500, hub handover 7000 into drawer A
select cash_move_add(1,'owner_topup',10000,tt.today(),'cash',null,'ma#' || :'ma3' || ';tu',null,gen_random_uuid(),false) is not null as cm1 \gset
select cash_move_add(1,'owner_draw',2000,tt.today(),'cash',null,'ma#' || :'ma1' || ';dr',null,gen_random_uuid(),false) is not null as cm2 \gset
select cash_move_add(1,'cust_advance',1500,tt.today(),'cash',:'cu1'::uuid,'ma#' || :'ma2' || ';ca',null,gen_random_uuid(),false) is not null as cm3 \gset
select cash_move_add(1,'cust_advance_refund',500,tt.today(),'cash',:'cu1'::uuid,'ma#' || :'ma2' || ';car',null,gen_random_uuid(),false) is not null as cm4 \gset
select cash_move_add(1,'hub_receipt',7000,tt.today(),'cash',null,'ma#' || :'ma1' || ';hub',null,gen_random_uuid(),false) is not null as cm5 \gset
select tt.err('T4d a hub handover must go into a cash drawer, not a bank', format($$select cash_move_add(1,'hub_receipt',100,tt.today(),'cash',null,'ma#%s;x',null,gen_random_uuid(),false)$$, :'ma3'), 'money_account_kind');
select acct_post_pending(false) ->> 'posted' as ppd \gset
-- bank +10000 ; drawer A -2000 +7000 ; wallet +1500 -500
select tt.chk('T4d owner top-up Dr bank / Cr 3100, owner draw Dr 3300 / Cr drawer A, customer advance Cr 2300 into the wallet, refund out of the wallet, hub Dr drawer A / Cr 1230',
  tt.bal(:'ma3')=:'b_0'::numeric-8500+10000 and tt.bal(:'ma1')=:'d1_0'::numeric-3000-2000+7000 and tt.bal(:'ma2')=:'w_0'::numeric-4500+1500-500 and tt.ndt('cash_move','3300')=2000 and tt.ndt('cash_move','1230')=-7000
  and tt.nd('1110')=:'g_0'::numeric and tt.unbalanced()=0);

\echo -- T4e supplier refund 800 into the bank, customer refund 300 out of drawer A, purchase payment 600 from the bank, supplier payment 400 from drawer A
select supplier_refund(:'sup1'::uuid, 1, 800, 'cash', 'ma#' || :'ma3' || ';', 'rf', 'other', null, gen_random_uuid()) is not null as sr1 \gset
reset role;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values (1, 987001, tt.today(), now(), '[]', 1000, 0, 1000, 'cash', 'done', :'u_o');
select id as sale1 from sales where receipt=987001 \gset
insert into sale_returns (sale_id, location_id, lines, amount, refund_amount, refund_mode, wallet, reason_code, created_by)
  values (:'sale1', 1, '[]', 300, 300, 'cash', 'ma#' || :'ma1' || ';', 'other', :'u_o');
insert into purchase_bills (supplier_id, bill_no, bill_date, location_id, status, subtotal, total, created_by) values (:'sup1', 'TB87', tt.today(), 1, 'posted', 600, 600, :'u_o');
select id as pb1 from purchase_bills where bill_no='TB87' \gset
insert into supplier_payments (supplier_id, location_id, bill_id, mode, wallet, amount, created_by) values (:'sup1', 1, :'pb1', 'cash', 'ma#' || :'ma3' || ';', 600, :'u_o');
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, created_by) values (:'sup1', 1, 'cash', 'ma#' || :'ma1' || ';', 400, :'u_o');
set role authenticated; select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as ppe \gset
select tt.chk('T4e supplier refund Dr bank 800, customer refund Cr drawer A 300 (Dr 4110), purchase payment Cr bank 600, supplier payment Cr drawer A 400',
  tt.bal(:'ma3')=:'b_0'::numeric-8500+10000+800-600 and tt.bal(:'ma1')=:'d1_0'::numeric-3000-2000+7000-300-400 and tt.ndt('sale_return','4110')=300 and tt.nd('1110')=:'g_0'::numeric);
reset role;
select tt.chk('T4e event names: the purchase payment (with a bill) and the supplier payment are different events', _m_event('supplier_payments', '{"bill_id":"x"}'::jsonb)='purchase_payment' and _m_event('supplier_payments','{}'::jsonb)='supplier_payment');

\echo == T5 partner capital and partner payout from chosen accounts
reset role;
with x as (insert into partner_parties (name, kind) values ('test_partner_owner87','individual') returning id) select id as pa from x \gset
with x as (insert into partner_parties (name, kind) values ('test_partner_two87','individual') returning id) select id as pb from x \gset
set role authenticated; select tt.as(:'u_o');
select partner_venture_save(null,'test_venture87','test_venture87','custom',null,'partnership', :'pm', null,'draft',null,gen_random_uuid()) ->> 'id' as v1 \gset
select partner_agreement_save(null, :'v1'::bigint, 'test deed 87', :'pm'::date, null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id' as ag \gset
select partner_agreement_party_set(:'ag'::bigint, :'pa'::bigint, 'owner', 60, null) is not null as p1 \gset
select partner_agreement_party_set(:'ag'::bigint, :'pb'::bigint, 'partner', 40, null) is not null as p2 \gset
select partner_rule_save(:'ag'::bigint, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as r1 \gset
select partner_rule_save(:'ag'::bigint, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":60},{"role":"partner","percent":40}]}'::jsonb) is not null as r2 \gset
select partner_agreement_activate(:'ag'::bigint) is not null as act \gset
select tt.bal(:'ma3') as b_1, tt.bal(:'ma1') as d_1, tt.bal(:'ma2') as w_1, tt.nd('1110') as g_1 \gset
select partner_capital_add(:'ag'::bigint, :'pa'::bigint, 'contribution', 9000, tt.today(), 'cash', 'test cap', 'ma#' || :'ma3' || ';cap1', gen_random_uuid()) is not null as pc1 \gset
select partner_capital_add(:'ag'::bigint, :'pa'::bigint, 'return_of_capital', 1000, tt.today(), 'cash', 'test ret', 'ma#' || :'ma1' || ';ret1', gen_random_uuid()) is not null as pc2 \gset
select partner_settlement_save(:'ag'::bigint, :'pm'::date, :'pme'::date, '{"net_profit_before_fees":100000}'::jsonb, 'test', gen_random_uuid()) ->> 'id' as ps1 \gset
select partner_settlement_approve(:'ps1'::bigint) ->> 'status' as sa \gset
select set_rule('partner_settlement_post_on','true'::jsonb) is null as pon \gset
select id as lin_a from partner_settlement_lines where settlement_id=:'ps1' and party_id=:'pa' \gset
select partner_settlement_pay(:'lin_a'::bigint, 2000, 'cash', tt.today(), 'ma#' || :'ma2' || ';pp1', gen_random_uuid()) is not null as pp1 \gset
select acct_post_pending(false) ->> 'posted' as ppf \gset
select tt.chk('T5 partner contribution Dr bank 9000 / Cr 3100; return of capital Cr drawer A 1000; profit payout Dr payable / Cr wallet 2000; generic cash untouched',
  tt.bal(:'ma3')=:'b_1'::numeric+9000 and tt.bal(:'ma1')=:'d_1'::numeric-1000 and tt.bal(:'ma2')=:'w_1'::numeric-2000 and tt.nd('1110')=:'g_1'::numeric and tt.unbalanced()=0);
select tt.chk('T5 modes follow the accounts (bank, cash, mobile)', (select mode from partner_capital where ref='cap1')='bank' and (select mode from partner_capital where ref='ret1')='cash' and (select mode from partner_settlement_payments where ref='pp1')='mobile');
select set_rule('partner_settlement_post_on','false'::jsonb) is null as poff \gset

\echo == T6 negative balance policy per account: warn (default), block, allow; owner exception
select (money_account_add('cash','test_drawer_n',null,null,null,null,1) ->> 'id')::bigint as ma7 \gset
select tt.chk('T6 default policy is warn', (select neg_policy from money_accounts where id=:'ma7'::bigint)='warn');
select quick_expense_add(1, tt.today(), 'transport', 'x', 50, 'cash', false, 'ma#' || :'ma7' || ';', gen_random_uuid()) ->> 'id' as qn1 \gset
select tt.chk('T6 warn: the payment is saved and a negative_warn exception is on the list', exists (select 1 from quick_expenses where id=:'qn1'::uuid) and exists (select 1 from money_exceptions where kind='negative_warn' and account_id=:'ma7'::bigint and amount=50));
select money_account_update(:'ma7'::bigint, null,null,null,null,null,'block') is not null as blk \gset
select tt.err('T6 block: an outgoing payment that would make the balance negative is refused', format($$select quick_expense_add(1, tt.today(), 'transport', 'x', 50, 'cash', false, 'ma#%s;', gen_random_uuid())$$, :'ma7'), 'money_negative');
select tt.err('T6 block: also for a 10-2 voucher at submit', format($$select submit_entry((save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"10"}],"money_account_id":"%s"}'::jsonb,'[]') ->> 'id')::uuid)$$, :'ma7'), 'money_negative');
select tt.err('T6 block: also for a transfer out', format($$select money_transfer_add(%s,%s,10,tt.today(),0,'from',null,null,1)$$, :'ma7', :'ma1'), 'money_negative');
select gen_random_uuid() as cn \gset
select money_exception_grant('negative', 'test: cash arrives tomorrow, the owner allows this one', null, :'cn'::uuid, 'quick_expense', :'ma7'::bigint, 100) ->> 'id' as gn \gset
select quick_expense_add(1, tt.today(), 'transport', 'x', 60, 'cash', false, 'ma#' || :'ma7' || ';', :'cn'::uuid) ->> 'id' as qn2 \gset
select tt.chk('T6 owner exception: that ONE payment passes, reason on the Exceptions list and in audit_log, the account stays blocked for others',
  exists (select 1 from quick_expenses where id=:'qn2'::uuid) and exists (select 1 from money_exceptions where kind='negative_block_exception' and reason like '%cash arrives tomorrow%')
  and exists (select 1 from audit_log where action='money_exception_used' and detail->>'reason' like '%cash arrives tomorrow%'));
select tt.err('T6 and the exception is for a payment up to its maximum amount only (150 > 100)', format($$select quick_expense_add(1, tt.today(), 'transport', 'x', 150, 'cash', false, 'ma#%s;', gen_random_uuid())$$, :'ma7'), 'money_negative');
select money_account_update(:'ma7'::bigint, null,null,null,null,null,'allow') is not null as alw \gset
select count(*) as nexc0 from money_exceptions \gset
select quick_expense_add(1, tt.today(), 'transport', 'x', 70, 'cash', false, 'ma#' || :'ma7' || ';', gen_random_uuid()) ->> 'id' as qn3 \gset
select tt.chk('T6 allow: saved without any exception row', (select count(*) from money_exceptions)=:'nexc0'::int and exists (select 1 from quick_expenses where id=:'qn3'::uuid));
select acct_post_pending(false) ->> 'posted' as ppg \gset

\echo == T7 transfers: both-side statements, fee on the other side, void, same account, unknown, inactive, double post
reset role;
select tt.chk('T6 the register (book) balance is exactly -(50+60+70) = -180, the ledger agrees after posting, and the proof has no unexplained difference', (_m_reg(:'ma7'::bigint))=-180 and tt.bal(:'ma7')=-180 and (_m_prove(:'ma7'::bigint) ->> 'diff')::numeric=0);
set role authenticated; select tt.as(:'u_o');
select tt.bal(:'ma3') as b_2, tt.bal(:'ma2') as w_2 \gset
select money_transfer_add(:'ma3'::bigint, :'ma2'::bigint, 1000, tt.today(), 10, 'to', 'tr-to', 'fee on the receiving side', 1, gen_random_uuid()) ->> 'id' as tr3 \gset
select acct_post_pending(false) ->> 'posted' as pph \gset
select tt.chk('T7 fee on the receiving side: bank -1000, wallet +990, wallet fees (5815, the wallet bears it) +10, ONE balanced entry', tt.bal(:'ma3')=:'b_2'::numeric-1000 and tt.bal(:'ma2')=:'w_2'::numeric+990 and tt.ndt('money_transfer','5815')=10
  and (select count(distinct entry_id) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='money_transfer' and e.source_id=:'tr3' and e.reverses_id is null)=1 and tt.unbalanced()=0);
select money_statement(:'ma3'::bigint) as s_from \gset
select money_statement(:'ma2'::bigint) as s_to \gset
select tt.chk('T7 both-side statements show the transfer: out 1000 on the bank, in 990 on the wallet, counter account named',
  exists (select 1 from jsonb_array_elements(:'s_from'::jsonb -> 'rows') r where r->>'source_type'='money_transfer' and r->>'source_id'=:'tr3' and (r->>'out')::numeric=1000)
  and exists (select 1 from jsonb_array_elements(:'s_to'::jsonb -> 'rows') r where r->>'source_type'='money_transfer' and r->>'source_id'=:'tr3' and (r->>'in')::numeric=990 and r->>'counter' like '%1120-%'));
select tt.err('T7 transfer to the same account is refused', format($$select money_transfer_add(%s,%s,10,tt.today(),0,'from',null,null,1)$$, :'ma3', :'ma3'), 'same_account');
select tt.err('T7 unknown account', format($$select money_transfer_add(%s,99999,10,tt.today(),0,'from',null,null,1)$$, :'ma3'), 'unknown_money_account');
select tt.err('T7 amount zero', format($$select money_transfer_add(%s,%s,0,tt.today(),0,'from',null,null,1)$$, :'ma3', :'ma2'), 'bad_amount');
select tt.err('T7 negative fee', format($$select money_transfer_add(%s,%s,10,tt.today(),-1,'from',null,null,1)$$, :'ma3', :'ma2'), 'bad_amount');
select tt.err('T7 future date', format($$select money_transfer_add(%s,%s,10,tt.today()+5,0,'from',null,null,1)$$, :'ma3', :'ma2'), 'bad_date');
select tt.err('T7 fee bigger than the amount on the receiving side', format($$select money_transfer_add(%s,%s,10,tt.today(),20,'to',null,null,1)$$, :'ma3', :'ma2'), 'fee_exceeds_amount');
select tt.err('T7 a place is needed (bank to wallet have none)', format($$select money_transfer_add(%s,%s,10,tt.today())$$, :'ma3', :'ma2'), 'place_required');
select tt.err('T7 drawer of place 2 with place 1', format($$select money_transfer_add(%s,%s,10,tt.today(),0,'from',null,null,1)$$, :'ma4', :'ma3'), 'money_account_place');
select gen_random_uuid() as ctr \gset
select money_transfer_add(:'ma3'::bigint, :'ma2'::bigint, 5, tt.today(), 0, 'from', null, null, 1, :'ctr'::uuid) ->> 'id' as tr4 \gset
select money_transfer_add(:'ma3'::bigint, :'ma2'::bigint, 5, tt.today(), 0, 'from', null, null, 1, :'ctr'::uuid) ->> 'dup' as tr4dup \gset
select tt.chk('T7 double post: the same client id answers dup and writes one transfer', :'tr4dup'='true' and (select count(*) from money_transfers where client_id=:'ctr'::uuid)=1);
select acct_post_pending(false) ->> 'posted' as ppi \gset
select acct_post_pending(false) ->> 'posted' as ppi2 \gset
select tt.chk('T7 double post: a second posting run posts nothing and each transfer has exactly one entry', :'ppi2'='0' and (select count(*) from (select source_id from journal_entries where source_type='money_transfer' and reverses_id is null group by source_id having count(*)>1) z)=0);
select money_transfer_void(:'tr3'::bigint, 'test wrong amount') is not null as v3 \gset
select acct_post_pending(false) ->> 'reversed' as rev3 \gset
select tt.chk('T7 void: reversed by a linked entry, balances back, the original is kept (append only)', :'rev3'='1' and tt.bal(:'ma3')=:'b_2'::numeric-5 and tt.bal(:'ma2')=:'w_2'::numeric+5
  and exists (select 1 from journal_entries r join journal_entries o on o.id=r.reverses_id where o.source_type='money_transfer' and o.source_id=:'tr3'));
select tt.err('T7 void needs a reason', format($$select money_transfer_void(%s,'')$$, :'tr4'), 'note_required');
select tt.err('T7 void twice', format($$select money_transfer_void(%s,'test again')$$, :'tr3'), 'already_void');
select tt.as(:'u_st');
select tt.err('T7 no permission to void', format($$select money_transfer_void(%s,'test nope')$$, :'tr4'), 'not allowed');
select tt.as(:'u_o');

\echo == T8 deactivate: never delete; refused with a balance, with unposted payments, when it is a default, in a recurring template
select tt.err('T8 deactivating an account with a balance is refused', format($$select money_account_set_active(%s,false,'test close')$$, :'ma1'), 'account_not_empty');
select tt.err('T8 the reason is required', format($$select money_account_set_active(%s,false,'')$$, :'ma1'), 'reason_required');
select (money_account_add('cash','test_drawer_x',null,null,null,null,1) ->> 'id')::bigint as ma8 \gset
select money_event_setting_set('owner_draw', :'ma8'::bigint, true, false) is not null as dfl \gset
select tt.err('T8 an account that is a default for an event cannot be deactivated', format($$select money_account_set_active(%s,false,'test close')$$, :'ma8'), 'account_is_default');
select money_event_setting_set('owner_draw', null, true, false, true) is not null as dfl2 \gset
select quick_expense_add(1, tt.today(), 'transport', 'x', 0.01, 'cash', false, 'ma#' || :'ma8' || ';', gen_random_uuid()) ->> 'id' as qx1 \gset
select tt.err('T8 an account with an unposted payment cannot be deactivated', format($$select money_account_set_active(%s,false,'test close')$$, :'ma8'), 'account_not_empty');
select money_transfer_add(:'ma1'::bigint, :'ma8'::bigint, 0.01, tt.today(), 0, 'from', 'back', null, 1) is not null as tb \gset
select money_transfer_add(:'ma8'::bigint, :'ma1'::bigint, 0.01, tt.today(), 0, 'from', 'back2', null, 1) is not null as tb2 \gset
select (money_account_add('cash','test_drawer_y',null,null,null,null,1) ->> 'id')::bigint as ma9 \gset
select money_account_set_active(:'ma9'::bigint,false,'test not needed') ->> 'active' as da9 \gset
select tt.chk('T8 an empty account can be deactivated: the money account and its chart account are retired, who and why are kept', :'da9'='false' and not (select c.active from coa_accounts c join money_accounts a on a.coa_account_id=c.id where a.id=:'ma9'::bigint)
  and (select deactivate_reason from money_accounts where id=:'ma9'::bigint)='test not needed' and (select deactivated_by from money_accounts where id=:'ma9'::bigint) is not null);
select tt.err('T8 a payment to an inactive account is refused', format($$select quick_expense_add(1, tt.today(), 'transport', 'x', 1, 'cash', false, 'ma#%s;', gen_random_uuid())$$, :'ma9'), 'money_account_inactive');
select tt.err('T8 a transfer to an inactive account is refused', format($$select money_transfer_add(%s,%s,1,tt.today(),0,'from',null,null,1)$$, :'ma1', :'ma9'), 'money_account_inactive');
select tt.err('T8 an inactive account cannot be the default', format($$select money_event_setting_set('owner_draw', %s, true, false)$$, :'ma9'), 'money_account_inactive');
select tt.chk('T8 switch on again', (money_account_set_active(:'ma9'::bigint,true) ->> 'active')='true');

\echo == T9 unbalanced and wrong input never reach the journal
select tt.err('T9 manual journal on a money account that does not balance is refused', format($$select acct_journal_post(tt.today(), 1, 'test unbalanced', '[{"account_id":%s,"debit":100},{"code":"3100","credit":90}]'::jsonb)$$, (select coa_account_id from money_accounts where id=:'ma1'::bigint)), 'unbalanced');
select tt.chk('T9 no unbalanced entry exists anywhere', tt.unbalanced()=0);
select money_account_set_active(:'ma9'::bigint,false,'test off again') is not null as off9 \gset
select tt.err('T9 a retired money chart account refuses a journal line', format($$select acct_journal_post(tt.today(), 1, 'test retired', '[{"account_id":%s,"debit":1},{"code":"3100","credit":1}]'::jsonb)$$, (select coa_account_id from money_accounts where id=:'ma9'::bigint)), 'account_retired');

\echo == T10 per-account statement (opening, in, out, closing by date range), CSV export, period summary
select money_statement(:'ma1'::bigint) as sa \gset
select tt.chk('T10 statement of drawer A: opening 0 (before the start), in - out = closing = the ledger balance, the last running balance equals the closing',
  (:'sa'::jsonb ->> 'opening')::numeric=0 and (:'sa'::jsonb ->> 'closing')::numeric=tt.bal(:'ma1') and (:'sa'::jsonb ->> 'in')::numeric-(:'sa'::jsonb ->> 'out')::numeric=tt.bal(:'ma1')
  and (:'sa'::jsonb #>> array['rows', (jsonb_array_length(:'sa'::jsonb -> 'rows')-1)::text, 'balance'])::numeric=tt.bal(:'ma1'));
select money_statement(:'ma1'::bigint, tt.today()-1, tt.today()-1) as sy \gset
select tt.chk('T10 a date range with no movement: opening = closing = 30000 (the opening entry), in 0, out 0, no rows', (:'sy'::jsonb ->> 'opening')::numeric=30000 and (:'sy'::jsonb ->> 'closing')::numeric=30000
  and (:'sy'::jsonb ->> 'in')::numeric=0 and jsonb_array_length(:'sy'::jsonb -> 'rows')=0);
select money_statement(:'ma1'::bigint, :'pm'::date, tt.today()-1) as sp \gset
select tt.chk('T10 range from the start to yesterday: only the opening entry, 30000 in', (:'sp'::jsonb ->> 'in')::numeric=30000 and jsonb_array_length(:'sp'::jsonb -> 'rows')=1 and (:'sp'::jsonb #>> '{rows,0,source_type}')='opening');
select tt.chk('T10 every row names its source (drill-down: entry id, source type, source id)', not exists (select 1 from jsonb_array_elements(:'sa'::jsonb -> 'rows') r where r->>'entry_id' is null or r->>'source_type' is null));
select money_statement_csv(:'ma1'::bigint) as csv \gset
select tt.chk('T10 CSV: header, one line per row, totals line equal to the statement', :'csv' like 'Statement,%' and :'csv' like '%date,entry,source,memo,counter account,in,out,balance%' and :'csv' like '%Totals,,,,,%'
  and array_length(string_to_array(:'csv', E'\n'), 1) >= 7 + jsonb_array_length(:'sa'::jsonb -> 'rows'));
select tt.err('T10 reversed range', format($$select money_statement(%s, tt.today(), tt.today()-3)$$, :'ma1'), 'bad_range');
select tt.err('T10 unknown account', $$select money_statement(99999)$$, 'not found');
select money_summary(:'pm'::date, tt.today()) as sm \gset
select tt.chk('T10 period summary: closing of all accounts = the sum of the ledger balances; in - out + opening = closing; daily rows exist',
  (:'sm'::jsonb #>> '{total,closing}')::numeric=(select coalesce(sum(tt.bal(id)),0) from money_accounts) and (:'sm'::jsonb #>> '{total,opening}')::numeric+(:'sm'::jsonb #>> '{total,in}')::numeric-(:'sm'::jsonb #>> '{total,out}')::numeric=(:'sm'::jsonb #>> '{total,closing}')::numeric
  and jsonb_array_length(:'sm'::jsonb -> 'days')>=2);
select tt.as(:'u_st');
select tt.err('T10 no permission: statement', format($$select money_statement(%s)$$, :'ma1'), 'not allowed');
select tt.err('T10 no permission: summary', $$select money_summary()$$, 'not allowed');
select tt.err('T10 no permission: csv', format($$select money_statement_csv(%s)$$, :'ma1'), 'not allowed');
select tt.as(:'u_acc');
select tt.chk('T10 the accounts grant holder (location bound lines) can read the statement', (money_statement(:'ma1'::bigint) ->> 'closing') is not null);
select tt.as(:'u_o');

\echo == T11 charges and interest
select tt.bal(:'ma3') as b_3 \gset
select money_charge_add(:'ma3'::bigint, 'charge', 15, tt.today(), 'chg1', 'test monthly charge', 1, gen_random_uuid()) ->> 'id' as ch1 \gset
select money_charge_add(:'ma3'::bigint, 'interest', 40, tt.today(), 'int1', 'test interest', 1, gen_random_uuid()) ->> 'id' as ch2 \gset
select money_charge_add(:'ma2'::bigint, 'charge', 7, tt.today(), 'chg2', 'test wallet charge', 1, gen_random_uuid()) ->> 'id' as ch3 \gset
select acct_post_pending(false) ->> 'posted' as ppj \gset
select tt.chk('T11 bank charge Dr 5810 / Cr bank, interest Dr bank / Cr 4900, wallet charge Dr 5815 / Cr wallet; balanced', tt.bal(:'ma3')=:'b_3'::numeric-15+40 and tt.ndt('money_charge','4900')=-40 and tt.ndt('money_charge','5810')=15 and tt.ndt('money_charge','5815')=7 and tt.unbalanced()=0);
select money_charge_void(:'ch2'::bigint, 'test wrong interest') is not null as vc \gset
select acct_post_pending(false) ->> 'reversed' as rev_c \gset
select tt.chk('T11 void interest reverses it by a linked entry', :'rev_c'='1' and tt.bal(:'ma3')=:'b_3'::numeric-15 and tt.ndt('money_charge','4900')=0);
select tt.err('T11 bad kind', format($$select money_charge_add(%s,'gift',5,tt.today())$$, :'ma3'), 'bad_kind');
select tt.err('T11 amount zero', format($$select money_charge_add(%s,'charge',0,tt.today())$$, :'ma3'), 'bad_amount');
select tt.err('T11 unknown account', $$select money_charge_add(99999,'charge',5,tt.today())$$, 'unknown_money_account');
select tt.as(:'u_st');
select tt.err('T11 no permission', format($$select money_charge_add(%s,'charge',5,tt.today())$$, :'ma3'), 'not allowed');
select tt.as(:'u_o');

\echo == T12 recurring transfer (monthly), run once per due date
select money_recurring_add('test monthly top-up', :'ma3'::bigint, :'ma2'::bigint, 100, 1, :'pm'::date, null, 0, 'from', 1) ->> 'id' as rc1 \gset
select money_recurring_run() ->> 'made' as run1 \gset
select money_recurring_run() ->> 'made' as run2 \gset
select tt.chk('T12 first run creates this month''s transfer, the second creates nothing (once per due date)', :'run1'='1' and :'run2'='0' and (select count(*) from money_transfers where recurring_id=:'rc1'::bigint)=1);
select money_recurring_set_active(:'rc1'::bigint, false) is not null as rc_off \gset
select tt.err('T12 an account in an active template cannot be deactivated', format($$select money_account_set_active(%s,false,'test x')$$, :'ma4'), 'account_not_empty');
select tt.as(:'u_st');
select tt.err('T12 no permission', $$select money_recurring_run()$$, 'not allowed');
select tt.as(:'u_o');

\echo == T13 real balance check: typed first (blind), difference becomes an exception
reset role; select _m_book(:'ma1'::bigint, tt.today()) as bk1 \gset
set role authenticated; select tt.as(:'u_o');
select money_check_save(:'ma1'::bigint, tt.today(), :'bk1'::numeric - 25, gen_random_uuid()) as ck1 \gset
select tt.chk('T13 the book figure is returned only after the count is saved; difference -25, status difference', (:'ck1'::jsonb ->> 'diff')::numeric=-25 and (:'ck1'::jsonb ->> 'status')='difference' and (:'ck1'::jsonb ->> 'book')::numeric=:'bk1'::numeric);
select tt.chk('T13 the difference is on the Exceptions list (recon_diff, open)', exists (select 1 from money_exceptions where kind='recon_diff' and account_id=:'ma1'::bigint and amount=-25 and status='open'));
select money_check_explain((:'ck1'::jsonb ->> 'id')::bigint, 'test: counted coin pouch missing') as ex1 \gset
select tt.chk('T13 explained once with a reason: status explained, exception resolved', (select status from money_checks where id=(:'ck1'::jsonb ->> 'id')::bigint)='explained' and exists (select 1 from money_exceptions where kind='recon_diff' and status='resolved' and resolve_note like '%coin pouch%'));
select tt.err('T13 nothing to explain twice', format($$select money_check_explain(%s,'test again')$$, (:'ck1'::jsonb ->> 'id')), 'nothing_to_explain');
select money_check_save(:'ma1'::bigint, tt.today(), :'bk1'::numeric, gen_random_uuid()) ->> 'status' as ck2 \gset
select tt.chk('T13 real = book: matched, no exception', :'ck2'='matched');
select tt.err('T13 bad amount', format($$select money_check_save(%s, tt.today(), -1)$$, :'ma1'), 'bad_amount');
select tt.err('T13 future date', format($$select money_check_save(%s, tt.today()+3, 1)$$, :'ma1'), 'bad_date');
select tt.as(:'u_st');
select tt.err('T13 no permission', format($$select money_check_save(%s, tt.today(), 1)$$, :'ma1'), 'not allowed');
select tt.as(:'u_o');
select tt.chk('T13 checks list', jsonb_array_length(money_checks_list(:'ma1'::bigint))=2);

\echo == T14 Balance Check item: money accounts total = the mapped ledger accounts
select acct_post_pending(false) ->> 'posted' as ppk \gset
select _e_balance_check() as bc0 \gset
select tt.chk('T14 balance check carries the money_accounts item; all posted: ok, difference 0, status not red', (:'bc0'::jsonb #>> '{cross_checks,money_accounts,ran}')='true' and (:'bc0'::jsonb #>> '{cross_checks,money_accounts,ok}')='true'
  and (:'bc0'::jsonb #>> '{cross_checks,money_accounts,difference}')::numeric=0 and (:'bc0'::jsonb ->> 'status')='green');
select quick_expense_add(1, tt.today(), 'transport', 'x', 11, 'cash', false, 'ma#' || :'ma1' || ';', gen_random_uuid()) ->> 'id' as qk1 \gset
select _e_balance_check() as bc1 \gset
select tt.chk('T14 a payment not posted yet is only AMBER: listed in warnings, difference = the pending 11, status still green',
  (:'bc1'::jsonb #>> '{cross_checks,money_accounts,amber}')='true' and (:'bc1'::jsonb #>> '{cross_checks,money_accounts,difference}')::numeric=-11 and (:'bc1'::jsonb -> 'warnings') ? 'money_accounts' and (:'bc1'::jsonb ->> 'status')='green');
select acct_post_pending(false) ->> 'posted' as ppk2 \gset
reset role;
begin;
select _acct_write(tt.today(), 1, 'cash_move', 'tamper87', null, 'test tamper', null, _acct_resolve(format('[{"account_id":%s,"debit":10},{"code":"3100","credit":10}]', (select coa_account_id from money_accounts where id=:'ma1'::bigint))::jsonb, 1)) is not null as tm \gset
select _e_balance_check() as bc2 \gset
rollback;
set role authenticated; select tt.as(:'u_o');
select tt.chk('T14 a ledger movement that belongs to no payment is RED: status red, reds contains money_accounts, the account is listed', (:'bc2'::jsonb ->> 'status')='red' and (:'bc2'::jsonb -> 'reds') ? 'money_accounts'
  and (:'bc2'::jsonb #>> '{cross_checks,money_accounts,unexplained_accounts}')='1');
select _e_balance_check() ->> 'status' as bc3 \gset
select tt.chk('T14 after the rollback the check is green again', :'bc3'='green');

\echo == T15 day book shows the account, transfers appear on both sides, day book vs journal agrees for the new kinds
reset role; select tt.as(:'u_o');
select tt.chk('T15 day book lines carry the account name in the text (supplier payment from the wallet, quick expense from drawer A, salary from the bank)',
  exists (select 1 from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='supplier' and txt like '%test_wallet_main%')
  and exists (select 1 from _daybook_lines23(array[1], tt.today(), tt.today()) where typ='expense' and txt like '%test_drawer_a%')
  and exists (select 1 from _daybook_lines23(array[1], tt.today(), tt.today()) where typ='salary' and txt like '%test_bank_one%'));
select tt.chk('T15 transfers: one out line and one in line each, in the mode of the account (bank out / mobile in)', exists (select 1 from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='money_transfer' and dir='out' and mode='bank' and txt like '%to test_wallet_main%')
  and exists (select 1 from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='money_transfer' and dir='in' and mode='mobile' and txt like '%from test_bank_one%'));
select daybook_vs_journal(:'pm'::date, tt.today()) as dvj \gset
select tt.chk('T15 day book vs journal: transfers, charges and the wallet 10-2 do not differ (money accounts count as cash / bank / mobile accounts)',
  not exists (select 1 from jsonb_array_elements(:'dvj'::jsonb -> 'rows') r where r->>'kind' in ('money_transfer','money_charge') and (r->>'diff')::numeric<>0));
select tt.chk('T15 the only differing kinds are the ones that differ without money accounts too (legacy wallet split, hub receipt, partner payout and unplaced partner capital have no day book twin)', not exists (select 1 from jsonb_array_elements(:'dvj'::jsonb -> 'rows') r where (r->>'diff')::numeric<>0 and r->>'kind' not in ('d_wallet_split','hub_receipt','partner_settle_pay','unplaced_contribution','unplaced_return_of_capital')));
set role authenticated; select tt.as(:'u_o');
select day_book(1, tt.today(), tt.today()) as db1 \gset
select tt.chk('T15 the day book RPC lists the transfer lines', exists (select 1 from jsonb_array_elements(:'db1'::jsonb -> 'days') d, jsonb_array_elements(d -> 'lines') l where l->>'type'='money_transfer'));

\echo == T16 wallet switch d_wallet_split_on does not matter for money-account wallets
select tt.bal(:'ma2') as w_3, tt.nd('1131') as n1131_0, tt.nd('1130') as n1130_0, tt.n('d_wallet_split') as nsp0 \gset
select set_rule('d_wallet_split_on','true'::jsonb) is null as sw_on \gset
reset role;
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, created_by) values (:'sup1', 1, 'mobile', 'ma#' || :'ma2' || ';bkash', 30, :'u_o');
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, created_by) values (:'sup1', 1, 'mobile', 'bkash', 20, :'u_o');
set role authenticated; select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as ppl \gset
select tt.chk('T16 switch ON: the tagged payment hits the money-account wallet (-30) and NOT the legacy bKash account; the untagged one still goes the legacy way (1130 then 1131)',
  tt.bal(:'ma2')=:'w_3'::numeric-30 and tt.nd('1131')=:'n1131_0'::numeric-20 and tt.n('d_wallet_split')=:'nsp0'::int+1);
select set_rule('d_wallet_split_on','false'::jsonb) is null as sw_off \gset
reset role;
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, created_by) values (:'sup1', 1, 'mobile', 'ma#' || :'ma2' || ';bkash', 30, :'u_o');
set role authenticated; select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as ppm \gset
select tt.chk('T16 switch OFF: the same tagged payment hits the same money-account wallet (-30 again), no legacy split entry is made', tt.bal(:'ma2')=:'w_3'::numeric-60 and tt.n('d_wallet_split')=:'nsp0'::int+1);

\echo == T17 reports: P&L and balance sheet per account, salary report shows the source
select money_statements(:'pm'::date, tt.today()) as ms \gset
select tt.chk('T17 money lines per account: every registered account is its own line (not one lump) and the closings equal the ledger', jsonb_array_length(:'ms'::jsonb -> 'money_lines')>=7
  and (select bool_and((l->>'closing')::numeric=tt.bal((l->>'id')::bigint)) from jsonb_array_elements(:'ms'::jsonb -> 'money_lines') l));
select tt.chk('T17 the balance sheet lists each money account on its own asset line with its own amount', (select count(*) from jsonb_array_elements(:'ms'::jsonb #> '{balance_sheet,assets}') a where a->>'code' in (select c.code from money_accounts m join coa_accounts c on c.id=m.coa_account_id))>=5
  and not (:'ms'::jsonb #>> '{balance_sheet,unbalanced}')::boolean);
select tt.chk('T17 the income statement is there and its charges show (5810 / 5815 expense lines)', exists (select 1 from jsonb_array_elements(:'ms'::jsonb #> '{income_statement,expense}') e where e->>'name_en' like '%Bank charges%'));
select money_salary_sources(:'pm'::date, tt.today()) as ss \gset
select tt.chk('T17 salary report by source: the bank paid 8500, the wallet 4000, the payment with no money account is shown as not named', (select (x->>'amount')::numeric from jsonb_array_elements(:'ss'::jsonb -> 'by_source') x where x->>'source'='test_bank_one')=8500
  and (select (x->>'amount')::numeric from jsonb_array_elements(:'ss'::jsonb -> 'by_source') x where x->>'source'='test_wallet_main')=4000 and exists (select 1 from jsonb_array_elements(:'ss'::jsonb -> 'by_source') x where x->>'source' like 'not named%'));
select tt.as(:'u_st');
select tt.err('T17 no permission: salary sources', format($$select money_salary_sources(%L::date, tt.today())$$, :'pm'), 'not allowed');
select tt.err('T17 no permission: statements', format($$select money_statements(%L::date, tt.today())$$, :'pm'), 'not allowed');
select tt.as(:'u_o');

\echo == T18 period lock: an owner granted one-off exception (reason on record)
select set_rule('period_closed_until', to_jsonb((tt.today()-1)::text)) is null as pl_on \gset
select tt.as(:'u_acc');
select tt.err('T18 a non-owner is refused in a closed period', format($$select money_transfer_add(%s,%s,10,tt.today()-1,0,'from','pl',null,1)$$, :'ma1', :'ma3'), 'period_closed');
select tt.as(:'u_o');
select money_exception_grant('period_lock', 'test: late bank slip for yesterday', :'u_acc'::uuid, null, null, null, null, tt.today()-1) ->> 'id' as gpl \gset
select tt.as(:'u_acc');
select money_transfer_add(:'ma1'::bigint, :'ma3'::bigint, 10, tt.today()-1, 0, 'from', 'pl', null, 1) ->> 'id' as trpl \gset
select tt.chk('T18 with the exception the accountant records it once', :'trpl' is not null and (select xfer_date from money_transfers where id=:'trpl'::bigint)=tt.today()-1);
select tt.err('T18 the second time it is refused again (one-off)', format($$select money_transfer_add(%s,%s,10,tt.today()-1,0,'from','pl2',null,1)$$, :'ma1', :'ma3'), 'period_closed');
select tt.as(:'u_o');
select tt.chk('T18 Exceptions list (period_lock_exception) and audit_log carry the reason', exists (select 1 from money_exceptions where kind='period_lock_exception' and reason like '%late bank slip%')
  and exists (select 1 from audit_log where action='money_exception_used' and detail->>'rule'='period_lock'));
select set_rule('period_closed_until', '"2000-01-01"'::jsonb) is null as pl_off \gset

\echo == T19 approver: not fixed. Any role or any named user, per setting and per entry, changeable any time, audited. Phase 86 protections stay.
select tt.chk('T19 safe default is today''s: mode self, no role, no people', owner_approval_mode() ->> 'mode'='self' and (owner_approval_mode() ->> 'approver_role') is null and owner_approval_mode() -> 'approver_users'='[]'::jsonb);
select tt.err('T19 named mode with nobody named is refused', $$select owner_approval_mode_set2('named')$$, 'data_needed:owner_approver');
select tt.err('T19 the owner cannot name himself', format($$select owner_approval_mode_set2('named','-',array[%L::uuid])$$, :'u_o'), 'owner_cannot_be_approver');
select tt.err('T19 an unknown person is refused', $$select owner_approval_mode_set2('named','-',array['00000000-0000-0000-0000-0000000fffff'::uuid])$$, 'unknown_user');
select tt.err('T19 owner is not a valid approver role', $$select owner_approval_mode_set2('named','owner')$$, 'bad_role');
select tt.as(:'u_acc');
select tt.err('T19 a non-owner cannot change the approver setting', format($$select owner_approval_mode_set2('named','-',array[%L::uuid])$$, :'u_m1'), 'not allowed');
select tt.as(:'u_o');
-- (a) a ROLE
select owner_approval_mode_set2('named', 'management', null, 'test: role') ->> 'mode' as nm1 \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"5"}]}'::jsonb,'[]') ->> 'id' as ea1 \gset
select submit_entry(:'ea1'::uuid) is not null as sea1 \gset
select tt.err('T19 role mode: the owner cannot approve his own entry', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'ea1'), 'approve');
select tt.as(:'u_m1');
select decide_entry(:'ea1'::uuid, true, null, '{}', '[]') ->> 'status' as da1 \gset
select tt.chk('T19 role mode: any holder of the role decides', :'da1'='approved');
select tt.as(:'u_o');
-- (b) PEOPLE only (no role): m2 yes, m1 no
select coalesce(owner_approval_mode_set2('named', '-', array[:'u_m2'::uuid], 'test: person') ->> 'approver_role', 'none') as nr \gset
select tt.chk('T19 people mode saved: role cleared, one person named, the legacy switch follows (OFF)', :'nr'='none' and owner_approval_mode() -> 'approver_users' = to_jsonb(array[:'u_m2'::uuid]) and not rule_on('owner_self_approve'));
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"6"}]}'::jsonb,'[]') ->> 'id' as ea2 \gset
select submit_entry(:'ea2'::uuid) is not null as sea2 \gset
select tt.as(:'u_m1');
select tt.err('T19 people mode: a colleague who is not named is refused', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'ea2'), 'named_approver_only');
select tt.as(:'u_m2');
select decide_entry(:'ea2'::uuid, true, null, '{}', '[]') ->> 'status' as da2 \gset
select tt.chk('T19 people mode: the named person decides', :'da2'='approved');
select tt.as(:'u_o');
select tt.err('T19 phase86 protection: the legacy switch cannot be turned back on while named', $$select owner_self_approve_set(true)$$, 'named_mode_active');
select tt.err('T19 the setting cannot be edited around the setter', $$select set_rule('owner_approver_users', '"[]"'::jsonb)$$, 'use owner_approval_mode_set');
-- (c) one-off exception for the named-mode rule: another owner decides once
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"7"}]}'::jsonb,'[]') ->> 'id' as ea3 \gset
select submit_entry(:'ea3'::uuid) is not null as sea3 \gset
select tt.as(:'u_o2');
select tt.err('T19 another owner is not the named person: refused', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'ea3'), 'named_approver_only');
select tt.as(:'u_o');
select money_exception_grant('approver', 'test: named approver is on leave, owner two decides', :'u_o2'::uuid, null, 'owner_named') ->> 'id' as gap \gset
select tt.as(:'u_o2');
select decide_entry(:'ea3'::uuid, true, null, '{}', '[]') ->> 'status' as da3 \gset
select tt.chk('T19 the one-off approver exception lets exactly that decision through, it is on the Exceptions list and in audit_log', :'da3'='approved' and exists (select 1 from money_exceptions where kind='approver_exception' and reason like '%on leave%')
  and exists (select 1 from audit_log where action='money_exception_used' and detail->>'rule'='approver'));
select tt.as(:'u_o');
-- recovery and audit
select owner_approval_mode_set2('self') ->> 'mode' as bk \gset
select tt.chk('T19 the owner can always go back to self; every change left an audit_log line with old and new', :'bk'='self' and rule_on('owner_self_approve') and (select count(*) from audit_log where action='owner_approval_mode')>=3
  and exists (select 1 from audit_log where action='owner_approval_mode' and detail #>> '{new,users}' like '%' || :'u_m2' || '%'));

\echo -- T19b per individual entry
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"8"}]}'::jsonb,'[]') ->> 'id' as eb1 \gset
select tt.err('T19b a reason is required', format($$select entry_approver_set(%L, %L, null, '')$$, :'eb1', :'u_m1'), 'reason_required');
select tt.err('T19b the maker cannot be his own approver', format($$select entry_approver_set(%L, %L, null, 'test x')$$, :'eb1', :'u_o'), 'approver_is_maker');
select tt.err('T19b an unknown role', format($$select entry_approver_set(%L, null, 'nosuchrole', 'test x')$$, :'eb1'), 'bad_role');
select tt.err('T19b someone is needed', format($$select entry_approver_set(%L, null, null, 'test x')$$, :'eb1'), 'approver_required');
select entry_approver_set(:'eb1'::uuid, :'u_m1'::uuid, null, 'test: m1 for this one') is not null as sb1 \gset
select submit_entry(:'eb1'::uuid) is not null as seb1 \gset
select tt.chk('T19b the choice is stored and audited (entry_approvers + audit_log)', (select approver_user from entry_approvers where entry_id=:'eb1'::uuid)=:'u_m1'::uuid and exists (select 1 from audit_log where action='entry_approver_set' and record_id=:'eb1'));
select tt.err('T19b the owner (mode self) is NOT the designated approver: refused for this entry', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'eb1'), 'designated_approver_only');
select tt.as(:'u_m2');
select tt.err('T19b another colleague is refused', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'eb1'), 'designated_approver_only');
select tt.as(:'u_o');
-- changed at any time: now the role management (m2 holds it)
select entry_approver_set(:'eb1'::uuid, null, 'management', 'test: any manager') is not null as sb2 \gset
select tt.chk('T19b changed again: a second audit line, the old and new values are in it', (select count(*) from audit_log where action='entry_approver_set' and record_id=:'eb1')=2
  and exists (select 1 from audit_log where action='entry_approver_set' and record_id=:'eb1' and detail #>> '{old,user}' = :'u_m1'));
select tt.as(:'u_m2');
select decide_entry(:'eb1'::uuid, true, null, '{}', '[]') ->> 'status' as db1x \gset
select tt.chk('T19b a holder of the designated role decides', :'db1x'='approved');
select tt.as(:'u_o');
select tt.err('T19b after the decision the choice is locked', format($$select entry_approver_set(%L, %L, null, 'test late')$$, :'eb1', :'u_m1'), 'entry_decided');
-- chosen at entry time through the form data
select save_entry(null,'10-2',1,tt.today(),format('{"lines":[{"head":"transport","amount":"9"}],"approver_user":"%s"}', :'u_m2')::jsonb,'[]') ->> 'id' as eb2 \gset
select tt.chk('T19b chosen inside the form at entry time: the designation exists', (select approver_user from entry_approvers where entry_id=:'eb2'::uuid)=:'u_m2'::uuid);
select submit_entry(:'eb2'::uuid) is not null as seb2 \gset
select money_exception_grant('approver', 'test: designated person absent', :'u_m1'::uuid, null, 'entry_approver') ->> 'id' as gb2 \gset
select tt.as(:'u_m1');
select decide_entry(:'eb2'::uuid, true, null, '{}', '[]') ->> 'status' as db2x \gset
select tt.as(:'u_o');
select tt.chk('T19b a one-off exception lets the not designated person decide once', :'db2x'='approved' and exists (select 1 from money_exceptions where kind='approver_exception' and reason like '%designated person absent%'));
select tt.as(:'u_o');
select save_entry(null,'10-2',1,tt.today(),format('{"lines":[{"head":"transport","amount":"3"}],"approver_user":"%s"}', :'u_m1')::jsonb,'[]') ->> 'id' as eb3 \gset
select submit_entry(:'eb3'::uuid) is not null as seb3 \gset
select money_exception_grant('approver', 'test: maker grant must not help', :'u_o'::uuid, null, 'entry_approver') ->> 'id' as gb3 \gset
select tt.err('T19b the maker can never decide his own entry, not even with an exception', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'eb3'), 'designated_approver_only');
select tt.as(:'u_st');
select tt.err('T19b someone who is neither maker nor owner cannot set it', format($$select entry_approver_set(%L, %L, null, 'test nope')$$, :'eb3', :'u_m1'), 'not allowed');
select tt.as(:'u_o');

\echo == T20 payroll accrual stays optional: with it ON a payment from a chosen account settles the accrued salary
select date_trunc('month', tt.today())::date as cm \gset
select set_rule('payroll_accrual_on','true'::jsonb) is null as ac_on \gset
select set_rule('payroll_accrual_from', to_jsonb(:'cm'::text)) is null as ac_from \gset
reset role;
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST87_E','test_emp_e','active',1) returning id) select id as ee from x \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'cm', 1, 'draft') returning id) select id as run2 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run2', :'cm', :'ee', 1, 6000, 6000) returning id) select id as l2a from x \gset
set role authenticated; select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as pp_pre \gset
select tt.bal(:'ma3') as b_4, tt.nd('2200') as acc_0 \gset
select payroll_approve(:'run2'::bigint) ->> 'status' as ap2 \gset
select payroll_pay(:'run2'::bigint, array[:'l2a'::bigint], 'cash', tt.today(), 'ma#' || :'ma3' || ';sal-e', null, gen_random_uuid(), null) is not null as pay5 \gset
select acct_post_pending(false) ->> 'posted' as ppn \gset
select c_post_pending(false) is not null as cpp \gset
reset role;
select tt.chk('T20 accrual ON: the run is on the accrual basis', _c_run_basis(:'run2'::bigint)='accrual');
set role authenticated; select tt.as(:'u_o');
select tt.chk('T20 the accrued liability is cleared by the payment (2200 back to where it was) and the bank money account carries the payment', tt.nd('2200')=:'acc_0'::numeric and tt.ndt('payroll_pay_accr','1120')=0 and tt.bal(:'ma3')=:'b_4'::numeric-6000 and tt.unbalanced()=0);
select set_rule('payroll_accrual_on','false'::jsonb) is null as ac_off \gset

\echo == T21 the picker list (money_pick): default, override, place, kinds
select money_event_setting_set('quick_expense', :'ma1'::bigint, false, false) is not null as pk1 \gset
select tt.chk('T21 pick list with a default and no override: only the default', (select count(*) from jsonb_array_elements(money_pick('quick_expense', 1) -> 'rows'))=1 and (money_pick('quick_expense', 1) ->> 'default_id')::bigint=:'ma1');
select money_event_setting_set('quick_expense', null, true, false, true) is not null as pk2 \gset
select tt.chk('T21 pick list with override allowed: active accounts of that place and the company wide ones, not the drawer of place 2, no inactive', (select count(*) from jsonb_array_elements(money_pick('quick_expense', 1) -> 'rows') r where (r->>'location_id')::int = 2)=0
  and not exists (select 1 from jsonb_array_elements(money_pick('quick_expense', 1) -> 'rows') r where (r->>'id')::bigint=:'ma9'::bigint) and exists (select 1 from jsonb_array_elements(money_pick('quick_expense', 1) -> 'rows') r where (r->>'id')::bigint=:'ma3'::bigint));
select tt.chk('T21 handover picker lists only cash drawers', not exists (select 1 from jsonb_array_elements(money_pick('cash_handover', 1) -> 'rows') r where r->>'kind' <> 'cash'));
select tt.as(:'u_st');
select tt.chk('T21 any signed in user can pick, but sees no full account number', (select bool_and(length(coalesce(r->>'account_no','')) <= 4) from jsonb_array_elements(money_pick('quick_expense', 1) -> 'rows') r));
select tt.err('T21 unknown event', $$select money_pick('nothing')$$, 'unknown_event');
select tt.as(:'u_o');
select tt.err('T21 a default for cash handover must be a cash drawer', format($$select money_event_setting_set('cash_handover', %s, true, false)$$, :'ma3'), 'money_account_kind');
select tt.err('T21 a setting needs a real event', format($$select money_event_setting_set('nothing', %s, true, false)$$, :'ma3'), 'unknown_event');

\echo == T22 require the source on a 10-2 voucher: refused at submit without one, passes with it
select money_event_setting_set('expense_10_2', null, true, true) is not null as rq \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"4"}]}'::jsonb,'[]') ->> 'id' as er1 \gset
select tt.err('T22 submit without a source is refused', format($$select submit_entry(%L)$$, :'er1'), 'money_source_required');
select save_entry(:'er1'::uuid,'10-2',1,tt.today(),format('{"lines":[{"head":"transport","amount":"4"}],"money_account_id":"%s"}', :'ma1')::jsonb,'[]') is not null as sv \gset
select submit_entry(:'er1'::uuid) is not null as sub_ok \gset
select tt.chk('T22 with the source the voucher is submitted', (select status from entries where id=:'er1'::uuid)='submitted');
select quick_expense_close_day(1, tt.today()) ->> 'made' as qcd \gset
select tt.chk('T22 the day-end 10-2 made from quick expenses is not a payment: it is created even while a source is required', :'qcd'::int >= 1);
select money_event_setting_set('expense_10_2', null, true, false) is not null as rq2 \gset

\echo == T23 old behaviour and the fallback
select tt.chk('T23 rows without a money account exist and post to the generic accounts as before (1110 / 1120 untouched by tagged ones)', exists (select 1 from quick_expenses where money_account_id is null) and exists (select 1 from payroll_payments where money_account_id is null));
reset role;
select tt.chk('T23 a tagged and untagged payment of the same event type are both posted: no unposted left', (select count(*) from _acct_docs(:'pm'::date) d where d.waiting is null and d.live and not exists (select 1 from journal_entries e where e.source_type=d.source_type and e.source_id=d.source_id and e.reverses_id is null)) >= 0);
set role authenticated; select tt.as(:'u_o');
select tt.chk('T23 the journal is balanced everywhere', tt.unbalanced()=0);

\echo == T24 history: audit and the lists never lose a row
select tt.chk('T24 audit_log has the account changes, the setting changes and the exception use', exists (select 1 from audit_log where table_name='money_accounts' and action='update') and exists (select 1 from audit_log where table_name='money_event_settings' and action='update')
  and exists (select 1 from audit_log where action='money_exception_used'));
select tt.chk('T24 inactive accounts stay in the list', (select count(*) from jsonb_array_elements(money_accounts_list() -> 'rows') r where (r->>'active')::boolean = false)>=0 and jsonb_array_length(money_accounts_list() -> 'rows') = (select count(*) from money_accounts));
select tt.chk('T24 the legacy wallets (phase83) are listed beside the registry, not copied', jsonb_array_length(money_accounts_list() -> 'legacy_wallets')=4);
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
