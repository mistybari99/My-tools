-- FRESH DB ONLY. Phase 26 (13 reports on report engine 3) tests.
--   ORDER="phase8 ... phase24 phase26" bash tests/sql/build_fresh_db.sh <db> ; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase26_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set r '00000000-0000-0000-0000-000000000003'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
-- first row of a report answer whose key k has the text value v (and, optionally, key k2 = v2)
create or replace function tt.row(j jsonb, k text, v text, k2 text default null, v2 text default null) returns jsonb language sql as $$
  select x from jsonb_array_elements(j -> 'rows') x where x ->> k = v and (k2 is null or x ->> k2 = v2) limit 1 $$;
create or replace function tt.n(j jsonb) returns int language sql as $$ select jsonb_array_length(j -> 'rows') $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'r','rep3@s.app','{"full_name":"Reporter"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'r','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'r',1),(:'r',2) on conflict do nothing;

-- ================= seed (postgres role) =================
insert into items (code, name_bn, unit, category) values ('T-1','চিনি','kg','raw'), ('T-2','রসগোল্লা','kg','sweet'), ('T-3','ময়দা','kg','raw');
insert into suppliers (name) values ('Sup A'), ('Sup B');
-- posted purchase bills with lines (Sup A, location 1)
insert into purchase_bills (supplier_id, kind, bill_no, bill_date, location_id, status, subtotal, total, created_by)
 select id, 'bill', 'B1', date '2026-09-02', 1, 'posted', 1000, 1000, :'o' from suppliers where name = 'Sup A';
insert into purchase_bills (supplier_id, kind, bill_no, bill_date, location_id, status, subtotal, total, created_by)
 select id, 'bill', 'B2', date '2026-09-20', 1, 'posted', 1200, 1200, :'o' from suppliers where name = 'Sup A';
insert into purchase_bills (supplier_id, kind, bill_no, bill_date, location_id, status, subtotal, total, created_by)
 select id, 'bill', 'B3', date '2026-09-12', 1, 'posted', 8750, 8750, :'o' from suppliers where name = 'Sup A';
insert into purchase_bills (supplier_id, kind, bill_no, bill_date, location_id, status, subtotal, total, created_by)
 select id, 'return', 'R1', date '2026-09-13', 1, 'posted', 750, 750, :'o' from suppliers where name = 'Sup A';
insert into purchase_bills (supplier_id, kind, bill_no, bill_date, location_id, status, subtotal, total, created_by)
 select id, 'bill', 'B4', date '2026-09-03', 1, 'draft', 99999, 99999, :'o' from suppliers where name = 'Sup A';
insert into purchase_lines (bill_id, line_no, item_id, qty, unit, unit_cost, amount)
 select b.id, 1, (select id from items where code = 'T-1'), 10, 'kg', 100, 1000 from purchase_bills b where b.bill_no = 'B1';
insert into purchase_lines (bill_id, line_no, item_id, qty, unit, unit_cost, amount)
 select b.id, 1, (select id from items where code = 'T-1'), 10, 'kg', 120, 1200 from purchase_bills b where b.bill_no = 'B2';
insert into purchase_lines (bill_id, line_no, item_id, qty, unit, unit_cost, amount)
 select b.id, 1, (select id from items where code = 'T-1'), 5, 'kg', 5000, 25000 from purchase_bills b where b.bill_no = 'B4';

-- 04-1 goods received notes
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('04-1', 1, 1, '2026-09-05', 'submitted', $j${"supplier":"Sup B","paper":"po","po_no":"PO-7","lines":[{"item":"T-1","memo":"20","counted":"18","rate":"90","quality":"accept"},{"item":"T-2","memo":"5","counted":"5","rate":"300","quality":"return"}]}$j$, :'o'),
 ('04-1', 1, 2, '2026-09-25', 'approved',  $j${"supplier":"Sup B","paper":"direct","lines":[{"item":"T-1","memo":"20","counted":"20","rate":"99","quality":"accept"}]}$j$, :'o'),
 ('04-1', 2, 1, '2026-09-06', 'submitted', $j${"supplier":"Sup B","paper":"direct","lines":[{"item":"T-1","memo":"5","counted":"5","rate":"50","quality":"accept"}]}$j$, :'o'),
 ('04-1', 2, 2, '2026-09-12', 'submitted', $j${"supplier":"Sup B","paper":"po","po_no":"PO-9","lines":[{"item":"T-1","memo":"4","counted":"4","rate":"50","quality":"accept"}]}$j$, :'o'),
 ('04-1', 1, 3, '2026-09-16', 'submitted', $j${"supplier":"Sup A","paper":"po","po_no":"po-010","lines":[{"item":"T-1","memo":"10","counted":"10","rate":"100","quality":"accept"}]}$j$, :'o'),
 ('04-1', 1, 4, '2026-09-18', 'draft',     $j${"supplier":"Sup B","paper":"direct","lines":[{"item":"T-1","memo":"99","counted":"1","rate":"1","quality":"hold"}]}$j$, :'o');
-- 06-3 purchase orders (paper_serial = the printed PO number)
insert into entries (form_code, location_id, serial, entry_date, status, data, paper_serial, created_by) values
 ('06-3', 1, 1, '2026-09-03', 'approved',  $j${"supplier":"Sup B","delivery_date":"2026-09-04","lines":[{"item":"T-1","qty":"20","rate":"90"},{"item":"T-2","qty":"5","rate":"300"}]}$j$, 'PO-7', :'o'),
 ('06-3', 1, 2, '2026-09-10', 'submitted', $j${"supplier":"Sup B","delivery_date":"2026-09-12","lines":[{"item":"T-1","qty":"10","rate":"100"}]}$j$, 'PO-8', :'o'),
 ('06-3', 2, 1, '2026-09-11', 'submitted', $j${"supplier":"Sup B","delivery_date":"2026-09-12","lines":[{"item":"T-1","qty":"4","rate":"50"}]}$j$, 'PO-9', :'o'),
 ('06-3', 1, 3, '2026-09-14', 'submitted', $j${"supplier":"Sup A","delivery_date":"2026-09-16","lines":[{"item":"T-1","qty":"10","rate":"100"}]}$j$, 'PO-10', :'o'),
 ('06-3', 1, 4, '2026-09-15', 'submitted', $j${"supplier":"Sup A","cancel":true,"delivery_date":"2026-09-16","lines":[{"item":"T-1","qty":"1","rate":"1"}]}$j$, 'PO-11', :'o'),
 ('06-3', 1, 5, '2026-09-15', 'draft',     $j${"supplier":"Sup A","delivery_date":"2026-09-16","lines":[{"item":"T-1","qty":"1","rate":"1"}]}$j$, 'PO-12', :'o');
