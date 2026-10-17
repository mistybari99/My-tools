-- FRESH DB ONLY. Phase 433 tests (RPT-B3 R6b: stockout log, shelf life not set, actual yield report). Needs phases 8 to 99, 430 to 433.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase433_test.sql | grep -E 'FAIL|RESULT'
-- Neutral test_* data only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set f '00000000-0000-0000-0000-000000000004'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.d() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_sales@s.app','{"full_name":"test_sales"}'), (:'k','test_store@s.app','{"full_name":"test_store"}'), (:'f','test_far@s.app','{"full_name":"test_far"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),(:'f','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'f',3) on conflict do nothing;
insert into rule_grants (grant_code, role_code) values ('report_stock','storekeeper') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('test_raw_a','test_raw_a','test_raw_a','kg','kg','raw_material',true,0), ('test_fg_a','test_fg_a','test_fg_a','kg','kg','finished_good',true,10),
 ('test_fg_b','test_fg_b','test_fg_b','kg','kg','finished_good',true,10), ('test_fg_c','test_fg_c','test_fg_c','kg','kg','finished_good',false,10);
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, is_active) values ('test_fg_off','test_fg_off','test_fg_off','kg','kg','finished_good',false,10,false);
select id as ra from items where code='test_raw_a' \gset
select id as fg from items where code='test_fg_a' \gset
select id as fgb from items where code='test_fg_b' \gset
select id as fgc from items where code='test_fg_c' \gset
select id as fgo from items where code='test_fg_off' \gset

\echo == T0 shape
select tt.chk('T0 table has RLS; browsers cannot write; functions: authenticated yes, anon no', (select relrowsecurity from pg_class where oid='public.stockout_log'::regclass) and not has_table_privilege('authenticated','public.stockout_log','insert')
  and has_function_privilege('authenticated','public.stockout_add(date,int,uuid,text,numeric,text,uuid)','execute') and not has_function_privilege('anon','public.stockout_add(date,int,uuid,text,numeric,text,uuid)','execute')
  and not has_function_privilege('authenticated','public._rb3_stockout_ok(int)','execute'));
select tt.chk('T0 grant stockout_log seeded to the four shop roles', (select string_agg(role_code, ',' order by role_code) from rule_grants where grant_code='stockout_log')='management,salesperson,showroom_manager,storekeeper');

\echo == T1 stockout entry
select tt.as(:'s'); set role authenticated;
select stockout_add(tt.d(), 1, :'fg'::uuid, 'test sold out by noon', 5, 'kg', 'd4330000-0000-0000-0000-000000000001') ->> 'id' as so1 \gset
select tt.chk('T1 a salesperson at the shop logs a stockout with an estimate', :'so1' is not null);
select tt.chk('T1 the same client id returns the same entry', (stockout_add(tt.d(), 1, :'fg'::uuid, 'again', 5, 'kg', 'd4330000-0000-0000-0000-000000000001') ->> 'dup')::boolean);
select stockout_add(tt.d(), 1, :'fg'::uuid, 'test no estimate', null, null, null) ->> 'id' as so2 \gset
select stockout_add(tt.d() - 1, 1, :'fgb'::uuid, null, null, null, null) ->> 'id' as so3 \gset
select tt.chk('T1 an entry with only date, place and item is enough', :'so3' is not null);
select tt.err('T1 a future date is refused', format($$select stockout_add(tt.d()+2, 1, '%s'::uuid)$$, :'fg'), 'bad_date');
select tt.err('T1 an inactive item is refused', format($$select stockout_add(tt.d(), 1, '%s'::uuid)$$, :'fgo'), 'item_not_found');
select tt.err('T1 a zero estimate is refused', format($$select stockout_add(tt.d(), 1, '%s'::uuid, null, 0, 'kg')$$, :'fg'), 'bad_qty');
select tt.err('T1 an unknown unit is refused', format($$select stockout_add(tt.d(), 1, '%s'::uuid, null, 3, 'bag')$$, :'fg'), 'unit_unknown');
select tt.err('T1 a note over 300 characters is refused', format($$select stockout_add(tt.d(), 1, '%s'::uuid, '%s')$$, :'fg', repeat('x',301)), 'bad_note');
select tt.err('T1 a place that does not exist is refused', format($$select stockout_add(tt.d(), 9999, '%s'::uuid)$$, :'fg'), 'bad_location');
reset role; select tt.as(:'f'); set role authenticated;
select tt.err('T1 a person at place 3 cannot log for place 1', format($$select stockout_add(tt.d(), 1, '%s'::uuid)$$, :'fg'), 'not allowed');
reset role;
select tt.chk('T1 estimate stored in base unit; blank stays null (not 0)', (select est_missed_qty from stockout_log where id=:'so1'::uuid)=5 and (select est_missed_qty is null from stockout_log where id=:'so2'::uuid));

\echo == T2 list, summary, void
select tt.as(:'k'); set role authenticated;
select tt.chk('T2 a storekeeper (grant + report right) lists the three entries of the month', jsonb_array_length(stockout_list() -> 'rows')=3);
select stockout_summary() as sm \gset
select tt.chk('T2 summary: item A has 2 events on 1 day, estimate total 5 from 1 captured, 1 NOT captured (not added as 0)', (select (x->>'events')::int=2 and (x->>'days')::int=1 and (x->>'est_missed_total')::numeric=5 and (x->>'est_captured_n')::int=1 and (x->>'est_not_captured_n')::int=1
  from jsonb_array_elements(:'sm'::jsonb -> 'rows') x where x->>'code'='test_fg_a'));
