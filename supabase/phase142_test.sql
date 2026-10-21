-- FRESH DB ONLY. Phase 142 tests (W1-FIX finding 8: a login linked after the person left is locked out again; coming back from a leaving status needs the owner).
--   build a database through phase 99 (tests/sql/ORDER.txt), paste phase142.sql once, then:
--   psql -h /tmp -p 5610 -U postgres -d a142db -qAt -f supabase/phase142_test.sql | grep -E 'FAIL|RESULT'      (run from the repository root)
-- Test data only (test_* names). Both gaps were reproduced on a database through phase 99 before this phase (see docs/integration/W1-FIX.md).
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000142'
\set u_o2 '00000000-0000-0000-0000-000000000242'
\set u_hr '00000000-0000-0000-0000-000000000342'
\set u_c1 '00000000-0000-0000-0000-000000000442'
\set u_c2 '00000000-0000-0000-0000-000000000542'
\set u_c3 '00000000-0000-0000-0000-000000000642'
\set u_c4 '00000000-0000-0000-0000-000000000742'
\set u_c5 '00000000-0000-0000-0000-000000000842'
\set u_c6 '00000000-0000-0000-0000-000000000942'
\set u_c7 '00000000-0000-0000-0000-000000001042'
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
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.mkemp(p_name text, p_loc int, p_login uuid) returns uuid language plpgsql as $$
declare a jsonb; i uuid;
begin
  a := employee_save(null, gen_random_uuid(), jsonb_build_object('full_name_bn', p_name, 'full_name_en', p_name, 'primary_location_id', p_loc, 'joining_date', (current_date - 30)::text, 'designation', 'cashier'));
  i := (a ->> 'id')::uuid;
  perform employee_submit(i);
  if p_login is not null then perform employee_link_profile(i, p_login); end if;
  return i;
end $$;
create or replace function tt.pstat(p_user uuid) returns text language sql stable security definer as $$ select status from public.profiles where id = p_user $$;
create or replace function tt.estat(p_emp uuid) returns text language sql stable security definer as $$ select status from public.employees where id = p_emp $$;
create or replace function tt.open_exc(p_flag text, p_emp uuid) returns bigint language sql stable security definer as $$
  select count(*) from public.exceptions where flag_code = p_flag and status = 'open' and text ->> 'ref' = p_emp::text $$;
create or replace function tt.live_grants(p_user uuid) returns bigint language sql stable security definer as $$
  select count(*) from public.user_grants where user_id = p_user and (valid_until is null or valid_until > now()) $$;
create or replace function tt.xlog(p_emp uuid, p_action text) returns bigint language sql stable security definer as $$
  select count(*) from public.w1c_exit_log where employee_id = p_emp and action = p_action $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner142@s.app','{"full_name":"test_owner142"}'), (:'u_o2','test_owner142b@s.app','{"full_name":"test_owner142b"}'), (:'u_hr','test_hr142@s.app','{"full_name":"test_hr142"}'),
 (:'u_c1','test_cashier142a@s.app','{"full_name":"test_cashier142a"}'), (:'u_c2','test_cashier142b@s.app','{"full_name":"test_cashier142b"}'), (:'u_c3','test_cashier142c@s.app','{"full_name":"test_cashier142c"}'),
 (:'u_c4','test_cashier142d@s.app','{"full_name":"test_cashier142d"}'), (:'u_c5','test_cashier142e@s.app','{"full_name":"test_cashier142e"}'), (:'u_c6','test_cashier142f@s.app','{"full_name":"test_cashier142f"}'), (:'u_c7','test_cashier142g@s.app','{"full_name":"test_cashier142g"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_o2','owner'),(:'u_hr','management'),(:'u_c1','salesperson'),(:'u_c2','salesperson'),(:'u_c3','salesperson'),(:'u_c4','salesperson'),(:'u_c5','salesperson'),(:'u_c6','salesperson'),(:'u_c7','salesperson') on conflict do nothing;
insert into user_locations values (:'u_hr',1),(:'u_c1',1),(:'u_c2',1),(:'u_c3',1),(:'u_c4',1),(:'u_c5',1),(:'u_c6',1),(:'u_c7',1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id, note) values (:'u_c1','sale_return',1,'test'),(:'u_c2','sale_return',1,'test'),(:'u_c3','sale_return',1,'test'),(:'u_c4','sale_return',1,'test'),(:'u_c5','sale_return',1,'test'),(:'u_c6','sale_return',1,'test'),(:'u_c7','sale_return',1,'test');

