-- FRESH DB ONLY. Phase 54 tests (P2c: attendance two paths counted once, self punch + locks, evidence, mark others, equation recompute).
--   ORDER="phase8 ... phase28 phase40 ... phase51 phase54" bash tests/sql/build_fresh_db.sh a54db
--   psql -h /tmp -p 5544 -U postgres -d a54db -qAt -f supabase/phase54_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set t '00000000-0000-0000-0000-000000000005'
\set p '00000000-0000-0000-0000-000000000006'
\set a '00000000-0000-0000-0000-000000000007'
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
create or replace function tt.is_shadow(p_type text, p_id text) returns boolean language sql security definer set search_path = public as $$ select public.is_shadow(p_type, p_id) $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager One"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
  (:'t','mgr5@s.app','{"full_name":"Manager Two"}'), (:'p','sales6@s.app','{"full_name":"Sales Person"}'), (:'a','acct7@s.app','{"full_name":"Accountant"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper'),(:'t','showroom_manager'),(:'p','salesperson'),(:'a','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'t',2),(:'p',1),(:'a',1) on conflict do nothing;

select to_char((date_trunc('month', tt.today()) - interval '1 month')::date, 'YYYY-MM-DD') as m0 \gset
select to_char(:'m0'::date + 3, 'YYYY-MM-DD') as d1, to_char(:'m0'::date + 4, 'YYYY-MM-DD') as d2, to_char(:'m0'::date + 5, 'YYYY-MM-DD') as d3 \gset
select to_char(date_trunc('month', tt.today())::date, 'YYYY-MM-DD') as mc, extract(month from :'m0'::date)::int as mm0, extract(year from :'m0'::date)::int as yy0 \gset
insert into employees (id, full_name_bn, full_name_en, employee_no, primary_location_id, status, joining_date, profile_id) values
 ('e0000000-0000-0000-0000-000000000001', 'করিম', 'Karim', 'E01', 1, 'active', '2025-01-01', null),
 ('e0000000-0000-0000-0000-000000000002', 'রহিম', 'Rahim', 'E02', 2, 'active', '2025-01-01', null),
 ('e0000000-0000-0000-0000-000000000005', 'সালমা', 'Salma', 'E05', 3, 'active', '2025-01-01', :'p'),
 ('e0000000-0000-0000-0000-000000000007', 'আনিস', 'Anis', 'E07', 3, 'active', '2025-01-01', :'a'),
 ('e0000000-0000-0000-0000-000000000010', 'স্টোর', 'Storeman', 'E10', 3, 'active', '2025-01-01', :'k'),
 ('e0000000-0000-0000-0000-000000000011', 'ম্যানেজার', 'Manager Emp', 'E11', 1, 'active', '2025-01-01', :'s');
\set e1 'e0000000-0000-0000-0000-000000000001'
\set e2 'e0000000-0000-0000-0000-000000000002'
\set e5 'e0000000-0000-0000-0000-000000000005'
\set e7 'e0000000-0000-0000-0000-000000000007'
\set e10 'e0000000-0000-0000-0000-000000000010'
\set e11 'e0000000-0000-0000-0000-000000000011'
set role authenticated;

\echo == T0 shape
reset role;
select tt.chk('T0 domain attendance exists, default primary a', (select default_primary from path_domains where domain='attendance')='a');
select tt.chk('T0 new grant exists and no role has it by default', exists (select 1 from grant_defs where grant_code='attendance_mark_others') and not exists (select 1 from rule_grants where grant_code='attendance_mark_others'));
select tt.chk('T0 the three new switches default OFF / numbers', (select default_value from rules where key='att_geo_check_on')='false' and (select default_value from rules where key='entry_equation_flag_on')='false');
select tt.chk('T0 helpers closed to browsers; screens callable by signed-in users only', not has_function_privilege('authenticated','public._eq_check54(public.entries)','execute') and not has_function_privilege('authenticated','public._att_form_link54(uuid)','execute')
  and has_function_privilege('authenticated','public.attendance_mark_others(uuid,date,text,text,text,int,text,text,text,uuid)','execute') and not has_function_privilege('anon','public.attendance_mark_others(uuid,date,text,text,text,int,text,text,text,uuid)','execute')
  and not has_function_privilege('anon','public.attendance_self_punch(text,numeric,numeric,numeric,text,text)','execute'));
select tt.chk('T0 attendance_app_punch is the bos54 wrapper', position('bos54' in pg_get_functiondef('public.attendance_app_punch(text)'::regprocedure))>0);

set role authenticated;
\echo == T1 self punch + locks
select tt.as(:'p'); select tt.err('T1 master switch OFF by default', $$select attendance_self_punch('in')$$, 'app_punch_off');
select tt.as(:'o'); select set_rule('app_punch_on', 'true'::jsonb) is null as r1 \gset
select tt.as(:'s'); select tt.err('T1 only the owner sets a lock', format($$select att_self_lock_set('person','%s',true,'x')$$, :'e5'), 'not allowed');
select tt.as(:'o');
select tt.err('T1 lock needs a real person', $$select att_self_lock_set('person','e0000000-0000-0000-0000-0000000000ff',true,'x')$$, 'not_found');
select tt.err('T1 lock needs a real role', $$select att_self_lock_set('role','nosuchrole',true,'x')$$, 'not_found');
select att_self_lock_set('person', :'e5', true, 'on probation') ->> 'locked' as l1 \gset
select tt.as(:'p'); select tt.chk('T1 status shows the lock', (att_my_status() ->> 'state')='self_punch_locked' and (att_my_status() ->> 'can_punch')='false');
select tt.err('T1 person lock refuses the screen punch', $$select attendance_self_punch('in')$$, 'self_punch_locked');
select tt.err('T1 person lock refuses the old entry point too', $$select attendance_app_punch('in')$$, 'self_punch_locked');
select tt.chk('T1 nothing was written by the refused punches', (select count(*) from attendance_punches where employee_id=:'e5')=0);
select tt.as(:'o'); select att_self_lock_set('person', :'e5', false) ->> 'locked' as l2 \gset
select tt.as(:'p'); select attendance_app_punch('in') ->> 'direction' as apd \gset
select tt.chk('T1 unlocked: the old entry point punches (source app, evidence none, geo unchecked)', :'apd'='in' and (select count(*) from attendance_punches where employee_id=:'e5' and source='app' and evidence_state='none' and geo_flag='unchecked')=1);
select tt.err('T1 twice within a minute refused (same as phase42)', $$select attendance_app_punch('out')$$, 'too_soon');
select tt.as(:'o'); select att_self_lock_set('role', 'salesperson', true, 'all sales') ->> 'locked' as l3 \gset
select tt.as(:'a'); select tt.err('T1 role lock refuses everybody with that role', $$select attendance_self_punch('in')$$, 'self_punch_locked');
select tt.as(:'k'); select tt.chk('T1 other roles are not touched by the role lock', (att_my_status() ->> 'can_punch')='true');
select tt.as(:'o'); select att_self_lock_set('role', 'salesperson', false) ->> 'locked' as l4 \gset

\echo == T2 evidence (flag + reference only)
select tt.as(:'a');
select tt.chk('T2 a person registers his own browser passkey', (att_evidence_register(:'e7'::uuid, 'webauthn', 'cred-AAA', 'my phone') ->> 'id') is not null);
select tt.chk('T2 repeat is idempotent', (att_evidence_register(:'e7'::uuid, 'webauthn', 'cred-AAA', 'my phone') ->> 'repeat')='true' and (select count(*) from att_evidence_reg where employee_id=:'e7')=1);
select tt.err('T2 a person cannot register a device fingerprint flag for himself', format($$select att_evidence_register('%s','finger_device','dev-17','x')$$, :'e7'), 'not allowed');
select tt.err('T2 a person cannot register for somebody else', format($$select att_evidence_register('%s','webauthn','x1','x')$$, :'e5'), 'not allowed');
select tt.err('T2 bad kind refused', format($$select att_evidence_register('%s','retina','x1','x')$$, :'e7'), 'bad_kind');
select tt.as(:'s'); select tt.err('T2 manager without attendance_manage at that place cannot (other place)', format($$select att_evidence_register('%s','finger_device','dev-9','x')$$, :'e2'), 'not allowed');
select tt.chk('T2 manager registers the device fingerprint flag for his place', (att_evidence_register(:'e1'::uuid, 'finger_device', 'dev-17', 'ZK front door') ->> 'id') is not null);
select tt.chk('T2 the person cannot read another person''s registrations', (select count(*) from att_evidence_reg where employee_id=:'e1')=1);
select tt.as(:'a'); select tt.chk('T2 ... and the other person sees none of them', (select count(*) from att_evidence_reg where employee_id=:'e1')=0 and (select count(*) from att_evidence_reg where employee_id=:'e7')=1);
select att_evidence_register(:'e7'::uuid, 'webauthn', 'cred-OLD', 'old') ->> 'id' as evold \gset
select tt.err('T2 void needs a reason', format($$select att_evidence_void(%s,'')$$, :'evold'), 'reason_required');
select att_evidence_void(:'evold'::bigint, 'lost phone') ->> 'active' as vd \gset
select tt.chk('T2 void turns the flag off (row kept)', :'vd'='false' and (select count(*) from att_evidence_reg where id=:'evold' and not active)=1);

\echo == T3 punch with evidence and soft GPS
select tt.as(:'o'); select set_rule('att_geo_check_on', 'true'::jsonb) is null as g1 \gset
select att_site_geo_set(3, 23.8103, 90.4125) ->> 'location_id' as sg \gset
select tt.as(:'a');
select tt.err('T3 impossible coordinates refused', $$select attendance_self_punch('in', 100, 90, 10, null, null)$$, 'bad_geo');
select tt.err('T3 unknown evidence kind refused', $$select attendance_self_punch('in', 23.81, 90.41, 10, 'iris', 'x')$$, 'bad_evidence');
select attendance_self_punch('in', 23.8104, 90.4126, 12, 'webauthn', 'cred-AAA') as pj \gset
select tt.chk('T3 near the place + registered passkey = geo ok, evidence registered', (select geo_flag from attendance_punches where employee_id=:'e7' and source='app')='ok' and (select evidence_state from attendance_punches where employee_id=:'e7' and source='app')='registered');
select tt.as(:'k'); select attendance_self_punch('in', 23.9500, 90.9000, 800, 'webauthn', 'cred-UNKNOWN') ->> 'geo_flag' as gk \gset
select tt.chk('T3 far away: the punch is RECORDED and flagged (soft), unknown passkey = unregistered', :'gk'='outside' and (select evidence_state from attendance_punches where employee_id=:'e10')='unregistered');
select tt.chk('T3 the answer says it is evidence only', (select att_my_status() ->> 'state')='ok');
select tt.as(:'o'); select att_site_geo_set(3, 23.8103, 90.4125) is not null as g2 \gset
select set_rule('att_geo_check_on', null) is null as g3 \gset
select tt.as(:'s'); select tt.err('T3 only the owner sets coordinates', $$select att_site_geo_set(1, 23.8, 90.4)$$, 'not allowed');

\echo == T4 path switch on the app side
select tt.as(:'o'); select path_switch_set('attendance',0,false,true,'a') is not null as sw1 \gset
select tt.as(:'p'); select tt.err('T4 path A locked: self punch refused', $$select attendance_self_punch('out')$$, 'path_locked');
select tt.as(:'o'); select path_switch_set('attendance',0,true,true,'a') is not null as sw2 \gset

\echo == T5 mark others (new grant)
select tt.as(:'s');
select tt.err('T5 attendance_manage alone is not the new grant', format($$select attendance_mark_others('%s','%s','present','09:00','21:00',60,'manual','late fix')$$, :'e1', :'d1'), 'not allowed');
select tt.err('T5 board needs the grant too', $$select att_others_board(1)$$, 'not allowed');
select tt.as(:'o'); reset role; insert into user_grants (user_id, grant_code, location_id, granted_by) values (:'s'::uuid, 'attendance_mark_others', 1, :'o'::uuid); set role authenticated; select tt.as(:'s');
select attendance_mark_others(:'e1'::uuid, :'d1'::date, 'present', '09:00', '21:00', 60, 'finger', 'device offline, manager saw him', null, '77777777-0000-0000-0000-000000000001'::uuid) as mk \gset
select tt.chk('T5 with the grant: day marked, rest 60 and closing 21:00 stored, tag finger, pending approval', (select rest_minutes from attendance_days where employee_id=:'e1' and day=:'d1')=60 and (select mark_source from attendance_days where employee_id=:'e1' and day=:'d1')='finger'
  and (select source from attendance_days where employee_id=:'e1' and day=:'d1')='manual' and (select worked_minutes from attendance_days where employee_id=:'e1' and day=:'d1')=660 and (select approved_by from attendance_days where employee_id=:'e1' and day=:'d1') is null
  and (select to_char(last_out at time zone 'Asia/Dhaka','HH24:MI') from attendance_days where employee_id=:'e1' and day=:'d1')='21:00');
select tt.chk('T5 same client key = same answer, no second log row', (attendance_mark_others(:'e1'::uuid, :'d1'::date, 'present', '09:00', '21:00', 60, 'finger', 'device offline, manager saw him', null, '77777777-0000-0000-0000-000000000001'::uuid) ->> 'duplicate')='true' and (select count(*) from att_mark_log54)=1);
select tt.chk('T5 log row carries marker, source tag, reason', (select source_tag||'|'||reason from att_mark_log54 where client_id='77777777-0000-0000-0000-000000000001')='finger|device offline, manager saw him' and (select marked_by from att_mark_log54 limit 1)=:'s'::uuid);
select attendance_mark_others(:'e1'::uuid, :'d1'::date, 'late', '09:40', '20:00', 45, 'face', 'corrected time') is not null as mk2 \gset
select tt.chk('T5 a re-mark keeps the old row in the log (prev) and updates the day', (select count(*) from att_mark_log54 where prev is not null)=1 and (select rest_minutes from attendance_days where employee_id=:'e1' and day=:'d1')=45 and (select status from attendance_days where employee_id=:'e1' and day=:'d1')='late');
select attendance_mark_others(:'e1'::uuid, :'d2'::date, 'present', '09:00', '20:00', null, 'manual', 'regular day') is not null as mk3 \gset
select attendance_mark_others(:'e1'::uuid, :'d3'::date, 'absent', '09:00', '20:00', 30, 'manual', 'did not come') is not null as mk4 \gset
select tt.chk('T5 absent keeps no times / rest', (select first_in is null and last_out is null and rest_minutes is null from attendance_days where employee_id=:'e1' and day=:'d3'));
select tt.err('T5 bad source', format($$select attendance_mark_others('%s','%s','present',null,null,null,'retina','reason here')$$, :'e1', :'d1'), 'bad_source');
select tt.err('T5 reason is mandatory', format($$select attendance_mark_others('%s','%s','present',null,null,null,'manual','x')$$, :'e1', :'d1'), 'reason_required');
select tt.err('T5 rest above 12h refused', format($$select attendance_mark_others('%s','%s','present','09:00','20:00',721,'manual','reason here')$$, :'e1', :'d1'), 'bad_rest');
select tt.err('T5 future day refused', format($$select attendance_mark_others('%s','%s','present',null,null,null,'manual','reason here')$$, :'e1', tt.today()+1), 'bad_date');
select tt.err('T5 older than 62 days refused', format($$select attendance_mark_others('%s','%s','present',null,null,null,'manual','reason here')$$, :'e1', tt.today()-70), 'bad_date');
select tt.err('T5 garbled time refused', format($$select attendance_mark_others('%s','%s','present','xx','20:00',null,'manual','reason here')$$, :'e1', :'d1'), 'bad_time');
select tt.err('T5 nobody marks himself', format($$select attendance_mark_others('%s','%s','present',null,null,null,'manual','reason here')$$, :'e11', :'d1'), 'cannot_mark_self');
select tt.err('T5 grant is scoped to his place', format($$select attendance_mark_others('%s','%s','present',null,null,null,'manual','reason here')$$, :'e2', :'d1'), 'not allowed');
select tt.as(:'k'); select tt.err('T5 a storekeeper cannot', format($$select attendance_mark_others('%s','%s','present',null,null,null,'manual','reason here')$$, :'e1', :'d1'), 'not allowed');
select tt.chk('T5 ... and cannot read the log', (select count(*) from att_mark_log54)=0);
select tt.as(:'s');
select tt.chk('T5 board shows source tag, rest and "is_me" (his own row is visible but not markable)', (select count(*) from jsonb_array_elements(att_others_board(1, :'d1'::date) -> 'rows') r where r ->> 'mark_source'='face' and (r ->> 'rest_minutes')::int=45)=1
  and (select count(*) from jsonb_array_elements(att_others_board(1, :'d1'::date) -> 'rows') r where (r ->> 'is_me')::boolean)=1);
select tt.as(:'o');
select tt.chk('T5 the owner can approve a pending day (existing function) and it stays tagged', (attendance_approve(:'e1'::uuid, :'d2'::date, true) ->> 'approved')='true' and (select mark_source from attendance_days where employee_id=:'e1' and day=:'d2')='manual');
select tt.as(:'s');
select attendance_mark(:'e1'::uuid, :'d1'::date, 'present', '09:00', '19:00', null, 'plain manager mark') is not null as pm \gset
select tt.chk('T5 the older attendance_mark resets rest/tag (no stale data)', (select rest_minutes is null and mark_source='manual' from attendance_days where employee_id=:'e1' and day=:'d1'));
select tt.as(:'o'); reset role;
select tt.err('T5 the log cannot be changed', $$update att_mark_log54 set reason='x'$$, 'append_only');
select tt.err('T5 the log cannot be deleted', $$delete from att_mark_log54$$, 'append_only');
set role authenticated; select tt.as(:'o');
select path_switch_set('attendance',0,false,true,'a') is not null as sw3 \gset
select tt.as(:'s'); select tt.err('T5 path A locked: marking others is refused', format($$select attendance_mark_others('%s','%s','present',null,null,null,'manual','reason here')$$, :'e1', :'d2'), 'path_locked');
select tt.as(:'o'); select path_switch_set('attendance',0,true,true,'a') is not null as sw4 \gset

\echo == T6 payroll lock is respected
reset role;
insert into payroll_runs (month, location_id, status) values (:'m0'::date, 1, 'approved') returning id as pr \gset
insert into payroll_lines (run_id, month, employee_id, location_id) values (:'pr', :'m0'::date, :'e1'::uuid, 1);
set role authenticated; select tt.as(:'s');
select tt.err('T6 a month in an approved payroll cannot be re-marked', format($$select attendance_mark_others('%s','%s','absent',null,null,null,'manual','reason here')$$, :'e1', :'d2'), 'month_locked');

\echo == T7 two paths counted once
select tt.as(:'o');
select count(*) as cnt_before from entries where form_code='02-1' \gset
select save_entry(null,'02-1',1,:'d3'::date, format('{"month":"%s","year":"%s","staff":[{"name":"Karim","present":2,"late":1,"absent":1}]}', :'mm0', :'yy0')::jsonb, '[]') ->> 'id' as f1 \gset
select submit_entry(:'f1'::uuid) is not null as sub_f1 \gset
select tt.chk('T7 submitted 02-1 for a month that path A holds is a locked shadow (primary a)', tt.is_shadow('entries', :'f1') and (select count(*) from shadow_links where domain='attendance' and state='confirmed')=1);
reset role;
select tt.err('T7 the shadow cannot be changed or re-opened', format($$update entries set status='draft' where id='%s'$$, :'f1'), 'shadow_locked');
set role authenticated; select tt.as(:'o');
select attendance_count_once(1, :'m0'::date) as co \gset
select tt.chk('T7 report: counted = attendance record, form listed as shadow, Karim matches (2 present incl. 1 late, 1 late, 1 absent)',
  (:'co'::jsonb ->> 'counted')='attendance_record' and (:'co'::jsonb -> 'forms' -> 0 ->> 'is_shadow')='true' and (:'co'::jsonb ->> 'mismatches')='0'
  and ((:'co'::jsonb -> 'rows' -> 0 -> 'device' ->> 'present')::numeric)=2 and ((:'co'::jsonb -> 'rows' -> 0 -> 'form' ->> 'present')::numeric)=2);
select save_entry(null,'02-1',1,:'d3'::date, format('{"month":"%s","year":"%s","staff":[{"name":"করিম","present":5,"late":0,"absent":0}]}', :'mm0', :'yy0')::jsonb, '[]') ->> 'id' as f2 \gset
select submit_entry(:'f2'::uuid) is not null as sub_f2 \gset
select tt.chk('T7 a second register for the same month is not shadowed twice (one link per place+month); it is listed', not tt.is_shadow('entries', :'f2') and (select count(*) from shadow_links where domain='attendance' and state<>'void')=1);
select attendance_count_once(1, :'m0'::date) as co2 \gset
select tt.chk('T7 report flags a difference between path A and the second register (5 vs 2)', (:'co2'::jsonb ->> 'mismatches')::int>=1);
select tt.as(:'k'); select tt.err('T7 report needs attendance rights at the place', $$select attendance_count_once(1, current_date)$$, 'not allowed');
select tt.as(:'o');
-- month with nothing on path A: stays the record; later link-run picks it up
select save_entry(null,'02-1',1,tt.today(),format('{"month":"%s","year":"%s","staff":[{"name":"Karim","present":1,"absent":0}]}', extract(month from tt.today())::int, extract(year from tt.today())::int)::jsonb,'[]') ->> 'id' as f3 \gset
select submit_entry(:'f3'::uuid) is not null as sub_f3 \gset
select tt.chk('T7 path A has no record for the current month yet: the form is NOT a shadow (it is the only record)', not tt.is_shadow('entries', :'f3'));
select tt.as(:'s'); select attendance_mark_others(:'e1'::uuid, tt.today(), 'present', '09:00', '19:00', 30, 'manual', 'today entry') is not null as mkt \gset
select tt.as(:'k'); select tt.err('T7 link-run needs attendance_manage', format($$select attendance_form_link_run(1,'%s')$$, :'mc'), 'not allowed');
select tt.as(:'o'); select attendance_form_link_run(1, :'mc'::date) -> 'result' ->> 'linked' as lr \gset
select attendance_form_link_run(1, :'mc'::date) -> 'result' ->> 'already' as lr2 \gset
select tt.chk('T7 link-run links it now; running again changes nothing', :'lr'='1' and tt.is_shadow('entries', :'f3') and :'lr2'='1');
-- primary b
select path_switch_set('attendance',0,true,true,'b') is not null as sw5 \gset
select save_entry(null,'02-1',3,:'d3'::date, format('{"month":"%s","year":"%s","staff":[{"name":"Salma","present":3}]}', :'mm0', :'yy0')::jsonb, '[]') ->> 'id' as f4 \gset
select submit_entry(:'f4'::uuid) is not null as sub_f4 \gset
select tt.chk('T7 primary=b: the form stays the record (no shadow) and the report says so', not tt.is_shadow('entries', :'f4') and (attendance_count_once(3, :'m0'::date) ->> 'counted')='form_02_1');
-- path B locked
select path_switch_set('attendance',0,true,false,'a') is not null as sw6 \gset
select tt.err('T7 form path locked: a new 02-1 is refused', format($$select save_entry(null,'02-1',1,'%s','{"staff":[]}','[]')$$, :'d3'), 'path_locked');
select tt.chk('T7 other forms are not affected by that lock', save_entry(null,'10-2',1,:'d3'::date,'{"lines":[]}','[]') is not null);
select path_switch_set('attendance',0,true,true,'a') is not null as sw7 \gset

\echo == T8 equation recompute
reset role;
insert into location_settings (location_id, key, value) values (1,'imprest','5000'),(1,'expense_max','1000') on conflict (location_id,key) do update set value=excluded.value;
set role authenticated; select tt.as(:'o');
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"x","amount":"300","receipt":"yes"},{"head":"y","amount":"200","receipt":"no"}],"cash_now":"4400","receipts_total":"400"}',
  '[{"code":"imprest_mismatch","level":"red","amount":-200},{"code":"no_receipt","level":"yellow","amount":200}]') ->> 'id' as q1 \gset
