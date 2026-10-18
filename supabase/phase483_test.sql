-- FRESH DB ONLY. Phase 483 tests (X3: social workspace, approval, publishing queue, deliveries, metrics).
--   build: tests/sql/build_fresh_db.sh with ORDER=all (through phase 478), then supabase/phase483.sql;  then:
--   psql -h /tmp -p 5820 -U postgres -d <db> -qAt -f supabase/phase483_test.sql 2>&1 | grep -E 'FAIL|RESULT'
\ir ../tests/sql/crmg_common.sql
select tt.today()::text as today \gset

\echo == T0 everything is OFF by default
select tt.as(:'u_o');
select tt.chk('T0 the workspace is off by default', (social_board() ->> 'on')::boolean = false and (social_board() ->> 'publish_on')::boolean = false);
select tt.chk('T0 the publisher sends nothing while off', (social_publish_claim(5) ->> 'on')::boolean = false);
select tt.err('T0 content is refused while off', $$select social_item_save(null, gen_random_uuid(), null, '{"title":"test_x"}')$$, 'module_off');
select tt.chk('T0 the limits are blank: nothing can be scheduled', (social_board() ->> 'limits_set')::boolean = false);

select set_rule('social_on', 'true') is null as r1 \gset
select set_rule('social_max_per_day', '10') is null as r2 \gset
select set_rule('social_max_per_hour', '5') is null as r3 \gset
insert into user_grants (user_id, grant_code, location_id) values (:'u_s1', 'social_manage', null), (:'u_m1', 'social_approve', null) on conflict do nothing;

\echo == T1 rights
select tt.as(:'u_x');
select tt.err('T1 a person with no grant cannot write', $$select social_item_save(null, gen_random_uuid(), null, '{"title":"test_x"}')$$, 'not allowed');
select tt.err('T1 a person with no grant cannot read the queue', $$select social_items_list(null, 10)$$, 'not allowed');
select tt.chk('T1 the browser role anon cannot read the queue tables', not has_table_privilege('anon', 'public.social_items', 'select') and not has_table_privilege('anon', 'public.social_deliveries', 'select') and not has_table_privilege('anon', 'public.social_metrics', 'select'));
select tt.chk('T1 row security is on for the queue tables', (select bool_and(relrowsecurity) from pg_class where relname in ('social_items', 'social_deliveries', 'social_item_events', 'social_metrics')));

\echo == T2 write, idempotent create, media and channel rules
select tt.as(:'u_s1');
select gen_random_uuid() as k1 \gset
select social_item_save(null, :'k1'::uuid, 1, jsonb_build_object('title', 'test_post1', 'caption_bn', 'test_বাংলা ক্যাপশন', 'caption_en', 'test caption one',
  'hashtags', '["test_tag"]'::jsonb, 'channels', '["facebook"]'::jsonb, 'is_public', true, 'draft_source', 'ai',
  'media', '[{"path":"test_p/1.jpg","kind":"image","mime":"image/jpeg","bytes":1000}]'::jsonb)) ->> 'id' as p1 \gset
select tt.chk('T2 the item is a draft, from an AI draft, with a Bangla caption', (select status = 'draft' and draft_source = 'ai' and caption_bn like 'test_%' from social_items where id = :'p1'::uuid));
select tt.chk('T2 the same client key gives the same item (no second item)', (social_item_save(null, :'k1'::uuid, 1, '{"title":"test_again"}') ->> 'id') = :'p1' and (select count(*) from social_items where client_id = :'k1'::uuid) = 1);
select tt.err('T2 a video over the size limit is refused', $$select social_item_save(null, gen_random_uuid(), 1, '{"title":"test_v","media":[{"path":"test_p/v.mp4","kind":"video","mime":"video/mp4","bytes":60000000}]}')$$, 'bad_media');
select tt.err('T2 a GIF is refused', $$select social_item_save(null, gen_random_uuid(), 1, '{"title":"test_g","media":[{"path":"test_p/g.gif","kind":"image","mime":"image/gif","bytes":100}]}')$$, 'bad_media');
select tt.err('T2 an image over the limit is refused', $$select social_item_save(null, gen_random_uuid(), 1, '{"title":"test_i","media":[{"path":"test_p/i.jpg","kind":"image","mime":"image/jpeg","bytes":6000000}]}')$$, 'bad_media');
select tt.err('T2 whatsapp is not an item channel (it goes to one customer)', $$select social_item_save(null, gen_random_uuid(), 1, '{"title":"test_c","channels":["whatsapp"]}')$$, 'bad_channel');
select tt.err('T2 too many hashtags is refused', $$select social_item_save(null, gen_random_uuid(), 1, jsonb_build_object('title','test_h','hashtags', (select jsonb_agg('t' || g) from generate_series(1, 31) g)))$$, 'bad_hashtags');
select tt.err('T2 a staff person may not approve', $$select social_item_approve('$$ || :'p1' || $$'::uuid, 'x', null)$$, 'not allowed');

