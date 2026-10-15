-- FRESH DB ONLY (built through phase131, then phase132). Phase 132 tests = Group ERP Stage C2: master data separated between businesses behind org_scope_on.
--   bash tests/sql/final_build.sh <db>   (the canonical order ends with phase132);  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase132_test.sql | grep -E 'FAIL|RESULT'   (from the repository root)
--   The "switch OFF = identical behaviour" proof on seeded data is tests/sql/c2_before_after.sh (needs a build WITHOUT phase132); here OFF is checked with hand numbers.
--   Two businesses: A = SWEETS (locations 1..7), B = HARDWARE (location hw1 under a branch, hw2 under the business). Users: o owner, ao A salesperson, am A manager, bs B salesperson, bm B manager, xn nobody.
\i tests/sql/e2e/00_common.sql
\set ao '00000000-0000-0000-0000-0000000000a1'
\set am '00000000-0000-0000-0000-0000000000a2'
\set bs '00000000-0000-0000-0000-0000000000b1'
\set bm '00000000-0000-0000-0000-0000000000b2'
\set xn '00000000-0000-0000-0000-0000000000c2'
\echo == T0 setup: two businesses, users scoped to each, masters in both
insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner@c2.app','{"full_name":"Owner"}'),(:'ao','a_staff@c2.app','{"full_name":"A Staff"}'),(:'am','a_mgr@c2.app','{"full_name":"A Manager"}'),
 (:'bs','b_staff@c2.app','{"full_name":"B Staff"}'),(:'bm','b_mgr@c2.app','{"full_name":"B Manager"}'),(:'xn','x_none@c2.app','{"full_name":"Nowhere"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ao','salesperson'),(:'am','management'),(:'bs','salesperson'),(:'bm','management'),(:'xn','salesperson') on conflict do nothing;
select tt.as(:'o');
select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'le-hw', 'হার্ডওয়্যার কোম্পানি', 'Hardware Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":100}'::jsonb, '00000000-0000-0000-0000-0000000000f1') ->> 'id' as hle \gset
select org_unit_save(null, :'hle'::bigint, 'business', 'HARDWARE', 'হার্ডওয়্যার ও রং', 'Hardware and paint', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000f2') ->> 'id' as hbz \gset
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B1', 'শাখা ১', 'Branch 1', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000f3') ->> 'id' as hb1 \gset
select id as sbz from org_units where code = 'SWEETS' \gset
insert into locations (code, name_bn, name_en, kind, status, org_unit_id) values ('hw1','হার্ডওয়্যার ১','Hardware 1','showroom','live', :'hb1'::bigint),('hw2','হার্ডওয়্যার ২','Hardware 2','showroom','live', :'hbz'::bigint);
select id as hw1 from locations where code = 'hw1' \gset
select id as hw2 from locations where code = 'hw2' \gset
insert into user_locations values (:'ao',1),(:'bs',:'hw1') on conflict do nothing;
select set_user_grant(:'am'::uuid, 'supplier_manage') is null as g1 \gset
select set_user_grant(:'bm'::uuid, 'supplier_manage') is null as g2 \gset
select set_user_grant(:'am'::uuid, 'item_create') is null as g3 \gset
select set_user_grant(:'bm'::uuid, 'item_create') is null as g4 \gset
select set_user_grant(:'am'::uuid, 'recipe_view') is null as g5 \gset
select set_user_grant(:'bm'::uuid, 'recipe_view') is null as g6 \gset
select set_user_grant(:'am'::uuid, 'customer_manage') is null as g7 \gset
select set_user_grant(:'bm'::uuid, 'customer_manage') is null as g8 \gset
select org_scope_grant(:'am'::uuid, :'sbz'::bigint, 'management', 'a mgr', gen_random_uuid()) ->> 'id' as sc_am \gset
select org_scope_grant(:'bm'::uuid, :'hbz'::bigint, 'management', 'b mgr', gen_random_uuid()) ->> 'id' as sc_bm \gset
select tt.t('T0 businesses, places, users and scopes are in place', :'hw1'::int > 7 and (select count(*) from org_units where kind = 'business') = 2 and :'sc_am' is not null and :'sc_bm' is not null);
-- masters of A and B (all made OFF, as the existing sweets data is): items, stock, customers (through sales), suppliers, a category, a vocabulary value, an artisan, an employee, a recipe
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('C2-A1','a','A item','pc','pc','finished_good',true,100,true),('C2-A2','a2','A item 2','pc','pc','finished_good',true,50,true);
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable,org_unit_id) values ('C2-B1','b','B item','pc','pc','finished_good',true,500,true,:'hbz'::bigint),('C2-B2','b2','B item 2','pc','pc','finished_good',true,70,true,:'hbz'::bigint);
select tt.t('T0 A items got the sweets business (default), B items the hardware business', (select org_unit_id from items where code = 'C2-A1') = :'sbz'::bigint and (select org_unit_id from items where code = 'C2-B1') = :'hbz'::bigint);
select acct_set_start(tt.today()-5)->>'start' as sd \gset
select stock_opening(tt.iid('C2-A1'), 1, 100, 40) is not null as s1 \gset
select stock_opening(tt.iid('C2-B1'), :'hw1'::int, 50, 300) is not null as s2 \gset
select record_sale2(gen_random_uuid(), 1, format('[{"item_id":"%s","qty":2,"price":100}]', tt.iid('C2-A1'))::jsonb, 0, '[{"mode":"cash","amount":200}]', '01711000001', 'A Customer', 'retail', null, false) ->> 'id' as sale_a \gset
select record_sale2(gen_random_uuid(), :'hw1'::int, format('[{"item_id":"%s","qty":1,"price":500}]', tt.iid('C2-B1'))::jsonb, 0, '[{"mode":"cash","amount":500}]', '01722000002', 'B Customer', 'retail', null, false) ->> 'id' as sale_b \gset
select tt.t('T0 two sales exist (A at place 1, B at hw1)', :'sale_a' is not null and :'sale_b' is not null and :'s1'::boolean and :'s2'::boolean);
select id as cust_a from customers where mobile like '%1711000001' \gset
select id as cust_b from customers where mobile like '%1722000002' \gset
select tt.t('T0 customers: the sale at a sweets place created an A customer, the sale at the hardware place a B customer (business of the place, not the caller)',
  (select org_unit_id from customers where id = :'cust_a') = :'sbz'::bigint and (select org_unit_id from customers where id = :'cust_b') = :'hbz'::bigint);
select tt.as(:'am');
select save_supplier(null, '{"name":"A Supplier"}') as sup_a \gset
select tt.as(:'bm');
select save_supplier(null, '{"name":"B Supplier"}') as sup_b \gset
select tt.t('T0 suppliers made by the manager of each business carry that business', (select org_unit_id from suppliers where id = :'sup_a') = :'sbz'::bigint and (select org_unit_id from suppliers where id = :'sup_b') = :'hbz'::bigint);
select tt.as(:'o');
insert into option_lists (list_code, value_code, label_bn, label_en, label_mix, sort) values ('expense_heads', 'c2_a_only', 'এ', 'A only head', 'A only head', 99);
insert into artisans (post, name, work_type, location_id) values ('karigor', 'A Artisan', 'mishti', 1), ('karigor', 'B Artisan', 'mishti', :'hw1'::int);
insert into employees (full_name_bn, primary_location_id) values ('A Employee', 1), ('B Employee', :'hw1'::int);
insert into item_categories (code, name_bn, name_en, name_mix, sort) values ('C2CAT', 'ক', 'C2 category', 'C2 category', 99);
select id as cat_a from item_categories where code = 'C2CAT' \gset
select tt.t('T0 vocabulary / category / artisan / employee rows are tagged: expense head and category = sweets, artisans and employees by place, units list = NULL (shared)',
  (select org_unit_id from option_lists where value_code = 'c2_a_only') = :'sbz'::bigint and (select org_unit_id from item_categories where id = :'cat_a'::bigint) = :'sbz'::bigint
  and (select org_unit_id from artisans where name = 'A Artisan') = :'sbz'::bigint and (select org_unit_id from artisans where name = 'B Artisan') = :'hbz'::bigint
  and (select org_unit_id from employees where full_name_bn = 'B Employee') = :'hbz'::bigint and not exists (select 1 from option_lists where list_code = 'units' and org_unit_id is not null));
