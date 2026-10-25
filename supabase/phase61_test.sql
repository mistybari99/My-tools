-- FRESH DB ONLY. Phase 61 tests (P3 slice b: #11 online orders, #12 forms 20-x <-> sales, #13 benefits depth, #14 BI export).
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase61" bash tests/sql/build_fresh_db.sh a61db
--   psql -h /tmp -p 5544 -U postgres -d a61db -qAt -f supabase/phase61_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
\set e '00000000-0000-0000-0000-000000000006'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','sales4@s.app','{"full_name":"Sales"}'), (:'t','mgr5@s.app','{"full_name":"Other place"}'), (:'e','exp6@s.app','{"full_name":"Exporter"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper'),(:'p','salesperson'),(:'t','showroom_manager'),(:'e','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1),(:'t',2),(:'e',1) on conflict do nothing;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('C1','C1','C1','kg','kg','finished_good',true,100), ('C2','C2','C2','kg','kg','finished_good',true,50);
select id as c1 from items where code='C1' \gset
select id as c2 from items where code='C2' \gset
select tt.as(:'o');
select stock_opening(:'c1'::uuid, 1, 100, 40, null, 'seed') is not null as op1 \gset
select stock_opening(:'c2'::uuid, 1, 100, 20, null, 'seed') is not null as op2 \gset

\echo == T0 shape
select tt.chk('T0 browser functions open, helpers closed, anon none',
  has_function_privilege('authenticated','public.bi_export(text,date,date,int,text,int)','execute') and not has_function_privilege('anon','public.bi_export(text,date,date,int,text,int)','execute')
  and has_function_privilege('authenticated','public.online_order_deliver(uuid,jsonb)','execute') and not has_function_privilege('authenticated','public._oo_gate61(int,text)','execute')
  and not has_function_privilege('authenticated','public._bi_csv61(text[],jsonb)','execute') and not has_function_privilege('anon','public.online_order_save(uuid,uuid,int,text,text,text,text,jsonb,text,text,date,numeric,numeric,numeric,text,text,text)','execute'));
select tt.chk('T0 tables are read-only for browsers (no insert/update/delete), RLS on',
  not has_table_privilege('authenticated','public.online_orders','insert') and not has_table_privilege('authenticated','public.online_orders','update') and not has_table_privilege('authenticated','public.sale_form_links','insert')
  and not has_table_privilege('authenticated','public.employee_benefit_grants','update') and not has_table_privilege('authenticated','public.bi_export_log','insert')
  and (select bool_and(relrowsecurity) from pg_class where relname in ('online_orders','online_order_events','sale_form_links','benefit_types','employee_benefit_grants','bi_export_log')));
select tt.chk('T0 secrets stay hidden: sale_client and the benefit value are not selectable', not has_column_privilege('authenticated','public.online_orders','sale_client','select')
  and not has_column_privilege('authenticated','public.employee_benefit_grants','value_per_month','select') and has_column_privilege('authenticated','public.employee_benefit_grants','eligible_from','select'));
select tt.chk('T0 five rules, all OFF except the row cap default 5000', (select count(*) from rules where key in ('online_orders_on','sale_forms_link_on','benefit_grants_on','bi_export_on'))=4
  and not rule_on('online_orders_on') and not rule_on('sale_forms_link_on') and not rule_on('benefit_grants_on') and not rule_on('bi_export_on') and rule_num('bi_export_max_rows')=5000);
select tt.chk('T0 path domain sale_forms exists (sale_forms present)', (select count(*) from path_domains)>=8 and exists (select 1 from path_domains where domain='sale_forms'));

\echo == T1 online orders (#11)
select tt.as(:'s');
select format('select online_order_save(null,gen_random_uuid(),1,%L,%L,%L,%L,%L::jsonb,%L,null,null,0,0,0,null,null,null)', 'facebook','Rina','01711000001','Dhaka',
   format('[{"item_id":"%s","qty":2}]', :'c1'), 'home') as oq \gset
select tt.err('T1 switch is off: refused', :'oq', 'module_off');
select tt.as(:'o'); select set_rule('online_orders_on','true') is null as r1 \gset
select tt.as(:'k');
select tt.err('T1 storekeeper (no POS) cannot create', :'oq', 'not allowed');
select tt.as(:'t');
select tt.err('T1 a manager of another place cannot create at place 1', :'oq', 'not allowed for this location');
select tt.as(:'s');
select gen_random_uuid()::text as oc \gset
select online_order_save(null, :'oc'::uuid, 1, 'facebook', 'Rina', '01711000001', 'Dhaka', format('[{"item_id":"%s","qty":2}]', :'c1')::jsonb, 'home', 'own', tt.today()+1, 30, 0, 50, 'mobile', 'bkash', 'note') as r \gset
select (:'r'::jsonb ->> 'id') as oid, (:'r'::jsonb ->> 'order_no') as ono, (:'r'::jsonb ->> 'balance') as obal \gset
select tt.chk('T1 created: order 1, subtotal 200, balance 200+30-50 = 180', :'ono'='1' and :'obal'::numeric=180 and (select subtotal from online_orders where id=:'oid'::uuid)=200);
select tt.chk('T1 same client id = same order (idempotent), still one row', (online_order_save(null, :'oc'::uuid, 1, 'facebook', 'Rina', '01711000001', 'Dhaka', format('[{"item_id":"%s","qty":2}]', :'c1')::jsonb, 'home', 'own', tt.today()+1, 30, 0, 50, 'mobile', 'bkash', 'note') ->> 'dup')::boolean
  and (select count(*) from online_orders)=1);
select tt.err('T1 home delivery needs an address', format($$select online_order_save(null,gen_random_uuid(),1,'phone','A','01711000002',null,'[{"item_id":"%s","qty":1}]'::jsonb,'home',null,null,0,0,0,null,null,null)$$, :'c1'), 'address_required');
select tt.err('T1 advance above the total refused', format($$select online_order_save(null,gen_random_uuid(),1,'phone','A','01711000002',null,'[{"item_id":"%s","qty":1}]'::jsonb,'pickup',null,null,0,0,500,'cash',null,null)$$, :'c1'), 'advance_over_total');
select tt.err('T1 advance needs a mode', format($$select online_order_save(null,gen_random_uuid(),1,'phone','A','01711000002',null,'[{"item_id":"%s","qty":1}]'::jsonb,'pickup',null,null,0,0,50,null,null,null)$$, :'c1'), 'bad_mode');
select tt.err('T1 bad qty refused', format($$select online_order_save(null,gen_random_uuid(),1,'phone','A','01711000002',null,'[{"item_id":"%s","qty":0}]'::jsonb,'pickup',null,null,0,0,0,null,null,null)$$, :'c1'), 'bad_qty');
select tt.err('T1 bad channel refused', format($$select online_order_save(null,gen_random_uuid(),1,'tv','A','01711000002',null,'[{"item_id":"%s","qty":1}]'::jsonb,'pickup',null,null,0,0,0,null,null,null)$$, :'c1'), 'bad_channel');
select tt.err('T1 deliver from new refused', format($$select online_order_deliver('%s','[]')$$, :'oid'), 'bad_status');
select tt.err('T1 cannot jump new -> packed', format($$select online_order_status('%s','packed')$$, :'oid'), 'bad_status');
select online_order_status(:'oid'::uuid,'confirmed') ->> 'status' as st1 \gset
select online_order_status(:'oid'::uuid,'confirmed') ->> 'noop' as st1b \gset
select tt.chk('T1 confirm works and repeating it is a no-op', :'st1'='confirmed' and :'st1b'='true');
select tt.chk('T1 edit while confirmed works (qty 3 -> subtotal 300)', (online_order_save(:'oid'::uuid, null, null, 'facebook', 'Rina', '01711000001', 'Dhaka', format('[{"item_id":"%s","qty":3}]', :'c1')::jsonb, 'home', 'own', tt.today()+1, 30, 0, 50, 'mobile', 'bkash', 'note') ->> 'subtotal')::numeric=300);
select online_order_status(:'oid'::uuid,'packed') ->> 'status' as st2 \gset
select tt.chk('T1 packed', :'st2'='packed');
select tt.err('T1 packed order cannot be edited', format($$select online_order_save('%s',null,null,'facebook','Rina','01711000001','Dhaka','[{"item_id":"%s","qty":1}]'::jsonb,'home','own',null,30,0,50,'mobile','bkash','x')$$, :'oid', :'c1'), 'order_closed');
select tt.as(:'k');
select tt.err('T1 storekeeper cannot deliver', format($$select online_order_deliver('%s','[]')$$, :'oid'), 'not allowed');
select tt.as(:'s');
select tt.err('T1 payment above the total refused by the existing sale path (overpaid)', format($$select online_order_deliver('%s','[{"mode":"cash","amount":9999}]')$$, :'oid'), 'overpaid');
select tt.chk('T1 the failed delivery left no sale and the order still packed', (select count(*) from sales)=0 and (select status from online_orders where id=:'oid'::uuid)='packed');
select online_order_deliver(:'oid'::uuid, '[{"mode":"cash","amount":280}]') as dv \gset
select (:'dv'::jsonb ->> 'sale_id') as sid \gset
select tt.chk('T1 delivered: ONE sale, total 300+30=330, paid 50 advance + 280 cash, no due', (select count(*) from sales)=1 and (select total from sales where id=:'sid'::uuid)=330
  and (select paid from sales where id=:'sid'::uuid)=330 and (select due_amount from sales where id=:'sid'::uuid)=0 and (select count(*) from sale_payments where sale_id=:'sid'::uuid)=2);
select tt.chk('T1 the stock left once through the sale (-3)', (select coalesce(sum(qty_delta),0) from stock_ledger where item_id=:'c1' and location_id=1 and reason<>'opening')=-3);
select tt.chk('T1 deliver again = same sale, no second sale', (online_order_deliver(:'oid'::uuid, '[{"mode":"cash","amount":10}]') ->> 'dup')::boolean and (select count(*) from sales)=1 and (select count(*) from sale_payments where sale_id=:'sid'::uuid)=2);
select tt.chk('T1 order now delivered and linked', (select status from online_orders where id=:'oid'::uuid)='delivered' and (select sale_id from online_orders where id=:'oid'::uuid)=:'sid'::uuid);
select tt.err('T1 a delivered order cannot be cancelled', format($$select online_order_cancel('%s','x','none')$$, :'oid'), 'order_closed');
select tt.err('T1 an order row can never be edited directly once closed', format($$update online_orders set note='x' where id='%s'$$, :'oid'), 'order_closed');
select tt.err('T1 an order is never deleted', format($$delete from online_orders where id='%s'$$, :'oid'), 'append_only');
select tt.err('T1 the order trail is append-only', $$update online_order_events set note='x'$$, 'append_only');
select tt.chk('T1 trail has created, confirmed, edited, packed, delivered', (select count(*) from online_order_events where order_id=:'oid'::uuid)=5);
-- cancel flow
select online_order_save(null, gen_random_uuid(), 1, 'whatsapp', 'Sumi', '01711000003', null, format('[{"item_id":"%s","qty":1}]', :'c2')::jsonb, 'pickup', null, null, 0, 0, 20, 'cash', null, null) ->> 'id' as oid2 \gset
select tt.err('T1 cancel needs a reason', format($$select online_order_cancel('%s','','refund')$$, :'oid2'), 'reason_required');
select tt.err('T1 cancel with an advance needs its fate', format($$select online_order_cancel('%s','no answer','none')$$, :'oid2'), 'advance_fate_required');
select online_order_cancel(:'oid2'::uuid, 'no answer', 'refund') ->> 'status' as cs \gset
select tt.chk('T1 cancelled with the advance fate kept on the order', :'cs'='cancelled' and (select advance_fate from online_orders where id=:'oid2'::uuid)='refund');
select tt.err('T1 a cancelled order cannot be delivered', format($$select online_order_deliver('%s','[]')$$, :'oid2'), 'bad_status');
-- link an existing sale
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1}]', :'c2')::jsonb, 0, '[{"mode":"cash","amount":50}]'::jsonb, null, null, 'retail', 'counter', false, null) ->> 'id' as csale \gset
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'Tia', '01711000004', null, format('[{"item_id":"%s","qty":1}]', :'c2')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) ->> 'id' as oid3 \gset
select tt.as(:'p');
select tt.err('T1 salesperson (no POS approve) cannot link an existing sale', format($$select online_order_link_sale('%s','%s')$$, :'oid3', :'csale'), 'not allowed');
select tt.as(:'s');
select tt.err('T1 the sale already used by order 1 cannot be linked again', format($$select online_order_link_sale('%s','%s')$$, :'oid3', :'sid'), 'sale_already_linked');
select online_order_link_sale(:'oid3'::uuid, :'csale'::uuid, 'sold at counter') ->> 'status' as ls \gset
select tt.chk('T1 linking an existing sale: delivered, NO new sale made (2 sales in all)', :'ls'='delivered' and (select count(*) from sales)=2 and (select sale_id from online_orders where id=:'oid3'::uuid)=:'csale'::uuid);
select tt.chk('T1 link is idempotent', (online_order_link_sale(:'oid3'::uuid, :'csale'::uuid) ->> 'dup')::boolean);
select tt.chk('T1 list: place filter + status filter', jsonb_array_length(online_orders_list(1,'delivered',null,null,50))=2 and jsonb_array_length(online_orders_list(1,'cancelled',null,null,50))=1);
select tt.as(:'t');
select tt.err('T1 another place cannot read the list of place 1', $$select online_orders_list(1,null,null,null,10)$$, 'not allowed for this location');
select tt.err('T1 another place cannot read one order', format($$select online_order_get('%s')$$, :'oid'), 'not allowed');
select tt.as(:'s');
select tt.chk('T1 order detail has the trail and hides the internal sale client id', jsonb_array_length(online_order_get(:'oid'::uuid)->'events')=5 and not (online_order_get(:'oid'::uuid) ? 'sale_client'));

