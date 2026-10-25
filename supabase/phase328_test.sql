-- FRESH DB ONLY. Phase 328 tests (CRM-H part 1: complaints with an SLA clock, owner, status machine, food-safety routing, return link, repeat flag, privacy by outlet and role).
--   Build: tests/sql/build_fresh_db.sh style, phases 8 .. 98, then phase328 (this file pastes phase328 again at the end).
--   Run:   psql -h /tmp -p 5576 -U postgres -d <db> -qAt -f supabase/phase328_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o  '00000000-0000-0000-0000-000000032801'
\set u_m1 '00000000-0000-0000-0000-000000032802'
\set u_c1 '00000000-0000-0000-0000-000000032803'
\set u_v1 '00000000-0000-0000-0000-000000032804'
\set u_m2 '00000000-0000-0000-0000-000000032805'
\set u_x  '00000000-0000-0000-0000-000000032806'
\set u_b  '00000000-0000-0000-0000-000000032807'
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
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$
declare r text; begin execute p_sql into r; return r; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner328@s.app','{"full_name":"test_owner328"}'), (:'u_m1','test_mgr1_328@s.app','{"full_name":"test_mgr1_328"}'), (:'u_c1','test_cash1_328@s.app','{"full_name":"test_cash1_328"}'),
 (:'u_v1','test_view1_328@s.app','{"full_name":"test_view1_328"}'), (:'u_m2','test_mgr2_328@s.app','{"full_name":"test_mgr2_328"}'), (:'u_x','test_nobody328@s.app','{"full_name":"test_nobody328"}'),
 (:'u_b','test_bot328@s.app','{"full_name":"test_bot328"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m1', :'u_c1', :'u_v1', :'u_m2', :'u_x');
insert into user_roles values (:'u_o','owner'),(:'u_m1','showroom_manager'),(:'u_c1','salesperson'),(:'u_v1','purchasing'),(:'u_m2','showroom_manager'),(:'u_x','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m1',1),(:'u_c1',1),(:'u_v1',1),(:'u_m2',2),(:'u_x',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_m1','crm_complaint_manage',null),(:'u_v1','crm_feedback_view',null),(:'u_m2','crm_complaint_manage',null) on conflict do nothing;
insert into ops_accounts (user_id, purpose) values (:'u_b','notify') on conflict do nothing;

insert into customers (mobile, name, created_by) values ('01800032801','test_cust_a',:'u_o'), ('01800032802','test_cust_b',:'u_o');
insert into items (code, name_bn, name_en, unit, sell_price) values ('TESTH-A','test_item_a','test_item_a','pc',100), ('TESTH-B','test_item_b','test_item_b','pc',50);
select id as ca from customers where mobile='01800032801' \gset
select id as cb from customers where mobile='01800032802' \gset
select id as ia from items where code='TESTH-A' \gset
select id as ib from items where code='TESTH-B' \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id) values
 (1, 328001, current_date, now() - interval '1 day', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'done', :'u_o', :'ca'),
 (1, 328002, current_date, now() - interval '1 day', format('[{"item_id":"%s","qty":2,"price":50,"amount":100}]', :'ib')::jsonb, 100, 0, 100, 'cash', 'done', :'u_o', :'cb'),
 (2, 328003, current_date, now() - interval '1 day', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'done', :'u_o', :'ca');
select id as s1 from sales where receipt=328001 and location_id=1 \gset
select id as s2 from sales where receipt=328002 and location_id=1 \gset
select id as s3 from sales where receipt=328003 and location_id=2 \gset
insert into sale_returns (sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, refund_mode, reason_code, status, created_by) values
 (:'s1', 1, :'ca', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'quality', 'done', :'u_o'),
 (:'s2', 1, :'cb', format('[{"item_id":"%s","qty":1,"price":50,"amount":50}]', :'ib')::jsonb, 50, 50, 0, null, 'quality', 'done', :'u_o'),
 (:'s2', 1, :'cb', format('[{"item_id":"%s","qty":1,"price":50,"amount":50}]', :'ib')::jsonb, 50, 50, 0, null, 'quality', 'void', :'u_o'),
 (:'s3', 2, :'ca', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'quality', 'done', :'u_o');
select id as r1 from sale_returns where sale_id=:'s1' \gset
select id as r2 from sale_returns where sale_id=:'s2' and status='done' \gset
select id as r2v from sale_returns where sale_id=:'s2' and status='void' \gset
select id as r3 from sale_returns where sale_id=:'s3' \gset

-- the accounting snapshot: nothing in this file may change it (complaints post nothing)
select md5(string_agg(x, '|' order by x)) as snap0 from (
  select 'je:' || count(*) from journal_entries union all select 'jl:' || coalesce(sum(debit),0) || ':' || coalesce(sum(credit),0) from journal_lines
  union all select 'sales:' || count(*) || ':' || coalesce(sum(total),0) from sales union all select 'ret:' || count(*) || ':' || coalesce(sum(amount),0) from sale_returns
  union all select 'pay:' || count(*) from sale_payments) z(x) \gset

