#!/bin/bash
# R2 proof (owner rules 2 and 5: new behaviour is OFF by default, nothing existing changes):
#   1. A is a copy of BASE (a fresh build through phase 99) with tests/sql/p87_fixture.sql loaded (posted journals, sales, expenses).
#   2. Before: snapshot of every report (tests/sql/p87_snap.sql), a md5 of every existing function definition, the row count of every existing table, every existing rule value.
#   3. Paste phases 130, 131, 132 twice each (paste-twice check: no error).
#   4. After: the same snapshots. Every report equal, every existing function definition equal (nothing was patched), every existing table count equal, every existing rule equal.
#   5. The new settings sit at their defaults (announce_on / todo_on / todo_repeat_on / shift_on OFF, shift_mates_on ON), nobody holds the three new grants, the new tables are empty.
# usage: BASE=<db> PORT=5600 bash tests/sql/r2_before_after.sh      (local throwaway Postgres only; BASE must exist: a fresh build through phase 99)
PORT=${PORT:-5600}; BASE=${BASE:-r2base}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
DB=r2_ba
fail=0
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB template $BASE" 2>&1 | grep -v NOTICE
$P -d $DB -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture"; exit 1; }
SNAPSQL="create schema if not exists tt; drop table if exists tt.fn_%s; create table tt.fn_%s as select p.oid::regprocedure::text as sig, md5(pg_get_functiondef(p.oid)) as h from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.prokind in ('f','p') and p.proname !~ '^_?r2';
 drop table if exists tt.tc_%s; create table tt.tc_%s (t text, n bigint); do \$\$ declare r record; begin for r in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname !~ '^r2_' loop execute format('insert into tt.tc_%s select %%L, count(*) from public.%%I', r.relname, r.relname); end loop; end \$\$;
 drop table if exists tt.ru_%s; create table tt.ru_%s as select key, value::text as v, default_value::text as d from public.rules;"
for lab in before; do $P -d $DB -v label=$lab -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot $lab"; exit 1; }; $P -d $DB -c "$(printf "$SNAPSQL" $lab $lab $lab $lab $lab $lab $lab)" >/dev/null || { echo "FAIL fn snapshot $lab"; exit 1; }; done
for n in 130 131 132; do
  $P -d $DB -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n paste 1"; fail=1; }
  $P -d $DB -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n paste 2"; fail=1; }
done
for lab in after; do $P -d $DB -v label=$lab -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot $lab"; exit 1; }; $P -d $DB -c "$(printf "$SNAPSQL" $lab $lab $lab $lab $lab $lab $lab)" >/dev/null || { echo "FAIL fn snapshot $lab"; exit 1; }; done
n=$($P -d $DB -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d $DB -c "select count(*) from tt.snap where label='before'")
echo "reports before/after: $tot snapshots compared, $n differ (must be 0)"; [ "$n" = "0" ] || fail=1
f=$($P -d $DB -c "select count(*) from tt.fn_before b full join tt.fn_after a on a.sig = b.sig where a.h is distinct from b.h")
ft=$($P -d $DB -c "select count(*) from tt.fn_before")
echo "existing functions: $ft definitions compared, $f differ or are missing (must be 0)"; [ "$f" = "0" ] || fail=1
c=$($P -d $DB -c "select string_agg(coalesce(a.t, b.t), ',' order by coalesce(a.t, b.t)) from tt.tc_before b full join tt.tc_after a on a.t = b.t where a.n is distinct from b.n")
echo "existing tables whose row count changed: [$c] (must be exactly audit_log (the change-log lines of the new settings), grant_defs (+3), rules (+5))"; [ "$c" = "audit_log,grant_defs,rules" ] || fail=1
r=$($P -d $DB -c "select count(*) from tt.ru_before b join public.rules a on a.key = b.key where a.value::text is distinct from b.v or a.default_value::text is distinct from b.d")
nr=$($P -d $DB -c "select count(*) from public.rules where key not in (select key from tt.ru_before)")
echo "existing rules: $r changed (must be 0); new rules: $nr (must be 5)"; { [ "$r" = "0" ] && [ "$nr" = "5" ]; } || fail=1
d=$($P -d $DB -c "select (not rule_on('announce_on') and not rule_on('todo_on') and not rule_on('todo_repeat_on') and not rule_on('shift_on') and rule_on('shift_mates_on'))::text")
g=$($P -d $DB -c "select (count(*) = 3 and not exists (select 1 from rule_grants where grant_code in ('announce_post','todo_assign','shift_manage')) and not exists (select 1 from user_grants where grant_code in ('announce_post','todo_assign','shift_manage')))::text from grant_defs where grant_code in ('announce_post','todo_assign','shift_manage')")
e=$($P -d $DB -c "select ((select count(*) from r2_announcements) + (select count(*) from r2_announce_seen) + (select count(*) from r2_todos) + (select count(*) from r2_roster_days) = 0)::text")
echo "defaults: $d (must be true); grants defined and held by nobody: $g (must be true); new tables empty: $e (must be true)"; { [ "$d" = "true" ] && [ "$g" = "true" ] && [ "$e" = "true" ]; } || fail=1
j=$($P -d $DB -c "select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z")
echo "unbalanced journal entries: $j (must be 0)"; [ "$j" = "0" ] || fail=1
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" 2>&1 | grep -v NOTICE
[ "$fail" = "0" ] && echo "R2 BEFORE/AFTER: OK" || echo "R2 BEFORE/AFTER: FAIL"
exit $fail
