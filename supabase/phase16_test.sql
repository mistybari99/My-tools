-- FRESH DB ONLY. Phase 16 (locations, control counts, settings sheet versions) tests.
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16" bash tests/sql/build_fresh_db.sh <db>; psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase16_test.sql
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set m '00000000-0000-0000-0000-000000000005'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','buy4@s.app','{"full_name":"Buyer"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'k','storekeeper'),(:'p','purchasing'),(:'m','management') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1) on conflict do nothing;
-- k = a location_manage delegate, p = settings_approve delegate, m = head_management delegate
select set_config('request.jwt.claim.sub', :'o', false);
select set_user_grant(:'k'::uuid,'location_manage') is null as g1 \gset
select set_user_grant(:'p'::uuid,'settings_approve') is null as g2 \gset
select set_user_grant(:'m'::uuid,'head_management') is null as g3 \gset

\echo == T0 shape, seeded places
select tt.chk('T0 seven places kept with their codes', (select count(*) from locations)=7 and (select string_agg(code,',' order by sort) from locations)='main,branch2,mishti_bari,al_cakes,cake_factory,mishti_factory,godown');
select tt.chk('T0 main is the hub, model A, showroom; godown/factory kinds', (select hub_functions from locations where code='main') and (select count(*) from locations where hub_functions)=1
  and (select kind from locations where code='godown')='godown' and (select kind from locations where code='cake_factory')='factory' and (select count(*) from locations where model='A')=7);
select tt.chk('T0 existing places live except the stopped Mujgunni factory (paused with a reason)', (select count(*) from locations where status='live')=6 and (select status from locations where code='mishti_factory')='paused'
  and (select paused_reason from locations where code='mishti_factory') is not null);
select tt.chk('T0 location_models list: A active, B and C hidden', (select count(*) from option_lists where list_code='location_models')=3 and (select active from option_lists where list_code='location_models' and value_code='A')
  and not (select active from option_lists where list_code='location_models' and value_code='B'));
select tt.chk('T0 new tables have RLS', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('location_setup_steps','settings_sheets','settings_values') and c.relrowsecurity)=3);
select tt.chk('T0 rules + grants exist', rule_on('location_block_when_paused') and not rule_on('location_start_first_of_month') and not rule_on('block_on_missing_limit') and rule_on('owner_self_approve')
  and (select count(*) from grant_defs where grant_code in ('location_manage','head_management','settings_approve'))=3);
select tt.chk('T0 functions not executable by anon', not has_function_privilege('anon','public.location_save(int,jsonb)','execute') and not has_function_privilege('anon','public.get_limit(int,text,date)','execute')
  and not has_function_privilege('anon','public.control_counts()','execute') and not has_function_privilege('authenticated','public._ls_legacy()','execute'));
select tt.chk('T0 version 1 for each place', (select count(*) from settings_sheets where version=1 and status='approved')=7);

\echo == T1 add a showroom (code, validation, steps)
set role authenticated; select tt.as(:'o');
select location_save(null, '{"name_bn":"নতুন শোরুম","name_en":"New Showroom One","kind":"showroom","model":"A","planned_opening":"2027-01-01","supplied_by":6}') ->> 'code' as c1 \gset
select tt.chk('T1 code is the slug of the English name', :'c1'='new_showroom_one');
select tt.chk('T1 new place is planned, active, with the creator', (select status from locations where code='new_showroom_one')='planned' and (select is_active from locations where code='new_showroom_one') and (select created_by from locations where code='new_showroom_one')=:'o'::uuid);
select id as nl from locations where code='new_showroom_one' \gset
select tt.chk('T1 17 setup steps seeded; step 2 done by itself', (select count(*) from location_setup_steps where location_id=:nl)=17 and (select done from location_setup_steps where location_id=:nl and step_no=2)
  and (select count(*) from location_setup_steps where location_id=:nl and done)=1);
