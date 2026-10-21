#!/bin/bash
# Step Sec2 (M1): the daily unmask limit under parallel calls.
# usage: bash tests/sql/p105_conc.sh <template db built through phase103 (phase105 NOT pasted)>        env: REPO, PGSOCK=/tmp PGPORT=5544
# Session A runs inbox_unmask inside an open transaction (holds it 3 s), session B calls inbox_unmask for ANOTHER message 1 s later.
# limit = 1 reveal per day. Without the advisory lock (phase103 build) B does not see A's uncommitted reveal and reveals too -> "2 revealed".
# With phase105 B waits for A, then sees used = 1 -> rate_limited -> "1 revealed".  Prints: BEFORE revealed=<n>  AFTER revealed=<n>  (expected 2 and 1).
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
TPL=$1; [ -z "$TPL" ] && { echo "usage: $0 <template db>"; exit 2; }
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; PSQL="psql -h $PGSOCK -p $PGPORT -U postgres -qAt"
Q=00000000-0000-0000-0000-000000000007; O=00000000-0000-0000-0000-000000000001
run() {   # $1 = before | after
  DB=p105conc_$$_$1; $PSQL -c "drop database if exists $DB" -c "create database $DB template $TPL" >/dev/null 2>&1
  [ "$1" = after ] && $PSQL -d $DB -v ON_ERROR_STOP=1 -f "$REPO/supabase/phase105.sql" >/dev/null 2>&1
  $PSQL -d $DB >/dev/null 2>&1 <<SQL
insert into auth.users (id,email,raw_user_meta_data) values ('$O','owner1@s.app','{"full_name":"Owner"}'), ('$Q','sales7@s.app','{"full_name":"Revealer"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values ('$O','owner'),('$Q','salesperson') on conflict do nothing;
insert into user_locations values ('$Q',1) on conflict do nothing;
insert into rule_grants (role_code, grant_code, allowed) values ('salesperson','inbox_contact_view',true) on conflict (role_code, grant_code) do update set allowed=true;
select set_config('request.jwt.claim.sub','$O',false);
select set_user_grant('$Q'::uuid,'inbox_unmask');
select set_rule('inbox_on','true');
select sales_channel_save(null,'fbpage','facebook',null,'FB page',1,null,'PAGE1',true);
select set_rule('inbox_pii_mode','"mask_phone"');
select set_rule('inbox_unmask_daily_max','1');
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, received_at)
  select id, 1, 'm-1', '01711000111', 'Customer A', 'hello', now() from sales_channels where code='fbpage';
insert into inbound_messages (channel_id, location_id, external_id, customer_handle, customer_name, msg_text, received_at)
  select id, 1, 'm-2', '01711000112', 'Customer B', 'price?', now() from sales_channels where code='fbpage';
SQL
  M1=$($PSQL -d $DB -c "select id from inbound_messages where external_id='m-1'"); M2=$($PSQL -d $DB -c "select id from inbound_messages where external_id='m-2'")
  ( $PSQL -d $DB -c "select set_config('request.jwt.claim.sub','$Q',false)" -c "begin" -c "select inbox_unmask('message','$M1')" -c "select pg_sleep(3)" -c "commit" >/dev/null 2>&1 ) &
  sleep 1
  $PSQL -d $DB -c "select set_config('request.jwt.claim.sub','$Q',false)" -c "select inbox_unmask('message','$M2')" >/dev/null 2>&1
  wait
  n=$($PSQL -d $DB -c "select count(*) from inbox_unmask_log99 where outcome='revealed'")
  $PSQL -c "drop database if exists $DB" >/dev/null 2>&1
  echo "$n"
}
b=$(run before); a=$(run after)
echo "BEFORE revealed=$b  AFTER revealed=$a   (expected 2 and 1)"
[ "$b" = 2 ] && [ "$a" = 1 ]
