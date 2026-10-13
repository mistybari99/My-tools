-- FRESH DB ONLY. Phase 25 (reports S10 D5 M1 X2 X3 X4 X5 G2 K3 E2 E3 E4 W1 W2 on engine 3) tests.
--   ORDER="phase8 ... phase24 phase25" bash tests/sql/build_fresh_db.sh <db> ; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase25_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set r '00000000-0000-0000-0000-000000000003'
\set n '00000000-0000-0000-0000-000000000004'
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
create or replace function tt.pick(j jsonb, c jsonb) returns jsonb language sql as $$ select r from jsonb_array_elements(j -> 'rows') r where r @> c limit 1 $$;
create or replace function tt.num(j jsonb, k text) returns numeric language sql as $$ select (j ->> k)::numeric $$;
create or replace function tt.run(p_key text, p_flt jsonb default '{}') returns jsonb language sql as $$ select public.report_run2(p_key, p_flt, null, null, 1) $$;
create or replace function tt.sale(p_loc int, p_rec int, p_date date, p_total numeric, p_disc numeric, p_status text, p_cust uuid, p_staff text, p_due numeric, p_quick boolean, p_lines jsonb default '[]')
returns void language sql as $$
  insert into sales (client_id, location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, created_by, created_staff, paid, due_amount, quick, status, customer_id)
  values (gen_random_uuid(), p_loc, p_rec, p_date, p_date::timestamp at time zone 'Asia/Dhaka' + interval '12 hours', p_lines, p_total + p_disc, p_disc, p_total, 'cash', '00000000-0000-0000-0000-000000000002', p_staff, p_total - p_due, p_due, p_quick, p_status, p_cust); $$;
create or replace function tt.ent(p_form text, p_loc int, p_serial int, p_date date, p_status text, p_data jsonb, p_flags jsonb default '[]', p_check jsonb default '{}')
returns uuid language sql as $$
  insert into entries (form_code, location_id, serial, entry_date, status, data, flags, check_data, created_by, created_staff)
  values (p_form, p_loc, p_serial, p_date, p_status, p_data, p_flags, p_check, '00000000-0000-0000-0000-000000000002', 'st') returning id; $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'r','rep3@s.app','{"full_name":"Reporter"}'), (:'n','nog4@s.app','{"full_name":"NoGrant"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'r','salesperson'),(:'n','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'r',1),(:'r',2),(:'n',1) on conflict do nothing;

\echo == seed (as postgres)
select tt.as(:'o');
select set_user_grant(u::uuid, g) is null as gg from (values (:'s'),(:'r')) v(u), unnest(array['report_sales','report_orders','report_control','report_staff','report_stock','report_expense','report_marketing','report_cash']) g \gset
insert into customers (mobile, name) values ('01711000001','C1'),('01711000002','C2'),('01711000003','C3'),('01711000004','C4'),('01711000005','C5'),('01711000006','C6');
select id as c1 from customers where name='C1' \gset
select id as c2 from customers where name='C2' \gset
select id as c3 from customers where name='C3' \gset
select id as c4 from customers where name='C4' \gset
select id as c5 from customers where name='C5' \gset
select id as c6 from customers where name='C6' \gset
-- D5 / M1: end date 2026-06-30, D5 period 2026-06-21..2026-06-30, M1 window 2025-12-12..2026-06-30
select tt.sale(1, 9301, date '2026-06-30' - 100, 1000, 0, 'done', :'c1', 'st1', 0, false);
select tt.sale(1, 9302, date '2026-06-30' - 5, 200, 0, 'done', :'c1', 'st1', 0, false);
select tt.sale(1, 9303, date '2026-06-30' - 2, 300, 0, 'done', :'c1', 'st1', 0, false);
select tt.sale(1, 9304, date '2026-06-30' - 1, 100, 0, 'done', :'c1', 'st1', 0, false);
select tt.sale(1, 9305, date '2026-06-30' - 3, 500, 0, 'done', :'c2', 'st1', 0, false);
select tt.sale(1, 9306, date '2026-06-30' - 2, 777, 0, 'void', :'c2', 'st1', 0, false);
select tt.sale(1, 9307, date '2026-06-30' - 40, 400, 0, 'done', :'c3', 'st1', 0, false);
select tt.sale(1, 9308, date '2026-06-30' - 150, 100, 0, 'done', :'c4', 'st1', 0, false);
select tt.sale(1, 9309, date '2026-06-30' - 100, 200, 0, 'done', :'c4', 'st1', 0, false);
select tt.sale(1, 9310, date '2026-06-30' - 10, 40, 0, 'done', :'c5', 'st1', 0, false);
select tt.sale(1, 9311, date '2026-06-30' - 5, 60, 0, 'done', :'c5', 'st1', 0, false);
select tt.sale(2, 9312, date '2026-06-30' - 1, 999, 0, 'done', :'c6', 'st1', 0, false);
-- X5: sales by staff by month (Nov-Dec 2025)
select tt.sale(1, 9401, date '2025-11-10', 1000, 100, 'done', null, 'staffA', 150, true, '[{"override":true,"qty":1}]'::jsonb);
select tt.sale(1, 9402, date '2025-11-12', 500, 0, 'done', null, 'staffA', 0, false);
select tt.sale(1, 9403, date '2025-11-14', 300, 0, 'void', null, 'staffA', 0, false);
select tt.sale(1, 9404, date '2025-12-03', 400, 0, 'done', null, 'staffA', 0, false);
select tt.sale(2, 9405, date '2025-11-20', 200, 0, 'done', null, 'staffB', 0, false);
-- S10 (Feb 2026)
select tt.ent('20-1',1,1,date '2026-02-05','approved','{"channel":"counter","deliv_by":"pickup","total":1000,"discount":100,"advance":300,"cust_signed":true}');
select tt.ent('20-1',1,2,date '2026-02-06','submitted','{"channel":"message","online":"fb","deliv_by":"courier","total":"500","advance":500,"not_collected":true}');
select tt.ent('20-1',1,3,date '2026-02-07','approved','{"channel":"counter","deliv_by":"pickup","total":200}');
select tt.ent('20-1',1,4,date '2026-02-08','draft','{"channel":"counter","deliv_by":"pickup","total":9999}');
select tt.ent('20-1',2,1,date '2026-02-09','approved','{"channel":"phone","deliv_by":"own","total":900}');
select tt.ent('20-6',1,1,date '2026-02-10','approved','{"lines":[{"platform":"Foodpanda","delivery":"foodapp","amt":300,"dcharge":20,"outcome":"handed"},{"platform":"foodpanda","delivery":"foodapp","amt":200,"dcharge":10,"outcome":"returned"},{"platform":"pathao","delivery":"courier","amt":100,"dcharge":5,"outcome":"handed"}]}');
-- X2 (March 2026)
select tt.ent('14-1',1,2001,date '2026-03-05','approved','{}') as e1 \gset
select tt.ent('14-1',2,2002,date '2026-03-05','approved','{}') as e2 \gset
insert into release_requests (entry_id, flag_code, flag_amount, reason, status, requested_by, requested_staff, requested_at) values
 (:'e1','hub_diff',100,'r','approved',:'s','alice','2026-03-05 10:00+06'),(:'e1','hub_diff',50,'r','rejected',:'s','alice','2026-03-06 10:00+06'),
 (:'e1','cash_short_over',20,'r','pending',:'s','bob','2026-03-07 10:00+06'),(:'e2','hub_diff',10,'r','approved',:'s','alice','2026-03-08 10:00+06');
