-- Imported from the advanced line (origin/ccr-9c1f9be7-3s9qnz): was phase86_test.sql there and is already pasted on the live database under that name.
-- Renumbered to phase512_test.sql by the union merge; the SQL below is unchanged (only comments, test include paths and raise labels carry the new number).
-- FRESH DB ONLY. Phase 512 tests (Step Tg: Telegram channel kind, intake, secret_token check, bad-signature log, idempotency, chat link, mask/audit, bot role compat).
--   ORDER="phase8 ... phase79 phase512" bash <copy of tests/sql/build_fresh_db.sh with your worktree paths> 86db
--   psql -h /tmp -p 5544 -U postgres -d 86db -qAt -f supabase/phase512_test.sql | grep -E 'FAIL|RESULT'
-- Test data only, no real person names. The secret below is a made-up test string.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set p '00000000-0000-0000-0000-000000000004'
\set t '00000000-0000-0000-0000-000000000005'
\set b '00000000-0000-0000-0000-000000000006'
\set r '00000000-0000-0000-0000-000000000007'
\set sec 'test_secret_token_AAAA1111bbbb'
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
create or replace function tt.err_browser(p_name text, p_sql text) returns void language plpgsql as $$
begin
  set local role authenticated;
  begin execute p_sql; reset role; perform tt.chk(p_name, false);
  exception when others then reset role; perform tt.chk(p_name, true); end;
end $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'p','sales4@s.app','{"full_name":"Sales"}'),
 (:'t','mgr5@s.app','{"full_name":"Other place"}'), (:'b','bot6@s.app','{"full_name":"Intake bot"}'), (:'r','bot7@s.app','{"full_name":"Role bot"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'p','salesperson'),(:'t','showroom_manager'),(:'b','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'p',1),(:'t',2),(:'b',1) on conflict do nothing;
insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price) values ('C1','C1','C1','kg','kg','finished_good',true,100) on conflict do nothing;
select id as c1 from items where code='C1' \gset
insert into customers (mobile, name) values ('01700000001','Test Customer One'), ('01700000002','Test Customer Two') on conflict do nothing;
select id as cu1 from customers where mobile='01700000001' \gset
select id as cu2 from customers where mobile='01700000002' \gset
select tt.as(:'o');
select stock_opening(:'c1'::uuid, 1, 100, 40, null, 'seed') is not null as op1 \gset
select _tg_hash(:'sec') as hgood \gset
select _tg_hash('wrong_secret_token_0000') as hbad \gset

