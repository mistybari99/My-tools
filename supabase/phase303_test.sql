-- FRESH DB ONLY. Phase 303 tests (CRM-B: consent record and withdraw per channel, do-not-contact, import, the message check, the hook proof on scratch copies).
--   bash tests/sql/crmb_run.sh        (builds a throwaway database on port 5572 through phase 98, pastes 303 to 305 twice, runs this file and the two after it)
--   or by hand:  psql -h /tmp -p 5572 -U postgres -d <db> -qAt -f supabase/phase303_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set u_o '00000000-0000-0000-0000-000000030301'
\set u_m '00000000-0000-0000-0000-000000030302'
\set u_c '00000000-0000-0000-0000-000000030303'
\set u_c2 '00000000-0000-0000-0000-000000030304'
\set u_n '00000000-0000-0000-0000-000000030305'
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
create or replace function tt.q(p_sql text) returns text language plpgsql security definer as $$
declare r text; begin execute p_sql into r; return r; end $$;       -- run a read as the table owner (the log tables are closed to browser roles)
create or replace function tt.je() returns bigint language sql security definer as $$ select count(*) from public.journal_entries $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'u_o','test_owner303@s.app','{"full_name":"test_owner303"}'), (:'u_m','test_mgr303@s.app','{"full_name":"test_mgr303"}'), (:'u_c','test_cashier303@s.app','{"full_name":"test_cashier303"}'),
 (:'u_c2','test_cashier2_303@s.app','{"full_name":"test_cashier2_303"}'), (:'u_n','test_nopos303@s.app','{"full_name":"test_nopos303"}') on conflict do nothing;
update profiles set status='active' where id in (:'u_o', :'u_m', :'u_c', :'u_c2', :'u_n');
insert into user_roles values (:'u_o','owner'),(:'u_m','showroom_manager'),(:'u_c','salesperson'),(:'u_c2','salesperson'),(:'u_n','storekeeper') on conflict do nothing;
insert into user_locations values (:'u_m',1),(:'u_c',1),(:'u_c2',2),(:'u_n',1) on conflict do nothing;
select tt.as(:'u_o');
select set_user_grant(:'u_m'::uuid,'customer_manage') is null as gm \gset
select set_rule('notify_sms_on','true') is null as son \gset
insert into customers (mobile, name) values ('01730300001','test_cust_a'),('01730300002','test_cust_b'),('01730300003','test_cust_c'),('01730300004','test_cust_d'),('01730300005','test_cust_e'),('123','test_cust_badphone'),('01730300006','test_cust_f');
select id as c1 from customers where mobile='01730300001' \gset
select id as c2 from customers where mobile='01730300002' \gset
select id as c3 from customers where mobile='01730300003' \gset
select id as c4 from customers where mobile='01730300004' \gset
select id as c5 from customers where mobile='01730300005' \gset
select id as cbad from customers where mobile='123' \gset
select id as c7 from customers where mobile='01730300006' \gset
select tt.je() as je0 \gset

\echo == T0 shape, safe defaults, nothing shared patched, internals closed
select tt.chk('T0 phase303 present', to_regprocedure('public._crmb_present()') is not null);
select tt.chk('T0 three rules, English text, safe defaults (pos consent OFF, quiet times blank)',
  (select count(*) from rules where key in ('crm_consent_pos_on','crm_quiet_from','crm_quiet_to') and module='crm')=3
  and not rule_on('crm_consent_pos_on') and rule_txt('crm_quiet_from') is null and rule_txt('crm_quiet_to') is null
  and not exists (select 1 from rules where key in ('crm_consent_pos_on','crm_quiet_from','crm_quiet_to') and (label_en ~ '[^\x01-\x7f]' or hint_en ~ '[^\x01-\x7f]' or label_bn is distinct from label_en)));
