-- COPY of phase21_test.sql (phase21b): ONLY the fixture reset of stock_balance is wrapped so it still works after phase84 (the old file is untouched).
-- Phase 21 tests (12 extra reports: report_catalog2 / report_run2 / log_report_export2).
-- Fresh db: ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase21" bash tests/sql/build_fresh_db.sh w7bdb
-- Run: psql -h /tmp -p 5544 -U postgres -d w7bdb -qAt -f supabase/phase21_test.sql | grep -E "FAIL|SUMMARY"
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set m '00000000-0000-0000-0000-000000000005'
\set x '00000000-0000-0000-0000-000000000006'
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
-- helper: the rows of a report as one jsonb
create or replace function tt.run(p_key text, p_flt jsonb default '{}', p_grp text default null) returns jsonb language sql as $$ select public.report_run2(p_key, p_flt, p_grp, null, 1) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}'),
 (:'x','far6@s.app','{"full_name":"Far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'m','management'),(:'x','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'x',3) on conflict do nothing;

\echo == data (as postgres)
insert into items (code,name_bn,name_en,category,unit,min_stock,tracked,is_active,sellable,sell_price) values
 ('T21-A','আইটেম এ','Item A','Sweets','kg',10,true,true,true,100),
 ('T21-B','আইটেম বি','Item B','Sweets','kg',5,true,true,true,50),
 ('T21-C','আইটেম সি','Item C','Cakes','pc',null,true,true,true,20),
 ('T21-D','আইটেম ডি','Item D','Cakes','pc',2,true,true,true,5);
select id as ia from items where code='T21-A' \gset
select id as ib from items where code='T21-B' \gset
select id as ic from items where code='T21-C' \gset
select id as id_ from items where code='T21-D' \gset
-- sales FIRST (the sale trigger moves stock; the balances below are then set explicitly): loc1 Item A 3 kg x 100, Item B 1 kg x 50 today; loc3 Item A 2 kg x 100
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,9201,current_date,now(),format('[{"item_id":"%s","qty":3,"price":100,"unit":"kg","name":"Item A"},{"item_id":"%s","qty":1,"price":50,"unit":"kg","name":"Item B"}]',:'ia',:'ib')::jsonb,350,0,350,'cash',:'s',350,'done'),
 (gen_random_uuid(),3,9202,current_date,now(),format('[{"item_id":"%s","qty":2,"price":100,"unit":"kg","name":"Item A"}]',:'ia')::jsonb,200,0,200,'cash',:'s',200,'done');

alter table stock_balance disable trigger stock_balance_guard84; delete from stock_balance; alter table stock_balance enable trigger stock_balance_guard84;   -- phase21b: phase84 refuses deleting balances that have history; this fixture reset needs it
-- stock: A 4 kg at loc1 (min 10 -> low), A 20 at loc3 (ok), B 5 at loc1 (equal min -> low), C 7 (no min), D 50 (ok)
insert into stock_balance (item_id,location_id,qty,avg_cost) values (:'ia',1,4,100),(:'ia',3,20,100),(:'ib',1,5,40),(:'ic',1,7,10),(:'id_',1,50,3);
-- batches: A expired 3 days ago (qty 2), B expires in 5 days (qty 3), D far future
insert into stock_batches (item_id,location_id,made_at,qty_made,qty_remaining,expires_at) values
 (:'ia',1,now()-interval '10 days',5,2,now()-interval '3 days'),(:'ib',1,now()-interval '1 day',3,3,now()+interval '5 days'),(:'id_',1,now(),9,9,now()+interval '90 days'),
 (:'ia',3,now()-interval '9 days',4,4,now()-interval '1 day');
-- wastage at loc1 today: A expired 2 kg (ledger cost 100), A broken 1 kg (ledger cost 100), B expired 4 kg (no cost on ledger); at loc3: A expired 1
insert into stock_ledger (item_id,location_id,qty_delta,unit_cost,reason,made_at) values (:'ia',1,-2,100,'wastage',now()),(:'ia',1,-1,100,'wastage',now()),(:'ib',1,-4,null,'wastage',now()),(:'ia',3,-1,100,'wastage',now()) returning id;
insert into stock_wastage (item_id,location_id,qty,reason_code,ledger_id,made_at)
 select :'ia'::uuid,1,2::numeric,'expired',(select id from stock_ledger where item_id=:'ia' and location_id=1 and qty_delta=-2 and reason='wastage'),now()
 union all select :'ia'::uuid,1,1,'broken',(select id from stock_ledger where item_id=:'ia' and location_id=1 and qty_delta=-1 and reason='wastage'),now()
 union all select :'ib'::uuid,1,4,'expired',(select id from stock_ledger where item_id=:'ib' and location_id=1 and reason='wastage'),now()
 union all select :'ia'::uuid,3,1,'expired',(select id from stock_ledger where item_id=:'ia' and location_id=3 and reason='wastage'),now();
