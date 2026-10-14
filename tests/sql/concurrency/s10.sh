#!/bin/bash
# S10 inbox_unmask: daily maximum (rule inbox_unmask_daily_max, phase99) under parallel calls by one grant holder
. "$(dirname "$0")/lib.sh"; N=${N:-30}; MAX=5
setup() { newdb $1
sqf $1 $O >/dev/null <<SQL
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true) is not null;
select set_rule('inbox_on','true'); select set_rule('online_orders_on','true'); select set_rule('web_form_on','true'); select set_rule('meta_intake_on','true');
select intake_bot_create('$BT'::uuid, 1) is not null;
select set_rule('inbox_pii_mode','"mask_phone_address"');
select set_rule('inbox_unmask_daily_max','$MAX');
SQL
for k in $(seq 1 $N); do sq $1 $BT "select inbound_message_receive('facebook','PAGE1','m-$k','0171100$k','Cust $k','I want 2 kg sweets, call 0171100$k',now(),null,true)" >/dev/null; done
}
id=S10; db=cc_s10; setup $db
echo "messages: $(psql -qAtX -d $db -c 'select count(*) from inbound_messages')"
# serial control: one session, N sequential calls -> exactly MAX revealed
sq $db $RV "select count(*) filter (where (inbox_unmask('message', id::text,'serial')->>'ok')::boolean) from inbound_messages" > $OUT/s10.serial
rec S10s "serial control: $N unmask calls one after the other -> exactly $MAX revealed" $( [ "$(tail -1 $OUT/s10.serial)" = $MAX ] && echo PASS || echo FAIL ) "revealed=$(tail -1 $OUT/s10.serial)"
db=cc_s10p; setup $db
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $RV "select 'U|'||coalesce((inbox_unmask('message',(select id::text from inbound_messages order by id offset (:i-1) limit 1),'race')->>'ok'),'?');" $id
rev=$(psql -qAtX -d $db -c "select count(*) from inbox_unmask_log99 where user_id='$RV' and outcome='revealed'")
echo "revealed in log=$rev (max $MAX); ok replies=$(cnt_out $id '^U|true') blocked replies=$(cnt_out $id '^U|false'); errors:"; errs $id 3
ck $id.a "parallel: revealed rows in inbox_unmask_log99 <= daily max ($MAX)" $db "select count(*)<=$MAX from inbox_unmask_log99 where user_id='$RV' and outcome='revealed'" "select 'revealed=$rev max=$MAX replies_true=$(cnt_out $id '^U|true')'"
ck $id.b "log rows == replies (every reveal is logged, audit_log has one row per reveal)" $db "select (select count(*) from inbox_unmask_log99 where outcome='revealed')=(select count(*) from audit_log where table_name='inbox_unmask')"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
