#!/bin/bash
# RPT-C3: run OLD web suites against THIS worktree's web folder. Most old tests hard-code /home/user/My-tools/web, so they are copied to a scratch folder with that path replaced.
# usage: bash tests/web/rptc3_regress.sh SCRATCH_DIR test_name [test_name ...]
SC=$1; shift
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"
rm -rf $SC; mkdir -p $SC
cp $HERE/*.js $HERE/*.json $SC/ 2>/dev/null
sed -i "s#/home/user/My-tools/web#$R/web#g; s#/home/user/My-tools/tests/web#$SC#g" $SC/*.js
export BOS_WEB_ROOT=$R/web
for t in "$@"; do
  echo "== $t"; (cd $R && timeout 400 node $SC/$t.js $SC 2>&1 | tail -4 | cut -c1-200)
done
