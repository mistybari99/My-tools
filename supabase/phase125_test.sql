-- FRESH DB ONLY (canonical order through phase125; phase126 may or may not be present). Phase 125 tests = variant item model, per-business items, price lists by channel.
--   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase125_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
--   Before/after proof on seeded A3/A5 data: tests/sql/var125_before_after.sh (needs a build WITHOUT phase125).
\i tests/sql/e2e/00_common.sql
\set hm '00000000-0000-0000-0000-000000000041'
\set hs '00000000-0000-0000-0000-000000000042'
\echo == T0 shape
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@v125.app','{"full_name":"Owner"}'),(:'sp','seller@v125.app','{"full_name":"Seller"}'),(:'hm','hwmgr@v125.app','{"full_name":"HwMgr"}'),(:'hs','hwstaff@v125.app','{"full_name":"HwStaff"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'sp','salesperson'),(:'hm','salesperson'),(:'hs','salesperson') on conflict do nothing;
insert into user_locations values (:'sp',1) on conflict do nothing;
select tt.as(:'o');
select tt.t('T0 the six new tables exist with RLS on', (select count(*) = 6 and bool_and(relrowsecurity) from pg_class where oid in ('public.option_sets'::regclass, 'public.option_values'::regclass, 'public.item_styles'::regclass,
  'public.style_axes'::regclass, 'public.price_lists'::regclass, 'public.price_list_items'::regclass)));
select tt.t('T0 anon / public have nothing, the browser role cannot write any of them', (select bool_and(not has_table_privilege('anon', t, 'select') and not has_table_privilege('authenticated', t, 'insert') and not has_table_privilege('authenticated', t, 'update')
  and not has_table_privilege('authenticated', t, 'delete')) from unnest(array['public.option_sets','public.option_values','public.item_styles','public.style_axes','public.price_lists','public.price_list_items']) t));
select tt.t('T0 audit + no-delete trigger on the five id tables', (select count(*) = 10 from pg_trigger where not tgisinternal and tgrelid in ('public.option_sets'::regclass, 'public.option_values'::regclass, 'public.item_styles'::regclass,
  'public.price_lists'::regclass, 'public.price_list_items'::regclass) and (tgname ~ '^audit_' or tgname ~ '_nodel125$')));
select tt.t('T0 helper functions are closed to anon; only the two policy helpers are open to signed-in users', not has_function_privilege('anon', 'public._my_biz125()', 'execute') and not has_function_privilege('authenticated', 'public._biz_mgr125(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public._var_gate125(bigint)', 'execute') and has_function_privilege('authenticated', 'public._biz_vis125(bigint)', 'execute') and not has_function_privilege('authenticated', 'public._items_org125()', 'execute'));
select tt.t('T0 browser functions: signed-in yes, anon no', has_function_privilege('authenticated', 'public.variants_generate(bigint,jsonb,boolean)', 'execute') and not has_function_privilege('anon', 'public.variants_generate(bigint,jsonb,boolean)', 'execute')
  and not has_function_privilege('anon', 'public.price_for125(uuid,text,date,numeric)', 'execute') and not has_function_privilege('anon', 'public.variants_overview(bigint)', 'execute'));
select tt.t('T0 rule variants_on is a switch and OFF; grant variants_manage exists', (select kind = 'switch' and default_value = 'false'::jsonb from rules where key = 'variants_on') and not rule_on('variants_on') and exists (select 1 from grant_defs where grant_code = 'variants_manage'));

\echo == T1 existing items belong to the sweets business; old unique constraint kept, new one added
select tt.eq('T1 no item without a business', 0, (select count(*) from items where org_unit_id is null));
select tt.eq('T1 every pre-existing item is in SWEETS', (select count(*) from items), (select count(*) from items i join org_units b on b.id = i.org_unit_id and b.code = 'SWEETS'));
select tt.t('T1 the old global unique constraint on items.code is still there', exists (select 1 from pg_constraint where conrelid = 'public.items'::regclass and contype = 'u' and conkey = (select array_agg(attnum) from pg_attribute where attrelid = 'public.items'::regclass and attname = 'code')));
select tt.t('T1 the new unique index (org_unit_id, code) exists', exists (select 1 from pg_indexes where indexname = 'items_org_code_uq125' and indexdef ~ 'UNIQUE.*\(org_unit_id, code\)'));
create temp table f0 as select (select count(*) from items) n_items, (select coalesce(sum(sell_price),0) from items) sum_price,
  (select md5(string_agg(to_jsonb(i)::text, '|' order by id)) from (select id, code, name_bn, name_en, category, unit, sell_price, wholesale_price, is_active, tracked, barcode from items) i) items_h,
  (select count(*) from stock_ledger) n_led, (select coalesce(sum(qty_delta),0) from stock_ledger) sum_led, (select count(*) from stock_balance) n_bal, (select coalesce(sum(qty),0) from stock_balance) sum_bal,
  (select md5(acct_trial_balance(null, null)::text)) tb_h, (select count(*) from rules) rules_n;