\echo == T0 shape, hooks in place, internals closed
select tt.chk('T0 phase142 present; marker bos142 is inside employee_link_profile and employee_status_set (and bos90 is still there)',
  to_regprocedure('public._w1x_present142()') is not null and position('bos142' in pg_get_functiondef('public.employee_link_profile(uuid,uuid)'::regprocedure))>0
  and position('bos142' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))>0 and position('bos90' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))>0);
select tt.chk('T0 internals closed to browsers', not has_function_privilege('authenticated','public._w1x_link_after(uuid,uuid)','execute') and not has_function_privilege('authenticated','public._w1x_reactivate_guard(uuid,text,text)','execute')
  and not has_function_privilege('anon','public._w1x142_hooks()','execute'));
select tt.chk('T0 no new setting: the fix follows exit_revoke_mode (default off) - nothing changes until the owner switches the exit rules on', coalesce(rule_txt('exit_revoke_mode'),'off')='off');

\echo == setup: people
set role authenticated; select tt.as(:'u_o');
select set_user_grant(:'u_hr'::uuid,'employee_manage') is null as g1 \gset
select tt.mkemp('test_staff_a', 1, null) as ea \gset
select tt.mkemp('test_staff_b', 1, :'u_c2') as eb \gset
select tt.mkemp('test_staff_c', 1, null) as ec \gset
select tt.mkemp('test_staff_d', 1, null) as ed \gset
select tt.mkemp('test_staff_e', 1, null) as ee \gset
select tt.mkemp('test_staff_f', 1, :'u_c6') as ef \gset
select tt.mkemp('test_staff_g', 1, :'u_c5') as eg \gset
reset role;

\echo == T1 default (exit rules OFF) = today: a login linked after the person left stays active, nothing is logged
set role authenticated; select tt.as(:'u_hr');
select employee_status_set(:'ea'::uuid,'resigned',tt.today(),'test left the job') ->> 'status' as s1 \gset
select employee_link_profile(:'ea'::uuid, :'u_c1'::uuid) ->> 'profile_id' as l1 \gset
reset role;
select tt.chk('T1 OFF: the link works as before, the login stays active, grants stay, no exit log line, no audit line of the new check',
  :'l1'=:'u_c1' and tt.pstat(:'u_c1')='active' and tt.live_grants(:'u_c1')=1 and not exists (select 1 from w1c_exit_log where employee_id=:'ea'::uuid) and not exists (select 1 from audit_log where action='staff_exit_link_checked'));
set role authenticated; select tt.as(:'u_o');
select set_rule('exit_revoke_statuses','"resigned,terminated,retired,on_leave"') is null as st1 \gset
select tt.as(:'u_hr');
select employee_status_set(:'eb'::uuid,'on_leave',tt.today(),'test leave') ->> 'status' as s1b \gset
select employee_status_set(:'eb'::uuid,'active',tt.today(),'test back') ->> 'status' as s1c \gset
reset role;
select tt.chk('T1 OFF: HR sets a person on leave and back again, as always; the login is never touched', :'s1b'='on_leave' and :'s1c'='active' and tt.pstat(:'u_c2')='active');

\echo == T2 mode auto: a login linked after the person left is locked out at once
set role authenticated; select tt.as(:'u_o');
select set_rule('exit_revoke_mode','"auto"') is null as m1 \gset
select tt.as(:'u_hr');
select employee_status_set(:'ec'::uuid,'resigned',tt.today(),'test left, no login yet') ->> 'status' as s2 \gset
reset role;
select tt.chk('T2 the person left with no login: yellow line "no linked login" (phase90, unchanged)', tt.xlog(:'ec'::uuid,'no_linked_login')=1 and tt.open_exc('exit_no_login_link',:'ec'::uuid)=1);
set role authenticated; select tt.as(:'u_hr');
select employee_link_profile(:'ec'::uuid, :'u_c3'::uuid) ->> 'profile_id' as l2 \gset
reset role;
select tt.chk('T2 HR links a login to the leaver: the answer is the same as before, but the login is disabled and its grant ended',
  :'l2'=:'u_c3' and tt.pstat(:'u_c3')='disabled' and tt.live_grants(:'u_c3')=0 and (select profile_id from employees where id=:'ec'::uuid)=:'u_c3'::uuid);
