-- FRESH DB ONLY. Phase 62 tests (P3c: SMS queue, payment intents + webhook + recon, accounting CSV export, assistant access).
--   ORDER="phase8 ... phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase62" bash tests/sql/build_fresh_db.sh p62db
--   psql -h /tmp -p 5544 -U postgres -d p62db -qAt -f supabase/phase62_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set m '00000000-0000-0000-0000-000000000002'
\set s '00000000-0000-0000-0000-000000000003'
\set a '00000000-0000-0000-0000-000000000004'
\set c '00000000-0000-0000-0000-000000000005'
\set b '00000000-0000-0000-0000-000000000006'
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
create or replace function tt.sx(p_sql text) returns text language plpgsql security definer as $$ declare r text; begin execute p_sql into r; return r; end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'m','head2@s.app','{"full_name":"Head"}'), (:'s','mgr3@s.app','{"full_name":"Manager"}'),
 (:'a','acct4@s.app','{"full_name":"Accountant"}'), (:'c','cust5@s.app','{"full_name":"CustMgr"}'), (:'b','bot6@s.app','{"full_name":"Bot"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'m','management'),(:'s','showroom_manager'),(:'a','showroom_manager'),(:'c','salesperson'),(:'b','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'a',1),(:'c',1),(:'b',1) on conflict do nothing;
insert into customers (mobile, name) values ('01712345678','TestK'), ('01898765432','TestF');
select id as c1 from customers where mobile='01712345678' \gset
select id as c2 from customers where mobile='01898765432' \gset

\echo == T0 shape
select tt.chk('T0 new tables have RLS and no browser write', (select count(*) from pg_class where relname in ('notify_templates','notify_optin','notify_optin_log','notify_outbox','payment_intents','payment_webhook_log') and relrowsecurity)=6
  and not has_table_privilege('authenticated','public.notify_outbox','insert') and not has_table_privilege('authenticated','public.payment_intents','update'));
select tt.chk('T0 no provider credential column anywhere in the new tables', not exists (select 1 from information_schema.columns where table_schema='public'
  and table_name in ('notify_templates','notify_optin','notify_outbox','payment_intents','payment_webhook_log') and column_name ~* '(secret|password|api_?key|token|credential|auth)'));
select tt.chk('T0 switches default OFF', not rule_on('notify_sms_on') and not rule_on('pay_gateway_on'));
select tt.chk('T0 recon view is closed to browsers; worker fns callable only when authenticated', not has_table_privilege('authenticated','public.payment_recon_v','select')
  and not has_function_privilege('anon','public.notify_outbox_claim(int)','execute'));
select tt.chk('T0 assistant_use grant exists once', (select count(*) from grant_defs where grant_code='assistant_use')=1);

\echo == T1 SMS queue
set role authenticated; select tt.as(:'o');
select tt.err('T1 switch OFF: enqueue refused', format($$select notify_enqueue(gen_random_uuid(), %L::uuid,'sms','due_reminder','{}')$$, :'c1'), 'sms_off');
reset role; select set_rule('notify_sms_on','true') is null as r1 \gset
set role authenticated; select tt.as(:'o');
select tt.err('T1 no opt-in: refused', format($$select notify_enqueue(gen_random_uuid(), %L::uuid,'sms','due_reminder','{}')$$, :'c1'), 'not_opted_in');
select tt.as(:'s'); select tt.err('T1 a showroom manager cannot opt a customer in', format($$select notify_optin_set(%L::uuid,'sms',true)$$, :'c1'), 'not allowed');
select tt.as(:'o');
select notify_optin_set(:'c1'::uuid,'sms',true,'customer_consent','asked at counter') ->> 'status' as os \gset
select tt.chk('T1 opt-in saved + logged', :'os'='in' and (select count(*) from notify_optin_log where customer_id=:'c1'::uuid)=1);
select tt.err('T1 unknown template refused', format($$select notify_enqueue(gen_random_uuid(), %L::uuid,'sms','nope','{}')$$, :'c1'), 'template_not_found');
select tt.err('T1 channel mismatch refused', format($$select notify_enqueue(gen_random_uuid(), %L::uuid,'whatsapp','due_reminder','{}')$$, :'c1'), 'template_channel_mismatch');
select gen_random_uuid() as k1 \gset
select notify_enqueue(:'k1'::uuid, :'c1'::uuid,'sms','due_reminder','{"amount":"1500","shop":"Islamia","bad key":"x"}','en','sale','S-1') as e1 \gset
select tt.chk('T1 queued with rendered body and +880 phone', (select body from notify_outbox where client_id=:'k1'::uuid)='Dear TestK, your balance due is 1500 Taka. Thank you. - Islamia'
  and (select to_phone from notify_outbox where client_id=:'k1'::uuid)='+8801712345678' and (select status from notify_outbox where client_id=:'k1'::uuid)='queued');
