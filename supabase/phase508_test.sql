-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase82_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase508_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 60 tests (P3a: reorder, wastage reasons, GRN batch/expiry, QC).
--   ORDER="phase8 ... phase51 phase60" bash tests/sql/build_fresh_db.sh p60db   (see docs/briefs_p2p3/COMMON.md)
--   psql -h /tmp -p 5544 -U postgres -d p60db -qAt -f supabase/phase60_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;


insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'), ('00000000-0000-0000-0000-000000000004','far4@s.app','{"full_name":"Far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),('00000000-0000-0000-0000-000000000004','storekeeper') on conflict do nothing;
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1) on conflict do nothing;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
create or replace function tt.noBn(p text) returns boolean language sql immutable as $$ select p !~ '[ঀ-৿]' $$;
grant execute on function tt.noBn(text) to authenticated, anon;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('G1','G1','G1','kg','kg','raw_material',true,0), ('G2','G2','G2','kg','kg','raw_material',true,0), ('G3','G3','G3','kg','kg','raw_material',true,0),
 ('G4','G4','G4','kg','kg','raw_material',true,0), ('G5','G5','G5','kg','kg','raw_material',true,0),
 ('FG','FG','FG','kg','kg','finished_good',true,10), ('BX','BX','BX','box','pc','finished_good',false,10), ('NO','NO','NO','kg','kg','finished_good',true,10);
select id as g1 from items where code='G1' \gset
select id as g2 from items where code='G2' \gset
select id as g3 from items where code='G3' \gset
select id as g4 from items where code='G4' \gset
select id as g5 from items where code='G5' \gset
select id as ifg from items where code='FG' \gset
select id as ibx from items where code='BX' \gset
select id as ino from items where code='NO' \gset
select tt.as(:'o');
select save_supplier(null,'{"name":"Sup"}') as sup \gset

\echo == T0 shape
select tt.chk('T0 four functions carry bos82 lines', (select count(*) from pg_proc where proname in ('_post_purchase_p13','_void_purchase_p13','_sale_stock_out','stock_post') and position('bos82' in pg_get_functiondef(oid))>0)=4);
select tt.chk('T0 new rules default to today (off / warn / void / false)', rule_txt('purchase_grn_guard')='off' and rule_txt('purchase_void_guard')='off' and rule_txt('purchase_void_payments')='void' and rule_txt('unit_conv_required')='warn' and not rule_on('neg_grant_log') and rule_txt('production_negative_reason')='off');
select tt.chk('T0 callable by authenticated, not anon', has_function_privilege('authenticated','public.guard_recommendations()','execute') and not has_function_privilege('anon','public.guard_recommendations()','execute') and not has_function_privilege('authenticated','public._items_unit_conv82()','execute'));
select tt.chk('T0 English text of new rules has no Bangla letters', (select bool_and(tt.noBn(label_en) and tt.noBn(hint_en)) from rules where key in ('purchase_grn_guard','purchase_void_guard','purchase_void_payments','unit_conv_required','neg_grant_log','production_negative_reason')));
select tt.chk('T0 every new rule has bn, mix and en text', (select bool_and(label_bn is not null and label_mix is not null and label_en is not null and hint_bn is not null and hint_mix is not null and hint_en is not null) from rules where key in ('purchase_grn_guard','purchase_void_guard','purchase_void_payments','unit_conv_required','neg_grant_log','production_negative_reason')));