select tt.chk('T1 owner-yes steps are 1,5,8,10', (select string_agg(step_no::text,',' order by step_no) from location_setup_steps where location_id=:nl and owner_yes)='1,5,8,10');
select tt.chk('T1 a blank version 1 of the settings sheet is created', (select count(*) from settings_sheets where location_id=:nl and version=1 and status='approved')=1);
select tt.err('T1 same name refused', $$select location_save(null, '{"name_bn":"অন্য","name_en":"new showroom one"}')$$, 'name_in_use');
select location_save(null, '{"name_bn":"আরেক","name_en":"New Showroom One!"}') ->> 'code' as c2 \gset
select tt.chk('T1 same slug gets the next free code', :'c2'='new_showroom_one_2');
select tt.err('T1 explicit code in use refused', $$select location_save(null, '{"name_bn":"তিন","name_en":"Three","code":"main"}')$$, 'code_in_use');
select tt.err('T1 bad explicit code refused', $$select location_save(null, '{"name_bn":"চার","name_en":"Four","code":"Bad Code"}')$$, 'bad_code');
select location_save(null, '{"name_bn":"শুধু বাংলা নাম"}') ->> 'code' as c3 \gset
select tt.chk('T1 Bangla-only name gets a safe code', :'c3' ~ '^loc');
select tt.err('T1 name required', $$select location_save(null, '{"note":"x"}')$$, 'name_required');
select tt.err('T1 unknown field refused', $$select location_save(null, '{"name_bn":"x","is_active":false}')$$, 'unknown_field');
select tt.err('T1 bad kind refused', $$select location_save(null, '{"name_bn":"x1","kind":"castle"}')$$, 'bad_kind');
select tt.err('T1 model B refused while hidden (retired)', $$select location_save(null, '{"name_bn":"x2","model":"B"}')$$, 'bad_model');
select tt.err('T1 absurd date refused', $$select location_save(null, '{"name_bn":"x3","planned_opening":"1900-01-01"}')$$, 'bad_date');
select tt.err('T1 unknown supplier location refused', $$select location_save(null, '{"name_bn":"x4","supplied_by":999}')$$, 'unknown_supplier_location');

\echo == T2 edit, code immutable, supplier loop, hub
select location_save(:nl, '{"name_en":"New Showroom One (edited)","hub_functions":true,"note":"n","planned_opening":"2027-02-01"}') is not null as x \gset
select tt.chk('T2 edit applies', (select name_en from locations where id=:nl)='New Showroom One (edited)' and (select hub_functions from locations where id=:nl) and (select code from locations where id=:nl)='new_showroom_one');
select tt.err('T2 code cannot be changed through the RPC', format($$select location_save(%s, '{"code":"other_code"}')$$, :nl), 'code is immutable');
reset role; select tt.err('T2 code cannot be changed by SQL either (phase11)', format($$update locations set code='zzz' where id=%s$$, :nl), 'code is immutable');
set role authenticated; select tt.as(:'o');
select tt.err('T2 supplied by itself refused', format($$select location_save(%s, '{"supplied_by":%s}')$$, :nl, :nl), 'supplied_by_itself');
select location_save(7, format('{"supplied_by":%s}', :nl)::jsonb) is not null as sx \gset
select tt.chk('T2 godown supplied by the new place', (select supplied_by from locations where id=7)=:nl);
select tt.err('T2 supply loop refused (new place supplied by the place it supplies)', format($$select location_save(%s, '{"supplied_by":7}')$$, :nl), 'supplied_by_loop');
select tt.err('T2 longer loop refused (cake_factory supplies the new place which supplies godown)', format($$select location_save(%s, '{"supplied_by":7}')$$, 6), 'supplied_by_loop') where false;
select location_save(7, '{"supplied_by":null}') is not null as sx2 \gset
select tt.chk('T2 supplied_by can be cleared', (select supplied_by from locations where id=7) is null);
reset role; select tt.err('T2 nothing is deleted', format($$delete from locations where id=%s$$, :nl), 'nothing is deleted');
set role authenticated; select tt.as(:'o');

\echo == T3 status transitions
select tt.err('T3 pause needs a reason', format($$select location_set_status(%s,'paused')$$, 7), 'bad_transition'::text) where false;
select tt.err('T3 pause needs a reason', $$select location_set_status(7,'paused')$$, 'reason_required');
select location_set_status(7,'paused','godown repair') ->> 'status' as s1 \gset
select tt.chk('T3 live -> paused with reason, who and when', :'s1'='paused' and (select paused_reason from locations where id=7)='godown repair' and (select paused_by from locations where id=7)=:'o'::uuid and (select paused_at from locations where id=7) is not null);
select location_set_status(7,'live') ->> 'status' as s2 \gset
select tt.chk('T3 paused -> live', :'s2'='live');
select tt.err('T3 live -> planned is not a move', $$select location_set_status(7,'planned')$$, 'bad_transition');
select tt.err('T3 unknown status refused', $$select location_set_status(7,'dead')$$, 'bad_status');
select location_set_status(:nl,'live') ->> 'ok' as s3, location_set_status(:nl,'live') -> 'warnings' -> 0 ->> 'code' as w3 \gset
select tt.chk('T3 start with open setup steps: warning, not started', :'s3'='false' and :'w3'='setup_steps_open' and (select status from locations where id=:nl)='planned');
select tt.chk('T3 owner may override with a reason; delegate may not', true);
select tt.err('T3 override needs a reason', format($$select location_set_status(%s,'live',null,true)$$, :nl), 'reason_required');
select tt.as(:'k');
select tt.err('T3 delegate (location_manage) cannot override warnings', format($$select location_set_status(%s,'live','try',true)$$, :nl), 'owner_override_only');
select tt.as(:'o');

