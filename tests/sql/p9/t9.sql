\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return 'no error'; exception when others then return sqlerrm; end $$;
set role anon;
select 'anon run: '||pg_temp.err($$select report_run('sales_summary','{}')$$);
select 'anon catalog: '||pg_temp.err($$select report_catalog()$$);
select 'anon presets: '||pg_temp.err($$select report_presets()$$);
select 'anon view: '||pg_temp.err($$select count(*) from rpt_daily$$);
select 'anon fact table: '||pg_temp.err($$select count(*) from sales_fact_t$$);
select 'anon rebuild: '||pg_temp.err($$select report_fact_rebuild()$$);
reset role; set role authenticated;
select 'authenticated fact table: '||pg_temp.err($$select count(*) from sales_fact_t$$);
select 'authenticated rpt_fact_load: '||pg_temp.err($$select rpt_fact_load(null)$$);
select 'authenticated no session user: '||pg_temp.err($$select report_run('sales_summary','{}')$$);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false) \g /dev/null
\timing on
select 'timeout test (top-level)', length(report_run('sales_summary','{"from":"2026-01-01","to":"2026-12-31"}','day,location,staff',null,1,true)::text);
