-- FRESH DB ONLY. Phase 86 tests (fixes M1-M4, m5, m8 after the independent check). Needs phases 8..79, 80..85, then 86 (run it once on a DB WITHOUT 86 to see the bypass: M1/M2/M3/M4 checks fail there).
--   ORDER="phase8 ... phase85 phase86" bash <build script> a86db ; psql -h /tmp -p 5552 -U postgres -d a86db -qAt -f supabase/phase86_test.sql | grep -E 'FAIL|RESULT'
-- Test data only (test_* names). Numbers are hand-computed above each block.
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set o2 '00000000-0000-0000-0000-000000000005'
\set m '00000000-0000-0000-0000-000000000004'
\set m2 '00000000-0000-0000-0000-000000000007'
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
create or replace function tt.nd(p_code text) returns numeric language sql stable as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.coa_accounts a on a.id = l.account_id where a.code = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;

insert into auth.users (id,email,raw_user_meta_data) values
 (:'o','test_owner@s.app','{"full_name":"test_owner"}'), (:'o2','test_owner2@s.app','{"full_name":"test_owner2"}'),
 (:'m','test_mgmt@s.app','{"full_name":"test_mgmt"}'), (:'m2','test_mgmt2@s.app','{"full_name":"test_mgmt2"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'o','owner'),(:'o2','owner'),(:'m','management'),(:'m2','management') on conflict do nothing;
insert into user_locations values (:'m',1),(:'m2',1) on conflict do nothing;

\echo == T0 shape and safe defaults
select tt.chk('T0 phase86 present, split switch exists and is OFF, helpers closed to browsers',
  to_regprocedure('public._p86_present()') is not null and exists (select 1 from rules where key='d_wallet_split_on') and not rule_on('d_wallet_split_on')
  and not has_function_privilege('authenticated','public._d_acct_docs(date)','execute') and not has_function_privilege('anon','public._d_split_on()','execute')
  and not has_function_privilege('authenticated','public._d_supplier_pay_neg86()','execute') and has_function_privilege('authenticated','public.owner_approval_mode_set(text,text,text)','execute'));
select tt.chk('T0 nothing else switched on', not rule_on('payroll_accrual_on') and not rule_on('cash_short_post_on') and not rule_on('partner_settlement_post_on') and rule_txt('owner_approval_mode')='self');

set role authenticated; select tt.as(:'o');

\echo == M1 named mode cannot be bypassed through the legacy switch
select owner_approval_mode_set('named','management','test: owner away') is not null as nm \gset
select tt.chk('M1 named: switch OFF', not rule_on('owner_self_approve') and owner_approval_mode()->>'mode'='named');
select tt.err('M1 owner_self_approve_set(true) is refused while named', $$select owner_self_approve_set(true)$$, 'named_mode_active');
select tt.err('M1 set_rule owner_self_approve true is refused while named', $$select set_rule('owner_self_approve','true'::jsonb)$$, 'named_mode_active');
select tt.chk('M1 the switch is still OFF', not rule_on('owner_self_approve'));
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as e1 \gset
select submit_entry(:'e1'::uuid) is not null as s1 \gset
select tt.err('M1 owner still cannot approve his own entry', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'e1'), 'approve');
select tt.chk('M1 a switch OFF while named is still fine (nothing else changes)', owner_self_approve_set(false) is not null);

\echo == M2 decider differs from maker; the owner may not hold the approver role
select tt.as(:'m'); select tt.chk('M2 the named role holder decides the owner entry', (decide_entry(:'e1'::uuid, true, null, '{}', '[]') ->> 'status')='approved'); select tt.as(:'o');
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as e2 \gset
select submit_entry(:'e2'::uuid) is not null as s2 \gset
reset role;
insert into user_roles values (:'o','management') on conflict do nothing;
select tt.err('M2 trigger: maker = decider is refused even if the maker holds the named role', format($$update entries set status='approved', checked_by=created_by, checked_at=now() where id=%L$$, :'e2'), 'named_approver_only');
select tt.err('M2 trigger: another owner who does not hold the role is refused', format($$update entries set status='approved', checked_by=%L, checked_at=now() where id=%L$$, :'o2', :'e2'), 'named_approver_only');
delete from user_roles where user_id=:'o' and role_code='management';
set role authenticated; select tt.as(:'o');
select owner_approval_mode_set('self', null, 'test: back') is not null as sb \gset
reset role; insert into user_roles values (:'o','management') on conflict do nothing; set role authenticated; select tt.as(:'o');
select tt.err('M2 cannot enter named mode while the owner holds the role', $$select owner_approval_mode_set('named','management')$$, 'owner_holds_approver_role');
select tt.err('M2 cannot point the approver role at a role the owner holds (self mode)', $$select owner_approval_mode_set('self','management')$$, 'owner_holds_approver_role');
select tt.chk('M2 mode is still self', owner_approval_mode()->>'mode'='self');
reset role; delete from user_roles where user_id=:'o' and role_code='management'; set role authenticated; select tt.as(:'o');

