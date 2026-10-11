\set ON_ERROR_STOP off
insert into user_locations values ('00000000-0000-0000-0000-000000000005',1) on conflict do nothing;
update profiles set status='active';
insert into user_roles values ('00000000-0000-0000-0000-000000000005','salesperson') on conflict do nothing;
set role authenticated;
\echo E1 salesperson discount refused; asks emergency; owner approves; works ONCE
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true);
select request_emergency('discount_over_limit',1,'{"discount":50}','customer is waiting, manager away') as req;
select request_emergency('sale_without_customer',1,'{}','x y z');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_emergency((select max(id) from emergency_requests),true,null);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) ->> 'total';
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true);
select status from emergency_requests order by id;
reset role; select flag_code, level from exceptions where flag_code='emergency_used'; set role authenticated;
\echo E2 rule off -> discount passes without grant ; owner-only set_rule
select set_rule('pos_discount_manager','false');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_rule('pos_discount_manager','false');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) ->> 'total';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_rule('pos_discount_manager','true'), set_rule('pos_credit_mode','"maybe"');
select set_rule('pos_offline_hours','-5');
\echo E3 grant to role salesperson then revoke
select set_grant('discount_over_limit','salesperson',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) ->> 'total';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_grant('discount_over_limit','salesperson',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true);
\echo E4 closed period: refused, emergency window, expiry
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select set_rule('period_closed_until','"2026-10-05"');
select set_rule('period_closed_until','"2026-02-30"');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select save_entry(null,'10-1',1,'2026-10-04','{}','[]');
select request_emergency('closed_period_edit',null,'{"date":"2026-10-04"}','late bank slip found');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_emergency((select max(id) from emergency_requests),true,'ok');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select save_entry(null,'10-1',1,'2026-10-04','{}','[]') ->> 'serial';
select save_entry(null,'10-1',1,'2026-10-03','{}','[]') ->> 'serial';
reset role; update emergency_requests set valid_until = now() - interval '1 minute' where grant_code='closed_period_edit'; set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select save_entry(null,'10-1',1,'2026-10-04','{}','[]');
select id, grant_code, status from my_emergency();
\echo E5 form access request for a form the cash controller cannot enter
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select save_entry(null,'06-3',1,'2026-10-12','{}','[]');
select request_emergency('form_access',1,'{"form":"06-3","action":"enter"}','need to log a PO');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_emergency((select max(id) from emergency_requests),true,null);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select save_entry(null,'06-3',1,'2026-10-12','{}','[]') ->> 'serial';
select save_entry(null,'06-2',1,'2026-10-12','{}','[]');
\echo E6 reject needs a note; cannot decide own; emergency_off for customer rule
select request_emergency('sale_without_customer',1,'{}','no mobile');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select request_emergency('discount_over_limit',1,'{}','second');
select decide_emergency((select max(id) from emergency_requests),false,null);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_emergency((select max(id) from emergency_requests),false,null);
select decide_emergency((select max(id) from emergency_requests),false,'not now');
\echo E7 paper no required rule
select set_rule('entry_paper_no_required','true');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select submit_entry((select id from entries where created_staff='shop2' order by serial limit 1));
