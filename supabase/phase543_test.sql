-- Phase 543 tests (clean form sequence). TEST DATABASE ONLY: a local throwaway Postgres built from the owner paste chain WITHOUT phase543.
-- This file pastes phase543.sql itself (T1 onwards), then pastes it again (T9: paste-twice is a no-op). Never paste this file into the live project.
-- Build the old-state database first (the order = FOUNDATION + NEW without phase543), e.g.:
--   ORD=$(. tests/sql/paste_order.env; echo -n "$FOUNDATION $NEW" | tr ' ' '\n' | grep -v '^phase543$' | tr '\n' ' '); PGPORT=5544 bash tests/sql/final_build.sh form_t543 "$ORD"
--   psql -h /tmp -p 5544 -U postgres -d form_t543 -f supabase/phase543_test.sql      (expect: 31 checks, 0 failures)
-- Fixtures use neutral test_* ids and the seeded owner role and locations 1..n only. Prints PASS / FAIL per check.
\set ON_ERROR_STOP off
create schema if not exists t543;
create table if not exists t543.res (name text, ok boolean);
truncate t543.res;
create or replace function t543.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into t543.res values (p_name, coalesce(p_ok, false)); raise notice '% %', case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end, p_name; end $$;

\echo == T0 fixtures written with the OLD codes (before the phase)
select t543.chk('T0a the database is the old sequence (forms 02-4 is the appointment letter)', exists (select 1 from forms where code = '02-4' and name_en like 'Appointment Letter%'));
select t543.chk('T0b no test marker yet', to_regclass('public.form_code_migration_543') is null);
insert into role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values ('owner', '02-4', true, true, false), ('owner', '20-1', true, false, false) on conflict do nothing;
insert into serials (form_code, location_id, last) values ('10-2', 1, 7) on conflict do nothing;
insert into pin_sig_cfg (form_code, enabled) values ('14-1', true) on conflict do nothing;
insert into forms_ledger_cfg (form_code, is_on) values ('04-1', true) on conflict do nothing;
insert into blind_count_cfg (form_code, location_id, enabled) values ('14-1', 1, true) on conflict do nothing;
update rules set label_en = 'test: form 14-1 and 10-2 note' where key = 'pos_customer_on_due';
alter table entries disable trigger user;
insert into entries (id, form_code, location_id, serial, entry_date, status, data, created_by, created_at, updated_at)
  values ('00000000-0000-0000-0000-00000000f543', '02-2', 1, 1, '2026-10-01', 'draft', '{"test": "t543"}', '00000000-0000-0000-0000-00000000a543', now(), now());
alter table entries enable trigger user;
select t543.chk('T0c the fixture rows exist', (select count(*) from role_form_perms where role_code = 'owner' and form_code in ('02-4', '20-1')) = 2
  and exists (select 1 from entries where id = '00000000-0000-0000-0000-00000000f543'));

\echo == T1 the phase (one transaction)
\i supabase/phase543.sql

\echo == T2 forms: the 41 printed codes are the new sequence, the names followed the codes
select t543.chk('T2a 42 printed forms (41 NN-1 plus 0-1)', (select count(*) from forms where code ~ '^[0-9][0-9]-[0-9]$' or code = '0-1') = 42);
select t543.chk('T2b every NN-1 code 01-1..41-1 exists once', (select count(*) from generate_series(1, 41) g where exists (select 1 from forms f where f.code = lpad(g::text, 2, '0') || '-1')) = 41);
select t543.chk('T2c 01-1 is the appointment letter, 40-1 the weekly review, 41-1 the yield test', exists (select 1 from forms where code = '01-1' and name_en like 'Appointment Letter%')
  and exists (select 1 from forms where code = '40-1' and name_en like 'Weekly Review%') and exists (select 1 from forms where code = '41-1' and name_en like 'Yield Test%'));
select t543.chk('T2d sort = position for the 41 forms; 0-1 keeps its sort 5', (select count(*) from forms where code ~ '^[0-9][0-9]-1$' and sort = substr(code, 1, 2)::int) = 41
  and (select sort from forms where code = '0-1') = 5);
select t543.chk('T2e no temporary code is left', (select count(*) from forms where code like '~543~%') = 0);
select t543.chk('T2f the non-printed codes are untouched', exists (select 1 from forms where code = 'POS') and exists (select 1 from forms where code = 'ONLINE_INTAKE'));

\echo == T3 data: form_code moved with the form
select t543.chk('T3a role permission 02-4 is now 01-1 (appointment letter)', exists (select 1 from role_form_perms where role_code = 'owner' and form_code = '01-1' and can_enter)
  and not exists (select 1 from role_form_perms where role_code = 'owner' and form_code = '02-4'));
