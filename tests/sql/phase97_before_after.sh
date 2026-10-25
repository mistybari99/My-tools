#!/bin/bash
# Phases 96 + 97 proof (W1-F): nothing an owner already reads changes when the two phases are pasted and every new setting is at its default.
#   1. fresh DB through phase 87 (BASE), load the phase 87 fixture + the W1-F fixture (no money account, an unposted voucher with the head utilities, an unposted quick expense with the head marketing,
#      cash and mobile collections, a POS split sale), snapshot "before" (P&L, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, balance check core, posting dry run,
#      the account every unposted document would post to, the payments, the dues)
#   2. paste phase 96 and phase 97 (twice), snapshot "after" and compare: no difference
#   3. a second wave of ordinary documents on that DB and on a twin DB that never got the two phases: the reports must agree
# usage: PORT=5566 BASE=base87 bash tests/sql/phase97_before_after.sh      (local throwaway Postgres; BASE = a fresh build through phase 87)
PORT=${PORT:-5566}; BASE=${BASE:-base87}
T=$(cd "$(dirname "$0")" && pwd); R=$(cd "$T/../.." && pwd)
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0
for db in w1fba_a w1fba_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in w1fba_a w1fba_b; do
  $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }
  $P -d $db -f $T/w1f_fixture.sql >/dev/null || { echo "FAIL w1f fixture $db"; exit 1; }
done
$P -d w1fba_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
$P -d w1fba_a -v label=before -f $T/w1f_snap.sql >/dev/null || { echo "FAIL w1f snapshot before"; exit 1; }
for ph in phase96 phase97 phase96 phase97; do $P -d w1fba_a -f $R/supabase/$ph.sql >/dev/null 2>/tmp/w1f_ba_$ph.err || { echo "FAIL paste $ph"; head -3 /tmp/w1f_ba_$ph.err; exit 1; }; done
$P -d w1fba_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
$P -d w1fba_a -v label=after -f $T/w1f_snap.sql >/dev/null || { echo "FAIL w1f snapshot after"; exit 1; }
n=$($P -d w1fba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d w1fba_a -c "select count(*) from tt.snap where label='before'")
echo "PASS-OR-FAIL before/after: $tot snapshots compared, $n differ"
if [ "$n" != "0" ]; then fail=1; $P -d w1fba_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; fi
# the seed is visible but inert: new accounts exist with no movement, the three heads are still retired
$P -d w1fba_a -c "select 'seeded accounts: ' || count(*) from w1f_seed_state where status in ('created','mapped_existing')"
$P -d w1fba_a -c "select 'blocked seeds (kept off because unposted documents exist): ' || coalesce(string_agg(key || '=' || status, ', '), '-') from w1f_seed_state where status = 'history_exists'"
act=$($P -d w1fba_a -c "select count(*) from option_lists where list_code='expense_heads' and value_code in ('rent','utilities','marketing') and active")
echo "seeded heads switched on by the paste: $act (must be 0)"; [ "$act" = "0" ] || fail=1
np=$($P -d w1fba_a -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false); select acct_post_pending(false) ->> 'posted'" | tail -1)
echo "posting run after the paste posted: $np document(s) of the fixture that were still unposted (nothing comes from phases 96 and 97)"
# second wave of ordinary documents on both twins
cat > /tmp/w1f_ba_wave2.sql <<'EOS'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false);
select quick_expense_add(1, (now() at time zone 'Asia/Dhaka')::date, 'transport', 'test_rider', 77, 'cash', false, null, gen_random_uuid()) is not null;
select cash_move_add(1,'owner_topup',900,(now() at time zone 'Asia/Dhaka')::date,'mobile',null,'w2',null,gen_random_uuid(),false) is not null;
select collect_payment(gen_random_uuid(), 1, (select id from customers where mobile='01800000988'), '[{"mode":"cash","amount":120},{"mode":"card","amount":80}]'::jsonb, 'w2') is not null;
select record_sale2(gen_random_uuid(),2,'[{"amount":260}]'::jsonb,0,'[{"mode":"cash","amount":100},{"mode":"mobile","amount":60,"wallet":"nagad"},{"mode":"card","amount":100}]'::jsonb,null,null,'retail',null,true) is not null;
select save_entry(null,'10-2',1,(now() at time zone 'Asia/Dhaka')::date,'{"lines":[{"head":"transport","amount":"90"}]}'::jsonb,'[]') is not null;
select acct_post_pending(false) ->> 'posted';
EOS
for db in w1fba_a w1fba_b; do $P -d $db -f /tmp/w1f_ba_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
$P -d w1fba_a -v label=wave2 -f $T/p87_snap.sql >/dev/null; $P -d w1fba_b -v label=wave2 -f $T/p87_snap.sql >/dev/null
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_totals_p1 day_book_all journal_lines; do
  a=$($P -d w1fba_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d w1fba_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ]; then echo "PASS wave2 $nm: with phases 96+97 = without"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
