-- Phase 534 tests (UNION-6: acct_journal_post). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain, tests/sql/run_all_union.sh). Prints PASS / FAIL per check.
-- Test users and items are neutral test_* ids. Run on the final database.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f534'
create schema if not exists t534;
create table if not exists t534.res (name text, ok boolean);
truncate t534.res;
create or replace function t534.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t534.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t534.def(p_sig text) returns text language sql as $$ select pg_get_functiondef(p_sig::regprocedure) $$;
create or replace function t534.has(p_sig text, p_text text) returns boolean language sql as $$ select position(p_text in pg_get_functiondef(p_sig::regprocedure)) > 0 $$;
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner534@test.invalid', '{"full_name":"test_owner534"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;

\echo == T1 both functions carry the guard and the gate
select t534.chk('T1a the 7-argument function has the bos85 manual journal guard and our journal gate', t534.has('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', 'manual_journal_guard') and t534.has('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)', '_w1e_journal_gate'));
select t534.chk('T1b the 8-argument function has the bos85 guard with p_reason and our journal gate', t534.has('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', '_manual_guard85(ln, p_reason)') and t534.has('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)', '_w1e_journal_gate'));
select t534.chk('T1c no parameter default on the 8-argument function (no ambiguity)', (select pronargdefaults = 0 from pg_proc where oid = 'public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)'::regprocedure));
select t534.chk('T1d manual_journal_guard defaults off', coalesce((select default_value::text from rules where key = 'manual_journal_guard'), '"off"') = '"off"');
select set_config('request.jwt.claim.sub', :'o', false);
do $t$ begin
  begin perform public.acct_journal_post(current_date, 1, 'test_t534 smoke', '[{"code":"1110","debit":1},{"code":"4100","credit":1}]'::jsonb, null, null, true); perform t534.chk('T2a a dry run through the 7-argument function works', true);
  exception when others then perform t534.chk('T2a a dry run through the 7-argument function works (' || sqlerrm || ')', sqlerrm not like '%not unique%' and sqlerrm not like '%does not exist%'); end;
  begin perform public.acct_journal_post(current_date, 1, 'test_t534 smoke', '[{"code":"1110","debit":1},{"code":"4100","credit":1}]'::jsonb, null, null, true, 'test'); perform t534.chk('T2b a dry run through the 8-argument function works', true);
  exception when others then perform t534.chk('T2b a dry run through the 8-argument function works (' || sqlerrm || ')', sqlerrm not like '%not unique%' and sqlerrm not like '%does not exist%'); end;
end $t$;
select md5(t534.def('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') || t534.def('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)')) as hb, (select count(*) from public._union_fn_backup) as nb \gset
\i supabase/phase534.sql
select t534.chk('T3 a second paste changes nothing', md5(t534.def('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean)') || t534.def('public.acct_journal_post(date,integer,text,jsonb,uuid,text,boolean,text)')) = :'hb' and (select count(*) from public._union_fn_backup) = :nb);

\echo == RESULT
select 'phase534 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t534.res;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from t534.res;
select name from t534.res where not ok;
