-- Phase 551 tests (XC-2): production suggestion arithmetic, festival handling, carry-over, open orders, confirmation, accuracy, access.
--   Built on a database through phase551 (phase550 is pasted before it). Run on a fresh copy: psql -d <db> -f supabase/phase551_test.sql
\ir ../tests/sql/xc_head.sql
select set_config('request.jwt.claim.sub', :'o', false);

-- fixtures (replica role: the sale, stock and order triggers do not run; the code under test runs as normal)
select set_config('session_replication_role', 'replica', false);
update rules set value = 'true'::jsonb where key = 'xc_prod_suggest_on';
update rules set value = '3'::jsonb where key = 'xc_prod_weeks';
insert into items (code, name_bn, name_en, unit, base_unit, sell_price, tracked, item_type)
  values ('T551-A', 'test_cake_a', 'test_cake_a', 'piece', 'piece', 100, true, 'finished_good');
select id as i_a from items where code = 'T551-A' \gset
-- history at place 1: the same weekday 6 and 20 days ago (ordinary), 13 days ago (a festival day, left out)
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, created_by, status)
values (1, 1101, tt.today() - 6, now(), jsonb_build_array(jsonb_build_object('name', 'test_cake_a', 'qty', 10, 'amount', 1000, 'item_id', :'i_a')), 1000, 1000, 'cash', :'o', 'done'),
       (1, 1102, tt.today() - 20, now(), jsonb_build_array(jsonb_build_object('name', 'test_cake_a', 'qty', 16, 'amount', 1600, 'item_id', :'i_a')), 1600, 1600, 'cash', :'o', 'done'),
       (1, 1103, tt.today() - 13, now(), jsonb_build_array(jsonb_build_object('name', 'test_cake_a', 'qty', 99, 'amount', 9900, 'item_id', :'i_a')), 9900, 9900, 'cash', :'o', 'done');
insert into festival_calendar (name_bn, name_en, start_date, end_date, uplift_pct, location_id, created_by)
  values ('test_festival_past', 'test_festival_past', tt.today() - 13, tt.today() - 13, 50, 1, :'o');
insert into stock_balance (item_id, location_id, qty, avg_cost) values (:'i_a', 1, 3, 10);
insert into production_orders (order_date, due_date, location_id, item_id, qty, status, created_by)
  values (tt.today(), tt.today() + 1, 1, :'i_a', 4, 'open', :'o');
select set_config('session_replication_role', 'origin', false);

-- T1 arithmetic: expected 13 (10 and 16), range 10..16, plus 4 open orders, minus 3 carry-over = 14; range 11..17
select xc_prod_suggest(tt.today() + 1, 1) as s1 \gset
select tt.chk('T1 the suggested quantity is 14 (average 13 + orders 4 - carry-over 3)', (select (r ->> 'suggested')::numeric from jsonb_array_elements(:'s1'::jsonb -> 'rows') r where r ->> 'code' = 'T551-A') = 14);
select tt.chk('T1 the range is 11 to 17 (lowest and highest history, with the same orders and carry-over)',
  (select (r ->> 'range_low')::numeric = 11 and (r ->> 'range_high')::numeric = 17 from jsonb_array_elements(:'s1'::jsonb -> 'rows') r where r ->> 'code' = 'T551-A'));
select tt.chk('T1 two trading days were used (the festival day is left out)', (:'s1'::jsonb ->> 'trading_days_used')::int = 2);
select tt.chk('T1 the explanation names the days, the range, the orders and the carry-over in plain words', (select r ->> 'explanation_en' from jsonb_array_elements(:'s1'::jsonb -> 'rows') r where r ->> 'code' = 'T551-A') like '%2 same-weekday trading day(s), range 10 to 16; plus open orders 4; minus carry-over 3.%');
select tt.chk('T1 no festival uplift is shown when the day has no festival', (select r ->> 'with_uplift' from jsonb_array_elements(:'s1'::jsonb -> 'rows') r where r ->> 'code' = 'T551-A') is null);
select tt.chk('T1 a suggestion never writes a production plan', (select count(*) from production_plans) = 0);
select tt.chk('T1 the notes say it is arithmetic, not a forecast, and that the range is not a confidence interval', (:'s1'::jsonb -> 'notes')::text like '%not a forecasting model%' and (:'s1'::jsonb -> 'notes')::text like '%not a confidence interval%');

-- T2 festival uplift on the day itself is shown separately (owner typed 20%)
insert into festival_calendar (name_bn, name_en, start_date, end_date, uplift_pct, location_id, created_by)
  values ('test_festival_next', 'test_festival_next', tt.today() + 1, tt.today() + 1, 20, 1, :'o');
select xc_prod_suggest(tt.today() + 1, 1) as s2 \gset
select tt.chk('T2 the festival and its uplift are shown', :'s2'::jsonb ->> 'festival' = 'test_festival_next' and (:'s2'::jsonb ->> 'uplift_pct')::numeric = 20);
select tt.chk('T2 with uplift 13 x 1.2 + 4 - 3 = 16.6 and it is the suggestion', (select (r ->> 'with_uplift')::numeric = 16.6 and (r ->> 'suggested')::numeric = 16.6 from jsonb_array_elements(:'s2'::jsonb -> 'rows') r where r ->> 'code' = 'T551-A'));

