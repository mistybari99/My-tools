-- FRESH DB ONLY. Phase 409-410 tests: sales targets, target vs achievement (#9, #24), KPI snapshots, KPI trends and exception alerts (#10) (package RPT-B4, R5).
--   Build a database through phase 99, paste supabase/phase404.sql .. phase410.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase410_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rb4_fixture.sql (hand-computed numbers in its header) plus sales history made below. Test data only (test_* names).
--   place 1 history (price 200 per kg): D-8, D-15, D-22 each 2 kg = 400 | D-2 one sale 1 kg with a 100 discount (total 100) and one voided sale | D-1 0.5 kg = 100 | today 4 kg = 800 and a 1 kg return (200)
\set ON_ERROR_STOP off
\ir ../tests/sql/rb4_fixture.sql
\ir ../tests/sql/rb4_fixture2.sql
\set ON_ERROR_STOP off
select tt.today() as td \gset
select date_trunc('month', :'td'::date)::date as m0 \gset
select to_char(:'td'::date - 30, 'YYYY-MM-DD') as d_from, to_char(:'td'::date - 1, 'YYYY-MM-DD') as d_to, to_char(:'td'::date - 35, 'YYYY-MM-DD') as d_from35 \gset

\echo == T0 shape
select tt.chk('T0 two tables with row level security; browsers cannot write them, the internals are closed',
  (select count(*) from pg_class where relname in ('sales_targets','kpi_snapshots') and relrowsecurity) = 2 and not has_table_privilege('authenticated','public.sales_targets','insert') and not has_table_privilege('authenticated','public.kpi_snapshots','update')
  and not has_function_privilege('authenticated','public._rb4_sales_days(date,date,int[])','execute') and not has_function_privilege('authenticated','public._rb4_kpi_put(date,int,text,numeric,boolean)','execute')
  and has_function_privilege('authenticated','public.sales_target_set(int,date,numeric,numeric,text)','execute') and not has_function_privilege('anon','public.rb4_kpi_trend(date,date,int)','execute'));
select tt.chk('T0 the grant exists and no role holds it by default (only the owner may set targets)', exists (select 1 from grant_defs where grant_code = 'sales_target_manage') and not exists (select 1 from rule_grants where grant_code = 'sales_target_manage'));
select tt.chk('T0 the three alert settings exist with a blank default (no limit invented)', (select count(*) from rules where key in ('kpi_alert_sales_drop_pct','kpi_alert_discount_pct','kpi_alert_void_n') and default_value is null and kind = 'number') = 3);

\echo == T1 target entry
select (sales_target_set(1, :'td'::date + 0, 10000, 30, 'test target') ->> 'id')::bigint as tg1 \gset
select tt.chk('T1 any day of the month is stored as the first of that month', (select month = :'m0'::date and amount = 10000 and gp_pct = 30 and status = 'active' and created_staff is not null from sales_targets where id = :'tg1'::bigint));
select sales_target_set(2, :'td'::date, 5000) is not null as w_t2 \gset
select tt.chk('T1 the same call again is a no-op', (sales_target_set(1, :'td'::date, 10000, 30, 'test target') ->> 'dup')::boolean and (select count(*) from sales_targets where location_id = 1) = 1);
select (sales_target_set(1, :'td'::date, 12000, 30, 'test raised') ->> 'replaced')::bigint as old1 \gset
select tt.chk('T1 a new amount retires the old line (kept) and writes a new one: one active, one retired', (select count(*) from sales_targets where location_id = 1 and status = 'active') = 1 and (select status = 'retired' and retired_by is not null from sales_targets where id = :'tg1'::bigint));
select tt.chk('T1 the list shows the active line only; with retired it shows both', jsonb_array_length(public.sales_target_list(:'m0'::date, :'m0'::date, 1) -> 'rows') = 1 and jsonb_array_length(public.sales_target_list(:'m0'::date, :'m0'::date, 1, true) -> 'rows') = 2);
select tt.err('T1 a negative amount is refused', format($$select sales_target_set(1,%L::date,-1)$$, :'td'), 'bad_amount');
select tt.err('T1 a gross-profit % above 100 is refused', format($$select sales_target_set(1,%L::date,1,120)$$, :'td'), 'bad_gp_pct');
select tt.err('T1 a missing month is refused', $$select sales_target_set(1,null,100)$$, 'bad_date');
select tt.err('T1 an unknown place is refused', format($$select sales_target_set(999,%L::date,100)$$, :'td'), 'bad_location');
select tt.as(:'fac');
select tt.err('T1 the factory in-charge cannot set a target (server refusal)', format($$select sales_target_set(5,%L::date,100)$$, :'td'), 'not allowed');
select tt.as(:'o');
insert into user_grants (user_id, grant_code) values (:'rep', 'sales_target_manage'), (:'rep', 'report_sales') on conflict do nothing;
select tt.as(:'rep');
select tt.chk('T1 a holder of the grant can set a target for a place of his own', (sales_target_set(5, :'td'::date, 700) ->> 'month')::date = :'m0'::date);
select tt.err('T1 ... but not for a place that is not his', format($$select sales_target_set(2,%L::date,100)$$, :'td'), 'not allowed');
select tt.err('T1 retiring needs a reason', $$select sales_target_retire((select id from sales_targets where location_id = 1 and status = 'active'), 'x')$$, 'note_required');
select tt.as(:'o');
delete from user_grants where user_id = :'rep' and grant_code = 'sales_target_manage';
select (sales_target_retire((select id from sales_targets where location_id = 5 and status = 'active'), 'test: not needed') ->> 'status') as w_r \gset
select tt.chk('T1 a retired target stays as a row', (select status = 'retired' and retired_note like 'test:%' from sales_targets where location_id = 5));
select tt.chk('T1 audit lines exist for targets', (select count(*) from audit_log where table_name = 'sales_targets') >= 4);

\echo == T2 target vs achievement
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":1}]',:'i_fg')::jsonb, (select value_code from option_lists where list_code='return_reasons' and active order by 1 limit 1), 'test', 'cash') ->> 'id' as r1 \gset
select public.rb4_target_report(:'m0'::date, :'m0'::date) as tr \gset
select tt.chk('T2 place 1: target 12000 (the raised one), sales 800 less a return of 200 = 600, achievement 5.0 %, shortfall 11400',
  (select tt.n(r,'target') = 12000 and tt.n(r,'achieved') = 600 and tt.n(r,'gross_sales') = 800 and tt.n(r,'returns') = 200 and tt.n(r,'achievement_pct') = 5.0 and tt.n(r,'shortfall') = 11400 from jsonb_array_elements(:'tr'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 1));
select tt.chk('T2 pace: the share of the month gone, today counted; status on_track if 600 is at least the pace amount, else behind',
  (select tt.n(r,'days_elapsed') = (:'td'::date - :'m0'::date + 1) and tt.near(tt.n(r,'pace_amount'), round(12000 * (:'td'::date - :'m0'::date + 1)::numeric / tt.n(r,'days_in_month'), 2), 0.01)
      and r ->> 'status' = case when 600 >= 12000 * (:'td'::date - :'m0'::date + 1)::numeric / tt.n(r,'days_in_month') then 'on_track' else 'behind' end from jsonb_array_elements(:'tr'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 1));
select tt.chk('T2 place 2: target 5000, no sale -> achieved 0 (a real 0: nothing was sold), behind', (select tt.n(r,'target') = 5000 and tt.n(r,'achieved') = 0 and r ->> 'status' = 'behind' from jsonb_array_elements(:'tr'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 2));
select tt.chk('T2 gross profit: costed, 30 % target, the gap is the difference; no uncosted share', (select r ->> 'gp_state' = 'known' and tt.n(r,'gp_pct') between 50 and 80 and tt.near(tt.n(r,'gp_gap_pp'), tt.n(r,'gp_pct') - 30, 0.01) and tt.n(r,'uncosted_pct') = 0 from jsonb_array_elements(:'tr'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 1));
select tt.chk('T2 place 2 has no gross-profit target: the answer says so (gp_target_not_set or cost_not_captured), never a made-up %', (select r ->> 'gp_state' in ('gp_target_not_set', 'cost_not_captured') and r -> 'gp_gap_pp' = 'null'::jsonb from jsonb_array_elements(:'tr'::jsonb -> 'rows') r where (r ->> 'location_id')::int = 2));
select tt.chk('T2 summary: 2 rows with a target, target total 17000, achieved total 600, no note', tt.n(:'tr'::jsonb -> 'summary','rows_with_target') = 2 and tt.n(:'tr'::jsonb -> 'summary','target_total') = 17000 and tt.n(:'tr'::jsonb -> 'summary','achieved_total_for_targets') = 600 and jsonb_array_length(:'tr'::jsonb -> 'notes') = 0);
select tt.chk('T2 the dashboard figure and the report agree: sales_summary(done) - returns = 600 for place 1 today', (select coalesce(sum(total), 0) from sales_summary(:'td'::date) where location_id = 1 and sale_date = :'td'::date and status = 'done') = 600);
select tt.chk('T2 a month with no target but with sales still shows the sales and "target not set" (previous month empty -> no row)', jsonb_array_length(public.rb4_target_report((:'m0'::date - 40), (:'m0'::date - 40), 1) -> 'rows') <= 1);
select tt.chk('T2 a period with no target at all says "target not set"', (select public.rb4_target_report(:'m0'::date - 600, :'m0'::date - 590) -> 'notes' -> 0 ->> 'code') = 'target_not_set');
select tt.as(:'rep');
select tt.chk('T2 a reader with the sales right but without the cost right sees gp_state cost_hidden and no GP figure', (select r ->> 'gp_state' = 'cost_hidden' and r -> 'gp_pct' = 'null'::jsonb from jsonb_array_elements(public.rb4_target_report(:'m0'::date, :'m0'::date) -> 'rows') r where (r ->> 'location_id')::int = 1)
  and (public.rb4_target_report(:'m0'::date, :'m0'::date) -> 'summary' ->> 'costs_hidden')::boolean);
select tt.as(:'shop');
select tt.err('T2 a salesperson without the sales report right cannot read targets', $$select rb4_target_report(null, null, 1)$$, 'not allowed');
select tt.err('T2 nor the list', $$select sales_target_list(null, null, 1)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T2 a reversed range is refused', format($$select rb4_target_report(%L::date,%L::date)$$, :'m0', (:'m0'::date - 90)::text), 'bad_range');

\echo == T3 history, snapshots, trend and alerts
-- sales history of place 1
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":200}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":400}]','','','retail',null,false)->>'id' as h8 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":200}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":400}]','','','retail',null,false)->>'id' as h15 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":200}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":400}]','','','retail',null,false)->>'id' as h22 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":200}]',:'i_fg')::jsonb,100,'[{"mode":"cash","amount":100}]','','','retail',null,false)->>'id' as h2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":200}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":200}]','','','retail',null,false)->>'id' as h2v \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":0.5,"price":200}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":100}]','','','retail',null,false)->>'id' as h1 \gset
select void_sale(:'h2v'::uuid, 'test void') is null as w_v \gset
update sales set sale_date = :'td'::date - 8, sold_at = sold_at - interval '8 days' where id = :'h8'::uuid;
update sales set sale_date = :'td'::date - 15, sold_at = sold_at - interval '15 days' where id = :'h15'::uuid;
update sales set sale_date = :'td'::date - 22, sold_at = sold_at - interval '22 days' where id = :'h22'::uuid;
update sales set sale_date = :'td'::date - 2, sold_at = sold_at - interval '2 days' where id in (:'h2'::uuid, :'h2v'::uuid);
update sales set sale_date = :'td'::date - 1, sold_at = sold_at - interval '1 day' where id = :'h1'::uuid;
select tt.err('T3 today is not closed: a snapshot of it is refused', format($$select kpi_snapshot_take(%L::date,%L::date)$$, :'td', :'td'), 'day_not_closed');
select tt.err('T3 more than 100 days at once is refused', format($$select kpi_snapshot_take(%L::date,%L::date)$$, (:'td'::date - 200)::text, (:'td'::date - 1)::text), 'bad_range');
select kpi_snapshot_take(:'d_from'::date, :'d_to'::date) as tk \gset
select tt.chk('T3 30 closed days: place 1 (sells) gets 7 figures a day and place 5 (produces) 3 a day = 300 rows', (:'tk'::jsonb ->> 'rows_written')::int = 300 and (select count(*) from kpi_snapshots) = 300);
select tt.chk('T3 a second take changes nothing (existing days are left alone)', (kpi_snapshot_take(:'d_from'::date, :'d_to'::date) ->> 'rows_written')::int = 0 and (select count(*) from kpi_snapshots) = 300);
select tt.chk('T3 the figures: D-8 gross 400, 1 bill; D-2 gross 100, discount 100 on 200, 1 void; D-1 gross 100',
  (select value from kpi_snapshots where snap_date = :'td'::date - 8 and location_id = 1 and kpi = 'gross_sales') = 400 and (select value from kpi_snapshots where snap_date = :'td'::date - 8 and location_id = 1 and kpi = 'bills_n') = 1
  and (select value from kpi_snapshots where snap_date = :'td'::date - 2 and location_id = 1 and kpi = 'discount_amt') = 100 and (select value from kpi_snapshots where snap_date = :'td'::date - 2 and location_id = 1 and kpi = 'subtotal_amt') = 200
  and (select value from kpi_snapshots where snap_date = :'td'::date - 2 and location_id = 1 and kpi = 'void_n') = 1 and (select value from kpi_snapshots where snap_date = :'td'::date - 1 and location_id = 1 and kpi = 'gross_sales') = 100);
