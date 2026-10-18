-- Phase 493 tests (XB part 3: riders, delivery status, zones, COD deposits and reconciliation). Neutral test_* data only.  bash tests/sql/xb_run.sh phase493
\ir ../tests/sql/c2_fixture.sql

\echo == T0 shape
select tt.chk('T0 writers open to browsers; anon denied; the job and the trail are read-only; RLS on',
  has_function_privilege('authenticated', 'public.xb_delivery_assign(uuid,bigint,text,text)', 'execute')
  and has_function_privilege('authenticated', 'public.xb_cod_reconcile(date,int)', 'execute')
  and not has_function_privilege('anon', 'public.xb_delivery_assign(uuid,bigint,text,text)', 'execute')
  and not has_table_privilege('authenticated', 'public.delivery_jobs', 'update')
  and not has_table_privilege('authenticated', 'public.cod_deposits', 'insert')
  and (select relrowsecurity from pg_class where relname = 'delivery_jobs') and (select relrowsecurity from pg_class where relname = 'cod_cases'));
select tt.chk('T0 the switch is OFF, no rider, no zone, no job exist yet', not rule_on('xb_delivery_on') and not exists (select 1 from riders) and not exists (select 1 from delivery_zones) and not exists (select 1 from delivery_jobs));

\echo == T1 switch OFF: refused
select tt.as(:'p');
select (online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_rd1', '01711000300', 'test_address_1',
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 10)), 'home', null, null, 0, 0, 0, null, null, null)->>'id')::uuid as o1 \gset
select (online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_rd2', '01711000301', 'test_address_2',
        jsonb_build_array(jsonb_build_object('item_id', :'ia', 'qty', 3)), 'home', null, null, 0, 0, 0, null, null, null)->>'id')::uuid as o2 \gset
select tt.err('T1 an assignment is refused while the switch is OFF', format($q$select xb_delivery_assign(%L::uuid, 1, 'zone_near', null)$q$, :'o1'), 'module_off');

\echo == T2 owner sets up riders and zones
select tt.as(:'o');
select set_rule('xb_delivery_on', 'true');
select (xb_rider_save(null, 'test_rider_a', 'test_rider_a', 'external', null, '01711000200', 1, true)->>'id')::bigint as r1 \gset
select (xb_delivery_zone_save('zone_near', 'test_zone_near', 'test_zone_near', 60)->>'fee')::numeric = 60 as z1 \gset
select (xb_delivery_zone_save('zone_far', 'test_zone_far', 'test_zone_far', 120)->>'fee')::numeric = 120 as z2 \gset
select tt.chk('T2 a rider and two zones with fees are saved', :'r1' is not null and :'z1' and :'z2');
select tt.err('T2 a staff rider needs an employee link', $q$select xb_rider_save(null, 'test_rider_s', null, 'staff', null, null, 1, true)$q$, 'employee_required');
select tt.as(:'p');
select tt.err('T2 a salesperson cannot manage riders', $q$select xb_rider_save(null, 'test_rider_x', null, 'external', null, null, 1, true)$q$, 'not allowed');

\echo == T3 assignment
select tt.err('T3 an unknown zone is refused (no fee invented)', format($q$select xb_delivery_assign(%L::uuid, %s, 'zone_none', null)$q$, :'o1', :'r1'), 'zone_not_found_or_inactive');
select tt.err('T3 a map link must be https', format($q$select xb_delivery_assign(%L::uuid, %s, 'zone_near', 'http://maps.example.test/x')$q$, :'o1', :'r1'), 'check');
select (xb_delivery_assign(:'o1'::uuid, :'r1', 'zone_near', 'https://maps.example.test/test-point-1')->>'fee')::numeric = 60 as a1 \gset
select tt.chk('T3 the order is assigned with the zone fee and the cod amount (the balance 1000)', :'a1' and (select cod_amount = 1000 and state = 'assigned' from delivery_jobs where order_id = :'o1'::uuid));

\echo == T4 status chain: out, failed, reattempt, returned, delivered
select tt.err('T4 a job cannot go to delivered before it is out', format($q$select xb_delivery_move((select id from delivery_jobs where order_id = %L::uuid), 'delivered', null, null)$q$, :'o1'), 'bad_status');
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'out')->>'state') = 'out' as t1 \gset
select tt.err('T4 a failed delivery needs a reason', format($q$select xb_delivery_move((select id from delivery_jobs where order_id = %L::uuid), 'failed', null, null)$q$, :'o1'), 'reason_required');
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'failed', null, 'test: customer not at home')->>'state') = 'failed' as t2 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'reattempt')->>'state') = 'assigned' as t3 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'out')->>'state') = 'out' as t4 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'failed', null, 'test: phone off')->>'state') = 'failed' as t5 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'reattempt')->>'state') = 'assigned' as t6 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'out')->>'state') = 'out' as t7 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'failed', null, 'test: refused')->>'attempts')::int = 3 as t8 \gset
select tt.err('T4 a third reattempt is refused: the goods go back to the shop', format($q$select xb_delivery_move((select id from delivery_jobs where order_id = %L::uuid), 'reattempt')$q$, :'o1'), 'too_many_attempts');
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o1'::uuid), 'returned')->>'state') = 'returned' as t9 \gset
select tt.chk('T4 the chain works: out, failed, reattempt twice, failed three times, returned', :'t1' and :'t2' and :'t3' and :'t4' and :'t5' and :'t6' and :'t7' and :'t8' and :'t9');
select tt.err('T4 a returned job cannot move again', format($q$select xb_delivery_move((select id from delivery_jobs where order_id = %L::uuid), 'out')$q$, :'o1'), 'bad_status');

