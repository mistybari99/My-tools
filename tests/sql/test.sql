\set ON_ERROR_STOP off
insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-000000000001','owner1@s.app','{"full_name":"Owner One"}');
insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-000000000002','Staff2@s.app','{"full_name":"Staff Two"}');
\echo '--- T1 first user is active owner, second pending'
select staff_id, status, (select string_agg(role_code,',') from user_roles ur where ur.user_id=p.id) roles from profiles p order by staff_id;

\echo '--- T2 pending user sees nothing'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select count(*) as items_visible_to_pending from items;
select (my_context()->'profile'->>'status') as ctx_status, my_context()->'perms' as perms;
update items set sell_price=1 where code='I-001'; 
reset role;

\echo '--- T3 owner approves staff2 + gives showroom_manager role'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
update profiles set status='active' where staff_id='staff2';
insert into user_roles values ('00000000-0000-0000-0000-000000000002','showroom_manager');
select count(*) as owner_perm_forms from jsonb_object_keys(my_context()->'perms');
reset role;

\echo '--- T4 staff2 (showroom_manager) can read items, cannot edit them, cannot read audit/others profiles'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select count(*) as items_visible from items;
update items set sell_price=999 where code='I-001'; select sell_price as price_after_unauth_update from items where code='I-001';
select count(*) as audit_rows_visible from audit_log;
select count(*) as profiles_visible from profiles;
update profiles set status='disabled' where staff_id='owner1';
insert into audit_log(action,table_name) values('x','y');
select can_do('14-1','enter') as sm_14_1_enter, can_do('ITEMS','enter') as sm_items_enter, can_do('06-3','enter') as sm_po_enter;
reset role;

\echo '--- T5 give staff2 management role: can edit item; price history + audit written'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
insert into user_roles values ('00000000-0000-0000-0000-000000000002','management');
reset role;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
update items set sell_price=270 where code='I-001';
update items set code='X-1' where code='I-002';
insert into items(name_bn,sell_price,cost_price) values ('টেস্ট আইটেম',10,5);
select code, sell_price from items where code in ('I-001','I-058');
reset role;
select count(*) as price_hist_rows_i001 from item_price_history h join items i on i.id=h.item_id where i.code='I-001';
select action, table_name, record_id!='' as has_rid, staff_id from audit_log where table_name='items' order by id desc limit 3;

\echo '--- T6 last owner guard'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
delete from user_roles where user_id='00000000-0000-0000-0000-000000000001' and role_code='owner';
update profiles set status='disabled' where staff_id='owner1';
reset role;
select staff_id,status from profiles where staff_id='owner1';

\echo '--- T7 login lock'
set role anon;
select login_failed('staff2') from generate_series(1,4); select login_precheck('staff2') as after4;
select login_failed('staff2'); select login_precheck('staff2') as after5;
select login_failed('nobody'); 
select count(*) as items_for_anon from items;
reset role;
select staff_id, fails, locked from login_failures;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
select unlock_staff('staff2');
reset role;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
select unlock_staff('staff2'); select login_precheck('staff2') as after_unlock;
reset role;

\echo '--- T8 role matrix toggle by owner; non-owner blocked'
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
update role_form_perms set can_enter=false where role_code='storekeeper' and form_code='04-1'; 
select can_enter from role_form_perms where role_code='storekeeper' and form_code='04-1';
reset role;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
update role_form_perms set can_enter=true where role_code='storekeeper' and form_code='04-1';
update forms set red_block=false where code='14-1';
select (select red_block from forms where code='14-1') as red_block_14_1;
insert into corrections(user_id,note) values ('00000000-0000-0000-0000-000000000002','   ');
insert into corrections(user_id,note) values ('00000000-0000-0000-0000-000000000002','price fix');
insert into corrections(user_id,note) values ('00000000-0000-0000-0000-000000000001','spoof');
reset role;
\echo '--- done'
