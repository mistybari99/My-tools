-- RPT-C2 shared test fixture (neutral test_* data only). Loaded with \ir by supabase/phase445_test.sql .. phase457_test.sql on a database built through phase99 + the C2 phases under test.
-- Users: o owner | m manager place 1 | p salesperson place 1 | x manager place 2 | c manager place 1 + grant cash_move | r report-only (view_reports grant, no POS role) | k storekeeper place 1 (no POS)
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-0000000c2001'
\set m '00000000-0000-0000-0000-0000000c2002'
\set p '00000000-0000-0000-0000-0000000c2003'
\set x '00000000-0000-0000-0000-0000000c2004'
\set c '00000000-0000-0000-0000-0000000c2005'
\set r '00000000-0000-0000-0000-0000000c2006'
\set k '00000000-0000-0000-0000-0000000c2007'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'m','test_mgr1@s.app','{"full_name":"test_mgr1"}'), (:'p','test_sales1@s.app','{"full_name":"test_sales1"}'),
 (:'x','test_mgr2@s.app','{"full_name":"test_mgr2"}'), (:'c','test_cash1@s.app','{"full_name":"test_cash1"}'), (:'r','test_report1@s.app','{"full_name":"test_report1"}'),
 (:'k','test_store1@s.app','{"full_name":"test_store1"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'m','showroom_manager'),(:'p','salesperson'),(:'x','showroom_manager'),(:'c','showroom_manager'),(:'r','storekeeper'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'m',1),(:'p',1),(:'x',2),(:'c',1),(:'r',1),(:'k',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'c','cash_move',1),(:'r','view_reports',null) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('TST-A','test_item_a','test_item_a','kg','kg','finished_good',true,100), ('TST-B','test_item_b','test_item_b','kg','kg','finished_good',true,50);
select id as ia from items where code='TST-A' \gset
select id as ib from items where code='TST-B' \gset
select tt.as(:'o');
select stock_opening(:'ia'::uuid, 1, 200, 40, null, 'seed') is not null as op1 \gset
select stock_opening(:'ib'::uuid, 1, 200, 20, null, 'seed') is not null as op2 \gset
select set_rule('online_orders_on','true') is null as r_oo \gset
