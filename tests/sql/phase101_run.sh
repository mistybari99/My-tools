#!/bin/bash
# Fresh build (canonical order + phase101) and the phase101 suite. usage (repo root): bash tests/sql/phase101_run.sh <dbname>
HERE="$(cd "$(dirname "$0")" && pwd)"; DB=${1:-rec_t}
ORD=$(grep '^ORDER=' "$HERE/final_build.sh" | sed 's/^ORDER=${2:-"//; s/"}$//')
bash "$HERE/final_build.sh" "$DB" "$ORD phase101" >/dev/null 2>&1
psql -h /tmp -p 5544 -U postgres -d "$DB" -qAt -f "$HERE/../../supabase/phase101_test.sql" 2>&1 | grep -E "FAIL|RESULT|\(got|did not"
