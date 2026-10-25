-- RPT-HUB phase470 tests (schema, helpers, empty database, permissions, RLS, paste twice). Run on a copy of a database through phase 99, from the repo root:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase470_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\i supabase/phase470.sql
\i supabase/phase470.sql
\i supabase/phase471.sql
\i supabase/phase472.sql
\i supabase/phase473.sql
\i supabase/phase474.sql
\i supabase/phase475.sql
\i supabase/phase476.sql
\set u_o '00000000-0000-0000-0000-000000045001'
\set u_x '00000000-0000-0000-0000-000000045004'
\set u_v '00000000-0000-0000-0000-000000045003'
insert into auth.users (id,email,raw_user_meta_data) values (:'u_o','test_owner450@s.app','{"full_name":"test_owner450"}'),(:'u_x','test_nogrant450@s.app','{"full_name":"test_nogrant450"}'),(:'u_v','test_viewer450@s.app','{"full_name":"test_viewer450"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o',:'u_x',:'u_v');
insert into user_roles values (:'u_o','owner'),(:'u_x','salesperson'),(:'u_v','salesperson') on conflict do nothing;
insert into user_locations values (:'u_x',1),(:'u_v',1) on conflict do nothing;
\echo == T0 shape
select tt.chk('T0 table + RLS + no anon access', (select relrowsecurity from pg_class where relname='rpthub_user_items') and not has_table_privilege('anon','public.rpthub_user_items','select'));
select tt.chk('T0 public API: authenticated yes, anon no',
  has_function_privilege('authenticated','public.rpt_hub_day(date,int,text[],int,int)','execute') and not has_function_privilege('anon','public.rpt_hub_day(date,int,text[],int,int)','execute')
  and has_function_privilege('authenticated','public.rpt_hub_spend(jsonb,int,int)','execute') and not has_function_privilege('anon','public.rpt_hub_spend(jsonb,int,int)','execute')
  and has_function_privilege('authenticated','public.rpt_hub_trail(text,text)','execute') and not has_function_privilege('anon','public.rpt_hub_trail(text,text)','execute'));
select tt.chk('T0 internals closed to browsers', not has_function_privilege('authenticated','public._rh_events(date,date,int,text[],text,text,boolean)','execute') and not has_function_privilege('authenticated','public._rh_area_ok(text)','execute'));
select tt.chk('T0 date indexes exist', (select count(*) from pg_indexes where indexname like 'rpthub_%')>=20);
select tt.chk('T0 no setting added (no OFF switch, nothing hidden)', not exists (select 1 from rules where key like 'rpthub%' or key like 'rpt_hub%'));
\echo == T1 empty database
select tt.as(:'u_o');
select tt.chk('T1 day replay on an empty day', (select (r->>'total_events')::int=0 and r->'reconcile'->>'status'='match' and jsonb_array_length(r->'events')=0 from (select public.rpt_hub_day(date '2020-01-01') r) z));
select tt.chk('T1 spend on an empty range', (select (r->>'count')::int=0 and (r->>'total')::numeric=0 from (select public.rpt_hub_spend(jsonb_build_object('from','2020-01-01','to','2020-01-31')) r) z));
select tt.chk('T1 compare on empty periods', (select jsonb_array_length(r->'metrics')>10 from (select public.rpt_hub_compare('2020-01-01','2020-01-31','2020-02-01','2020-02-29') r) z));
select tt.err('T1 trail of a missing record', $$select public.rpt_hub_trail('sales','00000000-0000-0000-0000-000000000000')$$, 'not_found');
select tt.err('T1 unknown table refused', $$select public.rpt_hub_trail('profiles','x')$$, 'bad_table');
select tt.err('T1 missing date refused', $$select public.rpt_hub_day(null)$$, 'bad_date');
select tt.err('T1 range too long refused', $$select public.rpt_hub_spend(jsonb_build_object('from','2000-01-01','to','2026-01-01'))$$, 'bad_range');
\echo == T2 permissions on an empty database
select tt.as(:'u_x');
select tt.chk('T2 no-grant user: kinds masked by name, no error', (select jsonb_array_length(r->'masked')>=5 from (select public.rpt_hub_day(date '2020-01-01') r) z));
select tt.err('T2 no-grant user cannot open an item timeline', format($$select public.rpt_hub_entity('item', %L, '2020-01-01','2020-02-01')$$, gen_random_uuid()), 'not allowed');
select tt.err('T2 no-grant spend refused', $$select public.rpt_hub_spend(jsonb_build_object('from','2020-01-01','to','2020-01-31'))$$, 'not allowed');
select tt.err('T2 export log needs the export right', $$select public.rpt_hub_log_export('x','{}'::jsonb,1)$$, 'not allowed');
\echo == T3 my items: own rows only
select tt.as(:'u_o');
select public.rpt_hub_item_save('fav','r011') as i1 \gset
select public.rpt_hub_item_save('view','tool:day','my view','{"date":"2026-01-01"}') is not null as i2 \gset
select public.rpt_hub_touch('r011','{}');
select public.rpt_hub_touch('r011','{}');
select tt.chk('T3 save twice = one row; touch counts opens', (select count(*) from rpthub_user_items where kind='fav')=1 and (select open_count from rpthub_user_items where kind='recent')=2);
select tt.as(:'u_x');
select tt.chk('T3 another person sees none of it', (select jsonb_array_length(r->'fav')=0 and jsonb_array_length(r->'view')=0 and jsonb_array_length(r->'recent')=0 from (select public.rpt_hub_my() r) z));
select tt.chk('T3 another person cannot remove it', not public.rpt_hub_item_remove((select id from rpthub_user_items where kind='fav' limit 1)));
set role authenticated;
select tt.as(:'u_x');
select tt.chk('T3 RLS: direct select shows nothing of the owner', (select count(*) from rpthub_user_items)=0);
reset role;
select tt.err('T3 a saved view needs a name', $$select public.rpt_hub_item_save('view','tool:day',null,'{}')$$, 'name_required');
select tt.err('T3 bad kind', $$select public.rpt_hub_item_save('x','k')$$, 'bad_kind');
select tt.as(:'u_o');
select tt.chk('T3 remove own', public.rpt_hub_item_remove((select id from rpthub_user_items where kind='fav' limit 1)));
select count(*) as n40 from (select public.rpt_hub_touch('k'||g,'{}') from generate_series(1,40) g) z \gset
select tt.chk('T3 recent keeps the latest 30', (select count(*) from rpthub_user_items where kind='recent')=30);
select 'RESULT ' || count(*) filter (where ok) || ' passed, ' || count(*) filter (where not ok) || ' FAILED' from tt.res;
