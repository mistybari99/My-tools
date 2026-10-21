#!/bin/bash
# S12 setup_recommend_apply: double tap with the same client id, and N taps with different client ids
. "$(dirname "$0")/lib.sh"; N=${N:-20}
# prerequisite state the e2e uses: channels exist so more rules are recommended
prep() { newdb $1; sq $1 $O "select sales_channel_save(null,'webform','web_form',null,'Web form',1,null,null,true) is not null" >/dev/null; }
id=S12s; db=cc_s12s; prep $db; c1=$(cat /proc/sys/kernel/random/uuid)
sq $db $O "select setup_recommend_apply('$c1'::uuid)->>'count'" | tail -1 > $OUT/s12.n1
sq $db $O "select setup_recommend_apply(gen_random_uuid())->>'count'" | tail -1 > $OUT/s12.n2
psql -qAtX -d $db -c "select key||'='||value::text from rules where value is not null order by key" > $OUT/s12.serial.rules
echo "serial: first apply count=$(cat $OUT/s12.n1), second apply count=$(cat $OUT/s12.n2), rules set=$(wc -l < $OUT/s12.serial.rules)"
# a) same client id x N
id=S12a; db=cc_s12a; prep $db; c=$(cat /proc/sys/kernel/random/uuid); d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'A|'||coalesce(setup_recommend_apply('$c'::uuid)->>'dup','fresh')||'|'||(setup_recommend_apply('$c'::uuid)->>'count');" $id
errs $id 3
ck $id.a "same client_id x$N: one batch row, one audit row, errors 0" $db "select (select count(*) from setup_apply_batches81 where client_id='$c')=1 and (select count(*) from audit_log where action='setup_apply' and record_id='$c')=1 and $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select 'batches='||(select count(*) from setup_apply_batches81 where client_id='$c')||' fresh='||$(cnt_out $id '^A|fresh')||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR)"
psql -qAtX -d $db -c "select key||'='||value::text from rules where value is not null order by key" > $OUT/s12.a.rules
ck $id.rules "end state of the rules == the serial run" $db "select true" ""
cmp -s $OUT/s12.serial.rules $OUT/s12.a.rules && rec $id.rules2 "final rules identical to serial run" PASS "" || rec $id.rules2 "final rules identical to serial run" FAIL "$(diff $OUT/s12.serial.rules $OUT/s12.a.rules | head -3 | tr '\n' ' ')"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
# b) different client ids x N (double tap with a refreshed client id)
id=S12b; db=cc_s12b; prep $db; d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'B|'||coalesce(setup_recommend_apply(gen_random_uuid())->>'count','?');" $id
errs $id 3
psql -qAtX -d $db -c "select key||'='||value::text from rules where value is not null order by key" > $OUT/s12.b.rules
cmp -s $OUT/s12.serial.rules $OUT/s12.b.rules && rec $id.rules "final rules identical to serial run (N different client ids)" PASS "" || rec $id.rules "final rules identical to serial run (N different client ids)" FAIL "$(diff $OUT/s12.serial.rules $OUT/s12.b.rules | head -3 | tr '\n' ' ')"
ck $id.once "each rule is reported 'applied' by exactly one batch (setup_apply_lines81 has no rule twice)" $db "select not exists (select 1 from setup_apply_lines81 group by rule_key having count(*)>1)" "select coalesce(string_agg(rule_key||'x'||n,', '),'') from (select rule_key,count(*) n from setup_apply_lines81 group by rule_key having count(*)>1) z"
ck $id.err "no session error" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
