-- FRESH DB ONLY. Phase 440 tests: report honesty part 1 (package RPT-C1, block R1).
--   a database built through phase99, then  psql -f supabase/phase440.sql   (this file pastes phase440 once more for the paste-twice check)
--   psql -h /tmp -p <port> -U postgres -d db440 -qAt -f supabase/phase440_test.sql | grep -E 'FAIL|RESULT'
-- The data comes from tests/sql/c1_fixture.sql (hand-computed numbers in its header). Test data only (test_* names).
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
create or replace function tt.row1(p_key text, p_flt jsonb default '{"preset":"this_month"}') returns jsonb language sql stable as $$
  select r from jsonb_array_elements(public.report_run2(p_key, p_flt) -> 'rows') r where (r ->> 'location_id')::int = 1 limit 1 $$;
create or replace function tt.note(p_notes jsonb, p_code text) returns jsonb language sql immutable as $$
  select n from jsonb_array_elements(p_notes) n where n ->> 'code' = p_code limit 1 $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select (now() at time zone 'Asia/Dhaka')::date as td \gset
select date_trunc('month', :'td'::date)::date as m1 \gset

\echo == T0 shape, safe default, patches in place, internals closed, pasting twice changes nothing
select tt.chk('T0 phase440 present; the new setting exists, is a switch and is OFF', to_regprocedure('public._c1_p440_present()') is not null
  and exists (select 1 from rules where key = 'report_profit_blank_on' and kind = 'switch' and default_value = 'false'::jsonb) and not rule_on('report_profit_blank_on'));
select tt.chk('T0 the setting has a label and a hint in the three modes', not exists (select 1 from rules where key = 'report_profit_blank_on' and (label_bn is null or label_mix is null or label_en is null or hint_bn is null or hint_mix is null or hint_en is null)));
select tt.chk('T0 the patches are in place (marker bos440) in report_run3, L1 and L3',
  (select count(*) from (values ('public.report_run3(text,jsonb,text,text,int)'),('public._r3q_l1_pnl(date,date,int[],jsonb)'),('public._r3q_l3_shop_pnl(date,date,int[],jsonb)')) v(f) where position('bos440' in pg_get_functiondef(v.f::regprocedure)) > 0) = 3);
select tt.chk('T0 the earlier tags are still there (bos72 bos78 in L1, bos93 in nothing lost)', position('bos72' in pg_get_functiondef('public._r3q_l1_pnl(date,date,int[],jsonb)'::regprocedure)) > 0 and position('bos78' in pg_get_functiondef('public._r3q_l1_pnl(date,date,int[],jsonb)'::regprocedure)) > 0);
select tt.chk('T0 internals closed, report_notes open to signed-in users only', not has_function_privilege('authenticated','public._c1_patch(regprocedure,text,text[])','execute') and not has_function_privilege('authenticated','public._c1_n_mgmt_view(text,date,date,int[],jsonb,text[])','execute')
  and not has_function_privilege('authenticated','public._c1_report_ok(text)','execute') and has_function_privilege('authenticated','public.report_notes(text,jsonb,text[])','execute') and not has_function_privilege('anon','public.report_notes(text,jsonb,text[])','execute')
  and not has_table_privilege('authenticated','public.report_notice_topics','select') and not has_table_privilege('anon','public.report_notice_topics','select'));
select tt.chk('T0 the two P&L reports say "management view"', (select bool_and(name_en like '%(management view)%' and name_bn like '%ম্যানেজমেন্ট ভিউ%' and name_mix like '%(management view)%') from report_defs3 where key in ('l1_pnl','l3_shop_pnl')));
select md5(pg_get_functiondef('public.report_run3(text,jsonb,text,text,int)'::regprocedure) || pg_get_functiondef('public._r3q_l1_pnl(date,date,int[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,int[],jsonb)'::regprocedure)) as h_before \gset
select count(*) as n_topics_before from report_notice_topics \gset
select name_en as l1_name_before from report_defs3 where key = 'l1_pnl' \gset
\ir phase440.sql
select tt.chk('T0 pasting phase440 again changes nothing (function bodies identical, same topics, same name)',
  md5(pg_get_functiondef('public.report_run3(text,jsonb,text,text,int)'::regprocedure) || pg_get_functiondef('public._r3q_l1_pnl(date,date,int[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_l3_shop_pnl(date,date,int[],jsonb)'::regprocedure)) = :'h_before'
  and (select count(*) from report_notice_topics) = :n_topics_before and (select name_en from report_defs3 where key = 'l1_pnl') = :'l1_name_before');
