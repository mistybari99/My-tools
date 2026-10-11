\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.ck(n text, ok boolean) returns text language sql as $$ select case when coalesce(ok,false) then 'PASS ' else 'FAIL ' end || n $$;
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
set role authenticated;
select pg_temp.u(1) \g /dev/null
select set_rule('report_aging_buckets',null) \g /dev/null
select set_rule('report_near_limit_pct',null) \g /dev/null
\set R '{"from":"2026-09-08","to":"2026-09-14"}'
with r as (select report_run('sales_summary',:'R') j)
select pg_temp.ck('T1 summary', j#>>'{totals,bills}'='6' and (j#>>'{totals,net}')::numeric=4530 and (j#>>'{totals,gross}')::numeric=4690 and (j#>>'{totals,discount}')::numeric=160 and (j#>>'{totals,paid}')::numeric=3950 and (j#>>'{totals,due}')::numeric=580 and j#>>'{totals,void_bills}'='1' and (j#>>'{totals,void_amt}')::numeric=260 and (j#>>'{totals,avg_bill}')::numeric=755 and (j#>>'{totals,cogs}')::numeric=2300 and (j#>>'{totals,gp}')::numeric=1221.86 and (j#>>'{totals,gp_pct}')::numeric=34.69 and (j#>>'{totals,uncosted_pct}')::numeric=22.25) from r;
with r as (select report_run('sales_summary',:'R','location') j)
select pg_temp.ck('T2a by location', (select string_agg(e->>'location_id'||':'||(e->>'bills')||':'||(e->>'net')||':'||(e->>'cogs'),',' order by e->>'location_id') from jsonb_array_elements(j->'rows') e)='1:3:3480:2100.00,3:3:1050:200.00') from r;
with r as (select report_run('sales_combined',:'R') j)
select pg_temp.ck('T2b combined default location + total', jsonb_array_length(j->'rows')=2 and (j#>>'{totals,net}')::numeric=4530 and (select sum((e->>'share_pct')::numeric) from jsonb_array_elements(j->'rows') e)=100.00 and j#>>'{totals,share_pct}'='100') from r;
with r as (select report_run('sales_combined',:'R','brand') j)
select pg_temp.ck('T2c by brand', (select string_agg(e->>'brand_code'||':'||(e->>'net'),',' order by e->>'brand_code') from jsonb_array_elements(j->'rows') e)='islamiya:3480,misty_bari:1050') from r;
-- compare
with r as (select report_run('sales_trend','{"from":"2026-09-08","to":"2026-09-14"}','day',null,1,true) j)
select pg_temp.ck('T3 compare totals', j#>>'{compare,from}'='2026-09-01' and j#>>'{compare,to}'='2026-09-07' and (j#>>'{compare,totals,net}')::numeric=1050 and (j#>>'{compare,delta,net,abs}')::numeric=3480 and (j#>>'{compare,delta,net,pct}')::numeric=331.43 and (j#>>'{compare,totals,bills}')='2') from r;
with r as (select report_run('sales_trend','{"from":"2026-09-08","to":"2026-09-14"}','day',null,1,true) j)
select pg_temp.ck('T3b compare rows aligned (09-03 -> 09-10 net 700; 09-05 -> 09-12 net 350)', (select (e->>'net')::numeric from jsonb_array_elements(j#>'{compare,rows}') e where e->>'day'='2026-09-10')=700 and (select (e->>'net')::numeric from jsonb_array_elements(j#>'{compare,rows}') e where e->>'day'='2026-09-12')=350) from r;
with r as (select report_run('sales_trend','{"from":"2026-09-08","to":"2026-09-14"}','day') j)
select pg_temp.ck('T3c trend days sorted asc', (select string_agg(e->>'day',',' order by ord) from jsonb_array_elements(j->'rows') with ordinality t(e,ord))='2026-09-08,2026-09-09,2026-09-10,2026-09-11,2026-09-13') from r;
with r as (select report_run('sales_trend','{"from":"2026-09-08","to":"2026-09-14","compare_mode":"week"}','day',null,1,true) j)
select pg_temp.ck('T3d compare week mode', j#>>'{compare,from}'='2026-09-01' and (j#>>'{compare,totals,net}')::numeric=1050) from r;
-- item / category
with r as (select report_run('item_sales',:'R') j)
select pg_temp.ck('T4 item_sales', (select string_agg(e->>'item_code'||'|'||(e->>'qty')||'|'||(e->>'net'),',' order by e->>'item_code', (e->>'net')::numeric) from jsonb_array_elements(j->'rows') e)='-|2.000|200.00,-|2.000|250.00,I-001|4.000|1021.86,I-002|10.000|2500.00,I-003|2.000|558.14'
  and (j#>>'{totals,net}')::numeric=4530 and (j#>>'{totals,cogs}')::numeric=2300 and (j#>>'{totals,override_lines}')='1') from r;
with r as (select report_run('item_sales',:'R','item') j) select (select string_agg(e->>'item_code'||'='||coalesce(e->>'gp','null'),',' order by e->>'item_code') from jsonb_array_elements(j->'rows') e) from r;
with r as (select report_run('category_sales',:'R') j)
select pg_temp.ck('T5 category', (j#>>'{totals,net}')::numeric=4530 and (select sum((e->>'net')::numeric) from jsonb_array_elements(j->'rows') e)=4530), (select string_agg(e->>'category'||'='||(e->>'net'),',') from jsonb_array_elements(j->'rows') e) from r;
-- register
with r as (select report_run('receipt_register',:'R') j)
select pg_temp.ck('T6 register owner', j#>>'{totals,receipts}'='7' and j#>>'{totals,void_receipts}'='1' and (j#>>'{totals,total}')::numeric=4530 and jsonb_array_length(j->'rows')=7 and j#>>'{rows,0,receipt}'='4' and j#>>'{rows,0,day}'='2026-09-13') from r;
with r as (select report_run('receipt_register','{"from":"2026-09-08","to":"2026-09-14","search":"Cust One"}') j) select pg_temp.ck('T6b search by name', j#>>'{totals,receipts}'='1') from r;
with r as (select report_run('receipt_register','{"from":"2026-09-08","to":"2026-09-14","status":"void"}') j) select pg_temp.ck('T6c status void', j#>>'{totals,receipts}'='1') from r;
with r as (select report_run('receipt_register','{"from":"2026-09-08","to":"2026-09-14","min_amount":700,"max_amount":1000}') j) select pg_temp.ck('T6d amount range 700..1000 (S3 780,S6 800)', j#>>'{totals,receipts}'='2') from r;
with r as (select report_run('receipt_register','{"from":"2026-09-08","to":"2026-09-14","search":"01711"}') j) select pg_temp.ck('T6e search mobile (owner)', j#>>'{totals,receipts}'='1') from r;
-- hour weekday
with r as (select report_run('hour_weekday',:'R') j)
select pg_temp.ck('T7 hours', (select string_agg(e->>'hour'||':'||(e->>'bills'),',' order by (e->>'hour')::int) from jsonb_array_elements(j->'rows') e)='9:1,11:1,12:1,14:1,16:1,19:1,20:0') from r;
with r as (select report_run('retail_wholesale',:'R') j)
select pg_temp.ck('T7b retail vs wholesale', (select string_agg(e->>'sale_type'||':'||(e->>'bills')||':'||(e->>'net'),',' order by e->>'sale_type') from jsonb_array_elements(j->'rows') e)='retail:5:2030,wholesale:1:2500') from r;
-- discounts
with r as (select report_run('discounts',:'R') j)
select pg_temp.ck('T8 discounts', (select string_agg(e->>'staff'||':'||(e->>'discount')||':'||(e->>'disc_bills')||':'||(e->>'override_lines'),',' order by e->>'staff') from jsonb_array_elements(j->'rows') e)='alice:100:1:0,bob:60:1:1') from r;
-- day close
with r as (select report_run('pos_day_close',:'R') j)
select pg_temp.ck('T9 day close', (select count(*) from jsonb_array_elements(j->'rows') e where e->>'day'='2026-09-08' and e->>'location_id'='1' and (e->>'cash_in')::numeric=300 and (e->>'expected_cash')::numeric=300 and e->>'bills'='1')=1
 and (select count(*) from jsonb_array_elements(j->'rows') e where e->>'day'='2026-09-12' and (e->>'cash_collections')::numeric=200 and (e->>'bills')='0')=1
 and (select count(*) from jsonb_array_elements(j->'rows') e where e->>'day'='2026-09-10' and e->>'location_id'='1' and (e->>'cash_in')::numeric=0 and e->>'void_bills'='1')=1
 and (j#>>'{totals,cash_in}')::numeric=450 and (j#>>'{totals,total_in}')::numeric=4150 and (j#>>'{totals,expected_cash}')::numeric=650) from r;
with r as (select report_run('voids',:'R') j) select pg_temp.ck('T10 voids', jsonb_array_length(j->'rows')=1 and j#>>'{rows,0,staff}'='alice' and j#>>'{rows,0,void_bills}'='1' and j#>>'{totals,void_amt}'='260') from r;
with r as (select report_run('voids',:'R','void_reason') j) select pg_temp.ck('T10b void reason', j#>>'{rows,0,void_reason}'='wrong') from r;
with r as (select report_run('quick_unlisted',:'R') j) select pg_temp.ck('T11 quick/unlisted', (select string_agg(e->>'line_kind'||':'||(e->>'net'),',' order by e->>'line_kind') from jsonb_array_elements(j->'rows') e)='quick:250.00,unlisted:200.00' and j#>>'{totals,lines}'='3') from r;
with r as (select report_run('payment_modes',:'R') j)
select pg_temp.ck('T12 payment modes', (select string_agg(e->>'mode'||':'||(e->>'amount')||':'||(e->>'collection_amount'),',' order by e->>'mode') from jsonb_array_elements(j->'rows') e)='card:200:0,cash:650:200,mobile:3300:0' and (j#>>'{totals,amount}')::numeric=4150) from r;
with r as (select report_run('wallet_recon',:'R') j)
select pg_temp.ck('T13 wallet recon', (select string_agg(e->>'wallet'||':'||(e->>'amount')||':'||(e->>'missing_ref'),',' order by e->>'wallet') from jsonb_array_elements(j->'rows') e)='bkash:2500:0,nagad:800:1') from r;
with r as (select report_run('collections',:'R') j) select pg_temp.ck('T14 collections', (j#>>'{totals,amount}')::numeric=200 and jsonb_array_length(j->'rows')=1) from r;
with r as (select report_run('best_customers',:'R') j) select pg_temp.ck('T15 best customers', j#>>'{rows,0,customer_name}'='Cust Two' and (j#>>'{rows,0,net}')::numeric=2500 and j#>>'{rows,0,mobile}'='01722222222' and jsonb_array_length(j->'rows')=3) from r;
-- dues
with r as (select report_run('customer_dues','{}') j) select pg_temp.ck('T16 dues', (select string_agg(e->>'name'||':'||(e->>'balance')||':'||(e->>'oldest_due')||':'||(e->>'days_old'),',' order by e->>'name') from jsonb_array_elements(j->'rows') e)='Cust One:280:2026-09-08:33,Cust Three:100:2026-09-13:28' and (j#>>'{totals,balance}')::numeric=380) from r;
-- must equal the existing customer_dues function
select pg_temp.ck('T16b matches customer_dues()', (select sum(balance) from customer_dues())=380);
with r as (select report_run('receivable_aging','{}') j) select pg_temp.ck('T17a aging no rule -> data needed', exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='data_needed' and n->>'what'='report_aging_buckets') and (j#>>'{totals,balance}')::numeric=380) from r;
with r as (select report_run('credit_limit_use','{}') j) select pg_temp.ck('T18a credit (no near rule)', (select string_agg(e->>'name'||':'||(e->>'status')||':'||coalesce(e->>'use_pct','n'),',' order by e->>'name') from jsonb_array_elements(j->'rows') e)='Cust One:ok:93.3,Cust Three:no_limit:n,Cust Two:ok:0.0' and exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'what'='report_near_limit_pct')) from r;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false) \g /dev/null
select set_rule('report_aging_buckets','"7,30,60"') \g /dev/null
select set_rule('report_near_limit_pct','90') \g /dev/null
with r as (select report_run('receivable_aging','{}') j) select pg_temp.ck('T17b aging buckets', (select string_agg(e->>'name'||':'||(e->>'bucket_1')||'/'||(e->>'bucket_2')||'/'||(e->>'bucket_3')||'/'||(e->>'bucket_4'),',' order by e->>'name') from jsonb_array_elements(j->'rows') e)='Cust One:0/0/280/0,Cust Three:0/100/0/0' and (j#>>'{totals,bucket_3}')::numeric=280 and jsonb_array_length(j->'columns')=9) from r;
with r as (select report_run('credit_limit_use','{}') j) select pg_temp.ck('T18b near', (select e->>'status' from jsonb_array_elements(j->'rows') e where e->>'name'='Cust One')='near' and j#>>'{totals,near_limit}'='1' and j#>>'{totals,no_limit_set}'='1') from r;
with r as (select report_run('item_sales',:'R') j) select pg_temp.ck('T4b bills per item exact (I-001:2, I-002:1, I-003:1, total 6)', (select string_agg(e->>'item_code'||':'||(e->>'bills'),',' order by e->>'item_code') from jsonb_array_elements(j->'rows') e where e->>'item_code' like 'I-%')='I-001:2,I-002:1,I-003:1' and j#>>'{totals,bills}'='6') from r;
with r as (select report_run('category_sales',:'R') j) select pg_temp.ck('T5b category bills distinct (sweet_kg 3 bills, none 3, total 6)', (select string_agg(e->>'category'||':'||(e->>'bills'),',' order by e->>'category') from jsonb_array_elements(j->'rows') e)='(none):3,sweet_kg:3' and j#>>'{totals,bills}'='6') from r;
with r as (select report_run('item_sales',:'R','location') j) select pg_temp.ck('T5c bills by location via line_no=1', (select string_agg(e->>'location_id'||':'||(e->>'bills'),',' order by e->>'location_id') from jsonb_array_elements(j->'rows') e)='1:3,3:3') from r;