select tt.chk('T2 it is in the exit log (revoked) with the reason and in the audit log (staff_exit_link_checked)', tt.xlog(:'ec'::uuid,'revoked')=1
  and (select reason from w1c_exit_log where employee_id=:'ec'::uuid and action='revoked')='login linked after the person had left'
  and (select count(*) from audit_log where action='staff_exit_link_checked' and record_id=:'ec' and detail->'result'->>'action'='revoked')=1
  and exists (select 1 from audit_log where action='staff_exit_access_revoked' and detail->>'employee'=:'ec'));
-- not left: nothing happens
set role authenticated; select tt.as(:'u_hr');
select employee_link_profile(:'ed'::uuid, :'u_c4'::uuid) ->> 'profile_id' as l2b \gset
select employee_link_profile(:'ed'::uuid, null) ->> 'id' as l2c \gset
reset role;
select tt.chk('T2 an active person: linking works and the login stays active; unlinking does nothing special', :'l2b'=:'u_c4' and tt.pstat(:'u_c4')='active' and :'l2c'=:'ed' and tt.live_grants(:'u_c4')=1);
-- a login with the owner role is never disabled by this feature (red line instead)
set role authenticated; select tt.as(:'u_o');
select employee_status_set(:'ee'::uuid,'terminated',tt.today(),'test ended') ->> 'status' as s2d \gset
select tt.as(:'u_hr');
select employee_link_profile(:'ee'::uuid, :'u_o2'::uuid) ->> 'profile_id' as l2d \gset
reset role;
select tt.chk('T2 a login that holds the owner role is not disabled; a red line tells the owner', :'l2d'=:'u_o2' and tt.pstat(:'u_o2')='active' and tt.xlog(:'ee'::uuid,'skipped_owner')=1 and tt.open_exc('exit_access_open',:'ee'::uuid)=1);
-- keep access: the owner keeps the login on purpose, the person leaves, a login is unlinked and linked again
set role authenticated; select tt.as(:'u_o');
select _w1c_exit_keep(:'eg'::uuid, 'test: the owner keeps this access on purpose') is not null as kp \gset
select employee_status_set(:'eg'::uuid,'retired',tt.today(),'test retired') ->> 'status' as s2e \gset
select tt.as(:'u_hr');
select employee_link_profile(:'eg'::uuid, null) ->> 'id' as l2e0 \gset
select employee_link_profile(:'eg'::uuid, :'u_c5'::uuid) ->> 'profile_id' as l2e \gset
reset role;
select tt.chk('T2 access the owner kept on purpose is not locked out by a later link (log says kept)', :'l2e'=:'u_c5' and tt.pstat(:'u_c5')='active' and tt.xlog(:'eg'::uuid,'kept')>=2 and tt.xlog(:'eg'::uuid,'revoked')=0);
-- running the check again for the same person in the same transaction is not skipped (unlink and link again)
set role authenticated; select tt.as(:'u_hr');
select employee_link_profile(:'ec'::uuid, null) ->> 'id' as l2f \gset
reset role;
update profiles set status='active' where id=:'u_c3';
set role authenticated; select tt.as(:'u_hr');
select employee_link_profile(:'ec'::uuid, :'u_c3'::uuid) ->> 'profile_id' as l2g \gset
reset role;
select tt.chk('T2 unlink, then link the (re-enabled) login again: it is disabled again', tt.pstat(:'u_c3')='disabled' and tt.xlog(:'ec'::uuid,'revoked')=2);

\echo == T3 mode alert: only the red line
set role authenticated; select tt.as(:'u_o');
select set_rule('exit_revoke_mode','"alert"') is null as m2 \gset
select tt.mkemp('test_staff_h', 1, null) as eh \gset
select employee_status_set(:'eh'::uuid,'resigned',tt.today(),'test left') ->> 'status' as s3 \gset
select tt.as(:'u_hr');
select employee_link_profile(:'eh'::uuid, :'u_c7'::uuid) ->> 'profile_id' as l3 \gset
reset role;
select tt.chk('T3 alert mode: the login is NOT disabled, a red line "login still active" is raised', :'l3'=:'u_c7' and tt.pstat(:'u_c7')='active' and tt.open_exc('exit_access_open',:'eh'::uuid)=1 and tt.xlog(:'eh'::uuid,'alert_only')=1);

