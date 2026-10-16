#!/bin/bash
# CRM-F: older suites must show the same result with phases 316 to 319 applied as without them (same failing lines).
# usage: BASE=crmf_base PORT=5574 SUITES="43 62 8" bash tests/sql/crmf_oldsuites.sh      (BASE = a fresh build through phase 98)
PORT=${PORT:-5574}; BASE=${BASE:-crmf_base}; SUITES=${SUITES:-"43"}; R=$(cd "$(dirname "$0")/../.." && pwd)
PSQL="psql -h /tmp -p $PORT -U postgres"; fail=0
for d in cfo_a cfo_b; do $PSQL -q -c "drop database if exists $d" -c "create database $d template $BASE" 2>&1 | grep -v NOTICE; done
for n in 316 317 318 319; do $PSQL -d cfo_b -v ON_ERROR_STOP=1 -q -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n"; exit 1; }; done
for s in $SUITES; do
  for d in cfo_a cfo_b; do
    # every suite needs its own fresh copy
    $PSQL -q -c "drop database if exists ${d}_$s" -c "create database ${d}_$s template $d" 2>&1 | grep -v NOTICE
    (cd $R && $PSQL -d ${d}_$s -qAt -f supabase/phase${s}_test.sql 2>&1 | grep -E "FAIL|RESULT|ERROR" | sed 's/^psql:[^:]*:[0-9]*: //' > /tmp/cfo_${d}_$s.txt)
    $PSQL -q -c "drop database if exists ${d}_$s" 2>&1 | grep -v NOTICE
  done
  if diff -q /tmp/cfo_cfo_a_$s.txt /tmp/cfo_cfo_b_$s.txt >/dev/null; then echo "PASS suite $s: same lines without and with CRM-F ($(tail -1 /tmp/cfo_cfo_b_$s.txt))"; else echo "FAIL suite $s differs"; diff /tmp/cfo_cfo_a_$s.txt /tmp/cfo_cfo_b_$s.txt | head -10; fail=1; fi
done
exit $fail