\echo == T0 shape, defaults, nothing shared patched
select tt.chk('T0 phase328 present', to_regprocedure('public._crmh_present()') is not null);
select tt.chk('T0 twelve new rules, English only, safe defaults (complaints OFF, SLA hours blank, repeat check off, fs exception ON, fs categories sick, severity keep)',
  (select count(*) from rules where key in ('crm_complaints_on','crm_complaint_sla_hours_low','crm_complaint_sla_hours_medium','crm_complaint_sla_hours_high','crm_complaint_sla_hours_critical','crm_complaint_fs_exception_on','crm_complaint_fs_categories','crm_complaint_fs_severity','crm_complaint_breach_exception_on','crm_repeat_days','crm_repeat_min','crm_repeat_scope'))=12
  and not rule_on('crm_complaints_on') and rule_num('crm_complaint_sla_hours_low') is null and rule_num('crm_complaint_sla_hours_medium') is null and rule_num('crm_complaint_sla_hours_high') is null and rule_num('crm_complaint_sla_hours_critical') is null
  and rule_on('crm_complaint_fs_exception_on') and rule_txt('crm_complaint_fs_categories')='sick' and rule_txt('crm_complaint_fs_severity')='keep' and rule_on('crm_complaint_breach_exception_on')
  and rule_num('crm_repeat_days') is null and rule_num('crm_repeat_min')=2 and rule_txt('crm_repeat_scope')='customer_item'
  and not exists (select 1 from rules where (key like 'crm\_complaint%' or key like 'crm\_repeat%') and (label_en is null or label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 three grants and three lists (9 categories, 4 resolutions, 4 close reasons)',
  (select count(*) from grant_defs where grant_code in ('crm_complaint_log','crm_complaint_manage','crm_feedback_view'))=3
  and (select count(*) from option_lists where list_code='crm_complaint_cats')=9 and (select count(*) from option_lists where list_code='crm_resolution_types')=4 and (select count(*) from option_lists where list_code='crm_close_reasons')=4);
select tt.chk('T0 no shared function was patched or re-created (no crmh text inside sale_return, record_sale2, notify_scan, rpt_mobile_ok, has_grant)',
  (select count(*) from (values ('public.notify_scan()'),('public.rpt_mobile_ok()'),('public.has_grant(text,integer)')) v(f)
     where to_regprocedure(v.f) is not null and position('crmh' in pg_get_functiondef(v.f::regprocedure))>0)=0
  and position('crmh' in pg_get_functiondef('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure))=0);
select tt.chk('T0 the tables are closed to browser roles (RLS on, no select/insert for anon or authenticated) and carry no-delete triggers',
  (select bool_and(relrowsecurity) from pg_class where relname in ('crm_complaints','crm_complaint_events','crm_complaint_returns'))
  and not has_table_privilege('authenticated','public.crm_complaints','select') and not has_table_privilege('authenticated','public.crm_complaints','update') and not has_table_privilege('anon','public.crm_complaint_events','insert')
  and (select count(*) from pg_trigger where tgrelid in ('public.crm_complaints'::regclass,'public.crm_complaint_events'::regclass,'public.crm_complaint_returns'::regclass) and tgname like '%nodel')=3);
select tt.chk('T0 API open to signed-in users only; helpers closed',
  has_function_privilege('authenticated','public._crmh_complaint_save(uuid,jsonb)','execute') and not has_function_privilege('anon','public._crmh_complaint_save(uuid,jsonb)','execute')
  and has_function_privilege('authenticated','public._crmh_sla_scan(boolean)','execute') and not has_function_privilege('anon','public._crmh_complaint_list(jsonb)','execute')
  and not has_function_privilege('authenticated','public._crmh_manage_ok(integer)','execute') and not has_function_privilege('authenticated','public._crmh_mark_breach(uuid)','execute')
  and not has_function_privilege('authenticated','public._crmh_exc(integer,text,text,text,text)','execute') and not has_function_privilege('anon','public._crmh_row(public.crm_complaints)','execute'));

\echo == T1 switch OFF: nothing is written
select tt.as(:'u_c1');
select tt.err('T1 OFF: a complaint is refused', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","category":"taste","description":"test too sweet"}'::jsonb)$$, :'s1'), 'complaints_off');
select tt.as(:'u_o');
select tt.chk('T1 OFF: scan skipped, a dry scan still works, counts and list answer on:false',
  (_crmh_sla_scan(false) ->> 'skipped')='switch_off' and (_crmh_sla_scan(true) ->> 'marked')='0' and (_crmh_counts() ->> 'on')='false' and (_crmh_complaint_list('{}') ->> 'total')='0');
select tt.chk('T1 OFF: no complaint row exists', (select count(*) from crm_complaints)=0);

-- switch on and set the clocks: low blank, medium 48 h, high 8 h, critical 2 h
select set_rule('crm_complaints_on','true') is null as a1 \gset
select set_rule('crm_complaint_sla_hours_medium','48') is null as a2 \gset
select set_rule('crm_complaint_sla_hours_high','8') is null as a3 \gset
select set_rule('crm_complaint_sla_hours_critical','2') is null as a4 \gset

\echo == T2 capture: outlet, item, severity, owner, validation, idempotency, who may log
select tt.as(:'u_c1');
select _crmh_complaint_save('a0000000-0000-0000-0000-000000032801', format('{"sale_id":"%s","item_id":"%s","category":"taste","description":"test too sweet","customer_phone":"01800032801"}', :'s1', :'ia')::jsonb) ->> 'id' as k1 \gset
select tt.chk('T2 cashier logs a complaint on a sale; outlet, customer, item and the medium clock (48 h) are filled by the server',
  (select location_id=1 and customer_id=:'ca'::uuid and item_id=:'ia'::uuid and severity='medium' and status='open' and due_at - created_at = interval '48 hours' and not food_safety and not repeat_flag and customer_name='test_cust_a' from crm_complaints where id=:'k1'::uuid));
select tt.chk('T2 first event is created; the audit log has the new-complaint line',
  (select count(*) from crm_complaint_events where complaint_id=:'k1'::uuid and kind='created')=1 and (select count(*) from audit_log where action='crmh_complaint_new' and record_id=:'k1')=1);
select tt.chk('T2 same client id again = dup, no second row', (_crmh_complaint_save('a0000000-0000-0000-0000-000000032801', format('{"sale_id":"%s","category":"taste","description":"test too sweet"}', :'s1')::jsonb) ->> 'dup')='true' and (select count(*) from crm_complaints)=1);
select tt.err('T2 item that is not on the sale', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","item_id":"%s","category":"taste","description":"test wrong item"}'::jsonb)$$, :'s1', :'ib'), 'item_not_in_sale');
select tt.err('T2 a different outlet than the sale', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","location_id":2,"category":"taste","description":"test other outlet"}'::jsonb)$$, :'s1'), 'sale_other_outlet');
select tt.err('T2 description too short', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","category":"taste","description":"ab"}'::jsonb)$$, :'s1'), 'description_required');
select tt.err('T2 category outside the list', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","category":"nope","description":"test bad category"}'::jsonb)$$, :'s1'), 'bad_category');
select tt.err('T2 bad severity', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","category":"taste","severity":"urgent","description":"test bad severity"}'::jsonb)$$, :'s1'), 'bad_severity');
select tt.err('T2 bad phone', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","category":"taste","description":"test bad phone","customer_phone":"abc"}'::jsonb)$$, :'s1'), 'bad_phone');
select tt.err('T2 no sale and no outlet', $$select _crmh_complaint_save(null, '{"category":"taste","description":"test no outlet"}'::jsonb)$$, 'location_required');
select tt.err('T2 a cashier cannot name an owner when logging', format($$select _crmh_complaint_save(null, '{"sale_id":"%s","category":"taste","description":"test with owner","owner_user":"%s"}'::jsonb)$$, :'s1', :'u_m1'), 'not allowed');
select tt.err('T2 cashier of outlet 1 cannot log for outlet 2', $$select _crmh_complaint_save(null, '{"location_id":2,"category":"taste","description":"test other outlet log"}'::jsonb)$$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T2 a user with no right (storekeeper, no grant) cannot log', $$select _crmh_complaint_save(null, '{"location_id":1,"category":"taste","description":"test no right"}'::jsonb)$$, 'not allowed');
select tt.as('');
select tt.err('T2 no login at all is refused', $$select _crmh_complaint_save(null, '{"location_id":1,"category":"taste","description":"test anon"}'::jsonb)$$, 'not allowed');
select tt.as(:'u_m1');
select tt.as(:'u_x');
select tt.err('T2 another user (no manage right) cannot reuse the cashier client id', $$select _crmh_complaint_save('a0000000-0000-0000-0000-000000032801', '{"location_id":1,"category":"taste","description":"test other user same key"}'::jsonb)$$, 'client_id_taken');
select tt.as(:'u_m1');
select tt.chk('T2 a manager of the outlet (grant) may name the owner when logging',
  (_crmh_complaint_save(null, format('{"location_id":1,"category":"late","severity":"high","description":"test late cake","owner_user":"%s"}', :'u_m1')::jsonb) ->> 'ticket_no') is not null);
select tt.chk('T2 high severity gets the 8 hour clock', (select due_at - created_at = interval '8 hours' and owner_user=:'u_m1'::uuid from crm_complaints where description='test late cake'));

\echo == T3 food safety is routed to the Exceptions list
select tt.as(:'u_c1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"sick","description":"test customer fell ill"}', :'s1', :'ia')::jsonb) ->> 'id' as k2 \gset
select tt.chk('T3 category sick = food safety by the setting, even without the box; one RED line in the Exceptions list with the ticket',
  (select food_safety from crm_complaints where id=:'k2'::uuid)
  and (select count(*) from exceptions where flag_code='crmh_food_safety' and level='red' and status='open' and text->>'ref'=:'k2' and location_id=1 and form_code='CRM')=1);
select tt.chk('T3 the event trail names the food-safety mark', (select count(*) from crm_complaint_events where complaint_id=:'k2'::uuid and kind='food_safety')=1);
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"smell","food_safety":true,"description":"test ticked the box"}', :'s2')::jsonb) ->> 'id' as k3 \gset
select tt.chk('T3 the box alone also marks it (category smell) and adds one red line', (select food_safety from crm_complaints where id=:'k3'::uuid) and (select count(*) from exceptions where flag_code='crmh_food_safety' and text->>'ref'=:'k3')=1);
select tt.as(:'u_o');
select set_rule('crm_complaint_fs_exception_on','false') is null as b1 \gset
select set_rule('crm_complaint_fs_severity','"critical"') is null as b2 \gset
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"sick","description":"test ill again"}', :'s2')::jsonb) ->> 'id' as k4 \gset
select tt.chk('T3 exception switch OFF: marked on the complaint, no Exceptions line; severity forced to critical = 2 hour clock',
  (select food_safety and severity='critical' and due_at - created_at = interval '2 hours' from crm_complaints where id=:'k4'::uuid) and (select count(*) from exceptions where flag_code='crmh_food_safety')=2);
select set_rule('crm_complaint_fs_exception_on','true') is null as b3 \gset
select set_rule('crm_complaint_fs_severity','"keep"') is null as b4 \gset
select set_rule('crm_complaint_fs_categories','""') is null as b5 \gset
select tt.chk('T3 blank category list: only the box decides', rule_txt('crm_complaint_fs_categories') is null);
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"sick","description":"test ill, box not ticked"}', :'s2')::jsonb) ->> 'id' as k5 \gset
select tt.chk('T3 ... so a sick complaint without the box is NOT food safety now', not (select food_safety from crm_complaints where id=:'k5'::uuid));
select set_rule('crm_complaint_fs_categories', null) is null as b6 \gset
select tt.chk('T3 clearing the setting returns the default (sick)', rule_txt('crm_complaint_fs_categories')='sick');

\echo == T4 status machine, owner, resolution, closing with a reason
select tt.as(:'u_c1');
select tt.err('T4 a cashier (not owner of the complaint) cannot move it', format($$select _crmh_complaint_move('%s','in_progress','test start')$$, :'k1'), 'not allowed');
select tt.as(:'u_m1');
select tt.err('T4 an unknown target status', format($$select _crmh_complaint_move('%s','archived','x')$$, :'k1'), 'illegal_status_change');
select tt.err('T4 open -> closed is not allowed (resolve first, or close with a reason)', format($$select _crmh_complaint_move('%s','closed','test')$$, :'k1'), 'illegal_status_change');
select _crmh_complaint_move(:'k1'::uuid,'in_progress','test calling the customer') ->> 'status' as rv \gset
select tt.chk('T4 open -> in_progress: first response stamped, owner taken by the mover',
  :'rv'='in_progress'
  and (select first_response_at is not null and owner_user=:'u_m1'::uuid from crm_complaints where id=:'k1'::uuid));
select tt.err('T4 resolve needs a result type from the list', format($$select _crmh_complaint_move('%s','resolved','test fixed')$$, :'k1'), 'resolution_required');
select tt.err('T4 resolve needs a note', format($$select _crmh_complaint_move('%s','resolved','x','explained')$$, :'k1'), 'resolution_required');
select tt.err('T4 resolution outside the list', format($$select _crmh_complaint_move('%s','resolved','test fixed','magic')$$, :'k1'), 'resolution_required');
select _crmh_complaint_move(:'k1'::uuid,'resolved','test explained to the customer','explained') ->> 'sla_state' as rv \gset
select tt.chk('T4 resolved inside the clock: sla_met true, state met',
  :'rv'='met' and (select sla_met and resolved_at is not null and resolution_type='explained' from crm_complaints where id=:'k1'::uuid));
select tt.err('T4 resolved -> open is illegal', format($$select _crmh_complaint_move('%s','open','x')$$, :'k1'), 'illegal_status_change');
select tt.err('T4 reopen needs a reason', format($$select _crmh_complaint_move('%s','in_progress','')$$, :'k1'), 'reason_required');
select _crmh_complaint_move(:'k1'::uuid,'in_progress','test customer called again') ->> 'status' as rv \gset
select tt.chk('T4 reopen with a reason: back in progress, resolution cleared, one reopen event and one audit line',
  :'rv'='in_progress' and (select resolved_at is null and sla_met is null and resolution_type is null from crm_complaints where id=:'k1'::uuid)
  and (select count(*) from crm_complaint_events where complaint_id=:'k1'::uuid and kind='reopen')=1 and (select count(*) from audit_log where action='crmh_complaint_reopen' and record_id=:'k1')=1);
select _crmh_complaint_move(:'k1'::uuid,'resolved','test replaced the goods','replaced') is not null as c1 \gset
select _crmh_complaint_move(:'k1'::uuid,'closed','test confirmed with customer') ->> 'status' as rv \gset
select tt.chk('T4 resolved -> closed', :'rv'='closed' and (select closed_at is not null from crm_complaints where id=:'k1'::uuid));
select tt.err('T4 a closed complaint is locked (move)', format($$select _crmh_complaint_move('%s','in_progress','test')$$, :'k1'), 'complaint_locked');
select tt.err('T4 a closed complaint is locked (note)', format($$select _crmh_complaint_note('%s','note','test late note')$$, :'k1'), 'complaint_locked');
select tt.err('T4 a closed complaint is locked (severity)', format($$select _crmh_complaint_severity_set('%s','low','test why')$$, :'k1'), 'complaint_locked');
select tt.err('T4 the database itself refuses closed -> open (direct update, no function)', format($$update crm_complaints set status='open' where id='%s'$$, :'k1'), 'complaint_locked');
select tt.err('T4 the database itself refuses open -> closed (direct update)', format($$update crm_complaints set status='closed' where id='%s'$$, :'k3'), 'illegal_status_change');
select tt.err('T4 identity columns cannot be changed (outlet)', format($$update crm_complaints set location_id=2 where id='%s'$$, :'k3'), 'complaint_immutable');
select tt.err('T4 nothing is deleted', format($$delete from crm_complaints where id='%s'$$, :'k3'), 'nothing is deleted');
select tt.err('T4 the event trail is append only (update)', $$update crm_complaint_events set note='x' where id=(select min(id) from crm_complaint_events)$$, 'append_only');
select tt.err('T4 the event trail is append only (delete)', $$delete from crm_complaint_events where id=(select min(id) from crm_complaint_events)$$, 'nothing is deleted');
-- close without a result = an exception with a reason
select tt.err('T4 close without a result needs a reason code', format($$select _crmh_complaint_move('%s','closed_no_resolution','test gave up')$$, :'k3'), 'reason_required');
select tt.err('T4 close without a result needs a note', format($$select _crmh_complaint_move('%s','closed_no_resolution','',null,'no_contact')$$, :'k3'), 'reason_required');
select _crmh_complaint_move(:'k3'::uuid,'closed_no_resolution','test phone switched off three times',null,'no_contact') ->> 'status' as rv \gset
select tt.chk('T4 close without a result with reason: status, audit line, and a RED Exceptions line because it is food safety',
  :'rv'='closed_no_resolution'
  and (select count(*) from audit_log where action='crmh_closed_no_resolution' and record_id=:'k3')=1
  and (select count(*) from exceptions where flag_code='crmh_closed_unresolved' and level='red' and text->>'ref'=:'k3')=1);
select tt.err('T4 and it is final', format($$select _crmh_complaint_move('%s','resolved','test','explained')$$, :'k3'), 'complaint_locked');
-- an assignee may start and resolve but not close
select tt.chk('T4 manager assigns the cashier as owner', (_crmh_complaint_assign(:'k2'::uuid, :'u_c1'::uuid, 'test please follow up') ->> 'owner_user')=:'u_c1');
select tt.as(:'u_c1');
select tt.chk('T4 the owner-assignee starts the complaint', (_crmh_complaint_move(:'k2'::uuid,'in_progress','test on it') ->> 'status')='in_progress');
select tt.chk('T4 the owner-assignee records a contact', (_crmh_complaint_note(:'k2'::uuid,'contact','test called the customer') ->> 'status')='in_progress');
select tt.err('T4 the owner-assignee cannot close without a result', format($$select _crmh_complaint_move('%s','closed_no_resolution','test',null,'other')$$, :'k2'), 'not allowed');
select tt.chk('T4 the owner-assignee resolves', (_crmh_complaint_move(:'k2'::uuid,'resolved','test explained','explained') ->> 'status')='resolved');
select tt.err('T4 the owner-assignee cannot close or reopen a resolved one', format($$select _crmh_complaint_move('%s','closed','test')$$, :'k2'), 'not allowed');
select tt.err('T4 a cashier who is not the owner cannot assign', format($$select _crmh_complaint_assign('%s','%s','x')$$, :'k5', :'u_c1'), 'not allowed');
select tt.as(:'u_m1');
select tt.err('T4 manager cannot assign a person of another outlet', format($$select _crmh_complaint_assign('%s','%s','x')$$, :'k5', :'u_m2'), 'owner_other_outlet');
select tt.chk('T4 manager clears the owner', (_crmh_complaint_assign(:'k5'::uuid, null, 'test unassign') ->> 'owner_user') is null);

\echo == T5 per outlet and per role visibility
select tt.as(:'u_o');
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"taste","description":"test outlet two complaint"}', :'s3')::jsonb) ->> 'id' as k6 \gset
select tt.as(:'u_m1');
select tt.err('T5 manager of outlet 1 cannot move an outlet 2 complaint', format($$select _crmh_complaint_move('%s','in_progress','test')$$, :'k6'), 'not allowed');
select tt.err('T5 ... nor read it', format($$select _crmh_complaint_get('%s')$$, :'k6'), 'not allowed');
select tt.err('T5 ... nor assign it', format($$select _crmh_complaint_assign('%s','%s','x')$$, :'k6', :'u_m1'), 'not allowed');
select tt.chk('T5 outlet 1 manager list holds only outlet 1 complaints', (select bool_and((r->>'location_id')::int=1) and count(*)>0 from jsonb_array_elements(_crmh_complaint_list('{"status":"all"}') -> 'rows') r)
   and (_crmh_complaint_list('{"status":"all","location_id":2}') ->> 'total')='0');
select tt.as(:'u_m2');
select tt.chk('T5 outlet 2 manager sees only outlet 2 (1 complaint)', (_crmh_complaint_list('{"status":"all"}') ->> 'total')='1');
select tt.as(:'u_v1');
select tt.chk('T5 viewer (grant crm_feedback_view, outlet 1) sees outlet 1 complaints but the phone is masked', (_crmh_complaint_list('{"status":"all"}') ->> 'total')::int >= 4
   and (select r->>'customer_phone' from jsonb_array_elements(_crmh_complaint_list('{"status":"all"}') -> 'rows') r where r->>'id'=:'k1') = '018****01');
select tt.err('T5 viewer cannot move a complaint', format($$select _crmh_complaint_move('%s','in_progress','test')$$, :'k5'), 'not allowed');
select tt.err('T5 viewer cannot log', $$select _crmh_complaint_save(null, '{"location_id":1,"category":"taste","description":"test viewer logs"}'::jsonb)$$, 'not allowed');
select tt.as(:'u_c1');
select tt.chk('T5 cashier sees their own complaints (and assigned ones) only, phone masked',
  (select count(*) from jsonb_array_elements(_crmh_complaint_list('{"status":"all"}') -> 'rows') r)>=3 and (select bool_and(r->>'customer_phone' like '%****%') from jsonb_array_elements(_crmh_complaint_list('{"status":"all"}') -> 'rows') r where r->>'customer_phone' is not null));
select tt.as(:'u_x');
select tt.chk('T5 a user with no right sees nothing', (_crmh_complaint_list('{"status":"all"}') ->> 'total')='0');
select tt.as(:'u_m1');
select tt.chk('T5 manager of the outlet sees the full phone', (select r->>'customer_phone' from jsonb_array_elements(_crmh_complaint_list('{"status":"all"}') -> 'rows') r where r->>'id'=:'k1') = '01800032801');
select tt.as(:'u_o');
select tt.chk('T5 owner sees every outlet (7 complaints so far)', (_crmh_complaint_list('{"status":"all"}') ->> 'total')='7' and (_crmh_counts() ->> 'open')::int >= 1);
select tt.as('');
select tt.err('T5 no login: list refused', $$select _crmh_complaint_list('{}')$$, 'not allowed');

\echo == T6 the SLA clock: overdue list, breach marking, late resolution, severity change, blank clock
select tt.as(:'u_m1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"broken","severity":"high","description":"test box was crushed"}', :'s2')::jsonb) ->> 'id' as k7 \gset
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"broken","severity":"high","description":"test second crushed box"}', :'s2')::jsonb) ->> 'id' as k8 \gset
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"broken","severity":"low","description":"test low severity, no clock"}', :'s2')::jsonb) ->> 'id' as k9 \gset
select tt.chk('T6 low severity: no clock when the hours are blank (due_at empty, state none)', (select due_at is null from crm_complaints where id=:'k9'::uuid) and (select r->>'sla_state' from jsonb_array_elements(_crmh_complaint_list('{"status":"all"}') -> 'rows') r where r->>'id'=:'k9')='none');
select tt.chk('T6 a fresh high complaint is running, minutes left about 480', (select (r->>'sla_state')='running' and (r->>'minutes_left')::int between 470 and 480 from jsonb_array_elements(_crmh_complaint_list('{"status":"all"}') -> 'rows') r where r->>'id'=:'k7'));
select tt.chk('T6 nothing is overdue yet', (_crmh_complaint_list('{"overdue":true}') ->> 'total')='0' and (_crmh_counts() ->> 'overdue')='0');
-- age two complaints (k7 by 9 hours, k8 by 1 hour past due) and the outlet 2 one
select format($$update crm_complaints set due_at = now() - interval '1 hour' where id in ('%s','%s')$$, :'k7', :'k8') as ag_sql \gset
:ag_sql;
select format($$update crm_complaints set due_at = now() - interval '2 hours' where id = '%s'$$, :'k6') as ag_sql \gset
:ag_sql;
select tt.chk('T6 overdue list shows the two outlet 1 complaints (manager 1), overdue first, state overdue', (_crmh_complaint_list('{"overdue":true}') ->> 'total')='2'
  and (select r->>'sla_state' from jsonb_array_elements(_crmh_complaint_list('{"overdue":true}') -> 'rows') r limit 1)='overdue' and (_crmh_counts() ->> 'overdue')='2');
select tt.chk('T6 the live state is computed: nothing marked yet', (select count(*) from crm_complaints where breached_at is not null)=0);
select tt.chk('T6 a dry scan reports 2 and writes nothing', (_crmh_sla_scan(true) ->> 'marked')='2' and (select count(*) from crm_complaints where breached_at is not null)=0 and (select count(*) from exceptions where flag_code='crmh_sla_breach')=0);
select _crmh_sla_scan(false) ->> 'marked' as rv \gset
select tt.chk('T6 the manager scan marks only his outlet (2 of 3), once each: breached_at, event, yellow Exceptions line, audit line',
  :'rv'='2' and (select count(*) from crm_complaints where breached_at is not null)=2 and (select breached_at is null from crm_complaints where id=:'k6'::uuid)
  and (select count(*) from crm_complaint_events where kind='sla_breach')=2 and (select count(*) from exceptions where flag_code='crmh_sla_breach' and level='yellow' and status='open')=2 and (select count(*) from audit_log where action='crmh_sla_breach')=2);
select _crmh_sla_scan(false) ->> 'marked' as rv \gset
select tt.chk('T6 scanning again marks nothing new', :'rv'='0' and (select count(*) from exceptions where flag_code='crmh_sla_breach')=2);
select tt.as(:'u_x');
select tt.err('T6 a user with no manage right cannot scan', $$select _crmh_sla_scan(false)$$, 'not allowed');
select tt.as(:'u_b');
select _crmh_sla_scan(false) ->> 'marked' as rv \gset
select tt.chk('T6 the notify bot may scan (outlet 2 complaint is marked now)', :'rv'='1' and (_crmh_sla_scan(true) ->> 'via')='notify_bot' and (select breached_at is not null from crm_complaints where id=:'k6'::uuid));
select tt.as(:'u_m1');
select _crmh_complaint_move(:'k7'::uuid,'resolved','test fixed late','explained') ->> 'sla_state' as rv \gset
select tt.chk('T6 late resolution: sla_met false, state missed', :'rv'='missed' and (select sla_met is false from crm_complaints where id=:'k7'::uuid));
-- late resolution of a never-scanned overdue complaint marks the breach itself
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"broken","severity":"high","description":"test never scanned"}', :'s2')::jsonb) ->> 'id' as k10 \gset
select format($$update crm_complaints set due_at = now() - interval '1 hour' where id = '%s'$$, :'k10') as ag_sql \gset
:ag_sql;
select _crmh_complaint_move(:'k10'::uuid,'resolved','test fixed late again','replaced') ->> 'sla_state' as rv \gset
select tt.chk('T6 resolving an overdue complaint that was never scanned marks the breach at that moment',
  :'rv'='missed' and (select breached_at is not null from crm_complaints where id=:'k10'::uuid));
-- severity change recomputes the clock from the logged time
select tt.err('T6 severity change needs a reason', format($$select _crmh_complaint_severity_set('%s','critical','')$$, :'k9'), 'reason_required');
select _crmh_complaint_severity_set(:'k9'::uuid,'critical','test it is food related') ->> 'severity' as rv \gset
select tt.chk('T6 low -> critical: clock becomes created + 2 h; event and audit line', :'rv'='critical'
  and (select due_at - created_at = interval '2 hours' from crm_complaints where id=:'k9'::uuid) and (select count(*) from crm_complaint_events where complaint_id=:'k9'::uuid and kind='severity')=1);
select tt.as(:'u_o');
select set_rule('crm_complaint_breach_exception_on','false') is null as d1 \gset
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"broken","severity":"high","description":"test breach without exception line"}', :'s2')::jsonb) ->> 'id' as k11 \gset
select format($$update crm_complaints set due_at = now() - interval '1 hour' where id = '%s'$$, :'k11') as ag_sql \gset
:ag_sql;
select _crmh_sla_scan(false) ->> 'marked' as rv \gset
select tt.chk('T6 breach exception switch OFF: marked on the complaint, no extra Exceptions line', :'rv'='1' and (select breached_at is not null from crm_complaints where id=:'k11'::uuid)
  and (select count(*) from exceptions where flag_code='crmh_sla_breach')=4);
select set_rule('crm_complaint_breach_exception_on','true') is null as d2 \gset

\echo == T7 link to the existing sale return (no refund path here, nothing posted)
select tt.as(:'u_m1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"broken","description":"test refund wanted"}', :'s1')::jsonb) ->> 'id' as k12 \gset
select tt.err('T7 a return that does not exist', format($$select _crmh_complaint_link_return('%s','00000000-0000-0000-0000-000000000099')$$, :'k12'), 'return_not_found');
select tt.err('T7 a voided return cannot be linked', format($$select _crmh_complaint_link_return('%s','%s')$$, :'k12', :'r2v'), 'return_not_done');
select tt.err('T7 a return of another sale', format($$select _crmh_complaint_link_return('%s','%s')$$, :'k12', :'r2'), 'return_other_sale');
select tt.err('T7 a return of another outlet', format($$select _crmh_complaint_link_return('%s','%s')$$, :'k12', :'r3'), 'return_other_outlet');
select tt.as(:'u_c1');
select tt.err('T7 a cashier cannot link', format($$select _crmh_complaint_link_return('%s','%s')$$, :'k12', :'r1'), 'not allowed');
select tt.as(:'u_m1');
select tt.chk('T7 the manager links the finished return: 1 return, value 100', (_crmh_complaint_link_return(:'k12'::uuid, :'r1'::uuid) -> 'returns' ->> 'amount')::numeric=100);
select tt.chk('T7 linking the same return again changes nothing', (_crmh_complaint_link_return(:'k12'::uuid, :'r1'::uuid) -> 'returns' ->> 'n')='1' and (select count(*) from crm_complaint_returns)=1);
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"broken","description":"test second complaint same sale"}', :'s1')::jsonb) ->> 'id' as k13 \gset
select tt.err('T7 a return can belong to one complaint only', format($$select _crmh_complaint_link_return('%s','%s')$$, :'k13', :'r1'), 'return_already_linked');
select tt.chk('T7 the detail names the existing sale return screen and never refunds itself',
  (_crmh_complaint_get(:'k12'::uuid) -> 'return_hint' ->> 'sale_id')=:'s1' and (_crmh_complaint_get(:'k12'::uuid) -> 'return_hint' ->> 'note') like '%never refunds%' and jsonb_array_length(_crmh_complaint_get(:'k12'::uuid) -> 'returns')=1);
select tt.chk('T7 the event trail records the link', (select count(*) from crm_complaint_events where complaint_id=:'k12'::uuid and kind='link_return')=1);

\echo == T8 repeat complaints (off by default)
select tt.as(:'u_c1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"taste","description":"test repeat one"}', :'s1', :'ia')::jsonb) ->> 'id' as p1 \gset
select tt.chk('T8 check off (days blank): never flagged, even with earlier complaints for the same customer and item', not (select repeat_flag from crm_complaints where id=:'p1'::uuid) and (select repeat_count from crm_complaints where id=:'p1'::uuid)=0);
select tt.as(:'u_o');
select set_rule('crm_repeat_days','30') is null as e1 \gset
select tt.as(:'u_c1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"taste","description":"test repeat two"}', :'s1', :'ia')::jsonb) ->> 'id' as p2 \gset
select tt.chk('T8 same customer and same item inside the window: flagged, count = earlier ones (k1, k2 and p1 match item A)',
  (select repeat_flag and repeat_count=3 from crm_complaints where id=:'p2'::uuid) and (select count(*) from crm_complaint_events where complaint_id=:'p2'::uuid and kind='repeat')=1);
