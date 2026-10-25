-- FRESH DB ONLY (counts and stock numbers assume an empty start; do not re-run on a used db).
-- Phase 12 tests. Fresh db: ORDER="phase8 phase9 phase10 phase12" bash tests/sql/build_fresh_db.sh <db>; then psql -qAt -f supabase/phase12_test.sql (prints PASS / FAIL, totals at the end).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set m '00000000-0000-0000-0000-000000000005'
\set x '00000000-0000-0000-0000-000000000006'
\set g '00000000-0000-0000-0000-000000000007'
\set v '00000000-0000-0000-0000-000000000008'
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
create or replace function tt.supbal(p uuid) returns numeric language sql security definer as $$ select public._sup_balance(p) $$;
create or replace function tt.custbal(p uuid) returns numeric language sql security definer as $$ select public._cust_bal(p) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','buy4@s.app','{"full_name":"Buyer"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}'), (:'x','far6@s.app','{"full_name":"Far"}'), (:'g','godown7@s.app','{"full_name":"Godown"}'),
 (:'v','cost8@s.app','{"full_name":"CostOnly"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'k','storekeeper'),(:'p','purchasing'),(:'m','management'),(:'x','salesperson'),(:'g','storekeeper'),(:'v','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1),(:'x',3),(:'g',7),(:'v',1) on conflict do nothing;
update items set unit='kg', base_unit='kg', sell_price=260, tracked=true where code in ('I-001','I-003');
update items set unit='box', base_unit='piece', sell_price=260, tracked=true where code='I-002';
select id as ia from items where code='I-001' \gset
select id as ib from items where code='I-002' \gset
select id as ic from items where code='I-003' \gset

\echo == T0 shape / defaults / re-run
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('wastage_requests','supplier_refunds','sale_returns') and c.relrowsecurity)=3);
select tt.chk('T0 limits empty, switches off', rule_val('wastage_approval_limit') is null and not rule_on('block_expired_sale') and not rule_on('em_stock_transfer') and not rule_on('em_stock_count_adjust')
  and not rule_on('em_stock_issue') and not rule_on('em_stock_production') and not rule_on('em_sale_return'));
select tt.chk('T0 four stock grants name their emergency switch', (select count(*) from grant_defs where grant_code in ('stock_count_adjust','stock_transfer','stock_issue','stock_production') and emergency_rule='em_'||grant_code)=4);
select tt.chk('T0 apply_item_patch wrapper in place', position('bos12-details' in pg_get_functiondef('public.apply_item_patch(uuid,jsonb)'::regprocedure))>0 and to_regprocedure('public._apply_item_patch_base(uuid,jsonb)') is not null);
set role authenticated; select tt.as(:'o'); select set_grant('sale_return','showroom_manager',false); reset role;
\i /home/user/My-tools/supabase/phase12.sql
select tt.chk('T0 phase12 re-runs; a removed role grant stays removed', not exists(select 1 from rule_grants where grant_code='sale_return' and role_code='showroom_manager')
  and (select count(*) from pg_proc where proname='apply_item_patch')=1);
set role authenticated; select tt.as(:'o'); select set_grant('sale_return','showroom_manager',true); reset role;

\echo == T1 items.details
set role authenticated; select tt.as(:'o');
select submit_item_change(:'ia'::uuid, '{"details":"  Made with ghee  "}'::jsonb, null);
select tt.chk('T1 owner sets details (trimmed)', (select details from items where id=:'ia'::uuid)='Made with ghee');
select submit_item_change(:'ia'::uuid, '{"details":""}'::jsonb, null);
select tt.chk('T1 empty details = cleared', (select details from items where id=:'ia'::uuid) is null);
select submit_item_change(null, '{"name_bn":"নতুন","unit":"kg","sell_price":10,"details":"d1","barcode":"BC12"}'::jsonb, null) ->> 'item_id' as nid \gset
select tt.chk('T1 new item with details; the old patch keys still work', (select details from items where id=:'nid'::uuid)='d1' and (select barcode from items where id=:'nid'::uuid)='BC12' and (select sell_price from items where id=:'nid'::uuid)=10);
select tt.chk('T1 old key-only patch leaves details alone', (submit_item_change(:'nid'::uuid, '{"sell_price":12}'::jsonb, null) is not null) and (select details from items where id=:'nid'::uuid)='d1');
select tt.err('T1 apply_item_patch is not callable by the app', 'select apply_item_patch(null, ''{}''::jsonb)', 'permission denied');