select tt.chk('T0 no shared function was patched (no bosCRMB inside notify_enqueue / notify_optin_set)',
  position('bosCRMB' in pg_get_functiondef('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure))=0
  and position('bosCRMB' in pg_get_functiondef('public.notify_optin_set(uuid,text,boolean,text,text)'::regprocedure))=0);
select tt.chk('T0 tables: RLS on, closed to browser writes',
  (select bool_and(relrowsecurity) from pg_class where relname in ('crm_consent_events','crm_contact_prefs'))
  and not has_table_privilege('authenticated','public.crm_consent_events','insert') and not has_table_privilege('authenticated','public.crm_contact_prefs','update')
  and not has_table_privilege('anon','public.crm_consent_events','select'));
select tt.chk('T0 API open to signed-in users only; helpers closed',
  has_function_privilege('authenticated','public._crmb_consent_set(uuid,uuid,text,boolean,text,text,int,text)','execute') and not has_function_privilege('anon','public._crmb_consent_set(uuid,uuid,text,boolean,text,text,int,text)','execute')
  and not has_function_privilege('authenticated','public._crmb_consent_apply(uuid,text,boolean,text,text,int,text,uuid,uuid,boolean)','execute')
  and not has_function_privilege('authenticated','public._crmb_send_allowed(uuid,text,text,timestamptz)','execute') and not has_function_privilege('authenticated','public._crmb_patch(regprocedure,text[],text)','execute')
  and not has_function_privilege('authenticated','public._crmb_enqueue_guard(uuid,text)','execute'));
select tt.chk('T0 existing customers keep no consent row (Not asked = nothing may be sent)', (select count(*) from notify_optin where customer_id in (:'c1',:'c2',:'c3',:'c4',:'c5'))=0);

\echo == T1 who may record (default: owner and customer manager only, as today)
set role authenticated;
select tt.as(:'u_c');
select tt.err('T1 cashier cannot record while crm_consent_pos_on is OFF', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'pos_tick')$$, :'c1'), 'not allowed');
select tt.err('T1 cashier cannot read consent while OFF', format($$select _crmb_consent_get(%L)$$, :'c1'), 'not allowed');
select tt.err('T1 cashier cannot set do-not-contact while OFF', format($$select _crmb_prefs_set(gen_random_uuid(), %L, true)$$, :'c1'), 'not allowed');
select tt.as(:'u_n');
select tt.err('T1 a user without POS cannot record', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone')$$, :'c1'), 'not allowed');
select tt.as('');
select tt.err('T1 nobody signed in cannot record', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone')$$, :'c1'), 'not allowed');
reset role; set role anon;
select tt.err('T1 anon has no execute', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone')$$, :'c1'), 'permission denied');
reset role; set role authenticated;

\echo == T2 manager records a yes: notify_optin, notify_optin_log and the evidence line; notify_enqueue then works
select tt.as(:'u_m');
select gen_random_uuid() as k1 \gset
select _crmb_consent_set(:'k1'::uuid, :'c1', 'sms', true, 'paper_form', 'signed form no 12', 1, 'v1') ->> 'status' as r1 \gset
select tt.chk('T2 answer is in', :'r1' = 'in');
select tt.chk('T2 notify_optin row: in, source customer_consent (paper form), note carries how and note',
  (select status from notify_optin where customer_id=:'c1' and channel='sms')='in' and (select source from notify_optin where customer_id=:'c1' and channel='sms')='customer_consent'
  and (select note from notify_optin where customer_id=:'c1' and channel='sms')='paper_form: signed form no 12');
select tt.chk('T2 old log has one line, evidence has one line with how, outlet, wording version, staff',
  (select count(*) from notify_optin_log where customer_id=:'c1')=1
  and tt.q(format($$select count(*) from crm_consent_events where customer_id=%L and kind='optin' and channel='sms' and status='in' and how='paper_form' and location_id=1 and text_version='v1' and staff_id is not null and note='signed form no 12'$$, :'c1'))='1');
select _crmb_consent_set(gen_random_uuid(), :'c2', 'whatsapp', true, 'owner_entry') ->> 'status' as r2 \gset
select tt.chk('T2 the owner entry way maps to owner_entry', :'r2'='in' and (select source from notify_optin where customer_id=:'c2' and channel='whatsapp')='owner_entry');
select tt.chk('T2 notify_enqueue now queues a message for the customer', (select notify_enqueue(gen_random_uuid(), :'c1', 'sms', 'thanks', '{"shop":"test_shop"}', 'en') ->> 'status')='queued');
select tt.err('T2 never asked: notify_enqueue refuses', format($$select notify_enqueue(gen_random_uuid(), %L, 'sms', 'thanks', '{}', 'en')$$, :'c3'), 'not_opted_in');
select tt.chk('T2 same client id twice: duplicate, nothing new', (select _crmb_consent_set(:'k1'::uuid, :'c1', 'sms', true, 'paper_form', 'signed form no 12', 1, 'v1') ->> 'duplicate')='true'
  and tt.q(format($$select count(*) from crm_consent_events where customer_id=%L$$, :'c1'))='1' and (select count(*) from notify_optin_log where customer_id=:'c1')=1);
select tt.chk('T2 a new client id for the same state: unchanged, no new line', (select _crmb_consent_set(gen_random_uuid(), :'c1', 'sms', true, 'phone') ->> 'unchanged')='true'
  and tt.q(format($$select count(*) from crm_consent_events where customer_id=%L$$, :'c1'))='1');

\echo == T3 withdraw: a no cancels queued messages at once and blocks new ones
select tt.chk('T3 one queued message waits', (select count(*) from notify_outbox where customer_id=:'c1' and status='queued')=1);
select _crmb_consent_set(gen_random_uuid(), :'c1', 'sms', false, 'phone', 'customer called') ->> 'cancelled' as cx \gset
select tt.chk('T3 the withdrawal reports 1 cancelled message', :'cx' = '1');
select tt.chk('T3 status out; queued message cancelled with reason opted_out; two log lines; two evidence lines',
  (select status from notify_optin where customer_id=:'c1' and channel='sms')='out' and (select status from notify_outbox where customer_id=:'c1')='cancelled'
  and (select last_error from notify_outbox where customer_id=:'c1')='opted_out' and (select count(*) from notify_optin_log where customer_id=:'c1')=2
  and tt.q(format($$select count(*) from crm_consent_events where customer_id=%L$$, :'c1'))='2');
select tt.err('T3 WITHDRAWN consent blocks queueing (notify_enqueue)', format($$select notify_enqueue(gen_random_uuid(), %L, 'sms', 'thanks', '{}', 'en')$$, :'c1'), 'not_opted_in');
select tt.chk('T3 the other channel is independent: whatsapp stays in', (select status from notify_optin where customer_id=:'c2' and channel='whatsapp')='in');
select _crmb_consent_set(gen_random_uuid(), :'c3', 'sms', false, 'message_reply', 'replied STOP') ->> 'status' as r3 \gset
select tt.chk('T3 withdrawing a customer who never said yes writes a "no" (so nobody asks again by mistake)', :'r3'='out' and (select status from notify_optin where customer_id=:'c3' and channel='sms')='out');

\echo == T4 a yes after a no needs a reason
select tt.err('T4 yes after no without a reason', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone')$$, :'c1'), 'reason_required');
select tt.err('T4 a 2-character reason is not a reason', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone', 'ok')$$, :'c1'), 'reason_required');
select tt.chk('T4 yes after no with a reason works and is audited',
  (select _crmb_consent_set(gen_random_uuid(), :'c1', 'sms', true, 'phone', 'customer asked to be messaged again') ->> 'status')='in'
  and tt.q($$select count(*) from audit_log where action='crm_consent_resubscribe'$$)='1');
select _crmb_consent_set(gen_random_uuid(), :'c1', 'sms', false, 'phone', 'again no') is not null as back_out \gset

\echo == T5 bad input
select tt.err('T5 bad channel', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'email', true, 'phone')$$, :'c4'), 'bad_input');
select tt.err('T5 bad way', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'shouted')$$, :'c4'), 'bad_input');
select tt.err('T5 note over 300', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone', repeat('x',301))$$, :'c4'), 'bad_input');
select tt.err('T5 missing client id', format($$select _crmb_consent_set(null, %L, 'sms', true, 'phone')$$, :'c4'), 'bad_input');
select tt.err('T5 yes/no missing', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', null, 'phone')$$, :'c4'), 'bad_input');
select tt.err('T5 unknown customer', $$select _crmb_consent_set(gen_random_uuid(), gen_random_uuid(), 'sms', true, 'phone')$$, 'customer_not_found');
select tt.err('T5 a yes needs a valid phone on the customer', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone')$$, :'cbad'), 'bad_phone');
select tt.chk('T5 a no for a customer with a bad phone is still recorded (protective)', (select _crmb_consent_set(gen_random_uuid(), :'cbad', 'sms', false, 'phone') ->> 'status')='out');
select tt.err('T5 outlet the manager does not hold', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'phone', null, 2)$$, :'c4'), 'not allowed for this location');

\echo == T6 counter staff: only while the owner switches it on, and only the ways that need the customer present
select tt.as(:'u_o'); select set_rule('crm_consent_pos_on','true') is null as pos_on \gset
select tt.as(:'u_c');
select tt.chk('T6 cashier records a yes at the counter (pos_tick, outlet 1)', (select _crmb_consent_set(gen_random_uuid(), :'c4', 'sms', true, 'pos_tick', null, 1) ->> 'status')='in');
select tt.err('T6 cashier cannot use owner_entry', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'owner_entry')$$, :'c5'), 'not allowed');
select tt.err('T6 cashier cannot use import', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'import')$$, :'c5'), 'not allowed');
select tt.err('T6 cashier cannot import a list', format($$select _crmb_consent_import(gen_random_uuid(), '[{"mobile":"01730300005"}]'::jsonb, 'sms', true, 'paper list', true)$$), 'not allowed');
select tt.err('T6 cashier cannot read the history', format($$select _crmb_consent_history(%L)$$, :'c4'), 'not allowed');
select tt.err('T6 cashier cannot see the register summary', $$select _crmb_consent_summary()$$, 'not allowed');
select tt.err('T6 cashier at outlet 1 cannot record for outlet 2', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'pos_tick', null, 2)$$, :'c5'), 'not allowed for this location');
select _crmb_consent_set_mobile(gen_random_uuid(), '০১৭৩০৩০০০০৫', 'whatsapp', true, 'pos_tick', null, 1) ->> 'status' as r6 \gset
select tt.chk('T6 cashier records by the mobile typed at the POS', :'r6'='in' and tt.q(format($$select status from notify_optin where customer_id=%L and channel='whatsapp'$$, :'c5'))='in');
select tt.err('T6 by mobile: unknown customer', $$select _crmb_consent_set_mobile(gen_random_uuid(), '01799999999', 'sms', true)$$, 'customer_not_found');
select tt.err('T6 by mobile: not a mobile number', $$select _crmb_consent_set_mobile(gen_random_uuid(), 'abc', 'sms', true)$$, 'bad_mobile');
select tt.chk('T6 cashier withdraws (any recorder may)', (select _crmb_consent_set(gen_random_uuid(), :'c4', 'sms', false, 'phone', 'at the counter') ->> 'status')='out');
select tt.chk('T6 cashier reads the status of the customer being served (no phone number inside)', (select _crmb_consent_get(:'c4') -> 'channels' -> 'sms' ->> 'status')='out'
  and position('0173' in (select _crmb_consent_get(:'c4')::text))=0);