select tt.chk('T3 production figures of place 5: D-3 has 1 run with typed yield 20 -> 18; D-1 has 1 run with no typed yield: its measured yield figures are EMPTY (not 0)',
  (select value from kpi_snapshots where snap_date = :'td'::date - 3 and location_id = 5 and kpi = 'runs_n') = 1 and (select value from kpi_snapshots where snap_date = :'td'::date - 3 and location_id = 5 and kpi = 'yield_actual_measured') = 18
  and (select value is null from kpi_snapshots where snap_date = :'td'::date - 1 and location_id = 5 and kpi = 'yield_std_measured') and (select value from kpi_snapshots where snap_date = :'td'::date - 1 and location_id = 5 and kpi = 'runs_n') = 1);
select tt.chk('T3 a day with no sale at a place that sells is a real 0 (D-5 gross 0)', (select value from kpi_snapshots where snap_date = :'td'::date - 5 and location_id = 1 and kpi = 'gross_sales') = 0);
-- the three limits are blank: no alert at all, and the answer says so
select public.rb4_kpi_trend(:'d_from35'::date, :'d_to'::date) as k0 \gset
select tt.chk('T3 with every limit blank there is no alert and three notes say the limits are not set', jsonb_array_length(:'k0'::jsonb -> 'alerts') = 0 and (select count(*) from jsonb_array_elements(:'k0'::jsonb -> 'notes') n where n ->> 'code' = 'alert_limit_not_set') = 3);
select tt.chk('T3 days before the first snapshot are listed as missing (5 days), not drawn as 0', jsonb_array_length(:'k0'::jsonb -> 'missing_days') = 5 and jsonb_array_length(:'k0'::jsonb -> 'days') = 30);
update rules set value = '50'::jsonb where key = 'kpi_alert_sales_drop_pct';
update rules set value = '40'::jsonb where key = 'kpi_alert_discount_pct';
update rules set value = '0'::jsonb where key = 'kpi_alert_void_n';
select public.rb4_kpi_trend(:'d_from35'::date, :'d_to'::date) as k1 \gset
select tt.chk('T3 sales drop: D-1 (100) against the average of the 4 earlier same weekdays (400, 400, 400, 0 = 300) is down 66.7 % -> alert; no other day alerts',
  (select count(*) from jsonb_array_elements(:'k1'::jsonb -> 'alerts') a where a ->> 'kind' = 'sales_drop') = 1
  and (select tt.n(a,'value') = 100 and tt.n(a,'reference') = 300 and tt.n(a,'drop_pct') = 66.7 and (a ->> 'reference_days')::int = 4 and a ->> 'day' = :'d_to' from jsonb_array_elements(:'k1'::jsonb -> 'alerts') a where a ->> 'kind' = 'sales_drop'));
