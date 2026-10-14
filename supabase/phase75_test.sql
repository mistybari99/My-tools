-- FRESH DB ONLY. Phase 75 tests (step C-2ক: cost sources + allocation). Needs phase8..phase71, phase73, phase74, phase75.
--   ORDER="phase8 ... phase71 phase73 phase74 phase75" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 75db
--   psql -h /tmp -p 5544 -U postgres -d 75db -qAt -f supabase/phase75_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (ids and roles, no names). Months are relative to today.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set e '00000000-0000-0000-0000-000000000002'
\set a '00000000-0000-0000-0000-000000000003'
\set x '00000000-0000-0000-0000-000000000004'
\set n '00000000-0000-0000-0000-000000000005'
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
create or replace function tt.mo(p_back int) returns date language sql stable as $$ select (date_trunc('month', now() at time zone 'Asia/Dhaka') - make_interval(months => p_back))::date $$;
create or replace function tt.mf(p_fwd int) returns date language sql stable as $$ select (date_trunc('month', now() at time zone 'Asia/Dhaka') + make_interval(months => p_fwd))::date $$;
create or replace function tt.pma(p_loc int, p_month date, p_type text) returns numeric language sql security definer as $$ select public._pool_month_actual(p_loc, p_month, p_type) $$;
create or replace function tt.exc(p_flag text) returns int language sql security definer as $$ select count(*)::int from public.exceptions where flag_code = p_flag and level = 'yellow' $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'e','entry2@s.app','{"full_name":"Entry"}'), (:'a','appr3@s.app','{"full_name":"Approver"}'), (:'x','view4@s.app','{"full_name":"Viewer"}'), (:'n','none5@s.app','{"full_name":"Nobody"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'e','storekeeper'),(:'a','storekeeper'),(:'x','storekeeper'),(:'n','salesperson') on conflict do nothing;
insert into user_locations values (:'e',1),(:'e',5),(:'e',6),(:'a',1),(:'a',5),(:'a',6),(:'x',1),(:'x',5),(:'x',6),(:'n',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'e'::uuid,'view_cost') is null as g1 \gset
select set_user_grant(:'e'::uuid,'cost_bill_entry') is null as g2 \gset
select set_user_grant(:'a'::uuid,'view_cost') is null as g3 \gset
select set_user_grant(:'a'::uuid,'cost_rule_approve') is null as g4 \gset
select set_user_grant(:'x'::uuid,'view_cost') is null as g5 \gset
-- a brand new site, added later: nothing in the code knows it
insert into locations (code, name_bn, name_en, kind, sort) values ('site8', 'নতুন জায়গা', 'New site', 'factory', 8) returning id as loc8 \gset
insert into user_locations values (:'e',:loc8),(:'a',:loc8),(:'x',:loc8) on conflict do nothing;
set role authenticated; select tt.as(:'o');

\echo == T0 shape
select tt.chk('T0 eight new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('cost_source_types','cost_sources','cost_source_locs','cost_source_rules','cost_source_rule_shares','cost_source_bills','cost_bill_inputs','cost_bill_shares') and c.relrowsecurity)=8);
select tt.chk('T0 types: বিদ্যুৎ/গ্যাস/ঘর ভাড়া/লাইসেন্স/মেরামত/পানি/ইন্টারনেট/অন্য seeded, each mapped to a pool type', (select count(*) from cost_source_types where builtin)=8
  and (select component_type from cost_source_types where code='electricity')='electricity' and (select component_type from cost_source_types where code='rent')='factory_rent' and (select component_type from cost_source_types where code='water')='other');
select tt.chk('T0 everything starts BLANK: no source, no rule, no bill, no share', not exists (select 1 from cost_sources) and not exists (select 1 from cost_source_rules) and not exists (select 1 from cost_source_bills) and not exists (select 1 from cost_bill_shares));
select tt.chk('T0 grants exist; rule cost_rule_self_approve default off', (select count(*) from grant_defs where grant_code in ('cost_bill_entry','cost_rule_approve'))=2 and not rule_on('cost_rule_self_approve'));
select tt.chk('T0 anon cannot execute; helpers closed', not has_function_privilege('anon','cost_bill_add(bigint,text,date,numeric,text,text,date,boolean,jsonb,text,uuid)','execute') and not has_function_privilege('authenticated','_cs_alloc(bigint)','execute') and not has_function_privilege('authenticated','_cs_push_pools(bigint)','execute'));
select tt.chk('T0 pool_set re-created with the bos75 tag', position('bos75' in pg_get_functiondef('public.pool_set(int,date,text,numeric,text,boolean,text,uuid)'::regprocedure))>0);

\echo == T1 who may see / enter / approve
select tt.as(:'n'); select tt.err('T1 no cost right: cannot create a source', $$select cost_source_save(null,'gas',null,'separate','factory',array[5],'monthly',tt.mo(2))$$, 'not allowed');
select tt.chk('T1 no cost right: sees nothing', (select count(*) from cost_sources)=0 and (select count(*) from cost_source_types)=0);
select tt.err('T1 no cost right: status refused', $$select cost_sources_status(tt.mo(0))$$, 'not allowed');
select tt.as(:'x'); select tt.err('T1 view-only cost-right holder cannot enter a source', $$select cost_source_save(null,'gas',null,'separate','factory',array[5],'monthly',tt.mo(2))$$, 'not allowed');
select tt.chk('T1 but he can read the types', (select count(*) from cost_source_types)=8);
select tt.as(:'a'); select tt.err('T1 the approver (no entry grant) cannot enter a source', $$select cost_source_save(null,'gas',null,'separate','factory',array[5],'monthly',tt.mo(2))$$, 'not allowed');
select tt.as(:'e');

\echo == T2 separate source: straight to its destination, no allocation step
select cost_source_save(null,'gas','meter G-100','separate','factory',array[5],'monthly',tt.mo(3),null,'a0000000-0000-0000-0000-000000000001'::uuid) ->> 'id' as sg \gset
select tt.chk('T2 same client id = dup', (cost_source_save(null,'gas','meter G-100','separate','factory',array[5],'monthly',tt.mo(3),null,'a0000000-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean and (select count(*) from cost_sources)=1);
select cost_source_save(null,'internet',null,'separate','showroom',array[1],'monthly',tt.mo(3)) ->> 'id' as si \gset
select tt.err('T2 separate source needs exactly one place', $$select cost_source_save(null,'gas',null,'separate','factory',array[5,6],'monthly',tt.mo(3))$$, 'separate_one_location');
select tt.err('T2 separate source needs a destination', $$select cost_source_save(null,'gas',null,'separate',null,array[5],'monthly',tt.mo(3))$$, 'dest_needed');
select tt.err('T2 shared source needs two places', $$select cost_source_save(null,'gas',null,'shared',null,array[5],'monthly',tt.mo(3))$$, 'shared_needs_two');
select cost_bill_add(:sg, 'month', tt.mo(1), 3000, 'bank', 'B-1', tt.mo(1)+10, false, null, null, 'b0000000-0000-0000-0000-000000000001'::uuid) ->> 'id' as bg \gset
select tt.chk('T2 separate bill: ONE share, whole amount, 100%, factory at place 5, no rule needed', (select count(*) from cost_bill_shares where bill_id=:bg and active)=1 and (select amount=3000 and pct=100 and dest='factory' and location_id=5 and kind='share' and rule_id is null from cost_bill_shares where bill_id=:bg and active));
select tt.chk('T2 it landed BY ITSELF in the factory pool: gas, that month, source allocated', (select actual_amount=3000 and source='allocated' and component_type='gas' and location_id=5 and period_kind='month' from factory_cost_pools where ref='bill:'||:bg||':5' and active));
select tt.chk('T2 the pool figure for that month = 3000 (what the cost code reads)', (select tt.pma(5, tt.mo(1), 'gas'))=3000);
select cost_bill_add(:si, 'month', tt.mo(1), 1200, 'cash', 'NET-9') ->> 'id' as bi \gset
select tt.chk('T2 a showroom bill goes straight to the branch P&L side: no pool row, one showroom share', (select count(*) from factory_cost_pools where ref like 'bill:'||:bi||':%')=0 and (select dest from cost_bill_shares where bill_id=:bi and active)='showroom');
select tt.chk('T2 branch_overhead for place 1 shows internet 1200 in showroom', (select (x->>'amount')::numeric from jsonb_array_elements(branch_overhead(1, tt.mo(1), tt.mo(1))->'rows') x where x->>'dest'='showroom' and x->>'cost_type'='internet')=1200);
select tt.err('T2 same bill number twice on a source is refused', format($$select cost_bill_add(%s,'month',tt.mo(1),10,null,'B-1')$$, :sg), 'duplicate_bill');
select tt.chk('T2 same bill client id = dup, one bill', (cost_bill_add(:sg, 'month', tt.mo(1), 3000, 'bank', 'B-1', tt.mo(1)+10, false, null, null, 'b0000000-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean);

\echo == T3 shared source: percent rule (sum 100 or refused), entry person cannot approve
select cost_source_save(null,'electricity','main meter M-1','shared',null,array[1,5,6],'monthly',tt.mo(3)) ->> 'id' as se \gset
select cost_bill_add(:se, 'month', tt.mo(1), 10000, 'bank', 'E-1') as eb1 \gset
select (:'eb1'::jsonb->>'id')::bigint as be1 \gset
select tt.chk('T3 no rule yet: the whole bill is an unallocated row (no_rule), nothing reaches a pool', (select count(*) from cost_bill_shares where bill_id=:be1 and active and kind='unallocated' and flag='no_rule' and amount=10000)=1 and (select count(*) from factory_cost_pools where ref like 'bill:'||:be1||':%')=0);
select tt.chk('T3 it is on the list ভাগ নির্ধারিত নয় (split not set), and the unallocated row is listed too', exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(1))->'split_not_set') s where (s->>'source_id')::bigint=:se and s->>'label_bn'='ভাগ নির্ধারিত নয়')
  and exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(1))->'unallocated') u where (u->>'bill_id')::bigint=:be1 and u->>'label_bn'='অভাগিত'));
select tt.err('T3 percentages that do not total 100 are refused', format($$select cost_rule_save(%s,'fixed_percent',tt.mo(3),'[{"location_id":5,"dest":"factory","value":50},{"location_id":1,"dest":"showroom","value":30},{"location_id":6,"dest":"factory","value":25}]'::jsonb)$$, :se), 'percent_not_100');
select cost_rule_save(:se,'fixed_percent',tt.mo(3),'[{"location_id":5,"dest":"factory","value":50},{"location_id":1,"dest":"showroom","value":30},{"location_id":6,"dest":"factory"}]'::jsonb) ->> 'id' as rb \gset
select tt.chk('T3 a rule with a blank percentage is a draft that is NOT complete (starts blank, nothing guessed)', (select not complete and status='draft' from cost_source_rules where id=:rb));
select tt.as(:'a'); select tt.err('T3 an incomplete rule cannot be approved', format($$select cost_rule_approve(%s)$$, :rb), 'rule_incomplete');
select tt.as(:'e');
select cost_rule_save(:se,'fixed_percent',tt.mo(3),'[{"location_id":5,"dest":"factory","value":50},{"location_id":1,"dest":"showroom","value":30},{"location_id":6,"dest":"factory","value":20}]'::jsonb, 'first rule', 'c0000000-0000-0000-0000-000000000001'::uuid) ->> 'id' as r1 \gset
select tt.chk('T3 complete rule saved as a draft; same client id = dup', (select complete and status='draft' from cost_source_rules where id=:r1) and (cost_rule_save(:se,'fixed_percent',tt.mo(3),'[{"location_id":5,"dest":"factory","value":50},{"location_id":1,"dest":"showroom","value":30},{"location_id":6,"dest":"factory","value":20}]'::jsonb, 'x', 'c0000000-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean);
select tt.err('T3 the person who entered the rule cannot approve it (no approve grant)', format($$select cost_rule_approve(%s)$$, :r1), 'not allowed');
select tt.as(:'o'); select set_user_grant(:'e'::uuid,'cost_rule_approve') is null as g6 \gset
select tt.as(:'e'); select tt.err('T3 even holding the approve grant, the entry person cannot approve his own rule', format($$select cost_rule_approve(%s)$$, :r1), 'self_approve_refused');
select tt.as(:'o'); select set_user_grant(:'e'::uuid,'cost_rule_approve',null,null,false) is null as g7 \gset
select tt.as(:'a');
select cost_rule_approve(:r1::bigint, 'ok') ->> 'bills_allocated' as nba \gset
select tt.chk('T3 a different person approves; the bill that waited is now allocated (1)', :'nba'::int=1 and (select status='approved' and approved_by=:'a'::uuid from cost_source_rules where id=:r1));
select tt.as(:'e');
select tt.chk('T3 the shares: 5000 factory@5, 3000 showroom@1, 2000 factory@6 - they total the bill 10000, no unallocated row', (select sum(amount) from cost_bill_shares where bill_id=:be1 and active)=10000 and not exists (select 1 from cost_bill_shares where bill_id=:be1 and active and kind='unallocated')
  and (select amount from cost_bill_shares where bill_id=:be1 and active and location_id=5 and dest='factory')=5000 and (select amount from cost_bill_shares where bill_id=:be1 and active and location_id=1 and dest='showroom')=3000 and (select amount from cost_bill_shares where bill_id=:be1 and active and location_id=6)=2000);
select tt.chk('T3 factory shares landed in the ELECTRICITY pool of each place; the showroom share did not', (select actual_amount from factory_cost_pools where ref='bill:'||:be1||':5' and active)=5000 and (select component_type from factory_cost_pools where ref='bill:'||:be1||':5' and active)='electricity'
  and (select actual_amount from factory_cost_pools where ref='bill:'||:be1||':6' and active)=2000 and not exists (select 1 from factory_cost_pools where ref='bill:'||:be1||':1'));
select tt.chk('T3 it left the list ভাগ নির্ধারিত নয়', not exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(1))->'split_not_set') s where (s->>'source_id')::bigint=:se));

\echo == T4 one bill over three destinations sums to the bill (rounding on the last share)
select cost_source_save(null,'water',null,'shared',null,array[1,5],'monthly',tt.mo(3)) ->> 'id' as sw \gset
select cost_rule_save(:sw,'fixed_percent',tt.mo(3),'[{"location_id":5,"dest":"factory","value":40},{"location_id":5,"dest":"admin","value":10},{"location_id":1,"dest":"showroom","value":50}]'::jsonb) ->> 'id' as rw \gset
select tt.as(:'a'); select cost_rule_approve(:rw::bigint) is not null as apw \gset
select tt.as(:'e');
select (cost_bill_add(:sw, 'month', tt.mo(1), 1001, 'cash', 'W-1')->>'id')::bigint as bw \gset
select tt.chk('T4 factory 400.40 + admin 100.10 + showroom 500.50 = 1001.00 exactly', (select sum(amount) from cost_bill_shares where bill_id=:bw and active)=1001 and (select count(distinct dest) from cost_bill_shares where bill_id=:bw and active)=3
  and (select amount from cost_bill_shares where bill_id=:bw and active and dest='factory')=400.40 and (select amount from cost_bill_shares where bill_id=:bw and active and dest='admin')=100.10 and (select amount from cost_bill_shares where bill_id=:bw and active and dest='showroom')=500.50);
select tt.chk('T4 the factory share of WATER lands in the mapped pool type (other)', (select component_type from factory_cost_pools where ref='bill:'||:bw||':5' and active)='other' and (select actual_amount from factory_cost_pools where ref='bill:'||:bw||':5' and active)=400.40);
select tt.chk('T4 admin share goes to the branch side (not a pool): branch_overhead place 5 shows admin 100.10', (select (x->>'amount')::numeric from jsonb_array_elements(branch_overhead(5, tt.mo(1), tt.mo(1))->'rows') x where x->>'dest'='admin' and x->>'cost_type'='water')=100.10);

\echo == T5 a rule change applies from its effective date; earlier months do NOT change
select array_agg(id order by id) as before_ids from cost_bill_shares where bill_id=:be1 and active \gset
select cost_rule_save(:se,'fixed_percent',tt.mf(0),'[{"location_id":5,"dest":"factory","value":20},{"location_id":1,"dest":"showroom","value":30},{"location_id":6,"dest":"factory","value":50}]'::jsonb) ->> 'id' as r2 \gset
select tt.as(:'a'); select cost_rule_approve(:r2::bigint) is not null as ap2 \gset
select tt.as(:'e');
select tt.chk('T5 the old bill (last month) keeps its shares and rule: same share rows, 5000 / 3000 / 2000, rule 1', (select array_agg(id order by id) from cost_bill_shares where bill_id=:be1 and active)=:'before_ids'::bigint[] and (select amount from cost_bill_shares where bill_id=:be1 and active and location_id=5)=5000
  and (select count(*) from cost_bill_shares where bill_id=:be1 and active and rule_id=:r1)=3);
select (cost_bill_add(:se, 'month', tt.mf(0), 10000, 'bank', 'E-2')->>'id')::bigint as be2 \gset
select tt.chk('T5 the new month uses the NEW rule: 2000 / 3000 / 5000', (select amount from cost_bill_shares where bill_id=:be2 and active and location_id=5)=2000 and (select amount from cost_bill_shares where bill_id=:be2 and active and location_id=6)=5000 and (select count(*) from cost_bill_shares where bill_id=:be2 and active and rule_id=:r2)=3);
select tt.chk('T5 the old rule is kept: both rules stay approved with their own effective dates', (select count(*) from cost_source_rules where source_id=:se and status='approved')=2 and (select count(distinct effective_from) from cost_source_rules where source_id=:se and status='approved')=2);
select tt.as(:'o'); select tt.chk('T5 audit rows exist for the rules (audit log is owner-readable)', (select count(*) from audit_log where table_name='cost_source_rules')>=3); select tt.as(:'e');
select cost_rule_save(:se,'fixed_percent',tt.mo(2),'[{"location_id":5,"dest":"factory","value":10},{"location_id":1,"dest":"showroom","value":10},{"location_id":6,"dest":"factory","value":80}]'::jsonb) ->> 'id' as r3 \gset
select tt.as(:'a'); select cost_rule_approve(:r3::bigint) is not null as ap3 \gset
select tt.as(:'e');
select tt.chk('T5 approving a rule with an EARLIER effective date does not touch a fully allocated bill', (select amount from cost_bill_shares where bill_id=:be1 and active and location_id=5)=5000);
select tt.err('T5 reallocate of a fully allocated bill is refused', format($$select cost_bill_reallocate(%s)$$, :be1), 'already_allocated');

\echo == T6 the other methods
select cost_source_save(null,'rent',null,'shared',null,array[1,5],'monthly',tt.mo(3)) ->> 'id' as sr \gset
select cost_rule_save(:sr,'floor_area',tt.mo(3),'[{"location_id":5,"dest":"factory","value":3000},{"location_id":1,"dest":"showroom","value":1000}]'::jsonb) ->> 'id' as rfa \gset
select tt.as(:'a'); select cost_rule_approve(:rfa::bigint) is not null as apfa \gset
select tt.as(:'e');
select (cost_bill_add(:sr, 'month', tt.mo(1), 40000, 'bank', 'R-1')->>'id')::bigint as brn \gset
select tt.chk('T6 floor area 3000 : 1000 sq ft -> 30000 factory (pool factory_rent) / 10000 showroom', (select amount from cost_bill_shares where bill_id=:brn and active and dest='factory')=30000 and (select amount from cost_bill_shares where bill_id=:brn and active and dest='showroom')=10000
  and (select component_type from factory_cost_pools where ref='bill:'||:brn||':5' and active)='factory_rent');
select cost_source_save(null,'gas',null,'shared',null,array[5,6],'monthly',tt.mo(3)) ->> 'id' as sh \gset
select cost_rule_save(:sh,'headcount',tt.mo(3),'[{"location_id":5,"dest":"factory","value":9},{"location_id":6,"dest":"factory","value":3}]'::jsonb) ->> 'id' as rhc \gset
select tt.as(:'a'); select cost_rule_approve(:rhc::bigint) is not null as aphc \gset
select tt.as(:'e');
select (cost_bill_add(:sh, 'month', tt.mo(1), 1200, 'bank', 'GH-1')->>'id')::bigint as bhc \gset
select tt.chk('T6 headcount 9 : 3 -> 900 / 300', (select amount from cost_bill_shares where bill_id=:bhc and active and location_id=5)=900 and (select amount from cost_bill_shares where bill_id=:bhc and active and location_id=6)=300);
select cost_source_save(null,'machine_repair',null,'shared',null,array[1,5],'irregular',tt.mo(3)) ->> 'id' as s1 \gset
select cost_rule_save(:s1,'whole_to_one',tt.mo(3),'[{"location_id":5,"dest":"factory"}]'::jsonb) ->> 'id' as r1w \gset
select tt.as(:'a'); select cost_rule_approve(:r1w::bigint) is not null as ap1w \gset
select tt.as(:'e');
select (cost_bill_add(:s1, 'month', tt.mo(1), 24000, 'cash', 'REP-1', null, true)->>'id')::bigint as brp \gset
select tt.chk('T6 whole bill to one location (factory @5): 24000; the pool row is flagged one_off (একবারের খরচ), type machine_repair', (select amount from cost_bill_shares where bill_id=:brp and active)=24000 and (select one_off and component_type='machine_repair' from factory_cost_pools where ref='bill:'||:brp||':5' and active));
-- sub meter
select cost_source_save(null,'electricity',null,'shared',null,array[1,6],'monthly',tt.mo(3)) ->> 'id' as ssm \gset
select cost_rule_save(:ssm,'sub_meter',tt.mo(3),'[{"location_id":6,"dest":"factory"},{"location_id":1,"dest":"showroom"}]'::jsonb) ->> 'id' as rsm \gset
select tt.as(:'a'); select cost_rule_approve(:rsm::bigint) is not null as apsm \gset
select tt.as(:'e');
select (cost_bill_add(:ssm, 'month', tt.mo(1), 5000, 'bank', 'SM-1')->>'id')::bigint as bsm \gset
select tt.chk('T6 sub-meter with NO reading typed: the whole bill is unallocated (meter_missing), never guessed', (select count(*) from cost_bill_shares where bill_id=:bsm and active and kind='unallocated' and flag='meter_missing' and amount=5000)=1);
select cost_bill_reallocate(:bsm, '[{"location_id":6,"dest":"factory","value":300},{"location_id":1,"dest":"showroom","value":700}]'::jsonb) is not null as rea \gset
select tt.chk('T6 readings 300 : 700 typed later -> 1500 factory@6 / 3500 showroom@1; pool row appears', (select amount from cost_bill_shares where bill_id=:bsm and active and location_id=6)=1500 and (select amount from cost_bill_shares where bill_id=:bsm and active and location_id=1)=3500
  and (select actual_amount from factory_cost_pools where ref='bill:'||:bsm||':6' and active)=1500);
-- other manual
select cost_source_save(null,'other','misc','shared',null,array[1,5],'irregular',tt.mo(3)) ->> 'id' as sm \gset
select cost_rule_save(:sm,'other_manual',tt.mo(3),'[{"location_id":5,"dest":"factory"},{"location_id":1,"dest":"showroom"}]'::jsonb) ->> 'id' as rmn \gset
select tt.as(:'a'); select cost_rule_approve(:rmn::bigint) is not null as apmn \gset
select tt.as(:'e');
select cost_bill_add(:sm, 'month', tt.mo(1), 1000, 'cash', 'M-1', null, false, '[{"location_id":5,"dest":"factory","value":600},{"location_id":1,"dest":"showroom","value":300}]'::jsonb) as bm \gset
select (:'bm'::jsonb->>'id')::bigint as bmid \gset
select tt.chk('T6 hand-typed amounts 600 + 300 on a 1000 bill: the remainder 100 is an অভাগিত row (yellow flag), shares sum to the bill', (select amount from cost_bill_shares where bill_id=:bmid and active and kind='unallocated' and flag='remainder')=100 and (select sum(amount) from cost_bill_shares where bill_id=:bmid and active)=1000
  and tt.exc('cost_bill_unallocated')>0);
select tt.err('T6 hand-typed amounts above the bill are refused', format($$select cost_bill_add(%s,'month',tt.mo(1),100,'cash','M-2',null,false,'[{"location_id":5,"dest":"factory","value":90},{"location_id":1,"dest":"showroom","value":90}]'::jsonb)$$, :sm), 'shares_exceed_bill');
select tt.chk('T6 the refused bill left nothing behind', (select count(*) from cost_source_bills where bill_no='M-2')=0);
-- output kg (automatic from production)
reset role;
select id as ifx from items limit 1 \gset
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked) values ('K-FG','তৈরি','Made','kg','kg','finished_good',true),('K-RM','কাঁচা','Raw','kg','kg','raw_material',true);
select id as ik from items where code='K-FG' \gset
select id as ir from items where code='K-RM' \gset
set role authenticated; select tt.as(:'o');
select (recipe_save(null, :'ik'::uuid, 10, null, 'k', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'ir','qty',1)))->>'id')::uuid as rck \gset
reset role;
insert into production_runs (location_id, recipe_id, item_id, batches, made_at, yield_base, status) values (5, :'rck', :'ik', 1, tt.mo(1)::timestamptz + interval '3 days', 300, 'done'), (6, :'rck', :'ik', 1, tt.mo(1)::timestamptz + interval '4 days', 100, 'done'), (6, :'rck', :'ik', 1, tt.mo(1)::timestamptz + interval '5 days', 50, 'void');
set role authenticated; select tt.as(:'e');
select cost_source_save(null,'gas',null,'shared',null,array[5,6],'monthly',tt.mo(3)) ->> 'id' as sk \gset
select cost_rule_save(:sk,'output_kg',tt.mo(3),'[{"location_id":5,"dest":"factory"},{"location_id":6,"dest":"factory"}]'::jsonb) ->> 'id' as rk \gset
select tt.as(:'a'); select cost_rule_approve(:rk::bigint) is not null as apk \gset
select tt.as(:'e');
select (cost_bill_add(:sk, 'month', tt.mo(1), 4000, 'bank', 'GK-1')->>'id')::bigint as bk \gset
select tt.chk('T6 output kg is automatic (300 : 100 kg, the voided run is ignored) -> 3000 / 1000, nothing typed', (select amount from cost_bill_shares where bill_id=:bk and active and location_id=5)=3000 and (select amount from cost_bill_shares where bill_id=:bk and active and location_id=6)=1000);
select tt.chk('T6 a month with no production: unallocated (no_output)', (select (cost_bill_add(:sk, 'month', tt.mo(2), 4000, 'bank', 'GK-2')->'shares'->0->>'flag'))='no_output');