\echo == T2 items_with_cost
reset role; insert into item_costs (item_id, cost_price) values (:'ia'::uuid, 150) on conflict (item_id) do update set cost_price=150;
set role authenticated; select tt.as(:'v');
select tt.chk('T2 plain staff: nothing', (select count(*) from items_with_cost())=0 and (select count(*) from item_costs)=0);
select tt.as(:'o'); select set_user_grant(:'v'::uuid, 'view_cost');
select tt.as(:'v');
select tt.chk('T2 view_cost holder sees costs through the RPC', (select cost_price from items_with_cost() where item_id=:'ia'::uuid)=150);
select tt.chk('T2 item_costs table still closed to them', (select count(*) from item_costs)=0);
select tt.as(:'o'); select tt.chk('T2 owner too', (select count(*) from items_with_cost())>=1);
reset role;
select tt.err('T2 anon has no execute', 'set role anon; select * from items_with_cost()', 'permission denied');
reset role;

\echo == T3 photo_ok
set role authenticated;
select tt.as(:'k');
select tt.chk('T3 storekeeper (stock grants) may add STOCK photo at own loc', photo_ok('STOCK/1/a.jpg','enter'));
select tt.chk('T3 ... not at another loc', not photo_ok('STOCK/3/a.jpg','enter'));
select tt.chk('T3 ... may view STOCK photo', photo_ok('STOCK/1/a.jpg','view'));
select tt.as(:'p');
select tt.chk('T3 purchasing adds and views PURCHASE photo', photo_ok('PURCHASE/1/a.jpg','enter') and photo_ok('PURCHASE/1/a.jpg','view'));
select tt.as(:'s');
select tt.chk('T3 salesperson: no PURCHASE enter / view, no STOCK enter', not photo_ok('PURCHASE/1/a.jpg','enter') and not photo_ok('PURCHASE/1/a.jpg','view') and not photo_ok('STOCK/1/a.jpg','enter'));
select tt.chk('T3 old form-code prefix unchanged (salesperson cannot enter 04-1)', photo_ok('04-1/1/a.jpg','enter') = can_do('04-1','enter'));
select tt.as(:'o');
select tt.chk('T3 owner everywhere', photo_ok('PURCHASE/3/a.jpg','enter') and photo_ok('STOCK/7/a.jpg','view') and not photo_ok('STOCK/abc/a.jpg','view'));
reset role;

\echo == T4 emergency keys
set role authenticated; select tt.as(:'g');
select tt.err('T4 emergency for stock_transfer is off by default', $$select request_emergency('stock_transfer',7,'{}'::jsonb,'urgent need')$$, 'emergency_off');
select tt.as(:'o'); select set_rule('em_stock_transfer','true'); select tt.as(:'g');
select tt.chk('T4 switched on: the request is accepted', request_emergency('stock_transfer',7,'{}'::jsonb,'urgent need') is not null);
select tt.as(:'o'); select set_rule('em_stock_transfer',null);
reset role;

\echo == stock set-up
set role authenticated; select tt.as(:'o');
select stock_opening(:'ia'::uuid,1,100,150,null,'start');
select stock_opening(:'ib'::uuid,1,50,null,null,'start');

