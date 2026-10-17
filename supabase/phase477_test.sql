-- FRESH DB ONLY. Phase 477 tests (integrator: re-patch all + integration glue).
--   build a database through phase 476 in the owner order (tests/sql/ORDER.txt: ORDER=all bash tests/sql/build_fresh_db.sh <db>), then from the repository root:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase477_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). The suite re-pastes older phase files on purpose (that removes hooks), then proves that phase 477 puts every hook back.
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
create or replace function tt.sig() returns text language sql as $$
  select md5(string_agg(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'), '|' order by p.oid::regprocedure::text))
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
\echo == T0 objects and rights
select tt.chk('T0 phase 477 objects exist', to_regprocedure('public._i2_apply_all()') is not null and to_regprocedure('public._i2_state()') is not null and to_regprocedure('public._i2_exc_kinds_apply()') is not null);
select tt.chk('T0 every 477 function is closed to browsers (anon and authenticated)', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_i2\_%' and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))));
select tt.chk('T0 the paste applied everything: no expected hook is missing', not exists (select 1 from public._i2_state() where not present));
select tt.chk('T0 the state lists all five packages that patch (B1, B3, CRM-B, CRM-C, C1) and the glue', (select count(distinct pkg) from public._i2_state() where how = 'patch') = 6);
select tt.chk('T0 state: 13 B1 + 1 B3 + 2 CRM-B + 1 CRM-C + 7 C1 + 1 glue patches (a function with two markers counts twice)', (select count(*) from public._i2_state() where how = 'patch') >= 25);

\echo == T1 paste twice: the second call patches nothing
select public._i2_apply_all() as r1 \gset
select tt.chk('T1 second call: every package reports 0 new patches', (select bool_and(value::int = 0) from jsonb_each_text(:'r1'::jsonb)));
select tt.chk('T1 the Wave 1 state function says all 37 hooks are in', (select count(*) filter (where (e ->> 'present')::boolean) = count(*) and count(*) = 37 from jsonb_array_elements(public._i1_hooks_state()) e));
select tt.chk('T1 the W1-FIX state function says all 4 hooks are in', (select bool_and((e ->> 'present')::boolean) and count(*) = 4 from jsonb_array_elements(public._w1x_hooks_state()) e));
select tt.chk('T1 the B1 state functions say all 13 sites are in', (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked() || public._rptb1_hooked401() || public._rptb1_hooked402())));
select tt.sig() as sig0 \gset

\echo == T2 re-pasting the old phases 8 to 98 removes hooks; phase 477 puts every one back (functions equal to before, blanks ignored)
-- every old phase from 8 to 98 in the owner order (a hook patches the text a chain of phases left; a single old phase pasted alone breaks that chain: see docs/PASTE_ORDER.md)
\i supabase/phase8.sql
\i supabase/phase9.sql
\i supabase/phase10.sql
\i supabase/phase11.sql
\i supabase/phase12.sql
\i supabase/phase13.sql
\i supabase/phase14.sql
\i supabase/phase15.sql
\i supabase/phase16.sql
\i supabase/phase17.sql
\i supabase/phase18.sql
\i supabase/phase19.sql
\i supabase/phase20.sql
\i supabase/phase21.sql
\i supabase/phase22.sql
\i supabase/phase23.sql
\i supabase/phase24.sql
\i supabase/phase25.sql
\i supabase/phase26.sql
\i supabase/phase27.sql
\i supabase/phase28.sql
\i supabase/phase40.sql
\i supabase/phase41.sql
\i supabase/phase42.sql
\i supabase/phase43.sql
\i supabase/phase44.sql
\i supabase/phase45.sql
\i supabase/phase46.sql
\i supabase/phase47.sql
\i supabase/phase48.sql
\i supabase/phase49.sql
\i supabase/phase50.sql
\i supabase/phase51.sql
\i supabase/phase52.sql
\i supabase/phase53.sql
\i supabase/phase54.sql
\i supabase/phase60.sql
\i supabase/phase61.sql
\i supabase/phase62.sql
\i supabase/phase70.sql
\i supabase/phase71.sql
\i supabase/phase72.sql
\i supabase/phase73.sql
\i supabase/phase74.sql
\i supabase/phase75.sql
\i supabase/phase76.sql
\i supabase/phase77.sql
\i supabase/phase78.sql
\i supabase/phase79.sql
\i supabase/phase80.sql
\i supabase/phase81.sql
\i supabase/phase82.sql
\i supabase/phase83.sql
\i supabase/phase84.sql
\i supabase/phase85.sql
\i supabase/phase86.sql
\i supabase/phase87.sql
\i supabase/phase88.sql
\i supabase/phase89.sql
\i supabase/phase90.sql
\i supabase/phase91.sql
\i supabase/phase92.sql
\i supabase/phase93.sql
\i supabase/phase94.sql
\i supabase/phase95.sql
\i supabase/phase96.sql
\i supabase/phase97.sql
\i supabase/phase98.sql
select count(*) as lost_before from public._i2_state() where not present and how = 'patch' \gset
select tt.chk('T2 the old phases really removed hooks (the test is not vacuous): ' || :'lost_before' || ' hooks missing', :'lost_before'::int >= 8);
select tt.chk('T2 and Wave 1 lost some too', (select count(*) filter (where not (e ->> 'present')::boolean) > 0 from jsonb_array_elements(public._i1_hooks_state()) e));
select public._i2_apply_all() as r2 \gset
select tt.chk('T2 after phase 477 no patch hook is missing', not exists (select 1 from public._i2_state() where not present and how = 'patch'));
select tt.chk('T2 Wave 1 (37) and W1-FIX (4) are all back', (select bool_and((e ->> 'present')::boolean) from jsonb_array_elements(public._i1_hooks_state()) e) and (select bool_and((e ->> 'present')::boolean) from jsonb_array_elements(public._w1x_hooks_state()) e));
select tt.chk('T2 phase 477 patched something in every one of the five packages that patch', (select bool_and(value::int > 0) from jsonb_each_text((:'r2'::jsonb) - 'INTEGRATION' - 'W1-FIX')));
select count(*) as repaste_n from public._i2_state() where not present and how like 'repaste%' \gset
select tt.chk('T2 the functions that are re-created as a whole are reported with the phase to paste again: ' || :'repaste_n', :'repaste_n'::int >= 4);
\i supabase/phase420.sql
\i supabase/phase421.sql
\i supabase/phase432.sql
\i supabase/phase434.sql
\i supabase/phase441.sql
select tt.chk('T2 after pasting 420, 421, 432, 434, 441 again nothing is missing at all', not exists (select 1 from public._i2_state() where not present));
select public._i2_apply_all() as r3 \gset
select tt.chk('T2 and a last 477 call changes nothing', (select bool_and(value::int = 0) from jsonb_each_text(:'r3'::jsonb)));
select tt.sig() as sig1 \gset
select tt.chk('T2 all functions are the same as before the old phases were pasted again (blanks ignored)', :'sig0' = :'sig1');

\echo == T3 the old four-argument qc_list comes back with phase 60 and 477 removes it
\i supabase/phase60.sql
select tt.chk('T3 phase 60 brought the old qc_list(int,date,date,text) back', to_regprocedure('public.qc_list(integer,date,date,text)') is not null);
select public._i2_apply_all();
select tt.chk('T3 phase 477 dropped it again (the six-argument one stays)', to_regprocedure('public.qc_list(integer,date,date,text)') is null and to_regprocedure('public.qc_list(integer,date,date,text,uuid,uuid)') is not null);

\echo == T4 Exceptions kinds
select tt.chk('T4 the kind list of 477 holds the Wave 1 list and the four later kinds', public._i2_exc_kinds() @> public._i1_exc_kinds() and public._i2_exc_kinds() @> array['r1_unbacked_payment', 'crmg_late_quote', 'crmg_lead_reopen', 'crmg_win_without_quote']);
select tt.chk('T4 the live constraint allows every one of them', (select bool_and(pg_get_constraintdef(c.oid) like '%''' || k || '''%') from pg_constraint c, unnest(public._i2_exc_kinds()) k
   where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%'));
select tt.chk('T4 the apply function is a no-op when everything is in', (public._i2_exc_kinds_apply() ->> 'changed') = 'false');
select tt.chk('T4 a kind of another package that the list does not know is kept (never removed)', (select pg_get_constraintdef(c.oid) like '%r1_unbacked_payment%' from pg_constraint c where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%'));

\echo == T5 glue: f3 counts a record of real use (RPT-B4) as a measurement
\set ON_ERROR_STOP on
\i tests/sql/rptb1_fixture.sql
\i tests/sql/rptb1_fixture2.sql
\set ON_ERROR_STOP off
create or replace function tt.e3(p_key text) returns jsonb language sql as $$ select public.report_run2(p_key, '{"preset":"last_7"}'::jsonb) $$;
create or replace function tt.rows(j jsonb) returns setof jsonb language sql as $$ select e from jsonb_array_elements(coalesce(j -> 'rows', '[]'::jsonb)) e $$;
select tt.as(:'o');
select tt.e3('f3_raw_vs_recipe') as fa \gset
select tt.chk('T5 before any record: actual is empty, status "not captured" (RPT-B1 behaviour unchanged)', (select r ->> 'actual' is null and r ->> 'actual_status' = 'not captured' from tt.rows(:'fa'::jsonb) r limit 1));
select prod_actual_issue_set(:'run1'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 6)), 'test real use') is not null as w_r1 \gset
select tt.e3('f3_raw_vs_recipe') as fb \gset
select tt.chk('T5 one of two runs recorded: status "partly (1 of 2 runs)", actual still empty', (select r ->> 'actual' is null and r ->> 'actual_status' = 'partly (1 of 2 runs)' from tt.rows(:'fb'::jsonb) r limit 1));
select prod_actual_issue_set(:'run2'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 7)), 'test real use') is not null as w_r2 \gset
select tt.e3('f3_raw_vs_recipe') as fc \gset
select tt.chk('T5 both recorded: actual 6 + 7 = 13 against 10 per recipe, difference 3, 30 %, status measured',
  (select (r ->> 'actual')::numeric = 13 and (r ->> 'diff')::numeric = 3 and (r ->> 'diff_pct')::numeric = 30 and r ->> 'actual_status' = 'measured' from tt.rows(:'fc'::jsonb) r limit 1));
select tt.chk('T5 the record is NOT a stock movement: raw on hand is still 200 - 5 - 5 - 3 = 187', (select qty from stock_balance where item_id = :'i_rm'::uuid and location_id = 1) = 187);
select prod_actual_issue_set(:'run1'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 5)), 'test correction') is not null as w_r3 \gset
select tt.e3('f3_raw_vs_recipe') as fd \gset
select tt.chk('T5 a corrected record replaces the older one (history kept): 5 + 7 = 12', (select (r ->> 'actual')::numeric = 12 from tt.rows(:'fd'::jsonb) r limit 1));
select stock_post(:'i_rm'::uuid, 1, -1, 'issue_out', 'production', :'run1', null, null, now(), 'test extra issue', null, 'full') is not null as w_x1 \gset
select tt.e3('f3_raw_vs_recipe') as fe \gset
select tt.chk('T5 a record wins over a stock movement of the same run and ingredient (still 12, not 13)', (select (r ->> 'actual')::numeric = 12 from tt.rows(:'fe'::jsonb) r limit 1));

select 'RESULT ' || count(*) filter (where ok) || ' passed, ' || count(*) filter (where not ok) || ' FAILED' from tt.res;
