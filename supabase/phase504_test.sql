-- Phase 504 tests (a made product as an ingredient, two-stage production). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain through phase 503).
-- Prints PASS / FAIL per check. The switch is set straight in the rules table and put back to OFF at the end.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f506'
create schema if not exists t504;
create table if not exists t504.res (name text, ok boolean);
truncate t504.res;
create or replace function t504.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t504.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t504.err(p_name text, p_sql text, p_msg text) returns void language plpgsql as $$
begin execute p_sql; perform t504.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform t504.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;

insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner503@test.invalid', '{"full_name":"test_owner503"}') on conflict do nothing;
update profiles set status = 'active';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
insert into user_locations values (:'o', 1) on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);
insert into items (code, name_bn, name_en, unit, tracked, sell_price, is_active, sellable, item_type) values
  ('test_t504_y', 'test t504 y (made intermediate)', 'test t504 y', 'kg', true, 0, true, false, 'finished_good'),
  ('test_t504_x', 'test t504 x (made product)', 'test t504 x', 'kg', true, 100, true, true, 'finished_good') on conflict do nothing;
select id as iy from items where code = 'test_t504_y' \gset
select id as ix from items where code = 'test_t504_x' \gset

\echo == T0 switch exists, default off: a made product is refused as an ingredient (as today)
select t504.chk('T0 recipe_intermediate_on exists, default off', (select default_value = 'false'::jsonb from rules where key = 'recipe_intermediate_on'));
select t504.err('T0a OFF: made product as ingredient refused with bad_ingredient_type', format('select recipe_save(null, %L::uuid, 1, ''kg'', ''t504'', %L::jsonb, gen_random_uuid(), false)',
  :'ix', format('[{"ingredient_item_id":"%s","qty":2,"unit":"kg"}]', :'iy')), 'bad_ingredient_type');

\echo == T1 switch on: X made from Y (the intermediate)
update rules set value = 'true'::jsonb where key = 'recipe_intermediate_on';
select recipe_save(null, :'ix'::uuid, 1, 'kg', 't504 x', format('[{"ingredient_item_id":"%s","qty":2,"unit":"kg"}]', :'iy')::jsonb, gen_random_uuid(), false) ->> 'id' as rx \gset
select t504.chk('T1a ON: recipe for X with Y as ingredient saved', :'rx' is not null);

\echo == T2 switch on: a loop is refused (Y made from X, while X is made from Y)
select t504.err('T2a ON: Y made from X refused as a loop', format('select recipe_save(null, %L::uuid, 1, ''kg'', ''t504 loop'', %L::jsonb, gen_random_uuid(), false)',
  :'iy', format('[{"ingredient_item_id":"%s","qty":1,"unit":"kg"}]', :'ix')), 'recipe_loop');

\echo == T3 production of X consumes the stock of Y
select stock_post(:'iy'::uuid, 1, 10, 'count_adjust', 'test', 't504-y', 40, null, now(), null, null, null, null, null) is not null as sy \gset
select production_post(1, :'rx'::uuid, 1, gen_random_uuid(), now(), 't504', null) ->> 'run_id' as run \gset
select t504.chk('T3a production of X ran', :'run' is not null);
select t504.chk('T3b Y consumed: 10 - 2 = 8 kg left at place 1', (select qty from stock_balance where item_id = :'iy'::uuid and location_id = 1) = 8);
select t504.chk('T3c X received its yield (1 kg) at place 1', (select qty from stock_balance where item_id = :'ix'::uuid and location_id = 1) >= 1);

\echo == T4 switch back to off: the refusal is back for new recipes
update rules set value = null where key = 'recipe_intermediate_on';
select t504.err('T4 OFF again: made product refused as ingredient', format('select recipe_save(null, %L::uuid, 1, ''kg'', ''t504 off'', %L::jsonb, gen_random_uuid(), false)',
  :'ix', format('[{"ingredient_item_id":"%s","qty":2,"unit":"kg"}]', :'iy')), 'bad_ingredient_type');

\echo == RESULT
select 'phase504 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t504.res;
select name from t504.res where not ok;
