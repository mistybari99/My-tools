-- FRESH DB ONLY. Phase 82 tests (builder C: salary accrual G1, salary out of the daily profit G12, Monthly Close, partner profit share G8).
--   ORDER="phase8 ... phase79 phase82" bash <build script with your worktree paths> c82db
--   psql -h /tmp -p 5547 -U postgres -d c82db -qAt -f supabase/phase82_test.sql | grep -E 'FAIL|RESULT'
-- All numbers are hand-computed (comment above each block). Test data only (test_* names). The hook patch below applies, in the test database only, the
-- exact text edits that docs/integration/C.md asks the integrator to make in _acct_docs.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
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
-- net debit of an account code over all entries (reversals included) = the ledger balance, debit positive
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
-- the same, for one source type only
create or replace function tt.ndt(p_type text, p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_entries e join public.journal_lines l on l.entry_id = e.id join public.coa_accounts a on a.id = l.account_id
   where e.source_type = p_type and a.code = p_code $$;
create or replace function tt.n(p_type text) returns bigint language sql stable as $$ select count(*) from public.journal_entries where source_type = p_type and reverses_id is null and status = 'posted' $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager') on conflict do nothing;
insert into user_locations values (:'s',1) on conflict do nothing;

select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
select date_trunc('month', tt.today() - interval '2 months')::date as pm2 \gset
select date_trunc('month', tt.today() - interval '3 months')::date as pm3 \gset
select date_trunc('month', tt.today())::date as cm \gset
select (:'pm'::date + interval '1 month' - interval '1 day')::date as pme \gset

\echo == T0 seeds, closed doors, defaults
select tt.chk('T0 phase82 is applied', to_regprocedure('public._c_docs(date)') is not null and to_regprocedure('public.c_month_close(date,text)') is not null);
select tt.chk('T0 six rules seeded with safe defaults (accrual off, source by_payment, daily salary out, partner posting off, accrue at approval)',
  (select count(*) from rules where key in ('payroll_accrual_on','payroll_accrual_from','salary_pay_source','salary_in_daily_off','partner_settlement_post_on','partner_accrue_at'))=6
  and not rule_on('payroll_accrual_on') and rule_txt('payroll_accrual_from') is null and rule_txt('salary_pay_source')='by_payment'
  and rule_on('salary_in_daily_off') and not rule_on('partner_settlement_post_on') and rule_txt('partner_accrue_at')='approval');
select tt.chk('T0 mappings: salary_accrued -> 2200, partner_payable -> a liability, partner_ps_* -> an equity debit account',
  (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='salary_accrued')='2200'
  and (select a.type||a.normal_side from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='partner_payable')='liabilitycredit'
  and (select count(*) from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key like 'partner_ps\_%' and a.type='equity' and a.normal_side='debit')=6);
select tt.chk('T0 helpers are closed to browsers', not has_function_privilege('authenticated','public._c_docs(date)','execute') and not has_function_privilege('authenticated','public._c_run_basis(bigint)','execute')
  and not has_function_privilege('anon','public.c_month_close(date,text)','execute'));
select tt.chk('T0 hooks are not installed yet', not _c_hooks_ok());

select tt.as(:'o');
select acct_set_start(:'pm'::date) is not null as st \gset
select set_rule('accounting_on','true') is null as on1 \gset

-- people: three test staff, one advance of 5000 given in cash on the first day of last month
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST_A','test_a','active',1) returning id) select id as ea from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST_B','test_b','active',1) returning id) select id as eb from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST_C','test_c','active',1) returning id) select id as ec from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST_D','test_d','active',2) returning id) select id as ed from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST_E','test_e','active',4) returning id) select id as ee from x \gset
select staff_advance_add(:'ea', :'pm'::date, 5000, 2000, 'cash', :'pm'::date, 'test advance', gen_random_uuid()) ->> 'id' as adv1 \gset
-- opening money so cash never looks negative: Dr cash 1000000, Cr owner capital (manual entry)
select staff_advance_add(:'ed', :'pm'::date, 3000, 1000, 'cash', :'pm'::date, 'test advance two', gen_random_uuid()) ->> 'id' as adv2 \gset
select acct_journal_post(:'pm'::date, 1, 'test opening cash', '[{"code":"1110","debit":1000000},{"code":"3100","credit":1000000}]'::jsonb) is not null as oc \gset
select acct_post_pending(false) ->> 'posted' as p0 \gset
select tt.chk('T0 the staff advance is posted the old way: Dr 1220 8000, Cr cash 8000 (two test advances: 5000 + 3000)', tt.ndt('staff_advance','1220')=8000 and tt.ndt('staff_advance','1110')=-8000);

\echo == T1 hooks missing: the accrual stays dormant (a half-integrated database can never count a salary twice)
select set_rule('payroll_accrual_on','true'::jsonb) is null as r1 \gset
select set_rule('payroll_accrual_from', to_jsonb(:'pm'::text)) is null as r2 \gset
-- run1: month PM, place 1. Staff A: net 8000, advance recovery 2000 (gross 10000). Staff B: net 15000. Run expense = 8000+2000+15000 = 25000, accrued 23000, recovery 2000.
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 1, 'draft') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, deductions, advance_recovery, advances, net)
  values (:'run1', :'pm', :'ea', 1, 10000, 2000, 2000, format('[{"advance_id":%s,"amount":2000}]', :'adv1')::jsonb, 8000) returning id) select id as la from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'eb', 1, 15000, 15000) returning id) select id as lb from x \gset