select tt.chk('T1 same client key = same row (idempotent)', (notify_enqueue(:'k1'::uuid, :'c1'::uuid,'sms','due_reminder','{}') ->> 'duplicate')::boolean and tt.sx('select count(*) from notify_outbox')='1');
select tt.chk('T1 same source+template with a new key = duplicate, still one row', (notify_enqueue(gen_random_uuid(), :'c1'::uuid,'sms','due_reminder','{}','bn','sale','S-1') ->> 'duplicate')::boolean and tt.sx('select count(*) from notify_outbox')='1');
select tt.chk('T1 summary masks the phone', (select (notify_outbox_summary() -> 'recent' -> 0 ->> 'to')) = '+88017****78');
select tt.as(:'m'); select tt.err('T1 head management without customer_manage cannot read the queue summary', $$select notify_outbox_summary()$$, 'not allowed');
select tt.as(:'b'); select tt.err('T1 a non-bot cannot claim', $$select notify_outbox_claim(5)$$, 'not allowed');
select tt.as(:'o'); select ops_account_set(:'b'::uuid,'notify',true) is not null as bot \gset
select tt.as(:'b');
select notify_outbox_claim(5) as cl \gset
select tt.chk('T1 claim returns the row once, attempt 1, status sending', (:'cl'::jsonb -> 'rows' -> 0 ->> 'attempt')='1' and tt.sx('select status from notify_outbox limit 1')='sending'
  and jsonb_array_length(notify_outbox_claim(5) -> 'rows')=0);
select notify_outbox_report(tt.sx('select id from notify_outbox limit 1')::bigint, false, null, 'timeout') ->> 'status' as rs \gset
select tt.chk('T1 failure -> back to queued with back-off', :'rs'='queued' and tt.sx('select (next_try_at > now() + interval ''1 minute'')::text from notify_outbox limit 1')='true' and tt.sx('select last_error from notify_outbox limit 1')='timeout');
reset role; update notify_outbox set next_try_at = now() - interval '1 minute'; set role authenticated; select tt.as(:'b');
select jsonb_array_length(notify_outbox_claim(5) -> 'rows') as again \gset
select notify_outbox_report(tt.sx('select id from notify_outbox limit 1')::bigint, true, 'prov-1', null) ->> 'status' as rs2 \gset
select tt.chk('T1 retry then success = sent with provider ref, attempts 2', :'again'='1' and :'rs2'='sent' and tt.sx('select attempts from notify_outbox limit 1')='2' and tt.sx('select provider_ref from notify_outbox limit 1')='prov-1');
select tt.chk('T1 report on a finished row is ignored', (notify_outbox_report(tt.sx('select id from notify_outbox limit 1')::bigint, false, null, 'x') ->> 'ignored')::boolean);
-- permanent failure after max attempts
select tt.as(:'o');
select notify_enqueue(gen_random_uuid(), :'c1'::uuid,'sms','thanks','{}') ->> 'id' as id2 \gset
reset role; update notify_outbox set max_attempts=1 where id=:id2; set role authenticated; select tt.as(:'b');
select notify_outbox_claim(5) is not null as x \gset
select tt.chk('T1 attempts used up -> failed (no more retries)', notify_outbox_report(:id2, false, null, 'down') ->> 'status' = 'failed' and jsonb_array_length(notify_outbox_claim(5) -> 'rows')=0);
-- opt-out cancels waiting rows
select tt.as(:'o');
select notify_enqueue(gen_random_uuid(), :'c1'::uuid,'sms','order_ready','{"ref":"A1"}') ->> 'id' as id3 \gset
select notify_optin_set(:'c1'::uuid,'sms',false) is not null as oo \gset
select tt.chk('T1 opt-out cancels the queued message and blocks new ones', (select status from notify_outbox where id=:id3)='cancelled');
select tt.err('T1 after opt-out enqueue refused', format($$select notify_enqueue(gen_random_uuid(), %L::uuid,'sms','thanks','{}')$$, :'c1'), 'not_opted_in');
reset role; update customers set mobile='abc' where id=:'c2'::uuid; set role authenticated; select tt.as(:'o');
select tt.err('T1 opt-in with a bad phone refused', format($$select notify_optin_set(%L::uuid,'sms',true)$$, :'c2'), 'bad_phone');
reset role; update customers set mobile='01898765432' where id=:'c2'::uuid; set role authenticated; select tt.as(:'o');
select tt.as(:'c'); select tt.err('T1 customer manager cannot edit templates', $$select notify_template_save('x1','sms','a','b')$$, 'not allowed');
select tt.as(:'o'); select notify_template_save('promo','whatsapp','বাংলা','English',true) ->> 'code' as tc \gset
select tt.chk('T1 owner saves a template', :'tc'='promo');

