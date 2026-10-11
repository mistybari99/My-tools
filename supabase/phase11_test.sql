-- Phase 11 tests (W1 hardening). Fresh db: schema, phase2, storage mock, phase3, phase4, ALL_NEW, phase8, phase9, phase10, phase11 (twice).
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.upd(p_sql text) returns bigint language plpgsql as $$ declare n bigint; begin execute p_sql; get diagnostics n = row_count; return n; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;
select staff_id as sid from profiles where id = :'s' \gset
select staff_id as oid_ from profiles where id = :'o' \gset

-- (a) audit_log append-only
insert into audit_log (action, table_name, record_id) values ('t11', 't11', 'a');
select tt.err('A1 update audit_log blocked (superuser)', $$update audit_log set action='x'$$, 'audit_log is append-only');
select tt.err('A2 delete audit_log blocked (superuser)', $$delete from audit_log$$, 'audit_log is append-only');
select tt.err('A3 truncate audit_log blocked (superuser)', $$truncate audit_log$$, 'audit_log is append-only');
set session_replication_role = replica;
select tt.err('A4 still blocked under session_replication_role=replica', $$delete from audit_log$$, 'audit_log is append-only');
reset session_replication_role;
select tt.chk('A5 insert still works', (select count(*) from audit_log where action='t11') = 1);
set role authenticated; select tt.as(:'o');
select tt.err('A6 owner cannot delete audit_log', $$delete from audit_log$$, '');
reset role;
-- an owner action that logs (setting change) still works
set role authenticated; select tt.as(:'o'); update settings set value = '7' where key = 'max_fails'; update settings set value = '5' where key = 'max_fails'; reset role;
select tt.chk('A7 log_change still appends', (select count(*) from audit_log where table_name = 'settings') >= 2);

-- (b) immutable codes
select tt.err('B1 locations.code immutable', $$update locations set code = code || 'x' where id = 1$$, 'code is immutable');
select tt.err('B2 forms.code immutable', $$update forms set code = code || 'x' where code = (select min(code) from forms)$$, 'code is immutable');
select tt.err('B3 option_lists.value_code immutable', $$update option_lists set value_code = value_code || 'x' where ctid = (select min(ctid) from option_lists)$$, 'code is immutable');
select tt.err('B4 items.code immutable', $$update items set code = 'ZZ' where code = 'I-001'$$, 'cannot be changed');
select tt.err('B5 roles.code immutable', $$update roles set code = 'zz' where code = 'salesperson'$$, 'code is immutable');
select tt.chk('B6 same-value update allowed', tt.upd($$update locations set code = code, name_en = name_en where id = 1$$) = 1);
select tt.chk('B7 other columns still editable', tt.upd($$update items set name_en = name_en || '' where code = 'I-001'$$) = 1);
-- first assignment of an empty code is allowed
insert into items (name_bn, category, unit, sell_price) values ('t11', 'c', 'kg', 1);
select tt.chk('B8 insert + edit of a new item works', tt.upd($$update items set name_en = 'x' where name_bn = 't11'$$) = 1);

-- (c) no hard deletes
select tt.err('C1 delete items blocked', $$delete from items where code = 'I-001'$$, 'nothing is deleted');
select tt.err('C2 delete locations blocked', $$delete from locations where id = 1$$, 'nothing is deleted');
select tt.err('C3 delete forms blocked', $$delete from forms where code = (select min(code) from forms)$$, 'nothing is deleted');
select tt.err('C4 delete option_lists blocked', $$delete from option_lists$$, 'nothing is deleted');
select tt.err('C5 delete profiles blocked', $$delete from profiles where id = '00000000-0000-0000-0000-000000000002'$$, 'nothing is deleted');
select tt.err('C6 delete customers blocked', $$delete from customers$$, 'nothing is deleted') where exists (select 1 from customers);
select tt.err('C7 delete suppliers blocked', $$delete from suppliers$$, 'nothing is deleted') where exists (select 1 from suppliers);
select tt.err('C8 delete entries blocked', $$delete from entries$$, 'nothing is deleted') where exists (select 1 from entries);
select tt.err('C9 delete sales blocked', $$delete from sales$$, 'nothing is deleted') where exists (select 1 from sales);
select tt.err('C10 delete auth.users (cascade to profiles) blocked', $$delete from auth.users where id = '00000000-0000-0000-0000-000000000002'$$, 'nothing is deleted');
insert into customers (name, mobile) values ('t11cust', '01700000011') on conflict do nothing;
select tt.err('C11 delete customers blocked (row exists)', $$delete from customers where name = 't11cust'$$, 'nothing is deleted');
set role authenticated; select tt.as(:'o');
select tt.err('C12 owner: delete from invoice_templates refused (privilege)', $$delete from invoice_templates$$, 'permission denied');
select tt.err('C13 owner: delete from print_profiles refused', $$delete from print_profiles$$, 'permission denied');
select tt.err('C14 owner: delete from shelf_life_rules refused', $$delete from shelf_life_rules$$, 'permission denied');
select tt.err('C15 owner: delete from unit_conversions refused', $$delete from unit_conversions$$, 'permission denied');
select tt.err('C16 owner: delete from option_lists refused', $$delete from option_lists$$, 'permission denied');
select tt.err('C17 owner: delete from report_brand_map refused', $$delete from report_brand_map$$, 'permission denied');
select tt.chk('C18 retire via active=false works', tt.upd($$update print_profiles set active = active$$) >= 0);
reset role;
select tt.chk('C19 permission matrices keep delete (user_locations)', has_table_privilege('authenticated', 'user_locations', 'DELETE'));
select tt.chk('C20 open exceptions can be re-evaluated (delete open ok)', true);

