REPO=${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}
S=$REPO/tests/sql/p8
su postgres -c "psql -h /tmp -p 5544 -qc 'drop database if exists p8' -c 'create database p8'" 2>&1 | grep -v NOTICE
bash $S/build.sh 2>&1 | grep -i "error"
for i in 1 2; do psql -h /tmp -p 5544 -U postgres -d p8 -v ON_ERROR_STOP=1 -q -f $REPO/supabase/phase8.sql 2>&1 | grep -v NOTICE; done
psql -h /tmp -p 5544 -U postgres -d p8 -qAt -f $REPO/supabase/phase8_test.sql 2>&1 | grep -E "FAIL|ERROR|--- (FAILED|TOTAL)" | head -80