\echo == m8 recovery when the only other holder of the named role is gone
select owner_approval_mode_set('named','management') is not null as n2 \gset
select save_entry(null,'10-2',1,current_date,'{}','[]') ->> 'id' as e3 \gset
select submit_entry(:'e3'::uuid) is not null as s3 \gset
reset role; update profiles set status='disabled' where id in (:'m', :'m2'); set role authenticated; select tt.as(:'o');
select tt.err('m8 nobody can approve the owner entry now (owner, other owner)', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'e3'), 'cannot approve your own');
select tt.as(:'o2'); select tt.err('m8 ... other owner is not the named role', format($$select decide_entry(%L,true,null,'{}','[]')$$, :'e3'), 'named_approver_only'); select tt.as(:'o');
select (select count(*) from audit_log where action='owner_approval_mode') as ac0 \gset
select owner_approval_mode_set('self', null, 'test: approver gone') is not null as rec \gset
select tt.chk('m8 owner switches the mode back to self: one more audit line, switch ON again', owner_approval_mode()->>'mode'='self' and rule_on('owner_self_approve')
  and (select count(*) from audit_log where action='owner_approval_mode')=:'ac0'::int+1 and (select detail->>'note' from audit_log where action='owner_approval_mode' order by at desc limit 1)='test: approver gone');
select tt.chk('m8 and the owner can approve his entry again', (decide_entry(:'e3'::uuid, true, null, '{}', '[]') ->> 'status')='approved');
reset role; update profiles set status='active'; set role authenticated; select tt.as(:'o');

\echo == M3 P&L salary with payroll accrual OFF is exactly the 02-2 sheets (as before phase85)
reset role;
select date_trunc('month', tt.today() - interval '2 months')::date as pm2 \gset
select date_trunc('month', tt.today() - interval '1 month')::date as pm \gset
select (:'pm'::date - 1) as pm2e \gset
select (:'pm'::date + interval '1 month' - interval '1 day')::date as pme \gset
set role authenticated; select tt.as(:'o');
select acct_set_start(:'pm2'::date) is not null as st \gset
select set_rule('accounting_on','true') is null as on1 \gset
select acct_journal_post(:'pm2'::date, 1, 'test opening cash', '[{"code":"1110","debit":1000000},{"code":"3100","credit":1000000}]'::jsonb) is not null as oc \gset
reset role;
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST86_A','test_a','active',1) returning id) select id as ea from x \gset
with x as (insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST86_B','test_b','active',1) returning id) select id as eb from x \gset
set role authenticated; select tt.as(:'o');
reset role;
-- run0: month PM2: net 8000 + 15000 = 23000 approved. Two 02-2 sheets in PM2: 4000 (no link) and 9000 (linked as the shadow of run0).
with x as (insert into payroll_runs (month, location_id, status) values (:'pm2', 1, 'draft') returning id) select id as run0 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run0', :'pm2', :'ea', 1, 8000, 8000) returning id) select id as l0a from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run0', :'pm2', :'eb', 1, 15000, 15000) returning id) select id as l0b from x \gset
set role authenticated; select tt.as(:'o');
select payroll_approve(:'run0'::bigint) ->> 'status' as ap0 \gset
reset role;
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
 ('02-2',1,9601,:'pm2'::date,'approved',format('{"pay":[{"due":4000}],"month":"%s"}',:'pm2')::jsonb,'[]',:'o','st'),
 ('02-2',1,9602,:'pm2'::date,'approved',format('{"pay":[{"due":9000}],"month":"%s"}',:'pm2')::jsonb,'[]',:'o','st');
select id as f2 from entries where form_code='02-2' and serial=9602 \gset
set role authenticated; select tt.as(:'o');
reset role;
select (select coalesce(sum(o_sal),0) from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1])) as sal_nolink \gset
select shadow_link_add('payroll', 1, 'payroll_runs', :'run0', 'entries', :'f2', 'test shadow') is not null as lk \gset
select tt.chk('M3 accrual OFF, run approved, before the link: salary = the two sheets 4000 + 9000 = 13000 (the run is NOT added)', :'sal_nolink'::numeric=13000);
select tt.chk('M3 accrual OFF after the link: still 13000 (the shadow sheet is counted as before phase85)', (select o_sal from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1]))=13000);
select tt.chk('M3 accrual OFF: equals the plain sum over all 02-2 sheets (the pre-phase85 rule)',
  (select o_sal from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1])) = (select sum(coalesce(_r2_num(r->'due'),0)+coalesce(_r2_num(r->'overtime'),0)+coalesce(_r2_num(r->'other'),0))
     from entries e, jsonb_array_elements(e.data->'pay') r where e.form_code='02-2' and e.status in ('submitted','approved') and e.entry_date between :'pm2'::date and :'pm2e'::date and e.location_id=1));
