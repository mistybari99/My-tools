#!/bin/bash
# CRM-C hook proof (docs/integration/CRM-C.md, section 3): the one optional line in notify_scan, applied by _crmc_patch on a scratch COPY of a database.
#   BASE = a database through phase 99 (default c_base99). Two copies A (never patched) and B (patched). Same data, same calls.
#   1. the patch applies once (true), carries the marker bosCRMC, a second call patches nothing (false); the 37 earlier hooks of phase 99 are all still present
#   2. schedule switched OFF (default): notify_scan on A and on B give the SAME answer, and no score run is written
#   3. schedule ON with hours: B writes one scheduled run per due moment; a second scan inside the hours writes nothing (A never writes any)
#   4. a failing CRM-C function can never stop the scan: B still answers
# usage: bash tests/sql/crmc_hook.sh      (local throwaway Postgres on PORT, default 5573)
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$(cd "$HERE/../.." && pwd)"; T="$HERE"
PORT=${PORT:-5573}; BASE=${BASE:-c_base99}
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
for db in hook_a hook_b; do
  psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE
  for f in w1d_fixture w1d_snap_setup p99_fixture_extra crmc_fixture; do $P -d $db -f $T/$f.sql >/dev/null 2>&1 || { echo "FAIL fixture $f on $db"; exit 1; }; done
  for n in 306 307 308; do $P -d $db -f $R/supabase/phase$n.sql >/dev/null 2>&1 || { echo "FAIL phase$n on $db"; exit 1; }; done
  $P -d $db -c "select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000c301',false); select set_rule('notify_on','true'::jsonb)" >/dev/null 2>&1
  $P -d $db -c "insert into ops_accounts (user_id, purpose) values ('00000000-0000-0000-0000-00000000c307','notify') on conflict do nothing" >/dev/null 2>&1
done
PATCH=$(cat <<'EOS'
select public._crmc_patch('public.notify_scan()'::regprocedure, array[
  E'  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);',
  E'  if to_regprocedure(''public.crmc_scheduled_run()'') is not null then begin perform public.crmc_scheduled_run(); exception when others then null; end; end if; /* bosCRMC */\n  select coalesce(sum(v::int), 0) into cnt from jsonb_each_text(made) e(k, v);'
], 'bosCRMC');
EOS
)
r1=$($P -d hook_b -c "$PATCH" | tail -1); r2=$($P -d hook_b -c "$PATCH" | tail -1)
[ "$r1" = "t" ] && [ "$r2" = "f" ] && ok "the patch applies once (t) and a second call patches nothing (f)" || bad "patch results: $r1 $r2"
has=$($P -d hook_b -c "select position('bosCRMC' in pg_get_functiondef('public.notify_scan()'::regprocedure)) > 0"); hasa=$($P -d hook_a -c "select position('bosCRMC' in pg_get_functiondef('public.notify_scan()'::regprocedure)) > 0")
[ "$has" = "t" ] && [ "$hasa" = "f" ] && ok "marker bosCRMC in the patched copy only" || bad "marker state $has $hasa"
hk=$($P -d hook_b -c "select count(*) from jsonb_array_elements(public._i1_hooks_state()) x where (x->>'present')::boolean")
[ "$hk" = "37" ] && ok "all 37 hooks of phase 99 are still installed next to the CRM-C hook" || bad "earlier hooks: $hk"
scan="select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000c307',false); select public.notify_scan()"
sa=$($P -d hook_a -c "$scan" | tail -1); sb=$($P -d hook_b -c "$scan" | tail -1)
[ "$sa" = "$sb" ] && ok "schedule OFF (default): notify_scan answers the same with and without the hook ($sb)" || bad "answers differ: $sa | $sb"
n=$($P -d hook_b -c "select count(*) from crm_metrics_runs"); [ "$n" = "0" ] && ok "schedule OFF: no score run written" || bad "runs written while OFF: $n"
on="select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000c301',false); select set_rule('crm_metrics_schedule_on','true'::jsonb), set_rule('crm_metrics_schedule_hours','6'::jsonb)"
for db in hook_a hook_b; do $P -d $db -c "$on" >/dev/null; done
$P -d hook_a -c "$scan" >/dev/null; $P -d hook_b -c "$scan" >/dev/null
na=$($P -d hook_a -c "select count(*) from crm_metrics_runs"); nb=$($P -d hook_b -c "select count(*) from crm_metrics_runs where kind='scheduled'")
[ "$na" = "0" ] && [ "$nb" = "1" ] && ok "schedule ON: the patched copy refreshed the scores once (7 customers), the unpatched copy did nothing" || bad "runs: A $na, B $nb"
$P -d hook_b -c "$scan" >/dev/null; nb2=$($P -d hook_b -c "select count(*) from crm_metrics_runs where kind='scheduled'")
[ "$nb2" = "1" ] && ok "a second scan inside the hours writes nothing new" || bad "second scan wrote: $nb2"
$P -d hook_b -c "create or replace function public.crmc_scheduled_run() returns jsonb language plpgsql as \$f\$ begin raise exception 'test: crm failure'; end \$f\$" >/dev/null
sc=$($P -d hook_b -c "$scan" 2>&1 | tail -1)
case "$sc" in *created*) ok "a failing CRM-C function does not stop the scan";; *) bad "scan stopped: $sc";; esac
[ $fail = 0 ] && echo "RESULT hook: all pass" || echo "RESULT hook: FAILURES"
exit $fail
