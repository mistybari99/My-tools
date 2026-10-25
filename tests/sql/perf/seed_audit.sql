\timing on
-- ~2.0M audit rows over 3 years: mix like production (sales/payments dominate, a few rare tables)
insert into audit_log (at, user_id, staff_id, action, table_name, record_id, detail)
select now() - ((g % 1095) || ' days')::interval - ((g::bigint*7919 % 86400) || ' seconds')::interval,
       '00000000-0000-0000-0000-0000000000a2', 'SEL1',
       case when t.r < 0.02 then 'view' when t.r < 0.18 then 'update' else 'insert' end,
       case when t.r < 0.40 then 'sales' when t.r < 0.62 then 'sale_payments' when t.r < 0.80 then 'purchase_lines' when t.r < 0.90 then 'stock_balance'
            when t.r < 0.94 then 'production_runs' when t.r < 0.97 then 'items' when t.r < 0.985 then 'customers' when t.r < 0.995 then 'inbound_messages' else 'locations' end,
       md5(g::text)::uuid::text,
       jsonb_build_object('new', jsonb_build_object('id', md5(g::text), 'note', repeat('x', 200 + g % 200), 'total', g % 5000, 'status', 'done', 'lines', 3))
from generate_series(1,2000000) g cross join lateral (select ((hashtext(g::text) & 2147483647)::numeric / 2147483647) r) t;
analyze audit_log;
select pg_size_pretty(pg_total_relation_size('audit_log')) sz, count(*) from audit_log;