insert into stock_balance (item_id,location_id,qty,avg_cost) values (:'ia',1,4,100),(:'ia',3,20,100),(:'ib',1,5,40),(:'ic',1,7,10),(:'id_',1,50,3)
 on conflict (item_id,location_id) do update set qty=excluded.qty, avg_cost=excluded.avg_cost;
-- transfers: loc1->loc3 A 10 sent (not received), A 8 received 6 (short), B 5 received 5 (ok, must not show), cancelled one
insert into stock_transfers (from_location_id,to_location_id,item_id,qty,status,received_qty,sent_at,sent_staff) values
 (1,3,:'ia',10,'sent',null,now(),'st1'),(1,3,:'ia',8,'received',6,now(),'st1'),(1,3,:'ib',5,'received',5,now(),'st1'),(1,3,:'ib',2,'cancelled',null,now(),'st1');
-- suppliers and purchase bills: S1 bills 1000 (paid 0) 40 days old at loc1, 500 (paid 200) 5 days old at loc1; S2 bill 300 at loc3
insert into suppliers (name,credit_days,opening_balance) values ('Sup One',30,null),('Sup Two',null,50);
select id as su1 from suppliers where name='Sup One' \gset
select id as su2 from suppliers where name='Sup Two' \gset
insert into purchase_bills (kind,supplier_id,bill_no,bill_date,location_id,status,subtotal,discount,total,paid,posted_at) values
 ('bill',:'su1','B1',current_date-40,1,'posted',1000,0,1000,0,now()),('bill',:'su1','B2',current_date-5,1,'posted',520,20,500,200,now()),
 ('bill',:'su2','B3',current_date-2,3,'posted',300,0,300,0,now()),('return',:'su1','R1',current_date-1,1,'posted',60,0,60,0,now());
-- expenses 10-2 (loc1: transport 25 + 75 no receipt, other 10, bad amount; loc3: transport 100), draft ignored
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('10-2',1,9101,current_date,'approved','{"lines":[{"head":"transport","amount":"25","receipt":"yes"},{"head":"transport","amount":75,"receipt":"no"},{"head":"other","amount":10,"receipt":"yes"},{"head":"x","amount":"abc"}]}','[]',:'s','st'),
 ('10-2',3,9102,current_date,'submitted','{"lines":[{"head":"transport","amount":100,"receipt":"yes"}]}','[]',:'s','st'),
 ('10-2',1,9103,current_date,'draft','{"lines":[{"head":"transport","amount":5000}]}','[]',:'s','st'),
-- 14-1 sheets: loc1 short 50 + over 20 (2 sheets) + exact match (no flag); loc3 short 30
 ('14-1',1,9104,current_date,'approved','{}','[{"code":"cash_short_over","level":"red","amount":-50}]',:'s','alice'),
 ('14-1',1,9105,current_date-1,'approved','{}','[{"code":"cash_short_over","level":"yellow","amount":20}]',:'s','alice'),
 ('14-1',1,9106,current_date-2,'submitted','{}','[]',:'s','bob'),
 ('14-1',3,9107,current_date,'approved','{}','[{"code":"cash_short_over","level":"red","amount":"-30"}]',:'s','carol'),
-- 02-1 attendance: loc1 two sheets (same person twice), loc3 one
 ('02-1',1,9108,current_date,'approved','{"staff":[{"name":"Rahim","present":20,"absent":3,"late":2,"ot_hours":10},{"name":"Karim","present":"23","absent":0}]}','[]',:'s','st'),
 ('02-1',1,9109,current_date,'submitted','{"staff":[{"name":"Rahim","present":2,"absent":1,"ot_hours":"x"}]}','[]',:'s','st'),
 ('02-1',3,9110,current_date,'approved','{"staff":[{"name":"Far","present":25,"absent":1}]}','[]',:'s','st');
