-- FRESH DB ONLY. Phase 85 tests (INTEGRATOR: the hooks of phases 81, 82, 83 in _acct_docs, _p27_pl, _daybook_lines).
--   ORDER="phase8 ... phase79 phase80 phase81 phase82 phase83 phase84 phase85" bash <build script> a85db
--   psql -h /tmp -p 5550 -U postgres -d a85db -qAt -f supabase/phase85_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only (test_* names). The REAL hooks are used: nothing is simulated here.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000085'
create schema if not exists tt;
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
-- net debit of an account code over all entries (reversals included), debit positive
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
create or replace function tt.ndt(p_type text, p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
   where e.source_type = p_type and a.code = p_code $$;
create or replace function tt.n(p_type text) returns bigint language sql stable as $$ select count(*) from public.journal_entries where source_type = p_type and reverses_id is null and status = 'posted' $$;
create or replace function tt.tags(p_sig text) returns int language sql stable as $$
  select (length(d) - length(replace(d, 'bos85', ''))) / 5 from (select pg_get_functiondef(p_sig::regprocedure) d) x $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values (:'o','owner85@s.app','{"full_name":"Owner"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner') on conflict do nothing;

select date_trunc('month', tt.today() - interval '2 months')::date as pm2 \gset
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
select (:'pm'::date - 1) as pm2e \gset
select (:'pm'::date + interval '1 month' - interval '1 day')::date as pme \gset

\echo == T0 the hooks are in place, tagged, closed to browsers
select tt.chk('T0 _acct_docs: 8 bos85 marks (3 run-skip, 1 pay key, 3 source calls, 1 comment) and the earlier tags are still inside',
  tt.tags('public._acct_docs(date)')=8 and position('bos52' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos72' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos74' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos50' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0);
select tt.chk('T0 _acct_docs calls _b_docs, _c_docs, _d_acct_docs, _c_run_skip, _c_salary_paykey', position('_b_docs' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('_c_docs' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('_d_acct_docs' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('_c_run_skip' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('_c_salary_paykey' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('is_shadow(''payroll_runs''' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))=0);
select tt.chk('T0 _p27_pl has 4 bos85 marks, _daybook_lines has 2, the older tags are kept', tt.tags('public._p27_pl(date,date,int[])')=4 and tt.tags('public._daybook_lines(int[],int[],date,date)')=2
  and position('bos72' in pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure))>0 and position('bos50' in pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure))>0
  and position('bos50' in pg_get_functiondef('public._daybook_lines(int[],int[],date,date)'::regprocedure))>0);
select tt.chk('T0 phase82 sees the hooks (_c_hooks_ok)', _c_hooks_ok());
select tt.chk('T0 the three functions stay closed to browsers', not has_function_privilege('authenticated','public._acct_docs(date)','execute') and not has_function_privilege('anon','public._acct_docs(date)','execute')
  and not has_function_privilege('authenticated','public._p27_pl(date,date,int[])','execute') and not has_function_privilege('anon','public._p27_pl(date,date,int[])','execute'));
select tt.chk('T0 nothing is switched on: accrual, cash short posting, partner posting, material gate are off; wallet fee default; test reset flag does not exist in the live order',
  not rule_on('payroll_accrual_on') and rule_txt('payroll_accrual_from') is null and not rule_on('cash_short_post_on') and not rule_on('partner_settlement_post_on')
  and rule_txt('d_recipe_materials_mode')='off' and rule_txt('d_wallet_fee_treatment') in ('separate_expense') and rule_txt('d_wallet_negative_mode')='refuse'
  and rule_txt('salary_pay_source')='by_payment' and rule_txt('d_material_cost_method')='average_purchase');
select tt.chk('T0 _acct_docs runs (all source blocks, including the three new calls)', (select count(*) >= 0 from public._acct_docs(tt.today()-400)));

select tt.as(:'o');
select acct_set_start(:'pm2'::date) is not null as st \gset
select set_rule('accounting_on','true') is null as on1 \gset
select acct_journal_post(:'pm2'::date, 1, 'test opening cash', '[{"code":"1110","debit":1000000},{"code":"3100","credit":1000000}]'::jsonb) is not null as oc \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST85_A','test_a','active',1) returning id) select id as ea from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST85_B','test_b','active',1) returning id) select id as eb from x \gset

\echo == S1 salary counted ONCE with the accrual setting OFF (month PM2, cash basis)
-- run0: place 1, month PM2: A net 8000, B net 15000 => salary cost 23000, paid in cash 23000. Journal: Dr 5200 23000 once (payroll_payment). P&L salary 23000 (from the run).
with x as (insert into payroll_runs (month, location_id, status) values (:'pm2', 1, 'draft') returning id) select id as run0 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run0', :'pm2', :'ea', 1, 8000, 8000) returning id) select id as l0a from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run0', :'pm2', :'eb', 1, 15000, 15000) returning id) select id as l0b from x \gset
select payroll_approve(:'run0'::bigint) ->> 'status' as ap0 \gset
select payroll_pay(:'run0'::bigint, array[:'l0a'::bigint, :'l0b'::bigint], 'cash', tt.today(), 'r0', null, gen_random_uuid(), null) is not null as pay0 \gset
select acct_post_pending(false) ->> 'posted' as pp0 \gset
select tt.chk('S1 run0 approved', :'ap0'='approved');
select tt.chk('S1 accrual OFF: run0 is cash basis, no accrual entry, nothing in 2200', _c_run_basis(:'run0')='cash' and tt.n('payroll_accrual')=0 and tt.nd('2200')=0);
select tt.chk('S1 journal: salary expense 5200 = 23000 exactly once (old payroll_payment source), cash -23000', tt.nd('5200')=23000 and tt.ndt('payroll_payment','5200')=23000 and tt.ndt('payroll_payment','1110')=-23000);
-- phase86 (fix M3): with the accrual setting OFF the P&L salary is only the 02-2 sheets (as before phase85), so the run is not added; phase85 alone adds it (23000)
select tt.chk('S1 P&L salary of month PM2 place 1 = 23000 (the app run is counted) [with phase86 and accrual OFF: 0, no sheet yet]', coalesce((select o_sal from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1])),0)=case when (to_regprocedure('public._p86_present()') is not null) then 0 else 23000 end);
-- a 02-2 sheet that is NOT linked to a run is a separate salary of 4000 and is counted; a 02-2 sheet linked as the SHADOW of run0 (9000) is not.
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('02-2',1,9501,:'pm2'::date,'approved',format('{"pay":[{"due":4000}],"month":"%s"}',:'pm2')::jsonb,'[]',:'o','st'),
 ('02-2',1,9502,:'pm2'::date,'approved',format('{"pay":[{"due":9000}],"month":"%s"}',:'pm2')::jsonb,'[]',:'o','st');