insert into emergency_requests (grant_code, requested_by, requested_staff, location_id, amount, reason, status, created_at) values
 ('report_sales',:'s','alice',1,200,'e','approved','2026-03-05 11:00+06'),('report_sales',:'s','bob',1,30,'e','used','2026-03-06 11:00+06'),('report_sales',:'s','alice',1,50,'e','expired','2026-03-07 11:00+06');
-- X3 audit log (March 2026)
insert into audit_log (staff_id, action, table_name, at) select 'alice','update','zz_t1','2026-03-15 10:00+06' from generate_series(1,3);
insert into audit_log (staff_id, action, table_name, at) values ('alice','insert','zz_t1','2026-03-15 10:00+06'),('bob','update','zz_t2','2026-03-16 10:00+06'),('bob','update','zz_t2','2026-03-17 10:00+06');
-- X4 (relative to today: period = last 10 days; ids 3001+)
select tt.ent('14-1',1,3001,current_date-1,'approved','{}');
select tt.ent('14-1',1,3002,current_date-1,'submitted','{}');
select tt.ent('14-1',1,3003,current_date-2,'approved','{}');
select tt.ent('14-1',1,3004,current_date-3,'approved','{}') as xl \gset
update entries set submitted_at = now() - interval '1 day' where id = :'xl';        -- Dhaka date = yesterday > entry_date (3 days ago): late
select tt.ent('14-1',1,3005,current_date-5,'draft','{}');                           -- stale draft
select tt.ent('14-1',1,3006,current_date,'draft','{}');                             -- today's draft is not stale
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff, submitted_at, entered_later, paper_serial, paper_at)
 values ('14-1',1,3007,current_date-6,'approved','{}',:'s','st',now(),true,'P-1',now() - interval '6 days');   -- entered later: never counted as late
select tt.ent('10-1',1,3008,current_date-4,'approved','{}');
-- G2 (April 2026, form 10-2)
select tt.ent('10-2',1,4001,date '2026-04-01','approved','{"paper_no":"101"}');
select tt.ent('10-2',1,4002,date '2026-04-02','approved','{"paper_no":"102"}');
select tt.ent('10-2',1,4003,date '2026-04-03','approved','{"paper_no":" 102 "}');
select tt.ent('10-2',1,4004,date '2026-04-05','approved','{"paper_no":"105"}');
select tt.ent('10-2',1,4005,date '2026-04-09','approved','{"paper_no":"104"}');
select tt.ent('10-2',1,4006,date '2026-04-06','approved','{}');
select tt.ent('10-2',1,4007,date '2026-04-07','submitted','{"paper_no":"A-9"}');
select tt.ent('10-2',1,4008,date '2026-04-08','draft','{"paper_no":"106"}');
select tt.ent('10-2',2,4001,date '2026-04-03','approved','{"paper_no":"201"}');
-- K3 (May 2026)
insert into items (code,name_bn,name_en,category,unit,tracked,is_active,sellable,sell_price) values ('T25-A','আইটেম এ','Item A','Sweets','kg',true,true,true,100),('T25-B','আইটেম বি','Item B','Sweets','kg',true,true,true,50),('T25-C','আইটেম সি','Item C','Cakes','pc',true,true,true,20);
select id as ia from items where code='T25-A' \gset
select id as ib from items where code='T25-B' \gset
select id as ic from items where code='T25-C' \gset
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, made_at) values
 (:'ia',1,10,55,'purchase_in','2026-05-10 10:00+06'),(:'ia',1,-3,null,'sale_out','2026-05-11 10:00+06'),(:'ia',1,-2,null,'sale_out','2026-05-11 11:00+06'),
 (:'ia',1,-1,null,'count_adjust','2026-05-12 10:00+06'),(:'ia',2,7,55,'purchase_in','2026-05-10 10:00+06'),(:'ib',1,5,20,'purchase_in','2026-05-10 10:00+06'),(:'ic',1,4,5,'purchase_in','2026-05-10 10:00+06'),
 (:'ia',1,9,null,'purchase_in','2026-04-01 10:00+06');
insert into stock_ledger (item_id, location_id, qty_delta, reason, reverses_id, made_at)
 select :'ia',1,2,'reversal',id,'2026-05-11 12:00+06' from stock_ledger where item_id=:'ia' and location_id=1 and qty_delta=-2 and reason='sale_out';
