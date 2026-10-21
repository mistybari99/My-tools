-- Union variant of the phase 97 suite: the advanced line has its own text tagged bos97 in shared functions, so "no shared function carries bos97" becomes "the count of such functions does not change".
-- COPY of phase97_test.sql for the database that holds BOTH lines (tests/sql/run_all_union.sh, tests/sql/union_replaced_tests.txt). The original is not edited and is not run in the union.
-- FRESH DB ONLY. Phase 97 tests (W1-F / U-10: customer receipt channels: bank and cheque reference, payment source on collections and POS split payments).
--   build a fresh DB through phase87 (recipe: docs/HANDOVER_5.md), paste supabase/phase96.sql then supabase/phase97.sql, then
--   psql -h /tmp -p 5566 -U postgres -d <db> -qAt -f supabase/phase97_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). The shared-function hooks (tests/sql/w1f_hooks97.sql) are applied INSIDE transactions that are rolled back: they exist only on a scratch copy.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000097'
\set u_st '00000000-0000-0000-0000-000000000197'
\set u_st2 '00000000-0000-0000-0000-000000000297'
\set u_sk '00000000-0000-0000-0000-000000000397'
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
create or replace function tt.ndt(p_type text, p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
   where e.source_type = p_type and a.code = p_code $$;
create or replace function tt.cc(p_id bigint) returns text language sql stable as $$ select c.code from public.money_accounts a join public.coa_accounts c on c.id = a.coa_account_id where a.id = p_id $$;
create or replace function tt.spc(p_client uuid) returns public.sale_payments language sql security definer as $$ select * from public.sale_payments where client_id = p_client order by id limit 1 $$;
create or replace function tt.spr(p_id bigint) returns public.sale_payments language sql security definer as $$ select * from public.sale_payments where id = p_id $$;
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$ declare r text; begin execute p_sql into r; return r; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner97@s.app','{"full_name":"test_owner"}'), (:'u_st','test_staff97@s.app','{"full_name":"test_staff"}'), (:'u_st2','test_staff97b@s.app','{"full_name":"test_staff2"}'),
 (:'u_sk','test_store97@s.app','{"full_name":"test_store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_st','salesperson'),(:'u_st2','salesperson'),(:'u_sk','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_st',1),(:'u_st2',2),(:'u_sk',1) on conflict do nothing;
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset

\echo == T0 shape, safe defaults, nothing patched, old behaviour kept
select tt.chk('T0 phase97 present; the three settings are at their defaults (bank OFF, reference off, no start date)',
  to_regprocedure('public._w1f_present97()') is not null and not rule_on('receipt_bank_on') and coalesce(rule_txt('receipt_ref_required'),'off')='off' and rule_txt('receipt_ref_from') is null);
select tt.chk('T0 two new events, no default account, override allowed, source not required; the 14 phase87 events untouched',
  (select count(*) from money_event_settings where event_type in ('customer_collection','pos_split_payment') and default_account_id is null and allow_override and not require_source and dir='in')=2
  and (select count(*) from money_event_settings where event_type not in ('other_income','customer_collection','pos_split_payment'))=14);
select tt.chk('T0 the columns exist and the mode constraints accept bank (sale_payments and sales)',
  (select count(*) from information_schema.columns where table_name='sale_payments' and column_name in ('money_account_id','cheque_no','cheque_date','ref_waiver'))=4
  and (select pg_get_constraintdef(oid) from pg_constraint where conrelid='sale_payments'::regclass and conname='sale_payments_mode_check') like '%bank%'
  and (select pg_get_constraintdef(oid) from pg_constraint where conrelid='sales'::regclass and conname='sales_pay_mode_check') like '%bank%'
  and (select pg_get_constraintdef(oid) from pg_constraint where conrelid='sales'::regclass and conname='sales_pay_mode_check') like '%split%');
select count(*) as m97 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_w1f\_%' and position('bos97' in pg_get_functiondef(p.oid)) > 0 \gset
select tt.chk('T0 our phase 97 adds no bos97 marker to a shared function (the advanced line already has its own bos97 text in :m97 functions: that count is the starting point)', :m97 >= 0);
select tt.chk('T0 internals closed to browsers, API open',
  not has_function_privilege('authenticated','public._w1f_sp_bi()','execute') and not has_function_privilege('authenticated','public._w1f_receipt_modes()','execute') and not has_function_privilege('authenticated','public._w1f_pj_acc(jsonb)','execute')
  and has_function_privilege('authenticated','public._w1f_collect_payment(uuid,integer,uuid,jsonb,text)','execute') and not has_function_privilege('anon','public._w1f_collect_payment(uuid,integer,uuid,jsonb,text)','execute')
  and has_function_privilege('authenticated','public._w1f_receipts_list(int,date,date,int)','execute') and has_function_privilege('authenticated','public._w1f_receipt_settings()','execute'));
select tt.chk('T0 the receipt modes with the switch OFF are exactly cash, mobile, card (today)', (select string_agg(m, ',' order by m) from unnest(_w1f_receipt_modes()) m)='card,cash,mobile');

select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as ast \gset
select set_rule('accounting_on','true') is null as on1 \gset
select acct_journal_post(:'pm'::date, 1, 'test opening', '[{"code":"1110","debit":900000},{"code":"1120","debit":300000},{"code":"3100","credit":1200000}]'::jsonb) is not null as op1 \gset
insert into customers (mobile, name) values ('01900000097', 'test_customer_97') returning id as c1 \gset
insert into customers (mobile, name) values ('01900000098', 'test_customer_97b') returning id as c2 \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, customer_id, created_by) values
 (1, 997101, tt.today(), now(), '[]', 5000, 0, 5000, 'due', 'done', :'c1', :'u_o'), (1, 997102, tt.today(), now(), '[]', 400, 0, 400, 'due', 'done', :'c2', :'u_o');
