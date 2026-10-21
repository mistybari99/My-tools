#!/bin/bash
# Phase 120 proof (R1 pay requests): with every setting at its default (and also with the two request switches ON but "required" OFF) nothing an owner already reads changes.
#   BASE = a fresh build through phase 99 (tests/sql/ORDER.txt). Twins: a = phase 120 pasted (twice) AFTER the fixture, b = never pasted, c = phase 120 + both request switches ON.
#   1. fixture (tests/sql/p87_fixture.sql: payroll payment, advance, supplier payments, sales ...) on a, b, c; snapshot "before" on a
#   2. paste phase 120 twice on a (and once on c, switches on); snapshot "after" on a; compare: no difference
#   3. wave 2 through the OLD functions (tests/sql/p120_wave2.sql: advance, paper advance, split supplier payment, quick expense, posting) on a, b, c: the reports must agree
# usage: PORT=5595 BASE=r1_base bash tests/sql/phase120_before_after.sh      (local throwaway Postgres)
PORT=${PORT:-5595}; BASE=${BASE:-r1_base}
T=$(cd "$(dirname "$0")" && pwd); R=$(cd "$T/../.." && pwd)
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
for db in r1ba_a r1ba_b r1ba_c; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in r1ba_a r1ba_b r1ba_c; do $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }; done
$P -d r1ba_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
for i in 1 2; do $P -d r1ba_a -f $R/supabase/phase120.sql >/dev/null 2>/tmp/r1_ba_paste.err || { echo "FAIL paste $i"; head -3 /tmp/r1_ba_paste.err; exit 1; }; done
$P -d r1ba_c -f $R/supabase/phase120.sql >/dev/null 2>/tmp/r1_ba_paste.err || { echo "FAIL paste c"; exit 1; }
$P -d r1ba_c -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false); select set_rule('pay_requests_on','true'); select set_rule('party_requests_on','true')" >/dev/null || { echo "FAIL switches c"; exit 1; }
$P -d r1ba_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d r1ba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d r1ba_a -c "select count(*) from tt.snap where label='before'")
echo "PASS-OR-FAIL before/after: $tot snapshots compared, $n differ"
[ "$n" = "0" ] || { fail=1; $P -d r1ba_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
for db in r1ba_a r1ba_b r1ba_c; do $P -d $db -f $T/p120_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; $P -d $db -v label=wave2 -f $T/p87_snap.sql >/dev/null; done
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_totals_p1 day_book_all journal_lines balance_check_core; do
  a=$($P -d r1ba_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d r1ba_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); c=$($P -d r1ba_c -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ] && [ "$b" = "$c" ]; then echo "PASS wave2 $nm: with phase 120 (default, and switches on) = without"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
x=$($P -d r1ba_a -c "select (select count(*) from pay_requests)+(select count(*) from pay_request_events)+(select count(*) from money_exceptions where kind='r1_unbacked_payment')+(select count(*) from notifications where kind='pay_request')")
echo "rows written by phase 120 in a default install: $x (must be 0)"; [ "$x" = "0" ] || fail=1
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
