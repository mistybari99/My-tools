-- RPT-C3 fixture (phases 458-468), loaded AFTER tests/sql/w1d_fixture.sql (owner 092, locations 1 and 2, items W1D-FG / W1D-RM, a production run, one sale of 400, stock, a bill).
-- Adds the records the marketing, audit and planning reports read. Test data only (test_* names). Idempotent per database (the marker row tt.rptc3).
-- Hand-computed numbers (place 1):
--   campaigns   test_alpha_promo (start today-10, end today+10, budget 1000) and test_beta_offer (no dates, no budget)
--   18-1 sheet  line 1: head 1, campaign list = test_alpha_promo, 300 paid from bank | line 2: head 5, free text "test_beta_offer", 200 paid from mobile
--               line 3: head 2, no campaign, 100 from imprest | line 4: head 2, no campaign, 80 value without payment (a sample, nonpay)
--   sales       S1  2 x W1D-FG @100 = 200 cash, tagged test_alpha_promo with code TESTOFFER10  | S2  2 x 100 less discount 20 = 180 cash, tagged test_beta_offer
--               S3  1 x 100 cash, no tag | S4  customer test_customer_c3 buys 1 x 100 on a test_alpha_promo tag
--   cost        W1D-FG costs 14 (from the production run), so S1 contributes 200 - 28 = 172, S2 (180/200 x 200 = 180) - 28 = 152 on 2 units
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000092'
select set_config('request.jwt.claim.sub', :'o', false);
create schema if not exists tt;
create table if not exists tt.rptc3 (k text primary key, v text);
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
select not exists (select 1 from tt.rptc3 where k = 'loaded') as c3_fresh \gset
\if :c3_fresh
insert into tt.rptc3 values ('loaded', '1');
select mkt_campaign_save(null, jsonb_build_object('name_bn','test_alpha_promo','name_en','test_alpha_promo','start',tt.today()-10,'end',tt.today()+10,'budget','1000','channel','test_channel')) ->> 'value_code' as ca \gset
select mkt_campaign_save(null, jsonb_build_object('name_bn','test_beta_offer','name_en','test_beta_offer','force',true)) ->> 'value_code' as cb \gset
insert into tt.rptc3 values ('ca', :'ca'), ('cb', :'cb');
-- the 18-1 sheet (approved)
select save_entry(null,'18-1',1,tt.today(), jsonb_build_object('lines', jsonb_build_array(
  jsonb_build_object('date',tt.today()::text,'head','1','campaign_id',:'ca','amt','300','source','bank','receipt','TEST-R1'),
  jsonb_build_object('date',tt.today()::text,'head','5','campaign','test_beta_offer','amt','200','source','mobile'),
  jsonb_build_object('date',tt.today()::text,'head','2','amt','100','source','imprest'),
  jsonb_build_object('date',tt.today()::text,'head','2','nonpay','80'))), '[]') ->> 'id' as m1 \gset
select submit_entry(:'m1'::uuid) is not null as m1s \gset
select decide_entry(:'m1'::uuid, true, null, '{}', '[]') ->> 'status' as m1d \gset
insert into tt.rptc3 values ('m1', :'m1');
-- customers and sales (W1D-FG costs 14, W1D-RM costs 20)
insert into item_costs (item_id, cost_price) select id, 14 from items where code = 'W1D-FG' on conflict (item_id) do update set cost_price = 14;
insert into customers (mobile, name, source) values ('01800000777', 'test_customer_c3', 'test_alpha_promo'), ('01800000778', 'test_customer_c3b', null);
select id as cu1 from customers where mobile = '01800000777' \gset
select id as fg from items where code = 'W1D-FG' \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false)->>'id' as s1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'fg')::jsonb,20,'[{"mode":"cash","amount":180}]',null,null,'retail',null,false)->>'id' as s2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as s3 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'fg')::jsonb,0,'[{"mode":"cash","amount":100}]','01800000777','test_customer_c3','retail',null,false)->>'id' as s4 \gset
select mkt_tag_sale(:'s1'::uuid, :'ca', 'testoffer10') ->> 'ok' as t1 \gset
select mkt_tag_sale(:'s2'::uuid, :'cb', null) ->> 'ok' as t2 \gset
select mkt_tag_sale(:'s4'::uuid, :'ca', null) ->> 'ok' as t4 \gset
insert into tt.rptc3 values ('s1', :'s1'), ('s2', :'s2'), ('s3', :'s3'), ('s4', :'s4'), ('cu1', :'cu1');
\endif
select 'c3 fixture ready' as ready;