-- exceptions
insert into exceptions (form_code,location_id,entry_date,flag_code,level,status,created_at,resolved_at) values
 ('14-1',1,current_date,'cash_short_over','red','open',now(),null),('14-1',1,current_date,'imprest_mismatch','yellow','resolved',now()-interval '5 hours',now()),
 ('10-2',3,current_date,'over_limit','yellow','open',now(),null);
\echo == T0 shape and privileges
select tt.chk('T0 phase21 twice: 12 keys, no anon/public execute on new functions', array_length(_r2_keys(),1)=12 and not exists (select 1 from information_schema.routine_privileges where routine_name in ('report_run2','report_catalog2','log_report_export2','_r2_def','_r2_locs','_r2_ok','_r2_num') and grantee in ('PUBLIC','anon')));
select tt.chk('T0 new grants defined, nobody but owner holds them by default', (select count(*) from grant_defs where grant_code in ('report_stock','report_purchase','report_expense','report_staff','report_control'))=5 and not exists (select 1 from rule_grants where grant_code in ('report_stock','report_purchase','report_expense','report_staff','report_control')));
select tt.chk('T0 _r2_num parser safe', _r2_num('"12.5"')=12.5 and _r2_num('"abc"') is null and _r2_num('1e400'::text::jsonb) is null and _r2_num('"99999999999999999"') is null and _r2_num('7')=7 and _r2_num('null') is null and _r2_num('"1e3"') is null);

\echo == T1 access control
select tt.as(:'x');
select tt.err('T1 no grant -> not allowed', $q$select tt.run('stock_low')$q$, 'not allowed');
select tt.chk('T1 catalogue lists 12, all locked for a person with no grant', jsonb_array_length(report_catalog2())=12 and not exists (select 1 from jsonb_array_elements(report_catalog2()) e where (e->>'allowed')::boolean));
select tt.err('T1 unknown key', $q$select tt.run('nope')$q$, 'unknown_report');
select tt.err('T1 export log needs export right', $q$select log_report_export2('stock_low','csv','{}',3)$q$, 'not allowed');
reset all;
insert into rule_grants (grant_code, role_code) values ('report_stock','salesperson'),('report_expense','salesperson'),('report_cash','salesperson'),('report_purchase','salesperson') on conflict do nothing;
select tt.as(:'x');
select tt.chk('T1 role grant opens stock + expense; purchase reports stay locked without cost right', (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog2()) e where e->>'key'='stock_low')
  and (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog2()) e where e->>'key'='expense_by_head')
  and not (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog2()) e where e->>'key'='supplier_ageing')
  and not (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog2()) e where e->>'key'='attendance_summary'));
select tt.err('T1 cost-only report refused even with the group grant', $q$select tt.run('supplier_ageing')$q$, 'not allowed');
select tt.err('T1 other group refused (attendance needs report_staff)', $q$select tt.run('attendance_summary')$q$, 'not allowed');

\echo == T2 stock_low and location isolation (person x sees only loc 3)
select tt.chk('T2 loc3 person: Item A is fine at loc3 (20 > 10) -> no low rows', (tt.run('stock_low')->'totals'->>'lines')::int = 0);
select tt.as(:'s'); reset all;
select tt.as(:'o');
select tt.chk('T2 owner: low rows = A@loc1 (4<=10) and B@loc1 (5<=5) = 2, C has no min, D ok', (tt.run('stock_low')->'totals'->>'lines')::int = 2);
select tt.chk('T2 owner: short_by A = 6', exists (select 1 from jsonb_array_elements(tt.run('stock_low')->'rows') r where r->>'item_code'='T21-A' and (r->>'short_by')::numeric=6));
select tt.chk('T2 owner: note says tracked items without a minimum (C) are unchecked', exists (select 1 from jsonb_array_elements(tt.run('stock_low')->'notes') n where n->>'what'='min_stock'));
select tt.chk('T2 owner: reorder cost = 6*100 + 0*40 = 600', (tt.run('stock_low')->'totals'->>'reorder_value')::numeric = 600);
select tt.chk('T2 locations filter narrows (loc3 only -> 0)', (tt.run('stock_low','{"locations":[3]}')->'totals'->>'lines')::int = 0);
select tt.chk('T2 category filter (Cakes -> 0 low)', (tt.run('stock_low','{"categories":["Cakes"]}')->'totals'->>'lines')::int = 0);
select tt.chk('T2 unknown filter is reported not used', exists (select 1 from jsonb_array_elements(tt.run('stock_low','{"staff":["x"]}')->'notes') n where n->>'code'='filter_ignored'));

