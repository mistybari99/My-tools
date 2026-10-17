#!/bin/bash
# CRM-F race proof: two cashiers redeem the LAST use of one coupon at the same moment. Exactly one must be accepted, the other refused (used_up / customer_limit).
# Session 1 holds the coupon row (redeem, then sleeps 2 seconds before it commits); session 2 starts half a second later and has to wait for the lock.
# usage: BASE=crmf_base PORT=5574 bash tests/sql/crmf_race.sh      (BASE = a fresh build through phase 98; local throwaway Postgres only)
PORT=${PORT:-5574}; BASE=${BASE:-crmf_base}; R=$(cd "$(dirname "$0")/../.." && pwd)
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
DB=cfrace; fail=0
psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $DB" -c "create database $DB template $BASE" 2>&1 | grep -v NOTICE
for n in 316 317 318; do $P -d $DB -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n"; exit 1; }; done
O=00000000-0000-0000-0000-000000031991; C1=00000000-0000-0000-0000-000000031992; C2=00000000-0000-0000-0000-000000031993
$P -d $DB >/dev/null <<EOF
insert into auth.users (id,email,raw_user_meta_data) values ('$O','test_owner_race@s.app','{}'),('$C1','test_cash1_race@s.app','{}'),('$C2','test_cash2_race@s.app','{}') on conflict do nothing;
update profiles set status='active' where id in ('$O','$C1','$C2');
insert into user_roles values ('$O','owner'),('$C1','salesperson'),('$C2','salesperson') on conflict do nothing;
insert into user_locations values ('$C1',1),('$C2',1) on conflict do nothing;
insert into location_settings (location_id,key,value) values (1,'discount_limit','500') on conflict (location_id,key) do update set value='500';
select set_config('request.jwt.claim.sub','$O',false);
select set_rule('crm_voucher_on','true'::jsonb); select set_rule('crm_voucher_max_amount','500'::jsonb);
select crmf_coupon_save(null, jsonb_build_object('code','RACEONE','name','test race one','kind','amount','value',100,'valid_from',(current_date-1)::text,'valid_to',(current_date+30)::text,'max_uses',1,'per_customer_uses',5));
select crmf_coupon_save(null, jsonb_build_object('code','RACECUST','name','test race customer','kind','amount','value',100,'valid_from',(current_date-1)::text,'valid_to',(current_date+30)::text,'max_uses',10,'per_customer_uses',1));
EOF
mk() { # cashier mobile code -> sale id
  $P -d $DB -c "set role authenticated; select set_config('request.jwt.claim.sub','$1',false); select (record_sale2(gen_random_uuid(),1,'[{\"amount\":1000}]',100,'[{\"mode\":\"cash\",\"amount\":900}]','$2','test_race_$2','retail',null,true))->>'id'" | tail -1
}
S1=$(mk $C1 01711991001); S2=$(mk $C2 01711991002); S3=$(mk $C1 01711991003); S4=$(mk $C2 01711991003)
run() { # cashier sale code sleep -> result
  $P -d $DB -c "set role authenticated; select set_config('request.jwt.claim.sub','$1',false); begin; select (r->>'ok') || ':' || coalesce(r->>'reason', 'ok') from (select crmf_coupon_redeem_after_sale('$3', '$2'::uuid) r) z; select pg_sleep($4); commit;" | grep -E "^(true|false):" | head -1
}
# scenario 1: two different customers race for the last of RACEONE
run $C1 $S1 RACEONE 2 > /tmp/crmf_race_1.txt &
sleep 0.5
run $C2 $S2 RACEONE 0 > /tmp/crmf_race_2.txt &
wait
r1=$(cat /tmp/crmf_race_1.txt); r2=$(cat /tmp/crmf_race_2.txt)
echo "scenario 1 (last use of RACEONE): session 1 -> $r1 ; session 2 -> $r2"
ok=$(printf "%s\n%s\n" "$r1" "$r2" | grep -c "^true"); ref=$(printf "%s\n%s\n" "$r1" "$r2" | grep -c "used_up")
live=$($P -d $DB -c "select count(*) from crmf_coupon_uses u join crmf_coupons c on c.id=u.coupon_id where c.code='RACEONE'")
echo "accepted=$ok refused_used_up=$ref recorded_uses=$live (must be 1 / 1 / 1)"; { [ "$ok" = 1 ] && [ "$ref" = 1 ] && [ "$live" = 1 ]; } || fail=1
# scenario 2: the SAME customer on two sales races a per-customer limit of 1
run $C1 $S3 RACECUST 2 > /tmp/crmf_race_3.txt &
sleep 0.5
run $C2 $S4 RACECUST 0 > /tmp/crmf_race_4.txt &
wait
r3=$(cat /tmp/crmf_race_3.txt); r4=$(cat /tmp/crmf_race_4.txt)
echo "scenario 2 (per-customer limit 1): session 1 -> $r3 ; session 2 -> $r4"
ok=$(printf "%s\n%s\n" "$r3" "$r4" | grep -c "^true"); ref=$(printf "%s\n%s\n" "$r3" "$r4" | grep -c "customer_limit")
live=$($P -d $DB -c "select count(*) from crmf_coupon_uses u join crmf_coupons c on c.id=u.coupon_id where c.code='RACECUST'")
echo "accepted=$ok refused_customer_limit=$ref recorded_uses=$live (must be 1 / 1 / 1)"; { [ "$ok" = 1 ] && [ "$ref" = 1 ] && [ "$live" = 1 ]; } || fail=1
[ $fail = 0 ] && echo "RESULT race: only one redemption wins" || echo "RESULT race: FAILED"
exit $fail
