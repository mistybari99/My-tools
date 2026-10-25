-- FRESH DB ONLY (built through phase134 by tests/sql/final_build.sh). Phase 134 tests = one profile per business + the upper layers invisible to the people of a business.
--   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase134_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root; ~10 minutes: two full leak sweeps)
--   Two businesses: A = SWEETS (places 1..7), B = HARDWARE renamed 'Zeta Hardware B134' (places hw1, hw2) - the c3 seed (tests/sql/c3_seed.sql), the same kinds of rows in each.
--   Users of A: a_staff (salesperson), a_mgr (management scope), a_super (every grant but org_manage), a_org (salesperson + the grant org_manage), plus m_multi (both businesses) and o_ops (notify / backup bot).
--   The leak sweep (tests/sql/leak134.sql) calls EVERY function the browser may execute and reads EVERY table / view it may select from, as each of those users, and looks for the group name, the legal
--   entities, the other business and its places in the answers and in the error texts; error texts for a foreign id and for a missing id must be equal (no existence oracle).
\i tests/sql/e2e/00_common.sql
\i tests/sql/c3_probe.sql
\i tests/sql/c3_seed.sql
\i tests/sql/leak134.sql
\echo == T0 setup: two businesses, users of each, an org_manage holder in each
select tt.as(:'o');
select c3.seed_data(1, 2, :'ao', 'A', :'sbz'::bigint)::text as ja \gset
select c3.seed_data(:'hw1'::int, :'hw2'::int, :'bo', 'B', :'hbz'::bigint)::text as jb \gset
\set aorg '00000000-0000-0000-0000-00000000134a'
\set borg '00000000-0000-0000-0000-00000000134b'
\set mb   '00000000-0000-0000-0000-00000000134c'
insert into auth.users (id,email,raw_user_meta_data) values (:'aorg','a_org@t134.app','{"full_name":"A Org"}'),(:'borg','b_org@t134.app','{"full_name":"B Org"}'),(:'mb','mb@t134.app','{"full_name":"Both"}');
update profiles set status='active';
insert into user_roles values (:'aorg','salesperson'),(:'borg','salesperson'),(:'mb','salesperson') on conflict do nothing;
insert into user_locations values (:'aorg',1),(:'borg',:'hw1'),(:'mb',1),(:'mb',:'hw1') on conflict do nothing;
select tt.as(:'o');
select set_user_grant(:'aorg'::uuid, 'org_manage'), set_user_grant(:'borg'::uuid, 'org_manage');
select group_id from (select id as group_id from org_units where kind = 'group') g \gset
select id as sle from org_units where code = 'LE-SWEETS' \gset
select tt.is('T0 the group unit is named MD-AL AMIN by the seed (it held the phase122 placeholder)', 'MD-AL AMIN|MD-AL AMIN', (select name_bn || '|' || name_en from org_units where id = :'group_id'::bigint));
-- B gets its own unique name, so that no template-catalogue text ('Hardware and paint') can look like a leak
select org_unit_save(:'hbz'::bigint, (select parent_id from org_units where id = :'hbz'::bigint), 'business', 'HARDWARE', 'জেটা হার্ডওয়্যার ১৩৪', 'Zeta Hardware B134', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null) ->> 'code' as bc \gset
update locations set name_en = 'Zeta Shop 1', name_bn = 'জেটা দোকান ১' where id = :'hw1'::int;
insert into c3.ids values ('persona_a_staff', :'ao'), ('persona_a_mgr', :'am'), ('persona_a_super', :'as'), ('persona_a_org', :'aorg'), ('persona_b_org', :'borg'), ('persona_o_ops', :'aop'), ('persona_m_multi', :'mb'),
  ('loc_a', '1'), ('biz_a', :'sbz'), ('loc_b', :'hw1'), ('biz_b', :'hbz'), ('cheque_b', '00000000-0000-0000-0000-00000000dead'), ('ship_b', '1');
insert into c3.ids select regexp_replace(k, '_B$', '_b'), v from jsonb_each_text(:'jb'::jsonb) e(k, v);