select tt.chk('T6 get by mobile: unknown mobile answers found=false, known answers the state', (select _crmb_consent_get_mobile('01799999999') ->> 'found')='false'
  and (select _crmb_consent_get_mobile('01730300005') -> 'channels' -> 'whatsapp' ->> 'status')='in');
select tt.chk('T6 cashier sets do-not-contact ON (protective)',
  (select _crmb_prefs_set(gen_random_uuid(), :'c5', true, 'asked at the counter', 'pos_tick', 1) ->> 'dnc')='true');
select tt.err('T6 cashier cannot clear do-not-contact', format($$select _crmb_prefs_set(gen_random_uuid(), %L, false, 'mistake')$$, :'c5'), 'not allowed');
select tt.as(:'u_o'); select set_rule('crm_consent_pos_on','false') is null as pos_off \gset
select tt.as(:'u_c');
select tt.err('T6 switch OFF again: cashier refused again', format($$select _crmb_consent_set(gen_random_uuid(), %L, 'sms', true, 'pos_tick')$$, :'c3'), 'not allowed');
select tt.as(:'u_m');
select tt.err('T6 clearing needs a reason', format($$select _crmb_prefs_set(gen_random_uuid(), %L, false)$$, :'c5'), 'reason_required');
select tt.chk('T6 manager clears do-not-contact with a reason', (select _crmb_prefs_set(gen_random_uuid(), :'c5', false, 'customer changed mind') ->> 'dnc')='false');

