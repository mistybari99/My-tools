#!/bin/bash
# Concurrency harness helpers. Source me:  . lib.sh
# env: PGSOCK=/tmp PGPORT=5544  TPL=conc_tpl  OUT=<dir for outputs>  PGLOG=/tmp/pg5544.log
export PGHOST=${PGSOCK:-/tmp} PGPORT=${PGPORT:-5544} PGUSER=postgres
TPL=${TPL:-conc_tpl}; HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; OUT=${OUT:-$HERE/out}; PGLOG=${PGLOG:-/tmp/pg5544.log}
mkdir -p "$OUT"; RES="$OUT/results.tsv"
O=00000000-0000-0000-0000-000000000001; BU=00000000-0000-0000-0000-000000000002; FM=00000000-0000-0000-0000-000000000003
SP=00000000-0000-0000-0000-000000000004; SK=00000000-0000-0000-0000-000000000005; BT=00000000-0000-0000-0000-000000000006
RV=00000000-0000-0000-0000-000000000007; AP=00000000-0000-0000-0000-000000000008; AC=00000000-0000-0000-0000-000000000009
NIL=$(echo | head -c0)

newdb() { # newdb <name>  : clone of the seeded template
  psql -qAtX -d postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='$1' and pid<>pg_backend_pid()" >/dev/null
  psql -qAtX -d postgres -c "drop database if exists $1" -c "create database $1 template $TPL" >/dev/null 2>&1 || { echo "cannot clone $TPL"; return 1; }
}
sq() { # sq <db> <uuid> <sql...>  : run SQL as a user (mocked auth), tuples only
  local db=$1 u=$2; shift 2
  psql -qAtX -v ON_ERROR_STOP=1 -d "$db" -c "select set_config('request.jwt.claim.sub','$u',false)" -c "$*" 2>&1 | tail -n +2
}
sqf() { # sqf <db> <uuid>  (sql on stdin)
  local db=$1 u=$2; { echo "select set_config('request.jwt.claim.sub','$u',false)\\g /dev/null"; cat; } | psql -qAtX -d "$db" 2>&1
}
deadlocks() { psql -qAtX -d postgres -c "select coalesce(sum(deadlocks),0) from pg_stat_database where datname='$1'"; }
logmark() { stat -c %s "$PGLOG" 2>/dev/null || echo 0; }
logdl() { tail -c +$(( $1 + 1 )) "$PGLOG" 2>/dev/null | grep -c 'deadlock detected'; }

