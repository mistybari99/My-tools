-- FRESH DB ONLY. Phase 88 tests (opening dues and payables linked to the customer and supplier sub-ledgers, plan item U-01, package W1-A).
--   ORDER="phase8 ... phase87 phase88"  (any builder script that applies the phases in order)
--   psql -h /tmp -p 5561 -U postgres -d <fresh db> -qAt -f supabase/phase88_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
-- THE HOOKS: phase88.sql patches NO shared function. This test applies the four hooks of tests/sql/phase88_hooks.sql on THIS scratch database (T2) to prove them,
-- and at the end puts the original definitions back (T10), so the database is again exactly phase 88 without hooks.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000088'
\set u_acc '00000000-0000-0000-0000-000000000188'
\set u_acc2 '00000000-0000-0000-0000-000000000288'
\set u_br '00000000-0000-0000-0000-000000000388'
\set u_sp '00000000-0000-0000-0000-000000000488'
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
-- a stable picture of what the customer screens show (customers by mobile, so the picture can be compared before and after the hooks); run as the owner
create or replace function tt.pic() returns text language sql stable security definer as $$
  select md5(coalesce((select jsonb_agg(jsonb_build_array(c.mobile, public._cust_bal(c.id)) order by c.mobile) from public.customers c where c.mobile like '018000088%'), '[]'::jsonb)::text
    || coalesce((select jsonb_agg(jsonb_build_array(d.mobile, d.balance, d.oldest) order by d.mobile) from public.customer_dues() d where d.mobile like '018000088%'), '[]'::jsonb)::text
    || coalesce((select jsonb_agg(jsonb_build_array(c.mobile, l.kind, l.debit, l.credit, l.balance) order by c.mobile, l.at, l.kind, l.debit) from public.customers c, lateral public.customer_ledger(c.id) l where c.mobile like '018000088%'), '[]'::jsonb)::text) $$;
create table if not exists tt.pic (label text, v text);
truncate tt.pic;
create table if not exists tt.orig_defs (fn text primary key, def text);
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon; grant select, insert on tt.pic to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner88@s.app','{"full_name":"test_owner88"}'), (:'u_acc','test_acct88@s.app','{"full_name":"test_acct88"}'), (:'u_acc2','test_acct88b@s.app','{"full_name":"test_acct88b"}'),
 (:'u_br','test_branch88@s.app','{"full_name":"test_branch88"}'), (:'u_sp','test_sales88@s.app','{"full_name":"test_sales88"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_acc','management'),(:'u_acc2','management'),(:'u_br','salesperson'),(:'u_sp','salesperson') on conflict do nothing;