-- E2 (current 2026-05-11..05-20, previous 2026-05-01..05-10)
select tt.ent('10-2',1,5001,date '2026-05-12','approved','{"lines":[{"head":"transport","amount":100,"receipt":"yes"},{"head":"transport","amount":"50","receipt":"yes"},{"head":"repair","amount":300,"receipt":"yes"}]}');
select tt.ent('10-2',1,5002,date '2026-05-03','approved','{"lines":[{"head":"transport","amount":100,"receipt":"yes"},{"head":"labour","amount":40,"receipt":"yes"}]}');
select tt.ent('10-2',1,5003,date '2026-05-13','draft','{"lines":[{"head":"transport","amount":9999}]}');
select tt.ent('10-2',2,5001,date '2026-05-14','approved','{"lines":[{"head":"transport","amount":1000,"receipt":"yes"}]}');
-- E3 (July 2026)
select tt.ent('10-2',1,6001,date '2026-07-05','approved','{"approved_by":"mgr1","lines":[{"head":"transport","amount":100,"receipt":"yes"},{"head":"repair","amount":200,"receipt":"no"}]}','[{"code":"over_limit","amount":200}]');
select tt.ent('10-2',1,6002,date '2026-07-06','submitted','{"approved_by":" ","lines":[{"head":"transport","amount":50,"receipt":"no"},{"head":"transport","amount":30,"receipt":"no"}]}','[{"code":"receipt_reason_missing","amount":80},{"code":"imprest_mismatch","amount":-40}]');
select tt.ent('10-2',1,6003,date '2026-07-07','draft','{"approved_by":"mgr1","lines":[{"head":"transport","amount":999,"receipt":"no"}]}');
select tt.ent('10-2',2,6001,date '2026-07-08','approved','{"approved_by":"mgr1","lines":[{"head":"transport","amount":70,"receipt":"no"}]}');
select tt.ent('14-1',1,6101,date '2026-07-05','approved','{}','[{"code":"open_imprest_diff","amount":25}]');
select tt.ent('14-1',1,6102,date '2026-07-06','approved','{}');
select tt.ent('14-1',1,6103,date '2026-07-07','draft','{}','[{"code":"open_imprest_diff","amount":99}]');
-- E4 (August 2026): head 1 has a limit in the option list (1000), head 2 a per-location setting (400), the rest none
update option_lists set extra = '{"limit_month":1000}'::jsonb where list_code='marketing_heads' and value_code='1';
insert into location_settings (location_id, key, value) values (1, 'mkt_limit_2', '400'::jsonb) on conflict (location_id, key) do update set value = excluded.value;
select tt.ent('18-1',1,7001,date '2026-08-05','approved','{"lines":[{"date":"2026-08-05","head":"1","amt":800},{"date":"2026-08-20","head":"1","amt":700},{"date":"2026-08-21","head":"2","amt":300},{"date":"2026-08-22","head":"other:xyz","amt":50},{"head":"3","nonpay":500},{"date":"junk","head":"3","amt":10},{"date":"2026-09-05","head":"1","amt":999}]}');
select tt.ent('18-1',1,7002,date '2026-08-06','draft','{"lines":[{"date":"2026-08-06","head":"1","amt":5000}]}');
select tt.ent('18-1',2,7001,date '2026-08-10','approved','{"lines":[{"date":"2026-08-10","head":"1","amt":100}]}');
-- W1 (2026-09-01..09-07)
insert into sale_payments (location_id, kind, mode, amount, paid_at, created_staff) values
 (1,'collection','cash',1000,'2026-09-02 10:00+06','st'),(1,'collection','cash',400,'2026-09-02 11:00+06','st'),(1,'collection','mobile',300,'2026-09-02 12:00+06','st'),(2,'collection','cash',250,'2026-09-03 10:00+06','st');
insert into sale_payments (location_id, kind, mode, amount, paid_at, created_staff, voided) values (1,'collection','cash',5000,'2026-09-02 13:00+06','st',true);
select tt.ent('10-2',1,8001,date '2026-09-02','approved','{"lines":[{"head":"transport","amount":150,"receipt":"yes"},{"head":"repair","amount":50,"receipt":"yes"}]}');
select tt.ent('10-1',1,8002,date '2026-09-02','approved','{"carrier":"W","count":{"n1000":3},"leave_float":500}');
select tt.ent('02-2',1,8003,date '2026-09-02','approved','{"receipts":[{"name":"x","net":9000,"method":"cash","date":"2026-09-02"}]}');
-- W2 (2026-03-20..03-25)
select tt.ent('10-1',1,9001,date '2026-03-20','approved','{"carrier":"Rafiq","count":{"n1000":5},"leave_float":500}','[]','{"rcount":{"n1000":4,"n500":1}}');
select tt.ent('10-1',1,9002,date '2026-03-21','approved','{"carrier":"Rafiq","count":{"n1000":3},"leave_float":0}','[]','{"rcount":{"n1000":2,"n500":1}}');
select tt.ent('10-1',1,9003,date '2026-03-22','submitted','{"carrier":"Karim","count":{"n500":4},"leave_float":0}');
select tt.ent('10-1',2,9001,date '2026-03-23','approved','{"carrier":"Rafiq","count":{"n1000":1},"leave_float":0}','[]','{"rcount":{"n1000":1,"n200":1}}');
select tt.ent('10-1',1,9004,date '2026-03-24','draft','{"carrier":"Rafiq","count":{"n1000":9},"leave_float":0}','[]','{"rcount":{"n1000":1}}');
select tt.ent('10-1',1,9005,date '2026-03-25','approved','{"carrier":"Hasan","count":{"n1000":1},"leave_float":0}') as eh \gset
insert into entry_counts (entry_id, section, counted_detail, counted, expected, diff, counted_by) values (:'eh','hub','{"n500":1,"n200":2,"n100":1}'::jsonb, 900, 1000, -100, :'s');

