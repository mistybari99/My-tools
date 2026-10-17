-- FRESH DB ONLY. Phase 434 tests (RPT-B3 R7a: price trend value column, agreed prices, preferred / alternative suppliers). Needs phases 8 to 99 and 430 to 434.
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase434_test.sql | grep -E 'FAIL|RESULT'
-- Neutral test_* data only.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set f '00000000-0000-0000-0000-000000000004'
\set u '00000000-0000-0000-0000-000000000005'
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
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'s','test_sales@s.app','{"full_name":"test_sales"}'), (:'k','test_store@s.app','{"full_name":"test_store"}'),
 (:'f','test_far@s.app','{"full_name":"test_far"}'), (:'u','test_buyer@s.app','{"full_name":"test_buyer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','salesperson'),(:'k','storekeeper'),(:'f','storekeeper'),(:'u','purchasing') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'f',3),(:'u',1) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values
 ('test_raw_a','test_raw_a','test_raw_a','kg','kg','raw_material',true,0), ('test_raw_b','test_raw_b','test_raw_b','kg','kg','raw_material',true,0);
insert into suppliers (name) values ('test_supplier_a'), ('test_supplier_b'), ('test_supplier_c');
insert into unit_conversions (from_unit, to_unit, factor) values ('g','kg',0.001) on conflict do nothing;
select id as ra from items where code='test_raw_a' \gset
select id as rb from items where code='test_raw_b' \gset
select id as sa from suppliers where name='test_supplier_a' \gset
select id as sb from suppliers where name='test_supplier_b' \gset
select id as sc from suppliers where name='test_supplier_c' \gset

\echo == T0 shape
select tt.chk('T0 tables: RLS on, prices unreadable by browsers (cost is secret), item_suppliers readable', (select bool_and(relrowsecurity) from pg_class where oid in ('public.supplier_item_prices'::regclass,'public.item_suppliers'::regclass))
  and not has_table_privilege('authenticated','public.supplier_item_prices','select') and has_table_privilege('authenticated','public.item_suppliers','select') and not has_table_privilege('authenticated','public.item_suppliers','insert'));
select tt.chk('T0 functions: authenticated yes, anon no; helpers nobody', has_function_privilege('authenticated','public.supplier_price_set(uuid,uuid,numeric,text,date,text)','execute') and not has_function_privilege('anon','public.supplier_price_list(uuid,uuid,boolean)','execute')
  and not has_function_privilege('authenticated','public._rb3_terms_ok()','execute'));
select tt.chk('T0 grant supplier_terms_manage seeded to purchasing and management only', (select string_agg(role_code, ',' order by role_code) from rule_grants where grant_code='supplier_terms_manage')='management,purchasing');
select tt.chk('T0 the price-trend report keeps all old columns and gains value; its total is value; the cost rule is unchanged', (select jsonb_array_length(cols)=13 and tot=array['value'] and cost and (cols @> '[["avg_rate","গড় দর","Average rate","money"]]'::jsonb) and (cols @> '[["value","মূল্য (পরিমাণ × দর)","Value (quantity x rate)","money"]]'::jsonb) from report_defs3 where key='p2_rate_trend'));

