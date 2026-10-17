-- Phase 450 tests (RPT-C2 R4 part 6: delayed orders #159, on-time #158, fulfilment rate #163). Neutral test_* data only.  bash tests/sql/c2_run.sh phase450
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_orders_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions open to browsers, anon none',
  has_function_privilege('authenticated','public.c2_orders_delayed(int,timestamptz,date,date)','execute') and has_function_privilege('authenticated','public.c2_orders_ontime(date,date,int)','execute')
  and has_function_privilege('authenticated','public.c2_order_fulfilment(date,date,int)','execute') and not has_function_privilege('anon','public.c2_orders_ontime(date,date,int)','execute')
  and not has_function_privilege('authenticated','public._c2_grace()','execute'));

\echo == T1 delayed and undelivered (#159)
select tt.as(:'m');
select c2_orders_delayed() as dl \gset
select tt.chk('T1 two delayed: app order B (slot ended) and paper sheet 20-1/9001 (promised yesterday 11:00)', (:'dl'::jsonb #>> '{summary,delayed}')::int=2 and (:'dl'::jsonb #>> '{summary,delayed_app}')::int=1 and (:'dl'::jsonb #>> '{summary,delayed_paper_20_1}')::int=1);
select tt.chk('T1 B is judged by its slot (hours overdue known), the paper sheet by date and time', (select r ->> 'basis' from jsonb_array_elements(:'dl'::jsonb -> 'rows') r where r ->> 'order_id'=:'ob')='slot'
  and (select (r ->> 'overdue_hours')::numeric from jsonb_array_elements(:'dl'::jsonb -> 'rows') r where r ->> 'order_id'=:'ob')>24);
select tt.chk('T1 the open order with no delivery date (G) is counted as not judged, never as late', (:'dl'::jsonb #>> '{summary,open_without_promised_date}')::int=1 and (:'dl'::jsonb -> 'notes') ? 'open_without_date_not_judged'
  and not exists (select 1 from jsonb_array_elements(:'dl'::jsonb -> 'rows') r where r ->> 'order_id'=:'og'));
select tt.chk('T1 delivered and cancelled orders are not in the delayed list', not exists (select 1 from jsonb_array_elements(:'dl'::jsonb -> 'rows') r where r ->> 'order_id' in (:'oa', :'oe', :'of', :'oc', :'od')));
select tt.chk('T1 an "as of" two days back: B is not yet past its promise (date T-2 09:00-10:00 vs as-of T-3)', (c2_orders_delayed(null, now() - interval '3 days') #>> '{summary,delayed_app}')::int=0);
select tt.chk('T1 place filter: place 1 only = same 2', (c2_orders_delayed(1) #>> '{summary,delayed}')::int=2);
select tt.as(:'x');
select tt.chk('T1 manager of place 2 sees none', (c2_orders_delayed() #>> '{summary,delayed}')::int=0);
select tt.err('T1 place 2 manager cannot ask for place 1', $$select c2_orders_delayed(1)$$, 'not allowed for this location');
select tt.as(:'k');
select tt.err('T1 storekeeper refused', $$select c2_orders_delayed()$$, 'not allowed');

\echo == T2 on-time performance (#158)
select tt.as(:'m');
select c2_orders_ontime(tt.today()-3, tt.today()+1) as ot \gset
select tt.chk('T2 3 delivered orders judged: A and E on time, F late; 66.7 percent; all three judged by slot', (:'ot'::jsonb #>> '{summary,judged}')::int=3 and (:'ot'::jsonb #>> '{summary,on_time}')::int=2 and (:'ot'::jsonb #>> '{summary,late}')::int=1
  and (:'ot'::jsonb #>> '{summary,on_time_pct}')::numeric=66.7 and (:'ot'::jsonb #>> '{summary,judged_by_slot}')::int=3);
select tt.chk('T2 F is late by 29 hours = 1740 minutes (promised yesterday 10:00, delivered today 15:00)', (select (r ->> 'late_minutes')::int from jsonb_array_elements(:'ot'::jsonb -> 'rows') r where r ->> 'order_id'=:'of')=1740
  and (:'ot'::jsonb #>> '{summary,avg_late_minutes}')::int=1740);
select tt.chk('T2 still-open overdue count is shown beside the percentage; paper has no delivery time (note)', (:'ot'::jsonb ->> 'still_open_overdue')::int=1 and (:'ot'::jsonb -> 'notes') ? 'paper_delivery_time_not_captured');
select tt.chk('T2 breakdown by delivery mode has home (A, F) and pickup (E)', (:'ot'::jsonb #>> '{breakdown,"by_mode:home",judged}')::int=2 and (:'ot'::jsonb #>> '{breakdown,"by_mode:pickup",judged}')::int=1);

\echo == T3 grace and the boundary
select tt.as(:'o');
set session_replication_role = replica;
update online_orders set delivered_at = ((tt.today()-1)::text || ' 10:30:00+06')::timestamptz where id = :'of'::uuid;
set session_replication_role = origin;
select tt.chk('T3 grace blank: 30 minutes after the slot end = late', (c2_orders_ontime(tt.today()-3, tt.today()+1) #>> '{summary,late}')::int=1 and (c2_orders_ontime(tt.today()-3, tt.today()+1) #>> '{summary,grace_minutes}') is null);
select set_rule('order_late_grace_minutes','30'::jsonb) is null as g1 \gset
select tt.chk('T3 grace 30 minutes: exactly at the edge = on time; 100 percent', (c2_orders_ontime(tt.today()-3, tt.today()+1) #>> '{summary,late}')::int=0 and (c2_orders_ontime(tt.today()-3, tt.today()+1) #>> '{summary,on_time_pct}')::numeric=100);
select set_rule('order_late_grace_minutes', null) is null as g2 \gset

\echo == T4 an order with no promise date is not judged
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_h', '01700000108', null, format('[{"item_id":"%s","qty":1}]', :'ib')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) ->> 'id' as oh \gset
select online_order_status(:'oh'::uuid,'confirmed') is not null as h1 \gset
select online_order_status(:'oh'::uuid,'packed') is not null as h2 \gset
select c2_order_deliver(:'oh'::uuid, '[{"mode":"cash","amount":50}]'::jsonb) is not null as h3 \gset
select tt.as(:'m');
select c2_orders_ontime(tt.today()-3, tt.today()+1) as ot2 \gset
select tt.chk('T4 delivered without a promised date: counted as not judged, the percentage does not change', (:'ot2'::jsonb #>> '{summary,delivered_without_promised_date_not_judged}')::int=1 and (:'ot2'::jsonb #>> '{summary,judged}')::int=3);
select tt.chk('T4 a window with nothing judged gives a null percentage, not 0', (c2_orders_ontime(tt.today()-300, tt.today()-290) #>> '{summary,on_time_pct}') is null and (c2_orders_ontime(tt.today()-300, tt.today()-290) #>> '{summary,judged}')::int=0);

\echo == T5 fulfilment (#163)
select c2_order_fulfilment(tt.today()-3, tt.today()+1) as fu \gset
select tt.chk('T5 app: 8 orders, 4 delivered (A,E,F,H), 2 cancelled, 2 open; rate of closed 4/6 = 66.7, of all 4/8 = 50.0',
  (:'fu'::jsonb #>> '{summary,app,orders}')::int=8 and (:'fu'::jsonb #>> '{summary,app,delivered}')::int=4 and (:'fu'::jsonb #>> '{summary,app,cancelled}')::int=2 and (:'fu'::jsonb #>> '{summary,app,still_open}')::int=2
  and (:'fu'::jsonb #>> '{summary,app,rate_of_closed_pct}')::numeric=66.7 and (:'fu'::jsonb #>> '{summary,app,rate_of_all_pct}')::numeric=50.0);
select tt.chk('T5 paper 20-1 is its own block (3 sheets: 1 handed, 1 not collected, 1 open) and is not mixed into the app rate', (:'fu'::jsonb #>> '{summary,paper_20_1,orders}')::int=3 and (:'fu'::jsonb #>> '{summary,paper_20_1,delivered}')::int=1
  and (:'fu'::jsonb #>> '{summary,paper_20_1,rate_of_closed_pct}')::numeric=50.0 and not (:'fu'::jsonb -> 'summary') ? 'paper_20_6');
select tt.chk('T5 nothing in the range gives null rates, not 0', (c2_order_fulfilment(tt.today()-300, tt.today()-290) -> 'summary') = '{}'::jsonb);
select tt.chk('T5 breakdown by channel exists', (:'fu'::jsonb #>> '{breakdown,"app:channel:phone",orders}')::int>=1);

\echo == T9 paste twice
\ir phase450.sql
select tt.chk('T9 pasted again without error', true);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
