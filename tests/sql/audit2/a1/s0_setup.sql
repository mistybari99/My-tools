\echo == S0 setup: users, items, accounting, purchases (hand: see comments)
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@a1.app','{"full_name":"Owner"}'),(:'fm','maker@a1.app','{"full_name":"Maker"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge') on conflict do nothing;
insert into user_locations values (:'fm',1) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false),
 ('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false),
 ('RM-B','Butter','Butter','kg','kg','raw_material',true,0,false),
 ('RM-M','Milk','Milk','ltr','ltr','raw_material',true,0,false),
 ('RM-O','Oil','Oil','kg','kg','raw_material',true,0,false),
 ('RM-NC','Uncosted rm','Uncosted rm','kg','kg','raw_material',true,0,false),
 ('FG-NC','Uncosted fg','Uncosted fg','kg','kg','finished_good',true,0,false),
 ('PK-B','Box','Box','pc','pc','packaging',true,0,false),
 ('PK-P','Pouch','Pouch','pc','pc','packaging',true,0,false),
 ('FG-CAKE','Cake','Cake','kg','kg','finished_good',true,300,true),
 ('FG-SW','Sweet','Sweet','kg','kg','finished_good',true,400,true),
 ('FG-CHH','Chhana','Chhana','kg','kg','finished_good',true,0,false),
 ('FG-PC','Piece item','Piece item','pc','pc','finished_good',true,10,true),
 ('FG-OIL','Oil product','Oil product','kg','kg','finished_good',true,100,true) on conflict do nothing;
select acct_set_start(tt.today()-100)->>'start' as sd \gset
select acct_opening('[{"code":"1110","debit":100000,"location_id":1},{"code":"3100","credit":100000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a1 \gset
select set_rule('accounting_autopost','true') is null as a2 \gset
with s as (insert into suppliers (name, credit_days) values ('Sup Main', null) returning id) select id as s1 from s \gset
-- hand: flour 100@40=4000, sugar 50@60=3000, butter 20@500=10000, box 200@3=600, milk 200@80=16000, pouch 300@1=300 -> 33900
select save_purchase(gen_random_uuid(),null,:'s1'::uuid,1,'A1',tt.today()-12,format('[{"item_id":"%s","qty":100,"unit":"kg","unit_cost":40},{"item_id":"%s","qty":50,"unit":"kg","unit_cost":60},{"item_id":"%s","qty":20,"unit":"kg","unit_cost":500},{"item_id":"%s","qty":200,"unit":"pc","unit_cost":3},{"item_id":"%s","qty":200,"unit":"ltr","unit_cost":80},{"item_id":"%s","qty":300,"unit":"pc","unit_cost":1}]',tt.iid('RM-F'),tt.iid('RM-S'),tt.iid('RM-B'),tt.iid('PK-B'),tt.iid('RM-M'),tt.iid('PK-P'))::jsonb)->>'id' as b1 \gset
select post_purchase(:'b1'::uuid) is not null as pb1 \gset
select tt.eq('S0 bill total', 33900, (select total from purchase_bills where id=:'b1'::uuid));
select acct_post_pending(false) as pp0 \gset
select tt.eq('S0 inventory GL raw+pack = 33900', 33900, tt.bal('1320')+tt.bal('1330'));
