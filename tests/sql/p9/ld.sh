psql -h /tmp -p 5544 -U postgres -d ${1:-t9} -v ON_ERROR_STOP=1 -q -f /home/user/My-tools/supabase/phase9.sql 2>&1 | grep -v NOTICE