select entry_equation_check(:'q1'::uuid) as c1 \gset
select tt.chk('T8 10-2: honest phone flags = ok; total 500, cash+receipts 4800, diff -200', (:'c1'::jsonb ->> 'ok')='true' and (:'c1'::jsonb -> 'recomputed' ->> 'total')::numeric=500 and (:'c1'::jsonb -> 'recomputed' ->> 'imprest_diff')::numeric=-200);
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"x","amount":"300","receipt":"yes"},{"head":"y","amount":"200","receipt":"no"}],"cash_now":"4400","receipts_total":"400"}','[]') ->> 'id' as q2 \gset
select entry_equation_check(:'q2'::uuid) as c2 \gset
select tt.chk('T8 10-2: phone saved NO flags -> two flag_missing differences', (:'c2'::jsonb ->> 'ok')='false' and (select count(*) from jsonb_array_elements(:'c2'::jsonb -> 'mismatches') m where m ->> 'kind'='flag_missing')=2);
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"x","amount":"300","receipt":"yes"}],"cash_now":"4400","receipts_total":"400"}','[{"code":"imprest_mismatch","level":"red","amount":-100}]') ->> 'id' as q3 \gset
select tt.chk('T8 10-2: wrong amount stored -> amount_differs (-100 vs -200)', (select count(*) from jsonb_array_elements(entry_equation_check(:'q3'::uuid) -> 'mismatches') m where m ->> 'kind'='amount_differs' and (m ->> 'recomputed')::numeric=-200 and (m ->> 'stored')::numeric=-100)=1);
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"x","amount":"300","receipt":"yes"}],"cash_now":"4600","receipts_total":"400"}','[{"code":"imprest_mismatch","level":"red","amount":-50}]') ->> 'id' as q4 \gset
select tt.chk('T8 10-2: red flag stored but the sum matches -> flag_extra', (select count(*) from jsonb_array_elements(entry_equation_check(:'q4'::uuid) -> 'mismatches') m where m ->> 'kind'='flag_extra')=1);
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"x","amount":"৩০০","receipt":"yes"}],"cash_now":"4600","receipts_total":"৪০০"}','[]') ->> 'id' as q5 \gset
select tt.chk('T8 Bangla digits are read like the phone does (300 + 4600 + 400)', (entry_equation_check(:'q5'::uuid) -> 'recomputed' ->> 'total')::numeric=300 and (entry_equation_check(:'q5'::uuid) ->> 'ok')='true');
select save_entry(null,'02-2',1,tt.today(),'{"pay":[{"name":"A","due":"1000","overtime":"0","other":"0","adv_ded":"1500","other_ded":"0","remark":"x"},{"name":"B","due":"2000","other":"100","adv_ded":"0","remark":""}],"receipts":[{"name":"B","net":"2100","signed":false}]}','[]') ->> 'id' as w1 \gset
select entry_equation_check(:'w1'::uuid) as cw \gset
select tt.chk('T8 02-2: net negative (1), other without reason (1), unsigned payment; t_net = 1600; phone saved none -> 3 missing', (:'cw'::jsonb -> 'recomputed' ->> 't_net')::numeric=1600 and (:'cw'::jsonb -> 'expected_flags' ->> 'net_negative')='1'
  and (:'cw'::jsonb -> 'expected_flags' ->> 'other_no_reason')='1' and (select count(*) from jsonb_array_elements(:'cw'::jsonb -> 'mismatches'))=3);
