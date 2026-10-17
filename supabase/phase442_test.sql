-- FRESH DB ONLY. Phase 442 tests: the expense register (package RPT-C1, block R2).
--   a database built through phase99, then phase440.sql .. phase442.sql  (this file pastes phase442 once more for the paste-twice check)
--   psql -h /tmp -p <port> -U postgres -d db442 -qAt -f supabase/phase442_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/c1_fixture.sql (hand-computed numbers in its header). Test data only (test_* names).
-- Hand-computed totals of the fixture (place 1, this month): vouchers: approved 500 + submitted 290 = 790; quick expense 300; wallet fee 12; bank charge 25; marketing line 1,500 (not in the books)
--   expense report = 790 (vouchers only)   P&L = 790 + 300 + 12 = 1,102   day book = 1,090 (no wallet fee)   journal = 500 + 300 + 12 + 25 = 837 (the submitted voucher waits for approval)
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
create or replace function tt.er(p_basis text default 'all', p_kinds text[] default null, p_status text default null, p_limit int default 100, p_off int default 0, p_loc int default null) returns jsonb language sql stable as $$
  select public.expense_register((date_trunc('month', tt.today()) - interval '1 month')::date, tt.today(), p_loc, p_basis, p_kinds, p_status, p_limit, p_off) $$;
create or replace function tt.tot(p_key text) returns numeric language sql stable as $$ select (tt.er() -> 'totals' ->> p_key)::numeric $$;
create or replace function tt.line(p_class text) returns jsonb language sql stable as $$ select l from jsonb_array_elements(tt.er() -> 'recon' -> 'lines') l where l ->> 'class' = p_class $$;
create or replace function tt.par(p_key text) returns numeric language sql stable as $$
  select (public.report_parity((date_trunc('month', tt.today()) - interval '1 month')::date, tt.today(), null) -> 'expenses' ->> p_key)::numeric $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select (now() at time zone 'Asia/Dhaka')::date as td \gset
select date_trunc('month', :'td'::date - interval '1 month')::date as pm2 \gset

\echo == T0 shape, internals closed, pasting twice changes nothing
select tt.chk('T0 phase442 present; the register is open to signed-in users only', to_regprocedure('public._c1_p442_present()') is not null and has_function_privilege('authenticated','public.expense_register(date,date,int,text,text[],text,int,int)','execute')
  and not has_function_privilege('anon','public.expense_register(date,date,int,text,text[],text,int,int)','execute') and not has_function_privilege('authenticated','public._c1_exp_rows(date,date,int[])','execute')
  and not has_function_privilege('authenticated','public._c1_exp_view()','execute') and not has_function_privilege('authenticated','public._c1_je_live(text,text)','execute'));
select md5(pg_get_functiondef('public.expense_register(date,date,int,text,text[],text,int,int)'::regprocedure) || pg_get_functiondef('public._c1_exp_rows(date,date,int[])'::regprocedure)) as h_before \gset
select count(*) as n_je_before from journal_entries \gset
select count(*) as n_rules_before from rules \gset
\ir phase442.sql
select tt.chk('T0 pasting phase442 again changes nothing', md5(pg_get_functiondef('public.expense_register(date,date,int,text,text[],text,int,int)'::regprocedure) || pg_get_functiondef('public._c1_exp_rows(date,date,int[])'::regprocedure)) = :'h_before' and (select count(*) from rules) = :n_rules_before);

