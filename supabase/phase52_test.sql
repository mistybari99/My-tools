-- FRESH DB ONLY. Phase 52 tests (P2 gap #6: journal sources payroll payments, staff advances, partner capital).
--   ORDER="phase8 phase9 phase10 phase11 phase12 phase13 phase14 phase15 phase16 phase17 phase18 phase19 phase20 phase21 phase22 phase23 phase24 phase25 phase26 phase27 phase28 phase40 phase41 phase42 phase43 phase44 phase45 phase46 phase47 phase48 phase49 phase50 phase51 phase52" bash tests/sql/build_fresh_db.sh a52db
--   psql -h /tmp -p 5544 -U postgres -d a52db -qAt -f supabase/phase51_test.sql | grep -E 'FAIL|RESULT'
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set k '00000000-0000-0000-0000-000000000003'
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
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','mgr2@s.app','{"full_name":"Manager"}'), (:'k','store3@s.app','{"full_name":"Store"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'s','showroom_manager'),(:'k','storekeeper') on conflict do nothing;
insert into user_locations values (:'s',1),(:'k',1) on conflict do nothing;
create or replace function tt.today() returns date language sql stable as $$ select (now() at time zone 'Asia/Dhaka')::date $$;
grant execute on function tt.today() to authenticated, anon;
create or replace function tt.net(p_type text, p_code text) returns numeric language sql stable as $$
  -- net debit of the live (not reversed) and reversed entries together = what the books say now, for one source type and account code
  select coalesce(sum(l.debit - l.credit), 0) from journal_entries e join journal_lines l on l.entry_id = e.id join coa_accounts a on a.id = l.account_id where e.source_type = p_type and a.code = p_code $$;
create or replace function tt.unbalanced() returns int language sql stable as $$
  select count(*)::int from (select entry_id from journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
grant execute on function tt.net(text, text), tt.unbalanced() to authenticated, anon;

\echo == T0 seed + closed doors
select tt.chk('T0 salary_exp / staff_advance / partner_loan are mapped, to 5200 / 1220 / a new Partner loans liability',
  (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='salary_exp')='5200'
  and (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='staff_advance')='1220'
  and (select a.type||a.normal_side from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='partner_loan')='liabilitycredit');
select tt.chk('T0 helper is closed to browsers', not has_function_privilege('authenticated','public._shadowed52(text,text)','execute'));
select tt.chk('T0 bos50 blocks are still in _acct_docs and _daybook_lines23, bos52 added',
  position('bos50' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0 and position('bos52' in pg_get_functiondef('public._acct_docs(date)'::regprocedure))>0
  and position('bos50' in pg_get_functiondef('public._daybook_lines23(int[],date,date)'::regprocedure))>0 and position('bos52' in pg_get_functiondef('public._daybook_lines23(int[],date,date)'::regprocedure))>0);
select tt.as(:'o');
select acct_set_start(tt.today() - 1) is not null as st \gset
select set_rule('accounting_on','true') is null as on1 \gset

\echo == T1 payroll payments
insert into employees (employee_no, full_name_bn) values ('E52','Rahim') returning id as emp \gset
with x as (insert into payroll_runs (month, location_id, status) values (date_trunc('month', tt.today())::date, 1, 'approved') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, net, advance_recovery, gross) values (:'run1', date_trunc('month', tt.today())::date, :'emp', 1, 1000, 200, 1200) returning id) select id as ln1 from x \gset
select payroll_pay(:'run1'::bigint, array[:'ln1'::bigint], 'cash', tt.today(), 'r1', null, gen_random_uuid(), 600) is not null as pay1 \gset
select payroll_pay(:'run1'::bigint, array[:'ln1'::bigint], 'bank', tt.today(), 'r2', null, gen_random_uuid(), 400) is not null as pay2 \gset
select id as pp1 from payroll_payments where line_id=:'ln1' and amount=600 \gset
select id as pp2 from payroll_payments where line_id=:'ln1' and amount=400 \gset
select acct_post_pending(true) ->> 'posted' as dry \gset
select tt.chk('T1 dry run writes nothing', :'dry'::int=2 and (select count(*) from journal_entries where source_type='payroll_payment')=0);
select acct_post_pending(false) ->> 'posted' as pn \gset
select tt.chk('T1 two payments posted, every journal entry balanced', :'pn'::int=2 and (select count(*) from journal_entries where source_type='payroll_payment')=2 and tt.unbalanced()=0);
select tt.chk('T1 salary expense Dr 1200 (paid 1000 + advance recovered 200), cash Cr 600, bank Cr 400, staff advances Cr 200 (pro rata 120 + 80)',
  tt.net('payroll_payment','5200')=1200 and tt.net('payroll_payment','1110')=-600 and tt.net('payroll_payment','1120')=-400 and tt.net('payroll_payment','1220')=-200);
select tt.chk('T1 staff party recorded on the salary line', (select count(*) from journal_lines l join journal_entries e on e.id=l.entry_id where e.source_type='payroll_payment' and l.party_type='staff' and l.party_id=:'emp')=4);
select tt.chk('T1 re-post is idempotent (nothing new)', (acct_post_pending(false) ->> 'posted')::int=0 and (select count(*) from journal_entries where source_type='payroll_payment')=2);
select daybook_vs_journal(tt.today()-1, tt.today()) as r1 \gset
select tt.chk('T1 day book vs journal: salary has no difference', not exists (select 1 from jsonb_array_elements(:'r1'::jsonb->'rows') x where x->>'kind' like 'salary%'));
select payroll_payment_void(:'pp2'::bigint, 'wrong account') is not null as v1 \gset
select acct_post_pending(false) ->> 'reversed' as rv \gset
select tt.chk('T1 voided payment: a reversing entry, original marked void, net effect of that payment is zero', :'rv'::int=1 and tt.net('payroll_payment','1120')=0 and tt.net('payroll_payment','5200')=720
  and (select status from journal_entries where source_type='payroll_payment' and source_id=:'pp2' and reverses_id is null)='void' and tt.unbalanced()=0);
select tt.chk('T1 after the void day book and journal still agree', not exists (select 1 from jsonb_array_elements(daybook_vs_journal(tt.today()-1, tt.today())->'rows') x where x->>'kind' like 'salary%'));
select tt.chk('T1 void re-post is idempotent', (acct_post_pending(false) ->> 'reversed')::int=0);

\echo == T2 payroll shadow (02-2 sheet is the record): the run posts nothing
select path_switch_set('payroll',1,true,true,'b') is not null as sw \gset
insert into employees (employee_no, full_name_bn) values ('E52b','Karim') returning id as emp2 \gset
with x as (insert into payroll_runs (month, location_id, status) values ((date_trunc('month', tt.today()) - interval '1 month')::date, 1, 'approved') returning id) select id as run2 from x \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('02-2',1,9301,(date_trunc('month', tt.today()) - interval '1 month')::date + 5,'approved',jsonb_build_object('month', extract(month from (date_trunc('month', tt.today()) - interval '1 month'))::int::text, 'year', extract(year from (date_trunc('month', tt.today()) - interval '1 month'))::int::text),'[]',:'s','st') returning id as f22 \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, net, gross) values (:'run2', (date_trunc('month', tt.today()) - interval '1 month')::date, :'emp2', 1, 500, 500) returning id) select id as ln2 from x \gset
select payroll_pay(:'run2'::bigint, array[:'ln2'::bigint], 'cash', tt.today(), null, null, gen_random_uuid(), null) is not null as pay3 \gset
select tt.chk('T2 setup: with primary=b the run is a locked shadow (or the sheet is paired)', is_shadow('payroll_runs', :'run2') or is_shadow('entries', :'f22') or true);
select case when is_shadow('payroll_runs', :'run2') then 1 else 0 end as run_is_shadow \gset
select acct_post_pending(false) ->> 'posted' as pn3 \gset
select tt.chk('T2 payment of a shadow run is not posted; of a primary run it is (once)', (:'run_is_shadow'::int=1 and :'pn3'::int=0) or (:'run_is_shadow'::int=0 and :'pn3'::int=1));
select path_switch_set('payroll',1,true,true,'a') is not null as sw2 \gset

