-- CRM-B before/after fixture (on top of tests/sql/p87_fixture.sql, owner ...0987): customers with sales, a due, a duplicate pair. Test data only (test_* names).
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000987', false);
select (record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":1200}]','01760600001','test_ba_ali rahman','retail',null,true)) is not null as s1 \gset
select (record_sale2(gen_random_uuid(),1,'[{"amount":900}]',0,'[{"mode":"cash","amount":300}]','01760600002','TEST_BA ali-rahman','retail',null,true)) is not null as s2 \gset
select (record_sale2(gen_random_uuid(),2,'[{"amount":400}]',0,'[{"mode":"mobile","wallet":"bkash","amount":400}]','01760600003','test_ba_other','retail',null,true)) is not null as s3 \gset
update customers set address='test road 1', birthday='1990-05-05', whatsapp='01760600009' where mobile in ('01760600001','01760600002');
select acct_post_pending(false) ->> 'posted' as posted2 \gset
select :'posted2' as posted_after_customers;