-- accrual ON from PM: month PM2 keeps the old posting but P&L counts each salary once: run0 23000 + the unlinked sheet 4000 = 27000 (shadow sheet 9000 is the same salary as run0)
set role authenticated; select tt.as(:'o');
select set_rule('payroll_accrual_on','true'::jsonb) is null as r1 \gset
select set_rule('payroll_accrual_from', to_jsonb(:'pm'::text)) is null as r2 \gset
reset role;
select tt.chk('M3 accrual ON: counted once = run 23000 + unlinked sheet 4000 = 27000', (select o_sal from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1]))=27000);
set role authenticated; select tt.as(:'o');
select set_rule('payroll_accrual_on','false'::jsonb) is null as r3 \gset
reset role;
select tt.chk('M3 accrual switched OFF again: back to 13000', (select o_sal from _p27_pl(:'pm2'::date, :'pm2e'::date, array[1]))=13000);

\echo == M4 wallet split switch (default OFF)
set role authenticated; select tt.as(:'o');
reset role;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
 (1, 986001, tt.today(), now(), '[]', 1000, 0, 1000, 'mobile', 'done', :'o'), (1, 986002, tt.today(), now(), '[]', 500, 0, 500, 'mobile', 'done', :'o'),
 (1, 986003, tt.today(), now(), '[]', 300, 0, 300, 'mobile', 'done', :'o'), (1, 986004, tt.today(), now(), '[]', 200, 0, 200, 'mobile', 'done', :'o');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by)
 select s.id, 1, 'sale', 'mobile', v.w, s.total, now(), :'o' from sales s join (values (986001, 'bkash'), (986002, 'Nagad'), (986003, 'rocket'), (986004, 'test_unknown_wallet')) v(r, w) on v.r = s.receipt;
insert into suppliers (name) values ('test_supplier_86');
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by)
 select id, 1, 'mobile', 'bkash', 100, now(), :'o' from suppliers where name = 'test_supplier_86';
set role authenticated; select tt.as(:'o');
select (select coalesce(sum(debit-credit),0) from journal_lines l join coa_accounts a on a.id=l.account_id where a.code='1130') as m0 \gset
select acct_post_pending(false) is not null as p1 \gset
-- mobile in: 1000+500+300+200 = 2000 debit on 1130, supplier out 100 credit on 1130 => net 1900 (the supplier payment posts on the mobile account)
select tt.chk('M4 OFF: nothing on 1131..1134 for the historic and new payments, all mobile money stays on 1130 (net 1900)',
  tt.nd('1131')=0 and tt.nd('1132')=0 and tt.nd('1133')=0 and tt.nd('1134')=0 and tt.nd('1130')=1900 and (select count(*) from journal_entries where source_type='d_wallet_split')=0);
-- fee 15 from bkash, bkash -> cash 400, nagad -> rocket 100 (register only: no journal entry while OFF because both sides would be 1130)
select (d_wallet_fee_add((select id from d_wallets where code='bkash'), 1, tt.today(), 15, 'cash_out', 'test_ref_86', null, '00000000-0000-0000-0000-000000000861')->>'id')::bigint as fee1 \gset
select (d_wallet_move_add((select id from d_wallets where code='bkash'), 1, tt.today(), 'out', 'cash', null, 400, null, null, '00000000-0000-0000-0000-000000000862')->>'id')::bigint as mv1 \gset
select (d_wallet_move_add((select id from d_wallets where code='nagad'), 1, tt.today(), 'out', 'wallet', (select id from d_wallets where code='rocket'), 100, null, null, null)->>'id')::bigint as mv2 \gset
select acct_post_pending(false) is not null as p2 \gset
select tt.chk('M4 OFF: the fee posts Dr 5815 / Cr 1130 and the cash move Dr 1110 / Cr 1130; nothing on the wallet accounts; wallet-to-wallet move has no entry',
  tt.nd('5815')=15 and tt.nd('1130')=1900-15-400 and tt.nd('1131')=0 and tt.nd('1132')=0 and tt.nd('1133')=0
  and (select count(*) from journal_entries where source_type='d_wallet_move' and source_id=:'mv2')=0 and (select count(*) from journal_entries where source_type='d_wallet_move' and source_id=:'mv1')=1);