-- 06-4 bill checks
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('06-4', 1, 1, '2026-09-26', 'approved',  $j${"supplier":"Sup B","bill_no":"X1","bill_amount":"3120","short":"yes","returned":"no","tri":[{"po":"PO-7","grn":"PO-7","bill":"PO-7"},{"po":"25","grn":"23","bill":"23"}]}$j$, :'o'),
 ('06-4', 2, 1, '2026-09-13', 'submitted', $j${"supplier":"Sup B","bill_no":"X2","bill_amount":"200","short":"no","returned":"no","tri":[{"po":"PO-9","grn":"PO-9","bill":"PO-9"}]}$j$, :'o'),
 ('06-4', 1, 2, '2026-09-17', 'submitted', $j${"supplier":"Sup A","bill_no":"X3","bill_amount":"1100","short":"no","returned":"yes","tri":[{"po":"PO-10","grn":"PO-10","bill":"PO-10"}]}$j$, :'o');
-- 10-4 cash position and purchase budget
insert into location_settings (location_id, key, value) values (1, 'hub_min_cash', '20000'::jsonb);
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('10-4', 1, 1, '2026-09-10', 'approved',  $j${"hub_cash":"50000","sr_float":"5000","bank":"20000","mobile":"5000","recv":[{"amt":"10000"},{"amt":"5000"},{"amt":""}],"pay":[{"amt":"30000"},{"amt":"10000"}]}$j$, :'o'),
 ('10-4', 1, 2, '2026-09-20', 'submitted', $j${"hub_cash":"10000"}$j$, :'o'),
 ('10-4', 2, 1, '2026-09-10', 'submitted', $j${"hub_cash":"1000"}$j$, :'o'),
 ('10-4', 1, 3, '2026-09-22', 'draft',     $j${"hub_cash":"999999"}$j$, :'o');
-- 04-3 count sheets
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('04-3', 1, 1, '2026-09-10', 'submitted', $j${"counted_by":"S1","rows":[{"item":"T-1","count":"8","book":"10","reason":"spill"},{"item":"T-2","count":"5","book":"5"}]}$j$, :'o'),
 ('04-3', 1, 2, '2026-09-17', 'approved',  $j${"counted_by":"S1","rows":[{"item":"T-1","count":"12","book":"10","reason":"recount"},{"item":"T-2","count":"3"}]}$j$, :'o'),
 ('04-3', 1, 3, '2026-09-18', 'submitted', $j${"counted_by":"S2","rows":[{"item":"T-1","count":"9","book":"10","reason":"x"}]}$j$, :'o'),
 ('04-3', 2, 1, '2026-09-10', 'submitted', $j${"counted_by":"S1","rows":[{"item":"T-1","count":"1","book":"5","reason":"lost"}]}$j$, :'o'),
 ('04-3', 1, 4, '2026-09-19', 'draft',     $j${"counted_by":"S1","rows":[{"item":"T-1","count":"0","book":"100"}]}$j$, :'o');
-- recipe: 10 kg of T-2 per batch from 2 kg T-1 (waste 10 %) and 1 kg T-3 (waste not set)
insert into recipes (id, item_id, version, yield_qty) values ('aaaaaaaa-0000-0000-0000-000000000001', (select id from items where code = 'T-2'), 1, 10);
insert into recipe_lines (recipe_id, ingredient_item_id, qty, waste_pct, sort) values
 ('aaaaaaaa-0000-0000-0000-000000000001', (select id from items where code = 'T-1'), 2, 10, 1),
 ('aaaaaaaa-0000-0000-0000-000000000001', (select id from items where code = 'T-3'), 1, null, 2);
insert into production_runs (id, location_id, recipe_id, item_id, batches, made_at, yield_base, status) values
 ('bbbbbbbb-0000-0000-0000-000000000001', 1, 'aaaaaaaa-0000-0000-0000-000000000001', (select id from items where code = 'T-2'), 2, '2026-09-10 10:00+06', 20, 'done'),
 ('bbbbbbbb-0000-0000-0000-000000000002', 1, 'aaaaaaaa-0000-0000-0000-000000000001', (select id from items where code = 'T-2'), 1, '2026-09-11 10:00+06', 10, 'done'),
 ('bbbbbbbb-0000-0000-0000-000000000003', 1, 'aaaaaaaa-0000-0000-0000-000000000001', (select id from items where code = 'T-2'), 1, '2026-09-12 10:00+06', 10, 'void'),
 ('bbbbbbbb-0000-0000-0000-000000000004', 2, 'aaaaaaaa-0000-0000-0000-000000000001', (select id from items where code = 'T-2'), 1, '2026-09-10 10:00+06', 10, 'done');
insert into stock_ledger (item_id, location_id, qty_delta, reason, ref_type, ref_id, made_at) values
 ((select id from items where code = 'T-1'), 1, -4.6, 'issue_out', 'production', 'bbbbbbbb-0000-0000-0000-000000000001', '2026-09-10 10:00+06'),
 ((select id from items where code = 'T-3'), 1, -2,   'issue_out', 'production', 'bbbbbbbb-0000-0000-0000-000000000001', '2026-09-10 10:00+06'),
 ((select id from items where code = 'T-1'), 1, -2.2, 'issue_out', 'production', 'bbbbbbbb-0000-0000-0000-000000000002', '2026-09-11 10:00+06'),
 ((select id from items where code = 'T-3'), 1, -1,   'issue_out', 'production', 'bbbbbbbb-0000-0000-0000-000000000002', '2026-09-11 10:00+06'),
 ((select id from items where code = 'T-1'), 1, -2.2, 'issue_out', 'production', 'bbbbbbbb-0000-0000-0000-000000000003', '2026-09-12 10:00+06'),
 ((select id from items where code = 'T-1'), 2, -2.2, 'issue_out', 'production', 'bbbbbbbb-0000-0000-0000-000000000004', '2026-09-10 10:00+06');
-- 05-1 factory sheets (fridges, breakdown, hygiene ticks, output)
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('05-1', 1, 1, '2026-09-10', 'submitted', $j${"batches":"3","fridges":[{"temp":"4"},{"temp":"9"}],"fridges2":[{"temp":"5"},{"temp":""}],"breakdown":"yes","bd_machine":"Mixer","bd_request":"REQ-1","bd_time":"11:15",
    "pots_done":true,"hygiene_done":true,"machines_done":true,"gas_off":true,"power_off":true,"output":[{"item":"T-2","qty":"20"},{"item":"T-1","qty":"5"}]}$j$, :'o'),
 ('05-1', 1, 2, '2026-09-11', 'approved',  $j${"batches":"2","breakdown":"no"}$j$, :'o'),
 ('05-1', 2, 1, '2026-09-12', 'submitted', $j${"batches":"1","output":[{"item":"T-2","qty":"10"}]}$j$, :'o'),
 ('05-1', 1, 3, '2026-09-13', 'draft',     $j${"batches":"50","breakdown":"yes","bd_machine":"Ghost"}$j$, :'o');
insert into stock_transfers (from_location_id, to_location_id, item_id, qty, status, sent_at) values
 (1, 2, (select id from items where code = 'T-2'), 7, 'sent', '2026-09-11 12:00+06'),
 (2, 1, (select id from items where code = 'T-2'), 3, 'received', '2026-09-12 12:00+06');
