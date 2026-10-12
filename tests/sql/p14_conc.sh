#!/bin/bash
# usage: p14_conc.sh <db> <owner uuid>   -> prints "<n codes>/<n distinct>/<n errors>" for 8 parallel item_new calls in one category
DB=$1; OWN=$2; D=$(mktemp -d)
for i in 1 2 3 4 5 6 7 8; do
  ( psql -h /tmp -p 5544 -U postgres -d $DB -qAt -c "select set_config('request.jwt.claim.sub','$OWN',false)" -c "set role authenticated" \
      -c "select item_new(jsonb_build_object('name_bn','conc $i','category','c14','item_type','finished_good'))->>'code'" > $D/$i.out 2> $D/$i.err ) &
done
wait
codes=$(cat $D/*.out | grep -E '^[0-9]{2}-[0-9]+$' | sort)
n=$(echo "$codes" | grep -c .); d=$(echo "$codes" | sort -u | grep -c .); e=$(cat $D/*.err | grep -c ERROR)
echo "$n/$d/$e"; rm -rf $D