create temp table h0 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname !~ '^(_biz_|_my_biz125|_var_gate125|_items_org125|_ean13_125|option_set_save|option_values_save|style_save|variants_|variant_matrix|my_businesses125|price_list|price_for125|items_search)';
select n_items as n0, items_h as items_h0, n_led as nled0, tb_h as tb0 from f0 \gset
insert into items (code, name_bn, sell_price) values ('ZZ-OLD1', 'old way', 10);
select tt.is('T1 an item inserted the old way (no org) lands in SWEETS', 'SWEETS', (select b.code from items i join org_units b on b.id = i.org_unit_id where i.code = 'ZZ-OLD1'));
select tt.err('T1 the old global code uniqueness still refuses a duplicate code', $$insert into items (code, name_bn) values ('ZZ-OLD1', 'dup')$$, 'duplicate key');
select tt.err('T1 an item cannot be moved to another business later', $$update items set org_unit_id = (select id from org_units where kind='business' and code <> 'SWEETS' limit 1) where code = 'ZZ-OLD1'$$, 'item_org_fixed');

\echo == T2 switch OFF: refused, nothing else changes
select tt.err('T2 option_set_save refused while variants_on is off', $$select option_set_save((select id from org_units where code='SWEETS'), null, 'X', 'x', null, 'size', null, true, gen_random_uuid())$$, 'variants_off');
select tt.err('T2 price_list_save refused while off', $$select price_list_save((select id from org_units where code='SWEETS'), null, 'X', 'x', null, 'retail', null, null, true, gen_random_uuid())$$, 'variants_off');
select tt.as(:'sp'); set role authenticated;
select tt.t('T2 a salesperson sees every item exactly as before (policy not enforced while off)', (select count(*) from items) = :n0 + 1);
reset role;
select tt.as(:'o');
select tt.t('T2 the items_read policy only adds the switch test (still readable by any active user when off)', (select qual ~ 'variants_on' from pg_policies where tablename = 'items' and policyname = 'items_read'));

\echo == T3 switch ON, a second business (hardware) with a branch and a location
update rules set value = 'true'::jsonb where key = 'variants_on';
select tt.t('T3 variants_on is now on', rule_on('variants_on'));
select org_unit_save(null, (select id from org_units where kind = 'group'), 'legal_entity', 'le-hw', 'হার্ডওয়্যার কোম্পানি', 'Hardware Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a1') ->> 'id' as hle \gset
select org_unit_save(null, :'hle'::bigint, 'business', 'HARDWARE', 'কাপড় ও হার্ডওয়্যার', 'Cloth and hardware', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a2') ->> 'id' as hbz \gset
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B1', 'শাখা ১', 'Branch 1', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a3') ->> 'id' as hb1 \gset
insert into locations (code, name_bn, kind, org_unit_id) values ('hw_shop', 'হার্ডওয়্যার দোকান', 'showroom', :'hb1'::bigint) returning id as hwloc \gset
insert into user_locations values (:'hm', :'hwloc'), (:'hs', :'hwloc') on conflict do nothing;
insert into user_grants (user_id, grant_code, granted_by) values (:'hm', 'variants_manage', :'o');
select id as swz from org_units where code = 'SWEETS' \gset
select tt.eq('T3 caller hm sees exactly one business', 1, (select count(*) from my_businesses125()) ) where false;
select tt.as(:'hm');
select tt.eq('T3 the hardware manager sees exactly one business (HARDWARE)', 1, (select count(*) from my_businesses125() where code = 'HARDWARE'));
select tt.eq('T3 ... and not SWEETS', 0, (select count(*) from my_businesses125() where code = 'SWEETS'));
select tt.as(:'sp');
select tt.eq('T3 the sweets salesperson sees only SWEETS', 1, (select count(*) from my_businesses125()));
select tt.as(:'o');
select tt.eq('T3 the owner sees both', 2, (select count(*) from my_businesses125()));

