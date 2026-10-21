#!/bin/bash
# W1-D proof (phases 92 and 93): NOTHING changes for an existing install until the owner switches a setting on, and each setting changes only what it should.
#   1. database A and a twin B from BASE (a fresh build through phase 87). Both get the fixture; A takes a snapshot "before".
#   2. A gets phases 92 and 93 and the integrator hook; snapshot "after": every snapshot must be identical (the old figures are the old figures).
#   3. a second wave of ordinary records on A and on the twin B (which never got 92/93): the reports must agree.
#   4. each setting is switched on in A: the figures it is meant to change differ, the figures it must not touch are identical, and switching it off again gives back the "before" figures.
# usage: bash tests/sql/w1d_before_after.sh     (local throwaway Postgres on PORT, default 5564; BASE must exist: a fresh build through phase 87)
PORT=${PORT:-5564}; BASE=${BASE:-w1d_base}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }
for db in w1d_ba_a w1d_ba_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in w1d_ba_a w1d_ba_b; do
  $P -d $db -f $T/w1d_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }
  $P -d $db -f $T/w1d_snap_setup.sql >/dev/null || { echo "FAIL setup $db"; exit 1; }
done
snap() { $P -d w1d_ba_a -v label=$1 -f $T/w1d_snap.sql >/dev/null || { echo "FAIL snapshot $1"; exit 1; }; }
# names whose value differs between two labels
differ() { $P -d w1d_ba_a -c "select a.name from tt.snap a join tt.snap b on a.name = b.name and b.label = '$2' where a.label = '$1' and a.val is distinct from b.val order by 1" | tr '\n' ' '; }
# expect(label_a, label_b, must_differ..., --same, must_same...)
has() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }
expect() {
  local a=$1 b=$2 d; shift 2; d=$(differ $a $b); local mode=differ n
  for n in "$@"; do
    if [ "$n" = "--same" ]; then mode=same; continue; fi
    if [ $mode = differ ]; then has "$d" $n && ok "$a vs $b: $n changes" || bad "$a vs $b: $n should change but did not"; else has "$d" $n && bad "$a vs $b: $n must NOT change but did" || ok "$a vs $b: $n unchanged"; fi
  done
}

