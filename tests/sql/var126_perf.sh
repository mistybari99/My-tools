#!/bin/bash
# Phase 126 measurement on a SYNTHETIC 20,000-item hardware catalogue (+ the sweets items already in the base build). Scratch DB only; dropped at the end.
# usage: bash tests/sql/var126_perf.sh <db_built_through_phase122_or_later_WITHOUT_125> [scratch_db_name]     env PGSOCK=/tmp PGPORT=5544  KEEP=1 keeps the scratch db
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO=${REPO:-$(cd "$HERE/../.." && pwd)}
PGSOCK=${PGSOCK:-/tmp}; PGPORT=${PGPORT:-5544}; PSQL="psql -h $PGSOCK -p $PGPORT -U postgres"
SRC=$1; DB=${2:-var125_perf_$$}
$PSQL -q -c "drop database if exists $DB" -c "create database $DB template $SRC" 2>&1 | grep -v NOTICE
Q="$PSQL -d $DB -qAt -v ON_ERROR_STOP=1"
t() { local s e; s=$(date +%s%N); "$@" >/dev/null 2>&1; e=$(date +%s%N); echo $(( (e - s) / 1000000 )); }
(cd "$REPO" && $Q -f supabase/phase125.sql >/dev/null 2>&1) || { echo "phase125 paste failed"; exit 1; }
$Q <<'SQL' >/dev/null
update rules set value = 'true'::jsonb where key = 'variants_on';
insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000f1','pf@x.app','{}'),('00000000-0000-0000-0000-0000000000f2','pf2@x.app','{}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values ('00000000-0000-0000-0000-0000000000f1','owner'),('00000000-0000-0000-0000-0000000000f2','salesperson') on conflict do nothing;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f1',false);
select org_unit_save(null,(select id from org_units where kind='group'),'legal_entity','le-pf','pf','pf',null,null,null,null,'BDT','Asia/Dhaka','{}'::jsonb,null,gen_random_uuid());
select org_unit_save(null,(select id from org_units where code='LE-PF'),'business','PERF','pf','pf','hardware_paint','active',null,null,'BDT','Asia/Dhaka','{}'::jsonb,null,gen_random_uuid());
select org_unit_save(null,(select id from org_units where code='PERF'),'branch','PF-B1','pf','pf',null,'active',null,null,'BDT','Asia/Dhaka','{}'::jsonb,null,gen_random_uuid());
insert into locations (code,name_bn,kind,org_unit_id) values ('pf_shop','pf','showroom',(select id from org_units where code='PF-B1'));
insert into user_locations select '00000000-0000-0000-0000-0000000000f2', id from locations where code='pf_shop';
SQL
ld() { echo "${LOAD//__A__/$1}" | sed "s/__B__/$2/"; }
LOAD="insert into items (code,name_bn,name_en,name_mix,category,unit,sell_price,barcode,org_unit_id,tracked)
select 'P'||lpad(g::text,6,'0'), 'পণ্য '||g||' '||(array['রং','পেইন্ট','পাইপ','তার','স্ক্রু','ব্রাশ'])[1+g%6],
  (array['Emulsion','Enamel','Primer','Putty','Brush','Roller','Pipe','Elbow','Wire','Switch','Screw','Hammer'])[1+g%12]||' '||(array['white','red','blue','1L','4L','20L','2in','3in','15mm'])[1+g%9]||' '||g,
  'item '||g, (array['Paint','Hardware','Sanitary','Electrical','Tools','Home','Accessories','Putty'])[1+g%8], 'pc', 50+g%900, '29'||lpad(g::text,11,'0'),
  (select id from org_units where code='PERF'), true