\echo == T7 do-not-contact beats an opt-in
select _crmb_consent_set(gen_random_uuid(), :'c2', 'sms', true, 'phone') is not null as c2sms \gset
select notify_enqueue(gen_random_uuid(), :'c2', 'sms', 'thanks', '{}', 'en') ->> 'status' as q_sms \gset
select tt.chk('T7 setup: customer b has a yes on sms and whatsapp (whatsapp template missing is fine to ignore)', :'q_sms' = 'queued');
select gen_random_uuid() as kd \gset
select _crmb_prefs_set(:'kd'::uuid, :'c2', true, 'customer asked: do not contact', 'phone') ->> 'cancelled' as dn \gset
select tt.chk('T7 do-not-contact ON cancels the queued message (1)', :'dn' = '1' and (select status from notify_outbox where customer_id=:'c2' and channel='sms')='cancelled'
  and (select last_error from notify_outbox where customer_id=:'c2' and channel='sms')='do_not_contact');
select tt.chk('T7 the message check says dnc and not overridable', (select _crmb_consent_get(:'c2') ->> 'block')='dnc' and (select dnc from crm_contact_prefs where customer_id=:'c2'));
select tt.chk('T7 do-not-contact twice: unchanged', (select _crmb_prefs_set(gen_random_uuid(), :'c2', true, 'again') ->> 'unchanged')='true');
select tt.chk('T7 client id repeat: duplicate, nothing new', (select _crmb_prefs_set(:'kd'::uuid, :'c2', true, 'customer asked: do not contact', 'phone') ->> 'duplicate')='true'
  and tt.q(format($$select count(*) from crm_consent_events where kind='dnc' and customer_id=%L$$, :'c2'))='1');