-- 05-4 yield tests
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('05-4', 1, 1, '2026-09-05', 'approved',  $j${"item":"T-2","b":[{"date":"2026-09-01","input":"100","good":"80","second":"10","waste":"10"},{"date":"2026-09-02","input":"100","good":"70","second":"20","waste":"10"},{"date":"2026-09-03","input":"100","good":"90","second":"5","waste":"5"}]}$j$, :'o'),
 ('05-4', 1, 2, '2026-09-24', 'submitted', $j${"item":"T-2","b":[{"date":"2026-09-22","input":"50","good":"30","second":"10","waste":"10"}]}$j$, :'o');
-- 08-1 maintenance requests
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('08-1', 1, 1, '2026-09-08', 'approved',  $j${"machine":"Mixer","machine_id":"M-1","found_date":"2026-09-08","found_time":"09:00","p_stop":true,"done_date":"2026-09-08","done_time":"15:30","est_cost":"500","actual_cost":"450"}$j$, :'o'),
 ('08-1', 1, 2, '2026-09-20', 'submitted', $j${"machine":"mixer","machine_id":"M-1","found_date":"2026-09-20","found_time":"10:00","p_leak":true,"p_noise":true,"est_cost":"200"}$j$, :'o'),
 ('08-1', 1, 3, '2026-08-01', 'approved',  $j${"machine":"Oven","machine_id":"O-1","found_date":"2026-08-01","found_time":"08:00","p_power":true}$j$, :'o'),
 ('08-1', 1, 4, '2026-07-01', 'approved',  $j${"machine":"Oven","machine_id":"O-1","found_date":"2026-07-01","found_time":"08:00","done_date":"2026-07-02","done_time":"08:00"}$j$, :'o'),
 ('08-1', 2, 1, '2026-09-09', 'approved',  $j${"machine":"Fridge","machine_id":"F-1","found_date":"2026-09-09","found_time":"08:00","p_cool":true,"done_date":"2026-09-10","done_time":"08:00","est_cost":"1000","actual_cost":"900"}$j$, :'o'),
 ('08-1', 1, 5, '2026-09-21', 'draft',     $j${"machine":"Ghost","found_date":"2026-09-21","est_cost":"77777"}$j$, :'o');
-- 18-1 marketing lines; sales
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('18-1', 1, 1, '2026-09-10', 'approved',  $j${"lines":[{"date":"2026-09-10","head":"1","amt":"500"},{"date":"2026-09-10","head":"3","amt":"300"},{"date":"2026-09-11","head":"1","amt":"200","nonpay":"0"},{"head":"other:xyz","amt":"100"},{"date":"2026-09-12","head":"1","nonpay":"400"}]}$j$, :'o'),
 ('18-1', 2, 1, '2026-09-10', 'submitted', $j${"lines":[{"date":"2026-09-10","head":"1","amt":"1000"}]}$j$, :'o'),
 ('18-1', 1, 2, '2026-09-10', 'draft',     $j${"lines":[{"date":"2026-09-10","head":"1","amt":"99999"}]}$j$, :'o');
insert into sales (location_id, receipt, sale_date, sold_at, subtotal, total, pay_mode, status, created_by) values
 (1, 901, '2026-09-10', '2026-09-10 12:00+06', 1000, 1000, 'cash', 'done', :'o'),
 (1, 902, '2026-09-10', '2026-09-10 13:00+06', 500, 500, 'cash', 'done', :'o'),
 (1, 903, '2026-09-10', '2026-09-10 14:00+06', 9999, 9999, 'cash', 'void', :'o'),
 (1, 904, '2026-09-13', '2026-09-13 14:00+06', 700, 700, 'cash', 'done', :'o'),
 (2, 901, '2026-09-10', '2026-09-10 12:00+06', 2000, 2000, 'cash', 'done', :'o');
-- Q1 limits, 14-1 showroom sheets
insert into location_settings (location_id, key, value) values (1, 'fridge1_min', '2'::jsonb), (1, 'fridge1_max', '6'::jsonb), (1, 'fridge2_min', '2'::jsonb), (1, 'fridge2_max', '6'::jsonb), (1, 'fridge1_name', '"Chiller A"'::jsonb);
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by) values
 ('14-1', 1, 1, '2026-09-11', 'submitted', $j${"fridges":[{"temp":"3"},{"temp":"7.5"},{"temp":"10"}],"t2_1":"8","t2_2":"4","expired_shown":"yes",
    "c1":true,"c2":true,"c3":true,"c4":true,"c5":true,"c6":true,"c7":true,"c8":true,"c9":true,"c10":true,"c11":true,"c12":true}$j$, :'o'),
 ('14-1', 1, 2, '2026-09-12', 'approved',  $j${"expired_shown":"no","c1":true,"c2":true,"c3":true,"c4":true,"c5":true,"c6":true,"c7":true,"c8":true,"c9":true,"c10":true,"c11":true,"c12":true,"c13":true,"c14":true,"c15":true,"c16":true}$j$, :'o'),
 ('14-1', 2, 1, '2026-09-10', 'submitted', $j${"fridges":[{"temp":"4"}]}$j$, :'o'),
 ('14-1', 1, 3, '2026-09-13', 'draft',     $j${"fridges":[{"temp":"40"}]}$j$, :'o');
-- Q3 complaints and sale returns
insert into entries (form_code, location_id, serial, entry_date, status, data, check_data, created_by) values
 ('20-3', 1, 1, '2026-09-10', 'approved',  $j${"item":"T-2","qty":"2","c_taste":true,"c_smell":true,"refund_amt":"100"}$j$, $j${"root_cause":"old milk","resolved":true}$j$, :'o'),
 ('20-3', 1, 2, '2026-09-11', 'submitted', $j${"item":"T-2","qty":"1","c_taste":true,"c_sick":true}$j$, '{}'::jsonb, :'o'),
 ('20-3', 2, 1, '2026-09-12', 'submitted', $j${"item":"T-1","qty":"1","c_late":true}$j$, '{}'::jsonb, :'o'),
 ('20-3', 1, 3, '2026-09-12', 'draft',     $j${"item":"T-2","qty":"9","c_taste":true}$j$, '{}'::jsonb, :'o');
insert into sale_returns (sale_id, location_id, lines, amount, credit_amount, refund_amount, reason_code, status, created_at) values
 ((select id from sales where receipt = 901 and location_id = 1), 1, ('[{"item_id":"' || (select id from items where code = 'T-2') || '","qty":1,"amount":300}]')::jsonb, 300, 0, 300, 'quality', 'done', '2026-09-10 15:00+06'),
 ((select id from sales where receipt = 902 and location_id = 1), 1, ('[{"item_id":"' || (select id from items where code = 'T-2') || '","qty":2,"amount":600}]')::jsonb, 600, 0, 600, 'damaged', 'done', '2026-09-11 15:00+06'),
 ((select id from sales where receipt = 902 and location_id = 1), 1, ('[{"item_id":"' || (select id from items where code = 'T-2') || '","qty":5,"amount":9000}]')::jsonb, 9000, 0, 9000, 'damaged', 'void', '2026-09-11 16:00+06');

