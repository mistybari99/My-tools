-- RPT-C2 order data set (neutral test_* data). Needs tests/sql/c2_fixture.sql first and the C2 phases through 448 pasted. Used by phase449_test .. phase452_test.
-- T = today (Dhaka). Place 1. Item test_item_a price 100, test_item_b price 50.
--   :oa  delivered on time (promise T 10:00-12:00, delivered T 11:00), advance 50 cash paid into the sale (legacy), delivery cost 40, cake spec 1.5 kg      total 230
--   :ob  confirmed, OVERDUE (delivery date T-2, promise 09:00-10:00), advance 40                                                                               total 200+0
--   :oc  cancelled with refund, refund DUE (advance 60 mobile, nobody with the cash right cancelled it)
--   :od  cancelled with refund while the refund switch was OFF (advance 25) -> refund not recorded
--   :oe  delivered with a POSTED and APPLIED advance 50 (promise T 14:00-16:00, delivered T 15:00)
--   :of  delivered LATE and part paid (promise T-1 09:00-10:00, delivered T 15:00, paid 100 of 230 -> 130 still due); home delivery, no delivery cost written
--   :og  new, no promise, no delivery date
--   paper: 20-1 custom open overdue (500, adv 100), 20-1 handed (300, adv 100, due paid 200), 20-1 not collected (adv 80, fate refund), 20-6 with two ledger lines
\set ON_ERROR_STOP off
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_a', '01700000101', 'test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'home', 'test_rider', tt.today(), 30, 0, 50, 'cash', null, null) ->> 'id' as oa \gset
select online_order_save(null, gen_random_uuid(), 1, 'whatsapp', 'test_customer_b', '01700000102', 'test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'home', null, tt.today(), 0, 0, 40, 'cash', null, null) ->> 'id' as ob \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_c', '01700000103', null, format('[{"item_id":"%s","qty":2}]', :'ib')::jsonb, 'pickup', null, null, 0, 0, 60, 'mobile', null, null) ->> 'id' as oc \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_d', '01700000104', null, format('[{"item_id":"%s","qty":1}]', :'ib')::jsonb, 'pickup', null, null, 0, 0, 25, 'cash', null, null) ->> 'id' as od \gset
select online_order_save(null, gen_random_uuid(), 1, 'facebook', 'test_customer_e', '01700000105', null, format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'pickup', null, tt.today(), 0, 0, 50, 'cash', null, null) ->> 'id' as oe \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_f', '01700000106', 'test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'home', null, tt.today(), 30, 0, 0, null, null, null) ->> 'id' as of \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_g', '01700000107', null, format('[{"item_id":"%s","qty":1}]', :'ib')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) ->> 'id' as og \gset
-- promises
select c2_order_promise_set(:'oa'::uuid, '10:00', '12:00') is not null as pa \gset
select c2_order_promise_set(:'ob'::uuid, '09:00', '10:00') is not null as pb \gset
select c2_order_promise_set(:'oe'::uuid, '14:00', '16:00') is not null as pe \gset
select c2_order_promise_set(:'of'::uuid, '09:00', '10:00') is not null as pf \gset
select c2_order_spec_save(:'oa'::uuid, '[{"weight_kg":1.5,"flavour":"test_flavour","message":"test_message","design":"test_design","photo_ref":"test_photo"}]'::jsonb) is not null as sa \gset
-- A: confirm, pack, deliver (advance goes into the sale, legacy), cost
select online_order_status(:'oa'::uuid,'confirmed') is not null as a1 \gset
select online_order_status(:'oa'::uuid,'packed') is not null as a2 \gset
select c2_order_deliver(:'oa'::uuid, '[{"mode":"cash","amount":180}]'::jsonb) is not null as a3 \gset
select c2_order_cost_add(:'oa'::uuid, 'rider_pay', 40, 'test_rider', null) is not null as a4 \gset
-- B: confirmed only
select online_order_status(:'ob'::uuid,'confirmed') is not null as b1 \gset
-- D: cancelled while the refund switch is OFF
select c2_order_cancel(:'od'::uuid, 'test_reason_d', 'refund') is not null as d1 \gset
-- F: delivered, part paid
select online_order_status(:'of'::uuid,'confirmed') is not null as f1 \gset
select online_order_status(:'of'::uuid,'packed') is not null as f2 \gset
select c2_order_deliver(:'of'::uuid, '[{"mode":"cash","amount":100}]'::jsonb) is not null as f3 \gset
-- switches for the rest
select tt.as(:'o');
select set_rule('order_refund_record_on','true') is null as r1 \gset
select set_rule('order_advance_post_on','true') is null as r2 \gset
select tt.as(:'p');
-- C: cancelled by a salesperson -> refund due
select c2_order_cancel(:'oc'::uuid, 'test_reason_c', 'refund') is not null as c1 \gset
-- E: posted + applied advance, delivered
select tt.as(:'c');
select c2_order_advance_post(:'oe'::uuid) is not null as e0 \gset
select online_order_status(:'oe'::uuid,'confirmed') is not null as e1 \gset
select online_order_status(:'oe'::uuid,'packed') is not null as e2 \gset
select c2_order_deliver(:'oe'::uuid, '[{"mode":"cash","amount":150}]'::jsonb) is not null as e3 \gset
select tt.as(:'o');
-- clock control (superuser, triggers off): delivery dates and times are set to known values
set session_replication_role = replica;
update online_orders set delivery_date = tt.today() - 2 where id = :'ob'::uuid;
update online_orders set delivery_date = tt.today() - 1, delivered_at = ((tt.today())::text || ' 15:00:00+06')::timestamptz where id = :'of'::uuid;
update online_orders set delivered_at = ((tt.today())::text || ' 11:00:00+06')::timestamptz where id = :'oa'::uuid;
update online_orders set delivered_at = ((tt.today())::text || ' 15:00:00+06')::timestamptz where id = :'oe'::uuid;
-- paper sheets
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff, submitted_at) values
 ('20-1', 1, 9001, tt.today(), 'submitted', jsonb_build_object('order_type','custom','channel','phone','cust_name','test_paper_a','cust_phone','01700000201','deliv_mode','home','deliv_date',(tt.today()-1)::text,'deliv_time','11:00',
    'total','500','advance','100','items',jsonb_build_array(jsonb_build_object('item','TST-A','desc','test_desc','qty','1','msg','test_msg','design','test_design','special','test_special'))), :'p', 'test_sales1', now()),
 ('20-1', 1, 9002, tt.today(), 'submitted', jsonb_build_object('order_type','normal','channel','counter','cust_name','test_paper_b','cust_phone','01700000202','deliv_mode','pickup','deliv_date',tt.today()::text,'total','300','advance','100','cust_signed','true','due_paid','200'), :'p', 'test_sales1', now()),
 ('20-1', 1, 9003, tt.today(), 'submitted', jsonb_build_object('order_type','normal','channel','phone','cust_name','test_paper_c','cust_phone','01700000203','deliv_mode','pickup','deliv_date',tt.today()::text,'total','200','advance','80','not_collected','true','adv_fate','refund','fate_reason','test_reason_p'), :'p', 'test_sales1', now()),
 ('20-6', 1, 9004, tt.today(), 'submitted', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('platform','test_platform','delivery','test_rider','amt','120','dcharge','20','outcome','handed'), jsonb_build_object('platform','test_platform','delivery','test_rider','amt','80','outcome','returned'))), :'p', 'test_sales1', now());
set session_replication_role = origin;
select tt.as(:'o');
