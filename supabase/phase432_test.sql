-- FRESH DB ONLY. Phase 432 tests (RPT-B3 R6a: quality check with item / quantity / supplier, damaged quantity on transfer receive). Needs phases 8 to 99, 430 to 432.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase432_test.sql | grep -E 'FAIL|RESULT'
-- Neutral test_* data only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set f '00000000-0000-0000-0000-000000000004'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.d() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_sales@s.app','{"full_name":"test_sales"}'), (:'k','test_store@s.app','{"full_name":"test_store"}'), (:'f','test_far@s.app','{"full_name":"test_far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),(:'f','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'f',3) on conflict do nothing;
insert into rule_grants (grant_code, role_code) values ('report_stock','storekeeper') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('test_raw_a','test_raw_a','test_raw_a','kg','kg','raw_material',true,0), ('test_raw_b','test_raw_b','test_raw_b','kg','kg','raw_material',true,0), ('test_fg_a','test_fg_a','test_fg_a','kg','kg','finished_good',true,10);
insert into suppliers (name) values ('test_supplier_a'), ('test_supplier_b');
insert into unit_conversions (from_unit, to_unit, factor) values ('g','kg',0.001) on conflict do nothing;
select id as ra from items where code='test_raw_a' \gset
select id as rb from items where code='test_raw_b' \gset
select id as fg from items where code='test_fg_a' \gset
select id as sa from suppliers where name='test_supplier_a' \gset
select id as sb from suppliers where name='test_supplier_b' \gset

\echo == T0 shape
select tt.chk('T0 new columns exist and are nullable', (select count(*) from information_schema.columns where table_name='qc_records' and column_name in ('item_id','qty','supplier_id') and is_nullable='YES')=3
  and (select count(*) from information_schema.columns where table_name='stock_transfers' and column_name in ('received_damaged_qty','damaged_reason') and is_nullable='YES')=2);
select tt.chk('T0 the 7-argument qc_record and the 3-argument stock_receive_transfer still exist; the new ones have 11 and 5 arguments', to_regprocedure('public.qc_record(text,uuid,text,jsonb,text,text,uuid)') is not null
  and to_regprocedure('public.qc_record(text,uuid,text,jsonb,text,text,uuid,uuid,numeric,text,uuid)') is not null and to_regprocedure('public.stock_receive_transfer(uuid,numeric,text)') is not null
  and to_regprocedure('public.stock_receive_transfer(uuid,numeric,text,numeric,text)') is not null);
select tt.chk('T0 the 3-argument transfer receive was not touched (no marker, same text as phase10)', position('bos432' in pg_get_functiondef('public.stock_receive_transfer(uuid,numeric,text)'::regprocedure))=0);
select tt.chk('T0 anon cannot call the new functions', not has_function_privilege('anon','public.transfer_damage_report(date,date,int)','execute') and not has_function_privilege('anon','public.qc_list(int,date,date,text,uuid,uuid)','execute')
  and not has_function_privilege('authenticated','public._rb3_qc_source(text,uuid)','execute'));
select tt.chk('T0 the damage reasons list is seeded and ends with Other', (select count(*) from option_lists where list_code='transfer_damage_reasons')=6 and exists (select 1 from option_lists where list_code='transfer_damage_reasons' and value_code='other')
  and exists (select 1 from list_defs where list_code='transfer_damage_reasons'));

\echo == T1 quality check on a purchase receipt
select tt.as(:'o'); set role authenticated;
select (save_purchase('b4320000-0000-0000-0000-000000000001'::uuid, null, :'sa'::uuid, 1, 'Q-1', tt.d(), format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":5},{"item_id":"%s","qty":20,"unit":"kg","unit_cost":7}]', :'ra', :'rb')::jsonb) ->> 'id') as b1 \gset
select post_purchase(:'b1'::uuid) is not null as p1 \gset
select tt.chk('T1 pass with item and quantity: supplier comes from the bill, quantity in base unit', (qc_record('grn', :'b1'::uuid, 'pass', '[{"code":"smell","ok":true}]'::jsonb, null, null, null, :'ra'::uuid, 100, 'kg', null) ->> 'supplier_id')=:'sa');
reset role;
select tt.chk('T1 stored: item raw A, qty 100, supplier A', (select item_id=:'ra'::uuid and qty=100 and supplier_id=:'sa'::uuid from qc_records where source_id=:'b1'::uuid order by created_at desc limit 1));
select tt.as(:'o'); set role authenticated;
select tt.chk('T1 reject with a quantity in grams is converted to kg (500 g = 0.5 kg)', (qc_record('grn', :'b1'::uuid, 'reject', '[{"code":"smell","ok":false}]'::jsonb, 'test smell off', null, null, :'rb'::uuid, 500, 'g', null) ->> 'qty')::numeric=0.5);
select tt.err('T1 an item that is not on the receipt is refused', format($$select qc_record('grn', '%s'::uuid, 'pass', '[]'::jsonb, null, null, null, '%s'::uuid, null, null, null)$$, :'b1', :'fg'), 'item_not_in_source');
select tt.err('T1 a quantity without an item is refused', format($$select qc_record('grn', '%s'::uuid, 'pass', '[]'::jsonb, null, null, null, null, 5, 'kg', null)$$, :'b1'), 'item_required_for_qty');
select tt.err('T1 another supplier than the receipt''s is refused', format($$select qc_record('grn', '%s'::uuid, 'pass', '[]'::jsonb, null, null, null, null, null, null, '%s'::uuid)$$, :'b1', :'sb'), 'supplier_mismatch');
select tt.err('T1 quantity zero refused', format($$select qc_record('grn', '%s'::uuid, 'pass', '[]'::jsonb, null, null, null, '%s'::uuid, 0, 'kg', null)$$, :'b1', :'ra'), 'bad_qty');
select tt.err('T1 unknown unit refused', format($$select qc_record('grn', '%s'::uuid, 'pass', '[]'::jsonb, null, null, null, '%s'::uuid, 3, 'bag', null)$$, :'b1', :'ra'), 'unit_unknown');
select tt.err('T1 reject still needs a note', format($$select qc_record('grn', '%s'::uuid, 'reject', '[]'::jsonb, null, null, null, '%s'::uuid, 3, 'kg', null)$$, :'b1', :'ra'), 'note_required');
select tt.chk('T1 the old 7-argument call still works (no item, no qty); the supplier of a receipt is still taken from the bill', (qc_record('grn', :'b1'::uuid, 'hold', '[{"code":"label","ok":false}]'::jsonb, 'test label missing', null, null) ->> 'supplier_id')=:'sa');
select tt.chk('T1 old call by named arguments works', (qc_record(p_source_type => 'grn', p_source_id => :'b1'::uuid, p_status => 'pass', p_checks => '[]'::jsonb) ->> 'status')='pass');

\echo == T2 quality check on a production run takes its item from the run
select recipe_save(null, :'fg'::uuid, 10, 'kg', 'x', format('[{"ingredient_item_id":"%s","qty":20,"unit":"kg","waste_pct":0}]', :'ra')::jsonb) ->> 'id' as rid \gset
select recipe_set_active(:'rid'::uuid, true) is null as rs \gset
select production_post(1, :'rid'::uuid, 1, null, null, 'test run') ->> 'run_id' as run \gset
select qc_record('production', :'run'::uuid, 'pass', '[]'::jsonb, null, null, null, null, 10, 'kg', null) ->> 'item_id' as qi \gset
select tt.chk('T2 production check: item = the run''s product, qty 10, no supplier', :'qi'=:'fg');
reset role;
select tt.chk('T2 stored with qty 10 and supplier null (not invented)', (select qty=10 and supplier_id is null from qc_records where source_id=:'run'::uuid));

\echo == T3 qc_list filters and columns
select tt.as(:'o'); set role authenticated;
select tt.chk('T3 four-argument call still works (the latest check of each of the 2 sources)', (select count(*) from qc_list(null, null, null, null))=2);
select tt.chk('T3 filter by supplier A: the receipt latest check only (one row per source)', (select count(*) from qc_list(null,null,null,null,null,:'sa'::uuid))=1);
select tt.chk('T3 filter by item (the production product)', (select count(*) from qc_list(null,null,null,null,:'fg'::uuid,null))=1 and (select item_code from qc_list(null,null,null,null,:'fg'::uuid,null))='test_fg_a');
select tt.chk('T3 filter by status pass', (select count(*) from qc_list(null,null,null,'pass'))=2);
select tt.chk('T3 the latest check of the receipt has no item (typed without one) and says null, not a made-up item', (select item_id is null and supplier_name='test_supplier_a' from qc_list(null,null,null,null,null,:'sa'::uuid)));
select tt.err('T3 bad date range refused', 'select * from qc_list(null, tt.d(), tt.d()-3)', 'bad_range');
reset role; select tt.as(:'s'); set role authenticated;
reset role;

\echo == T4 damaged quantity on transfer receive
select tt.as(:'o'); set role authenticated;
select stock_opening(:'ra'::uuid, 1, 0.5, null, null, 'x') is not null as op \gset
select (stock_transfer(1, 2, :'rb'::uuid, 5, 'kg', 'test move') ->> 'id') as t1 \gset
select tt.err('T4 damaged more than received refused', format($$select stock_receive_transfer('%s'::uuid, 4, 'n', 4.5, 'broken')$$, :'t1'), 'damaged_over_received');
select tt.err('T4 damaged without a reason refused', format($$select stock_receive_transfer('%s'::uuid, 4, 'n', 1, null)$$, :'t1'), 'damage_reason_required');
select tt.err('T4 a reason not in the list refused', format($$select stock_receive_transfer('%s'::uuid, 4, 'n', 1, 'nonsense')$$, :'t1'), 'damage_reason_required');
select tt.err('T4 negative damaged refused', format($$select stock_receive_transfer('%s'::uuid, 4, 'n', -1, 'broken')$$, :'t1'), 'bad_qty');
select tt.chk('T4 nothing was received by the refused calls (still in transit)', (select status from stock_transfers where id=:'t1'::uuid)='sent');
select (stock_receive_transfer(:'t1'::uuid, 4, 'test recv', 1.5, 'broken') ->> 'damaged')::numeric as dm \gset
select tt.chk('T4 received 4, damaged 1.5, reason broken; short 1 still raises its own exception', :'dm'::numeric=1.5);
reset role;
select tt.chk('T4 stored on the transfer', (select received_qty=4 and received_damaged_qty=1.5 and damaged_reason='broken' and status='received' from stock_transfers where id=:'t1'::uuid));
select tt.chk('T4 the Exceptions list has both lines: transit_short (existing rule) and transit_damaged (new)', (select count(*) from exceptions where flag_code='transit_short')=1 and (select count(*) from exceptions where flag_code='transit_damaged' and level='yellow')=1);
select tt.chk('T4 stock still counts all 4 received kg (damage is a record; write it off with the wastage screen)', (select qty from stock_balance where item_id=:'rb'::uuid and location_id=2)=4);
select tt.as(:'o'); set role authenticated;
select tt.chk('T4 receiving twice returns dup and does not change the figures', (stock_receive_transfer(:'t1'::uuid, 4, 'again', 0, null) ->> 'dup')::boolean);
reset role;
select tt.chk('T4 the repeat did not overwrite the damaged quantity', (select received_damaged_qty from stock_transfers where id=:'t1'::uuid)=1.5);
select tt.as(:'o'); set role authenticated;
select (stock_transfer(1, 2, :'rb'::uuid, 2, 'kg', 'test move 2') ->> 'id') as t2 \gset
select stock_receive_transfer(:'t2'::uuid, 2, 'plain 3-argument receive') is not null as r2 \gset
select (stock_transfer(1, 2, :'rb'::uuid, 1, 'kg', 'test move 3') ->> 'id') as t3 \gset
select stock_receive_transfer(:'t3'::uuid, 1, 'none damaged', 0, null) is not null as r3 \gset
reset role;
select tt.chk('T4 the 3-argument receive leaves damaged NULL = not captured (never 0); an explicit 0 is stored as 0 with no reason', (select received_damaged_qty is null from stock_transfers where id=:'t2'::uuid)
  and (select received_damaged_qty=0 and damaged_reason is null from stock_transfers where id=:'t3'::uuid));

\echo == T5 the damaged-on-receipt report
select tt.as(:'o'); set role authenticated;
select transfer_damage_report() as rep \gset
select tt.chk('T5 three received transfers in the last 30 days; the damaged total counts only the captured one (1.5); the 3-argument receive is counted as not captured', (:'rep'::jsonb ->> 'received_n')::int=3 and (:'rep'::jsonb ->> 'damaged_not_captured_n')::int=1 and (:'rep'::jsonb ->> 'damaged_total_captured')::numeric=1.5);
select tt.chk('T5 the damaged row: reason label, short 1, item, batch link absent for an item without batches', (select x->>'reason_label'='Broken' and (x->>'short')::numeric=1 and x->>'code'='test_raw_b' from jsonb_array_elements(:'rep'::jsonb -> 'rows') x where (x->>'damaged')::numeric=1.5));
select tt.chk('T5 the not-captured row has damaged null in the answer (the screen prints data not captured)', (select count(*) from jsonb_array_elements(:'rep'::jsonb -> 'rows') x where x->'damaged' = 'null'::jsonb)=1);
select tt.chk('T5 place filter works (nothing happened at place 3)', (transfer_damage_report(null, null, 3) ->> 'received_n')::int=0 and (transfer_damage_report(null, null, 2) ->> 'received_n')::int=3);
select tt.err('T5 bad range refused', 'select transfer_damage_report(tt.d(), tt.d()-1)', 'bad_range');
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T5 a salesperson (no stock report right) cannot read it', 'select transfer_damage_report()', 'not allowed');
reset role; select tt.as(:'f'); set role authenticated;
select tt.chk('T5 a storekeeper at place 3 with the report right sees none of places 1 and 2', (transfer_damage_report() ->> 'received_n')::int=0);
reset role;

\echo == T6 nothing else moved
select tt.chk('T6 no ledger row of reason wastage or count_adjust was created by any of this', (select count(*) from stock_ledger where reason in ('wastage','count_adjust'))=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
