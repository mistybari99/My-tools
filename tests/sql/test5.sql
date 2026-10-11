insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000001','owner1@s.app','{"full_name":"Owner"}'),
 ('00000000-0000-0000-0000-000000000002','shop2@s.app','{"full_name":"Shop Mgr"}'),
 ('00000000-0000-0000-0000-000000000003','cash3@s.app','{"full_name":"Cash Ctl"}'),
 ('00000000-0000-0000-0000-000000000005','shop5@s.app','{"full_name":"Other Shop"}');
update profiles set status='active' where staff_id<>'owner1';
insert into user_roles values ('00000000-0000-0000-0000-000000000002','showroom_manager'),('00000000-0000-0000-0000-000000000003','cash_controller'),('00000000-0000-0000-0000-000000000005','salesperson');
insert into user_locations values ('00000000-0000-0000-0000-000000000002',1),('00000000-0000-0000-0000-000000000003',1),('00000000-0000-0000-0000-000000000005',2);
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
\echo A null lines / NaN qty / zero-line rejected
select record_sale(gen_random_uuid(),1,null,0,'cash',null,null,null,false);
select record_sale(gen_random_uuid(),1,(select jsonb_build_array(jsonb_build_object('item_id',id,'qty','NaN')) from items limit 1),0,'cash',null,null,null,false);
\echo B offline sale keeps its own time (2 days ago), future time clamped
select record_sale(gen_random_uuid(),1,'[{"amount":40}]',0,'cash',null,null,null,true, now() - interval '2 days');
select sale_date = ((now() - interval '2 days') at time zone 'Asia/Dhaka')::date as kept_old_date from sales order by receipt desc limit 1;
select record_sale(gen_random_uuid(),1,'[{"amount":41}]',0,'cash',null,null,null,true, now() + interval '2 days');
select sold_at < now() + interval '1 minute' as clamped from sales order by receipt desc limit 1;
\echo C price drift flagged but list price used
select record_sale(gen_random_uuid(),1,(select jsonb_build_array(jsonb_build_object('item_id',id,'qty',1,'price',1)) from items order by code limit 1),0,'cash',null,null,null,false);
select flag_code from exceptions order by id desc limit 1;
\echo D same client id by another user is not echoed back
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale('22222222-2222-2222-2222-222222222222',1,'[{"amount":9}]',0,'cash',null,null,null,true);
select record_sale('22222222-2222-2222-2222-222222222222',1,'[{"amount":9}]',0,'cash',null,null,null,true);
\echo E entries cannot carry POS
select save_entry(null,'POS',1,'2026-10-12','{}','[]');
\echo F sales_summary under RLS
select sale_date, pay_mode, status, n, total from sales_summary(current_date - 5) order by 1,2;
\echo G exceptions location scope: other-location salesperson/mgr cannot resolve
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select count(*) as visible_to_loc2_salesperson from exceptions;
\echo H photo policy function
reset role; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select photo_ok('10-2/1/a.jpg','enter') as mgr_loc1, photo_ok('10-2/2/a.jpg','enter') as mgr_loc2, photo_ok('10-2/x/a.jpg','enter') as bad_path, photo_ok('06-3/1/a.jpg','view') as no_perm_form;
