-- FRESH DB ONLY. Phase 140 tests (W1-FIX finding 4: void_sale follows the return rules when the owner switches void_follows_return_rules ON).
--   build a database through phase 99 (tests/sql/ORDER.txt), paste phase140.sql once, then:
--   psql -h /tmp -p 5610 -U postgres -d a140db -qAt -f supabase/phase140_test.sql | grep -E 'FAIL|RESULT'      (run from the repository root)
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000140'
\set u_c '00000000-0000-0000-0000-000000000240'
\set u_m '00000000-0000-0000-0000-000000000340'
\set u_mo '00000000-0000-0000-0000-000000000440'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
create or replace function tt.bal(p_item uuid) returns numeric language sql stable security definer as $$ select coalesce((select qty from public.stock_balance where item_id = p_item and location_id = 1), 0) $$;
create or replace function tt.sell(p_item uuid, p_qty numeric, p_price numeric) returns uuid language plpgsql as $$
begin
  return (record_sale2(gen_random_uuid(), 1, jsonb_build_array(jsonb_build_object('item_id', p_item, 'qty', p_qty, 'price', p_price, 'unit', 'kg')), 0,
          jsonb_build_array(jsonb_build_object('mode', 'cash', 'amount', p_qty * p_price)), null, null, 'retail', null, false) ->> 'id')::uuid;
end $$;
create or replace function tt.age(p_sale uuid, p_hours numeric) returns void language plpgsql security definer as $$
begin
  perform set_config('session_replication_role', 'replica', true);
  update public.sales set sold_at = now() - make_interval(secs => p_hours * 3600) where id = p_sale;
  perform set_config('session_replication_role', 'origin', true);
end $$;
create or replace function tt.sstat(p_sale uuid) returns text language sql stable security definer as $$ select status from public.sales where id = p_sale $$;
create or replace function tt.exc(p_flag text, p_sale uuid) returns bigint language sql stable security definer as $$
  select count(*) from public.exceptions where flag_code = p_flag and text ->> 'ref' = p_sale::text $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner140@s.app','{"full_name":"test_owner140"}'), (:'u_c','test_cashier140@s.app','{"full_name":"test_cashier140"}'),
 (:'u_m','test_manager140@s.app','{"full_name":"test_manager140"}'), (:'u_mo','test_manager140b@s.app','{"full_name":"test_manager140b"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_c','salesperson'),(:'u_m','management'),(:'u_mo','management') on conflict do nothing;
insert into user_locations values (:'u_c',1),(:'u_m',1),(:'u_mo',1) on conflict do nothing;
update items set unit='kg', base_unit='kg', tracked=true where code in ('I-001','I-002','I-003');
update items set category='test_perish', sell_price=200 where code='I-001';
update items set category='test_dry', sell_price=100 where code='I-002';
update items set category='test_fresh2', sell_price=150 where code='I-003';
select id as i1 from items where code='I-001' \gset
select id as i2 from items where code='I-002' \gset
select id as i3 from items where code='I-003' \gset

\echo == T0 shape, safe default, internals closed, hook in place
select tt.chk('T0 phase140 present; hook marker bos140 is inside void_sale', to_regprocedure('public._w1x_present140()') is not null and position('bos140' in pg_get_functiondef('public.void_sale(uuid,text)'::regprocedure))>0);
select tt.chk('T0 the setting exists as a switch, default OFF, English label and hint',
  (select kind='switch' and default_value='false'::jsonb and label_en ~ '^[A-Za-z]' and hint_en ~ '^[A-Za-z]' from rules where key='void_follows_return_rules') and not rule_on('void_follows_return_rules'));
select tt.chk('T0 internals closed to browsers (guard, patch helper, hook function)',
  not has_function_privilege('authenticated','public._w1x_void_guard(uuid,text)','execute') and not has_function_privilege('anon','public._w1x_void_guard(uuid,text)','execute')
  and not has_function_privilege('authenticated','public._w1x_patch(regprocedure,text[],text)','execute') and not has_function_privilege('authenticated','public._w1x140_hooks()','execute'));
select tt.err('T0 bad marker refused', $$select public._w1x_patch('public.void_sale(uuid,text)'::regprocedure, array['x','y'], 'bos99')$$, 'bad marker');
select tt.err('T0 a patch site that is not there stops with a clear message', $$select public._w1x_patch('public.void_sale(uuid,text)'::regprocedure, array['this text is not in void_sale','y'], 'bos149')$$, 'patch site not found');

