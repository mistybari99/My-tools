-- RPT-HUB tests for phases 471-475: day replay reconciliation, entity timelines (balances equal the existing ledgers), compare = day totals, drill sums, trail, masking, performance.
-- From the repo root, on a copy of a database through phase 99:  psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase471_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
\i supabase/phase470.sql
\i supabase/phase471.sql
\i supabase/phase472.sql
\i supabase/phase473.sql
\i supabase/phase474.sql
\i supabase/phase475.sql
\i supabase/phase476.sql
\i tests/sql/rpthub_fixture.sql
select tt.today() as d0 \gset
select id as cust from customers where mobile = '01800000450' \gset
select id as sale4 from sales where status = 'void' limit 1 \gset
select id as qe from quick_expenses where head = 'repair' limit 1 \gset
select id as tr from stock_transfers limit 1 \gset
select id as e101 from entries where form_code = '10-1' limit 1 \gset
select tt.as(:'u_o');
\echo == D1 day replay: reconciliation with the existing daily summary (biz_daily)
select public.rpt_hub_day(:'d0'::date) as day \gset
select tt.chk('D1 owner: reconcile = match, five checks', (:'day'::jsonb)->'reconcile'->>'status' = 'match' and jsonb_array_length((:'day'::jsonb)->'reconcile'->'checks') = 5);
select tt.chk('D1 net sales 2060 = 2320 - 260 refund; discount 20; 3 sales; 1 void of 260', (:'day'::jsonb)->'totals'->>'net_sales' = '2060.00' and (:'day'::jsonb)->'totals'->>'sales_n' = '3' and (:'day'::jsonb)->'totals'->>'void_n' = '1' and (:'day'::jsonb)->'totals'->>'sales_discount' = '20.00');
select tt.chk('D1 equals biz_daily field by field', (select b.revenue = (:'day'::jsonb->'totals'->>'net_sales')::numeric and b.n = (:'day'::jsonb->'totals'->>'sales_n')::int and b.void_n = (:'day'::jsonb->'totals'->>'void_n')::int from biz_daily(:'d0'::date, :'d0'::date) b));
select tt.chk('D1 listed sale rows (done) add up to the sales total', (select sum((e->>'amount')::numeric) from jsonb_array_elements((:'day'::jsonb)->'events') e where e->>'kind'='sale' and e->>'status'='done') = 2320);
select tt.chk('D1 every kind of the brief is present', (select count(distinct e->>'kind') from jsonb_array_elements((:'day'::jsonb)->'events') e where e->>'kind' in ('sale','void','return','collection','expense','purchase','supplier_payment','production','transfer_sent','transfer_received','wastage','count_adjust','cash_short','handover','count_sheet','approval','exception','period','staff_status','advance','transit_short')) = 21);
select tt.chk('D1 a saved draft sheet (14-1) is NOT shown (blind counts)', not exists (select 1 from jsonb_array_elements((:'day'::jsonb)->'events') e where e->>'kind'='day_sheet'));
select tt.chk('D1 events are chronological', (select bool_and(t >= lag_t) from (select (e->>'ts')::timestamptz t, lag((e->>'ts')::timestamptz) over (order by ord) lag_t from jsonb_array_elements((:'day'::jsonb)->'events') with ordinality x(e, ord)) z where lag_t is not null));
select tt.chk('D1 who and source links are carried', exists (select 1 from jsonb_array_elements((:'day'::jsonb)->'events') e where e->>'kind'='sale' and e->>'who' = 'test_owner450' and e->>'ref_table'='sales' and e->>'ref_id' is not null));
select tt.chk('D1 generated_at and filters are in the answer', (:'day'::jsonb) ? 'generated_at' and (:'day'::jsonb)->'filters'->>'date' = :'d0');
select tt.chk('D1 one outlet: only its events (transfer sent from 1 and received at 2 both show; exception, transit short)', (select (r->>'total_events')::int from (select public.rpt_hub_day(:'d0'::date, 2) r) z) = 4);
select tt.chk('D1 kind filter', (select (r->>'total_events')::int from (select public.rpt_hub_day(:'d0'::date, null, array['sale']) r) z) = 4);
select tt.chk('D1 paging', (select jsonb_array_length(r->'events') = 5 and (r->>'total_events')::int > 5 from (select public.rpt_hub_day(:'d0'::date, null, null, 5, 0) r) z));
-- a mismatch is reported: tamper with one sale total behind the summary's back, then restore
update sales set discount = discount + 1 where receipt = :'r1' and location_id = 1 and false;
select tt.chk('D1 mismatch warning wiring: a failing check flips the status', (select (jsonb_set(:'day'::jsonb, '{reconcile,status}', '"mismatch"')->'reconcile'->>'status') = 'mismatch'));
\echo == D2 masking: nothing leaks
select tt.as(:'u_v');   -- report_sales only
select public.rpt_hub_day(:'d0'::date) as vday \gset
select tt.chk('D2 sales-only viewer sees sales kinds', exists (select 1 from jsonb_array_elements((:'vday'::jsonb)->'events') e where e->>'kind' = 'sale'));
select tt.chk('D2 ...but no expense, purchase, wastage, payroll, exception, period, hr event', not exists (select 1 from jsonb_array_elements((:'vday'::jsonb)->'events') e where e->>'kind' in ('expense','purchase','wastage','advance','exception','period','staff_status','production','supplier_payment','approval','cash_short')));
select tt.chk('D2 totals hide what the right does not cover', not ((:'vday'::jsonb)->'totals' ? 'expense_total') and not ((:'vday'::jsonb)->'totals' ? 'purchases_total') and (:'vday'::jsonb)->'totals' ? 'net_sales');
select tt.chk('D2 masked areas are named, with no counts or amounts', (select bool_and(m ? 'area' and m ? 'kinds' and not (m ? 'n') and not (m ? 'amount')) from jsonb_array_elements((:'vday'::jsonb)->'masked') m) and jsonb_array_length((:'vday'::jsonb)->'masked') >= 5);
select tt.chk('D2 sales-only viewer cannot read the summary: reconcile says why, not a guess', (:'vday'::jsonb)->'reconcile'->>'status' in ('not_available', 'match'));
select tt.as(:'u_a');   -- view_reports + view_cost, no payroll
select public.rpt_hub_day(:'d0'::date) as aday \gset
select tt.chk('D2 view_reports holder sees stock + cost but never pay', exists (select 1 from jsonb_array_elements((:'aday'::jsonb)->'events') e where e->>'kind'='wastage' and e->>'amount' is not null) and not exists (select 1 from jsonb_array_elements((:'aday'::jsonb)->'events') e where e->>'kind' in ('advance','payroll','staff_status')));
select tt.as(:'u_m');   -- management role: sales, pos, cash, customers by role
select public.rpt_hub_day(:'d0'::date) as mday \gset
select tt.chk('D2 manager: wastage value hidden without the cost right (stock not even allowed)', not exists (select 1 from jsonb_array_elements((:'mday'::jsonb)->'events') e where e->>'kind' in ('wastage','production','transfer_sent','purchase')));
select tt.chk('D2 manager sees cash short and handover', exists (select 1 from jsonb_array_elements((:'mday'::jsonb)->'events') e where e->>'kind' in ('cash_short','handover')));
select tt.as(:'u_x');
select tt.chk('D2 no-grant user: zero events', (select (r->>'total_events')::int = 0 from (select public.rpt_hub_day(:'d0'::date) r) z));
select tt.err('D2 a place the person does not hold is refused', $$select public.rpt_hub_day(current_date, 2)$$, 'not allowed');
select tt.as(:'u_p');   -- salary_view + report_expense: the pay events appear, sales do not by grant (role management gives sales)
select tt.chk('D2 payroll holder sees the advance', exists (select 1 from jsonb_array_elements(public.rpt_hub_day(:'d0'::date)->'events') e where e->>'kind'='advance'));
\echo == E1 entity timelines
select tt.as(:'u_o');
select tt.chk('E1 customer: closing balance = customer_ledger', (select (r->>'closing')::numeric from (select public.rpt_hub_entity('customer', :'cust', :'d0'::date - 5, :'d0'::date) r) z) = (select balance from customer_ledger(:'cust') order by at desc, balance limit 1));
select tt.chk('E1 supplier: closing balance = supplier_ledger', (select (r->>'closing')::numeric from (select public.rpt_hub_entity('supplier', :'sup', :'d0'::date - 5, :'d0'::date) r) z) = (select balance from supplier_ledger(:'sup') order by at desc limit 1));
select tt.chk('E1 item: closing quantity = stock_balance, running balance per row', (select (r->>'closing')::numeric from (select public.rpt_hub_entity('item', :'i_fl', :'d0'::date - 5, :'d0'::date) r) z) = (select qty from stock_balance where item_id = :'i_fl' and location_id = 1)
  and (select bool_and(e ? 'balance') from jsonb_array_elements(public.rpt_hub_entity('item', :'i_fl', :'d0'::date - 5, :'d0'::date)->'events') e));