\echo == T4 option sets and values (owner editable, nothing hardcoded)
select option_set_save(:'hbz'::bigint, null, 'size_alpha', 'সাইজ', 'Size (S M L)', 'size', 'Shirts', true, '00000000-0000-0000-0000-0000000002a1') ->> 'id' as s_size \gset
select option_set_save(:'hbz'::bigint, null, 'colour', 'রং', 'Colour', 'colour', null, true, '00000000-0000-0000-0000-0000000002a2') ->> 'id' as s_col \gset
select option_set_save(:'hbz'::bigint, null, 'size_num', 'সংখ্যা সাইজ', 'Numeric size', 'size', 'Trousers', true, '00000000-0000-0000-0000-0000000002a3') ->> 'id' as s_num \gset
select option_set_save(:'hbz'::bigint, null, 'age', 'বয়স', 'Kids age band', 'age', 'Kids', true, '00000000-0000-0000-0000-0000000002a4') ->> 'id' as s_age \gset
select option_set_save(:'hbz'::bigint, null, 'fabric', 'কাপড়', 'Fabric', 'fabric', null, true, '00000000-0000-0000-0000-0000000002a5') ->> 'id' as s_fab \gset
select option_set_save(:'hbz'::bigint, null, 'free', 'ফ্রি সাইজ', 'Free size', 'size', null, true, '00000000-0000-0000-0000-0000000002a6') ->> 'id' as s_free \gset
select tt.eq('T4 six option sets stored upper-cased', 6, (select count(*) from option_sets where org_unit_id = :'hbz'::bigint and code = upper(code)));
select tt.t('T4 same key again returns the same set (idempotent)', (option_set_save(:'hbz'::bigint, null, 'size_alpha', 'সাইজ', 'Size (S M L)', 'size', 'Shirts', true, '00000000-0000-0000-0000-0000000002a1') ->> 'dup')::boolean);
select tt.eq('T4 ... no second row', 6, (select count(*) from option_sets where org_unit_id = :'hbz'::bigint));
select tt.err('T4 a duplicate code in the same business is refused', $$select option_set_save((select id from org_units where code='HARDWARE'), null, 'COLOUR', 'x', null, 'colour', null, true, gen_random_uuid())$$, 'code_taken');
select tt.err('T4 a bad code is refused', $$select option_set_save((select id from org_units where code='HARDWARE'), null, 'a b', 'x', null, 'colour', null, true, gen_random_uuid())$$, 'bad_code');
select tt.err('T4 a create without an idempotency key is refused', $$select option_set_save((select id from org_units where code='HARDWARE'), null, 'ZZ', 'x', null, 'colour', null, true, null)$$, 'client_id_needed');
select tt.err('T4 a bad kind is refused', $$select option_set_save((select id from org_units where code='HARDWARE'), null, 'ZZ', 'x', null, 'weird', null, true, gen_random_uuid())$$, 'bad_kind');
select tt.err('T4 the code of a set cannot change', format($$select option_set_save(%s, %s, 'OTHER', 'x', null, 'size', null, true, null)$$, :'hbz', :'s_size'), 'code_fixed');
select option_values_save(:'s_size'::bigint, '[{"code":"s","label_bn":"S","label_en":"Small","sort":10},{"code":"M","label_bn":"M","label_en":"Medium","sort":20},{"code":"L","label_bn":"L","label_en":"Large","sort":30},{"code":"XL","label_bn":"XL","sort":40}]'::jsonb);
select option_values_save(:'s_col'::bigint, '[{"code":"RED","label_bn":"লাল","label_en":"Red","sort":10},{"code":"BLUE","label_bn":"নীল","label_en":"Blue","sort":20}]'::jsonb);
select option_values_save(:'s_num'::bigint, '[{"code":"28","label_bn":"28","sort":10},{"code":"30","label_bn":"30","sort":20},{"code":"32","label_bn":"32","sort":30}]'::jsonb);
select option_values_save(:'s_age'::bigint, '[{"code":"2.3Y","label_bn":"2-3 বছর","label_en":"2-3 yrs","sort":10},{"code":"4.5Y","label_bn":"4-5 বছর","label_en":"4-5 yrs","sort":20}]'::jsonb);
select option_values_save(:'s_free'::bigint, '[{"code":"FREE","label_bn":"ফ্রি","label_en":"Free","sort":10}]'::jsonb);
select option_values_save(:'s_fab'::bigint, '[{"code":"COTTON","label_bn":"সুতি","label_en":"Cotton","sort":10},{"code":"LINEN","label_bn":"লিনেন","label_en":"Linen","sort":20}]'::jsonb);
select tt.eq('T4 values stored (4 + 2 + 3 + 2 + 1 + 2)', 14, (select count(*) from option_values where org_unit_id = :'hbz'::bigint));
select tt.t('T4 a value code is upper-cased (s -> S)', exists (select 1 from option_values where set_id = :'s_size'::bigint and code = 'S'));
select option_values_save(:'s_size'::bigint, '[{"code":"S","label_bn":"ছোট","label_en":"Small","sort":10}]'::jsonb) ->> 'saved' as sv \gset
select tt.t('T4 saving a value again updates it, no duplicate', :'sv' = '1' and (select count(*) from option_values where set_id = :'s_size'::bigint) = 4
  and (select label_bn from option_values where set_id = :'s_size'::bigint and code = 'S') = 'ছোট');
select tt.err('T4 bad value code', format($$select option_values_save(%s, '[{"code":"a-b","label_bn":"x"}]'::jsonb)$$, :'s_size'), 'bad_code');
select tt.err('T4 empty list', format($$select option_values_save(%s, '[]'::jsonb)$$, :'s_size'), 'bad_values');
select tt.as(:'hs');
select tt.err('T4 a hardware staff member WITHOUT variants_manage is refused', format($$select option_values_save(%s, '[{"code":"Q","label_bn":"q"}]'::jsonb)$$, :'s_size'), 'not allowed');
select tt.as(:'sp');
select tt.err('T4 a sweets salesperson cannot edit the hardware lists', format($$select option_values_save(%s, '[{"code":"Q","label_bn":"q"}]'::jsonb)$$, :'s_size'), 'not allowed');
select tt.as(:'hm');
select tt.t('T4 the hardware manager (grant variants_manage) can', (option_values_save(:'s_size'::bigint, '[{"code":"XXL","label_bn":"XXL","sort":50}]'::jsonb) ->> 'saved') = '1');
select tt.err('T4 ... but not in the sweets business', format($$select option_set_save(%s, null, 'ZZ', 'x', null, 'colour', null, true, gen_random_uuid())$$, :'swz'), 'not allowed');
select tt.as(:'o');

