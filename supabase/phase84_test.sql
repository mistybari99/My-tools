-- FRESH DB ONLY. Phase 84 tests: balance check (G11) and guarded test reset (G13). Test data only, no person names. Place 1 only.
--   ORDER="phase8 ... phase79 phase84 phase84_test_project_only" bash <copy of tests/sql/build_fresh_db.sh with your paths> e84db   (the reset functions are in phase84_test_project_only.sql, test projects only)
--   psql -h /tmp -p 5549 -U postgres -d e84db -qAt -f supabase/phase84_test.sql | grep -E "FAIL|RESULT"
-- All numbers are hand-computed (comment above each block).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-0000000000e1'
\set ap '00000000-0000-0000-0000-0000000000e2'
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
create or replace function tt.unbalanced_entries() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'ap','test_other@s.app','{"full_name":"test_other"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ap','recipe_approver') on conflict do nothing;
insert into user_locations values (:'ap',1) on conflict do nothing;

\echo == T0 installed, safe defaults
select tt.chk('T0 rule allow_test_reset exists and is OFF by default', (select coalesce(value, default_value) from rules where key='allow_test_reset') = 'false'::jsonb and (select value from rules where key='allow_test_reset') is null);
select tt.chk('T0 the two lists do not overlap', not exists (select 1 from unnest(_e_reset_tables()) a join unnest(_e_reset_protected()) b on a=b));
select tt.chk('T0 items, rules, roles, locations are protected', _e_reset_protected() @> array['items','rules','roles','locations','forms','coa_accounts','audit_log']);
select tt.chk('T0 anon cannot run the reset or the check', not has_function_privilege('anon','public._e_test_reset(text)','execute') and not has_function_privilege('anon','public._e_balance_check(date,int,int)','execute'));

\echo == setup: accounting on, stock and a few postings at place 1
set role authenticated; select tt.as(:'o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
reset role;
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type) values
 ('E84-A','test_a','test_a','kg','kg',0,true,'raw_material'),
 ('E84-B','test_b','test_b','kg','kg',0,true,'raw_material');
select id as ia from items where code='E84-A' \gset
select id as ib from items where code='E84-B' \gset
set role authenticated; select tt.as(:'o');
-- A: opening 100, issue 30 -> 70.  B: opening 50 -> 50.
select stock_opening(:'ia'::uuid,1,100,10) is not null as s1 \gset
select stock_opening(:'ib'::uuid,1,50,4) is not null as s2 \gset
select stock_issue(:'ia'::uuid,1,30) is not null as s3 \gset
-- journal: capital 10000 Dr cash 1110 / Cr 3100 ; rent 2000 Dr 5300 / Cr 1110
select acct_journal_post(tt.today(),1,'test capital in',format('[{"code":"1110","debit":10000},{"code":"3100","credit":10000}]')::jsonb) is not null as j1 \gset
select acct_journal_post(tt.today(),1,'test rent paid',format('[{"code":"5300","debit":2000},{"code":"1110","credit":2000}]')::jsonb) is not null as j2 \gset
select _e_balance_check() as g1 \gset
select _e_balance_check(null, 1) as g2 \gset
reset role;

