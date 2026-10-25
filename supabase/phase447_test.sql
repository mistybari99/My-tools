-- Phase 447 tests (RPT-C2 R4 part 3: order advance as a customer advance, setting OFF). Neutral test_* data only.  bash tests/sql/c2_run.sh phase447
\ir ../tests/sql/c2_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions open to browsers, helpers closed, table read-only, RLS on',
  has_function_privilege('authenticated','public.c2_order_advance_post(uuid)','execute') and has_function_privilege('authenticated','public.c2_order_deliver(uuid,jsonb)','execute')
  and has_function_privilege('authenticated','public.c2_order_advance_apply(uuid)','execute') and has_function_privilege('authenticated','public.c2_order_advance_void(uuid,text)','execute')
  and not has_function_privilege('authenticated','public._c2_customer_for(text,text)','execute') and not has_function_privilege('anon','public.c2_order_deliver(uuid,jsonb)','execute')
  and not has_table_privilege('authenticated','public.order_advance_posts','update') and (select relrowsecurity from pg_class where relname='order_advance_posts'));
select tt.chk('T0 the switch is OFF and the from-date is blank', not rule_on('order_advance_post_on') and rule_txt('order_advance_post_from') is null);

\echo == T1 switch OFF: nothing changes
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_1', '01700000021', 'test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'home', null, tt.today()+1, 30, 0, 50, 'cash', null, null) ->> 'id' as o1 \gset
select tt.as(:'c');
select tt.err('T1 posting refused while OFF', format($$select c2_order_advance_post('%s')$$, :'o1'), 'advance_post_off');
select tt.as(:'p');
select online_order_status(:'o1'::uuid,'confirmed') is not null as a1 \gset
select online_order_status(:'o1'::uuid,'packed') is not null as a2 \gset
select (c2_order_deliver(:'o1'::uuid, '[{"mode":"cash","amount":180}]'::jsonb)) as d1 \gset
select tt.chk('T1 OFF: c2_order_deliver = the old delivery (advance counted as a sale payment: paid 230, due 0)', (:'d1'::jsonb ->> 'advance_posted')='false' and (:'d1'::jsonb ->> 'paid')::numeric=230 and (:'d1'::jsonb ->> 'due')::numeric=0
  and (select count(*) from cash_moves)=0);

\echo == T2 switch ON: post, apply, void
select tt.as(:'o'); select set_rule('order_advance_post_on','true') is null as s1 \gset
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_2', '01700000022', 'test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb, 'home', null, tt.today()+1, 30, 0, 50, 'mobile', null, null) ->> 'id' as o2 \gset
select tt.as(:'m');
select tt.err('T2 a manager without the cash_move right cannot post the advance', format($$select c2_order_advance_post('%s')$$, :'o2'), 'not allowed');
select tt.chk('T2 nothing was written by the refused post', (select count(*) from order_advance_posts)=0 and (select count(*) from cash_moves)=0);
select tt.as(:'x');
select tt.err('T2 other place refused', format($$select c2_order_advance_post('%s')$$, :'o2'), 'not allowed for this location');
select tt.as(:'c');
select c2_order_advance_post(:'o2'::uuid) ->> 'move_id' as mv2 \gset
select tt.chk('T2 posted: one cust_advance cash move of 50 by mobile, customer made from the order mobile', (select kind from cash_moves where id=:'mv2'::uuid)='cust_advance' and (select amount from cash_moves where id=:'mv2'::uuid)=50
  and (select mode from cash_moves where id=:'mv2'::uuid)='mobile' and exists (select 1 from customers where mobile='01700000022' and name='test_customer_2'));
select tt.chk('T2 posting again is a no-op', (c2_order_advance_post(:'o2'::uuid) ->> 'noop')::boolean and (select count(*) from order_advance_posts where order_id=:'o2'::uuid)=1);
select tt.as(:'p');
select tt.err('T2 the order advance cannot be edited under a posted advance', format($$select online_order_save('%s',null,null,'phone','test_customer_2','01700000022','test_address','[{"item_id":"%s","qty":2}]'::jsonb,'home',null,tt.today()+1,30,0,60,'mobile',null,null)$$, :'o2', :'ia'), 'advance_posted');
select tt.chk('T2 editing something else (the note) still works', online_order_save(:'o2'::uuid,null,null,'phone','test_customer_2','01700000022','test_address', format('[{"item_id":"%s","qty":2}]', :'ia')::jsonb,'home',null,tt.today()+1,30,0,50,'mobile',null,'test_note') is not null);
select online_order_status(:'o2'::uuid,'confirmed') is not null as b1 \gset
select online_order_status(:'o2'::uuid,'packed') is not null as b2 \gset
select (c2_order_deliver(:'o2'::uuid, '[{"mode":"cash","amount":180}]'::jsonb)) as d2 \gset
select tt.chk('T2 delivery with a posted advance: sale paid 180, due 50 (the advance is not counted twice), advance not applied yet (no cash right)',
  (:'d2'::jsonb ->> 'advance_posted')='true' and (:'d2'::jsonb ->> 'paid')::numeric=180 and (:'d2'::jsonb ->> 'due')::numeric=50 and (:'d2'::jsonb ->> 'advance_applied')='false'
  and (select state from order_advance_posts where order_id=:'o2'::uuid)='posted');