select tt.chk('M4 OFF: every entry balances', tt.unbalanced()=0);
-- switch ON: the split applies to historic payments; the fee / cash move posted on 1130 are moved to the wallet; the wallet-to-wallet move posts now.
-- bkash: 1000 - 100 - 15 - 400 = 485 ; nagad: 500 - 100 = 400 ; rocket: 300 + 100 = 400 ; 1130 keeps the unknown wallet 200
select set_rule('d_wallet_split_on','true'::jsonb) is null as on2 \gset
select acct_post_pending(false) is not null as p3 \gset
select tt.chk('M4 ON: wallet accounts get their balances: 1131 485, 1132 400, 1133 400, 1134 0; 1130 keeps 200 (unknown wallet text)',
  tt.nd('1131')=485 and tt.nd('1132')=400 and tt.nd('1133')=400 and tt.nd('1134')=0 and tt.nd('1130')=200);
select tt.chk('M4 ON: journal = register for every wallet, all entries balance', not exists (select 1 from jsonb_array_elements(d_wallet_balances()) x where (x->>'journal_gap')::numeric <> 0) and tt.unbalanced()=0);
select acct_post_pending(false) is not null as p4 \gset
select tt.chk('M4 ON: posting again adds nothing (3 sales + 1 supplier + 1 fee + 1 move reclass = 6 split entries)', (select count(*) from journal_entries where source_type='d_wallet_split' and reverses_id is null)=6);
-- a new bkash sale of 50 with the switch ON goes straight to 1131
reset role;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values (1, 986005, tt.today(), now(), '[]', 50, 0, 50, 'mobile', 'done', :'o');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by) select id, 1, 'sale', 'mobile', 'bkash', 50, now(), :'o' from sales where receipt=986005;
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) is not null as p5 \gset
select tt.chk('M4 ON: a new payment into bkash lands on 1131 (535)', tt.nd('1131')=535);
-- OFF again: new payments stay on 1130, entries already posted are not rewritten
select set_rule('d_wallet_split_on','false'::jsonb) is null as off2 \gset
reset role;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values (1, 986006, tt.today(), now(), '[]', 70, 0, 70, 'mobile', 'done', :'o');
insert into sale_payments (sale_id, location_id, kind, mode, wallet, amount, paid_at, created_by) select id, 1, 'sale', 'mobile', 'bkash', 70, now(), :'o' from sales where receipt=986006;
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) is not null as p6 \gset
select tt.chk('M4 OFF again: the new 70 stays on 1130 (270), 1131 unchanged 535', tt.nd('1130')=270 and tt.nd('1131')=535 and tt.unbalanced()=0);
-- voiding a split payment while OFF still reverses its split entry (books stay consistent)
reset role;
update sale_payments set voided=true where sale_id=(select id from sales where receipt=986005);
update sales set status='void' where receipt=986005;
set role authenticated; select tt.as(:'o');
select acct_post_pending(false) is not null as p7 \gset
select tt.chk('M4 OFF: a voided payment reverses its earlier split (1131 back to 485), entries balance', tt.nd('1131')=485 and tt.unbalanced()=0);

\echo == m5 supplier payment from a wallet and the negative block
reset role;
select id as wup from d_wallets where code='upay' \gset
select id as wro from d_wallets where code='rocket' \gset
set role authenticated; select tt.as(:'o');
select d_wallet_opening_set(:'wup'::int, 0, tt.today()-3) is not null as op \gset
reset role;
select tt.err('m5 supplier payment of 50 from upay (opening 0, no money in) is refused when the block mode is on',
  format($$insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by) select id, 1, 'mobile', 'upay', 50, now(), %L from suppliers where name='test_supplier_86'$$, :'o'), 'wallet_negative');
select tt.chk('m5 ... and nothing was saved', (select count(*) from supplier_payments where wallet='upay')=0);
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by) select id, 1, 'mobile', 'rocket', 10, now(), :'o' from suppliers where name='test_supplier_86';
select tt.chk('m5 a wallet without an opening date is not checked (documented limit): the payment of 10 from rocket is saved', (select count(*) from supplier_payments where wallet='rocket')=1);
select set_config('request.jwt.claim.sub', :'o', false);
set role authenticated;
select d_wallet_opening_set(:'wro'::int, 0, tt.today()-3) is not null as op2 \gset
select set_rule('d_wallet_negative_mode','"warn"'::jsonb) is null as w1 \gset
reset role;
insert into supplier_payments (supplier_id, location_id, mode, wallet, amount, paid_at, created_by) select id, 1, 'mobile', 'upay', 50, now(), :'o' from suppliers where name='test_supplier_86';
select tt.chk('m5 warn mode: the same payment is saved (no refusal)', (select count(*) from supplier_payments where wallet='upay')=1);
set role authenticated; select tt.as(:'o');
select set_rule('d_wallet_negative_mode','"refuse"'::jsonb) is null as w2 \gset

reset role;
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
