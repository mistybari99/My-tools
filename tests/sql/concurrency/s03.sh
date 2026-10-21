#!/bin/bash
# S03 stock_production_in (stock_post +) + stock_transfer (both directions) + count adjust + wastage + issue on ONE balance, then double receive
. "$(dirname "$0")/lib.sh"; N=${N:-48}
id=S03; db=cc_s03; newdb $db
psql -qAtX -d $db -c "insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('FG-X','X','X','pc','pc','finished_good',true,100,true)" >/dev/null
iid=$(psql -qAtX -d $db -c "select id from items where code='FG-X'")
sq $db $O "select stock_opening('$iid',1,500,10)" "select stock_opening('$iid',2,500,12)" >/dev/null 2>&1
sq $db $O "select stock_opening('$iid',1,500,10)" >/dev/null; sq $db $O "select stock_opening('$iid',2,500,12)" >/dev/null
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "
select 'P|'||(stock_production_in('$iid',1,3+:i,now(),null,'conc',gen_random_uuid(),10+:i))::text where :i % 6 = 0;
select 'T|'||(stock_transfer(1,2,'$iid',2)->>'id') where :i % 6 = 1;
select 'C|'||(stock_count_adjust('$iid',1,400+:i,'conc count')->>'delta') where :i % 6 = 2;
select 'W|'||(stock_wastage('$iid',1,1,'spoiled','conc'))::text where :i % 6 = 3;
select 'I|'||(stock_issue('$iid',1,1,null,'conc',gen_random_uuid()))::text where :i % 6 = 4;
select 'B|'||(stock_transfer(2,1,'$iid',3)->>'id') where :i % 6 = 5;
select 'Q|'||(stock_count_adjust('$iid',2,450+:i,'conc count 2')->>'delta') where :i % 6 = 5;
" $id
echo "ok: P=$(cnt_out $id '^P|') T=$(cnt_out $id '^T|') C=$(cnt_out $id '^C|') W=$(cnt_out $id '^W|') I=$(cnt_out $id '^I|') B=$(cnt_out $id '^B|') Q=$(cnt_out $id '^Q|')"; errs $id
ck $id.err "no errors in any session" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
# phase 2: every in-transit transfer received by 3 sessions at once
tl=$(psql -qAtX -d $db -c "select string_agg(id::text,',') from stock_transfers where status='sent'")
n_t=$(psql -qAtX -d $db -c "select count(*) from stock_transfers where status='sent'")
rm -f $OUT/${id}r.sql; for t in ${tl//,/ }; do echo "select 'R|'||(stock_receive_transfer('$t')->>'status');" >> $OUT/${id}r.sql; done
race $db 3 $O $OUT/${id}r.sql ${id}r
ck $id.recv "every transfer received exactly once (3 sessions each): transit_in rows == transfers" $db "select (select count(*) from stock_transfers where status='received')=$n_t and (select coalesce(sum(qty),0) from stock_transfers)=(select coalesce(sum(qty_delta),0) from stock_ledger where reason='transfer_in')" "select 'transfers=$n_t transfer_in_sum='||coalesce(sum(qty_delta),0)||' transfers_sum='||(select coalesce(sum(qty),0) from stock_transfers) from stock_ledger where reason='transfer_in'"
ck $id.recvErr "no error in the double receive" $db "select $(cat $OUT/${id}r/*.err | grep -c ERROR)=0" "select '$(errs ${id}r 3 | tr '\n' ' ')'"
ck $id.sum "balance == opening + sum of ledger (both places, total conserved by transfers)" $db "select (select sum(qty) from stock_balance where item_id='$iid')=(select sum(qty_delta) from stock_ledger where item_id='$iid')"
ck $id.avg "avg cost sane: between min and max unit cost seen" $db "select coalesce(min(avg_cost),0)>=8 and coalesce(max(avg_cost),0)<=60 from stock_balance where item_id='$iid'" "select string_agg(location_id||':'||qty||'@'||avg_cost,' ') from stock_balance where item_id='$iid'"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
