#!/bin/bash
# Runs the whole SQL test set on a local throwaway Postgres (never the live project).
#   1. two databases, both built by tests/sql/final_build.sh strictly in the order of tests/sql/ORDER.txt (= FOUNDATION + NEW of paste_order.env, tools/check_paste_order.py checks it):
#        base  = ORDER.txt from its first word up to and including phase87 (POSITION in the file, not number: 506-529 and 100-135 come before 80-87 there)
#        final = the whole of ORDER.txt
#   2. every supabase/<suite>_test.sql runs ONCE on its own fresh clone: on base when its phase (the number of the suite name, phase21b -> 21) is inside the base part
#      of ORDER.txt, on final otherwise (also for a suite whose phase is not in ORDER.txt). Exceptions, both written below:
#        PRE_OWN  suites that paste their own phase themselves and need the chain WITHOUT it (a third database is built for each: ORDER.txt minus that phase)
#        phase84_test gets phase84_test_project_only.sql pasted on its clone first (TEST databases only); phase84b/84c_test paste the test-project files themselves
#   3. the fail count of every suite is compared with tests/sql/baseline_fails.txt (column 2).
# usage: bash tests/sql/run_all_sql.sh [suite ...]        e.g.  bash tests/sql/run_all_sql.sh phase8 phase72 phase113 phase543
# env:   PGSOCK=/tmp PGPORT=5544 (same defaults as final_build.sh; PORT= is accepted as an alias of PGPORT)   REPO (default: this checkout)
#        TIMEOUT=600 per-suite seconds   JOBS=4 suites in parallel   LOGDIR=<dir> psql output of each suite   KEEP=1 keep the built databases   PFX=rs  db name prefix
# exit:  0 = every suite ran and equals the baseline; 1 = some suite differs, timed out, printed no result or could not be cloned; 2 = no connection / missing roles / a build failed
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}; export REPO
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-${PORT:-5544}}; export PGSOCK PGPORT
TIMEOUT=${TIMEOUT:-600}; JOBS=${JOBS:-4}; PFX=${PFX:-rs}; LOGDIR=${LOGDIR:-$(mktemp -d)}; mkdir -p "$LOGDIR"
PSQL="psql -h $PGSOCK -p $PGPORT -U postgres -X"
BASE_FILE="$HERE/baseline_fails.txt"
PRE_OWN=" phase543 "
die() { echo "ERROR: $*" >&2; exit 2; }
# 0. fail closed: a scratch server must answer and have the three Supabase roles (a fresh cluster has none: create them there)
$PSQL -qAt -c "select 1" >/dev/null 2>"$LOGDIR/connect.err" || die "cannot connect to Postgres at $PGSOCK:$PGPORT ($(head -1 "$LOGDIR/connect.err")); start a scratch server or set PGSOCK / PGPORT"
for r in anon authenticated service_role; do
  $PSQL -qAt -v ON_ERROR_STOP=1 -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = '$r') then create role $r nologin; end if; end \$\$" >/dev/null 2>&1 || die "role $r is missing and cannot be created"
