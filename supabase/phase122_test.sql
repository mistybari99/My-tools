-- FRESH DB ONLY (built through phase121, then phase122). Phase 122 tests = Group ERP Stage B1 (organization layer, additive, zero behaviour change).
--   bash tests/sql/final_build.sh <db>   (the canonical order ends with phase122);  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase122_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
--   The "sweets report totals unchanged" proof on seeded data is tests/sql/b1_before_after.sh (needs a build WITHOUT phase122); here the same idea runs around the second paste.
\i tests/sql/e2e/00_common.sql
\set ma '00000000-0000-0000-0000-000000000010'
\set fm2 '00000000-0000-0000-0000-000000000031'
\echo == T0 shape
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@b6.app','{"full_name":"Owner"}'),(:'fm','maker@b6.app','{"full_name":"Maker"}'),(:'sp','seller@b6.app','{"full_name":"Seller"}'),(:'ma','showroom@b6.app','{"full_name":"Showroom"}'),(:'fm2','orgmgr@b6.app','{"full_name":"OrgMgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'fm','factory_incharge'),(:'sp','salesperson'),(:'ma','showroom_manager'),(:'fm2','salesperson') on conflict do nothing;
insert into user_locations values (:'fm',1),(:'sp',1),(:'ma',1),(:'ma',2),(:'fm2',1) on conflict do nothing;
select tt.as(:'o');
select tt.t('T0 the three tables exist with RLS on', (select count(*) = 3 and bool_and(relrowsecurity) from pg_class where oid in ('public.org_units'::regclass, 'public.legal_entities'::regclass, 'public.business_templates'::regclass)));
select tt.t('T0 anon / public have no privilege on them, the browser role cannot write', not has_table_privilege('anon', 'public.org_units', 'select') and not has_table_privilege('anon', 'public.legal_entities', 'select')
  and not has_table_privilege('anon', 'public.business_templates', 'select')
  and not (has_table_privilege('authenticated', 'public.org_units', 'insert') or has_table_privilege('authenticated', 'public.org_units', 'update') or has_table_privilege('authenticated', 'public.org_units', 'delete'))
  and not (has_table_privilege('authenticated', 'public.legal_entities', 'insert') or has_table_privilege('authenticated', 'public.legal_entities', 'update'))
  and not (has_table_privilege('authenticated', 'public.business_templates', 'insert') or has_table_privilege('authenticated', 'public.business_templates', 'update'))
  and not has_sequence_privilege('authenticated', 'public.org_units_id_seq', 'usage'));
select tt.t('T0 audit trigger and no-delete trigger on every new table', (select count(*) = 6 from pg_trigger where not tgisinternal and tgrelid in ('public.org_units'::regclass, 'public.legal_entities'::regclass, 'public.business_templates'::regclass)
  and (tgname ~ '^audit_' or tgname ~ '_no_delete$')));
select tt.t('T0 locations.org_unit_id exists and is nullable', (select is_nullable = 'YES' from information_schema.columns where table_name = 'locations' and column_name = 'org_unit_id'));
select tt.t('T0 helper functions are closed to the browser role and to anon', not has_function_privilege('authenticated', 'public._org_mgr122()', 'execute') and not has_function_privilege('anon', 'public._org_mgr122()', 'execute')
  and not has_function_privilege('authenticated', 'public._org_visible122()', 'execute') and not has_function_privilege('authenticated', 'public._org_parent_ok122(text,text)', 'execute'));

\echo == T1 seed: one group, one legal entity, one business, every sweets location mapped
select tt.eq('T1 exactly one group', 1, (select count(*) from org_units where kind = 'group'));
select tt.eq('T1 one legal entity LE-SWEETS under the group', 1, (select count(*) from org_units u join org_units g on g.id = u.parent_id and g.kind = 'group' where u.code = 'LE-SWEETS' and u.kind = 'legal_entity'));
select tt.eq('T1 one business SWEETS under the legal entity, template food_manufacturing', 1, (select count(*) from org_units b join org_units l on l.id = b.parent_id and l.code = 'LE-SWEETS' where b.code = 'SWEETS' and b.kind = 'business' and b.template_code = 'food_manufacturing'));
select tt.eq('T1 the legal entity row exists: owner_pct 100, licence not invented (null)', 1, (select count(*) from legal_entities le join org_units u on u.id = le.org_unit_id where u.code = 'LE-SWEETS' and le.owner_pct = 100 and le.trade_licence_ref is null and le.base_currency = 'BDT'));
select tt.eq('T1 the 7 existing locations are all mapped to SWEETS', 7, (select count(*) from locations l join org_units b on b.id = l.org_unit_id and b.code = 'SWEETS'));
select tt.eq('T1 no location is left unmapped', 0, (select count(*) from locations where org_unit_id is null));
select tt.is('T1 food_manufacturing = available', 'available', (select status from business_templates where code = 'food_manufacturing'));
select tt.eq('T1 the five other industries = not_implemented', 5, (select count(*) from business_templates where code in ('dealership', 'hardware_paint', 'technology', 'construction', 'online_store') and status = 'not_implemented'));
select tt.t('T1 org_manage is a known grant', exists (select 1 from grant_defs where grant_code = 'org_manage'));

\echo == T2 zero behaviour change
select tt.t('T2 org_scope_on exists, is a switch and is OFF', (select kind = 'switch' and default_value = 'false'::jsonb from rules where key = 'org_scope_on') and not rule_on('org_scope_on'));
select tt.t('T2 can_loc is untouched: it knows nothing about the organization layer', to_regprocedure('public.can_scope(bigint,text)') is not null or pg_get_functiondef('public.can_loc'::regproc) !~* 'org_');   -- from phase123 on can_loc reads the layer by design (phase123_test covers it)
select tt.t('T2 no existing function or policy refers to the new objects', to_regprocedure('public.can_scope(bigint,text)') is not null or not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname !~ '(^org_|^_org_|^_le_kind_check122$|^_biz_|^_my_biz125$|^_var_gate125$|^_items_org125$|^option_|^style_save$|^variants_|^variant_matrix$|^my_businesses125$|^price_list|^price_for125$|^items_search)' and p.prosrc ~* 'org_units|org_scope|legal_entities|business_templates')
  and not exists (select 1 from pg_policies where schemaname = 'public' and tablename not in ('org_units', 'legal_entities', 'business_templates', 'items', 'option_sets', 'option_values', 'item_styles', 'style_axes', 'price_lists', 'price_list_items') and (qual ~* 'org_unit' or with_check ~* 'org_unit')));