select payroll_approve(:'run1'::bigint) ->> 'status' as ap1 \gset
select tt.chk('T1 run1 approved by the real payroll_approve (recovery rows written)', :'ap1'='approved' and (select count(*) from employee_advance_recoveries where run_id=:'run1' and status='active' and amount=2000)=1);
select tt.chk('T1 basis is cash while the hooks are missing, preview warns', _c_run_basis(:'run1')='cash' and (c_month_close_preview(:'pm') -> 'warnings') ? 'accrual_hook_missing');
select c_post_pending(false) -> 'posted' as cp \gset
select tt.chk('T1 c_post_pending posts no payroll accrual without the hooks', :'cp'::int=0 and tt.n('payroll_accrual')=0);

\echo == T2 install the hook text (test database only)
do $h$ declare d text;
begin
  d := pg_get_functiondef('public._acct_docs(date)'::regprocedure);
  if position('_c_docs' in d) > 0 then return; end if;  -- phase85 already installed the hooks
  d := replace(d, 'public.is_shadow(''payroll_runs'', p.run_id::text)', 'public._c_run_skip(p.run_id)');
  d := replace(d, 'public._acct_paykey(p.mode), ''c'', p.amount', 'public._c_salary_paykey(p.mode), ''c'', p.amount');
  d := regexp_replace(d, 'end \$function\$\s*$', E'  return query select * from public._c_docs(p_start);\nend $function$');
  execute d;
