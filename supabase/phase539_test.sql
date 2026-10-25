-- Phase 539 tests (UNION-11: stale overloads and the audit). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain, tests/sql/run_all_union.sh). Prints PASS / FAIL per check.
-- Test users and items are neutral test_* ids. Run on the final database.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f539'
create schema if not exists t539;
create table if not exists t539.res (name text, ok boolean);
truncate t539.res;
create or replace function t539.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t539.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t539.def(p_sig text) returns text language sql as $$ select pg_get_functiondef(p_sig::regprocedure) $$;
create or replace function t539.has(p_sig text, p_text text) returns boolean language sql as $$ select position(p_text in pg_get_functiondef(p_sig::regprocedure)) > 0 $$;

\echo == T1 stale overloads
select t539.chk('T1a no 9-argument inbound_message_receive next to the 10-argument one', to_regprocedure('public.inbound_message_receive(text,text,text,text,text,text,timestamp with time zone,text,boolean)') is null and to_regprocedure('public.inbound_message_receive(text,text,text,text,text,text,timestamp with time zone,text,boolean,text)') is not null);
select t539.chk('T1b no 13-argument web_order_submit next to the 14-argument one', to_regprocedure('public.web_order_submit(text,uuid,text,text,text,text,jsonb,text,text,text,text,text,boolean)') is null and to_regprocedure('public.web_order_submit(text,uuid,text,text,text,text,jsonb,text,text,text,text,text,boolean,text)') is not null);
\echo == T2 the audit
select t539.chk('T2a 156 functions are recorded', (select count(*) from public._union_fn_expected) = 156);
select t539.chk('T2b every one of them has exactly the merged text', (select count(*) from public._union_audit() where state <> 'merged') = 0);
select t539.chk('T2c the audit and the recorded md5 are closed to the browser', not has_function_privilege('anon', 'public._union_audit()', 'execute') and not has_function_privilege('authenticated', 'public._union_audit()', 'execute') and not has_table_privilege('authenticated', 'public._union_fn_expected', 'select'));
\echo == T3 pasting the whole union set again changes nothing
select count(*) as nb from public._union_fn_backup \gset
\i supabase/phase529.sql
\i supabase/phase530.sql
\i supabase/phase531.sql
\i supabase/phase532.sql
\i supabase/phase533.sql
\i supabase/phase534.sql
\i supabase/phase535.sql
\i supabase/phase536.sql
\i supabase/phase537.sql
\i supabase/phase538.sql
\i supabase/phase539.sql
select t539.chk('T3a nothing changed: still 156 merged, no new backup row', (select count(*) from public._union_audit() where state = 'merged') = 156 and (select count(*) from public._union_fn_backup) = :nb);
select t539.chk('T3b the hook list of our packages is complete', (select count(*) from public._i2_state() where not present) = 0);

\echo == RESULT
select 'phase539 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t539.res;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from t539.res;
select name from t539.res where not ok;
