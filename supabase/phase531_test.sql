-- Phase 531 tests (UNION-3: biz_items and rpt_agg_sql). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain, tests/sql/run_all_union.sh). Prints PASS / FAIL per check.
-- Test users and items are neutral test_* ids. Run on the final database.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f531'
create schema if not exists t531;
create table if not exists t531.res (name text, ok boolean);
truncate t531.res;
create or replace function t531.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t531.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t531.def(p_sig text) returns text language sql as $$ select pg_get_functiondef(p_sig::regprocedure) $$;
create or replace function t531.has(p_sig text, p_text text) returns boolean language sql as $$ select position(p_text in pg_get_functiondef(p_sig::regprocedure)) > 0 $$;
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner531@test.invalid', '{"full_name":"test_owner531"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;

\echo == T1 tags of both lines are in the merged bodies
select t531.chk('T1a biz_items: bos112 netting, phase 502 netting, bos402 cost hook, bos88 cost source', t531.has('public.biz_items(date,date,integer)', 'items_net_of_returns') and t531.has('public.biz_items(date,date,integer)', 'biz_items_net_returns')
  and t531.has('public.biz_items(date,date,integer)', 'bos402') and t531.has('public.biz_items(date,date,integer)', 'bos88'));
select t531.chk('T1b biz_items: the phase 502 returns never run while the advanced netting is on (no double take-off)', t531.has('public.biz_items(date,date,integer)', 'and not nr'));
select t531.chk('T1c rpt_agg_sql: bos110 set-based join and bos402 ledger_first join', t531.has('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'bos110') and t531.has('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)', 'bos402'));
\echo == T2 with every switch at its default the item analysis runs for the owner
select set_config('request.jwt.claim.sub', :'o', false);
select t531.chk('T2a biz_items runs (default switches)', (select count(*) >= 0 from biz_items(current_date - 30, current_date)));
select t531.chk('T2b the cost basis rule is at its default (price list)', coalesce(rule_txt('reports_cost_basis'), 'price_list') <> 'ledger_first');
select md5(t531.def('public.biz_items(date,date,integer)') || t531.def('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)')) as hb, (select count(*) from public._union_fn_backup) as nb \gset
\i supabase/phase531.sql
select t531.chk('T3 a second paste changes nothing', md5(t531.def('public.biz_items(date,date,integer)') || t531.def('public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)')) = :'hb' and (select count(*) from public._union_fn_backup) = :nb);

\echo == RESULT
select 'phase531 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t531.res;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from t531.res;
select name from t531.res where not ok;
