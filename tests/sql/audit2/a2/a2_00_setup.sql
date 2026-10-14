\echo == A2 00 setup (users, items, openings) - run through run_a2.sh (it prepends tests/sql/e2e/00_common.sql)
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner@a2.app','{"full_name":"Owner"}'),(:'fm','maker@a2.app','{"full_name":"Maker"}'),(:'sp','seller@a2.app','{"full_name":"Seller"}'),
 (:'sk','keeper@a2.app','{"full_name":"Keeper"}'),(:'ap','approver@a2.app','{"full_name":"Approver"}'),(:'rv','seller2@a2.app','{"full_name":"Seller Two"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge'),(:'sp','salesperson'),(:'sk','storekeeper'),(:'ap','recipe_approver'),(:'rv','salesperson') on conflict do nothing;
-- seller: loc 1 only; seller2: loc 2 only; maker/keeper/approver: loc 1+2
insert into user_locations values (:'fm',1),(:'fm',2),(:'sp',1),(:'sk',1),(:'sk',2),(:'ap',1),(:'rv',2) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('A-KG','Item kg','Item kg','kg','kg','finished_good',true,200,true),
 ('B-PC','Item pc (1 pc = 0.2 kg)','Item pc','pc','kg','finished_good',true,50,true),
 ('B-NOCONV','Item pc no conversion','Item pc noconv','pc','kg','finished_good',true,50,true),
 ('D-BOX','Box of 12 (stock in pc)','Box12','box','pc','finished_good',true,600,true),
 ('LOOSE','Loose pc','Loose pc','pc','pc','finished_good',true,60,true),
 ('COMBO12','Combo box of 12 loose','Combo12','box','box','finished_good',false,600,true),
 ('F-BATCH','Batch item','Batch item','kg','kg','finished_good',true,100,true),
 ('F-CAKE','Cake (recipe)','Cake','kg','kg','finished_good',true,300,true),
 ('F-SWPC','Sweet in pc, base kg','Sweet pc','pc','kg','finished_good',true,40,true),
 ('F-GAIN','Count gain item','Gain','kg','kg','finished_good',true,10,true),
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false),
 ('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false),
 ('T-1','Transfer item','Transfer','kg','kg','finished_good',true,10,true),
 ('T-B','Transfer batch item','Transfer batch','kg','kg','finished_good',true,10,true),
 ('N-OFF','Offline item','Offline','kg','kg','finished_good',true,100,true),
 ('N-NEG','Negative-mode item','Neg','kg','kg','finished_good',true,100,true),
 ('M-1','Merge/rename item','Merge1','kg','kg','finished_good',true,100,true)
 on conflict do nothing;
select set_unit_conversion(tt.iid('B-PC'),'pc','kg',0.2,'1 pc = 0.2 kg');
select set_unit_conversion(tt.iid('F-SWPC'),'pc','kg',0.05,'1 pc = 0.05 kg');
select set_unit_conversion(tt.iid('D-BOX'),'box','pc',12,'1 box = 12 pc');
-- openings: (cost per BASE unit)
select stock_opening(tt.iid('A-KG'),1,10,100) is not null as a1 \gset
select stock_opening(tt.iid('A-KG'),2,4,100) is not null as a2 \gset
select stock_opening(tt.iid('B-PC'),1,5,100) is not null as a3 \gset
select stock_opening(tt.iid('B-NOCONV'),1,5,100) is not null as a4 \gset
select stock_opening(tt.iid('D-BOX'),1,120,5) is not null as a5 \gset
select stock_opening(tt.iid('LOOSE'),1,120,5) is not null as a6 \gset
select stock_opening(tt.iid('RM-F'),1,100,40) is not null as a7 \gset
select stock_opening(tt.iid('RM-S'),1,100,50) is not null as a8 \gset
select stock_opening(tt.iid('T-1'),1,20,10) is not null as a9 \gset
select stock_opening(tt.iid('N-OFF'),1,5,100) is not null as a10 \gset
select stock_opening(tt.iid('N-NEG'),1,5,100) is not null as a11 \gset
select stock_opening(tt.iid('M-1'),1,10,100) is not null as a12 \gset
select tt.t('S0 openings ok', :'a1'::boolean and :'a2'::boolean and :'a3'::boolean and :'a4'::boolean and :'a5'::boolean and :'a6'::boolean and :'a7'::boolean and :'a8'::boolean and :'a9'::boolean and :'a10'::boolean and :'a11'::boolean and :'a12'::boolean);
