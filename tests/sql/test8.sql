\set ON_ERROR_STOP off
delete from sale_payments; delete from exceptions; delete from sales; delete from customers; truncate serials;
insert into user_locations values ('00000000-0000-0000-0000-000000000005',1) on conflict do nothing;
update profiles set status='active';
insert into location_settings (location_id,key,value) values (1,'discount_limit','50') on conflict (location_id,key) do update set value='50';
set role authenticated;
\echo --- shop2 = manager (POS approve); u5 = salesperson (enter only)
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
\echo T1 retail fully paid in cash, no customer
select record_sale2(gen_random_uuid(),1,'[{"amount":650,"name":"x"}]',0,'[{"mode":"cash","amount":650,"tendered":1000}]',null,null,'retail',null,true);
\echo T2 partial without customer -> refused ; with customer ok
select record_sale2(gen_random_uuid(),1,'[{"amount":650}]',0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,true);
select record_sale2(gen_random_uuid(),1,'[{"amount":650}]',0,'[{"mode":"cash","amount":300}]','+880 1712-345678','Karim','retail',null,true);
\echo T2b bad mobile / new customer without name
select record_sale2(gen_random_uuid(),1,'[{"amount":650}]',0,'[{"mode":"cash","amount":300}]','12345','X','retail',null,true);
select record_sale2(gen_random_uuid(),1,'[{"amount":10}]',0,'[]','01911222333',null,'retail',null,true);
\echo T3 split cash + bkash
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":200},{"mode":"mobile","wallet":"bkash","ref":"TX123","amount":300}]',null,null,'retail',null,true);
select pay_mode, paid, due_amount from sales order by receipt desc limit 1;
\echo T4 wholesale needs a customer even when paid
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',0,'[{"mode":"cash","amount":1000}]',null,null,'wholesale',null,true);
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',0,'[{"mode":"cash","amount":1000}]','01712345678',null,'wholesale',null,true);
select type from customers where mobile='01712345678';
\echo T5 overpaid
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]',0,'[{"mode":"cash","amount":150}]',null,null,'retail',null,true);
\echo T6 collect 200 (balance 350), overpay 500
select collect_payment(gen_random_uuid(),1,(select id from customers where mobile='01712345678'),'[{"mode":"cash","amount":200}]','part');
select collect_payment(gen_random_uuid(),1,(select id from customers where mobile='01712345678'),'[{"mode":"cash","amount":500}]',null);
\echo T7 dues and ledger
select name, mobile, balance, oldest from customer_dues();
select kind, ref, debit, credit, balance from customer_ledger((select id from customers where mobile='01712345678'));
\echo T8 custom line, override by salesperson refused, discount over limit by salesperson refused
select record_sale2(gen_random_uuid(),1,'[{"item_id":null,"name":"Special box","qty":2,"price":120}]',0,'[{"mode":"cash","amount":240}]',null,null,'retail',null,false);
select flag_code from exceptions order by id desc limit 1;
select record_sale2(gen_random_uuid(),1,(select jsonb_build_array(jsonb_build_object('item_id',id,'qty',1,'override',true,'price',1)) from items order by code limit 1),0,'[{"mode":"cash","amount":1}]',null,null,'retail',null,false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',80,'[{"mode":"cash","amount":420}]',null,null,'retail',null,true);
\echo T8b manager can: override, discount over limit (red exception)
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',80,'[{"mode":"cash","amount":420}]',null,null,'retail',null,true);
select flag_code, level from exceptions order by id desc limit 1;
\echo T9 credit limit 400: salesperson refused beyond, manager allowed with exception
reset role; update customers set credit_limit = 400 where mobile='01712345678'; set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":300}]',0,'[]','01712345678',null,'retail',null,true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":300}]',0,'[]','01712345678',null,'retail',null,true);
select flag_code from exceptions order by id desc limit 1;
\echo T10 find_customer, void effect
select find_customer('+8801712345678');
select void_sale((select id from sales where customer_id=(select id from customers where mobile='01712345678') and due_amount=300 order by receipt desc limit 1),'wrong');
select customer_balance((select id from customers where mobile='01712345678'));
select count(*) filter (where voided) as voided_payments from sale_payments;
\echo T11 payments summary
select * from payments_summary(current_date - 1) order by mode, kind;
\echo T12 idempotent resend
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2('33333333-3333-3333-3333-333333333333',1,'[{"amount":60}]',0,'[{"mode":"cash","amount":60}]',null,null,'retail',null,true);
select record_sale2('33333333-3333-3333-3333-333333333333',1,'[{"amount":60}]',0,'[{"mode":"cash","amount":60}]',null,null,'retail',null,true);
select count(*) from sales where client_id='33333333-3333-3333-3333-333333333333';
