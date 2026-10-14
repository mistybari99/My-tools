#!/bin/bash
# S04 production_post: N sessions each cook one batch (10 kg RM-P -> 8 kg FG-P) from the same 100 kg of raw material
. "$(dirname "$0")/lib.sh"; N=${N:-20}
for v in default block; do
  id=S04$v; db=cc_s04_$v; newdb $db
  [ $v = block ] && sq $db $O "select set_rule('stock_negative_mode','\"block\"')" >/dev/null
  rc=$(psql -qAtX -d $db -c "select r.id from recipes r join items i on i.id=r.item_id where i.code='FG-P'")
  rm_=$(psql -qAtX -d $db -c "select id from items where code='RM-P'"); fg=$(psql -qAtX -d $db -c "select id from items where code='FG-P'")
  if [ $v = default ]; then   # serial control: the 11th batch must be refused when nobody else is running
    for k in $(seq 1 11); do sq $db $FM "select production_post(1,'$rc',1,gen_random_uuid())->>'run_id'" ; done | grep -c 'insufficient_stock' > $OUT/s04.ctl
    rec S04ctl "serial control: 11 batches one after the other -> the 11th is refused (insufficient_stock)" $( [ "$(cat $OUT/s04.ctl)" = 1 ] && echo PASS || echo FAIL ) "refused=$(cat $OUT/s04.ctl)"
    newdb $db
  fi
  d0=$(deadlocks $db); lm=$(logmark)
  race $db $N $FM "select 'R|'||coalesce(production_post(1,'$rc',1,gen_random_uuid())->>'run_id','null');" $id
  ok=$(cnt_out $id 'R|[0-9a-f-]\{36\}')
  echo "variant=$v ok=$ok of $N"; errs $id 3
  ck $id.neg "RM-P never below 0 (refuse must hold under concurrency): final qty" $db "select (select qty from stock_balance where item_id='$rm_' and location_id=1)>=0 and not exists (select 1 from (select sum(qty_delta) over (order by id) s from stock_ledger where item_id='$rm_' and location_id=1) z where s<0)" "select 'RM-P='||(select qty from stock_balance where item_id='$rm_' and location_id=1)||' runs_ok=$ok (max allowed 10) FG-P='||coalesce((select qty from stock_balance where item_id='$fg' and location_id=1),0)"
  ck $id.runs "runs == FG-P yield / 8 == consumed RM / 10 (ledger consistent with production_runs)" $db "select (select count(*) from production_runs)=$ok and coalesce((select qty from stock_balance where item_id='$fg' and location_id=1),0)=8*$ok and (select -coalesce(sum(qty_delta),0) from stock_ledger where item_id='$rm_' and reason='issue_out')=10*$ok"
  [ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
  inv $db $id
done
