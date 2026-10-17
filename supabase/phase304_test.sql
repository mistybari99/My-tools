-- FRESH DB ONLY. Phase 304 tests (CRM-B privacy: masked customer list, reveal with log, export control, print log, policy, consent register).
--   bash tests/sql/crmb_run.sh        or by hand on a fresh database through phase 98 + 303 + 304 + 305:
--   psql -h /tmp -p 5572 -U postgres -d <db> -qAt -f supabase/phase304_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000030401'
\set u_m '00000000-0000-0000-0000-000000030402'
\set u_c '00000000-0000-0000-0000-000000030403'
\set u_g '00000000-0000-0000-0000-000000030404'
\set u_x '00000000-0000-0000-0000-000000030405'
\set u_n '00000000-0000-0000-0000-000000030406'
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
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner304@s.app','{"full_name":"test_owner304"}'), (:'u_m','test_mgr304@s.app','{"full_name":"test_mgr304"}'), (:'u_c','test_cashier304@s.app','{"full_name":"test_cashier304"}'),
 (:'u_g','test_grantee304@s.app','{"full_name":"test_grantee304"}'), (:'u_x','test_exporter304@s.app','{"full_name":"test_exporter304"}'), (:'u_n','test_nopos304@s.app','{"full_name":"test_nopos304"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m', :'u_c', :'u_g', :'u_x', :'u_n');
