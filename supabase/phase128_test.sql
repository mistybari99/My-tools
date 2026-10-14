-- FRESH DB ONLY (canonical build incl. phase127 + phase128).  Phase 128 tests = principal scheme engine.
--   psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase128_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
\i tests/sql/e2e/00_common.sql
\set hwm '00000000-0000-0000-0000-000000000201'
\set hwv '00000000-0000-0000-0000-000000000202'
\set swm '00000000-0000-0000-0000-000000000203'
\set pam '00000000-0000-0000-0000-000000000204'
\set sup1 '00000000-0000-0000-0000-00000000d001'
\set sup2 '00000000-0000-0000-0000-00000000d002'
\echo == T0 setup: sweets + HARDWARE + PAINT, principal One (also used by PAINT), purchases and sales
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@dl.app','{"full_name":"Owner"}'),(:'hwm','hwm@dl.app','{"full_name":"HwMgr"}'),(:'hwv','hwv@dl.app','{"full_name":"HwView"}'),
  (:'swm','swm@dl.app','{"full_name":"SweetsMgr"}'),(:'pam','pam@dl.app','{"full_name":"PaintMgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'hwm','salesperson'),(:'hwv','salesperson'),(:'swm','salesperson'),(:'pam','salesperson') on conflict do nothing;
select tt.as(:'o');
select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'LE-DL', 'ডিএল কোম্পানি', 'DL Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":100}'::jsonb, '00000000-0000-0000-0000-0000000002a1') ->> 'id' as dle \gset
select org_unit_save(null, :'dle'::bigint, 'business', 'HARDWARE', 'হার্ডওয়্যার', 'Hardware', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000002a2') ->> 'id' as hbz \gset
select org_unit_save(null, :'dle'::bigint, 'business', 'PAINT', 'পেইন্ট', 'Paint', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000002a3') ->> 'id' as pbz \gset
insert into locations (code, name_bn, name_en, kind, org_unit_id) values ('hw1','হার্ড ১','Hardware 1','showroom',:'hbz'::bigint),('hw2','হার্ড ২','Hardware 2','showroom',:'hbz'::bigint),('pt1','পেইন্ট ১','Paint 1','showroom',:'pbz'::bigint);
select id as h1 from locations where code='hw1' \gset
select id as h2 from locations where code='hw2' \gset
select id as p1 from locations where code='pt1' \gset
insert into user_locations values (:'hwm',:h1),(:'hwv',:h1),(:'swm',1),(:'pam',:p1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'hwm','dealer_scheme_manage',:h1),(:'hwv','dealer_scheme_view',:h1),(:'swm','dealer_scheme_manage',1),(:'pam','dealer_scheme_manage',:p1);
insert into suppliers (id, name, opening_balance) values (:'sup1','Principal One',0),(:'sup2','Principal Two',0);
select id as ia from items order by code limit 1 \gset
select id as ib from items order by code offset 1 limit 1 \gset
-- a purchase bill with lines
create or replace function tt.bill(p_sup uuid, p_date date, p_loc int, p_kind text, p_status text, p_lines jsonb) returns uuid language plpgsql as $$
declare b uuid := gen_random_uuid(); n int := 0; l jsonb; tot numeric := 0;
begin
  for l in select * from jsonb_array_elements(p_lines) loop tot := tot + (l->>'amount')::numeric; end loop;
  insert into purchase_bills (id, kind, supplier_id, bill_no, bill_date, location_id, status, subtotal, total) values (b, p_kind, p_sup, 'T' || substr(b::text,1,8), p_date, p_loc, p_status, tot, tot);
  for l in select * from jsonb_array_elements(p_lines) loop n := n + 1;
    insert into purchase_lines (bill_id, line_no, item_id, qty, unit_cost, amount) values (b, n, (l->>'item')::uuid, (l->>'qty')::numeric, (l->>'amount')::numeric / (l->>'qty')::numeric, (l->>'amount')::numeric); end loop;
  return b;
end $$;
-- stage 1: two bills totalling 100000.00 in the period; noise that must NOT count: before the period, draft, other business, other principal
select tt.bill(:'sup1', tt.today()-10, :h1, 'bill', 'posted', jsonb_build_array(jsonb_build_object('item',:'ia','qty',100,'amount',60000), jsonb_build_object('item',:'ib','qty',50,'amount',40000))) \gset
select tt.bill(:'sup1', tt.today()-60, :h1, 'bill', 'posted', jsonb_build_array(jsonb_build_object('item',:'ia','qty',9,'amount',99999))) \gset
select tt.bill(:'sup1', tt.today()-5, :h1, 'bill', 'draft', jsonb_build_array(jsonb_build_object('item',:'ia','qty',7,'amount',77777))) \gset
select tt.bill(:'sup1', tt.today()-5, :p1, 'bill', 'posted', jsonb_build_array(jsonb_build_object('item',:'ia','qty',5,'amount',55555))) \gset
select tt.bill(:'sup2', tt.today()-5, :h1, 'bill', 'posted', jsonb_build_array(jsonb_build_object('item',:'ia','qty',4,'amount',44444))) \gset
select tt.t('T0 tables exist with RLS, no browser write, anon none', (select count(*)=6 and bool_and(relrowsecurity) from pg_class where oid in ('public.dealer_schemes'::regclass,'public.dealer_scheme_items'::regclass,'public.dealer_scheme_slabs'::regclass,'public.dealer_scheme_accruals'::regclass,'public.dealer_scheme_claims'::regclass,'public.dealer_scheme_claim_events'::regclass))
  and not has_table_privilege('authenticated','public.dealer_schemes','insert') and not has_table_privilege('authenticated','public.dealer_scheme_accruals','insert') and not has_table_privilege('anon','public.dealer_schemes','select'));
select tt.t('T0 rule dealer_scheme_on exists, OFF', (select kind='switch' and default_value='false'::jsonb from rules where key='dealer_scheme_on') and not rule_on('dealer_scheme_on'));
select tt.t('T0 grants', (select count(*)=2 from grant_defs where grant_code in ('dealer_scheme_view','dealer_scheme_manage')));
select tt.t('T0 helpers closed to the browser', not has_function_privilege('authenticated','public._scheme_calc128(uuid,date)','execute') and not has_function_privilege('anon','public.scheme_save(uuid,uuid,bigint,uuid,text,text,text,text,date,date,jsonb,uuid[],jsonb,text)','execute'));
create temp table k0 as select (select md5(acct_trial_balance(null, null)::text)) tb, (select count(*) from stock_ledger) sl, (select count(*) from sale_payments) sp;

\echo == T1 flag OFF refuses writes
select tt.as(:'hwm');
select tt.err('T1 scheme_save refused while off', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'S', 'slab','purchase','value', tt.today()-30, tt.today()+30, '{}', '{}', '[{"from":0,"to":null,"rate":1}]')$q$, :'hbz', :'sup1'), 'feature_off');
select tt.as(:'o'); update rules set value='true'::jsonb where key='dealer_scheme_on';

