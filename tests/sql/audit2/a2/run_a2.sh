#!/bin/bash
# usage: run_a2.sh <db> [files...]   (default: all a2_*.sql in order).  The DB must be a copy of a final_build database:
#   createdb -T a2db a2t   (the script recreates it every time: no state is kept between runs)
DB=$1; shift
HERE="$(cd "$(dirname "$0")" && pwd)"; E=$HERE/../../e2e
psql -h /tmp -p 5544 -U postgres -qc "drop database if exists $DB" -c "create database $DB template ${TEMPLATE:-a2db}" >/dev/null 2>&1
FILES=${@:-$(ls $HERE/a2_*.sql)}
cat $E/00_common.sql $FILES > /tmp/a2_run_$DB.sql
psql -h /tmp -p 5544 -U postgres -d $DB -v mode=def -qAt -f /tmp/a2_run_$DB.sql 2>&1
echo "---- summary"; psql -h /tmp -p 5544 -U postgres -d $DB -qAt -c "select count(*) filter (where ok) pass, count(*) filter (where not ok) fail from tt.ea"