insert into user_roles values (:'u_o','owner'),(:'u_m','showroom_manager'),(:'u_c','salesperson'),(:'u_g','salesperson'),(:'u_x','showroom_manager'),(:'u_n','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_c',1),(:'u_g',1),(:'u_x',1),(:'u_n',1) on conflict do nothing;
select tt.as(:'u_o');
select set_user_grant(:'u_m'::uuid,'customer_manage') is null as g1 \gset
select set_user_grant(:'u_x'::uuid,'customer_manage') is null as g2 \gset
select set_user_grant(:'u_g'::uuid,'crm_contact_view') is null as g3 \gset
select set_user_grant(:'u_x'::uuid,'crm_export') is null as g4 \gset
-- customers: a has a sale, b owes 700, c has a birthday in March, d starts with "=" (spreadsheet formula guard)
select (record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":1200}]','01740400001','test_a','retail',null,true)) is not null as s1 \gset
select (record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":500}]','01740400002','test_b','retail',null,true)) is not null as s2 \gset
insert into customers (mobile, name, birthday, address, whatsapp) values ('01740400003','test_c','1990-03-12','test address c','01740400093'),('01740400004','=test_d',null,null,null);
update customers set address='test address a', whatsapp='01740400091' where mobile='01740400001';
select tt.je() as je0 \gset
select count(*) as sales0 from sales \gset
select id as ca from customers where mobile='01740400001' \gset
select id as cb from customers where mobile='01740400002' \gset
select id as cc from customers where mobile='01740400003' \gset

\echo == T0 shape, safe defaults, internals closed
select tt.chk('T0 phase304 present and seven rules with safe defaults (guard OFF, style first3_last2, reason ON, call OFF, export OFF, cap blank, print-needs-export OFF)',
  (select count(*) from rules where module='crm' and key in ('crm_pii_guard_on','crm_mask_style','crm_unmask_reason_required','crm_reveal_for_call','crm_export_on','crm_export_max_rows','crm_print_needs_export'))=7
  and not rule_on('crm_pii_guard_on') and rule_txt('crm_mask_style')='first3_last2' and rule_on('crm_unmask_reason_required') and not rule_on('crm_reveal_for_call') and not rule_on('crm_export_on')
  and rule_num('crm_export_max_rows') is null and not rule_on('crm_print_needs_export')
  and not exists (select 1 from rules where key like 'crm\_%' and (label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 two grants exist and nobody holds them by default except the people the owner gave them to',
  (select count(*) from grant_defs where grant_code in ('crm_contact_view','crm_export'))=2 and (select count(*) from user_grants where grant_code in ('crm_contact_view','crm_export'))=2);
select tt.chk('T0 customer_directory / customer_profile were not re-created (no crmb text inside)',
  position('crmb' in pg_get_functiondef('public.customer_directory(integer)'::regprocedure))=0 and position('crmb' in pg_get_functiondef('public.customer_profile(uuid)'::regprocedure))=0);
select tt.chk('T0 logs: RLS on, append-only, no browser writes', (select bool_and(relrowsecurity) from pg_class where relname in ('crm_view_log','crm_export_log'))
  and not has_table_privilege('authenticated','public.crm_view_log','insert') and not has_table_privilege('authenticated','public.crm_export_log','insert') and not has_table_privilege('anon','public.crm_view_log','select'));
select tt.chk('T0 API open to signed-in users only; helpers closed',
  has_function_privilege('authenticated','public._crmb_customer_list(int,boolean)','execute') and not has_function_privilege('anon','public._crmb_customer_list(int,boolean)','execute')
  and not has_function_privilege('authenticated','public._crmb_customer_rows(int,boolean,boolean)','execute') and not has_function_privilege('authenticated','public._crmb_view_log_add(uuid,text,text,int,jsonb)','execute')
  and not has_function_privilege('authenticated','public._crmb_mask_phone(text)','execute') and not has_function_privilege('anon','public._crmb_export(text,jsonb,text,int,text)','execute'));

\echo == T1 guard OFF (the default): the list is exactly customer_directory, nothing is masked, nothing is logged
set role authenticated;
select tt.as(:'u_c');
select tt.chk('T1 cashier: _crmb_customer_list has the same 19 columns and rows as customer_directory (both directions empty)',
  (select count(*) from (select id,mobile,name,type,active,tier_id,tier_locked,birthday,anniversary,address,whatsapp,note,credit_limit,customer_since,balance,spend,orders,last_sale,points from _crmb_customer_list()
     except select id,mobile,name,type,active,tier_id,tier_locked,birthday,anniversary,address,whatsapp,note,credit_limit,customer_since,balance,spend,orders,last_sale,points from customer_directory()) z)=0
  and (select count(*) from (select id,mobile,name,type,active,tier_id,tier_locked,birthday,anniversary,address,whatsapp,note,credit_limit,customer_since,balance,spend,orders,last_sale,points from customer_directory()
     except select id,mobile,name,type,active,tier_id,tier_locked,birthday,anniversary,address,whatsapp,note,credit_limit,customer_since,balance,spend,orders,last_sale,points from _crmb_customer_list()) z)=0
  and (select count(*) from _crmb_customer_list())=(select count(*) from customer_directory()) and (select count(*) from _crmb_customer_list())>=4);
select tt.chk('T1 same order as customer_directory', (select string_agg(id::text, ',' order by rn) from (select id, row_number() over () rn from _crmb_customer_list()) a)
  = (select string_agg(id::text, ',' order by rn) from (select id, row_number() over () rn from customer_directory()) b));
select tt.chk('T1 nothing is masked: masked=false for every row, full mobile and address present', (select bool_and(not masked) from _crmb_customer_list()) and (select mobile from _crmb_customer_list() where id=:'ca')='01740400001'
  and (select address from _crmb_customer_list() where id=:'ca')='test address a');
select tt.chk('T1 the balance of customer b is 700 (the sale left 700 due), spend of a is 1200', (select balance from _crmb_customer_list() where id=:'cb')=700 and (select spend from _crmb_customer_list() where id=:'ca')=1200);
select tt.chk('T1 no view-log line was written', tt.q($$select count(*) from crm_view_log$$)='0');
select tt.chk('T1 reveal at guard OFF: full number, nothing to log', (select _crmb_phone_reveal(:'ca') ->> 'mobile')='01740400001' and (select _crmb_phone_reveal(:'ca') ->> 'logged')='false' and tt.q($$select count(*) from crm_view_log$$)='0');
select tt.chk('T1 policy for the cashier at defaults: sees all, cannot export, can print, cannot consent, cannot link', (select _crmb_policy() ->> 'guard_on')='false' and (select _crmb_policy() ->> 'contact_ok')='true'
  and (select _crmb_policy() ->> 'can_export')='false' and (select _crmb_policy() ->> 'can_print')='true' and (select _crmb_policy() ->> 'can_consent')='false' and (select _crmb_policy() ->> 'can_link')='false');
select tt.as(:'u_n');
select tt.err('T1 a user without POS cannot read the list', $$select * from _crmb_customer_list()$$, 'not allowed');
select tt.err('T1 a user without POS cannot reveal', format($$select _crmb_phone_reveal(%L)$$, :'ca'), 'not allowed');
reset role; set role anon;
select tt.err('T1 anon has no execute on the list', $$select * from _crmb_customer_list()$$, 'permission denied');
reset role;

\echo == T2 guard ON: masked for everyone except the owner and holders of crm_contact_view
select tt.as(:'u_o'); select set_rule('crm_pii_guard_on','true') is null as gon \gset
set role authenticated; select tt.as(:'u_c');
select tt.chk('T2 cashier: mobile 017******01 style, address hidden, whatsapp masked, masked=true',
  (select mobile from _crmb_customer_list() where id=:'ca')='017******01' and (select address from _crmb_customer_list() where id=:'ca') is null
  and (select whatsapp from _crmb_customer_list() where id=:'ca')='017******91' and (select bool_and(masked) from _crmb_customer_list()));
select tt.chk('T2 the full number is nowhere in the row JSON (not through to_jsonb either)', (select count(*) from _crmb_customer_list() x where to_jsonb(x)::text like '%017404000%' and to_jsonb(x)::text not like '%017******%')=0
  and (select count(*) from _crmb_customer_list() x where to_jsonb(x)::text ~ '0174040000[0-9]')=0);
select tt.chk('T2 names, balances, spend are still shown (only contact details are hidden)', (select balance from _crmb_customer_list() where id=:'cb')=700 and (select name from _crmb_customer_list() where id=:'cb')='test_b');
select tt.chk('T2 cashier policy: contact_ok false, cannot reveal, reason required', (select _crmb_policy() ->> 'contact_ok')='false' and (select _crmb_policy() ->> 'can_reveal')='false');
select tt.chk('T2 residual exposure, stated plainly: a direct table read by a POS user still returns the number (customers_read policy is unchanged; see CRM-B.md)', (select mobile from customers where id=:'ca')='01740400001');
select tt.as(:'u_g');
select tt.chk('T2 holder of crm_contact_view sees the full number and address', (select mobile from _crmb_customer_list() where id=:'ca')='01740400001' and (select address from _crmb_customer_list() where id=:'ca')='test address a'
  and (select bool_and(not masked) from _crmb_customer_list()));
select tt.chk('T2 that look at the full list left view-log lines (what=list, by the grantee, row limit 5000)', tt.q($$select count(*) from crm_view_log where what='list' and user_id='00000000-0000-0000-0000-000000030404' and row_count=5000$$)::int>=1);
select tt.as(:'u_o');
select tt.q($$select count(*) from crm_view_log$$) as vl0 \gset
select tt.chk('T2 owner sees everything and leaves no line (the owner is not logged)', (select mobile from _crmb_customer_list() where id=:'ca')='01740400001' and tt.q($$select count(*) from crm_view_log$$)=:'vl0');
select tt.as(:'u_m');
select tt.chk('T2 a customer manager WITHOUT the grant is masked too (the guard is about contact details, not about managing)', (select mobile from _crmb_customer_list() where id=:'ca')='017******01');
reset role;
select tt.as(:'u_o'); select set_rule('crm_mask_style','"last4"') is null as ls \gset
set role authenticated; select tt.as(:'u_c');
select tt.chk('T2 style last4 shows only the last four digits', (select mobile from _crmb_customer_list() where id=:'ca')='*******0001');
reset role;
select tt.as(:'u_o'); select set_rule('crm_mask_style', null) is null as ls2 \gset
select tt.chk('T2 style back to default', rule_txt('crm_mask_style')='first3_last2' and (select _crmb_mask_phone('01740400001'))='017******01' and (select _crmb_mask_phone('123'))='***' and (select _crmb_mask_phone(null)) is null);

\echo == T2b the profile follows the same rule
set role authenticated; select tt.as(:'u_c');
select tt.chk('T2b guard ON: cashier profile has the number, WhatsApp and address hidden, masked=true; names and money intact',
  (select _crmb_customer_profile(:'ca') -> 'customer' ->> 'mobile')='017******01' and (select _crmb_customer_profile(:'ca') -> 'customer' ->> 'whatsapp')='017******91'
  and (select _crmb_customer_profile(:'ca') -> 'customer' -> 'address') = 'null'::jsonb and (select _crmb_customer_profile(:'ca') ->> 'masked')='true' and (select (_crmb_customer_profile(:'cb') ->> 'balance')::numeric)=700
  and (select _crmb_customer_profile(:'ca') -> 'customer' ->> 'name')='test_a' and position('01740400001' in (select _crmb_customer_profile(:'ca')::text))=0);
select tt.as(:'u_g');
select tt.chk('T2b holder of crm_contact_view: full profile, one profile line in the access log', (select _crmb_customer_profile(:'ca') -> 'customer' ->> 'mobile')='01740400001' and (select _crmb_customer_profile(:'ca') ->> 'masked')='false'
  and tt.q(format($$select count(*) from crm_view_log where what='profile' and customer_id=%L$$, :'ca'))::int>=1);
reset role; select tt.as(:'u_o'); select set_rule('crm_pii_guard_on','false') is null as goff2 \gset
set role authenticated; select tt.as(:'u_c');
select tt.chk('T2b guard OFF: the profile is exactly customer_profile plus masked=false', (select _crmb_customer_profile(:'ca') - 'masked') = (select customer_profile(:'ca')));
reset role; select tt.as(:'u_o'); select set_rule('crm_pii_guard_on','true') is null as gon2 \gset

\echo == T3 reveal one number: reason, log, who may
set role authenticated; select tt.as(:'u_c');
select tt.err('T3 masked cashier cannot open a number while crm_reveal_for_call is OFF', format($$select _crmb_phone_reveal(%L, 'order call')$$, :'ca'), 'not allowed');
reset role; select tt.as(:'u_o'); select set_rule('crm_reveal_for_call','true') is null as rc \gset
set role authenticated; select tt.as(:'u_c');
select tt.err('T3 call button without a reason', format($$select _crmb_phone_reveal(%L)$$, :'ca'), 'reason_required');
select tt.err('T3 a 2-character reason', format($$select _crmb_phone_reveal(%L, 'ok')$$, :'ca'), 'reason_required');
select tt.err('T3 reason over 200 characters', format($$select _crmb_phone_reveal(%L, repeat('x',201))$$, :'ca'), 'bad_input');
select tt.err('T3 unknown customer', $$select _crmb_phone_reveal(gen_random_uuid(), 'order call')$$, 'customer_not_found');
select _crmb_phone_reveal(:'ca', 'order is ready, calling') as rv \gset
select tt.chk('T3 with a reason: the number is returned once, the address is NOT (call only)', (:'rv'::jsonb ->> 'mobile')='01740400001' and (:'rv'::jsonb -> 'address') = 'null'::jsonb and (:'rv'::jsonb ->> 'logged')='true');
select tt.chk('T3 one log line: what=call, the reason, the staff, the customer', tt.q(format($$select count(*) from crm_view_log where what='call' and customer_id=%L and reason='order is ready, calling' and staff_id is not null$$, :'ca'))='1');
select tt.as(:'u_g');
select tt.err('T3 holder of the grant also gives a reason (setting is ON)', format($$select _crmb_phone_reveal(%L)$$, :'ca'), 'reason_required');
select tt.chk('T3 holder with a reason: number AND address, what=contact', (select _crmb_phone_reveal(:'ca', 'check address for delivery') ->> 'address')='test address a'
  and tt.q(format($$select count(*) from crm_view_log where what='contact' and customer_id=%L$$, :'ca'))='1');
select tt.as(:'u_o');
select tt.chk('T3 owner needs no reason, is logged', (select _crmb_phone_reveal(:'ca') ->> 'logged')='true' and tt.q(format($$select count(*) from crm_view_log where what='contact' and customer_id=%L$$, :'ca'))='2');
reset role; select set_rule('crm_unmask_reason_required','false') is null as rr \gset
set role authenticated; select tt.as(:'u_c');
select tt.chk('T3 reason setting OFF: no reason needed (still logged)', (select _crmb_phone_reveal(:'ca') ->> 'logged')='true');
reset role; select tt.as(:'u_o'); select set_rule('crm_unmask_reason_required', null) is null as rr2 \gset
set role authenticated;
select tt.as(:'u_o');
select tt.chk('T3 the owner reads the access log (newest first, with the customer name)', (select jsonb_array_length(_crmb_view_log_list()) from (select 1) z)>=4 and (select (_crmb_view_log_list(10, :'ca') -> 0 ->> 'customer_name'))='test_a');
select tt.as(:'u_m');
select tt.err('T3 a manager cannot read the access log', $$select _crmb_view_log_list()$$, 'not allowed');
select tt.as(:'u_c');
select tt.err('T3 cashier cannot read the access log', $$select _crmb_view_log_list()$$, 'not allowed');
select tt.chk('T3 the log table is closed to a cashier (policy: owner only)', (select count(*) from crm_view_log)=0);
select tt.as(:'u_o');
select tt.chk('T3 the owner can read the log table', (select count(*) from crm_view_log)>=4);
reset role;
select tt.err('T3 log lines cannot be changed', $$update crm_view_log set reason='x'$$, 'append-only');
select tt.err('T3 log lines cannot be deleted', $$delete from crm_view_log$$, 'append-only');

\echo == T4 export control
set role authenticated; select tt.as(:'u_x');
select tt.err('T4 export is OFF by default', $$select _crmb_export('customers','{}','json',null,'monthly list')$$, 'module_off');
reset role; select tt.as(:'u_o'); select set_rule('crm_export_on','true') is null as eon \gset
set role authenticated; select tt.as(:'u_x');
select tt.err('T4 switched ON but the row cap is blank: still blocked', $$select _crmb_export('customers','{}','json',null,'monthly list')$$, 'export_limit_not_set');
reset role; select tt.as(:'u_o'); select set_rule('crm_export_max_rows','2') is null as ecap \gset
set role authenticated; select tt.as(:'u_m');
select tt.err('T4 a customer manager without crm_export cannot export', $$select _crmb_export('customers','{}','json',null,'monthly list')$$, 'not allowed');
select tt.as(:'u_c');
select tt.err('T4 a cashier cannot export', $$select _crmb_export('customers','{}','json',null,'monthly list')$$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T4 exporter without a reason', $$select _crmb_export('customers','{}','json')$$, 'reason_required');
select tt.err('T4 bad dataset', $$select _crmb_export('suppliers','{}','json',null,'monthly list')$$, 'bad_dataset');
select tt.err('T4 bad format', $$select _crmb_export('customers','{}','xml',null,'monthly list')$$, 'bad_format');
select tt.err('T4 unknown filter key', $$select _crmb_export('customers','{"mobile":"017"}','json',null,'monthly list')$$, 'bad_filter');
select tt.err('T4 bad filter value', $$select _crmb_export('customers','{"birthday_month":13}','json',null,'monthly list')$$, 'bad_filter');
select tt.err('T4 filter must be an object', $$select _crmb_export('customers','[1]','json',null,'monthly list')$$, 'bad_filter');
select _crmb_export('customers','{}','json',null,'monthly list') as ex1 \gset
select tt.chk('T4 the cap of 2 rows is honoured: count 2, truncated, columns listed', (:'ex1'::jsonb ->> 'count')='2' and (:'ex1'::jsonb ->> 'truncated')='true' and jsonb_array_length(:'ex1'::jsonb -> 'rows')=2);
select tt.chk('T4 guard is ON and the exporter lacks crm_contact_view: the export is masked (no full number, no address)', (:'ex1'::jsonb ->> 'masked')='true' and position('01740400' in :'ex1')=0
  and (select bool_and((r -> 'address') = 'null'::jsonb) from jsonb_array_elements(:'ex1'::jsonb -> 'rows') r));
select tt.chk('T4 one export-log line (rows 2, masked, reason, format) and one audit line', tt.q($$select count(*) from crm_export_log where kind='export' and row_count=2 and masked and reason='monthly list' and format='json'$$)='1'
  and tt.q($$select count(*) from audit_log where action='export' and table_name='customers'$$)='1');
select _crmb_export('customers','{"has_due":true}','json',null,'who owes') as ex2 \gset
select tt.chk('T4 filter has_due returns only the customer who owes (b)', (:'ex2'::jsonb ->> 'count')='1' and (:'ex2'::jsonb -> 'rows' -> 0 ->> 'name')='test_b');
select _crmb_export('customers','{"birthday_month":3}','json',null,'march birthdays') as ex3 \gset
select tt.chk('T4 filter birthday_month 3 returns only customer c', (:'ex3'::jsonb ->> 'count')='1' and (:'ex3'::jsonb -> 'rows' -> 0 ->> 'name')='test_c');
select tt.chk('T4 a masked exporter cannot find a customer by typing digits of the hidden number (no enumeration)', (_crmb_export('customers','{"search":"1740400002"}','json',null,'digits test') ->> 'count')='0');
select tt.chk('T4 but can search by name', (_crmb_export('customers','{"search":"test_b"}','json',null,'name test') ->> 'count')='1');
select _crmb_export('customers','{"search":"test_d"}','csv',null,'csv test') as ex4 \gset
select tt.chk('T4 csv: header line, a name that starts with = is neutralised with a leading quote (formula guard)', (:'ex4'::jsonb ->> 'format')='csv' and (:'ex4'::jsonb ->> 'csv') like 'id,name,mobile,%' and (:'ex4'::jsonb ->> 'csv') like '%,''=test_d,%');
reset role; select tt.as(:'u_o'); select set_rule('crm_export_max_rows','50') is null as ecap2 \gset
set role authenticated; select tt.as(:'u_o');
select _crmb_export('customers','{}','json') as ex5 \gset
select tt.chk('T4 owner: no reason needed, full numbers (owner always sees), not truncated', (:'ex5'::jsonb ->> 'masked')='false' and (:'ex5'::jsonb ->> 'truncated')='false' and position('01740400001' in :'ex5')>0);
select tt.chk('T4 the owner can limit with p_limit below the cap', (_crmb_export('customers','{}','json',1) ->> 'count')='1');
select tt.chk('T4 the owner reads the export log', (select jsonb_array_length(_crmb_export_log_list()))>=5);
select tt.as(:'u_x');
select tt.err('T4 the exporter cannot read the export log (owner only)', $$select _crmb_export_log_list()$$, 'not allowed');
select tt.chk('T4 policy for the exporter: can_export true, cap 50', (select _crmb_policy() ->> 'can_export')='true' and (select _crmb_policy() ->> 'export_cap')='50');
select tt.as(:'u_c');
select tt.chk('T4 policy for the cashier: can_export false', (select _crmb_policy() ->> 'can_export')='false');
reset role;
select tt.err('T4 export-log lines cannot be changed or deleted', $$delete from crm_export_log$$, 'append-only');

\echo == T5 print log
set role authenticated; select tt.as(:'u_c');
select _crmb_print_log('customer_list', 3, 'monthly sheet') as pl \gset
select tt.chk('T5 default: a cashier may print and it is logged (kind print, masked because the guard is ON)', :'pl'::bigint > 0 and tt.q(format($$select count(*) from crm_export_log where id=%s and kind='print' and masked and row_count=3$$, :'pl'))='1');
select tt.err('T5 bad kind of print', $$select _crmb_print_log('everything', 3)$$, 'bad_input');
select tt.err('T5 negative count', $$select _crmb_print_log('customer_list', -1)$$, 'bad_input');
reset role; select tt.as(:'u_o'); select set_rule('crm_print_needs_export','true') is null as pne \gset
set role authenticated; select tt.as(:'u_c');
select tt.err('T5 print-needs-export ON: a cashier cannot print', $$select _crmb_print_log('customer_list', 3)$$, 'not allowed');
select tt.chk('T5 policy for the cashier: can_print false', (select _crmb_policy() ->> 'can_print')='false');
select tt.as(:'u_x');
select tt.chk('T5 the exporter can still print', (select _crmb_print_log('customer_list', 3) > 0) and (select _crmb_policy() ->> 'can_print')='true');
reset role;

\echo == T6 consent register (names, masked phone, status)
select tt.as(:'u_o');
select _crmb_consent_set(gen_random_uuid(), :'ca', 'sms', true, 'paper_form', 'form 1') is not null as c_a \gset
select _crmb_consent_set(gen_random_uuid(), :'cb', 'sms', false, 'phone', 'asked to stop') is not null as c_b \gset
set role authenticated; select tt.as(:'u_c');
select tt.err('T6 cashier cannot open the register', $$select _crmb_consent_register()$$, 'not allowed');
select tt.as(:'u_m');
select _crmb_consent_register(null, 'sms', null, 50, 0) as rg \gset
select tt.chk('T6 manager: rows with masked phone while the guard is ON; summary inside', (:'rg'::jsonb ->> 'masked')='true' and position('01740400001' in :'rg')=0 and (:'rg'::jsonb -> 'summary' -> 'channels' -> 'sms' ->> 'in')='1');
select tt.chk('T6 status filter in / out / not_asked', (select (_crmb_consent_register('in','sms') ->> 'total')='1' and (_crmb_consent_register('out','sms') ->> 'total')='1'
   and (_crmb_consent_register('not_asked','sms') ->> 'total')::int = (select count(*) from customers where active)-2));
select tt.chk('T6 search by name works; digits of a hidden number do not match', (_crmb_consent_register(null,'sms','test_a') ->> 'total')='1' and (_crmb_consent_register(null,'sms','1740400001') ->> 'total')='0');
select tt.err('T6 bad status', $$select _crmb_consent_register('maybe','sms')$$, 'bad_input');
select tt.err('T6 bad channel', $$select _crmb_consent_register(null,'email')$$, 'bad_input');
select tt.as(:'u_g');
select tt.err('T6 holder of crm_contact_view but no consent right cannot open the register', $$select _crmb_consent_register()$$, 'not allowed');
reset role;

\echo == T7 policy by role
set role authenticated; select tt.as(:'u_o');
select tt.chk('T7 owner: all true', (select _crmb_policy() ->> 'contact_ok')='true' and (select _crmb_policy() ->> 'can_export')='true' and (select _crmb_policy() ->> 'can_consent')='true' and (select _crmb_policy() ->> 'is_owner')='true');
select tt.as(:'u_n');
select tt.chk('T7 user without POS: no print, no export, no consent', (select _crmb_policy() ->> 'can_print')='false' and (select _crmb_policy() ->> 'can_export')='false' and (select _crmb_policy() ->> 'can_consent')='false');
select tt.as('');
select tt.err('T7 nobody signed in', $$select _crmb_policy()$$, 'not allowed');
reset role;

\echo == T8 nothing in the books or sales moved; paste again changes nothing
select tt.chk('T8 no journal entry and no sale was made by any privacy function', tt.je()=:'je0' and (select count(*) from sales)=:'sales0'::bigint);
select count(*) as rules_n, (select count(*) from grant_defs where grant_code like 'crm\_%') as gd_n, (select count(*) from pg_proc where proname like '\_crmb\_%') as fn_n, (select count(*) from crm_view_log) as vl_n from rules where key like 'crm\_%' \gset
\ir phase304.sql
select tt.chk('T8 re-pasting phase304: no new rule, grant, function or log line', (select count(*) from rules where key like 'crm\_%')=:'rules_n' and (select count(*) from grant_defs where grant_code like 'crm\_%')=:'gd_n'
  and (select count(*) from pg_proc where proname like '\_crmb\_%')=:'fn_n' and (select count(*) from crm_view_log)=:'vl_n' and rule_on('crm_pii_guard_on'));
select tt.chk('T8 and the grants are still in place', has_function_privilege('authenticated','public._crmb_customer_list(int,boolean)','execute'));

select 'RESULT phase304: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
