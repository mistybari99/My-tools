#!/bin/bash
# RPT-C3: run the web suites that touch the files RPT-C3 changed (ia.js, nav.js, pos.js, forms_cash.js, index.html) plus the new rptc3_test.js, then restore tests/web (the tests write screenshots).
# usage: bash tests/web/rptc3_run_all.sh [test names...]
export BOS_WEB_ROOT="$(cd "$(dirname "$0")/../../web" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
LIST="$@"; [ -z "$LIST" ] && LIST="rptc3_test ia_test nav_test nav2_test control_test favsync_test settings2_test wave1_wiring_test wave1_comment_guard_test pos2_test pos_units_test allforms_test daybook_test reports_test"
for t in $LIST; do
  [ -f $HERE/$t.js ] || { echo "no $t"; continue; }
  echo "== $t"; (cd $R && timeout 400 node tests/web/$t.js $HERE 2>&1 | tail -5 | cut -c1-220)
done
(cd $R && git checkout -- tests/web && git clean -fq tests/web -e rptc3_test.js -e rptc3_run_all.sh -e rptc3_common.js)
