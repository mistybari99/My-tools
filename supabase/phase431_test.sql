-- FRESH DB ONLY. Phase 431 tests (RPT-B3 R5b: trace_batch, recall cases, affected-stock report). Needs phases 8 to 99, 430 and 431.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase431_test.sql | grep -E 'FAIL|RESULT'
-- Neutral test_* data only. Chain under test: raw lot (supplier receipt) -> production run -> finished batch -> transfer to another place -> sales (one with a named customer).
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
 ('test_raw_a','test_raw_a','test_raw_a','kg','kg','raw_material',true,0), ('test_fg_a','test_fg_a','test_fg_a','kg','kg','finished_good',true,10);
insert into suppliers (name) values ('test_supplier_a'), ('test_supplier_b');
select id as ra from items where code='test_raw_a' \gset
select id as fg from items where code='test_fg_a' \gset
select id as sa from suppliers where name='test_supplier_a' \gset

\echo == T0 shape
select tt.chk('T0 tables have RLS, browsers cannot write', (select bool_and(relrowsecurity) from pg_class where oid in ('public.recall_cases'::regclass,'public.recall_batches'::regclass)) and not has_table_privilege('authenticated','public.recall_cases','insert') and not has_table_privilege('authenticated','public.recall_batches','update'));
select tt.chk('T0 callable by authenticated, not by anon; internals by nobody', has_function_privilege('authenticated','public.trace_batch(bigint,text)','execute') and not has_function_privilege('anon','public.trace_batch(bigint,text)','execute')
  and not has_function_privilege('authenticated','public._rb3_forward(bigint[])','execute') and not has_function_privilege('anon','public.recall_open(text,text,text,bigint[],uuid)','execute'));
select tt.chk('T0 grant recall_manage seeded to management, factory_incharge, storekeeper only', (select string_agg(role_code, ',' order by role_code) from rule_grants where grant_code='recall_manage')='factory_incharge,management,storekeeper');

\echo == T1 build the chain
select tt.as(:'o'); set role authenticated;
select (save_purchase('b4310000-0000-0000-0000-000000000001'::uuid, null, :'sa'::uuid, 1, 'R-1', tt.d(), format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":5}]', :'ra')::jsonb) ->> 'id') as b1 \gset
select receipt_lots_stage(:'b1'::uuid, format('[{"line_no":1,"lot_no":"TLOT-R1","expiry":"%s"}]', tt.d()+40)::jsonb) is not null as st \gset
select post_purchase(:'b1'::uuid) is not null as p1 \gset
select receipt_lots_apply(:'b1'::uuid) is not null as ap \gset
select (save_purchase('b4310000-0000-0000-0000-000000000002'::uuid, null, :'sa'::uuid, 1, 'R-2', tt.d(), format('[{"item_id":"%s","qty":50,"unit":"kg","unit_cost":5}]', :'ra')::jsonb) ->> 'id') as b2 \gset
select post_purchase(:'b2'::uuid) is not null as p2 \gset
select id as rawb from stock_batches where item_id=:'ra' and batch_no='TLOT-R1' \gset
select recipe_save(null, :'fg'::uuid, 10, 'kg', 'x', format('[{"ingredient_item_id":"%s","qty":20,"unit":"kg","waste_pct":0}]', :'ra')::jsonb) ->> 'id' as rid \gset
select recipe_set_active(:'rid'::uuid, true) is null as ra_ \gset
select production_post(1, :'rid'::uuid, 1, null, null, 'test run') ->> 'batch_id' as fgb \gset
select (stock_transfer(1, 2, :'fg'::uuid, 4, 'kg', 'test move') ->> 'id') as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 3.5, 'test recv') is not null as rc1 \gset
select (stock_transfer(1, 2, :'fg'::uuid, 1, 'kg', 'test move 2') ->> 'id') as t2 \gset
reset role;
insert into sales (client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, created_by, customer)
  values (gen_random_uuid(), 2, 1, tt.d(), now(), format('[{"item_id":"%s","qty":2}]', :'fg')::jsonb, 20, 0, 20, 'cash', :'o', 'test_customer_a');
insert into sales (client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, created_by)
  values (gen_random_uuid(), 1, 1, tt.d(), now(), format('[{"item_id":"%s","qty":1.5}]', :'fg')::jsonb, 15, 0, 15, 'cash', :'o');
insert into sales (client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, created_by, customer)
  values (gen_random_uuid(), 1, 2, tt.d(), now(), format('[{"item_id":"%s","qty":1}]', :'fg')::jsonb, 10, 0, 10, 'cash', :'o', 'test_customer_void');
update sales set status='void', void_by=:'o', void_at=now(), void_note='test_void' where location_id=1 and receipt=2;
select id as fgb2 from stock_batches where item_id=:'fg' and location_id=2 \gset
select tt.chk('T1 chain exists: raw lot batch, FG batch, FG batch at the other place', :'rawb' is not null and :'fgb' is not null and :'fgb2' is not null);

\echo == T2 trace forward from the raw lot
select tt.as(:'o'); set role authenticated;
select trace_batch(:'rawb'::bigint, 'fwd') as tr \gset
select tt.chk('T2 three batches reached: the lot, the finished batch, the batch at the other place', (select count(*) from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'batches'))=3);
select tt.chk('T2 relations: start, made_from, transferred', (select string_agg(x->>'relation', ',' order by x->>'relation') from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'batches') x)='made_from,start,transferred');
select tt.chk('T2 two sales listed (the voided one nets to zero and is left out)', (:'tr'::jsonb -> 'forward' ->> 'sales_total')::int=2 and (select sum((x->>'qty')::numeric) from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'sales') x)=3.5);
select tt.chk('T2 the sale at the other place names the customer; the walk-in has none', (select count(*) from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'sales') x where x->>'customer'='test_customer_a' and (x->>'location_id')::int=2)=1
  and (:'tr'::jsonb -> 'forward' -> 'summary' ->> 'named_customers')::int=1 and (:'tr'::jsonb -> 'forward' -> 'summary' ->> 'sales_without_customer')::int=1);