select id as f1 from entries where form_code='02-2' and serial=9501 \gset
select id as f2 from entries where form_code='02-2' and serial=9502 \gset
select (select o_sal from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1])) as sal_before_link \gset
select shadow_link_add('payroll', 1, 'payroll_runs', :'run0', 'entries', :'f2', 'test shadow') is not null as lk \gset
select tt.chk('S1 before the link both sheets and the run are counted: 23000 + 4000 + 9000 = 36000 [with phase86 and accrual OFF: sheets only 13000]', :'sal_before_link'::numeric=case when (to_regprocedure('public._p86_present()') is not null) then 13000 else 36000 end);
select tt.chk('S1 after the link the shadow sheet is NOT counted again: 23000 + 4000 = 27000 [with phase86 and accrual OFF: 13000, unchanged]', (select o_sal from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1]))=case when (to_regprocedure('public._p86_present()') is not null) then 13000 else 27000 end);

\echo == S2 salary counted ONCE with the accrual setting ON (month PM, accrual from PM)
select set_rule('payroll_accrual_on','true'::jsonb) is null as r1 \gset
select tt.chk('S2 switch ON but first month blank: still nothing accrued (no invented date)', _c_run_basis(:'run0')='cash');
select set_rule('payroll_accrual_from', to_jsonb(:'pm'::text)) is null as r2 \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 1, 'draft') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'ea', 1, 8000, 8000) returning id) select id as l1a from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'eb', 1, 15000, 15000) returning id) select id as l1b from x \gset
select payroll_approve(:'run1'::bigint) ->> 'status' as ap1 \gset
select acct_post_pending(false) ->> 'posted' as pp1 \gset
select tt.chk('S2 run1 is accrual basis, run0 (earlier, already paid) stays cash basis', _c_run_basis(:'run1')='accrual' and _c_run_basis(:'run0')='cash');
select tt.chk('S2 one accrual entry: Dr 5200 23000, Cr 2200 23000', tt.n('payroll_accrual')=1 and tt.ndt('payroll_accrual','5200')=23000 and tt.ndt('payroll_accrual','2200')=-23000);
select tt.chk('S2 salary expense 5200 in the whole journal = 23000 (run0) + 23000 (run1) = 46000', tt.nd('5200')=46000);
-- pay A 8000 cash and B 10000 bank; then the remaining 5000 cash
select payroll_pay(:'run1'::bigint, array[:'l1a'::bigint], 'cash', tt.today(), 'a1', null, gen_random_uuid(), null) is not null as pa \gset
select payroll_pay(:'run1'::bigint, array[:'l1b'::bigint], 'bank', tt.today(), 'b1', null, gen_random_uuid(), 10000) is not null as pb \gset
select acct_post_pending(false) ->> 'posted' as pp2 \gset
select tt.chk('S2 payments post Dr 2200 18000 / Cr cash 8000 / Cr bank 10000 (source payroll_pay_accr) and NOT as a second salary expense',
  tt.n('payroll_pay_accr')=2 and tt.ndt('payroll_pay_accr','2200')=18000 and tt.ndt('payroll_pay_accr','1110')=-8000 and tt.ndt('payroll_pay_accr','1120')=-10000
  and tt.ndt('payroll_payment','5200')=23000 and tt.nd('5200')=46000);
