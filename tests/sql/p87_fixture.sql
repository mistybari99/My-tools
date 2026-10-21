-- Phase 87 before/after fixture: the kinds of records an existing install has (NO money account anywhere). Test data only (test_* names).
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000987'
create schema if not exists tt;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','test_owner_ba@s.app','{"full_name":"test_owner"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
select acct_set_start(:'pm'::date) is not null as s1 \gset
select set_rule('accounting_on','true') is null as s2 \gset
select acct_journal_post(:'pm'::date, 1, 'test opening', '[{"code":"1110","debit":900000},{"code":"1120","debit":300000},{"code":"3100","credit":1200000}]'::jsonb) is not null as s3 \gset
insert into customers (mobile, name) values ('01800000987', 'test_customer_ba');
insert into suppliers (name) values ('test_supplier_ba');
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 987101, tt.today(), now(), '[]', 1000, 0, 1000, 'cash', 'done', :'o'), (1, 987102, tt.today(), now(), '[]', 500, 0, 500, 'mobile', 'done', :'o'),
 (2, 987103, tt.today(), now(), '[]', 800, 0, 800, 'card', 'done', :'o');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by)
 select s.id, s.location_id, 'sale', s.pay_mode, case when s.pay_mode = 'mobile' then 'bkash' end, s.total, now(), :'o' from sales s where s.receipt in (987101, 987102, 987103);
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by) select id, 1, 'mobile', 'nagad', 100, now(), :'o' from suppliers where name='test_supplier_ba';
insert into supplier_payments (supplier_id, location_id, mode, amount, paid_at, created_by) select id, 1, 'cash', 250, now(), :'o' from suppliers where name='test_supplier_ba';
insert into supplier_payments (supplier_id, location_id, mode, amount, paid_at, created_by) select id, 2, 'bank', 400, now(), :'o' from suppliers where name='test_supplier_ba';
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TESTBA_A','test_emp_ba','active',1) returning id) select id as ea from x \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 1, 'draft') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'ea', 1, 8000, 8000) returning id) select id as l1 from x \gset
select payroll_approve(:'run1'::bigint) ->> 'status' as ap \gset
select payroll_pay(:'run1'::bigint, array[:'l1'::bigint], 'bank', tt.today(), 'ba-sal', null, gen_random_uuid(), null) is not null as pp \gset
select staff_advance_add(:'ea'::uuid, tt.today(), 2000, 500, 'cash', tt.today() + 30, 'test advance', gen_random_uuid()) is not null as adv \gset
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 300, 'cash', false, 'test note', gen_random_uuid()) is not null as qe1 \gset
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 120, 'mobile', false, null, gen_random_uuid()) is not null as qe2 \gset
select cash_move_add(1,'owner_topup',5000,tt.today(),'cash',null,'ba',null,gen_random_uuid(),false) is not null as c1 \gset
select cash_move_add(1,'owner_draw',1500,tt.today(),'bank',null,'ba',null,gen_random_uuid(),false) is not null as c2 \gset
select cash_move_add(1,'bank_deposit',2000,tt.today(),null,null,'ba',null,gen_random_uuid(),false) is not null as c3 \gset
select cash_move_add(1,'hub_receipt',700,tt.today(),'cash',null,'ba',null,gen_random_uuid(),false) is not null as c4 \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"transport","amount":"500"}]}'::jsonb,'[]') ->> 'id' as e1 \gset
select submit_entry(:'e1'::uuid) is not null as se \gset
select decide_entry(:'e1'::uuid,true,null,'{}','[]') ->> 'status' as de \gset
select supplier_refund((select id from suppliers where name='test_supplier_ba'), 1, 90, 'cash', null, 'rf', 'other', null, gen_random_uuid()) is not null as sr \gset
insert into sale_returns (sale_id, location_id, lines, amount, refund_amount, refund_mode, reason_code, created_by) select id, 1, '[]', 200, 200, 'cash', 'other', :'o' from sales where receipt=987101;
select acct_post_pending(false) ->> 'posted' as posted \gset
select :'posted' as posted;
