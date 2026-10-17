#!/bin/bash
# W1-FIX proof (phases 140 to 143, docs/integration/W1-FIX.md): with the three new settings at their defaults (void_follows_return_rules OFF, supplier_pay_over_cumulative_days 0,
# exit_revoke_mode off) a database that got phases 88 to 99 AND 140 to 143 reports exactly what a database built only through phase 87 reports.
# It runs tests/sql/phase99_before_after.sh with the four extra phases (same fixture, same 30+ snapshots, paste twice, second wave of records through every hooked function
# - including void_sale, pay_supplier and employee_status_set, which now carry the W1-FIX hooks - on this DB and on a twin without any of the phases), then checks the four
# W1-FIX hooks are in place and that the Wave 1 hooks of phase99 are still all there.
# usage: bash tests/sql/w1fix_before_after.sh      (local throwaway Postgres on PORT, default 5570; BASE = a fresh build through phase 87)
HERE="$(cd "$(dirname "$0")" && pwd)"
PORT=${PORT:-5570}; BASE=${BASE:-base87}; export PORT BASE
export DBP=${DBP:-bafix} PHASES="88 89 90 91 92 93 94 95 96 97 98 99 140 141 142 143"
bash $HERE/phase99_before_after.sh; rc=$?
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
w=$($P -d ${DBP}_a -c "select count(*) from jsonb_array_elements(public._w1x_hooks_state()) x where (x->>'present')::boolean")
i=$($P -d ${DBP}_a -c "select count(*) from jsonb_array_elements(public._i1_hooks_state()) x where (x->>'present')::boolean")
if [ "$w" = "4" ] && [ "$i" = "37" ]; then echo "PASS all 4 W1-FIX hooks and all 37 Wave 1 hooks are installed while nothing changed"; else echo "FAIL hooks: W1-FIX $w of 4, Wave 1 $i of 37"; rc=1; fi
[ $rc = 0 ] && echo "RESULT w1fix before/after: all equal" || echo "RESULT w1fix before/after: DIFFERENCES"
exit $rc