-- recipes + children, made by SQL for both businesses (the children take the business of the parent)
insert into recipes (item_id, version, yield_qty, yield_unit) values (tt.iid('C2-A1'), 1, 10, 'pc'), (tt.iid('C2-B1'), 1, 5, 'pc');
select id as rec_a from recipes where item_id = tt.iid('C2-A1') \gset
select id as rec_b from recipes where item_id = tt.iid('C2-B1') \gset
insert into recipe_lines (recipe_id, ingredient_item_id, qty, unit) values (:'rec_a', tt.iid('C2-A2'), 1, 'pc'), (:'rec_b', tt.iid('C2-B2'), 2, 'pc');
select tt.t('T0 recipe and recipe line follow the finished item (A / B)', (select org_unit_id from recipes where id = :'rec_a') = :'sbz'::bigint and (select org_unit_id from recipes where id = :'rec_b') = :'hbz'::bigint
  and (select org_unit_id from recipe_lines where recipe_id = :'rec_b') = :'hbz'::bigint and (select org_unit_id from recipe_lines where recipe_id = :'rec_a') = :'sbz'::bigint);
-- more children for both businesses (a row per business in as many scoped tables as possible; the generic leak tests below walk the registry)
insert into item_cost_flags (item_id, cost_free, reason) values (tt.iid('C2-A2'), true, 'a'), (tt.iid('C2-B2'), true, 'b');
insert into item_logistics (item_id, unit_weight_kg) values (tt.iid('C2-A2'), 1.5), (tt.iid('C2-B2'), 2.5);
insert into unit_conversions (item_id, from_unit, to_unit, factor) values (tt.iid('C2-A2'), 'box', 'pc', 12), (tt.iid('C2-B2'), 'box', 'pc', 6);
insert into shelf_life_rules (item_id, value, unit) values (tt.iid('C2-A2'), 3, 'days'), (tt.iid('C2-B2'), 9, 'days');
insert into product_packaging (product_item_id, packaging_item_id, qty_per_unit, applies_to) values (tt.iid('C2-A1'), tt.iid('C2-A2'), 1, 'sale'), (tt.iid('C2-B1'), tt.iid('C2-B2'), 1, 'sale');
insert into item_changes (item_id, patch, requested_by, status) values (tt.iid('C2-A2'), '{"sell_price":51}', :'o', 'pending'), (tt.iid('C2-B2'), '{"sell_price":71}', :'o', 'pending');
insert into item_master_links (item_id, dict_code) values (tt.iid('C2-A2'), 'D-A'), (tt.iid('C2-B2'), 'D-B');
insert into item_mapping_review (item_id, status) values (tt.iid('C2-A2'), 'pending'), (tt.iid('C2-B2'), 'pending');
insert into item_map_actions (item_id, action) values (tt.iid('C2-A2'), 'keep'), (tt.iid('C2-B2'), 'keep');
insert into customer_points_ledger (customer_id, delta, reason) values (:'cust_a', 5, 'adjust'), (:'cust_b', 7, 'adjust');
insert into customer_gifts (customer_id, occasion, gift_text_en) values (:'cust_a', 'c2', 'A gift'), (:'cust_b', 'c2', 'B gift');
insert into customer_tier_history (customer_id, to_tier, reason) select :'cust_a', id, 'manual' from customer_tiers limit 1;
insert into customer_tier_history (customer_id, to_tier, reason) select :'cust_b', id, 'manual' from customer_tiers limit 1;
insert into notify_optin (customer_id, channel, status, source) values (:'cust_a', 'sms', 'in', 'owner_entry'), (:'cust_b', 'sms', 'in', 'owner_entry');
insert into recipe_steps (recipe_id, step_no, step_name) values (:'rec_a', 1, 'mix'), (:'rec_b', 1, 'mix');
insert into recipe_cost_components (recipe_id, component_type, basis, amount) select :'rec_a', code, 'per_batch', 5 from cost_component_types limit 1;
insert into recipe_cost_components (recipe_id, component_type, basis, amount) select :'rec_b', code, 'per_batch', 6 from cost_component_types limit 1;
insert into landed_supplier_flags (supplier_id, kind) values (:'sup_a', 'imported'), (:'sup_b', 'imported');
insert into deed_templates (family_id, version, role_code, title_bn) values (9001, 1, 'salesperson', 'দলিল');
insert into item_bulk_batches (client_batch, created_by, mode, rows_n) values ('c2-batch', :'o', 'direct', 1);
insert into assets (item_id, location_id) values (tt.iid('C2-A2'), 1), (tt.iid('C2-B2'), :'hw1'::int);
insert into asset_costs (asset_id, cost) select id, 100 from assets;
select tt.t('T0 the extra children follow their parents: points / gifts / history / optin / steps / costs / flags / asset costs carry the business of the owner row',
  (select org_unit_id from customer_points_ledger where customer_id = :'cust_b') = :'hbz'::bigint and (select org_unit_id from customer_gifts where customer_id = :'cust_a') = :'sbz'::bigint
  and (select org_unit_id from recipe_steps where recipe_id = :'rec_b') = :'hbz'::bigint and (select org_unit_id from item_cost_flags where item_id = tt.iid('C2-B2')) = :'hbz'::bigint
  and (select org_unit_id from landed_supplier_flags where supplier_id = :'sup_b') = :'hbz'::bigint and (select org_unit_id from asset_costs c join assets a on a.id = c.asset_id where a.location_id = :'hw1'::int) = :'hbz'::bigint
  and (select org_unit_id from asset_costs c join assets a on a.id = c.asset_id where a.location_id = 1) = :'sbz'::bigint and (select org_unit_id from unit_conversions where item_id = tt.iid('C2-B2')) = :'hbz'::bigint
  and (select org_unit_id from product_packaging where product_item_id = tt.iid('C2-B1')) = :'hbz'::bigint and (select org_unit_id from shelf_life_rules where item_id = tt.iid('C2-A2')) = :'sbz'::bigint
  and (select org_unit_id from item_changes where item_id = tt.iid('C2-B2')) = :'hbz'::bigint and (select org_unit_id from item_mapping_review where item_id = tt.iid('C2-A2')) = :'sbz'::bigint
  and (select org_unit_id from recipe_cost_components where recipe_id = :'rec_b') = :'hbz'::bigint);
select tt.t('T0 price history of the items and any item cost row carry the business of the item (children follow the parent)', not exists (select 1 from item_price_history h join items i on i.id = h.item_id where h.org_unit_id is distinct from i.org_unit_id)
  and not exists (select 1 from item_costs c join items i on i.id = c.item_id where c.org_unit_id is distinct from i.org_unit_id) and (select count(*) from item_price_history) > 0);
create or replace function tt.cnt(p_sql text) returns bigint language plpgsql as $$ declare n bigint; begin execute p_sql into n; return n; exception when others then return -1; end $$;
grant execute on all functions in schema tt to authenticated, anon;
select count(*) as n_cust_a from customers where org_unit_id = :'sbz'::bigint \gset
select count(*) as n_items_total from items \gset
select md5(string_agg(x::text, '|' order by x::text)) as dues_h from (select * from customer_dues()) x \gset

