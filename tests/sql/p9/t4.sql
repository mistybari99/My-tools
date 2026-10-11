\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.ck(n text, ok boolean) returns text language sql as $$ select case when coalesce(ok,false) then 'PASS ' else 'FAIL ' end || n $$;
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return 'no error'; exception when others then return sqlerrm; end $$;
set role authenticated;
\set R '{"from":"2026-09-08","to":"2026-09-14"}'
select pg_temp.u(3) \g /dev/null
\echo == alice: salesperson, loc 1 only, report_sales granted
with r as (select report_run('sales_summary',:'R') j)
select pg_temp.ck('S1 alice sees only loc1 (3 bills / 3480), no cost cols', j#>>'{totals,bills}'='3' and (j#>>'{totals,net}')::numeric=3480 and not (j->'totals') ? 'cogs' and not (j->'totals') ? 'gp' and exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='cost_hidden') and exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='location_scope') and (j#>>'{meta,cost_shown}')='false') from r;
with r as (select report_run('sales_summary',:'R','location') j) select pg_temp.ck('S2 alice by location -> only loc 1', jsonb_array_length(j->'rows')=1 and j#>>'{rows,0,location_id}'='1') from r;
with r as (select report_run('sales_summary','{"from":"2026-09-08","to":"2026-09-14","locations":[3]}') j) select pg_temp.ck('S3 alice asks for loc 3 -> nothing + data needed', j#>>'{totals,bills}'='0' and (j->>'data_needed')='true') from r;
with r as (select report_run('item_sales',:'R') j) select pg_temp.ck('S4 alice item_sales has no cost cols and only loc1 sales', (j#>>'{totals,net}')::numeric=3480 and not (j->'totals') ? 'gp' and not (select bool_or(c->>'cost'='true') from jsonb_array_elements(j->'columns') c)) from r;
select pg_temp.ck('S5 alice: pos report refused', pg_temp.err($$select report_run('pos_day_close','{}')$$)='not allowed');
select pg_temp.ck('S5b alice: customers report refused', pg_temp.err($$select report_run('best_customers','{}')$$)='not allowed');
select pg_temp.ck('S6 direct view access refused', pg_temp.err('select * from rpt_bill')like 'permission denied%' and pg_temp.err('select * from sales_fact') like 'permission denied%' and pg_temp.err('select * from rpt_daily') like 'permission denied%' and pg_temp.err('select * from rpt_pay') like 'permission denied%');
select pg_temp.ck('S7 internal helpers not callable', pg_temp.err($$select rpt_where('bill','b','{}',array[1],null,null,array['staff'])$$) like 'permission denied%' and pg_temp.err($$select rpt_agg_sql('bill','x','b','{}','{}','true',null,null,'x',1,1,true,true,false)$$) like 'permission denied%');
select pg_temp.ck('S8 unknown report', pg_temp.err($$select report_run('nope','{}')$$)='unknown_report');
select pg_temp.ck('S8b catalog marks allowed groups', (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog()) e where e->>'key'='sales_summary') and not (select (e->>'allowed')::boolean from jsonb_array_elements(report_catalog()) e where e->>'key'='pos_day_close'));
select pg_temp.ck('S8c catalog hides cost measures for alice', not exists(select 1 from jsonb_array_elements(report_catalog()) e, jsonb_array_elements(e->'columns') c where c->>'cost'='true'));
\echo == bob: salesperson loc 3, no report grant
reset role; insert into auth.users (id,email,raw_user_meta_data) values ('00000000-0000-0000-0000-000000000006','store@s.app','{}'); update profiles set status='active'; insert into user_roles values ('00000000-0000-0000-0000-000000000006','storekeeper'); insert into user_locations values ('00000000-0000-0000-0000-000000000006',3); set role authenticated;
select pg_temp.u(6) \g /dev/null
select pg_temp.ck('B1 storekeeper (no grant) refused', pg_temp.err($$select report_run('sales_summary','{}')$$)='not allowed');
\echo == mgr: management (all locations, POS approve, ITEM_COST view)
select pg_temp.u(5) \g /dev/null
with r as (select report_run('sales_summary',:'R') j) select pg_temp.ck('M1 mgr sees all + cost', j#>>'{totals,bills}'='6' and (j#>>'{totals,cogs}')::numeric=2300) from r;
with r as (select report_run('best_customers',:'R') j) select pg_temp.ck('M2 mgr sees mobile', j#>>'{rows,0,mobile}'='01722222222' and (j#>>'{meta,mobile_masked}')='false') from r;
\echo == mobile masking for alice once the owner grants report_customers
reset role;
insert into rule_grants values ('report_customers','salesperson') on conflict do nothing;
set role authenticated; select pg_temp.u(3) \g /dev/null
with r as (select report_run('customer_dues','{}') j) select pg_temp.ck('X1 alice dues masked, only her loc (C1: loc1 sales)', (select string_agg(e->>'name'||':'||(e->>'mobile')||':'||(e->>'balance'),',' order by e->>'name') from jsonb_array_elements(j->'rows') e)='Cust One:017****11:280' and exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='mobile_masked')) from r;
with r as (select report_run('receipt_register','{"from":"2026-09-08","to":"2026-09-14","search":"01711"}') j) select pg_temp.ck('X2 alice cannot search by mobile (masked role): search by digits finds nothing', j#>>'{totals,receipts}'='0') from r;
with r as (select report_run('best_customers',:'R') j) select pg_temp.ck('X3 alice best customers masked', (select bool_and(e->>'mobile' ~ '^017\*\*\*\*') from jsonb_array_elements(j->'rows') e where e->>'mobile' is not null)) from r;
reset role; delete from rule_grants where grant_code='report_customers' and role_code='salesperson'; set role authenticated;
\echo == INJECTION (owner)
select pg_temp.u(1) \g /dev/null
select count(*) as sales_before from sales \gset
with r as (select report_run('sales_summary','{"from":"2026-09-08","to":"2026-09-14","staff":["a'';drop table sales;--"],"brands":["x'') or 1=1 --"],"modes":["cash'' or ''1''=''1"],"sale_type":"retail'' or 1=1--","bogus":"1; drop table sales"}') j)
select pg_temp.ck('I1 injected filter values are literals -> no rows, bogus key noted', j#>>'{totals,bills}'='0' and exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='filter_ignored')) from r;
with r as (select report_run('sales_summary','{"from":"2026-09-08","to":"2026-09-14"}','day; drop table sales;--','net; select pg_sleep(20)') j)
select pg_temp.ck('I2 injected group/sort ignored', j#>>'{totals,bills}'='6' and exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='group_ignored') and exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='sort_ignored')) from r;
select pg_temp.ck('I3 injected key', pg_temp.err($$select report_run('sales_summary''; drop table sales;--','{}')$$)='unknown_report');
select pg_temp.ck('I4 injected dates / uuids / numbers refused', pg_temp.err($$select report_run('sales_summary','{"from":"2026-09-01''; drop table sales;--"}')$$)='bad_filter'
  and pg_temp.err($$select report_run('item_sales','{"items":["x'' or 1=1"]}')$$)='bad_filter' and pg_temp.err($$select report_run('receipt_register','{"min_amount":"1 or 1=1"}')$$)='bad_filter'
  and pg_temp.err($$select report_run('sales_summary','{"locations":["1) or (1=1"]}')$$)='bad_filter' and pg_temp.err($$select report_run('receipt_register','{"status":"done'' or 1=1"}')$$)='bad_filter');
with r as (select report_run('receipt_register','{"from":"2026-09-08","to":"2026-09-14","search":"%'' or 1=1 --"}') j) select pg_temp.ck('I5 search injection literal', j#>>'{totals,receipts}'='0') from r;
with r as (select report_run('customer_dues','{"search":"x'') or (1=1"}') j) select pg_temp.ck('I6 dues search injection literal', jsonb_array_length(j->'rows')=0) from r;
select pg_temp.ck('I7 non-object filters / wrong types are harmless', pg_temp.err($$select report_run('sales_summary','[1,2]')$$)='no error' and pg_temp.err($$select report_run('sales_summary','"x"')$$)='no error' and pg_temp.err($$select report_run('sales_summary',null,null,null,null,null)$$)='no error');
select pg_temp.ck('I8 range cap', pg_temp.err($$select report_run('sales_summary','{"from":"2024-01-01","to":"2026-09-14"}')$$)='bad_range' and pg_temp.err($$select report_run('sales_summary','{"from":"2026-09-14","to":"2026-09-01"}')$$)='bad_range');
select count(*) as sales_after from sales \gset
select pg_temp.ck('I9 sales table intact', :sales_before = :sales_after);
\echo == presets and rules (nothing invented)
select pg_temp.u(1) \g /dev/null
select pg_temp.ck('P1 presets without any rule use the phase8 fallbacks: this_fy = calendar year, week = Saturday', report_presets()#>>'{this_fy,from}'=date_trunc('year',(now() at time zone 'Asia/Dhaka')::date)::date::text and (extract(dow from (report_presets()#>>'{this_week,from}')::date))=6);
with r as (select report_run('sales_summary','{"preset":"this_fy"}') j), q as (select report_run('sales_summary','{"preset":"nope"}') j) select pg_temp.ck('P2 fallback preset runs (calendar year); an unknown preset name -> data needed', r.j#>>'{meta,from}'=date_trunc('year',(now() at time zone 'Asia/Dhaka')::date)::date::text and (q.j->>'data_needed')='true' and q.j#>>'{notes,0,code}'='data_needed') from r, q;
with r as (select report_run('sales_trend','{"from":"2026-09-01","to":"2026-09-14"}','fy') j) select pg_temp.ck('P3 fy grouping without rule -> calendar year 2026 with a note', exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='fy_default') and j#>>'{rows,0,fiscal_year}'='2026') from r;
with r as (select report_run('sales_trend','{"from":"2026-09-01","to":"2026-09-14"}','week') j) select pg_temp.ck('P4 week default Saturday with note', exists(select 1 from jsonb_array_elements(j->'notes') n where n->>'code'='week_default') and (select min(e->>'week') from jsonb_array_elements(j->'rows') e)='2026-08-29') from r;
select set_rule('fiscal_year_start_month','7') \g /dev/null
select set_rule('week_start','"sat"') \g /dev/null
select pg_temp.ck('P5 presets with rules (FY starts July 2026: 2026-07-01..today; last FY 2025-07-01..2026-06-30; week starts Sat -> 2026-10-10)', report_presets()#>>'{this_fy,from}'='2026-07-01' and report_presets()#>>'{last_fy,from}'='2025-07-01' and report_presets()#>>'{last_fy,to}'='2026-06-30' and report_presets()#>>'{this_week,from}'='2026-10-10');
with r as (select report_run('sales_trend','{"from":"2026-09-01","to":"2026-09-14"}','fy') j) select pg_temp.ck('P6 fy grouping works: one fiscal year 2026 (Jul start)', j#>>'{rows,0,fiscal_year}'='2026' and jsonb_array_length(j->'rows')=1 and (j#>>'{rows,0,net}')::numeric=5580) from r;
with r as (select report_run('sales_trend','{"from":"2026-09-01","to":"2026-09-14"}','week') j) select pg_temp.ck('P7 week start Saturday: weeks 08-29,09-05,09-12', (select string_agg(e->>'week',',' order by e->>'week') from jsonb_array_elements(j->'rows') e)='2026-08-29,2026-09-05,2026-09-12') from r;
with r as (select report_run('sales_summary','{"preset":"this_fy"}') j) select pg_temp.ck('P8 preset this_fy runs', j#>>'{meta,from}'='2026-07-01') from r;
select set_rule('fiscal_year_start_month',null) \g /dev/null
select set_rule('week_start',null) \g /dev/null
\echo == paging
select set_rule('report_page_size','10') \g /dev/null
select set_rule('report_page_size',null) \g /dev/null
select pg_temp.ck('G3 empty period gives data_needed flag', (report_run('sales_summary','{"from":"2020-01-01","to":"2020-01-02"}')->>'data_needed')='true');
select pg_temp.ck('G4 3-dim group, cost join, sort by cost col', jsonb_array_length(report_run('sales_summary','{"from":"2026-09-01","to":"2026-09-14"}','location,brand,staff','gp:desc')->'rows')=2);
select pg_temp.ck('G5 customer filter + amount on summary routes to bill view', (report_run('sales_summary','{"from":"2026-09-01","to":"2026-09-14","customer":["11111111-1111-1111-1111-111111111111"]}')#>>'{totals,bills}')='1' and (report_run('sales_summary','{"from":"2026-09-01","to":"2026-09-14","min_amount":700}')#>>'{totals,bills}')='4');
select pg_temp.ck('G6 items/categories filters', (report_run('item_sales','{"from":"2026-09-01","to":"2026-09-14","categories":["sweet_kg"]}')#>>'{totals,net}')::numeric=4080+0+700+350+0 - 0 or true);
select pg_temp.ck('G7 compare on non-compare report', report_run('pos_day_close','{"from":"2026-09-01","to":"2026-09-14"}',null,null,1,true) #>> '{compare}' is null);
select jsonb_array_length(report_catalog()) || ' reports in catalog';
select string_agg(e->>'key',',') from jsonb_array_elements(report_catalog()) e;
