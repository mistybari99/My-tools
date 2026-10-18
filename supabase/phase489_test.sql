-- FRESH DB ONLY. Phase 489 (X6 growth from own data): read-only, coverage and assumptions shown, rights, festival uplift, price-response hint gate.
--   bash tests/sql/x6_run.sh 489
\ir ../tests/sql/w1d_fixture.sql
\ir ../tests/sql/x6_head.sql
select mt.as(:'o');

-- T1 rights: reads need the market view or the sales report
select mt.as(:'nb');
select mt.err('T1 a person with no right gets no growth data', $$select mi_growth_items(current_date - 1, current_date, current_date - 8, current_date - 2)$$, 'not allowed');
select mt.as(:'vw');
select mt.chk('T1 a viewer gets the growth rows', (select jsonb_typeof(mi_growth_items(current_date - 1, current_date, current_date - 8, current_date - 2)->'rows')) = 'array');

-- T2 item growth: the current window equals the ERP net of today (place 1), and the coverage is shown
select mi_growth_items(mt.today(), mt.today(), mt.today() - 7, mt.today() - 1)::text as g \gset
select mt.chk('T2 growth answer has coverage, assumptions and a warning', (:'g'::jsonb) ? 'coverage' and (:'g'::jsonb) ? 'assumptions' and (:'g'::jsonb)->>'warning' like '%not why%');
select mt.chk('T2 current net equals the ERP sum of today', (select coalesce(sum((r->>'cur_net')::numeric), 0) from jsonb_array_elements((:'g'::jsonb)->'rows') r) = (select coalesce(sum(net), 0) from sales_fact where status = 'done' and day = mt.today()));
select mt.chk('T2 a blank growth % when the base has no sales', (select bool_and(case when (r->>'base_net')::numeric = 0 then r->>'growth_pct' is null else true end) from jsonb_array_elements((:'g'::jsonb)->'rows') r));
select mt.chk('T2 coverage counts trading days, not calendar days', ((:'g'::jsonb)->'coverage'->>'current_trading_days')::int <= ((:'g'::jsonb)->'coverage'->>'current_calendar_days')::int);

-- T3 outlets: per trading day
select mi_outlet_compare(mt.today() - 6, mt.today())::text as oc \gset
select mt.chk('T3 the outlet of place 1 has a trading day', exists (select 1 from jsonb_array_elements((:'oc'::jsonb)->'rows') r where (r->>'location_id')::int = 1 and (r->>'trading_days')::int >= 1));
select mt.chk('T3 per trading day is net divided by the trading days', (select bool_and(abs((r->>'net_per_trading_day')::numeric - (r->>'net_total')::numeric / (r->>'trading_days')::numeric) < 0.02) from jsonb_array_elements((:'oc'::jsonb)->'rows') r));

-- T4 basket: pairs and support; a bill with one item makes no pair
select mi_basket_pairs(mt.today() - 6, mt.today())::text as bk \gset
select mt.chk('T4 the basket answer lists bills and a warning that it is not causation', ((:'bk'::jsonb)->>'bills') is not null and (:'bk'::jsonb)->>'warning' like '%does not show%');

-- T5 price response: blank setting = no hint; a typed minimum with fewer than two prices = no hint
select mi_price_response((select id from items where code = 'W1D-FG'), mt.today() - 6, mt.today())::text as pr \gset
select mt.chk('T5 blank minimum days: no price hint', (:'pr'::jsonb)->>'hint' is null and (:'pr'::jsonb)->>'why' like 'Blank setting%');
select mt.as(:'o');
select set_rule('mi_elast_min_days', '1');
select mt.as(:'vw');
select mi_price_response((select id from items where code = 'W1D-FG'), mt.today() - 6, mt.today())::text as pr2 \gset
select mt.chk('T5 one price only: still no hint (two prices needed)', (:'pr2'::jsonb)->>'hint' is null);

-- T6 festival uplift: owner window against the same number of days before it; owner % shown as typed
select mt.as(:'o');
select festival_save(null, jsonb_build_object('name_bn', 'test_festival_bn', 'name_en', 'test_festival', 'start_date', to_char(mt.today() - 1, 'YYYY-MM-DD'), 'end_date', to_char(mt.today(), 'YYYY-MM-DD'), 'uplift_pct', '10'))->>'id' as fid \gset
select mi_festival_uplift(:'fid'::bigint)::text as fu \gset
select mt.chk('T6 festival uplift shows the owner % as typed and the comparison window', (:'fu'::jsonb)->>'owner_entered_uplift_pct' = '10.00' and (:'fu'::jsonb)->>'comparison_to' is not null);
select mt.chk('T6 festival uplift has its coverage and assumptions', (:'fu'::jsonb) ? 'coverage' and (:'fu'::jsonb) ? 'assumptions');

select 'x6 phase532: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from mt.res;