\echo == T1 switch OFF: everybody still reads every master (the old behaviour)
select tt.t('T1 org_scope_on is OFF by default', not rule_on('org_scope_on'));
set role authenticated;
select tt.as(:'bs');
select tt.eq('T1 OFF: a B salesperson reads every item (A and B)', :'n_items_total'::int, (select count(*) from items));
select tt.eq('T1 OFF: ... and the A customer by direct select', 1, (select count(*) from customers where id = :'cust_a'));
select tt.eq('T1 OFF: ... and the A expense head', 1, (select count(*) from option_lists where value_code = 'c2_a_only'));
reset role;
select tt.as(:'bs');
select tt.t('T1 OFF: find_customer of an A mobile works for a B person', (find_customer('01711000001') ->> 'found')::boolean);
select tt.t('T1 OFF: the guard is silent: a B manager can still save an A customer', (customer_save(:'cust_a'::uuid, '{"note":"off-ok"}'::jsonb, gen_random_uuid()) ->> 'id') = :'cust_a');
select tt.as(:'bm');
select tt.t('T1 OFF: supplier_pick lists both suppliers', (select count(*) from supplier_pick() where name in ('A Supplier', 'B Supplier')) = 2);
select tt.as(:'o');
select tt.t('T1 OFF: master_scope_report132 is an owner / org_manage tool', (select count(*) from master_scope_report132()) >= 50);
select tt.as(:'bm');
select tt.err('T1 a B manager cannot read the coverage report', $$select * from master_scope_report132()$$, 'not allowed');
select tt.err('T1 ... nor the masters preflight', $$select org_masters_preflight()$$, 'not allowed');
select tt.err('T1 ... nor create a share', format($q$select master_share_create('items', null, %s, %s, 'x', gen_random_uuid())$q$, :'hbz', :'sbz'), 'not allowed');

\echo == T2 switch ON: reads are separated (direct select, RPC lookups)
select tt.as(:'o');
update rules set value = 'true'::jsonb where key = 'org_scope_on';
select tt.t('T2 the switch reads ON', rule_on('org_scope_on') and _org_on123());
set role authenticated;
select tt.as(:'ao');
select tt.eq('T2 A salesperson: direct select of items = only the sweets items', (select count(*) from items where org_unit_id = :'sbz'::bigint), (select count(*) from items));
select tt.eq('T2 A salesperson: a B item by id = 0 rows', 0, (select count(*) from items where id = tt.iid('C2-B1')));
select tt.eq('T2 A salesperson: a B item by code = 0 rows', 0, (select count(*) from items where code = 'C2-B1'));
select tt.eq('T2 A salesperson: the B customer = 0 rows, the A customer = 1', 1, (select count(*) from customers where id in (:'cust_a', :'cust_b')));
select tt.eq('T2 A salesperson: sees no B recipe, no B recipe line', 0, (select count(*) from recipes where id = :'rec_b') + (select count(*) from recipe_lines where recipe_id = :'rec_b'));
select tt.eq('T2 A salesperson: no B employee row (direct select)', 0, (select count(*) from employees where full_name_bn = 'B Employee'));
select tt.eq('T2 A salesperson: the units list is shared (10 rows), the sweets expense head visible', 11, (select count(*) from option_lists where list_code = 'units' or value_code = 'c2_a_only'));
select tt.as(:'bs');
select tt.eq('T2 B salesperson: no A item (57 old + 2 new), only the 2 B items', 2, (select count(*) from items));
select tt.eq('T2 B salesperson: the units list is still visible (shared), the sweets expense heads are not', 10, (select count(*) from option_lists));
select tt.eq('T2 B salesperson: no A customer, the B customer yes', 1, (select count(*) from customers));
select tt.eq('T2 B salesperson: no sweets categories', 0, (select count(*) from item_categories));
select tt.eq('T2 B salesperson: no item cost / price history of A items', 0, (select count(*) from item_costs where item_id = tt.iid('C2-A1')) + (select count(*) from item_price_history where item_id = tt.iid('C2-A1')));
select tt.eq('T2 B salesperson: no list_defs of the sweets lists, only the shared units definition', 1, (select count(*) from list_defs));
reset role;
select tt.as(:'o');
set role authenticated;
select tt.eq('T2 owner: every item (59 + 2 sweets-or-B ... all of them)', :'n_items_total'::int, (select count(*) from items));
select tt.eq('T2 owner: both customers, both suppliers', 4, (select count(*) from customers where id in (:'cust_a', :'cust_b')) + (select count(*) from suppliers));
reset role;
-- the lookups that run inside definer functions
select tt.as(:'ao');
select tt.t('T2 find_customer: A person finds the A mobile', (find_customer('01711000001') ->> 'found')::boolean);
select tt.t('T2 find_customer: A person does NOT find the B mobile', not (find_customer('01722000002') ->> 'found')::boolean);
select tt.t('T2 customer_pos_info: the B mobile is not found for A', not (customer_pos_info('01722000002') ->> 'found')::boolean);
select tt.eq('T2 customer_directory (A person) lists only A customers', 0, (select count(*) from customer_directory(100) where id = :'cust_b'::uuid));
select tt.t('T2 customer_directory (A person) lists the A customer', (select count(*) from customer_directory(100) where id = :'cust_a'::uuid) = 1);
select tt.as(:'bs');
select tt.t('T2 find_customer: B person finds B, not A', (find_customer('01722000002') ->> 'found')::boolean and not (find_customer('01711000001') ->> 'found')::boolean);
select tt.as(:'am');
select tt.eq('T2 supplier_pick (A manager): only the A supplier', 1, (select count(*) from supplier_pick() where name in ('A Supplier', 'B Supplier')));
select tt.eq('T2 scan_match_items: the B item name is not matched for A', 0, (select count(*) from scan_match_items('B item 2', 10) where code = 'C2-B2'));
select tt.eq('T2 item_dup_check: a B item name is no duplicate for A', 0, (select count(*) from item_dup_check('b2', 'B item 2')));
select tt.t('T2 item_dup_check: the A item name is a duplicate for A', (select count(*) from item_dup_check('a2', 'A item 2')) = 1);
select tt.t('T2 category_list: A sees the sweets category', (select count(*) from category_list(true) where code = 'C2CAT') = 1);
select tt.as(:'bm');
select tt.t('T2 category_list: B sees none of the sweets categories', (select count(*) from category_list(true)) = 0);
select tt.eq('T2 artisan_list: B sees only its artisan', 1, (select jsonb_array_length(artisan_list(true))) );
select tt.as(:'o');
select tt.eq('T2 owner: supplier_pick lists both', 2, (select count(*) from supplier_pick() where name in ('A Supplier', 'B Supplier')));
select tt.t('T2 owner: find_customer finds both mobiles', (find_customer('01711000001') ->> 'found')::boolean and (find_customer('01722000002') ->> 'found')::boolean);

-- GENERIC: for every scoped table, a user of one business sees 0 rows of the other business (RLS applies: role authenticated; a table that is closed to the browser counts 0)
create or replace function tt.leak(p_biz bigint) returns jsonb language plpgsql as $$
declare r record; n bigint; res jsonb := '{}'::jsonb;
begin
  for r in select table_name from public.master_scope132 where decision = 'scoped' order by 1 loop
    begin execute format('select count(*) from public.%I where org_unit_id = $1', r.table_name) into n using p_biz;
    exception when others then n := 0; end;
    if n > 0 then res := res || jsonb_build_object(r.table_name, n); end if;
  end loop;
  return res;
