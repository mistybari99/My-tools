-- Phase 120 before/after wave 2: ordinary documents through the EXISTING payment functions, no request anywhere. Test data only.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false);
select staff_advance_add((select id from employees where employee_no='TESTBA_A'), (now() at time zone 'Asia/Dhaka')::date, 700, 100, 'cash', (now() at time zone 'Asia/Dhaka')::date, 'test wave2 advance', gen_random_uuid()) is not null;
select staff_advance_add((select id from employees where employee_no='TESTBA_A'), (now() at time zone 'Asia/Dhaka')::date, 300, null, 'none', (now() at time zone 'Asia/Dhaka')::date, 'test wave2 paper', gen_random_uuid()) is not null;
select set_config('bos88.api','1',false) is not null;
update suppliers set opening_balance = 5000 where name='test_supplier_ba';
select pay_supplier((select id from suppliers where name='test_supplier_ba'), 1, '[{"mode":"cash","amount":10},{"mode":"bank","amount":15}]'::jsonb, gen_random_uuid(), 'test wave2') is not null;
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 55, 'cash', false, null, gen_random_uuid()) is not null;
select acct_post_pending(false) ->> 'posted';
