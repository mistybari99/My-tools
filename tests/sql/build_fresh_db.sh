REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
S=$REPO/tests/sql
R=$REPO/supabase
PGP=${PGPORT:-5544}                                         # local throwaway Postgres port (default 5544; PGPORT=5610 to use another)
P="psql -h /tmp -p $PGP -U postgres -v ON_ERROR_STOP=1 -q"
DB=$1; shift
ORDER=${ORDER:-"phase8 phase9 phase10"}
[ "$ORDER" = "all" ] && ORDER=$(grep -v "^#" $S/ORDER.txt)   # ORDER=all: every phase of the owner paste order (tests/sql/ORDER.txt), phase 8 to the last
psql -h /tmp -p $PGP -U postgres -q -c "drop database if exists $DB" -c "create database $DB" 2>&1 | grep -v NOTICE
[ -z "$NODEF" ] && $P -d $DB -c "alter default privileges in schema public grant all on tables to anon, authenticated; alter default privileges in schema public grant all on functions to anon, authenticated; alter default privileges in schema public grant all on sequences to anon, authenticated;" 2>&1 | grep -v NOTICE
for f in $S/mock_auth2.sql $R/schema.sql $R/phase2.sql $S/mock_storage.sql $R/phase3.sql $R/phase4.sql $R/ALL_NEW.sql; do $P -d $DB -f $f >/dev/null 2>/tmp/errf.txt || { echo FAIL $f; head -5 /tmp/errf.txt; exit 1; }; done
for ph in $ORDER; do $P -d $DB -f $R/$ph.sql 2>&1 | grep -v NOTICE | head -10; done
echo built $DB