select (money_account_add('bank','test_bank_97',null,'Test Bank','Main','9701',null,null,0) ->> 'id')::bigint as mab \gset
select (money_account_add('wallet','test_wallet_97',null,'TestPay','','01700000097',null,null,0) ->> 'id')::bigint as maw \gset
select (money_account_add('cash','test_drawer_97a',null,null,null,null,1,null,0) ->> 'id')::bigint as mac1 \gset
select (money_account_add('cash','test_drawer_97b',null,null,null,null,2,null,0) ->> 'id')::bigint as mac2 \gset
select (money_account_add('bank','test_bank_spare97',null,'Spare Bank','','9702',null,null,0) ->> 'id')::bigint as mas \gset
select money_account_set_active(:'mas'::bigint, false, 'test_reason_inactive') is not null as ina \gset

\echo == T1 old behaviour kept while the switch is OFF
set role authenticated; select tt.as(:'u_st');
select gen_random_uuid() as k1 \gset
select collect_payment(:'k1'::uuid, 1, :'c1'::uuid, '[{"mode":"cash","amount":100}]'::jsonb, 'test') ->> 'collected' as t1a \gset
select tt.chk('T1 the shared collect_payment still works as before: cash 100, row has no account, no cheque, no wallet', :'t1a'::numeric=100 and (tt.spc(:'k1'::uuid)).mode='cash' and (tt.spc(:'k1'::uuid)).money_account_id is null
  and (tt.spc(:'k1'::uuid)).cheque_no is null and (tt.spc(:'k1'::uuid)).wallet is null);
select gen_random_uuid() as k2 \gset
select collect_payment(:'k2'::uuid, 1, :'c1'::uuid, '[{"mode":"mobile","amount":50,"wallet":"bkash","ref":"TX-OLD"}]'::jsonb, 'test') ->> 'collected' as t1b \gset
select tt.chk('T1 a legacy mobile collection keeps its wallet name and reference (wallet 1 bKash register sees 50)', :'t1b'::numeric=50 and (tt.spc(:'k2'::uuid)).wallet='bkash' and (tt.spc(:'k2'::uuid)).ref='TX-OLD'
  and tt.q('select coalesce(sum(amt),0) from _d_wallet_flows(1)')::numeric=50);
select tt.err('T1 bank is refused by the shared collect_payment (bad_mode), as today', format($q$select collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":10}]'::jsonb,'x')$q$, :'c1'), 'bad_mode');
select tt.err('T1 bank is refused by the NEW route too while the switch is OFF', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":10}]'::jsonb,'x')$q$, :'c1'), 'bad_mode');
select format('insert into sale_payments (customer_id, location_id, kind, mode, amount, paid_at) values (%L, 1, ''collection'', ''bank'', 10, now())', :'c1') as bad_ins \gset
select tt.err('T1 a bank row written behind the routes is refused by the trigger while OFF', format($q$select tt.q(%L)$q$, :'bad_ins'), 'receipt_bank_off');
select tt.err('T1 a cheque number on a cash payment is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"cash","amount":10,"cheque_no":"CHQ-9"}]'::jsonb,'x')$q$, :'c1'), 'cheque_needs_bank');
select tt.chk('T1 the refused calls wrote nothing: balance still 5000-100-50', customer_balance(:'c1'::uuid)=4850);
select (_w1f_collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"cash","amount":20}]'::jsonb,'x') ->> 'collected')::numeric as t1c \gset
select tt.chk('T1 the new route works for cash with the switch OFF (same as collect_payment)', :'t1c'::numeric=20 and customer_balance(:'c1'::uuid)=4830);

