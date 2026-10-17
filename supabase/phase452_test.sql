-- Phase 452 tests (RPT-C2 R4 part 8: order on a production run, order-wise cost #160, order profitability #161). Neutral test_* data only.  bash tests/sql/c2_run.sh phase452
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_orders_fixture.sql

-- one production run: 5 raw @ 20 = 100 material, 10 test_item_a made (unit cost 10)
select tt.as(:'o');
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('TST-RM','test_raw','test_raw','kg','kg','raw_material',true,0);
select id as irm from items where code='TST-RM' \gset
select stock_opening(:'irm'::uuid, 1, 200, 20, null, 'seed') is not null as oprm \gset
select (recipe_save(null, :'ia'::uuid, 10, null, 'test recipe', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'irm','qty',5,'waste_pct',0)))->>'id')::uuid as rc \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run1 \gset
select production_post(1, :'rc'::uuid, 1, gen_random_uuid())->>'run_id' as run2 \gset

\echo == T0 shape
select tt.chk('T0 functions open, helper closed, table read-only, RLS on',
  has_function_privilege('authenticated','public.c2_production_link_order(uuid,uuid,numeric,text)','execute') and has_function_privilege('authenticated','public.c2_order_production_cost(date,date,int,uuid)','execute')
  and has_function_privilege('authenticated','public.c2_order_profit(date,date,int)','execute') and has_function_privilege('authenticated','public.c2_orders_for_production(int)','execute')
  and not has_function_privilege('authenticated','public._c2_run_alloc(bigint)','execute') and not has_table_privilege('authenticated','public.production_run_orders','insert')
  and (select relrowsecurity from pg_class where relname='production_run_orders'));

\echo == T1 link a run to orders
select tt.as(:'p');
select c2_production_link_order(:'run1'::uuid, :'oa'::uuid, 4, 'test_note') ->> 'id' as l1 \gset
select tt.chk('T1 salesperson linked 4 of the 10 made to order A', :'l1' is not null and (select qty from production_run_orders where id=:'l1'::bigint)=4);
select tt.chk('T1 same pair again = no-op', (c2_production_link_order(:'run1'::uuid, :'oa'::uuid, 4) ->> 'noop')::boolean);
select tt.err('T1 more than the run made is refused (4 + 7 > 10)', format($$select c2_production_link_order('%s','%s',7)$$, :'run1', :'oe'), 'qty_over_output');
select c2_production_link_order(:'run1'::uuid, :'oe'::uuid, 6) ->> 'id' as l2 \gset
select tt.err('T1 qty must be above 0', format($$select c2_production_link_order('%s','%s',0)$$, :'run2', :'of'), 'bad_qty');
select c2_production_link_order(:'run2'::uuid, :'of'::uuid) ->> 'id' as l3 \gset
select tt.chk('T1 a blank quantity is allowed when the run has only this link (whole run)', :'l3' is not null);
select tt.as(:'x');
select tt.err('T1 place 2 manager (not the order place, no production right) refused', format($$select c2_production_link_order('%s','%s',1)$$, :'run2', :'ob'), 'not allowed');
select tt.as(:'k');
select tt.err('T1 storekeeper without production or POS right refused', format($$select c2_production_link_order('%s','%s',1)$$, :'run2', :'ob'), 'not allowed');
select tt.as(:'o');
select tt.chk('T1 the owner may link too', c2_production_link_order(:'run2'::uuid, :'ob'::uuid, 2) ->> 'id' is not null);
select tt.err('T1 a run with a whole-run link cannot take a second blank... the sum now exceeds: whole run is NOT counted, only explicit quantities', format($$select c2_production_link_order('%s','%s',9)$$, :'run2', :'og'), 'qty_over_output');

