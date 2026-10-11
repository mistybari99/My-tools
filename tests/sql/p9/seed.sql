\set ON_ERROR_STOP on
insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000001','owner1@s.app','{"full_name":"Owner"}'),
 ('00000000-0000-0000-0000-000000000003','alice@s.app','{"full_name":"Alice"}'),
 ('00000000-0000-0000-0000-000000000004','bob@s.app','{"full_name":"Bob"}'),
 ('00000000-0000-0000-0000-000000000005','mgr@s.app','{"full_name":"Mgr"}');
update profiles set status='active';
insert into user_roles values ('00000000-0000-0000-0000-000000000003','salesperson'),('00000000-0000-0000-0000-000000000004','salesperson'),('00000000-0000-0000-0000-000000000005','management');
insert into user_locations values ('00000000-0000-0000-0000-000000000003',1),('00000000-0000-0000-0000-000000000004',3);
-- costs: I-001 200, I-002 150, I-003 none
insert into item_costs(item_id,cost_price) select id,200 from items where code='I-001' on conflict (item_id) do update set cost_price=200;
insert into item_costs(item_id,cost_price) select id,150 from items where code='I-002' on conflict (item_id) do update set cost_price=150;
delete from item_costs where item_id=(select id from items where code='I-003');
update items set sell_price=260 where code in ('I-001','I-002'); update items set sell_price=350 where code='I-003';
insert into customers(id,mobile,name,type,credit_limit) values
 ('11111111-1111-1111-1111-111111111111','01711111111','Cust One','retail',300),
 ('22222222-2222-2222-2222-222222222222','01722222222','Cust Two','wholesale',5000),
 ('33333333-3333-3333-3333-333333333333','01733333333','Cust Three','retail',null);
create temp table i as select code,id from items where code in ('I-001','I-002','I-003');
create or replace function pg_temp.ln(c text, q numeric, pr numeric, ov boolean default false) returns jsonb language sql as $$
 select jsonb_build_object('item_id',(select id from i where code=c),'name','n','unit','kg','qty',q,'price',pr,'amount',q*pr,'override',ov) $$;
create or replace function pg_temp.sale(loc int, rc int, d text, tm text, stf text, uid text, ty text, lines jsonb, sub numeric, disc numeric, mode text, paid numeric, cust uuid, quick boolean, st text) returns uuid language plpgsql as $$
declare sid uuid := gen_random_uuid();
begin
 insert into sales(id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,created_staff,customer_id,sale_type,paid,due_amount,quick,status,void_staff,void_note)
 values (sid,loc,rc,d::date,(d||' '||tm||'+06')::timestamptz,lines,sub,disc,sub-disc,mode,uid::uuid,(select staff_id from profiles where id=uid::uuid),cust,ty,paid,sub-disc-paid,quick,st, case when st='void' then 'x' end, case when st='void' then 'wrong' end);
 return sid;
end $$;
\set a '00000000-0000-0000-0000-000000000003'
\set bb '00000000-0000-0000-0000-000000000004'
-- previous week
select pg_temp.sale(1,1,'2026-09-03','10:00','a',:'a','retail', jsonb_build_array(pg_temp.ln('I-001',2,260),pg_temp.ln('I-002',1,260)),780,80,'cash',700,null,false,'done') as s1 \gset
select pg_temp.sale(3,1,'2026-09-05','15:30','b',:'bb','retail', jsonb_build_array(pg_temp.ln('I-003',1,350)),350,0,'cash',350,null,false,'done') as s2 \gset
insert into sale_payments(sale_id,location_id,kind,mode,amount,paid_at,created_staff) values
 (:'s1',1,'sale','cash',700,'2026-09-03 10:00+06','alice'),(:'s2',3,'sale','cash',350,'2026-09-05 15:30+06','bob');
-- current week
select pg_temp.sale(1,2,'2026-09-08','11:00','a',:'a','retail', jsonb_build_array(pg_temp.ln('I-001',3,260)),780,0,'split',300,'11111111-1111-1111-1111-111111111111',false,'done') as s3 \gset
select pg_temp.sale(1,3,'2026-09-09','19:00','a',:'a','wholesale', jsonb_build_array(pg_temp.ln('I-002',10,260)),2600,100,'mobile',2500,'22222222-2222-2222-2222-222222222222',false,'done') as s4 \gset
select pg_temp.sale(3,2,'2026-09-09','09:00','b',:'bb','retail', jsonb_build_array(jsonb_build_object('item_id',null,'name','Quick sale','qty',1,'price',150,'amount',150,'override',false)),150,0,'cash',150,null,true,'done') as s5 \gset
select pg_temp.sale(3,3,'2026-09-10','12:00','b',:'bb','retail', jsonb_build_array(pg_temp.ln('I-003',2,300,true),pg_temp.ln('I-001',1,260)),860,60,'mobile',800,null,false,'done') as s6 \gset
select pg_temp.sale(1,4,'2026-09-10','20:00','a',:'a','retail', jsonb_build_array(pg_temp.ln('I-001',1,260)),260,0,'cash',260,null,false,'void') as s7 \gset
select pg_temp.sale(1,5,'2026-09-11','14:00','a',:'a','retail', jsonb_build_array(jsonb_build_object('item_id',null,'name','Special','qty',2,'price',100,'amount',200,'override',false,'custom',true)),200,0,'card',200,null,false,'done') as s8 \gset
select pg_temp.sale(3,4,'2026-09-13','16:00','b',:'bb','retail', jsonb_build_array(jsonb_build_object('item_id',null,'name','Quick sale','qty',1,'price',100,'amount',100,'override',false)),100,0,'due',0,'33333333-3333-3333-3333-333333333333',true,'done') as s9 \gset
insert into sale_payments(sale_id,customer_id,location_id,kind,mode,wallet,ref,amount,paid_at,created_staff,voided) values
 (:'s3','11111111-1111-1111-1111-111111111111',1,'sale','cash',null,null,300,'2026-09-08 11:00+06','alice',false),
 (:'s4','22222222-2222-2222-2222-222222222222',1,'sale','mobile','bkash','TX1',2500,'2026-09-09 19:00+06','alice',false),
 (:'s5',null,3,'sale','cash',null,null,150,'2026-09-09 09:00+06','bob',false),
 (:'s6',null,3,'sale','mobile','nagad',null,800,'2026-09-10 12:00+06','bob',false),
 (:'s7',null,1,'sale','cash',null,null,260,'2026-09-10 20:00+06','alice',true),
 (:'s8',null,1,'sale','card',null,null,200,'2026-09-11 14:00+06','alice',false),
 (null,'11111111-1111-1111-1111-111111111111',1,'collection','cash',null,null,200,'2026-09-12 10:00+06','alice',false);
-- owner gives salesperson the sales-report grant
insert into rule_grants(grant_code,role_code) values ('report_sales','salesperson') on conflict do nothing;