select tt.chk('T2 the production run uses 20 kg of the lot', (:'tr'::jsonb -> 'forward' -> 'made_into' -> 0 ->> 'qty')::numeric=20 and (:'tr'::jsonb -> 'forward' -> 'made_into' -> 0 ->> 'to_batch_id')::bigint=:'fgb'::bigint);
select tt.chk('T2 two transfers: one received (3.5 of 4 sent), one still in transit', (select count(*) from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'transfers') x where x->>'status'='received' and (x->>'received_qty')::numeric=3.5)=1
  and (select count(*) from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'transfers') x where x->>'status'='sent')=1);
select tt.chk('T2 by place: the other place has 1.5 kg on hand of the transferred batch, 2 sold, 1 in transit', (select (x->>'on_hand')::numeric=1.5 and (x->>'sold')::numeric=2 and (x->>'in_transit')::numeric=1 from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'summary' -> 'by_place') x where (x->>'location_id')::int=2));
select tt.chk('T2 unbatched quantity is printed: 50 kg of raw A (the receipt without a lot)', (select (x->>'unbatched')::numeric from jsonb_array_elements(:'tr'::jsonb -> 'forward' -> 'summary' -> 'unbatched') x where x->>'code'='test_raw_a')=50);
select tt.chk('T2 no mobile number or cost anywhere in the answer', position('mobile' in :'tr')=0 and position('unit_cost' in :'tr')=0 and position('avg_cost' in :'tr')=0);

\echo == T3 trace back from the finished batch and from the batch at the other place
select trace_batch(:'fgb'::bigint, 'back') as tb \gset
select tt.chk('T3 the run''s input is the lot, with supplier and lot number from the receipt', (:'tb'::jsonb -> 'back' -> 'inputs' -> 0 -> 'root_origin' ->> 'supplier')='test_supplier_a' and (:'tb'::jsonb -> 'back' -> 'inputs' -> 0 -> 'root_origin' ->> 'lot_no')='TLOT-R1'
  and (:'tb'::jsonb -> 'back' -> 'inputs' -> 0 ->> 'qty_used')::numeric=20 and (:'tb'::jsonb -> 'back' -> 'inputs' -> 0 ->> 'batch_id')::bigint=:'rawb'::bigint);
select trace_batch(:'fgb2'::bigint, 'back') as tb2 \gset
select tt.chk('T3 from the batch at the other place the root is the finished batch and the same lot is found', (:'tb2'::jsonb -> 'back' ->> 'root_batch_id')::bigint=:'fgb'::bigint and (:'tb2'::jsonb -> 'back' -> 'inputs' -> 0 -> 'root_origin' ->> 'lot_no')='TLOT-R1'
  and (:'tb2'::jsonb -> 'batch' -> 'origin' ->> 'type')='transfer');
