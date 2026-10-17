#!/bin/bash
# RPT-C2: the web tests that touch the files this package changed (ia.js, index.html, salesx.js, recipes.js, forms_cash.js) + the new c2 test.
# usage: bash tests/web/c2_regress.sh      (then: git checkout -- tests/web; git clean -fq tests/web  - the tests rewrite screenshots)
HERE="$(cd "$(dirname "$0")" && pwd)"
for t in c2 ia nav nav2 control favsync settings2 salesx recipes allforms forms_links customers wave1_wiring wave1_comment_guard reports; do
  [ -f $HERE/${t}_test.js ] || continue
  out=$(timeout 280 /opt/node22/bin/node $HERE/${t}_test.js $HERE 2>&1 | tail -4)
  echo "== $t: $(echo "$out" | grep -E 'assert failures|checks|failed' | tr '\n' ' ') $(echo "$out" | grep -E '^errors' | tr '\n' ' ')"
done
