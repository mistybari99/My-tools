-- FRESH DB ONLY. Phase 70 tests (restore drill record).
--   ORDER="phase8 ... phase46 ... phase62 phase70" bash tests/sql/build_fresh_db.sh 70db   (all phases through phase62, then phase70)
--   psql -h /tmp -p 5544 -U postgres -d 70db -qAt -f supabase/phase70_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1) on conflict do nothing;

\echo == T0 shape
select tt.chk('T0 table has RLS on and no direct write for app roles', (select relrowsecurity from pg_class where oid='public.restore_drills'::regclass)
  and not has_table_privilege('authenticated','public.restore_drills','insert') and not has_table_privilege('anon','public.restore_drills','select'));
select tt.chk('T0 functions are closed to anon, open to authenticated', not has_function_privilege('anon','public.restore_drill_status()','execute')
  and has_function_privilege('authenticated','public.restore_drill_record(text,text,boolean,boolean,text,timestamptz)','execute'));
select tt.chk('T0 rule restore_drill_warn_days defaults to 90', public.rule_num('restore_drill_warn_days')=90);
select tt.chk('T0 assistant_usage is now in the backup list, attendance_devices is not', 'assistant_usage' = any(public._backup_tables()) and not 'attendance_devices' = any(public._backup_tables()));
select tt.chk('T0 secret-bearing tables stay out', not exists (select 1 from unnest(public._backup_tables()) t where t like 'ops\_%' or t like '%\_secret%' or t in ('login_failures','backup_runs')));

\echo == T1 owner only
select tt.as(:'s');
select tt.err('T1 manager cannot record', $$select restore_drill_record('b1','pass',true,true,null)$$, 'not allowed');
select tt.err('T1 manager cannot list', $$select restore_drill_list()$$, 'not allowed');
select tt.err('T1 manager cannot read status', $$select restore_drill_status()$$, 'not allowed');
select tt.as(:'k');
select tt.err('T1 storekeeper cannot record', $$select restore_drill_record('b1','pass',true,true,null)$$, 'not allowed');
select tt.as('00000000-0000-0000-0000-0000000000ff');
select tt.err('T1 unknown user cannot read status', $$select restore_drill_status()$$, 'not allowed');

\echo == T2 status before any drill
select tt.as(:'o');
select tt.chk('T2 never + warn', (restore_drill_status() ->> 'never')::boolean and (restore_drill_status() ->> 'warn')::boolean and restore_drill_status() -> 'age_days' = 'null'::jsonb);
select tt.chk('T2 list is empty', jsonb_array_length(restore_drill_list())=0);

\echo == T3 record
select tt.err('T3 bad result', $$select restore_drill_record('b1','maybe',true,true,null)$$, 'bad_input');
select tt.err('T3 empty name', $$select restore_drill_record('  ','pass',true,true,null)$$, 'bad_input');
select tt.err('T3 future date', $$select restore_drill_record('b1','pass',true,true,null, now()+interval '2 days')$$, 'bad_input');
select tt.err('T3 a pass needs tables_ok and rows_ok', $$select restore_drill_record('b1','pass',true,false,null)$$, 'pass_needs');
select restore_drill_record('backup-old','pass',true,true,'first', now()-interval '100 days') as d1 \gset
select tt.chk('T3 old pass recorded; status warns (100 > 90 days)', (restore_drill_status() ->> 'warn')::boolean and (restore_drill_status() ->> 'age_days')::numeric between 99 and 101 and not (restore_drill_status() ->> 'never')::boolean);
select restore_drill_record('backup-new','pass',true,true,' ok ') as d2 \gset
select tt.chk('T3 fresh pass clears the warning', not (restore_drill_status() ->> 'warn')::boolean and (restore_drill_status() ->> 'drills')::int=2 and (restore_drill_status() -> 'last' ->> 'backup_name')='backup-new');
select restore_drill_record('backup-bad','fail',true,false,'row counts differ') as d3 \gset
select tt.chk('T3 a later fail is shown (last_failed) but the last pass still counts', (restore_drill_status() ->> 'last_failed')::boolean and not (restore_drill_status() ->> 'warn')::boolean);
select tt.chk('T3 list newest first, notes trimmed', (restore_drill_list() -> 0 ->> 'backup_name')='backup-bad' and (restore_drill_list() -> 1 ->> 'notes')='ok' and jsonb_array_length(restore_drill_list(2))=2);
select tt.chk('T3 recorded_by is the owner', (select count(*) from restore_drills where recorded_by=:'o'::uuid)=3);

\echo == T4 append only
select tt.err('T4 update refused', $$update restore_drills set result='pass'$$, 'append_only');
select tt.err('T4 delete refused', $$delete from restore_drills$$, 'append_only');
select tt.err('T4 browser role cannot write directly', $$set local role authenticated; insert into restore_drills (backup_name,result) values ('x','pass')$$, 'permission denied');
reset role;
select tt.as(:'s'); set role authenticated;
select count(*) as mgr_rows from restore_drills \gset
select tt.as(:'o');
select count(*) as own_rows from restore_drills \gset
reset role;
select tt.chk('T4 RLS: owner reads the drills, manager sees none', :own_rows=3 and :mgr_rows=0);

\echo == T5 rule can be changed by the owner
select tt.as(:'o');
select set_rule('restore_drill_warn_days','30'::jsonb) is null as r1 \gset
select tt.chk('T5 warn days now 30', (restore_drill_status() ->> 'warn_days')::numeric=30);
select tt.err('T5 below min refused', $$select set_rule('restore_drill_warn_days','1'::jsonb)$$, 'bad_value');
select set_rule('restore_drill_warn_days',null) is null as r2 \gset

\echo == T6 backup list still works
select tt.chk('T6 _backup_tables has restore_drills itself', 'restore_drills' = any(public._backup_tables()));

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
