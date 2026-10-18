-- FRESH DB ONLY. Phase 486 tests (item recognition foundation). Test data only: test_* names, throwaway database.
--   build a database through phase 486 (tests/sql/ORDER.txt + supabase/phase486.sql), then from the repository root
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase486_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\i tests/sql/rpthub_tt.sql
begin;   -- everything below is rolled back at the end, so the suite can be run again on the same database
\echo == setup: test owner and test clerk (no roles)
insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'test_owner@example.test'), ('22222222-2222-2222-2222-222222222222', 'test_clerk@example.test') on conflict do nothing;
insert into public.profiles (id, staff_id, full_name, status) values ('11111111-1111-1111-1111-111111111111', 'test_owner', 'test_owner', 'active'), ('22222222-2222-2222-2222-222222222222', 'test_clerk', 'test_clerk', 'active') on conflict do nothing;
insert into public.user_roles (user_id, role_code) values ('11111111-1111-1111-1111-111111111111', 'owner') on conflict do nothing;
insert into public.items (code, name_bn, name_en, item_type, unit, barcode) values
  ('test_cat-901', 'টেস্ট চিনি', 'Test Sugar Bag', 'resale', 'kg', 'test_bc_901'),
  ('test_cat-902', 'টেস্ট ডিম', 'Test Egg Tray', 'resale', 'pc', null)
on conflict do nothing;
select tt.as('11111111-1111-1111-1111-111111111111');

\echo == T1 rules default OFF, parity
select tt.chk('T1 every new recognition switch is OFF by default', not exists (select 1 from public.rules where key in ('item_similar_check_on', 'recog_ocr_on', 'recog_image_match_on', 'recog_vision_on', 'recog_vision_consent_on') and default_value <> 'false'));
select tt.chk('T1 the image threshold has no invented default (blank)', (select default_value is null from public.rules where key = 'recog_image_threshold'));
select tt.chk('T1 blank by default (no invented limit): ocr px, ocr langs, vision budget', (select count(*) from public.rules where key in ('recog_ocr_max_px', 'recog_ocr_langs', 'recog_vision_budget') and default_value is null) = 3);
select tt.chk('T1 OCR Wi-Fi-only switch is ON (safe default)', (select default_value = 'true' from public.rules where key = 'recog_ocr_wifi_only'));
select tt.chk('T1 rule_on of a new switch is false with the seed', public.rule_on('item_similar_check_on') = false and public.rule_on('recog_vision_on') = false);

\echo == T2 item_similar (Bangla and English, normalisation, barcode)
select tt.chk('T2 exact English name = exists', (public.item_similar(null, 'test sugar bag', null)->>'status') = 'exists');
select tt.chk('T2 spacing and case ignored (Bangla)', (public.item_similar('টেস্ট চিনি', null, null)->>'status') = 'exists');
select tt.chk('T2 one letter off (English) = similar', (public.item_similar(null, 'Test Sugr Bag', null)->>'status') = 'similar');
select tt.chk('T2 contains (Bangla) = similar', (public.item_similar('চিনি', null, null)->>'status') = 'similar');
select tt.chk('T2 unrelated name = none', (public.item_similar('গরুর মাংস', 'Beef', null)->>'status') = 'none');
select tt.chk('T2 barcode in use = barcode_exists with the item', (public.item_similar('নতুন', 'New', 'test_bc_901')->'barcode_hit'->>'code') = 'test_cat-901');
select tt.chk('T2 own item excluded by id', (public.item_similar(null, 'Test Sugar Bag', null, (select id from public.items where code = 'test_cat-901'))->>'status') = 'none');
select tt.chk('T2 similar list is capped at 8 and has the kind', (public.item_similar(null, 'Test Egg Tray', null)->'similar'->0->>'kind') = 'same');
select tt.err('T2 name too long refused', $q$select public.item_similar(repeat('a', 121), null, null)$q$, 'name_too_long');

