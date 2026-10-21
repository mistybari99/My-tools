#!/bin/bash
# Phase 87 proof: nothing changes for an existing install until the owner configures money accounts.
#   1. build a fresh DB through phase 86, load the fixture (records of every kind, no money account), snapshot "before"
#   2. paste phase87 on it, snapshot "after" (P&L, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, balance check core, posting dry run) and compare
#   3. add a second wave of untagged payments on that DB and on a twin DB that never got phase 87: the reports must agree
# usage: bash tests/sql/phase87_before_after.sh      (local throwaway Postgres on PORT, default 5553; the base DB BASE must exist: a fresh build through phase 86)
PORT=${PORT:-5553}; BASE=${BASE:-base86}; R=/home/user/My-tools; T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
for db in ba_a ba_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
# A gets the fixture, snapshot, phase 87, snapshot. B is the twin that never gets phase 87.
for db in ba_a ba_b; do $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }; done
$P -d ba_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
$P -d ba_a -f $R/supabase/phase87.sql >/dev/null 2>&1 || { echo "FAIL phase87 paste"; exit 1; }
$P -d ba_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d ba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d ba_a -c "select count(*) from tt.snap where label='before'")
echo "PASS-OR-FAIL before/after: $tot snapshots compared, $n differ"
[ "$n" = "0" ] || { fail=1; $P -d ba_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
# the poster has nothing new to post after the paste
np=$($P -d ba_a -c "select acct_post_pending(false) ->> 'posted'" 2>/dev/null)
$P -d ba_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false)" >/dev/null
np=$($P -d ba_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
echo "posting run after the paste posted: $np (must be 0)"; [ "$np" = "0" ] || fail=1
# second wave on both twins
cat > /tmp/p87_wave2.sql <<'EOS'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false);
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 77, 'cash', false, null, gen_random_uuid()) is not null;
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 33, 'bank', false, null, gen_random_uuid()) is not null;
select cash_move_add(1,'owner_topup',900,(now() at time zone 'Asia/Dhaka')::date,'mobile',null,'w2',null,gen_random_uuid(),false) is not null;
select cash_move_add(2,'owner_draw',400,(now() at time zone 'Asia/Dhaka')::date,'cash',null,'w2',null,gen_random_uuid(),false) is not null;
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by) select id, 1, 'mobile', 'bkash', 66, now(), '00000000-0000-0000-0000-000000000987' from suppliers where name='test_supplier_ba';
insert into supplier_payments (supplier_id, location_id, mode, amount, paid_at, created_by) select id, 1, 'cash', 44, now(), '00000000-0000-0000-0000-000000000987' from suppliers where name='test_supplier_ba';
select staff_advance_add((select id from employees where employee_no='TESTBA_A'), (now() at time zone 'Asia/Dhaka')::date, 1000, 500, 'bank', (now() at time zone 'Asia/Dhaka')::date + 30, 'w2', gen_random_uuid()) is not null;
select acct_post_pending(false) ->> 'posted';
EOS
for db in ba_a ba_b; do $P -d $db -f /tmp/p87_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
$P -d ba_a -v label=wave2 -f $T/p87_snap.sql >/dev/null; $P -d ba_b -v label=wave2 -f $T/p87_snap.sql >/dev/null
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_totals_p1 day_book_all journal_lines; do
  a=$($P -d ba_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d ba_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ]; then echo "PASS wave2 $nm: with phase 87 = without"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
