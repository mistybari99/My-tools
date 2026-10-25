-- X6 test head: result helpers and test users (all test_*). Included after tests/sql/w1d_fixture.sql by supabase/phase53x_test.sql.
\set ON_ERROR_STOP on
\set mgr '00000000-0000-0000-0000-000000000a06'
\set vw  '00000000-0000-0000-0000-000000000b06'
\set nb  '00000000-0000-0000-0000-000000000c06'
create schema if not exists mt;
create table if not exists mt.res (name text, ok boolean);
create or replace function mt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function mt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into mt.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function mt.err(p_name text, p_sql text, p_msg text) returns void language plpgsql as $$
begin execute p_sql; perform mt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform mt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function mt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema mt to authenticated, anon; grant execute on all functions in schema mt to authenticated, anon;
grant select, insert on mt.res to authenticated, anon;
insert into auth.users (id, email, raw_user_meta_data) values
 (:'mgr', 'test_mgr_x6@s.app', '{"full_name":"test_mgr"}'), (:'vw', 'test_vw_x6@s.app', '{"full_name":"test_vw"}'), (:'nb', 'test_nb_x6@s.app', '{"full_name":"test_nb"}') on conflict do nothing;
update profiles set status = 'active';
insert into user_roles values (:'mgr', 'salesperson'), (:'vw', 'salesperson'), (:'nb', 'salesperson') on conflict do nothing;
insert into user_locations values (:'mgr', 1), (:'vw', 1), (:'nb', 1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'mgr', 'market_manage', null), (:'vw', 'market_view', null) on conflict do nothing;