\echo == T1 the profile: seed, save, validation, idempotency, who may
select tt.as(:'o');
select tt.is('T1 the sweets profile carries the brand the app has always shown', 'ইসলামিয়া মিষ্টি ঘর|ISLAMIYA MISTY GHAR', (select display_name_bn || '|' || display_name_en from business_profiles where org_unit_id = :'sbz'::bigint));
select tt.eq('T1 every business has exactly one profile (2)', 2, (select count(*) from business_profiles));
select tt.is('T1 owner saves the profile of B (own name, address, colour, licence)', 'false', (business_profile_save(:'hbz'::bigint, '{"display_name_bn":"জেটা হার্ডওয়্যার ১৩৪","display_name_en":"Zeta Hardware B134","address":"Zeta Road 9","theme_color":"#336699","trade_licence_ref":"TL-B-77"}'::jsonb, '00000000-0000-0000-0000-000000134e01') ->> 'dup'));
select tt.is('T1 same client key again = dup, no second write', 'true', (business_profile_save(:'hbz'::bigint, '{"address":"CHANGED"}'::jsonb, '00000000-0000-0000-0000-000000134e01') ->> 'dup'));
select tt.is('T1 the replay changed nothing', 'Zeta Road 9', (select address from business_profiles where org_unit_id = :'hbz'::bigint));
select tt.as(:'aorg');
select tt.err('T1 the same key used by another user is refused', format('select business_profile_save(%L::bigint, ''{"address":"x"}''::jsonb, ''00000000-0000-0000-0000-000000134e01'')', :'sbz'), 'client_id_taken');
select tt.is('T1 the org_manage holder of A saves the profile of A', 'false', (business_profile_save(:'sbz'::bigint, '{"address":"Main road 1","phone":"01711-000000","email":"a@shop.test","receipt_header":"Welcome","receipt_footer":"Come again","trade_licence_ref":"TL-A-1"}'::jsonb, gen_random_uuid()) ->> 'dup'));
select tt.err('T1 ... but not the profile of B', format('select business_profile_save(%L::bigint, ''{"address":"x"}''::jsonb, gen_random_uuid())', :'hbz'), 'not allowed');
select tt.err('T1 ... a missing business answers the same', 'select business_profile_save(999999::bigint, ''{"address":"x"}''::jsonb, gen_random_uuid())', 'not allowed');
select tt.err('T1 bad colour', format('select business_profile_save(%L::bigint, ''{"theme_color":"red"}''::jsonb, gen_random_uuid())', :'sbz'), 'bad_color');
select tt.err('T1 bad email', format('select business_profile_save(%L::bigint, ''{"email":"nope"}''::jsonb, gen_random_uuid())', :'sbz'), 'bad_email');
select tt.err('T1 bad phone', format('select business_profile_save(%L::bigint, ''{"phone":"call me"}''::jsonb, gen_random_uuid())', :'sbz'), 'bad_phone');
select tt.err('T1 empty name', format('select business_profile_save(%L::bigint, ''{"display_name_bn":"  "}''::jsonb, gen_random_uuid())', :'sbz'), 'bad_name');
select tt.err('T1 name over 120', format('select business_profile_save(%L::bigint, jsonb_build_object(''display_name_en'', repeat(''x'', 121)), gen_random_uuid())', :'sbz'), 'bad_name');
select tt.err('T1 logo path with ..', format('select business_profile_save(%L::bigint, ''{"logo_path":"STOCK/../x.jpg"}''::jsonb, gen_random_uuid())', :'sbz'), 'bad_logo');
select tt.err('T1 unknown key', format('select business_profile_save(%L::bigint, ''{"owner_pct":5}''::jsonb, gen_random_uuid())', :'sbz'), 'bad_profile');
select tt.err('T1 no client key', format('select business_profile_save(%L::bigint, ''{"address":"x"}''::jsonb, null)', :'sbz'), 'client_id_needed');
select tt.is('T1 a logo path of the photos bucket is accepted', 'false', (business_profile_save(:'sbz'::bigint, '{"logo_path":"STOCK/1/logo-a.jpg","theme_color":"#a1111e"}'::jsonb, gen_random_uuid()) ->> 'dup'));
select tt.as(:'ao');
select tt.err('T1 a salesperson without the right cannot save', format('select business_profile_save(%L::bigint, ''{"address":"x"}''::jsonb, gen_random_uuid())', :'sbz'), 'not allowed');
select tt.is('T1 ... but reads the profile of his business (can_edit false)', 'false', (business_profile_get(null) ->> 'can_edit'));
select tt.is('T1 ... the licence is not in his copy', 'null', coalesce((business_profile_get(null) ->> 'trade_licence_ref'), 'null'));
select tt.is('T1 ... his profile name', 'ইসলামিয়া মিষ্টি ঘর', (business_profile_get(null) ->> 'display_name_bn'));
select tt.err('T1 a foreign business id = not allowed', format('select business_profile_get(%L::bigint)', :'hbz'), 'not allowed');
select tt.err('T1 a missing business id = the same text', 'select business_profile_get(999999::bigint)', 'not allowed');
select tt.eq('T1 the list holds his own business only (1)', 1, (select count(*) from business_profile_list134()));
select tt.as(:'aorg');
select tt.is('T1 the manager of A sees the licence of A', 'TL-A-1', (business_profile_get(null) ->> 'trade_licence_ref'));
select tt.as(:'o');
select tt.is('T1 the owner sees the licence of B', 'TL-B-77', (business_profile_get(:'hbz'::bigint) ->> 'trade_licence_ref'));
select tt.eq('T1 the owner list holds both businesses (2)', 2, (select count(*) from business_profile_list134()));
select tt.as(:'mb');
select tt.eq('T1 a user of both businesses lists 2', 2, (select count(*) from business_profile_list134()));
select tt.as(:'aorg');
set role authenticated;
select tt.err('T1 the licence column is not selectable by the browser', 'select trade_licence_ref from public.business_profiles', 'permission denied');
select tt.eq('T1 direct select: the manager of A sees 1 profile row (RLS)', 1, (select count(*) from public.business_profiles));
select tt.err('T1 no direct write', 'update public.business_profiles set address = ''x''', 'permission denied');
select tt.err('T1 the idempotency table is closed', 'select * from public.business_profile_ops134', 'permission denied');
reset role;
select tt.as(:'o');
select tt.is('T1 the profile change is in the audit log', 'true', (select (count(*) > 0)::text from audit_log where table_name = 'business_profiles'));
-- a new business unit gets its profile through the trigger
select org_unit_save(null, :'sle'::bigint, 'business', 'NEWBIZ134', 'নতুন ব্যবসা', 'New biz', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid()) ->> 'id' as nb \gset
select tt.is('T1 a new business has its profile at once (unit names)', 'নতুন ব্যবসা|New biz', (select display_name_bn || '|' || display_name_en from business_profiles where org_unit_id = :'nb'::bigint));
select org_unit_deactivate(:'nb'::bigint, 'test done', gen_random_uuid());

