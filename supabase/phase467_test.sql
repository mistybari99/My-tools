-- FRESH DB ONLY. Phase 467 tests (RPT-C3 R9 part 3): #189 upcoming supplier payments, #188 expected cash in / out calendar, #190 expected wastage and expiry risk.
--   bash tests/sql/rptc3_run.sh 467
-- Test data only (test_* names). History from tests/sql/rptc3_history.sql (17 FG units sold over a 21-day effective window).
\ir ../tests/sql/rptc3_head.sql
\ir ../tests/sql/rptc3_history.sql
select tt.as(:'u_o');
insert into user_grants (user_id, grant_code, location_id) values (:'u_rm', 'report_cash', null), (:'u_ex', 'report_stock', null) on conflict do nothing;
select id as fg from items where code = 'W1D-FG' \gset
select id as cs from items where code = 'W1D-CS' \gset

-- suppliers: w1d supplier has a 400 bill dated today; give it 7 credit days. A second supplier (3 days) with a 600 bill 5 days ago; a third with no credit days (100).
update suppliers set credit_days = 7 where name = 'test_supplier_w1d';
insert into suppliers (name, credit_days) values ('test_supplier_c3b', 3), ('test_supplier_c3c', null);
select id as sb from suppliers where name = 'test_supplier_c3b' \gset
select id as sc from suppliers where name = 'test_supplier_c3c' \gset
select post_purchase((save_purchase(gen_random_uuid(), null, :'sb'::uuid, 1, 'C3-B2', tt.today()-5, format('[{"item_id":"%s","qty":4,"unit_cost":150}]', :'cs')::jsonb, 0)->>'id')::uuid) is not null as p1 \gset
select post_purchase((save_purchase(gen_random_uuid(), null, :'sc'::uuid, 1, 'C3-B3', tt.today(), format('[{"item_id":"%s","qty":1,"unit_cost":100}]', :'cs')::jsonb, 0)->>'id')::uuid) is not null as p2 \gset

