-- FRESH DB ONLY. Phase 415-416 tests: factory vs retail (#7) and the audit line for the CSV of the new reports (package RPT-B4, R9).
--   Build a database through phase 99, paste supabase/phase404.sql .. phase416.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase416_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql (hand-computed numbers in its header). Hand-computed here (D = today):
--   production : 2 runs, 28 kg, booked cost 1200 + 600 = 1800 (conversion 0, complete)
--   transfers  : place 5 -> 1: 15 kg sent, 14 received | place 5 -> 2: 2 kg sent, in transit | ledger cost 64.285715 a kg -> 964.29 and 128.57 (1092.86 in all)
--   price_pct 70 on a selling price of 200 = 140 a kg: 2100.00 and 280.00 (2380.00); margin 1135.71 + 151.43 = 1287.14
--   shop 1     : sales 800, no return, cost of 4 kg = 257.14, gross profit 542.86 = 67.86 %
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select to_char(:'td'::date - 10, 'YYYY-MM-DD') as d_from \gset

\echo == T0 shape
select tt.chk('T0 the report and the audit function are open to signed-in users only', has_function_privilege('authenticated','public.rb4_factory_vs_retail(date,date)','execute') and not has_function_privilege('anon','public.rb4_factory_vs_retail(date,date)','execute')
  and has_function_privilege('authenticated','public.rb4_log_export(text,text,jsonb,int)','execute') and not has_function_privilege('anon','public.rb4_log_export(text,text,jsonb,int)','execute'));

\echo == T1 basis none (as shipped)
select public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) as r0 \gset
select tt.chk('T1 the basis is none and the note says transfers are not valued', :'r0'::jsonb ->> 'basis' = 'none' and exists (select 1 from jsonb_array_elements(:'r0'::jsonb -> 'notes') n where n ->> 'code' = 'transfers_not_valued'));
select tt.chk('T1 factory: 2 runs, 28 kg, production cost 1800.00 (material 1200 + 600, conversion 0)', (select (e ->> 'runs')::int = 2 and tt.n(e,'output') = 28 and tt.n(e,'production_cost') = 1800 and e ->> 'cost_state' = 'known' from jsonb_array_elements(:'r0'::jsonb -> 'factory' -> 'rows') e where e ->> 'code' = 'RB4-FG'));
select tt.chk('T1 transfers 5 -> 1: 15 kg sent, 14 received, ledger cost 964.29; value EMPTY with the state not_valued; margin EMPTY',
  (select tt.n(e,'sent') = 15 and tt.n(e,'received') = 14 and tt.near(tt.n(e,'cost_value'), 964.29, 0.01) and e -> 'transfer_value' = 'null'::jsonb and e ->> 'value_state' = 'not_valued' and e -> 'margin' = 'null'::jsonb
     from jsonb_array_elements(:'r0'::jsonb -> 'transfers' -> 'rows') e where (e ->> 'to_location_id')::int = 1));
select tt.chk('T1 transfers 5 -> 2: 2 kg still in transit, cost 128.57', (select tt.n(e,'in_transit') = 2 and tt.n(e,'received') = 0 and tt.near(tt.n(e,'cost_value'), 128.57, 0.01) from jsonb_array_elements(:'r0'::jsonb -> 'transfers' -> 'rows') e where (e ->> 'to_location_id')::int = 2));
select tt.chk('T1 totals: cost value 1092.86, nothing valued (2 rows not valued), no factory margin (empty)', tt.near(tt.n(:'r0'::jsonb -> 'transfers' -> 'totals','cost_value'), 1092.86, 0.02) and tt.n(:'r0'::jsonb -> 'transfers' -> 'totals','rows_not_valued') = 2 and :'r0'::jsonb -> 'transfers' -> 'totals' -> 'factory_margin' = 'null'::jsonb);
select tt.chk('T1 shop 1: net sales 800, cost of goods sold 257.14, gross profit 542.86 = 67.86 %, nothing uncosted',
  (select tt.n(e,'net_sales') = 800 and tt.near(tt.n(e,'cogs'), 257.14, 0.01) and tt.near(tt.n(e,'gross_profit'), 542.86, 0.01) and tt.near(tt.n(e,'gp_pct'), 67.86, 0.01) and tt.n(e,'uncosted_pct') = 0 from jsonb_array_elements(:'r0'::jsonb -> 'retail' -> 'rows') e where (e ->> 'location_id')::int = 1));