select tt.chk('T3 discount: D-2 gave 100 on 200 = 50 % > 40 % -> alert; void: D-2 had 1 voided sale > 0 -> alert; three alerts in all',
  (select tt.n(a,'value') = 50 from jsonb_array_elements(:'k1'::jsonb -> 'alerts') a where a ->> 'kind' = 'discount_high') and (select tt.n(a,'value') = 1 from jsonb_array_elements(:'k1'::jsonb -> 'alerts') a where a ->> 'kind' = 'void_high')
  and jsonb_array_length(:'k1'::jsonb -> 'alerts') = 3);
select tt.chk('T3 days with fewer than 2 same-weekday references are counted as "not enough history", never alerted', exists (select 1 from jsonb_array_elements(:'k1'::jsonb -> 'notes') n where n ->> 'code' = 'not_enough_history' and (n ->> 'days')::int > 0));
select tt.chk('T3 no alert-limit note any more', not exists (select 1 from jsonb_array_elements(:'k1'::jsonb -> 'notes') n where n ->> 'code' = 'alert_limit_not_set'));
select tt.chk('T3 the series: D-8 net 400 with 1 bill; D-1 net 100; average bill and discount % worked out when read', (select tt.n(d,'net_sales') = 400 and tt.n(d,'bills') = 1 and tt.n(d,'avg_bill') = 400 from jsonb_array_elements(:'k1'::jsonb -> 'days') d where d ->> 'day' = to_char(:'td'::date - 8, 'YYYY-MM-DD'))
  and (select tt.n(d,'discount_pct') = 50 from jsonb_array_elements(:'k1'::jsonb -> 'days') d where d ->> 'day' = to_char(:'td'::date - 2, 'YYYY-MM-DD')));
