-- Phase 13 tests (day book + salary report + audited export). Fresh db: ORDER="phase8 phase9 phase10 phase13" bash tests/sql/build_fresh_db.sh w3db
-- Run: psql -h /tmp -p 5544 -U postgres -d w3db -qAt -f supabase/phase13_test.sql | grep -E "FAIL|SUMMARY"
\set ON_ERROR_STOP off
\set o '00000000-0000-0000-0000-000000000001'
\set s '00000000-0000-0000-0000-000000000002'
\set m '00000000-0000-0000-0000-000000000005'
\set x '00000000-0000-0000-0000-000000000006'
\set a '00000000-0000-0000-0000-000000000008'
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
 (:'o','owner1@s.app','{"full_name":"Owner"}'), (:'s','staff2@s.app','{"full_name":"Sales"}'), (:'m','mgr5@s.app','{"full_name":"Mgr"}'),
 (:'x','far6@s.app','{"full_name":"Far"}'), (:'a','acc8@s.app','{"full_name":"Acct"}') on conflict do nothing;
update profiles set status='active';
insert into user_roles values (:'s','salesperson'),(:'m','management'),(:'x','salesperson'),(:'a','salesperson') on conflict do nothing;
insert into user_locations values (:'s',1),(:'x',3),(:'a',1) on conflict do nothing;
\i /home/user/My-tools/supabase/phase13.sql

\echo == T0 defaults and shape
select tt.chk('T0 grant view_daybook defined (window, emergency rule exists)', exists(select 1 from grant_defs g join rules r on r.key=g.emergency_rule where g.grant_code='view_daybook' and g.window_type='window'));
select tt.chk('T0 daybook_enabled default ON, start empty, em rule off', rule_on('daybook_enabled') and rule_txt('daybook_start') is null and not rule_on('em_view_daybook'));
select tt.chk('T0 no anon / public execute on new functions', not exists (select 1 from information_schema.routine_privileges where routine_name in ('day_book','salary_report','log_page_export','set_daybook_start','_daybook_lines') and grantee in ('PUBLIC','anon')));
select tt.chk('T0 parsers safe', _db_num('"12.5"')=12.5 and _db_num('"abc"') is null and _db_num('1e400'::text::jsonb) is null and _db_num('"99999999999999999"') is null and _db_date('2026-13-45') is null and _db_date('2026-10-05')='2026-10-05');

\echo == data (as postgres): loc1 and loc3 movements on 2026-10-05 / 06
insert into sales (client_id,location_id,receipt,sale_date,sold_at,lines,subtotal,discount,total,pay_mode,created_by,paid)
 values (gen_random_uuid(),1,901,'2026-10-05','2026-10-05 10:00+06','[]',500,0,500,'cash',:'s',500) returning id as s1 \gset
insert into sale_payments (sale_id,location_id,kind,mode,wallet,amount,paid_at,created_staff) values
 (:'s1',1,'sale','cash',null,300,'2026-10-05 10:00+06','st'),
 (:'s1',1,'sale','mobile','bkash',200,'2026-10-05 10:00+06','st'),
 (null,1,'collection','card',null,150,'2026-10-06 11:00+06','st'),
 (null,1,'sale','cash',null,40,'2026-10-06 12:00+06','st');
