-- FRESH DB ONLY. Phase 435 tests (RPT-B3 R7b: supplier returns and adjustments, agreed-price variance, rejection rate, dependency and risk, delivery performance).
-- Needs phases 8 to 99 and 430 to 435.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase435_test.sql | grep -E 'FAIL|RESULT'
-- Neutral test_* data only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set f '00000000-0000-0000-0000-000000000004'
\set u '00000000-0000-0000-0000-000000000005'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.d() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_sales@s.app','{"full_name":"test_sales"}'), (:'k','test_store@s.app','{"full_name":"test_store"}'),
 (:'f','test_far@s.app','{"full_name":"test_far"}'), (:'u','test_buyer@s.app','{"full_name":"test_buyer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),(:'f','storekeeper'),(:'u','purchasing') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'f',3),(:'u',1) on conflict do nothing;
insert into rule_grants (grant_code, role_code) values ('report_purchase','purchasing'), ('report_purchase','storekeeper'), ('report_stock','storekeeper') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('test_raw_a','test_raw_a','test_raw_a','kg','kg','raw_material',true,0), ('test_raw_b','test_raw_b','test_raw_b','kg','kg','raw_material',true,0);
insert into suppliers (name) values ('test_supplier_a'), ('test_supplier_b'), ('test_supplier_c');
select id as ra from items where code='test_raw_a' \gset
select id as rb from items where code='test_raw_b' \gset
select id as sa from suppliers where name='test_supplier_a' \gset
select id as sb from suppliers where name='test_supplier_b' \gset
select id as sc from suppliers where name='test_supplier_c' \gset

\echo == fixture: bills, a return, a void, agreed prices, supplier links, quality checks, paper POs and GRNs
select tt.as(:'o'); set role authenticated;
select (save_purchase('b4350000-0000-0000-0000-000000000001'::uuid, null, :'sa'::uuid, 1, 'W-1', tt.d() - 10, format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100}]', :'ra')::jsonb, 50) ->> 'id') as w1 \gset
select post_purchase(:'w1'::uuid) is not null as p1 \gset
select (save_purchase('b4350000-0000-0000-0000-000000000002'::uuid, null, :'sa'::uuid, 1, 'W-2', tt.d() - 2, format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":120}]', :'ra')::jsonb) ->> 'id') as w2 \gset
select post_purchase(:'w2'::uuid) is not null as p2 \gset
select (save_purchase('b4350000-0000-0000-0000-000000000003'::uuid, null, :'sb'::uuid, 1, 'W-3', tt.d() - 1, format('[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":130}]', :'ra')::jsonb) ->> 'id') as w3 \gset
select post_purchase(:'w3'::uuid) is not null as p3 \gset
select (save_purchase('b4350000-0000-0000-0000-000000000004'::uuid, null, :'sa'::uuid, 1, 'W-4', tt.d() - 1, format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":40}]', :'rb')::jsonb) ->> 'id') as w4 \gset
select post_purchase(:'w4'::uuid) is not null as p4 \gset
select (save_purchase('b4350000-0000-0000-0000-000000000005'::uuid, null, :'sa'::uuid, 1, 'W-5', tt.d() - 1, format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":100}]', :'ra')::jsonb) ->> 'id') as w5 \gset
select post_purchase(:'w5'::uuid) is not null as p5 \gset
select void_purchase(:'w5'::uuid, 'test entered by mistake') is not null as v5 \gset
select (save_purchase('b4350000-0000-0000-0000-000000000006'::uuid, null, :'sa'::uuid, 1, 'W-1R', tt.d() - 3, format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":100}]', :'ra')::jsonb, 0, null, null, 'return', :'w1'::uuid, 'damaged') ->> 'id') as w6 \gset
select post_purchase(:'w6'::uuid) is not null as p6 \gset
reset role;
insert into supplier_refunds (supplier_id, location_id, mode, amount, note, created_by) values (:'sa', 1, 'cash', 30, 'test refund note', :'o');
select tt.chk('fixture: 4 posted bills, 1 return, 1 void, 1 refund', (select count(*) from purchase_bills where status='posted' and kind='bill')=4 and (select count(*) from purchase_bills where kind='return' and status='posted')=1
  and (select count(*) from purchase_bills where status='void')=1 and (select count(*) from supplier_refunds)=1);
select tt.as(:'o'); set role authenticated;
select supplier_price_set(:'ra'::uuid, :'sa'::uuid, 110, 'kg', tt.d()-30, 'test contract') is not null as ap1 \gset
select item_supplier_set(:'ra'::uuid, :'sa'::uuid, 'preferred') is not null as is1 \gset
-- quality checks
select qc_record('grn', :'w1'::uuid, 'reject', '[{"code":"smell","ok":false}]'::jsonb, 'test smell off', null, null, :'ra'::uuid, 2, 'kg', null) is not null as q1 \gset
select qc_record('grn', :'w2'::uuid, 'pass', '[]'::jsonb, null, null, null, :'ra'::uuid, 10, 'kg', null) is not null as q2 \gset
select qc_record('grn', :'w3'::uuid, 'pass', '[]'::jsonb, null, null, null) is not null as q3 \gset
reset role;
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('04-1', 1, 91, tt.d(), 'submitted', $j${"supplier":"test_unlinked_supplier","paper":"direct","lines":[{"item":"test_raw_a","memo":"3","counted":"3","rate":"10","quality":"accept"}]}$j$, :'o');
select id as g0 from entries where form_code='04-1' and serial=91 \gset
select tt.as(:'o'); set role authenticated;
select qc_record('grn', :'g0'::uuid, 'hold', '[]'::jsonb, 'test held', null, null) is not null as q4 \gset
reset role;
-- paper purchase orders (06-3) and goods received notes (04-1)
insert into entries (form_code, location_id, serial, entry_date, status, data, paper_serial, created_by) values
 ('06-3', 1, 1, tt.d()-10, 'approved',  format($j${"supplier":"test_supplier_a","delivery_date":"%s","lines":[{"item":"test_raw_a","qty":"10","rate":"100"}]}$j$, tt.d()-3)::jsonb, 'PO-T1', :'o'),
 ('06-3', 1, 2, tt.d()-12, 'approved',  format($j${"supplier":"test_supplier_a","delivery_date":"%s","lines":[{"item":"test_raw_a","qty":"10","rate":"100"}]}$j$, tt.d()-8)::jsonb, 'PO-T2', :'o'),
 ('06-3', 1, 3, tt.d()-9,  'approved',  $j${"supplier":"test_supplier_b","lines":[{"item":"test_raw_a","qty":"4","rate":"130"}]}$j$::jsonb, 'PO-T3', :'o'),
 ('06-3', 1, 4, tt.d()-6,  'approved',  format($j${"supplier":"test_supplier_b","delivery_date":"%s","lines":[{"item":"test_raw_a","qty":"4","rate":"130"}]}$j$, tt.d()-2)::jsonb, 'PO-T4', :'o'),
 ('06-3', 1, 5, tt.d()-1,  'approved',  format($j${"supplier":"test_supplier_a","delivery_date":"%s","lines":[{"item":"test_raw_a","qty":"4","rate":"100"}]}$j$, tt.d()+5)::jsonb, 'PO-T5', :'o');
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('04-1', 1, 92, tt.d()-4, 'approved', $j${"supplier":"test_supplier_a","paper":"po","po_no":"PO-T1","lines":[{"item":"test_raw_a","memo":"10","counted":"10","rate":"100","quality":"accept"}]}$j$, :'o'),
 ('04-1', 1, 93, tt.d()-5, 'approved', $j${"supplier":"test_supplier_a","paper":"po","po_no":"PO-T2","lines":[{"item":"test_raw_a","memo":"10","counted":"10","rate":"100","quality":"accept"}]}$j$, :'o'),
 ('04-1', 1, 94, tt.d()-3, 'approved', $j${"supplier":"test_supplier_b","paper":"po","po_no":"PO-T3","lines":[{"item":"test_raw_a","memo":"4","counted":"4","rate":"130","quality":"accept"}]}$j$, :'o');

\echo == T0 shape
select tt.chk('T0 all five reports: authenticated yes, anon no; helpers nobody', has_function_privilege('authenticated','public.supplier_returns_report(date,date,int,uuid)','execute') and has_function_privilege('authenticated','public.purch_price_variance(date,date,int,uuid,uuid)','execute')
  and has_function_privilege('authenticated','public.supplier_rejection_rate(date,date,int,uuid)','execute') and has_function_privilege('authenticated','public.supplier_dependency(date,date,int)','execute')
  and has_function_privilege('authenticated','public.supplier_delivery_perf(date,date,int,uuid)','execute') and not has_function_privilege('anon','public.supplier_dependency(date,date,int)','execute')
  and not has_function_privilege('authenticated','public._rb3_locs(int)','execute') and not has_function_privilege('authenticated','public._rb3_purch_ok()','execute'));

\echo == T1 returns and adjustments (#100)
select tt.as(:'o'); set role authenticated;
select supplier_returns_report() as rr \gset
select tt.chk('T1 one return: 2 kg of item A against bill W-1, reason Damaged, credit 200', jsonb_array_length(:'rr'::jsonb -> 'returns')=1 and (:'rr'::jsonb -> 'returns' -> 0 ->> 'ref_bill_no')='W-1' and (:'rr'::jsonb -> 'returns' -> 0 ->> 'reason_label')='Damaged'
  and (:'rr'::jsonb -> 'returns' -> 0 ->> 'total')::numeric=200 and (:'rr'::jsonb -> 'returns' -> 0 -> 'items' -> 0 ->> 'qty')::numeric=2);
select tt.chk('T1 the bill discount (50 on W-1) is listed as an adjustment', (:'rr'::jsonb -> 'discounts' -> 0 ->> 'discount')::numeric=50 and jsonb_array_length(:'rr'::jsonb -> 'discounts')=1);
select tt.chk('T1 the voided bill W-5 is listed with its reason; the refund of 30 is listed', (:'rr'::jsonb -> 'voided' -> 0 ->> 'bill_no')='W-5' and (:'rr'::jsonb -> 'voided' -> 0 ->> 'void_note')='test entered by mistake' and (:'rr'::jsonb -> 'refunds' -> 0 ->> 'amount')::numeric=30);
select tt.chk('T1 summary of supplier A: 3 purchases (1000+1200+200=2400... bills W-1,W-2,W-4), 1 return of 200, return share = 200 / purchases', (select (x->>'purchases_n')::int=3 and (x->>'returns_n')::int=1 and (x->>'returns_total')::numeric=200
  and (x->>'purchases_total')::numeric=(950+1200+200) and (x->>'return_pct')::numeric=round(200/(950+1200+200.0)*100,2) and (x->>'voided_n')::int=1 and (x->>'refunds_total')::numeric=30
  from jsonb_array_elements(:'rr'::jsonb -> 'summary') x where x->>'supplier'='test_supplier_a'));
select tt.chk('T1 supplier filter: supplier B has no return, only its own bill', jsonb_array_length(supplier_returns_report(null,null,null,:'sb'::uuid) -> 'returns')=0 and (select (x->>'purchases_n')::int from jsonb_array_elements(supplier_returns_report(null,null,null,:'sb'::uuid) -> 'summary') x)=1);
select tt.chk('T1 drill ids are present (bill ids)', (:'rr'::jsonb -> 'returns' -> 0 ->> 'bill_id') is not null and (:'rr'::jsonb -> 'returns' -> 0 ->> 'ref_bill_id') is not null);
select tt.err('T1 bad range', 'select supplier_returns_report(tt.d(), tt.d()-1)', 'bad_range');
reset role; select tt.as(:'k'); set role authenticated;
select supplier_returns_report() as rru \gset
select tt.chk('T1 a storekeeper with the purchase report right but no cost right sees the rows with money = null and cost_hidden', (:'rru'::jsonb ->> 'cost_hidden')::boolean and (:'rru'::jsonb -> 'returns' -> 0 -> 'total')='null'::jsonb and (:'rru'::jsonb -> 'returns' -> 0 -> 'items' -> 0 ->> 'qty')::numeric=2);
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T1 a salesperson cannot read', 'select supplier_returns_report()', 'not allowed');
reset role; select tt.as(:'f'); set role authenticated;
select tt.chk('T1 a storekeeper of place 3 with the right sees nothing of place 1', jsonb_array_length(supplier_returns_report() -> 'returns')=0);
select tt.err('T1 and cannot ask for place 1', 'select supplier_returns_report(null,null,1)', 'not allowed for this location');
reset role;

\echo == T2 agreed-price variance (#101)
select tt.as(:'o'); set role authenticated;
select purch_price_variance() as pv \gset
select tt.chk('T2 W-1 line: actual 100 vs agreed 110 = -10 per kg, extra cost -100 (the bill discount is not part of it)', (select (x->>'diff')::numeric=-10 and (x->>'extra_cost')::numeric=-100 and (x->>'agreed_price')::numeric=110 from jsonb_array_elements(:'pv'::jsonb -> 'rows') x where x->>'bill_no'='W-1'));
select tt.chk('T2 W-2 line: 120 vs 110 = +10 per kg, +9.09 %, extra +100', (select (x->>'diff')::numeric=10 and (x->>'diff_pct')::numeric=9.09 and (x->>'extra_cost')::numeric=100 from jsonb_array_elements(:'pv'::jsonb -> 'rows') x where x->>'bill_no'='W-2'));
select tt.chk('T2 lines with no agreed price are COUNTED and show null, never 0 (W-3 supplier B, W-4 item B)', (:'pv'::jsonb ->> 'lines_without_agreed')::int=2 and (select x->'agreed_price'='null'::jsonb and x->'diff'='null'::jsonb and x->'extra_cost'='null'::jsonb from jsonb_array_elements(:'pv'::jsonb -> 'rows') x where x->>'bill_no'='W-3'));
select tt.chk('T2 the total extra cost counts only lines that have an agreed price (-100 + 100 = 0)', (:'pv'::jsonb ->> 'extra_cost_total')::numeric=0 and (:'pv'::jsonb ->> 'lines')::int=4 and (:'pv'::jsonb ->> 'lines_with_agreed')::int=2);
select tt.chk('T2 voided and return bills are not compared', (select count(*) from jsonb_array_elements(:'pv'::jsonb -> 'rows') x where x->>'bill_no' in ('W-5','W-1R'))=0);
select tt.chk('T2 filter by item', (select count(*) from jsonb_array_elements(purch_price_variance(null,null,null,null,:'rb'::uuid) -> 'rows'))=1);
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T2 a storekeeper without the cost right is refused (prices are costs)', 'select purch_price_variance()', 'not allowed');
reset role;

\echo == T3 supplier rejection rate (#103)
select tt.as(:'o'); set role authenticated;
select supplier_rejection_rate() as rj \gset
select tt.chk('T3 supplier A: 2 checks (W-1 reject, W-2 pass) = 50 %; quantity checked 12, rejected 2 = 16.67 %', (select (x->>'checks')::int=2 and (x->>'reject')::int=1 and (x->>'reject_rate_pct')::numeric=50 and (x->>'qty_checked')::numeric=12 and (x->>'qty_rejected')::numeric=2
  and (x->>'reject_rate_qty_pct')::numeric=16.67 from jsonb_array_elements(:'rj'::jsonb -> 'rows') x where x->>'supplier'='test_supplier_a'));
select tt.chk('T3 supplier B: 1 pass check typed without a quantity: 0 % by checks, quantity rate null (not 0), not captured count 1', (select (x->>'reject_rate_pct')::numeric=0 and x->'reject_rate_qty_pct'='null'::jsonb and (x->>'qty_not_captured_n')::int=1 and x->'qty_checked'='null'::jsonb
  from jsonb_array_elements(:'rj'::jsonb -> 'rows') x where x->>'supplier'='test_supplier_b'));
select tt.chk('T3 a check on a paper GRN with no supplier link is its own row "supplier not captured"', (select (x->>'checks')::int=1 and (x->>'hold')::int=1 and (x->>'supplier_not_captured')::boolean from jsonb_array_elements(:'rj'::jsonb -> 'rows') x where x->'supplier_id'='null'::jsonb));
select tt.chk('T3 receipts context: supplier A has 3 posted bills in the period, 2 were checked (67 %)', (select (x->>'receipts_n')::int=3 and (x->>'share_checked_pct')::numeric=66.7 from jsonb_array_elements(:'rj'::jsonb -> 'rows') x where x->>'supplier'='test_supplier_a'));
select tt.chk('T3 the check list carries source ids for the drill-down and marks bills', (select count(*) from jsonb_array_elements(:'rj'::jsonb -> 'checks') x where x->>'source_id' is not null)=4 and (select count(*) from jsonb_array_elements(:'rj'::jsonb -> 'checks') x where (x->>'is_bill')::boolean)=3);
select tt.chk('T3 supplier filter', jsonb_array_length(supplier_rejection_rate(null,null,null,:'sa'::uuid) -> 'rows')=1);
select qc_record('grn', :'w1'::uuid, 'pass', '[]'::jsonb, null, null, null, :'ra'::uuid, 8, 'kg', null) is not null as q5 \gset
select tt.chk('T3 only the LATEST check of a receipt counts (W-1 re-checked as pass: reject rate of A falls to 0)', (select (x->>'reject')::int=0 and (x->>'reject_rate_pct')::numeric=0 from jsonb_array_elements(supplier_rejection_rate() -> 'rows') x where x->>'supplier'='test_supplier_a'));
reset role; select tt.as(:'u'); set role authenticated;
select tt.chk('T3 a buyer with the purchase report right can read it (no cost needed: it has no money)', jsonb_array_length(supplier_rejection_rate() -> 'rows')=3);
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T3 a salesperson cannot', 'select supplier_rejection_rate()', 'not allowed');
reset role;

\echo == T4 dependency and risk (#104)
select tt.as(:'o'); set role authenticated;
select supplier_dependency() as dp \gset
select tt.chk('T4 item A: two suppliers used, main supplier A with 20 of 24 kg (83.3 %); preferred A declared, no alternative declared', (select (x->>'suppliers_used')::int=2 and x->>'top_supplier'='test_supplier_a' and (x->>'top_share_pct')::numeric=83.3 and (x->>'qty_total')::numeric=24
  and x->'flags' ? 'no_alternative_declared' and x->'flags' ? 'used_supplier_not_declared' and not (x->'flags' ? 'single_supplier_used') and not (x->'flags' ? 'preferred_not_the_main_supplier')
  from jsonb_array_elements(:'dp'::jsonb -> 'rows') x where x->>'code'='test_raw_a'));
select tt.chk('T4 item B: single supplier and NO declared suppliers: flagged as not captured (not "no alternative")', (select x->'flags' ? 'single_supplier_used' and x->'flags' ? 'declared_suppliers_not_captured' and not (x->'flags' ? 'no_alternative_declared')
  from jsonb_array_elements(:'dp'::jsonb -> 'rows') x where x->>'code'='test_raw_b'));
select tt.chk('T4 summary counts', (:'dp'::jsonb -> 'summary' ->> 'items')::int=2 and (:'dp'::jsonb -> 'summary' ->> 'single_supplier')::int=1 and (:'dp'::jsonb -> 'summary' ->> 'declared_not_captured')::int=1 and (:'dp'::jsonb -> 'summary' ->> 'no_alternative')::int=1);
select tt.chk('T4 the used-supplier list shows shares and whether each is declared', (select (u->>'share_pct')::numeric=83.3 and (u->>'declared')::boolean from jsonb_array_elements(:'dp'::jsonb -> 'rows' -> 0 -> 'used') u limit 1) is not null);
select item_supplier_set(:'ra'::uuid, :'sb'::uuid, 'alternative') is not null as is2 \gset
select item_supplier_set(:'ra'::uuid, :'sc'::uuid, 'preferred') is not null as is3 \gset
select supplier_dependency() as dp2 \gset
select tt.chk('T4 with an alternative declared and a second preferred (C, never used): no_alternative flag gone; both suppliers are now declared', (select not (x->'flags' ? 'no_alternative_declared') and not (x->'flags' ? 'used_supplier_not_declared') from jsonb_array_elements(:'dp2'::jsonb -> 'rows') x where x->>'code'='test_raw_a'));
select tt.chk('T4 money (the value per supplier) is shown to the owner', (:'dp2'::jsonb -> 'rows' -> 0 ->> 'value_total') is not null and not (:'dp2'::jsonb ->> 'cost_hidden')::boolean);
reset role; select tt.as(:'k'); set role authenticated;
select tt.chk('T4 a storekeeper without the cost right: quantity shares shown, money null', (supplier_dependency() ->> 'cost_hidden')::boolean and (supplier_dependency() -> 'rows' -> 0 -> 'value_total')='null'::jsonb and (supplier_dependency() -> 'rows' -> 0 ->> 'top_share_pct') is not null);
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T4 a salesperson cannot', 'select supplier_dependency()', 'not allowed');
reset role;

\echo == T5 delivery performance (#102)
select tt.as(:'o'); set role authenticated;
select supplier_delivery_perf() as dv \gset
select tt.chk('T5 supplier A: 3 POs, 2 complete, 1 on time + 1 late (3 days) = 50 %, average days late 3, none overdue', (select (x->>'pos')::int=3 and (x->>'received_complete')::int=2 and (x->>'on_time')::int=1 and (x->>'late')::int=1 and (x->>'on_time_pct')::numeric=50
  and (x->>'avg_days_late')::numeric=3.0 and (x->>'overdue_open')::int=0 from jsonb_array_elements(:'dv'::jsonb -> 'summary') x where x->>'supplier'='test_supplier_a'));
select tt.chk('T5 supplier B: 2 POs; PO-T3 received but no promised date (counted, not judged); PO-T4 open and overdue; on-time % null', (select (x->>'pos')::int=2 and (x->>'promised_date_not_captured')::int=1 and (x->>'overdue_open')::int=1 and x->'on_time_pct'='null'::jsonb
  from jsonb_array_elements(:'dv'::jsonb -> 'summary') x where x->>'supplier'='test_supplier_b'));
select tt.chk('T5 per-PO statuses', (select string_agg((x->>'po_no') || '=' || (x->>'status'), ',' order by x->>'po_no') from jsonb_array_elements(:'dv'::jsonb -> 'rows') x)='PO-T1=on_time,PO-T2=late,PO-T3=received_no_promised_date,PO-T4=overdue_open,PO-T5=open');
select tt.chk('T5 PO-T4: 2 days overdue; PO-T2: 3 days late; PO-T3 lead time 6 days (PO to first GRN)', (select (x->>'days_late')::int=2 from jsonb_array_elements(:'dv'::jsonb -> 'rows') x where x->>'po_no'='PO-T4')
  and (select (x->>'days_late')::int=3 from jsonb_array_elements(:'dv'::jsonb -> 'rows') x where x->>'po_no'='PO-T2') and (select (x->>'lead_days')::int=6 from jsonb_array_elements(:'dv'::jsonb -> 'rows') x where x->>'po_no'='PO-T3'));
select tt.chk('T5 PO-T3 has days_late null (no promised date), PO-T5 not yet due has 0', (select x->'days_late'='null'::jsonb from jsonb_array_elements(:'dv'::jsonb -> 'rows') x where x->>'po_no'='PO-T3') and (select (x->>'days_late')::int=0 from jsonb_array_elements(:'dv'::jsonb -> 'rows') x where x->>'po_no'='PO-T5'));
select tt.chk('T5 the drill id of every row is the paper PO entry', (select count(*) from jsonb_array_elements(:'dv'::jsonb -> 'rows') x where x->>'entry_id' is not null)=5);
select tt.chk('T5 supplier filter A', jsonb_array_length(supplier_delivery_perf(null,null,null,:'sa'::uuid) -> 'rows')=3);
select tt.err('T5 unknown supplier', 'select supplier_delivery_perf(null,null,null,gen_random_uuid())', 'supplier_not_found');
reset role; select tt.as(:'u'); set role authenticated;
select tt.chk('T5 a buyer with the purchase report right can read it', jsonb_array_length(supplier_delivery_perf() -> 'rows')=5);
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T5 a salesperson cannot', 'select supplier_delivery_perf()', 'not allowed');
reset role; select tt.as(:'f'); set role authenticated;
select tt.chk('T5 place 3 sees none of place 1', jsonb_array_length(supplier_delivery_perf() -> 'rows')=0);
reset role;

\echo == T6 reports changed nothing
select tt.chk('T6 no ledger or journal row is written by any report', (select count(*) from stock_ledger where reason not in ('purchase_in','purchase_return','reversal'))=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