\echo == T2 set-up: slab scheme (whole), validation, idempotency
select tt.as(:'hwm');
create temp table sl as select '[{"from":0,"to":50000,"rate":1},{"from":50000,"to":100000,"rate":2},{"from":100000,"to":null,"rate":3}]'::jsonb j;
grant select on sl to authenticated;
select scheme_save(null, '00000000-0000-0000-0000-000000000a01', :'hbz'::bigint, :'sup1', 'Quarterly slab', 'slab','purchase','value', tt.today()-30, tt.today()+30, '{}'::jsonb, '{}'::uuid[], (select j from sl), 'principal slab') ->> 'id' as s1 \gset
select scheme_save(null, '00000000-0000-0000-0000-000000000a01', :'hbz'::bigint, :'sup1', 'Quarterly slab', 'slab','purchase','value', tt.today()-30, tt.today()+30, '{}'::jsonb, '{}'::uuid[], (select j from sl), 'principal slab') as again \gset
select tt.t('T2 same key again: dup, same id, one scheme', (:'again'::jsonb->>'dup')::boolean and :'again'::jsonb->>'id' = :'s1' and (select count(*)=1 from dealer_schemes));
select tt.is('T2 starts as draft, three slabs stored', 'draft|3', (select status || '|' || (select count(*) from dealer_scheme_slabs where scheme_id = s.id) from dealer_schemes s where s.id = :'s1'::uuid));
select tt.err('T2 overlapping slabs refused', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'X', 'slab','purchase','value', tt.today(), tt.today()+10, '{}', '{}', '[{"from":0,"to":100,"rate":1},{"from":50,"to":null,"rate":2}]')$q$, :'hbz', :'sup1'), 'slab_overlap');
select tt.err('T2 rate above 100 refused', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'X', 'slab','purchase','value', tt.today(), tt.today()+10, '{}', '{}', '[{"from":0,"to":null,"rate":101}]')$q$, :'hbz', :'sup1'), 'bad_slab');
select tt.err('T2 a slab scheme without slabs refused', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'X', 'slab','purchase','value', tt.today(), tt.today()+10, '{}', '{}', '[]')$q$, :'hbz', :'sup1'), 'slabs_required');
select tt.err('T2 target needs a target and a rebate', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'X', 'target','purchase','value', tt.today(), tt.today()+10, '{"target_amount":1000}', '{}', '[]')$q$, :'hbz', :'sup1'), 'target_needs_amount_and_rebate');
select tt.err('T2 flat per pack needs qty measure', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'X', 'flat_pack','purchase','value', tt.today(), tt.today()+10, '{"per_pack_amount":5}', '{}', '[]')$q$, :'hbz', :'sup1'), 'bad_measure');
select tt.err('T2 period backwards refused', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'X', 'slab','purchase','value', tt.today(), tt.today()-1, '{}', '{}', '[{"from":0,"to":null,"rate":1}]')$q$, :'hbz', :'sup1'), 'bad_period');
select tt.err('T2 unknown principal refused', format($q$select scheme_save(null, gen_random_uuid(), %s, gen_random_uuid(), 'X', 'slab','purchase','value', tt.today(), tt.today()+10, '{}', '{}', '[{"from":0,"to":null,"rate":1}]')$q$, :'hbz'), 'supplier_not_found');
select tt.err('T2 not accruable while draft (real run)', format($q$select scheme_accrue(%L::uuid, null, false, gen_random_uuid())$q$, :'s1'), 'bad_status');
select scheme_activate(:'s1'::uuid) as act \gset
select tt.is('T2 activated', 'active', (select status from dealer_schemes where id = :'s1'::uuid));
select tt.err('T2 an active scheme is frozen (edit refused)', format($q$select scheme_save(%L::uuid, null, %s, %L, 'Changed', 'slab','purchase','value', tt.today()-30, tt.today()+30, '{}', '{}', '[{"from":0,"to":null,"rate":9}]')$q$, :'s1', :'hbz', :'sup1'), 'scheme_frozen');

