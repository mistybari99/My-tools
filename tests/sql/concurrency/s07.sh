#!/bin/bash
# S07 landed_post (several sessions, same doc, same/different client ids) concurrent with sales of the same item
. "$(dirname "$0")/lib.sh"; N=${N:-40}
id=S07; db=cc_s07; newdb $db
sq $db $O "select set_rule('landed_cost_mode','\"manual\"')" >/dev/null
b=$(mkbill $db FG-L 50 100 post); fl=$(itm $db FG-L); sup2=$(sid $db Transporter)
sq $db $O "select acct_post_pending(false)" >/dev/null
lc=$(sq $db $O "select landed_save(gen_random_uuid(), null, '{\"title\":\"Freight\",\"alloc_method\":\"value\"}'::jsonb, '[{\"type\":\"bill\",\"id\":\"$b\"}]'::jsonb, '[{\"charge_type\":\"freight\",\"amount\":500,\"alloc_method\":\"value\",\"pay_mode\":\"payable\",\"supplier_id\":\"$sup2\"}]'::jsonb)->>'id'" | tail -1)
echo "landed doc $lc"
cl=$(cat /proc/sys/kernel/random/uuid); d0=$(deadlocks $db); lm=$(logmark)
# sessions: 1/4 post the SAME landed doc (half with one shared client id, half with fresh ones), 3/4 sell FG-L (qty 1)
race $db $N $O "
select 'L|'||coalesce(landed_post('$lc'::uuid, '$cl'::uuid)->>'dup','fresh') where :i % 8 = 0;
select 'L|'||coalesce(landed_post('$lc'::uuid, gen_random_uuid())->>'dup','fresh') where :i % 8 = 4;
select set_config('request.jwt.claim.sub','$SP',false) \\gset
select 'S|'||coalesce(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$fl\",\"qty\":1,\"price\":200}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":200}]',null,null,'retail',null,false)->>'id','?') where :i % 4 <> 0;
" $id
echo "landed fresh=$(cnt_out $id '^L|false') dup=$(cnt_out $id '^L|true') sales=$(cnt_out $id '^S|[0-9a-f]')"; errs $id 5
ck $id.once "landed doc posted once (status posted, 1 allocation set, 2 cost_adjust rows)" $db "select (select status from landed_costs where id='$lc')='posted' and (select count(*) from landed_cost_stock where cost_id='$lc' and kind='post')=1 and (select count(*) from stock_ledger where reason='cost_adjust' and ref_id='$lc')=2" "select 'fresh=$(cnt_out $id '^L|false') cost_adjust='||(select count(*) from stock_ledger where reason='cost_adjust' and ref_id='$lc')||' alloc_rows='||(select count(*) from landed_cost_alloc where cost_id='$lc' and kind='post')"
ck $id.val "stock value is conserved: (opening 250 x 100 + 500 freight) = remaining value + value of units sold (sum of sale_out qty*cost)" $db "select abs((select 20000+5000+500) - ((select qty*avg_cost from stock_balance where item_id='$fl' and location_id=1) + (select coalesce(-sum(qty_delta*unit_cost),0) from stock_ledger where item_id='$fl' and reason='sale_out')))<0.05" "select 'bal='||(select qty*avg_cost from stock_balance where item_id='$fl' and location_id=1)||' sold='||(select coalesce(-sum(qty_delta*unit_cost),0) from stock_ledger where item_id='$fl' and reason='sale_out')||' avg='||(select avg_cost from stock_balance where item_id='$fl' and location_id=1)"
ck $id.noerr "no session error except expected" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
GLTOL=0.20 inv $db $id

# serial control: the same 30 sales + the landed post in one session, no concurrency -> is the rounding residue the same size?
id=S07s; db=cc_s07s; newdb $db
sq $db $O "select set_rule('landed_cost_mode','\"manual\"')" >/dev/null
b=$(mkbill $db FG-L 50 100 post); fl=$(itm $db FG-L); sup2=$(sid $db Transporter); sq $db $O "select acct_post_pending(false)" >/dev/null
lc=$(sq $db $O "select landed_save(gen_random_uuid(), null, '{\"title\":\"Freight\",\"alloc_method\":\"value\"}'::jsonb, '[{\"type\":\"bill\",\"id\":\"$b\"}]'::jsonb, '[{\"charge_type\":\"freight\",\"amount\":500,\"alloc_method\":\"value\",\"pay_mode\":\"payable\",\"supplier_id\":\"$sup2\"}]'::jsonb)->>'id'" | tail -1)
sq $db $SP "select count(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$fl\",\"qty\":1,\"price\":200}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":200}]',null,null,'retail',null,false)) from generate_series(1,10)" >/dev/null
sq $db $O "select landed_post('$lc'::uuid, gen_random_uuid())" >/dev/null
sq $db $SP "select count(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$fl\",\"qty\":1,\"price\":200}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":200}]',null,null,'retail',null,false)) from generate_series(1,20)" >/dev/null
sq $db $O "select acct_post_pending(false)" >/dev/null; sq $db $O "select acct_post_pending(false)" >/dev/null
ck $id.gl "SERIAL CONTROL (no concurrency): inventory_vs_gl unexplained within 0.20 (rounding residue)" $db "select abs((inventory_vs_gl()->'total'->>'unexplained')::numeric)<0.20" "select inventory_vs_gl()->'total'"
