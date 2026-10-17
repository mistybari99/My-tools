-- RPT-B4 fixture: the whole chain recipe -> production -> dispatch -> sale made through the real functions. Test data only (test_* names).
-- Needs a database built through phase 99 plus supabase/phase404.sql and phase405.sql (the 406+ tests add their own phases on top). Places: 5 = factory, 1 and 2 = showrooms.
-- Hand-computed numbers (D = today in Dhaka):
--   items      : RB4-RM milk (kg) 100 kg opening at 60 | RB4-SG sugar (kg) 50 kg opening at 80 | RB4-FG sweet (kg), selling price 200
--   recipe     : 1 batch = 10 kg RB4-FG from 6 kg milk + 3 kg sugar (no waste %)
--   standard price list (item_costs): milk 55, sugar 85
--   run 1 (D-3): 2 batches, the person typed the real output 18 kg -> booked milk 12 (720), sugar 6 (480), material 1200, standard output 20, yield -10 %, unit cost 66.666667, std cost 60
--   run 2 (D-1): 1 batch, no actual output typed -> booked milk 6 (360), sugar 3 (240), material 600, output 10, unit cost 60 (run 3 does not exist)
--   real use   : run 1 milk 13 (booked 12), sugar 6 (booked 6); run 2 nothing recorded
--   loss       : run 1 reject 1 kg 'burnt', rework 0.5 kg 'broken'; run 2 "checked, none"
--   dispatch   : 15 kg place 5 -> 1 (received 14, short 1) | 2 kg place 5 -> 2 (still in transit) | FG on hand at 5: 28 - 15 - 2 - 1 (wastage 'spoiled', batch of run 2) = 10
--   sale       : place 1 sells 4 kg of RB4-FG at 200 = 800 cash today
--   plans      : A = D-3, place 5, 2 batches (20 kg) | C = D+2, place 5, 1 batch (10 kg), nothing made
--   orders     : O1 place 5 for outlet 1, 25 kg, due D-1, run 1 linked (18 made) | O2 10 kg due D+4, run 2 linked (10 made) | O3 5 kg due D+5, nothing linked
--   variance run 1 (price vs list, usage, yield): price (60-55)*13 + (80-85)*6 = 35 | usage (13-12)*55 = 55 | yield (20-18) * (12*55+6*85)/20 = 2 * 58.5 = 117 | total 207 = 1260 - 18*58.5
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-000000000b40'
\set fac '00000000-0000-0000-0000-000000000b41'
\set shop '00000000-0000-0000-0000-000000000b42'
\set rep '00000000-0000-0000-0000-000000000b43'
create schema if not exists tt;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create table if not exists tt.res (name text, ok boolean);
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.near(a numeric, b numeric, tol numeric default 0.01) returns boolean language sql immutable as $$ select a is not null and b is not null and abs(a - b) <= tol $$;
create or replace function tt.n(p_j jsonb, p_k text) returns numeric language sql immutable as $$ select (p_j ->> p_k)::numeric $$;
-- one row of a report answer where the key column equals the value
create or replace function tt.row(p_j jsonb, p_key text, p_val text) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(p_j -> 'rows') e where e ->> p_key = p_val limit 1 $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
truncate tt.res;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner_rb4@s.app','{"full_name":"test_owner"}'), (:'fac','test_factory_rb4@s.app','{"full_name":"test_factory"}'),
 (:'shop','test_shop_rb4@s.app','{"full_name":"test_shop"}'), (:'rep','test_report_rb4@s.app','{"full_name":"test_report"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fac','factory_incharge'),(:'shop','salesperson'),(:'rep','salesperson') on conflict do nothing;
insert into user_locations values (:'fac',5),(:'shop',1),(:'rep',5),(:'rep',1) on conflict do nothing;
insert into user_grants (user_id, grant_code) values (:'rep','report_stock') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);

insert into items (code,name_bn,name_en,unit,base_unit,sell_price,tracked,item_type,category) values
 ('RB4-RM','test_milk','test_milk','kg','kg',null,true,'raw_material','test_raw'),
 ('RB4-SG','test_sugar','test_sugar','kg','kg',null,true,'raw_material','test_raw'),
 ('RB4-FG','test_sweet','test_sweet','kg','kg',200,true,'finished_good','test_sweet');
select id as i_rm from items where code='RB4-RM' \gset
select id as i_sg from items where code='RB4-SG' \gset
select id as i_fg from items where code='RB4-FG' \gset
insert into item_costs (item_id, cost_price) values (:'i_rm'::uuid, 55), (:'i_sg'::uuid, 85) on conflict (item_id) do update set cost_price = excluded.cost_price;
select stock_opening(:'i_rm'::uuid,5,100,60) is not null as w_o1 \gset
select stock_opening(:'i_sg'::uuid,5,50,80) is not null as w_o2 \gset
select (recipe_save(null, :'i_fg'::uuid, 10, null, 'rb4 v1', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'i_rm','qty',6,'waste_pct',0), jsonb_build_object('ingredient_item_id',:'i_sg','qty',3,'waste_pct',0)))->>'id')::uuid as rc \gset
select production_post(5, :'rc'::uuid, 2, gen_random_uuid(), now() - interval '3 days', 'test run 1', 18::numeric) ->> 'run_id' as run1 \gset
select production_post(5, :'rc'::uuid, 1, gen_random_uuid(), now() - interval '1 day', 'test run 2') ->> 'run_id' as run2 \gset
select batch_id as b2 from production_runs where id = :'run2'::uuid \gset
select stock_transfer(5, 1, :'i_fg'::uuid, 15, null, 'test dispatch 1', gen_random_uuid()) ->> 'id' as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 14, 'test short by 1') is not null as w_r1 \gset
select stock_transfer(5, 2, :'i_fg'::uuid, 2, null, 'test dispatch 2', gen_random_uuid()) ->> 'id' as t2 \gset
select stock_wastage(:'i_fg'::uuid, 5, 1, 'spoiled', 'test waste', null, null, gen_random_uuid(), :'b2'::bigint) is not null as w_w \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":200}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":800}]','','','retail',null,false)->>'id' as s1 \gset
select :'run1' as run1, :'run2' as run2;
