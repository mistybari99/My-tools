-- FRESH DB ONLY. Phase 43 tests (Module C: customers, tiers, tier discount at the POS, points, gifts, automatic tier refresh).
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase43" bash tests/sql/build_fresh_db.sh a43db
--   psql -h /tmp -p 5544 -U postgres -d a43db -qAt -f supabase/phase43_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set sp '00000000-0000-0000-0000-000000000008'
\set sp2 '00000000-0000-0000-0000-000000000009'
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
 (:'sp','sp8@s.app','{"full_name":"Sales"}'), (:'sp2','sp9@s.app','{"full_name":"Sales Two"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper'),(:'sp','salesperson'),(:'sp2','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'sp',1),(:'sp2',2) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'s'::uuid,'customer_manage') is null as gm \gset
insert into location_settings (location_id,key,value) values (1,'discount_limit','50') on conflict (location_id,key) do update set value='50';

\echo == T0 shape
select tt.chk('T0 seven tiers seeded, names only: every discount 0, no threshold', (select count(*) from customer_tiers)=7
  and (select count(*) from customer_tiers where discount_percent<>0 or discount_cap_amount is not null or min_lifetime_spend is not null or min_orders is not null or min_orders_12m is not null or min_months_active is not null)=0);
select tt.chk('T0 exactly one default tier = walkin', (select count(*) from customer_tiers where is_default)=1 and (select code from customer_tiers where is_default)='walkin');
select tt.chk('T0 five switches exist and are OFF', (select count(*) from rules where key in ('tier_discount_on','customer_tier_auto_on','customer_tier_allow_downgrade','loyalty_points_on','customer_gifts_on'))=5
  and not rule_on('tier_discount_on') and not rule_on('customer_tier_auto_on') and not rule_on('customer_tier_allow_downgrade') and not rule_on('loyalty_points_on') and not rule_on('customer_gifts_on'));
select tt.chk('T0 grant customer_manage exists', exists (select 1 from grant_defs where grant_code='customer_manage'));
select tt.chk('T0 new tables have RLS and no write grants', (select count(*) from pg_class where relname in ('customer_tiers','customer_tier_history','customer_points_ledger','gift_rules','customer_gifts','sale_tier_use') and relrowsecurity)=6
  and not has_table_privilege('authenticated','customer_tiers','insert') and not has_table_privilege('authenticated','customer_tiers','update') and not has_table_privilege('authenticated','customer_points_ledger','insert')
  and not has_table_privilege('authenticated','customer_gifts','update') and not has_table_privilege('authenticated','customer_tier_history','insert') and not has_table_privilege('authenticated','gift_rules','insert'));
select tt.chk('T0 anon has no execute; helpers are closed to signed-in users', not has_function_privilege('anon','public.customer_save(uuid,jsonb,uuid)','execute') and not has_function_privilege('anon','public.gifts_due(uuid)','execute')
  and not has_function_privilege('authenticated','public.loyalty_award(uuid)','execute') and not has_function_privilege('authenticated','public._cust_stats43(uuid,boolean)','execute')
  and has_function_privilege('authenticated','public.customer_tier_refresh(boolean)','execute'));
select tt.chk('T0 record_sale2 keeps its signature and privileges', has_function_privilege('authenticated','public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)','execute')
  and not has_function_privilege('anon','public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)','execute')
  and (select count(*) from pg_proc where proname='record_sale2')=1);
select tt.chk('T0 record_sale2: the bos22-late patch of phase22 is still inside', position('bos22-late' in pg_get_functiondef('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure))>0);
select tt.chk('T0 record_sale2: exactly the marked bos43 blocks were added', (select (length(d) - length(replace(d, 'bos43', '')))/5 from (select pg_get_functiondef('public.record_sale2(uuid,int,jsonb,numeric,jsonb,text,text,text,text,boolean,timestamptz,text,numeric)'::regprocedure) d) x)=5);

\echo == T1 tiers (owner only)
set role authenticated; select tt.as(:'sp');
select tt.chk('T1 staff can read the tiers', (select count(*) from customer_tiers)=7);
select tt.err('T1 staff cannot save a tier', $$select tier_save(null, '{"code":"plat","name_en":"Platinum"}')$$, 'not allowed');
select tt.err('T1 staff cannot write a tier directly', $$update customer_tiers set discount_percent=50$$, 'permission denied');
select tt.err('T1 staff cannot reorder', $$select tier_reorder(array[1,2])$$, 'not allowed');
select tt.err('T1 staff cannot save a gift rule', $$select gift_rule_save(null, '{"trigger":"manual","gift_text_en":"x"}')$$, 'not allowed');
select tt.as(:'o');
select tt.err('T1 bad code refused', $$select tier_save(null, '{"code":"Bad Code","name_en":"x"}')$$, 'bad_code');
select tt.err('T1 a name is required', $$select tier_save(null, '{"code":"nameless"}')$$, 'name_required');
select tt.err('T1 duplicate code refused', $$select tier_save(null, '{"code":"gold","name_en":"Gold again"}')$$, 'code_exists');
select tier_save(null, '{"code":"platinum","name_bn":"প্ল্যাটিনাম","name_en":"Platinum","color":"#111827","badge":"💎"}') ->> 'id' as plat \gset
select tt.chk('T1 owner adds a tier on top of the order', (select rank from customer_tiers where id=:plat) > (select max(rank) from customer_tiers where id<>:plat));
select tt.err('T1 discount above 100 refused', format($$select tier_save(%s, '{"discount_percent":"101"}')$$, :'plat'), 'bad_number');
select tt.err('T1 negative cap refused', format($$select tier_save(%s, '{"discount_cap_amount":"-1"}')$$, :'plat'), 'bad_number');
select tt.err('T1 NaN refused', format($$select tier_save(%s, '{"min_lifetime_spend":"NaN"}')$$, :'plat'), 'bad_number');
select tt.err('T1 text instead of a number refused', format($$select tier_save(%s, '{"min_orders":"abc"}')$$, :'plat'), 'bad_number');
select tt.err('T1 bad colour refused', format($$select tier_save(%s, '{"color":"red"}')$$, :'plat'), 'bad_color');
reset role;
select tt.err('T1 the code never changes', format($$update customer_tiers set code='zzz' where id=%s$$, :'plat'), 'tier_code_fixed');
select tt.err('T1 a tier is never deleted', format($$delete from customer_tiers where id=%s$$, :'plat'), '');
set role authenticated; select tt.as(:'o');
select id as t_walk from customer_tiers where code='walkin' \gset
select id as t_reg from customer_tiers where code='regular' \gset
select id as t_silver from customer_tiers where code='silver' \gset
select id as t_gold from customer_tiers where code='gold' \gset
select id as t_elite from customer_tiers where code='elite' \gset
select id as t_whole from customer_tiers where code='wholesale' \gset
select tier_save(:t_silver, '{"discount_percent":"5","min_lifetime_spend":"1000"}') is not null as e1 \gset
select tier_save(:t_gold, '{"discount_percent":"10","discount_cap_amount":"500","min_lifetime_spend":"5000","min_orders":"3","points_multiplier":"1.5","perks":"Free delivery","birthday_gift":"Sweet box","credit_limit_default":"20000"}') is not null as e2 \gset
select tier_save(:t_elite, '{"discount_percent":"15","min_orders_12m":"10","min_months_active":"6","points_multiplier":"2"}') is not null as e3 \gset
select tt.chk('T1 owner fills the tier policy', (select discount_percent=10 and discount_cap_amount=500 and min_orders=3 and points_multiplier=1.5 and credit_limit_default=20000 from customer_tiers where id=:t_gold));
select tier_reorder(array[:t_walk,:t_reg,:t_silver,:t_gold,:t_elite,:t_whole,:plat]::bigint[]) is not null as ro \gset
select tt.chk('T1 reorder sets the rank by position', (select rank from customer_tiers where id=:t_walk)=10 and (select rank from customer_tiers where id=:t_gold)=40 and (select rank from customer_tiers where id=:plat)=70);
select tt.err('T1 reorder with an unknown id refused', $$select tier_reorder(array[1,99999])$$, 'bad_value');
select tt.err('T1 the default tier cannot be retired', format($$select tier_save(%s, '{"active":false}')$$, :t_walk), 'default_tier_active');
select tier_save(:plat, '{"active":false}') is not null as ret \gset
select tt.chk('T1 a tier is retired with the flag, the row stays', (select not active from customer_tiers where id=:plat));
select tier_save(:plat, '{"active":true}') is not null as ret2 \gset
select tt.chk('T1 tier edits are in the audit log', exists (select 1 from audit_log where table_name='customer_tiers' and action='update'));

\echo == T2 customers: add, duplicate, rights
select tt.as(:'sp');
select customer_save(null, '{"mobile":"01711111111","name":"TestK","birthday":"1990-05-05","address":"Dhaka","note":"likes tea","source":"walk-in","whatsapp":"01711111111"}', gen_random_uuid()) as c1 \gset
select (:'c1'::jsonb ->> 'id')::uuid as cid1 \gset
select tt.chk('T2 salesperson adds a customer: default tier, start date, columns stored', (select tier_id=:t_walk and customer_since=(now() at time zone 'Asia/Dhaka')::date and birthday='1990-05-05' and address='Dhaka' and note='likes tea' and source='walk-in' and not tier_locked from customers where id=:'cid1'));
select tt.chk('T2 a second add with the same mobile returns dup, not an error', (customer_save(null, '{"mobile":"০১৭১১১১১১১১","name":"Other"}') ->> 'dup')::boolean and (customer_save(null, '{"mobile":"+8801711111111","name":"Other"}') ->> 'id')::uuid=:'cid1'::uuid);
select tt.chk('T2 still one row for that mobile', (select count(*) from customers where mobile='01711111111')=1);
select tt.err('T2 bad mobile refused', $$select customer_save(null, '{"mobile":"123","name":"X"}')$$, 'bad_mobile');
select tt.err('T2 name required', $$select customer_save(null, '{"mobile":"01722222222"}')$$, 'customer_name_required');
select tt.err('T2 future birthday refused', $$select customer_save(null, '{"mobile":"01722222222","name":"X","birthday":"2999-01-01"}')$$, 'bad_date');
select tt.err('T2 bad date refused', $$select customer_save(null, '{"mobile":"01722222222","name":"X","birthday":"31/31/2020"}')$$, 'bad_date');
select tt.err('T2 salesperson cannot choose a tier', format($$select customer_save(null, '{"mobile":"01722222222","name":"X","tier_id":"%s"}')$$, :t_gold), 'not allowed');
select tt.err('T2 salesperson cannot set a credit limit', format($$select customer_save(%L, '{"credit_limit":"5000"}')$$, :'cid1'), 'not allowed');
select tt.err('T2 salesperson cannot deactivate', format($$select customer_save(%L, '{"active":false}')$$, :'cid1'), 'not allowed');
select customer_save(:'cid1'::uuid, '{"name":"TestK Uddin","note":"vip soon"}') ->> 'name' as nn \gset
select tt.chk('T2 salesperson edits name and note', :'nn'='TestK Uddin' and (select note from customers where id=:'cid1')='vip soon');
with u as (update customers set name='Z' where id=:'cid1' returning 1) select count(*) as touched from u \gset
select tt.chk('T2 salesperson cannot update the table directly (no row is touched)', :touched=0);
select tt.as(:'k'); select tt.err('T2 a storekeeper (no POS right) cannot add customers', $$select customer_save(null, '{"mobile":"01733333333","name":"Nope"}')$$, 'not allowed');
select tt.err('T2 a storekeeper cannot read the directory', $$select * from customer_directory()$$, 'not allowed');
select tt.as(:'s');
select customer_save(null, ('{"mobile":"01744444444","name":"TestF Gold","tier_id":"'||:t_gold||'","credit_limit":"1000"}')::jsonb) ->> 'id' as cidg \gset
select tt.chk('T2 manager (grant) registers a customer straight into a tier (locked: a manual choice); an explicit limit beats the tier default', (select tier_id=:t_gold and credit_limit=1000 and tier_locked from customers where id=:'cidg'));
select tt.chk('T2 that registration left a manual history row', (select count(*) from customer_tier_history where customer_id=:'cidg' and reason='manual' and to_tier=:t_gold)=1);
reset role;
insert into customers (mobile, name, tier_id) values ('01755555555','Via other path', :t_gold) returning credit_limit as cl \gset
select tt.chk('T2 a customer created by any path gets the tier credit default when none is given', :'cl'='20000');
insert into customers (mobile, name) values ('01766666666','Plain') returning tier_id as pt \gset
select tt.chk('T2 and the default tier when no tier is given', :'pt'=:'t_walk');
set role authenticated;

\echo == T3 change a tier by hand, history, lock
select tt.as(:'sp');
select tt.err('T3 salesperson cannot change a tier', format($$select customer_set_tier(%L, %s, 'because', true)$$, :'cid1', :t_silver), 'not allowed');
select tt.as(:'s');
select tt.err('T3 a reason is required', format($$select customer_set_tier(%L, %s, '', true)$$, :'cid1', :t_silver), 'note_required');
select tt.err('T3 unknown tier refused', format($$select customer_set_tier(%L, 99999, 'because', true)$$, :'cid1'), 'tier_not_found');
select customer_set_tier(:'cid1'::uuid, :t_silver::bigint, 'loyal for years') ->> 'changed' as ch \gset
select tt.chk('T3 manager moves the tier: history row has from, to, reason and the person', :'ch'='true' and exists (select 1 from customer_tier_history where customer_id=:'cid1' and from_tier=:t_walk and to_tier=:t_silver and reason='manual' and note='loyal for years' and by_user=:'s'));
select tt.chk('T3 a manual change locks the tier by default', (select tier_locked from customers where id=:'cid1'));
reset role;
select tt.err('T3 history rows cannot be changed', $$update customer_tier_history set note='x'$$, 'append_only');
select tt.err('T3 history rows cannot be deleted', $$delete from customer_tier_history$$, 'append_only');
select tt.err('T3 history cannot be truncated', $$truncate customer_tier_history$$, 'append_only');
set role authenticated; select tt.as(:'o');
select customer_set_tier(:'cid1'::uuid, :t_reg::bigint, 'testing unlock', false) is not null as un \gset
select tt.chk('T3 owner can move and unlock', (select tier_id=:t_reg and not tier_locked from customers where id=:'cid1'));

\echo == T4 automatic refresh (dry run first)
reset role;
-- customers with sales built through record_sale2 itself
insert into customers (mobile, name) values ('01801000001','A one sale 1200'),('01801000002','B three sales 6000'),('01801000003','C one sale 4000'),('01801000004','D locked 6000'),('01801000005','E returned'),('01801000006','F nothing') on conflict do nothing;
update customers set tier_locked=true where mobile='01801000004';
set role authenticated; select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":1200}]',0,'[{"mode":"cash","amount":1200}]','01801000001','A','retail',null,true) is not null as sa1 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":2000}]',0,'[{"mode":"cash","amount":2000}]','01801000002','B','retail',null,true) is not null as sb1 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":2000}]',0,'[{"mode":"cash","amount":2000}]','01801000002','B','retail',null,true) is not null as sb2 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":2000}]',0,'[{"mode":"cash","amount":2000}]','01801000002','B','retail',null,true) is not null as sb3 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":4000}]',0,'[{"mode":"cash","amount":4000}]','01801000003','C','retail',null,true) is not null as sc1 \gset
select record_sale2(gen_random_uuid(),1,'[{"amount":6000}]',0,'[{"mode":"cash","amount":6000}]','01801000004','D','retail',null,true) is not null as sd1 \gset
select (record_sale2(gen_random_uuid(),1,'[{"amount":6000}]',0,'[{"mode":"cash","amount":6000}]','01801000005','E','retail',null,true) ->> 'id') as se1 \gset
reset role;
insert into sale_returns (sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, refund_mode, reason_code, status)
  select id, location_id, customer_id, '[]', 3000, 0, 3000, 'cash', 'damaged', 'done' from sales where id=:'se1'::uuid;