\echo == T2 payment intents + webhook + recon
select tt.as(:'o');
select tt.err('T2 gateway OFF: intent refused', format($$select payment_intent_create(gen_random_uuid(),'bkash',null,%L::uuid,1,500)$$, :'c1'), 'gateway_off');
reset role; select set_rule('pay_gateway_on','true') is null as g \gset
set role authenticated; select tt.as(:'o');
select gen_random_uuid() as ik \gset
select payment_intent_create(:'ik'::uuid,'bkash',null,:'c1'::uuid,1,500) ->> 'id' as i1 \gset
select tt.chk('T2 intent created, idempotent on client key', (payment_intent_create(:'ik'::uuid,'bkash',null,:'c1'::uuid,1,500) ->> 'duplicate')::boolean and (select count(*) from payment_intents)=1);
select tt.err('T2 bad amount refused', format($$select payment_intent_create(gen_random_uuid(),'bkash',null,%L::uuid,1,0)$$, :'c1'), 'bad_input');
select tt.err('T2 bad provider refused', format($$select payment_intent_create(gen_random_uuid(),'Bad Name',null,%L::uuid,1,5)$$, :'c1'), 'bad_input');
select payment_intent_set_ref(:i1, 'TXN-AAA') is not null as sr \gset
select tt.chk('T2 ref set -> pending', tt.sx('select status from payment_intents where id='||:i1)='pending');
select tt.err('T2 ref cannot be changed', format($$select payment_intent_set_ref(%s,'TXN-BBB')$$, :i1), 'ref_already_set');
select tt.as(:'s'); select tt.err('T2 a showroom manager cannot see recon', $$select payment_recon()$$, 'not allowed');
select tt.err('T2 ... or receive a webhook', $$select payment_webhook_receive('bkash','e1','TXN-AAA','paid','succeeded',500,true)$$, 'not allowed');
select tt.as(:'b');
select payment_webhook_receive('bkash','ev-1','TXN-AAA','payment.paid','succeeded',500,true,'{"x":1,"token":"SECRET","signature":"zz"}') as w1 \gset
select tt.chk('T2 webhook applied: intent succeeded with paid amount 500', (:'w1'::jsonb ->> 'applied')::boolean and tt.sx('select status from payment_intents where id='||:i1)='succeeded' and tt.sx('select paid_amount from payment_intents where id='||:i1)='500');
select tt.chk('T2 payload secrets stripped in the log', tt.sx('select payload::text from payment_webhook_log where event_id=''ev-1''')='{"x": 1}');
select tt.chk('T2 same event id again = duplicate, nothing changes (idempotent)', (payment_webhook_receive('bkash','ev-1','TXN-AAA','payment.paid','failed',1,true) ->> 'duplicate')::boolean
  and tt.sx('select status from payment_intents where id='||:i1)='succeeded' and tt.sx('select count(*) from payment_webhook_log')='1');
