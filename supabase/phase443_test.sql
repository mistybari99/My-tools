-- FRESH DB ONLY. Phase 443 tests: account classes and the P&L by month and outlet (package RPT-C1, block R3).
--   a database built through phase99, then phase440.sql .. phase443.sql  (this file pastes phase443 once more for the paste-twice check)
--   psql -h /tmp -p <port> -U postgres -d db443 -qAt -f supabase/phase443_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/c1_fixture.sql (hand-computed numbers in its header). Test data only (test_* names).
-- Hand-computed (journal, accounting start = pm): month pm: place 1 income 5,000 (cash sale), place 2 income 3,000 and rent 1,000;  this month: income = sale 400 + 3 champion 300 + 100 (+ w1d sales), see T1.
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
select tt.chk('T0 phase443 present; statements are for signed-in users only', to_regprocedure('public._c1_p443_present()') is not null
  and has_function_privilege('authenticated','public.stmt_pl_matrix(date,date,int)','execute') and not has_function_privilege('anon','public.stmt_pl_matrix(date,date,int)','execute')
  and not has_function_privilege('authenticated','public._c1_cash_ids()','execute') and not has_function_privilege('authenticated','public._c1_class_suggest(text,text)','execute')
  and has_function_privilege('authenticated','public.coa_class_set(bigint,text,text,text)','execute') and not has_function_privilege('anon','public.coa_class_set(bigint,text,text,text)','execute'));
select md5(pg_get_functiondef('public.stmt_pl_matrix(date,date,int)'::regprocedure) || pg_get_functiondef('public.coa_class_set(bigint,text,text,text)'::regprocedure)) as h_before \gset
select count(*) as n_je_before from journal_entries \gset
select count(*) as n_cls_before from coa_report_class \gset
\ir phase443.sql
select tt.chk('T0 pasting phase443 again changes nothing (no class row appears either)', md5(pg_get_functiondef('public.stmt_pl_matrix(date,date,int)'::regprocedure) || pg_get_functiondef('public.coa_class_set(bigint,text,text,text)'::regprocedure)) = :'h_before'
  and (select count(*) from coa_report_class) = :n_cls_before and :n_cls_before = 0);

\echo == T1 P&L by month and outlet = the journal
select tt.as(:'o');
select stmt_pl_matrix() as m \gset
select tt.chk('T1 months run from the accounting start to today (2 months)', jsonb_array_length(:'m'::jsonb -> 'months') = 2 and (:'m'::jsonb ->> 'from')::date = :'pm'::date);
select tt.chk('T1 first month, place 1: income 5,000, no cost, no other expense, net 5,000', exists (select 1 from jsonb_array_elements(:'m'::jsonb -> 'cells') c where c ->> 'month' = to_char(:'pm'::date,'YYYY-MM') and (c ->> 'location_id')::int = 1
  and (c ->> 'income')::numeric = 5000 and (c ->> 'expenses')::numeric = 0 and (c ->> 'net')::numeric = 5000));
select tt.chk('T1 first month, place 2: income 3,000, rent 1,000, net 2,000, gross 3,000', exists (select 1 from jsonb_array_elements(:'m'::jsonb -> 'cells') c where c ->> 'month' = to_char(:'pm'::date,'YYYY-MM') and (c ->> 'location_id')::int = 2
  and (c ->> 'income')::numeric = 3000 and (c ->> 'expenses')::numeric = 1000 and (c ->> 'gross')::numeric = 3000 and (c ->> 'net')::numeric = 2000));
select tt.chk('T1 first month total (by_month): income 8,000, expenses 1,000, net 7,000', exists (select 1 from jsonb_array_elements(:'m'::jsonb -> 'by_month') c where c ->> 'month' = to_char(:'pm'::date,'YYYY-MM') and (c ->> 'income')::numeric = 8000 and (c ->> 'expenses')::numeric = 1000 and (c ->> 'net')::numeric = 7000));
select tt.chk('T1 net = income - cost of goods - other expenses in every cell', not exists (select 1 from jsonb_array_elements(:'m'::jsonb -> 'cells') c where (c ->> 'net')::numeric <> (c ->> 'income')::numeric - (c ->> 'cogs')::numeric - (c ->> 'expenses')::numeric
  or (c ->> 'gross')::numeric <> (c ->> 'income')::numeric - (c ->> 'cogs')::numeric));