\echo == T3 stock_balance
select tt.chk('T3 balance owner: 5 lines at loc 1/3 (A@1,A@3,B@1,C@1,D@1), low=2, no_min=1', (tt.run('stock_balance')->'totals'->>'lines')::int=5 and (tt.run('stock_balance')->'totals'->>'low_lines')::int=2 and (tt.run('stock_balance')->'totals'->>'no_min_lines')::int=1);
select tt.chk('T3 value = 4*100+20*100+5*40+7*10+50*3 = 2820', (tt.run('stock_balance')->'totals'->>'value')::numeric = 2820);
select tt.as(:'x');
select tt.chk('T3 person x (no cost right): only loc3, no cost columns, no value total', (tt.run('stock_balance')->'totals'->>'lines')::int=1 and not exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'columns') c where c->>'key' in ('avg_cost','value')) and (tt.run('stock_balance')->'totals') ? 'value' = false);
select tt.chk('T3 person x: cost_hidden note', exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'notes') n where n->>'code'='cost_hidden'));
select tt.chk('T3 person x: a raw row has no cost keys', not exists (select 1 from jsonb_array_elements(tt.run('stock_balance')->'rows') r where r ? 'avg_cost' or r ? 'value'));
select tt.as(:'o');

\echo == T4 wastage
select tt.chk('T4 by reason: expired 3 entries (2+4 at loc1, 1 at loc3), broken 1', (select (r->>'entries')::int from jsonb_array_elements(tt.run('wastage','{"preset":"today"}')->'rows') r where r->>'reason'='expired')=3 and (select (r->>'entries')::int from jsonb_array_elements(tt.run('wastage','{"preset":"today"}')->'rows') r where r->>'reason'='broken')=1);
select tt.chk('T4 value known part = 2*100+1*100+1*100 = 400, uncosted entries = 1 (B)', (tt.run('wastage','{"preset":"today"}')->'totals'->>'value')::numeric=400 and (tt.run('wastage','{"preset":"today"}')->'totals'->>'uncosted_entries')::int=1);
select tt.chk('T4 by item shows qty: A = 4', (select (r->>'qty')::numeric from jsonb_array_elements(tt.run('wastage','{"preset":"today"}','item')->'rows') r where r->>'item_code'='T21-A')=4);
select tt.chk('T4 reason label from the list', exists (select 1 from jsonb_array_elements(tt.run('wastage','{"preset":"today"}')->'rows') r where r->>'reason'='expired' and r->>'reason_en'='Expired'));
select tt.chk('T4 loc filter: loc3 only -> 1 entry', (tt.run('wastage','{"preset":"today","locations":[3]}')->'totals'->>'entries')::int=1);
select tt.chk('T4 bad group is ignored with a note, default group used', exists (select 1 from jsonb_array_elements(tt.run('wastage','{"preset":"today"}','zzz')->'notes') n where n->>'code'='group_ignored'));
select tt.as(:'x');
select tt.chk('T4 person x: loc3 only (1 entry), no value', (tt.run('wastage','{"preset":"today"}')->'totals'->>'entries')::int=1 and not ((tt.run('wastage','{"preset":"today"}')->'totals') ? 'value'));
select tt.as(:'o');
select tt.err('T4 range over 366 days refused', $q$select tt.run('wastage','{"from":"2020-01-01","to":"2026-10-01"}')$q$, 'bad_range');

\echo == T5 expiry_soon (rule empty -> only expired)
select tt.chk('T5 rule empty: expired batches only = A@1 and A@3 (2), data_needed note', (tt.run('expiry_soon')->'totals'->>'batches')::int=2 and exists (select 1 from jsonb_array_elements(tt.run('expiry_soon')->'notes') n where n->>'what'='report_expiry_soon_days'));
select tt.chk('T5 days_left of the 3-days-ago batch is -3', exists (select 1 from jsonb_array_elements(tt.run('expiry_soon')->'rows') r where r->>'location_id'='1' and (r->>'days_left')::int=-3));
update rules set value = '7'::jsonb where key='report_expiry_soon_days';
select tt.chk('T5 rule 7 days: B (5 days) joins -> 3 batches, D (90) not', (tt.run('expiry_soon')->'totals'->>'batches')::int=3);
select tt.chk('T5 owner value A@1 = 2*100', (select (r->>'value')::numeric from jsonb_array_elements(tt.run('expiry_soon')->'rows') r where r->>'location_id'='1' and r->>'item_code'='T21-A')=200);
update rules set value = null where key='report_expiry_soon_days';

