-- Phase 546 tests (stock_transfer carries both lines again). TEST DATABASE ONLY (a local throwaway Postgres built from the paste chain through phase 546).
-- Checks the function text; the behaviour is covered by phase114_test (T2), phase115_test (T3) and phase544_test, which must pass on the same build.
\set ON_ERROR_STOP off
create schema if not exists t546;
create table if not exists t546.res (name text, ok boolean);
truncate t546.res;
create or replace function t546.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t546.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;

select pg_get_functiondef('public.stock_transfer(integer,integer,uuid,numeric,text,text,uuid)'::regprocedure) as def \gset
select t546.chk('T1 bos114 transfer_needs_stock is in stock_transfer', position('transfer_needs_stock' in :'def') > 0);
select t546.chk('T2 bos115 transfer_notify_receiver is in stock_transfer', position('transfer_notify_receiver' in :'def') > 0);
select t546.chk('T3 phase 544 client_id_reused is in both duplicate places', (length(:'def') - length(replace(:'def', 'client_id_reused', ''))) / length('client_id_reused') = 2);
select t546.chk('T4 phase 499 checks kept (overdraw, paused place)', position('transfer_overdraw_block' in :'def') > 0 and position('transfer_paused_block' in :'def') > 0);
select t546.chk('T5 switches stay at their defaults (OFF)', not rule_on('transfer_needs_stock') and not rule_on('transfer_notify_receiver') and not rule_on('transfer_client_reuse_block'));
select count(*) filter (where not ok) as failing, count(*) as checks from t546.res;
