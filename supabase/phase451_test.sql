-- Phase 451 tests (RPT-C2 R4 part 7: cancellation and refunds #157, delivery cost #162). Neutral test_* data only.  bash tests/sql/c2_run.sh phase451
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_orders_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions open to browsers, anon none',
  has_function_privilege('authenticated','public.c2_order_cancellations(date,date,int)','execute') and has_function_privilege('authenticated','public.c2_delivery_cost_report(date,date,int)','execute')
  and not has_function_privilege('anon','public.c2_delivery_cost_report(date,date,int)','execute'));

\echo == T1 cancellations and refunds (#157)
select tt.as(:'m');
select c2_order_cancellations(tt.today()-1, tt.today()+1) as cx \gset
select tt.chk('T1 two cancelled today (C and D); advance 85; refund due 60; refund NOT RECORDED 25 (cancelled while the switch was off)',
  (:'cx'::jsonb #>> '{summary,cancelled}')::int=2 and (:'cx'::jsonb #>> '{summary,advance_total}')::numeric=85 and (:'cx'::jsonb #>> '{summary,refund_due}')::numeric=60
  and (:'cx'::jsonb #>> '{summary,refund_not_recorded}')::numeric=25 and (:'cx'::jsonb #>> '{summary,refunded}')::numeric=0);
select tt.chk('T1 cancel rate = 2 of 7 orders taken = 28.6 percent', (:'cx'::jsonb #>> '{summary,orders_taken_in_range}')::int=7 and (:'cx'::jsonb #>> '{summary,cancel_rate_pct}')::numeric=28.6);
select tt.chk('T1 reasons grouped, one order each', jsonb_array_length(:'cx'::jsonb -> 'by_reason')=2 and (select (r ->> 'orders')::int from jsonb_array_elements(:'cx'::jsonb -> 'by_reason') r where r ->> 'reason'='test_reason_c')=1);
select tt.chk('T1 paper block: one sheet not collected, advance 80, fate refund counted', (:'cx'::jsonb #>> '{paper_20_1,sheets_not_collected}')::int=1 and (:'cx'::jsonb #>> '{paper_20_1,advance}')::numeric=80 and (:'cx'::jsonb #>> '{paper_20_1,by_fate,refund}')::int=1);
select tt.chk('T1 notes: sources_not_merged; the refund switch is on so no refund_switch_off note', (:'cx'::jsonb -> 'notes') ? 'sources_not_merged' and not (:'cx'::jsonb -> 'notes') ? 'refund_switch_off');
select tt.as(:'c');
select c2_order_refund_pay(:'oc'::uuid) is not null as paid_c \gset
select c2_order_cancellations(tt.today()-1, tt.today()+1) as cx2 \gset
select tt.chk('T1 after the refund is paid: refunded 60, due 0 (the report follows the money record)', (:'cx2'::jsonb #>> '{summary,refunded}')::numeric=60 and (:'cx2'::jsonb #>> '{summary,refund_due}')::numeric=0
  and (select r ->> 'advance_state' from jsonb_array_elements(:'cx2'::jsonb -> 'rows') r where r ->> 'order_id'=:'oc')='refunded');
select tt.chk('T1 a range with no cancellation: zero counts, null rate (not 0 of 0)', (c2_order_cancellations(tt.today()-300, tt.today()-290) #>> '{summary,cancelled}')::int=0 and (c2_order_cancellations(tt.today()-300, tt.today()-290) #>> '{summary,cancel_rate_pct}') is null);
select tt.as(:'o'); select set_rule('order_refund_record_on','false') is null as off1 \gset
select tt.chk('T1 switch off: the report says so (refund_switch_off) and keeps the rows', (c2_order_cancellations(tt.today()-1, tt.today()+1) -> 'notes') ? 'refund_switch_off');
select set_rule('order_refund_record_on','true') is null as on1 \gset

\echo == T2 delivery cost (#162) - owner (cost right)
select c2_delivery_cost_report(tt.today()-1, tt.today()+1) as dc \gset
select tt.chk('T2 3 home orders (A, B, F): 2 delivered; charge 60; cost captured on 1 (A: 40), not captured on 1 delivered (F)', (:'dc'::jsonb #>> '{summary,orders}')::int=3 and (:'dc'::jsonb #>> '{summary,delivered}')::int=2
  and (:'dc'::jsonb #>> '{summary,charge_total}')::numeric=60 and (:'dc'::jsonb #>> '{summary,with_cost_captured}')::int=1 and (:'dc'::jsonb #>> '{summary,cost_not_captured}')::int=1 and (:'dc'::jsonb #>> '{summary,cost_total_captured}')::numeric=40);
select tt.chk('T2 margin only where a cost was written: 30 - 40 = -10 (F is NOT counted as a free delivery)', (:'dc'::jsonb #>> '{summary,margin_where_cost_captured}')::numeric=-10 and (:'dc'::jsonb #>> '{summary,charge_where_cost_captured}')::numeric=30);
select tt.chk('T2 rows: F has cost null and cost_captured false; A has margin -10', (select r -> 'cost' from jsonb_array_elements(:'dc'::jsonb -> 'rows') r where r ->> 'order_id'=:'of')='null'::jsonb
  and (select (r ->> 'margin')::numeric from jsonb_array_elements(:'dc'::jsonb -> 'rows') r where r ->> 'order_id'=:'oa')=-10);
select tt.chk('T2 by kind: rider_pay 40; by delivery_by: test_rider 1 order, (not written) 2 orders', (:'dc'::jsonb #>> '{by_kind,rider_pay,amount}')::numeric=40
  and (select (r ->> 'orders')::int from jsonb_array_elements(:'dc'::jsonb -> 'by_delivery_by') r where r ->> 'delivery_by'='(not written)')=2);
select tt.chk('T2 paper 20-6: 2 ledger lines, charge 20, one line without a charge written; the paper has no cost side (note)', (:'dc'::jsonb #>> '{paper_20_6,lines}')::int=2 and (:'dc'::jsonb #>> '{paper_20_6,delivery_charge}')::numeric=20
  and (:'dc'::jsonb #>> '{paper_20_6,lines_without_charge_written}')::int=1 and (:'dc'::jsonb -> 'notes') ? 'paper_20_6_no_cost_side' and (:'dc'::jsonb -> 'notes') ? 'cost_is_information_not_posted');

\echo == T3 without the cost right the costs are hidden, not zero
select tt.as(:'m');
select c2_delivery_cost_report(tt.today()-1, tt.today()+1) as dcm \gset
select tt.chk('T3 manager: charge still shown, cost fields null, note cost_hidden', (:'dcm'::jsonb #>> '{summary,charge_total}')::numeric=60 and (:'dcm'::jsonb #>> '{summary,cost_total_captured}') is null and (:'dcm'::jsonb #>> '{summary,cost_not_captured}') is null
  and (:'dcm'::jsonb -> 'notes') ? 'cost_hidden' and (:'dcm'::jsonb -> 'by_kind')='null'::jsonb and (select bool_and((r -> 'cost')='null'::jsonb) from jsonb_array_elements(:'dcm'::jsonb -> 'rows') r));

\echo == T4 access
select tt.as(:'x');
select tt.chk('T4 place 2 manager sees nothing of place 1', (c2_order_cancellations(tt.today()-1, tt.today()+1) #>> '{summary,cancelled}')::int=0 and (c2_delivery_cost_report(tt.today()-1, tt.today()+1) #>> '{summary,orders}')::int=0);
select tt.as(:'k');
select tt.err('T4 storekeeper refused (cancellations)', $$select c2_order_cancellations(current_date-1, current_date)$$, 'not allowed');
select tt.err('T4 storekeeper refused (delivery cost)', $$select c2_delivery_cost_report(current_date-1, current_date)$$, 'not allowed');
select tt.as(:'r');
select tt.chk('T4 a view_reports holder may read both', (c2_order_cancellations(tt.today()-1, tt.today()+1) #>> '{summary,cancelled}')::int=2 and (c2_delivery_cost_report(tt.today()-1, tt.today()+1) #>> '{summary,orders}')::int=3);

\echo == T9 paste twice
\ir phase451.sql
select tt.chk('T9 pasted again without error', true);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
