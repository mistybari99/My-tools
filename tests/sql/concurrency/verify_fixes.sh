#!/bin/bash
# Builds template conc_tpl_fixed = conc_tpl + proposed_fixes.sql and re-runs the scenarios that failed, with OUT=out_fixed. Nothing in supabase/ is touched.
HERE="$(cd "$(dirname "$0")" && pwd)"; export PGHOST=${PGSOCK:-/tmp} PGPORT=${PGPORT:-5544} PGUSER=postgres
psql -qAtX -d postgres -c "drop database if exists conc_tpl_fixed" -c "create database conc_tpl_fixed template conc_tpl" >/dev/null
psql -qAtX -d conc_tpl_fixed -f $HERE/proposed_fixes.sql 2>&1 | grep -E 'patched|ERROR'
export TPL=conc_tpl_fixed OUT=$HERE/out_fixed; rm -rf $OUT; mkdir -p $OUT
for s in ${@:-s04 s08 s09b s10 s12 s13}; do bash $HERE/$s.sh; done 2>&1 | grep -E '^\s+(PASS|FAIL)' | grep -v 'recon\|dupje\|\.tb \|\.ap\|\.gl'
