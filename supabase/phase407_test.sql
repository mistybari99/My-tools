-- FRESH DB ONLY. Phase 407 tests: real consumption vs recipe (#44) and standard vs actual cost with the price / usage / yield split (#33, #43, #55) (package RPT-B4, R4b).
--   Build a database through phase 99, paste supabase/phase404.sql .. phase407.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase407_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql and rb4_fixture2.sql (hand-computed numbers in the headers). Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\ir ../tests/sql/rb4_fixture2.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select to_char(:'td'::date - 10, 'YYYY-MM-DD') as d_from \gset

\echo == T0 shape
select tt.chk('T0 both reports open to signed-in users only', has_function_privilege('authenticated','public.rb4_cost_variance(date,date,int,uuid)','execute') and not has_function_privilege('anon','public.rb4_consumption_vs_recipe(date,date,int,uuid)','execute'));

\echo == T1 consumption vs recipe
select public.rb4_consumption_vs_recipe(:'d_from'::date, :'td'::date, 5) as cv \gset
select tt.chk('T1 run 1 milk: booked (standard) 12, real 13, +1.0 kg = +8.33 %', (select tt.n(r,'std_qty') = 12 and tt.n(r,'actual_qty') = 13 and tt.n(r,'diff') = 1 and tt.n(r,'diff_pct') = 8.33 and r ->> 'status' = 'measured' from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1' and r ->> 'code' = 'RB4-RM'));
select tt.chk('T1 run 1 sugar: 6 vs 6, difference 0 (a real zero, because it was measured)', (select tt.n(r,'diff') = 0 and tt.n(r,'diff_pct') = 0 and r ->> 'status' = 'measured' from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1' and r ->> 'code' = 'RB4-SG'));
select tt.chk('T1 run 2 (nothing recorded): the real quantity is EMPTY and the status says not_captured; no difference is shown (never 0)',
  (select r -> 'actual_qty' = 'null'::jsonb and r -> 'diff' = 'null'::jsonb and r -> 'diff_pct' = 'null'::jsonb and r ->> 'status' = 'not_captured' and tt.n(r,'std_qty') = 6 from jsonb_array_elements(:'cv'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2' and r ->> 'code' = 'RB4-RM'));
select tt.chk('T1 summary milk: 2 runs issued it, 1 measured, 1 not captured; totals only from the measured run: 12 -> 13, +8.33 %',
  (select (s ->> 'runs_issued')::int = 2 and (s ->> 'runs_measured')::int = 1 and (s ->> 'runs_not_captured')::int = 1 and tt.n(s,'std_qty_measured') = 12 and tt.n(s,'actual_qty_measured') = 13 and tt.n(s,'diff_pct') = 8.33 from jsonb_array_elements(:'cv'::jsonb -> 'summary') s where s ->> 'code' = 'RB4-RM'));
select tt.chk('T1 2 runs, 1 with a record; no "not captured" note because some use was recorded', tt.n(:'cv'::jsonb,'runs') = 2 and tt.n(:'cv'::jsonb,'runs_with_real_use') = 1 and jsonb_array_length(:'cv'::jsonb -> 'notes') = 0);
select public.rb4_consumption_vs_recipe(:'td'::date - 600, :'td'::date - 500, 5) as cv0 \gset
select public.rb4_consumption_vs_recipe(:'d_from'::date, :'td'::date, 5, :'i_rm'::uuid) as cv1 \gset
select tt.chk('T1 with no run in the period the answer is empty and says "actual issue not captured"', jsonb_array_length(:'cv0'::jsonb -> 'rows') = 0 and (:'cv0'::jsonb -> 'notes' -> 0 ->> 'code') = 'actual_issue_not_captured');
select tt.chk('T1 an item filter on a raw item (not a finished product) finds no run', jsonb_array_length(:'cv1'::jsonb -> 'rows') = 0);
insert into items (code,name_bn,name_en,unit,base_unit,tracked,item_type,category) values ('RB4-EX','test_extra','test_extra','kg','kg',true,'raw_material','test_raw');
select id as i_ex from items where code='RB4-EX' \gset
select tt.as(:'fac');
select prod_actual_issue_set(:'run2'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_ex', 'qty', 2)), 'test extra ingredient') is not null as w_ex \gset
select tt.as(:'o');
select public.rb4_consumption_vs_recipe(:'d_from'::date, :'td'::date, 5) as cv2 \gset
select tt.chk('T1 an ingredient used but not in the recipe is listed as not_in_recipe with its real quantity and no standard', (select r ->> 'status' = 'not_in_recipe' and r -> 'std_qty' = 'null'::jsonb and tt.n(r,'actual_qty') = 2 from jsonb_array_elements(:'cv2'::jsonb -> 'rows') r where r ->> 'code' = 'RB4-EX'));
select tt.chk('T1 the extra line is not added into the summary of measured runs', not exists (select 1 from jsonb_array_elements(:'cv2'::jsonb -> 'summary') s where s ->> 'code' = 'RB4-EX' and (s ->> 'runs_measured')::int > 0));
select tt.as(:'shop');
select tt.err('T1 a salesperson cannot ask for place 5', $$select rb4_consumption_vs_recipe(null, null, 5)$$, 'not allowed');
select tt.as(:'o');

\echo == T2 cost variance
select public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) as v \gset
select tt.chk('T2 run 1 is fully measured: price 35.00, usage 55.00, yield 117.00, total 207.00',
  (select r ->> 'status' = 'measured' and tt.n(r,'price_var') = 35 and tt.n(r,'usage_var') = 55 and tt.n(r,'yield_var') = 117 and tt.n(r,'total_var') = 207 from jsonb_array_elements(:'v'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T2 the three parts add up to the total exactly (35 + 55 + 117 = 207)', (select tt.n(r,'price_var') + tt.n(r,'usage_var') + tt.n(r,'yield_var') = tt.n(r,'total_var') from jsonb_array_elements(:'v'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T2 run 1: standard cost of the real output 18 x 58.5 = 1053.00, real material cost 13 x 60 + 6 x 80 = 1260.00, standard unit cost by the list 58.5, yield short by 2 kg',
  (select tt.n(r,'std_cost_for_real_output') = 1053 and tt.n(r,'real_material_cost') = 1260 and tt.n(r,'std_unit_cost_list') = 58.5 and tt.n(r,'yield_var_qty') = 2 from jsonb_array_elements(:'v'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T2 run 1 lines: milk price +65.00 (13 x (60-55)), usage +55.00; sugar price -30.00 (6 x (80-85)), usage 0.00',
  (select tt.n(l,'price_var') = 65 and tt.n(l,'usage_var') = 55 from jsonb_array_elements(:'v'::jsonb -> 'rows') r, jsonb_array_elements(r -> 'lines') l where r ->> 'run_id' = :'run1' and l ->> 'code' = 'RB4-RM')
  and (select tt.n(l,'price_var') = -30 and tt.n(l,'usage_var') = 0 from jsonb_array_elements(:'v'::jsonb -> 'rows') r, jsonb_array_elements(r -> 'lines') l where r ->> 'run_id' = :'run1' and l ->> 'code' = 'RB4-SG'));
select tt.chk('T2 run 2: real use and real yield not recorded (only an extra line exists) -> not_measured, every variance EMPTY (never 0), the missing fields are named',
  (select r ->> 'status' = 'not_measured' and r -> 'price_var' = 'null'::jsonb and r -> 'usage_var' = 'null'::jsonb and r -> 'yield_var' = 'null'::jsonb and r -> 'total_var' = 'null'::jsonb
     and r -> 'missing' @> '"real use of ingredients"'::jsonb and r -> 'missing' @> '"actual yield"'::jsonb and not r -> 'missing' @> '"standard price (price list)"'::jsonb
     from jsonb_array_elements(:'v'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2'));
select tt.chk('T2 the booked figures of the existing costing stay: run 1 booked unit cost 66.666667 and standard unit cost 60 (conversion cost not split)',
  (select tt.n(r,'booked_unit_cost') = 66.666667 and tt.n(r,'std_unit_cost_booked') = 60 and tt.n(r,'material_cost') = 1200 from jsonb_array_elements(:'v'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T2 summary of the sweet: 2 runs, 1 measured, 1 not measured; total 207.00 = 19.66 % of 1053.00; price/usage/yield counted over the 1 run where they exist',
  (select (s ->> 'runs')::int = 2 and (s ->> 'runs_measured')::int = 1 and (s ->> 'runs_not_measured')::int = 1 and tt.n(s,'total_var') = 207 and tt.n(s,'total_var_pct') = 19.66 and (s ->> 'price_var_runs')::int = 1 and tt.n(s,'yield_var') = 117
     from jsonb_array_elements(:'v'::jsonb -> 'summary') s where s ->> 'code' = 'RB4-FG'));
select tt.chk('T2 the cost right is there for the owner: cost_hidden is false', not (:'v'::jsonb ->> 'cost_hidden')::boolean);
-- partial: record the real use for run 2 but not its yield
select tt.as(:'fac');
select prod_actual_issue_set(:'run2'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'i_rm', 'qty', 6.5), jsonb_build_object('item_id', :'i_sg', 'qty', 3)), 'test real use run 2') is not null as w_a2 \gset
select tt.as(:'o');
select public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) as v2 \gset
select tt.chk('T2 run 2 has an extra line (RB4-EX, not in the recipe) so usage and price stay EMPTY: a part is shown only when all its inputs are known',
  (select r ->> 'status' = 'not_measured' and r -> 'usage_var' = 'null'::jsonb and r -> 'missing' @> '"real use of ingredients"'::jsonb from jsonb_array_elements(:'v2'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2'));
update production_issue_actual set status = 'replaced' where run_id = :'run2'::uuid and item_id = :'i_ex'::uuid;
select public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) as v3 \gset
select tt.chk('T2 without the extra line run 2 is partly measured: usage (6.5-6) x 55 + 0 = 27.50; price 6.5 x 5 + 3 x (-5) = 17.50; yield and total still EMPTY (no typed output)',
  (select r ->> 'status' = 'partly' and tt.n(r,'usage_var') = 27.5 and tt.n(r,'price_var') = 17.5 and r -> 'yield_var' = 'null'::jsonb and r -> 'total_var' = 'null'::jsonb from jsonb_array_elements(:'v3'::jsonb -> 'rows') r where r ->> 'run_id' = :'run2'));
select tt.chk('T2 summary: usage and price now count 2 runs; total still only the 1 fully measured run (207.00)',
  (select (s ->> 'usage_var_runs')::int = 2 and tt.n(s,'usage_var') = 82.5 and tt.n(s,'price_var') = 52.5 and tt.n(s,'total_var') = 207 and (s ->> 'runs_partly')::int = 1 from jsonb_array_elements(:'v3'::jsonb -> 'summary') s where s ->> 'code' = 'RB4-FG'));
-- a missing standard price
delete from item_costs where item_id = :'i_sg'::uuid;
select public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) as v4 \gset
select tt.chk('T2 sugar without a list price: run 1 loses its split (price, usage, yield all EMPTY) and says "standard price (price list)" is missing',
  (select r ->> 'status' = 'not_measured' and r -> 'price_var' = 'null'::jsonb and r -> 'usage_var' = 'null'::jsonb and r -> 'yield_var' = 'null'::jsonb and r -> 'missing' @> '"standard price (price list)"'::jsonb and tt.n(r,'yield_var_qty') = 2
     from jsonb_array_elements(:'v4'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.chk('T2 all runs unmeasured -> a note says which inputs are missing', (:'v4'::jsonb -> 'notes' -> 0 ->> 'code') = 'no_run_fully_measured');
insert into item_costs (item_id, cost_price) values (:'i_sg'::uuid, 85) on conflict (item_id) do update set cost_price = 85;
-- cost right
select tt.as(:'rep');
select public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) as v5 \gset
select tt.chk('T2 a reader without the cost right: cost_hidden is true, every money field is EMPTY, quantities stay (yield short 2 kg)',
  (:'v5'::jsonb ->> 'cost_hidden')::boolean and (select r -> 'price_var' = 'null'::jsonb and r -> 'total_var' = 'null'::jsonb and r -> 'booked_unit_cost' = 'null'::jsonb and r -> 'material_cost' = 'null'::jsonb and tt.n(r,'yield_var_qty') = 2
     and (select bool_and(l -> 'booked_price' = 'null'::jsonb and l -> 'std_price' = 'null'::jsonb and l -> 'price_var' = 'null'::jsonb) from jsonb_array_elements(r -> 'lines') l)
     from jsonb_array_elements(:'v5'::jsonb -> 'rows') r where r ->> 'run_id' = :'run1'));
select tt.as(:'shop');
select tt.err('T2 a salesperson cannot ask for place 5', $$select rb4_cost_variance(null, null, 5)$$, 'not allowed');
select tt.chk('T2 without a place a salesperson sees no run', jsonb_array_length(public.rb4_cost_variance(:'d_from'::date, :'td'::date) -> 'rows') = 0);
select tt.as(:'o');
select tt.err('T2 a bad range is refused', $$select rb4_cost_variance(current_date, current_date - 4)$$, 'bad_range');
select tt.chk('T2 two finished runs in the answer', jsonb_array_length(public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) -> 'rows') = 2);

\echo == T3 paste twice
\ir phase407.sql
select tt.chk('T3 pasting phase 407 again keeps the answer', (public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) -> 'summary') = (public.rb4_cost_variance(:'d_from'::date, :'td'::date, 5) -> 'summary'));

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