snap before
tot=$($P -d w1d_ba_a -c "select count(*) from tt.snap where label='before'"); echo "snapshots taken: $tot"
$P -d w1d_ba_a -f $R/supabase/phase92.sql >/dev/null 2>&1 || { echo "FAIL phase92 paste"; exit 1; }
$P -d w1d_ba_a -f $R/supabase/phase93.sql >/dev/null 2>&1 || { echo "FAIL phase93 paste"; exit 1; }
$P -d w1d_ba_a -c "select public._w1d_hooks_apply()" >/dev/null 2>&1 || { echo "FAIL hooks"; exit 1; }
$P -d w1d_ba_a -f $R/supabase/phase92.sql >/dev/null 2>&1 && $P -d w1d_ba_a -f $R/supabase/phase93.sql >/dev/null 2>&1 && ok "phases 92 and 93 pasted twice without error" || bad "paste twice"
snap after
n=$(differ before after | wc -w)
[ "$n" = "0" ] && ok "with every setting at its default $tot snapshots are identical before and after phases 92, 93 and the hook" || { bad "default figures changed: $(differ before after)"; }
np=$($P -d w1d_ba_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
[ "$np" = "0" ] && ok "the poster has nothing new to post after the paste (posted $np)" || bad "the poster posted $np"

# 3. second wave on both twins
cat > /tmp/w1d_wave2_$$.sql <<'EOS'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false);
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 77, 'cash', false, null, gen_random_uuid()) is not null;
select cash_move_add(2,'owner_draw',400,(now() at time zone 'Asia/Dhaka')::date,'cash',null,'w2',null,gen_random_uuid(),false) is not null;
select stock_wastage((select id from items where code='W1D-WS'),1,2,'spoiled','w2') is not null;
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',(select id from items where code='W1D-FG'))::jsonb,0,'[{"mode":"cash","amount":100}]',null,null,'retail',null,false) is not null;
select acct_post_pending(false) ->> 'posted';
EOS
for db in w1d_ba_a w1d_ba_b; do $P -d $db -f /tmp/w1d_wave2_$$.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
rm -f /tmp/w1d_wave2_$$.sql
$P -d w1d_ba_a -v label=wave2 -f $T/w1d_snap.sql >/dev/null; $P -d w1d_ba_b -v label=wave2 -f $T/w1d_snap.sql >/dev/null
for nm in p27_pl l1_pnl l3_shop_pnl l4_owner_sheet l5_breakeven t4_staff_cost e2_expense_trend e3_weak_control expense_by_head partner_calculate partner_month_split brand_pnl income_statement balance_sheet trial_balance cash_flow day_book_all day_book_totals journal_lines; do
  a=$($P -d w1d_ba_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d w1d_ba_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  [ "$a" = "$b" ] && ok "wave2 $nm: with phases 92 + 93 = without" || bad "wave2 $nm differs"
done
snap before2   # the state to compare the switches against (after the second wave)

# 4. each setting on, then off again
setr() { $P -d w1d_ba_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false); select set_rule('$1', '$2'::jsonb)" >/dev/null || { echo "FAIL set_rule $1"; fail=1; }; }
setr profit_one_number_on true; snap s_master
expect before2 s_master p27_pl l1_pnl l3_shop_pnl partner_calculate partner_month_split --same income_statement balance_sheet trial_balance cash_flow day_book_all day_book_totals journal_lines post_dry brand_pnl expense_by_head e3_weak_control e2_expense_trend
setr profit_loss_wastage false; setr profit_loss_count false; setr profit_loss_transit false; setr profit_loss_cashshort false; setr profit_loss_billopex false; setr profit_overhead_once false; snap s_causes_off
expect before2 s_causes_off --same p27_pl l1_pnl l3_shop_pnl partner_calculate   # (the partner preview still moves from the journal figure to the management figure: that is the master switch itself)
for k in profit_loss_wastage profit_loss_count profit_loss_transit profit_loss_cashshort profit_loss_billopex profit_overhead_once; do setr $k true; done
setr profit_one_number_on false; snap back_master
expect before2 back_master --same p27_pl l1_pnl l3_shop_pnl partner_calculate partner_month_split income_statement journal_lines day_book_all brand_pnl expense_by_head
setr profit_source '"ledger"'; snap s_ledger_master_off
expect before2 s_ledger_master_off --same partner_calculate partner_month_split p27_pl
setr profit_source '"management"'

setr report_expense_parity_on true; snap s_parity
expect before2 s_parity expense_by_head e3_weak_control --same p27_pl l1_pnl l3_shop_pnl income_statement journal_lines day_book_all brand_pnl e2_expense_trend
setr report_expense_parity_on false; snap back_parity
expect before2 back_parity --same expense_by_head e3_weak_control p27_pl

setr report_salary_source '"app_first"'; snap s_salary
expect before2 s_salary p27_pl l1_pnl l3_shop_pnl t4_staff_cost --same income_statement balance_sheet journal_lines day_book_all expense_by_head brand_pnl
setr report_salary_source '"legacy"'; snap back_salary
expect before2 back_salary --same p27_pl l1_pnl l3_shop_pnl t4_staff_cost

setr expense_count_on '"approved"'; snap s_exp_approved
expect before2 s_exp_approved p27_pl l1_pnl l3_shop_pnl e2_expense_trend expense_by_head day_book_all day_book_totals --same journal_lines income_statement post_dry brand_pnl
setr expense_count_on '"submitted"'; snap s_exp_submitted
expect before2 s_exp_submitted post_dry --same p27_pl l1_pnl journal_lines day_book_all income_statement
setr expense_count_on '"as_today"'; snap back_exp
expect before2 back_exp --same p27_pl l1_pnl e2_expense_trend expense_by_head day_book_all day_book_totals journal_lines post_dry

$P -d w1d_ba_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000092',false); select brand_map_set(1,'test_brand_new','test_bn','test_en')" >/dev/null || { echo "FAIL brand_map_set"; fail=1; }
snap s_brand_changed
expect before2 s_brand_changed brand_pnl --same p27_pl income_statement journal_lines day_book_all
setr brand_map_dated_on true; snap s_brand_dated
expect s_brand_changed s_brand_dated brand_pnl --same p27_pl income_statement journal_lines day_book_all expense_by_head

[ $fail = 0 ] && echo "RESULT before/after: all as expected" || echo "RESULT before/after: DIFFERENCES"
exit $fail