from generate_series(__A__,__B__) g"
$Q -c "$(ld 1 10000)" >/dev/null
INS_NO=$(t $Q -c "$(ld 10001 12000)")      # 2,000 inserts WITHOUT the phase126 indexes
$Q -c "$(ld 12001 20000)" >/dev/null
$Q -c "analyze items" >/dev/null
echo "items: $($Q -c "select count(*) from items") total, $($Q -c "select count(*) from items where org_unit_id=(select id from org_units where code='PERF')") in PERF, $($Q -c "select count(*) from items where org_unit_id=(select id from org_units where code='SWEETS')") sweets"
echo "table size: $($Q -c "select pg_size_pretty(pg_total_relation_size('items'))") before phase126 indexes"
(cd "$REPO" && $Q -f supabase/phase126.sql >/dev/null 2>&1) || { echo "phase126 paste failed"; exit 1; }
$Q -c "analyze items" >/dev/null
echo "phase126 mode: $($Q -c "select items_search_info126()->>'trigram'") (trigram); table+indexes now $($Q -c "select pg_size_pretty(pg_total_relation_size('items'))")"
$Q -c "update items set brand = (array['Asian','Berger','Classic','Nippon','Jotun','Local','Hindware','Walton','Pran','Rfl','Bashundhara','Gazi'])[1+substr(code,2)::int%12] where code ~ '^P[0-9]+\$'" >/dev/null
INS_YES=$(t $Q -c "$(ld 20001 22000)")
echo "INSERT 2,000 items: ${INS_NO} ms without phase126 indexes, ${INS_YES} ms with them"
PF=00000000-0000-0000-0000-0000000000f1; HM=00000000-0000-0000-0000-0000000000f2
# each timing = best of 3, server-side (explain analyze would hide the function call; use clock via psql \timing)
tm() { # $1 = user, $2 = sql
  local best=999999 i ms
  for i in 1 2 3; do
    ms=$($PSQL -d $DB -qAt -v ON_ERROR_STOP=1 <<SQL | grep '^Time' | sed 's/Time: //;s/ ms//' | cut -d. -f1
select set_config('request.jwt.claim.sub','$1',false);
set role authenticated;
\timing on
$2
SQL
)
    [ -n "$ms" ] && [ "$ms" -lt "$best" ] && best=$ms
  done; echo $best; }
ORG=$($Q -c "select id from org_units where code='PERF'")
row() { printf '%-62s %6s ms\n' "$1" "$2"; }
echo "--- items_search as the hardware staff user (scope + RLS applied), best of 3"
row "name substring 'emulsion' (20k+ rows, page 50, with counts)" "$(tm $HM "select items_search($ORG,'emulsion','{}',50,0);")"
row "name substring 'putty 4L'" "$(tm $HM "select items_search($ORG,'putty 4L','{}',50,0);")"
row "Bangla substring 'পেইন্ট'" "$(tm $HM "select items_search($ORG,'পেইন্ট','{}',50,0);")"
row "rare term 'item 19999' (1 row)" "$(tm $HM "select items_search($ORG,'item 19999','{}',50,0);")"
row "code prefix 'P0123'" "$(tm $HM "select items_search($ORG,'P0123','{}',50,0);")"
row "barcode exact" "$(tm $HM "select items_search($ORG,'2900000012345','{}',50,0);")"
row "category filter 'Paint' + brand 'Asian', page 3" "$(tm $HM "select items_search($ORG,null,'{\"category\":\"Paint\",\"brand\":\"Asian\"}',50,100);")"
row "no query, first page, with summary counts" "$(tm $HM "select items_search($ORG,null,'{}',50,0);")"
row "no query, deep page (offset 20000)" "$(tm $HM "select items_search($ORG,null,'{}',50,20000);")"
row "no query, first page, counts off" "$(tm $HM "select items_search($ORG,null,'{\"counts\":false}',50,0);")"
row "short query 'em' (prefix only)" "$(tm $HM "select items_search($ORG,'em','{}',50,0);")"
row "owner, all businesses, 'brush'" "$(tm $PF "select items_search(null,'brush','{}',50,0);")"
echo "--- the old way, for comparison (same user)"
row "select count(*) from items  (hardware user, switch ON)" "$(tm $HM "select count(*) from items;")"
row "select ... from items order by code limit 50 (hardware user)" "$(tm $HM "select id,code,name_bn,sell_price from items order by code limit 50;")"
row "select count(*) from items  (sweets-style owner)" "$(tm $PF "select count(*) from items;")"
$Q -c "update rules set value='false'::jsonb where key='variants_on'" >/dev/null
row "select count(*) from items  (hardware user, switch OFF = old policy)" "$(tm $HM "select count(*) from items;")"
$Q -c "update rules set value='true'::jsonb where key='variants_on'" >/dev/null
echo "--- plans"
$PSQL -d $DB -qAt <<SQL | grep -E "Index|Bitmap|Seq Scan|Execution" | head -12
select set_config('request.jwt.claim.sub','$HM',false);
set role authenticated;
explain analyze select id from items where org_unit_id=$ORG and (name_en ilike '%emulsion%' or name_bn ilike '%emulsion%' or name_mix ilike '%emulsion%' or lower(code) like 'emulsion%' escape '\\');
SQL
[ -n "$KEEP" ] || $PSQL -q -c "drop database if exists $DB" >/dev/null 2>&1