select t543.chk('T3b role permission 20-1 is now 05-1 (customer order)', exists (select 1 from role_form_perms where role_code = 'owner' and form_code = '05-1'));
select t543.chk('T3c serial of 10-2 is now 11-1 (expense voucher), the counter kept', exists (select 1 from serials where form_code = '11-1' and location_id = 1 and last = 7));
select t543.chk('T3d pin signature setting of 14-1 is now 06-1 (daily showroom sheet)', exists (select 1 from pin_sig_cfg where form_code = '06-1' and enabled));
select t543.chk('T3e ledger setting of 04-1 is now 13-1 (goods received)', exists (select 1 from forms_ledger_cfg where form_code = '13-1' and is_on));
select t543.chk('T3f blind count of 14-1 is now 06-1', exists (select 1 from blind_count_cfg where form_code = '06-1' and location_id = 1));
select t543.chk('T3g the entry of 02-2 is now 21-1 (monthly salary) and keeps its data', exists (select 1 from entries where id = '00000000-0000-0000-0000-00000000f543' and form_code = '21-1' and data->>'test' = 't543'));
select t543.chk('T3h no table still holds a temporary code', (select count(*) from role_form_perms where form_code like '~543~%') + (select count(*) from entries where form_code like '~543~%') = 0);

\echo == T4 labels, functions, triggers, policies, checks, constraints
select t543.chk('T4a the label names the new codes (14-1 -> 06-1, 10-2 -> 11-1)', (select label_en from rules where key = 'pos_customer_on_due') = 'test: form 06-1 and 11-1 note');
select t543.chk('T4b a stored function names the new codes, not the old ones',
  (select count(*) from pg_proc where proname = '_acct_docs' and pg_get_functiondef(oid) like '%11-1%') >= 1
  and (select count(*) from pg_proc where proname = '_acct_docs' and pg_get_functiondef(oid) like '%''10-2''%') = 0);
select t543.chk('T4c the row policy of quick expenses checks 11-1 (not 10-2)', (select qual like '%11-1%' and qual not like '%10-2%' from pg_policies where tablename = 'quick_expenses' and policyname = 'quick_expenses_sel'));
select t543.chk('T4d the trigger on 02-2 entries now fires for 21-1', (select pg_get_triggerdef(oid) like '%''21-1''%' from pg_trigger where tgname = 'entries_payroll_link50'));
select t543.chk('T4e the check constraint on sale_form_links allows 05-1 and not 20-1', (select pg_get_constraintdef(oid) like '%05-1%' and pg_get_constraintdef(oid) not like '%20-1%' from pg_constraint where conname = 'sale_form_links_form_code_check'));
select t543.chk('T4f the 11 foreign keys to forms(code) are back', (select count(*) from pg_constraint where contype = 'f' and confrelid = 'public.forms'::regclass) = 11);

\echo == T5 the triggers that were on are on again; the forms code is still immutable
select t543.chk('T5a no user trigger is left disabled', (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal and t.tgenabled = 'D') = 0);
do $$ begin
  update forms set code = '99-9' where code = '0-1';
  perform t543.chk('T5b a code can not be changed afterwards (immutable)', false);
exception when others then
  perform t543.chk('T5b a code can not be changed afterwards (immutable)', sqlerrm = 'code is immutable');
end $$;

\echo == T6 the marker and the paste-twice rule
select t543.chk('T6a the marker is written once', (select count(*) from public.form_code_migration_543) = 1);
select t543.chk('T6b the marker is closed to the browser roles', not has_table_privilege('anon', 'public.form_code_migration_543', 'select') and not has_table_privilege('authenticated', 'public.form_code_migration_543', 'select'));

\echo == T7 paste phase543 again: nothing moves
create temp table t543_before as select code, name_en, sort from forms order by code;
create temp table t543_before_rp as select role_code, form_code from role_form_perms order by 1, 2;
\i supabase/phase543.sql
select t543.chk('T7a the forms are the same after the second paste', (select count(*) from (select code, name_en, sort from forms except select code, name_en, sort from t543_before) x) = 0);
select t543.chk('T7b the permissions are the same after the second paste', (select count(*) from (select role_code, form_code from role_form_perms except select role_code, form_code from t543_before_rp) x) = 0);
select t543.chk('T7c still one marker', (select count(*) from public.form_code_migration_543) = 1);
drop table t543_before; drop table t543_before_rp;

\echo == T8 the whole database still passes the package check
select t543.chk('T8a no package function is missing after the phase (_i2_state)', (select count(*) from public._i2_state() where not present) = 0);

\echo == RESULT
select count(*) filter (where not ok) as failures, count(*) as checks from t543.res;