\echo == catalog and shape
select tt.chk('T0 all 13 reports registered', (select count(*) from report_defs3 where key in ('p2_rate_trend','p4_supplier_score','p5_po_match','p6_purchase_budget','k2_count_variance','f1_production','f2_yield','f3_raw_vs_recipe','f4_breakdowns','m2_marketing_vs_sales','q1_fridge_temp','q2_hygiene','q3_complaints'))=13);
select tt.chk('T0 only P2 P4 P5 P6 are cost reports, none owner-only', (select array_agg(key order by key) from report_defs3 where cost and key in ('p2_rate_trend','p4_supplier_score','p5_po_match','p6_purchase_budget','k2_count_variance','f1_production','f2_yield','f3_raw_vs_recipe','f4_breakdowns','m2_marketing_vs_sales','q1_fridge_temp','q2_hygiene','q3_complaints'))=array['p2_rate_trend','p4_supplier_score','p5_po_match','p6_purchase_budget']
  and not exists (select 1 from report_defs3 where owner_only and code in ('P2','P4','P5','P6','K2','F1','F2','F3','F4','M2','Q1','Q2','Q3')));
select tt.chk('T0 the _r3q_ functions are private', not has_function_privilege('authenticated','_r3q_p2_rate_trend(date,date,int[],jsonb)','execute') and not has_function_privilege('authenticated','_p26_po(date,date,int[])','execute') and not has_function_privilege('authenticated','_p26_rates(date,date,int[])','execute'));

\echo == owner
set role authenticated; select tt.as(:'o');
select report_run2('p2_rate_trend','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('P2 rows: T-1 Sup A, T-1 Sup B, T-2 Sup B (draft bill and draft GRN excluded)', tt.n(:'j'::jsonb)=3);
select tt.chk('P2 Sup A T-1: bills 100->120 and the GRN at 100: n 3, +20 %, min 100, max 120, avg 106.6667',
  (tt.row(:'j'::jsonb,'supplier','Sup A')->>'n')::int=3 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'first_rate')::numeric=100 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'last_rate')::numeric=120
  and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'change_pct')::numeric=20 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'avg_rate')::numeric=106.6667 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'min_rate')::numeric=100 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'max_rate')::numeric=120);
select tt.chk('P2 Sup B T-1: n 4 over both places, 90 -> 99 = +10 %, min 50, avg 86.1702, qty 47',
  (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'n')::int=4 and (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'change_pct')::numeric=10
  and (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'min_rate')::numeric=50 and (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'avg_rate')::numeric=86.1702 and (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'qty')::numeric=47);
select tt.chk('P2 a single purchase has no change % (null, not 0)', (tt.row(:'j'::jsonb,'item_code','T-2')->'change_pct')='null'::jsonb and (tt.row(:'j'::jsonb,'item_code','T-2')->>'last_rate')::numeric=300);
select tt.chk('P2 default sort change % desc, nulls last', (:'j'::jsonb->'rows'->0->>'change_pct')::numeric=20 and (:'j'::jsonb->'rows'->2->'change_pct')='null'::jsonb);
select tt.chk('P2 category filter', tt.n(report_run2('p2_rate_trend','{"from":"2026-09-01","to":"2026-09-30","categories":["sweet"]}'::jsonb))=1);
select tt.chk('P2 period narrows it', tt.n(report_run2('p2_rate_trend','{"from":"2026-09-15","to":"2026-09-30"}'::jsonb))=2);

select report_run2('p4_supplier_score','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('P4 two suppliers', tt.n(:'j'::jsonb)=2);
select tt.chk('P4 Sup B quality: 4 GRNs, 5 lines, 1 short line, 1 returned line, none held',
  (tt.row(:'j'::jsonb,'supplier','Sup B')->>'grns')::int=4 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'lines')::int=5 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'short_lines')::int=1
  and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'rejected')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'held')::int=0 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'reduced')::int=0);
select tt.chk('P4 Sup B bills: 2 checked, 1 shortage claim, 0 return claims', (tt.row(:'j'::jsonb,'supplier','Sup B')->>'bills_checked')::int=2 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'short_claims')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'return_claims')::int=0);
select tt.chk('P4 Sup B POs: 3, 1 late (PO-7 came a day after 09-04), 1 open past due (PO-8)', (tt.row(:'j'::jsonb,'supplier','Sup B')->>'pos')::int=3 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'late_pos')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'overdue_open')::int=1);
select tt.chk('P4 Sup B average rate change +10 % over 1 comparable item', (tt.row(:'j'::jsonb,'supplier','Sup B')->>'rate_change_pct')::numeric=10 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'rate_items')::int=1);
select tt.chk('P4 Sup A: 1 GRN, 1 bill with a return claim, 1 PO on time (0 late), rate +20 %',
  (tt.row(:'j'::jsonb,'supplier','Sup A')->>'grns')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'return_claims')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'pos')::int=1
  and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'late_pos')::int=0 and (tt.row(:'j'::jsonb,'supplier','Sup A')->>'rate_change_pct')::numeric=20);
select tt.chk('P4 totals add the counts', (:'j'::jsonb->'totals'->>'grns')::numeric=5 and (:'j'::jsonb->'totals'->>'rejected')::numeric=1 and (:'j'::jsonb->'totals'->>'pos')::numeric=4);