select (xb_delivery_assign(:'o2'::uuid, :'r1', 'zone_far', null)->>'fee')::numeric = 120 as b1 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o2'::uuid), 'out')->>'state') = 'out' as b2 \gset
select (xb_delivery_move((select id from delivery_jobs where order_id = :'o2'::uuid), 'delivered', 300, null)->>'state') = 'delivered' as b3 \gset
select tt.chk('T4 a second order goes out and is delivered with 300 collected (balance was 300)', :'b1' and :'b2' and :'b3' and (select cod_collected = 300 from delivery_jobs where order_id = :'o2'::uuid));

\echo == T5 COD deposit and reconciliation
select tt.as(:'o');
select tt.err('T5 a deposit of zero is refused', format($q$select xb_cod_deposit(null, %s, 1, tt.today(), 0, null)$q$, :'r1'), 'bad_amount');
select tt.err('T5 a deposit for a future day is refused', format($q$select xb_cod_deposit(null, %s, 1, tt.today() + 1, 5, null)$q$, :'r1'), 'bad_date');
select (xb_cod_deposit('33333333-3333-3333-3333-333333333333', :'r1', 1, tt.today(), 200, 'test: first hand-in')->>'dup')::boolean = false as d1 \gset
select (xb_cod_deposit('33333333-3333-3333-3333-333333333333', :'r1', 1, tt.today(), 200, 'test: first hand-in')->>'dup')::boolean = true as d2 \gset
select tt.chk('T5 a deposit is written once (the same client id is a duplicate)', :'d1' and :'d2' and (select count(*) from cod_deposits) = 1);
select (xb_cod_reconcile(tt.today(), 1)->'riders'->0->>'collected')::numeric = 300 as rc1 \gset
select (xb_cod_reconcile(tt.today(), 1)->'riders'->0->>'difference')::numeric = 100 as rc2 \gset
select (xb_cod_reconcile(tt.today(), 1)->'riders'->0->>'status') = 'short' as rc3 \gset
select tt.chk('T5 reconcile: 300 collected, 200 deposited, 100 short, status short', :'rc1' and :'rc2' and :'rc3');
select tt.chk('T5 one open case per rider per day, not doubled by a second reconcile', (select count(*) = 1 and bool_and(state = 'open') from cod_cases));
select (xb_cod_case_explain((select id from cod_cases limit 1), 'test: rider paid the rest next morning')->>'state') = 'explained' as ex1 \gset
select tt.err('T5 an explained case cannot be explained again', $q$select xb_cod_case_explain((select id from cod_cases limit 1), 'again again')$q$, 'already_explained');
select tt.chk('T5 the case is explained by the owner', :'ex1');

\echo == T6 rider performance
select ((xb_rider_perf(tt.today(), tt.today(), 1)->0->>'jobs')::int = 2 and (xb_rider_perf(tt.today(), tt.today(), 1)->0->>'delivered')::int = 1
        and (xb_rider_perf(tt.today(), tt.today(), 1)->0->>'returned')::int = 1) as pf \gset
select tt.chk('T6 performance: 2 jobs, 1 delivered, 1 returned for the rider', :'pf');

\echo == T7 append-only and fixed fields
select tt.err('T7 the trail cannot be deleted', $q$delete from delivery_events$q$, 'append_only');
select tt.err('T7 a deposit cannot be changed', $q$update cod_deposits set amount = 1$q$, 'append_only');
select tt.err('T7 a delivery job is never deleted', $q$delete from delivery_jobs$q$, 'nothing is deleted');
select tt.err('T7 the fee of a delivery is fixed', format($q$update delivery_jobs set fee = 1 where order_id = %L::uuid$q$, :'o2'), 'fixed');
select tt.err('T7 a delivered job cannot change its state', format($q$update delivery_jobs set state = 'out' where order_id = %L::uuid$q$, :'o2'), 'closed');

\echo == T8 no money path
select tt.chk('T8 no journal entry is written by the delivery or COD flow', (select count(*) from journal_entries where source_type like 'xb%') = 0);