\echo == T7 yearly fee /12 and the pool
select cost_source_save(null,'licence_fee','trade licence','separate','factory',array[5],'yearly',tt.mo(3)) ->> 'id' as sl \gset
select (cost_bill_add(:sl, 'year', tt.mo(2), 12000, 'bank', 'LIC-1')->>'id')::bigint as bl \gset
select tt.chk('T7 the yearly fee is ONE pool row of period year; each covered month reads 12000 / 12 = 1000', (select period_kind from factory_cost_pools where ref='bill:'||:bl||':5' and active)='year' and (select tt.pma(5, tt.mo(0), 'licence_fee'))=1000 and (select tt.pma(5, tt.mf(5), 'licence_fee'))=1000);
select tt.chk('T7 outside the 12 months it is not there (null, not zero): before and after', (select tt.pma(5, tt.mo(3), 'licence_fee')) is null and (select tt.pma(5, tt.mf(10), 'licence_fee')) is null);
select tt.chk('T7 no বিল বাকি for the yearly source while the year is covered', not exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(0))->'bills_pending') p where (p->>'source_id')::bigint=:sl));

\echo == T8 duplicate guard against the 10-2 voucher
reset role;
insert into entries (form_code, location_id, serial, entry_date, status, data, flags, created_by, created_staff) values
  ('10-2', 5, 9801, tt.mo(1) + 4, 'approved', '{"lines":[{"head":"repair","to":"gas cylinder","amount":"2500","receipt":"yes"}]}', '[]', :'o', 'st');