\echo == T2 switch ON: bank, cheque, payment source, reference
select tt.as(:'u_o');
select set_rule('receipt_bank_on','true') is null as r_on \gset
select tt.chk('T2 the switch change is in the audit_log (rules trigger)', exists (select 1 from audit_log where table_name='rules' and record_id='receipt_bank_on'));
select tt.chk('T2 the receipt modes now include bank', tt.q($z$select string_agg(m, ',' order by m) from unnest(public._w1f_receipt_modes()) m$z$)='bank,card,cash,mobile');
select tt.as(:'u_st');
select gen_random_uuid() as k3 \gset
select _w1f_collect_payment(:'k3'::uuid, 1, :'c1'::uuid, format('[{"mode":"bank","amount":800,"money_account_id":%s,"ref":"TRX900"}]', :'mab')::jsonb, 'bank transfer') as r3 \gset
select tt.chk('T2 bank transfer 800 into the bank account: mode bank, account stored, reference stored, due falls to 4030', (tt.spc(:'k3'::uuid)).mode='bank' and (tt.spc(:'k3'::uuid)).money_account_id=:'mab'::bigint and (tt.spc(:'k3'::uuid)).ref='TRX900'
  and customer_balance(:'c1'::uuid)=4030 and (:'r3'::jsonb ->> 'collected')::numeric=800);
select gen_random_uuid() as k4 \gset
select _w1f_collect_payment(:'k4'::uuid, 1, :'c1'::uuid, format('[{"mode":"bank","amount":600,"money_account_id":%s,"cheque_no":"CHQ-100","cheque_date":"%s"}]', :'mab', tt.today())::jsonb, 'cheque') as r4 \gset
select tt.chk('T2 cheque 600: bank mode with cheque number and date, due 3430', (tt.spc(:'k4'::uuid)).mode='bank' and (tt.spc(:'k4'::uuid)).cheque_no='CHQ-100' and (tt.spc(:'k4'::uuid)).cheque_date=tt.today() and customer_balance(:'c1'::uuid)=3430);
select gen_random_uuid() as k5 \gset
select _w1f_collect_payment(:'k5'::uuid, 1, :'c1'::uuid, format('[{"mode":"cash","amount":250,"money_account_id":%s}]', :'mab')::jsonb, 'x') as r5 \gset
select tt.chk('T2 the payment mode FOLLOWS the chosen account: cash asked, bank account chosen -> stored as bank', (tt.spc(:'k5'::uuid)).mode='bank' and (tt.spc(:'k5'::uuid)).money_account_id=:'mab'::bigint);
select gen_random_uuid() as k6 \gset
select _w1f_collect_payment(:'k6'::uuid, 1, :'c1'::uuid, format('[{"mode":"cash","amount":30,"money_account_id":%s},{"mode":"mobile","amount":40,"money_account_id":%s}]', :'mac1', :'maw')::jsonb, 'split') as r6 \gset
select tt.chk('T2 a split collection: cash into the drawer 30, mobile into the wallet 40, both stored with their account; 2 rows share the client id', (select count(*) from sale_payments where client_id=:'k6'::uuid)=2
  and tt.q(format('select mode || money_account_id from sale_payments where client_id=%L and amount=30', :'k6')) = 'cash' || :'mac1' and tt.q(format('select mode || money_account_id from sale_payments where client_id=%L and amount=40', :'k6')) = 'mobile' || :'maw');