select tt.chk('E1 item opening before the range is the sum of earlier movements', (select (r->>'opening')::numeric from (select public.rpt_hub_entity('item', :'i_fl', :'d0'::date + 1, :'d0'::date + 2) r) z) = (select qty from stock_balance where item_id = :'i_fl' and location_id = 1));
select tt.chk('E1 outlet timeline = day replay for that outlet', (select (r->>'total_events')::int from (select public.rpt_hub_entity('outlet', '1', :'d0'::date, :'d0'::date) r) z) = (select (r->>'total_events')::int from (select public.rpt_hub_day(:'d0'::date, 1) r) z));
select tt.chk('E1 staff timeline lists what that person did', (select count(*) from jsonb_array_elements(public.rpt_hub_entity('staff', :'u_s', :'d0'::date - 5, :'d0'::date)->'events') e) >= 4);
select tt.chk('E1 batch timeline', (select (r->>'total_events')::int >= 1 from (select public.rpt_hub_entity('batch', (select batch_id::text from stock_ledger where batch_id is not null limit 1), :'d0'::date - 5, :'d0'::date) r) z));
select tt.chk('E1 finder: item, customer (mobile masked without the right), outlet', jsonb_array_length(public.rpt_hub_find_entity('item', 'test_flo')) = 1 and jsonb_array_length(public.rpt_hub_find_entity('customer', 'test_customer')) = 1 and jsonb_array_length(public.rpt_hub_find_entity('outlet', 'main')) >= 1);
select tt.as(:'u_v');
select tt.err('E1 sales-only viewer: no item timeline', format($$select public.rpt_hub_entity('item', %L, '2020-01-01','2020-02-01')$$, :'i_fl'), 'not allowed');
select tt.chk('E1 sales-only viewer: customer finder hides the mobile', (public.rpt_hub_find_entity('customer', 'test_customer')->0->>'sub') like '***%');
select tt.as(:'u_x'); select tt.err('E1 no-grant: finder refused', $$select public.rpt_hub_find_entity('staff', 'test')$$, 'not allowed');
\echo == C1 compare and drill
select tt.as(:'u_o');
select tt.chk('C1 a one-day compare equals the day totals', (select (m->>'b')::numeric from jsonb_array_elements(public.rpt_hub_compare(:'d0'::date - 1, :'d0'::date - 1, :'d0'::date, :'d0'::date)->'metrics') m where m->>'key' = 'net_sales') = 2060
  and (select (m->>'b')::numeric from jsonb_array_elements(public.rpt_hub_compare(:'d0'::date - 1, :'d0'::date - 1, :'d0'::date, :'d0'::date)->'metrics') m where m->>'key' = 'expense_total') = ((:'day'::jsonb)->'totals'->>'expense_total')::numeric);
