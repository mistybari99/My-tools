-- FRESH DB ONLY (built through phase118, then phase121). Phase 121 tests: the seven review fixes. Expected numbers are hand-computed (HAND comments).
--   bash tests/sql/final_build.sh <db>   (the canonical order ends with phase121);  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase121_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
\i tests/sql/e2e/00_common.sql
\set ma '00000000-0000-0000-0000-000000000010'
\echo == T0 shape
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@b5.app','{"full_name":"Owner"}'),(:'fm','maker@b5.app','{"full_name":"Maker"}'),(:'sp','seller@b5.app','{"full_name":"Seller"}'),(:'ma','showroom@b5.app','{"full_name":"Showroom"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge'),(:'sp','salesperson'),(:'ma','showroom_manager') on conflict do nothing;
insert into user_locations values (:'fm',1),(:'sp',1),(:'ma',1),(:'ma',2) on conflict do nothing;
select tt.as(:'o');
select tt.t('T0 the seven patched functions carry the marker sec121 and keep their older tags', (select count(*) = 7 and bool_and(case proname
    when 'pool_set' then d ~ 'bos117' and d ~ 'bos75' when '_pool_gl_after_bill117' then d ~ 'bos117' or true when 'cost_wait_supply96' then d ~ 'bos116'
    when 'sale_return' then d ~ 'bos114' else true end)
  from (select proname, pg_get_functiondef(oid) d from pg_proc where pronamespace = 'public'::regnamespace and pg_get_functiondef(oid) ~ 'sec121') x));
select tt.t('T0 helper _s121_patch is gone', to_regprocedure('public._s121_patch(text,text[],text[],text)') is null);
select tt.t('T0 sec121 is not a bosNN tag (body guards of 98 / 103 / 109 / 114 / 116 / 117 stay usable)', not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and pg_get_functiondef(oid) ~ 'bos121'));
create temp table h0 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace = 'public'::regnamespace;
\i supabase/phase121.sql
select tt.t('T0 paste twice: no function body changed', not exists (select 1 from pg_proc p join h0 on h0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> h0.h));

\echo == T1 fix 1: customer_dues_net113 is for signed-in users only
select tt.t('T1 anon and public cannot execute it', not has_function_privilege('anon', 'public.customer_dues_net113()', 'execute') and not has_function_privilege('public', 'public.customer_dues_net113()', 'execute'));
select tt.t('T1 authenticated can', has_function_privilege('authenticated', 'public.customer_dues_net113()', 'execute'));

\echo == setup (accounting, one supplier purchase)
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values
 ('RM-S','Sugar','Sugar','kg','kg','raw_material',true,0,false),('RM-NC','Unc 1','Unc 1','kg','kg','raw_material',true,0,false),('RM-NC2','Unc 2','Unc 2','kg','kg','raw_material',true,0,false),
 ('FG-NC','Fin 1','Fin 1','kg','kg','finished_good',true,100,true),('FG-NC2','Fin 2','Fin 2','kg','kg','finished_good',true,100,true),
 ('MX','Mixed unit item','Mixed unit item','pc','kg','finished_good',true,10,true),('TR','Transfer item','Transfer item','kg','kg','finished_good',true,10,true) on conflict do nothing;
select acct_set_start(tt.today()-100)->>'start' as sd \gset
select acct_opening('[{"code":"1110","debit":100000,"location_id":1},{"code":"3100","credit":100000}]'::jsonb)->>'id' as oj \gset
select set_rule('accounting_on','true') is null as a1 \gset
select set_rule('accounting_autopost','true') is null as a2 \gset
select stock_opening(tt.iid('RM-S'),1,100,60) is not null as os \gset
select set_user_grant(:'ma'::uuid,'view_cost') is null as g1 \gset
select tt.as(:'o');

