-- COPY of phase94_test.sql for the chain with phase114 + phase115 (BATCH 2): a re-paste of an older phase puts the older body of functions that 114/115 patch back, so this copy pastes 114/115 again after it (re-paste rule, docs/PASTE_ORDER.md section N). Assertions otherwise as in phase94_test.sql.
-- FRESH DB ONLY. Phase 94 tests (STEP Sec: findings of the security review of phases 72-93).
--   Build: bash tests/sql/final_build.sh <db>  (canonical order incl. 90-93, 95 and phase94 last, docs/PASTE_ORDER.md).
--   Run (repo root; the M6 block pastes supabase/phase94.sql a second time):
--     psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase94_test.sql | grep -E "FAIL|RESULT"
--   FAILING-BEFORE: on a build WITHOUT phase94 (final_build.sh <db> "<order without phase94>") every block below fails (missing function / rule / old behaviour);
--   PASSING-AFTER: on the full build 0 fail. Test data only, no real names. Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set u '00000000-0000-0000-0000-000000000002'
\set x '00000000-0000-0000-0000-000000000003'
\set c '00000000-0000-0000-0000-000000000004'
\set k '00000000-0000-0000-0000-000000000005'
\set k2 '00000000-0000-0000-0000-000000000006'
\set m '00000000-0000-0000-0000-000000000007'
\set b '00000000-0000-0000-0000-000000000008'
\set w '00000000-0000-0000-0000-000000000009'
\set a '00000000-0000-0000-0000-00000000000a'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'u','store2@s.app','{"full_name":"Uploader"}'), (:'x','store3@s.app','{"full_name":"Reviewer no cost"}'),
 (:'c','store4@s.app','{"full_name":"Reviewer with cost"}'), (:'k','sales5@s.app','{"full_name":"Seller"}'), (:'k2','sales6@s.app','{"full_name":"Other Seller"}'),
 (:'m','mgr7@s.app','{"full_name":"Manager"}'), (:'b','bot8@s.app','{"full_name":"Intake bot"}'), (:'w','store9@s.app','{"full_name":"Other place"}'),
 (:'a','acct10@s.app','{"full_name":"Accountant"}') on conflict do nothing;
update profiles set status='active';
update profiles set staff_id = 'OWN1' where id = :'o';
insert into user_roles values (:'o','owner'),(:'u','storekeeper'),(:'x','storekeeper'),(:'c','storekeeper'),(:'k','salesperson'),(:'k2','salesperson'),(:'m','showroom_manager'),
  (:'b','salesperson'),(:'w','storekeeper'),(:'a','salesperson') on conflict do nothing;
insert into user_locations values (:'u',1),(:'x',1),(:'c',1),(:'k',1),(:'k2',1),(:'m',1),(:'b',1),(:'w',2),(:'a',1) on conflict do nothing;
select tt.as(:'o');
select set_rule('scan_enabled','true') is null as sr \gset
select set_user_grant(:'x'::uuid,'scan_confirm') is null as g1 \gset
select set_user_grant(:'c'::uuid,'scan_confirm') is null as g2 \gset
select set_user_grant(:'c'::uuid,'view_cost') is null as g3 \gset
select set_user_grant(:'a'::uuid,'accounts_view') is null as g4 \gset
select intake_bot_set(:'b'::uuid, true) is not null as bt \gset
select set_rule('inbox_on','true') is null as r1 \gset
select set_rule('meta_intake_on','true') is null as r2 \gset
select set_rule('web_form_on','true') is null as r3 \gset
select set_rule('online_orders_on','true') is null as r3b \gset
select set_rule('web_form_rate_max','0') is null as r3c \gset

\echo == T0 shape: new objects, defaults = today's behaviour, tags kept, signatures
select tt.chk('T0 new functions exist and are open to signed-in users only',
  (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('intake_proof_set94','intake_proof_status94','intake_purge','scan_ai_gate94','pii_exposure_report94','anon_exec_audit94','acct_autopost_runs_list'))=7
  and not has_function_privilege('anon','public.intake_purge(int)','execute') and has_function_privilege('authenticated','public.intake_purge(int)','execute')
  and not has_function_privilege('authenticated','public._intake_proof_ok94(text,text)','execute') and not has_function_privilege('anon','public.scan_ai_gate94(uuid)','execute'));
