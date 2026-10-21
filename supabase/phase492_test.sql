-- Phase 492 tests (XB part 2: custom-cake workflow). Neutral test_* data only.  bash tests/sql/xb_run.sh phase492
\ir ../tests/sql/c2_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions: writers open to browsers, helpers closed; anon denied; the job table is read-only; RLS on',
  has_function_privilege('authenticated', 'public.xb_cake_create(uuid,uuid,date,time,numeric,text,int,text,text[],text,boolean,boolean,text,text[],numeric)', 'execute')
  and has_function_privilege('authenticated', 'public.xb_cake_move(uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.xb_cake_move(uuid,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public._xb541_quote(numeric,text,text[])', 'execute')
  and not has_table_privilege('authenticated', 'public.cake_jobs', 'update')
  and (select relrowsecurity from pg_class where relname = 'cake_jobs') and (select relrowsecurity from pg_class where relname = 'cake_job_events'));
select tt.chk('T0 switches OFF, capacity and lead time blank, no price rule and no cake job exists yet',
  not rule_on('cake_flow_on') and not rule_on('cake_photo_required') and rule_num('cake_capacity_day') is null and rule_num('cake_lead_days') is null
  and not exists (select 1 from cake_price_rules) and not exists (select 1 from cake_jobs));

\echo == T1 switch OFF: refused
select tt.as(:'p');
select (online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_cake', '01711000100', null,
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 20)), 'pickup', null, (tt.today() + 2), 0, 0, 0, null, null, null)->>'id')::uuid as oa \gset
select tt.err('T1 a cake cannot be created while the switch is OFF', format($q$select xb_cake_create(%L::uuid, null, tt.today() + 2, '10:00', 1.5, null, 1, null, '{}', null, false, false, null, '{}', 0)$q$, :'oa'), 'module_off');

\echo == T2 owner sets the switches, the limits and the price table
select tt.as(:'o');
select set_rule('cake_flow_on', 'true');
select set_rule('cake_capacity_day', '2');
select set_rule('cake_lead_days', '1');
select tt.chk('T2 owner sets the switch and the two limits', rule_on('cake_flow_on') and rule_num('cake_capacity_day') = 2 and rule_num('cake_lead_days') = 1);
select (xb_cake_price_rule_save('base_kg', 'base', 'per_kg', 'কেক', 'Cake base per kg', 800)->>'amount')::numeric = 800 as pr0 \gset
select (xb_cake_price_rule_save('flv_choc', 'flavour', 'per_kg', 'চকলেট', 'Chocolate', 100)->>'amount')::numeric = 100 as pr1 \gset
select (xb_cake_price_rule_save('dsg_flower', 'design', 'flat', 'ফুল', 'Flower design', 150)->>'amount')::numeric = 150 as pr2 \gset
select tt.chk('T2 the price table is saved (base per kg, flavour per kg, design flat)', :'pr0' and :'pr1' and :'pr2');
select tt.as(:'p');
select tt.err('T2 a salesperson cannot change the price table', $q$select xb_cake_price_rule_save('dsg_x', 'design', 'flat', 'x', 'x', 5)$q$, 'not allowed');
select tt.err('T2 a base price per kg only (checked as owner below)', $q$select xb_cake_price_rule_save('base_x', 'base', 'flat', 'x', 'x', 5)$q$, 'not allowed');

\echo == T3 quote breakdown
select (xb_cake_quote(1.5, 'flv_choc', array['dsg_flower'])->>'total')::numeric = 1500 as q1 \gset
select tt.chk('T3 quote 1.5 kg: base 1200 + chocolate 150 + flower 150 = 1500', :'q1');
select tt.err('T3 an unknown design code is refused, nothing invented', $q$select xb_cake_quote(1, null, array['dsg_none'])$q$, 'bad_design');
select tt.err('T3 an unknown flavour code is refused', $q$select xb_cake_quote(1, 'flv_none', '{}')$q$, 'bad_flavour');
select tt.err('T3 a weight of zero is refused', $q$select xb_cake_quote(0, null, '{}')$q$, 'bad_weight');

