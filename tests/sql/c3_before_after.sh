#!/bin/bash
# Stage C3 proof "switch OFF = byte-identical behaviour": on a build WITHOUT phase133 (final_build.sh with phase133 removed from ORDER), seed two businesses (tests/sql/c3_seed.sql: A = sweets, B = hardware,
# nine users incl. the owner and a notify bot), fingerprint every function phase133 re-creates for every user (can_grant / has_grant / can_do over many codes and places, rule_val / rule_on / rule_num /
# rule_txt over EVERY rule key, the readers' full output, the place-bound lookups, the login lockout), plus the report fingerprints; paste phase133.sql; fingerprint again; diff.
# Then the same fingerprints with the switch ON for the OWNER only (must also be identical: the owner sees everything and has no working business, so the group values apply).
# The set of function bodies that changed must equal the set of functions that carry the marker scope133 (nothing else was touched).
# usage: bash tests/sql/c3_before_after.sh <db_without_133> [<scratch_db_name>]    (the db is cloned; the clone is dropped at the end)  env PGSOCK=/tmp PGPORT=5544
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; PSQL="psql -h $PGSOCK -p $PGPORT -U postgres"
SRC=$1; DB=${2:-c3_133_ba_$$}
$PSQL -q -c "drop database if exists $DB" -c "create database $DB template $SRC" 2>&1 | grep -v NOTICE
cd "$REPO"
SEED=$(mktemp)
cat > $SEED <<'SQL'
\i tests/sql/e2e/00_common.sql
\i tests/sql/c3_seed.sql
select c3.seed_data(1, 2, :'ao', 'A', :'sbz'::bigint) is not null;
select c3.seed_data(:'hw1'::int, :'hw2'::int, :'bo', 'B', :'hbz'::bigint) is not null;
select tt.as(:'o');
insert into holidays (day, location_id, name_bn) values (current_date + 9, null, 'group');
SQL
$PSQL -d $DB -v mode=def -qAt -f $SEED > /tmp/c3_seed.log 2>&1
FP=$(mktemp)
USERS="00000000-0000-0000-0000-000000000001 00000000-0000-0000-0000-0000000c3a01 00000000-0000-0000-0000-0000000c3a02 00000000-0000-0000-0000-0000000c3a03 00000000-0000-0000-0000-0000000c3b01 00000000-0000-0000-0000-0000000c3b02 00000000-0000-0000-0000-0000000c3b03 00000000-0000-0000-0000-0000000c3a04 00000000-0000-0000-0000-0000000c3c01"
{
echo "\\set ON_ERROR_STOP off"
for u in $USERS; do
cat <<SQL
select set_config('request.jwt.claim.sub', '$u', false) \\gset
select '== user $u';
select 'can_grant ' || md5(coalesce((select string_agg(g.grant_code || ':' || public.can_grant(g.grant_code)::text, ' ' order by g.grant_code) from public.grant_defs g), ''));
select 'has_grant ' || md5(coalesce((select string_agg(g.grant_code || '@' || coalesce(l::text,'null') || ':' || public.has_grant(g.grant_code, l)::text, ' ' order by g.grant_code, l nulls first)
   from public.grant_defs g, unnest(array[null,1,2,3,5,7,12,13,14,99]::int[]) l), ''));
select 'can_do ' || md5(coalesce((select string_agg(f.code || ':' || a || ':' || public.can_do(f.code, a)::text, ' ' order by f.code, a) from public.forms f, unnest(array['view','enter','approve']) a), ''));
select 'rule_val ' || md5(coalesce((select string_agg(r.key || '=' || coalesce(public.rule_val(r.key)::text, 'null') || ':' || case r.kind when 'switch' then public.rule_on(r.key)::text when 'number' then coalesce(public.rule_num(r.key)::text, '-') else coalesce(public.rule_txt(r.key), '-') end, '|' order by r.key) from public.rules r where r.key <> 'org_scope_on'), ''));
select 'can_loc ' || coalesce((select string_agg(coalesce(l::text,'null') || ':' || public.can_loc(l)::text, ' ' order by l nulls first) from unnest(array[null,1,2,3,4,5,6,7,12,13,14,99]::int[]) l), '');
select 'flags ' || public._all_locs()::text || ' ' || public._acct_all()::text || ' ' || public._acct_view()::text || ' ' || public._acct_manage()::text;
select 'customer_dues_net113 ' || md5(coalesce((select string_agg(x::text, '|' order by x::text) from public.customer_dues_net113() x), '-'));
select 'rollout ' || md5(coalesce((select string_agg(f.code || '@' || l || ':' || public.rollout_mode(f.code, l) || public.blind_active(f.code, l)::text || public.stock_blind_active(f.code, l)::text, ' ' order by f.code, l)
   from (select code from public.forms limit 12) f, unnest(array[1,2,3,12,13,14]::int[]) l), ''));
select 'path_cfg ' || md5(coalesce((select string_agg(d.domain || '@' || l || ':' || public.path_cfg(d.domain, l)::text, ' ' order by d.domain, l) from public.path_domains d, unnest(array[0,1,12,13]::int[]) l), ''));
select 'templates ' || md5(coalesce((select string_agg(k || '@' || coalesce(l::text,'null') || ':' || coalesce((public.template_for(k, l)).id::text, '-'), ' ' order by k, l nulls first) from unnest(array['invoice','receipt']) k, unnest(array[null,1,12,13]::int[]) l), ''))
   || ' ' || md5(coalesce(public.get_doc_templates(1)::text, '-')) || md5(coalesce(public.get_doc_templates(null)::text, '-'));
select 'acct_status ' || md5(coalesce(public.acct_status()::text, '-'));
select 'acct_post_pending_dry ' || md5(coalesce(public.acct_post_pending(true, 1500)::text, '-'));
select 'control_counts ' || md5(coalesce(public.control_counts()::text, '-'));
select 'customer_dues ' || md5(coalesce((select string_agg(x::text, '|' order by x::text) from public.customer_dues() x), '-'));
select 'report_run ' || md5(coalesce(public.report_run('receivable_aging', '{}'::jsonb, null, null, 1, false)::text, '-'));
select 'report_run_sales ' || md5(coalesce(public.report_run('sales_summary', jsonb_build_object('from', (current_date - 30)::text, 'to', current_date::text), null, null, 1, false)::text, '-'));
select 'my_context ' || md5(coalesce(public.my_context()::text, '-'));
select 'daily_digest ' || md5(regexp_replace(coalesce(public.daily_digest(null)::text, '-'), '"generated_at": "[^"]*"', '', 'g'));
select 'photo_ok ' || md5(coalesce((select string_agg(n || ':' || public.photo_ok(n, a)::text, ' ' order by n, a) from unnest(array['STOCK/1/a.jpg','STOCK/12/a.jpg','PURCHASE/1/a.jpg','05-1/13/a.jpg','ITEMS/1/a.jpg']) n, unnest(array['view','enter']) a), ''));
SQL
done
cat <<'SQL'
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false) \gset
select '== reports';
select 'trial_balance ' || md5(acct_trial_balance((current_date - 90)::text::date, current_date)::text);
select 'sales_rows ' || count(*) || ' ' || coalesce(sum(total), 0) from sales;
select 'stock_ledger ' || count(*) || ' ' || coalesce(sum(qty_delta), 0) from stock_ledger;
select 'journal_lines ' || count(*) || ' ' || coalesce(sum(debit), 0) || ' ' || coalesce(sum(credit), 0) from journal_lines;
select 'rules_all ' || md5(string_agg(to_jsonb(r)::text, '|' order by key)) from rules r where key <> 'org_scope_on';
select 'policies_old ' || md5(string_agg(policyname || tablename || coalesce(qual,'') || coalesce(with_check,''), '|' order by tablename, policyname)) from pg_policies where schemaname = 'public' and policyname !~ '133$' and tablename !~ '133$' and tablename <> 'rule_overrides';
select 'login_lock ' || public.login_precheck('c3-unknown-id')::text;
select public.login_failed('c3-unknown-id') from generate_series(1, 7);
select 'login_lock_after_7_fails ' || public.login_precheck('c3-unknown-id')::text;
SQL
} > $FP
$PSQL -d $DB -qAt -f $FP > /tmp/c3_before.txt 2>&1
$PSQL -d $DB -qAt -c "select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' order by 1" > /tmp/c3_fn_before.txt
$PSQL -d $DB -qAt -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase133.sql" > /dev/null 2>&1 || echo "phase133 paste FAILED"
$PSQL -d $DB -qAt -c "delete from login_failures where staff_id = 'c3-unknown-id'" > /dev/null
$PSQL -d $DB -qAt -f $FP > /tmp/c3_after.txt 2>&1
$PSQL -d $DB -qAt -c "select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' order by 1" > /tmp/c3_fn_after.txt
echo "fingerprint lines: $(wc -l < /tmp/c3_before.txt) (errors inside: $(grep -c ERROR /tmp/c3_before.txt))"
if diff -q /tmp/c3_before.txt /tmp/c3_after.txt >/dev/null; then echo "C3 SWITCH OFF BEFORE/AFTER: OK (identical)"; else echo "C3 SWITCH OFF BEFORE/AFTER: DIFFERENT"; diff /tmp/c3_before.txt /tmp/c3_after.txt | head -40; fi
# the functions whose body changed = the functions that carry the marker (re-created or patched by phase133); everything older is untouched
CH=$(join -t '|' -j1 <(sort /tmp/c3_fn_before.txt) <(sort /tmp/c3_fn_after.txt) | awk -F'|' '$2 != $3 {print $1}' | sort)
MK=$($PSQL -d $DB -qAt -c "select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prosrc like '%scope133%' and p.proname !~ '133\$' order by 1" | sort)
if [ "$CH" == "$MK" ]; then echo "C3 CHANGED FUNCTIONS = MARKED FUNCTIONS: OK ($(echo "$CH" | grep -c .) functions)"; else echo "C3 CHANGED FUNCTIONS DIFFER FROM MARKED"; diff <(echo "$CH") <(echo "$MK") | head -20; fi
# switch ON: the owner must still see exactly the same
$PSQL -d $DB -qAt -c "update rules set value = 'true'::jsonb where key = 'org_scope_on'" >/dev/null
$PSQL -d $DB -qAt -f $FP > /tmp/c3_on.txt 2>&1
OWN='00000000-0000-0000-0000-000000000001'
awk -v u="$OWN" '/^== user /{p=($3==u)} p' /tmp/c3_before.txt | grep -v -E "^(login|policies_old)" > /tmp/c3_own_before.txt
awk -v u="$OWN" '/^== user /{p=($3==u)} p' /tmp/c3_on.txt | grep -v -E "^(login|policies_old)" > /tmp/c3_own_on.txt
if diff -q /tmp/c3_own_before.txt /tmp/c3_own_on.txt >/dev/null; then echo "C3 SWITCH ON, OWNER: OK (identical to before)"; else echo "C3 SWITCH ON, OWNER: DIFFERENT"; diff /tmp/c3_own_before.txt /tmp/c3_own_on.txt | head -20; fi
$PSQL -q -c "drop database if exists $DB" >/dev/null 2>&1; rm -f $FP $SEED
