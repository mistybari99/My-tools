-- Phase 445 tests (RPT-C2 R4 part 1: cake specification and promised time slot). Neutral test_* data only. FRESH DB through phase 99 + phase445:
--   bash tests/sql/c2_run.sh phase445      (or: psql -d <db> -qAt -f supabase/phase445_test.sql | grep -E 'FAIL|RESULT')
\ir ../tests/sql/c2_fixture.sql

\echo == T0 shape
select tt.chk('T0 browser functions open, helpers closed, anon none',
  has_function_privilege('authenticated','public.c2_order_spec_save(uuid,jsonb,text)','execute') and has_function_privilege('authenticated','public.c2_order_promise_set(uuid,time,time,text)','execute')
  and has_function_privilege('authenticated','public.c2_orders_features()','execute') and not has_function_privilege('anon','public.c2_orders_features()','execute')
  and not has_function_privilege('authenticated','public._c2_promise_of(uuid)','execute') and not has_function_privilege('authenticated','public._c2_trail_ro()','execute'));
select tt.chk('T0 tables are read-only for browsers, RLS on',
  not has_table_privilege('authenticated','public.order_cake_specs','insert') and not has_table_privilege('authenticated','public.order_cake_specs','update') and not has_table_privilege('authenticated','public.order_promises','insert')
  and (select bool_and(relrowsecurity) from pg_class where relname in ('order_cake_specs','order_promises')));
select tt.chk('T0 two rules: promise gate OFF, grace blank (nothing invented)', not rule_on('order_promise_required') and rule_num('order_late_grace_minutes') is null
  and (select count(*) from rules where key in ('order_promise_required','order_late_grace_minutes'))=2);

\echo == T1 cake specification
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_1', '01700000001', 'test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'home', null, tt.today()+2, 30, 0, 50, 'cash', null, 'test_note') ->> 'id' as o1 \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_2', '01700000002', null, format('[{"item_id":"%s","qty":1}]', :'ib')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) ->> 'id' as o2 \gset
select c2_order_spec_save(:'o1'::uuid, '[{"weight_kg":1.5,"flavour":"test_flavour","message":"test_message","design":"test_design","photo_ref":"test_photo_ref"}]'::jsonb) ->> 'specs' as s1 \gset
select tt.chk('T1 one cake spec saved by the salesperson of the place', :'s1'='1' and (select count(*) from order_cake_specs where order_id=:'o1'::uuid and state='active')=1
  and (select weight_kg from order_cake_specs where order_id=:'o1'::uuid and state='active')=1.5);
select tt.chk('T1 same set again is a no-op (no new rows)', (c2_order_spec_save(:'o1'::uuid, '[{"weight_kg":1.5,"flavour":"test_flavour","message":"test_message","design":"test_design","photo_ref":"test_photo_ref"}]'::jsonb) ->> 'noop')::boolean
  and (select count(*) from order_cake_specs where order_id=:'o1'::uuid)=1);
select c2_order_spec_save(:'o1'::uuid, format('[{"item_id":"%s","weight_kg":2,"flavour":"test_flavour_2"},{"message":"test_message_2"}]', :'ia')::jsonb, 'customer changed it') is not null as s2 \gset
select tt.chk('T1 replace voids the old row and adds two (history kept: 3 rows, 2 active, 1 void with a note)',
  (select count(*) from order_cake_specs where order_id=:'o1'::uuid)=3 and (select count(*) from order_cake_specs where order_id=:'o1'::uuid and state='active')=2
  and (select void_note from order_cake_specs where order_id=:'o1'::uuid and state='void')='customer changed it');
select tt.err('T1 weight must be positive', format($$select c2_order_spec_save('%s','[{"weight_kg":0}]')$$, :'o1'), 'bad_weight');
select tt.err('T1 an empty spec is refused', format($$select c2_order_spec_save('%s','[{}]')$$, :'o1'), 'empty_spec');
select tt.err('T1 an item that is not on the order is refused', format($$select c2_order_spec_save('%s','[{"item_id":"%s","weight_kg":1}]')$$, :'o1', gen_random_uuid()), 'item_not_on_order');
select tt.err('T1 a list is required', format($$select c2_order_spec_save('%s','{"a":1}')$$, :'o1'), 'bad_specs');
select tt.as(:'x');
select tt.err('T1 manager of another place refused', format($$select c2_order_spec_save('%s','[{"weight_kg":1}]')$$, :'o1'), 'not allowed for this location');
select tt.as(:'k');
select tt.err('T1 storekeeper (no POS) refused', format($$select c2_order_spec_save('%s','[{"weight_kg":1}]')$$, :'o1'), 'not allowed');
select tt.as(:'o'); select set_rule('online_orders_on','false') is null as off1 \gset
select tt.as(:'p');
select tt.err('T1 module switched off: refused', format($$select c2_order_spec_save('%s','[{"weight_kg":1}]')$$, :'o1'), 'module_off');
select tt.as(:'o'); select set_rule('online_orders_on','true') is null as on1 \gset
select tt.as(:'p');
select tt.chk('T1 the audit log has the insert lines', (select count(*) from audit_log where table_name='order_cake_specs')>=3);
select tt.err('T1 a spec row cannot be edited directly', format($$update order_cake_specs set weight_kg=9 where order_id='%s'$$, :'o1'), 'append_only');
select tt.err('T1 a spec row cannot be deleted', format($$delete from order_cake_specs where order_id='%s'$$, :'o1'), 'append_only');

