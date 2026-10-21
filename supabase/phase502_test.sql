-- Phase 502 tests (item analysis takes sale returns off). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain through phase 501).
-- Prints PASS / FAIL per check. The switch is set straight in the rules table and put back to OFF at the end.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f502'
\set sl '00000000-0000-0000-0000-00000000f503'
create schema if not exists t502;
create table if not exists t502.res (name text, ok boolean);
truncate t502.res;
create or replace function t502.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t502.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;

insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner501@test.invalid', '{"full_name":"test_owner501"}') on conflict do nothing;
insert into auth.users (id, email, raw_user_meta_data) values (:'sl', 'test_sales503@test.invalid', '{"full_name":"test_sales503"}') on conflict do nothing;
update profiles set status = 'active';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
insert into user_roles values (:'sl', 'salesperson') on conflict do nothing;
insert into user_locations values (:'sl', 1) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, tracked, sell_price, is_active, sellable) values
  ('test_t502_a', 'test t502 a', 'test t502 a', 'kg', false, 100, true, true) on conflict do nothing;
select id as ia from items where code = 'test_t502_a' \gset

\echo == T0 switch exists, default off, grant of biz_items unchanged for anon
select t502.chk('T0 biz_items_net_returns exists, default off', (select default_value = 'false'::jsonb from rules where key = 'biz_items_net_returns'));
select t502.chk('T0 biz_items: anon cannot execute', not has_function_privilege('anon', 'public.biz_items(date,date,integer)', 'execute'));

\echo == T1 a sale of 3 kg and a return of 1 kg today
select set_config('request.jwt.claim.sub', :'sl', false);
select (record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":3,"price":100,"unit":"kg"}]', :'ia')::jsonb, 0, '[{"mode":"cash","amount":300}]', null, null, 'retail', null, false, now()) ->> 'id') as s1 \gset
select set_config('request.jwt.claim.sub', :'o', false);
select sale_return(gen_random_uuid(), :'s1'::uuid, format('[{"item_id":"%s","qty":1,"unit":"kg"}]', :'ia')::jsonb,
  (select value_code from option_lists where list_code = 'return_reasons' and active order by value_code limit 1), 't502', 'cash') ->> 'id' as r1 \gset

\echo == T2 switch OFF: sales before returns (as today)
select qty as q_off, revenue as rev_off from biz_items((now() at time zone 'Asia/Dhaka')::date, (now() at time zone 'Asia/Dhaka')::date, 1) where item_id = :'ia'::uuid \gset
select t502.chk('T2a OFF: 3 kg and 300 shown (returns not taken off)', :'q_off'::numeric = 3 and :'rev_off'::numeric = 300);

\echo == T3 switch ON: returns of the day taken off
update rules set value = 'true'::jsonb where key = 'biz_items_net_returns';
select qty as q_on, revenue as rev_on from biz_items((now() at time zone 'Asia/Dhaka')::date, (now() at time zone 'Asia/Dhaka')::date, 1) where item_id = :'ia'::uuid \gset
select t502.chk('T3a ON: 2 kg and 200 shown after the 1 kg return', :'q_on'::numeric = 2 and :'rev_on'::numeric = 200);
select t502.chk('T3b ON: a period with no sale and no return shows the item at 0 qty and 0 revenue', (select qty = 0 and revenue = 0 from biz_items('2000-01-01', '2000-01-02', 1) where item_id = :'ia'::uuid));

\echo == T4 switch back to OFF
update rules set value = null where key = 'biz_items_net_returns';
select t502.chk('T4 switch back to default off', not rule_on('biz_items_net_returns'));

\echo == RESULT
select 'phase502 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t502.res;
select name from t502.res where not ok;
