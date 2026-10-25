-- FRESH DB ONLY. Phase 329 tests (CRM-H part 2: ratings, follow-up calls, rating to complaint, repeat list, report by outlet/item/category/severity/month).
--   Build: phases 8 .. 98, then phase328, phase329.   Run:
--   psql -h /tmp -p 5576 -U postgres -d <db> -qAt -f supabase/phase329_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o  '00000000-0000-0000-0000-000000032901'
\set u_m1 '00000000-0000-0000-0000-000000032902'
\set u_c1 '00000000-0000-0000-0000-000000032903'
\set u_v1 '00000000-0000-0000-0000-000000032904'
\set u_m2 '00000000-0000-0000-0000-000000032905'
\set u_x  '00000000-0000-0000-0000-000000032906'
\set u_b  '00000000-0000-0000-0000-000000032907'
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
 (:'u_o','test_owner329@s.app','{"full_name":"test_owner329"}'), (:'u_m1','test_mgr1_329@s.app','{"full_name":"test_mgr1_329"}'), (:'u_c1','test_cash1_329@s.app','{"full_name":"test_cash1_329"}'),
 (:'u_v1','test_view1_329@s.app','{"full_name":"test_view1_329"}'), (:'u_m2','test_mgr2_329@s.app','{"full_name":"test_mgr2_329"}'), (:'u_x','test_nobody329@s.app','{"full_name":"test_nobody329"}'),
 (:'u_b','test_bot329@s.app','{"full_name":"test_bot329"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m1', :'u_c1', :'u_v1', :'u_m2', :'u_x');
insert into user_roles values (:'u_o','owner'),(:'u_m1','showroom_manager'),(:'u_c1','salesperson'),(:'u_v1','purchasing'),(:'u_m2','showroom_manager'),(:'u_x','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m1',1),(:'u_c1',1),(:'u_v1',1),(:'u_m2',2),(:'u_x',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_m1','crm_complaint_manage',null),(:'u_v1','crm_feedback_view',null),(:'u_m2','crm_complaint_manage',null) on conflict do nothing;
insert into ops_accounts (user_id, purpose) values (:'u_b','notify') on conflict do nothing;

insert into customers (mobile, name, created_by) values ('01800032901','test_cust_a',:'u_o'), ('01800032902','test_cust_b',:'u_o');
insert into items (code, name_bn, name_en, unit, sell_price) values ('TESTH-A','test_item_a','test_item_a','pc',100), ('TESTH-B','test_item_b','test_item_b','pc',50);
select id as ca from customers where mobile='01800032901' \gset
select id as cb from customers where mobile='01800032902' \gset
select id as ia from items where code='TESTH-A' \gset
select id as ib from items where code='TESTH-B' \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id) values
 (1, 329011, current_date, now() - interval '1 day', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'done', :'u_o', :'ca'),
 (1, 329012, current_date, now() - interval '1 day', format('[{"item_id":"%s","qty":2,"price":50,"amount":100}]', :'ib')::jsonb, 100, 0, 100, 'cash', 'done', :'u_o', :'cb'),
 (2, 329013, current_date, now() - interval '1 day', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'done', :'u_o', :'ca');
select id as s1 from sales where receipt=329011 and location_id=1 \gset
select id as s2 from sales where receipt=329012 and location_id=1 \gset
select id as s3 from sales where receipt=329013 and location_id=2 \gset
insert into sale_returns (sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, refund_mode, reason_code, status, created_by) values
 (:'s1', 1, :'ca', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'quality', 'done', :'u_o'),
 (:'s2', 1, :'cb', format('[{"item_id":"%s","qty":1,"price":50,"amount":50}]', :'ib')::jsonb, 50, 50, 0, null, 'quality', 'done', :'u_o'),
 (:'s2', 1, :'cb', format('[{"item_id":"%s","qty":1,"price":50,"amount":50}]', :'ib')::jsonb, 50, 50, 0, null, 'quality', 'void', :'u_o'),
 (:'s3', 2, :'ca', format('[{"item_id":"%s","qty":1,"price":100,"amount":100}]', :'ia')::jsonb, 100, 0, 100, 'cash', 'quality', 'done', :'u_o');