\echo == G11 green path
select tt.chk('G1 books balance: status green, no reds', :'g1'::jsonb->>'status'='green' and :'g1'::jsonb->'reds'='[]'::jsonb);
-- assets: cash 10000-2000 = 8000 ; equity 10000 ; earnings = 0 income - 2000 expense = -2000 ; 8000 = 0 + 10000 - 2000
select tt.chk('G1 equation: assets 8000 = liabilities 0 + equity 10000 + earnings -2000, difference 0',
  (:'g1'::jsonb#>>'{equation,assets}')::numeric=8000 and (:'g1'::jsonb#>>'{equation,liabilities}')::numeric=0 and (:'g1'::jsonb#>>'{equation,equity}')::numeric=10000
  and (:'g1'::jsonb#>>'{equation,earnings}')::numeric=-2000 and (:'g1'::jsonb#>>'{equation,difference}')::numeric=0 and (:'g1'::jsonb#>>'{equation,ok}')::boolean);
select tt.chk('G1 trial balance: debit = credit', (:'g1'::jsonb#>>'{trial_balance,total_debit}')::numeric=(:'g1'::jsonb#>>'{trial_balance,total_credit}')::numeric and (:'g1'::jsonb#>>'{trial_balance,ok}')::boolean
  and (:'g1'::jsonb#>>'{trial_balance,total_debit}')::numeric > 0);
select tt.chk('G1 no broken journal entry, no broken stock identity', (:'g1'::jsonb#>>'{journal,broken}')::int=0 and (:'g1'::jsonb#>>'{stock_identity,broken}')::int=0);
select tt.chk('G1 cross-check blocks are present (day book, stock vs journal, unposted)', (:'g1'::jsonb->'cross_checks') ?& array['daybook_vs_journal','inventory_vs_gl','unposted_sources']);
select tt.chk('G1 place filter works (place 1 also green)', :'g2'::jsonb->>'status'='green');

\echo == G11 permissions and read-only
select tt.as(:'ap');
set role authenticated;
select tt.err('P1 a user without the accounts grant is refused', 'select _e_balance_check()', 'not allowed');
reset role;
select tt.chk('P2 the check wrote nothing (no row in the reset log, no new journal entry)', (select count(*) from _e_reset_log)=0 and (select count(*) from journal_entries)=2);

\echo == G11 negative: a stock break is detected
-- closing for A should be 70; force stock_balance to 75 behind the ledger's back
update stock_balance set qty = 75 where item_id=:'ia'::uuid and location_id=1;
set role authenticated; select tt.as(:'o');
select _e_balance_check() as s_bad \gset
reset role;
select tt.chk('N1 stock identity break found: status red, 1 row, expected 70 closing 75', :'s_bad'::jsonb->>'status'='red' and (:'s_bad'::jsonb#>>'{stock_identity,broken}')::int=1
  and (:'s_bad'::jsonb#>>'{stock_identity,rows,0,expected_closing}')::numeric=70 and (:'s_bad'::jsonb#>>'{stock_identity,rows,0,stock_balance}')::numeric=75 and (:'s_bad'::jsonb#>>'{stock_identity,rows,0,opening}')::numeric=100
  and (:'s_bad'::jsonb#>>'{stock_identity,rows,0,out}')::numeric=30 and (:'s_bad'::jsonb->'reds') ? 'stock_identity');
update stock_balance set qty = 70 where item_id=:'ia'::uuid and location_id=1;
set role authenticated; select tt.as(:'o');
select _e_balance_check() as s_ok \gset
reset role;
select tt.chk('N1 after the fix it is green again', :'s_ok'::jsonb->>'status'='green');

\echo == G11 negative: a seeded unbalanced journal entry is detected
-- 7000 debit on cash with only 6900 credit on capital: difference 100
insert into journal_entries (entry_date, location_id, source_type, source_id, memo) values (tt.today(), 1, 'manual', 'test_unbalanced_1', 'test unbalanced fixture') returning id as ue \gset
alter table journal_lines disable trigger jl_balance;   -- the books refuse an unbalanced entry at commit; this fixture bypasses that on purpose
insert into journal_lines (entry_id, line_no, account_id, debit, credit, location_id) values
 (:ue, 1, (select id from coa_accounts where code='1110'), 7000, 0, 1),
 (:ue, 2, (select id from coa_accounts where code='3100'), 0, 6900, 1);
alter table journal_lines enable trigger jl_balance;
select tt.chk('N2 fixture really is unbalanced (helper sees 1)', tt.unbalanced_entries()=1);
set role authenticated; select tt.as(:'o');
select _e_balance_check() as u_bad \gset
reset role;
select tt.chk('N2 status red; journal lists exactly that entry with diff 100', :'u_bad'::jsonb->>'status'='red' and (:'u_bad'::jsonb#>>'{journal,broken}')::int=1
  and (:'u_bad'::jsonb#>>'{journal,rows,0,entry_id}')::bigint=:ue and (:'u_bad'::jsonb#>>'{journal,rows,0,diff}')::numeric=100 and (:'u_bad'::jsonb->'reds') ? 'journal');
-- cash 8000+7000 = 15000 ; equity 10000+6900 = 16900 ; earnings -2000 ; 15000 - (16900 - 2000) = 100
select tt.chk('N2 the equation and the trial balance break by the same 100', (:'u_bad'::jsonb#>>'{equation,difference}')::numeric=100 and not (:'u_bad'::jsonb#>>'{equation,ok}')::boolean
  and (:'u_bad'::jsonb#>>'{trial_balance,difference}')::numeric=100 and (:'u_bad'::jsonb->'reds') ? 'equation' and (:'u_bad'::jsonb->'reds') ? 'trial_balance');
-- an entry with no lines at all
insert into journal_entries (entry_date, location_id, source_type, source_id, memo) values (tt.today(), 1, 'manual', 'test_empty_1', 'test entry with no lines') returning id as ee \gset
set role authenticated; select tt.as(:'o');
select _e_balance_check() as e_bad \gset
reset role;
select tt.chk('N3 an entry with no lines is also listed (2 broken)', (:'e_bad'::jsonb#>>'{journal,broken}')::int=2 and exists (select 1 from jsonb_array_elements(:'e_bad'::jsonb#>'{journal,rows}') r where (r->>'entry_id')::bigint=:ee and (r->>'lines')::int=0));

\echo == G13 the reset refuses by default
select count(*) as je0 from journal_entries \gset
select count(*) as sl0 from stock_ledger \gset
set role authenticated; select tt.as(:'o');
select tt.err('R1 default install: owner calling the reset is refused (flag OFF)', $$select _e_test_reset('DELETE ALL TEST DATA')$$, 'allow_test_reset is OFF');
select tt.err('R1 default install with no phrase is refused', $$select _e_test_reset()$$, 'test_reset_refused');
select tt.err('R1 default install with a wrong phrase is refused', $$select _e_test_reset('please')$$, 'test_reset_refused');
select _e_test_reset_state() as rs0 \gset
reset role;
select tt.chk('R1 nothing was cleared', (select count(*) from journal_entries)=:je0 and (select count(*) from stock_ledger)=:sl0 and (select count(*) from _e_reset_log)=0);
select tt.chk('R1 state report says not allowed', not (:'rs0'::jsonb->>'allowed')::boolean and not (:'rs0'::jsonb->>'flag')::boolean);

\echo == G13 flag on, but phrase wrong / caller not owner
set role authenticated; select tt.as(:'o');
select set_rule('allow_test_reset','true') is null as f_on \gset
select tt.err('R2 flag ON, no phrase: refused', $$select _e_test_reset()$$, 'wrong confirmation phrase');
select tt.err('R2 flag ON, wrong phrase: refused', $$select _e_test_reset('delete all test data')$$, 'wrong confirmation phrase');
select tt.err('R2 flag ON, close phrase: refused', $$select _e_test_reset('DELETE ALL TEST DATA ')$$, 'wrong confirmation phrase');
select tt.as(:'ap');
select tt.err('R3 flag ON, right phrase, but not the owner: refused', $$select _e_test_reset('DELETE ALL TEST DATA')$$, 'owner only');
reset role;
select tt.chk('R2/R3 nothing was cleared and the flag is still ON', (select count(*) from journal_entries)=:je0 and (select count(*) from stock_ledger)=:sl0 and rule_on('allow_test_reset'));

\echo == G13 the real reset on this test database
-- snapshot of the setup tables
create table tt.snap as select 'items' t, count(*) n from items union all select 'rules', count(*) from rules union all select 'roles', count(*) from roles
  union all select 'locations', count(*) from locations union all select 'forms', count(*) from forms union all select 'coa_accounts', count(*) from coa_accounts
  union all select 'acct_mappings', count(*) from acct_mappings union all select 'option_lists', count(*) from option_lists union all select 'user_roles', count(*) from user_roles
  union all select 'profiles', count(*) from profiles union all select 'grant_defs', count(*) from grant_defs;
select count(*) as audit0 from audit_log \gset
set role authenticated; select tt.as(:'o');
select _e_test_reset('DELETE ALL TEST DATA') as rr \gset
reset role;
select tt.chk('R4 the reset says ok and counted rows', (:'rr'::jsonb->>'ok')::boolean and (:'rr'::jsonb->>'rows_cleared')::bigint >= 1 and (:'rr'::jsonb->>'tables_cleared')::int >= 10);
select tt.chk('R4 journal, stock ledger and stock balance are empty', (select count(*) from journal_entries)=0 and (select count(*) from journal_lines)=0
  and (select count(*) from stock_ledger)=0 and (select count(*) from stock_balance)=0);
select tt.chk('R4 setup tables are intact (items, rules, roles, locations, forms, chart of accounts, mappings, lists, user roles, profiles, grant defs)',
  (select count(*) from items)=(select n from tt.snap where t='items') and (select count(*) from rules)=(select n from tt.snap where t='rules') and (select count(*) from roles)=(select n from tt.snap where t='roles')
  and (select count(*) from locations)=(select n from tt.snap where t='locations') and (select count(*) from forms)=(select n from tt.snap where t='forms')
  and (select count(*) from coa_accounts)=(select n from tt.snap where t='coa_accounts') and (select count(*) from acct_mappings)=(select n from tt.snap where t='acct_mappings')
  and (select count(*) from option_lists)=(select n from tt.snap where t='option_lists') and (select count(*) from user_roles)=(select n from tt.snap where t='user_roles')
  and (select count(*) from profiles)=(select n from tt.snap where t='profiles') and (select count(*) from grant_defs)=(select n from tt.snap where t='grant_defs'));
select tt.chk('R4 the two test items are still there (only their stock is gone)', (select count(*) from items where code in ('E84-A','E84-B'))=2);
select tt.chk('R4 the change log (audit_log) was not cleared', (select count(*) from audit_log) >= :audit0);
select tt.chk('R4 the flag switched itself OFF; one line in the reset log', not rule_on('allow_test_reset') and (select count(*) from _e_reset_log)=1 and (select rows_cleared from _e_reset_log) = (:'rr'::jsonb->>'rows_cleared')::bigint);
select tt.chk('R4 append-only triggers are switched on again', not exists (select 1 from pg_trigger t where t.tgrelid in ('journal_entries'::regclass,'journal_lines'::regclass,'stock_ledger'::regclass) and not t.tgisinternal and t.tgenabled <> 'O'));
select tt.chk('R4 the ledger is still immutable after the reset', (select count(*) from pg_trigger where tgrelid='stock_ledger'::regclass and tgname='stock_ledger_no_update')=1);
set role authenticated; select tt.as(:'o');
select tt.err('R5 a second call straight after is refused (flag is OFF again)', $$select _e_test_reset('DELETE ALL TEST DATA')$$, 'allow_test_reset is OFF');
-- the books still work after the reset: post again, and the check is green on the empty-then-new books
select acct_journal_post(tt.today(),1,'test after reset',format('[{"code":"1110","debit":500},{"code":"3100","credit":500}]')::jsonb) is not null as j3 \gset
select _e_balance_check() as post_g \gset
reset role;
select tt.chk('R6 after the reset the books accept a posting and the check is green', :'post_g'::jsonb->>'status'='green' and (:'post_g'::jsonb#>>'{equation,assets}')::numeric=500);
select tt.err('R6 a journal entry still cannot be deleted (append-only is back)', $$delete from journal_entries$$, 'append_only');

\echo == the clear list only names tables that are not setup
select tt.chk('S1 every name in the clear list that exists is not protected', not exists (select 1 from unnest(_e_reset_tables()) x where x = any(_e_reset_protected())));
select tt.chk('S2 the reset log table has RLS on and no browser access', (select relrowsecurity from pg_class where oid='_e_reset_log'::regclass) and not has_table_privilege('authenticated','public._e_reset_log','select'));

select count(*) filter (where ok) as pass, count(*) filter (where not ok) as fail from tt.res \gset
\echo RESULT :pass pass :fail fail
select name from tt.res where not ok;
