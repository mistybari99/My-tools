-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase84_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase510_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 510 tests (step F: audit trail + no-delete on stock cache / batches / transfers / purchase lines / wastage, production void audit, reconcile audit rows).
--   Needs phase8..phase78 (without 72) + phase510.
--   ORDER="phase8 ... phase78 phase510" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 84db
--   psql -h /tmp -p 5544 -U postgres -d 84db -qAt -f supabase/phase510_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (ids and roles, no names).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set e '00000000-0000-0000-0000-000000000002'
\set a '00000000-0000-0000-0000-000000000003'
\set m '00000000-0000-0000-0000-000000000004'
\set x '00000000-0000-0000-0000-000000000005'
\set n '00000000-0000-0000-0000-000000000006'
\set r '00000000-0000-0000-0000-000000000007'
\set q '00000000-0000-0000-0000-000000000008'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'e','entry2@s.app','{"full_name":"Entry"}'), (:'x','view5@s.app','{"full_name":"Viewer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'e','storekeeper'),(:'x','storekeeper') on conflict do nothing;
insert into user_locations values (:'e',1),(:'e',2),(:'x',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select staff_id as ost from profiles where id = :'o' \gset

\echo == data (as postgres)
insert into items (code,name_bn,name_en,category,unit,tracked,is_active,sellable,sell_price) values
 ('P84-A','এ','Item A','Sweets','kg',true,true,true,100), ('P84-B','বি','Item B','Sweets','kg',true,true,true,50), ('P84-C','সি','Item C','Sweets','kg',true,true,true,20),
 ('P84-D','ডি','Item D','Sweets','kg',true,true,true,20);
select id as ia from items where code='P84-A' \gset
select id as ib from items where code='P84-B' \gset
select id as ic from items where code='P84-C' \gset
select id as id_ from items where code='P84-D' \gset
select stock_post(:'ia'::uuid,1,100,'purchase_in',null,null,10);
select stock_post(:'ic'::uuid,1,50,'purchase_in',null,null,4);
select stock_post(:'ic'::uuid,2,5,'purchase_in',null,null,4);
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, batch_no) values (:'ib'::uuid,1,now(),40,40,now()+interval '5 days','B84-1') returning id as bid \gset
select stock_post(:'ib'::uuid,1,40,'purchase_in',null,null,3,:'bid'::bigint);

\echo == T0 shape and privileges
select tt.chk('T0 new triggers exist', (select count(*) from pg_trigger where not tgisinternal and tgname in ('stock_balance_guard84','audit_stock_balance84','stock_batches_guard84','audit_stock_batches84','stock_transfers_no_delete84','purchase_lines_guard84','audit_production_runs_void84'))=7);
select tt.chk('T0 trigger functions are closed to anon / authenticated', not has_function_privilege('anon','_aud84()','execute') and not has_function_privilege('authenticated','_aud84()','execute')
  and not has_function_privilege('authenticated','_sb_guard84()','execute') and not has_function_privilege('authenticated','_batch_guard84()','execute') and not has_function_privilege('authenticated','_pl_guard84()','execute'));
select tt.chk('T0 stock_reconcile keeps its grants (authenticated yes, anon no)', has_function_privilege('authenticated','stock_reconcile(boolean)','execute') and not has_function_privilege('anon','stock_reconcile(boolean)','execute'));
select tt.chk('T0 RLS still on and the app roles still cannot write the tables', (select count(*) from pg_class where relname in ('stock_balance','stock_batches','stock_transfers','purchase_lines','stock_wastage','production_runs') and relrowsecurity)=6
  and not has_table_privilege('authenticated','stock_balance','update') and not has_table_privilege('authenticated','stock_batches','delete'));

\echo == T1 stock_balance
select count(*) as a0 from audit_log \gset
select tt.err('T1 delete of a balance with history refused', format($$delete from stock_balance where item_id=%L and location_id=1$$, :'ia'), 'nothing is deleted');
select tt.err('T1 delete of a zero balance that HAS ledger rows refused', format($$delete from stock_balance where item_id=%L and location_id=2$$, :'ic'), 'nothing is deleted');
select tt.err('T1 item / place cannot be changed', format($$update stock_balance set location_id=2 where item_id=%L and location_id=1$$, :'ia'), 'identity_immutable');
insert into stock_balance (item_id, location_id) values (:'id_'::uuid, 1);
with d as (delete from stock_balance where item_id=:'id_'::uuid and location_id=1 returning 1) select tt.chk('T1 an EMPTY phantom row (no qty, no cost, no ledger) may be deleted', (select count(*) from d)=1);
select count(*) as a1 from audit_log \gset
-- the sale path: ledger-driven balance updates are NOT written to audit_log (derivable from the immutable ledger)
select stock_post(:'ia'::uuid,1,-3,'sale_out');
select tt.chk('T1 stock_post (sale path) still works: qty 97, avg cost kept', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=97 and (select avg_cost from stock_balance where item_id=:'ia'::uuid and location_id=1)=10);
select tt.chk('T1 sale path wrote NO stock_balance audit row (by design)', (select count(*) from audit_log where table_name='stock_balance')=0);
-- anything else IS audited: a direct change (postgres / service_role / any definer function)
update stock_balance set qty = 90 where item_id=:'ia'::uuid and location_id=1;
select tt.chk('T1 a direct change writes one audit row with old and new qty', (select count(*) from audit_log where table_name='stock_balance')=1
  and (select (detail->'old'->>'qty')::numeric from audit_log where table_name='stock_balance')=97 and (select (detail->'new'->>'qty')::numeric from audit_log where table_name='stock_balance')=90
  and (select record_id from audit_log where table_name='stock_balance')=:'ia'||':1' and (select action from audit_log where table_name='stock_balance')='update');
select tt.chk('T1 the audit row says who wrote (db user) and which phase', (select detail->>'db_user' from audit_log where table_name='stock_balance')=session_user and (select detail->>'src' from audit_log where table_name='stock_balance')='phase84');
update stock_balance set updated_at = now() where item_id=:'ia'::uuid and location_id=1;
select tt.chk('T1 a change that touches neither qty nor cost is not logged', (select count(*) from audit_log where table_name='stock_balance')=1);
update stock_balance set avg_cost = 11 where item_id=:'ia'::uuid and location_id=1;
select tt.chk('T1 avg_cost change logged with old 10 / new 11', (select count(*) from audit_log where table_name='stock_balance' and (detail->'old'->>'avg_cost')::numeric=10 and (detail->'new'->>'avg_cost')::numeric=11)=1);
-- a definer function (the owner's authenticated session) : stock_reconcile is covered in T7. Here: the audit user comes from auth.uid()
select tt.as(:'o');
update stock_balance set qty = 91 where item_id=:'ia'::uuid and location_id=1;
select tt.chk('T1 audit row carries user id and staff id of the signed-in caller', (select user_id from audit_log where table_name='stock_balance' order by id desc limit 1)=:'o'::uuid
  and (select staff_id from audit_log where table_name='stock_balance' order by id desc limit 1) is not distinct from :'ost');

\echo == T2 stock_batches
select tt.err('T2 delete of a batch refused', format($$delete from stock_batches where id=%s$$, :'bid'), 'nothing is deleted');
select tt.err('T2 qty_made cannot be changed', format($$update stock_batches set qty_made=99 where id=%s$$, :'bid'), 'identity_immutable');
select tt.err('T2 item cannot be changed', format($$update stock_batches set item_id=%L where id=%s$$, :'ia', :'bid'), 'identity_immutable');
select tt.err('T2 made_at cannot be changed', format($$update stock_batches set made_at=now()-interval '9 days' where id=%s$$, :'bid'), 'identity_immutable');
select stock_post(:'ib'::uuid,1,-4,'sale_out',null,null,null,:'bid'::bigint);
select tt.chk('T2 batch sale works (36 left) and is audited old 40 / new 36', (select qty_remaining from stock_batches where id=:'bid')=36
  and (select count(*) from audit_log where table_name='stock_batches' and record_id=:'bid' and (detail->'old'->>'qty_remaining')::numeric=40 and (detail->'new'->>'qty_remaining')::numeric=36)=1);
update stock_batches set expires_at = expires_at + interval '1 day', note='moved' where id=:'bid';
select tt.chk('T2 an expiry / note change is audited (old and new)', (select count(*) from audit_log where table_name='stock_batches' and detail->'new' ? 'expires_at' and detail->'new'->>'note'='moved')=1);
select tt.chk('T2 batch audit row carries the caller', (select user_id from audit_log where table_name='stock_batches' order by id desc limit 1)=:'o'::uuid);

\echo == T3 stock_transfers
insert into stock_transfers (from_location_id, to_location_id, item_id, qty) values (1,2,:'ia'::uuid,2) returning id as tid \gset
update stock_transfers set status='cancelled', cancelled_at=now() where id=:'tid';
select tt.chk('T3 transfer status change is audited (existing trigger) with old sent / new cancelled', (select count(*) from audit_log where table_name='stock_transfers' and record_id=:'tid' and detail->'old'->>'status'='sent' and detail->'new'->>'status'='cancelled')=1);
select tt.err('T3 delete of a transfer refused', format($$delete from stock_transfers where id=%L$$, :'tid'), 'nothing is deleted');

\echo == T4 purchase_lines
reset role; select tt.as(:'o');
select save_supplier(null,'{"name":"Sup84","credit_days":7}') as sup \gset
select save_purchase(null,null,:'sup'::uuid,1,'P84-1','2026-10-01'::date,format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]',:'ia')::jsonb) ->> 'id' as b1 \gset
select tt.chk('T4 a DRAFT bill keeps one line', (select count(*) from purchase_lines where bill_id=:'b1'::uuid)=1);
select save_purchase(null,:'b1'::uuid,:'sup'::uuid,1,'P84-1','2026-10-01'::date,format('[{"item_id":"%s","qty":12,"unit":"kg","unit_cost":100},{"item_id":"%s","qty":2,"unit":"kg","unit_cost":50}]',:'ia',:'ib')::jsonb);
select tt.chk('T4 editing a draft still replaces its lines (delete allowed while draft)', (select count(*) from purchase_lines where bill_id=:'b1'::uuid)=2 and (select sum(qty) from purchase_lines where bill_id=:'b1'::uuid)=14);
select post_purchase(:'b1'::uuid);
select tt.chk('T4 the bill is posted', (select status from purchase_bills where id=:'b1'::uuid)='posted');
select tt.err('T4 delete of a line of a posted bill refused', format($$delete from purchase_lines where bill_id=%L$$, :'b1'::uuid), 'nothing is deleted');
select tt.err('T4 qty of a posted line cannot be changed', format($$update purchase_lines set qty=1 where bill_id=%L$$, :'b1'::uuid), 'identity_immutable');
select tt.err('T4 unit cost of a posted line cannot be changed', format($$update purchase_lines set unit_cost=1 where bill_id=%L$$, :'b1'::uuid), 'identity_immutable');
select tt.err('T4 the bill of a posted line cannot be moved', format($$update purchase_lines set bill_id=%L where bill_id=%L$$, gen_random_uuid(), :'b1'::uuid), 'identity_immutable');
select tt.chk('T4 base qty / base cost (written at posting) stay writable', (select count(*) from purchase_lines where bill_id=:'b1'::uuid and base_qty is not null)=2);
update purchase_lines set description='note' where bill_id=:'b1'::uuid and line_no=1;
select tt.chk('T4 a non-identity change of a posted line is audited (existing trigger)', (select count(*) from audit_log where table_name='purchase_lines' and detail->'new'->>'description'='note')=1);
select tt.chk('T4 purchase line inserts are audited (existing)', (select count(*) from audit_log where table_name='purchase_lines' and action='insert')>=2);

\echo == T5 stock_wastage (already immutable since phase10)
insert into stock_wastage (item_id, location_id, qty, reason_code) values (:'ia'::uuid,1,1,'spoilt') returning id as wid \gset
select tt.err('T5 delete of a wastage row refused', format($$delete from stock_wastage where id=%L$$, :'wid'), 'ledger_immutable');
select tt.err('T5 update of a wastage row refused', format($$update stock_wastage set qty=5 where id=%L$$, :'wid'), 'ledger_immutable');

\echo == T6 production_runs void audit
insert into recipes (item_id, version, yield_qty) values (:'ib'::uuid, 1, 1) returning id as rid \gset
insert into production_runs (location_id, recipe_id, item_id, batches, made_at, yield_base) values (1,:'rid'::uuid,:'ib'::uuid,1,now(),1) returning id as prid \gset
select count(*) as pa0 from audit_log where table_name='production_runs' \gset
update production_runs set note = 'x', cost_complete = true, ledger_in_id = null where id=:'prid'::uuid;
select tt.chk('T6 a normal post-time update is NOT logged', (select count(*) from audit_log where table_name='production_runs')=:pa0);
select production_void(:'prid'::uuid, 'test void') ->> 'status' as vs \gset
select tt.chk('T6 production_void works', :'vs'='void' and (select status from production_runs where id=:'prid'::uuid)='void');
select tt.chk('T6 the void writes ONE audit row with status old done / new void and the void fields', (select count(*) from audit_log where table_name='production_runs' and record_id=:'prid' and action='update')=1
  and (select detail->'old'->>'status' from audit_log where table_name='production_runs' and record_id=:'prid' and action='update')='done'
  and (select detail->'new'->>'status' from audit_log where table_name='production_runs' and record_id=:'prid' and action='update')='void'
  and (select detail->'new'->>'void_note' from audit_log where table_name='production_runs' and record_id=:'prid' and action='update')='test void'
  and (select detail->'new'->>'void_by' from audit_log where table_name='production_runs' and record_id=:'prid' and action='update')=:'o'
  and (select detail->'new' ? 'void_at' from audit_log where table_name='production_runs' and record_id=:'prid' and action='update'));
select tt.chk('T6 the audit row names the caller', (select user_id from audit_log where table_name='production_runs' and record_id=:'prid' and action='update')=:'o'::uuid);
select count(*) as pa1 from audit_log where table_name='production_runs' \gset
select production_void(:'prid'::uuid, 'again');
select tt.chk('T6 a repeated void (no change) adds no row', (select count(*) from audit_log where table_name='production_runs')=:pa1);

\echo == T7 stock_reconcile(true) writes audit rows
-- clean-up first: earlier tests changed ia directly (T1), reconcile repairs it; this also proves it logs that repair
select count(*) as cleanup from stock_reconcile(true) \gset
select tt.chk('T7 clean-up reconcile found the T1-tampered ia only and logged it (1 row)', :cleanup=1 and (select count(*) from audit_log where action='reconcile_fix')=1);
select sum(qty_delta) as iaq from stock_ledger where item_id=:'ia'::uuid and location_id=1 \gset
select avg_cost as iaavg from stock_balance where item_id=:'ia'::uuid and location_id=1 \gset
select tt.chk('T7 balance equals the ledger after the clean-up', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=:iaq and (select count(*) from stock_reconcile(false))=0);
-- tamper two balances directly (the tamper itself is logged as an ordinary update)
update stock_balance set qty = qty + 7 where item_id=:'ia'::uuid and location_id=1;
update stock_balance set qty = qty - 2, avg_cost = 9 where item_id=:'ic'::uuid and location_id=1;
select count(*) as rcnt from stock_reconcile(false) \gset
select tt.chk('T7 a dry run lists the 2 tampered balances', :rcnt=2);
select tt.chk('T7 a dry run changes nothing and writes no new reconcile_fix row', (select count(*) from audit_log where action='reconcile_fix')=1 and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=:iaq+7);
select count(*) as pre_upd from audit_log where table_name='stock_balance' and action='update' \gset
select count(*) as fixed from stock_reconcile(true) \gset
select tt.chk('T7 reconcile(true) reports 2 fixes', :fixed=2);
select tt.chk('T7 balances are back to the ledger and a second run finds nothing', (select count(*) from stock_reconcile(false))=0
  and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=:iaq and (select qty from stock_balance where item_id=:'ic'::uuid and location_id=1)=50 and (select avg_cost from stock_balance where item_id=:'ic'::uuid and location_id=1)=4);
select tt.chk('T7 exactly ONE new reconcile_fix audit row per corrected balance (2)', (select count(*) from audit_log where action='reconcile_fix' and table_name='stock_balance')=3);
select tt.chk('T7 row for ia: old = tampered qty, new = ledger qty, record id item:place', (select count(*) from audit_log where action='reconcile_fix' and record_id=:'ia'||':1' and (detail->'old'->>'qty')::numeric=:iaq+7 and (detail->'new'->>'qty')::numeric=:iaq)=1);
select tt.chk('T7 row for ic: old qty 48 / avg 9 -> new qty 50 / avg 4', (select count(*) from audit_log where action='reconcile_fix' and record_id=:'ic'||':1' and (detail->'old'->>'qty')::numeric=48 and (detail->'old'->>'avg_cost')::numeric=9 and (detail->'new'->>'qty')::numeric=50 and (detail->'new'->>'avg_cost')::numeric=4)=1);
select tt.chk('T7 the rows carry who (user id + staff id) and source', (select count(*) from audit_log where action='reconcile_fix' and user_id=:'o'::uuid and staff_id is not distinct from :'ost' and detail->>'source'='stock_reconcile')=3);
select tt.chk('T7 reconcile did not ALSO write the generic update rows (no double count)', (select count(*) from audit_log where table_name='stock_balance' and action='update')=:pre_upd);
update stock_balance set qty = qty + 1 where item_id=:'ia'::uuid and location_id=1;
select tt.chk('T7 afterwards the audit is switched back on: the next direct change IS logged', (select count(*) from audit_log where table_name='stock_balance' and action='update')=:pre_upd+1);
select count(*) as c2 from stock_reconcile(true) \gset
select tt.chk('T7 and that tamper is repaired + logged again', :c2=1 and (select count(*) from audit_log where action='reconcile_fix')=4);
select tt.as(:'e');
select tt.err('T7 a non-owner cannot run reconcile', $$select * from stock_reconcile(true)$$, 'not allowed');
select tt.as(:'o');

\echo == T8 as the signed-in app role: sale path and refusals
set role authenticated; select tt.as(:'o');
select tt.err('T8 app role cannot delete stock_balance', $$delete from stock_balance$$, 'permission denied');
select tt.err('T8 app role cannot update stock_batches', $$update stock_batches set qty_remaining=0$$, 'permission denied');
select tt.err('T8 app role cannot delete purchase_lines', $$delete from purchase_lines$$, 'permission denied');
select tt.err('T8 app role cannot delete stock_transfers', $$delete from stock_transfers$$, 'permission denied');
select tt.err('T8 app role cannot call the audit function', $$select public._aud84()$$, 'permission denied');
select tt.chk('T8 the owner still reads the audit rows (RLS) and the balances', (select count(*) from audit_log where table_name='stock_balance')>=1 and (select count(*) from stock_balance)>=3);
select tt.err('T8 app role cannot call stock_post directly (unchanged)', format($$select stock_post(%L,1,-1,'sale_out')$$, :'ia'), 'permission denied');
reset role;
select stock_post(:'ia'::uuid,1,-1,'sale_out');
select tt.chk('T8 sale path after all the triggers: qty down by 1, no stock_balance audit row for it', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=:iaq-1 and (select count(*) from audit_log where action='update' and table_name='stock_balance')=:pre_upd+1);

\echo == T9 idempotent: audit trigger count unchanged by a second apply is checked outside (paste twice)
select tt.chk('T9 exactly one of each new trigger', (select count(*) from pg_trigger where not tgisinternal and tgname like '%84') = 7);

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
select 'FAIL ' || name from tt.res where not ok;
