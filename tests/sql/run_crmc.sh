#!/bin/bash
# Runs the whole CRM-C SQL proof on a LOCAL throwaway Postgres (never the live project). Default port 5573, database names start with crmc_.
#   1. base98 = a fresh build of phases 8..98 in the owner order (tests/sql/ORDER.txt without phase99); base99 = base98 + phase99 (the Wave 1 hooks)
#   2. t306 / t307 / t308 = base98 + the CRM-C phases up to that number, each pasted twice (paste-twice check); the three test files run on them
#   3. tests/sql/crmc_before_after.sh (figures unchanged, also when every CRM-C switch is ON and every function is used) and tests/sql/crmc_hook.sh (the one optional notify_scan line)
# usage: bash tests/sql/run_crmc.sh        result lines: RESULT ... per suite; any FAIL line is printed
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; S="$HERE"
PORT=${PORT:-5573}
PSQL="psql -h /tmp -p $PORT -U postgres"; P="$PSQL -v ON_ERROR_STOP=1 -q"
build() { # db, last phase list to add ("" or "99")
  local db=$1 with99=$2
  local ORDER; ORDER=$(grep -v '^#' $S/ORDER.txt); [ -z "$with99" ] && ORDER=$(echo $ORDER | sed 's/ phase99//')
  $PSQL -q -c "drop database if exists $db" -c "create database $db" 2>&1 | grep -v NOTICE
  $P -d $db -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
  for f in $S/mock_auth2.sql $R/supabase/schema.sql $R/supabase/phase2.sql $S/mock_storage.sql $R/supabase/phase3.sql $R/supabase/phase4.sql $R/supabase/ALL_NEW.sql; do $P -d $db -f $f >/dev/null 2>&1 || { echo "FAIL $f"; exit 1; }; done
  for ph in $ORDER; do $P -d $db -f $R/supabase/$ph.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/$ph: /"; done
}
build crmc_base98 ""
build crmc_base99 "99"
for n in 306 307 308; do
  db=crmc_t$n
  $PSQL -q -c "drop database if exists $db" -c "create database $db template crmc_base98" 2>&1 | grep -v NOTICE
  for k in 306 307 308; do [ $k -le $n ] && { $P -d $db -f $R/supabase/phase$k.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$k paste 1: /"; }; done
  for k in 306 307 308; do [ $k -le $n ] && { $P -d $db -f $R/supabase/phase$k.sql 2>&1 | grep -E "ERROR|FATAL" | sed "s/^/phase$k paste 2: /"; }; done
  (cd $R/supabase && $PSQL -d $db -qAt -f phase${n}_test.sql 2>&1 | grep -E "FAIL|RESULT|ERROR" | sed "s/^psql:[^:]*:[0-9]*: //")
done
PORT=$PORT BASE=crmc_base99 bash $S/crmc_before_after.sh 2>&1 | grep -E "FAIL|RESULT|PASS" | tail -8
PORT=$PORT BASE=crmc_base99 bash $S/crmc_hook.sh 2>&1 | grep -E "FAIL|RESULT" | tail -4