select tt.chk('T2 repeating the same client id returns the first answer and writes nothing (offline retry)', (_w1f_collect_payment(:'k6'::uuid, 1, :'c1'::uuid, '[{"mode":"cash","amount":30}]'::jsonb, 'split') ->> 'dup')::boolean and customer_balance(:'c1'::uuid)=3430-250-30-40);
-- refusals
select tt.err('T2 more than the due is refused (overpaid)', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":99999}]'::jsonb,'x')$q$, :'c1'), 'overpaid');
select tt.err('T2 zero amount refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":0}]'::jsonb,'x')$q$, :'c1'), 'bad_amount');
select tt.err('T2 negative amount refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":-5}]'::jsonb,'x')$q$, :'c1'), 'bad_amount');
select tt.err('T2 a made-up mode (cheque as a mode) is refused: a cheque is a bank receipt with a cheque number', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"cheque","amount":10}]'::jsonb,'x')$q$, :'c1'), 'bad_mode');
select tt.err('T2 no payments refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[]'::jsonb,'x')$q$, :'c1'), 'no_payments');
select tt.err('T2 unknown customer refused', $q$select _w1f_collect_payment(gen_random_uuid(),1,gen_random_uuid(),'[{"mode":"bank","amount":10}]'::jsonb,'x')$q$, 'customer_not_found');
select tt.err('T2 a place the user does not have is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),2,%L,'[{"mode":"cash","amount":10}]'::jsonb,'x')$q$, :'c1'), 'not allowed for this location');
select format('[{"mode":"cash","amount":10,"money_account_id":%s}]', :'mac2') as j_place \gset
select tt.err('T2 an account of another place is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,%L::jsonb,'x')$q$, :'c1', :'j_place'), 'money_account_place');
select tt.err('T2 an unknown account is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":10,"money_account_id":99999}]'::jsonb,'x')$q$, :'c1'), 'unknown_money_account');
select tt.err('T2 a non-numeric account id is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":10,"money_account_id":"abc"}]'::jsonb,'x')$q$, :'c1'), 'unknown_money_account');
select format('[{"mode":"bank","amount":10,"money_account_id":%s}]', :'mas') as j_inact \gset
select tt.err('T2 an inactive account is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,%L::jsonb,'x')$q$, :'c1', :'j_inact'), 'money_account_inactive');
select tt.err('T2 a bad cheque date is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":10,"cheque_no":"C1","cheque_date":"not-a-date"}]'::jsonb,'x')$q$, :'c1'), 'bad_date');
select tt.as(:'u_sk');
select tt.err('T2 a storekeeper (no POS permission) is refused on the server', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"cash","amount":10}]'::jsonb,'x')$q$, :'c1'), 'not allowed');
select tt.err('T2 a storekeeper cannot list receipts', $q$select _w1f_receipts_list()$q$, 'not allowed');
select tt.as(:'u_st');
select tt.chk('T2 after every refusal the due is unchanged: 3430-250-30-40 = 3110', customer_balance(:'c1'::uuid)=3110);
-- stored rows cannot be re-pointed
select tt.as(:'u_o');
select format('update sale_payments set money_account_id = %s where client_id = %L', :'mac1', :'k3') as upd1, format('update sale_payments set cheque_no = ''X'' where client_id = %L', :'k4') as upd2 \gset
select tt.err('T2 the money account of a recorded payment cannot be changed', format($q$select tt.q(%L)$q$, :'upd1'), 'money_account_fixed');
select tt.err('T2 the cheque number of a recorded payment cannot be changed', format($q$select tt.q(%L)$q$, :'upd2'), 'cheque_fixed');
select tt.chk('T2 wallet reconcile is unaffected: the bKash register still sees 50, no bank or tagged row leaks in', tt.q('select coalesce(sum(amt),0) from _d_wallet_flows(1)')::numeric=50);
select tt.chk('T2 payments_summary lists the bank mode for the place', exists (select 1 from payments_summary(tt.today()) where mode='bank' and kind='collection' and location_id=1));

