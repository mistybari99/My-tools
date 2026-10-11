\pset pager off
\pset tuples_only on
\pset format unaligned
create function pg_temp.u(n int) returns text language sql as $$ select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000'||n,false) $$;
create function pg_temp.t(label text, q text) returns text language plpgsql as $$ declare s timestamptz := clock_timestamp(); r jsonb; begin execute q into r; return label||' '||round(extract(epoch from clock_timestamp()-s)::numeric,2)||'s rows='||coalesce(jsonb_array_length(r->'rows'),0)||' groups='||coalesce(r#>>'{page,groups}','-')||' more='||coalesce(r->>'has_more','-'); exception when others then return label||' ERR '||sqlerrm||' '||round(extract(epoch from clock_timestamp()-s)::numeric,2)||'s'; end $$;
set role authenticated;
select pg_temp.u(1) \g /dev/null
\set Y '''{"from":"2026-01-01","to":"2026-12-31"}'''
select pg_temp.t('summary year', $$select report_run('sales_summary','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('summary year compare', $$select report_run('sales_summary','{"from":"2026-01-01","to":"2026-12-31"}',null,null,1,true)$$);
select pg_temp.t('trend day year', $$select report_run('sales_trend','{"from":"2026-01-01","to":"2026-12-31"}','day')$$);
select pg_temp.t('trend day+loc cmp', $$select report_run('sales_trend','{"from":"2026-01-01","to":"2026-12-31"}','day,location',null,1,true)$$);
select pg_temp.t('combined year', $$select report_run('sales_combined','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('item year', $$select report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('item year cmp day', $$select report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','item,month',null,1,true)$$);
select pg_temp.t('category year', $$select report_run('category_sales','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('register year', $$select report_run('receipt_register','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('register page 10', $$select report_run('receipt_register','{"from":"2026-01-01","to":"2026-12-31"}',null,null,10)$$);
select pg_temp.t('hour', $$select report_run('hour_weekday','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('discounts year (bill view)', $$select report_run('discounts','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('day close year', $$select report_run('pos_day_close','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('voids', $$select report_run('voids','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('quick', $$select report_run('quick_unlisted','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('payment modes', $$select report_run('payment_modes','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('best customers', $$select report_run('best_customers','{"from":"2026-01-01","to":"2026-12-31"}')$$);
select pg_temp.t('dues', $$select report_run('customer_dues','{}')$$);
select pg_temp.t('credit', $$select report_run('credit_limit_use','{}')$$);
select pg_temp.t('cap: item,day (items x 365)', $$select report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','day,item',null,2)$$);
select pg_temp.t('cap: page 10 of 500 (last page)', $$select report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','day,item',null,10)$$);
select pg_temp.t('cap: page 11 beyond cap', $$select report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','day,item',null,11)$$);
select pg_temp.t('summary by day,location,staff (cap)', $$select report_run('sales_summary','{"from":"2026-01-01","to":"2026-12-31"}','day,location,staff')$$);
select jsonb_path_query_array(report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','day,item',null,11),'$.notes[*].code');
select jsonb_path_query_array(report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','day,item',null,1),'$.notes[*].code') , (report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','day,item',null,1)#>>'{page,groups}');
select jsonb_array_length(report_run('item_sales','{"from":"2026-01-01","to":"2026-12-31"}','day,item',null,10)->'rows');
