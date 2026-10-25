-- FRESH DB ONLY. Phase 118 tests (Step B4: stock_recon_statement, stock_sales_unmatched, factory_branch_statement, net_profit_report, recon_export_log118).
--   Build: bash tests/sql/final_build.sh <db>   (canonical order incl. phase118), then from the REPO ROOT:
--     psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase118_test.sql | grep -E "FAIL|RESULT"
--   Scenario = audit2 A3 (places 1 main centre, 2 S1, 3 S2, 6 F; hand numbers of docs/audit2/A3_real_profit.md) extended with the A5 supply moves (short receipt, return to the
--   factory, goods in transit with ageing) and a few back-dated / raw rows for the stock statement. Hand-computed numbers are written next to each check. Test data only.
\set ON_ERROR_STOP off
\set QUIET on
\set o  '00000000-0000-0000-0000-000000000001'
\set ap '00000000-0000-0000-0000-000000000008'
\set pu '00000000-0000-0000-0000-000000000021'
\set pv '00000000-0000-0000-0000-000000000022'
\set pw '00000000-0000-0000-0000-000000000023'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.eq(p_step text, p_exp numeric, p_act numeric, p_tol numeric default 0.005) returns void language plpgsql as $$
declare ok boolean := (p_exp is null and p_act is null) or (p_act is not null and p_exp is not null and abs(p_exp - p_act) <= p_tol);
begin insert into tt.res values (p_step, ok); raise notice '% % exp=% act=%', case when ok then 'PASS' else 'FAIL' end, p_step, p_exp, p_act; end $$;
create or replace function tt.err(p_step text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; insert into tt.res values (p_step, false); raise notice 'FAIL % (no error)', p_step;
exception when others then insert into tt.res values (p_step, sqlerrm like '%' || p_msg || '%'); raise notice '% % (%)', case when sqlerrm like '%' || p_msg || '%' then 'PASS' else 'FAIL' end, p_step, sqlerrm; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.iid(p_code text) returns uuid language sql stable as $$ select id from public.items where code = p_code $$;
create or replace function tt.qty(p_code text, p_loc int default 1) returns numeric language sql stable as $$
  select coalesce((select b.qty from public.stock_balance b join public.items i on i.id = b.item_id where i.code = p_code and b.location_id = p_loc), 0) $$;
create or replace function tt.avg(p_code text, p_loc int default 1) returns numeric language sql stable as $$
  select (select b.avg_cost from public.stock_balance b join public.items i on i.id = b.item_id where i.code = p_code and b.location_id = p_loc) $$;
-- one row of a statement: tt.row(statement jsonb, location, item code) -> the jsonb row
create or replace function tt.row(p_st jsonb, p_loc int, p_code text) returns jsonb language sql stable as $$
  select r from jsonb_array_elements(p_st -> 'rows') r where (r ->> 'location_id')::int = p_loc and r ->> 'item_code' = p_code $$;
create or replace function tt.n(p_j jsonb, p_key text) returns numeric language sql immutable as $$ select (p_j ->> p_key)::numeric $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

\echo == A3 setup
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@a3.app','{"full_name":"Owner"}'),(:'ap','approver@a3.app','{"full_name":"Approver"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ap','recipe_approver') on conflict do nothing;
insert into user_locations values (:'ap',6) on conflict do nothing;
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('RM-F','Flour','Flour','kg','kg','raw_material',true,0,false,null),('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false,null),
 ('FG-A','Sweet A','Sweet A','kg','kg','finished_good',true,100,true,'sweet_kg'),
 ('RS-B','Item B','Item B','pc','pc','resale',true,90,true,'cake_pc'),
 ('RS-C','Item C nocost','Item C nocost','pc','pc','resale',true,100,true,'cake_pc') on conflict do nothing;
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select stock_opening(tt.iid('RM-F'),6,100,40) is not null as a1 \gset
select stock_opening(tt.iid('RM-S'),6,100,20) is not null as a2 \gset
select stock_opening(tt.iid('RS-B'),2,10,50) is not null as a3 \gset
select stock_opening(tt.iid('RS-C'),2,5,null) is not null as a4 \gset
select acct_opening('[{"code":"1110","debit":10000,"location_id":1},{"code":"3100","credit":10000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a_on \gset
select set_rule('accounting_autopost','true') is null as a_on2 \gset
select (recipe_save(null, tt.iid('FG-A'), 10, 'kg', 'A v1', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-F'),'qty',6,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',3,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rc \gset
select loc_cost_cfg_set(6,'recipe') is null as lc \gset
select recipe_cost_component_set(:'rc'::uuid,'labour','per_batch',100,null,null,'labour',gen_random_uuid()) is not null as cc \gset
select tt.as(:'ap'); select recipe_approve(:'rc'::uuid,'ok') is not null as rap \gset
select tt.as(:'o');
select production_post(6, :'rc'::uuid, 2, gen_random_uuid()) as pj \gset
select tt.eq('P0 factory unit cost of A = (300+100)/10', 40, tt.avg('FG-A',6), 0.0005);
select (stock_transfer(6,2,tt.iid('FG-A'),10,null,'t1')->>'id')::uuid as t1 \gset
select stock_receive_transfer(:'t1'::uuid, 10, null) is not null as r1 \gset
select (stock_transfer(6,3,tt.iid('FG-A'),10,null,'t2')->>'id')::uuid as t2 \gset
select stock_receive_transfer(:'t2'::uuid, 10, null) is not null as r2 \gset
select tt.eq('P0 S1 stock of A 10 @ 40', 40, tt.avg('FG-A',2), 0.0005);
select tt.eq('P0 S2 stock of A 10 @ 40', 40, tt.avg('FG-A',3), 0.0005);

\echo == B4 supply moves (A5 style) on top of the A3 setup
select tt.as(:'o');
select production_post(6, :'rc'::uuid, 1) is not null as pj3 \gset
select tt.eq('P3 F stock of A: 20 made and sent, third batch +10 = 10', 10, tt.qty('FG-A',6), 0.0005);
select (stock_transfer(6,2,tt.iid('FG-A'),4,null,'t3 short')->>'id')::uuid as t3 \gset
select stock_receive_transfer(:'t3'::uuid, 3, 'one kg missing') is not null as r3 \gset
select (stock_transfer(6,3,tt.iid('FG-A'),3,null,'t4 in transit')->>'id')::uuid as t4 \gset
select (stock_transfer(2,6,tt.iid('FG-A'),2,null,'t5 return to factory')->>'id')::uuid as t5 \gset
select stock_receive_transfer(:'t5'::uuid, null, null) is not null as r5 \gset
select (stock_transfer(6,3,tt.iid('FG-A'),1,null,'t6 old transit')->>'id')::uuid as t6 \gset
update stock_transfers set sent_at = now() - interval '50 hours' where id = :'t6'::uuid;
select tt.eq('P4 S1 stock of A before sales: 10 + 3 - 2 = 11', 11, tt.qty('FG-A',2), 0.0005);
select tt.eq('P4 F stock of A: 30 - 10 - 10 - 4 - 3 + 2 - 1 = 4', 4, tt.qty('FG-A',6), 0.0005);
\echo == A3 sales / return / wastage / fee / expenses
-- S1 sale1: A 5 kg x 100 = 500, discount 50 -> 450 cash
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":5,"price":100}]',tt.iid('FG-A'))::jsonb,50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,false) as s1 \gset
select (:'s1'::jsonb->>'id')::uuid as sale1 \gset
select tt.eq('X1 sale1 total (500-50)', 450, (:'s1'::jsonb->>'total')::numeric);
-- S1 sale2: B 4 x 90 = 360 by card
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":4,"price":90}]',tt.iid('RS-B'))::jsonb,0,'[{"mode":"card","amount":360}]',null,null,'retail',null,false) as s2 \gset
-- S1 sale3: C 2 x 100 = 200 cash, C has no cost anywhere
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":2,"price":100}]',tt.iid('RS-C'))::jsonb,0,'[{"mode":"cash","amount":200}]',null,null,'retail',null,false) as s3 \gset
-- S2 sale4: A 8 kg x 100 = 800, discount 160 (20 %) -> 640 cash
select record_sale2(gen_random_uuid(),3,format('[{"item_id":"%s","qty":8,"price":100}]',tt.iid('FG-A'))::jsonb,160,'[{"mode":"cash","amount":640}]',null,null,'retail',null,false) as s4 \gset
select tt.eq('X1 sale4 total (800-160)', 640, (:'s4'::jsonb->>'total')::numeric);
-- return of 1 kg A from sale1: refund = 1 x 100 x 450/500 = 90
select sale_return(gen_random_uuid(), :'sale1'::uuid, format('[{"item_id":"%s","qty":1}]',tt.iid('FG-A'))::jsonb, 'damaged','a3 return','cash') as rt \gset
select tt.eq('X2 return amount keeps the discount share (90, not 100)', 90, (:'rt'::jsonb->>'amount')::numeric);
-- wastage 1 kg A at S2 (cost 40)
select stock_wastage(tt.iid('FG-A'),3,1,'spoiled','a3 waste') is not null as wg \gset
-- card settlement S1: gross 360 fee 7.20 (2 %)
select card_settle(2, tt.today(), 360, 7.2, 'a3 batch', gen_random_uuid()) is not null as cs \gset
-- salary: S1 300 (booked to showroom 1), factory 200 ; sheet 02-2 is what the P&L reads
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('02-2',2,8101,tt.today(),'approved','{"pay":[{"name":"S1 Clerk - Clerk","due":300}]}','[]',:'o','st'),
 ('02-2',6,8102,tt.today(),'approved','{"pay":[{"name":"F Cook - Cook","due":200}]}','[]',:'o','st');
-- operating costs: S1 rent 150 (quick expense, head rent), S2 delivery 40 (head transport)
select quick_expense_add(2, tt.today(), 'rent', 'landlord', 150, 'cash', true, 'a3 rent S1', gen_random_uuid()) is not null as q1 \gset
select quick_expense_add(3, tt.today(), 'transport', 'rider', 40, 'cash', true, 'a3 delivery S2', gen_random_uuid()) is not null as q2 \gset

\echo == A3 shared cost bills (electricity headcount 2:1, internet fixed 70:30, admin share of S1 -> main centre)
select cost_source_save(null,'electricity','Utility Co','shared',null,array[2,3],'monthly',date_trunc('month',tt.today())::date,'a3',gen_random_uuid())->>'id' as es \gset
select cost_rule_save(:'es'::bigint,'headcount',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom","value":2},{"location_id":3,"dest":"showroom","value":1}]'::jsonb,'a3',gen_random_uuid())->>'id' as er \gset
select cost_rule_approve(:'er'::bigint,'ok') is not null as era \gset
select cost_bill_add(:'es'::bigint,'month',date_trunc('month',tt.today())::date,600,'cash','E-1',tt.today(),false,null,null,gen_random_uuid()) as eb \gset
select cost_source_save(null,'internet','ISP','shared',null,array[2,3],'monthly',date_trunc('month',tt.today())::date,'a3',gen_random_uuid())->>'id' as is_ \gset
select cost_rule_save(:'is_'::bigint,'fixed_percent',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom","value":70},{"location_id":3,"dest":"showroom","value":30}]'::jsonb,'a3',gen_random_uuid())->>'id' as ir \gset
select cost_rule_approve(:'ir'::bigint,'ok') is not null as ira \gset
select cost_bill_add(:'is_'::bigint,'month',date_trunc('month',tt.today())::date,300,'cash','I-1',tt.today(),false,null,null,gen_random_uuid()) as ib \gset
select cost_source_save(null,'other','Accounts software','separate','admin',array[2],'monthly',date_trunc('month',tt.today())::date,'a3 admin',gen_random_uuid())->>'id' as ads \gset
select cost_bill_add(:'ads'::bigint,'month',date_trunc('month',tt.today())::date,120,'cash','A-1',tt.today(),false,null,null,gen_random_uuid()) as ab \gset
select tt.eq('B1 electricity shares sum to bill', 600, (select sum(amount) from cost_bill_shares where bill_id=(:'eb'::jsonb->>'id')::bigint and active));
select tt.eq('B1 electricity S1 share 2/3 of 600', 400, (select amount from cost_bill_shares where bill_id=(:'eb'::jsonb->>'id')::bigint and active and location_id=2));
select tt.eq('B1 internet S1 share 70 % of 300', 210, (select amount from cost_bill_shares where bill_id=(:'ib'::jsonb->>'id')::bigint and active and location_id=2));
select tt.err('B2 sales-share allocation method is not offered', format($$select cost_rule_save(%s,'sales_share',date_trunc('month',tt.today())::date,'[{"location_id":2,"dest":"showroom"},{"location_id":3,"dest":"showroom"}]'::jsonb,'x',gen_random_uuid())$$,:'es'), 'bad_value');
\echo == A3 post to books
select acct_post_pending(false) is not null as pp \gset

\echo == users for the permission checks
insert into auth.users (id,email,raw_user_meta_data) values (:'pu','pu@b4.app','{"full_name":"Viewer One"}'),(:'pv','pv@b4.app','{"full_name":"Viewer Two"}'),(:'pw','pw@b4.app','{"full_name":"Viewer Three"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'pu','salesperson'),(:'pv','salesperson'),(:'pw','salesperson') on conflict do nothing;
insert into user_locations values (:'pu',2),(:'pv',2),(:'pw',2),(:'pw',3) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'pu'::uuid,'view_stock_recon') is null as ga \gset
select set_user_grant(:'pu'::uuid,'view_branch_statement') is null as gb \gset
select set_user_grant(:'pw'::uuid,'view_stock_recon',3) is null as gc \gset

\echo == T0 objects
select tt.chk('T0 three grants, two rules, two advisor rows, five RPCs exist',
  (select count(*) from grant_defs where grant_code in ('view_stock_recon','view_branch_statement','view_net_profit')) = 3
  and (select count(*) from rules where key in ('profit_variable_heads','branch_stmt_ageing_hours')) = 2
  and (select count(*) from setup_rec_defs81 where phase = '118') = 2
  and to_regprocedure('public.stock_recon_statement(date,date,integer,uuid,text,integer)') is not null
  and to_regprocedure('public.stock_sales_unmatched(date,date,integer,uuid,integer)') is not null
  and to_regprocedure('public.factory_branch_statement(date,date,integer,uuid,text,integer)') is not null
  and to_regprocedure('public.net_profit_report(date,date,integer,text)') is not null
  and to_regprocedure('public.recon_export_log118(text,integer,jsonb)') is not null);
select tt.chk('T0 internals are closed to the browser, RPCs closed to anon',
  not has_function_privilege('authenticated','public._rc118_buckets(date,date,integer[],uuid,text)','execute')
  and not has_function_privilege('authenticated','public._rc118_locs(text,integer)','execute')
  and not has_function_privilege('anon','public.stock_recon_statement(date,date,integer,uuid,text,integer)','execute')
  and not has_function_privilege('anon','public.net_profit_report(date,date,integer,text)','execute')
  and has_function_privilege('authenticated','public.net_profit_report(date,date,integer,text)','execute'));
select tt.chk('T0 every new function carries the bos118 tag',
  (select count(*) from pg_proc p where p.proname in ('stock_recon_statement','stock_sales_unmatched','factory_branch_statement','net_profit_report','_rc118_buckets','_rc118_gap','_rc118_locs') and p.prosrc like '%bos118%') = 7);
select tt.chk('T0 the reports are read-only (stable) functions',
  (select bool_and(p.provolatile = 's') from pg_proc p where p.proname in ('stock_recon_statement','stock_sales_unmatched','factory_branch_statement','net_profit_report')));
select tt.err('T0 bad period refused', $$select stock_recon_statement(tt.today(), tt.today()-1)$$, 'bad_period');

\echo == V1 stock reconciliation statement (A2 G1), period today-3 .. today, owner
select tt.as(:'o');
select stock_recon_statement(tt.today()-3, tt.today()) as st \gset
select tt.row(:'st'::jsonb, 2, 'FG-A') as r_s1 \gset
select tt.row(:'st'::jsonb, 3, 'FG-A') as r_s2 \gset
select tt.row(:'st'::jsonb, 6, 'FG-A') as r_f \gset
select tt.row(:'st'::jsonb, 6, 'RM-F') as r_rf \gset
-- S1 A: 0 + 0 + 0 + 13 (10 + 3 received) + 1 (customer return) - 0 - 5 sold - 0 - 2 (returned to F) = 7
select tt.eq('V1 S1 A transfer_in 13', 13, tt.n(:'r_s1'::jsonb,'transfer_in_qty'));
select tt.eq('V1 S1 A give-back 1', 1, tt.n(:'r_s1'::jsonb,'give_back_qty'));
select tt.eq('V1 S1 A sales 5', 5, tt.n(:'r_s1'::jsonb,'sales_qty'));
select tt.eq('V1 S1 A transfers out 2 (all returned to the sender)', 2, tt.n(:'r_s1'::jsonb,'transfer_out_qty'));
select tt.eq('V1 S1 A returned_to_sender 2', 2, tt.n(:'r_s1'::jsonb,'returned_to_sender_qty'));
select tt.eq('V1 S1 A closing 7 = 0+13+1-5-2', 7, tt.n(:'r_s1'::jsonb,'closing_qty'));
select tt.eq('V1 S1 A cached balance 7 and variance 0', 0, tt.n(:'r_s1'::jsonb,'variance_qty'));
select tt.chk('V1 S1 A has no flag', jsonb_array_length(:'r_s1'::jsonb->'flags') = 0);
-- S2 A: received 10 (the 3 + 1 kg in transit are not in anybody's balance), sold 8, wasted 1 -> 1
select tt.eq('V1 S2 A transfer_in 10', 10, tt.n(:'r_s2'::jsonb,'transfer_in_qty'));
select tt.eq('V1 S2 A sales 8, wastage 1, closing 1', 1, tt.n(:'r_s2'::jsonb,'closing_qty') + (tt.n(:'r_s2'::jsonb,'sales_qty') - 8) + (tt.n(:'r_s2'::jsonb,'wastage_qty') - 1));
-- F A: production 30 + received back 2 - sent out 28 (10 + 10 + 4 + 3 + 1) = 4
select tt.eq('V1 F A production 30', 30, tt.n(:'r_f'::jsonb,'production_qty'));
select tt.eq('V1 F A transfers out 28', 28, tt.n(:'r_f'::jsonb,'transfer_out_qty'));
select tt.eq('V1 F A transfer in 2, closing 4', 4, tt.n(:'r_f'::jsonb,'closing_qty') + (tt.n(:'r_f'::jsonb,'transfer_in_qty') - 2));
-- F flour: opening row of today 100 is an adjustment bucket, 3 batches x 6 kg used = 18, closing 82
select tt.eq('V1 F flour adjustments 100 (the opening row), used 18, closing 82', 82, tt.n(:'r_rf'::jsonb,'closing_qty') + (tt.n(:'r_rf'::jsonb,'adjustments_qty') - 100) + (tt.n(:'r_rf'::jsonb,'used_qty') - 18));
select tt.chk('V1 identity holds on every row (opening + in - out +/- adj = closing)', not exists (
  select 1 from jsonb_array_elements(:'st'::jsonb->'rows') r where abs(tt.n(r,'opening_qty') + tt.n(r,'production_qty') + tt.n(r,'purchases_qty') + tt.n(r,'transfer_in_qty') + tt.n(r,'give_back_qty')
    - tt.n(r,'used_qty') - tt.n(r,'sales_qty') - tt.n(r,'wastage_qty') - tt.n(r,'transit_loss_qty') - tt.n(r,'transfer_out_qty') + tt.n(r,'adjustments_qty') - tt.n(r,'closing_qty')) > 0.0005));
select tt.chk('V1 clean ledger: no variance flag anywhere', (:'st'::jsonb->'summary'->>'with_variance')::int = 0 and (:'st'::jsonb->'summary'->>'unbalanced')::int = 0);
select tt.eq('V1 S1 A value: avg cost 40, closing value 7 x 40 = 280', 280, tt.n(:'r_s1'::jsonb,'closing_value'));
-- an empty future window: opening = the ending balance, no movement
select stock_recon_statement(tt.today()+1, tt.today()+2, 2, tt.iid('FG-A')) as stf \gset
select tt.row(:'stf'::jsonb, 2, 'FG-A') as r_fut \gset
select tt.eq('V1 future window opening = 7, closing = 7, movements 0', 7, tt.n(:'r_fut'::jsonb,'opening_qty'));
select tt.eq('V1 future window closing 7', 7, tt.n(:'r_fut'::jsonb,'closing_qty'));
select tt.eq('V1 future window has no sales/transfers', 0, tt.n(:'r_fut'::jsonb,'sales_qty') + tt.n(:'r_fut'::jsonb,'transfer_in_qty') + tt.n(:'r_fut'::jsonb,'transfer_out_qty'));

\echo == V2 sales vs ledger (A2 G2): baseline is clean
select stock_sales_unmatched(tt.today()-3, tt.today()) as um0 \gset
select tt.eq('V2 baseline: every A3 sale line matches the ledger (0 unmatched)', 0, (:'um0'::jsonb->>'total')::numeric);

\echo == V3 factory-to-branch statement (A5 GAP-1), period today-3 .. today, owner
select factory_branch_statement(tt.today()-3, tt.today(), null, tt.iid('FG-A')) as fb \gset
select tt.row(:'fb'::jsonb, 2, 'FG-A') as b_s1 \gset
select tt.row(:'fb'::jsonb, 3, 'FG-A') as b_s2 \gset
select tt.row(:'fb'::jsonb, 6, 'FG-A') as b_f \gset
-- S1: sent 10 + 4 = 14, received 10 + 3 = 13, short 1 (7.14 %), returned 2, sold 5, remaining 7; values at 40: 560 / 520 / 40 / 280
select tt.eq('V3 S1 sent 14', 14, tt.n(:'b_s1'::jsonb,'sent_in_qty'));
select tt.eq('V3 S1 received 13', 13, tt.n(:'b_s1'::jsonb,'received_qty'));
select tt.eq('V3 S1 short 1', 1, tt.n(:'b_s1'::jsonb,'short_qty'));
select tt.eq('V3 S1 short pct = 1 / 14 = 7.14', 7.14, tt.n(:'b_s1'::jsonb,'short_pct'), 0.005);
select tt.eq('V3 S1 returned to the factory 2', 2, tt.n(:'b_s1'::jsonb,'returned_qty'));
select tt.eq('V3 S1 sold 5', 5, tt.n(:'b_s1'::jsonb,'sold_qty'));
select tt.eq('V3 S1 remaining 7', 7, tt.n(:'b_s1'::jsonb,'remaining_qty'));
select tt.eq('V3 S1 ledger received equals transfers received (mismatch 0)', 0, tt.n(:'b_s1'::jsonb,'receive_mismatch_qty'));
select tt.chk('V3 S1 flagged short only', :'b_s1'::jsonb->'flags' = '["short"]'::jsonb);
select tt.eq('V3 S1 sent value 14 x 40 = 560', 560, tt.n(:'b_s1'::jsonb,'sent_value'));
select tt.eq('V3 S1 received value 13 x 40 = 520', 520, tt.n(:'b_s1'::jsonb,'received_value'));
select tt.eq('V3 S1 short value 40', 40, tt.n(:'b_s1'::jsonb,'short_value'));
select tt.eq('V3 S1 remaining value 7 x 40 = 280', 280, tt.n(:'b_s1'::jsonb,'remaining_value'));
-- S2: sent 10 + 3 + 1 = 14, received 10, in transit 4 (3 young + 1 of 50 h), sold 8, wasted 1, remaining 1
select tt.eq('V3 S2 sent 14', 14, tt.n(:'b_s2'::jsonb,'sent_in_qty'));
select tt.eq('V3 S2 received 10', 10, tt.n(:'b_s2'::jsonb,'received_qty'));
select tt.eq('V3 S2 in transit 4', 4, tt.n(:'b_s2'::jsonb,'in_transit_qty'));
select tt.eq('V3 S2 ageing 0-24 h = 3', 3, tt.n(:'b_s2'::jsonb,'in_transit_age_0_qty'));
select tt.eq('V3 S2 ageing 1-3 days = 1', 1, tt.n(:'b_s2'::jsonb,'in_transit_age_1_qty'));
select tt.eq('V3 S2 ageing over 3 days = 0', 0, tt.n(:'b_s2'::jsonb,'in_transit_age_2_qty'));
select tt.eq('V3 S2 oldest in transit about 50 h', 50, tt.n(:'b_s2'::jsonb,'oldest_transit_hours'), 0.5);
select tt.eq('V3 S2 wasted 1, sold 8, remaining 1', 1, tt.n(:'b_s2'::jsonb,'remaining_qty') + (tt.n(:'b_s2'::jsonb,'sold_qty') - 8) + (tt.n(:'b_s2'::jsonb,'wasted_qty') - 1));
select tt.eq('V3 S2 in transit value 4 x 40 = 160', 160, tt.n(:'b_s2'::jsonb,'in_transit_value'));
-- F: sent out 28, received back 2, remaining 4
select tt.eq('V3 F sent out 28', 28, tt.n(:'b_f'::jsonb,'sent_out_qty'));
select tt.eq('V3 F received (the return) 2', 2, tt.n(:'b_f'::jsonb,'received_qty'));
select tt.eq('V3 F remaining 4', 4, tt.n(:'b_f'::jsonb,'remaining_qty'));
select tt.eq('V3 by-location S1: 2 transfers sent, 1 short', 3, (select (x->>'transfers_sent')::int + (x->>'transfers_short')::int from jsonb_array_elements(:'fb'::jsonb->'by_location') x where (x->>'location_id')::int = 2));
select tt.eq('V3 by-location S2: 3 sent, 2 in transit, sent value 560, in transit value 160', 3 + 2 + 560 + 160,
  (select (x->>'transfers_sent')::int + (x->>'transfers_in_transit')::int + (x->>'sent_value')::numeric + (x->>'in_transit_value')::numeric from jsonb_array_elements(:'fb'::jsonb->'by_location') x where (x->>'location_id')::int = 3));
-- ageing boundaries are a rule: 12,40 puts the 50 h transfer over the second boundary
select set_rule('branch_stmt_ageing_hours','"12,40"') is null as ar \gset
select factory_branch_statement(tt.today()-3, tt.today(), 3, tt.iid('FG-A')) as fb2 \gset
select tt.row(:'fb2'::jsonb, 3, 'FG-A') as b_s2b \gset
select tt.eq('V3 rule 12,40: over-boundary = 1, young = 3, middle = 0', 1 * 100 + 3 * 10 + 0, tt.n(:'b_s2b'::jsonb,'in_transit_age_2_qty') * 100 + tt.n(:'b_s2b'::jsonb,'in_transit_age_0_qty') * 10 + tt.n(:'b_s2b'::jsonb,'in_transit_age_1_qty'));
select tt.chk('V3 rule 12,40: flag transit_old', :'b_s2b'::jsonb->'flags' ? 'transit_old');
select tt.chk('V3 ageing hours reported back', :'fb2'::jsonb->'ageing_hours' = '[12, 40]'::jsonb);
select set_rule('branch_stmt_ageing_hours','"24,72"') is null as ar2 \gset

\echo == V4 net profit report (A3), month window, owner. Switch of attribution: no rule for the shared bills yet
select tt.as(:'o');
select net_profit_report(date_trunc('month', tt.today())::date, (date_trunc('month', tt.today()) + interval '1 month - 1 day')::date) as np0 \gset
select x as n_s1 from jsonb_array_elements(:'np0'::jsonb->'branches') x where (x->>'location_id')::int = 2 \gset
select x as n_s2 from jsonb_array_elements(:'np0'::jsonb->'branches') x where (x->>'location_id')::int = 3 \gset
select x as n_f from jsonb_array_elements(:'np0'::jsonb->'branches') x where (x->>'location_id')::int = 6 \gset
-- hand numbers (A3): S1 net sales 920 (500-50 discount -90 return +360 +200), costed 720, uncosted 200, cogs 360, GP 360, card fee 7.20, CM 352.80
select tt.eq('V4 S1 net sales 920 (after discount and return)', 920, tt.n(:'n_s1'::jsonb,'net_sales'));
select tt.eq('V4 S1 costed sales 720 and uncosted 200 shown apart', 720 + 200, tt.n(:'n_s1'::jsonb,'costed_sales') + tt.n(:'n_s1'::jsonb,'uncosted_sales'));
select tt.eq('V4 S1 cogs 360', 360, tt.n(:'n_s1'::jsonb,'cogs'));
select tt.eq('V4 S1 gross profit (costed part) 360', 360, tt.n(:'n_s1'::jsonb,'gross_profit'));
select tt.eq('V4 S1 card fee 7.20', 7.20, tt.n(:'n_s1'::jsonb,'card_fees'));
select tt.eq('V4 S1 contribution margin 352.80', 352.80, tt.n(:'n_s1'::jsonb,'contribution_margin'));
select tt.eq('V4 S1 contribution pct = 352.80 / 720 = 49.00', 49.00, tt.n(:'n_s1'::jsonb,'contribution_pct'), 0.005);
-- S1 overheads before attribution: rent 150 + salary 300 = 450, no shared bill charged -> net -97.20
select tt.eq('V4 S1 other expenses 150 (rent), salary 300, shared 0', 450, tt.n(:'n_s1'::jsonb,'other_expenses') + tt.n(:'n_s1'::jsonb,'salary') + tt.n(:'n_s1'::jsonb,'shared_costs'));
select tt.eq('V4 S1 net profit before attribution = 352.80 - 450 = -97.20', -97.20, tt.n(:'n_s1'::jsonb,'net_profit'));
select tt.chk('V4 S1 flagged: sales with unknown cost', :'n_s1'::jsonb->'gaps' ? 'uncosted_sales' and not (:'n_s1'::jsonb->>'complete')::boolean);
-- S2: GP 320, wastage 40, delivery (head transport) 40 -> CM 240; no salary sheet at S2
select tt.eq('V4 S2 gross profit 320', 320, tt.n(:'n_s2'::jsonb,'gross_profit'));
select tt.eq('V4 S2 wastage at cost 40', 40, tt.n(:'n_s2'::jsonb,'wastage_cost'));
select tt.eq('V4 S2 variable expense (transport) 40', 40, tt.n(:'n_s2'::jsonb,'variable_expenses'));
select tt.eq('V4 S2 contribution margin 240', 240, tt.n(:'n_s2'::jsonb,'contribution_margin'));
select tt.eq('V4 S2 other expenses 0 (delivery is variable, not overhead)', 0, tt.n(:'n_s2'::jsonb,'other_expenses'));
select tt.chk('V4 S2 flagged: no salary sheet', :'n_s2'::jsonb->'gaps' ? 'salary_not_recorded');
select tt.eq('V4 F net sales 0, salary 200, net profit -200', -200, tt.n(:'n_f'::jsonb,'net_profit'));
select tt.eq('V4 company before attribution: shared bills 600 + 300 + 120 = 1020 not charged to any place', 1020, tt.n(:'np0'::jsonb->'company','unallocated_shared_costs'));
select tt.chk('V4 report says what is included and what is not',
  jsonb_array_length(:'np0'::jsonb->'included') >= 8 and :'np0'::jsonb->'not_included' ? 'profit_on_sales_with_unknown_cost' and :'np0'::jsonb->'not_included' ? 'payroll_app_payments');
select tt.chk('V4 variable heads are shown back', :'np0'::jsonb->'variable_heads' = '["transport"]'::jsonb);

\echo == V4b after the cost attribution settings (A3 part 2): shares S1 610, S2 290, main centre 120
select cost_attrib_main_set(1, date_trunc('month',tt.today())::date, 'a3 main centre', gen_random_uuid()) is not null as m1 \gset
select cost_attrib_set(2, null, 'showroom', date_trunc('month',tt.today())::date, 'a3', gen_random_uuid()) is not null as c1 \gset
select cost_attrib_set(3, null, 'showroom', date_trunc('month',tt.today())::date, 'a3', gen_random_uuid()) is not null as c2 \gset
select cost_attrib_set(2, 'other', 'main_centre', date_trunc('month',tt.today())::date, 'a3 admin to head office', gen_random_uuid()) is not null as c3 \gset
select net_profit_report(date_trunc('month', tt.today())::date, (date_trunc('month', tt.today()) + interval '1 month - 1 day')::date) as np1 \gset
select x as m_s1 from jsonb_array_elements(:'np1'::jsonb->'branches') x where (x->>'location_id')::int = 2 \gset
select x as m_s2 from jsonb_array_elements(:'np1'::jsonb->'branches') x where (x->>'location_id')::int = 3 \gset
select x as m_m from jsonb_array_elements(:'np1'::jsonb->'branches') x where (x->>'location_id')::int = 1 \gset
select tt.eq('V4b S1 shared bills 400 + 210 = 610', 610, tt.n(:'m_s1'::jsonb,'shared_costs'));
select tt.eq('V4b S1 net profit after overhead = 352.80 - 300 - 150 - 610 = -707.20', -707.20, tt.n(:'m_s1'::jsonb,'net_profit'));
select tt.eq('V4b S2 shared bills 200 + 90 = 290, net profit 240 - 290 = -50', -50, tt.n(:'m_s2'::jsonb,'net_profit'));
select tt.eq('V4b main centre carries the admin bill 120: net profit -120', -120, tt.n(:'m_m'::jsonb,'net_profit'));
select tt.eq('V4b company contribution margin 592.80', 592.80, tt.n(:'np1'::jsonb->'company','contribution_margin'));
select tt.eq('V4b company net profit (cost-unknown sales left out) = -1077.20', -1077.20, tt.n(:'np1'::jsonb->'company','net_profit'));
select tt.eq('V4b nothing left unallocated', 0, tt.n(:'np1'::jsonb->'company','unallocated_shared_costs'));
select tt.eq('V4b company uncosted sales 200 stay outside profit', 200, tt.n(:'np1'::jsonb->'company','uncosted_sales'));
-- shared bills are pro-rated by days in a shorter window
select net_profit_report(tt.today(), tt.today(), 2) as np_day \gset
select tt.eq('V4c one-day window: S1 shared costs = 610 / days in the month', round(610.0 / extract(day from (date_trunc('month', tt.today()) + interval '1 month - 1 day')), 2), (:'np_day'::jsonb->'branches'->0->>'shared_costs')::numeric, 0.01);
select net_profit_report((date_trunc('month', tt.today()) - interval '2 month')::date, (date_trunc('month', tt.today()) - interval '1 month' - interval '1 day')::date, 2) as np_old \gset
select tt.eq('V4c a window with no activity charges no shared bill', 0, jsonb_array_length(:'np_old'::jsonb->'branches'));
-- product view
select x as p_a from jsonb_array_elements(:'np1'::jsonb->'product_branch') x where (x->>'location_id')::int = 2 and x->>'item_code' = 'FG-A' \gset
select x as p_b from jsonb_array_elements(:'np1'::jsonb->'product_branch') x where (x->>'location_id')::int = 2 and x->>'item_code' = 'RS-B' \gset
select x as p_c from jsonb_array_elements(:'np1'::jsonb->'product_branch') x where (x->>'location_id')::int = 2 and x->>'item_code' = 'RS-C' \gset
-- A at S1: net 360 (450 - 90), cogs 160, GP 200; share of branch net 360 / 920; variable 7.20 x share = 2.82; overhead 1060 x share = 414.78 -> -217.60
select tt.eq('V4d S1 product A net sales 360, cogs 160, gross profit 200', 360 + 160 + 200, tt.n(:'p_a'::jsonb,'net_sales') + tt.n(:'p_a'::jsonb,'cogs') + tt.n(:'p_a'::jsonb,'gross_profit'));
select tt.eq('V4d S1 product A net profit after overhead -217.60', -217.60, tt.n(:'p_a'::jsonb,'net_profit'), 0.01);
select tt.eq('V4d S1 product B net profit 160 - 2.82 - 414.78 = -257.60', -257.60, tt.n(:'p_b'::jsonb,'net_profit'), 0.01);
select tt.chk('V4d S1 product C (no cost known): uncosted 200, cost_complete false, gross profit 0 - never a 100 % margin',
  tt.n(:'p_c'::jsonb,'uncosted_sales') = 200 and tt.n(:'p_c'::jsonb,'gross_profit') = 0 and not (:'p_c'::jsonb->>'cost_complete')::boolean);
select tt.eq('V4d product profits of S1 add up to the S1 branch profit -707.20',
  -707.20, (select sum((x->>'net_profit')::numeric) from jsonb_array_elements(:'np1'::jsonb->'product_branch') x where (x->>'location_id')::int = 2), 0.05);
select tt.eq('V4d product profits of S2 add up to the S2 branch profit -50',
  -50, (select sum((x->>'net_profit')::numeric) from jsonb_array_elements(:'np1'::jsonb->'product_branch') x where (x->>'location_id')::int = 3), 0.05);
select tt.eq('V4d product contributions of S1 and S2 add up to the branch contributions 352.80 + 240',
  592.80, (select sum((x->>'contribution_margin')::numeric) from jsonb_array_elements(:'np1'::jsonb->'product_branch') x where (x->>'location_id')::int in (2,3)), 0.05);
-- A over both showrooms: net 360 + 640 = 1000, gross profit 200 + 320 = 520, wastage 40
select x as p_all from jsonb_array_elements(:'np1'::jsonb->'products') x where x->>'item_code' = 'FG-A' \gset
select tt.eq('V4d product A across places: net 1000, gross profit 520, wastage 40, qty 12', 1000 + 520 + 40 + 12,
  tt.n(:'p_all'::jsonb,'net_sales') + tt.n(:'p_all'::jsonb,'gross_profit') + tt.n(:'p_all'::jsonb,'wastage_cost') + tt.n(:'p_all'::jsonb,'qty'));
select tt.eq('V4d product A across places: net profit -217.60 + -50 = -267.60', -267.60, tt.n(:'p_all'::jsonb,'net_profit'), 0.02);
-- category filter: only cake_pc items (B and C)
select net_profit_report(date_trunc('month', tt.today())::date, (date_trunc('month', tt.today()) + interval '1 month - 1 day')::date, 2, 'cake_pc') as np_cat \gset
select tt.eq('V4e category filter cake_pc at S1: net sales 360 + 200 = 560', 560, (:'np_cat'::jsonb->'branches'->0->>'net_sales')::numeric);

\echo == V5 permissions and cost secrecy
-- no grant at all
select tt.as(:'pv');
select tt.err('V5 no grant: stock statement refused', $$select stock_recon_statement(tt.today(), tt.today())$$, 'not allowed');
select tt.err('V5 no grant: branch statement refused', $$select factory_branch_statement(tt.today(), tt.today())$$, 'not allowed');
select tt.err('V5 no grant: net profit refused', $$select net_profit_report(tt.today(), tt.today())$$, 'not allowed');
select tt.err('V5 no grant: unmatched list refused', $$select stock_sales_unmatched(tt.today(), tt.today())$$, 'not allowed');
-- grant without any cost right: quantities yes, cost keys no, own place only
select tt.as(:'pu');
select stock_recon_statement(tt.today()-3, tt.today()) as pst \gset
select tt.chk('V5 grant holder at place 2 sees only place 2', :'pst'::jsonb->'location_ids' = '[2]'::jsonb and not exists (select 1 from jsonb_array_elements(:'pst'::jsonb->'rows') r where (r->>'location_id')::int <> 2) and jsonb_array_length(:'pst'::jsonb->'rows') > 0);
select tt.chk('V5 without a cost right the statement has no cost or value key', not (:'pst'::jsonb->>'cost_visible')::boolean
  and not exists (select 1 from jsonb_array_elements(:'pst'::jsonb->'rows') r where r ? 'avg_cost' or r ? 'closing_value'));
select factory_branch_statement(tt.today()-3, tt.today()) as pfb \gset
select tt.chk('V5 branch statement without a cost right: quantities only', not (:'pfb'::jsonb->>'cost_visible')::boolean
  and not exists (select 1 from jsonb_array_elements(:'pfb'::jsonb->'rows') r where r ? 'sent_value' or r ? 'remaining_value' or r ? 'avg_cost' or r ? 'in_transit_value')
  and not exists (select 1 from jsonb_array_elements(:'pfb'::jsonb->'by_location') r where r ? 'sent_value' or r ? 'short_value')
  and exists (select 1 from jsonb_array_elements(:'pfb'::jsonb->'rows') r where r ? 'sent_in_qty'));
select tt.err('V5 the statement grant does not open the profit report', $$select net_profit_report(tt.today(), tt.today())$$, 'not allowed');
select tt.err('V5 place 3 is not visible to a place-2 user', $$select stock_recon_statement(tt.today(), tt.today(), 3)$$, 'not allowed');
-- cost right added
select tt.as(:'o');
select set_user_grant(:'pu'::uuid,'view_cost') is null as gcost \gset
select tt.as(:'pu');
select stock_recon_statement(tt.today()-3, tt.today(), 2, tt.iid('FG-A')) as pst2 \gset
select tt.row(:'pst2'::jsonb, 2, 'FG-A') as pr2 \gset
select tt.chk('V5 with view_cost the value keys appear (closing value 280)', (:'pst2'::jsonb->>'cost_visible')::boolean and tt.n(:'pr2'::jsonb,'closing_value') = 280 and tt.n(:'pr2'::jsonb,'avg_cost') = 40);
select tt.err('V5 view_cost alone does not open the profit report', $$select net_profit_report(tt.today(), tt.today())$$, 'not allowed');
select tt.as(:'o');
select set_user_grant(:'pu'::uuid,'view_net_profit') is null as gnp \gset
select tt.as(:'pu');
select net_profit_report(date_trunc('month', tt.today())::date, (date_trunc('month', tt.today()) + interval '1 month - 1 day')::date) as pnp \gset
select tt.chk('V5 view_net_profit + view_cost: profit report for place 2 only', :'pnp'::jsonb->'location_ids' = '[2]'::jsonb and jsonb_array_length(:'pnp'::jsonb->'branches') = 1
  and ((:'pnp'::jsonb->'branches'->0->>'location_id')::int = 2) and tt.n(:'pnp'::jsonb->'branches'->0,'net_profit') = -707.20);
select tt.as(:'o');
select set_user_grant(:'pu'::uuid,'view_cost',null,null,false) is null as gcost_off \gset
select tt.as(:'pu');
select tt.err('V5 view_net_profit without a cost right is refused (profit is cost-derived)', $$select net_profit_report(tt.today(), tt.today())$$, 'not allowed');
-- a grant given for one place only
select tt.as(:'pw');
select stock_recon_statement(tt.today()-3, tt.today()) as wst \gset
select tt.chk('V5 grant for place 3 only: the user (assigned to 2 and 3) sees place 3 only', :'wst'::jsonb->'location_ids' = '[3]'::jsonb);
select tt.err('V5 ... and place 2 is refused', $$select stock_recon_statement(tt.today(), tt.today(), 2)$$, 'not allowed');

\echo == V6 back-dated rows: opening is the balance before the window (item RC-X at place 2)
select tt.as(:'o');
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('RC-X','Item X','Item X','pc','pc','resale',true,10,true,'rc') on conflict do nothing;
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at) values
 (tt.iid('RC-X'),2, 10, 7, 'purchase_in', 'test', 'x1', now() - interval '5 days'),
 (tt.iid('RC-X'),2, -1, 7, 'wastage',     'test', 'x2', now() - interval '3 days'),
 (tt.iid('RC-X'),2,  5, 7, 'purchase_in', 'test', 'x3', now()),
 (tt.iid('RC-X'),2, -3, 7, 'sale_out',    'test', 'x4', now()),
 (tt.iid('RC-X'),2, -1, 7, 'count_adjust','test', 'x5', now());
select tt.eq('X0 cached balance of RC-X = 10 + 5 - 1 - 3 - 1 = 10', 10, tt.qty('RC-X',2), 0.0005);
-- window yesterday..today: opening 10 - 1 = 9; purchases 5; sales 3; adjustments -1; closing 10
select stock_recon_statement(tt.today()-1, tt.today(), 2, tt.iid('RC-X')) as xa \gset
select tt.row(:'xa'::jsonb, 2, 'RC-X') as ra \gset
select tt.eq('V6 opening 9 (the 5-day-old purchase less the 3-day-old wastage)', 9, tt.n(:'ra'::jsonb,'opening_qty'));
select tt.eq('V6 purchases 5', 5, tt.n(:'ra'::jsonb,'purchases_qty'));
select tt.eq('V6 sales 3', 3, tt.n(:'ra'::jsonb,'sales_qty'));
select tt.eq('V6 adjustments -1', -1, tt.n(:'ra'::jsonb,'adjustments_qty'));
select tt.eq('V6 closing 10 = 9 + 5 - 3 - 1', 10, tt.n(:'ra'::jsonb,'closing_qty'));
select tt.chk('V6 flagged adjusted (a count adjustment sits in the window), no variance', :'ra'::jsonb->'flags' = '["adjusted"]'::jsonb);
-- window 4 days ago .. 2 days ago: opening 10, wastage 1, closing 9
select stock_recon_statement(tt.today()-4, tt.today()-2, 2, tt.iid('RC-X')) as xb \gset
select tt.row(:'xb'::jsonb, 2, 'RC-X') as rb \gset
select tt.eq('V6 old window: opening 10, wastage 1, closing 9', 10 * 100 + 1 * 10 + 9, tt.n(:'rb'::jsonb,'opening_qty') * 100 + tt.n(:'rb'::jsonb,'wastage_qty') * 10 + tt.n(:'rb'::jsonb,'closing_qty'));
select tt.eq('V6 old window: closing 9 differs from today balance 10 but variance is ledger vs balance = 0', 0, tt.n(:'rb'::jsonb,'variance_qty'));
select tt.eq('V6 value: closing 10 x 7 = 70', 70, tt.n(:'ra'::jsonb,'closing_value'));
-- cached balance out of step with the ledger -> variance flag
update stock_balance set qty = qty + 1 where item_id = tt.iid('RC-X') and location_id = 2;
select stock_recon_statement(tt.today()-1, tt.today(), 2, tt.iid('RC-X')) as xc \gset
select tt.row(:'xc'::jsonb, 2, 'RC-X') as rc_ \gset
select tt.eq('V6 balance tampered by +1: variance -1 (ledger 10, cached 11)', -1, tt.n(:'rc_'::jsonb,'variance_qty'));
select tt.chk('V6 ... flagged variance and counted in the summary', :'rc_'::jsonb->'flags' ? 'variance' and (:'xc'::jsonb->'summary'->>'with_variance')::int = 1);
select stock_reconcile(true) is not null as fixed \gset
select stock_recon_statement(tt.today()-1, tt.today(), 2, tt.iid('RC-X')) as xd \gset
select tt.eq('V6 after stock_reconcile(true) the variance is gone', 0, tt.n(tt.row(:'xd'::jsonb, 2, 'RC-X'),'variance_qty'));

\echo == V7 sales lines that did not leave stock as sold (A2 G2)
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,category) values
 ('RC-U','Untracked','Untracked','pc','pc','resale',false,10,true,'rc'),
 ('RC-K','No conversion','No conversion','pc','kg','resale',true,10,true,'rc'),
 ('RC-R','Raw sale item','Raw sale item','kg','kg','resale',true,10,true,'rc') on conflict do nothing;
select stock_opening(tt.iid('RC-K'),2,10,5) is not null as ok1 \gset
select stock_opening(tt.iid('RC-R'),2,20,5) is not null as ok2 \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":2,"price":10}]',tt.iid('RC-U'))::jsonb,0,'[{"mode":"cash","amount":20}]',null,null,'retail',null,false) is not null as s1 \gset
select record_sale2(gen_random_uuid(),2,format('[{"item_id":"%s","qty":3,"price":10}]',tt.iid('RC-K'))::jsonb,0,'[{"mode":"cash","amount":30}]',null,null,'retail',null,false) is not null as s2 \gset
-- raw sale rows with the stock trigger switched off: one posts nothing, one posts 1 of 3
alter table sales disable trigger sales_stock_out;
insert into sales (location_id, receipt, sale_date, lines, subtotal, total, pay_mode, created_by)
  select 2, coalesce(max(receipt),0) + 1, tt.today(), format('[{"item_id":"%s","qty":3,"price":10,"unit":"kg"}]', tt.iid('RC-R'))::jsonb, 30, 30, 'cash', :'o'::uuid from sales where location_id = 2;
insert into sales (location_id, receipt, sale_date, lines, subtotal, total, pay_mode, created_by)
  select 2, coalesce(max(receipt),0) + 1, tt.today(), format('[{"item_id":"%s","qty":3,"price":10,"unit":"kg"}]', tt.iid('RC-R'))::jsonb, 30, 30, 'cash', :'o'::uuid from sales where location_id = 2;
alter table sales enable trigger sales_stock_out;
select id as raw2 from sales where location_id = 2 and lines @> format('[{"item_id":"%s"}]', tt.iid('RC-R'))::jsonb order by receipt desc limit 1 \gset
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at) values
 (tt.iid('RC-R'),2,-1,5,'sale_out','sale',:'raw2',now());
-- over-posted: one more kg leaves stock against the sale of 4 x B
select id as sale_b from sales where location_id = 2 and lines @> format('[{"item_id":"%s"}]', tt.iid('RS-B'))::jsonb limit 1 \gset
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type, ref_id, made_at) values
 (tt.iid('RS-B'),2,-1,50,'sale_out','sale',:'sale_b',now());
select stock_sales_unmatched(tt.today()-3, tt.today()) as um1 \gset
select tt.eq('V7 five kinds, one line each: untracked 1, unit_unknown 1, not_posted 1, short_posted 1, over_posted 1', 5,
  (select count(*) from jsonb_each_text(:'um1'::jsonb->'counts') where value::int = 1));
select tt.eq('V7 total unmatched lines 5', 5, (:'um1'::jsonb->>'total')::numeric);
select tt.eq('V7 short_posted: sold 3 kg, ledger 1, diff 2', 2, (select (r->>'diff_qty')::numeric from jsonb_array_elements(:'um1'::jsonb->'rows') r where r->>'kind' = 'short_posted'));
select tt.eq('V7 over_posted: sold 4, ledger 5, diff -1', -1, (select (r->>'diff_qty')::numeric from jsonb_array_elements(:'um1'::jsonb->'rows') r where r->>'kind' = 'over_posted'));
select tt.eq('V7 not_posted: sold 3, ledger 0', 3, (select (r->>'sold_base_qty')::numeric from jsonb_array_elements(:'um1'::jsonb->'rows') r where r->>'kind' = 'not_posted'));
select tt.chk('V7 unit_unknown names the item and keeps the stock at 10 kg', (select r->>'item_code' from jsonb_array_elements(:'um1'::jsonb->'rows') r where r->>'kind' = 'unit_unknown') = 'RC-K' and tt.qty('RC-K',2) = 10);
select tt.chk('V7 the statement carries the same counts', stock_recon_statement(tt.today()-3, tt.today())->'sales_unmatched' = :'um1'::jsonb->'counts');
select stock_sales_unmatched(tt.today()-3, tt.today(), null, tt.iid('RS-B')) as um2 \gset
select tt.eq('V7 item filter: only the over_posted line of B', 1, (:'um2'::jsonb->>'total')::numeric);
-- voided sales are not compared
select stock_sales_unmatched(tt.today()-3, tt.today(), 3) as um3 \gset
select tt.eq('V7 place 3 has no sales lines: 0', 0, (:'um3'::jsonb->>'total')::numeric);

\echo == V8 CSV export audit
select tt.as(:'o');
select count(*) as al0 from audit_log where table_name = 'recon_report' \gset
select recon_export_log118('net_profit_product', 12, '{"from":"x"}'::jsonb) is null as lg \gset
select tt.eq('V8 owner export is written to the audit log', :al0 + 1, (select count(*) from audit_log where table_name = 'recon_report' and record_id = 'net_profit_product'));
select tt.err('V8 unknown report key refused', $$select recon_export_log118('nope', 1, '{}'::jsonb)$$, 'unknown_report');
select tt.as(:'pu');
select tt.err('V8 a grant holder without export_data cannot log a CSV export', $$select recon_export_log118('stock_recon', 1, '{}'::jsonb)$$, 'not allowed');
select tt.as(:'o');
select set_user_grant(:'pu'::uuid,'export_data') is null as gex \gset
select tt.as(:'pu');
select recon_export_log118('stock_recon', 3, '{}'::jsonb) is null as lg2 \gset
select tt.chk('V8 grant + export_data: allowed for the report the grant covers', (select count(*) from audit_log where table_name = 'recon_report' and record_id = 'stock_recon') = 1);
select tt.err('V8 ... but not for a report another grant covers', $$select recon_export_log118('factory_branch_statement', 1, '{}'::jsonb)$$, 'unknown_report');
select tt.err('V8 ... and not for the profit report', $$select recon_export_log118('net_profit_branch', 1, '{}'::jsonb)$$, 'not allowed');
select tt.as(:'o');
-- the shortage is resolved as a loss: ledger gets +1 in and -1 loss; remaining stays 7; the cross check still holds
select transit_short_resolve(:'t3'::uuid, 'lost on the way')->>'short' as sr \gset
select factory_branch_statement(tt.today()-3, tt.today(), 2, tt.iid('FG-A')) as fb3 \gset
select tt.row(:'fb3'::jsonb, 2, 'FG-A') as b_s1c \gset
select tt.eq('V3 after resolving the short: transit_loss 1, ledger received 14, mismatch 0, remaining 7', 14 + 1 + 0 + 7,
  tt.n(:'b_s1c'::jsonb,'ledger_received_qty') + tt.n(:'b_s1c'::jsonb,'transit_loss_qty') + tt.n(:'b_s1c'::jsonb,'receive_mismatch_qty') + tt.n(:'b_s1c'::jsonb,'remaining_qty'));
select stock_recon_statement(tt.today(), tt.today(), 2, tt.iid('FG-A')) as st3 \gset
select tt.row(:'st3'::jsonb, 2, 'FG-A') as r_s1c \gset
select tt.eq('V3 stock statement after the resolve: transit loss 1 is its own column, closing still 7', 7 + 1, tt.n(:'r_s1c'::jsonb,'closing_qty') + tt.n(:'r_s1c'::jsonb,'transit_loss_qty'));
-- resolved short counts as a loss in the profit report (transit loss at ledger cost 40 at S1)
select tt.as(:'o');
select net_profit_report(date_trunc('month', tt.today())::date, (date_trunc('month', tt.today()) + interval '1 month - 1 day')::date, 2) as np2 \gset
select tt.eq('V9 after the resolve the transit loss of product A at S1 = 1 kg x 40 = 40', 40, (select (x->>'wastage_cost')::numeric from jsonb_array_elements(:'np2'::jsonb->'product_branch') x where x->>'item_code' = 'FG-A'));

\echo == V10 paste twice: nothing changes
select (select count(*) from rules) as rn0, (select count(*) from setup_rec_defs81) as sn0, (select count(*) from grant_defs) as gn0,
       (select md5(string_agg(md5(pg_get_functiondef(p.oid)), ',' order by p.proname)) from pg_proc p where p.proname in ('stock_recon_statement','stock_sales_unmatched','factory_branch_statement','net_profit_report','recon_export_log118','_rc118_buckets','_rc118_gap','_rc118_gap_summary','_rc118_locs')) as fa0 \gset
\i supabase/phase118.sql
select tt.chk('V10 paste twice: no function body, rule, advisor row or grant row changes',
  :'fa0' = (select md5(string_agg(md5(pg_get_functiondef(p.oid)), ',' order by p.proname)) from pg_proc p where p.proname in ('stock_recon_statement','stock_sales_unmatched','factory_branch_statement','net_profit_report','recon_export_log118','_rc118_buckets','_rc118_gap','_rc118_gap_summary','_rc118_locs'))
  and (select count(*) from rules) = :rn0 and (select count(*) from setup_rec_defs81) = :sn0 and (select count(*) from grant_defs) = :gn0);
select tt.chk('V10 the owner-typed rule values survive a paste (ageing default untouched)', rule_val('branch_stmt_ageing_hours') = '"24,72"'::jsonb and rule_val('profit_variable_heads') = '"transport"'::jsonb);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
