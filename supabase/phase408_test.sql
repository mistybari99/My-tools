-- FRESH DB ONLY. Phase 408 tests: run-level yield (#45), reject / rework / production loss (#49), wastage with the batch and run dimension (#50) (package RPT-B4, R4c).
--   Build a database through phase 99, paste supabase/phase404.sql .. phase408.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase408_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql and rb4_fixture2.sql (hand-computed numbers in the headers). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\ir ../tests/sql/rb4_fixture2.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select to_char(:'td'::date - 10, 'YYYY-MM-DD') as d_from \gset

\echo == T0 shape
select tt.chk('T0 three reports open to signed-in users only', has_function_privilege('authenticated','public.rb4_run_yield(date,date,int,uuid)','execute') and has_function_privilege('authenticated','public.rb4_losses(date,date,int,uuid)','execute')
  and not has_function_privilege('anon','public.rb4_wastage_dim(date,date,int,uuid)','execute'));

\echo == T1 run-level yield
select public.rb4_run_yield(:'d_from'::date, :'td'::date, 5) as y \gset
select tt.chk('T1 run 1: standard 20, typed 18 -> -2 kg = -10.00 %', (select tt.n(r,'yield_std') = 20 and tt.n(r,'yield_actual') = 18 and tt.n(r,'var_qty') = -2 and tt.n(r,'var_pct') = -10 and r ->> 'status' = 'measured' from jsonb_array_elements(:'y'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T1 run 2: nothing typed -> actual, difference and % are EMPTY (never 0) and the status says not_captured; the booked output 10 is still shown',
  (select r -> 'yield_actual' = 'null'::jsonb and r -> 'var_qty' = 'null'::jsonb and r -> 'var_pct' = 'null'::jsonb and r ->> 'status' = 'not_captured' and tt.n(r,'booked_output') = 10 from jsonb_array_elements(:'y'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2'));
select tt.chk('T1 summary: 2 runs, 1 measured, 1 not captured; over the measured run 20 -> 18 = -10.00 %', (select (s ->> 'runs')::int = 2 and (s ->> 'measured')::int = 1 and (s ->> 'not_captured')::int = 1 and tt.n(s,'std_qty_measured') = 20 and tt.n(s,'actual_qty_measured') = 18 and tt.n(s,'var_pct') = -10 from jsonb_array_elements(:'y'::jsonb -> 'summary') s where s ->> 'code' = 'RB4-FG'));
select tt.chk('T1 the owner has not set a warning limit: no run is flagged (over_limit empty) and the note says the limit is not set', (select bool_and(r -> 'over_limit' = 'null'::jsonb) from jsonb_array_elements(:'y'::jsonb -> 'rows') r)
  and exists (select 1 from jsonb_array_elements(:'y'::jsonb -> 'notes') n where n ->> 'code' = 'limit_not_set'));
update rules set value = '5'::jsonb where key = 'yield_variance_warn_pct';
select public.rb4_run_yield(:'d_from'::date, :'td'::date, 5) as y2 \gset
select tt.chk('T1 with the owner limit 5 %: run 1 (-10 %) is over the limit, run 2 is not judged', (select (r ->> 'over_limit')::boolean from jsonb_array_elements(:'y2'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1')
  and (select r -> 'over_limit' = 'null'::jsonb from jsonb_array_elements(:'y2'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2') and not exists (select 1 from jsonb_array_elements(:'y2'::jsonb -> 'notes') n where n ->> 'code' = 'limit_not_set'));
select tt.chk('T1 an item filter works (raw milk makes no run)', jsonb_array_length(public.rb4_run_yield(:'d_from'::date, :'td'::date, 5, :'i_rm'::uuid) -> 'rows') = 0);
select tt.as(:'shop');
select tt.err('T1 a salesperson cannot ask for place 5', $$select rb4_run_yield(null, null, 5)$$, 'not allowed');
select tt.chk('T1 without a place a salesperson sees no run', jsonb_array_length(public.rb4_run_yield(:'d_from'::date, :'td'::date) -> 'rows') = 0);
select tt.as(:'o');
select tt.err('T1 a bad range is refused', $$select rb4_run_yield(current_date, current_date - 2)$$, 'bad_range');

\echo == T2 reject / rework
select public.rb4_losses(:'d_from'::date, :'td'::date, 5) as x \gset
select tt.chk('T2 run 1: recorded, reject 1 kg = 5.56 % of 18, rework 0.5 kg = 2.78 %', (select r ->> 'state' = 'recorded' and tt.n(r,'reject_qty') = 1 and tt.n(r,'reject_pct') = 5.56 and tt.n(r,'rework_qty') = 0.5 and tt.n(r,'rework_pct') = 2.78 and jsonb_array_length(r -> 'lines') = 2
   from jsonb_array_elements(:'x'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T2 run 2: "checked, none" -> state none, a real 0 and 0.00 %', (select r ->> 'state' = 'none' and tt.n(r,'reject_qty') = 0 and tt.n(r,'reject_pct') = 0 from jsonb_array_elements(:'x'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2'));
select tt.chk('T2 by item over the 2 known runs: output 28, reject 1 = 3.57 %, rework 0.5 = 1.79 %', (select tt.n(s,'output_known') = 28 and tt.n(s,'reject_pct') = 3.57 and tt.n(s,'rework_pct') = 1.79 and (s ->> 'runs_known')::int = 2 from jsonb_array_elements(:'x'::jsonb -> 'by_item') s where s ->> 'code' = 'RB4-FG'));
select tt.chk('T2 by reason: burnt = 1 reject, broken = 1 rework (the wastage list labels)', (select (s ->> 'reject_n')::int = 1 and s ->> 'reason' = 'Burnt' from jsonb_array_elements(:'x'::jsonb -> 'by_reason') s where s ->> 'reason_code' = 'burnt')
  and (select (s ->> 'rework_n')::int = 1 from jsonb_array_elements(:'x'::jsonb -> 'by_reason') s where s ->> 'reason_code' = 'broken'));
select tt.chk('T2 summary: 2 runs, 1 recorded, 1 none, 0 not captured', tt.n(:'x'::jsonb -> 'summary','runs') = 2 and tt.n(:'x'::jsonb -> 'summary','recorded') = 1 and tt.n(:'x'::jsonb -> 'summary','none') = 1 and tt.n(:'x'::jsonb -> 'summary','not_captured') = 0);
select production_post(5, :'rc'::uuid, 1, gen_random_uuid(), now() - interval '1 hour', 'test run 3') ->> 'run_id' as run3 \gset
select public.rb4_losses(:'d_from'::date, :'td'::date, 5) as x2 \gset
select tt.chk('T2 a new run with nothing recorded is not_captured: reject and rework EMPTY, not in the percentages', (select r ->> 'state' = 'not_captured' and r -> 'reject_qty' = 'null'::jsonb and r -> 'reject_pct' = 'null'::jsonb from jsonb_array_elements(:'x2'::jsonb -> 'rows') r where r ->> 'run_id' = :'run3')
  and (select (s ->> 'runs_not_captured')::int = 1 and tt.n(s,'output_known') = 28 and tt.n(s,'reject_pct') = 3.57 from jsonb_array_elements(:'x2'::jsonb -> 'by_item') s where s ->> 'code' = 'RB4-FG') and tt.n(:'x2'::jsonb -> 'summary','not_captured') = 1);
select tt.chk('T2 with no run in the period the answer is empty', jsonb_array_length(public.rb4_losses(:'td'::date - 600, :'td'::date - 500, 5) -> 'rows') = 0);
select prod_loss_void(l.id, 'test void') is not null as w_v from production_loss l where l.run_id = :'run1'::uuid and l.status = 'active' \gset
select public.rb4_losses(:'d_from'::date, :'td'::date, 5) as x3 \gset
select tt.chk('T2 when every loss line of a run is voided the run is not_captured again (nothing says "none")', (select r ->> 'state' = 'not_captured' from jsonb_array_elements(:'x3'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T2 with no run captured at all the answer carries the note "loss not captured"', (select count(*) from jsonb_array_elements(public.rb4_losses(:'td'::date - 3, :'td'::date - 3, 5) -> 'notes') n where n ->> 'code' = 'loss_not_captured') = 1);
select tt.as(:'shop');
select tt.err('T2 a salesperson cannot ask for place 5', $$select rb4_losses(null, null, 5)$$, 'not allowed');
select tt.as(:'o');

\echo == T3 wastage with the batch and run dimension
select stock_wastage(:'i_rm'::uuid, 5, 2, 'spoiled', 'test unbatched', null, null, gen_random_uuid()) is not null as w_w2 \gset
select public.rb4_wastage_dim(:'d_from'::date, :'td'::date, 5) as w \gset
select tt.chk('T3 two write-offs: 1 kg of the sweet from the batch made by run 2, 2 kg of milk with no batch', tt.n(:'w'::jsonb -> 'summary','records') = 2 and tt.n(:'w'::jsonb -> 'summary','from_run') = 1 and tt.n(:'w'::jsonb -> 'summary','batch_not_captured') = 1);
select tt.chk('T3 the batched write-off names the run (run 2) and its batch; the other says "batch not captured" with no batch and no run',
  (select r ->> 'run_id' = :'run2' and r ->> 'batch_state' = 'from_run' and r ->> 'reason_code' = 'spoiled' and tt.n(r,'qty') = 1 from jsonb_array_elements(:'w'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-FG')
  and (select r ->> 'batch_state' = 'batch_not_captured' and r -> 'run_id' = 'null'::jsonb and r -> 'batch_id' = 'null'::jsonb from jsonb_array_elements(:'w'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-RM'));
select tt.chk('T3 value: sweet 1 x 64.29 (average cost of the day) and milk 2 x 60 = 120.00; total about 184.29', (select tt.near(tt.n(r,'value'), 64.29, 0.02) from jsonb_array_elements(:'w'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-FG')
  and (select tt.n(r,'value') = 120 from jsonb_array_elements(:'w'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-RM') and tt.near(tt.n(:'w'::jsonb -> 'summary','value'), 184.29, 0.03));
select tt.chk('T3 by reason: spoiled = 2 records; by batch: only the batched record (1 batch, 1 kg)', (select (s ->> 'records')::int = 2 from jsonb_array_elements(:'w'::jsonb -> 'by_reason') s where s ->> 'reason_code' = 'spoiled')
  and jsonb_array_length(:'w'::jsonb -> 'by_batch') = 1 and (select tt.n(b,'qty') = 1 and b ->> 'run_id' = :'run2' from jsonb_array_elements(:'w'::jsonb -> 'by_batch') b limit 1));
select tt.chk('T3 by item: the quantity of different items is never added (two rows)', jsonb_array_length(:'w'::jsonb -> 'by_item') = 2);
-- a write-off whose cost is unknown (stock that came in with no cost)
insert into items (code,name_bn,name_en,unit,base_unit,tracked,item_type,category) values ('RB4-EX','test_extra','test_extra','kg','kg',true,'raw_material','test_raw');
select id as i_ex from items where code='RB4-EX' \gset
select stock_opening(:'i_ex'::uuid,5,5,null) is not null as w_o3 \gset
select stock_wastage(:'i_ex'::uuid, 5, 1, 'spoiled', 'test no cost', null, null, gen_random_uuid()) is not null as w_w3 \gset
select public.rb4_wastage_dim(:'d_from'::date, :'td'::date, 5) as w2 \gset
select tt.chk('T3 a write-off with an unknown ledger cost has an EMPTY value and the state cost_not_captured; the total adds only the two known ones', (select r -> 'value' = 'null'::jsonb and r ->> 'value_state' = 'cost_not_captured' from jsonb_array_elements(:'w2'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-EX')
  and tt.n(:'w2'::jsonb -> 'summary','value_known_n') = 2 and tt.near(tt.n(:'w2'::jsonb -> 'summary','value'), 184.29, 0.03));
select tt.as(:'rep');
select public.rb4_wastage_dim(:'d_from'::date, :'td'::date, 5) as w3 \gset
select tt.chk('T3 a reader without the cost right: cost_hidden is true, values EMPTY, quantities stay', (:'w3'::jsonb ->> 'cost_hidden')::boolean and (select bool_and(r -> 'value' = 'null'::jsonb and r ->> 'value_state' = 'cost_hidden') from jsonb_array_elements(:'w3'::jsonb -> 'rows') r)
  and tt.n(:'w3'::jsonb -> 'summary','records') = 3);
select tt.as(:'shop');
select tt.err('T3 a salesperson cannot ask for place 5', $$select rb4_wastage_dim(null, null, 5)$$, 'not allowed');
select tt.chk('T3 without a place a salesperson sees no record of place 5', jsonb_array_length(public.rb4_wastage_dim(:'d_from'::date, :'td'::date) -> 'rows') = 0);
select tt.as(:'o');

\echo == T4 paste twice
\ir phase408.sql
select tt.chk('T4 pasting phase 408 again keeps the answer', public.rb4_run_yield(:'d_from'::date, :'td'::date, 5) -> 'summary' = public.rb4_run_yield(:'d_from'::date, :'td'::date, 5) -> 'summary');

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