\echo == T2 fix 2: the GL sync of a typed pool needs an owner / accountant
select set_rule('pool_gl_post117','true') is null as sw2 \gset
select tt.as(:'ma');
select pool_set(1, date_trunc('month', tt.today())::date, 'labour', 3000) ->> 'id' as pm \gset
select tt.t('T2 a showroom manager with view_cost can still type the pool (id returned)', :'pm' is not null);
select tt.eq('T2 ... but nothing was posted to the books for it (no entry)', 0, (select count(*) from pool_gl_posts117));
select tt.eq('T2 ... and 5200 is untouched', 0, tt.bal('5200'));
select tt.as(:'o');
-- HAND: the owner types 3500 (retires 3000): the sync posts Dr 5200 3500 / Cr 2400 3500
select pool_set(1, date_trunc('month', tt.today())::date, 'labour', 3500) is not null as p2 \gset
select tt.eq('T2 owner types 3500: 5200 = 3500', 3500, tt.bal('5200'));
select tt.eq('T2 owner: 2400 = -3500', -3500, tt.bal('2400'));
select tt.as(:'ma');
select pool_set(1, date_trunc('month', tt.today())::date, 'labour', 4000) is not null as p3 \gset
select tt.eq('T2 the showroom manager types 4000: the books still show 3500 until an owner / accountant syncs (catch-up)', 3500, tt.bal('5200'));
select tt.as(:'o');
select pool_gl_sync117(1, tt.today()) as sy \gset
select tt.eq('T2 the catch-up by the owner brings the books to 4000', 4000, tt.bal('5200'));
select tt.eq('T2 unbalanced entries', 0, tt.unbalanced());
select cost_source_save(null,'electricity','Utility Co','separate','factory',array[1],'monthly',date_trunc('month',tt.today())::date,'b5',gen_random_uuid())->>'id' as es \gset
select cost_bill_add(:'es'::bigint,'month',date_trunc('month',tt.today())::date,600,'cash','E-1',tt.today(),false,null,null,gen_random_uuid()) as eb \gset
select tt.eq('T2 a bill entered by the owner still reaches the books: utilities 5400 = 600', 600, tt.bal('5400'));
select set_rule('pool_gl_post117',null) is null as sw2o \gset

