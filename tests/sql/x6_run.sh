#!/bin/bash
# X6 (market intelligence) SQL suites. usage: PGPORT=5850 bash tests/sql/x6_run.sh [487 488 489 490]
# Needs a built base database named x6base (bash tests/sql/build_fresh_db.sh x6base with ORDER=all, phases 8..478 plus 487..490 applied).
# Each suite runs in its own copy of x6base (createdb -T). Local throwaway Postgres only; never the live project.
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PGPORT:-5850}
LIST="$@"; [ -z "$LIST" ] && LIST="487 488 489 490"
for n in $LIST; do
  psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists x6t$n" -c "create database x6t$n template x6base" 2>&1 | grep -v NOTICE
  (cd $R && psql -h /tmp -p $PORT -U postgres -d x6t$n -v ON_ERROR_STOP=1 -qAt -f supabase/phase${n}_test.sql 2>&1) > /tmp/x6pg/out_$n.txt
  echo "== phase$n"; grep -E "FAIL|ERROR|pass,|got:|did not" /tmp/x6pg/out_$n.txt | sed 's/^psql:[^:]*:[0-9]*: //' | head -40
  psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists x6t$n" 2>&1 | grep -v NOTICE
done