\echo == T5 styles and the variant generator
select style_save(:'hbz'::bigint, null, 'sh01', 'পুরুষ শার্ট', 'Mens shirt', 'Shirts', null, 'pc', 'resale', 850, array[:'s_size'::bigint, :'s_col'::bigint], 'active', '00000000-0000-0000-0000-0000000003a1') ->> 'id' as sty \gset
select tt.t('T5 style saved with two ordered axes', (select count(*) = 2 and min(set_id) filter (where axis_no = 1) = :'s_size'::bigint from style_axes where style_id = :'sty'::bigint));
select tt.t('T5 same style key again: no duplicate', (style_save(:'hbz'::bigint, null, 'sh01', 'পুরুষ শার্ট', 'Mens shirt', 'Shirts', null, 'pc', 'resale', 850, array[:'s_size'::bigint, :'s_col'::bigint], 'active', '00000000-0000-0000-0000-0000000003a1') ->> 'dup')::boolean and (select count(*) from item_styles) = 1);
select tt.err('T5 an axis from another business / unknown set is refused', format($$select style_save(%s, null, 'SH09', 'x', null, null, null, 'pc', 'resale', 1, array[999999::bigint], 'active', gen_random_uuid())$$, :'hbz'), 'bad_axes');
select tt.err('T5 more than 4 axes refused', format($$select style_save(%s, null, 'SH09', 'x', null, null, null, 'pc', 'resale', 1, array[%s,%s,%s,%s,%s]::bigint[], 'active', gen_random_uuid())$$, :'hbz', :'s_size', :'s_col', :'s_num', :'s_age', :'s_fab'), 'bad_axes');
select tt.err('T5 a negative price is refused', format($$select style_save(%s, null, 'SH09', 'x', null, null, null, 'pc', 'resale', -1, array[%s]::bigint[], 'active', gen_random_uuid())$$, :'hbz', :'s_size'), 'bad_price');
select tt.err('T5 an unknown item type is refused', format($$select style_save(%s, null, 'SH09', 'x', null, null, null, 'pc', 'nonsense', 1, array[%s]::bigint[], 'active', gen_random_uuid())$$, :'hbz', :'s_size'), 'bad_item_type');
select variants_generate(:'sty'::bigint, null, true) as dry1 \gset
select tt.eq('T5 dry run: 5 sizes x 2 colours = 10 would be created', 10, (:'dry1'::jsonb ->> 'would_create')::int);
select tt.eq('T5 ... and it wrote nothing', 0, (select count(*) from items where style_id = :'sty'::bigint));
select variants_generate(:'sty'::bigint, null, false) as gen1 \gset
select tt.eq('T5 generate: 10 variant items created', 10, (:'gen1'::jsonb ->> 'created')::int);
select tt.eq('T5 ... all in the hardware business, linked to the style, tracked', 10, (select count(*) from items where style_id = :'sty'::bigint and org_unit_id = :'hbz'::bigint and tracked));
select tt.is('T5 variant code = style + option codes', 'SH01-S-RED', (select code from items where style_id = :'sty'::bigint and variant_key = 'S|RED'));
select tt.is('T5 variant name uses the option labels', 'Mens shirt Small Red', (select name_en from items where code = 'SH01-S-RED'));
select tt.is('T5 variant opts stored by option set code', '{"COLOUR": "RED", "SIZE_ALPHA": "S"}', (select variant_opts::text from items where code = 'SH01-S-RED'));
select tt.is('T5 category / price copied from the style', 'Shirts|850.00', (select category || '|' || sell_price::text from items where code = 'SH01-S-RED'));
select tt.eq('T5 every variant has its own 13-digit barcode with a valid EAN-13 check digit', 10, (select count(*) from items where style_id = :'sty'::bigint and barcode ~ '^[0-9]{13}$'
  and (10 - (select sum(substr(barcode, k, 1)::int * case when k % 2 = 0 then 3 else 1 end) from generate_series(1, 12) k) % 10) % 10 = substr(barcode, 13, 1)::int));
