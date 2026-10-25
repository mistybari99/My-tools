#!/bin/bash
# S05 purchase: concurrent post / void / payment on the same bill; overpay race; payment replay
. "$(dirname "$0")/lib.sh"; N=${N:-30}
# a) draft bill posted by N sessions at once
id=S05a; db=cc_s05a; newdb $db; b=$(mkbill $db RM-B 10 20); iid=$(itm $db RM-B); d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'R|'||coalesce(post_purchase('$b'::uuid)->>'dup','fresh');" $id
ck $id.a "post_purchase x$N on one draft: stock +10 once, 1 purchase_in row" $db "select (select qty from stock_balance where item_id='$iid' and location_id=1)=10 and (select count(*) from stock_ledger where item_id='$iid' and reason='purchase_in')=1" "select 'fresh='||$(cnt_out $id 'R|fresh')||' dup='||$(cnt_out $id 'R|true')||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR)"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
# b) posted bill: void + pay + re-post at once (3 rounds with different void/pay mixes, so the void sometimes lands after some payments)
r=0; for vx in ":i % 3 = 0" ":i = 15" ":i = 30"; do r=$((r+1))
id=S05b$r; db=cc_s05b$r; newdb $db; b=$(mkbill $db RM-B 10 100 post); iid=$(itm $db RM-B); d0=$(deadlocks $db); lm=$(logmark)
sq $db $O "select acct_post_pending(false)" >/dev/null
race $db 30 $O "
select 'V|'||coalesce(void_purchase('$b'::uuid,'conc void')->>'status','?') where $vx;
select 'P|'||coalesce(bill_pay_record('purchase','$b','cash',100,gen_random_uuid())->>'remaining','?') where not ($vx) and :i % 2 = 1;
select 'X|'||coalesce(post_purchase('$b'::uuid)->>'dup','?') where not ($vx) and :i % 2 = 0;
" $id
echo "round $r ($vx): void ok=$(cnt_out $id '^V|') pay ok=$(cnt_out $id '^P|')"; errs $id 3
ck $id.a "void+pay+repost storm: stock is 0 (voided once) or 10, never doubled; 1 purchase_in, <=1 reversal" $db "select (select qty from stock_balance where item_id='$iid' and location_id=1) in (0,10) and (select count(*) from stock_ledger where item_id='$iid' and reason='purchase_in')=1 and (select count(*) from stock_ledger where item_id='$iid' and reverses_id is not null)<=1" "select 'qty='||(select qty from stock_balance where item_id='$iid' and location_id=1)||' status='||status||' paid='||paid||' payments='||(select count(*) from supplier_payments where bill_id=b.id) from purchase_bills b where id='$b'"
ck $id.c "payments never exceed the bill total; bill.paid == sum(live payments) unless voided" $db "select coalesce((select sum(amount) from supplier_payments where bill_id='$b' and not voided),0) <= (select total from purchase_bills where id='$b') and ((select status from purchase_bills where id='$b')='void' or (select paid from purchase_bills where id='$b')=coalesce((select sum(amount) from supplier_payments where bill_id='$b' and not voided),0))"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
done
# c) overpay race: bill 1000, 30 sessions pay 100 each (distinct client ids)
id=S05c; db=cc_s05c; newdb $db; b=$(mkbill $db RM-B 10 100 post); d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'P|'||coalesce(bill_pay_record('purchase','$b','cash',100,gen_random_uuid())->>'remaining','?');" $id
ck $id.a "overpay race: at most 10 x 100 accepted on a 1000 bill" $db "select coalesce(sum(amount),0)<=1000 and (select paid from purchase_bills where id='$b')<=1000 from supplier_payments where bill_id='$b'" "select 'accepted='||$(cnt_out $id '^P|')||' sum='||coalesce(sum(amount),0)||' bill.paid='||(select paid from purchase_bills where id='$b') from supplier_payments where bill_id='$b'"
ck $id.b "bill.paid == sum(supplier_payments)" $db "select (select paid from purchase_bills where id='$b')=coalesce(sum(amount),0) from supplier_payments where bill_id='$b'"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
# d) same payment client replayed
id=S05d; db=cc_s05d; newdb $db; b=$(mkbill $db RM-B 10 100 post); cid=$(cat /proc/sys/kernel/random/uuid)
race $db $N $O "select 'P|'||coalesce(bill_pay_record('purchase','$b','cash',100,'$cid'::uuid)->>'dup','fresh');" $id
ck $id.a "same payment client_id x$N: one payment row" $db "select count(*)=1 from supplier_payments where bill_id='$b'" "select 'rows='||count(*)||' fresh='||$(cnt_out $id 'P|fresh')||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR) from supplier_payments where bill_id='$b'"
inv $db $id