set role authenticated; select tt.as(:'sp');
select tt.err('T4 salesperson cannot run the refresh', $$select customer_tier_refresh(true)$$, 'not allowed');
select tt.as(:'o');
select customer_tier_refresh(true) as r0 \gset
select tt.chk('T4 DRY RUN lists the moves: A silver, B gold, C silver, E silver (net 3000 after the return); D locked and F untouched',
  (:'r0'::jsonb ->> 'count')::int=4 and (:'r0'::jsonb ->> 'dry')::boolean
  and (select count(*) from jsonb_array_elements(:'r0'::jsonb -> 'changes') x where x ->> 'mobile'='01801000001' and x ->> 'to_code'='silver' and x ->> 'from_code'='walkin')=1
  and (select count(*) from jsonb_array_elements(:'r0'::jsonb -> 'changes') x where x ->> 'mobile'='01801000002' and x ->> 'to_code'='gold' and (x ->> 'orders')::int=3 and (x ->> 'spend')::numeric=6000)=1
  and (select count(*) from jsonb_array_elements(:'r0'::jsonb -> 'changes') x where x ->> 'mobile'='01801000003' and x ->> 'to_code'='silver')=1
  and (select count(*) from jsonb_array_elements(:'r0'::jsonb -> 'changes') x where x ->> 'mobile'='01801000005' and x ->> 'to_code'='silver' and (x ->> 'spend')::numeric=3000)=1
  and (select count(*) from jsonb_array_elements(:'r0'::jsonb -> 'changes') x where x ->> 'mobile' in ('01801000004','01801000006'))=0);
