-- Phase 530 tests (UNION-2: lock_check with both lines). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain, tests/sql/run_all_union.sh). Prints PASS / FAIL per check.
-- Test users and items are neutral test_* ids. Run on the final database (needs our packages and phase530).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f530'
create schema if not exists t530;
create table if not exists t530.res (name text, ok boolean);
truncate t530.res;
create or replace function t530.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t530.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t530.def(p_sig text) returns text language sql as $$ select pg_get_functiondef(p_sig::regprocedure) $$;
create or replace function t530.has(p_sig text, p_text text) returns boolean language sql as $$ select position(p_text in pg_get_functiondef(p_sig::regprocedure)) > 0 $$;
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner530@test.invalid', '{"full_name":"test_owner530"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;

\echo == T1 the merged lock_check carries every tag
select t530.chk('T1a bos113 owner mode, bos87 one-off exception and bos89 period integrity are all in the body', t530.has('public.lock_check(date)', 'bos113') and t530.has('public.lock_check(date)', 'bos87') and t530.has('public.lock_check(date)', 'bos89'));
select t530.chk('T1b the owner modes default off (both rules)', coalesce((select default_value::text from rules where key = 'period_lock_owner_mode'), '"off"') in ('"off"', 'null')
  and coalesce((select default_value::text from rules where key = 'owner_closed_period_mode'), '"off"') in ('"off"', 'null'));
\echo == T2 behaviour
update rules set value = to_jsonb('2000-01-31'::text) where key = 'period_closed_until';
select set_config('request.jwt.claim.sub', :'o', false);
do $t$ begin
  begin perform lock_check('2000-01-15'); perform t530.chk('T2a an owner passes a closed date with the modes off', true);
  exception when others then perform t530.chk('T2a an owner passes a closed date with the modes off (' || sqlerrm || ')', false); end;
end $t$;
select t530.chk('T2a2 and no exception line is written', not exists (select 1 from exceptions where flag_code = 'closed_period_owner' and entry_date = '2000-01-15'));
update rules set value = to_jsonb('warn'::text) where key = 'period_lock_owner_mode';
select lock_check('2000-01-16') as x \gset
select t530.chk('T2b with period_lock_owner_mode = warn the owner passes and a yellow closed_period_owner line is written', exists (select 1 from exceptions where flag_code = 'closed_period_owner' and entry_date = '2000-01-16'));
select lock_check('2000-01-16') as x \gset
select t530.chk('T2c the line is written once a day per date', (select count(*) from exceptions where flag_code = 'closed_period_owner' and entry_date = '2000-01-16') = 1);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000a530', false);
do $t$ begin
  begin perform lock_check('2000-01-17'); perform t530.chk('T2d a person who is not the owner is refused on a closed date', false);
  exception when others then perform t530.chk('T2d a person who is not the owner is refused on a closed date', sqlerrm like '%period_closed%'); end;
end $t$;
update rules set value = null where key in ('period_closed_until', 'period_lock_owner_mode');
delete from exceptions where flag_code = 'closed_period_owner' and entry_date between '2000-01-15' and '2000-01-17';
select md5(t530.def('public.lock_check(date)')) as hl, (select count(*) from public._union_fn_backup) as nb \gset
\i supabase/phase530.sql
select t530.chk('T3 a second paste changes nothing', md5(t530.def('public.lock_check(date)')) = :'hl' and (select count(*) from public._union_fn_backup) = :nb);

\echo == RESULT
select 'phase530 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t530.res;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from t530.res;
select name from t530.res where not ok;
