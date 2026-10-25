select :'mode'='rec' as isrec \gset
\echo == 08 channels: web order via intake bot, telegram intake, inbox PII
select tt.as(:'o');
select sales_channel_save(null,'webform','web_form',null,'Web form',1,null,null,true) is not null as c1 \gset
select sales_channel_save(null,'tg1','telegram',null,'Telegram shop',1,null,'BOT1',true) is not null as c2 \gset
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null as c3 \gset
select id as ctg from sales_channels where code='tg1' \gset
select id as cweb from sales_channels where code='webform' \gset
\if :isrec
select setup_recommend_apply('aaaaaaaa-0000-0000-0000-00000000e2e3'::uuid) as ap3 \gset
select tt.t('CH0 after channels exist, setup_recommend_apply turns on online_orders_on / inbox_on / web_form_on', rule_on('online_orders_on') and rule_on('inbox_on') and rule_on('web_form_on'), 'all 3 on', rule_on('online_orders_on')::text||'/'||rule_on('inbox_on')::text||'/'||rule_on('web_form_on')::text);
\endif
select set_rule('online_orders_on','true') is null as r1 \gset
select set_rule('inbox_on','true') is null as r2 \gset
select set_rule('web_form_on','true') is null as r3 \gset
select set_rule('telegram_intake_on','true') is null as r4 \gset
select set_rule('meta_intake_on','true') is null as r5 \gset
select intake_bot_create(:'bt'::uuid, 1) is not null as ib \gset
select _tg_hash('test_secret_token_AAAA1111bbbb') as hgood \gset
select telegram_secret_set(:ctg, 'test_secret_token_AAAA1111bbbb') is not null as tss \gset

\echo -- web order
select tt.as(:'bt');
select gen_random_uuid() as sub1 \gset
select web_order_submit('webform', :'sub1'::uuid, 'Web Cust', '01811000001', 'Dhaka 5', 'home', format('[{"item_id":"%s","qty":2,"price":1}]', tt.iid('FG-CAKE'))::jsonb, 'please call') as w1 \gset
select tt.t('W1 web order accepted', (:'w1'::jsonb->>'ok')::boolean, 'ok', :'w1');
select tt.eq('W1 server price: 2 kg x 300 (client price 1 ignored)', 600, (:'w1'::jsonb->>'subtotal')::numeric);
select web_order_submit('webform', :'sub1'::uuid, 'Web Cust', '01811000001', 'Dhaka 5', 'home', format('[{"item_id":"%s","qty":2,"price":1}]', tt.iid('FG-CAKE'))::jsonb, 'please call') ->> 'dup' as w1d \gset
select tt.is('W1 same submission twice = dup', 'true', :'w1d');
select tt.eq('W1 one online order row', 1, (select count(*) from online_orders where external_ref=:'sub1'));
select id as ooid from online_orders where external_ref=:'sub1' \gset
\echo -- intake bot cannot sell
select tt.err('W2 intake bot cannot record a sale', format($$select record_sale2(gen_random_uuid(),1,'[{"item_id":"%s","qty":1,"price":300}]'::jsonb,0,'[{"mode":"cash","amount":300}]',null,null,'retail',null,false)$$, tt.iid('FG-CAKE')), 'not allowed');
select tt.err('W2 intake bot cannot deliver the order (create a sale)', format($$select online_order_deliver('%s'::uuid,'[{"mode":"cash","amount":600}]')$$, :'ooid'), 'not allowed');
select tt.err('W2 intake bot cannot read stock levels / cost', $$select stock_valuation(1)$$, 'not allowed');