select tt.chk('T0 every new limit / switch is empty or off by default (today''s behaviour)',
  (select count(*) from rules where key in ('scan_ai_max_per_job','scan_ai_max_per_user_day','offline_sale_max_age','inbox_rate_max_per_min','intake_reject_max_per_min') and default_value is null and value is null)=5
  and (select default_value from rules where key='invoice_own_sales_only')='false'::jsonb and not rule_on('invoice_own_sales_only')
  and rule_num('scan_ai_max_per_job') is null and rule_num('offline_sale_max_age') is null);
select tt.chk('T0 the new rules have text in all three languages',
  (select bool_and(label_bn is not null and label_mix is not null and label_en is not null and hint_en is not null) from rules where key in ('scan_ai_max_per_job','scan_ai_max_per_user_day','offline_sale_max_age','inbox_rate_max_per_min','intake_reject_max_per_min','invoice_own_sales_only')));
select tt.chk('T0 English texts of the new rules have no Bangla letters',
  (select bool_and(coalesce(label_en,'') !~ '[ঀ-৿]' and coalesce(hint_en,'') !~ '[ঀ-৿]') from rules where key in ('scan_ai_max_per_job','scan_ai_max_per_user_day','offline_sale_max_age','inbox_rate_max_per_min','intake_reject_max_per_min','invoice_own_sales_only')));
select tt.chk('T0 bos94 tag in every re-created function, older tags kept',
  (select bool_and(position('bos94' in pg_get_functiondef(p.oid)) > 0) from pg_proc p where pronamespace='public'::regnamespace and proname in ('_scan_photo_ok','scan_get','_sale_stock_out','_intake_fail','_inb_insert_message','invoice_data92','invoice_share_log92','inbound_message_receive','web_order_submit'))
  and (select bool_and(position(t in pg_get_functiondef('public._sale_stock_out()'::regprocedure)) > 0) from unnest(array['bos82','bos83','bos89','bos94']) t));
select tt.chk('T0 the old 9-argument inbound_message_receive and 13-argument web_order_submit are gone (one signature each, the new argument has a default)',
  (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='inbound_message_receive')=1 and (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname='web_order_submit')=1
  and (select pronargdefaults from pg_proc where proname='inbound_message_receive' and pronamespace='public'::regnamespace)=1);
select tt.chk('T0 scan_events accepts the ai_call action', (select pg_get_constraintdef(oid) like '%ai_call%' from pg_constraint where conname='scan_events_action_check'));

\echo == H1 the photo of a purchase bill follows the cost right
select tt.as(:'u');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/h1.jpg','aa11bb22cc33dd44ee55') ->> 'id' as j1 \gset
select scan_create(gen_random_uuid(),'expense',1,'SCAN/1/h2.jpg','aa11bb22cc33dd44ee56') ->> 'id' as j2 \gset
select tt.chk('H1 the uploader (made it) reads the purchase-bill photo and sees its path', _scan_photo_ok('SCAN/1/h1.jpg','view') and scan_get(:'j1'::uuid)->>'image_path' = 'SCAN/1/h1.jpg');
select tt.as(:'x');
select tt.chk('H1 a scan_confirm holder WITHOUT the cost right cannot read the purchase-bill photo', not _scan_photo_ok('SCAN/1/h1.jpg','view'));
select tt.chk('H1 ... and scan_get hides the path for him (cost_hidden true, image_path null)', (scan_get(:'j1'::uuid)->>'cost_hidden')='true' and scan_get(:'j1'::uuid)->'image_path' = 'null'::jsonb);
select tt.chk('H1 ... but an expense-slip photo stays readable for him and the path is shown', _scan_photo_ok('SCAN/1/h2.jpg','view') and scan_get(:'j2'::uuid)->>'image_path' = 'SCAN/1/h2.jpg');
select tt.as(:'c');
select tt.chk('H1 with the cost right the same reviewer reads it and gets the path', _scan_photo_ok('SCAN/1/h1.jpg','view') and scan_get(:'j1'::uuid)->>'image_path' = 'SCAN/1/h1.jpg');
select tt.as(:'o');
select tt.chk('H1 owner reads it', _scan_photo_ok('SCAN/1/h1.jpg','view') and scan_get(:'j1'::uuid)->>'image_path' = 'SCAN/1/h1.jpg');
select tt.as(:'w');
select tt.chk('H1 another place still sees nothing', not _scan_photo_ok('SCAN/1/h1.jpg','view') and not _scan_photo_ok('SCAN/1/h2.jpg','view'));
select tt.as(:'u');
select tt.chk('H1 upload permission unchanged (uploader may enter at place 1)', _scan_photo_ok('SCAN/1/new.jpg','enter') and not _scan_photo_ok('SCAN/2/new.jpg','enter'));