\echo == T5 wastage maker-checker
select coalesce(stock_wastage(:'ia'::uuid,1,2,'spoiled',null,null,null,gen_random_uuid()) ->> 'pending', '-') as pn \gset
select tt.chk('T5 no limit = direct posting (as before)', :'pn'='-' and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=98);
select set_rule('wastage_approval_limit','5');
select tt.as(:'k');
select coalesce(stock_wastage(:'ia'::uuid,1,3,'spoiled',null,null,null,gen_random_uuid()) ->> 'pending', '-') as pn \gset
select tt.chk('T5 under the limit posts at once', :'pn'='-' and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=95);
select stock_wastage(:'ia'::uuid,1,10,'spoiled','big','a/b.jpg',null,'aaaaaaaa-0000-0000-0000-000000000001') ->> 'request_id' as w1 \gset
reset role;
select tt.chk('T5 above the limit: saved as pending, stock untouched, yellow exception', (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=95
  and (select status from wastage_requests where id=:'w1'::uuid)='pending' and exists(select 1 from exceptions where flag_code='wastage_pending' and level='yellow'));
set role authenticated; select tt.as(:'k');
select tt.chk('T5 same client id again = dup, no second request', (stock_wastage(:'ia'::uuid,1,10,'spoiled','big','a/b.jpg',null,'aaaaaaaa-0000-0000-0000-000000000001') ->> 'dup')::boolean and (select count(*) from wastage_requests)=1);
select tt.err('T5 the writer (no wastage_approve grant) cannot decide', format($$select wastage_decide(%L,true,null)$$, :'w1'), 'not allowed');
select tt.chk('T5 writer sees own pending in the list, cannot decide', (select count(*) from wastage_pending(1))=1 and not (select can_decide from wastage_pending(1) limit 1));
select tt.as(:'s'); select tt.chk('T5 a salesperson sees none', (select count(*) from wastage_pending(1))=0 and (select count(*) from wastage_requests)=0);
select tt.as(:'o'); select set_user_grant(:'k'::uuid,'wastage_approve');
select tt.as(:'k');
select tt.err('T5 maker cannot approve own request even with the grant', format($$select wastage_decide(%L,true,null)$$, :'w1'), 'own_request');
select tt.as(:'m');
select tt.chk('T5 management (grant by role) sees it and can decide', (select can_decide from wastage_pending(1) limit 1));
select tt.err('T5 rejecting needs a note', format($$select wastage_decide(%L,false,null)$$, :'w1'), 'note_required');
select wastage_decide(:'w1'::uuid,true,'ok') ->> 'status' as ds \gset
select tt.chk('T5 approve posts the write-off now', :'ds'='approved' and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=85
  and (select count(*) from stock_wastage where qty=10 and created_staff='store3')=1);
select tt.chk('T5 deciding twice = dup', (wastage_decide(:'w1'::uuid,true,'ok') ->> 'dup')::boolean and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=85);
select tt.as(:'k'); select stock_wastage(:'ia'::uuid,1,6,'spoiled',null,null,null,gen_random_uuid()) ->> 'request_id' as w2 \gset
select tt.as(:'m'); select tt.chk('T5 reject keeps the stock', (wastage_decide(:'w2'::uuid,false,'no') ->> 'status')='rejected' and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=85);
select tt.as(:'k'); select stock_wastage(:'ia'::uuid,1,7,'spoiled',null,null,null,gen_random_uuid()) ->> 'request_id' as w3 \gset
select tt.chk('T5 requester can take it back', (wastage_cancel(:'w3'::uuid) ->> 'status')='cancelled');
select tt.as(:'o'); select coalesce(stock_wastage(:'ia'::uuid,1,8,'spoiled',null,null,null,gen_random_uuid()) ->> 'pending', '-') as pn \gset
select tt.chk('T5 owner is never held back', :'pn'='-' and (select qty from stock_balance where item_id=:'ia'::uuid and location_id=1)=77);
select set_rule('wastage_approval_limit',null); select set_user_grant(:'k'::uuid,'wastage_approve',null,null,false);
reset role;

\echo == T6 supplier refund
insert into suppliers (name, opening_balance) values ('Credit Sup', -500) returning id as sc \gset
set role authenticated; select tt.as(:'p');
select tt.err('T6 purchasing without supplier_pay cannot record a refund', format($$select supplier_refund(%L,1,100,'cash')$$, :'sc'), 'not allowed');
select tt.as(:'o');
select tt.chk('T6 credit list shows 500', (select credit from supplier_credits() where supplier_id=:'sc'::uuid)=500);
select tt.chk('T6 refund 200 of a 500 credit', (supplier_refund(:'sc'::uuid,1,200,'cash',null,null,null,'first',gen_random_uuid()) ->> 'balance')::numeric=-300);
select tt.err('T6 cannot refund more than the credit left', format($$select supplier_refund(%L,1,400,'cash')$$, :'sc'), 'refund_exceeds_credit');
select tt.err('T6 NaN / zero refused', format($$select supplier_refund(%L,1,'NaN'::numeric,'cash')$$, :'sc'), 'bad_amount');
select tt.err('T6 bad mode', format($$select supplier_refund(%L,1,10,'gold')$$, :'sc'), 'bad_mode');
select supplier_refund(:'sc'::uuid,1,50,'mobile','bKash','tx1','damaged',null,'bbbbbbbb-0000-0000-0000-000000000001');
select tt.chk('T6 same client id = dup, no double refund', (supplier_refund(:'sc'::uuid,1,50,'mobile','bKash','tx1','damaged',null,'bbbbbbbb-0000-0000-0000-000000000001') ->> 'dup')::boolean and (select count(*) from supplier_refunds where supplier_id=:'sc'::uuid)=2);
select tt.chk('T6 ledger shows the refunds as debits, balance -250', (select count(*) from supplier_ledger(:'sc'::uuid) where kind='refund')=2 and (select balance from supplier_ledger(:'sc'::uuid) order by at desc, pid desc nulls last limit 1)=-250);
select save_purchase(null,null,:'sc'::uuid,1,'R-1','2026-01-10'::date,'[{"description":"Gas","qty":1,"unit_cost":1000}]'::jsonb) ->> 'id' as rb \gset
select post_purchase(:'rb'::uuid);
select tt.chk('T6 open bills = balance: credit left after the refunds is what clears the new bill (1000-250)', (select sum(open_amt) from supplier_open_bills(:'sc'::uuid))=750 and tt.supbal(:'sc'::uuid)=750);
select tt.chk('T6 supplier_credits lists only suppliers that owe us', not exists(select 1 from supplier_credits() where supplier_id=:'sc'::uuid));
select tt.err('T6 a supplier we owe cannot refund', format($$select supplier_refund(%L,1,10,'cash')$$, :'sc'), 'refund_exceeds_credit');
reset role;
select id as rf1 from supplier_refunds where supplier_id=:'sc'::uuid order by id limit 1 \gset
set role authenticated; select tt.as(:'o');
select void_supplier_refund(:'rf1'::bigint,'typo');
select tt.chk('T6 void a refund: credit comes back, balance falls by it', tt.supbal(:'sc'::uuid)=550 and (select count(*) from supplier_ledger(:'sc'::uuid) where kind='refund')=1);
select tt.err('T6 void twice', format($$select void_supplier_refund(%L,'x')$$, :'rf1'), 'already void');
reset role;

\echo == T7 sale return
reset role;
insert into shelf_life_rules (item_id, value, unit) values (:'ic'::uuid, 24, 'hours');
set role authenticated; select tt.as(:'o');
select stock_production_in(:'ic'::uuid,1,30,now()-interval '30 hours',null,'old tray') ->> 'batch_id' as bt1 \gset
select stock_production_in(:'ic'::uuid,1,10,now(),null,'fresh tray') ->> 'batch_id' as bt2 \gset
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":4,"price":260,"unit":"kg"}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":540}]','01711111111','TestK','retail',null,false) ->> 'id' as sa \gset
select id as cu from customers where mobile='01711111111' \gset
select tt.chk('T7 setup: sale 1040, customer owes 500, fresh batch 6 left', tt.custbal(:'cu'::uuid)=500 and (select qty_remaining from stock_batches where id=:bt2)=6);
select tt.err('T7 salesperson has no sale_return grant', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":1}]'::jsonb,'damaged')$$, :'sa', :'ic'), 'not allowed');
select tt.as(:'m');
select tt.err('T7 reason from the list is required', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":1}]'::jsonb,null)$$, :'sa', :'ic'), 'reason_required');
select tt.err('T7 item not in the sale', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":1}]'::jsonb,'damaged')$$, :'sa', :'ia'), 'line_not_in_sale');
select tt.err('T7 more than sold', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":5}]'::jsonb,'damaged')$$, :'sa', :'ic'), 'return_exceeds_sale');
select tt.err('T7 NaN / zero qty refused', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":"NaN"}]'::jsonb,'damaged')$$, :'sa', :'ic'), 'bad_qty');
select tt.err('T7 a refund needs a mode when the due does not cover it', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":2}]'::jsonb,'damaged')$$, :'sa', :'ic'), 'refund_mode_required');
select sale_return('cccccccc-0000-0000-0000-000000000001'::uuid, :'sa'::uuid, format('[{"item_id":"%s","qty":2}]',:'ic')::jsonb, 'damaged', 'two came back', 'cash') ->> 'id' as sr1 \gset
select tt.chk('T7 value 520 -> 500 off the due, 20 refunded in cash', (select amount=520 and credit_amount=500 and refund_amount=20 and refund_mode='cash' from sale_returns where id=:'sr1'::uuid) and tt.custbal(:'cu'::uuid)=0);
select tt.chk('T7 re-sent request = dup (nothing twice)', (sale_return('cccccccc-0000-0000-0000-000000000001'::uuid, :'sa'::uuid, format('[{"item_id":"%s","qty":2}]',:'ic')::jsonb, 'damaged', 'two came back', 'cash') ->> 'dup')::boolean and (select count(*) from sale_returns)=1);
reset role;
select tt.chk('T7 stock back into the SAME batch at the sale cost: fresh batch 8, ledger row sale_return', (select qty_remaining from stock_batches where id=:bt2)=8
  and (select count(*) from stock_ledger where reason='sale_return' and ref_id=:'sr1' and batch_id=:bt2 and qty_delta=2)=1
  and (select qty from stock_balance where item_id=:'ic'::uuid and location_id=1)=38);
select tt.chk('T7 exception line for the owner', exists(select 1 from exceptions where flag_code='sale_return' and sale_id=:'sa'::uuid));
select tt.chk('T7 audit row written', exists(select 1 from audit_log where table_name='sale_returns'));
set role authenticated; select tt.as(:'o');
select tt.chk('T7 customer no longer in the dues list', not exists(select 1 from customer_dues() where id=:'cu'::uuid));
select tt.chk('T7 customer ledger shows the return as a credit', exists(select 1 from customer_ledger(:'cu'::uuid) where kind='sale_return' and credit=500));
select tt.err('T7 the sale cannot be voided while a return is live', format($$select void_sale(%L,'x')$$, :'sa'), 'sale_has_returns');
select sale_return(null, :'sa'::uuid, format('[{"item_id":"%s","qty":2}]',:'ic')::jsonb, 'damaged', null, 'mobile', 'bKash') ->> 'id' as sr2 \gset
select tt.chk('T7 second return: customer owes nothing now, so the full 520 is refunded', (select credit_amount=0 and refund_amount=520 and refund_mode='mobile' from sale_returns where id=:'sr2'::uuid));
select tt.err('T7 nothing left to return', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":0.5}]'::jsonb,'damaged',null,'cash')$$, :'sa', :'ic'), 'return_exceeds_sale');
select tt.chk('T7 sale_returns_for lists both and nothing left', (select jsonb_array_length(sale_returns_for(:'sa'::uuid)->'returns'))=2 and ((sale_returns_for(:'sa'::uuid)->'lines'->0->>'left')::numeric)=0);
select tt.chk('T7 sale_returns_for carries the discount factor, rule and balance', (sale_returns_for(:'sa'::uuid)->>'factor')::numeric=1 and (sale_returns_for(:'sa'::uuid)->>'due_first')::boolean and (sale_returns_for(:'sa'::uuid)->>'balance')::numeric=0);
select void_sale_return(:'sr2'::uuid, 'mistake'); select void_sale_return(:'sr1'::uuid, 'mistake');
reset role;
select tt.chk('T7 void returns: stock and batch back, due back', (select qty_remaining from stock_batches where id=:bt2)=6 and (select qty from stock_balance where item_id=:'ic'::uuid and location_id=1)=36 and tt.custbal(:'cu'::uuid)=500);
set role authenticated; select tt.as(:'o');
select void_sale(:'sa'::uuid, 'test');
select tt.chk('T7 with returns voided the sale can be voided; stock reversed once', (select qty_remaining from stock_batches where id=:bt2)=10 and (select qty from stock_balance where item_id=:'ic'::uuid and location_id=1)=40);
select set_rule('sale_return_due_first','false');
select tt.as(:'s'); select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":260,"unit":"kg"}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":100}]','01711111111','TestK','retail',null,false) ->> 'id' as sb \gset
select tt.as(:'m'); select sale_return(null, :'sb'::uuid, format('[{"item_id":"%s","qty":1}]',:'ic')::jsonb, 'quality', null, 'cash') ->> 'id' as sr3 \gset
select tt.chk('T7 rule off: the whole value is refunded, the due is not touched', (select credit_amount=0 and refund_amount=260 from sale_returns where id=:'sr3'::uuid));
select tt.as(:'o'); select set_rule('sale_return_due_first',null);
reset role;

\echo == T8 block expired sale
set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":25,"price":260,"unit":"kg"}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":6500}]',null,null,'retail',null,false) ->> 'id' as se \gset
reset role;
select tt.chk('T8 OFF: the sale of expired stock goes through, red exception as before', exists(select 1 from exceptions where flag_code='sold_expired' and sale_id=:'se'::uuid and level='red'));
set role authenticated; select tt.as(:'o'); select void_sale(:'se'::uuid,'t'); select set_rule('block_expired_sale','true'); select tt.as(:'s');
select qty as q_before from stock_balance where item_id=:'ic'::uuid and location_id=1 \gset
select tt.err('T8 ON: a sale that needs expired stock is refused', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":25,"price":260,"unit":"kg"}]'::jsonb,0,'[{"mode":"cash","amount":6500}]',null,null,'retail',null,false)$$, :'ic'), 'expired_stock_blocked');
select tt.chk('T8 ... and nothing was posted', (select qty from stock_balance where item_id=:'ic'::uuid and location_id=1)=:q_before::numeric);
select tt.chk('T8 ON: a sale the fresh batch can cover is fine', (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":5,"price":260,"unit":"kg"}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":1300}]',null,null,'retail',null,false) ->> 'id') is not null);
select tt.chk('T8 ON: a late-synced (offline) sale is never refused', (record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":25,"price":260,"unit":"kg"}]',:'ic')::jsonb,0,'[{"mode":"cash","amount":6500}]',null,null,'retail',null,false,now()-interval '1 hour') ->> 'id') is not null);
select tt.as(:'o'); select set_rule('block_expired_sale',null);
reset role;

\echo == T9 stock_ledger.ref_id
set role authenticated; select tt.as(:'p');
select save_purchase(null,null,:'sc'::uuid,1,'R-9','2026-01-12'::date,format('[{"item_id":"%s","qty":3,"unit":"kg","unit_cost":140}]',:'ia')::jsonb) ->> 'id' as pb \gset
select post_purchase(:'pb'::uuid);
select tt.as(:'k');
select tt.err('T9 location user cannot read ref_id directly', 'select ref_id from stock_ledger limit 1', 'permission denied');
select tt.err('T9 select * is refused too', 'select * from stock_ledger limit 1', 'permission denied');
select tt.chk('T9 other columns still readable directly', (select count(*) from (select id, item_id, qty_delta, reason, ref_type, batch_id from stock_ledger where location_id=1 limit 5) z)>0);
select tt.as(:'s'); select tt.chk('T9 stock_ledger_rows hides the purchase ref from a salesperson', (select count(*) from stock_ledger_rows(1,:'ia'::uuid) where reason='purchase_in' and ref_id is null)=1);
select tt.as(:'p');
select tt.chk('T9 ... and gives it to the purchasing person', (select count(*) from stock_ledger_rows(1,:'ia'::uuid) where reason='purchase_in' and ref_id=:'pb')=1);
reset role;

\echo == T10 audit fixes
-- daily sum against the wastage limit (stops splitting)
set role authenticated; select tt.as(:'o'); select set_rule('wastage_approval_limit','5'); select tt.as(:'k');
select coalesce(stock_wastage(:'ib'::uuid,1,3,'spoiled',null,null,null,gen_random_uuid()) ->> 'pending','-') as pn \gset
select tt.chk('T10 first 3 under the limit posts', :'pn'='-');
select coalesce(stock_wastage(:'ib'::uuid,1,3,'spoiled',null,null,null,gen_random_uuid()) ->> 'pending','-') as pn \gset
select tt.chk('T10 second 3 the same day: the SUM 6 > 5 goes pending', :'pn'='true');
select tt.as(:'o'); select set_rule('wastage_limit_daily_sum','false'); select tt.as(:'k');
select coalesce(stock_wastage(:'ib'::uuid,1,3,'spoiled',null,null,null,gen_random_uuid()) ->> 'pending','-') as pn \gset
select tt.chk('T10 sum switch off: 3 posts again', :'pn'='-');
select tt.as(:'o'); select set_rule('wastage_limit_daily_sum',null); select set_rule('wastage_approval_limit',null); select tt.as(:'k');
select tt.err('T10 wastage qty above 999,999,999 refused', format($$select stock_wastage(%L,1,1000000000,'spoiled')$$, :'ib'), 'bad_qty');
-- malformed lines
select tt.as(:'m');
select tt.err('T10 malformed item id', format($$select sale_return(null,%L,'[{"item_id":"zzz","qty":1}]'::jsonb,'damaged',null,'cash')$$, :'sa'), 'bad_item');
select tt.err('T10 malformed qty', format($$select sale_return(null,%L,'[{"item_id":"%s","qty":"abc"}]'::jsonb,'damaged',null,'cash')$$, :'sa', :'ic'), 'bad_qty');
select tt.err('T10 line that is not an object', format($$select sale_return(null,%L,'[5]'::jsonb,'damaged',null,'cash')$$, :'sa'), 'bad_item');
-- no stock trace: sold while untracked, tracked later
reset role; select id as iu from items where code='I-004' \gset
update items set unit='kg', base_unit='kg', sell_price=33.33, tracked=false where id=:'iu'::uuid;
set role authenticated; select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":3,"price":33.33,"unit":"kg"}]',:'iu')::jsonb,0,'[{"mode":"cash","amount":99.99}]',null,null,'retail',null,false) ->> 'id' as su \gset
reset role; update items set tracked=true where id=:'iu'::uuid;
set role authenticated; select tt.as(:'m');
select sale_return(null,:'su'::uuid,format('[{"item_id":"%s","qty":1}]',:'iu')::jsonb,'damaged',null,'cash') ->> 'amount' as a1 \gset
select sale_return(null,:'su'::uuid,format('[{"item_id":"%s","qty":1}]',:'iu')::jsonb,'damaged',null,'cash');
select sale_return(null,:'su'::uuid,format('[{"item_id":"%s","qty":1}]',:'iu')::jsonb,'damaged',null,'cash');
reset role;
select tt.chk('T10 partial returns add up to the line exactly (99.99), nothing left', (select sum(amount) from sale_returns where sale_id=:'su'::uuid)=99.99 and :'a1'::numeric=33.33);
select tt.chk('T10 no ledger trace: no phantom stock, yellow exception return_no_stock_trace', not exists(select 1 from stock_ledger where item_id=:'iu'::uuid) and (select count(*) from exceptions where flag_code='return_no_stock_trace' and sale_id=:'su'::uuid)>=1);
-- location-scoped view_cost
set role authenticated; select tt.as(:'o'); select set_user_grant(:'v'::uuid,'view_cost',null,null,false); select tt.as(:'v');
select tt.chk('T10 no grant: nothing', (select count(*) from items_with_cost())=0);
select tt.as(:'o'); select set_user_grant(:'v'::uuid,'view_cost',1); select tt.as(:'v');
select tt.chk('T10 location-scoped view_cost still gives the list', (select count(*) from items_with_cost())>=1);
-- backup RPCs
select tt.as(:'o');
select tt.chk('T10 owner backup of ledger and balance (with costs)', (select count(*) from backup_stock_ledger(0,10))>0 and (select count(*) from backup_stock_balance())>0 and (select count(*) from backup_stock_ledger((select max(id) from backup_stock_ledger(0,5000)),10))=0);
select tt.as(:'k'); select tt.err('T10 others cannot use the backup RPC', 'select * from backup_stock_ledger(0,10)', 'not allowed');
reset role;

select '--- FAILED: ' || count(*) filter (where not ok) || ' of ' || count(*) from tt.res;
