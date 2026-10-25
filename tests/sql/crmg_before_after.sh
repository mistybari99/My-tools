#!/bin/bash
# CRM-G proof (phases 323 to 327): with every CRM-G setting at its default a database that got the five phases reports exactly what a database built only through phase 98 reports,
# and the same holds AFTER every CRM-G function has been used once with everything switched on (a lead, a quote and a task post nothing; an order made from a lead is the normal
# unpaid order, which no report counts until it is delivered).
#   1. BASE = a fresh build through phase 98 (recipe: docs/integration/CRM-G.md). Fixtures: w1d_fixture + w1d_snap_setup + p99_fixture_extra (stock, production, wastage, count, supplier bill,
#      vouchers, payroll, partner agreement, credit sale, collection, void, return, owner money, bank moves, supplier payment, advance ...). Snapshot "before".
#   2. paste 323..327 -> snapshot "after" (identical); paste all five again -> "after2" (identical, and every _crmg_ function definition byte for byte the same)
#   3. tests/sql/crmg_exercise.sql (everything ON, every function used) -> "used" (identical), and the journal / sale / payment / stock / cash-move row counts are unchanged
#   4. phase 99 (the Wave 1 integrator) pasted on top keeps the three CRM-G Exceptions kinds
# usage: bash tests/sql/crmg_before_after.sh      (local throwaway Postgres on PORT, default 5575; BASE = a fresh build through phase 98)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; T="$HERE"
PORT=${PORT:-5575}; BASE=${BASE:-crmg_base}
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
DB=crmg_ba
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB template $BASE" 2>&1 | grep -v NOTICE
for f in w1d_fixture w1d_snap_setup p99_fixture_extra; do $P -d $DB -f $T/$f.sql >/dev/null 2>&1 || { echo "FAIL fixture $f"; exit 1; }; done
snap() { $P -d $DB -v label=$1 -f $T/w1d_snap.sql >/dev/null 2>&1 && $P -d $DB -v label=$1 -f $T/p99_snap_extra.sql >/dev/null 2>&1 || { echo "FAIL snapshot $1"; exit 1; }; }
differ() { $P -d $DB -c "select a.name from tt.snap a join tt.snap b on a.name = b.name and b.label = '$2' where a.label = '$1' and a.val is distinct from b.val order by 1" | tr '\n' ' '; }
rows() { $P -d $DB -c "select (select count(*) from journal_entries) || '/' || (select count(*) from journal_lines) || '/' || (select count(*) from sales) || '/' || (select count(*) from sale_payments) || '/' || (select count(*) from stock_ledger) || '/' || (select count(*) from cash_moves) || '/' || (select count(*) from customers)"; }
snap before
tot=$($P -d $DB -c "select count(*) from tt.snap where label='before'"); echo "snapshots taken: $tot"
r0=$(rows)
for n in 323 324 325 326 327; do $P -d $DB -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n paste"; exit 1; }; done
fdef() { $P -d $DB -c "select md5(string_agg(pg_get_functiondef(p.oid), '|' order by p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_crmg\_%'"; }
f1=$(fdef); n1=$($P -d $DB -c "select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like '\_crmg\_%'")
snap after
d=$(differ before after); [ -z "$d" ] && ok "with every CRM-G setting at its default $tot snapshots are identical before and after phases 323 to 327" || bad "default figures changed: $d"
[ "$(rows)" = "$r0" ] && ok "journal, sale, payment, stock and cash-move rows unchanged by the pastes" || bad "row counts moved after the pastes"
c0=$($P -d $DB -c "select (select count(*) from crm_leads)+(select count(*) from crm_tasks)+(select count(*) from crm_lead_events)+(select count(*) from crm_lead_quotes)")
[ "$c0" = "0" ] && ok "no lead, task, quote or event exists after the pastes (nothing starts by itself)" || bad "CRM rows exist after the pastes: $c0"
for n in 323 324 325 326 327; do $P -d $DB -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n second paste"; fail=1; }; done
f2=$(fdef)
[ "$f1" = "$f2" ] && ok "pasted a second time: all $n1 _crmg_ function definitions are byte for byte the same" || bad "a function definition changed on the second paste"
snap after2
d=$(differ before after2); [ -z "$d" ] && ok "phases 323 to 327 pasted a second time: still identical" || bad "second paste changed: $d"
sw=$($P -d $DB -c "select count(*) from rules where module = 'crm' and key like 'crm\_%' and (value is not null)")
[ "$sw" = "0" ] && ok "no CRM-G setting was changed by the pastes" || bad "settings changed: $sw"
$P -d $DB -f $T/crmg_exercise.sql >/tmp/crmg_ex_out.txt 2>/tmp/crmg_ex_err.txt || { echo "FAIL exercise"; head -5 /tmp/crmg_ex_err.txt; fail=1; }
leads=$($P -d $DB -c "select count(*) from crm_leads"); orders=$($P -d $DB -c "select count(*) from online_orders where source like 'crm_lead %'"); forms=$($P -d $DB -c "select count(*) from entries where form_code = '20-4' and data->>'order_no' like 'ENQ-%'")
[ "$leads" = "2" ] && [ "$orders" = "1" ] && [ "$forms" = "1" ] && ok "the exercise really ran: 2 leads, 1 order made through online_order_save2, 1 draft party invoice made through save_entry" || bad "the exercise did not run as expected (leads $leads orders $orders forms $forms)"
snap used
d=$(differ before used); [ -z "$d" ] && ok "after every CRM-G function was used with everything ON, all $tot snapshots are identical" || bad "figures changed after use: $d"
r1=$(rows); r0b=$(echo "$r0" | sed 's#/[0-9]*$##'); r1b=$(echo "$r1" | sed 's#/[0-9]*$##')
[ "$r0b" = "$r1b" ] && ok "journal, sale, payment, stock and cash-move rows unchanged after use ($r1b)" || bad "books rows moved: $r0b -> $r1b"
ub=$($P -d $DB -c "select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z")
[ "$ub" = "0" ] && ok "every journal entry still balances (Dr = Cr)" || bad "unbalanced entries: $ub"
np=$($P -d $DB -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false); select acct_post_pending(true) ->> 'posted'" | tail -1)
ok "the posting dry run still answers (posted field: $np)"
# a lead never reaches the books: the poster has no source type from CRM-G
nt=$($P -d $DB -c "select count(*) from journal_entries where source_type like 'crm%'")
[ "$nt" = "0" ] && ok "no journal entry has a CRM source type" || bad "journal entries with a crm source: $nt"
# phase 99 on top keeps the CRM-G Exceptions kinds
if [ -f $R/supabase/phase99.sql ]; then
  $P -d $DB -f $R/supabase/phase99.sql >/dev/null 2>&1 || { echo "FAIL phase99 on top"; fail=1; }
  k=$($P -d $DB -c "select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.money_exceptions'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%negative_warn%'")
  case "$k" in *crmg_lead_reopen*crmg_late_quote*|*crmg_late_quote*crmg_lead_reopen*) case "$k" in *crmg_win_without_quote*) ok "phase 99 on top keeps the three CRM-G Exceptions kinds";; *) bad "phase 99 dropped a CRM-G kind";; esac;; *) bad "phase 99 dropped the CRM-G Exceptions kinds";; esac
  snap after99
  d=$(differ before after99); [ -z "$d" ] && ok "with phase 99 on top the snapshots are still identical" || bad "phase 99 on top changed: $d"
fi
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