select tt.chk('T1 the whole chain ties: milk and sugar (opening cost) -> 28 kg of sweet at 1800 -> 15 + 2 kg moved out at 1800 / 28 a kg -> 4 kg sold: the cost of goods sold 4 x 1800 / 28 = 257.14', (select tt.near(tt.n(e,'cogs'), 4 * 1800.0 / 28, 0.01) from jsonb_array_elements(:'r0'::jsonb -> 'retail' -> 'rows') e where (e ->> 'location_id')::int = 1)
  and (select tt.near(tt.n(e,'cost_value'), 15 * 1800.0 / 28, 0.01) from jsonb_array_elements(:'r0'::jsonb -> 'transfers' -> 'rows') e where (e ->> 'to_location_id')::int = 1));
select tt.chk('T1 the statement that the shop profit is not netted with a transfer value is in the answer', :'r0'::jsonb ->> 'statement' like '%never netted%');

\echo == T2 basis cost
update rules set value = '"cost"'::jsonb where key = 'transfer_valuation_basis';
select public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) as r1 \gset
select tt.chk('T2 at cost the transfer value equals the cost value and the factory margin is 0.00 (a real 0: by definition)', (select tt.near(tt.n(e,'transfer_value'), tt.n(e,'cost_value'), 0.01) and tt.n(e,'margin') = 0 and e ->> 'value_state' = 'cost' from jsonb_array_elements(:'r1'::jsonb -> 'transfers' -> 'rows') e where (e ->> 'to_location_id')::int = 1)
  and tt.n(:'r1'::jsonb -> 'transfers' -> 'totals','factory_margin') = 0 and not exists (select 1 from jsonb_array_elements(:'r1'::jsonb -> 'notes') n where n ->> 'code' = 'transfers_not_valued'));

\echo == T3 basis price_pct
update rules set value = '"price_pct"'::jsonb where key = 'transfer_valuation_basis';
select public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) as r2 \gset
select tt.chk('T3 price_pct with the percentage blank: no value, the state says so and a note names the setting', (select e -> 'transfer_value' = 'null'::jsonb and e ->> 'value_state' = 'pct_not_set' from jsonb_array_elements(:'r2'::jsonb -> 'transfers' -> 'rows') e where (e ->> 'to_location_id')::int = 1)
  and exists (select 1 from jsonb_array_elements(:'r2'::jsonb -> 'notes') n where n ->> 'code' = 'pct_not_set' and n ->> 'field' = 'transfer_price_pct'));
update rules set value = '70'::jsonb where key = 'transfer_price_pct';
select public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) as r3 \gset
select tt.chk('T3 at 70 % of 200: 5 -> 1 valued 2100.00, margin 1135.71; 5 -> 2 valued 280.00, margin 151.43', (select tt.n(e,'transfer_value') = 2100 and tt.near(tt.n(e,'margin'), 1135.71, 0.01) and e ->> 'value_state' = 'price_pct' from jsonb_array_elements(:'r3'::jsonb -> 'transfers' -> 'rows') e where (e ->> 'to_location_id')::int = 1)
  and (select tt.n(e,'transfer_value') = 280 and tt.near(tt.n(e,'margin'), 151.43, 0.01) from jsonb_array_elements(:'r3'::jsonb -> 'transfers' -> 'rows') e where (e ->> 'to_location_id')::int = 2));
select tt.chk('T3 totals: transfer value 2380.00, factory margin about 1287.14; the shop profit is unchanged (542.86)', tt.n(:'r3'::jsonb -> 'transfers' -> 'totals','transfer_value') = 2380 and tt.near(tt.n(:'r3'::jsonb -> 'transfers' -> 'totals','factory_margin'), 1287.14, 0.02)
  and tt.near(tt.n(:'r3'::jsonb -> 'retail' -> 'totals','gross_profit'), 542.86, 0.01));
