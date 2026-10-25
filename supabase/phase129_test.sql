-- FRESH DB ONLY (canonical build incl. phase127 + phase129).  Phase 129 tests = tinting machine (shade formulas, tint jobs, stock, cost, customer shade history).
--   psql -h /tmp -p 5544 -U postgres -d <db> -qAt -f supabase/phase129_test.sql | grep -E 'FAIL|RESULT'   (run from the repository root)
\i tests/sql/e2e/00_common.sql
\set hwm '00000000-0000-0000-0000-000000000301'
\set hwv '00000000-0000-0000-0000-000000000302'
\set swm '00000000-0000-0000-0000-000000000303'
\set pam '00000000-0000-0000-0000-000000000304'
\set hwc '00000000-0000-0000-0000-000000000305'
\set cu1 '00000000-0000-0000-0000-00000000c001'
\echo == T0 setup: sweets + HARDWARE (h1) + PAINT (p1); base A 20 packs @800, colorant B 1000 ml @0.40, colorant C 500 ml @0.90
insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner@dl.app','{"full_name":"Owner"}'),(:'hwm','hwm@dl.app','{"full_name":"HwMgr"}'),(:'hwv','hwv@dl.app','{"full_name":"HwView"}'),
  (:'swm','swm@dl.app','{"full_name":"SweetsMgr"}'),(:'pam','pam@dl.app','{"full_name":"PaintMgr"}'),(:'hwc','hwc@dl.app','{"full_name":"HwCost"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'hwm','salesperson'),(:'hwv','salesperson'),(:'swm','salesperson'),(:'pam','salesperson'),(:'hwc','salesperson') on conflict do nothing;
select tt.as(:'o');
select org_unit_save(null, (select id from org_units where kind='group'), 'legal_entity', 'LE-DL', 'ডিএল কোম্পানি', 'DL Co', null, null, null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, '{"owner_pct":100}'::jsonb, '00000000-0000-0000-0000-0000000003a1') ->> 'id' as dle \gset
select org_unit_save(null, :'dle'::bigint, 'business', 'HARDWARE', 'হার্ডওয়্যার', 'Hardware', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000003a2') ->> 'id' as hbz \gset
select org_unit_save(null, :'dle'::bigint, 'business', 'PAINT', 'পেইন্ট', 'Paint', 'hardware_paint', 'active', null, null, 'BDT', 'Asia/Dhaka', '{}'::jsonb, null, '00000000-0000-0000-0000-0000000003a3') ->> 'id' as pbz \gset
insert into locations (code, name_bn, name_en, kind, org_unit_id) values ('hw1','হার্ড ১','Hardware 1','showroom',:'hbz'::bigint),('pt1','পেইন্ট ১','Paint 1','showroom',:'pbz'::bigint);
select id as h1 from locations where code='hw1' \gset
select id as p1 from locations where code='pt1' \gset
insert into user_locations values (:'hwm',:h1),(:'hwv',:h1),(:'hwc',:h1),(:'swm',1),(:'pam',:p1) on conflict do nothing;
insert into user_grants (user_id, grant_code, location_id) values (:'hwm','dealer_tint_manage',:h1),(:'hwm','dealer_tint_run',:h1),(:'hwv','dealer_tint_view',:h1),(:'hwc','dealer_tint_run',:h1),(:'hwc','view_cost',null),
  (:'swm','dealer_tint_manage',1),(:'swm','dealer_tint_run',1),(:'pam','dealer_tint_manage',:p1),(:'pam','dealer_tint_run',:p1);
insert into customers (id, mobile, name) values (:'cu1','01700000001','Rahim Traders'),('00000000-0000-0000-0000-00000000c002','01700000002','Karim Stores');
select id as ia from items order by code limit 1 \gset
select id as ib from items order by code offset 1 limit 1 \gset
select id as ic from items order by code offset 2 limit 1 \gset
select stock_post(:'ia', :h1, 20, 'purchase_in', 'test', 'seedA', 800) \gset
select stock_post(:'ib', :h1, 1000, 'purchase_in', 'test', 'seedB', 0.40) \gset
select stock_post(:'ic', :h1, 500, 'purchase_in', 'test', 'seedC', 0.90) \gset
select stock_post(:'ia', :p1, 5, 'purchase_in', 'test', 'seedAp', 800) \gset
select tt.t('T0 tables exist with RLS; browser role cannot write; anon none', (select count(*)=5 and bool_and(relrowsecurity) from pg_class where oid in ('public.dealer_shades'::regclass,'public.dealer_tint_formulas'::regclass,'public.dealer_tint_formula_lines'::regclass,'public.dealer_tint_jobs'::regclass,'public.dealer_tint_job_lines'::regclass))
  and not has_table_privilege('authenticated','public.dealer_tint_jobs','insert') and not has_table_privilege('authenticated','public.dealer_tint_jobs','update') and not has_table_privilege('anon','public.dealer_tint_jobs','select'));
select tt.t('T0 cost columns are not readable by the browser role', not has_column_privilege('authenticated','public.dealer_tint_jobs','cost_total','select') and not has_column_privilege('authenticated','public.dealer_tint_job_lines','cost','select')
  and not has_column_privilege('authenticated','public.dealer_tint_job_lines','unit_cost','select') and has_column_privilege('authenticated','public.dealer_tint_jobs','packs','select'));
select tt.t('T0 rule dealer_tint_on exists, OFF', (select kind='switch' and default_value='false'::jsonb from rules where key='dealer_tint_on') and not rule_on('dealer_tint_on'));
select tt.t('T0 three grants', (select count(*)=3 from grant_defs where grant_code in ('dealer_tint_view','dealer_tint_manage','dealer_tint_run')));
select tt.t('T0 stock seeded: A 20 @800 at H1', tt.qty((select code from items where id=:'ia'), :h1) = 20 and tt.avg((select code from items where id=:'ia'), :h1) = 800);
create temp table k0 as select (select md5(acct_trial_balance(null, null)::text)) tb, (select count(*) from stock_ledger where location_id = 1) sl1, (select count(*) from stock_ledger) sl;

\echo == T1 flag OFF refuses writes
select tt.as(:'hwm');
select tt.err('T1 formula save refused while off', format($q$select tint_formula_save(gen_random_uuid(), %s, 'BR-101', 'Brick red', %L, '4L', 1, jsonb_build_array(jsonb_build_object('item',%L,'qty',12.5)))$q$, :'hbz', :'ia', :'ib'), 'feature_off');
select tt.as(:'o'); update rules set value='true'::jsonb where key='dealer_tint_on'; select tt.as(:'hwm');

\echo == T2 formulas: validation, versions, idempotency
select tint_formula_save('00000000-0000-0000-0000-000000000a01', :'hbz'::bigint, ' br-101 ', 'Brick red', :'ia'::uuid, '4L', 1, jsonb_build_array(jsonb_build_object('item',:'ib','qty',12.5), jsonb_build_object('item',:'ic','qty',7.25)), 'first') ->> 'id' as f1 \gset
select tint_formula_save('00000000-0000-0000-0000-000000000a01', :'hbz'::bigint, ' br-101 ', 'Brick red', :'ia'::uuid, '4L', 1, jsonb_build_array(jsonb_build_object('item',:'ib','qty',12.5), jsonb_build_object('item',:'ic','qty',7.25)), 'first') as again \gset
select tt.t('T2 same key again: dup, one formula, one shade', (:'again'::jsonb->>'dup')::boolean and (select count(*)=1 from dealer_tint_formulas) and (select count(*)=1 from dealer_shades));
select tt.is('T2 shade code upper-cased and trimmed, version 1 active, 2 colorant lines', 'BR-101|1|active|2', (select s.shade_code||'|'||f.version||'|'||f.status||'|'||(select count(*) from dealer_tint_formula_lines where formula_id=f.id) from dealer_tint_formulas f join dealer_shades s on s.id=f.shade_id where f.id=:'f1'::uuid));
select tt.err('T2 no colorants refused', format($q$select tint_formula_save(gen_random_uuid(), %s, 'X1', null, %L, null, 1, '[]')$q$, :'hbz', :'ia'), 'lines_required');
select tt.err('T2 quantity 0 refused', format($q$select tint_formula_save(gen_random_uuid(), %s, 'X2', null, %L, null, 1, jsonb_build_array(jsonb_build_object('item',%L,'qty',0)))$q$, :'hbz', :'ia', :'ib'), 'bad_qty');
select tt.err('T2 the base cannot be its own colorant', format($q$select tint_formula_save(gen_random_uuid(), %s, 'X3', null, %L, null, 1, jsonb_build_array(jsonb_build_object('item',%L,'qty',1)))$q$, :'hbz', :'ia', :'ia'), 'colorant_is_base');
select tt.err('T2 duplicate colorant refused', format($q$select tint_formula_save(gen_random_uuid(), %s, 'X4', null, %L, null, 1, jsonb_build_array(jsonb_build_object('item',%L,'qty',1), jsonb_build_object('item',%L,'qty',2)))$q$, :'hbz', :'ia', :'ib', :'ib'), 'duplicate_colorant');
select tt.err('T2 base quantity 0 refused', format($q$select tint_formula_save(gen_random_uuid(), %s, 'X5', null, %L, null, 0, jsonb_build_array(jsonb_build_object('item',%L,'qty',1)))$q$, :'hbz', :'ia', :'ib'), 'bad_qty');
select tt.err('T2 unknown item refused', format($q$select tint_formula_save(gen_random_uuid(), %s, 'X6', null, %L, null, 1, jsonb_build_array(jsonb_build_object('item',gen_random_uuid(),'qty',1)))$q$, :'hbz', :'ia'), 'item_not_found');
select tt.eq('T2 a refused save left nothing behind (still 1 shade)', 1, (select count(*) from dealer_shades));
select tt.err('T2 formula lines cannot be edited', $$update dealer_tint_formula_lines set qty_per_pack = 1$$, 'append_only');

\echo == T3 dry run, then the job: stock, hand-computed cost
select tint_job_run(gen_random_uuid(), :h1, :'f1'::uuid, 3, :'cu1'::uuid, null, null, 4200.50, 'for Rahim', true) as dry \gset
select tt.t('T3 dry run: base 3, B 37.5, C 21.75; nothing short; wrote nothing', (:'dry'::jsonb->>'dry')::boolean and not (:'dry'::jsonb->>'short')::boolean
  and (select string_agg((x->>'qty'), ',' order by ord) from jsonb_array_elements(:'dry'::jsonb->'lines') with ordinality t(x, ord)) = '3.0000,37.5000,21.7500'
  and (select count(*) from dealer_tint_jobs) = 0 and tt.qty((select code from items where id=:'ia'), :h1) = 20);
select tt.t('T3 a user without the cost right gets no estimate', (:'dry'::jsonb->'estimated_cost') = 'null'::jsonb);
select tt.as(:'hwc');
select tt.eq('T3 a cost-right user sees the estimate 3x800 + 37.5x0.40 + 21.75x0.90 = 2434.575 -> 2434.58', 2434.58, (tint_job_run(gen_random_uuid(), :h1, :'f1'::uuid, 3, null, null, null, null, null, true)->>'estimated_cost')::numeric);
select tt.as(:'hwm');
select tint_job_run('00000000-0000-0000-0000-000000000b01', :h1, :'f1'::uuid, 3, :'cu1'::uuid, null, null, 4200.50, 'for Rahim') as j1 \gset
select tt.t('T3 job 1 done: not short, no cost shown to this user', (:'j1'::jsonb->>'status') = 'done' and (:'j1'::jsonb->'cost_total') = 'null'::jsonb);
select tt.eq('T3 stock A: 20 - 3 = 17', 17, tt.qty((select code from items where id=:'ia'), :h1));
select tt.eq('T3 stock B: 1000 - 37.5 = 962.5', 962.5, tt.qty((select code from items where id=:'ib'), :h1));
select tt.eq('T3 stock C: 500 - 21.75 = 478.25', 478.25, tt.qty((select code from items where id=:'ic'), :h1));
select tt.eq('T3 three ledger rows, reason issue_out, ref tint_job', 3, (select count(*) from stock_ledger where ref_type='tint_job' and ref_id=(:'j1'::jsonb->>'id') and reason='issue_out'));
select tint_job_run('00000000-0000-0000-0000-000000000b01', :h1, :'f1'::uuid, 3, :'cu1'::uuid, null, null, 4200.50, 'for Rahim') as j1b \gset
select tt.t('T3 same key again: dup, same job, stock not consumed twice', (:'j1b'::jsonb->>'dup')::boolean and :'j1b'::jsonb->>'id' = :'j1'::jsonb->>'id' and tt.qty((select code from items where id=:'ia'), :h1) = 17 and (select count(*)=1 from dealer_tint_jobs));
select tt.as(:'o');
select tt.eq('T3 owner: cost_total = 2400.00 + 15.00 + 19.58 (19.575 rounded per line) = 2434.58', 2434.58, (tint_job_cost((:'j1'::jsonb->>'id')::uuid)->>'cost_total')::numeric);
select tt.eq('T3 owner: cost per pack = 2434.58 / 3 = 811.5267', 811.5267, (tint_job_cost((:'j1'::jsonb->>'id')::uuid)->>'cost_per_pack')::numeric);
select tt.eq('T3 owner: margin = 4200.50 - 2434.58 = 1765.92', 1765.92, (tint_job_cost((:'j1'::jsonb->>'id')::uuid)->>'margin')::numeric);
select tt.is('T3 cost is known on every line', 'true', (tint_job_cost((:'j1'::jsonb->>'id')::uuid)->>'cost_known'));
select tt.as(:'hwm');
select tt.err('T3 a user without the cost right cannot read the job cost', format($q$select tint_job_cost(%L::uuid)$q$, :'j1'::jsonb->>'id'), 'not allowed');
select tt.err('T3 ... nor the cost report', format($q$select * from tint_cost_report(%s)$q$, :'hbz'), 'not allowed');
select tt.as(:'hwc');
select tt.eq('T3 a cost-right user can', 2434.58, (tint_job_cost((:'j1'::jsonb->>'id')::uuid)->>'cost_total')::numeric);
select tt.as(:'hwm');
select tt.is('T3 the formula is now used (frozen)', 'true', (select (used_at is not null)::text from dealer_tint_formulas where id=:'f1'::uuid));
select tt.err('T3 a used formula cannot be rewritten', $$update dealer_tint_formulas set base_qty_per_pack = 2$$, 'formula_frozen');

\echo == T4 rounding, new version, retired formula, shortage, block mode
select tint_job_run(gen_random_uuid(), :h1, :'f1'::uuid, 2.0005, :'cu1'::uuid) as j2 \gset
select tt.eq('T4 packs 2.0005 -> 2.001 (3 places)', 2.001, (select packs from dealer_tint_jobs where id = (:'j2'::jsonb->>'id')::uuid));
select tt.eq('T4 colorant B used = 2.001 x 12.5 = 25.0125', 25.0125, (select qty from dealer_tint_job_lines where job_id = (:'j2'::jsonb->>'id')::uuid and item_id = :'ib'::uuid));
select tt.eq('T4 stock B now 962.5 - 25.0125 = 937.4875', 937.4875, tt.qty((select code from items where id=:'ib'), :h1));
select tint_formula_save(gen_random_uuid(), :'hbz'::bigint, 'BR-101', null, :'ia'::uuid, '4L', 1, jsonb_build_array(jsonb_build_object('item',:'ib','qty',13), jsonb_build_object('item',:'ic','qty',7.25)), 'v2') ->> 'id' as f2 \gset
select tt.is('T4 version 2 is active, version 1 retired, still one shade', '2|retired|1', (select (select version::text from dealer_tint_formulas where id=:'f2'::uuid)||'|'||(select status from dealer_tint_formulas where id=:'f1'::uuid)||'|'||(select count(*)::text from dealer_shades)));
select tt.err('T4 a retired formula cannot be run', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1)$q$, :h1, :'f1'), 'formula_retired');
select tint_job_run(gen_random_uuid(), :h1, :'f2'::uuid, 1, :'cu1'::uuid) as j3 \gset
select tt.eq('T4 job on version 2 recorded with version 2', 2, (select formula_version from dealer_tint_jobs where id = (:'j3'::jsonb->>'id')::uuid));
select tint_formula_save(gen_random_uuid(), :'hbz'::bigint, 'GR-202', 'Grey', :'ia'::uuid, '4L', 1, jsonb_build_array(jsonb_build_object('item',:'ib','qty',5)), null) ->> 'id' as f3 \gset
select tint_job_run(gen_random_uuid(), :h1, :'f3'::uuid, 1, :'cu1'::uuid) as j4 \gset
select tt.eq('T4 stock A after 3 + 2.001 + 1 + 1 packs = 20 - 7.001 = 12.999', 12.999, tt.qty((select code from items where id=:'ia'), :h1));
select tint_job_run(gen_random_uuid(), :h1, :'f2'::uuid, 50, null, null, null, null, null, true) as dsh \gset
select tt.t('T4 dry run for 50 packs flags the shortage', (:'dsh'::jsonb->>'short')::boolean);
select tint_job_run('00000000-0000-0000-0000-000000000b09', :h1, :'f2'::uuid, 50) as jneg \gset
select tt.t('T4 mode warn: the job runs and stock goes negative (existing stock rule), a yellow exception is raised', tt.qty((select code from items where id=:'ia'), :h1) < 0 and exists (select 1 from exceptions where flag_code = 'stock_negative'));
select tint_job_void((:'jneg'::jsonb->>'id')::uuid, gen_random_uuid(), 'wrong qty') as vv \gset
select tt.eq('T4 void restores the stock exactly (12.999)', 12.999, tt.qty((select code from items where id=:'ia'), :h1));
select tt.as(:'o'); update rules set value='"block"'::jsonb where key='stock_negative_mode'; select tt.as(:'hwm');
select tt.err('T4 mode block: a job above the stock is refused (insufficient_stock)', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 50)$q$, :h1, :'f2'), 'insufficient_stock');
select tt.eq('T4 ... and nothing was written (jobs so far: 1,2,3,4 + the voided one = 5)', 5, (select count(*) from dealer_tint_jobs));
select tt.as(:'o'); update rules set value='"warn"'::jsonb where key='stock_negative_mode'; select tt.as(:'hwm');
select tt.err('T4 bad packs refused', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 0)$q$, :h1, :'f2'), 'bad_packs');
select tt.err('T4 job date more than 3 days back refused', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1, null, null, tt.today()-4)$q$, :h1, :'f2'), 'bad_date');
select tt.err('T4 future date refused', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1, null, null, tt.today()+1)$q$, :h1, :'f2'), 'bad_date');