select tt.eq('T5 ... and all barcodes differ', 10, (select count(distinct barcode) from items where style_id = :'sty'::bigint));
select md5(string_agg(code || barcode || id::text, '|' order by code)) as snap1 from items where style_id = :'sty'::bigint \gset
select variants_generate(:'sty'::bigint, null, false) as gen2 \gset
select tt.eq('T5 IDEMPOTENT: generate again creates nothing', 0, (:'gen2'::jsonb ->> 'created')::int);
select tt.eq('T5 ... all 10 reported as existing', 10, (:'gen2'::jsonb ->> 'existing')::int);
select tt.is('T5 ... same ids, codes and barcodes as before', :'snap1', (select md5(string_agg(code || barcode || id::text, '|' order by code)) from items where style_id = :'sty'::bigint));
select tt.eq('T5 ... still 10 items', 10, (select count(*) from items where style_id = :'sty'::bigint));
select option_values_save(:'s_col'::bigint, '[{"code":"GREEN","label_bn":"সবুজ","label_en":"Green","sort":30}]'::jsonb);
select variants_generate(:'sty'::bigint, null, false) as gen3 \gset
select tt.eq('T5 a new colour later: only the 5 new combinations are created', 5, (:'gen3'::jsonb ->> 'created')::int);
select tt.eq('T5 ... 15 variants in all', 15, (select count(*) from items where style_id = :'sty'::bigint));
select variants_generate(:'sty'::bigint, '{"SIZE_ALPHA":["M"],"COLOUR":["RED","BLUE"]}'::jsonb, true) as dry4 \gset
select tt.eq('T5 pick subset: M x (red, blue) = 2 combinations, both exist already', 0, (:'dry4'::jsonb ->> 'would_create')::int);
select option_values_save(:'s_col'::bigint, '[{"code":"GREEN","label_bn":"সবুজ","active":false}]'::jsonb);
select variants_generate(:'sty'::bigint, null, false) as gen5 \gset
select tt.eq('T5 a retired option value creates nothing and removes nothing', 0, (:'gen5'::jsonb ->> 'created')::int);
select tt.eq('T5 ... the green variants stay', 5, (select count(*) from items where style_id = :'sty'::bigint and variant_key like '%|GREEN'));
select tt.err('T5 axes cannot change once variants exist', format($$select style_save(%s, %s, null, 'x', null, null, null, 'pc', 'resale', 1, array[%s]::bigint[], 'active', null)$$, :'hbz', :'sty', :'s_size'), 'axes_locked');
select tt.t('T5 ... but the name and price can', (style_save(:'hbz'::bigint, :'sty'::bigint, null, 'পুরুষ শার্ট', 'Mens shirt', 'Shirts', null, 'pc', 'resale', 900, null, 'active', null) ->> 'dup')::boolean = false);
select tt.eq('T5 a price change on the style does not rewrite variants already made', 850, (select sell_price from items where code = 'SH01-S-RED'));
-- three axes + a kids style + free size
select style_save(:'hbz'::bigint, null, 'TR01', 'ট্রাউজার', 'Trouser', 'Trousers', null, 'pc', 'resale', 1200, array[:'s_num'::bigint, :'s_col'::bigint, :'s_fab'::bigint], 'active', '00000000-0000-0000-0000-0000000003a2') ->> 'id' as sty2 \gset
select tt.eq('T5 three axes (numeric size x colour x fabric): 3 x 3 x 2 = 18 (green is retired: 2 colours) -> 12', 12, (variants_generate(:'sty2'::bigint, null, false) ->> 'created')::int);
select style_save(:'hbz'::bigint, null, 'KD01', 'বাচ্চার ড্রেস', 'Kids dress', 'Kids', null, 'pc', 'resale', 500, array[:'s_age'::bigint, :'s_free'::bigint], 'active', '00000000-0000-0000-0000-0000000003a3') ->> 'id' as sty3 \gset
select tt.eq('T5 kids age band x free size = 2', 2, (variants_generate(:'sty3'::bigint, null, false) ->> 'created')::int);
select tt.is('T5 age band code with a dot is kept', 'KD01-2.3Y-FREE', (select code from items where style_id = :'sty3'::bigint and variant_key = '2.3Y|FREE'));
-- too many
insert into option_sets (org_unit_id, code, name_bn, kind) values (:'hbz'::bigint, 'BIG1', 'b1', 'other'), (:'hbz'::bigint, 'BIG2', 'b2', 'other');
insert into option_values (set_id, org_unit_id, code, label_bn) select s.id, :'hbz'::bigint, 'V' || g, 'v' || g from option_sets s, generate_series(1, 25) g where s.code in ('BIG1', 'BIG2');
select style_save(:'hbz'::bigint, null, 'BIGS', 'Big', null, null, null, 'pc', 'resale', 1, (select array_agg(id order by code) from option_sets where code in ('BIG1', 'BIG2')), 'active', '00000000-0000-0000-0000-0000000003a4') ->> 'id' as sty4 \gset
select tt.err('T5 625 combinations in one call are refused (max 500)', format($$select variants_generate(%s, null, false)$$, :'sty4'), 'too_many');
select tt.eq('T5 ... nothing was written', 0, (select count(*) from items where style_id = :'sty4'::bigint));
-- a code taken by an unrelated item (global code uniqueness still applies)
insert into items (code, name_bn, org_unit_id) values ('SH02-S-RED', 'unrelated sweets-style code', :'swz'::bigint);
select style_save(:'hbz'::bigint, null, 'SH02', 'Other shirt', null, null, null, 'pc', 'resale', 1, array[:'s_size'::bigint, :'s_col'::bigint], 'active', '00000000-0000-0000-0000-0000000003a5') ->> 'id' as sty5 \gset
select tt.err('T5 a clash with an existing global item code is refused before anything is written', format($$select variants_generate(%s, null, false)$$, :'sty5'), 'code_taken');
select tt.eq('T5 ... nothing written', 0, (select count(*) from items where style_id = :'sty5'::bigint));
select tt.as(:'sp');
select tt.err('T5 a sweets user cannot generate hardware variants', format($$select variants_generate(%s, null, false)$$, :'sty'), 'not allowed');
select tt.as(:'hs');
select tt.err('T5 hardware staff without the grant cannot', format($$select variants_generate(%s, null, false)$$, :'sty'), 'not allowed');
select tt.as(:'o');