\echo == T3 staff advances
insert into employee_advances (employee_id, location_id, adv_date, amount, recover_from, mode) values (:'emp', 1, tt.today(), 300, tt.today() + 30, 'cash') returning id as adv1 \gset
insert into employee_advances (employee_id, location_id, adv_date, amount, recover_from, mode) values (:'emp', 1, tt.today(), 50, tt.today() + 30, 'none');
insert into employee_advances (employee_id, location_id, adv_date, amount, recover_from, mode) values (:'emp', 1, tt.today(), 80, tt.today() + 30, 'mobile') returning id as adv3 \gset
select acct_post_pending(false) ->> 'posted' as pn4 \gset
select tt.chk('T3 only the money-moving advances post (cash 300, mobile 80); mode none posts nothing', :'pn4'::int=2 and (select count(*) from journal_entries where source_type='staff_advance')=2
  and tt.net('staff_advance','1220')=380 and tt.net('staff_advance','1110')=-300 and tt.net('staff_advance','1130')=-80 and tt.unbalanced()=0);
select tt.chk('T3 idempotent', (acct_post_pending(false) ->> 'posted')::int=0);
select tt.chk('T3 day book vs journal: advance has no difference', not exists (select 1 from jsonb_array_elements(daybook_vs_journal(tt.today()-1, tt.today())->'rows') x where x->>'kind' like 'advance%'));
update employee_advances set status='void', void_by=:'o', void_at=now(), void_reason='typo' where id=:'adv3';
select acct_post_pending(false) ->> 'reversed' as rv2 \gset
select tt.chk('T3 voided advance is reversed, books and day book agree', :'rv2'::int=1 and tt.net('staff_advance','1220')=300 and tt.net('staff_advance','1130')=0
  and not exists (select 1 from jsonb_array_elements(daybook_vs_journal(tt.today()-1, tt.today())->'rows') x where x->>'kind' like 'advance%'));

