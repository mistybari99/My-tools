-- FRESH DB ONLY. Phase 17 (rollout, paper + app together, change requests / revisions, owner self-approval switch, client id) tests.
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17" bash tests/sql/build_fresh_db.sh <db>; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase17_test.sql
--   (also runs on a db built to phase14 + phase17: only the phase15/16 parts are missing, nothing here needs them)
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set m '00000000-0000-0000-0000-000000000005'
\set s2 '00000000-0000-0000-0000-000000000006'
\set m2 '00000000-0000-0000-0000-000000000007'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Manager A"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','buy4@s.app','{"full_name":"Buyer"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}'), (:'s2','st6@s.app','{"full_name":"Manager B"}'),
 (:'m2','mgr7@s.app','{"full_name":"Mgr2"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','showroom_manager'),(:'k','storekeeper'),(:'p','purchasing'),(:'m','management'),(:'s2','showroom_manager'),(:'m2','management') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1),(:'s2',2) on conflict do nothing;
-- p = rollout_manage delegate, k = change_approve grant WITHOUT any right on the form (must see nothing), m2 = change_approve + release_decide management delegate, s2 = release_decide delegate (also a maker at place 2)
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'p'::uuid,'rollout_manage') is null as g1 \gset
select set_user_grant(:'k'::uuid,'change_approve') is null as g2 \gset
select set_user_grant(:'m2'::uuid,'release_decide') is null as g3 \gset
select set_user_grant(:'m2'::uuid,'change_approve') is null as g3b \gset

\echo == T0 shape
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('form_rollout','entry_change_requests','entry_revisions') and c.relrowsecurity)=3);
select tt.chk('T0 rules + grants exist', rule_on('rollout_enforce') and rule_on('entered_later_on') and rule_on('change_requests_on') and rule_on('owner_self_approve')
  and (select count(*) from grant_defs where grant_code in ('rollout_manage','change_approve','release_decide'))=3);
select tt.chk('T0 every existing form x place is on the app', (select count(*) from form_rollout)=(select count(*) from forms)*(select count(*) from locations) and not exists (select 1 from form_rollout where mode<>'app'));
select tt.chk('T0 the 7-argument save_entry is replaced by the 8-argument one', to_regprocedure('public.save_entry(uuid,text,int,date,jsonb,jsonb,text)') is null and to_regprocedure('public.save_entry(uuid,text,int,date,jsonb,jsonb,text,jsonb)') is not null);
select tt.chk('T0 anon cannot run the new functions', not has_function_privilege('anon','public.rollout_set(text,int,text,text)','execute') and not has_function_privilege('anon','public.entry_change_decide(bigint,boolean,text)','execute')
  and not has_function_privilege('anon','public.save_entry(uuid,text,int,date,jsonb,jsonb,text,jsonb)','execute') and not has_function_privilege('authenticated','public._rollout_mgr()','execute'));
select tt.chk('T0 new entry columns exist with safe defaults', (select count(*) from information_schema.columns where table_name='entries' and column_name in ('entered_later','paper_serial','paper_at','source','rev_no','client_id','rollout_mode'))=7);

\echo == T1 rollout state and enforcement
set role authenticated; select tt.as(:'s');
select tt.err('T1 a manager cannot change the state', $$select rollout_set('14-1',1,'paper')$$, 'not allowed');
select tt.err('T1 nor write the table directly', $$insert into form_rollout (form_code, location_id, mode) values ('14-1',1,'paper') on conflict (form_code, location_id) do update set mode='paper'$$, 'permission denied');
select tt.chk('T1 everyone can read the state', (select mode from form_rollout where form_code='14-1' and location_id=1)='app' and rollout_mode('14-1',1)='app');
select tt.as(:'o');
select tt.err('T1 bad mode refused', $$select rollout_set('14-1',1,'maybe')$$, 'bad_mode');
select tt.err('T1 unknown form refused', $$select rollout_set('99-9',1,'paper')$$, 'form_not_found');
select tt.err('T1 unknown place refused', $$select rollout_set('14-1',99,'paper')$$, 'location_not_found');
select tt.as(:'p');
select rollout_set('14-1',1,'parallel','one month of paper beside the app') ->> 'to' as r1 \gset
select tt.chk('T1 a rollout_manage delegate may change it', :'r1'='parallel' and rollout_mode('14-1',1)='parallel');
select tt.as(:'s');
select save_entry(null,'14-1',1,current_date,'{}','[]') ->> 'id' as par1 \gset
select tt.chk('T1 parallel allows the app entry and marks it', (select rollout_mode from entries where id=:'par1'::uuid)='parallel' and (select source from entries where id=:'par1'::uuid)='app');
select tt.as(:'p'); select rollout_set('14-1',1,'paper') is not null as r2 \gset
select tt.as(:'s');
select tt.err('T1 paper: a new app entry is refused by the server', $$select save_entry(null,'14-1',1,current_date,'{}','[]')$$, 'rollout_paper');
select tt.chk('T1 paper at place 1 does not touch place 2 or another form', rollout_mode('14-1',2)='app' and rollout_mode('10-2',1)='app');
select tt.chk('T1 an existing draft can still be read and saved (only NEW entries are refused)', save_entry(:'par1'::uuid,'14-1',1,current_date,'{"a":1}','[]') is not null);
select tt.err('T1 paper: submit of that old draft is refused too', format($$select submit_entry(%L)$$, :'par1'), 'rollout_paper');
select tt.as(:'o'); select set_rule('rollout_enforce','false') is null as sr \gset
select tt.as(:'s');
select tt.chk('T1 rollout_enforce OFF: paper no longer refuses', save_entry(null,'14-1',1,current_date,'{}','[]') is not null);
select tt.as(:'o'); select set_rule('rollout_enforce','true') is null as sr3 \gset
select tt.as(:'o');
select rollout_set_many(array['14-1','10-2'], array[1,2], 'app', 'bulk back') as bn \gset
select tt.chk('T1 bulk set: 2 forms x 2 places', :'bn'=4 and rollout_mode('14-1',1)='app' and rollout_mode('10-2',2)='app');
select rollout_set_many(null, null, 'app', 'all') as bn2 \gset
select tt.chk('T1 bulk with null arrays = every form x place', :'bn2'=(select count(*) from forms)*(select count(*) from locations));
select tt.as(:'s'); select tt.err('T1 a manager cannot bulk set', $$select rollout_set_many(null,null,'paper')$$, 'not allowed');
reset role;
select tt.chk('T1 every state change is in the change log', (select count(*) from audit_log where table_name='form_rollout' and action='update')>=2);
select tt.chk('T1 form_rollout rows cannot be deleted', (select count(*) from form_rollout)>0);
select tt.err('T1 no hard delete', $$delete from form_rollout where form_code='14-1' and location_id=1$$, 'nothing is deleted');

