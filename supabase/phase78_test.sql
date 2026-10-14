-- FRESH DB ONLY. Phase 78 tests (step C-2খ: cost attribution to showroom / main centre, re-assign trail, approval separation hint).
--   Needs phase8..phase71, phase73, phase74, phase75, phase78 (phase72 is another branch).
--   ORDER="phase8 ... phase75 phase78" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 78db
--   psql -h /tmp -p 5544 -U postgres -d 78db -qAt -f supabase/phase78_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (ids and roles, no names). Months are relative to today.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set e '00000000-0000-0000-0000-000000000002'
\set a '00000000-0000-0000-0000-000000000003'
\set m '00000000-0000-0000-0000-000000000004'
\set x '00000000-0000-0000-0000-000000000005'
\set n '00000000-0000-0000-0000-000000000006'
\set r '00000000-0000-0000-0000-000000000007'
\set q '00000000-0000-0000-0000-000000000008'
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
create or replace function tt.row(j jsonb, k text, v text) returns jsonb language sql immutable as $$ select r from jsonb_array_elements(j->'rows') r where r->>k = v limit 1 $$;
-- rows of the cost view by destination kind / place / cost type: the amount (null when absent)
create or replace function tt.cv(j jsonb, p_kind text, p_dloc int, p_type text) returns numeric language sql immutable as $$
  select sum((r->>'amount')::numeric) from jsonb_array_elements(j->'rows') r where r->>'dest_kind' = p_kind and (r->>'dest_location')::int is not distinct from p_dloc and (p_type is null or r->>'cost_type' = p_type) $$;
create or replace function tt.tot(j jsonb, p_kind text) returns numeric language sql immutable as $$
  select sum((r->>'amount')::numeric) from jsonb_array_elements(j->'totals') r where r->>'dest_kind' = p_kind $$;
create or replace function tt.exc(p_flag text) returns int language sql security definer as $$ select count(*)::int from public.exceptions where flag_code = p_flag and level = 'yellow' $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'e','entry2@s.app','{"full_name":"Entry"}'), (:'a','appr3@s.app','{"full_name":"Approver"}'), (:'m','mgr4@s.app','{"full_name":"Manager"}'),
 (:'x','view5@s.app','{"full_name":"Viewer"}'), (:'n','none6@s.app','{"full_name":"Nobody"}'), (:'r','rec7@s.app','{"full_name":"Recipe"}'), (:'q','rolq8@s.app','{"full_name":"RoleQ"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'e','storekeeper'),(:'a','storekeeper'),(:'m','storekeeper'),(:'x','storekeeper'),(:'n','salesperson'),(:'r','storekeeper'),(:'q','recipe_approver') on conflict do nothing;
insert into user_locations values (:'e',1),(:'e',2),(:'e',5),(:'a',1),(:'a',2),(:'a',5),(:'m',1),(:'m',2),(:'m',5),(:'x',1),(:'x',2),(:'x',5),(:'n',1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'e'::uuid,'view_cost') is null as g1 \gset
select set_user_grant(:'e'::uuid,'cost_bill_entry') is null as g2 \gset
select set_user_grant(:'a'::uuid,'view_cost') is null as g3 \gset
select set_user_grant(:'a'::uuid,'cost_rule_approve') is null as g4 \gset
select set_user_grant(:'m'::uuid,'view_cost') is null as g5 \gset
select set_user_grant(:'m'::uuid,'cost_attrib_manage') is null as g6 \gset
select set_user_grant(:'x'::uuid,'view_cost') is null as g7 \gset

\echo == data (as postgres): the branch P&L fixture (same shape as phase27) for the current month
select (now() at time zone 'Asia/Dhaka')::date as td, date_trunc('month', (now() at time zone 'Asia/Dhaka')::date)::date as m1,
       (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) + interval '1 month - 1 day')::date as m2,
       (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) - interval '1 day')::date as lastend,
       (date_trunc('month', (now() at time zone 'Asia/Dhaka')::date) + interval '2 month - 1 day')::date as nextend,
       to_char((now() at time zone 'Asia/Dhaka')::date, 'YYYY-MM') as tm \gset
select format('{"from":"%s","to":"%s"}', :'m1', :'m2') as per \gset
insert into items (code,name_bn,name_en,category,unit,tracked,is_active,sellable,sell_price) values
 ('P78-A','এ','Item A','Sweets','kg',true,true,true,100), ('P78-B','বি','Item B','Sweets','kg',true,true,true,50), ('P78-C','সি','Item C','Cakes','pc',true,true,true,20);
