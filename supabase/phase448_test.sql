-- Phase 448 tests (RPT-C2 R4 part 4: cancel with refund makes a real money record, setting OFF). Neutral test_* data only.  bash tests/sql/c2_run.sh phase448
\ir ../tests/sql/c2_fixture.sql
select tt.as(:'o'); select acct_set_start(tt.today()-30) is not null as ac0 \gset
select set_rule('accounting_on','true') is null as ac \gset

\echo == T0 shape
select tt.chk('T0 functions open, helpers closed, table read-only, RLS on',
  has_function_privilege('authenticated','public.c2_order_cancel(uuid,text,text,text)','execute') and has_function_privilege('authenticated','public.c2_order_refund_pay(uuid,text)','execute')
  and has_function_privilege('authenticated','public.c2_order_refunds_list(date,date,int,text)','execute') and not has_function_privilege('authenticated','public._c2_refund_pay(bigint)','execute')
  and not has_table_privilege('authenticated','public.order_refunds','insert') and (select relrowsecurity from pg_class where relname='order_refunds') and not rule_on('order_refund_record_on'));

\echo == T1 switch OFF = today
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_1', '01700000031', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 60, 'cash', null, null) ->> 'id' as o1 \gset
select c2_order_cancel(:'o1'::uuid, 'test_reason', 'refund') as c1 \gset
select tt.chk('T1 OFF: cancelled, refund not recorded, no row, no money move', (:'c1'::jsonb ->> 'status')='cancelled' and (:'c1'::jsonb ->> 'refund')='not_recorded'
  and (select count(*) from order_refunds)=0 and (select count(*) from cash_moves)=0);

\echo == T2 switch ON: the person may not move money -> a due refund, then paid by the cash user
select tt.as(:'o'); select set_rule('order_refund_record_on','true') is null as s1 \gset
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_2', '01700000032', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 60, 'mobile', null, null) ->> 'id' as o2 \gset
select c2_order_cancel(:'o2'::uuid, 'test_reason', 'refund') as c2 \gset
select tt.chk('T2 salesperson cancels: refund row due, nothing paid yet', (:'c2'::jsonb ->> 'refund')='due' and (select state from order_refunds where order_id=:'o2'::uuid)='due' and (select count(*) from cash_moves)=0);
select tt.chk('T2 default mode follows the advance mode (mobile)', (select refund_mode from order_refunds where order_id=:'o2'::uuid)='mobile');
select tt.err('T2 the salesperson cannot pay it', format($$select c2_order_refund_pay('%s')$$, :'o2'), 'not allowed');
select tt.as(:'x');
select tt.err('T2 other place cannot pay it', format($$select c2_order_refund_pay('%s')$$, :'o2'), 'not allowed for this location');
select tt.as(:'c');
select c2_order_refund_pay(:'o2'::uuid, 'cash') as pay2 \gset
select tt.chk('T2 paid by the cash user (mode changed to cash): two moves - 60 in (mobile, found now) and 60 out (cash), row paid',
  (:'pay2'::jsonb ->> 'state')='paid' and (select count(*) from cash_moves where kind='cust_advance' and amount=60 and mode='mobile')=1 and (select count(*) from cash_moves where kind='cust_advance_refund' and amount=60 and mode='cash')=1
  and (select state from order_refunds where order_id=:'o2'::uuid)='paid' and (select in_move_id from order_refunds where order_id=:'o2'::uuid) is not null);
select tt.chk('T2 paying again is a no-op', (c2_order_refund_pay(:'o2'::uuid) ->> 'noop')::boolean);
select tt.chk('T2 the customer advance balance is 0 (in 60, out 60)', coalesce((select sum(case when kind='cust_advance' then amount else -amount end) from cash_moves where status='done' and kind like 'cust_advance%'),0)=0);