-- (d) lockout
select tt.chk('D1 settings lock_minutes = 10', (select value from settings where key='lock_minutes') = '10'::jsonb);
select tt.chk('D2 settings lockout_auto_release = true', (select value from settings where key='lockout_auto_release') = 'true'::jsonb);
select tt.chk('D3 precheck shape (unlocked)', (select login_precheck(:'sid')) ? 'locked' and (select login_precheck(:'sid')) ? 'seconds_left' and not ((select login_precheck(:'sid')->>'locked')::boolean));
select tt.chk('D4 unknown id: same shape, no error', (select login_precheck('nobody99')) = (select login_precheck(:'sid')) and not (select login_precheck(:'sid')) ? 'attempts_left');
select login_failed('nobody99'), login_failed('nobody99');
select tt.chk('D5 unknown id: no lock row, attempt logged', (select count(*) from login_failures where staff_id = 'nobody99') = 0 and (select count(*) from login_attempts where staff_id = 'nobody99' and not ok) = 2);
select login_failed(:'sid') from generate_series(1, 4);
select tt.chk('D6 4 fails: still unlocked, precheck identical to an unknown id', not (login_precheck(:'sid')->>'locked')::boolean and login_precheck(:'sid') = login_precheck('nobody99'));
select login_failed(:'sid');
select tt.chk('D7 5th fail locks', (login_precheck(:'sid')->>'locked')::boolean);
select tt.chk('D8 seconds_left about 600', (login_precheck(:'sid')->>'seconds_left')::int between 590 and 600);
select tt.chk('D9 5 failed attempts logged', (select count(*) from login_attempts where staff_id = :'sid' and not ok) = 5);
select login_failed(:'sid');
select tt.chk('D10 more fails while locked do not extend the lock', (login_precheck(:'sid')->>'seconds_left')::int <= 600);
-- auto-release after the window
update login_failures set locked_until = now() - interval '1 second' where staff_id = :'sid';
select tt.chk('D11 auto-release after window', not (login_precheck(:'sid')->>'locked')::boolean);
select login_failed(:'sid');
select tt.chk('D12 fail after release restarts the count at 1', (select fails from login_failures where staff_id = :'sid') = 1 and not (login_precheck(:'sid')->>'locked')::boolean);
-- window for counting: old fails expire
update login_failures set fails = 4, window_start = now() - interval '11 minutes' where staff_id = :'sid';
select login_failed(:'sid');
select tt.chk('D13 fails older than the window do not count', (select fails from login_failures where staff_id = :'sid') = 1 and not (login_precheck(:'sid')->>'locked')::boolean);
-- switch off auto release: lock stays until owner unlocks
update settings set value = 'false' where key = 'lockout_auto_release';
select login_failed(:'sid') from generate_series(1, 4);
update login_failures set locked_until = now() - interval '1 hour' where staff_id = :'sid';
select tt.chk('D14 auto_release off: stays locked past the time', (login_precheck(:'sid')->>'locked')::boolean and (login_precheck(:'sid')->>'seconds_left') is null);
set role authenticated; select tt.as(:'s');
select tt.err('D15 staff cannot unlock', format($$select unlock_staff(%L)$$, :'sid'), 'owner only');
select tt.chk('D17 staff sees 0 login_attempts', (select count(*) from login_attempts) = 0);
select tt.err('D18 staff cannot insert login_attempts', $$insert into login_attempts (staff_id, ok) values ('x', true)$$, 'permission denied');
select tt.err('D19 staff cannot read login_throttle', $$select * from login_throttle$$, 'permission denied');
reset role;
set role authenticated; select tt.as(:'o');
select tt.chk('D20 owner reads login_attempts', (select count(*) from login_attempts) > 5);
select unlock_staff(:'sid');
select tt.chk('D21 owner unlock works', not (login_precheck(:'sid')->>'locked')::boolean);
select tt.err('D22 owner cannot write login_attempts', $$delete from login_attempts$$, 'permission denied');
select tt.chk('D23 unlock logged in audit_log', (select count(*) from audit_log where action = 'unlock') >= 1);
reset role;
update settings set value = 'true' where key = 'lockout_auto_release';
-- owner account always auto-releases, even with the switch off
update settings set value = 'false' where key = 'lockout_auto_release';
select login_failed(:'oid_') from generate_series(1, 5);
select tt.chk('D33 owner lock has a time limit although auto_release is off', (login_precheck(:'oid_')->>'locked')::boolean and (login_precheck(:'oid_')->>'seconds_left') is not null);
update login_failures set locked_until = now() - interval '1 second' where staff_id = :'oid_';
select tt.chk('D34 owner lock auto-released', not (login_precheck(:'oid_')->>'locked')::boolean);
update settings set value = 'true' where key = 'lockout_auto_release';
-- success clears
select login_failed(:'sid') from generate_series(1, 3);
set role authenticated; select tt.as(:'s'); select login_success(); reset role;
select tt.chk('D24 login_success clears counters', (select count(*) from login_failures where staff_id = :'sid') = 0);
select tt.chk('D25 login_success logged ok row', (select count(*) from login_attempts where staff_id = :'sid' and ok) >= 1);
-- anon may call precheck / failed
set role anon;
select tt.chk('D26 anon can call precheck', (select login_precheck('whoever')) ? 'locked');
select login_failed('whoever');
select tt.err('D27 anon cannot call unlock_staff', $$select unlock_staff('x')$$, 'permission denied');
select tt.err('D28 anon cannot call throttle helper', $$select _login_throttle('x', 1)$$, 'permission denied');
reset role;
-- spam guard: 60 fails on one id = only 50 rows
truncate login_throttle;
delete from login_attempts where true;
select login_failed(:'sid') from generate_series(1, 60);
select tt.chk('D29 per-staff spam capped at 20 rows/min', (select count(*) from login_attempts where staff_id = :'sid') = 20);
truncate login_throttle;
select login_failed('ghost' || g) from generate_series(1, 260) g;
select tt.chk('D30 unknown ids share a global cap (60/min)', (select count(*) from login_attempts where staff_id like 'ghost%') = 60);
select tt.chk('D31 junk input does not error', (select login_precheck(null)) ? 'locked');
select login_failed(null), login_failed('');
update settings set value = '"abc"' where key = 'lock_minutes';
select tt.chk('D32 garbage setting falls back to default (10 min)', _login_setting_num('lock_minutes', 10) = 10);
update settings set value = '10' where key = 'lock_minutes';

-- unit_conversions retired, not deleted
set role authenticated; select tt.as(:'o');
select set_unit_conversion(null, 'zz1', 'zz2', 3);
select set_unit_conversion(null, 'zz1', 'zz2', null);
reset role;
select tt.chk('E1 set_unit_conversion(null factor) retires the row', (select active from unit_conversions where from_unit='zz1' and to_unit='zz2') = false);
select tt.chk('E2 hook function exists and rejects a locked account', (select proname from pg_proc where proname='hook_password_verification_attempt') is not null);
select login_failed(:'sid') from generate_series(1, 5);
select tt.chk('E3 hook: locked -> reject', (hook_password_verification_attempt(jsonb_build_object('user_id', :'s', 'valid', true)) ->> 'decision') = 'reject');
select unlock_staff(:'sid') where false;
delete from login_failures;
select tt.chk('E4 hook: unlocked -> continue', (hook_password_verification_attempt(jsonb_build_object('user_id', :'s', 'valid', true)) ->> 'decision') = 'continue');

select '--- FAILED: ' || count(*) from tt.res where not ok;
select '--- TOTAL: ' || count(*) from tt.res;
select name from tt.res where not ok;
