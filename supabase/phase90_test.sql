-- FRESH DB ONLY. Phase 90 tests (U-03 staff exit revokes login, grants and device tokens; statuses configurable).
--   ORDER="phase8 ... phase87 phase90" bash tests/sql/build_fresh_db.sh a90db          (port 5563 here)
--   psql -h /tmp -p 5563 -U postgres -d a90db -qAt -f supabase/phase90_test.sql | grep -E 'FAIL|RESULT'      (run from the repository root)
-- Test data only (test_* names). The hook for employee_status_set is proved at the end on a SCRATCH COPY of the database (created and dropped by this file);
-- the shared function in the tested database is never patched.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000000090'
\set u_o2 '00000000-0000-0000-0000-000000000190'
\set u_hr '00000000-0000-0000-0000-000000000290'
\set u_c1 '00000000-0000-0000-0000-000000000390'
\set u_c2 '00000000-0000-0000-0000-000000000490'
\set u_c4 '00000000-0000-0000-0000-000000000590'
\set u_k '00000000-0000-0000-0000-000000000690'
\set u_c5 '00000000-0000-0000-0000-000000000790'
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
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
-- register one employee (as the owner), optionally link a login
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
create or replace function tt.open_exc(p_flag text, p_emp uuid) returns bigint language sql stable security definer as $$
  select count(*) from public.exceptions where flag_code = p_flag and status = 'open' and text ->> 'ref' = p_emp::text $$;
create or replace function tt.live_grants(p_user uuid) returns bigint language sql stable security definer as $$
  select count(*) from public.user_grants where user_id = p_user and (valid_until is null or valid_until > now()) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner90@s.app','{"full_name":"test_owner90"}'), (:'u_o2','test_owner90b@s.app','{"full_name":"test_owner90b"}'), (:'u_hr','test_hr90@s.app','{"full_name":"test_hr90"}'),
 (:'u_c1','test_cashier1@s.app','{"full_name":"test_cashier1"}'), (:'u_c2','test_cashier2@s.app','{"full_name":"test_cashier2"}'), (:'u_c4','test_cashier4@s.app','{"full_name":"test_cashier4"}'),
 (:'u_k','test_keeper90@s.app','{"full_name":"test_keeper90"}'), (:'u_c5','test_cashier5@s.app','{"full_name":"test_cashier5"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'u_o','owner'),(:'u_o2','owner'),(:'u_hr','management'),(:'u_c1','salesperson'),(:'u_c2','salesperson'),(:'u_c4','salesperson'),(:'u_k','management'),(:'u_c5','salesperson') on conflict do nothing;
insert into user_locations values (:'u_hr',1),(:'u_c1',1),(:'u_c2',1),(:'u_c4',1),(:'u_k',1),(:'u_c5',1) on conflict do nothing;

\echo == T0 shape, safe defaults, internals closed
select tt.chk('T0 phase90 present, tables exist with RLS and no browser write right',
  to_regprocedure('public._w1c_present90()') is not null and (select count(*) from pg_class c where c.relname in ('w1c_exit_log','w1c_exit_keep') and c.relrowsecurity)=2
  and not has_table_privilege('authenticated','public.w1c_exit_log','insert') and not has_table_privilege('authenticated','public.w1c_exit_keep','update') and not has_table_privilege('anon','public.w1c_exit_log','select'));
select tt.chk('T0 four settings with safe defaults: mode off, statuses resigned/terminated/retired, alert hours blank, devices off',
  rule_txt('exit_revoke_mode')='off' and rule_txt('exit_revoke_statuses')='resigned,terminated,retired' and rule_num('exit_alert_hours') is null and not rule_on('exit_deactivate_devices'));
select tt.chk('T0 every setting has an English label and hint', (select count(*) from rules where key in ('exit_revoke_mode','exit_revoke_statuses','exit_alert_hours','exit_deactivate_devices') and label_en ~ '^[A-Za-z]' and hint_en ~ '^[A-Za-z]')=4);
select tt.chk('T0 grant exit_keep_access exists and nobody holds it by role', exists (select 1 from grant_defs where grant_code='exit_keep_access') and not exists (select 1 from rule_grants where grant_code='exit_keep_access' and allowed));
select tt.chk('T0 internals closed to browsers, screen calls open to signed-in users only',
  not has_function_privilege('authenticated','public._w1c_exit_apply(uuid,text,text,date,text)','execute') and not has_function_privilege('authenticated','public._w1c_patch(regprocedure,text[],text)','execute')
  and not has_function_privilege('anon','public._w1c_exit_keep(uuid,text)','execute') and has_function_privilege('authenticated','public._w1c_exit_keep(uuid,text)','execute')
  and not has_function_privilege('authenticated','public._w1c_exc(int,text,text,text,text,text,numeric,date)','execute') and not has_function_privilege('authenticated','public._w1c_exit_scan_run()','execute'));
select tt.chk('T0 the shared function employee_status_set is NOT patched here', position('bos90' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))=0);

