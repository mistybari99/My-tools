-- FRESH DB ONLY. Phase 301 tests (CRM-A write functions: extras, phones, delivery points, family dates, tags, notes, reveal).
--   Build a local throwaway database through phase 98 (or 99), paste phases 300, 301, 302 (twice each), then
--     psql -h /tmp -p 5571 -U postgres -d <db> -qAt -f supabase/phase301_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Roles: owner; cashier (salesperson: POS view + enter, place 1); manager (cashier + grant customer_manage); noter (cashier + grant crm_view);
-- reader (cash_controller: POS view only); outsider (storekeeper: no POS).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000030101'
\set u_c '00000000-0000-0000-0000-000000030102'
\set u_m '00000000-0000-0000-0000-000000030103'
\set u_n '00000000-0000-0000-0000-000000030104'
\set u_r '00000000-0000-0000-0000-000000030105'
\set u_x '00000000-0000-0000-0000-000000030106'
\set u_p '00000000-0000-0000-0000-000000030107'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.try(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'ok'; exception when others then return sqlerrm; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.acct() returns text language sql security definer as $$
  select (select count(*) from public.journal_entries) || '/' || (select count(*) from public.journal_lines) || '/' || (select count(*) from public.sales) || '/' || (select count(*) from public.sale_payments)
      || '/' || (select coalesce(sum(total),0) from public.sales) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner301@s.app','{"full_name":"test_owner301"}'), (:'u_c','test_cash301@s.app','{"full_name":"test_cash301"}'), (:'u_m','test_mgr301@s.app','{"full_name":"test_mgr301"}'),
 (:'u_n','test_noter301@s.app','{"full_name":"test_noter301"}'), (:'u_r','test_reader301@s.app','{"full_name":"test_reader301"}'), (:'u_x','test_outsider301@s.app','{"full_name":"test_outsider301"}'),
 (:'u_p','test_pending301@s.app','{"full_name":"test_pending301"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_c', :'u_m', :'u_n', :'u_r', :'u_x');
insert into user_roles values (:'u_o','owner'),(:'u_c','salesperson'),(:'u_m','salesperson'),(:'u_n','salesperson'),(:'u_r','cash_controller'),(:'u_x','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_c',1),(:'u_m',1),(:'u_n',1),(:'u_r',1),(:'u_x',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'u_m','customer_manage',null),(:'u_n','crm_view',null);
select tt.acct() as acct0 \gset
select tt.as(:'u_o');
insert into customers (mobile, name) values ('01711031001','test_cust_301a'),('01711031002','test_cust_301b'),('01711031003','test_cust_301c');
select id as ca from customers where mobile='01711031001' \gset
select id as cb from customers where mobile='01711031002' \gset
select id as cc from customers where mobile='01711031003' \gset

\echo == T0 switch OFF (default): every write is refused with crm_off and nothing is written
select tt.as(:'u_c');
select tt.err('T0 extras refused while crm_on is OFF', format($q$select crma_customer_extras_save(%L, '{"language":"bn"}')$q$, :'ca'), 'crm_off');
select tt.err('T0 phone refused while OFF', format($q$select crma_phone_add(%L, '01711031011')$q$, :'ca'), 'crm_off');
select tt.err('T0 address refused while OFF', format($q$select crma_address_save(%L, '{"address":"test_addr"}')$q$, :'ca'), 'crm_off');
select tt.err('T0 date refused while OFF', format($q$select crma_date_save(%L, '{"kind":"birthday","person_label":"Spouse","month":3,"day":4}')$q$, :'ca'), 'crm_off');
select tt.err('T0 tag set refused while OFF', $q$select crma_tag_set(gen_random_uuid(), 1)$q$, 'crm_off');
select tt.as(:'u_n');
select tt.err('T0 note refused while OFF', format($q$select crma_note_add(%L, 'test_note')$q$, :'ca'), 'crm_off');
select tt.chk('T0 nothing was written to the new tables', (select count(*) from customer_phones) + (select count(*) from customer_addresses) + (select count(*) from customer_dates) + (select count(*) from crm_notes) + (select count(*) from customer_tags) = 0);
select tt.as(:'u_m');
select tt.err('T0 the tag list cannot be edited while OFF', $q$select crma_tag_save(null, 'vip', 'VIP')$q$, 'crm_off');
select tt.as(:'u_c');
select tt.chk('T0 existing customer_save still works (creates and finds the duplicate) with CRM OFF',
  (select crma_ok from (select (customer_save(null, '{"mobile":"01711031099","name":"test_cust_301z"}'::jsonb, gen_random_uuid()) ->> 'dup')::boolean = false
        and (customer_save(null, '{"mobile":"01711031099","name":"test_cust_301z"}'::jsonb, gen_random_uuid()) ->> 'dup')::boolean = true crma_ok) z));
select tt.as(:'u_o');
select set_rule('crm_on', 'true'::jsonb) is null as s1 \gset

\echo == T1 customer extras
select tt.as(:'u_c');
select tt.chk('T1 cashier sets language and preferred outlet', (crma_customer_extras_save(:'ca', '{"language":"bn","preferred_location_id":1}') ->> 'saved')::boolean);
select tt.chk('T1 saved on the customer row', (select language = 'bn' and preferred_location_id = 1 from customers where id = :'ca'));
select tt.err('T1 cashier cannot set customer type', format($q$select crma_customer_extras_save(%L, '{"type_code":"party"}')$q$, :'ca'), 'not allowed');
select tt.err('T1 cashier cannot set credit days', format($q$select crma_customer_extras_save(%L, '{"credit_days":15}')$q$, :'ca'), 'not allowed');
select tt.err('T1 cashier cannot set the account owner', format($q$select crma_customer_extras_save(%L, jsonb_build_object('owner_user', %L))$q$, :'ca', :'u_m'), 'not allowed');
select tt.err('T1 a bad language is refused', format($q$select crma_customer_extras_save(%L, '{"language":"fr"}')$q$, :'ca'), 'bad_value');
select tt.err('T1 an unknown outlet is refused', format($q$select crma_customer_extras_save(%L, '{"preferred_location_id":9999}')$q$, :'ca'), 'location_not_found');
select tt.err('T1 an unreadable outlet is refused', format($q$select crma_customer_extras_save(%L, '{"preferred_location_id":"abc"}')$q$, :'ca'), 'bad_value');
select tt.err('T1 an unknown key is refused, not silently dropped', format($q$select crma_customer_extras_save(%L, '{"credit_limit":99999}')$q$, :'ca'), 'unknown_key');
select tt.err('T1 an unknown customer is refused', $q$select crma_customer_extras_save(gen_random_uuid(), '{"language":"en"}')$q$, 'customer_not_found');
select tt.as(:'u_m');
select crma_customer_extras_save(:'ca', jsonb_build_object('type_code','party','credit_days',15,'owner_user',:'u_c')) ->> 'saved' as r \gset
select tt.chk('T1 manager sets type, credit terms and account owner', :'r' = 'true' and (select type_code = 'party' and credit_days = 15 and owner_user = :'u_c'::uuid from customers where id = :'ca'));
select tt.chk('T1 the POS type (retail / wholesale) is NOT changed by the richer type', (select type = 'retail' from customers where id = :'ca'));
select tt.err('T1 an unknown customer type is refused', format($q$select crma_customer_extras_save(%L, '{"type_code":"zzz"}')$q$, :'ca'), 'type_not_found');
select tt.err('T1 credit days must be a whole number', format($q$select crma_customer_extras_save(%L, '{"credit_days":15.5}')$q$, :'ca'), 'bad_number');
select tt.err('T1 credit days over 365 refused', format($q$select crma_customer_extras_save(%L, '{"credit_days":400}')$q$, :'ca'), 'bad_number');
select tt.err('T1 a person who is not an active user cannot be the account owner', format($q$select crma_customer_extras_save(%L, jsonb_build_object('owner_user', %L))$q$, :'ca', :'u_p'), 'user_not_found');
select crma_customer_extras_save(:'ca', '{"credit_days":null}') ->> 'saved' as r \gset
select tt.chk('T1 a field is cleared with null; the others stay', :'r' = 'true' and (select credit_days is null and type_code = 'party' and language = 'bn' from customers where id = :'ca'));
select crma_customer_extras_save(:'ca', '{"language":"bn"}', gen_random_uuid()) ->> 'saved' as r \gset
select tt.chk('T1 a repeat of the same call changes nothing', :'r' = 'true' and (select language = 'bn' and type_code = 'party' from customers where id = :'ca'));
select tt.as(:'u_r');
select tt.err('T1 a read-only person (POS view only) cannot write', format($q$select crma_customer_extras_save(%L, '{"language":"en"}')$q$, :'ca'), 'not allowed');
select tt.as(:'u_x');
select tt.err('T1 a person without POS cannot write', format($q$select crma_customer_extras_save(%L, '{"language":"en"}')$q$, :'ca'), 'not allowed');

\echo == T2 extra phones
select tt.as(:'u_c');
select tt.err('T2 extra phones are off by default (crm_second_phone_on)', format($q$select crma_phone_add(%L, '01711031011')$q$, :'ca'), 'second_phone_off');
select tt.as(:'u_o');
select set_rule('crm_second_phone_on', 'true'::jsonb) is null as s2 \gset
select tt.as(:'u_c');
select crma_phone_add(:'ca', '+880 1711-031011', 'home', true, 'test_home_line', gen_random_uuid()) ->> 'id' as ph1 \gset
select tt.chk('T2 an extra phone is stored normalised with its label and WhatsApp flag', (select phone = '01711031011' and label = 'home' and wa_ok and active and note = 'test_home_line' from customer_phones where id = :'ph1'::bigint));
select tt.err('T2 a bad phone is refused', format($q$select crma_phone_add(%L, '12345')$q$, :'ca'), 'bad_mobile');
select tt.err('T2 an empty phone is refused', format($q$select crma_phone_add(%L, '  ')$q$, :'ca'), 'bad_mobile');
select tt.err('T2 letters in a phone are refused', format($q$select crma_phone_add(%L, '01711abc011')$q$, :'ca'), 'bad_mobile');
select tt.err('T2 a bad label is refused', format($q$select crma_phone_add(%L, '01711031012', 'fax')$q$, :'ca'), 'bad_value');
select tt.chk('T2 the same number again is a duplicate, no second row', (crma_phone_add(:'ca', '01711031011') ->> 'dup')::boolean and (select count(*) from customer_phones where customer_id = :'ca' and phone = '01711031011') = 1);
select tt.chk('T2 the main number as an extra is a duplicate (primary)', (crma_phone_add(:'ca', '01711031001') ->> 'primary')::boolean and (select count(*) from customer_phones where customer_id = :'ca') = 1);
select gen_random_uuid() as cl1 \gset
select crma_phone_add(:'ca', '01711031013', 'work', false, null, :'cl1'::uuid) ->> 'id' as ph2 \gset
select tt.chk('T2 a retry with the same client id changes nothing', (crma_phone_add(:'ca', '01711031013', 'work', false, null, :'cl1'::uuid) ->> 'dup')::boolean and (select count(*) from customer_phones where customer_id = :'ca') = 2);
select crma_phone_add(:'cb', '01711031001') as r \gset
select tt.chk('T2 a number held as the MAIN number of another customer is accepted and reported', (:'r'::jsonb ->> 'warning') = 'phone_shared' and (:'r'::jsonb -> 'shared_with' -> 0 ->> 'id') = :'ca'
  and (select count(*) from customer_phones where customer_id = :'cb' and phone = '01711031001') = 1);
select crma_phone_add(:'cc', '01711031011') as r \gset
select tt.chk('T2 a number held as an EXTRA number of another customer is accepted and reported', (:'r'::jsonb ->> 'warning') = 'phone_shared');
select tt.chk('T2 a sale is never blocked: a customer with a shared number still exists once per number', (select count(*) from customers where mobile in ('01711031001','01711031011')) = 1);
select tt.err('T2 not more than 10 extra numbers', format($q$select crma_phone_add(%L, '0171103' || (2000 + g)::text) from generate_series(1, 12) g$q$, :'cc'), 'too_many_phones');
select crma_phone_retire(:'ph2'::bigint) ->> 'dup' as r \gset
select tt.chk('T2 retire an extra phone', :'r' = 'false' and (select not active from customer_phones where id = :'ph2'::bigint));
select tt.chk('T2 retire twice is a duplicate', (crma_phone_retire(:'ph2'::bigint) ->> 'dup')::boolean);
select tt.err('T2 retire an unknown phone', $q$select crma_phone_retire(999999)$q$, 'phone_not_found');
select tt.chk('T2 after retiring, the same number may be added again', (crma_phone_add(:'ca', '01711031013') ->> 'dup')::boolean = false);
select tt.as(:'u_c');
select tt.err('T2 a cashier cannot change the main number', format($q$select crma_phone_make_primary(%L::bigint, 'customer asked')$q$, :'ph1'), 'not allowed');
select tt.as(:'u_m');
select tt.err('T2 the manager needs a reason', format($q$select crma_phone_make_primary(%L::bigint, 'ab')$q$, :'ph1'), 'reason_required');
select crma_phone_add(:'cc', '01711031002') ->> 'id' as ph_taken \gset
select tt.err('T2 a number that is the main number of another customer cannot become the main number', format($q$select crma_phone_make_primary(%L::bigint, 'customer asked')$q$, :'ph_taken'), 'mobile_taken');
select crma_phone_make_primary(:'ph1'::bigint, 'customer lost the old SIM') ->> 'mobile' as r \gset
select tt.chk('T2 the manager swaps the main number with a reason',
  :'r' = '01711031011'
  and (select mobile = '01711031011' from customers where id = :'ca')
  and exists (select 1 from customer_phones where customer_id = :'ca' and phone = '01711031001' and active)
  and not exists (select 1 from customer_phones where customer_id = :'ca' and phone = '01711031011' and active));
select tt.chk('T2 one change-log line with the reason', (select count(*) from audit_log where action = 'crm_primary_phone_changed' and record_id = :'ca' and detail ->> 'reason' = 'customer lost the old SIM') = 1);
select tt.chk('T2 the existing find_customer finds the new main number and not the old one', (find_customer('01711031011') ->> 'found')::boolean and not (find_customer('01711031001') ->> 'found')::boolean);
select tt.chk('T2 crma_find_by_any_phone finds the customer by the OLD number (now an extra one)', (crma_find_by_any_phone('01711031001') ->> 'found')::boolean and (crma_find_by_any_phone('01711031001') ->> 'via') = 'extra_phone'
  and (crma_find_by_any_phone('01711031001') ->> 'matches')::int = 2);
select crma_phone_add(:'ca', '01711031700') ->> 'dup' as r \gset
select tt.chk('T2 a number held by one customer only is found as that customer, with the main number to sell on', :'r' = 'false' and (crma_find_by_any_phone('01711031700') ->> 'id') = :'ca' and (crma_find_by_any_phone('01711031700') ->> 'mobile') = '01711031011' and (crma_find_by_any_phone('01711031700') ->> 'matches')::int = 1);
select tt.chk('T2 crma_find_by_any_phone by the main number says via mobile', (crma_find_by_any_phone('01711031011') ->> 'via') = 'mobile');
select tt.chk('T2 an unknown number is not found', not (crma_find_by_any_phone('01911031555') ->> 'found')::boolean);
select tt.err('T2 a bad number is refused by the lookup', $q$select crma_find_by_any_phone('xyz')$q$, 'bad_mobile');
select crma_phone_add(:'cb', '01711031555') ->> 'dup' as r1 \gset
select crma_phone_add(:'cc', '01711031555') ->> 'dup' as r2 \gset
select tt.chk('T2 two customers holding the same extra number: the lookup says ambiguous', :'r1' = 'false' and :'r2' = 'false' and (crma_find_by_any_phone('01711031555') ->> 'ambiguous')::boolean
  and (crma_find_by_any_phone('01711031555') ->> 'matches')::int = 2 and (crma_find_by_any_phone('01711031011') ->> 'ambiguous') = 'false');
select tt.chk('T2 the manager sees the possible duplicates', jsonb_array_length(crma_phone_conflicts()) >= 2);
select tt.as(:'u_c');
select tt.err('T2 a cashier cannot list the duplicates', $q$select crma_phone_conflicts()$q$, 'not allowed');
select tt.as(:'u_x');
select tt.err('T2 an outsider cannot look a customer up', $q$select crma_find_by_any_phone('01711031011')$q$, 'not allowed');

\echo == T3 delivery points
select tt.as(:'u_c');
select crma_address_save(:'ca', '{"label":"office","address":"test_addr_office_1","area":"test_area","landmark":"near test_mosque","delivery_note":"ring twice","is_default":true}', null, gen_random_uuid()) ->> 'id' as ad1 \gset
select tt.chk('T3 a delivery point is saved', (select label = 'office' and address = 'test_addr_office_1' and area = 'test_area' and is_default and active from customer_addresses where id = :'ad1'::bigint));
select gen_random_uuid() as cl2 \gset
select crma_address_save(:'ca', '{"address":"test_addr_gift_2","label":"gift","is_default":true}', null, :'cl2'::uuid) ->> 'id' as ad2 \gset
select tt.chk('T3 a second default moves the default flag (only one default)', (select count(*) from customer_addresses where customer_id = :'ca' and is_default and active) = 1 and (select is_default from customer_addresses where id = :'ad2'::bigint));
select tt.chk('T3 a retry with the same client id changes nothing', (crma_address_save(:'ca', '{"address":"test_addr_gift_2"}', null, :'cl2'::uuid) ->> 'dup')::boolean and (select count(*) from customer_addresses where customer_id = :'ca') = 2);
select tt.chk('T3 the same address again is a duplicate', (crma_address_save(:'ca', '{"address":"TEST_ADDR_GIFT_2"}') ->> 'dup')::boolean and (select count(*) from customer_addresses where customer_id = :'ca') = 2);
select tt.err('T3 an address is required', format($q$select crma_address_save(%L, '{"label":"home"}')$q$, :'ca'), 'address_required');
select tt.err('T3 a bad label is refused', format($q$select crma_address_save(%L, '{"address":"x","label":"castle"}')$q$, :'ca'), 'bad_value');
select tt.err('T3 an unknown key is refused', format($q$select crma_address_save(%L, '{"address":"x","city":"y"}')$q$, :'ca'), 'unknown_key');
select crma_address_save(:'ca', jsonb_build_object('address', repeat('a', 300))) ->> 'id' as ad3 \gset
select tt.chk('T3 a long address is cut at 200 characters', length((select address from customer_addresses where id = :'ad3'::bigint)) = 200);
select crma_address_save(:'ca', '{"landmark":"near test_school"}', :'ad1'::bigint) ->> 'id' as r \gset
select tt.chk('T3 a delivery point is edited (partial change keeps the rest)', :'r'::bigint = :'ad1'::bigint
  and (select landmark = 'near test_school' and address = 'test_addr_office_1' and area = 'test_area' from customer_addresses where id = :'ad1'::bigint));
select tt.err('T3 a delivery point of ANOTHER customer cannot be edited through this customer', format($q$select crma_address_save(%L, '{"landmark":"x"}', %L::bigint)$q$, :'cb', :'ad1'), 'address_not_found');
select crma_address_retire(:'ad2'::bigint) ->> 'dup' as r \gset
select tt.chk('T3 retire a delivery point', :'r' = 'false' and (select not active and not is_default from customer_addresses where id = :'ad2'::bigint));
select tt.chk('T3 retire twice is a duplicate', (crma_address_retire(:'ad2'::bigint) ->> 'dup')::boolean);
select tt.as(:'u_r');
select tt.err('T3 a read-only person cannot add one', format($q$select crma_address_save(%L, '{"address":"x"}')$q$, :'ca'), 'not allowed');

\echo == T4 family dates
select tt.as(:'u_c');
select crma_date_save(:'ca', '{"kind":"birthday","person_label":"Spouse","month":3,"day":15,"year":1990,"remind_days_before":7}') ->> 'id' as dt1 \gset
select tt.chk('T4 a family date is saved', (select kind = 'birthday' and person_label = 'Spouse' and month = 3 and day = 15 and year = 1990 and remind_days_before = 7 from customer_dates where id = :'dt1'::bigint));
select tt.chk('T4 the same date again (any letter case) is a duplicate', (crma_date_save(:'ca', '{"kind":"birthday","person_label":"spouse","month":3,"day":15}') ->> 'dup')::boolean and (select count(*) from customer_dates where customer_id = :'ca') = 1);
select tt.chk('T4 29 February without a year is accepted', (crma_date_save(:'ca', '{"kind":"birthday","person_label":"Child 1","month":2,"day":29}') ->> 'dup')::boolean = false);
select tt.err('T4 30 February is refused', format($q$select crma_date_save(%L, '{"kind":"other","person_label":"x","month":2,"day":30}')$q$, :'ca'), 'bad_date');
select tt.err('T4 month 13 is refused', format($q$select crma_date_save(%L, '{"kind":"other","person_label":"x","month":13,"day":1}')$q$, :'ca'), 'bad_number');
select tt.err('T4 a month with a fraction is refused', format($q$select crma_date_save(%L, '{"kind":"other","person_label":"x","month":2.5,"day":1}')$q$, :'ca'), 'bad_number');
select tt.err('T4 a birth year in the future is refused', format($q$select crma_date_save(%L, jsonb_build_object('kind','birthday','person_label','Child 2','month',1,'day',1,'year', extract(year from now())::int + 1))$q$, :'ca'), 'bad_date');
select tt.err('T4 a person label is required', format($q$select crma_date_save(%L, '{"kind":"birthday","month":3,"day":4}')$q$, :'ca'), 'person_required');
select tt.err('T4 a bad kind is refused', format($q$select crma_date_save(%L, '{"kind":"holiday","person_label":"x","month":3,"day":4}')$q$, :'ca'), 'bad_value');
select tt.err('T4 an unknown key is refused', format($q$select crma_date_save(%L, '{"kind":"other","person_label":"x","month":3,"day":4,"note":"y"}')$q$, :'ca'), 'unknown_key');
select crma_date_save(:'ca', '{"remind_days_before":3}', :'dt1'::bigint) ->> 'id' as r \gset
select tt.chk('T4 a date is edited (partial change)', :'r'::bigint = :'dt1'::bigint and (select remind_days_before = 3 and month = 3 and day = 15 from customer_dates where id = :'dt1'::bigint));
select tt.chk('T4 retire a date; twice is a duplicate', (crma_date_retire(:'dt1'::bigint) ->> 'dup')::boolean = false and (crma_date_retire(:'dt1'::bigint) ->> 'dup')::boolean);
select tt.chk('T4 after retiring, the same date may be saved again', (crma_date_save(:'ca', '{"kind":"birthday","person_label":"Spouse","month":3,"day":15}') ->> 'dup')::boolean = false);

\echo == T5 tags
select tt.as(:'u_c');
select tt.err('T5 a cashier cannot create a tag', $q$select crma_tag_save(null, 'vip', 'VIP')$q$, 'not allowed');
select tt.as(:'u_m');
select crma_tag_save(null, 'vip', 'VIP customer') ->> 'id' as tg1 \gset
select tt.err('T5 a duplicate tag code is refused', $q$select crma_tag_save(null, 'vip', 'Another')$q$, 'code_exists');
select tt.err('T5 a bad tag code is refused', $q$select crma_tag_save(null, 'Bad Code', 'x')$q$, 'bad_code');
select tt.err('T5 a tag needs a name', $q$select crma_tag_save(null, 'okcode', '  ')$q$, 'name_required');
select crma_tag_save(:'tg1'::bigint, 'ignored', 'VIP buyer') ->> 'code' as r \gset
select tt.chk('T5 a tag is renamed, its code stays', :'r' = 'vip' and (select label = 'VIP buyer' from crm_tags where id = :'tg1'::bigint));
select crma_tag_save(null, 'party_host', 'Party host') ->> 'id' as tg2 \gset
select tt.as(:'u_c');
select crma_tag_set(:'ca', :'tg1'::bigint) ->> 'dup' as r \gset
select tt.chk('T5 a cashier puts a tag on a customer', :'r' = 'false' and (select active from customer_tags where customer_id = :'ca' and tag_id = :'tg1'::bigint));
select tt.chk('T5 the same tag again is a duplicate', (crma_tag_set(:'ca', :'tg1'::bigint) ->> 'dup')::boolean);
select crma_tag_set(:'ca', :'tg1'::bigint, false) ->> 'dup' as r \gset
select tt.chk('T5 remove the tag, twice is a duplicate', :'r' = 'false' and (crma_tag_set(:'ca', :'tg1'::bigint, false) ->> 'dup')::boolean and (select not active from customer_tags where customer_id = :'ca' and tag_id = :'tg1'::bigint));
select crma_tag_set(:'ca', :'tg1'::bigint) ->> 'dup' as r \gset
select tt.chk('T5 the tag can be put on again after removal (one row)', :'r' = 'false' and (select count(*) from customer_tags where customer_id = :'ca' and tag_id = :'tg1'::bigint) = 1);
select tt.err('T5 an unknown tag is refused', format($q$select crma_tag_set(%L, 999999)$q$, :'ca'), 'tag_not_found');
select tt.err('T5 an unknown customer is refused', format($q$select crma_tag_set(gen_random_uuid(), %L::bigint)$q$, :'tg1'), 'customer_not_found');
select tt.as(:'u_m');
select tt.chk('T5 a retired tag cannot be newly put on a customer', (crma_tag_save(:'tg2'::bigint, 'x', 'Party host', false) ->> 'code') = 'party_host' and tt.try(format($q$select crma_tag_set(%L, %L::bigint)$q$, :'ca', :'tg2')) like '%tag_not_found%');
select tt.chk('T5 the tag list is readable by a browser role', (select count(*) from crm_tags) = 2);

\echo == T6 notes (grant crm_view or the owner)
select tt.as(:'u_c');
select tt.err('T6 a cashier without crm_view cannot write a note', format($q$select crma_note_add(%L, 'test_note')$q$, :'ca'), 'not allowed');
select tt.as(:'u_m');
select tt.err('T6 customer_manage alone is not crm_view', format($q$select crma_note_add(%L, 'test_note')$q$, :'ca'), 'not allowed');
select tt.as(:'u_n');
select gen_random_uuid() as cl3 \gset
select crma_note_add(:'ca', 'test_note_one: asked for sugar-free sweets', 'call', :'cl3'::uuid) ->> 'id' as nt1 \gset
select tt.chk('T6 a note is stored with the author and the time', (select kind = 'call' and created_staff = (select staff_id from profiles where id = :'u_n') and created_at > now() - interval '1 minute' and created_by = :'u_n'::uuid from crm_notes where id = :'nt1'::bigint));
select tt.chk('T6 a retry with the same client id changes nothing', (crma_note_add(:'ca', 'test_note_one: asked for sugar-free sweets', 'call', :'cl3'::uuid) ->> 'dup')::boolean and (select count(*) from crm_notes where customer_id = :'ca') = 1);
select tt.err('T6 an empty note is refused', format($q$select crma_note_add(%L, '   ')$q$, :'ca'), 'note_required');
select tt.err('T6 a bad kind is refused', format($q$select crma_note_add(%L, 'x', 'gossip')$q$, :'ca'), 'bad_value');
select tt.err('T6 a note for an unknown customer is refused', $q$select crma_note_add(gen_random_uuid(), 'x')$q$, 'customer_not_found');
select crma_note_add(:'ca', repeat('b', 1200)) ->> 'id' as nt2 \gset
select tt.chk('T6 a long note is cut at 1000 characters', length((select body from crm_notes where id = :'nt2'::bigint)) = 1000);
select tt.err('T6 retiring needs a reason', format($q$select crma_note_retire(%L::bigint, 'ab')$q$, :'nt1'), 'reason_required');
select tt.as(:'u_o');
insert into user_grants (user_id, grant_code, location_id) values (:'u_c','crm_view',null);
select tt.as(:'u_c');
select tt.err('T6 another note-writer (not the author, not the owner) cannot retire it', format($q$select crma_note_retire(%L::bigint, 'wrong customer')$q$, :'nt1'), 'not allowed');
select tt.as(:'u_n');
select crma_note_retire(:'nt1'::bigint, 'written on the wrong customer') ->> 'dup' as r \gset
select tt.chk('T6 the author retires the note with a reason; the text stays in the table', :'r' = 'false'
  and (select retired_at is not null and retire_reason = 'written on the wrong customer' and body like 'test_note_one%' from crm_notes where id = :'nt1'::bigint));
select tt.chk('T6 retire twice is a duplicate', (crma_note_retire(:'nt1'::bigint, 'again please') ->> 'dup')::boolean);
select tt.as(:'u_o');
select tt.chk('T6 the owner writes a note without any grant', (crma_note_add(:'ca', 'test_owner_note') ->> 'dup')::boolean = false);
select tt.as(:'u_x');
select tt.err('T6 an outsider cannot write a note', format($q$select crma_note_add(%L, 'x')$q$, :'ca'), 'not allowed');

\echo == T7 reveal of a masked number
select tt.as(:'u_c');
select tt.chk('T7 with masking OFF (default) the number is returned without a log line', (crma_phone_reveal(:'ca', null) ->> 'logged')::boolean = false and (crma_phone_reveal(:'ca', null) ->> 'mobile') = '01711031011');
select tt.as(:'u_o');
select set_rule('crm_mask_phone', 'true'::jsonb) is null as s3 \gset
select tt.as(:'u_c');
select tt.err('T7 masked caller needs a reason', format($q$select crma_phone_reveal(%L, 'x')$q$, :'ca'), 'reason_required');
select crma_phone_reveal(:'ca', 'customer is at the counter and asked me to call') ->> 'mobile' as r \gset
select tt.chk('T7 masked caller with a reason gets the number once and one change-log line is written', :'r' = '01711031011'
  and (select count(*) from audit_log where action = 'crm_phone_reveal' and record_id = :'ca' and user_id = :'u_c'::uuid) = 1);
select tt.as(:'u_o');
select tt.chk('T7 the owner is never masked and writes no line', (crma_phone_reveal(:'ca', null) ->> 'logged')::boolean = false);
select tt.as(:'u_x');
select tt.err('T7 an outsider cannot reveal', format($q$select crma_phone_reveal(%L, 'testing')$q$, :'ca'), 'not allowed');
select tt.as(:'u_o');
select set_rule('crm_mask_phone', 'false'::jsonb) is null as s4 \gset

\echo == T8 accounting untouched and paste-twice
select tt.chk('T8 journal entries and lines, sales, payments and the sales total are exactly as before (CRM never posts)', tt.acct() = :'acct0');

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
