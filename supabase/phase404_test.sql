-- FRESH DB ONLY. Phase 404 tests: production capture tables and the reader / writer helpers (package RPT-B4, R3a).
--   Build a database through phase 99, paste supabase/phase404.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase404_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql (hand-computed numbers in its header). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset

\echo == T0 tables
select tt.chk('T0 five capture tables exist with row level security on', (select count(*) from pg_class where relname in ('production_plans','production_orders','production_run_links','production_issue_actual','production_loss') and relrowsecurity) = 5);
select tt.chk('T0 browsers can read the tables but not write them',
  (select bool_and(has_table_privilege('authenticated', 'public.' || t, 'select') and not has_table_privilege('authenticated', 'public.' || t, 'insert') and not has_table_privilege('authenticated', 'public.' || t, 'update') and not has_table_privilege('authenticated', 'public.' || t, 'delete'))
     from unnest(array['production_plans','production_orders','production_run_links','production_issue_actual','production_loss']) t));
select tt.chk('T0 anon reads nothing', not has_table_privilege('anon', 'public.production_plans', 'select') and not has_table_privilege('anon', 'public.production_loss', 'select'));
select tt.chk('T0 the checks the policies use are callable by signed-in users only', has_function_privilege('authenticated', 'public._rb4_prod_view(int)', 'execute') and not has_function_privilege('anon', 'public._rb4_prod_view(int)', 'execute'));
select tt.chk('T0 the tables carry the integrity checks: a plan needs batches or a quantity; a loss of kind none has quantity 0',
  (select count(*) from pg_constraint where conrelid = 'public.production_plans'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%planned_batches IS NOT NULL%') = 1
  and (select count(*) from pg_constraint where conrelid = 'public.production_loss'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%none%') >= 1);
select tt.chk('T0 production_post is untouched by this package', position('bos404' in pg_get_functiondef('public.production_post(int,uuid,numeric,uuid,timestamptz,text,numeric)'::regprocedure)) = 0);

\echo == T1 who may read and who may write
select tt.chk('T1 the owner may read and write at place 5', public._rb4_prod_view(5) and public._rb4_prod_entry(5));
select tt.as(:'fac');
select tt.chk('T1 the factory in-charge (production grant, place 5) may read and write at her place, not at place 1', public._rb4_prod_view(5) and public._rb4_prod_entry(5) and not public._rb4_prod_view(1) and not public._rb4_prod_entry(1));
select tt.as(:'rep');
select tt.chk('T1 a holder of the stock report right at places 5 and 1 may read both but write at neither', public._rb4_prod_view(5) and public._rb4_prod_view(1) and not public._rb4_prod_entry(5) and not public._rb4_prod_entry(1));
select tt.as(:'shop');
select tt.chk('T1 a salesperson of place 1 may neither read nor write production data', not public._rb4_prod_view(1) and not public._rb4_prod_entry(1) and not public._rb4_prod_view(5));
select tt.as(:'o');

\echo == T2 date helpers
select tt.chk('T2 the Dhaka day of a timestamp near midnight UTC is the next day', public._rb4_day('2026-03-01 19:30:00+00'::timestamptz) = '2026-03-02'::date and public._rb4_day('2026-03-01 17:59:00+00'::timestamptz) = '2026-03-01'::date);
select tt.chk('T2 the range helper defaults to the last 30 days and refuses a reversed or an over-long range', (select f = public._rb4_today() - 30 and t = public._rb4_today() from public._rb4_range(null, null)));
select tt.err('T2 a reversed range is refused', $$select * from public._rb4_range(current_date, current_date - 1)$$, 'bad_range');
select tt.err('T2 a range of more than 800 days is refused', $$select * from public._rb4_range(current_date - 900, current_date)$$, 'bad_range');

\echo == T3 constraints
select tt.err('T3 a plan with neither batches nor quantity cannot be inserted even by the database owner', format($$insert into production_plans (plan_date, location_id, item_id) values (%L, 5, %L)$$, :'td', :'i_fg'), 'violates check');
select tt.err('T3 a loss of kind reject with quantity 0 is refused', format($$insert into production_loss (run_id, kind, qty, reason_code) values (%L, 'reject', 0, 'burnt')$$, :'run1'), 'violates check');
select tt.err('T3 a real use of ingredients with a negative quantity is refused', format($$insert into production_issue_actual (run_id, item_id, actual_qty) values (%L, %L, -1)$$, :'run1', :'i_rm'), 'violates check');
insert into production_issue_actual (run_id, item_id, actual_qty) values (:'run1'::uuid, :'i_rm'::uuid, 5);
select tt.err('T3 two active real-use lines for the same run and ingredient cannot coexist', format($$insert into production_issue_actual (run_id, item_id, actual_qty) values (%L, %L, 6)$$, :'run1', :'i_rm'), 'duplicate key');

\echo == T4 paste twice
\ir phase404.sql
select tt.chk('T4 pasting the file again keeps the data', (select count(*) from production_issue_actual) = 1);

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