\echo -- order -> stock out once
select tt.as(:'o');
select tt.eq('W3 cake before 26', 26, tt.qty('FG-CAKE'));
select count(*) as n_sales0 from sales \gset
select count(*) as n_out0 from stock_ledger where item_id=tt.iid('FG-CAKE') and reason='sale_out' \gset
select online_order_status(:'ooid'::uuid,'confirmed') is not null as st1 \gset
select online_order_status(:'ooid'::uuid,'packed') as st2 \gset
select tt.eq('W3 confirmed + packed: stock untouched (26)', 26, tt.qty('FG-CAKE'));
select online_order_deliver(:'ooid'::uuid,'[{"mode":"cash","amount":600}]') as dv \gset
select tt.eq('W3 after delivery stock 26-2', 24, tt.qty('FG-CAKE'));
select online_order_deliver(:'ooid'::uuid,'[{"mode":"cash","amount":10}]') ->> 'dup' as dvd \gset
select tt.is('W3 deliver again = dup', 'true', :'dvd');
select tt.eq('W3 stock still 24 (stock out once)', 24, tt.qty('FG-CAKE'));
select tt.eq('W3 exactly one new sale row (after deliver + dup deliver)', :n_sales0::int+1, (select count(*) from sales));
select tt.eq('W3 exactly one new cake sale_out ledger row', :n_out0::int+1, (select count(*) from stock_ledger where item_id=tt.iid('FG-CAKE') and reason='sale_out'));
select tt.eq('W3 online order is linked to that sale', 1, (select count(*) from online_orders where id=:'ooid'::uuid and sale_id is not null));

\echo -- telegram intake
select tt.as(:'bt');
select telegram_message_receive('tg1',:'hgood',1001,555,'user_a','Chat A','I want 2 kg sweets',now(),null) as t1 \gset
select telegram_message_receive('tg1',:'hgood',1001,555,'user_a','Chat A','I want 2 kg sweets',now(),null) ->> 'duplicate' as t1d \gset
select tt.is('T1 same update_id twice = duplicate', 'true', :'t1d');
select tt.eq('T1 one inbox row for update 1001', 1, (select count(*) from inbound_messages where external_id='1001'));
select telegram_message_receive('tg1',:'hgood',1002,555,'user_a','Chat A','second',now(),'photo:F1') ->> 'duplicate' as t2d \gset
select tt.eq('T1 new update id = new row', 2, (select count(*) from inbound_messages where channel_id=:ctg));
select tt.is('T1 wrong secret rejected (bad_signature), nothing stored', 'bad_signature', telegram_message_receive('tg1',repeat('0',64),1003,555,'user_a','Chat A','x',now(),null)->>'rejected');
select tt.eq('T1 inbox rows for telegram still 2', 2, (select count(*) from inbound_messages where channel_id=:ctg));

\echo -- inbox PII mask + unmask audit
select inbound_message_receive('facebook','PAGE1','m-1','01711000111','Customer A','I want 2 kg sweets, call 01711000111',now(),null,true) as fm1 \gset
select id as m1 from inbound_messages where external_id='m-1' \gset
select tt.as(:'o');
select rule_txt('inbox_pii_mode') as pii0 \gset
\echo INBOX_PII_MODE_AT_START=:pii0
select tt.as(:'sp');
select inbox_get(:m1)->>'handle' as h0 \gset
select tt.is('P1 mode at start: handle shown clear only when mode is off', case when :'pii0'='off' then '01711000111' else '••••••••111' end, :'h0');
select tt.as(:'o'); select set_rule('inbox_pii_mode','"mask_phone_address"') is null as pm \gset
select tt.as(:'sp');
select tt.is('P2 mask_phone_address: handle masked', '••••••••111', inbox_get(:m1)->>'handle');
select tt.is('P2 online order mobile masked (last 3 digits)', '••••••••001', online_order_get(:'ooid'::uuid)->>'customer_mobile');
select tt.is('P2 online order address hidden', '••••', online_order_get(:'ooid'::uuid)->>'address');
select tt.err('P3 salesperson without inbox_unmask cannot reveal', format($$select inbox_unmask('message','%s')$$, :m1), 'not allowed');
select tt.as(:'rv');
select inbox_unmask('message', :m1::text, 'customer called') as um \gset
select tt.is('P3 grant holder reveals real handle', '01711000111', :'um'::jsonb->'data'->>'handle');
select tt.eq('P3 unmask log row (who, reason)', 1, (select count(*) from inbox_unmask_log99 where user_id=:'rv'::uuid and kind='message' and reason='customer called' and outcome='revealed'));
select tt.eq('P3 audit_log row', 1, (select count(*) from audit_log where table_name='inbox_unmask' and record_id='message:'||:m1::text and user_id=:'rv'::uuid));
select tt.is('P3 next plain read masked again', '••••••••111', inbox_get(:m1)->>'handle');
select tt.as(:'o');
select acct_post_pending(false) as pp10 \gset
\echo POST_PENDING_10: :pp10