select tt.err('T0 a patch site that does not exist stops the call', $$select public._c1_patch('public._r3q_l5_breakeven(date,date,int[],jsonb)'::regprocedure, 'bos440', array['this text is not there','x'])$$, 'patch site not found');
select tt.err('T0 a marker of another shape is refused', $$select public._c1_patch('public._r3q_l5_breakeven(date,date,int[],jsonb)'::regprocedure, 'bos99', array['a','b'])$$, 'bad_marker');
select count(*) as n_je_before from journal_entries \gset

\echo == T1 totals: a column with no value at all is "not captured" (null), never 0
select tt.as(:'o');
select report_run2('l5_breakeven', '{"preset":"this_month"}') as l5 \gset
select tt.chk('T1 break-even: no fixed cost set -> row fixed and be_sales are null, and so are the TOTALS (they were 0.0000 before)',
  (tt.row1('l5_breakeven') -> 'fixed') = 'null'::jsonb and (:'l5'::jsonb #> '{totals,fixed}') = 'null'::jsonb and (:'l5'::jsonb #> '{totals,be_sales}') = 'null'::jsonb);
select tt.chk('T1 a column that has values still adds up: net sales total is a number and equals the row', (:'l5'::jsonb #>> '{totals,net_sales}')::numeric = (tt.row1('l5_breakeven') ->> 'net_sales')::numeric and (:'l5'::jsonb #>> '{totals,net_sales}')::numeric > 0);
select tt.chk('T1 L1: no salary captured -> salary total is null; expenses total is a number', (report_run2('l1_pnl', '{"preset":"this_month"}') #> '{totals,salary}') = 'null'::jsonb and (report_run2('l1_pnl', '{"preset":"this_month"}') #>> '{totals,expenses}')::numeric = (select sum(o_exp) from _p27_pl(:'m1'::date, :'td'::date, array[1])));
insert into location_settings (location_id, key, value) values (1, 'fixed_cost_month', '3000') on conflict (location_id, key) do update set value = '3000';
select tt.chk('T1 fixed cost set -> break-even total appears (a number), fixed total is a number', (report_run2('l5_breakeven', '{"preset":"this_month"}') #>> '{totals,fixed}') is not null and (report_run2('l5_breakeven', '{"preset":"this_month"}') #>> '{totals,be_sales}')::numeric > 0);
delete from location_settings where location_id = 1 and key = 'fixed_cost_month';
select tt.chk('T1 an empty period still answers; totals of nothing are null, not 0', (report_run2('t4_staff_cost_ratio', '{"from":"2020-01-01","to":"2020-01-02"}') #> '{totals,net_sales}') = 'null'::jsonb and (report_run2('t4_staff_cost_ratio', '{"from":"2020-01-01","to":"2020-01-02"}') ->> 'data_needed')::boolean);

\echo == T2 profit: default keeps today's number, the setting shows "not captured"
select tt.chk('T2 default: L1 profit is today''s number = net - cogs - expenses (salary and fixed left out): ' , (tt.row1('l1_pnl') ->> 'profit')::numeric
  = (select round(sum(o_net) - sum(o_cogs) - coalesce(sum(o_exp), 0), 2) from _p27_pl(:'m1'::date, :'td'::date, array[1])) and (tt.row1('l1_pnl') ->> 'profit') is not null);
select tt.chk('T2 default: profit_complete is false because salary and fixed cost were not captured; gaps names them', (tt.row1('l1_pnl') ->> 'profit_complete')::boolean = false and (tt.row1('l1_pnl') ->> 'gaps') like '%salary%' and (tt.row1('l1_pnl') ->> 'gaps') like '%fixed%');
select tt.chk('T2 default: L3 profit and profit_pct are numbers', (tt.row1('l3_shop_pnl') ->> 'profit') is not null and (tt.row1('l3_shop_pnl') ->> 'profit_pct') is not null);
select tt.as(:'o'); select set_rule('report_profit_blank_on', 'true') is null as pb1 \gset
select tt.chk('T2 setting ON: L1 profit is null (not captured) and says why; the other figures are unchanged', (tt.row1('l1_pnl') -> 'profit') = 'null'::jsonb and (tt.row1('l1_pnl') ->> 'net_sales')::numeric > 0 and (tt.row1('l1_pnl') ->> 'gaps') <> '');
select tt.chk('T2 setting ON: L3 profit and profit_pct are null', (tt.row1('l3_shop_pnl') -> 'profit') = 'null'::jsonb and (tt.row1('l3_shop_pnl') -> 'profit_pct') = 'null'::jsonb);
select tt.chk('T2 setting ON: the profit TOTAL of a report with only incomplete rows is null too', (report_run2('l1_pnl', '{"preset":"this_month"}') #> '{totals,profit}') = 'null'::jsonb);
-- make the row complete: a salary sheet (02-2), a fixed cost; costs are known
select save_entry(null,'02-2',1,tt.today(),'{"pay":[{"name":"test_emp_c1","due":"1000"}]}'::jsonb,'[]') ->> 'id' as t2_sal \gset
select submit_entry(:'t2_sal'::uuid) is not null as t2_sub \gset
insert into location_settings (location_id, key, value) values (1, 'fixed_cost_month', '3000') on conflict (location_id, key) do update set value = '3000';
select tt.chk('T2 setting ON, every part captured: profit is a number again and profit_complete is true',
  (tt.row1('l1_pnl') ->> 'profit_complete')::boolean and (tt.row1('l1_pnl') ->> 'profit') is not null
  and (tt.row1('l1_pnl') ->> 'profit')::numeric = (select round(sum(o_net) - sum(o_cogs) - coalesce(sum(o_exp), 0) - coalesce(sum(o_sal), 0) - coalesce(sum(o_fixed), 0), 2) from _p27_pl(:'m1'::date, :'td'::date, array[1])));
select set_rule('report_profit_blank_on', 'false') is null as pb0 \gset
delete from location_settings where location_id = 1 and key = 'fixed_cost_month';
select tt.chk('T2 setting OFF again: the incomplete L1 profit is a number again', (tt.row1('l1_pnl') ->> 'profit') is not null);

\echo == T3 notices (report_notes)
select tt.as(:'o');
select report_notes('l1_pnl', '{"preset":"this_month"}') as n1 \gset
select tt.chk('T3 L1: the management view notice links to Profit check and carries three basis lines (salary, expenses, returns)',
  tt.note(:'n1'::jsonb, 'management_view') #>> '{link,route}' = 'profitcheck' and jsonb_array_length(tt.note(:'n1'::jsonb, 'management_view') -> 'basis') = 3
  and (tt.note(:'n1'::jsonb, 'management_view') #>> '{basis,0,code}') = 'salary' and (tt.note(:'n1'::jsonb, 'management_view') #>> '{basis,2,code}') = 'returns');
select tt.chk('T3 L1: every notice has an English and a Bangla text', (select bool_and(n ->> 'text_en' <> '' and n ->> 'text_bn' <> '') from jsonb_array_elements(:'n1'::jsonb) n));
select tt.chk('T3 L1: the incomplete-rows notice counts what is missing (salary was captured in T2, fixed cost is not)', tt.note(:'n1'::jsonb, 'profit_incomplete') #>> '{data,no_salary}' = '0' and tt.note(:'n1'::jsonb, 'profit_incomplete') #>> '{data,no_fixed}' = '1' and tt.note(:'n1'::jsonb, 'profit_incomplete') ->> 'level' = 'warn');
select tt.chk('T3 L1: salary basis says legacy sheets (default)', (tt.note(:'n1'::jsonb, 'management_view') #>> '{basis,0,text_en}') like '%salary sheets (02-2)%payroll run paid in the app is not used%');
select set_rule('report_salary_source', '"app_first"') is null as ss1 \gset
select tt.chk('T3 salary source app_first changes the salary basis line', (tt.note(report_notes('l1_pnl', '{"preset":"this_month"}'), 'management_view') #>> '{basis,0,text_en}') like '%payroll runs that are counted%');
select set_rule('report_salary_source', '"legacy"') is null as ss0 \gset
select set_rule('reports_net_of_returns', 'false') is null as nr1 \gset
select tt.chk('T3 returns setting off: the returns basis line says returns are NOT taken off', (tt.note(report_notes('l3_shop_pnl', '{"preset":"this_month"}'), 'management_view') #>> '{basis,2,text_en}') like '%NOT taken off%');
select set_rule('reports_net_of_returns', 'true') is null as nr0 \gset
select tt.chk('T3 L5: break-even says fixed cost is missing for 1 of the places', tt.note(report_notes('l5_breakeven', '{"preset":"this_month"}'), 'fixed_cost_missing') #>> '{data,places}' = '1');
select tt.chk('T3 T4: salary is captured at place 1 now, so no salary notice for it', tt.note(report_notes('t4_staff_cost_ratio', '{"preset":"this_month","locations":[1]}'), 'salary_missing') is null);
-- sales reports: the returns line
select report_notes('sales_summary', '{"preset":"this_month"}') as ns \gset
select tt.chk('T3 sales summary: returns line = 1 return of 100 in this period, before-returns statement', tt.note(:'ns'::jsonb, 'returns_line') #>> '{data,count}' = '1' and (tt.note(:'ns'::jsonb, 'returns_line') #>> '{data,amount}')::numeric = 100
  and (tt.note(:'ns'::jsonb, 'returns_line') ->> 'text_en') like '%before returns%' and tt.note(:'ns'::jsonb, 'returns_line') #>> '{link,route}' = 'salereturn');
select tt.chk('T3 sales summary: when the report has its own returns column the line says so and makes no before-returns claim',
  (tt.note(report_notes('sales_summary', '{"preset":"this_month"}', array['returns','net']), 'returns_line') #>> '{data,in_report}') = 'true' and (tt.note(report_notes('sales_summary', '{"preset":"this_month"}', array['returns','net']), 'returns_line') ->> 'text_en') not like '%before returns%');
select tt.chk('T3 sales summary: an item filter is named as not narrowing the returns', (tt.note(report_notes('sales_summary', jsonb_build_object('preset','this_month','items',jsonb_build_array(:'i_fg'))), 'returns_line') ->> 'text_en') like '%not narrowed%');
select tt.chk('T3 sales summary: a period with no return says so (a real zero)', (tt.note(report_notes('sales_summary', '{"from":"2020-01-01","to":"2020-01-31"}'), 'returns_line') #>> '{data,count}') = '0');
select tt.chk('T3 sales reports without a topic (voids, a profit report of other groups) answer an empty list', report_notes('voids', '{"preset":"this_month"}') = '[]'::jsonb);
-- expense reports
select tt.chk('T3 expense report: quick expenses are NOT counted (switch off) and the Expense register is linked', (tt.note(report_notes('expense_by_head', '{"preset":"this_month"}'), 'expense_basis') ->> 'text_en') like '%NOT counted%'
  and tt.note(report_notes('expense_by_head', '{"preset":"this_month"}'), 'expense_basis') #>> '{link,route}' = 'expenseregister');
select set_rule('report_expense_parity_on', 'true') is null as ep1 \gset
select tt.chk('T3 expense report: switch on -> quick expenses are counted', (tt.note(report_notes('expense_by_head', '{"preset":"this_month"}'), 'expense_basis') ->> 'text_en') like '%counted (setting on)%');
select set_rule('report_expense_parity_on', 'false') is null as ep0 \gset
select tt.err('T3 an unknown report', $$select report_notes('no_such_report')$$, 'unknown_report');
select tt.chk('T3 an unknown preset answers an empty list', report_notes('l1_pnl', '{"preset":"no_such_preset"}') = '[]'::jsonb);

\echo == T4 rights
set role authenticated; select tt.as(:'st');
select tt.err('T4 a salesperson without the profit report right cannot read its notices', $$select report_notes('l1_pnl', '{"preset":"this_month"}')$$, 'not allowed');
select tt.err('T4 nor the notices of a sales report without the sales report right', $$select report_notes('sales_summary', '{"preset":"this_month"}')$$, 'not allowed');
select tt.err('T4 the internal notice builder is closed', $$select public._c1_n_returns_line('sales_summary', current_date, current_date, array[1], '{}'::jsonb, null)$$, 'permission denied');
select tt.err('T4 the patch helper is closed', $$select public._c1_patch('public._r3q_l5_breakeven(date,date,int[],jsonb)'::regprocedure, 'bos440', array['a','b'])$$, 'permission denied');
reset role;
set role anon;
select tt.err('T4 anonymous: no notices', $$select report_notes('l1_pnl')$$, 'permission denied');
reset role;
select tt.as(:'o');
insert into user_grants (user_id, grant_code, location_id) values (:'st', 'report_sales', null) on conflict do nothing;
set role authenticated; select tt.as(:'st');
select tt.chk('T4 with the sales report right the sales notices open (places: his own)', jsonb_array_length(report_notes('sales_summary', '{"preset":"this_month"}')) = 1);
reset role;

\echo == T5 the books
select tt.chk('T5 every journal entry balances', tt.unbalanced() = 0);
select tt.chk('T5 phase440 posted nothing (same number of journal entries as before the checks)', (select count(*) from journal_entries) = :n_je_before);

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