select id as ia from items where code='P78-A' \gset
select id as ib from items where code='P78-B' \gset
select id as ic from items where code='P78-C' \gset
insert into item_costs (item_id, cost_price) values (:'ia',60),(:'ic',10) on conflict (item_id) do update set cost_price = excluded.cost_price;
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid,status) values
 (gen_random_uuid(),1,9701,:'td',now(),format('[{"item_id":"%s","qty":2,"price":100,"unit":"kg","amount":200},{"item_id":"%s","qty":1,"price":50,"unit":"kg","amount":50}]',:'ia',:'ib')::jsonb,250,0,250,'cash',:'o',250,'done'),
 (gen_random_uuid(),1,9702,:'td',now(),format('[{"item_id":"%s","qty":10,"price":20,"unit":"pc","amount":200}]',:'ic')::jsonb,200,20,180,'cash',:'o',180,'done'),
 (gen_random_uuid(),2,9703,:'td',now(),format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg","amount":100}]',:'ia')::jsonb,100,0,100,'cash',:'o',100,'done');
select id as sid from sales where receipt=9701 and location_id=1 \gset
insert into sale_returns (sale_id,location_id,lines,amount,credit_amount,refund_amount,refund_mode,reason_code,status,created_at) values
 (:'sid',1,format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg","amount":100}]',:'ia')::jsonb,100,0,100,'cash','x','done',now());
insert into location_settings (location_id,key,value) values (1,'fixed_cost_month','3100') on conflict (location_id,key) do update set value='3100';
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('10-2',1,9711,:'td','approved','{"lines":[{"head":"transport","amount":"25"},{"head":"transport","amount":75}]}','[]',:'o','st'),
 ('10-2',2,9713,:'td','submitted','{"lines":[{"head":"other","amount":40}]}','[]',:'o','st'),
 ('02-2',1,9721,:'td','approved','{"pay":[{"name":"Cook","due":1000,"overtime":100},{"name":"Clerk","due":"800","other":50}]}','[]',:'o','st');
set role authenticated; select tt.as(:'o');

\echo == T0 shape, defaults
select tt.chk('T0 four new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('location_cost_attribution','cost_attrib_main','cost_share_reassign','grant_separation_pairs') and c.relrowsecurity)=4);
select tt.chk('T0 switch cost_attrib_in_pl exists and is OFF by default', exists (select 1 from rules where key='cost_attrib_in_pl' and kind='switch') and not rule_on('cost_attrib_in_pl'));
select tt.chk('T0 grant cost_attrib_manage exists; two separation pairs seeded (recipe, cost rules)', exists (select 1 from grant_defs where grant_code='cost_attrib_manage') and (select count(*) from grant_separation_pairs)=2);
select tt.chk('T0 blank start: no attribution, no main centre, no re-assignment', not exists (select 1 from location_cost_attribution) and not exists (select 1 from cost_attrib_main) and not exists (select 1 from cost_share_reassign));
select tt.chk('T0 anon cannot execute; helpers closed', not has_function_privilege('anon','cost_share_reassign(bigint,text,int,text,uuid)','execute') and not has_function_privilege('anon','branch_cost_view(date,int)','execute')
  and not has_function_privilege('authenticated','_c78_rows(date,date)','execute') and not has_function_privilege('authenticated','_c78_dest(bigint,date)','execute') and not has_function_privilege('authenticated','_r3q_l1_pnl(date,date,int[],jsonb)','execute'));
select tt.chk('T0 the P&L functions carry the bos78 tag', position('bos78' in pg_get_functiondef('public._r3q_l1_pnl(date,date,int[],jsonb)'::regprocedure))>0 and position('bos78' in pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,int[],jsonb)'::regprocedure))>0);

\echo == T1 BEFORE any bill or setting: the P&L numbers
select report_run2('l1_pnl', :'per'::jsonb) as l1_before \gset
select report_run2('l3_shop_pnl', :'per'::jsonb) as l3_before \gset
select tt.chk('T1 before: two shop-month rows; loc1 profit -4980; loc2 profit 0; total profit -4980, expenses 140', jsonb_array_length(:'l1_before'::jsonb->'rows')=2 and (tt.row(:'l1_before'::jsonb,'location_id','1')->>'profit')::numeric=-4980
  and (tt.row(:'l1_before'::jsonb,'location_id','2')->>'profit')::numeric=0 and (:'l1_before'::jsonb->'totals'->>'profit')::numeric=-4980 and (:'l1_before'::jsonb->'totals'->>'expenses')::numeric=140);

\echo == data: cost bills through the phase75 screens (entry person e, approver a)
select tt.as(:'e');
select cost_source_save(null,'internet',null,'separate','showroom',array[1],'monthly',tt.mo(3)) ->> 'id' as si \gset
select cost_source_save(null,'water',null,'shared',null,array[1,2],'monthly',tt.mo(3)) ->> 'id' as sw \gset
select cost_source_save(null,'gas',null,'separate','factory',array[5],'monthly',tt.mo(3)) ->> 'id' as sg \gset
select cost_source_save(null,'other',null,'shared',null,array[1,2],'monthly',tt.mo(3)) ->> 'id' as sm \gset
select cost_source_save(null,'licence_fee',null,'separate','showroom',array[2],'yearly',tt.mo(3)) ->> 'id' as sl \gset
select cost_rule_save(:sw,'fixed_percent',tt.mo(3),'[{"location_id":1,"dest":"showroom","value":50},{"location_id":2,"dest":"showroom","value":30},{"location_id":2,"dest":"admin","value":20}]'::jsonb) ->> 'id' as rw \gset
select cost_rule_save(:sm,'other_manual',tt.mo(3),'[{"location_id":1,"dest":"showroom"},{"location_id":2,"dest":"showroom"}]'::jsonb) ->> 'id' as rm \gset
select tt.as(:'a'); select cost_rule_approve(:rw) is not null as ap1 \gset
select cost_rule_approve(:rm) is not null as ap2 \gset
select tt.as(:'e');
select cost_bill_add(:si,'month',tt.mo(0),1200,'cash','I-0') ->> 'id' as bi0 \gset
select cost_bill_add(:si,'month',tt.mo(1),700,'cash','I-1') ->> 'id' as bi1 \gset
select cost_bill_add(:si,'month',tt.mf(1),900,'cash','I-2') ->> 'id' as bi2 \gset
select cost_bill_add(:sw,'month',tt.mo(0),1000,'bank','W-0') ->> 'id' as bw0 \gset
select cost_bill_add(:sw,'month',tt.mo(1),800,'bank','W-1') ->> 'id' as bw1 \gset
select cost_bill_add(:sg,'month',tt.mo(0),3000,'bank','G-0') ->> 'id' as bg0 \gset
select cost_bill_add(:sm,'month',tt.mo(1),100,'cash','M-1',null,false,'[{"location_id":1,"dest":"showroom","value":60},{"location_id":2,"dest":"showroom","value":30}]'::jsonb) ->> 'id' as bm1 \gset
select cost_bill_add(:sl,'year',tt.mo(1),12000,'bank','L-1') ->> 'id' as bl1 \gset
select tt.chk('D0 hand check of the phase75 split: water this month 500 / 300 / 200, last month 400 / 240 / 160', (select string_agg(amount::text, '/' order by location_id, dest desc) from cost_bill_shares where bill_id=:bw0 and active and kind='share')='500.00/300.00/200.00'
  and (select string_agg(amount::text, '/' order by location_id, dest desc) from cost_bill_shares where bill_id=:bw1 and active and kind='share')='400.00/240.00/160.00');
select tt.chk('D0 the M bill has an unallocated remainder of 10 (60 + 30 typed of 100)', (select amount from cost_bill_shares where bill_id=:bm1 and active and kind='unallocated')=10);
select id as sh_i0 from cost_bill_shares where bill_id=:bi0 and active \gset
select id as sh_w1_l1 from cost_bill_shares where bill_id=:bw1 and active and location_id=1 \gset
select id as sh_g0 from cost_bill_shares where bill_id=:bg0 and active \gset
select id as sh_m1 from cost_bill_shares where bill_id=:bm1 and active and kind='share' and location_id=1 \gset
select id as sh_w0_l2s from cost_bill_shares where bill_id=:bw0 and active and location_id=2 and dest='showroom' \gset

\echo == T2 default OFF: bills exist, nothing is set -> the P&L is exactly as before
select tt.as(:'o');
select report_run2('l1_pnl', :'per'::jsonb) as l1_off \gset
select report_run2('l3_shop_pnl', :'per'::jsonb) as l3_off \gset
select tt.chk('T2 l1_pnl identical to before the bills (jsonb equal)', :'l1_off'::jsonb = :'l1_before'::jsonb);
select tt.chk('T2 l3_shop_pnl identical to before the bills (jsonb equal)', :'l3_off'::jsonb = :'l3_before'::jsonb);
select branch_cost_view(tt.mo(0)) as cv0 \gset
select tt.chk('T2 cost view this month, nothing set: every share is unallocated (default), via default', tt.tot(:'cv0'::jsonb,'unallocated') = 1200+500+300+200+1000 and tt.tot(:'cv0'::jsonb,'location') is null and tt.tot(:'cv0'::jsonb,'main_centre') is null
  and not exists (select 1 from jsonb_array_elements(:'cv0'::jsonb->'rows') r where r->>'via' <> 'default'));
select tt.chk('T2 cost view leaves the factory gas share out (layer 2 is product cost) and flags in_pl=false', not exists (select 1 from jsonb_array_elements(:'cv0'::jsonb->'rows') r where (r->>'share_id')::bigint=:sh_g0) and (:'cv0'::jsonb->>'in_pl')::boolean=false);
select tt.chk('T2 the yearly licence 12000 shows as 1000 a month in the view', tt.cv(:'cv0'::jsonb,'unallocated',null,'licence_fee')=1000);

\echo == T3 who may set / see
select tt.as(:'n');
select tt.err('T3 no cost right: cost view refused', $$select branch_cost_view(tt.mo(0))$$, 'not allowed');
select tt.err('T3 no cost right: cannot set', $$select cost_attrib_set(1,null,'showroom',tt.mo(0))$$, 'not allowed');
select tt.chk('T3 no cost right: sees no setting, no trail, no pairs of cost', (select count(*) from location_cost_attribution)=0 and (select count(*) from cost_share_reassign)=0 and (select count(*) from cost_attrib_main)=0);
select tt.err('T3 no cost right: cannot re-assign', format($$select cost_share_reassign(%s,'main_centre',null,'reason here')$$, :sh_i0), 'not allowed');
select tt.as(:'x');
select tt.err('T3 view-only holder cannot set', $$select cost_attrib_set(1,null,'showroom',tt.mo(0))$$, 'not allowed');
select tt.err('T3 view-only holder cannot re-assign', format($$select cost_share_reassign(%s,'main_centre',null,'reason here')$$, :sh_i0), 'not allowed');
select tt.chk('T3 but he can read the cost view', branch_cost_view(tt.mo(0)) ? 'rows');
select tt.as(:'e');
select tt.err('T3 the bill-entry person (no attribution grant) cannot set', $$select cost_attrib_set(1,null,'showroom',tt.mo(0))$$, 'not allowed');
select tt.as(:'a');
select tt.err('T3 the approver (no attribution grant) cannot set', $$select cost_attrib_set(1,null,'showroom',tt.mo(0))$$, 'not allowed');
select tt.as(:'m');

\echo == T4 the owner's choice per place, effective-dated (manager holds cost_attrib_manage)
select tt.err('T4 a past month is refused (earlier months never change)', format($$select cost_attrib_set(1,null,'showroom',%L)$$, tt.mo(1)), 'effective_in_past');
select tt.err('T4 bad destination refused', $$select cost_attrib_set(1,null,'nowhere',tt.mo(0))$$, 'bad_value');
select tt.err('T4 unknown cost type refused', $$select cost_attrib_set(1,'zzz','showroom',tt.mo(0))$$, 'unknown_type');
select tt.err('T4 unknown place refused', $$select cost_attrib_set(999,null,'showroom',tt.mo(0))$$, 'unknown_location');
select cost_attrib_set(1,null,'showroom',tt.mo(0),null,'d0000000-0000-0000-0000-000000000001'::uuid) ->> 'id' as a1 \gset
select tt.chk('T4 first setting needs no reason; same client id = dup', (cost_attrib_set(1,null,'showroom',tt.mo(0),null,'d0000000-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean and (select count(*) from location_cost_attribution)=1);
select cost_attrib_set(2,'water','main_centre',tt.mo(0)) ->> 'id' as a2 \gset
select cost_attrib_main_set(1, tt.mo(0)) ->> 'id' as mc1 \gset
select tt.chk('T4 main centre = place 1 from this month', (select location_id from cost_attrib_main where id=:mc1)=1);
-- still OFF: the P&L did not move
select tt.as(:'o');
select tt.chk('T4 settings made but the switch is OFF: l1 and l3 still identical to before', report_run2('l1_pnl', :'per'::jsonb) = :'l1_before'::jsonb and report_run2('l3_shop_pnl', :'per'::jsonb) = :'l3_before'::jsonb);
select branch_cost_view(tt.mo(0)) as cv1 \gset
select tt.chk('T4 cost view this month: place 1 showroom = 1200 internet + 500 water', tt.cv(:'cv1'::jsonb,'location',1,'internet')=1200 and tt.cv(:'cv1'::jsonb,'location',1,'water')=500 and tt.tot(:'cv1'::jsonb,'location')=1700);
select tt.chk('T4 place 2 water (300 showroom + 200 admin) goes to the main centre = place 1: 500; licence (no setting) stays unallocated 1000', tt.cv(:'cv1'::jsonb,'main_centre',1,'water')=500 and tt.tot(:'cv1'::jsonb,'unallocated')=1000);
select tt.chk('T4 each row says why: via setting / default', exists (select 1 from jsonb_array_elements(:'cv1'::jsonb->'rows') r where r->>'cost_type'='water' and r->>'dest_kind'='main_centre' and r->>'via'='setting')
  and exists (select 1 from jsonb_array_elements(:'cv1'::jsonb->'rows') r where r->>'cost_type'='licence_fee' and r->>'via'='default'));
select branch_cost_view(tt.mo(1)) as cvl \gset
select tt.chk('T4 LAST month is untouched by this month''s setting: everything unallocated 1160 + 1430 = 2590', tt.tot(:'cvl'::jsonb,'unallocated')=2590 and tt.tot(:'cvl'::jsonb,'location') is null and tt.tot(:'cvl'::jsonb,'main_centre') is null);
select tt.chk('T4 branch_cost_view for one place: place 2 sees the water shares it produces', (select count(*) from jsonb_array_elements(branch_cost_view(tt.mo(0), 2)->'rows') r where r->>'cost_type'='water')=2);

\echo == T5 switch ON: the shares are added as SEPARATE rows; hand-computed
select set_rule('cost_attrib_in_pl','true') is null as son \gset
select report_run2('l1_pnl', :'per'::jsonb) as l1_on \gset
select tt.chk('T5 ON: original rows unchanged', (select jsonb_agg(r order by r->>'location_id') from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'row_type' is null)
  = (select jsonb_agg(r order by r->>'location_id') from jsonb_array_elements(:'l1_before'::jsonb->'rows') r));
select tt.chk('T5 ON: exactly 3 separate cost-share rows (internet 1200, water 500 own, water 500 main centre), all on place 1', (select count(*) from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'row_type'='cost_share')=3
  and (select count(*) from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'row_type'='cost_share' and r->>'location_id'='1')=3);
select tt.chk('T5 ON: internet row expenses 1200, profit -1200; water showroom 500; water main centre 500',
  (select (r->>'expenses')::numeric=1200 and (r->>'profit')::numeric=-1200 from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'cost_type'='internet')
  and (select (r->>'expenses')::numeric=500 from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'cost_type'='water' and r->>'cost_share_dest'='location')
  and (select (r->>'expenses')::numeric=500 from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'cost_type'='water' and r->>'cost_share_dest'='main_centre'));
select tt.chk('T5 ON: report totals follow: expenses 140 + 2200 = 2340, profit -4980 - 2200 = -7180', (:'l1_on'::jsonb->'totals'->>'expenses')::numeric=2340 and (:'l1_on'::jsonb->'totals'->>'profit')::numeric=-7180);
select tt.chk('T5 ON: the row names say what they are (Bangla label with the cost type, main centre marked)', exists (select 1 from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'location_bn' like '%খরচ ভাগ: পানি (মূল কেন্দ্র)'));
select tt.chk('T5 ON: the factory gas share and the unallocated licence are NOT in the P&L', not exists (select 1 from jsonb_array_elements(:'l1_on'::jsonb->'rows') r where r->>'cost_type' in ('gas','licence_fee')));
select report_run2('l3_shop_pnl', :'per'::jsonb) as l3_on \gset
select tt.chk('T5 ON l3: original rows unchanged; 3 separate rows; totals profit -7180', (select jsonb_agg(r order by r->>'location_id') from jsonb_array_elements(:'l3_on'::jsonb->'rows') r where r->>'row_type' is null)
  = (select jsonb_agg(r order by r->>'location_id') from jsonb_array_elements(:'l3_before'::jsonb->'rows') r)
  and (select count(*) from jsonb_array_elements(:'l3_on'::jsonb->'rows') r where r->>'row_type'='cost_share')=3 and (:'l3_on'::jsonb->'totals'->>'profit')::numeric=-7180);
select tt.chk('T5 ON: a location filter (place 2) shows no share rows - place 2 pays nothing under these settings', not exists (select 1 from jsonb_array_elements(report_run2('l1_pnl', format('{"from":"%s","to":"%s","locations":[2]}',:'m1',:'m2')::jsonb)->'rows') r where r->>'row_type'='cost_share'));
select set_rule('cost_attrib_in_pl','false') is null as soff \gset
select tt.chk('T5 switch back OFF: l1 / l3 identical to before again', report_run2('l1_pnl', :'per'::jsonb) = :'l1_before'::jsonb and report_run2('l3_shop_pnl', :'per'::jsonb) = :'l3_before'::jsonb);

\echo == T6 effective dates: a change from a later month never touches an earlier one; old rows kept
select tt.as(:'m');
select tt.err('T6 changing an existing setting needs a reason', format($$select cost_attrib_set(1,null,'main_centre',%L)$$, tt.mf(1)), 'reason_required');
select cost_attrib_set(1,null,'main_centre',tt.mf(1),'move the showroom costs to the main centre from next month') ->> 'id' as a3 \gset
select tt.chk('T6 the new row keeps the previous values (prev_dest showroom, prev id)', (select prev_dest='showroom' and prev_id=:a1 and prev_effective_from=tt.mo(0) from location_cost_attribution where id=:a3));
select tt.chk('T6 this month''s cost view is byte-for-byte the same after the change', branch_cost_view(tt.mo(0)) = :'cv1'::jsonb);
select tt.chk('T6 last month''s cost view is the same too', branch_cost_view(tt.mo(1)) = :'cvl'::jsonb);
select branch_cost_view(tt.mf(1)) as cvn \gset
select tt.chk('T6 next month: the internet bill 900 of place 1 goes to the main centre (place 1)', tt.cv(:'cvn'::jsonb,'main_centre',1,'internet')=900 and tt.tot(:'cvn'::jsonb,'location') is null);
select cost_attrib_set(1,null,'unallocated',tt.mf(1),'second thought, leave it unallocated next month') ->> 'id' as a4 \gset
select tt.chk('T6 same-date replacement: the old row stays (inactive, replaced_by), the new one is active', (select not active and replaced_by=:a4 from location_cost_attribution where id=:a3) and (select active from location_cost_attribution where id=:a4)
  and (select count(*) from location_cost_attribution where location_id=1)=3);
select tt.chk('T6 next month now unallocated (900 internet; the yearly licence 1000 is unallocated too)', tt.cv(branch_cost_view(tt.mf(1)),'unallocated',null,'internet')=900);
select tt.chk('T6 this month still showroom (1700) after the second change', tt.tot(branch_cost_view(tt.mo(0)),'location')=1700);
select cost_attrib_set(1,'internet','main_centre',tt.mf(1),'internet to the main centre') ->> 'id' as a5 \gset
select tt.chk('T6 a typed cost type beats the general row (general says unallocated, internet says main centre -> 900 at the main centre)', tt.cv(branch_cost_view(tt.mf(1)),'main_centre',1,'internet')=900);
select cost_attrib_retire((select id from location_cost_attribution where location_id=1 and cost_type='internet' and active), 'not needed after all') is null as ret \gset
select tt.chk('T6 retired (take back): the row stays, inactive, with who/when/why; next month back to unallocated', (select not active and retired_reason='not needed after all' and retired_at is not null from location_cost_attribution where location_id=1 and cost_type='internet') and tt.cv(branch_cost_view(tt.mf(1)),'unallocated',null,'internet')=900);
select tt.err('T6 retiring needs a reason', format($$select cost_attrib_retire(%s, '')$$, :a2), 'reason_required');
select tt.chk('T6 history is visible: every row (active or not) can be read by the cost-right holder', (select count(*) from location_cost_attribution)=5 and (select count(*) from location_cost_attribution where not active)=2);
reset role;
select tt.err('T6 a setting row cannot be edited in place', $$update location_cost_attribution set dest='unallocated' where id=1$$, 'never rewritten');
select tt.err('T6 nor deleted', $$delete from location_cost_attribution where id=1$$, 'nothing is deleted');
set role authenticated; select tt.as(:'m');
select tt.err('T6 and the browser role has no write on the table', $$insert into location_cost_attribution (location_id, dest, effective_from) values (1,'showroom',tt.mo(0))$$, 'permission denied');
select cost_attrib_main_set(null, tt.mf(1), 'no place stands for the main centre from next month') ->> 'id' as mc2 \gset
select tt.chk('T6 main centre can be blank from a month: this month still place 1, next month none', (branch_cost_view(tt.mo(0))->>'main_centre_location')::int=1 and branch_cost_view(tt.mf(1))->>'main_centre_location' is null);

\echo == T7 re-assign one share: reason compulsory, trail append-only, never silent
select tt.as(:'m');
select tt.err('T7 no reason = refused', format($$select cost_share_reassign(%s,'location',2,'')$$, :sh_i0), 'reason_required');
select tt.err('T7 a 2-letter reason = refused', format($$select cost_share_reassign(%s,'location',2,'ok')$$, :sh_i0), 'reason_required');
select tt.err('T7 target place needed', format($$select cost_share_reassign(%s,'location',null,'moved to the wrong place')$$, :sh_i0), 'unknown_location');
select tt.err('T7 same destination (place 1 already) refused', format($$select cost_share_reassign(%s,'location',1,'no change really')$$, :sh_i0), 'same_destination');
select tt.err('T7 a factory share (product cost) cannot be re-assigned', format($$select cost_share_reassign(%s,'location',2,'factory gas to a shop')$$, :sh_g0), 'factory_share_not_reassignable');
select tt.err('T7 a share of a bill with an unallocated remainder cannot be re-assigned yet', format($$select cost_share_reassign(%s,'location',2,'wait for the remainder')$$, :sh_m1), 'bill_not_fully_allocated');
select cost_share_reassign(:sh_i0,'location',2,'this internet line serves the second showroom','e0000000-0000-0000-0000-000000000001'::uuid) as ra1 \gset
select tt.chk('T7 re-assigned: trail row has old (place 1) and new (place 2) destination, reason, amount snapshot', (select from_kind='location' and from_loc=1 and to_kind='location' and to_loc=2 and amount=1200 and reason like 'this internet%' and not locked_override and period_month=tt.mo(0) from cost_share_reassign where share_id=:sh_i0));
select tt.chk('T7 same client id = dup, no second row', (cost_share_reassign(:sh_i0,'location',2,'this internet line serves the second showroom','e0000000-0000-0000-0000-000000000001'::uuid)->>'dup')::boolean and (select count(*) from cost_share_reassign)=1);
select branch_cost_view(tt.mo(0)) as cv2 \gset
select tt.chk('T7 cost view: internet 1200 now at place 2, via reassigned, with the reason; place 1 no longer has it', tt.cv(:'cv2'::jsonb,'location',2,'internet')=1200 and tt.cv(:'cv2'::jsonb,'location',1,'internet') is null
  and exists (select 1 from jsonb_array_elements(:'cv2'::jsonb->'rows') r where (r->>'share_id')::bigint=:sh_i0 and (r->>'reassigned')::boolean and r->>'via'='reassigned' and r->>'reason' like 'this internet%'));
select tt.chk('T7 the total charged is unchanged by a move (showroom 1700 -> 500 + 1200 on two places)', tt.tot(:'cv2'::jsonb,'location')=1700);
select tt.err('T7 water 300 of place 2 is already at the main centre by setting: same destination', format($$select cost_share_reassign(%s,'main_centre',null,'try the same place again')$$, :sh_w0_l2s), 'same_destination');
select cost_share_reassign(:sh_w0_l2s,'unallocated',null,'leave this 300 out of the branch figures') is not null as ra2 \gset
select tt.chk('T7 to unallocated: the 300 moves out of the main centre (500 -> 200)', tt.cv(branch_cost_view(tt.mo(0)),'main_centre',1,'water')=200 and tt.tot(branch_cost_view(tt.mo(0)),'unallocated')=1300);
select cost_share_reassign(:sh_i0,'location',1,'back to the first showroom, my mistake') is not null as ra3 \gset
select tt.chk('T7 changed again: history keeps all rows (3 now), the latest wins', (select count(*) from cost_share_reassign where share_id=:sh_i0)=2 and tt.cv(branch_cost_view(tt.mo(0)),'location',1,'internet')=1200);
reset role;
select tt.err('T7 the trail cannot be edited', $$update cost_share_reassign set reason='changed later' where id=1$$, 'append-only');
select tt.err('T7 nor deleted', $$delete from cost_share_reassign where id=1$$, 'append-only');
select tt.chk('T7 every re-assignment is in the audit log', (select count(*) from audit_log where table_name='cost_share_reassign' and action='insert')=3);
set role authenticated; select tt.as(:'o');
select tt.chk('T7 the owner can re-assign too (no grant needed)', cost_share_reassign(:sh_i0,'main_centre',null,'owner moves it to the main centre') is not null);

\echo == T8 P&L with the switch ON after the re-assignments (hand-computed)
select set_rule('cost_attrib_in_pl','true') is null as son2 \gset
select report_run2('l1_pnl', :'per'::jsonb) as l1_on2 \gset
-- now: internet 1200 -> main centre (place 1); water: own 500 showroom (place 1); place 2 water showroom 300 unallocated; admin 200 main centre (place 1)
select tt.chk('T8 internet 1200 + water 200 are main-centre rows on place 1; water 500 showroom row', (select sum((r->>'expenses')::numeric) from jsonb_array_elements(:'l1_on2'::jsonb->'rows') r where r->>'cost_share_dest'='main_centre')=1400
  and (select sum((r->>'expenses')::numeric) from jsonb_array_elements(:'l1_on2'::jsonb->'rows') r where r->>'cost_share_dest'='location')=500);
select tt.chk('T8 total profit = -4980 - 1400 - 500 = -6880', (:'l1_on2'::jsonb->'totals'->>'profit')::numeric=-6880);
select set_rule('cost_attrib_in_pl','false') is null as soff2 \gset

\echo == T9 locked period
select set_rule('period_closed_until', to_json(:'lastend'::text)::jsonb) is null as lk \gset
select tt.as(:'m');
select tt.err('T9 closed period: the manager cannot re-assign a last-month share', format($$select cost_share_reassign(%s,'location',2,'moving a closed month share')$$, :sh_w1_l1), 'period_closed');
select tt.chk('T9 nothing was written by the refused attempt', (select count(*) from cost_share_reassign where share_id=:sh_w1_l1)=0);
select tt.as(:'o');
select cost_share_reassign(:sh_w1_l1,'location',2,'owner correction in a closed month') ->> 'locked_override' as lov \gset
select tt.chk('T9 the owner may, and it is FLAGGED: locked_override true on the trail row', :'lov'='true' and (select locked_override from cost_share_reassign where share_id=:sh_w1_l1));
select tt.chk('T9 and a yellow exception cost_share_locked_reassign was raised', tt.exc('cost_share_locked_reassign')=1);
select tt.chk('T9 an open month is not flagged (the earlier re-assignments had locked_override false)', not exists (select 1 from cost_share_reassign where period_month=tt.mo(0) and locked_override));
select tt.as(:'m');
select tt.as(:'o'); select set_rule('period_closed_until', to_json(:'nextend'::text)::jsonb) is null as lk3 \gset
select tt.as(:'m');
select tt.err('T9 a setting from a closed month is refused for the manager', format($$select cost_attrib_set(2,null,'showroom',%L,'x reason')$$, tt.mf(1)), 'period_closed');
select tt.as(:'o');
select tt.chk('T9 the owner may set it', cost_attrib_set(2,null,'showroom',tt.mf(1),'owner sets in a closed month') is not null);
select set_rule('period_closed_until', null) is null as unlk \gset

\echo == T10 approval separation hint (non-blocking)
select tt.as(:'o');
select set_user_grant(:'r'::uuid,'recipe_manage') is null as rg1 \gset
select grant_separation_hint(:'e'::uuid,'cost_rule_approve') as h1 \gset
select tt.chk('T10 e holds cost_bill_entry: giving him cost_rule_approve -> suggest true, never blocking, with the Bangla text', (:'h1'::jsonb->>'suggest')::boolean and not (:'h1'::jsonb->>'blocking')::boolean
  and :'h1'::jsonb->>'message_bn' = 'অন্য কাউকে অনুমোদনের দায়িত্ব দেওয়া ভালো — একই ব্যক্তি এন্ট্রি ও অনুমোদন দুটোই করলে ঝুঁকি' and :'h1'::jsonb->'pairs'->0->>'code'='cost_rules');
select tt.chk('T10 a holds cost_rule_approve: giving him cost_bill_entry -> suggest true', (grant_separation_hint(:'a'::uuid,'cost_bill_entry')->>'suggest')::boolean);
select tt.chk('T10 x holds neither: giving cost_bill_entry -> no suggestion', not (grant_separation_hint(:'x'::uuid,'cost_bill_entry')->>'suggest')::boolean and grant_separation_hint(:'x'::uuid,'cost_bill_entry')->>'message_bn' is null);
select tt.chk('T10 an unrelated grant (view_cost) -> no suggestion', not (grant_separation_hint(:'e'::uuid,'view_cost')->>'suggest')::boolean);
select tt.chk('T10 recipes: r holds recipe_manage, giving recipe_approve -> suggest true (pair recipe)', (grant_separation_hint(:'r'::uuid,'recipe_approve')->>'suggest')::boolean and grant_separation_hint(:'r'::uuid,'recipe_approve')->'pairs'->0->>'code'='recipe');
select tt.chk('T10 recipes by ROLE: q is a recipe approver (role), giving recipe_manage -> suggest true', (grant_separation_hint(:'q'::uuid,'recipe_manage')->>'suggest')::boolean);
select tt.chk('T10 the owner as the person: never a suggestion, never blocked (reason owner)', not (grant_separation_hint(:'o'::uuid,'recipe_approve')->>'suggest')::boolean and grant_separation_hint(:'o'::uuid,'recipe_approve')->>'reason'='owner');
select set_user_grant(:'e'::uuid,'cost_rule_approve') is null as gg \gset
select tt.chk('T10 NON-BLOCKING: the owner gave e the second right anyway, and it is there', exists (select 1 from user_grants where user_id=:'e' and grant_code='cost_rule_approve'));
select tt.chk('T10 the report of people who hold both sides lists e (cost rules) and r only after he gets both', exists (select 1 from jsonb_array_elements(grant_separation_report()) x where x->>'user_id'=:'e' and x->>'pair'='cost_rules')
  and not exists (select 1 from jsonb_array_elements(grant_separation_report()) x where x->>'user_id'=:'r'));
select tt.as(:'m');
select tt.err('T10 only the owner may ask (it shows who holds what)', $$select grant_separation_hint('00000000-0000-0000-0000-000000000002','cost_rule_approve')$$, 'not allowed');
select tt.err('T10 nor the report', $$select grant_separation_report()$$, 'not allowed');
select tt.as(:'o');
-- even with the same person holding both, the existing phase75 rule still refuses self-approval of a rule he entered (the hint is advice; the rule is unchanged)
select tt.as(:'e');
select cost_rule_save(:sm,'whole_to_one',tt.mo(2),'[{"location_id":2,"dest":"showroom"}]'::jsonb) ->> 'id' as rself \gset
select tt.err('T10 e holds both rights but phase75 still refuses approving his own rule (unchanged)', format($$select cost_rule_approve(%s)$$, :rself), 'self_approve_refused');

\echo == T11 audit and a new place
select tt.as(:'o');
select tt.chk('T11 audit rows exist for settings (insert + the replaced/retired updates)', (select count(*) from audit_log where table_name='location_cost_attribution')>=6 and (select count(*) from audit_log where table_name='cost_attrib_main')>=2);
reset role;
insert into locations (code, name_bn, name_en, kind, sort) values ('shop78', 'নতুন শোরুম', 'New shop', 'showroom', 9) returning id as loc9 \gset
set role authenticated; select tt.as(:'o');
select tt.chk('T11 a place created later can be given a setting with no code change', (cost_attrib_set(:loc9,null,'showroom',tt.mo(0)) ->> 'id') is not null);
select tt.chk('T11 and it can receive a re-assigned share', (cost_share_reassign((select id from cost_bill_shares where bill_id=:bw0 and active and location_id=1),'location',:loc9,'the new shop uses this water') ->> 'to_location')::int=:loc9);

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