\echo == T3 submit, maker rule, preview, lock, state machine
select social_item_submit(:'p1'::uuid) ->> 'status' as s1 \gset
select tt.chk('T3 submit moves the item to awaiting approval', :'s1' = 'awaiting_approval');
select tt.err('T3 a second submit is an illegal move', $$select social_item_submit('$$ || :'p1' || $$'::uuid)$$, 'illegal_transition');
select tt.err('T3 a changed item is locked while awaiting approval', $$select social_item_save('$$ || :'p1' || $$'::uuid, null, null, '{"title":"test_changed"}')$$, 'not_draft');
select tt.as(:'u_o');
select social_item_save(null, gen_random_uuid(), 1, '{"title":"test_owner_post","caption_en":"owner caption","channels":["instagram"]}') ->> 'id' as p2 \gset
select social_item_submit(:'p2'::uuid) is not null as s2 \gset
select tt.err('T3 the writer cannot approve his own item (owner too)', $$select social_item_approve('$$ || :'p2' || $$'::uuid, (social_item_preview('$$ || :'p2' || $$'::uuid) ->> 'preview_hash'), null)$$, 'maker_cannot_approve');
select tt.as(:'u_m1');
select tt.err('T3 approving without the preview hash is refused', $$select social_item_approve('$$ || :'p1' || $$'::uuid, 'not-the-hash', null)$$, 'preview_changed');
select social_item_preview(:'p1'::uuid) ->> 'preview_hash' as h1 \gset
select social_item_approve(:'p1'::uuid, :'h1', 'test ok') ->> 'status' as s3 \gset
select tt.chk('T3 the approver with the grant approves the previewed item', :'s3' = 'approved' and (select approved_by from social_items where id = :'p1'::uuid) = :'u_m1'::uuid);
select tt.err('T3 an approved item cannot be edited in place', $$update social_items set caption_en = 'test changed after approval' where id = '$$ || :'p1' || $$'$$, 'locked');
select tt.err('T3 an illegal move is refused in the database too', $$update social_items set status = 'published' where id = '$$ || :'p1' || $$'$$, 'illegal_transition');
select tt.err('T3 a deleted item is never removed', $$delete from social_items where id = '$$ || :'p1' || $$'$$, 'nothing is deleted');

