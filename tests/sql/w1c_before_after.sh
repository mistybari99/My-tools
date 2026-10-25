#!/bin/bash
# Package W1-C proof (U-03 and U-04): nothing changes for an existing install until the owner changes a setting.
#   1. copy a fresh DB through phase 87 twice (A gets the phases, B is the twin that never does), load the p87 fixture on both, snapshot A "before"
#   2. paste phase 90 and phase 91 on A, snapshot "after" (P&L, balance sheet, trial balance, cash flow, day book, day book vs journal, journal lines, balance check, posting dry run): identical
#   3. apply the two hooks of docs/integration/W1-C.md on A (employee_status_set, sale_return, void_sale_return) with every new setting at its default
#   4. a second wave of records on A and on B: an exit status change and a tracked sale with a full return: reports, stock movements and the person's login must be identical
# usage: bash tests/sql/w1c_before_after.sh      (local throwaway Postgres on PORT, default 5563; the base DB BASE must exist: a fresh build through phase 87)
PORT=${PORT:-5563}; BASE=${BASE:-w1c_base87}; R=$(cd "$(dirname "$0")/../.." && pwd); T=$R/tests/sql
P="psql -h /tmp -p $PORT -U postgres -qAt -v ON_ERROR_STOP=1"
fail=0; HK=$(mktemp); W2=$(mktemp)
for db in w1c_ba_a w1c_ba_b; do psql -h /tmp -p $PORT -U postgres -q -c "drop database if exists $db" -c "create database $db template $BASE" 2>&1 | grep -v NOTICE; done
for db in w1c_ba_a w1c_ba_b; do $P -d $db -f $T/p87_fixture.sql >/dev/null || { echo "FAIL fixture $db"; exit 1; }; done
$P -d w1c_ba_a -v label=before -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot before"; exit 1; }
$P -d w1c_ba_a -f $R/supabase/phase90.sql >/dev/null 2>&1 || { echo "FAIL phase90 paste"; exit 1; }
$P -d w1c_ba_a -f $R/supabase/phase91.sql >/dev/null 2>&1 || { echo "FAIL phase91 paste"; exit 1; }
$P -d w1c_ba_a -f $R/supabase/phase90.sql >/dev/null 2>&1 || { echo "FAIL phase90 second paste"; exit 1; }
$P -d w1c_ba_a -f $R/supabase/phase91.sql >/dev/null 2>&1 || { echo "FAIL phase91 second paste"; exit 1; }
$P -d w1c_ba_a -v label=after -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot after"; exit 1; }
n=$($P -d w1c_ba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val")
tot=$($P -d w1c_ba_a -c "select count(*) from tt.snap where label='before'")
echo "PASS-OR-FAIL before/after phases 90+91 pasted twice: $tot snapshots compared, $n differ"
[ "$n" = "0" ] || { fail=1; $P -d w1c_ba_a -c "select a.name from tt.snap b join tt.snap a on a.name=b.name and a.label='after' where b.label='before' and a.val is distinct from b.val"; }
# hooks (the exact text of docs/integration/W1-C.md)
cat > $HK <<'EOS'
select _w1c_patch('public.employee_status_set(uuid,text,date,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', e.id, ''status'', p_status);', E'  perform public._w1c_exit_apply(e.id, e.status, p_status, p_date, v_reason); /* bos90 */\n  return jsonb_build_object(''id'', e.id, ''status'', p_status);'], 'bos90');
select _w1c_patch('public.sale_return(uuid,uuid,jsonb,text,text,text,text,text)'::regprocedure, array[
  E'  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);', E'  perform public._w1c_return_hook(rid); /* bos91 */\n  return jsonb_build_object(''id'', rid, ''amount'', amt, ''credit'', credit, ''refund'', refund);'], 'bos91');
select _w1c_patch('public.void_sale_return(uuid,text)'::regprocedure, array[
  E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;', E'  if r.status = ''void'' then return jsonb_build_object(''dup'', true, ''status'', ''void''); end if;\n  perform public._w1c_return_void_guard(p_id); /* bos91 */'], 'bos91');
EOS
$P -d w1c_ba_a -f $HK >/dev/null || { echo "FAIL hooks"; exit 1; }
$P -d w1c_ba_a -v label=hooked -f $T/p87_snap.sql >/dev/null || { echo "FAIL snapshot hooked"; exit 1; }
n=$($P -d w1c_ba_a -c "select count(*) from tt.snap b join tt.snap a on a.name=b.name and a.label='hooked' where b.label='before' and a.val is distinct from b.val")
echo "PASS-OR-FAIL before/after with the three hooks applied: $n differ"; [ "$n" = "0" ] || fail=1
# second wave on both twins
cat > $W2 <<'EOS'
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000987',false);
update items set unit='kg', base_unit='kg', tracked=true, sell_price=100 where code='I-001';
select id as it1 from items where code='I-001' \gset
select stock_opening(:'it1'::uuid, 1, 30, 40) is not null as w2a;
select record_sale2(gen_random_uuid(), 1, jsonb_build_array(jsonb_build_object('item_id', :'it1', 'qty', 5, 'price', 100, 'unit', 'kg')), 0, '[{"mode":"cash","amount":500}]', null, null, 'retail', null, false) ->> 'id' as w2sale \gset
select sale_return(gen_random_uuid(), :'w2sale'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'it1', 'qty', 5)), 'damaged', null, 'cash') is not null as w2ret;
select record_sale2(gen_random_uuid(), 1, jsonb_build_array(jsonb_build_object('item_id', :'it1', 'qty', 2, 'price', 100, 'unit', 'kg')), 0, '[{"mode":"cash","amount":200}]', null, null, 'retail', null, false) ->> 'id' as w2sale2 \gset
select sale_return(gen_random_uuid(), :'w2sale2'::uuid, jsonb_build_array(jsonb_build_object('item_id', :'it1', 'qty', 1)), 'damaged', null, 'cash') is not null as w2ret2;
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TESTBA_B','test_emp_ba_b','active',1) returning id) select id as eb from x \gset
select employee_status_set(:'eb'::uuid, 'resigned', (now() at time zone 'Asia/Dhaka')::date, 'test leaving') ->> 'status' as w2st;
select acct_post_pending(false) ->> 'posted' as w2post;
EOS
for db in w1c_ba_a w1c_ba_b; do $P -d $db -f $W2 >/dev/null || { echo "FAIL wave2 $db"; fail=1; }; done
$P -d w1c_ba_a -v label=wave2 -f $T/p87_snap.sql >/dev/null; $P -d w1c_ba_b -v label=wave2 -f $T/p87_snap.sql >/dev/null
for nm in p27_pl_all income_statement balance_sheet trial_balance cash_flow day_book_p1 day_book_totals_p1 day_book_all journal_lines; do
  a=$($P -d w1c_ba_a -c "select md5(val) from tt.snap where label='wave2' and name='$nm'"); b=$($P -d w1c_ba_b -c "select md5(val) from tt.snap where label='wave2' and name='$nm'")
  if [ "$a" = "$b" ]; then echo "PASS wave2 $nm: with phases 90+91 and hooks = without"; else echo "FAIL wave2 $nm differs"; fail=1; fi
done
SIG="select md5(string_agg(reason || ':' || qty_delta::text || ':' || coalesce(unit_cost, 0)::text, ',' order by id)) from stock_ledger where item_id=(select id from items where code='I-001')"
a=$($P -d w1c_ba_a -c "$SIG"); b=$($P -d w1c_ba_b -c "$SIG")
if [ "$a" = "$b" ]; then echo "PASS wave2 stock ledger movements identical"; else echo "FAIL wave2 stock ledger differs"; fail=1; fi
a=$($P -d w1c_ba_a -c "select count(*) from stock_wastage"); b=$($P -d w1c_ba_b -c "select count(*) from stock_wastage")
if [ "$a" = "$b" ]; then echo "PASS wave2 wastage rows identical ($a)"; else echo "FAIL wave2 wastage rows differ"; fail=1; fi
a=$($P -d w1c_ba_a -c "select count(*) from profiles where status <> 'active'"); b=$($P -d w1c_ba_b -c "select count(*) from profiles where status <> 'active'")
if [ "$a" = "$b" ]; then echo "PASS wave2 no login touched by the exit status change ($a)"; else echo "FAIL wave2 logins differ"; fail=1; fi
a=$($P -d w1c_ba_a -c "select count(*) from w1c_exit_log"); echo "exit log rows on A (must be 0 with mode off): $a"; [ "$a" = "0" ] || fail=1
[ $fail = 0 ] && echo "RESULT before/after: all equal" || echo "RESULT before/after: DIFFERENCES"
rm -f $HK $W2
exit $fail
