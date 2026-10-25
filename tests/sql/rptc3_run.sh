#!/bin/bash
# RPT-C3: run the SQL suites. usage: PORT=5710 bash tests/sql/rptc3_run.sh [N ...]   (default: 458 .. 468)
# For each N: build a fresh local database through phase 99 + the RPT-C3 phases up to N, run supabase/phaseN_test.sql, print the FAIL / ERROR / RESULT lines.
# Never the live project: local throwaway Postgres only (port PORT, default 5710, socket dir /tmp).
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PORT:-5710}
LIST="$@"; [ -z "$LIST" ] && LIST="458 459 460 461 462 463 464 465 466 467 468"
for n in $LIST; do
  [ -f $R/supabase/phase${n}_test.sql ] || { echo "phase$n: no test file yet"; continue; }
  PORT=$PORT bash $HERE/rptc3_build.sh rptc3_t$n $n > /tmp/rptc3_build_$n.txt 2>&1
  grep -E "ERROR|FAIL" /tmp/rptc3_build_$n.txt | head -3
  (cd $R && psql -h /tmp -p $PORT -U postgres -d rptc3_t$n -qAt -f supabase/phase${n}_test.sql 2>&1) > /tmp/rptc3_out_$n.txt
  echo "== phase$n"; grep -E "FAIL|ERROR|RESULT|\(got|did not" /tmp/rptc3_out_$n.txt | sed 's/^psql:[^:]*:[0-9]*: //' | head -40
done
