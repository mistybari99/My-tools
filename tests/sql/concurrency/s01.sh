#!/bin/bash
# S01 record_sale2: N sessions sell the last unit of the same item, stock_negative_mode block vs allow
. "$(dirname "$0")/lib.sh"; N=${N:-30}
for mode in block allow; do
  id=S01$mode; db=cc_s01_$mode; newdb $db
  sq $db $O "select set_rule('stock_negative_mode','\"$mode\"')" >/dev/null
  psql -qAtX -d $db -c "insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('FG-ONE','One','One','pc','pc','finished_good',true,100,true)" >/dev/null
  sq $db $O "select stock_opening((select id from items where code='FG-ONE'),1,1,60)" >/dev/null
  iid=$(psql -qAtX -d $db -c "select id from items where code='FG-ONE'")
  d0=$(deadlocks $db); lm=$(logmark)
  race $db $N $SP "select 'R|'||coalesce(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$iid\",\"qty\":1,\"price\":100}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":100}]',null,null,'retail',null,false)->>'id','null');" $id
  ok=$(cnt_out $id 'R|[0-9a-f-]\{36\}')
  if [ $mode = block ]; then
    ck $id.a "block: exactly 1 of $N sells the last unit (ok=$ok)" $db "select count(*)=1 from sales" "select 'sales='||count(*)||' ok='||$ok||' refused='||$(cnt_err $id insufficient_stock) from sales"
    ck $id.b "block: stock never below 0, final qty 0" $db "select (select qty from stock_balance where item_id='$iid' and location_id=1)=0 and not exists (select 1 from stock_ledger where item_id='$iid' group by item_id having min(qty_delta)<-1)" "select qty::text from stock_balance where item_id='$iid' and location_id=1"
  else
    ck $id.a "allow: all $N sales go through (negative stock allowed)" $db "select count(*)=$N from sales" "select 'sales='||count(*) from sales"
    ck $id.b "allow: balance = 1 - $N" $db "select (select qty from stock_balance where item_id='$iid' and location_id=1)=1-$N"
  fi
  ck $id.dl "no deadlock (pg_stat_database delta + server log)" $db "select true" "select 'dl_stat=$(( $(deadlocks $db) - d0 )) dl_log='||$(logdl $lm)"
  [ "$(( $(deadlocks $db) - d0 ))" = 0 ] || rec $id.dl2 "deadlock counter moved" FAIL "$(( $(deadlocks $db) - d0 ))"
  inv $db $id
done