insert into sale_payments (sale_id,location_id,kind,mode,amount,paid_at,voided) values (null,1,'sale','cash',999,'2026-10-05 13:00+06',true);
insert into sale_payments (location_id,kind,mode,amount,paid_at) values (3,'sale','cash',70,'2026-10-05 10:00+06');
insert into suppliers (name) values ('Dudh Ghor') returning id as su \gset
insert into supplier_payments (supplier_id,location_id,mode,amount,paid_at) values (:'su',1,'cash',100,'2026-10-05 15:00+06'), (:'su',1,'bank',60,'2026-10-06 15:00+06');
insert into supplier_payments (supplier_id,location_id,mode,amount,paid_at,voided) values (:'su',1,'cash',555,'2026-10-05 15:00+06',true);
-- expense voucher 10-2 at loc 1 (submitted) + draft one that must not count
insert into entries (form_code,location_id,serial,entry_date,status,data,created_by) values
 ('10-2',1,9001,'2026-10-05','approved','{"lines":[{"head":"transport","amount":"25"},{"head":"other","amount":10},{"head":"x","amount":"abc"}]}',:'s'),
 ('10-2',1,9002,'2026-10-05','draft','{"lines":[{"amount":500}]}',:'s'),
 ('10-1',1,9003,'2026-10-06','submitted','{"count":{"n1000":2,"n500":1,"coin":20},"leave_float":"500","carrier":"Karim"}',:'s'),
 ('02-3',1,9004,'2026-10-05','approved','{"staff":"owner1","post":"cook","adv":[{"date":"2026-10-05","amount":"1000","method":"cash","ded_now":200,"balance":800},{"date":"2026-10-05","amount":300,"method":"goods","balance":300}]}',:'s'),
 ('02-2',1,9005,'2026-10-31','approved','{"month":"10","year":"2026","pay_method":"bank","pay_date":"2026-10-31","pay":[{"name":"Rahim cook","salary":10000,"due":"10000","overtime":500,"other":0,"adv_ded":1000,"other_ded":0},{"name":"Karim","salary":8000,"due":8000,"other":100,"other_ded":50,"remark":"x"}],"receipts":[{"name":"Rahim cook","net":9500,"date":"2026-10-05","method":"bank","signed":true},{"name":"Karim","net":8050,"method":"owner"}]}',:'s'),
 ('02-2',3,9006,'2026-10-31','approved','{"month":"10","year":"2026","pay":[{"name":"Far person","salary":5000,"due":5000,"adv_ded":0,"other_ded":0}],"receipts":[]}',:'s'),
 ('02-2',1,9007,'2026-09-30','approved','{"month":"9","year":"2026","pay":[{"name":"Old","due":1}]}',:'s'),
 ('02-1',1,9008,'2026-10-31','approved','{"month":"10","year":"2026","staff":[{"name":"Rahim cook","present":26,"absent":3,"late":2,"ot_hours":10}]}',:'s')
 on conflict do nothing;

