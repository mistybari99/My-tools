-- RPT-HUB test fixture (phases 450-456). Neutral test_* data only. Loaded with \i by the rpthub suites, after tt.* helpers exist.
-- Users: owner o, management m (report_sales/pos/cash/customers by role), viewer v (report_sales only), nogrant x, payroll p (salary_view + report_expense), allrep a (view_reports).
-- Everything is posted through the real functions, so the ledgers are the ones the app writes. The "day" of the replay is today (Asia/Dhaka).
\set u_o '00000000-0000-0000-0000-000000045001'
\set u_m '00000000-0000-0000-0000-000000045002'
\set u_v '00000000-0000-0000-0000-000000045003'
\set u_x '00000000-0000-0000-0000-000000045004'
\set u_p '00000000-0000-0000-0000-000000045005'
\set u_a '00000000-0000-0000-0000-000000045006'
\set u_s '00000000-0000-0000-0000-000000045007'
insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner450@s.app','{"full_name":"test_owner450"}'), (:'u_m','test_manager450@s.app','{"full_name":"test_manager450"}'),
 (:'u_v','test_viewer450@s.app','{"full_name":"test_viewer450"}'), (:'u_x','test_nogrant450@s.app','{"full_name":"test_nogrant450"}'),
 (:'u_p','test_payroll450@s.app','{"full_name":"test_payroll450"}'), (:'u_a','test_allrep450@s.app','{"full_name":"test_allrep450"}'),
 (:'u_s','test_seller450@s.app','{"full_name":"test_seller450"}') on conflict do nothing;
update profiles set status = 'active' where id in (:'u_o', :'u_m', :'u_v', :'u_x', :'u_p', :'u_a', :'u_s');
insert into user_roles values (:'u_o','owner'),(:'u_m','management'),(:'u_v','salesperson'),(:'u_x','salesperson'),(:'u_p','management'),(:'u_a','salesperson'),(:'u_s','salesperson') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_m',2),(:'u_v',1),(:'u_x',1),(:'u_p',1),(:'u_a',1),(:'u_s',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'u_o', false);
select set_user_grant(:'u_v'::uuid, 'report_sales') is null as g1 \gset
select set_user_grant(:'u_p'::uuid, 'salary_view') is null as g2 \gset
select set_user_grant(:'u_p'::uuid, 'report_expense') is null as g3 \gset
select set_user_grant(:'u_a'::uuid, 'view_reports') is null as g4 \gset
select set_user_grant(:'u_a'::uuid, 'view_cost') is null as g5 \gset

insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('test_fg', 'test_fg', 'test_sweet', 'kg', 'kg', 'finished_good', true, 260),
 ('test_fl', 'test_fl', 'test_flour', 'kg', 'kg', 'raw_material', true, null),
 ('test_su', 'test_su', 'test_sugar', 'kg', 'kg', 'raw_material', true, null) on conflict do nothing;