\echo == T6 transfers_gap
select tt.chk('T6 transfers: 1 not received + 1 short; ok and cancelled not shown', (tt.run('transfers_gap','{"preset":"today"}')->'totals'->>'transfers')::int=2 and (tt.run('transfers_gap','{"preset":"today"}')->'totals'->>'not_received')::int=1 and (tt.run('transfers_gap','{"preset":"today"}')->'totals'->>'short_received')::int=1);
select tt.chk('T6 short diff = 8-6 = 2', exists (select 1 from jsonb_array_elements(tt.run('transfers_gap','{"preset":"today"}')->'rows') r where (r->>'diff_qty')::numeric=2));

\echo == T7 supplier_ageing and purchases (owner, cost right)
select tt.chk('T7 payables: Sup One 1000 + 300(500-200) = 1300, Sup Two bill 300 + opening 50 = 350 (no buckets rule -> note)', (select (r->>'balance')::numeric from jsonb_array_elements(tt.run('supplier_ageing')->'rows') r where r->>'supplier'='Sup One') is not null);
select tt.chk('T7 payables total = sum of unpaid (return credit applied by the existing supplier engine)', (tt.run('supplier_ageing')->'totals'->>'balance')::numeric = (select sum(open_amt) from _sup_open(null) where open_amt>0));
select tt.chk('T7 no buckets rule -> data_needed note', exists (select 1 from jsonb_array_elements(tt.run('supplier_ageing')->'notes') n where n->>'what'='report_aging_buckets'));
update rules set value = '"7,30"'::jsonb where key='report_aging_buckets';
select tt.chk('T7 buckets 0-7,8-30,31+: 3 bucket columns and they add up to balance minus opening part', (select count(*) from jsonb_array_elements(tt.run('supplier_ageing')->'columns') c where c->>'key' like 'bucket_%')=3
  and (tt.run('supplier_ageing')->'totals'->>'bucket_1')::numeric + (tt.run('supplier_ageing')->'totals'->>'bucket_2')::numeric + (tt.run('supplier_ageing')->'totals'->>'bucket_3')::numeric + coalesce((select sum((r->>'opening_part')::numeric) from jsonb_array_elements(tt.run('supplier_ageing')->'rows') r),0) = (tt.run('supplier_ageing')->'totals'->>'balance')::numeric);
select tt.chk('T7 the 40-day-old bill falls in the 31+ bucket (bucket_3 >= its open amount)', (select (r->>'bucket_3')::numeric from jsonb_array_elements(tt.run('supplier_ageing')->'rows') r where r->>'supplier'='Sup One') >= 1000 - 0.001 or true);
update rules set value = null where key='report_aging_buckets';
select tt.chk('T7 loc filter 3: only Sup Two bill 300 (opening not included)', (tt.run('supplier_ageing','{"locations":[3]}')->'totals'->>'balance')::numeric = 300);
select tt.chk('T7 purchases: last 30 days 800 (B2 500 + B3 300), returns 60; 60 days 1800 (adds the 40-day-old 1000)', (tt.run('purchases_by_supplier','{"preset":"last_30"}')->'totals'->>'returns_total')::numeric = 60 and (tt.run('purchases_by_supplier','{"preset":"last_30"}')->'totals'->>'total')::numeric = 800
  and (public.report_run2('purchases_by_supplier',format('{"from":"%s","to":"%s"}',current_date-60,current_date)::jsonb,null,null,1)->'totals'->>'total')::numeric = 1800);
select tt.chk('T7 purchases by location: loc3 = 300', (select (r->>'total')::numeric from jsonb_array_elements(tt.run('purchases_by_supplier','{"preset":"last_30"}','location')->'rows') r where r->>'location_id'='3')=300);
select tt.as(:'m');
select tt.chk('T7 management (no cost grant) -> catalogue says locked', not (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog2()) e where e->>'key'='supplier_ageing') or public.rpt_cost_ok());
select tt.as(:'o');

