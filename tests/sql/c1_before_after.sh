#!/bin/bash
# Stage C1 proof "switch OFF = byte-identical behaviour": on a build WITHOUT phase123 (final_build.sh with phase123 removed from ORDER), seed the A3/A5 scenario (phase118_test.sql) plus a
# matrix of users (owner, two management users, staff with and without a place, an accountant with NULL-location grants), fingerprint every function phase123 re-creates for every user
# (can_loc / has_grant / _all_locs / _acct_all / _notif_ok per place; the readers' full output), plus the report fingerprints of b1_before_after.sh; paste phase123.sql; fingerprint again; diff.
# Then the same fingerprints are taken with the switch ON for the OWNER only (must also be identical: the owner sees everything) and the script prints OK / DIFFERENT.
# usage: bash tests/sql/c1_before_after.sh <db_without_123> [<scratch_db_name>]    (the db is cloned; the clone is dropped at the end)  env PGSOCK=/tmp PGPORT=5544
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; PSQL="psql -h $PGSOCK -p $PGPORT -U postgres"
SRC=$1; DB=${2:-c1_ba_$$}
$PSQL -q -c "drop database if exists $DB" -c "create database $DB template $SRC" 2>&1 | grep -v NOTICE
(cd "$REPO" && $PSQL -d $DB -qAt -f supabase/phase118_test.sql 2>&1 | grep -E '^RESULT')
SEED=$(mktemp)
cat > $SEED <<'SQL'
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000101','m1@c1.app','{"full_name":"Mgmt One"}'),('00000000-0000-0000-0000-000000000102','m2@c1.app','{"full_name":"Mgmt Two"}'),
 ('00000000-0000-0000-0000-000000000103','s1@c1.app','{"full_name":"Staff Three"}'),('00000000-0000-0000-0000-000000000104','s0@c1.app','{"full_name":"Staff None"}'),
 ('00000000-0000-0000-0000-000000000105','ac@c1.app','{"full_name":"Accountant"}') on conflict do nothing;
update profiles set status = 'active' where id::text like '00000000-0000-0000-0000-0000000001%';
insert into user_roles values ('00000000-0000-0000-0000-000000000101','management'),('00000000-0000-0000-0000-000000000102','management'),('00000000-0000-0000-0000-000000000103','salesperson'),
 ('00000000-0000-0000-0000-000000000104','salesperson'),('00000000-0000-0000-0000-000000000105','hr') on conflict do nothing;
insert into user_locations values ('00000000-0000-0000-0000-000000000101',1),('00000000-0000-0000-0000-000000000103',3),('00000000-0000-0000-0000-000000000105',2) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values ('00000000-0000-0000-0000-000000000103','view_cost',null),('00000000-0000-0000-0000-000000000105','accounts_manage',null),
 ('00000000-0000-0000-0000-000000000105','accounts_view',2),('00000000-0000-0000-0000-000000000104','view_reports',3) on conflict do nothing;