\echo == T6 stock per variant uses the existing stock_ledger
insert into stock_ledger (item_id, location_id, qty_delta, reason, ref_type, ref_id, note) select id, :'hwloc', 10, 'opening', 'v125', 'x', 'opening' from items where code in ('SH01-S-RED', 'SH01-M-RED');
insert into stock_ledger (item_id, location_id, qty_delta, reason, ref_type, ref_id, note) select id, 1, 3, 'opening', 'v125', 'x', 'opening' from items where code = 'SH01-S-RED';
select tt.eq('T6 stock_balance per variant per location (hardware shop: S red 10)', 10, (select qty from stock_balance b join items i on i.id = b.item_id where i.code = 'SH01-S-RED' and b.location_id = :'hwloc'));
select tt.as(:'hm');
select tt.eq('T6 the matrix shows the hardware manager 10 of S/RED (location 1 stock is out of their scope)', 10, (select (c->>'stock')::numeric from jsonb_array_elements(variant_matrix(:'sty'::bigint)->'cells') c where c->>'code' = 'SH01-S-RED'));
select tt.eq('T6 ... the matrix has 15 cells and 2 axes', 17, (select jsonb_array_length(variant_matrix(:'sty'::bigint)->'cells') + jsonb_array_length(variant_matrix(:'sty'::bigint)->'axes')));
select tt.as(:'o');
select tt.eq('T6 the owner sees the combined stock of S/RED (13)', 13, (select (c->>'stock')::numeric from jsonb_array_elements(variant_matrix(:'sty'::bigint)->'cells') c where c->>'code' = 'SH01-S-RED'));
select tt.eq('T6 ... or one location (location 1: 3)', 3, (select (c->>'stock')::numeric from jsonb_array_elements(variant_matrix(:'sty'::bigint, 1)->'cells') c where c->>'code' = 'SH01-S-RED'));

\echo == T7 two businesses are isolated (direct select, RPC parameter swap, id guess)
select id as hwitem from items where code = 'SH01-S-RED' \gset
select id as switem from items where code = 'ZZ-OLD1' \gset
select option_set_save(:'swz'::bigint, null, 'SW_BOX', 'বক্স', 'Box', 'other', null, true, '00000000-0000-0000-0000-0000000004a1') ->> 'id' as sw_set \gset
select price_list_save(:'hbz'::bigint, null, 'hw-ret', 'Retail', null, 'retail', null, null, true, '00000000-0000-0000-0000-0000000004a2') ->> 'id' as pl_hw \gset
select price_list_save(:'swz'::bigint, null, 'sw-ret', 'Sweets retail', null, 'retail', null, null, true, '00000000-0000-0000-0000-0000000004a3') ->> 'id' as pl_sw \gset
select tt.as(:'sp'); set role authenticated;
select tt.eq('T7 sweets user: no hardware item by direct select', 0, (select count(*) from items where org_unit_id = (select id from org_units where code = 'HARDWARE')));
select tt.eq('T7 ... nor by guessing the id', 0, (select count(*) from items where id = :'hwitem'));
select tt.t('T7 ... but all sweets items are still visible', (select count(*) from items) = (:n0 + 2));
select tt.eq('T7 ... no hardware option set', 0, (select count(*) from option_sets where org_unit_id = :'hbz'::bigint));
select tt.eq('T7 ... no hardware option value', 0, (select count(*) from option_values where org_unit_id = :'hbz'::bigint));
select tt.eq('T7 ... no hardware style', 0, (select count(*) from item_styles));
select tt.eq('T7 ... no style axes', 0, (select count(*) from style_axes));
select tt.eq('T7 ... no hardware price list', 0, (select count(*) from price_lists where id = :'pl_hw'::bigint));
select tt.eq('T7 ... but sees its own sweets option set', 1, (select count(*) from option_sets));
select tt.eq('T7 ... and its own sweets price list', 1, (select count(*) from price_lists));
select tt.err('T7 variants_overview of the hardware business is refused', format($$select variants_overview(%s)$$, :'hbz'), 'not allowed');
select tt.err('T7 variant_matrix of a hardware style is refused', format($$select variant_matrix(%s)$$, :'sty'), 'not allowed');
select tt.err('T7 price_for125 of a hardware item is refused', format($$select price_for125(%L)$$, :'hwitem'), 'not allowed');
reset role;
select tt.as(:'hm'); set role authenticated;
select tt.eq('T7 hardware user: no sweets item at all', 0, (select count(*) from items where org_unit_id = :'swz'::bigint));
select tt.eq('T7 ... sees all 15 + 12 + 2 hardware variants', 29, (select count(*) from items));
select tt.eq('T7 ... not the sweets price list nor option set', 0, (select count(*) from price_lists where id = :'pl_sw'::bigint) + (select count(*) from option_sets where id = :'sw_set'::bigint));
select tt.err('T7 variants_overview of SWEETS is refused', format($$select variants_overview(%s)$$, :'swz'), 'not allowed');
select tt.err('T7 price_for125 of a sweets item is refused', format($$select price_for125(%L)$$, :'switem'), 'not allowed');
select tt.err('T7 swapping the list id: put a hardware item into the SWEETS price list', format($$select price_list_items_set(%s, '[{"item_id":"%s","price":5}]'::jsonb)$$, :'pl_sw', :'hwitem'), 'not allowed');
select tt.err('T7 ... and a sweets item into the hardware list is refused', format($$select price_list_items_set(%s, '[{"item_id":"%s","price":5}]'::jsonb)$$, :'pl_hw', :'switem'), 'item_not_in_business');
select tt.err('T7 hardware user cannot write a table directly', $$update items set name_bn = 'x' where false returning 1; update option_sets set name_bn = 'x'$$, 'permission denied');
reset role;
select tt.as(:'o'); set role authenticated;
select tt.t('T7 the owner sees both businesses', (select count(distinct org_unit_id) from items) = 2);
reset role;
update rules set value = 'false'::jsonb where key = 'variants_on';
select tt.as(:'sp'); set role authenticated;
select tt.t('T7 switch OFF again: the policy is not enforced, everything visible as before (no change)', (select count(*) from items) = (select count(*) from items where true) and (select count(*) from items where org_unit_id = :'hbz'::bigint) = 29);
reset role;
select tt.as(:'o');
update rules set value = 'true'::jsonb where key = 'variants_on';

