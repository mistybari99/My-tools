#!/bin/bash
# Phase 88 proof: nothing changes for an existing install until the owner turns a setting on. NO historic figure moves.
#   1. a fresh DB through phase 87, the phase 87 fixture and the phase 88 fixture (credit sale, collection, supplier with a typed opening), snapshot "before"
#      (P&L, balance sheet, trial balance, cash flow, day book, journal lines, balance check, posting dry run + customer dues, ledger, balances, supplier ledger, acct_reconcile)
#   2. paste phase88 -> snapshot "after_phase88" -> identical.   3. apply the four hooks (tests/sql/phase88_hooks.sql), every setting at its default -> "after_hooks" -> identical.
#   4. switch open_parties_link ON while no customer has an opening -> "link_on_empty" -> identical (the switch alone changes nothing).
#   5. a second wave of records on this DB and on a twin that never got phase 88 -> the reports agree.
# usage: bash tests/sql/phase88_before_after.sh      (local throwaway Postgres on PORT, default 5561; the base DB BASE must exist: a fresh build through phase 87)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; T="$HERE"
PORT=${PORT:-5561}; BASE=${BASE:-w1a_base}
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
for db in ba88_a ba88_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in ba88_a ba88_b; do
  $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture 87 $db"; exit 1; }
  $P -d $db -f $T/p88_fixture.sql >/dev/null || { echo "FAIL fixture 88 $db"; exit 1; }
done
snap() { $P -d ba88_a -v label=$1 -f $T/p88_snap.sql >/dev/null || { echo "FAIL snapshot $1"; exit 1; }; }
cmp_with() {   # $1 = label compared with "before"
  n=$($P -d ba88_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='$1' where b.label='before' and a.val is distinct from b.val")
  tot=$($P -d ba88_a -c "select count(*) from tt.snap where label='before'")
  echo "PASS-OR-FAIL $1: $tot snapshots compared with 'before', $n differ"
  [ "$n" = "0" ] || { fail=1; $P -d ba88_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='$1' where b.label='before' and a.val is distinct from b.val"; }
}
snap before
$P -d ba88_a -f $R/supabase/phase88.sql >/dev/null 2>&1 || { echo "FAIL phase88 paste"; exit 1; }
snap after_phase88; cmp_with after_phase88
$P -d ba88_a -f $T/phase88_hooks.sql >/dev/null 2>&1 || { echo "FAIL hooks"; exit 1; }
snap after_hooks; cmp_with after_hooks
$P -d ba88_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false); select set_rule('open_parties_link','true')" >/dev/null || { echo "FAIL switch"; exit 1; }
snap link_on_empty; cmp_with link_on_empty
$P -d ba88_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false); select set_rule('open_parties_link','false')" >/dev/null
np=$($P -d ba88_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
echo "posting run after phase 88 and the hooks posted: $np (must be 0)"; [ "$np" = "0" ] || fail=1
cat > /tmp/p88_wave2.sql <<'EOS'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false);
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by, customer_id)
  select 1, 988201, (now() at time zone 'Asia/Dhaka')::date, now(), '[]', 300, 0, 300, 'cash', 'done', '00000000-0000-0000-0000-000000000987', id from customers where mobile = '01800000988';
select collect_payment(gen_random_uuid(), 1, (select id from customers where mobile='01800000988'), '[{"mode":"cash","amount":100}]'::jsonb, 'w2') is not null;
insert into supplier_payments (supplier_id, location_id, mode, amount, paid_at, created_by) select id, 1, 'cash', 50, now(), '00000000-0000-0000-0000-000000000987' from suppliers where name='test_supplier_ba';
select acct_post_pending(false) ->> 'posted';
EOS
for db in ba88_a ba88_b; do $P -d $db -f /tmp/p88_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
$P -d ba88_a -v label=wave2 -f $T/p88_snap.sql >/dev/null; $P -d ba88_b -v label=wave2 -f $T/p88_snap.sql >/dev/null
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_all journal_lines p88_cust_bal p88_customer_dues p88_customer_ledger p88_sup_balance p88_acct_reconcile; do
  a=$($P -d ba88_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d ba88_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ]; then echo "PASS wave2 $nm: with phase 88 and the hooks = without"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