select tt.chk('T3 the raw lot has origin type receipt with the bill number', (:'tr'::jsonb -> 'batch' -> 'origin' ->> 'type')='receipt' and (:'tr'::jsonb -> 'batch' -> 'origin' ->> 'bill_no')='R-1');
reset role;
-- an old batch with no origin says so instead of inventing one
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining) values (:'ra', 1, now(), 5, 5);
select id as oldb from stock_batches where batch_no is null and item_id=:'ra' \gset
select tt.as(:'o'); set role authenticated;
select tt.chk('T3 a batch with no recorded origin: warning origin_not_captured, never a made-up supplier', (trace_batch(:'oldb'::bigint) -> 'warnings') ? 'origin_not_captured' and (trace_batch(:'oldb'::bigint) -> 'batch' -> 'origin' ->> 'supplier') is null);
select tt.err('T3 unknown batch', 'select trace_batch(999999)', 'batch_not_found');
select tt.err('T3 bad direction', format($$select trace_batch(%s, 'sideways')$$, :'rawb'), 'bad_dir');

\echo == T4 find a batch
select tt.chk('T4 find by lot text', (select count(*) from jsonb_array_elements(trace_batch_find('TLOT-R')))=1);
select tt.chk('T4 find by item with stock', (select count(*) from jsonb_array_elements(trace_batch_find(null, :'fg'::uuid)))>=2);
select tt.chk('T4 a batch with no stock is hidden unless asked', (select count(*) from jsonb_array_elements(trace_batch_find('TLOT-R', null, null, true)))>=1);
select tt.err('T4 query text longer than 60 refused', format($$select trace_batch_find('%s')$$, repeat('x',61)), 'bad_query');

\echo == T5 who may see what
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T5 a salesperson (no report right) cannot trace', format($$select trace_batch(%s)$$, :'rawb'), 'not allowed');
select tt.err('T5 nor read recall cases', 'select recall_list()', 'not allowed');
reset role; select tt.as(:'k'); set role authenticated;
select trace_batch(:'rawb'::bigint, 'fwd') as trk \gset
select tt.chk('T5 a storekeeper with the stock report right sees his place only: other place counted as hidden, no sale there listed', (:'trk'::jsonb -> 'forward' ->> 'hidden_places')::int>=1
  and (select count(*) from jsonb_array_elements(:'trk'::jsonb -> 'forward' -> 'sales') x where (x->>'location_id')::int=2)=0);
reset role; select tt.as(:'f'); set role authenticated;
select tt.err('T5 a person at another place cannot trace a batch of place 1', format($$select trace_batch(%s)$$, :'rawb'), 'not allowed for this location');
reset role;

\echo == T6 recall case
select tt.as(:'o'); set role authenticated;
select tt.err('T6 title and reason are required', format($$select recall_open('ab','', null, array[%s]::bigint[])$$, :'rawb'), 'bad_title');
select tt.err('T6 reason required', format($$select recall_open('test recall','', null, array[%s]::bigint[])$$, :'rawb'), 'reason_required');
select tt.err('T6 unknown batch refused', $$select recall_open('test recall','test_reason', null, array[999999]::bigint[])$$, 'batch_not_found');
select recall_open('test recall A','test_reason lot suspected', 'test_hazard', array[:'rawb']::bigint[], 'c4310000-0000-0000-0000-000000000001') ->> 'id' as rc \gset
reset role;
select tt.chk('T6 the case is open with its batch and a red Exceptions line was written', (select status from recall_cases where id=:'rc'::uuid)='open' and (select count(*) from recall_batches where case_id=:'rc'::uuid)=1
  and (select count(*) from exceptions where flag_code='recall_opened' and level='red')=1);
set role authenticated;
select tt.chk('T6 the same client id returns the same case', (recall_open('test recall A','x y z', null, '{}', 'c4310000-0000-0000-0000-000000000001') ->> 'dup')::boolean);
select recall_affected(:'rc'::uuid) as ra1 \gset
select tt.chk('T6 affected stock: 3 batches reached, 3.5 kg sold, 1 named customer', jsonb_array_length(:'ra1'::jsonb -> 'forward' -> 'batches')=3 and (select sum((x->>'qty')::numeric) from jsonb_array_elements(:'ra1'::jsonb -> 'forward' -> 'sales') x)=3.5
  and (:'ra1'::jsonb -> 'summary' ->> 'named_customers')::int=1);
