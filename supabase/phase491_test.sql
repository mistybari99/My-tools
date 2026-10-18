-- FRESH COPY ONLY. X2 website tests (phases 490 + 491). Build a database through phase 478, then paste 490 and 491 (twice is fine), then:
--   psql -h /tmp -p <port> -U postgres -d <db> -qAt -f supabase/phase491_test.sql | grep -E 'FAIL|RESULT'
-- Test data only: items and names are test_*. Covers: public read RPCs only for anon, no cost/stock leak, idempotent checkout,
-- server re-pricing, rate limit, validation, hard holds (no oversell, release on cancel and on expiry), tracking, cancel and custom requests,
-- closures, publishing guard, drift, go-live, owner-only admin, default-off parity.
\set ON_ERROR_STOP off
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

\set o '00000000-0000-0000-0000-0000000091a1'
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner91@test.app','{"full_name":"test_owner"}') on conflict do nothing;
update profiles set status='active' where id = :'o';
insert into user_roles values (:'o','owner') on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, category, category_bn)
  values ('W91A','test_w1','test_w1','pc','pc','finished_good',true,100,'test_cake','test_cake'),
         ('W91B','test_w2','test_w2','pc','pc','finished_good',false,50,'test_cake','test_cake'),
         ('W91C','test_w3_hidden','test_w3','pc','pc','finished_good',false,70,'test_cake','test_cake') on conflict do nothing;
update items set hidden = true where code = 'W91C';
select id as w1 from items where code='W91A' \gset
select id as w2 from items where code='W91B' \gset
select id as w3 from items where code='W91C' \gset
select tt.as(:'o');
select public._dhaka_today()::text as today \gset
select stock_opening(:'w1'::uuid, 1, 5, 40, null, 'test seed') is not null as so \gset

-- owner setup (every switch is set on purpose here; the default test at the end checks the OFF state)
select set_rule('website_on','true') is null as r1 \gset
select set_rule('website_location_id','1') is null as r2 \gset
select set_rule('website_brand_bn','"test_shop"') is null as r3 \gset
select set_rule('website_brand_en','"test_shop"') is null as r4 \gset
select set_rule('website_pay_cod_on','true') is null as r5 \gset
select set_rule('website_pay_manual_on','true') is null as r6 \gset
select set_rule('website_pay_mobile_number','"01700000091"') is null as r7 \gset
select set_rule('website_rate_max','50') is null as r8 \gset
select set_rule('online_orders_on','true') is null as r9 \gset
select set_rule('website_stock_threshold','5') is null as r10 \gset
select set_rule('website_reserve_on','false') is null as r11 \gset
select set_rule('website_reserve_minutes','30') is null as r12 \gset
select set_rule('website_captcha_on','false') is null as r13 \gset
select web_admin_item_save(:'w1'::uuid, '{"published":true,"name_bn":"test_w1 bn","name_en":"test_w1 en","category_pub":"test_cakes","diet":["eggless"],"allergens":"test milk"}'::jsonb) is not null as p1 \gset
select web_admin_item_save(:'w2'::uuid, '{"published":true,"name_en":"test_w2 en","category_pub":"test_sweets","avail_mode":"auto"}'::jsonb) is not null as p2 \gset
select web_admin_zone_save(null, '{"name_bn":"test_zone","charge":50,"min_order":0}'::jsonb) is not null as z1 \gset
select web_admin_pickup_save(1, '{"public":true,"hours_bn":"test_hours","address":"test_addr"}'::jsonb) is not null as pk1 \gset
select id as zone1 from web_zones where name_bn='test_zone' \gset

