-- RPT-C3 test head: the tt helpers + the shared fixtures. Included by supabase/phase458_test.sql .. phase468_test.sql with  \ir ../tests/sql/rptc3_head.sql
-- Users (all test_*): o = owner 092, acc = accounts manager 192 (management role, accounts_manage + accounts_view), st = salesperson 292 (place 1),
--                     rm = report_marketing holder 392 (place 1), nb = nobody 492 (no grant, no role), ex = export_data holder 592 (report_marketing too)
\set ON_ERROR_STOP on
\ir w1d_fixture.sql
\ir rptc3_fixture.sql
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000092'
\set u_acc '00000000-0000-0000-0000-000000000192'
\set u_st '00000000-0000-0000-0000-000000000292'
\set u_rm '00000000-0000-0000-0000-000000000392'
\set u_nb '00000000-0000-0000-0000-000000000492'
\set u_ex '00000000-0000-0000-0000-000000000592'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.k(p_k text) returns text language sql stable as $$ select v from tt.rptc3 where k = p_k $$;
create or replace function tt.n(p jsonb, k text) returns numeric language sql immutable as $$ select (p ->> k)::numeric $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon; grant select on tt.rptc3 to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_rm','test_rm_c3@s.app','{"full_name":"test_rm"}'), (:'u_nb','test_nb_c3@s.app','{"full_name":"test_nb"}'), (:'u_ex','test_ex_c3@s.app','{"full_name":"test_ex"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_rm','salesperson'),(:'u_nb','salesperson'),(:'u_ex','salesperson') on conflict do nothing;
insert into user_locations values (:'u_rm',1),(:'u_nb',1),(:'u_ex',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_rm','report_marketing',null),(:'u_ex','report_marketing',null),(:'u_ex','export_data',null) on conflict do nothing;
truncate tt.res;
