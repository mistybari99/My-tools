-- RPT-B1 fixture (phases 400, 401, 402): sales, returns, wastage and production made through the real functions. Test data only (test_* names). Places 1 and 2 only.
-- Needs a database built through phase 99 (the owner paste order). Does NOT need phases 400-402.
-- Hand-computed numbers (all dated today unless said otherwise):
--   place 1 sales : s1 cash 5 x A (100) = 500 | s2 cash 2 x A + 4 x B (50) = 400 | s3 credit wholesale 10 x B = 500 to test customer | s4 voided 1 x A = 100 (not counted anywhere)
--   place 2 sales : s5 cash 4 x A = 400, dated 3 days ago
--   returns       : R1 on s1, 2 x A = 200 refunded in CASH | R2 on s2, 2 x B = 100 refunded by MOBILE, made 2 days ago (a day with no sale at place 1)
--                   R3 on s3, 2 x B = 100 settled against the customer's due (credit, no money out) | R4 on s1, 1 x A = 100 cash then VOIDED (counted nowhere)
--   so            : sales (net) 1800 = 1400 at place 1 + 400 at place 2 | returns 400 | sales after returns 1400 (place 1: 1000, place 2: 400) | refunds paid out 300 (cash 200, mobile 100)
--   item A: sold 5 + 2 + 4 = 11 (place 1: 7), returned 2 | item B: sold 4 + 10 = 14, returned 2 + 2 = 4
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000400'
\set st '00000000-0000-0000-0000-000000000401'
create schema if not exists tt;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner_rb1@s.app','{"full_name":"test_owner"}'), (:'st','test_staff_rb1@s.app','{"full_name":"test_staff"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'st','salesperson') on conflict do nothing;
insert into user_locations values (:'st',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category) values
 ('RB1-A','test_item_a','test_item_a','piece','piece',100,true,'finished_good','test_cat_one'),
 ('RB1-B','test_item_b','test_item_b','piece','piece',50,true,'finished_good','test_cat_two');
select id as i_a from items where code='RB1-A' \gset
select id as i_b from items where code='RB1-B' \gset
select stock_opening(:'i_a'::uuid,1,200,60) is not null as w_o1 \gset
select stock_opening(:'i_b'::uuid,1,200,30) is not null as w_o2 \gset
select stock_opening(:'i_a'::uuid,2,50,60) is not null as w_o3 \gset
insert into customers (mobile, name, credit_limit) values ('01800000400', 'test_customer_rb1', 100000);
select id as c1 from customers where mobile='01800000400' \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":100}]',:'i_a')::jsonb,0,'[{"mode":"cash","amount":500}]','','','retail',null,false)->>'id' as s1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100},{"item_id":"%s","qty":4,"price":50}]',:'i_a',:'i_b')::jsonb,0,'[{"mode":"cash","amount":400}]','','','retail',null,false)->>'id' as s2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":10,"price":50}]',:'i_b')::jsonb,0,'[]','01800000400','test_customer_rb1','wholesale',null,false)->>'id' as s3 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'i_a')::jsonb,0,'[{"mode":"cash","amount":100}]','','','retail',null,false)->>'id' as s4 \gset
select void_sale(:'s4'::uuid, 'test void') is null as w_v \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":4,"price":100}]',:'i_a')::jsonb,0,'[{"mode":"cash","amount":400}]','','','retail',null,false)->>'id' as s5 \gset
update sales set sale_date = tt.today() - 3, sold_at = sold_at - interval '3 days' where id = :'s5'::uuid;
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":2}]',:'i_a')::jsonb, (select value_code from option_lists where list_code='return_reasons' and active order by 1 limit 1), 'test', 'cash') ->> 'id' as r1 \gset
select sale_return(gen_random_uuid(), :'s2'::uuid, format('[{"item_id":"%s","qty":2}]',:'i_b')::jsonb, (select value_code from option_lists where list_code='return_reasons' and active order by 1 limit 1), 'test', 'mobile', 'bkash', 'TX-RB1') ->> 'id' as r2 \gset
update sale_returns set created_at = created_at - interval '2 days' where id = :'r2'::uuid;
select sale_return(gen_random_uuid(), :'s3'::uuid, format('[{"item_id":"%s","qty":2}]',:'i_b')::jsonb, (select value_code from option_lists where list_code='return_reasons' and active order by 1 limit 1), 'test', 'cash') ->> 'id' as r3 \gset
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":1}]',:'i_a')::jsonb, (select value_code from option_lists where list_code='return_reasons' and active order by 1 limit 1), 'test', 'cash') ->> 'id' as r4 \gset
select void_sale_return(:'r4'::uuid, 'test void return') is not null as w_vr \gset
select :'s1' as s1, :'r1' as r1;
