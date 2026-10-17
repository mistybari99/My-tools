-- RPT-B1 fixture, third part (phase 403): a cake item over several days, customers, last year's sales. Runs after rptb1_fixture.sql and rptb1_fixture2.sql. Test data only (test_* names).
-- Item test_cake (K, price 60, tracked), place 1 unless said otherwise. "today" = the Dhaka date.
--   D-5 opening 20 @ 50 | D-2: produced +30 @ 40, received +10 @ 45, sold 25 (10 + 15), wasted 3 (after the receipts: average cost (20x50 + 30x40 + 10x45) / 60 = 44.1667 -> waste cost 132.50) -> left 32
--   D-1: produced +20 @ 40, sold 28 (14 + 14), sent 4 to place 2 (place 2 receives 4) -> left 20 | today: sold 10 (5 walk-in + 5 to customer 2), wasted 2, 1 returned by the walk-in buyer -> left 9
--   test_cake_nocost (K2): opening 10 with NO cost on D-5, wasted 1 today (cost unknown) | test_cake_old (L): opening 50 @ 10, no movement in the window
--   test_untracked (U): not stock-tracked, 6 sold today (60) | one quick line of 90 today
--   customers: c2 buys 5 K (300) + 2 A (200) today; c3 buys 2 B (100) today. (c1 = the credit customer of fixture 1: 10 B = 500, 100 returned against the due -> 400)
--   LAST YEAR (direct sales rows, no stock movement): K 2 x 20 @ 60 = 2400 on (today - 1 day) - 1 year | A 5 @ 100 = 500 on today - 1 year | L 7 @ 25 = 175 on (today - 2 days) - 1 year
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000400'
select set_config('request.jwt.claim.sub', :'o', false);
insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category) values
 ('RB1-K','test_cake','test_cake','piece','piece',60,true,'finished_good','test_cat_cake'),
 ('RB1-K2','test_cake_nocost','test_cake_nocost','piece','piece',20,true,'finished_good','test_cat_cake'),
 ('RB1-L','test_cake_old','test_cake_old','piece','piece',25,true,'finished_good','test_cat_cake'),
 ('RB1-U','test_untracked','test_untracked','piece','piece',10,false,'finished_good','test_cat_cake');
select id as i_k from items where code='RB1-K' \gset
select id as i_k2 from items where code='RB1-K2' \gset
select id as i_l from items where code='RB1-L' \gset
select id as i_u from items where code='RB1-U' \gset
select id as i_a from items where code='RB1-A' \gset
select id as i_b from items where code='RB1-B' \gset
insert into customers (mobile, name, credit_limit) values ('01800000402', 'test_customer_rb2', 100000), ('01800000403', 'test_customer_rb3', 100000);

-- D-5: openings (the ledger cannot be edited, so the date is given when posting)
select stock_post(:'i_k'::uuid,1,20,'opening','opening',null,50,null,now() - interval '5 days') is not null as w1 \gset
select stock_post(:'i_k2'::uuid,1,10,'opening','opening',null,null,null,now() - interval '5 days') is not null as w2 \gset
select stock_post(:'i_l'::uuid,1,50,'opening','opening',null,10,null,now() - interval '5 days') is not null as w3 \gset

-- D-2
select stock_post(:'i_k'::uuid,1,30,'production_in','production','rb1-run-a',40,null,now() - interval '2 days') is not null as w4 \gset
select stock_post(:'i_k'::uuid,1,10,'transfer_in','transfer','rb1-tr-a',45,null,now() - interval '2 days') is not null as w5 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":10,"price":60}]',:'i_k')::jsonb,0,'[{"mode":"cash","amount":600}]','','','retail',null,false, now() - interval '2 days') is not null as w6 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":15,"price":60}]',:'i_k')::jsonb,0,'[{"mode":"cash","amount":900}]','','','retail',null,false, now() - interval '2 days') is not null as w7 \gset
select stock_post(:'i_k'::uuid,1,-3,'wastage','wastage','rb1-w-a',null,null,now() - interval '2 days') is not null as w8 \gset

-- D-1
select stock_post(:'i_k'::uuid,1,20,'production_in','production','rb1-run-b',40,null,now() - interval '1 day') is not null as w9 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":14,"price":60}]',:'i_k')::jsonb,0,'[{"mode":"cash","amount":840}]','','','retail',null,false, now() - interval '1 day') is not null as w10 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":14,"price":60}]',:'i_k')::jsonb,0,'[{"mode":"cash","amount":840}]','','','retail',null,false, now() - interval '1 day') is not null as w11 \gset
select stock_post(:'i_k'::uuid,1,-4,'transfer_out','transfer','rb1-tr-b',null,null,now() - interval '1 day') is not null as w12 \gset
select stock_post(:'i_k'::uuid,2,4,'transfer_in','transfer','rb1-tr-b',45,null,now() - interval '1 day') is not null as w13 \gset

-- today
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":60}]',:'i_k')::jsonb,0,'[{"mode":"cash","amount":300}]','','','retail',null,false) ->> 'id' as s_kw \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":60},{"item_id":"%s","qty":2,"price":100}]',:'i_k',:'i_a')::jsonb,0,'[{"mode":"cash","amount":500}]','01800000402','test_customer_rb2','retail',null,false) is not null as w14 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":50}]',:'i_b')::jsonb,0,'[{"mode":"cash","amount":100}]','01800000403','test_customer_rb3','retail',null,false) is not null as w15 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":6,"price":10}]',:'i_u')::jsonb,0,'[{"mode":"cash","amount":60}]','','','retail',null,false) is not null as w16 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":90}]'::jsonb,0,'[{"mode":"cash","amount":90}]','','','retail',null,true) is not null as w17 \gset
select stock_post(:'i_k'::uuid,1,-2,'wastage','wastage','rb1-w-b',null,null,now()) is not null as w18 \gset
select stock_post(:'i_k2'::uuid,1,-1,'wastage','wastage','rb1-w-c',null,null,now()) is not null as w19 \gset
select sale_return(gen_random_uuid(), :'s_kw'::uuid, format('[{"item_id":"%s","qty":1}]',:'i_k')::jsonb, (select value_code from option_lists where list_code='return_reasons' and active order by 1 limit 1), 'test', 'cash') ->> 'id' as r_k \gset

-- last year (direct rows: no stock movement)
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, created_staff, paid)
 select 1, 880000 + n, ((now() at time zone 'Asia/Dhaka')::date - d - interval '1 year')::date, now() - d * interval '1 day' - interval '1 year',
        format('[{"item_id":"%s","qty":%s,"price":%s,"amount":%s}]', it, q, pr, q * pr)::jsonb, q * pr, 0, q * pr, 'cash', 'done', :'o'::uuid, 'test_owner_rb1', q * pr
   from (values (1, 1, :'i_k'::uuid, 20, 60), (2, 1, :'i_k'::uuid, 20, 60), (3, 0, :'i_a'::uuid, 5, 100), (4, 2, :'i_l'::uuid, 7, 25)) v(n, d, it, q, pr);
select count(*) as n_ly from sales where receipt >= 880000 \gset
select :'n_ly' as last_year_sales;
