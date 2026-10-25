-- FRESH DB ONLY. Phase 411 tests: the target tile for the owner board (package RPT-B4, R5c).
--   Build a database through phase 99, paste supabase/phase404.sql .. phase411.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase411_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql (sale of 800 at place 1 today). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select date_trunc('month', :'td'::date)::date as m0 \gset

\echo == T1 tile
select public.rb4_target_tile() as t0 \gset
select tt.chk('T1 no target yet: no line, a note says "target not set"; place 1 is listed as sold-but-no-target with its 800', jsonb_array_length(:'t0'::jsonb -> 'rows') = 0 and (:'t0'::jsonb -> 'notes' -> 0 ->> 'code') = 'target_not_set'
  and (select tt.n(e,'achieved') = 800 from jsonb_array_elements(:'t0'::jsonb -> 'no_target') e where (e ->> 'location_id')::int = 1) and :'t0'::jsonb -> 'total' = 'null'::jsonb);
select sales_target_set(1, :'td'::date, 10000, 30) is not null as w_a \gset
select sales_target_set(2, :'td'::date, 5000) is not null as w_b \gset
select public.rb4_target_tile() as t1 \gset
select tt.chk('T1 two targets: two lines, total target 15000, achieved 800 (place 1 only), 5.3 %', jsonb_array_length(:'t1'::jsonb -> 'rows') = 2 and tt.n(:'t1'::jsonb -> 'total','target') = 15000 and tt.n(:'t1'::jsonb -> 'total','achieved') = 800 and tt.n(:'t1'::jsonb -> 'total','achievement_pct') = 5.3
  and jsonb_array_length(:'t1'::jsonb -> 'no_target') = 0 and :'t1'::jsonb ->> 'month' = to_char(:'m0'::date, 'YYYY-MM-DD'));
select tt.chk('T1 each line carries target, achieved, achievement % and pace %', (select tt.n(e,'target') = 10000 and tt.n(e,'achieved') = 800 and tt.n(e,'achievement_pct') = 8.0 and e -> 'pace_pct' <> 'null'::jsonb from jsonb_array_elements(:'t1'::jsonb -> 'rows') e where (e ->> 'location_id')::int = 1));
select tt.chk('T1 behind count equals the number of lines whose status is behind', (:'t1'::jsonb ->> 'behind')::int = (select count(*) from jsonb_array_elements(:'t1'::jsonb -> 'rows') e where e ->> 'status' = 'behind'));
select tt.chk('T1 another month has no line', jsonb_array_length(public.rb4_target_tile(:'m0'::date - 40) -> 'rows') = 0);
select tt.as(:'shop');
select tt.chk('T1 a salesperson without the sales right sees no target line (places are filtered by the right)', jsonb_array_length(public.rb4_target_tile() -> 'rows') = 0 and jsonb_array_length(public.rb4_target_tile() -> 'no_target') = 0);
select tt.as(:'o');
select tt.chk('T1 closed to anon, open to signed-in users', has_function_privilege('authenticated','public.rb4_target_tile(date)','execute') and not has_function_privilege('anon','public.rb4_target_tile(date)','execute'));
\ir phase411.sql
select tt.chk('T1 pasting the file again keeps the answer', (public.rb4_target_tile() -> 'total') = (public.rb4_target_tile() -> 'total'));

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
