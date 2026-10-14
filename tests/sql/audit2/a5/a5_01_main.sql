-- A5 audit: factory -> branch reconciliation. MAIN SCENARIO (hand-computed expectations are in the comments, written BEFORE the first run).
-- Run:  bash tests/sql/audit2/a5/run.sh <db>   (db built by tests/sql/final_build.sh). Test data only, no person names.
-- Locations: 1 = factory/main centre, 2 = branch A, 3 = branch B, 4 = outsider branch.
-- Cost: flour 100@40, sugar 100@50. Recipe 10 kg sweet = 5 flour (200) + 3 sugar (150) = 350  => 35/kg. 10 batches = 100 kg = 3500.
-- Send 60 -> A (2100 at cost), 30 -> B (1050). Factory keeps 10 (350). A receives 58 (2030), short 2 kg (70). B receives 30 (1050).
-- A sells 40 @400 = 16000 (COGS 1400), returns 3 to factory (105), wastes 2 (70).  B sells 25 @400 = 10000 (COGS 875).
-- Expected qty: A 58-40-3-2=13, B 30-25=5, factory 100-60-30+3=13, company 31, in transit 0.  (100 made - 65 sold - 2 short - 2 waste = 31)
-- Expected value @35: A 455, B 175, factory 455. Clearing 1230 by place (Dr+): factory +3045 (3150 out - 105 back), A -1995 (2030 in + 70 loss - 105 back), B -1050, sum 0.
-- Expected profit: A 16000-1400-70(waste)-70(transit loss at receiver) = 14460 ; B 10000-875 = 9125.
\set o  '00000000-0000-0000-0000-000000000001'
\set fm '00000000-0000-0000-0000-000000000003'
\set ma '00000000-0000-0000-0000-000000000011'
\set mb '00000000-0000-0000-0000-000000000012'
\set mx '00000000-0000-0000-0000-000000000013'
\set ap '00000000-0000-0000-0000-000000000008'
\echo == S0 setup
insert into auth.users (id,email,raw_user_meta_data) values (:'o','o@a5.app','{"full_name":"Owner"}'),(:'fm','fm@a5.app','{"full_name":"Factory Mgr"}'),(:'ma','ma@a5.app','{"full_name":"Branch A Mgr"}'),
 (:'mb','mb@a5.app','{"full_name":"Branch B Mgr"}'),(:'mx','mx@a5.app','{"full_name":"Outsider Mgr"}'),(:'ap','ap@a5.app','{"full_name":"Approver"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge'),(:'ma','showroom_manager'),(:'mb','showroom_manager'),(:'mx','showroom_manager'),(:'ap','recipe_approver') on conflict do nothing;
