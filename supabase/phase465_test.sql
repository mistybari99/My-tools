-- FRESH DB ONLY. Phase 465 tests (RPT-C3 R9 part 1): festival calendar, #184 sales forecast, #185 item demand forecast, with the assumptions panel.
--   bash tests/sql/rptc3_run.sh 465
-- The history and the hand-computed numbers are in tests/sql/rptc3_history.sql. Test data only (test_* names).
\ir ../tests/sql/rptc3_head.sql
\ir ../tests/sql/rptc3_history.sql
select tt.as(:'u_o');
insert into user_grants (user_id, grant_code, location_id) values (:'u_rm', 'report_sales', null) on conflict do nothing;

-- T1 festival calendar: owner enters, nothing deleted
select tt.chk('T1 nothing is seeded: only the two test festivals exist', (select count(*) from festival_calendar) = 2);
select tt.err('T1 end before start is refused', format($$select festival_save(null, '{"name_bn":"test_x","start_date":"%s","end_date":"%s"}')$$, tt.today()+5, tt.today()+3), 'end_before_start');
select tt.err('T1 a name is required', format($$select festival_save(null, '{"start_date":"%s"}')$$, tt.today()+5), 'name_required');
select tt.err('T1 an uplift of -100% or less is refused', format($$select festival_save(null, '{"name_bn":"test_x","start_date":"%s","uplift_pct":"-100"}')$$, tt.today()+5), 'bad_uplift');
select tt.err('T1 a bad date is refused', $$select festival_save(null, '{"name_bn":"test_x","start_date":"2026-02-31"}')$$, 'bad_date');
select tt.err('T1 an unknown place is refused', format($$select festival_save(null, '{"name_bn":"test_x","start_date":"%s","location_id":999}')$$, tt.today()+5), 'bad_location');
select tt.as(:'u_acc');
select tt.err('T1 a manager is not the owner: cannot enter a festival', format($$select festival_save(null, '{"name_bn":"test_x","start_date":"%s"}')$$, tt.today()+5), 'not allowed');
select tt.as(:'u_o');
select festival_save(tt.k_('fnw')::bigint, '{"uplift_pct":"25"}') ->> 'ok' as e1 \gset
select tt.chk('T1 an edit changes only what was sent', (select uplift_pct = 25 and name_en = 'test_fest_new' from festival_calendar where id = tt.k_('fnw')::bigint));
select festival_save(tt.k_('fnw')::bigint, '{"uplift_pct":"20"}') ->> 'ok' as e2 \gset
select festival_retire(tt.k_('fo')::bigint, 'test retire') ->> 'ok' as r1 \gset
select tt.chk('T1 retiring keeps the row (nothing is deleted) and lists it only on request', (select count(*) from festival_calendar) = 2 and jsonb_array_length(festival_list(false)->'rows') = 1 and jsonb_array_length(festival_list(true)->'rows') = 2);
select tt.err('T1 delete is refused', $$delete from festival_calendar$$, 'nothing is deleted');
select tt.err('T1 retiring needs a reason', format($$select festival_retire(%s, ' ')$$, tt.k_('fnw')), 'reason_required');
select festival_reactivate(tt.k_('fo')::bigint) ->> 'ok' as r2 \gset
select tt.chk('T1 reactivated', jsonb_array_length(festival_list(false)->'rows') = 2);
select tt.chk('T1 every festival change is in audit_log', (select count(*) from audit_log where table_name = 'festival_calendar') >= 6);

