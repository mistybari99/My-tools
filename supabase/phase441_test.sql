-- FRESH DB ONLY. Phase 441 tests: report honesty part 2 (package RPT-C1, block R1): attendance, compliance, RFM, lapsed, cash short.
--   a database built through phase99, then phase440.sql and phase441.sql  (this file pastes phase441 once more for the paste-twice check)
--   psql -h /tmp -p <port> -U postgres -d db441 -qAt -f supabase/phase441_test.sql | grep -E 'FAIL|RESULT'
-- Data: tests/sql/c1_fixture.sql (hand-computed numbers in its header) plus the records made below. Test data only (test_* names).
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
create or replace function tt.note(p_notes jsonb, p_code text) returns jsonb language sql immutable as $$
  select n from jsonb_array_elements(p_notes) n where n ->> 'code' = p_code limit 1 $$;
create or replace function tt.rows(p_key text, p_flt jsonb default '{"preset":"this_month"}', p_group text default null) returns jsonb language sql stable as $$
  select public.report_run2(p_key, p_flt, p_group) -> 'rows' $$;
grant usage on schema tt to authenticated, anon; grant execute on all functions in schema tt to authenticated, anon; grant select, insert on tt.res to authenticated, anon;
select (now() at time zone 'Asia/Dhaka')::date as td \gset
select date_trunc('month', :'td'::date)::date as m1 \gset

\echo == T0 shape, safe defaults, patches in place, internals closed, pasting twice changes nothing
select tt.chk('T0 phase441 present; the seven settings exist and are blank / OFF', to_regprocedure('public._c1_p441_present()') is not null
  and (select count(*) from rules where key in ('report_rfm_min_orders','report_rfm_recent_days','report_rfm_atrisk_days','report_lapsed_days','report_compliance_from','report_compliance_closed_days','report_cash_short_by_case_on')) = 7
  and (select bool_and(default_value is null or default_value = 'false'::jsonb) from rules where key like 'report\_rfm%' or key like 'report\_lapsed%' or key like 'report\_compliance%' or key = 'report_cash_short_by_case_on')
  and not rule_on('report_cash_short_by_case_on') and rule_txt('report_compliance_from') is null);
select tt.chk('T0 every setting has a label and a hint in the three modes', not exists (select 1 from rules where (key like 'report\_rfm%' or key like 'report\_lapsed%' or key like 'report\_compliance%' or key = 'report_cash_short_by_case_on')
  and (label_bn is null or label_mix is null or label_en is null or hint_bn is null or hint_mix is null or hint_en is null)));
select tt.chk('T0 the patches are in place (bos441 / bos441a / bos441b)', position('bos441' in pg_get_functiondef('public._r3q_m1_rfm(date,date,int[],jsonb)'::regprocedure)) > 0 and position('bos441' in pg_get_functiondef('public._r3q_d5_lapsed(date,date,int[],jsonb)'::regprocedure)) > 0
  and position('bos441' in pg_get_functiondef('public._r3q_x4_compliance(date,date,int[],jsonb)'::regprocedure)) > 0 and position('bos441a' in pg_get_functiondef('public.report_run2_core(text,jsonb,text,text,int)'::regprocedure)) > 0
  and position('bos441b' in pg_get_functiondef('public.report_run2_core(text,jsonb,text,text,int)'::regprocedure)) > 0);
select tt.chk('T0 the earlier tags of report_run2_core are still there (bos93)', position('bos93' in pg_get_functiondef('public.report_run2_core(text,jsonb,text,text,int)'::regprocedure)) > 0);
select tt.chk('T0 internals closed', not has_function_privilege('authenticated','public._c1_att_rows(date,date,int[])','execute') and not has_function_privilege('authenticated','public._c1_rfm(text)','execute')
  and not has_function_privilege('authenticated','public._c1_compliance_from()','execute') and not has_function_privilege('authenticated','public._r3q_x4_compliance(date,date,int[],jsonb)','execute') and not has_function_privilege('anon','public._c1_n_att_sources(text,date,date,int[],jsonb,text[])','execute'));