insert into user_locations values (:'fm',1),(:'ma',2),(:'mb',3),(:'mx',4),(:'ap',1) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'fm'::uuid,'view_cost') is null as g1 \gset
select set_user_grant(:'ma'::uuid,'view_cost') is null as g2 \gset
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('A5-F','Flour','Flour','kg','kg','raw_material',true,0,false),('A5-S','Sugar','Sugar','kg','kg','raw_material',true,0,false),
 ('A5-SW','Sweet','Sweet','kg','kg','finished_good',true,400,true),('A5-Y','Ladoo','Ladoo','kg','kg','finished_good',true,300,true) on conflict do nothing;
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select stock_opening(tt.iid('A5-F'),1,100,40) is not null as a1 \gset
select stock_opening(tt.iid('A5-S'),1,100,50) is not null as a2 \gset
select acct_opening('[{"code":"1110","debit":20000,"location_id":1},{"code":"1320","debit":9000,"location_id":1},{"code":"3100","credit":29000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as r1 \gset
select set_rule('acct_transfer_mode','"location_tagged"') is null as r2 \gset
select set_rule('acct_transit_loss','true') is null as r3 \gset
select loc_cost_cfg_set(1,'recipe') is null as lc \gset
select (recipe_save(null, tt.iid('A5-SW'), 10, 'kg', 'sweet v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('A5-F'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('A5-S'),'qty',3,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select tt.as(:'ap'); select recipe_approve(:'rc'::uuid,'ok') is not null as rap \gset
select tt.as(:'fm');
select production_post(1, :'rc'::uuid, 10, gen_random_uuid()) as pj \gset
select tt.eq('P1 factory qty after production = 100', 100, tt.qty('A5-SW',1));
select tt.eq('P2 factory avg cost = 35 (3500/100)', 35, tt.avg('A5-SW',1));
select tt.eq('P3 batches created at the factory for the output (count>=1)', 1, (select least(1,count(*)) from stock_batches where item_id=tt.iid('A5-SW') and location_id=1)::numeric);

\echo == M1 send 60 -> A, 30 -> B
select (stock_transfer(1,2,tt.iid('A5-SW'),60,null,'to A',gen_random_uuid())->>'id')::uuid as ta \gset
select (stock_transfer(1,3,tt.iid('A5-SW'),30,null,'to B',gen_random_uuid())->>'id')::uuid as tb \gset
select tt.eq('M1 factory after send = 10', 10, tt.qty('A5-SW',1));
select tt.eq('M2 A has nothing yet (goods in transit, not at A)', 0, tt.qty('A5-SW',2));
select tt.eq('M3 in-transit total = 90', 90, (select coalesce(sum(qty),0) from stock_in_transit()));
select tt.eq('M4 ledger transfer_out unit_cost at send = 35', 35, (select unit_cost from stock_ledger where ref_id=:'ta' and reason='transfer_out' limit 1));
select tt.as(:'o'); select acct_post_pending(false) as pp0 \gset
select tt.eq('G1 after send, clearing 1230 at factory = Dr 3150', 3150, tt.bal_loc('1230',1));

\echo == M2 receive: A 58 (short 2), B 30
select tt.as(:'ma');
select stock_receive_transfer(:'ta'::uuid, 58, 'two kg missing') as ra \gset
select tt.as(:'mb');
select stock_receive_transfer(:'tb'::uuid, 30, 'ok') as rb \gset
select tt.eq('M5 A qty after receive 58', 58, tt.qty('A5-SW',2));
select tt.eq('M6 B qty after receive 30', 30, tt.qty('A5-SW',3));
select tt.eq('M7 A avg cost carried = 35', 35, tt.avg('A5-SW',2));
select tt.eq('M8 short returned by receive = 2', 2, (:'ra'::jsonb->>'short')::numeric);
select tt.eq('M9 in-transit now 0', 0, (select coalesce(sum(qty),0) from stock_in_transit()));
select tt.t('M10 yellow exception transit_short raised at A', exists (select 1 from exceptions where flag_code='transit_short' and location_id=2));
select tt.as(:'o');
select tt.eq('M11 transit_short_open lists 1 short row = 2 kg', 2, (select coalesce(sum((x->>'short')::numeric),0) from jsonb_array_elements(transit_short_open(null)) x));
select tt.eq('M12 transit_short_open value = 2 x 35 = 70', 70, (select coalesce(sum((x->>'value')::numeric),0) from jsonb_array_elements(transit_short_open(null)) x));

\echo == M3 A sells 40, returns 3 to factory, wastes 2; B sells 25
select tt.as(:'ma');
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":40,"price":400}]',tt.iid('A5-SW'))::jsonb,0,'[{"mode":"cash","amount":16000}]',null,null,'retail',null,false) is not null as sa \gset
select (stock_transfer(2,1,tt.iid('A5-SW'),3,null,'return to factory',gen_random_uuid())->>'id')::uuid as tr \gset
select stock_wastage(tt.iid('A5-SW'),2,2,'spoiled','branch waste') is not null as wa \gset
select tt.as(:'fm'); select stock_receive_transfer(:'tr'::uuid) as rr \gset
select tt.as(:'mb');
select record_sale2(gen_random_uuid(),3,format('[{"item_id":"%s","qty":25,"price":400}]',tt.iid('A5-SW'))::jsonb,0,'[{"mode":"cash","amount":10000}]',null,null,'retail',null,false) is not null as sb \gset
select tt.eq('Q1 A remaining 13', 13, tt.qty('A5-SW',2));
select tt.eq('Q2 B remaining 5', 5, tt.qty('A5-SW',3));
select tt.eq('Q3 factory remaining 13 (10 + 3 returned)', 13, tt.qty('A5-SW',1));
select tt.eq('Q4 company total 31', 31, tt.qty('A5-SW',1)+tt.qty('A5-SW',2)+tt.qty('A5-SW',3));
select tt.eq('Q5 company: made 100 - sold 65 - short 2 - waste 2 = 31', 31, 100-65-2-2);
select tt.as(:'o'); select acct_post_pending(false) as pp1 \gset
select tt.eq('G2 clearing 1230 at factory = Dr 3045', 3045, tt.bal_loc('1230',1));
select tt.eq('G3 clearing 1230 at A = Cr 1995', -1995, tt.bal_loc('1230',2));
select tt.eq('G4 clearing 1230 at B = Cr 1050', -1050, tt.bal_loc('1230',3));
select tt.eq('G5 clearing 1230 company-wide = 0', 0, tt.bal('1230'));
select tt.eq('G6 transit loss 5130 = Dr 70', 70, tt.bal('5130'));
select tt.eq('G7 transit loss booked at the receiving branch A (loc 2)', 70, tt.bal_loc('5130',2));
select tt.eq('G8 unbalanced entries = 0', 0, tt.unbalanced());
select inventory_vs_gl(null,null) as ivg \gset
\echo INVENTORY_VS_GL: :ivg
select tt.as(:'o');
select acct_income_statement(tt.today(),tt.today(),2) as isa \gset
select acct_income_statement(tt.today(),tt.today(),3) as isb \gset
\echo IS_A: :isa
\echo IS_B: :isb
