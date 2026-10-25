-- FRESH DB ONLY. Phase 403 tests: three added reports (daily sell-out, festival comparison, top customers' items) and report_drill (package RPT-B1).
--   Build a database through phase 99, paste supabase/phase400.sql .. phase403.sql, then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase403_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/rptb1_fixture.sql, rptb1_fixture2.sql, rptb1_fixture3.sql (hand-computed numbers in their headers). The hooks file is installed by this file. Test data only (test_* names).
\set ON_ERROR_STOP off
\ir ../tests/sql/rptb1_fixture.sql
\ir ../tests/sql/rptb1_fixture2.sql
\ir ../tests/sql/rptb1_fixture3.sql
\set ON_ERROR_STOP off
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.has_note(p_j jsonb, p_code text) returns boolean language sql immutable as $$ select exists (select 1 from jsonb_array_elements(p_j -> 'notes') n where n ->> 'code' = p_code) $$;
create or replace function tt.note(p_j jsonb, p_code text) returns jsonb language sql immutable as $$ select n from jsonb_array_elements(p_j -> 'notes') n where n ->> 'code' = p_code limit 1 $$;
-- one row of a report answer: by item code (and optionally day / place / customer rank)
create or replace function tt.row(p_j jsonb, p_code text, p_day text default null, p_loc text default null) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(p_j -> 'rows') e where e ->> 'item_code' = p_code and (p_day is null or e ->> 'day' = p_day) and (p_loc is null or e ->> 'location_id' = p_loc) limit 1 $$;
create or replace function tt.n(p_j jsonb, p_k text) returns numeric language sql immutable as $$ select (p_j ->> p_k)::numeric $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select tt.today() as td \gset
select to_char(:'td'::date - 2, 'YYYY-MM-DD') as dm2, to_char(:'td'::date - 1, 'YYYY-MM-DD') as dm1, to_char(:'td'::date, 'YYYY-MM-DD') as dt0 \gset
select tt.as(:'o');

\echo == T0 shape
select tt.chk('T0 phase403 present; three registry rows; the setting exists with a blank default', to_regprocedure('public._rptb1_p403_present()') is not null and (select count(*) from report_defs3 where key in ('y1_daily_sellout', 'y2_festival_compare', 'y3_customer_items') and is_active) = 3
  and (select default_value is null and kind = 'number' and label_en = label_bn from rules where key = 'report_top_customers_n'));
select tt.chk('T0 internals closed to browsers; report_drill open to signed-in users only', not has_function_privilege('authenticated','public._r3q_y1_daily_sellout(date,date,integer[],jsonb)','execute') and not has_function_privilege('authenticated','public._rptb1_y_notes(text,date,date,integer[],jsonb)','execute')
  and has_function_privilege('authenticated','public.report_drill(text,jsonb)','execute') and not has_function_privilege('anon','public.report_drill(text,jsonb)','execute'));
\ir ../docs/integration/RPT-B1_hooks.sql
select tt.chk('T0 the hooks are in (section 2 carries the notes call that reaches the three reports)', (select bool_and(value::boolean) from jsonb_each_text(public._rptb1_hooked401())));
select tt.chk('T0 the reports are in the second-engine catalogue (hub) under their groups', (select count(*) from jsonb_array_elements(public.report_catalog2()) c where c ->> 'key' in ('y1_daily_sellout', 'y2_festival_compare', 'y3_customer_items')
  and c ->> 'group' = case c ->> 'key' when 'y1_daily_sellout' then 'stock' when 'y2_festival_compare' then 'sales' else 'customers' end and (c ->> 'allowed')::boolean) = 3);

\echo == T1 daily sell-out
select public.report_run2('y1_daily_sellout', jsonb_build_object('from', :'dm2', 'to', :'dt0')) as y1 \gset
select tt.chk('T1 D-2 test_cake place 1: opening 20, produced 30, received 10, sold 25, wasted 3, left 32, sell-through 41.7 %, waste cost 132.50',
  (select tt.n(r, 'opening') = 20 and tt.n(r, 'produced') = 30 and tt.n(r, 'received') = 10 and tt.n(r, 'sold') = 25 and tt.n(r, 'wasted') = 3 and tt.n(r, 'closing') = 32 and tt.n(r, 'sell_through_pct') = 41.7 and tt.n(r, 'waste_cost') = 132.5
     from (select tt.row(:'y1'::jsonb, 'RB1-K', :'dm2', '1') r) z));
select tt.chk('T1 D-1 place 1: opening 32 (yesterday''s close), produced 20, sold 28, sent 4, left 20, sell-through 28 / 52 = 53.8 %, no waste = 0', (select tt.n(r, 'opening') = 32 and tt.n(r, 'produced') = 20 and tt.n(r, 'sold') = 28 and tt.n(r, 'sent') = 4 and tt.n(r, 'closing') = 20 and tt.n(r, 'sell_through_pct') = 53.8 and tt.n(r, 'waste_cost') = 0
     from (select tt.row(:'y1'::jsonb, 'RB1-K', :'dm1', '1') r) z));
select tt.chk('T1 today place 1: opening 20, sold 10, returned 1, wasted 2, left 9, sell-through (10 - 1) / 20 = 45 %, waste cost about 85.13 (2 x 42.5641)', (select tt.n(r, 'opening') = 20 and tt.n(r, 'sold') = 10 and tt.n(r, 'returned') = 1 and tt.n(r, 'wasted') = 2 and tt.n(r, 'closing') = 9 and tt.n(r, 'sell_through_pct') = 45 and abs(tt.n(r, 'waste_cost') - 85.13) < 0.02
     from (select tt.row(:'y1'::jsonb, 'RB1-K', :'dt0', '1') r) z));
select tt.chk('T1 place 2 on D-1: received 4, left 4, nothing sold = 0.0 %', (select tt.n(r, 'received') = 4 and tt.n(r, 'closing') = 4 and tt.n(r, 'sell_through_pct') = 0 from (select tt.row(:'y1'::jsonb, 'RB1-K', :'dm1', '2') r) z));
select tt.chk('T1 an item whose stock came in with no cost: waste cost EMPTY (unknown), never 0', (select (r -> 'waste_cost') = 'null'::jsonb and tt.n(r, 'wasted') = 1 and tt.n(r, 'closing') = 9 from (select tt.row(:'y1'::jsonb, 'RB1-K2', :'dt0', '1') r) z));
select tt.chk('T1 the stock identity holds on every row: closing = opening + produced + received + returned - sold - wasted - sent + other', (select bool_and(tt.n(e, 'closing') = tt.n(e, 'opening') + tt.n(e, 'produced') + tt.n(e, 'received') + tt.n(e, 'returned') - tt.n(e, 'sold') - tt.n(e, 'wasted') - tt.n(e, 'sent') + tt.n(e, 'other'))
     from jsonb_array_elements(:'y1'::jsonb -> 'rows') e));
select tt.chk('T1 a day''s close is the next day''s opening (test_cake place 1)', tt.n(tt.row(:'y1'::jsonb, 'RB1-K', :'dm2', '1'), 'closing') = tt.n(tt.row(:'y1'::jsonb, 'RB1-K', :'dm1', '1'), 'opening') and tt.n(tt.row(:'y1'::jsonb, 'RB1-K', :'dm1', '1'), 'closing') = tt.n(tt.row(:'y1'::jsonb, 'RB1-K', :'dt0', '1'), 'opening'));
select tt.chk('T1 the item that did not move in the window (test_cake_old) has no row; sales of the untracked item are not in it', tt.row(:'y1'::jsonb, 'RB1-L') is null and tt.row(:'y1'::jsonb, 'RB1-U') is null);
select tt.chk('T1 the untracked item and the quick line are named in a "not captured" note with what is needed', (select n ->> 'code' = 'not_captured' and (n ->> 'items')::int = 1 and (n ->> 'quick_lines')::int = 1 and n ->> 'text_en' like '%Needed%tracked%' and n ->> 'text_bn' like '%দরকার%' from (select tt.note(:'y1'::jsonb, 'not_captured') n) z));
select tt.chk('T1 the totals add the movements', tt.n(:'y1'::jsonb -> 'totals', 'produced') = (select sum(tt.n(e, 'produced')) from jsonb_array_elements(:'y1'::jsonb -> 'rows') e) and tt.n(:'y1'::jsonb -> 'totals', 'sold') = (select sum(tt.n(e, 'sold')) from jsonb_array_elements(:'y1'::jsonb -> 'rows') e));
select tt.chk('T1 the place and category filters work', (select count(*) from jsonb_array_elements(public.report_run2('y1_daily_sellout', jsonb_build_object('from', :'dm2', 'to', :'dt0', 'locations', jsonb_build_array(2))) -> 'rows') e where e ->> 'location_id' <> '2') = 0
  and (select count(*) from jsonb_array_elements(public.report_run2('y1_daily_sellout', jsonb_build_object('from', :'dm2', 'to', :'dt0', 'categories', jsonb_build_array('test_cat_cake'))) -> 'rows') e where e ->> 'item_code' not like 'RB1-K%') = 0);
-- ledger vs the report for the whole window (independent recomputation from the ledger)
select tt.chk('T1 sold per the report = the ledger''s sale_out + void rows for test_cake place 1', (select sum(tt.n(e, 'sold')) from jsonb_array_elements(:'y1'::jsonb -> 'rows') e where e ->> 'item_code' = 'RB1-K' and e ->> 'location_id' = '1')
  = (select -sum(l.qty_delta) from stock_ledger l join items i on i.id = l.item_id where i.code = 'RB1-K' and l.location_id = 1 and l.reason in ('sale_out', 'sale_void_in') and (l.made_at at time zone 'Asia/Dhaka')::date between :'dm2'::date and :'dt0'::date));

\echo == T2 drill-down of a sell-out row
select public.report_drill('y1_daily_sellout', (tt.row(:'y1'::jsonb, 'RB1-K', :'dt0', '1')) -> '_drill') as d1 \gset
select tt.chk('T2 the row''s transactions: 2 sales, 1 wastage, 1 return - quantities add up to the day''s movement (-10 -2 +1)', jsonb_array_length(:'d1'::jsonb -> 'rows') = 4 and (select sum((e ->> 'qty')::numeric) from jsonb_array_elements(:'d1'::jsonb -> 'rows') e) = -11
  and (select count(*) from jsonb_array_elements(:'d1'::jsonb -> 'rows') e where e ->> 'ref' like 'Receipt %') = 2 and :'d1'::jsonb ->> 'title_en' like '%stock movements%' and :'d1'::jsonb ->> 'title_bn' like '%স্টকের নড়াচড়া%');
select tt.chk('T2 the owner sees the unit cost column', exists (select 1 from jsonb_array_elements(:'d1'::jsonb -> 'columns') c where c ->> 'key' = 'unit_cost'));
select tt.err('T2 a bad reference is refused', $$select public.report_drill('y1_daily_sellout', '{"day":"x","loc":1,"item":"y"}'::jsonb)$$, 'bad_filter');
select tt.err('T2 an unknown report is refused', $$select public.report_drill('l1_pnl', '{}'::jsonb)$$, 'unknown_report');

\echo == T3 festival comparison
select public.report_run2('y2_festival_compare', jsonb_build_object('from', :'dm2', 'to', :'dt0')) as y2 \gset
select tt.chk('T3 test_cake: now 62 pieces (63 sold - 1 returned) for 3720; last year 40 for 2400; +22 = 55.0 % in quantity, 55.0 % in sales; state up', (select tt.n(r, 'qty_now') = 62 and tt.n(r, 'net_now') = 3720 and tt.n(r, 'qty_prev') = 40 and tt.n(r, 'net_prev') = 2400 and tt.n(r, 'qty_change') = 22 and tt.n(r, 'qty_change_pct') = 55 and tt.n(r, 'net_change_pct') = 55 and r ->> 'state' like '%up'
     from (select tt.row(:'y2'::jsonb, 'RB1-K') r) z));
select tt.chk('T3 item A: 9 sold - 2 returned = 7 for 700 against 5 for 500: +2, 40 %', (select tt.n(r, 'qty_now') = 7 and tt.n(r, 'net_now') = 700 and tt.n(r, 'qty_prev') = 5 and tt.n(r, 'qty_change_pct') = 40 from (select tt.row(:'y2'::jsonb, 'RB1-A') r) z));
select tt.chk('T3 item B was not sold last year: previous quantity 0 and the state says so (12 now after 4 returned)', (select tt.n(r, 'qty_now') = 12 and tt.n(r, 'qty_prev') = 0 and r ->> 'state' like '%not sold last year' from (select tt.row(:'y2'::jsonb, 'RB1-B') r) z));
select tt.chk('T3 item L sold last year (7 for 175) and not now: a row with 0 now and the state "not sold this time"', (select tt.n(r, 'qty_now') = 0 and tt.n(r, 'qty_prev') = 7 and tt.n(r, 'net_prev') = 175 and r ->> 'state' like '%not sold this time' from (select tt.row(:'y2'::jsonb, 'RB1-L') r) z));
select tt.chk('T3 the quick / unlisted lines are one row of their own (90), compared by sales', (select tt.n(r, 'net_now') = 90 and r ->> 'state' like '%not sold last year' from (select tt.row(:'y2'::jsonb, 'quick') r) z));
select tt.chk('T3 totals: sales now 5570, before 3075', tt.n(:'y2'::jsonb -> 'totals', 'net_now') = 5570 and tt.n(:'y2'::jsonb -> 'totals', 'net_prev') = 3075);
select tt.chk('T3 the note names the compared dates (one year earlier) and says sales are after returns', (select n ->> 'from' = to_char(:'dm2'::date - interval '1 year', 'YYYY-MM-DD') and n ->> 'text_en' like '%after returns%' from (select tt.note(:'y2'::jsonb, 'compare_range') n) z) and not tt.has_note(:'y2'::jsonb, 'not_captured'));
select public.report_run2('y2_festival_compare', jsonb_build_object('from', :'dm2', 'to', :'dt0', 'prev_from', '2019-01-01', 'prev_to', '2019-01-03')) as y2n \gset
select tt.chk('T3 NO PREVIOUS DATA: compared with a period without any sale, previous columns are EMPTY (not 0), the state says so and a "not captured" note says what is needed',
  (select r -> 'qty_prev' = 'null'::jsonb and r -> 'net_prev' = 'null'::jsonb and r ->> 'state' like '%no previous data' from (select tt.row(:'y2n'::jsonb, 'RB1-K') r) z) and tt.has_note(:'y2n'::jsonb, 'not_captured') and (select n ->> 'text_en' like '%Compare with%' from (select tt.note(:'y2n'::jsonb, 'not_captured') n) z));
select tt.chk('T3 other dates can be chosen: last year''s window moved by a day still finds the test_cake sales', tt.n(tt.row(public.report_run2('y2_festival_compare', jsonb_build_object('from', :'dm2', 'to', :'dt0', 'prev_from', to_char(:'dm1'::date - interval '1 year', 'YYYY-MM-DD'), 'prev_to', to_char(:'dm1'::date - interval '1 year', 'YYYY-MM-DD'))), 'RB1-K'), 'qty_prev') = 40);
select tt.err('T3 a previous window that ends before it starts is refused', format($$select public.report_run2('y2_festival_compare', '{"from":"%s","to":"%s","prev_from":"2019-02-01","prev_to":"2019-01-01"}'::jsonb)$$, :'dm2', :'dt0'), 'bad_range');
select set_rule('reports_net_of_returns', 'false') is null as w_off \gset
select tt.chk('T3 the rule reports_net_of_returns is honoured: off = before returns (63 pieces / 3780), and the note says so', (select tt.n(r, 'qty_now') = 63 and tt.n(r, 'net_now') = 3780 from (select tt.row(public.report_run2('y2_festival_compare', jsonb_build_object('from', :'dm2', 'to', :'dt0')), 'RB1-K') r) z)
  and (select n ->> 'text_en' like '%before returns%' from (select tt.note(public.report_run2('y2_festival_compare', jsonb_build_object('from', :'dm2', 'to', :'dt0')), 'compare_range') n) z));
select set_rule('reports_net_of_returns', 'true') is null as w_on \gset
select public.report_drill('y2_festival_compare', (tt.row(:'y2'::jsonb, 'RB1-K')) -> '_drill') as d2 \gset
select tt.chk('T3 drill: the sales behind test_cake - 6 sales now (10, 15, 14, 14, 5, 5) and 2 last year, plus the return; quantities add up to 62 + 40', (select count(*) from jsonb_array_elements(:'d2'::jsonb -> 'rows') e where e ->> 'period' like '%this time') = 7
  and (select count(*) from jsonb_array_elements(:'d2'::jsonb -> 'rows') e where e ->> 'period' like '%before') = 2 and (select sum((e ->> 'qty')::numeric) from jsonb_array_elements(:'d2'::jsonb -> 'rows') e where e ->> 'period' like '%this time') = 62
  and (select sum((e ->> 'qty')::numeric) from jsonb_array_elements(:'d2'::jsonb -> 'rows') e where e ->> 'period' like '%before') = 40);

\echo == T4 top customers and their items
select public.report_run2('y3_customer_items', jsonb_build_object('from', :'dm2', 'to', :'dt0')) as y3 \gset
select tt.chk('T4 three customers, ranked by sales after returns: #1 test_customer_rb2 500, #2 test_customer_rb1 400 (500 - 100 returned), #3 test_customer_rb3 100', (select string_agg(distinct (e ->> 'rank') || ':' || (e ->> 'customer_name') || ':' || (e ->> 'customer_net'), ' ' order by (e ->> 'rank') || ':' || (e ->> 'customer_name') || ':' || (e ->> 'customer_net'))
     from jsonb_array_elements(:'y3'::jsonb -> 'rows') e) = '1:test_customer_rb2:500.00 2:test_customer_rb1:400.00 3:test_customer_rb3:100.00');
select tt.chk('T4 customer 2 buys test_cake 5 for 300 (60 %) and item A 2 for 200 (40 %)', (select tt.n(r, 'qty') = 5 and tt.n(r, 'net') = 300 and tt.n(r, 'share_pct') = 60 from (select tt.row(:'y3'::jsonb, 'RB1-K') r) z) and (select tt.n(r, 'net') = 200 and tt.n(r, 'share_pct') = 40 from (select tt.row(:'y3'::jsonb, 'RB1-A') r) z));
select tt.chk('T4 customer 1: item B 10 sold - 2 returned = 8 for 400, 1 bill', (select e ->> 'customer_name' = 'test_customer_rb1' and tt.n(e, 'qty') = 8 and tt.n(e, 'net') = 400 and (e ->> 'bills')::int = 1 from jsonb_array_elements(:'y3'::jsonb -> 'rows') e where e ->> 'item_code' = 'RB1-B' and e ->> 'rank' = '2'));
select tt.chk('T4 the owner sees the mobile in full; walk-in sales are counted and said (customer_coverage note)', (select count(*) from jsonb_array_elements(:'y3'::jsonb -> 'rows') e where e ->> 'mobile' like '%****%') = 0 and tt.has_note(:'y3'::jsonb, 'customer_coverage'));
select set_rule('report_top_customers_n', '2') is null as w_n \gset
select public.report_run2('y3_customer_items', jsonb_build_object('from', :'dm2', 'to', :'dt0')) as y3b \gset
select tt.chk('T4 the setting limits the list to 2 customers and the note says so', (select count(distinct e ->> 'customer_name') from jsonb_array_elements(:'y3b'::jsonb -> 'rows') e) = 2 and (tt.note(:'y3b'::jsonb, 'top_n') ->> 'n')::int = 2);
select set_rule('report_top_customers_n', 'null'::jsonb) is null as w_n2 \gset
select tt.chk('T4 a customer filter restricts the list', (select count(distinct e ->> 'customer_name') from jsonb_array_elements(public.report_run2('y3_customer_items', jsonb_build_object('from', :'dm2', 'to', :'dt0', 'customer', jsonb_build_array((select id from customers where mobile = '01800000403')))) -> 'rows') e) = 1);
select public.report_drill('y3_customer_items', (select e -> '_drill' from jsonb_array_elements(:'y3'::jsonb -> 'rows') e where e ->> 'item_code' = 'RB1-B' and e ->> 'rank' = '2')) as d3 \gset
select tt.chk('T4 drill: the sale (10) and the return (-2) of customer 1 for item B; 8 in total', jsonb_array_length(:'d3'::jsonb -> 'rows') = 2 and (select sum((e ->> 'qty')::numeric) from jsonb_array_elements(:'d3'::jsonb -> 'rows') e) = 8);

\echo == T5 who sees what
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_customers', null), (:'st', 'report_stock', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select public.report_run2('y3_customer_items', jsonb_build_object('from', :'dm2', 'to', :'dt0')) as y3s \gset
select tt.chk('T5 a place-1 person without the mobile right sees the mobile masked', (select bool_and(e ->> 'mobile' like '018****%') from jsonb_array_elements(:'y3s'::jsonb -> 'rows') e) and jsonb_array_length(:'y3s'::jsonb -> 'rows') > 0);
select public.report_run2('y1_daily_sellout', jsonb_build_object('from', :'dm2', 'to', :'dt0')) as y1s \gset
select tt.chk('T5 without the cost right the waste cost is EMPTY and a note says it is hidden', (select bool_and(e -> 'waste_cost' = 'null'::jsonb) from jsonb_array_elements(:'y1s'::jsonb -> 'rows') e) and tt.has_note(:'y1s'::jsonb, 'cost_hidden') and jsonb_array_length(:'y1s'::jsonb -> 'rows') > 0);
select public.report_drill('y1_daily_sellout', (tt.row(:'y1s'::jsonb, 'RB1-K', :'dt0', '1')) -> '_drill') as d1s \gset
select tt.chk('T5 the drill-down hides the unit cost column too', not exists (select 1 from jsonb_array_elements(:'d1s'::jsonb -> 'columns') c where c ->> 'key' = 'unit_cost') and (select bool_and(e -> 'unit_cost' = 'null'::jsonb) from jsonb_array_elements(:'d1s'::jsonb -> 'rows') e));
select tt.chk('T5 a drill-down for place 2 is empty for the place-1 person (location scope)', jsonb_array_length(public.report_drill('y1_daily_sellout', jsonb_build_object('day', :'dm1', 'loc', 2, 'item', (select id from items where code = 'RB1-K'))) -> 'rows') = 0);
reset role; delete from user_grants where user_id = :'st'::uuid and grant_code in ('report_customers', 'report_stock'); set role authenticated; select tt.as(:'st');
select tt.err('T5 without the group right the reports and the drill-down are refused', $$select public.report_run2('y2_festival_compare', '{"preset":"last_7"}'::jsonb)$$, 'not allowed');
select tt.err('T5 drill-down refused as well', $$select public.report_drill('y3_customer_items', '{}'::jsonb)$$, 'not allowed');
reset role; select tt.as(:'o');

\echo == T6 paste twice, books
select md5(pg_get_functiondef('public._r3q_y1_daily_sellout(date,date,integer[],jsonb)'::regprocedure) || pg_get_functiondef('public.report_drill(text,jsonb)'::regprocedure) || pg_get_functiondef('public._rptb1_y_notes(text,date,date,integer[],jsonb)'::regprocedure)) as h \gset
\ir phase403.sql
select tt.chk('T6 phase403 again: functions unchanged, still 3 registry rows, one setting row', md5(pg_get_functiondef('public._r3q_y1_daily_sellout(date,date,integer[],jsonb)'::regprocedure) || pg_get_functiondef('public.report_drill(text,jsonb)'::regprocedure) || pg_get_functiondef('public._rptb1_y_notes(text,date,date,integer[],jsonb)'::regprocedure)) = :'h'
  and (select count(*) from report_defs3 where key like 'y_\_%' or key in ('y1_daily_sellout', 'y2_festival_compare', 'y3_customer_items')) = 3 and (select count(*) from rules where key = 'report_top_customers_n') = 1);
select tt.chk('T6 read-only: nothing was posted, every journal entry balances', not exists (select 1 from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z));

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
