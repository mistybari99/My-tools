#!/bin/bash
# CRM-F: build a fresh local throwaway database (phases 8 to 98 of tests/sql/ORDER.txt) on PORT (default 5574).
# usage: bash tests/sql/crmf_build.sh <dbname>      (never the live project; local Postgres only)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
PORT=${PORT:-5574}; DB=$1
S=$HERE; SQ=$R/supabase
P="psql -h /tmp -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
UP_TO=${UP_TO:-98}
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE
$P -d $DB -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
for f in $S/mock_auth2.sql $SQ/schema.sql $SQ/phase2.sql $S/mock_storage.sql $SQ/phase3.sql $SQ/phase4.sql $SQ/ALL_NEW.sql; do
  $P -d $DB -f $f >/dev/null 2>/tmp/errf_crmf.txt || { echo FAIL $f; head -5 /tmp/errf_crmf.txt; exit 1; }
done
for ph in $(grep -v "^#" $S/ORDER.txt); do
  n=${ph#phase}; [ "$n" -gt "$UP_TO" ] && continue
  $P -d $DB -f $SQ/$ph.sql 2>&1 | grep -v NOTICE | head -10
done
echo built $DB