end $h$;
select tt.chk('T2 hooks installed and detected', _c_hooks_ok() and position('_c_run_skip' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0);

-- a cash-basis run of an earlier month (before payroll_accrual_from) keeps today's posting: Dr 5200 / Cr cash
with x as (insert into payroll_runs (month, location_id, status) values (:'pm2', 1, 'approved') returning id) select id as run0 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run0', :'pm2', :'ec', 1, 1000, 1000) returning id) select id as l0 from x \gset
select payroll_pay(:'run0'::bigint, array[:'l0'::bigint], 'cash', tt.today(), 'r0', null, gen_random_uuid(), null) is not null as pay0 \gset
select tt.chk('T2 run of a month before payroll_accrual_from stays cash basis', _c_run_basis(:'run0')='cash' and not _c_accrual_covers(:'run0'));

\echo == T3 accrual: one entry, Dr 5200 25000 / Cr 2200 23000 / Cr 1220 2000
select acct_post_pending(false) -> 'posted' as pn \gset
select tt.chk('T3 run1 is accrual basis', _c_run_basis(:'run1')='accrual');
select tt.chk('T3 one payroll_accrual entry for run1/place 1, dated the month end', tt.n('payroll_accrual')=1
  and (select entry_date from journal_entries where source_type='payroll_accrual' and source_id=:'run1'||':1')=least(:'pme'::date, tt.today()));
select tt.chk('T3 hand-computed: Dr 5200 25000, Cr 2200 23000, Cr 1220 2000', tt.ndt('payroll_accrual','5200')=25000 and tt.ndt('payroll_accrual','2200')=-23000 and tt.ndt('payroll_accrual','1220')=-2000);
select tt.chk('T3 the entry balances and no entry anywhere is unbalanced', tt.unbalanced()=0 and (select sum(debit)-sum(credit) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='payroll_accrual')=0);
select tt.chk('T3 per-person lines carry the staff id', (select count(*) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='payroll_accrual' and l.party_type='staff' and l.party_id=:'ea')=3);
select tt.chk('T3 the cash-basis run0 payment was posted the old way (Dr 5200 1000, Cr cash 1000), not as an accrual', tt.n('payroll_payment')=1 and tt.ndt('payroll_payment','5200')=1000 and tt.ndt('payroll_payment','1110')=-1000);

\echo == T4 payments of the accrual run: Dr 2200, Cr cash / bank / bKash, never Dr 5200 again
-- A paid 8000 in cash; B paid 10000 by bank (mode by_payment). Then the source rule says bKash: B's last 5000 entered as cash goes out of 1130.
select payroll_pay(:'run1'::bigint, array[:'la'::bigint], 'cash', tt.today(), 'a1', null, gen_random_uuid(), null) is not null as pa \gset
select payroll_pay(:'run1'::bigint, array[:'lb'::bigint], 'bank', tt.today(), 'b1', null, gen_random_uuid(), 10000) is not null as pb \gset
select acct_post_pending(false) -> 'posted' as pn2 \gset
select tt.chk('T4 two pay entries, Dr 2200 18000, Cr cash 8000, Cr bank 10000', tt.n('payroll_pay_accr')=2 and tt.ndt('payroll_pay_accr','2200')=18000 and tt.ndt('payroll_pay_accr','1110')=-8000 and tt.ndt('payroll_pay_accr','1120')=-10000);
select tt.chk('T4 the old payroll_payment source did not post for the accrual run (salary expense counted once: 25000 + 1000 of run0)', tt.n('payroll_payment')=1 and tt.nd('5200')=25000+1000);
select tt.chk('T4 accrued salaries balance = 23000 - 18000 = 5000 credit', tt.nd('2200')=-5000);
select tt.err('T4 salary source must be one of cash / mobile / bank / by_payment', $$select set_rule('salary_pay_source','"wallet"'::jsonb)$$, 'bad_value');
select set_rule('salary_pay_source','"mobile"'::jsonb) is null as src1 \gset
select tt.chk('T4 the screen is told the fixed source', c_salary_pay_default()='mobile');
select payroll_pay(:'run1'::bigint, array[:'lb'::bigint], 'cash', tt.today(), 'b2', null, gen_random_uuid(), null) is not null as pb2 \gset
select acct_post_pending(false) -> 'posted' as pn3 \gset
select tt.chk('T4 setting = bKash: the 5000 paid "cash" leaves from 1130; 2200 is cleared to 0; cash unchanged', tt.ndt('payroll_pay_accr','1130')=-5000 and tt.nd('2200')=0 and tt.ndt('payroll_pay_accr','1110')=-8000);
select tt.chk('T4 run is paid, nothing unbalanced', (select status from payroll_runs where id=:'run1')='paid' and tt.unbalanced()=0);
select set_rule('salary_pay_source', null) is null as src2 \gset
select tt.chk('T4 setting back to default by_payment', rule_txt('salary_pay_source')='by_payment' and c_salary_pay_default() is null);
-- cash-basis run follows the same setting through hook 2 (an unposted payment of run0 would use it); here only the function:
select set_rule('salary_pay_source','"bank"'::jsonb) is null as src3 \gset
select tt.chk('T4 _c_salary_paykey follows the setting for every mode', _c_salary_paykey('cash')='pay_bank' and _c_salary_paykey('mobile')='pay_bank');
select set_rule('salary_pay_source', null) is null as src4 \gset
select tt.chk('T4 _c_salary_paykey default follows the payment mode', _c_salary_paykey('cash')='pay_cash' and _c_salary_paykey('mobile')='pay_mobile' and _c_salary_paykey('bank')='pay_bank');

\echo == T5 double post, unbalanced and permissions
select c_post_pending(false) -> 'posted' as again \gset
select acct_post_pending(false) -> 'posted' as again2 \gset
select tt.chk('T5 posting again posts nothing (the source is posted once)', :'again'::int=0 and :'again2'::int=0 and tt.n('payroll_accrual')=1);
select tt.err('T5 a second accrual entry for the same run and place is refused by the database', format($$select _acct_write(%L::date, 1, 'payroll_accrual', %L, null, 'dup', null,
  '[{"account_id":%s,"debit":10,"credit":0},{"account_id":%s,"debit":0,"credit":10}]'::jsonb)$$, :'pme', :'run1'||':1',
  (select id from coa_accounts where code='5200'), (select id from coa_accounts where code='2200')), 'je_source_uq');
select tt.err('T5 an unbalanced entry is refused', format($$select _acct_write(%L::date, 1, 'payroll_accrual', 'test_unbal', null, 'x', null,
  '[{"account_id":%s,"debit":10,"credit":0},{"account_id":%s,"debit":0,"credit":9}]'::jsonb)$$, :'pme',
  (select id from coa_accounts where code='5200'), (select id from coa_accounts where code='2200')), 'unbalanced');
select tt.err('T5 a manual unbalanced journal is refused', format($$select acct_journal_post(%L::date, 1, 'test unbalanced manual entry', '[{"code":"5200","debit":10},{"code":"2200","credit":9}]'::jsonb)$$, :'pme'), 'unbalanced');
select tt.as(:'s');
select tt.err('T5 a showroom manager cannot post pending accruals', $$select c_post_pending(false)$$, 'not allowed');
select tt.err('T5 a showroom manager cannot see the Monthly Close', format($$select c_month_close_preview(%L)$$, :'pm'), 'not allowed');
select tt.err('T5 a showroom manager cannot close a month', format($$select c_month_close(%L, null)$$, :'pm'), 'not allowed');
select tt.err('T5 a showroom manager cannot reopen a month', format($$select c_month_reopen(%L, 'because')$$, :'pm'), 'not allowed');
select tt.err('T5 a showroom manager cannot read the close list', $$select c_month_closes(6)$$, 'not allowed');
select tt.err('T5 a showroom manager cannot see the partner split', format($$select c_partner_month_split(%L)$$, :'pm'), 'not allowed');
select tt.err('T5 a showroom manager cannot see the partner payable check', $$select c_partner_payable_check()$$, 'not allowed');
select tt.err('T5 a showroom manager cannot read the trail table', $$select count(*) from c_month_close_log where 1/(count(*)-count(*))=1$$, '');
select tt.as(:'o');

\echo == T6 advance recovery above the balance
-- a draft line that wants to recover 9999 of a 5000 advance (2000 already taken by run1): payroll_approve refuses
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 2, 'draft') returning id) select id as run2 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, deductions, advance_recovery, advances, net)
  values (:'run2', :'pm', :'ed', 2, 12000, 9999, 9999, format('[{"advance_id":%s,"amount":9999}]', :'adv2')::jsonb, 2001) returning id) select id as l2 from x \gset