select tt.chk('T0 the new compliance column and total are registered', exists (select 1 from report_defs3 where key = 'x4_compliance' and cols::text like '%"closed_days"%' and 'closed_days' = any (tot)));
select md5(pg_get_functiondef('public._r3q_m1_rfm(date,date,int[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_d5_lapsed(date,date,int[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_x4_compliance(date,date,int[],jsonb)'::regprocedure)
  || pg_get_functiondef('public.report_run2_core(text,jsonb,text,text,int)'::regprocedure)) as h_before \gset
select count(*) as n_rules_before from rules \gset
select count(*) as n_topics_before from report_notice_topics \gset
select cols::text as x4_cols_before from report_defs3 where key = 'x4_compliance' \gset
\ir phase441.sql
select tt.chk('T0 pasting phase441 again changes nothing (bodies identical, same rules, same topics, same columns)',
  md5(pg_get_functiondef('public._r3q_m1_rfm(date,date,int[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_d5_lapsed(date,date,int[],jsonb)'::regprocedure) || pg_get_functiondef('public._r3q_x4_compliance(date,date,int[],jsonb)'::regprocedure)
  || pg_get_functiondef('public.report_run2_core(text,jsonb,text,text,int)'::regprocedure)) = :'h_before' and (select count(*) from rules) = :n_rules_before and (select count(*) from report_notice_topics) = :n_topics_before
  and (select cols::text from report_defs3 where key = 'x4_compliance') = :'x4_cols_before');
select count(*) as n_je_before from journal_entries \gset

\echo == T1 attendance summary: both sources, in separate rows
select tt.as(:'o');
select tt.chk('T1 total view: two rows, the app records and the paper register, never added', jsonb_array_length(tt.rows('attendance_summary', '{"preset":"this_month"}', 'none')) = 2
  and exists (select 1 from jsonb_array_elements(tt.rows('attendance_summary', '{"preset":"this_month"}', 'none')) r where r ->> 'source' = 'App attendance' and (r ->> 'records')::int = 3 and r -> 'sheets' = 'null'::jsonb)
  and exists (select 1 from jsonb_array_elements(tt.rows('attendance_summary', '{"preset":"this_month"}', 'none')) r where r ->> 'source' = 'Paper register (02-1)' and (r ->> 'sheets')::int = 1 and r -> 'records' = 'null'::jsonb));
select tt.chk('T1 app row: present 2 (present + late), late 1, absent 1, overtime 1.0 hour', exists (select 1 from jsonb_array_elements(tt.rows('attendance_summary', '{"preset":"this_month"}', 'none')) r
  where r ->> 'source' = 'App attendance' and (r ->> 'present')::numeric = 2 and (r ->> 'late')::numeric = 1 and (r ->> 'absent')::numeric = 1 and (r ->> 'ot_hours')::numeric = 1));
select tt.chk('T1 paper row: present 20, late 2, absent 1, overtime 3 (as before this phase)', exists (select 1 from jsonb_array_elements(tt.rows('attendance_summary', '{"preset":"this_month"}', 'none')) r
  where r ->> 'source' = 'Paper register (02-1)' and (r ->> 'present')::numeric = 20 and (r ->> 'late')::numeric = 2 and (r ->> 'absent')::numeric = 1 and (r ->> 'ot_hours')::numeric = 3));
