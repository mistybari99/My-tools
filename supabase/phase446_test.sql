-- Phase 446 tests (RPT-C2 R4 part 2: actual delivery cost). Neutral test_* data only.  bash tests/sql/c2_run.sh phase446
\ir ../tests/sql/c2_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions open to browsers, anon none, table read-only',
  has_function_privilege('authenticated','public.c2_order_cost_add(uuid,text,numeric,text,text,uuid)','execute') and has_function_privilege('authenticated','public.c2_order_cost_void(bigint,text)','execute')
  and not has_function_privilege('anon','public.c2_order_cost_add(uuid,text,numeric,text,text,uuid)','execute')
  and not has_table_privilege('authenticated','public.order_delivery_costs','insert') and not has_table_privilege('authenticated','public.order_delivery_costs','update')
  and (select relrowsecurity from pg_class where relname='order_delivery_costs'));
select tt.chk('T0 the kinds list: 4 kinds, Other present, list rule exists', (select count(*) from option_lists where list_code='order_delivery_cost_kinds')=4
  and exists (select 1 from option_lists where list_code='order_delivery_cost_kinds' and value_code='other') and exists (select 1 from list_defs where list_code='order_delivery_cost_kinds'));

\echo == T1 add a cost
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_1', '01700000011', 'test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'home', 'test_rider', tt.today()+1, 30, 0, 0, null, null, null) ->> 'id' as o1 \gset
select tt.err('T1 a new (unconfirmed) order takes no cost', format($$select c2_order_cost_add('%s','fuel',20)$$, :'o1'), 'bad_status');
select online_order_status(:'o1'::uuid,'confirmed') is not null as s1 \gset
select online_order_status(:'o1'::uuid,'packed') is not null as s2 \gset
select gen_random_uuid()::text as cl \gset
select c2_order_cost_add(:'o1'::uuid, 'fuel', 20, 'test_rider', null, :'cl'::uuid) ->> 'id' as c1 \gset
select tt.chk('T1 cost saved: amount 20, kind fuel, Dhaka date today', (select amount from order_delivery_costs where id=:'c1'::bigint)=20 and (select cost_date from order_delivery_costs where id=:'c1'::bigint)=tt.today());
select tt.chk('T1 same client id = same row (idempotent)', (c2_order_cost_add(:'o1'::uuid, 'fuel', 20, 'test_rider', null, :'cl'::uuid) ->> 'dup')::boolean and (select count(*) from order_delivery_costs)=1);
select tt.err('T1 amount must be above 0', format($$select c2_order_cost_add('%s','fuel',0)$$, :'o1'), 'bad_amount');
select tt.err('T1 kind must be on the list', format($$select c2_order_cost_add('%s','test_kind',5)$$, :'o1'), 'bad_kind');
select tt.err('T1 Other needs a note', format($$select c2_order_cost_add('%s','other',5)$$, :'o1'), 'note_required');
select c2_order_cost_add(:'o1'::uuid, 'other', 15.5, null, 'test_toll') is not null as c2 \gset
select tt.chk('T1 two active costs sum to 35.5', (select sum(amount) from order_delivery_costs where order_id=:'o1'::uuid and state='active')=35.5);
select tt.as(:'x');
select tt.err('T1 other place refused', format($$select c2_order_cost_add('%s','fuel',5)$$, :'o1'), 'not allowed for this location');
select tt.as(:'k');
select tt.err('T1 storekeeper refused', format($$select c2_order_cost_add('%s','fuel',5)$$, :'o1'), 'not allowed');

\echo == T2 cost after delivery and after cancel
select tt.as(:'p');
select (online_order_deliver(:'o1'::uuid, format('[{"mode":"cash","amount":230}]')::jsonb) ->> 'status') as dl \gset
select tt.chk('T2 delivered', :'dl'='delivered');
select c2_order_cost_add(:'o1'::uuid, 'rider_pay', 40, 'test_rider', 'paid after the trip') ->> 'id' as c3 \gset
select tt.chk('T2 a delivered order still takes a cost (the order row is closed, the cost table is not)', :'c3' is not null and (select status from online_orders where id=:'o1'::uuid)='delivered');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_2', '01700000012', null, format('[{"item_id":"%s","qty":1}]', :'ib')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) ->> 'id' as o2 \gset
select online_order_status(:'o2'::uuid,'confirmed') is not null as s3 \gset
select online_order_cancel(:'o2'::uuid, 'test_reason', 'none') is not null as s4 \gset
select tt.chk('T2 a cancelled order still takes a cost (a wasted trip)', c2_order_cost_add(:'o2'::uuid, 'fuel', 12) ->> 'id' is not null);

\echo == T3 void
select tt.err('T3 a void needs a reason', format($$select c2_order_cost_void(%s,'')$$, :'c1'), 'reason_required');
select tt.chk('T3 void works and the row stays', (c2_order_cost_void(:'c1'::bigint, 'test_wrong_entry') ->> 'state')='void' and (select count(*) from order_delivery_costs where id=:'c1'::bigint)=1);
select tt.chk('T3 void twice = no-op', (c2_order_cost_void(:'c1'::bigint, 'again') ->> 'noop')::boolean);
select tt.err('T3 a cost row cannot be edited directly', format($$update order_delivery_costs set amount=1 where id=%s$$, :'c1'), 'append_only');
select tt.err('T3 a cost row cannot be deleted', format($$delete from order_delivery_costs where id=%s$$, :'c1'), 'append_only');
select tt.chk('T3 the costs sum without the voided row: 15.5 + 40', (select sum(amount) from order_delivery_costs where order_id=:'o1'::uuid and state='active')=55.5);

\echo == T4 nothing is posted to the books
select tt.chk('T4 no cash move, no journal entry came from a delivery cost', (select count(*) from cash_moves)=0
  and not exists (select 1 from journal_entries where source_type ilike '%delivery_cost%'));

\echo == T5 reads
set role authenticated;
select tt.as(:'p'); select tt.chk('T5 place 1 salesperson reads 4 cost rows', (select count(*) from order_delivery_costs)=4);
select tt.as(:'x'); select tt.chk('T5 other place reads none', (select count(*) from order_delivery_costs)=0);
select tt.as(:'k'); select tt.chk('T5 storekeeper reads none', (select count(*) from order_delivery_costs)=0);
reset role;

\echo == T9 paste twice
select count(*) as n_before from order_delivery_costs \gset
select count(*) as l_before from option_lists where list_code='order_delivery_cost_kinds' \gset
\ir phase446.sql
select tt.chk('T9 pasted again: no new rows, no duplicate list values', (select count(*) from order_delivery_costs)=:n_before and (select count(*) from option_lists where list_code='order_delivery_cost_kinds')=:l_before);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
