-- FRESH DB ONLY (canonical order through phase126). Phase 126 tests = items_search (server-side search / paging / counts) scoped by business, brand column, indexes, no change to existing listings.
--   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase126_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
--   The 20,000-item timing run is tests/sql/var126_perf.sh (scratch db, results in docs/regs/variants125.md).
\i tests/sql/e2e/00_common.sql
\set hm '00000000-0000-0000-0000-000000000041'
\echo == T0 shape
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@v126.app','{"full_name":"Owner"}'),(:'sp','seller@v126.app','{"full_name":"Seller"}'),(:'hm','hwstaff@v126.app','{"full_name":"HwStaff"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'sp','salesperson'),(:'hm','salesperson') on conflict do nothing;
insert into user_locations values (:'sp',1) on conflict do nothing;
select tt.as(:'o');
select tt.t('T0 items.brand exists and is nullable; sweets items have no brand', (select is_nullable = 'YES' from information_schema.columns where table_name = 'items' and column_name = 'brand') and not exists (select 1 from items where brand is not null));
select tt.t('T0 search functions: signed-in yes, anon no', has_function_privilege('authenticated', 'public.items_search(bigint,text,jsonb,integer,integer)', 'execute') and not has_function_privilege('anon', 'public.items_search(bigint,text,jsonb,integer,integer)', 'execute')
  and not has_function_privilege('anon', 'public.items_search_info126()', 'execute') and not has_function_privilege('public', 'public.items_search(bigint,text,jsonb,integer,integer)', 'execute'));
select tt.t('T0 the btree indexes exist', (select count(*) = 4 from pg_indexes where schemaname = 'public' and tablename = 'items' and indexname in ('items_org_cat126', 'items_code_lpfx126', 'items_barcode_pfx126', 'items_org_brand126')));
select tt.t('T0 name search index mode is known: trigram GIN (pg_trgm) or btree prefix fallback', case when (items_search_info126()->>'trigram')::boolean
  then (select count(*) = 3 from pg_indexes where indexname ~ '^items_name_(bn|en|mix)_trgm126$') else (select count(*) = 3 from pg_indexes where indexname ~ '^items_name_(bn|en|mix)_pfx126$') end,
  'true', (items_search_info126()->>'trigram'));
create temp table f0 as select (select count(*) from items) n_items, (select md5(string_agg(to_jsonb(i)::text, '|' order by id)) from (select id, code, name_bn, name_en, name_mix, category, unit, sell_price, wholesale_price, is_active, tracked, barcode from items) i) items_h;
create temp table h0 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname !~ '^(_biz_|_my_biz125|_var_gate125|_items_org125|_ean13_125|option_set_save|option_values_save|style_save|variants_|variant_matrix|my_businesses125|price_list|price_for125|items_search)';
select n_items as n0, items_h as items_h0 from f0 \gset
select count(*) as nsweets from items \gset

