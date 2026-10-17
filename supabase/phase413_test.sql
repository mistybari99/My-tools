-- FRESH DB ONLY. Phase 413 tests: output per labour hour (#48) and capacity utilization (#51) (package RPT-B4, R8b).
--   Build a database through phase 99, paste supabase/phase404.sql, phase405.sql, phase412.sql and phase413.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase413_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql and rb4_fixture2.sql (hand-computed numbers in the headers) plus labour and ratings made below. Test data only (test_* names).
--   labour : run 1 = 3 people x 4 h + 2 people x 1.5 h = 15 h (output 18 -> 1.2 per hour) | run 2 = 2 people x 5 h = 10 h (output 10 -> 1.0 per hour)
--   rating : place 5 = 4 batches a day, 6 days a week, from D-40 -> a 7-day period has 7 x 4 x 6 / 7 = 24 batches of capacity; 3 batches made (2 + 1) = 12.5 %
--            line one = 2 batches a day, 6 days a week, from D-40 -> 12 batches in 7 days; run 1 (2 batches) is on it = 16.7 %
--            line three = 3 batches a day, 7 days a week, from D-2 -> 3 rated days in the 7-day period, 9 batches of capacity; run 2 (1 batch, D-1) is on it = 11.1 %; run 1 (D-3, 2 batches) was made on an unrated day
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\ir ../tests/sql/rb4_fixture2.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select to_char(:'td'::date - 6, 'YYYY-MM-DD') as d6 \gset

\echo == T0 shape
select tt.chk('T0 both reports open to signed-in users only', has_function_privilege('authenticated','public.rb4_labour_productivity(date,date,int,uuid)','execute') and has_function_privilege('authenticated','public.rb4_capacity_utilization(date,date,int)','execute')
  and not has_function_privilege('anon','public.rb4_capacity_utilization(date,date,int)','execute'));

\echo == T1 labour productivity
select public.rb4_labour_productivity(:'d6'::date, :'td'::date, 5) as p0 \gset
select tt.chk('T1 nothing recorded yet: every run is labour_not_captured, the figure is EMPTY (never 0) and a note says so', (select bool_and(r ->> 'status' = 'labour_not_captured' and r -> 'output_per_hour' = 'null'::jsonb and r -> 'labour_hours' = 'null'::jsonb) from jsonb_array_elements(:'p0'::jsonb -> 'rows') r)
  and (:'p0'::jsonb -> 'notes' -> 0 ->> 'code') = 'labour_not_captured' and jsonb_array_length(:'p0'::jsonb -> 'by_item') = 1);
select tt.as(:'fac');
select prod_labour_add(:'run1'::uuid, 3, 4) is not null as w1 \gset
select prod_labour_add(:'run1'::uuid, 2, 1.5) is not null as w2 \gset
select prod_labour_add(:'run2'::uuid, 2, 5) is not null as w3 \gset
select tt.as(:'o');
select public.rb4_labour_productivity(:'d6'::date, :'td'::date, 5) as p1 \gset
select tt.chk('T1 run 1: 15 labour hours (2 crews, 5 people), 18 output -> 1.2 per hour, 0.8333 hours per unit', (select tt.n(r,'labour_hours') = 15 and (r ->> 'crews')::int = 2 and tt.n(r,'people') = 5 and tt.n(r,'output_per_hour') = 1.2 and tt.n(r,'hours_per_unit') = 0.8333 and r ->> 'status' = 'measured' from jsonb_array_elements(:'p1'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T1 run 2: 10 hours, output 10 -> 1.0 per hour', (select tt.n(r,'labour_hours') = 10 and tt.n(r,'output_per_hour') = 1.0 from jsonb_array_elements(:'p1'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2'));
select tt.chk('T1 by item: 2 runs measured, output 28 over 25 hours = 1.12 per hour', (select (s ->> 'measured')::int = 2 and tt.n(s,'output_measured') = 28 and tt.n(s,'labour_hours') = 25 and tt.n(s,'output_per_hour') = 1.12 from jsonb_array_elements(:'p1'::jsonb -> 'by_item') s where s ->> 'code' = 'RB4-FG'));
select tt.chk('T1 by place: place 5 has 2 runs measured, 25 hours, 3 batches -> 0.12 batches per hour', (select (s ->> 'measured')::int = 2 and tt.n(s,'labour_hours') = 25 and tt.n(s,'batches_measured') = 3 and tt.n(s,'batches_per_hour') = 0.12 from jsonb_array_elements(:'p1'::jsonb -> 'by_place') s where (s ->> 'location_id')::int = 5));
select tt.chk('T1 no note when some runs are measured', jsonb_array_length(:'p1'::jsonb -> 'notes') = 0);
select prod_labour_void((select id from production_labour where run_id = :'run2'::uuid and status = 'active'), 'test typed wrong') is not null as w_v \gset
select public.rb4_labour_productivity(:'d6'::date, :'td'::date, 5) as p2 \gset
select tt.chk('T1 after the labour line of run 2 is voided: run 2 is not captured again and drops out of the totals (18 over 15 h = 1.2)', (select r ->> 'status' = 'labour_not_captured' from jsonb_array_elements(:'p2'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2')
  and (select (s ->> 'measured')::int = 1 and (s ->> 'labour_not_captured')::int = 1 and tt.n(s,'output_per_hour') = 1.2 from jsonb_array_elements(:'p2'::jsonb -> 'by_item') s where s ->> 'code' = 'RB4-FG'));
select tt.chk('T1 an item filter on a raw item finds no run', jsonb_array_length(public.rb4_labour_productivity(:'d6'::date, :'td'::date, 5, :'i_rm'::uuid) -> 'rows') = 0);
select tt.as(:'shop');
select tt.err('T1 a salesperson cannot ask for place 5', $$select rb4_labour_productivity(null, null, 5)$$, 'not allowed');
select tt.chk('T1 without a place a salesperson sees nothing of place 5', jsonb_array_length(public.rb4_labour_productivity(:'d6'::date, :'td'::date) -> 'rows') = 0);
select tt.as(:'o');
select tt.err('T1 a bad range is refused', $$select rb4_labour_productivity(current_date, current_date - 2)$$, 'bad_range');

\echo == T2 capacity utilization
select public.rb4_capacity_utilization(:'d6'::date, :'td'::date, 5) as c0 \gset
select tt.chk('T2 no rating yet: place 5 is listed with "rated capacity not captured", capacity and % EMPTY (never 0), the 3 batches made are still shown, and a note says so',
  (select r ->> 'status' = 'rated_capacity_not_captured' and r -> 'capacity_batches' = 'null'::jsonb and r -> 'utilization_pct' = 'null'::jsonb and tt.n(r,'batches_made') = 3 from jsonb_array_elements(:'c0'::jsonb -> 'rows') r where r -> 'line_id' = 'null'::jsonb)
  and (:'c0'::jsonb -> 'notes' -> 0 ->> 'code') = 'capacity_not_captured');
select production_line_set(null, 5, 'test_line_one', 'Test line one') ->> 'id' as ln1 \gset
select production_line_set(null, 5, 'test_line_three', 'Test line three') ->> 'id' as ln3 \gset
select capacity_rating_set(5, null, 4, 6, :'td'::date - 40) is not null as w_c1 \gset
select capacity_rating_set(5, :'ln1'::int, 2, 6, :'td'::date - 40) is not null as w_c2 \gset
select capacity_rating_set(5, :'ln3'::int, 3, 7, :'td'::date - 2) is not null as w_c3 \gset
select prod_run_line(:'run1'::uuid, :'ln1'::int) is not null as w_l1 \gset
select prod_run_line(:'run2'::uuid, :'ln3'::int) is not null as w_l2 \gset
select public.rb4_capacity_utilization(:'d6'::date, :'td'::date, 5) as c1 \gset
select tt.chk('T2 place 5: 7 days x 4 batches x 6/7 = 24 batches of capacity, 3 made = 12.5 %, status rated', (select tt.n(r,'capacity_batches') = 24 and tt.n(r,'batches_made') = 3 and tt.n(r,'utilization_pct') = 12.5 and r ->> 'status' = 'rated' and (r ->> 'days_rated')::int = 7
   from jsonb_array_elements(:'c1'::jsonb -> 'rows') r where r -> 'line_id' = 'null'::jsonb));
select tt.chk('T2 line one: 12 batches of capacity, run 1 (2 batches) = 16.7 %', (select tt.n(r,'capacity_batches') = 12 and tt.n(r,'batches_made') = 2 and tt.n(r,'utilization_pct') = 16.7 from jsonb_array_elements(:'c1'::jsonb -> 'rows') r where (r ->> 'line_id')::int = :'ln1'::int));
select tt.chk('T2 line three rated from D-2: 3 rated days, 4 not rated; capacity 3 x 3 = 9 batches; run 2 (1 batch on a rated day) = 11.1 %; status partly_rated', (select (r ->> 'days_rated')::int = 3 and (r ->> 'days_not_rated')::int = 4 and tt.n(r,'capacity_batches') = 9 and tt.n(r,'batches_made_on_rated_days') = 1 and tt.n(r,'utilization_pct') = 11.1 and r ->> 'status' = 'partly_rated'
   from jsonb_array_elements(:'c1'::jsonb -> 'rows') r where (r ->> 'line_id')::int = :'ln3'::int));
select prod_run_line(:'run1'::uuid, :'ln3'::int) is not null as w_l3 \gset
select public.rb4_capacity_utilization(:'d6'::date, :'td'::date, 5) as c2 \gset
select tt.chk('T2 run 1 (2 batches, D-3) moved to line three: it was made on a day line three had no rating -> shown apart (2), not judged; the 11.1 % stays', (select tt.n(r,'batches_made_on_days_not_rated') = 2 and tt.n(r,'utilization_pct') = 11.1 and tt.n(r,'batches_made') = 3 from jsonb_array_elements(:'c2'::jsonb -> 'rows') r where (r ->> 'line_id')::int = :'ln3'::int));
select tt.chk('T2 a longer period with a rating change: the rating in force each day is used (place rating raised to 8 from D-3: days D-6..D-4 use 4, D-3..D use 8)',
  (capacity_rating_set(5, null, 8, 7, :'td'::date - 3) is not null) and true);
select public.rb4_capacity_utilization(:'d6'::date, :'td'::date, 5) as c3 \gset
select tt.chk('T2 capacity = 3 days x 4 x 6/7 + 4 days x 8 = 10.29 + 32 = 42.29; 3 made = 7.1 %', (select tt.near(tt.n(r,'capacity_batches'), 42.29, 0.01) and tt.n(r,'utilization_pct') = 7.1 and tt.n(r,'rated_batches_per_day') = 8 from jsonb_array_elements(:'c3'::jsonb -> 'rows') r where r -> 'line_id' = 'null'::jsonb));
select tt.chk('T2 the place filter works: place 1 has no run and no rating -> no row', jsonb_array_length(public.rb4_capacity_utilization(:'d6'::date, :'td'::date, 1) -> 'rows') = 0);
select tt.as(:'shop');
select tt.err('T2 a salesperson cannot ask for place 5', $$select rb4_capacity_utilization(null, null, 5)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T2 a bad range is refused', $$select rb4_capacity_utilization(current_date, current_date - 2)$$, 'bad_range');

\echo == T3 paste twice
\ir phase413.sql
select tt.chk('T3 pasting the file again keeps the answer', (public.rb4_capacity_utilization(:'d6'::date, :'td'::date, 5) -> 'rows') = (public.rb4_capacity_utilization(:'d6'::date, :'td'::date, 5) -> 'rows'));

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