select _r3_lockdown() as ld \gset
\echo == catalog
select tt.as(:'o'); set role authenticated;
select tt.chk('T0 all 14 reports registered, bilingual, with columns', (select count(*) from report_defs3 where key in ('s10_orders','d5_lapsed','m1_rfm','x2_bypass','x3_audit_log','x4_compliance','x5_staff_trend','g2_paper_numbers','k3_store_ledger','e2_expense_trend','e3_weak_control','e4_marketing_limit','w1_cash_flow','w2_handover_vs_hub') and name_bn <> '' and name_en <> '' and jsonb_array_length(cols) > 3) = 14);
select tt.chk('T0 report functions are private', not has_function_privilege('authenticated','_r3q_s10_orders(date,date,int[],jsonb)','execute') and not has_function_privilege('authenticated','_r3q_w2_handover_vs_hub(date,date,int[],jsonb)','execute'));
select tt.chk('T0 X3 is owner-only, no report is cost', (select owner_only from report_defs3 where key='x3_audit_log') and not exists (select 1 from report_defs3 where key in ('s10_orders','d5_lapsed','m1_rfm','x2_bypass','x3_audit_log','x4_compliance','x5_staff_trend','g2_paper_numbers','k3_store_ledger','e2_expense_trend','e3_weak_control','e4_marketing_limit','w1_cash_flow','w2_handover_vs_hub') and cost));

\echo == S10
select tt.run('s10_orders','{"from":"2026-02-01","to":"2026-02-28"}') as j \gset
select tt.chk('S10 counter/pickup group: 2 orders, 1200, advance 300, balance 800, 1 handed', tt.num(tt.pick(:'j','{"source":"20-1","channel":"counter","delivery":"pickup"}'),'orders')=2 and tt.num(tt.pick(:'j','{"source":"20-1","channel":"counter","delivery":"pickup"}'),'amount')=1200 and tt.num(tt.pick(:'j','{"source":"20-1","channel":"counter","delivery":"pickup"}'),'advance')=300 and tt.num(tt.pick(:'j','{"source":"20-1","channel":"counter","delivery":"pickup"}'),'balance')=800 and tt.num(tt.pick(:'j','{"source":"20-1","channel":"counter","delivery":"pickup"}'),'handed')=1);
select tt.chk('S10 message/fb/courier: 500 paid in advance, balance 0, 1 not collected (string amount read)', tt.num(tt.pick(:'j','{"channel":"message","online":"fb","delivery":"courier"}'),'amount')=500 and tt.num(tt.pick(:'j','{"channel":"message","online":"fb"}'),'balance')=0 and tt.num(tt.pick(:'j','{"channel":"message","online":"fb"}'),'not_collected')=1);
select tt.chk('S10 ledger rows: foodpanda grouped case-insensitively 2 orders 500, 1 handed, 1 returned, charge 30', tt.num(tt.pick(:'j','{"source":"20-6","online":"foodpanda"}'),'orders')=2 and tt.num(tt.pick(:'j','{"source":"20-6","online":"foodpanda"}'),'amount')=500 and tt.num(tt.pick(:'j','{"source":"20-6","online":"foodpanda"}'),'returned')=1 and tt.num(tt.pick(:'j','{"source":"20-6","online":"foodpanda"}'),'delivery_charge')=30 and tt.num(tt.pick(:'j','{"source":"20-6","online":"pathao"}'),'handed')=1);
select tt.chk('S10 ledger rows have null advance/balance (not captured there)', (tt.pick(:'j','{"source":"20-6","online":"pathao"}')->'advance') = 'null'::jsonb);
select tt.chk('S10 totals: 7 orders, 3200 (draft excluded)', tt.num(:'j'::jsonb->'totals','orders')=7 and tt.num(:'j'::jsonb->'totals','amount')=3200);
select tt.as(:'s'); select tt.run('s10_orders','{"from":"2026-02-01","to":"2026-02-28"}') as j \gset
select tt.chk('S10 location-1 user: 6 orders, 2300; phone/own (loc 2) absent', tt.num(:'j'::jsonb->'totals','orders')=6 and tt.num(:'j'::jsonb->'totals','amount')=2300 and tt.pick(:'j','{"channel":"phone"}') is null);

\echo == D5
select tt.as(:'o'); select tt.run('d5_lapsed','{"from":"2026-06-21","to":"2026-06-30"}') as j \gset
select tt.chk('D5 C1 repeat: 3 orders, 600 in period, 4 in all, silent 1 day', tt.pick(:'j','{"name":"C1","kind":"repeat"}') is not null and tt.num(tt.pick(:'j','{"name":"C1"}'),'orders_period')=3 and tt.num(tt.pick(:'j','{"name":"C1"}'),'amount_period')=600 and tt.num(tt.pick(:'j','{"name":"C1"}'),'orders_total')=4 and tt.num(tt.pick(:'j','{"name":"C1"}'),'days_silent')=1);
select tt.chk('D5 C2 new: 500, the void sale ignored', tt.pick(:'j','{"name":"C2","kind":"new"}') is not null and tt.num(tt.pick(:'j','{"name":"C2"}'),'amount_period')=500 and tt.num(tt.pick(:'j','{"name":"C2"}'),'orders_total')=1);
select tt.chk('D5 C3 and C4 lapsed with days silent 40 and 100', tt.pick(:'j','{"name":"C3","kind":"lapsed","days_silent":40}') is not null and tt.pick(:'j','{"name":"C4","kind":"lapsed","days_silent":100}') is not null);
select tt.chk('D5 C5 repeat (first buy before the period), C6 new in loc 2', tt.pick(:'j','{"name":"C5","kind":"repeat"}') is not null and tt.num(tt.pick(:'j','{"name":"C5"}'),'amount_period')=60 and tt.pick(:'j','{"name":"C6","kind":"new"}') is not null);
select tt.chk('D5 totals: 6 rows, 6 orders, 2159', jsonb_array_length(:'j'::jsonb->'rows')=6 and tt.num(:'j'::jsonb->'totals','orders_period')=6 and tt.num(:'j'::jsonb->'totals','amount_period')=2159);
select tt.as(:'s'); select tt.run('d5_lapsed','{"from":"2026-06-21","to":"2026-06-30"}') as j \gset
select tt.chk('D5 loc-1 user: 5 rows, 1160, no C6', jsonb_array_length(:'j'::jsonb->'rows')=5 and tt.num(:'j'::jsonb->'totals','amount_period')=1160 and tt.pick(:'j','{"name":"C6"}') is null);