select tt.as(:'c');
select c2_order_advance_apply(:'o2'::uuid) ->> 'applied' as ap2 \gset
select tt.chk('T2 applied by the cash user: 50 used, state applied, a cust_advance_used move (no money)', :'ap2'::numeric=50 and (select state from order_advance_posts where order_id=:'o2'::uuid)='applied'
  and (select count(*) from cash_moves where kind='cust_advance_used' and amount=50 and mode is null)=1);
select tt.chk('T2 applying again is a no-op', (c2_order_advance_apply(:'o2'::uuid) ->> 'noop')::boolean);
select tt.chk('T2 the customer advance balance is back to 0', coalesce((select sum(case when kind='cust_advance' then amount else -amount end) from cash_moves where status='done' and kind like 'cust_advance%'),0)=0);

\echo == T3 void a posted advance, then edit
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_3', '01700000023', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 40, 'cash', null, null) ->> 'id' as o3 \gset
select tt.as(:'c');
select c2_order_advance_post(:'o3'::uuid) ->> 'post_id' as p3 \gset
select tt.err('T3 void needs a reason', format($$select c2_order_advance_void('%s','')$$, :'o3'), 'reason_required');
select tt.as(:'p');
select tt.err('T3 a salesperson without the cash_move right cannot void', format($$select c2_order_advance_void('%s','test_reason')$$, :'o3'), 'not allowed');
select tt.as(:'c');
select c2_order_advance_void(:'o3'::uuid, 'test_wrong_amount') ->> 'state' as v3 \gset
select tt.chk('T3 voided: post void, cash move void (kept), order advance editable again', :'v3'='void' and (select state from order_advance_posts where id=:'p3'::bigint)='void'
  and (select status from cash_moves where kind='cust_advance' and amount=40)='void');
select tt.as(:'p');
select tt.chk('T3 the advance can now be changed', online_order_save(:'o3'::uuid,null,null,'phone','test_customer_3','01700000023',null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb,'pickup',null,null,0,0,45,'cash',null,null) is not null);
select tt.as(:'c');
select c2_order_advance_post(:'o3'::uuid) ->> 'amount' as amt3 \gset
select tt.chk('T3 and it can be posted again (new post row, new money record)', :'amt3'::numeric=45 and (select count(*) from order_advance_posts where order_id=:'o3'::uuid)=2);

\echo == T4 the from-date
select tt.as(:'o'); select set_rule('order_advance_post_from', to_jsonb((tt.today()+5)::text)) is null as f1 \gset
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_customer_4', '01700000024', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, null, 0, 0, 30, 'cash', null, null) ->> 'id' as o4 \gset
select tt.as(:'c');
select tt.err('T4 an order created before the from-date is not posted', format($$select c2_order_advance_post('%s')$$, :'o4'), 'advance_post_off');
select tt.as(:'o'); select set_rule('order_advance_post_from', null) is null as f2 \gset

\echo == T5 the books (journal) agree
select tt.as(:'o'); select acct_set_start(tt.today()-30) is not null as ac0 \gset
select set_rule('accounting_on','true') is null as ac \gset
select acct_post_pending(false, 500) is not null as posted \gset
select tt.chk('T5 account 2300 holds the 45 still posted for order 3 and nothing for order 2 (used)', (select coalesce(sum(l.credit-l.debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='2300')=45);
select tt.chk('T5 the journal is balanced', (select coalesce(sum(debit)-sum(credit),0) from journal_lines)=0);

\echo == T9 paste twice
select count(*) as n_before from order_advance_posts \gset
select count(*) as r_before from rules where key like 'order_advance%' \gset
\ir phase447.sql
select tt.chk('T9 pasted again: no new rows', (select count(*) from order_advance_posts)=:n_before and (select count(*) from rules where key like 'order_advance%')=:r_before);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