\echo == T2 the seed never overwrites a name the owner chose; paste twice
select org_unit_save(:'group_id'::bigint, null, 'group', null, 'OWNER CHOSEN', 'OWNER CHOSEN', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null);
update org_units set attrs = attrs - 'seed134' where id = :'group_id'::bigint;
select org_unit_save(:'group_id'::bigint, null, 'group', null, 'গ্রুপ', 'Group', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null);
update org_units set attrs = attrs - 'seed134' where id = :'group_id'::bigint;
\i supabase/phase134.sql
select tt.is('T2 a group that holds the placeholder and has no seed flag IS named by the seed (once)', 'MD-AL AMIN', (select name_en from org_units where id = :'group_id'::bigint));
select org_unit_save(:'group_id'::bigint, null, 'group', null, 'OWNER CHOSEN', 'OWNER CHOSEN', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null);
\i supabase/phase134.sql
select tt.is('T2 a name the owner chose is NOT overwritten by a second paste', 'OWNER CHOSEN', (select name_en from org_units where id = :'group_id'::bigint));
select tt.is('T2 the sweets profile is not overwritten either', 'ইসলামিয়া মিষ্টি ঘর', (select display_name_bn from business_profiles where org_unit_id = :'sbz'::bigint));
select org_unit_save(:'group_id'::bigint, null, 'group', null, 'MD-AL AMIN', 'MD-AL AMIN', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null);

