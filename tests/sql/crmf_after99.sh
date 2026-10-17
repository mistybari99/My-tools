#!/bin/bash
# CRM-F: phases 316 to 319 also paste cleanly (twice) on a database built through phase 99 (the Wave 1 integration), and the package suites pass there.
# usage: DB=crmf_99 PORT=5574 bash tests/sql/crmf_after99.sh      (DB = a fresh build through phase 99: UP_TO=99 bash tests/sql/crmf_build.sh crmf_99)
PORT=${PORT:-5574}; DB=${DB:-crmf_99}; R=$(cd "$(dirname "$0")/../.." && pwd); PSQL="psql -h /tmp -p $PORT -U postgres"; fail=0
for pass in 1 2; do for n in 316 317 318 319; do $PSQL -d $DB -v ON_ERROR_STOP=1 -q -f $R/supabase/phase$n.sql >/dev/null 2>/tmp/crmf99_err.txt || { echo "FAIL phase$n paste $pass"; head -3 /tmp/crmf99_err.txt; fail=1; }; done; done
echo "functions with crmf in the name: $($PSQL -d $DB -qAt -c "select count(*) from pg_proc where proname like '%crmf%'")"
for n in 316 317 318 319; do
  $PSQL -q -c "drop database if exists ${DB}_t" -c "create database ${DB}_t template $DB" 2>&1 | grep -v NOTICE
  r=$(cd $R && $PSQL -d ${DB}_t -qAt -f supabase/phase${n}_test.sql 2>&1 | grep -E "FAIL|RESULT" | sed 's/^psql:[^:]*:[0-9]*: //')
  echo "phase${n}_test on a database through phase 99 and CRM-F: $(echo "$r" | tail -1)"; echo "$r" | grep -c "FAIL" | sed 's/^/  fail lines: /'
done
$PSQL -q -c "drop database if exists ${DB}_t" 2>&1 | grep -v NOTICE
exit $fail
