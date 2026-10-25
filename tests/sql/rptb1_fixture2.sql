-- RPT-B1 fixture, second part (phases 401 and 402): production, costing, wastage. Runs after tests/sql/rptb1_fixture.sql. Test data only (test_* names).
-- Hand-computed numbers (place 1, today unless said otherwise):
--   raw material test_raw: 200 kg opening at 20 = 4000. Recipe: 5 kg raw -> 10 pieces of test_fin (one batch). Material 5 x 20 = 100 per batch.
--   run 1: 1 batch, no actual yield typed   -> 10 pieces at 10 each (100 / 10); location method OFF, so no conversion cost
--   run 2: 1 batch, actual yield typed = 8  -> 8 pieces at 12.5 each (100 / 8); yield variance -20 %
--   sale: 4 x test_fin at 100 = 400 (ledger cost 10 each = 40; the price list item_costs has NO row for test_fin)
--   wastage: 3 kg raw at 20 = 60 (left out of the profit while profit_one_number_on is off)
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000400'
select set_config('request.jwt.claim.sub', :'o', false);
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category) values
 ('RB1-RM','test_raw','test_raw','kg','kg',0,true,'raw_material','test_cat_raw'),
 ('RB1-FG','test_fin','test_fin','piece','piece',100,true,'finished_good','test_cat_one');
select id as i_rm from items where code='RB1-RM' \gset
select id as i_fg from items where code='RB1-FG' \gset
select stock_opening(:'i_rm'::uuid,1,200,20) is not null as w_o4 \gset
select (recipe_save(null, :'i_fg'::uuid, 10, null, 'rb1 v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'i_rm','qty',5,'waste_pct',0)))->>'id')::uuid as rc \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid()) ->> 'run_id' as run1 \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, null, 8::numeric) ->> 'run_id' as run2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":100}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":400}]','','','retail',null,false)->>'id' as s6 \gset
select stock_wastage(:'i_rm'::uuid,1,3,'spoiled','test') ->> 'id' as w_waste \gset
select :'run1' as run1, :'run2' as run2;