end $$;
grant execute on all functions in schema tt to authenticated, anon;
set role authenticated;
select tt.as(:'ao');
select tt.leak(:'hbz'::bigint) as leak_a \gset
select tt.as(:'bs');
select tt.leak(:'sbz'::bigint) as leak_b \gset
select tt.as(:'o');
select tt.leak(:'hbz'::bigint) as leak_o \gset
reset role;
select tt.t('T2 GENERIC: an A user reads no row of business B in ANY of the 34 scoped tables', :'leak_a'::jsonb = '{}'::jsonb, '{}', :'leak_a');
select tt.t('T2 GENERIC: a B user reads no row of business A in ANY scoped table (the units rows have no business)', :'leak_b'::jsonb = '{}'::jsonb, '{}', :'leak_b');
select tt.t('T2 GENERIC: the owner reads the B rows of the tables that have any (at least 20 tables)', (select count(*) from jsonb_object_keys(:'leak_o'::jsonb)) >= 20, 'true', :'leak_o');

\echo == T3 switch ON: writes are refused (id swap, explicit business, RPC parameters)
select tt.as(:'ao');
select tt.err('T3 A person saves a B customer by id: refused like a missing id', format($q$select customer_save(%L::uuid, '{"note":"x"}'::jsonb, gen_random_uuid())$q$, :'cust_b'), 'customer_not_found');
select tt.err('T3 A person creates a customer INTO the B business: refused', format($q$select customer_save(null, '{"mobile":"01733000003","name":"Sneaky","org_unit_id":%s}'::jsonb, gen_random_uuid())$q$, :'hbz'), 'not allowed');
select tt.t('T3 A person creates an ordinary customer (customer_save): it lands in the sweets business', (customer_save(null, '{"mobile":"01733000004","name":"Plain A"}'::jsonb, gen_random_uuid()) ->> 'dup') = 'false');
select tt.t('T3 ... and carries the A business', (select org_unit_id from customers where mobile like '%1733000004') = :'sbz'::bigint);
select tt.err('T3 A person sells to the B customer mobile at an A place: no B customer is touched (the lookup does not see it; the global unique stops a duplicate)',
  format($q$select record_sale2(gen_random_uuid(), 1, '[{"item_id":"%s","qty":1,"price":100}]'::jsonb, 0, '[]', '01722000002', 'Thief', 'retail', null, false)$q$, tt.iid('C2-A1')), 'customers_mobile_key');
select tt.err('T3 A person reads the profile of a B customer by id (customer_profile): refused like a missing id', format($q$select customer_profile(%L::uuid)$q$, :'cust_b'), 'customer_not_found');
select tt.t('T3 A person: the balance of a B customer by id is NULL (customer_balance), the balance of an A customer is a number', customer_balance(:'cust_b'::uuid) is null and customer_balance(:'cust_a'::uuid) is not null);
select tt.err('T3 A person adds loyalty points to a B customer by id: refused', format($q$select customer_points_adjust(%L::uuid, 5, 'x', gen_random_uuid())$q$, :'cust_b'), 'not');
select tt.eq('T3 ... the B customer still has its 7 points', 7, (select sum(delta) from customer_points_ledger where customer_id = :'cust_b'));
select tt.as(:'am');
select tt.err('T3 A manager changes a B item by id (item_apply): refused', format($q$select item_apply(%L::uuid, '{"sell_price":1}'::jsonb)$q$, tt.iid('C2-B1')), 'item_not_found');
select tt.err('T3 A manager edits the B supplier by id (save_supplier): refused', format($q$select save_supplier(%L::uuid, '{"note":"x"}'::jsonb)$q$, :'sup_b'), 'not found');
select tt.eq('T3 ... the B item price is still 500', 500, (select sell_price from items where code = 'C2-B1'));
select tt.as(:'o');
select tt.err('T3 even the owner cannot book a B item at an A place (cross_business_item)', format($q$select stock_opening(%L::uuid, 3, 5, 10)$q$, tt.iid('C2-B1')), 'cross_business_item');
select tt.err('T3 ... nor an A item at a B place', format($q$select stock_opening(%L::uuid, %s, 5, 10)$q$, tt.iid('C2-A2'), :'hw1'), 'cross_business_item');
select tt.t('T3 ... an A item at an A place and a B item at a B place are fine', stock_opening(tt.iid('C2-A2'), 2, 5, 10) is not null and stock_opening(tt.iid('C2-B2'), :'hw2'::int, 5, 10) is not null);
select tt.as(:'bm');
select item_apply(tt.iid('C2-B1'), '{"sell_price":510}'::jsonb) ->> 'status' as st \gset
select tt.t('T3 B manager changes its own item price', :'st' = 'applied' and (select sell_price from items where code = 'C2-B1') = 510);
select tt.err('T3 B manager changes the sweets item by id: refused', format($q$select item_apply(%L::uuid, '{"sell_price":1}'::jsonb)$q$, tt.iid('C2-A1')), 'item_not_found');
select tt.err('T3 B manager updates the sweets artisan by id (artisan_set_active): refused', format($q$select artisan_set_active(%s, false, 'x')$q$, (select id from artisans where name = 'A Artisan')), 'not');
select tt.eq('T3 ... the sweets artisan is still active', 1, (select count(*) from artisans where name = 'A Artisan' and active));
select tt.as(:'o');
-- direct table updates by a business user are impossible anyway (no privilege), but the trigger refuses even a function-level update; check the org cannot be moved
select tt.err('T3 the business of a row never moves (owner tries to move a B item to sweets)', format($q$update items set org_unit_id = %s where code = 'C2-B2'$q$, :'sbz'), 'org_fixed');
select tt.err('T3 ... same for a customer', format($q$update customers set org_unit_id = %s where id = %L$q$, :'sbz', :'cust_b'), 'master_org_fixed');
select tt.err('T3 ... same for a child row (recipe line)', format($q$update recipe_lines set org_unit_id = %s where recipe_id = %L$q$, :'sbz', :'rec_b'), 'master_org_fixed');

-- GENERIC WRITE: an UPDATE of a B row by an A user is refused by the trigger in every scoped table that has a B row (the claim is the user, the session is a superuser: no privilege layer in between)
create or replace function tt.wleak(p_biz bigint) returns jsonb language plpgsql as $$
declare r record; n bigint; res jsonb := '{"tried":0}'::jsonb; refused int := 0; tried int := 0; open_ text := '';
begin
  for r in select table_name from public.master_scope132 where decision = 'scoped' order by 1 loop
    execute format('select count(*) from public.%I where org_unit_id = $1', r.table_name) into n using p_biz;
    continue when n = 0;
    tried := tried + 1;
    begin
      execute format('update public.%I set org_unit_id = org_unit_id where ctid in (select ctid from public.%I where org_unit_id = $1 limit 1)', r.table_name, r.table_name) using p_biz;
      open_ := open_ || r.table_name || ' ';
    exception when others then
      if sqlerrm = 'not found' then refused := refused + 1; else open_ := open_ || r.table_name || '(' || sqlerrm || ') '; end if;
    end;
  end loop;
  return jsonb_build_object('tried', tried, 'refused', refused, 'not_refused', open_);
end $$;
grant execute on all functions in schema tt to authenticated, anon;
select tt.as(:'ao');
select tt.wleak(:'hbz'::bigint) as wleak_a \gset
select tt.as(:'bm');
select tt.wleak(:'sbz'::bigint) as wleak_b \gset
select tt.t('T3 GENERIC WRITE: an A user is refused with "not found" on every scoped table that holds a B row (at least 20 tables, none left open)',
  (:'wleak_a'::jsonb ->> 'tried')::int >= 20 and (:'wleak_a'::jsonb ->> 'tried') = (:'wleak_a'::jsonb ->> 'refused'), 'true', :'wleak_a');
