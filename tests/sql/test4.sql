insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000001','owner1@s.app','{"full_name":"Owner"}'),
 ('00000000-0000-0000-0000-000000000002','shop2@s.app','{"full_name":"Shop Mgr"}'),
 ('00000000-0000-0000-0000-000000000003','cash3@s.app','{"full_name":"Cash Ctl"}'),
 ('00000000-0000-0000-0000-000000000005','shop5@s.app','{"full_name":"Other Shop"}');
update profiles set status='active' where staff_id<>'owner1';
insert into user_roles values ('00000000-0000-0000-0000-000000000002','showroom_manager'),('00000000-0000-0000-0000-000000000003','cash_controller'),('00000000-0000-0000-0000-000000000005','salesperson');
insert into user_locations values ('00000000-0000-0000-0000-000000000002',1),('00000000-0000-0000-0000-000000000003',1),('00000000-0000-0000-0000-000000000005',2);
\echo T1 item sale at server price
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale('11111111-1111-1111-1111-111111111111',1,
 (select jsonb_build_array(jsonb_build_object('item_id',id,'qty',2.5,'price',1)) from items order by code limit 1),0,'cash',2000,null,null,false);
select receipt,subtotal,total,lines->0->>'price' as price,lines->0->>'amount' as amt,(select sell_price from items order by code limit 1) as list from sales;
\echo T2 resend same client id = dup, no second row
select record_sale('11111111-1111-1111-1111-111111111111',1,'[{"amount":50}]',0,'cash',null,null,null,true);
select count(*) from sales;
\echo T3 quick sale, discount, due needs customer
select record_sale(gen_random_uuid(),1,'[{"amount":300,"name":"Rush"}]',20,'mobile',null,null,null,true);
select record_sale(gen_random_uuid(),1,'[{"amount":300}]',0,'due',null,null,null,true);
select record_sale(gen_random_uuid(),1,'[{"amount":300}]',0,'due',null,'Karim','pay friday',true);
select record_sale(gen_random_uuid(),1,'[{"amount":300}]',999,'cash',null,null,null,true);
\echo T4 price override makes exception; other location blocked; zero qty blocked
select record_sale(gen_random_uuid(),1,(select jsonb_build_array(jsonb_build_object('item_id',id,'qty',1,'override',true,'price',1)) from items order by code limit 1),0,'cash',null,null,null,false);
select count(*) as override_exceptions from exceptions where flag_code='price_override';
select record_sale(gen_random_uuid(),2,'[{"amount":5}]',0,'cash',null,null,null,true);
select record_sale(gen_random_uuid(),1,(select jsonb_build_array(jsonb_build_object('item_id',id,'qty',0)) from items limit 1),0,'cash',null,null,null,false);
select receipt,total,pay_mode,status from sales order by receipt;
\echo T5 void: salesperson cannot, manager needs note
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale(gen_random_uuid(),2,'[{"amount":5}]',0,'cash',null,null,null,true);
select void_sale((select id from sales where receipt=1 and location_id=1),'x');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select void_sale((select id from sales where receipt=1 and location_id=1),'');
select void_sale((select id from sales where receipt=1 and location_id=1),'wrong item');
select void_sale((select id from sales where receipt=1 and location_id=1),'again');
select status,void_staff,void_note from sales where receipt=1 and location_id=1;
\echo T6 cash controller view only; other-location user sees only own location
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select count(*) as cc_sees from sales;
select record_sale(gen_random_uuid(),1,'[{"amount":5}]',0,'cash',null,null,null,true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select count(*) as other_loc_sees from sales;
\echo T7 direct write blocked
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
update sales set total=1;
