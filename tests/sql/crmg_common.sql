-- CRM-G test fixture shared by supabase/phase323_test.sql .. phase327_test.sql (included with \ir). Test data only: every name starts test_.
-- A fresh database built through phase 98 plus the CRM-G phases under test. Safe to run twice (inserts use on conflict do nothing).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000003201'
\set u_m1 '00000000-0000-0000-0000-000000003202'
\set u_s1 '00000000-0000-0000-0000-000000003203'
\set u_s1b '00000000-0000-0000-0000-000000003204'
\set u_s2 '00000000-0000-0000-0000-000000003205'
\set u_m2 '00000000-0000-0000-0000-000000003206'
\set u_x '00000000-0000-0000-0000-000000003207'
\set u_hq '00000000-0000-0000-0000-000000003208'
\set u_bot '00000000-0000-0000-0000-000000003209'
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
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$
declare r text; begin execute p_sql into r; return r; end $$;       -- a read as the table owner (the CRM tables are closed to browser roles)
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
create or replace function tt.books() returns text language sql security definer as $$
  select (select count(*) from public.journal_entries) || '/' || (select count(*) from public.journal_lines) || '/' || (select count(*) from public.sales) || '/' || (select count(*) from public.sale_payments)
      || '/' || (select count(*) from public.stock_ledger) || '/' || (select count(*) from public.cash_moves) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner_crmg@s.app','{"full_name":"test_owner_crmg"}'), (:'u_m1','test_mgr1_crmg@s.app','{"full_name":"test_mgr1_crmg"}'), (:'u_s1','test_sales1_crmg@s.app','{"full_name":"test_sales1_crmg"}'),
 (:'u_s1b','test_sales1b_crmg@s.app','{"full_name":"test_sales1b_crmg"}'), (:'u_s2','test_sales2_crmg@s.app','{"full_name":"test_sales2_crmg"}'), (:'u_m2','test_mgr2_crmg@s.app','{"full_name":"test_mgr2_crmg"}'),
 (:'u_x','test_nobody_crmg@s.app','{"full_name":"test_nobody_crmg"}'), (:'u_hq','test_head_crmg@s.app','{"full_name":"test_head_crmg"}'), (:'u_bot','test_bot_crmg@s.app','{"full_name":"test_bot_crmg"}') on conflict do nothing;
update profiles set status = 'active' where id in (:'u_o', :'u_m1', :'u_s1', :'u_s1b', :'u_s2', :'u_m2', :'u_x', :'u_hq');       -- the bot stays unapproved on purpose (as in the notify setup)
insert into user_roles values (:'u_o','owner'), (:'u_m1','showroom_manager'), (:'u_s1','salesperson'), (:'u_s1b','salesperson'), (:'u_s2','salesperson'), (:'u_m2','showroom_manager'), (:'u_hq','management') on conflict do nothing;
insert into user_locations values (:'u_m1',1), (:'u_s1',1), (:'u_s1b',1), (:'u_s2',2), (:'u_m2',2) on conflict do nothing;
insert into ops_accounts (user_id, purpose) values (:'u_bot', 'notify') on conflict do nothing;
-- the rights are given by the owner, never by default
insert into user_grants (user_id, grant_code, location_id) select :'u_m1', g, null from unnest(array['crm_lead_manage', 'crm_task_assign']) g on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) select :'u_m2', g, null from unnest(array['crm_lead_manage']) g on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('test_crmg_a', 'test_crmg_a', 'test_crmg_a', 'kg', 'kg', 'finished_good', false, 100), ('test_crmg_b', 'test_crmg_b', 'test_crmg_b', 'pc', 'pc', 'finished_good', false, 250),
 ('test_crmg_np', 'test_crmg_np', 'test_crmg_np', 'pc', 'pc', 'finished_good', false, null) on conflict do nothing;
select id as ia from items where code = 'test_crmg_a' \gset
select id as ib from items where code = 'test_crmg_b' \gset
select id as inp from items where code = 'test_crmg_np' \gset
select id as ch1 from sales_channels where code = 'test_crmg_ch' \gset
insert into sales_channels (code, kind, name_bn, location_id, active) select 'test_crmg_ch', 'phone', 'test_crmg_ch', null, true where not exists (select 1 from sales_channels where code = 'test_crmg_ch');
select id as ch1 from sales_channels where code = 'test_crmg_ch' \gset