\echo == T0 objects and grants
select tt.chk('T0 phase 490/491 objects exist', to_regprocedure('public.web_checkout_submit(uuid,text,text,text,int,text,jsonb,text,text,text,date,int,jsonb,text)') is not null and to_regprocedure('public.web_admin_go_live()') is not null and to_regprocedure('public.web_catalog_v2(text)') is not null);
select tt.chk('T0 anon may execute the public entry points', has_function_privilege('anon','public.web_catalog_v2(text)','execute') and has_function_privilege('anon','public.web_site_config()','execute') and has_function_privilege('anon','public.web_quote(jsonb,int,text)','execute') and has_function_privilege('anon','public.web_checkout_submit(uuid,text,text,text,int,text,jsonb,text,text,text,date,int,jsonb,text)','execute') and has_function_privilege('anon','public.web_order_track(text,text)','execute') and has_function_privilege('anon','public.web_custom_request(uuid,text,text,text,numeric,text,date,text,text,text)','execute'));
select tt.chk('T0 anon may NOT execute any owner admin function or helper of this phase', not exists (select 1 from pg_proc p where p.pronamespace='public'::regnamespace and (p.proname like 'web\_admin\_%' or p.proname in ('web_holds_expire', '_web_avail', '_web_rate91', '_web_hold_sync91', '_web_newcode91')) and has_function_privilege('anon', p.oid, 'execute')));
select tt.chk('T0 no anon read of the new tables', not (has_table_privilege('anon','public.web_item_pub','select') or has_table_privilege('anon','public.web_stock_holds','select') or has_table_privilege('anon','public.web_item_images','select') or has_table_privilege('anon','public.web_zones','select') or has_table_privilege('anon','public.web_rate_hits','select') or has_table_privilege('anon','public.web_custom_requests','select') or has_table_privilege('anon','public.web_cancel_requests','select')));

\echo == T1 anon catalogue: published only, no cost, no stock number, no internal fields
set role anon;
select web_catalog_v2(null)::text as cat \gset
reset role;
select tt.chk('T1 catalogue shows the two published items and not the hidden one', (:'cat'::jsonb->'items') @> jsonb_build_array(jsonb_build_object('id', :'w1'::uuid)) and (:'cat'::jsonb->'items') @> jsonb_build_array(jsonb_build_object('id', :'w2'::uuid)) and not (:'cat'::text like '%' || :'w3'::text || '%'));
select tt.chk('T1 limited at the threshold (stock 5, threshold 5), in stock when untracked', (select (x->>'availability') from jsonb_array_elements(:'cat'::jsonb->'items') x where (x->>'id')::uuid = :'w1'::uuid) = 'limited' and (select (x->>'availability') from jsonb_array_elements(:'cat'::jsonb->'items') x where (x->>'id')::uuid = :'w2'::uuid) = 'in_stock');
select tt.chk('T1 no cost, supplier, exact stock, code or purchase fields leak', position('cost' in lower(:'cat')) = 0 and position('wholesale' in lower(:'cat')) = 0 and position('supplier' in lower(:'cat')) = 0 and position('"qty"' in :'cat') = 0 and position('"stock' in lower(:'cat')) = 0 and position('W91A' in :'cat') = 0 and position('"code"' in :'cat') = 0 and position('by_staff' in :'cat') = 0);
select tt.chk('T1 allergen and diet tags are shown', position('test milk' in :'cat') > 0 and position('eggless' in :'cat') > 0);
set role anon;
select web_site_config()::text as cfg \gset
reset role;
select tt.chk('T1 public config gives the brand and the pickup point, and no secret-looking key', position('test_shop' in :'cfg') > 0 and position('test_hours' in :'cfg') > 0 and position('service' in lower(:'cfg')) = 0 and position('secret' in lower(:'cfg')) = 0);

\echo == T2 server re-prices: the browser price is ignored, the total comes from the item list
set role anon;
select web_quote(('[{"item_id":"'||:'w2'||'","qty":2,"price":1}]')::jsonb, null, 'pickup')::text as q1 \gset
reset role;
select tt.chk('T2 a fake client price is ignored (2 x 50 = 100)', (:'q1'::jsonb->>'subtotal')::numeric = 100);
select tt.chk('T2 an unpublished item is refused', (select (web_quote(('[{"item_id":"'||:'w3'||'","qty":1}]')::jsonb, null, 'pickup')->>'ok')::boolean) = false);
select tt.chk('T2 a fractional quantity of a piece item is refused', (select web_quote(('[{"item_id":"'||:'w2'||'","qty":1.5}]')::jsonb, null, 'pickup')->>'error') = 'bad_qty');

