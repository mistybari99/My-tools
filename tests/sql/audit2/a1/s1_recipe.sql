\echo == S1 (a) recipe with 3 raw + packaging + waste% + yield loss, 2 batches, actual yield 18.5 (mode=recipe)
-- HAND per batch (yield 10 kg): flour 6 x1.10=6.6 x40=264 | sugar 3x60=180 | butter 2x1.05=2.1 x500=1050 | box 2x3=6  => material 1500
--   conversion per batch: labour 2h x 50 = 100 ; gas per_unit 2 x 10kg = 20 -> 120 ; recipe_cost unit = (1500+120)/10 = 162.000
-- HAND run 2 batches, actual 18.5kg: need flour 13.2 sugar 6 butter 4.2 box 4 -> material 528+360+2100+12 = 3000
--   conversion = labour 2x2x50=200 + gas 2 x 18.5(actual out)=37 -> 237 ; total 3237 ; unit = 3237/18.5 = 174.973 ; std_cost = 3237/20 = 161.85 ; yield var = -7.5 %
-- HAND journal: Dr 1310 3237 / Cr 1320 2988 (528+360+2100) / Cr 1330 12 / Cr 5950 237 ; stock left flour 86.8 sugar 44 butter 15.8 box 196 cake 18.5
select loc_cost_cfg_set(1,'recipe') is null as lc \gset
select (recipe_save(null, tt.iid('FG-CAKE'), 10, 'kg', 'cake v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',10),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-B'),'qty',2,'unit','kg','waste_pct',5),
  jsonb_build_object('ingredient_item_id',tt.iid('PK-B'),'qty',2,'unit','pc','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select recipe_cost_component_set(:'rc'::uuid,'labour','per_labour_hour',50,2,null,'2h x 50',gen_random_uuid()) is not null as c1 \gset
select recipe_cost_component_set(:'rc'::uuid,'gas','per_unit',2,null,null,'gas per kg',gen_random_uuid()) is not null as c2 \gset
select recipe_cost(:'rc'::uuid,1) as rcj \gset
select tt.eq('A1 recipe_cost material (raw row incl box)', 1500, (select (x->>'amount')::numeric from jsonb_array_elements(:'rcj'::jsonb->'rows') x where x->>'row'='raw'));
select tt.eq('A1 recipe_cost conversion', 120, (:'rcj'::jsonb->>'conversion_cost')::numeric);
select tt.eq('A1 recipe_cost unit cost', 162, (:'rcj'::jsonb->>'unit_cost')::numeric, 0.0005);
select tt.as(:'o'); select recipe_approve(:'rc'::uuid,'ok') is not null as ap \gset
select set_user_grant(:'o'::uuid,'view_cost') is null as g0 \gset
select production_post(1, :'rc'::uuid, 2, gen_random_uuid(), null, 'a1 two batches', 18.5) as pj \gset
select (:'pj'::jsonb->>'run_id')::uuid as run1 \gset
select tt.eq('A2 booked qty = actual yield', 18.5, tt.qty('FG-CAKE'));
select tt.eq('A2 flour left', 86.8, tt.qty('RM-F')); select tt.eq('A2 sugar left', 44, tt.qty('RM-S')); select tt.eq('A2 butter left', 15.8, tt.qty('RM-B')); select tt.eq('A2 box left', 196, tt.qty('PK-B'));
select tt.eq('A2 run material_cost', 3000, (select material_cost from production_runs where id=:'run1'::uuid));
select tt.eq('A2 run conversion_cost', 237, (select conversion_cost from production_runs where id=:'run1'::uuid));
select tt.eq('A2 FG unit cost on actual yield', 174.973, tt.avg('FG-CAKE'), 0.0005);
select tt.eq('A2 std_cost column', 161.85, (select std_cost from production_runs where id=:'run1'::uuid), 0.0005);
select tt.eq('A2 yield_var_pct', -7.5, (select yield_var_pct from production_runs where id=:'run1'::uuid));
select acct_post_pending(false) as pp \gset
select tt.eq('A3 journal Dr 1310 for the run', 3237, (select coalesce(sum(l.debit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='production' and e.source_id=:'run1' and a.code='1310'));
select tt.eq('A3 journal Cr 1320', 2988, (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='production' and e.source_id=:'run1' and a.code='1320'));
select tt.eq('A3 journal Cr 1330', 12, (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='production' and e.source_id=:'run1' and a.code='1330'));
select tt.eq('A3 journal Cr 5950 overhead absorbed', 237, (select coalesce(sum(l.credit),0) from journal_entries e join journal_lines l on l.entry_id=e.id join coa_accounts a on a.id=l.account_id where e.source_type='production' and e.source_id=:'run1' and a.code='5950'));
select tt.eq('A3 unbalanced entries', 0, tt.unbalanced());
-- what the system cannot show: cost of the yield loss in money. HAND: 1.5 kg missing x 161.85 std = 242.78 ; extra per kg 13.12 x 18.5 = 242.78
select (select r from jsonb_array_elements(production_run_costs(1, tt.today()-1, tt.today()+1)) r limit 1) as prc \gset
\echo RUN_COSTS_ROW: :prc
select tt.t('A4 run-cost report has a money field for yield loss', (:'prc'::jsonb) ? 'yield_loss_cost', 'field present', case when (:'prc'::jsonb) ? 'yield_loss_cost' then 'yes' else 'no (only yield_var_pct %)' end);
-- over-yield 
select production_post(1, :'rc'::uuid, 1, gen_random_uuid(), null, 'a1 one batch over-yield', 10.8) as pj_o \gset
-- HAND: material 1500, conv 100 + 2x10.8=21.6 -> 121.6 ; total 1621.6 / 10.8 = 150.148
select tt.eq('A5 over-yield 10.8 kg unit cost', 150.148, (select unit_cost from production_runs where id=(:'pj_o'::jsonb->>'run_id')::uuid), 0.0005);
-- waste required / missing waste
select tt.t('A6 yield_variance_warn_pct default (no alert unless set)', rule_num('yield_variance_warn_pct') is null, 'null', coalesce(rule_num('yield_variance_warn_pct')::text,'null'));