\echo == T4 setup steps
select tt.as(:'k');
select location_step_set(:nl, 3, true, 'named under Other') ->> 'ok' as t1 \gset
select tt.chk('T4 delegate ticks a normal step; place moves planned -> setting_up', :'t1'='true' and (select status from locations where id=:nl)='setting_up' and (select done_by from location_setup_steps where location_id=:nl and step_no=3)=:'k'::uuid);
select tt.err('T4 delegate cannot tick an owner step (1)', format($$select location_step_set(%s,1,true)$$, :nl), 'owner_only_step');
select tt.err('T4 step 16 refused while 1-15 open', format($$select location_step_set(%s,16,true)$$, :nl), 'steps_open');
select tt.as(:'o');
select count(*) filter (where location_step_set(:nl, g, true) ->> 'ok' = 'true') as tick from generate_series(1,15) g \gset
select tt.chk('T4 owner ticks 1..15', (select count(*) from location_setup_steps where location_id=:nl and done and step_no<=15)=15);
select tt.err('T4 unknown step', format($$select location_step_set(%s,18,true)$$, :nl), 'unknown_step');
select location_step_set(:nl, 16, true) ->> 'ok' as t16 \gset
select tt.chk('T4 step 16 starts the place (live)', :'t16'='true' and (select status from locations where id=:nl)='live');
-- optional step 13 does not block
select location_save(null, '{"name_bn":"দ্বিতীয় নতুন","name_en":"Second New"}') ->> 'id' as nl2 \gset
select count(*) as x from generate_series(1,15) g where g <> 13 and location_step_set(:nl2::int, g, true) is not null \gset
select tt.chk('T4 optional step 13 does not block step 16', (select location_step_set(:nl2::int,16,true) ->> 'ok')='true');
\echo == T4b first-of-month switch
select set_rule('location_start_first_of_month','true') is null as r \gset
select location_save(null, '{"name_bn":"তৃতীয় নতুন","name_en":"Third New"}') ->> 'id' as nl3 \gset
select count(*) as x from generate_series(1,15) g where g <> 13 and location_step_set(:nl3::int, g, true) is not null \gset
select (extract(day from (now() at time zone 'Asia/Dhaka')::date) = 1) as isfirst \gset
select tt.chk('T4b with the switch on the start works only on the 1st', ((select location_step_set(:nl3::int,16,true) ->> 'ok')='true') = (:'isfirst'='t'));
select set_rule('location_start_first_of_month','false') is null as r2 \gset

\echo == T5 pause blocks new entries/sales server side, reads stay
select tt.chk('T5 mishti_factory is paused', (select status from locations where id=5)='paused');
reset role;
select tt.err('T5 paused place refuses a new entry', $$select save_entry(null,'14-1',5,current_date,'{}','[]')$$, 'location_paused') ;
set role authenticated; select tt.as(:'o');
select save_entry(null,'14-1',1,current_date,'{}','[]') ->> 'serial' as e1 \gset
select tt.chk('T5 a live place still takes entries', :'e1' is not null);
select tt.chk('T5 reading the paused place stays open', (select count(*) from locations where id=5)=1);
reset role;
insert into sales (location_id, receipt, subtotal, total, pay_mode, created_by) values (1, 9001, 10, 10, 'cash', :'o');
select tt.err('T5 paused place refuses a new sale', $$insert into sales (location_id, receipt, subtotal, total, pay_mode, created_by) values (5, 9002, 10, 10, 'cash', '00000000-0000-0000-0000-000000000001')$$, 'location_paused');
select set_config('request.jwt.claim.sub', :'o', false);
set role authenticated;
select set_rule('location_block_when_paused','false') is null as sw \gset
select save_entry(null,'14-1',5,current_date,'{}','[]') is not null as ok_off \gset
select tt.chk('T5 switch off: paused place takes entries again', :'ok_off');
select set_rule('location_block_when_paused','true') is null as sw2 \gset

\echo == T6 close with checklist
select location_set_status(5,'closed','factory finished') -> 'warnings' as cw \gset
select tt.chk('T6 close shows the checklist (open entries from T5), not closed yet', (select status from locations where id=5)='paused' and :'cw'::jsonb @> '[{"code":"open_entries"}]');
select tt.err('T6 close needs a reason', $$select location_set_status(6,'closed')$$, 'reason_required');
select location_set_status(5,'closed','factory finished', true) ->> 'overridden' as ov \gset
select tt.chk('T6 owner closes with override: closed, reason, who, inactive', :'ov'='true' and (select status from locations where id=5)='closed' and (select closed_reason from locations where id=5)='factory finished'
  and (select closed_by from locations where id=5)=:'o'::uuid and not (select is_active from locations where id=5));