select report_run2('p5_po_match','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('P5 four POs (cancelled and draft PO excluded)', tt.n(:'j'::jsonb)=4);
select tt.chk('P5 PO-7 partial: total 3300, GRN 3120, 1 line still open, billed 3120 (diff 0), 1 day late',
  tt.row(:'j'::jsonb,'po_no','PO-7')->>'status' like 'আংশিক%' and (tt.row(:'j'::jsonb,'po_no','PO-7')->>'po_total')::numeric=3300 and (tt.row(:'j'::jsonb,'po_no','PO-7')->>'grn_value')::numeric=3120
  and (tt.row(:'j'::jsonb,'po_no','PO-7')->>'lines_open')::int=1 and (tt.row(:'j'::jsonb,'po_no','PO-7')->>'bill_amount')::numeric=3120 and (tt.row(:'j'::jsonb,'po_no','PO-7')->>'bill_diff')::numeric=0
  and (tt.row(:'j'::jsonb,'po_no','PO-7')->>'days_late')::int=(select ((now() at time zone 'Asia/Dhaka')::date - date '2026-09-04')));
select tt.chk('P5 PO-8 open: no GRN, no bill, null GRN/bill figures, late since 09-12',
  tt.row(:'j'::jsonb,'po_no','PO-8')->>'status' like 'খোলা%' and (tt.row(:'j'::jsonb,'po_no','PO-8')->>'grn_n')::int=0 and tt.row(:'j'::jsonb,'po_no','PO-8')->'grn_value'='null'::jsonb and tt.row(:'j'::jsonb,'po_no','PO-8')->'bill_amount'='null'::jsonb
  and (tt.row(:'j'::jsonb,'po_no','PO-8')->>'days_late')::int=(select ((now() at time zone 'Asia/Dhaka')::date - date '2026-09-12')));
select tt.chk('P5 PO-9 (place 2) matched: 200 / 200 / 200, on time', tt.row(:'j'::jsonb,'po_no','PO-9')->>'status' like 'বিল মিলেছে%' and (tt.row(:'j'::jsonb,'po_no','PO-9')->>'bill_diff')::numeric=0 and (tt.row(:'j'::jsonb,'po_no','PO-9')->>'days_late')::int=0);
select tt.chk('P5 PO-10 (typed po-010 on the GRN) received, bill 1100 vs GRN 1000 differs by 100', tt.row(:'j'::jsonb,'po_no','PO-10')->>'status' like 'বিল অমিল%' and (tt.row(:'j'::jsonb,'po_no','PO-10')->>'bill_diff')::numeric=100 and (tt.row(:'j'::jsonb,'po_no','PO-10')->>'lines_open')::int=0);
select tt.chk('P5 default sort: most days late first', tt.row(:'j'::jsonb,'po_no','PO-7') is not null and (:'j'::jsonb->'rows'->0->>'po_no') in ('PO-8','PO-7'));

select report_run2('p6_purchase_budget','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('P6 three sheets (the draft is out)', tt.n(:'j'::jsonb)=3);
select tt.chk('P6 sheet 09-10 place 1: cash 80000, receivable 15000, payable 40000, minimum 20000 -> budget 35000',
  (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'cash_total')::numeric=80000 and (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'receivable')::numeric=15000
  and (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'payable')::numeric=40000 and (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'budget')::numeric=35000);
select tt.chk('P6 sheet 09-10: bills of the next 7 days 8750 - 750 = 8000, used 22.9 %, left 27000',
  (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'bills_7d')::numeric=8000 and (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'spent')::numeric=8000
  and (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'used_pct')::numeric=22.9 and (tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->>'budget_left')::numeric=27000);
select tt.chk('P6 sheet 09-20: budget -10000 (overspent), bill B2 1200, used % null when there is no budget, left -11200',
  (tt.row(:'j'::jsonb,'day','2026-09-20')->>'budget')::numeric=-10000 and (tt.row(:'j'::jsonb,'day','2026-09-20')->>'spent')::numeric=1200 and tt.row(:'j'::jsonb,'day','2026-09-20')->'used_pct'='null'::jsonb and (tt.row(:'j'::jsonb,'day','2026-09-20')->>'budget_left')::numeric=-11200);
select tt.chk('P6 place 2 has no hub_min_cash setting: budget null, left null, spent still shown (0)', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where (x->>'cash_total')::numeric=1000 and x->'min_cash'='null'::jsonb and x->'budget'='null'::jsonb and x->'budget_left'='null'::jsonb and x->'used_pct'='null'::jsonb and (x->>'spent')::numeric=0));
select tt.chk('P6 the outlook is only on the latest sheet of a place (an older sheet has none)', tt.row(:'j'::jsonb,'day','2026-09-10','min_cash','20000')->'outlook_low'='null'::jsonb);

select report_run2('k2_count_variance','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('K2 four counter-item rows (draft and rows without a book figure are out)', tt.n(:'j'::jsonb)=4);
select tt.chk('K2 S1 / T-1 place 1: 2 counts, both off, 1 short 1 over, net 0, absolute 4, last reason recount',
  (tt.row(:'j'::jsonb,'counter','S1','item_code','T-1')->>'counts')::int>=1 and exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'counter'='S1' and x->>'item_code'='T-1' and (x->>'counts')::int=2 and (x->>'off_n')::int=2 and (x->>'short_n')::int=1 and (x->>'over_n')::int=1
     and (x->>'net_var')::numeric=0 and (x->>'abs_var')::numeric=4 and (x->>'off_pct')::numeric=100 and x->>'last_reason'='recount' and x->>'last_date'='2026-09-17'));
select tt.chk('K2 S1 / T-2 counted right once: off 0', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'counter'='S1' and x->>'item_code'='T-2' and (x->>'counts')::int=1 and (x->>'off_n')::int=0 and (x->>'off_pct')::numeric=0));
select tt.chk('K2 S2 net -1', (tt.row(:'j'::jsonb,'counter','S2')->>'net_var')::numeric=-1);
select tt.chk('K2 totals: 5 counts, 4 off', (:'j'::jsonb->'totals'->>'counts')::numeric=5 and (:'j'::jsonb->'totals'->>'off_n')::numeric=4);
select tt.chk('K2 sort off_n desc: first row has 2', (:'j'::jsonb->'rows'->0->>'off_n')::int=2);
select tt.chk('K2 shows no money column', not exists (select 1 from jsonb_array_elements(:'j'::jsonb->'columns') c where c->>'type'='money') and not (select cost_only from jsonb_to_recordset(report_catalog2()) as x(key text, cost_only boolean) where key='k2_count_variance'));

select report_run2('f1_production','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('F1 ten rows: 4 runs, 4 sheet lines, 2 dispatches', tt.n(:'j'::jsonb)=10 and (select count(*) from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'রান%')=4
  and (select count(*) from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'শিট%')=4 and (select count(*) from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'চালান%')=2);
select tt.chk('F1 the voided run is listed with status void', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'রান%' and x->>'status'='void' and x->>'day'='2026-09-12' and (x->>'qty')::numeric=10));
select tt.chk('F1 run of 09-10 place 1: 2 batches, 20', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'রান%' and x->>'day'='2026-09-10' and x->>'status'='done' and (x->>'batches')::numeric=2 and (x->>'qty')::numeric=20 and x->>'product_code'='T-2'));
select tt.chk('F1 sheet S1: batches 3 on the first output line only, qty 20 and 5', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'শিট%' and x->>'product_code'='T-2' and x->>'day'='2026-09-10' and (x->>'batches')::numeric=3 and (x->>'qty')::numeric=20)
  and exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'শিট%' and x->>'product_code'='T-1' and (x->'batches')='null'::jsonb and (x->>'qty')::numeric=5));
select tt.chk('F1 sheet S2 without output: one row, batches 2, no product', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'শিট%' and x->>'day'='2026-09-11' and (x->>'batches')::numeric=2 and x->'product_code'='null'::jsonb and x->>'status'='approved'));
select tt.chk('F1 dispatch 1 -> 2 qty 7 shows the destination', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'চালান%' and (x->>'qty')::numeric=7 and x->>'status'='sent' and x->>'to_location_bn' is not null));

select report_run2('f2_yield','{"from":"2026-09-10","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('F2 three place-product rows', tt.n(:'j'::jsonb)=3);
select tt.chk('F2 place 1 T-2: standard 0.8 (latest approved sheet), 1 measurement in the period at 0.6 = -25 %, second 20 %, waste 20 %',
  exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'item_code'='T-2' and (x->>'std_yield')::numeric=0.8 and (x->>'tests_n')::int=1 and (x->>'test_yield')::numeric=0.6 and (x->>'yield_diff_pct')::numeric=-25
    and (x->>'second_pct')::numeric=20 and (x->>'waste_pct')::numeric=20));
