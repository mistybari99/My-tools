#!/bin/bash
# CRM-A proof (owner rule 2: accounting figures never change; rule 1: nothing starts by itself):
#   1. A is built from the BASE template (a fresh build through phase 98, or 99) with tests/sql/p87_fixture.sql (everything posted) and tests/sql/crm_a_fixture_core.sql
#      (customers with sales, dues, a return, points, a gift, orders, a message, an enquiry).
#   2. "before" snapshot: accounting reports (p87_snap) + every existing customer function and customer report + a hash of every shared function.
#   3. Paste phases 300, 301, 302 twice. "after" snapshot at the DEFAULT settings: every snapshot equal (including the function hashes: no shared function changed).
#   4. Switch ON crm_on, crm_second_phone_on and crm_mask_phone, write extras (phones, delivery points, dates, tags, notes, language, type, credit days), read the 360 view.
#      Accounting snapshots and the customer money figures are STILL equal; the journal has not gained a line; the existing customer functions still return the same.
# usage: bash tests/sql/crm_a_before_after.sh      (local throwaway Postgres on PORT, default 5571; BASE must exist: a fresh build through phase 98 or 99)
PORT=${PORT:-5571}; BASE=${BASE:-crm_base}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
OWN=00000000-0000-0000-0000-000000030201
fail=0
db=ba_crma
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE
$P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL p87 fixture"; exit 1; }
$P -d $db -f $T/crm_a_fixture_core.sql >/dev/null || { echo "FAIL crm fixture"; exit 1; }
$P -d $db -v label=before -f $T/crm_a_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
for ph in phase300 phase301 phase302; do for i in 1 2; do $P -d $db -f $R/supabase/$ph.sql >/dev/null 2>&1 || { echo "FAIL $ph paste $i"; exit 1; }; done; done
$P -d $db -v label=after -f $T/crm_a_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d $db -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d $db -c "select count(*) from tt.snap where label='before'")
echo "defaults: $tot snapshots compared before/after the three CRM-A phases, $n differ (must be 0)"
[ "$n" = "0" ] || { fail=1; $P -d $db -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
d=$($P -d $db -c "select (not rule_on('crm_on') and not rule_on('crm_second_phone_on') and not rule_on('crm_mask_phone'))::text")
echo "settings at their defaults: $d (must be true)"; [ "$d" = "true" ] || fail=1
# 4. switch everything ON and write profile data
SETO="select set_config('request.jwt.claim.sub','$OWN',false);"
$P -d $db -c "$SETO select set_rule('crm_on','true'); select set_rule('crm_second_phone_on','true'); select set_rule('crm_mask_phone','true');" >/dev/null
$P -d $db -c "$SETO
  select crma_customer_extras_save(id, '{\"language\":\"bn\",\"type_code\":\"party\",\"credit_days\":30,\"preferred_location_id\":1}') from customers where mobile='01711032001';
  select crma_phone_add(id, '01711032077', 'work', true) from customers where mobile='01711032001';
  select crma_address_save(id, '{\"address\":\"test_addr_x\",\"is_default\":true}') from customers where mobile='01711032001';
  select crma_date_save(id, '{\"kind\":\"birthday\",\"person_label\":\"Child 1\",\"month\":5,\"day\":6,\"year\":2015}') from customers where mobile='01711032001';
  select crma_tag_save(null, 'test_tag_ba', 'Test') ;
  select crma_tag_set(c.id, t.id) from customers c, crm_tags t where c.mobile='01711032001' and t.code='test_tag_ba';
  select crma_note_add(id, 'test_note_ba') from customers where mobile='01711032001';
  select crma_customer_360(id) from customers where mobile='01711032001';
  select crma_timeline(id) from customers where mobile='01711032001';
  select count(*) from crma_customer_directory();" >/dev/null || { echo "FAIL CRM writes/reads"; fail=1; }
$P -d $db -v label=after_on -f $T/crm_a_snap.sql >/dev/null || { echo "FAIL snapshot after_on"; fail=1; }
n2=$($P -d $db -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after_on' where b.label='before' and a.val is distinct from b.val")
echo "all three switches ON and profile data written: $n2 snapshots differ from before (must be 0)"
[ "$n2" = "0" ] || { fail=1; $P -d $db -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after_on' where b.label='before' and a.val is distinct from b.val"; }
ub=$($P -d $db -c "select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit)<>sum(credit)) z")
echo "unbalanced journal entries: $ub (must be 0)"; [ "$ub" = "0" ] || fail=1
crm=$($P -d $db -c "select count(*) from journal_entries where source_type like 'crm%'")
echo "journal entries created by CRM: ${crm:-0} (must be 0)"; [ "${crm:-0}" = "0" ] || fail=1
[ $fail = 0 ] && echo "RESULT crm_a before/after: all equal" || echo "RESULT crm_a before/after: DIFFERENCES"
exit $fail
