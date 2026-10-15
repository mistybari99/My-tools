-- FRESH DB ONLY. Phase 114 tests (batch 2 stock safety, part 1). Every number is hand-computed; "default" cases reproduce the audit2 A2 findings, "on" cases show the fix.
--   bash tests/sql/final_build.sh p114db ; psql -h /tmp -p 5544 -U postgres -d p114db -qAt -f supabase/phase114_test.sql | grep -E 'FAIL|RESULT'
\set o  '00000000-0000-0000-0000-000000000001'
\set sp '00000000-0000-0000-0000-000000000004'
\set sk '00000000-0000-0000-0000-000000000005'
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
create or replace function tt.iid(p_code text) returns uuid language sql stable as $$ select id from public.items where code = p_code $$;
create or replace function tt.qty(p_code text, p_loc int default 1) returns numeric language sql stable as $$
  select coalesce((select b.qty from public.stock_balance b where b.item_id = tt.iid(p_code) and b.location_id = p_loc), 0) $$;
create or replace function tt.bsum(p_code text, p_loc int default 1) returns numeric language sql stable as $$
  select coalesce(sum(qty_remaining), 0) from public.stock_batches where item_id = tt.iid(p_code) and location_id = p_loc $$;
create or replace function tt.sale(p_loc int, p_code text, p_qty numeric, p_at timestamptz default null, p_offline boolean default false) returns jsonb language plpgsql as $$
declare amt numeric; l jsonb;
begin select round(p_qty * sell_price, 2) into amt from public.items where code = p_code;
  l := jsonb_build_array(jsonb_build_object('item_id', tt.iid(p_code), 'qty', p_qty));
  if p_offline then return public.record_sale_offline(gen_random_uuid(), p_loc, l, 0, jsonb_build_array(jsonb_build_object('mode','cash','amount', amt)), null, null, 'retail', null, false, p_at); end if;
  return public.record_sale2(gen_random_uuid(), p_loc, l, 0, jsonb_build_array(jsonb_build_object('mode','cash','amount', amt)), null, null, 'retail', null, false, p_at); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'sp','seller4@s.app','{"full_name":"Seller"}'), (:'sk','keeper5@s.app','{"full_name":"Keeper"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'sp','salesperson'),(:'sk','storekeeper') on conflict do nothing;
insert into user_locations values (:'sp',1),(:'sk',1),(:'sk',2) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('L1','Late 1','Late 1','kg','kg','finished_good',true,10,true),('L2','Late 2','Late 2','kg','kg','finished_good',true,10,true),('L3','Late 3','Late 3','kg','kg','finished_good',true,10,true),
 ('X1','Xfer 1','Xfer 1','kg','kg','finished_good',true,10,true),('X2','Xfer 2','Xfer 2','kg','kg','finished_good',true,10,true),
 ('U1','Unit 1 (pc, base kg)','Unit 1','pc','kg','finished_good',true,50,true),('U2','Unit 2 (pc, base kg)','Unit 2','pc','kg','finished_good',true,50,true),
 ('B1','Base 1','Base 1','kg','kg','finished_good',true,10,true),('B2','Base 2','Base 2','kg','kg','finished_good',true,10,true),
 ('Z1','Life 1','Life 1','kg','kg','finished_good',true,10,true),('Z2','Life 2','Life 2','kg','kg','finished_good',true,10,true),
 ('G1','Gain 1','Gain 1','kg','kg','finished_good',true,10,true),('G2','Gain 2','Gain 2','kg','kg','finished_good',true,10,true),
 ('O1','Open 1','Open 1','kg','kg','finished_good',true,10,true),('O2','Open 2','Open 2','kg','kg','finished_good',true,10,true),
 ('R1','Refill 1','Refill 1','kg','kg','finished_good',true,10,true),('R2','Refill 2','Refill 2','kg','kg','finished_good',true,10,true);
select set_unit_conversion(tt.iid('U1'),'pc','kg',0.2,'1 pc = 0.2 kg'); select set_unit_conversion(tt.iid('U2'),'pc','kg',0.2,'1 pc = 0.2 kg');

\echo == T0 shape, paste twice
select tt.chk('T0 seven rules, all switches, default false', (select count(*) = 7 and bool_and(kind = 'switch' and default_value = 'false'::jsonb) from rules where key in ('late_sale_follows_block','transfer_needs_stock','return_uses_sale_rows','item_unit_change_needs_zero','item_lifecycle_needs_zero','batch_for_adjustments','batch_refill_cap')));
select tt.chk('T0 seven advisor rows of phase 114', (select count(*) = 7 from setup_rec_defs81 where phase = '114'));
select tt.chk('T0 transfer_needs_stock has no recommended value (owner decides after the first count)', (select rec_value is null from setup_rec_defs81 where code = 'transfer_needs_stock'));
select tt.chk('T0 the five patched functions carry bos114 and keep their older tags', (select bool_and(case proname
   when '_sale_stock_out' then d ~ 'bos114:late-sale' and d ~ 'bos94' and d ~ 'bos83' and d ~ 'bos82' when 'stock_transfer' then d ~ 'bos114:xfer-stock'
   when 'sale_return' then d ~ 'bos114:return-rows' and d ~ 'bos80' when 'stock_count_adjust' then d ~ 'bos114:count-batch' and d ~ 'bos85' else d ~ 'bos114:opening-batch' end)
   from (select proname, pg_get_functiondef(oid) d from pg_proc where pronamespace = 'public'::regnamespace and proname in ('_sale_stock_out','stock_transfer','sale_return','stock_count_adjust','stock_opening')) z));
select tt.chk('T0 internal functions have no privilege for anon / authenticated', not has_function_privilege('authenticated', 'public._adj_batch114(uuid,integer,numeric,text)', 'execute') and not has_function_privilege('authenticated', 'public._stock_batch_refill114()', 'execute')
   and has_function_privilege('authenticated', 'public.stock_batch_reconcile(boolean)', 'execute') and not has_function_privilege('anon', 'public.stock_batch_reconcile(boolean)', 'execute'));
select tt.chk('T0 helper _b2_patch114 is gone', to_regprocedure('public._b2_patch114(text,text,text,text)') is null);

\echo == T1 G3 block bypass by an old p_sold_at (A2 i4)
select set_rule('stock_negative_mode', '"block"'::jsonb);
select stock_opening(tt.iid('L1'),1,3,10) is not null as a \gset
select stock_opening(tt.iid('L2'),1,3,10) is not null as a \gset
select stock_opening(tt.iid('L3'),1,3,10) is not null as a \gset
select tt.as(:'sp');
select tt.err('T1 default: sale 10 of stock 3 with p_sold_at = now is refused', $$select tt.sale(1,'L1',10)$$, 'insufficient_stock');
select tt.sale(1,'L1',10, now() - interval '5 minutes') is not null as ok \gset
select tt.chk('T1 default: the SAME sale with p_sold_at = now-5min is accepted (today: block bypassed), balance 3 - 10 = -7', tt.qty('L1') = -7);
select tt.as(:'o'); select set_rule('late_sale_follows_block', 'true'::jsonb); select tt.as(:'sp');
select tt.err('T1 on: sale 10 of stock 3 with p_sold_at = now-5min is refused', $$select tt.sale(1,'L2',10, now() - interval '5 minutes')$$, 'insufficient_stock');
select tt.chk('T1 on: balance still 3 and no sale row for that attempt', tt.qty('L2') = 3 and not exists (select 1 from sales where lines::text like '%' || tt.iid('L2')::text || '%'));
select tt.sale(1,'L2',3, now() - interval '5 minutes') is not null as ok \gset
select tt.chk('T1 on: a late sale of exactly the stock (3) is accepted, balance 0', tt.qty('L2') = 0);
select tt.sale(1,'L2',10, now() - interval '5 minutes', true) is not null as ok \gset
select tt.chk('T1 on: a real offline-queue replay (record_sale_offline) of 10 with stock 0 is still accepted (soft): 0 - 10 = -10', tt.qty('L2') = -10);
select tt.as(:'o'); select set_rule('stock_negative_mode', '"warn"'::jsonb); select tt.as(:'sp');
select tt.sale(1,'L3',10, now() - interval '5 minutes') is not null as ok \gset
select tt.chk('T1 on + warn mode: nothing is blocked, 3 - 10 = -7 with a yellow flag', tt.qty('L3') = -7 and exists (select 1 from exceptions where flag_code = 'stock_negative'));
select tt.as(:'o'); select set_rule('late_sale_follows_block', 'false'::jsonb); select set_rule('stock_negative_mode', 'null'::jsonb);

\echo == T2 G6 transfer above the sender's stock (A2 g8, A5 C22)
select stock_opening(tt.iid('X1'),1,10,10) is not null as a \gset
select stock_opening(tt.iid('X2'),1,10,10) is not null as a \gset
select tt.as(:'sk');
select stock_transfer(1,2,tt.iid('X1'),20) ->> 'status' as s \gset
select tt.chk('T2 default: transfer of 20 from stock 10 accepted, sender 10 - 20 = -10 (stock from nothing)', :'s' = 'sent' and tt.qty('X1') = -10);
select tt.as(:'o'); select set_rule('transfer_needs_stock', 'true'::jsonb); select tt.as(:'sk');
select tt.err('T2 on: transfer of 20 from stock 10 refused', $$select stock_transfer(1,2,tt.iid('X2'),20)$$, 'insufficient_stock');
select tt.chk('T2 on: sender still 10 and no transfer row for X2', tt.qty('X2') = 10 and not exists (select 1 from stock_transfers where item_id = tt.iid('X2')));
select stock_transfer(1,2,tt.iid('X2'),10) ->> 'status' as s \gset
select tt.chk('T2 on: transfer of exactly 10 accepted, sender 0, in transit 10', :'s' = 'sent' and tt.qty('X2') = 0 and (select sum(qty) from stock_in_transit() where item_id = tt.iid('X2')) = 10);
select tt.as(:'o');
select stock_transfer(1,2,tt.iid('X2'),5) ->> 'status' as s \gset
select tt.chk('T2 on: the owner (sell_below_zero) can still send 5 more, sender -5', :'s' = 'sent' and tt.qty('X2') = -5);
select set_rule('transfer_needs_stock', 'false'::jsonb);

\echo == T3 G5 return after a unit factor edit (A2 d7)
select stock_opening(tt.iid('U1'),1,5,100) is not null as a \gset
select stock_opening(tt.iid('U2'),1,5,100) is not null as a \gset
select tt.as(:'sp'); select (tt.sale(1,'U1',3) ->> 'id')::uuid as s1 \gset
select (tt.sale(1,'U2',3) ->> 'id')::uuid as s2 \gset
select tt.chk('T3 3 pc at 0.2 kg: 5 - 0.6 = 4.4 for both', tt.qty('U1') = 4.4 and tt.qty('U2') = 4.4);
select tt.as(:'o'); select set_unit_conversion(tt.iid('U1'),'pc','kg',0.25,'edited'); select set_unit_conversion(tt.iid('U2'),'pc','kg',0.25,'edited');
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":1}]', tt.iid('U1'))::jsonb, 'damaged', null, 'cash') is not null as a \gset
select tt.chk('T3 default: return 1 pc after the factor became 0.25 restores 0.25 (wrong): 4.4 + 0.25 = 4.65', tt.qty('U1') = 4.65);
select set_rule('return_uses_sale_rows', 'true'::jsonb);
select sale_return(gen_random_uuid(), :'s2'::uuid, format('[{"item_id":"%s","qty":1}]', tt.iid('U2'))::jsonb, 'damaged', null, 'cash') is not null as a \gset
select tt.chk('T3 on: return 1 pc restores what the sale took out (0.2): 4.4 + 0.2 = 4.6', tt.qty('U2') = 4.6);
select sale_return(gen_random_uuid(), :'s2'::uuid, format('[{"item_id":"%s","qty":2}]', tt.iid('U2'))::jsonb, 'damaged', null, 'cash') is not null as a \gset
select tt.chk('T3 on: the other 2 pc restore 0.4 -> back to exactly 5.0 (not 5.05)', tt.qty('U2') = 5);
select tt.err('T3 on: returning more than sold is still refused', format($$select sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'s2', tt.iid('U2')), 'return_exceeds_sale');
select set_rule('return_uses_sale_rows', 'false'::jsonb);

\echo == T4 G5 base unit change with stock (A2 k0)
select stock_opening(tt.iid('B1'),1,10,10) is not null as a \gset
select stock_opening(tt.iid('B2'),1,10,10) is not null as a \gset
update items set base_unit = 'pc' where code = 'B1';
select tt.chk('T4 default: base unit kg -> pc accepted with 10 on hand (the number 10 now means pieces)', (select base_unit from items where code = 'B1') = 'pc');
select set_rule('item_unit_change_needs_zero', 'true'::jsonb);
select tt.err('T4 on: base unit change with 10 on hand refused', $$update items set base_unit = 'pc' where code = 'B2'$$, 'item_has_stock');
select tt.chk('T4 on: B2 still kg', (select base_unit from items where code = 'B2') = 'kg');
update items set sell_price = 11 where code = 'B2';
select tt.chk('T4 on: other edits (price) are not touched', (select sell_price from items where code = 'B2') = 11);
select stock_wastage(tt.iid('B2'),1,10,'spoiled','zero it',null,null,gen_random_uuid(),null) is not null as a \gset
update items set base_unit = 'pc' where code = 'B2';
select tt.chk('T4 on: with stock 0 the base unit can change', (select base_unit from items where code = 'B2') = 'pc');
select set_rule('item_unit_change_needs_zero', 'false'::jsonb);

\echo == T5 G9 untrack / deactivate with stock (A2 k4 k5)
select stock_opening(tt.iid('Z1'),1,8,100) is not null as a \gset
select stock_opening(tt.iid('Z2'),1,8,100) is not null as a \gset
update items set tracked = false where code = 'Z1';
select tt.chk('T5 default: untrack with 8 on hand accepted (book stays 8)', not (select tracked from items where code = 'Z1') and tt.qty('Z1') = 8);
update items set tracked = true, is_active = false where code = 'Z1';
select tt.chk('T5 default: deactivate with 8 on hand accepted', not (select is_active from items where code = 'Z1'));
select set_rule('item_lifecycle_needs_zero', 'true'::jsonb);
select tt.err('T5 on: untrack with 8 on hand refused', $$update items set tracked = false where code = 'Z2'$$, 'item_has_stock');
select tt.err('T5 on: deactivate with 8 on hand refused', $$update items set is_active = false where code = 'Z2'$$, 'item_has_stock');
select tt.chk('T5 on: Z2 unchanged', (select tracked and is_active from items where code = 'Z2'));
select stock_wastage(tt.iid('Z2'),1,8,'spoiled','zero it',null,null,gen_random_uuid(),null) is not null as a \gset
update items set is_active = false where code = 'Z2';
select tt.chk('T5 on: with stock 0 the item can be deactivated', not (select is_active from items where code = 'Z2'));
select set_rule('item_lifecycle_needs_zero', 'false'::jsonb);

\echo == T6 G8 batches: count gain, opening, negative refill (A2 h6 c2 j7)
select stock_production_in(tt.iid('G1'),1,5) is not null as a \gset
select stock_production_in(tt.iid('G2'),1,5) is not null as a \gset
select stock_count_adjust(tt.iid('G1'),1,6,'count') is not null as a \gset
select tt.chk('T6 default: count gain +1 on a batch item: batches 5 vs balance 6', tt.bsum('G1') = 5 and tt.qty('G1') = 6);
select set_rule('batch_for_adjustments', 'true'::jsonb);
select stock_count_adjust(tt.iid('G2'),1,6,'count') is not null as a \gset
select tt.chk('T6 on: count gain +1: batches 5 + 1 = 6 = balance, the new batch has no expiry', tt.bsum('G2') = 6 and tt.qty('G2') = 6
  and (select count(*) from stock_batches where item_id = tt.iid('G2') and expires_at is null and qty_made = 1) = 1);
select stock_count_adjust(tt.iid('G2'),1,4,'count loss') is not null as a \gset
select tt.chk('T6 on: a count LOSS of 2 takes from the batches (earliest first) and stays equal: 4 = 4', tt.bsum('G2') = 4 and tt.qty('G2') = 4);
select stock_opening(tt.iid('O1'),1,9,10) is not null as a \gset
select tt.chk('T6 on: opening 9 gets one no-expiry batch of 9', tt.bsum('O1') = 9 and (select count(*) from stock_batches where item_id = tt.iid('O1')) = 1);
select set_rule('batch_for_adjustments', 'false'::jsonb);
select stock_opening(tt.iid('O2'),1,9,10) is not null as a \gset
select tt.chk('T6 default: opening 9 has no batch (batches 0, balance 9)', tt.bsum('O2') = 0 and tt.qty('O2') = 9);
-- negative refill: balance -2 then production 10
select tt.sale(1,'R1',2) is not null as a \gset
select tt.sale(1,'R2',2) is not null as a \gset
select tt.chk('T6 setup: both refill items at -2 (warn mode)', tt.qty('R1') = -2 and tt.qty('R2') = -2);
select stock_production_in(tt.iid('R1'),1,10) is not null as a \gset
select tt.chk('T6 default: production 10 into -2: balance 8, batch 10 (2 phantom)', tt.qty('R1') = 8 and tt.bsum('R1') = 10);
select set_rule('batch_refill_cap', 'true'::jsonb);
select stock_production_in(tt.iid('R2'),1,10) is not null as a \gset
select tt.chk('T6 on: production 10 into -2: balance 8, batch 8', tt.qty('R2') = 8 and tt.bsum('R2') = 8 and (select qty_made from stock_batches where item_id = tt.iid('R2')) = 10);
select tt.sale(1,'R2',8) is not null as a \gset
select tt.chk('T6 on: selling the 8 empties both: balance 0, batches 0', tt.qty('R2') = 0 and tt.bsum('R2') = 0);
select set_rule('batch_refill_cap', 'false'::jsonb);

\echo == T7 stock_batch_reconcile
select tt.chk('T7 report lists G1 (batches 5, balance 6, diff -1) and R1 (batches 10, balance 8, diff +2) and not the repaired ones',
  (select count(*) = 2 from stock_batch_reconcile(false) r where r.item_id in (tt.iid('G1'), tt.iid('R1')))
  and (select diff from stock_batch_reconcile(false) r where r.item_id = tt.iid('G1')) = -1 and (select diff from stock_batch_reconcile(false) r where r.item_id = tt.iid('R1')) = 2
  and not exists (select 1 from stock_batch_reconcile(false) r where r.item_id in (tt.iid('G2'), tt.iid('O1'), tt.iid('R2'))));
select tt.chk('T7 report only: nothing changed', tt.bsum('G1') = 5);
select (select fixed from stock_batch_reconcile(true) r where r.item_id = tt.iid('G1')) as fx \gset
select tt.chk('T7 fix adds an adjustment batch of exactly 1 for G1 (5 + 1 = 6) and leaves the phantom +2 (R1) alone', :'fx'::boolean and tt.bsum('G1') = 6 and tt.bsum('R1') = 10);
select tt.chk('T7 after the fix only R1 remains, and one audit row was written', (select count(*) = 1 from stock_batch_reconcile(false)) and (select count(*) = 1 from audit_log where action = 'batch_reconcile_fix'));
select tt.as(:'sp');
select tt.err('T7 a non-owner cannot run it', $$select * from stock_batch_reconcile(false)$$, 'not allowed');
select tt.as(:'o');

\echo == T8 ledger equals balance everywhere, paste twice changes nothing
select tt.chk('T8 stock_reconcile: 0 differences', (select count(*) = 0 from stock_reconcile(false)));
create temp table h1 as select proname, md5(pg_get_functiondef(oid)) h from pg_proc where pronamespace = 'public'::regnamespace and proname in ('_sale_stock_out','stock_transfer','sale_return','stock_count_adjust','stock_opening','stock_batch_reconcile','_adj_batch114','_stock_batch_refill114','_items_stock_guard114');
create temp table r1 as select key, value, default_value from rules where key in ('late_sale_follows_block','transfer_needs_stock','return_uses_sale_rows','item_unit_change_needs_zero','item_lifecycle_needs_zero','batch_for_adjustments','batch_refill_cap');
select count(*) as nrec1 from setup_rec_defs81 \gset
\i supabase/phase114.sql
select tt.chk('T8 paste twice: same function bodies', (select count(*) = 9 from h1 where exists (select 1 from pg_proc p where p.proname = h1.proname and p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) = h1.h)));
select tt.chk('T8 paste twice: rules and advisor rows unchanged', (select count(*) = 7 from r1 join rules r using (key) where r.value is not distinct from r1.value and r.default_value = r1.default_value) and (select count(*) from setup_rec_defs81) = :nrec1);
select tt.chk('T8 paste twice: one trigger each', (select count(*) from pg_trigger where tgname in ('stock_batch_refill114','items_stock_guard114')) = 2);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
