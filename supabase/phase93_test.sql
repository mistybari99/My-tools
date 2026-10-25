-- FRESH DB ONLY. Phase 93 tests: U-06 report parity and dated brand map (package W1-D).
--   a database built through phase87, then  psql -f supabase/phase92.sql  and  psql -f supabase/phase93.sql
--   psql -h /tmp -p <port> -U postgres -d db93 -qAt -f supabase/phase93_test.sql | grep -E 'FAIL|RESULT'
-- The data comes from tests/sql/w1d_fixture.sql (hand-computed numbers in its header) plus the records made below. Test data only (test_* names). Places 1 and 2 only.
\set ON_ERROR_STOP off
\ir ../tests/sql/w1d_fixture.sql
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
create or replace function tt.sal(p_from date) returns numeric language sql stable as $$ select sum(o_sal) from public._p27_pl(p_from, tt.today(), array[1]) $$;
create or replace function tt.exp(p_from date) returns numeric language sql stable as $$ select sum(o_exp) from public._p27_pl(p_from, tt.today(), array[1]) $$;
create or replace function tt.rep_total(p_from date) returns numeric language sql stable as $$
  select (public.report_run2_core('expense_by_head', jsonb_build_object('from', p_from, 'to', tt.today()), 'none') #>> '{totals,amount}')::numeric $$;
create or replace function tt.brand(p_code text) returns numeric language sql stable as $$
  select revenue from public.brand_pnl((select date_trunc('month', tt.today() - interval '1 month')::date), tt.today(), p_code) where brand_code = p_code $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select (now() at time zone 'Asia/Dhaka')::date as td \gset
select date_trunc('month', :'td'::date)::date as m1 \gset
select :'pm'::date as d1 \gset

\echo == T0 shape, safe defaults, patches in place, internals closed
select tt.chk('T0 phase93 present; settings default: salary legacy, parity off, voucher rule as_today, brand dating off',
  to_regprocedure('public._w1d_p93_present()') is not null and rule_txt('report_salary_source') = 'legacy' and not rule_on('report_expense_parity_on') and rule_txt('expense_count_on') = 'as_today' and not rule_on('brand_map_dated_on'));
select tt.chk('T0 labels and hints are English and not empty (owner rule 5)', not exists (select 1 from rules where key in ('report_salary_source','report_expense_parity_on','expense_count_on','brand_map_dated_on') and (label_en is null or hint_en is null or label_bn <> label_en or label_en ~ '[^ -~]')));
select tt.chk('T0 the patches are in place (marker bos93) in _p27_pl, report_run2_core, E3, E2, brand_pnl',
  (select count(*) from (values ('public._p27_pl(date,date,int[])'),('public.report_run2_core(text,jsonb,text,text,int)'),('public._r3q_e3_weak_control(date,date,int[],jsonb)'),('public._r3q_e2_expense_trend(date,date,int[],jsonb)'),('public.brand_pnl(date,date,text)')) v(f)
   where position('bos93' in pg_get_functiondef(v.f::regprocedure)) > 0) = 5);
select tt.chk('T0 the earlier tags are still there (bos92, bos86, bos50 in _p27_pl)', (select bool_and(position(t in pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure)) > 0) from unnest(array['bos92','bos86','bos50','bos85']) t));
select tt.chk('T0 internals closed, API open, anon nothing', not has_function_privilege('authenticated','public._w1d_hooks_apply()','execute') and not has_function_privilege('authenticated','public._w1d_brand_at(int,date)','execute')
  and has_function_privilege('authenticated','public.report_parity(date,date,int)','execute') and has_function_privilege('authenticated','public.brand_map_set(int,text,text,text,date,text)','execute')
  and not has_function_privilege('anon','public.report_parity(date,date,int)','execute') and not has_function_privilege('anon','public.brand_map_set(int,text,text,text,date,text)','execute')
  and not has_table_privilege('authenticated','public.report_brand_map_hist','insert') and not has_table_privilege('anon','public.report_brand_map_hist','select'));