\echo == T3 preview then accrue: hand-computed numbers
select scheme_accrue(:'s1'::uuid, null, true) as pv \gset
select tt.eq('T3 preview base value 100000.00 (noise excluded: old, draft, other business, other principal)', 100000, (:'pv'::jsonb->>'base_value')::numeric);
select tt.eq('T3 preview base qty 150', 150, (:'pv'::jsonb->>'base_qty')::numeric);
select tt.eq('T3 preview earned 3% x 100000 = 3000.00', 3000, (:'pv'::jsonb->>'earned')::numeric);
select tt.eq('T3 the preview wrote nothing', 0, (select count(*) from dealer_scheme_accruals));
select scheme_accrue(:'s1'::uuid, null, false, '00000000-0000-0000-0000-000000000b01') as a1 \gset
select tt.eq('T3 accrual 1 delta 3000.00', 3000, (:'a1'::jsonb->>'delta')::numeric);
select scheme_accrue(:'s1'::uuid, null, false, '00000000-0000-0000-0000-000000000b01') as a1b \gset
select tt.t('T3 same key again: dup, still one accrual row', (:'a1b'::jsonb->>'dup')::boolean and (select count(*)=1 from dealer_scheme_accruals));
select scheme_accrue(:'s1'::uuid, null, false, '00000000-0000-0000-0000-000000000b02') as a1c \gset
select tt.t('T3 a new key with no new data accrues nothing (paste twice safe)', (:'a1c'::jsonb->>'nothing_new')::boolean and (select count(*)=1 from dealer_scheme_accruals));
-- stage 2: +12000.50 bill, -6000 return => 106000.50 ; whole 3% = 3180.015 -> 3180.02 ; delta 180.02
reset role;
select tt.bill(:'sup1', tt.today()-3, :h2, 'bill', 'posted', jsonb_build_array(jsonb_build_object('item',:'ia','qty',20,'amount',12000.50))) \gset
select tt.bill(:'sup1', tt.today()-2, :h1, 'return', 'posted', jsonb_build_array(jsonb_build_object('item',:'ia','qty',10,'amount',6000))) \gset
select tt.as(:'hwm');
select scheme_accrue(:'s1'::uuid, null, true) as pv2 \gset
select tt.eq('T3 stage 2 base 106000.50 (second HARDWARE location counted, return netted)', 106000.50, (:'pv2'::jsonb->>'base_value')::numeric);
select tt.eq('T3 stage 2 earned 3180.015 rounds to 3180.02', 3180.02, (:'pv2'::jsonb->>'earned')::numeric);
select tt.eq('T3 stage 2 delta = 3180.02 - 3000.00 = 180.02', 180.02, (:'pv2'::jsonb->>'delta')::numeric);
select scheme_accrue(:'s1'::uuid, null, false, '00000000-0000-0000-0000-000000000b03') as a2 \gset
select tt.eq('T3 accrued total now 3180.02', 3180.02, (select sum(delta) from dealer_scheme_accruals where scheme_id = :'s1'::uuid));
select tt.eq('T3 an accrual up to a date BEFORE the stage-2 bills sees only stage 1 (3000.00)', 3000, (scheme_accrue(:'s1'::uuid, tt.today()-8, true)->>'earned')::numeric);
select tt.err('T3 accrual date in the future refused', format($q$select scheme_accrue(%L::uuid, tt.today()+1, true)$q$, :'s1'), 'bad_date');
reset role;
select tt.err('T3 accrual rows cannot be edited', $$update dealer_scheme_accruals set delta = 1$$, 'append_only');
select tt.as(:'hwm');

