-- FRESH DB ONLY. Phase 466 tests (RPT-C3 R9 part 2): #186 production requirement and #187 recipe-exploded raw material purchase forecast.
--   bash tests/sql/rptc3_run.sh 466
-- History: tests/sql/rptc3_history.sql (FG demand over 3 days = 5.5 expected, 5 low, 6 high). Recipe from the W1D fixture: 10 FG from 5 kg raw, waste 0. Test data only.
\ir ../tests/sql/rptc3_head.sql
\ir ../tests/sql/rptc3_history.sql
select tt.as(:'u_o');
insert into user_grants (user_id, grant_code, location_id) values (:'u_rm', 'report_stock', null) on conflict do nothing;
select id as fg from items where code = 'W1D-FG' \gset
select id as rm from items where code = 'W1D-RM' \gset
-- stock set so the numbers are hand-checkable: FG 2 on hand, raw 1 kg on hand
select stock_count_adjust(:'fg'::uuid, 1, 2, 'test count fg') is not null as c1 \gset
select stock_count_adjust(:'rm'::uuid, 1, 1, 'test count rm') is not null as c2 \gset
-- one open order due tomorrow (4 pieces), one undated order, one delivered order (not counted)
insert into online_orders (location_id, customer_name, customer_mobile, lines, subtotal, status, created_by, order_no, channel, delivery_mode, delivery_date, advance, advance_mode)
  values (1, 'test_o1', '01800000601', jsonb_build_array(jsonb_build_object('item_id', :'fg', 'qty', 4, 'price', 100, 'amount', 400)), 400, 'confirmed', :'u_o'::uuid, 99101, 'phone', 'pickup', tt.today()+1, 100, 'cash'),
         (1, 'test_o2', '01800000602', jsonb_build_array(jsonb_build_object('item_id', :'fg', 'qty', 9, 'price', 100, 'amount', 900)), 900, 'new', :'u_o'::uuid, 99102, 'phone', 'pickup', null, 0, null),
         (1, 'test_o3', '01800000603', jsonb_build_array(jsonb_build_object('item_id', :'fg', 'qty', 7, 'price', 100, 'amount', 700)), 700, 'delivered', :'u_o'::uuid, 99103, 'phone', 'pickup', tt.today()+1, 0, null);