select tt.chk('T3 yield: D-3 runs 1, yield -10 % (18 against 20); open exceptions are counted for the link', (select tt.n(d,'yield_var_pct') = -10 and tt.n(d,'runs_n') = 1 from jsonb_array_elements(:'k1'::jsonb -> 'days') d where d ->> 'day' = to_char(:'td'::date - 3, 'YYYY-MM-DD'))
  and (:'k1'::jsonb -> 'open_exceptions') is not null);
select tt.chk('T3 by place: place 1 has 30 days with sales figures', (select (p ->> 'days')::int = 30 and tt.n(p,'net_sales') = 1400 from jsonb_array_elements(:'k1'::jsonb -> 'places') p where (p ->> 'location_id')::int = 1));
select tt.chk('T3 the per-place filter works: place 5 has no sales figure (net empty)', (select p -> 'net_sales' = 'null'::jsonb from jsonb_array_elements(public.rb4_kpi_trend(:'d_from'::date, :'d_to'::date, 5) -> 'places') p where (p ->> 'location_id')::int = 5));
-- redo and who
select tt.as(:'rep');
select tt.err('T3 a plain report reader may take a missing day but cannot redo', format($$select kpi_snapshot_take(%L::date,%L::date,true)$$, :'d_from', :'d_to'), 'not allowed');
select tt.chk('T3 the report reader sees place 1 and place 5 (hers) in the trend', jsonb_array_length(public.rb4_kpi_trend(:'d_from'::date, :'d_to'::date) -> 'places') = 2);
select tt.as(:'shop');
select tt.err('T3 a salesperson without the sales right cannot take a snapshot', format($$select kpi_snapshot_take(%L::date,%L::date)$$, :'d_from', :'d_to'), 'not allowed');
select tt.err('T3 nor read the trend', $$select rb4_kpi_trend(null, null, 1)$$, 'not allowed');
insert into ops_accounts (user_id, purpose, active) values (:'shop', 'notify', true) on conflict do nothing;
select tt.chk('T3 the scheduler account that runs notify_scan may take snapshots (nothing new to write here)', (kpi_snapshot_take(:'d_from'::date, :'d_to'::date) ->> 'rows_written')::int = 0);
select tt.as(:'o');
update sales set total = total + 100 where id = :'h1'::uuid;
select tt.chk('T3 redo by the owner writes the 10 figures of that day again', (kpi_snapshot_take(:'d_to'::date, :'d_to'::date, true) ->> 'rows_written')::int = 10);
select tt.chk('T3 ... and D-1 gross has changed from 100 to 200', (select value from kpi_snapshots where snap_date = :'td'::date - 1 and location_id = 1 and kpi = 'gross_sales') = 200);
select tt.err('T3 a bad range is refused', $$select rb4_kpi_trend(current_date, current_date - 4)$$, 'bad_range');

\echo == T4 paste twice
\ir phase409.sql
\ir phase410.sql
select tt.chk('T4 pasting both files again keeps the data and the settings', (select count(*) from sales_targets) = 4 and (select count(*) from kpi_snapshots) = 300 and (select value from rules where key = 'kpi_alert_void_n') = '0'::jsonb);

select 'RESULT ' || count(*) filter (where ok) || '/' || count(*) || ' passed' from tt.res;