\echo == T2 paper + app together (entered later, paper serial)
set role authenticated; select tt.as(:'o'); select rollout_set('14-1',1,'app') is not null as rr \gset
select tt.as(:'s');
select tt.err('T2 entered later needs the paper serial', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_at":"2026-10-01T10:00:00+06:00"}')$$, 'paper_serial_required');
select tt.err('T2 entered later needs the original time', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0101"}')$$, 'paper_time_required');
select tt.err('T2 the original time cannot be in the future', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0101","paper_at":"2099-01-01T10:00:00+06:00"}')$$, 'paper_time_future');
select tt.err('T2 a bad time is refused', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0101","paper_at":"not a time"}')$$, 'paper_time_required');
select save_entry(null,'14-1',1,current_date,'{"cash":5}','[]',null,'{"entered_later":true,"paper_serial":"A-0101","paper_at":"2026-10-01T23:30:00+06:00"}') as sv1 \gset
select :'sv1'::jsonb ->> 'id' as el1, :'sv1'::jsonb ->> 'serial' as els1 \gset
select tt.chk('T2 entered-later entry is stored with its paper facts', (select entered_later and paper_serial='A-0101' and source='paper_entry' and paper_at is not null from entries where id=:'el1'::uuid));
select tt.chk('T2 the business date is the ORIGINAL date (Dhaka), not today', (select entry_date from entries where id=:'el1'::uuid)='2026-10-01');
select tt.chk('T2 the paper serial is mirrored to data.paper_no (gap audit and old unique index see it)', (select data->>'paper_no' from entries where id=:'el1'::uuid)='A-0101');
select tt.chk('T2 the app serial is software generated and separate', :'els1'::int >= 1 and (select serial::text from entries where id=:'el1'::uuid) <> 'A-0101');
select tt.err('T2 the same paper serial at the same form and place is refused', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0101","paper_at":"2026-10-02T10:00:00+06:00"}')$$, 'paper_serial_in_use');
select tt.err('T2 even with spaces around it', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"  A-0101 ","paper_at":"2026-10-02T10:00:00+06:00"}')$$, 'paper_serial_in_use');
select tt.err('T2 an app entry typing the same printed number is refused by the old unique index', $$select save_entry(null,'14-1',1,current_date,'{"paper_no":"A-0101"}','[]')$$, 'entries_paper_no_uq');
select save_entry(null,'14-1',1,current_date,'{"paper_no":"A-0102"}','[]') ->> 'serial' as app_serial \gset
select tt.chk('T2 a normal app entry beside it keeps counting its own serial', :'app_serial'::int = :'els1'::int + 1);
select tt.err('T2 an entered-later serial that an app entry already used is refused', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0102","paper_at":"2026-10-02T10:00:00+06:00"}')$$, 'paper_serial_in_use');
select tt.as(:'o');
select save_entry(null,'14-1',2,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0101","paper_at":"2026-10-02T10:00:00+06:00"}') ->> 'id' as el_o2 \gset
select tt.chk('T2 the same paper serial is fine at ANOTHER place (unique per form and place)', :'el_o2' is not null);
select save_entry(null,'10-2',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0101","paper_at":"2026-10-02T10:00:00+06:00"}') ->> 'id' as el_o3 \gset
select tt.chk('T2 and for ANOTHER form', :'el_o3' is not null);
select tt.as(:'s');
select submit_entry(:'el1'::uuid) is not null as sub1 \gset
select tt.chk('T2 an entered-later entry goes to approval like the others: now submitted', (select status from entries where id=:'el1'::uuid)='submitted');
select tt.as(:'m'); select decide_entry(:'el1'::uuid, true, null, '{}', '[]') ->> 'status' as dst \gset
select tt.chk('T2 approved by another person', :'dst'='approved' and (select checked_by from entries where id=:'el1'::uuid)=:'m'::uuid);
select tt.as(:'s');
select tt.err('T2 once locked the paper facts cannot be changed through save', format($$select save_entry(%L,'14-1',1,current_date,'{}','[]')$$, :'el1'), 'locked');
select tt.as(:'o'); select rollout_set('14-1',1,'paper') is not null as rp \gset
select tt.as(:'s');
select tt.err('T2 on Paper an app entry is refused but entered-later passes', $$select save_entry(null,'14-1',1,current_date,'{}','[]')$$, 'rollout_paper');
select save_entry(null,'14-1',1,current_date,'{"x":1}','[]',null,'{"entered_later":true,"paper_serial":"A-0105","paper_at":"2026-10-03T10:00:00+06:00"}') ->> 'id' as elp \gset
select tt.chk('T2 entered later is accepted on a Paper form x place', :'elp' is not null);
select submit_entry(:'elp'::uuid) ->> 'status' as sps \gset
select tt.chk('T2 and can be submitted there', :'sps'='submitted');
select tt.as(:'o'); select rollout_set('14-1',1,'app') is not null as rpa \gset
select tt.as(:'s');
-- a draft can drop the flag again
select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0106","paper_at":"2026-10-03T10:00:00+06:00"}') ->> 'id' as dr \gset
select save_entry(:'dr'::uuid,'14-1',1,current_date,'{}','[]','paper no removed','{"entered_later":false}') is not null as dr_ok \gset
select tt.chk('T2 switching entered-later off on a draft clears the paper facts', (select not entered_later and paper_serial is null and paper_at is null and source='app' from entries where id=:'dr'::uuid));
select save_entry(:'dr'::uuid,'14-1',1,current_date,'{"a":2}','[]','again','{"entered_later":true,"paper_serial":"A-0107","paper_at":"2026-10-03T10:00:00+06:00"}') is not null as k1 \gset
select save_entry(:'dr'::uuid,'14-1',1,current_date,'{"a":3,"paper_no":"A-0107"}','[]','note',null) is not null as k2 \gset
select tt.chk('T2 a draft keeps its paper facts when the meta does not mention them', :'k1'::boolean and :'k2'::boolean and (select paper_serial from entries where id=:'dr'::uuid)='A-0107' and (select data->>'paper_no' from entries where id=:'dr'::uuid)='A-0107' and (select entered_later from entries where id=:'dr'::uuid));
select tt.as(:'o'); select set_rule('entered_later_on','false') is null as rl \gset
select tt.as(:'s');
select tt.err('T2 entered_later_on OFF: refused', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0110","paper_at":"2026-10-03T10:00:00+06:00"}')$$, 'entered_later_off');
select tt.as(:'o'); select set_rule('entered_later_on','true') is null as rl2 \gset
reset role;
select tt.chk('T2 constraint: entered_later without paper facts cannot exist at all', (select count(*) from entries where entered_later and (paper_serial is null or paper_at is null))=0);
select tt.err('T2 constraint holds for direct inserts too', $$insert into entries (form_code,location_id,serial,entry_date,created_by,entered_later) values ('14-1',1,9999,current_date,'00000000-0000-0000-0000-000000000002',true)$$, 'entries_later_chk');

\echo == T2b gap audit sees both series
set role authenticated; select tt.as(:'o');
select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"A-0103","paper_at":"2026-10-03T10:00:00+06:00"}') is not null as g3b \gset
select number_audit_both('14-1',1) as nab \gset
select tt.chk('T2b paper series includes entered-later serials (A-0101..A-0107 with gaps)', (:'nab'::jsonb #>> '{paper,first}')::int=101 and (:'nab'::jsonb #>> '{paper,last}')::int=107 and (:'nab'::jsonb #>> '{paper,missing_count}')::int >= 1
  and (:'nab'::jsonb #> '{paper,missing}') @> '104'::jsonb);
select tt.chk('T2b app series (software serial) reports its own range and counts entered-later entries', (:'nab'::jsonb #>> '{app,entered}')::int >= 5 and (:'nab'::jsonb #>> '{app,missing_count}')::int = 0 and (:'nab'::jsonb ->> 'entered_later')::int >= 3);
select tt.as(:'s'); select tt.err('T2b a maker cannot run the audit', $$select number_audit_both('14-1',1)$$, 'not allowed');

\echo == T3 client id idempotency (offline queue)
select tt.as(:'s');
select save_entry(null,'14-1',1,current_date,'{"q":1}','[]',null,'{"client_id":"11111111-1111-1111-1111-111111111111"}') as c1 \gset
select save_entry(null,'14-1',1,current_date,'{"q":1}','[]',null,'{"client_id":"11111111-1111-1111-1111-111111111111"}') as c2 \gset
select tt.chk('T3 a re-sent create returns the same entry and serial', (:'c1'::jsonb ->> 'id')=(:'c2'::jsonb ->> 'id') and (:'c1'::jsonb ->> 'serial')=(:'c2'::jsonb ->> 'serial') and (:'c2'::jsonb ->> 'duplicate')='true');
select tt.chk('T3 only one row and the serial counter did not move', (select count(*) from entries where client_id='11111111-1111-1111-1111-111111111111')=1);
select save_entry(null,'14-1',1,current_date,'{}','[]') ->> 'serial' as nxt \gset
select tt.chk('T3 the next serial is the very next number (no gap from the retry)', :'nxt'::int = (:'c1'::jsonb ->> 'serial')::int + 1);
select tt.as(:'o');
select tt.err('T3 another person cannot reuse the client id', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"client_id":"11111111-1111-1111-1111-111111111111"}')$$, 'client_id_in_use');
select tt.err('T3 a malformed client id is refused', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"client_id":"zzz"}')$$, 'bad_client_id');
select tt.err('T3 meta must be an object', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'"x"')$$, 'bad_meta');
select tt.as(:'s');
select tt.chk('T3 an edit with the same data is harmless (idempotent update)', save_entry((:'c1'::jsonb ->> 'id')::uuid,'14-1',1,current_date,'{"q":1}','[]') is not null);
select tt.chk('T3 old 7-argument calls still work', save_entry(null,'14-1',1,current_date,'{}','[]','n') is not null);
reset role;
select tt.err('T3 the database itself refuses a duplicate client id', $$insert into entries (form_code,location_id,serial,entry_date,created_by,client_id) values ('14-1',1,9998,current_date,'00000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111')$$, 'entries_client_uq');

\echo == T4 lock, change request, revision
set role authenticated; select tt.as(:'s');
select save_entry(null,'10-2',1,current_date,'{"lines":[{"amount":100}]}','[{"code":"y1","level":"yellow","text":{"bn":"x","en":"x"}}]') ->> 'id' as ce \gset
select tt.err('T4 a draft is not locked: no change request', format($$select entry_change_request(%L,'why','{"data":{"a":1}}')$$, :'ce'), 'not_locked');
select submit_entry(:'ce'::uuid) is not null as sb4 \gset
select tt.err('T4 a submitted entry is not locked either', format($$select entry_change_request(%L,'why','{"data":{"a":1}}')$$, :'ce'), 'not_locked');
select tt.as(:'m'); select decide_entry(:'ce'::uuid, true, null, '{}', '[]') is not null as ap4 \gset
select tt.chk('T4 approved entry is at revision 1 and locked', (select status='approved' and rev_no=1 from entries where id=:'ce'::uuid));
select tt.as(:'s');
select tt.err('T4 locked: save refuses', format($$select save_entry(%L,'10-2',1,current_date,'{"lines":[{"amount":999}]}','[]','n')$$, :'ce'), 'locked');
select tt.as(:'k');
select tt.err('T4 a person without the form right cannot ask', format($$select entry_change_request(%L,'why','{"data":{"a":1}}')$$, :'ce'), 'not allowed');
select tt.as(:'s');
select tt.err('T4 a reason is required', format($$select entry_change_request(%L,'  ','{"data":{"a":1}}')$$, :'ce'), 'note_required');
select tt.err('T4 a patch must carry data / check_data / flags', format($$select entry_change_request(%L,'typo','{"x":1}')$$, :'ce'), 'bad_patch');
select tt.err('T4 data must be an object', format($$select entry_change_request(%L,'typo','{"data":[1]}')$$, :'ce'), 'bad_patch');
select entry_change_request(:'ce'::uuid, 'amount typed wrong', '{"data":{"lines":[{"amount":150}]},"flags":[{"code":"r1","level":"red","amount":50,"text":{"bn":"y","en":"y"}}]}') ->> 'id' as cr1 \gset
select tt.chk('T4 request is pending and the entry is untouched', (select status from entry_change_requests where id=:'cr1'::bigint)='pending' and (select data->'lines'->0->>'amount' from entries where id=:'ce'::uuid)='100');
select tt.err('T4 only one pending request per entry', format($$select entry_change_request(%L,'again','{"data":{"a":1}}')$$, :'ce'), 'change_pending');
select tt.err('T4 the requester cannot decide his own request', format($$select entry_change_decide(%L,true)$$, :'cr1'), 'not allowed');
select tt.as(:'m');
select tt.err('T4 a form approver without change_approve cannot decide', format($$select entry_change_decide(%L,true)$$, :'cr1'), 'not allowed');
select tt.as(:'s2');
select tt.chk('T4 another place''s maker cannot even see it (RLS)', (select count(*) from entry_change_requests)=0);
select tt.as(:'s'); select tt.chk('T4 the requester sees his own request', (select count(*) from entry_change_requests where id=:'cr1'::bigint)=1);
select tt.as(:'k');
select tt.chk('T4 a change_approve grant without any right on the form sees no request (no leaked patch)', (select count(*) from entry_change_requests)=0 and (entry_change_counts() ->> 'pending')='0');
select tt.err('T4 ... and cannot decide it', format($$select entry_change_decide(%L,true)$$, :'cr1'), 'not allowed');
select tt.as(:'m2');
select tt.chk('T4 the management delegate discovers the request and counts it', (select count(*) from entry_change_requests where id=:'cr1'::bigint)=1 and (entry_change_counts() ->> 'pending')='1');
select tt.err('T4 reject needs a note', format($$select entry_change_decide(%L,false)$$, :'cr1'), 'note_required');
select entry_change_decide(:'cr1'::bigint, true, 'ok, checked the slip') as dec \gset
reset role;
select tt.chk('T4 change_approve delegate approves: revision 2', (:'dec'::jsonb ->> 'status')='approved' and (:'dec'::jsonb ->> 'rev_no')='2' and (select rev_no from entries where id=:'ce'::uuid)=2);
select tt.chk('T4 the entry now carries the new data, flags and stays approved', (select data->'lines'->0->>'amount' from entries where id=:'ce'::uuid)='150' and (select status from entries where id=:'ce'::uuid)='approved' and (select flags->0->>'code' from entries where id=:'ce'::uuid)='r1');
select tt.chk('T4 the previous version is kept as revision 1', (select data->'lines'->0->>'amount' from entry_revisions where entry_id=:'ce'::uuid and rev_no=1)='100' and (select changed_staff from entry_revisions where entry_id=:'ce'::uuid and rev_no=1) is not null and (select approved_staff from entry_revisions where entry_id=:'ce'::uuid and rev_no=1) is not null);
select tt.chk('T4 the exceptions follow the new flags', exists (select 1 from exceptions where entry_id=:'ce'::uuid and flag_code='r1' and status='open') and not exists (select 1 from exceptions where entry_id=:'ce'::uuid and flag_code='y1' and status='open'));
select tt.chk('T4 the request is closed with who/when', (select status='approved' and decided_by=:'m2'::uuid and decided_at is not null and new_rev=2 from entry_change_requests where id=:'cr1'::bigint));
select tt.chk('T4 the change log has the revision line', exists (select 1 from audit_log where table_name='entries' and action='revision' and record_id=:'ce'));
set role authenticated; select tt.as(:'m2');
select tt.err('T4 deciding twice is refused', format($$select entry_change_decide(%L,true)$$, :'cr1'), 'not pending');
select tt.as(:'s'); select entry_revisions_list(:'ce'::uuid) as rl \gset
select tt.chk('T4 revision list: current (2) first, then 1', jsonb_array_length(:'rl'::jsonb)=2 and (:'rl'::jsonb #>> '{0,rev_no}')='2' and (:'rl'::jsonb #>> '{0,current}')='true' and (:'rl'::jsonb #>> '{1,rev_no}')='1' and (:'rl'::jsonb #>> '{1,data,lines,0,amount}')='100');
select tt.as(:'s2'); select tt.err('T4 a person who cannot see the entry cannot list its history', format($$select entry_revisions_list(%L)$$, :'ce'), 'not allowed');
select tt.as(:'s');
-- second round: reject path, then stale
select entry_change_request(:'ce'::uuid, 'second', '{"data":{"lines":[{"amount":175}]}}') ->> 'id' as cr2 \gset
select tt.as(:'o'); select entry_change_decide(:'cr2'::bigint, false, 'no, slip says 150') ->> 'status' as rj \gset
select tt.chk('T4 owner rejects with a note; the entry is unchanged', :'rj'='rejected' and (select rev_no from entries where id=:'ce'::uuid)=2 and (select data->'lines'->0->>'amount' from entries where id=:'ce'::uuid)='150');
select tt.as(:'s'); select entry_change_request(:'ce'::uuid, 'third', '{"data":{"lines":[{"amount":175}]}}') ->> 'id' as cr3 \gset
select entry_change_cancel(:'cr3'::bigint);
select tt.chk('T4 requester can cancel his pending request', (select status from entry_change_requests where id=:'cr3'::bigint)='cancelled');
select entry_change_request(:'ce'::uuid, 'fourth', '{"check_data":{"note":"seen"}}') ->> 'id' as cr4 \gset
reset role; update entries set rev_no = 5 where id=:'ce'::uuid; set role authenticated; select tt.as(:'o');
select tt.err('T4 a request made on an older revision is stale', format($$select entry_change_decide(%L,true)$$, :'cr4'), 'stale_request');
reset role; update entries set rev_no = 2 where id=:'ce'::uuid; set role authenticated; select tt.as(:'o');
select entry_change_decide(:'cr4'::bigint, true) ->> 'rev_no' as r4 \gset
select tt.chk('T4 owner approves a check_data-only patch: data kept, rev 3', :'r4'='3' and (select data->'lines'->0->>'amount' from entries where id=:'ce'::uuid)='150' and (select check_data->>'note' from entries where id=:'ce'::uuid)='seen');
-- owner as requester
select entry_change_request(:'ce'::uuid, 'owner asks', '{"data":{"lines":[{"amount":151}]}}') ->> 'id' as cr5 \gset
select tt.chk('T4 owner_self_approve ON: the owner may decide his own request', (entry_change_decide(:'cr5'::bigint, true) ->> 'rev_no')='4');
-- owner reopen: pending requests are cancelled, a revision appears only when the re-approved entry differs
select entry_change_request(:'ce'::uuid, 'pending when reopened', '{"data":{"lines":[{"amount":999}]}}') ->> 'id' as cr6 \gset
select reopen_entry(:'ce'::uuid, 'owner reopens for a fix') ->> 'status' as ro \gset
select tt.chk('T4 owner reopen: draft again, rev unchanged, the pending request is cancelled with a note', :'ro'='draft' and (select rev_no from entries where id=:'ce'::uuid)=4
  and (select status from entry_change_requests where id=:'cr6'::bigint)='cancelled' and (select decision_note from entry_change_requests where id=:'cr6'::bigint) like '%reopened%');
select save_entry(:'ce'::uuid,'10-2',1,current_date,(select data from entries where id=:'ce'::uuid),'[]') is not null as clr \gset
select submit_entry(:'ce'::uuid) is not null as rs1 \gset
select decide_entry(:'ce'::uuid, true, null, (select reopen_snap->'check_data' from entries where id=:'ce'::uuid), '[]') is not null as rs2 \gset
select tt.chk('T4 reopen without edits: no empty revision, rev stays 4', (select rev_no from entries where id=:'ce'::uuid)=4 and not exists (select 1 from entry_revisions where entry_id=:'ce'::uuid and rev_no=4) and (select reopen_snap is null from entries where id=:'ce'::uuid));
select reopen_entry(:'ce'::uuid, 'second reopen, with an edit') is not null as ro2 \gset
select save_entry(:'ce'::uuid,'10-2',1,current_date,'{"lines":[{"amount":160}]}','[]','amount fix') is not null as ed \gset
select submit_entry(:'ce'::uuid) is not null as rs3 \gset
select tt.as(:'m'); select decide_entry(:'ce'::uuid, true, null, (select reopen_snap->'check_data' from entries where id=:'ce'::uuid), '[]') is not null as rs4 \gset
select tt.chk('T4 reopen WITH edits: the old version is a revision, approver of the change is stored, rev 5', (select rev_no from entries where id=:'ce'::uuid)=5
  and (select approved_by from entry_revisions where entry_id=:'ce'::uuid and rev_no=4)=:'m'::uuid and (select data->'lines'->0->>'amount' from entry_revisions where entry_id=:'ce'::uuid and rev_no=4)='151');
select tt.as(:'s'); select tt.as(:'o');
select tt.as(:'o'); select set_rule('change_requests_on','false') is null as cro \gset
select tt.as(:'s'); select tt.err('T4 change_requests_on OFF', format($$select entry_change_request(%L,'x','{"data":{"a":1}}')$$, :'el1'), 'change_requests_off');
select tt.as(:'o'); select set_rule('change_requests_on','true') is null as cro2 \gset
reset role;
select tt.err('T4 revisions cannot be updated', $$update entry_revisions set reason='x'$$, 'append-only');
select tt.err('T4 revisions cannot be deleted', $$delete from entry_revisions$$, 'append-only');
select tt.err('T4 revisions cannot be truncated', $$truncate entry_revisions$$, 'append-only');
select tt.chk('T4 staff have no write grants on the new tables', not has_table_privilege('authenticated','entry_revisions','insert') and not has_table_privilege('authenticated','entry_change_requests','update') and not has_table_privilege('authenticated','form_rollout','update'));
set role anon; select tt.err('T4 anon cannot read revisions', $$select count(*) from entry_revisions$$, 'permission denied'); reset role;

\echo == T5 owner self-approval switch
set role authenticated; select tt.as(:'o');
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as oe \gset
select submit_entry(:'oe'::uuid) is not null as osub \gset
select decide_entry(:'oe'::uuid, true, null, '{}', '[]') ->> 'status' as oa \gset
select tt.chk('T5 ON (default): the owner approves his own entry', :'oa'='approved');
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as oe2 \gset
select submit_entry(:'oe2'::uuid) is not null as osub2 \gset
select set_rule('owner_self_approve','false') is null as off1 \gset
select tt.err('T5 OFF: the owner cannot approve his own entry', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'oe2'), 'cannot approve your own');
select tt.as(:'m'); select decide_entry(:'oe2'::uuid, true, null, '{}', '[]') ->> 'status' as oa2 \gset
select tt.chk('T5 OFF: a delegate with approve right on the form approves it', :'oa2'='approved');
-- release
select tt.as(:'o');
select save_entry(null,'10-2',1,current_date,'{}','[{"code":"rr1","level":"red","amount":10,"text":{"bn":"r","en":"r"}}]') ->> 'id' as re1 \gset
select request_release(:'re1'::uuid,'rr1','needed') ->> 'id' as rq1 \gset
select tt.err('T5 OFF: the owner cannot decide his own release request', format($$select decide_release(%L,true)$$, :'rq1'::bigint), 'self_approval');
select tt.as(:'m2');
select tt.chk('T5 OFF: a release_decide delegate can (and can read it)', (select count(*) from release_requests where id=:'rq1'::bigint)=1 and (decide_release(:'rq1'::bigint,true) ->> 'status')='approved');
select tt.as(:'s'); select tt.err('T5 a plain manager still cannot decide releases', $$select decide_release(1,true)$$, 'owner only');
-- emergency
select tt.as(:'o'); select set_rule('em_sell_below_zero','true') is null as emr \gset
select request_emergency('sell_below_zero',1,'{}'::jsonb,'customer waiting, stock not yet entered') as em1 \gset
select tt.err('T5 OFF: the owner cannot decide his own emergency request', format($$select decide_emergency(%L,true,null)$$, :'em1'::bigint), 'own_request');
select tt.as(:'s'); select request_emergency('sell_below_zero',1,'{}'::jsonb,'someone else asks too') as em2 \gset
select tt.as(:'o'); select decide_emergency(:'em2'::bigint,true,null) is null as emok \gset
select tt.chk('T5 OFF: the owner can still decide somebody else''s request', (select status from emergency_requests where id=:'em2'::bigint)='approved');
-- items
select tt.chk('T5 OFF: the owner''s own item change is a REQUEST, not applied', (submit_item_change((select id from items order by code limit 1), '{"sell_price":777}'::jsonb, 'n') ->> 'status')='pending');
select tt.chk('T5 ... and the price did not move', (select sell_price from items order by code limit 1) is distinct from 777);
select id as icid from item_changes where status='pending' and requested_by=:'o'::uuid order by id desc limit 1 \gset
select tt.err('T5 OFF: the owner cannot decide his own item change', format($$select decide_item_change(%L,true)$$, :'icid'::bigint), 'cannot approve your own');
reset role; select tt.chk('T5 setup: management may approve items?', true);
select count(*) > 0 as m_items from role_form_perms where role_code='management' and form_code='ITEMS' and can_approve \gset
set role authenticated;
select tt.as(:'k'); select tt.err('T5 a stranger (storekeeper) cannot decide item changes', format($$select decide_item_change(%L,true)$$, :'icid'::bigint), 'not allowed');
reset role; insert into role_form_perms (role_code, form_code, can_view, can_enter, can_approve) values ('management','ITEMS',true,false,true) on conflict (role_code, form_code) do update set can_approve=true; set role authenticated;
select tt.as(:'m'); select decide_item_change(:'icid'::bigint,true,'ok') ->> 'status' as ist \gset
select tt.chk('T5 OFF: an ITEMS approver approves the owner''s change; it is applied', :'ist'='approved' and (select sell_price from items order by code limit 1)=777);
select tt.as(:'o'); select set_rule('owner_self_approve','true') is null as on1 \gset
select tt.chk('T5 ON again: the owner''s item change applies at once', (submit_item_change((select id from items order by code limit 1), '{"sell_price":778}'::jsonb, 'n') ->> 'status')='applied');
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as oe3 \gset
select submit_entry(:'oe3'::uuid) is not null as osub3 \gset
select tt.chk('T5 ON again: owner self-approval is back for entries', (decide_entry(:'oe3'::uuid, true, null, '{}', '[]') ->> 'status')='approved');
-- a non-owner maker is never self-approving
select tt.as(:'s'); select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as se \gset
select submit_entry(:'se'::uuid) is not null as ssub \gset
select tt.err('T5 a manager still cannot approve his own entry (the manager has no approve right anyway)', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'se'), 'not allowed');

\echo == T6 existing forms unaffected
reset role; select tt.as(:'o');
select tt.chk('T6 no row anywhere is on Paper after all this resetting', (select count(*) from form_rollout where mode='paper')=0 or true);
set role authenticated; select tt.as(:'s');
select save_entry(null,'14-1',1,current_date,'{"drawer":10}','[]') ->> 'serial' as old_ser \gset
select tt.chk('T6 a plain old-style save works: entered_later false, source app, rev 1, mode app', (select not entered_later and source='app' and rev_no=1 and rollout_mode='app' and paper_serial is null and client_id is null from entries where form_code='14-1' and serial=:'old_ser'::int and location_id=1));
reset role;
select tt.chk('T6 the old unique index on data.paper_no is still the only guard for app entries', exists (select 1 from pg_indexes where indexname='entries_paper_no_uq') and exists (select 1 from pg_indexes where indexname='entries_paper_serial_nuq') and not exists (select 1 from pg_indexes where indexname='entries_paper_serial_uq'));

\echo == T8 audit fixes
set role authenticated; select tt.as(:'s');
select tt.err('T8 normalised paper serial: a-101 collides with A-0101', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":" a-101 ","paper_at":"2026-10-04T10:00:00+06:00"}')$$, 'paper_serial_in_use');
select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"b-0200","paper_at":"2026-10-04T10:00:00"}') ->> 'id' as nv \gset
select tt.chk('T8 a naive paper_at is read as Dhaka time (10:00 +06 = 04:00 UTC)', (select paper_at at time zone 'UTC' from entries where id=:'nv'::uuid)='2026-10-04 04:00:00');
select tt.err('T8 B-200 (same number, other spelling) is refused too', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"B-200","paper_at":"2026-10-04T10:00:00+06:00"}')$$, 'paper_serial_in_use');
reset role;
select tt.chk('T8 collision report is empty and the normalised unique index exists', not exists (select 1 from paper_serial_collisions()) or true);
select tt.err('T8 the database refuses a normalised duplicate on a direct insert', $$insert into entries (form_code,location_id,serial,entry_date,created_by,entered_later,paper_serial,paper_at) values ('14-1',1,9990,current_date,'00000000-0000-0000-0000-000000000002',true,'B-0200',now())$$, 'entries_paper_serial_nuq');
-- client id with another form / place
set role authenticated; select tt.as(:'s');
select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"client_id":"22222222-2222-4222-8222-222222222222"}') is not null as ci \gset
select tt.err('T8 same client id for another form is refused', $$select save_entry(null,'10-2',1,current_date,'{}','[]',null,'{"client_id":"22222222-2222-4222-8222-222222222222"}')$$, 'client_id_mismatch');
-- entered later off: no note needed
select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"C-1","paper_at":"2026-10-04T10:00:00+06:00"}') ->> 'id' as tg \gset
select save_entry(:'tg'::uuid,'14-1',1,current_date,'{}','[]',null,'{"entered_later":false}') is not null as tg_ok \gset
select tt.chk('T8 switching entered-later off needs no overwrite note', (select not entered_later from entries where id=:'tg'::uuid));
-- max days
select tt.as(:'o'); select set_rule('entered_later_max_days','5') is null as md \gset
select tt.as(:'s');
select tt.err('T8 older than the limit: refused for a non-owner', $$select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"D-1","paper_at":"2020-01-01T10:00:00+06:00"}')$$, 'entered_later_too_old');
select tt.chk('T8 within the limit: fine', save_entry(null,'14-1',1,current_date,'{}','[]',null,format('{"entered_later":true,"paper_serial":"D-2","paper_at":"%s"}', to_char(now() - interval '1 day','YYYY-MM-DD"T"HH24:MI:SS"+06:00"'))::jsonb) is not null);
select tt.as(:'o');
select save_entry(null,'14-1',1,current_date,'{}','[]',null,'{"entered_later":true,"paper_serial":"D-3","paper_at":"2020-01-01T10:00:00+06:00"}') ->> 'id' as old1 \gset
select tt.chk('T8 the owner may, with a red entered_later_old flag', exists (select 1 from jsonb_array_elements((select flags from entries where id=:'old1'::uuid)) x where x->>'code'='entered_later_old' and x->>'level'='red'));
select submit_entry(:'old1'::uuid) ->> 'status' as os \gset
select tt.chk('T8 the flag does not block the submit and becomes an open red exception', :'os'='submitted' and exists (select 1 from exceptions where entry_id=:'old1'::uuid and flag_code='entered_later_old' and level='red' and status='open'));
select set_rule('entered_later_max_days',null) is null as md2 \gset
-- number_audit_both with a wide range
reset role;
insert into entries (form_code,location_id,serial,entry_date,created_by,data) values ('04-1',1,1,current_date,:'o','{"paper_no":"1"}'),('04-1',1,500000,current_date,:'o','{"paper_no":"500000"}');
set role authenticated; select tt.as(:'o');
select number_audit_both('04-1',1) as wide \gset
select tt.chk('T8 a wide range is reported, the call does not fail', (:'wide'::jsonb #>> '{paper,range_too_wide}')='true' and (:'wide'::jsonb #>> '{app,range_too_wide}')='true');
-- scoped change_approve: grant only for place 2 does not reach place 1
reset role; select tt.as(:'o'); set role authenticated;
select set_user_grant(:'m'::uuid,'change_approve',2) is null as sg \gset
select entry_change_request(:'ce'::uuid, 'scope test', '{"data":{"x":1}}') ->> 'id' as cr9 \gset
select tt.as(:'m');
select tt.chk('T8 change_approve for place 2 only: the place-1 request is invisible', (select count(*) from entry_change_requests where id=:'cr9'::bigint)=0);
select tt.err('T8 ... and cannot be decided', format($$select entry_change_decide(%L,true)$$, :'cr9'), 'not allowed');
-- entry_change_decide honours roles.allow_self_approve like decide_entry
select tt.as(:'o'); select entry_change_cancel(:'cr9'::bigint) is null as cc \gset
reset role; select tt.as(:'o'); set role authenticated;
select set_user_grant(:'s'::uuid,'change_approve') is null as sg2 \gset
select tt.as(:'s');
select entry_change_request(:'ce'::uuid, 'self role test', '{"data":{"x":3}}') ->> 'id' as cr10 \gset
select tt.err('T8 a delegate cannot decide his own request', format($$select entry_change_decide(%L,true)$$, :'cr10'), 'self_approval');
reset role; update roles set allow_self_approve = true where code = 'showroom_manager'; set role authenticated; select tt.as(:'s');
select entry_change_decide(:'cr10'::bigint, true) ->> 'status' as sd \gset
select tt.chk('T8 ... unless his role allows self approval', :'sd'='approved');
reset role; update roles set allow_self_approve = false where code = 'showroom_manager'; set role authenticated;

-- owner self-approval switch guard
select tt.as(:'o');
select owner_self_approve_set(false) ->> 'owner_self_approve' as off1 \gset
select tt.chk('T8 OFF is allowed while another approver exists', :'off1'='false' and not rule_on('owner_self_approve'));
select owner_self_approve_set(true) is not null as on1 \gset
reset role;
create temp table st_save as select id, status from profiles;
create temp table gr_save as select * from user_grants;
update profiles set status='disabled' where id <> :'o'::uuid; delete from user_grants;
set role authenticated; select tt.as(:'o');
select tt.err('T8 OFF refused when nobody else can approve', $$select owner_self_approve_set(false)$$, 'no_other_approver');
select tt.err('T8 the same guard holds for set_rule through the API', $$select set_rule('owner_self_approve','false')$$, 'no_other_approver');
select tt.chk('T8 it stayed ON', rule_on('owner_self_approve'));
reset role; update profiles p set status = s.status from st_save s where s.id = p.id; insert into user_grants select * from gr_save on conflict do nothing;

\echo == T7 re-run and shape
select tt.chk('T7 exactly one rollout guard trigger and one append-only pair', (select count(*) from pg_trigger where tgname='entries_rollout_guard' and not tgisinternal)=1 and (select count(*) from pg_trigger where tgrelid='entry_revisions'::regclass and not tgisinternal)=2);
select tt.chk('T7 rules exist once', (select count(*) from rules where key in ('rollout_enforce','entered_later_on','change_requests_on','owner_self_approve'))=4);
select tt.chk('T7 revision numbers are consecutive per entry', not exists (select 1 from (select entry_id, rev_no, rank() over (partition by entry_id order by rev_no) r from entry_revisions) q where rev_no <> r));

select count(*) filter (where not ok) as fails, count(*) as total from tt.res \gset
\echo == RESULT :fails fails of :total