select tt.chk('T4 the dry run wrote nothing', (select count(*) from customer_tier_history where reason='auto')=0 and (select count(*) from customers where mobile like '018010000%' and tier_id<>:t_walk)=0);
select tt.chk('T4 the default of the argument is a dry run', (customer_tier_refresh() ->> 'dry')::boolean);
select tt.err('T4 a real run needs the switch', $$select customer_tier_refresh(false)$$, 'tier_auto_off');
select set_rule('customer_tier_auto_on','true') is null as sw \gset
select customer_tier_refresh(false) as r1 \gset
select tt.chk('T4 real run applies exactly what the dry run listed', (:'r1'::jsonb ->> 'count')::int=4 and not (:'r1'::jsonb ->> 'dry')::boolean
  and (select tier_id=:t_silver from customers where mobile='01801000001') and (select tier_id=:t_gold from customers where mobile='01801000002')
  and (select tier_id=:t_silver from customers where mobile='01801000003') and (select tier_id=:t_walk from customers where mobile='01801000004') and (select tier_id=:t_silver from customers where mobile='01801000005'));
select tt.chk('T4 one auto history row per move, with the numbers', (select count(*) from customer_tier_history where reason='auto')=4 and exists (select 1 from customer_tier_history h join customers c on c.id=h.customer_id where c.mobile='01801000002' and h.reason='auto' and h.to_tier=:t_gold and h.note like 'spend 6000%orders 3'));
select tt.chk('T4 a second run changes nothing (idempotent)', (customer_tier_refresh(true) ->> 'count')::int=0 and (customer_tier_refresh(false) ->> 'count')::int=0 and (select count(*) from customer_tier_history where reason='auto')=4);
-- never downgrade by default
select tier_save(:t_gold, '{"min_lifetime_spend":"9000"}') is not null as raise_bar \gset
select tt.chk('T4 raising the bar never downgrades while the downgrade switch is OFF', (customer_tier_refresh(true) ->> 'count')::int=0);
select set_rule('customer_tier_allow_downgrade','true') is null as dg \gset
select customer_tier_refresh(true) as r2 \gset
select tt.chk('T4 with downgrades ON the dry run shows B (spend 6000 < the new 9000) moving gold -> silver, nothing written; the manager-registered (locked) gold customer is not listed',
  exists (select 1 from jsonb_array_elements(:'r2'::jsonb -> 'changes') x where x ->> 'mobile'='01801000002' and x ->> 'direction'='down' and x ->> 'to_code'='silver')
  and not exists (select 1 from jsonb_array_elements(:'r2'::jsonb -> 'changes') x where x ->> 'mobile'='01744444444')
  and (select tier_id=:t_gold from customers where mobile='01801000002'));