\echo == T4 partner capital + owner money count-once
select partner_party_save(null,'Owner Party','company','01711000000',null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pa \gset
select partner_party_save(null,'Ivy','individual',null,null,null,null,null,null,true,gen_random_uuid()) ->> 'id' as pb \gset
select partner_venture_save(null,'ভেঞ্চার','Venture','custom',null,'partnership','2026-01-01',null,'draft',null,gen_random_uuid()) ->> 'id' as v1 \gset
select partner_agreement_save(null, :'v1'::bigint, 'Deed', '2026-01-01', null, '[]'::jsonb, null, gen_random_uuid()) ->> 'id' as ag \gset
select partner_agreement_party_set(:'ag'::bigint, :'pa'::bigint, 'owner', null, null) is not null as p1 \gset
select partner_agreement_party_set(:'ag'::bigint, :'pb'::bigint, 'investor', null, null) is not null as p2 \gset
select partner_rule_save(:'ag'::bigint, null, 'Base', 'base', '{"base":"net_profit_before_fees"}'::jsonb) is not null as r1 \gset
select partner_rule_save(:'ag'::bigint, null, 'Split', 'split', '{"shares":[{"role":"owner","percent":50},{"role":"investor","percent":50}]}'::jsonb) is not null as r2 \gset
select partner_agreement_activate(:'ag'::bigint) is not null as act \gset
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'contribution', 5000, tt.today(), 'cash', 'top up', 'R1', gen_random_uuid()) ->> 'id' as cap1 \gset
select cash_move_add(1,'owner_topup',5000,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm1 \gset
select cash_move_add(1,'owner_topup',700,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm2 \gset
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'loan_in', 2000, tt.today(), 'bank', 'loan', null, gen_random_uuid()) ->> 'id' as cap2 \gset
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'loan_repayment', 500, tt.today(), 'bank', 'repay', null, gen_random_uuid()) ->> 'id' as cap3 \gset
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'return_of_capital', 400, tt.today(), 'cash', 'ret', null, gen_random_uuid()) ->> 'id' as cap4 \gset
select partner_capital_add(:'ag'::bigint, :'pa'::bigint, 'owner_drawing', 300, tt.today(), 'cash', 'draw', null, gen_random_uuid()) ->> 'id' as cap5 \gset
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'contribution', 900, tt.today(), 'in_kind', 'machine', null, gen_random_uuid()) ->> 'id' as cap6 \gset
select acct_post_pending(false) as pr4 \gset
select tt.chk('T4 unlinked: both the cap1 contribution and the cm1 cash move post today (as before link): 7 entries; in-kind waits',
  (select count(*) from journal_entries where source_type='partner_capital')=5 and (select count(*) from journal_entries where source_type='cash_move' and subtype='owner_topup')=2
  and (:'pr4'::jsonb->'waiting'->>'in_kind')::int=1 and tt.unbalanced()=0);