set role authenticated; select tt.as(:'e');
select cost_source_save(null,'gas','cylinders','separate','factory',array[5],'monthly',tt.mo(3)) ->> 'id' as sd \gset
select cost_bill_add(:sd, 'month', tt.mo(1), 2500, 'cash', 'CYL-1', null, false, null, 'V-9801') as bd \gset
select (:'bd'::jsonb->>'id')::bigint as bdid \gset
select tt.chk('T8 same place, month, head (repair/utilities) and amount as an approved 10-2: flagged as a possible duplicate', (:'bd'::jsonb->>'dup_voucher')::boolean and (select dup_entry_id is not null from cost_source_bills where id=:bdid) and tt.exc('cost_bill_dup_voucher')>0);
select tt.chk('T8 the status lists it under duplicates; the bill keeps the 10-2 number only as a reference', exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(1))->'duplicates') d where (d->>'bill_id')::bigint=:bdid) and (select voucher_ref from cost_source_bills where id=:bdid)='V-9801');
select tt.chk('T8 a different amount is not flagged', not (cost_bill_add(:sd, 'month', tt.mo(1), 2600, 'cash', 'CYL-2')->>'dup_voucher')::boolean);
select cost_bill_dup_ack(:bdid, 'a different cylinder') is null as ack \gset
select tt.chk('T8 acknowledging it (with a reason) clears it from the list', not exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(1))->'duplicates') d where (d->>'bill_id')::bigint=:bdid));

