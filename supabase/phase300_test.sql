-- FRESH DB ONLY. Phase 300 tests (CRM-A: schema, settings, grants, helpers, privacy of the new tables).
--   Build a local throwaway database through phase 98 (or 99), then:
--     for p in phase300 phase301 phase302; do psql -h /tmp -p 5571 -U postgres -d <db> -v ON_ERROR_STOP=1 -q -f supabase/$p.sql; done      (paste each twice)
--     psql -h /tmp -p 5571 -U postgres -d <db> -qAt -f supabase/phase300_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000030001'
\set u_c '00000000-0000-0000-0000-000000030002'
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
create or replace function tt.q_role(p_sql text) returns text language plpgsql as $$
declare r text;
begin
  set local role authenticated;
  begin execute p_sql into r; exception when insufficient_privilege then reset role; return 'denied'; end;
  reset role; return r;
end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'u_o','test_owner300@s.app','{"full_name":"test_owner300"}'), (:'u_c','test_cash300@s.app','{"full_name":"test_cash300"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_c');
insert into user_roles values (:'u_o','owner'),(:'u_c','salesperson') on conflict do nothing;
insert into user_locations values (:'u_c',1) on conflict do nothing;

\echo == T0 present, three settings at safe defaults with English text, two grants, nothing shared patched
select tt.chk('T0 phase300 present', to_regprocedure('public._crma_present()') is not null);
select tt.chk('T0 three rules exist, module crm, defaults OFF, English text only',
  (select count(*) from rules where key in ('crm_on','crm_second_phone_on','crm_mask_phone') and module = 'crm' and kind = 'switch') = 3
  and not rule_on('crm_on') and not rule_on('crm_second_phone_on') and not rule_on('crm_mask_phone')
  and not exists (select 1 from rules where key in ('crm_on','crm_second_phone_on','crm_mask_phone') and (label_en is null or label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 two grants defined (crm_view, crm_contact_view) and nobody holds them',
  (select count(*) from grant_defs where grant_code in ('crm_view','crm_contact_view')) = 2
  and not exists (select 1 from user_grants where grant_code in ('crm_view','crm_contact_view')) and not exists (select 1 from rule_grants where grant_code in ('crm_view','crm_contact_view') and allowed));
select tt.chk('T0 no shared function was patched or re-created (no crma / bos300 text in customer_save, find_customer, customer_directory, customer_profile, record_sale2, _cust_bal, customer_dues, customer_ledger, notify_scan)',
  (select count(*) from (values ('public.find_customer(text)'),('public.customer_directory(integer)'),('public.customer_profile(uuid)'),('public._cust_bal(uuid)'),('public.customer_dues()'),('public.customer_ledger(uuid)'),('public.notify_scan()'),('public.customer_save(uuid,jsonb,uuid)')) v(f)
   where pg_get_functiondef(v.f::regprocedure) ~* '(crma|bos300)') = 0
  and (select count(*) from pg_proc where proname = 'record_sale2' and prosrc ~* '(crma|bos300)') = 0);
select tt.chk('T0 customers got four NULLABLE columns, no default, existing rows untouched',
  (select count(*) from information_schema.columns where table_schema='public' and table_name='customers' and column_name in ('preferred_location_id','language','owner_user','credit_days') and is_nullable='YES' and column_default is null) = 4
  and not exists (select 1 from customers where preferred_location_id is not null or language is not null or owner_user is not null or credit_days is not null));

\echo == T1 helpers
select tt.chk('T1 mask 01712345678 -> 017******78', public._crma_mask('01712345678') = '017******78');
select tt.chk('T1 mask short and null', public._crma_mask('12345') = '*****' and public._crma_mask(null) is null);
select tt.chk('T1 norm accepts +880 / spaces / Bangla digits, returns NULL (no error) for rubbish',
  public._crma_norm('+880 1711-000001') = '01711000001' and public._crma_norm('০১৭১১০০০০০১') = '01711000001' and public._crma_norm('abc') is null and public._crma_norm('12') is null and public._crma_norm(null) is null);
select tt.chk('T1 valid month/day: 29 Feb allowed, 30 Feb and month 13 refused', public._crma_valid_md(2,29) and not public._crma_valid_md(2,30) and not public._crma_valid_md(13,1) and public._crma_valid_md(12,31) and not public._crma_valid_md(4,31));
select tt.chk('T1 next date: later this year, else next year', public._crma_next_date(3,15,date '2026-03-01') = date '2026-03-15' and public._crma_next_date(3,15,date '2026-03-15') = date '2026-03-15' and public._crma_next_date(3,15,date '2026-03-16') = date '2027-03-15');
select tt.chk('T1 next date: 29 Feb falls on 28 Feb in a year without a 29th, stays 29 Feb in a leap year',
  public._crma_next_date(2,29,date '2026-01-01') = date '2026-02-28' and public._crma_next_date(2,29,date '2027-03-01') = date '2028-02-29' and public._crma_next_date(2,29,date '2028-01-01') = date '2028-02-29');

\echo == T2 the new tables: row security on, closed to browsers, nothing deleted, change log
select tt.chk('T2 row security is on for all six tables', (select count(*) from pg_class where relnamespace='public'::regnamespace and relname in ('customer_phones','customer_addresses','customer_dates','crm_tags','customer_tags','crm_notes') and relrowsecurity) = 6);
select tt.chk('T2 browsers have NO select on the five private tables, and may read the tag list',
  not has_table_privilege('authenticated','public.customer_phones','select') and not has_table_privilege('authenticated','public.customer_addresses','select')
  and not has_table_privilege('authenticated','public.customer_dates','select') and not has_table_privilege('authenticated','public.customer_tags','select')
  and not has_table_privilege('authenticated','public.crm_notes','select') and has_table_privilege('authenticated','public.crm_tags','select')
  and not has_table_privilege('anon','public.crm_tags','select') and not has_table_privilege('authenticated','public.customer_phones','insert'));
select tt.chk('T2 sequences closed', not has_sequence_privilege('authenticated','public.customer_phones_id_seq','usage') and not has_sequence_privilege('authenticated','public.crm_notes_id_seq','usage'));
select tt.chk('T2 helper functions are not callable by browsers', not has_function_privilege('authenticated','public._crma_mask(text)','execute') and not has_function_privilege('anon','public._crma_view_ok()','execute')
  and not has_function_privilege('authenticated','public._crma_phones(uuid)','execute'));
select tt.chk('T2 browser functions are callable by signed-in users only', has_function_privilege('authenticated','public.crma_customer_360(uuid)','execute') and not has_function_privilege('anon','public.crma_customer_360(uuid)','execute')
  and has_function_privilege('authenticated','public.crma_phone_add(uuid,text,text,boolean,text,uuid)','execute') and not has_function_privilege('anon','public.crma_customer_directory(integer)','execute'));
select tt.chk('T2 every new table has a delete guard (except notes, which have their own append-only guard) and an audit trigger',
  (select count(*) from pg_trigger where not tgisinternal and tgname in ('customer_phones_nodel','customer_addresses_nodel','customer_dates_nodel','crm_tags_nodel','customer_tags_nodel')) = 5
  and (select count(*) from pg_trigger where not tgisinternal and tgname in ('audit_customer_phones','audit_customer_addresses','audit_customer_dates','audit_crm_tags','audit_customer_tags','audit_crm_notes','crm_notes_guard')) = 7);
select tt.chk('T2 as a plain browser role the private tables cannot be read', tt.q_role('select count(*) from public.customer_phones') = 'denied');

\echo == T3 constraints (direct inserts as the table owner)
select tt.as(:'u_o');
insert into customers (mobile, name) values ('01711030001','test_cust_300a') on conflict do nothing;
select id as c1 from customers where mobile='01711030001' \gset
select tt.err('T3 bad phone shape refused by the table', format($q$insert into customer_phones (customer_id, phone) values (%L, '12345')$q$, :'c1'), 'violates check');
select tt.err('T3 bad phone label refused', format($q$insert into customer_phones (customer_id, phone, label) values (%L, '01711030002', 'fax')$q$, :'c1'), 'violates check');
insert into customer_phones (customer_id, phone) values (:'c1', '01711030002');
select tt.err('T3 the same phone twice for one customer refused', format($q$insert into customer_phones (customer_id, phone) values (%L, '01711030002')$q$, :'c1'), 'duplicate key');
update customer_phones set active=false where customer_id=:'c1' and phone='01711030002';
select tt.chk('T3 a phone can be retired', (select active from customer_phones where customer_id = :'c1' and phone='01711030002') = false);
select tt.chk('T3 a retired phone may be added again (unique only among active)', tt.try(format($q$insert into customer_phones (customer_id, phone) values (%L, '01711030002')$q$, :'c1')) = 'ok');
select tt.err('T3 delete is refused', format($q$delete from customer_phones where customer_id=%L$q$, :'c1'), 'nothing is deleted');
select tt.err('T3 date 30 February refused', format($q$insert into customer_dates (customer_id, kind, person_label, month, day) values (%L,'birthday','Spouse',2,30)$q$, :'c1'), 'violates check');
select tt.err('T3 date needs a person label', format($q$insert into customer_dates (customer_id, kind, person_label, month, day) values (%L,'birthday','',3,3)$q$, :'c1'), 'violates check');
select tt.err('T3 language other than bn / en refused', format($q$update customers set language='fr' where id=%L$q$, :'c1'), 'violates check');
select tt.err('T3 credit days over 365 refused', format($q$update customers set credit_days=400 where id=%L$q$, :'c1'), 'violates check');
select tt.err('T3 tag code must be lower case letters, digits, underscore', $q$insert into crm_tags (code,label) values ('Bad Code','x')$q$, 'violates check');
insert into crm_notes (customer_id, body) values (:'c1','test_note_300');
select tt.err('T3 a note cannot be edited', format($q$update crm_notes set body='changed' where customer_id=%L$q$, :'c1'), 'append_only');
select tt.err('T3 a note cannot be deleted', format($q$delete from crm_notes where customer_id=%L$q$, :'c1'), 'append_only');
select tt.chk('T3 a note can be retired once', tt.try(format($q$update crm_notes set retired_at=now(), retire_reason='test' where customer_id=%L$q$, :'c1')) = 'ok');
select tt.err('T3 a retired note cannot change again', format($q$update crm_notes set retire_reason='other' where customer_id=%L$q$, :'c1'), 'append_only');
select tt.chk('T3 the change log wrote lines for the inserts', (select count(*) from audit_log where table_name in ('customer_phones','crm_notes') and record_id is not null) >= 2);

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