create temp table h0 as select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname !~ '(^org_|^_org_|^_le_kind_check122$|^_biz_|^_my_biz125$|^_var_gate125$|^_items_org125$|^option_|^style_save$|^variants_|^variant_matrix$|^my_businesses125$|^price_list|^price_for125$|^items_search)';
create temp table k0 as select (select count(*) from rules) rules_n, (select count(*) from grant_defs) gd_n, (select count(*) from setup_rec_defs81) adv_n, (select count(*) from locations) loc_n,
  (select count(*) from org_units) ou_n, (select count(*) from legal_entities) le_n, (select count(*) from business_templates) bt_n,
  (select md5(string_agg(to_jsonb(u)::text, '|' order by id)) from org_units u) ou_h, (select md5(string_agg(to_jsonb(l)::text, '|' order by id)) from locations l) loc_h,
  (select md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r) rules_h, (select md5(acct_trial_balance(null, null)::text)) tb_h;

\echo == T3 a second business with branches, created through the functions (no code change)
select org_unit_save(null, (select id from org_units where kind = 'group'), 'legal_entity', 'le-hw', 'হার্ডওয়্যার কোম্পানি', 'Hardware Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb,
  '{"trade_licence_ref":"TL-HW-001","owner_pct":60,"fiscal_start":"2025-07-01"}'::jsonb, '00000000-0000-0000-0000-0000000000a1') ->> 'id' as hle \gset