select tt.chk('F2 place 1 T-2: runs 3 batches / 30 (void run left out), sheet 20, gap -10', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'item_code'='T-2' and (x->>'run_batches')::numeric=3 and (x->>'run_qty')::numeric=30 and (x->>'sheet_qty')::numeric=20 and (x->>'qty_gap')::numeric=-10));
select tt.chk('F2 place 2 T-2: no standard (null), no test, gap 0', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'item_code'='T-2' and x->'std_yield'='null'::jsonb and (x->>'tests_n')::int=0 and (x->>'qty_gap')::numeric=0));
select tt.chk('F2 T-1 only on a sheet: run null, gap null', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'item_code'='T-1' and (x->>'sheet_qty')::numeric=5 and x->'run_qty'='null'::jsonb and x->'qty_gap'='null'::jsonb));
select tt.chk('F2 whole September: 4 measurements, mean 0.75 vs 0.8 = -6.25 %', exists (select 1 from jsonb_array_elements(report_run2('f2_yield','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb)->'rows') x where x->>'item_code'='T-2' and (x->>'tests_n')::int=4 and (x->>'test_yield')::numeric=0.75 and (x->>'yield_diff_pct')::numeric=-6.25 and (x->>'second_pct')::numeric=13.75 and (x->>'waste_pct')::numeric=11.25));

select report_run2('f3_raw_vs_recipe','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('F3 four rows (void run excluded)', tt.n(:'j'::jsonb)=4);
select tt.chk('F3 place 2 T-3 was never issued in the ledger: expected 1, actual / diff null (not 0)', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'ingredient_code'='T-3' and (x->>'expected')::numeric=1 and x->'actual'='null'::jsonb and x->'diff'='null'::jsonb and x->'diff_pct'='null'::jsonb));
select tt.chk('F3 place 1 T-1: 2 runs, 3 batches, expected 6.6 (2 kg + 10 % waste), issued 6.8, +0.2 = +3.03 %',
  exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'ingredient_code'='T-1' and x->>'location_bn' like '%মেইন%' and (x->>'runs')::int=2 and (x->>'batches')::numeric=3 and (x->>'expected')::numeric=6.6 and (x->>'actual')::numeric=6.8
    and (x->>'diff')::numeric=0.2 and (x->>'diff_pct')::numeric=3.03 and (x->>'waste_missing')::int=0));
select tt.chk('F3 T-3 has no waste % in the recipe: expected 3, issued 3, flagged on 2 runs', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'ingredient_code'='T-3' and (x->>'expected')::numeric=3 and (x->>'actual')::numeric=3 and (x->>'diff')::numeric=0 and (x->>'waste_missing')::int=2));
select tt.chk('F3 place 2 T-1: expected 2.2 issued 2.2', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'ingredient_code'='T-1' and (x->>'runs')::int=1 and (x->>'expected')::numeric=2.2 and (x->>'actual')::numeric=2.2));
select tt.chk('F3 sort diff % desc', (:'j'::jsonb->'rows'->0->>'diff_pct')::numeric=3.03);

select report_run2('f4_breakdowns','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('F4 five rows: 4 requests (one open from August, the July closed one and the draft are out) + 1 sheet breakdown', tt.n(:'j'::jsonb)=5);
select tt.chk('F4 M1 closed: 6.5 hours, 500 est, 450 actual, problem not running, 1 time', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source'='08-1' and x->>'day'='2026-09-08' and x->>'status' like 'শেষ%' and (x->>'downtime_h')::numeric=6.5
  and (x->>'est_cost')::numeric=500 and (x->>'actual_cost')::numeric=450 and x->>'problem' like 'চলছে না%' and (x->>'repeat_n')::int=1));
select tt.chk('F4 M2 open, second Mixer fault (repeat 2), two problems, no downtime', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source'='08-1' and x->>'day'='2026-09-20' and x->>'status' like 'খোলা%' and (x->>'repeat_n')::int=2 and x->'downtime_h'='null'::jsonb and x->>'problem' like '%শব্দ%' and x->>'problem' like '%লিক%'));
select tt.chk('F4 old open Oven request is listed although August is outside the period', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'machine'='Oven' and x->>'day'='2026-08-01' and x->>'status' like 'খোলা%'));
select tt.chk('F4 place 2 fridge: 24 hours', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'machine'='Fridge' and (x->>'downtime_h')::numeric=24));
select tt.chk('F4 05-1 breakdown row carries the request number', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source'='05-1' and x->>'machine'='Mixer' and x->>'request_ref'='REQ-1' and x->>'found_time'='11:15'));
select tt.chk('F4 totals: downtime 30.5, est 1700, actual 1350', (:'j'::jsonb->'totals'->>'downtime_h')::numeric=30.5 and (:'j'::jsonb->'totals'->>'est_cost')::numeric=1700 and (:'j'::jsonb->'totals'->>'actual_cost')::numeric=1350);

select report_run2('m2_marketing_vs_sales','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('M2 five day-place rows', tt.n(:'j'::jsonb)=5);
select tt.chk('M2 09-10 place 1: spend 500+300+100 = 900, sales 1000+500 (void out) = 1500 in 2 bills', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'day'='2026-09-10' and (x->>'spend')::numeric=900 and (x->>'sales_total')::numeric=1500 and (x->>'sales_n')::int=2 and (x->>'mkt_lines')::int=3 and x->>'heads' like '%500%' and x->>'heads' like '%300%'));
select tt.chk('M2 09-11: spend 200, no sales', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'day'='2026-09-11' and (x->>'spend')::numeric=200 and (x->>'sales_total')::numeric=0 and (x->>'sales_n')::int=0));
select tt.chk('M2 09-12: value without payment 400, spend 0', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'day'='2026-09-12' and (x->>'spend')::numeric=0 and (x->>'nonpay_value')::numeric=400));
select tt.chk('M2 09-13: sales only 700', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'day'='2026-09-13' and (x->>'spend')::numeric=0 and (x->>'sales_total')::numeric=700 and x->'heads'='null'::jsonb));
select tt.chk('M2 totals: spend 2100, non-cash 400, sales 4200 in 4 bills', (:'j'::jsonb->'totals'->>'spend')::numeric=2100 and (:'j'::jsonb->'totals'->>'nonpay_value')::numeric=400 and (:'j'::jsonb->'totals'->>'sales_total')::numeric=4200 and (:'j'::jsonb->'totals'->>'sales_n')::numeric=4);

select report_run2('q1_fridge_temp','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('Q1 six readings rows (draft sheet out, empty second slot gives no row)', tt.n(:'j'::jsonb)=6);
select tt.chk('Q1 05-1 fridge 1: 4 and 5 inside 2-6, named from settings, 0 out', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='05-1' and (x->>'fridge')::int=1 and (x->>'reading1')::numeric=4 and (x->>'reading2')::numeric=5 and x->>'fridge_name'='Chiller A' and (x->>'out_n')::int=0 and (x->>'min_c')::numeric=2 and (x->>'max_c')::numeric=6));
select tt.chk('Q1 05-1 fridge 2: 9 is out, no second reading', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='05-1' and (x->>'fridge')::int=2 and (x->>'reading1')::numeric=9 and x->'reading2'='null'::jsonb and (x->>'out_n')::int=1));
select tt.chk('Q1 14-1 fridge 1: 3 then busy-day 8 -> 1 out', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='14-1' and x->>'day'='2026-09-11' and (x->>'fridge')::int=1 and (x->>'reading2')::numeric=8 and (x->>'out_n')::int=1));
select tt.chk('Q1 14-1 fridge 2: 7.5 and 4 -> 1 out', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='14-1' and x->>'day'='2026-09-11' and (x->>'fridge')::int=2 and (x->>'reading1')::numeric=7.5 and (x->>'out_n')::int=1));
select tt.chk('Q1 fridge 3 and place 2 have no limits: out_n null, never guessed', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='14-1' and (x->>'fridge')::int=3 and (x->>'reading1')::numeric=10 and x->'out_n'='null'::jsonb and x->'max_c'='null'::jsonb)
  and exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'day'='2026-09-10' and x->>'form'='14-1' and x->'out_n'='null'::jsonb));
