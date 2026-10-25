-- FRESH DB ONLY (canonical build through phase124). Phase 124 tests = Import-Export basic module, scoped per business.
--   bash tests/sql/final_build.sh <db>;  psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase124_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
\i tests/sql/e2e/00_common.sql
\set ua '00000000-0000-0000-0000-000000000041'
\set uav '00000000-0000-0000-0000-000000000042'
\set ub '00000000-0000-0000-0000-000000000043'
\set un '00000000-0000-0000-0000-000000000044'
\set cl 'gen_random_uuid()'
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@b6.app','{"full_name":"Owner"}'),(:'ua','ua@b6.app','{"full_name":"UA"}'),(:'uav','uav@b6.app','{"full_name":"UAV"}'),(:'ub','ub@b6.app','{"full_name":"UB"}'),(:'un','un@b6.app','{"full_name":"UN"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'ua','salesperson'),(:'uav','salesperson'),(:'ub','salesperson'),(:'un','salesperson') on conflict do nothing;

\echo == T0 shape
select tt.t('T0 four tables, RLS on, no browser privilege, no policy', (select count(*) = 4 and bool_and(relrowsecurity) from pg_class where oid in ('public.ie_currencies'::regclass,'public.ie_fx_rates'::regclass,'public.ie_shipments'::regclass,'public.ie_shipment_events'::regclass))
  and not has_table_privilege('authenticated','public.ie_shipments','select') and not has_table_privilege('authenticated','public.ie_shipments','insert') and not has_table_privilege('anon','public.ie_fx_rates','select')
  and not exists (select 1 from pg_policies where tablename like 'ie\_%'));
select tt.t('T0 every table has org_unit_id', (select count(*) = 4 from information_schema.columns where table_name in ('ie_currencies','ie_fx_rates','ie_shipments','ie_shipment_events') and column_name = 'org_unit_id'));
select tt.t('T0 grants and rule exist, rule is a switch and OFF', exists(select 1 from grant_defs where grant_code='impexp_view') and exists(select 1 from grant_defs where grant_code='impexp_manage')
  and (select kind = 'switch' and default_value = 'false'::jsonb from rules where key='impexp_on') and not rule_on('impexp_on'));
select tt.t('T0 helpers closed to the browser', not has_function_privilege('authenticated','public._ie_access124(bigint,text)','execute') and not has_function_privilege('authenticated','public._ie_write124(bigint)','execute'));
select tt.t('T0 template import_export: needs_setup, modules list built and not_built honestly (no GL posting)', (select status = 'needs_setup' and modules @> '[{"code":"accounting_posting","state":"not_built"}]'::jsonb and modules @> '[{"code":"letter_of_credit","state":"not_built"}]'::jsonb
  and modules @> '[{"code":"shipments","state":"built"}]'::jsonb from business_templates where code = 'import_export'));

create temp table jl0 as select count(*) n from journal_lines;
\echo == T1 two businesses A and B (import_export), own legal entities and locations
select tt.as(:'o');
select org_unit_save(null,(select id from org_units where kind='group'),'legal_entity','LE-IEA','এ কোম্পানি','LE A',null,null,null,null,'BDT','Asia/Dhaka','{}'::jsonb,'{"base_currency":"BDT"}'::jsonb,gen_random_uuid())->>'id' as lea \gset
select org_unit_save(null,:'lea'::bigint,'business','IEA','এ আমদানি','IE A','import_export','active',null,null,'BDT','Asia/Dhaka','{}'::jsonb,null,gen_random_uuid())->>'id' as bza \gset
select org_unit_save(null,(select id from org_units where kind='group'),'legal_entity','LE-IEB','বি কোম্পানি','LE B',null,null,null,null,'USD','Asia/Dhaka','{}'::jsonb,'{"base_currency":"USD"}'::jsonb,gen_random_uuid())->>'id' as leb \gset
select org_unit_save(null,:'leb'::bigint,'business','IEB','বি আমদানি','IE B','import_export','active',null,null,'USD','Asia/Dhaka','{}'::jsonb,null,gen_random_uuid())->>'id' as bzb \gset
insert into locations (code,name_bn,name_en,sort,org_unit_id) values ('iea_off','এ অফিস','A office',90,:'bza'::bigint),('ieb_off','বি অফিস','B office',91,:'bzb'::bigint);
insert into user_locations select :'ua', id from locations where code='iea_off';
insert into user_locations select :'uav', id from locations where code='iea_off';
insert into user_locations select :'un', id from locations where code='iea_off';
insert into user_locations select :'ub', id from locations where code='ieb_off';
insert into user_grants (user_id, grant_code) values (:'ua','impexp_manage'),(:'uav','impexp_view'),(:'ub','impexp_manage');
select tt.is('T1 base currency follows the legal entity (A=BDT, B=USD)', 'BDT/USD', (select string_agg(base_currency, '/' order by code) from ie_businesses124()));
select tt.eq('T1 owner sees both businesses', 2, (select count(*) from ie_businesses124()));
select tt.eq('T1 sweets business is not an import_export business, not listed', 0, (select count(*) from ie_businesses124() where code = 'SWEETS'));

