-- Phase 501 tests (sweets sale stock: unknown unit, late sale, return factor). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain through phase 501).
-- Prints PASS / FAIL per check. Switches are set straight in the rules table (no two-factor here) and put back to OFF at the end.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f500'
\set sl '00000000-0000-0000-0000-00000000f501'
create schema if not exists t501;
create table if not exists t501.res (name text, ok boolean);
truncate t501.res;
create or replace function t501.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t501.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t501.err(p_name text, p_sql text, p_msg text) returns void language plpgsql as $$
begin execute p_sql; perform t501.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform t501.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;

-- an owner (returns, switches) and a salesperson at place 1 (sales)
insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner500@test.invalid', '{"full_name":"test_owner500"}') on conflict do nothing;
insert into auth.users (id, email, raw_user_meta_data) values (:'sl', 'test_sales501@test.invalid', '{"full_name":"test_sales501"}') on conflict do nothing;
update profiles set status = 'active';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
insert into user_roles values (:'sl', 'salesperson') on conflict do nothing;
insert into user_locations values (:'sl', 1) on conflict do nothing;

insert into items (code, name_bn, name_en, unit, base_unit, tracked, sell_price, is_active, sellable) values
  ('test_t501_b', 'test t501 b', 'test t501 b', 'kg', null, true, 100, true, true),
  ('test_t501_e', 'test t501 e', 'test t501 e', 'box', 'piece', true, 100, true, true),
  ('test_t501_d', 'test t501 d', 'test t501 d', 'box', 'piece', true, 100, true, true) on conflict do nothing;
select id as ib from items where code = 'test_t501_b' \gset
select id as ie from items where code = 'test_t501_e' \gset
select id as idd from items where code = 'test_t501_d' \gset
insert into unit_conversions (item_id, from_unit, to_unit, factor, active) values (:'idd'::uuid, 'box', 'piece', 12, true) on conflict do nothing;
select stock_post(:'ib'::uuid, 1, 5, 'opening', 'test', 't501-b', 50, null, now(), null, null, null, null, null) is not null as s1 \gset
select stock_post(:'ie'::uuid, 1, 50, 'opening', 'test', 't501-e', 5, null, now(), null, null, null, null, null) is not null as s2 \gset
select stock_post(:'idd'::uuid, 1, 120, 'opening', 'test', 't501-d', 5, null, now(), null, null, null, null, null) is not null as s3 \gset
select set_config('request.jwt.claim.sub', :'sl', false);

\echo == T0 switches exist and default OFF; the factor table is closed to the browser
select t501.chk('T0 two switches exist, default off', (select count(*) = 2 from rules where key in ('stock_unit_unknown_block', 'return_sale_factor_on') and default_value = 'false'::jsonb));
select t501.chk('T0 switches are off now', not rule_on('stock_unit_unknown_block') and not rule_on('return_sale_factor_on'));
select t501.chk('T0 sale_base_factor: row security on, no anon or authenticated grant', (select relrowsecurity from pg_class where oid = 'public.sale_base_factor'::regclass)
  and not has_table_privilege('authenticated', 'public.sale_base_factor', 'select') and not has_table_privilege('anon', 'public.sale_base_factor', 'select'));

