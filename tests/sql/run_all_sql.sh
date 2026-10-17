#!/bin/bash
# Runs the whole SQL test set on a local throwaway Postgres (never the live project). Port PORT (default 5570), database names start with PFX (default r99).
#   1. base DB  = phases 8 to 87 in the owner order (tests/sql/ORDER.txt);  tN = the base plus every later phase of ORDER.txt (88 .. 99, 120, 130-132, 140-143, 300-329, 400-477), each pasted once on the
#      database before it, then a second time on a copy (paste-twice check). The order is the file's order, so a phase that is added to ORDER.txt is built and tested without editing this script.
#   2. every old suite (phase8 .. phase87) runs on a copy of the base AND on a copy of the final build; compare the two result folders: the failing lines must be the same (documented baseline)
#   3. every new suite phaseN_test.sql (N from 88 on) runs on a copy of tN (the database through its own phase: the suites of the packages assert "hooks not installed yet" and "package X not installed";
#      phase99_test.sql runs on t99). The suites of phases 477 and later need the whole build: they run on the final database copy.
#      phase84_test.sql needs phase84_test_project_only.sql (a TEST project file) pasted first; phase84b_test.sql pastes the two test-project files itself.
# usage: PORT=5570 bash tests/sql/run_all_sql.sh      -> results in $OUT (default /tmp/run_all_sql/<PFX>): <suite>.txt (FAIL / ERROR / RESULT lines), summary.txt
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PORT:-5570}; PFX=${PFX:-r99}; OUT=${OUT:-/tmp/run_all_sql/$PFX}; JOBS=${JOBS:-4}; mkdir -p $OUT/base $OUT/full $OUT/own $OUT/twice
PSQL="psql -h /tmp -p $PORT -U postgres"; P="$PSQL -v ON_ERROR_STOP=1 -q"
ALL=$(grep -v '^#' $HERE/ORDER.txt); OLD=""; NEW=""
for w in $ALL; do n=${w#phase}; if [ "$n" -le 87 ]; then OLD="$OLD $w"; else NEW="$NEW $n"; fi; done
LAST=$(echo $NEW | tr ' ' '\n' | tail -1)
mk() { $PSQL -q -c "drop database if exists $1" -c "create database $1 template $2" 2>&1 | grep -v NOTICE; }
# 1. build
$PSQL -q -c "drop database if exists ${PFX}_t87" 2>&1 | grep -v NOTICE
# build_fresh_db.sh finds its own checkout and takes the port from PGPORT
ORDER="$OLD" PGPORT=$PORT bash $HERE/build_fresh_db.sh ${PFX}_t87 2>&1 | grep -E "FAIL|ERROR" | head
run1() { # template label file
  local t=$1 l=$2 f=$3 n; n=$(basename $f .sql); local db=${PFX}_x_${l}_$n
  $PSQL -q -c "drop database if exists $db" -c "create database $db template $t" >/dev/null 2>&1
  (cd $R && timeout 1500 $PSQL -d $db -qAt -f $f > $OUT/$l/$n.raw 2>&1)
  grep -E 'FAIL|ERROR|RESULT|SUMMARY|^--- (FAILED|TOTAL)' $OUT/$l/$n.raw | sed 's/^psql:[^:]*:[0-9]*: //' > $OUT/$l/$n.txt
  $PSQL -q -c "drop database if exists $db" >/dev/null 2>&1
}
prev=${PFX}_t87
for n in $NEW; do
  f=$R/supabase/phase$n.sql
  mk ${PFX}_t$n $prev; (cd $R && $P -d ${PFX}_t$n -f $f 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$n paste 1: /")
  mk ${PFX}_tw ${PFX}_t$n; (cd $R && $P -d ${PFX}_tw -f $f 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$n paste 2: /") | tee -a $OUT/twice/errors.txt
  # a suite of a phase that needs the whole build (the last phase) runs on the final database below
  if [ -f $R/supabase/phase${n}_test.sql ] && [ "$n" != "$LAST" ]; then run1 ${PFX}_t$n own $R/supabase/phase${n}_test.sql; fi
  [ "$prev" != "${PFX}_t87" ] && $PSQL -q -c "drop database if exists $prev" >/dev/null 2>&1
  prev=${PFX}_t$n
done
$PSQL -q -c "drop database if exists ${PFX}_tw" 2>&1 | grep -v NOTICE
FINAL=${PFX}_t$LAST
[ -f $R/supabase/phase${LAST}_test.sql ] && run1 $FINAL own $R/supabase/phase${LAST}_test.sql
mk ${PFX}_t87tp ${PFX}_t87; $P -d ${PFX}_t87tp -f $R/supabase/phase84_test_project_only.sql >/dev/null 2>&1; $P -d ${PFX}_t87tp -f $R/supabase/phase84b_test_project_only_wave1.sql >/dev/null 2>&1   # TEST databases only
mk ${PFX}_tftp $FINAL; $P -d ${PFX}_tftp -f $R/supabase/phase84_test_project_only.sql >/dev/null 2>&1; $P -d ${PFX}_tftp -f $R/supabase/phase84b_test_project_only_wave1.sql >/dev/null 2>&1   # TEST databases only
# 2. old suites: base (through 87) and the final build
for f in $R/supabase/phase*_test.sql; do
  b=$(basename $f .sql); [ "$b" = phase84_test_project_only ] && continue; [ "$b" = phase84b_test ] && continue   # phase84b_test runs a reset: below, on its own copy
  n=${b#phase}; n=${n%_test}
  [ "$n" -le 87 ] || continue
  tb=${PFX}_t87; tf=$FINAL; [ "$n" = 84 ] && { tb=${PFX}_t87tp; tf=${PFX}_tftp; }
  run1 $tb base $f & run1 $tf full $f &
  while [ $(jobs -r | wc -l) -ge $JOBS ]; do sleep 1; done
done; wait
run1 $FINAL own $R/supabase/phase84b_test.sql      # TEST file: pastes the two test-project files itself and runs a reset in its own throwaway copy
# summary + comparison of old suites base vs full
{ echo "== new suites (own database)"; for f in $OUT/own/*.txt; do echo "$(basename $f .txt): $(grep -E 'RESULT|SUMMARY' $f | tail -1)"; done
  echo "== paste-twice errors (empty = every phase from 88 on can be pasted twice)"; cat $OUT/twice/errors.txt
  echo "== old suites: differences between the base (through 87) and the final build (through $LAST); empty = identical failing lines"
  for f in $OUT/base/*.txt; do n=$(basename $f); cmp -s $f $OUT/full/$n || { echo "--- $n"; diff $f $OUT/full/$n; }; done; } > $OUT/summary.txt
cat $OUT/summary.txt
