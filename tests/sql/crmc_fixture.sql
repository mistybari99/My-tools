-- CRM-C test fixture (test_* names only). Load on a database through phase 98 or later. Safe to load once per database.
-- Dates are relative to today (Dhaka) as T. Hand-computed expectations are written in the phase306/307/308 tests.
\set ON_ERROR_STOP off
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

\set u_o   '00000000-0000-0000-0000-00000000c301'
\set u_m   '00000000-0000-0000-0000-00000000c302'
\set u_e   '00000000-0000-0000-0000-00000000c303'
\set u_v   '00000000-0000-0000-0000-00000000c304'
\set u_x   '00000000-0000-0000-0000-00000000c305'
\set u_c   '00000000-0000-0000-0000-00000000c306'
\set u_bot '00000000-0000-0000-0000-00000000c307'
\set u_d   '00000000-0000-0000-0000-00000000c308'
\set u_k   '00000000-0000-0000-0000-00000000c309'
\set u_n   '00000000-0000-0000-0000-00000000c30a'
insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner_c@s.app','{"full_name":"test_owner_c"}'),(:'u_m','test_mgr_c@s.app','{"full_name":"test_mgr_c"}'),(:'u_e','test_editor_c@s.app','{"full_name":"test_editor_c"}'),
 (:'u_v','test_viewer_c@s.app','{"full_name":"test_viewer_c"}'),(:'u_x','test_exporter_c@s.app','{"full_name":"test_exporter_c"}'),(:'u_c','test_cashier_c@s.app','{"full_name":"test_cashier_c"}'),
 (:'u_bot','test_bot_c@s.app','{"full_name":"test_bot_c"}'),(:'u_d','test_contact_c@s.app','{"full_name":"test_contact_c"}'),(:'u_k','test_cost_c@s.app','{"full_name":"test_cost_c"}'),(:'u_n','test_nocost_c@s.app','{"full_name":"test_nocost_c"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o',:'u_m',:'u_e',:'u_v',:'u_x',:'u_c',:'u_d',:'u_k',:'u_n');
insert into user_roles values (:'u_o','owner'),(:'u_m','management'),(:'u_e','management'),(:'u_v','management'),(:'u_x','management'),(:'u_c','salesperson'),(:'u_d','management'),(:'u_k','management'),(:'u_n','salesperson') on conflict do nothing;
insert into user_locations select u::uuid, l from (values (:'u_m'),(:'u_e'),(:'u_v'),(:'u_x'),(:'u_c'),(:'u_d'),(:'u_k')) a(u), (values (1),(2)) b(l) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_m','customer_manage',null),(:'u_e','crm_settings_edit',null),(:'u_v','crm_view',null),(:'u_x','crm_export',null),(:'u_x','crm_view',null),
 (:'u_d','crm_view',null),(:'u_d','crm_contact_view',null),(:'u_k','crm_view',null),(:'u_k','view_cost',null),(:'u_n','crm_view',null);
insert into ops_accounts (user_id, purpose) values (:'u_bot','notify') on conflict do nothing;

insert into items (id, code, name_bn, name_en, unit, sell_price) values
 ('aaaaaaaa-0000-0000-0000-0000000000a1','test_it_a','test item a','test item a','piece',50),('aaaaaaaa-0000-0000-0000-0000000000a2','test_it_b','test item b','test item b','piece',100) on conflict do nothing;
insert into item_costs (item_id, cost_price) values ('aaaaaaaa-0000-0000-0000-0000000000a1', 40) on conflict do nothing;   -- item b has no cost anywhere (unknown cost)

select tt.today() as t \gset
insert into customers (id, mobile, name, type, birthday, source, active) values
 ('00000000-0000-0000-0000-00000000c3a1','01700000001','test_cust_champ','retail',(:'t'::date + 3) - interval '30 years','Facebook',true),
 ('00000000-0000-0000-0000-00000000c3a2','01700000002','test_cust_atrisk','wholesale',null,null,true),
 ('00000000-0000-0000-0000-00000000c3a3','01700000003','test_cust_onetime','retail',null,'walk-in',true),
 ('00000000-0000-0000-0000-00000000c3a4','01700000004','test_cust_old','retail',null,null,true),
 ('00000000-0000-0000-0000-00000000c3a5','01700000005','test_cust_never','retail',(:'t'::date + 200) - interval '40 years',null,true),
 ('00000000-0000-0000-0000-00000000c3a6','01700000006','test_cust_void','retail',null,null,true),
 ('00000000-0000-0000-0000-00000000c3a7','01700000007','test_cust_inactive','retail',null,null,false),
 ('00000000-0000-0000-0000-00000000c3a8','01700000008','test_cust_due','retail',null,null,true) on conflict do nothing;