\echo == T1 unknown unit: kept with a warning and no stock movement (switch off, as today)
select (record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":2,"price":100,"unit":"box"}]', :'ie')::jsonb, 0, '[{"mode":"cash","amount":200}]', null, null, 'retail', null, false, now()) ->> 'id') as u1 \gset
select t501.chk('T1a OFF: sale of 2 box kept (no conversion box to piece for item e)', :'u1' is not null);
select t501.chk('T1b OFF: stock not reduced (still 50 piece)', (select qty from stock_balance where item_id = :'ie'::uuid and location_id = 1) = 50);
select t501.chk('T1c OFF: yellow stock_unit_unknown exception written', (select count(*) from exceptions where flag_code = 'stock_unit_unknown' and sale_id = :'u1'::uuid) = 1);

\echo == T2 unknown unit refused with the switch on
update rules set value = 'true'::jsonb where key = 'stock_unit_unknown_block';
select t501.err('T2a ON: sale refused with stock_unit_unknown', format('select record_sale2(gen_random_uuid(), 1, %L::jsonb, 0, %L::jsonb, null, null, %L, null, false, now())',
  format('[{"item_id":"%s","qty":2,"price":100,"unit":"box"}]', :'ie'), '[{"mode":"cash","amount":200}]', 'retail'), 'stock_unit_unknown');
select t501.chk('T2b ON: stock still 50 after the refused sale', (select qty from stock_balance where item_id = :'ie'::uuid and location_id = 1) = 50);
update rules set value = null where key = 'stock_unit_unknown_block';

\echo == T3 late sale under block: kept, stock negative, owner told (decision L1)
update rules set value = '"block"'::jsonb where key = 'stock_negative_mode';
select (record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":9,"price":100,"unit":"kg"}]', :'ib')::jsonb, 0, '[{"mode":"cash","amount":900}]', null, null, 'retail', null, false, now() - interval '10 minutes') ->> 'id') as l1 \gset
select t501.chk('T3a late sale 10 minutes old accepted under block (decision L1)', :'l1' is not null);
select t501.chk('T3b and the stock went negative (5 - 9 = -4)', (select qty from stock_balance where item_id = :'ib'::uuid and location_id = 1) = -4);
select t501.chk('T3c with a yellow stock_negative exception for the owner', (select count(*) from exceptions where flag_code = 'stock_negative' and sale_id = :'l1'::uuid) = 1);
select t501.err('T3d a fresh sale of 1 kg under block is refused (the block still works for live sales)', format('select record_sale2(gen_random_uuid(), 1, %L::jsonb, 0, %L::jsonb, null, null, %L, null, false, now())',
  format('[{"item_id":"%s","qty":1,"price":100,"unit":"kg"}]', :'ib'), '[{"mode":"cash","amount":100}]', 'retail'), 'insufficient_stock');
update rules set value = null where key = 'stock_negative_mode';

\echo == T4 the factor of each sale is kept
select (record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":2,"price":100,"unit":"box"}]', :'idd')::jsonb, 0, '[{"mode":"cash","amount":200}]', null, null, 'retail', null, false, now()) ->> 'id') as s_d1 \gset
select t501.chk('T4a sale of 2 box at factor 12: 24 piece out (stock 96)', (select qty from stock_balance where item_id = :'idd'::uuid and location_id = 1) = 96);
select t501.chk('T4b the factor 12 is saved for that sale', (select factor from sale_base_factor where sale_id = :'s_d1'::uuid and item_id = :'idd'::uuid and unit = 'box') = 12);

\echo == T5 return after the factor was edited to 10, switch OFF (defect as today: 4 piece lost)
update unit_conversions set factor = 10 where item_id = :'idd'::uuid and from_unit = 'box';
select set_config('request.jwt.claim.sub', :'o', false);
select sale_return(gen_random_uuid(), :'s_d1'::uuid, format('[{"item_id":"%s","qty":2,"unit":"box"}]', :'idd')::jsonb,
  (select value_code from option_lists where list_code = 'return_reasons' and active order by value_code limit 1), 't501 return off', 'cash') ->> 'id' as r_d1 \gset
select t501.chk('T5a OFF: return puts back 20 piece with today factor 10 (defect)', (select qty from stock_balance where item_id = :'idd'::uuid and location_id = 1) = 116);

\echo == T6 return after the factor was edited, switch ON: the factor of the sale is used (24 piece back)
select set_config('request.jwt.claim.sub', :'sl', false);
update unit_conversions set factor = 12 where item_id = :'idd'::uuid and from_unit = 'box';
select (record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":2,"price":100,"unit":"box"}]', :'idd')::jsonb, 0, '[{"mode":"cash","amount":200}]', null, null, 'retail', null, false, now()) ->> 'id') as s_d2 \gset
update unit_conversions set factor = 10 where item_id = :'idd'::uuid and from_unit = 'box';
update rules set value = 'true'::jsonb where key = 'return_sale_factor_on';
select set_config('request.jwt.claim.sub', :'o', false);
select sale_return(gen_random_uuid(), :'s_d2'::uuid, format('[{"item_id":"%s","qty":2,"unit":"box"}]', :'idd')::jsonb,
  (select value_code from option_lists where list_code = 'return_reasons' and active order by value_code limit 1), 't501 return on', 'cash') ->> 'id' as r_d2 \gset
select t501.chk('T6a ON: return puts back 24 piece (the factor of the sale)', (select qty from stock_balance where item_id = :'idd'::uuid and location_id = 1) = 116);

\echo == T7 the switches go back to OFF (the test leaves the database as it was)
update rules set value = null where key in ('stock_unit_unknown_block', 'return_sale_factor_on', 'stock_negative_mode');
update unit_conversions set factor = 12 where item_id = :'idd'::uuid and from_unit = 'box';
select t501.chk('T7 switches back to default off', not rule_on('stock_unit_unknown_block') and not rule_on('return_sale_factor_on'));

\echo == RESULT
select 'phase501 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t501.res;
select name from t501.res where not ok;