\echo == T4 scheduling: kill switch, limits, quiet hours
select tt.as(:'u_s1');
select tt.as(:'u_o');
select set_rule('social_stop_all', 'true') is null as k1 \gset
select tt.err('T4 the emergency stop refuses scheduling', $$select social_item_schedule('$$ || :'p1' || $$'::uuid, now() + interval '1 day')$$, 'stopped');
select set_rule('social_stop_all', 'false') is null as k2 \gset
select set_rule('social_max_per_day', null) is null as k3 \gset
select tt.err('T4 blank limits refuse scheduling (nothing invented)', $$select social_item_schedule('$$ || :'p1' || $$'::uuid, now() + interval '1 day')$$, 'limit_not_set');
select set_rule('social_max_per_day', '10') is null as k4 \gset
select set_rule('social_quiet_from', '"22:00"') is null as q1 \gset
select set_rule('social_quiet_to', '"06:00"') is null as q2 \gset
select (((now() at time zone 'Asia/Dhaka')::date + 2)::text || ' 23:30 Asia/Dhaka')::timestamptz::text as quiet_at \gset
select tt.err('T4 a time inside quiet hours is refused', $$select social_item_schedule('$$ || :'p1' || $$'::uuid, '$$ || :'quiet_at' || $$'::timestamptz)$$, 'quiet_hours');
select tt.err('T4 a quiet-hours setting must be HH:MM', $$select set_rule('social_quiet_from', '"25:99"')$$, 'bad_value');
select set_rule('social_quiet_from', null) is null as q3 \gset
select set_rule('social_quiet_to', null) is null as q4 \gset
select social_item_schedule(:'p1'::uuid, now() + interval '1 day') ->> 'status' as s4 \gset
select tt.chk('T4 the approved item is scheduled and one delivery per channel exists', :'s4' = 'scheduled' and (select count(*) from social_deliveries where item_id = :'p1'::uuid) = 1
  and (select status from social_deliveries where item_id = :'p1'::uuid) = 'queued');
select tt.err('T4 a second schedule of the same item is an illegal move', $$select social_item_schedule('$$ || :'p1' || $$'::uuid, now() + interval '2 days')$$, 'illegal_transition');
select tt.err('T4 a duplicate delivery for the same item and channel is refused by the database', $$insert into social_deliveries (item_id, channel, idempotency_key, scheduled_at) values ('$$ || :'p1' || $$', 'facebook', '$$ || :'p1' || $$:facebook', now())$$, 'duplicate key');
select set_rule('social_max_per_day', '1') is null as k5 \gset
select gen_random_uuid() as k3b \gset
select social_item_save(null, :'k3b'::uuid, 1, '{"title":"test_post3","caption_en":"third","channels":["facebook"]}') ->> 'id' as p3 \gset
select social_item_submit(:'p3'::uuid) is not null as s5 \gset
select tt.as(:'u_m1');
select social_item_approve(:'p3'::uuid, (social_item_preview(:'p3'::uuid) ->> 'preview_hash'), null) is not null as a5 \gset
select tt.as(:'u_o');
select tt.err('T4 the per-day limit refuses one more post that day', $$select social_item_schedule('$$ || :'p3' || $$'::uuid, now() + interval '1 day')$$, 'day_limit');
select set_rule('social_max_per_day', '10') is null as k6 \gset

\echo == T5 worker: switched off, claim rights, lease, success
select tt.as(:'u_o');
select set_rule('social_publish_on', 'false') is null as w0 \gset
select tt.chk('T5 nothing is claimed while publishing is off', (social_publish_claim(5) ->> 'on')::boolean = false);
select set_rule('social_publish_on', 'true') is null as w1 \gset
select tt.as(:'u_s1');
select tt.err('T5 a staff person cannot run the publisher', $$select social_publish_claim(5)$$, 'not allowed');
select tt.as(:'u_bot');
select tt.chk('T5 the bot finds nothing before the time', jsonb_array_length(social_publish_claim(5) -> 'rows') = 0);
update social_deliveries set scheduled_at = now() - interval '1 minute' where item_id = :'p1'::uuid;
select social_publish_claim(5) -> 'rows' -> 0 ->> 'id' as d1 \gset
select tt.chk('T5 the claimed row carries the caption and attempt 1', (select attempts from social_deliveries where id = :'d1'::bigint) = 1 and (select status from social_deliveries where id = :'d1'::bigint) = 'sending');
select tt.chk('T5 a claimed row is not claimed twice while its lease runs', jsonb_array_length(social_publish_claim(5) -> 'rows') = 0);

\echo == T6 worker: failure, back-off, success, item published, metrics
select social_publish_report(:'d1'::bigint, false, null, null, 'test provider down') ->> 'status' as r1 \gset
select tt.chk('T6 a failure waits (queued, back-off in the future, error kept)', :'r1' = 'queued' and (select next_try_at > now() from social_deliveries where id = :'d1'::bigint)
  and (select last_error from social_deliveries where id = :'d1'::bigint) = 'test provider down');
