\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.ck(n text, ok boolean) returns text language sql as $$ select case when coalesce(ok,false) then 'PASS ' else 'FAIL ' end || n $$;
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return 'no error'; exception when others then return sqlerrm; end $$;
\echo == (1) half-cent percent discount (phase8)
reset role;
insert into serials(form_code,location_id,last) values ('POS',1,500) on conflict (form_code,location_id) do update set last=500;
set role authenticated; select pg_temp.u(1) \g /dev/null
select pg_temp.ck('H1 percent 5% of 100.50 (server 5.03, phone showed 5.02), paid 95.48: no overpaid error, discount 5.02',
  (record_sale2(gen_random_uuid(),1,'[{"amount":100.50}]',5.02,'[{"mode":"cash","amount":95.48}]',null,null,'retail',null,true,null,'percent',5)->>'discount')::numeric=5.02);
select pg_temp.ck('H2 phone value 0.02 away is NOT trusted: server amount 5.03 -> paying the phone total 95.49 is overpaid',
  pg_temp.err($$select record_sale2(gen_random_uuid(),1,'[{"amount":100.50}]',5.01,'[{"mode":"cash","amount":95.49}]',null,null,'retail',null,true,null,'percent',5)$$)='overpaid');
select pg_temp.ck('H3 percent without p_discount still computed by the server (5.03)',
  (record_sale2(gen_random_uuid(),1,'[{"amount":100.50}]',null,'[{"mode":"cash","amount":95.47}]',null,null,'retail',null,true,null,'percent',5)->>'discount')::numeric=5.03);
select pg_temp.ck('H4 p_discount above the subtotal is never trusted',
  pg_temp.err($$select record_sale2(gen_random_uuid(),1,'[{"amount":0.00}]',0.01,'[]',null,null,'retail',null,true,null,'percent',100)$$) <> 'no error');
select pg_temp.ck('H5 amount discount unchanged',
  (record_sale2(gen_random_uuid(),1,'[{"amount":200}]',20,'[{"mode":"cash","amount":180}]',null,null,'retail',null,true)->>'discount')::numeric=20);

\echo == (2) personal / role / emergency grants open report_run (storekeeper user 6, loc 3, no report grant at the start)
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G0 storekeeper starts closed', pg_temp.err($$select report_run('sales_summary','{}')$$)='not allowed');
select pg_temp.u(1) \g /dev/null
select set_user_grant('00000000-0000-0000-0000-000000000006','report_sales');
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G1 PERSONAL grant report_sales opens sales reports, not pos', pg_temp.err($$select report_run('sales_summary','{}')$$)='no error' and pg_temp.err($$select report_run('voids','{}')$$)='not allowed');
select pg_temp.ck('G1b catalog says allowed for sales, not for pos', (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog()) e where e->>'key'='sales_summary') and not (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog()) e where e->>'key'='voids'));
select pg_temp.u(1) \g /dev/null
select set_user_grant('00000000-0000-0000-0000-000000000006','report_sales',null,null,false);
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G1c personal grant removed -> closed again', pg_temp.err($$select report_run('sales_summary','{}')$$)='not allowed');
select pg_temp.u(1) \g /dev/null
select set_grant('report_cash','storekeeper',true);
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G2 ROLE grant report_cash opens payment reports', pg_temp.err($$select report_run('payment_modes','{}')$$)='no error');
select pg_temp.u(1) \g /dev/null
select set_grant('report_cash','storekeeper',false);
select set_user_grant('00000000-0000-0000-0000-000000000006','view_reports');
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G3 grant view_reports opens EVERY report group', pg_temp.err($$select report_run('sales_summary','{}')$$)='no error' and pg_temp.err($$select report_run('voids','{}')$$)='no error'
  and pg_temp.err($$select report_run('payment_modes','{}')$$)='no error' and pg_temp.err($$select report_run('best_customers','{}')$$)='no error' and biz_ok());