\echo == M1
select tt.as(:'o'); select tt.run('m1_rfm','{"from":"2025-12-12","to":"2026-06-30"}') as j \gset
select tt.chk('M1 C1 Champion: 4 orders, 1600, recency 1', tt.pick(:'j','{"name":"C1","segment":"Champion","frequency":4,"recency_days":1}') is not null and tt.num(tt.pick(:'j','{"name":"C1"}'),'monetary')=1600);
select tt.chk('M1 C4 At-risk (2 orders, silent 100 days)', tt.pick(:'j','{"name":"C4","segment":"At-risk","recency_days":100,"frequency":2}') is not null);
select tt.chk('M1 C2, C3, C6 One-time; C5 Regular', tt.pick(:'j','{"name":"C2","segment":"One-time"}') is not null and tt.pick(:'j','{"name":"C3","segment":"One-time"}') is not null and tt.pick(:'j','{"name":"C6","segment":"One-time"}') is not null and tt.pick(:'j','{"name":"C5","segment":"Regular"}') is not null);
select tt.chk('M1 totals: 6 customers; frequency 4+1+1+2+2+1=11', jsonb_array_length(:'j'::jsonb->'rows')=6 and tt.num(:'j'::jsonb->'totals','frequency')=11);
select tt.as(:'s'); select tt.run('m1_rfm','{"from":"2025-12-12","to":"2026-06-30"}') as j \gset
select tt.chk('M1 loc-1 user: 5 customers, no C6', jsonb_array_length(:'j'::jsonb->'rows')=5 and tt.pick(:'j','{"name":"C6"}') is null);

\echo == X2
select tt.as(:'o'); select tt.run('x2_bypass','{"from":"2026-03-01","to":"2026-03-31"}') as j \gset
select tt.chk('X2 alice releases hub_diff: 3 requests, 2 approved, 1 rejected, 160', tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"release","code":"hub_diff"}'),'requests')=3 and tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"release","code":"hub_diff"}'),'approved')=2 and tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"release","code":"hub_diff"}'),'rejected')=1 and tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"release","code":"hub_diff"}'),'amount')=160);
select tt.chk('X2 bob release pending 1 (20)', tt.num(tt.pick(:'j','{"staff_id":"bob","kind":"release"}'),'pending')=1 and tt.num(tt.pick(:'j','{"staff_id":"bob","kind":"release"}'),'amount')=20);
select tt.chk('X2 emergency: alice 2 requests, 1 approved, 1 expired, 250; bob used counts as approved', tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"emergency"}'),'requests')=2 and tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"emergency"}'),'approved')=1 and tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"emergency"}'),'other')=1 and tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"emergency"}'),'amount')=250 and tt.num(tt.pick(:'j','{"staff_id":"bob","kind":"emergency"}'),'approved')=1);
select tt.chk('X2 totals: 7 requests', tt.num(:'j'::jsonb->'totals','requests')=7);
select tt.run('x2_bypass','{"from":"2026-04-01","to":"2026-04-30"}') as j0 \gset
select tt.chk('X2 other month: no rows = data needed', (:'j0'::jsonb->>'data_needed')::boolean);
select tt.as(:'s'); select tt.run('x2_bypass','{"from":"2026-03-01","to":"2026-03-31"}') as j \gset
select tt.chk('X2 loc-1 user: alice release hub_diff only 2 (the loc-2 one is hidden); total 6', tt.num(tt.pick(:'j','{"staff_id":"alice","kind":"release"}'),'requests')=2 and tt.num(:'j'::jsonb->'totals','requests')=6);

\echo == X3
select tt.as(:'o'); select tt.run('x3_audit_log','{"from":"2026-03-01","to":"2026-03-31"}') as j \gset
select tt.chk('X3 alice update zz_t1: 3 events; insert 1; bob zz_t2 2 events over 2 days', tt.num(tt.pick(:'j','{"table_name":"zz_t1","action":"update","staff_id":"alice"}'),'events')=3 and tt.num(tt.pick(:'j','{"table_name":"zz_t1","action":"insert"}'),'events')=1 and tt.num(tt.pick(:'j','{"table_name":"zz_t2","staff_id":"bob"}'),'events')=2 and tt.pick(:'j','{"table_name":"zz_t2","first_day":"2026-03-16","last_day":"2026-03-17"}') is not null);
select tt.as(:'r'); select tt.err('X3 owner-only: a report_control grant is not enough', $$select tt.run('x3_audit_log','{}')$$, 'not allowed');

\echo == X4
select tt.as(:'o'); select tt.run('x4_compliance',format('{"from":"%s","to":"%s"}', current_date-9, current_date)::jsonb) as j \gset
select tt.chk('X4 loc1 14-1: 10 days, 3 submitted days (two sheets one day), 7 missing, 30%, 1 stale draft, 1 late (entered-later not counted)', tt.num(tt.pick(:'j','{"location_id":1,"form":"14-1"}'),'days')=10 and tt.num(tt.pick(:'j','{"location_id":1,"form":"14-1"}'),'submitted_days')=3 and tt.num(tt.pick(:'j','{"location_id":1,"form":"14-1"}'),'missing_days')=7 and tt.num(tt.pick(:'j','{"location_id":1,"form":"14-1"}'),'compliance_pct')=30 and tt.num(tt.pick(:'j','{"location_id":1,"form":"14-1"}'),'stale_drafts')=1 and tt.num(tt.pick(:'j','{"location_id":1,"form":"14-1"}'),'late_submits')=1);
select tt.chk('X4 loc1 10-1: 1 submitted day, 9 missing, 10%', tt.num(tt.pick(:'j','{"location_id":1,"form":"10-1"}'),'submitted_days')=1 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-1"}'),'missing_days')=9 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-1"}'),'compliance_pct')=10);
select tt.chk('X4 loc2 never submitted: 0%; only live showrooms (4 shops x 2 forms = 8 rows; factories/godown absent)', tt.num(tt.pick(:'j','{"location_id":2,"form":"14-1"}'),'compliance_pct')=0 and jsonb_array_length(:'j'::jsonb->'rows')=8);
select tt.chk('X4 a future end date does not add missing days (to = today + 5)', tt.num(tt.pick(tt.run('x4_compliance',format('{"from":"%s","to":"%s"}', current_date-9, current_date+5)::jsonb),'{"location_id":1,"form":"14-1"}'),'days')=10);
select tt.as(:'s'); select tt.run('x4_compliance',format('{"from":"%s","to":"%s"}', current_date-9, current_date)::jsonb) as j \gset
select tt.chk('X4 loc-1 user: only location 1 (2 rows)', jsonb_array_length(:'j'::jsonb->'rows')=2 and tt.pick(:'j','{"location_id":2}') is null);