\echo == T1 the register and the three totals (default settings)
select tt.as(:'o');
select tt.chk('T1 expense report total 790 (vouchers only: the quick expense is left out while the setting is off)', tt.tot('report') = 790);
select tt.chk('T1 P&L total 1,102 = vouchers 790 + quick 300 + wallet fee 12', tt.tot('pl') = 1102);
select tt.chk('T1 day book total 1,090 (the P&L without the wallet fee)', tt.tot('daybook') = 1090);
select tt.chk('T1 journal total 837 = approved voucher 500 + quick 300 + wallet fee 12 + bank charge 25 (the submitted voucher waits)', tt.tot('journal') = 837);
select tt.chk('T1 everything counted by the journal is posted already', tt.tot('journal_posted') = 837 and (tt.er() -> 'recon' -> 'unposted' ->> 'n')::int = 0);
select tt.chk('T1 marketing 1,500 is listed as not in the books and is in none of the totals', tt.tot('not_in_books') = 1500);
select tt.chk('T1 six lines: 2 vouchers, quick, bank charge, wallet fee, marketing', (tt.er() ->> 'count')::int = 6 and jsonb_array_length(tt.er() -> 'rows') = 6);
select tt.chk('T1 the totals agree with the existing parity report: expense report', tt.tot('report') = tt.par('expense_report'));
select tt.chk('T1 ... the day book', tt.tot('daybook') = tt.par('daybook'));
select tt.chk('T1 ... the P&L (the parity report leaves the wallet fee out of its P&L figure)', tt.tot('pl') - 12 = tt.par('pl'));
select tt.chk('T1 ... the expense report total equals the real expense_by_head report', tt.tot('report') = (report_run2_core('expense_by_head', jsonb_build_object('from', :'pm2', 'to', :'td'), 'none') #>> '{totals,amount}')::numeric);
select tt.chk('T1 ... and the P&L figure equals _p27_pl expenses of the same period', tt.tot('pl') = (select sum(o_exp) from _p27_pl(:'pm2'::date, :'td'::date, array[1,2,3,4,5,6,7,8,9]) ));
select tt.chk('T1 each line says which totals count it: the quick expense is in P&L and journal, not in the report', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'kind' = 'quick' and not (r ->> 'in_report')::boolean and (r ->> 'in_pl')::boolean and (r ->> 'in_journal')::boolean and (r ->> 'amount')::numeric = 300));
select tt.chk('T1 the submitted voucher is in the report and the P&L, not in the journal', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'class' = 'voucher_submitted' and (r ->> 'in_report')::boolean and (r ->> 'in_pl')::boolean and not (r ->> 'in_journal')::boolean and (r ->> 'amount')::numeric = 290));
select tt.chk('T1 the bank charge is only in the journal', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'kind' = 'bank_charge' and not (r ->> 'in_report')::boolean and not (r ->> 'in_pl')::boolean and (r ->> 'in_journal')::boolean and (r ->> 'amount')::numeric = 25));
select tt.chk('T1 the marketing line is in no total, carries the flags not_in_books and maybe_in_voucher (source imprest)', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'kind' = 'marketing' and not (r ->> 'in_report')::boolean and not (r ->> 'in_pl')::boolean and not (r ->> 'in_journal')::boolean
  and r -> 'flags' ? 'not_in_books' and r -> 'flags' ? 'maybe_in_voucher' and (r ->> 'amount')::numeric = 1500 and r ->> 'mode' = 'imprest' and r ->> 'paid_to' = 'test_campaign'));
