-- CRM-G before/after helper: switch EVERYTHING of the package on and use every function once, as the owner of tests/sql/w1d_fixture.sql (092).
-- The books must not move: tests/sql/crmg_before_after.sh takes the same snapshots before and after this file and they must be identical.
-- Test data only (test_*).
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', false);
select set_rule('crm_lead_on', 'true'); select set_rule('crm_task_on', 'true'); select set_rule('crm_task_reminder_on', 'true'); select set_rule('online_orders_on', 'true');
select set_rule('crm_order_task_days', '1'); select set_rule('crm_lead_quote_valid_days', '14'); select set_rule('crm_lead_stale_days', '30');
update forms set enabled = true where code in ('20-1', '20-4');
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) select 'test_crmg_x', 'test_crmg_x', 'test_crmg_x', 'kg', 'kg', 'finished_good', false, 120 where not exists (select 1 from items where code = 'test_crmg_x');
insert into sales_channels (code, kind, name_bn, location_id, active) select 'test_crmg_x', 'phone', 'test_crmg_x', null, true where not exists (select 1 from sales_channels where code = 'test_crmg_x');
select id as it from items where code = 'test_crmg_x' \gset
select id as ch from sales_channels where code = 'test_crmg_x' \gset
-- a lead, a quote, an order, a task, a lost lead, a reopen, a form, a reminder run
select _crmg_lead_save(null, gen_random_uuid(), 1, format('{"contact_name":"test_ex_one","contact_phone":"01812340001","source":"phone","event_date":"%s"}', current_date + 9)::jsonb) ->> 'id' as l1 \gset
select _crmg_lead_note(:'l1'::uuid, 'call', 'test_ex note') is not null as n1 \gset
select _crmg_quote_save(:'l1'::uuid, null, format('{"items":[{"item_id":"%s","qty":3},{"item_id":"%s","qty":1,"price":80}],"discount":10,"send":true}', :'it', :'it')::jsonb) ->> 'status' as q1 \gset
select _crmg_lead_convert(:'l1'::uuid, gen_random_uuid(), 'online_order', format('{"channel_id":%s,"delivery_date":"%s","delivery_mode":"pickup"}', :'ch', current_date + 9)::jsonb) is not null as c1 \gset
select _crmg_lead_save(null, gen_random_uuid(), 1, '{"contact_name":"test_ex_two","contact_phone":"01812340002"}') ->> 'id' as l2 \gset
select _crmg_lead_stage(:'l2'::uuid, 'following_up', 'test_ex', jsonb_build_object('follow_up', (now() + interval '3 days')::text, 'make_task', true)) is not null as s2 \gset
select _crmg_lead_stage(:'l2'::uuid, 'lost', '', '{"lost_reason":"no_reply"}') is not null as s3 \gset
select _crmg_lead_reopen(:'l2'::uuid, 'test_ex came back') is not null as r2 \gset
select _crmg_quote_save(:'l2'::uuid, null, '{"items":[{"desc":"test_ex big","qty":2,"price":500}],"send":true,"valid_until":"2099-01-01"}') is not null as q2 \gset
select _crmg_lead_convert(:'l2'::uuid, gen_random_uuid(), 'form_20_4', '{}') is not null as c2 \gset
select _crmg_task_save(null, gen_random_uuid(), jsonb_build_object('title', 'test_ex task', 'due_at', (now() - interval '1 day')::text)) ->> 'id' as t1 \gset
select _crmg_task_snooze(:'t1'::uuid, null, 3) is not null as sn \gset
select _crmg_task_done(:'t1'::uuid, 'test_ex') is not null as dn \gset
select _crmg_my_tasks('team') is not null as mt \gset
select _crmg_lead_list('{}') is not null as li \gset
select _crmg_lead_board(null, null) is not null as bd \gset
select _crmg_lead_report(null, null, null) is not null as rp \gset
select _crmg_task_scan(false) is not null as sc \gset
select _crmg_tasks_sweep(false) is not null as sw \gset
select _crmg_settings() is not null as se \gset
select _crmg_readiness() is not null as rd \gset