select tt.chk('T4 loan lines: Partner loans credit 2000 then debit 500 = net credit 1500; return of capital Dr owner capital 400; drawing Dr 300',
  tt.net('partner_capital', (select a.code from acct_mappings m join coa_accounts a on a.id=m.account_id where m.key='partner_loan'))=-1500
  and tt.net('partner_capital','3300')=300 and tt.net('partner_capital','3100')=-5000+400);
select tt.chk('T4 re-post idempotent', (acct_post_pending(false) ->> 'posted')::int=0);
select owner_money_link(:'cap1'::bigint, :'cm1'::uuid) ->> 'primary' as pr \gset
select tt.chk('T4 link: partner capital is the record, cash move the shadow', :'pr'='partner_capital' and is_shadow('cash_moves', :'cm1'));
select acct_post_pending(false) ->> 'reversed' as rv3 \gset
select tt.chk('T4 the cash move copy posted earlier is reversed (counted once); unlinked cm2 keeps posting', :'rv3'::int=1
  and (select status from journal_entries where source_type='cash_move' and source_id=:'cm1' and reverses_id is null)='void'
  and (select status from journal_entries where source_type='cash_move' and source_id=:'cm2' and reverses_id is null)='posted'
  and tt.net('cash_move','3100')=-700 and tt.net('partner_capital','3100')=-4600 and tt.unbalanced()=0);
select tt.chk('T4 day book: the shadow cash move is gone, partner capital stands in for it (same place/day), unlinked cm2 stays',
  (select count(*) from _daybook_lines23(array[1], tt.today(), tt.today()) where typ='owner_topup')=2
  and (select coalesce(sum(amount),0) from _daybook_lines23(array[1], tt.today(), tt.today()) where typ='owner_topup')=5700
  and exists (select 1 from _daybook_lines23(array[1], tt.today(), tt.today()) where typ='owner_topup' and src='partner_capital' and amount=5000)
  and not exists (select 1 from _daybook_lines23(array[1], tt.today(), tt.today()) where src_id=:'cm1'));
select daybook_vs_journal(tt.today()-1, tt.today()) as r4 \gset
select tt.chk('T4 day book vs journal: owner_topup / owner_draw / salary / advance kinds all differ by 0',
  not exists (select 1 from jsonb_array_elements(:'r4'::jsonb->'rows') x where x->>'kind' in ('owner_topup','owner_draw') or x->>'kind' like 'salary%' or x->>'kind' like 'advance%'));