select tt.chk('Q1 total out-of-range readings 3; sorted worst first', (:'j'::jsonb->'totals'->>'out_n')::numeric=3 and (:'j'::jsonb->'rows'->0->>'out_n')::int=1);

select report_run2('q2_hygiene','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('Q2 six sheets', tt.n(:'j'::jsonb)=6);
select tt.chk('Q2 14-1 of 09-11: 12 of 16 done, 75 %, missed c13..c16, expired shown and not removed', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='14-1' and x->>'day'='2026-09-11' and (x->>'checks')::int=16 and (x->>'done')::int=12 and (x->>'missed')::int=4
  and (x->>'compliance_pct')::numeric=75 and x->>'missed_list'='c13, c14, c15, c16' and (x->>'expired_shown')::int=1 and (x->>'expired_not_removed')::int=1));
select tt.chk('Q2 14-1 of 09-12: all 16, 100 %, nothing missed (list null), no expired goods', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='14-1' and x->>'day'='2026-09-12' and (x->>'done')::int=16 and (x->>'compliance_pct')::numeric=100 and x->'missed_list'='null'::jsonb and (x->>'expired_shown')::int=0 and (x->>'expired_not_removed')::int=0));
select tt.chk('Q2 05-1 S1: 5 of 8 = 62.5 %, missed clean_done, machines_off, fire_safe; no expiry figure', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'form'='05-1' and x->>'day'='2026-09-10' and (x->>'done')::int=5 and (x->>'compliance_pct')::numeric=62.5
  and x->>'missed_list'='clean_done, machines_off, fire_safe' and x->'expired_shown'='null'::jsonb));
select tt.chk('Q2 sorted worst compliance first; totals 72 steps, 33 done, 39 missed', (:'j'::jsonb->'rows'->0->>'compliance_pct')::numeric=0 and (:'j'::jsonb->'totals'->>'checks')::numeric=72 and (:'j'::jsonb->'totals'->>'done')::numeric=33 and (:'j'::jsonb->'totals'->>'missed')::numeric=39
  and (:'j'::jsonb->'totals'->>'expired_not_removed')::numeric=1);

select report_run2('q3_complaints','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('Q3 six rows (draft complaint and void return out)', tt.n(:'j'::jsonb)=6);
select tt.chk('Q3 taste on T-2 place 1: 2 complaints, qty 3, refund 100, 1 unresolved, 1 sick, 1 without root cause', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like '20-3%' and x->>'cause' like 'স্বাদ%' and x->>'product_code'='T-2' and (x->>'n')::int=2
  and (x->>'qty')::numeric=3 and (x->>'refund_amt')::numeric=100 and (x->>'unresolved')::int=1 and (x->>'sick')::int=1 and (x->>'no_root_cause')::int=1));
select tt.chk('Q3 smell: 1 resolved complaint with a root cause', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'cause' like 'গন্ধ%' and (x->>'n')::int=1 and (x->>'unresolved')::int=0 and (x->>'no_root_cause')::int=0));
select tt.chk('Q3 fell-ill row and the late row of place 2', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'cause' like 'খেয়ে অসুস্থ%' and (x->>'sick')::int=1) and exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'cause' like 'দেরি%' and x->>'product_code'='T-1'));
select tt.chk('Q3 returns grouped by reason, labelled from the list: quality 1 x 300, damaged 2 x 600', exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'রিটার্ন%' and x->>'cause'='মান ভালো না' and (x->>'qty')::numeric=1 and (x->>'refund_amt')::numeric=300 and x->'unresolved'='null'::jsonb)
  and exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'source' like 'রিটার্ন%' and x->>'cause'='ক্ষতিগ্রস্ত' and (x->>'qty')::numeric=2 and (x->>'refund_amt')::numeric=600));
select tt.chk('Q3 totals n 7, unresolved 3, sick 2', (:'j'::jsonb->'totals'->>'n')::numeric=7 and (:'j'::jsonb->'totals'->>'unresolved')::numeric=3 and (:'j'::jsonb->'totals'->>'sick')::numeric=2);
select tt.chk('Q3 category filter keeps only sweets (the T-1 late row goes)', tt.n(report_run2('q3_complaints','{"from":"2026-09-01","to":"2026-09-30","categories":["sweet"]}'::jsonb))=5);