\echo == M1 PII exposure report (default NOT changed)
select tt.as(:'o');
select tt.chk('M1 default of inbox_pii_guard_on is still off; the recommendation row says on', (select default_value from rules where key='inbox_pii_guard_on')='false'::jsonb and not rule_on('inbox_pii_guard_on')
  and (select rec_value from setup_rec_defs81 where code='inbox_pii_guard_on')='true'::jsonb);
select pii_exposure_report94() as pr0 \gset
select tt.chk('M1 report with the guard off: direct phone + address reads are open, count of POS-view users is given, the note recommends on',
  (:'pr0'::jsonb->>'guard_on')='false' and (:'pr0'::jsonb->>'direct_mobile_read')='true' and (:'pr0'::jsonb->>'direct_address_read')='true'
  and (:'pr0'::jsonb->>'users_with_pos_view')::int >= 3 and :'pr0'::jsonb->>'note' ilike '%recommended%');
select set_rule('inbox_pii_guard_on','true') is null as pg1 \gset
select tt.chk('M1 report with the guard on: direct reads closed', (pii_exposure_report94()->>'guard_on')='true' and (pii_exposure_report94()->>'direct_mobile_read')='false' and (pii_exposure_report94()->>'direct_address_read')='false');
select set_rule('inbox_pii_guard_on','false') is null as pg2 \gset
select tt.as(:'k');
select tt.err('M1 a seller cannot run the report', 'select pii_exposure_report94()', 'not allowed');
select tt.as(:'o');

\echo == M2 optional proof secrets (hash only); not set = today's behaviour
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null as ch2 \gset
select sales_channel_save(null,'webform','web_form',null,'Web form',1,'salesperson','FORM1',true) is not null as ch1 \gset
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('W1','W1','W1','kg','kg','finished_good',true,100);
select id as w1 from items where code='W1' \gset
select stock_opening(:'w1'::uuid, 1, 100, 40, null, 'seed') is not null as op1 \gset
select tt.as(:'b');
select tt.chk('M2 no proof set (compat): a signed message is stored as before (old 9-argument call shape)', (inbound_message_receive('facebook','PAGE1','m-1','u1','Name','hello',now(),null,true)->>'duplicate')='false');
select tt.chk('M2 no proof set: a web order is taken as before', (web_order_submit('webform',gen_random_uuid(),'A','01711000001','x','home',format('[{"item_id":"%s","qty":1}]',:'w1')::jsonb,null)->>'ok')='true');
select tt.as(:'k');
select tt.err('M2 a seller cannot set a proof', $$select intake_proof_set94('meta','abcdefghijklmnop1234')$$, 'not allowed');
select tt.as(:'o');
select tt.err('M2 too short secret refused', $$select intake_proof_set94('meta','short')$$, 'bad_secret');
select tt.err('M2 unknown scope refused', $$select intake_proof_set94('sms','abcdefghijklmnop1234')$$, 'bad_scope');
select intake_proof_set94('meta','metaProofSecret_0001') ->> 'set' as ps1 \gset
select tt.chk('M2 set returns true; status shows meta only; the table holds a 64-hex hash, not the secret',
  :'ps1'='true' and (intake_proof_status94()->>'meta')='true' and (intake_proof_status94()->>'web_form')='false'
  and (select secret_hash ~ '^[0-9a-f]{64}$' and secret_hash <> 'metaProofSecret_0001' from intake_proofs94 where scope='meta')
  and (select count(*) from audit_log where table_name='intake_proofs94' and detail::text not like '%metaProofSecret%')=1);