select tt.chk('T8 02-2: receipts (2100) vs sheet net (1600) is reported as information only', (select count(*) from jsonb_array_elements(:'cw'::jsonb -> 'observations') x where x ->> 'code'='receipts_vs_net')=1);
select save_entry(null,'14-1',1,tt.today(),'{}','[]') ->> 'id' as x14 \gset
select tt.chk('T8 14-1 is not re-worked (honest: supported=false)', (entry_equation_check(:'x14'::uuid) ->> 'supported')='false');
select tt.as(:'t'); select tt.err('T8 another place cannot check my entry', format($$select entry_equation_check('%s')$$, :'q1'), 'not allowed');
select tt.as(:'o');
select tt.chk('T8 the check wrote nothing (read only)', (select count(*) from exceptions where flag_code='equation_mismatch')=0);

\echo == T9 optional red exception at submit
select submit_entry(:'q2'::uuid) is not null as s0 \gset
select tt.chk('T9 switch OFF (default): a differing sheet is submitted with no extra exception', (select count(*) from exceptions where entry_id=:'q2'::uuid and flag_code='equation_mismatch')=0);
select set_rule('entry_equation_flag_on', 'true'::jsonb) is null as r9 \gset
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"x","amount":"300","receipt":"yes"},{"head":"y","amount":"200","receipt":"no"}],"cash_now":"4400","receipts_total":"400"}','[]') ->> 'id' as q6 \gset
select submit_entry(:'q6'::uuid) is not null as s1 \gset
select tt.chk('T9 switch ON: one red exception equation_mismatch is raised for the differing sheet; the submit still went through',
  (select count(*) from exceptions where entry_id=:'q6'::uuid and flag_code='equation_mismatch' and level='red' and status='open')=1 and (select status from entries where id=:'q6'::uuid)='submitted');
select submit_entry(:'q1'::uuid) is not null as s2 \gset
select tt.chk('T9 switch ON: an honest sheet raises nothing', (select count(*) from exceptions where entry_id=:'q1'::uuid and flag_code='equation_mismatch')=0);
select set_rule('entry_equation_flag_on', null) is null as r10 \gset

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