\echo == T9 বিল বাকি (bill pending): marked, never filled by a guess
select tt.chk('T9 a monthly source with no bill for the month is marked বিল বাকি', exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(0))->'bills_pending') p where (p->>'source_id')::bigint=:sg and p->>'label_bn'='বিল বাকি'));
select tt.chk('T9 an irregular source (repair) is never pending', not exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(0))->'bills_pending') p where (p->>'source_id')::bigint=:s1));
select tt.chk('T9 the month with a bill is not pending', not exists (select 1 from jsonb_array_elements(cost_sources_status(tt.mo(1))->'bills_pending') p where (p->>'source_id')::bigint=:sg));
select tt.chk('T9 the empty month has NO pool figure (null) - no average was invented', (select tt.pma(5, tt.mo(0), 'gas')) is null);

\echo == T10 void
select cost_bill_void(:bg, 'entered twice by mistake') is null as vd \gset
select tt.err('T10 a void needs a reason', format($$select cost_bill_void(%s,'')$$, :bi), 'note_required');
select tt.chk('T10 void: shares and the pool row are retired; the pool figure drops by that bill (only the other gas bills remain)', (select count(*) from cost_bill_shares where bill_id=:bg and active)=0 and (select count(*) from factory_cost_pools where ref='bill:'||:bg||':5' and active)=0 and (select tt.pma(5, tt.mo(1), 'gas')) = (select coalesce(sum(actual_amount),0) from factory_cost_pools where location_id=5 and month=tt.mo(1) and component_type='gas' and active));

