-- Batch 1 shared scenario = the audit A3 scenario (docs/audit2/A3_real_profit.md, hand-computed there), reproduced for the phase112 / phase113 tests. Needs tests/sql/e2e/00_common.sql (tt.*) and \set o, ap.
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@b1.app','{"full_name":"Owner"}'),(:'ap','approver@b1.app','{"full_name":"Approver"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ap','recipe_approver') on conflict do nothing;
insert into user_locations values (:'ap',6) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false,null),('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false,null),
 ('FG-A','Sweet A','Sweet A','kg','kg','finished_good',true,100,true,'sweet_kg'),
 ('RS-B','Item B','Item B','pc','pc','resale',true,90,true,'cake_pc'),
 ('RS-C','Item C nocost','Item C nocost','pc','pc','resale',true,100,true,'cake_pc') on conflict do nothing;
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select stock_opening(tt.iid('RM-F'),6,100,40) is not null as a1 \gset
select stock_opening(tt.iid('RM-S'),6,100,20) is not null as a2 \gset
select stock_opening(tt.iid('RS-B'),2,10,50) is not null as a3 \gset
select stock_opening(tt.iid('RS-C'),2,5,null) is not null as a4 \gset
select acct_opening('[{"code":"1110","debit":10000,"location_id":1},{"code":"3100","credit":10000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a_on \gset
select set_rule('accounting_autopost','true') is null as a_on2 \gset
select (recipe_save(null, tt.iid('FG-A'), 10, 'kg', 'A v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select loc_cost_cfg_set(6,'recipe') is null as lc \gset
select recipe_cost_component_set(:'rc'::uuid,'labour','per_batch',100,null,null,'labour',gen_random_uuid()) is not null as cc \gset
select tt.as(:'ap'); select recipe_approve(:'rc'::uuid,'ok') is not null as rap \gset
select tt.as(:'o');
select production_post(6, :'rc'::uuid, 2, gen_random_uuid()) as pj \gset
select (stock_transfer(6,2,tt.iid('FG-A'),10,null,'t1')->>'id')::uuid as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 10, null) is not null as r1 \gset
select (stock_transfer(6,3,tt.iid('FG-A'),10,null,'t2')->>'id')::uuid as t2 \gset
select stock_receive_transfer(:'t2'::uuid, 10, null) is not null as r2 \gset
select tt.eq('S0 unit cost of A = (300+100)/10', 40, tt.avg('FG-A',6), 0.0005);
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":5,"price":100}]',tt.iid('FG-A'))::jsonb,50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,false) as s1 \gset
select (:'s1'::jsonb->>'id')::uuid as sale1 \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":4,"price":90}]',tt.iid('RS-B'))::jsonb,0,'[{"mode":"card","amount":360}]',null,null,'retail',null,false) as s2 \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('RS-C'))::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false) as s3 \gset
select record_sale2(gen_random_uuid(),3,format('[{"item_id":"%s","qty":8,"price":100}]',tt.iid('FG-A'))::jsonb,160,'[{"mode":"cash","amount":640}]',null,null,'retail',null,false) as s4 \gset
select sale_return(gen_random_uuid(), :'sale1'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-A'))::jsonb, 'damaged','b1 return','cash') as rt \gset
select tt.eq('S0 return keeps the discount share (90, not 100)', 90, (:'rt'::jsonb->>'amount')::numeric);
select stock_wastage(tt.iid('FG-A'),3,1,'spoiled','b1 waste') is not null as wg \gset
select card_settle(2, tt.today(), 360, 7.2, 'b1 batch', gen_random_uuid()) is not null as cs \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('02-2',2,8101,tt.today(),'approved','{"pay":[{"name":"S1 Clerk - Clerk","due":300}]}','[]',:'o','st'),
 ('02-2',6,8102,tt.today(),'approved','{"pay":[{"name":"F Cook - Cook","due":200}]}','[]',:'o','st');
select quick_expense_add(2, tt.today(), 'rent', 'landlord', 150, 'cash', true, 'b1 rent S1', gen_random_uuid()) is not null as q1 \gset
select quick_expense_add(3, tt.today(), 'transport', 'rider', 40, 'cash', true, 'b1 delivery S2', gen_random_uuid()) is not null as q2 \gset
select cost_source_save(null,'electricity','Utility Co','shared',null,array[2,3],'monthly',date_trunc('month',tt.today())::date,'b1',gen_random_uuid())->>'id' as es \gset
select cost_rule_save(:'es'::bigint,'headcount',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom","value":2},{"location_id":3,"dest":"showroom","value":1}]'::jsonb,'b1',gen_random_uuid())->>'id' as er \gset
select cost_rule_approve(:'er'::bigint,'ok') is not null as era \gset
select cost_bill_add(:'es'::bigint,'month',date_trunc('month',tt.today())::date,600,'cash','E-1',tt.today(),false,null,null,gen_random_uuid()) as eb \gset
select cost_source_save(null,'internet','ISP','shared',null,array[2,3],'monthly',date_trunc('month',tt.today())::date,'b1',gen_random_uuid())->>'id' as is_ \gset
select cost_rule_save(:'is_'::bigint,'fixed_percent',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom","value":70},{"location_id":3,"dest":"showroom","value":30}]'::jsonb,'b1',gen_random_uuid())->>'id' as ir \gset
select cost_rule_approve(:'ir'::bigint,'ok') is not null as ira \gset
select cost_bill_add(:'is_'::bigint,'month',date_trunc('month',tt.today())::date,300,'cash','I-1',tt.today(),false,null,null,gen_random_uuid()) as ib \gset
select cost_source_save(null,'other','Accounts software','separate','admin',array[2],'monthly',date_trunc('month',tt.today())::date,'b1 admin',gen_random_uuid())->>'id' as ads \gset
select cost_bill_add(:'ads'::bigint,'month',date_trunc('month',tt.today())::date,120,'cash','A-1',tt.today(),false,null,null,gen_random_uuid()) as ab \gset
select acct_post_pending(false) is not null as pp \gset
