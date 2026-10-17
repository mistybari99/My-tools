-- FRESH DB ONLY. Phase 444 tests: the cash-flow statement and the working capital (package RPT-C1, block R3).
--   a database built through phase99, then phase440.sql .. phase444.sql  (this file pastes phase444 once more for the paste-twice check)
--   psql -h /tmp -p <port> -U postgres -d db444 -qAt -f supabase/phase444_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/c1_fixture.sql (hand-computed numbers in its header). Test data only (test_* names).
-- Hand-computed cash movements of the fixture journal (cash = 1110 + bank 1120 + bank test_bank + wallet 1130), accounting start = pm:
--   real opening journal 50,000 (bank) on pm = opening, not a flow;  the W1-D fixture also opens with a manual journal of 900,000 dated pm (counts as inflow until the setting names its date)
--   operating: cash sales 5,000 + 3,000 + 700;  rent -1,000;  vouchers -500, quick -300, return -100, bank charge -25, wallet fee -12  (the rest of the W1-D stock entries do not move cash)
--   investing: fixed asset bought from bank -4,000     financing: owner capital +2,000      the bank deposit 2,000 (cash -> bank) is a transfer: netted, in no class
--   with the opening date set to pm and the usual-practice classes applied: flows = 8,812 - 2,049 - 4,000 + 2,000 = 4,763;  opening journals in the period 950,000;  closing 954,763
\set ON_ERROR_STOP off
\ir ../tests/sql/c1_fixture.sql
\set ON_ERROR_STOP off
create table if not exists tt.res (name text, ok boolean);
truncate tt.res;
create or replace function tt.chk(p_name text, p_ok boolean) returns void language plpgsql as $$
begin insert into tt.res values (p_name, coalesce(p_ok,false)); raise notice '% %', case when coalesce(p_ok,false) then 'PASS' else 'FAIL' end, p_name; end $$;
create or replace function tt.err(p_name text, p_sql text, p_msg text default '') returns void language plpgsql as $$
begin execute p_sql; perform tt.chk(p_name, false); raise notice '  (it did not fail)';
exception when others then perform tt.chk(p_name, sqlerrm like '%' || p_msg || '%'); if sqlerrm not like '%' || p_msg || '%' then raise notice '  (got: %)', sqlerrm; end if; end $$;
create or replace function tt.as(p_sub text) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', p_sub, false); end $$;
create or replace function tt.unbalanced() returns bigint language sql stable as $$
  select count(*) from (select entry_id from public.journal_lines group by entry_id having sum(debit) <> sum(credit)) z $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select (now() at time zone 'Asia/Dhaka')::date as td \gset
select _acct_start() as pm \gset


\echo == T0 shape, internals closed, pasting twice changes nothing
select tt.chk('T0 phase444 present; the three statements are for signed-in users only; the helper is closed', to_regprocedure('public._c1_p444_present()') is not null
  and has_function_privilege('authenticated','public.stmt_cash_flow(date,date,int)','execute') and not has_function_privilege('anon','public.stmt_cash_flow(date,date,int)','execute')
  and has_function_privilege('authenticated','public.stmt_working_capital(date,int)','execute') and not has_function_privilege('anon','public.stmt_working_capital(date,int)','execute')
  and has_function_privilege('authenticated','public.stmt_cf_drill(date,date,int,text,bigint)','execute') and not has_function_privilege('authenticated','public._c1_open_through()','execute'));
select tt.chk('T0 the new setting exists, is text, is blank by default', exists (select 1 from rules where key = 'report_cf_opening_through' and kind = 'text' and default_value is null) and public._c1_open_through() is null);
select md5(pg_get_functiondef('public.stmt_cash_flow(date,date,int)'::regprocedure) || pg_get_functiondef('public.stmt_working_capital(date,int)'::regprocedure)) as h_before \gset
select count(*) as n_je_before from journal_entries \gset
select count(*) as n_rules_before from rules \gset
\ir phase444.sql
select tt.chk('T0 pasting phase444 again changes nothing', md5(pg_get_functiondef('public.stmt_cash_flow(date,date,int)'::regprocedure) || pg_get_functiondef('public.stmt_working_capital(date,int)'::regprocedure)) = :'h_before'
  and (select count(*) from rules) = :n_rules_before);