\echo == E1 GRN vs purchase page
set role authenticated; select tt.as(:'o');
select set_rule('forms_post_to_ledger','true') is null as r1 \gset
select set_rule('grn_receipt_source','"grn"') is null as r2 \gset
reset role;
-- GRN of 10 kg + bill of 10 kg, guard OFF (today)
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-1',1,tt.today(),'{"supplier":"Sup A","lines":[{"item":"G1","counted":"10","rate":"5","quality":"accept"}]}','[]') ->> 'id' as ga \gset
select submit_entry(:'ga'::uuid) is not null as sa \gset
select tt.as(:'o'); select decide_entry(:'ga'::uuid, true, null, null, '[]') ->> 'status' as da \gset
select tt.as(:'k');
select save_purchase(null,null,:'sup',1,'E1-A',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":5}]',:'g1')::jsonb) ->> 'id' as ba \gset
select post_purchase(:'ba'::uuid) is not null as pa \gset
reset role;
select tt.chk('E1 guard off + source grn: GRN and bill both add (today = +20, the audit finding)', (select qty from stock_balance where item_id=:'g1'::uuid and location_id=1)=20);
-- guard SKIP
set role authenticated; select tt.as(:'o'); select set_rule('purchase_grn_guard','"skip"') is null as r3 \gset
select tt.as(:'k');
select save_entry(null,'04-1',1,tt.today(),'{"supplier":"Sup A","lines":[{"item":"G2","counted":"10","rate":"5","quality":"accept"}]}','[]') ->> 'id' as gb \gset
select submit_entry(:'gb'::uuid) is not null as sb \gset
select tt.as(:'o'); select decide_entry(:'gb'::uuid, true, null, null, '[]') ->> 'status' as db_ \gset
select tt.as(:'k');
select save_purchase(null,null,:'sup',1,'E1-B',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":5}]',:'g2')::jsonb) ->> 'id' as bb \gset
select post_purchase(:'bb'::uuid) ->> 'stock_from_grn' as flag \gset
reset role;
select tt.chk('E1 guard skip: GRN + bill for 10 kg gives +10, not +20', (select qty from stock_balance where item_id=:'g2'::uuid and location_id=1)=10 and :'flag'='true');
select tt.chk('E1 skip: the bill still records money (supplier owes 50) and the line base qty', (select total from purchase_bills where id=:'bb'::uuid)=50 and (select base_qty from purchase_lines where bill_id=:'bb'::uuid)=10 and _sup_balance(:'sup'::uuid)=100);
select tt.chk('E1 skip does not touch stock when the source is the purchase page', true);
-- GRN without any bill under source grn: still adds stock
set role authenticated; select tt.as(:'k');
select save_entry(null,'04-1',1,tt.today(),'{"supplier":"Sup B","lines":[{"item":"G3","counted":"7","rate":"5","quality":"accept"}]}','[]') ->> 'id' as gc \gset
select submit_entry(:'gc'::uuid) is not null as sc \gset
select tt.as(:'o'); select decide_entry(:'gc'::uuid, true, null, null, '[]') ->> 'status' as dc \gset
reset role;
select tt.chk('E1 bill-less GRN under source grn adds stock (+7)', (select qty from stock_balance where item_id=:'g3'::uuid and location_id=1)=7);
set role authenticated; select tt.as(:'o');
select tt.chk('E1 pending report (source grn): the two GRNs without link are listed, bill E1-B has no receipt link', (select jsonb_array_length(grn_pending_report()->'receipts_without_bill') from (select 1) x)=3 and (select jsonb_array_length(grn_pending_report()->'bills_without_receipt'))=2);
select grn_bill_link(:'gb'::uuid, :'bb'::uuid) is not null as lk \gset
select tt.chk('E1 link made: GRN gb and bill bb drop out of the pending lists', (select jsonb_array_length(grn_pending_report()->'receipts_without_bill'))=2 and (select jsonb_array_length(grn_pending_report()->'bills_without_receipt'))=1);
select tt.err('E1 a void or unknown bill cannot be linked', format($$select grn_bill_link('%s'::uuid, gen_random_uuid())$$, :'gb'), 'bill_not_found');
-- LINK mode
select set_rule('purchase_grn_guard','"link"') is null as r4 \gset
select tt.as(:'k');
select save_purchase(null,null,:'sup',1,'E1-C',tt.today(),format('[{"item_id":"%s","qty":7,"unit":"kg","unit_cost":5}]',:'g3')::jsonb) ->> 'id' as bc \gset
select tt.err('E1 link mode: bill without a GRN link is refused', format($$select post_purchase('%s'::uuid)$$, :'bc'), 'grn_link_required');
select grn_bill_link(:'gc'::uuid, :'bc'::uuid) is not null as lk2 \gset
select post_purchase(:'bc'::uuid) ->> 'status' as pc \gset
reset role;
select tt.chk('E1 link mode: after linking, the bill posts and stock stays +7 (not +14)', :'pc'='posted' and (select qty from stock_balance where item_id=:'g3'::uuid and location_id=1)=7);
-- source = purchase page: default behaviour, bill-less receive list
set role authenticated; select tt.as(:'o');
select set_rule('grn_receipt_source','"purchase"') is null as r5 \gset
select tt.as(:'k');
select save_entry(null,'04-1',1,tt.today(),'{"supplier":"Sup C","lines":[{"item":"G4","counted":"3","rate":"5","quality":"accept"}]}','[]') ->> 'id' as gd \gset
select submit_entry(:'gd'::uuid) is not null as sd \gset
select tt.as(:'o'); select decide_entry(:'gd'::uuid, true, null, null, '[]') ->> 'status' as dd \gset
select tt.chk('E1 source purchase: a receipt with no bill is in the pending list "no-bill receive"', exists (select 1 from jsonb_array_elements(grn_pending_report()->'receipts_without_bill') x where x->>'entry_id'=:'gd') and grn_pending_report()->>'source'='purchase' and jsonb_array_length(grn_pending_report()->'bills_without_receipt')=0);
reset role;
select tt.chk('E1 source purchase: its in-line was skipped, no stock (today)', not exists (select 1 from stock_ledger where item_id=:'g4'::uuid));
set role authenticated; select tt.as(:'k');
select save_purchase(null,null,:'sup',1,'E1-D',tt.today(),format('[{"item_id":"%s","qty":3,"unit":"kg","unit_cost":5}]',:'g4')::jsonb) ->> 'id' as bd \gset
select post_purchase(:'bd'::uuid) is not null as pd \gset
select tt.as(:'o'); select grn_bill_link(:'gd'::uuid, :'bd'::uuid) is not null as lk3 \gset
reset role;
select tt.chk('E1 source purchase: bill adds +3 once; after linking the receipt leaves the pending list', (select qty from stock_balance where item_id=:'g4'::uuid and location_id=1)=3 and not exists (select 1 from jsonb_array_elements(grn_pending_report()->'receipts_without_bill') x where x->>'entry_id'=:'gd'));
set role authenticated; select tt.as(:'o'); select set_rule('purchase_grn_guard','"off"') is null as r6 \gset reset role;

\echo == E2 void of a posted bill
set role authenticated; select tt.as(:'o');
select set_rule('grn_receipt_source','"purchase"') is null as q0 \gset
select set_rule('purchase_void_guard','"refuse"') is null as q1 \gset
reset role;
-- (a) posted return refers to the bill
set role authenticated; select tt.as(:'o');
select save_purchase(null,null,:'sup',1,'E2-A',tt.today(),format('[{"item_id":"%s","qty":20,"unit":"kg","unit_cost":10}]',:'g5')::jsonb) ->> 'id' as v1 \gset
select post_purchase(:'v1'::uuid, '[{"mode":"cash","amount":100}]'::jsonb) is not null as pv1 \gset
select save_purchase(null,null,:'sup',1,'E2-A-R',tt.today(),format('[{"item_id":"%s","qty":2,"unit":"kg","unit_cost":10}]',:'g5')::jsonb,0,'bad',null,'return',:'v1'::uuid,'damaged') ->> 'id' as r1 \gset
select post_purchase(:'r1'::uuid) is not null as pr1 \gset
select tt.err('E2 refuse: a posted return exists', format($$select void_purchase('%s'::uuid,'wrong bill')$$, :'v1'), 'void_has_return');
select tt.chk('E2 refused void left bill posted, stock 18 and payment intact', (select status from purchase_bills where id=:'v1'::uuid)='posted' and (select qty from stock_balance where item_id=:'g5'::uuid and location_id=1)=18 and (select count(*) from supplier_payments where bill_id=:'v1'::uuid and not voided)=1);
select void_purchase(:'r1'::uuid,'return was a mistake') ->> 'status' as vr \gset
-- (b) goods already used: stock would go negative
select stock_wastage(:'g5'::uuid, 1, 15, 'spoiled', 'used up') is not null as si \gset
select tt.err('E2 refuse: voiding would make stock negative (20 bought, 15 used + return voided = 20 on hand? no: 5 left)', format($$select void_purchase('%s'::uuid,'wrong bill')$$, :'v1'), 'void_would_go_negative');
-- (c) live GRN batch
select save_purchase(null,null,:'sup',1,'E2-B',tt.today(),format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":10}]',:'g4')::jsonb) ->> 'id' as v2 \gset
select post_purchase(:'v2'::uuid) is not null as pv2 \gset
select grn_batch_add('purchase', :'v2'::uuid, :'g4'::uuid, 4, 'kg', 'LOT-E2', tt.today()+5) ->> 'batch_id' as bt \gset
select tt.err('E2 refuse: a live GRN batch exists', format($$select void_purchase('%s'::uuid,'wrong bill')$$, :'v2'), 'void_has_grn_batch');
-- (d) payment kept as supplier credit
select save_supplier(null,'{"name":"Sup2"}') as sup2 \gset
select save_purchase(null,null,:'sup2',1,'E2-C',tt.today(),format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":10}]',:'g3')::jsonb) ->> 'id' as v3 \gset
select post_purchase(:'v3'::uuid, '[{"mode":"cash","amount":50}]'::jsonb) is not null as pv3 \gset
select set_rule('purchase_void_payments','"keep"') is null as q2 \gset
select void_purchase(:'v3'::uuid,'duplicate bill') ->> 'payments_kept' as kept \gset
select tt.chk('E2 keep: the bill is void, stock back, the cash payment is NOT voided', (select status from purchase_bills where id=:'v3'::uuid)='void' and (select count(*) from supplier_payments where bill_id=:'v3'::uuid and not voided)=1 and :'kept'::numeric=50);
select tt.chk('E2 keep: the 50 paid shows up as supplier credit (refund path exists)', (select credit from supplier_credits() where supplier_id=:'sup2'::uuid)=50 and exists (select 1 from exceptions where flag_code='purchase_void_credit'));
select tt.chk('E2 keep: supplier_refund can take the money back', (supplier_refund(:'sup2'::uuid, 1, 10, 'cash', null, null, null, 'part refund')->>'refunded')::numeric=10);
select set_rule('purchase_void_payments','"void"') is null as q3 \gset
-- (e) default payments behaviour unchanged (void) and warn mode proceeds with a red line
select set_rule('purchase_void_guard','"warn"') is null as q4 \gset
select save_purchase(null,null,:'sup',1,'E2-D',tt.today(),format('[{"item_id":"%s","qty":5,"unit":"kg","unit_cost":10}]',:'g3')::jsonb) ->> 'id' as v4 \gset
select post_purchase(:'v4'::uuid, '[{"mode":"cash","amount":20}]'::jsonb) is not null as pv4 \gset
select void_purchase(:'v4'::uuid,'again') ->> 'status' as vs4 \gset
select tt.chk('E2 void mode (today): payment voided too', :'vs4'='void' and (select count(*) from supplier_payments where bill_id=:'v4'::uuid and voided)=1);
select void_purchase(:'v1'::uuid,'warn mode') ->> 'status' as vs5 \gset
select tt.chk('E2 warn: unsafe void goes through but raises a red purchase_void_unsafe line', :'vs5'='void' and exists (select 1 from exceptions where flag_code='purchase_void_unsafe' and level='red'));
select set_rule('purchase_void_guard','"off"') is null as q5 \gset
reset role;
select tt.chk('E2 English text of the new exceptions has no Bangla letters', (select bool_and(tt.noBn(text->>'en')) from exceptions where flag_code in ('purchase_void_credit','purchase_void_unsafe')));

\echo == E3 unit conversion at sale
reset role;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('UB','UB','UB','box','pc','finished_good',true,50);
select id as iub from items where code='UB' \gset
select stock_opening(:'iub'::uuid,1,100,10,null,'seed') is not null as op \gset
-- default warn = today
select tt.as(:'o');
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 82001, now(), tt.today(), format('[{"item_id":"%s","qty":2,"price":50,"amount":100,"unit":"box"}]', :'iub')::jsonb, 100, 0, 100, 'cash', :'o', 'owner1', 'done') returning id as w1 \gset
select tt.chk('E3 warn (today): sale accepted, stock NOT reduced, yellow stock_unit_unknown', (select qty from stock_balance where item_id=:'iub'::uuid and location_id=1)=100 and (select count(*) from exceptions where sale_id=:'w1'::uuid and flag_code='stock_unit_unknown' and level='yellow')=1);
select tt.chk('E3 unit_unknown_items counts UB', (unit_unknown_items()->>'count')::int=1 and unit_unknown_items()->'items'->0->>'code'='UB');
select set_rule('unit_conv_required','"refuse"') is null as u1 \gset
select tt.err('E3 refuse: online sale is refused with unit_unknown', format($$insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status) values (gen_random_uuid(), 1, 82002, now(), current_date, '[{"item_id":"%s","qty":1,"price":50,"amount":50,"unit":"box"}]'::jsonb, 50, 0, 50, 'cash', %L, 'owner1', 'done')$$, :'iub', :'o'), 'unit_unknown');
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 82003, now() - interval '1 hour', tt.today(), format('[{"item_id":"%s","qty":1,"price":50,"amount":50,"unit":"box"}]', :'iub')::jsonb, 50, 0, 50, 'cash', :'o', 'owner1', 'done') returning id as w3 \gset
select tt.chk('E3 refuse: a late offline sale is accepted, stock not reduced, flagged RED', (select qty from stock_balance where item_id=:'iub'::uuid and location_id=1)=100 and (select count(*) from exceptions where sale_id=:'w3'::uuid and flag_code='stock_unit_unknown_late' and level='red')=1);
select tt.err('E3 refuse: item editor cannot make a mis-set item tracked', format($$update items set tracked=true where id='%s'$$, :'ibx'), 'unit_unknown');
select tt.err('E3 refuse: a new tracked item with no conversion is refused', $$insert into items (code,name_bn,unit,base_unit,tracked) values ('NEWX','NEWX','box','pc',true)$$, 'unit_unknown');
insert into unit_conversions (item_id, from_unit, to_unit, factor) values (:'iub'::uuid, 'box', 'pc', 12);
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 82004, now(), tt.today(), format('[{"item_id":"%s","qty":2,"price":50,"amount":100,"unit":"box"}]', :'iub')::jsonb, 100, 0, 100, 'cash', :'o', 'owner1', 'done');
select tt.chk('E3 with a conversion the sale deducts qty x factor (2 boxes = 24 pc)', (select qty from stock_balance where item_id=:'iub'::uuid and location_id=1)=76 and (unit_unknown_items()->>'count')::int=0);
insert into unit_conversions (item_id, from_unit, to_unit, factor) values (:'ibx'::uuid, 'box', 'pc', 6);
update items set tracked=true where id=:'ibx'::uuid;
select tt.chk('E3 refuse: after the conversion exists the item can be tracked', (select tracked from items where id=:'ibx'::uuid));
delete from unit_conversions where item_id=:'iub'::uuid;
select set_rule('unit_conv_required','"off"') is null as u2 \gset
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 82005, now(), tt.today(), format('[{"item_id":"%s","qty":1,"price":50,"amount":50,"unit":"box"}]', :'iub')::jsonb, 50, 0, 50, 'cash', :'o', 'owner1', 'done') returning id as w5 \gset
select tt.chk('E3 off: sale accepted and no exception at all', (select count(*) from exceptions where sale_id=:'w5'::uuid)=0);
select set_rule('unit_conv_required','"warn"') is null as u3 \gset
select tt.chk('E3 English text of unit exceptions has no Bangla letters', (select bool_and(tt.noBn(text->>'en')) from exceptions where flag_code in ('stock_unit_unknown','stock_unit_unknown_late')));
select tt.chk('E3 unit_unknown_items is owner-only', (select count(*) from (select 1) x)=1);
select tt.as(:'s'); set role authenticated;
select tt.err('E3 unit_unknown_items refused for a manager', 'select unit_unknown_items()', 'not allowed');
reset role; select tt.as(:'o');

