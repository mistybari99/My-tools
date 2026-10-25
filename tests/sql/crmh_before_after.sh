#!/bin/bash
# CRM-H proof (phases 328 and 329): with the new settings at their defaults, AND with every CRM-H setting switched ON and every function used, every existing report gives exactly the figures it gave before.
#   1. BASE = a fresh build through phase 98 (tests/sql/build_fresh_db.sh style). Load the Wave 1 fixtures (w1d_fixture, w1d_snap_setup, p99_fixture_extra): stock, production, wastage, counts, sales,
#      credit sale and collection, void, return, payments, payroll, partner agreement ... then snapshot "before" (P&L, L1 L3 L4 L5 T4 E2 E3, income statement, balance sheet, trial balance, cash flow,
#      day book, journal lines, posting dry run, stock levels and valuation, customer dues and ledger, supplier balance, returns, payments ...).
#   2. paste phase328 and phase329 -> snapshot "after" -> identical (defaults)
#   3. paste both again -> "after2" -> identical
#   4. tests/sql/crmh_exercise.sql switches every CRM-H setting ON and uses every function (complaints, notes, closing, food safety, return link, ratings, follow-up, overdue scan, report) -> "after_on" -> identical
#      (a complaint posts nothing; the linked return is only READ). The poster has nothing new to post.
# usage: bash tests/sql/crmh_before_after.sh      (local throwaway Postgres on PORT, default 5576; BASE = a fresh build through phase 98, default base98)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; T="$HERE"
PORT=${PORT:-5576}; BASE=${BASE:-base98}
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
db=ba_crmh
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE
for f in w1d_fixture w1d_snap_setup p99_fixture_extra; do $P -d $db -f $T/$f.sql >/dev/null 2>/tmp/crmh_ba_err.txt || { echo "FAIL fixture $f"; head -3 /tmp/crmh_ba_err.txt; exit 1; }; done
snap() { $P -d $db -v label=$1 -f $T/w1d_snap.sql >/dev/null 2>&1 && $P -d $db -v label=$1 -f $T/p99_snap_extra.sql >/dev/null 2>&1 || { echo "FAIL snapshot $1"; exit 1; }; }
differ() { $P -d $db -c "select a.name from tt.snap a join tt.snap b on a.name = b.name and b.label = '$2' where a.label = '$1' and a.val is distinct from b.val order by 1" | tr '\n' ' '; }
snap before
tot=$($P -d $db -c "select count(*) from tt.snap where label='before'"); echo "snapshots taken: $tot"
[ "$tot" -gt 30 ] && ok "snapshot set is large enough ($tot)" || bad "too few snapshots ($tot)"
for n in 328 329; do $P -d $db -f $R/supabase/phase$n.sql >/dev/null 2>/tmp/crmh_ba_err.txt || { echo "FAIL phase$n paste"; head -3 /tmp/crmh_ba_err.txt; exit 1; }; done
snap after
d=$(differ before after); [ -z "$d" ] && ok "with every CRM-H setting at its default $tot snapshots are identical before and after phases 328 and 329" || bad "default figures changed: $d"
for n in 328 329; do $P -d $db -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n second paste"; fail=1; }; done
snap after2
d=$(differ before after2); [ -z "$d" ] && ok "phases 328 and 329 pasted a second time: still identical" || bad "second paste changed: $d"
out=$($P -d $db -f $T/crmh_exercise.sql 2>/tmp/crmh_ba_err.txt | tail -1) || { echo "FAIL exercise"; head -5 /tmp/crmh_ba_err.txt; fail=1; }
echo "$out"
echo "$out" | grep -q "exercise done: 3 complaints" && ok "the exercise ran (every CRM-H function used with every setting ON)" || bad "exercise did not complete as planned: $out"
snap after_on
d=$(differ before after_on); [ -z "$d" ] && ok "with every CRM-H setting ON and every function used, all $tot snapshots are still identical (a complaint posts nothing)" || bad "figures changed with the settings ON: $d"
np=$($P -d $db -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
[ "$np" = "0" ] && ok "the poster has nothing new to post (posted $np)" || bad "the poster posted $np"
ub=$($P -d $db -c "select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z")
[ "$ub" = "0" ] && ok "no unbalanced journal entry" || bad "unbalanced entries: $ub"
sd=$($P -d $db -c "select count(*) from public.sale_returns")
echo "sale returns in the database: $sd (unchanged by CRM-H: it only reads them)"
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
