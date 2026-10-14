\echo == 04 recipe + production
select tt.as(:'o');
select (recipe_save(null, tt.iid('FG-CAKE'), 10, 'kg', 'cake v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',10),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('PK-B'),'qty',2,'unit','pc','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-W'),'qty',5,'unit','ltr','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select tt.t('R0 recipe saved', :'rc' is not null);
select loc_cost_cfg_set(1,'recipe') is null as lc \gset
select recipe_cost_component_set(:'rc'::uuid,'labour','per_batch',100,null,null,'labour',gen_random_uuid()) is not null as cc \gset
select recipe_cost(:'rc'::uuid,1) as rcj \gset
select tt.eq('R1 recipe_cost sum of line_cost (282.04 + 189 + 6.30 + water 0 flagged free) = 477.34', 477.34, (select sum((x->>'line_cost')::numeric) from jsonb_array_elements(:'rcj'::jsonb->'lines') x));
select tt.eq('R1 recipe_cost raw row (all ingredient lines incl. box line = 477.34) [water is flagged free]', 477.34, (select (x->>'amount')::numeric from jsonb_array_elements(:'rcj'::jsonb->'rows') x where x->>'row'='raw'));
select tt.eq('R1 recipe_cost conversion 100', 100, (select (x->>'amount')::numeric from jsonb_array_elements(:'rcj'::jsonb->'rows') x where x->>'row'='conversion'));
select tt.eq('R1 recipe_cost unit cost = (477.34+100)/10 = 57.734', 57.734, (:'rcj'::jsonb->>'unit_cost')::numeric, 0.0005);
\echo RECIPE_COST_ROWS: :rcj
-- approval (rec mode: warn; def: off) - approve by a different person in both modes
select tt.as(:'ap');
select recipe_approve(:'rc'::uuid,'ok') is not null as rap \gset
select tt.as(:'o');
-- production without enough stock check not needed. Run 2 batches => 20 kg
select production_post(1, :'rc'::uuid, 2, gen_random_uuid()) as pj \gset
select tt.eq('R2 production yield 20 kg', 20, (:'pj'::jsonb->>'qty')::numeric);
select tt.eq('R2 flour left 300-13.2', 286.8, tt.qty('RM-F'));
select tt.eq('R2 sugar left 100-6', 94, tt.qty('RM-S'));
select tt.eq('R2 box left 500-4', 496, tt.qty('PK-B'));
select tt.eq('R2 water left 100-10', 90, tt.qty('RM-W'));
select tt.eq('R2 cake qty', 20, tt.qty('FG-CAKE'));
select tt.eq('R2 FG cost = (raw 942.08 + box 12.60 + conversion 200)/20 = 57.734', 57.734, tt.avg('FG-CAKE'), 0.0005);
select tt.eq('R2 production_runs material_cost 954.68', 954.68, (select material_cost from production_runs where recipe_id=:'rc'::uuid));
select tt.eq('R2 production_runs conversion_cost 200', 200, (select conversion_cost from production_runs where recipe_id=:'rc'::uuid));
select tt.eq('R2 recipe_cost unit cost == posted unit cost', (:'rcj'::jsonb->>'unit_cost')::numeric, (select unit_cost from production_runs where recipe_id=:'rc'::uuid), 0.0005);

\echo -- free-cost item flag with production_requires_cost=refuse
select set_rule('production_requires_cost','"refuse"') is null as prc \gset
select item_cost_free_set(tt.iid('RM-W'), false, 'test', gen_random_uuid()) is not null as unf \gset
select tt.err('F1 refuse + water NOT flagged free (cost 0) -> production refused', format($$select production_post(1,'%s',1,gen_random_uuid())$$, :'rc'), 'cost_missing');
select item_cost_free_set(tt.iid('RM-W'), true, 'tap water, really free', gen_random_uuid()) is not null as fr \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid()) as pj2 \gset
select tt.eq('F1 flagged free -> production allowed; unit cost still 57.734', 57.734, (select unit_cost from production_runs where id=(:'pj2'::jsonb->>'run_id')::uuid), 0.0005);
select tt.eq('F1 cake qty 30', 30, tt.qty('FG-CAKE'));

\echo -- production without recipe
select stock_production_in(tt.iid('FG-NOREC'),1,5,now(),null,'manual test no cost',gen_random_uuid(),null) as spi \gset
select tt.t('N1 direct production-in works while production_requires_recipe is off (default)', :'spi' is not null, 'allowed', left(:'spi',40));
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('FG-NOREC2','Biscuit','Biscuit','kg','kg','finished_good',true,200,true) on conflict do nothing;
select stock_production_in(tt.iid('FG-NOREC2'),1,3,now(),null,'manual typed cost',gen_random_uuid(),80) as spi2 \gset
select tt.eq('N1 biscuit typed cost 3 kg x 80: stock value 240', 240, tt.qty('FG-NOREC2')*tt.avg('FG-NOREC2'));
select set_rule('production_requires_recipe','true') is null as prr \gset
select tt.err('N2 production_requires_recipe=on -> direct production-in refused', format($$select stock_production_in('%s',1,5,now(),null,'manual test 2',gen_random_uuid(),null)$$, tt.iid('FG-NOREC')), 'recipe');
select tt.eq('N2 cookie stock still 5 (first run only)', 5, tt.qty('FG-NOREC'));