\echo == T8 price lists by channel
select price_list_save(:'hbz'::bigint, null, 'hw-ws', 'Wholesale', 'Wholesale', 'wholesale', null, null, true, '00000000-0000-0000-0000-0000000005a1') ->> 'id' as pl_ws \gset
select price_list_save(:'hbz'::bigint, null, 'hw-on', 'Online', 'Online', 'online', current_date + 30, current_date + 60, true, '00000000-0000-0000-0000-0000000005a2') ->> 'id' as pl_on \gset
select tt.t('T8 same price-list key again: same list', (price_list_save(:'hbz'::bigint, null, 'hw-ws', 'Wholesale', 'Wholesale', 'wholesale', null, null, true, '00000000-0000-0000-0000-0000000005a1') ->> 'dup')::boolean);
select tt.err('T8 bad channel', format($$select price_list_save(%s, null, 'ZZ', 'x', null, 'dropship', null, null, true, gen_random_uuid())$$, :'hbz'), 'bad_channel');
select tt.err('T8 valid_to before valid_from', format($$select price_list_save(%s, null, 'ZZ', 'x', null, 'retail', current_date, current_date - 1, true, gen_random_uuid())$$, :'hbz'), 'bad_date');
select tt.err('T8 the channel of a list cannot change', format($$select price_list_save(%s, %s, null, 'x', null, 'online', null, null, true, null)$$, :'hbz', :'pl_hw'), 'channel_fixed');
update items set wholesale_price = 700 where code = 'SH01-S-RED';
select price_list_items_set(:'pl_hw'::bigint, format('[{"item_id":"%s","price":799},{"item_id":"%s","price":749,"min_qty":5}]', :'hwitem', :'hwitem')::jsonb) as r1 \gset
select tt.eq('T8 two rows saved (price and a quantity tier)', 2, (:'r1'::jsonb ->> 'saved')::int);
select tt.eq('T8 retail price from the list, qty 1', 799, (price_for125(:'hwitem'::uuid, 'retail', null, 1) ->> 'price')::numeric);
select tt.eq('T8 qty 5 gets the tier price', 749, (price_for125(:'hwitem'::uuid, 'retail', null, 5) ->> 'price')::numeric);
select tt.is('T8 source = list', 'list', price_for125(:'hwitem'::uuid, 'retail', null, 1) ->> 'source');
select tt.eq('T8 the item''s own price is NOT overwritten (850)', 850, (select sell_price from items where id = :'hwitem'::uuid));
select tt.is('T8 wholesale channel with no wholesale list falls back to the item''s wholesale price', 'item', price_for125(:'hwitem'::uuid, 'wholesale') ->> 'source');
select tt.eq('T8 ... 700', 700, (price_for125(:'hwitem'::uuid, 'wholesale') ->> 'price')::numeric);
select price_list_items_set(:'pl_ws'::bigint, format('[{"item_id":"%s","price":640}]', :'hwitem')::jsonb);
select tt.eq('T8 wholesale list price wins over the item wholesale price', 640, (price_for125(:'hwitem'::uuid, 'wholesale') ->> 'price')::numeric);
select price_list_items_set(:'pl_on'::bigint, format('[{"item_id":"%s","price":600}]', :'hwitem')::jsonb);
select tt.is('T8 an online list that starts in 30 days does not apply today (item price)', 'item', price_for125(:'hwitem'::uuid, 'online') ->> 'source');
select tt.eq('T8 ... but applies on its start date', 600, (price_for125(:'hwitem'::uuid, 'online', current_date + 30) ->> 'price')::numeric);
select tt.is('T8 ... and not after it ends', 'item', price_for125(:'hwitem'::uuid, 'online', current_date + 61) ->> 'source');
select price_list_save(:'hbz'::bigint, :'pl_hw'::bigint, null, 'Retail', null, 'retail', null, null, false, null);
select tt.is('T8 an inactive list is ignored', 'item', price_for125(:'hwitem'::uuid, 'retail') ->> 'source');
select price_list_save(:'hbz'::bigint, :'pl_hw'::bigint, null, 'Retail', null, 'retail', null, null, true, null);
select price_list_items_set(:'pl_hw'::bigint, format('[{"item_id":"%s","price":810}]', :'hwitem')::jsonb);
select tt.eq('T8 upsert: same item/qty/from updates the row (810), still 2 rows', 2 + 810, (select count(*) from price_list_items where price_list_id = :'pl_hw'::bigint) + (price_for125(:'hwitem'::uuid, 'retail', null, 1) ->> 'price')::numeric);
select tt.err('T8 negative price', format($$select price_list_items_set(%s, '[{"item_id":"%s","price":-1}]'::jsonb)$$, :'pl_hw', :'hwitem'), 'bad_price');
select tt.err('T8 zero quantity', format($$select price_list_items_set(%s, '[{"item_id":"%s","price":1,"min_qty":0}]'::jsonb)$$, :'pl_hw', :'hwitem'), 'bad_qty');
select tt.err('T8 an item that is not in the list''s business', format($$select price_list_items_set(%s, '[{"item_id":"%s","price":1}]'::jsonb)$$, :'pl_hw', :'switem'), 'item_not_in_business');
select tt.is('T8 a SWEETS item with no list: its own price, source item (sweets flow unchanged)', 'item', price_for125(:'switem'::uuid, 'retail') ->> 'source');
select tt.eq('T8 ... 10', 10, (price_for125(:'switem'::uuid, 'retail') ->> 'price')::numeric);
select tt.t('T8 the overview lists sets, styles (with variant counts) and price lists', (select jsonb_array_length(o->'option_sets') = 8 and jsonb_array_length(o->'styles') = 5 and jsonb_array_length(o->'price_lists') = 3
  and (o->'styles'->0->>'variant_count') is not null and (o->>'can_manage')::boolean from (select variants_overview(:'hbz'::bigint) o) x));

