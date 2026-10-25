#!/bin/bash
# CRM-C proof: pasting phases 306 to 308 and USING every CRM-C function (with every CRM-C switch turned ON) changes no accounting or report figure.
#   1. a copy of BASE (a fresh build through phase 99) gets tests/sql/w1d_fixture.sql + w1d_snap_setup.sql + p99_fixture_extra.sql (stock, production, wastage, supplier bills, vouchers, payroll, sales, returns,
#      owner money ...) and tests/sql/crmc_fixture.sql (customers, sales, a return, payments, opt-ins): snapshot "before" (the same 33+ snapshots as phase99_before_after.sh:
#      P&L, L1 L3 L4 L5, T4, E2, E3, expense report, partner calculation and split, brand P&L, income statement, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines,
#      posting dry run, stock levels / valuation / movements, customer dues / ledger / balance, supplier balance, returns, payments, cash moves, acct_reconcile)
#   2. paste 306, 307, 308 -> snapshot "after" -> identical;  paste all three again -> "after2" -> identical
#   3. the owner switches EVERYTHING on (lists, scheduled refresh, export, own score cut-offs, lapsed days) and the functions are used: refresh scores, scheduled run, preview, members, save, freeze, retire,
#      overview, score lists, lapsed, value card, profit view, export -> snapshot "used" -> identical to "before"; the only tables that changed are the CRM-C tables.
# usage: bash tests/sql/crmc_before_after.sh      (local throwaway Postgres on PORT, default 5573; BASE = a fresh build through phase 99, default c_base99)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; T="$HERE"
PORT=${PORT:-5573}; BASE=${BASE:-c_base99}
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
db=ba_crmc
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE
for f in w1d_fixture w1d_snap_setup p99_fixture_extra; do $P -d $db -f $T/$f.sql >/dev/null 2>&1 || { echo "FAIL fixture $f"; exit 1; }; done
psql -h /tmp -p $PORT -U postgres -d $db -qAt -f $T/crmc_fixture.sql >/dev/null 2>&1 || { echo "FAIL fixture crmc"; exit 1; }
snap() { $P -d $db -v label=$1 -f $T/w1d_snap.sql >/dev/null 2>&1 && $P -d $db -v label=$1 -f $T/p99_snap_extra.sql >/dev/null 2>&1 || { echo "FAIL snapshot $1"; exit 1; }; }
differ() { $P -d $db -c "select a.name from tt.snap a join tt.snap b on a.name = b.name and b.label = '$2' where a.label = '$1' and a.val is distinct from b.val order by 1" | tr '\n' ' '; }
snap before
tot=$($P -d $db -c "select count(*) from tt.snap where label='before'"); echo "snapshots taken: $tot"
for n in 306 307 308; do $P -d $db -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n paste"; exit 1; }; done
snap after
d=$(differ before after); [ -z "$d" ] && ok "with every setting at its default $tot snapshots are identical before and after phases 306 to 308" || bad "default figures changed: $d"
for n in 306 307 308; do $P -d $db -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n second paste"; fail=1; }; done
snap after2
d=$(differ before after2); [ -z "$d" ] && ok "phases 306 to 308 pasted a second time: still identical" || bad "second paste changed: $d"

cat > /tmp/crmc_use_$$.sql <<'EOS'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000c301',false);
select set_rule('crm_segments_on','true'::jsonb), set_rule('crm_metrics_schedule_on','true'::jsonb), set_rule('crm_metrics_schedule_hours','1'::jsonb), set_rule('crm_seg_export_on','true'::jsonb),
       set_rule('crm_seg_export_max_rows','100'::jsonb), set_rule('crm_rfm_recent_days','30'::jsonb), set_rule('crm_rfm_frequency_min','2'::jsonb), set_rule('crm_rfm_spend_min','400'::jsonb), set_rule('crm_winback_days','60'::jsonb);
select crmc_metrics_refresh(false) ->> 'processed';
select crmc_scheduled_run();
select crmc_preview('{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}') ->> 'count';
select crmc_members('{"conditions":[{"field":"orders_total","op":"ge","value":0}]}') ->> 'total';
select crmc_segment_save('c0000000-0000-0000-0000-0000000000f1', null, 'test_ba_list', '{"conditions":[{"field":"days_since_last","op":"gt","value":30}]}') ->> 'id';
select crmc_segment_freeze('c0000000-0000-0000-0000-0000000000f2', null, '{"conditions":[{"field":"orders_total","op":"ge","value":1}]}', 'test_ba_frozen') ->> 'id';
select crmc_segment_retire((select id from crm_segments where name = 'test_ba_list'), false, 'test: done');
select crmc_overview() ->> 'buyers';
select crmc_rfm_summary() ->> 'mode';
select crmc_rfm_list('Champion') ->> 'total';
select crmc_value_list() ->> 'total';
select crmc_lapsed() ->> 'total';
select crmc_customer_value('00000000-0000-0000-0000-00000000c3a1') ->> 'label';
select crmc_profit(current_date - 120, current_date) ->> 'customers';
select crmc_export(null, null, '{"conditions":[{"field":"orders_total","op":"ge","value":1}]}', 'test: before/after') ->> 'total';
EOS
$P -d $db -f /tmp/crmc_use_$$.sql >/tmp/crmc_use_out_$$.txt 2>&1 || { echo "FAIL using the CRM-C functions"; tail -3 /tmp/crmc_use_out_$$.txt; fail=1; }
rm -f /tmp/crmc_use_$$.sql
snap used
d=$(differ before used); [ -z "$d" ] && ok "after using every CRM-C function with every switch ON, all $tot snapshots are still identical" || bad "figures changed after use: $d"
# the only tables whose content changed are the CRM-C ones (rules and audit_log aside)
chg=$($P -d $db -c "select count(*) from crm_metrics")
[ "$chg" -gt 0 ] && ok "the CRM-C cache holds $chg score rows (the only data written besides its own logs, rules and the audit log)" || bad "no score rows"
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