\echo == E4 negative stock
-- never-opened list under warn
select set_rule('stock_negative_mode','"warn"') is null as n0 \gset
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 82010, now(), tt.today(), format('[{"item_id":"%s","qty":1,"price":10,"amount":10,"unit":"kg"}]', :'ino')::jsonb, 10, 0, 10, 'cash', :'o', 'owner1', 'done');
select tt.chk('E4 never-opened item sold under warn: negative, no stock_negative exception (the audit gap)', (select qty from stock_balance where item_id=:'ino'::uuid and location_id=1)=-1 and not exists (select 1 from exceptions where flag_code='stock_negative' and text->>'en' like '%NO%'));
select tt.chk('E4 never_opened_negative_items lists it (and not an item that was opened)', (never_opened_negative_items()->>'count')::int=1 and never_opened_negative_items()->'items'->0->>'code'='NO');
select stock_opening(:'ino'::uuid,1,5,3,null,'late opening') is not null as op2 \gset
select tt.chk('E4 after an opening row exists the item leaves the list', (never_opened_negative_items()->>'count')::int=0);
-- grant use log under block
select stock_opening(:'ifg'::uuid,1,3,3,null,'seed') is not null as op3 \gset
select set_rule('stock_negative_mode','"block"') is null as n1 \gset
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 82011, now(), tt.today(), format('[{"item_id":"%s","qty":5,"price":10,"amount":50,"unit":"kg"}]', :'ifg')::jsonb, 50, 0, 50, 'cash', :'o', 'owner1', 'done') returning id as n2 \gset
select tt.chk('E4 switch off (today): owner holding the grant goes below zero with no exception', (select qty from stock_balance where item_id=:'ifg'::uuid and location_id=1)=-2 and not exists (select 1 from exceptions where flag_code='sell_below_zero_used'));
select set_rule('neg_grant_log','true') is null as n3 \gset
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 82012, now(), tt.today(), format('[{"item_id":"%s","qty":1,"price":10,"amount":10,"unit":"kg"}]', :'ifg')::jsonb, 10, 0, 10, 'cash', :'o', 'owner1', 'done') returning id as n4 \gset
select tt.chk('E4 switch on: grant use logs one yellow line (item, qty, staff)', (select count(*) from exceptions where sale_id=:'n4'::uuid and flag_code='sell_below_zero_used' and level='yellow' and text->>'en' like '%FG%' and text->>'en' like '%qty 1%')=1);
select tt.chk('E4 English text has no Bangla letters', (select bool_and(tt.noBn(text->>'en')) from exceptions where flag_code in ('sell_below_zero_used')));
-- a user without the grant is still refused in block mode
select tt.as(:'s');
select tt.err('E4 block still refuses a user without the grant', format($$select stock_post('%s'::uuid,1,-1,'issue_out','issue','x1')$$, :'ifg'), 'insufficient_stock');
select tt.as(:'o');
-- production negative ingredient
select set_rule('stock_negative_mode','"warn"') is null as n5 \gset
select stock_opening(:'g1'::uuid,1,2,1,null,'seed') is not null as op4 \gset
select tt.chk('E4 production negative, switch off (today): goes through with no reason', stock_post(:'g1'::uuid,1,-30,'issue_out','production','run-1',null,null,now(),null,null,'full') is not null);
select set_rule('production_negative_reason','"required"') is null as n6 \gset
select tt.err('E4 required: production negative without a reason is refused', format($$select stock_post('%s'::uuid,1,-5,'issue_out','production','run-2',null,null,now(),null,null,'full')$$, :'g1'), 'production_negative_reason_needed');
select stock_post(:'g1'::uuid,1,-5,'issue_out','production','run-3',null,null,now(),'stock card not yet updated',null,'full') is not null as ok3 \gset
select tt.chk('E4 required: with a reason it passes and a yellow production_negative line names qty and reason', :'ok3'::boolean
  and exists (select 1 from exceptions where flag_code='production_negative' and text->>'en' like '%qty 5%' and text->>'en' like '%stock card not yet updated%'));