select encode(sha256(convert_to('metaProofSecret_0001','UTF8')),'hex') as mhash \gset
select tt.as(:'b');
select inbound_message_receive('facebook','PAGE1','m-2','u1','Name','forged',now(),null,true) as r_np \gset
select tt.chk('M2 proof set: "signature ok" WITHOUT the proof is rejected (bad_proof) and nothing is stored', :'r_np'::jsonb->>'rejected'='bad_proof' and not exists (select 1 from inbound_messages where external_id='m-2'));
select inbound_message_receive('facebook','PAGE1','m-3','u1','Name','forged',now(),null,true,repeat('0',64)) as r_wp \gset
select tt.chk('M2 proof set: a wrong proof is rejected', :'r_wp'::jsonb->>'rejected'='bad_proof' and not exists (select 1 from inbound_messages where external_id='m-3'));
select inbound_message_receive('facebook','PAGE1','m-4','u1','Name','real',now(),null,true,:'mhash') as r_ok \gset
select tt.chk('M2 proof set: the right proof is stored (upper-case hex also fine)', (:'r_ok'::jsonb->>'duplicate')='false' and exists (select 1 from inbound_messages where external_id='m-4')
  and (inbound_message_receive('facebook','PAGE1','m-5','u1','Name','real',now(),null,true,upper(:'mhash'))->>'duplicate')='false');
select tt.chk('M2 proof set: a "bad signature" report still only logs the fact', (inbound_message_receive('facebook',null,'sig-1',null,null,null,null,null,false)->>'rejected')='bad_signature');
select tt.as(:'o');
select tt.chk('M2 the owner is never blocked by the proof', (inbound_message_receive('facebook','PAGE1','m-6','u1','Name','owner test',now(),null,true)->>'duplicate')='false');
select intake_proof_set94('web_form','webProofSecret_0002') ->> 'set' as ps2 \gset
select encode(sha256(convert_to('webProofSecret_0002','UTF8')),'hex') as whash \gset
select tt.as(:'b');
select tt.chk('M2 web proof set: a call without it is refused (captcha / key not believed)', web_order_submit('webform',gen_random_uuid(),'A','01711000002','x','home',format('[{"item_id":"%s","qty":1}]',:'w1')::jsonb,null,null,null,null,'k1',true)->>'error'='bad_proof');
select tt.chk('M2 web proof set: the right proof is accepted', (web_order_submit('webform',gen_random_uuid(),'A','01711000003','x','home',format('[{"item_id":"%s","qty":1}]',:'w1')::jsonb,null,null,null,null,'k1',true,:'whash')->>'ok')='true');
select tt.chk('M2 web proof set: the meta proof does not open the web form', web_order_submit('webform',gen_random_uuid(),'A','01711000004','x','home',format('[{"item_id":"%s","qty":1}]',:'w1')::jsonb,null,null,null,null,'k1',true,:'mhash')->>'error'='bad_proof');
select tt.as(:'o');
select intake_proof_set94('meta', null) ->> 'set' as pc1 \gset
select intake_proof_set94('web_form', null) ->> 'set' as pc2 \gset
select tt.chk('M2 clearing both proofs returns to today''s behaviour', :'pc1'='false' and :'pc2'='false' and (intake_proof_status94()->>'meta')='false' and not exists (select 1 from intake_proofs94));
select tt.as(:'b');
select tt.chk('M2 after clearing: calls without proof work again', (inbound_message_receive('facebook','PAGE1','m-7','u1','Name','again',now(),null,true)->>'duplicate')='false'
  and (web_order_submit('webform',gen_random_uuid(),'A','01711000005','x','home',format('[{"item_id":"%s","qty":1}]',:'w1')::jsonb,null)->>'ok')='true');

\echo == M3 flood limits and purge
select tt.as(:'o');
update intake_failures set created_at = created_at - interval '1 hour';      -- earlier rejected lines of this test must not count in the minute window
select set_rule('intake_reject_max_per_min','2') is null as cap1 \gset
select count(*) as rj0 from intake_failures where state='rejected' \gset
select tt.as(:'b');
select inbound_message_receive('facebook',null,'sig-a',null,null,null,null,null,false) ->> 'failure_id' as fa \gset
select inbound_message_receive('facebook',null,'sig-b',null,null,null,null,null,false) ->> 'failure_id' as fb \gset
select inbound_message_receive('facebook',null,'sig-c',null,null,null,null,null,false) ->> 'failure_id' as fc \gset
select tt.chk('M3 limit 2 per minute: the 3rd and 4th rejected lines are not stored (failure id 0), only 2 new rows',
  :'fa'::bigint > 0 and :'fb'::bigint > 0 and :'fc'::bigint = 0 and (select count(*) from intake_failures where state='rejected') - :rj0 = 2);
