-- RPT-C1 fixture (phases 440 to 444): the W1-D fixture (tests/sql/w1d_fixture.sql) PLUS what the reports of this package read. Test data only (test_* names). Needs a database built through phase99
-- (the phases 440 to 444 may or may not be pasted: nothing here depends on them). Same users as the W1-D fixture: :o owner, :acc management with accounts rights, :st salesperson (place 1).
-- Hand-computed numbers (place 1, "today" = tt.today(), pm = first day of the previous month = the accounting start date):
--   W1-D part (see its header): sale 400 cash, expenses: approved voucher 500 + quick 300, wastage, count shortage, transit, cash short -20 and +5 (approved cases), supplier bill 400.
--   returns:      one sale return of 1 finished good = 100 (refund cash)
--   expenses:     a second voucher 290 (submitted, NOT approved); a bank charge 25 (bank account test_bank); a wallet fee 12 (bKash); one marketing line 18-1 of 1500 (source imprest)
--   journal:      opening (real opening journal) bank 50,000 / retained 50,000 on pm;  manual: pm+4  place 1 cash sale 5,000 (Dr 1110, Cr 4100);  pm+6 place 2 cash sale 3,000;  pm+6 place 2 rent 1,000 (Dr 5300, Cr 1110);
--                 pm+8 owner capital 2,000 into cash (Dr 1110, Cr 3100);  pm+9 fixed asset bought from bank 4,000 (Dr 1510, Cr 1120);  pm+10 bank deposit 2,000 cash -> bank (a transfer);
--                 pm+11 supplier bill paid by bank 600 outside the bill documents is NOT made (the W1-D bill 400 is unpaid = a payable)
--   attendance:   employee test_emp_c1 (place 1): 3 attendance_days today-2 .. today (present, late, absent); a paper register 02-1 with one line test_emp_paper (present 20, late 2, absent 1)
--   holidays:     one holiday today-3 (all places)
--   customers:    test_cust_champion: 3 sales today;  test_cust_old: one sale 200 days ago
\set ON_ERROR_STOP on
\ir w1d_fixture.sql
\set o '00000000-0000-0000-0000-000000000092'
\set acc '00000000-0000-0000-0000-000000000192'
select set_config('request.jwt.claim.sub', :'o', false);
select (:'pm'::date + 4) as d4, (:'pm'::date + 6) as d6, (:'pm'::date + 8) as d8, (:'pm'::date + 9) as d9, (:'pm'::date + 10) as d10 \gset

-- the real opening journal (source opening) and the manual postings of both months
select acct_opening('[{"code":"1120","debit":50000},{"code":"3900","credit":50000}]'::jsonb, false, 'test opening c1') ->> 'id' as c_open \gset
select acct_journal_post(:'d4'::date, 1, 'test cash sale p1', '[{"code":"1110","debit":5000},{"code":"4100","credit":5000}]'::jsonb) is not null as c_j1 \gset
select acct_journal_post(:'d6'::date, 2, 'test cash sale p2', '[{"code":"1110","debit":3000,"location_id":2},{"code":"4100","credit":3000,"location_id":2}]'::jsonb) is not null as c_j2 \gset
select acct_journal_post(:'d6'::date, 2, 'test rent p2', '[{"code":"5300","debit":1000,"location_id":2},{"code":"1110","credit":1000,"location_id":2}]'::jsonb) is not null as c_j3 \gset
select acct_journal_post(:'d8'::date, 1, 'test owner capital', '[{"code":"1110","debit":2000},{"code":"3100","credit":2000}]'::jsonb) is not null as c_j4 \gset
select acct_journal_post(:'d9'::date, 1, 'test fixed asset', '[{"code":"1510","debit":4000},{"code":"1120","credit":4000}]'::jsonb) is not null as c_j5 \gset
select acct_journal_post(:'d10'::date, 1, 'test bank deposit', '[{"code":"1120","debit":2000},{"code":"1110","credit":2000}]'::jsonb) is not null as c_j6 \gset

