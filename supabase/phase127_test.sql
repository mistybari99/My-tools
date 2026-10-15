-- FRESH DB ONLY (canonical build incl. phase127).  Phase 127 tests = dealer cheque / PDC register.
--   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase127_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
\i tests/sql/e2e/00_common.sql
\set hwm '00000000-0000-0000-0000-000000000101'
\set hwv '00000000-0000-0000-0000-000000000102'
\set swm '00000000-0000-0000-0000-000000000103'
\set pam '00000000-0000-0000-0000-000000000104'
\echo == T0 setup: sweets (loc 1) + business HARDWARE (2 locations) + business PAINT (1 location)
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@dl.app','{"full_name":"Owner"}'),(:'hwm','hwm@dl.app','{"full_name":"HwMgr"}'),(:'hwv','hwv@dl.app','{"full_name":"HwView"}'),
  (:'swm','swm@dl.app','{"full_name":"SweetsMgr"}'),(:'pam','pam@dl.app','{"full_name":"PaintMgr"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'hwm','salesperson'),(:'hwv','salesperson'),(:'swm','salesperson'),(:'pam','salesperson') on conflict do nothing;
select tt.as(:'o');
select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'LE-DL', 'ডিএল কোম্পানি', 'DL Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":100}'::jsonb, '00000000-0000-0000-0000-0000000001a1') ->> 'id' as dle \gset
select org_unit_save(null, :'dle'::bigint, 'business', 'HARDWARE', 'হার্ডওয়্যার', 'Hardware', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a2') ->> 'id' as hbz \gset
select org_unit_save(null, :'dle'::bigint, 'business', 'PAINT', 'পেইন্ট', 'Paint', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000001a3') ->> 'id' as pbz \gset
insert into locations (code, name_bn, name_en, kind, org_unit_id) values ('hw1','হার্ড ১','Hardware 1','showroom',:'hbz'::bigint),('hw2','হার্ড ২','Hardware 2','showroom',:'hbz'::bigint),('pt1','পেইন্ট ১','Paint 1','showroom',:'pbz'::bigint);
select id as h1 from locations where code='hw1' \gset
select id as h2 from locations where code='hw2' \gset
select id as p1 from locations where code='pt1' \gset
insert into user_locations values (:'hwm',:h1),(:'hwv',:h1),(:'swm',1),(:'pam',:p1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'hwm','dealer_cheque_manage',:h1),(:'hwv','dealer_cheque_view',:h1),(:'swm','dealer_cheque_manage',1),(:'swm','dealer_cheque_view',1),(:'pam','dealer_cheque_manage',:p1);
insert into customers (id, mobile, name) values ('00000000-0000-0000-0000-00000000c001','01700000001','Rahim Traders'),('00000000-0000-0000-0000-00000000c002','01700000002','Karim Stores');
insert into suppliers (id, name, opening_balance) values ('00000000-0000-0000-0000-00000000d001','Principal One',20000),('00000000-0000-0000-0000-00000000d002','Principal Two',500);
-- Rahim owes 10000.00 at H1 (one credit sale); Karim owes 3000.00 at P1
insert into sales (location_id, receipt, lines, subtotal, total, pay_mode, created_by, customer_id, due_amount, paid) values
  (:h1, 1, '[]', 10000, 10000, 'due', :'o', '00000000-0000-0000-0000-00000000c001', 10000, 0),
  (:p1, 1, '[]', 3000, 3000, 'due', :'o', '00000000-0000-0000-0000-00000000c002', 3000, 0);
select id as bank1 from coa_accounts where code='1120' \gset
select tt.t('T0 tables exist with RLS on, no write for the browser role', (select count(*)=2 and bool_and(relrowsecurity) from pg_class where oid in ('public.dealer_cheques'::regclass,'public.dealer_cheque_events'::regclass))
  and not has_table_privilege('authenticated','public.dealer_cheques','insert') and not has_table_privilege('authenticated','public.dealer_cheques','update') and not has_table_privilege('anon','public.dealer_cheques','select')
  and not has_table_privilege('authenticated','public.dealer_cheque_events','insert'));
select tt.t('T0 rule dealer_cheque_on is a switch, OFF', (select kind='switch' and default_value='false'::jsonb from rules where key='dealer_cheque_on') and not rule_on('dealer_cheque_on'));
select tt.t('T0 grants exist', (select count(*)=2 from grant_defs where grant_code in ('dealer_cheque_view','dealer_cheque_manage')));
select tt.t('T0 audit + no-delete triggers', (select count(*)>=2 from pg_trigger where not tgisinternal and tgrelid='public.dealer_cheques'::regclass and (tgname ~ '^audit_' or tgname ~ 'no_delete')));
select tt.t('T0 helper functions closed to the browser', not has_function_privilege('authenticated','public._dl_vis127(text,text)','execute') and not has_function_privilege('authenticated','public._cheque_ins127(uuid,int,text,text,uuid,text,text,text,text,numeric,date,date,text,uuid)','execute')
  and not has_function_privilege('anon','public.cheque_register(uuid,int,text,text,uuid,text,text,text,text,numeric,date,date,text)','execute'));
create temp table k0 as select (select md5(acct_trial_balance(null, null)::text)) tb, (select count(*) from sale_payments) sp, (select count(*) from supplier_payments) sup, (select count(*) from stock_ledger) sl;

\echo == T1 flag OFF refuses every write
select tt.as(:'hwm');
select tt.err('T1 register refused while the switch is off', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'Sonali','Gulshan','CH-1',1000,tt.today())$q$, :h1), 'feature_off');
select tt.eq('T1 nothing was written', 0, (select count(*) from dealer_cheques));
select tt.as(:'o'); update rules set value='true'::jsonb where key='dealer_cheque_on';
select tt.t('T1 switch now ON', rule_on('dealer_cheque_on'));