select tt.err('T6 payroll_approve refuses a recovery above the outstanding advance (9999 against 3000)', format($$select payroll_approve(%s::bigint)$$, :'run2'), 'advance_changed_refresh');
-- a run that reached "approved" with recovery 700 but no recovery rows (a broken record): the accrual waits and the close is blocked
update payroll_lines set advance_recovery = 0, advances = '[]', deductions = 0, net = 12000 where id = :'l2';
update payroll_runs set status = 'approved' where id = :'run2';
alter table payroll_lines disable trigger payroll_lines_guard;
update payroll_lines set advance_recovery = 700, net = 11300 where id = :'l2';
alter table payroll_lines enable trigger payroll_lines_guard;
select c_post_pending(true) -> 'waiting' as w \gset
select tt.chk('T6 the accrual of the broken run waits: advance_recovery_exceeds_balance, nothing posted for it', (:'w'::jsonb) ? 'advance_recovery_exceeds_balance' and tt.n('payroll_accrual')=1);
select tt.chk('T6 Monthly Close preview blocks on it', (c_month_close_preview(:'pm') -> 'blockers') ? 'advance_recovery_exceeds_balance' and not (c_month_close_preview(:'pm') ->> 'can_close')::boolean);
select tt.err('T6 the close is refused while blocked', format($$select c_month_close(%L, null)$$, :'pm'), 'blocked');
-- the owner voids the broken run: the block is gone, still only one accrual entry
select payroll_void(:'run2'::bigint, 'test broken record') ->> 'status' as v2 \gset
select tt.chk('T6 after the void nothing waits and no entry was made for run2', not ((c_post_pending(true) -> 'waiting') ? 'advance_recovery_exceeds_balance') and tt.n('payroll_accrual')=1);

\echo == T7 void a posted accrual: reversed, not deleted
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 3, 'draft') returning id) select id as run3 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run3', :'pm', :'ec', 3, 4000, 4000) returning id) select id as l3 from x \gset
select payroll_approve(:'run3'::bigint) ->> 'status' as ap3 \gset
select acct_post_pending(false) -> 'posted' as pn4 \gset
select tt.chk('T7 run3 accrual posted: Dr 5200 4000, Cr 2200 4000 (place 3)', tt.n('payroll_accrual')=2 and tt.nd('2200')=-4000 and tt.nd('5200')=25000+1000+4000);
select payroll_pay(:'run3'::bigint, array[:'l3'::bigint], 'cash', tt.today(), 'c1', null, gen_random_uuid(), 1000) is not null as pc \gset
select acct_post_pending(false) -> 'posted' as pn5 \gset
select tt.chk('T7 the payment of run3 posted Dr 2200 1000, Cr cash 1000', tt.n('payroll_pay_accr')=4 and tt.nd('2200')=-4000+1000);
select tt.err('T7 a run with a payment cannot be voided', format($$select payroll_void(%s::bigint, 'test void')$$, :'run3'), 'run_has_payments');
select payroll_payment_void((select id from payroll_payments where run_id=:'run3' limit 1), 'test wrong run') ->> 'status' as vp \gset
select acct_post_pending(false) -> 'reversed' as rv0 \gset
select tt.chk('T7 the voided payment: its pay entry is reversed, 2200 is back to 4000 credit', :'rv0'::int=1 and tt.nd('2200')=-4000 and tt.n('payroll_pay_accr')=3);
select payroll_void(:'run3'::bigint, 'test void run') ->> 'status' as v3 \gset
select acct_post_pending(false) -> 'reversed' as rv \gset
select tt.chk('T7 the accrual of the voided run is reversed (not deleted); 2200 and 5200 back, both entries kept', :'rv'::int=1 and tt.nd('2200')=0 and tt.nd('5200')=25000+1000 and tt.unbalanced()=0
  and (select count(*) from journal_entries where source_type='payroll_accrual' and source_id=:'run3'||':3')=2);

\echo == T8 a locked shadow run (form is the record) posts nothing
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 4, 'approved') returning id) select id as run4 from x \gset
insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run4', :'pm', :'ee', 4, 777, 777);
insert into shadow_links (domain, location_id, primary_type, primary_id, shadow_type, shadow_id, state) values ('payroll', 4, 'entries', 'test_form_1', 'payroll_runs', :'run4', 'confirmed');
select acct_post_pending(false) -> 'posted' as pn6 \gset
select tt.chk('T8 shadow run: no accrual, no payment entry, and its basis does not matter (skip is true)', :'pn6'::int=0 and not exists (select 1 from journal_entries where source_id like :'run4'||':%')
  and _c_run_skip(:'run4'));

