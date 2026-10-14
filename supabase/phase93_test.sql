-- FRESH DB ONLY. Phase 93 tests (Step Tpl: doc_template_choice, set_doc_template, get_doc_templates).
--   ORDER="phase8 ... phase79 phase80 ... phase88 phase93" bash <copy of tests/sql/build_fresh_db.sh with worktree paths> a93db
--   psql -h /tmp -p 5544 -U postgres -d a93db -qAt -f supabase/phase93_test.sql | grep -E 'FAIL|RESULT'
-- Test data only, no person names.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
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

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Staff"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 table exists, RLS on', (select relrowsecurity from pg_class where oid='public.doc_template_choice'::regclass));
select tt.chk('T0 no direct write for the browser', not has_table_privilege('authenticated','public.doc_template_choice','insert') and not has_table_privilege('authenticated','public.doc_template_choice','update') and not has_table_privilege('authenticated','public.doc_template_choice','delete') and has_table_privilege('authenticated','public.doc_template_choice','select'));
select tt.chk('T0 rpc grants: signed-in only', has_function_privilege('authenticated','public.set_doc_template(text,text,int)','execute') and not has_function_privilege('anon','public.set_doc_template(text,text,int)','execute') and has_function_privilege('authenticated','public.get_doc_templates(int)','execute') and not has_function_privilege('anon','public.get_doc_templates(int)','execute'));

\echo == default: no choice = nothing returned (today's output)
set role authenticated; select tt.as(:'s');
select tt.chk('T1 empty by default', get_doc_templates(1) = '[]'::jsonb);
\echo == owner only
select tt.err('T2 staff cannot set', $$select set_doc_template('pos_receipt','thermal80_classic',null)$$, 'owner_only');
select tt.as(:'o');
select tt.err('T3 bad doc type', $$select set_doc_template('Bad Type!','thermal80_classic',null)$$, 'bad_doc_type');
select tt.err('T4 bad template id', $$select set_doc_template('pos_receipt','x; drop',null)$$, 'bad_template_id');
select tt.err('T5 unknown location', $$select set_doc_template('pos_receipt','thermal80_classic',99999)$$, 'bad_location');
select set_doc_template('pos_receipt','thermal80_classic',null) ->> 'template_id' as t1 \gset
select tt.chk('T6 owner sets the all-locations default', :'t1' = 'thermal80_classic');
select set_doc_template('pos_receipt','a4_modern',1) ->> 'template_id' as t2 \gset
select tt.chk('T7 owner sets a location choice', :'t2' = 'a4_modern');
select tt.as(:'s');
select tt.chk('T8 staff reads; location 1 effective = a4_modern, all-locations row is not effective there',
  (select count(*) from jsonb_array_elements(get_doc_templates(1)) r where r->>'doc_type'='pos_receipt' and (r->>'effective')::boolean and r->>'template_id'='a4_modern') = 1
  and (select count(*) from jsonb_array_elements(get_doc_templates(1)) r where (r->>'effective')::boolean) = 1);
select tt.chk('T9 another place falls back to the all-locations row', (select count(*) from jsonb_array_elements(get_doc_templates(2)) r where (r->>'effective')::boolean and r->>'template_id'='thermal80_classic') = 1);
select tt.as(:'o');
select set_doc_template('pos_receipt','thermal58_slim',1);
select tt.chk('T10 replace keeps one row per place', (select count(*) from doc_template_choice where doc_type='pos_receipt') = 2 and (select template_id from doc_template_choice where location_id=1)='thermal58_slim');
select set_doc_template('pos_receipt',null,1) ->> 'old' as old \gset
select tt.chk('T11 clear removes the location row (old value reported)', :'old' = 'thermal58_slim' and (select count(*) from doc_template_choice where doc_type='pos_receipt') = 1);
reset role;
select tt.chk('T12 audit rows written (3 sets + 1 clear)', (select count(*) from audit_log where table_name='doc_template_choice') = 4 and (select count(*) from audit_log where action='doc_template_clear') = 1);
select tt.chk('T13 set_by recorded', (select set_by from doc_template_choice limit 1) = :'o'::uuid);
\echo == paste twice
\i supabase/phase93.sql
select tt.chk('T14 second paste keeps the data', (select count(*) from doc_template_choice) = 1);
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
