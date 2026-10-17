-- Phase 454 tests (RPT-C2 R5 part 2: lifetime value #139, returns and complaints #140, special-order history #141, customer card). Neutral test_* data only.  bash tests/sql/c2_run.sh phase454
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_cust_fixture.sql

-- extra data: a return, complaint sheets, a cake order and a custom paper sheet for test_cust_1; birthday in 10 days
select tt.as(:'p');
select online_order_save(null, gen_random_uuid(), 1, 'phone', 'test_cust_1', '01700000301', null, format('[{"item_id":"%s","qty":1}]', :'ia')::jsonb, 'pickup', null, tt.today()+2, 0, 0, 0, null, null, null) ->> 'id' as ocake \gset
select c2_order_spec_save(:'ocake'::uuid, '[{"weight_kg":2,"flavour":"Test_Flavour_X","message":"test_msg","design":"test_design"}]'::jsonb) is not null as sp \gset
select tt.as(:'o');
set session_replication_role = replica;
insert into sale_returns (sale_id, location_id, customer_id, lines, amount, credit_amount, refund_amount, reason_code, status, created_by) values (:'s1'::uuid, 1, :'cu1'::uuid, '[]'::jsonb, 100, 100, 0, 'test_reason_x', 'done', :'p'::uuid);
insert into entries (form_code, location_id, serial, entry_date, status, data, created_by, created_staff, submitted_at) values
 ('20-3', 1, 9101, tt.today(), 'submitted', jsonb_build_object('cust_name','test_cust_1','cust_phone','01700000301','c_taste','true','refund_amt','50'), :'p', 'test_sales1', now()),
 ('20-3', 1, 9102, tt.today(), 'submitted', jsonb_build_object('cust_name','test_cust_1','cust_phone','0170 000 0301','c_sick','true','c_late','true'), :'p', 'test_sales1', now()),
 ('20-3', 1, 9103, tt.today(), 'submitted', jsonb_build_object('cust_name','test_nophone','c_broken','true'), :'p', 'test_sales1', now()),
 ('20-3', 1, 9104, tt.today(), 'submitted', jsonb_build_object('cust_name','test_unknown','cust_phone','01799999999','c_short','true'), :'p', 'test_sales1', now()),
 ('20-1', 1, 9201, tt.today(), 'submitted', jsonb_build_object('order_type','custom','cust_name','test_cust_1','cust_phone','01700000301','deliv_date',(tt.today()-4)::text,'total','400','advance','100',
     'items',jsonb_build_array(jsonb_build_object('item','TST-A','desc','test_paper_flavour','qty','1','msg','test_paper_msg','design','test_paper_design'))), :'p', 'test_sales1', now()),
 ('20-1', 1, 9202, tt.today(), 'submitted', jsonb_build_object('order_type','custom','cust_name','test_unknown','cust_phone','01799999999','total','300','advance','50','items',jsonb_build_array(jsonb_build_object('item','TST-A','desc','test_other'))), :'p', 'test_sales1', now());
set session_replication_role = origin;
-- birthday: a past year, the month and day of today + 10
update customers set birthday = make_date(1990, extract(month from tt.today() + 10)::int, extract(day from tt.today() + 10)::int) where id = :'cu1'::uuid;

\echo == T0 shape
select tt.chk('T0 functions open to browsers, helpers closed, anon none',
  has_function_privilege('authenticated','public.c2_customer_ltv(date,date,text,int,uuid)','execute') and has_function_privilege('authenticated','public.c2_customer_returns(date,date,text,uuid)','execute')
  and has_function_privilege('authenticated','public.c2_customer_special_orders(date,date,text,uuid)','execute') and has_function_privilege('authenticated','public.c2_customer_card(uuid)','execute')
  and not has_function_privilege('authenticated','public._c2_mob(text)','execute') and not has_function_privilege('anon','public.c2_customer_card(uuid)','execute'));

\echo == T1 lifetime value (#139) - all time, no 365-day cap
select tt.as(:'m');
select c2_customer_ltv() as lt \gset
select tt.chk('T1 cu1: 2 orders, revenue 400, returns 100, net 300, average 200, first T-40, last T-10, 30 days as a customer', (select (r ->> 'orders')::int from jsonb_array_elements(:'lt'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=2
  and (select (r ->> 'revenue')::numeric from jsonb_array_elements(:'lt'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=400 and (select (r ->> 'net_revenue')::numeric from jsonb_array_elements(:'lt'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=300
  and (select (r ->> 'avg_order')::numeric from jsonb_array_elements(:'lt'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=200 and (select (r ->> 'days_as_customer')::int from jsonb_array_elements(:'lt'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=30
  and (select r ->> 'first_sale' from jsonb_array_elements(:'lt'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=(tt.today()-40)::text);
select tt.chk('T1 sorted by net revenue: cu2 (500) first; sales with no customer are counted apart (1 sale, 100)', (:'lt'::jsonb -> 'rows' -> 0 ->> 'customer_id')=:'cu2' and (:'lt'::jsonb #>> '{summary,sales_without_customer}')::int=1
  and (:'lt'::jsonb #>> '{summary,revenue_without_customer}')::numeric=100 and (:'lt'::jsonb #>> '{summary,customers}')::int=4);
select tt.chk('T1 a manager has no cost right: margin hidden (null) and the note says so', (select r -> 'gross_margin' from jsonb_array_elements(:'lt'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')='null'::jsonb and (:'lt'::jsonb -> 'notes') ? 'cost_hidden');
select tt.as(:'o');
select c2_customer_ltv() as lto \gset
select tt.chk('T1 owner: cu1 margin only over sales with a known cost: (300-120)+(100-40) = 240, both sales costed', (select (r ->> 'gross_margin')::numeric from jsonb_array_elements(:'lto'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=240
  and (select (r ->> 'sales_with_known_cost')::int from jsonb_array_elements(:'lto'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=2);
set session_replication_role = replica; update sales set sale_date = tt.today()-600 where id = :'s3'::uuid; set session_replication_role = origin;
select tt.chk('T1 a sale 600 days old is counted in all-time (no 365-day cap) and in a 700-day window', (select (r ->> 'revenue')::numeric from jsonb_array_elements(c2_customer_ltv() -> 'rows') r where r ->> 'customer_id'=:'cu2')=500
  and (select (r ->> 'revenue')::numeric from jsonb_array_elements(c2_customer_ltv(tt.today()-700, tt.today()) -> 'rows') r where r ->> 'customer_id'=:'cu2')=500);
select tt.chk('T1 a window narrows it: T-45..T-30 leaves cu1 with 1 order of 300 and returns 0 (the return is dated today)', (select (r ->> 'orders')::int from jsonb_array_elements(c2_customer_ltv(tt.today()-45, tt.today()-30) -> 'rows') r where r ->> 'customer_id'=:'cu1')=1
  and (select (r ->> 'revenue')::numeric from jsonb_array_elements(c2_customer_ltv(tt.today()-45, tt.today()-30) -> 'rows') r where r ->> 'customer_id'=:'cu1')=300 and (select (r ->> 'returns')::numeric from jsonb_array_elements(c2_customer_ltv(tt.today()-45, tt.today()-30) -> 'rows') r where r ->> 'customer_id'=:'cu1')=0);
select tt.err('T1 one date only is refused', $$select c2_customer_ltv(current_date - 5, null)$$, 'bad_date');
select tt.chk('T1 search and single customer', jsonb_array_length(c2_customer_ltv(null, null, 'test_cust_3') -> 'rows')=1 and jsonb_array_length(c2_customer_ltv(null, null, null, 200, :'cu4'::uuid) -> 'rows')=1);

\echo == T2 returns and complaints (#140)
select tt.as(:'m');
select c2_customer_returns(tt.today()-30, tt.today()) as rr \gset
select tt.chk('T2 cu1: 1 return of 100 (top reason test_reason_x), 2 complaint sheets linked by phone (one written with spaces), 1 sick case, refund 50',
  (select (r ->> 'returns')::int from jsonb_array_elements(:'rr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=1 and (select (r ->> 'return_amount')::numeric from jsonb_array_elements(:'rr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=100
  and (select r ->> 'top_reason' from jsonb_array_elements(:'rr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')='test_reason_x' and (select (r ->> 'complaints')::int from jsonb_array_elements(:'rr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=2
  and (select (r ->> 'sick_cases')::int from jsonb_array_elements(:'rr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=1 and (select (r ->> 'complaint_refunds')::numeric from jsonb_array_elements(:'rr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=50
  and (select (r #>> '{causes,taste}')::int from jsonb_array_elements(:'rr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=1);
select tt.chk('T2 four sheets in all: 1 without a phone and 1 with a phone that is no customer are COUNTED apart, not dropped', (:'rr'::jsonb #>> '{summary,complaint_sheets_total}')::int=4 and (:'rr'::jsonb #>> '{summary,complaint_sheets_without_phone}')::int=1
  and (:'rr'::jsonb #>> '{summary,complaint_sheets_phone_not_a_customer}')::int=1 and (:'rr'::jsonb #>> '{summary,complaints_linked}')::int=2 and (:'rr'::jsonb -> 'notes') ? 'paper_20_3_phone_optional');
select tt.chk('T2 only customers with a return or a complaint are listed (just cu1)', jsonb_array_length(:'rr'::jsonb -> 'rows')=1);
select tt.chk('T2 outside the range: nothing', jsonb_array_length(c2_customer_returns(tt.today()-300, tt.today()-200) -> 'rows')=0);
select tt.err('T2 bad range', $$select c2_customer_returns(current_date, current_date - 2)$$, 'bad_date');

\echo == T3 special orders (#141)
select c2_customer_special_orders(tt.today()-30, tt.today()+3) as so \gset
select tt.chk('T3 cu1 has 2 special orders (1 app cake with flavour test_flavour_x, 1 paper custom with test_paper_flavour); sources kept apart',
  (select (z ->> 'special_orders')::int from jsonb_array_elements(:'so'::jsonb -> 'customers') z where z ->> 'customer_id'=:'cu1')=2
  and (select count(*) from jsonb_array_elements(:'so'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1' and r ->> 'source'='app')=1 and (select count(*) from jsonb_array_elements(:'so'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1' and r ->> 'source'='paper_20_1')=1
  and (select z -> 'flavours' from jsonb_array_elements(:'so'::jsonb -> 'customers') z where z ->> 'customer_id'=:'cu1') @> '["test_flavour_x"]'::jsonb);
select tt.chk('T3 one paper sheet of a phone that is no customer: counted as rows_without_a_customer_match, not dropped', (:'so'::jsonb #>> '{summary,rows_without_a_customer_match}')::int=1 and (:'so'::jsonb #>> '{summary,special_order_rows}')::int=3);
select tt.chk('T3 birthday as entered, next one in 10 days; anniversary blank stays null (never a guess)', (select (z ->> 'next_birthday_in_days')::int from jsonb_array_elements(:'so'::jsonb -> 'customers') z where z ->> 'customer_id'=:'cu1')=10
  and (select z -> 'next_anniversary_in_days' from jsonb_array_elements(:'so'::jsonb -> 'customers') z where z ->> 'customer_id'=:'cu1')='null'::jsonb);
select tt.chk('T3 29 February falls on 1 March in a year with none; a normal date is the next one', _c2_next_annual(date '2000-02-29', date '2027-01-10')=date '2027-03-01' and _c2_next_annual(date '1990-05-05', date '2027-05-05')=date '2027-05-05');
select tt.chk('T3 single customer filter', jsonb_array_length(c2_customer_special_orders(tt.today()-30, tt.today()+3, null, :'cu1'::uuid) -> 'rows')=2 and jsonb_array_length(c2_customer_special_orders(tt.today()-30, tt.today()+3, null, :'cu2'::uuid) -> 'rows')=0);

\echo == T4 customer card
select c2_customer_card(:'cu1'::uuid) as cd \gset
select tt.chk('T4 card of cu1: terms 30, credit row (balance 150 minus the 100 return credit = 50), ltv row (orders 2), returns row, 2 special orders', (:'cd'::jsonb #>> '{customer,credit_days}')::int=30 and (:'cd'::jsonb #>> '{credit,balance}')::numeric=50 and (:'cd'::jsonb #>> '{ltv,orders}')::int=2
  and (:'cd'::jsonb #>> '{returns_last_365_days,returns}')::int=1 and jsonb_array_length(:'cd'::jsonb -> 'special_orders_last_365_days')=2 and (:'cd'::jsonb ->> 'can_edit_terms')='false');
select tt.err('T4 unknown customer', format($$select c2_customer_card('%s')$$, gen_random_uuid()), 'customer_not_found');

\echo == T5 access
select tt.as(:'r');
select tt.chk('T5 view_reports holder reads all four; mobile hidden', c2_customer_ltv() ->> 'all_time' = 'true' and (c2_customer_returns(tt.today()-30, tt.today()) -> 'notes') ? 'mobile_hidden' and jsonb_array_length(c2_customer_special_orders(tt.today()-30, tt.today()+3) -> 'rows')=3);
select tt.as(:'k');
select tt.err('T5 storekeeper refused (ltv)', $$select c2_customer_ltv()$$, 'not allowed');
select tt.err('T5 storekeeper refused (returns)', $$select c2_customer_returns(current_date-1, current_date)$$, 'not allowed');
select tt.err('T5 storekeeper refused (special orders)', $$select c2_customer_special_orders(current_date-1, current_date)$$, 'not allowed');
select tt.err('T5 storekeeper refused (card)', format($$select c2_customer_card('%s')$$, :'cu1'), 'not allowed');

\echo == T9 paste twice
\ir phase454.sql
select tt.chk('T9 pasted again without error', true);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
