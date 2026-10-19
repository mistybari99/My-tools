-- Phase 503 tests (customer due takes off applied advances). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain through phase 502).
-- Prints PASS / FAIL per check. The switch is set straight in the rules table and put back to OFF at the end.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f504'
\set sl '00000000-0000-0000-0000-00000000f505'
create schema if not exists t503;
create table if not exists t503.res (name text, ok boolean);
truncate t503.res;
create or replace function t503.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t503.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;

insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner502@test.invalid', '{"full_name":"test_owner502"}') on conflict do nothing;
insert into auth.users (id, email, raw_user_meta_data) values (:'sl', 'test_sales502@test.invalid', '{"full_name":"test_sales502"}') on conflict do nothing;
update profiles set status = 'active';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
insert into user_roles values (:'sl', 'salesperson') on conflict do nothing;
insert into user_locations values (:'o', 1) on conflict do nothing;
insert into user_locations values (:'sl', 1) on conflict do nothing;
insert into customers (id, mobile, name, type, active, tier_locked) values (gen_random_uuid(), '01700000504', 'test t503 customer', 'retail', true, false) on conflict do nothing;
insert into customers (id, mobile, name, type, active, tier_locked) values (gen_random_uuid(), '01700000505', 'test t503 advance only', 'retail', true, false) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, tracked, sell_price, is_active, sellable) values ('test_t503_a', 'test t503 a', 'test t503 a', 'kg', false, 100, true, true) on conflict do nothing;
select id as cu from customers where mobile = '01700000504' \gset
select id as cu2 from customers where mobile = '01700000505' \gset
select id as ia from items where code = 'test_t503_a' \gset

\echo == T0 switch exists, default off
select t503.chk('T0 dues_net_advance_on exists, default off', (select default_value = 'false'::jsonb from rules where key = 'dues_net_advance_on'));

\echo == T1 a credit sale of 500 and an advance of 300 applied (switch off: the due still shows 500, as today)
select set_config('request.jwt.claim.sub', :'sl', false);
select (record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":5,"price":100,"unit":"kg"}]', :'ia')::jsonb, 0, '[]', '01700000504', 'test t503 customer', 'retail', null, false, now()) ->> 'id') as s1 \gset
select set_config('request.jwt.claim.sub', :'o', false);
select cash_move_add(1, 'cust_advance', 300, null, 'cash', :'cu'::uuid, 'test advance', null, gen_random_uuid(), false) ->> 'id' as adv \gset
select cash_move_add(1, 'cust_advance_used', 300, null, 'cash', :'cu'::uuid, 'applied to the sale', 'test', gen_random_uuid(), false) ->> 'id' as used \gset
select balance as due_off from customer_dues() where id = :'cu'::uuid \gset
select t503.chk('T1a OFF: due shows 500 after 300 applied (defect as today)', :'due_off'::numeric = 500);
select t503.chk('T1b the advance balance is 0 after it was used', (select balance from customer_advances() where customer_id = :'cu'::uuid) is null);

\echo == T2 switch on: the due is 200
update rules set value = 'true'::jsonb where key = 'dues_net_advance_on';
select balance as due_on from customer_dues() where id = :'cu'::uuid \gset
select t503.chk('T2a ON: due shows 200 (500 less the 300 applied)', :'due_on'::numeric = 200);

\echo == T3 an advance with no sale is not a due
select cash_move_add(1, 'cust_advance', 100, null, 'cash', :'cu2'::uuid, 'advance only', null, gen_random_uuid(), false) ->> 'id' as adv2 \gset
select cash_move_add(1, 'cust_advance_used', 100, null, 'cash', :'cu2'::uuid, 'applied to nothing', null, gen_random_uuid(), false) ->> 'id' as used2 \gset
select t503.chk('T3a ON: a customer with no sale does not appear in the due list', not exists (select 1 from customer_dues() where id = :'cu2'::uuid));

\echo == T4 switch back to off
update rules set value = null where key = 'dues_net_advance_on';
select t503.chk('T4 switch back to default off', not rule_on('dues_net_advance_on'));
select balance as due_back from customer_dues() where id = :'cu'::uuid \gset
select t503.chk('T4b OFF again: due shows 500', :'due_back'::numeric = 500);

\echo == RESULT
select 'phase503 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t503.res;
select name from t503.res where not ok;
