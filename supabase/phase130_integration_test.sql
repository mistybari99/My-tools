-- FRESH DB ONLY (full canonical build 72..129). Integration test (Group ERP): with org_scope_on ON and two extra businesses
-- (HW = hardware/paint dealer, IE = import-export) the functions of phases 124-129 stay isolated, and with the switch OFF again the owner's numbers are identical.
-- Adds NO SQL phase (test only).   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase130_integration_test.sql | grep -E 'FAIL|RESULT'
\i tests/sql/e2e/00_common.sql
\set hwm '00000000-0000-0000-0000-000000000301'
\set iem '00000000-0000-0000-0000-000000000302'
\set swm '00000000-0000-0000-0000-000000000303'
create function pg_temp.cnt(q text) returns int language plpgsql as $f$ declare n int; begin execute 'select count(*) from (' || q || ') z' into n; return n; exception when others then return 0; end $f$;
\echo == T0 setup
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@i130.app','{"full_name":"Owner"}'),(:'hwm','hwm@i130.app','{"full_name":"HwMgr"}'),(:'iem','iem@i130.app','{"full_name":"IeMgr"}'),(:'swm','swm@i130.app','{"full_name":"SweetsMgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'hwm','salesperson'),(:'iem','salesperson'),(:'swm','salesperson') on conflict do nothing;
select tt.as(:'o');
select org_unit_save(null,(select id from org_units where kind='group'),'legal_entity','LE-I130','ক','Co 130',null,null,null,null,'BDT','Asia/Dhaka','{}'::jsonb,'{"owner_pct":100}'::jsonb,'00000000-0000-0000-0000-0000000130a1') ->> 'id' as le \gset
select org_unit_save(null,:'le'::bigint,'business','HW','হার্ডওয়্যার','Hardware','hardware_paint','active',null,null,'BDT','Asia/Dhaka','{}'::jsonb,null,'00000000-0000-0000-0000-0000000130a2') ->> 'id' as hwb \gset
select org_unit_save(null,:'le'::bigint,'business','IE','আমদানি','ImpExp','import_export','active',null,null,'BDT','Asia/Dhaka','{}'::jsonb,null,'00000000-0000-0000-0000-0000000130a3') ->> 'id' as ieb \gset
select id as swb from org_units where code='SWEETS' \gset
insert into locations (code,name_bn,name_en,kind,org_unit_id) values ('hw1','হার্ড','Hardware 1','showroom',:'hwb'::bigint),('ie1','আম','IE 1','showroom',:'ieb'::bigint);
select id as hw1 from locations where code='hw1' \gset
select id as ie1 from locations where code='ie1' \gset
insert into user_locations values (:'hwm',:hw1),(:'iem',:ie1),(:'swm',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) select :'hwm', g, :hw1 from unnest(array['variants_manage','dealer_cheque_manage','dealer_cheque_view','dealer_scheme_manage','dealer_scheme_view','dealer_tint_manage','dealer_tint_view','dealer_tint_run']) g;
insert into user_grants (user_id, grant_code, location_id) values (:'iem','impexp_manage',:ie1),(:'iem','impexp_view',:ie1);
insert into user_grants (user_id, grant_code, location_id) select :'swm', g, 1 from unnest(array['variants_manage','dealer_cheque_manage','dealer_scheme_manage','dealer_tint_manage','impexp_manage']) g;
select org_scope_grant(:'hwm'::uuid,:'hwb'::bigint,'management','hw mgr',gen_random_uuid());
select org_scope_grant(:'iem'::uuid,:'ieb'::bigint,'management','ie mgr',gen_random_uuid());
update rules set value='true'::jsonb where key in ('impexp_on','variants_on','dealer_cheque_on','dealer_scheme_on','dealer_tint_on');
-- data in each business (owner)
select currency_save(:'ieb'::bigint,'USD','ডলার','US dollar',2,true,gen_random_uuid());
select fx_rate_set(:'ieb'::bigint,'USD',110.5,date '2026-01-01','jan',gen_random_uuid());
select shipment_save(:'ieb'::bigint,null,'import','R-130','Test','USD',1000,null,current_date,null,null,0,0,0,0,gen_random_uuid());
insert into items (code,name_bn,sell_price,org_unit_id,tracked) values ('HW-I1','রং এক',100,:'hwb'::bigint,true),('HW-I2','রং দুই',200,:'hwb'::bigint,true),('IE-I1','পণ্য',50,:'ieb'::bigint,true);
insert into customers (id,mobile,name) values ('00000000-0000-0000-0000-00000000f001','01700013001','Cust130');
insert into suppliers (id,name,opening_balance) values ('00000000-0000-0000-0000-00000000f101','Principal130',0);
select cheque_register(gen_random_uuid(),:hw1,'received','customer','00000000-0000-0000-0000-00000000f001',null,'Bank','Br','C130-1',500,tt.today(),tt.today());
select scheme_save(null,gen_random_uuid(),:'hwb'::bigint,'00000000-0000-0000-0000-00000000f101','S130','slab','purchase','value',tt.today()-30,tt.today()+30,'{}','{}','[{"from":0,"to":null,"rate":1}]');
select tint_formula_save(gen_random_uuid(),:'hwb'::bigint,'BR-130','Brick',(select id from items where code='HW-I1'),'4L',1,jsonb_build_array(jsonb_build_object('item',(select id from items where code='HW-I2'),'qty',5)),'x');
-- OFF snapshot (owner)
create temp table k0 as select (select count(*) from cheque_list(null)) ch, (select count(*) from shipments_list(:'ieb'::bigint,null,null,100)) sh, (select count(*) from scheme_list(:'hwb'::bigint,null)) sc, (select count(*) from tint_formula_list(:'hwb'::bigint,null,null)) tf,
  (select (items_search(:'hwb'::bigint,null,'{}',50,0)->>'total')::int) hwitems, (select count(*) from items) allitems, (select md5(acct_trial_balance(null,null)::text)) tb;
select ch,sh,sc,tf,hwitems from k0;
select tt.t('T0 data exists in both businesses', (select ch=1 and sh=1 and sc=1 and tf=1 and hwitems=2 from k0));

\echo == T1 org_scope_on ON
update rules set value='true'::jsonb where key='org_scope_on';
select tt.t('T1 org_scope_on is ON', rule_on('org_scope_on'));
select tt.as(:'hwm');
select tt.eq('T1 HW manager: own cheque visible', 1, (select count(*) from cheque_list(null)));
select tt.eq('T1 HW manager: own scheme', 1, (select count(*) from scheme_list(:'hwb'::bigint,null)));
select tt.eq('T1 HW manager: own tint formula', 1, (select count(*) from tint_formula_list(:'hwb'::bigint,null,null)));
select tt.eq('T1 HW manager: items_search of HW finds the 2 HW items', 2, (items_search(:'hwb'::bigint,null,'{}',50,0)->>'total')::int);
select tt.err('T1 HW manager cannot read IE shipments', format($q$select * from shipments_list(%s,null,null,50)$q$,:'ieb'), 'not allowed');
select tt.err('T1 HW manager cannot save a shipment in IE', format($q$select shipment_save(%s,null,'import','X','x','USD',1,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'ieb'), 'not allowed');
select tt.err('T1 HW manager cannot search IE items', format($q$select items_search(%s,null,'{}',50,0)$q$,:'ieb'), 'not allowed');
select tt.err('T1 HW manager cannot read IE variants overview', format($q$select variants_overview(%s)$q$,:'ieb'), 'not allowed');
select tt.err('T1 HW manager cannot register a cheque at the IE place', format($q$select cheque_register(gen_random_uuid(),%s,'received','other',null,'x','B','','Z1',5,tt.today())$q$,:ie1), 'not allowed');
set role authenticated;
select tt.t('T1 direct select: HW manager sees only HW items among the two new businesses', (select count(*) from items where code like 'IE-%') = 0 and (select count(*) from items where code like 'HW-%') = 2);
reset role;
select tt.as(:'iem');
select tt.eq('T1 IE manager: own shipment', 1, (select count(*) from shipments_list(:'ieb'::bigint,null,null,50)));
select tt.eq('T1 IE manager: no dealer cheque', 0, pg_temp.cnt('select * from cheque_list(null)'));
select tt.eq('T1 IE manager: no scheme', 0, pg_temp.cnt(format('select * from scheme_list(%s,null)',:'hwb')));
select tt.eq('T1 IE manager: no tint formula', 0, pg_temp.cnt(format('select * from tint_formula_list(%s,null,null)',:'hwb')));
select tt.err('T1 IE manager cannot search HW items', format($q$select items_search(%s,null,'{}',50,0)$q$,:'hwb'), 'not allowed');
set role authenticated;
select tt.t('T1 direct select: IE manager sees no HW item', (select count(*) from items where code like 'HW-%') = 0);
reset role;
select tt.as(:'swm');
select tt.eq('T1 sweets manager (with every grant): no cheque', 0, pg_temp.cnt('select * from cheque_list(null)'));
select tt.err('T1 sweets manager cannot read IE shipments', format($q$select * from shipments_list(%s,null,null,50)$q$,:'ieb'), 'not allowed');
select tt.eq('T1 sweets manager: no scheme', 0, pg_temp.cnt(format('select * from scheme_list(%s,null)',:'hwb')));
select tt.eq('T1 sweets manager: no tint formula', 0, pg_temp.cnt(format('select * from tint_formula_list(%s,null,null)',:'hwb')));
select tt.err('T1 sweets manager cannot search HW items', format($q$select items_search(%s,null,'{}',50,0)$q$,:'hwb'), 'not allowed');
set role authenticated;
select tt.t('T1 direct select: sweets manager sees no HW / IE item', (select count(*) from items where code like 'HW-%' or code like 'IE-%') = 0);
reset role;

\echo == T2 owner sees everything with the switch ON, same numbers as OFF
select tt.as(:'o');
select tt.t('T2 owner numbers with the switch ON equal the OFF snapshot', (select ch = (select count(*) from cheque_list(null)) and sh = (select count(*) from shipments_list(:'ieb'::bigint,null,null,100)) and sc = (select count(*) from scheme_list(:'hwb'::bigint,null))
  and tf = (select count(*) from tint_formula_list(:'hwb'::bigint,null,null)) and hwitems = (select (items_search(:'hwb'::bigint,null,'{}',50,0)->>'total')::int) and allitems = (select count(*) from items) and tb = (select md5(acct_trial_balance(null,null)::text)) from k0));

\echo == T3 switch OFF again: nothing changed by having used it
update rules set value='false'::jsonb where key='org_scope_on';
select tt.t('T3 org_scope_on is OFF', not rule_on('org_scope_on'));
select tt.t('T3 owner numbers identical to the first snapshot', (select ch = (select count(*) from cheque_list(null)) and sh = (select count(*) from shipments_list(:'ieb'::bigint,null,null,100)) and sc = (select count(*) from scheme_list(:'hwb'::bigint,null))
  and tf = (select count(*) from tint_formula_list(:'hwb'::bigint,null,null)) and allitems = (select count(*) from items) and tb = (select md5(acct_trial_balance(null,null)::text)) from k0));
select tt.as(:'swm');
select tt.eq('T3 OFF: sweets manager sees no dealer cheque (phase 127 has its own business gate)', 0, (select count(*) from cheque_list(null)));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;

