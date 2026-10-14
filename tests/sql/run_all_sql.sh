#!/bin/bash
# Build the final DB from the canonical paste order (docs/PASTE_ORDER.md) once, then run every supabase/*_test.sql on its own clone of it,
# print pass/fail per suite and compare with tests/sql/baseline_fails.txt (the known failures of docs/briefs_p2p3/step_INT3_REPORT.md).
# usage: bash tests/sql/run_all_sql.sh [suite ...]        e.g.  bash tests/sql/run_all_sql.sh phase8 phase72 phase89c phase99
# env:   REPO (repo root, default: this checkout)  PGSOCK=/tmp  PGPORT=5544  (scratch Postgres, user postgres)
#        TEMPLATE=<db>  reuse an already built final db instead of building one     KEEP=1  keep the built template db
#        TIMEOUT=600    per-suite seconds     LOGDIR=<dir> where the psql output of each suite is kept
# exit code: 0 = every suite matches the baseline; 1 = some suite has more fails than the baseline (or differs); 2 = build failed
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}; export REPO
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; TIMEOUT=${TIMEOUT:-600}; LOGDIR=${LOGDIR:-$(mktemp -d)}
PSQL="psql -h $PGSOCK -p $PGPORT -U postgres"
BASE="$HERE/baseline_fails.txt"; ME=$$
# 1. order from docs/PASTE_ORDER.md: foundation list (section A) + the numbered table (section B); phases > 99 that exist as files are appended
PO="$REPO/docs/PASTE_ORDER.md"
FOUND=$(grep -oE 'phase8( [0-9]+)+' "$PO" | head -1 | tr -s ' ' '\n' | sed -E 's/^([0-9]+)$/phase\1/' | tr '\n' ' ')
TABLE=$(grep -E '^\| [0-9]+ \|' "$PO" | sed -E 's/^\| [0-9]+ \| \**(phase[0-9]+)\.sql.*/\1/' | tr '\n' ' ')
EXTRA=""; for f in $(ls "$REPO"/supabase/phase1[0-9][0-9].sql 2>/dev/null | sort); do b=$(basename "$f" .sql); case " $TABLE " in *" $b "*) ;; *) EXTRA="$EXTRA $b";; esac; done
ORDER="$(echo $FOUND | sed 's/^phase8 /phase8 /') $TABLE$EXTRA"; ORDER=$(echo $ORDER)
echo "paste order: $ORDER"
# 2. build
if [ -n "$TEMPLATE" ]; then TPL=$TEMPLATE; else
  TPL=rq_final_$ME; echo "building $TPL ..."
  bash "$HERE/final_build.sh" "$TPL" "$ORDER" > "$LOGDIR/build.log" 2>&1
  tail -1 "$LOGDIR/build.log"; grep -qx "built $TPL" "$LOGDIR/build.log" || { echo "BUILD FAILED, see $LOGDIR/build.log"; head -20 "$LOGDIR/build.log"; exit 2; }
fi
# 3. suites
if [ $# -gt 0 ]; then SUITES="$*"; else SUITES=$(ls "$REPO"/supabase/*_test.sql | xargs -n1 basename | sed 's/_test\.sql$//' | sort -V); fi
rows=(); bad=0; tp=0; tf=0
printf '%-12s %7s %6s  %-8s %s\n' SUITE PASS FAIL BASELINE VERDICT
for s in $SUITES; do
  f="$REPO/supabase/${s}_test.sql"; [ -f "$f" ] || { echo "$s: no such suite"; bad=$((bad+1)); continue; }
  DB=rq_${ME}_$(echo "$s" | tr -c 'a-z0-9\n' '_'); $PSQL -q -c "drop database if exists $DB" -c "create database $DB template $TPL" >/dev/null 2>&1 || { echo "$s: clone failed"; bad=$((bad+1)); continue; }
  (cd "$REPO" && timeout "$TIMEOUT" $PSQL -d "$DB" -qAt -f "$f") > "$LOGDIR/$s.log" 2>&1; rc=$?
  res=$(grep -E '^RESULT [0-9]+ pass [0-9]+ fail' "$LOGDIR/$s.log" | tail -1)
  if [ -n "$res" ]; then p=$(echo "$res" | awk '{print $2}'); fl=$(echo "$res" | awk '{print $4}')
  else p=$(grep -cE '(^|NOTICE: +)PASS ' "$LOGDIR/$s.log"); fl=$(grep -cE '(^|NOTICE: +)FAIL ' "$LOGDIR/$s.log"); fi
  [ $rc -eq 124 ] && v="TIMEOUT" || v=""
  b=$(awk -v s="$s" '$1==s{print $2}' "$BASE")
  if [ -z "$v" ]; then
    if [ -z "$b" ]; then [ "$fl" -eq 0 ] && v="ok (not in baseline)" || { v="NEW FAILS"; bad=$((bad+1)); }
    elif [ "$fl" -eq "$b" ]; then v="ok (= baseline)"
    elif [ "$fl" -lt "$b" ]; then v="IMPROVED (update baseline)"; bad=$((bad+1))
    else v="REGRESSION"; bad=$((bad+1)); fi
  else bad=$((bad+1)); fi
  tp=$((tp+p)); tf=$((tf+fl)); printf '%-12s %7s %6s  %-8s %s\n' "$s" "$p" "$fl" "${b:--}" "$v"
  $PSQL -q -c "drop database if exists $DB" >/dev/null 2>&1
done
echo "TOTAL pass=$tp fail=$tf  (baseline total fail=$(awk '{s+=$2} END{print s+0}' "$BASE") over all suites; compare only when running all)  logs: $LOGDIR"
[ -z "$KEEP" ] && [ -z "$TEMPLATE" ] && $PSQL -q -c "drop database if exists $TPL" >/dev/null 2>&1
[ $bad -eq 0 ]