\echo == T5 void, history per customer
select tint_job_void((:'j2'::jsonb->>'id')::uuid, gen_random_uuid(), 'customer cancelled') as v2 \gset
select tt.eq('T5 job 2 voided: stock B back to 962.5 - 13 - 5 = 944.5', 944.5, tt.qty((select code from items where id=:'ib'), :h1));
select tint_job_void((:'j2'::jsonb->>'id')::uuid, gen_random_uuid(), 'customer cancelled') as v2b \gset
select tt.t('T5 void again: dup, stock not restored twice', (:'v2b'::jsonb->>'dup')::boolean and tt.qty((select code from items where id=:'ib'), :h1) = 944.5);
select tt.err('T5 a void needs a reason', format($q$select tint_job_void(%L::uuid, gen_random_uuid(), '')$q$, :'j4'::jsonb->>'id'), 'reason_required');
select tt.eq('T5 the ledger kept the original rows and added reversals (6 rows for job 2)', 6, (select count(*) from stock_ledger where ref_type='tint_job' and ref_id=(:'j2'::jsonb->>'id')));
select tt.eq('T5 shade history of Rahim: 2 shades', 2, (select count(*) from tint_customer_shades(:'cu1'::uuid)));
select tt.is('T5 BR-101: voided job 2 not counted -> jobs 2 (job 1 + job 3), packs 4', '2|4.000', (select jobs||'|'||packs from tint_customer_shades(:'cu1'::uuid) where shade_code='BR-101'));
select tt.is('T5 last formula version used for BR-101 = 2', '2', (select last_formula_version::text from tint_customer_shades(:'cu1'::uuid) where shade_code='BR-101'));
select tt.eq('T5 job list for the business (not voided count 3 + 2 void)', 5, (select count(*) from tint_job_list(:'hbz'::bigint)));
select tt.eq('T5 job list filtered by customer (jobs 1-4; the shortage job had no customer)', 4, (select count(*) from tint_job_list(:'hbz'::bigint, null, null, :'cu1'::uuid)));
select tt.as(:'o');
select tt.eq('T5 cost report: BR-101 done jobs = job 1 (3 packs) + job 3 (1 pack): packs 4', 4, (select packs from tint_cost_report(:'hbz'::bigint) where shade_code='BR-101'));
select tt.eq('T5 cost report: BR-101 cost = 2434.58 + (800 + 13x0.40 + 7.25x0.90 = 811.725 -> 5.20 + 6.53 + 800.00 = 811.73) = 3246.31', 3246.31, (select cost_total from tint_cost_report(:'hbz'::bigint) where shade_code='BR-101'));
select tt.eq('T5 cost report: charge total 4200.50', 4200.50, (select charge_total from tint_cost_report(:'hbz'::bigint) where shade_code='BR-101'));