\echo == T3 blindness with the switch ON: the tree, the scope, the lists
update rules set value = 'true'::jsonb where key = 'org_scope_on';
create or replace function tt.codes(p_uid text) returns text language plpgsql as $$
declare r text; begin perform set_config('request.jwt.claim.sub', p_uid, false); select coalesce(string_agg(code, ',' order by code collate "C"), '') into r from public.org_tree(); return r; end $$;
select tt.is('T3 owner tree (unchanged shape): group, both legal entities, both businesses, branches', 'GROUP,HARDWARE,HW-B1,LE-C3,LE-SWEETS,NEWBIZ134,SWEETS', tt.codes(:'o'));
select tt.is('T3 a_staff sees his business only, as the root', 'SWEETS', tt.codes(:'ao'));
select tt.is('T3 a_mgr (management scope) sees his business only', 'SWEETS', tt.codes(:'am'));
select tt.is('T3 a_org (org_manage) sees his business only: no group, no legal entity, no B', 'SWEETS', tt.codes(:'aorg'));
select tt.is('T3 b_org sees HARDWARE and its branch only', 'HARDWARE,HW-B1', tt.codes(:'borg'));
select tt.is('T3 m_multi (both businesses) sees both businesses, no group, no legal entity', 'HARDWARE,HW-B1,SWEETS', tt.codes(:'mb'));
select tt.as(:'aorg');
select tt.t('T3 the business row is the root: parent null, depth 0, path = its code', (select parent_id is null and depth = 0 and path = 'SWEETS' from org_tree() where kind = 'business'));
select tt.is('T3 the business row carries the profile name', 'ইসলামিয়া মিষ্টি ঘর|ISLAMIYA MISTY GHAR', (select name_bn || '|' || name_en from org_tree() where kind = 'business'));
select tt.t('T3 no owner percentage, no tax config, no fiscal start for a non-owner', (select bool_and(owner_pct is null and tax_cfg is null and fiscal_start is null) from org_tree()));
select tt.is('T3 the manager sees the licence of his business on the business row', 'TL-A-1', (select trade_licence_ref from org_tree() where kind = 'business'));
select tt.as(:'ao');
select tt.t('T3 a plain salesperson does not see the licence', (select trade_licence_ref is null from org_tree() where kind = 'business'));
select tt.as(:'o');
select tt.t('T3 the owner still sees the group row as the root', (select parent_id is null and name_en = 'MD-AL AMIN' from org_tree() where kind = 'group'));
select tt.is('T3 the owner sees the unit name (not the profile name) on the business row: unchanged', 'Sweets business', (select name_en from org_tree() where code = 'SWEETS'));
select tt.is('T3 org_unit_scope for the owner: legal entity and group named', 'LE-SWEETS|true|GROUP,LE-SWEETS,SWEETS', (select (r ->> 'legal_entity_code') || '|' || ((r ->> 'group_id') is not null)::text || '|' || (select string_agg(x, ',' order by x) from jsonb_array_elements_text(r -> 'path') x) from (select org_unit_scope(1) r) q));
select tt.as(:'ao');
select tt.is('T3 org_unit_scope for a_staff: business only, no legal entity, no group', 'SWEETS||false|SWEETS', (select (r ->> 'business_code') || '|' || coalesce(r ->> 'legal_entity_code', '') || '|' || ((r ->> 'group_id') is not null)::text || '|' || (select string_agg(x, ',') from jsonb_array_elements_text(r -> 'path') x) from (select org_unit_scope(1) r) q));
select tt.err('T3 org_unit_scope of a foreign place', format('select org_unit_scope(%s)', :'hw1'), 'not allowed');
select tt.err('T3 org_unit_scope of a missing place = the same text', 'select org_unit_scope(999999)', 'not allowed');
select tt.as(:'o');
select tt.err('T3 the owner still gets bad_location for a missing place', 'select org_unit_scope(999999)', 'bad_location');
-- scopes
select org_scope_grant(:'aorg'::uuid, :'sle'::bigint, 'salesperson', 'on the legal entity', gen_random_uuid()) ->> 'id' as lesc \gset
select tt.as(:'aorg');
select tt.t('T3 org_scope_list: a scope on the legal entity is shown without the unit', (select org_unit_id is null and unit_code is null from org_scope_list() where id = :'lesc'::bigint));
select tt.t('T3 org_scope_list for the manager of A names only scopes inside A', (select bool_and(unit_code = 'SWEETS' or unit_code is null) from org_scope_list()));
select tt.as(:'o');
select tt.t('T3 org_scope_list for the owner names the legal entity', (select unit_code = 'LE-SWEETS' from org_scope_list() where id = :'lesc'::bigint));
select tt.eq('T3 the owner sees the scopes of both businesses (at least 5 rows)', 1, (select (count(*) >= 5)::int from org_scope_list()));
select org_scope_revoke(:'lesc'::bigint, 'test done');
select tt.as(:'aorg');
select tt.t('T3 the manager of A does not see the scope rows of B users', (select count(*) = 0 from org_scope_list() where user_id in (:'bm'::uuid, :'bs'::uuid)));
-- shares / coverage report / context / digest / rule value: owner only, or no existence oracle
select tt.err('T3 master_share_list is owner only', 'select * from master_share_list()', 'not allowed');
select tt.err('T3 master_scope_report132 is owner only', 'select * from master_scope_report132()', 'not allowed');
select tt.err('T3 master_context_set132 with a foreign business', format('select master_context_set132(%L::bigint)', :'hbz'), 'not allowed');
select tt.err('T3 ... a missing business: the same text', 'select master_context_set132(999999::bigint)', 'not allowed');
select tt.as(:'am');
select tt.err('T3 daily_digest_biz133 foreign business', format('select daily_digest_biz133(%L::bigint)', :'hbz'), 'not allowed');
select tt.err('T3 ... missing business: the same text', 'select daily_digest_biz133(999999::bigint)', 'not allowed');
select tt.err('T3 rule_val_in133 foreign business', format('select rule_val_in133(''reports_net_of_returns'', %L::bigint)', :'hbz'), 'not allowed');
select tt.err('T3 ... missing business: the same text', 'select rule_val_in133(''reports_net_of_returns'', 999999::bigint)', 'not allowed');
select tt.as(:'o');
select tt.t('T3 the owner reads master_share_list and the report', (select count(*) >= 0 from master_share_list()) and (select count(*) > 10 from master_scope_report132()));
select tt.is('T3 import-export helper still finds the base currency of a business', 'BDT', _ie_base124(:'sbz'::bigint));
-- structure by a business manager
select tt.as(:'aorg');
select org_unit_save(null, :'sbz'::bigint, 'branch', 'x1', 'শাখা এক্স', 'Branch X', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid()) ->> 'code' as xcode \gset
select tt.is('T3 the manager creates a branch inside A: the code is namespaced by the business code', 'SWEETS-X1', :'xcode');
select org_unit_save(null, :'sbz'::bigint, 'branch', 'SWEETS-X2', 'শাখা ২', 'Branch X2', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid()) ->> 'id' as x2 \gset
select tt.err('T3 a branch under B is refused like a missing parent', format('select org_unit_save(null, %L::bigint, ''branch'', ''zz'', ''z'', ''z'', null, null, null, null, ''BDT'', ''Asia/Dhaka'', ''{}''::jsonb, null, gen_random_uuid())', :'hbz'), 'bad_parent');
select tt.err('T3 ... a missing parent: the same text', 'select org_unit_save(null, 999999::bigint, ''branch'', ''zz'', ''z'', ''z'', null, null, null, null, ''BDT'', ''Asia/Dhaka'', ''{}''::jsonb, null, gen_random_uuid())', 'bad_parent');
select tt.err('T3 a business cannot be created by a business manager', format('select org_unit_save(null, %L::bigint, ''business'', ''nb'', ''n'', ''n'', null, null, null, null, ''BDT'', ''Asia/Dhaka'', ''{}''::jsonb, null, gen_random_uuid())', :'sle'), 'not allowed');
select tt.err('T3 a unit of B cannot be changed: unit_not_found', format('select org_unit_save(%L::bigint, %L::bigint, ''branch'', null, ''q'', ''q'', null, null, null, null, ''BDT'', ''Asia/Dhaka'', ''{}''::jsonb, null, null)', (select id from org_units where code = 'HW-B1'), :'hbz'), 'unit_not_found');
select tt.err('T3 ... a missing unit: the same text', format('select org_unit_save(999999::bigint, %L::bigint, ''branch'', null, ''q'', ''q'', null, null, null, null, ''BDT'', ''Asia/Dhaka'', ''{}''::jsonb, null, null)', :'sbz'), 'unit_not_found');
select tt.err('T3 the business unit itself is the owner''s (profile is the way)', format('select org_unit_save(%L::bigint, %L::bigint, ''business'', null, ''q'', ''q'', null, null, null, null, ''BDT'', ''Asia/Dhaka'', ''{}''::jsonb, null, null)', :'sbz', :'sle'), 'not allowed');
select tt.err('T3 deactivate a unit of B', format('select org_unit_deactivate(%L::bigint, ''x'', gen_random_uuid())', (select id from org_units where code = 'HW-B1')), 'unit_not_found');
select tt.err('T3 ... a missing unit: the same text', 'select org_unit_deactivate(999999::bigint, ''x'', gen_random_uuid())', 'unit_not_found');
select tt.err('T3 the business itself cannot be deactivated by a manager', format('select org_unit_deactivate(%L::bigint, ''x'', gen_random_uuid())', :'sbz'), 'not allowed');
select tt.is('T3 the manager deactivates his own branch', 'false', (org_unit_deactivate(:'x2'::bigint, 'not needed', gen_random_uuid()) ->> 'dup'));
select tt.as(:'ao');
select tt.err('T3 a salesperson without org_manage cannot create a unit', format('select org_unit_save(null, %L::bigint, ''branch'', ''q1'', ''q'', ''q'', null, null, null, null, ''BDT'', ''Asia/Dhaka'', ''{}''::jsonb, null, gen_random_uuid())', :'sbz'), 'not allowed');
-- direct reads
select tt.as(:'aorg');
set role authenticated;
select tt.eq('T3 direct select org_units as the manager of A: only A and below (SWEETS, SWEETS-X1, SWEETS-X2 = 3)', 3, (select count(*) from public.org_units));
select tt.eq('T3 no group / legal entity row among them', 0, (select count(*) from public.org_units where kind in ('group', 'legal_entity')));
select tt.eq('T3 legal_entities: nothing', 0, (select count(*) from public.legal_entities));
select tt.eq('T3 master_shares132: nothing', 0, (select count(*) from public.master_shares132));
select tt.t('T3 user_org_scopes: no row of a unit above A, none of B', (select count(*) = 0 from public.user_org_scopes where org_unit_id in (:'sle'::bigint, :'hbz'::bigint)));
reset role;
select tt.as(:'ao');
set role authenticated;
select tt.eq('T3 a plain salesperson reads no org_units row directly', 0, (select count(*) from public.org_units));
reset role;