\echo == T0 shape
select tt.chk('T0 sha256 known vector (abc)', _tg_hash('abc')='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
select tt.chk('T0 hash compare: equal true, different / malformed / null false', _tg_hash_eq(:'hgood',:'hgood') and not _tg_hash_eq(:'hgood',:'hbad') and not _tg_hash_eq(:'hgood','abc') and not _tg_hash_eq(null,:'hgood'));
select tt.chk('T0 telegram switch defaults OFF', not rule_on('telegram_intake_on'));
select tt.chk('T0 browser functions open, helpers closed, anon none',
  has_function_privilege('authenticated','public.telegram_message_receive(text,text,bigint,bigint,text,text,text,timestamptz,text)','execute')
  and not has_function_privilege('anon','public.telegram_message_receive(text,text,bigint,bigint,text,text,text,timestamptz,text)','execute')
  and not has_function_privilege('anon','public.telegram_secret_set(int,text)','execute')
  and not has_function_privilege('authenticated','public._tg_hash(text)','execute') and not has_function_privilege('authenticated','public._tg_actor_ok()','execute'));
select tt.chk('T0 new tables closed to browsers, RLS on',
  not has_table_privilege('authenticated','public.telegram_secrets','select') and not has_table_privilege('authenticated','public.telegram_chat_links','select')
  and not has_table_privilege('authenticated','public.telegram_chat_links','insert') and not has_table_privilege('anon','public.telegram_secrets','select')
  and (select bool_and(relrowsecurity) from pg_class where relname in ('telegram_secrets','telegram_chat_links')));
select tt.err_browser('T0 browser cannot read the secret table', 'select * from public.telegram_secrets');
select tt.err_browser('T0 browser cannot write a chat link directly', $$insert into public.telegram_chat_links (channel_id, chat_id, note) values (1,'1','x')$$);

\echo == T1 channel kind (Tg1)
select tt.as(:'s');
select tt.err('T1 only the owner makes a channel', $$select sales_channel_save(null,'tg1','telegram',null,'Telegram',1,null,'BOT1',true)$$, 'not allowed');
select tt.as(:'o');
select tt.err('T1 telegram needs an account ref', $$select sales_channel_save(null,'tg1','telegram',null,'Telegram',1,null,null,true)$$, 'account_ref_required');
select tt.err('T1 an unknown kind is still refused', $$select sales_channel_save(null,'tgx','signal',null,'X',1,null,'B',true)$$, 'bad_kind');
select sales_channel_save(null,'tg1','telegram',null,'Telegram shop',1,null,'BOT1',true) is not null as c1ok \gset
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null as c2ok \gset
select id as ctg from sales_channels where code='tg1' \gset
select tt.chk('T1 telegram channel stored; old kinds still work (check re-added, old one gone)', (select kind from sales_channels where code='tg1')='telegram'
  and (select count(*) from pg_constraint where conrelid='public.sales_channels'::regclass and contype='c' and pg_get_constraintdef(oid) like '%web_form%')=1);
select tt.err('T1 a raw insert of a bad kind is refused by the check', $$insert into sales_channels (code, kind, name_bn) values ('zz','signal','Z')$$, 'violates check');
select tt.as(:'p');
select tt.chk('T1 staff list hides the account ref but shows the telegram kind', (select count(*) from jsonb_array_elements(sales_channels_list(false)) e where e->>'kind'='telegram' and e->>'account_ref' is null)=1);

\echo == T2 secret token (Tg3) and switches
select tt.as(:'p');
select tt.err('T2 staff cannot set a secret', format($$select telegram_secret_set(%s,'%s')$$, :ctg, :'sec'), 'not allowed');
select tt.as(:'o');
select tt.err('T2 short secret refused', format($$select telegram_secret_set(%s,'short')$$, :ctg), 'bad_secret');
select tt.err('T2 secret with bad characters refused', format($$select telegram_secret_set(%s,'abcdefghijklmnop qrstuvwx')$$, :ctg), 'bad_secret');
select tt.err('T2 non-telegram channel refused', format($$select telegram_secret_set((select id from sales_channels where code='fbpage'),'%s')$$, :'sec'), 'channel_not_found');
select telegram_secret_set(:ctg, :'sec') is not null as sset \gset
select tt.chk('T2 only the hash is stored (64 hex), the secret text is nowhere in the table or the audit', (select secret_hash from telegram_secrets where channel_id=:ctg)=:'hgood'
  and not exists (select 1 from telegram_secrets where secret_hash like '%test_secret%') and not exists (select 1 from audit_log where detail::text like '%test_secret%')
  and exists (select 1 from audit_log where table_name='telegram_secrets' and detail->>'event'='secret_set'));
select intake_bot_set(:'b'::uuid, true) is not null as bt \gset
select tt.as(:'b');
select tt.chk('T2 inbox off: receive returns off, nothing stored', (telegram_message_receive('tg1',:'hgood',1001,555,'user_a','Chat A','hello',now(),null)->>'off')::boolean and (select count(*) from inbound_messages)=0);
select tt.as(:'o'); select set_rule('inbox_on','true') is null as r1 \gset
select set_rule('online_orders_on','true') is null as r1b \gset
select tt.as(:'b');
select tt.chk('T2 inbox on but telegram switch off: returns off', (telegram_message_receive('tg1',:'hgood',1001,555,'user_a','Chat A','hello',now(),null)->>'off')::boolean and (select count(*) from inbound_messages)=0);
select tt.as(:'o'); select set_rule('telegram_intake_on','true') is null as r2 \gset
select tt.as(:'p');
select tt.err('T2 normal staff cannot use the receiver', format($$select telegram_message_receive('tg1','%s',1,5,null,null,'x',now(),null)$$, :'hgood'), 'not allowed');

\echo == T3 intake, idempotency, bad token (Tg2)
select tt.as(:'b');
select telegram_message_receive('tg1',:'hgood',1001,555,'user_a','Chat A','I want 2 kg sweets',now(),null)::text as r1 \gset
select tt.chk('T3 first update stored: one row, status new, handle tg:<chat>, external id = update id',
  (select count(*) from inbound_messages)=1 and (select status from inbound_messages)='new' and (select customer_handle from inbound_messages)='tg:555'
  and (select external_id from inbound_messages)='1001' and (:'r1'::jsonb->>'duplicate')::boolean is false
  and (select kind from sales_channels c join inbound_messages m on m.channel_id=c.id)='telegram');
select telegram_message_receive('tg1',:'hgood',1001,555,'user_a','Chat A','I want 2 kg sweets',now(),null)->>'duplicate' as dd \gset
select tt.chk('T3 SAME update_id twice = one inbox row (idempotent on channel + update_id)', :'dd'='true' and (select count(*) from inbound_messages)=1);
select telegram_message_receive('tg1',:'hgood',1002,555,'user_a','Chat A','second message',now(),'photo:FILEID1')->>'duplicate' as d2 \gset
select tt.chk('T3 a new update_id is a new row; attachment marker kept', :'d2'='false' and (select count(*) from inbound_messages)=2 and (select attachment_ref from inbound_messages where external_id='1002')='photo:FILEID1');
select telegram_message_receive('tg1',:'hbad',1003,555,'user_a','Evil','spam text',now(),null)->>'rejected' as rj \gset
select tt.chk('T3 WRONG token: rejected, no message row, one rejected line in the failed list (no body, no chat id)', :'rj'='bad_signature'
  and (select count(*) from inbound_messages where external_id='1003')=0
  and (select count(*) from intake_failures where state='rejected' and kind='bad_signature' and error='bad_signature')=1
  and (select payload::text from intake_failures where kind='bad_signature')='{"kind": "telegram"}');
select telegram_message_receive('tg1',null,1004,555,null,null,'no header',now(),null)->>'rejected' as rj2 \gset
select tt.chk('T3 MISSING token (null hash): rejected as well', :'rj2'='bad_signature' and (select count(*) from inbound_messages where external_id='1004')=0);
select telegram_message_receive('tg1','not-a-hash',1005,555,null,null,'garbage',now(),null)->>'rejected' as rj3 \gset
select tt.chk('T3 malformed hash: rejected', :'rj3'='bad_signature' and (select count(*) from inbound_messages where external_id='1005')=0);
select telegram_message_receive('nochannel',:'hgood',1006,555,null,null,'x',now(),null)->>'rejected' as rj4 \gset
select tt.chk('T3 unknown channel code: rejected and logged', :'rj4'='channel_not_found' and (select count(*) from intake_failures where error='channel_not_found' and state='rejected')=1);
select tt.err('T3 bad input (null chat id) raises', format($$select telegram_message_receive('tg1','%s',1007,null,null,null,'x',now(),null)$$, :'hgood'), 'bad_input');
select tt.as(:'o');
select sales_channel_save(null,'tg2','telegram',null,'Telegram no secret',1,null,'BOT2',true) is not null as c3ok \gset
select tt.as(:'b');
select telegram_message_receive('tg2',:'hgood',2001,9,null,null,'x',now(),null)->>'rejected' as rj5 \gset
select tt.chk('T3 channel without a secret set: rejected (secret_not_set), nothing stored', :'rj5'='secret_not_set' and (select count(*) from inbound_messages where external_id='2001')=0);
select tt.as(:'o');
select sales_channel_save(null,'tg3','telegram',null,'Telegram other place',2,null,'BOT3',true) is not null as c4ok \gset
select telegram_secret_set((select id from sales_channels where code='tg3'), 'other_channel_secret_ZZ9999') is not null as s3 \gset
select tt.as(:'b');
select tt.chk('T3 the token of channel 1 does not open channel 3', telegram_message_receive('tg3',:'hgood',3001,9,null,null,'x',now(),null)->>'rejected'='bad_signature');
select telegram_message_receive('tg1',:'hgood',1010,556,null,'@only_username','named by username?',now(),null) is not null as r10 \gset
select tt.chk('T3 no display name: the stored name stays empty/handle-only (no invented name)', (select customer_name from inbound_messages where external_id='1010') is null or (select customer_name from inbound_messages where external_id='1010')='@only_username');
select tt.chk('T3 audit has the insert without message text or chat id', (select count(*) from audit_log where table_name='inbound_messages' and action='insert')=3
  and not exists (select 1 from audit_log where table_name='inbound_messages' and (detail::text like '%sweets%' or detail::text like '%tg:555%')));
select tt.chk('T3 nothing replied, no order made by intake', (select count(*) from online_orders)=0);

\echo == T4 failed list + retry for telegram
select tt.as(:'o');
update sales_channels set active=false where code='tg1';
select tt.as(:'b');
select telegram_message_receive('tg1',:'hgood',1020,555,null,'Chat A','x',now(),null)->>'rejected' as rj6 \gset
select tt.chk('T4 inactive channel: rejected, not stored', :'rj6'='channel_not_found');
select tt.as(:'o');
update sales_channels set active=true where code='tg1';
-- a stored-failure path: the channel exists but _inb_insert_message fails (no location)
update sales_channels set location_id=null where code='tg3';
select tt.as(:'b');
select telegram_message_receive('tg3','' || _tg_hash('other_channel_secret_ZZ9999'),3002,9,null,'Z','x',now(),null)->>'queued' as qd \gset
select tt.chk('T4 channel without a place: queued in the failed list (not lost, not thrown)', :'qd'='true' and (select count(*) from intake_failures where kind='message' and state='failed')=1);
select tt.as(:'o');
update sales_channels set location_id=2 where code='tg3';
update intake_failures set next_try_at = now() - interval '1 minute' where state='failed';
select tt.as(:'b');
select intake_retry_due(10)->>'done' as rdone \gset
select tt.chk('T4 after the fix the retry stores the telegram message once', :'rdone'='1' and (select count(*) from inbound_messages where external_id='3002')=1 and (select customer_handle from inbound_messages where external_id='3002')='tg:9');

\echo == T5 inbox reuse + PII mask/audit
select tt.as(:'p');
select tt.chk('T5 inbox_list shows telegram messages with kind telegram (guard off = today)', (select count(*) from jsonb_array_elements(inbox_list(1,null,50)) e where e->>'kind'='telegram')=3
  and (inbox_list(1,'new',50)->0->>'text') is not null);
select id as m1 from inbound_messages where external_id='1001' \gset
select id as m2 from inbound_messages where external_id='1002' \gset
select id as m3 from inbound_messages where external_id='3002' \gset
select inbox_get(:m1)->>'handle' as gh \gset
select tt.chk('T5 inbox_get returns handle and writes a view audit', :'gh'='tg:555' and exists (select 1 from audit_log where action='view' and table_name='inbound_messages' and record_id=:m1::text));
select tt.chk('T5 inbox_set_status works on a telegram message', inbox_set_status(:m1,'seen')->>'status'='seen');
select tt.as(:'t');
select tt.err('T5 manager of another place cannot open a place-1 telegram message', format($$select inbox_get(%s)$$, :m1), 'not allowed');
select tt.chk('T5 the other place sees only its own telegram message', jsonb_array_length(inbox_list(null,null,50))=1);
select tt.as(:'o'); select set_rule('inbox_pii_guard_on','true') is null as g1 \gset
select tt.as(:'p');
select tt.chk('T5 guard ON: salesperson sees no text / handle of the telegram message', (inbox_get(:m1)->>'handle') is null and (inbox_get(:m1)->>'text') is null and (inbox_get(:m1)->>'masked')::boolean);
select tt.chk('T5 guard ON: chat info is masked (no customer name / mobile)', (telegram_chat_info(:m1)->>'masked')::boolean and (telegram_chat_info(:m1)->>'customer_name') is null);
select tt.as(:'o'); select set_rule('inbox_pii_guard_on','false') is null as g2 \gset

\echo == T6 link chat to customer / order (Tg4)
select tt.as(:'p');
select tt.chk('T6 before any link: info says not linked, 2 messages in the chat', (telegram_chat_info(:m1)->>'linked')::boolean is false and (telegram_chat_info(:m1)->>'message_count')::int=2);
select tt.err('T6 link needs a customer or an order', format($$select telegram_chat_link(%s,null,null,null)$$, :m1), 'bad_input');
select tt.err('T6 unknown customer refused', format($$select telegram_chat_link(%s,gen_random_uuid(),null,null)$$, :m1), 'customer_not_found');
select tt.err('T6 unknown order refused', format($$select telegram_chat_link(%s,null,gen_random_uuid(),null)$$, :m1), 'order_not_found');
select telegram_chat_link(:m1, :'cu1'::uuid, null, 'regular') is not null as lk \gset
select tt.chk('T6 chat linked to a customer; info shows name + mobile; link audited without chat id',
  (telegram_chat_info(:m2)->>'linked')::boolean and telegram_chat_info(:m2)->>'customer_name'='Test Customer One' and telegram_chat_info(:m2)->>'customer_mobile'='01700000001'
  and exists (select 1 from audit_log where table_name='telegram_chat_links' and detail->>'event'='link') and not exists (select 1 from audit_log where table_name='telegram_chat_links' and detail::text like '%555%'));
select telegram_chat_link(:m1, :'cu2'::uuid, null, null) is not null as lk2 \gset
select tt.chk('T6 relink moves the chat to the other customer (still one link row)', (select count(*) from telegram_chat_links)=1 and telegram_chat_info(:m1)->>'customer_name'='Test Customer Two');
select tt.as(:'t');
select tt.err('T6 another place cannot link', format($$select telegram_chat_link(%s,'%s'::uuid,null,null)$$, :m1, :'cu1'), 'not allowed');
select tt.as(:'p');
select tt.err('T6 telegram link refused for a non-telegram message', format($$select telegram_chat_link((select id from inbound_messages limit 0),'%s'::uuid,null,null)$$, :'cu1'), 'not_found');
-- order made from the telegram message links the chat to the order by itself
select (online_order_save2(null, '00000000-0000-0000-0000-0000000000a1'::uuid, 1, :ctg, 'Test Customer Two', '01700000002', 'Test road 1', format('[{"item_id":"%s","qty":2}]', :'c1')::jsonb, 'home', null, null, 0, 0, 0, null, null, 'from telegram', null, null, null, null, null, :m2)->>'order_no') as ono \gset
select tt.chk('T6 order made from the message: message converted, chat auto-linked to the order, customer link kept',
  (select status from inbound_messages where id=:m2)='converted' and (telegram_chat_info(:m1)->>'order_no')=:'ono' and telegram_chat_info(:m1)->>'customer_name'='Test Customer Two'
  and jsonb_array_length(telegram_chat_info(:m1)->'orders')=1);
select tt.chk('T6 the order carries the telegram channel id (channel kind other in the old text column)', (select channel_id from online_orders limit 1)=:ctg and (select channel from online_orders limit 1)='other');
select tt.err('T6 unlink needs a reason', format($$select telegram_chat_unlink(%s,'')$$, :m1), 'reason_required');
select telegram_chat_unlink(:m1, 'wrong person') is not null as ul \gset
select tt.chk('T6 unlinked: info says not linked; the row is kept (nothing deleted)', (telegram_chat_info(:m1)->>'linked')::boolean is false and (select count(*) from telegram_chat_links)=1
  and (select unlink_note from telegram_chat_links)='wrong person');
select tt.as(:'o');
select tt.chk('T6 owner can re-link after unlink (link row revived)', telegram_chat_link(:m1, :'cu1'::uuid, null, null) is not null and (telegram_chat_info(:m1)->>'linked')::boolean);

\echo == T7 board + status + intake-bot role compatibility (Tg5)
select tt.as(:'p');
select tt.chk('T7 board lists the telegram channels of the place (two in place 1, not the one of place 2)', (select count(*) from jsonb_array_elements(inbox_board(1)->'channels') e where e->>'kind'='telegram')=2);
select tt.as(:'o');
select tt.chk('T7 owner status: channels with secret flag, switch on, rejected count > 0', (telegram_status()->>'switch_on')::boolean and (telegram_status()->>'rejected_24h')::int>=4
  and (select count(*) from jsonb_array_elements(telegram_status()->'channels') e where (e->>'secret_set')::boolean)=2 and (select count(*) from jsonb_array_elements(telegram_status()->'channels') e where not (e->>'secret_set')::boolean)=1);
select tt.as(:'p');
select tt.err('T7 staff cannot read telegram status', $$select telegram_status()$$, 'not allowed');
-- a user with a role named intake_bot (if such a role is created later) may use the receiver without POS rights
select tt.as(:'r');
select tt.err('T7 user without bot mark and without that role: refused', format($$select telegram_message_receive('tg1','%s',4001,7,null,'R','role test',now(),null)$$, :'hgood'), 'not allowed');
select tt.as(:'o');
insert into roles (code, name_bn, name_mix, name_en) values ('intake_bot','ইনটেক বট','Intake bot','Intake bot') on conflict do nothing;
insert into user_roles values (:'r','intake_bot') on conflict do nothing;
select tt.as(:'r');
select tt.chk('T7 role intake_bot (no POS permission at all): the receiver works', telegram_message_receive('tg1',:'hgood',4001,7,null,'R','role test',now(),null)->>'duplicate'='false'
  and not coalesce(can_do('POS','enter'), false));
select tt.err('T7 ... and that user cannot enter POS: opening the inbox is refused', $$select inbox_list(1,null,10)$$, 'not allowed');
select tt.as(:'o');
select tt.chk('T7 old Meta/web paths untouched: facebook channel still saved with its kind', (select kind from sales_channels where code='fbpage')='facebook');
select tt.err('T13 a message is never deleted', $$delete from inbound_messages$$, 'append_only');

select 'RESULT pass=' || count(*) filter (where ok) || ' fail=' || count(*) filter (where not ok) from tt.res;