select set_rule('customer_tier_allow_downgrade','false') is null as dg0 \gset
select tier_save(:t_gold, '{"min_lifetime_spend":"5000"}') is not null as lower_bar \gset
-- locked customers never move even when they qualify
select tt.chk('T4 the locked customer D is still walk-in', (select tier_id=:t_walk and tier_locked from customers where mobile='01801000004'));
-- months active threshold: elite needs 6 months and 10 orders in 12 months, nobody has that
select tt.chk('T4 a tier with several thresholds needs ALL of them (elite not reached)', not exists (select 1 from customers where tier_id=:t_elite));

\echo == T5 tier discount pre-approved at the POS
select tt.as(:'o');
select customer_set_tier(c.id, :t_gold, 'fix for pos test', true) is not null as g1 from customers c where c.mobile='01801000002' \gset
select tt.as(:'sp');
select tt.err('T5 switch OFF: 10 percent on a gold customer still needs a manager (limit is 50)', $$select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01801000002','B','retail',null,true,null,'percent',10)$$, 'discount_needs_approval');
select tt.as(:'o'); select set_rule('tier_discount_on','true') is null as sw2 \gset
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01801000002','B','retail',null,true,null,'percent',10) as t1 \gset
select tt.chk('T5 switch ON: the gold 10 percent goes through without a manager; sale total 900', (:'t1'::jsonb ->> 'total')::numeric=900 and (:'t1'::jsonb ->> 'discount')::numeric=100);
select tt.chk('T5 the sale remembers tier, percent and amount', exists (select 1 from sale_tier_use u where u.sale_id=(:'t1'::jsonb ->> 'id')::uuid and u.tier_id=:t_gold and u.tier_percent=10 and u.tier_discount=100 and u.customer_id=(:'t1'::jsonb ->> 'customer_id')::uuid));
select tt.chk('T5 no "discount over the limit" exception for the tier part', not exists (select 1 from exceptions where sale_id=(:'t1'::jsonb ->> 'id')::uuid and flag_code in ('discount_over_limit','discount_no_limit')));
select tt.err('T5 12 percent (above the tier 10) follows the normal approval rule', $$select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',120,'[{"mode":"cash","amount":880}]','01801000002','B','retail',null,true,null,'percent',12)$$, 'discount_needs_approval');
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',90,'[{"mode":"cash","amount":910}]','01801000002','B','retail',null,true) as t2 \gset
select tt.chk('T5 an amount that equals 9 percent is covered too', (:'t2'::jsonb ->> 'total')::numeric=910 and exists (select 1 from sale_tier_use where sale_id=(:'t2'::jsonb ->> 'id')::uuid and tier_discount=90));
select tt.err('T5 a walk-in (tier discount 0) still needs approval', $$select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01801000006','F','retail',null,true,null,'percent',10)$$, 'discount_needs_approval');
select tt.err('T5 no customer: still needs approval', $$select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]',null,null,'retail',null,true,null,'percent',10)$$, 'discount_needs_approval');
select tt.as(:'o'); select tier_save(:t_gold, '{"discount_cap_amount":"80"}') is not null as capset \gset
select tt.as(:'sp');
select tt.err('T5 the cap: 100 taka is above the tier cap of 80 and needs approval', $$select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01801000002','B','retail',null,true,null,'percent',10)$$, 'discount_needs_approval');
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',80,'[{"mode":"cash","amount":920}]','01801000002','B','retail',null,true) as t3 \gset
select tt.chk('T5 exactly the cap is covered', exists (select 1 from sale_tier_use where sale_id=(:'t3'::jsonb ->> 'id')::uuid and tier_discount=80));
select tt.as(:'s');
select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',150,'[{"mode":"cash","amount":850}]','01801000002','B','retail',null,true) as t4 \gset
select tt.chk('T5 a manager can still go above the tier: the normal approver is recorded, the tier part is recorded too', (select discount_approval='grant' from sales where id=(:'t4'::jsonb ->> 'id')::uuid)
  and exists (select 1 from sale_tier_use where sale_id=(:'t4'::jsonb ->> 'id')::uuid and tier_discount=80));
select tt.chk('T5 above the limit part still raises the red exception', exists (select 1 from exceptions where sale_id=(:'t4'::jsonb ->> 'id')::uuid and flag_code='discount_over_limit'));
select tt.as(:'o'); select tier_save(:t_gold, '{"discount_cap_amount":"","active":false}') is not null as retire_gold \gset
select tt.as(:'sp');
select tt.err('T5 a retired tier gives no pre-approval', $$select record_sale2(gen_random_uuid(),1,'[{"amount":1000}]',100,'[{"mode":"cash","amount":900}]','01801000002','B','retail',null,true,null,'percent',10)$$, 'discount_needs_approval');
select tt.as(:'o'); select tier_save(:t_gold, '{"active":true}') is not null as unretire \gset
select tt.chk('T5 report: tier usage counts the tier discount', (select tier_discount from tier_usage_report(current_date-1,current_date+1) where code='gold')=350);
select tt.as(:'sp'); select tt.err('T5 report is closed to a salesperson', $$select * from tier_usage_report(current_date-1,current_date+1)$$, 'not allowed');
select tt.as(:'o'); select set_rule('tier_discount_on','false') is null as sw3 \gset

\echo == T6 existing sale behaviour is unchanged
select tt.as(:'sp');
select record_sale2('11111111-1111-1111-1111-111111111111',1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) as u1 \gset
select tt.chk('T6 a plain sale within the limit, no customer', (:'u1'::jsonb ->> 'total')::numeric=450 and (:'u1'::jsonb ->> 'due')::numeric=0);
select tt.chk('T6 the same client key returns the same sale (dup)', (record_sale2('11111111-1111-1111-1111-111111111111',1,'[{"amount":500}]',50,'[{"mode":"cash","amount":450}]',null,null,'retail',null,true) ->> 'dup')::boolean);
select tt.err('T6 above the limit refused as before', $$select record_sale2(gen_random_uuid(),1,'[{"amount":500}]',60,'[{"mode":"cash","amount":440}]',null,null,'retail',null,true)$$, 'discount_needs_approval');
select tt.chk('T6 no tier row for sales without a tier discount', not exists (select 1 from sale_tier_use where sale_id=(:'u1'::jsonb ->> 'id')::uuid));
select record_sale2(gen_random_uuid(),1,'[{"amount":100}]',0,'[{"mode":"cash","amount":100}]','01899999999','Posnew','retail',null,true) ->> 'customer_id' as pn \gset
select tt.chk('T6 a new customer made by the POS gets the default tier', :'pn' is not null and (select tier_id=:t_walk and customer_since is not null from customers where mobile='01899999999'));

\echo == T7 loyalty points
select tt.as(:'o');
select customer_save(null, ('{"mobile":"01911111111","name":"Points Pat","tier_id":"'||:t_gold||'"}')::jsonb) ->> 'id' as cp \gset
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":1250}]',0,'[{"mode":"cash","amount":1250}]','01911111111','Pat','retail',null,true) ->> 'id' as ps0 \gset
select tt.chk('T7 switch OFF: no points', (select count(*) from customer_points_ledger where customer_id=:'cp')=0);
select tt.as(:'o');
select set_rule('loyalty_points_on','true') is null as lp \gset
select set_rule('points_per_100_taka','2') is null as lp2 \gset
select set_rule('point_value_taka','0.5') is null as lp3 \gset
select set_rule('redeem_min_points','20') is null as lp4 \gset
select tt.as(:'sp');
select record_sale2(gen_random_uuid(),1,'[{"amount":1250}]',0,'[{"mode":"cash","amount":1250}]','01911111111','Pat','retail',null,true) ->> 'id' as ps1 \gset
select tt.chk('T7 points = floor(1250 / 100 x 2 per 100 x 1.5 gold) = floor(37.5) = 37', (select delta=37 and reason='sale' and sale_id=:'ps1'::uuid from customer_points_ledger where customer_id=:'cp' and reason='sale'));
select record_sale2(gen_random_uuid(),1,'[{"amount":1249}]',0,'[{"mode":"cash","amount":1249}]','01911111111','Pat','retail',null,true) is not null as ps2 \gset
select tt.chk('T7 floor again: 1249 gives floor(37.47) = 37', (select count(*) from customer_points_ledger where customer_id=:'cp' and delta=37)=2);
select record_sale2(gen_random_uuid(),1,'[{"amount":3}]',0,'[{"mode":"cash","amount":3}]','01911111111','Pat','retail',null,true) is not null as ps3 \gset
select tt.chk('T7 a sale too small for a point writes no row', (select count(*) from customer_points_ledger where customer_id=:'cp')=2);
select record_sale2(gen_random_uuid(),1,'[{"amount":2000}]',0,'[{"mode":"cash","amount":2000}]',null,null,'retail',null,true) is not null as ps4 \gset
select tt.chk('T7 a sale without a customer earns nothing', (select count(*) from customer_points_ledger)=2);
select tt.chk('T7 balance function', customer_points(:'cp'::uuid)=74);
select tt.err('T7 loyalty_award is not callable from the browser', format($$select loyalty_award(%L)$$, :'ps1'), 'permission denied');
reset role;
select tt.chk('T7 loyalty_award twice for the same sale does not double', loyalty_award(:'ps1'::uuid)=37 and (select count(*) from customer_points_ledger where sale_id=:'ps1'::uuid)=1);
select tt.err('T7 ledger rows are immutable', $$update customer_points_ledger set delta=1$$, 'append_only');
select tt.err('T7 ledger rows cannot be deleted', $$delete from customer_points_ledger$$, 'append_only');
set role authenticated; select tt.as(:'s');
select tt.as(:'sp');
select tt.err('T7 staff cannot adjust points', format($$select customer_points_adjust(%L, 10, 'gift points')$$, :'cp'), 'not allowed');
select tt.as(:'s');
select tt.err('T7 a note is required', format($$select customer_points_adjust(%L, 10, '')$$, :'cp'), 'note_required');
select tt.err('T7 zero refused', format($$select customer_points_adjust(%L, 0, 'nothing')$$, :'cp'), 'bad_number');
select tt.err('T7 cannot go below zero', format($$select customer_points_adjust(%L, -1000, 'too much')$$, :'cp'), 'not_enough_points');
select customer_points_adjust(:'cp'::uuid, 10, 'manual bonus', '22222222-2222-2222-2222-222222222222') as pa \gset
select tt.chk('T7 manager adds 10 points; same client key again is a dup and writes nothing', (:'pa'::jsonb ->> 'balance')::int=84 and (customer_points_adjust(:'cp'::uuid, 10, 'manual bonus', '22222222-2222-2222-2222-222222222222') ->> 'dup')::boolean and customer_points(:'cp'::uuid)=84);
select tt.as(:'sp');
select tt.err('T7 below the minimum refused', format($$select customer_points_redeem(%L, 10)$$, :'cp'), 'below_min_points');
select tt.err('T7 more than the balance refused', format($$select customer_points_redeem(%L, 500)$$, :'cp'), 'not_enough_points');
select customer_points_redeem(:'cp'::uuid, 40, null, null, true) as rd \gset
select tt.chk('T7 redeem PREVIEW: 40 points x 0.5 = 20 taka, nothing written', (:'rd'::jsonb ->> 'value_taka')::numeric=20 and (:'rd'::jsonb ->> 'balance_after')::int=44 and customer_points(:'cp'::uuid)=84);
select customer_points_redeem(:'cp'::uuid, 40, 'bill 12', '33333333-3333-3333-3333-333333333333') as rd2 \gset
select tt.chk('T7 redeem writes -40 once; the same key again is a dup', (:'rd2'::jsonb ->> 'balance')::int=44 and (customer_points_redeem(:'cp'::uuid, 40, 'bill 12', '33333333-3333-3333-3333-333333333333') ->> 'dup')::boolean and customer_points(:'cp'::uuid)=44);
select tt.as(:'o');
select set_rule('loyalty_points_on','false') is null as lp0 \gset
select tt.as(:'sp'); select tt.err('T7 redeem is closed while the switch is OFF', format($$select customer_points_redeem(%L, 40)$$, :'cp'), 'loyalty_off');
select tt.as(:'o'); select set_rule('loyalty_points_on','true') is null as lp1 \gset
-- void a sale: the points go back
select void_sale((:'ps1')::uuid, 'wrong bill') is null as vs \gset
select tt.chk('T7 a voided sale takes its points back once (-37 adjust), balance 7', (select delta=-37 from customer_points_ledger where sale_id=:'ps1'::uuid and reason='adjust') and customer_points(:'cp'::uuid)=7);

\echo == T8 gifts
select tt.as(:'sp');
select tt.chk('T8 switch OFF: nothing is due', (select count(*) from gifts_due(:'cp'::uuid))=0);
select tt.as(:'o'); select set_rule('customer_gifts_on','true') is null as gs \gset
select customer_save(:'cp'::uuid, format('{"birthday":"%s"}', to_char((now() at time zone 'Asia/Dhaka')::date - 100, 'YYYY-MM-DD'))::jsonb) is not null as bd0 \gset
select tt.chk('T8 birthday far away: nothing due', (select count(*) from gifts_due(:'cp'::uuid) where kind='birthday')=0);
select gift_rule_save(null, '{"trigger":"birthday","gift_text_bn":"মিষ্টির বাক্স","gift_text_en":"Sweet box","value_taka":300,"valid_days":10}') ->> 'id' as gr_b \gset
select gift_rule_save(null, format('{"trigger":"every_n_purchases","threshold":"3","tier_id":"%s","gift_text_en":"Free tea"}', :t_gold)::jsonb) ->> 'id' as gr_n \gset
select gift_rule_save(null, '{"trigger":"spend_threshold","threshold":"2000","gift_text_en":"Mug"}') ->> 'id' as gr_s \gset
select gift_rule_save(null, '{"trigger":"first_purchase","gift_text_en":"Welcome card"}') ->> 'id' as gr_f \gset
select tt.err('T8 a threshold is required for every_n', $$select gift_rule_save(null, '{"trigger":"every_n_purchases","gift_text_en":"x"}')$$, 'threshold_required');
select tt.err('T8 a gift text is required', $$select gift_rule_save(null, '{"trigger":"manual"}')$$, 'gift_text_required');
select tt.err('T8 bad trigger refused', $$select gift_rule_save(null, '{"trigger":"whenever","gift_text_en":"x"}')$$, 'bad_trigger');
-- birthday in 3 days (a birth year long ago)
select customer_save(:'cp'::uuid, format('{"birthday":"1985-%s"}', to_char((now() at time zone 'Asia/Dhaka')::date + 3, 'MM-DD'))::jsonb) is not null as bd1 \gset
select tt.as(:'sp');
select tt.chk('T8 birthday within the 7-day window: the birthday gift is due, not issued yet', (select count(*)=1 and bool_and(not issued) and bool_and(value_taka=300) from gifts_due(:'cp'::uuid) where kind='birthday'));
select tt.chk('T8 spend threshold, first purchase and every-3-purchases (gold, 3 completed sales, 1 voided) are due', (select count(*) from gifts_due(:'cp'::uuid) where kind='spend_threshold')=1
  and (select count(*) from gifts_due(:'cp'::uuid) where kind='first_purchase')=1 and (select count(*) from gifts_due(:'cp'::uuid) where kind='every_n_purchases')=1);
select tt.chk('T8 a gift rule of the gold tier is not shown to a walk-in', (select count(*) from gifts_due((select id from customers where mobile='01899999999')) where kind='every_n_purchases')=0);
select tt.chk('T8 POS info shows the tier, the perks and the gift count', (customer_pos_info('01911111111') -> 'tier' ->> 'code')='gold' and (customer_pos_info('01911111111') ->> 'gifts_due')::int>=3 and (customer_pos_info('01911111111') -> 'tier' ->> 'perks')='Free delivery');
select tt.chk('T8 POS info for an unknown mobile', (customer_pos_info('01500000000') ->> 'found')='false');
select gift_claim(:'cp'::uuid, null, :gr_b::bigint, 'birthday:' || extract(year from (now() at time zone 'Asia/Dhaka')::date + 3)::int) as gc \gset
select tt.chk('T8 claiming a rule gift issues and claims it in one step (who and when stored)', (:'gc'::jsonb ->> 'dup')='false' and exists (select 1 from customer_gifts g where g.customer_id=:'cp' and g.rule_id=:gr_b and g.claimed_at is not null and g.claimed_by=:'sp' and g.claimed_staff is not null and g.value_taka=300));
select tt.chk('T8 claiming again is idempotent: dup, one row, same time', (gift_claim(:'cp'::uuid, null, :gr_b::bigint, 'birthday:' || extract(year from (now() at time zone 'Asia/Dhaka')::date + 3)::int) ->> 'dup')='true'
  and (select count(*) from customer_gifts where customer_id=:'cp' and rule_id=:gr_b)=1);
select tt.chk('T8 a claimed gift is no longer due', (select count(*) from gifts_due(:'cp'::uuid) where kind='birthday')=0);
select tt.err('T8 a gift that is not due cannot be claimed', format($$select gift_claim(%L, null, %s, 'nth:99')$$, :'cp', :gr_n), 'gift_not_due');
select tt.err('T8 claim of an unknown gift id refused', format($$select gift_claim(%L, gen_random_uuid())$$, :'cp'), 'gift_not_found');
select tt.err('T8 staff cannot issue a one-off gift', format($$select gift_issue(%L, 'বই', 'A book')$$, :'cp'), 'not allowed');
select tt.as(:'s');
select gift_issue(:'cp'::uuid, 'বই', 'A book', 150, current_date + 5, 'complaint', '44444444-4444-4444-4444-444444444444') ->> 'id' as mg \gset
select tt.chk('T8 manager issues a one-off gift; same key again = dup', (gift_issue(:'cp'::uuid, 'বই', 'A book', 150, current_date + 5, 'complaint', '44444444-4444-4444-4444-444444444444') ->> 'dup')='true'
  and (select count(*) from customer_gifts where customer_id=:'cp' and rule_id is null)=1);
select tt.as(:'sp');
select tt.chk('T8 the one-off gift shows as issued and due', (select count(*) from gifts_due(:'cp'::uuid) where issued and kind='manual')=1);
select gift_claim(:'cp'::uuid, :'mg'::uuid) ->> 'dup' as c1d \gset
select tt.chk('T8 claim by id works once, then dup', :'c1d'='false' and (gift_claim(:'cp'::uuid, :'mg'::uuid) ->> 'dup')='true');
reset role;
insert into customer_gifts (customer_id, rule_id, occasion, gift_text_en, valid_until) values (:'cp'::uuid, null, 'manual:old', 'Old gift', current_date - 1) returning id as og \gset
set role authenticated; select tt.as(:'sp');
select tt.chk('T8 an expired gift is not listed', (select count(*) from gifts_due(:'cp'::uuid) where text_en='Old gift')=0);
select tt.err('T8 an expired gift cannot be claimed', format($$select gift_claim(%L, %L)$$, :'cp', :'og'), 'gift_expired');
select tt.err('T8 staff cannot write gifts directly', $$update customer_gifts set claimed_at=null$$, 'permission denied');
select tt.as(:'o'); select set_rule('customer_gifts_on','false') is null as gs0 \gset
select tt.as(:'sp'); select tt.err('T8 claim is closed while gifts are OFF', format($$select gift_claim(%L, %L)$$, :'cp', :'mg'), 'gifts_off');

\echo == T9 reading: directory, profile, permissions
select tt.as(:'sp');
select tt.chk('T9 directory lists customers with spend, orders, points, tier', (select count(*)>=10 from customer_directory()) and (select tier_id=:t_gold and orders>=3 and spend>=6000 from customer_directory() where mobile='01801000002')
  and (select points=7 from customer_directory() where mobile='01911111111'));
select tt.chk('T9 directory spend is net of returns (E: 6000 - 3000)', (select spend from customer_directory() where mobile='01801000005')=3000);
select customer_profile(:'cp'::uuid) as pf \gset
select tt.chk('T9 profile: totals, points, history, gifts, recent sales', (:'pf'::jsonb ->> 'orders')::int>=3 and jsonb_typeof(:'pf'::jsonb -> 'history')='array' and jsonb_array_length(:'pf'::jsonb -> 'gifts')>=2 and jsonb_array_length(:'pf'::jsonb -> 'recent_sales')>=3 and (:'pf'::jsonb ->> 'points')::int=7);
select tt.chk('T9 profile has no cost or salary field', not (:'pf'::jsonb::text ~* 'cost|salary'));
select tt.as(:'k'); select tt.err('T9 a storekeeper cannot open a profile', format($$select customer_profile(%L)$$, :'cp'), 'not allowed');
select tt.chk('T9 a storekeeper sees no points ledger rows', (select count(*) from customer_points_ledger)=0);
select tt.as(:'sp2');
select tt.chk('T9 location scope: a salesperson of place 2 sees none of place 1 sales in the directory numbers', (select spend=0 and orders=0 from customer_directory() where mobile='01801000002'));
select tt.chk('T9 and none in the profile recent sales', jsonb_array_length(customer_profile((select id from customers where mobile='01801000002')) -> 'recent_sales')=0);
reset role;
select tt.chk('T9 both triggers on sales are separate from record_sale2', (select count(*) from pg_trigger where tgname in ('sales_tier_use43','sales_loyalty43','sales_loyalty_void43') and not tgisinternal)=3);
select tt.chk('T9 audit log has the customer and tier edits', exists (select 1 from audit_log where table_name='customers' and action='update'));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
