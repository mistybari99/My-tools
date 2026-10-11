\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
create function pg_temp.err(q text) returns text language plpgsql as $$ begin execute q; return 'no error'; exception when others then return sqlerrm; end $$;
set role authenticated;
select pg_temp.u(3) \g /dev/null
select report_run('sales_summary','{"from":"2026-09-08","to":"2026-09-14","locations":[3]}') - 'columns';
select pg_temp.u(4) \g /dev/null
select pg_temp.err($$select report_run('sales_summary','{}')$$);
select pg_temp.u(3) \g /dev/null
select report_run('customer_dues','{}')->'rows';
select pg_temp.u(1) \g /dev/null
select report_run('sales_summary','{"from":"2026-09-08","to":"2026-09-14","staff":["a'';drop table sales;--"],"brands":["x'') or 1=1 --"],"modes":["cash'' or ''1''=''1"],"sale_type":"retail'' or 1=1--","bogus":"1; drop table sales"}') - 'columns';
select pg_temp.err($$select report_run('sales_summary','{"from":"2026-09-08","to":"2026-09-14"}','day',null,1)$$);
select pg_temp.err($$select report_run('sales_summary','{"from":"2020-01-01","to":"2020-01-02"}')$$);
select pg_temp.err($$select report_run('sales_summary','{"from":"2026-09-01","to":"2026-09-14"}','location,brand,staff','gp:desc')$$);
