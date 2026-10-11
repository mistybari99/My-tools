\timing off
insert into auth.users (id,email,raw_user_meta_data) select ('00000000-0000-0000-0000-0000000001'||lpad(g::text,2,'0'))::uuid, 'st'||g||'@s.app','{}' from generate_series(1,20) g;
update profiles set status='active';
-- 300k sales over 365 days, 7 locations, 3 lines each
insert into sales(location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,created_staff,customer_id,sale_type,paid,due_amount,quick,status)
select 1+(g%7), 1000+g/7, d, d::timestamp+interval '8 hours'+ (g%720)*interval '1 minute', 
  jsonb_build_array(jsonb_build_object('item_id',i1,'name','n','unit','kg','qty',1+g%3,'price',260,'amount',(1+g%3)*260,'override',false),
                    jsonb_build_object('item_id',i2,'name','n','unit','kg','qty',2,'price',260,'amount',520,'override',(g%50=0)),
                    jsonb_build_object('item_id',i3,'name','n','unit','kg','qty',1,'price',350,'amount',350,'override',false)),
  (1+g%3)*260+520+350, (g%4)*10, (1+g%3)*260+520+350-(g%4)*10, (array['cash','mobile','card','due','split'])[1+g%5],
  ('00000000-0000-0000-0000-0000000001'||lpad((1+g%20)::text,2,'0'))::uuid, 'st'||(1+g%20), case when g%5=3 then '11111111-1111-1111-1111-111111111111'::uuid end,
  case when g%9=0 then 'wholesale' else 'retail' end, (1+g%3)*260+520+350-(g%4)*10, 0, false, case when g%97=0 then 'void' else 'done' end
from (select g, date '2026-01-01' + (g%365) d, (select id from items where code='I-001') i1,(select id from items where code='I-002') i2,(select id from items where code='I-003') i3 from generate_series(1,300000) g) x;
insert into sale_payments(sale_id,location_id,kind,mode,amount,paid_at,created_staff)
select id, location_id,'sale',(array['cash','mobile','card'])[1+receipt%3], total, sold_at, created_staff from sales where pay_mode<>'due' and receipt>=1000;
analyze;