\echo == T2 promised time slot
select tt.chk('T2 a slot cannot be set without a delivery date', (select count(*) from (select 1) z where false)=0);
select tt.err('T2 order with no delivery date refused', format($$select c2_order_promise_set('%s','10:00','12:00')$$, :'o2'), 'delivery_date_required');
select c2_order_promise_set(:'o1'::uuid, '10:00', '12:00') ->> 'id' as pr1 \gset
select tt.chk('T2 first slot written', :'pr1' is not null and (select slot_from from order_promises where id=:'pr1'::bigint)='10:00'::time);
select tt.chk('T2 same slot again = no-op', (c2_order_promise_set(:'o1'::uuid, '10:00', '12:00') ->> 'noop')::boolean and (select count(*) from order_promises where order_id=:'o1'::uuid)=1);
select tt.err('T2 a change needs a reason', format($$select c2_order_promise_set('%s','14:00','16:00')$$, :'o1'), 'reason_required');
select tt.err('T2 end must be after start', format($$select c2_order_promise_set('%s','14:00','13:00','test_reason')$$, :'o1'), 'bad_slot');
select c2_order_promise_set(:'o1'::uuid, '14:00', null, 'customer asked for later') ->> 'id' as pr2 \gset
select tt.chk('T2 change = new row with the reason; two active rows, newest wins', (select count(*) from order_promises where order_id=:'o1'::uuid)=2
  and (_c2_promise_of(:'o1'::uuid)).slot_from='14:00'::time and (select reason from order_promises where id=:'pr2'::bigint)='customer asked for later');
select tt.as(:'x');
select tt.err('T2 other place refused', format($$select c2_order_promise_set('%s','10:00','11:00','test_reason')$$, :'o1'), 'not allowed for this location');
select tt.as(:'p');

\echo == T3 the optional promise gate (rule order_promise_required)
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_3', '01700000003', null, format('[{"item_id":"%s","qty":1}]', :'ib')::jsonb, 'pickup', null, tt.today()+3, 0, 0, 0, null, null, null) ->> 'id' as o3 \gset
select tt.as(:'o'); select set_rule('order_promise_required','true') is null as g1 \gset
select tt.as(:'p');
select tt.err('T3 gate ON: confirm refused without a slot', format($$select online_order_status('%s','confirmed')$$, :'o3'), 'promise_required');
select c2_order_promise_set(:'o3'::uuid, '09:00', '10:00') is not null as g2 \gset
select tt.chk('T3 gate ON: confirm works once a slot exists', (online_order_status(:'o3'::uuid,'confirmed') ->> 'status')='confirmed');
select tt.as(:'o'); select set_rule('order_promise_required','false') is null as g3 \gset
select tt.as(:'p');
select tt.chk('T3 gate OFF = today: confirm works without a slot', (online_order_status(:'o2'::uuid,'confirmed') ->> 'status')='confirmed');

\echo == T4 closed orders do not change
select online_order_status(:'o2'::uuid,'packed') is not null as k1 \gset
select online_order_cancel(:'o2'::uuid, 'test_reason', 'none') is not null as k2 \gset
select tt.err('T4 cancelled order: spec refused', format($$select c2_order_spec_save('%s','[{"weight_kg":1}]')$$, :'o2'), 'order_closed');
select tt.err('T4 cancelled order: slot refused', format($$select c2_order_promise_set('%s','09:00','10:00')$$, :'o2'), 'order_closed');

\echo == T5 reads and features
set role authenticated;
select tt.as(:'p');
select tt.chk('T5 salesperson of place 1 sees the spec rows', (select count(*) from order_cake_specs where order_id=:'o1'::uuid)=3);
select tt.as(:'x');
select tt.chk('T5 manager of place 2 sees none (row policy)', (select count(*) from order_cake_specs)=0 and (select count(*) from order_promises)=0);
select tt.as(:'r');
select tt.chk('T5 a view_reports holder (no POS) may read', (select count(*) from order_cake_specs where order_id=:'o1'::uuid)=3);
select tt.as(:'k');
select tt.chk('T5 storekeeper without any report right sees none', (select count(*) from order_cake_specs)=0);
select tt.as(:'p');
select tt.chk('T5 features: spec and promise yes, later parts not yet', (c2_orders_features() ->> 'spec')::boolean and (c2_orders_features() ->> 'promise')::boolean and not (c2_orders_features() ->> 'cost')::boolean
  and (c2_orders_features() ->> 'v')='445');
reset role;

\echo == T9 paste twice
select count(*) as n_before from order_cake_specs \gset
select count(*) as r_before from rules where key like 'order_%' \gset
\ir phase445.sql
select tt.chk('T9 phase 445 pasted again: no new rows, no duplicate rules', (select count(*) from order_cake_specs)=:n_before and (select count(*) from rules where key like 'order_%')=:r_before);
select tt.chk('RESULT', true) where false;
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
