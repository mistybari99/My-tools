update settings set value='"2026-10-05"' where key='books_closed_until';
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
\echo manager: entry dated inside closed period refused; after the date allowed
select save_entry(null,'10-1',1,'2026-10-04','{}','[]');
select save_entry(null,'10-1',1,'2026-10-06','{}','[]');
\echo owner can write into the closed period
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select save_entry(null,'10-1',1,'2026-10-04','{}','[]');
\echo sale today is outside the closed period
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":50}]',0,'[{"mode":"cash","amount":50}]',null,null,'retail',null,true);
reset role; update settings set value='"2099-01-01"' where key='books_closed_until'; set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select record_sale2(gen_random_uuid(),1,'[{"amount":50}]',0,'[{"mode":"cash","amount":50}]',null,null,'retail',null,true);