\echo == setup: accounting on, stock at place 1, grants
set role authenticated; select tt.as(:'u_o');
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select set_rule('accounting_on','true') is null as on1 \gset
reset role;
insert into shelf_life_rules (item_id, value, unit) values (:'i1'::uuid, 24, 'hours'), (:'i3'::uuid, 24, 'hours');
set role authenticated; select tt.as(:'u_o');
select stock_production_in(:'i1'::uuid,1,30,now(),null,'test tray',null,100) ->> 'batch_id' as b1 \gset
select stock_opening(:'i2'::uuid,1,50,50) is not null as o2 \gset
select stock_production_in(:'i3'::uuid,1,5,now()-interval '30 hours',null,'test old tray',null,80) ->> 'batch_id' as b3old \gset
select stock_production_in(:'i3'::uuid,1,6,now(),null,'test new tray',null,80) ->> 'batch_id' as b3new \gset
select set_user_grant(:'u_mo'::uuid,'return_override') is null as g1 \gset
select _w1c_return_class_set('test_perish','no_restock',null,null,null,'test: never put back') is not null as c1 \gset
reset role;
select tt.chk('setup: stock 30 / 50 / 11; class test_perish is never put back', tt.bal(:'i1'::uuid)=30 and tt.bal(:'i2'::uuid)=50 and tt.bal(:'i3'::uuid)=11
  and (select restock from w1c_return_class_rules where class_code='test_perish')='no_restock');

\echo == T1 setting OFF = today: a void is not asked anything
-- sale A: 4 kg of the never-put-back class, 30 hours old. The manager voids it.
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i1'::uuid,4,200) as sa \gset
reset role;
select tt.age(:'sa'::uuid, 30);
set role authenticated; select tt.as(:'u_m');
select void_sale(:'sa'::uuid, 'test void with the setting off') is null as v1 \gset
reset role;
select tt.chk('T1 OFF: the void works, the whole 4 kg is back (30), no override line, no exception of the new kind',
  tt.sstat(:'sa'::uuid)='void' and tt.bal(:'i1'::uuid)=30 and not exists (select 1 from audit_log where action='void_override') and tt.exc('void_outside_return_rules',:'sa'::uuid)=0);

\echo == T2 setting ON: the same void is refused for a person without the override
set role authenticated; select tt.as(:'u_o');
select set_rule('void_follows_return_rules','true') is null as on2 \gset
reset role;
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i1'::uuid,4,200) as sb \gset
reset role;
select tt.age(:'sb'::uuid, 2);
set role authenticated; select tt.as(:'u_m');
select tt.err('T2 ON: a class that is never put back cannot be voided by the manager (a void would put it all back)', format($$select void_sale(%L::uuid,'test void')$$, :'sb'), 'return_restock_not_allowed');
reset role;
select tt.chk('T2 the refusal wrote nothing: sale still done, stock still 26, no exception, no audit line', tt.sstat(:'sb'::uuid)='done' and tt.bal(:'i1'::uuid)=26
  and not exists (select 1 from audit_log where action='void_override') and tt.exc('void_outside_return_rules',:'sb'::uuid)=0);

\echo == T3 owner and the override grant: allowed, with the reason logged
set role authenticated; select tt.as(:'u_mo');
select tt.err('T3 the override holder still needs a reason of at least three letters', format($$select void_sale(%L::uuid,'ab')$$, :'sb'), 'return_override_reason_required');
select void_sale(:'sb'::uuid, 'test: customer sent it back, checked by hand') is null as v3 \gset
reset role;
select tt.chk('T3 override holder: void done, stock back to 30, audit line with the reason and the broken rule, yellow row in the Exceptions list',
  tt.sstat(:'sb'::uuid)='void' and tt.bal(:'i1'::uuid)=30
  and (select count(*) from audit_log where action='void_override' and record_id=:'sb' and detail->>'reason' like 'test: customer sent it back%' and detail->'rules_broken' ? 'return_restock_not_allowed')=1
  and (select level from exceptions where flag_code='void_outside_return_rules' and text->>'ref'=:'sb')='yellow'
  and exists (select 1 from exceptions where flag_code='sale_void' and sale_id=:'sb'::uuid));
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i1'::uuid,2,200) as sc \gset
select tt.as(:'u_o');
select void_sale(:'sc'::uuid, 'test: owner voids, reason logged') is null as v3b \gset
reset role;
select tt.chk('T3 the owner may void outside the rules too; the reason is in the audit line and in the Exceptions list',
  tt.sstat(:'sc'::uuid)='void' and tt.exc('void_outside_return_rules',:'sc'::uuid)=1
  and (select text->>'en' from exceptions where flag_code='void_outside_return_rules' and text->>'ref'=:'sc') like '%Reason: test: owner voids, reason logged%');

\echo == T4 window: class window and the general window
-- class test_dry gets a 24 hour window. Sale D is 30 hours old, sale E is 2 hours old.
set role authenticated; select tt.as(:'u_o');
select _w1c_return_class_set('test_dry','restock',24,null,null,'test window') is not null as c2 \gset
select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,3,100) as sd2 \gset
select tt.sell(:'i2'::uuid,2,100) as se \gset
reset role;
select tt.age(:'sd2'::uuid, 30); select tt.age(:'se'::uuid, 2);
set role authenticated; select tt.as(:'u_m');
select tt.err('T4 a sale past the class window cannot be voided by the manager', format($$select void_sale(%L::uuid,'test void')$$, :'sd2'), 'return_window_exceeded');
select void_sale(:'se'::uuid, 'test void inside the window') is null as v4 \gset
reset role;
select tt.chk('T4 inside the window the void works with no override line; past the window nothing changed', tt.sstat(:'se'::uuid)='void' and tt.sstat(:'sd2'::uuid)='done' and tt.exc('void_outside_return_rules',:'se'::uuid)=0
  and tt.bal(:'i2'::uuid)=47);