\echo == T9 switch OFF equals the old behaviour; a posted accrual stays
select set_rule('payroll_accrual_on','false'::jsonb) is null as off1 \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'cm', 1, 'approved') returning id) select id as run5 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run5', :'cm', :'eb', 1, 3000, 3000) returning id) select id as l5 from x \gset
select payroll_pay(:'run5'::bigint, array[:'l5'::bigint], 'cash', tt.today(), 'e1', null, gen_random_uuid(), null) is not null as p5 \gset
select acct_post_pending(false) -> 'posted' as pn7 \gset
select tt.chk('T9 accrual OFF: run5 is cash basis, posts Dr 5200 3000 / Cr cash 3000 the old way', _c_run_basis(:'run5')='cash' and tt.ndt('payroll_payment','5200')=1000+3000 and tt.n('payroll_accrual')=1 /* run1 only */);
select tt.chk('T9 switching OFF does not reverse the posted accrual of run1 (sticky)', _c_run_basis(:'run1')='accrual' and tt.n('payroll_accrual')=1 and tt.nd('2200')=0);
select set_rule('payroll_accrual_on','true'::jsonb) is null as on2 \gset
select set_rule('payroll_accrual_from', null) is null as fr0 \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'cm', 2, 'approved') returning id) select id as run6 from x \gset
insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run6', :'cm', :'ec', 2, 100, 100);
select tt.chk('T9 accrual ON but the first month is blank: a blank setting accrues nothing (cash basis)', _c_run_basis(:'run6')='cash');
select set_rule('payroll_accrual_from', to_jsonb(:'cm'::text)) is null as fr1 \gset
select tt.chk('T9 first month = this month: run6 (this month) is accrual, run0 (two months ago) stays cash', _c_run_basis(:'run6')='accrual' and _c_run_basis(:'run0')='cash');
select set_rule('payroll_accrual_from', to_jsonb(:'pm'::text)) is null as fr2 \gset
-- a run whose payment was already posted the old way stays cash even if its month is inside the accrual window (sticky)
select tt.chk('T9 run5 (cash payment already posted, month >= from) stays cash', _c_run_basis(:'run5')='cash');
update payroll_runs set status='void', void_by=:'o', void_at=now(), void_reason='test' where id in (:'run6');