\echo == T1 two businesses, a 300-item hardware catalogue
update rules set value = 'true'::jsonb where key = 'variants_on';
select org_unit_save(null, (select id from org_units where kind = 'group'), 'legal_entity', 'le-hw', 'x', 'x', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a1') ->> 'id' as hle \gset
select org_unit_save(null, :'hle'::bigint, 'business', 'HARDWARE', 'x', 'x', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a2') ->> 'id' as hbz \gset
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B1', 'x', 'x', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a3') ->> 'id' as hb1 \gset
insert into locations (code, name_bn, kind, org_unit_id) values ('hw_shop', 'x', 'showroom', :'hb1'::bigint);
insert into user_locations select :'hm', id from locations where code = 'hw_shop';
select id as swz from org_units where code = 'SWEETS' \gset
insert into items (code, name_bn, name_en, name_mix, category, unit, sell_price, barcode, brand, org_unit_id, tracked, is_active)
select 'P' || lpad(g::text, 4, '0'), 'পণ্য ' || g || ' ' || (array['রং', 'পেইন্ট', 'পাইপ'])[1 + g % 3],
  (array['Emulsion', 'Enamel', 'Primer', 'Putty', 'Brush'])[1 + g % 5] || ' ' || (array['white', 'red', '1L', '4L'])[1 + g % 4] || ' ' || g, 'item ' || g,
  (array['Paint', 'Hardware', 'Tools'])[1 + g % 3], 'pc', 100 + g, '29' || lpad(g::text, 11, '0'), (array['Asian', 'Berger', 'Classic'])[1 + g % 3], :'hbz'::bigint, true, g % 10 <> 0
from generate_series(1, 300) g;
insert into items (code, name_bn, name_en, category, org_unit_id) values ('P-100%', 'percent item', 'Special 100% cotton', 'Paint', :'hbz'::bigint), ('P_UNDER', 'underscore item', 'Under_score tool', 'Tools', :'hbz'::bigint);
select tt.eq('T1 302 hardware items, none inactive by default except every 10th (30)', 30, (select count(*) from items where org_unit_id = :'hbz'::bigint and not is_active));
select tt.eq('T1 sweets item count unchanged by all this', :n0, (select count(*) from items where org_unit_id = :'swz'::bigint));

\echo == T2 scope: a user only searches the businesses they work in
select tt.as(:'sp'); set role authenticated;
select tt.eq('T2 sweets user, own business: all active sweets items', (select count(*) from items where is_active), (items_search(:'swz'::bigint, null, '{}', 50, 0) ->> 'total')::int);
select tt.err('T2 sweets user asking for the hardware business is refused', format($$select items_search(%s, null, '{}', 50, 0)$$, :'hbz'), 'not allowed');
select tt.eq('T2 sweets user, org null: still only sweets rows', 0, (select count(*) from jsonb_array_elements(items_search(null, 'emulsion', '{}', 200, 0)->'rows') r where (r->>'org_unit_id')::bigint <> :'swz'::bigint));
select tt.eq('T2 ... a hardware code finds nothing for a sweets user', 0, (items_search(null, 'P0001', '{}', 50, 0) ->> 'total')::int);
reset role;
select tt.as(:'hm'); set role authenticated;
select tt.eq('T2 hardware user, org null: only hardware rows (271 active + 2)', 272, (items_search(null, null, '{}', 200, 0) ->> 'total')::int);
select tt.err('T2 hardware user asking for SWEETS is refused', format($$select items_search(%s, null, '{}', 50, 0)$$, :'swz'), 'not allowed');
reset role;
select tt.as(:'o'); set role authenticated;
select tt.eq('T2 owner, org null: both businesses (active only)', (select count(*) from items where is_active), (items_search(null, null, '{}', 200, 0) ->> 'total')::int);
reset role;
select tt.as(:'o');

\echo == T3 search behaviour (hardware user)
select tt.as(:'hm'); set role authenticated;
select :'hbz' as org \gset
select tt.eq('T3 exact code', 1, (items_search(:'org'::bigint, 'P0007', '{}', 50, 0) ->> 'total')::int);
select tt.is('T3 ... and it is that item', 'P0007', items_search(:'org'::bigint, 'p0007', '{}', 50, 0) -> 'rows' -> 0 ->> 'code');
select tt.eq('T3 code prefix P001 -> P0010..P0019 active (10 minus the inactive P0010)', 9, (items_search(:'org'::bigint, 'P001', '{}', 50, 0) ->> 'total')::int);
select tt.is('T3 barcode exact', 'P0042', items_search(:'org'::bigint, '2900000000042', '{}', 50, 0) -> 'rows' -> 0 ->> 'code');
select tt.eq('T3 barcode prefix', 9, (items_search(:'org'::bigint, '290000000001', '{}', 50, 0) ->> 'total')::int);
select tt.t('T3 English name substring (case-insensitive)', (items_search(:'org'::bigint, 'EMULSION', '{}', 50, 0) ->> 'total')::int > 0 and not exists
  (select 1 from jsonb_array_elements(items_search(:'org'::bigint, 'EMULSION', '{}', 200, 0)->'rows') r where r->>'name_en' !~* 'emulsion'));
select tt.t('T3 two-word substring ''putty 4L''', (items_search(:'org'::bigint, 'putty 4L', '{}', 200, 0) ->> 'total')::int > 0 and not exists
  (select 1 from jsonb_array_elements(items_search(:'org'::bigint, 'putty 4L', '{}', 200, 0)->'rows') r where r->>'name_en' !~* 'putty 4L'));
select tt.t('T3 Bangla substring', (items_search(:'org'::bigint, 'পেইন্ট', '{}', 200, 0) ->> 'total')::int > 0 and not exists
  (select 1 from jsonb_array_elements(items_search(:'org'::bigint, 'পেইন্ট', '{}', 200, 0)->'rows') r where r->>'name_bn' !~ 'পেইন্ট'));
select tt.t('T3 short query (2 chars) = prefix only: ''em'' finds Emulsion, not ''Primer''', (items_search(:'org'::bigint, 'em', '{}', 200, 0) ->> 'total')::int > 0 and not exists
  (select 1 from jsonb_array_elements(items_search(:'org'::bigint, 'em', '{}', 200, 0)->'rows') r where r->>'name_en' !~* '^em'));
select tt.eq('T3 a literal % in the query is not a wildcard (only the 100% item)', 1, (items_search(:'org'::bigint, '100%', '{}', 50, 0) ->> 'total')::int);
select tt.eq('T3 a literal _ in the query is not a wildcard', 1, (items_search(:'org'::bigint, 'under_s', '{}', 50, 0) ->> 'total')::int);
select tt.eq('T3 a query that matches nothing', 0, (items_search(:'org'::bigint, 'zzzzqqq', '{}', 50, 0) ->> 'total')::int);
select tt.is('T3 exact code ranks before name matches', 'P0007', items_search(:'org'::bigint, 'P0007', '{}', 5, 0) -> 'rows' -> 0 ->> 'code');
select tt.eq('T3 category Hardware (every 3rd of 300 = 100, minus inactive every 10th)', (select count(*) from items where category = 'Hardware' and is_active and org_unit_id = :'org'::bigint), (items_search(:'org'::bigint, null, '{"category":"Hardware"}', 5, 0) ->> 'total')::int);
select tt.eq('T3 brand filter', (select count(*) from items where brand = 'Berger' and is_active and org_unit_id = :'org'::bigint), (items_search(:'org'::bigint, null, '{"brand":"Berger"}', 5, 0) ->> 'total')::int);
select tt.eq('T3 category + brand + query together', (select count(*) from items where brand = 'Asian' and category = 'Paint' and is_active and name_en ilike '%brush%' and org_unit_id = :'org'::bigint),
  (items_search(:'org'::bigint, 'brush', '{"brand":"Asian","category":"Paint"}', 5, 0) ->> 'total')::int);
select tt.eq('T3 active=false lists the 30 inactive', 30, (items_search(:'org'::bigint, null, '{"active":"false"}', 5, 0) ->> 'total')::int);
select tt.eq('T3 active=all lists 302', 302, (items_search(:'org'::bigint, null, '{"active":"all"}', 5, 0) ->> 'total')::int);

\echo == T4 paging and summary counts
select tt.eq('T4 first page has 50 rows', 50, jsonb_array_length(items_search(:'org'::bigint, null, '{}', 50, 0) -> 'rows'));
select tt.eq('T4 the total does not depend on the page', (items_search(:'org'::bigint, null, '{}', 50, 0) ->> 'total')::int, (items_search(:'org'::bigint, null, '{}', 50, 100) ->> 'total')::int);
select tt.eq('T4 pages do not overlap (page 1 + page 2 = 100 distinct ids)', 100, (select count(distinct r->>'id') from (select jsonb_array_elements(items_search(:'org'::bigint, null, '{}', 50, 0)->'rows') r
  union all select jsonb_array_elements(items_search(:'org'::bigint, null, '{}', 50, 50)->'rows')) z));
select tt.eq('T4 the last page is short (272 active+2: offset 250 -> 22)', 22, jsonb_array_length(items_search(:'org'::bigint, null, '{}', 50, 250) -> 'rows'));
select tt.eq('T4 beyond the end: no rows, same total', 0, jsonb_array_length(items_search(:'org'::bigint, null, '{}', 50, 5000) -> 'rows'));
select tt.is('T4 ordering is by code within the same rank', (select string_agg(code, ',' order by code) from (select code from items where org_unit_id = :'org'::bigint and is_active order by code limit 3) z),
  (select string_agg(r->>'code', ',') from (select jsonb_array_elements(items_search(:'org'::bigint, null, '{}', 3, 0)->'rows') r) z));
select tt.eq('T4 counts: active + inactive = total (active filter all)', 302, (items_search(:'org'::bigint, null, '{"active":"all"}', 5, 0)->'counts'->>'active')::int + (items_search(:'org'::bigint, null, '{"active":"all"}', 5, 0)->'counts'->>'inactive')::int);
select tt.eq('T4 counts by category add up to the total', (items_search(:'org'::bigint, null, '{}', 5, 0) ->> 'total')::int, (select sum((c->>'n')::int) from jsonb_array_elements(items_search(:'org'::bigint, null, '{}', 5, 0)->'counts'->'by_category') c));
select tt.eq('T4 counts by brand (3 brands)', 3, jsonb_array_length(items_search(:'org'::bigint, null, '{}', 5, 0)->'counts'->'by_brand'));
select tt.t('T4 counts off -> no summary', items_search(:'org'::bigint, null, '{"counts":false}', 5, 0)->'counts' = 'null'::jsonb);
select tt.err('T4 limit 0 refused', format($$select items_search(%s, null, '{}', 0, 0)$$, :'org'), 'bad_limit');
select tt.err('T4 limit 201 refused', format($$select items_search(%s, null, '{}', 201, 0)$$, :'org'), 'bad_limit');
select tt.err('T4 negative offset refused', format($$select items_search(%s, null, '{}', 10, -1)$$, :'org'), 'bad_offset');
select tt.err('T4 a very long query refused', format($$select items_search(%s, repeat('a', 81), '{}', 10, 0)$$, :'org'), 'bad_query');
select tt.err('T4 bad filters refused', format($$select items_search(%s, null, '{"active":"maybe"}', 10, 0)$$, :'org'), 'bad_filters');
select tt.t('T4 the result never carries a cost field', items_search(:'org'::bigint, 'brush', '{}', 50, 0)::text !~* 'cost');
select tt.t('T4 variant fields are returned (style_id, variant_opts keys exist)', (items_search(:'org'::bigint, 'P0001', '{}', 5, 0) -> 'rows' -> 0) ? 'style_id');
reset role;
select tt.as(:'o');
select tt.err('T4 anon cannot call it', $$set role anon; select items_search(null, null, '{}', 5, 0)$$, 'permission denied');
reset role;

\echo == T5 existing listings unchanged, second paste
select tt.t('T5 sweets items are exactly as before (list, prices, units, barcodes)', :'items_h0' = (select md5(string_agg(to_jsonb(i)::text, '|' order by id)) from (select id, code, name_bn, name_en, name_mix, category, unit, sell_price, wholesale_price, is_active, tracked, barcode from items where org_unit_id = :'swz'::bigint) i));
select tt.t('T5 no older function body changed or dropped', not exists (select 1 from pg_proc p join h0 on h0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> h0.h)
  and not exists (select 1 from h0 where not exists (select 1 from pg_proc p where p.oid::regprocedure::text = h0.fn)));
create temp table k1 as select (select count(*) from items) n, (select count(*) from pg_indexes where tablename = 'items') idx_n, (select md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r) rules_h;
\i supabase/phase126.sql
select tt.t('T5 second paste: nothing added or changed', (select n = (select count(*) from items) and idx_n = (select count(*) from pg_indexes where tablename = 'items') and rules_h = (select md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r) from k1));
select tt.t('T5 the policy on items is still the one from phase125 (switch-aware)', (select qual ~ 'variants_on' from pg_policies where tablename = 'items' and policyname = 'items_read'));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
