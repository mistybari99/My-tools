-- CRM-A fixture, PART 1 (core): customers and every touchpoint that exists BEFORE the CRM phases (no side table, no new column). Used on its own by the before/after proof.
-- (old header follows) CRM-A fixture: customers with every kind of touchpoint. Test data only (test_* names). Needs phases 300-302 (side tables) and a database through phase 98.
-- Does not change any accounting table other than adding test sales / payments / returns.
\set ON_ERROR_STOP on
\set u_o '00000000-0000-0000-0000-000000030201'
\set u_c '00000000-0000-0000-0000-000000030202'
\set u_v '00000000-0000-0000-0000-000000030203'
\set u_cv '00000000-0000-0000-0000-000000030204'
\set u_mg '00000000-0000-0000-0000-000000030205'
\set u_r '00000000-0000-0000-0000-000000030206'
\set u_x '00000000-0000-0000-0000-000000030207'
create schema if not exists tt;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner302@s.app','{"full_name":"test_owner302"}'), (:'u_c','test_cash302@s.app','{"full_name":"test_cash302"}'), (:'u_v','test_viewer302@s.app','{"full_name":"test_viewer302"}'),
 (:'u_cv','test_contact302@s.app','{"full_name":"test_contact302"}'), (:'u_mg','test_mgmt302@s.app','{"full_name":"test_mgmt302"}'), (:'u_r','test_reader302@s.app','{"full_name":"test_reader302"}'),
 (:'u_x','test_outsider302@s.app','{"full_name":"test_outsider302"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_c', :'u_v', :'u_cv', :'u_mg', :'u_r', :'u_x');
insert into user_roles values (:'u_o','owner'),(:'u_c','salesperson'),(:'u_v','salesperson'),(:'u_cv','salesperson'),(:'u_mg','management'),(:'u_r','cash_controller'),(:'u_x','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_c',1),(:'u_v',1),(:'u_cv',1),(:'u_mg',1),(:'u_r',1),(:'u_x',1) on conflict do nothing;

select set_config('request.jwt.claim.sub', :'u_o', false);
insert into customers (mobile, name, whatsapp, birthday, anniversary, address, note, source)
  values ('01711032001', 'test_cust_one', '01711032009', date '1990-03-15', date '2015-11-20', 'test_addr_main_1', 'test_old_note', 'test_source');
insert into customers (mobile, name) values ('01711032002', 'test_cust_two'), ('01711032003', 'test_cust_three');
select id as c1 from customers where mobile = '01711032001' \gset
select id as c2 from customers where mobile = '01711032002' \gset
select id as c3 from customers where mobile = '01711032003' \gset
select id as i1 from items order by id limit 1 \gset
select id as i2 from items order by id offset 1 limit 1 \gset

-- sales: s1 done at place 1, s2 done with a due, s3 void, s4 at place 2 (the cashier cannot see it)
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id, paid, due_amount) values
 (1, 932001, tt.today() - 10, now() - interval '10 days', jsonb_build_array(jsonb_build_object('item_id', :'i1', 'name', 'test_item_a', 'unit', 'kg', 'qty', 2, 'price', 200, 'amount', 400), jsonb_build_object('item_id', :'i2', 'name', 'test_item_b', 'unit', 'pcs', 'qty', 1, 'price', 150, 'amount', 150)), 550, 0, 550, 'cash', 'done', :'u_o', :'c1', 550, 0),
 (1, 932002, tt.today() - 5, now() - interval '5 days', jsonb_build_array(jsonb_build_object('item_id', :'i1', 'name', 'test_item_a', 'unit', 'kg', 'qty', 3, 'price', 200, 'amount', 600)), 600, 0, 600, 'due', 'done', :'u_o', :'c1', 400, 200),
 (1, 932003, tt.today() - 4, now() - interval '4 days', jsonb_build_array(jsonb_build_object('item_id', :'i1', 'name', 'test_item_a', 'unit', 'kg', 'qty', 10, 'price', 200, 'amount', 2000)), 2000, 0, 2000, 'cash', 'void', :'u_o', :'c1', 2000, 0),
 (2, 932004, tt.today() - 3, now() - interval '3 days', jsonb_build_array(jsonb_build_object('name', 'test_quick', 'amount', 50)), 50, 0, 50, 'cash', 'done', :'u_o', :'c1', 50, 0);
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, paid_at, created_by) select s.id, :'c1', s.location_id, 'sale', 'cash', s.paid, s.sold_at, :'u_o' from sales s where s.receipt in (932001, 932002, 932004);
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, paid_at, created_by) values (null, :'c1', 1, 'collection', 'cash', 100, now() - interval '2 days', :'u_o');
insert into sale_returns (sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, reason_code, created_by, created_at)
  select s.id, 1, :'c1', '[]', 100, 100, 0, 'other', :'u_o', now() - interval '9 days' from sales s where s.receipt = 932001;
-- online orders: one by the main number (typed with +880), one by the extra number, one at place 2
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, discount, delivery_mode, delivery_charge, status, created_by, created_at) values
 (932001, 1, 'phone', 'test_cust_one', '+8801711032001', '[{"name":"test_cake","qty":1}]', 1000, 100, 'home', 50, 'new', :'u_o', now() - interval '1 day'),
 (932002, 1, 'phone', 'test_cust_one', '01711032011', '[{"name":"test_cake","qty":1}]', 500, 0, 'pickup', 0, 'delivered', :'u_o', now() - interval '8 days'),
 (932003, 2, 'phone', 'test_cust_one', '01711032001', '[{"name":"test_cake","qty":1}]', 300, 0, 'pickup', 0, 'new', :'u_o', now() - interval '2 days');
insert into customer_points_ledger (customer_id, delta, reason, sale_id, note, at) select :'c1', 55, 'sale', s.id, null, now() - interval '10 days' from sales s where s.receipt = 932001;
insert into customer_points_ledger (customer_id, delta, reason, note, at) values (:'c1', -20, 'redeem', 'test', now() - interval '6 days'), (:'c1', 5, 'adjust', 'test', now() - interval '1 day');
insert into customer_gifts (customer_id, rule_id, occasion, gift_text_en, value_taka, issued_at) values (:'c1', null, 'manual:test_gift', 'test_gift', 100, now() - interval '7 days');
insert into customer_tier_history (customer_id, from_tier, to_tier, reason, note, at) select :'c1', (select id from customer_tiers where code = 'walkin'), (select id from customer_tiers where code = 'regular'), 'manual', 'test', now() - interval '12 days';
insert into notify_outbox (client_id, customer_id, channel, to_phone, template_code, body, status, sent_at, created_at) values (gen_random_uuid(), :'c1', 'sms', '+8801711032001', 'thanks', 'test_body_sms', 'sent', now() - interval '6 days', now() - interval '6 days');
insert into sales_channels (code, kind, name_bn) values ('test_chan_302', 'phone', 'test_channel') on conflict do nothing;
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, msg_text, received_at) select id, 1, 'test_ext_302', '01711032011', 'test_enquiry_text', now() - interval '11 days' from sales_channels where code = 'test_chan_302';

