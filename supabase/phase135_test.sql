-- FRESH DB ONLY (built through phase135 by tests/sql/final_build.sh). Phase 135 tests = places of a business created from the app, mapped to that business, and moved by the owner.
--   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase135_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
--   Two businesses: A = SWEETS (places 1..7, the original business) and D = a dealership 'DLR135' with two branch units, all created through the SAME functions the app calls
--   (org_unit_save + business_place_create135). Users: a_org (org_manage holder of A), d_org (org_manage holder of D), a_staff (plain salesperson of A), the owner.
\i tests/sql/e2e/00_common.sql
\set ON_ERROR_STOP off
\set ao  '00000000-0000-0000-0000-000000135a01'
\set aorg '00000000-0000-0000-0000-000000135a02'
\set dorg '00000000-0000-0000-0000-000000135d01'
\set dstf '00000000-0000-0000-0000-000000135d02'
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@t135.app','{"full_name":"Owner"}'),(:'ao','a_staff@t135.app','{"full_name":"A Staff"}'),(:'aorg','a_org@t135.app','{"full_name":"A Org"}'),
  (:'dorg','d_org@t135.app','{"full_name":"D Org"}'),(:'dstf','d_staff@t135.app','{"full_name":"D Staff"}');
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ao','salesperson'),(:'aorg','salesperson'),(:'dorg','salesperson'),(:'dstf','salesperson') on conflict do nothing;
insert into user_locations values (:'ao',1),(:'aorg',1) on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'aorg'::uuid, 'org_manage'), set_user_grant(:'dorg'::uuid, 'org_manage');
select id as sbz from org_units where code = 'SWEETS' \gset
select id as grp from org_units where kind = 'group' \gset

\echo == T0 fingerprint of the sweets business BEFORE anything is created for the second business
create or replace function tt.fp_sweets() returns text language sql stable security definer set search_path = public as $$
  select md5(
    coalesce((select string_agg(l.id || ':' || l.code || ':' || l.name_bn || ':' || coalesce(l.kind, '') || ':' || l.status || ':' || coalesce(l.org_unit_id::text, ''), '|' order by l.id) from public.locations l where l.id <= 7), '') || '#' ||
    coalesce((select string_agg(key || '=' || coalesce(value::text, '') || '/' || coalesce(default_value::text, ''), ',' order by key) from public.rules), '') || '#' ||
    (select count(*) from public.sales where location_id <= 7) || ',' || (select count(*) from public.stock_ledger where location_id <= 7) || ',' || (select count(*) from public.journal_entries where location_id <= 7) || '#' ||
    coalesce((select string_agg(location_id || ':' || step_no || ':' || done, ',' order by location_id, step_no) from public.location_setup_steps where location_id <= 7), '') || '#' ||
    coalesce((select string_agg(location_id || ':' || coalesce(key, '') , ',' order by location_id, key) from (select location_id, 'x' as key from public.location_settings where location_id <= 7) z), '') || '#' ||
    (select count(*) from public.settings_sheets where location_id <= 7) || '#' ||
    coalesce((select string_agg(u.code || ':' || u.status || ':' || u.name_en, ',' order by u.code) from public.org_units u where u.code in ('SWEETS', 'LE-SWEETS')), ''));
$$;
select tt.fp_sweets() as fp0 \gset
select count(*) as nloc0 from locations \gset