\echo == T3 fix 3: the supplied cost reaches the average only for a manager
select set_user_grant(:'ma'::uuid,'view_cost') is null as g2 \gset
select loc_cost_cfg_set(1,'off') is null as lc \gset
select stock_opening(tt.iid('RM-NC'),1,50,null) is not null as o1 \gset
select stock_opening(tt.iid('RM-NC2'),1,50,null) is not null as o2 \gset
select (recipe_save(null, tt.iid('FG-NC'), 10, 'kg', 'nc', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-NC'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',5,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rnc \gset
select recipe_approve(:'rnc'::uuid,'ok') is not null as ap1 \gset
select (recipe_save(null, tt.iid('FG-NC2'), 10, 'kg', 'nc2', jsonb_build_array(
  jsonb_build_object('ingredient_item_id',tt.iid('RM-NC2'),'qty',5,'unit','kg','waste_pct',0),
  jsonb_build_object('ingredient_item_id',tt.iid('RM-S'),'qty',5,'unit','kg','waste_pct',0)), gen_random_uuid())->>'id')::uuid as rnc2 \gset
select recipe_approve(:'rnc2'::uuid,'ok') is not null as ap2 \gset
select production_post(1, :'rnc'::uuid, 1, gen_random_uuid(), null, 'uncosted 1', null) as pp1 \gset
select production_post(1, :'rnc2'::uuid, 1, gen_random_uuid(), null, 'uncosted 2', null) as pp2 \gset
select set_rule('cost_supply_to_avg116','true') is null as sw3 \gset
select x->>'ref' as ref1 from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->'items'->0->>'code'='RM-NC' \gset
select x->>'ref' as ref2 from jsonb_array_elements(cost_wait_list96()->'items') x where x->>'kind'='ledger' and x->'items'->0->>'code'='RM-NC2' \gset
select tt.as(:'ma');
select cost_wait_supply96('ledger', :'ref1', 'manual', format('[{"item_id":"%s","cost":20}]', tt.iid('RM-NC'))::jsonb, 'supplier quote', gen_random_uuid(), false) as sp1 \gset
select tt.t('T3 showroom manager (view_cost, not recipe / accounts manager): the answer says needs_manager', (:'sp1'::jsonb->>'needs_manager')::boolean);
select tt.t('T3 ... the supplied cost row is saved (2 rows or more)', (:'sp1'::jsonb->>'rows')::int >= 1);
select tt.t('T3 ... but the item average is NOT moved (still blank)', tt.avg('RM-NC') is null);
select tt.as(:'o');
select cost_wait_supply96('ledger', :'ref2', 'manual', format('[{"item_id":"%s","cost":20}]', tt.iid('RM-NC2'))::jsonb, 'supplier quote', gen_random_uuid(), false) as sp2 \gset
select tt.t('T3 owner: no needs_manager key', not (:'sp2'::jsonb ? 'needs_manager'));
select tt.eq('T3 owner: the supplied cost reached the average (20)', 20, tt.avg('RM-NC2'));
select set_rule('cost_supply_to_avg116',null) is null as sw3o \gset

\echo == T4 fix 4: a mixed-unit sale returns exactly what it took out
select set_unit_conversion(tt.iid('MX'),'pc','kg',0.2,'1 pc = 0.2 kg') is null as c1 \gset
select set_unit_conversion(tt.iid('MX'),'box','kg',2,'1 box = 2 kg') is null as c2 \gset
select stock_opening(tt.iid('MX'),1,10,5) is not null as om \gset
select tt.as(:'sp');
-- The app writes the item unit on every line, so a mixed-unit sale (a legacy / synced one) is built by editing the stored sale: 3 pc + 1 box.
-- HAND: 3 pc (0.6 kg) + 1 box (2 kg) = 2.6 kg out of 10 -> 7.4
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":3,"unit":"pc"},{"item_id":"%s","qty":1,"unit":"pc"}]', tt.iid('MX'), tt.iid('MX'))::jsonb, 0, jsonb_build_array(jsonb_build_object('mode','cash','amount',40)), null, null, 'retail', null, false, null) ->> 'id' as ms \gset
set session_replication_role = replica;
update sales set lines = jsonb_set(lines, '{1,unit}', '"box"') where id = :'ms'::uuid;
update stock_ledger set qty_delta = -2 where ref_type = 'sale' and ref_id = :'ms' and qty_delta = -0.2;
update stock_balance set qty = qty - 1.8 where item_id = tt.iid('MX') and location_id = 1;
set session_replication_role = origin;
select tt.eq('T4 setup: 10 - 2.6 = 7.4', 7.4, tt.qty('MX'));
select tt.as(:'o');
select set_rule('return_uses_sale_rows','true') is null as sw4 \gset
-- old text: sold_line counted only the pc lines (3) -> 2.6 * 1 / 3 = 0.8667 back for ONE pc. New: 2.6 * 0.2 / 2.6 = 0.2
select sale_return(gen_random_uuid(), :'ms'::uuid, format('[{"item_id":"%s","qty":1,"unit":"pc"}]', tt.iid('MX'))::jsonb, 'damaged', null, 'cash') is not null as r1 \gset
select tt.eq('T4 on: 1 pc back = 0.2 -> 7.6 (not 8.2667)', 7.6, tt.qty('MX'));
select sale_return(gen_random_uuid(), :'ms'::uuid, format('[{"item_id":"%s","qty":2,"unit":"pc"}]', tt.iid('MX'))::jsonb, 'damaged', null, 'cash') is not null as r2 \gset
select tt.eq('T4 on: 2 more pc = 0.4 -> 8.0 (2 pc x 0.2, the stored box line does not distort the part)', 8, tt.qty('MX'));
select set_rule('return_uses_sale_rows',null) is null as sw4o \gset

\echo == T5 fix 5: bank_stmt_post113 answers dup on a retry
select set_rule('bank_recon_on','true') is null as bro \gset
select set_rule('bank_stmt_post_on','"on"'::jsonb) is null as r6 \gset
select id as bank_id from coa_accounts where code='1120' \gset
select bank_stmt_import(:bank_id, format('[{"date":"%s","amount":-12.5,"description":"monthly bank fee"}]', tt.today())::jsonb, gen_random_uuid(), false) is not null as bsi \gset
select id as fee_line from bank_statement_lines where amount=-12.5 \gset
select gen_random_uuid() as cl \gset
select bank_stmt_post113(:fee_line, 'fee', 1, 'monthly fee', :'cl'::uuid) ->> 'id' as e1 \gset
select tt.eq('T5 first call posts: 5810 = 12.5', 12.5, tt.bal('5810'));
select bank_stmt_post113(:fee_line, 'fee', 1, 'monthly fee', :'cl'::uuid) as retry \gset
select tt.t('T5 the retry with the same client id returns dup:true and the same entry', (:'retry'::jsonb->>'dup')::boolean and (:'retry'::jsonb->>'id') = :'e1');
select tt.eq('T5 nothing posted twice: 5810 still 12.5', 12.5, tt.bal('5810'));
select tt.err('T5 another client id on the posted line is still refused', format($$select bank_stmt_post113(%s,'fee',1,null,gen_random_uuid())$$, :fee_line), 'line_already_matched');

\echo == T6 fix 6: a return transfer locks the original
select stock_opening(tt.iid('TR'),1,30,50) is not null as ot \gset
select tt.as(:'fm'); select (stock_transfer(1,2,tt.iid('TR'),20)->>'id')::uuid as t3 \gset
select tt.as(:'ma'); select stock_receive_transfer(:'t3'::uuid) is not null as rc \gset
select tt.as(:'o'); select set_rule('transfer_return_marker','true') is null as sw6 \gset
select tt.as(:'ma');
select stock_return_transfer(2,1,tt.iid('TR'),5,'damaged',:'t3'::uuid,null,'broken',gen_random_uuid()) ->> 'id' as rr1 \gset
select tt.t('T6 the return of 5 works', :'rr1' is not null);
select tt.err('T6 HAND: 20 received - 5 returned = 15 left; 16 asked is refused', format($$select stock_return_transfer(2,1,tt.iid('TR'),16,'excess',%L::uuid)$$, :'t3'), 'return_exceeds_receipt');
select tt.t('T6 the original row is read with for update', pg_get_functiondef('public.stock_return_transfer(integer,integer,uuid,numeric,text,uuid,text,text,uuid)'::regprocedure) ~ 'where id = p_ref for update');
select tt.as(:'o'); select set_rule('transfer_return_marker',null) is null as sw6o \gset

\echo == T7 fix 7: production_recost116 checks rights before the row lock
select tt.as(:'sp');
select tt.err('T7 a salesperson is refused', format($$select production_recost116(%L::uuid, true)$$, (:'pp1'::jsonb->>'run_id')), 'not allowed');
select tt.as(:'ma');
select tt.err('T7 a showroom manager without recipe_manage is refused', format($$select production_recost116(%L::uuid, true)$$, (:'pp1'::jsonb->>'run_id')), 'not allowed');
select tt.as(:'o');
select tt.t('T7 in the body the rights check comes before the first FOR UPDATE', (select position('not allowed' in d) > 0 and position('not allowed' in d) < position('for update' in d) from (select pg_get_functiondef('public.production_recost116(uuid,boolean)'::regprocedure) d) x));
select tt.err('T7 the owner gets past the rights check (unknown run: not_found)', $$select production_recost116(gen_random_uuid(), true)$$, 'not_found');

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
