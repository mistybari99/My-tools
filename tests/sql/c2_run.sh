#!/bin/bash
# RPT-C2 SQL test runner on a LOCAL throwaway Postgres (never the live project).
# usage: PORT=5700 bash tests/sql/c2_run.sh phase445 [phase446 ...]
#   builds phases 8..99 once (tests/sql/ORDER.txt), then for each named phase N: pastes phases 445..N (each twice, second paste on a copy to prove paste-twice safety) and runs supabase/phaseN_test.sql.
#   result lines: FAIL ... / RESULT n pass, m fail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PORT:-5700}; PFX=${PFX:-c2r}
PSQL="psql -h /tmp -p $PORT -U postgres"; P="$PSQL -v ON_ERROR_STOP=1 -q"
BASE=${PFX}_base
if ! $PSQL -tAc "select 1 from pg_database where datname='$BASE'" | grep -q 1; then
  S=$R/tests/sql; SQ=$R/supabase
  ORDER=$(grep -v '^#' $S/ORDER.txt | tr ' ' '\n' | awk '$0!="" {print} $0=="phase99"{exit}' | tr '\n' ' ')
  $PSQL -q -c "create database $BASE" 2>&1 | grep -v NOTICE
  $P -d $BASE -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
  for f in $S/mock_auth2.sql $SQ/schema.sql $SQ/phase2.sql $S/mock_storage.sql $SQ/phase3.sql $SQ/phase4.sql $SQ/ALL_NEW.sql; do $P -d $BASE -f $f >/dev/null 2>/tmp/${PFX}_errf.txt || { echo FAIL $f; head -5 /tmp/${PFX}_errf.txt; exit 1; }; done
  for ph in $ORDER; do $P -d $BASE -f $SQ/$ph.sql 2>&1 | grep -E "ERROR|FATAL" | head -3; done
  echo built $BASE
fi
C2="phase445 phase446 phase447 phase448 phase449 phase450 phase451 phase452 phase453 phase454 phase455 phase456 phase457"
for t in "$@"; do
  db=${PFX}_$t
  $PSQL -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE
  for ph in $C2; do
    $P -d $db -f $R/supabase/$ph.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/$ph paste 1: /"
    [ "$ph" = "$t" ] && break
  done
  # paste-twice proof on a copy: every phase up to t pasted a second time
  $PSQL -q -c "drop database if exists ${db}_tw" -c "create database ${db}_tw template $db" 2>&1 | grep -v NOTICE
  for ph in $C2; do
    $P -d ${db}_tw -f $R/supabase/$ph.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/$ph paste 2: /"
    [ "$ph" = "$t" ] && break
  done
  $PSQL -q -c "drop database if exists ${db}_tw" 2>&1 | grep -v NOTICE
  (cd $R && $PSQL -d $db -qAt -f supabase/${t}_test.sql 2>&1 | grep -E 'FAIL|ERROR|RESULT|\(got|did not fail')
done
