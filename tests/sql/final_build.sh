#!/bin/bash
# Fresh scratch DB through the canonical paste order (docs/PASTE_ORDER.md): phase8..71, 72..88, 90, 91, 89, 92, 93, 95, 94, 96, 97, then 98 LAST (phase98 = merge of what 96 and 97 both re-create).
# usage: bash tests/sql/final_build.sh <dbname> [ORDER override]   (Postgres on socket /tmp port 5544; repo paths are taken from this file's location)
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE"; R="$HERE/../../supabase"
P="psql -h /tmp -p 5544 -U postgres -v ON_ERROR_STOP=1 -q"
DB=$1
ORDER=${2:-"phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase52 phase53 phase54 phase60 phase61 phase62 phase70 phase71 phase72 phase73 phase74 phase75 phase76 phase77 phase78 phase79 phase80 phase81 phase82 phase83 phase84 phase85 phase86 phase87 phase88 phase90 phase91 phase89 phase92 phase93 phase95 phase94 phase96 phase97 phase98"}
psql -h /tmp -p 5544 -U postgres -q -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE
$P -d $DB -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
for f in $S/mock_auth2.sql $R/schema.sql $R/phase2.sql $S/mock_storage.sql $R/phase3.sql $R/phase4.sql $R/ALL_NEW.sql; do $P -d $DB -f $f >/dev/null 2>/tmp/final_build_err.txt || { echo FAIL $f; head -5 /tmp/final_build_err.txt; exit 1; }; done
for ph in $ORDER; do $P -d $DB -f $R/$ph.sql 2>&1 | grep -v NOTICE | head -10; done
echo built $DB
