-- Phase 88 before/after fixture, loaded AFTER tests/sql/p87_fixture.sql: customer and supplier records an existing install has (test_* names only).
-- A credit sale with a collection, a customer who only paid, a supplier with a typed opening and a payment. NO opening on any customer (the column does not exist before phase 88).
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000987'
select set_config('request.jwt.claim.sub', :'o', false);
insert into customers (mobile, name) values ('01800000988', 'test_customer_ba88'), ('01800000989', 'test_customer_ba88b') on conflict do nothing;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id)
  select 1, 988101, tt.today(), now(), '[]', 700, 0, 700, 'cash', 'done', :'o', id from customers where mobile = '01800000988';
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id)
  select 1, 988102, tt.today(), now(), '[]', 450, 0, 450, 'cash', 'done', :'o', id from customers where mobile = '01800000989';
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, paid_at, created_by)
  select null, id, 1, 'collection', 'cash', 200, now(), :'o' from customers where mobile = '01800000988';
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, paid_at, created_by)
  select s.id, s.customer_id, 1, 'sale', 'cash', 450, now(), :'o' from sales s where s.receipt = 988102;
update suppliers set opening_balance = 250 where name = 'test_supplier_ba';
select acct_post_pending(false) ->> 'posted' as posted88;