select md5(pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure)) || md5(pg_get_functiondef('public.report_run2_core(text,jsonb,text,text,int)'::regprocedure)) || md5(pg_get_functiondef('public.brand_pnl(date,date,text)'::regprocedure)) as h_before \gset
select count(*) as n_hist_before from report_brand_map_hist \gset
\ir phase93.sql
select tt.chk('T0 pasting phase93 again changes nothing (function bodies identical, same history rows)',
  md5(pg_get_functiondef('public._p27_pl(date,date,int[])'::regprocedure)) || md5(pg_get_functiondef('public.report_run2_core(text,jsonb,text,text,int)'::regprocedure)) || md5(pg_get_functiondef('public.brand_pnl(date,date,text)'::regprocedure)) = :'h_before'
  and (select count(*) from report_brand_map_hist) = :n_hist_before);
select tt.chk('T0 the history was filled from the map that existed: 4 rows, valid from the beginning, all active', :n_hist_before = 4 and not exists (select 1 from report_brand_map_hist where valid_from is not null or valid_to is not null or not active));

\echo == T1 DEFAULTS KEEP TODAY
select tt.as(:'o');
select tt.chk('T1 P&L expenses 800 (voucher 500 + quick 300, as before phase93)', tt.exp(:'d1'::date) = 800);
select tt.chk('T1 the expense report still shows only the voucher: 500 (the known gap, unchanged while the switch is off)', tt.rep_total(:'d1'::date) = 500);
select tt.chk('T1 report_parity says so: day book 800, P&L 800, expense report 500, journal 800 -> not in agreement', (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'expense_report')::numeric = 500
  and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'daybook')::numeric = 800 and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'pl')::numeric = 800
  and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'journal')::numeric = 800 and not (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'agree')::boolean);
select tt.chk('T1 the control report E3 has no quick-expense row while the switch is off', not exists (select 1 from _r3q_e3_weak_control(:'d1'::date, :'td'::date, array[1], '{}'::jsonb) x where x ->> 'source' = 'quick'));

\echo == T2 expense parity switch: expense report and E3 count the same expenses as the P&L
select set_rule('report_expense_parity_on', 'true') is null as ep1 \gset
select tt.chk('T2 expense report 800 (voucher 500 + quick 300)', tt.rep_total(:'d1'::date) = 800);
select tt.chk('T2 the four totals agree: day book 800, P&L 800, expense report 800, journal 800', (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'agree')::boolean);
select tt.chk('T2 E3 now has a quick row: 1 quick expense, 1 line without a receipt of 300', exists (select 1 from _r3q_e3_weak_control(:'d1'::date, :'td'::date, array[1], '{}'::jsonb) x
  where x ->> 'source' = 'quick' and (x ->> 'vouchers')::int = 1 and (x ->> 'no_receipt_lines')::int = 1 and (x ->> 'no_receipt_amount')::numeric = 300));
-- a day-end shadow voucher made from the quick expense must not be counted again
select quick_expense_close_day(1, :'td'::date) ->> 'made' as made \gset
select id as w_shadow from entries where form_code = '10-2' and (data ->> 'from_quick') = 'true' \gset
update entries set status = 'approved' where id = :'w_shadow'::uuid;
select tt.chk('T2 the day-end copy (a locked shadow, approved) is not counted again: expense report still 800, P&L still 800, journal still 800', :'made' = '1' and is_shadow('entries', :'w_shadow') and tt.rep_total(:'d1'::date) = 800 and tt.exp(:'d1'::date) = 800
  and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'agree')::boolean);
select set_rule('report_expense_parity_on', 'false') is null as ep2 \gset
select tt.chk('T2 switch off again: the old report (voucher 500 + the shadow 300 = 800 once the day is closed, the old way)', tt.rep_total(:'d1'::date) = 800);

\echo == T3 salary: an approved payroll run of 8000 and a 02-2 sheet of 7000 for the same month and place
insert into employees (employee_no, full_name_bn, status, primary_location_id) values ('TEST93_A','test_emp','active',1) returning id as ea \gset
with x as (insert into payroll_runs (month, location_id, status) values (:'pm', 1, 'draft') returning id) select id as run1 from x \gset
with x as (insert into payroll_lines (run_id, month, employee_id, location_id, gross, net) values (:'run1', :'pm', :'ea', 1, 8000, 8000) returning id) select id as l1 from x \gset
select payroll_approve(:'run1'::bigint) ->> 'status' as ap \gset
select payroll_pay(:'run1'::bigint, array[:'l1'::bigint], 'bank', :'td'::date, 'w1d-sal', null, gen_random_uuid(), null) is not null as pp \gset
select extract(month from :'pm'::date)::int as pmm, extract(year from :'pm'::date)::int as pyy \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
  ('02-2',1,93001,:'pm'::date + 2,'approved',format('{"month":"%s","year":"%s","pay":[{"name":"test_emp","due":"7000","overtime":"0","other":"0"}],"receipts":[]}',:'pmm',:'pyy')::jsonb,'[]',:'o','t');