\echo == T11 pool double entry
select cost_source_save(null,'electricity','sep-el','separate','factory',array[6],'monthly',tt.mo(3)) ->> 'id' as sel6 \gset
select cost_bill_add(:sel6, 'month', tt.mo(1), 700, 'bank', 'EL6-1') is not null as be6 \gset
select pool_set(6, tt.mo(1), 'electricity', 500) ->> 'allocated_exists' as ae \gset
select tt.chk('T11 a manual pool amount on top of a bill is flagged (it would count twice)', :'ae'='true' and tt.exc('pool_double_entry')>0);

\echo == T12 a new site needs no code change
select tt.chk('T12 the picker lists the new site by itself', exists (select 1 from jsonb_array_elements(cost_pick_locations()) l where (l->>'id')::int=:loc8));
select cost_source_save(null,'electricity','site8 meter','separate','factory',array[:loc8],'monthly',tt.mo(3)) ->> 'id' as s8 \gset
select (cost_bill_add(:s8, 'month', tt.mo(1), 900, 'bank', 'S8-1')->>'id')::bigint as b8 \gset
select tt.chk('T12 its bill lands in ITS pool', (select actual_amount from factory_cost_pools where ref='bill:'||:b8||':'||:loc8 and active)=900 and (select location_id from factory_cost_pools where ref='bill:'||:b8||':'||:loc8 and active)=:loc8);
select cost_source_save(null,'internet','shared net','shared',null,array[1,:loc8],'monthly',tt.mo(3)) ->> 'id' as sn \gset
select cost_rule_save(:sn,'fixed_percent',tt.mo(3),format('[{"location_id":1,"dest":"showroom","value":60},{"location_id":%s,"dest":"admin","value":40}]', :loc8)::jsonb) ->> 'id' as rn \gset
select tt.as(:'a'); select cost_rule_approve(:rn::bigint) is not null as apn \gset
select tt.as(:'e');
select (cost_bill_add(:sn, 'month', tt.mo(1), 1000, 'bank', 'NN-1')->>'id')::bigint as bnn \gset
select tt.chk('T12 a shared bill over an old and the new site splits 600 showroom / 400 admin', (select amount from cost_bill_shares where bill_id=:bnn and active and location_id=1)=600 and (select amount from cost_bill_shares where bill_id=:bnn and active and location_id=:loc8 and dest='admin')=400);

