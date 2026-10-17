#!/bin/bash
# CRM-F: every SQL check in one go, on a local throwaway Postgres (never the live project).
#   1. base = fresh build through phase 98 (tests/sql/ORDER.txt), c316 = base + 316, c317 = + 317, c318 = + 318, c319 = + 319 (each phase pasted once; the suites run on a copy)
#   2. phase316_test .. phase319_test on their own database; before/after snapshot; race; older suites with and without CRM-F; the same on a build through phase 99
# usage: PORT=5574 bash tests/sql/crmf_run_all.sh        -> prints one RESULT line per check
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; export PORT=${PORT:-5574}; PSQL="psql -h /tmp -p $PORT -U postgres"
mk() { $PSQL -q -c "drop database if exists $1" -c "create database $1 template $2" 2>&1 | grep -v NOTICE; }
paste1() { $PSQL -d $1 -v ON_ERROR_STOP=1 -q -f $R/supabase/phase$2.sql 2>&1 | grep -v NOTICE; }
bash $HERE/crmf_build.sh crmf_base | tail -1
prev=crmf_base
for n in 316 317 318 319; do mk crmf_c$n $prev; paste1 crmf_c$n $n; prev=crmf_c$n; done
for n in 316 317 318 319; do
  mk crmf_t$n crmf_c$n
  echo "phase${n}_test: $(cd $R && $PSQL -d crmf_t$n -qAt -f supabase/phase${n}_test.sql 2>&1 | grep -E 'FAIL|RESULT' | sed 's/^psql:[^:]*:[0-9]*: //' | tr '\n' ' ')"
  $PSQL -q -c "drop database if exists crmf_t$n" 2>&1 | grep -v NOTICE
done
echo "before/after: $(BASE=crmf_base bash $HERE/crmf_before_after.sh 2>&1 | grep -E 'RESULT|FAIL|compared' | tr '\n' ' ')"
echo "race: $(BASE=crmf_base bash $HERE/crmf_race.sh 2>&1 | grep -E 'RESULT|accepted' | tr '\n' ' ')"
echo "older suites: $(SUITES='43 62 76 81' BASE=crmf_base bash $HERE/crmf_oldsuites.sh 2>&1 | tr '\n' ' ')"
UP_TO=99 bash $HERE/crmf_build.sh crmf_99 | tail -1
bash $HERE/crmf_after99.sh 2>&1 | tr '\n' ' '; echo
