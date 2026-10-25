#!/bin/bash
# XB package SQL runner on a LOCAL throwaway Postgres (never the live project).
# usage: PGPORT=5860 bash tests/sql/xb_run.sh phase491 [phase492 ...]
#   needs database xb_base = tests/sql/build_fresh_db.sh with ORDER=all (phases 8..478), built once.
#   for each named phase N: copies xb_base, pastes every XB phase up to N twice (second paste on a copy), runs supabase/N_test.sql.
#   result lines: FAIL ... / RESULT n pass, m fail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PGPORT:-5860}; BASE=${XB_BASE:-xb_base}
PSQL="psql -h /tmp -p $PORT -U postgres"; P="$PSQL -v ON_ERROR_STOP=1 -q"
XB="phase491 phase492 phase493"
for t in "$@"; do
  db=xb_$t
  $PSQL -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE
  for ph in $XB; do
    $P -d $db -f $R/supabase/$ph.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/$ph paste 1: /"
    [ "$ph" = "$t" ] && break
  done
  $PSQL -q -c "drop database if exists ${db}_tw" -c "create database ${db}_tw template $db" 2>&1 | grep -v NOTICE
  for ph in $XB; do
    $P -d ${db}_tw -f $R/supabase/$ph.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/$ph paste 2: /"
    [ "$ph" = "$t" ] && break
  done
  $PSQL -q -c "drop database if exists ${db}_tw" 2>&1 | grep -v NOTICE
  (cd $R && $PSQL -d $db -qAt -f supabase/${t}_test.sql 2>&1 | grep -E 'FAIL|ERROR|RESULT|\(got|did not fail|NOTICE:  PASS' | grep -v 'NOTICE:  PASS')
  $PSQL -d $db -qAt -c "select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res" 2>/dev/null
done