select tt.t('T3 GENERIC WRITE: a B manager is refused on every scoped table that holds an A row (at least 20 tables, none left open)',
  (:'wleak_b'::jsonb ->> 'tried')::int >= 20 and (:'wleak_b'::jsonb ->> 'tried') = (:'wleak_b'::jsonb ->> 'refused'), 'true', :'wleak_b');
select tt.as(:'o');
select tt.t('T3 GENERIC WRITE: the owner is not refused (the same update passes)', (tt.wleak(:'hbz'::bigint) ->> 'refused') = '0');

-- normal flows inside ONE business keep working with the switch ON (purchase, transfer, return) and a cross-business line is refused
select tt.as(:'o');
select save_purchase(gen_random_uuid(), null, :'sup_b'::uuid, :'hw1'::int, 'C2-PB-1', current_date, format('[{"item_id":"%s","qty":10,"unit":"pc","unit_cost":50}]', tt.iid('C2-B1'))::jsonb) ->> 'id' as pur_b \gset
select post_purchase(:'pur_b'::uuid, '{}'::jsonb) ->> 'status' as pst \gset
select tt.t('T3 ON: a purchase of a B item from a B supplier at a B place is saved and posted (stock +10)', :'pur_b' is not null and :'pst' = 'posted' and (select sum(qty_delta) from stock_ledger where item_id = tt.iid('C2-B1') and location_id = :'hw1'::int and ref_type = 'purchase') = 10);
select save_purchase(gen_random_uuid(), null, :'sup_b'::uuid, :'hw1'::int, 'C2-PB-2', current_date, format('[{"item_id":"%s","qty":1,"unit":"pc","unit_cost":5}]', tt.iid('C2-A1'))::jsonb) ->> 'id' as pur_x \gset
select tt.err('T3 ON: posting a purchase line with an A item at a B place is refused (cross_business_item)', format($q$select post_purchase(%L::uuid, '{}'::jsonb)$q$, :'pur_x'), 'cross_business_item');
select stock_transfer(:'hw1'::int, :'hw2'::int, tt.iid('C2-B1'), 2, null, 'x', gen_random_uuid()) is not null as xf \gset
select tt.t('T3 ON: a stock transfer of a B item inside the business works (hw1 -> hw2)', :'xf'::boolean);
select sale_return(gen_random_uuid(), :'sale_b'::uuid, format('[{"item_id":"%s","qty":1}]', tt.iid('C2-B1'))::jsonb, 'damaged', null, 'cash') is not null as srt \gset
select tt.t('T3 ON: sale_return of the B sale by the owner is accepted (same business)', :'srt'::boolean);

\echo == T4 new masters are scoped to the caller / working business automatically
select tt.as(:'bs');
select record_sale2(gen_random_uuid(), :'hw1'::int, format('[{"item_id":"%s","qty":1,"price":500}]', tt.iid('C2-B1'))::jsonb, 0, '[{"mode":"cash","amount":510}]', '01744000005', 'New B Cust', 'retail', null, false) ->> 'id' as nsale \gset
select tt.t('T4 B salesperson sale to a new mobile at hw1 makes a B customer', :'nsale' is not null and (select org_unit_id from customers where mobile like '%1744000005') = :'hbz'::bigint);
select tt.as(:'bs');
select customer_save(null, '{"mobile":"01755000006","name":"B Made"}'::jsonb, gen_random_uuid()) ->> 'id' as ncust \gset
select tt.t('T4 B salesperson makes a customer with customer_save: business HARDWARE', (select org_unit_id from customers where id = :'ncust'::uuid) = :'hbz'::bigint);
select tt.as(:'bm');
select item_new('{"name_bn":"নতুন","name_en":"B new item","unit":"pc","sell_price":9,"item_type":"finished_good"}'::jsonb) ->> 'item_id' as nitem \gset
select tt.t('T4 B manager makes an item with item_new: business HARDWARE', (select org_unit_id from items where id = :'nitem'::uuid) = :'hbz'::bigint);
select tt.as(:'o');
select employee_save(null, gen_random_uuid(), format('{"full_name_bn":"Emp Via Function","primary_location_id":%s}', :'hw1')::jsonb) ->> 'id' as efid \gset
select tt.t('T4 employee_save (owner, place hw1): the employee is tagged HARDWARE (business of the place)', :'efid' is not null and (select org_unit_id from employees where id = :'efid'::uuid) = :'hbz'::bigint);
select item_new('{"name_bn":"নতুন","name_en":"Owner new item","unit":"pc","sell_price":9,"item_type":"finished_good"}'::jsonb) ->> 'item_id' as oitem \gset
select tt.is('T4 owner (two businesses, no working business): the new item lands in the sweets business', (select org_unit_id::text from items where id = :'oitem'::uuid), :'sbz');
select master_context_set132(:'hbz'::bigint) ->> 'org_unit_id' as wctx \gset
select item_new('{"name_bn":"নতুন","name_en":"Owner new B item","unit":"pc","sell_price":9,"item_type":"finished_good"}'::jsonb) ->> 'item_id' as oitem2 \gset
select tt.t('T4 owner sets the working business HARDWARE; the next item is a B item', :'wctx' = :'hbz' and (select org_unit_id from items where id = :'oitem2'::uuid) = :'hbz'::bigint and (master_context_get132() ->> 'working')::bigint = :'hbz'::bigint);
select coalesce(master_context_set132(null) ->> 'org_unit_id', '') as wclr \gset
select tt.t('T4 ... and the owner can clear it again (back to the default business)', :'wclr' = '' and (master_context_get132() ->> 'working') is null);
select tt.as(:'bs');
select tt.err('T4 a B user cannot make the sweets business their working business', format($q$select master_context_set132(%s)$q$, :'sbz'), 'not allowed');
select tt.t('T4 a B user working business defaults to the only business', (master_context_get132() ->> 'working')::bigint = :'hbz'::bigint);
-- the trigger itself, as a logged-in user (the session is a superuser, the claim is the user): fill, refuse a foreign business, refuse a foreign update, children follow the parent
select tt.as(:'bm');
insert into option_lists (list_code, value_code, label_bn, label_en, label_mix, sort) values ('wastage_reasons', 'c2_b_only', 'বি', 'B only reason', 'B only reason', 98);
select tt.t('T4 trigger: a vocabulary row inserted by a B user is tagged HARDWARE', (select org_unit_id from option_lists where value_code = 'c2_b_only') = :'hbz'::bigint);
select tt.err('T4 trigger: ... a B user cannot insert a vocabulary row into the sweets business', format($q$insert into option_lists (list_code, value_code, label_bn, org_unit_id) values ('wastage_reasons', 'c2_x', 'x', %s)$q$, :'sbz'), 'not allowed');
select tt.err('T4 trigger: ... nor change a sweets row (answer = a missing id)', $$update option_lists set label_en = 'hacked' where value_code = 'c2_a_only'$$, 'not found');
select tt.err('T4 trigger: ... nor add an ingredient line to a sweets recipe (child of a foreign parent)', format($q$insert into recipe_lines (recipe_id, ingredient_item_id, qty, unit) values (%L, %L, 1, 'pc')$q$, :'rec_a', tt.iid('C2-A2')), 'not allowed');
select tt.err('T4 trigger: ... nor change a shared (NULL business) units row', $$update option_lists set label_en = 'x' where list_code = 'units' and value_code = 'box'$$, 'not found');
with i as (insert into recipe_lines (recipe_id, ingredient_item_id, qty, unit) values (:'rec_b', tt.iid('C2-B1'), 1, 'pc') returning org_unit_id) select org_unit_id as rl_org from i \gset
select tt.t('T4 trigger: a B user adds a line to its own recipe: tagged HARDWARE', :'rl_org'::bigint = :'hbz'::bigint);
select tt.as(:'o');
with u as (update option_lists set label_en = 'A only head' where value_code = 'c2_a_only' returning 1) select count(*) as ow from u \gset
select tt.t('T4 trigger: the owner may write into any business (a sweets row)', :'ow'::int = 1);