\echo == setup: people and logins
set role authenticated; select tt.as(:'u_o');
select set_user_grant(:'u_hr'::uuid,'employee_manage') is null as g1 \gset
select tt.mkemp('test_staff_one', 1, :'u_c1') as e1 \gset
select tt.mkemp('test_staff_two', 1, :'u_c2') as e2 \gset
select tt.mkemp('test_staff_three', 1, null) as e3 \gset
select tt.mkemp('test_staff_four', 1, :'u_c4') as e4 \gset
select tt.mkemp('test_staff_five', 1, :'u_c5') as e5 \gset
select tt.mkemp('test_owner_staff', 1, :'u_o2') as eo \gset
select tt.mkemp('test_hr_staff', 1, :'u_hr') as eh \gset
reset role;
insert into user_grants (user_id, grant_code, location_id, note) values (:'u_c1','sale_return',1,'test'),(:'u_c1','wastage_write_off',1,'test'),(:'u_c2','sale_return',1,'test'),(:'u_c4','sale_return',1,'test'),(:'u_c5','sale_return',1,'test');
insert into list_managers (list_code, user_id) values ('return_reasons', :'u_c1');
insert into attendance_devices (name, location_id, token_hash, created_by) values ('test_device_c1', 1, 'hash_c1_90', :'u_c1'), ('test_device_c2', 1, 'hash_c2_90', :'u_c2');
select tt.chk('setup: seven people, six linked logins, grants given', (select count(*) from employees where status='active')=7 and tt.live_grants(:'u_c1')=2);

\echo == T1 default = today: with mode off nothing is touched
set role authenticated; select tt.as(:'u_hr');
select _w1c_employee_status_set(:'e1'::uuid,'resigned',tt.today(),'test left the job') ->> 'status' as s1 \gset
select tt.chk('T1 status changed as always', :'s1'='resigned' and (select status from employees where id=:'e1'::uuid)='resigned');
select tt.chk('T1 login still active, grants still live, no exit log, no exception (old behaviour)', tt.pstat(:'u_c1')='active' and tt.live_grants(:'u_c1')=2
  and not exists (select 1 from w1c_exit_log where employee_id=:'e1'::uuid) and tt.open_exc('exit_access_open',:'e1'::uuid)=0);
select tt.as(:'u_o'); select employee_status_set(:'e1'::uuid,'active',tt.today(),'rehired for the test') is not null as rh \gset
select tt.chk('T1 owner brought the person back; still nothing logged', (select status from employees where id=:'e1'::uuid)='active' and not exists (select 1 from w1c_exit_log where employee_id=:'e1'::uuid));