\echo == T9 audit, no hard delete, no secrets
select tt.err('T9 option sets cannot be hard-deleted', $$delete from option_sets$$, 'delete');
select tt.err('T9 price list rows cannot be hard-deleted', $$delete from price_list_items$$, 'delete');
select tt.t('T9 changes are audited', exists (select 1 from audit_log where table_name = 'price_lists') and exists (select 1 from audit_log where table_name = 'option_sets'));
select tt.t('T9 the matrix / search JSON never carries a cost field', variant_matrix(:'sty'::bigint)::text !~* 'cost');

\echo == T10 second paste = no change
create temp table k1 as select (select count(*) from option_sets) a, (select count(*) from option_values) b, (select count(*) from item_styles) c, (select count(*) from items) d, (select count(*) from price_list_items) e,
  (select md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r) rules_h, (select count(*) from grant_defs) gd, (select md5(string_agg(code || coalesce(barcode,''), '|' order by code)) from items where style_id is not null) var_h,
  (select count(*) from pg_policies where tablename = 'items') pol_n;
\i supabase/phase125.sql
select tt.t('T10 no row added or changed anywhere', (select a = (select count(*) from option_sets) and b = (select count(*) from option_values) and c = (select count(*) from item_styles) and d = (select count(*) from items) and e = (select count(*) from price_list_items)
  and rules_h = (select md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r) and gd = (select count(*) from grant_defs)
  and var_h = (select md5(string_agg(code || coalesce(barcode,''), '|' order by code)) from items where style_id is not null) and pol_n = (select count(*) from pg_policies where tablename = 'items') from k1));
select tt.t('T10 the owner-typed switch value survives the second paste (on)', rule_on('variants_on'));
select tt.eq('T10 the generator after the second paste still creates nothing', 0, (variants_generate(:'sty'::bigint, null, false) ->> 'created')::int);
select tt.t('T10 no older function body changed', not exists (select 1 from pg_proc p join h0 on h0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> h0.h));
select tt.t('T10 ... and no older function was dropped', not exists (select 1 from h0 where not exists (select 1 from pg_proc p where p.oid::regprocedure::text = h0.fn)));

\echo == T11 sweets numbers unchanged (flag on, hardware data present)
select tt.is('T11 sweets items: same list, prices, units, barcodes as at the start (excluding the 2 test items)', :'items_h0', (select md5(string_agg(to_jsonb(i)::text, '|' order by id)) from (select id, code, name_bn, name_en, category, unit, sell_price, wholesale_price, is_active, tracked, barcode from items
  where org_unit_id = :'swz'::bigint and code not in ('ZZ-OLD1', 'SH02-S-RED')) i));
select tt.eq('T11 sweets stock ledger rows at sweets locations unchanged except the one test opening at location 1', (:nled0 + 1)::numeric, (select count(*) from stock_ledger l join locations x on x.id = l.location_id join org_units b on b.id = x.org_unit_id and b.code = 'SWEETS'));
select tt.t('T11 trial balance unchanged', :'tb0' = md5(acct_trial_balance(null, null)::text));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