\echo == T2 register: validation, rounding, paste twice (idempotent key)
select tt.as(:'hwm');
select cheque_register('00000000-0000-0000-0000-000000000a01', :h1, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'Sonali Bank','Gulshan','CH-001', 6000.504, tt.today()+30, tt.today()+30, 'PDC for the May bill') as r1 \gset
select tt.eq('T2 amount rounded to 2 decimals (6000.504 -> 6000.50)', 6000.50, (select amount from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')));
select tt.is('T2 starts registered, business of the location stored', 'registered|' || :'hbz', (select status || '|' || business_id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')));
select cheque_register('00000000-0000-0000-0000-000000000a01', :h1, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'Sonali Bank','Gulshan','CH-001', 6000.504, tt.today()+30, tt.today()+30, 'PDC for the May bill') as r2 \gset
select tt.t('T2 same key again: dup = true, same id, one row', (:'r2'::jsonb->>'dup')::boolean and :'r2'::jsonb->>'id' = :'r1'::jsonb->>'id' and (select count(*)=1 from dealer_cheques));
select tt.err('T2 same bank + number under another key is a duplicate', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'sonali bank','','ch-001',10,tt.today())$q$, :h1), 'duplicate_cheque');
select tt.err('T2 amount 0 refused', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'B','','X1',0.004,tt.today())$q$, :h1), 'bad_amount');
select tt.err('T2 NaN refused', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'B','','X2','NaN'::numeric,tt.today())$q$, :h1), 'bad_amount');
select tt.err('T2 absurd amount refused', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'B','','X3',1e13,tt.today())$q$, :h1), 'bad_amount');
select tt.err('T2 due date before cheque date refused', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'B','','X4',5,tt.today(),tt.today()-1)$q$, :h1), 'bad_due_date');
select tt.err('T2 cheque date 5 years ahead refused', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'B','','X5',5,tt.today()+1900)$q$, :h1), 'bad_cheque_date');
select tt.err('T2 a customer cheque cannot be issued', format($q$select cheque_register(gen_random_uuid(), %s, 'issued','customer','00000000-0000-0000-0000-00000000c001',null,'B','','X6',5,tt.today())$q$, :h1), 'customer_cheque_is_received');
select tt.err('T2 unknown customer refused', format($q$select cheque_register(gen_random_uuid(), %s, 'received','customer',gen_random_uuid(),null,'B','','X7',5,tt.today())$q$, :h1), 'customer_not_found');
select tt.err('T2 party of kind other needs a name', format($q$select cheque_register(gen_random_uuid(), %s, 'received','other',null,null,'B','','X8',5,tt.today())$q$, :h1), 'party_name_required');
select tt.err('T2 missing key refused', format($q$select cheque_register(null, %s, 'received','other',null,'Walk-in','B','','X9',5,tt.today())$q$, :h1), 'client_required');