# race <db> <N> <user uuid> <snippet-file-or-string> <tag>
#   Starts N psql sessions, each connects, authenticates, then blocks on a shared advisory lock (barrier) held by a 'holder' session;
#   when all N are waiting the holder is killed and all N fire at once. psql vars in the snippet: :i (1..N), :'u' (user). Output -> $OUT/<tag>.<i>.out / .err
race() {
  local db=$1 n=$2 user=$3 snip=$4 tag=$5 d="$OUT/$5" i k=0
  rm -rf "$d"; mkdir -p "$d"
  if [ -f "$snip" ]; then cp "$snip" "$d/snip.sql"; else printf '%s\n' "$snip" > "$d/snip.sql"; fi
  { echo '\set ON_ERROR_STOP off'; echo '\set VERBOSITY terse'
    echo "select set_config('request.jwt.claim.sub', :'u', false) \\gset"
    echo "set role authenticated;"
    echo "select pg_advisory_lock_shared(7770001) \\gset"
    echo "select pg_advisory_unlock_shared(7770001) \\gset"
    cat "$d/snip.sql"; } > "$d/worker.sql"
  PGAPPNAME=holder psql -qAtX -d "$db" -c "select pg_advisory_lock(7770001)" -c "select pg_sleep(600)" >/dev/null 2>&1 &
  until [ "$(psql -qAtX -d "$db" -c "select count(*) from pg_locks where locktype='advisory' and objid=7770001 and granted")" = 1 ]; do sleep 0.05; done
  local pids=()
  for i in $(seq 1 "$n"); do
    PGAPPNAME=worker psql -qAtX -d "$db" -v "i=$i" -v "u=$user" -f "$d/worker.sql" > "$d/$i.out" 2> "$d/$i.err" &
    pids+=($!)
  done
  until [ "$(psql -qAtX -d "$db" -c "select count(*) from pg_locks where locktype='advisory' and objid=7770001 and not granted")" -ge "$n" ] || [ $((k++)) -gt 600 ]; do sleep 0.05; done
  psql -qAtX -d "$db" -c "select pg_terminate_backend(pid) from pg_stat_activity where application_name='holder'" >/dev/null
  wait "${pids[@]}" 2>/dev/null
  wait 2>/dev/null
}
cnt_out() { cat "$OUT/$1"/*.out 2>/dev/null | grep -c -- "$2"; }      # lines in worker output matching a pattern
cnt_err() { cat "$OUT/$1"/*.err 2>/dev/null | grep -c -- "$2"; }
errs() { cat "$OUT/$1"/*.err 2>/dev/null | sed 's/^psql:[^ ]* *//' | sort | uniq -c | sort -rn | head -${2:-6}; }

# rec <id> <name> <PASS|FAIL> <detail>
rec() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$RES"; printf '  %-5s %-4s %s  [%s]\n' "$3" "$1" "$2" "$4"; }
# ck <id> <name> <db> <boolean sql> [detail sql]   (run as owner)
ck() {
  local r d=""; r=$(sq "$3" $O "$4" | tail -1)
  [ -n "$5" ] && d=$(sq "$3" $O "$5" | tail -1)
  if [ "$r" = t ]; then rec "$1" "$2" PASS "$d"; else rec "$1" "$2" FAIL "got=$r $d"; fi
}
# standard invariants after a scenario (owner): books posted first, then compare everything
inv() { # inv <db> <id> [skip-gl]
  local db=$1 id=$2
  sq $db $O "select acct_post_pending(false)" >/dev/null; sq $db $O "select acct_post_pending(false)" >/dev/null
  ck $id.recon "stock_balance == replay of ledger (qty and avg)" $db "select count(*)=0 from stock_reconcile(false)" "select coalesce(string_agg(item_id::text||'@'||location_id||' led='||ledger_qty||' bal='||cached_qty||' avg='||coalesce(cached_avg,-1)||'/'||coalesce(replay_avg,-1),'; '),'') from stock_reconcile(false)"
  ck $id.tb "trial balance: unbalanced entries 0, debit-credit diff 0" $db "select (select count(*) from (select entry_id from journal_lines group by entry_id having sum(debit)<>sum(credit)) z)=0 and (select coalesce(sum(debit-credit),0) from journal_lines)=0"
  ck $id.dupje "one journal entry per source (je_source_uq)" $db "select count(*)=0 from (select source_type,source_id from journal_entries where reverses_id is null group by 1,2 having count(*)>1) z"
  ck $id.ap "GL supplier payable (2100) == sum of supplier balances (bills - payments)" $db "select (select coalesce(sum(l.credit-l.debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='2100')=(select coalesce(sum(_sup_balance(id)),0) from suppliers)" "select 'gl='||(select coalesce(sum(l.credit-l.debit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='2100')||' subledger='||(select coalesce(sum(_sup_balance(id)),0) from suppliers)"
  ck $id.gl "inventory_vs_gl unexplained = 0 (tolerance GLTOL, default 0.05 = rounding)" $db "select abs((inventory_vs_gl()->'total'->>'unexplained')::numeric)<${GLTOL:-0.05}" "select inventory_vs_gl()->'total'"
}
sid() { psql -qAtX -d "$1" -c "select id from suppliers where name='${2:-Sup Main}'"; }
itm() { psql -qAtX -d "$1" -c "select id from items where code='$2'"; }
# mkbill <db> <item code> <qty> <unit cost> [post]  -> prints bill id (owner, location 1, supplier Sup Main)
mkbill() {
  local b; b=$(sq "$1" $O "select save_purchase(gen_random_uuid(),null,'$(sid $1)'::uuid,1,'B-'||substr(gen_random_uuid()::text,1,6),(now() at time zone 'Asia/Dhaka')::date,'[{\"item_id\":\"$(itm $1 $2)\",\"qty\":$3,\"unit\":\"$(psql -qAtX -d $1 -c "select unit from items where code='$2'")\",\"unit_cost\":$4}]'::jsonb)->>'id'" | tail -1)
  [ "$5" = post ] && sq "$1" $O "select post_purchase('$b'::uuid)" >/dev/null
  echo "$b"
}
