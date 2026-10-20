#!/bin/bash
# Runs the whole SQL test set of the UNION of the two lines on a local throwaway Postgres (never the live project). Port PORT (default 5570), database names start with PFX (default u99).
#   1. tests/sql/ORDER.txt is the union order: phases 8-79 (shared base), then the advanced block (506-528, 100-118, 121-129, 133-135), then phase529 (shim), then our line 80..505, then phase530-534.
#      Every phase is pasted on a copy of the database before it, then a SECOND time on a copy (paste-twice check, errors are listed in twice/errors.txt).
#   2. a suite phaseN_test.sql (and its variants phaseN[a-z]_test.sql) runs on the database through its OWN phase N of this order (the suites of the packages assert "hooks not installed yet").
#      The suites of the last phases (477 and later, and 530-534) need the whole build: they run on the final database.
#   3. old suites (phase8 .. phase79, incl. variants such as phase21b_test) run on the base (through phase79) AND on the final build; the failing lines must be the same (documented baseline).
# usage: PORT=5570 bash tests/sql/run_all_union.sh   (env ORDER_FILE=<file> PFX=<prefix> OUT=<dir> JOBS=<n>)      -> results in $OUT (default /tmp/run_all_union/<PFX>): <suite>.txt (FAIL / ERROR / RESULT lines), summary.txt
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PORT:-5570}; PFX=${PFX:-u99}; OUT=${OUT:-/tmp/run_all_union/$PFX}; JOBS=${JOBS:-4}; mkdir -p $OUT/base $OUT/full $OUT/own $OUT/twice
PSQL="psql -h /tmp -p $PORT -U postgres"; P="$PSQL -v ON_ERROR_STOP=1 -q"
ORDER_FILE=${ORDER_FILE:-$HERE/ORDER.txt}   # another order file (one name per word) runs the same tests on a single line's chain, e.g. to get the baseline of each line
ALL=$(grep -v '^#' $ORDER_FILE); OLD=""; NEW=""
for w in $ALL; do n=${w#phase}; if [ -z "$NEW" ] && [ "$n" -le 79 ] && [ "$n" -ge 8 ]; then OLD="$OLD $w"; else NEW="$NEW $n"; fi; done
LAST=$(echo $NEW | tr ' ' '\n' | tail -1)
mk() { $PSQL -q -c "drop database if exists $1" -c "create database $1 template $2" 2>&1 | grep -v NOTICE; }
# 1. build the base (phases 8..79)
$PSQL -q -c "drop database if exists ${PFX}_t79" 2>&1 | grep -v NOTICE
ORDER="$OLD" PGPORT=$PORT bash $HERE/build_fresh_db.sh ${PFX}_t79 2>&1 | grep -E "FAIL|ERROR" | head
run1() { # template label file
  local t=$1 l=$2 f=$3 n; n=$(basename $f .sql); local db=${PFX}_x_${l}_$n
  $PSQL -q -c "drop database if exists $db" -c "create database $db template $t" >/dev/null 2>&1
  (cd $R && timeout 1500 $PSQL -d $db -qAt -f $f > $OUT/$l/$n.raw 2>&1)
  grep -E 'FAIL|ERROR|RESULT|SUMMARY|^--- (FAILED|TOTAL)' $OUT/$l/$n.raw | sed 's/^psql:[^:]*:[0-9]*: //' > $OUT/$l/$n.txt
  $PSQL -q -c "drop database if exists $db" >/dev/null 2>&1
}
FINALSET=" 477 478 479 480 481 482 483 484 485 486 487 488 489 490 491 492 493 494 495 496 497 498 499 501 502 503 504 505 530 531 532 533 534 535 536 537 538 539 "
prev=${PFX}_t79
for n in $NEW; do
  f=$R/supabase/phase$n.sql
  mk ${PFX}_t$n $prev; (cd $R && $P -d ${PFX}_t$n -f $f 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$n paste 1: /") | tee -a $OUT/twice/errors1.txt
  mk ${PFX}_tw ${PFX}_t$n; (cd $R && $P -d ${PFX}_tw -f $f 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$n paste 2: /") | tee -a $OUT/twice/errors.txt
  case "$FINALSET" in *" $n "*) ;; *)   # suites of the phases that need the whole build run on the final database below
    for t in $R/supabase/phase${n}_test.sql $R/supabase/phase${n}[a-z]_test.sql; do [ -f $t ] && run1 ${PFX}_t$n own $t & done;; esac
  wait
  [ "$prev" != "${PFX}_t79" ] && $PSQL -q -c "drop database if exists $prev" >/dev/null 2>&1
  prev=${PFX}_t$n
done
$PSQL -q -c "drop database if exists ${PFX}_tw" 2>&1 | grep -v NOTICE
FINAL=${PFX}_t$LAST
for n in $FINALSET; do for t in $R/supabase/phase${n}_test.sql $R/supabase/phase${n}[a-z]_test.sql; do [ -f $t ] && run1 $FINAL own $t; done; done
mk ${PFX}_t79tp ${PFX}_t79; $P -d ${PFX}_t79tp -f $R/supabase/phase84_test_project_only.sql >/dev/null 2>&1; $P -d ${PFX}_t79tp -f $R/supabase/phase84b_test_project_only_wave1.sql >/dev/null 2>&1   # TEST databases only
# 3. old suites: base (through 79) and the final build
for f in $R/supabase/phase*_test.sql; do
  b=$(basename $f .sql); n=${b#phase}; n=${n%_test}; nn=${n%%[a-z_]*}
  [ -n "$nn" ] && [ "$nn" -le 79 ] || continue
  run1 ${PFX}_t79 base $f & run1 $FINAL full $f &
  while [ $(jobs -r | wc -l) -ge $JOBS ]; do sleep 1; done
done; wait
{ echo "== suites at their own position (own database)"; for f in $OUT/own/*.txt; do echo "$(basename $f .txt): $(grep -E 'RESULT|SUMMARY' $f | tail -1)"; done
  echo "== paste-twice errors (empty = every phase from 80 on can be pasted twice)"; cat $OUT/twice/errors.txt
  echo "== first-paste errors"; cat $OUT/twice/errors1.txt
  echo "== old suites: differences between the base (through 79) and the final build (through $LAST); empty = identical failing lines"
  for f in $OUT/base/*.txt; do n=$(basename $f); cmp -s $f $OUT/full/$n || { echo "--- $n"; diff $f $OUT/full/$n; }; done; } > $OUT/summary.txt
cat $OUT/summary.txt
