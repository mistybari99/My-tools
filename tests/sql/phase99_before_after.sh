#!/bin/bash
# Phase 99 proof (Wave 1 integration): with EVERY new setting at its default, a database that got phases 88 to 99 reports exactly what a database built only through phase 87 reports.
#   1. a base DB built through phase 87 (BASE), loaded with tests/sql/w1d_fixture.sql + w1d_snap_setup.sql + p99_fixture_extra.sql (stock, production, wastage, count, transit loss, cash short, supplier bill,
#      vouchers, quick expenses, payroll, partner agreement, credit sale and collection, void, return, owner money, bank moves, supplier payment, advance): snapshot "before"
#      (P&L, L1 L3 L4 L5 T4 E2 E3, expense report, partner calculation, brand P&L, income statement, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, posting dry run,
#       stock levels, stock valuation, stock movements, customer dues / ledger / balance, supplier balance, returns, payments, cash moves, acct_reconcile)
#   2. paste phases 88 to 99 in order -> snapshot "after" -> identical;  paste all twelve again -> snapshot "after2" -> identical;  the poster has nothing new to post.
#   3. a second wave of records through every hooked function (sale, late sale, credit sale, collection, return, void, owner money, bank deposit, quick expense, back-dated purchase, production, supplier payment,
#      employee exit, manual journal) on this DB and on a twin that never got phases 88 to 99 -> every report agrees.
# usage: bash tests/sql/phase99_before_after.sh      (local throwaway Postgres on PORT, default 5570; BASE = a fresh build through phase 87)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; T="$HERE"
PORT=${PORT:-5570}; BASE=${BASE:-base87}
PHASES=${PHASES:-88 89 90 91 92 93 94 95 96 97 98 99}   # W1-FIX: tests/sql/w1fix_before_after.sh runs this very script with 140 141 142 143 added
DBP=${DBP:-ba99}
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
for db in ${DBP}_a ${DBP}_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in ${DBP}_a ${DBP}_b; do
  for f in w1d_fixture w1d_snap_setup p99_fixture_extra; do $P -d $db -f $T/$f.sql >/dev/null 2>&1 || { echo "FAIL fixture $f on $db"; exit 1; }; done