\echo == T1 the owner builds the second business exactly as the app does: legal entity, business, two branches, three places
select org_unit_save(null, :'grp'::bigint, 'legal_entity', 'LE-DLR135', 'ডিলারশিপ কোম্পানি', 'Dealer Company', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-000000135f01') ->> 'id' as dle \gset
select org_unit_save(null, :'dle'::bigint, 'business', 'DLR135', 'ডিলারশিপ ১৩৫', 'Dealership 135', 'dealership', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-000000135f02') ->> 'id' as dbz \gset
select org_unit_save(null, :'dbz'::bigint, 'branch', 'DLR135-N', 'উত্তর শাখা', 'North branch', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-000000135f03') ->> 'id' as dbn \gset
select org_unit_save(null, :'dbz'::bigint, 'branch', 'DLR135-S', 'দক্ষিণ শাখা', 'South branch', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-000000135f04') ->> 'id' as dbs \gset
select tt.t('T1 the new business has its profile at once (phase134 trigger)', exists (select 1 from business_profiles where org_unit_id = :'dbz'::bigint));
select business_place_create135(:'dbz'::bigint, 'showroom', 'north', 'উত্তর শো-রুম', 'Dealer North', :'dbn'::bigint, '00000000-0000-0000-0000-000000135c01') ->> 'id' as pn \gset
select business_place_create135(:'dbz'::bigint, 'branch', 'south', 'দক্ষিণ শো-রুম', 'Dealer South', :'dbs'::bigint, '00000000-0000-0000-0000-000000135c02') ->> 'id' as ps \gset
select business_place_create135(:'dbz'::bigint, 'warehouse', null, 'কেন্দ্রীয় গুদাম', 'Central Warehouse', null, '00000000-0000-0000-0000-000000135c03') ->> 'id' as pw \gset
select tt.is('T1 stored code = business prefix + code (north)', 'dlr135_north', (select code from locations where id = :'pn'::int));
select tt.is('T1 stored code (south)', 'dlr135_south', (select code from locations where id = :'ps'::int));
select tt.is('T1 no code given: made from the English name', 'dlr135_central_warehouse', (select code from locations where id = :'pw'::int));
select tt.is('T1 north is mapped to the NORTH BRANCH unit of the business', :'dbn', (select org_unit_id::text from locations where id = :'pn'::int));
select tt.is('T1 south is mapped to the south branch unit', :'dbs', (select org_unit_id::text from locations where id = :'ps'::int));
select tt.is('T1 the warehouse (no branch) is mapped to the business itself', :'dbz', (select org_unit_id::text from locations where id = :'pw'::int));
select tt.is('T1 kinds: showroom / branch alias -> showroom / warehouse alias -> godown', 'showroom,showroom,godown', (select string_agg(kind, ',' order by id) from locations where id in (:'pn'::int, :'ps'::int, :'pw'::int)));
select tt.is('T1 the new places start in setting_up (the status the pick-lists show)', 'setting_up,setting_up,setting_up', (select string_agg(status, ',' order by id) from locations where id in (:'pn'::int, :'ps'::int, :'pw'::int)));
select tt.is('T1 default model A (own place), active', 'A,A,A|true', (select string_agg(model, ',' order by id) from locations where id in (:'pn'::int, :'ps'::int, :'pw'::int)) || '|' || (select bool_and(is_active)::text from locations where id in (:'pn'::int, :'ps'::int, :'pw'::int)));
select tt.eq('T1 17 setup steps per new place (same path as the Places screen)', 51, (select count(*) from location_setup_steps where location_id in (:'pn'::int, :'ps'::int, :'pw'::int)));
select tt.eq('T1 step 2 (location code and a row in the list) is done with the place', 3, (select count(*) from location_setup_steps where location_id in (:'pn'::int, :'ps'::int, :'pw'::int) and step_no = 2 and done));
-- the place made by the old Places screen path (location_save) has the same defaults
select location_save(null, '{"name_bn":"পুরনো পথ","name_en":"Old path place","code":"oldpath135"}'::jsonb) ->> 'id' as pold \gset
select tt.is('T1 same defaults as the Places screen: model, kind, number of steps and settings sheets', (select model || '|' || kind || '|' || (select count(*) from location_setup_steps where location_id = l.id) || '|' || (select count(*) from settings_sheets where location_id = l.id) from locations l where id = :'pold'::int),
  (select model || '|' || kind || '|' || (select count(*) from location_setup_steps where location_id = l.id) || '|' || (select count(*) from settings_sheets where location_id = l.id) from locations l where id = :'pn'::int));
select tt.t('T1 the old path leaves the place UNMAPPED (this is the gap B1; the new function maps)', (select org_unit_id is null from locations where id = :'pold'::int));
select tt.is('T1 org_unit_scope of a new place: business DLR135, not SWEETS', 'DLR135', (org_unit_scope(:'pn'::int) ->> 'business_code'));
select tt.is('T1 the business list holds the three places', '3', (select count(*)::text from business_places_list135(:'dbz'::bigint)));
select tt.is('T1 audit: the creation is in the audit log', 'true', (select (count(*) >= 3)::text from audit_log where table_name = 'locations' and action = 'insert' and detail::text like '%dlr135_%'));
select tt.eq('T1 the ops table has 3 create rows', 3, (select count(*) from business_place_ops135 where op = 'create'));

\echo == T2 idempotency
select business_place_create135(:'dbz'::bigint, 'showroom', 'north', 'উত্তর শো-রুম', 'Dealer North', :'dbn'::bigint, '00000000-0000-0000-0000-000000135c01') ->> 'dup' as d1 \gset
select tt.is('T2 the same client key again = dup', 'true', :'d1');
select tt.eq('T2 ... no second place', 1, (select count(*) from locations where code like 'dlr135_north%'));
select tt.is('T2 ... and it returns the same place', :'pn', (business_place_create135(:'dbz'::bigint, 'showroom', 'north', 'x', 'x', null, '00000000-0000-0000-0000-000000135c01') ->> 'id'));
select tt.as(:'dorg');
select tt.err('T2 a user without the right is refused before the key is looked at', format('select business_place_create135(%L::bigint, ''showroom'', ''zz'', ''z'', ''z'', null, %L)', :'dbz', '00000000-0000-0000-0000-000000135c01'), 'not allowed');
select tt.as(:'o');

\echo == T3 validation: friendly codes
select tt.err('T3 bad kind', format('select business_place_create135(%L::bigint, ''castle'', ''x1'', ''a'', ''a'', null, gen_random_uuid())', :'dbz'), 'bad_kind');
select tt.err('T3 no kind', format('select business_place_create135(%L::bigint, null, ''x1'', ''a'', ''a'', null, gen_random_uuid())', :'dbz'), 'bad_kind');
select tt.err('T3 no name', format('select business_place_create135(%L::bigint, ''showroom'', ''x1'', null, ''  '', null, gen_random_uuid())', :'dbz'), 'name_required');
select tt.err('T3 bad code (capital letters and a space)', format('select business_place_create135(%L::bigint, ''showroom'', ''Bad Code'', ''a'', ''Place Q'', null, gen_random_uuid())', :'dbz'), 'bad_code');
select tt.err('T3 bad code (starts with a digit)', format('select business_place_create135(%L::bigint, ''showroom'', ''9abc'', ''a'', ''Place Q'', null, gen_random_uuid())', :'dbz'), 'bad_code');
select tt.err('T3 code already used in the business', format('select business_place_create135(%L::bigint, ''showroom'', ''north'', ''অন্য'', ''Another'', null, gen_random_uuid())', :'dbz'), 'code_in_use');
select tt.err('T3 code that starts with the prefix is not doubled: the stored code exists already', format('select business_place_create135(%L::bigint, ''showroom'', ''dlr135_north'', ''অন্য'', ''Another2'', null, gen_random_uuid())', :'dbz'), 'code_in_use');
select tt.err('T3 code too long once the prefix is added', format('select business_place_create135(%L::bigint, ''showroom'', %L, ''অন্য'', ''Another3'', null, gen_random_uuid())', :'dbz', 'abcdefghijklmnopqrstuvwxyz'), 'code_too_long');
select tt.err('T3 same name inside the business', format('select business_place_create135(%L::bigint, ''showroom'', ''north2'', ''অন্য'', ''dealer north'', null, gen_random_uuid())', :'dbz'), 'name_in_use');
select tt.err('T3 name too long', format('select business_place_create135(%L::bigint, ''showroom'', ''long1'', ''অন্য'', repeat(''x'', 121), null, gen_random_uuid())', :'dbz'), 'too_long');
select tt.err('T3 no client key', format('select business_place_create135(%L::bigint, ''showroom'', ''nk1'', ''অন্য'', ''No key'', null, null)', :'dbz'), 'client_id_needed');
select tt.err('T3 a branch unit of ANOTHER business is refused (the legal entity of A is not a branch either)', format('select business_place_create135(%L::bigint, ''showroom'', ''xb1'', ''অন্য'', ''Foreign branch'', %L::bigint, gen_random_uuid())', :'dbz', (select id from org_units where code = 'LE-SWEETS')), 'bad_branch');
select tt.err('T3 a missing branch unit', format('select business_place_create135(%L::bigint, ''showroom'', ''xb2'', ''অন্য'', ''Missing branch'', 999999, gen_random_uuid())', :'dbz'), 'bad_branch');
select tt.err('T3 the owner passing a branch as the business', format('select business_place_create135(%L::bigint, ''showroom'', ''xb3'', ''অন্য'', ''Not a business'', null, gen_random_uuid())', :'dbn'), 'unknown_business');
select tt.err('T3 the owner passing a missing business', 'select business_place_create135(999999::bigint, ''showroom'', ''xb4'', ''অন্য'', ''Missing business'', null, gen_random_uuid())', 'unknown_business');
select tt.eq('T3 nothing was created by the refused calls', 3, (select count(*) from locations where code like 'dlr135_%'));
-- an auto code is numbered when the name repeats in ANOTHER spelling
select business_place_create135(:'dbz'::bigint, 'online', null, 'অনলাইন', 'Dealer North Online', null, gen_random_uuid()) ->> 'code' as oc \gset
select tt.is('T3 auto code from the name', 'dlr135_dealer_north_online', :'oc');
select business_place_create135(:'dbz'::bigint, 'other', null, 'অনলাইন ২', 'Dealer North  Online', null, gen_random_uuid()) ->> 'code' as oc2 \gset
select tt.is('T3 a second place whose slug is taken gets a free number', 'dlr135_dealer_north_online_2', :'oc2');
select tt.err('T3 name check ignores letter case and spaces at the edges only (second spelling with two spaces is a different name: allowed above)', format('select business_place_create135(%L::bigint, ''other'', null, ''অনলাইন'', ''x'', null, gen_random_uuid())', :'dbz'), 'name_in_use');

\echo == T4 who may create: strict scope, switch OFF
select tt.as(:'aorg');
select tt.is('T4 the org_manage holder of A creates a place in A', 'true', (business_place_create135(:'sbz'::bigint, 'showroom', 'extra', 'অতিরিক্ত', 'Sweets Extra 135', null, gen_random_uuid()) ->> 'id' is not null)::text);
select tt.is('T4 ... it is mapped to A', :'sbz', (select org_unit_id::text from locations where code = 'sweets_extra'));
select tt.err('T4 ... but NOT in D', format('select business_place_create135(%L::bigint, ''showroom'', ''hack1'', ''a'', ''Hack One'', null, gen_random_uuid())', :'dbz'), 'not allowed');
select tt.err('T4 ... a missing business answers the same text', 'select business_place_create135(999999::bigint, ''showroom'', ''hack2'', ''a'', ''Hack Two'', null, gen_random_uuid())', 'not allowed');
select tt.err('T4 ... a branch of D cannot be borrowed for a place of A', format('select business_place_create135(%L::bigint, ''showroom'', ''hack3'', ''a'', ''Hack Three'', %L::bigint, gen_random_uuid())', :'sbz', :'dbn'), 'bad_branch');
select tt.err('T4 ... cannot list the places of D', format('select * from business_places_list135(%L::bigint)', :'dbz'), 'not allowed');
select tt.err('T4 ... cannot move a place', format('select business_place_move135(%L::int, %L::bigint, ''r135'', true)', :'pn', :'sbz'), 'not allowed');
select tt.err('T4 ... cannot ensure the profile of D', format('select business_profile_ensure135(%L::bigint)', :'dbz'), 'not allowed');
select tt.as(:'ao');
select tt.err('T4 a plain salesperson of A cannot create in A', format('select business_place_create135(%L::bigint, ''showroom'', ''hack4'', ''a'', ''Hack Four'', null, gen_random_uuid())', :'sbz'), 'not allowed');
select tt.err('T4 ... nor in D', format('select business_place_create135(%L::bigint, ''showroom'', ''hack5'', ''a'', ''Hack Five'', null, gen_random_uuid())', :'dbz'), 'not allowed');
-- the dealer manager needs a place of D to be "inside" D (phase134 rule): the owner gives him the new north place
select tt.as(:'o');
insert into user_locations values (:'dorg', :'pn'::int), (:'dstf', :'pn'::int) on conflict do nothing;
select tt.as(:'dorg');
select tt.is('T4 the org_manage holder of D creates a place in D', 'true', (business_place_create135(:'dbz'::bigint, 'showroom', 'extra', 'অতিরিক্ত', 'Dealer Extra 135', :'dbn'::bigint, gen_random_uuid()) ->> 'id' is not null)::text);
select tt.err('T4 the key of the owner used by the D manager is refused', format('select business_place_create135(%L::bigint, ''showroom'', ''zz'', ''z'', ''z'', null, %L)', :'dbz', '00000000-0000-0000-0000-000000135c01'), 'client_id_taken');
select tt.err('T4 ... but NOT in A', format('select business_place_create135(%L::bigint, ''showroom'', ''hack6'', ''a'', ''Hack Six'', null, gen_random_uuid())', :'sbz'), 'not allowed');
select tt.err('T4 ... a branch of D under A is refused too', format('select business_place_create135(%L::bigint, ''showroom'', ''hack7'', ''a'', ''Hack Seven'', %L::bigint, gen_random_uuid())', :'sbz', :'dbn'), 'not allowed');
select tt.eq('T4 ... lists the 6 places of D', 6, (select count(*) from business_places_list135(:'dbz'::bigint)));
select tt.err('T4 ... cannot list A', format('select * from business_places_list135(%L::bigint)', :'sbz'), 'not allowed');
select tt.err('T4 ... the group / legal entity is not a business to him', format('select business_place_create135(%L::bigint, ''showroom'', ''hack8'', ''a'', ''Hack Eight'', null, gen_random_uuid())', :'dle'), 'not allowed');
select tt.as(:'dstf');
select tt.err('T4 a plain salesperson of D cannot create', format('select business_place_create135(%L::bigint, ''showroom'', ''hack9'', ''a'', ''Hack Nine'', null, gen_random_uuid())', :'dbz'), 'not allowed');
select tt.is('T4 ... but may list the places of his own business (north)', 'true', (select (count(*) >= 1)::text from business_places_list135(:'dbz'::bigint)));
select tt.as(:'o');
select tt.is('T4 the same name may exist in another business: the owner creates "Dealer North" in A', 'true', (business_place_create135(:'sbz'::bigint, 'showroom', 'dealer_north', 'উত্তর', 'Dealer North', null, gen_random_uuid()) ->> 'id' is not null)::text);

\echo == T5 who sees what: the places belong to their own business only (switch ON)
update rules set value = 'true'::jsonb where key = 'org_scope_on';
select tt.as(:'aorg');
set role authenticated;
select tt.eq('T5 A manager reads no place of D (RLS)', 0, (select count(*) from locations where code like 'dlr135\_%'));
select tt.t('T5 ... and reads the places of A', (select count(*) >= 7 from locations where org_unit_id = :'sbz'::bigint));
reset role;
select tt.err('T5 org_unit_scope of a D place for A = not allowed', format('select org_unit_scope(%L::int)', :'pn'), 'not allowed');
select tt.is('T5 A manager can still create in A with the switch ON', 'true', (business_place_create135(:'sbz'::bigint, 'godown', 'store2', 'গুদাম', 'Sweets Store Two', null, gen_random_uuid()) ->> 'id' is not null)::text);
select tt.err('T5 ... and still cannot in D', format('select business_place_create135(%L::bigint, ''showroom'', ''hack10'', ''a'', ''Hack Ten'', null, gen_random_uuid())', :'dbz'), 'not allowed');
select tt.as(:'dorg');
set role authenticated;
select tt.eq('T5 D manager reads the place of D that is assigned to him', 1, (select count(*) from locations where code = 'dlr135_north'));
select tt.eq('T5 ... no place of A', 0, (select count(*) from locations where code like 'sweets\_%' or id <= 7));
reset role;
select tt.is('T5 ... org_unit_scope of his place names business DLR135', 'DLR135', (org_unit_scope(:'pn'::int) ->> 'business_code'));
select tt.err('T5 ... org_unit_scope of a place of A = not allowed', 'select org_unit_scope(1)', 'not allowed');
select tt.as(:'o');
select tt.is('T5 owner: org_unit_scope per place (D place / A place)', 'DLR135/SWEETS', (org_unit_scope(:'pn'::int) ->> 'business_code') || '/' || (org_unit_scope(1) ->> 'business_code'));
select tt.eq('T5 owner: the places of D (list)', 6, (select count(*) from business_places_list135(:'dbz'::bigint)));
select tt.is('T5 owner: list of A holds the new A places and none of D', 'true', (select (bool_and(code not like 'dlr135_%') and count(*) >= 9)::text from business_places_list135(:'sbz'::bigint)));
update rules set value = null where key = 'org_scope_on';

\echo == T6 the sweets business is unchanged by everything done for D (switch OFF fingerprint)
create or replace function tt.fp_sweets_after() returns text language sql stable security definer set search_path = public as $$
  select md5(
    coalesce((select string_agg(l.id || ':' || l.code || ':' || l.name_bn || ':' || coalesce(l.kind, '') || ':' || l.status || ':' || coalesce(l.org_unit_id::text, ''), '|' order by l.id) from public.locations l where l.id <= 7), '') || '#' ||
    coalesce((select string_agg(key || '=' || coalesce(value::text, '') || '/' || coalesce(default_value::text, ''), ',' order by key) from public.rules), '') || '#' ||
    (select count(*) from public.sales where location_id <= 7) || ',' || (select count(*) from public.stock_ledger where location_id <= 7) || ',' || (select count(*) from public.journal_entries where location_id <= 7) || '#' ||
    coalesce((select string_agg(location_id || ':' || step_no || ':' || done, ',' order by location_id, step_no) from public.location_setup_steps where location_id <= 7), '') || '#' ||
    coalesce((select string_agg(location_id || ':' || coalesce(key, '') , ',' order by location_id, key) from (select location_id, 'x' as key from public.location_settings where location_id <= 7) z), '') || '#' ||
    (select count(*) from public.settings_sheets where location_id <= 7) || '#' ||
    coalesce((select string_agg(u.code || ':' || u.status || ':' || u.name_en, ',' order by u.code) from public.org_units u where u.code in ('SWEETS', 'LE-SWEETS')), ''));
$$;
select tt.is('T6 sweets places 1..7, rules, sales / stock / journal counts, setup steps, settings, sheets, units: identical fingerprint', :'fp0', tt.fp_sweets_after());
select tt.is('T6 only the intended new rows exist (D places 6, A places 3 incl. the same-name one, old-path place 1, total +10)', (:'nloc0'::int + 10)::text, (select count(*)::text from locations));

\echo == T7 move: dry-run, force, blockers, owner only
insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('T135-X','x','Item X 135','pc','pc','finished_good',true,100,true) on conflict do nothing;
select id as it from items where code = 'T135-X' \gset
select tt.t('T7 an item exists for the stock test', :'it' <> '');
insert into stock_ledger (item_id, location_id, qty_delta, unit_cost, reason, ref_type) values (:'it'::uuid, :'ps'::int, 5, 10, 'opening', 'test135');
select business_place_move135(:'ps'::int, :'dbz'::bigint, 'same business', true) ->> 'same_business' as sm \gset
select tt.is('T7 dry-run to the same business: same_business true, nothing needed', 'true', :'sm');
select tt.is('T7 moving a place from its branch to the other branch of the SAME business works, even with transactions (no force)', 'false', (business_place_move135(:'ps'::int, :'dbz'::bigint, 'branch change', false, false, '00000000-0000-0000-0000-000000135e01', :'dbn'::bigint) ->> 'dup'));
select tt.is('T7 ... it now hangs on the north branch', :'dbn', (select org_unit_id::text from locations where id = :'ps'::int));
select business_place_move135(:'ps'::int, :'sbz'::bigint, null, true) as dry \gset
select tt.is('T7 dry-run to A: stock and transaction counted', '1|5.000|true', (:'dry'::jsonb ->> 'stock_items') || '|' || (:'dry'::jsonb ->> 'stock_qty') || '|' || ((:'dry'::jsonb ->> 'tx_total')::int >= 1)::text);
select tt.is('T7 dry-run: needs_force and cannot move without it', 'true|false', (:'dry'::jsonb ->> 'needs_force') || '|' || (:'dry'::jsonb ->> 'can_move'));
select tt.is('T7 dry-run lists the blocker place_has_transactions', 'place_has_transactions', (:'dry'::jsonb -> 'blockers' ->> 0));
select tt.is('T7 the dry-run wrote nothing (place still in D, no move row)', 'D|0', (case when public._business_of_unit123((select org_unit_id from locations where id = :'ps'::int)) = :'dbz'::bigint then 'D' else 'A' end) || '|' || (select count(*)::text from business_place_ops135 where op = 'move' and forced));
select tt.err('T7 real move without force is refused: the place has transactions', format('select business_place_move135(%L::int, %L::bigint, ''wrong business'', false, false, gen_random_uuid())', :'ps', :'sbz'), 'place_has_transactions');
select tt.err('T7 a reason is needed', format('select business_place_move135(%L::int, %L::bigint, ''  '', false, true, gen_random_uuid())', :'ps', :'sbz'), 'reason_required');
select tt.err('T7 a client key is needed', format('select business_place_move135(%L::int, %L::bigint, ''wrong business'', false, true, null)', :'ps', :'sbz'), 'client_id_needed');
-- people assigned: blocked also with force
insert into user_locations values (:'dstf', :'ps'::int) on conflict do nothing;
select tt.err('T7 people assigned: refused even with force', format('select business_place_move135(%L::int, %L::bigint, ''wrong business'', false, true, gen_random_uuid())', :'ps', :'sbz'), 'place_has_users');
select business_place_move135(:'ps'::int, :'sbz'::bigint, null, true) -> 'blockers' as bl \gset
select tt.t('T7 the dry-run names place_has_users', :'bl'::jsonb ? 'place_has_users');
delete from user_locations where user_id = :'dstf' and location_id = :'ps'::int;
-- an open document: blocked also with force
select business_place_create135(:'dbz'::bigint, 'showroom', 'docs', 'ডকুমেন্ট', 'Dealer Docs 135', null, gen_random_uuid()) ->> 'id' as pz \gset
insert into entries (form_code, location_id, serial, entry_date, status, created_by) values ((select code from forms order by code limit 1), :'pz'::int, 1, tt.today(), 'draft', :'o');
select tt.err('T7 an open document (draft entry): refused even with force', format('select business_place_move135(%L::int, %L::bigint, ''wrong business'', false, true, gen_random_uuid())', :'pz', :'sbz'), 'open_documents');
select business_place_move135(:'pz'::int, :'sbz'::bigint, null, true) -> 'blockers' as bl3 \gset
select tt.t('T7 the dry-run names open_documents', :'bl3'::jsonb ? 'open_documents');
-- not the owner
select tt.as(:'aorg');
select tt.err('T7 an org_manage holder of A cannot move a place into A', format('select business_place_move135(%L::int, %L::bigint, ''steal'', false, true, gen_random_uuid())', :'ps', :'sbz'), 'not allowed');
select tt.err('T7 ... not even a dry-run (impact of another business is not shown)', format('select business_place_move135(%L::int, %L::bigint, null, true)', :'ps', :'sbz'), 'not allowed');
select tt.as(:'dorg');
select tt.err('T7 the D manager cannot move his own place out', format('select business_place_move135(%L::int, %L::bigint, ''leave'', false, true, gen_random_uuid())', :'ps', :'sbz'), 'not allowed');
select tt.as(:'o');
select tt.err('T7 unknown place', format('select business_place_move135(999999, %L::bigint, ''r135'', true)', :'sbz'), 'unknown_location');
select tt.err('T7 unknown business', format('select business_place_move135(%L::int, 999999::bigint, ''r135'', true)', :'ps'), 'unknown_business');
select tt.err('T7 a branch is not a business', format('select business_place_move135(%L::int, %L::bigint, ''r135'', true)', :'ps', :'dbn'), 'unknown_business');
select tt.err('T7 a branch of D cannot be the target of a move into A', format('select business_place_move135(%L::int, %L::bigint, ''r135'', false, true, gen_random_uuid(), %L::bigint)', :'ps', :'sbz', :'dbn'), 'bad_branch');
-- the real move with force
select business_place_move135(:'ps'::int, :'sbz'::bigint, 'created in the wrong business', false, true, '00000000-0000-0000-0000-000000135e02') ->> 'dup' as mv \gset
select tt.is('T7 the forced move happened', 'false', :'mv');
select tt.is('T7 ... the place is now in A', 'SWEETS', (org_unit_scope(:'ps'::int) ->> 'business_code'));
select tt.is('T7 ... the move row holds who / why / forced / the impact', 'created in the wrong business|true|true', (select reason || '|' || forced::text || '|' || ((impact ->> 'tx_total')::int >= 1)::text from business_place_ops135 where client_id = '00000000-0000-0000-0000-000000135e02'));
select tt.is('T7 ... the move is in the audit log (locations update with org_unit_id)', 'true', (select (count(*) > 0)::text from audit_log where table_name = 'locations' and action = 'update' and record_id = :'ps' and detail::text like '%org_unit_id%'));
select tt.is('T7 repeating the same key = dup, nothing happens twice', 'true', (business_place_move135(:'ps'::int, :'sbz'::bigint, 'created in the wrong business', false, true, '00000000-0000-0000-0000-000000135e02') ->> 'dup'));
select tt.is('T7 moving to where it already is = noop', 'true', (business_place_move135(:'ps'::int, :'sbz'::bigint, 'again', false, true, gen_random_uuid()) ->> 'noop'));
select tt.eq('T7 exactly 2 move rows (branch change + forced move)', 2, (select count(*) from business_place_ops135 where op = 'move'));
select tt.err('T7 a move row cannot be changed', 'update business_place_ops135 set reason = ''x''', 'append_only');
select tt.err('T7 ... nor deleted', 'delete from business_place_ops135', 'append_only');
-- an unmapped place (the old path) can be mapped by the owner
select business_place_move135(:'pold'::int, :'dbz'::bigint, null, true) as dr2 \gset
select tt.is('T7 dry-run for an unmapped place: unmapped true, can move (no transactions)', 'true|true', (:'dr2'::jsonb ->> 'unmapped') || '|' || (:'dr2'::jsonb ->> 'can_move'));
select tt.is('T7 the owner maps the unmapped place into D', 'false', (business_place_move135(:'pold'::int, :'dbz'::bigint, 'map the old place', false, false, gen_random_uuid()) ->> 'dup'));
select tt.is('T7 ... it is in D now', 'DLR135', (org_unit_scope(:'pold'::int) ->> 'business_code'));
-- supply link across the border
update locations set supplied_by = :'pw'::int where id = :'pold'::int;
select business_place_move135(:'pold'::int, :'sbz'::bigint, null, true) -> 'blockers' as bl2 \gset
select tt.t('T7 a supply link inside D blocks a move out of D (dry-run says supply_link)', :'bl2'::jsonb ? 'supply_link');
select tt.err('T7 ... and the real move is refused', format('select business_place_move135(%L::int, %L::bigint, ''x135'', false, true, gen_random_uuid())', :'pold', :'sbz'), 'supply_link');
update locations set supplied_by = null where id = :'pold'::int;

\echo == T8 profile helper
select tt.is('T8 ensure on a business that has a profile = created false', 'false', (business_profile_ensure135(:'dbz'::bigint) ->> 'created'));
alter table org_units disable trigger bp_seed134;
select org_unit_save(null, :'dle'::bigint, 'business', 'DLR135-B', 'দ্বিতীয়', 'Second business 135', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid()) ->> 'id' as nb \gset
alter table org_units enable trigger bp_seed134;
select tt.eq('T8 the new business has no profile (trigger was off)', 0, (select count(*) from business_profiles where org_unit_id = :'nb'::bigint));
select tt.is('T8 ensure creates it from the unit names', 'true', (business_profile_ensure135(:'nb'::bigint) ->> 'created'));
select tt.is('T8 ... with the unit names', 'দ্বিতীয়|Second business 135', (select display_name_bn || '|' || display_name_en from business_profiles where org_unit_id = :'nb'::bigint));
select tt.is('T8 ... a second call changes nothing', 'false', (business_profile_ensure135(:'nb'::bigint) ->> 'created'));
select tt.err('T8 not a business', format('select business_profile_ensure135(%L::bigint)', :'dbn'), 'unknown_business');
select org_unit_deactivate(:'nb'::bigint, 'test done', gen_random_uuid());
select tt.err('T8 a place cannot be created in an inactive business', format('select business_place_create135(%L::bigint, ''showroom'', ''inact1'', ''a'', ''Inactive Place'', null, gen_random_uuid())', :'nb'), 'business_inactive');

\echo == T9 paste twice, privileges
select md5(pg_get_functiondef('public.location_save(integer,jsonb)'::regprocedure)) as h1 \gset
select count(*) as nloc1 from locations \gset
\i supabase/phase135.sql
select tt.is('T9 second paste: location_save body unchanged', :'h1', md5(pg_get_functiondef('public.location_save(integer,jsonb)'::regprocedure)));
select tt.eq('T9 second paste: no row added', :'nloc1', (select count(*) from locations));
select tt.eq('T9 the patched location_save carries the marker exactly once', 1, (length(pg_get_functiondef('public.location_save(integer,jsonb)'::regprocedure)) - length(replace(pg_get_functiondef('public.location_save(integer,jsonb)'::regprocedure), '/* loc135 */', ''))) / length('/* loc135 */'));
select tt.t('T9 anon cannot execute any of the new functions', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '135$' and has_function_privilege('anon', p.oid, 'execute')));
select tt.t('T9 the token helpers and the impact helper are closed to the browser', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_pc_ok135', '_pc_biz135', '_pc_unit135', '_place_impact135') and has_function_privilege('authenticated', p.oid, 'execute')));
select tt.t('T9 the browser role can execute the four public functions', (select count(*) = 4 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('business_place_create135', 'business_places_list135', 'business_place_move135', 'business_profile_ensure135') and has_function_privilege('authenticated', p.oid, 'execute')));
select tt.t('T9 RLS on the ops table; anon has no privilege', (select relrowsecurity from pg_class where oid = 'public.business_place_ops135'::regclass) and not has_table_privilege('anon', 'public.business_place_ops135', 'select'));
select tt.as(:'aorg');
set role authenticated;
do $$ declare n int; begin update public.locations set org_unit_id = null where id = 1; get diagnostics n = row_count; perform tt.t('T9 a business manager cannot re-map a place by a direct update (RLS: 0 rows)', n = 0); end $$;
select tt.err('T9 no direct write into the ops table', 'insert into public.business_place_ops135 (op, client_id, location_id, business_id) values (''create'', gen_random_uuid(), 1, 1)', 'permission denied');
select tt.eq('T9 the ops table is owner-read only: a manager reads 0 rows', 0, (select count(*) from public.business_place_ops135));
select tt.err('T9 the token cannot be forged from a plain call: location_save still refuses a plain user to add a place', 'select public.location_save(null, ''{"name_bn":"forged","code":"forged135"}''::jsonb)', 'not allowed');
select tt.err('T9 ... even after setting the setting himself (the token is bound to the transaction id of the call, and set_config is not exposed)', 'select set_config(''bos.pc135'', ''1'', true), public.location_save(null, ''{"name_bn":"forged2","code":"forged136"}''::jsonb)', 'not allowed');
reset role;
select tt.as(:'o');

\echo == RESULT
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.ea;
select 'FAIL ' || step || ' exp=' || coalesce(expected, '') || ' act=' || coalesce(actual, '') from tt.ea where not ok;
