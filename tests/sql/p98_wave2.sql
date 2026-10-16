-- Phase 98 before/after helper: a second wave of documents that are NOT yet in the books (records of many kinds, test data only).
-- Run on a database that already holds tests/sql/p87_fixture.sql (owner 987). Nothing here posts: the poster (manual or scheduled) does.
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false);
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 77, 'cash', false, null, gen_random_uuid()) is not null;
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date - 2, 'transport', 'test_rider', 33, 'bank', false, null, gen_random_uuid()) is not null;
select cash_move_add(1,'owner_topup',900,(now() at time zone 'Asia/Dhaka')::date,'mobile',null,'w2',null,gen_random_uuid(),false) is not null;
select cash_move_add(2,'owner_draw',400,(now() at time zone 'Asia/Dhaka')::date,'cash',null,'w2',null,gen_random_uuid(),false) is not null;
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by) select id, 1, 'mobile', 'bkash', 66, now(), '00000000-0000-0000-0000-000000000987' from suppliers where name='test_supplier_ba';
insert into supplier_payments (supplier_id, location_id, mode, amount, paid_at, created_by) select id, 1, 'cash', 44, now() - interval '3 days', '00000000-0000-0000-0000-000000000987' from suppliers where name='test_supplier_ba';
select staff_advance_add((select id from employees where employee_no='TESTBA_A'), (now() at time zone 'Asia/Dhaka')::date, 1000, 500, 'bank', (now() at time zone 'Asia/Dhaka')::date + 30, 'w2', gen_random_uuid()) is not null;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 987201, (now() at time zone 'Asia/Dhaka')::date, now(), '[]', 700, 0, 700, 'cash', 'done', '00000000-0000-0000-0000-000000000987'),
 (2, 987202, (now() at time zone 'Asia/Dhaka')::date - 1, now() - interval '1 day', '[]', 450, 0, 450, 'mobile', 'done', '00000000-0000-0000-0000-000000000987');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by)
 select s.id, s.location_id, 'sale', s.pay_mode, case when s.pay_mode = 'mobile' then 'bkash' end, s.total, s.sold_at, '00000000-0000-0000-0000-000000000987' from sales s where s.receipt in (987201, 987202);
select void_sale((select id from sales where receipt = 987102), 'test void wave2') is null;      -- an already posted sale is voided: the poster must reverse it
