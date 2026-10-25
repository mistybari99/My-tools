\set ON_ERROR_STOP off
-- synthetic: 21 days of sales at loc 1 by two staff, item-based + quick + a void + a discount
do $$
declare d int; it record; sid uuid; r int := 1000;
begin
  select id into sid from auth.users where email='shop2@s.app';
  for d in 1..21 loop
    for it in select id, sell_price, name_bn from items order by code limit 3 loop
      r := r + 1;
      insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, quick, created_by, created_staff, status)
      values (1, r, current_date - d, now() - (d||' days')::interval, jsonb_build_array(jsonb_build_object('item_id',it.id,'qty',2,'price',it.sell_price,'amount',2*it.sell_price,'override',(d=5))), 2*it.sell_price, case when d=3 then 50 else 0 end, 2*it.sell_price - case when d=3 then 50 else 0 end, case when d%7=0 then 'due' else 'cash' end, false, sid, case when r%5=0 then 'testf02' else 'shop2' end, 'done');
    end loop;
    r := r + 1;
    insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, quick, created_by, created_staff, status)
    values (1, r, current_date - d, now(), '[{"item_id":null,"name":"quick","qty":1,"price":300,"amount":300,"override":false}]', 300, 0, 300, 'cash', true, sid, 'shop2', case when d=2 then 'void' else 'done' end);
  end loop;
end $$;
-- expense vouchers
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff)
select '10-2', 1, g, current_date - g, 'approved', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('amount', (100+g*10)::text), jsonb_build_object('amount','abc'), jsonb_build_object('amount', '250'))), (select id from auth.users where email='shop2@s.app'), 'shop2' from generate_series(1,12) g;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
\echo T1 biz_daily (manager has POS approve, no ITEM_COST view -> cogs null)
select count(*), sum(revenue), sum(void_n), sum(cogs) is null as cogs_hidden from biz_daily(current_date-30, current_date, 1);
\echo T2 outlook (no cost -> no purchase estimate)
select biz_outlook(1,7,28);
\echo T3 staff view only role cannot
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select * from biz_daily(current_date-3,current_date,1);
\echo T4 owner: cogs, items, staff, outlook, suggest
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select count(*) as days, round(sum(revenue)) rev, round(sum(costed_rev)) costed, round(sum(cogs)) cogs, round(100*(sum(costed_rev)-sum(cogs))/sum(costed_rev),1) gm_pct_costed from biz_daily(current_date-30, current_date, 1);
select code, qty, revenue, cogs, share_pct, cum_pct, abc from biz_items(current_date-30,current_date,1) limit 6;
select count(*) filter (where abc='-') as unsold_items from biz_items(current_date-30,current_date,1);
select staff_id, n, revenue, discount_pct, void_pct, override_pct, quick_pct, due_pct, med_discount_pct, peers from biz_staff(current_date-30,current_date,1);
select biz_outlook(1,7,28);
select biz_suggest(1,90);
\echo T5 suggest is owner only
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select biz_suggest(1,90);
\echo T6 other-location user sees nothing of loc 1
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',false);
select biz_daily(current_date-3,current_date,1);