\echo == T2 forms 20-1 / 20-2 / 20-4 <-> sales (#12)
select tt.as(:'o');
select save_entry(null,'20-1',1,tt.today(),'{"taker":"x","cust_name":"Rina","cust_phone":"01711000001","total":"330","discount":"0","advance":"50"}','[]') ->> 'id' as f1 \gset
select save_entry(null,'20-2',1,tt.today(),'{"seller":"x"}','[]') ->> 'id' as f2 \gset
select save_entry(null,'20-4',1,tt.today(),'{"party":"Party A","phone":"01711000009"}','[]') ->> 'id' as f4 \gset
select save_entry(null,'20-3',1,tt.today(),'{}','[]') ->> 'id' as f3 \gset
select save_entry(null,'20-1',2,tt.today(),'{"cust_name":"Far","total":"330"}','[]') ->> 'id' as fz \gset
update entries set status='submitted' where id in (:'f1'::uuid, :'f2'::uuid, :'f4'::uuid, :'f3'::uuid, :'fz'::uuid) and false;
select tt.err('T2 switch off: refused', format($$select sale_form_link('%s','%s')$$, :'f1', :'sid'), 'module_off');
select set_rule('sale_forms_link_on','true') is null as r2 \gset
select tt.err('T2 a draft form cannot be linked', format($$select sale_form_link('%s','%s')$$, :'f1', :'sid'), 'form_not_final');
update entries set status='submitted' where id in (:'f1'::uuid, :'f2'::uuid, :'f4'::uuid, :'f3'::uuid, :'fz'::uuid);
select tt.as(:'s');
select tt.err('T2 only the owner links', format($$select sale_form_link('%s','%s')$$, :'f1', :'sid'), 'not allowed');
select tt.as(:'o');
select tt.err('T2 20-3 is not linkable', format($$select sale_form_link('%s','%s')$$, :'f3', :'sid'), 'form_not_linkable');
select tt.err('T2 a form of another place cannot link a sale of place 1', format($$select sale_form_link('%s','%s')$$, :'fz', :'sid'), 'other_location');
select tt.chk('T2 report before linking lists the 20-1, 20-2, 20-4 (3 forms) with candidate sales for 20-1 (total 330 -> the delivered sale)',
  jsonb_array_length(unlinked_sale_forms(tt.today(), tt.today(), 1, 50))=3
  and (select (z->'candidate_sales') ? :'sid' from jsonb_array_elements(unlinked_sale_forms(tt.today(), tt.today(), 1, 50)) z where z->>'form_code'='20-1'));
select sale_form_link(:'f1'::uuid, :'sid'::uuid, 'checked paper') as lk1 \gset
select (:'lk1'::jsonb ->> 'id') as l1 \gset
select tt.chk('T2 linked: amount matches the sale (diff 0)', (:'lk1'::jsonb ->> 'amount_diff')::numeric=0 and (:'lk1'::jsonb ->> 'amount_matches')::boolean);
select tt.chk('T2 the form is a locked shadow (shadow type entries:20-1), the sale is the primary', is_shadow('entries:20-1', :'f1') and not is_shadow('sales', :'sid')
  and exists (select 1 from shadow_links where domain='sale_forms' and primary_type='sales' and primary_id=:'sid' and shadow_type='entries:20-1' and shadow_id=:'f1' and state='confirmed'));
select tt.chk('T2 linking again is idempotent', (sale_form_link(:'f1'::uuid, :'sid'::uuid) ->> 'dup')::boolean and (select count(*) from sale_form_links where state='active')=1);
select tt.err('T2 the same form cannot link a second sale', format($$select sale_form_link('%s','%s')$$, :'f1', :'csale'), 'entry_already_linked');
select save_entry(null,'20-1',1,tt.today(),'{"cust_name":"Dup","total":"330"}','[]') ->> 'id' as f1b \gset
update entries set status='submitted' where id=:'f1b'::uuid;
select tt.err('T2 a sale takes one 20-1 only', format($$select sale_form_link('%s','%s')$$, :'f1b', :'sid'), 'sale_already_has_form');
select sale_form_link(:'f2'::uuid, :'sid'::uuid) is not null as j2, sale_form_link(:'f4'::uuid, :'sid'::uuid) is not null as j4 \gset
select tt.chk('T2 20-2 and 20-4 can join the same sale (own shadow types)', :'j2'::boolean and :'j4'::boolean and jsonb_array_length(sale_forms_for(:'sid'::uuid))=3);
select tt.chk('T2 amount unknown for 20-2 / 20-4 (null, not a false match)', (select count(*) from sale_form_links where form_code in ('20-2','20-4') and amount_diff is null)=2);
select tt.err('T2 a linked form cannot be edited', format($$update entries set data = data || '{"total":"1"}' where id='%s'$$, :'f1'), 'shadow_locked');
select tt.err('T2 a linked form cannot be re-opened', format($$update entries set status='draft' where id='%s'$$, :'f1'), 'shadow_locked');
with u as (update entries set status='approved' where id=:'f1'::uuid returning 1) select count(*) as nap from u \gset
select tt.chk('T2 approving a linked form (data unchanged) still works', :'nap'::int=1);
select tt.chk('T2 sales and stock are untouched by linking (2 sales, stock -4 still)', (select count(*) from sales)=2 and (select coalesce(sum(qty_delta),0) from stock_ledger where location_id=1 and reason<>'opening')=-4);
select tt.chk('T2 nothing counted twice: no shadow reached the journal, no entry is both primary and shadow', shadow_count_once_check() = '{"shadow_in_journal": [], "both_roles": []}'::jsonb);
select tt.chk('T2 report after linking: only f1b (a 2nd 20-1) is still unlinked', jsonb_array_length(unlinked_sale_forms(tt.today(), tt.today(), 1, 50))=1 and unlinked_sale_forms(tt.today(), tt.today(), 1, 50)->0->>'entry_id'=:'f1b');
select tt.as(:'k');
select tt.err('T2 report: a user of place 1 cannot read place 2', $$select unlinked_sale_forms(current_date-1, current_date, 2, 10)$$, 'not allowed for this location');
select tt.as(:'o');
select path_switch_set('sale_forms',0,true,false,'a') is not null as sw1 \gset
select tt.err('T2 owner locks path B: no new link', format($$select sale_form_link('%s','%s')$$, :'f1b', :'csale'), 'path_locked');
select path_switch_set('sale_forms',0,true,true,'a') is not null as sw2 \gset
select tt.err('T2 unlink needs a note', format($$select sale_form_unlink(%s,'')$$, :'l1'), 'note_needed');
select tt.as(:'s');
select tt.err('T2 only the owner unlinks', format($$select sale_form_unlink(%s,'x')$$, :'l1'), 'not allowed');
select tt.as(:'o');
select sale_form_unlink(:'l1'::bigint, 'wrong sale') ->> 'state' as us \gset
select tt.chk('T2 unlinked: link void, shadow void, form free to edit again', :'us'='void' and not is_shadow('entries:20-1', :'f1') and (select state from shadow_links where shadow_id=:'f1')='void');
with u as (update entries set status='draft' where id=:'f1'::uuid returning 1) select count(*) as ndr from u \gset
select tt.chk('T2 after unlink the form can be re-opened', :'ndr'::int=1);
select tt.chk('T2 the link trail is kept (void row stays) and cannot be deleted', (select count(*) from sale_form_links where id=:'l1'::bigint and state='void')=1);
select tt.err('T2 link trail is append-only', format($$delete from sale_form_links where id=%s$$, :'l1'), 'append_only');
update entries set status='submitted' where id=:'f1'::uuid;
select tt.chk('T2 after unlink the form can be linked to the right sale', (sale_form_link(:'f1'::uuid, :'csale'::uuid) ->> 'amount_diff')::numeric=280);

\echo == T3 benefits depth (#13)
select tt.as(:'o');
insert into employees (full_name_bn, primary_location_id, joining_date, status) values ('এমপ ১', 1, tt.today()-30, 'active'), ('এমপ ২', 1, tt.today()-300, 'active');
select id as e1 from employees where full_name_bn='এমপ ১' \gset
select id as e2 from employees where full_name_bn='এমপ ২' \gset
select tt.err('T3 switch off: grant refused', format($$select employee_benefit_grant(null,gen_random_uuid(),'%s','meal','%s',null,null)$$, :'e1', tt.today()), 'module_off');
select set_rule('benefit_grants_on','true') is null as r3 \gset
select benefit_type_save('festival','উৎসব ভাতা','Festival allowance',true,90,true,true) ->> 'code' as bt \gset
select tt.chk('T3 owner defines a type: paid in payroll, eligible after 90 days, default for all', :'bt'='festival' and (select eligible_after_days from benefit_types where code='festival')=90 and (select paid_in_payroll and default_for_all from benefit_types where code='festival'));
select tt.err('T3 bad code refused', $$select benefit_type_save('Bad Code','x','x',false,0,false)$$, 'bad_code');
select tt.err('T3 bad days refused', $$select benefit_type_save('x1','x','x',false,4000,false)$$, 'bad_days');
select tt.as(:'s');
select tt.err('T3 a manager without salary_manage cannot define types', $$select benefit_type_save('x2','x','x',false,0,false)$$, 'not allowed');
select tt.as(:'o');
select set_user_grant(:'s'::uuid,'employee_manage',null,null,true,null) is null as g1 \gset
select tt.as(:'s');
select employee_benefit_grant(null, gen_random_uuid(), :'e1'::uuid, 'festival', tt.today()-30, null, null, null, 'first') ->> 'id' as g1id \gset
select tt.chk('T3 manager grants without a value; paid flag taken from the type (true); eligible from = joining + 90 days (future)',
  (select paid_in_payroll from employee_benefit_grants where id=:'g1id'::bigint) and (select eligible_from from employee_benefit_grants where id=:'g1id'::bigint)=tt.today()-30+90);
select tt.err('T3 a manager without salary_manage cannot write a value', format($$select employee_benefit_grant(null,gen_random_uuid(),'%s','meal','%s',null,500)$$, :'e1', tt.today()), 'not allowed');
select tt.err('T3 overlapping grant of the same type refused', format($$select employee_benefit_grant(null,gen_random_uuid(),'%s','festival','%s',null,null)$$, :'e1', tt.today()), 'overlap');
select tt.err('T3 a manager of another place cannot grant', format($$select 1 from (select set_config('request.jwt.claim.sub','%s',false)) q, lateral (select employee_benefit_grant(null,gen_random_uuid(),'%s','meal','%s',null,null)) z$$, :'t', :'e1', tt.today()), 'not allowed');
select tt.as(:'s');
select gen_random_uuid()::text as gc \gset
select employee_benefit_grant(null, :'gc'::uuid, :'e1'::uuid, 'meal', tt.today()-10, null, null, false, null) ->> 'id' as g2id \gset
select tt.chk('T3 idempotent client id', (employee_benefit_grant(null, :'gc'::uuid, :'e1'::uuid, 'meal', tt.today()-10, null, null, false, null) ->> 'repeat')::boolean);
select tt.as(:'o');
select employee_benefit_grant(:'g2id'::bigint, null, null, null, tt.today()-10, null, 800, true, 'raised') ->> 'paid_in_payroll' as pf \gset
select tt.chk('T3 owner sets the value and the paid-in-payroll flag on a grant', :'pf'='true' and (select value_per_month from employee_benefit_grants where id=:'g2id'::bigint)=800);
select benefits_report(tt.today()) as rep_o \gset
select tt.chk('T3 report (owner): festival grant is not_yet (eligible later), meal grant eligible, value visible, monthly paid-in-payroll eligible total = 800',
  (select z->>'state' from jsonb_array_elements(:'rep_o'::jsonb->'grants') z where z->>'type_code'='festival')='not_yet'
  and (select z->>'state' from jsonb_array_elements(:'rep_o'::jsonb->'grants') z where z->>'type_code'='meal')='eligible'
  and (select (z->>'value_per_month')::numeric from jsonb_array_elements(:'rep_o'::jsonb->'grants') z where z->>'type_code'='meal')=800 and (:'rep_o'::jsonb->>'paid_in_payroll_monthly_visible')::numeric=800);
select tt.chk('T3 report: employee 2 (joined 300 days ago) is missing the default-for-all festival grant, employee 1 is not', (select count(*) from jsonb_array_elements(:'rep_o'::jsonb->'missing') z where z->>'employee_id'=:'e2' and z->>'type_code'='festival')=1
  and (select count(*) from jsonb_array_elements(:'rep_o'::jsonb->'missing') z where z->>'employee_id'=:'e1')=0);
select tt.as(:'s');
select benefits_report(tt.today()) as rep_s \gset
select tt.chk('T3 report (manager without salary_view): grants listed but the value is hidden', jsonb_array_length(:'rep_s'::jsonb->'grants')=2
  and (select z->'value_per_month' from jsonb_array_elements(:'rep_s'::jsonb->'grants') z where z->>'type_code'='meal')='null'::jsonb and (:'rep_s'::jsonb->>'paid_in_payroll_monthly_visible')::numeric=0);
select tt.as(:'o');
select employee_benefit_grant(null, gen_random_uuid(), :'e2'::uuid, 'festival', tt.today()-100, null, null, null, null) is not null as g3 \gset
select tt.chk('T3 after the grant employee 2 leaves the missing list; eligible_from = joining + 90 = already past', (select count(*) from jsonb_array_elements(benefits_report(tt.today())->'missing') z where z->>'employee_id'=:'e2')=0
  and (select z->>'state' from jsonb_array_elements(benefits_report(tt.today())->'grants') z where z->>'employee_id'=:'e2')='eligible');
select employee_benefit_grant_end(:'g2id'::bigint, tt.today(), 'left') is not null as en \gset
select tt.chk('T3 ending a grant: state ended in the report (a day later)', (select z->>'state' from jsonb_array_elements(benefits_report(tt.today()+1)->'grants') z where z->>'type_code'='meal')='ended');
select tt.err('T3 an ended grant cannot be edited', format($$select employee_benefit_grant(%s,null,null,null,'%s',null,1,null,null)$$, :'g2id', tt.today()-10), 'grant_ended');
select tt.chk('T3 payroll maths untouched: no payroll function reads the new grants', not exists (select 1 from pg_proc where pronamespace='public'::regnamespace and prosrc like '%employee_benefit_grants%' and proname not in ('employee_benefit_grant','employee_benefit_grant_end','benefits_report')));
select tt.as(:'k');
select tt.chk('T3 storekeeper (no employee right) sees no grants and no missing list', jsonb_array_length(benefits_report(tt.today())->'grants')=0 and jsonb_array_length(benefits_report(tt.today())->'missing')=0);

\echo == T4 BI export (#14)
select tt.as(:'o');
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":1}]', :'c2')::jsonb, 0, '[{"mode":"cash","amount":50}]'::jsonb, '01788888888', '=A1, x', 'retail', 'csv test', false, null) ->> 'id' as xs \gset
select tt.err('T4 switch off: refused', format($$select bi_export('sales','%s','%s',null,'json',null)$$, tt.today(), tt.today()), 'module_off');
select set_rule('bi_export_on','true') is null as r4 \gset
select tt.as(:'e');
select tt.err('T4 a user without the export grant is refused', format($$select bi_export('sales','%s','%s',null,'json',null)$$, tt.today(), tt.today()), 'not allowed');
select tt.as(:'o'); select set_user_grant(:'e'::uuid,'export_data',null,null,true,null) is null as g4 \gset
select tt.as(:'e');
select bi_export('sales', tt.today(), tt.today(), null, 'json', null) as x1 \gset
select tt.chk('T4 sales export (json): 3 sales, columns, row_count, not truncated, a log row', (:'x1'::jsonb->>'row_count')::int=3 and jsonb_array_length(:'x1'::jsonb->'rows')=3 and not (:'x1'::jsonb->>'truncated')::boolean
  and jsonb_array_length(:'x1'::jsonb->'columns')=14 and (select count(*) from bi_export_log where dataset='sales' and row_count=3 and user_id=:'e')=1);
select tt.chk('T4 sales export carries no cost and no customer mobile', not (:'x1'::text ~* 'unit_cost|mobile|01788888888'));
select bi_export('sales', tt.today(), tt.today(), null, 'csv', null) as x2 \gset
select tt.chk('T4 csv: header + 3 rows, formula guard (leading =) and quoting of the comma', array_length(string_to_array(:'x2'::jsonb->>'csv', E'\n'),1)=4 and (:'x2'::jsonb->>'csv') like '%"''=A1, x"%' and (:'x2'::jsonb->>'csv') like 'id,receipt,sale_date,%');
select bi_export('sales', tt.today(), tt.today(), null, 'json', 2) as x3 \gset
select tt.chk('T4 row cap: limit 2 -> 2 rows and truncated = true', (:'x3'::jsonb->>'row_count')::int=2 and (:'x3'::jsonb->>'truncated')::boolean and jsonb_array_length(:'x3'::jsonb->'rows')=2);
select bi_export('sale_lines', tt.today(), tt.today(), 1, 'json', null) as x4 \gset
select tt.chk('T4 sale_lines: one row per sale line (4 lines in all: the delivered order has a delivery-charge line)', (:'x4'::jsonb->>'row_count')::int=4);
select tt.err('T4 more than 366 days refused', format($$select bi_export('sales','%s','%s',null,'json',null)$$, tt.today()-400, tt.today()), 'bad_date');
select tt.err('T4 from after to refused', format($$select bi_export('sales','%s','%s',null,'json',null)$$, tt.today(), tt.today()-1), 'bad_date');
select tt.err('T4 unknown dataset refused', format($$select bi_export('users','%s','%s',null,'json',null)$$, tt.today(), tt.today()), 'bad_dataset');
select tt.err('T4 unknown format refused', format($$select bi_export('sales','%s','%s',null,'xml',null)$$, tt.today(), tt.today()), 'bad_format');
select tt.err('T4 another place refused', format($$select bi_export('sales','%s','%s',2,'json',null)$$, tt.today(), tt.today()), 'not allowed for this location');
select tt.err('T4 purchases carry cost prices: refused without the cost right', format($$select bi_export('purchases','%s','%s',null,'json',null)$$, tt.today(), tt.today()), 'cost_not_allowed');
select tt.err('T4 journal needs the accounts right', format($$select bi_export('journal','%s','%s',null,'json',null)$$, tt.today(), tt.today()), 'not allowed');
select bi_export('stock_ledger', tt.today(), tt.today(), 1, 'json', null) as x5 \gset
select tt.chk('T4 stock ledger without the cost right: rows present, unit_cost blank on every row, cost_visible false',
  (:'x5'::jsonb->>'row_count')::int>=4 and not (:'x5'::jsonb->>'cost_visible')::boolean and (select bool_and(z->'unit_cost' = 'null'::jsonb) from jsonb_array_elements(:'x5'::jsonb->'rows') z));
select tt.as(:'o');
select bi_export('stock_ledger', tt.today(), tt.today(), 1, 'json', null) as x6 \gset
select tt.chk('T4 owner sees unit_cost in the stock ledger (opening 40)', (:'x6'::jsonb->>'cost_visible')::boolean and exists (select 1 from jsonb_array_elements(:'x6'::jsonb->'rows') z where (z->>'unit_cost')::numeric=40));
select bi_export('purchases', tt.today(), tt.today(), null, 'csv', null) as x7 \gset
select bi_export('journal', tt.today(), tt.today(), null, 'json', null) as x8 \gset
select tt.chk('T4 owner can export purchases (csv) and the journal (json)', (:'x7'::jsonb->>'csv') like 'bill_id,%' and (:'x8'::jsonb->>'dataset')='journal');
select set_rule('bi_export_max_rows','100') is null as r5 \gset
select tt.chk('T4 the rule cap wins over a bigger limit (cap 100)', (bi_export('sales', tt.today(), tt.today(), null, 'json', 99999)->>'cap')::int=100);
select tt.chk('T4 every successful call is logged, denied ones are not (owner 4 incl. the cap test, user e 5)', (select count(*) from bi_export_log where user_id=:'e')=5 and (select count(*) from bi_export_log where user_id=:'o')=4
  and jsonb_array_length(bi_export_log_list(50))=9);
select tt.err('T4 the log is append-only', $$update bi_export_log set row_count=0$$, 'append_only');
select tt.err('T4 the log cannot be deleted', $$delete from bi_export_log$$, 'append_only');
select tt.as(:'e');
select tt.err('T4 only the owner reads the export log', $$select bi_export_log_list(10)$$, 'not allowed');

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
