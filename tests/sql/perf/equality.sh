#!/bin/bash
# usage: equality.sh <db> [out-file]   -> EQ lines of tests/sql/perf/equality.sql (md5 of every function result). Diff two outputs: before vs after phase110.
HERE="$(cd "$(dirname "$0")" && pwd)"
psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -d "$1" -q -f "$HERE/equality.sql" 2>&1 | grep -E '^(psql:.*)?(NOTICE:  )?EQ |ERROR' | sed -E 's/^psql:[^ ]+ NOTICE:  //; s/^NOTICE:  //' > "${2:-/dev/stdout}"