\echo == T6 two businesses isolated, owner sees both
select tt.as(:'pam');
select tint_formula_save(gen_random_uuid(), :'pbz'::bigint, 'BR-101', 'Brick red (paint)', :'ia'::uuid, '4L', 1, jsonb_build_array(jsonb_build_object('item',:'ib','qty',10))) ->> 'id' as pf \gset
select tt.t('T6 PAINT may use the same shade code: its own shade + formula', (select count(*) = 2 from dealer_shades where shade_code = 'BR-101'));
select tt.eq('T6 PAINT sees only its own formula', 1, (select count(*) from tint_formula_list(:'pbz'::bigint)));
select tt.err('T6 PAINT cannot list HARDWARE formulas', format($q$select * from tint_formula_list(%s)$q$, :'hbz'), 'not allowed');
select tt.err('T6 PAINT cannot read a HARDWARE formula', format($q$select tint_formula_get(%L::uuid)$q$, :'f2'), 'not allowed');
select tt.err('T6 PAINT cannot run a HARDWARE formula (its own location)', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1)$q$, :p1, :'f2'), 'not allowed');
select tt.err('T6 ... nor at a HARDWARE location', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1)$q$, :h1, :'f2'), 'not allowed');
select tt.err('T6 PAINT cannot create a formula in HARDWARE', format($q$select tint_formula_save(gen_random_uuid(), %s, 'Z1', null, %L, null, 1, jsonb_build_array(jsonb_build_object('item',%L,'qty',1)))$q$, :'hbz', :'ia', :'ib'), 'not allowed');
select tint_job_run(gen_random_uuid(), :p1, :'pf'::uuid, 2, '00000000-0000-0000-0000-00000000c002'::uuid) as pj \gset
select tt.eq('T6 PAINT stock A: 5 - 2 = 3 (HARDWARE stock untouched, 12.999)', 3, tt.qty((select code from items where id=:'ia'), :p1));
select tt.eq('T6 ... PAINT sees none of the HARDWARE jobs', 1, (select count(*) from tint_job_list(:'pbz'::bigint)));
select tt.eq('T6 ... the customer history seen by PAINT has only PAINT jobs even for the HARDWARE customer', 0, (select count(*) from tint_customer_shades(:'cu1'::uuid)));
select tt.err('T6 ... cannot void a HARDWARE job', format($q$select tint_job_void(%L::uuid, gen_random_uuid(), 'x')$q$, :'j4'::jsonb->>'id'), 'not allowed');
select tt.as(:'swm');
select tt.err('T6 a sweets user with grants cannot touch HARDWARE', format($q$select * from tint_formula_list(%s)$q$, :'hbz'), 'not allowed');
select tt.as(:'hwv');
select tt.eq('T6 view-only user lists HARDWARE jobs', 5, (select count(*) from tint_job_list(:'hbz'::bigint)));
select tt.err('T6 ... cannot run a job', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1)$q$, :h1, :'f2'), 'not allowed');
select tt.as(:'hwm'); set role authenticated;
select tt.t('T6 RLS: direct reads show only HARDWARE rows; cost columns refused', (select count(*) > 0 and bool_and(business_id = :'hbz'::bigint) from dealer_tint_jobs));
select tt.err('T6 reading cost_total directly is refused', $$select cost_total from dealer_tint_jobs$$, 'permission denied');
select tt.err('T6 no direct write', $$update dealer_tint_jobs set packs = 1$$, 'permission denied');
reset role; select tt.as(:'o'); set role authenticated;
select tt.eq('T6 owner reads both businesses directly', 2, (select count(distinct business_id) from dealer_tint_jobs));
reset role;