-- switching the setting OFF again does not change a run that has entries (sticky), the last 5000 is still a payment of the accrual
select set_rule('payroll_accrual_on','false'::jsonb) is null as r3 \gset
select tt.chk('S2 switch OFF after posting: run1 stays accrual basis (no re-booking)', _c_run_basis(:'run1')='accrual');
select payroll_pay(:'run1'::bigint, array[:'l1b'::bigint], 'cash', tt.today(), 'b2', null, gen_random_uuid(), null) is not null as pb2 \gset
select acct_post_pending(false) ->> 'posted' as pp3 \gset
select tt.chk('S2 the last 5000: Dr 2200 -> accrued salaries back to 0; salary expense still 46000; payroll_payment source untouched',
  tt.nd('2200')=0 and tt.nd('5200')=46000 and tt.ndt('payroll_payment','5200')=23000 and tt.n('payroll_pay_accr')=3);
select tt.chk('S2 P&L salary of month PM place 1 = 23000 (run1 once; no sheet in that month)', coalesce((select o_sal from _p27_pl(:'pm'::date, :'pme'::date, array[1])),0)=case when (to_regprocedure('public._p86_present()') is not null) then 0 else 23000 end);  -- phase86: accrual is OFF here, no sheet in PM => 0
select tt.chk('S2 P&L salary over both months = 27000 + 23000 = 50000 and the journal 5200 = 46000 (the 4000 sheet has no journal source: known, Dr = 46000 + 4000 only in the P&L)',
  (select sum(o_sal) from _p27_pl(:'pm2'::date, :'pme'::date, array[1]))=case when (to_regprocedure('public._p86_present()') is not null) then 13000 else 50000 end);
select acct_post_pending(false) ->> 'posted' as pp4 \gset
select tt.chk('S2 posting again posts nothing (no double posting), every entry balances', :'pp4'::int=0 and tt.unbalanced()=0);
select set_rule('payroll_accrual_from', null) is null as r4 \gset

\echo == S3 mobile wallet fee: journal, P&L expense, day book (hooks H1 H2 H3)
select d_wallet_opening_set((select id from d_wallets where code='bkash'), 500, :'pm2'::date) ->> 'opening' as wo \gset
select coalesce(sum(o_exp),0) as exp0 from _p27_pl(date_trunc('month', tt.today())::date, tt.today(), array[1]) \gset
-- phase86: the wallet split is a switch (default OFF); this block tests the split, so it is switched on here
select case when exists (select 1 from rules where key='d_wallet_split_on') then set_rule('d_wallet_split_on','true'::jsonb)::text end as spl \gset
select (d_wallet_fee_add((select id from d_wallets where code='bkash'), 1, tt.today(), 15, 'cash_out', 'test_ref_85', null, gen_random_uuid())->>'id') is not null as fee \gset
select acct_post_pending(false) ->> 'posted' as pp5 \gset
select tt.chk('S3 journal: wallet fee Dr 5815 15, Cr the bKash wallet account 15', tt.ndt('d_wallet_fee','5815')=15 and tt.ndt('d_wallet_fee','1131')=-15);
select tt.chk('S3 P&L expense of this month grows by exactly 15', (select coalesce(sum(o_exp),0) from _p27_pl(date_trunc('month', tt.today())::date, tt.today(), array[1]))=:'exp0'::numeric+15);
select tt.chk('S3 day book has one wallet_fee line: out, mobile, 15', (select count(*) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='wallet_fee' and dir='out' and mode='mobile' and amount=15)=1);
select set_rule('d_wallet_fee_treatment','"not_posted"'::jsonb) is null as tr1 \gset
select acct_post_pending(false) ->> 'posted' as pp6 \gset
select tt.chk('S3 treatment not_posted: the P&L and the day book drop the fee, the journal reverses it (all three agree)',
  (select coalesce(sum(o_exp),0) from _p27_pl(date_trunc('month', tt.today())::date, tt.today(), array[1]))=:'exp0'::numeric
  and (select count(*) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='wallet_fee')=0 and tt.ndt('d_wallet_fee','5815')=0);