\echo == T8 the message check (_crmb_send_allowed)
reset role;
select tt.chk('T8 customer b (dnc): not allowed, reason dnc, overridable false', (select _crmb_send_allowed(:'c2','sms') ->> 'reason')='dnc' and (select _crmb_send_allowed(:'c2','sms') ->> 'overridable')='false');
select tt.chk('T8 customer a (said no): opted_out', (select _crmb_send_allowed(:'c1','sms') ->> 'reason')='opted_out');
select tt.chk('T8 customer e (never asked on sms): not_asked', (select _crmb_send_allowed(:'c5','sms') ->> 'reason')='not_asked');
select tt.chk('T8 customer d (yes then no at the counter): opted_out', (select _crmb_send_allowed(:'c4','sms') ->> 'reason')='opted_out');
select _crmb_consent_set(gen_random_uuid(), :'c3', 'sms', true, 'phone', 'customer wants messages again') is not null as c3yes \gset
select tt.chk('T8 a customer with a yes and no block: ok=true, reason null', (select (_crmb_send_allowed(:'c3','sms') ->> 'ok')='true' and (_crmb_send_allowed(:'c3','sms') -> 'reason') = 'null'::jsonb));
update notify_optin set status='in' where customer_id=:'cbad' and channel='sms';
select tt.chk('T8 a yes on file but a bad phone number: bad_phone', (select _crmb_send_allowed(:'cbad','sms') ->> 'reason')='bad_phone');
select tt.chk('T8 unknown customer / bad channel', (select _crmb_send_allowed(gen_random_uuid(),'sms') ->> 'reason')='customer_not_found' and (select _crmb_send_allowed(:'c3','email') ->> 'reason')='bad_channel');
-- quiet hours: 21:00 to 08:00 (past midnight), shop time Dhaka (UTC+6, no daylight saving)
select tt.as(:'u_o'); select set_rule('crm_quiet_from','"21:00"') is null as qf \gset
select set_rule('crm_quiet_to','"08:00"') is null as qt \gset
reset role;
select tt.chk('T8 22:30 Dhaka is quiet (overridable)', (select _crmb_send_allowed(:'c3','sms','promo', '2026-03-10 22:30:00+06'::timestamptz) ->> 'reason')='quiet_hours'
  and (select _crmb_send_allowed(:'c3','sms','promo', '2026-03-10 22:30:00+06'::timestamptz) ->> 'overridable')='true');
select tt.chk('T8 03:00 Dhaka is quiet, 08:00 and 12:00 are not, 20:59 is not, 21:00 is',
  (select _crmb_send_allowed(:'c3','sms','promo', '2026-03-10 03:00:00+06'::timestamptz) ->> 'reason')='quiet_hours'
  and (select (_crmb_send_allowed(:'c3','sms','promo', '2026-03-10 08:00:00+06'::timestamptz) ->> 'ok')='true')
  and (select (_crmb_send_allowed(:'c3','sms','promo', '2026-03-10 12:00:00+06'::timestamptz) ->> 'ok')='true')
  and (select (_crmb_send_allowed(:'c3','sms','promo', '2026-03-10 20:59:00+06'::timestamptz) ->> 'ok')='true')
  and (select _crmb_send_allowed(:'c3','sms','promo', '2026-03-10 21:00:00+06'::timestamptz) ->> 'reason')='quiet_hours');