select tt.as(:'o'); select set_rule('intake_reject_max_per_min','null') is null as cap2 \gset
select tt.as(:'b');
select tt.chk('M3 empty limit = as before: rejected lines are stored again', (inbound_message_receive('facebook',null,'sig-d',null,null,null,null,null,false) ->> 'failure_id')::bigint > 0);
select tt.as(:'o');
select sales_channel_save(null,'fbpage2','facebook',null,'FB page 2',1,null,'PAGE2',true) is not null as ch3 \gset      -- a channel without earlier messages
select set_rule('inbox_rate_max_per_min','1') is null as rc1 \gset
select count(*) as im0 from inbound_messages \gset
select tt.as(:'b');
select inbound_message_receive('facebook','PAGE2','r-1','u9','Name','first',now(),null,true) ->> 'duplicate' as q1 \gset
select inbound_message_receive('facebook','PAGE2','r-2','u9','Name','second',now(),null,true) as q2 \gset
select tt.chk('M3 channel limit 1 per minute: the 1st is stored, the 2nd goes to the retry list (queued), not into the inbox',
  :'q1'='false' and (:'q2'::jsonb->>'queued')='true' and (select count(*) from inbound_messages) - :im0 = 1
  and exists (select 1 from intake_failures where kind='message' and external_id='r-2' and error like '%rate_limited%' and state='failed'));
select tt.as(:'o'); select set_rule('inbox_rate_max_per_min','null') is null as rc2 \gset
-- age some lines: 40 days old rejected + done, 40 days old failed (kept), a fresh rejected (kept)
update intake_failures set created_at = now() - interval '40 days' where external_id in ('sig-a','sig-b','sig-d');
update intake_failures set created_at = now() - interval '40 days' where external_id = 'r-2';          -- still state failed: must stay
select count(*) as fo from intake_failures where state in ('rejected','done','dismissed') and created_at < now() - interval '30 days' \gset
select count(*) as fk from intake_failures where state not in ('rejected','done','dismissed') \gset
select tt.chk('M3 fixtures: some old finished/rejected lines and a failed line exist', :fo >= 3 and :fk >= 1);
insert into intake_hits (channel_id, key_hash, at) select id, 'old', now() - interval '40 days' from sales_channels where code='webform';
select tt.as(:'k');
select tt.err('M3 a seller cannot purge', 'select intake_purge(30)', 'not allowed');
select tt.as(:'o');
select tt.err('M3 bad days refused', 'select intake_purge(0)', 'bad_input');
select intake_purge(30) as pg \gset
select tt.chk('M3 purge deletes exactly the old finished / rejected lines and old hits, keeps failed, dead and recent ones',
  (:'pg'::jsonb->>'failures_deleted')::int = :fo and (:'pg'::jsonb->>'hits_deleted')::int >= 1
  and (select count(*) from intake_failures where state not in ('rejected','done','dismissed')) = :fk
  and not exists (select 1 from intake_failures where state in ('rejected','done','dismissed') and created_at < now() - interval '30 days')
  and exists (select 1 from intake_failures where external_id = 'r-2'));
select tt.chk('M3 the audit trail itself is untouched by the purge', (select count(*) from audit_log where table_name='intake_failures') > 0);

\echo == M4 paid AI call limit
select tt.as(:'o');
select tt.chk('M4 rule edges: 0 refused (min 1), owner-typed only', (select kind='number' and min_value=1 from rules where key='scan_ai_max_per_job') );
select tt.err('M4 0 refused', $$select set_rule('scan_ai_max_per_job','0')$$, 'bad_value');
select tt.as(:'u');
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/ai1.jpg','bb11bb22cc33dd44ee55') ->> 'id' as ja \gset
select scan_create(gen_random_uuid(),'purchase_bill',1,'SCAN/1/ai2.jpg','bb11bb22cc33dd44ee56') ->> 'id' as jb \gset
select scan_ai_gate94(:'ja'::uuid) ->> 'attempt' as t1 \gset
select scan_ai_gate94(:'ja'::uuid) ->> 'attempt' as t2 \gset
select scan_ai_gate94(:'ja'::uuid) ->> 'attempt' as t3 \gset
select tt.chk('M4 empty limit = unlimited (as before): three calls pass and are counted 1, 2, 3', :'t1'='1' and :'t2'='2' and :'t3'='3' and (select count(*) from scan_events where job_id=:'ja'::uuid and action='ai_call')=3);
select tt.as(:'o'); select set_rule('scan_ai_max_per_job','3') is null as cj \gset
select tt.as(:'u');
select tt.err('M4 per job limit 3: the 4th call is refused before any AI call', format($$select scan_ai_gate94(%L::uuid)$$, :'ja'), 'too_many_attempts');
select tt.chk('M4 ... and the refused call is not counted', (select count(*) from scan_events where job_id=:'ja'::uuid and action='ai_call')=3);
select tt.chk('M4 another job of the same person is not affected by that limit', (scan_ai_gate94(:'jb'::uuid)->>'attempt')='1');
select tt.as(:'o'); select set_rule('scan_ai_max_per_job','null') is null as cj2 \gset
select set_rule('scan_ai_max_per_user_day','4') is null as cu \gset
select tt.as(:'u');
-- the uploader has made 4 calls so far in the last 24 hours (3 + 1)
select tt.err('M4 per person per day limit 4: the 5th call of the day is refused', format($$select scan_ai_gate94(%L::uuid)$$, :'jb'), 'too_many_attempts_today');
select tt.as(:'w');
select tt.err('M4 a user of another place cannot use the gate at all', format($$select scan_ai_gate94(%L::uuid)$$, :'ja'), 'not found');
select tt.as(:'k');
select tt.err('M4 a seller without scan rights cannot', format($$select scan_ai_gate94(%L::uuid)$$, :'ja'), 'not found');
select tt.as(:'o'); select set_rule('scan_ai_max_per_user_day','null') is null as cu2 \gset