\echo == T3 the canceller may move money: paid at once; a posted advance needs one move only
select tt.as(:'o'); select set_rule('order_advance_post_on','true') is null as s2 \gset
select tt.as(:'c');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_3', '01700000033', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 70, 'cash', null, null) ->> 'id' as o3 \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_4', '01700000034', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 80, 'cash', null, null) ->> 'id' as o4 \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_5', '01700000035', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 90, 'cash', null, null) ->> 'id' as o5 \gset
select c2_order_advance_post(:'o3'::uuid) is not null as ap3 \gset
select c2_order_advance_post(:'o4'::uuid) is not null as ap4 \gset
select tt.err('T3 income with a posted advance is refused (nothing cancelled)', format($$select c2_order_cancel('%s','test_reason','income')$$, :'o3'), 'advance_posted_income');
select tt.chk('T3 the refused cancel changed nothing', (select status from online_orders where id=:'o3'::uuid)='new');
select tt.err('T3 bad refund mode refused', format($$select c2_order_cancel('%s','test_reason','refund','card')$$, :'o3'), 'bad_mode');
select c2_order_cancel(:'o3'::uuid, 'test_reason', 'refund') as c3 \gset
select tt.chk('T3 posted advance + refund by a cash user: paid at once with ONE refund move (no extra cash-in), post state refunded',
  (:'c3'::jsonb ->> 'refund')='paid' and (select count(*) from cash_moves where kind='cust_advance_refund' and amount=70)=1 and (select count(*) from cash_moves where kind='cust_advance' and amount=70)=1
  and (select state from order_advance_posts where order_id=:'o3'::uuid)='refunded' and (select in_move_id from order_refunds where order_id=:'o3'::uuid) is null);
select c2_order_cancel(:'o4'::uuid, 'test_reason', 'adjust') as c4 \gset
select tt.chk('T3 posted advance + adjust: the advance stays a customer advance (post still posted, no refund row)', (:'c4'::jsonb ->> 'refund')='held_as_customer_advance'
  and (select state from order_advance_posts where order_id=:'o4'::uuid)='posted' and (select count(*) from order_refunds where order_id=:'o4'::uuid)=0);
select tt.chk('T3 advance list shows the 80 still held', coalesce((select sum(case when kind='cust_advance' then amount else -amount end) from cash_moves where status='done' and kind like 'cust_advance%'),0)=80);

\echo == T4 the old cancel function still creates the due row (no screen can skip it)
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_6', '01700000036', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 25, 'cash', null, null) ->> 'id' as o6 \gset
select online_order_cancel(:'o6'::uuid, 'test_reason', 'refund') is not null as old6 \gset
select tt.chk('T4 online_order_cancel (old screen): a due refund row exists', (select state from order_refunds where order_id=:'o6'::uuid)='due');
select tt.as(:'c');
select tt.err('T4 a refund can be closed without paying only with a reason', format($$select c2_order_refund_void('%s','')$$, :'o6'), 'reason_required');
select tt.chk('T4 void: row void, still there', (c2_order_refund_void(:'o6'::uuid, 'test_settled_another_way') ->> 'state')='void' and (select count(*) from order_refunds where order_id=:'o6'::uuid)=1);

\echo == T5 the list and the books
select tt.as(:'p');
select c2_order_refunds_list(tt.today()-1, tt.today()+1, null, null) as lst \gset
select tt.chk('T5 list: rows for orders 2, 3, 6 visible to the place-1 user', jsonb_array_length(:'lst'::jsonb -> 'rows')=3 and (:'lst'::jsonb ->> 'record_on')='true');
select tt.as(:'x');
select tt.chk('T5 other place sees none', jsonb_array_length(c2_order_refunds_list(null,null,null,null) -> 'rows')=0);
select tt.as(:'k');
select tt.err('T5 storekeeper without report access refused', $$select c2_order_refunds_list(null,null,null,null)$$, 'not allowed');
select tt.as(:'o');
select acct_post_pending(false, 500) is not null as posted \gset
select tt.chk('T5 account 2300 now holds only the 80 of the adjusted order', (select coalesce(sum(l.credit-l.debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='2300')=80);
select tt.chk('T5 journal balanced and the refunds cost nothing in income or expense (only cash/bank/mobile and 2300 moved)', (select coalesce(sum(debit)-sum(credit),0) from journal_lines)=0
  and not exists (select 1 from journal_lines l join coa_accounts a on a.id=l.account_id where a.type in ('income','expense')));

\echo == T9 paste twice
select count(*) as n_before from order_refunds \gset
\ir phase448.sql
select tt.chk('T9 pasted again: no new rows, one rule', (select count(*) from order_refunds)=:n_before and (select count(*) from rules where key='order_refund_record_on')=1);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