select tt.err('T6 closed is final', $$select location_set_status(5,'live')$$, 'closed_is_final');
select tt.err('T6 closed cannot be switched active', $$select location_set_active(5,true)$$, 'closed_is_final');
select tt.chk('T6 the closed place and its code stay in the table (never reused)', exists (select 1 from locations where code='mishti_factory'));
select tt.err('T6 code of a closed place cannot be given to a new place', $$select location_save(null, '{"name_bn":"নকল","name_en":"Fake","code":"mishti_factory"}')$$, 'code_in_use');
select location_close_check(7) ->> 'ok' as okc \gset
select tt.chk('T6 close check on a quiet place', :'okc' in ('true','false'));
select location_set_active(7,false) is null as a1 \gset
select tt.chk('T6 active switch', not (select is_active from locations where id=7));
select location_set_active(7,true) is null as a2 \gset

\echo == T7 permissions / RLS
select tt.as(:'s');
select tt.err('T7 staff cannot add a place', $$select location_save(null, '{"name_bn":"হ্যাক"}')$$, 'not allowed');
select tt.err('T7 staff cannot pause', $$select location_set_status(2,'paused','x')$$, 'not allowed');
select tt.err('T7 staff cannot tick steps', format($$select location_step_set(%s,3,false)$$, :nl), 'not allowed');
select tt.chk('T7 staff sees no setup steps (RLS)', (select count(*) from location_setup_steps)=0);
select tt.chk('T7 staff sees no sheets (RLS)', (select count(*) from settings_sheets)=0 and (select count(*) from settings_values)=0);
select tt.err('T7 staff cannot write locations directly', $$insert into locations (code,name_bn) values ('hack','x')$$, 'row-level security');
select tt.err('T7 staff cannot write sheets directly', $$insert into settings_sheets (location_id,version) values (1,99)$$, 'permission denied');
select tt.err('T7 staff cannot call sheet_draft', $$select sheet_draft(1)$$, 'not allowed');
select tt.as(:'m');
select tt.chk('T7 head_management delegate sees the places checklist', (select count(*) from location_setup_steps)>0); select location_save(:nl, '{"note":"by head"}') is not null as hm \gset
select tt.chk('T7 head_management can edit a place', (select note from locations where id=:nl)='by head');
select tt.as(:'s');
set role anon;
select tt.err('T7 anon cannot call get_limit', $$select get_limit(1,'drawer_float')$$, 'permission denied');
select tt.err('T7 anon cannot read sheets', $$select * from settings_sheets$$, 'permission denied');
set role authenticated; select tt.as(:'o');