\echo == T4 coming back: when the exit step disabled the login, only the owner brings the person back
set role authenticated; select tt.as(:'u_o');
select set_rule('exit_revoke_mode','"auto"') is null as m3 \gset
select tt.as(:'u_hr');
select employee_status_set(:'eb'::uuid,'on_leave',tt.today(),'test leave again') ->> 'status' as s4 \gset
reset role;
select tt.chk('T4 on_leave counts as leaving here: the login of test_staff_b is disabled', tt.estat(:'eb'::uuid)='on_leave' and tt.pstat(:'u_c2')='disabled' and tt.xlog(:'eb'::uuid,'revoked')=1);
set role authenticated; select tt.as(:'u_hr');
select tt.err('T4 HR cannot bring the person back (owner_only)', format($$select employee_status_set(%L::uuid,'active',tt.today(),'test back')$$, :'eb'), 'owner_only');
reset role;
select tt.chk('T4 the refusal changed nothing: still on leave, login still disabled', tt.estat(:'eb'::uuid)='on_leave' and tt.pstat(:'u_c2')='disabled');
set role authenticated; select tt.as(:'u_o');
select employee_status_set(:'eb'::uuid,'active',tt.today(),'test owner brings back') ->> 'status' as s4b \gset
reset role;
select tt.chk('T4 the owner brings the person back: status active, login enabled again, logged with the reason', :'s4b'='active' and tt.pstat(:'u_c2')='active' and tt.xlog(:'eb'::uuid,'reenabled')=1
  and exists (select 1 from audit_log where action='staff_exit_login_reenabled' and detail->>'employee'=:'eb' and detail->>'reason'='test owner brings back'));
-- a login that somebody else disabled (the exit step only logged "already_disabled"): HR may still bring the person back, the login stays disabled (phase90 rule)
update profiles set status='disabled' where id=:'u_c6';
set role authenticated; select tt.as(:'u_hr');
select employee_status_set(:'ef'::uuid,'on_leave',tt.today(),'test leave f') ->> 'status' as s4d \gset
select employee_status_set(:'ef'::uuid,'active',tt.today(),'test back f') ->> 'status' as s4e \gset
reset role;
select tt.chk('T4 a login disabled by someone else is not the exit step''s: HR can move the person back, the login stays disabled', :'s4d'='on_leave' and :'s4e'='active' and tt.pstat(:'u_c6')='disabled'
  and tt.xlog(:'ef'::uuid,'already_disabled')=1 and tt.xlog(:'ef'::uuid,'revoked')=0);
-- resigned -> active stays owner_only (phase41 rule)
set role authenticated; select tt.as(:'u_hr');
select tt.err('T4 resigned to active by HR is still owner_only (existing rule)', format($$select employee_status_set(%L::uuid,'active',tt.today(),'test back')$$, :'ea'), 'owner_only');
select tt.err('T4 retired to active by HR is still owner_only (existing rule)', format($$select employee_status_set(%L::uuid,'active',tt.today(),'test back')$$, :'eg'), 'owner_only');
reset role;

\echo == T5 mode OFF again: the old behaviour for everything above
set role authenticated; select tt.as(:'u_o');
select set_rule('exit_revoke_mode','"off"') is null as m4 \gset
select tt.as(:'u_hr');
select employee_status_set(:'ed'::uuid,'on_leave',tt.today(),'test leave d3') ->> 'status' as s5b \gset
select employee_status_set(:'ed'::uuid,'active',tt.today(),'test back by HR with the rules off') ->> 'status' as s5c \gset
reset role;
select tt.chk('T5 OFF: HR moves the person on leave and back, no refusal, the login is not touched', :'s5b'='on_leave' and :'s5c'='active' and tt.pstat(:'u_c4')='active' and tt.xlog(:'ed'::uuid,'revoked')=0);

\echo == T6 hooks idempotent; no demo names
select public._w1x142_hooks() as again \gset
select tt.chk('T6 a second call of the hook function changes nothing', :'again'::jsonb = '{"employee_status_set": false, "employee_link_profile": false}'::jsonb);
select tt.chk('T6 no demo data: every name in this file starts with test_', not exists (select 1 from profiles where full_name <> '' and full_name not like 'test\_%') and not exists (select 1 from employees where full_name_en not like 'test\_%'));
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