-- T1 supplier payments (#189)
select fc_supplier_payments(30) as sp \gset
select tt.chk('T1 the 600 bill of 5 days ago with 3 credit days is overdue by 2 days', (select x->>'status' = 'overdue' and tt.n(x,'days_overdue') = 2 and tt.n(x,'open_amount') = 600 and (x->>'due_date')::date = tt.today()-2 from jsonb_array_elements((:'sp'::jsonb)->'rows') x where x->>'bill_no' = 'C3-B2'));
select tt.chk('T1 the 400 bill from today with 7 credit days falls due in 7 days', (select x->>'status' = 'due' and (x->>'due_date')::date = tt.today()+7 from jsonb_array_elements((:'sp'::jsonb)->'rows') x where x->>'bill_no' = 'W1D-B1'));
select tt.chk('T1 a supplier with no credit days has NO due date and is not placed on the calendar', (select x->>'status' = 'date_unknown' and x->>'due_date' is null from jsonb_array_elements((:'sp'::jsonb)->'rows') x where x->>'bill_no' = 'C3-B3'));
select tt.chk('T1 totals: overdue 600, due 400, unknown 100, all open 1100', tt.n((:'sp'::jsonb)->'totals','overdue') = 600 and tt.n((:'sp'::jsonb)->'totals','due_in_horizon') = 400 and tt.n((:'sp'::jsonb)->'totals','date_unknown') = 100 and tt.n((:'sp'::jsonb)->'totals','all_open') = 1100);
select tt.chk('T1 coverage: 2 of 3 bills have a date (66.7%), one supplier lacks credit days', tt.n((:'sp'::jsonb)->'coverage','dated_pct') = 66.7 and tt.n((:'sp'::jsonb)->'coverage','suppliers_without_credit_days') = 1);
select tt.chk('T1 a shorter horizon moves the 400 bill to "later"', (select x->>'status' = 'later' from jsonb_array_elements(fc_supplier_payments(5)->'rows') x where x->>'bill_no' = 'W1D-B1'));
select pay_supplier(:'sb'::uuid, 1, '[{"mode":"cash","amount":250}]'::jsonb, gen_random_uuid(), 'test part pay') is not null as pp \gset
select tt.chk('T1 a payment is taken off: the 600 bill now owes 350', (select tt.n(x,'open_amount') = 350 from jsonb_array_elements(fc_supplier_payments(30)->'rows') x where x->>'bill_no' = 'C3-B2'));
select tt.err('T1 days are required', $$select fc_supplier_payments(null)$$, 'bad_range');

-- T2 cash calendar (#188)
insert into online_orders (location_id, customer_name, customer_mobile, lines, subtotal, status, created_by, order_no, channel, delivery_mode, delivery_date, advance, advance_mode)
  values (1, 'test_c1', '01800000701', '[{"qty":4,"price":100,"amount":400}]', 400, 'confirmed', :'u_o'::uuid, 99201, 'phone', 'pickup', tt.today()+1, 100, 'cash'),
         (1, 'test_c2', '01800000702', '[{"qty":2,"price":100,"amount":200}]', 200, 'new', :'u_o'::uuid, 99202, 'phone', 'pickup', tt.today()-2, 0, null),
         (1, 'test_c3', '01800000703', '[{"qty":2,"price":100,"amount":200}]', 200, 'delivered', :'u_o'::uuid, 99203, 'phone', 'pickup', tt.today()+1, 0, null);
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":2,"price":100}]',:'fg')::jsonb,0,'[]'::jsonb,'01800000778','test_customer_c3b','retail',null,false)->>'id' as cr \gset
select fc_cash_calendar(30) as cc \gset
select tt.chk('T2 the order balance (400 - 100 advance) is money in tomorrow; the delivered order is not counted', (select tt.n(i,'amount') = 300 from jsonb_array_elements((:'cc'::jsonb)->'rows') r, jsonb_array_elements(r->'items') i where (r->>'date')::date = tt.today()+1 and i->>'kind' = 'order_balance'));
select tt.chk('T2 the open order that was due 2 days ago is overdue, not on a future day: 200', tt.n((:'cc'::jsonb)->'buckets','overdue_in') = 200);
select tt.chk('T2 the supplier bill falls on its due date (400 on day +7); the overdue 350 is in the overdue bucket', (select tt.n(r,'out') = 400 from jsonb_array_elements((:'cc'::jsonb)->'rows') r where (r->>'date')::date = tt.today()+7) and tt.n((:'cc'::jsonb)->'buckets','overdue_out') = 350);
select tt.chk('T2 customer dues have no credit days yet: 200 stays "date unknown", and the page says why', tt.n((:'cc'::jsonb)->'buckets','date_unknown_in') = 200 and (:'cc'::jsonb)->'notes' ? 'customers_have_no_credit_days_so_dues_are_undated' and (:'cc'::jsonb)->'coverage'->>'customer_credit_days_column' = 'false');
select tt.chk('T2 the unknown supplier date (100) is also kept off the calendar', tt.n((:'cc'::jsonb)->'buckets','date_unknown_out') = 100);
select tt.chk('T2 totals inside the horizon: in 300, out 400', tt.n((:'cc'::jsonb)->'totals','in') = 300 and tt.n((:'cc'::jsonb)->'totals','out') = 400);
select tt.chk('T2 the notes say what is NOT included', (:'cc'::jsonb)->'notes' @> '["only_known_future_money","no_opening_balance_no_forecast_sales_no_tax"]'::jsonb);
-- a customers.credit_days column (added by another package) is used when present
alter table customers add column if not exists credit_days int;
update customers set credit_days = 10 where mobile = '01800000778';
select tt.chk('T2 with credit days on the customer the 200 due moves to day +10', (select tt.n(i,'amount') = 200 from jsonb_array_elements(fc_cash_calendar(30)->'rows') r, jsonb_array_elements(r->'items') i where (r->>'date')::date = tt.today()+10 and i->>'kind' = 'customer_due') and tt.n(fc_cash_calendar(30)->'buckets','date_unknown_in') = 0);
-- salary: an approved run with unpaid lines, and recurring transfers with a bank fee
insert into employees (full_name_bn) values ('test_emp_c3');
insert into payroll_runs (month, location_id, status, created_by) values (date_trunc('month', tt.today())::date, 1, 'approved', :'u_o'::uuid);
select id as run from payroll_runs order by id desc limit 1 \gset
insert into payroll_lines (run_id, month, employee_id, location_id, name, net, payment_status, paid_amount, active) select :'run'::bigint, date_trunc('month', tt.today())::date, id, 1, 'test_emp_c3', 5000, 'unpaid', 0, true from employees where full_name_bn = 'test_emp_c3';
select tt.chk('T2 approved unpaid payroll (5000) is owed: pay day not set, so it is "date unknown" out', (select sum((i->>'amount')::numeric) = 5000 from jsonb_array_elements(fc_cash_calendar(30)->'rows') r, jsonb_array_elements(r->'items') i where i->>'kind' = 'salary_owed') is not true
  and tt.n(fc_cash_calendar(30)->'buckets','date_unknown_out') = 5100);
select set_rule('fc_payroll_day', to_jsonb(extract(day from tt.today() + 3)::int)) is null as pd \gset
select tt.chk('T2 once the pay day is set the owed salary sits on that day', exists (select 1 from jsonb_array_elements(fc_cash_calendar(30)->'rows') r, jsonb_array_elements(r->'items') i where i->>'kind' = 'salary_owed' and tt.n(i,'amount') = 5000));
update payroll_lines set payment_status = 'paid', paid_amount = 5000 where run_id = :'run'::bigint;
update payroll_runs set status = 'paid' where id = :'run'::bigint;
select tt.chk('T2 when the run is fully paid, the next pay day repeats the last run - marked as an assumption', exists (select 1 from jsonb_array_elements(fc_cash_calendar(30)->'rows') r, jsonb_array_elements(r->'items') i where i->>'kind' = 'salary_assumed' and tt.n(i,'amount') = 5000 and (i->>'assumed') = 'true') and jsonb_array_length(fc_cash_calendar(30)->'assumptions') = 1);
select code as bankcode from coa_accounts where code = '1120' \gset
insert into money_accounts (code, kind, name_bn, name_en, coa_account_id) select 'TEST-A1', 'bank', 'test_a1', 'test_a1', id from coa_accounts where code = '1120';
insert into money_accounts (code, kind, name_bn, name_en, coa_account_id) select 'TEST-A2', 'cash', 'test_a2', 'test_a2', id from coa_accounts where code = '1110';
insert into money_recurring (name, from_account, to_account, amount, fee, day_of_month, start_date, active)
  select 'test_recurring', (select id from money_accounts where code = 'TEST-A1'), (select id from money_accounts where code = 'TEST-A2'), 1000, 10, extract(day from tt.today() + 2)::int, tt.today() - 60, true;
select tt.chk('T2 a recurring transfer is listed apart (1000, not in the net) and only its bank fee (10) is money out', exists (select 1 from jsonb_array_elements(fc_cash_calendar(30)->'rows') r where tt.n(r,'transfers') = 1000) and exists (select 1 from jsonb_array_elements(fc_cash_calendar(30)->'rows') r, jsonb_array_elements(r->'items') i where i->>'kind' = 'transfer_fee' and tt.n(i,'amount') = 10));
-- salary lines are hidden from a reader without salary_view
select tt.as(:'u_rm');
select tt.chk('T2 a cash reader without salary_view sees no salary line and is told', not exists (select 1 from jsonb_array_elements(fc_cash_calendar(30)->'rows') r, jsonb_array_elements(r->'items') i where i->>'kind' like 'salary%') and fc_cash_calendar(30)->'notes' ? 'salary_hidden');
select tt.as(:'u_nb');
select tt.err('T2 nobody: calendar', $$select fc_cash_calendar(30)$$, 'not allowed');
select tt.err('T2 nobody: supplier payments', $$select fc_supplier_payments(30)$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T2 days are required', $$select fc_cash_calendar(0)$$, 'bad_range');

-- T3 expiry and wastage risk (#190)
update stock_batches set qty_remaining = 0;
insert into stock_batches (item_id, location_id, made_at, qty_made, qty_remaining, expires_at, batch_no) values
 (:'fg'::uuid, 1, now(), 4, 4, now() + interval '2 days', 'TEST-EXP-A'), (:'fg'::uuid, 1, now(), 10, 10, now() + interval '5 days', 'TEST-EXP-B'),
 (:'fg'::uuid, 1, now() - interval '3 days', 3, 3, now() - interval '1 day', 'TEST-EXP-C'), (:'fg'::uuid, 1, now(), 7, 7, now() + interval '60 days', 'TEST-EXP-D'), (:'fg'::uuid, 1, now(), 2, 2, null, 'TEST-EXP-N');
select fc_expiry_risk(1, 10, 28) as ex \gset
select tt.chk('T3 batch A (4 units, 2 days): about 1.619 sold before it expires, 2.381 at risk, value 33.33 at cost 14', (select tt.n(x,'expected_sold_before_expiry') = 1.619 and tt.n(x,'at_risk_qty') = 2.381 and tt.n(x,'at_risk_value') = 33.33 and tt.n(x,'avg_sold_per_day') = 0.8095 from jsonb_array_elements((:'ex'::jsonb)->'rows') x where x->>'batch_no' = 'TEST-EXP-A'));
select tt.chk('T3 batch B (10 units, 5 days) comes second in first-expiring-first-out: only 0.048 of it is sold before it expires', (select tt.n(x,'expected_sold_before_expiry') = 0.048 and tt.n(x,'at_risk_qty') = 9.952 from jsonb_array_elements((:'ex'::jsonb)->'rows') x where x->>'batch_no' = 'TEST-EXP-B'));
select tt.chk('T3 a batch expiring after the horizon (60 days) is not listed', not exists (select 1 from jsonb_array_elements((:'ex'::jsonb)->'rows') x where x->>'batch_no' = 'TEST-EXP-D'));
select tt.chk('T3 stock already expired is listed apart', exists (select 1 from jsonb_array_elements((:'ex'::jsonb)->'already_expired') x where x->>'batch_no' = 'TEST-EXP-C') and not exists (select 1 from jsonb_array_elements((:'ex'::jsonb)->'rows') x where x->>'batch_no' = 'TEST-EXP-C'));
select tt.chk('T3 a batch with no expiry date is counted as not covered, never guessed', tt.n((:'ex'::jsonb)->'assumptions','batches_without_expiry_not_covered') = 1);
select tt.chk('T3 the assumptions state the order of use and that no restock is modelled', (:'ex'::jsonb)->'assumptions'->>'order_of_use' = 'first expiring batch first' and (:'ex'::jsonb)->'notes' ? 'no_restock_or_price_cut_modelled');
select tt.chk('T3 days not typed and not set: data needed (nothing assumed)', fc_expiry_risk(1, null, 28)->'data_needed' ? 'report_expiry_soon_days');
select set_rule('report_expiry_soon_days', '10') is null as rs \gset
select tt.chk('T3 the existing setting report_expiry_soon_days supplies the days', fc_expiry_risk(1, null, 28)->>'days' = '10');
select tt.as(:'u_ex');
select tt.chk('T3 a stock reader without the cost right gets no value and is told', (select x->>'at_risk_value' is null from jsonb_array_elements(fc_expiry_risk(1, 10, 28)->'rows') x where x->>'batch_no' = 'TEST-EXP-A') and fc_expiry_risk(1, 10, 28)->'notes' ? 'cost_hidden');
select tt.as(:'u_nb');
select tt.err('T3 nobody', $$select fc_expiry_risk(1, 10, 28)$$, 'not allowed');
select tt.as(:'u_o');
\i supabase/phase467.sql
select tt.chk('T4 paste twice: still answers, books balanced', tt.n(fc_supplier_payments(30)->'totals','all_open') = 850 and tt.unbalanced() = 0);
\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select name from tt.res where not ok;
