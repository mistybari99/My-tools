#!/bin/bash
# Failing-before / passing-after for the six findings of CONCURRENCY_REPORT.md (fixes are in supabase/phase109.sql; proposed_fixes.sql is the historic scratch version).
#   before = template conc_tpl_before built WITHOUT phase109 (NO109=1)  -> the finding scenarios must show FAIL lines
#   after  = template conc_tpl_after  built WITH phase109               -> every line must be PASS
# usage: bash tests/sql/concurrency/verify_fixes.sh [before|after|both] [scenario ...]    default: both, s04 s08 s09b s10 s12 s13   (s10 = F3, fixed by phase105 not 109: only FAIL-before is expected to stay)
HERE="$(cd "$(dirname "$0")" && pwd)"; export PGHOST=${PGSOCK:-/tmp} PGPORT=${PGPORT:-5544} PGUSER=postgres
W=${1:-both}; shift; SC=${@:-s04 s08 s09b s12 s13}
run() { # run <tag> <template>
  export TPL=$2 OUT=$HERE/out_$1; rm -rf $OUT; mkdir -p $OUT
  echo "=== $1 (template $2)"; for s in $SC; do bash $HERE/$s.sh; done 2>&1 | grep -E '^\s+(PASS|FAIL)' | grep -v 'recon\|dupje\|\.tb \|\.ap\|\.gl'
  echo "$1: $(grep -c PASS $OUT/results.tsv) PASS, $(grep -c FAIL $OUT/results.tsv) FAIL"
}
if [ $W = before ] || [ $W = both ]; then NO109=1 bash $HERE/build_template.sh conc_tpl_before | tail -1; run before conc_tpl_before; fi
if [ $W = after ] || [ $W = both ]; then bash $HERE/build_template.sh conc_tpl_after | tail -1; run after conc_tpl_after; fi
