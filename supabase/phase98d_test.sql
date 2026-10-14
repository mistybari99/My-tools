-- COPY of phase98b_test.sql for the chain with phase114 + phase115 (BATCH 2): a re-paste of an older phase puts the older body of functions that 114/115 patch back, so this copy pastes 114/115 again after it (re-paste rule, docs/PASTE_ORDER.md section N). Assertions otherwise as in phase98b_test.sql.
-- FRESH DB ONLY. phase98b_test.sql = phase98_test.sql for the chain that ends with phase103 (Step E2E): phase103 re-creates _acct_docs and inventory_vs_gl from the phase98 text, so 'phase97 then phase98 gives the identical hash as before' needs phase103 pasted after it (P1b), and the body guard of phase98 refuses to run over a body that carries bos103 (G1 last block: phase89 then phase103 instead of phase98). Phase98_test.sql itself is NOT edited (docs/PASTE_ORDER.md rule 3).
-- Original header: Phase 98 tests (final merge of what phase96 and phase97 both re-create).
--   Build: tests/sql/final_build.sh (72..88, 90, 91, 89, 92, 93, 95, 94, 96, 97, 98).  Run from the repo root (the P blocks do \i supabase/phaseNN.sql):
--   psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase98_test.sql | grep -E "FAIL|RESULT"
-- Test data only, no person names. Place 1 only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner') on conflict do nothing;

\echo == T0 every tag of every phase survives in _acct_docs; bos96 in the four phase96 functions
select tt.chk('T0 _acct_docs carries ' || t, position(t in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0)
  from unnest(array['bos50','bos52','bos72','bos74','bos80','bos85','bos89','bos96','bos97','bos98']) t;
select tt.chk('T0 ' || f || ' carries bos96', position('bos96' in pg_get_functiondef(f::regprocedure)) > 0)
  from unnest(array['public._acct_inv_split72(text[],text,text[],integer)','public._acct_stock_moves85(date)','public._pvar85(uuid)','public.inventory_vs_gl(date,integer)']) f;
select tt.chk('T0 _acct_docs: 3 bos96 stock_ledger_eff96 reads (wastage, production, transfer) and both bos97 landed blocks',
  (select count(*) from regexp_matches(pg_get_functiondef('public._acct_docs(date)'::regprocedure), 'stock_ledger_eff96 [a-z] /\* bos96', 'g')) = 3
  and position('''landed_cost''::text' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0 and position('''landed_cost_void''::text' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0);
select tt.chk('T0 exactly one _acct_docs, SECURITY DEFINER, stable, search_path public',
  (select count(*) from pg_proc where proname='_acct_docs') = 1 and (select prosecdef and provolatile='s' and proconfig::text like '%search_path=public%' from pg_proc where proname='_acct_docs'));

\echo == T1 the two bodies are a real merge: the phase97 blocks come after the phase89 content, no leftover conflict marks
select tt.chk('T1 no conflict markers in _acct_docs', pg_get_functiondef('public._acct_docs(date)'::regprocedure) !~ '(^|\n)(<<<<<<<|>>>>>>>|=======)');

\echo == S1 the merged body runs and the books stay balanced
select tt.chk('S1 _acct_docs runs on the final chain (no error)', (select count(*) >= 0 from public._acct_docs(date '2000-01-01')));
select tt.chk('S1 no unbalanced journal entry', (select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z) = 0);
select tt.chk('S1 view stock_ledger_eff96 (read by the bos96 lines) exists', to_regclass('public.stock_ledger_eff96') is not null);

\echo == P1 re-paste order test: phase97 pasted again erases bos96 from _acct_docs, phase98 puts it back (same hash as before)
create temp table k0 as select md5(pg_get_functiondef('public._acct_docs(date)'::regprocedure)) h;
\i supabase/phase97.sql
select tt.chk('P1a phase97 again: _acct_docs lost bos96 (this is the defect phase98 repairs)', position('bos96' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0);
\i supabase/phase98.sql
\i supabase/phase103.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
select tt.chk('P1b phase98 then phase103 after it: bos96 and bos97 back, identical hash as before', (select h from k0) = md5(pg_get_functiondef('public._acct_docs(date)'::regprocedure))
  and position('bos96' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0 and position('bos97' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0);

\echo == P2 paste twice: re-applying phase98 changes no function body, no ACL, no table
create temp table h1 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h, p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f';
create temp table r1 as select c.relname, c.relacl::text acl, c.relrowsecurity rls, c.relkind from pg_class c where c.relnamespace='public'::regnamespace;
create temp table g1 as select tgname, tgrelid::regclass::text rel from pg_trigger where not tgisinternal;
\i supabase/phase98.sql
create temp table h2 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h, p.proacl::text acl from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f';
select tt.chk('P2 second paste: identical function bodies and ACLs', (select count(*) from h1 full join h2 using (fn) where h1.h is distinct from h2.h or h1.acl is distinct from h2.acl) = 0);
select tt.chk('P2 tables, views, RLS flags, table ACLs and triggers unchanged', (select count(*) from r1 full join (select c.relname, c.relacl::text acl, c.relrowsecurity rls, c.relkind from pg_class c where c.relnamespace='public'::regnamespace) r2 using (relname) where r1.acl is distinct from r2.acl or r1.rls is distinct from r2.rls or r1.relkind is distinct from r2.relkind) = 0
  and (select count(*) from g1) = (select count(*) from pg_trigger where not tgisinternal));

\echo == G1 guard: a missing phase stops phase98 and nothing is changed (even for a client that keeps going after an error)
\i supabase/phase97.sql
create temp table k1 as select md5(pg_get_functiondef('public._acct_docs(date)'::regprocedure)) h;
alter function public._landed_jlines97(uuid,text) rename to _landed_jlines97_x;
\i supabase/phase98.sql
select tt.chk('G1 phase97 marker missing: phase98 changed nothing', (select h from k1) = md5(pg_get_functiondef('public._acct_docs(date)'::regprocedure)) and position('bos98' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0);
alter function public._landed_jlines97_x(uuid,text) rename to _landed_jlines97;
select pg_get_functiondef('public._pvar85(uuid)'::regprocedure) as origdef \gset
drop function public._pvar85(uuid);
create function public._pvar85(p uuid) returns numeric language sql as $$ select 0::numeric /* bos99 */ $$;
\i supabase/phase98.sql
select tt.chk('G1 unknown tag bos99 (body guard): phase98 changed nothing', position('bos98' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) = 0);
drop function public._pvar85(uuid);
select :'origdef' \gexec
\i supabase/phase89.sql
\i supabase/phase103.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
select tt.chk('G1 (phase103 world: phase89 puts the older bodies back, ONE paste of phase103 repairs them) after the body is right again, the merged _acct_docs is back (bos96 + bos97 + bos98 present)', position('bos98' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0 and position('bos96' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0 and position('bos97' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0);

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