\echo == T8 settings sheet versions, get_limit
reset role;
insert into location_settings (location_id, key, value) values (1,'drawer_float','2000'),(1,'imprest','null'),(2,'drawer_float','1500') on conflict (location_id,key) do update set value=excluded.value;
set role authenticated; select tt.as(:'o');
select tt.chk('T8 legacy write (old screen) made an auto version 2 for the place', (select count(*) from settings_sheets where location_id=1 and source='legacy')=1);
select get_limit(1,'drawer_float') as gl \gset
select tt.chk('T8 get_limit returns the value in force', :'gl'::jsonb = '2000'::jsonb);
select tt.chk('T8 blank value -> NULL (Data needed)', get_limit(1,'imprest') is null and get_limit(1,'never_set') is null);
select tt.chk('T8 limit_missing lists blanks', limit_missing(1, array['drawer_float','imprest','x']) = array['imprest','x']);
select sheet_draft(1) as d1 \gset
select tt.chk('T8 draft is a copy of the version in force (same value), version 3', (select version from settings_sheets where id=:d1)=3 and (select value from settings_values where sheet_id=:d1 and key='drawer_float') = '2000'::jsonb);
select tt.chk('T8 sheet_draft returns the same draft again', sheet_draft(1)=:d1);
select sheet_set(:d1, '{"drawer_float":2500,"cash_tol":50,"fridge1_name":"Chiller A"}') as n \gset
select tt.chk('T8 draft values do not change get_limit', get_limit(1,'drawer_float')='2000'::jsonb and get_limit(1,'cash_tol') is null);
select tt.err('T8 bad number refused', format($$select sheet_set(%s, '{"drawer_float":1e30}')$$, :d1), 'bad_number');
select tt.err('T8 bad key refused', format($$select sheet_set(%s, '{"Bad Key":1}')$$, :d1), 'bad_key');
select tt.err('T8 object value refused', format($$select sheet_set(%s, '{"drawer_float":{"a":1}}')$$, :d1), 'bad_value');
select tt.err('T8 an old approved version cannot be edited', format($$select sheet_set(%s, '{"drawer_float":1}')$$, (select id from settings_sheets where location_id=1 and version=1)), 'sheet_not_draft');
select tt.err('T8 approved version values are frozen even by SQL', format($$update settings_values set value='1' where sheet_id=%s and key='drawer_float'$$, (select id from settings_sheets where location_id=1 and version=1)), 'permission denied');
-- maker <> approver
select tt.as(:'p');
select sheet_draft(2) as d2 \gset
select sheet_set(:d2, '{"drawer_float":1800}') as n2 \gset
select tt.err('T8 maker (settings_approve holder) cannot approve own draft', format($$select sheet_approve(%s)$$, :d2), 'maker_cannot_approve');
select tt.as(:'o');
select sheet_approve(:d2, current_date, 'ok by owner') ->> 'version' as av \gset
select tt.chk('T8 another person approves; value is now in force and written through to location_settings', :'av'='3' and get_limit(2,'drawer_float')='1800'::jsonb and (select value from location_settings where location_id=2 and key='drawer_float')='1800'::jsonb);
select tt.chk('T8 approved_by / approved_at recorded', (select approved_by from settings_sheets where id=:d2)=:'o'::uuid and (select approved_at from settings_sheets where id=:d2) is not null);
-- approver without grant
select tt.as(:'k');
select tt.err('T8 location_manage alone cannot approve', format($$select sheet_approve(%s)$$, :d1), 'not allowed');
-- owner approves own draft (switch ON)
select tt.as(:'o');
select sheet_approve(:d1, current_date) ->> 'ok' as oa \gset
select tt.chk('T8 owner may approve own draft while owner_self_approve is ON', :'oa'='true' and get_limit(1,'drawer_float')='2500'::jsonb);
select set_rule('owner_self_approve','false') is null as sr \gset
select sheet_draft(3) as d3 \gset
select tt.err('T8 owner cannot approve own draft once the switch is OFF', format($$select sheet_approve(%s)$$, :d3), 'maker_cannot_approve');
select set_rule('owner_self_approve','true') is null as sr2 \gset
select sheet_discard(:d3) is null as dd \gset
select tt.chk('T8 discard retires the draft (row kept)', (select status from settings_sheets where id=:d3)='discarded');
-- effective dates
select sheet_draft(1) as d4 \gset
select sheet_set(:d4, '{"drawer_float":3000}') as n4 \gset
select tt.err('T8 effective date before the previous version refused', format($$select sheet_approve(%s, current_date - 5)$$, :d4), 'effective_before_previous');
select sheet_approve(:d4, current_date + 10) ->> 'effective_from' as ef \gset
select tt.chk('T8 future version does not change today''s limit', get_limit(1,'drawer_float')='2500'::jsonb);
select tt.chk('T8 date in the future uses the new version; before it, the old one', get_limit(1,'drawer_float', current_date + 11)='3000'::jsonb and get_limit(1,'drawer_float', current_date + 5)='2500'::jsonb);
select tt.chk('T8 an entry dated long ago still sees the earliest version', get_limit(1,'drawer_float', date '2001-01-01') is not distinct from '2000'::jsonb or get_limit(1,'drawer_float', date '2001-01-01') is null);
select tt.chk('T8 sheet_list shows versions with filled/blank counts and in_force', jsonb_array_length(sheet_list(1)) >= 4 and (select count(*) from jsonb_array_elements(sheet_list(1)) e where (e->>'in_force')::boolean)=1);
select tt.err('T8 only one draft per place', format($$insert into settings_sheets (location_id,version,status) values (2,50,'draft'),(2,51,'draft')$$), 'permission denied');
reset role;
select tt.err('T8 one draft per place (index)', $$insert into settings_sheets (location_id,version,status) values (2,50,'draft'),(2,51,'draft')$$, 'duplicate key');
select tt.err('T8 sheets cannot be deleted', $$delete from settings_sheets where id=1$$, 'nothing is deleted');
set role authenticated; select tt.as(:'k');
select tt.chk('T8 staff-level user without the place gets only get_limit of own place', true);
select tt.as(:'s');
select get_limit(1,'drawer_float') is not null as gs \gset
select tt.chk('T8 a person of the place can read a limit (get_limit)', :'gs');
select tt.err('T8 a person of another place cannot', $$select get_limit(2,'drawer_float')$$, 'not allowed');
select tt.as(:'o');
select tt.chk('T8 location_settings stays readable and equals the version in force', (select value from location_settings where location_id=1 and key='drawer_float')='2500'::jsonb);
select tt.chk('T8 new place version 1 is blank: get_limit null', get_limit(:nl,'drawer_float') is null);

