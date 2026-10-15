#!/bin/bash
# S14 (extra) sale side: void_sale x N on one sale, sale_return over-return race, void vs return, production_void x N
. "$(dirname "$0")/lib.sh"; N=${N:-20}
id=S14a; db=cc_s14a; newdb $db; a=$(itm $db FG-BULK)
s=$(sq $db $SP "select record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$a\",\"qty\":3,\"price\":50}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":150}]',null,null,'retail',null,false)->>'id'" | tail -1)
sq $db $O "select acct_post_pending(false)" >/dev/null; d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'V|ok' from (select void_sale('$s'::uuid,'conc void')) z;" $id
errs $id 3
ck $id.a "void_sale x$N: stock restored exactly once (1000), one sale_void_in set" $db "select (select qty from stock_balance where item_id='$a' and location_id=1)=1000 and (select count(*) from stock_ledger where item_id='$a' and reverses_id is not null)=1" "select 'qty='||(select qty from stock_balance where item_id='$a' and location_id=1)||' reversals='||(select count(*) from stock_ledger where item_id='$a' and reverses_id is not null)||' ok='||$(cnt_out $id '^V|')||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR)"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
# over-return race: sold 3, 12 sessions each return 1 (different client ids) while 1 session voids
id=S14b; db=cc_s14b; newdb $db; a=$(itm $db FG-BULK)
s=$(sq $db $SP "select record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$a\",\"qty\":3,\"price\":50}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":150}]',null,null,'retail',null,false)->>'id'" | tail -1)
sq $db $O "select acct_post_pending(false)" >/dev/null; d0=$(deadlocks $db); lm=$(logmark)
race $db 12 $O "select 'R|'||coalesce(sale_return(gen_random_uuid(),'$s'::uuid,'[{\"item_id\":\"$a\",\"qty\":1}]'::jsonb,'damaged','conc','cash')->>'id','?');" $id
errs $id 3
ck $id.a "sold 3: at most 3 units can be returned in total" $db "select coalesce(sum(qty_delta),0)<=3 from stock_ledger where item_id='$a' and reason='sale_return'" "select 'returned='||coalesce(sum(qty_delta),0)||' ok replies='||$(cnt_out $id '^R|[0-9a-f]') from stock_ledger where item_id='$a' and reason='sale_return'"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
# void vs return on the same sale
id=S14c; db=cc_s14c; newdb $db; a=$(itm $db FG-BULK)
s=$(sq $db $SP "select record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$a\",\"qty\":3,\"price\":50}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":150}]',null,null,'retail',null,false)->>'id'" | tail -1)
sq $db $O "select acct_post_pending(false)" >/dev/null; d0=$(deadlocks $db); lm=$(logmark)
race $db 12 $O "
select 'R|'||coalesce(sale_return(gen_random_uuid(),'$s'::uuid,'[{\"item_id\":\"$a\",\"qty\":1}]'::jsonb,'damaged','conc','cash')->>'id','?') where :i % 2 = 0;
select 'V|ok' from (select void_sale('$s'::uuid,'conc void')) z where :i % 2 = 1;" $id
errs $id 3
ck $id.a "void + returns of one sale: stock never above 1000 (no double restore)" $db "select (select qty from stock_balance where item_id='$a' and location_id=1)<=1000" "select 'qty='||(select qty from stock_balance where item_id='$a' and location_id=1)||' sale='||(select status from sales where id='$s')||' returns='||(select count(*) from stock_ledger where item_id='$a' and reason='sale_return')"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
# production_void x N on the same run
id=S14d; db=cc_s14d; newdb $db
rc=$(psql -qAtX -d $db -c "select r.id from recipes r join items i on i.id=r.item_id where i.code='FG-P'"); rm_=$(itm $db RM-P)
run=$(sq $db $FM "select production_post(1,'$rc',2,gen_random_uuid())->>'run_id'" | tail -1)
sq $db $O "select acct_post_pending(false)" >/dev/null; d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "select 'P|'||coalesce(production_void('$run'::uuid,'conc')::text,'?');" $id
errs $id 3
ck $id.a "production_void x$N: RM-P back to 100 exactly once, FG-P back to 0" $db "select (select qty from stock_balance where item_id='$rm_' and location_id=1)=100 and (select qty from stock_balance where item_id=(select id from items where code='FG-P') and location_id=1)=0" "select 'RM-P='||(select qty from stock_balance where item_id='$rm_' and location_id=1)||' errors='||$(cat $OUT/$id/*.err | grep -c ERROR)"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
