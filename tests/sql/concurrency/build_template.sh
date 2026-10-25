#!/bin/bash
# Builds the final DB (docs/PASTE_ORDER.md, order of tests/sql/paste_order.env incl. phase109 + phase111; NO109=1 builds without it = the failing-before state) and the clean concurrency seed into template db conc_tpl.
# usage: bash tests/sql/concurrency/build_template.sh [tpl=conc_tpl]    (env PGSOCK=/tmp PGPORT=5544)
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../../.." && pwd)"; TPL=${1:-conc_tpl}
export PGSOCK=${PGSOCK:-/tmp} PGPORT=${PGPORT:-5544}
. "$REPO/tests/sql/paste_order.env"; ORD=""; for f in $FOUNDATION $NEW; do [ -f "$REPO/supabase/$f.sql" ] || continue; if [ -n "$NO109" ] && { [ $f = phase109 ] || [ $f = phase111 ]; }; then continue; fi; ORD="$ORD $f"; done; ORD=$(echo $ORD)
bash $REPO/tests/sql/final_build.sh $TPL "$ORD" | tail -1
E=$REPO/tests/sql/e2e
cat $E/00_common.sql $E/01_setup.sql $HERE/seed_extra.sql | psql -h $PGSOCK -p $PGPORT -U postgres -d $TPL -qAt 2>&1 | grep -E 'FAIL|ERROR' | head
echo template $TPL ready
