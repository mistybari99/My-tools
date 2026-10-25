-- concurrency seed, part 2 (runs after tests/sql/e2e/00_common.sql + 01_setup.sql in the same psql session)
\echo == seed_extra
select tt.as(:'o');
insert into user_locations values (:'o',1),(:'o',2),(:'bu',2),(:'fm',2),(:'sp',2),(:'sk',2),(:'rv',2),(:'ac',2) on conflict do nothing;
select set_rule('accounting_on','true') is null as r1 \gset
select set_rule('accounting_autopost','true') is null as r2 \gset
-- suppliers
insert into suppliers (name, credit_days) values ('Sup Main', null), ('Transporter', null);
-- scenario items
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('FG-LAST','Last unit','Last unit','pc','pc','finished_good',true,100,true),
 ('FG-BULK','Bulk','Bulk','pc','pc','finished_good',true,50,true),
 ('RM-P','Prod raw','Prod raw','kg','kg','raw_material',true,0,false),
 ('FG-P','Prod out','Prod out','kg','kg','finished_good',true,90,true),
 ('RM-L','Landed raw','Landed raw','kg','kg','raw_material',true,0,false),
 ('FG-L','Landed fg','Landed fg','pc','pc','finished_good',true,200,true),
 ('RM-B','Bill raw','Bill raw','kg','kg','raw_material',true,0,false)
 on conflict do nothing;
select stock_opening(tt.iid('FG-BULK'),1,1000,30) is not null as o1 \gset
select stock_opening(tt.iid('RM-P'),1,100,10) is not null as o3 \gset
select stock_opening(tt.iid('RM-L'),1,100,20) is not null as o4 \gset
select stock_opening(tt.iid('FG-L'),1,200,100) is not null as o5 \gset
select opening_stock_apply96('difference',1,null,null,'concurrency seed opening stock','bbbbbbbb-0000-0000-0000-00000000c0c0'::uuid) is not null as oj2 \gset
-- recipe: 10 kg RM-P -> 8 kg FG-P ; approved
select (recipe_save(null, tt.iid('FG-P'), 8, 'kg', 'conc recipe', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-P'),'qty',10,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select tt.as(:'ap');
select recipe_approve(:'rc'::uuid,'ok') is not null as rap \gset
select tt.as(:'o');
select acct_post_pending(false) as pp \gset
select tt.t('SEED unbalanced = 0', tt.unbalanced() = 0);
select tt.t('SEED opening posted', (:'pp'::jsonb->>'posted')::int >= 0, 'info', :'pp');