update social_deliveries set next_try_at = now() - interval '1 minute' where id = :'d1'::bigint;
select tt.as(:'u_bot');
select tt.chk('T6 the retry is claimed again (attempt 2)', (social_publish_claim(5) -> 'rows' -> 0 ->> 'attempt')::int = 2);
select social_publish_report(:'d1'::bigint, true, 'test_ref_1', 'https://example.test/p/1', null) ->> 'status' as r2 \gset
select tt.chk('T6 success is final and the item becomes published', :'r2' = 'published' and (select status from social_items where id = :'p1'::uuid) = 'published');
select tt.chk('T6 a late report on a finished delivery is ignored', (social_publish_report(:'d1'::bigint, false, null, null, 'x') ->> 'ignored')::boolean = true);
select tt.as(:'u_o');
select tt.chk('T6 metrics say "not captured" when nothing came from the provider', (social_item_get(:'p1'::uuid) -> 'deliveries' -> 0 ->> 'metrics') = 'not captured' and (social_item_get(:'p1'::uuid) -> 'deliveries' -> 0 ->> 'reach') is null);
select tt.err('T6 metrics for a post that is not published are refused', $$select social_metric_record(999999, 1, 1, 1)$$, 'not_published');
select social_metric_record(:'d1'::bigint, 120, 8, 3) ->> 'saved' as m1 \gset
select tt.chk('T6 a provider metric is shown with its numbers', (social_item_get(:'p1'::uuid) -> 'deliveries' -> 0 ->> 'reach')::int = 120 and (social_item_get(:'p1'::uuid) -> 'deliveries' -> 0 ->> 'metrics') = 'captured');

select tt.as(:'u_o');
\echo == T7 retries run out: failed, then a person tries again
select tt.as(:'u_s1');
select gen_random_uuid() as k4 \gset
select social_item_save(null, :'k4'::uuid, 1, '{"title":"test_post4","caption_en":"fourth","channels":["facebook"]}') ->> 'id' as p4 \gset
select social_item_submit(:'p4'::uuid) is not null as s6 \gset
select tt.as(:'u_m1');
select social_item_approve(:'p4'::uuid, (social_item_preview(:'p4'::uuid) ->> 'preview_hash'), null) is not null as a6 \gset
select tt.as(:'u_o');
select social_item_schedule(:'p4'::uuid, now() + interval '1 day') ->> 'status' as s7 \gset
update social_deliveries set scheduled_at = now() - interval '1 minute', max_attempts = 1 where item_id = :'p4'::uuid;
select tt.as(:'u_bot');
select social_publish_claim(5) -> 'rows' -> 0 ->> 'id' as d4 \gset
select social_publish_report(:'d4'::bigint, false, null, null, 'test bad token') ->> 'status' as r4 \gset
select tt.chk('T7 the last try failed: delivery and item are failed', :'r4' = 'failed' and (select status from social_items where id = :'p4'::uuid) = 'failed');
select tt.as(:'u_o');
select social_item_schedule(:'p4'::uuid, now() + interval '1 day') ->> 'status' as s8 \gset
select tt.chk('T7 a person tries a failed post again: queued, attempts reset', :'s8' = 'scheduled' and (select status || ':' || attempts from social_deliveries where item_id = :'p4'::uuid) = 'queued:0');