\echo == T2 settings: owner only, validated, audited
select tt.as(:'u_hr');
select tt.err('T2 HR cannot change the settings', $$select _w1c_exit_settings_set('auto','resigned,terminated,retired',null,false)$$, 'not allowed');
select tt.chk('T2 HR can read them', (_w1c_exit_settings() ->> 'mode')='off');
select tt.as(:'u_c2'); select tt.err('T2 a cashier cannot even read them', $$select _w1c_exit_settings()$$, 'not allowed');
select tt.as(:'u_o');
select tt.err('T2 bad mode refused', $$select _w1c_exit_settings_set('sometimes','resigned',null,false)$$, 'bad_mode');
select tt.err('T2 unknown status refused', $$select _w1c_exit_settings_set('auto','resigned,fired',null,false)$$, 'bad_statuses');
select tt.err('T2 empty status list refused', $$select _w1c_exit_settings_set('auto','',null,false)$$, 'bad_statuses');
select tt.err('T2 negative alert hours refused', $$select _w1c_exit_settings_set('auto','resigned',-1,false)$$, 'bad_hours');
select tt.err('T2 the Rules page cannot save an unknown status either', $$select set_rule('exit_revoke_statuses','"resigned,bogus"'::jsonb)$$, 'bad_value');
select tt.err('T2 a wrong mode through the Rules page is refused', $$select set_rule('exit_revoke_mode','"maybe"'::jsonb)$$, 'bad_value');
select _w1c_exit_settings_set('auto','resigned,terminated,retired',null,false,'go live') ->> 'mode' as m2 \gset
select tt.chk('T2 owner switched to auto', :'m2'='auto' and rule_txt('exit_revoke_mode')='auto');
reset role;
select tt.chk('T2 every change is an audit_log line (summary line + rules audit)', exists (select 1 from audit_log where action='exit_settings_changed' and detail #>> '{new,mode}'='auto' and detail #>> '{old,mode}'='off')
  and exists (select 1 from audit_log where table_name='rules' and record_id='exit_revoke_mode' and detail #>> '{new,value}'='auto'));
set role authenticated;

\echo == T3 auto: resigned -> login disabled, grants ended, list rows ended, device token left alone (switch off)
select tt.as(:'u_hr');
select _w1c_employee_status_set(:'e1'::uuid,'resigned',tt.today(),'test left the job') as r3 \gset
select tt.chk('T3 answer says revoked with 2 grants', (:'r3'::jsonb #>> '{exit,action}')='revoked' and (:'r3'::jsonb #>> '{exit,grants_ended}')='2');
reset role;
select tt.chk('T3 profile disabled, grants ended (rows kept, not deleted), list manager row inactive', tt.pstat(:'u_c1')='disabled' and tt.live_grants(:'u_c1')=0
  and (select count(*) from user_grants where user_id=:'u_c1')=2 and not (select active from list_managers where user_id=:'u_c1'));
select tt.chk('T3 device token untouched while the switch is off', (select active from attendance_devices where token_hash='hash_c1_90'));
select tt.chk('T3 one log row, one audit_log line with the numbers', (select count(*) from w1c_exit_log where employee_id=:'e1'::uuid and action='revoked' and grants_ended=2 and lists_ended=1 and devices_off=0)=1
  and (select count(*) from audit_log where action='staff_exit_access_revoked' and record_id=:'u_c1' and (detail->>'grants_ended')='2')=1);
set role authenticated; select tt.as(:'u_c1');
select tt.chk('T3 the disabled person is refused by the server', not is_active() and not has_grant('sale_return',1));
select tt.err('T3 and cannot call a protected function', $$select _w1c_exit_settings()$$, 'not allowed');
select tt.as(:'u_o');
select _w1c_employee_status_set(:'e1'::uuid,'terminated',tt.today(),'second exit status') #>> '{exit,action}' as a3b \gset
reset role;
select tt.chk('T3 a second exit status for a person already disabled changes nothing more', :'a3b'='already_disabled' and tt.pstat(:'u_c1')='disabled' and (select count(*) from w1c_exit_log where employee_id=:'e1'::uuid and action='revoked')=1);
set role authenticated; select tt.as(:'u_o'); select employee_status_set(:'e1'::uuid,'resigned',tt.today(),'back to resigned for the next test') is not null as r3c \gset
reset role;

\echo == T4 device switch on: only tokens THIS person registered go off
set role authenticated; select tt.as(:'u_o');
select _w1c_exit_settings_set('auto','resigned,terminated,retired',null,true,'tokens too') is not null as s4 \gset
select tt.as(:'u_hr');
select _w1c_employee_status_set(:'e2'::uuid,'terminated',tt.today(),'test dismissed') #>> '{exit,devices_off}' as d2 \gset
reset role;
select tt.chk('T4 device of the dismissed person is off, the other token is still on', :'d2'='1' and not (select active from attendance_devices where token_hash='hash_c2_90') and (select active from attendance_devices where token_hash='hash_c1_90'));
select tt.chk('T4 login of the second person disabled too', tt.pstat(:'u_c2')='disabled');

\echo == T5 re-hire: login comes back, grants and devices do not
set role authenticated; select tt.as(:'u_hr');
select tt.err('T5 HR cannot bring someone back (existing owner-only rule)', format($$select _w1c_employee_status_set(%L::uuid,'active',tt.today(),'rehire')$$, :'e1'), 'owner_only');
select tt.as(:'u_o');
select _w1c_employee_status_set(:'e1'::uuid,'active',tt.today(),'test rehired') #>> '{exit,action}' as a5 \gset
reset role;
select tt.chk('T5 login enabled again, answer says reenabled', :'a5'='reenabled' and tt.pstat(:'u_c1')='active');
select tt.chk('T5 grants are NOT restored automatically', tt.live_grants(:'u_c1')=0 and (select count(*) from user_grants where user_id=:'u_c1')=2);
select tt.chk('T5 log has revoked then reenabled, audit line written', (select string_agg(action, ',' order by id) from w1c_exit_log where employee_id=:'e1'::uuid and action in ('revoked','reenabled'))='revoked,reenabled'
  and exists (select 1 from audit_log where action='staff_exit_login_reenabled' and record_id=:'u_c1'));
update profiles set status='disabled' where id=:'u_c4';
set role authenticated; select tt.as(:'u_o');
select employee_status_set(:'e4'::uuid,'on_leave',tt.today(),'test leave') is not null as l4 \gset
select employee_status_set(:'e4'::uuid,'active',tt.today(),'test back') is not null as b4 \gset
reset role;
select tt.chk('T5 manual disable stays disabled when the person comes back (this feature did not do it)', tt.pstat(:'u_c4')='disabled');
update profiles set status='active' where id=:'u_c4';

\echo == T6 exception path: keep access with a reason
set role authenticated; select tt.as(:'u_hr');
select tt.err('T6 HR without the grant cannot keep access', format($$select _w1c_exit_keep(%L::uuid,'needed for handover')$$, :'e5'), 'not allowed');
select tt.as(:'u_k'); select tt.err('T6 a manager without the grant cannot keep access', format($$select _w1c_exit_keep(%L::uuid,'needed for handover')$$, :'e5'), 'not allowed');
select tt.as(:'u_o');
select tt.err('T6 a reason is required', format($$select _w1c_exit_keep(%L::uuid,'')$$, :'e5'), 'reason_required');
select tt.err('T6 a two letter reason is refused', format($$select _w1c_exit_keep(%L::uuid,'ok')$$, :'e5'), 'reason_required');
select tt.err('T6 a person without a login cannot be kept', format($$select _w1c_exit_keep(%L::uuid,'no login at all')$$, :'e3'), 'no_linked_login');
select _w1c_exit_keep(:'e5'::uuid,'handover of the till until the month end') ->> 'kept' as k5 \gset
select tt.chk('T6 owner keeps the access of person five', :'k5'='true' and exists (select 1 from w1c_exit_keep where employee_id=:'e5'::uuid and ended_at is null));
select tt.as(:'u_hr');
select _w1c_employee_status_set(:'e5'::uuid,'resigned',tt.today(),'test left') #>> '{exit,action}' as a6 \gset
reset role;
select tt.chk('T6 the person who left stays active because access was kept', :'a6'='kept' and tt.pstat(:'u_c5')='active' and tt.live_grants(:'u_c5')=1);
select tt.chk('T6 audit_log line with the reason, yellow row in the Exceptions list', exists (select 1 from audit_log where action='staff_exit_access_kept' and detail->>'reason' = 'handover of the till until the month end')
  and exists (select 1 from exceptions where flag_code='exit_access_kept' and level='yellow' and text->>'en' like '%handover of the till%'));
set role authenticated; select tt.as(:'u_o');
select set_user_grant(:'u_k'::uuid,'exit_keep_access') is null as gk \gset
select tt.as(:'u_k');
select tt.chk('T6 the owner can give the right to anyone: the manager with the grant now holds it (not tied to a role)', has_grant('exit_keep_access'));
select _w1c_exit_keep_end(:'e5'::uuid,'handover is finished') #>> '{exit,action}' as ke \gset
reset role;
select tt.chk('T6 ending the keep applies the exit at once (auto mode)', :'ke'='revoked' and tt.pstat(:'u_c5')='disabled' and tt.live_grants(:'u_c5')=0);
select tt.chk('T6 keep record is closed, not deleted, with the end reason', exists (select 1 from w1c_exit_keep where employee_id=:'e5'::uuid and ended_at is not null and end_reason='handover is finished'));
set role authenticated; select tt.as(:'u_k');
select tt.err('T6 ending a keep that is not open is refused', format($$select _w1c_exit_keep_end(%L::uuid,'again please')$$, :'e5'), 'not_kept');
reset role;

\echo == T7 keep after the login was disabled puts the login back (grants stay ended)
set role authenticated; select tt.as(:'u_o');
select _w1c_exit_keep(:'e2'::uuid,'needs the stock report for one week') ->> 'login_restored' as lr \gset
reset role;
select tt.chk('T7 login restored by the owner exception; grants and device token NOT restored', :'lr'='true' and tt.pstat(:'u_c2')='active' and tt.live_grants(:'u_c2')=0
  and not (select active from attendance_devices where token_hash='hash_c2_90'));
set role authenticated; select tt.as(:'u_o'); select _w1c_exit_keep_end(:'e2'::uuid,'week is over') is not null as ke2 \gset
reset role;
select tt.chk('T7 ending that keep disables the login again', tt.pstat(:'u_c2')='disabled');

\echo == T8 a person without a linked login, the owner login and the caller are never disabled by accident
set role authenticated; select tt.as(:'u_hr');
select _w1c_employee_status_set(:'e3'::uuid,'resigned',tt.today(),'test no login') #>> '{exit,action}' as a8 \gset
select tt.chk('T8 no linked login: logged, yellow exception, nothing else', :'a8'='no_linked_login');
select tt.as(:'u_o');
select _w1c_employee_status_set(:'eo'::uuid,'resigned',tt.today(),'test owner left') #>> '{exit,action}' as ao \gset
reset role;
select tt.chk('T8 a person who holds the owner role keeps the login; red exception for the owner', :'ao'='skipped_owner' and tt.pstat(:'u_o2')='active' and tt.open_exc('exit_access_open',:'eo'::uuid)=1);
set role authenticated; select tt.as(:'u_hr');
select _w1c_employee_status_set(:'eh'::uuid,'resigned',tt.today(),'test own exit') #>> '{exit,action}' as ah \gset
reset role;
select tt.chk('T8 the caller is never locked out by his own click; red exception raised', :'ah'='skipped_self' and tt.pstat(:'u_hr')='active' and tt.open_exc('exit_access_open',:'eh'::uuid)=1);
select tt.chk('T8 the no-login case has a yellow exception', exists (select 1 from exceptions where flag_code='exit_no_login_link' and level='yellow' and text->>'ref'=:'e3'));

\echo == T9 alert mode: nothing is disabled, a red exception appears
set role authenticated; select tt.as(:'u_o');
select _w1c_exit_settings_set('alert','resigned,terminated,retired',null,false) is not null as s9 \gset
select tt.mkemp('test_staff_six', 1, null) as e6 \gset
reset role;
insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-000000000890','test_cashier6@s.app','{"full_name":"test_cashier6"}') on conflict do nothing;
update profiles set status='active' where id='00000000-0000-0000-0000-000000000890';
set role authenticated; select tt.as(:'u_o');
select employee_link_profile(:'e6'::uuid,'00000000-0000-0000-0000-000000000890') is not null as l6 \gset
select tt.as(:'u_hr');
select _w1c_employee_status_set(:'e6'::uuid,'retired',tt.today(),'test retired') #>> '{exit,action}' as a9 \gset
reset role;
select tt.chk('T9 alert only: login still active, grants untouched, one red exception', :'a9'='alert_only' and tt.pstat('00000000-0000-0000-0000-000000000890')='active' and tt.open_exc('exit_access_open',:'e6'::uuid)=1);

\echo == T10 scan: login still active N hours after leaving
set role authenticated; select tt.as(:'u_c2'); select tt.err('T10 a cashier cannot run the scan', $$select _w1c_exit_scan()$$, 'not allowed');
select tt.as(:'u_o');
select _w1c_exit_settings_set('off','resigned,terminated,retired',null,false) is not null as s10 \gset
select _w1c_exit_scan() ->> 'skipped' as sk \gset
select tt.chk('T10 hours blank = the scan is off', :'sk'='alert_hours_blank');
reset role;
update profiles set status='active' where id in (:'u_c5');
set role authenticated; select tt.as(:'u_o');
select _w1c_exit_settings_set('off','resigned,terminated,retired',0,false) is not null as s10b \gset
select (_w1c_exit_scan() ->> 'raised')::int as n1 \gset
select (_w1c_exit_scan() ->> 'raised')::int as n2 \gset
reset role;
select tt.chk('T10 scan raised for the leaver whose login is active (person five), a second scan raises nothing new', :'n1'>=1 and :'n2'=0 and tt.open_exc('exit_access_open',:'e5'::uuid)=1);
select tt.chk('T10 the owner login is never flagged by the scan', tt.open_exc('exit_access_open',:'eo'::uuid)=1);
set role authenticated; select tt.as(:'u_o');
select _w1c_exit_keep(:'e5'::uuid,'back for a short job') is not null as k10 \gset
reset role;
select tt.chk('T10 keeping access closes the open red exception of that person', tt.open_exc('exit_access_open',:'e5'::uuid)=0);
set role authenticated; select tt.as(:'u_o');
select jsonb_array_length(_w1c_exit_open_list()) as ol \gset
select tt.chk('T10 the open list shows people who left and still can log in', :'ol'>=1);
select jsonb_array_length(_w1c_exit_log_list(50)) as ll \gset
select tt.chk('T10 the log list answers', :'ll'>=5);
reset role;

\echo == T11 statuses are configurable (on_leave can revoke when the owner wants it; terminated can be left out)
set role authenticated; select tt.as(:'u_o');
select _w1c_exit_settings_set('auto','resigned,on_leave',null,false) is not null as s11 \gset
select tt.mkemp('test_staff_seven', 1, null) as e7 \gset
reset role;
insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-000000000891','test_cashier7@s.app','{"full_name":"test_cashier7"}') on conflict do nothing;
update profiles set status='active' where id='00000000-0000-0000-0000-000000000891';
set role authenticated; select tt.as(:'u_o');
select employee_link_profile(:'e7'::uuid,'00000000-0000-0000-0000-000000000891') is not null as l7 \gset
select _w1c_employee_status_set(:'e7'::uuid,'terminated',tt.today(),'test dismissed') #>> '{exit,action}' as a11 \gset
reset role;
select tt.chk('T11 terminated is not in the list now: nothing happens', :'a11'='none' and tt.pstat('00000000-0000-0000-0000-000000000891')='active');
set role authenticated; select tt.as(:'u_o');
select employee_status_set(:'e7'::uuid,'active',tt.today(),'back') is not null as bk \gset
select _w1c_employee_status_set(:'e7'::uuid,'on_leave',tt.today(),'test long leave') #>> '{exit,action}' as a11b \gset
reset role;
select tt.chk('T11 on_leave is in the list now: login disabled', :'a11b'='revoked' and tt.pstat('00000000-0000-0000-0000-000000000891')='disabled');
set role authenticated; select tt.as(:'u_o');
select _w1c_employee_status_set(:'e7'::uuid,'active',tt.today(),'test back from leave') #>> '{exit,action}' as a11c \gset
reset role;
select tt.chk('T11 coming back from leave re-enables it', :'a11c'='reenabled' and tt.pstat('00000000-0000-0000-0000-000000000891')='active');

\echo == T12 logs are append-only, nothing deleted
select tt.err('T12 exit log cannot be edited', $$update w1c_exit_log set reason='x'$$, 'w1c_append_only');
select tt.err('T12 exit log cannot be deleted', $$delete from w1c_exit_log$$, 'w1c_append_only');
select tt.err('T12 keep records are never deleted', $$delete from w1c_exit_keep$$, 'nothing is deleted');
select tt.chk('T12 no demo names, no journal effect: the books are untouched and balanced', tt.unbalanced()=0 and not exists (select 1 from journal_entries where source_type like 'w1c%'));

\echo == T13 paste twice: the file runs again, settings and logs survive
select count(*) as logs_before from w1c_exit_log \gset
select rule_txt('exit_revoke_mode') as mode_before \gset
\i supabase/phase90.sql
select tt.chk('T13 second paste: no error, settings and rows unchanged, still only one trigger and one grant row',
  (select count(*) from w1c_exit_log)=:'logs_before'::int and rule_txt('exit_revoke_mode')=:'mode_before' and (select count(*) from pg_trigger where tgname='w1c_rules_guard90')=1
  and (select count(*) from grant_defs where grant_code='exit_keep_access')=1);

\echo == T14 the hook for employee_status_set, proved on a SCRATCH COPY (this database keeps the original function)
select current_database() as w1c_main \gset
select count(*) filter (where not ok) as f0 from tt.res \gset
\c postgres
drop database if exists w1c_scratch90;
create database w1c_scratch90 template :"w1c_main";
\c w1c_scratch90
select tt.chk('T14 scratch copy starts with the original function (no marker)', position('bos90' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))=0);
select _w1c_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', e.id, ''status'', p_status);', E'  perform public._w1c_exit_apply(e.id, e.status, p_status, p_date, v_reason); /* bos90 */\n  return jsonb_build_object(''id'', e.id, ''status'', p_status);'], 'bos90') as patched1 \gset
select _w1c_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', e.id, ''status'', p_status);', E'  perform public._w1c_exit_apply(e.id, e.status, p_status, p_date, v_reason); /* bos90 */\n  return jsonb_build_object(''id'', e.id, ''status'', p_status);'], 'bos90') as patched2 \gset
select tt.chk('T14 patch applied once, the second call is a no-op (marker)', :'patched1'='t' and :'patched2'='f' and position('bos90' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))>0);
select tt.err('T14 a missing patch site stops with a clear message and changes nothing', $$select _w1c_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array['no such text here','x'], 'bos91')$$, 'patch site not found');
select tt.err('T14 a patch without a marker in its new text is refused', $$select _w1c_patch('public._w1c_present90()'::regprocedure, array['select true','select true /* changed */'], 'bos91')$$, 'carries no marker');
-- mode auto, hook only (the plain function, no wrapper)
update rules set value='"auto"' where key='exit_revoke_mode';
update rules set value='"resigned,terminated,retired"' where key='exit_revoke_statuses';
update rules set value=null where key='exit_alert_hours';
update profiles set status='active' where id = :'u_c1';
insert into user_grants (user_id, grant_code, location_id, note) values (:'u_c1','sale_return',1,'test hook') on conflict do nothing;
select count(*) as rv0 from w1c_exit_log where employee_id=:'e1'::uuid and action='revoked' \gset
set role authenticated; select tt.as(:'u_o');
select employee_status_set(:'e1'::uuid,'terminated',tt.today(),'hook test') ->> 'status' as ok_h \gset
reset role;
select tt.chk('T14 hooked ORIGINAL employee_status_set disables the login by itself, one log row, grants ended', :'ok_h'='terminated' and tt.pstat(:'u_c1')='disabled' and tt.live_grants(:'u_c1')=0
  and (select count(*) from w1c_exit_log where employee_id=:'e1'::uuid and action='revoked')=:'rv0'::int+1);
