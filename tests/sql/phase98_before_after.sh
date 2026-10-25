#!/bin/bash
# Phase 98 proof (owner rule 2: nothing changes a historic figure; nothing switches on by itself):
#   1. A and B are twins built from the same base (a fresh build through phase 87) with tests/sql/p87_fixture.sql loaded (owner 987, everything posted).
#   2. A: snapshot "before", paste phase98 twice, snapshot "after" -> every report equal (P&L, balance sheet, trial balance, cash flow, day book, journal lines, balance check, posting dry run).
#   3. A: with the scheduler switch still OFF a run posts nothing; a dry run lists the waiting documents.
#   4. Second wave of documents (tests/sql/p98_wave2.sql) on both. B posts with the manual poster acct_post_pending. A switches the scheduler ON, sets cap 2,
#      lets the NOTIFY BOT call _w1g_post_scheduled until nothing is left. The journal lines and every report must equal B (same engine, same lines).
#   5. A second session holds the posting lock: the scheduler answers "busy" and posts nothing, then posts after the lock is released.
# usage: bash tests/sql/phase98_before_after.sh      (local throwaway Postgres on PORT, default 5567; BASE must exist: a fresh build through phase 87)
PORT=${PORT:-5567}; BASE=${BASE:-w98base}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
OWN=00000000-0000-0000-0000-000000000987; BOT=00000000-0000-0000-0000-000000009899
fail=0
for db in ba98_a ba98_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in ba98_a ba98_b; do $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }; done
$P -d ba98_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
$P -d ba98_a -f $R/supabase/phase98.sql >/dev/null 2>&1 || { echo "FAIL phase98 paste 1"; exit 1; }
$P -d ba98_a -f $R/supabase/phase98.sql >/dev/null 2>&1 || { echo "FAIL phase98 paste 2"; exit 1; }
$P -d ba98_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d ba98_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d ba98_a -c "select count(*) from tt.snap where label='before'")
echo "PASS-OR-FAIL before/after: $tot snapshots compared, $n differ"
[ "$n" = "0" ] || { fail=1; $P -d ba98_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
# new rules sit at their defaults
d=$($P -d ba98_a -c "select (not rule_on('journal_sched_post_on') and rule_num('journal_sched_post_cap')=1500 and not rule_on('backup_encrypt_on') and rule_txt('switch_coupling_warning')='warn')::text")
echo "defaults: $d (must be true)"; [ "$d" = "true" ] || fail=1
# a bot that is an ops 'notify' account (never approved) on A
$P -d ba98_a -c "insert into auth.users (id,email,raw_user_meta_data) values ('$BOT','test_bot_ba98@s.app','{}') on conflict do nothing; insert into ops_accounts (user_id,purpose) values ('$BOT','notify') on conflict do nothing;" >/dev/null
SETB="select set_config('request.jwt.claim.sub','$BOT',false);"; SETO="select set_config('request.jwt.claim.sub','$OWN',false);"
# wave 2 on both twins
for db in ba98_a ba98_b; do $P -d $db -f $T/p98_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
# switch OFF: nothing posted
off=$($P -d ba98_a -c "$SETB select _w1g_post_scheduled(false)->>'skipped'" | tail -1)
je_a=$($P -d ba98_a -c "select count(*) from journal_entries"); je_b=$($P -d ba98_b -c "select count(*) from journal_entries")
echo "scheduler OFF: answer=$off, journal entries A=$je_a B=$je_b (must be switch_off and equal)"; { [ "$off" = "switch_off" ] && [ "$je_a" = "$je_b" ]; } || fail=1
dry=$($P -d ba98_a -c "$SETB select (_w1g_post_scheduled(true)->>'posted')::int" | tail -1)
drymanual=$($P -d ba98_b -c "$SETO select (acct_post_pending(true)->>'posted')::int" | tail -1)
echo "dry run lists $dry documents, the manual dry run lists $drymanual (must be equal and > 0)"; { [ "$dry" = "$drymanual" ] && [ "$dry" -gt 0 ]; } || fail=1
# lock held by another session -> busy
( $P -d ba98_a -c "begin; select pg_advisory_xact_lock(hashtextextended('acct_post',0)); select pg_sleep(3); commit;" >/dev/null ) &
sleep 1
$P -d ba98_a -c "$SETO select set_rule('journal_sched_post_on','true'); select set_rule('journal_sched_post_cap','2');" >/dev/null
busy=$($P -d ba98_a -c "$SETB select _w1g_post_scheduled(false)->>'skipped'" | tail -1)
wait
echo "another session posting: answer=$busy (must be busy)"; [ "$busy" = "busy" ] || fail=1
# B: manual poster
$P -d ba98_b -c "$SETO select acct_post_pending(false)->>'posted'" >/dev/null
# A: scheduler with cap 2 until nothing is left
runs=0; while :; do
  r=$($P -d ba98_a -c "$SETB select (_w1g_post_scheduled(false)->>'posted')::int + (_w1g_post_scheduled(true)->>'posted')::int" | tail -1)
  runs=$((runs+1)); [ "$r" = "0" ] && break; [ $runs -gt 40 ] && { echo "FAIL too many runs"; fail=1; break; }
done
echo "scheduler needed $runs call(s) at cap 2"
$P -d ba98_a -v label=wave2 -f $T/p87_snap.sql >/dev/null; $P -d ba98_b -v label=wave2 -f $T/p87_snap.sql >/dev/null
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_totals_p1 day_book_all journal_lines; do
  a=$($P -d ba98_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d ba98_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ]; then echo "PASS wave2 $nm: scheduled posting = manual posting"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
ub=$($P -d ba98_a -c "select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit)<>sum(credit)) z")
echo "unbalanced entries on A: $ub (must be 0)"; [ "$ub" = "0" ] || fail=1
rv=$($P -d ba98_a -c "select count(*) from journal_entries r join journal_entries o on o.id=r.reverses_id where o.source_type='sale'")
echo "sale reversals on A: $rv (the voided sale was reversed, must be 1)"; [ "$rv" = "1" ] || fail=1
bal=$($P -d ba98_a -c "$SETO select (_e_balance_check()->>'status')" | tail -1)
echo "balance check on A: $bal (must not be red)"; [ "$bal" != "red" ] || fail=1
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
