\echo == A2 20 production, transfers, count, wastage
\echo -- (f) production at the right unit, actual yield
select tt.as(:'o');
select (recipe_save(null, tt.iid('F-CAKE'), 10, 'kg', 'a2 cake', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select (recipe_save(null, tt.iid('F-SWPC'), 40, 'pc', 'a2 sweet pc', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',1,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc2 \gset
select tt.as(:'ap');
select recipe_approve(:'rc'::uuid,'ok') is not null as a1 \gset
select recipe_approve(:'rc2'::uuid,'ok') is not null as a2 \gset
select tt.as(:'o');
select production_post(1, :'rc'::uuid, 2, gen_random_uuid()) as p1 \gset
select tt.eq('f1 cake +2 batches x 10 kg', 20, tt.qty('F-CAKE',1));
select tt.eq('f1 flour 100 - 12', 88, tt.qty('RM-F',1));
select tt.eq('f1 sugar 100 - 6', 94, tt.qty('RM-S',1));
select tt.eq('f1 unit cost (12 x 40 + 6 x 50) / 20 = 39', 39, tt.avg('F-CAKE',1), 0.0005);
select tt.eq('f1 other location untouched', 0, tt.qty('F-CAKE',2));
select tt.eq('f1 batch qty_made = qty_remaining = 20', 20, (select qty_remaining from stock_batches where id=(:'p1'::jsonb->>'batch_id')::bigint));
select production_post(1, :'rc'::uuid, 2, gen_random_uuid(), now(), 'actual yield test', 18.5) as p2 \gset
select tt.eq('f2 actual yield 18.5 booked (not recipe 20): 20 + 18.5', 38.5, tt.qty('F-CAKE',1));
select tt.eq('f2 ingredients still taken at recipe quantity: flour 88 - 12', 76, tt.qty('RM-F',1));
select tt.eq('f2 yield_var_pct (18.5-20)/20 = -7.5', -7.5, (select yield_var_pct from production_runs where id=(:'p2'::jsonb->>'run_id')::uuid));
select tt.eq('f2 unit cost of the run 780 / 18.5', 42.162162, (select unit_cost from production_runs where id=(:'p2'::jsonb->>'run_id')::uuid), 0.0005);
select production_post(1, :'rc2'::uuid, 3, gen_random_uuid()) as p3 \gset
select tt.eq('f3 recipe yield in PC: 3 batches x 40 pc x 0.05 kg = 6 kg stock', 6, tt.qty('F-SWPC',1));
select tt.eq('f3 flour 76 - 3', 73, tt.qty('RM-F',1));
select tt.as(:'sp');
select tt.sale(1,'F-SWPC',20) is not null as sp1 \gset
select tt.eq('f3 sell 20 pc = 1 kg: 6 - 1', 5, tt.qty('F-SWPC',1));
select tt.as(:'o');
select tt.sale(1,'F-CAKE',5) is not null as sc1 \gset
select tt.err('f4 production_void of run 1 refused after part of its batch was sold (FIFO sold run 1 first)', format($$select production_void('%s'::uuid,'a2 void')$$, :'p1'::jsonb->>'run_id'), 'batch_partly_used');
select production_void((:'p2'::jsonb->>'run_id')::uuid,'a2 void unsold run') as pv \gset
select tt.eq('f4 void of unsold run: cake 38.5 - 5 - 18.5', 15, tt.qty('F-CAKE',1));
select tt.eq('f4 void gives ingredients back: flour 73 + 12', 85, tt.qty('RM-F',1));
select tt.eq('f4 void gives ingredients back: sugar 88 + 6', 94, tt.qty('RM-S',1));

\echo -- (g) transfers
select tt.as(:'o');
select stock_transfer(1,2,tt.iid('T-1'),8) as t1 \gset
select (:'t1'::jsonb->>'id')::uuid as tid1 \gset
select tt.eq('g1 sent: loc1 20-8', 12, tt.qty('T-1',1));
select tt.eq('g1 sent: loc2 not yet credited', 0, tt.qty('T-1',2));
select tt.eq('g1 in-transit view shows 8', 8, (select coalesce(sum(qty),0) from stock_in_transit(null) where item_id=tt.iid('T-1')));
select stock_receive_transfer(:'tid1'::uuid, 6, 'short 2') as r1 \gset
select tt.eq('g2 received 6 of 8: loc2', 6, tt.qty('T-1',2));
select tt.eq('g2 in-transit view now empty (status received)', 0, (select coalesce(sum(qty),0) from stock_in_transit(null) where item_id=tt.iid('T-1')));
select tt.eq('g2 all-location stock = 12 + 6 = 18 (2 kg are in nobody''s balance)', 18, tt.qty('T-1',1)+tt.qty('T-1',2));
select tt.eq('g2 shortage listed in transit_short_open (2 kg)', 2, (select coalesce(sum((x->>'short')::numeric),0) from jsonb_array_elements(transit_short_open(null)) x where x->>'item_id'=tt.iid('T-1')::text));
select tt.eq('g2 transit_short exception raised', 1, tt.exc('transit_short'));
select transit_short_resolve(:'tid1'::uuid, 'lost, written off') is not null as tsr \gset
select tt.eq('g3 after resolve: shortage no longer listed', 0, (select count(*) from jsonb_array_elements(transit_short_open(null)) x where x->>'item_id'=tt.iid('T-1')::text));
select tt.eq('g3 write-off nets to zero at destination (6 stays)', 6, tt.qty('T-1',2));
select tt.eq('g3 ledger has a transit_loss row of -2', -2, (select qty_delta from stock_ledger where reason='transit_loss' and ref_id=:'tid1'));
select stock_receive_transfer(:'tid1'::uuid, 6, 'again') ->> 'dup' as dup1 \gset
select tt.is('g4 second receive = dup, no extra stock', 'true', :'dup1');
select tt.eq('g4 loc2 still 6', 6, tt.qty('T-1',2));
select stock_transfer(1,2,tt.iid('T-1'),3) ->> 'id' as t2 \gset
select stock_cancel_transfer(:'t2'::uuid,'a2 cancel') is not null as cx \gset
select tt.eq('g5 cancel gives the 3 kg back at the sender', 12, tt.qty('T-1',1));
select stock_transfer(1,2,tt.iid('T-1'),2) ->> 'id' as t3 \gset
select tt.err('g6 receive more than sent refused', format($$select stock_receive_transfer('%s'::uuid, 3, 'x')$$, :'t3'), 'over_received');
select stock_receive_transfer(:'t3'::uuid, null, 'full') is not null as r3 \gset
-- unit: 5 pc of an item with 1 pc = 0.2 kg
select stock_transfer(1,2,tt.iid('B-PC'),5,'pc') ->> 'qty' as bqty \gset
select tt.eq('g7 transfer in pc is stored in base unit: 5 pc = 1 kg', 1, :'bqty'::numeric);
-- transfer of more than the sender holds, default stock_negative_mode (warn)
select stock_transfer(1,2,tt.iid('T-1'),20) ->> 'status' as g8st \gset
select tt.t('g8 transfer of 20 kg from a place that holds 10 is refused (default mode warn)', :'g8st' is null, 'refused', 'accepted, status '||coalesce(:'g8st','?'));
select tt.eq('g8 sender balance after (a transfer should never take the sender below 0)', 0, greatest(-tt.qty('T-1',1),0));
-- batches travel with the goods
insert into shelf_life_rules (item_id, value, unit, active) values (tt.iid('T-B'), 4, 'days', true);
select (stock_production_in(tt.iid('T-B'),1,5,now()-interval '3 days'))->>'batch_id' as tb_o \gset
select (stock_production_in(tt.iid('T-B'),1,5,now()-interval '1 day'))->>'batch_id' as tb_y \gset
select stock_transfer(1,2,tt.iid('T-B'),7) ->> 'id' as t4 \gset
select tt.is('g9 sender batches after sending 7 (oldest first): 0,3', '0,3', tt.brem('T-B',1));
select stock_receive_transfer(:'t4'::uuid, 5, 'short 2') is not null as r4 \gset
select tt.is('g9 receiver gets ONE batch of 5 (the shortage is taken from the younger batch)', '5', tt.brem('T-B',2));
select tt.t('g9 receiver batch keeps the oldest batch expiry', (select expires_at from stock_batches where item_id=tt.iid('T-B') and location_id=2) = (select expires_at from stock_batches where id=:'tb_o'::bigint));
select tt.eq('g9 receiver batch sum = receiver balance', tt.qty('T-B',2), tt.bsum('T-B',2));

\echo -- (h) count adjustment
select stock_opening(tt.iid('F-GAIN'),1,10,10) is not null as og \gset
select stock_count_adjust(tt.iid('F-GAIN'),1,12,'a2 count gain') as c1 \gset
select tt.eq('h1 count 12 vs book 10: delta +2', 2, (:'c1'::jsonb->>'delta')::numeric);
select tt.eq('h1 balance 12', 12, tt.qty('F-GAIN',1));
select tt.eq('h1 avg cost not diluted by a gain with no cost', 10, tt.avg('F-GAIN',1));
select stock_count_adjust(tt.iid('F-GAIN'),1,12,'a2 count again') ->> 'delta' as c2 \gset
select tt.eq('h2 same count again: delta 0, no ledger row', 0, :'c2'::numeric);
select tt.eq('h3 count variance exception by default (count_tolerance_pct unset)', 0, tt.exc('stock_count_variance'));
select stock_count_adjust(tt.iid('B-PC'),1,10,'a2 count in pc','pc') ->> 'qty' as c3 \gset
select tt.eq('h4 count entered as 10 pc = 2 kg base', 2, :'c3'::numeric);
select tt.eq('h4 balance 2 kg', 2, tt.qty('B-PC',1));
select stock_count_adjust(tt.iid('F-BATCH'),1,13,'a2 count loss on batch item') ->> 'delta' as c4 \gset
select tt.is('h5 loss of 2 taken from batches in FEFO order (youngest 5, oldest 3, middle 5)', '5,3,5', tt.brem('F-BATCH',1));
select stock_count_adjust(tt.iid('F-BATCH'),1,14,'a2 count gain on batch item') ->> 'delta' as c5 \gset
select tt.eq('h6 gain of 1 on a batch item: balance', 14, tt.qty('F-BATCH',1));
select tt.t('h6 gain creates no batch: sum(batch remaining) = balance', tt.bsum('F-BATCH',1) = tt.qty('F-BATCH',1), 'equal', 'batches '||tt.bsum('F-BATCH',1)||' vs balance '||tt.qty('F-BATCH',1));

\echo -- wastage
select stock_wastage(tt.iid('F-BATCH'),1,1,'spoiled','a2 waste',null,null,gen_random_uuid(),(select id from stock_batches where item_id=tt.iid('F-BATCH') and location_id=1 order by id limit 1)) as w1 \gset
select tt.eq('w1 wastage 1 kg from the named batch: balance 14 - 1', 13, tt.qty('F-BATCH',1));
select tt.is('w1 named batch 5 -> 4 (others 3,5)', '4,3,5', tt.brem('F-BATCH',1));
select stock_wastage(tt.iid('B-PC'),1,5,'spoiled','5 pc',null,'pc') is not null as w2 \gset
select tt.eq('w2 5 pc = 1 kg out: 2 - 1', 1, tt.qty('B-PC',1));