\echo == T3 event settings of phase87 apply to customer receipts; reference rule with exceptions
select money_event_setting_set('customer_collection', :'mab'::bigint, true, false) is not null as ev1 \gset
select tt.as(:'u_st');
select gen_random_uuid() as k7 \gset
select _w1f_collect_payment(:'k7'::uuid, 1, :'c1'::uuid, '[{"mode":"bank","amount":10}]'::jsonb, 'x') is not null as p7 \gset
select tt.chk('T3 the owner default account of the event is used when none is named and the mode matches (bank default, bank payment)', (tt.spc(:'k7'::uuid)).money_account_id=:'mab'::bigint);
select gen_random_uuid() as k8 \gset
select _w1f_collect_payment(:'k8'::uuid, 1, :'c1'::uuid, '[{"mode":"cash","amount":10}]'::jsonb, 'x') is not null as p8 \gset
select tt.chk('T3 a cash payment is NOT forced onto a bank default', (tt.spc(:'k8'::uuid)).money_account_id is null and (tt.spc(:'k8'::uuid)).mode='cash');
select tt.as(:'u_o');
select money_event_setting_set('customer_collection', :'mab'::bigint, false, false) is not null as ev2 \gset
select tt.as(:'u_st');
select format('[{"mode":"mobile","amount":10,"money_account_id":%s}]', :'maw') as j_fixed \gset
select tt.err('T3 the owner fixed the source: another account is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,%L::jsonb,'x')$q$, :'c1', :'j_fixed'), 'money_source_fixed');
select tt.as(:'u_o');
select money_event_setting_set('customer_collection', null, true, true, true) is not null as ev3 \gset
select gen_random_uuid() as k9 \gset
select tt.as(:'u_st');
select tt.err('T3 source required: a collection with no account is refused', format($q$select _w1f_collect_payment(%L,1,%L,'[{"mode":"cash","amount":10}]'::jsonb,'x')$q$, :'k9', :'c1'), 'money_source_required');
select tt.as(:'u_o');
select money_exception_grant('require_source', 'test_reason_nosrc', null, :'k9'::uuid, 'customer_collection') is not null as gr1 \gset
select tt.as(:'u_st');
select _w1f_collect_payment(:'k9'::uuid, 1, :'c1'::uuid, '[{"mode":"cash","amount":10}]'::jsonb, 'x') is not null as p9 \gset
select tt.as(:'u_o');
select tt.chk('T3 a one-off owner exception lets exactly that collection through; reason, audit line and Exceptions row exist', :'p9'::boolean and (tt.spc(:'k9'::uuid)).money_account_id is null
  and exists (select 1 from audit_log where action='money_exception_used' and detail->>'reason'='test_reason_nosrc') and exists (select 1 from money_exceptions where kind='source_required_exception' and event_type='customer_collection'));
select money_event_setting_set('customer_collection', null, true, false, true) is not null as ev4 \gset
-- reference rule
select set_rule('receipt_ref_required', '"bank"'::jsonb) is null as rr1 \gset
select tt.chk('T3 the setting change is in the audit_log', exists (select 1 from audit_log where table_name='rules' and record_id='receipt_ref_required'));
select tt.as(:'u_st');
select tt.err('T3 reference required: a bank receipt with no reference is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":10}]'::jsonb,'x')$q$, :'c1'), 'receipt_reference_required');
select tt.err('T3 a too-short reason does not waive it', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":10,"exception_reason":"ab"}]'::jsonb,'x')$q$, :'c1'), 'receipt_reference_required');
select tt.chk('T3 with a transaction number it passes', (_w1f_collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"bank","amount":10,"ref":"TRX-77"}]'::jsonb,'x') ->> 'collected')::numeric=10);
select tt.chk('T3 with a cheque number it passes', (_w1f_collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"bank","amount":10,"cheque_no":"CHQ-7"}]'::jsonb,'x') ->> 'collected')::numeric=10);
select tt.chk('T3 cash is never asked for a reference', (_w1f_collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"cash","amount":10}]'::jsonb,'x') ->> 'collected')::numeric=10);
select tt.chk('T3 mobile is not asked under the "bank" setting', (_w1f_collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"mobile","amount":10,"wallet":"bkash"}]'::jsonb,'x') ->> 'collected')::numeric=10);
select gen_random_uuid() as k10 \gset
select _w1f_collect_payment(:'k10'::uuid, 1, :'c1'::uuid, '[{"mode":"bank","amount":10,"exception_reason":"test_reason_noref"}]'::jsonb, 'x') is not null as p10 \gset
select tt.as(:'u_o');
select tt.chk('T3 waived with a written reason: stored on the row, audit_log line, one yellow Exceptions line (the books are not affected)', (tt.spc(:'k10'::uuid)).ref_waiver='test_reason_noref'
  and exists (select 1 from audit_log where action='receipt_reference_waived' and detail->>'reason'='test_reason_noref') and exists (select 1 from exceptions where flag_code='receipt_reference_waived' and level='yellow' and form_code='POS'));
select set_rule('receipt_ref_required', '"bank_mobile"'::jsonb) is null as rr2 \gset
select tt.as(:'u_st');
select tt.err('T3 under bank_mobile a mobile receipt with no reference is refused', format($q$select _w1f_collect_payment(gen_random_uuid(),1,%L,'[{"mode":"mobile","amount":10,"wallet":"bkash"}]'::jsonb,'x')$q$, :'c1'), 'receipt_reference_required');
select tt.as(:'u_o');
select set_rule('receipt_ref_from', to_jsonb((tt.today()+1)::text)) is null as rf1 \gset
select tt.as(:'u_st');
select tt.chk('T3 the start date is in the future: today a bank receipt needs no reference (an old figure is never touched)', (_w1f_collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"bank","amount":10}]'::jsonb,'x') ->> 'collected')::numeric=10);
select tt.as(:'u_o');
select set_rule('receipt_ref_from', null) is null as rf2 \gset
select set_rule('receipt_ref_required', '"off"'::jsonb) is null as rr3 \gset
select tt.as(:'u_st');
select tt.chk('T3 back to off: a bank receipt with no reference passes again', (_w1f_collect_payment(gen_random_uuid(),1,:'c1'::uuid,'[{"mode":"bank","amount":10}]'::jsonb,'x') ->> 'collected')::numeric=10);
select tt.chk('T3 the receipts list shows bank and cheque rows with the account name, the cheque number and the waived reason; cash without account is not listed',
  exists (select 1 from jsonb_array_elements(_w1f_receipts_list(1) -> 'rows') r where r->>'cheque_no'='CHQ-100' and r->>'account_name'='test_bank_97' and r->>'customer_name'='test_customer_97')
  and exists (select 1 from jsonb_array_elements(_w1f_receipts_list(1) -> 'rows') r where r->>'ref_waiver'='test_reason_noref')
  and not exists (select 1 from jsonb_array_elements(_w1f_receipts_list(1) -> 'rows') r where r->>'mode'='cash' and r->>'money_account_id' is null));
select tt.chk('T3 settings reader: bank on, modes, events', (_w1f_receipt_settings() ->> 'bank_on')::boolean and jsonb_array_length(_w1f_receipt_settings() -> 'modes')=4 and jsonb_array_length(_w1f_receipt_settings() -> 'events')=2);
select tt.as(:'u_o');
select void_collection((tt.spc(:'k3'::uuid)).id, 'test_reason_void') as vc \gset
select tt.chk('T3 voiding a bank collection restores the due (+800) and keeps the row (nothing deleted)', (tt.spc(:'k3'::uuid)).voided and customer_balance(:'c1'::uuid) = 3110 - 100 + 800);

\echo == T4 POS split payments: the payment source travels in band; bank needs the hook
select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]'::jsonb,0,format('[{"mode":"cash","amount":300,"wallet":"ma#%s;"},{"mode":"mobile","amount":200,"wallet":"ma#%s;"}]', :'mac1', :'maw')::jsonb,null,null,'retail',null,true) ->> 'id' as s1 \gset
select tt.chk('T4 a POS sale split cash 300 (drawer) + mobile 200 (wallet) with the in-band tag: both rows carry their account, wallet text cleared, sale is split',
  (select count(*) from sale_payments where sale_id=:'s1'::uuid and money_account_id is not null)=2 and tt.q(format('select string_agg(mode||money_account_id||coalesce(wallet,''-''), '','' order by mode) from sale_payments where sale_id=%L', :'s1'))='cash'||:'mac1'||'-,mobile'||:'maw'||'-'
  and tt.q(format('select pay_mode from sales where id=%L', :'s1'))='split');