select id as i_fg from items where code = 'test_fg' \gset
select id as i_fl from items where code = 'test_fl' \gset
select id as i_su from items where code = 'test_su' \gset
insert into suppliers (name, mobile) values ('test_supplier_a', '01700000450') on conflict do nothing;
select id as sup from suppliers where name = 'test_supplier_a' \gset
set role authenticated; select set_config('request.jwt.claim.sub', :'u_o', false);
select stock_opening(:'i_fl'::uuid, 1, 100, 40, null, 'test open') is not null as so1 \gset
select stock_opening(:'i_su'::uuid, 1, 100, 60, null, 'test open') is not null as so2 \gset
select stock_opening(:'i_fg'::uuid, 1, 20, 150, null, 'test open') is not null as so3 \gset
select (recipe_save(null, :'i_fg'::uuid, 10, null, 'test v1', jsonb_build_array(jsonb_build_object('ingredient_item_id', :'i_fl', 'qty', 6, 'waste_pct', 0), jsonb_build_object('ingredient_item_id', :'i_su', 'qty', 3, 'waste_pct', 0)))->>'id')::uuid as rc \gset
-- sales today: s1 cash 2 kg, s2 cash 3 kg with discount 20, s3 wholesale on credit (customer), s4 sold then voided
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":2,"price":260,"unit":"kg"}]', :'i_fg')::jsonb, 0, '[{"mode":"cash","amount":520}]', null, null, 'retail', null, false) ->> 'receipt' as r1 \gset
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":3,"price":260,"unit":"kg"}]', :'i_fg')::jsonb, 20, '[{"mode":"mobile","wallet":"bkash","ref":"t450","amount":760}]', null, null, 'retail', null, false) ->> 'receipt' as r2 \gset
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":4,"price":260,"unit":"kg"}]', :'i_fg')::jsonb, 0, '[{"mode":"cash","amount":400}]', '01800000450', 'test_customer_a', 'wholesale', null, false) ->> 'receipt' as r3 \gset
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]', :'i_fg')::jsonb, 0, '[{"mode":"cash","amount":260}]', null, null, 'retail', null, false) ->> 'receipt' as r4 \gset
select id as sale4 from sales where location_id = 1 and receipt = :'r4' \gset
select void_sale(:'sale4'::uuid, 'test wrong item') is not null as vd \gset
select id as sale1 from sales where location_id = 1 and receipt = :'r1' \gset
select sale_return(gen_random_uuid(), :'sale1'::uuid, format('[{"item_id":"%s","qty":1}]', :'i_fg')::jsonb, 'damaged', 'test return', 'cash', null, null) is not null as rt \gset
select id as cust from customers where mobile = '01800000450' \gset
select collect_payment(gen_random_uuid(), 1, :'cust'::uuid, '[{"mode":"cash","amount":300}]', 'test collection') is not null as cp \gset
-- expenses: head staff_meal with a memo that names a person; electricity typed in the memo under another head
select quick_expense_add(1, tt.today(), 'staff_meal', 'test_staff_a lunch', 120, 'cash', true, 'test staff meal', gen_random_uuid()) is not null as q1 \gset
select quick_expense_add(1, tt.today(), 'repair', 'test_power_co', 800, 'cash', true, 'test electricity bill october', gen_random_uuid()) is not null as q2 \gset
select quick_expense_add(1, tt.today(), 'transport', 'test_rider', 60, 'cash', false, 'test rickshaw', gen_random_uuid()) is not null as q3 \gset
-- purchase + payment
select save_purchase(null, null, :'sup'::uuid, 1, 'T450-1', tt.today(), format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":42}]', :'i_fl')::jsonb) ->> 'id' as pb \gset
select post_purchase(:'pb'::uuid) is not null as pp \gset
select pay_supplier(:'sup'::uuid, 1, '[{"mode":"cash","amount":200}]', gen_random_uuid(), 'test pay') is not null as ps \gset
-- stock: wastage, count adjustment, transfer received short, production
select stock_wastage(:'i_su'::uuid, 1, 2, 'spoiled', 'test waste', null, null, gen_random_uuid()) is not null as w1 \gset
select stock_count_adjust(:'i_fl'::uuid, 1, 105, 'test recount', null, gen_random_uuid()) is not null as ca \gset
select stock_transfer(1, 2, :'i_fg'::uuid, 5, null, 'test move', gen_random_uuid()) ->> 'id' as tr1 \gset
select stock_receive_transfer(:'tr1'::uuid, 4, 'test one short') is not null as rcv \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid()) ->> 'run_id' as run1 \gset
reset role;
-- direct rows for kinds without a posting function (test data)
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff, submitted_at)
 values ('10-1', 1, 450001, tt.today(), 'submitted', '{"count":{"n1000":2}}', :'u_s', 'test_seller450', now()),
        ('04-3', 1, 450002, tt.today(), 'submitted', '{}', :'u_s', 'test_seller450', now()),
        ('14-1', 1, 450003, tt.today(), 'draft', '{}', :'u_s', 'test_seller450', now());
select id as e101 from entries where form_code = '10-1' and serial = 450001 \gset
insert into exceptions (form_code, location_id, entry_date, flag_code, level, amount, text, status) values ('POS', 1, tt.today(), 'test_flag', 'yellow', 50, '{"en":"test exception"}', 'open');
insert into employees (employee_no, full_name_en, full_name_bn, joining_date, status, primary_location_id, profile_id) values ('test_e1', 'test_employee_a', 'test_employee_a', '2026-01-01', 'active', 1, :'u_s') on conflict do nothing;
select id as emp from employees where employee_no = 'test_e1' \gset
insert into employee_status_log (employee_id, from_status, to_status, status_date, reason, "by", at) values (:'emp', 'active', 'resigned', tt.today(), 'test exit', :'u_o', now());
insert into employee_advances (employee_id, location_id, adv_date, amount, recover_from, mode, status, created_by) values (:'emp', 1, tt.today(), 500, tt.today(), 'cash', 'active', :'u_o');
insert into c_month_close_log (month, action, note, created_by, created_staff) values (date_trunc('month', tt.today())::date, 'close', 'test close', :'u_o', 'test_owner450');
insert into shortage_cash_cases (entry_id, form_code, location_id, case_date, amount, reason, status, treatment) values (:'e101', '14-1', 1, tt.today(), 75, 'test short', 'open', null);
insert into release_requests (entry_id, flag_code, flag_amount, reason, status, requested_by, requested_staff, requested_at) values (:'e101', 'test_flag', 50, 'test release', 'pending', :'u_s', 'test_seller450', now());
-- an older day, direct rows (a past expense and a past supplier payment)
insert into quick_expenses (location_id, exp_date, head, paid_to, amount, mode, receipt, note, status, created_by, created_staff, created_at)
 values (1, tt.today() - 3, 'staff_meal', 'test_staff_a lunch', 100, 'cash', true, 'test older meal', 'done', :'u_o', 'test_owner450', (tt.today() - 3)::timestamp at time zone 'Asia/Dhaka' + interval '13 hours');