-- the 14-1 sheets of the W1-D fixture carry the short / over flag the hub report reads (the fixture made only the exception rows)
update entries set flags = '[{"code":"cash_short_over","amount":-20}]'::jsonb where form_code = '14-1' and serial = 92001;
update entries set flags = '[{"code":"cash_short_over","amount":5}]'::jsonb where form_code = '14-1' and serial = 92002;

-- a sale return of 1 finished good (100, refund in cash)
select sale_return(null, :'w_sale'::uuid, format('[{"item_id":"%s","qty":1}]', :'i_fg')::jsonb, 'damaged', 'test return', 'cash', null, null) ->> 'id' as c_ret \gset

-- expense records: a submitted voucher (290), a bank account with a charge (25), a wallet fee (12), a marketing line of 18-1 (1500, imprest)
select save_entry(null,'10-2',1,tt.today(),'{"lines":[{"head":"staff_meal","amount":"290","receipt":"yes"}]}'::jsonb,'[]') ->> 'id' as c_v2 \gset
select submit_entry(:'c_v2'::uuid) is not null as c_v2s \gset
select (money_account_add('bank', 'test_bank', 'test_bank', 'test_provider', null, 'test_acc_c1', null, null, 0, null, 'warn', null) ->> 'id')::bigint as c_ma \gset
select money_charge_add(:'c_ma'::bigint, 'charge', 25, tt.today(), 'test_ref_c1', null, 1, gen_random_uuid()) is not null as c_ch \gset
select d_wallet_opening_set(1, 1000, :'pm'::date) is not null as c_wo \gset
select d_wallet_fee_add(1, 1, tt.today(), 12, 'cash_out', 'test_ref_c1', null, gen_random_uuid()) is not null as c_wf \gset
select save_entry(null,'18-1',1,tt.today(), format('{"lines":[{"date":"%s","head":"1","campaign":"test_campaign","source":"imprest","amt":"1500"}]}', tt.today())::jsonb,'[]') ->> 'id' as c_m1 \gset
select submit_entry(:'c_m1'::uuid) is not null as c_m1s \gset

-- staff: one employee with 3 attendance days, one paper register 02-1, one holiday
insert into employees (full_name_bn, full_name_en, status, primary_location_id, employee_no) values ('test_emp_c1', 'test_emp_c1', 'active', 1, 'TC1');
select id as c_emp from employees where employee_no = 'TC1' \gset
select attendance_mark(:'c_emp'::uuid, tt.today() - 2, 'present', null, null, 0, 'test mark', 'test') is not null as c_a1 \gset
select attendance_mark(:'c_emp'::uuid, tt.today() - 1, 'late', null, null, 60, 'test mark', 'test') is not null as c_a2 \gset
select attendance_mark(:'c_emp'::uuid, tt.today(), 'absent', null, null, 0, 'test absence', 'test') is not null as c_a3 \gset
select save_entry(null,'02-1',1,tt.today(),'{"staff":[{"name":"test_emp_paper","present":"20","late":"2","absent":"1","ot_hours":"3"}]}'::jsonb,'[]') ->> 'id' as c_e21 \gset
select submit_entry(:'c_e21'::uuid) is not null as c_e21s \gset
select holiday_save(tt.today() - 3, null, 'test_holiday', 'test_holiday', true) is not null as c_h1 \gset

-- customers for the segment and lapsed reports
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":100}]','01711000001','test_cust_champion','retail',null,false)->>'id' as c_s1 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":100}]','01711000001','test_cust_champion','retail',null,false)->>'id' as c_s2 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":100}]','01711000001','test_cust_champion','retail',null,false)->>'id' as c_s3 \gset
select record_sale2(gen_random_uuid(),1,format('[{"item_id":"%s","qty":1,"price":100}]',:'i_fg')::jsonb,0,'[{"mode":"cash","amount":100}]','01711000002','test_cust_old','retail',null,false)->>'id' as c_s4 \gset
update sales set sale_date = tt.today() - 200 where id = :'c_s4'::uuid;
select acct_post_pending(false) ->> 'posted' as c_posted \gset
select :'c_posted' as posted_c1;
