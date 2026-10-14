#!/bin/bash
# S08 card_settle: same client twice (x N), and N different settlements of the same 600 receivable
. "$(dirname "$0")/lib.sh"; N=${N:-20}
prep() { newdb $1; local a; a=$(itm $1 FG-BULK)
  sq $1 $SP "select record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$a\",\"qty\":12,\"price\":50}]'::jsonb,0,'[{\"mode\":\"card\",\"amount\":600}]',null,null,'retail',null,false)->>'id'" >/dev/null
  sq $1 $O "select acct_post_pending(false)" >/dev/null; }
# a) same client id
id=S08a; db=cc_s08a; prep $db; cid=$(cat /proc/sys/kernel/random/uuid); d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'C|'||coalesce(card_settle(1,(now() at time zone 'Asia/Dhaka')::date,600,12,'batch','$cid'::uuid)->>'dup','fresh');" $id
ck $id.a "card_settle same client_id x$N: exactly one settlement row" $db "select count(*)=1 from card_settlements85 where client_id='$cid'" "select 'rows='||count(*)||' fresh='||$(cnt_out $id 'C|fresh')||' dup='||$(cnt_out $id 'C|true')||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR) from card_settlements85 where client_id='$cid'"
inv $db $id
ck $id.card "card receivable (1140) is 0 after one settlement of 600 posted" $db "select (select coalesce(sum(l.debit-l.credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1140')=0"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
# b) serial control then concurrent: different client ids, each 600 against a 600 receivable
id=S08s; db=cc_s08s; prep $db
for k in 1 2 3; do sq $db $O "select card_settle(1,(now() at time zone 'Asia/Dhaka')::date,600,12,'serial',gen_random_uuid())->>'over'"; done | tr '\n' ' ' > $OUT/s08s.over
rec $id "serial control: 3 settlements of 600 against a 600 receivable; 'over' flags returned (no posting between calls)" $( [ "$(cat $OUT/s08s.over)" = "false false false " ] && echo FAIL || echo PASS ) "over flags: $(cat $OUT/s08s.over)"
id=S08b; db=cc_s08b; prep $db; d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'C|'||coalesce(card_settle(1,(now() at time zone 'Asia/Dhaka')::date,600,12,'batch',gen_random_uuid())->>'over','?');" $id
sq $db $O "select acct_post_pending(false)" >/dev/null
ck $id.a "different client ids: over-settlement must be refused or flagged: GL card receivable must not go negative" $db "select (select coalesce(sum(l.debit-l.credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1140')>=0" "select 'settlements='||(select count(*) from card_settlements85)||' over=true:'||$(cnt_out $id 'C|true')||' over=false:'||$(cnt_out $id 'C|false')||' receivable='||(select coalesce(sum(l.debit-l.credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1140')"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