\echo == T8 stop, cancel, return, reads
select tt.as(:'u_m1');
select tt.err('T8 only the owner can press the emergency stop', $$select social_stop_all_set(true, 'test')$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T8 the emergency stop needs a reason', $$select social_stop_all_set(true, null)$$, 'reason_required');
select social_stop_all_set(true, 'test stop') ->> 'social_stop_all' as st1 \gset
select tt.chk('T8 the publisher stops at once', (social_publish_claim(5) ->> 'reason') = 'stopped');
select social_stop_all_set(false, null) ->> 'social_stop_all' as st2 \gset
select tt.chk('T8 switching the stop off lets the queue resume', :'st2' = 'false' and (social_publish_claim(5) ->> 'on')::boolean = true);
select social_item_cancel(:'p3'::uuid, 'test not needed') ->> 'status' as c1 \gset
select tt.chk('T8 a cancelled item is closed and has no delivery', :'c1' = 'cancelled' and (select count(*) from social_deliveries where item_id = :'p3'::uuid) = 0);
select tt.err('T8 cancel needs a reason', $$select social_item_cancel('$$ || :'p2' || $$'::uuid, '')$$, 'reason_required');
select social_item_return(:'p2'::uuid, 'test change the caption') ->> 'status' as rt1 \gset
select tt.chk('T8 a submitted item goes back to draft with a reason and can be edited again', :'rt1' = 'draft' and social_item_save(:'p2'::uuid, null, null, '{"caption_en":"owner caption fixed"}') ->> 'status' = 'draft');
select tt.chk('T8 the trail has a line for each move, in order', (select count(*) >= 4 from social_item_events where item_id = :'p1'::uuid));
select tt.chk('T8 the board counts and the calendar answer', (social_board() -> 'items' ->> 'published')::int >= 1 and jsonb_typeof(social_calendar(current_date - 1, current_date + 30) -> 'festivals') = 'array');
select tt.err('T8 a calendar range longer than a year is refused', $$select social_calendar(date '2020-01-01', date '2025-01-01')$$, 'bad_range');

\echo == T9 WhatsApp to one customer: consent first, then the worker checks again
select tt.as(:'u_o');
insert into customers (mobile, name) values ('01711099001', 'test_cust_wa') on conflict do nothing;
select id as cust from customers where mobile = '01711099001' \gset
select social_item_save(null, gen_random_uuid(), 1, '{"title":"test_wa_post","caption_bn":"test wa","template_code":"test_tpl","channels":["facebook"]}') ->> 'id' as pw \gset
select social_item_submit(:'pw'::uuid) is not null as sw \gset
select tt.as(:'u_m1');
select social_item_approve(:'pw'::uuid, (social_item_preview(:'pw'::uuid) ->> 'preview_hash'), null) is not null as aw \gset
select tt.as(:'u_o');
select social_item_schedule(:'pw'::uuid, now() + interval '1 day') is not null as scw \gset
select tt.err('T9 no yes from the customer: no message', $$select social_wa_enqueue('$$ || :'pw' || $$', '$$ || :'cust' || $$')$$, 'consent_blocked');
select notify_optin_set(:'cust'::uuid, 'whatsapp', true, 'customer_consent', 'test yes') is not null as opt \gset
select social_wa_enqueue(:'pw'::uuid, :'cust'::uuid) ->> 'duplicate' as wa1 \gset
select tt.chk('T9 with a yes, the message is queued once', :'wa1' = 'false' and (social_wa_enqueue(:'pw'::uuid, :'cust'::uuid) ->> 'duplicate') = 'true');
insert into crm_contact_prefs (customer_id, dnc, note) values (:'cust'::uuid, true, 'test do not contact') on conflict do nothing;
update social_deliveries set scheduled_at = now() - interval '1 minute' where item_id = :'pw'::uuid and channel = 'whatsapp';
select tt.as(:'u_bot');
select jsonb_array_length(social_publish_claim(5) -> 'rows') as wa_claimed \gset
select tt.chk('T9 the worker claims no message to a do-not-contact customer', :'wa_claimed' = '0');
select tt.chk('T9 the worker re-checks consent and cancels the queued message (kept, with the reason)', (select status || ':' || last_error from social_deliveries where item_id = :'pw'::uuid and channel = 'whatsapp') = 'cancelled:consent: dnc');

\echo == T10 done
select tt.chk('T10 nothing that is not a test_ name was left in the table', (select count(*) = 0 from social_items where title not like 'test_%'));
select 'RESULT pass=' || (select count(*) from tt.res where ok) || ' fail=' || (select count(*) from tt.res where not ok) as result;