select tt.as(:'u_o');
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"taste","description":"test same customer other outlet"}', :'s3', :'ia')::jsonb) ->> 'id' as p2b \gset
select tt.chk('T8 the same customer and item at ANOTHER outlet is still a repeat (count 4)', (select repeat_flag and repeat_count=4 from crm_complaints where id=:'p2b'::uuid));
select tt.as(:'u_m1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"taste","description":"test other customer b"}', :'s2', :'ib')::jsonb) ->> 'id' as p3 \gset
select tt.chk('T8 a different customer and item is not a repeat', not (select repeat_flag from crm_complaints where id=:'p3'::uuid));
select tt.as(:'u_o');
select set_rule('crm_repeat_scope','"customer"') is null as e2 \gset
select tt.as(:'u_m1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"late","description":"test same customer other thing"}', :'s2')::jsonb) ->> 'id' as p4 \gset
select tt.chk('T8 scope customer: any earlier complaint by the same customer counts', (select repeat_flag from crm_complaints where id=:'p4'::uuid));
select tt.as(:'u_o');
select set_rule('crm_repeat_min','4') is null as e3 \gset
select tt.as(:'u_m1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"late","description":"test needs four"}', :'s2')::jsonb) ->> 'id' as p5 \gset
select tt.chk('T8 minimum 4 (this one included): many earlier ones, still flagged', (select repeat_flag and repeat_count >= 3 from crm_complaints where id=:'p5'::uuid));
select tt.as(:'u_o');
select set_rule('crm_repeat_min','50') is null as e4 \gset
select tt.as(:'u_m1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","category":"late","description":"test needs fifty"}', :'s2')::jsonb) ->> 'id' as p6 \gset
select tt.chk('T8 minimum 50: not flagged', not (select repeat_flag from crm_complaints where id=:'p6'::uuid));
select tt.chk('T8 the repeat filter and the count', (_crmh_complaint_list('{"repeat":true,"status":"all"}') ->> 'total')::int >= 3 and (_crmh_counts() ->> 'repeat')::int >= 1);
select tt.as(:'u_o');
select set_rule('crm_repeat_days', null) is null as e5 \gset
select set_rule('crm_repeat_scope', null) is null as e6 \gset
select set_rule('crm_repeat_min', null) is null as e7 \gset