select id as r1 from sale_returns where sale_id=:'s1' \gset
select id as r2 from sale_returns where sale_id=:'s2' and status='done' \gset
select id as r2v from sale_returns where sale_id=:'s2' and status='void' \gset
select id as r3 from sale_returns where sale_id=:'s3' \gset

select count(*) as je0 from journal_entries \gset
select count(*) as pay0 from sale_payments \gset
select coalesce(sum(debit),0) as jd0, coalesce(sum(credit),0) as jc0 from journal_lines \gset
select count(*) as ret0 from sale_returns \gset

-- online orders for the order-linked ratings: o1 (carries sale s2), o2 cancelled, o3 plain (no sale), all outlet 1
insert into online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode, status, sale_id, created_by) values
 (329001, 1, 'phone', 'test_cust_b', '01800032902', format('[{"item_id":"%s","qty":1,"price":50}]', :'ib')::jsonb, 50, 'pickup', 'delivered', :'s2', :'u_o'),
 (329002, 1, 'phone', 'test_cust_b', '01800032902', format('[{"item_id":"%s","qty":1,"price":50}]', :'ib')::jsonb, 50, 'pickup', 'cancelled', null, :'u_o'),
 (329003, 1, 'phone', 'test_cust_a', '01800032901', format('[{"item_id":"%s","qty":1,"price":100}]', :'ia')::jsonb, 100, 'pickup', 'confirmed', null, :'u_o');
select id as o1 from online_orders where order_no=329001 \gset
select id as o2 from online_orders where order_no=329002 \gset
select id as o3 from online_orders where order_no=329003 \gset