select id as e22 from entries where form_code = '02-2' and serial = 93001 \gset
select tt.chk('T3 the sheet became a locked shadow of the run (the normal path)', is_shadow('entries', :'e22') and not is_shadow('payroll_runs', :'run1'::text));
select acct_post_pending(false) ->> 'posted' as pp2 \gset
select tt.chk('T3 legacy, accrual off (today): the P&L salary is the sheet, 7000; the run is invisible', tt.sal(:'d1'::date) = 7000);
select tt.chk('T3 the journal and the day book carry the run: 8000 paid, journal salary 8000', (report_parity(:'d1'::date, :'td'::date, null) -> 'salary' ->> 'journal')::numeric = 8000 and (report_parity(:'d1'::date, :'td'::date, null) -> 'salary' ->> 'daybook_paid')::numeric = 8000);
select tt.chk('T3 so today the P&L (7000) and the journal (8000) disagree and report_parity says so', not (report_parity(:'d1'::date, :'td'::date, null) -> 'salary' ->> 'pl_agrees_journal')::boolean);
select set_rule('report_salary_source', '"app_first"') is null as ss1 \gset
select tt.chk('T3 app_first, accrual off: the run is primary, the sheet is the fallback only where no run exists: 8000', tt.sal(:'d1'::date) = 8000);
select tt.chk('T3 now the P&L salary equals the journal salary (8000) and the day book paid (8000, no advance recovery)', (report_parity(:'d1'::date, :'td'::date, null) -> 'salary' ->> 'pl_agrees_journal')::boolean
  and (report_parity(:'d1'::date, :'td'::date, null) -> 'salary' ->> 'daybook_agrees_journal_less_recovery')::boolean);
-- the sheet and the run both counted (no link: both paths open) = the double count that app_first prevents
update shadow_links set state = 'void' where domain = 'payroll' and primary_id = :'run1';
select tt.chk('T3 without the link neither is a shadow', not is_shadow('entries', :'e22') and not is_shadow('payroll_runs', :'run1'::text));
select tt.chk('T3 app_first with form AND run both present, neither a shadow: 8000, counted once', tt.sal(:'d1'::date) = 8000);
select set_rule('payroll_accrual_on', 'true') is null as ac1 \gset
select tt.chk('T3 app_first + accrual on: still 8000 once', tt.sal(:'d1'::date) = 8000);
select set_rule('report_salary_source', '"legacy"') is null as ss2 \gset
select tt.chk('T3 legacy + accrual on + both present and not linked: 7000 + 8000 = 15000 (the double count of today, unchanged while the setting is legacy)', tt.sal(:'d1'::date) = 15000);
select set_rule('payroll_accrual_on', 'false') is null as ac2 \gset
select set_rule('report_salary_source', '"app_first"') is null as ss3 \gset
insert into entries (form_code,location_id,serial,entry_date,status,data,flags,created_by,created_staff) values
  ('02-2',1,93002,:'td'::date,'approved',format('{"month":"%s","year":"%s","pay":[{"name":"test_emp","due":"1000","overtime":"200","other":"50"}],"receipts":[]}',extract(month from :'td'::date)::int,extract(year from :'td'::date)::int)::jsonb,'[]',:'o','t');
select tt.chk('T3 app_first: this month has a sheet of 1250 and no run, so the sheet is the fallback: 8000 (last month run) + 1250', tt.sal(:'d1'::date) = 9250);
update entries set status = 'rejected' where form_code = '02-2' and serial = 93002;
select tt.chk('T3 the sheet is rejected: it no longer counts, 8000 again', tt.sal(:'d1'::date) = 8000);

