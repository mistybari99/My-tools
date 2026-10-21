-- Phase 453 tests (RPT-C2 R5 part 1: credit days, credit risk and overdue #138, dues-not-linked notice). Neutral test_* data only.  bash tests/sql/c2_run.sh phase453
\ir ../tests/sql/c2_fixture.sql
\ir ../tests/sql/c2_cust_fixture.sql

\echo == T0 shape
select tt.chk('T0 functions open, helper closed, anon none; column and three rules exist, all blank',
  has_function_privilege('authenticated','public.c2_credit_risk(date,boolean,text)','execute') and has_function_privilege('authenticated','public.c2_customer_credit_days_set(uuid,int,text)','execute')
  and has_function_privilege('authenticated','public.c2_dues_not_linked_notice()','execute') and not has_function_privilege('anon','public.c2_credit_risk(date,boolean,text)','execute')
  and not has_function_privilege('authenticated','public._c2_audit(text,text,text,jsonb)','execute')
  and exists (select 1 from information_schema.columns where table_name='customers' and column_name='credit_days')
  and rule_num('credit_default_days') is null and rule_num('credit_risk_watch_days') is null and rule_num('credit_risk_high_days') is null);

\echo == T1 credit days
select tt.as(:'p');
select tt.err('T1 a salesperson without customer_manage cannot set credit days', format($$select c2_customer_credit_days_set('%s', 15)$$, :'cu2'), 'not allowed');
select tt.as(:'o');
select c2_customer_credit_days_set(:'cu2'::uuid, 15) ->> 'credit_days' as cd \gset
select tt.chk('T1 owner sets 15 days (first time, no reason needed); audit line written', :'cd'='15' and (select credit_days from customers where id=:'cu2'::uuid)=15
  and exists (select 1 from audit_log where action='credit_days_set' and record_id=:'cu2'));
select tt.err('T1 changing an existing value needs a reason', format($$select c2_customer_credit_days_set('%s', 20)$$, :'cu2'), 'reason_required');
select tt.err('T1 days must be 0 to 3650', format($$select c2_customer_credit_days_set('%s', -1)$$, :'cu2'), 'bad_days');
select tt.chk('T1 same value = no-op', (c2_customer_credit_days_set(:'cu2'::uuid, 15) ->> 'noop')::boolean);
select c2_customer_credit_days_set(:'cu2'::uuid, null, 'test_terms_removed') is not null as rm \gset
select tt.chk('T1 a blank (null) removes the terms', (select credit_days from customers where id=:'cu2'::uuid) is null);
select tt.as(:'m'); select tt.err('T1 manager without the grant refused', format($$select c2_customer_credit_days_set('%s', 5)$$, :'cu2'), 'not allowed');
select tt.as(:'o');

\echo == T2 credit risk (rules blank): amounts and ages are facts, the risk label says rule not set
select tt.as(:'m');
select c2_credit_risk() as cr \gset
select tt.chk('T2 customers owing: cu1 150, cu2 500, cu4 200 (cu3 paid in full is not listed); balance total 850', (:'cr'::jsonb #>> '{summary,customers_owing}')::int=3 and (:'cr'::jsonb #>> '{summary,balance_total}')::numeric=850);
select tt.chk('T2 cu1: balance 150, oldest open T-40, terms 30 days (customer), overdue 50, 10 days past due, not yet due 100', (select (r ->> 'balance')::numeric from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=150
  and (select (r ->> 'overdue')::numeric from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=50 and (select (r ->> 'days_past_due')::int from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=10
  and (select (r ->> 'not_yet_due')::numeric from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=100 and (select r ->> 'terms_source' from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')='customer');
select tt.chk('T2 the balance equals the existing dues list for every customer (same figure, not a new one)', not exists (
  select 1 from jsonb_array_elements(:'cr'::jsonb -> 'rows') r join customer_dues() d on d.id = (r ->> 'customer_id')::uuid where abs((r ->> 'balance')::numeric - d.balance) > 0.005)
  and (select count(*) from customer_dues())=3);
select tt.chk('T2 cu2 has no terms: balance 500 listed, overdue is null (not 0), risk no_terms', (select r -> 'overdue' from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu2')='null'::jsonb
  and (select r ->> 'risk' from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu2')='no_terms' and (:'cr'::jsonb #>> '{summary,owing_without_terms}')::int=1 and (:'cr'::jsonb #>> '{summary,balance_without_terms}')::numeric=500);
select tt.chk('T2 cu4: limit 100, balance 200 = 200 percent, over limit, terms 0 days -> 2 days past due', (select (r ->> 'limit_used_pct')::numeric from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu4')=200.0
  and (select (r ->> 'over_limit')::boolean from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu4') and (select (r ->> 'days_past_due')::int from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu4')=2);
select tt.chk('T2 risk rules blank: customers with an overdue amount say rule_not_set (no invented limit); notes say so', (select r ->> 'risk' from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')='rule_not_set'
  and (:'cr'::jsonb -> 'notes') ? 'risk_rule_not_set' and (:'cr'::jsonb -> 'notes') ? 'no_default_terms');
select tt.chk('T2 advance held beside the due: cu1 40', (select (r ->> 'advance_held')::numeric from jsonb_array_elements(:'cr'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')=40);

\echo == T3 the rules switch the labels on
select tt.as(:'o');
select set_rule('credit_risk_watch_days','7'::jsonb) is null as w1 \gset
select set_rule('credit_risk_high_days','30'::jsonb) is null as w2 \gset
select set_rule('credit_default_days','60'::jsonb) is null as w3 \gset
select c2_credit_risk() as cr2 \gset
select tt.chk('T3 cu1 (10 days past due) = watch; cu4 (2 days) = ok; cu2 now uses the default 60 days: 100 days old -> 40 past due -> high',
  (select r ->> 'risk' from jsonb_array_elements(:'cr2'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu1')='watch' and (select r ->> 'risk' from jsonb_array_elements(:'cr2'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu4')='ok'
  and (select r ->> 'risk' from jsonb_array_elements(:'cr2'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu2')='high' and (select r ->> 'terms_source' from jsonb_array_elements(:'cr2'::jsonb -> 'rows') r where r ->> 'customer_id'=:'cu2')='default'
  and (:'cr2'::jsonb #>> '{summary,high}')::int=1 and (:'cr2'::jsonb #>> '{summary,watch}')::int=1);
select tt.chk('T3 only-overdue filter and search', jsonb_array_length(c2_credit_risk(null, true) -> 'rows')=3 and jsonb_array_length(c2_credit_risk(null, false, 'test_cust_4') -> 'rows')=1);
select tt.chk('T3 as-of in the past: 20 days ago cu1 S1 (due T-10) is not yet due, overdue 0', (select (r ->> 'overdue')::numeric from jsonb_array_elements(c2_credit_risk(tt.today()-20) -> 'rows') r where r ->> 'customer_id'=:'cu1')=0);
select tt.err('T3 a future as-of is refused', $$select c2_credit_risk(current_date + 30)$$, 'bad_date');

\echo == T4 access
select tt.as(:'r');
select tt.chk('T4 a view_reports holder may read; mobile hidden', c2_credit_risk() ->> 'as_of' is not null and (c2_credit_risk() -> 'notes') ? 'mobile_hidden');
select tt.as(:'k');
select tt.err('T4 storekeeper without report access refused', $$select c2_credit_risk()$$, 'not allowed');
select tt.err('T4 ... and the notice too', $$select c2_dues_not_linked_notice()$$, 'not allowed');

\echo == T5 dues not linked to a customer
select tt.as(:'m');
select c2_dues_not_linked_notice() as nl \gset
select tt.chk('T5 opening dues 300 entered but not counted (open_parties_link OFF); sale due 100 with no customer; manager is not an accountant so the journal part is not checked',
  (select (i ->> 'amount')::numeric from jsonb_array_elements(:'nl'::jsonb -> 'items') i where i ->> 'code'='opening_not_counted')=300
  and (select (i ->> 'amount')::numeric from jsonb_array_elements(:'nl'::jsonb -> 'items') i where i ->> 'code'='sales_due_no_customer')=100 and (:'nl'::jsonb ->> 'journal_checked')='false'
  and (select i ->> 'fix_route' from jsonb_array_elements(:'nl'::jsonb -> 'items') i where i ->> 'code'='opening_not_counted')='openparties');
select tt.as(:'o'); select acct_set_start(tt.today()-300) is not null as ac0 \gset
select set_rule('accounting_on','true') is null as ac1 \gset
select acct_post_pending(false, 500) is not null as posted \gset
select c2_dues_not_linked_notice() as nl2 \gset
select tt.chk('T5 owner with the books started: the journal part is checked; receivable with no customer shown (the no-customer sale 100 posts without a party)',
  (:'nl2'::jsonb ->> 'journal_checked')='true' and (select (i ->> 'amount')::numeric from jsonb_array_elements(:'nl2'::jsonb -> 'items') i where i ->> 'code'='journal_receivable_no_customer')=100);

\echo == T9 paste twice
select count(*) as r_before from rules where key like 'credit_%' \gset
\ir phase453.sql
select tt.chk('T9 pasted again: no duplicate rules, credit days kept', (select count(*) from rules where key like 'credit_%')=:r_before and (select credit_days from customers where id=:'cu1'::uuid)=30);
select 'RESULT ' || count(*) filter (where ok) || ' pass, ' || count(*) filter (where not ok) || ' fail' from tt.res;
