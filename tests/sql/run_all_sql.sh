#!/bin/bash
# Runs the whole SQL test set on a local throwaway Postgres (never the live project). Port PORT (default 5570), database names start with PFX (default r99).
#   1. base DB  = phases 8 to 87 in the owner order (tests/sql/ORDER.txt);  tN = the base plus phases 88 .. 99 and 140 .. 143 (W1-FIX), each pasted once, then a second time on a copy (paste-twice check)
#   2. every old suite (phase8 .. phase87) runs on a copy of the base AND on a copy of t143 (the full build); compare the two result folders: the failing lines must be the same (documented baseline)
#   3. every new suite phaseN_test.sql (88 .. 99 and 140 .. 143) runs on a copy of tN (the database through its own phase: the suites of the packages assert "hooks not installed yet");
#      the W1-FIX suites (140 .. 143) hook their own functions and run on the database through their own phase as well. phase84_test.sql needs phase84_test_project_only.sql (a TEST project file) pasted first.
# usage: PORT=5570 bash tests/sql/run_all_sql.sh      -> results in $OUT (default /tmp/run_all_sql/<PFX>): <suite>.txt (FAIL / ERROR / RESULT lines), summary.txt
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PORT:-5570}; PFX=${PFX:-r99}; OUT=${OUT:-/tmp/run_all_sql/$PFX}; mkdir -p $OUT/base $OUT/full $OUT/own
PSQL="psql -h /tmp -p $PORT -U postgres"; P="$PSQL -v ON_ERROR_STOP=1 -q"
ALL=$(grep -v '^#' $HERE/ORDER.txt); OLD=""; for w in $ALL; do n=${w#phase}; [ "$n" -le 87 ] && OLD="$OLD $w"; done
mk() { $PSQL -q -c "drop database if exists $1" -c "create database $1 template $2" 2>&1 | grep -v NOTICE; }
# 1. build
$PSQL -q -c "drop database if exists ${PFX}_t87" 2>&1 | grep -v NOTICE
# build_fresh_db.sh finds its own checkout and takes the port from PGPORT
ORDER="$OLD" PGPORT=$PORT bash $HERE/build_fresh_db.sh ${PFX}_t87 2>&1 | grep -E "FAIL|ERROR" | head
prev=${PFX}_t87
for n in 88 89 90 91 92 93 94 95 96 97 98 99 140 141 142 143; do
  mk ${PFX}_t$n $prev; $P -d ${PFX}_t$n -f $R/supabase/phase$n.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$n paste 1: /"
  mk ${PFX}_tw $prev;  $P -d ${PFX}_tw -f $R/supabase/phase$n.sql >/dev/null 2>&1; $P -d ${PFX}_tw -f $R/supabase/phase$n.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$n paste 2: /"
  prev=${PFX}_t$n
done
$PSQL -q -c "drop database if exists ${PFX}_tw" 2>&1 | grep -v NOTICE
mk ${PFX}_t87tp ${PFX}_t87; $P -d ${PFX}_t87tp -f $R/supabase/phase84_test_project_only.sql >/dev/null 2>&1; $P -d ${PFX}_t87tp -f $R/supabase/phase84b_test_project_only_wave1.sql >/dev/null 2>&1   # TEST databases only
mk ${PFX}_t143tp ${PFX}_t143; $P -d ${PFX}_t143tp -f $R/supabase/phase84_test_project_only.sql >/dev/null 2>&1; $P -d ${PFX}_t143tp -f $R/supabase/phase84b_test_project_only_wave1.sql >/dev/null 2>&1   # TEST databases only
# 2 and 3. run
run1() { # template label file
  local t=$1 l=$2 f=$3 n; n=$(basename $f .sql); local db=${PFX}_x_${l}_$n
  $PSQL -q -c "drop database if exists $db" -c "create database $db template $t" >/dev/null 2>&1
  (cd $R && timeout 900 $PSQL -d $db -qAt -f $f > $OUT/$l/$n.raw 2>&1)
  grep -E 'FAIL|ERROR|RESULT|^--- (FAILED|TOTAL)' $OUT/$l/$n.raw | sed 's/^psql:[^:]*:[0-9]*: //' > $OUT/$l/$n.txt
  $PSQL -q -c "drop database if exists $db" >/dev/null 2>&1
}
for f in $R/supabase/phase*_test.sql; do
  b=$(basename $f .sql); [ "$b" = phase84_test_project_only ] && continue; [ "$b" = phase84b_test ] && continue   # phase84b_test runs a reset: below, on its own copy
  n=${b#phase}; n=${n%_test}
  tb=${PFX}_t87; tf=${PFX}_t143; [ "$n" = 84 ] && { tb=${PFX}_t87tp; tf=${PFX}_t143tp; }
  if [ "$n" -le 87 ]; then run1 $tb base $f & run1 $tf full $f & else run1 ${PFX}_t$n own $f & fi
  while [ $(jobs -r | wc -l) -ge 6 ]; do sleep 1; done
done; wait
run1 ${PFX}_t143 own $R/supabase/phase84b_test.sql      # TEST file: pastes the two test-project files itself and runs a reset in its own throwaway copy
# summary + comparison of old suites base vs full
{ echo "== new suites (own database)"; for f in $OUT/own/*.txt; do echo "$(basename $f .txt): $(grep -E 'RESULT' $f | tail -1)"; done
  echo "== old suites: differences between the base (through 87) and the full build (through 99); empty = identical failing lines"
  for f in $OUT/base/*.txt; do n=$(basename $f); cmp -s $f $OUT/full/$n || { echo "--- $n"; diff $f $OUT/full/$n; }; done; } > $OUT/summary.txt
cat $OUT/summary.txt
