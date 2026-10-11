\set ON_ERROR_STOP off
insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-000000000001','owner1@s.app','{"full_name":"Owner"}'),('00000000-0000-0000-0000-000000000002','staff2@s.app','{"full_name":"Mgr"}'),('00000000-0000-0000-0000-000000000003','staff3@s.app','{"full_name":"Buyer"}'),('00000000-0000-0000-0000-000000000004','staff4@s.app','{"full_name":"Shop"}');
update profiles set status='active' where staff_id<>'owner1';
insert into user_roles values ('00000000-0000-0000-0000-000000000002','management'),('00000000-0000-0000-0000-000000000003','purchasing'),('00000000-0000-0000-0000-000000000004','showroom_manager');
\echo 'T1 seed: items, costs'
select count(*) items, (select count(*) from item_costs) costs, (select sum(cost_price) from item_costs) cost_sum from items;
\echo 'T2 who can read cost / history'
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false); select count(*) as shop_costs, (select count(*) from item_price_history) as shop_hist, (select count(*) from items) as shop_items from item_costs;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false); select count(*) as buyer_costs from item_costs;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false); select count(*) as owner_costs from item_costs;
reset role;
\echo 'T3 showroom manager cannot submit; buyer can change price but not cost'
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',false);
select submit_item_change((select id from items where code='I-001'), '{"sell_price":300}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select submit_item_change((select id from items where code='I-001'), '{"sell_price":300,"cost_price":100}');
select submit_item_change((select id from items where code='I-001'), '{"sell_price":300}', 'rate up');
select sell_price as still_260 from items where code='I-001';
reset role;
\echo 'T4 buyer cannot approve (no approve right); manager can; own request blocked'
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select decide_item_change(1, true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select submit_item_change(null, '{"name_bn":"নতুন মিষ্টি","sell_price":50,"cost_price":40,"category":"sweet_pc","unit":"pc"}', 'new product');
select decide_item_change(2, true);
select decide_item_change(1, true, 'ok');
select sell_price as now_300 from items where code='I-001';
select count(*) as pending_left from item_changes where status='pending';
reset role;
\echo 'T5 new item + cost applied, history rows'
select code, sell_price, (select cost_price from item_costs c where c.item_id=i.id) cost from items i where name_bn='নতুন মিষ্টি';
select count(*) as hist_rows_i001 from item_price_history h join items i on i.id=h.item_id where i.code='I-001';
\echo 'T6 owner direct apply, cost change'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select submit_item_change((select id from items where code='I-002'), '{"cost_price":235}');
select cost_price as i002_cost from item_costs where item_id=(select id from items where code='I-002');
insert into items(name_bn) values ('direct');
update items set sell_price=1;
reset role;
\echo 'T7 allow_self_approve lets a requester approve own'
update roles set allow_self_approve=true where code='purchasing';
update role_form_perms set can_approve=true where role_code='purchasing' and form_code='ITEMS';
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',false);
select submit_item_change((select id from items where code='I-003'), '{"sell_price":360}');
select decide_item_change((select max(id) from item_changes), true);
select sell_price as i003 from items where code='I-003';
reset role;
\echo 'T8 audit has item changes'
select count(*) filter (where table_name='item_changes') as changes_logged, count(*) filter (where table_name='item_costs') as cost_logged from audit_log;