-- T3 blanks and switches: nothing assumed
select set_config('session_replication_role', 'replica', false);
update rules set value = null where key = 'xc_prod_weeks';
select set_config('session_replication_role', 'origin', false);
select xc_prod_suggest(tt.today() + 1, 1) as s3 \gset
select tt.chk('T3 with the weeks blank: no rows and "data needed: xc_prod_weeks"', jsonb_array_length(:'s3'::jsonb -> 'rows') = 0 and (:'s3'::jsonb -> 'data_needed') ? 'xc_prod_weeks');
select set_config('session_replication_role', 'replica', false);
update rules set value = '3'::jsonb where key = 'xc_prod_weeks';
update rules set value = 'false'::jsonb where key = 'xc_prod_suggest_on';
select set_config('session_replication_role', 'origin', false);
select tt.chk('T3 with the switch off: skipped, nothing calculated', (xc_prod_suggest(tt.today() + 1, 1) ->> 'skipped') = 'switch_off');
select tt.err('T3 confirming while the switch is off is refused', format($$select xc_prod_confirm(%L, 1, '[{"item_id":"%s","planned_qty":5}]')$$, tt.today() + 1, :'i_a'), 'suggestion_off');
select set_config('session_replication_role', 'replica', false);
update rules set value = 'true'::jsonb where key = 'xc_prod_suggest_on';
select set_config('session_replication_role', 'origin', false);

-- T4 confirmation stores the suggestion as it stood (14, range 11..17, 2 days) and the baker's planned figure
select xc_prod_confirm(tt.today() + 1, 1, jsonb_build_array(jsonb_build_object('item_id', :'i_a', 'planned_qty', 15))) ->> 'saved' as c1 \gset
select tt.chk('T4 one line saved', :'c1' = '1');
select tt.chk('T4 the stored suggestion is the one shown at confirmation (festival uplift in place: 16.6), range 11..17, 2 days', (select suggested_qty = 16.6 and range_low = 11 and range_high = 17 and days_used = 2 and planned_qty = 15 from xc_prod_feedback where item_id = :'i_a' and plan_date = tt.today() + 1));
select tt.err('T4 a planned quantity cannot be negative', format($$select xc_prod_confirm(%L, 1, '[{"item_id":"%s","planned_qty":-1}]')$$, tt.today() + 1, :'i_a'), 'bad_value');
select xc_prod_confirm(tt.today() + 2, 1, jsonb_build_array(jsonb_build_object('item_id', :'i_a', 'planned_qty', 1))) ->> 'saved' as c2 \gset
select tt.chk('T4 an item with no suggestion is still saved (as a line with a blank suggestion)', :'c2' = '1');
select tt.chk('T4 a blank-suggestion line stores a null suggestion', (select suggested_qty is null from xc_prod_feedback where plan_date = tt.today() + 2 and item_id = :'i_a'));

-- T5 after the day: made and unsold are typed by the person; the accuracy report reads the sales
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, created_by, status)
values (1, 1104, tt.today() + 1, now(), jsonb_build_array(jsonb_build_object('name', 'test_cake_a', 'qty', 12, 'amount', 1200, 'item_id', :'i_a')), 1200, 1200, 'cash', :'o', 'done');
select xc_prod_actual_save(tt.today() + 1, 1, :'i_a', 15, 2, 'test_note') ->> 'ok' as a1 \gset
select tt.chk('T5 made and unsold are stored', :'a1' = 'true' and (select made_qty = 15 and unsold_qty = 2 from xc_prod_feedback where item_id = :'i_a' and plan_date = tt.today() + 1));
select tt.err('T5 made cannot be entered for a day that was never confirmed', format($$select xc_prod_actual_save(%L, 1, '%s', 1, 0, null)$$, tt.today() + 5, :'i_a'), 'not_confirmed');
select xc_prod_accuracy(tt.today() - 30, tt.today() + 1, 1) as acc \gset
select tt.chk('T5 the accuracy report: sold 12 is inside the range 11..17 (100%)', (select (r ->> 'sold_in_range_pct')::numeric = 100 from jsonb_array_elements(:'acc'::jsonb -> 'rows') r where r ->> 'code' = 'T551-A'));
select tt.chk('T5 the accuracy report: the one suggested day was edited (planned 15 against 14): 100%', (select (r ->> 'edited_pct')::numeric = 100 from jsonb_array_elements(:'acc'::jsonb -> 'rows') r where r ->> 'code' = 'T551-A'));

-- T6 access: a staff user with no production grant is refused; the owner is allowed; a bad place is refused
select tt.as(:'st');
select tt.err('T6 a staff user without a production grant cannot see a suggestion', format($$select xc_prod_suggest(%L, 1)$$, tt.today() + 1), 'not allowed');
select tt.err('T6 a staff user cannot confirm', format($$select xc_prod_confirm(%L, 1, '[{"item_id":"%s","planned_qty":1}]')$$, tt.today() + 3, :'i_a'), 'not allowed');
select tt.err('T6 a staff user cannot read the accuracy report', $$select xc_prod_accuracy(null, null, 1)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T6 an unknown place is refused', format($$select xc_prod_suggest(%L, 999)$$, tt.today() + 1), 'bad_location');
select tt.err('T6 a date more than 14 days ahead is refused', format($$select xc_prod_suggest(%L, 1)$$, tt.today() + 30), 'bad_date');

-- T7 no same-weekday trading day in the window at place 2: no history, nothing invented
select set_config('session_replication_role', 'replica', false);
update rules set value = '3'::jsonb where key = 'xc_prod_weeks';
select set_config('session_replication_role', 'origin', false);
select xc_prod_suggest(tt.today() + 1, 2) as s7 \gset
select tt.chk('T7 place 2 with no history says so and suggests nothing', (:'s7'::jsonb -> 'data_needed') ? 'no_same_weekday_trading_day_in_window' and (:'s7'::jsonb ->> 'trading_days_used')::int = 0);

-- T8 the settings are paste-safe: the two rows exist once
select tt.chk('T8 the two suggestion settings exist once each', (select count(*) from rules where key in ('xc_prod_suggest_on', 'xc_prod_weeks')) = 2);

select tt.summary();
