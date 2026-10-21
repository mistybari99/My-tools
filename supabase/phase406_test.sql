-- FRESH DB ONLY. Phase 406 tests: plan vs actual (#40), order status and pending (#52), production-to-dispatch reconciliation (#53) (package RPT-B4, R4a).
--   Build a database through phase 99, paste supabase/phase404.sql .. phase406.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase406_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql and rb4_fixture2.sql (hand-computed numbers in the headers). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\ir ../tests/sql/rb4_fixture2.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select to_char(:'td'::date - 10, 'YYYY-MM-DD') as d_from, to_char(:'td'::date + 3, 'YYYY-MM-DD') as d_to, to_char(:'td'::date - 3, 'YYYY-MM-DD') as dm3, to_char(:'td'::date - 1, 'YYYY-MM-DD') as dm1, to_char(:'td'::date + 2, 'YYYY-MM-DD') as dp2 \gset

\echo == T0 shape
select tt.chk('T0 three reports open to signed-in users only, internals closed',
  has_function_privilege('authenticated','public.rb4_plan_vs_actual(date,date,int)','execute') and not has_function_privilege('anon','public.rb4_order_status(date,date,int,text)','execute')
  and not has_function_privilege('authenticated','public._rb4_pva_runs(date,date,int)','execute') and not has_function_privilege('authenticated','public._rb4_dr_rows(date,date,int)','execute'));

\echo == T1 plan vs actual
select public.rb4_plan_vs_actual(:'d_from'::date, :'d_to'::date, 5) as pva \gset
select tt.chk('T1 plan A (D-3, 2 batches = 20 kg): made 18 kg in 1 run = 90.0 %, status short, the run id is there for the drill-down',
  (select tt.n(r,'planned_qty') = 20 and tt.n(r,'planned_batches') = 2 and tt.n(r,'actual_qty') = 18 and tt.n(r,'achievement_pct') = 90.0 and r ->> 'status' = 'short' and (r ->> 'runs_n')::int = 1 and r -> 'run_ids' ->> 0 = :'run1'
     from jsonb_array_elements(:'pva'::jsonb -> 'rows') r where r ->> 'plan_date' = :'dm3'));
select tt.chk('T1 plan C (D+2): nothing made, not due yet - not "short", not 0 %', (select r ->> 'status' = 'not_due_yet' and tt.n(r,'actual_qty') = 0 and r -> 'achievement_pct' = 'null'::jsonb from jsonb_array_elements(:'pva'::jsonb -> 'rows') r where r ->> 'plan_date' = :'dp2'));
select tt.chk('T1 run 2 (D-1, 10 kg) has no plan: listed as unplanned, not hidden', jsonb_array_length(:'pva'::jsonb -> 'unplanned') = 1 and (select tt.n(u,'qty') = 10 and u ->> 'day' = :'dm1' from jsonb_array_elements(:'pva'::jsonb -> 'unplanned') u limit 1));
select tt.chk('T1 summary: 2 plans, 1 short, 0 met, 1 unplanned run, no note about missing plans', tt.n(:'pva'::jsonb -> 'summary','plans') = 2 and tt.n(:'pva'::jsonb -> 'summary','rows_short') = 1 and tt.n(:'pva'::jsonb -> 'summary','rows_met') = 0
  and tt.n(:'pva'::jsonb -> 'summary','unplanned_runs') = 1 and jsonb_array_length(:'pva'::jsonb -> 'notes') = 0);
select (prod_plan_add(:'dm1'::date, 5, :'i_fg'::uuid, 1, null, null, null, 'test plan for run 2', gen_random_uuid()) ->> 'id')::uuid as plan_b \gset
select (prod_plan_add(:'dm1'::date, 5, :'i_rm'::uuid, 3, null, null, null, 'test plan, item without a recipe', gen_random_uuid()) ->> 'id')::uuid as plan_n \gset
select public.rb4_plan_vs_actual(:'d_from'::date, :'d_to'::date, 5) as pva2 \gset
select tt.chk('T1 a plan for D-1 with the same place + item: run 2 matches it by day -> met 10 / 10 = 100.0 %, and it is no longer unplanned',
  (select r ->> 'status' = 'met' and tt.n(r,'achievement_pct') = 100.0 and tt.n(r,'actual_qty') = 10 from jsonb_array_elements(:'pva2'::jsonb -> 'rows') r where r ->> 'plan_date' = :'dm1' and r ->> 'code' = 'RB4-FG')
  and jsonb_array_length(:'pva2'::jsonb -> 'unplanned') = 0);
select tt.chk('T1 a plan in batches for an item with no recipe: the planned quantity is EMPTY and the status says so (never 0)',
  (select r ->> 'status' = 'qty_not_captured' and r -> 'planned_qty' = 'null'::jsonb and r -> 'achievement_pct' = 'null'::jsonb and tt.n(r,'planned_batches') = 3 from jsonb_array_elements(:'pva2'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-RM'));
select tt.chk('T1 four plan rows now (A, B, the recipe-less one, C)', jsonb_array_length(:'pva2'::jsonb -> 'rows') = 4);
select prod_plan_cancel(:'plan_n'::uuid, 'test cancel') is not null as w_pc \gset
select public.rb4_plan_vs_actual(:'d_from'::date, :'d_to'::date, 5) as pva3 \gset
select tt.chk('T1 after the cancel: the plan row is gone from the rows, counted in cancelled_plans', jsonb_array_length(:'pva3'::jsonb -> 'rows') = 3 and tt.n(:'pva3'::jsonb -> 'summary','cancelled_plans') = 1);
select prod_run_link(:'run2'::uuid, :'plan_b'::uuid, null) is not null as w_lk \gset
select tt.chk('T1 an explicit link keeps run 2 on plan B', (select plan_id = :'plan_b'::uuid and order_id is not null from production_run_links where run_id = :'run2'::uuid));
-- a run linked to a plan of ANOTHER day counts for that plan day
select (prod_plan_add(:'dm3'::date, 5, :'i_fg'::uuid, 1, null, null, null, 'test second plan same key', gen_random_uuid()) ->> 'id')::uuid as plan_e \gset
select public.rb4_plan_vs_actual(:'d_from'::date, :'d_to'::date, 5) as pva4 \gset
select tt.chk('T1 two plans on the same place + item + day are one row: planned 20 + 10 = 30 kg, 18 made = 60.0 %', (select (r ->> 'plans_n')::int = 2 and tt.n(r,'planned_qty') = 30 and tt.n(r,'achievement_pct') = 60.0 from jsonb_array_elements(:'pva4'::jsonb -> 'rows') r where r ->> 'plan_date' = :'dm3'));
select tt.err('T1 a bad range is refused', $$select rb4_plan_vs_actual(current_date, current_date - 3)$$, 'bad_range');
select tt.as(:'shop');
select tt.err('T1 a salesperson of place 1 cannot ask for place 5', $$select rb4_plan_vs_actual(null, null, 5)$$, 'not allowed');
select tt.chk('T1 for no place given a salesperson sees an empty answer (nothing of place 5 leaks)', jsonb_array_length(public.rb4_plan_vs_actual(:'d_from'::date, :'d_to'::date) -> 'rows') = 0 and jsonb_array_length(public.rb4_plan_vs_actual(:'d_from'::date, :'d_to'::date) -> 'unplanned') = 0);
select tt.as(:'rep');
select tt.chk('T1 a holder of the stock report right at place 5 sees the same rows', jsonb_array_length(public.rb4_plan_vs_actual(:'d_from'::date, :'d_to'::date, 5) -> 'rows') = 3);
select tt.as(:'o');
select tt.chk('T1 with no plan at all in a period the answer carries the note "plan not captured" (and no 0 %)', (select public.rb4_plan_vs_actual(:'td'::date - 600, :'td'::date - 500, 5) -> 'notes' -> 0 ->> 'code') = 'plan_not_captured');

\echo == T2 order status
select public.rb4_order_status(:'d_from'::date, :'d_to'::date, 5) as os \gset
select tt.chk('T2 order 1: 25 ordered, 18 made, balance 7, due yesterday -> overdue by 1 day, named place and outlet',
  (select tt.n(r,'qty') = 25 and tt.n(r,'made') = 18 and tt.n(r,'balance') = 7 and r ->> 'state' = 'overdue' and tt.n(r,'days_overdue') = 1 and (r ->> 'for_location_id')::int = 1 and r -> 'run_ids' ->> 0 = :'run1'
     from jsonb_array_elements(:'os'::jsonb -> 'rows') r where (r ->> 'order_no')::bigint = :'ord1'::bigint));
select tt.chk('T2 order 2: 10 ordered, 10 made but still open -> made_not_closed, balance 0', (select r ->> 'state' = 'made_not_closed' and tt.n(r,'balance') = 0 from jsonb_array_elements(:'os'::jsonb -> 'rows') r where (r ->> 'order_no')::bigint = :'ord2'::bigint));
select tt.chk('T2 order 3: nothing linked -> not_started, 0 made, due in 5 days (no overdue figure)', (select r ->> 'state' = 'not_started' and tt.n(r,'made') = 0 and r -> 'days_overdue' = 'null'::jsonb from jsonb_array_elements(:'os'::jsonb -> 'rows') r where (r ->> 'order_no')::bigint = :'ord3'::bigint));
select tt.chk('T2 the overdue order is listed first; summary 3 orders, 3 open, 1 overdue, 1 not started, 1 made-not-closed', (:'os'::jsonb -> 'rows' -> 0 ->> 'state') = 'overdue'
  and tt.n(:'os'::jsonb -> 'summary','orders') = 3 and tt.n(:'os'::jsonb -> 'summary','open') = 3 and tt.n(:'os'::jsonb -> 'summary','overdue') = 1 and tt.n(:'os'::jsonb -> 'summary','not_started') = 1 and tt.n(:'os'::jsonb -> 'summary','made_not_closed') = 1);
select tt.chk('T2 filter overdue = 1 row; filter pending = 3 rows', jsonb_array_length(public.rb4_order_status(:'d_from'::date, :'d_to'::date, 5, 'overdue') -> 'rows') = 1 and jsonb_array_length(public.rb4_order_status(:'d_from'::date, :'d_to'::date, 5, 'pending') -> 'rows') = 3);
select tt.err('T2 an unknown status filter is refused', $$select rb4_order_status(null, null, null, 'weird')$$, 'bad_status');
select prod_order_close(:'ord2'::bigint) is not null as w_c2 \gset
select prod_order_cancel(:'ord3'::bigint, 'test: not needed') is not null as w_c3 \gset
select public.rb4_order_status(:'td'::date - 3, :'td'::date, 5) as os2 \gset
select tt.chk('T2 a closed and a cancelled order stay in the list for their period; the old open order 1 stays too (pending is never dropped by the date filter)',
  (select count(*) from jsonb_array_elements(:'os2'::jsonb -> 'rows')) = 3 and tt.n(:'os2'::jsonb -> 'summary','open') = 1
  and (select r ->> 'state' from jsonb_array_elements(:'os2'::jsonb -> 'rows') r where (r ->> 'order_no')::bigint = :'ord2'::bigint) = 'closed'
  and (select r ->> 'state' from jsonb_array_elements(:'os2'::jsonb -> 'rows') r where (r ->> 'order_no')::bigint = :'ord3'::bigint) = 'cancelled');
select (prod_order_add(:'td'::date, null, 5, null, :'i_fg'::uuid, 3, null, 'test no due day', gen_random_uuid()) ->> 'id')::bigint as ord5 \gset
select tt.chk('T2 an order without a due day says "due day not captured"; it is never overdue', (select (r ->> 'due_not_captured')::boolean and r ->> 'state' = 'not_started' from jsonb_array_elements(public.rb4_order_status(:'d_from'::date, :'d_to'::date, 5) -> 'rows') r where (r ->> 'order_no')::bigint = :'ord5'::bigint)
  and tt.n(public.rb4_order_status(:'d_from'::date, :'d_to'::date, 5) -> 'summary','due_not_captured') = 1);
select tt.as(:'shop');
select tt.chk('T2 a salesperson who may not read production sees no order, even the one meant for outlet 1', jsonb_array_length(public.rb4_order_status(:'d_from'::date, :'d_to'::date) -> 'rows') = 0);
select tt.as(:'o');

\echo == T3 dispatch reconciliation
select stock_transfer(5, 1, :'i_sg'::uuid, 5, null, 'test raw transfer', gen_random_uuid()) is not null as w_rt \gset
select public.rb4_dispatch_recon(:'d_from'::date, :'td'::date, 5) as dr \gset
select tt.chk('T3 D-3: made 18 in 1 run, nothing sent', (select tt.n(r,'made') = 18 and tt.n(r,'sent') = 0 and (r ->> 'runs_n')::int = 1 from jsonb_array_elements(:'dr'::jsonb -> 'rows') r where r ->> 'day' = :'dm3' and r ->> 'code' = 'RB4-FG'));
select tt.chk('T3 today: sent 17 (15 + 2), received 14, in transit 2, short 1, and the tie sent = received + in transit + short holds',
  (select tt.n(r,'sent') = 17 and tt.n(r,'received') = 14 and tt.n(r,'in_transit') = 2 and tt.n(r,'short') = 1 and (r ->> 'tie_ok')::boolean and (r ->> 'transfers_n')::int = 2 from jsonb_array_elements(:'dr'::jsonb -> 'rows') r where r ->> 'day' = :'td' and r ->> 'code' = 'RB4-FG'));
select tt.chk('T3 summary for the sweet: made 28, sent 17, received 14, in transit 2, short 1, made - sent = 11, on hand now 10',
  (select tt.n(s,'made') = 28 and tt.n(s,'sent') = 17 and tt.n(s,'received') = 14 and tt.n(s,'in_transit') = 2 and tt.n(s,'short') = 1 and tt.n(s,'made_not_sent') = 11 and tt.n(s,'on_hand_now') = 10 and (s ->> 'tie_ok')::boolean
     from jsonb_array_elements(:'dr'::jsonb -> 'summary') s where s ->> 'code' = 'RB4-FG'));
select tt.chk('T3 the raw sugar transfer is NOT in this report (the place never produced sugar)', not exists (select 1 from jsonb_array_elements(:'dr'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-SG'));
select stock_receive_transfer(:'t2'::uuid, 2, 'test arrived') is not null as w_r2 \gset
select public.rb4_dispatch_recon(:'d_from'::date, :'td'::date, 5) as dr2 \gset
select tt.chk('T3 after the second transfer arrives: in transit 0, received 16, short still 1', (select tt.n(s,'in_transit') = 0 and tt.n(s,'received') = 16 and tt.n(s,'short') = 1 from jsonb_array_elements(:'dr2'::jsonb -> 'summary') s where s ->> 'code' = 'RB4-FG'));
select tt.chk('T3 a period with nothing in it is an empty answer, not an error',
  jsonb_array_length(public.rb4_dispatch_recon(:'td'::date - 600, :'td'::date - 500, 5) -> 'rows') = 0);
select tt.as(:'shop');
select tt.err('T3 a salesperson cannot ask for place 5', $$select rb4_dispatch_recon(null, null, 5)$$, 'not allowed');
select tt.chk('T3 without a place a salesperson sees nothing of place 5', jsonb_array_length(public.rb4_dispatch_recon(:'d_from'::date, :'td'::date) -> 'rows') = 0);
select tt.as(:'o');

\echo == T4 paste twice
\ir phase406.sql
select tt.chk('T4 pasting phase 406 again keeps the answers', public.rb4_order_status(:'d_from'::date, :'d_to'::date, 5) -> 'summary' = public.rb4_order_status(:'d_from'::date, :'d_to'::date, 5) -> 'summary');

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