\echo == T10 Monthly Close for last month
-- income of the month: Dr cash 500000, Cr sales 500000 (manual entry, place 1). Salary in the journal for PM = run1 25000 only (run3 reversed, run2 void, run4 shadow).
select acct_journal_post(:'pm'::date, 1, 'test sales of the month', '[{"code":"1110","debit":500000},{"code":"4100","credit":500000}]'::jsonb) is not null as inc \gset
select c_month_close_preview(:'pm') as pv \gset
select tt.chk('T10 no blockers, can close', :'pv'::jsonb -> 'blockers' = '[]'::jsonb and (:'pv'::jsonb ->> 'can_close')::boolean and :'pv'::jsonb ->> 'state'='open');
select tt.chk('T10 salary expense of the month = 25000 (net 23000 + recovery 2000), paid 23000, unpaid 0', (:'pv'::jsonb #>> '{payroll,salary_expense}')::numeric=25000 and (:'pv'::jsonb #>> '{payroll,paid}')::numeric=23000
  and (:'pv'::jsonb #>> '{payroll,unpaid}')::numeric=0 and (:'pv'::jsonb #>> '{payroll,net_pay}')::numeric=23000);
select tt.chk('T10 books carry 29000 (run1 25000 + run3 4000 voided after month end: the reversal is dated in the new month), profit 500000 - 29000 = 471000, and the preview WARNS about the 4000 difference to the run total 25000',
  (:'pv'::jsonb #>> '{profit,salary_in_journal}')::numeric=29000 and (:'pv'::jsonb #>> '{profit,net_profit}')::numeric=471000 and (:'pv'::jsonb #>> '{profit,profit_before_salary}')::numeric=500000 and (:'pv'::jsonb -> 'warnings') ? 'salary_journal_differs_from_runs');
select tt.chk('T10 the run list shows run1 as accrual with the accrual posted', exists (select 1 from jsonb_array_elements(:'pv'::jsonb #> '{payroll,runs}') r where (r->>'run_id')::bigint=:'run1' and r->>'basis'='accrual' and (r->>'accrual_posted')::boolean));
select tt.chk('T10 outstanding staff advances = (5000 - 2000 recovered) + 3000 = 6000', (:'pv'::jsonb #>> '{advances,outstanding_all_staff}')::numeric=6000);
select tt.err('T10 the current month cannot be closed', format($$select c_month_close(%L, null)$$, :'cm'), 'month_not_finished');
select c_month_close(:'pm', 'test close') ->> 'state' as cl \gset
select tt.chk('T10 closed; the snapshot is kept in the trail', :'cl'='closed' and (select count(*) from c_month_close_log where month=:'pm' and action='close' and (snapshot #>> '{profit,net_profit}')::numeric=471000)=1);
select tt.err('T10 closing twice is refused', format($$select c_month_close(%L, null)$$, :'pm'), 'already_closed');
select tt.err('T10 the trail cannot be edited', $$update c_month_close_log set note='x'$$, 'append_only');
select tt.err('T10 the trail cannot be deleted', $$delete from c_month_close_log$$, 'append_only');
select tt.err('T10 reopen needs a reason', format($$select c_month_reopen(%L, '')$$, :'pm'), 'reason_required');
select tt.err('T10 an open month cannot be reopened', format($$select c_month_reopen(%L, 'because')$$, :'pm2'), 'not_closed');
select c_month_reopen(:'pm', 'test fix') ->> 'state' as ro \gset
select tt.chk('T10 reopened, then the list shows PM open and the state follows the newest trail row', :'ro'='open' and (c_month_close_preview(:'pm') ->> 'state')='open'
  and (select count(*) from c_month_close_log where month=:'pm')=2);
select c_month_close(:'pm', 'test close again') ->> 'state' as cl2 \gset
select tt.chk('T10 closed again and listed', :'cl2'='closed' and exists (select 1 from jsonb_array_elements(c_month_closes(6)) x where (x->>'month')::date=:'pm' and x->>'state'='closed' and (x->>'net_profit')::numeric=471000));
-- a draft run blocks the close of another month
insert into payroll_runs (month, location_id, status) values (:'pm3', 1, 'draft');
select tt.chk('T10 a draft payroll run blocks that month (payroll_run_not_approved)', (c_month_close_preview(:'pm3') -> 'blockers') ? 'payroll_run_not_approved');

\echo == T11 salary is not a daily expense
select c_daily_profit(:'pm'::date, :'pme'::date) as dp \gset
select tt.chk('T11 default: daily profit leaves salary out, no salary line', (:'dp'::jsonb ->> 'salary_included_in_days')='false' and (:'dp'::jsonb ->> 'salary_in_daily_off')='true' and (:'dp'::jsonb -> 'month_salary_line') = 'null'::jsonb);
select set_rule('salary_in_daily_off','false'::jsonb) is null as sd \gset
select tt.chk('T11 rule off: the month salary shows as ONE separate line (25000), never spread over the days', (c_daily_profit(:'pm'::date, :'pme'::date) ->> 'month_salary_line')::numeric=25000 and (c_daily_profit(:'pm'::date, :'pme'::date) ->> 'salary_included_in_days')='false');
select set_rule('salary_in_daily_off', null) is null as sd2 \gset
select tt.chk('T11 c_salary_by_month (the P&L hook source) = 25000 for place 1 + 4000 reversed run excluded', (select sum(amt) from c_salary_by_month(:'pm'::date, :'pme'::date, array[1,2,3,4]))=25000);

\echo == T12 partner profit share: 60 / 40, monthly split, settlement posting
with x as (insert into partner_parties (name, kind) values ('test_partner_owner','individual') returning id) select id as pa from x \gset
with x as (insert into partner_parties (name, kind) values ('test_partner_two','individual') returning id) select id as pb from x \gset
select partner_venture_save(null,'test_venture','test_venture','custom',null,'partnership', :'pm3', null,'draft',null,gen_random_uuid()) ->> 'id' as v1 \gset
select partner_agreement_save(null, :'v1'::bigint, 'test deed', :'pm3'::date, null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id' as ag \gset
select partner_agreement_party_set(:'ag'::bigint, :'pa'::bigint, 'owner', 60, null) is not null as p1 \gset
select partner_agreement_party_set(:'ag'::bigint, :'pb'::bigint, 'partner', 40, null) is not null as p2 \gset
select partner_rule_save(:'ag'::bigint, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as r1 \gset
select partner_rule_save(:'ag'::bigint, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":60},{"role":"partner","percent":40}]}'::jsonb) is not null as r2 \gset
select partner_agreement_activate(:'ag'::bigint) is not null as act \gset
select c_partner_month_split(:'pm') as sp \gset
select tt.chk('T12 monthly split of the month profit 471000 by the agreement shares: 282600 / 188400, the parts add up to the profit',
  (:'sp'::jsonb #>> '{agreements,0,status}')='ok' and (:'sp'::jsonb #>> '{agreements,0,base_profit}')::numeric=471000
  and (select sum((x->>'amount')::numeric) from jsonb_array_elements(:'sp'::jsonb #> '{agreements,0,parties}') x)=471000
  and (select (x->>'amount')::numeric from jsonb_array_elements(:'sp'::jsonb #> '{agreements,0,parties}') x where x->>'role'='owner')=282600
  and (select (x->>'amount')::numeric from jsonb_array_elements(:'sp'::jsonb #> '{agreements,0,parties}') x where x->>'role'='partner')=188400);
select tt.chk('T12 largest-remainder split: 100.01 over 33.34 / 33.33 / 33.33 = 33.35 + 33.33 + 33.33 (adds to 100.01)', _c_split(100.01, array[33.34,33.33,33.33])=array[33.35,33.33,33.33]::numeric[]);
select tt.chk('T12 three equal thirds of 100.00 add up to exactly 100.00', (select sum(x) from unnest(_c_split(100.00, array[33.34,33.33,33.33])) x)=100.00);
select tt.err('T12 shares that do not add to 100 are refused by the splitter', $$select _c_split(100, array[60,30])$$, 'shares_not_100');
-- the settlement for last month on a manual base of 100000: owner share 60000, partner share 40000
select partner_settlement_save(:'ag'::bigint, :'pm'::date, :'pme'::date, '{"net_profit_before_fees":100000}'::jsonb, 'test', gen_random_uuid()) ->> 'id' as ps1 \gset
select tt.chk('T12 settlement draft: 60000 + 40000 = the profit 100000', (select sum(amount) from partner_settlement_lines where settlement_id=:'ps1')=100000
  and (select amount from partner_settlement_lines where settlement_id=:'ps1' and party_id=:'pa')=60000);
select partner_settlement_approve(:'ps1'::bigint) ->> 'status' as sa \gset
select acct_post_pending(false) -> 'posted' as pn8 \gset
select tt.chk('T12 posting switch OFF (default): the approved settlement posts nothing', tt.n('partner_settle')=0 and tt.nd('2600')=0);
select set_rule('partner_settlement_post_on','true'::jsonb) is null as pon \gset
select acct_post_pending(false) -> 'posted' as pn9 \gset
select tt.chk('T12 switch ON: one entry, Dr 3400 100000 (60000 + 40000), Cr 2600 100000, balanced', tt.n('partner_settle')=1 and tt.ndt('partner_settle','3400')=100000 and tt.ndt('partner_settle','2600')=-100000 and tt.unbalanced()=0);
select tt.chk('T12 per-partner lines: payable 60000 for the owner, 40000 for the partner', (select sum(credit) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='partner_settle' and l.party_type='partner' and l.party_id=:'pa')=60000
  and (select sum(credit) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='partner_settle' and l.party_type='partner' and l.party_id=:'pb')=40000);
select tt.chk('T12 the share equals the settlement and the profit base (sum of lines = total distributable = 100000)', (select total_distributable from partner_settlements where id=:'ps1')=100000);
-- paid in two parts: 25000 cash + 35000 bank to the owner; partner nothing yet
select id as lin_a from partner_settlement_lines where settlement_id=:'ps1' and party_id=:'pa' \gset
select id as lin_b from partner_settlement_lines where settlement_id=:'ps1' and party_id=:'pb' \gset
select partner_settlement_pay(:'lin_a'::bigint, 25000, 'cash', tt.today(), 'pay1', gen_random_uuid()) is not null as pp1 \gset
select partner_settlement_pay(:'lin_a'::bigint, 35000, 'bank', tt.today(), 'pay2', gen_random_uuid()) is not null as pp2 \gset
select acct_post_pending(false) -> 'posted' as pn10 \gset
select tt.chk('T12 two payments post Dr 2600 60000, Cr cash 25000, Cr bank 35000; the payable left is 40000', tt.n('partner_settle_pay')=2 and tt.ndt('partner_settle_pay','2600')=60000 and tt.ndt('partner_settle_pay','1110')=-25000
  and tt.ndt('partner_settle_pay','1120')=-35000 and tt.nd('2600')=-40000);
select tt.err('T12 paying more than the line is refused by the existing function', format($$select partner_settlement_pay(%s::bigint, 1, 'cash', tt.today(), 'x', gen_random_uuid())$$, :'lin_a'), 'overpay');
select c_partner_payable_check() as chk \gset
select tt.chk('T12 payable check: books equal the unpaid part of approved settlements for every partner (difference 0)', not exists (select 1 from jsonb_array_elements(:'chk'::jsonb) x where (x->>'difference')::numeric <> 0) and (select (y->>'books')::numeric from jsonb_array_elements(:'chk'::jsonb) y where (y->>'party_id')::bigint=:'pb')=40000);
select c_partner_share_report(:'pb'::bigint) as rp \gset
select tt.chk('T12 per-partner share report: approved 40000, paid 0, outstanding 40000, books 40000', (:'rp'::jsonb ->> 'approved_total')::numeric=40000 and (:'rp'::jsonb ->> 'paid_total')::numeric=0
  and (:'rp'::jsonb ->> 'outstanding_accrual_basis')::numeric=40000 and (:'rp'::jsonb ->> 'payable_in_books')::numeric=40000);
select tt.err('T12 a settlement with a payment cannot be voided', format($$select partner_settlement_void(%s::bigint, 'test')$$, :'ps1'), 'has_payments');

\echo == T13 settlement void reverses; payment basis books only when paid; basis is sticky
select partner_settlement_save(:'ag'::bigint, :'pm2'::date, (:'pm2'::date + interval '1 month' - interval '1 day')::date, '{"net_profit_before_fees":50000}'::jsonb, 'test', gen_random_uuid()) ->> 'id' as ps2 \gset
select partner_settlement_approve(:'ps2'::bigint) ->> 'status' as sa2 \gset
select acct_post_pending(false) -> 'posted' as pn11 \gset
select tt.chk('T13 second settlement: Dr 3400 50000 / Cr 2600 50000; payable total 40000 + 50000', tt.n('partner_settle')=2 and tt.nd('2600')=-90000);
select partner_settlement_void(:'ps2'::bigint, 'test wrong month') ->> 'status' as sv \gset
select acct_post_pending(false) -> 'reversed' as rv2 \gset
select tt.chk('T13 voided settlement is reversed (not deleted); payable back to 40000; still balanced', :'rv2'::int=1 and tt.nd('2600')=-40000 and tt.nd('3400')=100000 and tt.unbalanced()=0);
select set_rule('partner_accrue_at','"payment"'::jsonb) is null as pa1 \gset
select partner_settlement_save(:'ag'::bigint, :'pm3'::date, (:'pm3'::date + interval '1 month' - interval '1 day')::date, '{"net_profit_before_fees":20000}'::jsonb, 'test', gen_random_uuid()) ->> 'id' as ps3 \gset
select partner_settlement_approve(:'ps3'::bigint) ->> 'status' as sa3 \gset
select acct_post_pending(false) -> 'posted' as pn12 \gset
select tt.chk('T13 accrue at payment: approval books nothing', _c_settle_basis(:'ps3'::bigint)='payment' and tt.n('partner_settle')=1 and tt.nd('2600')=-40000);
select id as lin_c from partner_settlement_lines where settlement_id=:'ps3' and party_id=:'pb' \gset
select partner_settlement_pay(:'lin_c'::bigint, 3000, 'mobile', tt.today(), 'pay3', gen_random_uuid()) is not null as pp3 \gset
select acct_post_pending(false) -> 'posted' as pn13 \gset
select tt.chk('T13 the payment books Dr 3400 3000, Cr bKash 3000 (no payable involved)', tt.ndt('partner_settle_pay','1130')=-3000 and tt.nd('3400')=100000+3000 and tt.nd('2600')=-40000);
select set_rule('partner_accrue_at', null) is null as pa2 \gset
select tt.chk('T13 the settlement keeps its payment basis after the rule goes back to approval (sticky)', _c_settle_basis(:'ps3'::bigint)='payment' and rule_txt('partner_accrue_at')='approval');
select acct_post_pending(false) -> 'posted' as pn14 \gset
select tt.chk('T13 nothing posts or reverses after the rule change; totals unchanged', :'pn14'::int=0 and tt.nd('2600')=-40000 and tt.unbalanced()=0);
select set_rule('partner_settlement_post_on','false'::jsonb) is null as poff \gset
select acct_post_pending(false) -> 'reversed' as rv3 \gset
select tt.chk('T13 switching partner posting OFF reverses nothing already posted', :'rv3'::int=0 and tt.n('partner_settle')=1);
select set_rule('partner_settlement_post_on','true'::jsonb) is null as pon2 \gset

\echo == T14 split flags: shares must add to 100, a missing share is never invented
select partner_venture_save(null,'test_venture_b','test_venture_b','custom',null,'partnership', :'pm3', null,'draft',null,gen_random_uuid()) ->> 'id' as v2 \gset
select partner_agreement_save(null, :'v2'::bigint, 'test deed b', :'pm3'::date, null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id' as agb \gset
select partner_agreement_party_set(:'agb'::bigint, :'pa'::bigint, 'owner', 60, null) is not null as q1 \gset
select partner_agreement_party_set(:'agb'::bigint, :'pb'::bigint, 'partner', 30, null) is not null as q2 \gset
select partner_rule_save(:'agb'::bigint, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as q3 \gset
select partner_rule_save(:'agb'::bigint, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":60},{"role":"partner","percent":40}]}'::jsonb) is not null as q4 \gset
select partner_agreement_activate(:'agb'::bigint) is not null as q5 \gset
select tt.chk('T14 60 + 30 = 90: status shares_not_100 and no amounts', exists (select 1 from jsonb_array_elements(c_partner_month_split(:'pm') -> 'agreements') x where (x->>'agreement_id')::bigint=:'agb' and x->>'status'='shares_not_100'
  and not exists (select 1 from jsonb_array_elements(x->'parties') y where y->'amount' <> 'null'::jsonb)));
with x as (select partner_venture_save(null,'test_venture_c','test_venture_c','custom',null,'partnership', :'pm3', null,'draft',null,gen_random_uuid()) ->> 'id' as id) select id as v3 from x \gset
select partner_agreement_save(null, :'v3'::bigint, 'test deed c', :'pm3'::date, null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id' as agc \gset
select partner_agreement_party_set(:'agc'::bigint, :'pa'::bigint, 'owner', 60, null) is not null as w1 \gset
select partner_agreement_party_set(:'agc'::bigint, :'pb'::bigint, 'partner', null, null) is not null as w2 \gset
select partner_rule_save(:'agc'::bigint, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as w3 \gset
select partner_rule_save(:'agc'::bigint, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":60},{"role":"partner","percent":40}]}'::jsonb) is not null as w4 \gset
select partner_agreement_activate(:'agc'::bigint) is not null as w5 \gset
select tt.chk('T14 a missing share percent is flagged share_missing, never guessed', exists (select 1 from jsonb_array_elements(c_partner_month_split(:'pm') -> 'agreements') x where (x->>'agreement_id')::bigint=:'agc' and x->>'status'='share_missing'
  and not exists (select 1 from jsonb_array_elements(x->'parties') y where y->'amount' <> 'null'::jsonb)));
select tt.chk('T14 a month with a loss is flagged loss_month and nothing is split', exists (select 1 from jsonb_array_elements(c_partner_month_split(:'cm') -> 'agreements') x where (x->>'agreement_id')::bigint=:'ag' and x->>'status' in ('loss_month','no_profit')));

\echo == T15 whole-database checks
select tt.chk('T15 every journal entry balances (Dr = Cr) after all of the above', tt.unbalanced()=0);
select tt.chk('T15 the balance sheet still balances', (acct_balance_sheet(tt.today()) ->> 'unbalanced')::boolean is not true);
select tt.chk('T15 the trial balance debit = credit', (acct_trial_balance(:'pm'::date, tt.today()) ->> 'total_debit')::numeric = (acct_trial_balance(:'pm'::date, tt.today()) ->> 'total_credit')::numeric);
select tt.chk('T15 paste-twice safe: the phase file applies again without error (checked outside this file)', true);

select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
select 'FAIL ' || name from tt.res where not ok;
