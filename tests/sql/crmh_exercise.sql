-- CRM-H before/after helper: switch EVERY CRM-H setting ON and use every write function on records that already exist (as the owner of the Wave 1 fixture).
-- Nothing here may change a figure: tests/sql/crmh_before_after.sh takes the same snapshots before and after this file and they must be identical.
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000092', false);
select set_rule('crm_complaints_on', 'true') is null as r1 \gset
select set_rule('crm_feedback_on', 'true') is null as r2 \gset
select set_rule('crm_complaint_sla_hours_medium', '24') is null as r3 \gset
select set_rule('crm_complaint_sla_hours_high', '4') is null as r4 \gset
select set_rule('crm_feedback_low_max', '2') is null as r5 \gset
select set_rule('crm_repeat_days', '30') is null as r6 \gset
select id as sa from sales where status = 'done' and location_id = 1 order by sold_at, receipt limit 1 \gset
select id as sb from sales where status = 'done' and location_id = 1 and id <> :'sa' order by sold_at, receipt limit 1 \gset
select _crmh_complaint_save(gen_random_uuid(), format('{"sale_id":"%s","category":"sick","severity":"high","description":"test exercise food safety"}', :'sa')::jsonb) ->> 'id' as c1 \gset
select _crmh_complaint_save(gen_random_uuid(), format('{"sale_id":"%s","category":"taste","description":"test exercise taste"}', :'sa')::jsonb) ->> 'id' as c2 \gset
select _crmh_complaint_assign(:'c1'::uuid, '00000000-0000-0000-0000-000000000092'::uuid, 'test') is not null as x1 \gset
select _crmh_complaint_note(:'c1'::uuid, 'contact', 'test called the customer') is not null as x2 \gset
select _crmh_complaint_move(:'c1'::uuid, 'in_progress', 'test started') is not null as x3 \gset
select _crmh_complaint_move(:'c1'::uuid, 'resolved', 'test explained', 'explained') is not null as x4 \gset
select _crmh_complaint_move(:'c1'::uuid, 'closed', 'test done') is not null as x5 \gset
select _crmh_complaint_move(:'c2'::uuid, 'closed_no_resolution', 'test could not reach', null, 'no_contact') is not null as x6 \gset
select id as rr from sale_returns where status = 'done' and location_id = 1 limit 1 \gset
select _crmh_complaint_save(gen_random_uuid(), format('{"sale_id":"%s","category":"broken","description":"test exercise return link"}', sale_id)::jsonb) ->> 'id' as c3 from sale_returns where id = :'rr' \gset
select _crmh_complaint_link_return(:'c3'::uuid, :'rr'::uuid) is not null as x7 \gset
select _crmh_feedback_add(gen_random_uuid(), format('{"sale_id":"%s","rating":1,"comment":"test exercise rating"}', :'sb')::jsonb) ->> 'id' as f1 \gset
select _crmh_feedback_followup(:'f1'::uuid, 'test called the customer') is not null as x8 \gset
select _crmh_sla_scan(false) is not null as x9 \gset
select _crmh_report('{}') is not null as x10 \gset
select _crmh_report('{"by":"item"}') is not null as x11 \gset
select _crmh_repeat_list('{}') is not null as x12 \gset
select _crmh_complaint_list('{"status":"all"}') is not null as x13 \gset
select _crmh_counts() is not null as x14 \gset
select 'exercise done: ' || (select count(*) from crm_complaints) || ' complaints, ' || (select count(*) from crm_feedback) || ' ratings, ' || (select count(*) from crm_complaint_returns) || ' linked returns, '
    || (select count(*) from exceptions where form_code = 'CRM') || ' CRM exception lines';