\echo == M5 old-dated sale and the stock guard (block mode; opening 5, sale of 10 dated 10 hours back)
select set_rule('stock_negative_mode','"block"') is null as nb \gset
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('M5A','M5A','M5A','kg','kg','finished_good',true,10), ('M5B','M5B','M5B','kg','kg','finished_good',true,10), ('M5C','M5C','M5C','kg','kg','finished_good',true,10);
select id as ma from items where code='M5A' \gset
select id as mb from items where code='M5B' \gset
select id as mc from items where code='M5C' \gset
select stock_opening(:'ma'::uuid, 1, 5, 3, null, 'seed') is not null as oa \gset
select stock_opening(:'mb'::uuid, 1, 5, 3, null, 'seed') is not null as ob \gset
select stock_opening(:'mc'::uuid, 1, 5, 3, null, 'seed') is not null as oc \gset
select tt.as(:'k');     -- a plain seller: the owner may go below zero by his own grant, a seller may not
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 94001, now() - interval '10 hours', tt.today(), format('[{"item_id":"%s","qty":10,"price":10,"amount":100,"unit":"kg"}]', :'ma')::jsonb, 100, 0, 100, 'cash', :'k', 'seller1', 'done');
select tt.chk('M5 rule empty (today): the 10-hour-old sale of 10 against stock 5 is accepted, stock -5', (select qty from stock_balance where item_id=:'ma'::uuid and location_id=1) = -5);
select tt.as(:'o'); select set_rule('offline_sale_max_age','1') is null as ma1 \gset
select tt.as(:'k');
select tt.err('M5 limit 1 hour: the same kind of 10-hour-old sale is now refused by the stock guard',
  format($$insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status) values (gen_random_uuid(), 1, 94002, now() - interval '10 hours', tt.today(), '[{"item_id":"%s","qty":10,"price":10,"amount":100,"unit":"kg"}]'::jsonb, 100, 0, 100, 'cash', %L, 'owner1', 'done')$$, :'mb', :'o'), 'insufficient_stock');
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 94003, now() - interval '30 minutes', tt.today(), format('[{"item_id":"%s","qty":10,"price":10,"amount":100,"unit":"kg"}]', :'mc')::jsonb, 100, 0, 100, 'cash', :'k', 'seller1', 'done');
select tt.chk('M5 limit 1 hour: a 30-minute-old (inside the window) sale is still a late sync and is accepted', (select qty from stock_balance where item_id=:'mc'::uuid and location_id=1) = -5);
select set_config('bos.replay_override','1',false) as ov \gset
insert into sales (client_id, location_id, receipt, sold_at, sale_date, lines, subtotal, discount, total, pay_mode, created_by, created_staff, status)
  values (gen_random_uuid(), 1, 94004, now() - interval '10 hours', tt.today(), format('[{"item_id":"%s","qty":10,"price":10,"amount":100,"unit":"kg"}]', :'mb')::jsonb, 100, 0, 100, 'cash', :'k', 'seller1', 'done');