\echo == T6b business templates say what is built
select tt.t('T6b hardware_paint lists tinting / schemes / cheques as built and lists what is NOT built; status unchanged (not_implemented)', (select status = 'not_implemented' and modules @> '[{"code":"tinting","state":"built"}]'::jsonb
  and modules @> '[{"code":"bulk_item_import","state":"not_built"}]'::jsonb from business_templates where code = 'hardware_paint'));
select tt.t('T6b dealership: cheque + schemes built, vehicle stock not built; status unchanged', (select status = 'not_implemented' and modules @> '[{"code":"principal_schemes","state":"built"}]'::jsonb and modules @> '[{"code":"vehicle_stock_and_sales","state":"not_built"}]'::jsonb from business_templates where code = 'dealership'));
select tt.t('T6b the other templates were not touched', (select count(*) = 4 from business_templates where code in ('technology','construction','online_store','food_manufacturing') and (modules = '[]'::jsonb or code = 'food_manufacturing')));

\echo == T7 flag off, period lock, paste twice, sweets untouched
update rules set value='false'::jsonb where key='dealer_tint_on'; select tt.as(:'hwm');
select tt.err('T7 flag off: a real job refused', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1)$q$, :h1, :'f2'), 'feature_off');
select tt.t('T7 flag off: dry run still works', (tint_job_run(gen_random_uuid(), :h1, :'f2'::uuid, 1, null, null, null, null, null, true)->>'dry')::boolean);
select tt.err('T7 flag off: void refused', format($q$select tint_job_void(%L::uuid, gen_random_uuid(), 'x')$q$, :'j4'::jsonb->>'id'), 'feature_off');
select tt.as(:'o'); update rules set value='true'::jsonb where key='dealer_tint_on';
select set_rule('period_closed_until', to_jsonb(tt.today()::text)); select tt.as(:'hwm');
select tt.err('T7 closed period: a staff user cannot run a job dated inside it (period_closed)', format($q$select tint_job_run(gen_random_uuid(), %s, %L::uuid, 1)$q$, :h1, :'f2'), 'period_closed');
select tt.as(:'o'); select set_rule('period_closed_until', 'null'::jsonb);
create temp table cnt1 as select (select count(*) from dealer_shades) a, (select count(*) from dealer_tint_formulas) b, (select count(*) from dealer_tint_formula_lines) c, (select count(*) from dealer_tint_jobs) d,
  (select count(*) from dealer_tint_job_lines) e, (select count(*) from grant_defs) g, (select count(*) from rules) r, (select count(*) from stock_ledger) s;
