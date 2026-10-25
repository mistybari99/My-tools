#!/bin/bash
# A4 cash/accounting reconciliation scenarios. usage: run_a4.sh [base_db]  (base_db = a fresh final_build.sh database; default a4db)
# Copies the base db to a4run (template), runs e2e 00_common + the A4 files in ONE psql session, prints PASS/FAIL notices and ECHO lines.
BASE=${1:-a4db}; HERE="$(cd "$(dirname "$0")" && pwd)"; E2E="$HERE/../../e2e"
psql -h /tmp -p 5544 -U postgres -q -c "drop database if exists a4run" -c "create database a4run template $BASE" 2>&1 | grep -v NOTICE
cat "$E2E/00_common.sql" "$HERE"/a4_0[1-9]*.sql > /tmp/a4_run.sql
psql -h /tmp -p 5544 -U postgres -d a4run -v mode=rec -qAt -f /tmp/a4_run.sql 2>&1
# FIX probes (written after the batch fixes): each fix_*.sql is self-contained (it \i-includes a4_01_day.sql) and runs in its OWN clone of the base db
REPO="$(cd "$HERE/../../../.." && pwd)"
for f in $(ls "$HERE"/fix_*.sql 2>/dev/null | LC_ALL=C sort); do
  psql -h /tmp -p 5544 -U postgres -q -c "drop database if exists a4fx" -c "create database a4fx template $BASE" 2>&1 | grep -v NOTICE
  ( cd "$REPO" && psql -h /tmp -p 5544 -U postgres -d a4fx -v mode=def -qAt -f tests/sql/audit2/a4/$(basename $f) 2>&1 )
done
psql -h /tmp -p 5544 -U postgres -q -c "drop database if exists a4fx" 2>&1 | grep -v NOTICE
