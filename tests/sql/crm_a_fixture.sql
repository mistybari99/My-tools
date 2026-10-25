-- CRM-A fixture, PART 2 (needs phases 300-302): the side tables and the new columns for customer one, on top of crm_a_fixture_core.sql. Test data only (test_* names).
-- Included by supabase/phase302_test.sql.
\ir crm_a_fixture_core.sql
\set ON_ERROR_STOP on
insert into user_grants (user_id, grant_code, location_id) values (:'u_v','crm_view',null),(:'u_cv','crm_contact_view',null) on conflict do nothing;
update customers set language = 'en', preferred_location_id = 1, type_code = 'party', credit_days = 15 where id = :'c1';
insert into customer_phones (customer_id, phone, label, wa_ok) values (:'c1', '01711032011', 'home', true);
insert into customer_phones (customer_id, phone, label) values (:'c2', '01711032001', 'work');          -- customer two lists customer one's MAIN number as an extra: a shared number
insert into customer_addresses (customer_id, label, address, area, landmark, delivery_note, is_default) values (:'c1', 'office', 'test_addr_office_1', 'test_area', 'near test_mosque', 'ring twice', true);
insert into customer_dates (customer_id, kind, person_label, month, day, year, remind_days_before) values (:'c1', 'birthday', 'Spouse', 7, 4, 1992, 7), (:'c1', 'anniversary', 'Parents', 2, 29, null, null);
insert into crm_tags (code, label) values ('test_tag', 'Test tag') on conflict do nothing;
insert into customer_tags (customer_id, tag_id) select :'c1', id from crm_tags where code = 'test_tag';
insert into crm_notes (customer_id, kind, body, created_by, created_staff, created_at) values (:'c1', 'call', 'test_note_new', :'u_v', 'test_viewer302', now() - interval '3 days'), (:'c1', 'note', 'test_note_retired', :'u_v', 'test_viewer302', now() - interval '4 days');
update crm_notes set retired_at = now(), retire_reason = 'test' where body = 'test_note_retired';

