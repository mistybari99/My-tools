#!/bin/bash
# Phase 9 report scripts t1..t10 have printed results with "expect" comments, never assertions. This runs them on the phase-9 database (baseline) and on the
# database with every later phase applied, then diffs the outputs: any difference is a change of a phase-9 report number and must be explained.
#   usage: bash run_regress.sh        (needs Postgres on /tmp:5544)
REPO=${REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}; S=$REPO/tests/sql/p9; R=$REPO/supabase; P="psql -h /tmp -p 5544 -U postgres -q"
build() { bash $S/setup.sh $1 >/dev/null 2>&1; for ph in ${2:-}; do $P -d $1 -v ON_ERROR_STOP=0 -f $R/$ph.sql >/dev/null 2>&1; done; $P -d $1 -f $S/seed.sql >/dev/null 2>&1; }
build p9base "phase8 phase9"
build p9full "phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase28"
mkdir -p /tmp/p9out; n=0
for t in $S/t[0-9]*.sql; do b=$(basename $t .sql); for d in p9base p9full; do psql -h /tmp -p 5544 -U postgres -d $d -qAt -f $t 2>&1 | grep -v '^Time:' | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<uuid>/g; s/[0-9]+\.[0-9]+ ms/<ms>/g' > /tmp/p9out/$b.$d; done
  if ! diff -q /tmp/p9out/$b.p9base /tmp/p9out/$b.p9full >/dev/null; then n=$((n+1)); echo "DIFF $b: $(diff /tmp/p9out/$b.p9base /tmp/p9out/$b.p9full | grep -c '^[<>]') lines"; fi; done
echo "scripts with differences: $n"