select set_config('bos.replay_override','',false) as ov2 \gset
select tt.chk('M5 a manager replay override still lets an old sale in', (select qty from stock_balance where item_id=:'mb'::uuid and location_id=1) = -5);
select tt.as(:'o'); select set_rule('offline_sale_max_age','null') is null as ma2 \gset
select set_rule('stock_negative_mode','"warn"') is null as nw \gset
select tt.err('M5 limit above the range refused', $$select set_rule('offline_sale_max_age','9000')$$, 'bad_value');

\echo == L1 set_doc_template audit staff id
select tt.as(:'o');
select set_doc_template('invoice','tpl_a',null) is not null as sd \gset
select tt.chk('L1 the audit line of set_doc_template carries the owner''s staff id', (select staff_id from audit_log where table_name='doc_template_choice' order by id desc limit 1) = 'OWN1');

\echo == L2 invoice scoping (optional) + share-log dedupe
select tt.as(:'o'); select set_rule('pos_discount_manager','false') is null as dm \gset
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('I1','I1','I1','pc','pc','resale',false,100);
select id as i1 from items where code='I1' \gset
select tt.as(:'k'); set role authenticated;
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'i1')::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false)->>'id' as sa \gset
reset role;
select tt.as(:'k2'); set role authenticated;
select tt.chk('L2 default (switch off): another seller at the same place can open the invoice, as before', invoice_data92(:'sa'::uuid)->>'id' = :'sa');
reset role; select tt.as(:'o'); select set_rule('invoice_own_sales_only','true') is null as io \gset
select tt.as(:'k2'); set role authenticated;
select tt.err('L2 switch on: the other seller gets not_found for the invoice', format($$select invoice_data92(%L::uuid)$$, :'sa'), 'not_found');
select tt.err('L2 switch on: ... and for the share log', format($$select invoice_share_log92(%L::uuid, 'print')$$, :'sa'), 'not_found');
reset role; select tt.as(:'k'); set role authenticated;
select tt.chk('L2 switch on: the seller of that sale still opens it', invoice_data92(:'sa'::uuid)->>'id' = :'sa');
reset role; select tt.as(:'m'); set role authenticated;
select tt.chk('L2 switch on: POS approve (manager) still opens any sale', invoice_data92(:'sa'::uuid)->>'id' = :'sa');
reset role; select tt.as(:'o'); select set_rule('invoice_own_sales_only','false') is null as io2 \gset
select tt.as(:'k'); set role authenticated;
select invoice_share_log92(:'sa'::uuid,'print') as l1 \gset
select invoice_share_log92(:'sa'::uuid,'print') as l2 \gset
select invoice_share_log92(:'sa'::uuid,'sms') as l3 \gset
reset role;
select tt.chk('L2 the same person + sale + channel within a minute is ONE log line (same id), another channel is a new line',
  :'l1'=:'l2' and :'l3'<>:'l1' and (select count(*) from invoice_shares where sale_id=:'sa'::uuid)=2);

\echo == scheduler run history
insert into acct_autopost_runs85 (posted, reversed, errors, locked, waiting, more, note) values (3, 0, 0, 1, 2, false, 'fixture');
select tt.as(:'o');
select tt.chk('R1 owner reads the run history through the function', jsonb_array_length(acct_autopost_runs_list(5)) = 1 and acct_autopost_runs_list(5)->0->>'note' = 'fixture' and (acct_autopost_runs_list(5)->0->>'posted')::int = 3);
select tt.as(:'a');
select tt.chk('R1 a holder of accounts_view reads it too', jsonb_array_length(acct_autopost_runs_list()) = 1);
select tt.as(:'k');
select tt.err('R1 a seller cannot', 'select acct_autopost_runs_list()', 'not allowed');
select tt.chk('R1 the table itself is still closed to the browser', not has_table_privilege('authenticated','public.acct_autopost_runs85','select'));

\echo == recommendation rows for the setup guide
select tt.chk('S1 partner_base_estimate: recommend refuse, packaging_return_mode: recommend wastage; rule defaults unchanged (warn / none)',
  (select rec_value from setup_rec_defs81 where code='partner_base_estimate')='"refuse"'::jsonb and (select rec_value from setup_rec_defs81 where code='packaging_return_mode')='"wastage"'::jsonb
  and (select default_value from rules where key='partner_base_estimate')='"warn"'::jsonb and (select default_value from rules where key='packaging_return_mode')='"none"'::jsonb
  and rule_txt('partner_base_estimate')='warn' and rule_txt('packaging_return_mode')='none');
