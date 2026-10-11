\set ON_ERROR_STOP off
insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000001','owner1@s.app','{"full_name":"Owner"}'),
 ('00000000-0000-0000-0000-000000000002','shop2@s.app','{"full_name":"Shop Mgr"}'),
 ('00000000-0000-0000-0000-000000000003','cash3@s.app','{"full_name":"Cash Ctl"}'),
 ('00000000-0000-0000-0000-000000000004','mgmt4@s.app','{"full_name":"Management"}'),
 ('00000000-0000-0000-0000-000000000005','shop5@s.app','{"full_name":"Other Shop"}');
update profiles set status='active' where staff_id<>'owner1';
insert into user_roles values ('00000000-0000-0000-0000-000000000002','showroom_manager'),('00000000-0000-0000-0000-000000000003','cash_controller'),('00000000-0000-0000-0000-000000000004','management'),('00000000-0000-0000-0000-000000000005','showroom_manager');
insert into user_locations values ('00000000-0000-0000-0000-000000000002',1),('00000000-0000-0000-0000-000000000003',1),('00000000-0000-0000-0000-000000000005',2);
\echo 'T1 maker saves a new draft; other-location maker blocked'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select save_entry(null,'10-1',1,'2026-10-12','{"amount":1000}','[]');
select save_entry(null,'10-1',2,'2026-10-12','{"amount":1}','[]');
select save_entry(null,'06-3',1,'2026-10-12','{}','[]');
select serial, status from entries;
\echo 'T2 filling a blank is free; overwriting needs note'
select save_entry((select id from entries limit 1),'10-1',1,'2026-10-12','{"amount":1000,"carrier":"Rafiq"}','[]');
select save_entry((select id from entries limit 1),'10-1',1,'2026-10-12','{"amount":1200,"carrier":"Rafiq"}','[]');
select save_entry((select id from entries limit 1),'10-1',1,'2026-10-12','{"amount":1200,"carrier":"Rafiq"}','[]','counted again');
select data from entries limit 1;
select count(*) as corrections_logged from corrections;
\echo 'T3 serial increments'
select save_entry(null,'10-1',1,'2026-10-12','{}','[]');
select serial from entries order by serial;
\echo 'T4 red flag blocks submit; release request; owner approves; submit; exceptions created'
select save_entry((select id from entries where serial=2),'10-1',1,'2026-10-12','{"x":1}','[{"code":"cash_short","level":"red","amount":-150,"text":{"bn":"ক্যাশ কম","en":"Cash short"}},{"code":"price_gap","level":"yellow","amount":5,"text":{"en":"gap"}}]');
select submit_entry((select id from entries where serial=2));
select request_release((select id from entries where serial=2),'cash_short','');
select request_release((select id from entries where serial=2),'cash_short','count error, recounted twice');
select request_release((select id from entries where serial=2),'cash_short','again');
reset role;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
select decide_release(1,true);
reset role;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select decide_release(1,true,'ok');
reset role;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select submit_entry((select id from entries where serial=2));
select count(*) as exceptions_made from exceptions;
select save_entry((select id from entries where serial=2),'10-1',1,'2026-10-12','{}','[]');
reset role;
\echo 'T5 approve: maker cannot; cash controller can (10-1 approve); locked afterwards'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select decide_entry((select id from entries where serial=2),true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select decide_entry((select id from entries where serial=2),false);
select decide_entry((select id from entries where serial=2),true,'ok');
select status from entries where serial=2;
select count(*) as visible_to_cash_controller from entries;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select count(*) as visible_to_other_location_shop from entries;
reset role;
\echo 'T6 reopen: maker needs note; approved entry only owner'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select reopen_entry((select id from entries where serial=2),'');
select reopen_entry((select id from entries where serial=2),'please');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select reopen_entry((select id from entries where serial=2),'owner fix');
select status from entries where serial=2;
reset role;
\echo 'T7 exceptions: shop cannot see; owner resolves needs note'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select count(*) as shop_sees_exceptions from exceptions;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select resolve_exception(1,'');
select resolve_exception(1,'checked with the manager');
select status from exceptions where id=1;
reset role;
\echo 'T8 jsonb_overwrites unit checks'
select jsonb_overwrites('{"a":"x"}','{"a":"x","b":1}') f1, jsonb_overwrites('{"a":"x"}','{"a":"y"}') t1, jsonb_overwrites('{"a":""}','{"a":"y"}') f2,
 jsonb_overwrites('{"r":[{"q":1},{"q":2}]}','{"r":[{"q":1}]}') t2, jsonb_overwrites('{"r":[{"q":1}]}','{"r":[{"q":1},{"q":3}]}') f3, jsonb_overwrites('{"a":"x"}','{}') t3;
\echo 'T9 audit rows'
select count(*) filter (where action='status') as status_logs from audit_log where table_name='entries';
