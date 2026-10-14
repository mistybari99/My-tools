#!/bin/bash
# usage: bash tests/sql/audit2/a3/run.sh [dbname]   (scratch PG16 on /tmp:5544; builds <db> from the canonical order if it does not exist, then runs the scenario)
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../../../.." && pwd)"; DB=${1:-a3run}
P="psql -h /tmp -p 5544 -U postgres"
$P -Atc "select 1 from pg_database where datname='$DB'" | grep -q 1 || bash $REPO/tests/sql/final_build.sh $DB >/dev/null
cd $HERE
cat $REPO/tests/sql/e2e/00_common.sql a3_scenario.sql a3_probes.sql $(ls fix_*.sql 2>/dev/null) > /tmp/a3_run_$DB.sql
$P -d $DB -v mode=def -qAt -f /tmp/a3_run_$DB.sql 2>&1
