#!/bin/bash
# CRM-F proof (owner rule 2: no accounting figure changes unless the owner switches voucher liability on; nothing switches on by itself):
#   1. A and B are twins built from the same base (a fresh build through phase 98) with tests/sql/p87_fixture.sql loaded (owner 987, everything posted).
#   2. A: snapshot "before", paste phases 316 to 319 twice, snapshot "after" -> every report equal (P&L, balance sheet, trial balance, cash flow, day book, journal lines, balance check, posting dry run ...).
#   3. A second wave of documents (tests/sql/p98_wave2.sql) plus customer sales with points ON and a discount, made by the SAME calls on both twins. Both are posted by the manual poster.
#      A (with CRM-F at defaults) must equal B (without): journal lines and every report, the sales rows, the points ledger.
#   4. The new settings sit at their defaults, and no journal entry has a crmf source on A.
# usage: BASE=crmf_base PORT=5574 bash tests/sql/crmf_before_after.sh      (local throwaway Postgres only)
PORT=${PORT:-5574}; BASE=${BASE:-crmf_base}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
OWN=00000000-0000-0000-0000-000000000987
fail=0
for db in cfba_a cfba_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in cfba_a cfba_b; do $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }; done
$P -d cfba_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
for pass in 1 2; do
  for n in 316 317 318 319; do $P -d cfba_a -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n paste $pass"; exit 1; }; done
done
$P -d cfba_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d cfba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d cfba_a -c "select count(*) from tt.snap where label='before'")
echo "PASS-OR-FAIL before/after: $tot snapshots compared, $n differ"
[ "$n" = "0" ] || { fail=1; $P -d cfba_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
d=$($P -d cfba_a -c "select (not rule_on('crm_referral_on') and not rule_on('crm_voucher_on') and not rule_on('crm_voucher_liability_on') and not rule_on('crm_hooks_on')
  and rule_num('crm_points_expiry_months') is null and rule_txt('crm_points_expiry_from') is null and rule_num('crm_burn_max_percent') is null and rule_num('crm_burn_max_points') is null and rule_num('crm_burn_step_points') is null
  and rule_num('crm_referral_reward_points') is null and rule_num('crm_voucher_max_percent') is null and rule_num('crm_voucher_max_amount') is null and rule_txt('crm_voucher_liability_from') is null
  and rule_num('crm_points_adjust_alert_over') is null and rule_num('crm_points_expiry_warn_days') is null)::text")
echo "defaults: $d (must be true)"; [ "$d" = "true" ] || fail=1
# wave 2 plus customer sales (points ON, a discount, a second customer) by the same calls on both twins
SALES="select set_config('request.jwt.claim.sub','$OWN',false);
select set_rule('loyalty_points_on','true'::jsonb);
select record_sale2(gen_random_uuid(),1,'[{\"amount\":1250}]',50,'[{\"mode\":\"cash\",\"amount\":1200}]','01711777001','test_ba_cust_one','retail',null,true) is not null;
select record_sale2(gen_random_uuid(),1,'[{\"amount\":800}]',0,'[{\"mode\":\"mobile\",\"amount\":800}]','01711777001','test_ba_cust_one','retail',null,true) is not null;
select record_sale2(gen_random_uuid(),2,'[{\"amount\":2100}]',100,'[{\"mode\":\"cash\",\"amount\":1000}]','01711777002','test_ba_cust_two','wholesale',null,true) is not null;"
for db in cfba_a cfba_b; do
  $P -d $db -f $T/p98_wave2.sql >/dev/null || { echo "FAIL wave2 $db"; fail=1; }
  $P -d $db -c "$SALES" >/dev/null || { echo "FAIL sales $db"; fail=1; }
  $P -d $db -c "select set_config('request.jwt.claim.sub','$OWN',false); select acct_post_pending(false)->>'posted'" >/dev/null || { echo "FAIL posting $db"; fail=1; }
done
$P -d cfba_a -v label=wave2 -f $T/p87_snap.sql >/dev/null; $P -d cfba_b -v label=wave2 -f $T/p87_snap.sql >/dev/null
cnt=0
for nm in $($P -d cfba_a -c "select name from tt.snap where label='wave2' order by name"); do
  a=$($P -d cfba_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d cfba_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  cnt=$((cnt+1))
  if [ "$a" = "$b" ]; then :; else echo "FAIL wave2 $nm differs between A (with CRM-F) and B (without)"; fail=1; fi
done
echo "wave 2: $cnt snapshots compared A vs B"
JL="select md5(coalesce(string_agg(e.source_type||'|'||e.entry_date||'|'||l.account_id||'|'||l.debit||'|'||l.credit, ';' order by e.source_type||'|'||e.entry_date||'|'||l.account_id||'|'||l.debit||'|'||l.credit), '')) from journal_entries e join journal_lines l on l.entry_id=e.id"
SL="select md5(coalesce(string_agg(location_id||'|'||receipt||'|'||subtotal||'|'||discount||'|'||total||'|'||paid||'|'||due_amount||'|'||pay_mode, ';' order by location_id, receipt), '')) from sales"
PL="select md5(coalesce(string_agg(c.mobile||'|'||l.delta||'|'||l.reason, ';' order by c.mobile, l.id), '')) from customer_points_ledger l join customers c on c.id=l.customer_id"
for q in "$JL" "$SL" "$PL"; do
  a=$($P -d cfba_a -c "$q"); b=$($P -d cfba_b -c "$q")
  if [ "$a" = "$b" ]; then echo "PASS twins equal: ${q:0:60}..."; else echo "FAIL twins differ: ${q:0:60}"; fail=1; fi
done
pts=$($P -d cfba_a -c "select count(*) from customer_points_ledger where reason='sale'")
echo "points rows on A: $pts (must be > 0 so the comparison means something)"; [ "$pts" -gt 0 ] || fail=1
cf=$($P -d cfba_a -c "select count(*) from journal_entries where source_type like 'crmf%'")
echo "journal entries with a crmf source on A: $cf (must be 0)"; [ "$cf" = "0" ] || fail=1
ub=$($P -d cfba_a -c "select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit)<>sum(credit)) z")
echo "unbalanced entries on A: $ub (must be 0)"; [ "$ub" = "0" ] || fail=1
bal=$($P -d cfba_a -c "select set_config('request.jwt.claim.sub','$OWN',false); select (_e_balance_check()->>'status')" | tail -1)
echo "balance check on A: $bal (must not be red)"; [ "$bal" != "red" ] || fail=1
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
exit $fail
