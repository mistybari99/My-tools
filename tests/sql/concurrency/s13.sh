#!/bin/bash
# S13 option views: bulk set (ascending and descending key order, user and role level) racing with reads
. "$(dirname "$0")/lib.sh"; N=${N:-32}; K=200
id=S13; db=cc_s13; newdb $db
asc=$(psql -qAtX -d $db -c "select jsonb_agg(jsonb_build_object('key','r:k'||lpad(g::text,3,'0'),'mode','hide') order by g) from generate_series(1,$K) g")
desc_=$(psql -qAtX -d $db -c "select jsonb_agg(jsonb_build_object('key','r:k'||lpad(g::text,3,'0'),'mode','locked') order by g desc) from generate_series(1,$K) g")
d0=$(deadlocks $db); lm=$(logmark)
race $db $N $O "
select 'A|'||coalesce(set_option_view_bulk('$SP'::uuid,'$asc'::jsonb,gen_random_uuid())->>'count','?') where :i % 4 = 0;
select 'B|'||coalesce(set_option_view_bulk('$SP'::uuid,'$desc_'::jsonb,gen_random_uuid())->>'count','?') where :i % 4 = 1;
select 'R|'||(select count(*) from jsonb_array_elements(option_views_for_user('$SP'::uuid)->'overrides'))  where :i % 4 = 2;
select 'S|'||coalesce(set_role_option_view_bulk('salesperson','$asc'::jsonb,gen_random_uuid())->>'count','?') where :i % 4 = 3;
select 'S2|'||coalesce(set_role_option_view_bulk('salesperson','$desc_'::jsonb,gen_random_uuid())->>'count','?') where :i % 4 = 3;
" $id
echo "A ok=$(cnt_out $id '^A|[0-9]') B ok=$(cnt_out $id '^B|[0-9]') reads: $(cat $OUT/$id/*.out | grep '^R|' | sort | uniq -c | tr '\n' ' ')"; errs $id 4
dl=$(( $(deadlocks $db) - d0 ))
ck $id.reads "every read saw 0 or $K overrides (a bulk set is atomic for readers)" $db "select true" ""
bad=$(cat $OUT/$id/*.out | grep '^R|' | grep -v "^R|0$\|^R|$K$" | wc -l)
[ "$bad" = 0 ] && rec $id.reads2 "every read saw 0 or $K overrides (bulk set atomic for readers)" PASS "reads=$(cat $OUT/$id/*.out | grep -c '^R|')" || rec $id.reads2 "bulk set atomic for readers" FAIL "$bad torn reads"
ck $id.state "final state is uniform: all $K keys hold the same mode (user level)" $db "select count(distinct mode)<=1 from user_option_view where user_id='$SP'" "select string_agg(mode||':'||n,' ') from (select mode,count(*) n from user_option_view where user_id='$SP' group by 1) z"
ck $id.state2 "final state is uniform (role level)" $db "select count(distinct mode)<=1 from role_option_view where role_code='salesperson'" "select string_agg(mode||':'||n,' ') from (select mode,count(*) n from role_option_view where role_code='salesperson' group by 1) z"
ck $id.err "no session error (deadlock victims would show here)" $db "select $(cat $OUT/$id/*.err | grep -c ERROR)=0" "select '$(errs $id 3 | tr '\n' ' ')'"
[ "$dl" = 0 ] && rec $id.dl "no deadlock (stat + log)" PASS "dl_log=$(logdl $lm)" || rec $id.dl "no deadlock: two bulk sets with opposite key order" FAIL "deadlocks=$dl"