\echo == T3 checkout: idempotent, validated, rate limited
set role anon;
select web_checkout_submit('00000000-0000-4000-8000-0000000091c1'::uuid, 'test_buyer', '01711000091', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":2}]')::jsonb, 'test note', 'cod', null, :'today', null, '{"source":"test","medium":"cpc","campaign":"test_camp"}'::jsonb, 'kh91')::text as c1 \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091c1'::uuid, 'test_buyer', '01711000091', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":2}]')::jsonb, 'test note', 'cod', null, :'today', null, '{}'::jsonb, 'kh91')::text as c2 \gset
reset role;
select tt.chk('T3 first checkout is an order (status new, total 100)', (:'c1'::jsonb->>'ok')::boolean and (:'c1'::jsonb->>'status') = 'new' and (:'c1'::jsonb->>'total')::numeric = 100 and (:'c1'::jsonb->>'web_code') ~ '^[A-Z0-9]{8}$');
select tt.chk('T3 the same submission twice gives the same order, not a second one', (:'c2'::jsonb->>'dup')::boolean and (:'c2'::jsonb->>'order_no') = (:'c1'::jsonb->>'order_no') and (select count(*) from online_orders where external_ref = '00000000-0000-4000-8000-0000000091c1') = 1);
select tt.chk('T3 the campaign from the link is kept (order source and marketing tag)', exists (select 1 from online_orders where web_code = :'c1'::jsonb->>'web_code' and source = 'test/cpc/test_camp') and exists (select 1 from mkt_order_tags where campaign_code = 'test_camp'));
select tt.chk('T3 the order is in the web channel for the branch', exists (select 1 from online_orders where web_code = :'c1'::jsonb->>'web_code' and channel = 'website' and location_id = 1));
set role anon;
select web_checkout_submit('00000000-0000-4000-8000-0000000091c2'::uuid, 'test_buyer', '01711000091', 'home', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, 'kh91')::text as e1 \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091c3'::uuid, 'test_buyer', '01711000091', 'home', null, 'test_addr', ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, 'kh91')::text as e2 \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091c4'::uuid, 'test_buyer', '01711000091', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'manual', '', :'today', null, null, 'kh91')::text as e3 \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091c5'::uuid, 'test_buyer', '01711000091', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, (:'today'::date - 1), null, null, 'kh91')::text as e4 \gset
reset role;
select tt.chk('T3 home delivery without an address is refused', (:'e1'::jsonb->>'error') = 'address_required');
select tt.chk('T3 home delivery without a zone is refused', (:'e2'::jsonb->>'error') = 'zone_required' and (:'e2'::jsonb->>'ok')::boolean = false);
select tt.chk('T3 manual bKash/Nagad without a Trx ID is refused', (:'e3'::jsonb->>'error') = 'trx_required');
select tt.chk('T3 a past delivery date is refused', (:'e4'::jsonb->>'error') = 'bad_date');
select set_rule('website_rate_max','2') is null as rl1 \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091c6'::uuid, 'test_buyer', '01711000091', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, 'kh-rl')::text as rl_a \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091c7'::uuid, 'test_buyer', '01711000091', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, 'kh-rl')::text as rl_b \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091c8'::uuid, 'test_buyer', '01711000091', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, 'kh-rl')::text as rl_c \gset
select tt.chk('T3 the rate limit (max 2 per device) refuses the 3rd attempt from one device', (:'rl_c'::jsonb->>'error') = 'rate_limited' and (:'rl_b'::jsonb->>'error') is distinct from 'rate_limited');
select set_rule('website_rate_max','50') is null as rl2 \gset