set role authenticated; select tt.as(:'u_o');
select employee_status_set(:'e1'::uuid,'active',tt.today(),'hook back') is not null as ok_b \gset
reset role;
select tt.chk('T14 re-hire through the hooked function re-enables the login only', tt.pstat(:'u_c1')='active' and tt.live_grants(:'u_c1')=0);
select count(*) as rv1 from w1c_exit_log where employee_id=:'e1'::uuid and action='revoked' \gset
set role authenticated; select tt.as(:'u_o');
select _w1c_employee_status_set(:'e1'::uuid,'resigned',tt.today(),'wrapper on the hooked function') #>> '{exit,skipped}' as ok_w \gset
reset role;
select tt.chk('T14 wrapper on top of the hook: the exit step runs once, not twice', :'ok_w'='done' and (select count(*) from w1c_exit_log where employee_id=:'e1'::uuid and action='revoked')=:'rv1'::int+1 and tt.pstat(:'u_c1')='disabled');
-- setting off + hook = old behaviour
update rules set value='"off"' where key='exit_revoke_mode';
select count(*) as lg0 from w1c_exit_log \gset
set role authenticated; select tt.as(:'u_o');
select employee_status_set(:'e7'::uuid,'resigned',tt.today(),'hook with mode off') ->> 'status' as ok_off \gset
reset role;
select tt.chk('T14 mode off + hook = old behaviour: status changed, login untouched, nothing logged', :'ok_off'='resigned' and tt.pstat('00000000-0000-0000-0000-000000000891')='active' and (select count(*) from w1c_exit_log)=:'lg0'::int);
select count(*) filter (where not ok) as f1, count(*) as tot from tt.res \gset
\c postgres
drop database if exists w1c_scratch90;
\c :w1c_main
select tt.chk('T14 hook proof on the scratch copy: no failed check (scratch failures: ' || (:'f1'::int - :'f0'::int) || ')', (:'f1'::int - :'f0'::int) = 0);
select tt.chk('T14 the tested database still has the ORIGINAL employee_status_set (the hook was not committed)', position('bos90' in pg_get_functiondef('public.employee_status_set(uuid,text,date,text)'::regprocedure))=0);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
