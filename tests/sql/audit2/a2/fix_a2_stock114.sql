-- A2 FIX probes (gap closure by phase114: G3 late sale vs block, G5 return after unit edit + base unit change, G6 transfer above stock,
-- G8 batches vs balance, G9 item lifecycle).  Self-contained scenario with the audit's numbers (hand-computed, see the comments), derived from
-- supabase/phase114_test.sql.  Own session on a clone of the template DB.  The batch switches are NOT set here: defaults = OFF -> FAIL = gap
-- open by default; switches_on.txt = ON -> PASS = closed.  Labels start FX2-<gap>.
\i tests/sql/e2e/00_common.sql
create or replace function tt.chk(p_name text, p_ok boolean) returns void language sql as $$ select tt.t(p_name, p_ok) $$;
create or replace function tt.bsum(p_code text, p_loc int default 1) returns numeric language sql stable as $$
  select coalesce(sum(qty_remaining), 0) from public.stock_batches where item_id = tt.iid(p_code) and location_id = p_loc $$;
create or replace function tt.sale(p_loc int, p_code text, p_qty numeric, p_at timestamptz default null, p_offline boolean default false) returns jsonb language plpgsql as $$
declare amt numeric; l jsonb;
begin select round(p_qty * sell_price, 2) into amt from public.items where code = p_code;
  l := jsonb_build_array(jsonb_build_object('item_id', tt.iid(p_code), 'qty', p_qty));
  if p_offline then return public.record_sale_offline(gen_random_uuid(), p_loc, l, 0, jsonb_build_array(jsonb_build_object('mode','cash','amount', amt)), null, null, 'retail', null, false, p_at); end if;
  return public.record_sale2(gen_random_uuid(), p_loc, l, 0, jsonb_build_array(jsonb_build_object('mode','cash','amount', amt)), null, null, 'retail', null, false, p_at); end $$;
grant execute on all functions in schema tt to authenticated, anon;
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
\echo == T1 G3 block bypass by an old p_sold_at (A2 i4)
select set_rule('stock_negative_mode', '"block"'::jsonb);
select stock_opening(tt.iid('L1'),1,3,10) is not null as a \gset
select stock_opening(tt.iid('L2'),1,3,10) is not null as a \gset
select stock_opening(tt.iid('L3'),1,3,10) is not null as a \gset
select tt.as(:'sp');
select tt.sale(1,'L1',10, now() - interval '5 minutes') is not null as ok \gset
select tt.as(:'o');  select tt.as(:'sp');
select tt.err('FX2-G3 T1 sale 10 of stock 3 with p_sold_at = now-5min is refused', $$select tt.sale(1,'L2',10, now() - interval '5 minutes')$$, 'insufficient_stock');
select tt.chk('FX2-G3 T1 balance still 3 and no sale row for that attempt', tt.qty('L2') = 3 and not exists (select 1 from sales where lines::text like '%' || tt.iid('L2')::text || '%'));
select tt.sale(1,'L2',3, now() - interval '5 minutes') is not null as ok \gset
select tt.chk('FX2-G3 T1 a late sale of exactly the stock (3) is accepted, balance 0', tt.qty('L2') = 0);
select tt.sale(1,'L2',10, now() - interval '5 minutes', true) is not null as ok \gset
select tt.chk('FX2-G3 T1 a real offline-queue replay (record_sale_offline) of 10 with stock 0 is still accepted (soft): 0 - 10 = -10', tt.qty('L2') = -10);
select tt.as(:'o'); select set_rule('stock_negative_mode', '"warn"'::jsonb); select tt.as(:'sp');
select tt.sale(1,'L3',10, now() - interval '5 minutes') is not null as ok \gset
select tt.chk('FX2-G3 T1 warn mode: nothing is blocked, 3 - 10 = -7 with a yellow flag', tt.qty('L3') = -7 and exists (select 1 from exceptions where flag_code = 'stock_negative'));
select tt.as(:'o');  select set_rule('stock_negative_mode', 'null'::jsonb);