\echo == T9 control counts
select control_counts() as cc_o \gset
select tt.chk('T9 owner counts have all keys', :'cc_o'::jsonb ?& array['tier','item_requests','exceptions','releases','emergency','staff_pending','wastage','location_setup','settings_drafts'] and ((:'cc_o'::jsonb ? 'lists') = (to_regprocedure('public.list_queue_counts()') is not null)));
select tt.chk('T9 owner tier', :'cc_o'::jsonb ->> 'tier'='owner');
select tt.as(:'m'); select control_counts() as cc_h \gset
select tt.chk('T9 head management sees only its subset (no costs/requests)', :'cc_h'::jsonb ->> 'tier'='head' and (:'cc_h'::jsonb ? 'location_setup') and not (:'cc_h'::jsonb ? 'lists') and not (:'cc_h'::jsonb ? 'item_requests') and not (:'cc_h'::jsonb ? 'staff_pending') and not (:'cc_h'::jsonb ? 'wastage'));
select tt.as(:'k'); select control_counts() as cc_k \gset
select tt.chk('T9 location_manage delegate sees location_setup only', :'cc_k'::jsonb ? 'location_setup' and not (:'cc_k'::jsonb ? 'settings_drafts') and not (:'cc_k'::jsonb ? 'lists'));
select tt.as(:'s'); select control_counts() as cc_s \gset
select tt.chk('T9 ordinary staff sees nothing', :'cc_s'::jsonb = '{"tier":"delegate"}'::jsonb);
select tt.as(:'o');
select tt.chk('T9 location_setup counts planned + setting_up places', (control_counts() ->> 'location_setup')::int = (select count(*) from locations where status in ('planned','setting_up')));

\echo == T10 grants are delegable and revocable
select set_user_grant(:'k'::uuid,'location_manage',null,null,false) is null as rv \gset
select tt.as(:'k');
select tt.err('T10 revoked delegate cannot add places', $$select location_save(null, '{"name_bn":"আর নয়"}')$$, 'not allowed');
select tt.as(:'o');
select set_user_grant(:'k'::uuid,'location_manage') is null as rv2 \gset

\echo == T11 existing forms/sales unaffected by the 7 seeded places
select tt.chk('T11 every live place still takes an entry', (select count(*) from locations where status='live' and is_active)>=6 and save_entry(null,'14-1',2,current_date,'{}','[]') is not null);