\echo == T5 master_shares132: the only way to cross the border
select tt.as(:'o');
select master_share_create('items', null, :'hbz'::bigint, :'sbz'::bigint, 'B items for A', gen_random_uuid()) ->> 'id' as sh1 \gset
select tt.t('T5 the owner shares every B item with A (read only)', :'sh1' is not null);
select tt.as(:'ao');
set role authenticated;
select tt.t('T5 A now READS the B items by direct select', (select count(*) from items where code = 'C2-B1') = 1 and (select count(*) from items where org_unit_id = :'hbz'::bigint) >= 2);
reset role;
select tt.err('T5 ... but cannot change one (no write by share)', format($q$select item_apply(%L::uuid, '{"sell_price":1}'::jsonb)$q$, tt.iid('C2-B1')), 'not');
select tt.as(:'o');
select tt.err('T5 ... nor move stock of it at an A place (even the owner)', format($q$select stock_opening(%L::uuid, 2, 5, 10)$q$, tt.iid('C2-B1')), 'cross_business_item');
select tt.as(:'ao');
set role authenticated;
select tt.as(:'ao');
select tt.eq('T5 ... the share does not open the B item COSTS (children are never shared)', 0, (select count(*) from item_costs where item_id = tt.iid('C2-B1')));
reset role;
set role authenticated;
select tt.as(:'ao');
select tt.eq('T5 ... B customers stay hidden (customers are never shareable)', 0, (select count(*) from customers where org_unit_id = :'hbz'::bigint));
reset role;
select tt.as(:'bs');
set role authenticated;
select tt.t('T5 the share is one-way: B still sees no sweets item', (select count(*) from items where code = 'C2-A1') = 0);
reset role;
select tt.as(:'o');
select tt.is('T5 the same share again: dup, no second row', (master_share_create('items', null, :'hbz'::bigint, :'sbz'::bigint, 'again', gen_random_uuid()) ->> 'dup'), 'true');
select tt.err('T5 customers are not shareable', format($q$select master_share_create('customers', null, %s, %s, 'x', gen_random_uuid())$q$, :'hbz', :'sbz'), 'table_not_shareable');
select tt.err('T5 an item_costs share is refused (children follow their parent)', format($q$select master_share_create('item_costs', null, %s, %s, 'x', gen_random_uuid())$q$, :'hbz', :'sbz'), 'table_not_shareable');
select tt.err('T5 a share from a business to itself is refused', format($q$select master_share_create('items', null, %s, %s, 'x', gen_random_uuid())$q$, :'hbz', :'hbz'), 'bad_business');
select tt.err('T5 a share of a row that does not exist is refused', format($q$select master_share_create('items', 'no-such-id', %s, %s, 'x', gen_random_uuid())$q$, :'sbz', :'hbz'), 'row_not_found');
select tt.eq('T5 master_share_list shows the share', 1, (select count(*) from master_share_list() where table_name = 'items' and status = 'active'));
select master_share_revoke(:'sh1'::bigint, 'test') ->> 'dup' as rv \gset
select tt.is('T5 revoke works', :'rv', 'false');
select tt.as(:'ao');
set role authenticated;
select tt.eq('T5 after the revoke A sees no B item again', 0, (select count(*) from items where org_unit_id = :'hbz'::bigint));
reset role;
select tt.as(:'o');
-- a row-level share (one item) and a list-level share (a whole vocabulary)
select master_share_create('items', tt.iid('C2-B2')::text, :'hbz'::bigint, :'sbz'::bigint, 'one item', gen_random_uuid()) ->> 'id' as sh2 \gset
select master_share_create('option_lists', 'expense_heads', :'sbz'::bigint, :'hbz'::bigint, 'heads to B', gen_random_uuid()) ->> 'id' as sh3 \gset
select tt.t('T5 one-row share and one list-level share are created', :'sh2' is not null and :'sh3' is not null);
select tt.as(:'ao');
set role authenticated;
select tt.eq('T5 A sees exactly the one shared B item', 1, (select count(*) from items where org_unit_id = :'hbz'::bigint));
reset role;
select tt.as(:'bs');
set role authenticated;
select tt.eq('T5 B sees the whole expense_heads list (all 7 + the sweets-only head) after the list share, and still the units', 8 + 10, (select count(*) from option_lists where list_code in ('expense_heads', 'units')));
reset role;
select tt.t('T5 a B salesperson cannot create a share', (select tt.cnt(format($q$select (master_share_create('items', null, %s, %s, 'x', gen_random_uuid()) ->> 'id')::bigint$q$, :'sbz', :'hbz'))) = -1);
select tt.as(:'o');
select master_share_revoke(:'sh2'::bigint, 'test') is not null and master_share_revoke(:'sh3'::bigint, 'test') is not null as rv2 \gset
select tt.t('T5 the other shares are revoked again', :'rv2'::boolean);

\echo == T7 deactivate keeps history; the owner sees everything; masters of a deactivated record stay readable
select tt.as(:'bm');
select customer_save(:'cust_b'::uuid, '{"active":false}'::jsonb, gen_random_uuid()) ->> 'id' as dc \gset
select tt.t('T7 B manager deactivates a B customer: the row and its sale history stay', :'dc' is not null and (select active from customers where id = :'cust_b') = false and (select count(*) from sales where customer_id = :'cust_b') = 1);
select tt.t('T7 ... the customer ledger still answers for the B customer', (select count(*) from customer_ledger(:'cust_b'::uuid)) >= 1);
select tt.as(:'o');
select tt.t('T7 owner still sees the deactivated B customer and the deactivated flag', (select active from customers where id = :'cust_b') = false);
select tt.as(:'bm');
select item_apply(tt.iid('C2-B2'), '{"is_active":false}'::jsonb) ->> 'status' as di \gset
select tt.t('T7 B manager deactivates a B item: kept with its stock history', :'di' = 'applied' and (select is_active from items where code = 'C2-B2') = false and (select count(*) from stock_ledger where item_id = tt.iid('C2-B2')) >= 1);

\echo == T8 coverage: every table of the audit list has a decision; scoped tables have column, policy, trigger
select tt.as(:'o');
select tt.eq('T8 registry has all 50 tables of the audit list (4.5)', 50, (select count(*) from master_scope132 where table_name in (
  'acct_mappings','artisans','asset_costs','benefit_types','coa_accounts','cost_charge_types','cost_component_types','cost_source_types','customer_gifts','customer_points_ledger','customer_tier_history',
  'customer_tiers','customers','deed_templates','doc_template_choice','employees','forms','gift_rules','invoice_templates','item_bulk_batches','item_categories','item_changes','item_class_map',
  'item_cost_flags','item_costs','item_import_batches','item_logistics','item_map_actions','item_mapping_review','item_master_links','item_price_history','item_types','items','leave_types','list_defs',
  'notify_templates','option_lists','partner_templates','print_profiles','product_packaging','recipe_cost_components','recipe_lines','recipe_steps','recipe_versions','recipes','report_brand_map',
  'shelf_life_rules','staff_roles','suppliers','unit_conversions')));