\echo == T4 the other kinds: marginal slab, target, flat per pack, sale basis
select scheme_save(null, gen_random_uuid(), :'hbz'::bigint, :'sup1', 'Marginal', 'slab','purchase','value', tt.today()-30, tt.today()+30, '{"slab_mode":"marginal"}'::jsonb, '{}'::uuid[], (select j from sl)) ->> 'id' as s2 \gset
select tt.eq('T4 marginal: 1% x 50000 + 2% x 50000 + 3% x 6000.50 = 1680.015 -> 1680.02', 1680.02, (scheme_accrue(:'s2'::uuid, null, true)->>'earned')::numeric);
select scheme_save(null, gen_random_uuid(), :'hbz'::bigint, :'sup1', 'Target reached', 'target','purchase','value', tt.today()-30, tt.today()+30, '{"target_amount":100000,"rebate_pct":1.5,"rebate_flat":250}'::jsonb, '{}'::uuid[], '[]') ->> 'id' as s3 \gset
select tt.eq('T4 target reached: 1.5% x 106000.50 + 250 = 1840.0075 -> 1840.01', 1840.01, (scheme_accrue(:'s3'::uuid, null, true)->>'earned')::numeric);
select scheme_save(null, gen_random_uuid(), :'hbz'::bigint, :'sup1', 'Target missed', 'target','purchase','value', tt.today()-30, tt.today()+30, '{"target_amount":200000,"rebate_pct":5}'::jsonb, '{}'::uuid[], '[]') ->> 'id' as s4 \gset
select tt.eq('T4 target missed: 0', 0, (scheme_accrue(:'s4'::uuid, null, true)->>'earned')::numeric);
select scheme_save(null, gen_random_uuid(), :'hbz'::bigint, :'sup1', 'Per pack', 'flat_pack','purchase','qty', tt.today()-30, tt.today()+30, '{"per_pack_amount":12.5}'::jsonb, '{}'::uuid[], '[]') ->> 'id' as s5 \gset
select tt.eq('T4 flat per pack: 12.50 x (100+50+20-10 = 160) = 2000.00', 2000, (scheme_accrue(:'s5'::uuid, null, true)->>'earned')::numeric);
select scheme_save(null, gen_random_uuid(), :'hbz'::bigint, :'sup1', 'Per pack item A', 'flat_pack','purchase','qty', tt.today()-30, tt.today()+30, '{"per_pack_amount":12.5}'::jsonb, array[:'ia'::uuid], '[]') ->> 'id' as s6 \gset
select tt.eq('T4 with an item scope (A only): 12.50 x (100+20-10 = 110) = 1375.00', 1375, (scheme_accrue(:'s6'::uuid, null, true)->>'earned')::numeric);
select scheme_save(null, gen_random_uuid(), :'hbz'::bigint, :'sup1', 'Sale basis none', 'flat_pack','sale','qty', tt.today()-30, tt.today()+30, '{"per_pack_amount":20}'::jsonb, '{}'::uuid[], '[]') ->> 'id' as s8 \gset
select tt.err('T4 a sale-based scheme without items cannot be activated', format($q$select scheme_activate(%L::uuid)$q$, :'s8'), 'sale_scheme_needs_items');
select scheme_save(null, gen_random_uuid(), :'hbz'::bigint, :'sup1', 'Sale basis A', 'flat_pack','sale','qty', tt.today()-30, tt.today()+30, '{"per_pack_amount":20}'::jsonb, array[:'ia'::uuid], '[]') ->> 'id' as s7 \gset
reset role;
insert into sales (location_id, receipt, sale_date, lines, subtotal, total, pay_mode, created_by, status) values
  (:h1, 901, tt.today()-4, jsonb_build_array(jsonb_build_object('item_id',:'ia','qty',3,'price',500,'amount',1500), jsonb_build_object('item_id',:'ib','qty',9,'price',10,'amount',90)), 1590, 1590, 'cash', :'o', 'done'),
  (:h2, 902, tt.today()-3, jsonb_build_array(jsonb_build_object('item_id',:'ia','qty',2,'price',500,'amount',1000)), 1000, 1000, 'cash', :'o', 'done'),
  (:h1, 903, tt.today()-3, jsonb_build_array(jsonb_build_object('item_id',:'ia','qty',100,'price',500,'amount',50000)), 50000, 50000, 'cash', :'o', 'void'),
  (:p1, 904, tt.today()-3, jsonb_build_array(jsonb_build_object('item_id',:'ia','qty',50,'price',500,'amount',25000)), 25000, 25000, 'cash', :'o', 'done'),
  (:h1, 905, tt.today()-90, jsonb_build_array(jsonb_build_object('item_id',:'ia','qty',40,'price',500,'amount',20000)), 20000, 20000, 'cash', :'o', 'done');
