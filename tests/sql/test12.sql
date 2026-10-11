\set ON_ERROR_STOP off
insert into user_locations values ('00000000-0000-0000-0000-000000000005',1) on conflict do nothing;
update profiles set status='active';
insert into user_roles values ('00000000-0000-0000-0000-000000000005','salesperson') on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
\echo B1 ITEM_COST / unknown form / bad action refused for form_access
select request_emergency('form_access',null,'{"form":"ITEM_COST"}','need cost');
select request_emergency('form_access',null,'{"form":"NOPE"}','need cost');
select request_emergency('form_access',null,'{"form":"06-3","action":"approve"}','need cost');
select request_emergency('form_access',null,'{"form":"06-3"}','need to log a PO') as ok;
\echo B2 loc_access with bad location / bad context refused
select request_emergency('loc_access',99,'{}','visit shop 99');
select request_emergency('discount_over_limit',1,'{}','no amount here');
\echo B3 amount binding: approved for discount 50, used for 80 -> refused; for 50 -> ok
select request_emergency('discount_over_limit',1,'{"amount":50}','customer waiting') as r1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_emergency(:r1,true,null);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',80,'[{"mode":"cash","amount":420}]',null,null,'retail',null,true);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) ->> 'total';
\echo B4 closed period approval is bound to the date; window use leaves an exception
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_rule('period_closed_until','"2026-10-05"');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select request_emergency('closed_period_edit',null,'{"date":"2026-10-03"}','late slip') as r2 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_emergency(:r2,true,null);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select save_entry(null,'10-1',1,'2026-10-04','{}','[]');
select save_entry(null,'10-1',1,'2026-10-03','{}','[]') ->> 'serial';
reset role; select flag_code, form_code from exceptions where flag_code='emergency_window_used'; select used_at is not null as stamped from emergency_requests where id=:r2; set role authenticated;
\echo B5 due without a customer when the rule is off -> exception
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_rule('pos_customer_on_due','false');
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,true) ->> 'due';
reset role; select flag_code from exceptions where flag_code='unattributed_due'; set role authenticated;
\echo B6 bounds on number rules
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_rule('pos_offline_hours','100000000000');
select set_rule('em_minutes','0');
select set_rule('em_minutes','45');
\echo B7 internal functions not callable by staff
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select use_emergency('discount_over_limit',1,'x');
select rule_ok('sale_void',1);
\echo B8 two price overrides in one sale use one approval
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select request_emergency('price_override',1,'{}','shop fixing prices') as r3 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_emergency(:r3,true,null);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,(select jsonb_agg(jsonb_build_object('item_id',id,'qty',1,'override',true,'price',1)) from (select id from items order by code limit 2) x),0,'[{"mode":"cash","amount":2}]',null,null,'retail',null,false) ->> 'total';
