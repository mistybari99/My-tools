-- Phase 529 tests (UNION-1: the shim before our packages). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain, tests/sql/run_all_union.sh). Prints PASS / FAIL per check.
-- Test users and items are neutral test_* ids. Run on the database through phase529 (the advanced block pasted, our packages not yet).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f529'
create schema if not exists t529;
create table if not exists t529.res (name text, ok boolean);
truncate t529.res;
create or replace function t529.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t529.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t529.def(p_sig text) returns text language sql as $$ select pg_get_functiondef(p_sig::regprocedure) $$;
create or replace function t529.has(p_sig text, p_text text) returns boolean language sql as $$ select position(p_text in pg_get_functiondef(p_sig::regprocedure)) > 0 $$;

\echo == T1 lock_check has the phase 6 text our hooks look for, and not the bos113 owner mode
select t529.chk('T1a lock_check carries the phase 6 hook site', t529.has('public.lock_check(date)', 'if p_date is null or public.is_owner() then return; end if;'));
select t529.chk('T1b lock_check has no bos113 text any more (phase530 puts it back after our hooks)', not t529.has('public.lock_check(date)', 'bos113'));
select t529.chk('T1c the advanced body was saved first', exists (select 1 from public._union_fn_backup where fn = 'public.lock_check(date)' and position('bos113' in def) > 0));
\echo == T2 acct_journal_post: one 7-argument and one 8-argument function, no ambiguity
select t529.chk('T2a the 7-argument function exists (phase88 needs it)', to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') is not null);
select t529.chk('T2b the 8-argument function exists and has NO parameter default', to_regprocedure('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)') is not null
  and (select pronargdefaults = 0 from pg_proc where oid = 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)'::regprocedure));
select t529.chk('T2c the 7-argument function keeps its 3 defaults', (select pronargdefaults = 3 from pg_proc where oid = 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)'::regprocedure));
do $t$ begin
  begin perform public.acct_journal_post(null::date, 1, 'test', '[]'::jsonb); perform t529.chk('T2d a short call is not ambiguous', true);
  exception when others then perform t529.chk('T2d a short call is not ambiguous (' || sqlerrm || ')', sqlerrm not like '%not unique%'); end;
end $t$;
select t529.chk('T2e only authenticated may execute both', has_function_privilege('authenticated', 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'execute') and not has_function_privilege('anon', 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'execute') and not has_function_privilege('anon', 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', 'execute'));
\echo == T3 the base texts of the four hooked functions are back
select t529.chk('T3a _cust_bal has no scope133 yet', not t529.has('public._cust_bal(uuid)', 'scope133'));
select t529.chk('T3b customer_dues has no bos105 mask yet', not t529.has('public.customer_dues()', 'bos105'));
select t529.chk('T3c rpt_agg_sql has no bos110 set-based join yet', not t529.has('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'bos110'));
select t529.chk('T3d biz_items has no bos112 netting yet', not t529.has('public.biz_items(date,date,integer)', 'bos112'));
\echo == T4 the backup table is closed to the browser and pasting the file again changes nothing
select t529.chk('T4a _union_fn_backup has row level security and no grant to anon', (select relrowsecurity from pg_class where oid = 'public._union_fn_backup'::regclass) and not has_table_privilege('anon', 'public._union_fn_backup', 'select'));
select count(*) as nb, md5(string_agg(md5(def), '' order by id)) as hb from public._union_fn_backup \gset
select md5(t529.def('public.lock_check(date)')) as hl \gset
\i supabase/phase529.sql
select t529.chk('T4b a second paste adds no backup row and keeps lock_check', (select count(*) from public._union_fn_backup) = :nb and md5(t529.def('public.lock_check(date)')) = :'hl');

\echo == RESULT
select 'phase529 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t529.res;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from t529.res;
select name from t529.res where not ok;