\echo == T2 order-wise cost (#160)
select tt.as(:'o');
select c2_order_production_cost(tt.today()-1, tt.today()+1) as pc \gset
select tt.chk('T2 order A: 4 of 10 -> material 40 (100 x 4/10); order E: 6 of 10 -> material 60; shares 40 and 60 percent',
  (select (r ->> 'material_cost')::numeric from jsonb_array_elements(:'pc'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')=40 and (select (r ->> 'material_cost')::numeric from jsonb_array_elements(:'pc'::jsonb -> 'rows') r where r ->> 'order_id'=:'oe')=60
  and (select (r ->> 'share_pct')::numeric from jsonb_array_elements(:'pc'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')=40.0);
select tt.chk('T2 per order totals; run 2 is shared by F (whole run blank) and B (2): F cost is NOT known because the run has two links and F gave no quantity',
  (select (x ->> 'material_cost')::numeric from jsonb_array_elements(:'pc'::jsonb -> 'per_order') x where x ->> 'order_id'=:'oa')=40
  and (select x -> 'material_cost' from jsonb_array_elements(:'pc'::jsonb -> 'per_order') x where x ->> 'order_id'=:'of')='null'::jsonb
  and (select (r ->> 'allocation_known')::boolean from jsonb_array_elements(:'pc'::jsonb -> 'rows') r where r ->> 'order_id'=:'of')=false
  and (select (r ->> 'material_cost')::numeric from jsonb_array_elements(:'pc'::jsonb -> 'rows') r where r ->> 'order_id'=:'ob')=20);
select tt.chk('T2 cake order A has a linked run (so it is not in the without-a-run count); no other cake order exists', (:'pc'::jsonb ->> 'cake_orders_without_a_linked_run')::int=0);
select tt.as(:'m');
select c2_order_production_cost(tt.today()-1, tt.today()+1) as pcm \gset
select tt.chk('T2 manager without the cost right: links visible, costs null, note cost_hidden', jsonb_array_length(:'pcm'::jsonb -> 'rows')=4 and (select bool_and((r -> 'material_cost')='null'::jsonb) from jsonb_array_elements(:'pcm'::jsonb -> 'rows') r)
  and (:'pcm'::jsonb -> 'notes') ? 'cost_hidden');
select tt.chk('T2 single order filter', jsonb_array_length(c2_order_production_cost(tt.today()-1, tt.today()+1, null, :'oa'::uuid) -> 'rows')=1);

\echo == T3 void a link
select tt.as(:'p');
select tt.err('T3 a void needs a reason', format($$select c2_production_link_void(%s,'')$$, :'l1'), 'reason_required');
select tt.chk('T3 void keeps the row', (c2_production_link_void(:'l1'::bigint, 'test_wrong_order') ->> 'state')='void' and (select count(*) from production_run_orders where id=:'l1'::bigint)=1);
select tt.err('T3 a link row cannot be edited directly', format($$update production_run_orders set qty=1 where id=%s$$, :'l1'), 'append_only');
select tt.chk('T3 after the void, order A has no active link', (select count(*) from production_run_orders where order_id=:'oa'::uuid and state='active')=0);
select c2_production_link_order(:'run1'::uuid, :'oa'::uuid, 4) is not null as relink \gset

\echo == T4 orders a factory person can pick from
select tt.as(:'k');
select tt.err('T4 storekeeper without any production or POS right refused', $$select c2_orders_for_production()$$, 'not allowed');
select tt.as(:'p');
select c2_orders_for_production() as pk \gset
select tt.chk('T4 open orders only: B and G (confirmed/new); no mobile numbers, no money in the answer', jsonb_array_length(:'pk'::jsonb -> 'rows')=2 and (:'pk'::text !~ '0170000') and (:'pk'::text !~ 'advance|total|balance'));

\echo == T5 order profitability (#161)
select tt.as(:'o');
select c2_order_profit(tt.today()-1, tt.today()+1) as pf \gset
select tt.chk('T5 A: revenue 230 - goods 80 (2 x 40 at the sale) - delivery 40 = 110; E (pickup): 200 - 80 = 120', (select (r ->> 'profit')::numeric from jsonb_array_elements(:'pf'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')=110
  and (select (r ->> 'profit')::numeric from jsonb_array_elements(:'pf'::jsonb -> 'rows') r where r ->> 'order_id'=:'oe')=120);
select tt.chk('T5 F (home, no delivery cost written): NO profit, missing = delivery_cost (never a profit built on a zero cost)', (select r -> 'profit' from jsonb_array_elements(:'pf'::jsonb -> 'rows') r where r ->> 'order_id'=:'of')='null'::jsonb
  and (select r -> 'missing' from jsonb_array_elements(:'pf'::jsonb -> 'rows') r where r ->> 'order_id'=:'of')='["delivery_cost"]'::jsonb);
select tt.chk('T5 summary: 3 delivered, 2 with every cost known, profit 230 on revenue 430 = 53.5 percent', (:'pf'::jsonb #>> '{summary,delivered_orders}')::int=3 and (:'pf'::jsonb #>> '{summary,orders_with_every_cost_known}')::int=2
  and (:'pf'::jsonb #>> '{summary,profit_of_full_cost_orders}')::numeric=230 and (:'pf'::jsonb #>> '{summary,margin_pct_of_full_cost_orders}')::numeric=53.5);
select tt.chk('T5 linked production cost is shown beside A (40) and not subtracted', (select (r ->> 'linked_production_cost')::numeric from jsonb_array_elements(:'pf'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')=40 and (:'pf'::jsonb -> 'notes') ? 'linked_production_not_subtracted');
select tt.as(:'m');
select c2_order_profit(tt.today()-1, tt.today()+1) as pfm \gset
select tt.chk('T5 manager without the cost right: revenue only, profit null, missing says cost_hidden', (select r -> 'profit' from jsonb_array_elements(:'pfm'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')='null'::jsonb
  and (select r -> 'missing' from jsonb_array_elements(:'pfm'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')='["cost_hidden"]'::jsonb and (:'pfm'::jsonb #>> '{summary,profit_of_full_cost_orders}') is null);
select tt.as(:'o');
set session_replication_role = replica;
insert into sale_returns (sale_id, location_id, lines, amount, credit_amount, refund_amount, reason_code, status, created_by) select sale_id, 1, '[]'::jsonb, 100, 100, 0, 'test_reason', 'done', :'p'::uuid from online_orders where id=:'oe'::uuid;
set session_replication_role = origin;
select c2_order_profit(tt.today()-1, tt.today()+1) as pfr \gset
select tt.chk('T5 a delivered order whose sale has a return is not judged: no profit, missing = sale_has_returns', (select r -> 'profit' from jsonb_array_elements(:'pfr'::jsonb -> 'rows') r where r ->> 'order_id'=:'oe')='null'::jsonb
  and (select r -> 'missing' from jsonb_array_elements(:'pfr'::jsonb -> 'rows') r where r ->> 'order_id'=:'oe')='["sale_has_returns"]'::jsonb);
select tt.as(:'x');
select tt.chk('T5 place 2 manager sees no orders', (c2_order_profit(tt.today()-1, tt.today()+1) #>> '{summary,delivered_orders}')::int=0);
select tt.as(:'k');
select tt.err('T5 storekeeper refused', $$select c2_order_profit(current_date-1, current_date)$$, 'not allowed');

\echo == T6 reads wrote nothing; paste twice
select tt.as(:'o');
select count(*) as n_before from production_run_orders \gset
\ir phase452.sql
select tt.chk('T9 pasted again: no new rows', (select count(*) from production_run_orders)=:n_before);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
