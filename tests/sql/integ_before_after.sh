#!/bin/bash
# INTEGRATION parity proof: a database built through phase 87 gets phases 88 .. 477 (EVERY package, in the owner paste order tests/sql/ORDER.txt) with every new setting at its default;
# the 33 existing reports of the phase 99 snapshot must be identical before and after, pasted once and pasted twice, and after a second wave of records made through the hooked functions
# (that is the unchanged tests/sql/phase99_before_after.sh run with PHASES = all phases from 88 on).
# Two intended exceptions, both added by a package and both only text / a new key, never a number:
#   l1_pnl and l3_shop_pnl:  new key profit_complete (RPT-C1) and the words in the gaps column (RPT-B1 names the losses that are left out of the profit).
# This script proves that nothing else differs in those two reports: with the two keys removed the rows are equal, including every profit figure.
# usage: PORT=5570 BASE=base87 bash tests/sql/integ_before_after.sh      (BASE = a fresh build through phase 87)
HERE="$(cd "$(dirname "$0")" && pwd)"
export PORT=${PORT:-5570} BASE=${BASE:-base87} DBP=${DBP:-ibaf}
export PHASES=$(grep -v '^#' $HERE/ORDER.txt | tr ' ' '\n' | sed 's/phase//' | awk '$1>=88' | tr '\n' ' ')
bash $HERE/phase99_before_after.sh | grep -v "^PASS wave2 .*: with phases" > /tmp/${DBP}_run.txt
grep -E "^FAIL|^snapshots|^wave2 reports" /tmp/${DBP}_run.txt | sed "s/^FAIL/INFO (expected: l1_pnl and l3_shop_pnl only, checked below) FAIL/"
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
bad=0
strip="md5((select coalesce(jsonb_agg((e - 'gaps' - 'profit_complete') order by e::text), '[]')::text from jsonb_array_elements(val::jsonb) e))"
for k in l1_pnl l3_shop_pnl; do
  b=$($P -d ${DBP}_a -c "select $strip from tt.snap where name = '$k' and label = 'before'")
  for lab in after after2; do
    a=$($P -d ${DBP}_a -c "select $strip from tt.snap where name = '$k' and label = '$lab'")
    if [ "$a" = "$b" ]; then echo "PASS $k $lab equals before (without the keys gaps and profit_complete)"; else echo "FAIL $k $lab differs beyond gaps / profit_complete"; bad=1; fi
  done
  wa=$($P -d ${DBP}_a -c "select $strip from tt.snap where name = '$k' and label = 'wave2'"); wb=$($P -d ${DBP}_b -c "select $strip from tt.snap where name = '$k' and label = 'wave2'")
  if [ "$wa" = "$wb" ]; then echo "PASS $k wave2: with all phases = without (without the keys gaps and profit_complete)"; else echo "FAIL $k wave2 differs beyond gaps / profit_complete"; bad=1; fi
done
only=$(grep -E "^FAIL" /tmp/${DBP}_run.txt | grep -v -E "l1_pnl|l3_shop_pnl" | wc -l)
if [ "$only" != 0 ]; then echo "FAIL a report other than l1_pnl / l3_shop_pnl differs"; bad=1; fi
[ $bad = 0 ] && echo "RESULT integration before/after: IDENTICAL except the two intended additions" || echo "RESULT integration before/after: DIFFERENCES"
