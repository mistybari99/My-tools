#!/bin/bash
# usage: run.sh <db> [file...]   (default: all a5_*.sql in order). Reuses tests/sql/e2e/00_common.sql (tt.* helpers).
DB=$1; shift; H="$(cd "$(dirname "$0")" && pwd)"; FILES=${@:-$(ls $H/a5_*.sql | LC_ALL=C sort)}
cat $H/../../e2e/00_common.sql $FILES > /tmp/a5_run_$DB.sql
psql -h /tmp -p 5544 -U postgres -d $DB -v mode=def -qAt -f /tmp/a5_run_$DB.sql 2>&1
# FIX probes (written after the batch fixes): each fix_*.sql is self-contained and runs in its OWN clone of $TEMPLATE (set by run_all.sh; skipped when unset)
if [ -n "$TEMPLATE" ] && [ -z "$*" ]; then REPO="$(cd "$H/../../../.." && pwd)"; for f in $(ls $H/fix_*.sql 2>/dev/null | LC_ALL=C sort); do
  psql -h /tmp -p 5544 -U postgres -qc "drop database if exists ${DB}_fx" -c "create database ${DB}_fx template $TEMPLATE" >/dev/null 2>&1
  ( cd $REPO && psql -h /tmp -p 5544 -U postgres -d ${DB}_fx -v mode=def -qAt -f tests/sql/audit2/a5/$(basename $f) 2>&1 ); done
  psql -h /tmp -p 5544 -U postgres -qc "drop database if exists ${DB}_fx" >/dev/null 2>&1; fi