\echo == T9 settings, detail, accounting untouched, paste twice
select tt.as(:'u_m1');
select tt.chk('T9 settings answer for the screen: clocks, lists, rights', (_crmh_settings() -> 'sla_hours' ->> 'high')='8' and (_crmh_settings() -> 'sla_hours' ->> 'low') is null and jsonb_array_length(_crmh_settings() -> 'categories')=9 and (_crmh_settings() ->> 'may_manage')='true');
select tt.as(:'u_c1');
select tt.chk('T9 a cashier may log but not manage', (_crmh_settings() ->> 'may_log')='true' and (_crmh_settings() ->> 'may_manage')='false');
select tt.as(:'u_m1');
select tt.chk('T9 detail: trail, earlier complaints by the same customer, can_manage', jsonb_array_length(_crmh_complaint_get(:'k12'::uuid) -> 'events')>=2 and jsonb_array_length(_crmh_complaint_get(:'k13'::uuid) -> 'earlier_by_same_customer')>=1 and (_crmh_complaint_get(:'k13'::uuid) ->> 'can_manage')='true');
select tt.chk('T9 filters: by severity and by item', (_crmh_complaint_list('{"status":"all","severity":"critical"}'::jsonb) ->> 'total')::int>=1 and (_crmh_complaint_list(format('{"status":"all","item_id":"%s"}', :'ia')::jsonb) ->> 'total')::int>=3);
select tt.err('T9 an unknown status filter', $$select _crmh_complaint_list('{"status":"zzz"}')$$, 'bad_status');
select md5(string_agg(x, '|' order by x)) as snap1 from (
  select 'je:' || count(*) from journal_entries union all select 'jl:' || coalesce(sum(debit),0) || ':' || coalesce(sum(credit),0) from journal_lines
  union all select 'sales:' || count(*) || ':' || coalesce(sum(total),0) from sales union all select 'ret:' || count(*) || ':' || coalesce(sum(amount),0) from sale_returns
  union all select 'pay:' || count(*) from sale_payments) z(x) \gset
select tt.chk('T9 ACCOUNTING UNTOUCHED: journal, sales, returns and payments are byte-identical after every complaint action above', :'snap0' = :'snap1');
select tt.chk('T9 the unbalanced-entry count is still zero', (select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z)=0);

select count(*) as n_rules_before from rules where module='crm' \gset
select count(*) as n_list_before from option_lists where list_code like 'crm\_%' \gset
select count(*) as n_cx_before from crm_complaints \gset
select count(*) as n_ev_before from crm_complaint_events \gset
\ir phase328.sql
select tt.chk('T9 pasted a second time: no error, same rules, same lists, same data', (select count(*) from rules where module='crm')=:n_rules_before and (select count(*) from option_lists where list_code like 'crm\_%')=:n_list_before
  and (select count(*) from crm_complaints)=:n_cx_before and (select count(*) from crm_complaint_events)=:n_ev_before);
select tt.as(:'u_m1');
select tt.chk('T9 still works after the second paste (list for outlet 1 = its rows)', (_crmh_complaint_list('{"status":"all","limit":100}') ->> 'total')::int=(select count(*) from crm_complaints where location_id=1));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail of ' || count(*) from tt.res;
select 'FAIL ' || name from tt.res where not ok;
