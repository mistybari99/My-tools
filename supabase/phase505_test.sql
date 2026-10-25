-- Phase 505 tests (stock tracking mapping tool). TEST DATABASE ONLY (a local throwaway Postgres built from the owner paste chain through phase 504).
-- Prints PASS / FAIL per check. The switch is set straight in the rules table and put back to OFF at the end. Test items are neutral test_* codes.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-00000000f507'
\set sl '00000000-0000-0000-0000-00000000f508'
create schema if not exists t505;
create table if not exists t505.res (name text, ok boolean);
truncate t505.res;
create or replace function t505.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t505.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function t505.err(p_name text, p_sql text, p_msg text) returns void language plpgsql as $$
begin execute p_sql; perform t505.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform t505.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;

insert into auth.users (id, email, raw_user_meta_data) values (:'o', 'test_owner504@test.invalid', '{"full_name":"test_owner504"}') on conflict do nothing;
insert into auth.users (id, email, raw_user_meta_data) values (:'sl', 'test_sales504@test.invalid', '{"full_name":"test_sales504"}') on conflict do nothing;
update profiles set status = 'active';
insert into user_roles values (:'o', 'owner') on conflict do nothing;
insert into user_roles values (:'sl', 'salesperson') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, tracked, sell_price, is_active, sellable, item_type) values
  ('test_t505_r1', 'test t505 raw one', 'test t505 raw one', 'kg', false, 0, true, false, 'raw_material'),
  ('test_t505_r2', 'test t505 raw two', 'test t505 raw two', 'kg', false, 0, true, false, 'raw_material') on conflict do nothing;
select set_config('request.jwt.claim.sub', :'o', false);

\echo == T0 the proposals exist for all 8 types and nothing is tracked by the map
select t505.chk('T0a the map has one row per item type (8)', (select count(*) = 8 from stock_tracking_map));
select t505.chk('T0b finished goods and raw materials proposed tracked, assets not', (select bool_and(proposed_tracked) from stock_tracking_map where item_type in ('finished_good', 'raw_material'))
  and (select not bool_or(proposed_tracked) from stock_tracking_map where item_type in ('asset', 'infrastructure')));
select t505.chk('T0c switch exists, default off', (select default_value = 'false'::jsonb from rules where key = 'tracking_map_apply_on'));
select t505.chk('T0d the map is closed to the browser (no direct select for authenticated)', not has_table_privilege('authenticated', 'public.stock_tracking_map', 'select'));

\echo == T1 the plan is read-only and owner only
select t505.chk('T1a plan lists raw_material with its items', (select items_total >= 2 from stock_tracking_plan() where item_type = 'raw_material'));
select t505.chk('T1e the plan has a row for items with no type (may be zero)', (select count(*) = 1 from stock_tracking_plan() where item_type = '(not classified)'));
select count(*) as tracked_before from items where item_type = 'raw_material' and tracked \gset
select t505.chk('T1b plan changed no item', (select count(*) from items where item_type = 'raw_material' and tracked) = :tracked_before);
select set_config('request.jwt.claim.sub', :'sl', false);
select t505.err('T1c a salesperson cannot read the plan', 'select * from stock_tracking_plan()', 'not allowed');
select set_config('request.jwt.claim.sub', :'o', false);

\echo == T2 dry run counts only; a real run needs the switch and a review
select (stock_tracking_apply('raw_material', true) ->> 'would_change')::int as would \gset
select t505.chk('T2a dry run would change the 2 test raw materials', :would = 2);
select t505.chk('T2b dry run changed nothing', (select count(*) from items where item_type = 'raw_material' and tracked) = :tracked_before);
select t505.err('T2c real run refused while the switch is off', 'select stock_tracking_apply(''raw_material'', false)', 'tracking_map_apply_off');
update rules set value = 'true'::jsonb where key = 'tracking_map_apply_on';
select t505.err('T2d real run refused until the owner reviewed the type', 'select stock_tracking_apply(''raw_material'', false)', 'not_reviewed');
select t505.err('T2e review needs a note', 'select stock_tracking_review(''raw_material'', '' '')', 'note_required');
select stock_tracking_review('raw_material', 'test review') ->> 'reviewed' as rv \gset
select t505.chk('T2f review recorded', :'rv' = 'true' and (select reviewed_at is not null from stock_tracking_map where item_type = 'raw_material'));

\echo == T3 the switch on and reviewed: the real run sets the test items to tracked, and only those that differ
select stock_tracking_apply('raw_material', false) ->> 'changed' as ch \gset
select t505.chk('T3a real run changed the 2 test raw materials', :'ch'::int = 2 and (select count(*) from items where item_type = 'raw_material' and tracked) = 2);
select stock_tracking_apply('raw_material', false) ->> 'changed' as ch2 \gset
select t505.chk('T3b a second real run changes nothing (paste twice safe)', :'ch2'::int = 0);

\echo == T4 put the test items and the switches back
update items set tracked = false where item_type = 'raw_material' and code like 'test_t505_%';
update rules set value = null where key = 'tracking_map_apply_on';
update stock_tracking_map set reviewed_by = null, reviewed_at = null, review_note = null where item_type = 'raw_material';
select t505.chk('T4 switch and review back to the start', not rule_on('tracking_map_apply_on') and (select reviewed_at is null from stock_tracking_map where item_type = 'raw_material'));

\echo == RESULT
select 'phase505 tests: ' || count(*) filter (where ok) || ' PASS, ' || count(*) filter (where not ok) || ' FAIL' as result from t505.res;
select name from t505.res where not ok;