SQL
$PSQL -d $DB -qAt -f $SEED > /dev/null 2>&1
# fingerprint script: one block per user
FP=$(mktemp)
USERS="00000000-0000-0000-0000-000000000001 00000000-0000-0000-0000-000000000101 00000000-0000-0000-0000-000000000102 00000000-0000-0000-0000-000000000103 00000000-0000-0000-0000-000000000104 00000000-0000-0000-0000-000000000105"
{
echo "\\set ON_ERROR_STOP off"
for u in $USERS; do
cat <<SQL
select set_config('request.jwt.claim.sub', '$u', false) \\gset
select '== user $u';
select 'can_loc ' || coalesce((select string_agg(coalesce(l::text,'null') || ':' || public.can_loc(l)::text, ' ' order by l nulls first) from unnest(array[null,1,2,3,4,5,6,7,99]::int[]) l), '');
select 'has_grant ' || coalesce((select string_agg(g || '@' || coalesce(l::text,'null') || ':' || public.has_grant(g, l)::text, ' ' order by g, l nulls first)
   from unnest(array['view_cost','accounts_view','accounts_manage','view_reports','purchase_entry','stock_transfer']) g, unnest(array[null,1,2,3,5,7]::int[]) l), '');
select 'flags ' || public._all_locs()::text || ' ' || public._acct_all()::text || ' ' || public._acct_view()::text || ' ' || public._acct_manage()::text;
select 'notif_ok ' || coalesce((select string_agg(a || '@' || coalesce(l::text,'null') || ':' || public._notif_ok(null, a, l)::text, ' ' order by a, l nulls first)
   from unnest(array['all','manager','owner']) a, unnest(array[null,1,3]::int[]) l), '');
select 'staff_directory ' || md5(public.staff_directory()::text);
select 'customer_dues ' || count(*) || ' ' || coalesce(sum(balance),0) || ' ' || md5(coalesce(string_agg(d::text,'|' order by d::text),'')) from public.customer_dues() d;
select 'customer_ledger ' || md5(coalesce((select string_agg(x::text,'|' order by x::text) from public.customer_ledger((select customer_id from sales where customer_id is not null limit 1)) x),'-'));
select 'fa_register ' || md5(coalesce(public.fa_register(current_date)::text,'-'));
select 'year_close_list ' || md5(coalesce(public.year_close_list()::text,'-'));
select 'items_with_cost ' || count(*) || ' ' || md5(coalesce(string_agg(x::text,'|' order by x::text),'')) from public.items_with_cost() x;
select 'item_cost_status88 ' || count(*) || ' ' || md5(coalesce(string_agg(x::text,'|' order by x::text),'')) from public.item_cost_status88() x;
select 'drawer_report ' || md5(coalesce(public.drawer_report(current_date - 60, current_date)::text,'-'));
select 'profit_truth112 ' || md5(coalesce(public.profit_truth112(current_date - 90, current_date, null)::text,'-'));
select 'profit_truth112_loc3 ' || md5(coalesce(public.profit_truth112(current_date - 90, current_date, 3)::text,'-'));
select 'sales_visible ' || count(*) from sales;   -- through the RLS of the session role is not applied (superuser), so use the policy function directly:
select 'can_loc_rows ' || (select count(*) from sales s where public.can_loc(s.location_id)) || ' ' || (select count(*) from journal_lines j where public.can_loc(j.location_id))
   || ' ' || (select count(*) from stock_ledger s where public.can_loc(s.location_id));
SQL
done
cat <<'SQL'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false) \gset
select (current_date - 90)::text as f, current_date::text as t \gset
select '== reports';
select 'trial_balance ' || md5(acct_trial_balance(:'f', :'t')::text);
select 'net_profit_report ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from net_profit_report(:'f', :'t') r), ''));
select 'stock_recon_statement ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from stock_recon_statement(:'f', :'t') r), ''));
select 'factory_branch_statement ' || md5(coalesce((select string_agg(to_jsonb(r)::text, '|' order by to_jsonb(r)::text) from factory_branch_statement(:'f', :'t') r), ''));
select 'sales_rows ' || count(*) || ' ' || coalesce(sum(total), 0) from sales;
select 'stock_ledger ' || count(*) || ' ' || coalesce(sum(qty_delta), 0) from stock_ledger;
select 'journal_lines ' || count(*) || ' ' || coalesce(sum(debit), 0) || ' ' || coalesce(sum(credit), 0) from journal_lines;
select 'old_functions ' || md5(string_agg(p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)), '|' order by p.oid::regprocedure::text))
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
   and p.proname not in ('can_loc','has_grant','_all_locs','_acct_all','_notif_ok','staff_directory','customer_dues','customer_ledger','fa_register','fa_schedule','year_close_list','items_with_cost','item_cost_status88','drawer_report','profit_truth112','decide_emergency')
   and p.proname !~ '(^org_|^_org_|^_le_kind_check122|123$|^can_scope$|^business_of_)';
select 'rules_other ' || md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r where key <> 'org_scope_on';
select 'policies_old ' || md5(string_agg(policyname || tablename || coalesce(qual,'') || coalesce(with_check,''), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public' and policyname !~ '123$' and tablename <> 'user_org_scopes';
SQL
} > $FP
$PSQL -d $DB -qAt -f $FP > /tmp/c1_before.txt 2>&1
$PSQL -d $DB -qAt -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase123.sql" > /dev/null 2>&1 || echo "phase123 paste FAILED"
$PSQL -d $DB -qAt -f $FP > /tmp/c1_after.txt 2>&1
echo "fingerprint lines: $(wc -l < /tmp/c1_before.txt) (errors inside: $(grep -c ERROR /tmp/c1_before.txt))"
if diff -q /tmp/c1_before.txt /tmp/c1_after.txt >/dev/null; then echo "C1 SWITCH OFF BEFORE/AFTER: OK (identical)"; else echo "C1 SWITCH OFF BEFORE/AFTER: DIFFERENT"; diff /tmp/c1_before.txt /tmp/c1_after.txt | head -40; fi
# switch ON: the owner must still see exactly the same
$PSQL -d $DB -qAt -c "update rules set value = 'true'::jsonb where key = 'org_scope_on'" >/dev/null
$PSQL -d $DB -qAt -f $FP > /tmp/c1_on.txt 2>&1
OWN='00000000-0000-0000-0000-000000000001'
awk -v u="$OWN" '/^== user /{p=($3==u)} p' /tmp/c1_before.txt > /tmp/c1_own_before.txt
awk -v u="$OWN" '/^== user /{p=($3==u)} p' /tmp/c1_on.txt > /tmp/c1_own_on.txt
if diff -q /tmp/c1_own_before.txt /tmp/c1_own_on.txt >/dev/null; then echo "C1 SWITCH ON, OWNER: OK (identical to before)"; else echo "C1 SWITCH ON, OWNER: DIFFERENT"; diff /tmp/c1_own_before.txt /tmp/c1_own_on.txt | head -20; fi
$PSQL -q -c "drop database if exists $DB" >/dev/null 2>&1; rm -f $FP $SEED