\echo == T4 voucher rule expense_count_on: one rule in the P&L, the expense report, the day book and the journal
select save_entry(null,'10-2',1,:'td'::date,'{"lines":[{"head":"transport","amount":"200"}]}'::jsonb,'[]') ->> 'id' as v2 \gset
select submit_entry(:'v2'::uuid) is not null as s2 \gset
select set_rule('report_expense_parity_on', 'true') is null as ep3 \gset
select tt.chk('T4 as_today: a SUBMITTED voucher counts in the P&L (1000) and the expense report (1000) but not in the journal (800): the totals differ today',
  tt.exp(:'d1'::date) = 1000 and tt.rep_total(:'d1'::date) = 1000 and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'journal')::numeric = 800 and not (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'agree')::boolean);
select set_rule('expense_count_on', '"approved"') is null as ec1 \gset
select tt.chk('T4 approved: P&L 800 and expense report 800 (day book and journal follow once the hook is applied)', tt.exp(:'d1'::date) = 800 and tt.rep_total(:'d1'::date) = 800);
select _w1d_hooks_apply() as hk \gset
select tt.chk('T4 the integrator hook patched the shared day book and journal (and a second call patches nothing)', :'hk'::jsonb = '{"acct_docs_patched": true, "daybook_lines_patched": true}'::jsonb and _w1d_hooks_apply() = '{"acct_docs_patched": false, "daybook_lines_patched": false}'::jsonb
  and position('bos93' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0 and position('bos50' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0 and position('bos87' in pg_get_functiondef('public._acct_docs(date)'::regprocedure)) > 0
  and position('bos93' in pg_get_functiondef('public._daybook_lines(int[],int[],date,date)'::regprocedure)) > 0);
select tt.chk('T4 approved everywhere: day book 800, P&L 800, expense report 800, journal 800 -> agree', (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'agree')::boolean
  and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'daybook')::numeric = 800);
select set_rule('expense_count_on', '"submitted"') is null as ec2 \gset
select acct_post_pending(false) ->> 'posted' as pp3 \gset
select tt.chk('T4 submitted everywhere: the journal posts the submitted voucher: day book 1000, P&L 1000, expense report 1000, journal 1000 -> agree',
  (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'journal')::numeric = 1000 and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'agree')::boolean and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'daybook')::numeric = 1000
  and tt.unbalanced() = 0);
select set_rule('expense_count_on', '"approved"') is null as ec3 \gset
select acct_post_pending(false) ->> 'posted' as pp4 \gset
select tt.chk('T4 back to approved: the posting of the submitted voucher is reversed, the journal is 800 again and balanced',
  (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'journal')::numeric = 800 and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'agree')::boolean and tt.unbalanced() = 0);
select set_rule('expense_count_on', '"as_today"') is null as ec4 \gset
select acct_post_pending(false) ->> 'posted' as pp5 \gset
select tt.chk('T4 as_today again: the shared functions behave as before (P&L 1000 counts the submitted voucher, journal 800)', tt.exp(:'d1'::date) = 1000 and (report_parity(:'d1'::date, :'td'::date, null) -> 'expenses' ->> 'journal')::numeric = 800);

\echo == T5 dated brand map
select set_rule('expense_count_on', '"as_today"') is null as ec5 \gset
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, discount, total, pay_mode, status, created_by) values
  (1, 93101, :'pm'::date + 5, now(), '[]', 1000, 0, 1000, 'cash', 'done', :'o');
select tt.chk('T5 before any change: place 1 is islamiya; its revenue 1000 (old month) + 400 (today) = 1400', tt.brand('islamiya') = 1400);
select brand_code as old_code from report_brand_map where location_id = 1 \gset
select tt.as(:'o');
select brand_map_set(1, 'test_brand_new', 'test_bn', 'test_en') ->> 'backdated' as bd1 \gset
select tt.chk('T5 the map changed: place 1 -> test_brand_new; history keeps the old row closed yesterday and the new one open from today',
  (select brand_code from report_brand_map where location_id = 1) = 'test_brand_new' and :'bd1' = 'false'
  and (select count(*) from report_brand_map_hist where location_id = 1 and active) = 2
  and (select valid_to from report_brand_map_hist where location_id = 1 and brand_code = :'old_code' and active) = :'td'::date - 1
  and (select valid_from from report_brand_map_hist where location_id = 1 and brand_code = 'test_brand_new') = :'td'::date and (select valid_to from report_brand_map_hist where location_id = 1 and brand_code = 'test_brand_new') is null);