done
# 1. orders from ORDER.txt
ALL=$(grep -v '^#' "$HERE/ORDER.txt" | tr -s ' \n' ' '); ALL=$(echo $ALL)
echo " $ALL " | grep -q " phase87 " || die "phase87 is not in ORDER.txt"
BASE_ORDER=$(echo $ALL | tr ' ' '\n' | sed '/^phase87$/q' | tr '\n' ' '); BASE_ORDER=$(echo $BASE_ORDER)
for w in $ALL; do [ -f "$REPO/supabase/$w.sql" ] || die "ORDER.txt names $w but supabase/$w.sql does not exist"; done
build() { # db order
  bash "$HERE/final_build.sh" "$1" "$2" > "$LOGDIR/build_$1.log" 2>&1; local rc=$?
  [ $rc -eq 0 ] && tail -1 "$LOGDIR/build_$1.log" | grep -qx "built $1" || { sed -n '1,20p' "$LOGDIR/build_$1.log" >&2; die "build of $1 failed (rc $rc), see $LOGDIR/build_$1.log"; }
  echo "built $1 ($(echo $2 | wc -w) phases)"
}
dbs=""; cleanup() { [ -n "$KEEP" ] && return; for d in $dbs; do $PSQL -q -c "drop database if exists $d" >/dev/null 2>&1; done; }
trap cleanup EXIT
dbs="${PFX}_base ${PFX}_final"; build ${PFX}_base "$BASE_ORDER"; build ${PFX}_final "$ALL"
# 2. suites and their template
if [ $# -gt 0 ]; then SUITES="$*"; else SUITES=$(ls "$REPO"/supabase/*_test.sql | xargs -n1 basename | sed 's/_test\.sql$//' | sort -V); fi
tpl_of() { # suite -> template db (builds the PRE_OWN databases on demand)
  local s=$1 ph; ph=phase$(echo "$s" | sed -E 's/^phase([0-9]+).*/\1/')
  case "$PRE_OWN" in *" $s "*)
    local d=${PFX}_pre_${ph#phase}
    if ! $PSQL -qAt -c "select 1 from pg_database where datname = '$d'" | grep -q 1; then
      build $d "$(echo $ALL | tr ' ' '\n' | grep -vx "$ph" | tr '\n' ' ')" >&2 || return 1; fi
    echo $d; return;; esac
  case " $BASE_ORDER " in *" $ph "*) echo ${PFX}_base;; *) echo ${PFX}_final;; esac
}
run1() { # suite template -> one result line in $LOGDIR/<suite>.row
  local s=$1 t=$2 f="$REPO/supabase/$1_test.sql" db=${PFX}_x_$(echo "$1" | tr -c 'a-z0-9\n' '_') rc p fl res
  if ! $PSQL -q -v ON_ERROR_STOP=1 -c "drop database if exists $db" -c "create database $db template $t" >"$LOGDIR/$s.clone" 2>&1; then
    echo "$s|$t|-|-|CLONE FAILED" > "$LOGDIR/$s.row"; return; fi
  [ "$s" = phase84 ] && { (cd "$REPO" && $PSQL -q -v ON_ERROR_STOP=1 -d $db -f supabase/phase84_test_project_only.sql) >"$LOGDIR/$s.pre" 2>&1 || { echo "$s|$t|-|-|SETUP FAILED" > "$LOGDIR/$s.row"; return; }; }
  (cd "$REPO" && timeout "$TIMEOUT" $PSQL -d $db -qAt -f "$f") > "$LOGDIR/$s.log" 2>&1; rc=$?
  $PSQL -q -c "drop database if exists $db" >/dev/null 2>&1
  res=$(grep -E '^RESULT [0-9]+ pass[ ,/]+[0-9]+ fail' "$LOGDIR/$s.log" | tail -1)   # 'RESULT 96 pass, 2 fail' / 'RESULT 65 pass / 0 fail' / 'RESULT 8 pass 1 fail'
  if [ -n "$res" ]; then p=$(echo "$res" | sed -E 's/^RESULT ([0-9]+) pass[ ,\/]+([0-9]+) fail.*/\1/'); fl=$(echo "$res" | sed -E 's/^RESULT ([0-9]+) pass[ ,\/]+([0-9]+) fail.*/\2/')
  else p=$(grep -cE '(^|NOTICE: +)PASS ' "$LOGDIR/$s.log"); fl=$(grep -cE '(^|NOTICE: +)FAIL ' "$LOGDIR/$s.log"); fi
  if [ $rc -eq 124 ]; then echo "$s|$t|$p|$fl|TIMEOUT"
  elif [ $rc -eq 2 ] || grep -qE '^psql: error|FATAL:|server closed the connection' "$LOGDIR/$s.log"; then echo "$s|$t|$p|$fl|CONNECTION LOST"
  elif [ $((p + fl)) -eq 0 ]; then echo "$s|$t|0|0|NO RESULT"
  else echo "$s|$t|$p|$fl|"; fi > "$LOGDIR/$s.row"
}
for s in $SUITES; do
  [ -f "$REPO/supabase/${s}_test.sql" ] || { echo "$s|-|-|-|NO SUCH SUITE" > "$LOGDIR/$s.row"; continue; }
  t=$(tpl_of $s) || exit 2
  case "$PRE_OWN" in *" $s "*) dbs="$dbs $t";; esac
  run1 $s $t &
  while [ $(jobs -r | wc -l) -ge $JOBS ]; do sleep 0.2; done
done; wait
# 3. compare with the baseline
bad=0; tp=0; tf=0
printf '%-12s %-12s %6s %5s  %-8s %s\n' SUITE DATABASE PASS FAIL BASELINE VERDICT
for s in $SUITES; do
  IFS='|' read -r _ t p fl v < "$LOGDIR/$s.row"
  b=$(awk -v s="$s" '$1==s{print $2}' "$BASE_FILE")
  if [ -z "$v" ]; then
    if [ -z "$b" ]; then [ "$fl" -eq 0 ] && v="ok (not in baseline)" || { v="NEW FAILS"; bad=$((bad+1)); }
    elif [ "$fl" -eq "$b" ]; then v="ok (= baseline)"
    elif [ "$fl" -lt "$b" ]; then v="IMPROVED (update baseline)"; bad=$((bad+1))
    else v="REGRESSION"; bad=$((bad+1)); fi
  else bad=$((bad+1)); fi
  [ "$p" != - ] && tp=$((tp+p)) && tf=$((tf+fl))
  printf '%-12s %-12s %6s %5s  %-8s %s\n' "$s" "${t#${PFX}_}" "$p" "$fl" "${b:--}" "$v"
done
echo "TOTAL pass=$tp fail=$tf  bad=$bad  (baseline total fail=$(awk '!/^#/{s+=$2} END{print s+0}' "$BASE_FILE") over all suites; compare only when running all)  logs: $LOGDIR"
[ $bad -eq 0 ]
