#!/bin/bash
# Phase 134 proof "the sweets business behaves as before, only the group is renamed and the profile exists": compares a build WITHOUT phase134 with a build WITH it (org_scope_on OFF, owner view).
# usage: bash tests/sql/prof134_before_after.sh <db_without_134> <db_with_134>      env PGSOCK=/tmp PGPORT=5544
# 1. every function body is byte-identical except the 12 functions phase134 re-creates or patches (listed, compared with the expected list) and the new ones
# 2. every rule and grant_def row identical; every policy identical except the 3 re-created (ou122_read, uos123_read, master_shares132_read) and the new one
# 3. with the same seeded owner and sweets data, the owner sees the same org_tree() rows (all columns) EXCEPT the group row, which differs only in its two names and the seed flag in attrs;
#    locations, sales, journal, trial balance, items, customers counts and sums are equal
PSQL="psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -qAt"
cd "$(dirname "$0")/../.."
O=00000000-0000-0000-0000-000000000001
# the same seeded data in both databases: two businesses (sweets with its places, hardware), the owner, users, sales / purchases / returns / entries ... (tests/sql/c3_seed.sql)
seed() { psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -qAt -d $1 >/dev/null 2>&1 <<SQL
\\i tests/sql/e2e/00_common.sql
\\i tests/sql/c3_probe.sql
\\i tests/sql/c3_seed.sql
select tt.as(:'o');
select c3.seed_data(1, 2, :'ao', 'A', :'sbz'::bigint);
select c3.seed_data(:'hw1'::int, :'hw2'::int, :'bo', 'B', :'hbz'::bigint);
SQL
}
fp() { seed $1; $PSQL -d $1 <<SQL
select set_config('request.jwt.claim.sub','$O',false) \gset
select 'ORG_TREE_NONGROUP ' || md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id),'')) || ' ' || count(*) from org_tree() t where t.kind <> 'group';
select 'ORG_TREE_GROUP_COLS ' || md5(((to_jsonb(t) - 'name_bn' - 'name_en' - 'attrs'))::text) from org_tree() t where t.kind = 'group';
select 'GROUP_NAME ' || name_bn || '/' || name_en from org_tree() t where t.kind = 'group';
select 'RULES ' || md5(string_agg(key||coalesce(value::text,'')||coalesce(default_value::text,''),',' order by key)) || ' ' || count(*) from rules;
select 'GRANTS ' || md5(string_agg(grant_code,',' order by grant_code)) from grant_defs;
select 'LOCS ' || md5(string_agg(id||code||coalesce(org_unit_id::text,''),',' order by id)) from locations;
select 'COUNTS ' || (select count(*) from sales) || ' ' || (select count(*) from items) || ' ' || (select count(*) from customers) || ' ' || (select count(*) from journal_entries) || ' ' || (select count(*) from stock_ledger);
select 'DIGEST ' || md5(regexp_replace(daily_digest(null)::text, '"generated_at": "[^"]*"', '', 'g')); select 'DUES ' || (select sum(balance) from customer_dues());
select 'TB ' || md5(acct_trial_balance(null, null)::text);
select 'POLICIES ' || md5(string_agg(tablename||policyname||coalesce(qual,''),',' order by tablename,policyname)) from pg_policies where schemaname='public' and policyname not in ('ou122_read','uos123_read','master_shares132_read','bp134_read');
SQL
}
fn() { $PSQL -d $1 -c "select oid::regprocedure::text||' '||md5(pg_get_functiondef(oid)) from pg_proc where pronamespace='public'::regnamespace and prokind='f' order by 1"; }
a=$(fp $1); b=$(fp $2)
echo "$a" | sed 's/^/before: /'; echo "$b" | sed 's/^/after:  /'
fn $1 > /tmp/fnA.$$; fn $2 > /tmp/fnB.$$
changed=$(join -j1 <(sed 's/ \([0-9a-f]*\)$/\t\1/' /tmp/fnA.$$ | sort) <(sed 's/ \([0-9a-f]*\)$/\t\1/' /tmp/fnB.$$ | sort) -t$'\t' | awk -F'\t' '$2!=$3{print $1}' | sed 's/(.*//; s/^public\.//' | sort | tr '\n' ' ')
dropped=$(comm -23 <(cut -d' ' -f1 /tmp/fnA.$$ | sort) <(cut -d' ' -f1 /tmp/fnB.$$ | sort) | wc -l)
expected="_ie_base124 _org_visible122 daily_digest_biz133 master_context_set132 master_scope_report132 master_share_list org_scope_list org_tree org_unit_deactivate org_unit_save org_unit_scope rule_val_in133 "
echo "changed functions: $changed"; echo "dropped functions: $dropped"; rm -f /tmp/fnA.$$ /tmp/fnB.$$
ga=$(echo "$a" | grep -v '^GROUP_NAME\|^ORG_TREE_GROUP_COLS' | md5sum); gb=$(echo "$b" | grep -v '^GROUP_NAME' | grep -v '^ORG_TREE_GROUP_COLS' | md5sum)
gc1=$(echo "$a" | grep '^ORG_TREE_GROUP_COLS'); gc2=$(echo "$b" | grep '^ORG_TREE_GROUP_COLS')
if [ "$ga" = "$gb" ] && [ "$gc1" = "$gc2" ] && [ "$changed" = "$expected" ] && [ "$dropped" = "0" ]; then echo "PROF134 BEFORE/AFTER: OK (identical except the group name, the 12 listed functions and the 3 policies)"; else echo "PROF134 BEFORE/AFTER: DIFFERENT"; exit 1; fi