select tt.chk('T1 the cells add up to the row totals, the column totals and the grand total', (select sum((c ->> 'net')::numeric) from jsonb_array_elements(:'m'::jsonb -> 'cells') c) = (:'m'::jsonb -> 'grand' ->> 'net')::numeric
  and (select sum((c ->> 'net')::numeric) from jsonb_array_elements(:'m'::jsonb -> 'by_month') c) = (:'m'::jsonb -> 'grand' ->> 'net')::numeric
  and (select sum((c ->> 'net')::numeric) from jsonb_array_elements(:'m'::jsonb -> 'by_outlet') c) = (:'m'::jsonb -> 'grand' ->> 'net')::numeric);
select tt.chk('T1 the grand total equals the books Income statement of the same period (net profit)', (:'m'::jsonb -> 'grand' ->> 'net')::numeric = (acct_income_statement(:'pm'::date, :'td'::date, null) ->> 'net_profit')::numeric);
select tt.chk('T1 ... and its income and expenses', (:'m'::jsonb -> 'grand' ->> 'income')::numeric = (acct_income_statement(:'pm'::date, :'td'::date, null) ->> 'total_income')::numeric);
select tt.chk('T1 the answer says it is the books view, not the management view (both languages)', :'m'::jsonb #>> '{basis,text_en}' like '%not the management view%' and :'m'::jsonb #>> '{basis,text_bn}' <> '');
select tt.chk('T1 the outlets are listed with their names', jsonb_array_length(:'m'::jsonb -> 'outlets') >= 2 and exists (select 1 from jsonb_array_elements(:'m'::jsonb -> 'outlets') o where (o ->> 'location_id')::int = 1 and o ->> 'name_en' is not null));
select tt.chk('T1 the place filter: place 2 only has the first month', (select count(*) from jsonb_array_elements(stmt_pl_matrix(null, null, 2) -> 'cells') c) = 1 and (stmt_pl_matrix(null, null, 2) -> 'grand' ->> 'net')::numeric = 2000);
select tt.chk('T1 a narrower period: only the second month (from the first of this month)', (select count(*) from jsonb_array_elements(stmt_pl_matrix(date_trunc('month', :'td'::date)::date, :'td'::date) -> 'months')) = 1);

\echo == T2 outlet-less journal lines, closing journals
select acct_journal_post(:'pm'::date + 12, null, 'test no outlet income', '[{"code":"1110","debit":70},{"code":"4100","credit":70}]'::jsonb) is not null as t2_j \gset
select stmt_pl_matrix() as m2 \gset
select tt.chk('T2 a journal line without an outlet is on its own row (outlet null), with a note', exists (select 1 from jsonb_array_elements(:'m2'::jsonb -> 'outlets') o where (o ->> 'location_id') is null and (o ->> 'assigned')::boolean = false)
  and exists (select 1 from jsonb_array_elements(:'m2'::jsonb -> 'notes') n where n ->> 'code' = 'unassigned_outlet') and (:'m2'::jsonb -> 'grand' ->> 'income')::numeric = (:'m'::jsonb -> 'grand' ->> 'income')::numeric + 70);
select tt.chk('T2 and the grand total still equals the books Income statement', (:'m2'::jsonb -> 'grand' ->> 'net')::numeric = (acct_income_statement(:'pm'::date, :'td'::date, null) ->> 'net_profit')::numeric);
select tt.chk('T2 the drill-down of that cell: the account 4100 and the entry of 70', (stmt_pl_drill(:'pm'::date, null, 'income', true) -> 'accounts' -> 0 ->> 'code') = '4100' and (stmt_pl_drill(:'pm'::date, null, 'income', true) -> 'entries' -> 0 ->> 'amount')::numeric = 70);

\echo == T3 drill-down
select tt.chk('T3 drill place 1, first month, income: account 4100 = 5,000 and one entry of 5,000', (stmt_pl_drill(:'pm'::date, 1, 'income') -> 'accounts' -> 0 ->> 'amount')::numeric = 5000 and (stmt_pl_drill(:'pm'::date, 1, 'income') -> 'entries' -> 0 ->> 'amount')::numeric = 5000);
select tt.chk('T3 drill place 2, expenses: account 5300 = 1,000', (stmt_pl_drill(:'pm'::date, 2, 'expenses') -> 'accounts' -> 0 ->> 'code') = '5300' and (stmt_pl_drill(:'pm'::date, 2, 'expenses') -> 'accounts' -> 0 ->> 'amount')::numeric = 1000);
select tt.chk('T3 the drill-down of a cell adds up to the cell (this month, place 1, all kinds)', (select sum((a ->> 'amount')::numeric * case when a ->> 'kind' = 'income' then 1 else -1 end) from jsonb_array_elements(stmt_pl_drill(date_trunc('month', :'td'::date)::date, 1, 'all') -> 'accounts') a)
  = (select (c ->> 'net')::numeric from jsonb_array_elements(:'m'::jsonb -> 'cells') c where c ->> 'month' = to_char(:'td'::date,'YYYY-MM') and (c ->> 'location_id')::int = 1));
select tt.err('T3 a bad kind is refused', format($$select stmt_pl_drill(%L, 1, 'x')$$, :'pm'::date), 'bad_value');
select tt.err('T3 a bad range is refused', format($$select stmt_pl_matrix(%L, %L)$$, :'td'::date, :'pm'::date), 'bad_range');

\echo == T4 the classes (blank = unclassified, owner decides, never guessed)
select coa_class_list() as cl \gset
select tt.chk('T4 every posting account is listed; no class is set by itself', jsonb_array_length(:'cl'::jsonb) > 30 and not exists (select 1 from jsonb_array_elements(:'cl'::jsonb) a where a ->> 'cf_class' is not null or a ->> 'bs_class' is not null));
select tt.chk('T4 a suggestion is shown but not applied: 4100 operating, 1510 investing + non_current, 3100 financing, 1110 is a cash account with no flow class', exists (select 1 from jsonb_array_elements(:'cl'::jsonb) a where a ->> 'code' = '4100' and a ->> 'suggest_cf' = 'operating')
  and exists (select 1 from jsonb_array_elements(:'cl'::jsonb) a where a ->> 'code' = '1510' and a ->> 'suggest_cf' = 'investing' and a ->> 'suggest_bs' = 'non_current')
  and exists (select 1 from jsonb_array_elements(:'cl'::jsonb) a where a ->> 'code' = '3100' and a ->> 'suggest_cf' = 'financing')
  and exists (select 1 from jsonb_array_elements(:'cl'::jsonb) a where a ->> 'code' = '1110' and (a ->> 'is_cash')::boolean));
select (id)::bigint as a_4100 from coa_accounts where code = '4100' \gset
select (id)::bigint as a_1110 from coa_accounts where code = '1110' \gset
select (id)::bigint as a_2100 from coa_accounts where code = '2100' \gset
select coa_class_set(:'a_4100'::bigint, 'operating', null, 'test: sales are operating') ->> 'cf_class' as t4_set \gset
select tt.chk('T4 the owner sets a class; it is stored and audited', :'t4_set' = 'operating' and (select cf_class from coa_report_class where account_id = :'a_4100'::bigint) = 'operating'
  and exists (select 1 from audit_log where table_name = 'coa_report_class'));
select tt.err('T4 a cash account has no flow class', format($$select coa_class_set(%s, 'operating', null, null)$$, :'a_1110'), 'cash_account_has_no_flow_class');
select tt.err('T4 a balance class only for assets and liabilities', format($$select coa_class_set(%s, null, 'current', null)$$, :'a_4100'), 'balance_class_is_for_assets_and_liabilities');
select tt.err('T4 a wrong value is refused', format($$select coa_class_set(%s, 'banana', null, null)$$, :'a_4100'), 'bad_value');
select tt.err('T4 an account that does not exist', $$select coa_class_set(999999, 'operating', null, null)$$, 'account_not_found');
select tt.chk('T4 dry run applies nothing and says how many accounts it would fill', (coa_class_apply_suggested(null, true) ->> 'accounts')::int > 20 and (select count(*) from coa_report_class) = 1);
select tt.err('T4 applying for real needs a reason', $$select coa_class_apply_suggested(null, false)$$, 'reason_required');
select coa_class_set(:'a_2100'::bigint, null, 'non_current', 'test: owner decides this one') is not null as t4_own \gset
select coa_class_apply_suggested('test: apply the usual practice', false) ->> 'accounts' as t4_n \gset
select tt.chk('T4 apply fills blanks only and never overwrites: 2100 stays non_current (the owner set it), 4100 keeps its class and others are filled', (select bs_class from coa_report_class where account_id = :'a_2100'::bigint) = 'non_current'
  and (select cf_class from coa_report_class where account_id = :'a_4100'::bigint) = 'operating' and (select count(*) from coa_report_class) > 20
  and not exists (select 1 from coa_report_class where account_id = :'a_1110'::bigint and cf_class is not null));
select coa_class_set(:'a_4100'::bigint, null, null, 'test: cleared') is not null as t4_clr \gset
select tt.chk('T4 clearing a class blanks it (the row stays: nothing is deleted)', exists (select 1 from coa_report_class where account_id = :'a_4100'::bigint and cf_class is null and bs_class is null));
select tt.err('T4 a class row cannot be deleted', format($$delete from coa_report_class where account_id = %s$$, :'a_4100'), '');

\echo == T5 rights and places
set role authenticated; select tt.as(:'st');
select tt.err('T5 a salesperson without the profit report right cannot open the P&L matrix', 'select stmt_pl_matrix()', 'not allowed');
select tt.err('T5 ... nor the class list', 'select coa_class_list()', 'not allowed');
select tt.err('T5 ... nor set a class', format($$select coa_class_set(%s, 'operating', null, null)$$, :'a_4100'), 'not allowed');
reset role;
select tt.as(:'o');
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_profit', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select tt.chk('T5 with the profit report right he sees only his place (place 1), not place 2', exists (select 1 from jsonb_array_elements(stmt_pl_matrix() -> 'cells') c where (c ->> 'location_id')::int = 1) and not exists (select 1 from jsonb_array_elements(stmt_pl_matrix() -> 'cells') c where (c ->> 'location_id')::int = 2));
select tt.err('T5 and not the place filter of a place he cannot see', 'select stmt_pl_matrix(null, null, 2)', 'not allowed');
select tt.err('T5 a reader cannot set a class (only the owner / accounts manager)', format($$select coa_class_set(%s, 'operating', null, null)$$, :'a_4100'), 'not allowed');
reset role;
set role authenticated; select tt.as(:'acc');
select tt.chk('T5 the accounts manager (all places) sees both places and may set a class', exists (select 1 from jsonb_array_elements(stmt_pl_matrix() -> 'cells') c where (c ->> 'location_id')::int = 2) and coa_class_set(:'a_4100'::bigint, 'operating', null, 'test') is not null);
reset role;
set role anon;
select tt.err('T5 anonymous: nothing', 'select stmt_pl_matrix()', 'permission denied');
reset role;

\echo == T6 accounting module not switched on: no number, a clear notice
select tt.as(:'o');
select set_rule('accounting_start_date', '""'::jsonb) is null as t6_off \gset
select tt.chk('T6 without the accounting start date the matrix carries no number: data_needed and the "no data captured" text, in both languages', (stmt_pl_matrix() ->> 'data_needed')::boolean and stmt_pl_matrix() ->> 'text_en' like '%no data captured%'
  and stmt_pl_matrix() ->> 'text_bn' <> '' and not (stmt_pl_matrix() ? 'grand') and not (stmt_pl_matrix() ? 'cells'));
select tt.chk('T6 the drill-down also says data_needed', (stmt_pl_drill(:'pm'::date, 1, 'income') ->> 'data_needed')::boolean);
select set_rule('accounting_start_date', to_jsonb(:'pm'::text)) is null as t6_on \gset
select tt.chk('T6 the date back: the figures are back', stmt_pl_matrix() ? 'grand');

\echo == T7 the books
select tt.chk('T7 every journal entry balances', tt.unbalanced() = 0);
select tt.chk('T7 the statements posted nothing of their own (only the one entry made by this test)', (select count(*) from journal_entries) = :n_je_before + 1);

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