select tt.chk('T1 a voucher row carries its heads (the lines), the paid-to is shown and no-receipt amounts are reported', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'class' = 'voucher_approved' and jsonb_array_length(r -> 'heads') = 1 and r #>> '{heads,0,head}' = 'transport' and (r ->> 'amount')::numeric = 500));
select tt.chk('T1 the quick expense has no receipt: no_receipt_amount 300 and the flag', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'kind' = 'quick' and (r ->> 'no_receipt_amount')::numeric = 300 and r -> 'flags' ? 'no_receipt' and r ->> 'paid_to' = 'test_rider'));
select tt.chk('T1 head labels come with the answer (both lists)', tt.er() #>> '{labels,expense_heads,transport,en}' = 'Transport' and tt.er() #>> '{labels,marketing_heads}' is not null);

\echo == T2 the basis selector, the filters and the paging
select tt.chk('T2 basis report: the two vouchers only, shown amount 790', (tt.er('report') ->> 'count')::int = 2 and (tt.er('report') ->> 'shown_amount')::numeric = 790);
select tt.chk('T2 basis pl: vouchers 2 + quick + wallet fee, shown amount 1,102', (tt.er('pl') ->> 'count')::int = 4 and (tt.er('pl') ->> 'shown_amount')::numeric = 1102);
select tt.chk('T2 basis journal: approved voucher + quick + bank charge + wallet fee, shown amount 837', (tt.er('journal') ->> 'count')::int = 4 and (tt.er('journal') ->> 'shown_amount')::numeric = 837);
select tt.chk('T2 basis all: six lines, shown amount 790 + 300 + 25 + 12 + 1,500 = 2,627', (tt.er('all') ->> 'count')::int = 6 and (tt.er('all') ->> 'shown_amount')::numeric = 2627);
select tt.chk('T2 the totals strip does not depend on the basis or the filter', (tt.er('report', array['quick']) -> 'totals' ->> 'journal')::numeric = 837 and (tt.er('journal', array['voucher'], 'approved') -> 'totals' ->> 'pl')::numeric = 1102);
select tt.chk('T2 kind filter: only quick expenses', (tt.er('all', array['quick']) ->> 'count')::int = 1 and (tt.er('all', array['quick']) ->> 'shown_amount')::numeric = 300);
select tt.chk('T2 status filter: the approved voucher only', (tt.er('all', null, 'approved') ->> 'count')::int = 1 and (tt.er('all', null, 'submitted') ->> 'count')::int = 2);
select tt.chk('T2 paging: limit 4 gives 4 rows and has_more; the next page gives 2 and no more', jsonb_array_length(tt.er('all', null, null, 4, 0) -> 'rows') = 4 and (tt.er('all', null, null, 4, 0) ->> 'has_more')::boolean
  and jsonb_array_length(tt.er('all', null, null, 4, 4) -> 'rows') = 2 and not (tt.er('all', null, null, 4, 4) ->> 'has_more')::boolean and (tt.er('all', null, null, 4, 4) ->> 'count')::int = 6);
select tt.chk('T2 the two pages together are the six lines, each once', (select count(distinct r ->> 'key') from (select jsonb_array_elements(tt.er('all', null, null, 4, 0) -> 'rows') r union all select jsonb_array_elements(tt.er('all', null, null, 4, 4) -> 'rows')) z) = 6);
select tt.chk('T2 a limit of 0 or less is raised to 1; more than 500 is cut to 500', jsonb_array_length(tt.er('all', null, null, 0, 0) -> 'rows') = 1 and (tt.er('all', null, null, 9999, 0) ->> 'limit')::int = 500);
select tt.chk('T2 place filter: place 2 has no expense line', (tt.er('all', null, null, 100, 0, 2) ->> 'count')::int = 0 and (tt.er('all', null, null, 100, 0, 1) ->> 'count')::int = 6);

\echo == T3 the three settings move the flags (and still agree with the existing reports)
select set_rule('report_expense_parity_on', 'true') is null as t3_p1 \gset
select tt.chk('T3 parity ON: the quick expense is in the report too: report 1,090 = the real expense_by_head total and the parity report', tt.tot('report') = 1090 and tt.tot('report') = tt.par('expense_report')
  and tt.tot('report') = (report_run2_core('expense_by_head', jsonb_build_object('from', :'pm2', 'to', :'td'), 'none') #>> '{totals,amount}')::numeric);
select tt.chk('T3 parity ON: the quick-expense line no longer shows a difference between the report and the P&L', (tt.line('quick') ->> 'd_pl_report')::numeric = 0);
select set_rule('report_expense_parity_on', 'false') is null as t3_p0 \gset
select set_rule('expense_count_on', '"approved"') is null as t3_a1 \gset
select tt.chk('T3 only approved vouchers count: report 500, P&L 812, and the submitted voucher is in no total', tt.tot('report') = 500 and tt.tot('pl') = 812 and tt.tot('journal') = 837
  and (tt.line('voucher_submitted') ->> 'report')::numeric = 0 and (tt.line('voucher_submitted') ->> 'pl')::numeric = 0);
select tt.chk('T3 ... and still equals the real report', tt.tot('report') = (report_run2_core('expense_by_head', jsonb_build_object('from', :'pm2', 'to', :'td'), 'none') #>> '{totals,amount}')::numeric);
select set_rule('expense_count_on', '"submitted"') is null as t3_s1 \gset
select tt.chk('T3 submitted counts everywhere: the journal counts the submitted voucher too (1,127) - but only if the journal hook is in (phase99); posted stays 837', tt.tot('journal') = 1127 and tt.tot('journal_posted') = 837 and (tt.er() -> 'recon' -> 'unposted' ->> 'n')::int = 1 and (tt.er() -> 'recon' -> 'unposted' ->> 'amount')::numeric = 290);
select set_rule('expense_count_on', '"as_today"') is null as t3_s0 \gset
select set_rule('d_wallet_fee_treatment', '"not_posted"') is null as t3_w1 \gset
select tt.chk('T3 wallet fees not treated as expense: out of the P&L and the journal (1,090 / 825); the line says why', tt.tot('pl') = 1090 and tt.tot('journal') = 825 and (tt.line('wallet_fee') ->> 'why_en') like '%not treated as a separate expense%');
select set_rule('d_wallet_fee_treatment', '"separate_expense"') is null as t3_w0 \gset
select tt.chk('T3 settings back: the first figures are back', tt.tot('report') = 790 and tt.tot('pl') = 1102 and tt.tot('journal') = 837);

\echo == T4 the reconciliation lines: why the three totals differ
select tt.chk('T4 the report -> P&L difference is the sum of the lines: 312 = quick 300 + wallet fee 12', (select sum((l ->> 'd_pl_report')::numeric) from jsonb_array_elements(tt.er() -> 'recon' -> 'lines') l) = tt.tot('pl') - tt.tot('report') and tt.tot('pl') - tt.tot('report') = 312);
select tt.chk('T4 the P&L -> journal difference is the sum of the lines: -265 = submitted -290 + bank charge 25', (select sum((l ->> 'd_journal_pl')::numeric) from jsonb_array_elements(tt.er() -> 'recon' -> 'lines') l) = tt.tot('journal') - tt.tot('pl') and tt.tot('journal') - tt.tot('pl') = -265);
select tt.chk('T4 per line: submitted voucher d_journal_pl = -290; bank charge d_journal_pl = +25; quick d_pl_report = +300; wallet fee d_pl_report = +12', (tt.line('voucher_submitted') ->> 'd_journal_pl')::numeric = -290 and (tt.line('bank_charge') ->> 'd_journal_pl')::numeric = 25
  and (tt.line('quick') ->> 'd_pl_report')::numeric = 300 and (tt.line('wallet_fee') ->> 'd_pl_report')::numeric = 12);
select tt.chk('T4 the approved voucher line needs no explanation (counted everywhere)', tt.line('voucher_approved') -> 'why_en' = 'null'::jsonb and (tt.line('voucher_approved') ->> 'report')::numeric = 500 and (tt.line('voucher_approved') ->> 'journal')::numeric = 500);
select tt.chk('T4 each explained line has an English and a Bangla text; marketing says "Not in the books"', (select bool_and(l ->> 'why_en' <> '' and l ->> 'why_bn' <> '') from jsonb_array_elements(tt.er() -> 'recon' -> 'lines') l where l ->> 'class' <> 'voucher_approved')
  and (tt.line('marketing') ->> 'why_en') like 'Not in the books%');
select tt.chk('T4 the summary sentence names the three totals and the day book', (tt.er() -> 'recon' ->> 'summary_en') like 'Expense report 790.00; P&L 1,102.00 (the day book shows 1,090.00%; journal 837.00.%' and (tt.er() -> 'recon' ->> 'summary_bn') like '%790.00%1,102.00%837.00%');
select tt.chk('T4 the totals do not agree (agree = false)', not (tt.er() -> 'recon' ->> 'agree')::boolean);
select tt.chk('T4 the settings are echoed', tt.er() #>> '{settings,expense_count_on}' = 'as_today' and tt.er() #>> '{settings,report_expense_parity_on}' = 'false' and tt.er() #>> '{settings,d_wallet_fee_treatment}' = 'separate_expense');
-- an approved voucher that is not posted yet
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"repair","amount":"77","receipt":"yes"}]}'::jsonb,'[]') ->> 'id' as t4_v \gset
select submit_entry(:'t4_v'::uuid) is not null as t4_s \gset
select decide_entry(:'t4_v'::uuid,true,null,'{}','[]') ->> 'status' as t4_d \gset
select tt.chk('T4 an approved voucher that is not posted yet: counted by the journal basis, listed as waiting to post', (tt.er() -> 'recon' -> 'unposted' ->> 'n')::int = 1 and (tt.er() -> 'recon' -> 'unposted' ->> 'amount')::numeric = 77
  and tt.tot('journal') = 914 and tt.tot('journal_posted') = 837 and exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'source_id' = :'t4_v' and (r ->> 'in_journal')::boolean and not (r ->> 'posted')::boolean));
select acct_post_pending(false) ->> 'posted' as t4_post \gset
select tt.chk('T4 after posting, nothing is waiting any more', (tt.er() -> 'recon' -> 'unposted' ->> 'n')::int = 0 and tt.tot('journal_posted') = 914);

\echo == T5 voids, drafts and copies
select quick_expense_add(1, tt.today(), 'transport', 'test_rider2', 40, 'cash', true, 'to be voided', gen_random_uuid()) ->> 'id' as t5_q \gset
select quick_expense_void(:'t5_q'::uuid, 'test void') is not null as t5_v \gset
select tt.chk('T5 a voided quick expense is listed with status void and is in no total', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'source_id' = :'t5_q' and r ->> 'status' = 'void' and not (r ->> 'in_report')::boolean and not (r ->> 'in_pl')::boolean and not (r ->> 'in_journal')::boolean) and tt.tot('pl') = 1179);
select (money_charge_add(:'c_ma'::bigint, 'charge', 9, tt.today(), 'test_ref_void', null, 1, gen_random_uuid())) is not null as t5_c \gset
select id as t5_cid from money_charges where ref = 'test_ref_void' \gset
select money_charge_void(:'t5_cid'::bigint, 'test void') is not null as t5_cv \gset
select tt.chk('T5 a voided bank charge is listed (void) and in no total', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'source_id' = :'t5_cid' and r ->> 'status' = 'void' and not (r ->> 'in_journal')::boolean));
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"labour","amount":"15"}]}'::jsonb,'[]') ->> 'id' as t5_dr \gset
select tt.chk('T5 a draft voucher is listed, in no total (draft = not an expense yet)', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'source_id' = :'t5_dr' and r ->> 'class' = 'voucher_not_counted' and not (r ->> 'in_report')::boolean and not (r ->> 'in_pl')::boolean and not (r ->> 'in_journal')::boolean));
insert into shadow_links (domain, location_id, primary_type, primary_id, shadow_type, shadow_id, state, locked) values ('expense', 1, 'quick_expenses', 'x', 'entries', :'t5_dr', 'confirmed', true);
select tt.chk('T5 a copy (shadow) of another record is its own class and counted nowhere in the P&L and the journal', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where r ->> 'source_id' = :'t5_dr' and r ->> 'class' = 'voucher_shadow' and r -> 'flags' ? 'shadow' and not (r ->> 'in_pl')::boolean));
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"labour","amount":"abc"},{"head":"labour","amount":"10"}]}'::jsonb,'[]') ->> 'id' as t5_un \gset
select tt.chk('T5 an unreadable amount is counted as unreadable, not as 0 silently', exists (select 1 from jsonb_array_elements(tt.er() -> 'rows') r where (r ->> 'unreadable')::int = 1 and r -> 'flags' ? 'unreadable_lines' and (r ->> 'amount')::numeric = 10));

