-- Phase 533 tests (UNION-5: stock functions). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain, tests/sql/run_all_union.sh). Prints PASS / FAIL per check.
-- Test users and items are neutral test_* ids. Run on the final database.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f533'
create schema if not exists t533;
create table if not exists t533.res (name text, ok boolean);
truncate t533.res;
create or replace function t533.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t533.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t533.def(p_sig text) returns text language sql as $$ select pg_get_functiondef(p_sig::regprocedure) $$;
create or replace function t533.has(p_sig text, p_text text) returns boolean language sql as $$ select position(p_text in pg_get_functiondef(p_sig::regprocedure)) > 0 $$;

\echo == T1 tags
select t533.chk('T1a _sale_stock_out: phase 501 switch, bos82 unit_conv_required, bos83 offline soft stock, bos94, bos114', t533.has('public._sale_stock_out()', 'stock_unit_unknown_block') and t533.has('public._sale_stock_out()', 'unit_conv_required') and t533.has('public._sale_stock_out()', 'offline_soft_stock') and t533.has('public._sale_stock_out()', 'bos94') and t533.has('public._sale_stock_out()', 'late_sale_follows_block'));
select t533.chk('T1b sale_return: return_sale_factor_on (phase 501) and return_uses_sale_rows (bos114)', t533.has('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'return_sale_factor_on') and t533.has('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)', 'return_uses_sale_rows'));
select t533.chk('T1c stock_receive_transfer: partial receipt (phase 499) and transit_short_mode (bos83)', t533.has('public.stock_receive_transfer(uuid,numeric,text)', 'transfer_partial_on') and t533.has('public.stock_receive_transfer(uuid,numeric,text)', 'transit_short_mode') and t533.has('public.stock_receive_transfer(uuid,numeric,text)', '_transit_loss83'));
select t533.chk('T1d stock_reconcile: change log (bos420) and audit line (bos84)', t533.has('public.stock_reconcile(boolean)', 'bos420') and t533.has('public.stock_reconcile(boolean)', 'reconcile_fix'));
select t533.chk('T1e _recipe_lines_ok: both intermediate-ingredient switches and both loop checks', t533.has('public._recipe_lines_ok(uuid,jsonb)', 'recipe_intermediate_on') and t533.has('public._recipe_lines_ok(uuid,jsonb)', 'semi_finished_ingredient116') and t533.has('public._recipe_lines_ok(uuid,jsonb)', '_recipe_reaches116') and t533.has('public._recipe_lines_ok(uuid,jsonb)', '_recipe_reaches('));
select t533.chk('T1f stock_transfer exists with both lines tags', t533.has('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)', 'transfer_overdraw_block') );
\echo == T2 every switch of these functions defaults to off
select t533.chk('T2 the switches are off by default', (select bool_and(coalesce(default_value::text, 'false') in ('false', '"off"', 'null')) from rules where key in ('stock_unit_unknown_block', 'return_sale_factor_on', 'transfer_partial_on', 'recipe_intermediate_on', 'transfer_overdraw_block')));
select md5(t533.def('public._sale_stock_out()') || t533.def('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)') || t533.def('public.stock_receive_transfer(uuid,numeric,text)')) as hb, (select count(*) from public._union_fn_backup) as nb \gset
\i supabase/phase533.sql
select t533.chk('T3 a second paste changes nothing', md5(t533.def('public._sale_stock_out()') || t533.def('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)') || t533.def('public.stock_receive_transfer(uuid,numeric,text)')) = :'hb' and (select count(*) from public._union_fn_backup) = :nb);

\echo == RESULT
select 'phase533 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t533.res;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from t533.res;
select name from t533.res where not ok;