\echo == X5
select tt.as(:'o'); select tt.run('x5_staff_trend','{"from":"2025-10-01","to":"2025-12-31"}') as j \gset
select tt.chk('X5 staffA Nov: 2 sales, 1500, discount 6.25%, void 33.33%, override 50%, quick 50%, due 10%', tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-11-01"}'),'orders')=2 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-11-01"}'),'revenue')=1500 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-11-01"}'),'discount_pct')=6.25 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-11-01"}'),'void_pct')=33.33 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-11-01"}'),'override_pct')=50 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-11-01"}'),'quick_pct')=50 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-11-01"}'),'due_pct')=10);
select tt.chk('X5 staffA Dec: 1 sale 400, all percentages 0', tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-12-01"}'),'revenue')=400 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-12-01"}'),'discount_pct')=0 and tt.num(tt.pick(:'j','{"staff_id":"staffA","month":"2025-12-01"}'),'void_pct')=0);
select tt.chk('X5 same numbers as biz_staff for November', (select discount_pct from biz_staff('2025-11-01','2025-11-30',1) where staff_id='staffA') = 6.25 and (select void_pct from biz_staff('2025-11-01','2025-11-30',1) where staff_id='staffA') = 33.33);
select tt.chk('X5 totals: 4 sales, 2100 (staffB in loc 2 included for the owner)', tt.num(:'j'::jsonb->'totals','orders')=4 and tt.num(:'j'::jsonb->'totals','revenue')=2100);
select tt.as(:'s'); select tt.run('x5_staff_trend','{"from":"2025-10-01","to":"2025-12-31"}') as j \gset
select tt.chk('X5 loc-1 user: no staffB, 3 sales 1900', tt.pick(:'j','{"staff_id":"staffB"}') is null and tt.num(:'j'::jsonb->'totals','revenue')=1900);

\echo == G2
select tt.as(:'o'); select tt.run('g2_paper_numbers','{"from":"2026-04-01","to":"2026-04-30"}') as j \gset
select tt.chk('G2 loc1 10-2: 7 entries, 1 without number, 5 distinct, 1 duplicate (trimmed), 1 out of order', tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'entries')=7 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'no_paper_no')=1 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'distinct_numbers')=5 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'duplicate_numbers')=1 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'out_of_order')=1);
select tt.chk('G2 book usage: first 101, last 105, 1 number missing (103); draft 106 ignored', tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'first_no')=101 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'last_no')=105 and tt.num(tt.pick(:'j','{"location_id":1,"form":"10-2"}'),'missing_numbers')=1);
select tt.chk('G2 loc2 book is separate and clean', tt.num(tt.pick(:'j','{"location_id":2,"form":"10-2"}'),'duplicate_numbers')=0 and tt.num(tt.pick(:'j','{"location_id":2,"form":"10-2"}'),'missing_numbers')=0);
select tt.as(:'s'); select tt.run('g2_paper_numbers','{"from":"2026-04-01","to":"2026-04-30"}') as j \gset
select tt.chk('G2 loc-1 user: loc 2 book hidden', tt.pick(:'j','{"location_id":2}') is null and tt.pick(:'j','{"location_id":1}') is not null);

\echo == K3
select tt.as(:'o'); select tt.run('k3_store_ledger','{"from":"2026-05-01","to":"2026-05-31"}') as j \gset
select tt.chk('K3 item A purchase_in: 2 movements, in 17 (loc1 10 + loc2 7); April row outside the period', tt.num(tt.pick(:'j','{"item_code":"T25-A","kind":"purchase_in"}'),'movements')=2 and tt.num(tt.pick(:'j','{"item_code":"T25-A","kind":"purchase_in"}'),'in_qty')=17);
select tt.chk('K3 item A sale_out: the reversed sale (-2) and its reversal are both left out, so 1 movement, out 3', tt.num(tt.pick(:'j','{"item_code":"T25-A","kind":"sale_out"}'),'movements')=1 and tt.num(tt.pick(:'j','{"item_code":"T25-A","kind":"sale_out"}'),'out_qty')=3 and tt.num(tt.pick(:'j','{"item_code":"T25-A","kind":"sale_out"}'),'net_qty')=-3 and tt.pick(:'j','{"kind":"reversal"}') is null);
select tt.chk('K3 count_adjust out 1; B in 5; C in 4; no value columns', tt.num(tt.pick(:'j','{"item_code":"T25-A","kind":"count_adjust"}'),'out_qty')=1 and tt.num(tt.pick(:'j','{"item_code":"T25-B"}'),'in_qty')=5 and tt.num(tt.pick(:'j','{"item_code":"T25-C"}'),'in_qty')=4 and not (:'j'::jsonb->'rows'->0 ? 'value'));
select tt.chk('K3 categories filter: Cakes only', (select count(*) from jsonb_array_elements(tt.run('k3_store_ledger','{"from":"2026-05-01","to":"2026-05-31","categories":["Cakes"]}')->'rows') r where r->>'item_code'='T25-C') = 1 and jsonb_array_length(tt.run('k3_store_ledger','{"from":"2026-05-01","to":"2026-05-31","categories":["Cakes"]}')->'rows')=1);
select tt.as(:'s'); select tt.run('k3_store_ledger','{"from":"2026-05-01","to":"2026-05-31"}') as j \gset
select tt.chk('K3 loc-1 user: item A purchase_in 10 only', tt.num(tt.pick(:'j','{"item_code":"T25-A","kind":"purchase_in"}'),'in_qty')=10);

