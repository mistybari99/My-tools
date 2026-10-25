#!/bin/bash
# usage: run_a2.sh <db> [files...]   (default: all a2_*.sql in order).  The DB must be a copy of a final_build database:
#   createdb -T a2db a2t   (the script recreates it every time: no state is kept between runs)
DB=$1; shift
HERE="$(cd "$(dirname "$0")" && pwd)"; E=$HERE/../../e2e
psql -h /tmp -p 5544 -U postgres -qc "drop database if exists $DB" -c "create database $DB template ${TEMPLATE:-a2db}" >/dev/null 2>&1
FILES=${@:-$(ls $HERE/a2_*.sql)}
cat $E/00_common.sql $FILES > /tmp/a2_run_$DB.sql
psql -h /tmp -p 5544 -U postgres -d $DB -v mode=def -qAt -f /tmp/a2_run_$DB.sql 2>&1
# FIX probes (written after the batch fixes): each fix_*.sql is self-contained and runs in its OWN clone of the template (only when no explicit file list is given)
if [ -z "$*" ]; then REPO="$(cd "$HERE/../../../.." && pwd)"; for f in $(ls $HERE/fix_*.sql 2>/dev/null | LC_ALL=C sort); do
  psql -h /tmp -p 5544 -U postgres -qc "drop database if exists ${DB}_fx" -c "create database ${DB}_fx template ${TEMPLATE:-a2db}" >/dev/null 2>&1
  ( cd $REPO && psql -h /tmp -p 5544 -U postgres -d ${DB}_fx -v mode=def -qAt -f tests/sql/audit2/a2/$(basename $f) 2>&1 ); done
  psql -h /tmp -p 5544 -U postgres -qc "drop database if exists ${DB}_fx" >/dev/null 2>&1; fi
echo "---- summary"; psql -h /tmp -p 5544 -U postgres -d $DB -qAt -c "select count(*) filter (where ok) pass, count(*) filter (where not ok) fail from tt.ea"