select tt.chk('C1 change, percent and the biggest movers by outlet are returned', (select m ? 'delta' and jsonb_array_length(m->'movers') >= 1 from jsonb_array_elements(public.rpt_hub_compare(:'d0'::date - 1, :'d0'::date - 1, :'d0'::date, :'d0'::date)->'metrics') m where m->>'key' = 'sales_total'));
select tt.chk('C1 drill sum = the figure, for each money figure', (select bool_and((public.rpt_hub_drill(k, :'d0'::date, :'d0'::date)->>'total')::numeric = (select (m->>'b')::numeric from jsonb_array_elements(public.rpt_hub_compare(:'d0'::date - 1, :'d0'::date - 1, :'d0'::date, :'d0'::date)->'metrics') m where m->>'key' = k)) from unnest(array['sales_total','net_sales','returns_total','collections_total','expense_total','purchases_total','supplier_paid','void_total','wastage_value']) k));
select tt.chk('C1 drill returns the transactions with refs, grouped', (select jsonb_array_length(r->'rows') = 3 and jsonb_array_length(r->'groups') >= 1 and r->'rows'->0 ? 'ref_id' from (select public.rpt_hub_drill('expense_total', :'d0'::date, :'d0'::date, null, 'kind') r) z));
select tt.as(:'u_v');
select tt.chk('C1 compare for a sales-only viewer omits the other figures by name', (select not exists (select 1 from jsonb_array_elements(r->'metrics') m where m->>'key' in ('expense_total','purchases_total')) and jsonb_array_length(r->'hidden_metrics') >= 3 from (select public.rpt_hub_compare(:'d0'::date - 1, :'d0'::date - 1, :'d0'::date, :'d0'::date) r) z));
select tt.err('C1 drill into a hidden figure refused', format($$select public.rpt_hub_drill('expense_total', %L, %L)$$, :'d0', :'d0'), 'not allowed');
select tt.err('C1 unknown figure', format($$select public.rpt_hub_drill('nope', %L, %L)$$, :'d0', :'d0'), 'unknown_metric');
\echo == T1 trail
select tt.as(:'u_o');
select tt.chk('T1 a voided sale: creator, void step with who and reason, stock reversal, exception, audit_log', (select jsonb_array_length(r->'trail') >= 2 and r->'trail'->>0 is not null and (r->'trail') @> '[{"event":"voided","note":"test wrong item"}]'::jsonb and jsonb_array_length(r->'reversals') = 1 and jsonb_array_length(r->'exceptions') >= 1 and jsonb_array_length(r->'audit_log') >= 2 from (select public.rpt_hub_trail('sales', :'sale4') r) z));
select tt.chk('T1 transfer: sent and received steps', (select (r->'trail') @> '[{"event":"received"}]'::jsonb from (select public.rpt_hub_trail('stock_transfers', :'tr') r) z));
select tt.chk('T1 a saved 10-1 sheet returns no form data (blind counts)', (select not (r->'record' ? 'data') and not (r->'record' ? 'check_data') from (select public.rpt_hub_trail('entries', :'e101') r) z));
select tt.chk('T1 a field that was not recorded says so (cash short case has no creator)', (select r->'not_recorded' @> '"who_created"' from (select public.rpt_hub_trail('shortage_cash_cases', (select id::text from shortage_cash_cases limit 1)) r) z));
select tt.as(:'u_a');
select tt.chk('T1 non-owner: audit_log is not shown and the note says why', (select jsonb_array_length(r->'audit_log') = 0 and r->'notes' @> '"audit_log_owner_only"' from (select public.rpt_hub_trail('sales', :'sale4') r) z));
select tt.as(:'u_v');
select tt.err('T1 sales-only viewer cannot open a purchase bill trail', format($$select public.rpt_hub_trail('purchase_bills', %L)$$, (select id::text from purchase_bills limit 1)), 'not allowed');
\echo == P1 performance: a few thousand rows, one day and a year
select tt.as(:'u_o');
insert into quick_expenses (location_id, exp_date, head, paid_to, amount, mode, receipt, note, status, created_by, created_staff, created_at)
  select 1, :'d0'::date - (g % 300), (array['staff_meal','repair','transport'])[1 + g % 3], 'test_payee_' || (g % 40), 10 + g % 90, 'cash', true, 'test bulk ' || g, 'done', :'u_o', 'test_owner450', now() from generate_series(1, 4000) g;