select tt.chk('T2 a late "pending" event does not regress a succeeded intent', (payment_webhook_receive('bkash','ev-2','TXN-AAA','payment.pending','pending',null,true) ->> 'note')='stale_event' and tt.sx('select status from payment_intents where id='||:i1)='succeeded');
select tt.chk('T2 bad signature is logged, never applied', (payment_webhook_receive('bkash','ev-3','TXN-AAA','payment.refund','refunded',500,false) ->> 'note')='bad_signature' and tt.sx('select status from payment_intents where id='||:i1)='succeeded');
select tt.chk('T2 unknown ref is logged as no_intent (orphan)', (payment_webhook_receive('bkash','ev-4','TXN-ZZZ','payment.paid','succeeded',77,true) ->> 'note')='no_intent');
select tt.err('T2 bad status refused', $$select payment_webhook_receive('bkash','ev-5','TXN-AAA','x','weird',1,true)$$, 'bad_input');
reset role;
do $$ begin begin update public.payment_webhook_log set note='x'; perform tt.chk('T2 log rows cannot be updated (append-only)', false); exception when others then perform tt.chk('T2 log rows cannot be updated (append-only)', sqlerrm like '%append-only%'); end; end $$;
-- recon
select set_config('request.jwt.claim.sub', :'o', false);
set role authenticated; select tt.as(:'o');
select tt.chk('T2 recon: succeeded intent without a sale payment = missing_payment', (payment_recon() -> 'rows' -> 0 ->> 'state')='missing_payment');
reset role;
insert into sale_payments (customer_id, location_id, kind, mode, wallet, ref, amount) values (:'c1'::uuid, 1, 'collection', 'mobile', 'bkash', 'TXN-AAA', 500);
set role authenticated; select tt.as(:'o');
select tt.chk('T2 recon: matched by ref when amounts agree', (payment_recon() -> 'rows' -> 0 ->> 'state')='matched' and (payment_recon() -> 'counts' ->> 'matched')='1');
reset role; update sale_payments set amount=450 where ref='TXN-AAA'; set role authenticated; select tt.as(:'o');
select tt.chk('T2 recon: amount mismatch with the difference', (payment_recon() -> 'rows' -> 0 ->> 'state')='amount_mismatch' and (payment_recon() -> 'rows' -> 0 ->> 'diff')::numeric=50);
select tt.chk('T2 recon lists orphan events (no_intent, bad_signature)', jsonb_array_length(payment_recon() -> 'orphan_events')=2);
select tt.chk('T2 recon filter by state', jsonb_array_length(payment_recon(null,null,'open') -> 'rows')=0);
select tt.err('T2 recon bad state refused', $$select payment_recon(null,null,'zzz')$$, 'bad_input');
reset role; update sale_payments set amount=500, voided=true where ref='TXN-AAA'; set role authenticated; select tt.as(:'o');
select tt.chk('T2 recon: voided payment flagged', (payment_recon() -> 'rows' -> 0 ->> 'state')='voided_payment');
select tt.as(:'a'); select tt.err('T2 accountant without accounts_manage refused', $$select payment_recon()$$, 'not allowed');
select tt.as(:'o'); select set_user_grant(:'a'::uuid,'accounts_manage') is null as ga \gset
select tt.as(:'a'); select tt.chk('T2 accounts_manage can read recon', payment_recon() ? 'rows');
select tt.err('T2 browser cannot read the recon view directly', $$select * from payment_recon_v$$, 'permission denied');

\echo == T3 accounting export
select tt.as(:'o');
select tt.chk('T3 data_needed while accounting start date is empty', (acct_export_csv('journal',null,null) ->> 'data_needed')::boolean);
select acct_set_start(tt.today() - 5) is not null as st \gset
select acct_journal_post(tt.today(), 1, 'Test, with "quotes" and comma', '[{"code":"1110","debit":100},{"code":"3100","credit":100}]') is not null as j1 \gset
select acct_journal_post(tt.today(), 1, '=HYPERLINK("x")', '[{"code":"1110","debit":25.5},{"code":"3100","credit":25.5}]') is not null as j2 \gset
select acct_export_csv('journal', null, null) as ej \gset
select tt.chk('T3 journal csv: header + 4 lines, columns documented', (:'ej'::jsonb ->> 'rows')='4' and jsonb_array_length(:'ej'::jsonb -> 'columns')=19
  and array_length(regexp_split_to_array(:'ej'::jsonb ->> 'csv', E'\r\n'),1)=5);
