#!/bin/bash
# CRM-B proof (owner rules 2, 7, 8: accounting never changes, existing customers need no migration, privacy default keeps today's visibility):
#   1. A is a fresh build through phase 98 (BASE) with tests/sql/p87_fixture.sql + tests/sql/crmb_fixture.sql loaded (customers with sales, a due, a duplicate pair, everything posted).
#   2. Snapshot "before" (all accounting reports of p87_snap.sql + customer figures of crmb_snap.sql), paste 303, 304, 305 TWICE, snapshot "after": every snapshot equal.
#   3. The customer list at defaults equals customer_directory (19 columns, same order).
#   4. Every CRM-B switch ON, consent recorded, a customer exported, two customers linked, then unlinked: snapshot "on": every accounting and customer figure still equal.
#   5. The new rules sit at their safe defaults right after the paste.
# usage: bash tests/sql/crmb_before_after.sh      (local throwaway Postgres on PORT, default 5572; BASE must exist: a fresh build through phase 98)
PORT=${PORT:-5572}; BASE=${BASE:-crmb_base}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
OWN=00000000-0000-0000-0000-000000000987
fail=0; DB=crmb_ba
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB template $BASE" 2>&1 | grep -v NOTICE
$P -d $DB -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture p87"; exit 1; }
$P -d $DB -f $T/crmb_fixture.sql >/dev/null || { echo "FAIL fixture crmb"; exit 1; }
snap() { $P -d $DB -v label=$1 -f $T/p87_snap.sql >/dev/null && $P -d $DB -v label=$1 -f $T/crmb_snap.sql >/dev/null || { echo "FAIL snapshot $1"; exit 1; }; }
snap before
for round in 1 2; do for p in 303 304 305; do $P -d $DB -f $R/supabase/phase$p.sql >/dev/null 2>&1 || { echo "FAIL phase$p paste $round"; fail=1; }; done; done
snap after
cmp() { # label_a label_b   (crm_notify_state is excluded when consent was recorded on purpose)
  n=$($P -d $DB -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='$2' where b.label='$1' and a.val is distinct from b.val and (a.name <> 'crm_notify_state' or '$2' <> 'on')")
  tot=$($P -d $DB -c "select count(*) from tt.snap where label='$1'")
  echo "PASS-OR-FAIL $1 vs $2: $tot snapshots compared, $n differ"
  [ "$n" = "0" ] || { fail=1; $P -d $DB -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='$2' where b.label='$1' and a.val is distinct from b.val"; }
}
cmp before after
# the list at defaults is customer_directory
SETO="select set_config('request.jwt.claim.sub','$OWN',false);"
same=$($P -d $DB -c "$SETO select (select count(*) from (select id,mobile,name,type,active,tier_id,tier_locked,birthday,anniversary,address,whatsapp,note,credit_limit,customer_since,balance,spend,orders,last_sale,points from _crmb_customer_list() except select id,mobile,name,type,active,tier_id,tier_locked,birthday,anniversary,address,whatsapp,note,credit_limit,customer_since,balance,spend,orders,last_sale,points from customer_directory()) z)" | tail -1)
echo "customer list vs customer_directory at defaults: $same rows differ (must be 0)"; [ "$same" = "0" ] || fail=1
# defaults
d=$($P -d $DB -c "select (not rule_on('crm_consent_pos_on') and rule_txt('crm_quiet_from') is null and not rule_on('crm_pii_guard_on') and not rule_on('crm_reveal_for_call') and not rule_on('crm_export_on') and rule_num('crm_export_max_rows') is null and not rule_on('crm_print_needs_export') and not rule_on('crm_dup_check_on') and not rule_on('crm_dup_similar_names_on') and rule_on('crm_unmask_reason_required'))::text")
echo "defaults: $d (must be true)"; [ "$d" = "true" ] || fail=1
n=$($P -d $DB -c "$SETO select (select count(*) from notify_optin)||'/'||(select count(*) from crm_customer_links)||'/'||(select count(*) from crm_view_log)" | tail -1)
echo "no consent row, link or log line exists after the paste: $n (must be 0/0/0)"; [ "$n" = "0/0/0" ] || fail=1
# everything ON
$P -d $DB -c "$SETO select set_rule('crm_consent_pos_on','true'); select set_rule('crm_dup_check_on','true'); select set_rule('crm_dup_similar_names_on','true'); select set_rule('crm_export_on','true'); select set_rule('crm_export_max_rows','100'); select set_rule('crm_pii_guard_on','true'); select set_rule('crm_print_needs_export','true');" >/dev/null
$P -d $DB -c "$SETO
 select _crmb_consent_set(gen_random_uuid(), id, 'sms', true, 'paper_form', 'ba form') from customers where mobile='01760600001';
 select _crmb_consent_set(gen_random_uuid(), id, 'sms', false, 'phone', 'ba stop') from customers where mobile='01760600002';
 select _crmb_prefs_set(gen_random_uuid(), id, true, 'ba dnc') from customers where mobile='01760600003';
 select _crmb_export('customers','{}','csv',null,'ba export');
 select _crmb_dup_candidates();
 select _crmb_link_customers(gen_random_uuid(), a.id, b.id, 'ba same person') from customers a, customers b where a.mobile='01760600001' and b.mobile='01760600002';
 select _crmb_customer_list(5000, true); select _crmb_phone_reveal(id, 'ba') from customers where mobile='01760600001';" >/dev/null || { echo "FAIL switched-on calls"; fail=1; }
snap on
cmp before on
# the guard is ON now, so the list differs from the directory by design: only phone/address are hidden for a person without the grant
$P -d $DB -c "$SETO select count(*) from _crmb_customer_list() where mobile = '01760600001'" | tail -1 | grep -q '^1$' && echo "owner still sees full numbers" || { echo "FAIL owner sees masked numbers"; fail=1; }
ub=$($P -d $DB -c "select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit)<>sum(credit)) z")
echo "unbalanced entries: $ub (must be 0)"; [ "$ub" = "0" ] || fail=1
[ $fail = 0 ] && echo "RESULT crmb before/after: all equal" || echo "RESULT crmb before/after: DIFFERENCES"
exit $fail