\echo == T0 shape and defaults
select tt.chk('T0 phase329 objects present', to_regclass('public.crm_feedback') is not null and to_regprocedure('public._crmh_report(jsonb)') is not null);
select tt.chk('T0 three feedback rules, English only, safe defaults (OFF, blank, blank)',
  (select count(*) from rules where key in ('crm_feedback_on','crm_feedback_low_max','crm_feedback_window_days'))=3 and not rule_on('crm_feedback_on') and rule_num('crm_feedback_low_max') is null and rule_num('crm_feedback_window_days') is null
  and not exists (select 1 from rules where key like 'crm\_feedback%' and (label_en is null or label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 table closed to browsers, RLS on, no-delete trigger, one rating per sale and per order (unique indexes)',
  (select relrowsecurity from pg_class where relname='crm_feedback') and not has_table_privilege('authenticated','public.crm_feedback','select') and not has_table_privilege('anon','public.crm_feedback','insert')
  and (select count(*) from pg_indexes where tablename='crm_feedback' and indexname in ('crm_feedback_one_per_sale','crm_feedback_one_per_order'))=2
  and exists (select 1 from pg_trigger where tgrelid='public.crm_feedback'::regclass and tgname='crm_feedback_nodel'));
select tt.chk('T0 API open to signed-in users only',
  has_function_privilege('authenticated','public._crmh_feedback_add(uuid,jsonb)','execute') and not has_function_privilege('anon','public._crmh_feedback_add(uuid,jsonb)','execute')
  and has_function_privilege('authenticated','public._crmh_report(jsonb)','execute') and not has_function_privilege('anon','public._crmh_report(jsonb)','execute')
  and not has_function_privilege('authenticated','public._crmh_feedback_guard()','execute'));

\echo == T1 switch OFF
select tt.as(:'u_c1');
select tt.err('T1 OFF: a rating is refused', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":5}'::jsonb)$$, :'s1'), 'feedback_off');
select tt.as(:'u_o');
select tt.chk('T1 OFF: list and settings answer; nothing stored', (_crmh_feedback_list('{}') ->> 'on')='false' and (_crmh_feedback_settings() ->> 'on')='false' and (select count(*) from crm_feedback)=0);
select set_rule('crm_feedback_on','true') is null as a1 \gset
select set_rule('crm_complaints_on','true') is null as a2 \gset

\echo == T2 capture: one rating per sale or order
select tt.as(:'u_c1');
select _crmh_feedback_add('b0000000-0000-0000-0000-000000032901', format('{"sale_id":"%s","rating":5,"comment":"test lovely","channel":"counter"}', :'s1')::jsonb) ->> 'id' as f1 \gset
select tt.chk('T2 cashier rates a sale: outlet and customer come from the sale; no follow-up while the threshold is blank',
  (select location_id=1 and customer_id=:'ca'::uuid and rating=5 and follow_up='none' and sale_id=:'s1'::uuid and comment='test lovely' from crm_feedback where id=:'f1'::uuid)
  and (select count(*) from audit_log where action='crmh_rating_new' and record_id=:'f1')=1);
select tt.chk('T2 same client id = dup, nothing added', (_crmh_feedback_add('b0000000-0000-0000-0000-000000032901', format('{"sale_id":"%s","rating":5}', :'s1')::jsonb) ->> 'dup')='true' and (select count(*) from crm_feedback)=1);
select tt.err('T2 a second rating for the same sale', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":3}'::jsonb)$$, :'s1'), 'already_rated');
select tt.err('T2 rating 0', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":0}'::jsonb)$$, :'s2'), 'bad_rating');
select tt.err('T2 rating 6', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":6}'::jsonb)$$, :'s2'), 'bad_rating');
select tt.err('T2 rating as text', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":"good"}'::jsonb)$$, :'s2'), 'bad_rating');
select tt.err('T2 rating 2.5', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":2.5}'::jsonb)$$, :'s2'), 'bad_rating');
select tt.err('T2 no sale and no order', $$select _crmh_feedback_add(null, '{"rating":4}'::jsonb)$$, 'sale_or_order_required');
select tt.err('T2 bad channel', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":4,"channel":"carrier pigeon"}'::jsonb)$$, :'s2'), 'bad_channel');
select tt.err('T2 a cashier of outlet 1 cannot rate an outlet 2 sale', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":4}'::jsonb)$$, :'s3'), 'not allowed');
select tt.err('T2 order cancelled', format($$select _crmh_feedback_add(null, '{"order_id":"%s","rating":4}'::jsonb)$$, :'o2'), 'order_cancelled');
select tt.err('T2 order and sale that do not belong together', format($$select _crmh_feedback_add(null, '{"order_id":"%s","sale_id":"%s","rating":4}'::jsonb)$$, :'o1', :'s1'), 'order_sale_mismatch');
select tt.as(:'u_x');
select tt.err('T2 a user with no right cannot rate', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":4}'::jsonb)$$, :'s2'), 'not allowed');
select tt.as(:'u_v1');
select tt.err('T2 a viewer cannot rate', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":4}'::jsonb)$$, :'s2'), 'not allowed');
select tt.as('');
select tt.err('T2 no login', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":4}'::jsonb)$$, :'s2'), 'not allowed');
-- a voided sale
select tt.as(:'u_o');
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values (1, 329009, current_date, now(), '[]', 10, 0, 10, 'cash', 'void', :'u_o');
select id as sv from sales where receipt=329009 \gset
select tt.err('T2 a voided sale cannot be rated', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":4}'::jsonb)$$, :'sv'), 'sale_void');
-- rating through an order that carries a sale: the sale is filled in, so the sale cannot be rated again
select tt.as(:'u_c1');
select _crmh_feedback_add(null, format('{"order_id":"%s","rating":4,"channel":"phone"}', :'o1')::jsonb) ->> 'id' as f2 \gset
select tt.chk('T2 rating by order: the order carries sale s2, which is filled in', (select sale_id=:'s2'::uuid and order_id=:'o1'::uuid from crm_feedback where id=:'f2'::uuid));
select tt.err('T2 so the same sale cannot be rated again directly', format($$select _crmh_feedback_add(null, '{"sale_id":"%s","rating":1}'::jsonb)$$, :'s2'), 'already_rated');
select _crmh_feedback_add(null, format('{"order_id":"%s","rating":2}', :'o3')::jsonb) ->> 'id' as f3 \gset
select tt.chk('T2 rating for an order with no sale', (select sale_id is null and order_id=:'o3'::uuid and rating=2 from crm_feedback where id=:'f3'::uuid));
select tt.err('T2 the same order twice', format($$select _crmh_feedback_add(null, '{"order_id":"%s","rating":3}'::jsonb)$$, :'o3'), 'already_rated');

\echo == T3 the low-rating follow-up call (the threshold is a setting)
select tt.as(:'u_o');
select tt.chk('T3 threshold blank: nothing needs a call so far', (select count(*) from crm_feedback where follow_up <> 'none')=0);
select set_rule('crm_feedback_low_max','2') is null as b1 \gset
select _crmh_feedback_add(null, format('{"sale_id":"%s","rating":1,"comment":"test cold and stale"}', :'s3')::jsonb) ->> 'id' as f4 \gset
select tt.chk('T3 threshold 2: a 1 star rating needs a call', (select follow_up from crm_feedback where id=:'f4'::uuid)='needed');
select tt.as(:'u_c1');
select tt.err('T3 a cashier cannot record the call', format($$select _crmh_feedback_followup('%s','test called')$$, :'f4'), 'not allowed');
select tt.as(:'u_m1');
select tt.err('T3 a manager of outlet 1 cannot record a call for outlet 2', format($$select _crmh_feedback_followup('%s','test called him')$$, :'f4'), 'not allowed');
select tt.err('T3 a rating that needed no call has no call to record', format($$select _crmh_feedback_followup('%s','test called')$$, :'f1'), 'no_follow_up_needed');
select tt.as(:'u_m2');
select tt.err('T3 the call needs a note', format($$select _crmh_feedback_followup('%s','')$$, :'f4'), 'note_required');
select _crmh_feedback_followup(:'f4'::uuid, 'test called the customer and apologised') ->> 'follow_up' as rv \gset
select tt.chk('T3 the manager of outlet 2 records the call: done, with who and when', :'rv'='done' and (select follow_up_by=:'u_m2'::uuid and follow_up_at is not null and follow_up_note like 'test called%' from crm_feedback where id=:'f4'::uuid));
select tt.chk('T3 repeating it is a dup', (_crmh_feedback_followup(:'f4'::uuid, 'test again') ->> 'dup')='true');
select tt.err('T3 rating, comment and links cannot be edited (database guard)', format($$update crm_feedback set rating=5 where id='%s'$$, :'f4'), 'feedback_immutable');
select tt.err('T3 a finished call cannot be undone (database guard)', format($$update crm_feedback set follow_up='needed' where id='%s'$$, :'f4'), 'illegal_status_change');
select tt.err('T3 nothing is deleted', format($$delete from crm_feedback where id='%s'$$, :'f4'), 'nothing is deleted');

\echo == T4 turn a low rating into a complaint (a complaint only, never a refund)
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id) values
 (1, 329004, current_date, now(), format('[{"item_id":"%s","qty":1,"price":50,"amount":50}]', :'ib')::jsonb, 50, 0, 50, 'cash', 'done', :'u_o', :'cb');
select id as s4 from sales where receipt=329004 \gset
select tt.as(:'u_m1');
select _crmh_feedback_add(null, format('{"sale_id":"%s","rating":2,"comment":"test wrong sweets in the box"}', :'s4')::jsonb) ->> 'id' as f5 \gset
select tt.as(:'u_c1');
select tt.err('T4 a cashier cannot convert', format($$select _crmh_feedback_to_complaint('%s','{"category":"wrong"}'::jsonb)$$, :'f5'), 'not allowed');
select tt.as(:'u_m1');
select tt.err('T4 the category must be on the list', format($$select _crmh_feedback_to_complaint('%s','{"category":"nope"}'::jsonb)$$, :'f5'), 'bad_category');
select _crmh_feedback_to_complaint(:'f5'::uuid, format('{"category":"wrong","severity":"high","item_id":"%s"}', :'ib')::jsonb) ->> 'complaint_id' as cv \gset
select tt.chk('T4 a complaint now exists: same sale and customer, description from the comment, severity high; the rating shows it and its call is done',
  (select sale_id=:'s4'::uuid and customer_id=:'cb'::uuid and description='test wrong sweets in the box' and severity='high' and location_id=1 and item_id=:'ib'::uuid from crm_complaints where id=:'cv'::uuid)
  and (select complaint_id=:'cv'::uuid and follow_up='done' from crm_feedback where id=:'f5'::uuid));
select tt.chk('T4 pressing it twice returns the same complaint', (_crmh_feedback_to_complaint(:'f5'::uuid, '{"category":"wrong"}'::jsonb) ->> 'complaint_id')=:'cv' and (select count(*) from crm_complaints)=1);
select tt.err('T4 the complaint link on a rating cannot be moved (database guard)', format($$update crm_feedback set complaint_id=null where id='%s'$$, :'f5'), 'feedback_immutable');

\echo == T5 the rating list: outlet and role visibility
select tt.as(:'u_o');
select tt.chk('T5 owner: 5 ratings, average (5+4+2+1+2)/5 = 2.8, nothing needs a call (both low ones were handled)',
  (_crmh_feedback_list('{}') ->> 'total')='5' and (_crmh_feedback_list('{}') ->> 'average')::numeric=2.80 and (_crmh_feedback_list('{}') ->> 'needs_call')='0');
select tt.as(:'u_m1');
select tt.chk('T5 manager of outlet 1: 4 ratings; outlet 2 filter gives none', (_crmh_feedback_list('{}') ->> 'total')='4' and (_crmh_feedback_list('{"location_id":2}') ->> 'total')='0');
select tt.chk('T5 filters: up to 2 stars = 2 ratings at outlet 1; follow_up done = 1', (_crmh_feedback_list('{"rating_max":2}') ->> 'total')='2' and (_crmh_feedback_list('{"follow_up":"done"}') ->> 'total')='1');
select tt.as(:'u_m2');
select tt.chk('T5 manager of outlet 2 sees one rating', (_crmh_feedback_list('{}') ->> 'total')='1' and (_crmh_feedback_list('{}') -> 'rows' -> 0 ->> 'receipt')='329013');
select tt.as(:'u_v1');
select tt.chk('T5 viewer (grant, outlet 1): 4 ratings', (_crmh_feedback_list('{}') ->> 'total')='4');
select tt.as(:'u_c1');
select tt.chk('T5 cashier sees only what the cashier recorded (f1, f2, f3 = 3)', (_crmh_feedback_list('{}') ->> 'total')='3');
select tt.as(:'u_x');
select tt.chk('T5 a user with no right sees none', (_crmh_feedback_list('{}') ->> 'total')='0');
select tt.err('T5 a bad follow_up filter', $$select _crmh_feedback_list('{"follow_up":"zzz"}')$$, 'bad_status');
select tt.as('');
select tt.err('T5 no login', $$select _crmh_feedback_list('{}')$$, 'not allowed');

\echo == T6 complaints for the report and the repeat list
select tt.as(:'u_o');
select set_rule('crm_complaint_sla_hours_medium','48') is null as c0 \gset
select set_rule('crm_complaint_sla_hours_high','8') is null as c00 \gset
select tt.err('T6 repeat list: the check is off by default', $$select _crmh_repeat_list('{}')$$, 'days_required');
select set_rule('crm_repeat_days','30') is null as c01 \gset
select tt.as(:'u_m1');
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"taste","description":"test one"}', :'s1', :'ia')::jsonb) ->> 'id' as c1 \gset
select _crmh_complaint_move(:'c1'::uuid,'resolved','test explained','explained') ->> 'status' as rv \gset
select _crmh_complaint_link_return(:'c1'::uuid, :'r1'::uuid) ->> 'id' as rv2 \gset
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"sick","description":"test two"}', :'s1', :'ia')::jsonb) ->> 'id' as c2 \gset
select format($$update crm_complaints set due_at = now() - interval '1 hour' where id = '%s'$$, :'c2') as ag_sql \gset
:ag_sql;
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"late","severity":"low","description":"test three"}', :'s2', :'ib')::jsonb) ->> 'id' as c3 \gset
select _crmh_complaint_move(:'c3'::uuid,'closed_no_resolution','test phone off',null,'no_contact') ->> 'status' as rv3 \gset
select tt.as(:'u_o');
select _crmh_complaint_save(null, format('{"sale_id":"%s","item_id":"%s","category":"taste","description":"test four"}', :'s3', :'ia')::jsonb) ->> 'id' as c4 \gset
select tt.chk('T6 repeat flags: c2 (second A for the same customer) and c4 (third, other outlet) and c3 (second B for customer b) are flagged; c1 and the converted one are not',
  (select repeat_flag from crm_complaints where id=:'c2'::uuid) and (select repeat_flag from crm_complaints where id=:'c4'::uuid) and (select repeat_flag from crm_complaints where id=:'c3'::uuid)
  and not (select repeat_flag from crm_complaints where id=:'c1'::uuid) and not (select repeat_flag from crm_complaints where id=:'cv'::uuid));
select tt.chk('T6 repeat list (default scope customer_item, min 2): customer a + item A = 3 complaints at 2 outlets, customer b + item B = 2',
  (select count(*) from jsonb_array_elements(_crmh_repeat_list('{}') -> 'rows'))=2
  and (select (r->>'complaints')::int=3 and (r->>'outlets')::int=2 and (r->>'customer_name')='test_cust_a' from jsonb_array_elements(_crmh_repeat_list('{}') -> 'rows') r where r->>'item_name'='test_item_a')
  and (select (r->>'complaints')::int=2 from jsonb_array_elements(_crmh_repeat_list('{}') -> 'rows') r where r->>'item_name'='test_item_b'));
select tt.chk('T6 repeat list min 3: only customer a + A', (select count(*) from jsonb_array_elements(_crmh_repeat_list('{"min":3}') -> 'rows'))=1);
select tt.chk('T6 repeat list scope customer: still the two customers', (select count(*) from jsonb_array_elements(_crmh_repeat_list('{"scope":"customer"}') -> 'rows'))=2);
select tt.err('T6 repeat list: min below 2', $$select _crmh_repeat_list('{"min":1}')$$, 'bad_min');
select tt.err('T6 repeat list: bad scope', $$select _crmh_repeat_list('{"scope":"x"}')$$, 'bad_scope');
select tt.as(:'u_m2');
select tt.chk('T6 manager of outlet 2 sees only outlet 2: no repeat row (one complaint there)', (select count(*) from jsonb_array_elements(_crmh_repeat_list('{}') -> 'rows'))=0);
select tt.as(:'u_x');
select tt.chk('T6 a user with no right sees no repeat row', (select count(*) from jsonb_array_elements(_crmh_repeat_list('{}') -> 'rows'))=0);

\echo == T7 the report
select tt.as(:'u_o');
select _crmh_report('{}') as rep \gset
select tt.chk('T7 default report by outlet: 5 complaints, 5 ratings, average 2.8', (:'rep'::jsonb -> 'totals' ->> 'complaints')='5' and (:'rep'::jsonb -> 'totals' ->> 'ratings')='5' and (:'rep'::jsonb -> 'totals' ->> 'average_rating')::numeric=2.80 and (:'rep'::jsonb ->> 'by')='outlet');
select tt.chk('T7 outlet 1 complaints: 4 total, 2 open (cv, c2), 1 resolved (c1), 1 closed with no result (c3), 1 overdue now, 1 food safety, 1 SLA met, 2 repeats, refund 100',
  (select (r->>'total')::int=4 and (r->>'open')::int=2 and (r->>'resolved')::int=1 and (r->>'closed_no_result')::int=1 and (r->>'overdue_now')::int=1 and (r->>'food_safety')::int=1
      and (r->>'sla_met')::int=1 and (r->>'sla_missed')::int=0 and (r->>'repeat')::int=2 and (r->>'refund_total')::numeric=100 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='1'));
select tt.chk('T7 outlet 2 complaints: 1 open, 1 repeat, no refund', (select (r->>'total')::int=1 and (r->>'open')::int=1 and (r->>'repeat')::int=1 and (r->>'refund_total')::numeric=0 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='2'));
select tt.chk('T7 outlet 1 ratings: 4 ratings, average (5+4+2+2)/4 = 3.25, stars 2:2 4:1 5:1, no call open',
  (select (r->>'n')::int=4 and (r->>'average')::numeric=3.25 and (r->'stars'->>'2')::int=2 and (r->'stars'->>'4')::int=1 and (r->'stars'->>'5')::int=1 and (r->'stars'->>'1')::int=0 and (r->>'needs_call')::int=0
     from jsonb_array_elements(:'rep'::jsonb -> 'ratings') r where (r->>'key')='1'));
select tt.chk('T7 outlet 2 ratings: 1 rating of 1 star', (select (r->>'n')::int=1 and (r->>'average')::numeric=1.00 from jsonb_array_elements(:'rep'::jsonb -> 'ratings') r where (r->>'key')='2'));
select tt.chk('T7 labels are the outlet names', (select r->>'label' from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='1') = (select coalesce(name_en, name_bn) from locations where id=1));
select _crmh_report('{"by":"item"}') as rep \gset
select tt.chk('T7 by item: A = 3 complaints, B = 2 complaints; ratings counted for every item on the sale: A 3 ratings average (5+2+1)/3 = 2.67, B 2 ratings average 3.00; a note says so',
  (select (r->>'total')::int=3 and r->>'label'='test_item_a' from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')=:'ia')
  and (select (r->>'total')::int=2 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')=:'ib')
  and (select (r->>'n')::int=3 and (r->>'average')::numeric=2.67 from jsonb_array_elements(:'rep'::jsonb -> 'ratings') r where (r->>'key')=:'ia')
  and (select (r->>'n')::int=2 and (r->>'average')::numeric=3.00 from jsonb_array_elements(:'rep'::jsonb -> 'ratings') r where (r->>'key')=:'ib')
  and (:'rep'::jsonb ->> 'note') like '%every item%');
select _crmh_report('{"by":"category"}') as rep \gset
select tt.chk('T7 by category: taste 2 (c1, c4), sick 1, late 1, wrong 1 (the converted one); ratings are empty here',
  (select (r->>'total')::int=2 and r->>'label'='Taste' from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='taste')
  and (select (r->>'total')::int=1 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='sick')
  and (select (r->>'total')::int=1 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='wrong')
  and (select (r->>'total')::int=1 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='late') and jsonb_array_length(:'rep'::jsonb -> 'ratings')=0);
select _crmh_report('{"by":"severity"}') as rep \gset
select tt.chk('T7 by severity: high 1 (cv), medium 3, low 1', (select (r->>'total')::int=1 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='high')
  and (select (r->>'total')::int=3 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='medium') and (select (r->>'total')::int=1 from jsonb_array_elements(:'rep'::jsonb -> 'complaints') r where (r->>'key')='low'));
select _crmh_report('{"by":"month"}') as rep \gset
select tt.chk('T7 by month: one month holds all 5 complaints and 5 ratings', jsonb_array_length(:'rep'::jsonb -> 'complaints')=1 and (:'rep'::jsonb -> 'complaints' -> 0 ->> 'total')='5' and (:'rep'::jsonb -> 'ratings' -> 0 ->> 'n')='5'
  and (:'rep'::jsonb -> 'complaints' -> 0 ->> 'key')=to_char((now() at time zone 'Asia/Dhaka')::date,'YYYY-MM'));
select tt.chk('T7 a period with nothing in it is empty, not an error', jsonb_array_length(_crmh_report(format('{"from":"%s","to":"%s"}', current_date + 5, current_date + 6)::jsonb) -> 'complaints')=0);
select tt.chk('T7 outlet filter', jsonb_array_length(_crmh_report('{"location_id":2}'::jsonb) -> 'complaints')=1);
select tt.err('T7 unknown grouping', $$select _crmh_report('{"by":"colour"}')$$, 'bad_group');
select tt.err('T7 from after to', $$select _crmh_report('{"from":"2026-02-02","to":"2026-02-01"}')$$, 'bad_range');
select tt.err('T7 a range over a year', $$select _crmh_report('{"from":"2024-01-01","to":"2026-01-01"}')$$, 'range_too_long');
select tt.as(:'u_m2');
select tt.chk('T7 manager of outlet 2: only outlet 2 (1 complaint, 1 rating), and nothing else leaks into the totals', (_crmh_report('{}') -> 'totals' ->> 'complaints')='1' and (_crmh_report('{}') -> 'totals' ->> 'ratings')='1' and jsonb_array_length(_crmh_report('{}') -> 'complaints')=1);
select tt.as(:'u_v1');
select tt.chk('T7 viewer (grant, outlet 1): 4 complaints, 4 ratings', (_crmh_report('{}') -> 'totals' ->> 'complaints')='4' and (_crmh_report('{}') -> 'totals' ->> 'ratings')='4');
select tt.as(:'u_c1');
select tt.err('T7 a cashier has no report', $$select _crmh_report('{}')$$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T7 a user with no right has no report', $$select _crmh_report('{}')$$, 'not allowed');
select tt.as('');
select tt.err('T7 no login, no report', $$select _crmh_report('{}')$$, 'not allowed');

\echo == T8 accounting untouched, paste twice
select tt.chk('T8 ACCOUNTING UNTOUCHED: journal entries, journal debit and credit totals, payments and sale returns are identical after every rating, complaint and report call',
  (select count(*) from journal_entries)=:je0 and (select coalesce(sum(debit),0) from journal_lines)=:jd0 and (select coalesce(sum(credit),0) from journal_lines)=:jc0
  and (select count(*) from sale_payments)=:pay0 and (select count(*) from sale_returns)=:ret0 and (select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z)=0);
select count(*) as n_fb from crm_feedback \gset
select count(*) as n_rules from rules where module='crm' \gset
select count(*) as n_cx from crm_complaints \gset
\ir phase329.sql
\ir phase328.sql
\ir phase329.sql
select tt.chk('T8 phases 328 and 329 pasted again: no error, same rules and data', (select count(*) from crm_feedback)=:n_fb and (select count(*) from rules where module='crm')=:n_rules and (select count(*) from crm_complaints)=:n_cx);
select tt.as(:'u_o');
select tt.chk('T8 still works after the re-paste', (_crmh_feedback_list('{}') ->> 'total')='5' and (_crmh_report('{}') -> 'totals' ->> 'complaints')='5');

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail of ' || count(*) from tt.res;
select 'FAIL ' || name from tt.res where not ok;
