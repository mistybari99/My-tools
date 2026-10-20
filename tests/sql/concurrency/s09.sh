#!/bin/bash
# S09 bill auto-payment (rule purchase_bill_creates_payment=auto_cash, trigger _bp_pur_auto99): concurrent save+post of distinct bills, and concurrent post of the same bills
. "$(dirname "$0")/lib.sh"; N=${N:-30}
id=S09; db=cc_s09; newdb $db
sq $db $O "select set_rule('purchase_bill_creates_payment','\"auto_cash\"')" >/dev/null
sup=$(sid $db); rb=$(itm $db RM-B)
# (save and post are separate transactions here, as the browser does it; the one-transaction variant is S09b)
# 6 pre-saved drafts; each is posted by 5 sessions at once (30 sessions); and every session also saves+posts a bill of its own
for k in 1 2 3 4 5 6; do mkbill $db RM-B 2 50 > $OUT/s09.b$k; done
cat $OUT/s09.b* | tr '\n' ' ' > /dev/null
d0=$(deadlocks $db); lm=$(logmark)
SN="select 'P|'||coalesce(post_purchase('\$(cat $OUT/s09.b1)'::uuid)->>'dup','fresh') where :i % 6 = 0;"
snip=""; for k in 1 2 3 4 5 6; do snip="$snip
select 'P$k|'||coalesce(post_purchase('$(cat $OUT/s09.b$k)'::uuid)->>'dup','fresh') where :i % 6 = $((k % 6));"; done
snip="$snip
select save_purchase(gen_random_uuid(),null,'$sup'::uuid,1,'M-'||:i,(now() at time zone 'Asia/Dhaka')::date,'[{\"item_id\":\"$rb\",\"qty\":1,\"unit\":\"kg\",\"unit_cost\":10}]'::jsonb)->>'id' as nb \\gset
select 'M|'||coalesce(post_purchase(:'nb'::uuid)->>'status','?');"
race $db $N $O "$snip" $id
echo "own bills posted=$(cnt_out $id '^M|posted')"; errs $id 5
ck $id.err "no session error" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
ck $id.one "every posted bill has exactly one active auto payment (record + supplier_payments row) and is fully paid" $db "select not exists (select 1 from purchase_bills b where b.status='posted' and ((select count(*) from bill_payments99 p where p.bill_ref=b.id::text and p.status='active')<>1 or (select count(*) from supplier_payments s where s.bill_id=b.id and not s.voided)<>1 or b.paid<>b.total))" "select 'bills='||count(*)||' paid_ok='||count(*) filter (where paid=total)||' payments='||(select count(*) from supplier_payments)||' links='||(select count(*) from bill_payments99) from purchase_bills where status='posted'"
ck $id.sum "sum(supplier_payments) == sum(posted bill totals) (no double auto-payment)" $db "select (select coalesce(sum(amount),0) from supplier_payments where not voided)=(select coalesce(sum(total),0) from purchase_bills where status='posted')"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