\echo == T2 flag OFF refuses every write
select tt.err('T2 currency_save refused while impexp_on is OFF', format($q$select currency_save(%s,'USD','ডলার','US dollar',2,true,gen_random_uuid())$q$, :'bza'), 'impexp_off');
select tt.err('T2 shipment_save refused while OFF', format($q$select shipment_save(%s,null,'import','R-1','x','BDT',100,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$, :'bza'), 'impexp_off');
select tt.err('T2 fx_rate_set refused while OFF', format($q$select fx_rate_set(%s,'USD',110,null,null,gen_random_uuid())$q$, :'bza'), 'impexp_off');
update rules set default_value = 'true'::jsonb where key = 'impexp_on';
select tt.t('T2 now ON', rule_on('impexp_on'));

\echo == T3 currencies and rates
select currency_save(:'bza'::bigint,'usd','ডলার','US dollar',2,true,'00000000-0000-0000-0000-0000000000c1') ->> 'id' as cusd \gset
select currency_save(:'bza'::bigint,'EUR','ইউরো','Euro',2,true,gen_random_uuid());
select currency_save(:'bza'::bigint,'JPY','ইয়েন','Yen',0,true,gen_random_uuid());
select tt.eq('T3 three currencies listed for A (no hardcoded list: only what was entered)', 3, (select count(*) from ie_currencies_list(:'bza'::bigint)));
select tt.eq('T3 B has none', 0, (select count(*) from ie_currencies_list(:'bzb'::bigint)));
select tt.t('T3 same key again = dup, same id', (select (r->>'dup')::boolean and (r->>'id')::bigint = :'cusd'::bigint from (select currency_save(:'bza'::bigint,'USD','ডলার','US dollar',2,true,'00000000-0000-0000-0000-0000000000c1') r) z));
select currency_save(:'bza'::bigint,'JPY','ইয়েন','Japanese yen',0,false,gen_random_uuid());
select tt.is('T3 edit deactivates, history stays', 'false', (select active::text from ie_currencies where org_unit_id=:'bza'::bigint and code='JPY'));
select tt.err('T3 base currency cannot be listed', format($q$select currency_save(%s,'BDT','টাকা',null,2,true,gen_random_uuid())$q$,:'bza'), 'is_base_currency');
select tt.err('T3 bad code', format($q$select currency_save(%s,'US','x',null,2,true,gen_random_uuid())$q$,:'bza'), 'bad_currency');
select tt.err('T3 bad decimals', format($q$select currency_save(%s,'GBP','x',null,9,true,gen_random_uuid())$q$,:'bza'), 'bad_decimals');
select tt.err('T3 name too long', format($q$select currency_save(%s,'GBP',repeat('x',81),null,2,true,gen_random_uuid())$q$,:'bza'), 'bad_name');
select fx_rate_set(:'bza'::bigint,'USD',110.5,date '2026-01-01','jan',gen_random_uuid());
select fx_rate_set(:'bza'::bigint,'USD',120,date '2026-03-01','mar','00000000-0000-0000-0000-0000000000d1') ->> 'id' as fx1 \gset
select tt.t('T3 fx same key = dup', (select (fx_rate_set(:'bza'::bigint,'USD',120,date '2026-03-01','mar','00000000-0000-0000-0000-0000000000d1')->>'dup')::boolean));
select tt.eq('T3 history has 2 rows (append-only)', 2, (select count(*) from ie_fx_rates_list(:'bza'::bigint,'USD')));
select tt.err('T3 rate history cannot be updated', format('update ie_fx_rates set rate = 1 where id = %s', :'fx1'), 'append_only');
select tt.err('T3 rate history cannot be deleted', format('delete from ie_fx_rates where id = %s', :'fx1'), 'append_only');
select tt.err('T3 rate zero', format($q$select fx_rate_set(%s,'USD',0,null,null,gen_random_uuid())$q$,:'bza'), 'bad_rate');
select tt.err('T3 rate negative', format($q$select fx_rate_set(%s,'USD',-1,null,null,gen_random_uuid())$q$,:'bza'), 'bad_rate');
select tt.err('T3 rate NaN', format($q$select fx_rate_set(%s,'USD','NaN'::numeric,null,null,gen_random_uuid())$q$,:'bza'), 'bad_amount');
select tt.err('T3 rate too big', format($q$select fx_rate_set(%s,'USD',2e12,null,null,gen_random_uuid())$q$,:'bza'), 'bad_amount');
select tt.err('T3 rate for an unlisted currency', format($q$select fx_rate_set(%s,'CHF',100,null,null,gen_random_uuid())$q$,:'bza'), 'currency_not_listed');
select tt.err('T3 rate for an inactive currency', format($q$select fx_rate_set(%s,'JPY',1,null,null,gen_random_uuid())$q$,:'bza'), 'currency_not_listed');
select tt.err('T3 rate needs a key', format($q$select fx_rate_set(%s,'USD',100,null,null,null)$q$,:'bza'), 'client_id_needed');
select tt.err('T3 rate date far in the future', format($q$select fx_rate_set(%s,'USD',100,current_date + 400,null,gen_random_uuid())$q$,:'bza'), 'bad_date');

\echo == T4 shipments: rounding, rate lookup, cost lines
select shipment_save(:'bza'::bigint,null,'import','IMP-001','Shanghai Co','USD',1000.555,null,date '2026-02-10',date '2026-03-10','first',50.10,20,100.005,0,'00000000-0000-0000-0000-0000000000e1') as r1 \gset
select tt.eq('T4 rate in force on 2026-02-10 is the Jan rate 110.5: amount_base = round(1000.56 * 110.5, 2)', round(1000.56*110.5, 2), (:'r1'::jsonb->>'amount_base')::numeric);
select tt.eq('T4 stored amount rounded to 2 places (1000.56)', 1000.56, (select amount from ie_shipments where reference='IMP-001'));
select tt.is('T4 rate used is stored', '110.50000000', (select rate::text from ie_shipments where reference='IMP-001'));
select shipment_save(:'bza'::bigint,null,'export','EXP-001','Dhaka Buyer','BDT',2500,null,date '2026-04-01',null,null,0,0,0,0,gen_random_uuid()) as r2 \gset
select tt.eq('T4 base-currency shipment: rate 1, base = amount', 2500, (:'r2'::jsonb->>'amount_base')::numeric);
select shipment_save(:'bza'::bigint,null,'import','IMP-002','Tokyo Ltd','USD',10,115.123456,date '2026-04-05',null,null,0,0,0,0,gen_random_uuid()) as r3 \gset
select tt.eq('T4 user-typed rate wins: 10 * 115.123456', 1151.23, (:'r3'::jsonb->>'amount_base')::numeric);
select tt.eq('T4 landed cost summary = goods + typed lines', round(1000.56*110.5,2) + 50.10 + 20 + 100.01, (shipment_cost_summary(:'bza'::bigint,(:'r1'::jsonb->>'id')::bigint)->>'landed_base')::numeric);
select tt.eq('T4 lines_total', 170.11, (shipment_cost_summary(:'bza'::bigint,(:'r1'::jsonb->>'id')::bigint)->>'lines_total')::numeric);
select tt.t('T4 same key again = dup, one row', (select (shipment_save(:'bza'::bigint,null,'import','IMP-001','Shanghai Co','USD',1000.555,null,date '2026-02-10',null,null,0,0,0,0,'00000000-0000-0000-0000-0000000000e1')->>'dup')::boolean) and (select count(*) = 1 from ie_shipments where reference='IMP-001'));
select tt.err('T4 create without key', format($q$select shipment_save(%s,null,'import','IMP-9',null,'BDT',1,null,current_date,null,null,0,0,0,0,null)$q$,:'bza'), 'client_id_needed');
select tt.err('T4 duplicate reference in the same business', format($q$select shipment_save(%s,null,'import','IMP-001',null,'BDT',1,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'reference_taken');
select tt.err('T4 no rate = refused, nothing guessed', format($q$select shipment_save(%s,null,'import','IMP-3',null,'EUR',5,null,date '2026-02-10',null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'no_rate');
select tt.err('T4 rate not yet valid on an early ship date', format($q$select shipment_save(%s,null,'import','IMP-4',null,'USD',5,null,date '2025-12-31',null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'no_rate');
select tt.err('T4 currency not in the list', format($q$select shipment_save(%s,null,'import','IMP-5',null,'CHF',5,100,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'currency_not_listed');
select tt.err('T4 bad direction', format($q$select shipment_save(%s,null,'sideways','IMP-6',null,'BDT',5,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_direction');
select tt.err('T4 amount NaN', format($q$select shipment_save(%s,null,'import','IMP-7',null,'BDT','NaN'::numeric,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_amount');
select tt.err('T4 amount above 1e12', format($q$select shipment_save(%s,null,'import','IMP-8',null,'BDT',1.5e12,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_amount');
select tt.err('T4 negative amount', format($q$select shipment_save(%s,null,'import','IMP-8',null,'BDT',-1,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_amount');
select tt.err('T4 negative cost line', format($q$select shipment_save(%s,null,'import','IMP-8',null,'BDT',1,null,current_date,null,null,-5,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_amount');
select tt.err('T4 base currency with a rate other than 1', format($q$select shipment_save(%s,null,'import','IMP-8',null,'BDT',1,2,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_rate');
select tt.err('T4 reference too long', format($q$select shipment_save(%s,null,'import',repeat('x',61),null,'BDT',1,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_reference');
select tt.err('T4 notes too long', format($q$select shipment_save(%s,null,'import','IMP-N',null,'BDT',1,null,current_date,null,repeat('x',1001),0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_notes');
select tt.err('T4 bad date', format($q$select shipment_save(%s,null,'import','IMP-D',null,'BDT',1,null,date '1990-01-01',null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_date');
select tt.err('T4 amount_base cannot overflow the cap', format($q$select shipment_save(%s,null,'import','IMP-O',null,'USD',9e11,9e11,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'bad_amount');

\echo == T5 status flow
select (:'r1'::jsonb->>'id') as s1 \gset
select tt.is('T5 draft to booked', 'booked', shipment_set_status(:'bza'::bigint,:'s1'::bigint,'booked',null,gen_random_uuid())->>'status');
select tt.err('T5 booked cannot go back to closed (skip)', format($q$select shipment_set_status(%s,%s,'closed',null,gen_random_uuid())$q$,:'bza',:'s1'), 'bad_transition');
select tt.is('T5 booked to in_transit', 'in_transit', shipment_set_status(:'bza'::bigint,:'s1'::bigint,'in_transit','sailed','00000000-0000-0000-0000-0000000000f1')->>'status');
select tt.t('T5 same key = dup, no second event', (shipment_set_status(:'bza'::bigint,:'s1'::bigint,'in_transit','sailed','00000000-0000-0000-0000-0000000000f1')->>'dup')::boolean and (select count(*) = 3 from ie_shipment_events where shipment_id=:'s1'::bigint));
select tt.t('T5 asking for the current status is a no-op dup', (shipment_set_status(:'bza'::bigint,:'s1'::bigint,'in_transit',null,gen_random_uuid())->>'dup')::boolean);
select tt.err('T5 amount cannot change once in transit', format($q$select shipment_save(%s,%s,null,null,null,'USD',5000,110.5,date '2026-02-10',null,null,0,0,0,0,null)$q$,:'bza',:'s1'), 'amount_locked');
select shipment_save(:'bza'::bigint,:'s1'::bigint,null,null,'Shanghai Co','USD',1000.555,110.5,date '2026-02-10',null,null,60,25,110,5,null)->>'landed_base' as lb2 \gset
select tt.eq('T5 cost lines can still be entered in transit (landed = goods + 200)', round(1000.56*110.5,2)+200, :'lb2'::numeric);
select tt.t('T5 the edit is in the event log', exists(select 1 from ie_shipment_events where shipment_id=:'s1'::bigint and event='edit'));
select tt.err('T5 direction is fixed', format($q$select shipment_save(%s,%s,'export',null,null,'USD',1000.555,110.5,date '2026-02-10',null,null,0,0,0,0,null)$q$,:'bza',:'s1'), 'direction_fixed');
select shipment_set_status(:'bza'::bigint,:'s1'::bigint,'received',null,gen_random_uuid());
select tt.t('T5 received_date is set', (select received_date is not null from ie_shipments where id=:'s1'::bigint));
select shipment_set_status(:'bza'::bigint,:'s1'::bigint,'closed','done',gen_random_uuid());
select tt.err('T5 closed is final (edit refused)', format($q$select shipment_save(%s,%s,null,null,null,'USD',1000.555,110.5,date '2026-02-10',null,null,0,0,0,0,null)$q$,:'bza',:'s1'), 'shipment_final');
select tt.err('T5 closed cannot be cancelled', format($q$select shipment_set_status(%s,%s,'cancelled',null,gen_random_uuid())$q$,:'bza',:'s1'), 'bad_transition');
select tt.err('T5 bad status', format($q$select shipment_set_status(%s,%s,'flying',null,gen_random_uuid())$q$,:'bza',:'s1'), 'bad_status');
select tt.err('T5 events cannot be edited', 'update ie_shipment_events set note = ''x''', 'append_only');
select tt.err('T5 no hard delete of a shipment', 'delete from ie_shipments', 'delet');
select tt.t('T5 audit rows written', (select count(*) >= 3 from audit_log where table_name = 'ie_shipments'));
select shipment_set_status(:'bza'::bigint,((:'r3'::jsonb)->>'id')::bigint,'cancelled','dropped',gen_random_uuid());

\echo == T6 reports
select tt.eq('T6 by currency: USD import = 1 shipment (cancelled one left out)', 1, (select shipments from shipments_by_currency(:'bza'::bigint) where currency='USD' and direction='import'));
select tt.eq('T6 by currency: BDT export base', 2500, (select amount_base from shipments_by_currency(:'bza'::bigint) where currency='BDT' and direction='export'));
select tt.eq('T6 date range filter excludes February', 0, (select count(*) from shipments_by_currency(:'bza'::bigint, date '2026-03-01', null) where currency='USD'));
select tt.eq('T6 list filter by status', 1, (select count(*) from shipments_list(:'bza'::bigint,'closed',null)));
select tt.eq('T6 list filter by direction', 1, (select count(*) from shipments_list(:'bza'::bigint,null,'export')));
select tt.t('T6 landed_base in list equals cost summary', (select landed_base from shipments_list(:'bza'::bigint,'closed',null)) = (shipment_cost_summary(:'bza'::bigint,:'s1'::bigint)->>'landed_base')::numeric);

\echo == T7 isolation: business B (base USD) is separate
select currency_save(:'bzb'::bigint,'BDT','টাকা','Taka',2,true,gen_random_uuid());
select fx_rate_set(:'bzb'::bigint,'BDT',0.0083,date '2026-01-01',null,gen_random_uuid());
select shipment_save(:'bzb'::bigint,null,'export','EXP-B1','B buyer','BDT',10000,null,date '2026-02-15',null,null,0,0,0,0,gen_random_uuid()) as rb \gset
select tt.eq('T7 B amount_base in USD = round(10000*0.0083,2)', 83, (:'rb'::jsonb->>'amount_base')::numeric);
select tt.eq('T7 B reference namespace is its own (IMP-001 can exist in B)', 1, (select (shipment_save(:'bzb'::bigint,null,'import','IMP-001','x','USD',1,null,current_date,null,null,0,0,0,0,gen_random_uuid())->>'id')::int > 0)::int);
select tt.eq('T7 owner sees A shipments', 3, (select count(*) from shipments_list(:'bza'::bigint)));
select tt.eq('T7 owner sees B shipments', 2, (select count(*) from shipments_list(:'bzb'::bigint)));
\set ON_ERROR_STOP off
select tt.as(:'ua');
select tt.eq('T7 user A sees only business A in the picker', 1, (select count(*) from ie_businesses124()));
select tt.is('T7 ... and it is A', 'IEA', (select code from ie_businesses124()));
select tt.eq('T7 user A lists A shipments', 3, (select count(*) from shipments_list(:'bza'::bigint)));
select tt.err('T7 user A cannot list B shipments', format('select * from shipments_list(%s)', :'bzb'), 'not allowed');
select tt.err('T7 user A cannot read B currencies', format('select * from ie_currencies_list(%s)', :'bzb'), 'not allowed');
select tt.err('T7 user A cannot read B fx rates', format('select * from ie_fx_rates_list(%s)', :'bzb'), 'not allowed');
select tt.err('T7 user A cannot read B report', format('select * from shipments_by_currency(%s)', :'bzb'), 'not allowed');
select tt.err('T7 user A cannot read a B cost summary', format('select shipment_cost_summary(%s, %s)', :'bzb', (:'rb'::jsonb->>'id')), 'not allowed');
select tt.err('T7 user A cannot save a B shipment', format($q$select shipment_save(%s,null,'import','A-IN-B',null,'USD',1,1,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bzb'), 'not allowed');
select tt.err('T7 user A cannot set a B shipment status', format($q$select shipment_set_status(%s,%s,'booked',null,gen_random_uuid())$q$,:'bzb',(:'rb'::jsonb->>'id')), 'not allowed');
select tt.err('T7 user A cannot set a B rate', format($q$select fx_rate_set(%s,'BDT',1,null,null,gen_random_uuid())$q$,:'bzb'), 'not allowed');
select tt.err('T7 user A cannot save a B currency', format($q$select currency_save(%s,'EUR','x',null,2,true,gen_random_uuid())$q$,:'bzb'), 'not allowed');
select tt.err('T7 A shipment id under B scope is not found even for the owner path (wrong business)', format($q$select shipment_set_status(%s,%s,'booked',null,gen_random_uuid())$q$,:'bza',(:'rb'::jsonb->>'id')), 'shipment_not_found');
select tt.eq('T7 user A can write in A', 1, (select (currency_save(:'bza'::bigint,'GBP','পাউন্ড','Pound',2,true,gen_random_uuid())->>'id')::int > 0)::int);
select tt.as(:'ub');
select tt.eq('T7 user B sees only B', 1, (select count(*) from ie_businesses124()));
select tt.err('T7 user B cannot list A', format('select * from shipments_list(%s)', :'bza'), 'not allowed');
select tt.eq('T7 user B lists B', 2, (select count(*) from shipments_list(:'bzb'::bigint)));

\echo == T8 view-only and no-grant users
select tt.as(:'uav');
select tt.eq('T8 view-only user lists A', 3, (select count(*) from shipments_list(:'bza'::bigint)));
select tt.err('T8 view-only user cannot save', format($q$select shipment_save(%s,null,'import','V-1',null,'BDT',1,null,current_date,null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'not allowed');
select tt.err('T8 view-only user cannot change status', format($q$select shipment_set_status(%s,%s,'booked',null,gen_random_uuid())$q$,:'bza',:'s1'), 'not allowed');
select tt.err('T8 view-only user cannot enter a rate', format($q$select fx_rate_set(%s,'USD',1,null,null,gen_random_uuid())$q$,:'bza'), 'not allowed');
select tt.as(:'un');
select tt.err('T8 user with no grant cannot list', format('select * from shipments_list(%s)', :'bza'), 'not allowed');
select tt.eq('T8 user with no grant sees no business', 0, (select count(*) from ie_businesses124()));
set role anon;
select tt.err('T8 anon cannot call the list', format('select * from shipments_list(%s)', :'bza'), 'permission denied');
select tt.err('T8 anon cannot read the table', 'select count(*) from ie_shipments', 'permission denied');
reset role;
set role authenticated;
select tt.as(:'ua');
select tt.err('T8 signed-in user cannot read the table directly', 'select count(*) from ie_shipments', 'permission denied');
select tt.err('T8 signed-in user cannot insert directly', 'insert into ie_currencies (org_unit_id, code, name_bn) values (1, ''ZZZ'', ''x'')', 'permission denied');
reset role;
select tt.as(:'o');

\echo == T9 period lock
update rules set default_value = to_jsonb(to_char(date '2026-01-31', 'YYYY-MM-DD')) where key = 'period_closed_until';
select tt.t('T9 owner is never locked out', (select (shipment_save(:'bza'::bigint,null,'import','LOCK-OWN','x','BDT',1,null,date '2026-01-10',null,null,0,0,0,0,gen_random_uuid())->>'id') is not null));
select tt.as(:'ua');
select tt.err('T9 manager cannot save into a closed period', format($q$select shipment_save(%s,null,'import','LOCK-1','x','BDT',1,null,date '2026-01-10',null,null,0,0,0,0,gen_random_uuid())$q$,:'bza'), 'period_closed');
select tt.err('T9 manager cannot enter a rate dated in a closed period', format($q$select fx_rate_set(%s,'USD',100,date '2026-01-05',null,gen_random_uuid())$q$,:'bza'), 'period_closed');
select tt.t('T9 an open-period date still works', (select (shipment_save(:'bza'::bigint,null,'import','LOCK-2','x','BDT',1,null,date '2026-02-20',null,null,0,0,0,0,gen_random_uuid())->>'id') is not null));
select tt.as(:'o');
update rules set default_value = 'null'::jsonb where key = 'period_closed_until';

\echo == T10 no GL posting, no cross-business flows, nothing existing changed
select tt.t('T10 no journal entry or line was created by this module', (select n = (select count(*) from journal_lines) from jl0));
select tt.t('T10 our functions never write journal tables', not exists (select 1 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname ~ '(shipment|^ie_|^_ie_|currency_save|fx_rate)' and p.prosrc ~* 'journal_|acct_post'));
select tt.t('T10 can_loc and org_unit_scope untouched by this phase (still no ie reference)', pg_get_functiondef('public.can_loc'::regproc) !~* 'ie_|impexp');

\echo == T11 second paste = no change
create temp table k1 as select (select count(*) from ie_shipments) s_n, (select md5(string_agg(to_jsonb(s)::text, '|' order by id)) from ie_shipments s) s_h, (select count(*) from ie_currencies) c_n, (select count(*) from ie_fx_rates) f_n,
  (select count(*) from rules) r_n, (select count(*) from grant_defs) g_n, (select md5(to_jsonb(r)::text) from rules r where key = 'impexp_on') rule_h;
\i supabase/phase124.sql
select tt.t('T11 second paste: shipments, currencies, rates, rules, grants unchanged', (select s_n = (select count(*) from ie_shipments) and s_h = (select md5(string_agg(to_jsonb(s)::text, '|' order by id)) from ie_shipments s)
  and c_n = (select count(*) from ie_currencies) and f_n = (select count(*) from ie_fx_rates) and r_n = (select count(*) from rules) and g_n = (select count(*) from grant_defs) and rule_h = (select md5(to_jsonb(r)::text) from rules r where key='impexp_on') from k1));
select tt.t('T11 ... the rule is still ON (the owner value survives)', rule_on('impexp_on'));
select tt.is('T11 template status unchanged', 'needs_setup', (select status from business_templates where code = 'import_export'));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