-- T1 production requirement (#186)
select fc_production_requirement(1, 3, 28) as pr \gset
select tt.chk('T1 the finished good with a recipe: demand 5.5 (range 5-6), on hand 2, open orders 4', (select tt.n(x,'demand_expected') = 5.5 and tt.n(x,'demand_low') = 5 and tt.n(x,'demand_high') = 6 and tt.n(x,'on_hand') = 2 and tt.n(x,'open_orders') = 4 from jsonb_array_elements((:'pr'::jsonb)->'rows') x where x->>'code' = 'W1D-FG'));
select tt.chk('T1 to make 3.5 without orders (0.35 batch of 10); 7.5 with the orders (0.75 batch, 1 whole batch)', (select tt.n(x,'to_make') = 3.5 and tt.n(x,'batches') = 0.35 and tt.n(x,'to_make_with_orders') = 7.5 and tt.n(x,'batches_with_orders') = 0.75 and tt.n(x,'batches_whole_with_orders') = 1 and tt.n(x,'yield_per_batch') = 10 from jsonb_array_elements((:'pr'::jsonb)->'rows') x where x->>'code' = 'W1D-FG'));
select tt.chk('T1 the undated order and the delivered order are not counted, the undated one is reported', tt.n((:'pr'::jsonb)->'assumptions','orders_without_a_date_not_counted') = 1);
select tt.chk('T1 the high basis uses the high demand: 6 - 2 = 4', (select tt.n(x,'to_make') = 4 from jsonb_array_elements(fc_production_requirement(1, 3, 28, 'high')->'rows') x where x->>'code' = 'W1D-FG'));
select tt.chk('T1 notes warn orders may double count and nothing is ordered', (:'pr'::jsonb)->'notes' @> '["orders_on_top_may_count_some_demand_twice","nothing_is_ordered_or_produced_by_this_report"]'::jsonb);
select tt.chk('T1 no window: data needed', fc_production_requirement(1, 3, null)->'data_needed' ? 'fc_window_days');
select tt.err('T1 a bad basis is refused', $$select fc_production_requirement(1, 3, 28, 'median')$$, 'bad_basis');
select tt.err('T1 a place is required', $$select fc_production_requirement(null, 3, 28)$$, 'not allowed');

-- T2 raw material purchase (#187)
select fc_raw_purchase(1, 3, 28) as rp \gset
select tt.chk('T2 raw: need 1.75 kg (0.35 batch x 5), on hand 1, shortfall 0.75, cost 20 -> 15', (select tt.n(x,'need') = 1.75 and tt.n(x,'on_hand') = 1 and tt.n(x,'shortfall') = 0.75 and tt.n(x,'unit_cost') = 20 and tt.n(x,'est_cost') = 15 from jsonb_array_elements((:'rp'::jsonb)->'rows') x where x->>'code' = 'W1D-RM'));
select tt.chk('T2 the total cost of the shortfall is 15 and nothing is uncosted', tt.n((:'rp'::jsonb)->'totals','estimated_cost_of_shortfall') = 15 and tt.n((:'rp'::jsonb)->'totals','shortfall_items_without_a_cost') = 0);
select tt.chk('T2 with open orders on top: need 3.75, shortfall 2.75', (select tt.n(x,'need') = 3.75 and tt.n(x,'shortfall') = 2.75 from jsonb_array_elements(fc_raw_purchase(1, 3, 28, 'expected', true)->'rows') x where x->>'code' = 'W1D-RM'));
select tt.chk('T2 each ingredient says which product needs it', (select x->'used_by'->0->>'product' = 'W1D-FG' from jsonb_array_elements((:'rp'::jsonb)->'rows') x where x->>'code' = 'W1D-RM'));
select tt.chk('T2 the lead days shown are the existing setting reorder_lead_days (3), not invented here', (:'rp'::jsonb)->'assumptions'->>'lead_days_setting' = '3');
select set_rule('reorder_lead_days', '5') is null as ld \gset
select tt.chk('T2 once the owner sets lead days they are shown', fc_raw_purchase(1, 3, 28)->'rows'->0->>'lead_days' = '5');
select set_rule('reorder_lead_days', null) is null as ld2 \gset
-- a recipe line with no waste percent is flagged
select (recipe_save(null, :'fg'::uuid, 10, null, 'c3 v2 no waste', jsonb_build_array(jsonb_build_object('ingredient_item_id', :'rm', 'qty', 6)), null, true)->>'id') is not null as rv2 \gset
select tt.chk('T2 a recipe line without a waste percent is flagged (zero waste used)', (select (x->>'waste_percent_missing') = 'true' and tt.n(x,'need') = 2.1 from jsonb_array_elements(fc_raw_purchase(1, 3, 28)->'rows') x where x->>'code' = 'W1D-RM'));
-- access: stock reader without the cost right
select tt.as(:'u_rm');
select fc_raw_purchase(1, 3, 28) as rp2 \gset
select tt.chk('T2 a stock reader without the cost right sees quantities, no unit cost, no totals', (select x->>'unit_cost' is null and x->>'est_cost' is null and tt.n(x,'shortfall') > 0 from jsonb_array_elements((:'rp2'::jsonb)->'rows') x where x->>'code' = 'W1D-RM') and (:'rp2'::jsonb)->'totals'->>'estimated_cost_of_shortfall' is null and (:'rp2'::jsonb)->'notes' ? 'cost_hidden');
select tt.as(:'u_nb');
select tt.err('T2 nobody: production', $$select fc_production_requirement(1, 3, 28)$$, 'not allowed');
select tt.err('T2 nobody: raw', $$select fc_raw_purchase(1, 3, 28)$$, 'not allowed');
select tt.as(:'u_o');
\i supabase/phase466.sql
select tt.chk('T3 paste twice: still answers', jsonb_array_length(fc_production_requirement(1, 3, 28)->'rows') = 1);
select tt.chk('T3 nothing written, books balanced', tt.unbalanced() = 0);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
