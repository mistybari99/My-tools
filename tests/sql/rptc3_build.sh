#!/bin/bash
# RPT-C3: build a fresh local throwaway database through phase99 (tests/sql/ORDER.txt), then optionally the RPT-C3 phases 458..468.
# usage: PORT=5710 bash tests/sql/rptc3_build.sh DBNAME [LASTPHASE]   (LASTPHASE = a number 458..468: the RPT-C3 phases up to it are pasted; none = through phase 99 only)   (never the live project; local Postgres only)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)/supabase"; S=$HERE
PORT=${PORT:-5710}
P="psql -h /tmp -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
DB=$1; MODE=$2
ORDER=$(grep -v "^#" $S/ORDER.txt)
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE
$P -d $DB -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
for f in $S/mock_auth2.sql $R/schema.sql $R/phase2.sql $S/mock_storage.sql $R/phase3.sql $R/phase4.sql $R/ALL_NEW.sql; do $P -d $DB -f $f >/dev/null 2>/tmp/rptc3_errf.txt || { echo FAIL $f; head -5 /tmp/rptc3_errf.txt; exit 1; }; done
for ph in $ORDER; do $P -d $DB -f $R/$ph.sql 2>&1 | grep -v NOTICE | head -10; done
if [ -n "$MODE" ]; then for n in 458 459 460 461 462 463 464 465 466 467 468; do [ $n -le $MODE ] && $P -d $DB -f $R/phase$n.sql 2>&1 | grep -v NOTICE | head -10; done; fi
echo built $DB