select tt.chk('S1 recommended values are valid choices of their rules', (select r.choices @> jsonb_build_array(d.rec_value #>> '{}') from setup_rec_defs81 d join rules r on r.key=d.rule_key where d.code='partner_base_estimate')
  and (select r.choices @> jsonb_build_array(d.rec_value #>> '{}') from setup_rec_defs81 d join rules r on r.key=d.rule_key where d.code='packaging_return_mode'));
select tt.chk('S1 the new limits get a row each with text in three languages and NO invented value', (select count(*) from setup_rec_defs81 where code in ('scan_ai_max_per_job','scan_ai_max_per_user_day','offline_sale_max_age','inbox_rate_max_per_min','intake_reject_max_per_min') and rec_value is null and reason_bn is not null and reason_mix is not null and reason_en is not null)=5
  and (select rec_value from setup_rec_defs81 where code='invoice_own_sales_only')='true'::jsonb);
select tt.chk('S1 English reasons have no Bangla letters', (select bool_and(reason_en !~ '[ঀ-৿]') from setup_rec_defs81 where phase in ('94') or code in ('partner_base_estimate','packaging_return_mode')));
select tt.chk('S1 every row points to an existing rule', not exists (select 1 from setup_rec_defs81 d where not exists (select 1 from rules r where r.key = d.rule_key)));

\echo == M6 execute is revoked from anon / public on the re-created functions (simulate the Supabase default first)
do $$
declare r regprocedure;
begin
  for r in select p.oid::regprocedure from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('acct_income_statement','acct_overview','acct_post_pending','partner_calculate','partner_settlement_save','sale_return','stock_count_adjust','stock_receive_transfer','record_sale2','urgent_alerts','biz_items','items_with_cost')
  loop execute format('grant execute on function %s to anon, public, authenticated', r); end loop;
end $$;
select tt.chk('M6 before: the 12 functions are executable by anon (the Supabase default is simulated)',
  (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('acct_income_statement','acct_overview','acct_post_pending','partner_calculate','partner_settlement_save','sale_return','stock_count_adjust','stock_receive_transfer','record_sale2','urgent_alerts','biz_items','items_with_cost') and has_function_privilege('anon', p.oid, 'execute'))=12);
create temp table fh as select string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text) h from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f';
\i supabase/phase94.sql
\i supabase/phase112.sql
\i supabase/phase113.sql
\i supabase/phase114.sql
\i supabase/phase115.sql
\i supabase/phase116.sql
\i supabase/phase117.sql
\i supabase/phase118.sql
\i supabase/phase120.sql
\i supabase/phase121.sql
select tt.chk('M6 after the second paste: no function body changed (paste-twice safe)', (select h from fh) = (select string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text) from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f'));
select tt.chk('M6 after: anon and public cannot execute any of the 12, signed-in users still can',
  (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('acct_income_statement','acct_overview','acct_post_pending','partner_calculate','partner_settlement_save','sale_return','stock_count_adjust','stock_receive_transfer','record_sale2','urgent_alerts','biz_items','items_with_cost')
     and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('public', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute'))=12);
select tt.chk('M6 the internal closed functions stay closed (rpt_agg_sql, stock_post)', not has_function_privilege('authenticated','public.rpt_agg_sql(text,text,text,text[],text[],text,text,text,text,integer,integer,boolean,boolean,boolean)','execute')
  and not has_function_privilege('authenticated','public.stock_post(uuid,integer,numeric,text,text,text,numeric,bigint,timestamp with time zone,text,bigint,text,uuid,uuid)','execute'));
select tt.as(:'o');
select anon_exec_audit94() as ae \gset
select tt.chk('M6 anon_exec_audit94 (owner) lists what anon can still run: the login helpers, none of the 12', (:'ae'::jsonb)::text like '%login_precheck%' and (:'ae'::jsonb)::text not like '%acct_overview%' and (:'ae'::jsonb)::text not like '%record_sale2%');
select tt.as(:'k');
select tt.err('M6 a seller cannot run the audit', 'select anon_exec_audit94()', 'not allowed');
select tt.chk('M6 after the 2nd paste the settings are still empty / off (limits not changed by pasting)', rule_num('scan_ai_max_per_job') is null and rule_num('offline_sale_max_age') is null and not rule_on('invoice_own_sales_only'));

\echo == RESULT
select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
