-- Phase 119 test (integration of the audit-fix batches): the documented re-paste rule gives the SAME function bodies as a fresh canonical build.
-- Rule (docs/PASTE_ORDER.md, Invariant): after re-pasting ANY of phase 89, 94, 96, 97, 98, 103, 105, 109, 110, 111, paste the repair tail again:
--   89, 103, 105, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118   (phase89 first puts the older text back where a later body guard - phase98/103 on _acct_docs with bos113, phase109 on production_post with bos116 - would refuse).
-- Short rule (enough for 94, 97, 98, 103, 105, 109, 110, 111; tested as S94..S111): re-paste X, then 112..118. 89 and 96 need the full tail (R89, R96).
-- FRESH DB ONLY, final chain (tests/sql/final_build.sh up to phase118). No data is created; only function bodies are compared (md5 of pg_get_functiondef over all public functions).
-- Build:  bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase119_test.sql | grep -E "FAIL|RESULT"   (run from the repo root)
\set ON_ERROR_STOP off
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create temp table fresh as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f';
select tt.chk('R0 the build is the full chain: bos113 in _acct_docs, bos116 in production_post, bos117 in _p27_pl, bos118 reports exist',
  position('bos113' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0
  and exists (select 1 from pg_proc where proname='production_post' and prosrc like '%bos116%')
  and position('bos117' in pg_get_functiondef('public._p27_pl(date,date,integer[])'::regprocedure)) > 0
  and exists (select 1 from pg_proc where proname='net_profit_report'));
\echo == R89 re-paste phase89, then the repair tail
\i supabase/phase89.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R89 after phase89 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R94 re-paste phase94, then the repair tail
\i supabase/phase94.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R94 after phase94 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R96 re-paste phase96, then the repair tail
\i supabase/phase96.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R96 after phase96 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R97 re-paste phase97, then the repair tail
\i supabase/phase97.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R97 after phase97 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R98 re-paste phase98, then the repair tail
\i supabase/phase98.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R98 after phase98 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R103 re-paste phase103, then the repair tail
\i supabase/phase103.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R103 after phase103 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R105 re-paste phase105, then the repair tail
\i supabase/phase105.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R105 after phase105 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R109 re-paste phase109, then the repair tail
\i supabase/phase109.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R109 after phase109 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R110 re-paste phase110, then the repair tail
\i supabase/phase110.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R110 after phase110 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == R111 re-paste phase111, then the repair tail
\i supabase/phase111.sql
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase105.sql
\i supabase/phase109.sql
\i supabase/phase110.sql
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('R111 after phase111 + the repair tail every public function body equals the fresh canonical build (' || (select count(*) from fresh) || ' functions, differing: ' || coalesce((select string_agg(fn, ',') from (select fn from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h limit 5) z),'none') || ')',
  (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);

\echo == S94 short rule: re-paste phase94, then only 112..118
\i supabase/phase94.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S94 after phase94 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == S97 short rule: re-paste phase97, then only 112..118
\i supabase/phase97.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S97 after phase97 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == S98 short rule: re-paste phase98, then only 112..118
\i supabase/phase98.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S98 after phase98 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == S103 short rule: re-paste phase103, then only 112..118
\i supabase/phase103.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S103 after phase103 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == S105 short rule: re-paste phase105, then only 112..118
\i supabase/phase105.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S105 after phase105 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == S109 short rule: re-paste phase109, then only 112..118
\i supabase/phase109.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S109 after phase109 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == S110 short rule: re-paste phase110, then only 112..118
\i supabase/phase110.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S110 after phase110 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);
\echo == S111 short rule: re-paste phase111, then only 112..118
\i supabase/phase111.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
\i supabase/phase122.sql
\i supabase/phase123.sql
\i supabase/phase124.sql
\i supabase/phase125.sql
\i supabase/phase126.sql
\i supabase/phase127.sql
\i supabase/phase128.sql
\i supabase/phase129.sql
\i supabase/phase131.sql
\i supabase/phase133.sql
select tt.chk('S111 after phase111 + 112..118 (short rule) every public function body equals the fresh canonical build', (select count(*) from fresh f full join (select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f') c using (fn) where f.h is distinct from c.h) = 0);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