reset role;
\i supabase/phase129.sql
select tt.t('T7 second paste: nothing added or lost', (select a = (select count(*) from dealer_shades) and b = (select count(*) from dealer_tint_formulas) and c = (select count(*) from dealer_tint_formula_lines) and d = (select count(*) from dealer_tint_jobs)
  and e = (select count(*) from dealer_tint_job_lines) and g = (select count(*) from grant_defs) and r = (select count(*) from rules) and s = (select count(*) from stock_ledger) from cnt1));
select tt.eq('T7 sweets location 1: no stock row came from tinting', 0, (select count(*) from stock_ledger where location_id = 1 and ref_type = 'tint_job'));
select tt.eq('T7 sweets stock ledger unchanged', 0, (select count(*) from stock_ledger where location_id = 1) - (select sl1 from k0));
select tt.t('T7 trial balance untouched (nothing here posts to the books)', (select tb = md5(acct_trial_balance(null, null)::text) from k0));
select tt.t('T7 no existing function mentions the tint tables', not exists (select 1 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname !~ 'tint|_dl_' and p.prosrc ~* 'dealer_tint|dealer_shades'));

\echo == RESULT
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.ea;
select 'FAILED: ' || step || ' exp=' || coalesce(expected,'') || ' act=' || coalesce(actual,'') from tt.ea where not ok;
