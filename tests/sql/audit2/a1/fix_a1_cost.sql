-- A1 FIX probes (gap closure by phase116, written after the fixes).  Self-contained scenario = the A1 audit numbers
-- (same items / purchase / recipe as the phase116 test, hand-computed numbers in the HAND comments).  Run in its OWN session on a clone of
-- the template DB.  The batch switches are NOT set here: the probes use whatever the DB has (defaults = OFF -> FAIL = gap open by default;
-- switches_on.txt = ON -> PASS = closed).  Labels start FX1-<gap>.  Derived from supabase/phase116_test.sql T1,T3..T8.
\i tests/sql/e2e/00_common.sql
\echo == T0 shape, defaults, tags
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@b3.app','{"full_name":"Owner"}'),(:'fm','maker@b3.app','{"full_name":"Maker"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge') on conflict do nothing;
insert into user_locations values (:'fm',1) on conflict do nothing;
select tt.as(:'o');
\echo == T1 setup (items, purchases) - same prices as the A1 audit
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false),('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false),('RM-B','Butter','Butter','kg','kg','raw_material',true,0,false),
 ('RM-M','Milk','Milk','ltr','ltr','raw_material',true,0,false),('RM-O','Oil','Oil','kg','kg','raw_material',true,0,false),
 ('RM-NC','Uncosted rm','Uncosted rm','kg','kg','raw_material',true,0,false),('RM-NC2','Uncosted rm 2','Uncosted rm 2','kg','kg','raw_material',true,0,false),
 ('FG-NC','Uncosted fg','Uncosted fg','kg','kg','finished_good',true,0,false),('FG-NC2','Uncosted fg 2','Uncosted fg 2','kg','kg','finished_good',true,0,false),
 ('PK-B','Box','Box','pc','pc','packaging',true,0,false),('PK-P','Pouch','Pouch','pc','pc','packaging',true,0,false),
 ('FG-CAKE','Cake','Cake','kg','kg','finished_good',true,300,true),('FG-SW','Sweet','Sweet','kg','kg','finished_good',true,400,true),('FG-CHH','Chhana','Chhana','kg','kg','finished_good',true,0,false),
 ('FG-PC','Piece item','Piece item','pc','pc','finished_good',true,10,true),('FG-OIL','Oil product','Oil product','kg','kg','finished_good',true,100,true) on conflict do nothing;
select acct_set_start(tt.today()-100)->>'start' as sd \gset
select acct_opening('[{"code":"1110","debit":100000,"location_id":1},{"code":"3100","credit":100000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a1 \gset
select set_rule('accounting_autopost','true') is null as a2 \gset
with s as (insert into suppliers (name, credit_days) values ('Sup Main', null) returning id) select id as s1 from s \gset
-- HAND: flour 100@40, sugar 50@60, butter 20@500, box 200@3, milk 200@80, pouch 300@1, oil 100@40
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'B3',tt.today()-12,format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":40},{"item_id":"%s","qty":50,"unit":"kg","unit_cost":60},{"item_id":"%s","qty":20,"unit":"kg","unit_cost":500},{"item_id":"%s","qty":200,"unit":"pc","unit_cost":3},{"item_id":"%s","qty":200,"unit":"ltr","unit_cost":80},{"item_id":"%s","qty":300,"unit":"pc","unit_cost":1},{"item_id":"%s","qty":100,"unit":"kg","unit_cost":40}]',tt.iid('RM-F'),tt.iid('RM-S'),tt.iid('RM-B'),tt.iid('PK-B'),tt.iid('RM-M'),tt.iid('PK-P'),tt.iid('RM-O'))::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select tt.eq('T1 purchase total 4000+3000+10000+600+16000+300+4000', 37900, (select total from purchase_bills where id=:'b1'::uuid));
select acct_post_pending(false) as pp0 \gset
select set_user_grant(:'o'::uuid,'view_cost') is null as g0 \gset

\echo == T2 defaults OFF = today: semi-finished refused, std_cost as before, packaging on planned yield
select loc_cost_cfg_set(1,'recipe') is null as lc \gset
select (recipe_save(null, tt.iid('FG-CAKE'), 10, 'kg', 'cake v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',10),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-B'),'qty',2,'unit','kg','waste_pct',5),
  jsonb_build_object('ingredient_item_id',tt.iid('PK-B'),'qty',2,'unit','pc','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select recipe_cost_component_set(:'rc'::uuid,'labour','per_labour_hour',50,2,null,'2h x 50',gen_random_uuid()) is not null as c1 \gset
select recipe_cost_component_set(:'rc'::uuid,'gas','per_unit',2,null,null,'gas per kg',gen_random_uuid()) is not null as c2 \gset
select recipe_approve(:'rc'::uuid,'ok') is not null as ap \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, 'switches off', null) as pj0 \gset
-- HAND (A1 s1): 1 batch full yield: material 1500, conversion 100 + 2 x 10 = 120, unit 162; std_cost (old formula) 162

\echo == T3 standard vs actual: yield loss in money (A1 a8), price / usage / conversion variance
-- HAND: snapshot per batch material 1500, conversion 120, yield 10 -> standard unit 162.
-- run 2 batches actual 18.5: material 3000 (528+360+2100+12), conversion 200 + 2 x 18.5 = 237 -> 3237 ; unit 3237/18.5 = 174.973
--   yield loss money = 3237 x (1 - 18.5/20) = 242.775 -> 242.78
--   standard of the output = 162 x 18.5 = 2997 (material 2775 + conversion 222) ; total variance 3237 - 2997 = 240 = price 0 + usage 225 (3000 - 2775) + conversion 15 (237 - 222)
select production_post(1, :'rc'::uuid, 2, gen_random_uuid(), null, 'two batches short', 18.5) as pj \gset
select (:'pj'::jsonb->>'run_id')::uuid as run1 \gset
select tt.eq('FX1-G8 T3 run unit cost 174.973', 174.973, (select unit_cost from production_runs where id=:'run1'::uuid), 0.0005);
select tt.eq('FX1-G8 T3 cost_full_yield116 keeps the old number', 161.85, (select cost_full_yield116 from production_runs where id=:'run1'::uuid), 0.0005);
select tt.eq('FX1-G8 T3 std_unit_cost116 = true standard 162', 162, (select std_unit_cost116 from production_runs where id=:'run1'::uuid), 0.0005);
select (select r from jsonb_array_elements(production_run_costs(1, tt.today()-1, tt.today()+1)) r where r->>'run_id' = :'run1') as prc \gset
select tt.eq('FX1-G8 T3 run-costs report: yield_loss_money', 242.78, (:'prc'::jsonb->>'yield_loss_money')::numeric);
select production_variance116(1, tt.today()-1, tt.today()+1) as pv \gset
select (select r from jsonb_array_elements(:'pv'::jsonb->'rows') r where r->>'run_id' = :'run1') as pvr \gset
select tt.eq('FX1-G8 T3 variance: actual total', 3237, (:'pvr'::jsonb->>'actual_total')::numeric);
select tt.eq('FX1-G8 T3 variance: standard total of the output', 2997, (:'pvr'::jsonb->>'standard_total')::numeric);
select tt.eq('FX1-G8 T3 variance: price_var', 0, (:'pvr'::jsonb->>'price_var')::numeric);
select tt.eq('FX1-G8 T3 variance: usage_var (includes the yield loss at standard price)', 225, (:'pvr'::jsonb->>'usage_var')::numeric);
select tt.eq('FX1-G8 T3 variance: conv_var', 15, (:'pvr'::jsonb->>'conv_var')::numeric);
select tt.eq('FX1-G8 T3 variance: total_var = parts', 240, (:'pvr'::jsonb->>'total_var')::numeric);
select tt.eq('FX1-G8 T3 variance: yield_loss_money 242.78', 242.78, (:'pvr'::jsonb->>'yield_loss_money')::numeric);
-- price variance: flour 50 kg @52 -> average (86.8 x 40 + 50 x 52)/136.8 = 44.385965 (stock after run 1: flour 100 - 6 x 1.1 x 2 = 86.8 ; the first full-yield run above used 6.6 -> 80.2)
select tt.eq('FX1-G8 T3 flour left before the second purchase (100 - 6.6 - 13.2)', 80.2, tt.qty('RM-F'));
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'B3b',tt.today()-1,format('[{"item_id":"%s","qty":50,"unit":"kg","unit_cost":52}]',tt.iid('RM-F'))::jsonb)->>'id' as b2 \gset
select post_purchase(:'b2'::uuid) is not null as pb2 \gset
-- HAND: new flour average = (80.2 x 40 + 50 x 52) / 130.2 = (3208 + 2600) / 130.2 = 44.608295 ; 1 batch full yield: flour 6.6 x 44.608295 = 294.4147 ; price_var = 6.6 x (44.608295 - 40) = 30.4147 -> 30.41 ; usage 0 ; conv 120 vs 120 = 0
select tt.eq('FX1-G8 T3 new flour average', 44.608295, tt.avg('RM-F'), 0.00001);
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, 'price moved', null) as pjp \gset
select production_variance116(1, tt.today()-1, tt.today()+1) as pv2 \gset
select (select r from jsonb_array_elements(:'pv2'::jsonb->'rows') r where r->>'run_id' = :'pjp'::jsonb->>'run_id') as pvr2 \gset
select tt.eq('FX1-G8 T3 price variance of the flour price move', 30.41, (:'pvr2'::jsonb->>'price_var')::numeric);
select tt.eq('FX1-G8 T3 usage variance 0 at full yield', 0, (:'pvr2'::jsonb->>'usage_var')::numeric);
select tt.eq('FX1-G8 T3 total variance = price variance', 30.41, (:'pvr2'::jsonb->>'total_var')::numeric);
-- std_cost_true116 on: the next run stores the standard in std_cost
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, 'true std', null) as pjt \gset
select tt.eq('FX1-G8 T3 std_cost_true116: std_cost = 162 (stored standard), not the actual-cost number', 162, (select std_cost from production_runs where id=(:'pjt'::jsonb->>'run_id')::uuid), 0.0005);
select tt.t('FX1-G8 T3 actual cost per unit moved (flour dearer) but std_cost did not', (select unit_cost > 162 from production_runs where id=(:'pjt'::jsonb->>'run_id')::uuid));
select tt.err('FX1-G8 T3 variance report needs the cost right', format($$select tt.as('%s'); select production_variance116(1, null, null)$$, :'fm'), 'not allowed');
select tt.as(:'o');