select tt.chk('T6 affected stock prints the unbatched 45 kg (50 without a lot, minus the 5 kg old batch added in T3) and says so in data_notes', (select (x->>'unbatched')::numeric from jsonb_array_elements(:'ra1'::jsonb -> 'summary' -> 'unbatched') x where x->>'code'='test_raw_a')=45 and (:'ra1'::jsonb -> 'data_notes') ? 'unbatched_stock_present');
select tt.chk('T6 receipts of the same item and supplier with no lot are listed (bill R-2)', (select count(*) from jsonb_array_elements(:'ra1'::jsonb -> 'unlotted_receipts') x where x->>'bill_no'='R-2' and x->>'supplier'='test_supplier_a')=1 and (:'ra1'::jsonb -> 'data_notes') ? 'receipts_without_lot');
select tt.chk('T6 the entered batch row carries its action status to_do', (:'ra1'::jsonb -> 'entered' -> 0 ->> 'action_status')='to_do');
select tt.err('T6 written off needs a note', format($$select recall_batch_mark('%s'::uuid, %s, 'written_off', '')$$, :'rc', :'rawb'), 'note_required');
select tt.err('T6 bad status', format($$select recall_batch_mark('%s'::uuid, %s, 'burnt', 'abc')$$, :'rc', :'rawb'), 'bad_status');
select tt.err('T6 a batch not in the case', format($$select recall_batch_mark('%s'::uuid, %s, 'removed_from_shelf', 'abc')$$, :'rc', :'oldb'), 'batch_not_in_case');
select recall_add_batch(:'rc'::uuid, :'oldb'::bigint, 'test_note') is not null as addb \gset
reset role;
select tt.chk('T6 a batch was added to the open case', (select count(*) from recall_batches where case_id=:'rc'::uuid)=2);
set role authenticated;
select recall_batch_mark(:'rc'::uuid, :'rawb'::bigint, 'removed_from_shelf', 'test shelf cleared') is not null as mk \gset
reset role;
select tt.chk('T6 the action is stored with who and when', (select action_status='removed_from_shelf' and action_by is not null and action_at is not null from recall_batches where case_id=:'rc'::uuid and batch_id=:'rawb'::bigint));
set role authenticated;
select tt.err('T6 closing needs a note', format($$select recall_close('%s'::uuid, '')$$, :'rc'), 'note_required');
select (recall_close(:'rc'::uuid, 'test all done') ->> 'still_to_do')::int as left_ \gset
select tt.chk('T6 closed with one batch still to do: said in the answer and as a yellow Exceptions line', :'left_'::int=1 and (select count(*) from exceptions where flag_code='recall_closed_open')=1);
select tt.err('T6 a closed case takes no new batch', format($$select recall_add_batch('%s'::uuid, %s)$$, :'rc', :'rawb'), 'case_closed');
select tt.err('T6 a closed case cannot change an action', format($$select recall_batch_mark('%s'::uuid, %s, 'written_off', 'abcd')$$, :'rc', :'rawb'), 'case_closed');
select tt.chk('T6 recall_list shows the case, closed, numbered', (select (x->>'case_no')::int>=1 and x->>'status'='closed' and (x->>'to_do_n')::int=1 from jsonb_array_elements(recall_list('closed')) x limit 1));
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T6 a salesperson cannot open a recall', format($$select recall_open('test recall B','test_reason', null, array[%s]::bigint[])$$, :'rawb'), 'not allowed');
reset role; select tt.as(:'k'); set role authenticated;
select tt.chk('T6 a storekeeper (grant recall_manage) can open one', (recall_open('test recall B','test_reason b', null, array[:'rawb']::bigint[]) ->> 'case_no') is not null);
reset role;

\echo == T7 nothing moved
select tt.chk('T7 no stock or money row was written by any trace or recall call (ledger rows only from the fixture)', (select count(*) from stock_ledger where reason not in ('purchase_in','issue_out','production_in','transfer_out','transfer_in','sale_out','sale_void_in'))=0);
select tt.chk('T7 the books balance (no journal entry from this package)', (select count(*) from journal_entries where source_type like 'recall%')=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