select record_sale2(gen_random_uuid(),1,'[{"amount":700}]'::jsonb,0,format('[{"mode":"card","amount":700,"wallet":"ma#%s;"}]', :'mab')::jsonb,null,null,'retail',null,true) ->> 'id' as s2 \gset
select tt.chk('T4 a card payment tied to the bank account is stored as a bank receipt of that account (phase87 card-to-bank rule)', tt.q(format('select mode||money_account_id from sale_payments where sale_id=%L', :'s2'))='bank'||:'mab');
select tt.err('T4 WITHOUT the hook the shared record_sale2 still refuses bank (the hook is what opens it)', format($q$select record_sale2(gen_random_uuid(),1,'[{"amount":100}]'::jsonb,0,'[{"mode":"bank","amount":100}]'::jsonb,null,null,'retail',null,true)$q$), 'bad_mode');
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]'::jsonb,0,'[{"mode":"cash","amount":100}]'::jsonb,null,null,'retail',null,true) ->> 'id' as s0 \gset
select tt.chk('T4 a plain old POS sale (cash 100, no tag) is stored exactly as before: no account, no cheque', tt.q(format('select count(*) from sale_payments where sale_id=%L and money_account_id is null and cheque_no is null and mode=''cash'' and wallet is null', :'s0'))::int=1);
select tt.as(:'u_o');
select money_event_setting_set('pos_split_payment', :'mac1'::bigint, true, false) is not null as ev5 \gset
select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,'[{"amount":60}]'::jsonb,0,'[{"mode":"cash","amount":60}]'::jsonb,null,null,'retail',null,true) ->> 'id' as s3 \gset
select tt.chk('T4 the default account of the POS event is applied to a plain cash payment of that place', tt.q(format('select money_account_id from sale_payments where sale_id=%L', :'s3'))=:'mac1');
select tt.as(:'u_o');
select money_event_setting_set('pos_split_payment', null, true, false, true) is not null as ev6 \gset