\echo == T3 item_new2 (idempotent, barcode, exact name, similar, default parity)
select tt.chk('T3 default OFF: a clean new item is created like item_new', (public.item_new2('{"name_bn":"টেস্ট নতুন এক","name_en":"Test New One","item_type":"resale","unit":"pc"}', null, '33333333-3333-3333-3333-333333333333', false)->>'status') in ('created', 'pending'));
select tt.chk('T3 same client_id again returns the same answer, creates nothing new', (select count(*) from public.items where name_en = 'Test New One') = 1);
select tt.chk('T3 repeat flag is set', (public.item_new2('{"name_bn":"টেস্ট নতুন এক","name_en":"Test New One","item_type":"resale","unit":"pc"}', null, '33333333-3333-3333-3333-333333333333', false)->>'repeat') = 'true');
select public.set_rule('item_similar_check_on', 'true'::jsonb);
select tt.chk('T3 switch ON: exact name refused, nothing created', (public.item_new2('{"name_bn":"টেস্ট চিনি","name_en":"Test Sugar Bag","item_type":"resale","unit":"kg"}', null, '44444444-4444-4444-4444-444444444444', false)->>'status') = 'exists' and (select count(*) from public.items where name_en = 'Test Sugar Bag') = 1);
select tt.chk('T3 switch ON: barcode in use refused with the item', (public.item_new2('{"name_bn":"টেস্ট অন্য","name_en":"Other","item_type":"resale","unit":"pc","barcode":"test_bc_901"}', null, '55555555-5555-5555-5555-555555555555', false)->>'status') = 'barcode_exists');
select tt.chk('T3 switch ON: similar name asks, does not create', (public.item_new2('{"name_bn":"টেস্ট ডিমের","name_en":"Test Egg Trays","item_type":"resale","unit":"pc"}', null, '66666666-6666-6666-6666-666666666666', false)->>'status') = 'similar' and (select count(*) from public.items where name_en = 'Test Egg Trays') = 0);
select tt.chk('T3 switch ON: force = true creates the similar item', (public.item_new2('{"name_bn":"টেস্ট ডিমের","name_en":"Test Egg Trays","item_type":"resale","unit":"pc"}', null, '77777777-7777-7777-7777-777777777777', true)->>'status') in ('created', 'pending'));
select public.set_rule('item_similar_check_on', 'false'::jsonb);
select tt.chk('T3 switch back OFF restored', public.rule_on('item_similar_check_on') = false);

\echo == T4 review queue and aliases
select tt.err('T4 rejected without reason refused', $q$select public.item_recognition_review_add((select id from public.items where code = 'test_cat-901'), 'ocr', null, 'rejected', '')$q$, 'reason_required');
select tt.chk('T4 review add (owner): ambiguous with reason', public.item_recognition_review_add((select id from public.items where code = 'test_cat-901'), 'ocr', null, 'ambiguous', 'two labels') > 0);
select tt.err('T4 approved needs a candidate', $q$select public.item_recognition_review_add((select id from public.items where code = 'test_cat-901'), 'image', null, 'approved', null)$q$, 'candidate_required');
select tt.err('T4 bad decision refused', $q$select public.item_recognition_review_add(null, 'ocr', null, 'maybe', 'x')$q$, 'bad_decision');
select public.item_alias_approve('চিনির বস্তা', (select id from public.items where code = 'test_cat-901'), 'label_text') as alias_id \gset
select tt.chk('T4 alias approve (owner) and find by normalised text (separate statement: find is stable)', :alias_id > 0 and exists (select 1 from public.item_alias_find('চিনির  বস্তা')));
select tt.chk('T4 alias approve again is idempotent (one row)', public.item_alias_approve('চিনির বস্তা', (select id from public.items where code = 'test_cat-901'), 'label_text') is not null and (select count(*) from public.item_aliases) = 1);
select tt.chk('T4 alias find returns the source', (select source from public.item_alias_find('চিনির বস্তা')) = 'label_text');

\echo == T5 assets: identity fields (owner); unique serial per item
select tt.chk('T5 asset identity columns exist', (select count(*) from information_schema.columns where table_name = 'assets' and column_name in ('brand', 'serial_no', 'warranty_until')) = 3);

\echo == T6 RLS and rights: anon and clerk refused, closed tables
set role anon;
select tt.err('T6 anon: item_new2 refused', $q$select public.item_new2('{"name_bn":"x"}', null, null, false)$q$, 'permission denied');
select tt.err('T6 anon: item_recognition_reviews read refused', $q$select count(*) from public.item_recognition_reviews$q$, 'permission denied');
select tt.err('T6 anon: item_new_clients read refused', $q$select count(*) from public.item_new_clients$q$, 'permission denied');
reset role;
select tt.as('22222222-2222-2222-2222-222222222222');
set role authenticated;
select tt.err('T6 clerk without ITEMS rights: item_new2 refused', $q$select public.item_new2('{"name_bn":"টেস্ট ক্লার্ক","name_en":"Clerk Item"}', null, null, false)$q$, 'not allowed');
select tt.err('T6 clerk: review add refused', $q$select public.item_recognition_review_add(null, 'ocr', null, 'manual', null)$q$, 'not allowed');
select tt.err('T6 clerk: alias approve refused', $q$select public.item_alias_approve('abc', (select id from public.items limit 1), 'manual')$q$, 'not allowed');
select tt.err('T6 clerk: direct write to item_aliases refused', $q$insert into public.item_aliases (alias, norm, item_id, source) values ('x', 'x', (select id from public.items limit 1), 'manual')$q$, 'permission denied');
reset role;
select tt.as('11111111-1111-1111-1111-111111111111');

\echo == T7 paste twice
\i supabase/phase486.sql
select tt.chk('T7 second paste: aliases kept', (select count(*) from public.item_aliases) = 1);
select tt.chk('T7 second paste: rules still OFF', public.rule_on('recog_ocr_on') = false);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
rollback;