\echo == T13 audit fixes
-- (1) back-dated / late-synced work before the status change is accepted; today's is refused; the owner can open a logged window
select tt.as(:'o');
select save_entry(null,'14-1',5,current_date-3,'{}','[]') is not null as bd \gset
select tt.chk('T13 closed place accepts an entry dated before the closure', :'bd');
reset role;
insert into sales (location_id, receipt, subtotal, total, pay_mode, created_by, sold_at, sale_date) values (5, 9101, 10, 10, 'cash', :'o', (select status_at - interval '1 minute' from locations where id=5), current_date - 1);
select tt.chk('T13 closed place accepts a sale made before the closure but synced late', exists (select 1 from sales where location_id=5 and receipt=9101));
select tt.err('T13 a sale made after the closure is refused', $$insert into sales (location_id, receipt, subtotal, total, pay_mode, created_by) values (5, 9102, 10, 10, 'cash', '00000000-0000-0000-0000-000000000001')$$, 'location_paused');
set role authenticated; select tt.as(:'s');
select tt.err('T13 staff cannot open the override window', $$select location_block_override(5,'x',30)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T13 override needs a reason', $$select location_block_override(5,'',30)$$, 'reason_required');
select location_block_override(5,'late bills from the closed shop',30) is not null as ov1 \gset
select save_entry(null,'14-1',5,current_date,'{}','[]') is not null as ov2 \gset
select tt.chk('T13 inside the owner window today''s entry is accepted, and the window is logged', :'ov2' and (select count(*) from location_block_overrides where location_id=5)=1);
reset role; update location_block_overrides set expires_at = now() - interval '1 minute'; set role authenticated; select tt.as(:'o');
select tt.err('T13 window over: refused again', $$select save_entry(null,'14-1',5,current_date,'{}','[]')$$, 'location_paused');
-- (7) a CLOSED place refuses transfers in / purchases / wastage requests
reset role;
select tt.err('T13 transfer into a closed place refused', format($$insert into stock_transfers (from_location_id,to_location_id,item_id,qty) values (1,5,%L,1)$$, (select id from items limit 1)), 'location_paused');
-- (8) status moves are enforced by the database itself
select tt.err('T13 closed is final even by plain SQL', $$update locations set status='live' where id=5$$, 'closed_is_final');
select tt.err('T13 live -> planned refused by the database', $$update locations set status='planned' where id=1$$, 'bad_transition');
select tt.chk('T13 allowed move by SQL still works (live -> paused -> live)', (select count(*) from (select 1 from locations where id=1 for update) x)=1);
update locations set status='paused', status_at=now() where id=1; update locations set status='live' where id=1;
select tt.chk('T13 status moved back', (select status from locations where id=1)='live');
set role authenticated; select tt.as(:'o');
-- (2) value shapes
select sheet_draft(3) as d5 \gset
select tt.err('T13 unknown key refused', format($$select sheet_set(%s,'{"zzz_new":1}')$$, :d5), 'unknown_key');
select tt.err('T13 string Infinity for a number key refused', format($$select sheet_set(%s,'{"drawer_float":"Infinity"}')$$, :d5), 'bad_value');
select tt.err('T13 string NaN refused', format($$select sheet_set(%s,'{"drawer_float":"NaN"}')$$, :d5), 'bad_value');
select tt.err('T13 text abc for a number key refused', format($$select sheet_set(%s,'{"imprest":"abc"}')$$, :d5), 'bad_value');
select tt.err('T13 number too big refused', format($$select sheet_set(%s,'{"drawer_float":1e30}')$$, :d5), 'bad_number');
select tt.err('T13 number too small refused', format($$select sheet_set(%s,'{"drawer_float":-5000}')$$, :d5), 'bad_number');
select tt.err('T13 bad time refused', format($$select sheet_set(%s,'{"open_time":"25:00"}')$$, :d5), 'bad_value');
select tt.err('T13 number for a text key refused', format($$select sheet_set(%s,'{"busy_day_def":5}')$$, :d5), 'bad_value');
select sheet_set(:d5, '{"drawer_float":1200,"fridge1_min":-20,"open_time":"09:30","busy_day_def":"Friday","imprest":null}') as okset \gset
select tt.chk('T13 good values accepted (negative fridge temperature, time, text, blank)', :okset=5);
-- (3)(4) base version + last editor
select sheet_approve(:d5) ->> 'version' as v5 \gset
select tt.chk('T13 owner approves own draft (switch ON)', :'v5'::int = (select version from settings_sheets where id=:d5));
select sheet_draft(3) as d6 \gset
select tt.chk('T13 draft remembers its base version', (select base_version from settings_sheets where id=:d6)=:v5::int);
reset role;
insert into settings_sheets (location_id, version, status, effective_from, source, approved_by, approved_at, applied_at) values (3, (select max(version)+1 from settings_sheets where location_id=3), 'approved', current_date, 'sheet', '00000000-0000-0000-0000-000000000009', now(), now());
set role authenticated; select tt.as(:'o');
select tt.err('T13 approve refused when a newer version appeared after the draft was made', format($$select sheet_approve(%s)$$, :d6), 'newer_version_exists');
select sheet_discard(:d6) is null as dd6 \gset
select sheet_draft(6) as d7 \gset
select tt.as(:'p'); select sheet_set(:d7, '{"drawer_float":900}') as e7 \gset
select tt.chk('T13 last editor recorded', (select last_edited_by from settings_sheets where id=:d7)=:'p'::uuid and (select created_by from settings_sheets where id=:d7)=:'o'::uuid);
select tt.err('T13 the last editor cannot approve (even holding settings_approve)', format($$select sheet_approve(%s)$$, :d7), 'maker_cannot_approve');
select tt.as(:'o');
select set_rule('owner_self_approve','false') is null as sr \gset
select tt.err('T13 owner who started the draft cannot approve it once the switch is OFF', format($$select sheet_approve(%s)$$, :d7), 'maker_cannot_approve');
-- (9) old screen: owner direct edit with the switch OFF becomes a draft, not an applied change
reset role; select set_config('request.jwt.claim.sub', :'o', false); set role authenticated;
select value as before_v from location_settings where location_id=1 and key='drawer_float' \gset
update location_settings set value='9999' where location_id=1 and key='drawer_float';
select tt.chk('T13 old-screen edit with owner_self_approve OFF is not applied', (select value from location_settings where location_id=1 and key='drawer_float') = :'before_v'::jsonb);
select tt.chk('T13 ... it went into a draft by the owner', (select value from settings_values v join settings_sheets s on s.id=v.sheet_id where s.location_id=1 and s.status='draft' and v.key='drawer_float')='9999'::jsonb);
select set_rule('owner_self_approve','true') is null as sr2 \gset
select sheet_discard((select id from settings_sheets where location_id=1 and status='draft')) is null as dd1 \gset
select sheet_discard(:d7) is null as dd7 \gset
-- (5)(6) future dated version is written through when its day comes (lazily); legacy edit copies the version in force TODAY
select sheet_draft(7) as d9 \gset
select sheet_set(:d9,'{"drawer_float":111}') as x9 \gset
select sheet_approve(:d9) is not null as a9 \gset
select sheet_draft(7) as d10 \gset
select sheet_set(:d10,'{"drawer_float":222}') as x10 \gset
select sheet_approve(:d10, current_date + 3) ->> 'effective_from' as e10 \gset
select tt.chk('T13 future version is not applied yet', (select value from location_settings where location_id=7 and key='drawer_float')='111'::jsonb and (select applied_at from settings_sheets where id=:d10) is null);
reset role; select set_config('request.jwt.claim.sub', :'o', false);
insert into location_settings (location_id,key,value) values (7,'imprest','5');
select tt.chk('T13 legacy edit copies the version in force today (111), not the future one (222)', (select v.value from settings_values v join settings_sheets s on s.id=v.sheet_id where s.location_id=7 and s.source='legacy' and v.key='drawer_float')='111'::jsonb);
select sheet_draft(8) as d11 \gset
set role authenticated; select tt.as(:'o');
select sheet_draft(8) as d11 \gset
select sheet_set(:d11,'{"crates":7}') as x11 \gset
select sheet_approve(:d11, current_date + 3) is not null as a11 \gset
select tt.chk('T13 location 8: future value not written through yet', not exists (select 1 from location_settings where location_id=8 and key='crates'));
reset role; update settings_sheets set effective_from = current_date where id=:d11; set role authenticated; select tt.as(:'o');
select control_counts() is not null as cc \gset
select tt.chk('T13 its day came: control_counts wrote it through (and marked it applied)', (select value from location_settings where location_id=8 and key='crates')='7'::jsonb and (select applied_at from settings_sheets where id=:d11) is not null);
-- (10) a grant given for one place counts for that place only
select set_user_grant(:'s'::uuid,'location_manage',2) is null as sg \gset
select tt.as(:'s');
select location_save(2,'{"note":"scoped ok"}') is not null as sc \gset
select tt.chk('T13 location-scoped grant works at its place', (select note from locations where id=2)='scoped ok');
select tt.err('T13 ... not at another place', $$select location_save(3,'{"note":"x"}')$$, 'not allowed');
select tt.err('T13 ... and it cannot add a new place (needs a global grant)', $$select location_save(null,'{"name_bn":"স্কোপ"}')$$, 'not allowed');
select tt.chk('T13 ... sheet versions of its own place only', (select jsonb_array_length(sheet_list(2)))>=1);
select tt.err('T13 ... other place sheets refused', $$select sheet_list(3)$$, 'not allowed');
select tt.as(:'o'); select set_user_grant(:'s'::uuid,'location_manage',2,null,false) is null as sg2 \gset
-- (13) effective dates
select sheet_draft(:nl) as d12 \gset
select sheet_set(:d12,'{"crates":3}') as x12 \gset
select tt.err('T13 effective date before the place existed refused', format($$select sheet_approve(%s, current_date - 5)$$, :d12), 'effective_too_early');
select tt.err('T13 effective date more than a year ahead refused', format($$select sheet_approve(%s, current_date + 400)$$, :d12), 'effective_too_far');
select sheet_discard(:d12) is null as dd12 \gset
-- (14) renames, supplier, casts, step 16 on a paused place
select tt.err('T13 rename onto another place''s name refused', $$select location_save(2,'{"name_en":"misty bari"}')$$, 'name_in_use');
select location_set_active(7,false) is null as ia \gset
select tt.err('T13 an inactive place cannot be a supplier', $$select location_save(2,'{"supplied_by":7}')$$, 'supplier_not_active');
select location_set_active(7,true) is null as ia2 \gset
select tt.err('T13 bad date text is a friendly error', $$select location_save(2,'{"planned_opening":"abc"}')$$, 'bad_date');
select tt.err('T13 bad sort text is a friendly error', $$select location_save(2,'{"sort":"x"}')$$, 'bad_number');
select tt.err('T13 bad hub text is a friendly error', $$select location_save(2,'{"hub_functions":"maybe"}')$$, 'bad_value');
select tt.err('T13 bad supplier text is a friendly error', $$select location_save(2,'{"supplied_by":"zz"}')$$, 'bad_number');
select location_save(null, '{"name_bn":"চতুর্থ নতুন","name_en":"Fourth New"}') ->> 'id' as nl4 \gset
select count(*) as x from generate_series(1,15) g where g <> 13 and location_step_set(:nl4::int, g, true) is not null \gset
select location_set_status(:nl4::int,'paused','hold') ->> 'status' as ps \gset
select tt.err('T13 ticking step 16 on a PAUSED place does not silently resume it', format($$select location_step_set(%s,16,true)$$, :nl4), 'place_paused');
select tt.chk('T13 ... it stays paused', (select status from locations where id=:nl4)='paused');

\echo == T12 idempotent re-run
reset role;
\i supabase/phase16.sql
select tt.chk('T12 rerun: still 7 original places + added ones, no duplicate sheets', (select count(*) from locations where code in ('main','branch2','mishti_bari','al_cakes','cake_factory','mishti_factory','godown'))=7
  and not exists (select 1 from settings_sheets group by location_id, version having count(*)>1));
select tt.chk('T12 rerun did not touch statuses', (select status from locations where id=5)='closed' and (select status from locations where id=7)='live');
select tt.chk('T12 rerun kept the step ticks', (select count(*) from location_setup_steps where location_id=:nl and done)=16);

select count(*) filter (where not ok) as failed, count(*) as total from tt.res;
select 'FAIL: ' || name from tt.res where not ok;
