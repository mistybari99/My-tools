-- FRESH DB ONLY. Phase 468 tests (RPT-C3 R9 part 4): #192 scenario what-if and #193 seasonal / festival analysis.
--   bash tests/sql/rptc3_run.sh 468
-- History: tests/sql/rptc3_history.sql. Test data only (test_* names). Expected values that depend on the calendar month are computed from the base functions in the test.
\ir ../tests/sql/rptc3_head.sql
\ir ../tests/sql/rptc3_history.sql
select tt.as(:'u_o');
insert into user_grants (user_id, grant_code, location_id) values (:'u_rm', 'report_profit', null), (:'u_ex', 'report_sales', null) on conflict do nothing;
select to_char(tt.today() - 30, 'YYYY-MM-DD') as f30, to_char(tt.today(), 'YYYY-MM-DD') as t0, to_char(tt.today() - 7, 'YYYY-MM-DD') as f7, to_char(tt.today() - 6, 'YYYY-MM-DD') as t6 \gset

-- T1 scenario (#192): the baseline is the management view's own figures
select sum(o_net) as bnet, sum(o_costed) as bcost, sum(o_cogs) as bcogs, sum(o_exp) as bexp from public._p27_pl(:'f30'::date, :'t0'::date, array[1,2]) \gset
select fc_scenario(null, :'f30'::date, :'t0'::date, '{}') as s0 \gset
select tt.chk('T1 no input: the scenario equals the baseline on every line (no percent is assumed)', (select bool_and(coalesce(tt.n(l,'delta'), 0) = 0) from jsonb_array_elements((:'s0'::jsonb)->'lines') l));
select tt.chk('T1 baseline net sales and cost agree with the management view', (select tt.n(l,'baseline') = :'bnet'::numeric from jsonb_array_elements((:'s0'::jsonb)->'lines') l where l->>'key' = 'net_sales') and (select tt.n(l,'baseline') = round(:'bcogs'::numeric, 2) from jsonb_array_elements((:'s0'::jsonb)->'lines') l where l->>'key' = 'cost_of_goods_costed_part'));
select fc_scenario(null, :'f30'::date, :'t0'::date, '{"volume_pct":"10","price_pct":"5","cost_pct":"-10","expense_pct":"20"}') as s1 \gset
select tt.chk('T1 volume +10% and price +5%: net sales x 1.155', (select abs(tt.n(l,'scenario') - round(:'bnet'::numeric * 1.1 * 1.05, 2)) <= 0.01 from jsonb_array_elements((:'s1'::jsonb)->'lines') l where l->>'key' = 'net_sales'));
select tt.chk('T1 goods cost moves with volume and unit cost only: x 1.1 x 0.9', (select abs(tt.n(l,'scenario') - round(:'bcogs'::numeric * 1.1 * 0.9, 2)) <= 0.01 from jsonb_array_elements((:'s1'::jsonb)->'lines') l where l->>'key' = 'cost_of_goods_costed_part'));
select tt.chk('T1 vouchers + 20% only on the expense line', (select abs(tt.n(l,'scenario') - round(:'bexp'::numeric * 1.2, 2)) <= 0.01 from jsonb_array_elements((:'s1'::jsonb)->'lines') l where l->>'key' = 'expense_vouchers'));
select tt.chk('T1 a quick sale has no cost, so the costed share is not full and the result is BLANK with the reasons named (no profit guessed)', (select l->>'scenario' is null and l->>'baseline' is null from jsonb_array_elements((:'s1'::jsonb)->'lines') l where l->>'key' = 'result_after_costs')
  and (:'s1'::jsonb)->'result_missing' @> '["cost_coverage_not_full","salary_not_captured","fixed_cost_not_set"]'::jsonb);
select tt.chk('T1 the notes say it is arithmetic, not a forecast, and no percent is suggested', (:'s1'::jsonb)->'notes' @> '["arithmetic_on_typed_percents_not_a_forecast","no_percent_is_suggested"]'::jsonb);
select tt.err('T1 an unknown input is refused', format($$select fc_scenario(null,'%s','%s','{"magic":"5"}')$$, :'f30', :'t0'), 'bad_input');
select tt.err('T1 -100% is refused', format($$select fc_scenario(null,'%s','%s','{"volume_pct":"-100"}')$$, :'f30', :'t0'), 'bad_input');
select tt.err('T1 text is refused', format($$select fc_scenario(null,'%s','%s','{"price_pct":"ten"}')$$, :'f30', :'t0'), 'bad_input');
select tt.chk('T1 a period with no sales: data needed, not a row of zeros', fc_scenario(null, tt.today()-900, tt.today()-890, '{}')->'data_needed' ? 'sales_in_period');
-- a clean window: only costed bills (T-7, T-6), a voucher, a salary sheet, a fixed cost: the result appears
select save_entry(null,'10-2',1,:'t6'::date,'{"lines":[{"head":"transport","amount":"40"}]}'::jsonb,'[]') ->> 'id' as v \gset
select submit_entry(:'v'::uuid) is not null as vs \gset
select decide_entry(:'v'::uuid,true,null,'{}','[]') ->> 'status' as vd \gset
select save_entry(null,'02-2',1,:'t6'::date,'{"pay":[{"due":"100"}]}'::jsonb,'[]') ->> 'id' as sh \gset
select submit_entry(:'sh'::uuid) is not null as shs \gset
insert into location_settings (location_id, key, value) values (1, 'fixed_cost_month', '3000'::jsonb) on conflict (location_id, key) do update set value = '3000'::jsonb;
select sum(o_net) as cnet, sum(o_cogs) as ccogs, sum(o_exp) as cexp, sum(o_sal) as csal, sum(o_fixed) as cfix from public._p27_pl(:'f7'::date, :'t6'::date, array[1,2]) \gset
select fc_scenario(1, :'f7'::date, :'t6'::date, '{"volume_pct":"20","salary_pct":"10"}') as s2 \gset
select tt.chk('T1 clean window: net 500 (300 + 200), cost 6 units x 14... all costed, so the result shows', (select tt.n(l,'baseline') = 500 from jsonb_array_elements((:'s2'::jsonb)->'lines') l where l->>'key' = 'net_sales') and jsonb_array_length((:'s2'::jsonb)->'result_missing') = 0);
select tt.chk('T1 result after costs: baseline = net - cost - vouchers - salary - fixed', (select abs(tt.n(l,'baseline') - round(:'cnet'::numeric - :'ccogs'::numeric - :'cexp'::numeric - :'csal'::numeric - :'cfix'::numeric, 2)) <= 0.01 from jsonb_array_elements((:'s2'::jsonb)->'lines') l where l->>'key' = 'result_after_costs'));
select tt.chk('T1 scenario result = 1.2 x net - 1.2 x cost - vouchers - 1.1 x salary - fixed', (select abs(tt.n(l,'scenario') - round(:'cnet'::numeric * 1.2 - :'ccogs'::numeric * 1.2 - :'cexp'::numeric - :'csal'::numeric * 1.1 - :'cfix'::numeric, 2)) <= 0.01 from jsonb_array_elements((:'s2'::jsonb)->'lines') l where l->>'key' = 'result_after_costs'));
-- cost hidden
select tt.as(:'u_rm');
select tt.chk('T1 a profit reader without the cost right: cost lines blank, the result blank, the reason named', (select bool_and(l->>'baseline' is null) from jsonb_array_elements(fc_scenario(1, :'f7'::date, :'t6'::date, '{}')->'lines') l where l->>'key' in ('cost_of_goods_costed_part','result_after_costs')) and fc_scenario(1, :'f7'::date, :'t6'::date, '{}')->'result_missing' ? 'cost_hidden');
select tt.as(:'u_nb');
select tt.err('T1 nobody', format($$select fc_scenario(null,'%s','%s','{}')$$, :'f30', :'t0'), 'not allowed');
select tt.as(:'u_o');

-- T2 seasonal and festival analysis (#193)
update festival_calendar set uplift_pct = 30 where id = tt.k_('fo')::bigint;
select fc_seasonal(null, 28, 3) as se \gset
select tt.chk('T2 the past festival (T-14): 1 trading day of 500 against the ordinary days before it (T-21: 400) = +25.0%', (select tt.n(x,'trading_days') = 1 and tt.n(x,'avg_per_trading_day') = 500 and tt.n(x,'baseline_trading_days') = 1 and tt.n(x,'baseline_avg_per_trading_day') = 400 and tt.n(x,'observed_difference_pct') = 25.0 from jsonb_array_elements((:'se'::jsonb)->'festivals') x where x->>'name_en' = 'test_fest_old'));
select tt.chk('T2 the owner uplift (30%) is shown beside the observed one, for comparison only', (select tt.n(x,'owner_uplift_pct') = 30 from jsonb_array_elements((:'se'::jsonb)->'festivals') x where x->>'name_en' = 'test_fest_old') and (:'se'::jsonb)->'notes' ? 'owner_uplift_shown_for_comparison_only');
select tt.chk('T2 a festival still to come is listed as upcoming, not analysed', exists (select 1 from jsonb_array_elements((:'se'::jsonb)->'upcoming') x where x->>'name_en' = 'test_fest_new') and not exists (select 1 from jsonb_array_elements((:'se'::jsonb)->'festivals') x where x->>'name_en' = 'test_fest_new'));
select tt.chk('T2 grouped by name: one occurrence with data, average +25.0', (select tt.n(x,'occurrences') = 1 and tt.n(x,'with_data') = 1 and tt.n(x,'average_observed_difference_pct') = 25.0 from jsonb_array_elements((:'se'::jsonb)->'grouped') x where x->>'name' = 'test_fest_old'));
-- an earlier festival with no sales around it: no percentage, not 0
select festival_save(null, jsonb_build_object('name_bn','test_fest_empty','name_en','test_fest_empty','start_date',tt.today()-300,'end_date',tt.today()-298)) ->> 'id' as fe \gset
select tt.chk('T2 a festival with no sales in or before it has no percentage (null) and says 0 trading days', (select x->>'observed_difference_pct' is null and tt.n(x,'trading_days') = 0 and x->>'avg_per_trading_day' is null from jsonb_array_elements(fc_seasonal(null, 28, 3)->'festivals') x where x->>'name_en' = 'test_fest_empty'));
select tt.chk('T2 sales by month cover the months asked, with trading days, and add up to the sales', jsonb_array_length((:'se'::jsonb)->'by_month') between 1 and 3
  and (select sum((x->>'net_sales')::numeric) from jsonb_array_elements((:'se'::jsonb)->'by_month') x) = (select sum(total) from sales where status = 'done' and sale_date >= (date_trunc('month', tt.today()) - interval '2 months')::date));
select tt.err('T2 baseline days must be typed (7 to 90)', $$select fc_seasonal(null, 3, 3)$$, 'bad_range');
select tt.err('T2 months must be typed', $$select fc_seasonal(null, 28, null)$$, 'bad_range');
select tt.as(:'u_nb');
select tt.err('T2 nobody', $$select fc_seasonal(null, 28, 3)$$, 'not allowed');
select tt.as(:'u_ex');
select tt.chk('T2 a report_sales holder reads it', jsonb_array_length(fc_seasonal(1, 28, 3)->'festivals') >= 1);
select tt.as(:'u_o');
\i supabase/phase468.sql
select tt.chk('T3 paste twice: still answers, books balanced, nothing written', tt.n(fc_seasonal(null, 28, 3)->'festivals'->0,'trading_days') is not null and tt.unbalanced() = 0);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