select tt.eq('T8 decisions: 30 scoped + 4 extra scoped, 14 shared config, 4 location-scoped by phase123, 2 deferred', 54, (select count(*) from master_scope132));
select tt.eq('T8 ... scoped 34', 34, (select count(*) from master_scope132 where decision = 'scoped'));
select tt.eq('T8 ... shared_config 14, loc_scoped_c1 4, deferred 2', 20, (select count(*) from master_scope132 where decision in ('shared_config', 'loc_scoped_c1', 'deferred')));
select tt.eq('T8 every scoped table has the org_unit_id column', 34, (select count(*) from master_scope132 m where decision = 'scoped' and exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = m.table_name and c.column_name = 'org_unit_id')));
select tt.eq('T8 every scoped table has the restrictive read policy <t>_m132', 34, (select count(*) from master_scope132 m where decision = 'scoped' and exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = m.table_name and p.policyname = m.table_name || '_m132' and p.permissive = 'RESTRICTIVE')));
select tt.eq('T8 every scoped table has the fill + guard trigger', 34, (select count(*) from master_scope132 m where decision = 'scoped' and exists (select 1 from pg_trigger t where t.tgrelid = ('public.' || m.table_name)::regclass and t.tgname = 'a132_scope' and not t.tgisinternal)));
select tt.eq('T8 no scoped table has a row without a business (the units vocabulary rows are the only NULLs)', 0, (select coalesce(sum(rows_without_business), 0) from master_scope_report132() where decision = 'scoped' and table_name not in ('option_lists', 'list_defs')));
select tt.t('T8 the units vocabulary stays shared (NULL business), nothing else in the vocabularies', not exists (select 1 from option_lists where org_unit_id is null and list_code <> 'units') and not exists (select 1 from list_defs where org_unit_id is null and list_code <> 'units'));
select tt.t('T8 report: deferred tables are listed with the reason', (select count(*) from master_scope_report132() where decision = 'deferred' and why like 'DEFERRED%') = 2);
select tt.t('T8 report counts rows (items > 60)', (select total_rows from master_scope_report132() where table_name = 'items') > 60);
select tt.t('T8 every row of the registry that is scoped is an existing table', not exists (select 1 from master_scope132 where decision = 'scoped' and to_regclass('public.' || table_name) is null));
-- anon and privileges
select tt.t('T8 anon cannot run any new function', not has_function_privilege('anon', 'public.master_share_create(text,text,bigint,bigint,text,uuid)', 'execute') and not has_function_privilege('anon', 'public.org_masters_preflight()', 'execute')
  and not has_function_privilege('anon', 'public.org_masters_relax_unique(boolean,boolean)', 'execute') and not has_function_privilege('anon', 'public.master_context_set132(bigint)', 'execute')
  and not has_function_privilege('anon', 'public._m132_shared(text,bigint,text)', 'execute') and not has_function_privilege('anon', 'public._m132_mybiz()', 'execute'));
select tt.t('T8 the internals are closed to the browser', not has_function_privilege('authenticated', 'public._m132_scope()', 'execute') and not has_function_privilege('authenticated', 'public._m132_patch(text,text,text[])', 'execute')
  and not has_function_privilege('authenticated', 'public._m132_caller_biz()', 'execute') and not has_function_privilege('authenticated', 'public._m132_relaxed()', 'execute')
  and not has_function_privilege('authenticated', 'public._m132_vis(text,bigint,text,boolean)', 'execute') and not has_function_privilege('authenticated', 'public._m132_own(bigint)', 'execute') and not has_function_privilege('authenticated', 'public._m132_at(bigint,int)', 'execute')
  and has_function_privilege('authenticated', 'public._m132_mybiz()', 'execute'));
select tt.t('T8 the new tables have no browser write and no anon access', not has_table_privilege('authenticated', 'public.master_shares132', 'insert') and not has_table_privilege('authenticated', 'public.master_scope132', 'update')
  and not has_table_privilege('anon', 'public.master_shares132', 'select') and not has_table_privilege('anon', 'public.master_unique_log132', 'select') and not has_table_privilege('authenticated', 'public.master_ctx132', 'insert'));
select tt.err('T8 shares are never hard deleted', $$delete from master_shares132$$, 'nothing is deleted');

\echo == T9 paste twice, switch OFF again = the old behaviour, then ON again
select tt.as(:'o');
select md5(string_agg(x::text, '|' order by x::text)) as h_sh from (select table_name, row_key, from_org, to_org, status from master_shares132) x \gset
select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) as h_fn_before from pg_proc p where p.pronamespace = 'public'::regnamespace \gset
select count(*) as n_pol_before from pg_policies where policyname like '%m132' \gset
select count(*) as n_trg_before from pg_trigger where tgname in ('a132_scope', 'stock_ledger_xbiz132', 'rules_m132') \gset
select md5(string_agg(x::text, '|' order by x::text)) as h_cust from (select id, mobile, org_unit_id from customers) x \gset
\i supabase/phase132.sql
-- phase134 re-creates master_share_list / master_context_set132 / patches master_scope_report132: it is last in the order, so a re-paste of 132 is followed by it
\i supabase/phase134.sql
select tt.t('T9 paste again: no error, same functions (patched ones too), same policies and triggers, same shares, no business moved',
  (select md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace) = :'h_fn_before'
  and (select count(*) from pg_policies where policyname like '%m132') = :'n_pol_before'::int
  and (select count(*) from pg_trigger where tgname in ('a132_scope', 'stock_ledger_xbiz132', 'rules_m132')) = :'n_trg_before'::int
  and (select md5(string_agg(x::text, '|' order by x::text)) from (select table_name, row_key, from_org, to_org, status from master_shares132) x) = :'h_sh'
  and (select md5(string_agg(x::text, '|' order by x::text)) from (select id, mobile, org_unit_id from customers) x) = :'h_cust');
select tt.t('T9 the paste never writes the switch', rule_on('org_scope_on'));
update rules set value = null where key = 'org_scope_on';
select tt.t('T9 switch OFF again (value cleared)', not rule_on('org_scope_on'));
set role authenticated;
select tt.as(:'bs');
select tt.t('T9 OFF: a B salesperson reads every item and every customer again', (select count(*) from items) = (select count(*) from items where true) and (select count(*) from items where org_unit_id = :'sbz'::bigint) > 50
  and (select count(*) from customers where id = :'cust_a') = 1 and (select count(*) from option_lists where value_code = 'c2_a_only') = 1);
reset role;
select tt.t('T9 OFF: find_customer of an A mobile works for a B person; the guard is silent', (find_customer('01711000001') ->> 'found')::boolean
  and (customer_save(:'cust_a'::uuid, '{"note":"off-again"}'::jsonb, gen_random_uuid()) ->> 'id') = :'cust_a');
select tt.as(:'o');
select tt.t('T9 OFF: the stock guard is silent (an A item at a B place is accepted, as before the phase)', stock_opening(tt.iid('C2-A2'), :'hw2'::int, 1, 10) is not null);
select tt.t('T9 OFF: new rows are still tagged (so the switch can be turned ON later)', (select org_unit_id from customers where id = :'cust_a') = :'sbz'::bigint);
update rules set value = 'true'::jsonb where key = 'org_scope_on';
select tt.t('T9 ON again', rule_on('org_scope_on'));
set role authenticated;
select tt.as(:'bs');
select tt.eq('T9 ON again: the B salesperson is separated again (no sweets item visible)', 0, (select count(*) from items where org_unit_id = :'sbz'::bigint));
reset role;
select tt.as(:'o');

\echo == T10 uniqueness per business: preflight, relax (dry first), same mobile / code in two businesses, restore (LAST: the duplicates stay)
select tt.as(:'o');
select org_masters_preflight() as pf \gset
select tt.t('T10 preflight reads: switch on, not relaxed, 2 businesses, no row without business, scoped tables counted', (:'pf'::jsonb ->> 'switch_on')::boolean and not (:'pf'::jsonb ->> 'unique_relaxed')::boolean
  and (:'pf'::jsonb ->> 'businesses')::int = 2 and (:'pf'::jsonb -> 'rows_without_business') = '{}'::jsonb and (:'pf'::jsonb ->> 'scoped_tables')::int >= 34);
