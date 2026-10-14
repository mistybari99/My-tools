#!/bin/bash
# Builds the final DB (docs/PASTE_ORDER.md, phases 72..103) and the clean concurrency seed into template db conc_tpl.
# usage: bash tests/sql/concurrency/build_template.sh [tpl=conc_tpl]    (env PGSOCK=/tmp PGPORT=5544)
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../../.." && pwd)"; TPL=${1:-conc_tpl}
export PGSOCK=${PGSOCK:-/tmp} PGPORT=${PGPORT:-5544}
ORD="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase70 phase71 phase72 phase73 phase74 phase75 phase76 phase77 phase78 phase79 phase80 phase81 phase82 phase83 phase84 phase85 phase86 phase87 phase88 phase90 phase91 phase89 phase92 phase93 phase95 phase94 phase96 phase97 phase98 phase99 phase100 phase101 phase103"
bash $REPO/tests/sql/final_build.sh $TPL "$ORD" | tail -1
E=$REPO/tests/sql/e2e
cat $E/00_common.sql $E/01_setup.sql $HERE/seed_extra.sql | psql -h $PGSOCK -p $PGPORT -U postgres -d $TPL -qAt 2>&1 | grep -E 'FAIL|ERROR' | head
echo template $TPL ready
