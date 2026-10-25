#!/bin/bash
# usage: build.sh DB [last_phase_number]   builds a fresh DB through phase8..LAST on port 5572 from the CRM-B worktree
W=$(cd "$(dirname "$0")/../.." && pwd)
S=$W/tests/sql; R=$W/supabase
P="psql -h /tmp -p 5572 -U postgres -v ON_ERROR_STOP=1 -q"
DB=$1; LAST=${2:-98}
psql -h /tmp -p 5572 -U postgres -q -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE
$P -d $DB -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
for f in $S/mock_auth2.sql $R/schema.sql $R/phase2.sql $S/mock_storage.sql $R/phase3.sql $R/phase4.sql $R/ALL_NEW.sql; do $P -d $DB -f $f >/dev/null 2>/tmp/crmb_errf.txt || { echo FAIL $f; head -5 /tmp/crmb_errf.txt; exit 1; }; done
for ph in $(grep -v "^#" $S/ORDER.txt); do
  n=${ph#phase}; [ "$n" -gt "$LAST" ] && break
  $P -d $DB -f $R/$ph.sql 2>&1 | grep -v NOTICE | head -10
done
echo built $DB
