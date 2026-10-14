#!/bin/bash
# Fresh scratch DB through the canonical paste order (tests/sql/paste_order.env = the one place; docs/PASTE_ORDER.md mirrors it, tools/check_paste_order.py compares).
# usage: bash tests/sql/final_build.sh <dbname> [ORDER override]   (env: REPO = repo root, default = this file's repo; PGSOCK=/tmp PGPORT=5544)
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}; S="$REPO/tests/sql"; R="$REPO/supabase"
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; ERR=$(mktemp)
P="psql -h $PGSOCK -p $PGPORT -U postgres -v ON_ERROR_STOP=1 -q"
DB=$1
ORDER=${2:-"$(. "$S/paste_order.env"; for f in $FOUNDATION $NEW; do [ -f "$R/$f.sql" ] && echo -n "$f "; done)"}
psql -h $PGSOCK -p $PGPORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE
$P -d $DB -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
for f in $S/mock_auth2.sql $R/schema.sql $R/phase2.sql $S/mock_storage.sql $R/phase3.sql $R/phase4.sql $R/ALL_NEW.sql; do $P -d $DB -f $f >/dev/null 2>$ERR || { echo FAIL $f; head -5 $ERR; exit 1; }; done
for ph in $ORDER; do $P -d $DB -f $R/$ph.sql 2>&1 | grep -v NOTICE | head -10; done
echo built $DB
