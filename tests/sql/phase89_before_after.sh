#!/bin/bash
# Phase 89 proof: nothing changes for an existing install until the owner changes a W1-B setting.
#   1. a fresh DB through phase 87 (BASE), the phase 87 fixture (records of every kind), snapshot "before"
#   2. paste phase89 + the hooks of docs/integration/W1-B_hooks.sql, snapshot "after" (P&L, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, balance check, posting dry run): identical
#   3. a second wave (owner works in a closed period, back-dates to the year 2000, late offline sale, posting run) on that DB and on a twin DB that never got phase 89: the reports must agree
# usage: bash tests/sql/phase89_before_after.sh      (local throwaway Postgres on PORT, default 5562; BASE must exist: a fresh build through phase 87)
PORT=${PORT:-5562}; BASE=${BASE:-base87}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
OWNER=00000000-0000-0000-0000-000000000987
fail=0
for db in ba89_a ba89_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in ba89_a ba89_b; do $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }; done
$P -d ba89_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
$P -d ba89_a -f $R/supabase/phase89.sql >/dev/null 2>&1 || { echo "FAIL phase89 paste"; exit 1; }
$P -d ba89_a -f $R/docs/integration/W1-B_hooks.sql >/dev/null 2>&1 || { echo "FAIL hooks paste"; exit 1; }
$P -d ba89_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d ba89_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d ba89_a -c "select count(*) from tt.snap where label='before'")
echo "PASS-OR-FAIL before/after: $tot snapshots compared, $n differ"
[ "$n" = "0" ] || { fail=1; $P -d ba89_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
np=$($P -d ba89_a -c "select set_config('request.jwt.claim.sub','$OWNER',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
echo "posting run after the paste posted: $np (must be 0)"; [ "$np" = "0" ] || fail=1
nr=$($P -d ba89_a -c "select count(*) from money_exceptions where kind in ('period_lock_exception','backdate_exception','late_sale_held','late_sale_redated')")
echo "exception lines written by the paste: $nr (must be 0)"; [ "$nr" = "0" ] || fail=1
# second wave on both twins
for db in ba89_a ba89_b; do $P -d $db -f $T/p89_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
$P -d ba89_a -v label=wave2 -f $T/p87_snap.sql >/dev/null; $P -d ba89_b -v label=wave2 -f $T/p87_snap.sql >/dev/null
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_totals_p1 day_book_all journal_lines; do
  a=$($P -d ba89_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d ba89_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ]; then echo "PASS wave2 $nm: with phase 89 = without"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
ja=$($P -d ba89_a -c "select count(*) from journal_entries"); jb=$($P -d ba89_b -c "select count(*) from journal_entries")
[ "$ja" = "$jb" ] && echo "PASS wave2 journal entry count equal ($ja)" || { echo "FAIL wave2 journal entries $ja vs $jb"; fail=1; }
sa=$($P -d ba89_a -c "select count(*) from sales where sale_date = (now() at time zone 'Asia/Dhaka')::date"); sb=$($P -d ba89_b -c "select count(*) from sales where sale_date = (now() at time zone 'Asia/Dhaka')::date")
[ "$sa" = "$sb" ] && echo "PASS wave2 late sale re-dated the same way ($sa sales dated today)" || { echo "FAIL wave2 sales $sa vs $sb"; fail=1; }
xa=$($P -d ba89_a -c "select count(*) from money_exceptions where kind in ('period_lock_exception','backdate_exception','late_sale_held','late_sale_redated')")
[ "$xa" = "0" ] && echo "PASS wave2 no new exception lines with default settings" || { echo "FAIL wave2 exception lines: $xa"; fail=1; }
$P -d ba89_a -c "select 'unbalanced entries: ' || count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z"
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