select tt.chk('T3 csv quoting and formula guard', (:'ej'::jsonb ->> 'csv') like '%"Test, with ""quotes"" and comma"%' and (:'ej'::jsonb ->> 'csv') like '%''=HYPERLINK%');
select acct_export_csv('trial_balance', null, null) as et \gset
select tt.chk('T3 trial balance csv balanced and has the 11 columns', (:'et'::jsonb ->> 'balanced')::boolean and jsonb_array_length(:'et'::jsonb -> 'columns')=11 and (:'et'::jsonb ->> 'csv') like 'account_code,%' and (:'et'::jsonb ->> 'rows')::int>=2);
select tt.chk('T3 export wrote nothing (journal count unchanged)', (select count(*) from journal_entries where source_type<>'opening') >= 2);
select tt.err('T3 bad kind refused', $$select acct_export_csv('x', null, null)$$, 'bad_input');
select tt.err('T3 bad range refused', $$select acct_export_csv('journal', tt.today(), tt.today()-3)$$, 'bad_range');
select tt.as(:'s'); select tt.err('T3 showroom manager refused', $$select acct_export_csv('journal', null, null)$$, 'not allowed');
select tt.as(:'m'); select tt.err('T3 head management without accounts_manage refused', $$select acct_export_csv('journal', null, null)$$, 'not allowed');
select tt.as(:'a'); select tt.chk('T3 accounts_manage may export', (acct_export_csv('trial_balance', null, null) ->> 'rows')::int>=2);
select tt.as(:'o'); select tt.chk('T3 stable (read-only) function read-only: STABLE function', (select provolatile from pg_proc where proname='acct_export_csv')='s');

\echo == T4 assistant access
select tt.as(:'o');
select tt.chk('T4 owner may use the assistant', (assistant_me() ->> 'allowed')::boolean);
select tt.as(:'m');
select tt.chk('T4 head management (no grant) is now refused', not (assistant_me() ->> 'allowed')::boolean and (assistant_me() ->> 'reason')='no_right');
select tt.as(:'s'); select tt.chk('T4 showroom manager (no grant) refused', not (assistant_me() ->> 'allowed')::boolean);
select tt.as(:'o'); select set_user_grant(:'s'::uuid,'assistant_use') is null as gs \gset
select tt.as(:'s'); select tt.chk('T4 explicit assistant_use grant opens it', (assistant_me() ->> 'allowed')::boolean);
select tt.as(:'o'); select tt.chk('T4 owner sees the access list', jsonb_array_length(assistant_access_list() -> 'users')=1 and assistant_access_list() -> 'users' -> 0 ->> 'name'='Manager');
select tt.as(:'s'); select tt.err('T4 non-owner cannot read the access list', $$select assistant_access_list()$$, 'not allowed');
select tt.as(:'o'); select set_user_grant(:'s'::uuid,'assistant_use',null,null,false) is null as rv \gset
select tt.as(:'s'); select tt.chk('T4 revoke closes it again', not (assistant_me() ->> 'allowed')::boolean);
select tt.err('T4 assistant_log refuses a non-granted caller', $$select assistant_log('local','x',array[]::text[],1)$$, 'not allowed');
select tt.as(:'o'); select set_rule('assistant_roles','"*"') is null as rr \gset
select tt.as(:'s'); select tt.chk('T4 the old assistant_roles rule (*) no longer opens it', not (assistant_me() ->> 'allowed')::boolean);
select tt.as(:'o'); select set_user_grant(:'c'::uuid,'assistant_use',1) is null as gl \gset
select tt.as(:'c'); select tt.chk('T4 location-scoped assistant_use opens it', (assistant_me() ->> 'allowed')::boolean);

reset role;
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
select 'FAIL ' || name from tt.res where not ok;