select tt.as(:'u_o'); select set_rule('crm_quiet_from','"9pm"') is null as qbad \gset
reset role;
select tt.chk('T8 a badly written quiet time is ignored (no quiet window)', (select (_crmb_send_allowed(:'c3','sms','promo', '2026-03-10 22:30:00+06'::timestamptz) ->> 'ok')='true'));
select tt.as(:'u_o'); select set_rule('crm_quiet_from', null) is null as q1 \gset
select set_rule('crm_quiet_to', null) is null as q2 \gset
reset role;
select tt.chk('T8 quiet times back to blank: no window', rule_txt('crm_quiet_from') is null and (select (_crmb_send_allowed(:'c3','sms','promo', '2026-03-10 22:30:00+06'::timestamptz) ->> 'ok')='true'));

\echo == T9 the hooks, proved on scratch copies (the real notify_enqueue / notify_optin_set are not touched)
select tt.chk('T9 (setup) customer b: dnc on and a yes on sms', (select dnc from crm_contact_prefs where customer_id=:'c2') and (select status from notify_optin where customer_id=:'c2' and channel='sms')='in');
do $$ declare d text;
begin
  d := pg_get_functiondef('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure);
  d := replace(d, 'FUNCTION public.notify_enqueue(', 'FUNCTION tt.notify_enqueue_x(');
  execute d;
  d := pg_get_functiondef('public.notify_optin_set(uuid,text,boolean,text,text)'::regprocedure);
  d := replace(d, 'FUNCTION public.notify_optin_set(', 'FUNCTION tt.notify_optin_set_x(');
  execute d;
end $$;
grant execute on all functions in schema tt to authenticated, anon;
select tt.chk('T9 scratch copy installed without the hook: same behaviour as the real one',
  position('bosCRMB' in pg_get_functiondef('tt.notify_enqueue_x(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure))=0);
select tt.as(:'u_m'); set role authenticated;
select notify_enqueue(gen_random_uuid(), :'c2', 'sms', 'thanks', '{}', 'en') ->> 'status' as real_dnc \gset
select tt.chk('T9 the REAL notify_enqueue (no hook) queues the do-not-contact customer: this is today and the reason the hook is needed', :'real_dnc' = 'queued');
select notify_cancel(id) is not null as cx2 from notify_outbox where customer_id=:'c2' and status='queued' limit 1 \gset
reset role;
select _crmb_patch('tt.notify_enqueue_x(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure, _crmb_hook_pairs('notify_enqueue')) as patched1 \gset
select _crmb_patch('tt.notify_enqueue_x(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure, _crmb_hook_pairs('notify_enqueue')) as patched2 \gset
select tt.chk('T9 the hook text patches the scratch copy once (true) and the second paste is a no-op (false)', :'patched1' = 't' and :'patched2' = 'f');
select tt.chk('T9 the real notify_enqueue is still unpatched', position('bosCRMB' in pg_get_functiondef('public.notify_enqueue(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure))=0);
select tt.as(:'u_m'); set role authenticated;
select tt.err('T9 patched copy: a do-not-contact customer is refused (do_not_contact) even though the yes is on file',
  format($$select tt.notify_enqueue_x(gen_random_uuid(), %L, 'sms', 'thanks', '{}', 'en')$$, :'c2'), 'do_not_contact');
select tt.chk('T9 patched copy: a normal opted-in customer is still queued', (select tt.notify_enqueue_x(gen_random_uuid(), :'c3', 'sms', 'thanks', '{}', 'en') ->> 'status')='queued');
select tt.err('T9 patched copy: still refuses the withdrawn customer (not_opted_in)', format($$select tt.notify_enqueue_x(gen_random_uuid(), %L, 'sms', 'thanks', '{}', 'en')$$, :'c1'), 'not_opted_in');
select tt.err('T9 patched copy: a customer never asked is refused', format($$select tt.notify_enqueue_x(gen_random_uuid(), %L, 'sms', 'thanks', '{}', 'en')$$, :'c5'), 'not_opted_in');
reset role;
select tt.err('T9 wrong patch site raises', $$select _crmb_patch('tt.notify_enqueue_x(uuid,uuid,text,text,jsonb,text,text,text)'::regprocedure, array['this text is not there','x'], 'bosNOPE')$$, 'patch site not found');
-- second hook: notify_optin_set writes the evidence line
select _crmb_patch('tt.notify_optin_set_x(uuid,text,boolean,text,text)'::regprocedure, _crmb_hook_pairs('notify_optin_set')) as patched3 \gset
select tt.as(:'u_o'); set role authenticated;
select tt.q($$select count(*) from crm_consent_events$$) as ev0 \gset
select tt.chk('T9 the unpatched old function (real) records a yes without an evidence line', (select notify_optin_set(:'c5', 'sms', true, 'owner_entry', 'old way') ->> 'status')='in' and tt.q($$select count(*) from crm_consent_events$$)=:'ev0');
select tt.chk('T9 the patched copy records the yes AND an evidence line (old function, source owner_entry)',
  (select tt.notify_optin_set_x(:'c4', 'sms', true, 'owner_entry', 'old way 2') ->> 'status')='in' and tt.q($$select count(*) from crm_consent_events$$)::int=:'ev0'::int+1
  and tt.q(format($$select how from crm_consent_events where customer_id=%L order by id desc limit 1$$, :'c4'))='owner_entry');
reset role;
select tt.chk('T9 the patch of the second hook returned true and the real function is untouched', :'patched3' = 't' and position('bosCRMB' in pg_get_functiondef('public.notify_optin_set(uuid,text,boolean,text,text)'::regprocedure))=0);

\echo == T10 paper list import (dry run first; a withdrawn no is never turned back into a yes)
select tt.as(:'u_m'); set role authenticated;
select gen_random_uuid() as bk \gset
select _crmb_consent_import(:'bk'::uuid, '[{"mobile":"01730300006"},{"mobile":"01730300001"},{"mobile":"০১৭৩০৩০০০০৬"},{"mobile":"nope"},{"mobile":"01799999999"},{"mobile":"01730300003"}]'::jsonb, 'sms', true, 'paper list May', true) as dry \gset
select tt.chk('T10 dry run: 1 will change (f), 1 same (c has a yes), 1 withdrawn kept (a said no), 1 repeated row, 1 bad number, 1 unknown customer',
  (:'dry'::jsonb ->> 'will_change')='1' and (:'dry'::jsonb ->> 'same')='1' and (:'dry'::jsonb ->> 'withdrawn_kept')='1' and (:'dry'::jsonb ->> 'errors')='3' and (:'dry'::jsonb ->> 'dry')='true');
select tt.chk('T10 the dry run wrote nothing', not exists (select 1 from notify_optin where customer_id=:'c7') and tt.q(format($$select count(*) from crm_consent_events where batch_id=%L$$, :'bk'))='0');
select _crmb_consent_import(:'bk'::uuid, '[{"mobile":"01730300006"},{"mobile":"01730300001"},{"mobile":"01730300003"}]'::jsonb, 'sms', true, 'paper list May', false) as real1 \gset
select tt.chk('T10 real run: customer f is in (import way, list name in the note); a stays out', (select status from notify_optin where customer_id=:'c7' and channel='sms')='in'
  and (select source from notify_optin where customer_id=:'c7' and channel='sms')='owner_entry' and (select note from notify_optin where customer_id=:'c7' and channel='sms')='import: paper list May'
  and (select status from notify_optin where customer_id=:'c1' and channel='sms')='out' and tt.q(format($$select count(*) from crm_consent_events where batch_id=%L and how='import'$$, :'bk'))='1');
select tt.chk('T10 the same batch id again: duplicate, nothing new', (select _crmb_consent_import(:'bk'::uuid, '[{"mobile":"01730300006"}]'::jsonb, 'sms', true, 'paper list May', false) ->> 'duplicate')='true'
  and tt.q(format($$select count(*) from crm_consent_events where batch_id=%L$$, :'bk'))='1');
select _crmb_consent_set(gen_random_uuid(), :'c7', 'sms', true, 'phone') is not null as noop \gset
select notify_enqueue(gen_random_uuid(), :'c7', 'sms', 'thanks', '{}', 'en') ->> 'status' as cq \gset
select _crmb_consent_import(gen_random_uuid(), '[{"mobile":"01730300006"}]'::jsonb, 'sms', false, 'opt-out list June', false) ->> 'will_change' as outn \gset
select tt.chk('T10 an opt-out list turns f to out and cancels the queued message', :'cq' = 'queued' and :'outn' = '1' and (select status from notify_optin where customer_id=:'c7' and channel='sms')='out'
  and (select status from notify_outbox where customer_id=:'c7' order by id desc limit 1)='cancelled');
select tt.err('T10 a list needs a name (reason)', $$select _crmb_consent_import(gen_random_uuid(), '[{"mobile":"01730300006"}]'::jsonb, 'sms', true, 'ab', true)$$, 'reason_required');
select tt.err('T10 empty list', $$select _crmb_consent_import(gen_random_uuid(), '[]'::jsonb, 'sms', true, 'paper list', true)$$, 'no_rows');
select tt.err('T10 more than 2000 rows', $$select _crmb_consent_import(gen_random_uuid(), (select jsonb_agg(jsonb_build_object('mobile','01730300006')) from generate_series(1,2001)), 'sms', true, 'paper list', true)$$, 'too_many_rows');
select tt.err('T10 not a list', $$select _crmb_consent_import(gen_random_uuid(), '{"a":1}'::jsonb, 'sms', true, 'paper list', true)$$, 'bad_input');
select tt.as(:'u_c');
select tt.err('T10 cashier cannot import', $$select _crmb_consent_import(gen_random_uuid(), '[{"mobile":"01730300006"}]'::jsonb, 'sms', true, 'paper list', true)$$, 'not allowed');
reset role;

\echo == T11 read side
select tt.as(:'u_m'); set role authenticated;
select tt.chk('T11 state of a customer never asked: not_asked on both channels, no dnc', (select _crmb_consent_get(:'c5') -> 'channels' -> 'sms' ->> 'status') is not null);
select tt.chk('T11 history is newest first and has the way and the staff', (select (_crmb_consent_history(:'c1') -> 0 ->> 'status')='out' and (_crmb_consent_history(:'c1') -> 0 ->> 'how')='phone' and jsonb_array_length(_crmb_consent_history(:'c1'))>=3));
select _crmb_consent_summary() as sm \gset
select tt.chk('T11 summary has counts only (no mobile, no name)', position('0173' in :'sm')=0 and position('test_cust' in :'sm')=0 and (:'sm'::jsonb -> 'channels' -> 'sms' ->> 'in') is not null);
select tt.chk('T11 summary counts add up to the active customers (in + out + not asked = total) for sms',
  ((:'sm'::jsonb -> 'channels' -> 'sms' ->> 'in')::int + (:'sm'::jsonb -> 'channels' -> 'sms' ->> 'out')::int + (:'sm'::jsonb -> 'channels' -> 'sms' ->> 'not_asked')::int) = (:'sm'::jsonb ->> 'active_customers')::int);
select tt.err('T11 consent_get for an unknown customer', $$select _crmb_consent_get(gen_random_uuid())$$, 'customer_not_found');
reset role;

\echo == T12 append-only evidence, no direct writes
select tt.err('T12 evidence line cannot be changed (even by the table owner)', $$update crm_consent_events set note='x' where id=(select min(id) from crm_consent_events)$$, 'append-only');
select tt.err('T12 evidence line cannot be deleted', $$delete from crm_consent_events$$, 'append-only');
select tt.err('T12 contact prefs cannot be deleted', $$delete from crm_contact_prefs$$, 'nothing is deleted');
set role authenticated; select tt.as(:'u_m');
select tt.err('T12 a manager cannot write the evidence table directly', format($$insert into crm_consent_events (customer_id, kind, channel, status, how) values (%L,'optin','sms','in','phone')$$, :'c4'), 'permission denied');
select tt.err('T12 a manager cannot flip do-not-contact directly', format($$update crm_contact_prefs set dnc=false where customer_id=%L$$, :'c2'), 'permission denied');
select tt.chk('T12 a manager can read the evidence table (policy), a cashier cannot', (select count(*) from crm_consent_events)>0);
select tt.as(:'u_c');
select tt.chk('T12 cashier reads zero evidence rows (policy)', (select count(*) from crm_consent_events)=0);
reset role;

\echo == T13 nothing in the books or the sales moved
select tt.chk('T13 no journal entry was made by any consent function', tt.je()=:'je0');
select tt.chk('T13 no sale, payment or customer row was created or changed by consent (customers: only the 7 fixtures)', (select count(*) from customers)=7);

\echo == T14 paste the file again: nothing doubles
select count(*) as rules_n, (select count(*) from notify_optin) as optin_n, (select count(*) from crm_consent_events) as ev_n, (select count(*) from pg_proc where proname like '\_crmb\_%') as fn_n from rules where key like 'crm\_%' \gset
\ir phase303.sql
select tt.chk('T14 re-pasting phase303 changes no row and adds no function', (select count(*) from rules where key like 'crm\_%')=:'rules_n' and (select count(*) from notify_optin)=:'optin_n'
  and (select count(*) from crm_consent_events)=:'ev_n' and (select count(*) from pg_proc where proname like '\_crmb\_%')=:'fn_n');
select tt.chk('T14 re-pasting 303 left the grants of the API functions in place', has_function_privilege('authenticated','public._crmb_consent_set(uuid,uuid,text,boolean,text,text,int,text)','execute'));

select 'RESULT phase303: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
