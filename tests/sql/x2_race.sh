#!/bin/bash
# X2 oversell race test (local throwaway Postgres only, never the live project).
# usage: PORT=5810 bash tests/sql/x2_race.sh <db built through phases 481 + 482 + phase482_test>
# Makes its own copy of the database, sets up ONE tracked test item with stock 1 and reserve ON,
# then fires N checkouts in parallel for that one unit. Exactly one may succeed (advisory lock per item and branch).
set -u
PORT=${PORT:-5810}; SRC=${1:?source database}; DB=x2race_$$
P="psql -h /tmp -p $PORT -U postgres"
N=${N:-20}
$P -q -c "create database $DB template $SRC" || exit 1
trap '$P -q -c "drop database if exists $DB" >/dev/null 2>&1' EXIT
$P -d $DB -q -c "insert into items (code, name_bn, name_en, unit, base_unit, item_type, tracked, sell_price, category, category_bn)
  values ('RACE1','test_race','test_race','pc','pc','finished_good',true,10,'test_race','test_race')" >/dev/null || exit 1
RID=$($P -d $DB -tA -c "select id from items where code='RACE1'")
$P -d $DB -q -c "insert into stock_balance (item_id, location_id, qty, avg_cost) values ('$RID', 1, 1, 1)" >/dev/null
$P -d $DB -q -c "insert into web_item_pub (item_id, published, category_pub, price_snapshot) values ('$RID', true, 'test_race', 10)" >/dev/null
$P -d $DB -q -c "update rules set value='true' where key in ('website_on','website_reserve_on')" -c "update rules set value='0' where key='website_rate_max'" >/dev/null
for i in $(seq 1 $N); do
  sid=$(printf '00000000-0000-4000-9000-%012d' $i)
  ( $P -d $DB -tA -c "set role anon" -c "select public.web_checkout_submit('$sid'::uuid, 'test_racer', '0171100$(printf '%04d' $i)', 'pickup', null, null, ('[{\"item_id\":\"$RID\",\"qty\":1}]')::jsonb, null, 'cod', null, (now() at time zone 'Asia/Dhaka')::date, null, null, null)->>'ok'" 2>/dev/null | tail -1 > /tmp/x2race_$DB.$i ) &
done
wait
OK=$(cat /tmp/x2race_$DB.* 2>/dev/null | grep -c '^true$')
rm -f /tmp/x2race_$DB.*
HELD=$($P -d $DB -tA -c "select count(*) from web_stock_holds where item_id='$RID' and state='held'")
echo "parallel checkouts: $N, succeeded: $OK, live holds: $HELD"
if [ "$OK" = "1" ] && [ "$HELD" = "1" ]; then echo "RESULT race: PASS (exactly one unit sold)"; else echo "RESULT race: FAIL"; exit 1; fi
