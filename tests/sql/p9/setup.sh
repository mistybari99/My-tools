#!/bin/bash
# usage: setup.sh dbname  (builds base through ALL_NEW)
REPO=${REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}
S=$REPO/tests/sql
R=$REPO/supabase
P="psql -h /tmp -p 5544 -U postgres -v ON_ERROR_STOP=1 -q"
psql -h /tmp -p 5544 -U postgres -q -c "drop database if exists $1" -c "create database $1" 
for f in $S/p9/mock_auth2.sql $R/schema.sql $R/phase2.sql $S/mock_storage.sql $R/phase3.sql $R/phase4.sql $R/ALL_NEW.sql; do
  $P -d $1 -f $f >/dev/null 2>/tmp/err.txt || { echo FAIL $f; head -5 /tmp/err.txt; exit 1; }
done
echo base ok
