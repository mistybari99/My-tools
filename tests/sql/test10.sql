\set ON_ERROR_STOP off
insert into user_locations values ('00000000-0000-0000-0000-000000000005',1),('00000000-0000-0000-0000-000000000002',2) on conflict do nothing;
update profiles set status='active';
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
\echo M1 mobiles
select norm_mobile('+880 01712345678'), norm_mobile('0088 01712345678'), norm_mobile('008801712345678'), norm_mobile('১৭১২৩৪৫৬৭৮');
select norm_mobile('01712345678x');
select norm_mobile('0171234567');
\echo C1 due sale at loc1, credit limit 150 (owner sets), loc2 manager adds 100 more
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]',0,'[]','01711112222','Rina','retail',null,true) ->> 'due';
reset role; update customers set credit_limit=150; set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]',0,'[]','01711112222',null,'retail',null,true);
\echo C2 rounding
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":100.01}]',0.005,'[{"mode":"cash","amount":33.333},{"mode":"cash","amount":33.333},{"mode":"cash","amount":33.333}]','01733334444','Sadia','retail',null,true) ->> 'due';
\echo C3 collect: two payments resend with same client id counts once
select collect_payment('44444444-4444-4444-4444-444444444444',1,(select id from customers where mobile='01711112222'),'[{"mode":"cash","amount":10},{"mode":"mobile","wallet":"bkash","amount":10}]','x');
select collect_payment('44444444-4444-4444-4444-444444444444',1,(select id from customers where mobile='01711112222'),'[{"mode":"cash","amount":10},{"mode":"mobile","wallet":"bkash","amount":10}]','x');
select customer_balance(id) from customers where mobile='01711112222';
\echo C4 void a wrong collection (manager) then balance returns
select void_collection((select min(id) from sale_payments where kind='collection'),'wrong customer');
select customer_balance(id) from customers where mobile='01711112222';
\echo C5 FIFO oldest: old due 100 (days ago) then new sale fully paid -> oldest stays the old one
reset role; update sales set sale_date = current_date - 3, sold_at = now() - interval '3 days' where customer_id=(select id from customers where mobile='01711112222') and receipt=(select min(receipt) from sales where customer_id=(select id from customers where mobile='01711112222')); set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":60}]',0,'[{"mode":"cash","amount":60}]','01711112222',null,'retail',null,true) ->> 'due';
select name, balance, oldest from customer_dues() where mobile='01711112222';
\echo C6 discount with NO limit needs a manager (salesperson refused, manager ok)
reset role; delete from location_settings where key='discount_limit'; set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]',10,'[{"mode":"cash","amount":90}]',null,null,'retail',null,true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]',10,'[{"mode":"cash","amount":90}]',null,null,'retail',null,true) ->> 'total';
\echo L1 malformed lock date does not lock anyone out
reset role; update settings set value='"2026-02-30"' where key='books_closed_until'; set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":5}]',0,'[{"mode":"cash","amount":5}]',null,null,'retail',null,true) ->> 'total';
\echo N1 very long paper number does not break the audit
select save_entry(null,'10-1',1,'2026-10-20','{"paper_no":"123456789012345678901234"}','[]');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select number_audit('10-1',1);
select count(*) from number_audit_summary();
