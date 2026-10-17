-- Fixture for the phase 420-425 report suites (neutral test_* data only). Loaded with  \i tests/sql/p420_fixture.sql  from the repository root, as the database owner.
-- It walks one small business through the whole stock chain with the REAL functions:
--   opening -> purchase (posted + a draft + a voided one + a purchase return) -> transfer of raw material -> production (recipe run + a direct production)
--   -> transfers of finished goods (one received in full, one received short, one still in transit) -> sales (one voided, one beyond stock) -> refund
--   -> wastage -> stock counts -> closing.
-- Places used (rows of the shipped locations table): 7 = test store (godown), 6 = test factory, 1 / 3 / 4 = test outlets.
-- Users: owner (all rights), a storekeeper and a salesperson with no report grant.
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set x '00000000-0000-0000-0000-000000000006'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.run(p_key text, p_flt jsonb default '{}', p_grp text default null) returns jsonb language sql as $$ select public.report_run2(p_key, p_flt, p_grp, null, 1) $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.core(p_key text, p_flt jsonb default '{}') returns jsonb language sql security definer as $$ select public.report_run2_core(p_key, p_flt, null, null, 1) $$;
create or replace function tt.n(p_sql text) returns numeric language plpgsql security definer as $$ declare v numeric; begin execute p_sql into v; return v; end $$;
create or replace function tt.t(p_sql text) returns text language plpgsql security definer as $$ declare v text; begin execute p_sql into v; return v; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"test_owner"}'), (:'s','staff2@s.app','{"full_name":"test_sales"}'), (:'k','store3@s.app','{"full_name":"test_store"}'),
 (:'x','far6@s.app','{"full_name":"test_far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),(:'x','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',7),(:'x',3) on conflict do nothing;

-- items (all tracked). raw: flour, sugar, salt (salt is opened WITHOUT a cost); packaging: box; finished goods: sweet (shelf life 72 h), cake (no shelf-life rule), tea (resale)
insert into items (code,name_bn,name_en,category,unit,min_stock,tracked,is_active,sellable,sell_price,item_type) values
 ('test_raw_flour','test_ময়দা','test_flour','test_cat_raw','kg',20,true,true,false,null,'raw_material'),
 ('test_raw_sugar','test_চিনি','test_sugar','test_cat_raw','kg',10,true,true,false,null,'raw_material'),
 ('test_raw_salt','test_লবণ','test_salt','test_cat_raw','kg',null,true,true,false,null,'raw_material'),
 ('test_pack_box','test_বাক্স','test_box','test_cat_pack','pc',50,true,true,false,null,'packaging'),
 ('test_fg_sweet','test_মিষ্টি','test_sweet','test_cat_fg','kg',5,true,true,true,300,'finished_good'),
 ('test_fg_cake','test_কেক','test_cake','test_cat_fg','pc',2,true,true,true,500,'finished_good'),
 ('test_rs_tea','test_চা','test_tea','test_cat_resale','pc',null,true,true,true,20,'resale')
 on conflict (code) do nothing;
select id as i_fl from items where code='test_raw_flour' \gset
select id as i_su from items where code='test_raw_sugar' \gset
select id as i_sa from items where code='test_raw_salt' \gset
select id as i_bx from items where code='test_pack_box' \gset
select id as i_sw from items where code='test_fg_sweet' \gset
select id as i_ck from items where code='test_fg_cake' \gset
select id as i_te from items where code='test_rs_tea' \gset
insert into shelf_life_rules (item_id, value, unit) select :'i_sw'::uuid, 72, 'hours' where not exists (select 1 from shelf_life_rules where item_id = :'i_sw'::uuid);
insert into suppliers (name, credit_days) values ('test_sup_one', 30), ('test_sup_nocredit', null);
select id as su1 from suppliers where name='test_sup_one' \gset
select id as su2 from suppliers where name='test_sup_nocredit' \gset

set role authenticated; select tt.as(:'o');
-- 1. OPENING at the test store (7): flour 100 @40, sugar 50 @60, box 200 @5, salt 10 with NO cost
select stock_opening(:'i_fl',7,100,40,null,'test opening') is not null as o1 \gset
select stock_opening(:'i_su',7,50,60,null,'test opening') is not null as o2 \gset
select stock_opening(:'i_bx',7,200,5,null,'test opening') is not null as o3 \gset
select stock_opening(:'i_sa',7,10,null,null,'test opening, cost not known') is not null as o4 \gset
select stock_opening(:'i_te',1,40,12,null,'test opening') is not null as o5 \gset
-- (pb3 below stays a draft)
-- 2. PURCHASES at the store: one posted bill (flour 60 @42, sugar 20 @61, sugar 5 for a second supplier), a draft, one voided, one purchase return
select save_purchase(null,null,:'su1',7,'T-B1',tt.today()-6,format('[{"item_id":"%s","qty":60,"unit":"kg","unit_cost":42},{"item_id":"%s","qty":20,"unit":"kg","unit_cost":61}]',:'i_fl',:'i_su')::jsonb) ->> 'id' as pb1 \gset
select post_purchase(:'pb1'::uuid) is not null as p1 \gset
select save_purchase(null,null,:'su2',7,'T-B2',tt.today()-5,format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":60}]',:'i_su')::jsonb) ->> 'id' as pb2 \gset
select post_purchase(:'pb2'::uuid) is not null as p2 \gset
select save_purchase(null,null,:'su1',7,'T-B3',tt.today()-4,format('[{"item_id":"%s","qty":999,"unit":"kg","unit_cost":1}]',:'i_fl')::jsonb) ->> 'id' as pb3 \gset
select save_purchase(null,null,:'su1',7,'T-B4',tt.today()-4,format('[{"item_id":"%s","qty":888,"unit":"kg","unit_cost":1}]',:'i_fl')::jsonb) ->> 'id' as pb4 \gset
select post_purchase(:'pb4'::uuid) is not null as p4 \gset
select void_purchase(:'pb4'::uuid, 'test void') is not null as v4 \gset
select save_purchase(null,null,:'su1',7,'T-R1',tt.today()-3,format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":42}]',:'i_fl')::jsonb,0,null,null,'return',:'pb1'::uuid,'damaged') ->> 'id' as pr1 \gset
select post_purchase(:'pr1'::uuid) is not null as pr1p \gset
-- 3. TRANSFER of raw material store -> factory (received in full): flour 80, sugar 40, box 100
select stock_transfer(7,6,:'i_fl',80) ->> 'id' as t1 \gset
select stock_receive_transfer(:'t1'::uuid) is not null as t1r \gset
select stock_transfer(7,6,:'i_su',40) ->> 'id' as t2 \gset
select stock_receive_transfer(:'t2'::uuid) is not null as t2r \gset
select stock_transfer(7,6,:'i_bx',100) ->> 'id' as t3 \gset
select stock_receive_transfer(:'t3'::uuid) is not null as t3r \gset
-- 4. PRODUCTION at the factory (6): recipe run (5 batches of 10 kg sweet = 50 kg; 6 kg flour + 3 kg sugar per batch) and a direct production of 12 cakes (no shelf-life rule)
select recipe_save(null,:'i_sw'::uuid,10,null,'test recipe',jsonb_build_array(jsonb_build_object('ingredient_item_id',:'i_fl','qty',6,'waste_pct',0),jsonb_build_object('ingredient_item_id',:'i_su','qty',3,'waste_pct',0))) ->> 'id' as rc1 \gset
select production_post(6,:'rc1'::uuid,5,gen_random_uuid(),now()-interval '2 days','test run') ->> 'batch_id' as runb \gset
select stock_production_in(:'i_ck',6,12,now()-interval '1 day',null,'test cakes',gen_random_uuid()) ->> 'batch_id' as ckb \gset
-- 5. TRANSFERS of finished goods from the factory: 20 kg sweet to outlet 1 (received in full), 10 kg to outlet 3 (received 8 = short 2), 5 kg to outlet 4 (stays in transit); 8 cakes to outlet 1
select stock_transfer(6,1,:'i_sw',20) ->> 'id' as t4 \gset
select stock_receive_transfer(:'t4'::uuid) is not null as t4r \gset
select stock_transfer(6,3,:'i_sw',10) ->> 'id' as t5 \gset
select stock_receive_transfer(:'t5'::uuid, 8, 'test short') is not null as t5r \gset
select stock_transfer(6,4,:'i_sw',5) ->> 'id' as t6 \gset
select stock_transfer(6,1,:'i_ck',8) ->> 'id' as t7 \gset
select stock_receive_transfer(:'t7'::uuid) is not null as t7r \gset
select stock_transfer(7,1,:'i_bx',5) ->> 'id' as t8 \gset
select stock_cancel_transfer(:'t8'::uuid, 'test cancel') is not null as t8c \gset
reset role;
-- 6. SALES at outlet 1 (the sale trigger moves the stock): sweet 12 kg + tea 4; a second sale of sweet 3 kg that is then VOIDED; cakes 9 pc when only 8 are there (goes -1, oversold)
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,990001,tt.today(),now(),format('[{"item_id":"%s","qty":12,"price":300,"amount":3600,"unit":"kg","name":"test_sweet"},{"item_id":"%s","qty":4,"price":20,"amount":80,"unit":"pc","name":"test_tea"}]',:'i_sw',:'i_te')::jsonb,3680,0,3680,'cash',:'s',3680,'done');
select id as sale1 from sales where receipt=990001 \gset
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,990002,tt.today(),now(),format('[{"item_id":"%s","qty":3,"price":300,"amount":900,"unit":"kg","name":"test_sweet"}]',:'i_sw')::jsonb,900,0,900,'cash',:'s',900,'done');
select id as sale2 from sales where receipt=990002 \gset
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,990003,tt.today(),now(),format('[{"item_id":"%s","qty":9,"price":500,"amount":4500,"unit":"pc","name":"test_cake"}]',:'i_ck')::jsonb,4500,0,4500,'cash',:'s',4500,'done');
update sales set status='void' where id=:'sale2'::uuid;
set role authenticated; select tt.as(:'o');
-- 7. REFUND of 2 kg sweet from the first sale, reason damaged
select set_grant('sale_return','owner',true) is null as g1 \gset
select sale_return(null,:'sale1'::uuid,format('[{"item_id":"%s","qty":2}]',:'i_sw')::jsonb,'damaged','test refund','cash') is not null as rf \gset
-- 8. WASTAGE at outlet 1: sweet 1.5 expired, 0.5 broken
select stock_wastage(:'i_sw',1,1.5,'expired','test wastage') is not null as w1 \gset
select stock_wastage(:'i_sw',1,0.5,'broken','test wastage') is not null as w2 \gset
select stock_wastage(:'i_ck',6,1,'expired','test wastage in pieces') is not null as w3 \gset
-- 9. COUNTS: outlet 1 sweet counted 7.7 against the book 8.0 (RPC count adjust), store flour counted 1 kg less
select stock_count_adjust(:'i_sw',1,7.7,'test count') is not null as c1 \gset
select stock_count_adjust(:'i_fl',7,(select qty-1 from stock_balance where item_id=:'i_fl'::uuid and location_id=7),'test count flour') is not null as c2 \gset
select stock_count_adjust(:'i_te',1,38,'test count tea up') is not null as c3 \gset
select stock_count_adjust(:'i_sa',7,9,'test count salt, no cost') is not null as c4 \gset
reset role;
