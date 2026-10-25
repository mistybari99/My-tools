-- W1-F before/after fixture, second part (runs after p87_fixture.sql): documents an existing install may hold that touch the heads and the receipts of phases 96 and 97.
-- NO money account, no payment source anywhere. Test data only (test_* names).
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000987'
select set_config('request.jwt.claim.sub', :'o', false);
-- an approved but still UNPOSTED 10-2 voucher whose head is one of the three that phase 96 seeds (utilities): its figure must stay on Other expenses after the paste
select save_entry(null,'10-2',1,(now() at time zone 'Asia/Dhaka')::date,'{"lines":[{"head":"utilities","amount":"640"}]}'::jsonb,'[]') ->> 'id' as w1 \gset
select submit_entry(:'w1'::uuid) is not null as ws \gset
select decide_entry(:'w1'::uuid,true,null,'{}','[]') ->> 'status' as wd \gset
-- an unposted quick expense with the head marketing
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'marketing', 'test_printer', 210, 'cash', false, null, gen_random_uuid()) is not null as wq \gset
-- a customer with a due, one cash and one mobile collection (the receipts of phase 97 must treat them exactly as before)
insert into customers (mobile, name) values ('01800000988', 'test_customer_ba2');
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, customer_id, created_by)
  select 1, 987201, (now() at time zone 'Asia/Dhaka')::date, now(), '[]', 3000, 0, 3000, 'due', 'done', id, :'o' from customers where mobile='01800000988';
select collect_payment(gen_random_uuid(), 1, (select id from customers where mobile='01800000988'), '[{"mode":"cash","amount":400},{"mode":"mobile","amount":300,"wallet":"nagad","ref":"TX-BA"}]'::jsonb, 'test') is not null as wc \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":900}]'::jsonb,0,'[{"mode":"cash","amount":500},{"mode":"mobile","amount":400,"wallet":"bkash"}]'::jsonb,null,null,'retail',null,true) is not null as wsale \gset