select tt.chk('T2 summary: item B (no estimate at all) has est_missed_total null, never 0', (select x->'est_missed_total'='null'::jsonb and (x->>'est_not_captured_n')::int=1 from jsonb_array_elements(:'sm'::jsonb -> 'rows') x where x->>'code'='test_fg_b'));
select tt.chk('T2 on_hand_now is null where there is no balance row (not shown as 0)', (select x->'on_hand_now'='null'::jsonb from jsonb_array_elements(:'sm'::jsonb -> 'rows') x where x->>'code'='test_fg_b'));
select tt.err('T2 void needs a note', format($$select stockout_void('%s'::uuid, 'x')$$, :'so2'), 'note_required');
select tt.chk('T2 another holder of the grant may void with a note', (stockout_void(:'so2'::uuid, 'test entered twice') ->> 'status')='void');
select tt.chk('T2 voided entries leave the list and the summary; they show with p_with_void', jsonb_array_length(stockout_list() -> 'rows')=2 and jsonb_array_length(stockout_list(null,null,null,null,true) -> 'rows')=3
  and (select (x->>'events')::int from jsonb_array_elements(stockout_summary() -> 'rows') x where x->>'code'='test_fg_a')=1);
select tt.err('T2 bad range refused', 'select stockout_list(tt.d(), tt.d()-2)', 'bad_range');
reset role; select tt.as(:'f'); set role authenticated;
select tt.err('T2 place 3 user cannot read place 1', 'select stockout_list(null,null,1)', 'not allowed');
select tt.chk('T2 place 3 user sees none of place 1 in the all-places list', jsonb_array_length(stockout_list() -> 'rows')=0);
reset role;

\echo == T3 shelf life not set
select tt.as(:'o'); set role authenticated;
select recipe_save(null, :'fg'::uuid, 10, 'kg', 'x', format('[{"ingredient_item_id":"%s","qty":20,"unit":"kg","waste_pct":0}]', :'ra')::jsonb) ->> 'id' as rid \gset
select recipe_set_active(:'rid'::uuid, true) is null as rs \gset
select tt.chk('T3 a product with an active recipe and no shelf-life rule is listed', (select count(*) from jsonb_array_elements(shelf_life_missing() -> 'items') x where x->>'code'='test_fg_a' and x->>'why'='recipe')=1);
select tt.chk('T3 a product that is not made in the factory is not listed', (select count(*) from jsonb_array_elements(shelf_life_missing() -> 'items') x where x->>'code' in ('test_fg_b','test_raw_a','test_fg_c'))=0);
reset role;
insert into shelf_life_rules (item_id, value, unit) values (:'fg', 2, 'days');
select tt.as(:'o'); set role authenticated;
select tt.chk('T3 once a rule applies, the product is no longer listed', (shelf_life_missing() ->> 'count')::int=0);
reset role;
update shelf_life_rules set active=false where item_id=:'fg';
select tt.as(:'o'); set role authenticated;
select tt.chk('T3 retiring the rule brings the notice back', (shelf_life_missing() ->> 'count')::int=1);
reset role;
insert into shelf_life_rules (item_id, category, value, unit) values (null, null, 3, 'days');
select tt.as(:'o'); set role authenticated;
select tt.chk('T3 an "all items" rule clears the notice (the same answer shelf_life_for gives)', (shelf_life_missing() ->> 'count')::int=0);
reset role;
delete from shelf_life_rules;

\echo == T4 actual yield report
select tt.as(:'o'); set role authenticated;
select stock_opening(:'ra'::uuid, 1, 500, 5, 'kg', 'x') is not null as op \gset
select production_post(1, :'rid'::uuid, 1, null, null, 'test run std') ->> 'run_id' as run1 \gset
select production_post(1, :'rid'::uuid, 1, null, null, 'test run actual', 9) ->> 'run_id' as run2 \gset
select yield_report() as yr \gset
select tt.chk('T4 two runs listed; the run with no typed yield says null, never the standard', (select count(*) from jsonb_array_elements(:'yr'::jsonb -> 'rows'))=2
  and (select x->'yield_actual'='null'::jsonb and x->'var_pct'='null'::jsonb from jsonb_array_elements(:'yr'::jsonb -> 'rows') x where x->>'run_id'=:'run1'));
select tt.chk('T4 the run with 9 kg actual against 10 kg standard: -10 %', (select (x->>'yield_actual')::numeric=9 and (x->>'yield_std')::numeric=10 and (x->>'var_pct')::numeric=-10 from jsonb_array_elements(:'yr'::jsonb -> 'rows') x where x->>'run_id'=:'run2'));
select tt.chk('T4 summary: 2 runs, 1 captured, 1 not captured; difference computed only on the captured run', (select (x->>'runs')::int=2 and (x->>'actual_captured')::int=1 and (x->>'actual_not_captured')::int=1 and (x->>'var_pct')::numeric=-10 and (x->>'std_of_captured')::numeric=10
  from jsonb_array_elements(:'yr'::jsonb -> 'summary') x where x->>'code'='test_fg_a'));
select tt.chk('T4 each row carries the finished batch id for the drill-down', (select count(*) from jsonb_array_elements(:'yr'::jsonb -> 'rows') x where x->>'batch_id' is not null)=2);
select tt.err('T4 bad range refused', 'select yield_report(tt.d(), tt.d()-1)', 'bad_range');
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T4 a salesperson (no stock report right, no recipe right) cannot read it', 'select yield_report()', 'not allowed');
reset role; select tt.as(:'f'); set role authenticated;
select tt.chk('T4 a storekeeper at place 3 sees no run of place 1', jsonb_array_length(yield_report() -> 'rows')=0);
reset role;

\echo == T5 nothing moved by the reports
select tt.chk('T5 the stockout functions wrote no ledger row', (select count(*) from stock_ledger where reason not in ('opening','issue_out','production_in'))=0);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