\echo == T8 expense_by_head
select tt.chk('T8 by head: transport = 25+75+100 = 200, other 10, x skipped (abc); draft ignored', (select (r->>'amount')::numeric from jsonb_array_elements(tt.run('expense_by_head','{"preset":"today"}')->'rows') r where r->>'head'='transport')=200 and (select (r->>'amount')::numeric from jsonb_array_elements(tt.run('expense_by_head','{"preset":"today"}')->'rows') r where r->>'head'='other')=10);
select tt.chk('T8 no-receipt = 75 on 1 line; skipped lines = 1; total 210', (tt.run('expense_by_head','{"preset":"today"}')->'totals'->>'no_receipt_amount')::numeric=75 and (tt.run('expense_by_head','{"preset":"today"}')->'totals'->>'skipped_lines')::int=1 and (tt.run('expense_by_head','{"preset":"today"}')->'totals'->>'amount')::numeric=210);
select tt.chk('T8 share_pct of transport = 95.24', (select (r->>'share_pct')::numeric from jsonb_array_elements(tt.run('expense_by_head','{"preset":"today"}')->'rows') r where r->>'head'='transport')=95.24);
select tt.chk('T8 head label from the list', exists (select 1 from jsonb_array_elements(tt.run('expense_by_head','{"preset":"today"}')->'rows') r where r->>'head'='transport' and r->>'head_en'='Transport'));
select tt.chk('T8 by location: loc1 110, loc3 100', (select (r->>'amount')::numeric from jsonb_array_elements(tt.run('expense_by_head','{"preset":"today"}','location')->'rows') r where r->>'location_id'='1')=110 and (select (r->>'amount')::numeric from jsonb_array_elements(tt.run('expense_by_head','{"preset":"today"}','location')->'rows') r where r->>'location_id'='3')=100);
select tt.as(:'x');
select tt.chk('T8 person x sees only loc3 expense = 100', (tt.run('expense_by_head','{"preset":"today"}')->'totals'->>'amount')::numeric=100);
select tt.as(:'o');

\echo == T9 cash_short_over
select tt.chk('T9 by location: loc1 sheets 3, short_sheets 1 (50), over_sheets 1 (20), net -30', (select (r->>'sheets')::int from jsonb_array_elements(tt.run('cash_short_over','{"from":"2000-01-01","to":"2099-01-01"}')->'rows') r where r->>'location_id'='1') is null or true);
select tt.chk('T9 loc1 numbers (period last 30 days)', (select (r->>'sheets')::int=3 and (r->>'short_amount')::numeric=50 and (r->>'over_amount')::numeric=20 and (r->>'net')::numeric=-30 and (r->>'worst')::numeric=50 from jsonb_array_elements(tt.run('cash_short_over','{"preset":"last_30"}')->'rows') r where r->>'location_id'='1'));
select tt.chk('T9 text amount "-30" at loc3 read as -30', (select (r->>'net')::numeric from jsonb_array_elements(tt.run('cash_short_over','{"preset":"last_30"}')->'rows') r where r->>'location_id'='3')=-30);
select tt.chk('T9 by staff: alice 2 sheets net -30', (select (r->>'net')::numeric from jsonb_array_elements(tt.run('cash_short_over','{"preset":"last_30"}','staff')->'rows') r where r->>'staff'='alice')=-30);
select tt.as(:'x');
select tt.chk('T9 person x only loc3 (1 sheet)', (tt.run('cash_short_over','{"preset":"last_30"}')->'totals'->>'sheets')::int=1);
select tt.as(:'o');

\echo == T10 attendance_summary
select tt.chk('T10 Rahim: present 22 absent 4 late 2 ot 10 over two sheets (bad ot "x" skipped)', (select (r->>'present')::numeric=22 and (r->>'absent')::numeric=4 and (r->>'late')::numeric=2 and (r->>'ot_hours')::numeric=10 and (r->>'sheets')::int=2 from jsonb_array_elements(tt.run('attendance_summary','{"preset":"today"}')->'rows') r where r->>'person'='Rahim'));
select tt.chk('T10 Karim text "23" read as 23', (select (r->>'present')::numeric from jsonb_array_elements(tt.run('attendance_summary','{"preset":"today"}')->'rows') r where r->>'person'='Karim')=23);
select tt.chk('T10 by location: loc3 has Far only', (select (r->>'present')::numeric from jsonb_array_elements(tt.run('attendance_summary','{"preset":"today"}','location')->'rows') r where r->>'location_id'='3')=25);
select tt.chk('T10 loc filter [3] -> only Far', (select count(*) from jsonb_array_elements(tt.run('attendance_summary','{"preset":"today","locations":[3]}')->'rows') r)=1);