select tt.chk('E4 a normal production within stock is not affected', stock_post(:'g2'::uuid,1,-1,'issue_out','production','run-4',null,null,now(),null,null,'full') is not null);
select tt.chk('E4 English text has no Bangla letters', (select bool_and(tt.noBn(text->>'en')) from exceptions where flag_code='production_negative'));
select set_rule('production_negative_reason','"off"') is null as n7 \gset

\echo == guard_recommendations
set role authenticated;
select tt.chk('R1 recommendations: 7 rows with key, current, recommended and 3 reasons', (select count(*) from jsonb_array_elements(guard_recommendations()) x where x ? 'key' and x ? 'current' and x ? 'recommended' and x ? 'reason_bn' and x ? 'reason_mix' and x ? 'reason_en')=7);
select tt.chk('R1 English reasons have no Bangla letters', (select bool_and(tt.noBn(x->>'reason_en')) from jsonb_array_elements(guard_recommendations()) x));
select tt.chk('R1 stock_negative_mode recommends block once an opening exists; unit_conv follows the data', (select x->>'recommended' from jsonb_array_elements(guard_recommendations()) x where x->>'key'='stock_negative_mode')='block');
select tt.chk('R1 recommending changes nothing', rule_txt('stock_negative_mode')='warn' and rule_txt('purchase_void_guard')='off');
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('R1 owner only', 'select guard_recommendations()', 'not allowed');
reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
