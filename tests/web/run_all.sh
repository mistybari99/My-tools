#!/bin/bash
# Run every tests/web/*_test.js ONE AT A TIME with a per-test timeout; continue after failures; summary table; non-zero exit if any exit code != 0.
# usage: bash tests/web/run_all.sh [pattern]      env: WEB_DIR (web folder to test, default <repo>/web), TIMEOUT (seconds, default 300), PORT (fixed port; default = free port per test)
HERE="$(cd "$(dirname "$0")" && pwd)"
TIMEOUT=${TIMEOUT:-300}
PAT=${1:-}
LOGDIR=${LOGDIR:-$(mktemp -d)}
rows=(); bad=0
for f in "$HERE"/*_test.js; do
  n=$(basename "$f" .js); [ -n "$PAT" ] && [[ "$n" != *$PAT* ]] && continue
  timeout "$TIMEOUT" node "$f" "$HERE" > "$LOGDIR/$n.log" 2>&1; rc=$?
  # pass/fail counts when the test prints them
  pf=$(grep -oE '[0-9]+ pass(ed)? */ *[0-9]+ fail(ed)?|pass(ed)?:? *[0-9]+,? *fail(ed)?:? *[0-9]+|checked [0-9]+, failed [0-9]+|assert failures: [0-9]+|[0-9]+ passed, [0-9]+ failed' "$LOGDIR/$n.log" | tail -1)
  [ -z "$pf" ] && pf=$(grep -cE '^(FAIL|not ok|  FAIL)' "$LOGDIR/$n.log" | sed 's/^/FAIL lines: /')
  [ $rc -eq 124 ] && pf="TIMEOUT ${TIMEOUT}s"
  [ $rc -ne 0 ] && bad=$((bad+1))
  rows+=("$(printf '%-28s %-5s %s' "$n" "$rc" "$pf")")
  echo "${rows[-1]}"
done
echo; echo "=== SUMMARY (logs in $LOGDIR) ==="; printf '%-28s %-5s %s\n' TEST EXIT RESULT
printf '%s\n' "${rows[@]}"
echo "tests with non-zero exit: $bad of ${#rows[@]}"
[ $bad -eq 0 ]
