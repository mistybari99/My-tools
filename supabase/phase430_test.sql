-- FRESH DB ONLY. Phase 430 tests (RPT-B3 R5a: supplier lot and expiry at the raw receipt). Needs phases 8 to 99 and phase430.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase430_test.sql | grep -E 'FAIL|RESULT'
-- Neutral test_* data only. The shared-function hook (tests/sql/rb3_hooks430.sql) is applied INSIDE a transaction that is rolled back.
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
create or replace function tt.errmsg(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function tt.d() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_sales@s.app','{"full_name":"test_sales"}'), (:'k','test_store@s.app','{"full_name":"test_store"}'), (:'f','test_far@s.app','{"full_name":"test_far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),(:'f','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'f',3) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('test_raw_a','test_raw_a','test_raw_a','kg','kg','raw_material',true,0), ('test_raw_b','test_raw_b','test_raw_b','kg','kg','raw_material',true,0),
 ('test_fg_a','test_fg_a','test_fg_a','kg','kg','finished_good',true,10);
insert into suppliers (name) values ('test_supplier_a');
select id as ra from items where code='test_raw_a' \gset
select id as rb from items where code='test_raw_b' \gset
select id as sa from suppliers where name='test_supplier_a' \gset

\echo == T0 shape
select tt.chk('T0 table has RLS and browsers cannot write it', (select relrowsecurity from pg_class where oid='public.receipt_lots'::regclass) and not has_table_privilege('authenticated','public.receipt_lots','insert') and has_table_privilege('authenticated','public.receipt_lots','select'));
select tt.chk('T0 public calls: authenticated yes, anon no; internals: nobody', has_function_privilege('authenticated','public.receipt_lots_stage(uuid,jsonb)','execute') and not has_function_privilege('anon','public.receipt_lots_stage(uuid,jsonb)','execute')
  and not has_function_privilege('authenticated','public._rb3_lot_apply(uuid)','execute') and not has_function_privilege('authenticated','public._rb3_lot_gate(uuid)','execute') and not has_function_privilege('anon','public.stock_unbatched(int,uuid)','execute'));
select tt.chk('T0 both switches exist and default OFF', not rule_on('receipt_lot_required') and not rule_on('receipt_expiry_required'));
select tt.chk('T0 no shared function carries the marker yet (hook is separate)', (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_rb3\_%' and position('bos430' in pg_get_functiondef(p.oid))>0)=0);

\echo == T1 stage lots on a draft
select tt.as(:'o'); set role authenticated;
select (save_purchase('b4300000-0000-0000-0000-000000000001'::uuid, null, :'sa'::uuid, 1, 'T-1', tt.d(), format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":5},{"item_id":"%s","qty":10,"unit":"kg","unit_cost":7},{"description":"test_freight","qty":1,"unit_cost":50}]', :'ra', :'rb')::jsonb) ->> 'id') as b1 \gset
select tt.chk('T1 stage one lot with expiry on line 1', (receipt_lots_stage(:'b1'::uuid, format('[{"line_no":1,"lot_no":"TLOT-1","expiry":"%s"}]', tt.d()+30)::jsonb) ->> 'staged')::int=1);
select tt.chk('T1 the staged lot is readable', (select count(*) from jsonb_array_elements(receipt_lots_get(:'b1'::uuid)) x where x->>'lot_no'='TLOT-1' and x->>'status'='staged')=1);
select tt.err('T1 a free-text line takes no lot', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":3,"lot_no":"X"}]'::jsonb)$$, :'b1'), 'line_not_stock');
select tt.err('T1 expiry before the bill date refused', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":1,"lot_no":"X","expiry":"2000-01-01"}]'::jsonb)$$, :'b1'), 'bad_expiry');
select tt.err('T1 lot number longer than 40 refused', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":1,"lot_no":"%s"}]'::jsonb)$$, :'b1', repeat('x',41)), 'bad_lot_no');
select tt.err('T1 two lots on one line need a quantity each', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":1,"lot_no":"A"},{"line_no":1,"lot_no":"B"}]'::jsonb)$$, :'b1'), 'qty_needed_for_each_lot');
select tt.err('T1 lots cannot exceed the line', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":1,"lot_no":"A","qty":70},{"line_no":1,"lot_no":"B","qty":40}]'::jsonb)$$, :'b1'), 'lots_exceed_line');
select tt.chk('T1 refused calls left the earlier staged lot as it was (the replace is rolled back with the refusal)', (select count(*) from receipt_lots where bill_id=:'b1'::uuid)=1);
select tt.chk('T1 empty entries are skipped, not stored', (receipt_lots_stage(:'b1'::uuid, '[{"line_no":1},{"line_no":2,"lot_no":"TLOT-B","expiry":null}]'::jsonb) ->> 'staged')::int=1 and (select count(*) from receipt_lots where bill_id=:'b1'::uuid)=1);
select receipt_lots_stage(:'b1'::uuid, format('[{"line_no":1,"lot_no":"TLOT-1","expiry":"%s"},{"line_no":2,"lot_no":"TLOT-B"}]', tt.d()+30)::jsonb) is not null as st2 \gset
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T1 a salesperson (no purchase right) cannot stage', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":1,"lot_no":"Z"}]'::jsonb)$$, :'b1'), 'not allowed');
select tt.err('T1 a salesperson cannot read the lots (no report or purchase right)', format($$select receipt_lots_get('%s'::uuid)$$, :'b1'), 'not allowed');
reset role; select tt.as(:'f'); set role authenticated;
select tt.err('T1 a person at another place cannot stage', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":1,"lot_no":"Z"}]'::jsonb)$$, :'b1'), 'not allowed');
reset role;

\echo == T2 post and apply
select tt.as(:'o'); set role authenticated;
select tt.err('T2 apply before posting refused', format($$select receipt_lots_apply('%s'::uuid)$$, :'b1'), 'not_posted');
select post_purchase(:'b1'::uuid) is not null as posted \gset
select tt.chk('T2 posting alone made no batch (no hook installed)', (select count(*) from stock_batches where item_id=:'ra')=0);
select tt.err('T2 staging after posting refused', format($$select receipt_lots_stage('%s'::uuid, '[{"line_no":1,"lot_no":"LATE"}]'::jsonb)$$, :'b1'), 'not_draft');
select (receipt_lots_apply(:'b1'::uuid) ->> 'applied')::int as ap \gset
select tt.chk('T2 two lots applied', :'ap'=2);
select tt.chk('T2 batch of raw A: lot no, quantity 100, expiry in 30 days', (select qty_made=100 and qty_remaining=100 and batch_no='TLOT-1' and (expires_at at time zone 'Asia/Dhaka')::date=tt.d()+30 from stock_batches where item_id=:'ra'));
select tt.chk('T2 batch of raw B has no expiry (null, not invented)', (select qty_made=10 and batch_no='TLOT-B' and expires_at is null from stock_batches where item_id=:'rb'));
select tt.chk('T2 the paper-GRN link exists only where a lot and an expiry exist', (select count(*) from grn_batch_links where source_type='purchase' and source_id=:'b1'::uuid)=1);
select tt.chk('T2 second apply does nothing', (receipt_lots_apply(:'b1'::uuid) ->> 'applied')::int=0 and (select count(*) from stock_batches where item_id in (:'ra',:'rb'))=2);
select tt.chk('T2 lots show applied with the batch id', (select count(*) from jsonb_array_elements(receipt_lots_get(:'b1'::uuid)) x where x->>'status'='applied' and x->>'batch_id' is not null)=2);
select tt.chk('T2 nothing unbatched after a fully lotted receipt', (select (x->>'unbatched')::numeric from jsonb_array_elements(stock_unbatched(1,:'ra'::uuid)) x)=0);
select tt.chk('T2 FEFO hint still works with the new batch', (select count(*) from fefo_hint(:'ra'::uuid,1))=1);

\echo == T3 partial lot: the rest stays unbatched and is said so
select (save_purchase('b4300000-0000-0000-0000-000000000002'::uuid, null, :'sa'::uuid, 1, 'T-2', tt.d(), format('[{"item_id":"%s","qty":50,"unit":"kg","unit_cost":5}]', :'ra')::jsonb) ->> 'id') as b2 \gset
select receipt_lots_stage(:'b2'::uuid, format('[{"line_no":1,"lot_no":"TLOT-2","expiry":"%s","qty":30}]', tt.d()+60)::jsonb) is not null as st3 \gset
select post_purchase(:'b2'::uuid) is not null as posted2 \gset
select (receipt_lots_apply(:'b2'::uuid) ->> 'applied')::int as ap2 \gset
select tt.chk('T3 a batch of 30 was made', :'ap2'=1 and (select qty_made from stock_batches where batch_no='TLOT-2')=30);
select tt.chk('T3 unbatched = 20 (150 on hand, 130 in batches), printed as a number', (select (x->>'unbatched')::numeric from jsonb_array_elements(stock_unbatched(1,:'ra'::uuid)) x)=20 and (select (x->>'on_hand')::numeric from jsonb_array_elements(stock_unbatched(1,:'ra'::uuid)) x)=150);
select tt.chk('T3 batches expire in FEFO order (30 days first)', (select batch_no from fefo_hint(:'ra'::uuid,1) order by rank limit 1)='TLOT-1');

\echo == T4 required switches (server gate, checked directly)
select (save_purchase('b4300000-0000-0000-0000-000000000003'::uuid, null, :'sa'::uuid, 1, 'T-3', tt.d(), format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":5}]', :'ra')::jsonb) ->> 'id') as b3 \gset
reset role;
select tt.chk('T4 the gate is not callable by a browser user', not has_function_privilege('authenticated','public._rb3_lot_gate(uuid)','execute'));
select tt.chk('T4 switches OFF: the gate lets everything pass', tt.errmsg(format($$select public._rb3_lot_gate('%s'::uuid)$$, :'b3')) is null);
select set_rule('receipt_lot_required','true'::jsonb) is null as r1 \gset
select tt.chk('T4 lot required: a bill with a stock line and no lot is refused by the gate', tt.errmsg(format($$select public._rb3_lot_gate('%s'::uuid)$$, :'b3')) like '%lot_required%');
select tt.chk('T4 the check lists the missing line', (receipt_lot_check(:'b3'::uuid) -> 'missing' -> 0 ->> 'code')='test_raw_a' and (receipt_lot_check(:'b3'::uuid) ->> 'lot_required')::boolean);
select receipt_lots_stage(:'b3'::uuid, '[{"line_no":1,"lot_no":"TLOT-3"}]'::jsonb) is not null as st4 \gset
select tt.chk('T4 lot required, lot given: gate passes', tt.errmsg(format($$select public._rb3_lot_gate('%s'::uuid)$$, :'b3')) is null);
select set_rule('receipt_expiry_required','true'::jsonb) is null as r2 \gset
select tt.chk('T4 expiry required too: lot without expiry refused', tt.errmsg(format($$select public._rb3_lot_gate('%s'::uuid)$$, :'b3')) like '%expiry_required%');
select receipt_lots_stage(:'b3'::uuid, format('[{"line_no":1,"lot_no":"TLOT-3","expiry":"%s"}]', tt.d()+20)::jsonb) is not null as st5 \gset
select tt.chk('T4 lot and expiry given: gate passes', tt.errmsg(format($$select public._rb3_lot_gate('%s'::uuid)$$, :'b3')) is null);
select set_rule('receipt_lot_required','false'::jsonb) is null as r3 \gset
select set_rule('receipt_expiry_required','false'::jsonb) is null as r4 \gset
select tt.chk('T4 back to OFF', not rule_on('receipt_lot_required') and not rule_on('receipt_expiry_required'));

\echo == T5 the hook (scratch copy, rolled back): server refuses and posting applies the lots by itself
begin;
\ir ../tests/sql/rb3_hooks430.sql
select position('bos430' in pg_get_functiondef('public.post_purchase(uuid,jsonb)'::regprocedure))>0 as h_marker \gset
select public._rb3_patch('public.post_purchase(uuid,jsonb)'::regprocedure, array['x','y'], 'bos430') as h_second \gset
select set_rule('receipt_lot_required','true'::jsonb) is null as h1 \gset
select (save_purchase('b4300000-0000-0000-0000-000000000004'::uuid, null, :'sa'::uuid, 1, 'T-4', tt.d(), format('[{"item_id":"%s","qty":8,"unit":"kg","unit_cost":5}]', :'rb')::jsonb) ->> 'id') as b4 \gset
select tt.errmsg(format($$select post_purchase('%s'::uuid)$$, :'b4')) as h_err \gset
select (select status from purchase_bills where id=:'b4'::uuid) as h_st, (select qty from stock_balance where item_id=:'rb' and location_id=1) as h_qty \gset
select receipt_lots_stage(:'b4'::uuid, format('[{"line_no":1,"lot_no":"TLOT-4","expiry":"%s"}]', tt.d()+9)::jsonb) is not null as h2 \gset
select post_purchase(:'b4'::uuid) is not null as h3 \gset
select (select qty_made from stock_batches where batch_no='TLOT-4') as h_bq, (select status from receipt_lots where bill_id=:'b4'::uuid) as h_ls \gset
select set_rule('receipt_lot_required','false'::jsonb) is null as h4 \gset
select (save_purchase('b4300000-0000-0000-0000-000000000005'::uuid, null, :'sa'::uuid, 1, 'T-5', tt.d(), format('[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":5}]', :'rb')::jsonb) ->> 'id') as b5 \gset
select post_purchase(:'b5'::uuid) is not null as h5 \gset
select (select count(*) from stock_batches where item_id=:'rb') as h_nb \gset
rollback;
select tt.chk('T5 post_purchase carries the marker on the scratch copy', :'h_marker'::boolean);
select tt.chk('T5 pasting the hook twice is a no-op', not :'h_second'::boolean);
select tt.chk('T5 lot required: post_purchase refuses a bill with no lot', :'h_err' like '%lot_required%');
select tt.chk('T5 the refused bill is still a draft and made no stock', :'h_st'='draft' and :'h_qty'::numeric=10);
select tt.chk('T5 with a lot the bill posts and the batch exists without any extra call', :'h_bq'::numeric=8 and :'h_ls'='applied');
select tt.chk('T5 switch OFF, no lot staged: posting is exactly as before (no new batch)', :'h_nb'::int=2);
select tt.chk('T5 after the rollback the database carries no marker in a shared function', (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname not like '\_rb3\_%' and position('bos430' in pg_get_functiondef(p.oid))>0)=0
  and (select count(*) from purchase_bills where bill_no in ('T-4','T-5'))=0);

\echo == T6 reads leave the books alone
select tt.chk('T6 the lot functions wrote no ledger row of their own (3 purchase_in rows: 2 lines of bill 1, 1 of bill 2)', (select count(*) from stock_ledger where reason in ('purchase_in'))=3);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