\echo == T1 price trend with value (same engine, one more column)
select tt.as(:'o'); set role authenticated;
select (save_purchase('b4340000-0000-0000-0000-000000000001'::uuid, null, :'sa'::uuid, 1, 'V-1', tt.d() - 10, format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":100},{"item_id":"%s","qty":5,"unit":"kg","unit_cost":40}]', :'ra', :'rb')::jsonb) ->> 'id') as v1 \gset
select post_purchase(:'v1'::uuid) is not null as p1 \gset
select (save_purchase('b4340000-0000-0000-0000-000000000002'::uuid, null, :'sa'::uuid, 1, 'V-2', tt.d() - 2, format('[{"item_id":"%s","qty":10,"unit":"kg","unit_cost":120}]', :'ra')::jsonb) ->> 'id') as v2 \gset
select post_purchase(:'v2'::uuid) is not null as p2 \gset
select (save_purchase('b4340000-0000-0000-0000-000000000003'::uuid, null, :'sb'::uuid, 1, 'V-3', tt.d() - 1, format('[{"item_id":"%s","qty":4,"unit":"kg","unit_cost":130}]', :'ra')::jsonb) ->> 'id') as v3 \gset
select post_purchase(:'v3'::uuid) is not null as p3 \gset
select report_run2('p2_rate_trend', format('{"from":"%s","to":"%s"}', tt.d()-30, tt.d())::jsonb) as rt \gset
select tt.chk('T1 value for item A / supplier A = 10x100 + 10x120 = 2200', (select (r->>'value')::numeric=2200 from jsonb_array_elements(:'rt'::jsonb -> 'rows') r where r->>'item_code'='test_raw_a' and r->>'supplier'='test_supplier_a'));
select tt.chk('T1 value for item A / supplier B = 4x130 = 520; item B / supplier A = 5x40 = 200', (select (r->>'value')::numeric=520 from jsonb_array_elements(:'rt'::jsonb -> 'rows') r where r->>'item_code'='test_raw_a' and r->>'supplier'='test_supplier_b')
  and (select (r->>'value')::numeric=200 from jsonb_array_elements(:'rt'::jsonb -> 'rows') r where r->>'item_code'='test_raw_b'));
select tt.chk('T1 the total of the value column is 2920', (:'rt'::jsonb -> 'totals' ->> 'value')::numeric=2920);
select tt.chk('T1 the old columns are unchanged: average rate A/supplier A = 110, change +20 %', (select (r->>'avg_rate')::numeric=110 and (r->>'change_pct')::numeric=20 from jsonb_array_elements(:'rt'::jsonb -> 'rows') r where r->>'item_code'='test_raw_a' and r->>'supplier'='test_supplier_a'));
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T1 a salesperson still cannot run the cost report', format($$select report_run2('p2_rate_trend', '{"from":"%s","to":"%s"}'::jsonb)$$, tt.d()-30, tt.d()), 'not allowed');
reset role;

\echo == T2 agreed prices
select tt.as(:'u'); set role authenticated;
select tt.chk('T2 purchasing sets an agreed price: 110 per kg from 30 days ago', (supplier_price_set(:'ra'::uuid, :'sa'::uuid, 110, 'kg', tt.d()-30, 'test contract') ->> 'id') is not null);
select tt.chk('T2 a price in grams is stored per base unit (0.05 per g = 50 per kg)', (supplier_price_set(:'rb'::uuid, :'sa'::uuid, 0.05, 'g', tt.d()-30, null) ->> 'price_base')::numeric=50);
select tt.chk('T2 a new price from 5 days ago closes the old one the day before', (supplier_price_set(:'ra'::uuid, :'sa'::uuid, 125, 'kg', tt.d()-5, 'test new contract') ->> 'closed_previous') is not null);
reset role;
select tt.chk('T2 old row now ends 6 days ago, new row is open', (select effective_to from supplier_item_prices where item_id=:'ra' and supplier_id=:'sa' and price=110)=tt.d()-6 and (select effective_to is null from supplier_item_prices where item_id=:'ra' and supplier_id=:'sa' and price=125));
select tt.as(:'u'); set role authenticated;
select tt.err('T2 a price dated before the open one is refused (retire first)', format($$select supplier_price_set('%s'::uuid, '%s'::uuid, 130, 'kg', tt.d()-5)$$, :'ra', :'sa'), 'overlaps_existing');
select tt.err('T2 zero / negative price refused', format($$select supplier_price_set('%s'::uuid, '%s'::uuid, 0, 'kg')$$, :'ra', :'sb'), 'bad_price');
select tt.err('T2 unknown unit refused', format($$select supplier_price_set('%s'::uuid, '%s'::uuid, 5, 'bag')$$, :'ra', :'sb'), 'unit_unknown');
select tt.err('T2 unknown item refused', format($$select supplier_price_set('%s'::uuid, '%s'::uuid, 5)$$, :'sa', :'sb'), 'item_not_found');
select tt.chk('T2 the list shows both lines of the pair (the closed one with its end date) and marks one as current', jsonb_array_length(supplier_price_list(:'ra'::uuid, :'sa'::uuid))=2 and (select count(*) from jsonb_array_elements(supplier_price_list(:'ra'::uuid, :'sa'::uuid)) x where (x->>'current')::boolean)=1);
reset role; select tt.as(:'k'); set role authenticated;
select tt.err('T2 a storekeeper (no terms right, no cost right) cannot set a price', format($$select supplier_price_set('%s'::uuid, '%s'::uuid, 5)$$, :'ra', :'sb'), 'not allowed');
select tt.err('T2 nor read the list (cost)', 'select supplier_price_list()', 'not allowed');
reset role; select tt.as(:'u'); set role authenticated;
reset role;
select id as pid from supplier_item_prices where item_id=:'rb' \gset
select tt.as(:'u'); set role authenticated;
select tt.err('T2 retiring needs a note', format($$select supplier_price_retire(%s, 'x')$$, :'pid'), 'note_required');
select tt.chk('T2 retire with a note', (supplier_price_retire(:'pid'::bigint, 'test price withdrawn') ->> 'active')::boolean is false);
select tt.chk('T2 retiring twice is harmless', (supplier_price_retire(:'pid'::bigint, 'again') ->> 'dup')::boolean);
select tt.chk('T2 the retired price leaves the active list but stays with p_all (nothing is deleted)', jsonb_array_length(supplier_price_list(:'rb'::uuid))=0 and jsonb_array_length(supplier_price_list(:'rb'::uuid, null, true))=1);
reset role;

\echo == T3 preferred and alternative suppliers
select tt.as(:'u'); set role authenticated;
select tt.chk('T3 A is the preferred supplier of item A; B an alternative', (item_supplier_set(:'ra'::uuid, :'sa'::uuid, 'preferred') ->> 'updated')::boolean is false and (item_supplier_set(:'ra'::uuid, :'sb'::uuid, 'alternative', 'test backup') ->> 'updated')::boolean is false);
select tt.chk('T3 setting again updates the same row (one row per item and supplier)', (item_supplier_set(:'ra'::uuid, :'sb'::uuid, 'alternative', 'test backup 2') ->> 'updated')::boolean and (select count(*) from jsonb_array_elements(item_supplier_list(:'ra'::uuid)))=2);
select tt.err('T3 bad rank refused', format($$select item_supplier_set('%s'::uuid, '%s'::uuid, 'best')$$, :'ra', :'sc'), 'bad_rank');
select (select (x->>'id')::bigint from jsonb_array_elements(item_supplier_list(:'ra'::uuid)) x where x->>'supplier'='test_supplier_b') as isb \gset
select tt.err('T3 retire needs a note', format($$select item_supplier_retire(%s, '')$$, :'isb'), 'note_required');
select (item_supplier_retire(:'isb'::bigint, 'test dropped') ->> 'active') as rt_active \gset
select tt.chk('T3 retire with a note: it leaves the active list, stays with p_all', :'rt_active'='false' and (select count(*) from jsonb_array_elements(item_supplier_list(:'ra'::uuid)))=1
  and (select count(*) from jsonb_array_elements(item_supplier_list(:'ra'::uuid, null, true)))=2);
select (item_supplier_set(:'ra'::uuid, :'sb'::uuid, 'alternative') ->> 'updated') as again \gset
select tt.chk('T3 a retired link can be set again (back to active)', :'again'='true' and (select count(*) from jsonb_array_elements(item_supplier_list(:'ra'::uuid)))=2);
reset role; select tt.as(:'s'); set role authenticated;
select tt.err('T3 a salesperson cannot set or read', format($$select item_supplier_set('%s'::uuid, '%s'::uuid, 'preferred')$$, :'ra', :'sc'), 'not allowed');
select tt.err('T3 nor list (no purchase / stock report right)', 'select item_supplier_list()', 'not allowed');
reset role;

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
