#!/bin/bash
# Fresh scratch DB through the canonical paste order (tests/sql/paste_order.env = the one place; docs/PASTE_ORDER.md mirrors it, tools/check_paste_order.py compares).
# usage: bash tests/sql/final_build.sh <dbname> [ORDER override]   (env: REPO = repo root, default = this file's repo; PGSOCK=/tmp PGPORT=5544)
# env FROM=<db>: start from a clone of <db> (a database already built through an earlier point of the same order) and paste only ORDER on it; the base files are not pasted again.
# Fails closed: exit 1 (and no "built <db>" line) when the database cannot be created or any file stops with an error.
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}; S="$REPO/tests/sql"; R="$REPO/supabase"
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; ERR=$(mktemp)
P="psql -h $PGSOCK -p $PGPORT -U postgres -v ON_ERROR_STOP=1 -q"
DB=$1
ORDER=${2:-"$(. "$S/paste_order.env"; for f in $FOUNDATION $NEW; do [ -f "$R/$f.sql" ] && echo -n "$f "; done)"}
[ -n "$DB" ] || { echo "usage: final_build.sh <dbname> [ORDER]"; exit 1; }
if [ -n "$FROM" ]; then
  $P -c "drop database if exists $DB" -c "create database $DB template $FROM" >$ERR 2>&1 || { echo FAIL create database $DB template $FROM; grep -v NOTICE $ERR | head -5; exit 1; }
else
$P -c "drop database if exists $DB" -c "create database $DB" >$ERR 2>&1 || { echo FAIL create database $DB; grep -v NOTICE $ERR | head -5; exit 1; }
$P -d $DB -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" >$ERR 2>&1 || { echo FAIL default privileges; head -5 $ERR; exit 1; }
for f in $S/mock_auth2.sql $R/schema.sql $R/phase2.sql $S/mock_storage.sql $R/phase3.sql $R/phase4.sql $R/ALL_NEW.sql; do $P -d $DB -f $f >/dev/null 2>$ERR || { echo FAIL $f; head -5 $ERR; exit 1; }; done
fi
for ph in $ORDER; do $P -d $DB -f $R/$ph.sql >$ERR 2>&1; rc=$?; grep -v NOTICE $ERR | head -10; [ $rc -eq 0 ] || { echo FAIL $ph; exit 1; }; done
rm -f $ERR
echo built $DB