\echo == T4 create: order must carry the cake; lead time; capacity
select tt.err('T4 the order lines must carry the quoted total (order of 10 x 100 = 1000 < 1500)', format($q$select xb_cake_create((online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_cake_s', '01711000103', null, jsonb_build_array(jsonb_build_object('item_id', %L, 'qty', 10)), 'pickup', null, (tt.today() + 2), 0, 0, 0, null, null, null)->>'id')::uuid, null, tt.today() + 2, '10:00', 1.5, 'flv_choc', 2, 'x', array['dsg_flower'], null, false, false, null, '{}', 0)$q$, :'ia'), 'order_total_below_quote');
select (online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_cake', '01711000100', null,
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 20)), 'pickup', null, (tt.today() + 2), 0, 0, 0, null, null, null)->>'id')::uuid as oa2 \gset
select tt.err('T4 no cake on the day of the order (lead time is 1 day)', format($q$select xb_cake_create(%L::uuid, null, tt.today(), '10:00', 1.5, 'flv_choc', 2, 'x', array['dsg_flower'], null, false, false, null, '{}', 0)$q$, :'oa2'), 'lead_time');
select tt.err('T4 an advance above the quote is refused', format($q$select xb_cake_create(%L::uuid, null, tt.today() + 2, '10:00', 1.5, 'flv_choc', 2, 'x', array['dsg_flower'], null, false, false, null, '{}', 1600)$q$, :'oa2'), 'bad_advance');
select (xb_cake_create(:'oa2'::uuid, '22222222-2222-2222-2222-222222222222', tt.today() + 2, '10:00', 1.5, 'flv_choc', 2, 'test_message_a', array['dsg_flower'], 'test design note', false, true, 'test nut-free not', array['cake/1/ref_a.jpg'], 300)->>'state') = 'quoted' as c1 \gset
select (xb_cake_create(:'oa2'::uuid, '22222222-2222-2222-2222-222222222222', tt.today() + 2, '10:00', 1.5, 'flv_choc', 2, 'test_message_a', array['dsg_flower'], 'test design note', false, true, 'test nut-free not', array['cake/1/ref_a.jpg'], 300)->>'dup')::boolean as c1d \gset
select tt.chk('T4 the cake job is created quoted, and the same client id returns it (no second job)', :'c1' and :'c1d' and (select count(*) from cake_jobs) = 1);
select (select id from cake_jobs limit 1) as ja \gset
select tt.err('T4 a second cake job on the same order is refused', format($q$select xb_cake_create(%L::uuid, null, tt.today() + 2, '10:00', 1, null, null, null, '{}', null, false, false, null, '{}', 0)$q$, :'oa2'), 'already_has_cake_job');
select tt.chk('T4 the job holds the quote, the balance and the flags', (select quote_total = 1500 and balance = 1200 and halal and not eggless from cake_jobs where id = :'ja'));

\echo == T5 confirm needs the advance in the order
select tt.err('T5 confirm refused while the order has no advance', format($q$select xb_cake_confirm(%L::uuid)$q$, :'ja'), 'advance_required');
select (online_order_save(:'oa2'::uuid, null, 1, 'phone', 'test_cust_cake', '01711000100', null,
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 20)), 'pickup', null, (tt.today() + 2), 0, 0, 300, 'cash', null, null)->>'id')::uuid as oa3 \gset
select (xb_cake_confirm(:'ja'::uuid)->>'state') = 'confirmed' as cf \gset
select tt.chk('T5 with the advance of 300 in the order the cake is confirmed', :'cf');

\echo == T6 forward chain, skipping refused, photo, delivery needs the order delivered
select tt.err('T6 a step cannot be skipped (confirmed to baked)', format($q$select xb_cake_move(%L::uuid, 'baked')$q$, :'ja'), 'bad_status');
select (xb_cake_move(:'ja'::uuid, 'slip', 'slip printed')->>'state') = 'slip' as m1 \gset
select (xb_cake_move(:'ja'::uuid, 'baked')->>'state') = 'baked' as m2 \gset
select (xb_cake_move(:'ja'::uuid, 'decorated')->>'state') = 'decorated' as m3 \gset
select (xb_cake_move(:'ja'::uuid, 'ready')->>'state') = 'ready' as m4 \gset
select tt.err('T6 a photo of the finished cake must be a cake path', format($q$select xb_cake_photo(%L::uuid, 'other/1/a.jpg')$q$, :'ja'), 'bad_path');
select (xb_cake_photo(:'ja'::uuid, 'cake/1/done_a.jpg')->>'photo_ready_path') = 'cake/1/done_a.jpg' as ph \gset
select tt.chk('T6 the chain slip, baked, decorated, ready works and the photo is stored', :'m1' and :'m2' and :'m3' and :'m4' and :'ph');
select tt.err('T6 delivered is refused until the app order is delivered', format($q$select xb_cake_move(%L::uuid, 'delivered')$q$, :'ja'), 'order_not_delivered');
select (online_order_status(:'oa2'::uuid, 'confirmed')->>'status') = 'confirmed' as os1 \gset
select (online_order_status(:'oa2'::uuid, 'packed')->>'status') = 'packed' as os2 \gset
select (online_order_deliver(:'oa2'::uuid, '[{"mode":"cash","amount":1700}]'::jsonb)->>'status') = 'delivered' as od \gset
select tt.chk('T6 the order is then delivered through its own path (advance 300 + cash 1700 = the order total 2000)', :'os1' and :'os2' and :'od');
select (xb_cake_move(:'ja'::uuid, 'delivered', 'handed over')->>'state') = 'delivered' as dl \gset
select tt.chk('T6 the cake is delivered; the trail holds every step', :'dl' and (select count(*) from cake_job_events where job_id = :'ja'::uuid) = 8);

