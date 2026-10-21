-- Phase 99 before/after fixture, loaded AFTER tests/sql/w1d_fixture.sql and w1d_snap_setup.sql (they supply the owner 092, stock, production, wastage, a count, a transit loss, a cash short,
-- a supplier bill, a 10-2 voucher, a quick expense, a payroll run, a 02-2 sheet and a partner agreement). This file adds the other kinds of records an install has that the Wave 1 hooks
-- touch: a credit sale and a collection, a customer return, a voided sale, owner money and bank moves, a supplier payment, a staff advance, a second quick expense. NO new setting is switched on.
-- Test data only (test_* names).
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000092'
select set_config('request.jwt.claim.sub', :'o', false);
create schema if not exists tt;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
insert into customers (mobile, name) values ('01800000999', 'test_customer_p99'), ('01800000998', 'test_customer_p99b');
select id as pc1 from customers where mobile = '01800000999' \gset
select id as pi from items where code = 'W1D-RM' \gset
select id as pf from items where code = 'W1D-FG' \gset
-- a credit sale of 2 finished goods (customer pays 120 later), a cash sale that is voided, a sale that is partly returned
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":2,"price":100}]', :'pf')::jsonb, 0, '[]'::jsonb, '01800000999', 'test_customer_p99', 'retail', null, false) ->> 'id' as pc_sale \gset
select collect_payment(gen_random_uuid(), 1, :'pc1'::uuid, '[{"mode":"cash","amount":120}]'::jsonb, 'test') is not null as pc_col \gset
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1,"price":100}]', :'pf')::jsonb, 0, '[{"mode":"cash","amount":100}]'::jsonb, null, null, 'retail', null, false) ->> 'id' as pv_sale \gset
select void_sale(:'pv_sale'::uuid, 'test void') is not null as pv_do \gset
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":2,"price":100}]', :'pf')::jsonb, 0, '[{"mode":"mobile","amount":200,"wallet":"bkash"}]'::jsonb, null, null, 'retail', null, false) ->> 'id' as pr_sale \gset
select sale_return(gen_random_uuid(), :'pr_sale'::uuid, format('[{"item_id":"%s","qty":1}]', :'pf')::jsonb, 'damaged', null, 'cash', null, null) is not null as pr_do \gset
-- owner money, bank moves, supplier payment and refund, advance, a second quick expense, a voucher in submitted state
select cash_move_add(1,'owner_topup',5000,tt.today(),'cash',null,'p99',null,gen_random_uuid(),false) is not null as c1 \gset
select cash_move_add(1,'owner_draw',1500,tt.today(),'bank',null,'p99',null,gen_random_uuid(),false) is not null as c2 \gset
select cash_move_add(1,'bank_deposit',2000,tt.today(),null,null,'p99',null,gen_random_uuid(),false) is not null as c3 \gset
select pay_supplier((select id from suppliers where name='test_supplier_w1d'), 1, '[{"mode":"cash","amount":50}]'::jsonb, gen_random_uuid(), 'p99') is not null as sp1 \gset
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 120, 'mobile', false, null, gen_random_uuid()) is not null as qe2 \gset
select staff_advance_add((select id from employees where employee_no='TESTBA_W'), tt.today(), 1000, 500, 'cash', tt.today() + 30, 'p99 advance', gen_random_uuid()) is not null as adv \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"90"}]}'::jsonb,'[]') ->> 'id' as pe1 \gset
select submit_entry(:'pe1'::uuid) is not null as pse \gset
select acct_post_pending(false) ->> 'posted' as posted \gset
select :'posted' as posted;