\echo == E2
select tt.as(:'o'); select tt.run('e2_expense_trend','{"from":"2026-05-11","to":"2026-05-20"}') as j \gset
select tt.chk('E2 transport (owner, both locations): current 1150, previous 100, label from the head list', tt.num(tt.pick(:'j','{"head":"যাতায়াত / পরিবহন"}'),'current')=1150 and tt.num(tt.pick(:'j','{"head":"যাতায়াত / পরিবহন"}'),'previous')=100 and tt.num(tt.pick(:'j','{"head":"যাতায়াত / পরিবহন"}'),'change')=1050 and tt.num(tt.pick(:'j','{"head":"যাতায়াত / পরিবহন"}'),'change_pct')=1050);
select tt.chk('E2 new head repair: previous 0 -> change_pct null; vanished head labour: -40, -100%', tt.num(tt.pick(:'j','{"head":"মেরামত / ইউটিলিটি"}'),'current')=300 and (tt.pick(:'j','{"head":"মেরামত / ইউটিলিটি"}')->'change_pct')='null'::jsonb and tt.num(tt.pick(:'j','{"head":"labour"}'),'change')=-40 and tt.num(tt.pick(:'j','{"head":"labour"}'),'change_pct')=-100);
select tt.chk('E2 totals: current 1450, previous 140 (draft 9999 excluded)', tt.num(:'j'::jsonb->'totals','current')=1450 and tt.num(:'j'::jsonb->'totals','previous')=140);
select tt.as(:'s'); select tt.run('e2_expense_trend','{"from":"2026-05-11","to":"2026-05-20"}') as j \gset
select tt.chk('E2 loc-1 user: transport current 150 only', tt.num(tt.pick(:'j','{"head":"যাতায়াত / পরিবহন"}'),'current')=150 and tt.num(:'j'::jsonb->'totals','current')=450);

\echo == E3
select tt.as(:'o'); select tt.run('e3_weak_control','{"from":"2026-07-01","to":"2026-07-31"}') as j \gset
select tt.chk('E3 loc1 mgr1: 1 voucher, 1 no-receipt line 200, over-limit 1 (200)', tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"mgr1"}'),'no_receipt_lines')=1 and tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"mgr1"}'),'no_receipt_amount')=200 and tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"mgr1"}'),'over_limit_vouchers')=1 and tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"mgr1"}'),'over_limit_amount')=200);
select tt.chk('E3 loc1 no approver ("-"): 2 no-receipt lines 80, reason missing 1, imprest mismatch 1 / 40', tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"-"}'),'no_receipt_lines')=2 and tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"-"}'),'no_receipt_amount')=80 and tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"-"}'),'reason_missing')=1 and tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"-"}'),'imprest_diff_sheets')=1 and tt.num(tt.pick(:'j','{"location_id":1,"source":"10-2","approver":"-"}'),'imprest_diff_amount')=40);
select tt.chk('E3 14-1 imprest: loc1 2 sheets, 1 with a difference of 25 (draft 99 excluded)', tt.num(tt.pick(:'j','{"location_id":1,"source":"14-1"}'),'vouchers')=2 and tt.num(tt.pick(:'j','{"location_id":1,"source":"14-1"}'),'imprest_diff_sheets')=1 and tt.num(tt.pick(:'j','{"location_id":1,"source":"14-1"}'),'imprest_diff_amount')=25);
select tt.chk('E3 totals: 5 vouchers/sheets, no-receipt 350 (draft 999 excluded)', tt.num(:'j'::jsonb->'totals','vouchers')=5 and tt.num(:'j'::jsonb->'totals','no_receipt_amount')=350);
select tt.as(:'s'); select tt.run('e3_weak_control','{"from":"2026-07-01","to":"2026-07-31"}') as j \gset
select tt.chk('E3 loc-1 user: no-receipt 280, loc-2 row hidden', tt.num(:'j'::jsonb->'totals','no_receipt_amount')=280 and tt.pick(:'j','{"location_id":2}') is null);

\echo == E4
select tt.as(:'o'); select tt.run('e4_marketing_limit','{"from":"2026-08-01","to":"2026-08-31"}') as j \gset
select tt.chk('E4 head 1 loc1 Aug: spend 1500 vs list limit 1000 = 150%, over 500 (draft and Sept line excluded)', tt.num(tt.pick(:'j','{"location_id":1,"head":"অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)"}'),'spend')=1500 and tt.num(tt.pick(:'j','{"location_id":1,"head":"অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)"}'),'limit')=1000 and tt.num(tt.pick(:'j','{"location_id":1,"head":"অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)"}'),'used_pct')=150 and tt.num(tt.pick(:'j','{"location_id":1,"head":"অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)"}'),'over_amount')=500);
select tt.chk('E4 head 2: limit 400 from the location setting, 75%, not over', tt.num(tt.pick(:'j','{"location_id":1,"head":"কনটেন্ট তৈরি"}'),'limit')=400 and tt.num(tt.pick(:'j','{"location_id":1,"head":"কনটেন্ট তৈরি"}'),'used_pct')=75 and tt.num(tt.pick(:'j','{"location_id":1,"head":"কনটেন্ট তৈরি"}'),'over_amount')=0);
select tt.chk('E4 no limit captured: limit null, used_pct null, over null (other:xyz folds into other)', (tt.pick(:'j','{"location_id":1,"head":"other"}')->'limit')='null'::jsonb and (tt.pick(:'j','{"location_id":1,"head":"other"}')->'used_pct')='null'::jsonb and (tt.pick(:'j','{"location_id":1,"head":"other"}')->'over_amount')='null'::jsonb and tt.num(tt.pick(:'j','{"location_id":1,"head":"other"}'),'spend')=50);
select tt.chk('E4 unreadable line date falls back to the entry date (head 3: 10, no limit); non-paid line ignored', tt.num(tt.pick(:'j','{"location_id":1,"head":"ছাপা"}'),'spend')=10);
select tt.chk('E4 loc2 head 1: 100 of 1000 = 10%; totals spend 1960, over 500', tt.num(tt.pick(:'j','{"location_id":2,"head":"অনলাইন বিজ্ঞাপন ও বুস্ট (ভ্যাটসহ)"}'),'used_pct')=10 and tt.num(:'j'::jsonb->'totals','spend')=1960 and tt.num(:'j'::jsonb->'totals','over_amount')=500);
select tt.as(:'s'); select tt.run('e4_marketing_limit','{"from":"2026-08-01","to":"2026-08-31"}') as j \gset
select tt.chk('E4 loc-1 user: spend 1860, loc-2 row hidden', tt.num(:'j'::jsonb->'totals','spend')=1860 and tt.pick(:'j','{"location_id":2}') is null);