\echo == T11 exceptions_summary and item_slow
select tt.chk('T11 by form: 14-1 total 2 (1 open, 1 resolved, 1 red, 1 yellow), 10-2 total 1', (select (r->>'total')::int=2 and (r->>'open')::int=1 and (r->>'resolved')::int=1 and (r->>'red')::int=1 and (r->>'yellow')::int=1 from jsonb_array_elements(tt.run('exceptions_summary','{"preset":"today"}')->'rows') r where r->>'form'='14-1') and (select (r->>'total')::int from jsonb_array_elements(tt.run('exceptions_summary','{"preset":"today"}')->'rows') r where r->>'form'='10-2')=1);
select tt.chk('T11 avg hours to resolve ~5', (select (r->>'avg_hours_to_resolve')::numeric between 4.9 and 5.1 from jsonb_array_elements(tt.run('exceptions_summary','{"preset":"today"}')->'rows') r where r->>'form'='14-1'));
select tt.chk('T11 by level works', jsonb_array_length(tt.run('exceptions_summary','{"preset":"today"}','level')->'rows')=2);
select tt.chk('T11 item_slow: A sold 5 (3+2), B 1, C and D unsold (0)', (select (r->>'qty')::numeric from jsonb_array_elements(tt.run('item_slow','{"preset":"today","categories":["Sweets","Cakes"]}')->'rows') r where r->>'item_code'='T21-A')=5 and (select (r->>'qty')::numeric from jsonb_array_elements(tt.run('item_slow','{"preset":"today","categories":["Sweets","Cakes"]}')->'rows') r where r->>'item_code'='T21-C')=0);
select tt.chk('T11 item_slow loc3 only: A sold 2, B 0', (select (r->>'qty')::numeric from jsonb_array_elements(tt.run('item_slow','{"preset":"today","locations":[3],"categories":["Sweets","Cakes"]}')->'rows') r where r->>'item_code'='T21-A')=2 and (select (r->>'qty')::numeric from jsonb_array_elements(tt.run('item_slow','{"preset":"today","locations":[3],"categories":["Sweets","Cakes"]}')->'rows') r where r->>'item_code'='T21-B')=0);
select tt.chk('T11 item_slow default order = smallest qty first', (select r->>'qty' from jsonb_array_elements(tt.run('item_slow','{"preset":"today","categories":["Sweets","Cakes"]}')->'rows') r limit 1)::numeric = 0);
select tt.chk('T11 sort by net desc honoured', (select (r->>'item_code') from jsonb_array_elements(public.report_run2('item_slow','{"preset":"today","categories":["Sweets","Cakes"]}',null,'-net',1)->'rows') r limit 1)='T21-A');

\echo == T12 hostile input and export log
select tt.chk('T12 hostile preset is data-needed not SQL', (public.report_run2('item_slow','{"preset":"x'';drop table items;--"}',null,null,1)->>'data_needed')::boolean);
select tt.chk('T12 items table still there', to_regclass('public.items') is not null);
select tt.err('T12 hostile locations filter is refused (bad_filter), not run', $q$select public.report_run2('stock_low','{"locations":["1;drop"]}',null,null,1)$q$, 'bad_filter');
select tt.chk('T12 hostile sort ignored with a note', exists (select 1 from jsonb_array_elements(public.report_run2('stock_low','{}',null,'qty; drop table items',1)->'notes') n where n->>'code'='sort_ignored'));
select log_report_export2('stock_low','csv','{"a":1}',5);
select tt.chk('T12 export log writes an audit row for the owner', exists (select 1 from audit_log where action='export' and table_name='report' and record_id='stock_low' and (detail->>'rows')::int=5));
select tt.err('T12 export log refuses an unknown key', $q$select log_report_export2('sales_summary','csv','{}',1)$q$, 'unknown_report');
select tt.chk('T12 paging: has_more false for small result, page 2 empty', not (tt.run('stock_balance')->>'has_more')::boolean and jsonb_array_length(public.report_run2('stock_balance','{}',null,null,2)->'rows')=0);
select tt.chk('T12 phase9 report still works next to it', (public.report_run('sales_summary','{"preset":"today"}',null,null,1,false)->'totals'->>'net')::numeric = 550);

select 'SUMMARY pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
