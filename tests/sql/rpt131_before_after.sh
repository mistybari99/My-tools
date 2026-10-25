#!/bin/bash
# Reports Stage 1 proof "phase131 changes nothing that exists": compares a build WITHOUT phase131 with a build WITH it.
# Everything except the new rpt131_* functions and the rule rpt131_on must be identical: every function body, every other rule, every policy, table count, grant list.
# usage: bash tests/sql/rpt131_before_after.sh <db_without_131> <db_with_131>      env PGSOCK=/tmp PGPORT=5544
PSQL="psql -h ${PGSOCK:-/tmp} -p ${PGPORT:-5544} -U postgres -qAt"
fp() { $PSQL -d $1 -c "select md5(string_agg(oid::regprocedure::text||md5(pg_get_functiondef(oid)),',' order by oid::regprocedure::text)), count(*) from pg_proc where pronamespace='public'::regnamespace and prokind='f' and proname !~ 'rpt131'" \
 -c "select md5(string_agg(key||coalesce(value::text,'')||coalesce(default_value::text,''),',' order by key)), count(*) from rules where key<>'rpt131_on'" \
 -c "select md5(string_agg(tablename||policyname||coalesce(qual,''),',' order by tablename,policyname)) from pg_policies where schemaname='public'" \
 -c "select count(*) from pg_class where relnamespace='public'::regnamespace and relkind='r'" -c "select md5(string_agg(grant_code,',' order by grant_code)) from grant_defs"; }
a=$(fp $1); b=$(fp $2); echo "$a" | sed 's/^/before: /'; echo "$b" | sed 's/^/after:  /'
[ "$a" = "$b" ] && echo "RPT131 BEFORE/AFTER: OK (identical)" || { echo "RPT131 BEFORE/AFTER: DIFFERENT"; exit 1; }