\echo == access and locations
select tt.as(:'s');
select tt.err('A1 no grant: K2 closed', $$select report_run2('k2_count_variance','{}'::jsonb)$$, 'not allowed');
select tt.err('A1 no grant: Q1 closed', $$select report_run2('q1_fridge_temp','{}'::jsonb)$$, 'not allowed');
select tt.err('A1 no grant: M2 closed', $$select report_run2('m2_marketing_vs_sales','{}'::jsonb)$$, 'not allowed');
select tt.chk('A1 catalog marks them closed', not exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key' in ('k2_count_variance','q2_hygiene','m2_marketing_vs_sales','p2_rate_trend') and (c->>'allowed')::boolean));
select tt.as(:'o'); select set_user_grant(:'s'::uuid,'report_stock') is null as g1, set_user_grant(:'s'::uuid,'report_quality') is null as g2, set_user_grant(:'s'::uuid,'report_marketing') is null as g3 \gset
select tt.as(:'s');
select tt.chk('A2 report_stock opens K2 F1 F2 F3 F4', (report_run2('k2_count_variance','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb)->>'report')='k2_count_variance' and (report_run2('f1_production','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb)->>'report')='f1_production'
  and (report_run2('f2_yield','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb)->>'report')='f2_yield' and (report_run2('f3_raw_vs_recipe','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb)->>'report')='f3_raw_vs_recipe' and (report_run2('f4_breakdowns','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb)->>'report')='f4_breakdowns');
select tt.chk('A2 catalog marks K2 open and the cost report P2 still closed', exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key'='k2_count_variance' and (c->>'allowed')::boolean) and exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key'='p2_rate_trend' and not (c->>'allowed')::boolean));
select tt.err('A2 purchase cost reports closed without report_purchase', $$select report_run2('p5_po_match','{}'::jsonb)$$, 'not allowed');
select report_run2('k2_count_variance','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L1 K2: place 1 only (3 rows, total counts 4)', tt.n(:'j'::jsonb)=3 and (:'j'::jsonb->'totals'->>'counts')::numeric=4 and not exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'location_bn' not like '%মেইন%'));
select tt.chk('L1 K2: a locations filter for place 2 gives nothing for this user', tt.n(report_run2('k2_count_variance','{"from":"2026-09-01","to":"2026-09-30","locations":[2]}'::jsonb))=0);
select tt.chk('L1 F1: 7 rows (3 runs incl. void, 3 sheet lines, 1 dispatch out of place 1)', tt.n(report_run2('f1_production','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb))=7);
select tt.chk('L1 F2: 2 rows', tt.n(report_run2('f2_yield','{"from":"2026-09-10","to":"2026-09-30"}'::jsonb))=2);
select tt.chk('L1 F3: 2 rows', tt.n(report_run2('f3_raw_vs_recipe','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb))=2);
select report_run2('f4_breakdowns','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L1 F4: 4 rows, no Fridge of place 2, totals downtime 6.5 est 700 actual 450', tt.n(:'j'::jsonb)=4 and tt.row(:'j'::jsonb,'machine','Fridge') is null and (:'j'::jsonb->'totals'->>'downtime_h')::numeric=6.5 and (:'j'::jsonb->'totals'->>'est_cost')::numeric=700 and (:'j'::jsonb->'totals'->>'actual_cost')::numeric=450);
select report_run2('m2_marketing_vs_sales','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L1 M2: 4 rows, spend 1100, sales 2200', tt.n(:'j'::jsonb)=4 and (:'j'::jsonb->'totals'->>'spend')::numeric=1100 and (:'j'::jsonb->'totals'->>'sales_total')::numeric=2200);
select report_run2('q1_fridge_temp','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L1 Q1: 5 rows, 3 out of range', tt.n(:'j'::jsonb)=5 and (:'j'::jsonb->'totals'->>'out_n')::numeric=3);
select tt.chk('L1 Q2: 4 sheets', tt.n(report_run2('q2_hygiene','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb))=4);
select report_run2('q3_complaints','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L1 Q3: 5 rows, 6 complaints/returns, place 2 late row hidden', tt.n(:'j'::jsonb)=5 and (:'j'::jsonb->'totals'->>'n')::numeric=6 and not exists (select 1 from jsonb_array_elements(:'j'::jsonb->'rows') x where x->>'cause' like 'দেরি%'));

\echo == cost reports
select tt.as(:'o'); select set_user_grant(:'r'::uuid,'report_purchase') is null as g4 \gset
select tt.as(:'r');
select tt.err('C1 report_purchase alone: P2 closed (cost)', $$select report_run2('p2_rate_trend','{}'::jsonb)$$, 'not allowed');
select tt.err('C1 report_purchase alone: P4 closed (cost)', $$select report_run2('p4_supplier_score','{}'::jsonb)$$, 'not allowed');
select tt.err('C1 report_purchase alone: P5 closed (cost)', $$select report_run2('p5_po_match','{}'::jsonb)$$, 'not allowed');
select tt.err('C1 report_purchase alone: P6 closed (cost)', $$select report_run2('p6_purchase_budget','{}'::jsonb)$$, 'not allowed');
select tt.chk('C1 catalog: all four cost reports closed for the grant-only user', not exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key' in ('p2_rate_trend','p4_supplier_score','p5_po_match','p6_purchase_budget') and (c->>'allowed')::boolean));
select tt.err('C1 a stock-only report is closed for a purchase-only user', $$select report_run2('f1_production','{}'::jsonb)$$, 'not allowed');
select tt.as(:'o'); select set_user_grant(:'s'::uuid,'report_purchase') is null as g5, set_user_grant(:'s'::uuid,'view_cost') is null as g6 \gset
select tt.as(:'s');
select tt.chk('C2 report_purchase + view_cost opens P2..P6', (report_run2('p2_rate_trend','{}'::jsonb)->>'report')='p2_rate_trend' and (report_run2('p4_supplier_score','{}'::jsonb)->>'report')='p4_supplier_score' and (report_run2('p5_po_match','{}'::jsonb)->>'report')='p5_po_match' and (report_run2('p6_purchase_budget','{}'::jsonb)->>'report')='p6_purchase_budget');
select report_run2('p2_rate_trend','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L2 P2 place 1 only: Sup B T-1 n 2, avg 94.7368, no T-2 row removed? (T-2 GRN is place 1: still 1 row)', (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'n')::int=2 and (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'avg_rate')::numeric=94.7368 and (tt.row(:'j'::jsonb,'supplier','Sup B','item_code','T-1')->>'min_rate')::numeric=90 and tt.n(:'j'::jsonb)=3);
select report_run2('p4_supplier_score','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L2 P4 place 1 only: Sup B 2 GRNs, 3 lines, 2 POs, 1 late, 1 overdue, 1 bill; rate change 10', (tt.row(:'j'::jsonb,'supplier','Sup B')->>'grns')::int=2 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'lines')::int=3 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'pos')::int=2
  and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'late_pos')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'overdue_open')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'bills_checked')::int=1 and (tt.row(:'j'::jsonb,'supplier','Sup B')->>'rate_change_pct')::numeric=10);
select report_run2('p5_po_match','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L2 P5 place 1 only: PO-7, PO-8, PO-10 (not PO-9)', tt.n(:'j'::jsonb)=3 and tt.row(:'j'::jsonb,'po_no','PO-9') is null);
select report_run2('p6_purchase_budget','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb) as j \gset
select tt.chk('L2 P6 place 1 only: 2 sheets', tt.n(:'j'::jsonb)=2);
select tt.as(:'o'); select set_user_grant(:'r'::uuid,'view_cost') is null as g7 \gset
select tt.as(:'r');
select tt.chk('L3 user of places 1+2 with purchase + cost right sees both places in P5 (4 POs), and a locations filter narrows it', tt.n(report_run2('p5_po_match','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb))=4 and tt.n(report_run2('p5_po_match','{"from":"2026-09-01","to":"2026-09-30","locations":[2]}'::jsonb))=1);

\echo == paste twice
reset role;
select count(*) as n_before from report_defs3 where key in ('p2_rate_trend','p4_supplier_score','p5_po_match','p6_purchase_budget','k2_count_variance','f1_production','f2_yield','f3_raw_vs_recipe','f4_breakdowns','m2_marketing_vs_sales','q1_fridge_temp','q2_hygiene','q3_complaints') \gset
\i supabase/phase26.sql
select tt.chk('R1 phase26 re-applied: still 13 rows, functions still private', (select count(*) from report_defs3 where key in ('p2_rate_trend','p4_supplier_score','p5_po_match','p6_purchase_budget','k2_count_variance','f1_production','f2_yield','f3_raw_vs_recipe','f4_breakdowns','m2_marketing_vs_sales','q1_fridge_temp','q2_hygiene','q3_complaints'))=:n_before
  and not has_function_privilege('authenticated','_r3q_f3_raw_vs_recipe(date,date,int[],jsonb)','execute'));
set role authenticated; select tt.as(:'o');
select tt.chk('R1 still answers after the re-apply', (select count(*) from jsonb_array_elements(report_run2('p4_supplier_score','{"from":"2026-09-01","to":"2026-09-30"}'::jsonb)->'rows'))=2);
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
