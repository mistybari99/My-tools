-- FRESH DB ONLY. Phase 412 tests: production lines, rated capacity, labour hours per run, line of a run (package RPT-B4, R8a).
--   Build a database through phase 99, paste supabase/phase404.sql, phase405.sql and phase412.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase412_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql and rb4_fixture2.sql (hand-computed numbers in the headers). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\ir ../tests/sql/rb4_fixture2.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset

\echo == T0 shape
select tt.chk('T0 three tables with row level security; browsers cannot write them', (select count(*) from pg_class where relname in ('production_lines','capacity_ratings','production_labour') and relrowsecurity) = 3
  and not has_table_privilege('authenticated','public.capacity_ratings','insert') and not has_table_privilege('authenticated','public.production_labour','update'));
select tt.chk('T0 the grant exists and no role holds it by default', exists (select 1 from grant_defs where grant_code = 'capacity_manage') and not exists (select 1 from rule_grants where grant_code = 'capacity_manage'));
select tt.chk('T0 the run link table has the line column', exists (select 1 from information_schema.columns where table_name = 'production_run_links' and column_name = 'line_id'));

\echo == T1 lines
select (production_line_set(null, 5, 'test_line_one', 'Test line one') ->> 'id')::int as ln1 \gset
select (production_line_set(null, 5, 'test_line_two', null) ->> 'id')::int as ln2 \gset
select tt.chk('T1 two lines at place 5; the English name may stay blank', (select count(*) from production_lines where location_id = 5) = 2 and (select name_en is null from production_lines where id = :'ln2'::int));
select tt.err('T1 the same Bangla name twice at one place is refused', $$select production_line_set(null, 5, 'test_line_one')$$, 'duplicate');
select tt.err('T1 a blank name is refused', $$select production_line_set(null, 5, '  ')$$, 'bad_name');
select tt.err('T1 an unknown place is refused', $$select production_line_set(null, 999, 'x')$$, 'bad_location');
select tt.as(:'fac');
select tt.err('T1 the factory in-charge cannot add a line (the owner holds the right)', $$select production_line_set(null, 5, 'test_line_x')$$, 'not allowed');
select tt.chk('T1 ... but she can read the lines of her place', jsonb_array_length(public.production_line_list(5)) = 2);
select tt.as(:'o');
insert into user_grants (user_id, grant_code) values (:'fac', 'capacity_manage') on conflict do nothing;
select tt.as(:'fac');
select tt.chk('T1 with the grant she can rename a line', (production_line_set(:'ln2'::int, null, 'test_line_two_b', 'Test line two') ->> 'id')::int = :'ln2'::int);
select tt.chk('T1 ... and the new name is stored', (select name_en = 'Test line two' and name_bn = 'test_line_two_b' from production_lines where id = :'ln2'::int));
select tt.err('T1 retiring a line needs a reason', format($$select production_line_set(%s, null, 'test_line_two_b', 'Test line two', false)$$, :'ln2'), 'note_required');
select production_line_set(:'ln2'::int, null, 'test_line_two_b', 'Test line two', false, 'test: not used') is not null as w_ret \gset
select tt.chk('T1 a retired line stays, flagged; the default list leaves it out, the full list shows it', (select not active and retired_note like 'test:%' from production_lines where id = :'ln2'::int)
  and jsonb_array_length(public.production_line_list(5)) = 1 and jsonb_array_length(public.production_line_list(5, true)) = 2);
select tt.as(:'o');

\echo == T2 rated capacity
select (capacity_rating_set(5, null, 4, 6, :'td'::date - 40, 'test place rating') ->> 'id')::bigint as cr1 \gset
select (capacity_rating_set(5, :'ln1'::int, 2, 6, :'td'::date - 40, 'test line rating') ->> 'id')::bigint as cr2 \gset
select tt.chk('T2 a rating for the place and one for a line are separate rows', (select count(*) from capacity_ratings where location_id = 5 and status = 'active') = 2);
select tt.chk('T2 the same rating again is a no-op', (capacity_rating_set(5, null, 4, 6, :'td'::date - 40) ->> 'dup')::boolean);
select (capacity_rating_set(5, null, 5, 6, :'td'::date - 40, 'test raised') ->> 'replaced')::bigint as old1 \gset
select tt.chk('T2 a new value for the same day retires the old row (kept) and writes a new one', :'old1'::bigint = :'cr1'::bigint and (select status = 'retired' from capacity_ratings where id = :'cr1'::bigint) and (select count(*) from capacity_ratings where location_id = 5 and line_id is null and status = 'active') = 1);
select tt.err('T2 a rating of 0 batches is refused', format($$select capacity_rating_set(5,null,0,6,%L::date)$$, :'td'), 'bad_capacity');
select tt.err('T2 more than 7 working days a week is refused', format($$select capacity_rating_set(5,null,3,8,%L::date)$$, :'td'), 'bad_days');
select tt.err('T2 a line of another place is refused', format($$select capacity_rating_set(1,%s,3,6,%L::date)$$, :'ln1', :'td'), 'line_not_found');
select tt.err('T2 a retired line cannot be rated', format($$select capacity_rating_set(5,%s,3,6,%L::date)$$, :'ln2', :'td'), 'line_not_found');
select tt.err('T2 a missing date is refused', $$select capacity_rating_set(5,null,3,6,null)$$, 'bad_date');
select tt.as(:'shop');
select tt.err('T2 a salesperson cannot set a rating', format($$select capacity_rating_set(5,null,3,6,%L::date)$$, :'td'), 'not allowed');
select tt.err('T2 nor read the ratings of a place that is not hers', $$select capacity_rating_list(5)$$, 'not allowed');
select tt.as(:'o');
select tt.chk('T2 the list: 2 active rows; with retired, 3', jsonb_array_length(public.capacity_rating_list(5)) = 2 and jsonb_array_length(public.capacity_rating_list(5, true)) = 3);
select tt.err('T2 retiring a rating needs a reason', format($$select capacity_rating_retire(%s,'x')$$, :'cr2'), 'note_required');
select capacity_rating_retire(:'cr2'::bigint, 'test: line closed') is not null as w_cr \gset
select tt.chk('T2 a retired rating stays as a row', (select status = 'retired' from capacity_ratings where id = :'cr2'::bigint));
select capacity_rating_set(5, :'ln1'::int, 2, 6, :'td'::date - 40, 'test line rating again') is not null as w_cr3 \gset

