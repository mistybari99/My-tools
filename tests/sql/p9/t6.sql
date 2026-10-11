\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
set role authenticated;
select pg_temp.u(1) \g /dev/null
select set_rule('report_page_size','10') \g /dev/null
select j->'page', j->'has_more', jsonb_array_length(j->'rows'), j#>'{totals,net}', j->'notes' from (select report_run('item_sales','{"from":"2026-09-01","to":"2026-09-14"}','day,item',null,1) j) r;
select set_rule('report_page_size',null) \g /dev/null
select j->'rows'->0, j->'notes' from (select report_run('sales_summary','{"from":"2026-09-01","to":"2026-09-14"}','location,brand,staff','gp:desc') j) r;
