-- Phase 449 tests (RPT-C2 R4 part 5: order register #153, cake register #155, advance and balances #156, order detail). Neutral test_* data only.  bash tests/sql/c2_run.sh phase449
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_orders_fixture.sql

\echo == T0 shape
select tt.chk('T0 report functions open to browsers, helpers closed, anon none',
  has_function_privilege('authenticated','public.c2_order_register(date,date,int,text,text,text,int)','execute') and has_function_privilege('authenticated','public.c2_cake_register(date,date,int,text)','execute')
  and has_function_privilege('authenticated','public.c2_order_balances(date,date,int,boolean)','execute') and has_function_privilege('authenticated','public.c2_order_detail(uuid)','execute')
  and not has_function_privilege('anon','public.c2_order_register(date,date,int,text,text,text,int)','execute') and not has_function_privilege('authenticated','public._c2_orders_base(date,date,int,text)','execute'));

\echo == T1 the register: three sources, never merged
select tt.as(:'m');
select c2_order_register(tt.today()-3, tt.today()+1) as reg \gset
select tt.chk('T1 3 sources present with their own totals (app 7 orders, paper 20-1 3 sheets, paper 20-6 2 lines)', (:'reg'::jsonb #>> '{totals_by_source,app,rows}')::int=7 and (:'reg'::jsonb #>> '{totals_by_source,paper_20_1,rows}')::int=3
  and (:'reg'::jsonb #>> '{totals_by_source,paper_20_6,rows}')::int=2 and (:'reg'::jsonb ->> 'row_count')::int=12);
select tt.chk('T1 every row has a source; no row merges two sources', (select bool_and(r ->> 'source' in ('app','paper_20_1','paper_20_6')) from jsonb_array_elements(:'reg'::jsonb -> 'rows') r)
  and (select count(*) from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'source'='app' and r ->> 'entry_id' is not null)=0);
select tt.chk('T1 notes: sources_not_merged present, module_off absent (module is on)', (:'reg'::jsonb -> 'notes') ? 'sources_not_merged' and not ((:'reg'::jsonb -> 'notes') ? 'module_off'));
select c2_order_register(tt.today()-3, tt.today()+1, null, 'app') as reg_app \gset
select tt.chk('T1 source filter: app only = 7 rows', jsonb_array_length(:'reg_app'::jsonb -> 'rows')=7 and not (:'reg_app'::jsonb -> 'totals_by_source') ? 'paper_20_1');
select tt.err('T1 a bad source is refused', $$select c2_order_register(current_date-1, current_date, null, 'test_source')$$, 'bad_filter');
select tt.err('T1 to before from refused', $$select c2_order_register(current_date, current_date-1)$$, 'bad_date');

\echo == T2 balances per order (the old list is not changed)
select (r ->> 'balance')::numeric as bal_a, r ->> 'advance_state' as st_a, r ->> 'balance_basis' as bs_a, r ->> 'order_type' as ty_a, (r -> 'promised_from') as pf_a, (r ->> 'delivery_cost')::numeric as dc_a
  from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'order_id' = :'oa' \gset
select tt.chk('T2 order A delivered and fully paid: balance 0 (the old list says 180 owed), advance paid into the sale, type cake, slot 10:00', :'bal_a'::numeric=0 and :'st_a'='paid_into_sale' and :'ty_a'='cake'
  and (select (balance) from online_orders_list(null,null,null,null,50) l, jsonb_to_recordset(online_orders_list(null,null,null,null,50)) as x(id uuid, balance numeric) where x.id=:'oa'::uuid limit 1)=180);
select tt.chk('T2 order A delivery cost is visible to a manager only with the cost right: not for the manager role here (hidden)', not :{?dc_a});
select (r ->> 'balance')::numeric as bal_b, r ->> 'status' as s_b from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'order_id' = :'ob' \gset
select tt.chk('T2 order B open: 200 - 40 = 160', :'bal_b'::numeric=160 and :'s_b'='confirmed');
select r ->> 'advance_state' as st_c, (r ->> 'balance')::numeric as bal_c from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'order_id' = :'oc' \gset
select tt.chk('T2 order C cancelled, refund due: owes nothing, advance state refund_due', :'st_c'='refund_due' and :'bal_c'::numeric=0);
select r ->> 'advance_state' as st_d from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'order_id' = :'od' \gset
select tt.chk('T2 order D cancelled while the switch was OFF: refund_not_recorded', :'st_d'='refund_not_recorded');
select r ->> 'advance_state' as st_e, (r ->> 'balance')::numeric as bal_e, r ->> 'balance_basis' as bs_e from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'order_id' = :'oe' \gset
select tt.chk('T2 order E delivered, advance posted and applied: balance 0, applied_to_sale', :'st_e'='applied_to_sale' and :'bal_e'::numeric=0 and :'bs_e'='sale_due_after_payments_and_applied_advance');
select (r ->> 'balance')::numeric as bal_f from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'order_id' = :'of' \gset
select tt.chk('T2 order F delivered, part paid: 130 still due on the sale', :'bal_f'::numeric=130);
select r ->> 'balance' as bal_g from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'order_id' = :'og' \gset
select tt.chk('T2 order G new: 50 - 0', :'bal_g'::numeric=50);
select tt.chk('T2 paper 20-1 open sheet: 500 - 100 = 400; handed sheet: 300-100-200 = 0; not collected: 0',
  (select (r ->> 'balance')::numeric from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'ref'='20-1/9001')=400
  and (select (r ->> 'balance')::numeric from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'ref'='20-1/9002')=0
  and (select (r ->> 'balance')::numeric from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'ref'='20-1/9003')=0);
select tt.chk('T2 paper 20-6 lines carry amount and delivery charge, no balance (null, not 0)', (select (r ->> 'delivery_charge')::numeric from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'ref'='20-6/9004/1')=20
  and (select r -> 'balance' from jsonb_array_elements(:'reg'::jsonb -> 'rows') r where r ->> 'ref'='20-6/9004/1')='null'::jsonb);

\echo == T3 paper sheet with the due payment not written shows no balance
set session_replication_role = replica;
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff, submitted_at) values
 ('20-1', 1, 9005, tt.today(), 'submitted', jsonb_build_object('order_type','normal','cust_name','test_paper_d','total','300','advance','100','cust_signed','true'), :'p', 'test_sales1', now());
set session_replication_role = origin;
select c2_order_register(tt.today(), tt.today(), null, 'paper_20_1') as regp \gset
select tt.chk('T3 handed sheet without a due payment: balance is null and the basis says so (never shown as 0)', (select r -> 'balance' from jsonb_array_elements(:'regp'::jsonb -> 'rows') r where r ->> 'ref'='20-1/9005')='null'::jsonb
  and (select r ->> 'balance_basis' from jsonb_array_elements(:'regp'::jsonb -> 'rows') r where r ->> 'ref'='20-1/9005')='due_payment_not_written' and (:'regp'::jsonb #>> '{totals_by_source,paper_20_1,rows_without_balance}')::int=1);

\echo == T4 date basis and filters
select tt.chk('T4 by promised date: only orders with a delivery date inside the range (A, B, E, F), no 20-6 (no date basis)', (c2_order_register(tt.today()-3, tt.today()+1, null, null, null, 'promised') ->> 'row_count')::int
  = (select count(*) from online_orders where delivery_date between tt.today()-3 and tt.today()+1) + (select count(*) from entries where form_code='20-1' and (data->>'deliv_date')::date between tt.today()-3 and tt.today()+1));
select tt.chk('T4 status filter works (delivered app orders = 3)', (c2_order_register(tt.today()-3, tt.today()+1, null, 'app', 'delivered') ->> 'row_count')::int=3);

\echo == T5 cake register
select c2_cake_register(tt.today()-3, tt.today()+1) as ck \gset
select tt.chk('T5 cake register: 1 app spec row (1.5 kg, flavour, message, design, photo) and 1 paper custom item row; 4 open or delivered app orders without a spec are counted, not hidden',
  (select count(*) from jsonb_array_elements(:'ck'::jsonb -> 'rows') r where r ->> 'source'='app')=1 and (select count(*) from jsonb_array_elements(:'ck'::jsonb -> 'rows') r where r ->> 'source'='paper_20_1')=1
  and (select (r ->> 'weight_kg')::numeric from jsonb_array_elements(:'ck'::jsonb -> 'rows') r where r ->> 'source'='app')=1.5
  and (select r ->> 'message' from jsonb_array_elements(:'ck'::jsonb -> 'rows') r where r ->> 'source'='paper_20_1')='test_msg' and (:'ck'::jsonb ->> 'app_orders_without_spec')::int=4);

\echo == T6 advance and outstanding balances
select c2_order_balances(tt.today()-3, tt.today()+1) as bl \gset
select tt.chk('T6 open orders: advance held 40 (B) + 0; balance to collect 160 + 50 = 210; advance not in the books 40',
  (:'bl'::jsonb #>> '{summary,app,advance_held_open_orders}')::numeric=40 and (:'bl'::jsonb #>> '{summary,app,balance_to_collect_open_orders}')::numeric=210 and (:'bl'::jsonb #>> '{summary,app,advance_not_in_books_open}')::numeric=40);
select tt.chk('T6 delivered orders still owing: only F (130); cancelled advances to return: C (60 due) + D (25 not recorded) = 85',
  (:'bl'::jsonb #>> '{summary,app,still_owed_after_delivery}')::numeric=130 and (:'bl'::jsonb #>> '{summary,app,advance_to_return_cancelled}')::numeric=85);
select tt.chk('T6 paper: open sheet advance 100, balance 400; one handed sheet without a due payment written', (:'bl'::jsonb #>> '{summary,paper_20_1,advance_open_sheets}')::numeric=100 and (:'bl'::jsonb #>> '{summary,paper_20_1,balance_open_sheets}')::numeric=400
  and (:'bl'::jsonb #>> '{summary,paper_20_1,handed_without_due_payment_written}')::int=1);
select tt.chk('T6 notes say the old list differs', (:'bl'::jsonb -> 'notes') ? 'old_list_balance_differs');

\echo == T7 detail (drill-down)
select c2_order_detail(:'oa'::uuid) as dt \gset
select tt.chk('T7 detail of A: events, one cake spec, a promise, a sale with receipt, cost hidden for a manager without the cost right', jsonb_array_length(:'dt'::jsonb -> 'events')>=3 and jsonb_array_length(:'dt'::jsonb -> 'specs')=1
  and (:'dt'::jsonb #>> '{promise,slot_from}')='10:00:00' and (:'dt'::jsonb #>> '{sale,status}')='done' and (:'dt'::jsonb -> 'costs')='null'::jsonb and (:'dt'::jsonb ->> 'cost_hidden')='true');
select tt.as(:'o');
select c2_order_detail(:'oa'::uuid) as dto \gset
select tt.chk('T7 the owner sees the cost rows (40) and the register delivery_cost', jsonb_array_length(:'dto'::jsonb -> 'costs')=1 and (:'dto'::jsonb #>> '{register_row,delivery_cost}')::numeric=40);
select c2_order_register(tt.today()-3, tt.today()+1, null, 'app') as rego \gset
select tt.chk('T7 the owner register has delivery_cost for A', (select (r ->> 'delivery_cost')::numeric from jsonb_array_elements(:'rego'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')=40);

\echo == T8 access
select tt.as(:'x');
select tt.chk('T8 manager of place 2 sees no rows of place 1', (c2_order_register(tt.today()-3, tt.today()+1) ->> 'row_count')::int=0);
select tt.err('T8 place 2 manager cannot ask for place 1', $$select c2_order_register(current_date-1, current_date, 1)$$, 'not allowed for this location');
select tt.err('T8 place 2 manager cannot open the order detail of place 1', format($$select c2_order_detail('%s')$$, :'oa'), 'not allowed');
select tt.as(:'r');
select c2_order_register(tt.today()-3, tt.today()+1) as regr \gset
select tt.chk('T8 a view_reports holder without POS reads the register; mobile numbers are hidden and the note says so', (:'regr'::jsonb ->> 'row_count')::int=13 and (:'regr'::jsonb -> 'notes') ? 'mobile_hidden'
  and (select bool_and((r -> 'customer_mobile')='null'::jsonb) from jsonb_array_elements(:'regr'::jsonb -> 'rows') r));
select tt.as(:'k');
select tt.err('T8 a storekeeper with no report right is refused', $$select c2_order_register(current_date-1, current_date)$$, 'not allowed');
select tt.as(:'o'); select set_rule('online_orders_on','false') is null as off \gset
select tt.as(:'m');
select c2_order_register(tt.today()-3, tt.today()+1) as regoff \gset
select tt.chk('T8 module switched off: the answer says module_off AND still returns the rows that exist (nothing hidden)', (:'regoff'::jsonb -> 'notes') ? 'module_off' and (:'regoff'::jsonb ->> 'row_count')::int=13 and (:'regoff'::jsonb ->> 'module_on')='false');
select tt.as(:'o'); select set_rule('online_orders_on','true') is null as on2 \gset

\echo == T9 nothing was changed by reading
select tt.chk('T9 the old list still gives the old figure for A (180) - existing figures untouched', (select x.balance from jsonb_to_recordset(online_orders_list(null,null,null,null,50)) as x(id uuid, balance numeric) where x.id=:'oa'::uuid)=180);
select count(*) as n_before from audit_log \gset
select c2_order_register(tt.today()-3, tt.today()+1) is not null as again \gset
select tt.chk('T9 reading wrote no audit line', (select count(*) from audit_log)=:n_before);
\ir phase449.sql
select tt.chk('T9 phase 449 pasted again without error', true);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