-- general window 10 hours for classes without their own: switch the class window off, set the general one
set role authenticated; select tt.as(:'u_o');
select _w1c_return_class_off('test_dry', 'test off') is not null as c3 \gset
select _w1c_return_global_set(false, 10, 'allow') is not null as gw \gset
select tt.as(:'u_m');
select tt.err('T4 general window 10 hours: the 30 hour old sale is still refused', format($$select void_sale(%L::uuid,'test void')$$, :'sd2'), 'return_window_exceeded');
select tt.as(:'u_mo');
select void_sale(:'sd2'::uuid, 'test: allowed by the override holder') is null as v4b \gset
reset role;
select tt.chk('T4 the override holder voided it: stock back (50), one exception row', tt.sstat(:'sd2'::uuid)='void' and tt.bal(:'i2'::uuid)=50 and tt.exc('void_outside_return_rules',:'sd2'::uuid)=1);
set role authenticated; select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'allow') is not null as gw2 \gset
reset role;

\echo == T5 expired batch: a void cannot write goods off, so it may not put expired goods back (modes writeoff and block)
-- item three: new tray 6 kg, old tray 5 kg (expired). A sale of 8 kg takes 6 from the new tray and 2 from the old one.
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i3'::uuid,8,150) as sf \gset
select tt.as(:'u_m');
select void_sale(:'sf'::uuid, 'test void, mode allow') is null as v5a \gset
reset role;
select tt.chk('T5 mode allow (today): the void works and all 8 kg are back (11)', tt.sstat(:'sf'::uuid)='void' and tt.bal(:'i3'::uuid)=11 and tt.exc('void_outside_return_rules',:'sf'::uuid)=0);
set role authenticated; select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'block') is not null as gb \gset
select tt.as(:'u_c'); select tt.sell(:'i3'::uuid,8,150) as sg \gset
select tt.as(:'u_m');
select tt.err('T5 mode block: the manager cannot void a sale that took goods from an expired tray', format($$select void_sale(%L::uuid,'test void')$$, :'sg'), 'return_expired_restock');
select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'writeoff') is not null as gw3 \gset
select tt.as(:'u_m');
select tt.err('T5 mode writeoff: also refused (a void cannot write the 2 kg off)', format($$select void_sale(%L::uuid,'test void')$$, :'sg'), 'return_expired_restock');
select tt.as(:'u_mo');
select void_sale(:'sg'::uuid, 'test: tray was checked by hand') is null as v5b \gset
reset role;
select tt.chk('T5 override holder: done, RED row in the Exceptions list', tt.sstat(:'sg'::uuid)='void' and (select level from exceptions where flag_code='void_outside_return_rules' and text->>'ref'=:'sg')='red');
set role authenticated; select tt.as(:'u_o'); select _w1c_return_global_set(false, null, 'allow') is not null as gw4 \gset
reset role;

\echo == T6 a sale inside every rule is voided as always, with the setting ON
set role authenticated; select tt.as(:'u_c'); select tt.sell(:'i2'::uuid,1,100) as sh \gset
select tt.as(:'u_m');
select void_sale(:'sh'::uuid, 'test normal void') is null as v6 \gset
reset role;
select tt.chk('T6 normal void: done, stock back, no override line', tt.sstat(:'sh'::uuid)='void' and tt.bal(:'i2'::uuid)=50 and tt.exc('void_outside_return_rules',:'sh'::uuid)=0
  and not exists (select 1 from audit_log where action='void_override' and record_id=:'sh'));
set role authenticated; select tt.as(:'u_m');
select tt.err('T6 the old checks still come first: no note', format($$select void_sale(%L::uuid,'')$$, :'sh'), 'note_required');
select tt.err('T6 an already void sale is still refused', format($$select void_sale(%L::uuid,'again')$$, :'sh'), 'already void');
select tt.as(:'u_c');
select tt.err('T6 a cashier without the void right is still refused', format($$select void_sale(%L::uuid,'x')$$, :'sh'), 'not allowed');
reset role;

\echo == T7 paste twice, hook idempotent, books balanced, no demo names
select public._w1x140_hooks() ->> 'void_sale' as again \gset
select tt.chk('T7 a second call of the hook function changes nothing', :'again'='false' and (select count(*) from rules where key='void_follows_return_rules')=1);
select tt.chk('T7 every journal entry balances', tt.unbalanced()=0);
select tt.chk('T7 no demo data: every name in this file starts with test_', not exists (select 1 from profiles where full_name <> '' and full_name not like 'test\_%'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