select pg_temp.ck('G3b ...but not the cost columns', (report_run('item_sales','{}')#>>'{meta,cost_shown}')='false');
select pg_temp.u(1) \g /dev/null
select set_user_grant('00000000-0000-0000-0000-000000000006','view_reports',null,null,false);
select set_user_grant('00000000-0000-0000-0000-000000000006','view_cost');
select pg_temp.u(6) \g /dev/null
select pg_temp.u(1) \g /dev/null
select set_user_grant('00000000-0000-0000-0000-000000000006','view_cost',null,null,false);
select set_user_grant('00000000-0000-0000-0000-000000000006','view_profit');
select set_user_grant('00000000-0000-0000-0000-000000000006','report_sales');
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G4b personal view_profit + report_sales -> cost columns shown', (report_run('item_sales','{}')#>>'{meta,cost_shown}')='true');
select pg_temp.u(1) \g /dev/null
select set_user_grant('00000000-0000-0000-0000-000000000006','view_profit',null,null,false);
select set_user_grant('00000000-0000-0000-0000-000000000006','report_sales',null,null,false);
-- emergency window
select set_rule('em_view_reports','true');
select pg_temp.u(6) \g /dev/null
select request_emergency('view_reports',3,'{}','need the sales report now') as er \gset
select pg_temp.ck('G5 pending emergency request opens nothing', pg_temp.err($$select report_run('sales_summary','{}')$$)='not allowed');
select pg_temp.u(1) \g /dev/null
select decide_emergency(:er,true,null);
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G5b approved EMERGENCY window opens the reports', pg_temp.err($$select report_run('sales_summary','{}')$$)='no error' and pg_temp.err($$select report_run('voids','{}')$$)='no error');
reset role; update emergency_requests set valid_until = now() - interval '1 minute' where id=:er; set role authenticated; select pg_temp.u(6) \g /dev/null
select pg_temp.ck('G5c expired window closes again', pg_temp.err($$select report_run('sales_summary','{}')$$)='not allowed');
select pg_temp.u(1) \g /dev/null
select set_rule('em_view_reports',null);

\echo == (5) settings: week_start / fiscal year come from the phase8 rules
select set_rule('week_start','"mon"');
select pg_temp.ck('W1 week_start=mon -> this_week starts on a Monday, last_week is the 7 days before', extract(dow from (report_presets()#>>'{this_week,from}')::date)=1 and (report_presets()#>>'{last_week,from}')::date=(report_presets()#>>'{this_week,from}')::date-7 and (report_presets()#>>'{last_week,to}')::date=(report_presets()#>>'{this_week,from}')::date-1);
with r as (select report_run('sales_trend','{"from":"2026-09-01","to":"2026-09-14"}','week') j) select pg_temp.ck('W2 weekly grouping on Mondays 08-31, 09-07, and no fallback note', (select string_agg(e->>'week',',' order by e->>'week') from jsonb_array_elements(j->'rows') e)='2026-08-31,2026-09-07' and not exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='week_default')) from r;
select set_rule('week_start','"sun"');
select pg_temp.ck('W3 week_start=sun -> Sunday', extract(dow from (report_presets()#>>'{this_week,from}')::date)=0);
select set_rule('week_start',null);
reset role; insert into rules(key,module,kind,value,min_value,max_value,label_bn) values ('week_start_dow','reports','number','2',0,6,'x'); set role authenticated; select pg_temp.u(1) \g /dev/null
select pg_temp.ck('W4 old rule week_start_dow is a fallback only while week_start is empty (2 = Tuesday)', extract(dow from (report_presets()#>>'{this_week,from}')::date)=2);
select set_rule('week_start','"fri"');
select pg_temp.ck('W5 ...and week_start wins over it', extract(dow from (report_presets()#>>'{this_week,from}')::date)=5);
select set_rule('week_start',null);
reset role; delete from rules where key='week_start_dow'; set role authenticated; select pg_temp.u(1) \g /dev/null
select set_rule('fiscal_year_start_month','9'); select set_rule('fiscal_year_start_day','10');
select pg_temp.ck('Y1 fiscal start 10 September: this_fy from = last 10 September, last_fy is the year before', (report_presets()#>>'{this_fy,from}')::date = (case when (now() at time zone 'Asia/Dhaka')::date >= make_date(extract(year from now())::int,9,10) then make_date(extract(year from now())::int,9,10) else make_date(extract(year from now())::int-1,9,10) end)
  and (report_presets()#>>'{last_fy,to}')::date=(report_presets()#>>'{this_fy,from}')::date-1 and (report_presets()#>>'{last_fy,from}')::date=(report_presets()#>>'{this_fy,from}')::date - interval '1 year');
with r as (select report_run('sales_trend','{"from":"2026-09-01","to":"2026-09-14"}','day,fy') j) select pg_temp.ck('Y2 fiscal grouping honours the DAY: sales on 09-03 (before the 10th) are FY 2025, on 09-13 FY 2026', (select e->>'fiscal_year' from jsonb_array_elements(j->'rows') e where e->>'day'='2026-09-03')='2025' and (select e->>'fiscal_year' from jsonb_array_elements(j->'rows') e where e->>'day'='2026-09-13')='2026') from r;
select set_rule('fiscal_year_start_month',null); select set_rule('fiscal_year_start_day',null);
reset role;
select pg_temp.ck('Y4 rpt_fy_start(2026-04-14,415)=2025-04-15, (2026-04-15,415)=2026-04-15, (2026-03-01,230)->2026-02-28 / 2025-02-28', rpt_fy_start('2026-04-14',415)='2025-04-15' and rpt_fy_start('2026-04-15',415)='2026-04-15' and rpt_fy_start('2026-03-01',230)='2026-02-28' and rpt_fy_start('2026-02-10',230)='2025-02-28');
select pg_temp.ck('Y5 the old draft rule week_start_dow no longer exists after phase9', not exists(select 1 from rules where key='week_start_dow'));
select pg_temp.ck('Y6 settings rows are the phase8 ones (module settings, once)', (select count(*) from rules where key in ('week_start','fiscal_year_start_month','fiscal_year_start_day') and module='settings')=3);

\echo == (4) discount buckets none / amount / percent
set role authenticated; select pg_temp.u(1) \g /dev/null
with r as (select report_run('discounts','{"from":"2026-09-01","to":"2026-12-31"}','discount_kind') j)
select pg_temp.ck('D1 buckets: none (no discount), amount (incl. pre-phase8 sales), percent; no n/a', (select string_agg(e->>'discount_kind',',' order by e->>'discount_kind') from jsonb_array_elements(j->'rows') e)='amount,none,percent') from r;
with r as (select report_run('discounts','{"from":"2026-10-01","to":"2026-12-31"}','discount_kind') j)
select pg_temp.ck('D2 new sales: percent = 2 discounted bills / 10.05 (5.02 + 5.03); amount = 1 bill / 20', (select (e->>'disc_bills')||'/'||(e->>'discount') from jsonb_array_elements(j->'rows') e where e->>'discount_kind'='percent')='2/10.05' and (select (e->>'disc_bills')||'/'||(e->>'discount') from jsonb_array_elements(j->'rows') e where e->>'discount_kind'='amount')='1/20.00') from r;
reset role;
select pg_temp.ck('D3 pct stored: rpt_bill.discount_pct = 5 for the percent sales, null for amount/none', (select count(*) from rpt_bill where discount_kind='percent' and discount_pct=5)=2 and (select count(*) from rpt_bill where discount_kind in ('amount','none') and discount_pct is not null)=0);
select pg_temp.ck('D4 item_sales facts show the same buckets', (select count(distinct discount_kind) from sales_fact where discount_kind is not null)=3);
set role authenticated; select pg_temp.u(1) \g /dev/null

\echo == (7) fact gap note, (8) page clamp
reset role; create temp table gap as select sale_id from sales_fact_t where status='done' and day>='2026-09-08' limit 1; delete from sales_fact_t where sale_id=(select sale_id from gap);
set role authenticated; select pg_temp.u(1) \g /dev/null
with r as (select report_run('item_sales','{"from":"2026-09-01","to":"2026-12-31"}') j) select pg_temp.ck('N1 missing fact rows -> note fact_gap with sales vs facts counts', exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='fact_gap' and (n->>'sales')::int=(n->>'facts')::int+1)) from r;
with r as (select report_run('sales_summary','{"from":"2026-09-01","to":"2026-12-31"}') j) select pg_temp.ck('N2 bill reports (no facts) have no fact_gap note', not exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='fact_gap')) from r;
select report_fact_rebuild() \g /dev/null
with r as (select report_run('item_sales','{"from":"2026-09-01","to":"2026-12-31"}') j) select pg_temp.ck('N3 after report_fact_rebuild the note is gone', not exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='fact_gap')) from r;
select pg_temp.ck('N4 huge / negative / null page numbers do not overflow', pg_temp.err($$select report_run('sales_summary','{}','day',null,2147483647)$$)='no error' and pg_temp.err($$select report_run('sales_summary','{}','day',null,-5)$$)='no error' and pg_temp.err($$select report_run('sales_summary','{}','day',null,null)$$)='no error');
select pg_temp.ck('N5 page is clamped to 1000', (report_run('sales_summary','{}','day',null,2147483647)#>>'{page,n}')::int=1000);

\echo == (9) log_report_export
reset role; select count(*) as a0 from audit_log where action='export' \gset
set role authenticated; select pg_temp.u(1) \g /dev/null
select log_report_export('sales_summary','csv','{"from":"2026-09-01"}',42);
reset role;
select pg_temp.ck('L1 owner export logged (user, report, kind, rows, filters)', (select count(*) from audit_log where action='export')=:a0+1 and exists(select 1 from audit_log where action='export' and table_name='report' and record_id='sales_summary' and detail->>'kind'='csv' and (detail->>'rows')::int=42 and detail#>>'{filters,from}'='2026-09-01' and user_id='00000000-0000-0000-0000-000000000001'));
set role authenticated; select pg_temp.u(6) \g /dev/null
select pg_temp.ck('L2 no export_data -> not allowed', pg_temp.err($$select log_report_export('sales_summary','csv','{}',1)$$)='not allowed');
select pg_temp.u(1) \g /dev/null
select set_user_grant('00000000-0000-0000-0000-000000000006','export_data');
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('L3 personal export_data -> allowed', pg_temp.err($$select log_report_export('voids','print','{}',3)$$)='no error');
select pg_temp.ck('L4 bad report / bad kind refused', pg_temp.err($$select log_report_export('nope','csv','{}',1)$$)='unknown_report' and pg_temp.err($$select log_report_export('voids','c;s v','{}',1)$$)='bad_kind');
select pg_temp.u(1) \g /dev/null
select set_user_grant('00000000-0000-0000-0000-000000000006','export_data',null,null,false);
set role anon;
select pg_temp.ck('L5 anon cannot call it', pg_temp.err($$select log_report_export('voids','csv','{}',1)$$) like 'permission denied%');
reset role;

\echo == (11) helpers have a search_path, internals are closed
select pg_temp.ck('S1 every rpt_* function has search_path set', (select count(*) from pg_proc p where p.pronamespace='public'::regnamespace and p.proname like 'rpt\_%' and not exists (select 1 from unnest(coalesce(p.proconfig,'{}')) c where c like 'search_path=%'))=0);
set role authenticated;
select pg_temp.ck('S2 authenticated cannot call rpt_grant / rpt_fy_start / rpt_week_cfg / rpt_views_refresh', pg_temp.err($$select rpt_grant('x')$$) like 'permission denied%' and pg_temp.err($$select rpt_fy_start(now()::date,101)$$) like 'permission denied%' and pg_temp.err($$select rpt_week_cfg()$$) like 'permission denied%' and pg_temp.err($$select rpt_views_refresh()$$) like 'permission denied%');
select pg_temp.ck('S3 views still closed to the app after refresh', pg_temp.err('select * from rpt_bill') like 'permission denied%' and pg_temp.err('select * from sales_fact') like 'permission denied%');
reset role;
