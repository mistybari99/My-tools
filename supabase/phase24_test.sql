-- FRESH DB ONLY. Phase 24 (report engine 3) tests.
--   ORDER="phase8 ... phase23 phase24" bash tests/sql/build_fresh_db.sh <db> ; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase24_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set r '00000000-0000-0000-0000-000000000003'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'r','rep3@s.app','{"full_name":"Reporter"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'r','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'r',1),(:'r',2) on conflict do nothing;

-- demo reports (test only)
create or replace function public._r3q_demo_loc(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('location_id', l.id, 'code', l.code, 'n', l.id * 2, 'amt', l.id * 100.5) from public.locations l where l.id = any (locs); $$;
insert into report_defs3 (key, code, grp, name_bn, name_en, cols, tot, sort_key, allow) values
 ('demo_loc','Z1','sales','ডেমো','Demo','[["location_id","","","id"],["code","কোড","Code","text"],["n","সংখ্যা","N","int"],["amt","টাকা","Amount","money"]]'::jsonb, array['n','amt'], 'n', array['locations']),
 ('demo_cost','Z2','sales','ডেমো খরচ','Demo cost','[["code","কোড","Code","text"]]'::jsonb, '{}', null, array['locations']),
 ('demo_owner','Z3','control','ডেমো মালিক','Demo owner','[["code","কোড","Code","text"]]'::jsonb, '{}', null, array['locations']),
 ('demo_missing','Z4','sales','ডেমো নেই','Demo missing','[["code","কোড","Code","text"]]'::jsonb, '{}', null, array['locations']);
update report_defs3 set cost = true where key = 'demo_cost';
update report_defs3 set owner_only = true where key = 'demo_owner';
create or replace function public._r3q_demo_cost(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb language sql stable security definer set search_path = public as $$ select jsonb_build_object('code','x'); $$;
create or replace function public._r3q_demo_owner(d1 date, d2 date, locs int[], flt jsonb) returns setof jsonb language sql stable security definer set search_path = public as $$ select jsonb_build_object('code','x'); $$;

select _r3_lockdown() as ld \gset
\echo == shape
select tt.chk('T0 table has RLS, no write grant', (select relrowsecurity from pg_class where relname='report_defs3') and not has_table_privilege('authenticated','report_defs3','insert'));
select tt.chk('T0 anon cannot run', not has_function_privilege('anon','report_run3(text,jsonb,text,text,int)','execute') and not has_function_privilege('anon','report_run2(text,jsonb,text,text,int)','execute') and not has_function_privilege('authenticated','_r3q_demo_loc(date,date,int[],jsonb)','execute') and not has_function_privilege('anon','_r3q_demo_loc(date,date,int[],jsonb)','execute'));
select tt.chk('T0 core functions are not callable', not has_function_privilege('authenticated','report_run2_core(text,jsonb,text,text,int)','execute'));
select tt.chk('T0 new report grants exist', (select count(*) from grant_defs where grant_code in ('report_profit','report_quality','report_marketing','report_orders'))=4);

\echo == owner
set role authenticated; select tt.as(:'o');
select report_run2('demo_loc','{}'::jsonb) as j \gset
select tt.chk('T1 owner: all rows, columns and totals', jsonb_array_length(:'j'::jsonb->'rows') = (select count(*) from locations) and jsonb_array_length(:'j'::jsonb->'columns')=4
  and (:'j'::jsonb->'totals'->>'n')::numeric = (select sum(id*2) from locations));
select tt.chk('T1 default sort n desc', (:'j'::jsonb->'rows'->0->>'n')::numeric = (select max(id)*2 from locations));
select report_run2('demo_loc','{}'::jsonb,null,'code:asc') as j2 \gset
select tt.chk('T1 sort by a text column ascending', :'j2'::jsonb->'rows'->0->>'code' = (select min(code) from locations));
select report_run2('demo_loc','{"locations":[1]}'::jsonb) as j3 \gset
select tt.chk('T1 location filter', jsonb_array_length(:'j3'::jsonb->'rows')=1);
select tt.chk('T1 catalog lists the registry entries with engine 2', exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key'='demo_loc' and (c->>'engine')::int=2 and (c->>'allowed')::boolean));
select tt.chk('T1 old engine-2 keys still work through the wrapper', (report_run2('stock_low','{}'::jsonb)->>'report')='stock_low');
select tt.chk('T1 owner-only and cost reports open for the owner', (report_run2('demo_owner','{}'::jsonb)->>'report')='demo_owner' and (report_run2('demo_cost','{}'::jsonb)->>'report')='demo_cost');
select tt.chk('T1 missing function = data needed, not an error', (report_run2('demo_missing','{}'::jsonb)->>'data_needed')::boolean);
select tt.err('T1 unknown key', $$select report_run2('nope','{}'::jsonb)$$, 'unknown_report');
select tt.chk('T1 unknown filter is reported', exists (select 1 from jsonb_array_elements(report_run2('demo_loc','{"brands":["x"]}'::jsonb)->'notes') n where n->>'code'='filter_ignored'));
select tt.chk('T1 bad sort key ignored with a note', exists (select 1 from jsonb_array_elements(report_run2('demo_loc','{}'::jsonb,null,'zzz')->'notes') n where n->>'code'='sort_ignored'));

\echo == staff
select tt.as(:'s');
select tt.err('T2 no report grant = not allowed', $$select report_run2('demo_loc','{}'::jsonb)$$, 'not allowed');
select tt.chk('T2 catalog shows it as not allowed', exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key'='demo_loc' and not (c->>'allowed')::boolean));
select tt.as(:'o'); select set_user_grant(:'r'::uuid,'report_sales') is null as g1 \gset
select tt.as(:'r');
select tt.chk('T3 grant report_sales opens it, only for the person''s locations', jsonb_array_length(report_run2('demo_loc','{}'::jsonb)->'rows')=2);
select tt.err('T3 owner-only stays closed', $$select report_run2('demo_owner','{}'::jsonb)$$, 'not allowed');
select tt.err('T3 cost report needs the cost right', $$select report_run2('demo_cost','{}'::jsonb)$$, 'not allowed');
select tt.err('T3 range over a year refused', $$select report_run2('demo_loc','{"from":"2020-01-01","to":"2026-01-01"}'::jsonb)$$, 'bad_range');
select tt.as(:'o'); select log_report_export2('demo_loc','csv','{}'::jsonb,3) is null as lg \gset
select tt.chk('T4 export log accepts an engine-3 key', exists (select 1 from audit_log where table_name='report' and record_id='demo_loc'));
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