\echo == T4 the leak sweep with the switch ON (every function, every readable table, every persona)
select tt.as(:'o');
insert into l134.tokens (grp, token, cs) values
  ('A', 'MD-AL AMIN', false), ('A', '"GROUP"', true), ('A', 'LE-SWEETS', true), ('A', 'LE-C3', false), ('A', 'Sweets business (legal entity)', false), ('A', 'প্রতিষ্ঠান)', false),
  ('A', 'Zeta', false), ('A', 'জেটা', false), ('A', 'HARDWARE', true), ('A', 'HW-B1', false), ('A', 'Hardware Co', false), ('A', 'হার্ডওয়্যার কোম্পানি', false), ('A', 'Branch 1', false),
  ('B', 'MD-AL AMIN', false), ('B', '"GROUP"', true), ('B', 'LE-SWEETS', true), ('B', 'LE-C3', false), ('B', 'Sweets business (legal entity)', false);
update rules set value = 'true'::jsonb where key = 'org_scope_on';
set role authenticated;
select l134.scan_fn('ON');
select l134.scan_tables('ON');
reset role;
select tt.t('T4 the sweep ran (more than 8000 function answers and 1000 table reads)', (select count(*) filter (where kind = 'fn') > 8000 and count(*) filter (where kind = 'tbl') > 1000 from l134.probe where snap = 'ON'));
select tt.eq('T4 ON: no forbidden token in any answer or error text of the business people (a_staff, a_mgr, a_super, a_org, b_org)', 0, (select count(*) from l134.hits where snap = 'ON'));
select tt.eq('T4 ON: a foreign id and a missing id give the same error text (no existence oracle)', 0, (select count(*) from l134.errdiff where snap = 'ON' and persona like 'a\_%'));
select tt.t('T4 the sweep is able to see a leak: the owner-like persona m_multi legitimately sees B (control)', (select count(*) > 0 from l134.probe p where p.snap = 'ON' and p.persona = 'm_multi' and p.txt like '%Zeta%'));