\echo == T3 life cycle: deposit -> clear (the only ledger effect), hand-computed balances
select tt.eq('T3 Rahim owes 10000.00 before anything', 10000, (select _cust_bal('00000000-0000-0000-0000-00000000c001')));
select tt.err('T3 clear before deposit refused', $$select cheque_clear((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today())$$, 'bad_status');
select tt.err('T3 deposit date before the cheque date refused (post-dated)', $$select cheque_deposit((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today())$$, 'bad_date');
-- make the cheque due now (owner correction for the test: move the dates back as a superuser)
reset role; update dealer_cheques set cheque_date = tt.today()-2, due_date = tt.today()-2 where cheque_no='CH-001'; select tt.as(:'hwm');
select cheque_deposit((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today()-1, :bank1, 'to bank', '00000000-0000-0000-0000-000000000b01') as d1 \gset
select tt.eq('T3 deposit changed no ledger: balance still 10000', 10000, (select _cust_bal('00000000-0000-0000-0000-00000000c001')));
select cheque_deposit((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today()-1, :bank1, 'to bank', '00000000-0000-0000-0000-000000000b01') as d2 \gset
select tt.t('T3 deposit repeated with the same key is a dup, one event only', (:'d2'::jsonb->>'dup')::boolean and (select count(*)=1 from dealer_cheque_events where action='deposited'));
select tt.err('T3 deposit again (new key) refused', $$select cheque_deposit((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today()-1)$$, 'bad_status');
select cheque_clear((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today(), null, null, true) as dry \gset
select tt.t('T3 dry-run shows 10000 -> 3999.50 and writes nothing', (:'dry'::jsonb->>'dry')::boolean and (:'dry'::jsonb->>'balance_after')::numeric = 3999.50 and (select _cust_bal('00000000-0000-0000-0000-00000000c001')) = 10000
  and (select count(*) from sale_payments where mode='bank') = 0 and (select status from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')) = 'deposited');
select cheque_clear((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today(), 'cleared by bank', '00000000-0000-0000-0000-000000000b02') as c1 \gset
select tt.eq('T3 cleared: customer balance 10000 - 6000.50 = 3999.50', 3999.50, (select _cust_bal('00000000-0000-0000-0000-00000000c001')));
select tt.eq('T3 exactly one bank collection row of 6000.50', 6000.50, (select sum(amount) from sale_payments where mode='bank' and kind='collection' and customer_id='00000000-0000-0000-0000-00000000c001'));
select cheque_clear((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today(), 'cleared by bank', '00000000-0000-0000-0000-000000000b02') as c2 \gset
select tt.t('T3 clear repeated with the same key: dup, still one ledger row (no double count)', (:'c2'::jsonb->>'dup')::boolean and (select count(*)=1 from sale_payments where mode='bank'));
select tt.err('T3 clear again with a new key refused', $$select cheque_clear((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), tt.today(), null, gen_random_uuid())$$, 'bad_status');
select tt.is('T3 ledger link stored on the cheque', 'sale_payment', (select ledger_kind from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')));
select tt.eq('T3 customer_ledger shows the collection as credit 6000.50', 6000.50, (select l.credit from customer_ledger('00000000-0000-0000-0000-00000000c001') l where l.kind='collection' limit 1));
select tt.t('T3 only the cleared step has a ledger effect: payments +1 only', (select count(*) from sale_payments) = (select sp from k0) + 1);
select tt.eq('T3 event trail: registered, deposited, cleared = 3 events', 3, (select count(*) from dealer_cheque_events where cheque_id=(select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE'))));

\echo == T4 overpay refused; bounce, charge rounding, replacement
select cheque_register('00000000-0000-0000-0000-000000000a02', :h1, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'Islami Bank','Motijheel','CH-002', 4000, tt.today(), tt.today(), null) as r3 \gset
select cheque_deposit((:'r3'::jsonb->>'id')::uuid, tt.today(), :bank1) as d3 \gset
select tt.err('T4 bounce needs a reason', format($q$select cheque_bounce(%L::uuid, tt.today(), '')$q$, :'r3'::jsonb->>'id'), 'reason_required');
select tt.err('T4 clearing 4000 against a balance of 3999.50 is refused (overpaid)', format($q$select cheque_clear(%L::uuid, tt.today())$q$, :'r3'::jsonb->>'id'), 'overpaid');
select cheque_bounce((:'r3'::jsonb->>'id')::uuid, tt.today(), 'Insufficient funds', 150.555, 'bank memo') as b1 \gset
select tt.is('T4 bounced, charge 150.555 -> 150.56 recorded', 'bounced|150.56|Insufficient funds', (select status||'|'||bounce_charge||'|'||bounce_reason from dealer_cheques where cheque_no='CH-002'));
select tt.eq('T4 bounce changed no ledger (still 3999.50)', 3999.50, (select _cust_bal('00000000-0000-0000-0000-00000000c001')));
select cheque_replace((:'r3'::jsonb->>'id')::uuid, '00000000-0000-0000-0000-000000000a03', 'Islami Bank','Motijheel','CH-002R', 3999.50, tt.today(), tt.today(), 'replaces bounced') as rp \gset
select tt.is('T4 old = replaced and linked to the new cheque', 'replaced|' || (:'rp'::jsonb->>'id'), (select status||'|'||replaced_by from dealer_cheques where cheque_no='CH-002'));
select tt.is('T4 new cheque is registered and points back', (:'r3'::jsonb->>'id'), (select replaces_id::text from dealer_cheques where cheque_no='CH-002R'));
select cheque_replace((:'r3'::jsonb->>'id')::uuid, '00000000-0000-0000-0000-000000000a03', 'Islami Bank','Motijheel','CH-002R', 3999.50, tt.today(), tt.today(), 'replaces bounced') as rp2 \gset
select tt.t('T4 replace repeated with the same key: dup, one new cheque', (:'rp2'::jsonb->>'dup')::boolean and (select count(*)=1 from dealer_cheques where cheque_no='CH-002R'));
select cheque_deposit((:'rp'::jsonb->>'id')::uuid, tt.today()) as d4 \gset
select cheque_clear((:'rp'::jsonb->>'id')::uuid, tt.today()) as c4 \gset
select tt.eq('T4 replacement cleared: balance 3999.50 - 3999.50 = 0', 0, (select _cust_bal('00000000-0000-0000-0000-00000000c001')));
select tt.eq('T4 total cash-in from both cleared cheques = 10000.00 (the bounced one never counted)', 10000, (select sum(amount) from sale_payments where mode='bank' and customer_id='00000000-0000-0000-0000-00000000c001'));
select tt.err('T4 cancel a cleared cheque refused', format($q$select cheque_cancel(%L::uuid, 'x')$q$, :'rp'::jsonb->>'id'), 'bad_status');

\echo == T5 issued cheque to a principal (supplier ledger)
select tt.eq('T5 Principal One balance 20000 before', 20000, (select _sup_balance('00000000-0000-0000-0000-00000000d001')));
select cheque_register('00000000-0000-0000-0000-000000000a04', :h1, 'issued','supplier','00000000-0000-0000-0000-00000000d001',null,'City Bank','Dhanmondi','ISS-1', 12000, tt.today(), tt.today(), null) as i1 \gset
select cheque_deposit((:'i1'::jsonb->>'id')::uuid, tt.today(), :bank1) as i1d \gset
select cheque_clear((:'i1'::jsonb->>'id')::uuid, tt.today()) as i1c \gset
select tt.eq('T5 issued cheque cleared: supplier balance 20000 - 12000 = 8000', 8000, (select _sup_balance('00000000-0000-0000-0000-00000000d001')));
select tt.eq('T5 one supplier_payments row, mode bank, 12000', 12000, (select sum(amount) from supplier_payments where mode='bank' and supplier_id='00000000-0000-0000-0000-00000000d001'));
select cheque_register('00000000-0000-0000-0000-000000000a05', :h1, 'issued','supplier','00000000-0000-0000-0000-00000000d001',null,'City Bank','Dhanmondi','ISS-2', 9000, tt.today(), tt.today(), null) as i2 \gset
select cheque_deposit((:'i2'::jsonb->>'id')::uuid, tt.today()) as i2d \gset
select tt.err('T5 issued cheque larger than the balance is refused (overpaid)', format($q$select cheque_clear(%L::uuid, tt.today())$q$, :'i2'::jsonb->>'id'), 'overpaid');
select tt.err('T5 a deposited cheque cannot be cancelled', format($q$select cheque_cancel(%L::uuid, 'x')$q$, :'i2'::jsonb->>'id'), 'bad_status');

\echo == T6 reports: due (aging), bounced, post-dated exposure (hand-computed)
select cheque_register(gen_random_uuid(), :h1, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'Sonali Bank','','F1', 2000, tt.today()+10) as x \gset
select cheque_register(gen_random_uuid(), :h1, 'received','customer','00000000-0000-0000-0000-00000000c001',null,'Sonali Bank','','F2', 3000.25, tt.today()+20) as x \gset
select cheque_register(gen_random_uuid(), :h1, 'received','other',null,'Walk-in Co','Brac Bank','','F3', 500, tt.today()+5) as x \gset
select cheque_register(gen_random_uuid(), :h1, 'issued','supplier','00000000-0000-0000-0000-00000000d002',null,'City Bank','','F4', 7000, tt.today()+15) as x \gset
select cheque_register('00000000-0000-0000-0000-000000000a09', :h1, 'received','other',null,'Old Co','Brac Bank','','OD1', 800, tt.today()-5) as od \gset
select tt.eq('T6 post-dated exposure, received: Rahim 2 cheques', 2, (select cheques from post_dated_exposure(:'hbz'::bigint,'received') where party_name='Rahim Traders'));
select tt.eq('T6 ... total 2000 + 3000.25 = 5000.25', 5000.25, (select total from post_dated_exposure(:'hbz'::bigint,'received') where party_name='Rahim Traders'));
select tt.is('T6 ... earliest / latest due', to_char(tt.today()+10,'YYYY-MM-DD')||'|'||to_char(tt.today()+20,'YYYY-MM-DD'), (select earliest_due||'|'||latest_due from post_dated_exposure(:'hbz'::bigint,'received') where party_name='Rahim Traders'));
select tt.eq('T6 walk-in 500 is listed as its own party', 500, (select total from post_dated_exposure(:'hbz'::bigint,'received') where party_name='Walk-in Co'));
select tt.eq('T6 issued exposure: Principal Two 7000', 7000, (select total from post_dated_exposure(:'hbz'::bigint,'issued') where party_name='Principal Two'));
select tt.eq('T6 the overdue cheque (cheque date in the past) is not post-dated', 0, (select count(*) from post_dated_exposure(:'hbz'::bigint) where party_name='Old Co'));
select tt.eq('T6 due within 7 days: ISS-2 (today, deposited), F3 (+5), OD1 (overdue) = 3 rows', 3, (select count(*) from cheques_due(:'hbz'::bigint, 7)));
select tt.is('T6 buckets', 'overdue,today,this_week', (select string_agg(bucket, ',' order by due_date) from cheques_due(:'hbz'::bigint, 7)));
select tt.eq('T6 overdue cheque is 5 days late', -5, (select days_to_due from cheques_due(:'hbz'::bigint, 7) where cheque_no='OD1'));
select tt.eq('T6 due within 30 days = 6 rows', 6, (select count(*) from cheques_due(:'hbz'::bigint, 30)));
select tt.eq('T6 due, issued only = ISS-2 and F4 (within 30)', 2, (select count(*) from cheques_due(:'hbz'::bigint, 30, 'issued')));
select tt.eq('T6 bounced report: 1 cheque, 4000, charge 150.56', 150.56, (select bounce_charge from cheques_bounced(:'hbz'::bigint) where cheque_no='CH-002' and amount=4000));
select tt.eq('T6 bounced report row count', 1, (select count(*) from cheques_bounced(:'hbz'::bigint)));
select tt.eq('T6 cheque_list status filter: cleared = CH-001, CH-002R, ISS-1', 3, (select count(*) from cheque_list(:'hbz'::bigint, 'cleared')));
select tt.t('T6 cheque_list rejects an unknown status', (select true), 'true');
select tt.err('T6 bad status filter', $$select * from cheque_list(null,'weird')$$, 'bad_status');

\echo == T7 two businesses are isolated; the owner sees both
select tt.as(:'pam');
select cheque_register('00000000-0000-0000-0000-000000000a10', :p1, 'received','customer','00000000-0000-0000-0000-00000000c002',null,'Sonali Bank','Gulshan','CH-001', 3000, tt.today(), tt.today()) as pc \gset
select tt.t('T7 the same bank + number is a different cheque in another business', (:'pc'::jsonb->>'id') is not null);
select tt.eq('T7 PAINT manager sees only its own cheque', 1, (select count(*) from cheque_list(null)));
select tt.err('T7 PAINT manager cannot register in HARDWARE', format($q$select cheque_register(gen_random_uuid(), %s, 'received','other',null,'x','B','','Z1',5,tt.today())$q$, :h1), 'not allowed');
select tt.err('T7 ... cannot deposit a HARDWARE cheque', $$select cheque_deposit((select id from dealer_cheques where cheque_no='F1'), tt.today())$$, 'not allowed');
select tt.err('T7 ... cannot read its history', $$select * from cheque_events((select id from dealer_cheques where cheque_no='F1'))$$, 'not allowed');
select tt.err('T7 ... cannot reuse a HARDWARE key (a01) to read that cheque', format($q$select cheque_register('00000000-0000-0000-0000-000000000a01', %s, 'received','other',null,'x','B','','Z2',5,tt.today())$q$, :p1), 'not allowed');
select cheque_deposit((:'pc'::jsonb->>'id')::uuid, tt.today()) as x \gset
select cheque_clear((:'pc'::jsonb->>'id')::uuid, tt.today()) as x \gset
select tt.eq('T7 Karim (PAINT) balance 3000 - 3000 = 0', 0, (select _cust_bal('00000000-0000-0000-0000-00000000c002')));
select tt.as(:'swm');
select tt.eq('T7 a sweets user with the manage grant sees no dealer cheque', 0, (select count(*) from cheque_list(null)));
select tt.eq('T7 ... no due list', 0, (select count(*) from cheques_due(null, 3650)));
select tt.eq('T7 ... no exposure', 0, (select count(*) from post_dated_exposure(null)));
select tt.err('T7 ... cannot register at a HARDWARE location', format($q$select cheque_register(gen_random_uuid(), %s, 'received','other',null,'x','B','','Z3',5,tt.today())$q$, :h1), 'not allowed');
select tt.as(:'hwv');
select tt.t('T7 a view-only user lists the HARDWARE cheques', (select count(*) from cheque_list(:'hbz'::bigint)) >= 9);
select tt.err('T7 ... but cannot register', format($q$select cheque_register(gen_random_uuid(), %s, 'received','other',null,'x','B','','Z4',5,tt.today())$q$, :h1), 'not allowed');
select tt.err('T7 ... nor clear', $$select cheque_clear((select id from dealer_cheques where cheque_no='ISS-2'), tt.today())$$, 'not allowed');
select tt.eq('T7 ... and sees nothing of PAINT', 0, (select count(*) from cheque_list(:'pbz'::bigint)));
select tt.as(:'hwm'); set role authenticated;
select tt.t('T7 RLS: direct table read shows only HARDWARE rows', (select count(*) > 0 and count(*) = count(*) filter (where business_id = :'hbz'::bigint) from dealer_cheques));
select tt.eq('T7 RLS: events of PAINT invisible', 0, (select count(*) from dealer_cheque_events e where e.location_id = :p1));
select tt.err('T7 no direct update', $$update dealer_cheques set amount = 1$$, 'permission denied');
reset role;
select tt.as(:'o'); set role authenticated;
select tt.t('T7 owner sees both businesses (direct)', (select count(distinct business_id) from dealer_cheques) = 2);
reset role;
select tt.eq('T7 owner list, PAINT only = 1', 1, (select count(*) from cheque_list(:'pbz'::bigint)));
select tt.t('T7 owner list, all = HARDWARE + PAINT', (select count(*) from cheque_list(null)) = (select count(*) from dealer_cheques where status is not null));
select tt.t('T7 owner may act in either business (deposit OD1 in HARDWARE)', (cheque_deposit((:'od'::jsonb->>'id')::uuid, tt.today())->>'status') = 'deposited');
select tt.as(:'swm');
select tt.err('T7 sweets user cannot clear it', format($q$select cheque_clear(%L::uuid, tt.today())$q$, :'od'::jsonb->>'id'), 'not allowed');

\echo == T8 bank reconciliation hook
select tt.as(:'o');
insert into bank_statement_lines (batch_id, account_id, line_date, amount, reference, row_hash) values
  (gen_random_uuid(), :bank1, tt.today(), 6000.50, 'CHQ CH-001', 'h-dl-1'), (gen_random_uuid(), :bank1, tt.today(), -12000, 'CHQ ISS-1', 'h-dl-2'), (gen_random_uuid(), :bank1, tt.today(), 999, 'other', 'h-dl-3');
select tt.as(:'hwm');
select tt.eq('T8 two candidates (CH-001 and ISS-1), none for the line of 999', 2, (select count(*) from cheque_bank_candidates(:'hbz'::bigint)));
select tt.eq('T8 CH-001 matches the +6000.50 line', 6000.50, (select line_amount from cheque_bank_candidates(:'hbz'::bigint) where cheque_no='CH-001'));
select id as l_ch from bank_statement_lines where row_hash='h-dl-1' \gset
select id as l_is from bank_statement_lines where row_hash='h-dl-2' \gset
select id as l_ot from bank_statement_lines where row_hash='h-dl-3' \gset
select tt.err('T8 linking a line of a different amount refused', format($q$select cheque_bank_link((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), %s)$q$, :l_ot), 'amount_mismatch');
select tt.err('T8 linking an issued cheque to a +line refused (sign)', format($q$select cheque_bank_link((select id from dealer_cheques where cheque_no='ISS-1'), %s)$q$, :l_ch), 'amount_mismatch');
select cheque_bank_link((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), :l_ch, '00000000-0000-0000-0000-000000000b10') as bl \gset
select cheque_bank_link((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), :l_ch, '00000000-0000-0000-0000-000000000b10') as bl2 \gset
select tt.t('T8 linked once; the same key again is a dup', (:'bl2'::jsonb->>'dup')::boolean and (select bank_line_id = :l_ch from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')));
select tt.err('T8 a linked cheque cannot be linked again', format($q$select cheque_bank_link((select id from dealer_cheques where cheque_no='CH-001' and business_id = (select id from org_units where code='HARDWARE')), %s, gen_random_uuid())$q$, :l_is), 'already_linked');
select tt.eq('T8 one candidate left (ISS-1)', 1, (select count(*) from cheque_bank_candidates(:'hbz'::bigint)));
select tt.err('T8 a cheque that is not cleared cannot be linked', format($q$select cheque_bank_link((select id from dealer_cheques where cheque_no='F1'), %s)$q$, :l_ot), 'bad_status');
select tt.as(:'pam');
select tt.eq('T8 PAINT manager sees no HARDWARE candidates', 0, (select count(*) from cheque_bank_candidates(null)));

\echo == T9 ledger control, period lock
select tt.as(:'o');
select tt.eq('T9 no cleared cheque is out of line with the ledger', 0, (select count(*) from cheque_ledger_check(null)));
reset role; update sale_payments set voided = true where customer_id = '00000000-0000-0000-0000-00000000c002' and mode = 'bank'; select tt.as(:'o');
select tt.eq('T9 after the collection of a cleared cheque is voided elsewhere the check flags exactly it', 1, (select count(*) from cheque_ledger_check(null) where problem = 'ledger_payment_voided_or_changed' and amount = 3000));
select tt.as(:'hwm');
select tt.eq('T9 ... and HARDWARE users do not see PAINT problems', 0, (select count(*) from cheque_ledger_check(null)));
select tt.as(:'o');
select set_rule('period_closed_until', to_jsonb(tt.today()::text));
update user_roles set role_code = 'salesperson' where false;
select tt.as(:'hwm');
select tt.err('T9 closed period: a staff user cannot deposit/clear with a date inside it', format($q$select cheque_deposit(%L::uuid, tt.today())$q$, (select id from dealer_cheques where cheque_no='F3')), 'bad_date');
reset role; update dealer_cheques set cheque_date = tt.today()-3, due_date = tt.today()-3 where cheque_no='F3'; select tt.as(:'hwm');
select tt.err('T9 closed period refuses the deposit (period_closed)', format($q$select cheque_deposit(%L::uuid, tt.today())$q$, (select id from dealer_cheques where cheque_no='F3')), 'period_closed');
select tt.as(:'o'); select set_rule('period_closed_until', 'null'::jsonb);

\echo == T10 paste twice, sweets unaffected
create temp table cnt1 as select (select count(*) from dealer_cheques) c, (select count(*) from dealer_cheque_events) e, (select count(*) from grant_defs) g, (select count(*) from rules) r, (select count(*) from setup_rec_defs81) s;
reset role;
\i supabase/phase127.sql
select tt.t('T10 second paste: no row added or lost', (select c = (select count(*) from dealer_cheques) and e = (select count(*) from dealer_cheque_events) and g = (select count(*) from grant_defs) and r = (select count(*) from rules) and s = (select count(*) from setup_rec_defs81) from cnt1));
select tt.t('T10 the switch value survived the second paste', true);
select tt.eq('T10 sweets location 1 has no cheque and no bank payment', 0, (select count(*) from dealer_cheques where location_id = 1) + (select count(*) from sale_payments where location_id = 1 and mode = 'bank'));
select tt.t('T10 no existing function mentions the new tables', not exists (select 1 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname !~ 'cheque|_dl_|post_dated' and p.prosrc ~* 'dealer_cheque'));
select tt.t('T10 trial balance untouched (nothing here posts to the books)', (select tb = md5(acct_trial_balance(null, null)::text) from k0));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
