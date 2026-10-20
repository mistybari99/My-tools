#!/bin/bash
# S09b scan_confirm(p_post=true): save_purchase + post_purchase inside ONE transaction, many sessions, same supplier
# (insert bill = FK key-share lock on the supplier row, then post_purchase asks FOR UPDATE on the same row -> classic upgrade deadlock)
. "$(dirname "$0")/lib.sh"; N=${N:-12}
id=S09b; db=cc_s09b; newdb $db
sup=$(sid $db); rb=$(itm $db RM-B)
sq $db $O "select set_rule('purchase_bill_creates_payment','\"off\"')" >/dev/null
for i in $(seq 1 $N); do
  psql -qAtX -d $db -c "insert into scan_jobs (id, client_id, kind, location_id, image_path, status, engine, edited, created_by) values ('00000000-0000-0000-0000-0000000000$(printf %02d $i)', gen_random_uuid(), 'purchase_bill', 1, 'SCAN/1/s$i.jpg', 'reviewed', 'manual',
    '{\"supplier\":{\"id\":\"$sup\"},\"date\":\"$(date +%F)\",\"bill_no\":\"SC-$i\",\"lines\":[{\"decision\":\"map\",\"item_id\":\"$rb\",\"qty\":$i,\"unit\":\"kg\",\"unit_cost\":10}]}'::jsonb, '$O')" >/dev/null || exit 1
done
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'S|'||coalesce(scan_confirm(('00000000-0000-0000-0000-0000000000'||lpad(:i::text,2,'0'))::uuid, ('00000000-0000-0000-0000-0000000001'||lpad(:i::text,2,'0'))::uuid, true, true)->'result'->'posted'->>'status','?');" $id
echo "confirmed+posted=$(cnt_out $id '^S|posted')"; errs $id 4
dl=$(( $(deadlocks $db) - d0 ))
ck $id.a "all $N scan_confirm(post) calls succeed (no deadlock victim)" $db "select $(cnt_out $id '^S|posted')=$N" "select 'ok=$(cnt_out $id '^S|posted') deadlocks=$dl errors='||$(cat $OUT/$id/*.err | grep -c ERROR)"
[ "$dl" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock: scan_confirm(post) same supplier" FAIL "deadlocks=$dl (victims retry-able, but the user sees an error)"
# the rows that did commit must be consistent
inv $db $id
