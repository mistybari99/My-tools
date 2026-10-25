#!/bin/bash
# CRM-B runner. Local throwaway Postgres on port 5572 only (recipe: docs/HANDOVER_5.md; roles anon/authenticated/service_role must exist).
#   BASE=<db built through phase 98>  (default crmb_base; build it with: bash tests/sql/crmb_build.sh crmb_base 98)
#   bash tests/sql/crmb_run.sh        for each suite: a fresh clone of BASE, phases 303, 304, 305 pasted TWICE (any error fails), then the suite
PORT=${PORT:-5572}; BASE=${BASE:-crmb_base}
R=$(cd "$(dirname "$0")/../.." && pwd)
P="psql -h /tmp -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
fail=0
for f in 303 304 305; do
  DB=crmb_t$f
  psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB template $BASE" 2>&1 | grep -v NOTICE
  for round in 1 2; do for p in 303 304 305; do
    $P -d $DB -f $R/supabase/phase$p.sql >/dev/null 2>/tmp/crmb_err.txt || { echo "FAIL paste $p round $round"; head -5 /tmp/crmb_err.txt; fail=1; }
  done; done
  out=$(cd $R/supabase && psql -h /tmp -p $PORT -U postgres -d $DB -qAt -f phase${f}_test.sql 2>&1)
  echo "$out" | grep -E 'NOTICE:  FAIL|RESULT|ERROR' | head -40
  echo "$out" | grep -q "RESULT phase$f: .* 0 fail" || fail=1
done
[ $fail = 0 ] && echo "CRM-B SQL: all suites pass (pasted twice)" || echo "CRM-B SQL: FAILURES"
exit $fail