select tt.t('T10 preflight: all ten lookup functions are business aware', not exists (select 1 from jsonb_each(:'pf'::jsonb -> 'patched_functions') e where e.value <> 'true'::jsonb));
select tt.t('T10 preflight: no blocker; warnings only list the known report lookups', jsonb_array_length(:'pf'::jsonb -> 'blockers') = 0);
select tt.t('T10 preflight warns about the owner without a working business (2 businesses)', (:'pf'::jsonb -> 'warnings') ? 'owner_has_no_working_business');
select org_masters_relax_unique(true, false) as dry \gset
select tt.t('T10 relax dry-run: would apply, drops nothing', (:'dry'::jsonb ->> 'dry')::boolean and (:'dry'::jsonb ->> 'would_apply')::boolean and exists (select 1 from pg_constraint where conname = 'customers_mobile_key'));
select tt.err('T10 relax for real without acknowledging the warnings is refused', $$select org_masters_relax_unique(false, false)$$, 'warnings_need_ack');
select tt.as(:'bm');
select tt.err('T10 a B manager cannot relax', $$select org_masters_relax_unique(false, true)$$, 'not allowed');
select tt.err('T10 ... nor restore', $$select org_masters_restore_unique(false)$$, 'not allowed');
select tt.as(:'o');
select org_masters_relax_unique(false, true) as rx \gset
select tt.t('T10 relax applied: the three global uniques are gone and logged', (:'rx'::jsonb ->> 'relaxed')::boolean and not exists (select 1 from pg_constraint where conname in ('customers_mobile_key', 'items_code_key'))
  and to_regclass('public.items_barcode_uq') is null and (select count(*) from master_unique_log132 where action = 'relax') = 3);
select tt.is('T10 relax twice = dup, nothing more', (org_masters_relax_unique(false, true) ->> 'dup'), 'true');
select tt.err('T10 the switch cannot be turned OFF while the uniques are relaxed', $$update rules set value = 'false'::jsonb where key = 'org_scope_on'$$, 'masters_unique_relaxed_restore_first');
select tt.err('T10 ... also not by clearing the value', $$update rules set value = null where key = 'org_scope_on'$$, 'masters_unique_relaxed_restore_first');
-- restore while no duplicate exists, then relax again
select org_masters_restore_unique(true) as rd \gset
select tt.t('T10 restore dry-run: would restore (no duplicates yet)', (:'rd'::jsonb ->> 'would_restore')::boolean);
select org_masters_restore_unique(false) as rs \gset
select tt.t('T10 restore applied: the global uniques are back', exists (select 1 from pg_constraint where conname = 'customers_mobile_key') and exists (select 1 from pg_constraint where conname = 'items_code_key')
  and to_regclass('public.items_barcode_uq') is not null and not _m132_relaxed());
select org_masters_relax_unique(false, true) ->> 'relaxed' as rx2 \gset
select tt.t('T10 relaxed again', :'rx2'::boolean and _m132_relaxed());
-- the same mobile and the same item code in the second business
select tt.as(:'bs');
select record_sale2(gen_random_uuid(), :'hw1'::int, format('[{"item_id":"%s","qty":1,"price":500}]', tt.iid('C2-B1'))::jsonb, 0, '[{"mode":"cash","amount":500}]', '01711000001', 'Same Mobile B', 'retail', null, false) ->> 'id' as dsale \gset
select tt.t('T10 B sells to the SAME mobile as the A customer at hw1: a separate B customer is created (no error)', :'dsale' is not null and (select count(*) from customers where mobile like '%1711000001') = 2);
select tt.eq('T10 the A customer is untouched (name, business)', 1, (select count(*) from customers where mobile like '%1711000001' and name = 'A Customer' and org_unit_id = :'sbz'::bigint));
select find_customer('01711000001') ->> 'name' as fc_b \gset
select tt.as(:'ao');
select find_customer('01711000001') ->> 'name' as fc_a \gset
select tt.t('T10 find_customer by the shared mobile: B gets its own, A gets its own', :'fc_b' = 'Same Mobile B' and :'fc_a' = 'A Customer');
select tt.as(:'o');
select tt.t('T10 owner: find_customer picks the customer of the working business first (sweets by default)', (find_customer('01711000001') ->> 'name') = 'A Customer');
with ins as (insert into items (code,name_bn,name_en,unit,base_unit,item_type,sell_price,org_unit_id) values ('C2-A1','dup','Same code in B','pc','pc','finished_good',5,:'hbz'::bigint) returning 1) select count(*) as n_ins from ins \gset
select tt.t('T10 the same item code can exist in both businesses', :'n_ins'::int = 1);
select tt.err('T10 ... but not twice inside one business', format($q$insert into items (code,name_bn,name_en,unit,base_unit,item_type,sell_price,org_unit_id) values ('C2-A1','dup','again','pc','pc','finished_good',5,%s)$q$, :'hbz'), 'items_org_code_uq125');
select tt.err('T10 ... and a customer mobile twice inside one business is refused', format($q$insert into customers (mobile, name, org_unit_id) values ('01722000002', 'dup', %s)$q$, :'hbz'), 'customers_org_mobile_uq132');
with ins as (insert into items (code,name_bn,name_en,unit,base_unit,item_type,sell_price,barcode,org_unit_id) values ('C2-BC1','x','x','pc','pc','finished_good',1,'8800000000001',:'sbz'::bigint) returning 1) select count(*) as n_b1 from ins \gset
with ins as (insert into items (code,name_bn,name_en,unit,base_unit,item_type,sell_price,barcode,org_unit_id) values ('C2-BC2','x','x','pc','pc','finished_good',1,'8800000000001',:'hbz'::bigint) returning 1) select count(*) as n_b2 from ins \gset
select tt.t('T10 an item barcode can be reused across businesses, not inside one', :'n_b1'::int = 1 and :'n_b2'::int = 1 and tt.cnt(format($q$insert into items (code,name_bn,name_en,unit,base_unit,item_type,sell_price,barcode,org_unit_id) values ('C2-BC3','x','x','pc','pc','finished_good',1,'8800000000001',%s) returning 1$q$, :'hbz')) = -1);
select tt.t('T10 an entry-form style code lookup resolves inside the place business (the A copy at an A place, the B copy at a B place)',
  (select org_unit_id from items where code = 'C2-A1' and _m132_at(org_unit_id, 1)) = :'sbz'::bigint and (select org_unit_id from items where code = 'C2-A1' and _m132_at(org_unit_id, :'hw1'::int)) = :'hbz'::bigint);
select org_masters_restore_unique(true) as rd2 \gset
select tt.t('T10 restore is now blocked by the duplicates (and says how many)', not (:'rd2'::jsonb ->> 'would_restore')::boolean and (:'rd2'::jsonb ->> 'duplicate_mobiles')::int = 1 and (:'rd2'::jsonb ->> 'duplicate_codes')::int = 1 and (:'rd2'::jsonb ->> 'duplicate_barcodes')::int = 1);
select tt.err('T10 ... and the real restore raises', $$select org_masters_restore_unique(false)$$, 'duplicates_block_restore');
set role authenticated;
select tt.as(:'ao');
select tt.eq('T10 A direct select of the shared-code item: only its own (the B copy is invisible)', 1, (select count(*) from items where code = 'C2-A1'));
reset role;
select tt.as(:'o');

select tt.err('T10 OFF is refused while relaxed even for the owner (the old lookups assume one row per mobile / code)', $$update rules set value = 'false'::jsonb where key = 'org_scope_on'$$, 'masters_unique_relaxed_restore_first');

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