-- T2 the sales forecast (#184)
select tt.chk('T2 no window typed and no setting: "data needed", nothing assumed', fc_sales_forecast(null, 3, null)->'data_needed' ? 'fc_window_days');
select fc_sales_forecast(null, 3, 28) as fc \gset
select tt.chk('T2 today: same-weekday days T-7 and T-21 (T-14 is a festival day, left out): expected 350, low 300, high 400, n 2', (select tt.n(x,'expected') = 350 and tt.n(x,'low') = 300 and tt.n(x,'high') = 400 and tt.n(x,'n_obs') = 2 and (x->>'is_today') = 'true' from jsonb_array_elements((:'fc'::jsonb)->'rows') x order by x->>'date' limit 1));
select tt.chk('T2 tomorrow: T-6 and T-13: expected 225, range 200-250, a festival with the owner uplift 20% -> 270', (select tt.n(x,'expected') = 225 and tt.n(x,'low') = 200 and tt.n(x,'high') = 250 and tt.n(x,'expected_with_uplift') = 270 and x->>'festival' = 'test_fest_new' from jsonb_array_elements((:'fc'::jsonb)->'rows') x order by x->>'date' offset 1 limit 1));
select tt.chk('T2 the day with no same-weekday history has NO estimate (null), not 0', (select x->>'expected' is null and tt.n(x,'n_obs') = 0 from jsonb_array_elements((:'fc'::jsonb)->'rows') x order by x->>'date' offset 2 limit 1));
select tt.chk('T2 totals: expected 575, low 500, high 650, with uplift 620, one day without an estimate', tt.n((:'fc'::jsonb)->'totals','expected') = 575 and tt.n((:'fc'::jsonb)->'totals','low') = 500 and tt.n((:'fc'::jsonb)->'totals','high') = 650 and tt.n((:'fc'::jsonb)->'totals','expected_with_uplift') = 620 and tt.n((:'fc'::jsonb)->'totals','days_without_estimate') = 1);
select tt.chk('T2 the assumptions panel: window 28, effective 21 days, 6 trading days, 5 ordinary, 1 festival left out, coverage 28.6%', tt.n((:'fc'::jsonb)->'assumptions','window_days') = 28 and tt.n((:'fc'::jsonb)->'assumptions','effective_window_days') = 21 and tt.n((:'fc'::jsonb)->'assumptions','trading_days') = 6
  and tt.n((:'fc'::jsonb)->'assumptions','ordinary_trading_days') = 5 and tt.n((:'fc'::jsonb)->'assumptions','festival_days_left_out') = 1 and tt.n((:'fc'::jsonb)->'assumptions','data_coverage_pct') = 28.6);
select tt.chk('T2 the panel says the basis, the owner-entered uplift and the festival rows', (:'fc'::jsonb)->'assumptions'->>'revenue_basis' = 'net of returns' and ((:'fc'::jsonb)->'assumptions'->>'uplift_entered_by_owner') = 'true' and tt.n((:'fc'::jsonb)->'assumptions','festival_rows') = 2);
select tt.chk('T2 the notes state the limits: range is not a confidence interval, no probability, closed days are not zero, short history', (:'fc'::jsonb)->'notes' @> '["range_is_lowest_and_highest_past_same_weekday_not_a_confidence_interval","no_probability_claimed","days_without_a_bill_are_closed_not_zero","history_shorter_than_the_window"]'::jsonb);
select tt.chk('T2 same-weekday day counts are given per weekday', jsonb_typeof((:'fc'::jsonb)->'assumptions'->'same_weekday_days_used') = 'object' and (select sum(value::int) from jsonb_each_text((:'fc'::jsonb)->'assumptions'->'same_weekday_days_used')) = 5);
-- the setting supplies the window; a place with no history says so
select set_rule('fc_window_days', '28') is null as sw \gset
select tt.chk('T2 the setting supplies the window when none is typed', fc_sales_forecast(null, 3, null)->'assumptions'->>'window_days' = '28');
select set_rule('fc_window_days', null) is null as sw2 \gset
select tt.chk('T2 a place with no bills in the window: no estimate anywhere and not a single zero', (select bool_and(x->>'expected' is null) from jsonb_array_elements(fc_sales_forecast(2, 3, 28)->'rows') x) and fc_sales_forecast(2, 3, 28)->'totals'->>'expected' is null);
select tt.err('T2 a window under 7 days is refused', $$select fc_sales_forecast(null, 3, 3)$$, 'bad_range');
select tt.err('T2 a horizon over 90 days is refused', $$select fc_sales_forecast(null, 120, 28)$$, 'bad_range');
select tt.err('T2 the horizon must be typed', $$select fc_sales_forecast(null, null, 28)$$, 'bad_range');
-- returns are netted by the setting
select sale_return(gen_random_uuid(), tt.k_('h1')::uuid, format('[{"item_id":"%s","qty":1}]', (select id from items where code='W1D-FG'))::jsonb, 'damaged', null, 'cash', null, null) is not null as rr \gset
select tt.chk('T2 a return on T-7 lowers that day: expected for today is now (200 + 400) / 2 = 300', (select tt.n(x,'expected') = 300 and tt.n(x,'low') = 200 from jsonb_array_elements(fc_sales_forecast(null, 3, 28)->'rows') x order by x->>'date' limit 1));
select set_rule('reports_net_of_returns', 'false') is null as nr \gset
select tt.chk('T2 with returns not netted (owner setting) it is back to 350, and the panel says so', (select tt.n(x,'expected') = 350 from jsonb_array_elements(fc_sales_forecast(null, 3, 28)->'rows') x order by x->>'date' limit 1) and fc_sales_forecast(null, 3, 28)->'assumptions'->>'revenue_basis' = 'bill totals, returns not netted');
select set_rule('reports_net_of_returns', null) is null as nr2 \gset
-- access
select tt.as(:'u_nb');
select tt.err('T2 nobody has no access', $$select fc_sales_forecast(null, 3, 28)$$, 'not allowed');
select tt.as(:'u_rm');
select tt.chk('T2 a report_sales holder reads it', jsonb_array_length(fc_sales_forecast(1, 3, 28)->'rows') = 3);
select tt.err('T2 a place he cannot see', $$select fc_sales_forecast(2, 3, 28)$$, 'not allowed');
select tt.as(:'u_o');

-- T3 item demand (#185)
select fc_item_demand(null, 3, 28) as fi \gset
select tt.chk('T3 W1D-FG: 12 units in 5 ordinary trading days, 4 of them with a sale... (avg 2.4 a trading day)', (select tt.n(x,'units_in_window') = 12 and tt.n(x,'avg_per_trading_day') = 2.4 from jsonb_array_elements((:'fi'::jsonb)->'rows') x where x->>'code' = 'W1D-FG'));
select tt.chk('T3 expected 5.5 units over 3 days, range 5 to 6; with the uplift option 5.9', (select tt.n(x,'expected') = 5.5 and tt.n(x,'low') = 5 and tt.n(x,'high') = 6 and x->>'expected_with_uplift' is null from jsonb_array_elements((:'fi'::jsonb)->'rows') x where x->>'code' = 'W1D-FG')
  and (select tt.n(x,'expected_with_uplift') = 5.9 from jsonb_array_elements(fc_item_demand(null, 3, 28, true)->'rows') x where x->>'code' = 'W1D-FG'));
select tt.chk('T3 the item panel gives window, trading days and the limits', tt.n((:'fi'::jsonb)->'assumptions','ordinary_trading_days') = 5 and (:'fi'::jsonb)->'notes' ? 'days_out_of_stock_count_as_zero' and (:'fi'::jsonb)->'notes' ? 'untracked_items_not_covered');
select tt.chk('T3 stock on hand and days of cover come from the ledger', (select x->>'on_hand' is not null and x->>'days_cover' is not null from jsonb_array_elements((:'fi'::jsonb)->'rows') x where x->>'code' = 'W1D-FG'));
select tt.chk('T3 an item that never sold in the window is not listed (no invented zero row)', not exists (select 1 from jsonb_array_elements((:'fi'::jsonb)->'rows') x where x->>'code' = 'W1D-RM'));
select tt.chk('T3 uplift is applied to items only when asked, and says so', fc_item_demand(null, 3, 28, true)->'notes' ? 'the_same_uplift_is_applied_to_every_item' and not ((:'fi'::jsonb)->'notes' ? 'the_same_uplift_is_applied_to_every_item'));
select tt.chk('T3 no window: data needed', fc_item_demand(null, 3, null)->'data_needed' ? 'fc_window_days');
select tt.as(:'u_nb');
select tt.err('T3 nobody has no access', $$select fc_item_demand(null, 3, 28)$$, 'not allowed');
select tt.as(:'u_o');
\i supabase/phase465.sql
select tt.chk('T4 paste twice keeps the festivals and the answer', (select count(*) from festival_calendar) = 2 and tt.n(fc_sales_forecast(null, 3, 28)->'totals','expected') = 525);
select tt.chk('T4 no journal entry is unbalanced and the forecasts wrote nothing', tt.unbalanced() = 0);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