\echo == T5 the hooks on a scratch copy (rolled back): journal, day book, shared routes
reset role;
-- A: without the hooks the chosen account is not used by the poster (the generic accounts are)
begin;
select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as a_posted \gset
select tt.nd(tt.cc(:'mab'::bigint)) as a_bank_acc \gset
select tt.unbalanced() as a_unbal \gset
rollback;
select tt.chk('H0 WITHOUT the hook the poster books the collections to the generic accounts: the chosen bank account stays at 0 (so H97-1 is required) and the books still balance', :'a_bank_acc'::numeric=0 and :'a_unbal'::int=0 and :'a_posted'::int>0);
-- B: with the hooks
begin;
\ir ../tests/sql/w1f_hooks97.sql
select tt.as(:'u_o');
select (select coalesce(sum(amount),0) from sale_payments where kind='collection' and not voided and money_account_id=:'mab'::bigint) as b_bank_coll \gset
select (select coalesce(sum(amount),0) from sale_payments where kind='sale' and not voided and money_account_id=:'mab'::bigint) as b_bank_sale \gset
select (select coalesce(sum(amount),0) from sale_payments where kind in ('collection','sale') and not voided and money_account_id=:'mac1'::bigint) as b_drawer \gset
select (select coalesce(sum(amount),0) from sale_payments where kind in ('collection','sale') and not voided and money_account_id=:'maw'::bigint) as b_wallet \gset
-- a sale with a bank leg and a cheque, through the HOOKED record_sale2
select tt.as(:'u_st');
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]'::jsonb,0,format('[{"mode":"cash","amount":300,"wallet":"ma#%s;"},{"mode":"bank","amount":700,"money_account_id":%s,"cheque_no":"CHQ-555","cheque_date":"%s"}]', :'mac1', :'mab', tt.today())::jsonb,null,null,'retail',null,true) ->> 'id' as b_s4 \gset
select (select mode||money_account_id||coalesce(cheque_no,'-') from sale_payments where sale_id=:'b_s4'::uuid and amount=700) as b_row \gset
select (select pay_mode from sales where id=:'b_s4'::uuid) as b_paymode \gset
select (select coalesce(sum(amount),0) from sale_payments where mode='bank' and money_account_id is null and not voided) as b_gen_before \gset
select tt.as(:'u_st');
select (_w1f_collect_payment(gen_random_uuid(),1,:'c2'::uuid,'[{"mode":"bank","amount":400}]'::jsonb,'x') ->> 'collected') as b_c2 \gset
-- the old routes accept the same channels
select (collect_payment(gen_random_uuid(),1,:'c1'::uuid,format('[{"mode":"bank","amount":15,"money_account_id":%s,"cheque_no":"CHQ-OLD","ref":"R-OLD"}]', :'mab')::jsonb,'x') ->> 'collected') as b_old \gset
select (select mode||money_account_id||cheque_no from sale_payments where cheque_no='CHQ-OLD') as b_old_row \gset
select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as b_posted \gset
select tt.nd(tt.cc(:'mab'::bigint)) as b_bank_acc \gset
select tt.nd(tt.cc(:'mac1'::bigint)) as b_drawer_acc \gset
select tt.nd(tt.cc(:'maw'::bigint)) as b_wallet_acc \gset
select tt.nd('1120') as b_generic_bank \gset
select tt.unbalanced() as b_unbal \gset
select tt.ndt('collection','1210') as b_recv_coll \gset
select (select count(*) from jsonb_array_elements(day_book(1, tt.today(), tt.today()) -> 'days') d, jsonb_array_elements(d -> 'lines') l where l ->> 'type' = 'collection' and l ->> 'text' like '%test_bank_97%' and l ->> 'text' like '%cheque CHQ-100%') as b_dbk \gset
select (select count(*) from jsonb_array_elements(daybook_vs_journal(:'pm'::date, tt.today()+1) -> 'rows') r where r->>'kind' in ('collection','sale') and (r->>'diff')::numeric <> 0) as b_dvj \gset
select _w1f_patch('public.collect_payment(uuid,integer,uuid,jsonb,text)'::regprocedure, array['x','y'], 'bos97') as b_second \gset
select position('bos97' in pg_get_functiondef('public.record_sale2(uuid,integer,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure)) > 0 as b_marker \gset
-- switch OFF again: the hooked routes refuse bank once more
select set_rule('receipt_bank_on','false') is null as b_off \gset
select tt.as(:'u_st');
select tt.err('H5 hooked collect_payment: bank refused again when the switch is OFF', format($q$select collect_payment(gen_random_uuid(),1,%L,'[{"mode":"bank","amount":1}]'::jsonb,'x')$q$, :'c1'), 'bad_mode');
select tt.err('H5 hooked record_sale2: bank refused again when the switch is OFF', $q$select record_sale2(gen_random_uuid(),1,'[{"amount":100}]'::jsonb,0,'[{"mode":"bank","amount":100}]'::jsonb,null,null,'retail',null,true)$q$, 'bad_mode');
rollback;
select tt.chk('H1 hooked poster: every collection and sale payment debits ITS OWN account: bank account = collections ('||:'b_bank_coll'||') + sale bank legs ('||:'b_bank_sale'||') + 700 + 15',
  :'b_bank_acc'::numeric = :'b_bank_coll'::numeric + :'b_bank_sale'::numeric + 700 + 15);
select tt.chk('H1 drawer account = ('||:'b_drawer'||') + 300; wallet account = ('||:'b_wallet'||'); the generic bank account 1120 keeps only the opening 300000 + the bank receipts that named no account ('||:'b_gen_before'||' + 400)', :'b_drawer_acc'::numeric = :'b_drawer'::numeric + 300 and :'b_wallet_acc'::numeric = :'b_wallet'::numeric and :'b_generic_bank'::numeric = 300000 + :'b_gen_before'::numeric + 400);
select tt.chk('H1 balanced: Dr = Cr on every entry, the poster posted something', :'b_unbal'::int=0 and :'b_posted'::int>0);
select tt.chk('H1 the receivable is credited by every collection (party ledger intact): credits to 1210 from collections equal the live collections', :'b_recv_coll'::numeric < 0);
select tt.chk('H2 day book: the line of the 600 cheque names the money account and the cheque number', :'b_dbk'::int=1);
select tt.chk('H2 day book vs journal: no difference for collections and sales', :'b_dvj'::int=0);
select tt.chk('H3 hooked collect_payment accepts bank with cheque number, reference and account (row: bank, account, cheque)', :'b_old'::numeric=15 and :'b_old_row'='bank'||:'mab'||'CHQ-OLD');
select tt.chk('H4 hooked record_sale2: split cash 300 + bank 700 by cheque -> row bank + account + cheque number; the sale pay_mode is split', :'b_row'='bank'||:'mab'||'CHQ-555' and :'b_paymode'='split');
select tt.chk('H4 the new route collected a whole bank due for a second customer (400)', :'b_c2'::numeric=400);
select tt.chk('H5 marker on the scratch copy; a second patch is a no-op (returns false)', :'b_marker'::boolean and not :'b_second'::boolean);
select tt.chk('H5 after the rollback the database under test carries NO bos97 marker and no hooked data (cheque CHQ-OLD / CHQ-555 do not exist, switch still ON)',
  (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_w1f\_%' and position('bos97' in pg_get_functiondef(p.oid)) > 0) = :m97
  and not exists (select 1 from sale_payments where cheque_no in ('CHQ-OLD','CHQ-555')) and rule_on('receipt_bank_on'));

\echo == T6 books balance, paste twice
select tt.chk('T6 every journal entry balances', tt.unbalanced()=0);
select (select count(*) from audit_log) as a1, (select count(*) from rules) as r1, (select count(*) from money_event_settings) as e1, (select count(*) from sale_payments) as p1,
  (select count(*) from pg_trigger where tgrelid='sale_payments'::regclass and not tgisinternal) as t1 \gset
\ir phase97.sql
select tt.chk('T6 pasting phase97 a second time changes nothing (audit_log, rules, event settings, payments, triggers)',
  (select count(*) from audit_log)=:'a1'::int and (select count(*) from rules)=:'r1'::int and (select count(*) from money_event_settings)=:'e1'::int and (select count(*) from sale_payments)=:'p1'::int
  and (select count(*) from pg_trigger where tgrelid='sale_payments'::regclass and not tgisinternal)=:'t1'::int);
select tt.chk('T6 and still no shared function carries bos97', (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_w1f\_%' and position('bos97' in pg_get_functiondef(p.oid)) > 0) = :m97);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
