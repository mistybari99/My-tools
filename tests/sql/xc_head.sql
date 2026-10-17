-- XC test head (phases 550-554): the tt helpers, one owner and one staff user (both test_* names), and the test fixture helpers.
-- Included by supabase/phase55x_test.sql with  \ir ../tests/sql/xc_head.sql . Test data only; a throwaway database, never the live project.
-- Fixture writes use session_replication_role = replica, so the sale and payment triggers do not run while the test rows are made; the code under test runs normally.
\set ON_ERROR_STOP on
\set o '00000000-0000-0000-0000-00000000a001'
\set st '00000000-0000-0000-0000-00000000a002'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.summary() returns void language plpgsql as $$
declare a int; b int; begin select count(*) filter (where ok), count(*) into a, b from tt.res; raise notice 'RESULT % of % passed', a, b; end $$;
grant usage on schema tt to authenticated, anon;
grant execute on all functions in schema tt to authenticated, anon;
grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id, email, raw_user_meta_data) values
  (:'o', 'test_owner_xc@s.app', '{"full_name":"test_owner"}'), (:'st', 'test_staff_xc@s.app', '{"full_name":"test_staff"}') on conflict do nothing;
update profiles set status = 'active';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
insert into user_locations values (:'o', 1), (:'o', 2), (:'o', 3), (:'o', 4) on conflict do nothing;
insert into user_locations values (:'st', 1) on conflict do nothing;
truncate tt.res;
create or replace function tt.n(p jsonb, k text) returns numeric language sql immutable as $$ select (p ->> k)::numeric $$;