select tt.chk('T5 switch OFF (today): the new brand takes ALL history, old months included: 1400 under test_brand_new', tt.brand('test_brand_new') = 1400);
select set_rule('brand_map_dated_on', 'true') is null as bm1 \gset
select tt.chk('T5 switch ON: the old month stays with the old brand (1000), only today (400) is test_brand_new', tt.brand('test_brand_new') = 400 and tt.brand(:'old_code') >= 1000);
select tt.chk('T5 changing the map did not change the old month: its revenue under the old brand is exactly what it was', (select sum(revenue) from brand_pnl(:'pm'::date, (:'pm'::date + 10), :'old_code')) = 1000);
-- a date in the past needs a reason
select tt.err('T5 a change from a past date needs a reason', format($$select brand_map_set(1, 'test_brand_retro', 'test_bn', 'test_en', %L::date, null)$$, (:'pm'::date + 3)::text), 'reason_required');
select tt.err('T5 ... a short reason is refused too', format($$select brand_map_set(1, 'test_brand_retro', 'test_bn', 'test_en', %L::date, 'abc')$$, (:'pm'::date + 3)::text), 'reason_required');
select tt.err('T5 a future date is refused', format($$select brand_map_set(1, 'test_brand_retro', 'test_bn', 'test_en', %L::date, 'a long enough reason')$$, (:'td'::date + 2)::text), 'future_date_not_allowed');
select tt.err('T5 an unknown place is refused', $$select brand_map_set(999, 'x', 'x', 'x')$$, 'location_not_found');
select tt.err('T5 a blank brand is refused', $$select brand_map_set(1, ' ', 'x', 'x')$$, 'bad_brand');
select brand_map_set(1, 'test_brand_retro', 'test_bn', 'test_en', (:'pm'::date + 3), 'the brand was wrong from the third of that month') ->> 'backdated' as bd2 \gset
select tt.chk('T5 with a reason the past change is made: the sale of day 5 of that month moves to test_brand_retro, the one before day 3 would not', :'bd2' = 'true' and tt.brand('test_brand_retro') = 1400);
select tt.chk('T5 it is in audit_log and the Exceptions list', exists (select 1 from exceptions where flag_code = 'brand_map_backdated' and level = 'yellow')
  and exists (select 1 from audit_log where table_name = 'report_brand_map_hist' and action = 'insert' and detail -> 'new' ->> 'reason' = 'the brand was wrong from the third of that month'));
select tt.chk('T5 nothing was deleted: the superseded rows are kept, inactive', (select count(*) from report_brand_map_hist where location_id = 1) = 3 and exists (select 1 from report_brand_map_hist where location_id = 1 and not active));
select tt.chk('T5 history list shows the rows', jsonb_array_length(brand_map_hist_list(1)) = (select count(*) from report_brand_map_hist where location_id = 1));
update report_brand_map set brand_en = 'TEST EDIT' where location_id = 2;
select tt.chk('T5 a direct edit of the map (SQL) is recorded in the history from today', exists (select 1 from report_brand_map_hist where location_id = 2 and brand_en = 'TEST EDIT' and valid_from = :'td'::date and active)
  and (select valid_to from report_brand_map_hist where location_id = 2 and brand_en = 'ISLAMIYA MISTY GHAR' and active) = :'td'::date - 1);
set role authenticated; select tt.as(:'st');
select tt.err('T5 a salesperson cannot change the map', $$select brand_map_set(1, 'x', 'x', 'x')$$, 'not allowed');
select tt.err('T5 a salesperson cannot read the parity report', format($$select report_parity(%L, %L, null)$$, :'d1', :'td'), 'not allowed');
select tt.as(:'o');
select tt.err('T5 report parity: bad range', format($$select report_parity(%L, %L, null)$$, :'td', :'d1'), 'bad_range');
reset role;

\echo == T6 the books
select tt.chk('T6 every journal entry balances', tt.unbalanced() = 0);
select tt.chk('T6 phase93 wrote no journal entry of its own', not exists (select 1 from journal_entries where source_type like 'brand%' or source_type like 'parity%'));

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