\echo == W1
select tt.as(:'o'); select tt.run('w1_cash_flow','{"from":"2026-09-01","to":"2026-09-07"}') as j \gset
select tt.chk('W1 loc1 2026-09-02: cash in 1400, cash out 200 (voucher), net 1200, mobile in 300', tt.num(tt.pick(:'j','{"location_id":1,"day":"2026-09-02"}'),'cash_in')=1400 and tt.num(tt.pick(:'j','{"location_id":1,"day":"2026-09-02"}'),'cash_out')=200 and tt.num(tt.pick(:'j','{"location_id":1,"day":"2026-09-02"}'),'net_cash')=1200 and tt.num(tt.pick(:'j','{"location_id":1,"day":"2026-09-02"}'),'other_in')=300);
select tt.chk('W1 internal handover (2500) and salary (9000) excluded, voided payment (5000) excluded', tt.num(:'j'::jsonb->'totals','cash_out')=200 and tt.num(:'j'::jsonb->'totals','cash_in')=1650);
select tt.chk('W1 loc2 2026-09-03 cash in 250; totals net 1450', tt.num(tt.pick(:'j','{"location_id":2,"day":"2026-09-03"}'),'cash_in')=250 and tt.num(:'j'::jsonb->'totals','net_cash')=1450);
select tt.as(:'s'); select tt.run('w1_cash_flow','{"from":"2026-09-01","to":"2026-09-07"}') as j \gset
select tt.chk('W1 loc-1 user: cash in 1400 only', tt.num(:'j'::jsonb->'totals','cash_in')=1400 and tt.pick(:'j','{"location_id":2}') is null);

\echo == W2
select tt.as(:'o'); select tt.run('w2_handover_vs_hub','{"from":"2026-03-20","to":"2026-03-25"}') as j \gset
select tt.chk('W2 loc1 Rafiq: 2 slips, handover 7500, hub 7000, diff -500, 1 short (draft excluded)', tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Rafiq"}'),'slips')=2 and tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Rafiq"}'),'handover')=7500 and tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Rafiq"}'),'hub_received')=7000 and tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Rafiq"}'),'diff')=-500 and tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Rafiq"}'),'short_slips')=1);
select tt.chk('W2 Karim: not counted at hub -> hub and diff null, not_counted 1', (tt.pick(:'j','{"location_id":1,"carrier":"Karim"}')->'hub_received')='null'::jsonb and (tt.pick(:'j','{"location_id":1,"carrier":"Karim"}')->'diff')='null'::jsonb and tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Karim"}'),'not_counted')=1 and tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Karim"}'),'handover')=2000);
select tt.chk('W2 Hasan: hub count from entry_counts 900 vs 1000 = -100', tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Hasan"}'),'hub_received')=900 and tt.num(tt.pick(:'j','{"location_id":1,"carrier":"Hasan"}'),'diff')=-100);
select tt.chk('W2 loc2 Rafiq over by 200', tt.num(tt.pick(:'j','{"location_id":2,"carrier":"Rafiq"}'),'diff')=200 and tt.num(tt.pick(:'j','{"location_id":2,"carrier":"Rafiq"}'),'over_slips')=1);
select tt.chk('W2 totals: diff -500-100+200 = -400, 5 slips', tt.num(:'j'::jsonb->'totals','diff')=-400 and tt.num(:'j'::jsonb->'totals','slips')=5);
select tt.as(:'s'); select tt.run('w2_handover_vs_hub','{"from":"2026-03-20","to":"2026-03-25"}') as j \gset
select tt.chk('W2 loc-1 user: diff -600, loc 2 hidden', tt.num(:'j'::jsonb->'totals','diff')=-600 and tt.pick(:'j','{"location_id":2}') is null);

\echo == access
select tt.as(:'n');
select tt.err('A1 no grant: ' || k, format($$select report_run2(%L,'{}'::jsonb)$$, k), 'not allowed') from unnest(array['s10_orders','d5_lapsed','m1_rfm','x2_bypass','x3_audit_log','x4_compliance','x5_staff_trend','g2_paper_numbers','k3_store_ledger','e2_expense_trend','e3_weak_control','e4_marketing_limit','w1_cash_flow','w2_handover_vs_hub']) k;
select tt.chk('A2 catalog: allowed for a granted user, closed for the ungranted one', exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key'='w1_cash_flow' and not (c->>'allowed')::boolean));
select tt.as(:'s'); select tt.chk('A2 catalog: granted user sees them allowed (except X3)', (select count(*) from jsonb_array_elements(report_catalog2()) c where c->>'key' in ('s10_orders','d5_lapsed','m1_rfm','x2_bypass','x4_compliance','x5_staff_trend','g2_paper_numbers','k3_store_ledger','e2_expense_trend','e3_weak_control','e4_marketing_limit','w1_cash_flow','w2_handover_vs_hub') and (c->>'allowed')::boolean)=13 and exists (select 1 from jsonb_array_elements(report_catalog2()) c where c->>'key'='x3_audit_log' and not (c->>'allowed')::boolean));
reset role;
-- a grant for only one group opens only that group's reports
select tt.as(:'o'); set role authenticated;
select set_user_grant(:'n'::uuid,'report_cash') is null as gn \gset
select tt.as(:'n');
select tt.chk('A3 report_cash alone: W1 and W2 open', (report_run2('w1_cash_flow','{"from":"2026-09-01","to":"2026-09-07"}')->>'report')='w1_cash_flow' and (report_run2('w2_handover_vs_hub','{"from":"2026-03-20","to":"2026-03-25"}')->>'report')='w2_handover_vs_hub');
select tt.err('A3 report_cash alone: S10 (orders group) stays closed', $$select report_run2('s10_orders','{}'::jsonb)$$, 'not allowed');
select tt.err('A3 report_cash alone: E2 (expense group) stays closed', $$select report_run2('e2_expense_trend','{}'::jsonb)$$, 'not allowed');
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