-- an unknown cost
update stock_ledger set unit_cost = unit_cost where false;
select tt.as(:'rep');
select public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) as r4 \gset
select tt.chk('T3 a reader without the cost right: cost_hidden is true; production cost, transfer cost, value, margin, cogs and profit are all EMPTY; quantities stay',
  (:'r4'::jsonb ->> 'cost_hidden')::boolean and (select e -> 'production_cost' = 'null'::jsonb and e ->> 'cost_state' = 'cost_hidden' and tt.n(e,'output') = 28 from jsonb_array_elements(:'r4'::jsonb -> 'factory' -> 'rows') e)
  and (select bool_and(e -> 'cost_value' = 'null'::jsonb and e -> 'transfer_value' = 'null'::jsonb and e -> 'margin' = 'null'::jsonb) and sum((e ->> 'sent')::numeric) = 17 from jsonb_array_elements(:'r4'::jsonb -> 'transfers' -> 'rows') e)
  and (select e -> 'cogs' = 'null'::jsonb and e -> 'gross_profit' = 'null'::jsonb and e ->> 'cost_state' = 'cost_hidden' and tt.n(e,'net_sales') = 800 from jsonb_array_elements(:'r4'::jsonb -> 'retail' -> 'rows') e where (e ->> 'location_id')::int = 1));
select tt.as(:'shop');
select public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) as r5 \gset
select tt.chk('T3 a salesperson sees no factory and no shop block, and a note says there is no factory place for him', jsonb_array_length(:'r5'::jsonb -> 'factory' -> 'rows') = 0 and jsonb_array_length(:'r5'::jsonb -> 'transfers' -> 'rows') = 0 and jsonb_array_length(:'r5'::jsonb -> 'retail' -> 'rows') = 0
  and exists (select 1 from jsonb_array_elements(:'r5'::jsonb -> 'notes') n where n ->> 'code' = 'no_factory_place'));
select tt.as(:'o');
select tt.err('T3 a bad range is refused', $$select rb4_factory_vs_retail(current_date, current_date - 3)$$, 'bad_range');
select tt.chk('T3 a period with nothing in it is an empty answer, not an error', jsonb_array_length(public.rb4_factory_vs_retail(:'td'::date - 600, :'td'::date - 500) -> 'transfers' -> 'rows') = 0);

\echo == T4 audit line for the CSV
select tt.chk('T4 the owner may log an export of each kind of key', (select count(*) from (select rb4_log_export(k, 'csv', jsonb_build_object('from', :'d_from'), 12) from unnest(array['plan_vs_actual','order_status','dispatch_recon','consumption','cost_variance','run_yield','losses','wastage_dim','labour_productivity','capacity','target_report','kpi_trend','factory_vs_retail','production_runs','capacity_ratings','sales_targets']) k) z) = 16);
select tt.chk('T4 each wrote one audit line with who, what, rows and filters', (select count(*) from audit_log where action = 'export' and table_name = 'report' and detail ->> 'kind' = 'csv') = 16 and (select detail -> 'filters' ->> 'from' from audit_log where action = 'export' and record_id = 'losses') = :'d_from');
select tt.err('T4 an unknown report key is refused', $$select rb4_log_export('daybook_x', 'csv', '{}'::jsonb, 1)$$, 'unknown_report');
select tt.err('T4 a bad kind is refused', $$select rb4_log_export('losses', 'x y', '{}'::jsonb, 1)$$, 'bad_kind');
select tt.as(:'shop');
select tt.err('T4 a salesperson without the export right gets no audit line and so no file', $$select rb4_log_export('losses', 'csv', '{}'::jsonb, 1)$$, 'not allowed');
select tt.as(:'rep');
select tt.err('T4 a report reader without the export right is refused too', $$select rb4_log_export('losses', 'csv', '{}'::jsonb, 1)$$, 'not allowed');
insert into user_grants (user_id, grant_code) values (:'rep', 'export_data') on conflict do nothing;
select tt.chk('T4 with the export right and the stock report right a production key is allowed', (select count(*) from (select rb4_log_export('losses', 'csv', '{}'::jsonb, 3)) z) = 1);
select tt.err('T4 ... but not a target key (no sales report right)', $$select rb4_log_export('kpi_trend', 'csv', '{}'::jsonb, 3)$$, 'not allowed');
select tt.as(:'o');

\echo == T5 paste twice
\ir phase416.sql
select tt.chk('T5 pasting the file again keeps the answer', (public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) -> 'transfers' -> 'totals') = (public.rb4_factory_vs_retail(:'d_from'::date, :'td'::date) -> 'transfers' -> 'totals'));

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