select org_unit_save(null, :'hle'::bigint, 'business', 'HARDWARE', 'হার্ডওয়্যার ও রং', 'Hardware and paint', 'hardware_paint', 'planned', null, null, 'BDT', 'Asia/Dhaka', '{"note":"x"}'::jsonb, null, '00000000-0000-0000-0000-0000000000a2') ->> 'id' as hbz \gset
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B1', 'শাখা ১', 'Branch 1', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000a3') ->> 'id' as hb1 \gset
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B2', 'শাখা ২', 'Branch 2', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000a4') ->> 'id' as hb2 \gset
select org_unit_save(null, :'hb1'::bigint, 'department', 'HW-B1-D1', 'বিক্রয়', 'Sales', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000a5') ->> 'id' as hd1 \gset
select tt.eq('T3 the second business has its own 2 branches and they hang under it, not under SWEETS', 2, (select count(*) from org_units where kind = 'branch' and parent_id = :'hbz'::bigint));
select tt.eq('T3 SWEETS is unchanged: no child unit', 0, (select count(*) from org_units where parent_id = (select id from org_units where code = 'SWEETS')));
select tt.t('T3 code is stored in upper case; legal entity details saved (licence, owner_pct 60, fiscal start)', exists (select 1 from legal_entities le join org_units u on u.id = le.org_unit_id
  where u.code = 'LE-HW' and le.trade_licence_ref = 'TL-HW-001' and le.owner_pct = 60 and le.fiscal_start = date '2025-07-01'));
select tt.eq('T3 org_tree shows 5 more units (8 in all), depth of the department is 4', 4, (select depth from org_tree() where code = 'HW-B1-D1'));
select tt.eq('T3 org_tree total', 8, (select count(*) from org_tree()));
select tt.is('T3 the new business is a not_implemented template: shown as such, not as ready', 'not_implemented', (select template_status from org_tree() where code = 'HARDWARE'));
select tt.is('T3 org_unit_scope of a mapped sweets location names the sweets business and the group', 'SWEETS/LE-SWEETS', (select org_unit_scope(1)->>'business_code' || '/' || (org_unit_scope(1)->>'legal_entity_code')));
select tt.t('T3 ... and the group id', (org_unit_scope(1)->>'group_id')::bigint = (select id from org_units where kind = 'group'));
select org_unit_save(:'hbz'::bigint, :'hle'::bigint, null, null, 'হার্ডওয়্যার ও রং', 'Hardware & Paint', 'hardware_paint', null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null) ->> 'dup' as upd \gset
select tt.is('T3 an update is not a duplicate', 'false', :'upd');
select tt.is('T3 the new name is stored', 'Hardware & Paint', (select name_en from org_units where id = :'hbz'::bigint));
select tt.is('T3 a planned status is kept by an update that passes none', 'planned', (select status from org_units where id = :'hbz'::bigint));
select tt.t('T3 every create wrote an audit row', (select count(*) >= 5 from audit_log where table_name = 'org_units' and action = 'insert'));

\echo == T4 idempotency key
select org_unit_save(null, :'hbz'::bigint, 'branch', 'HW-B1', 'শাখা ১', 'Branch 1', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000a3') as again \gset
select tt.t('T4 same key again: dup = true and the same id, no second row', (:'again'::jsonb->>'dup')::boolean and (:'again'::jsonb->>'id')::bigint = :'hb1'::bigint);
select tt.eq('T4 still one HW-B1', 1, (select count(*) from org_units where code = 'HW-B1'));
select tt.err('T4 a create without key is refused', $$select org_unit_save(null, (select id from org_units where code = 'HARDWARE'), 'branch', 'HW-B9', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)$$, 'client_id_needed');
select tt.err('T4 another user cannot reuse the key (refused)', format($q$select tt.as(%L); select org_unit_save(null, %s, 'branch', 'HW-B3', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000000a3')$q$, :'fm2', :'hbz'), 'not allowed');
select tt.as(:'o');

\echo == T5 validation
select tt.err('T5 a second group is refused', $$select org_unit_save(null, 1, 'group', 'G2', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_kind');
select tt.err('T5 unknown kind', $$select org_unit_save(null, 1, 'shop', 'ZZ1', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_kind');
select tt.err('T5 bad code', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'a b', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_code');
select tt.err('T5 duplicate code', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'hw-b2', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'code_taken');
select tt.err('T5 a branch cannot sit under the group', $$select org_unit_save(null, (select id from org_units where kind='group'), 'branch', 'ZZ2', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_parent_kind');
select tt.err('T5 unknown parent', $$select org_unit_save(null, 999999, 'branch', 'ZZ3', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_parent');
select tt.err('T5 a template only on a business', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ4', 'x', null, 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'template_only_for_business');
select tt.err('T5 unknown template', $$select org_unit_save(null, (select id from org_units where code='LE-HW'), 'business', 'ZZ5', 'x', null, 'nope', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_template');
select tt.err('T5 bad currency', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ6', 'x', null, null, 'active', null, null, 'taka1', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_currency');
select tt.err('T5 bad time zone', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ7', 'x', null, null, 'active', null, null, 'BDT', 'Mars/Base', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_tz');
select tt.err('T5 end before start', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ8', 'x', null, null, 'active', date '2025-02-01', date '2025-01-01', 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_date');
select tt.err('T5 empty name', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ9', '  ', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_name');
select tt.err('T5 inactive is not a status you can set by save', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ10', 'x', null, null, 'inactive', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'bad_status');
select tt.err('T5 attrs must be an object', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ11', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '[1]'::jsonb, null, gen_random_uuid())$$, 'bad_attrs');
select tt.err('T5 owner_pct above 100', $$select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'LE-X', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":150}'::jsonb, gen_random_uuid())$$, 'bad_owner_pct');
select tt.err('T5 owner_pct below 0', $$select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'LE-X', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":-1}'::jsonb, gen_random_uuid())$$, 'bad_owner_pct');
select tt.err('T5 unknown legal-entity key', $$select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'LE-X', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"foo":1}'::jsonb, gen_random_uuid())$$, 'bad_legal');
select tt.err('T5 legal details only for a legal entity', $$select org_unit_save(null, (select id from org_units where code='HARDWARE'), 'branch', 'ZZ12', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":50}'::jsonb, gen_random_uuid())$$, 'legal_only_for_legal_entity');
select tt.err('T5 the kind never changes', $$select org_unit_save((select id from org_units where code='HW-B2'), (select id from org_units where code='HARDWARE'), 'site', null, 'x', null, null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)$$, 'kind_fixed');
select tt.err('T5 the code never changes', $$select org_unit_save((select id from org_units where code='HW-B2'), (select id from org_units where code='HARDWARE'), null, 'NEWCODE', 'x', null, null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)$$, 'code_fixed');
select tt.err('T5 a unit cannot move under its own child (cycle / bad kind)', $$select org_unit_save((select id from org_units where code='HW-B1'), (select id from org_units where code='HW-B1-D1'), null, null, 'x', null, null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)$$, 'bad_parent_kind');
select tt.err('T5 a branch cannot become its own descendant (cycle)', $$select org_unit_save((select id from org_units where code='HW-B1'), (select id from org_units where code='HW-B1'), null, null, 'x', null, null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)$$, 'parent_cycle');
select tt.eq('T5 nothing was created by the refused calls (still 8 units)', 8, (select count(*) from org_units));
select tt.t('T5 a branch moves to another business (allowed move)', (org_unit_save((select id from org_units where code='HW-B2'), (select id from org_units where code='HW-B1'), null, null, 'শাখা ২', 'Branch 2', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)->>'id')::bigint = :'hb2'::bigint);
select tt.t('T5 ... and now sits under HW-B1', (select parent_id = :'hb1'::bigint from org_units where id = :'hb2'::bigint));
select org_unit_save(:'hb2'::bigint, :'hbz'::bigint, null, null, 'শাখা ২', 'Branch 2', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null) is not null as mv \gset

\echo == T6 deactivation keeps history
select tt.err('T6 refused while an active child exists', $$select org_unit_deactivate((select id from org_units where code='HARDWARE'), 'closing', gen_random_uuid())$$, 'has_active_children');
select tt.err('T6 the sweets business is refused while its locations are active', $$select org_unit_deactivate((select id from org_units where code='SWEETS'), 'test', null)$$, 'has_active_locations');
select org_unit_deactivate((select id from org_units where code='HW-B1-D1'), 'merged', gen_random_uuid()) ->> 'dup' as d1 \gset
select tt.is('T6 first deactivation is not a duplicate', 'false', :'d1');
select tt.is('T6 repeating it is a no-op (dup)', 'true', org_unit_deactivate((select id from org_units where code='HW-B1-D1'), 'merged', gen_random_uuid()) ->> 'dup');
select tt.is('T6 status inactive, effective_to = today, reason kept', 'inactive/' || tt.today()::text || '/merged', (select status || '/' || effective_to::text || '/' || deactivated_reason from org_units where code = 'HW-B1-D1'));
select tt.eq('T6 the row is still there (not deleted)', 1, (select count(*) from org_units where code = 'HW-B1-D1'));
select tt.t('T6 the audit log has the insert and the deactivation of that unit', (select count(*) filter (where action = 'insert') = 1 and count(*) filter (where action = 'update' and detail->'new'->>'status' = 'inactive') = 1
  from audit_log where table_name = 'org_units' and record_id = (select id::text from org_units where code = 'HW-B1-D1')));
select tt.err('T6 a hard delete is refused', $$delete from org_units where code = 'HW-B1-D1'$$, '');
select tt.eq('T6 ... the row survived', 1, (select count(*) from org_units where code = 'HW-B1-D1'));
select tt.err('T6 an inactive unit takes no new child', $$select org_unit_save(null, (select id from org_units where code='HW-B1-D1'), 'cost_centre', 'CC1', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'parent_inactive');
select tt.t('T6 the deactivated unit still shows in org_tree with its history', exists (select 1 from org_tree() where code = 'HW-B1-D1' and status = 'inactive'));
select org_unit_deactivate((select id from org_units where code='HW-B2'), null, gen_random_uuid()) is not null as x1 \gset
select org_unit_deactivate((select id from org_units where code='HW-B1'), null, gen_random_uuid()) is not null as x2 \gset
select org_unit_deactivate((select id from org_units where code='HARDWARE'), 'closed', gen_random_uuid()) is not null as x3 \gset
select tt.is('T6 whole branch closed bottom-up', 'inactive', (select status from org_units where code = 'HARDWARE'));
select tt.err('T6 editing an inactive unit under an inactive parent cannot reactivate it', $$select org_unit_save((select id from org_units where code='HW-B1'), (select id from org_units where code='HARDWARE'), null, null, 'শাখা ১', 'Branch 1', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)$$, 'parent_inactive');
select org_unit_save((select id from org_units where code='HARDWARE'), (select id from org_units where code='LE-HW'), null, null, 'হার্ডওয়্যার ও রং', 'Hardware & Paint', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null) is not null as ra \gset
select tt.t('T6 reactivation with an explicit active status works and clears the reason', (select status = 'active' and deactivated_reason is null from org_units where code = 'HARDWARE'));

\echo == T7 who may do what
select tt.as(:'sp');
select tt.err('T7 a salesperson without org_manage cannot create', $$select org_unit_save(null, (select id from org_units where code='LE-SWEETS'), 'business', 'NOPE1', 'x', null, null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())$$, 'not allowed');
select tt.err('T7 ... cannot update', $$select org_unit_save((select id from org_units where code='SWEETS'), (select id from org_units where code='LE-SWEETS'), null, null, 'x', null, null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, null)$$, 'not allowed');
select tt.err('T7 ... cannot deactivate', $$select org_unit_deactivate((select id from org_units where code='HARDWARE'), 'x', null)$$, 'not allowed');
select tt.eq('T7 org_tree for a salesperson of location 1: only the sweets chain (group, legal entity, business)', 3, (select count(*) from org_tree()));
select tt.t('T7 ... no hardware unit visible', not exists (select 1 from org_tree() where code like 'HW%' or code in ('HARDWARE', 'LE-HW')));
select tt.t('T7 ... no ownership %, tax config, licence, attrs, fiscal start', (select bool_and(owner_pct is null and tax_cfg is null and trade_licence_ref is null and attrs = '{}'::jsonb and fiscal_start is null) from org_tree()));
select tt.is('T7 org_unit_scope of an assigned location works', 'SWEETS', org_unit_scope(1)->>'business_code');
select tt.err('T7 org_unit_scope of a location not assigned is refused', $$select org_unit_scope(3)$$, 'not allowed');
select tt.as(:'ma');
select tt.eq('T7 a manager of locations 1 and 2 still sees the same 3 units', 3, (select count(*) from org_tree()));
select tt.as(:'o');
select set_user_grant(:'fm2'::uuid, 'org_manage') is null as gg \gset
select tt.as(:'fm2');
select tt.t('T7 with the org_manage grant the user can create a unit', (org_unit_save(null, (select id from org_units where code='HARDWARE'), 'site', 'HW-S1', 'গুদাম', 'Warehouse', null, 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, gen_random_uuid())->>'id') is not null);
select tt.err('T7 ... but ownership % needs the owner', $$select org_unit_save((select id from org_units where code='LE-HW'), (select id from org_units where kind='group'), null, null, 'x', null, null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":10}'::jsonb, null)$$, 'owner_only');
select tt.err('T7 ... and so does the tax config', $$select org_unit_save((select id from org_units where code='LE-HW'), (select id from org_units where kind='group'), null, null, 'x', null, null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"tax_cfg":{"a":1}}'::jsonb, null)$$, 'owner_only');
select tt.t('T7 ... the licence number can be changed by org_manage', (org_unit_save((select id from org_units where code='LE-HW'), (select id from org_units where kind='group'), null, null, 'হার্ডওয়্যার কোম্পানি', 'Hardware Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"trade_licence_ref":"TL-HW-002"}'::jsonb, null)->>'id') is not null);
select tt.eq('T7 org_manage sees every unit', (select count(*) from org_units)::numeric, (select count(*) from org_tree()));
select tt.is('T7 ... the licence but not the ownership % of the hardware company', 'TL-HW-002/null', (select trade_licence_ref || '/' || coalesce(owner_pct::text, 'null') from org_tree() where code = 'LE-HW'));
select tt.as(:'o');
select tt.is('T7 the owner sees the ownership %', '60.0000', (select owner_pct::text from org_tree() where code = 'LE-HW'));
select tt.t('T7 the owner can change the ownership %', (org_unit_save((select id from org_units where code='LE-HW'), (select id from org_units where kind='group'), null, null, 'হার্ডওয়্যার কোম্পানি', 'Hardware Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":55.5}'::jsonb, null)->>'id') is not null);
select tt.eq('T7 ... 55.5', 55.5, (select owner_pct from legal_entities where org_unit_id = (select id from org_units where code='LE-HW')));
select tt.err('T7 a legal_entities row cannot point at a non legal-entity unit', $$insert into legal_entities (org_unit_id) values ((select id from org_units where code='SWEETS'))$$, 'not_a_legal_entity');

\echo == T8 direct table access and anon
select tt.as(:'sp'); set role authenticated;
select tt.eq('T8 a salesperson reads no row of org_units directly (RLS)', 0, (select count(*) from org_units));
select tt.eq('T8 ... nor legal_entities', 0, (select count(*) from legal_entities));
select tt.t('T8 ... but may read the template list', (select count(*) from business_templates) >= 6);
select tt.err('T8 ... and cannot write a table', $$update org_units set name_bn = 'x'$$, 'permission denied');
reset role;
select tt.as(:'o'); set role authenticated;
select tt.t('T8 the owner can read org_units directly', (select count(*) from org_units) >= 8);
select tt.eq('T8 ... and only the owner reads legal_entities (2 rows)', 2, (select count(*) from legal_entities));
reset role;
select tt.t('T8 anon cannot execute any of the four browser functions', not has_function_privilege('anon', 'public.org_tree()', 'execute') and not has_function_privilege('anon', 'public.org_unit_scope(integer)', 'execute')
  and not has_function_privilege('anon', 'public.org_unit_save(bigint,bigint,text,text,text,text,text,text,date,date,text,text,jsonb,jsonb,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.org_unit_deactivate(bigint,text,uuid)', 'execute') and not has_function_privilege('public', 'public.org_tree()', 'execute'));
select tt.t('T8 signed-in users can', has_function_privilege('authenticated', 'public.org_tree()', 'execute') and has_function_privilege('authenticated', 'public.org_unit_deactivate(bigint,text,uuid)', 'execute'));
set role anon;
select tt.err('T8 anon calling org_tree is refused', $$select * from org_tree()$$, 'permission denied');
select tt.err('T8 anon reading org_units is refused', $$select count(*) from org_units$$, 'permission denied');
reset role;
select tt.as(:'o');

\echo == T9 second paste, no change; a location added later is not auto-mapped
insert into locations (code, name_bn, name_en, kind, status) values ('hw_shop', 'হার্ডওয়্যার দোকান', 'Hardware shop', 'showroom', 'planned');
create temp table k1 as select (select count(*) from org_units) ou_n, (select md5(string_agg(to_jsonb(u)::text, '|' order by id)) from org_units u) ou_h, (select md5(string_agg(to_jsonb(l)::text, '|' order by org_unit_id)) from legal_entities l) le_h,
  (select md5(string_agg(to_jsonb(l)::text, '|' order by id)) from locations l) loc_h, (select count(*) from rules) rules_n, (select count(*) from grant_defs) gd_n, (select count(*) from setup_rec_defs81) adv_n,
  (select md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r) rules_h;
\i supabase/phase122.sql
select tt.t('T9 second paste: no org_unit, legal entity or location row changed', (select ou_n = (select count(*) from org_units) and ou_h = (select md5(string_agg(to_jsonb(u)::text, '|' order by id)) from org_units u)
  and le_h = (select md5(string_agg(to_jsonb(l)::text, '|' order by org_unit_id)) from legal_entities l) and loc_h = (select md5(string_agg(to_jsonb(l)::text, '|' order by id)) from locations l) from k1));
select tt.t('T9 ... rules, grants and advisor rows unchanged (the owner-typed values survive)', (select rules_n = (select count(*) from rules) and gd_n = (select count(*) from grant_defs) and adv_n = (select count(*) from setup_rec_defs81)
  and rules_h = (select md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r) from k1));
select tt.is('T9 a location created after the first paste stays unmapped (fill-null only up to the first-paste ids)', 'null', (select coalesce(org_unit_id::text, 'null') from locations where code = 'hw_shop'));
select tt.eq('T9 still exactly one group, one SWEETS', 2, (select count(*) from org_units where kind = 'group' or code = 'SWEETS'));
select tt.is('T9 org_unit_scope of the unmapped location says so', 'false', org_unit_scope((select id from locations where code = 'hw_shop'))->>'mapped');
select tt.t('T9 no existing function body changed by the second paste', not exists (select 1 from pg_proc p join h0 on h0.fn = p.oid::regprocedure::text where p.pronamespace = 'public'::regnamespace and md5(pg_get_functiondef(p.oid)) <> h0.h));
select tt.t('T9 ... and no function was added except ours', not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname !~ '(^org_|^_org_|^_le_kind_check122$|^_biz_|^_my_biz125$|^_var_gate125$|^_items_org125$|^option_|^style_save$|^variants_|^variant_matrix$|^my_businesses125$|^price_list|^price_for125$|^items_search)' and p.oid::regprocedure::text not in (select fn from h0)));

\echo == T10 sweets numbers unchanged
select tt.t('T10 the 7 sweets locations still map to SWEETS after everything above', (select count(*) = 7 from locations l join org_units b on b.id = l.org_unit_id and b.code = 'SWEETS'));
select tt.t('T10 trial balance and the rules table (other than the new switch) are as at the start', (select tb_h = (select md5(acct_trial_balance(null, null)::text)) from k0));
select tt.t('T10 the only new rule is org_scope_on', (select count(*) from rules) = (select rules_n from k0));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
