#!/bin/bash
# Runs the whole concurrency suite and prints the result table.
#   usage: bash tests/sql/concurrency/run_all.sh [s01 s02 ...]       env: N=<sessions>  SKIP_BUILD=1  TPL=<template db>  OUT=<dir>
# Needs the scratch Postgres 16 (socket /tmp, port 5544; restart: su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pg5544 -o '-p 5544 -k /tmp' -l /tmp/pg5544.log start").
HERE="$(cd "$(dirname "$0")" && pwd)"; export OUT=${OUT:-$HERE/out}
[ -z "$SKIP_BUILD" ] && [ -z "$TPL" ] && bash $HERE/build_template.sh
rm -rf "$OUT"; mkdir -p "$OUT"
LM=$(stat -c %s /tmp/pg5544.log 2>/dev/null || echo 0)
for s in ${@:-s01 s01c s02 s03 s04 s05 s06 s07 s08 s09 s09b s10 s11 s12 s13 s14}; do echo "=== $s"; bash $HERE/$s.sh; done 2>&1 | tee $OUT/run.log | grep -E '^(===|\s+(PASS|FAIL))' | grep -E '^===|FAIL|\.a |\.dl|S0[0-9]ctl|ctl' 
echo; echo "TOTAL: $(grep -c PASS $OUT/results.tsv) PASS, $(grep -c FAIL $OUT/results.tsv) FAIL"; echo "FAILS:"; grep FAIL $OUT/results.tsv | cut -f1,2,4
echo "deadlock lines in the server log during this run (all DBs): $(tail -c +$((LM+1)) /tmp/pg5544.log | grep -c 'deadlock detected')"