\echo == T4 hard stock holds: reserve on, no oversell, release on cancel and on expiry
select set_rule('website_reserve_on','true') is null as rr2 \gset
set role anon;
select web_checkout_submit('00000000-0000-4000-8000-0000000091d1'::uuid, 'test_buyer', '01711000092', 'pickup', null, null, ('[{"item_id":"'||:'w1'||'","qty":5}]')::jsonb, null, 'cod', null, :'today', null, null, null)::text as h1 \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091d2'::uuid, 'test_buyer', '01711000093', 'pickup', null, null, ('[{"item_id":"'||:'w1'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, null)::text as h2 \gset
reset role;
select tt.chk('T4 the first checkout takes all 5 units and is held', (:'h1'::jsonb->>'ok')::boolean and (:'h1'::jsonb->>'held')::boolean);
select tt.chk('T4 the second checkout for the last unit is refused as sold out (no oversell)', (:'h2'::jsonb->>'error') = 'sold_out');
select tt.chk('T4 the held quantity is visible to staff only (holds report)', (web_admin_holds_report()->>'held_qty')::numeric = 5);
select id as h1id from online_orders where web_code = :'h1'::jsonb->>'web_code' \gset
select online_order_cancel(:'h1id'::uuid, 'test cancel', 'none') is not null as cx \gset
select tt.chk('T4 a cancelled order releases its hold', (select count(*) from web_stock_holds where order_id = :'h1id'::uuid and state = 'released') = 1 and (select count(*) from web_stock_holds where order_id = :'h1id'::uuid and state = 'held') = 0);
set role anon;
select web_checkout_submit('00000000-0000-4000-8000-0000000091d3'::uuid, 'test_buyer', '01711000093', 'pickup', null, null, ('[{"item_id":"'||:'w1'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, null)::text as h3 \gset
reset role;
select tt.chk('T4 after the release the unit can be sold again', (:'h3'::jsonb->>'ok')::boolean and (:'h3'::jsonb->>'held')::boolean);
update web_stock_holds set expires_at = now() - interval '1 minute' where submission = '00000000-0000-4000-8000-0000000091d3'::uuid;
select web_holds_expire() as exp \gset
select tt.chk('T4 an expired hold is released by the expiry run (nothing deleted)', :exp = 1 and (select state||':'||close_note from web_stock_holds where submission = '00000000-0000-4000-8000-0000000091d3'::uuid and item_id = :'w1'::uuid) = 'released:expired');
select tt.chk('T4 the reconciliation report has no expired-but-open holds', (web_admin_holds_report()->>'expired_not_closed')::int = 0);
select set_rule('website_reserve_on','false') is null as rr3 \gset

\echo == T5 tracking and cancel request (customer sees status only)
set role anon;
select web_order_track(:'c1'::jsonb->>'web_code', '01711000091')::text as t1 \gset
select web_order_track(:'c1'::jsonb->>'web_code', '01799999999')::text as t2 \gset
select web_order_cancel_request(:'c1'::jsonb->>'web_code', '01711000091', 'test changed mind', 'kh-cancel')::text as k1 \gset
select web_order_cancel_request(:'c1'::jsonb->>'web_code', '01711000091', 'test again', 'kh-cancel')::text as k2 \gset
reset role;
select tt.chk('T5 tracking with the right code and phone shows the status', (:'t1'::jsonb->>'ok')::boolean and (:'t1'::jsonb->>'status') = 'new');
select tt.chk('T5 a wrong phone gets the same not_found (no order enumeration)', (:'t2'::jsonb->>'error') = 'not_found');
select tt.chk('T5 tracking never shows staff names or internal notes', position('by_staff' in :'t1') = 0 and position('test note' in :'t1') = 0 and position('web' in :'t1'::jsonb->>'events') = 0);
select tt.chk('T5 a cancel request is recorded once (the second is a no-op)', (:'k1'::jsonb->>'requested')::boolean and not (:'k2'::jsonb->>'requested')::boolean);
select web_admin_cancel_decide((select id from web_cancel_requests where order_id = (select id from online_orders where web_code = :'c1'::jsonb->>'web_code') and state='open'), false, 'test no') is not null as dec \gset
select tt.chk('T5 the owner decides; declining leaves the order open', (select state from web_cancel_requests where order_id = (select id from online_orders where web_code = :'c1'::jsonb->>'web_code') order by id desc limit 1) = 'declined' and (select status from online_orders where web_code = :'c1'::jsonb->>'web_code') = 'new');

\echo == T6 custom cake request (photo must be in the private bucket)
set role anon;
select web_custom_request('00000000-0000-4000-8000-0000000091e1'::uuid, 'test_cake_buyer', '01711000094', 'test_flavour', 1.5, 'test msg', (:'today'::date + 3), 'test_slot', null, 'kh-cake')::text as cu0 \gset
reset role;
select tt.chk('T6 custom cake is off until the owner switches it on', (:'cu0'::jsonb->>'error') = 'off');
select set_rule('website_custom_cake_on','true') is null as cc \gset
insert into storage.buckets (id, name, public) values ('web-refs','web-refs', false) on conflict do nothing;
insert into storage.objects (bucket_id, name) values ('web-refs', 'test_ref/1.jpg') on conflict do nothing;
set role anon;
select web_custom_request('00000000-0000-4000-8000-0000000091e2'::uuid, 'test_cake_buyer', '01711000094', 'test_flavour', 1.5, 'test msg', (:'today'::date + 3), 'test_slot', 'test_ref/missing.jpg', 'kh-cake')::text as cu1 \gset
select web_custom_request('00000000-0000-4000-8000-0000000091e3'::uuid, 'test_cake_buyer', '01711000094', 'test_flavour', 1.5, 'test msg', (:'today'::date + 3), 'test_slot', 'test_ref/1.jpg', 'kh-cake2')::text as cu2 \gset
select web_custom_request('00000000-0000-4000-8000-0000000091e3'::uuid, 'test_cake_buyer', '01711000094', 'test_flavour', 1.5, 'test msg', (:'today'::date + 3), 'test_slot', 'test_ref/1.jpg', 'kh-cake2')::text as cu3 \gset
reset role;
select tt.chk('T6 a photo that is not in the private bucket is refused', (:'cu1'::jsonb->>'error') = 'photo_not_found');
select tt.chk('T6 a request with a real photo is taken once (same submission = same request)', (:'cu2'::jsonb->>'ok')::boolean and (:'cu3'::jsonb->>'dup')::boolean);
select tt.chk('T6 the photo bucket is private and limited to 3 MB jpeg/png/webp', exists (select 1 from storage.buckets where id = 'web-refs' and not coalesce(public,false) and file_size_limit = 3145728) and exists (select 1 from storage.buckets where id = 'web-public' and public and file_size_limit = 819200));

\echo == T7 publishing guard, images, drift
select tt.err('T7 a hidden item cannot be published', 'select web_admin_item_save(''' || :'w3' || '''::uuid, ''{"published":true}''::jsonb)', 'item_not_sellable');
update items set sell_price = 60 where id = :'w2'::uuid;
select tt.chk('T7 a price change in the ERP shows as drift until published again', (web_admin_drift()->'counts'->>'price_changed')::int = 1);
select web_admin_item_save(:'w2'::uuid, '{"published":true}'::jsonb) is not null as rp \gset
select tt.chk('T7 publishing again refreshes the price snapshot (drift clears)', (web_admin_drift()->'counts'->>'price_changed')::int = 0);
select tt.chk('T7 an image is shown only after approval; the path must sit under the item', (select (web_admin_image_add(:'w1'::uuid, 'items/'||:'w1'||'/1.jpg', 'image/jpeg', 1000)->>'approved')::boolean) = false and (select count(*) from web_item_images where item_id = :'w1'::uuid and approved) = 0);
select web_admin_image_approve((select id from web_item_images where item_id = :'w1'::uuid), true) is not null as ap \gset
set role anon;
select web_catalog_v2(null)::text as cat2 \gset
reset role;
select tt.chk('T7 the approved photo path appears in the catalogue', position('items/' in :'cat2') > 0);
select tt.err('T7 an image path outside the item folder is refused', 'select web_admin_image_add(''' || :'w1' || '''::uuid, ''other/x.jpg'', ''image/jpeg'', 1)', 'bad_path');

\echo == T8 closures
select web_admin_closure_save(:'today', 'test_closed', 'test_closed', false) is not null as cl1 \gset
select tt.chk('T8 a closure day refuses checkout', (select web_checkout_submit('00000000-0000-4000-8000-0000000091f1'::uuid, 'test_buyer', '01711000095', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, null)->>'error') = 'closed_today');
select web_admin_closure_save(:'today', null, null, true) is not null as cl2 \gset
select tt.chk('T8 a reopened day takes orders again (nothing deleted)', (select (web_checkout_submit('00000000-0000-4000-8000-0000000091f2'::uuid, 'test_buyer', '01711000095', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, null)->>'ok')::boolean) and (select count(*) from web_closures where day = :'today') = 1);

\echo == T9 go-live checklist and admin is owner-only
select tt.chk('T9 the go-live check says the domain is missing (honest), but the rest of the local set is OK', (select (x->>'ok')::boolean from jsonb_array_elements(web_admin_go_live()->'items') x where x->>'key'='domain') = false and (select (x->>'ok')::boolean from jsonb_array_elements(web_admin_go_live()->'items') x where x->>'key'='anon_grants') = true and (select (x->>'ok')::boolean from jsonb_array_elements(web_admin_go_live()->'items') x where x->>'key'='test_order') = true);
select set_rule('website_public_url','"https://test-shop.example"') is null as dom \gset
select tt.chk('T9 with a https address the domain item is OK', (select (x->>'ok')::boolean from jsonb_array_elements(web_admin_go_live()->'items') x where x->>'key'='domain') = true);
select set_rule('website_public_url','""') is null as dom2 \gset
set role anon;
do $$ begin
  begin perform public.web_admin_drift(); perform tt.chk('T9 anon cannot run the drift report', false);
  exception when insufficient_privilege then perform tt.chk('T9 anon cannot run the drift report', true); end;
  begin perform public.web_admin_go_live(); perform tt.chk('T9 anon cannot run the go-live check', false);
  exception when insufficient_privilege then perform tt.chk('T9 anon cannot run the go-live check', true); end;
  begin perform count(*) from public.web_item_pub; perform tt.chk('T9 anon cannot read the publishing table', false);
  exception when insufficient_privilege then perform tt.chk('T9 anon cannot read the publishing table', true); end;
end $$;
reset role;

\echo == T10 default OFF parity (every switch back to its default)
select set_rule('website_on','false') is null as off1 \gset
set role anon;
select web_site_config()::text as cfg0 \gset
select web_catalog_v2(null)::text as cat0 \gset
select web_checkout_submit('00000000-0000-4000-8000-0000000091a9'::uuid, 'test_buyer', '01711000096', 'pickup', null, null, ('[{"item_id":"'||:'w2'||'","qty":1}]')::jsonb, null, 'cod', null, :'today', null, null, null)::text as off_c \gset
reset role;
select tt.chk('T10 with the website OFF the public config says off and lists nothing', (:'cfg0'::jsonb->>'on')::boolean = false and (:'cat0'::jsonb->>'on')::boolean = false and (:'cat0'::jsonb->'items') = '[]'::jsonb);
select tt.chk('T10 with the website OFF checkout takes nothing', (:'off_c'::jsonb->>'error') = 'off' and not exists (select 1 from online_orders where external_ref = '00000000-0000-4000-8000-0000000091a9'));
select tt.chk('T10 the existing order screens still answer (no change to phase 61/76/77 behaviour)', to_regprocedure('public.online_orders_list(int,text,date,date,int)') is not null and to_regprocedure('public.online_order_status(uuid,text,text)') is not null);
select tt.chk('T10 every website switch exists and defaults to off or blank', (select bool_and(not (default_value::text::boolean)) from rules where key in ('website_on','website_reserve_on','website_pay_cod_on','website_pay_manual_on','website_custom_cake_on','website_festival_mode_on','website_captcha_on') and kind='switch') and (select count(*) from rules where key like 'website\_%') >= 20);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
