#!/bin/bash
# Phase 135 proof "the sweets business and the Places screen behave as before; only the new place functions exist": compares a build WITHOUT phase135 with a build WITH it (org_scope_on OFF, owner view).
# usage: bash tests/sql/loc135_before_after.sh <db_without_135> <db_with_135>      env PGSOCK=/tmp PGPORT=5544
# 1. every function body is byte-identical except location_save (patched once, marker /* loc135 */); no function is dropped; the new ones are listed
# 2. rules, grant_defs, org_tree, locations, counts, digest, dues, trial balance and every policy identical on the same seeded data (tests/sql/c3_seed.sql: sweets + hardware)
# 3. the OLD way to add a place (location_save(null, patch), what the Places screen does) gives the same row (except id / time), the same 17 steps, the same sheet versions and the same error texts in both builds
PSQL="psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -qAt"
cd "$(dirname "$0")/../.."
O=00000000-0000-0000-0000-000000000001
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
select 'ORG_TREE ' || md5(coalesce(string_agg(to_jsonb(t)::text, '|' order by t.id),'')) || ' ' || count(*) from org_tree() t;
select 'RULES ' || md5(string_agg(key||coalesce(value::text,'')||coalesce(default_value::text,''),',' order by key)) || ' ' || count(*) from rules;
select 'GRANTS ' || md5(string_agg(grant_code,',' order by grant_code)) from grant_defs;
select 'LOCS ' || md5(string_agg(id||code||coalesce(org_unit_id::text,'')||status,',' order by id)) from locations;
select 'COUNTS ' || (select count(*) from sales) || ' ' || (select count(*) from items) || ' ' || (select count(*) from customers) || ' ' || (select count(*) from journal_entries) || ' ' || (select count(*) from stock_ledger);
select 'DIGEST ' || md5(regexp_replace(daily_digest(null)::text, '"generated_at": "[^"]*"', '', 'g')); select 'DUES ' || (select sum(balance) from customer_dues());
select 'TB ' || md5(acct_trial_balance(null, null)::text);
select 'POLICIES ' || md5(string_agg(tablename||policyname||coalesce(qual,''),',' order by tablename,policyname)) from pg_policies where schemaname='public' and tablename <> 'business_place_ops135';
-- the old path: add a place through location_save and look at what it made
select location_save(null, '{"name_bn":"বা-আ ১৩৫","name_en":"BA place 135","code":"ba135","kind":"godown"}'::jsonb) ->> 'id' as nid \gset
select 'OLDPATH_ROW ' || (select md5(concat_ws('|', code, name_bn, name_en, kind, model, status, is_active, coalesce(org_unit_id::text,'NULL'), hub_functions)) from locations where id = :'nid'::int);
select 'OLDPATH_STEPS ' || (select count(*) || '/' || count(*) filter (where done) from location_setup_steps where location_id = :'nid'::int);
select 'OLDPATH_SHEETS ' || (select count(*) from settings_sheets where location_id = :'nid'::int);
do \$\$ declare m text; begin begin perform location_save(null, '{"name_bn":"বা-আ ১৩৫","code":"ba135b"}'::jsonb); exception when others then m := sqlerrm; end; raise notice 'OLDPATH_ERR_NAME %', m; end \$\$;
do \$\$ declare m text; begin begin perform location_save(null, '{"name_bn":"নতুন","code":"ba135"}'::jsonb); exception when others then m := sqlerrm; end; raise notice 'OLDPATH_ERR_CODE %', m; end \$\$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000c3a01',false) \gset
do \$\$ declare m text; begin begin perform location_save(null, '{"name_bn":"X","code":"ba135c"}'::jsonb); exception when others then m := sqlerrm; end; raise notice 'OLDPATH_ERR_USER %', m; end \$\$;
SQL
}
fn() { $PSQL -d $1 -c "select oid::regprocedure::text||' '||md5(pg_get_functiondef(oid)) from pg_proc where pronamespace='public'::regnamespace and prokind='f' order by 1"; }
a=$(fp $1 2>&1 | grep -v '^$'); b=$(fp $2 2>&1 | grep -v '^$')
echo "$a" | sed 's/^/before: /'; echo "$b" | sed 's/^/after:  /'
fn $1 > /tmp/fnA.$$; fn $2 > /tmp/fnB.$$
changed=$(join -j1 <(sed 's/ \([0-9a-f]*\)$/\t\1/' /tmp/fnA.$$ | sort) <(sed 's/ \([0-9a-f]*\)$/\t\1/' /tmp/fnB.$$ | sort) -t$'\t' | awk -F'\t' '$2!=$3{print $1}' | sed 's/(.*//; s/^public\.//' | sort | tr '\n' ' ')
dropped=$(comm -23 <(cut -d' ' -f1 /tmp/fnA.$$ | sort) <(cut -d' ' -f1 /tmp/fnB.$$ | sort) | wc -l)
added=$(comm -13 <(cut -d' ' -f1 /tmp/fnA.$$ | sort) <(cut -d' ' -f1 /tmp/fnB.$$ | sort) | sed 's/(.*//; s/^public\.//' | sort | tr '\n' ' ')
echo "changed functions: $changed"; echo "dropped functions: $dropped"; echo "new functions: $added"; rm -f /tmp/fnA.$$ /tmp/fnB.$$
if [ "$a" = "$b" ] && [ "$changed" = "location_save " ] && [ "$dropped" = "0" ] && [ "$added" = "_pc_biz135 _pc_ok135 _pc_unit135 _place_impact135 business_place_create135 business_place_move135 business_places_list135 business_profile_ensure135 " ]; then
  echo "LOC135 BEFORE/AFTER: OK (identical data, rules, tree, policies and the old add-a-place path; only location_save is patched, 8 functions are new)"; else echo "LOC135 BEFORE/AFTER: DIFFERENT"; exit 1; fi
