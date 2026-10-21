\echo == 01 setup users, items, accounting start, opening
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner@e2e.app','{"full_name":"Owner"}'),(:'bu','buyer@e2e.app','{"full_name":"Buyer"}'),(:'fm','maker@e2e.app','{"full_name":"Maker"}'),
 (:'sp','seller@e2e.app','{"full_name":"Seller"}'),(:'sk','keeper@e2e.app','{"full_name":"Keeper"}'),(:'bt','bot@e2e.app','{"full_name":"Bot"}'),
 (:'rv','reveal@e2e.app','{"full_name":"Revealer"}'),(:'ap','approver@e2e.app','{"full_name":"Approver"}'),(:'ac','acct@e2e.app','{"full_name":"Accountant"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'bu','purchasing'),(:'fm','factory_incharge'),(:'sp','salesperson'),(:'sk','storekeeper'),(:'ap','recipe_approver'),(:'rv','salesperson') on conflict do nothing;
insert into user_locations values (:'bu',1),(:'fm',1),(:'sp',1),(:'sk',1),(:'rv',1),(:'ap',1),(:'ac',1) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'fm'::uuid,'view_cost') is null as g1 \gset
select set_user_grant(:'rv'::uuid,'inbox_unmask') is null as g2 \gset
select set_user_grant(:'bu'::uuid,'supplier_pay') is null as g3 \gset
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson','inbox_contact_view',true) on conflict (role_code, grant_code) do update set allowed=true;
-- items
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false),
 ('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false),
 ('RM-SALT','Salt','Salt','kg','kg','raw_material',true,0,false),
 ('RM-W','Water','Water','ltr','ltr','raw_material',true,0,false),
 ('RM-X','Glaze','Glaze','kg','kg','raw_material',true,0,false),
 ('PK-B','Box','Box','pc','pc','packaging',true,0,false),
 ('PK-SN','Snack box','Snack box','pc','pc','packaging',true,0,false),
 ('FG-CAKE','Cake','Cake','kg','kg','finished_good',true,300,true),
 ('FG-SW','Sweet','Sweet','kg','kg','finished_good',true,400,true),
 ('FG-SNK','Snack','Snack','pc','pc','finished_good',true,25,true),
 ('FG-MILK','Milk','Milk','kg','kg','finished_good',true,100,true),
 ('FG-NOREC','Cookie','Cookie','kg','kg','finished_good',true,200,true) on conflict do nothing;
update items set sell_units = '{kg,pc}' where code='FG-SW';
select set_unit_conversion(tt.iid('FG-SW'),'pc','kg',0.05,'1 kg = 20 pc');
-- accounting: start 5 days ago
select acct_set_start(tt.today()-5)->>'start' as sd \gset
-- openings (stock ledger): flour 100@40, sweet 10@200, snack 50@10, snack box 100@2, water 100 (no cost, free), glaze 5 (no cost)
select stock_opening(tt.iid('RM-F'),1,100,40) is not null as a1 \gset
select stock_opening(tt.iid('FG-SW'),1,10,200) is not null as a2 \gset
select stock_opening(tt.iid('FG-SNK'),1,50,10) is not null as a3 \gset
select stock_opening(tt.iid('PK-SN'),1,100,2) is not null as a4 \gset
select stock_opening(tt.iid('RM-W'),1,100,null) is not null as a5 \gset
select stock_opening(tt.iid('RM-X'),1,5,null) is not null as a6 \gset
-- opening journal: cash 20000 + raw material 4000 (the flour) = capital 24000
select acct_opening('[{"code":"1110","debit":20000,"location_id":1},{"code":"1320","debit":4000,"location_id":1},{"code":"3100","credit":24000}]'::jsonb)->>'id' as oj \gset
select tt.t('S0 setup openings ok', :'a1'::boolean and :'a2'::boolean and :'a3'::boolean and :'a4'::boolean and :'a5'::boolean and :'a6'::boolean and :'oj' is not null);
select item_cost_free_set(tt.iid('RM-W'), true, 'tap water, really free', gen_random_uuid()) is not null as fr \gset
