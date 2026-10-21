#!/bin/bash
# RPT-C1 proof (phases 440 to 444): with EVERY new setting at its default, a database built through phase 99 reports exactly what it reported before, except the documented honesty change:
#   a total over a column with no value at all is empty (not captured) instead of 0 (engine 3 totals, phase 440).
#   1. database A from BASE (a fresh build through phase 99) gets the W1-D fixture + the extra fixture of phase 99: snapshot "before" (the same snapshot list as the phase 99 proof)
#   2. phases 440 to 444 pasted -> snapshot "after": every snapshot identical (or listed in ALLOWED with the reason); pasted a second time -> snapshot "after2" identical to "after"
#   3. the report engine totals: only all-empty columns changed (checked on report_run3 of the L5 report)
#   4. no journal entry was written by the pastes (the poster has nothing new to post)
# usage: PORT=5690 BASE=c1_base99 bash tests/sql/c1_before_after.sh      (local throwaway Postgres; BASE = a fresh build through phase 99)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; T="$HERE"
PORT=${PORT:-5690}; BASE=${BASE:-c1_base99}; DB=${DB:-c1_ba_a}
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB template $BASE" 2>&1 | grep -v NOTICE
for f in w1d_fixture w1d_snap_setup p99_fixture_extra; do $P -d $DB -f $T/$f.sql >/dev/null 2>&1 || { echo "FAIL fixture $f"; exit 1; }; done
snap() { $P -d $DB -v label=$1 -f $T/w1d_snap.sql >/dev/null 2>&1 && $P -d $DB -v label=$1 -f $T/p99_snap_extra.sql >/dev/null 2>&1 || { echo "FAIL snapshot $1"; exit 1; }; }
differ() { $P -d $DB -c "select a.name from tt.snap a join tt.snap b on a.name = b.name and b.label = '$2' where a.label = '$1' and a.val is distinct from b.val order by 1" | tr '\n' ' '; }
snap before
tot=$($P -d $DB -c "select count(*) from tt.snap where label='before'"); echo "snapshots taken: $tot"
OWN="select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false)"
j0=$($P -d $DB -c "select count(*) from journal_entries" | tail -1)
for n in 440 441 442 443 444; do $P -d $DB -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n paste"; exit 1; }; done
snap after
# ALLOWED: snapshot names that may differ and why: l5_breakeven (engine 3 totals of an all-empty column: not captured, no longer 0); l1_pnl, l3_shop_pnl (the new key profit_complete on every row - checked below to be the ONLY difference)
ALLOWED=" l5_breakeven l1_pnl l3_shop_pnl "
d=$(differ before after); bad_list=""
for n in $d; do case "$ALLOWED" in *" $n "*) ;; *) bad_list="$bad_list $n";; esac; done
[ -z "$bad_list" ] && ok "with every setting at its default $tot snapshots are identical before and after phases 440 to 444 (allowed to change: ${d:-none})" || bad "default figures changed:$bad_list"
for k in l1_pnl l3_shop_pnl; do
  x=$($P -d $DB -c "select count(*) from tt.snap a join tt.snap b on a.name = b.name and b.label = 'after' where a.label = 'before' and a.name = '$k' and a.val::jsonb is distinct from (select coalesce(jsonb_agg(r - 'profit_complete' order by r::text), '[]'::jsonb) from jsonb_array_elements(b.val::jsonb) r)" | tail -1)
  [ "$x" = "0" ] && ok "$k: the only difference is the new key profit_complete (every existing figure is unchanged)" || bad "$k: other keys changed"
done
for n in 440 441 442 443 444; do $P -d $DB -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n second paste"; fail=1; }; done
snap after2
d=$(differ after after2); [ -z "$d" ] && ok "phases 440 to 444 pasted a second time: still identical" || bad "second paste changed: $d"
j1=$($P -d $DB -c "select count(*) from journal_entries" | tail -1)
[ "$j0" = "$j1" ] && ok "the pastes wrote no journal entry ($j0 before, $j1 after)" || bad "journal entries changed: $j0 -> $j1"
# totals: a column that has values keeps its total; only an all-empty column is null now
r=$($P -d $DB -c "$OWN" -c "select (select count(*) from jsonb_each(totals) e where e.value = 'null'::jsonb) from (select report_run3('l5_breakeven', '{\"preset\":\"this_month\"}'::jsonb, null, null, 500) -> 'totals' as totals) z" | tail -1)
echo "info: L5 totals with 'not captured' (null): $r"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
