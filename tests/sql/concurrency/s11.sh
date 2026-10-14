#!/bin/bash
# S11 intake: the same Telegram update_id / Meta message id / web-form submission from N sessions -> one row
. "$(dirname "$0")/lib.sh"; N=${N:-30}
id=S11; db=cc_s11; newdb $db
sqf $db $O >/dev/null <<SQL
select sales_channel_save(null,'webform','web_form',null,'Web form',1,null,null,true) is not null;
select sales_channel_save(null,'tg1','telegram',null,'Telegram shop',1,null,'BOT1',true) is not null;
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null;
select set_rule('online_orders_on','true'); select set_rule('inbox_on','true'); select set_rule('web_form_on','true'); select set_rule('telegram_intake_on','true'); select set_rule('meta_intake_on','true');
select intake_bot_create('$BT'::uuid, 1) is not null;
select telegram_secret_set((select id from sales_channels where code='tg1'), 'test_secret_token_AAAA1111bbbb') is not null;
SQL
h=$(psql -qAtX -d $db -c "select _tg_hash('test_secret_token_AAAA1111bbbb')"); cake=$(itm $db FG-BULK); sub=$(cat /proc/sys/kernel/random/uuid)
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $BT "
select 'T|'||coalesce(telegram_message_receive('tg1','$h',555001,777,'user_a','Chat A','I want 2 kg sweets',now(),null)->>'duplicate','?') where :i % 3 = 0;
select 'M|'||coalesce(inbound_message_receive('facebook','PAGE1','mid-1','01711000111','Cust A','hello',now(),null,true)->>'duplicate','?') where :i % 3 = 1;
select 'W|'||coalesce(web_order_submit('webform','$sub'::uuid,'Web Cust','01811000001','Dhaka 5','home','[{\"item_id\":\"$cake\",\"qty\":2,\"price\":1}]'::jsonb,'call')->>'dup','fresh') where :i % 3 = 2;
" $id
errs $id 4
ck $id.tg "telegram update_id 555001 x$((N/3)) sessions -> 1 inbound row" $db "select count(*)=1 from inbound_messages where external_id='555001'" "select 'rows='||count(*)||' dup_replies='||$(cnt_out $id '^T|true')||' fresh='||$(cnt_out $id '^T|false') from inbound_messages where external_id='555001'"
ck $id.meta "facebook message id 'mid-1' -> 1 inbound row" $db "select count(*)=1 from inbound_messages where external_id='mid-1'" "select 'rows='||count(*) from inbound_messages where external_id='mid-1'"
ck $id.web "web form submission uuid -> 1 online order" $db "select count(*)=1 from online_orders where external_ref='$sub'" "select 'rows='||count(*)||' dup='||$(cnt_out $id '^W|true')||' fresh='||$(cnt_out $id '^W|false') from online_orders where external_ref='$sub'"
ck $id.err "no session error (unique violation must be absorbed as duplicate)" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
# 20+ sessions on the SAME telegram update only
id=S11b; d0=$(deadlocks $db)
race $db $N $BT "select 'T|'||coalesce(telegram_message_receive('tg1','$h',555002,777,'user_a','Chat A','again',now(),null)->>'duplicate','?');" $id
ck $id.tg "telegram update_id 555002 from all $N sessions -> 1 row, no error" $db "select count(*)=1 and $(cat $OUT/$id/*.err | grep -c ERROR)=0 from inbound_messages where external_id='555002'" "select 'rows='||count(*)||' dup='||$(cnt_out $id '^T|true')||' fresh='||$(cnt_out $id '^T|false')||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR) from inbound_messages where external_id='555002'"