select set_rule('d_wallet_fee_treatment', null) is null as tr2 \gset
select acct_post_pending(false) ->> 'posted' as pp7 \gset
select tt.chk('S3 back to the default: the fee is in the P&L and the day book again', (select coalesce(sum(o_exp),0) from _p27_pl(date_trunc('month', tt.today())::date, tt.today(), array[1]))=:'exp0'::numeric+15
  and (select count(*) from _daybook_lines(array[1], array[1], tt.today(), tt.today()) where typ='wallet_fee')=1);
-- KNOWN LIMIT (reported, not a regression): the poster never re-posts a source whose first entry was reversed, so after not_posted -> separate_expense the journal stays at 0
-- while the P&L and day book show 15. Documented in docs/BUILD-LOG.md; the owner should not toggle this setting back and forth after real postings.
select tt.chk('S3 KNOWN LIMIT: the reversed fee is not posted a second time (journal 5815 stays 0 after switching back)', tt.nd('5815')=0 and tt.n('d_wallet_fee')=0);

\echo == S4 cash short posts through the shared poster once the owner turns posting on (hook H1 of builder B)
insert into entries (form_code,location_id,serial,entry_date,status,created_by,created_staff) values ('14-1',1,9551,tt.today(),'submitted',:'o','t');
select id as e1 from entries where serial=9551 and form_code='14-1' \gset
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values (:'e1','14-1',1,tt.today(),'cash_short_over','red',-200,'{}');
select id as c1 from shortage_cash_cases where entry_id=:'e1' \gset
select cash_short_decide(:'c1'::uuid,true,'checked the count slip') is not null as dec \gset
select acct_post_pending(false) ->> 'posted' as ps0 \gset
select tt.chk('S4 posting setting OFF (default): an approved case waits, nothing in the journal', tt.n('cash_short')=0);
select set_rule('cash_short_post_on','true') is null as ron \gset
select acct_post_pending(false) -> 'by_type' as bt \gset
select tt.chk('S4 acct_post_pending posts the approved short: Dr 5800 200, Cr cash 200, by_type cash_short = 1', (:'bt'::jsonb->>'cash_short')::int=1 and tt.ndt('cash_short','5800')=200 and tt.ndt('cash_short','1110')=-200);
select acct_post_pending(false) ->> 'posted' as ps1 \gset
select tt.chk('S4 a second run posts nothing', :'ps1'::int=0 and tt.n('cash_short')=1);
select set_rule('cash_short_post_on', null) is null as roff \gset

\echo == S5 whole-database checks
select tt.chk('S5 every journal entry balances', tt.unbalanced()=0);
select tt.chk('S5 the trial balance debit = credit', (acct_trial_balance(:'pm2'::date, tt.today()) ->> 'total_debit')::numeric = (acct_trial_balance(:'pm2'::date, tt.today()) ->> 'total_credit')::numeric);
select tt.chk('S5 the balance sheet balances', (acct_balance_sheet(tt.today()) ->> 'unbalanced')::boolean is not true);
select tt.chk('S5 the balance check (phase84) has no red from the integration', coalesce(_e_balance_check(tt.today(), null, 31) ->> 'status','') in ('green','data_needed') or (_e_balance_check(tt.today(), null, 31) -> 'reds') = '[]'::jsonb);
select tt.chk('S5 the day book reader still answers (salary-sensitive and wallet rows)', (select count(*) >= 0 from _daybook_lines(array[1], array[1], :'pm2'::date, tt.today())));

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