\echo == T2 G6 transfer above the sender's stock (A2 g8, A5 C22)
select stock_opening(tt.iid('X1'),1,10,10) is not null as a \gset
select stock_opening(tt.iid('X2'),1,10,10) is not null as a \gset
select tt.as(:'sk');
select stock_transfer(1,2,tt.iid('X1'),20) ->> 'status' as s \gset
select tt.as(:'o');  select tt.as(:'sk');
select tt.err('FX2-G6 T2 transfer of 20 from stock 10 refused', $$select stock_transfer(1,2,tt.iid('X2'),20)$$, 'insufficient_stock');
select tt.chk('FX2-G6 T2 sender still 10 and no transfer row for X2', tt.qty('X2') = 10 and not exists (select 1 from stock_transfers where item_id = tt.iid('X2')));
select stock_transfer(1,2,tt.iid('X2'),10) ->> 'status' as s \gset
select tt.chk('FX2-G6 T2 transfer of exactly 10 accepted, sender 0, in transit 10', :'s' = 'sent' and tt.qty('X2') = 0 and (select sum(qty) from stock_in_transit() where item_id = tt.iid('X2')) = 10);
select tt.as(:'o');
select stock_transfer(1,2,tt.iid('X2'),5) ->> 'status' as s \gset
select tt.chk('FX2-G6 T2 the owner (sell_below_zero) can still send 5 more, sender -5', :'s' = 'sent' and tt.qty('X2') = -5);

\echo == T3 G5 return after a unit factor edit (A2 d7)
select stock_opening(tt.iid('U1'),1,5,100) is not null as a \gset
select stock_opening(tt.iid('U2'),1,5,100) is not null as a \gset
select tt.as(:'sp'); select (tt.sale(1,'U1',3) ->> 'id')::uuid as s1 \gset
select (tt.sale(1,'U2',3) ->> 'id')::uuid as s2 \gset
select tt.chk('FX2-G5 T3 3 pc at 0.2 kg: 5 - 0.6 = 4.4 for both', tt.qty('U1') = 4.4 and tt.qty('U2') = 4.4);
select tt.as(:'o'); select set_unit_conversion(tt.iid('U1'),'pc','kg',0.25,'edited'); select set_unit_conversion(tt.iid('U2'),'pc','kg',0.25,'edited');
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":1}]', tt.iid('U1'))::jsonb, 'damaged', null, 'cash') is not null as a \gset
select sale_return(gen_random_uuid(), :'s2'::uuid, format('[{"item_id":"%s","qty":1}]', tt.iid('U2'))::jsonb, 'damaged', null, 'cash') is not null as a \gset
select tt.chk('FX2-G5 T3 return 1 pc restores what the sale took out (0.2): 4.4 + 0.2 = 4.6', tt.qty('U2') = 4.6);
select sale_return(gen_random_uuid(), :'s2'::uuid, format('[{"item_id":"%s","qty":2}]', tt.iid('U2'))::jsonb, 'damaged', null, 'cash') is not null as a \gset
select tt.chk('FX2-G5 T3 the other 2 pc restore 0.4 -> back to exactly 5.0 (not 5.05)', tt.qty('U2') = 5);
select tt.err('FX2-G5 T3 returning more than sold is still refused', format($$select sale_return(gen_random_uuid(), %L::uuid, '[{"item_id":"%s","qty":1}]'::jsonb, 'damaged', null, 'cash')$$, :'s2', tt.iid('U2')), 'return_exceeds_sale');

\echo == T4 G5 base unit change with stock (A2 k0)
select stock_opening(tt.iid('B1'),1,10,10) is not null as a \gset
select stock_opening(tt.iid('B2'),1,10,10) is not null as a \gset
update items set base_unit = 'pc' where code = 'B1';
select tt.err('FX2-G5 T4 base unit change with 10 on hand refused', $$update items set base_unit = 'pc' where code = 'B2'$$, 'item_has_stock');
select tt.chk('FX2-G5 T4 B2 still kg', (select base_unit from items where code = 'B2') = 'kg');
update items set sell_price = 11 where code = 'B2';
select tt.chk('FX2-G5 T4 other edits (price) are not touched', (select sell_price from items where code = 'B2') = 11);
select stock_wastage(tt.iid('B2'),1,10,'spoiled','zero it',null,null,gen_random_uuid(),null) is not null as a \gset
update items set base_unit = 'pc' where code = 'B2';
select tt.chk('FX2-G5 T4 with stock 0 the base unit can change', (select base_unit from items where code = 'B2') = 'pc');