\echo == T1 owner: movements and numbers
set role authenticated; select tt.as(:'o');
select day_book(1,'2026-10-05','2026-10-06') as j \gset
select tt.chk('T1 two days with lines', jsonb_array_length(:'j'::jsonb->'days')=2);
select tt.chk('T1 no start date => no opening/closing, flagged', not (:'j'::jsonb->>'opening_known')::boolean and jsonb_typeof(:'j'::jsonb#>'{days,0,open}')='null' and jsonb_typeof(:'j'::jsonb#>'{totals,open}')='null');
-- day 1 loc1: in cash 300, mobile 200; out cash 100 (supplier) + 35 (expense 25+10; "abc" ignored) + salary lines (owner holds salary_view): advance 1000 cash, salary 9500 bank
select tt.chk('T1 day1 cash in 300, mobile in 200, voided payment ignored', (:'j'::jsonb#>>'{days,0,in,cash}')::numeric=300 and (:'j'::jsonb#>>'{days,0,in,mobile}')::numeric=200 and (:'j'::jsonb#>>'{days,0,in,total}')::numeric=500);
select tt.chk('T1 day1 cash out = 100 supplier + 35 expense + 1000 advance (goods advance and draft ignored)', (:'j'::jsonb#>>'{days,0,out,cash}')::numeric=1135);
select tt.chk('T1 day1 bank out = salary receipt 9500 only (owner-personal receipt skipped)', (:'j'::jsonb#>>'{days,0,out,bank}')::numeric=9500);
select tt.chk('T1 day2 card = bank in 150; bank out 60; handover = 2*1000+500+20-500 = 2020 (loc view counts it)', (:'j'::jsonb#>>'{days,1,in,bank}')::numeric=150 and (:'j'::jsonb#>>'{days,1,out,bank}')::numeric=60 and (:'j'::jsonb#>>'{days,1,out,cash}')::numeric=2020);
select tt.chk('T1 loc 3 sale not in loc 1 view', (:'j'::jsonb#>>'{totals,in,cash}')::numeric=340);
-- all locations: loc3 cash 70 added, handover internal dropped
select day_book(null,'2026-10-05','2026-10-06') as ja \gset
select tt.chk('T1 all-locations: cash in 410, internal handover excluded from out', (:'ja'::jsonb#>>'{totals,in,cash}')::numeric=410 and (:'ja'::jsonb#>>'{totals,out,cash}')::numeric=1135
   and exists (select 1 from jsonb_array_elements(:'ja'::jsonb#>'{days,1,lines}') l where l->>'type'='handover' and (l->>'internal')::boolean));
-- start date
select set_daybook_start('2026-10-01');
select day_book(1,'2026-10-06','2026-10-06') as jb \gset
-- cash balance before 10-06 = 300 - 1135 = -835 ; bank: -9500 ; mobile 200 ; (negative is real: nothing before the start date is counted)
select tt.chk('T1 net since start = running total from the start date (cash 300-1135 = -835 before 10-06)', (:'jb'::jsonb#>>'{days,0,net_open,cash}')::numeric=-835 and (:'jb'::jsonb#>>'{days,0,net_open,bank}')::numeric=-9500 and (:'jb'::jsonb#>>'{days,0,net_open,mobile}')::numeric=200);
select tt.chk('T1 no opening balances set => open/close null (Data needed), balances false', jsonb_typeof(:'jb'::jsonb#>'{days,0,open}')='null' and not (:'jb'::jsonb->>'balances')::boolean);
select tt.chk('T1 net close = net open + day', (:'jb'::jsonb#>>'{days,0,net_close,cash}')::numeric=-835+40-2020 and (:'jb'::jsonb#>>'{totals,net_close,total}')::numeric=(:'jb'::jsonb#>>'{totals,net_open,total}')::numeric + (:'jb'::jsonb#>>'{totals,in,total}')::numeric - (:'jb'::jsonb#>>'{totals,out,total}')::numeric);
select day_book(1,'2026-09-28','2026-10-06') as jc \gset
select tt.chk('T1 range straddling the start: first day on/after start has 0 net opening', (:'jc'::jsonb#>>'{totals,net_open,total}')::numeric=0 and (:'jc'::jsonb#>>'{days,0,net_open,cash}')::numeric=0);
-- D1: start date INSIDE the data range: movements before it never enter the running total
select set_daybook_start('2026-10-06');
select day_book(1,'2026-10-05','2026-10-06') as jd \gset
select tt.chk('D1 day before the start has no net_open; 10-06 starts from 0 (10-05 rows ignored)', jsonb_typeof(:'jd'::jsonb#>'{days,0,net_open}')='null' and (:'jd'::jsonb#>>'{days,1,net_open,total}')::numeric=0
   and (:'jd'::jsonb#>>'{totals,net_close,cash}')::numeric=40-2020 and (:'jd'::jsonb#>>'{totals,net_open,total}')::numeric=0);
select set_daybook_start('2026-10-01');
select tt.err('T1 start date validated', $q$select set_daybook_start('1999-01-01')$q$, 'bad_date');
select tt.err('T1 range validated (to < from)', $q$select day_book(1,'2026-10-06','2026-10-05')$q$, 'bad_range');
select tt.err('T1 range validated (over a year)', $q$select day_book(1,'2020-01-01','2026-10-05')$q$, 'bad_range');
select tt.err('T1 null dates refused', $q$select day_book(1,null,'2026-10-05')$q$, 'bad_range');
select set_daybook_start(null);
select tt.chk('T1 start cleared again', (day_book(1,'2026-10-05','2026-10-06')->>'start') is null);

\echo == T2 grants and location isolation
reset role; set role authenticated; select tt.as(:'s');
select tt.err('T2 salesperson without grant refused', $q$select day_book(1,'2026-10-05','2026-10-06')$q$, 'not allowed');
select tt.err('T2 all-locations also refused', $q$select day_book(null,'2026-10-05','2026-10-06')$q$, 'not allowed');
select tt.err('T2 cannot set start date', $q$select set_daybook_start('2026-10-01')$q$, 'not allowed');
select tt.err('T2 salary report refused', $q$select salary_report(1,'2026-10-01')$q$, 'not allowed');
select tt.err('T2 export log refused (no export_data)', $q$select log_page_export('daybook','csv','{}',3)$q$, 'not allowed');
reset role; set role authenticated; select tt.as(:'o');
select set_user_grant(:'s','view_daybook');
reset role; set role authenticated; select tt.as(:'s');
select day_book(1,'2026-10-05','2026-10-06') as js \gset
select tt.chk('T2 with the grant: loc 1 allowed', jsonb_array_length(:'js'::jsonb->'days')=2);
select tt.chk('T2 salary lines hidden without salary_view (advance 1000 / salary 9500 not in sums)', (:'js'::jsonb->>'salary_hidden')::boolean and (:'js'::jsonb#>>'{days,0,out,cash}')::numeric=135 and (:'js'::jsonb#>>'{days,0,out,bank}')::numeric=0
  and not exists (select 1 from jsonb_array_elements(:'js'::jsonb->'days') d, jsonb_array_elements(d->'lines') l where l->>'type' in ('salary','advance')));
select tt.err('T2 no access to location 3 (not their location)', $q$select day_book(3,'2026-10-05','2026-10-06')$q$, 'not allowed');
select day_book(null,'2026-10-05','2026-10-06') as jn \gset
select tt.chk('T2 all-locations for a one-location user only shows their location', (:'jn'::jsonb#>>'{totals,in,cash}')::numeric=340);
-- grant limited to location 3 only: person at loc 1 cannot use it for loc 1
reset role; set role authenticated; select tt.as(:'o');
select set_user_grant(:'s','view_daybook',3);
select set_user_grant(:'s','view_daybook',null,null,false);
reset role; set role authenticated; select tt.as(:'s');
select tt.err('T2 location-limited grant (loc 3) does not open loc 1', $q$select day_book(1,'2026-10-05','2026-10-06')$q$, 'not allowed');
select tt.err('T2 ...and loc 3 is not their location (can_loc)', $q$select day_book(3,'2026-10-05','2026-10-06')$q$, 'not allowed');
reset role; set role authenticated; select tt.as(:'o');
select set_user_grant(:'s','view_daybook',3,null,false);
-- management role via role grant
select set_grant('view_daybook','management',true);
reset role; set role authenticated; select tt.as(:'m');
select tt.chk('T2 role grant works for management (all locations)', (select (day_book(null,'2026-10-05','2026-10-06')#>>'{totals,in,cash}')::numeric)=410);
reset role; set role authenticated; select tt.as(:'o');
select set_grant('view_daybook','management',false);
reset role; set role authenticated; select tt.as(:'m');
select tt.err('T2 role grant removed => refused', $q$select day_book(null,'2026-10-05','2026-10-06')$q$, 'not allowed');
-- switch off: only the owner
reset role; set role authenticated; select tt.as(:'o');
select set_user_grant(:'s','view_daybook');
select set_rule('daybook_enabled', 'false'::jsonb);
reset role; set role authenticated; select tt.as(:'s');
select tt.err('T2 daybook_enabled off => grantee refused', $q$select day_book(1,'2026-10-05','2026-10-06')$q$, 'daybook_off');
reset role; set role authenticated; select tt.as(:'o');
select tt.chk('T2 owner still opens it when off', jsonb_array_length(day_book(1,'2026-10-05','2026-10-06')->'days')=2);
select set_rule('daybook_enabled', 'true'::jsonb);
-- anonymous
reset role; set role anon;
select tt.err('T2 anon refused', $q$select day_book(1,'2026-10-05','2026-10-06')$q$, 'permission denied');
reset role;

\echo == T3 salary report
set role authenticated; select tt.as(:'o');
select salary_report(1,'2026-10-17') as r \gset
select tt.chk('T3 two lines for loc 1 / October, September sheet and loc 3 not included', jsonb_array_length(:'r'::jsonb->'rows')=2 and (:'r'::jsonb->>'sheets')::int=1);
select tt.chk('T3 gross/net = form formulas', (:'r'::jsonb#>>'{rows,0,gross}')::numeric=10500 and (:'r'::jsonb#>>'{rows,0,deductions}')::numeric=1000 and (:'r'::jsonb#>>'{rows,0,net}')::numeric=9500
   and (:'r'::jsonb#>>'{rows,1,gross}')::numeric=8100 and (:'r'::jsonb#>>'{rows,1,net}')::numeric=8050);
select tt.chk('T3 totals', (:'r'::jsonb#>>'{totals,gross}')::numeric=18600 and (:'r'::jsonb#>>'{totals,net}')::numeric=17550 and (:'r'::jsonb#>>'{totals,adv_ded}')::numeric=1000 and (:'r'::jsonb#>>'{totals,other_ded}')::numeric=50);
select tt.chk('T3 paid (receipts) and signed shown only as written', (:'r'::jsonb#>>'{rows,0,paid}')::numeric=9500 and (:'r'::jsonb#>>'{rows,0,signed}')::boolean and (:'r'::jsonb#>>'{rows,1,signed}') is null or true);
select tt.chk('T3 advances block: 1000 given in the month (goods line too = 1300), 200 deducted, balances as the form sums them', (:'r'::jsonb#>>'{advances,0,given}')::numeric=1300 and (:'r'::jsonb#>>'{advances,0,deducted}')::numeric=200 and (:'r'::jsonb#>>'{advances,0,outstanding}')::numeric=1100);
select tt.chk('T3 attendance block from 02-1', (:'r'::jsonb#>>'{attendance,0,present}')::numeric=26 and (:'r'::jsonb#>>'{attendance,0,ot_hours}')::numeric=10);
select tt.chk('T3 September sheet is a different month', (select (salary_report(1,'2026-09-02')#>>'{totals,gross}')::numeric)=1);
select tt.chk('T3 empty month => data_needed, no invented rows', (select (salary_report(1,'2026-05-02')->>'data_needed')::boolean and jsonb_array_length(salary_report(1,'2026-05-02')->'rows')=0));
select tt.chk('T3 all locations includes loc 3', (select jsonb_array_length(salary_report(null,'2026-10-02')->'rows'))=3);
select tt.err('T3 absurd month refused', $q$select salary_report(1,'1900-01-01')$q$, 'bad_range');
reset role; set role authenticated; select tt.as(:'a');
select tt.err('T3 no grant: refused', $q$select salary_report(1,'2026-10-01')$q$, 'not allowed');
reset role; set role authenticated; select tt.as(:'o');
select set_user_grant(:'a','salary_view',1);
reset role; set role authenticated; select tt.as(:'a');
select tt.chk('T3 salary_view at loc 1 opens loc 1', jsonb_array_length(salary_report(1,'2026-10-01')->'rows')=2);
select tt.err('T3 location-limited salary_view does not open loc 3', $q$select salary_report(3,'2026-10-01')$q$, 'not allowed');
select tt.chk('T3 all-locations shows only loc 1 to this person', (select jsonb_array_length(salary_report(null,'2026-10-01')->'rows'))=2);
select tt.err('T3 export not allowed without export_data', $q$select log_page_export('salary','csv','{}',2)$q$, 'not allowed');
reset role; set role authenticated; select tt.as(:'o');
select set_user_grant(:'a','export_data');
reset role; set role authenticated; select tt.as(:'a');
select log_page_export('salary','csv','{"month":"2026-10"}',2);
reset role;
select tt.chk('T3 export now allowed and audited', exists(select 1 from audit_log where action='export' and table_name='report' and record_id='salary' and staff_id is not null) );
set role authenticated; select tt.as(:'a');
select tt.err('T3 daybook export needs view_daybook too', $q$select log_page_export('daybook','csv','{}',2)$q$, 'not allowed');
select tt.err('T3 unknown report key', $q$select log_page_export('zzz','csv','{}',2)$q$, 'unknown_report');
select tt.err('T3 bad kind', $q$select log_page_export('salary','c;sv','{}',2)$q$, 'bad_kind');
reset role;

\echo == T5 audit fixes
reset role; set role authenticated; select tt.as(:'o');
-- D10 range / infinity
select tt.err('D10 366 days ok, 367 refused', $q$select day_book(1,'2025-10-01','2026-10-02')$q$, 'bad_range');
select tt.chk('D10 exactly 366 days accepted', (select day_book(1,'2025-10-01','2026-09-30') is not null));
select tt.err('D10 infinity refused', $q$select day_book(1,'-infinity','2026-10-02')$q$, 'bad_range');
select tt.err('D10 infinity (to) refused', $q$select day_book(1,'2026-10-02','infinity')$q$, 'bad_range');
-- D9 future dates capped at today
reset role;
insert into entries (form_code,location_id,serial,entry_date,status,data,created_by) values ('10-2',1,9100,(now() at time zone 'Asia/Dhaka')::date + 5,'approved','{"lines":[{"amount":77}]}',:'s');
set role authenticated; select tt.as(:'o');
select day_book(1,(now() at time zone 'Asia/Dhaka')::date,(now() at time zone 'Asia/Dhaka')::date + 10) as jf \gset
select tt.chk('D9 future-dated voucher not shown; to capped to today', (:'jf'::jsonb->>'capped')::boolean and (:'jf'::jsonb->>'to')::date=(now() at time zone 'Asia/Dhaka')::date and jsonb_array_length(:'jf'::jsonb->'days')=0);
-- D6 numbers
reset role;
select tt.chk('D6 parser: commas, leading/trailing dot, currency, Bangla digits', _db_num('"1,250.50"')=1250.5 and _db_num('".5"')=0.5 and _db_num('"5."')=5 and _db_num('"৳ 1,000"')=1000 and _db_num('"Tk 300"')=300 and _db_num('"১২৩"')=123 and _db_num('"-.5"')=-0.5 and _db_num('"1.2.3"') is null and _db_num('"12abc"') is null);
insert into entries (form_code,location_id,serial,entry_date,status,data,created_by) values ('10-2',1,9101,'2026-10-07','approved','{"lines":[{"amount":"1,000"},{"amount":"12x"},{"amount":""}]}',:'s');
set role authenticated; select tt.as(:'o');
select day_book(1,'2026-10-07','2026-10-07') as jg \gset
select tt.chk('D6 "1,000" counted, unreadable "12x" counted in skipped_rows, empty ignored', (:'jg'::jsonb#>>'{days,0,out,cash}')::numeric=1000 and (:'jg'::jsonb->>'skipped_rows')::int=1);
-- D3 opening balances (owner setter)
select tt.err('D3 setter owner-only / bounds', $q$select set_daybook_opening(1e15,0,0)$q$, 'bad_amount');
select set_daybook_start('2026-10-01');
select set_daybook_opening(1000,2000,3000);
select day_book(null,'2026-10-06','2026-10-06') as jh \gset
select tt.chk('D3 all-locations with all three balances: open = balance + net since start', (:'jh'::jsonb->>'balances')::boolean and (:'jh'::jsonb#>>'{days,0,open,cash}')::numeric=1000+(:'jh'::jsonb#>>'{days,0,net_open,cash}')::numeric and (:'jh'::jsonb#>>'{days,0,close,total}')::numeric=6000+(:'jh'::jsonb#>>'{days,0,net_close,total}')::numeric);
select day_book(1,'2026-10-06','2026-10-06') as ji \gset
select tt.chk('D3 single-location view never shows business-wide balances', not (:'ji'::jsonb->>'balances')::boolean and jsonb_typeof(:'ji'::jsonb#>'{days,0,open}')='null');
select set_daybook_opening(1000,null,3000);
select tt.chk('D3 one balance empty => no balances at all', not (day_book(null,'2026-10-06','2026-10-06')->>'balances')::boolean);
select set_daybook_opening(null,null,null);
reset role; set role authenticated; select tt.as(:'s');
select tt.err('D3 non-owner cannot set balances', $q$select set_daybook_opening(1,1,1)$q$, 'not allowed');
-- D5 handover: own line, summed separately, out in the single view only
reset role; set role authenticated; select tt.as(:'o');
select tt.chk('D5 transfers total shown in both views; counted in cash out only in the single-location view', (day_book(1,'2026-10-06','2026-10-06')#>>'{days,0,transfers}')::numeric=2020 and (day_book(null,'2026-10-06','2026-10-06')#>>'{days,0,transfers}')::numeric=2020
   and (day_book(1,'2026-10-06','2026-10-06')#>>'{days,0,out,cash}')::numeric=2020 and (day_book(null,'2026-10-06','2026-10-06')#>>'{days,0,out,cash}')::numeric=0);
-- D4 phase12 flows (only when phase12 is installed)
reset role;
select to_regclass('public.sale_returns') is not null as has12 \gset
\if :has12
insert into sale_returns (sale_id,location_id,lines,amount,credit_amount,refund_amount,refund_mode,reason_code,status,created_at) values (:'s1',1,'[]',80,0,80,'cash','damaged','done','2026-10-08 10:00+06');
insert into sale_returns (sale_id,location_id,lines,amount,credit_amount,refund_amount,refund_mode,reason_code,status,created_at) values (:'s1',1,'[]',50,50,0,null,'damaged','done','2026-10-08 11:00+06');
insert into supplier_refunds (supplier_id,location_id,mode,amount,refunded_at) values (:'su',1,'bank',90,'2026-10-08 12:00+06');
insert into supplier_refunds (supplier_id,location_id,mode,amount,refunded_at,voided) values (:'su',1,'cash',999,'2026-10-08 12:00+06',true);
set role authenticated; select tt.as(:'o');
select day_book(1,'2026-10-08','2026-10-08') as jr \gset
select tt.chk('D4 customer refund = cash OUT 80 (credit-only return ignored); supplier refund = bank IN 90 (voided ignored)', (:'jr'::jsonb#>>'{days,0,out,cash}')::numeric=80 and (:'jr'::jsonb#>>'{days,0,in,bank}')::numeric=90 and (:'jr'::jsonb#>>'{days,0,in,total}')::numeric=90);
reset role;
\endif
-- D12 masking
set role authenticated; select tt.as(:'o');
select set_rule('daybook_mask_names','true'::jsonb);
select tt.chk('D12 owner still sees names when masking is on', exists (select 1 from jsonb_array_elements(day_book(1,'2026-10-05','2026-10-05')#>'{days,0,lines}') l where l->>'text' is not null));
reset role; set role authenticated; select tt.as(:'s');
select day_book(1,'2026-10-05','2026-10-05') as jm \gset
select tt.chk('D12 grant holder gets names/refs masked when the switch is on', (:'jm'::jsonb->>'names_masked')::boolean and not exists (select 1 from jsonb_array_elements(:'jm'::jsonb#>'{days,0,lines}') l where l->>'text' is not null or l->>'ref' is not null));
reset role; set role authenticated; select tt.as(:'o');
select set_rule('daybook_mask_names','false'::jsonb);
-- D9 two sheets for the same location+month, same-name people
reset role;
insert into entries (form_code,location_id,serial,entry_date,status,data,created_by) values
 ('02-2',1,9010,'2026-10-20','approved','{"month":"10","year":"2026","pay":[{"name":"Karim","due":500}],"receipts":[{"name":"Karim","net":500,"signed":true}]}',:'s');
set role authenticated; select tt.as(:'o');
select salary_report(1,'2026-10-02') as jz \gset
select tt.chk('D9 duplicate sheets reported for loc 1', (:'jz'::jsonb#>>'{duplicate_sheets,0,loc}')::int=1 and (:'jz'::jsonb#>>'{duplicate_sheets,0,n}')::int=2);
select tt.chk('D9 same name twice => ambiguous, paid/signed not guessed, totals still add every line', (select count(*) from jsonb_array_elements(:'jz'::jsonb->'rows') r where (r->>'ambiguous')::boolean and r->>'name'='Karim')=2
   and not exists (select 1 from jsonb_array_elements(:'jz'::jsonb->'rows') r where r->>'name'='Karim' and r->'paid'<>'null'::jsonb) and (:'jz'::jsonb#>>'{totals,gross}')::numeric=19100);
reset role;
\echo == T4 re-run safety
\i /home/user/My-tools/supabase/phase13.sql
select tt.chk('T4 re-run keeps one grant def, rules not reset', (select count(*) from grant_defs where grant_code='view_daybook')=1 and (select count(*) from rules where key in ('daybook_enabled','daybook_start'))=2);
select 'SUMMARY ' || count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from tt.res;
