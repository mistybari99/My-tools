#!/bin/bash
# equality120.sh <db> <out.txt>   (env: PGSOCK=/tmp PGPORT=5544)
# md5 of every output of the phase118 reports + their internal buckets / gap functions over a grid of periods, places, items and categories, as the owner.
# Run it on a database BEFORE phase120 and on a clone AFTER it (same data): `diff before.txt after.txt` must print nothing.
# Needs the seed of tests/sql/perf (seed.sql, seed_post.sql, seed_c4.sql) or any database that has phase118.
DB=$1; OUT=${2:-/dev/stdout}; PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}
OWN=00000000-0000-0000-0000-0000000000a1
Q=$(mktemp)
{
echo "select set_config('request.jwt.claim.sub','$OWN',false) is not null;"
echo "select (select id from items where code='P0160')::text as a, (select id from items where code='P0300')::text as b, (select id from items where code='P0003')::text as c \\gset"
for rng in "current_date-1,current_date-1" "current_date-7,current_date-1" "current_date-30,current_date-1" "current_date-90,current_date-45" "current_date-200,current_date-100" "current_date-370,current_date-1"; do
  big=0; [ "$rng" = "current_date-370,current_date-1" ] && big=1
  for loc in null 1 2 6 7; do
    for itm in null ":'a'" ":'b'" ":'c'"; do
      for cat in null "'cat7'"; do
        # the year view is heavy on the old code: only two combinations
        if [ $big = 1 ] && [ "$loc" != null ] && [ "$loc" != 6 ]; then continue; fi
        if [ $big = 1 ] && [ "$itm" != null ] && [ "$cat" != null ]; then continue; fi
        if [ "$itm" != null ] && [ "$cat" != null ]; then continue; fi
        t="$rng|$loc|$itm|$cat"; t=${t//\'/}; t=${t//:/}
        echo "select 'RECON $t', md5(stock_recon_statement($rng,$loc,$itm::uuid,$cat,5000)::text);"
        echo "select 'FBRANCH $t', md5(factory_branch_statement($rng,$loc,$itm::uuid,$cat,5000)::text);"
        if [ "$cat" = null ]; then
          echo "select 'UNMATCHED $t', md5(stock_sales_unmatched($rng,$loc,$itm::uuid,2000)::text);"
          echo "select 'BUCKETS $t', md5(coalesce(string_agg(x::text,'|' order by x.location_id, x.item_id),'-')) from _rc118_buckets($rng,array(select id from locations where ($loc::int is null or id=$loc::int)),$itm::uuid,null) x;"
          echo "select 'GAP $t', md5(coalesce(string_agg(x::text,'|' order by x.sale_id, x.item_id),'-')) from _rc118_gap($rng,array(select id from locations where ($loc::int is null or id=$loc::int)),$itm::uuid) x;"
        else
          echo "select 'BUCKETSC $t', md5(coalesce(string_agg(x::text,'|' order by x.location_id, x.item_id),'-')) from _rc118_buckets($rng,array(select id from locations where ($loc::int is null or id=$loc::int)),$itm::uuid,$cat) x;"
        fi
      done
    done
  done
done
} > $Q
psql -h $PGSOCK -p $PGPORT -U postgres -d $DB -X -At -F ' ' -q -f $Q 2>&1 | grep -v '^t$' > $OUT
echo "$(wc -l < $OUT) lines, $(grep -c ERROR $OUT) errors -> $OUT"
rm -f $Q