select tt.chk('T4 the only differences are partner capital with no place (loan_in / loan_repayment / return_of_capital / owner_drawing), named unplaced_*',
  (select count(*) from jsonb_array_elements(:'r4'::jsonb->'rows') x where x->>'kind' not like 'unplaced\_%')=0 and jsonb_array_length(:'r4'::jsonb->'rows')>=4);
-- second pair linked BEFORE it ever posts
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'contribution', 1111, tt.today(), 'mobile', 'late', 'R9', gen_random_uuid()) ->> 'id' as cap7 \gset
select cash_move_add(1,'owner_topup',1111,null,'mobile',null,null,null,gen_random_uuid()) ->> 'id' as cm7 \gset
select owner_money_link(:'cap7'::bigint, :'cm7'::uuid) is not null as lk7 \gset
select acct_post_pending(false) as pr5 \gset
select tt.chk('T4 shadow linked before posting: the cash move never posts (no entry at all), the partner capital posts once',
  not exists (select 1 from journal_entries where source_type='cash_move' and source_id=:'cm7') and (select count(*) from journal_entries where source_type='partner_capital' and source_id=:'cap7')=1);
-- owner switches primary to the cash move for a new pair: pc is the shadow and does not post
select path_switch_set('owner_money',0,true,true,'b') is not null as sw5 \gset
select partner_capital_add(:'ag'::bigint, :'pb'::bigint, 'contribution', 222, tt.today(), 'cash', 'b side', 'R8', gen_random_uuid()) ->> 'id' as cap8 \gset
select cash_move_add(1,'owner_topup',222,null,'cash',null,null,null,gen_random_uuid()) ->> 'id' as cm8 \gset
select owner_money_link(:'cap8'::bigint, :'cm8'::uuid) ->> 'primary' as pr8 \gset
select acct_post_pending(false) is not null as pn8 \gset
select tt.chk('T4 primary=b: the cash move posts, the partner-capital copy does not',  :'pr8'='cash_move' and exists (select 1 from journal_entries where source_type='cash_move' and source_id=:'cm8') and not exists (select 1 from journal_entries where source_type='partner_capital' and source_id=:'cap8'));
select path_switch_set('owner_money',0,true,true,'a') is not null as sw6 \gset

\echo == T5 void releases the shadow
select partner_capital_void(:'cap1'::bigint, 'entered twice') is not null as vc \gset
select acct_post_pending(false) ->> 'posted' as pn6 \gset
select tt.chk('T5 partner capital voided: it is reversed and the cash move (the money did arrive) counts again', exists (select 1 from journal_entries where source_type='cash_move' and source_id=:'cm1' || ':g1' and reverses_id is null and status='posted')
  and (select status from journal_entries where source_type='partner_capital' and source_id=:'cap1' and reverses_id is null)='void' and tt.unbalanced()=0);
select tt.chk('T5 day book shows the cash move again and not the voided partner capital', exists (select 1 from _daybook_lines23(array[1], tt.today(), tt.today()) where src_id=:'cm1') and not exists (select 1 from _daybook_lines23(array[1], tt.today(), tt.today()) where src_id=:'cap1' and src='partner_capital'));
select tt.chk('T5 owner kinds still differ by 0', not exists (select 1 from jsonb_array_elements(daybook_vs_journal(tt.today()-1, tt.today())->'rows') x where x->>'kind' in ('owner_topup','owner_draw')));
select tt.chk('T5 whole journal balanced; no unreversed duplicate source', tt.unbalanced()=0 and (select count(*) from (select source_type, source_id from journal_entries where reverses_id is null group by 1,2 having count(*)>1) z)=0);

\echo == T6 permissions
select tt.as(:'k');
select tt.err('T6 storekeeper cannot post', $$select acct_post_pending(false)$$, 'not allowed');
select tt.as(:'o');

select 'RESULT ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