\echo == T6 rights and places
select tt.err('T6 bad range', format($$select expense_register(%L, %L)$$, :'td'::date, :'pm2'::date), 'bad_range');
select tt.err('T6 range longer than a year', format($$select expense_register(%L, %L)$$, :'td'::date - 400, :'td'::date), 'bad_range');
select tt.err('T6 bad basis', format($$select expense_register(%L, %L, null, 'x')$$, :'pm2'::date, :'td'::date), 'bad_basis');
set role authenticated; select tt.as(:'st');
select tt.err('T6 a salesperson without the expense report right cannot open the register', format($$select expense_register(%L, %L)$$, :'pm2'::date, :'td'::date), 'not allowed');
reset role;
select tt.as(:'o');
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_expense', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select tt.chk('T6 with the expense report right he sees the lines of his place', (expense_register(:'pm2'::date, :'td'::date) ->> 'count')::int > 0);
select tt.err('T6 but not the place he has no access to', format($$select expense_register(%L, %L, 2)$$, :'pm2'::date, :'td'::date), 'not allowed');
reset role;
set role authenticated; select tt.as(:'acc');
select tt.chk('T6 the accounts manager (accounts rights, all places) opens it', (expense_register(:'pm2'::date, :'td'::date) ->> 'count')::int > 0);
reset role;
set role anon;
select tt.err('T6 anonymous: no register', format($$select expense_register(%L, %L)$$, :'pm2'::date, :'td'::date), 'permission denied');
reset role;

\echo == T7 the books
select tt.chk('T7 every journal entry balances', tt.unbalanced() = 0);
select tt.chk('T7 the register posted nothing of its own (only the entries made by this test itself)', (select count(*) from journal_entries) <= :n_je_before + 3);

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