select tt.as(:'hwm');
select tt.eq('T4 sale basis: item A qty 3 + 2 = 5 (void, other business and old sales excluded) x 20 = 100.00', 100, (scheme_accrue(:'s7'::uuid, null, true)->>'earned')::numeric);
select tt.eq('T4 sale basis base value 2500.00', 2500, (scheme_accrue(:'s7'::uuid, null, true)->>'base_value')::numeric);

\echo == T5 claims: never above the unclaimed accrual; receipts; reject; reconciliation
select claim_create('00000000-0000-0000-0000-000000000c01', :'s1'::uuid, 'CL-1', tt.today(), 2000, 'first part') as cl1 \gset
select claim_create('00000000-0000-0000-0000-000000000c01', :'s1'::uuid, 'CL-1', tt.today(), 2000, 'first part') as cl1b \gset
select tt.t('T5 claim 1 created; same key again is a dup', (:'cl1b'::jsonb->>'dup')::boolean and (select count(*)=1 from dealer_scheme_claims));
select tt.eq('T5 unclaimed after claim 1 = 3180.02 - 2000 = 1180.02', 1180.02, (:'cl1'::jsonb->>'unclaimed_after')::numeric);
select claim_create('00000000-0000-0000-0000-000000000c02', :'s1'::uuid, 'CL-2', tt.today(), 1180.02, 'rest') as cl2 \gset
select tt.err('T5 one paisa more than accrued is refused (exceeds_accrual)', format($q$select claim_create(gen_random_uuid(), %L::uuid, 'CL-3', tt.today(), 0.01)$q$, :'s1'), 'exceeds_accrual');
select claim_reject((:'cl2'::jsonb->>'id')::uuid, '00000000-0000-0000-0000-000000000c12', 'principal disputes the period') as rj \gset
select claim_reject((:'cl2'::jsonb->>'id')::uuid, '00000000-0000-0000-0000-000000000c12', 'principal disputes the period') as rj2 \gset
select tt.t('T5 claim 2 rejected (repeat with the same key = dup)', (select status = 'rejected' from dealer_scheme_claims where claim_no = 'CL-2') and (:'rj2'::jsonb->>'dup')::boolean);
select claim_receive((:'cl1'::jsonb->>'id')::uuid, '00000000-0000-0000-0000-000000000c21', 1500, tt.today(), 'CR-77') as rc1 \gset
select tt.is('T5 receipt 1500 of 2000: part_settled, outstanding 500', 'part_settled|500.00', (:'rc1'::jsonb->>'status') || '|' || to_char((:'rc1'::jsonb->>'outstanding')::numeric, 'FM999990.00'));
select claim_receive((:'cl1'::jsonb->>'id')::uuid, '00000000-0000-0000-0000-000000000c21', 1500, tt.today(), 'CR-77') as rc1b \gset
select tt.t('T5 same receipt key again: dup, received once', (:'rc1b'::jsonb->>'dup')::boolean and (select sum(amount) = 1500 from dealer_scheme_claim_events where kind = 'received'));
select tt.err('T5 receiving more than outstanding refused', format($q$select claim_receive(%L::uuid, gen_random_uuid(), 500.01, tt.today())$q$, :'cl1'::jsonb->>'id'), 'overpaid');
select claim_receive((:'cl1'::jsonb->>'id')::uuid, '00000000-0000-0000-0000-000000000c22', 500, tt.today(), 'CR-78') as rc2 \gset
select tt.is('T5 settled', 'settled', (select status from dealer_scheme_claims where claim_no = 'CL-1'));
select tt.err('T5 a settled claim cannot be rejected', format($q$select claim_reject(%L::uuid, gen_random_uuid(), 'x')$q$, :'cl1'::jsonb->>'id'), 'bad_status');
select tt.eq('T5 reconciliation: accrued 3180.02', 3180.02, (select accrued from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select tt.eq('T5 ... claimed (active claims only) 2000.00', 2000, (select claimed from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select tt.eq('T5 ... outstanding 0 (received 2000)', 0, (select outstanding from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select tt.eq('T5 ... received 2000.00', 2000, (select received from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select tt.eq('T5 ... unclaimed 1180.02 (the rejected claim freed its amount)', 1180.02, (select unclaimed from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select tt.eq('T5 ... rejected total 1180.02', 1180.02, (select rejected from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select tt.eq('T5 claim_list shows 2 claims for the principal', 2, (select count(*) from claim_list(:'hbz'::bigint, :'sup1')));
select tt.eq('T5 scheme_list totals agree (accrued 3180.02 + claimed 2000 + received 2000)', 3180.02 + 2000 + 2000, (select accrued + claimed + received from scheme_list(:'hbz'::bigint) where id = :'s1'::uuid));
-- a purchase return AFTER accrual lowers the earned amount: negative delta, over_claimed shows when claims exceed accrual
reset role;
select tt.bill(:'sup1', tt.today()-1, :h1, 'return', 'posted', jsonb_build_array(jsonb_build_object('item',:'ia','qty',60,'amount',40000))) \gset
select tt.as(:'hwm');
select tt.eq('T5 after a 40000 return: base 66000.50 -> whole slab 2% = 1320.01 ; delta -1860.01', -1860.01, (scheme_accrue(:'s1'::uuid, null, true)->>'delta')::numeric);
select scheme_accrue(:'s1'::uuid, null, false, '00000000-0000-0000-0000-000000000b04') as a4 \gset
select tt.eq('T5 negative accrual recorded; accrued total 1320.01', 1320.01, (select sum(delta) from dealer_scheme_accruals where scheme_id = :'s1'::uuid));
select tt.eq('T5 reconciliation shows over_claimed 679.99 (claimed 2000 > accrued 1320.01)', 679.99, (select over_claimed from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select scheme_close(:'s1'::uuid, '00000000-0000-0000-0000-000000000d01') as cls \gset
select tt.is('T5 closed', 'closed', (select status from dealer_schemes where id = :'s1'::uuid));
select tt.err('T5 a closed scheme takes no more accruals', format($q$select scheme_accrue(%L::uuid, null, false, gen_random_uuid())$q$, :'s1'), 'bad_status');
select tt.err('T5 a closed scheme cannot be cancelled', format($q$select scheme_cancel(%L::uuid, 'x')$q$, :'s1'), 'bad_status');

\echo == T6 two businesses isolated, owner sees both
select tt.as(:'pam');
select scheme_save(null, gen_random_uuid(), :'pbz'::bigint, :'sup1', 'Paint target', 'target','purchase','value', tt.today()-30, tt.today()+30, '{"target_amount":50000,"rebate_pct":2}'::jsonb, '{}'::uuid[], '[]') ->> 'id' as ps \gset
select scheme_activate(:'ps'::uuid) as x \gset
select tt.eq('T6 PAINT sees only its own scheme', 1, (select count(*) from scheme_list(:'pbz'::bigint)));
select tt.err('T6 PAINT cannot list HARDWARE schemes', format($q$select * from scheme_list(%s)$q$, :'hbz'), 'not allowed');
select tt.err('T6 PAINT cannot preview a HARDWARE scheme', format($q$select scheme_accrue(%L::uuid, null, true)$q$, :'s2'), 'not allowed');
select tt.err('T6 PAINT cannot create a scheme in HARDWARE', format($q$select scheme_save(null, gen_random_uuid(), %s, %L, 'X', 'target','purchase','value', tt.today(), tt.today()+10, '{"target_amount":5,"rebate_pct":1}', '{}', '[]')$q$, :'hbz', :'sup1'), 'not allowed');
select tt.err('T6 PAINT cannot read a HARDWARE claim list', format($q$select * from claim_list(%s)$q$, :'hbz'), 'not allowed');
select tt.eq('T6 PAINT base = its own 55555.00 only (HARDWARE purchases excluded): 2% = 1111.10', 1111.10, (scheme_accrue(:'ps'::uuid, null, true)->>'earned')::numeric);
select tt.as(:'swm');
select tt.err('T6 a sweets user with the manage grant is refused in HARDWARE', format($q$select * from scheme_list(%s)$q$, :'hbz'), 'not allowed');
select tt.as(:'hwv');
select tt.t('T6 view-only user lists HARDWARE schemes', (select count(*) from scheme_list(:'hbz'::bigint)) >= 7);
select tt.eq('T6 ... and reads the reconciliation', 1, (select count(*) from scheme_reconciliation(:'hbz'::bigint) where scheme_id = :'s1'::uuid));
select tt.err('T6 ... but cannot accrue for real', format($q$select scheme_accrue(%L::uuid, null, false, gen_random_uuid())$q$, :'s5'), 'not allowed');
select tt.t('T6 ... a dry-run preview is allowed (writes nothing)', (scheme_accrue(:'s5'::uuid, null, true)->>'dry')::boolean);
select tt.err('T6 ... cannot create a claim', format($q$select claim_create(gen_random_uuid(), %L::uuid, 'Z', tt.today(), 1)$q$, :'s1'), 'not allowed');
select tt.as(:'hwm'); set role authenticated;
select tt.t('T6 RLS: direct reads show only HARDWARE rows', (select count(*) > 0 and bool_and(business_id = :'hbz'::bigint) from dealer_schemes) and (select bool_and(business_id = :'hbz'::bigint) from dealer_scheme_accruals));
select tt.err('T6 no direct write', $$update dealer_schemes set name = 'x'$$, 'permission denied');
reset role; select tt.as(:'o'); set role authenticated;
select tt.eq('T6 owner reads both businesses directly', 2, (select count(distinct business_id) from dealer_schemes));
reset role;
select tt.eq('T6 owner reconciliation PAINT', 1, (select count(*) from scheme_reconciliation(:'pbz'::bigint)));
select tt.eq('T6 owner accrues in PAINT for real (1111.10)', 1111.10, (scheme_accrue(:'ps'::uuid, null, false, gen_random_uuid())->>'delta')::numeric);
select tt.err('T6 a PAINT claim above the PAINT accrual (1111.11) is refused', format($q$select claim_create(gen_random_uuid(), %L::uuid, 'PC2', tt.today(), 1111.11)$q$, :'ps'), 'exceeds_accrual');

\echo == T7 flag OFF again, period lock, paste twice, sweets untouched
update rules set value='false'::jsonb where key='dealer_scheme_on'; select tt.as(:'hwm');
select tt.err('T7 flag off: claim refused', format($q$select claim_create(gen_random_uuid(), %L::uuid, 'Q', tt.today(), 1)$q$, :'ps'), 'not allowed');
select tt.as(:'o');
select tt.err('T7 flag off: owner real accrual refused', format($q$select scheme_accrue(%L::uuid, null, false, gen_random_uuid())$q$, :'s5'), 'feature_off');
select tt.t('T7 flag off: preview still works', (scheme_accrue(:'s5'::uuid, null, true)->>'earned')::numeric = 1250);   -- 12.50 x (160 - 60 returned)
update rules set value='true'::jsonb where key='dealer_scheme_on';
select scheme_activate(:'s5'::uuid) as x \gset
select set_rule('period_closed_until', to_jsonb(tt.today()::text));
select tt.as(:'hwm');
select tt.err('T7 closed period: real accrual refused for a staff user (period_closed)', format($q$select scheme_accrue(%L::uuid, null, false, gen_random_uuid())$q$, :'s5'), 'period_closed');
select tt.as(:'o'); select set_rule('period_closed_until', 'null'::jsonb);
create temp table cnt1 as select (select count(*) from dealer_schemes) a, (select count(*) from dealer_scheme_accruals) b, (select count(*) from dealer_scheme_claims) c, (select count(*) from dealer_scheme_claim_events) d,
  (select count(*) from grant_defs) g, (select count(*) from rules) r;
reset role;
\i supabase/phase128.sql
select tt.t('T7 second paste: nothing added or lost', (select a = (select count(*) from dealer_schemes) and b = (select count(*) from dealer_scheme_accruals) and c = (select count(*) from dealer_scheme_claims) and d = (select count(*) from dealer_scheme_claim_events)
  and g = (select count(*) from grant_defs) and r = (select count(*) from rules) from cnt1));
select tt.t('T7 no existing function was changed to use the scheme tables', not exists (select 1 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname !~ 'scheme|claim_|_dl_' and p.prosrc ~* 'dealer_scheme'));
select tt.eq('T7 no stock or payment effect of the scheme engine', 0, ((select count(*) from stock_ledger) - (select sl from k0)) + ((select count(*) from sale_payments) - (select sp from k0)));
select tt.t('T7 trial balance untouched', (select tb = md5(acct_trial_balance(null, null)::text) from k0));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
