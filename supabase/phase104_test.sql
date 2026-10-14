-- FRESH DB ONLY. Phase 104 tests (Owner dashboard layouts): RLS own row only, idempotent save, audit, guard, paste twice.
--   Build: bash tests/sql/run_all_sql.sh phase104     (phase104 is appended after phase103 automatically)
--   Run from the REPO ROOT:  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase104_test.sql | grep -E "FAIL|RESULT"
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set p '00000000-0000-0000-0000-000000000004'
\set v '00000000-0000-0000-0000-000000000005'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.try(p_sql text) returns text language plpgsql as $$
declare r text;
begin execute p_sql into r; return r;
exception when others then return 'ERR:' || sqlerrm; end $$;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'p','sales4@s.app','{"full_name":"Sales"}'), (:'v','phoneview5@s.app','{"full_name":"Viewer"}') on conflict do nothing;
insert into user_roles values (:'o','owner'),(:'p','salesperson'),(:'v','salesperson') on conflict do nothing;
update profiles set status = 'active' where id in (:'o', :'p', :'v');

select tt.chk('T1 table + RLS + two functions exist', to_regclass('public.dash_layouts') is not null
  and (select relrowsecurity from pg_class where oid = 'public.dash_layouts'::regclass)
  and to_regprocedure('public.dash_layout_get()') is not null and to_regprocedure('public.dash_layout_save(jsonb,text)') is not null);
select tt.chk('T1b anon cannot execute; authenticated can', not has_function_privilege('anon', 'public.dash_layout_save(jsonb,text)', 'execute') and has_function_privilege('authenticated', 'public.dash_layout_save(jsonb,text)', 'execute'));

\echo == save / get as the owner
select tt.as(:'o');
select tt.chk('T2 get before any save: layout null', (dash_layout_get() -> 'layout') = 'null'::jsonb);
select dash_layout_save('{"v":1,"tiles":[{"id":"a","metric":"sales_total"}]}'::jsonb, 'c1') as s1 \gset
select tt.chk('T3 first save: ok + changed', (:'s1'::jsonb ->> 'changed') = 'true');
select tt.chk('T3b get returns what was saved', (dash_layout_get() -> 'layout' -> 'tiles' -> 0 ->> 'metric') = 'sales_total');
select count(*) as a1 from audit_log where table_name = 'dash_layouts' \gset
select dash_layout_save('{"v":1,"tiles":[{"id":"a","metric":"sales_total"}]}'::jsonb, 'c1') as s2 \gset
select tt.chk('T4 same layout again: changed=false (idempotent)', (:'s2'::jsonb ->> 'changed') = 'false');
select tt.chk('T4b no new audit row for the repeat', (select count(*) from audit_log where table_name = 'dash_layouts') = :a1);
select tt.chk('T4c exactly one row for the owner', (select count(*) from dash_layouts where user_id = :'o') = 1);
select dash_layout_save('{"v":1,"tiles":[{"id":"b","metric":"top_items"}]}'::jsonb, 'c1') as s3 \gset
select tt.chk('T5 a changed layout updates the same row and is audited', (:'s3'::jsonb ->> 'changed') = 'true' and (select count(*) from dash_layouts where user_id = :'o') = 1
  and (select count(*) from audit_log where table_name = 'dash_layouts') > :a1);

\echo == other users
select tt.as(:'p');
select tt.chk('T6 another user sees no layout of the owner (get = null)', (dash_layout_get() -> 'layout') = 'null'::jsonb);
select tt.chk('T6b direct table select as another user returns 0 rows', tt.try($$select count(*) from (select 1 from dash_layouts) x$$) is not null);
set role authenticated;
select count(*) as vis from dash_layouts \gset
select tt.chk('T7 RLS: the other user (role authenticated) reads 0 rows of the table', :vis = 0);
select tt.chk('T8 RLS: cannot update the owner row', (with u as (update dash_layouts set layout = '{"v":1,"tiles":[]}' where user_id = :'o' returning 1) select count(*) from u) = 0);
select tt.chk('T9 RLS: cannot insert a row for the owner', tt.try(format($q$insert into dash_layouts (user_id, layout) values (%L, '{}')$q$, :'o')) like 'ERR:%');
reset role;
select tt.as(:'p');
select dash_layout_save('{"v":1,"tiles":[{"id":"z","metric":"cust_dues"}]}'::jsonb, 'c2');
select tt.chk('T10 own save works for the second user and is separate', (select layout -> 'tiles' -> 0 ->> 'metric' from dash_layouts where user_id = :'p') = 'cust_dues'
  and (select layout -> 'tiles' -> 0 ->> 'metric' from dash_layouts where user_id = :'o') = 'top_items');
select tt.as(:'o');
select tt.chk('T11 the owner layout is untouched by the other save', (dash_layout_get() -> 'layout' -> 'tiles' -> 0 ->> 'metric') = 'top_items');
select tt.chk('T12 no delete privilege', not has_table_privilege('authenticated', 'public.dash_layouts', 'delete'));

\echo == validation
select tt.chk('T13 not an object refused', tt.try($$select dash_layout_save('[1]'::jsonb, 'x')$$) like 'ERR:%bad_layout%');
select tt.chk('T14 null refused', tt.try($$select dash_layout_save(null, 'x')$$) like 'ERR:%bad_layout%');
select tt.chk('T15 more than 40 tiles refused', tt.try($$select dash_layout_save(jsonb_build_object('tiles', (select jsonb_agg(i) from generate_series(1,41) i)), 'x')$$) like 'ERR:%bad_tiles%');
select tt.chk('T16 too big refused', tt.try($$select dash_layout_save(jsonb_build_object('x', repeat('a', 70000)), 'x')$$) like 'ERR:%layout_too_big%');
select set_config('request.jwt.claim.sub', '', false);
select tt.chk('T17 no user: refused', tt.try($$select dash_layout_get()$$) like 'ERR:%');

\echo == paste twice
select md5(pg_get_functiondef('public.dash_layout_save(jsonb,text)'::regprocedure)) as f1, (select count(*) from pg_policies where tablename = 'dash_layouts') as pol1 \gset
\i supabase/phase104.sql
select tt.chk('T18 paste twice: same function body, same policies, row kept', md5(pg_get_functiondef('public.dash_layout_save(jsonb,text)'::regprocedure)) = :'f1'
  and (select count(*) from pg_policies where tablename = 'dash_layouts') = :pol1 and (select count(*) from dash_layouts) = 2);

\echo == guard
alter function public._inb_pii_f99(text, text) rename to _inb_pii_f99_hold104;
drop table public.dash_layouts cascade;
\i supabase/phase104.sql
select tt.chk('T19 guard: with phase99 missing nothing is created', to_regclass('public.dash_layouts') is null and current_setting('phase104.ok') = 'off');
alter function public._inb_pii_f99_hold104(text, text) rename to _inb_pii_f99;
\i supabase/phase104.sql
select tt.chk('T20 markers back: table is created again', to_regclass('public.dash_layouts') is not null and current_setting('phase104.ok') = 'guard1');

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