\echo == T13 owner-added type maps to a pool type
select cost_source_type_add('জেনারেটর মেরামত', 'Generator repair', 'machine_repair') ->> 'code' as yt \gset
select cost_source_save(null,:'yt','gen','separate','factory',array[5],'irregular',tt.mo(3)) ->> 'id' as sy \gset
select (cost_bill_add(:sy, 'month', tt.mo(1), 800, 'cash', 'GEN-1')->>'id')::bigint as by_ \gset
select tt.chk('T13 the owner-added type feeds the machine_repair pool', (select component_type from factory_cost_pools where ref='bill:'||:by_||':5' and active)='machine_repair');

\echo == T14 end to end: bills -> pool -> conversion cost of a recipe (phase74)
reset role;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('E-FG','রসগোল্লা','Rasgulla E','kg','kg','finished_good',true,200),('E-RM','চিনি','Sugar E','kg','kg','raw_material',true,null);
select id as ie from items where code='E-FG' \gset
select id as irm from items where code='E-RM' \gset
set role authenticated; select tt.as(:'o');
select stock_opening(:'irm'::uuid, :loc8, 100, 10, null, 'e') is not null as soe \gset
select (recipe_save(null, :'ie'::uuid, 10, null, 'e', jsonb_build_array(jsonb_build_object('ingredient_item_id',:'irm','qty',5,'waste_pct',0)))->>'id')::uuid as rce \gset
select loc_cost_cfg_set(:loc8,'pool',100) is null as pm \gset
-- the new site: its electricity bill (900, last month) fed ITS pool by itself; the rate = pool figure / normal output 100 kg
select tt.chk('T14 pool mode at the new site: electricity = 3-month window since the first entry: (900 + 0 this month) / 2 = 450 -> 4.5 per kg -> 45 on a 10 kg batch; unit cost 5.0 material + 4.5', (recipe_cost(:'rce'::uuid, :loc8)->>'conversion_cost')::numeric=45 and (recipe_cost(:'rce'::uuid, :loc8)->>'conversion_complete')::boolean and (recipe_cost(:'rce'::uuid, :loc8)->>'unit_cost')::numeric=9.5);
select tt.chk('T14 the missing month is shown as a gap (বিল বাকি), not filled: months 2, gap_months 1', exists (select 1 from jsonb_array_elements(recipe_cost(:'rce'::uuid, :loc8)->'conversion_detail') d where d->>'type'='electricity' and (d->>'months')::int=2 and (d->>'gap_months')::int=1 and (d->>'rate')::numeric=4.5));
select tt.as(:'e');

\echo == T15 audit
select tt.as(:'o'); select tt.chk('T15 every write is audited (sources, rules, bills, shares) and bills carry created_by', (select count(*) from audit_log where table_name='cost_source_bills')>=8 and (select count(*) from audit_log where table_name='cost_sources')>=8 and (select count(*) from audit_log where table_name='cost_bill_shares')>=8 and not exists (select 1 from cost_source_bills where created_by is null));
select tt.as(:'n'); select tt.chk('T15 no cost right: still sees nothing at the end', (select count(*) from cost_source_bills)=0 and (select count(*) from cost_bill_shares)=0 and (select count(*) from cost_source_rules)=0);

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
