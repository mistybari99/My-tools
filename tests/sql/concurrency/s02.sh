#!/bin/bash
# S02 same client_id replayed from N sessions at once: exactly one sale, the others 'dup'
. "$(dirname "$0")/lib.sh"; N=${N:-30}
for fn in record_sale2 record_sale_offline; do
  id=S02$fn; db=cc_s02_$fn; newdb $db
  iid=$(psql -qAtX -d $db -c "select id from items where code='FG-BULK'")
  cid=$(cat /proc/sys/kernel/random/uuid); d0=$(deadlocks $db); lm=$(logmark)
  extra=""; [ $fn = record_sale_offline ] && extra=",now()"
  race $db $N $SP "select 'R|'||coalesce((r->>'id'),'null')||'|'||coalesce(r->>'dup','f') from (select $fn('$cid'::uuid,1,'[{\"item_id\":\"$iid\",\"qty\":2,\"price\":50}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":100}]',null,null,'retail',null,false$extra) r) z;" $id
  ck $id.a "$fn same client_id x$N: exactly one sale row" $db "select count(*)=1 from sales where client_id='$cid'" "select 'rows='||count(*)||' dupreplies='||$(cnt_out $id '|true')||' fresh='||$(cnt_out $id '|f$')||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR) from sales where client_id='$cid'"
  ck $id.b "exactly one sale_out ledger row set, stock 1000-2" $db "select (select qty from stock_balance where item_id='$iid' and location_id=1)=998 and (select count(*) from stock_ledger where item_id='$iid' and reason='sale_out')=1"
  ck $id.c "no session got an error (all non-winners answer dup)" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
  ck $id.d "one journal entry per sale" $db "select (select count(*) from journal_entries e join sales s on s.id::text=e.source_id where e.source_type='sale' and s.client_id='$cid') <= 1"
  [ "$(( $(deadlocks $db) - d0 ))" = 0 ] || rec $id.dl "deadlock counter moved" FAIL "$(( $(deadlocks $db) - d0 ))"
  inv $db $id
done