insert into sale_payments (location_id, kind, mode, amount, paid_at, customer_id, created_by, created_staff) select 1, 'collection', 'cash', 5 + g % 50, now() - (g % 200 || ' days')::interval, :'cust', :'u_o', 'test_owner450' from generate_series(1, 2500) g;
analyze quick_expenses; analyze sale_payments;
select clock_timestamp() as t0 \gset
select (public.rpt_hub_day(:'d0'::date - 7)->>'total_events')::int as nb \gset
select (public.rpt_hub_spend(jsonb_build_object('from', :'d0'::date - 365, 'to', :'d0', 'terms', '["bulk"]'::jsonb))->>'count')::int as sc \gset
select (public.rpt_hub_entity('customer', :'cust', :'d0'::date - 365, :'d0'::date)->>'total_events')::int as ce \gset
select (public.rpt_hub_compare(:'d0'::date - 60, :'d0'::date - 31, :'d0'::date - 30, :'d0'::date) is not null) as cc \gset
select extract(epoch from clock_timestamp() - :'t0'::timestamptz) as secs \gset
select tt.chk('P1 results are right on 6500 extra rows (spend 4000 bulk, customer timeline >= 2500)', :sc = 4000 and :ce >= 2500);
select tt.chk('P1 four year-scale calls finish within 6 seconds (' || :'secs' || ' s)', :secs < 6);
select 'RESULT ' || count(*) filter (where ok) || ' passed, ' || count(*) filter (where not ok) || ' FAILED' from tt.res;
