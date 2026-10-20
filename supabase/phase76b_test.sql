-- phase76b_test.sql = copy of phase76_test.sql for the FINAL build (72..91 + 89). Only change (marked bos89): T1 'bad kind' used 'telegram', which phase512 made a VALID kind; it now uses 'signal'.
-- FRESH DB ONLY. Phase 76 tests (Step H: channels, inbox, web form intake, Meta intake, drafts, dup flags, PII guard, failed list).
--   bash <build_fresh_db copy> with ORDER="phase8 ... phase62 phase70 phase71 phase76" (see docs/briefs_p2p3/step_H_REPORT.md)
--   psql -h /tmp -p 5544 -U postgres -d 76db -qAt -f supabase/phase76_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
\set p '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
\set b '00000000-0000-0000-0000-000000000006'
\set x '00000000-0000-0000-0000-000000000007'
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
-- run one statement as the plain browser role (RLS + privileges apply); must fail
create or replace function tt.err_browser(p_name text, p_sql text) returns void language plpgsql as $$
begin
  set local role authenticated;
  begin execute p_sql; reset role; perform tt.chk(p_name, false);
  exception when others then reset role; perform tt.chk(p_name, true); end;
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}'),
 (:'p','sales4@s.app','{"full_name":"Sales"}'), (:'t','mgr5@s.app','{"full_name":"Other place"}'), (:'b','bot6@s.app','{"full_name":"Intake bot"}'),
 (:'x','bot7@s.app','{"full_name":"Intake bot without role"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper'),(:'p','salesperson'),(:'t','showroom_manager'),(:'b','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1),(:'p',1),(:'t',2),(:'b',1) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('C1','C1','C1','kg','kg','finished_good',true,100), ('C2','C2','C2','kg','kg','finished_good',true,50),
  ('C3','C3 not sellable','C3','kg','kg','finished_good',true,70), ('C4','C4 hidden','C4','kg','kg','finished_good',true,70), ('C5','C5 inactive','C5','kg','kg','finished_good',true,70), ('C6','C6 noprice','C6','kg','kg','finished_good',true,null);
update items set sellable=false where code='C3'; update items set hidden=true where code='C4'; update items set is_active=false where code='C5';
select id as c1 from items where code='C1' \gset
select id as c2 from items where code='C2' \gset
select id as c3 from items where code='C3' \gset
select id as c4 from items where code='C4' \gset
select id as c5 from items where code='C5' \gset
select id as c6 from items where code='C6' \gset
select tt.as(:'o');
select stock_opening(:'c1'::uuid, 1, 100, 40, null, 'seed') is not null as op1 \gset
select stock_opening(:'c2'::uuid, 1, 100, 20, null, 'seed') is not null as op2 \gset

\echo == T0 shape
select tt.chk('T0 browser functions open, helpers closed, anon none',
  has_function_privilege('authenticated','public.web_order_submit(text,uuid,text,text,text,text,jsonb,text,text,text,text,text,boolean)','execute')
  and not has_function_privilege('anon','public.inbound_message_receive(text,text,text,text,text,text,timestamptz,text,boolean)','execute')
  and not has_function_privilege('authenticated','public._inb_insert_message(jsonb)','execute') and not has_function_privilege('authenticated','public._web_order_run(jsonb)','execute')
  and not has_function_privilege('authenticated','public._inb_hmac_sha256(bytea,bytea)','execute'));
select tt.chk('T0 new tables are read-only for browsers, RLS on, failures/hits/bots closed',
  not has_table_privilege('authenticated','public.inbound_messages','insert') and not has_table_privilege('authenticated','public.sales_channels','insert') and not has_table_privilege('authenticated','public.order_dup_flags','update')
  and not has_table_privilege('authenticated','public.intake_failures','select') and not has_table_privilege('authenticated','public.intake_hits','select') and not has_table_privilege('authenticated','public.intake_bots','select')
  and (select bool_and(relrowsecurity) from pg_class where relname in ('sales_channels','intake_bots','inbound_messages','inbound_message_events','intake_failures','intake_hits','order_dup_flags')));
select tt.chk('T0 message text / handle / name / attachment and channel account ref are not selectable',
  not has_column_privilege('authenticated','public.inbound_messages','msg_text','select') and not has_column_privilege('authenticated','public.inbound_messages','customer_handle','select')
  and not has_column_privilege('authenticated','public.inbound_messages','customer_name','select') and not has_column_privilege('authenticated','public.inbound_messages','attachment_ref','select')
  and not has_column_privilege('authenticated','public.sales_channels','account_ref','select') and has_column_privilege('authenticated','public.inbound_messages','status','select'));
select tt.chk('T0 switches default OFF; numbers are settings', not rule_on('inbox_on') and not rule_on('meta_intake_on') and not rule_on('web_form_on') and not rule_on('web_form_captcha_on')
  and not rule_on('inbox_autodraft_on') and not rule_on('inbox_pii_guard_on') and rule_num('web_form_rate_max')=10 and rule_num('inbox_silence_hours')=24 and rule_num('intake_max_tries')=5);
select tt.chk('T0 contact-view grant defined', exists (select 1 from grant_defs where grant_code='inbox_contact_view'));
select tt.chk('T0 phone/address still selectable today (guard off = today''s behaviour)', has_column_privilege('authenticated','public.online_orders','customer_mobile','select'));

\echo == T1 channels (H1)
select tt.as(:'s');
select tt.err('T1 only the owner makes a channel', $$select sales_channel_save(null,'fbpage','facebook',null,'FB',1,null,'PAGE1',true)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T1 kind other needs the free text', $$select sales_channel_save(null,'misc','other',null,'Other',1,null,null,true)$$, 'other_text_required');
select tt.err('T1 bad kind refused', $$select sales_channel_save(null,'misc','signal',null,'X',1,null,null,true)$$, 'bad_kind');
select sales_channel_save(null,'webform','web_form',null,'Web form',1,'salesperson','FORM1',true) is not null as ch1 \gset
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null as ch2 \gset
select sales_channel_save(null,'wa','whatsapp',null,'WhatsApp',1,null,'PHONEID1',true) is not null as ch3 \gset
select sales_channel_save(null,'phoneline','phone',null,'Phone',1,'salesperson',null,true) is not null as ch4 \gset
select sales_channel_save(null,'other1','other','TikTok','Other: TikTok',1,null,null,true) is not null as ch5 \gset
select id as cweb from sales_channels where code='webform' \gset
select id as cfb from sales_channels where code='fbpage' \gset
select id as cwa from sales_channels where code='wa' \gset
select id as cph from sales_channels where code='phoneline' \gset
select tt.chk('T1 five channels (web, fb, whatsapp, phone, other with text)', (select count(*) from sales_channels)=5 and (select other_text from sales_channels where code='other1')='TikTok');
select tt.chk('T1 owner sees account ref in the list', (select bool_and(true) from jsonb_array_elements(sales_channels_list(false)) e where e->>'code'='fbpage' and e->>'account_ref'='PAGE1'));
select tt.as(:'p');
select tt.chk('T1 staff list hides the account ref', (select count(*) from jsonb_array_elements(sales_channels_list(false)) e where e->>'account_ref' is not null)=0 and jsonb_array_length(sales_channels_list(false))=5);
select tt.as(:'o');
select tt.err('T1 a channel is never deleted', $$delete from sales_channels where code='other1'$$, 'append_only');
select tt.err('T1 same kind + account ref twice refused', $$select sales_channel_save(null,'fb2','facebook',null,'FB2',1,null,'PAGE1',true)$$, 'duplicate');

\echo == T2 switches off / bots
select intake_bot_set(:'b'::uuid, true) is not null as bt \gset
select intake_bot_set(:'x'::uuid, true) is not null as bt2 \gset
select tt.err('T2 the owner cannot be a bot', format($$select intake_bot_set('%s'::uuid,true)$$, :'o'), 'owner_cannot_be_bot');
select tt.as(:'s');
select tt.err('T2 staff cannot mark a bot', format($$select intake_bot_set('%s'::uuid,true)$$, :'p'), 'not allowed');
select tt.as(:'b');
select tt.chk('T2 switch off: receive returns off, nothing stored', (inbound_message_receive('facebook','PAGE1','m-off','u1','Name','hello',now(),null,true)->>'off')::boolean and (select count(*) from inbound_messages)=0);
select tt.chk('T2 switch off: web submit returns off', (web_order_submit('webform',gen_random_uuid(),'A','01711000001','x','home',format('[{"item_id":"%s","qty":1}]',:'c1')::jsonb,null)->>'off')::boolean);
select tt.as(:'o');
select set_rule('inbox_on','true') is null as r1 \gset
select set_rule('online_orders_on','true') is null as r2 \gset
select tt.as(:'b');
select tt.chk('T2 inbox on but Meta intake still off: facebook returns off', (inbound_message_receive('facebook','PAGE1','m-off','u1','Name','hello',now(),null,true)->>'off')::boolean);
select tt.as(:'o'); select set_rule('meta_intake_on','true') is null as r3 \gset

\echo == T3 message intake (H2 / H4)
select tt.as(:'p');
select tt.err('T3 normal staff cannot use the receiver', $$select inbound_message_receive('facebook','PAGE1','m1','u1','Name','hello',now(),null,true)$$, 'not allowed');
select tt.as(:'b');
select inbound_message_receive('facebook','PAGE1','m1','psid-1','Customer A','I want 2 kg sweets',now(),'https://x/a.jpg',true)::text as r_m1 \gset
select tt.chk('T3 first message stored (one row, status new)', (select count(*) from inbound_messages)=1 and (select status from inbound_messages)='new' and (:'r_m1'::jsonb->>'duplicate')::boolean is false);
select inbound_message_receive('facebook','PAGE1','m1','psid-1','Customer A','I want 2 kg sweets',now(),null,true)->>'duplicate' as dd1 \gset
select tt.chk('T3 SAME message twice = one inbox row', :'dd1'='true' and (select count(*) from inbound_messages)=1);
select inbound_message_receive('whatsapp','PHONEID1','m1','8801711000009','Customer B','price?',now(),null,true)->>'duplicate' as dd2 \gset
select tt.chk('T3 same external id on another channel is another message', :'dd2'='false' and (select count(*) from inbound_messages)=2);
select inbound_message_receive('facebook','PAGE1','m-bad','psid-9','Evil','spam',now(),null,false)->>'rejected' as rj \gset
select tt.chk('T3 WRONG signature rejected: no message row, a rejected line in the failed list (no body kept)', :'rj'='bad_signature'
  and (select count(*) from inbound_messages where external_id='m-bad')=0 and (select count(*) from intake_failures where state='rejected' and kind='bad_signature')=1
  and (select payload::text from intake_failures where kind='bad_signature')='{"kind": "facebook"}');
select inbound_message_receive('facebook','NOPE','m-x','psid-2','C','hi',now(),null,true)->>'queued' as qd \gset
select tt.chk('T3 unknown page id: queued in the failed list (not lost, not thrown)', :'qd'='true'
  and (select count(*) from intake_failures where kind='message' and state='failed')=1 and (select count(*) from inbound_messages)=2);
select tt.chk('T3 audit has the insert without message text', (select count(*) from audit_log where table_name='inbound_messages' and action='insert')=2
  and not exists (select 1 from audit_log where table_name='inbound_messages' and detail::text like '%want 2 kg%'));

\echo == T4 HMAC (RFC 4231 case 2) and signature check
select tt.chk('T4 HMAC-SHA256 matches the RFC 4231 vector', _inb_hmac_sha256(convert_to('Jefe','UTF8'), convert_to('what do ya want for nothing?','UTF8'))='5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
select tt.chk('T4 long key (131 bytes of 0xaa, RFC 4231 case 6) matches', _inb_hmac_sha256(decode(repeat('aa',131),'hex'), convert_to('Test Using Larger Than Block-Size Key - Hash Key First','UTF8'))='60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54');
select tt.chk('T4 inbound_sig_verify: right header true', inbound_sig_verify('Jefe','what do ya want for nothing?','sha256=5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843'));
select tt.chk('T4 inbound_sig_verify: wrong / malformed / empty-secret headers false', not inbound_sig_verify('Jefe','what do ya want for nothing?','sha256=5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3844')
  and not inbound_sig_verify('Jefe','tampered body','sha256=5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843') and not inbound_sig_verify('Jefe','x','nonsense') and not inbound_sig_verify('','x','sha256=00'));

\echo == T5 failed list + retry
select tt.as(:'o');
select sales_channel_save(null,'fbpage2','facebook',null,'FB page 2',1,null,'NOPE',true) is not null as chfix \gset
select tt.as(:'b');
select tt.chk('T5 not yet due: nothing retried', (intake_retry_due(10)->>'done')::int=0);
update intake_failures set next_try_at = now() - interval '1 minute' where state='failed';
select intake_retry_due(10)->>'done' as rdone \gset
select tt.chk('T5 after the channel exists the retry stores the message and closes the failure', :'rdone'='1' and (select count(*) from inbound_messages where external_id='m-x')=1
  and (select state from intake_failures where kind='message')='done');
select tt.as(:'o');
select tt.err('T5 dismiss needs a reason', $$select intake_failure_dismiss(1,'')$$, 'reason_required');
select tt.as(:'p');
select tt.err('T5 plain staff cannot read the failed list', $$select intake_failures_list()$$, 'not allowed');
select tt.as(:'s');
select tt.chk('T5 POS approver can read the failed list (no payload column)', jsonb_array_length(intake_failures_list(null,50))=2 and not (intake_failures_list(null,50)->0 ? 'payload'));
-- retries stop after the setting
select tt.as(:'o');
select _intake_fail('message', null, 'dead-1', 'boom', '{"kind":"facebook","account_ref":"NOPE2","external_id":"dead-1"}') as dfid \gset
update intake_failures set next_try_at = now() - interval '1 minute' where id = :dfid;
select tt.as(:'b');
select intake_retry_due(10) is not null as rt1 \gset
update intake_failures set next_try_at = now() - interval '1 minute' where id = :dfid;
select tt.chk('T5 failing again increases attempts and keeps it failed', (select attempts from intake_failures where id=:dfid)=1 and (select state from intake_failures where id=:dfid)='failed');
select tt.as(:'o'); select set_rule('intake_max_tries','2') is null as rr2 \gset
select tt.as(:'b'); select intake_retry_due(10) is not null as rt2 \gset
select tt.chk('T5 after max tries (setting) the failure is dead', (select state from intake_failures where id=:dfid)='dead');

\echo == T6 inbox list / get / status / convert (H2)
select tt.as(:'p');
select tt.chk('T6 list shows both messages with text (guard off = today)', jsonb_array_length(inbox_list(1,'new',50))=3 and (inbox_list(1,'new',50)->0->>'text') is not null);
select id as m1 from inbound_messages where external_id='m1' and channel_id=:cfb \gset
select id as m2 from inbound_messages where external_id='m1' and channel_id=:cwa \gset
select inbox_get(:m1)->>'text' as gtxt \gset
select tt.chk('T6 get shows the full message and writes a view audit row', :'gtxt'='I want 2 kg sweets' and exists (select 1 from audit_log where action='view' and table_name='inbound_messages' and record_id=:m1::text));
select tt.as(:'t');
select tt.err('T6 another place cannot open it', format($$select inbox_get(%s)$$, :m1), 'not allowed');
select tt.as(:'k');
select tt.err('T6 storekeeper (no POS) cannot list', $$select inbox_list(1,null,10)$$, 'not allowed');
select tt.as(:'p');
select tt.chk('T6 mark seen', inbox_set_status(:m1,'seen')->>'status'='seen');
select tt.err('T6 ignore needs a reason', format($$select inbox_set_status(%s,'ignored','')$$, :m2), 'reason_required');
select tt.chk('T6 ignore with reason then back to new', inbox_set_status(:m2,'ignored','spam')->>'status'='ignored' and inbox_set_status(:m2,'new')->>'status'='new');
select tt.err_browser('T6 browser role cannot insert a message', $$insert into public.inbound_messages (channel_id, location_id, external_id) values (1,1,'hack')$$);
select tt.err_browser('T6 browser role cannot insert an order', $$insert into public.online_orders (order_no, location_id, channel, customer_name, customer_mobile, lines, subtotal, delivery_mode) values (99,1,'phone','x','0171100000','[]',0,'pickup')$$);
-- convert: staff type the items; customer and channel come from the message
select tt.chk('T6 convert (order screen pre-filled; staff typed items, qty, address)',
  (online_order_save2(null, '00000000-0000-0000-0000-0000000000a1'::uuid, 1, :cfb, 'Customer A', '01711000111', 'Dhaka road 1', format('[{"item_id":"%s","qty":2}]', :'c1')::jsonb, 'home', null, null, 0, 0, 0, null, null, 'from FB', null, 'campaign-x', 'mobile', null, 'TX123', :m1)->>'order_no') is not null);
select id as ord1 from online_orders where inbox_msg_id=:m1 \gset
select tt.chk('T6 message is converted + linked; order has channel, external ref, source, pay mode, pay ref',
  (select status from inbound_messages where id=:m1)='converted' and (select linked_order_id from inbound_messages where id=:m1)=:'ord1'::uuid
  and (select channel_id from online_orders where id=:'ord1'::uuid)=:cfb and (select external_ref from online_orders where id=:'ord1'::uuid)='m1'
  and (select source from online_orders where id=:'ord1'::uuid)='campaign-x' and (select pay_mode||pay_ref from online_orders where id=:'ord1'::uuid)='mobileTX123' and (select channel from online_orders where id=:'ord1'::uuid)='facebook');
select tt.err('T6 a converted message cannot be converted twice', format($$select online_order_save2(null, gen_random_uuid(), 1, %s, 'Customer A', '01711000111', 'Dhaka', '[{"item_id":"%s","qty":1}]'::jsonb, 'home', null, null, 0, 0, 0, null, null, null, null, null, null, null, null, %s)$$, :cfb, :'c1', :m1), 'message_closed');
select tt.err('T6 message of another channel cannot be used', format($$select online_order_save2(null, gen_random_uuid(), 1, %s, 'Customer B', '01711000112', 'Dhaka', '[{"item_id":"%s","qty":1}]'::jsonb, 'home', null, null, 0, 0, 0, null, null, null, null, null, null, null, null, %s)$$, :cfb, :'c1', :m2), 'message_not_found');
select tt.err('T6 pay mode other needs the text', format($$select online_order_save2(null, gen_random_uuid(), 1, %s, 'Z', '01711000113', null, '[{"item_id":"%s","qty":1}]'::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null, null, null, 'other', null, null, null)$$, :cfb, :'c1'), 'pay_mode_other_required');
select online_order_save2(null, '00000000-0000-0000-0000-0000000000a1'::uuid, 1, :cfb, 'Customer A', '01711000111', 'Dhaka road 1', format('[{"item_id":"%s","qty":2}]', :'c1')::jsonb, 'home', null, null, 0, 0, 0, null, null, 'from FB', null, 'campaign-x', 'mobile', null, 'TX123', :m1)->>'dup' as sdup \gset
select tt.chk('T6 same client id again = the same order (idempotent through the wrapper)', :'sdup'='true' and (select count(*) from online_orders)=1);
select online_order_save(null,gen_random_uuid(),1,'phone','Old way','01711000114',null,format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,'pickup',null,null,0,0,0,null,null,null)->>'order_no' as oldno \gset
select tt.chk('T6 the old online_order_save still works with the text channel', :'oldno' is not null and (select count(*) from online_orders)=2);

\echo == T7 web form (H3)
select tt.as(:'o'); select set_rule('web_form_on','true') is null as r4 \gset
select set_rule('web_form_rate_max','0') is null as r4b \gset
select tt.as(:'b');
select gen_random_uuid() as sub1 \gset
select format('select web_order_submit(%L,%L::uuid,%L,%L,%L,%L,%L::jsonb,%L)', 'webform', :'sub1', 'Web Cust', '01811000001', 'Dhaka 5', 'home',
   format('[{"item_id":"%s","qty":3,"price":1,"amount":3}]', :'c1'), 'please call') as wq \gset
select (:wq)::text as w1 \gset
select tt.chk('T7 web order saved, status new, total computed by the server (3 x 100 = 300, client price 1 ignored)', (:'w1'::jsonb->>'ok')::boolean and (:'w1'::jsonb->>'subtotal')::numeric=300
  and (select subtotal from online_orders where external_ref=:'sub1')=300 and (select (lines->0->>'price')::numeric from online_orders where external_ref=:'sub1')=100);
select tt.chk('T7 the web order carries the channel + source of the form and is created through online_order_save (event trail present)',
  (select channel_id from online_orders where external_ref=:'sub1')=:cweb and (select channel from online_orders where external_ref=:'sub1')='website'
  and exists (select 1 from online_order_events e join online_orders o on o.id=e.order_id where o.external_ref=:'sub1' and e.note='created'));
select (:wq)::text as w2 \gset
select tt.chk('T7 SAME submission twice = ONE order', (:'w2'::jsonb->>'dup')::boolean and (select count(*) from online_orders where external_ref=:'sub1')=1);
select tt.chk('T7 the form never wrote the table directly: bot has no table privilege', not has_table_privilege('authenticated','public.online_orders','insert'));
select tt.chk('T7 inactive item refused', web_order_submit('webform',gen_random_uuid(),'A','01811000002','x','home',format('[{"item_id":"%s","qty":1}]',:'c5')::jsonb,null)->>'error'='item_unavailable');
select tt.chk('T7 not-sellable item refused', web_order_submit('webform',gen_random_uuid(),'A','01811000002','x','home',format('[{"item_id":"%s","qty":1}]',:'c3')::jsonb,null)->>'error'='item_unavailable');
select tt.chk('T7 hidden item refused', web_order_submit('webform',gen_random_uuid(),'A','01811000002','x','home',format('[{"item_id":"%s","qty":1}]',:'c4')::jsonb,null)->>'error'='item_unavailable');
select tt.chk('T7 item without price refused', web_order_submit('webform',gen_random_uuid(),'A','01811000002','x','home',format('[{"item_id":"%s","qty":1}]',:'c6')::jsonb,null)->>'error'='item_unavailable');
select tt.chk('T7 bad qty / bad mobile / missing address are user errors (not queued)', web_order_submit('webform',gen_random_uuid(),'A','01811000002','x','home',format('[{"item_id":"%s","qty":0}]',:'c1')::jsonb,null)->>'error'='bad_qty'
  and web_order_submit('webform',gen_random_uuid(),'A','12','x','home',format('[{"item_id":"%s","qty":1}]',:'c1')::jsonb,null)->>'error'='bad_mobile'
  and web_order_submit('webform',gen_random_uuid(),'A','01811000002',null,'home',format('[{"item_id":"%s","qty":1}]',:'c1')::jsonb,null)->>'error'='address_required'
  and (select count(*) from intake_failures where kind='web_order')=0);
select tt.chk('T7 catalogue lists only active + sellable + visible + priced items (C1, C2 yes; C3..C6 no)', (select count(*) from jsonb_array_elements(web_form_catalog('webform')->'items') e where e->>'id' in (:'c1',:'c2'))=2
  and (select count(*) from jsonb_array_elements(web_form_catalog('webform')->'items') e where e->>'id' in (:'c3',:'c4',:'c5',:'c6'))=0);
-- captcha hook
select tt.as(:'o'); select set_rule('web_form_captcha_on','true') is null as r5 \gset
select tt.as(:'b');
select tt.chk('T7 captcha on: no pass = refused; pass = accepted', web_order_submit('webform',gen_random_uuid(),'A','01811000003','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null,null,null,null,'k1',null)->>'error'='captcha_required'
  and (web_order_submit('webform',gen_random_uuid(),'A','01811000003','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null,null,null,null,'k1',true)->>'ok')::boolean);
select tt.as(:'o'); select set_rule('web_form_captcha_on','false') is null as r6 \gset
select set_rule('web_form_rate_max','2') is null as r7 \gset
select tt.as(:'b');
select web_order_submit('webform',gen_random_uuid(),'R','01811000004','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null,null,null,null,'dev-A',null) is not null as rl1 \gset
select tt.chk('T7 rate limit (setting 2 per window; one hit was already counted for key dev-A? no: fresh key)', (web_order_submit('webform',gen_random_uuid(),'R','01811000004','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null,null,null,null,'dev-A',null)->>'ok')::boolean
  and web_order_submit('webform',gen_random_uuid(),'R','01811000004','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null,null,null,null,'dev-A',null)->>'error'='rate_limited');
select tt.chk('T7 another device is not limited', (web_order_submit('webform',gen_random_uuid(),'R','01811000005','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null,null,null,null,'dev-B',null)->>'ok')::boolean);
select tt.as(:'o'); select set_rule('web_form_rate_max','0') is null as r8 \gset
select tt.as(:'p');
select tt.err('T7 normal staff cannot call the form endpoint function', format($$select web_order_submit('webform',gen_random_uuid(),'A','01811000009','x','home','[{"item_id":"%s","qty":1}]'::jsonb,null)$$, :'c1'), 'not allowed');
-- failure -> queue -> retry (bot without a POS role)
select tt.as(:'x');
select gen_random_uuid() as sub2 \gset
select web_order_submit('webform',:'sub2'::uuid,'Q','01811000006','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null)::text as wf \gset
select tt.chk('T7 a system failure (bot lacks POS) does not lose the order: queued in the failed list', (:'wf'::jsonb->>'queued')::boolean and (select count(*) from intake_failures where kind='web_order' and state='failed')=1
  and (select count(*) from online_orders where external_ref=:'sub2')=0);
select tt.as(:'o');
insert into user_roles values (:'x','salesperson') on conflict do nothing; insert into user_locations values (:'x',1) on conflict do nothing;
update intake_failures set next_try_at = now() - interval '1 minute' where kind='web_order';
select tt.as(:'x');
select intake_retry_due(10)->>'done' as rdone2 \gset
select tt.chk('T7 after the fix the retry creates the order once and closes the failure', :'rdone2'='1' and (select count(*) from online_orders where external_ref=:'sub2')=1
  and (select state from intake_failures where kind='web_order')='done');
select tt.chk('T7 submitting it again afterwards is a dup (no second order)', (web_order_submit('webform',:'sub2'::uuid,'Q','01811000006','x','pickup',format('[{"item_id":"%s","qty":1}]',:'c2')::jsonb,null)->>'dup')::boolean and (select count(*) from online_orders where external_ref=:'sub2')=1);
select tt.as(:'o');
select tt.chk('T7 embed: not configured until the public URL setting exists', (web_form_embed('webform')->>'configured')::boolean is false);
select set_rule('web_form_public_url','"https://example.invalid/fn/web-order"') is null as r9 \gset
select tt.chk('T7 embed: link + iframe code', web_form_embed('webform')->>'link'='https://example.invalid/fn/web-order?c=webform' and web_form_embed('webform')->>'embed' like '<iframe src="https://example.invalid/fn/web-order?c=webform"%');
select tt.as(:'p');
select tt.err('T7 only the owner gets the share link', $$select web_form_embed('webform')$$, 'not allowed');

\echo == T8 duplicates across channels (H6)
select tt.as(:'p');
select count(*) as nflag0 from order_dup_flags \gset
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Dup Cust', '01911000001', null, format('[{"item_id":"%s","qty":1}]', :'c2')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) is not null as d1 \gset
select tt.chk('T8 first order: no flag', (select count(*) from order_dup_flags)=:nflag0);
select online_order_save2(null, gen_random_uuid(), 1, :cfb, 'Dup Cust', '01911000001', null, format('[{"item_id":"%s","qty":2}]', :'c2')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) is not null as d2 \gset
select tt.chk('T8 same customer + same item + same day via a 2nd channel => ONE flag, both orders kept (never merged)', (select count(*) from order_dup_flags)=:nflag0+1
  and (select count(*) from online_orders where customer_mobile='01911000001')=2 and (select state from order_dup_flags order by id desc limit 1)='open');
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Dup Cust', '01911000001', null, format('[{"item_id":"%s","qty":1}]', :'c2')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) is not null as d3 \gset
select tt.chk('T8 a 3rd order on the SAME channel as one of them: flagged only against the other channel', (select count(*) from order_dup_flags where location_id=1 and state='open')>=2);
select online_order_save2(null, gen_random_uuid(), 1, :cfb, 'Other Cust', '01911000002', null, format('[{"item_id":"%s","qty":1}]', :'c1')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) is not null as d4 \gset
select online_order_save2(null, gen_random_uuid(), 1, :cph, 'Other Cust', '01911000002', null, format('[{"item_id":"%s","qty":1}]', :'c2')::jsonb, 'pickup', null, null, 0, 0, 0, null, null, null) is not null as d5 \gset
select tt.chk('T8 same customer, different items: no flag', not exists (select 1 from order_dup_flags f join online_orders a on a.id=f.order_a where a.customer_mobile='01911000002'));
select tt.chk('T8 list shows the open flags', jsonb_array_length(order_dup_flags_list(1,'open'))>=2);
select tt.as(:'s');
select order_dup_flags_list(1,'open')->0->>'id' as fid \gset
select tt.err('T8 review needs a note', format($$select order_dup_flag_review(%s,'')$$, :fid), 'reason_required');
select tt.chk('T8 review closes the flag (orders untouched)', order_dup_flag_review(:'fid'::bigint,'checked: real second order')->>'state'='reviewed');
select tt.err('T8 a flag is never deleted', format($$delete from order_dup_flags where id=%s$$, :fid), 'append_only');

\echo == T9 PII guard + view audit (H6)
select tt.as(:'o'); select count(*) as aud0 from audit_log where action='view' and table_name='online_orders' \gset
select tt.as(:'p');
select (online_orders_list(1,null,null,null,50)->0->>'customer_mobile') is not null as lm, (online_order_get(:'ord1'::uuid)->>'customer_mobile') is not null as gm \gset
select tt.chk('T9 guard OFF: salesperson sees the phone in list and get (today''s behaviour); the view is audited', :'lm' = 't' and :'gm' = 't' and (select count(*) from audit_log where action='view' and table_name='online_orders')>:aud0);
select tt.as(:'o');
select set_rule('inbox_pii_guard_on','true') is null as g1 \gset
select tt.chk('T9 guard ON: direct column read of phone/address revoked from browsers', not has_column_privilege('authenticated','public.online_orders','customer_mobile','select') and not has_column_privilege('authenticated','public.online_orders','address','select'));
select tt.as(:'p');
select tt.chk('T9 guard ON: salesperson without the grant sees NO phone/address (list, get) but sees the order', (online_orders_list(1,null,null,null,50)->0->>'customer_mobile') is null and (online_orders_list(1,null,null,null,50)->0->>'masked')::boolean
  and (online_order_get(:'ord1'::uuid) ? 'customer_mobile') is false and (online_order_get(:'ord1'::uuid)->>'masked')::boolean and (online_order_get(:'ord1'::uuid)->>'order_no') is not null);
select tt.chk('T9 guard ON: inbox shows no text/handle to them', (inbox_get(:m1)->>'text') is null and (inbox_get(:m1)->>'masked')::boolean and (inbox_list(1,null,50)->0->>'text') is null);
select tt.as(:'o');
insert into rule_grants (role_code, grant_code, allowed) values ('showroom_manager','inbox_contact_view',true) on conflict (role_code, grant_code) do update set allowed=true;
select tt.as(:'s'); select count(*) as aud1 from audit_log where action='view' \gset
select online_order_get(:'ord1'::uuid)->>'customer_mobile' as seen_m \gset
select tt.chk('T9 guard ON: a person with the contact grant sees phone + address, and it is audited', :'seen_m'='01711000111' and (select count(*) from audit_log where action='view')>:aud1);
select tt.as(:'t');
select tt.chk('T9 guard ON: the grant holder of another place still sees nothing of place 1', jsonb_array_length(online_orders_list(null,null,null,null,50))=0);
select tt.as(:'o');
select tt.chk('T9 owner always sees', (online_order_get(:'ord1'::uuid)->>'customer_mobile')='01711000111');
select set_rule('inbox_pii_guard_on','false') is null as g2 \gset
select tt.chk('T9 guard OFF again: columns granted back', has_column_privilege('authenticated','public.online_orders','customer_mobile','select'));

\echo == T10 drafts (H5)
select tt.as(:'b'); select inbound_message_receive('whatsapp','PHONEID1','m-draft','8801711000010','Customer D','2 kg rasgulla to Mirpur',now(),null,true) is not null as bb2 \gset
select tt.as(:'p');
select id as m3 from inbound_messages where external_id='m-draft' \gset
select tt.err('T10 draft switch OFF: refused', format($$select online_order_save2(null, gen_random_uuid(), 1, %s, 'Customer D', '01711000010', 'Mirpur', '[{"item_id":"%s","qty":2}]'::jsonb, 'home', null, null, 0, 0, 0, null, null, null, null, null, null, null, null, %s, true)$$, :cwa, :'c1', :m3), 'module_off');
select tt.as(:'o'); select set_rule('inbox_autodraft_on','true') is null as ad \gset
select tt.as(:'p');
select count(*) as sales0 from sales \gset
select coalesce(sum(qty),0) as stock0 from stock_balance where item_id=:'c1'::uuid and location_id=1 \gset
select online_order_save2(null, gen_random_uuid(), 1, :cwa, 'Customer D', '01711000010', 'Mirpur', format('[{"item_id":"%s","qty":2}]', :'c1')::jsonb, 'home', null, null, 0, 0, 0, null, null, null, null, null, null, null, null, :m3, true)->>'draft' as dr \gset
select id as dord from online_orders where inbox_msg_id=:m3 \gset
select tt.chk('T10 draft made: marked draft + the note, message NOT converted (draft link only)', :'dr'='true' and (select is_draft from online_orders where id=:'dord'::uuid) and (select draft_note from online_orders where id=:'dord'::uuid)='খসড়া, যাচাই বাকি'
  and (select status from inbound_messages where id=:m3)='new' and (select draft_order_id from inbound_messages where id=:m3)=:'dord'::uuid and (select linked_order_id from inbound_messages where id=:m3) is null);
select tt.err('T10 a draft cannot be confirmed', format($$select online_order_status('%s','confirmed')$$, :'dord'), 'draft_unverified');
select tt.chk('T10 a draft moves NO stock and makes NO sale', (select count(*) from sales)=:sales0 and (select coalesce(sum(qty),0) from stock_balance where item_id=:'c1'::uuid and location_id=1)=:stock0);
select tt.err('T10 a draft cannot be delivered', format($$select online_order_deliver('%s','[]')$$, :'dord'), '');
select tt.chk('T10 editing a draft keeps it a draft', (online_order_save2(:'dord'::uuid, null, 1, :cwa, 'Customer D', '01711000010', 'Mirpur 10', format('[{"item_id":"%s","qty":3}]', :'c1')::jsonb, 'home', null, null, 0, 0, 0, null, null, null)->>'subtotal')::numeric=300
  and (select is_draft from online_orders where id=:'dord'::uuid));
select online_order_draft_verify(:'dord'::uuid, 'checked with customer') is not null as vv \gset
select tt.chk('T10 verified by a person: no longer a draft, message converted + linked', not (select is_draft from online_orders where id=:'dord'::uuid) and (select draft_verified_by from online_orders where id=:'dord'::uuid)=:'p'::uuid
  and (select status from inbound_messages where id=:m3)='converted' and (select linked_order_id from inbound_messages where id=:m3)=:'dord'::uuid);
select tt.chk('T10 after verification the normal flow works (confirm)', online_order_status(:'dord'::uuid,'confirmed')->>'status'='confirmed');

\echo == T11 order -> sale (H7: deliver unchanged, new columns do not disturb it)
select online_order_status(:'dord'::uuid,'packed')->>'status' as pk \gset
select online_order_deliver(:'dord'::uuid, '[{"mode":"cash","amount":300}]')->>'sale_id' as dsale \gset
select tt.chk('T11 one delivery = one sale, total 300, stock cut once (-3), order delivered with the sale id', (select count(*) from sales)=:sales0+1 and (select total from sales where id=:'dsale'::uuid)=300
  and (select coalesce(sum(qty),0) from stock_balance where item_id=:'c1'::uuid and location_id=1)=:stock0-3 and (select status from online_orders where id=:'dord'::uuid)='delivered');
select tt.chk('T11 deliver again = dup, no second sale / cut', (online_order_deliver(:'dord'::uuid,'[]')->>'dup')::boolean and (select count(*) from sales)=:sales0+1
  and (select coalesce(sum(qty),0) from stock_balance where item_id=:'c1'::uuid and location_id=1)=:stock0-3);

\echo == T12 board (H6)
select tt.as(:'o'); select _intake_fail('message', null, 'board-x', 'e', '{}') as bfid \gset
select tt.as(:'s');
select inbox_board(1)::text as bd \gset
select tt.chk('T12 board: new message count, last message time, failed count, dup flags, switch', (:'bd'::jsonb->>'on')::boolean and (:'bd'::jsonb->>'new_count')::int=(select count(*) from inbound_messages where status='new' and location_id=1)
  and (:'bd'::jsonb->>'last_at') is not null and (:'bd'::jsonb->>'failed_count')::int>=1 and (:'bd'::jsonb->>'dup_open')::int>=1 and jsonb_array_length(:'bd'::jsonb->'channels')=3);
select tt.chk('T12 no silence warning right after a message', not (:'bd'::jsonb->>'silent')::boolean);
alter table inbound_messages disable trigger inbound_messages_ro76;
update inbound_messages set received_at = now() - interval '30 hours';
alter table inbound_messages enable trigger inbound_messages_ro76;
select tt.chk('T12 silence warning when no message for longer than the setting (24h, test data aged 30h)', (inbox_board(1)->>'silent')::boolean and (inbox_board(1)->>'hours_since')::numeric>=30);
select tt.as(:'o'); select set_rule('inbox_silence_hours','0') is null as sh \gset
select tt.chk('T12 silence limit 0 = warning off', not (inbox_board(1)->>'silent')::boolean);
select tt.as(:'o'); select set_rule('inbox_on','false') is null as off1 \gset
select tt.chk('T12 inbox off: board says off', not (inbox_board(1)->>'on')::boolean);

\echo == T13 trails and immutability
select tt.err('T13 a received message text cannot be changed', $$update inbound_messages set msg_text='x'$$, 'append_only');
select tt.err('T13 a message is never deleted', $$delete from inbound_messages$$, 'append_only');
select tt.err('T13 message trail is append-only', $$update inbound_message_events set note='x'$$, 'append_only');
select tt.chk('T13 converted message cannot go back', (select count(*) from inbound_messages where status='converted')>=2);

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
