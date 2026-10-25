-- FRESH DB ONLY. Phase 436 tests (RPT-B3: audit line for the CSV export of the new reports). Needs phases 8 to 99 and 430 to 436.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase436_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set u '00000000-0000-0000-0000-000000000005'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.errmsg(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return null; exception when others then return sqlerrm; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_sales@s.app','{"full_name":"test_sales"}'), (:'k','test_store@s.app','{"full_name":"test_store"}'), (:'u','test_buyer@s.app','{"full_name":"test_buyer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),(:'u','purchasing') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'u',1) on conflict do nothing;
insert into rule_grants (grant_code, role_code) values ('report_stock','storekeeper'), ('report_purchase','purchasing'), ('export_data','storekeeper'), ('export_data','purchasing') on conflict do nothing;

select tt.chk('T0 callable by authenticated, not anon', has_function_privilege('authenticated','public.rb3_log_export(text,text,jsonb,int)','execute') and not has_function_privilege('anon','public.rb3_log_export(text,text,jsonb,int)','execute'));
select tt.as(:'o'); set role authenticated;
select rb3_log_export('trace', 'csv', '{"batch":1}'::jsonb, 12) is null as e1 \gset
reset role;
select tt.chk('T1 the owner exports: one audit line with the kind and the row count', (select count(*) from audit_log where action='export' and record_id='trace' and (detail->>'rows')::int=12 and detail->>'kind'='csv')=1);
select tt.as(:'k'); set role authenticated;
select tt.chk('T2 a storekeeper with the stock report right and export_data may export stock reports', tt.errmsg($$select rb3_log_export('yield', 'csv', null, 3)$$) is null);
select tt.err('T2 but not purchase reports (no purchase report right)', $$select rb3_log_export('supplier_returns', 'csv', null, 3)$$, 'not allowed');
reset role; select tt.as(:'u'); set role authenticated;
select tt.chk('T3 a buyer with the purchase report right and export_data may export the returns report', tt.errmsg($$select rb3_log_export('supplier_returns', 'csv', null, 3)$$) is null);
select tt.chk('T3 the buyer holds the cost right through the role, so the variance export is allowed', tt.errmsg($$select rb3_log_export('price_variance', 'csv', null, 3)$$) is null);
select tt.err('T3 a stock report is not open to a buyer without the stock report right', $$select rb3_log_export('stockout', 'csv', null, 3)$$, 'not allowed');
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T4 a salesperson cannot export (no export_data)', $$select rb3_log_export('stockout', 'csv', null, 3)$$, 'not allowed');
reset role; select tt.as(:'o'); set role authenticated;
select tt.err('T5 unknown report key refused', $$select rb3_log_export('nonsense', 'csv', null, 1)$$, 'unknown_report');
select tt.err('T5 bad kind refused', $$select rb3_log_export('trace', 'CSV; drop', null, 1)$$, 'bad_kind');
reset role;

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