select tt.chk('T1 by person: the app person and the paper person are two rows', jsonb_array_length(tt.rows('attendance_summary')) = 2 and exists (select 1 from jsonb_array_elements(tt.rows('attendance_summary')) r where r ->> 'person' = 'test_emp_c1' and r ->> 'source' = 'App attendance'));
select save_entry(null,'02-1',1,tt.today(),'{"staff":[{"name":"test_emp_c1","present":"5","late":"0","absent":"0"}]}'::jsonb,'[]') ->> 'id' as t1_e \gset
select submit_entry(:'t1_e'::uuid) is not null as t1_s \gset
select tt.chk('T1 the same name on both sources is NOT merged: two rows for test_emp_c1', (select count(*) from jsonb_array_elements(tt.rows('attendance_summary')) r where r ->> 'person' = 'test_emp_c1') = 2);
select tt.chk('T1 by place: the app row follows the place of the record', exists (select 1 from jsonb_array_elements(tt.rows('attendance_summary', '{"preset":"this_month"}', 'location')) r where (r ->> 'location_id')::int = 1 and r ->> 'source' = 'App attendance'));
select tt.chk('T1 the totals row adds the sources (and the notice says not to)', (report_run2('attendance_summary', '{"preset":"this_month"}') #>> '{totals,records}')::int = 3);
select report_notes('attendance_summary', '{"preset":"this_month"}') as n_att \gset
select tt.chk('T1 notice: 3 app records and 2 paper registers, a person on both appears twice', tt.note(:'n_att'::jsonb, 'attendance_sources') #>> '{data,app_records}' = '3' and tt.note(:'n_att'::jsonb, 'attendance_sources') #>> '{data,paper_sheets}' = '2'
  and (tt.note(:'n_att'::jsonb, 'attendance_sources') ->> 'text_en') like '%appears twice%' and tt.note(:'n_att'::jsonb, 'no_app_data') is null);
select tt.chk('T1 notice: a period with no app record says "data not captured in the app"', tt.note(report_notes('attendance_summary', '{"from":"2020-01-01","to":"2020-01-31"}'), 'no_app_data') is not null);
select set_rule('attendance_on', 'false') is null as t1_off \gset
select tt.chk('T1 notice: attendance switched off -> "not switched on - no data captured"', (tt.note(report_notes('attendance_summary', '{"from":"2020-01-01","to":"2020-01-31"}'), 'module_off') ->> 'text_en') like '%not switched on - no data captured%');
select set_rule('attendance_on', 'true') is null as t1_on \gset
select tt.chk('T1 the report still opens when attendance is off (reads are not gated by the capture switch)', jsonb_array_length(tt.rows('attendance_summary', '{"preset":"this_month"}', 'none')) = 2);

\echo == T2 compliance: rollout start date and closed days
select tt.as(:'o');
select (:'td'::date - :'m1'::date + 1) as t2_days \gset
select tt.chk('T2 blank rule = today: every calendar day of the period is a required day, no closed day left out, start_date null', (select bool_and((r ->> 'days')::int = :t2_days and (r ->> 'closed_days')::int = 0 and r -> 'start_date' = 'null'::jsonb) from jsonb_array_elements(tt.rows('x4_compliance')) r));
select tt.chk('T2 blank rule: missing = days - submitted days, as before', (select bool_and((r ->> 'missing_days')::int = greatest((r ->> 'days')::int - (r ->> 'submitted_days')::int, 0)) from jsonb_array_elements(tt.rows('x4_compliance')) r));
select tt.chk('T2 the notice warns that no start date is set and the missing days are overstated', tt.note(report_notes('x4_compliance', '{"preset":"this_month"}'), 'compliance_basis') ->> 'level' = 'warn'
  and (tt.note(report_notes('x4_compliance', '{"preset":"this_month"}'), 'compliance_basis') ->> 'text_en') like '%overstated%');
select set_rule('report_compliance_from', to_jsonb((:'td'::date - 9)::text)) is null as t2_set \gset
select tt.chk('T2 start date = 9 days ago: place 1 form 14-1 has 10 days, 1 closed (the holiday 3 days ago), 9 required, the 2 sheets of today are 1 submitted day, 8 missing',
  exists (select 1 from jsonb_array_elements(tt.rows('x4_compliance', '{"preset":"this_month"}')) r where (r ->> 'location_id')::int = 1 and r ->> 'form' = '14-1'
    and (r ->> 'days')::int = 9 and (r ->> 'closed_days')::int = 1 and (r ->> 'submitted_days')::int = 1 and (r ->> 'missing_days')::int = 8 and (r ->> 'compliance_pct')::numeric = round(100.0 / 9, 2) and r ->> 'start_date' = (:'td'::date - 9)::text));
select tt.chk('T2 a place with no sheet at all: all required days are missing', exists (select 1 from jsonb_array_elements(tt.rows('x4_compliance', '{"preset":"this_month"}')) r where r ->> 'form' = '10-1' and (r ->> 'submitted_days')::int = 0 and (r ->> 'missing_days')::int = (r ->> 'days')::int and (r ->> 'days')::int = 9));
select tt.chk('T2 the notice now names the start date and the holiday', tt.note(report_notes('x4_compliance', '{"preset":"this_month"}'), 'compliance_basis') ->> 'level' = 'info' and (tt.note(report_notes('x4_compliance', '{"preset":"this_month"}'), 'compliance_basis') ->> 'text_en') like ('%' || (:'td'::date - 9)::text || '%')
  and (tt.note(report_notes('x4_compliance', '{"preset":"this_month"}'), 'compliance_basis') #>> '{data,holiday_days}') = '1');
select set_rule('report_compliance_closed_days', '"fri,sat"') is null as t2_wk \gset
select (select count(*) from generate_series(:'td'::date - 9, :'td'::date, interval '1 day') g where lower(to_char(g, 'dy')) in ('fri','sat') and g::date <> :'td'::date - 3) as t2_wkdays \gset
select tt.chk('T2 weekly closed days (fri,sat) are left out too (the holiday is not counted twice)', exists (select 1 from jsonb_array_elements(tt.rows('x4_compliance', '{"preset":"this_month"}')) r where (r ->> 'location_id')::int = 1 and r ->> 'form' = '14-1'
    and (r ->> 'closed_days')::int = 1 + :t2_wkdays and (r ->> 'days')::int = 10 - 1 - :t2_wkdays or false));
select set_rule('report_compliance_closed_days', null) is null as t2_wk0 \gset
select set_rule('report_compliance_from', to_jsonb((:'td'::date + 5)::text)) is null as t2_fut \gset
select tt.chk('T2 a start date after the period: no day is required yet (days 0, compliance null)', (select bool_and((r ->> 'days')::int = 0 and r -> 'compliance_pct' = 'null'::jsonb) from jsonb_array_elements(tt.rows('x4_compliance', '{"preset":"this_month"}')) r));
select set_rule('report_compliance_from', '"not a date"') is null as t2_bad \gset
select tt.chk('T2 a text that is not a date is ignored (as blank) and the notice says so', (select bool_and((r ->> 'days')::int = :t2_days) from jsonb_array_elements(tt.rows('x4_compliance', '{"preset":"this_month"}')) r)
  and (tt.note(report_notes('x4_compliance', '{"preset":"this_month"}'), 'compliance_basis') ->> 'text_en') like '%not a valid date%');
select set_rule('report_compliance_from', null) is null as t2_off \gset
select tt.chk('T2 blank again: back to today''s figures', (select bool_and((r ->> 'days')::int = :t2_days) from jsonb_array_elements(tt.rows('x4_compliance', '{"preset":"this_month"}')) r));

\echo == T3 RFM and lapsed: the numbers are settings; blank = the numbers that were in the code
select tt.chk('T3 default: 3 orders today -> Champion (3 orders, within 30 days)', exists (select 1 from jsonb_array_elements(tt.rows('m1_rfm')) r where r ->> 'name' = 'test_cust_champion' and r ->> 'segment' = 'Champion' and (r ->> 'frequency')::int = 3));
select report_notes('m1_rfm', '{"preset":"this_month"}') as n_rfm \gset
select tt.chk('T3 default notice: all three numbers are built-in, NOT set by the owner (warn)', tt.note(:'n_rfm'::jsonb, 'rfm_cutoffs') ->> 'level' = 'warn' and jsonb_array_length(tt.note(:'n_rfm'::jsonb, 'rfm_cutoffs') #> '{data,built_in}') = 3
  and (tt.note(:'n_rfm'::jsonb, 'rfm_cutoffs') ->> 'text_en') like '%NOT SET BY THE OWNER%' and (tt.note(:'n_rfm'::jsonb, 'rfm_cutoffs') ->> 'text_en') like '%at least 3 orders%');
select set_rule('report_rfm_min_orders', '4') is null as t3_a \gset
select tt.chk('T3 min orders = 4 -> the same customer is Regular now', exists (select 1 from jsonb_array_elements(tt.rows('m1_rfm')) r where r ->> 'name' = 'test_cust_champion' and r ->> 'segment' = 'Regular'));
select tt.chk('T3 the notice names 4 and drops that number from the built-in list', jsonb_array_length(tt.note(report_notes('m1_rfm', '{"preset":"this_month"}'), 'rfm_cutoffs') #> '{data,built_in}') = 2 and (tt.note(report_notes('m1_rfm', '{"preset":"this_month"}'), 'rfm_cutoffs') ->> 'text_en') like '%at least 4 orders%');
select set_rule('report_rfm_min_orders', '3') is null as t3_b \gset
select set_rule('report_rfm_recent_days', '1') is null as t3_c \gset
select set_rule('report_rfm_atrisk_days', '1') is null as t3_d \gset
select tt.chk('T3 all three set by the owner: the notice is info and lists nothing built-in; the customer is still Champion (bought today)', tt.note(report_notes('m1_rfm', '{"preset":"this_month"}'), 'rfm_cutoffs') ->> 'level' = 'info'
  and jsonb_array_length(tt.note(report_notes('m1_rfm', '{"preset":"this_month"}'), 'rfm_cutoffs') #> '{data,built_in}') = 0 and exists (select 1 from jsonb_array_elements(tt.rows('m1_rfm')) r where r ->> 'name' = 'test_cust_champion' and r ->> 'segment' = 'Champion'));
select set_rule('report_rfm_min_orders', null) is null as t3_e \gset
select set_rule('report_rfm_recent_days', null) is null as t3_f \gset
select set_rule('report_rfm_atrisk_days', null) is null as t3_g \gset
select tt.chk('T3 lapsed, default 180 days: the customer who bought 200 days ago is not listed', not exists (select 1 from jsonb_array_elements(tt.rows('d5_lapsed')) r where r ->> 'name' = 'test_cust_old'));
select tt.chk('T3 lapsed notice default: 180 is built-in, not set by the owner', tt.note(report_notes('d5_lapsed', '{"preset":"this_month"}'), 'lapse_days') ->> 'level' = 'warn' and (tt.note(report_notes('d5_lapsed', '{"preset":"this_month"}'), 'lapse_days') #>> '{data,days}') = '180');
select set_rule('report_lapsed_days', '250') is null as t3_h \gset
select tt.chk('T3 lapsed 250 days: now listed as lapsed, days silent about 200 (from the end of the period)', exists (select 1 from jsonb_array_elements(tt.rows('d5_lapsed')) r where r ->> 'name' = 'test_cust_old' and r ->> 'kind' = 'lapsed' and (r ->> 'days_silent')::int between 198 and 230));
select tt.chk('T3 lapsed notice: set by the owner (info)', tt.note(report_notes('d5_lapsed', '{"preset":"this_month"}'), 'lapse_days') ->> 'level' = 'info' and (tt.note(report_notes('d5_lapsed', '{"preset":"this_month"}'), 'lapse_days') #>> '{data,set_by_owner}') = 'true');
select set_rule('report_lapsed_days', null) is null as t3_i \gset
select tt.chk('T3 blank again: the 200-day customer is gone again', not exists (select 1 from jsonb_array_elements(tt.rows('d5_lapsed')) r where r ->> 'name' = 'test_cust_old'));
select tt.err('T3 a cut-off of 0 is refused by the setting', $$select set_rule('report_lapsed_days', '0')$$, 'bad_value');

\echo == T4 cash short / over follows the shortage case
select tt.as(:'o');
insert into entries (form_code,location_id,serial,entry_date,status,created_by,created_staff,flags) values ('14-1',1,92003,tt.today(),'submitted',:'o','t','[{"code":"cash_short_over","amount":-30}]'::jsonb);
select id as t4_e3 from entries where serial = 92003 and form_code = '14-1' \gset
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values (:'t4_e3','14-1',1,tt.today(),'cash_short_over','red',-30,'{}');
select id as t4_case from shortage_cash_cases where entry_id = :'t4_e3' \gset
select tt.chk('T4 the third sheet made an open case', (select status from shortage_cash_cases where id = :'t4_case'::uuid) = 'open');
select tt.chk('T4 default: all three flagged sheets count (the old behaviour): short 50, over 5, net -45, 3 sheets', (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'sheets')::int = 3
  and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'short_amount')::numeric = 50 and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'net')::numeric = -45);
select tt.chk('T4 default: the case columns show 1 open, 2 approved', (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'cases_open')::int = 1 and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'cases_approved')::int = 2);
select cash_short_decide(:'t4_case'::uuid, false, 'the count was wrong, not a shortage') ->> 'status' as t4_dec \gset
select tt.chk('T4 the owner rejected the case', :'t4_dec' = 'rejected');
insert into entries (form_code,location_id,serial,entry_date,status,created_by,created_staff,flags) values ('14-1',1,92004,tt.today(),'submitted',:'o','t','[{"code":"cash_short_over","amount":-10}]'::jsonb);
select id as t4_e4 from entries where serial = 92004 and form_code = '14-1' \gset
insert into exceptions (entry_id,form_code,location_id,entry_date,flag_code,level,amount,text) values (:'t4_e4','14-1',1,tt.today(),'cash_short_over','red',-10,'{}');
select id as t4_case2 from shortage_cash_cases where entry_id = :'t4_e4' \gset
select cash_short_decide(:'t4_case2'::uuid, true, 'approved first, then voided') ->> 'status' as t4_dec2 \gset
select cash_short_void(:'t4_case2'::uuid, 'test void') ->> 'status' as t4_void \gset
select tt.chk('T4 a fourth sheet: its case was approved and then voided', :'t4_void' = 'void' or (select status from shortage_cash_cases where id = :'t4_case2'::uuid) = 'void');
select tt.chk('T4 setting OFF: the rejected and the voided sheets STILL count (4 sheets, short 60) and the columns show them', (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'sheets')::int = 4 and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'short_amount')::numeric = 60
  and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'cases_rejected')::int = 1 and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'cases_void')::int = 1);
select tt.chk('T4 setting OFF: the notice warns that a rejected case is counted', tt.note(report_notes('cash_short_over', '{"preset":"this_month"}'), 'cash_short_basis') ->> 'level' = 'warn' and (tt.note(report_notes('cash_short_over', '{"preset":"this_month"}'), 'cash_short_basis') #>> '{data,rejected}') = '1');
select set_rule('report_cash_short_by_case_on', 'true') is null as t4_on \gset
select tt.chk('T4 setting ON: the rejected and the voided sheets are left out: 2 sheets, short 20, over 5, net -15', (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'sheets')::int = 2 and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'short_amount')::numeric = 20
  and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'net')::numeric = -15 and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'cases_rejected')::int = 0 and (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'cases_void')::int = 0);
select tt.chk('T4 setting ON: the notice states the setting and still counts the rejected case', (tt.note(report_notes('cash_short_over', '{"preset":"this_month"}'), 'cash_short_basis') ->> 'text_en') like '%Setting ON%' and (tt.note(report_notes('cash_short_over', '{"preset":"this_month"}'), 'cash_short_basis') #>> '{data,rejected}') = '1' and (tt.note(report_notes('cash_short_over', '{"preset":"this_month"}'), 'cash_short_basis') #>> '{data,void}') = '1');
select tt.chk('T4 setting ON, by place: place 1 only', (tt.rows('cash_short_over', '{"preset":"this_month"}', 'location') -> 0 ->> 'sheets')::int = 2);
select set_rule('report_cash_short_by_case_on', 'false') is null as t4_off \gset
select tt.chk('T4 setting OFF again: back to the old figures (4 sheets)', (tt.rows('cash_short_over', '{"preset":"this_month"}', 'none') -> 0 ->> 'sheets')::int = 4);

\echo == T5 rights
set role authenticated; select tt.as(:'st');
select tt.err('T5 a salesperson without the staff report right cannot read the attendance notices', $$select report_notes('attendance_summary', '{"preset":"this_month"}')$$, 'not allowed');
select tt.err('T5 nor the report', $$select report_run2('attendance_summary', '{"preset":"this_month"}')$$, 'not allowed');
reset role;
select tt.chk('T5 report_run2_core cannot be called by a browser (as before)', not has_function_privilege('authenticated','public.report_run2_core(text,jsonb,text,text,int)','execute'));

\echo == T6 the books
select tt.chk('T6 every journal entry balances', tt.unbalanced() = 0);
select tt.chk('T6 phase441 posted nothing', (select count(*) from journal_entries) = :n_je_before);

select 'RESULT: ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' as result from tt.res;
select name from tt.res where not ok;