\echo == T4 semi-finished goods as an ingredient (A1 c1/c2, G1)
select loc_cost_cfg_set(1,'off') is null as lc0 \gset
select (recipe_save(null, tt.iid('FG-CHH'), 3, 'kg', 'chhana v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',tt.iid('RM-M'),'qty',20,'unit','ltr','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rch \gset
select recipe_approve(:'rch'::uuid,'ok') is not null as apc \gset
-- HAND: 20 ltr x 80 = 1600 -> 3 kg -> 533.333333 per kg
select production_post(1, :'rch'::uuid, 1, gen_random_uuid(), null, 'chhana', null) as ppc \gset
select tt.eq('FX1-G1 T4 chhana unit cost 1600/3', 533.333333, tt.avg('FG-CHH'), 0.0000005);
-- sweet = 2 kg chhana + 1 kg sugar -> 3 kg. HAND: 2 x 533.333333 = 1066.666667 + 60 = 1126.666667 -> 375.555556 per kg
select (recipe_save(null, tt.iid('FG-SW'), 3, 'kg', 'sweet from chhana', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('FG-CHH'),'qty',2,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',1,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rsw \gset
select recipe_approve(:'rsw'::uuid,'ok') is not null as aps \gset
select recipe_stage_cost116(:'rsw'::uuid, 1) as stg \gset
select tt.err('FX1-G1 T4 a recipe that closes a circle is refused (chhana made from the sweet)', format($$select recipe_save(null,'%s',3,'kg','loop','[{"ingredient_item_id":"%s","qty":1,"unit":"kg","waste_pct":0}]'::jsonb,gen_random_uuid())$$, tt.iid('FG-CHH'), tt.iid('FG-SW')), 'recipe_cycle');
select production_post(1, :'rsw'::uuid, 1, gen_random_uuid(), null, 'sweet', null) as pps \gset
select tt.eq('FX1-G1 T4 chhana consumed: 3 - 2 left', 1, tt.qty('FG-CHH'));
select tt.eq('FX1-G1 T4 sweet unit cost', 375.555556, (select unit_cost from production_runs where id=(:'pps'::jsonb->>'run_id')::uuid), 0.000002);
select acct_post_pending(false) as ppx \gset
select tt.eq('FX1-G1 T4 journal unbalanced entries', 0, tt.unbalanced());
select tt.eq('FX1-G1 T4 inventory vs GL: unexplained', 0, (inventory_vs_gl(tt.today(),1)->'total'->>'unexplained')::numeric, 0.05);
select tt.eq('FX1-G1 T4 inventory vs GL: diff', 0, (inventory_vs_gl(tt.today(),1)->'total'->>'diff')::numeric, 0.05);

\echo == T5 packaging on the quantity really made (A1 c5, G10)
select set_rule('packaging_consume_on','"production"') is null as pc \gset
select packaging_set(tt.iid('FG-OIL'), tt.iid('PK-P'), 1, 'production') is not null as ps \gset
select (recipe_save(null, tt.iid('FG-OIL'), 10, 'kg', 'oil product', jsonb_build_array(jsonb_build_object('ingredient_item_id',tt.iid('RM-O'),'qty',10,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as roil \gset
select recipe_approve(:'roil'::uuid,'ok') is not null as apo \gset
-- HAND, switch off: 3 batches (30 kg planned), actual 27: oil 30 x 40 = 1200 ; pouches 30 x 1 ; unit (1200+30)/27 = 45.555556 ; pouches left 270
select production_post(1, :'roil'::uuid, 3, gen_random_uuid(), null, 'oil off', 27) as ppo \gset
-- HAND, switch on: pouches 27 x 1 ; oil 1200 ; unit (1200+27)/27 = 45.444444 ; pouches left 270 - 27 = 243
select production_post(1, :'roil'::uuid, 3, gen_random_uuid(), null, 'oil on', 27) as ppo2 \gset
select tt.eq('FX1-G10 T5 two runs of actual 27 kg: pouches used 27 + 27 (300 - 54 = 246; planned-yield mode would use 30 + 30 = 240)', 246, tt.qty('PK-P'));
select tt.eq('FX1-G10 T5 first run unit cost (1200+27)/27 = 45.444444 (planned-yield mode: 45.555556)', 45.444444, (select unit_cost from production_runs where id=(:'ppo'::jsonb->>'run_id')::uuid), 0.0000005);
select tt.eq('FX1-G10 T5 second run unit cost (1200+27)/27', 45.444444, (select unit_cost from production_runs where id=(:'ppo2'::jsonb->>'run_id')::uuid), 0.0000005);

\echo == T6 pool mode: piece product and the other drivers (A1 b3/b4, G5/G6)
-- pool of THIS month: labour 3000, gas 2000.  Cake (kg) at normal 1000 kg stays as today.
select loc_cost_cfg_set(1,'pool',1000) is null as lcp \gset
select pool_set(1, date_trunc('month', tt.today())::date, 'labour', 3000) is not null as pl1 \gset
select pool_set(1, date_trunc('month', tt.today())::date, 'gas', 2000) is not null as pl2 \gset
select (recipe_save(null, tt.iid('FG-PC'), 10, 'pc', 'piece v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',1,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rpc \gset
select recipe_cost_component_set(:'rpc'::uuid,'labour','per_labour_hour',1,0.5,null,'half an hour',gen_random_uuid()) is not null as hc \gset
select recipe_approve(:'rpc'::uuid,'ok') is not null as app \gset
-- HAND: switch OFF: 10 pc per batch, piece base unit -> conversion 0, flagged incomplete, unit = sugar 60 / 10 = 6.0
select production_post(1, :'rpc'::uuid, 1, gen_random_uuid(), null, 'piece off', null) as pp1 \gset
-- HAND: switch ON, place default driver batches, normal 100 batches/month: (3000 + 2000)/100 = 50 per batch ; 2 batches = 100 ; material 2 x 60 = 120 ; output 20 pc ; unit (120+100)/20 = 11
select loc_cost_driver_set116(1, 'batches', null, 100, 200) is null as ld \gset
select production_post(1, :'rpc'::uuid, 2, gen_random_uuid(), null, 'piece batches', null) as pp2 \gset
select tt.eq('FX1-G6 T6 batches driver: conversion 2 x 50 = 100', 100, (select conversion_cost from production_runs where id=(:'pp2'::jsonb->>'run_id')::uuid), 0.0005);
select tt.eq('FX1-G6 T6 batches driver: unit cost (120+100)/20', 11, (select unit_cost from production_runs where id=(:'pp2'::jsonb->>'run_id')::uuid), 0.0000005);
select tt.is('FX1-G6 T6 batches driver: conversion complete', 'true', (select conversion_complete::text from production_runs where id=(:'pp2'::jsonb->>'run_id')::uuid));
-- HAND: labour by labour hours (normal 200 h): 3000/200 = 15 per hour x 0.5 h x 2 batches = 15 ; gas by batches 2000/100 x 2 = 40 ; conversion 55 ; unit (120+55)/20 = 8.75
select cost_type_driver_set116('labour', 'labour_hours') is null as td \gset
select production_post(1, :'rpc'::uuid, 2, gen_random_uuid(), null, 'piece hours', null) as pp3 \gset
select tt.eq('FX1-G6 T6 labour hours + batches: conversion 15 + 40', 55, (select conversion_cost from production_runs where id=(:'pp3'::jsonb->>'run_id')::uuid), 0.0005);
select tt.eq('FX1-G6 T6 labour hours + batches: unit cost 8.75', 8.75, (select unit_cost from production_runs where id=(:'pp3'::jsonb->>'run_id')::uuid), 0.0000005);
-- the kg cake with the same drivers off for gas: default output_kg for types with no override and place default batches -> gas follows the PLACE default (batches). Cake 1 batch: labour 15 x 2h... see T7 for the totals; here only: kg product still works
select cost_type_driver_set116('labour', null) is null as td0 \gset
select loc_cost_driver_set116(1, null, null, null, null) is null as ld0 \gset
-- back to today's rule: with the switch off the piece product is incomplete again (no regression)
select production_post(1, :'rpc'::uuid, 1, gen_random_uuid(), null, 'piece off again', null) as pp4 \gset

\echo == T7 early-month run: provisional conversion, work queue, re-price (A1 b5, G4)
-- Place on pool mode, drivers ON with batches. The run month (last month) has NO pool; the month before has labour 3000 / 100 batches = 30 per batch.
-- HAND: provisional: 2 batches x 30 = 60 (labour only) ; material 2 x 60 = 120 ; unit (120+60)/20 = 9.0
--       real pool of the run month typed later: labour 4000 -> 40 per batch -> 80 ; delta +20 ; unit (120+80)/20 = 10.0 ; all 20 pc still on hand -> inventory +20, Cr 5950 20
select loc_cost_driver_set116(1, 'batches', null, 100, null) is null as ld2 \gset
select (date_trunc('month', tt.today()) - interval '1 month')::date as m1 \gset
select (date_trunc('month', tt.today()) - interval '2 month')::date as m2 \gset
select pool_set(1, :'m2'::date, 'labour', 3000) is not null as pm2 \gset
select (:'m1'::date + 4)::timestamptz + interval '10 hours' as made1 \gset
select production_post(1, :'rpc'::uuid, 2, gen_random_uuid(), :'made1'::timestamptz, 'early month', null) as ppe \gset
select (:'ppe'::jsonb->>'run_id')::uuid as rune \gset
select tt.eq('FX1-G4 T7 provisional conversion 2 x 30', 60, (select conversion_cost from production_runs where id=:'rune'::uuid), 0.0005);
select tt.is('FX1-G4 T7 run flagged provisional', 'true', (select conversion_provisional116::text from production_runs where id=:'rune'::uuid));
select tt.eq('FX1-G4 T7 unit cost (120+60)/20', 9, (select unit_cost from production_runs where id=:'rune'::uuid), 0.0000005);
select tt.t('FX1-G4 T7 work queue lists the run as provisional', exists (select 1 from jsonb_array_elements(production_cost_queue116(1)) q where q->>'run_id' = :'rune' and q->>'reason' = 'conversion_provisional'));
select pool_set(1, :'m1'::date, 'labour', 4000) is not null as pm1 \gset
select tt.t('FX1-G4 T7 dry re-price shows delta 20 and changes nothing', (production_reprice116(1, :'m1'::date, true)->>'total_delta')::numeric = 20 and (select conversion_cost from production_runs where id=:'rune'::uuid) = 60);
select acct_post_pending(false) as ppe1 \gset
select production_reprice116(1, :'m1'::date, false) as rep \gset
select tt.eq('FX1-G4 T7 re-priced conversion 2 x 40', 80, (select conversion_cost from production_runs where id=:'rune'::uuid), 0.0005);
select tt.eq('FX1-G4 T7 re-priced unit cost (120+80)/20', 10, (select unit_cost from production_runs where id=:'rune'::uuid), 0.0000005);
select tt.eq('FX1-G4 T7 adjustment entry: Cr 5950 20', 20, (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='prod_reprice116' and e.source_id=:'rune' and a.code='5950'));
select tt.eq('FX1-G4 T7 adjustment entry: Dr 1310 20 (all stock still on hand)', 20, (select coalesce(sum(l.debit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='prod_reprice116' and e.source_id=:'rune' and a.code='1310'));
select tt.eq('FX1-G4 T7 inventory vs GL after the re-price', 0, (inventory_vs_gl(tt.today(),1)->'total'->>'diff')::numeric, 0.05);
select tt.eq('FX1-G4 T7 stock_reconcile (ledger replay) agrees with the cached averages', 0, (select count(*) from stock_reconcile(false)));
select tt.eq('FX1-G4 T7 second call does nothing', 0, (production_reprice116(1, :'m1'::date, false)->>'runs')::numeric);
select tt.err('FX1-G4 T7 a re-priced run cannot be voided silently', format($$select production_void('%s'::uuid, 'test void')$$, :'rune'), 'run_repriced');
select loc_cost_driver_set116(1, null, null, null, null) is null as ld3 \gset

\echo == T8 unknown-cost ingredient: the supplied cost reaches the item average and the run (A1 f5, G7)
select loc_cost_cfg_set(1,'off') is null as lc8 \gset
-- OFF first (today): pair 2
select stock_opening(tt.iid('RM-NC2'),1,50,null) is not null as o2 \gset
select (recipe_save(null, tt.iid('FG-NC2'), 10, 'kg', 'nc2', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-NC2'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',5,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rnc2 \gset
select recipe_approve(:'rnc2'::uuid,'ok') is not null as apn2 \gset
select production_post(1, :'rnc2'::uuid, 1, gen_random_uuid(), null, 'uncosted 2', null) as ppn2 \gset
select cost_wait_supply96('ledger', (select x->>'ref' from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->'items'->0->>'code'='RM-NC2'), 'manual', format('[{"item_id":"%s","cost":20}]', tt.iid('RM-NC2'))::jsonb, 'supplier quote', gen_random_uuid()) as spn2 \gset
-- ON: pair 1.  HAND: the first run (made before the cost was known) booked sugar 5 x 60 = 300 only (unit NULL) ; cost supplied 20/kg ; a NEW run: 5 x 20 + 5 x 60 = 400 -> unit 40
select stock_opening(tt.iid('RM-NC'),1,50,null) is not null as o1 \gset
select (recipe_save(null, tt.iid('FG-NC'), 10, 'kg', 'nc v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-NC'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',5,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rnc \gset
select recipe_approve(:'rnc'::uuid,'ok') is not null as apn \gset
select production_post(1, :'rnc'::uuid, 1, gen_random_uuid(), null, 'uncosted', null) as ppn \gset
select (:'ppn'::jsonb->>'run_id')::uuid as runn \gset
select tt.is('FX1-G7 T8 first run: cost_complete false', 'false', (select cost_complete::text from production_runs where id=:'runn'::uuid));
select tt.t('FX1-G7 T8 first run: unit cost NULL (cost unknown)', (select unit_cost from production_runs where id=:'runn'::uuid) is null);
select tt.t('FX1-G7 T8 the run is on the cost work queue (the phase96 list drops a run once its partial entry is posted)', exists (select 1 from jsonb_array_elements(production_cost_queue116(1)) q where q->>'run_id' = :'runn' and q->>'reason' = 'ingredient_cost_unknown'));
select tt.err('FX1-G7 T8 re-cost is refused while the ingredient has no average', format($$select production_recost116('%s'::uuid, false)$$, :'runn'), 'cost_unavailable');
select cost_wait_supply96('ledger', (select x->>'ref' from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->'items'->0->>'code'='RM-NC'), 'manual', format('[{"item_id":"%s","cost":20}]', tt.iid('RM-NC'))::jsonb, 'supplier quote', gen_random_uuid()) as spn \gset
select tt.eq('FX1-G7 T8 the supplied cost reached the item average (20)', 20, tt.avg('RM-NC'));
select production_post(1, :'rnc'::uuid, 1, gen_random_uuid(), null, 'uncosted again', null) as ppn3 \gset
select tt.eq('FX1-G7 T8 a NEW run after the supply: 5 x 20 + 5 x 60 = 400 -> unit 40 (the audit hand value)', 40, (select unit_cost from production_runs where id=(:'ppn3'::jsonb->>'run_id')::uuid), 0.0005);
select tt.eq('FX1-G7 T8 new run material cost 400', 400, (select material_cost from production_runs where id=(:'ppn3'::jsonb->>'run_id')::uuid), 0.0005);
-- the OLD run (its partial entry Dr 1310 300 / Cr 1320 300, flag cogs_missing, was posted by the supply above): re-cost it. HAND: 5 x 20 + 5 x 60 = 400 -> unit 40 ; entry reversed and re-posted Dr 1310 400 / Cr 1320 400
select acct_post_pending(false) as ppz \gset
select tt.t('FX1-G7 T8 old run: partial entry is posted and flagged', exists (select 1 from journal_entries e where e.source_type='production' and e.source_id=:'runn' and e.flags like '%cogs_missing%'));
select tt.eq('FX1-G7 T8 dry run of the re-cost: material_new 400', 400, (production_recost116(:'runn'::uuid, true)->>'material_new')::numeric, 0.005);
select tt.t('FX1-G7 T8 dry run changed nothing', (select cost_complete from production_runs where id=:'runn'::uuid) is not true);
select production_recost116(:'runn'::uuid, false) as rcj \gset
select tt.eq('FX1-G7 T8 old run re-costed: material 5 x 20 + 5 x 60 = 400', 400, (select material_cost from production_runs where id=:'runn'::uuid), 0.0005);
select tt.eq('FX1-G7 T8 old run re-costed: unit cost 40', 40, (select unit_cost from production_runs where id=:'runn'::uuid), 0.0005);
select tt.is('FX1-G7 T8 old run: cost_complete', 'true', (select cost_complete::text from production_runs where id=:'runn'::uuid));
select tt.eq('FX1-G7 T8 re-posted entry: Dr 1310 400', 400, (select coalesce(sum(l.debit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='prod_recost116' and e.source_id=:'runn' and a.code='1310'));
select tt.eq('FX1-G7 T8 re-posted entry: Cr 1320 400', 400, (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='prod_recost116' and e.source_id=:'runn' and a.code='1320'));
select tt.t('FX1-G7 T8 the old partial entry is reversed', exists (select 1 from journal_entries r join journal_entries o on o.id=r.reverses_id where o.source_type='production' and o.source_id=:'runn'));
select tt.t('FX1-G7 T8 the run is off the work queue', not exists (select 1 from jsonb_array_elements(production_cost_queue116(1)) q where q->>'run_id' = :'runn'));
select tt.eq('FX1-G7 T8 second re-cost does nothing', 1, case when (production_recost116(:'runn'::uuid, false)->>'nothing_to_do')::boolean then 1 else 0 end);
select tt.eq('FX1-G7 T8 finished good average 40', 40, tt.avg('FG-NC'), 0.0005);
select acct_post_pending(false) as ppy \gset
select tt.eq('FX1-G7 T8 stock_reconcile (ledger replay) agrees with the cached averages after the supplied costs', 0, (select count(*) from stock_reconcile(false)));
select tt.eq('FX1-G7 T8 unbalanced entries', 0, tt.unbalanced());
select tt.eq('FX1-G7 T8 inventory vs GL: unexplained', 0, (inventory_vs_gl(tt.today(),1)->'total'->>'unexplained')::numeric, 0.05);

