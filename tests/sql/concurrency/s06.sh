#!/bin/bash
# S06 acct_post_pending / acct_autopost_tick in parallel (and while new sales, voids and purchases arrive)
. "$(dirname "$0")/lib.sh"; N=${N:-24}; DOCS=${DOCS:-1500}
id=S06; db=cc_s06; newdb $db
a=$(itm $db FG-BULK)
sq $db $O "select set_rule('acct_scheduler_on','true')" >/dev/null
sq $db $SP "select count(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$a\",\"qty\":1,\"price\":50}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":50}]',null,null,'retail',null,false)) from generate_series(1,$DOCS)" >/dev/null
for k in 1 2 3 4 5 6; do mkbill $db RM-B 5 20 post >/dev/null; done
sq $db $O "select count(void_sale(id,'conc void')) from (select id from sales order by id limit 20) z" >/dev/null
sq $db $O "select acct_post_pending(false)" >/dev/null     # post the first batch serially, then void 20 already-posted sales: the race must produce exactly one reversal each
sq $db $O "select count(void_sale(id,'conc void2')) from (select id from sales where status<>'void' order by id desc limit 20) z" >/dev/null
for k in 1 2 3; do mkbill $db RM-B 5 20 post >/dev/null; done
pre=$(psql -qAtX -d $db -c "select count(*) from journal_entries")
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "
select 'PP|'||(acct_post_pending(false)->>'posted')||'|'||jsonb_array_length(acct_post_pending(false)->'errors') where :i % 4 = 0;
select 'TK|'||coalesce(acct_autopost_tick()::text,'?') where :i % 4 = 1;
select set_config('request.jwt.claim.sub','',false) \\gset
select 'TS|'||coalesce(acct_autopost_tick()::text,'?') where :i % 4 = 2;
select set_config('request.jwt.claim.sub', :'u', false) \\gset
select 'S|'||coalesce(record_sale2(gen_random_uuid(),1,'[{\"item_id\":\"$a\",\"qty\":1,\"price\":50}]'::jsonb,0,'[{\"mode\":\"cash\",\"amount\":50}]',null,null,'retail',null,false)->>'id','?') where :i % 4 = 3;
" $id
echo "pp=$(cnt_out $id '^PP|') tick=$(cnt_out $id '^TK|') sched=$(cnt_out $id '^TS|') sales=$(cnt_out $id '^S|')"; errs $id 5
ck $id.err "no session raised an error (incl. deadlock / unique violation)" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
ck $id.errs "no document failed to post (acct_post_errors72 empty)" $db "select count(*)=0 from acct_post_errors72" "select coalesce(string_agg(source_type||':'||error,'; '),'') from acct_post_errors72"
sq $db $O "select acct_post_pending(false)" >/dev/null; sq $db $O "select acct_post_pending(false)" >/dev/null
ck $id.once "each non-void sale posted exactly once (voided before posting = no entry)" $db "select (select count(*) from sales s where s.status<>'void' and not exists (select 1 from journal_entries e where e.source_type='sale' and e.source_id=s.id::text and e.reverses_id is null))=0 and (select count(*) from (select source_id from journal_entries where source_type='sale' and reverses_id is null group by 1 having count(*)>1) z)=0" "select 'sales='||(select count(*) from sales)||' entries='||(select count(*) from journal_entries where source_type='sale' and reverses_id is null)||' reversals='||(select count(*) from journal_entries where source_type='sale' and reverses_id is not null)"
ck $id.rev "20 voids of posted sales -> exactly 20 reversals, one per original" $db "select (select count(*) from journal_entries where source_type='sale' and reverses_id is not null)=20 and (select count(*) from (select reverses_id from journal_entries where reverses_id is not null group by 1 having count(*)>1) z)=0" "select 'reversals='||count(*) from journal_entries where source_type='sale' and reverses_id is not null"
ck $id.nowait "nothing left pending after the final run" $db "select (acct_post_pending(true)->>'posted')::int=0" "select acct_post_pending(true)->>'posted'"
ck $id.runs "autopost runs table: every run recorded, none with errors" $db "select coalesce(sum(errors),0)=0 from acct_autopost_runs85"
[ "$(( $(deadlocks $db) - d0 ))" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock" FAIL "$(( $(deadlocks $db) - d0 ))"
inv $db $id
