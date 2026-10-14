#!/bin/bash
# usage: run.sh <db> [file...]   (default: all a5_*.sql in order). Reuses tests/sql/e2e/00_common.sql (tt.* helpers).
DB=$1; shift; H="$(cd "$(dirname "$0")" && pwd)"; FILES=${@:-$(ls $H/a5_*.sql | LC_ALL=C sort)}
cat $H/../../e2e/00_common.sql $FILES > /tmp/a5_run_$DB.sql
psql -h /tmp -p 5544 -U postgres -d $DB -v mode=def -qAt -f /tmp/a5_run_$DB.sql 2>&1
