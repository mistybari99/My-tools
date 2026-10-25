-- RPT-C2 customer data set (neutral test_* data). Needs tests/sql/c2_fixture.sql first. T = today (Dhaka), place 1, test_item_a price 100.
--   cu1 test_cust_1  S1 (T-40) 300 paid 100 -> 200 open | S2 (T-10) 100 unpaid | a collection of 150 at T-5 -> oldest first: S1 has 50 left, S2 100 -> balance 150. Terms 30 days -> S1 due T-10 -> 50 overdue, 10 days.
--                    advance held 40 (cash_move cust_advance)
--   cu2 test_cust_2  S3 (T-100) 500 unpaid, no credit terms -> balance 500, terms none
--   cu3 test_cust_3  S4 (T-3) 200 paid in full -> no dues; special-order data lives on cu1 (see c2_orders)
--   cu4 test_cust_4  S5 (T-2) 200 unpaid, credit limit 100, terms 0 days -> balance 200 over limit (200 percent), 2 days past due
--   a sale with a due and NO customer (S6, 100) and an opening due of 300 on test_cust_5 (not counted while open_parties_link is OFF)
\set ON_ERROR_STOP off
select tt.as(:'p');
select (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":100}]',:'ia')::jsonb,0,'[{"mode":"cash","amount":100}]'::jsonb,'01700000301','test_cust_1','retail',null,false)->>'id')::uuid as s1 \gset
select (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'ia')::jsonb,0,'[]'::jsonb,'01700000301','test_cust_1','retail',null,false)->>'id')::uuid as s2 \gset
select (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":100}]',:'ia')::jsonb,0,'[]'::jsonb,'01700000302','test_cust_2','retail',null,false)->>'id')::uuid as s3 \gset
select (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'ia')::jsonb,0,'[{"mode":"cash","amount":200}]'::jsonb,'01700000303','test_cust_3','retail',null,false)->>'id')::uuid as s4 \gset
select (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'ia')::jsonb,0,'[]'::jsonb,'01700000304','test_cust_4','retail',null,false)->>'id')::uuid as s5 \gset
select (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'ia')::jsonb,0,'[]'::jsonb,'01700000306','test_cust_6','retail',null,false)->>'id')::uuid as s6 \gset
select id as cu1 from customers where mobile='01700000301' \gset
select id as cu2 from customers where mobile='01700000302' \gset
select id as cu3 from customers where mobile='01700000303' \gset
select id as cu4 from customers where mobile='01700000304' \gset
select id as cu6 from customers where mobile='01700000306' \gset
select tt.as(:'o');
set session_replication_role = replica;
update sales set sale_date = tt.today()-40, sold_at = (tt.today()-40)::timestamptz + interval '10 hours' where id = :'s1'::uuid;
update sales set sale_date = tt.today()-10, sold_at = (tt.today()-10)::timestamptz + interval '10 hours' where id = :'s2'::uuid;
update sales set sale_date = tt.today()-100, sold_at = (tt.today()-100)::timestamptz + interval '10 hours' where id = :'s3'::uuid;
update sales set sale_date = tt.today()-3, sold_at = (tt.today()-3)::timestamptz + interval '10 hours' where id = :'s4'::uuid;
update sales set sale_date = tt.today()-2, sold_at = (tt.today()-2)::timestamptz + interval '10 hours' where id = :'s5'::uuid;
update sale_payments set paid_at = (tt.today()-40)::timestamptz + interval '10 hours' where sale_id = :'s1'::uuid;
update sale_payments set paid_at = (tt.today()-3)::timestamptz + interval '10 hours' where sale_id = :'s4'::uuid;
-- a collection of 150 five days ago
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, paid_at, created_by, created_staff) values (null, :'cu1'::uuid, 1, 'collection', 'cash', 150, (tt.today()-5)::timestamptz + interval '12 hours', :'p'::uuid, 'test_sales1');
-- the legacy sale with a due and no customer
update sales set customer_id = null where id = :'s6'::uuid;
update sale_payments set customer_id = null where sale_id = :'s6'::uuid;
-- terms, limit, opening
update customers set credit_days = 30 where id = :'cu1'::uuid;
update customers set credit_days = 0, credit_limit = 100 where id = :'cu4'::uuid;
insert into customers (mobile, name, type, opening_balance, opening_date, created_by) values ('01700000305', 'test_cust_5', 'retail', 300, tt.today()-200, :'o'::uuid);
set session_replication_role = origin;
select tt.as(:'c');
select cash_move_add(1, 'cust_advance', 40, tt.today(), 'cash', :'cu1'::uuid, 'test advance', null, gen_random_uuid()) is not null as adv1 \gset
select tt.as(:'o');