\echo == T3 labour hours of a run
select tt.as(:'fac');
select (prod_labour_add(:'run1'::uuid, 3, 4, 'test crew one', gen_random_uuid()) ->> 'labour_hours')::numeric as lh1 \gset
select tt.chk('T3 3 people x 4 hours = 12 labour hours', :'lh1'::numeric = 12);
select prod_labour_add(:'run1'::uuid, 2, 1.5, 'test crew two') is not null as w_l2 \gset
select public.prod_labour_list(:'td'::date - 10, :'td'::date, 5) as ll \gset
select tt.chk('T3 two crews on run 1: 12 + 3 = 15 labour hours; run 2 has no entry (empty, not 0)', (select tt.n(r,'labour_hours') = 15 and jsonb_array_length(r -> 'entries') = 2 from jsonb_array_elements(:'ll'::jsonb) r where r ->> 'run_id' = :'run1')
  and (select r -> 'labour_hours' = 'null'::jsonb and jsonb_array_length(r -> 'entries') = 0 from jsonb_array_elements(:'ll'::jsonb) r where r ->> 'run_id' = :'run2'));
select tt.err('T3 0 people is refused', format($$select prod_labour_add(%L::uuid,0,2)$$, :'run2'), 'bad_people');
select tt.err('T3 more than 24 hours is refused', format($$select prod_labour_add(%L::uuid,2,25)$$, :'run2'), 'bad_hours');
select tt.err('T3 0 hours is refused', format($$select prod_labour_add(%L::uuid,2,0)$$, :'run2'), 'bad_hours');
select tt.chk('T3 the same client id twice returns the first row', (prod_labour_add(:'run2'::uuid, 2, 5, null, '00000000-0000-0000-0000-00000000d001') ->> 'id') is not null and (prod_labour_add(:'run2'::uuid, 2, 5, null, '00000000-0000-0000-0000-00000000d001') ->> 'dup')::boolean);
select tt.chk('T3 ... and there is only one row', (select count(*) from production_labour where run_id = :'run2'::uuid) = 1);
select id as lbx from production_labour where run_id = :'run2'::uuid \gset
select tt.err('T3 voiding needs a reason', format($$select prod_labour_void(%s,'')$$, :'lbx'), 'note_required');
select prod_labour_void(:'lbx'::bigint, 'test typed twice') is not null as w_v \gset
select tt.chk('T3 a voided line stays and no longer counts', (select status = 'void' from production_labour where id = :'lbx'::bigint) and (select r -> 'labour_hours' = 'null'::jsonb from jsonb_array_elements(public.prod_labour_list(:'td'::date - 10, :'td'::date, 5)) r where r ->> 'run_id' = :'run2'));
select tt.as(:'shop');
select tt.err('T3 a salesperson cannot add labour hours', format($$select prod_labour_add(%L::uuid,2,2)$$, :'run2'), 'not allowed');
select tt.as(:'o');
select production_post(5, :'rc'::uuid, 1, gen_random_uuid(), now() - interval '2 hours', 'test run to void') ->> 'run_id' as run3 \gset
select production_void(:'run3'::uuid, 'test void') is not null as w_pv \gset
select tt.err('T3 labour on a voided run is refused', format($$select prod_labour_add(%L::uuid,2,2)$$, :'run3'), 'run_void');

\echo == T4 line of a run
select tt.as(:'fac');
select prod_run_line(:'run1'::uuid, :'ln1'::int) is not null as w_rl \gset
select tt.chk('T4 run 1 is on line one; its plan and order links are untouched', (select line_id = :'ln1'::int and plan_id = :'plan_a'::uuid and order_id = :'ord1'::bigint from production_run_links where run_id = :'run1'::uuid));
select prod_run_link(:'run1'::uuid, :'plan_a'::uuid, :'ord1'::bigint) is not null as w_rk \gset
select tt.chk('T4 linking again to the plan keeps the line', (select line_id = :'ln1'::int from production_run_links where run_id = :'run1'::uuid));
select tt.err('T4 a retired line cannot be set', format($$select prod_run_line(%L::uuid,%s)$$, :'run2', :'ln2'), 'line_not_found');
select prod_run_line(:'run2'::uuid, :'ln1'::int) is not null as w_rl2 \gset
select tt.chk('T4 a run with no earlier link gets a link row with the line only', (select line_id = :'ln1'::int and plan_id is null from production_run_links where run_id = :'run2'::uuid));
select prod_run_line(:'run2'::uuid, null) is not null as w_rl3 \gset
select tt.chk('T4 clearing the line leaves it blank', (select line_id is null from production_run_links where run_id = :'run2'::uuid));
select tt.err('T4 a voided run is refused', format($$select prod_run_line(%L::uuid,%s)$$, :'run3', :'ln1'), 'run_void');
select tt.as(:'o');

\echo == T5 paste twice
\ir phase412.sql
select tt.chk('T5 pasting the file again keeps the data', (select count(*) from production_lines) = 2 and (select count(*) from capacity_ratings) = 4 and (select count(*) from production_labour) = 3);

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
