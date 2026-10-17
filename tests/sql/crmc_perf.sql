-- CRM-C performance check on synthetic data (test_* names). Run on a throwaway database through phase 308 (no fixture needed):
--   psql -h /tmp -p 5573 -U postgres -d <db> -qAt -f tests/sql/crmc_perf.sql
-- Creates 5000 customers and 40000 sales over 18 months (two outlets, two items, about 8 percent of the sales without a customer), then times: the first score refresh in batches,
-- the incremental refresh, previews of the main rule kinds, a page of members, the overview and the profit view; EXPLAIN ANALYZE of the two heavy statements is printed.
\set ON_ERROR_STOP on
\timing on
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000c3901', 'test_owner_perf@s.app', '{"full_name":"test_owner_perf"}') on conflict do nothing;
update profiles set status = 'active' where id = '00000000-0000-0000-0000-0000000c3901';
insert into user_roles values ('00000000-0000-0000-0000-0000000c3901', 'owner') on conflict do nothing;
insert into items (id, code, name_bn, name_en, unit, sell_price) values ('aaaaaaaa-0000-0000-0000-0000000000a1', 'test_it_a', 'test item a', 'test item a', 'piece', 50), ('aaaaaaaa-0000-0000-0000-0000000000a2', 'test_it_b', 'test item b', 'test item b', 'piece', 100) on conflict do nothing;
insert into customers (mobile, name, birthday, source) select '0155' || lpad(g::text, 7, '0'), 'test_perf_' || g, case when g % 3 = 0 then date '1990-01-01' + (g % 365) end, case when g % 5 = 0 then 'facebook' end from generate_series(1, 5000) g;
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, customer_id, status, created_by, paid)
select 1 + (g % 2), 100000 + g, (now() at time zone 'Asia/Dhaka')::date - (g * 7919 % 540), now() - make_interval(days => (g * 7919 % 540)),
       jsonb_build_array(jsonb_build_object('item_id', case when g % 2 = 0 then 'aaaaaaaa-0000-0000-0000-0000000000a1' else 'aaaaaaaa-0000-0000-0000-0000000000a2' end, 'name', 'test item', 'qty', 1 + g % 3, 'amount', 50 + (g % 7) * 10)),
       50 + (g % 7) * 10, 50 + (g % 7) * 10, 'cash', case when g % 12 = 0 then null else (select id from customers where mobile = '0155' || lpad((1 + (g * 31 % 5000))::text, 7, '0')) end, 'done', '00000000-0000-0000-0000-0000000c3901', 50 + (g % 7) * 10
  from generate_series(1, 40000) g;
analyze customers; analyze sales;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000c3901', false);
select 'customers', count(*) from customers; select 'sales', count(*) from sales;
\echo == first refresh in batches of 2000 (the technical batch size)
select crmc_metrics_refresh(false);
select crmc_metrics_refresh(false);
select crmc_metrics_refresh(false);
select crmc_metrics_refresh(false);
\echo == incremental: nothing is stale; then 200 new sales make 200 customers stale
select crmc_metrics_refresh(true);
insert into sales (location_id, receipt, sale_date, sold_at, lines, subtotal, total, pay_mode, customer_id, status, created_by, paid)
select 1, 500000 + g, (now() at time zone 'Asia/Dhaka')::date, now(), '[]', 10, 10, 'cash', (select id from customers where mobile = '0155' || lpad(g::text, 7, '0')), 'done', '00000000-0000-0000-0000-0000000c3901', 10 from generate_series(1, 200) g;
select crmc_metrics_refresh(false);
select set_rule('crm_segments_on', 'true'::jsonb);
\echo == previews
select crmc_preview('{"conditions":[{"field":"days_since_last","op":"gt","value":60}]}') ->> 'count' as lapsed;
select crmc_preview('{"conditions":[{"field":"days_since_last","op":"gt","value":60},{"field":"spend_12m","op":"ge","value":200},{"field":"tier","op":"in","value":["walkin"]}]}') ->> 'count' as three_conditions;
select crmc_preview('{"conditions":[{"field":"birthday_in_days","op":"le","value":30}]}') ->> 'count' as birthday_30;
select crmc_preview('{"conditions":[{"field":"rfm_label","op":"in","value":["Champion","At-risk"]}]}') ->> 'count' as labels;
select crmc_preview('{"conditions":[{"field":"outlet","op":"in","value":[2]},{"field":"orders_12m","op":"ge","value":2}]}') ->> 'count' as outlet2;
select crmc_preview('{"conditions":[{"field":"bought_item","op":"in","value":["aaaaaaaa-0000-0000-0000-0000000000a1"],"within_days":90}]}') ->> 'count' as item_90d;
select crmc_preview('{"conditions":[{"field":"not_bought_item","op":"in","value":["aaaaaaaa-0000-0000-0000-0000000000a1"]}]}') ->> 'count' as never_item;
select crmc_preview('{"conditions":[{"field":"has_due","op":"is","value":true}]}') ->> 'count' as owing;
select crmc_preview('{"conditions":[{"field":"opted_in","op":"is","value":false}]}') ->> 'count' as not_agreed;
\echo == a page of members, the overview, the RFM summary, the lapsed list, the profit view (180 days), one export of the lapsed list is not timed (limit blank)
select jsonb_array_length(crmc_members('{"conditions":[{"field":"days_since_last","op":"gt","value":60}]}', null, 50, 0) -> 'rows');
select crmc_overview() ->> 'repeat_rate_pct';
select crmc_rfm_summary() ->> 'customers_scored';
select crmc_lapsed(60) ->> 'total';
select crmc_profit((now() at time zone 'Asia/Dhaka')::date - 180, (now() at time zone 'Asia/Dhaka')::date) ->> 'customers';
\echo == EXPLAIN of the heavy statements
explain (analyze, buffers, costs off, summary on)
select count(*) from public._crmc_stale(2000);
explain (analyze, buffers, costs off, summary on)
select coalesce(array_agg(distinct s.customer_id), '{}') from public.sales s
 where s.status = 'done' and s.customer_id is not null and s.sale_date > (now() at time zone 'Asia/Dhaka')::date - 90
   and exists (select 1 from unnest(array['aaaaaaaa-0000-0000-0000-0000000000a1']) it where s.lines @> jsonb_build_array(jsonb_build_object('item_id', it)));
explain (analyze, buffers, costs off, summary on)
select coalesce(array_agg(c.id), '{}') from public.customers c left join public.crm_metrics m on m.customer_id = c.id
 where c.active and (current_date - m.last_visit)::numeric > 60;
