#!/bin/bash
# Phases 94 and 95 proof (package W1-E): nothing changes for an existing install until the owner changes a setting, and a setting never rewrites a historic figure.
#   1. copy a fresh build through phase 87 (BASE), load the phase 87 fixture (records of every kind), snapshot "before"
#   2. paste phases 94 and 95, snapshot "after" (P&L, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, balance check core, posting dry run): must be identical
#   3. a second wave of records at the defaults on this DB and on a twin that never got phases 94/95: the reports must agree
#   4. switch EVERY new setting on and snapshot again: the figures of the records already in the books must not move
# usage: bash tests/sql/phase94_95_before_after.sh      (local throwaway Postgres on PORT, default 5565; BASE must exist: a fresh build through phase 87)
PORT=${PORT:-5565}; BASE=${BASE:-base87}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
OWN=00000000-0000-0000-0000-000000000987
fail=0
TMPD=$(mktemp -d)
for db in w1e_ba_a w1e_ba_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in w1e_ba_a w1e_ba_b; do $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }; done
$P -d w1e_ba_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
$P -d w1e_ba_a -f $R/supabase/phase94.sql >/dev/null 2>&1 || { echo "FAIL phase94 paste"; exit 1; }
$P -d w1e_ba_a -f $R/supabase/phase95.sql >/dev/null 2>&1 || { echo "FAIL phase95 paste"; exit 1; }
$P -d w1e_ba_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d w1e_ba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d w1e_ba_a -c "select count(*) from tt.snap where label='before'")
echo "before/after (paste of 94 + 95): $tot snapshots compared, $n differ"
[ "$n" = "0" ] || { fail=1; $P -d w1e_ba_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
np=$($P -d w1e_ba_a -c "select set_config('request.jwt.claim.sub','$OWN',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
echo "posting run after the paste posted: $np (must be 0)"; [ "$np" = "0" ] || fail=1
# the new settings all sit at their safe defaults
d=$($P -d w1e_ba_a -c "select count(*) from rules where key in ('owner_money_entry_mode','bank_slip_required','bank_move_large_over','bank_move_backdate_days','supplier_pay_dup_mode','supplier_pay_dup_hours','supplier_pay_over','supplier_dup_mode','employee_pay_dup_mode','employee_pay_change_flag','journal_loc_check','mapping_type_guard','journal_attach_over','journal_control_acct_mode','journal_control_prefixes') and value is null")
echo "new settings left at their defaults: $d of 15 (must be 15)"; [ "$d" = "15" ] || fail=1
# wave 2 at the defaults, on both twins; a non-owner also records owner money (today it is allowed) and a bank deposit without a slip
cat > $TMPD/ba_wave2.sql <<EOS
select set_config('request.jwt.claim.sub','$OWN',false);
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 77, 'cash', false, null, gen_random_uuid()) is not null;
select cash_move_add(1,'owner_topup',900,(now() at time zone 'Asia/Dhaka')::date,'mobile',null,'w2',null,gen_random_uuid(),false) is not null;
select cash_move_add(2,'owner_draw',400,(now() at time zone 'Asia/Dhaka')::date,'cash',null,'w2',null,gen_random_uuid(),false) is not null;
select cash_move_add(1,'bank_deposit',650,(now() at time zone 'Asia/Dhaka')::date - 20,null,null,null,null,gen_random_uuid(),false) is not null;
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by) select id, 1, 'mobile', 'bkash', 66, now(), '$OWN' from suppliers where name='test_supplier_ba';
insert into suppliers (name, mobile) values ('test_supplier_ba', '01800000987');
insert into employees (employee_no, full_name_bn, status, primary_location_id, bank_account) values ('TESTBA_X','test_emp_x','active',1,'1111-2222'), ('TESTBA_Y','test_emp_y','active',1,'11112222');
select acct_journal_post((now() at time zone 'Asia/Dhaka')::date, null, 'test w2 journal', '[{"code":"1110","debit":5000000,"location_id":2},{"code":"4900","credit":5000000}]'::jsonb) is not null;
select acct_mapping_set('exp_transport', (select id from coa_accounts where code='5900')) is not null;
select acct_mapping_set('exp_transport', (select id from coa_accounts where code='5700')) is not null;
select acct_post_pending(false) ->> 'posted';
EOS
for db in w1e_ba_a w1e_ba_b; do $P -d $db -f $TMPD/ba_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
$P -d w1e_ba_a -v label=wave2 -f $T/p87_snap.sql >/dev/null; $P -d w1e_ba_b -v label=wave2 -f $T/p87_snap.sql >/dev/null
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_totals_p1 day_book_all journal_lines; do
  a=$($P -d w1e_ba_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d w1e_ba_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ]; then echo "PASS wave2 $nm: with phases 94/95 = without"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
# every new setting ON: the figures already in the books stay as they were
cat > $TMPD/ba_on.sql <<EOS
select set_config('request.jwt.claim.sub','$OWN',false);
select set_rule('owner_money_entry_mode','"approval"'), set_rule('bank_slip_required','true'), set_rule('bank_move_large_over','100'), set_rule('bank_move_backdate_days','1'),
  set_rule('supplier_pay_dup_mode','"block"'), set_rule('supplier_pay_over','1'), set_rule('supplier_dup_mode','"block"'), set_rule('employee_pay_dup_mode','"block"'), set_rule('employee_pay_change_flag','true'),
  set_rule('journal_loc_check','true'), set_rule('mapping_type_guard','true'), set_rule('journal_attach_over','1'), set_rule('journal_control_acct_mode','"request"');
EOS
$P -d w1e_ba_a -f $TMPD/ba_on.sql >/dev/null || { echo "FAIL switching the settings on"; fail=1; }
$P -d w1e_ba_a -v label=on -f $T/p87_snap.sql >/dev/null
m=$($P -d w1e_ba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='on' where b.label='wave2' and a.val is distinct from b.val")
echo "all new settings ON: snapshots that moved against the same books: $m (must be 0)"; [ "$m" = "0" ] || { fail=1; $P -d w1e_ba_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='on' where b.label='wave2' and a.val is distinct from b.val"; }
ub=$($P -d w1e_ba_a -c "select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z")
echo "unbalanced journal entries: $ub (must be 0)"; [ "$ub" = "0" ] || fail=1
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