\echo == T5 G9 untrack / deactivate with stock (A2 k4 k5)
select stock_opening(tt.iid('Z1'),1,8,100) is not null as a \gset
select stock_opening(tt.iid('Z2'),1,8,100) is not null as a \gset
update items set tracked = false where code = 'Z1';
update items set tracked = true, is_active = false where code = 'Z1';
select tt.err('FX2-G9 T5 untrack with 8 on hand refused', $$update items set tracked = false where code = 'Z2'$$, 'item_has_stock');
select tt.err('FX2-G9 T5 deactivate with 8 on hand refused', $$update items set is_active = false where code = 'Z2'$$, 'item_has_stock');
select tt.chk('FX2-G9 T5 Z2 unchanged', (select tracked and is_active from items where code = 'Z2'));
select stock_wastage(tt.iid('Z2'),1,8,'spoiled','zero it',null,null,gen_random_uuid(),null) is not null as a \gset
update items set is_active = false where code = 'Z2';
select tt.chk('FX2-G9 T5 with stock 0 the item can be deactivated', not (select is_active from items where code = 'Z2'));

\echo == T6 G8 batches: count gain, opening, negative refill (A2 h6 c2 j7)
select stock_production_in(tt.iid('G1'),1,5) is not null as a \gset
select stock_production_in(tt.iid('G2'),1,5) is not null as a \gset
select stock_count_adjust(tt.iid('G1'),1,6,'count') is not null as a \gset
select stock_count_adjust(tt.iid('G2'),1,6,'count') is not null as a \gset
select tt.chk('FX2-G8 T6 count gain +1: batches 5 + 1 = 6 = balance, the new batch has no expiry', tt.bsum('G2') = 6 and tt.qty('G2') = 6
  and (select count(*) from stock_batches where item_id = tt.iid('G2') and expires_at is null and qty_made = 1) = 1);
select stock_count_adjust(tt.iid('G2'),1,4,'count loss') is not null as a \gset
select tt.chk('FX2-G8 T6 a count LOSS of 2 takes from the batches (earliest first) and stays equal: 4 = 4', tt.bsum('G2') = 4 and tt.qty('G2') = 4);
select stock_opening(tt.iid('O1'),1,9,10) is not null as a \gset
select tt.chk('FX2-G8 T6 opening 9 gets one no-expiry batch of 9', tt.bsum('O1') = 9 and (select count(*) from stock_batches where item_id = tt.iid('O1')) = 1);
select stock_opening(tt.iid('O2'),1,9,10) is not null as a \gset
-- negative refill: balance -2 then production 10
select tt.sale(1,'R1',2) is not null as a \gset
select tt.sale(1,'R2',2) is not null as a \gset
select tt.chk('FX2-G8 T6 setup: both refill items at -2 (warn mode)', tt.qty('R1') = -2 and tt.qty('R2') = -2);
select stock_production_in(tt.iid('R1'),1,10) is not null as a \gset
select stock_production_in(tt.iid('R2'),1,10) is not null as a \gset
select tt.chk('FX2-G8 T6 production 10 into -2: balance 8, batch 8', tt.qty('R2') = 8 and tt.bsum('R2') = 8 and (select qty_made from stock_batches where item_id = tt.iid('R2')) = 10);
select tt.sale(1,'R2',8) is not null as a \gset
select tt.chk('FX2-G8 T6 selling the 8 empties both: balance 0, batches 0', tt.qty('R2') = 0 and tt.bsum('R2') = 0);

\echo == T7 batch table equals balance for every item after the scenarios (A2 h6 / j7 / x1 / l3)
select tt.chk('FX2-G8 T7 stock_batch_reconcile lists no item (G1 G2 O1 O2 R1 R2: batches = balance)', not exists (select 1 from stock_batch_reconcile(false) r where r.item_id in (tt.iid('G1'),tt.iid('G2'),tt.iid('O1'),tt.iid('O2'),tt.iid('R1'),tt.iid('R2'))));
select tt.chk('FX2-G8 T7 stock_reconcile (ledger vs balance): 0 differences', (select count(*) = 0 from stock_reconcile(false)));
