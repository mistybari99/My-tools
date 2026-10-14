#!/bin/bash
# S15 batch 2 stock safety (phase114): rules ON, N sessions race
#  a) transfer_needs_stock: N storekeepers send 1 each from a balance of 5 -> exactly 5 pass, balance 0 (never negative)
#  b) late_sale_follows_block: N salespeople sell the last unit with p_sold_at = now-5min in block mode -> exactly 1 passes
#  c) batch_refill_cap: balance -N (N sales), then N sessions produce 1 each -> balance 0 and the batches add up to 0
. "$(dirname "$0")/lib.sh"; N=${N:-20}
id=S15; db=cc_s15; newdb $db
psql -qAtX -d $db -c "insert into items (code,name_bn,name_en,unit,base_unit,item_type,tracked,sell_price,sellable) values ('S15-A','A','A','kg','kg','finished_good',true,10,true),('S15-B','B','B','kg','kg','finished_good',true,10,true),('S15-C','C','C','kg','kg','finished_good',true,10,true)" >/dev/null
A=$(itm $db S15-A); B=$(itm $db S15-B); C=$(itm $db S15-C)
for r in transfer_needs_stock late_sale_follows_block batch_refill_cap; do sq $db $O "select set_rule('$r','true')" >/dev/null; done
sq $db $O "select stock_opening('$A',1,5,10)" >/dev/null; sq $db $O "select stock_opening('$B',1,1,10)" >/dev/null
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $SK "select 'T|'||coalesce(stock_transfer(1,2,'$A',1)->>'id','null');" ${id}a
ck $id.a1 "transfer_needs_stock: exactly 5 of $N transfers pass (ok=$(cnt_out ${id}a 'T|[0-9a-f-]\{36\}'))" $db "select count(*)=5 from stock_transfers where item_id='$A'" "select 'rows='||count(*)||' refused='||$(cnt_err ${id}a insufficient_stock) from stock_transfers where item_id='$A'"
ck $id.a2 "sender balance 0, never negative (min running balance >= 0)" $db "select (select qty from stock_balance where item_id='$A' and location_id=1)=0 and not exists (select 1 from (select sum(qty_delta) over (order by id) r from stock_ledger where item_id='$A' and location_id=1) z where r<0)"
sq $db $O "select set_rule('stock_negative_mode','\"block\"')" >/dev/null
race $db $N $SP "select 'S|'||coalesce(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$B\",\"qty\":1,\"price\":10}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":10}]',null,null,'retail',null,false,now()-interval '5 minutes')->>'id','null');" ${id}b
ck $id.b1 "late sale in block mode: exactly 1 of $N sells the last unit (ok=$(cnt_out ${id}b 'S|[0-9a-f-]\{36\}'))" $db "select count(*)=1 from sales" "select 'sales='||count(*)||' refused='||$(cnt_err ${id}b insufficient_stock) from sales"
ck $id.b2 "balance 0" $db "select (select qty from stock_balance where item_id='$B' and location_id=1)=0"
sq $db $O "select set_rule('stock_negative_mode','\"warn\"')" >/dev/null
race $db $N $SP "select 'N|'||coalesce(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$C\",\"qty\":1,\"price\":10}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":10}]',null,null,'retail',null,false)->>'id','null');" ${id}c0
race $db $N $O "select 'P|'||(stock_production_in('$C',1,1,now(),null,'conc',gen_random_uuid()))::text;" ${id}c
ck $id.c1 "negative refill: balance -$N + $N = 0" $db "select (select qty from stock_balance where item_id='$C' and location_id=1)=0"
ck $id.c2 "negative refill: batches add up to the balance (0), none left over" $db "select coalesce(sum(qty_remaining),0)=0 from stock_batches where item_id='$C' and location_id=1" "select 'batches='||coalesce(sum(qty_remaining),0)||' n='||count(*) from stock_batches where item_id='$C'"
ck $id.err "no unexpected error (only insufficient_stock refusals)" $db "select $(cat $OUT/${id}a/*.err $OUT/${id}b/*.err $OUT/${id}c/*.err | grep ERROR | grep -vc insufficient_stock)=0" "select '$(errs ${id}c 3 | tr '\n' ' ')'"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