done
snap() { $P -d ${DBP}_a -v label=$1 -f $T/w1d_snap.sql >/dev/null 2>&1 && $P -d ${DBP}_a -v label=$1 -f $T/p99_snap_extra.sql >/dev/null 2>&1 || { echo "FAIL snapshot $1"; exit 1; }; }
differ() { $P -d ${DBP}_a -c "select a.name from tt.snap a join tt.snap b on a.name = b.name and b.label = '$2' where a.label = '$1' and a.val is distinct from b.val order by 1" | tr '\n' ' '; }
snap before
tot=$($P -d ${DBP}_a -c "select count(*) from tt.snap where label='before'"); echo "snapshots taken: $tot"
for n in $PHASES; do $P -d ${DBP}_a -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n paste"; exit 1; }; done
snap after
d=$(differ before after); [ -z "$d" ] && ok "with every setting at its default $tot snapshots are identical before and after phases $PHASES" || bad "default figures changed: $d"
for n in $PHASES; do $P -d ${DBP}_a -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n second paste"; fail=1; }; done
snap after2
d=$(differ before after2); [ -z "$d" ] && ok "phases $PHASES pasted a second time: still identical" || bad "second paste changed: $d"
np=$($P -d ${DBP}_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
[ "$np" = "0" ] && ok "the poster has nothing new to post after the pastes (posted $np)" || bad "the poster posted $np"
hk=$($P -d ${DBP}_a -c "select count(*) from jsonb_array_elements(public._i1_hooks_state()) x where (x->>'present')::boolean")
[ "$hk" = "37" ] && ok "all 37 hooks are installed in the shared functions while nothing changed" || bad "hooks installed: $hk"

cat > /tmp/p99_wave2_$$.sql <<'EOS'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false);
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false) is not null;
-- an 80 hour old offline sale: redated to now, exactly as before (late_sale_policy = redate)
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[{"mode":"mobile","amount":100,"wallet":"bkash"}]',null,null,'retail',null,false, now() - interval '80 hours', null, null) is not null;
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[]'::jsonb,'01800000998','test_customer_p99b','retail',null,false) is not null;
select collect_payment(gen_random_uuid(), 1, (select id from customers where mobile='01800000998'), '[{"mode":"mobile","amount":40,"wallet":"nagad","ref":"TX-W2"}]'::jsonb, 'w2') is not null;
select sale_return(gen_random_uuid(), (select id from sales where total=200 and pay_mode='mobile' order by sold_at desc limit 1), format('[{"item_id":"%s","qty":1}]',(select id from items where code='W1D-FG'))::jsonb, 'damaged', null, 'cash', null, null) is not null;
select void_sale((select id from sales where total=100 and pay_mode='cash' order by sold_at desc limit 1), 'test void w2') is not null;
select cash_move_add(2,'owner_draw',400,(now() at time zone 'Asia/Dhaka')::date,'cash',null,'w2',null,gen_random_uuid(),false) is not null;
select cash_move_add(1,'bank_deposit',700,(now() at time zone 'Asia/Dhaka')::date - 400,null,null,'w2',null,gen_random_uuid(),false) is not null;
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date - 5, 'transport', 'test_rider', 77, 'cash', false, null, gen_random_uuid()) is not null;
select save_purchase(gen_random_uuid(), null, (select id from suppliers where name='test_supplier_w1d'), 1, 'W2-B1', (now() at time zone 'Asia/Dhaka')::date - 40, format('[{"item_id":"%s","qty":3,"unit_cost":21}]',(select id from items where code='W1D-RM'))::jsonb, 0) is not null;
select pay_supplier((select id from suppliers where name='test_supplier_w1d'), 1, '[{"mode":"cash","amount":60}]'::jsonb, gen_random_uuid(), 'w2') is not null;
select pay_supplier((select id from suppliers where name='test_supplier_w1d'), 1, '[{"mode":"cash","amount":60}]'::jsonb, gen_random_uuid(), 'w2 repeat') is not null;
select stock_wastage((select id from items where code='W1D-WS'),1,2,'spoiled','w2') is not null;
select employee_status_set((select id from employees where employee_no='TESTBA_W'), 'on_leave', (now() at time zone 'Asia/Dhaka')::date, 'w2') is not null;
select acct_journal_post((now() at time zone 'Asia/Dhaka')::date, 1, 'test w2 manual', '[{"code":"1110","debit":250},{"code":"3100","credit":250}]'::jsonb) is not null;
select acct_post_pending(false) ->> 'posted';
EOS
for db in ${DBP}_a ${DBP}_b; do $P -d $db -f /tmp/p99_wave2_$$.sql >/dev/null 2>/tmp/p99_w2_err_$db.txt || { echo "FAIL wave2 $db"; head -3 /tmp/p99_w2_err_$db.txt; fail=1; }; done
rm -f /tmp/p99_wave2_$$.sql
for db in ${DBP}_a ${DBP}_b; do $P -d $db -v label=wave2 -f $T/w1d_snap.sql >/dev/null 2>&1; $P -d $db -v label=wave2 -f $T/p99_snap_extra.sql >/dev/null 2>&1; done
names=$($P -d ${DBP}_a -c "select name from tt.snap where label='wave2' order by 1")
cnt=0
for nm in $names; do
  a=$($P -d ${DBP}_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d ${DBP}_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  cnt=$((cnt+1)); [ "$a" = "$b" ] && ok "wave2 $nm: with phases $PHASES = without" || bad "wave2 $nm differs"
done
echo "wave2 reports compared: $cnt"
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