update customers set tier_id = (select id from customer_tiers where code = 'gold') where id = '00000000-0000-0000-0000-00000000c3a1';
update customers set tier_id = (select id from customer_tiers where code = 'silver') where id = '00000000-0000-0000-0000-00000000c3a2';

-- sales: (id, customer, loc, receipt, days ago, total, status, lines)
insert into sales (id, location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, customer_id, status, created_by, paid, due_amount)
select v.id::uuid, v.loc, v.rc, :'t'::date - v.ago, (:'t'::date - v.ago)::timestamp + interval '10 hours', v.lines::jsonb, v.total, v.total, v.pm, v.cust::uuid, v.st, :'u_o'::uuid, v.paid, v.total - v.paid
from (values
 ('5a000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000c3a1',1,9001,5,100,'cash','done',100,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a1","name":"test item a","qty":2,"amount":100}]'),
 ('5a000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000c3a1',1,9002,10,200,'cash','done',200,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a1","name":"test item a","qty":3,"amount":120},{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a2","name":"test item b","qty":1,"amount":80}]'),
 ('5a000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000c3a1',1,9003,20,300,'cash','done',300,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a2","name":"test item b","qty":3,"amount":300}]'),
 ('5a000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-00000000c3a2',1,9004,100,150,'cash','done',150,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a1","name":"test item a","qty":1,"amount":150}]'),
 ('5a000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-00000000c3a2',1,9005,90,250,'cash','done',250,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a2","name":"test item b","qty":2,"amount":250}]'),
 ('5a000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-00000000c3a3',2,9006,40,80,'cash','done',80,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a1","name":"test item a","qty":1,"amount":80}]'),
 ('5a000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-00000000c3a4',1,9007,400,500,'cash','done',500,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a1","name":"test item a","qty":5,"amount":500}]'),
 ('5a000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-00000000c3a6',2,9008,3,999,'cash','void',999,'[]'),
 ('5a000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-00000000c3a6',2,9009,2,60,'cash','done',60,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a2","name":"test item b","qty":1,"amount":60}]'),
 ('5a000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000c3a7',1,9010,1,10,'cash','done',10,'[]'),
 ('5a000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000c3a8',1,9011,15,1000,'due','done',400,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a1","name":"test item a","qty":10,"amount":1000}]'),
 ('5a000000-0000-0000-0000-00000000000c',null,1,9012,4,70,'cash','done',70,'[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a1","name":"test item a","qty":1,"amount":70}]')
) v(id, cust, loc, rc, ago, total, pm, st, paid, lines) on conflict do nothing;
-- the money taken at the counter for every done sale (the due sale: 400 of 1000 paid, so 600 is owed)
insert into sale_payments (sale_id, customer_id, location_id, kind, mode, amount, created_by) select id, customer_id, location_id, 'sale', 'cash', paid, created_by from sales where status = 'done' and paid > 0;
-- one return (credit note) of 50 on the 90-day-old sale of the at-risk customer
insert into sale_returns (id, sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, reason_code, status, created_at)
 values ('7e000000-0000-0000-0000-000000000001','5a000000-0000-0000-0000-000000000005',1,'00000000-0000-0000-0000-00000000c3a2','[{"item_id":"aaaaaaaa-0000-0000-0000-0000000000a2","qty":0.4,"amount":50}]'::jsonb,50,50,0,'test',
         'done',(:'t'::date - 85)::timestamp + interval '11 hours');
-- stock ledger cost for the sales of item a at known cost 40 (items b stay without cost)
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at) values
 ('aaaaaaaa-0000-0000-0000-0000000000a1',1,-2,40,'sale_out','sale','5a000000-0000-0000-0000-000000000001',now()),
 ('aaaaaaaa-0000-0000-0000-0000000000a1',1,-3,40,'sale_out','sale','5a000000-0000-0000-0000-000000000002',now());
insert into customer_points_ledger (customer_id, delta, reason, note) values ('00000000-0000-0000-0000-00000000c3a1', 50, 'adjust', 'test');
insert into notify_optin (customer_id, channel, status, source) values
 ('00000000-0000-0000-0000-00000000c3a1','sms','in','owner_entry'),('00000000-0000-0000-0000-00000000c3a3','whatsapp','in','owner_entry'),('00000000-0000-0000-0000-00000000c3a2','sms','out','owner_entry') on conflict do nothing;