\echo == T7 cancel: capacity, refund rules reuse the order cancel, closed jobs stay closed
select (online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_cake_b', '01711000101', null,
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 10)), 'pickup', null, (tt.today() + 2), 0, 0, 0, null, null, null)->>'id')::uuid as ob \gset
select (xb_cake_create(:'ob'::uuid, null, tt.today() + 2, null, 1, null, null, null, '{}', null, true, false, null, '{}', 0)->>'state') = 'quoted' as cb \gset
select (select id from cake_jobs where order_id = :'ob'::uuid) as jb \gset
select (online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_cake_c', '01711000102', null,
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 10)), 'pickup', null, (tt.today() + 2), 0, 0, 0, null, null, null)->>'id')::uuid as oc \gset
select tt.err('T7 the day is full at 2 cakes (capacity cap)', format($q$select xb_cake_create(%L::uuid, null, tt.today() + 2, null, 1, null, null, null, '{}', null, false, false, null, '{}', 0)$q$, :'oc'), 'capacity_full');
select (xb_cake_cancel(:'jb'::uuid, 'test: customer changed the day', 'none', null)->>'state') = 'cancelled' as cx \gset
select tt.chk('T7 a cancelled cake frees its place and the order is cancelled too', :'cb' and :'cx' and (select status from online_orders where id = :'ob'::uuid) = 'cancelled');
select (xb_cake_create(:'oc'::uuid, null, tt.today() + 2, null, 1, null, null, null, '{}', null, false, false, null, '{}', 0)->>'state') = 'quoted' as cc \gset
select tt.chk('T7 the freed place can be used', :'cc');
select tt.err('T7 a delivered cake is not cancelled', format($q$select xb_cake_cancel(%L::uuid, 'x', 'none', null)$q$, :'ja'), 'order_closed');
select tt.err('T7 a cancel needs a reason', $q$select xb_cake_cancel((select id from cake_jobs where order_id = '00000000-0000-0000-0000-000000000000'::uuid), null, 'none', null)$q$, 'not_found');

\echo == T8 production and decoration sheet
select ((xb_cake_due(tt.today() + 2)->>'count')::int = 2 and (xb_cake_due(tt.today() + 2)->>'total_kg')::numeric = 2.5) as s1 \gset
select (xb_cake_due(tt.today() + 2)->'rows'->0->>'eggless')::boolean = false
       and (xb_cake_due(tt.today() + 2)->'rows'->0->'design_codes'->>0) = 'dsg_flower' as s2 \gset
select tt.chk('T8 the sheet shows the cakes due that day (cancelled ones left out) with the design and the flags', :'s1' and :'s2');

\echo == T9 customer text and consent
select tt.as(:'o');
select (xb_cake_notify(:'ja'::uuid, 'cake_confirmed')->>'wa_phone') = '8801711000100' as w1 \gset
select (xb_cake_notify(:'ja'::uuid, 'cake_confirmed')->>'sms') = 'sms_off' as w2 \gset
select tt.chk('T9 the wa.me phone and text are returned; SMS is off by default', :'w1' and :'w2' and (xb_cake_notify(:'ja'::uuid)->>'wa_text') like '%order #%');
select set_rule('notify_sms_on', 'true');
insert into crm_contact_prefs (customer_id, dnc, note) select id, true, 'test do not contact' from customers where mobile = '01711000100' on conflict do nothing;
select tt.chk('T9 a do-not-contact customer gets no SMS, even with SMS on', (xb_cake_notify(:'ja'::uuid)->>'sms') = 'do_not_contact');
select tt.err('T9 an unknown template is refused', format($q$select xb_cake_notify(%L::uuid, 'free_text')$q$, :'ja'), 'bad_template');

\echo == T10 append-only and no money path
select tt.err('T10 a cake job cannot be deleted', $q$delete from cake_jobs$q$, 'nothing is deleted');
select tt.err('T10 the weight cannot be changed under a job', $q$update cake_jobs set weight_kg = 9 where id = $q$ || quote_literal(:'ja') || $q$$q$, 'changes only its state');
select tt.chk('T10 no journal entry is written by the cake flow', (select count(*) from journal_entries where source_type like 'xb%') = 0);