\echo == T5 the same with the switch OFF (the group and the legal entities are hidden in both states; one business is then every user's business)
update rules set value = 'false'::jsonb where key = 'org_scope_on';
select tt.is('T5 OFF: a_staff tree', 'SWEETS', tt.codes(:'ao'));
select tt.is('T5 OFF: the org_manage holder sees his business and what is inside it, no group', 'SWEETS,SWEETS-X1,SWEETS-X2', tt.codes(:'aorg'));
select tt.as(:'o');
select tt.is('T5 OFF: the owner tree is unchanged (everything, incl. the units made above)', 'GROUP,HARDWARE,HW-B1,LE-C3,LE-SWEETS,NEWBIZ134,SWEETS,SWEETS-X1,SWEETS-X2', tt.codes(:'o'));
delete from l134.tokens;
insert into l134.tokens (grp, token, cs) values ('A', 'MD-AL AMIN', false), ('A', '"GROUP"', true), ('A', 'LE-SWEETS', true), ('A', 'LE-C3', false), ('A', 'Sweets business (legal entity)', false), ('A', 'প্রতিষ্ঠান)', false),
  ('B', 'MD-AL AMIN', false), ('B', '"GROUP"', true), ('B', 'LE-SWEETS', true), ('B', 'LE-C3', false), ('B', 'Sweets business (legal entity)', false);
set role authenticated;
select l134.scan_fn('OFF');
select l134.scan_tables('OFF');
reset role;
select tt.eq('T5 OFF: no group name / legal entity in any answer or error text of the business people', 0, (select count(*) from l134.hits where snap = 'OFF'));

\echo == T6 privileges
select tt.t('T6 anon cannot execute the new functions', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '(134|_vis_biz|_unit_mgr|_unit_vis|_biz_mgr|_grp_owner|_cur_biz)' and has_function_privilege('anon', p.oid, 'execute')));
select tt.t('T6 the helpers are closed to the browser except the three policy helpers', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_grp_owner134', '_biz_mgr134', '_cur_biz134', '_bp_json134', '_bp_seed134', '_bp_kind_check134') and has_function_privilege('authenticated', p.oid, 'execute')));
select tt.t('T6 anon has no table privilege on the new tables', not has_table_privilege('anon', 'public.business_profiles', 'select') and not has_table_privilege('anon', 'public.business_profile_ops134', 'select'));
select tt.t('T6 RLS is on for both new tables', (select bool_and(relrowsecurity) from pg_class where oid in ('public.business_profiles'::regclass, 'public.business_profile_ops134'::regclass)));
select tt.t('T6 no business profile is ever hard deleted', (select count(*) = 2 from pg_trigger where tgname in ('bp134_no_delete', 'bpo134_no_delete')));

\echo == RESULT
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.ea;
select 'FAIL ' || step || ' exp=' || coalesce(expected, '') || ' act=' || coalesce(actual, '') from tt.ea where not ok;
