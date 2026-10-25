#!/bin/bash
# S01c two-line sales in opposite line order (A,B vs B,A) + production + stock_wastage: lock-order deadlock hunt
. "$(dirname "$0")/lib.sh"; N=${N:-40}
id=S01c; db=cc_s01c; newdb $db
a=$(psql -qAtX -d $db -c "select id from items where code='FG-BULK'"); b=$(psql -qAtX -d $db -c "select id from items where code='FG-L'")
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $SP "
select 'R|'||coalesce(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$a\",\"qty\":1,\"price\":50},{\"item_id\":\"$b\",\"qty\":1,\"price\":200}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":250}]',null,null,'retail',null,false)->>'id','null') where :i % 2 = 0;
select 'R|'||coalesce(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$b\",\"qty\":1,\"price\":200},{\"item_id\":\"$a\",\"qty\":1,\"price\":50}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":250}]',null,null,'retail',null,false)->>'id','null') where :i % 2 = 1;
" $id
ok=$(cnt_out $id 'R|[0-9a-f-]\{36\}'); echo "ok=$ok of $N"; errs $id 4
ck $id.all "all $N two-line sales succeed (no deadlock victim)" $db "select count(*)=$N from sales" "select 'sales='||count(*)||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR) from sales"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock: opposite line order" FAIL "deadlocks=$(( $(deadlocks $db) - d0 ))"
inv $db $id
