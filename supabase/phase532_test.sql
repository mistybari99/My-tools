-- Phase 532 tests (UNION-4: books and balances). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain, tests/sql/run_all_union.sh). Prints PASS / FAIL per check.
-- Test users and items are neutral test_* ids. Run on the final database.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f532'
create schema if not exists t532;
create table if not exists t532.res (name text, ok boolean);
truncate t532.res;
create or replace function t532.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t532.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t532.def(p_sig text) returns text language sql as $$ select pg_get_functiondef(p_sig::regprocedure) $$;
create or replace function t532.has(p_sig text, p_text text) returns boolean language sql as $$ select position(p_text in pg_get_functiondef(p_sig::regprocedure)) > 0 $$;
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner532@test.invalid', '{"full_name":"test_owner532"}') on conflict do nothing;
update profiles set status = 'active' where id = :'o';
insert into user_roles values (:'o', 'owner') on conflict do nothing;

\echo == T1 tags
select t532.chk('T1a _cust_bal: open parties (bos88) and business scope (scope133)', t532.has('public._cust_bal(uuid)', '_w1a_cust_open') and t532.has('public._cust_bal(uuid)', 'scope133'));
select t532.chk('T1b customer_dues: bos88, mobile mask (bos105), scope and phase 503 advance', t532.has('public.customer_dues()', '_w1a_cust_open') and t532.has('public.customer_dues()', 'bos105') and t532.has('public.customer_dues()', '_org_on123') and t532.has('public.customer_dues()', 'dues_net_advance_on'));
select t532.chk('T1c _acct_docs: our sources (bos85/87/96) and the advanced sources (transit loss, purchase variance, card settlement, landed cost, cash variance)', t532.has('public._acct_docs(date)', '_w1f_docs') and t532.has('public._acct_docs(date)', '_m_docs') and t532.has('public._acct_docs(date)', '_b_docs')
  and t532.has('public._acct_docs(date)', 'transit_loss') and t532.has('public._acct_docs(date)', 'purchase_variance') and t532.has('public._acct_docs(date)', 'card_settlement') and t532.has('public._acct_docs(date)', 'landed_cost') and t532.has('public._acct_docs(date)', 'cash_variance'));
select t532.chk('T1d _daybook_lines: money account (bos87), pay mode (bos113), card fee and drawer rows', t532.has('public._daybook_lines(integer[],integer[],date,date)', '_m_mode') and t532.has('public._daybook_lines(integer[],integer[],date,date)', 'daybook_align_mode') and t532.has('public._daybook_lines(integer[],integer[],date,date)', 'card_settlements85') and t532.has('public._daybook_lines(integer[],integer[],date,date)', 'drawer_short_post'));
select t532.chk('T1e _p27_pl: payroll accrual (bos85/86/93) and labour absorbed (bos117)', t532.has('public._p27_pl(date,date,integer[])', 'payroll_accrual_on') and t532.has('public._p27_pl(date,date,integer[])', 'factory_labour_absorbed117') and t532.has('public._p27_pl(date,date,integer[])', 'sa0'));
select t532.chk('T1f _r3q_l3_shop_pnl: bos440 blank profit inside the bos112 wrapper', t532.has('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'report_profit_blank_on') and t532.has('public._r3q_l3_shop_pnl(date,date,integer[],jsonb)', 'profit_truth_mode'));
\echo == T2 they run
select set_config('request.jwt.claim.sub', :'o', false);
select t532.chk('T2a customer_dues runs', (select count(*) >= 0 from customer_dues()));
select t532.chk('T2b the day book runs', (select count(*) >= 0 from _daybook_lines(array[1], array[1], current_date - 7, current_date)));
select t532.chk('T2c the profit and loss helper runs', (select count(*) >= 0 from _p27_pl(current_date - 30, current_date, array[1])));
select md5(t532.def('public._acct_docs(date)') || t532.def('public._cust_bal(uuid)') || t532.def('public.customer_dues()')) as hb, (select count(*) from public._union_fn_backup) as nb \gset
\i supabase/phase532.sql
select t532.chk('T3 a second paste changes nothing', md5(t532.def('public._acct_docs(date)') || t532.def('public._cust_bal(uuid)') || t532.def('public.customer_dues()')) = :'hb' and (select count(*) from public._union_fn_backup) = :nb);

\echo == RESULT
select 'phase532 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t532.res;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from t532.res;
select name from t532.res where not ok;