create or replace function tt.cf(p_loc int default null) returns jsonb language sql stable as $$ select public.stmt_cash_flow((select public._acct_start()), tt.today(), p_loc) $$;
create or replace function tt.cls(p_class text, p_key text) returns numeric language sql stable as $$ select (x ->> p_key)::numeric from jsonb_array_elements(tt.cf() -> 'classes') x where x ->> 'class' = p_class $$;
create or replace function tt.cfc(p_loc int default null) returns numeric language sql stable as $$ select (public.acct_cash_flow((select public._acct_start()), tt.today(), p_loc) ->> 'closing')::numeric $$;
create or replace function tt.note(p_code text) returns boolean language sql stable as $$ select exists (select 1 from jsonb_array_elements(tt.cf() -> 'notes') n where n ->> 'code' = p_code) $$;
grant execute on all functions in schema tt to authenticated, anon;

\echo == T1 default settings: nothing guessed (no class, no opening date)
select tt.as(:'o');
select tt.chk('T1 every cash movement is "unclassified" while no class is set; operating / investing / financing are 0 because nothing is classed', tt.cls('operating','net') = 0 and tt.cls('investing','net') = 0 and tt.cls('financing','net') = 0 and tt.cls('unclassified','in') > 0 and tt.note('unclassified'));
select tt.chk('T1 the real opening journal (source opening) is NEVER a flow: it is on its own line, 50,000', (tt.cf() ->> 'opening_in_period')::numeric >= 50000 and tt.note('opening_in_period'));
select tt.chk('T1 the 900,000 manual opening is a flow until the owner names its date - and the statement says so', tt.note('maybe_opening') and (tt.cf() ->> 'flows')::numeric > 900000);
select tt.chk('T1 the closing equals the closing of the existing Cash flow tab (acct_cash_flow)', (tt.cf() ->> 'closing')::numeric = tt.cfc());
select tt.chk('T1 opening + flows + opening journals = closing', (tt.cf() ->> 'opening')::numeric + (tt.cf() ->> 'flows')::numeric + (tt.cf() ->> 'opening_in_period')::numeric = (tt.cf() ->> 'closing')::numeric);
select tt.chk('T1 the bank deposit (cash to bank) is netted: one transfer entry, 2,000, and it is in no class and no source line', (tt.cf() ->> 'transfer_entries')::int = 1 and (tt.cf() ->> 'transfers_netted')::numeric = 2000);
select tt.chk('T1 the basis text is given in both languages', tt.cf() #>> '{basis,text_en}' like 'Direct method%' and tt.cf() #>> '{basis,text_bn}' <> '');

\echo == T2 the opening date setting and the classes (the owner decides)
select set_rule('report_cf_opening_through', to_jsonb(:'pm'::text)) is null as t2_set \gset
select coa_class_apply_suggested('test: usual practice', false) is not null as t2_apply \gset
select tt.chk('T2 with the opening date the 900,000 is no flow any more: opening journals in the period 950,000, flows 4,763', (tt.cf() ->> 'opening_in_period')::numeric = 950000 and (tt.cf() ->> 'flows')::numeric = 4763 and not tt.note('maybe_opening') and not tt.note('unclassified'));
select tt.chk('T2 operating: in 8,812 out 2,049 (sales 8,700 + stock lines, rent, expenses, return, charges)', tt.cls('operating','in') = 8812 and tt.cls('operating','out') = 2049);
select tt.chk('T2 investing: the fixed asset -4,000', tt.cls('investing','in') = 0 and tt.cls('investing','out') = 4000 and tt.cls('investing','net') = -4000);
select tt.chk('T2 financing: owner capital +2,000', tt.cls('financing','in') = 2000 and tt.cls('financing','out') = 0);
select tt.chk('T2 unclassified is empty and the classes add up to the flows', tt.cls('unclassified','net') = 0 and tt.cls('operating','net') + tt.cls('investing','net') + tt.cls('financing','net') + tt.cls('unclassified','net') = (tt.cf() ->> 'flows')::numeric);
select tt.chk('T2 by source: the sales 700, voucher -500, quick -300, return -100, charge -25, wallet fee -12 and the manual postings are listed', (select sum((s ->> 'net')::numeric) from jsonb_array_elements(tt.cf() -> 'by_source') s) = (tt.cf() ->> 'flows')::numeric
  and exists (select 1 from jsonb_array_elements(tt.cf() -> 'by_source') s where s ->> 'category' = 'sale' and (s ->> 'net')::numeric = 700) and exists (select 1 from jsonb_array_elements(tt.cf() -> 'by_source') s where s ->> 'category' = 'expense_voucher' and (s ->> 'net')::numeric = -500));
select tt.chk('T2 closing 954,763 = opening 0 + flows 4,763 + opening journals 950,000 = the Cash flow tab', (tt.cf() ->> 'closing')::numeric = 954763 and tt.cfc() = 954763 and (tt.cf() ->> 'opening_through')::date = :'pm'::date);
select tt.chk('T2 the accounts behind a class are listed (investing: 1510 -4,000)', exists (select 1 from jsonb_array_elements(tt.cf() -> 'classes') c, jsonb_array_elements(c -> 'accounts') a where c ->> 'class' = 'investing' and a ->> 'code' = '1510' and (a ->> 'net')::numeric = -4000));
-- the owner moves one account to another class: the statement moves with it, the total does not
select id as a_3100 from coa_accounts where code = '3100' \gset
select coa_class_set(:'a_3100'::bigint, 'operating', null, 'test: owner decides') is not null as t2_mv \gset
select tt.chk('T2 the owner classes capital as operating: financing 0, operating +2,000, flows unchanged', tt.cls('financing','net') = 0 and tt.cls('operating','net') = 8812 - 2049 + 2000 and (tt.cf() ->> 'flows')::numeric = 4763);
select coa_class_set(:'a_3100'::bigint, null, null, 'test: blank again') is not null as t2_bl \gset
select tt.chk('T2 a blank class puts its cash in "unclassified" (nothing guessed): 2,000 there, warning shown', tt.cls('unclassified','net') = 2000 and tt.note('unclassified') and tt.cls('financing','net') = 0);
select coa_class_set(:'a_3100'::bigint, 'financing', null, 'test: financing') is not null as t2_fin \gset

\echo == T3 a move between two cash accounts, a reversal and an opening reversal
select acct_journal_post(:'pm'::date + 13, 1, 'test wallet top-up', '[{"code":"1130","debit":300},{"code":"1110","credit":300}]'::jsonb) ->> 'id' as t3_j \gset
select tt.chk('T3 a cash to wallet move is netted too: transfers 2,300, flows unchanged', (tt.cf() ->> 'transfers_netted')::numeric = 2300 and (tt.cf() ->> 'transfer_entries')::int = 2 and (tt.cf() ->> 'flows')::numeric = 4763 and (tt.cf() ->> 'closing')::numeric = tt.cfc());
select acct_journal_post(:'pm'::date + 14, 1, 'test cash expense', '[{"code":"5300","debit":40},{"code":"1110","credit":40}]'::jsonb) ->> 'id' as t3_e \gset
select tt.chk('T3 a new cash expense moves operating by -40 and the closing stays equal to the Cash flow tab', tt.cls('operating','out') = 2089 and (tt.cf() ->> 'closing')::numeric = tt.cfc() and (tt.cf() ->> 'closing')::numeric = 954723);
select tt.chk('T3 the opening balance of a LATER period is the closing of the earlier: from this month, opening = journal before it', (public.stmt_cash_flow(date_trunc('month', :'td'::date)::date, :'td'::date) ->> 'opening')::numeric
  = (select sum(l.debit - l.credit) from journal_lines l join journal_entries e on e.id = l.entry_id where l.account_id = any (public._c1_cash_ids()) and e.entry_date < date_trunc('month', :'td'::date)::date)
  and (public.stmt_cash_flow(date_trunc('month', :'td'::date)::date, :'td'::date) ->> 'closing')::numeric = 954723);
select tt.chk('T3 and a period in the middle starts from the right opening', (public.stmt_cash_flow(:'pm'::date + 5, :'pm'::date + 7) ->> 'opening')::numeric + (public.stmt_cash_flow(:'pm'::date + 5, :'pm'::date + 7) ->> 'flows')::numeric + (public.stmt_cash_flow(:'pm'::date + 5, :'pm'::date + 7) ->> 'opening_in_period')::numeric
  = (public.stmt_cash_flow(:'pm'::date + 5, :'pm'::date + 7) ->> 'closing')::numeric);

\echo == T4 drill-down
select tt.chk('T4 investing drill: one entry, the fixed asset, -4,000', jsonb_array_length(stmt_cf_drill(:'pm'::date, :'td'::date, null, 'investing') -> 'rows') = 1 and (stmt_cf_drill(:'pm'::date, :'td'::date, null, 'investing') -> 'rows' -> 0 ->> 'amount')::numeric = -4000);
select tt.chk('T4 transfer drill: the deposit 2,000 and the top-up 300', (select sum((r ->> 'amount')::numeric) from jsonb_array_elements(stmt_cf_drill(:'pm'::date, :'td'::date, null, 'transfer') -> 'rows') r) = 2300);
select tt.chk('T4 opening drill: the opening journals (950,000)', (select sum((r ->> 'amount')::numeric) from jsonb_array_elements(stmt_cf_drill(:'pm'::date, :'td'::date, null, 'opening') -> 'rows') r) = 950000);
select tt.chk('T4 the drill of a class adds up to the class (operating net)', (select sum((r ->> 'amount')::numeric) from jsonb_array_elements(stmt_cf_drill(:'pm'::date, :'td'::date, null, 'operating') -> 'rows') r) = tt.cls('operating','net'));
select tt.chk('T4 drill by account: 5300 rent in operating = -1,040', (select sum((r ->> 'amount')::numeric) from jsonb_array_elements(stmt_cf_drill(:'pm'::date, :'td'::date, null, 'operating', (select id from coa_accounts where code = '5300')) -> 'rows') r) = -1040);
select tt.err('T4 a bad class is refused', format($$select stmt_cf_drill(%L, %L, null, 'x')$$, :'pm'::date, :'td'::date), 'bad_value');
select tt.err('T4 a bad range is refused', format($$select stmt_cf_drill(%L, %L, null, 'all')$$, :'td'::date, :'pm'::date), 'bad_range');
select tt.err('T4 a bad range for the statement', format($$select stmt_cash_flow(%L, %L)$$, :'td'::date, :'pm'::date), 'bad_range');

\echo == T5 one place
select tt.chk('T5 place 2: operating in 3,000 out 1,000, closing 2,000 = the Cash flow tab for place 2', (tt.cf(2) -> 'classes' -> 0 ->> 'in')::numeric = 3000 and (tt.cf(2) -> 'classes' -> 0 ->> 'out')::numeric = 1000 and (tt.cf(2) ->> 'closing')::numeric = 2000 and tt.cfc(2) = 2000);
select tt.chk('T5 place 2 has no transfer, no opening journal', (tt.cf(2) ->> 'transfers_netted')::numeric = 0 and (tt.cf(2) ->> 'opening_in_period')::numeric = 0);

\echo == T6 working capital
select tt.as(:'o');
select stmt_working_capital() as w \gset
select tt.chk('T6 classes applied: working capital by class = current assets 954,739 - current liabilities 400 (plain formula agrees: cash + receivables + inventory - payables)', (:'w'::jsonb #>> '{by_class,working_capital}')::numeric = (:'w'::jsonb #>> '{formula,working_capital}')::numeric
  and (:'w'::jsonb #>> '{formula,payables}')::numeric = 400);
select tt.chk('T6 the fixed asset (non current) is not in working capital and is listed apart', exists (select 1 from jsonb_array_elements(:'w'::jsonb #> '{by_class,non_current_assets}') a where a ->> 'code' = '1510' and (a ->> 'amount')::numeric = 4000) and (:'w'::jsonb #>> '{by_class,totals,non_current_assets}')::numeric = 4000);
select tt.chk('T6 the working capital + non current - ... balances to the balance sheet: assets by class = the trial balance assets', (:'w'::jsonb #>> '{by_class,totals,current_assets}')::numeric + (:'w'::jsonb #>> '{by_class,totals,non_current_assets}')::numeric = (select sum(x.open_net + x.dr - x.cr) from _acct_bal(null, :'td'::date, null) x join coa_accounts a on a.id = x.account_id where a.type = 'asset' and not a.is_group));
select tt.chk('T6 the payable of the formula equals the supplier payables account of the balance sheet (2100 = 400)', (:'w'::jsonb #>> '{formula,payables}')::numeric = 400);
select id as a_1320 from coa_accounts where code = '1320' \gset
select coa_class_set(:'a_1320'::bigint, null, null, 'test: cleared') is not null as t6_clr \gset
select tt.chk('T6 an asset with a balance and no class is listed apart, a warning is shown, and it is NOT in the working capital', (stmt_working_capital() #>> '{by_class,unclassified_accounts}')::int = 1 and exists (select 1 from jsonb_array_elements(stmt_working_capital() #> '{notes}') n where n ->> 'code' = 'unclassified_balances')
  and (stmt_working_capital() #>> '{by_class,working_capital}')::numeric = (:'w'::jsonb #>> '{by_class,working_capital}')::numeric + 80);
select coa_class_set(:'a_1320'::bigint, null, 'current', 'test: back') is not null as t6_back \gset
-- no class at all
create temp table t6_save as select * from coa_report_class;
update coa_report_class set bs_class = null;
select tt.chk('T6 no balance class at all: working capital by class is NOT calculated (null, "not captured"), never 0; the formula still shows', (stmt_working_capital() #> '{by_class,working_capital}') = 'null'::jsonb
  and exists (select 1 from jsonb_array_elements(stmt_working_capital() #> '{notes}') n where n ->> 'code' = 'no_current_class') and (stmt_working_capital() #>> '{formula,payables}')::numeric = 400);
update coa_report_class c set bs_class = s.bs_class from t6_save s where s.account_id = c.account_id;
select tt.chk('T6 at an earlier date (before the sales) the figures are different: as of pm - 1 there is nothing', (stmt_working_capital(:'pm'::date - 1) #>> '{formula,cash}')::numeric = 0);
select tt.chk('T6 one place: place 2 cash 2,000', (stmt_working_capital(null, 2) #>> '{formula,cash}')::numeric = 2000);

\echo == T7 rights and places
set role authenticated; select tt.as(:'st');
select tt.err('T7 a salesperson without the profit report right cannot open the cash-flow statement', 'select stmt_cash_flow()', 'not allowed');
select tt.err('T7 ... nor the working capital', 'select stmt_working_capital()', 'not allowed');
select tt.err('T7 ... nor the drill-down', format($$select stmt_cf_drill(%L, %L, null, 'all')$$, :'pm'::date, :'td'::date), 'not allowed');
reset role;
select tt.as(:'o');
select (stmt_cash_flow(null, null, 1) ->> 'closing')::numeric as all_close1 \gset
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_profit', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select tt.chk('T7 with the profit report right he sees his place only (place 1 lines)', (stmt_cash_flow() ->> 'flows') is not null);
select tt.err('T7 but not the place filter of place 2', 'select stmt_cash_flow(null, null, 2)', 'not allowed');
select tt.chk('T7 his cash flow does not contain place 2: closing = the owner''s figure for place 1 only (lines without a place are not his to see)', (stmt_cash_flow() ->> 'closing')::numeric = :all_close1);
reset role;
set role anon;
select tt.err('T7 anonymous: nothing', 'select stmt_cash_flow()', 'permission denied');
reset role;

\echo == T7b export log (the CSV gate)
select tt.as(:'o');
select count(*) as n_exp_before from audit_log where action = 'export' and record_id = 'stmt_cash_flow' \gset
select c1_export_log('stmt_cash_flow', 'csv', '{"from":"x"}'::jsonb, 12) is null as t7b_ok \gset
select tt.chk('T7b the owner may export; one audit line is written (who, what, rows)', (select count(*) from audit_log where action = 'export' and record_id = 'stmt_cash_flow') = :n_exp_before + 1);
select tt.err('T7b an unknown report key is refused', $$select c1_export_log('daybook2', 'csv')$$, 'unknown_report');
select tt.err('T7b a bad kind is refused', $$select c1_export_log('stmt_cash_flow', 'Bad Kind!')$$, 'bad_kind');
set role authenticated; select tt.as(:'st');
select tt.err('T7b the salesperson (profit report right, no export right) cannot export', $$select c1_export_log('stmt_cash_flow', 'csv')$$, 'not allowed');
reset role;
select tt.as(:'o');
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'export_data', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select c1_export_log('stmt_cash_flow', 'csv') as t7b_st \gset
reset role;
select tt.chk('T7b with the export right AND the profit report right he may: a second audit line is there', (select count(*) from audit_log where action = 'export' and record_id = 'stmt_cash_flow') = :n_exp_before + 2);
set role authenticated; select tt.as(:'st');
select tt.err('T7b ... but not the expense register (no expense report right)', $$select c1_export_log('expense_register', 'csv')$$, 'not allowed');
reset role;
set role anon;
select tt.err('T7b anonymous: nothing', $$select c1_export_log('stmt_cash_flow', 'csv')$$, 'permission denied');
reset role;
select tt.as(:'o');

\echo == T8 accounting module not switched on
select tt.as(:'o');
select set_rule('accounting_start_date', '""'::jsonb) is null as t8_off \gset
select tt.chk('T8 no start date: the three statements carry no number and say "no data captured"', (stmt_cash_flow() ->> 'data_needed')::boolean and (stmt_working_capital() ->> 'data_needed')::boolean and (stmt_cf_drill(:'pm'::date, :'td'::date, null, 'all') ->> 'data_needed')::boolean
  and stmt_cash_flow() ->> 'text_en' like '%no data captured%' and not (stmt_cash_flow() ? 'closing') and not (stmt_working_capital() ? 'formula'));
select set_rule('accounting_start_date', to_jsonb(:'pm'::text)) is null as t8_on \gset
select tt.chk('T8 the date back: the figures are back', stmt_cash_flow() ? 'closing');

\echo == T9 the books
select tt.chk('T9 every journal entry balances', tt.unbalanced() = 0);
select tt.chk('T9 the statements posted nothing of their own (only the two entries made by this test)', (select count(*) from journal_entries) = :n_je_before + 2);

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