insert into user_locations values (:'u_acc',1),(:'u_acc',2),(:'u_acc2',1),(:'u_br',1),(:'u_sp',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_acc','accounts_manage',null),(:'u_acc','accounts_view',null),(:'u_acc2','accounts_manage',null),(:'u_acc2','accounts_view',null),
  (:'u_br','accounts_manage',1),(:'u_br','accounts_view',1);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
insert into customers (mobile, name) values ('01800008801','test_cust_collect'),('01800008802','test_cust_plain'),('01800008803','test_cust_credit'),('01800008805','test_cust_limit'),('01800008806','test_cust_gate'),('01800008807','test_cust_limit_off');
update customers set credit_limit = 400 where mobile in ('01800008805','01800008807');
insert into suppliers (name) values ('test_sup_pay'),('test_sup_gate'),('test_sup_over');
select id as c1 from customers where mobile='01800008801' \gset
select id as c2 from customers where mobile='01800008802' \gset
select id as c3 from customers where mobile='01800008803' \gset
select id as c5 from customers where mobile='01800008805' \gset
select id as c6 from customers where mobile='01800008806' \gset
select id as c7 from customers where mobile='01800008807' \gset
select id as s1 from suppliers where name='test_sup_pay' \gset
select id as s2 from suppliers where name='test_sup_gate' \gset
select id as s3 from suppliers where name='test_sup_over' \gset
set role authenticated; select tt.as(:'u_o');
select acct_set_start(:'pm'::date) is not null as st1 \gset
select set_rule('accounting_on','true') is null as st2 \gset
reset role;

\echo == T0 shape, safe defaults, internals closed, hooks NOT in place
select tt.chk('T0 phase88 present', to_regprocedure('public._p88_present()') is not null);
select tt.chk('T0 three settings exist with the safe defaults (link OFF, freeze off, adjust direct) and are in the Rules hub module books',
  (select count(*) from rules where key in ('open_parties_link','open_parties_freeze','open_parties_adjust_mode') and module='books')=3
  and not rule_on('open_parties_link') and rule_txt('open_parties_freeze')='off' and rule_txt('open_parties_adjust_mode')='direct');
select tt.chk('T0 the settings carry an English label and a hint', (select count(*) from rules where key in ('open_parties_link','open_parties_freeze','open_parties_adjust_mode') and length(label_en)>10 and length(hint_en)>20)=3);
select tt.chk('T0 columns exist and are empty: no customer or supplier has an opening', exists (select 1 from information_schema.columns where table_name='customers' and column_name='opening_balance')
  and exists (select 1 from information_schema.columns where table_name='customers' and column_name='opening_date') and exists (select 1 from information_schema.columns where table_name='suppliers' and column_name='opening_date')
  and (select count(*) from customers where opening_balance is not null)=0 and (select count(*) from suppliers where opening_balance is not null)=0);
select tt.chk('T0 phase88 patches no shared function (no marker bos88 in the four hooked functions yet)',
  (select count(*) from (values ('public._cust_bal(uuid)'),('public.customer_dues()'),('public.customer_ledger(uuid)'),('public.opening_balance_post(jsonb,uuid,boolean,boolean)')) v(f)
    where position('bos88' in pg_get_functiondef(v.f::regprocedure))>0)=0);
select tt.chk('T0 internals closed to browsers, API open',
  not has_function_privilege('authenticated','public._w1a_patch(regprocedure,text[],text)','execute') and not has_function_privilege('authenticated','public._w1a_cust_open(uuid)','execute')
  and not has_function_privilege('authenticated','public._w1a_opening_apply(jsonb)','execute') and not has_function_privilege('authenticated','public._w1a_adj_apply(bigint,text)','execute')
  and not has_function_privilege('anon','public.w1a_open_list(text,text,text,int,int)','execute') and has_function_privilege('authenticated','public.w1a_open_list(text,text,text,int,int)','execute')
  and has_function_privilege('authenticated','public.w1a_party_gate(text)','execute'));
select tt.chk('T0 the adjustments table is closed to direct writes', not has_table_privilege('authenticated','public.open_party_adjustments','insert') and not has_table_privilege('authenticated','public.open_party_adjustments','update')
  and has_table_privilege('authenticated','public.open_party_adjustments','select'));

\echo == T1 staging: type the opening once (no hook needed). Permissions, validation, audit.
set role authenticated; select tt.as(:'u_sp');
select tt.err('T1 salesperson cannot type an opening', format($$select w1a_open_set('customer', %L, 500, null, 'x')$$, :'c1'), 'not allowed');
select tt.err('T1 salesperson cannot list', $$select w1a_open_list('customer')$$, 'not allowed');
select tt.err('T1 salesperson cannot run the gate', $$select w1a_party_gate()$$, 'not allowed');
select tt.err('T1 salesperson cannot import', $$select w1a_open_import('customer', '[{"mobile":"01800008801","amount":"5"}]'::jsonb, true)$$, 'not allowed');
select tt.as(:'u_br');
select tt.err('T1 a branch accountant (Accounts manage at one place only) cannot type an opening', format($$select w1a_open_set('customer', %L, 500, null, 'x')$$, :'c1'), 'not allowed');
select tt.err('T1 a branch accountant cannot list the company figures', $$select w1a_open_list('customer')$$, 'not allowed');
select tt.chk('T1 a branch accountant may read the state but cannot manage', (w1a_open_state() ->> 'can_manage')::boolean = false);
select tt.as(:'u_acc');
select tt.err('T1 unknown kind refused', format($$select w1a_open_set('bank', %L, 500, null, 'x')$$, :'c1'), 'bad_kind');
select tt.err('T1 negative customer opening refused', format($$select w1a_open_set('customer', %L, -5, null, 'x')$$, :'c1'), 'negative_not_allowed');
select tt.err('T1 not a number refused', format($$select w1a_open_set('customer', %L, 'NaN'::numeric, null, 'x')$$, :'c1'), 'bad_amount');
select tt.err('T1 unknown party refused', $$select w1a_open_set('customer', gen_random_uuid(), 5, null, 'x')$$, 'unknown_party');
select w1a_open_set('customer', :'c1'::uuid, 500, null, 'paper ledger page 1') ->> 'new' as r1 \gset
select tt.chk('T1 accountant types customer opening 500', :'r1'::numeric = 500);
reset role;
select tt.chk('T1 the opening is stored', (select opening_balance from customers where id=:'c1') = 500);
select tt.chk('T1 the change wrote one audit line with old, new and the note', (select count(*) from audit_log where action='open_party_set' and record_id=:'c1'::text and detail ->> 'note'='paper ledger page 1' and (detail ->> 'new')::numeric=500)=1);
set role authenticated; select tt.as(:'u_acc');
select w1a_open_set('customer', :'c1'::uuid, 0, null, null) ->> 'new' as r0 \gset
reset role;
select tt.chk('T1 typing 0 clears the opening (empty, not zero)', (select opening_balance from customers where id=:'c1') is null);
set role authenticated; select tt.as(:'u_acc');
select w1a_open_set('customer', :'c1'::uuid, 500, null, 'paper ledger page 1') is not null as r1b \gset
select w1a_open_set('supplier', :'s1'::uuid, 300, null, 'paper') is not null as rs1 \gset
select w1a_open_set('supplier', :'s2'::uuid, -40, null, 'we paid in advance') is not null as rs2 \gset
reset role;
select tt.chk('T1 a supplier opening may be negative (the supplier owes us)', (select opening_balance from suppliers where id=:'s2') = -40);
set role authenticated; select tt.as(:'u_acc');
select w1a_open_set('supplier', :'s2'::uuid, null, null, 'cleared') is not null as rs2b \gset
reset role;

\echo == T1b paste import: dry run first, all or nothing, create, same file twice
set role authenticated; select tt.as(:'u_acc');
select w1a_open_import('customer', '[{"mobile":"01800008803","amount":"200"},{"mobile":"01800008805","amount":"300"},{"mobile":"01800008807","amount":"300"},{"mobile":"01800008804","name":"test_cust_new","amount":"125.50"},
  {"mobile":"01800008899","amount":"7"},{"mobile":"01800008803","amount":"9"},{"name":"test_cust_plain","amount":"abc"},{"mobile":"0180","amount":"3"},{"mobile":"01800008802","amount":"-3"},{"amount":"4"}]'::jsonb, true, false) as d0 \gset
select tt.chk('T1b dry run (no create): 3 good rows and 7 errors', (:'d0'::jsonb ->> 'ok')::int = 3 and (:'d0'::jsonb ->> 'errors')::int = 7 and (:'d0'::jsonb ->> 'dry')::boolean);
select tt.chk('T1b the dry run named the reason of each bad row (unknown customer, unknown mobile, duplicate, bad amount, bad mobile, negative, no party)',
  (select string_agg(x ->> 'status', ',' order by (x ->> 'i')::int) from jsonb_array_elements(:'d0'::jsonb -> 'rows') x) = 'ok,ok,ok,unknown_party,unknown_party,duplicate_row,bad_amount,bad_mobile,negative_not_allowed,party_missing');
reset role;
select tt.chk('T1b the dry run wrote nothing', (select count(*) from customers where opening_balance is not null)=1 and not exists (select 1 from customers where mobile='01800008804'));
set role authenticated; select tt.as(:'u_acc');
select tt.err('T1b a real run with any bad row refuses the whole file', $$select w1a_open_import('customer', '[{"mobile":"01800008803","amount":"200"},{"mobile":"01800008802","amount":"-3"}]'::jsonb, false, false)$$, 'import_has_errors');
select tt.err('T1b more than 2000 rows refused', $$select w1a_open_import('customer', (select jsonb_agg(jsonb_build_object('mobile','01800008803','amount','1')) from generate_series(1,2001)), true, false)$$, 'too_many_rows');
select tt.err('T1b empty file refused', $$select w1a_open_import('customer', '[]'::jsonb, true, false)$$, 'no_rows');
reset role;
select tt.chk('T1b nothing of the refused file was written', (select count(*) from customers where opening_balance is not null)=1);
set role authenticated; select tt.as(:'u_acc');
select w1a_open_import('customer', '[{"mobile":"01800008803","amount":"200"},{"mobile":"01800008805","amount":"300"},{"mobile":"01800008807","amount":"300"},{"mobile":"01800008804","name":"test_cust_new","amount":"125.50"}]'::jsonb, false, true) as ap1 \gset
reset role;
select tt.chk('T1b real import: 3 changed, 1 created, total 925.50; the new customer has the opening', (:'ap1'::jsonb ->> 'changed')::int=3 and (:'ap1'::jsonb ->> 'created')::int=1 and (:'ap1'::jsonb ->> 'total_new')::numeric=925.50
  and (select opening_balance from customers where mobile='01800008804')=125.50 and (select opening_balance from customers where mobile='01800008803')=200);
select tt.chk('T1b one audit line for the whole import', (select count(*) from audit_log where action='open_party_import')=1);
set role authenticated; select tt.as(:'u_acc');
select w1a_open_import('customer', '[{"mobile":"01800008803","amount":"200"},{"mobile":"01800008805","amount":"300"},{"mobile":"01800008807","amount":"300"},{"mobile":"01800008804","name":"test_cust_new","amount":"125.50"}]'::jsonb, false, true) as ap2 \gset
select tt.chk('T1b the same file twice changes nothing (4 unchanged, no second customer)', (:'ap2'::jsonb ->> 'changed')::int=0 and (:'ap2'::jsonb ->> 'unchanged')::int=4);
select w1a_open_import('supplier', '[{"name":"test_sup_over","amount":"300"},{"name":"test_sup_pay","amount":"300"}]'::jsonb, false, false) as sc \gset
select tt.chk('T1b supplier import by name: one changed, one already the same', (:'sc'::jsonb ->> 'changed')::int=1 and (:'sc'::jsonb ->> 'unchanged')::int=1);
select tt.err('T1b suppliers are never created by the import', $$select w1a_open_import('supplier', '[{"name":"test_sup_nope","amount":"5"}]'::jsonb, false, true)$$, 'import_has_errors');
reset role;
select tt.chk('T1b supplier 3 has its opening, and exactly 7 test customers exist', (select opening_balance from suppliers where id=:'s3')=300 and (select count(*) from customers where mobile like '018000088%')=7);

\echo == T1c the opening screen sections come from what was typed once (no second typing)
set role authenticated; select tt.as(:'u_acc');
select w1a_open_json() as oj \gset
select tt.chk('T1c customer_dues section: 5 customers, 1425.50 in total', jsonb_array_length(:'oj'::jsonb -> 'customer_dues')=5
  and (select sum((x ->> 'amount')::numeric) from jsonb_array_elements(:'oj'::jsonb -> 'customer_dues') x)=1425.50);
select tt.chk('T1c supplier_dues section: 2 suppliers, 600', jsonb_array_length(:'oj'::jsonb -> 'supplier_dues')=2 and (select sum((x ->> 'amount')::numeric) from jsonb_array_elements(:'oj'::jsonb -> 'supplier_dues') x)=600);
select w1a_open_set('supplier', :'s2'::uuid, -40, null, 'advance') is not null as sx \gset
select tt.chk('T1c a supplier who owes us cannot go in supplier_dues: reported as not postable', jsonb_array_length(w1a_open_json() -> 'not_postable')=1 and jsonb_array_length(w1a_open_json() -> 'supplier_dues')=2);
select w1a_open_set('supplier', :'s2'::uuid, null, null, 'cleared') is not null as sx2 \gset
select tt.as(:'u_sp');
select tt.err('T1c salesperson cannot read the opening sections', $$select w1a_open_json()$$, 'not allowed');
reset role;

\echo == T2 the hooks, on this scratch database: with the switch OFF nothing changes at all
insert into tt.orig_defs select v.f, pg_get_functiondef(v.f::regprocedure) from (values ('public._cust_bal(uuid)'),('public.customer_dues()'),('public.customer_ledger(uuid)'),('public.opening_balance_post(jsonb,uuid,boolean,boolean)')) v(f) on conflict (fn) do nothing;
set role authenticated; select tt.as(:'u_o');
insert into tt.pic select 'before_hooks_owner', tt.pic();
reset role;
\ir ../tests/sql/phase88_hooks.sql
select tt.chk('T2 the four hooks are in place (marker bos88)', (select count(*) from (values ('public._cust_bal(uuid)'),('public.customer_dues()'),('public.customer_ledger(uuid)'),('public.opening_balance_post(jsonb,uuid,boolean,boolean)')) v(f)
    where position('bos88' in pg_get_functiondef(v.f::regprocedure))>0)=4);
select tt.chk('T2 the earlier tag survives in opening_balance_post (bos87)', position('bos87' in pg_get_functiondef('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure))>0);
select tt.chk('T2 hooks twice = no-op (the marker is already inside)', not public._w1a_patch('public._cust_bal(uuid)'::regprocedure, array['x','y']));
select tt.err('T2 a patch whose site is missing stops with a clear message', $$select public._w1a_patch('public.customer_dues()'::regprocedure, array['this text is not there','x'], 'bos99')$$, 'patch site not found');
select tt.err('T2 a patch that carries no marker is refused', $$select public._w1a_patch('public.customer_dues()'::regprocedure, array['order by 6 desc;','order by 6 desc;'], 'bos98')$$, 'carries no marker');
set role authenticated; select tt.as(:'u_o');
insert into tt.pic select 'after_hooks_owner', tt.pic();
reset role;
select tt.chk('T2 switch OFF, hooks on: _cust_bal, dues list and ledger of every test customer are identical to before the hooks', (select v from tt.pic where label='before_hooks_owner') = (select v from tt.pic where label='after_hooks_owner'));
select tt.chk('T2 switch OFF: a customer with a typed opening still has balance 0', _cust_bal(:'c1'::uuid)=0 and _w1a_cust_open(:'c1'::uuid)=0);
set role authenticated; select tt.as(:'u_o');
select tt.chk('T2 switch OFF: the customer is not in the dues list', not exists (select 1 from customer_dues() where id=:'c1'::uuid));
select tt.err('T2 switch OFF: collecting the old due is refused as before (overpaid)', format($$select collect_payment(gen_random_uuid(), 1, %L, '[{"mode":"cash","amount":100}]'::jsonb, 'x')$$, :'c1'), 'overpaid');
select tt.as(:'u_acc');
select tt.err('T2 an accountant cannot switch the setting on (owner only)', $$select set_rule('open_parties_link','true')$$, 'not allowed');
select tt.as(:'u_sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":150}]',0,'[]','01800008807','test_cust_limit_off','retail',null,true) ->> 'id' as sale7 \gset
select tt.chk('T2 switch OFF: the credit limit ignores the opening as today (opening 300 + 150 would pass 400, the sale goes through)', :'sale7' is not null);
reset role;

\echo == T3 the owner switches the link ON (audited); the old due can now be collected
select count(*) as a0 from audit_log where table_name='rules' and record_id='open_parties_link' \gset
set role authenticated; select tt.as(:'u_o');
select set_rule('open_parties_link','true') is null as on1 \gset
reset role;
select tt.chk('T3 the setting change is one audit_log line', (select count(*) from audit_log where table_name='rules' and record_id='open_parties_link') = :a0 + 1);
select tt.chk('T3 customer 1: the opening 500 is the balance', _cust_bal(:'c1'::uuid)=500 and _w1a_cust_open(:'c1'::uuid)=500);
set role authenticated; select tt.as(:'u_o');
select tt.chk('T3 the dues list shows customer 1 with 500; the oldest item is the opening (accounting start)', (select balance from customer_dues() where id=:'c1'::uuid)=500 and (select oldest from customer_dues() where id=:'c1'::uuid)=:'pm'::date);
select tt.err('T3 collecting 600 on an opening of 500 is refused (overpaid)', format($$select collect_payment(gen_random_uuid(), 1, %L, '[{"mode":"cash","amount":600}]'::jsonb, 'x')$$, :'c1'), 'overpaid');
select collect_payment(gen_random_uuid(), 1, :'c1'::uuid, '[{"mode":"cash","amount":500}]'::jsonb, 'old due') as col \gset
select tt.chk('T3 collecting 500 works and leaves 0', (:'col'::jsonb ->> 'collected')::numeric=500 and (:'col'::jsonb ->> 'balance')::numeric=0);
select tt.chk('T3 the paid customer leaves the dues list', not exists (select 1 from customer_dues() where id=:'c1'::uuid));
select tt.chk('T3 ledger of customer 1: the opening row first (debit 500), then the collection; the running balance ends at 0',
  (select count(*) from customer_ledger(:'c1'::uuid))=2 and (select kind from customer_ledger(:'c1'::uuid) order by at, (debit>0) desc limit 1)='opening'
  and (select debit from customer_ledger(:'c1'::uuid) where kind='opening')=500 and (select balance from customer_ledger(:'c1'::uuid) order by at desc, (debit>0) limit 1)=0);
select tt.as(:'u_sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":300}]',0,'[]','01800008803','test_cust_credit','retail',null,true) ->> 'id' as sale3 \gset
select tt.as(:'u_o');
select tt.chk('T3 customer 3: opening 200 + credit sale 300 = 500 in the dues list; the oldest item is the opening', (select balance from customer_dues() where id=:'c3'::uuid)=500 and (select oldest from customer_dues() where id=:'c3'::uuid)=:'pm'::date);
select collect_payment(gen_random_uuid(), 1, :'c3'::uuid, '[{"mode":"cash","amount":200}]'::jsonb, 'part') ->> 'balance' as cb3 \gset
select tt.chk('T3 collecting 200 clears the opening first: balance 300 and the oldest item is now the sale (today)', :'cb3'::numeric=300 and (select oldest from customer_dues() where id=:'c3'::uuid)=tt.today());
select tt.chk('T3 customer_balance (read by the POS credit check) includes the opening: customer 5 = 300, customer 7 = 450', customer_balance(:'c5'::uuid)=300 and customer_balance(:'c7'::uuid)=450);
select tt.as(:'u_sp');
select tt.err('T3 credit limit: opening 300 + new credit 150 > limit 400 is refused', $$select record_sale2(gen_random_uuid(),1,'[{"amount":150}]',0,'[]','01800008805','test_cust_limit','retail',null,true)$$, 'over_credit_limit');
select record_sale2(gen_random_uuid(),1,'[{"amount":90}]',0,'[]','01800008805','test_cust_limit','retail',null,true) ->> 'id' as sale5 \gset
select tt.chk('T3 credit limit: opening 300 + 90 = 390 is within the limit 400 and goes through', :'sale5' is not null);
select tt.as(:'u_o');
select tt.err('T3 supplier overpaid: paying 301 on an opening of 300 is refused', format($$select pay_supplier(%L, 1, '[{"mode":"cash","amount":301}]'::jsonb)$$, :'s3'), 'overpaid');
select pay_supplier(:'s3'::uuid, 1, '[{"mode":"cash","amount":300}]'::jsonb) ->> 'balance' as sb3 \gset
select tt.chk('T3 paying 300 works and leaves 0', :'sb3'::numeric=0);
reset role;
select tt.chk('T3 customer 5 now: 300 + 90 = 390 (sub-ledger)', _cust_bal(:'c5'::uuid)=390);

\echo == T4 the opening batch: unbalanced refused with nothing applied; the posted figure wins over the typed one (audited); second post refused
set role authenticated; select tt.as(:'u_acc');
select tt.err('T4 an unbalanced opening is refused (customer 500 with no capital)', format($$select opening_balance_post(jsonb_build_object('customer_dues', jsonb_build_array(jsonb_build_object('customer_id', %L, 'amount', '500'))), gen_random_uuid(), false, false)$$, :'c2'), 'unbalanced');
reset role;
select tt.chk('T4 the refused post changed no party (customer 2 still has no opening) and no batch exists', (select opening_balance from customers where id=:'c2') is null and not exists (select 1 from opening_batches));
-- customers: c1 500, c3 200, c4 125.50, c5 310 (typed 300: the posted figure wins), c7 300 = 1435.50 debit; suppliers s1 300 + s3 300 = 600; owner capital 835.50
select format('{"customer_dues":[{"customer_id":"%s","amount":"500"},{"customer_id":"%s","amount":"200"},{"customer_id":"%s","amount":"125.50"},{"customer_id":"%s","amount":"310"},{"customer_id":"%s","amount":"300"}],
  "supplier_dues":[{"supplier_id":"%s","amount":"300"},{"supplier_id":"%s","amount":"300"}],"capital":[{"kind":"owner","amount":"835.50"}]}',
  :'c1', :'c3', (select id from customers where mobile='01800008804'), :'c5', :'c7', :'s1', :'s3') as bj \gset
set role authenticated; select tt.as(:'u_acc');
select w1a_open_precheck(:'bj'::jsonb) as pc \gset
select tt.chk('T4 precheck: 7 parties, only customer 5 differs (310 in the file, 300 typed)', jsonb_array_length(:'pc'::jsonb -> 'rows')=7 and (:'pc'::jsonb ->> 'differing')::int=1
  and exists (select 1 from jsonb_array_elements(:'pc'::jsonb -> 'rows') r where r ->> 'party_id'=:'c5' and r ->> 'status'='differs'));
select opening_balance_post(:'bj'::jsonb, null, true, false) as dry \gset
select tt.chk('T4 dry run: balanced, debit 1435.50 = credit 1435.50', (:'dry'::jsonb ->> 'balanced')::boolean and (:'dry'::jsonb ->> 'total_debit')::numeric=1435.50);
reset role;
select tt.chk('T4 the dry run changed nothing', (select opening_balance from customers where id=:'c5')=300 and not exists (select 1 from opening_batches));
set role authenticated; select tt.as(:'u_acc');
select opening_balance_post(:'bj'::jsonb, gen_random_uuid(), false, false) ->> 'id' as bid \gset
reset role;
select tt.chk('T4 the batch is posted (one opening entry) and every entry balances', :'bid' is not null and (select count(*) from journal_entries where source_type='opening')=1 and tt.unbalanced()=0);
select tt.chk('T4 the posted figure won: customer 5 now has 310 (not 300), opening date = accounting start; an audit line says typed 300, posted 310',
  (select opening_balance=310 and opening_date=:'pm'::date from customers where id=:'c5') and exists (select 1 from audit_log where action='open_party_json_override' and record_id=:'c5' and (detail ->> 'typed')::numeric=300 and (detail ->> 'posted')::numeric=310));
select tt.chk('T4 one linked-parties audit line (5 customers, 2 suppliers)', exists (select 1 from audit_log where action='open_party_linked' and (detail ->> 'customers')::int=5 and (detail ->> 'suppliers')::int=2));
select tt.chk('T4 the supplier sub-ledger equals the journal figure (typed once): supplier 1 = 300 with the opening date', (select opening_balance=300 and opening_date=:'pm'::date from suppliers where id=:'s1'));
set role authenticated; select tt.as(:'u_acc');
select tt.err('T4 a second opening post is refused (opening_exists)', format($$select opening_balance_post(%L::jsonb, gen_random_uuid(), false, false)$$, '{"capital":[{"kind":"owner","amount":"1"}],"other":[{"code":"1110","debit":1}]}'), 'opening_exists');
select tt.err('T4 typing an opening after the batch is refused: use an adjustment', format($$select w1a_open_set('customer', %L, 5, null, 'x')$$, :'c2'), 'opening_posted_use_adjust');
select tt.err('T4 an import after the batch is refused too', $$select w1a_open_import('customer', '[{"mobile":"01800008802","amount":"5"}]'::jsonb, true)$$, 'opening_posted_use_adjust');
reset role;

\echo == T5 the gate: sub-ledger equals the general ledger for every party
set role authenticated; select tt.as(:'u_o');
select acct_post_pending(false) ->> 'posted' as posted \gset
reset role;
select tt.chk('T5 the poster posted the collections, sales and payment after the batch', :'posted'::int >= 6 and tt.unbalanced()=0);
set role authenticated; select tt.as(:'u_acc');
select w1a_party_gate() as g1 \gset
select tt.chk('T5 the gate is green: every customer and supplier agrees with the books', :'g1'::jsonb ->> 'status' = 'green' and (:'g1'::jsonb ->> 'customers_off')::int=0 and (:'g1'::jsonb ->> 'suppliers_off')::int=0);
select tt.as(:'u_br');
select tt.err('T5 a branch accountant cannot run the gate', $$select w1a_party_gate()$$, 'not allowed');
select tt.as(:'u_acc');
select w1a_open_list('customer', null, 'all', 300, 0) as l1 \gset
select tt.chk('T5 list: customer 1 shows opening 500, journal opening 500, journal balance 0, sub-ledger 0, difference 0 and the mobile (manager)',
  exists (select 1 from jsonb_array_elements(:'l1'::jsonb -> 'rows') r where r ->> 'id'=:'c1' and (r ->> 'opening')::numeric=500 and (r ->> 'journal_opening')::numeric=500 and (r ->> 'journal_balance')::numeric=0
          and (r ->> 'subledger_balance')::numeric=0 and (r ->> 'difference')::numeric=0 and r ->> 'mobile'='01800008801'));
select tt.chk('T5 list: customer 3 (opening 200, sale 300, collected 200): books 300 = sub-ledger 300', exists (select 1 from jsonb_array_elements(:'l1'::jsonb -> 'rows') r where r ->> 'id'=:'c3' and (r ->> 'journal_balance')::numeric=300 and (r ->> 'subledger_balance')::numeric=300));
select tt.chk('T5 list filter opening: only parties with an opening (5 customers)', jsonb_array_length(w1a_open_list('customer', null, 'opening', 300, 0) -> 'rows')=5);
select tt.chk('T5 list filter diff: nobody differs', jsonb_array_length(w1a_open_list('customer', null, 'diff', 300, 0) -> 'rows')=0 and jsonb_array_length(w1a_open_list('supplier', null, 'diff', 300, 0) -> 'rows')=0);
select tt.chk('T5 list search by name and by mobile; limit 1 reports more rows', jsonb_array_length(w1a_open_list('customer', 'collect', 'all', 300, 0) -> 'rows')=1 and jsonb_array_length(w1a_open_list('customer', '0180000880', 'all', 300, 0) -> 'rows')=7
  and jsonb_array_length(w1a_open_list('customer', null, 'all', 1, 0) -> 'rows')=1 and (w1a_open_list('customer', null, 'all', 1, 0) ->> 'has_more')::boolean);
select tt.chk('T5 supplier list: supplier 1 opening 300, books 300, sub-ledger 300', exists (select 1 from jsonb_array_elements(w1a_open_list('supplier', null, 'opening', 300, 0) -> 'rows') r where r ->> 'id'=:'s1' and (r ->> 'difference')::numeric=0 and (r ->> 'subledger_balance')::numeric=300));
select tt.err('T5 bad filter refused', $$select w1a_open_list('customer', null, 'nope')$$, 'bad_value');
select tt.chk('T5 state: batch exists, link on, freeze off, 5 customers and 2 suppliers typed', (w1a_open_state() ->> 'batch_exists')::boolean and (w1a_open_state() ->> 'link')::boolean and w1a_open_state() ->> 'freeze'='off'
  and (w1a_open_state() ->> 'customers_typed')::int=5 and (w1a_open_state() ->> 'suppliers_typed')::int=2 and (w1a_open_state() ->> 'customers_typed_total')::numeric=1435.50);
reset role;

\echo == T6 freeze (setting): off = today's behaviour, after_opening = a direct change is refused, the way is an adjustment
update customers set opening_balance = 205 where id=:'c3';
select tt.chk('T6 freeze OFF (default): a direct change of an opening still works, exactly as today', (select opening_balance from customers where id=:'c3')=205);
update customers set opening_balance = 200 where id=:'c3';
set role authenticated; select tt.as(:'u_acc');
select tt.err('T6 an accountant cannot change the freeze setting (owner only)', $$select set_rule('open_parties_freeze','"after_opening"')$$, 'not allowed');
select tt.as(:'u_o');
select set_rule('open_parties_freeze','"after_opening"') is null as fz \gset
reset role;
select tt.err('T6 freeze ON: a direct change of a customer opening is refused', format($$update customers set opening_balance = 250 where id=%L$$, :'c3'), 'opening_frozen');
select tt.err('T6 freeze ON: a direct change of the opening date is refused', format($$update customers set opening_date = date '2020-01-01' where id=%L$$, :'c3'), 'opening_frozen');
select tt.err('T6 freeze ON: a direct change of a supplier opening is refused', format($$update suppliers set opening_balance = 250 where id=%L$$, :'s1'), 'opening_frozen');
select tt.err('T6 freeze ON: a new supplier with an opening is refused', $$insert into suppliers (name, opening_balance) values ('test_sup_late', 60)$$, 'opening_frozen');
insert into suppliers (name) values ('test_sup_late_ok');
update customers set note = 'test note' where id=:'c3';
select tt.chk('T6 freeze ON: a new supplier without an opening and any other column change are not blocked', exists (select 1 from suppliers where name='test_sup_late_ok') and (select note from customers where id=:'c3')='test note');
set role authenticated; select tt.as(:'u_o');
select tt.err('T6 freeze ON: the supplier screen path (save_supplier) cannot change the opening either', format($$select save_supplier(%L, '{"opening_balance":260}')$$, :'s1'), 'opening_frozen');
reset role;
select tt.chk('T6 nothing changed by the refused attempts', (select opening_balance from customers where id=:'c3')=200 and (select opening_balance from suppliers where id=:'s1')=300);

\echo == T7 adjustment after the opening (mode direct): reason, balanced journal, audit line, Exceptions row, idempotent
select count(*) as ex0 from exceptions where flag_code='opening_adjusted' \gset
select count(*) as je0 from journal_entries \gset
set role authenticated; select tt.as(:'u_sp');
select tt.err('T7 salesperson cannot adjust', format($$select w1a_open_adjust('customer', %L, 250, 'because', null)$$, :'c3'), 'not allowed');
select tt.as(:'u_br');
select tt.err('T7 branch accountant cannot adjust', format($$select w1a_open_adjust('customer', %L, 250, 'because', null)$$, :'c3'), 'not allowed');
select tt.as(:'u_acc');
select tt.err('T7 a reason is required', format($$select w1a_open_adjust('customer', %L, 250, '', null)$$, :'c3'), 'reason_required');
select tt.err('T7 a reason of 2 characters is not a reason', format($$select w1a_open_adjust('customer', %L, 250, 'ab', null)$$, :'c3'), 'reason_required');
select tt.err('T7 the same figure is no change', format($$select w1a_open_adjust('customer', %L, 200, 'same', null)$$, :'c3'), 'no_change');
select tt.err('T7 a negative customer opening is refused', format($$select w1a_open_adjust('customer', %L, -1, 'neg', null)$$, :'c3'), 'negative_not_allowed');
select tt.err('T7 unknown party refused', $$select w1a_open_adjust('customer', gen_random_uuid(), 5, 'x reason', null)$$, 'unknown_party');
select gen_random_uuid() as cl1 \gset
select w1a_open_adjust('customer', :'c3'::uuid, 250, 'paper ledger corrected: 250 not 200', :'cl1'::uuid) as ad1 \gset
select tt.chk('T7 the adjustment is approved at once (mode direct) with a journal entry', :'ad1'::jsonb ->> 'status'='approved' and (:'ad1'::jsonb ->> 'journal_entry_id') is not null and (:'ad1'::jsonb ->> 'delta')::numeric=50);
reset role;
select tt.chk('T7 the opening is 250 now and the sub-ledger followed: balance 350 (250 + 300 sale - 200 collected)', (select opening_balance from customers where id=:'c3')=250 and _cust_bal(:'c3'::uuid)=350);
select tt.chk('T7 the journal entry is manual and balanced: Dr receivable 50 (party customer 3), Cr retained 50', (select count(*) from journal_entries where id=(:'ad1'::jsonb ->> 'journal_entry_id')::bigint and source_type='manual')=1
  and (select sum(debit) from journal_lines where entry_id=(:'ad1'::jsonb ->> 'journal_entry_id')::bigint)=50 and (select sum(credit) from journal_lines where entry_id=(:'ad1'::jsonb ->> 'journal_entry_id')::bigint)=50
  and exists (select 1 from journal_lines l join acct_mappings m on m.account_id=l.account_id and m.key='receivable' where l.entry_id=(:'ad1'::jsonb ->> 'journal_entry_id')::bigint and l.debit=50 and l.party_type='customer' and l.party_id=:'c3')
  and exists (select 1 from journal_lines l join acct_mappings m on m.account_id=l.account_id and m.key='retained' where l.entry_id=(:'ad1'::jsonb ->> 'journal_entry_id')::bigint and l.credit=50) and tt.unbalanced()=0 and (select count(*) from journal_entries)=:je0+1);
select tt.chk('T7 one audit_log line with old, new, delta and the reason', (select count(*) from audit_log where action='open_party_adjust' and record_id=:'c3' and (detail ->> 'old')::numeric=200 and (detail ->> 'new')::numeric=250 and detail ->> 'reason' like 'paper ledger corrected%')=1);
select tt.chk('T7 one row in the Exceptions list (flag opening_adjusted, yellow, amount 50) with the reason in the text', (select count(*) from exceptions where flag_code='opening_adjusted')=:ex0+1
  and exists (select 1 from exceptions where flag_code='opening_adjusted' and level='yellow' and amount=50 and text ->> 'en' like '%paper ledger corrected%' and status='open'));
set role authenticated; select tt.as(:'u_acc');
select w1a_open_adjust('customer', :'c3'::uuid, 250, 'paper ledger corrected: 250 not 200', :'cl1'::uuid) as ad1b \gset
select tt.chk('T7 the same client id again = same answer, no second journal entry', (:'ad1b'::jsonb ->> 'dup')::boolean);
reset role;
select tt.chk('T7 no second entry or exception was made', (select count(*) from journal_entries)=:je0+1 and (select count(*) from exceptions where flag_code='opening_adjusted')=:ex0+1);
set role authenticated; select tt.as(:'u_acc');
select w1a_open_adjust('supplier', :'s1'::uuid, 280, 'supplier statement says 280', null) as ad2 \gset
reset role;
select tt.chk('T7 supplier adjusted 300 -> 280: payable debit 20 (we owe less), sub-ledger 280', (:'ad2'::jsonb ->> 'status')='approved' and _sup_balance(:'s1'::uuid)=280
  and (select sum(l.debit) from journal_lines l join acct_mappings m on m.account_id=l.account_id and m.key='payable' where l.entry_id=(:'ad2'::jsonb ->> 'journal_entry_id')::bigint and l.party_id=:'s1')=20 and tt.unbalanced()=0);
set role authenticated; select tt.as(:'u_o');
select tt.err('T7 the supplier overpaid guard uses the adjusted figure: 281 refused', format($$select pay_supplier(%L, 1, '[{"mode":"cash","amount":281}]'::jsonb)$$, :'s1'), 'overpaid');
select tt.as(:'u_acc');
select w1a_party_gate() ->> 'status' as g2 \gset
select tt.chk('T7 the gate stays green after the adjustments (books and sub-ledger moved together)', :'g2'='green');
select tt.chk('T7 the adjustment list shows both, newest first', jsonb_array_length(w1a_open_adjust_list(null, 100) -> 'rows')=2 and (w1a_open_adjust_list('approved', 10) -> 'rows' -> 0 ->> 'kind')='supplier');
reset role;

\echo == T8 mode approval: a second person decides; the maker never decides his own; the owner follows the owner approval setting (not hard-coded)
set role authenticated; select tt.as(:'u_o');
select set_rule('open_parties_adjust_mode','"approval"') is null as am \gset
select tt.as(:'u_acc');
select w1a_open_adjust('customer', :'c3'::uuid, 260, 'second correction', null) as ap1 \gset
reset role;
select tt.chk('T8 approval mode: the request waits (pending), nothing moved', :'ap1'::jsonb ->> 'status'='pending' and (select opening_balance from customers where id=:'c3')=250);
select (:'ap1'::jsonb ->> 'id')::bigint as rid \gset
set role authenticated; select tt.as(:'u_acc');
select tt.err('T8 a second request for the same party while one waits is refused', format($$select w1a_open_adjust('customer', %L, 270, 'again', null)$$, :'c3'), 'adjust_pending_exists');
select tt.err('T8 the maker cannot decide his own request', format($$select w1a_open_adjust_decide(%s, true, 'ok')$$, :'rid'), 'maker_cannot_decide');
select tt.as(:'u_sp');
select tt.err('T8 a salesperson cannot decide', format($$select w1a_open_adjust_decide(%s, true, 'ok')$$, :'rid'), 'not allowed');
select tt.as(:'u_br');
select tt.err('T8 a branch accountant cannot decide', format($$select w1a_open_adjust_decide(%s, true, 'ok')$$, :'rid'), 'not allowed');
select tt.as(:'u_acc2');
select tt.err('T8 rejecting needs a note', format($$select w1a_open_adjust_decide(%s, false, '')$$, :'rid'), 'note_required');
select w1a_open_adjust_decide(:'rid'::bigint, false, 'not supported by the paper') ->> 'status' as rj \gset
reset role;
select tt.chk('T8 rejected: nothing moved, no journal', :'rj'='rejected' and (select opening_balance from customers where id=:'c3')=250);
set role authenticated; select tt.as(:'u_acc2');
select tt.err('T8 a decided request cannot be decided again', format($$select w1a_open_adjust_decide(%s, true, 'x')$$, :'rid'), 'not_pending');
select tt.as(:'u_acc');
select w1a_open_adjust('customer', :'c3'::uuid, 260, 'second correction, with the receipt', null) ->> 'id' as rid2 \gset
select tt.as(:'u_acc2');
select w1a_open_adjust_decide(:'rid2'::bigint, true, 'seen the receipt') as dec \gset
reset role;
select tt.chk('T8 a second person approves: opening 260, decided_by is the approver, requested_by the maker', :'dec'::jsonb ->> 'status'='approved' and (select opening_balance from customers where id=:'c3')=260
  and (select decided_by = :'u_acc2'::uuid and requested_by = :'u_acc'::uuid and journal_entry_id is not null from open_party_adjustments where id=:'rid2'::bigint));
set role authenticated; select tt.as(:'u_o');
select w1a_open_adjust('customer', :'c2'::uuid, 80, 'customer says he owes 80 from before go-live', null) ->> 'id' as rid3 \gset
select w1a_open_adjust_decide(:'rid3'::bigint, true, 'my own request') ->> 'status' as odec \gset
reset role;
select tt.chk('T8 owner approval setting = self: the owner decides his own request (customer 2 gets an opening of 80 after the batch)', :'odec'='approved' and (select opening_balance from customers where id=:'c2')=80);
set role authenticated; select tt.as(:'u_o');
select owner_approval_mode_set2('named', null, array[:'u_acc2'::uuid], 'test') is not null as nm \gset
select w1a_open_adjust('customer', :'c2'::uuid, 90, 'corrected to 90', null) ->> 'id' as rid4 \gset
select tt.err('T8 named mode: the owner cannot decide his own request', format($$select w1a_open_adjust_decide(%s, true, 'x')$$, :'rid4'), 'maker_cannot_decide');
select tt.as(:'u_acc');
select tt.err('T8 named mode: a holder of Accounts manage who is not named cannot decide the owner request', format($$select w1a_open_adjust_decide(%s, true, 'x')$$, :'rid4'), 'named_approver_only');
select tt.as(:'u_acc2');
select w1a_open_adjust_decide(:'rid4'::bigint, true, 'named approver') ->> 'status' as ndec \gset
reset role;
select tt.chk('T8 named mode: the person the owner named decides (any person set by the owner, nobody is written in the code)', :'ndec'='approved' and (select opening_balance from customers where id=:'c2')=90);
set role authenticated; select tt.as(:'u_o');
select owner_approval_mode_set2('self', null, array[]::uuid[], 'back') is not null as bk \gset
select set_rule('open_parties_adjust_mode','"direct"') is null as am2 \gset
reset role;
select tt.chk('T8 every decision is in audit_log (request, approve, reject) and the journal still balances', exists (select 1 from audit_log where action='open_party_adjust_request') and exists (select 1 from audit_log where action='open_party_adjust_reject')
  and (select count(*) from audit_log where action='open_party_adjust')=5 and tt.unbalanced()=0);
select tt.chk('T8 the Exceptions list has one row per applied adjustment (5) and the table keeps 6 requests', (select count(*) from exceptions where flag_code='opening_adjusted')=5 and (select count(*) from open_party_adjustments)=6);

\echo == T9 the gate names a party whose books and sub-ledger disagree, and the fill from the journal repairs it
select set_config('bos88.api', '1', false);
update customers set opening_balance = 150 where id=:'c6';
update customers set opening_balance = null where id=:'c5';
update suppliers set opening_balance = 77 where id=:'s2';
select set_config('bos88.api', '', false);
set role authenticated; select tt.as(:'u_acc');
select w1a_party_gate() as g3 \gset
select tt.chk('T9 the gate is red and lists customers 5 and 6 and supplier 2', :'g3'::jsonb ->> 'status'='red' and (:'g3'::jsonb ->> 'customers_off')::int=2 and (:'g3'::jsonb ->> 'suppliers_off')::int=1);
select tt.chk('T9 customer 6: books 0, sub-ledger 150, difference -150, cause = in the sub-ledger, not in the books',
  exists (select 1 from jsonb_array_elements(:'g3'::jsonb -> 'customers') x where x ->> 'party_id'=:'c6' and (x ->> 'difference')::numeric=-150 and x ->> 'cause'='opening_in_subledger_not_in_books'));
select tt.chk('T9 customer 5: books 400 (310 + credit sale 90), sub-ledger 90, difference 310, cause = in the books, not in the sub-ledger',
  exists (select 1 from jsonb_array_elements(:'g3'::jsonb -> 'customers') x where x ->> 'party_id'=:'c5' and (x ->> 'journal')::numeric=400 and (x ->> 'existing')::numeric=90 and (x ->> 'difference')::numeric=310 and x ->> 'cause'='opening_in_books_not_in_subledger'));
select tt.chk('T9 supplier 2: difference -77 and the cause is named', exists (select 1 from jsonb_array_elements(:'g3'::jsonb -> 'suppliers') x where x ->> 'party_id'=:'s2' and (x ->> 'difference')::numeric=-77 and x ->> 'cause'='opening_in_subledger_not_in_books'));
select tt.chk('T9 the list "differences only" shows the same parties', jsonb_array_length(w1a_open_list('customer', null, 'diff', 300, 0) -> 'rows')=2 and jsonb_array_length(w1a_open_list('supplier', null, 'diff', 300, 0) -> 'rows')=1);
select w1a_open_from_journal(true) as fj0 \gset
select tt.chk('T9 fill from the opening journal, dry run: customer 5 would be filled with 310; customer 3 (typed 260 after the adjustments, journal 200) is a conflict and is never overwritten',
  exists (select 1 from jsonb_array_elements(:'fj0'::jsonb -> 'rows') x where x ->> 'party_id'=:'c5' and x ->> 'status'='fill' and (x ->> 'journal')::numeric=310)
  and exists (select 1 from jsonb_array_elements(:'fj0'::jsonb -> 'rows') x where x ->> 'party_id'=:'c3' and x ->> 'status'='conflict') and (:'fj0'::jsonb ->> 'dry')::boolean);
reset role;
select tt.chk('T9 the dry run wrote nothing', (select opening_balance from customers where id=:'c5') is null);
set role authenticated; select tt.as(:'u_sp');
select tt.err('T9 salesperson cannot run the fill', $$select w1a_open_from_journal(false)$$, 'not allowed');
select tt.as(:'u_acc');
select w1a_open_from_journal(false) ->> 'filled' as fj1 \gset
reset role;
select tt.chk('T9 the fill repaired customer 5 only (310) and left the conflict alone', (select opening_balance from customers where id=:'c5')=310 and (select opening_balance from customers where id=:'c3')=260 and :'fj1'::int=1);
select set_config('bos88.api', '1', false);
update customers set opening_balance = null where id=:'c6';
update suppliers set opening_balance = null where id=:'s2';
select set_config('bos88.api', '', false);
set role authenticated; select tt.as(:'u_acc');
select tt.chk('T9 after the repairs the gate is green again', w1a_party_gate() ->> 'status' = 'green');
reset role;

\echo == T10 back to default: switch OFF = old behaviour; the hooks are removed again; paste twice
set role authenticated; select tt.as(:'u_o');
select set_rule('open_parties_freeze','"off"') is null as fz2 \gset
select set_rule('open_parties_link','false') is null as off1 \gset
select tt.chk('T10 link OFF again: customer 5 is back to its sales only (90) and customer 1 is not in the dues list', customer_balance(:'c5'::uuid)=90 and not exists (select 1 from customer_dues() where id=:'c1'::uuid) and (select balance from customer_dues() where id=:'c5'::uuid)=90);
reset role;
select tt.chk('T10 audit_log has the link switch changes (ON and OFF)', (select count(*) from audit_log where table_name='rules' and record_id='open_parties_link') >= 2);
-- the hooks come out again: the database is phase 88 without hooks
do $r$ declare r record; begin for r in select fn, def from tt.orig_defs loop execute r.def; end loop; end $r$;
select tt.chk('T10 the original definitions are back: no bos88 marker in the four functions (bos87 is still in opening_balance_post)', (select count(*) from (values ('public._cust_bal(uuid)'),('public.customer_dues()'),('public.customer_ledger(uuid)'),('public.opening_balance_post(jsonb,uuid,boolean,boolean)')) v(f)
    where position('bos88' in pg_get_functiondef(v.f::regprocedure))>0)=0 and position('bos87' in pg_get_functiondef('public.opening_balance_post(jsonb,uuid,boolean,boolean)'::regprocedure))>0);
\ir phase88.sql
select tt.chk('T10 paste twice: phase88.sql again changes no owner setting and removes no data', rule_txt('open_parties_freeze')='off' and not rule_on('open_parties_link') and rule_txt('open_parties_adjust_mode')='direct'
  and (select count(*) from open_party_adjustments)=6 and (select count(*) from opening_batches)=1);
select tt.chk('T10 every journal entry in the test database balances (Dr = Cr)', tt.unbalanced()=0);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
